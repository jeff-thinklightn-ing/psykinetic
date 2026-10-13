class_name Fields
extends RefCounted
## Heat and light per cell, from their sources: fire cells, torches, and
## anything that carries a light or a heat of its own (GridEntity.emit_light,
## emit_heat: the lantern every player and companion carries), and
## lanterns hung in a level (its lantern markers). Owned by
## World, on every peer: a client works it out from the same map and doors.
##
## A source reaches the cells within its reach that it can see
## (World.has_clear_line: walls and closed doors stop it, bodies do not). Heat falls off
## by HEAT_FALLOFF a pace and adds up, so a cell ringed by fire is hotter
## than one beside a single flame; World burns a creature standing where it
## reaches World.HEAT_BURN. Light falls off linearly to nothing past its
## reach, adds to the level's ambient light (level.json "ambient", 0..1,
## default 1: fully lit) and is capped at 1.
##
## Fixed sources (fire, torches) are worked out once and again only when
## the map or a door changes (World.fields_changed); carried ones are added
## at each look, so they are always where their bearer is. Each fixed
## source's share is kept (_parts): a door that opens or shuts works out
## again only the sources that reach it (mark_dirty_near), and the totals
## are added up from the shares in the same order as ever, so they come out
## the same to the last bit (the whole castle took 16 ms a door).

## What each fixed source gives at its own cell, and how far it reaches.
const FIRE := {"heat": 10.0, "light": 0.8, "reach": 4}
const TORCH := {"heat": 2.0, "light": 1.0, "reach": 5}
const LANTERN := {"heat": 0.0, "light": 0.9, "reach": 4}
## A carried light reaches this far.
const CARRIED_REACH := 4
## Heat kept per pace of distance.
const HEAT_FALLOFF := 0.35

var ambient := 1.0
var _fire: Array[Vector2i] = []
var _torches: Array[Vector2i] = []
var _lanterns: Array[Vector2i] = []
var _heat: Dictionary[Vector2i, float] = {}
var _light: Dictionary[Vector2i, float] = {}
var _dirty := true
## Each fixed source's share, fire then torches then lanterns, each in
## order: {"heat": {cell: amount}, "light": {cell: amount}}, or null to be
## worked out again. Empty: all of them.
var _parts: Array = []


func load(terrain: Dictionary) -> void:
	_fire.assign(terrain.get("fire", []))
	_torches.assign(terrain.get("torches", []))
	_lanterns.assign(terrain.get("lanterns", []))
	ambient = clampf(float(terrain.get("ambient", 1.0)), 0.0, 1.0)
	mark_dirty()


func mark_dirty() -> void:
	_parts.clear()
	_dirty = true


## Something changed at [param cells] (a door between two): only the
## sources that reach that far (their reach, and a pace) are worked out
## again; any line of theirs that crosses it stays within that.
func mark_dirty_near(cells: Array[Vector2i]) -> void:
	_dirty = true
	if _parts.is_empty():
		return
	var sources := _sources()
	for i in sources.size():
		var source: Vector2i = sources[i][0]
		var reach: int = sources[i][1]["reach"]
		for cell in cells:
			if maxi(absi(cell.x - source.x), absi(cell.y - source.y)) <= reach + 1:
				_parts[i] = null
				break


## Every fixed source in the order its share is added: [cell, spec].
func _sources() -> Array:
	var sources := []
	for cell in _fire:
		sources.append([cell, FIRE])
	for cell in _torches:
		sources.append([cell, TORCH])
	for cell in _lanterns:
		sources.append([cell, LANTERN])
	return sources


## Heat at [param cell]: fixed sources and carried ones.
func heat_at(world: Node, cell: Vector2i) -> float:
	_refresh(world)
	var heat: float = _heat.get(cell, 0.0)
	for entity: GridEntity in world.get_entities():
		if entity.emit_heat > 0.0 and entity.spawned:
			heat += _reaching(world, entity.tile, cell, CARRIED_REACH, entity.emit_heat, true)
	return heat


## The heat at [param cell] from the map's own sources alone (fire,
## torches, lanterns set in it), without what creatures carry: heat_at when
## nobody carries any.
func map_heat_at(world: Node, cell: Vector2i) -> float:
	_refresh(world)
	return _heat.get(cell, 0.0)


## Whether anything in [param world] carries heat now (see heat_at).
func any_carried_heat(world: Node) -> bool:
	for entity: GridEntity in world.get_entities():
		if entity.emit_heat > 0.0 and entity.spawned:
			return true
	return false


## Light at [param cell], 0 (dark) to 1; [param carried]: with the lights
## creatures carry (the 3D view draws those itself).
func light_at(world: Node, cell: Vector2i, carried := true) -> float:
	_refresh(world)
	var light: float = ambient + _light.get(cell, 0.0)
	if carried:
		for entity: GridEntity in world.get_entities():
			if entity.emit_light > 0.0 and entity.spawned:
				light += _reaching(world, entity.tile, cell, CARRIED_REACH, entity.emit_light, false)
	return minf(light, 1.0)


## Where the heat at [param cell] comes from: the sum of the offsets to its
## sources, each weighted by what it gives here (ZERO for none, or for a
## cell that is itself a source).
func heat_from(world: Node, cell: Vector2i) -> Vector2:
	var toward := Vector2.ZERO
	for source in _fire + _torches:
		var spec: Dictionary = FIRE if source in _fire else TORCH
		toward += Vector2(source - cell) * _reaching(world, source, cell, spec["reach"], spec["heat"], true)
	return toward


## Whether any fixed source gives heat at all (World's hazard check skips
## the creatures otherwise).
func has_heat() -> bool:
	return not _fire.is_empty() or not _torches.is_empty()


func _refresh(world: Node) -> void:
	if not _dirty:
		return
	_dirty = false
	var sources := _sources()
	_parts.resize(sources.size())
	for i in sources.size():
		if _parts[i] == null:
			_parts[i] = _spread(world, sources[i][0], sources[i][1])
	_heat.clear()
	_light.clear()
	for part: Dictionary in _parts:
		var heat: Dictionary = part["heat"]
		for cell: Vector2i in heat:
			_heat[cell] = _heat.get(cell, 0.0) + heat[cell]
		var light: Dictionary = part["light"]
		for cell: Vector2i in light:
			_light[cell] = _light.get(cell, 0.0) + light[cell]


## One source's share: {"heat": {cell: amount}, "light": {cell: amount}},
## each cell's line from it traced once for both.
func _spread(world: Node, source: Vector2i, spec: Dictionary) -> Dictionary:
	var reach: int = spec["reach"]
	var heat_share: Dictionary[Vector2i, float] = {}
	var light_share: Dictionary[Vector2i, float] = {}
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var cell := source + Vector2i(dx, dy)
			var distance := Vector2(cell - source).length()
			if distance > reach + 0.5:
				continue
			if cell != source and not world.has_clear_line(source, cell):
				continue
			var heat := _given(distance, reach, spec["heat"], true)
			if heat > 0.0:
				heat_share[cell] = heat
			var light := _given(distance, reach, spec["light"], false)
			if light > 0.0:
				light_share[cell] = light
	return {"heat": heat_share, "light": light_share}


## What a source at [param source] giving [param amount] gives at
## [param cell]: heat falls off by HEAT_FALLOFF a pace, light linearly;
## nothing past [param reach] or out of the source's sight.
func _reaching(world: Node, source: Vector2i, cell: Vector2i, reach: int, amount: float, heat: bool) -> float:
	var distance := Vector2(cell - source).length()
	if distance > reach + 0.5 or amount <= 0.0:
		return 0.0
	if cell != source and not world.has_clear_line(source, cell):
		return 0.0
	return _given(distance, reach, amount, heat)


## What a source giving [param amount] gives [param distance] paces off,
## in its sight (see _reaching).
static func _given(distance: float, reach: int, amount: float, heat: bool) -> float:
	if amount <= 0.0:
		return 0.0
	if heat:
		return amount * pow(HEAT_FALLOFF, distance)
	return amount * clampf(1.0 - distance / (reach + 1.0), 0.0, 1.0)
