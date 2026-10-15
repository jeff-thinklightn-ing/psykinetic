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
	_test_start()
	_test_ways_out()
	_test_crossing()
	_test_levels()
	_test_join()
	_test_places()
	_test_holdings()
	_test_saved_holdings()
	_test_routes()
	_test_level_routes()
	_test_territory_routes()
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


func _test_start() -> void:
	print("the start zone (decision 300)")
	var settings: String = preload("res://tests/test_ports.gd").scratch_path("world_map.json")
	WorldMap.settings_path = settings
	DirAccess.remove_absolute(settings)
	_check(WorldMap.start_zone() == "" and WorldMap.root() == Level.DEFAULT_MAP, "no world_map.json: no start zone, measured from the default map")
	Level.register("wm_town", Level.image_from_rows(["....."], {Vector2i(1, 0): "start"}), null, {})
	var names: Array[String] = ["wm_town", "wm_lost"]
	var write := func(zone: String) -> void:
		FileAccess.open(settings, FileAccess.WRITE).store_string(JSON.stringify({"start": {"zone": zone}}))
	write.call("wm_town")
	var problems := WorldMap.build(names).problems()
	_check(WorldMap.start_zone() == "wm_town" and WorldMap.root() == "wm_town", "world_map.json names the start zone: %s" % WorldMap.start_zone())
	_check(problems.has("wm_lost: cannot be reached from wm_town") and not problems.any(func(p: String) -> bool: return "start zone" in p),
		"the world is measured from it, and one with starts is not flagged (%s)" % [problems])
	write.call("wm_lost")
	problems = WorldMap.build(names).problems()
	_check(problems.has("wm_lost: it is the start zone (world_map.json) but has no starts"), "a start zone with no starts is flagged (%s)" % [problems])
	write.call("wm_nowhere")
	problems = WorldMap.build(names).problems()
	_check(problems.has("world_map.json: the start zone wm_nowhere is not a level"), "a start zone that is no level is flagged")
	WorldMap.settings_path = "res://levels/world_map.json"
	DirAccess.remove_absolute(settings)


func _test_ways_out() -> void:
	print("ways out, and where their targets lie (decision 325)")
	var world := _world()
	var out := world.ways_out("wm_hub", 3)
	var edge: Dictionary = out.filter(func(way: Dictionary) -> bool: return way["kind"] == "edge")[0]
	var to_ours: Transform2D = edge["to_ours"]
	_check(edge["to_map"] == "wm_east" and edge["side"] == "east" and edge["out"] == Vector2i(1, 0) and not edge["one_way"],
		"a neighbour: its side, out, and a way back (%s)" % [edge])
	# Where a step off the east edge arrives, put back in ours, is the cell stepped into.
	var stepped := Vector2i(6, 0)
	var arrives := WorldMap.arrival("east", stepped, world.areas["wm_east"]["size"])
	_check(Vector2i(to_ours * Vector2(arrives)) == stepped, "its cells lie where arrival() puts a crossing (%s -> %s)" % [arrives, to_ours * Vector2(arrives)])
	var link: Dictionary = out.filter(func(way: Dictionary) -> bool: return way["to_map"] == "wm_a")[0]
	var placed := Vector2i((link["to_ours"] as Transform2D) * Vector2(link["to_cell"]))
	_check(link["from_cell"] == Vector2i(0, 0) and link["to_cell"] == Vector2i(2, 0) and link["out"] == Vector2i(0, -1),
		"a link: our marker, where it arrives, out by the edge that arrival is nearest (%s)" % [link])
	_check(placed == Vector2i(0, -4), "its arrival lies across from our marker, 3 cells past our land (%s)" % placed)
	var meant: Dictionary = out.filter(func(way: Dictionary) -> bool: return way["to_map"] == "wm_b")[0]
	_check(meant["one_way"], "a one-way link says so")
	var real := WorldMap.build(["wilds", "castle"])
	var to_castle: Array = real.ways_out("wilds", 3).filter(func(way: Dictionary) -> bool: return way["to_map"] == "castle")
	_check(to_castle.size() == 1 and to_castle[0]["out"] == Vector2i(0, -1), "the wilds' way to the castle points north")
	if to_castle.size() == 1:
		var spawn := Vector2i((to_castle[0]["to_ours"] as Transform2D) * Vector2(to_castle[0]["to_cell"]))
		var marker: Vector2i = to_castle[0]["from_cell"]
		var land := marker
		var floor_cells: Dictionary = real.areas["wilds"]["floor"]
		while floor_cells.has(land + Vector2i(0, -1)):
			land += Vector2i(0, -1)
		var castle_size: Vector2i = real.areas["castle"]["size"]
		var bottom := Vector2i((to_castle[0]["to_ours"] as Transform2D) * Vector2(0, castle_size.y - 1)).y
		_check(spawn.x == marker.x and bottom == land.y - 4,
			"the castle lies 3 cells past where the wilds' land ends going north from the link, its arrival across from it (land ends at row %d, its south row at %d, arrival %s)" % [land.y, bottom, spawn])


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


## h_land: 20 x 10 cells of floor, (5, 8) void; its places: a goblin camp
## (15, 5) r 3 worth 2, a town farm (3, 5) r 2, a ford nobody holds (9, 5)
## r 2, a town well (12, 5) r 1 inside the camp's ground; h_bad: places off
## the map, on void, and held by elves.
func _register_place_maps() -> void:
	var land := _block(20, 10)
	land.set_pixel(10, 16, Color(0, 0, 0, 0))
	Level.register("h_land", land, null, {"places": {
		"camp": {"at": [15, 5], "kind": "camp", "radius": 3, "worth": 2, "holder": "goblins", "name": "the goblin camp"},
		"farm": {"at": [3, 5], "kind": "farm", "radius": 2, "holder": "town"},
		"ford": {"at": [9, 5], "kind": "gate", "radius": 2},
		"well": {"at": [12, 5], "kind": "other", "radius": 1, "holder": "town"}}})
	Level.register("h_bad", land, null, {"places": {
		"far": {"at": [40, 5]}, "pit": {"at": [5, 8], "holder": "goblins"}, "glade": {"at": [2, 2], "holder": "elves"},
		"odd": {"at": [1, 1], "kind": "tower", "radius": 0}}})


func _test_places() -> void:
	print("places")
	_register_place_maps()
	var factions := Factions.read()
	_check(factions.names() == _strings(["goblins", "town"]) and factions.of_kind("brute") == "goblins" and factions.of_kind("wolf") == "nobody",
		"levels/factions.json: the goblins and the town; brutes act for the goblins (%s)" % [factions.names()])
	_check(factions.hostile("goblins", "town") and not factions.hostile("town", "town") and factions.has("nobody") and not factions.has("elves"),
		"goblins and town are hostile; nobody can hold, elves cannot")
	var names: Array[String] = ["h_land", "h_bad"]
	var world_map := WorldMap.build(names)
	var camp: Dictionary = world_map.areas["h_land"]["places"]["camp"]
	_check(camp == {"key": "camp", "cell": Vector2i(15, 5), "name": "the goblin camp", "kind": "camp", "radius": 3, "worth": 2, "holder": "goblins"},
		"a place as level.json gives it (%s)" % [camp])
	var ford: Dictionary = world_map.areas["h_land"]["places"]["ford"]
	_check(ford["holder"] == "nobody" and ford["worth"] == 1 and ford["name"] == "Ford", "unsaid: held by nobody, worth 1, named from its key")
	var problems := world_map.problems("h_land", factions)
	var has := func(words: String) -> bool: return problems.any(func(problem: String) -> bool: return words in problem)
	_check(has.call("place far is off the 20 x 10 map"), "a place off the map is a problem (moved_config moves places)")
	_check(has.call("the place pit at (5, 8) is on no floor"), "a place on void is a problem")
	_check(has.call("the place glade is held by elves, which is no faction"), "a holder that is no faction is a problem")
	_check(has.call("the place odd is a tower") and has.call("the place odd has a radius under 1"), "a kind there is not, and a radius under 1, are warned of")
	_check(not problems.any(func(problem: String) -> bool: return problem.begins_with("h_land:") and "place" in problem), "h_land's places are fine")
	var moved := LevelMap.moved_config({"places": {"a": {"at": [1, 1]}, "b": {"at": [9, 9]}}},
		func(at: Vector2i) -> Variant: return at + Vector2i(2, 0) if at.x < 5 else null)
	_check(moved["places"] == {"a": {"at": [3, 1]}}, "moved_config carries places and drops one that falls off (%s)" % [moved["places"]])
	var piece := LevelMap.new(Vector2i(3, 3), {})
	for y in 3:
		for x in 3:
			piece.set_cell(Vector2i(x, y), "grass")
	var prefab := {"map": piece, "config": {"places": {"camp": {"at": [1, 1], "kind": "camp", "holder": "goblins"}}}}
	var stamped := Prefab.stamp_changes(prefab, LevelMap.new(Vector2i(10, 10), {}), Vector2i(5, 5), {"places": {"camp": {"at": [0, 0]}}})
	_check(stamped.get("config", {}).get("places") == {"camp": {"at": [0, 0]}, "camp_2": {"at": [6, 6], "kind": "camp", "holder": "goblins"}},
		"a stamped prefab's place joins the map's, moved, its key taken already: camp_2 (%s)" % [stamped.get("config")])
	_check("places" in Prefab.KEEP, "and a prefab keeps the places in it")


func _test_holdings() -> void:
	print("holdings")
	var names: Array[String] = ["h_land"]
	var world_map := WorldMap.build(names)
	var clock := [100]
	var holdings := Holdings.new(world_map, null, {}, func() -> int: return clock[0])
	_check(holdings.all_places() == _strings(["h_land/camp", "h_land/farm", "h_land/ford", "h_land/well"]),
		"every place by id (%s)" % [holdings.all_places()])
	_check(holdings.holder("h_land/camp") == "goblins" and holdings.holder("h_land/ford") == "nobody" and holdings.strength("h_land/camp") == 1
		and holdings.since("h_land/camp") == 100, "held as the level starts them, strength 1, since now")
	_check(holdings.places_of("town") == _strings(["h_land/farm", "h_land/well"]) and holdings.places_in("nowhere").is_empty(), "places_of and places_in")
	_check(holdings.area_holder("h_land") == "contested", "goblins 2 worth, town 2 (farm and well): the area is contested")
	_check(holdings.ground("h_land", Vector2i(17, 5)) == "goblins" and holdings.ground("h_land", Vector2i(3, 6)) == "town"
		and holdings.ground("h_land", Vector2i(9, 5)) == "nobody" and holdings.ground("h_land", Vector2i(6, 1)) == "nobody",
		"ground: the camp's radius is the goblins', the farm's the town's, a place nobody holds is no one's, and so is the rest")
	_check(holdings.ground("h_land", Vector2i(12, 5)) == "contested", "the well inside the camp's ground: contested")
	var for_town := holdings.blocked_cells("h_land", "town")
	var for_goblins := holdings.blocked_cells("h_land", "goblins")
	_check(for_town.has(Vector2i(15, 5)) and for_town.has(Vector2i(12, 5)) and not for_town.has(Vector2i(3, 5)) and not for_town.has(Vector2i(9, 5)),
		"the town may not walk the camp's ground, the contested well among it; its farm and the ford are open to it")
	_check(for_goblins.has(Vector2i(3, 5)) and for_goblins.has(Vector2i(12, 5)) and not for_goblins.has(Vector2i(16, 5)),
		"the goblins may not walk the farm or the well; their own camp is open to them")
	var events: Array = []
	holdings.place_taken.connect(func(id: String, from: String, to: String) -> void: events.append(["taken", id, from, to]))
	holdings.area_changed.connect(func(area: String, from: String, to: String) -> void: events.append(["area", area, from, to]))
	clock[0] = 250
	_check(holdings.take("h_land/ford", "goblins", 3), "the goblins take the ford")
	_check(events == [["taken", "h_land/ford", "nobody", "goblins"], ["area", "h_land", "contested", "goblins"]],
		"place_taken, and area_changed as the area tips to them (%s)" % [events])
	_check(holdings.strength("h_land/ford") == 3 and holdings.since("h_land/ford") == 250, "at the strength given, since now")
	_check(not holdings.take("h_land/ford", "goblins") and not holdings.take("h_land/ford", "elves") and not holdings.take("h_land/nope", "town"),
		"no take of one's own, by no faction, or of no place")
	_check(holdings.strengthen("h_land/ford", 2) == 5 and holdings.weaken("h_land/ford", 9) == 0 and holdings.holder("h_land/ford") == "goblins",
		"strengthen and weaken (to 0 at least, still held)")
	clock[0] = 300
	var saved := holdings.to_dict()
	_check(saved["h_land/ford"] == {"holder": "goblins", "strength": 0, "age": 50}, "saved: holder, strength, age (%s)" % [saved["h_land/ford"]])
	clock[0] = 10
	var back := Holdings.new(world_map, null, saved, func() -> int: return clock[0])
	_check(back.holder("h_land/ford") == "goblins" and back.since("h_land/ford") == -40 and back.strength("h_land/ford") == 0,
		"loaded from it on a clock that starts elsewhere: since keeps its age")
	var stale := Holdings.new(world_map, null, {"h_land/gone": {"holder": "town"}, "h_land/farm": {"holder": "elves"}})
	_check(stale.holder("h_land/farm") == "town" and stale.all_places().size() == 4, "a saved place no longer there, or held by no faction, is left out")
	Level.register("h_land", _block(20, 10), null, {"places": {"camp": {"at": [15, 5], "radius": 3, "holder": "goblins"},
		"mill": {"at": [5, 5], "holder": "town"}}})
	var gone := back.rebind(WorldMap.build(names))
	_check(gone == _strings(["h_land/farm", "h_land/ford", "h_land/well"]) and back.holder("h_land/mill") == "town" and back.holder("h_land/camp") == "goblins",
		"rebind: places gone are dropped, a new one starts as its level says, the rest keep theirs (%s)" % [gone])


## The snapshot: a file from before holdings loads with the levels' own
## holders; one saved with them gives them back.
func _test_saved_holdings() -> void:
	print("holdings in the snapshot")
	Level.register("h_land", _block(20, 10), null, {"places": {"camp": {"at": [15, 5], "radius": 3, "holder": "goblins"},
		"mill": {"at": [5, 5], "holder": "town"}}})
	var names: Array[String] = ["h_land"]
	var world_map := WorldMap.build(names)
	var path: String = preload("res://tests/test_ports.gd").scratch("world_map_test_snapshot.json")
	var old := FileAccess.open(path, FileAccess.WRITE)
	old.store_string(JSON.stringify({"version": Snapshot.VERSION, "zones": {}, "players": [], "steps": 40}))
	old.close()
	var loaded := Snapshot.load(path)
	_check(loaded["ok"] and loaded["holdings"] == {}, "a snapshot from before holdings loads, with none (%s)" % [loaded.get("holdings")])
	var clock := [loaded["steps"]]
	var holdings := Holdings.new(world_map, null, loaded["holdings"], func() -> int: return clock[0])
	_check(holdings.holder("h_land/camp") == "goblins" and holdings.holder("h_land/mill") == "town",
		"and the places are held as the levels start them")
	holdings.take("h_land/mill", "goblins", 4)
	clock[0] = 90
	var players: Array[PlayerRecord] = []
	_check(Snapshot.save(path, {}, players, {"steps": 90, "holdings": holdings.to_dict()}), "saved with them, through the world argument")
	var again := Snapshot.load(path)
	var back := Holdings.new(world_map, null, again["holdings"], func() -> int: return again["steps"])
	_check(back.holder("h_land/mill") == "goblins" and back.strength("h_land/mill") == 4 and back.since("h_land/mill") == 40,
		"loaded again: the goblins hold the mill, strength 4, since step 40 (%s)" % [again["holdings"]])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_join() -> void:
	print("join and unjoin (MapDocs, no screen)")
	var ports := preload("res://tests/test_ports.gd")
	var a := MapDoc.open(ports.scratch("wm_join_a/"), Vector2i(4, 4))
	var b := MapDoc.open(ports.scratch("wm_join_b/"), Vector2i(4, 4))
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
	# Walking each time (no fields), then with the fields made on the pool.
	var walking := WorldRoutes.new(world_map, false, false)
	_check(not walking.is_ready() and walking.route("r_room", Vector2i(0, 0), "r_east", Vector2i(1, 1)).map(
		func(leg: Dictionary) -> float: return leg["steps"]) == [10.5, 3.0, 1.0], "with no distance fields, a route walks the areas and finds the same legs")
	var routes := world_map.routes()
	routes.wait()
	_check(routes.is_ready() and routes.build_ms.size() == 3, "the distance fields are made on a pool task, every area's (%s)" % [routes.build_ms])
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
	routes.blocked = func(way: Dictionary, _faction: String) -> bool: return way["kind"] == "edge"
	_check(routes.route("r_room", Vector2i(0, 0), "r_east", Vector2i(1, 1)).is_empty(), "a blocked way closes the route")
	routes.blocked = Callable()
	_check(routes.route("r_room", Vector2i(0, 0), "nowhere", Vector2i.ZERO).is_empty(), "no route to an area that is not there")
	_test_along(routes)


func _test_along(routes: WorldRoutes) -> void:
	print("along")
	var legs := routes.route("r_room", Vector2i(0, 0), "r_east", Vector2i(1, 1))
	var at := func(cells: float) -> Dictionary: return routes.along(legs, cells)
	_check(at.call(0.0) == {"area": "r_room", "cell": Vector2i(0, 0), "leg": 0, "done": false}, "after no steps: where it set out")
	var halfway: Dictionary = at.call(5.5)
	var left := routes.steps_from("r_room", halfway["cell"], [Vector2i(4, 0)] as Array[Vector2i])
	_check(halfway["area"] == "r_room" and left.get(Vector2i(4, 0), -1.0) == 5.0,
		"5.5 steps on: on the walk round the wall, 5 steps from the link (%s)" % [halfway])
	_check(at.call(10.5) == {"area": "r_field", "cell": Vector2i(0, 1), "leg": 1, "done": false}, "crossing the link: where it arrives")
	_check(at.call(13.0)["cell"] == Vector2i(2, 1), "1.5 steps into r_field: down the east edge's field, at (2, 1) (%s)" % [at.call(13.0)])
	_check(at.call(16.5) == {"area": "r_east", "cell": Vector2i(1, 1), "leg": 2, "done": true}, "after every step and crossing (16.5): there, done")
	_check(at.call(99.0)["done"] and routes.along([] as Array[Dictionary], 3.0).is_empty(), "further is still there; no route is nowhere")


## t_mid (21 x 9 cells of floor) has a goblin camp at (10, 4), radius 2, a
## ford nobody holds at (8, 4), radius 4, and t_east (5 x 9) east of it,
## whose arrival from t_mid, (0, 4), is a goblin gate's ground.
func _register_territory_maps() -> void:
	Level.register("t_mid", _block(21, 9), null, {"neighbours": {"east": "t_east"}, "places": {
		"camp": {"at": [10, 4], "kind": "camp", "radius": 2, "holder": "goblins"},
		"ford": {"at": [8, 4], "kind": "gate", "radius": 4}}})
	Level.register("t_east", _block(5, 9), null, {"neighbours": {"west": "t_mid"}, "places": {
		"gate": {"at": [0, 4], "kind": "gate", "radius": 1, "holder": "goblins"}}})


func _test_territory_routes() -> void:
	print("routes round held ground")
	_register_territory_maps()
	var names: Array[String] = ["t_mid", "t_east"]
	var world_map := WorldMap.build(names)
	var holdings := Holdings.new(world_map)
	var routes := holdings.make_routes(world_map)
	routes.wait()
	_check(routes.factions() == _strings(["goblins", "town"]) and routes.is_ready(), "a layer per faction, every field in (%s)" % [routes.build_ms])
	var town := routes.route("t_mid", Vector2i(0, 4), "t_mid", Vector2i(20, 4), "town")
	var goblins := routes.route("t_mid", Vector2i(0, 4), "t_mid", Vector2i(20, 4), "goblins")
	_check(goblins.size() == 1 and goblins[0]["steps"] == 20.0, "the goblins walk straight through their own camp: 20 steps (%s)" % [goblins])
	_check(town.size() == 1 and town[0]["steps"] > 20.0 and not town[0].has("meets"), "the town goes round it, further (%s)" % [town])
	var stepped_on := []
	for half in range(0, int(town[0]["steps"] * 2) + 1):
		var cell: Vector2i = routes.along(town, half / 2.0, "town")["cell"]
		if holdings.ground("t_mid", cell) == "goblins":
			stepped_on.append(cell)
	_check(stepped_on.is_empty(), "and never sets foot on the camp's ground on the way (%s)" % [stepped_on])
	var into := routes.route("t_mid", Vector2i(0, 4), "t_east", Vector2i(3, 4), "town")
	_check(into.size() == 1 and into[0].get("meets") == "t_east/gate" and into[0]["to"] == Vector2i(20, 4) and into[0]["way"].is_empty(),
		"the only way into t_east arrives on the goblins' gate: the route stops at the edge it would cross, meeting it (%s)" % [into])
	var attack := routes.route("t_mid", Vector2i(0, 4), "t_mid", Vector2i(10, 4), "town")
	var edge: Vector2i = attack[-1]["to"] if not attack.is_empty() else Vector2i(-1, -1)
	_check(attack.size() == 1 and attack[0].get("meets") == "t_mid/camp" and holdings.ground("t_mid", edge) == "nobody"
		and (edge - Vector2i(10, 4)).length() <= 3.5, "to the camp itself: to the edge of its ground, meeting it (%s)" % [attack])
	var inside := routes.route("t_mid", Vector2i(10, 5), "t_mid", Vector2i(0, 4), "town")
	_check(str(inside) == str([{"area": "t_mid", "from": Vector2i(10, 5), "to": Vector2i(10, 5), "steps": 0.0, "way": {}, "meets": "t_mid/camp"}]),
		"a town group standing in the camp's ground meets it where it is")
	_check(not routes.route("t_mid", Vector2i(0, 4), "t_east", Vector2i(3, 4), "goblins").is_empty()
		and not routes.route("t_mid", Vector2i(0, 4), "t_east", Vector2i(3, 4), "goblins")[-1].has("meets"), "the goblins go through their gate")
	print("held ground taken")
	holdings.take("t_mid/ford", "goblins")
	var cut := routes.route("t_mid", Vector2i(0, 4), "t_mid", Vector2i(20, 4), "town")
	_check(cut.size() == 1 and cut[0].get("meets") == "t_mid/ford" and holdings.ground("t_mid", cut[0]["to"]) == "nobody",
		"the goblins take the ford, wall to wall: at once the town's way across meets it, before its fields are made again (%s)" % [cut])
	routes.wait()
	_check(routes.is_ready("town") and str(routes.route("t_mid", Vector2i(0, 4), "t_mid", Vector2i(20, 4), "town")) == str(cut),
		"its fields made again on the pool: the same answer")
	_check(routes.route("t_mid", Vector2i(0, 4), "t_mid", Vector2i(20, 4), "goblins")[0]["steps"] == 20.0, "the goblins' own ground stays open to them")
	_check(routes.route("t_mid", Vector2i(0, 4), "t_mid", Vector2i(20, 4)).size() == 1, "a route with no faction ignores held ground")
	routes.blocked = func(way: Dictionary, faction: String) -> bool: return faction == "goblins" and way["kind"] == "edge"
	_check(routes.route("t_mid", Vector2i(0, 4), "t_east", Vector2i(3, 4), "goblins").is_empty(),
		"a way blocked for a faction (not by ground) gives it no route, not one to meet anything")
	routes.blocked = Callable()


func _test_level_routes() -> void:
	print("routes on levels/")
	var started := Time.get_ticks_usec()
	var world_map := WorldMap.build()
	var built := Time.get_ticks_usec()
	var routes := world_map.routes()
	var routed := Time.get_ticks_usec()
	routes.wait()
	print("    WorldMap.build %.0f ms; routes %.0f ms on this thread, then distance fields on the pool in %.0f ms (%s)" % [
		(built - started) / 1000.0, (routed - built) / 1000.0, (Time.get_ticks_usec() - routed) / 1000.0,
		", ".join(routes.build_ms.keys().map(func(area: String) -> String: return "%s %.0f ms" % [area, routes.build_ms[area]]))])
	_check((routed - built) / 1000.0 < 50.0, "making the routes leaves the distance fields to the pool: under 50 ms here")
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
	# Deep into the wilds: its last leg comes from the fields, not a walk.
	var far := Vector2i.ZERO
	for cell: Vector2i in wilds["floor"]:
		if cell.y > far.y:
			far = cell
	query = Time.get_ticks_usec()
	legs = routes.route("test_room", room["starts"][0], "wilds", far)
	var ms := (Time.get_ticks_usec() - query) / 1000.0
	print("    test_room to the wilds' far side %s: %.0f ms, %s steps" % [far, ms, legs.map(func(leg: Dictionary) -> float: return leg["steps"])])
	_check(legs.size() == 3 and ms < 50.0, "to the wilds' far side, with the fields: %.0f ms" % ms)


## [param values] as an Array[String], to compare typed arrays with.
static func _strings(values: Array) -> Array[String]:
	var out: Array[String] = []
	out.assign(values)
	return out


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
