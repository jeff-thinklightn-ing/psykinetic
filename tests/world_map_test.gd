extends Node
## The world map (sim/world_map.gd): every area and the ways between them,
## and its check (one-way links and neighbours, missing spawn points, cells
## off the map or on no floor, unreachable areas), on maps made in code and
## on the levels in levels/.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

var _failures := 0


func _ready() -> void:
	World.set_process(false)
	_register_maps()

	_test_graph()
	_test_problems()
	_test_levels()

	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## A strip of [param width] floor cells, one row, with link markers on
## [param link_cells].
static func _strip(width: int, link_cells: Array[Vector2i] = []) -> Image:
	var markers := {}
	for at in link_cells:
		markers[at] = "link"
	return Level.image_from_rows([".".repeat(2 * width - 1)], markers)


## hub <-> a (links), hub -> b (one way, meant), b -> hub (link to a spawn
## point hub lacks), hub east | west east_side (neighbours, both ways),
## east_side north -> nowhere_back (not named back), lost (nothing leads
## there), a with a spawn point off the map and one on no floor.
func _register_maps() -> void:
	Level.register("wm_hub", _strip(6, [Vector2i(0, 0), Vector2i(5, 0)]), null, {
		"spawn_points": {"from_a": [1, 0]},
		"links": [{"at": [0, 0], "to_map": "wm_a", "to_spawn": "from_hub"},
			{"at": [5, 0], "to_map": "wm_b", "to_spawn": "", "one_way": true}],
		"neighbours": {"east": "wm_east"}})
	var a_image := _strip(4, [Vector2i(3, 0)])
	a_image.set_pixel(4, 0, Color(0, 0, 0, 0))  # Cell (2, 0) is void.
	Level.register("wm_a", a_image, null, {
		"spawn_points": {"from_hub": [2, 0], "far": [40, 0]},
		"links": [{"at": [3, 0], "to_map": "wm_hub", "to_spawn": "from_a"}]})
	Level.register("wm_b", _strip(3, [Vector2i(2, 0)]), null, {
		"links": [{"at": [2, 0], "to_map": "wm_hub", "to_spawn": "nope"}]})
	Level.register("wm_east", _strip(3), null, {"neighbours": {"west": "wm_hub", "north": "wm_up"}})
	Level.register("wm_up", _strip(3), null, {})
	Level.register("wm_lost", _strip(3), null, {})


func _world() -> WorldMap:
	var names: Array[String] = ["wm_hub", "wm_a", "wm_b", "wm_east", "wm_up", "wm_lost"]
	return WorldMap.build(names)


func _test_graph() -> void:
	print("graph")
	var world_map := _world()
	_check(world_map.areas.size() == 6, "every area is read (%s)" % [world_map.areas.keys()])
	_check(world_map.areas["wm_hub"]["size"] == Vector2i(6, 1), "an area knows its size in cells")
	var out := world_map.ways_from("wm_hub")
	_check(out.size() == 3, "the hub has three ways out: two links and a neighbour (%d)" % out.size())
	var edge := out.filter(func(way: Dictionary) -> bool: return way["kind"] == "edge")
	_check(edge.size() == 1 and edge[0]["side"] == "east" and edge[0]["to"] == "wm_east", "the neighbour is an edge way east to wm_east")
	var link := out.filter(func(way: Dictionary) -> bool: return way["to"] == "wm_a")
	_check(link.size() == 1 and link[0]["at"] == Vector2i(0, 0) and link[0]["to_spawn"] == "from_hub", "a link way keeps its cell and spawn point")
	_check(world_map.ways_into("wm_hub").size() == 3, "three ways lead into the hub (a, b, east)")
	var expected: Array[String] = ["wm_hub", "wm_a", "wm_b", "wm_east", "wm_up"]
	_check(world_map.reachable("wm_hub") == expected,
		"reachable from the hub, nearest first, never lost (%s)" % [world_map.reachable("wm_hub")])
	_check("wm_up" not in world_map.reachable("wm_hub", true), "wm_up leads nowhere back")


func _test_problems() -> void:
	print("problems")
	var problems := _world().problems("wm_hub")
	for problem in problems:
		print("    " + problem)
	var has := func(area: String, words: String) -> bool:
		return problems.any(func(problem: String) -> bool: return problem.begins_with(area + ":") and words in problem)
	_check(not has.call("wm_hub", "the link at (5, 0)"), "a one-way link that says so is not flagged")
	_check(has.call("wm_b", "spawn point nope"), "a link to a spawn point the area lacks is flagged")
	_check(has.call("wm_east", "north neighbour is wm_up, but wm_up's south neighbour is not wm_east"), "a neighbour not named back is flagged")
	_check(not has.call("wm_hub", "east neighbour"), "a neighbour named back is not flagged")
	_check(has.call("wm_a", "spawn point far is off the 4 x 1 map"), "a spawn point off the map is flagged (through moved_config)")
	_check(has.call("wm_a", "spawn point from_hub at (2, 0) is on no floor"), "a spawn point on void is flagged")
	_check(has.call("wm_lost", "cannot be reached from wm_hub"), "an area nothing leads to is flagged")
	_check(has.call("wm_up", "has no way back to wm_hub"), "an area with no way back is flagged")
	_check(not has.call("wm_a", "no way back"), "a link with a link back is not flagged")
	Level.register("wm_dead", _strip(2, [Vector2i(1, 0)]), null, {"links": [{"at": [1, 0], "to_map": "wm_hub"}]})
	var names: Array[String] = ["wm_hub", "wm_dead", "wm_ghost"]
	var more := WorldMap.build(names).problems("wm_hub")
	_check(more.any(func(problem: String) -> bool: return problem.begins_with("wm_dead:") and "with no way back" in problem),
		"a link with no way back that does not say one_way is flagged")
	Level.register("wm_ghost_link", _strip(2, [Vector2i(1, 0)]), null, {"links": [{"at": [1, 0], "to_map": "wm_ghost"}]})
	names = ["wm_ghost_link"]
	more = WorldMap.build(names).problems("wm_ghost_link")
	_check(more.any(func(problem: String) -> bool: return "goes to wm_ghost, which is no level" in problem), "a link to no level is flagged")


func _test_levels() -> void:
	print("levels/")
	var names := Level.names()
	_check("test_room" in names and "castle" in names and "prefabs" not in names and "wm_hub" not in names,
		"Level.names() lists the level folders, not prefabs or levels made in code (%s)" % [names])
	var world_map := WorldMap.build()
	var problems := world_map.problems()
	for problem in problems:
		print("    " + problem)
	_check(problems.is_empty(), "the levels connect with no problems")
	_check(world_map.reachable(Level.DEFAULT_MAP).size() == names.size(), "every level is reachable from %s" % Level.DEFAULT_MAP)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
