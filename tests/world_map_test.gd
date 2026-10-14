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
	_test_crossing()
	_test_levels()
	_test_join()
	_test_routes()
	_test_level_routes()
	await _test_view()

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


func _test_crossing() -> void:
	print("crossing")
	var world_map := _world()
	var east := world_map.crossing("wm_hub", Vector2i(5, 0), Vector2i(1, 0))
	_check(east == {"to": "wm_east", "side": "east", "at": Vector2i(0, 0)}, "off the hub's east edge to wm_east's west edge, same row (%s)" % [east])
	var back := world_map.crossing("wm_east", Vector2i(0, 0), Vector2i(-1, 0))
	_check(back == {"to": "wm_hub", "side": "west", "at": Vector2i(5, 0)}, "and back to the hub's east edge (%s)" % [back])
	_check(world_map.crossing("wm_hub", Vector2i(4, 0), Vector2i(1, 0)).is_empty(), "a step that stays on the map crosses nothing")
	_check(world_map.crossing("wm_hub", Vector2i(0, 0), Vector2i(-1, 0)).is_empty(), "an edge with no neighbour crosses nothing")
	var up := world_map.crossing("wm_east", Vector2i(1, 0), Vector2i(0, -1))
	_check(up == {"to": "wm_up", "side": "north", "at": Vector2i(1, 0)}, "north lands on the neighbour's last row, even one not named back (%s)" % [up])
	Level.register("wm_nowhere", _strip(2), null, {"neighbours": {"east": "wm_ghost"}})
	var names: Array[String] = ["wm_nowhere"]
	_check(WorldMap.build(names).crossing("wm_nowhere", Vector2i(1, 0), Vector2i(1, 0)).is_empty(), "a neighbour that is no level here crosses nothing")
	_check(WorldMap.side_off(Vector2i(4, 3), Vector2i(4, 3)) == "east" and WorldMap.side_off(Vector2i(4, 3), Vector2i(1, -1)) == "north"
		and WorldMap.side_off(Vector2i(4, 3), Vector2i(3, 2)) == "", "side_off: past a corner is east or west; on the map is none")
	_check(WorldMap.arrival("south", Vector2i(9, 3), Vector2i(5, 5)) == Vector2i(4, 0)
		and WorldMap.arrival("north", Vector2i(2, -1), Vector2i(5, 5)) == Vector2i(2, 4),
		"arrival: south lands on row 0, north on the last row, kept on a narrower map")


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


func _test_join() -> void:
	print("join and unjoin (MapDocs, no screen)")
	var a := MapDoc.open("user://wm_join_a/", Vector2i(4, 4))
	var b := MapDoc.open("user://wm_join_b/", Vector2i(4, 4))
	b.config["neighbours"] = {"south": "elsewhere"}
	var before := WorldMap.join(a, "east", b)
	_check(a.config["neighbours"] == {"east": "wm_join_b"} and b.config["neighbours"] == {"south": "elsewhere", "west": "wm_join_a"},
		"join sets both sides (%s, %s)" % [a.config.get("neighbours"), b.config.get("neighbours")])
	_check(a.config_dirty and b.config_dirty, "and marks both level.json as changed")
	_check(before == {"a": {}, "b": {"south": "elsewhere"}}, "and returns what was there (%s)" % [before])
	WorldMap.unjoin(a, "east", b)
	_check(not a.config.has("neighbours") and b.config["neighbours"] == {"south": "elsewhere"}, "unjoin takes both away, the rest kept")
	WorldMap.put_neighbours(b, before["b"])
	_check(b.config["neighbours"] == {"south": "elsewhere"}, "put_neighbours puts back what join returned")


## The node map on the real levels, edited in memory and never saved.
func _test_view() -> void:
	print("the world map view (not saved)")
	var view: WorldMapView = preload("res://editor/world_map_view.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	var boxes := view.graph.get_children().filter(func(child: Node) -> bool: return child is GraphNode)
	_check(boxes.size() == Level.names().size(), "a box per level (%d)" % boxes.size())
	_check(view.graph.get_connection_list().size() == view.world_map.ways.size(), "a wire per way (%d)" % view.graph.get_connection_list().size())
	var to_room := view.graph.get_connection_list().filter(func(wire: Dictionary) -> bool:
		return wire["from_node"] == &"castle" and wire["to_node"] == &"test_room")
	_check(to_room.size() == 1 and view._ports["castle"]["right"][to_room[0]["from_port"]] == Vector2i(27, 12)
		and view._ports["test_room"]["left"][to_room[0]["to_port"]] == "in", "the castle's link at (27, 12) is wired to the test room's in")
	view.join("castle", "west", "sample")
	_check(view.world_map.areas["castle"]["neighbours"] == {"west": "sample"} and view.world_map.areas["sample"]["neighbours"] == {"east": "castle"},
		"joining the castle's west to the sample makes them neighbours both ways, in the graph at once")
	_check(view.unsaved() and view.world_map.ways.size() == view.graph.get_connection_list().size(), "unsaved, and the wires follow")
	view.unjoin("castle", "west", "sample")
	_check(view.world_map.areas["sample"]["neighbours"].is_empty(), "unjoining takes it away again")
	view.set_link("castle", Vector2i(27, 12), "sample", view.default_spawn("castle", "sample"))
	var problems := view.world_map.problems()
	_check(problems.any(func(problem: String) -> bool: return problem.begins_with("castle:") and "sample" in problem and "no way back" in problem),
		"retargeting the castle's link to the sample shows its problems at once (%s)" % [problems])
	view.remove_link("castle", Vector2i(27, 12))
	_check(view.world_map.problems().any(func(problem: String) -> bool: return "(27, 12) goes nowhere" in problem),
		"taking the link out leaves its marker going nowhere, and says so")
	_check(FileAccess.get_file_as_string("res://levels/castle/level.json").contains("\"to_map\": \"test_room\""), "nothing was saved")
	view.queue_free()


## r_room (5 x 5, a wall between columns 1 and 2 on rows 0-3) links from
## (4, 0), one way, to r_field's gate; r_field (4 x 3) has r_east (3 x 3)
## east of it, both ways.
func _register_route_maps() -> void:
	var rows: Array[String] = []
	for y in 9:
		var row := ".".repeat(9) if y % 2 == 0 else ".".repeat(9)
		if y % 2 == 0 and y <= 6:
			row = row.substr(0, 3) + "#" + row.substr(4)
		rows.append(row)
	Level.register("r_room", Level.image_from_rows(rows, {Vector2i(0, 0): "start", Vector2i(4, 0): "link"}), null,
		{"links": [{"at": [4, 0], "to_map": "r_field", "to_spawn": "gate", "one_way": true}]})
	Level.register("r_field", _block(4, 3), null, {"spawn_points": {"gate": [0, 1]}, "neighbours": {"east": "r_east"}})
	Level.register("r_east", _block(3, 3), null, {"neighbours": {"west": "r_field"}})


## A [param width] x [param height] block of floor.
static func _block(width: int, height: int) -> Image:
	var rows: Array[String] = []
	for y in 2 * height - 1:
		rows.append(".".repeat(2 * width - 1))
	return Level.image_from_rows(rows)


func _test_routes() -> void:
	print("routes")
	_register_route_maps()
	var names: Array[String] = ["r_room", "r_field", "r_east"]
	var world_map := WorldMap.build(names)
	var routes := world_map.routes()
	_check(routes.gaps.is_empty(), "every way has its portals (%s)" % [routes.gaps])
	var around := routes.steps_from("r_room", Vector2i(0, 0), [Vector2i(4, 0)] as Array[Vector2i])
	_check(around.get(Vector2i(4, 0), -1.0) == 10.5, "the walk round the wall is 10.5 steps, not the 4 of a straight line (%s)" % [around])
	var same := routes.route("r_room", Vector2i(0, 0), "r_room", Vector2i(4, 0))
	_check(same.size() == 1 and same[0]["steps"] == 10.5 and same[0]["way"].is_empty(), "a route inside one area is one leg (%s)" % [same])
	var legs := routes.route("r_room", Vector2i(0, 0), "r_east", Vector2i(1, 1))
	var areas := legs.map(func(leg: Dictionary) -> String: return leg["area"])
	_check(areas == ["r_room", "r_field", "r_east"], "r_room to r_east goes by r_field (%s)" % [areas])
	if legs.size() == 3:
		_check(legs[0]["to"] == Vector2i(4, 0) and legs[0]["steps"] == 10.5 and legs[0]["way"]["kind"] == "link", "out of r_room by its link, round the wall")
		_check(legs[1]["from"] == Vector2i(0, 1) and legs[1]["to"] == Vector2i(3, 1) and legs[1]["steps"] == 3.0 and legs[1]["way"]["side"] == "east",
			"across r_field from its gate to the middle of its east edge (%s)" % [legs[1]])
		_check(legs[2]["from"] == Vector2i(0, 1) and legs[2]["to"] == Vector2i(1, 1) and legs[2]["steps"] == 1.0, "and into r_east at the matching cell (%s)" % [legs[2]])
	_check(routes.route("r_field", Vector2i(0, 1), "r_room", Vector2i(0, 0)).is_empty(), "no route back over a one-way link")
	var back := routes.route("r_east", Vector2i(1, 1), "r_field", Vector2i(0, 1))
	_check(back.size() == 2 and back[0]["way"]["side"] == "west", "but back west across the edge (%s)" % [back])
	routes.blocked = func(way: Dictionary) -> bool: return way["kind"] == "edge"
	_check(routes.route("r_room", Vector2i(0, 0), "r_east", Vector2i(1, 1)).is_empty(), "a blocked way closes the route")
	routes.blocked = Callable()
	routes.extra_cost = func(_way: Dictionary) -> float: return 5.0
	_check(routes.route("r_room", Vector2i(0, 0), "r_east", Vector2i(1, 1)).size() == 3, "an extra cost slows a way without closing it")
	_check(routes.route("r_room", Vector2i(0, 0), "nowhere", Vector2i.ZERO).is_empty(), "no route to an area that is not there")


func _test_level_routes() -> void:
	print("routes on levels/")
	var started := Time.get_ticks_usec()
	var world_map := WorldMap.build()
	var built := Time.get_ticks_usec()
	var routes := world_map.routes()
	var routed := Time.get_ticks_usec()
	print("    WorldMap.build %.0f ms; routes %.0f ms (in-area lengths: %s)" % [(built - started) / 1000.0, (routed - built) / 1000.0,
		", ".join(routes.build_ms.keys().map(func(area: String) -> String: return "%s %.0f ms" % [area, routes.build_ms[area]]))])
	_check(routes.gaps.is_empty(), "every way on the levels has its portals (%s)" % [routes.gaps])
	# The worst a pair of portals can cost: a walk that floods the whole area.
	for area_name: String in world_map.areas:
		var area: Dictionary = world_map.areas[area_name]
		var flood := Time.get_ticks_usec()
		routes.steps_from(area_name, area["starts"][0], [Vector2i(-1, -1)] as Array[Vector2i])
		print("    flooding %s (%d floor cells) from its start: %.0f ms" % [area_name, area["floor"].size(), (Time.get_ticks_usec() - flood) / 1000.0])
	var room: Dictionary = world_map.areas["test_room"]
	var wilds: Dictionary = world_map.areas["wilds"]
	var query := Time.get_ticks_usec()
	var legs := routes.route("test_room", room["starts"][0], "wilds", wilds["spawn_points"]["from_castle"])
	print("    test_room to wilds: %.0f ms, %s" % [(Time.get_ticks_usec() - query) / 1000.0,
		" / ".join(legs.map(func(leg: Dictionary) -> String: return "%s %s->%s %.1f" % [leg["area"], leg["from"], leg["to"], leg["steps"]]))])
	_check(legs.map(func(leg: Dictionary) -> String: return leg["area"]) == ["test_room", "castle", "wilds"],
		"the test room's start to the wilds goes through the castle")


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
