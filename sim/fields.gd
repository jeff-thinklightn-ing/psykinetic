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
## again only the sources that reach it (mark_dirty_near), and only the
## cells those reach are added up again, from the shares in the same order
## as ever, so they come out the same to the last bit (the whole castle
## took 16 ms a door, and adding up the whole map again made a door's cost
## grow with the map). And what a source's line to each cell owes to doors
## is worked out once (_lines, World.line_doors), so a source done again
## for a door only asks which of those doors are open.

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
## The sources whose shares were let go since the last refresh (indices
## into _parts).
var _redo: Dictionary[int, bool] = {}
## For each cell a source can reach, the sources that can, in order
## (indices into _parts): who to add up again when one changes.
var _covering: Dictionary[Vector2i, PackedInt32Array] = {}
## The cells added up again since the last take_touched(), or all of them
## (a whole recompute): what a view shading the floor has to shade again.
var _touched: Dictionary[Vector2i, bool] = {}
var _touched_all := true
## _sources(), kept till the map changes.
var _source_list: Array = []
## For each fixed source (indices into _parts), or null till worked out:
## {"cells": the cells within its reach whose line the terrain does not
## stop, in the order _spread looks at them, "doors": for each, what its
## line owes to doors (World.line_doors)}.
var _lines: Array = []


func load(terrain: Dictionary) -> void:
	_fire.assign(terrain.get("fire", []))
	_torches.assign(terrain.get("torches", []))
	_lanterns.assign(terrain.get("lanterns", []))
	ambient = clampf(float(terrain.get("ambient", 1.0)), 0.0, 1.0)
	_source_list = []
	mark_dirty()


func mark_dirty() -> void:
	_parts.clear()
	_redo.clear()
	_lines.clear()
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
				_redo[i] = true
				break


## Every fixed source in the order its share is added: [cell, spec].
## Not a copy: read it, do not change it.
func _sources() -> Array:
	if not _source_list.is_empty():
		return _source_list
	var sources := []
	for cell in _fire:
		sources.append([cell, FIRE])
	for cell in _torches:
		sources.append([cell, TORCH])
	for cell in _lanterns:
		sources.append([cell, LANTERN])
	_source_list = sources
	return sources


## The cells whose fixed heat or light may have changed since the last
## take: {"all": true} after a whole recompute, else {"all": false,
## "cells": [...]}; worked out first if due. Forgets them.
func take_touched(world: Node) -> Dictionary:
	_refresh(world)
	var taken := {"all": _touched_all, "cells": _touched.keys()}
	_touched_all = false
	_touched.clear()
	return taken


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
	if not _parts.is_empty():
		_refresh_redone(world, sources)
		return
	_parts.resize(sources.size())
	for i in sources.size():
		_parts[i] = _spread(world, i, sources[i][0], sources[i][1])
	_touched_all = true
	_touched.clear()
	_covering.clear()
	for i in sources.size():
		for cell in _reachable(sources[i][0], sources[i][1]["reach"]):
			if not _covering.has(cell):
				_covering[cell] = PackedInt32Array()
			_covering[cell].append(i)
	_heat.clear()
	_light.clear()
	for part: Dictionary in _parts:
		var heat: Dictionary = part["heat"]
		for cell: Vector2i in heat:
			_heat[cell] = _heat.get(cell, 0.0) + heat[cell]
		var light: Dictionary = part["light"]
		for cell: Vector2i in light:
			_light[cell] = _light.get(cell, 0.0) + light[cell]


## The sources let go since the last refresh worked out again, and the
## cells they can reach added up again from every share that reaches them,
## in order, as the whole sum adds them.
func _refresh_redone(world: Node, sources: Array) -> void:
	var cells: Dictionary[Vector2i, bool] = {}
	for i: int in _redo:
		_parts[i] = _spread(world, i, sources[i][0], sources[i][1])
		for cell in _reachable(sources[i][0], sources[i][1]["reach"]):
			cells[cell] = true
	_redo.clear()
	if not _touched_all:
		_touched.merge(cells)
	for cell: Vector2i in cells:
		var heat := 0.0
		var light := 0.0
		var heated := false
		var lit := false
		for i in _covering[cell]:
			var part: Dictionary = _parts[i]
			var heat_share: Dictionary = part["heat"]
			if heat_share.has(cell):
				heat += heat_share[cell]
				heated = true
			var light_share: Dictionary = part["light"]
			if light_share.has(cell):
				light += light_share[cell]
				lit = true
		if heated:
			_heat[cell] = heat
		else:
			_heat.erase(cell)
		if lit:
			_light[cell] = light
		else:
			_light.erase(cell)


## The cells within [param reach] of [param source], as _spread looks at
## them (whether it sees them or not).
static func _reachable(source: Vector2i, reach: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var offset := Vector2i(dx, dy)
			if Vector2(offset).length() <= reach + 0.5:
				cells.append(source + offset)
	return cells


## One source's share (the [param index]th): {"heat": {cell: amount},
## "light": {cell: amount}}, from the cells it can see: those whose line
## the terrain lets through and whose doors on the way are open.
func _spread(world: Node, index: int, source: Vector2i, spec: Dictionary) -> Dictionary:
	var reach: int = spec["reach"]
	var heat_share: Dictionary[Vector2i, float] = {}
	var light_share: Dictionary[Vector2i, float] = {}
	var lines: Dictionary = _lines_of(world, index, source, reach)
	var cells: Array[Vector2i] = lines["cells"]
	var doors: Array = lines["doors"]
	for k in cells.size():
		var cell := cells[k]
		var owed: Variant = doors[k]
		if owed is int:
			if not world.has_clear_line(source, cell):
				continue
		elif not _all_open(world, owed):
			continue
		var distance := Vector2(cell - source).length()
		var heat := _given(distance, reach, spec["heat"], true)
		if heat > 0.0:
			heat_share[cell] = heat
		var light := _given(distance, reach, spec["light"], false)
		if light > 0.0:
			light_share[cell] = light
	return {"heat": heat_share, "light": light_share}


## The [param index]th source's lines (_lines), worked out the first time.
func _lines_of(world: Node, index: int, source: Vector2i, reach: int) -> Dictionary:
	if _lines.size() <= index:
		_lines.resize(_sources().size())
	if _lines[index] != null:
		return _lines[index]
	var cells: Array[Vector2i] = []
	var doors := []
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var cell := source + Vector2i(dx, dy)
			if Vector2(cell - source).length() > reach + 0.5:
				continue
			var owed: Variant = [] if cell == source else world.line_doors(source, cell)
			if owed == null:
				continue
			cells.append(cell)
			doors.append(owed)
	_lines[index] = {"cells": cells, "doors": doors}
	return _lines[index]


## Whether every door at [param keys] is there and open (a door that has
## not arrived counts as shut, as World.edge_blocks_sight has it).
static func _all_open(world: Node, keys: Array) -> bool:
	for key: Vector3i in keys:
		var door: Door = world.door_on(key)
		if door == null or not door.is_open():
			return false
	return true


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
