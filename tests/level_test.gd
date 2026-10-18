extends Node
## Levels from pixel maps (sim/level.gd): the test room unchanged, a round
## trip through PNG, edge walls and doors from wall and door pixels, heights,
## stairs, falls, sight over lower walls, level links, the console.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const LEGACY := preload("res://tests/legacy_test_room.gd")

var _failures := 0
var _main: Node
var _pushes: Array[Dictionary] = []


func _ready() -> void:
	World.set_process(false)
	Net.port = preload("res://tests/test_ports.gd").of(17790)
	Net.companions = false
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	World.entity_pushed.connect(func(entity: GridEntity, _by: GridEntity, _direction: Vector2i, tiles: int, impact: int, stopped_by: String) -> void:
		_pushes.append({"entity": entity, "tiles": tiles, "impact": impact, "stopped_by": stopped_by}))
	_register_maps()

	_test_test_room_unchanged()
	_test_every_level()
	_test_round_trip()
	_test_edges_and_doors()
	_test_markers()
	_test_heights_and_stairs()
	_test_falls()
	_test_sight_over_walls()
	_test_hills()
	_test_buildings()
	_test_field()
	_test_building_links()
	_test_town_walls()
	_test_roofs()
	await _test_level_links()
	await _test_edge_links()
	_test_console()
	await _test_castle()

	_main.load_map(Level.DEFAULT_MAP)
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


# --- Maps made in code -------------------------------------------------------------

## ASCII rows in Terrain's double resolution for cells x in [x0, x1], y in
## [y0, y1], all floor, with [param walls] and [param doors] (edge keys).
static func _rows(x0: int, x1: int, y0: int, y1: int, walls: Array[Vector3i] = [], doors: Array[Vector3i] = []) -> Array[String]:
	var width := 2 * x1 + 3
	var height := 2 * y1 + 3
	var grid: Array[PackedStringArray] = []
	for y in height:
		var row := PackedStringArray()
		row.resize(width)
		row.fill(" ")
		grid.append(row)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			grid[2 * y][2 * x] = "."
	for key in walls:
		var at := Vector2i(key.x, key.y) * 2 + (Vector2i(1, 0) if key.z == Terrain.EAST else Vector2i(0, 1))
		grid[at.y][at.x] = "#"
	for key in doors:
		var at := Vector2i(key.x, key.y) * 2 + (Vector2i(1, 0) if key.z == Terrain.EAST else Vector2i(0, 1))
		grid[at.y][at.x] = "+"
	var rows: Array[String] = []
	for row in grid:
		rows.append("".join(row))
	return rows


func _register_maps() -> void:
	# Edges: a wall pixel between (1,1) and (2,1), a door between (2,1) and
	# (3,1); a wall pixel on cell (4,2) is void; the wall colour overridden.
	var config := {"legend": {"wall": "#123456"}}
	var rows := _rows(1, 4, 1, 2, [Vector3i(1, 1, Terrain.EAST)], [Vector3i(2, 1, Terrain.EAST)])
	var image := Level.image_from_rows(rows, {Vector2i(1, 1): "start", Vector2i(1, 2): "crate", Vector2i(3, 2): "monster_brute"}, config)
	image.set_pixel(8, 4, Color("#123456"))
	Level.register("test_edges", image, null, config)
	# Heights: x 1-2 at 0, x 3 at 1, x 4-5 at 2; row 3's x 3 at 0; a stair
	# on (2,2) climbing east; a wall between (1,3) and (2,3).
	var heights := {}
	var levels := [[0, 0, 1, 2, 2], [0, 0, 1, 2, 2], [0, 0, 0, 2, 2]]
	for y in 3:
		for x in 5:
			heights[Vector2i(x + 1, y + 1)] = levels[y][x]
	var height_rows := _rows(1, 5, 1, 3, [Vector3i(1, 3, Terrain.EAST)])
	var layout := Level.image_from_rows(height_rows, {Vector2i(1, 1): "start", Vector2i(2, 2): "stair"})
	Level.register("test_heights", layout, Level.height_image(layout, heights), {})
	# Links: a to b, arriving at b's spawn point "gate".
	Level.register("test_link_a", Level.image_from_rows(_rows(1, 4, 1, 1), {Vector2i(1, 1): "start", Vector2i(4, 1): "link"}), null,
		{"links": [{"at": [4, 1], "to_map": "test_link_b", "to_spawn": "gate"}]})
	Level.register("test_link_b", Level.image_from_rows(_rows(1, 3, 1, 2), {Vector2i(1, 1): "start"}), null,
		{"spawn_points": {"gate": [2, 2]}})
	# Edge links: test_edge_w (4 x 3 cells, all floor) has test_edge_e
	# (3 x 5) east of it, and the other way round.
	var w_rows: Array[String] = []
	for y in 5:
		w_rows.append(".".repeat(7))
	Level.register("test_edge_w", Level.image_from_rows(w_rows, {Vector2i(0, 1): "start"}), null, {"neighbours": {"east": "test_edge_e"}})
	var e_rows: Array[String] = []
	for y in 9:
		e_rows.append(".".repeat(5))
	Level.register("test_edge_e", Level.image_from_rows(e_rows, {Vector2i(2, 0): "start"}), null, {"neighbours": {"west": "test_edge_w"}})


# --- Tests ----------------------------------------------------------------------

func _test_test_room_unchanged() -> void:
	print("\n== levels/test_room is the old test room, unchanged (but for its chest, and crates that carry) ==")
	_check(load("res://levels/test_room/layout.png") is Image, "its layout.png is imported as an Image (readable on a headless server)")
	var level := Level.load_level("test_room")
	var old := Terrain.parse(LEGACY.LEVEL)
	var terrain: Dictionary = level["terrain"]
	_check(_same_cells(terrain["floor"], old["floor"]) and _same_cells(terrain["fire"], old["fire"]),
			"the same floor (%d) and fire (%d)" % [terrain["floor"].size(), terrain["fire"].size()])
	_check(terrain["edges"] == old["edges"], "the same walls and doors (%d edges)" % terrain["edges"].size())
	var entities: Array = level["entities"].filter(func(spec: Dictionary) -> bool: return spec["script"] != Level.CHEST)
	var chests: Array = level["entities"].filter(func(spec: Dictionary) -> bool: return spec["script"] == Level.CHEST)
	_check(chests.size() == 1 and chests[0]["tile"] == Vector2i(10, 3) and chests[0]["name"] == "Chest1"
			and Array(chests[0]["props"]["slots"]) == ["bandaging_kit", "", "", ""],
			"one thing new: Chest1 at (10, 3), a bandaging kit in it")
	var same := entities.size() == LEGACY.LEVEL_ENTITIES.size()
	for i in mini(entities.size(), LEGACY.LEVEL_ENTITIES.size()):
		var a: Dictionary = entities[i]
		var b: Dictionary = LEGACY.LEVEL_ENTITIES[i].duplicate(true)
		if b["name"].begins_with("Crate"):
			# Crates carry things now (decision 259): a Cargo of 4, nothing else changed.
			b["script"] = Level.CARGO
			b["props"] = {"capacity": 4}
		for key in ["script", "shape", "name", "tile", "tint", "props"]:
			if a.get(key) != b.get(key):
				same = false
				print("    entity %d %s: %s vs %s" % [i, key, a.get(key), b.get(key)])
	_check(same, "the same entities, in the same order, with the same props")
	_check(level["starts"] == LEGACY.PLAYER_STARTS and level["centre"] == LEGACY.CHAMBER_CENTRE, "the same starts, in order, and centre")
	_check(level["warnings"].is_empty() and terrain["heights"].is_empty() and terrain["water"].is_empty(),
			"no warnings, no heights, no water (%s)" % [level["warnings"]])
	_check(_main.map_name == "test_room" and _main.level_entities.size() == 10, "and it is what the game plays by default")


func _test_every_level() -> void:
	_check(World.holdings != null and World.holdings.all_places().size() == WorldMap.build().areas.values().reduce(
			func(count: int, area: Dictionary) -> int: return count + area["places"].size(), 0),
			"the server's boot makes World.holdings, a holding for every place in the levels")
	print("\n== every level in levels/ imports as Images and loads cleanly ==")
	for folder in DirAccess.get_directories_at(Level.DIR):
		if Level.DIR + folder + "/" == Prefab.DIR or not FileAccess.file_exists(Level.DIR + folder + "/layout.png"):
			continue
		var images_ok := load(Level.DIR + folder + "/layout.png") is Image
		if ResourceLoader.exists(Level.DIR + folder + "/height.png"):
			images_ok = images_ok and load(Level.DIR + folder + "/height.png") is Image
		var level := Level.load_level(folder)
		_check(images_ok and not level.is_empty() and level["warnings"].is_empty(),
				"%s: %d cells, %d entities (%s)" % [folder, level["terrain"]["floor"].size() if not level.is_empty() else 0,
					level["entities"].size() if not level.is_empty() else 0, level.get("warnings", "no level")])
	print("
== the levels connect: WorldMap.problems() (links and spawn points, ways back, reachable) ==")
	var problems := WorldMap.build().problems()
	_check(problems.is_empty(), "every link leads to a level and a spawn point it has, with a way back, and every level is reachable (%s)" % [problems])
	print("
== every prefab in levels/prefabs/ imports as Images and reads cleanly ==")
	var prefabs := Prefab.names()
	_check(prefabs.size() >= 4, "the prefabs seeded by hand are there (%s)" % [prefabs])
	for prefab_name in prefabs:
		var folder := Prefab.DIR + prefab_name + "/"
		var image_ok := load(folder + "layout.png") is Image
		var prefab := Prefab.load_prefab(prefab_name)
		# A piece of map has no start of its own: that warning is expected.
		var warnings: Array = Level.parse(prefab["map"].to_image(), null, prefab["config"])["warnings"].filter(
				func(warning: String) -> bool: return not warning.begins_with("no player start"))
		_check(image_ok and warnings.is_empty(), "%s: %s cells (%s)" % [prefab_name, prefab["map"].size, warnings])


func _test_round_trip() -> void:
	print("\n== round trip: the ASCII room to an image, to a PNG and back ==")
	var image := Level.image_from_rows(LEGACY.LEVEL)
	var path: String = preload("res://tests/test_ports.gd").scratch_path("round_trip.png")
	_check(image.save_png(path) == OK, "saved")
	var back := Image.load_from_file(path)
	var level := Level.parse(back, null, {})
	var old := Terrain.parse(LEGACY.LEVEL)
	_check(_same_cells(level["terrain"]["floor"], old["floor"]) and level["terrain"]["edges"] == old["edges"],
			"read back, the same terrain as Terrain.parse of the rows")
	_check(back.get_data() == image.get_data(), "and the same pixels")
	DirAccess.remove_absolute(path)


func _test_edges_and_doors() -> void:
	print("\n== edge walls from wall pixels, doors from door pixels ==")
	var level := Level.load_level("test_edges")
	var edges: Dictionary = level["terrain"]["edges"]
	_check(edges.get(Vector3i(1, 1, Terrain.EAST)) == Terrain.Edge.WALL, "a wall pixel between two floor cells: a thin wall on that edge")
	_check(edges.get(Vector3i(2, 1, Terrain.EAST)) == Terrain.Edge.DOOR, "a door pixel: a door")
	_check(not edges.has(Vector3i(3, 1, Terrain.EAST)), "no pixel between floor cells: open")
	_check(edges.get(Vector3i(0, 1, Terrain.EAST)) == Terrain.Edge.WALL and edges.get(Vector3i(1, 0, Terrain.SOUTH)) == Terrain.Edge.WALL,
			"floor against the void: the outer wall, drawn or not")
	_check(Vector2i(4, 2) not in level["terrain"]["floor"] and edges.get(Vector3i(4, 1, Terrain.SOUTH)) == Terrain.Edge.WALL,
			"a wall pixel on a cell: void, walled off")
	_check(level["warnings"].is_empty(), "the legend override (#123456 is wall) was read (%s)" % [level["warnings"]])
	_main.load_map("test_edges")
	_check(_main.map_name == "test_edges" and World.edge_kind(Vector2i(1, 1), Vector2i(1, 0)) == Terrain.Edge.WALL,
			"loaded, the World has the wall")
	var door := _named("Door_2_1_e")
	_check(door is Door, "and the door is a Door, spawned with the level")
	_check(World.edge_blocks(Vector2i(2, 1), Vector2i(1, 0)) and not World.edge_blocks(Vector2i(2, 1), Vector2i(1, 0), true),
			"closed: it stops a push, a creature opens it")


func _test_markers() -> void:
	print("\n== markers: entities by type, starts, unknown colours ==")
	var level := Level.load_level("test_edges")
	var names: Array[String] = []
	for spec: Dictionary in level["entities"]:
		names.append(str(spec["name"]))
	_check(names == ["Crate1", "Brute1"], "a crate and a brute, named by kind: %s" % [names])
	var brute: Dictionary = level["entities"][1]
	_check(brute["props"].get("mass") == 70.0 and brute["script"] == Level.MONSTER, "the brute has a brute's mass (%s)" % [brute["props"]])
	_check(level["starts"] == [Vector2i(1, 1)], "the start marker is a start")
	_check(level["terrain"]["kinds"].get(Vector2i(1, 2)) == "stone", "a marker's cell is the ground around it")
	var odd := Level.image_from_rows(_rows(1, 2, 1, 1))
	odd.set_pixel(2, 2, Color("#abcdef"))
	var parsed := Level.parse(odd, null, {})
	_check(Vector2i(1, 1) not in parsed["terrain"]["floor"] and str(parsed["warnings"]).contains("abcdef"),
			"a colour not in the legend is void, and said so: %s" % [parsed["warnings"]])


func _test_heights_and_stairs() -> void:
	print("\n== heights: a ledge stops walkers; a stair joins two heights ==")
	_main.load_map("test_heights")
	var level: Dictionary = _main.level
	_check(level["terrain"]["stairs"] == {Vector2i(2, 2): Vector2i(1, 0)}, "the stair climbs east, from its neighbours: %s" % [level["terrain"]["stairs"]])
	_check(World.height_at(Vector2i(4, 1)) == 2 and World.height_at(Vector2i(3, 1)) == 1 and World.height_at(Vector2i(1, 1)) == 0,
			"heights read from height.png")
	_check(World._terrain_blocks_step(Vector2i(2, 1), Vector2i(1, 0)) and World._terrain_blocks_step(Vector2i(3, 1), Vector2i(-1, 0)),
			"no stair: a ledge, up or down")
	_check(not World._terrain_blocks_step(Vector2i(2, 2), Vector2i(1, 0)) and not World._terrain_blocks_step(Vector2i(3, 2), Vector2i(-1, 0)),
			"the stair: up it and down it")
	_check(World._terrain_blocks_step(Vector2i(2, 2), Vector2i(1, -1)), "not diagonally off it")
	var player := _player()
	_put(player, Vector2i(2, 2))
	_wait_for_step(player)
	_check(World.try_move(player, Vector2i(1, 0)) and player.tile == Vector2i(3, 2), "Player walks up the stair (%s)" % player.tile)
	_wait_for_step(player)
	_check(not World.try_move(player, Vector2i(0, -1)) or World.height_at(player.tile) == 1, "along the top, still on level 1")
	_put(player, Vector2i(3, 1))
	_wait_for_step(player)
	_check(not World.try_move(player, Vector2i(-1, 0)) and player.tile == Vector2i(3, 1), "and does not step off the ledge (%s)" % player.tile)
	var path := World.find_path(Vector2i(1, 1), Vector2i(3, 1), true)
	_check(not path.is_empty() and Vector2i(2, 2) in path and Vector2i(3, 2) in path, "a path to level 1 goes by the stair: %s" % [path])
	_check(World.find_path(Vector2i(1, 1), Vector2i(4, 1)).is_empty(), "and none reaches level 2, which no stair joins")
	var bad := Level.parse(Level.image_from_rows(_rows(1, 2, 1, 1), {Vector2i(1, 1): "stair"}), null, {})
	_check(bad["terrain"]["stairs"].is_empty() and str(bad["warnings"]).contains("no cell one level up"),
			"a stair with nothing above it is floor, and said so")


func _test_falls() -> void:
	print("\n== falls: off a ledge for impact per level; never up a step ==")
	_main.load_map("test_heights")
	var player := _player()
	var imp: Monster = _main._spawn({"script": Level.MONSTER, "shape": "capsule", "name": "Faller", "tile": Vector2i(4, 3), "props": {"sight_range": 0}})
	_put(player, Vector2i(5, 3))
	_pushes.clear()
	var hp := imp.hp
	World._push(player, imp, Vector2i(-1, 0), 3.0)
	_check(imp.tile == Vector2i(3, 3) and _pushes.back()["stopped_by"] == "a fall of 2",
			"pushed off two levels: it falls to (3, 3) (%s, %s)" % [imp.tile, _pushes.back()["stopped_by"]])
	_check(hp - imp.hp == World.FALL_IMPACT_PER_LEVEL * 2, "and takes %d impact a level (%d)" % [World.FALL_IMPACT_PER_LEVEL, hp - imp.hp])
	_check(imp.stunned_until_tick > World.tick, "stunned by it")
	_put(imp, Vector2i(2, 1))
	_put(player, Vector2i(1, 1))
	_pushes.clear()
	World._push(player, imp, Vector2i(1, 0), 3.0)
	_check(imp.tile == Vector2i(2, 1) and _pushes.back()["stopped_by"] == "a ledge", "pushed at a step up: it stays (%s)" % _pushes.back()["stopped_by"])
	World.despawn(imp)


func _test_sight_over_walls() -> void:
	print("\n== higher cells see over lower walls ==")
	_check(not World.has_line_of_sight(Vector2i(3, 3), Vector2i(1, 3)), "on the ground, the wall between (1,3) and (2,3) stops sight")
	_check(World.has_line_of_sight(Vector2i(4, 3), Vector2i(1, 3)), "from two levels up, it is seen over")


## levels/hills (decision 358, tools/make_hills.gd): a bot walks from the
## valley up the terraces onto the plateau and down the cliff's flight; a
## body pushed off the rim falls four levels, off the flight two; the
## plateau sees over the valley's low wall, the valley floor does not.
func _test_hills() -> void:
	print("
== levels/hills: heights to walk, fall from and see over ==")
	_check(_main.load_map("hills") and World.outdoor, "hills loads, outdoors")
	var player := _player()
	_check(player != null and World.height_at(player.tile) == 0, "Player starts on the valley floor (%s)" % [player.tile if player else "none"])
	var plateau := Vector2i(72, 30)
	_check(World.height_at(plateau) == 4 and World.height_at(Vector2i(61, 38)) == 0, "the plateau stands at 4 over the valley at 0")
	var path := World.find_path(player.tile, plateau)
	_check(not path.is_empty() and (Vector2i(76, 49) in path or Vector2i(61, 30) in path), "a way up to the plateau, by the terraces' stairs or the cliff's flight (%d steps)" % path.size())
	var climbed := {}
	World.order_move(player, plateau)
	for i in 600:
		if player.tile == plateau:
			break
		World.step()
		climbed[World.height_at(player.tile)] = true
	_check(player.tile == plateau and climbed.size() == 5, "the bot walks up there, on every level from 0 to 4 on the way (%s, %s)" % [player.tile, climbed.keys()])
	var below := Vector2i(57, 30)
	World.order_move(player, below)
	for i in 300:
		if player.tile == below:
			break
		World.step()
	_check(player.tile == below, "and back down to the valley (%s)" % player.tile)
	for top: Vector2i in [Vector2i(20, 48), Vector2i(22, 25), Vector2i(24, 77)]:
		_check(World.height_at(top) > 0 and not World.find_path(below, top).is_empty(),
				"the rise at %s (level %d) has a way up" % [top, World.height_at(top)])
	_check(World.height_at(Vector2i(28, 49)) == 0 and World.height_at(Vector2i(28, 48)) > 0 and World._terrain_blocks_step(Vector2i(28, 49), Vector2i(0, -1)),
			"the gully's floor is at 0, a ledge up to its side")
	var imp: Monster = _main._spawn({"script": Level.MONSTER, "shape": "capsule", "name": "Faller", "tile": Vector2i(62, 38), "props": {"sight_range": 0}})
	_put(player, Vector2i(63, 38))
	_pushes.clear()
	var hp := imp.hp
	World._push(player, imp, Vector2i(-1, 0), 3.0)
	_check(World.height_at(imp.tile) == 0 and _pushes.back()["stopped_by"] == "a fall of 4" and hp - imp.hp == World.FALL_IMPACT_PER_LEVEL * 4,
			"pushed off the rim: it falls four levels for %d (%s, %s)" % [hp - imp.hp, imp.tile, _pushes.back()["stopped_by"]])
	_put(imp, Vector2i(60, 30))
	_put(player, Vector2i(61, 30))
	_pushes.clear()
	World._push(player, imp, Vector2i(0, 1), 3.0)
	_check(_pushes.back()["stopped_by"] == "a fall of 2" and World.height_at(imp.tile) == 0, "pushed off the cliff's flight, open at its sides: it falls two (%s)" % _pushes.back()["stopped_by"])
	World.despawn(imp)
	_check(not World.has_line_of_sight(Vector2i(57, 38), Vector2i(53, 38)), "on the valley floor, the low wall stops sight")
	_check(World.has_line_of_sight(Vector2i(63, 37), Vector2i(53, 38)), "from the plateau's rim it is seen over")


## [param prefab_name] stamped onto [param map] at [param at], turned
## [param turns]: the map changed in place, the config returned.
func _stamp(map: LevelMap, config: Dictionary, prefab_name: String, at: Vector2i, turns := 0) -> Dictionary:
	var changes := Prefab.stamp_changes(Prefab.rotated(Prefab.load_prefab(prefab_name), turns), map, at, config)
	for cell: Vector2i in changes["cells"]:
		map.set_cell(cell, changes["cells"][cell])
	for key: Vector3i in changes["edges"]:
		map.set_edge(key, changes["edges"][key])
	var out := config.duplicate(true)
	out.merge(changes.get("config", {}), true)
	return out


func _test_buildings() -> void:
	print("\n== buildings: kit prefabs stamped, turned, replaced; the footprint checked ==")
	var map := LevelMap.new(Vector2i(24, 20))
	for y in 20:
		for x in 24:
			map.set_cell(Vector2i(x, y), "grass")
	var config := _stamp(map, {}, "building_house", Vector2i(2, 2))
	config = _stamp(map, config, "building_hut", Vector2i(12, 2), 1)
	config = _stamp(map, config, "building_shed", Vector2i(2, 12), 1)
	var level := Level.parse(map.to_image(), null, config)
	var by_slot := {}
	for building: Dictionary in level["buildings"]:
		by_slot[building["slot"]] = building
	var said := func(warnings: Array) -> Array: return warnings.filter(func(text: String) -> bool: return text.contains("building"))
	_check(by_slot.size() == 3 and said.call(level["warnings"]).is_empty(), "three buildings, nothing said of them (%s)" % [level["warnings"]])
	_check(by_slot.get("building.house", {}).get("rect") == Rect2i(3, 3, 4, 6) and by_slot["building.house"]["facing"] == Vector2i(0, 1),
			"the house's footprint is 4 x 6 inside its walls, its front south (%s)" % [by_slot.get("building.house")])
	_check(by_slot.get("building.shed", {}).get("rect") == Rect2i(3, 13, 3, 2) and by_slot["building.shed"]["facing"] == Vector2i(-1, 0),
			"the shed turned a quarter is 3 x 2, its front west (%s)" % [by_slot.get("building.shed")])
	var shed: Rect2i = by_slot["building.shed"]["rect"]
	var walls := Level.outline(shed).filter(func(key: Vector3i) -> bool: return level["terrain"]["edges"].get(key) == Terrain.Edge.WALL)
	var doors := Level.outline(shed).filter(func(key: Vector3i) -> bool: return level["terrain"]["edges"].get(key) == Terrain.Edge.DOOR)
	_check(walls.size() == 9 and doors.size() == 1 and doors[0].z == Terrain.EAST and doors[0].x == shed.position.x - 1,
			"its outline is walls and a door on its west side (%s)" % [doors])

	config = _stamp(map, config, "building_hut", Vector2i(12, 2))
	var slots := (config["buildings"] as Array).map(func(entry: Dictionary) -> String: return entry["slot"])
	_check(slots.count("building.hut") == 1 and slots.size() == 3, "a hut stamped over the hut replaces it, the others kept (%s)" % [slots])
	config = _stamp(map, config, "campfire_camp", Vector2i(1, 1))
	_check((config["buildings"] as Array).size() == 2, "another prefab laid over the house takes the house's record with it")

	var bad := config.duplicate(true)
	bad["buildings"] = [{"slot": "building.castle", "at": [0, 0]}, {"slot": "building.hut", "at": [22, 18]},
		{"slot": "building.hut", "at": [13, 3]}, {"slot": "building.hut", "at": [15, 15]}]
	level = Level.parse(map.to_image(), null, bad)
	_check(level["buildings"].size() == 2 and level["buildings"][1]["rect"] == Rect2i(15, 15, 3, 3), "an unknown slot and one off the floor are left out (%s)" % [level["buildings"]])
	var warned: Array = said.call(level["warnings"])
	_check(warned.size() == 3 and str(warned[2]).contains("open edges"), "said, and the hut in the open said to have open edges (%s)" % [warned])
	config = _stamp(map, config, "well", Vector2i(12, 12))
	level = Level.parse(map.to_image(), null, config)
	var wells := (level["buildings"] as Array).filter(func(b: Dictionary) -> bool: return b["slot"] == "building.well")
	_check(wells.size() == 1 and wells[0]["rect"] == Rect2i(14, 14, 1, 1) and Vector2i(14, 14) in level["terrain"]["water"],
			"the well prefab's well stands on its water (%s)" % [wells])
	_check(said.call(level["warnings"]).is_empty(), "a well has no walls, and is not said to be open")
	bad = config.duplicate(true)
	bad["buildings"] = [{"slot": "building.well", "at": [20, 2]}]
	level = Level.parse(map.to_image(), null, bad)
	_check(level["buildings"].is_empty() and str(said.call(level["warnings"])).contains("water"), "a well on grass is left out: it stands on water")
	var hut_at := Rect2i(13, 3, 3, 3)
	_check(Level.rect_cells(hut_at).size() == 9 and Level.outline(hut_at).size() == 12, "a 3 x 3 footprint: nine cells, twelve outline edges")


## A field (Level.OPEN_AIR, decision 452): its prefab's fence is walls on
## its outline but the gate, which stop walkers and not sight; nothing of
## it roofed, while a hut beside it is walled and roofed as ever.
func _test_field() -> void:
	print("\n== a field: fenced against walkers, open to sight and sky ==")
	var map := LevelMap.new(Vector2i(12, 8))
	for y in 8:
		for x in 12:
			map.set_cell(Vector2i(x, y), "grass")
	map.set_cell(Vector2i(0, 0), "start")
	var config := _stamp(map, {}, "building_field", Vector2i(1, 1))
	config = _stamp(map, config, "building_hut", Vector2i(7, 1))
	var level := Level.parse(map.to_image(), null, config)
	var fields := (level["buildings"] as Array).filter(func(b: Dictionary) -> bool: return b["slot"] == "building.field")
	var said := (level["warnings"] as Array).filter(func(text: String) -> bool: return text.contains("building") or text.contains("field"))
	_check(fields.size() == 1 and fields[0]["rect"] == Rect2i(2, 2, 4, 4) and fields[0]["facing"] == Vector2i(0, 1) and said.is_empty(),
			"the prefab's field is 4 x 4, its front south, its gate not said to be open (%s, %s)" % [fields, level["warnings"]])
	var edges: Dictionary = level["terrain"]["edges"]
	var open := Level.outline(Rect2i(2, 2, 4, 4)).filter(func(key: Vector3i) -> bool: return edges.get(key) != Terrain.Edge.WALL)
	_check(open == [Vector3i(4, 5, Terrain.SOUTH)], "fenced all round but the gate, in its front just right of the middle (%s)" % [open])
	Level.register("test_field", map.to_image(), null, config)
	_check(_main.load_map("test_field"), "the level with a field loads")
	_check(World.edge_blocks(Vector2i(2, 3), Vector2i(-1, 0)) and World.edge_blocks(Vector2i(3, 2), Vector2i(0, -1)),
			"the fence stops a walker")
	_check(not World.edge_blocks(Vector2i(4, 5), Vector2i(0, 1)), "the gate lets one through")
	_check(World.has_line_of_sight(Vector2i(0, 3), Vector2i(4, 3)) and World.has_line_of_sight(Vector2i(3, 0), Vector2i(3, 7)),
			"sight crosses the fence, both sides")
	_check(not World.has_line_of_sight(Vector2i(7, 3), Vector2i(9, 3)), "the hut's wall still stops sight")
	_check(Level.rect_cells(Rect2i(2, 2, 4, 4)).all(func(cell: Vector2i) -> bool: return not World.fields._roofed.has(cell))
			and World.fields._roofed.has(Vector2i(9, 3)), "nothing of the field is roofed; the hut is")
	Level.unregister("test_field")


func _test_building_links() -> void:
	print("
== buildings linked to their town's records: use and town checked ==")
	var map := LevelMap.new(Vector2i(30, 12))
	for y in 12:
		for x in 30:
			map.set_cell(Vector2i(x, y), "grass")
	var config := {"places": {"square": {"at": [8, 5], "kind": "stockpile", "radius": 8}, "field": {"at": [26, 5], "kind": "farm"}}}
	for at in [Vector2i(1, 1), Vector2i(7, 1), Vector2i(13, 1), Vector2i(19, 1), Vector2i(24, 1)]:
		config = _stamp(map, config, "building_hut", at)
	var entries: Array = config["buildings"]
	entries[0].merge({"use": "forge", "town": "square"})
	entries[1].merge({"use": "forge", "town": "square"})
	entries[2].merge({"use": "castle", "town": "square"})
	entries[3].merge({"use": "inn", "town": "field"})
	entries[4].merge({"use": "kitchen", "town": "square"})
	var level := Level.parse(map.to_image(), null, config)
	var links := (level["buildings"] as Array).map(func(b: Dictionary) -> String: return "%s:%s" % [b["use"], b["town"]])
	_check(links == ["forge:square", ":", ":", ":", "kitchen:square"], "linked: the first forge and the kitchen; a second forge, a use there is not and a town that is no stockpile stand unlinked (%s)" % [links])
	var said := (level["warnings"] as Array).filter(func(text: String) -> bool: return text.contains("linked") or text.contains("radius"))
	_check(said.size() == 3 and str(said).contains("already has its forge") and not str(said).contains("radius"),
			"each said; the kitchen far from the store is linked all the same: a town is more than its store's yard (%s)" % [said])
	var turned := Prefab.rotated({"map": map, "config": config}, 1)
	_check((turned["config"]["buildings"] as Array)[0].get("use") == "forge", "a link moves with its building")


func _test_town_walls() -> void:
	print("
== town walls: a ring of the layout's walls named a town's, its gates its doors ==")
	var map := LevelMap.new(Vector2i(24, 20))
	for y in 20:
		for x in 24:
			map.set_cell(Vector2i(x, y), "grass")
	var rect := Rect2i(4, 3, 12, 10)
	var gate := Vector3i(9, 12, Terrain.SOUTH)
	var gap := Vector3i(3, 6, Terrain.EAST)
	for key in Level.outline(rect):
		if key != gap:
			map.set_edge(key, "door" if key == gate else "wall")
	var places := {"square": {"at": [9, 7], "kind": "stockpile"}, "yard": {"at": [20, 16], "kind": "stockpile"}, "field": {"at": [2, 2], "kind": "farm"}}
	var config := {"places": places, "town_walls": [
		{"town": "square", "rect": [4, 3, 12, 10]},
		{"town": "square", "rect": [1, 1, 3, 3]},
		{"town": "field", "rect": [1, 14, 4, 4]},
		{"town": "yard", "rect": [20, 18, 6, 6]},
		{"town": "yard", "rect": [17, 14, 2, 2]}]}
	var level := Level.parse(map.to_image(), null, config)
	var rings: Array = level["town_walls"]
	var said := (level["warnings"] as Array).filter(func(text: String) -> bool: return text.contains("town wall"))
	_check(rings.size() == 2 and rings[0]["town"] == "square" and rings[0]["rect"] == rect and rings[1]["town"] == "yard",
			"the square's wall and the yard's small one stand (%s)" % [rings.map(func(r: Dictionary) -> String: return "%s %s" % [r["town"], r["rect"]])])
	_check(rings[0]["gates"] == [gate] and rings[0]["walls"].size() == Level.outline(rect).size() - 2, "its gate is the door on its ring; the rest walls but the gap")
	_check(said.size() == 6 and str(said).contains("has its wall already") and str(said).contains("no stockpile place") and str(said).contains("on the map")
			and str(said).contains("1 open edges") and str(said).contains("does not hold its place"),
			"a second wall, a town that is no stockpile, a ring off the map left out; the gaps (the yard's ring is not drawn) and the yard's cell outside said (%s)" % [said])
	_check(level["terrain"]["town_walls"] == rings, "the views have them in the terrain")
	var turned := Prefab.rotated({"map": map, "config": config}, 1)
	var moved: Array = turned["config"]["town_walls"]
	_check(moved.size() == 5 and moved[0]["rect"] == [7, 4, 10, 12], "turned with the map, a ring keeps its cells: 10 x 12 (%s)" % [moved[0]])



func _test_roofs() -> void:
	print("
== roofs: a tiling set over any room (decision 364), checked as buildings are ==")
	var map := LevelMap.new(Vector2i(24, 20))
	for y in 20:
		for x in 24:
			map.set_cell(Vector2i(x, y), "grass")
	map.set_cell(Vector2i(20, 2), "water")
	var config := {"buildings": [{"slot": "building.hut", "at": [16, 12]}], "roofs": [
		{"rect": [2, 2, 4, 6]},
		{"rect": [10, 2, 5, 3], "ridge": "x", "set": "shingle"},
		{"rect": [2, 12, 3, 3], "set": "slate"},
		{"rect": [4, 6, 3, 3]},
		{"rect": [17, 13, 2, 2]},
		{"rect": [19, 2, 3, 1]},
		{"rect": [2, 16]}]}
	var level := Level.parse(map.to_image(), null, config)
	var roofs: Array = level["roofs"]
	var said := (level["warnings"] as Array).filter(func(text: String) -> bool: return text.contains("roof"))
	_check(roofs.size() == 2 and roofs[0]["rect"] == Rect2i(2, 2, 4, 6) and roofs[0]["ridge"] == "z" and roofs[0]["set"] == "shingle"
			and roofs[1]["rect"] == Rect2i(10, 2, 5, 3) and roofs[1]["ridge"] == "x",
			"two roofs stand, the ridge along the long side if not given (%s)" % [roofs])
	_check(said.size() == 5 and str(said).contains("one of shingle") and str(said).count("clear floor of one height") == 3 and str(said).contains("has no"),
			"a set there is not, over another roof, over a building, over water, and no rect, each said and left out (%s)" % [said])
	_check(level["terrain"]["roofs"] == roofs, "the views have them in the terrain")
	var fields := Fields.new()
	fields.load(level["terrain"])
	fields.outdoor = true
	_check(not fields.under_sky(Vector2i(3, 4)) and not fields.under_sky(Vector2i(12, 3)) and fields.under_sky(Vector2i(8, 4)),
			"a roof's cells are under it, as a building's are")
	var turned := Prefab.rotated({"map": map, "config": config}, 1)
	var moved: Array = turned["config"]["roofs"]
	_check(moved.size() == 6 and moved[1]["ridge"] == "z" and (moved[1]["rect"] as Array).slice(2) == [3, 5] and not moved[0].has("ridge"),
			"turned with the map, a roof keeps its cells and its ridge turns with it; one with no rect dropped (%s)" % [moved[1]])
	var piece := LevelMap.new(Vector2i(4, 4))
	for y in 4:
		for x in 4:
			piece.set_cell(Vector2i(x, y), "grass")
	var stamped := Prefab.stamp_changes({"map": piece, "config": {"roofs": [{"rect": [1, 1, 2, 2]}]}}, map, Vector2i(8, 8), config)
	var after: Array = stamped.get("config", {}).get("roofs", [])
	_check(after.size() == 8 and after[7]["rect"] == [9, 9, 2, 2], "a prefab's roof is stamped with it, moved (%s)" % [after.back() if not after.is_empty() else null])


func _test_level_links() -> void:
	print("\n== level links: the player who steps on one goes through ==")
	_main.load_map("test_link_a")
	var player := _player()
	_put(player, Vector2i(3, 1))
	_wait_for_step(player)
	_check(World.try_move(player, Vector2i(1, 0)), "Player steps onto the link")
	await get_tree().process_frame
	await get_tree().process_frame
	var arrived := _player()
	_check(_main.map_name == "test_link_b", "the map is now test_link_b (%s)" % _main.map_name)
	_check(arrived != null and arrived.tile == Vector2i(2, 2), "and Player arrives at its spawn point gate, (2, 2) (%s)" % [arrived.tile if arrived else "none"])
	_check(World.zones.has("test_link_a") and arrived != null and arrived.zone == "test_link_b",
		"in the zone test_link_b; test_link_a stays loaded")


func _test_edge_links() -> void:
	print("
== edge links: walk off one map's edge, arrive at the next one's ==")
	_main.load_map("test_edge_w")
	_check(_main.level["size"] == Vector2i(4, 3) and _main.level["neighbours"] == {"east": "test_edge_e"},
		"test_edge_w is 4 x 3 cells with test_edge_e east (%s, %s)" % [_main.level["size"], _main.level["neighbours"]])
	var player := _player()
	_put(player, Vector2i(3, 0))
	_wait_for_step(player)
	_check(not World.try_move(player, Vector2i(0, -1)), "walking into the north edge, which has no neighbour, is a wall")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_main.map_name == "test_edge_w", "and Player stays (%s)" % _main.map_name)
	player = _player()
	_put(player, Vector2i(3, 2))
	_wait_for_step(player)
	_check(not World.try_move(player, Vector2i(1, 0)), "walking into the east edge is not a step on the map")
	await get_tree().process_frame
	await get_tree().process_frame
	var arrived := _player()
	_check(_main.map_name == "test_edge_e" and arrived != null and arrived.zone == "test_edge_e", "it takes Player to test_edge_e (%s)" % _main.map_name)
	_check(arrived != null and arrived.tile == Vector2i(0, 2), "arriving on its west edge at the same row, (0, 2) (%s)" % [arrived.tile if arrived else "none"])
	_put(arrived, Vector2i(0, 4))
	_wait_for_step(arrived)
	World.try_move(arrived, Vector2i(-1, 0))
	await get_tree().process_frame
	await get_tree().process_frame
	var back := _player()
	_check(_main.map_name == "test_edge_w" and back != null and back.tile == Vector2i(3, 2),
		"back west from row 4, past test_edge_w's last row: its east edge's last cell, (3, 2) (%s)" % [back.tile if back else "none"])


func _test_castle() -> void:
	print("\n== the castle, and the way there from the test room ==")
	var castle := Level.load_level("castle")
	_check(not castle.is_empty() and castle["display_name"] == "The Castle" and castle["warnings"].is_empty(),
			"levels/castle is \"The Castle\" and loads cleanly (%s)" % [castle.get("warnings", "missing")])
	_check(load("res://levels/castle/layout.png") is Image, "its layout.png is imported as an Image")
	_check(str(castle["links"]) == str([{"tile": Vector2i(27, 12), "to_map": "test_room", "to_spawn": "from_castle", "one_way": false},
			{"tile": Vector2i(16, 23), "to_map": "wilds", "to_spawn": "from_castle", "one_way": false}]),
			"its link at (27, 12) goes to the test room, at the foot of its road to the wilds (%s)" % [castle["links"]])
	var room := Level.load_level("test_room")
	var back: Array = (room["links"] as Array).filter(func(link: Dictionary) -> bool: return link["to_map"] == "castle")
	_check(back.size() == 1 and back[0]["tile"] == Vector2i(30, 34) and back[0]["to_spawn"] == "from_test_room",
			"the test room's link at (30, 34) goes to the castle")
	_main.load_map("test_room")
	var player := _player()
	var start := player.tile
	var path: Array = World.find_path(start, Vector2i(30, 34))
	_check(not path.is_empty(), "a path from the start, %s, to that link (%d steps)" % [start, path.size()])
	var turns: Array[Vector2i] = []
	for i in path.size():
		var here: Vector2i = path[i]
		var before: Vector2i = start if i == 0 else path[i - 1]
		var after: Vector2i = path[i + 1] if i + 1 < path.size() else here
		if i + 1 == path.size() or after - here != here - before:
			turns.append(here)
	print("    the way: %s -> %s" % [start, " -> ".join(turns.map(func(t: Vector2i) -> String: return str(t)))])
	_put(player, Vector2i(30, 33))
	_wait_for_step(player)
	_check(World.try_move(player, Vector2i(0, 1)), "Player steps onto it")
	await get_tree().process_frame
	await get_tree().process_frame
	var there := _player()
	_check(World.outdoor and castle["terrain"]["outdoor"] and not room["terrain"]["outdoor"],
			"the castle is outdoors (level.json \"outdoor\"), the test room is not")
	_check(_main.map_name == "castle" and there != null and there.tile == Vector2i(26, 13),
			"and arrives in the castle beside its link, at (26, 13) (%s %s)" % [_main.map_name, there.tile if there else "none"])
	_wait_for_step(there)
	_check(World.try_move(there, Vector2i(1, -1)), "steps onto the castle's link")
	await get_tree().process_frame
	await get_tree().process_frame
	var home := _player()
	_check(not World.outdoor, "and World is indoors again in the test room")
	_check(_main.map_name == "test_room" and home != null and home.tile == Vector2i(30, 33),
			"and is back in the test room beside its link, at (30, 33) (%s %s)" % [_main.map_name, home.tile if home else "none"])


func _test_console() -> void:
	print("\n== the console: map load is zone reset now ==")
	_check(_main.admin_command("map").begins_with("map load is now zone reset"), _main.admin_command("map"))
	_check(_main.admin_command("zone reset nowhere").begins_with("no map nowhere"), "an unknown map is refused")
	var reply: String = _main.admin_command("zone reset test_room")
	_check(reply.begins_with("zone test_room rebuilt: 275 cells") and World.zone.name == "test_edge_w",
			"zone reset test_room rebuilds it, the host's zone untouched: %s" % reply)


# --- Helpers ---------------------------------------------------------------------

static func _same_cells(a: Array, b: Array) -> bool:
	var left := a.duplicate()
	var right := b.duplicate()
	left.sort()
	right.sort()
	return left == right


func _named(entity_name: String) -> Node:
	for entity in World.get_entities():
		if String(entity.name) == entity_name:
			return entity
	return _main.find_child(entity_name, true, false)


func _player() -> Player:
	for entity in World.get_entities():
		if entity is Player and entity.spawned:
			return entity
	return null


func _put(entity: GridEntity, tile: Vector2i) -> void:
	if entity.tile == tile:
		return
	var occupant := World.get_entity_at(tile)
	if occupant != null:
		World.despawn(occupant)
	World._relocate(entity, tile)
	if entity is Player:
		entity.queued_steps.clear()
		entity.has_move_order = false


## Steps the world until [param entity] may move again.
func _wait_for_step(entity: GridEntity) -> void:
	for i in 10:
		if World.tick >= entity.next_move_tick and not World.is_stunned(entity):
			return
		World.step()


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
