class_name Clearing
extends RefCounted
## The forest felled and growing back (decision 591; Jeff: "forests to chop
## down, town and city growing and becoming something is one of the major
## gameplay components", "forests can regenerate too if not built over").
## Server only; World keeps one (World.clearing), made by Main at boot and
## moved on by the world tick's first slice, whether or not anyone is in a
## zone. Kept in the world snapshot ("clearing"), never in a level: the
## levels stay as made, and a cell grown back is the level's trunk again,
## leaving no trace.
##
## A tree is a trunk: a level's void cell inside its land (one beside the
## land's floor, more than EDGE cells in from the map's edge). fell takes
## trunks for a woodcut: the edge trunks within REACH of the site nearest
## the town first, each cell then a stump. A felled cell is floor of its
## stage's kind: a stump (dirt), then grass, scrub, saplings (grass); a
## stage lasts a season (Season.season_days), twice that for a cell with no
## standing trunk beside it, so a clearing closes from its edges in. Past
## saplings it is a trunk again, unless something stands or lies on it (it
## waits), or it is built over (a building's cell, a road's: never).
##
## The cells a zone has felled reach the views as terrain["clearing"]
## (cell -> stage), applied to a level's terrain as it loads (apply), and as
## the "clearing" message ({zone, cells: [[x, y, stage]]}, "trunk" for one
## grown back) when they change (changed).

## What each stage is, in order, and the floor kind it is.
const STAGES: Array[String] = ["stump", "grass", "scrub", "saplings"]
const STAGE_KINDS := {"stump": "dirt", "grass": "grass", "scrub": "grass", "saplings": "grass"}
## A cell grown back: the level's own trunk again.
const TRUNK := "trunk"
## How far round a woodcut's site trunks are taken (cells).
const REACH := 6
## How far a site steps out to the nearest standing edge when bare (cells).
const STEP_REACH := 40
## Trunks this near the map's edge are its border, never felled.
const EDGE := 4

## zone -> cell -> [stage index, the day the stage began].
var felled: Dictionary = {}
## zone -> {size, floor (cell -> true), built (cell -> true)}: the level as
## made, read once a zone.
var _base: Dictionary = {}
var _day := -1
## The day, for tests (an int); else World's steps' day.
var clock := Callable()
## Told when a zone's cells change: (zone, cells: [[x, y, stage]]).
signal changed(zone: String, cells: Array)


func _init(saved := {}) -> void:
	for zone: String in saved:
		var cells := {}
		var listed: Variant = saved[zone]
		if listed is Dictionary:
			for key: String in listed:
				var entry: Variant = listed[key]
				if entry is Array and (entry as Array).size() == 2:
					cells[Vector2i(int(key.get_slice(",", 0)), int(key.get_slice(",", 1)))] = [int(entry[0]), int(entry[1])]
		felled[zone] = cells


func to_dict() -> Dictionary:
	var out := {}
	for zone: String in felled:
		var cells := {}
		for cell: Vector2i in felled[zone]:
			cells["%d,%d" % [cell.x, cell.y]] = (felled[zone][cell] as Array).duplicate()
		if not cells.is_empty():
			out[zone] = cells
	return out


func today() -> int:
	if clock.is_valid():
		return int(clock.call())
	return World.steps / maxi(DayNight.day_steps, 1)


## [param terrain] (a level's as parsed, zone [param zone]'s) with its
## felled cells floor of their stage's kind and terrain["clearing"] (cell ->
## stage) for the views. Main applies it before World loads the terrain.
func apply(zone: String, terrain: Dictionary) -> void:
	var stages: Dictionary[Vector2i, String] = {}
	for cell: Vector2i in felled.get(zone, {}):
		var stage: String = STAGES[int(felled[zone][cell][0])]
		stages[cell] = stage
		if not cell in terrain["floor"]:
			terrain["floor"].append(cell)
		terrain["kinds"][cell] = STAGE_KINDS[stage]
	terrain["clearing"] = stages


## [param cells] ([[x, y, stage]], a "clearing" message's) laid on a
## client's [param terrain]: felled cells floor, grown ones void again.
static func apply_cells(terrain: Dictionary, cells: Array) -> void:
	var stages: Dictionary = terrain.get("clearing", {})
	for each: Array in cells:
		var cell := Vector2i(int(each[0]), int(each[1]))
		var stage := str(each[2])
		if stage == TRUNK:
			stages.erase(cell)
			terrain["floor"].erase(cell)
			terrain["kinds"].erase(cell)
		else:
			stages[cell] = stage
			if not cell in terrain["floor"]:
				terrain["floor"].append(cell)
			terrain["kinds"][cell] = STAGE_KINDS.get(stage, "grass")
	terrain["clearing"] = stages


## A zone's felled cells as a message's list ([[x, y, stage]]).
func cells_of(zone: String) -> Array:
	var out := []
	for cell: Vector2i in felled.get(zone, {}):
		out.append([cell.x, cell.y, STAGES[int(felled[zone][cell][0])]])
	return out


## A woodcut (economy's, through Towns.fell): up to [param wanted] trunks of
## zone [param zone] felled within REACH of [param site] (its woodlot's
## cell), the edge trunks nearest [param toward] (the town's store) first;
## how many. None within reach: 0 (step_site moves the lot).
func fell(zone: String, site: Vector2i, toward: Vector2i, wanted: int) -> int:
	if wanted <= 0 or not Level.exists(zone):
		return 0
	var taken := []
	for i in wanted:
		var trunk := _nearest_edge(zone, site, REACH, toward)
		if trunk == World.NO_CELL:
			break
		if not felled.has(zone):
			felled[zone] = {}
		felled[zone][trunk] = [0, today()]
		taken.append([trunk.x, trunk.y, STAGES[0]])
	if not taken.is_empty():
		changed.emit(zone, taken)
	return taken.size()


## Where a woodlot bare of trunks within REACH of [param site] steps out to:
## the floor cell beside the standing edge trunk nearest it (within
## STEP_REACH), nearest the site; World.NO_CELL if there is none.
func step_site(zone: String, site: Vector2i) -> Vector2i:
	var trunk := _nearest_edge(zone, site, STEP_REACH, site)
	if trunk == World.NO_CELL:
		return World.NO_CELL
	var base := _base_of(zone)
	var best := World.NO_CELL
	for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var beside := trunk + step
		if _is_floor(zone, base, beside) and (best == World.NO_CELL or Vector2(beside - site).length() < Vector2(best - site).length()):
			best = beside
	return best


## The world tick: on a new day, every zone's felled cells grow on.
func tick() -> void:
	var day := today()
	if day == _day:
		return
	_day = day
	daily(day)


## [param day]'s growing: each felled cell's stage on when it has lasted its
## season (twice that with no standing trunk beside it); past saplings, a
## trunk again if nothing stands or lies on it and it is not built over.
func daily(day: int) -> void:
	var stage_days := maxi(1, Season.season_days)
	for zone: String in felled.keys():
		var base := _base_of(zone)
		var grown := []
		for cell: Vector2i in (felled[zone] as Dictionary).keys():
			if base["built"].has(cell):
				continue
			var entry: Array = felled[zone][cell]
			var needed := stage_days if _beside_trunk(zone, base, cell) else stage_days * 2
			if day - int(entry[1]) < needed:
				continue
			if int(entry[0]) + 1 < STAGES.size():
				felled[zone][cell] = [int(entry[0]) + 1, day]
				grown.append([cell.x, cell.y, STAGES[int(entry[0]) + 1]])
			elif not _occupied(zone, cell):
				(felled[zone] as Dictionary).erase(cell)
				grown.append([cell.x, cell.y, TRUNK])
		if not grown.is_empty():
			changed.emit(zone, grown)


## The standing edge trunk of [param zone] within [param reach] of [param
## site] nearest [param toward]: a trunk not felled with floor (the level's,
## or felled) beside it; World.NO_CELL if none.
func _nearest_edge(zone: String, site: Vector2i, reach: int, toward: Vector2i) -> Vector2i:
	var base := _base_of(zone)
	var size: Vector2i = base["size"]
	var best := World.NO_CELL
	for y in range(site.y - reach, site.y + reach + 1):
		for x in range(site.x - reach, site.x + reach + 1):
			var cell := Vector2i(x, y)
			if x < EDGE or y < EDGE or x >= size.x - EDGE or y >= size.y - EDGE or Vector2(cell - site).length() > reach:
				continue
			if base["floor"].has(cell) or felled.get(zone, {}).has(cell) or base["built"].has(cell) or base["water"].has(cell):
				continue
			var edge := false
			for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				edge = edge or _is_floor(zone, base, cell + step)
			if edge and (best == World.NO_CELL or Vector2(cell - toward).length() < Vector2(best - toward).length()):
				best = cell
	return best


func _is_floor(zone: String, base: Dictionary, cell: Vector2i) -> bool:
	return base["floor"].has(cell) or felled.get(zone, {}).has(cell)


## Whether a standing trunk (the level's void, not felled) is beside [param cell].
func _beside_trunk(zone: String, base: Dictionary, cell: Vector2i) -> bool:
	var size: Vector2i = base["size"]
	for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var near := cell + step
		if near.x >= 0 and near.y >= 0 and near.x < size.x and near.y < size.y and not _is_floor(zone, base, near) and not base["water"].has(near):
			return true
	return false


## Whether something stands or lies on [param cell] of loaded zone [param
## zone] (a cell grown back must not shut anyone in); an unloaded zone has
## nothing on it.
func _occupied(zone: String, cell: Vector2i) -> bool:
	if not World.zones.has(zone):
		return false
	var was := World.zone
	World.enter(World.zones[zone])
	var taken := not World.is_free(cell) or not World.ground_at(cell).is_empty()
	World.enter(was)
	return taken


## The level as made, read once a zone: its size, floor, water, and what is
## built over (buildings' cells, roads' cells).
func _base_of(zone: String) -> Dictionary:
	if _base.has(zone):
		return _base[zone]
	var level := Level.load_level(zone)
	var base := {"size": Vector2i.ZERO, "floor": {}, "water": {}, "built": {}}
	if not level.is_empty():
		var terrain: Dictionary = level["terrain"]
		base["size"] = level["size"]
		for cell: Vector2i in terrain["floor"]:
			base["floor"][cell] = true
		for key in ["water", "fords", "bridged"]:
			for cell: Vector2i in terrain.get(key, []):
				base["water"][cell] = true
		for building: Dictionary in level["buildings"]:
			for cell in Level.building_cells(building):
				base["built"][cell] = true
		for road: Dictionary in terrain.get("roads", []):
			for cell: Vector2i in Curves.cells(road["curve"], false):
				base["built"][cell] = true
	_base[zone] = base
	return base
