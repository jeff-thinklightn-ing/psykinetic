class_name WorldRichness
extends RefCounted
## How rich in game each cell of the world is, 0..1 (decision 368), for
## economy's Herds (decision 367: capacity = open cells x density x
## richness). Server only; World keeps one (World.richness).
##
## 0 on dead ground (WorldMap.is_dead: level.json "dead_ground"), out of the
## sky (an indoor level, a cell under a building's roof), and on ground a
## faction holds (Holdings.ground: anyone but the town, contested ground
## too). Elsewhere 1, thinned toward the mine: by the walking steps from the
## nearest place of kind "mine" over the world map, across its ways
## (WorldRoutes.distances_from), so a mine behind a wall or a ridge is
## further than it looks: 0 within mine_dead steps, 1 from mine_full on,
## straight between (levels/economy.json "wildlife"). No mine, no thinning.
##
## The steps are worked out once, on a WorkerThreadPool task (start(), or
## the first ask), and kept per cell; a richness asked before they are in
## waits for them. Mines are read when it is made: a world map built again
## (a level edited) wants a WorldRichness of its own.

const RULES := "res://levels/economy.json"
const DEFAULTS := {"mine_dead": 40.0, "mine_full": 400.0}
const MINE := "mine"
## The faction whose ground keeps its game (the rest's held ground has none).
const TOWN := "town"

var world_map: WorldMap
var holdings: Holdings
var rules := {}
## The mines' places: {area, cell}.
var mines: Array[Dictionary] = []
var _steps: Dictionary[String, PackedFloat32Array] = {}
var _task := -1
var _done := false
## Area name -> {cell: true} under a roof, as worked out.
var _roofed: Dictionary[String, Dictionary] = {}


func _init(map: WorldMap, with_holdings: Holdings, with_rules := {}) -> void:
	world_map = map
	holdings = with_holdings
	rules = DEFAULTS.duplicate()
	rules.merge(with_rules if not with_rules.is_empty() else _read_rules(), true)
	for id in holdings.all_places():
		var place := holdings.place(id)
		if place.get("kind") == MINE:
			mines.append({"area": place["area"], "cell": place["cell"]})


static func _read_rules() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RULES)) if FileAccess.file_exists(RULES) else null
	if parsed is Dictionary:
		var wildlife: Variant = (parsed as Dictionary).get("wildlife", {})
		return wildlife if wildlife is Dictionary else {}
	return {}


## Starts working out the steps from the mines (once).
func start() -> void:
	if _task >= 0 or _done:
		return
	if mines.is_empty():
		_done = true
		return
	var routes := world_map.routes()
	var from := mines.duplicate(true)
	_task = WorkerThreadPool.add_task(func() -> void: _steps = routes.distances_from(from), false, "world richness: steps from the mines")


## Whether the steps are in (or there are none to work out), without
## waiting: Main swaps a richness made again in only once it is (368
## amended), the old one answering meanwhile.
func is_ready() -> bool:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		finish()
	return _done


## Waits for the steps, if they are being worked out: before the server
## quits, and before the first richness.
func finish() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_done = true


## How rich in game [param cell] of [param area_name] is, 0..1. Herds'
## richness Callable.
func richness(area_name: String, cell: Vector2i) -> float:
	if not world_map.areas.has(area_name) or world_map.is_dead(area_name) or not under_sky(area_name, cell):
		return 0.0
	var held := holdings.ground(area_name, cell)
	if held != Factions.NOBODY and held != TOWN:
		return 0.0
	return thinning(area_name, cell)


## Whether [param cell] of [param area_name] is under the sky: an outdoor
## level's, not under a building's roof (as Fields has them).
func under_sky(area_name: String, cell: Vector2i) -> bool:
	if not world_map.is_outdoor(area_name):
		return false
	if not _roofed.has(area_name):
		var roofed := {}
		for building: Dictionary in world_map.areas[area_name].get("buildings", []):
			for each in Level.building_cells(building):
				roofed[each] = true
		_roofed[area_name] = roofed
	return not _roofed[area_name].has(cell)


## The mine's thinning at [param cell]: 1 with no mine or none reaching
## it, 0 within mine_dead steps of one, rising to 1 at mine_full.
func thinning(area_name: String, cell: Vector2i) -> float:
	var away := steps_from_mine(area_name, cell)
	if away < 0.0:
		return 1.0
	var dead := float(rules["mine_dead"])
	var full := maxf(float(rules["mine_full"]), dead + 1.0)
	return clampf((away - dead) / (full - dead), 0.0, 1.0)


## The walking steps from the nearest mine to [param cell] of
## [param area_name]; -1 with no mine or none reaching it.
func steps_from_mine(area_name: String, cell: Vector2i) -> float:
	start()
	finish()
	var steps: PackedFloat32Array = _steps.get(area_name, PackedFloat32Array())
	var size: Vector2i = world_map.areas[area_name]["size"] if world_map.areas.has(area_name) else Vector2i.ZERO
	if steps.is_empty() or not Rect2i(Vector2i.ZERO, size).has_point(cell):
		return -1.0
	return steps[cell.y * size.x + cell.x]
