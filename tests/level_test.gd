extends Node
## Levels from pixel maps (sim/level.gd): the test room unchanged, a round
## trip through PNG, edge walls and doors from wall and door pixels, heights,
## stairs, falls, sight over lower walls, level links, the console.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const LEGACY := preload("res://tests/legacy_test_room.gd")
const Sheet := preload("res://tools/plan_sheet.gd")
## The floor kinds a pond would lie in (Level.GROUNDS but stone, the paving).
const NATURAL_GROUND: Array[String] = ["grass", "dirt"]
## Levels whose cell water is a test's fixture: the sample's pool and stream
## are what view_test draws cell water from (terrain's side, 553/557).
const CELL_WATER_FIXTURES: Array[String] = ["sample"]
## How far a ledge's curve may lie from the cliff edges it traces (585;
## terrain's bound, as the forest edge's EDGE_BOUND).
const LEDGE_BOUND := 0.45

var _failures := 0
var _main: Node
var _pushes: Array[Dictionary] = []
## Every "party" line this peer's screen was sent (133 amended (1): a line
## said to a player must reach it, not the party log alone).
var _heard: Array[String] = []


func _ready() -> void:
	World.set_process(false)
	Net.port = preload("res://tests/test_ports.gd").of(17790)
	Net.companions = false
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	World.entity_pushed.connect(func(entity: GridEntity, _by: GridEntity, _direction: Vector2i, tiles: int, impact: int, stopped_by: String) -> void:
		_pushes.append({"entity": entity, "tiles": tiles, "impact": impact, "stopped_by": stopped_by}))
	Net.message_received.connect(func(kind: String, data: Dictionary) -> void:
		if kind == "party":
			_heard.append(str(data.get("text", ""))))
	_register_maps()
	_check(_player() == null or World.free_body(_player()), "a player is a free body: every player's walk below is one (6b, 703)")

	_test_test_room_unchanged()
	_test_every_level()
	_test_round_trip()
	_test_edges_and_doors()
	_test_markers()
	_test_heights_and_stairs()
	_test_pit_ways_out()
	_test_mine_track()
	_test_step_cache()
	_test_layout_sense()
	_test_castle_hold()
	_test_sense_everywhere()
	_test_hollow_chiefs()
	_test_falls()
	_test_sight_over_walls()
	_test_hills()
	_test_admin_move()
	_test_solid()
	_test_forest()
	_test_buildings()
	_test_field()
	_test_fold()
	_test_kinds()
	_test_canopy()
	_test_building_links()
	_test_building_level_link()
	_test_umbrage_locker()
	_test_beds()
	_test_place_towns()
	_test_regenerate_mark()
	_test_town_walls()
	_test_roofs()
	await _test_level_links()
	await _test_links_kept_clear()
	await _test_sealed_link()
	await _test_temple_stair()
	_test_temple_town()
	_test_barrow_won()
	await _test_hall_door()
	await _test_hidden_niche()
	await _test_robbers_latch()
	_test_double_doors()
	_test_camp_chest()
	_test_band()
	_test_crypt_ways()
	_test_arrival_rule()
	_test_giver_rule()
	_test_deep_crypt()
	_test_chest_guardable()
	_test_crypt_spacing()
	_test_hall_shortcut()
	await _test_throne_way_held()
	await _test_throne_home()
	_test_barrow_quest()
	await _test_knights_altar()
	await _test_altar_charges()
	await _test_full_circle_on()
	_test_quest_card_place()
	_test_decor()
	_test_barrow_level()
	_test_castle_halls_level()
	_test_tower_levels()
	await _test_edge_links()
	_test_console()
	await _test_castle()
	await _test_barrow_exits()
	await _test_spawn_near()
	_test_reed_pond()
	_test_kind_lists()

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
	# A sealed link (decision 540): the same way, open to the marked alone.
	Level.register("test_link_s", Level.image_from_rows(_rows(1, 4, 1, 1), {Vector2i(1, 1): "start", Vector2i(4, 1): "link"}), null,
		{"links": [{"at": [4, 1], "to_map": "test_link_b", "to_spawn": "gate", "sealed": "draugr"}]})
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
		elif b["script"] == Level.MONSTER:
			b["props"]["max_hp"] = 20  # 823: the imp row's max hp, a kindless monster's body.
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
		# A dungeon's arrangement (a level marked to regenerate) keeps the
		# width rule (612) as its generations do: no passage one cell wide.
		if not level.is_empty() and not level["regenerate"].is_empty():
			var narrow := Level.narrow_runs(level["terrain"])
			_check(narrow.is_empty(), "%s: no passage one cell wide in its arrangement (%s)" % [folder, narrow.slice(0, 8)])
	_test_built_water()
	_test_ledges()
	_test_link_cues()
	_test_clearing()
	_test_unbuild()
	_test_felled_walls()
	_test_plots()
	_test_unplot()
	_test_refuges()
	_test_held()
	_test_bridges()
	_test_herders()
	_test_forest_healer()
	_test_world_plane()
	_test_safe_paths()
	_test_fill_hills()
	_test_wilds_on_foot()
	_test_farm_and_barrow()
	_test_hearth()
	_test_town_warm_rests()
	_test_fill_hills_sights()
	_test_relaid()
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
		# A piece of map has no start of its own, and its places work for
		# the level's town (the Old Tower's "store"): those warnings are expected.
		var warnings: Array = Level.parse(prefab["map"].to_image(), null, prefab["config"])["warnings"].filter(
				func(warning: String) -> bool: return not warning.begins_with("no player start") and not warning.ends_with("no stockpile place of that key here; it works for none"))
		_check(image_ok and warnings.is_empty(), "%s: %s cells (%s)" % [prefab_name, prefab["map"].size, warnings])


## Natural water is a curve (Jeff's rule); water no "waters" curve lays is
## built, and terrain draws it square and still (568 amended). So every
## curveless body of water in a level lies under a building or in paving (a
## well, a basin): none of it beside natural ground, where a pond would be.
## The cell-water fixtures (CELL_WATER_FIXTURES) are left out.
func _test_built_water() -> void:
	print("\n== water no curve lays is built: under a building, or no natural ground beside it ==")
	for folder in DirAccess.get_directories_at(Level.DIR):
		if Level.DIR + folder + "/" == Prefab.DIR or not FileAccess.file_exists(Level.DIR + folder + "/layout.png") or folder in CELL_WATER_FIXTURES:
			continue
		var level := Level.load_level(folder)
		if level.is_empty():
			continue
		var terrain: Dictionary = level["terrain"]
		var wet := {}
		for key in ["water", "fords", "bridged"]:
			for cell: Vector2i in terrain.get(key, []):
				wet[cell] = true
		var curved := {}
		for water: Dictionary in terrain.get("waters", []):
			curved.merge(Curves.cells(water["curve"], water["closed"]))
		var housed := {}
		for building: Dictionary in level["buildings"]:
			for cell in Level.building_cells(building):
				housed[cell] = true
		var seen := {}
		var bodies := 0
		var loose: Array[Vector2i] = []
		for start: Vector2i in wet:
			if seen.has(start):
				continue
			var body: Array[Vector2i] = [start]
			seen[start] = true
			var natural := false
			var index := 0
			while index < body.size():
				var cell := body[index]
				index += 1
				natural = natural or curved.has(cell)
				for step: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
					var next := cell + step
					if wet.has(next) and not seen.has(next):
						seen[next] = true
						body.append(next)
			if natural:
				continue
			bodies += 1
			for cell in body:
				if housed.has(cell):
					continue
				for step: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
					var next := cell + step
					if not wet.has(next) and str(terrain["kinds"].get(next, "")) in NATURAL_GROUND:
						loose.append(cell)
						break
		_check(loose.is_empty(), "%s: %d curveless water bodies, each under a building or with no natural ground beside it (beside it at %s)" % [
				folder, bodies, loose.slice(0, 4)])


## Decision 585: each level's "ledges" are its relief's as it is (traced
## again, the same), and stay within LEDGE_BOUND of the cliff edges they
## trace both ways: terrain draws the face on the curve while the sim's
## cliff stays on the cell's edge, so past half a cell a walked cell would
## look cliffed or a cliff walkable.
func _test_ledges() -> void:
	print("\n== ledges: traced from the relief as it is, within %.2f of its cliff edges both ways ==" % LEDGE_BOUND)
	var traced_any := 0
	for folder in DirAccess.get_directories_at(Level.DIR):
		if Level.DIR + folder + "/" == Prefab.DIR or not FileAccess.file_exists(Level.DIR + folder + "/layout.png"):
			continue
		var level := Level.load_level(folder)
		if level.is_empty() or not level["terrain"].has("relief"):
			continue
		var terrain: Dictionary = level["terrain"]
		var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(Level.DIR + folder + "/level.json"))
		var stored: Array = (config as Dictionary).get("ledges", []) if config is Dictionary else []
		var traced := Level.ledges_of(terrain)
		traced_any += traced.size()
		_check(JSON.stringify(stored) == JSON.stringify(traced), "%s: its %d ledges are its relief's (traced again: %d)" % [folder, stored.size(), traced.size()])
		# The cliff edges as trace_ledges takes them: walked or wet cells, no bank.
		var wet := {}
		var ground := {}
		for cell: Vector2i in terrain["floor"]:
			ground[cell] = true
		for key in ["water", "fords", "bridged"]:
			for cell: Vector2i in terrain.get(key, []):
				ground[cell] = true
				wet[cell] = true
		var edges: Array = []
		for cell: Vector2i in ground:
			for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var next := cell + step
				if ground.has(next) and wet.has(cell) == wet.has(next) and Relief.cliff_between(
						Relief.at(terrain["relief"], terrain["relief_size"], cell), Relief.at(terrain["relief"], terrain["relief_size"], next)):
					var corner := Vector2(cell) + Vector2(0.5, 0.5)
					edges.append([corner - Vector2(0, 1) if step.x == 1 else corner - Vector2(1, 0), corner])
		var astray := 0.0
		var unled := 0.0
		for ledge: Dictionary in terrain["ledges"]:
			for point: Vector2 in ledge["curve"]["points"]:
				var near := INF
				for edge: Array in edges:
					near = minf(near, point.distance_to(Geometry2D.get_closest_point_to_segment(point, edge[0], edge[1])))
				astray = maxf(astray, near)
		for edge: Array in edges:
			var middle: Vector2 = (edge[0] + edge[1]) / 2.0
			var near := INF
			for ledge: Dictionary in terrain["ledges"]:
				var points: PackedVector2Array = ledge["curve"]["points"]
				for i in range(1, points.size()):
					near = minf(near, middle.distance_to(Geometry2D.get_closest_point_to_segment(middle, points[i - 1], points[i])))
			unled = maxf(unled, near)
		_check(astray <= LEDGE_BOUND and (edges.is_empty() or unled <= LEDGE_BOUND),
				"%s: every ledge point within %.2f of a cliff edge (worst %.2f), every cliff edge of a ledge (worst %.2f)" % [folder, LEDGE_BOUND, astray, unled if not edges.is_empty() else 0.0])
	_check(traced_any > 0, "the levels with relief have ledges (%d)" % traced_any)


## Decision 589: every link shows where it leads, picked from where it goes.
func _test_link_cues() -> void:
	print("
== link cues: an arch overland, stairs between depths, a slab where sealed, nothing on a door ==")
	var cue_of := func(level_name: String, at: Vector2i) -> Dictionary:
		for cue: Dictionary in Level.load_level(level_name)["terrain"]["link_cues"]:
			if cue["tile"] == at:
				return cue
		return {}
	var castle_way: Dictionary = cue_of.call("wilds", Vector2i(128, 20))
	_check(castle_way.get("cue") == "arch" and castle_way.get("facing") == Vector2i(0, -1) and castle_way.get("variant") == 2,
			"the wilds' way north (the castle's till 745, the foothills' since): a stone arch facing north, out to it (%s)" % [castle_way])
	var gate: Dictionary = cue_of.call("castle", Vector2i(16, 23))
	_check(gate.get("cue") == "waystones" and gate.get("facing") == Vector2i(0, 1), "the castle's way out at its edge: waystones (%s)" % [gate])
	_check(cue_of.call("barrow_deep", Vector2i(49, 1)).get("cue") == "up" and cue_of.call("barrow_deep", Vector2i(49, 77)).is_empty(),
			"the barrow's depths: the Ossuary's stair up to the shallower; behind the throne no way and no slab (896 switched on: the throne is the way home)")
	_check(cue_of.call("wilds", Vector2i(160, 160)).get("cue") == "none" and cue_of.call("wilds", Vector2i(199, 199)).get("cue") == "down"
		and cue_of.call("barrow", Vector2i(30, 8)).is_empty() and cue_of.call("barrow", Vector2i(31, 52)).get("cue") == "up",
			"the mound's door is its own cue; the chapel stair (the temple's back corner, 832 switched on: open, into the First Hall) a way down; no way down from the First Hall (896 switched on: the short cut in dropped), the camp's breach a way up")
	var wilds := Level.load_level("wilds")
	_check(wilds["links"].all(func(link: Dictionary) -> bool: return str(link.get("cue", "")) in Level.CUES),
			"each link carries its cue for the big map")
	_check(Level.CUE_SLOTS.values().all(func(slot: String) -> bool: return ArtKit.has(slot)), "each cue's piece is in the kit (%s)" % [Level.CUE_SLOTS])


## Decision 591: a woodcut fells the grove's edge nearest the town, the
## cells regrow a stage a season from the edge in, back to the level's trunk;
## built over, never; kept in the snapshot.
## 591 amended (terrain's find): a felled trunk's cell is floor like any,
## its outline walls to the floor beside it gone (in the terrain the views
## draw and in the walk), walls to the trunks still standing made, and all
## back as they were when it grows back to a trunk.
func _test_felled_walls() -> void:
	print("\n== felled cells: their outline walls open to the floor beside them, walked into; back when regrown ==")
	var size := Vector2i(16, 10)
	var colour := func(meaning: String) -> Color: return Color(str(Level.LEGEND[meaning]))
	var image := Image.create_empty(size.x * 2 + 1, size.y * 2 + 1, false, Image.FORMAT_RGBA8)
	image.fill(colour.call("grass"))
	for y in range(3, 7):
		for x in range(8, 12):
			image.set_pixel(x * 2, y * 2, colour.call("void"))
	# An authored wall between the grove's (8, 3) and the grass west of it.
	image.set_pixel(7 * 2 + 1, 3 * 2, colour.call("wall"))
	image.set_pixel(2, 2, colour.call("start"))
	Level.register("felled_walls", image, null, {"name": "Felled", "outdoor": true})
	var terrain: Dictionary = Level.load_level("felled_walls")["terrain"]
	var edge := func(cell: Vector2i, way: Vector2i) -> int: return int(terrain["edges"].get(Terrain.edge_key(cell, way), Terrain.Edge.OPEN))
	_check(edge.call(Vector2i(8, 4), Vector2i(-1, 0)) == Terrain.Edge.WALL and terrain["outline"].has(Terrain.edge_key(Vector2i(8, 4), Vector2i(-1, 0)))
			and not terrain["outline"].has(Terrain.edge_key(Vector2i(8, 3), Vector2i(-1, 0))),
			"parsed: the grove's edge walled by the outline rule, the wall pixel's not counted as outline")
	var felled := [[8, 3, "stump"], [8, 4, "stump"], [8, 5, "grass"]]
	var changes := Clearing.apply_cells(terrain, felled)
	_check(edge.call(Vector2i(8, 4), Vector2i(-1, 0)) == Terrain.Edge.OPEN and edge.call(Vector2i(8, 5), Vector2i(-1, 0)) == Terrain.Edge.OPEN
			and edge.call(Vector2i(8, 4), Vector2i(0, -1)) == Terrain.Edge.OPEN,
			"felled: open to the grass and to each other (%d edges changed)" % changes.size())
	_check(edge.call(Vector2i(8, 4), Vector2i(1, 0)) == Terrain.Edge.WALL and edge.call(Vector2i(8, 5), Vector2i(0, 1)) == Terrain.Edge.WALL,
			"walled to the trunks still standing east and south of them")
	_check(edge.call(Vector2i(8, 3), Vector2i(-1, 0)) == Terrain.Edge.WALL, "the authored wall stays")
	# The walk: the server's own change, a loaded zone's.
	_check(_main.load_map("felled_walls"), "the grove loads")
	_check(World.find_path(Vector2i(2, 4), Vector2i(8, 4), true).is_empty(), "before: no way into the grove")
	_main._on_clearing_changed("felled_walls", felled)
	var into := World.find_path(Vector2i(2, 4), Vector2i(8, 4), true)
	_check(not into.is_empty() and not World.find_path(Vector2i(2, 4), Vector2i(8, 5), true).is_empty(),
			"felled: walked into from the grass (%d steps)" % into.size())
	_main._on_clearing_changed("felled_walls", [[8, 3, Clearing.TRUNK], [8, 4, Clearing.TRUNK], [8, 5, Clearing.TRUNK]])
	var walled := int(_main._terrain["edges"].get(Terrain.edge_key(Vector2i(8, 4), Vector2i(-1, 0)), Terrain.Edge.OPEN)) == Terrain.Edge.WALL
	_check(World.find_path(Vector2i(2, 4), Vector2i(8, 4), true).is_empty() and walled,
			"regrown to trunks: walled again, no way in")
	_main.load_map("test_room")


func _test_clearing() -> void:
	print("
== clearing: felled at the edge nearest the town, regrown a season a stage, back to the trunk ==")
	# 24 x 14 of grass, a grove of trunks (void) at x 9..15, y 4..9.
	var size := Vector2i(24, 14)
	var colour := func(meaning: String) -> Color: return Color(str(Level.LEGEND[meaning]))
	var image := Image.create_empty(size.x * 2 + 1, size.y * 2 + 1, false, Image.FORMAT_RGBA8)
	image.fill(colour.call("grass"))
	for y in range(4, 10):
		for x in range(9, 16):
			image.set_pixel(x * 2, y * 2, colour.call("void"))
	image.set_pixel(2, 2, colour.call("start"))
	Level.register("clearing_grove", image, null, {"name": "Grove", "outdoor": true})
	var day := [0]
	var clearing := Clearing.new()
	clearing.clock = func() -> int: return day[0]
	var told: Array = []
	clearing.changed.connect(func(zone: String, cells: Array) -> void: told.append_array(cells))
	_check(clearing.fell("clearing_grove", Vector2i(8, 6), Vector2i(1, 6), 3) == 3, "a woodcut fells three trunks")
	var cells: Array = clearing.felled["clearing_grove"].keys()
	_check(cells.all(func(cell: Vector2i) -> bool: return cell.x == 9) and told.size() == 3 and told.all(func(each: Array) -> bool: return each[2] == "stump"),
			"the grove's west edge, nearest the town, each a stump, told (%s)" % [cells])
	var terrain: Dictionary = Level.load_level("clearing_grove")["terrain"]
	clearing.apply("clearing_grove", terrain)
	_check(cells.all(func(cell: Vector2i) -> bool: return cell in terrain["floor"] and terrain["kinds"][cell] == "dirt" and terrain["clearing"][cell] == "stump"),
			"applied: floor, bare dirt, terrain[\"clearing\"] their stage")
	_check(clearing.fell("clearing_grove", Vector2i(2, 12), Vector2i(1, 12), 2) == 0, "no trunk within reach of a far site: nothing felled")
	var stepped := clearing.step_site("clearing_grove", Vector2i(2, 12))
	_check(stepped != World.NO_CELL and not stepped in terrain.get("water", []) and Vector2(stepped - Vector2i(9, 9)).length() <= 2.0,
			"the lot steps out beside the nearest standing trunk (%s)" % stepped)
	# Built over: a felled cell under something built never grows back.
	var built: Vector2i = cells[0]
	clearing._base_of("clearing_grove")["built"][built] = true
	told.clear()
	var stage_days := Season.season_days
	day[0] = stage_days
	clearing.daily(day[0])
	_check(told.size() == 2 and told.all(func(each: Array) -> bool: return each[2] == "grass"), "a season on: the two beside standing trunks are grass (%s)" % [told])
	for season in range(2, 12):
		day[0] = stage_days * season
		clearing.daily(day[0])
	var left: Dictionary = clearing.felled["clearing_grove"]
	_check(left.size() == 1 and left.has(built) and told.filter(func(each: Array) -> bool: return each[2] == Clearing.TRUNK).size() == 2,
			"grown back: trunks again, the level's own; the built-over one stays felled (%s)" % [left])
	var again := Clearing.new(clearing.to_dict())
	_check(again.felled == clearing.felled, "kept in the snapshot and read back the same (%s)" % [clearing.to_dict()])
	# A save restored on a level changed since (758, terrain's find): a cell no
	# trunk now (grass, past the edge) is dropped; a trunk, or the level's own floor (1), stays.
	var restored := Clearing.new({"clearing_grove": {"10,5": [1, 0], "6,6": [1, 0], "30,5": [1, 0], "5,6": [0, 0, 1]}})
	var fresh: Dictionary = Level.load_level("clearing_grove")["terrain"]
	restored.apply("clearing_grove", fresh)
	var kept: Array = restored.felled["clearing_grove"].keys()
	kept.sort()
	_check(kept == [Vector2i(5, 6), Vector2i(10, 5)] and not Vector2i(30, 5) in fresh["floor"] and fresh["clearing"].size() == 2,
		"restored on a changed level: the trunk and the level's own floor stay, grass and a cell past the edge go (%s)" % [kept])
	Level.unregister("clearing_grove")


## 649, terrain's side: a ruin's footprint given back to the forest
## (Clearing.unbuild), its level floor grown to trunks that stay, kept over a
## reload; a woodcut fells one as any trunk; build takes cells back.
func _test_unbuild() -> void:
	print("\n== unbuild: a ruin's ground back to the forest, kept trunks, built again ==")
	var size := Vector2i(24, 14)
	var colour := func(meaning: String) -> Color: return Color(str(Level.LEGEND[meaning]))
	var image := Image.create_empty(size.x * 2 + 1, size.y * 2 + 1, false, Image.FORMAT_RGBA8)
	image.fill(colour.call("grass"))
	for y in range(4, 10):
		for x in range(9, 16):
			image.set_pixel(x * 2, y * 2, colour.call("void"))
	image.set_pixel(2, 2, colour.call("start"))
	Level.register("ruin_grove", image, null, {"name": "Ruin Grove", "outdoor": true})
	var zone := "ruin_grove"
	var day := [0]
	var clearing := Clearing.new()
	clearing.clock = func() -> int: return day[0]
	var told: Array = []
	clearing.changed.connect(func(_zone: String, cells: Array) -> void: told.append_array(cells))
	# The ruin: three grass cells by the grove, one of them the level's own
	# building's (built over as made).
	var ruin: Array[Vector2i] = [Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6)]
	clearing._base_of(zone)["built"][ruin[0]] = true
	_check(clearing.unbuild(zone, ruin, 0) == 3 and told.size() == 3 and told.all(func(each: Array) -> bool: return each[2] == "stump")
			and clearing.given_back[zone].has(ruin[0]) and ruin.all(func(cell: Vector2i) -> bool: return (clearing.felled[zone][cell] as Array).size() == 3),
			"unbuilt: three stumps from the day given, told; the level's building's cell given back")
	_check(clearing.unbuild(zone, [Vector2i(12, 6)], 0) == 0, "a standing trunk: nothing to unbuild")
	told.clear()
	for season in range(1, 12):
		day[0] = Season.season_days * season
		clearing.daily(day[0])
	var trunks := told.filter(func(each: Array) -> bool: return each[2] == Clearing.TRUNK)
	_check(trunks.size() == 3 and ruin.all(func(cell: Vector2i) -> bool: return clearing._kept(zone, cell))
			and clearing.cells_of(zone).filter(func(each: Array) -> bool: return each[2] == Clearing.TRUNK).size() == 3,
			"grown back: the level's own floor three trunks kept, \"trunk\" in the zone's cells (%s)" % [clearing.felled[zone]])
	var terrain: Dictionary = Level.load_level(zone)["terrain"]
	clearing.apply(zone, terrain)
	_check(ruin.all(func(cell: Vector2i) -> bool: return not cell in terrain["floor"] and not terrain["clearing"].has(cell)),
			"applied: the kept trunks are no floor, no stage")
	var walled := ruin.all(func(cell: Vector2i) -> bool:
		return int(terrain["edges"].get(Terrain.edge_key(cell, Vector2i(0, 1)), Terrain.Edge.OPEN)) == Terrain.Edge.WALL)
	_check(walled, "the outline walled round them, the floor's edge south of them")
	var again := Clearing.new(clearing.to_dict())
	_check(again.felled == clearing.felled and again.given_back == clearing.given_back and ruin.all(func(cell: Vector2i) -> bool: return again._kept(zone, cell)),
			"kept in the snapshot and read back the same (%s)" % [clearing.to_dict()[zone]])
	# Told a client: "trunk" kept, the level's floor made void on a reload.
	var client: Dictionary = Level.load_level(zone)["terrain"]
	Clearing.apply_cells(client, clearing.cells_of(zone))
	_check(ruin.all(func(cell: Vector2i) -> bool: return not cell in client["floor"]), "a client's terrain from the zone's cells: the same trunks")
	# A woodcut takes one as any edge trunk; it grows back kept again.
	told.clear()
	_check(clearing.fell(zone, Vector2i(7, 8), Vector2i(7, 8), 1) == 1 and told.size() == 1, "a woodcut fells one of them")
	var cut := Vector2i(int(told[0][0]), int(told[0][1]))
	_check(ruin.has(cut) and (clearing.felled[zone][cut] as Array).size() == 3 and not clearing._kept(zone, cut),
			"felled at a stump, still the level's floor's (%s)" % [clearing.felled[zone][cut]])
	# Built again: the cells grass, held, never growing back.
	told.clear()
	clearing.build(zone, ruin)
	_check(told.size() == 2 and told.all(func(each: Array) -> bool: return each[2] == "grass" and Vector2i(int(each[0]), int(each[1])) != cut)
			and ruin.all(func(cell: Vector2i) -> bool: return clearing.built_over[zone].has(cell)),
			"built: the two kept trunks grass, the felled one held at its stage, all three built over (%s)" % [told])
	told.clear()
	for season in range(12, 20):
		day[0] = Season.season_days * season
		clearing.daily(day[0])
	_check(told.is_empty() and Clearing.new(clearing.to_dict()).built_over == clearing.built_over, "built over: they never grow, kept in the snapshot")
	# A ruin over a laid plot: the whole plot dropped first (maps' unplot),
	# then its cells the forest's.
	var plot := clearing.lay_plot(zone, "town", "hut", Rect2i(2, 9, 4, 4), Vector2i(0, 1))
	var dropped: Array = []
	clearing.unplotted.connect(func(_zone: String, gone: Dictionary) -> void: dropped.append(gone))
	told.clear()
	_check(not plot.is_empty() and clearing.unbuild(zone, [Vector2i(3, 10), Vector2i(4, 11)], day[0]) == 2 and dropped.size() == 1
			and dropped[0]["rect"] == plot["rect"] and clearing.plots_of(zone).is_empty() and not clearing._plotted(zone).has(Vector2i(2, 9))
			and told.size() == 2,
			"a ruin over a plot: the plot dropped, its ring and all, then the two cells stumps (%s)" % [told])
	Level.unregister(zone)


func _test_plots() -> void:
	print("\n== plots: a class's footprint and ring on cleared level ground nearest the store, two cells apart ==")
	# 44 x 24 of forest (void) but a field of grass at x 2..11, y 2..21; the
	# store at (6, 4). Past EDGE the field is 8 across: an S plot's ring.
	var size := Vector2i(44, 24)
	var colour := func(meaning: String) -> Color: return Color(str(Level.LEGEND[meaning]))
	var image := Image.create_empty(size.x * 2 + 1, size.y * 2 + 1, false, Image.FORMAT_RGBA8)
	image.fill(colour.call("void"))
	for y in range(2, 22):
		for x in range(2, 12):
			image.set_pixel(x * 2, y * 2, colour.call("grass"))
	image.set_pixel(6 * 2, 3 * 2, colour.call("start"))
	Level.register("plot_field", image, null, {"name": "Field", "outdoor": true})
	var store := Vector2i(6, 4)
	var clearing := Clearing.new()
	clearing.clock = func() -> int: return 0
	var floor_of := func(rect: Rect2i) -> bool:
		var base: Dictionary = clearing._base_of("plot_field")
		return Level.rect_cells(rect).all(func(cell: Vector2i) -> bool: return base["floor"].has(cell) or clearing.felled.get("plot_field", {}).has(cell))
	var first := clearing.plot_for("plot_field", "S", store)
	_check(first.size == Vector2i(8, 8) and floor_of.call(first) and first.position.x == 4, "an S plot: its 6 x 6 and a ring, on the field's grass (%s)" % first)
	_check(clearing.lay_plot("plot_field", "plot_field/store", "hut", first, Clearing.facing_for(first, "S", store))["facing"].y != 0,
		"laid, facing the store along the field")
	var second := clearing.plot_for("plot_field", "S", store)
	var a := first.grow(-1)
	var b := second.grow(-1)
	var gap := maxi(maxi(b.position.x - a.end.x, a.position.x - b.end.x), maxi(b.position.y - a.end.y, a.position.y - b.end.y))
	_check(second.has_area() and floor_of.call(second) and gap >= Clearing.PLOT_GAP, "a second beside it, two cells between the footprints (%s, gap %d)" % [second, gap])
	clearing.lay_plot("plot_field", "plot_field/store", "shed", second, Clearing.facing_for(second, "S", store))
	_check(not clearing.plot_for("plot_field", "S", store).has_area(), "a third: no cleared ground left, none (the forest stands)")
	# Felled: x 12..21, y 4..19 of the forest, now grass.
	clearing.felled["plot_field"] = {}
	for y in range(4, 20):
		for x in range(12, 22):
			clearing.felled["plot_field"][Vector2i(x, y)] = [1, 0]
	var third := clearing.plot_for("plot_field", "S", store)
	_check(third.has_area() and floor_of.call(third) and third.position.x >= 12, "felled, a third fits on the cleared forest (%s)" % third)
	var base: Dictionary = clearing._base_of("plot_field")
	for y in range(4, 20):
		base["roads"][Vector2i(17, y)] = true
	_check(not clearing.plot_for("plot_field", "S", store).has_area(), "a road across it: no footprint on the road")
	base["roads"] = {}
	base["heights"] = {Vector2i(16, 8): 1}
	third = clearing.plot_for("plot_field", "S", store)
	_check(third.has_area() and not third.has_point(Vector2i(16, 8)), "a step in the ground: the plot is laid off it, on one height (%s)" % third)
	base["heights"] = {}
	clearing.lay_plot("plot_field", "plot_field/store", "hut", third, Clearing.facing_for(third, "S", store))
	clearing.daily(Season.season_days * 20)
	_check(Level.rect_cells(third).all(func(cell: Vector2i) -> bool: return clearing.felled["plot_field"].has(cell)), "its felled cells never grow back")
	var again := Clearing.new(clearing.to_dict(), clearing.plots_to_dict())
	_check(again.plots_of("plot_field") == clearing.plots_of("plot_field") and again.plots_of("plot_field").size() == 3,
		"kept in the snapshot and read back the same (%s)" % [clearing.plots_to_dict()])
	var terrain: Dictionary = Level.load_level("plot_field")["terrain"].duplicate(true)
	clearing.apply("plot_field", terrain)
	var built: Array = terrain.get("plot_buildings", [])
	var theirs := built.filter(func(each: Dictionary) -> bool: return each["town_id"] == "plot_field/store" and each.get("plot", false))
	_check(terrain["plots"].size() == 3 and built.size() == 3 and theirs.size() == 3,
		"applied: listed for the views, each its kind's building, its town's (%s)" % [built.map(func(each: Dictionary) -> Rect2i: return each["rect"])])
	var house: Dictionary = built[0] if not built.is_empty() else {}
	var edges: Dictionary = Level.plot_edges(house) if not house.is_empty() else {}
	_check(not house.is_empty() and first.grow(-1).encloses(house["rect"]) and edges.values().has(Terrain.Edge.DOOR)
			and edges.keys().all(func(key: Vector3i) -> bool: return terrain["edges"].get(key) == edges[key]),
		"its walls and door laid in the edges, in the footprint (%s)" % [house.get("rect")])
	Level.unregister("plot_field")


## A plot dropped (649, maps' side): its building and the edges it laid off
## the terrain, its cells growing back; live, off the walk as well, and a
## client told it is gone.
func _test_unplot() -> void:
	print("
== unplot: a plot dropped, its building and edges off, its cells growing back, the clients told ==")
	var size := Vector2i(30, 20)
	var colour := func(meaning: String) -> Color: return Color(str(Level.LEGEND[meaning]))
	var image := Image.create_empty(size.x * 2 + 1, size.y * 2 + 1, false, Image.FORMAT_RGBA8)
	image.fill(colour.call("void"))
	for y in range(2, 18):
		for x in range(2, 12):
			image.set_pixel(x * 2, y * 2, colour.call("grass"))
	image.set_pixel(6 * 2, 3 * 2, colour.call("start"))
	Level.register("unplot_field", image, null, {"name": "Field", "outdoor": true})
	# The forest felled east of the field, x 12..21, y 4..15; the plot on it.
	var felled := {}
	for y in range(4, 16):
		for x in range(12, 22):
			felled[Vector2i(x, y)] = [1, 0]
	var rect := Rect2i(13, 5, 8, 8)
	var clearing := Clearing.new()
	clearing.clock = func() -> int: return 0
	clearing.felled["unplot_field"] = felled.duplicate(true)
	var heard := []
	clearing.unplotted.connect(func(_zone: String, plot: Dictionary) -> void: heard.append(plot))
	clearing.lay_plot("unplot_field", "unplot_field/store", "hut", rect, Vector2i(0, 1))
	var terrain: Dictionary = Level.load_level("unplot_field")["terrain"].duplicate(true)
	clearing.apply("unplot_field", terrain)
	var built: Array = terrain.get("plot_buildings", [])
	var laid: Array = (built[0] as Dictionary).get("laid", []) if not built.is_empty() else []
	_check(built.size() == 1 and not laid.is_empty() and laid.all(func(key: Vector3i) -> bool: return terrain["edges"].has(key)),
		"laid: its building, and the %d edges it laid" % laid.size())
	var dropped := clearing.unplot("unplot_field", rect)
	_check(dropped.get("rect") == rect and heard.size() == 1 and clearing.plots_of("unplot_field").is_empty() and clearing.plot_at("unplot_field", Vector2i(15, 8)).is_empty(),
		"dropped: told, no plot left there")
	_check(clearing.unplot("unplot_field", rect).is_empty() and heard.size() == 1, "dropped again: nothing, nothing told")
	var building := Clearing.unlay_plot(terrain, rect)
	_check(not building.is_empty() and terrain["plot_buildings"].is_empty() and terrain["plots"].is_empty()
			and laid.all(func(key: Vector3i) -> bool: return not terrain["edges"].has(key)),
		"taken off the terrain: its building and its edges")
	for step in range(1, 60):
		clearing.daily(step * Season.season_days * 2)
	var back := Level.rect_cells(rect).filter(func(cell: Vector2i) -> bool: return not clearing.felled.get("unplot_field", {}).has(cell))
	_check(back.size() == rect.get_area(), "its cells grown back to forest (%d of %d)" % [back.size(), rect.get_area()])
	# Live: the zone loaded, the main clearing's plot laid and dropped.
	if World.clearing == null:
		_check(false, "World.clearing is set")
		Level.unregister("unplot_field")
		return
	World.clearing.felled["unplot_field"] = felled.duplicate(true)
	_check(_main.load_map("unplot_field"), "the field loads")
	World.clearing.lay_plot("unplot_field", "unplot_field/store", "hut", rect, Vector2i(0, 1))
	var walk: Dictionary = World._edges
	var on_walk := laid.filter(func(key: Vector3i) -> bool: return walk.has(key))
	var town_built: Array = World.fields.town_buildings.filter(func(each: Dictionary) -> bool: return each.get("plot", false))
	_check(on_walk.size() == laid.size() and town_built.size() == 1, "live: its edges on the walk (%d of %d), its building a town building" % [on_walk.size(), laid.size()])
	World.clearing.unplot("unplot_field", rect)
	on_walk = laid.filter(func(key: Vector3i) -> bool: return World._edges.has(key))
	town_built = World.fields.town_buildings.filter(func(each: Dictionary) -> bool: return each.get("plot", false))
	_check(on_walk.is_empty() and town_built.is_empty() and (_main._terrain.get("plot_buildings", []) as Array).is_empty(),
		"live, dropped: off the walk, the town buildings and the terrain drawn")
	# A client told it laid, then gone.
	var wire := Clearing.plot_wire({"town": "unplot_field/store", "kind": "hut", "use": "hut", "rect": rect, "facing": Vector2i(0, 1)})
	_main._on_clearing({"zone": "unplot_field", "cells": [], "plots": [wire]})
	var told: int = (_main._plots_told.get("unplot_field", []) as Array).size()
	_main._on_clearing({"zone": "unplot_field", "cells": [], "gone": [wire]})
	_check(told == 1 and (_main._plots_told.get("unplot_field", []) as Array).is_empty(), "a client: told it laid, then gone")
	World.clearing.felled.erase("unplot_field")
	World.clearing.plots.erase("unplot_field")
	_main._plots_told.erase("unplot_field")
	_main._clearing_told.erase("unplot_field")
	_main.load_map("test_room")
	Level.unregister("unplot_field")


## Held on its own map (651, step 1): its link to the wilds both ways,
## the Old Tower stamped (its door reached over the bridge, and over the
## ford with the bridge gone), the store's cell reserved on a level pad,
## no town yet (no houses, the fort working for no town).
## Every bridge in the world's levels (those on the world plane; Jeff on the
## trailer, the wilds' on a bend: "holo-bridge"): two cells wide, square
## across a run of river (water on past both its long sides), its ends on
## dry banks, and on road where the level has roads, so a walker steps off
## it onto the way. (levels/sample's one-cell bridge is a fixture.)
func _test_bridges() -> void:
	print("
== bridges: square across the water, the road at both ends ==")
	var found := 0
	var plane: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://levels/world_plane.json"))
	for name: String in plane["zones"]:
		var path := "res://levels/%s/level.json" % name
		if not FileAccess.file_exists(path) or not FileAccess.get_file_as_string(path).contains("\"slot\": \"bridge\""):
			continue
		var level := Level.load_level(name)
		var terrain: Dictionary = level["terrain"]
		var wet := {}
		for key in ["water", "bridged", "fords"]:
			for cell: Vector2i in terrain.get(key, []):
				wet[cell] = true
		var roads := {}
		for road: Dictionary in terrain.get("roads", []):
			roads.merge(Curves.cells(road["curve"], false))
		var bridges: Array = level["buildings"].filter(func(building: Dictionary) -> bool: return building["slot"] == Level.BRIDGE)
		var left_out: Array = level["warnings"].filter(func(warning: String) -> bool: return warning.contains("bridge"))
		_check(not bridges.is_empty() and left_out.is_empty(), "%s: its bridges are laid (%s)" % [name, left_out])
		for bridge: Dictionary in bridges:
			found += 1
			var rect: Rect2i = bridge["rect"]
			var along := Vector2i(absi(bridge["facing"].x), absi(bridge["facing"].y))
			var side := Vector2i(along.y, along.x)
			var length := rect.size.x if along.x != 0 else rect.size.y
			var width := rect.size.y if along.x != 0 else rect.size.x
			var beside := [0, 0]
			for i in length:
				var cell := rect.position + along * i
				if wet.has(cell - side):
					beside[0] += 1
				if wet.has(cell + side * width):
					beside[1] += 1
			var ends: Array[Vector2i] = []
			for row in width:
				ends.append(rect.position - along + side * row)
				ends.append(rect.position + along * length + side * row)
			var dry := ends.all(func(cell: Vector2i) -> bool: return not wet.has(cell) and cell in terrain["floor"])
			var on_road := roads.is_empty() or ends.all(func(cell: Vector2i) -> bool: return roads.has(cell))
			_check(width == 2 and beside[0] >= length - 1 and beside[1] >= length - 1 and dry and on_road,
				"%s's bridge at %s: two wide (%d), the river on past both sides (%s of %d), its ends dry (%s) and on the road (%s)" % [name, rect.position, width, beside, length, dry, on_road])
	_check(found >= 3, "the bridges found: %d" % found)


func _test_held() -> void:
	print("
== Held, step 1 (651): its own map, the Old Tower stamped, the store's cell reserved, no town yet ==")
	var level := Level.load_level("held")
	_check(level["size"] == Vector2i(192, 192) and level.get("warnings", []).is_empty(), "levels/held loads, 192 x 192, clean (%s)" % [level.get("warnings", [])])
	_check(level["display_name"] == "Towerside", "its name is Towerside, the town having moved into the wilds (651 amended; Jeff; the id stays held: %s)" % level["display_name"])
	var links: Array = level["links"]
	var to_wilds: Array = links.filter(func(link: Dictionary) -> bool: return link["to_map"] == "wilds")
	var wilds := Level.load_level("wilds")
	var town_cells: Array = [wilds["places"]["store"]["cell"], wilds["places"]["woodlot"]["cell"]]
	for building: Dictionary in wilds["buildings"]:
		if str(building.get("town", "")) != "":
			town_cells.append(building["cell"])
	_check(town_cells.all(func(cell: Vector2i) -> bool: return Level.room_at(wilds, cell) == "umbrage") and wilds["rooms"]["umbrage"]["name"] == "Umbrage"
			and Level.room_at(wilds, Vector2i(70, 202)) == "" and Level.room_at(wilds, Vector2i(160, 160)) == "" and Level.room_at(wilds, Vector2i(155, 160)) == "",
		"the wilds' town ground is named Umbrage while the town stands there (665's rooms; the store, the woodlot, the town's buildings), the standing stones and the barrow's mound and link not (774 amended) (%s: %s)"
			% [town_cells, town_cells.map(func(cell: Vector2i) -> String: return Level.room_at(wilds, cell))])
	var back: Array = wilds["links"].filter(func(link: Dictionary) -> bool: return link["to_map"] == "held")
	_check(to_wilds.size() == 1 and (to_wilds[0]["tile"] as Vector2i).y == 0 and back.size() == 1 and (back[0]["tile"] as Vector2i).y >= 236
			and level["spawn_points"].has("from_wilds") and wilds["spawn_points"].has("from_held"),
		"its north edge links to the wilds' south edge and back, Umbrage downstream (743) (%s, %s)" % [to_wilds.map(func(link: Dictionary) -> Vector2i: return link["tile"]), back.map(func(link: Dictionary) -> Vector2i: return link["tile"])])
	var road_cells := {}
	for road: Dictionary in level["terrain"].get("roads", []):
		road_cells.merge(Curves.cells(road["curve"], false))
	var wilds_roads := {}
	for road: Dictionary in wilds["terrain"].get("roads", []):
		wilds_roads.merge(Curves.cells(road["curve"], false))
	var arrival: Vector2i = level["spawn_points"].get("from_wilds", Vector2i(-1, -1))
	var wilds_arrival: Vector2i = wilds["spawn_points"].get("from_held", Vector2i(-1, -1))
	_check(road_cells.has(arrival) and wilds_roads.has(wilds_arrival),
		"a road meets both ends of the link: Umbrage's gate road at %s, the wilds' south arm at %s (743)" % [arrival, wilds_arrival])
	var fort: Dictionary = level["places"].get("old_tower", {})
	_check(fort.get("kind") == "fort" and not fort.has("town"), "the Old Tower's place: a fort, working for no town yet (%s)" % [fort])
	var kinds: Array = level["buildings"].filter(func(building: Dictionary) -> bool: return building.has("kind"))
	_check(kinds.size() == 1 and kinds[0]["kind"] == "tower_room", "no houses: the only kind building the tower's room (%s)" % [kinds.map(func(building: Dictionary) -> String: return building["kind"])])
	var store := Vector2i(100, 96)
	var height := _ground(level, store)
	var pad := Level.rect_cells(Rect2i(store - Vector2i(4, 4), Vector2i(9, 9)))
	var covered: Array = level["buildings"].filter(func(building: Dictionary) -> bool: return (building["rect"] as Rect2i).has_point(store))
	_check(store in level["terrain"]["floor"] and covered.is_empty() and pad.all(func(cell: Vector2i) -> bool: return absf(_ground(level, cell) - height) < 0.01),
		"the store's cell reserved: open floor, nothing on it, its 9 x 9 pad level")
	_check(_main.load_map("held"), "Held loads")
	var start: Vector2i = level["starts"][0]
	var room := Vector2i(19, 92)
	var way := World.find_path(start, room, true)
	_check(not way.is_empty(), "the tower's room walked to from the link, over the bridge (%d steps)" % way.size())
	var bridge: Dictionary = level["buildings"].filter(func(building: Dictionary) -> bool: return building.get("slot") == "bridge")[0]
	var spans := Level.rect_cells(bridge["rect"])
	spans.append_array(Array(level["terrain"]["bridged"]))
	for cell in spans:
		World.set_floor(cell, false)
	way = World.find_path(start, room, true)
	var fords: Array = Array(level["terrain"]["fords"])
	_check(not way.is_empty() and not way.any(func(cell: Vector2i) -> bool: return cell in spans) and way.any(func(cell: Vector2i) -> bool: return cell in fords),
		"and with the bridge gone, over the ford (%d steps, %d ford cells)" % [way.size(), fords.size()])
	_main.load_map("test_room")


## The sought's refuges (613 amended): one place a story, keyed by its tag,
## of kind "refuge" with its where, each walked to from its level's start;
## every story's tag in economy.json (sought.trades, when there) laid.
func _test_refuges() -> void:
	print("\n== refuges: each story's place, walked to from the level's start ==")
	var tags := {}
	for zone: String in ["wilds", "hills", "forest", "castle_halls"]:
		var level := Level.load_level(zone)
		_check(_main.load_map(zone), "%s loads" % zone)
		var start: Vector2i = level["starts"][0]
		for key: String in level["places"]:
			var place: Dictionary = level["places"][key]
			if place["kind"] != "refuge":
				continue
			tags[key] = zone
			var path := World.find_path(start, place["cell"], true)
			# A regenerating level's template keeps its anchors in the rock
			# (the forge under the castle, 613): the generator joins them,
			# labyrinth_test walks a generation; its where is the sought's.
			var walked := not path.is_empty() or Regen.marked(zone)
			var where_wanted := "castle_dungeon" if zone == "castle_halls" else zone
			_check(place.get("where", "") == where_wanted and walked,
				"%s's %s (%s): where %s, walked to in %d steps" % [zone, key, place["cell"], place.get("where", ""), path.size()])
	# The hill cave waits on terrain's shelter (make_hills' SHELTER_BUILT, 820's rule): its story falls to its alt.
	var shelter: bool = preload("res://tools/make_hills.gd").SHELTER_BUILT
	_check(tags.size() == (12 if shelter else 11), "the refuges laid, the smith's forge under the castle among them (%s)" % [tags.keys()])
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://levels/economy.json"))
	var trades: Dictionary = rules.get("sought", {}).get("trades", {})
	var wanted := []
	for trade: String in trades:
		for variant: Variant in [trades[trade], trades[trade].get("alt")]:
			if variant is Dictionary and str(variant.get("place", "camp")) != "camp":
				wanted.append(str(variant["place"]))
	var missing := wanted.filter(func(tag: String) -> bool: return not tags.has(tag) and (shelter or tag != "hill_cave"))
	_check(missing.is_empty(), "every story's place economy names is laid (%d named; missing %s)" % [wanted.size(), missing])
	_main.load_map("test_room")


func _test_herders() -> void:
	print("\n== herders: each holding's hut and fold, its gate and door, walked into ==")
	var level := Level.load_level("hills")
	_check(_main.load_map("hills"), "hills loads")
	var edges: Dictionary = level["terrain"]["edges"]
	var floor := {}
	for cell: Vector2i in level["terrain"]["floor"]:
		floor[cell] = true
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://levels/economy.json"))
	var named: Array = rules.get("herder", {}).get("places", ["herders_hut", "hill_shieling"])
	_check(named.size() == 2, "economy names two herders' places (%s)" % [named])
	for key: Variant in named:
		var place: Dictionary = level["places"].get(str(key), {})
		_check(place.get("kind", "") == "refuge" and place.get("where", "") == "hills", "%s: a hills refuge (%s)" % [key, place.get("cell")])
		if place.is_empty():
			continue
		var stand: Vector2i = place["cell"]
		var fold := Level.fold_near(level["buildings"], stand)
		_check(not fold.is_empty(), "%s: its fold stands by it (%s)" % [key, fold.get("rect")])
		if fold.is_empty():
			continue
		var rect: Rect2i = fold["rect"]
		var facing: Vector2i = fold["facing"]
		var cells: Array[Vector2i] = []
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				cells.append(Vector2i(x, y))
		var open := Level.blocks_outline(cells).filter(func(edge: Vector3i) -> bool: return not edges.has(edge))
		var front := true
		for edge: Vector3i in open:
			var a := Vector2i(edge.x, edge.y)
			var b := a + (Vector2i(1, 0) if edge.z == Terrain.EAST else Vector2i(0, 1))
			var outward := b - a if rect.has_point(a) else a - b
			front = front and outward == facing
		_check(open.size() == 2 and front, "%s: the fold's fence is shut but its gate, two edges on its %s side (%s)" % [key, facing, open])
		var huts: Array = level["buildings"].filter(func(b: Dictionary) -> bool: return b["slot"] == "building.hut" and b["facing"] == -facing)
		var door := stand + facing  # The hut's door cell, beyond the stand from the fold.
		var hut_ok := huts.any(func(b: Dictionary) -> bool: return (b["rect"] as Rect2i).has_point(door))
		_check(hut_ok and int(edges.get(Terrain.edge_key(door, -facing), -1)) == Terrain.Edge.DOOR,
			"%s: a hut's door opens on its place, toward the fold" % key)
		var pad := rect.grow(2)
		for b: Dictionary in huts:
			if (b["rect"] as Rect2i).has_point(door):
				pad = rect.merge(b["rect"]).grow(2)
		var blocked := []
		for y in range(pad.position.y, pad.end.y):
			for x in range(pad.position.x, pad.end.x):
				var cell := Vector2i(x, y)
				if not floor.has(cell) and not huts.any(func(b: Dictionary) -> bool: return (b["rect"] as Rect2i).has_point(cell)):
					blocked.append(cell)
		_check(blocked.is_empty(), "%s: open ground two cells round the hut and the fold (blocked %s)" % [key, blocked.slice(0, 4)])
		var inside := Vector2i(rect.get_center())
		var path := World.find_path(level["starts"][0], stand, true)
		var into := World.find_path(stand, inside, true)
		_check(not path.is_empty() and not into.is_empty(), "%s: walked to from the start (%d steps) and into the fold through its gate (%d)" % [key, path.size(), into.size()])
	_main.load_map("test_room")


func _test_forest_healer() -> void:
	print("\n== the forest's healer's hut (641): its place, open ground round it, walked into ==")
	var level := Level.load_level("forest")
	_check(_main.load_map("forest"), "forest loads")
	var huts: Array = level["buildings"].filter(func(b: Dictionary) -> bool: return Level.BUILDING_PLACES.get(b["slot"]) == "healers_hut")
	var places: Array = level["places"].values().filter(func(p: Dictionary) -> bool: return p["kind"] == "healers_hut")
	_check(huts.size() == 1 and places.size() == 1 and level["warnings"].is_empty(), "one hut, one healers_hut place, no warnings (%s)" % [level["warnings"]])
	if huts.size() != 1 or places.size() != 1:
		_main.load_map("test_room")
		return
	var rect: Rect2i = huts[0]["rect"]
	var floor := {}
	for cell: Vector2i in level["terrain"]["floor"]:
		floor[cell] = true
	var blocked := []
	var banked := Level.banked_cells(huts[0])
	var ring := rect.grow(2)
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			if not floor.has(Vector2i(x, y)) and not Vector2i(x, y) in banked:
				blocked.append(Vector2i(x, y))
	_check(huts[0]["slot"] == "building.turf_house" and blocked.is_empty(),
			"the turf house (718), open ground two cells round it but its own bank, bed and hearth (blocked %s)" % [blocked.slice(0, 4)])
	var front: Vector2i = places[0]["cell"]
	var inside := rect.get_center()
	var path := World.find_path(level["starts"][0], front, true)
	var into := World.find_path(front, inside, true)
	_check(not path.is_empty() and not into.is_empty(), "its door walked to from the start (%d steps) and in (%d)" % [path.size(), into.size()])
	_main.load_map("test_room")


func _test_safe_paths() -> void:
	print("
== safe paths (763, Level.safe_paths): roads and dirt tracks, not patches or banks ==")
	var areas := WorldMap.build().areas
	var counts := {}
	for land: String in ["wilds", "hills", "forest", "foothills", "held"]:
		counts[land] = (areas[land].get("safe_paths", {}) as Dictionary).size()
	var wilds: Dictionary = areas["wilds"]["safe_paths"]
	var hills: Dictionary = areas["hills"]["safe_paths"]
	var forest := Level.load_level("forest")
	var dirt := 0
	var floor := {}
	for cell: Vector2i in forest["terrain"]["floor"]:
		floor[cell] = true
	for cell: Vector2i in forest["terrain"]["kinds"]:
		if forest["terrain"]["kinds"][cell] == "dirt" and floor.has(cell):
			dirt += 1
	_check(wilds.has(Vector2i(185, 95)) and not wilds.has(Vector2i(13, 227)) and wilds.size() > 1400,
		"the wilds: a track's cell a path, a cleared patch's not (%s)" % [counts])
	# Without the hill cave's track (SHELTER_BUILT false, 820) about 100 cells fewer.
	var least := 690 if preload("res://tools/make_hills.gd").SHELTER_BUILT else 590
	_check(not hills.has(Vector2i(91, 149)) and hills.size() >= least and hills.size() < least + 70,
		"the hills: the road and 777's tracks, not the river's dirt bank (%d)" % hills.size())
	_check(counts["forest"] == dirt, "the forest, no road curves: all its dirt on its floor (%d of %d)" % [counts["forest"], dirt])


## Filling the hills, phase 1 (777): a track from the road to each refuge
## (its place's cell on a safe path), two rest camps (649's camp kind, a
## "rest" place at Level.camp_fire), seven forage patches on grass; the do
## rhythm: every safe path cell within FILL_DO_REACH of something to do (a
## rest, a refuge, a patch), about 15 s of walking either way; a player by
## a camp's fire, unhurt a while, is warmed (physics' heal), and not once hit.
const FILL_DO_REACH := 60


## Filling the hills, phase 2 (778): the landmarks, roadside sights and
## story pieces stand, bare (no words yet), none on a path, the lean-to with
## its cold hearth, and every floor cell still walked to from the link.
func _test_fill_hills_sights() -> void:
	print("\n== filling the hills (778): landmarks, roadside sights, stories ==")
	var level := Level.load_level("hills")
	var counts := {}
	for building: Dictionary in level["buildings"]:
		var slot := str(building.get("slot", ""))
		counts[slot] = int(counts.get(slot, 0)) + 1
	var want := {"building.tower_ruin": 1, "tree.great_oak": 1, "building.standing_stone": 1, "building.milestone": 2,
		"building.wayside_shrine": 1, "building.woodpile": 1, "building.hunters_blind": 1, "building.waystone": 3,
		"building.cairn": 1, "building.grave": 1, "building.lean_to": 1}
	if not preload("res://tools/make_hills.gd").SHELTER_BUILT:
		want["building.waystone"] = 1  # W4 waits on the hill cave's shelter (820's rule).
	var short := want.keys().filter(func(slot: String) -> bool: return int(counts.get(slot, 0)) != int(want[slot]))
	_check(short.is_empty(), "the sights stand: a watchtower, an oak, a stone, two milestones, a shrine, a stack, a blind, three waystones, a cairn, a grave, a lean-to (off: %s)" % [short])
	# Hollowfell's mine mouth (798 amended (3), maps' side): its link's "mine" cue, the bank's rock
	# behind it (no floor), and terrain's raised bank round it.
	var MakeHills := preload("res://tools/make_hills.gd")
	# From the file: Level keeps a cue only once it knows it (terrain's "mine", in its own landing).
	var hills_json: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://levels/hills/level.json"))
	var mine_link: Array = (hills_json["links"] as Array).filter(func(l: Dictionary) -> bool: return l["to_map"] == "hollowfell")
	var mine_floor: Array = []
	for y in range(55, 62):
		for x in range(168, 173):
			if Vector2i(x, y) in level["terrain"]["floor"]:
				mine_floor.append(Vector2i(x, y))
	var mine_relief: PackedFloat32Array = level["terrain"]["relief"]
	var mine_size: Vector2i = level["terrain"]["relief_size"]
	var low: Array = MakeHills.MINE_BANK.filter(func(row: Array) -> bool:
		return Relief.at(mine_relief, mine_size, Vector2i(row[0], row[1])) < float(row[2]) - 0.05)
	_check(mine_link.size() == 1 and str(mine_link[0].get("cue", "")) == "mine" and mine_floor.is_empty() and low.is_empty(),
		"Hollowfell's mouth: the link's mine cue, its bank's rock no floor (%s), every bank cell at least terrain's height (%s)" % [mine_floor, low.slice(0, 3)])
	# Hollowfell's track and waystone (the iron package's pointer): a dirt track from the road's
	# end to the mouth's place, two cells across all the way (a 2 x 2 of floor round every cell
	# on its line), and the carved stone in the fork, the shieling's track east of it.
	var mouth_at: Array = hills_json["places"]["hollowfell"]["at"]
	var mine_track: Array = (hills_json["roads"] as Array).filter(func(r: Dictionary) -> bool:
		var points: Array = r["points"]
		return Vector2(points[0][0], points[0][1]).distance_to(Vector2(MakeHills.ROAD_END)) < 1.5 			and Vector2(points[-1][0], points[-1][1]).distance_to(Vector2(mouth_at[0], mouth_at[1])) < 1.5)
	var pinched: Array = []
	if mine_track.size() == 1:
		var points: Array = mine_track[0]["points"]
		for i in range(points.size() - 1):
			var a := Vector2(points[i][0], points[i][1])
			var b := Vector2(points[i + 1][0], points[i + 1][1])
			for step in range(int(a.distance_to(b) * 4.0) + 1):
				var cell := Vector2i(a.lerp(b, step / maxf(1.0, a.distance_to(b) * 4.0)).floor())
				var wide := false
				for corner: Vector2i in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
					var all_floor := true
					for d: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
						all_floor = all_floor and (cell + corner + d) in level["terrain"]["floor"]
					wide = wide or all_floor
				if not wide and not cell in pinched:
					pinched.append(cell)
	var fork_stone: Array = (hills_json["buildings"] as Array).filter(func(b: Dictionary) -> bool: return b.get("carved", "") == "Mine")
	var stone_at := Vector2i(fork_stone[0]["at"][0], fork_stone[0]["at"][1]) if fork_stone.size() == 1 else Vector2i(-1, -1)
	_check(mine_track.size() == 1 and pinched.is_empty() and Vector2(stone_at).distance_to(Vector2(MakeHills.ROAD_END)) < 6.0
			and stone_at.x < MakeHills.ROAD_END.x and stone_at.y < MakeHills.ROAD_END.y,
		"Hollowfell's track from the road's end to its mouth, two across all the way (pinched at %s), its stone in the fork at %s" % [pinched.slice(0, 4), stone_at])
	# The hill cave (798 amended (4), maps' side): the refuge opens east to a shelter, the
	# cells under the overhang floor and the rest of its hill rock, terrain's bank raised round
	# it; no rest place (its fire ring is cold, 798 amended (4), maps' side).
	if MakeHills.SHELTER_BUILT:
		var shelter_floor: Variant = level["terrain"]["floor"]
		var wrong_cells: Array = []
		for cell: Vector2i in Level.rect_cells(MakeHills.SHELTER_ROCK):
			if (cell in shelter_floor) != MakeHills.SHELTER_FLOOR.has_point(cell):
				wrong_cells.append(cell)
		var shelter_low: Array = MakeHills.SHELTER_BANK.filter(func(row: Array) -> bool:
			return Relief.at(mine_relief, mine_size, Vector2i(row[0], row[1])) < float(row[2]) - 0.05)
		var shelters: Array = level["terrain"].get("shelters", [])
		var cave: Dictionary = level["places"].get("hill_cave", {})
		_check(shelters.size() == 1 and shelters[0]["at"] == Vector2i(52, 176) and shelters[0]["opens"] == Vector2i(1, 0)
			and wrong_cells.is_empty() and shelter_low.is_empty() and cave.get("kind", "") == "refuge"
			and not level["places"].has("hill_cave_camp"),
			"the hill cave: a shelter opening east (%s), floor under the overhang and rock round it (%s), every bank cell at least terrain's height (%s), no rest place" % [shelters, wrong_cells.slice(0, 3), shelter_low.slice(0, 3)])
	var decor := {}
	for piece: Dictionary in level["terrain"]["decor"]:
		decor[piece["kind"]] = int(decor.get(piece["kind"], 0)) + 1
	_check(decor.get("broken_cart", 0) == 1 and decor.get("fallen_guard", 0) == 1 and decor.get("rusted_gear", 0) == 1 and decor.get("campfire_cold", 0) == 1,
		"and lying: a broken cart, a dead traveller, an old fight's gear, the lean-to's cold hearth (%s)" % [decor])
	var paths: Dictionary = WorldMap.build().areas["hills"]["safe_paths"]
	var on_path := []
	for building: Dictionary in level["buildings"]:
		if str(building.get("slot", "")) in want:
			for cell in Level.rect_cells(building["rect"]):
				if paths.has(cell):
					on_path.append(cell)
	_check(on_path.is_empty(), "none stands on a path (%s)" % [on_path.slice(0, 4)])


func _test_fill_hills() -> void:
	print("\n== filling the hills (777): tracks, rest camps, forage, the warmed rest ==")
	var area: Dictionary = WorldMap.build().areas["hills"]
	var paths: Dictionary = area["safe_paths"]
	var places: Dictionary = area["places"]
	var far_refuges := []
	# The hill cave's package waits on terrain's shelter (make_hills' SHELTER_BUILT, 820's rule).
	var shelter: bool = preload("res://tools/make_hills.gd").SHELTER_BUILT
	_check(places.has("hill_cave") == shelter, "the hill cave's place only with its shelter (%s)" % shelter)
	for key: String in (["herders_hut", "hill_cave", "hill_shieling"] if shelter else ["herders_hut", "hill_shieling"]):
		var at: Vector2i = places[key]["cell"]
		var near := false
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				near = near or paths.has(at + Vector2i(dx, dy))
		if not near:
			far_refuges.append(key)
	_check(far_refuges.is_empty(), "a track reaches each refuge, its cell within 3 of a safe path (%s)" % [far_refuges])
	var camps: Array = (area["buildings"] as Array).filter(func(b: Dictionary) -> bool: return str(b.get("kind", "")) == "camp")
	var rests: Array = places.values().filter(func(p: Dictionary) -> bool: return p["kind"] == "rest")
	_check(camps.size() == 2 and rests.size() == 2 and camps.all(func(b: Dictionary) -> bool:
		return rests.any(func(p: Dictionary) -> bool: return p["cell"] == Level.camp_fire(b))),
		"two rest camps, a rest place at each one's fire (%s)" % [rests.map(func(p: Dictionary) -> Vector2i: return p["cell"])])
	var patches: Array = area["forage"]
	var size: Vector2i = area["size"]
	_check(patches.size() == 7 and patches.all(func(p: Dictionary) -> bool:
		var c: Vector2i = p["cell"]
		return area["grass"][c.y * size.x + c.x] == 1 and not p["kinds"].is_empty()), "seven forage patches, each on grass (%d)" % patches.size())
	var doing: Array[Vector2i] = []
	for p: Dictionary in places.values():
		if p["kind"] in ["rest", "refuge"]:
			doing.append(p["cell"])
	for p: Dictionary in patches:
		doing.append(p["cell"])
	var bare: Array[Vector2i] = []
	for cell: Vector2i in paths:
		if not doing.any(func(at: Vector2i) -> bool: return Vector2(cell - at).length() <= FILL_DO_REACH):
			bare.append(cell)
	_check(bare.is_empty(), "the rhythm: every safe path cell within %d of something to do (%d of %d not: %s)" % [FILL_DO_REACH, bare.size(), paths.size(), bare.slice(0, 4)])
	_check(_main.load_map("hills"), "the hills load")
	var player := _player()
	var fire := Level.camp_fire(camps[0]) if not camps.is_empty() else Vector2i(-1, -1)
	var beside := fire
	for step: Vector2i in [Vector2i(0, -2), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(2, 0), Vector2i(-1, -1), Vector2i(1, 1)]:
		if World.is_walkable(fire + step):
			beside = fire + step
			break
	_put(player, beside)
	player.buffs = {}
	player.hurt_tick = World.tick - _main.WARM_UNHIT_TICKS - 1
	_main._warm_rests()
	_check(World.buff(player, "heal") == _main.WARM_HEAL, "by the camp's fire at %s, unhurt: warmed, healing %.1f a second" % [beside, World.buff(player, "heal")])
	player.buffs = {}
	player.hurt_tick = World.tick
	_main._warm_rests()
	_check(World.buff(player, "heal") == 0.0, "just hit: not warmed")
	player.hurt_tick = World.tick - _main.WARM_UNHIT_TICKS - 1
	_put(player, fire + Vector2i(_main.WARM_REACH + 3, 0) if World.is_walkable(fire + Vector2i(_main.WARM_REACH + 3, 0)) else fire - Vector2i(_main.WARM_REACH + 3, 0))
	_main._warm_rests()
	_check(World.buff(player, "heal") == 0.0, "a few cells off: not warmed")
	player.buffs = {}
	_main.load_map("test_room")


## The wilds on foot ("wilds basics: river", the ford): the main stream waded,
## its bridge over a deep channel, the river's wide reach deep; every place a
## walker can reach from the level's centre (its cell or one beside it, a well's
## or a store's being solid), the walk over the floor and the fords, never
## through a wall or a closed door left shut.
func _test_wilds_on_foot() -> void:
	print("
== the wilds on foot: every place reached from the centre, the stream waded ==")
	_check(_main.load_map("wilds"), "the wilds load")
	var level := Level.load_level("wilds")
	var start: Vector2i = level["centre"]
	var reached := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := at + step
			if reached.has(next) or not World.is_walkable(next) or World.edge_blocks(at, step, true):
				continue
			reached[next] = true
			queue.append(next)
	var cut_off: Array[String] = []
	for key: String in level["places"]:
		var cell: Vector2i = level["places"][key]["cell"]
		var near := false
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				near = near or reached.has(cell + Vector2i(dx, dy))
		if not near:
			cut_off.append(key)
	var fords: Array = level["terrain"].get("fords", [])
	_check(World.is_walkable(start) and cut_off.is_empty() and fords.size() > 700,
		"from the centre %s, every place reached on foot (%d cells walked; not: %s), the stream waded (%d ford cells)" % [start, reached.size(), cut_off, fords.size()])
	_main.load_map("test_room")


## Wilds basics: farm and barrow (827): the barrow's mound out past the town
## (its middle 25 cells or more from every other building's), its door on the
## link, from_barrow before it, the barrow post by its track; the old
## farmstead a farm gone to ruin (a ruined cottage over its floorboard cache,
## a rubble heap, two fields striped in furrows of dirt and weeds) and the
## ruined barn a ruined barn; no lantern left at the farmstead.
func _test_farm_and_barrow() -> void:
	print("
== wilds basics: farm and barrow (827) ==")
	var wilds := Level.load_level("wilds")
	var mound: Dictionary = {}
	var nearest := INF
	var ruins := {}
	for building: Dictionary in wilds["buildings"]:
		if building.get("slot") == "building.mound":
			mound = building
	var middle := Vector2(mound["rect"].get_center()) if not mound.is_empty() else Vector2(-1000, -1000)
	for building: Dictionary in wilds["buildings"]:
		if building == mound or not building.get("rect") is Rect2i:
			continue
		nearest = minf(nearest, middle.distance_to(Vector2((building["rect"] as Rect2i).get_center())))
		if building.get("ruined", false):
			ruins[str(building.get("kind", ""))] = building["rect"]
	var link: Array = wilds["links"].filter(func(l: Dictionary) -> bool: return l["to_map"] == "barrow" and not l.has("building"))
	_check(not mound.is_empty() and nearest >= 25.0 and mound["door"] == Vector2i(160, 160) and link.size() == 1 and link[0]["tile"] == Vector2i(160, 160)
		and wilds["spawn_points"].get("from_barrow") == Vector2i(160, 159)
		and Vector2(wilds["places"]["post_barrow"]["cell"]).distance_to(Vector2(160, 160)) <= 16.0,
		"the barrow out past the town: its mound %.0f cells from the nearest building, its door on the link (160, 160), the post by its track" % nearest)
	var cottage: Variant = ruins.get("cottage")
	var barn: Variant = ruins.get("barn")
	var plots: Array[Rect2i] = [Rect2i(112, 143, 8, 5), Rect2i(106, 154, 8, 5)]
	var kinds: Dictionary = wilds["terrain"]["kinds"]
	var weeds := {}
	for cell: Vector2i in wilds["terrain"]["tall_grass"]:
		weeds[cell] = true
	# Two plots west of the road beside the cottage (the coordinator), bare dirt
	# with no tall grass (it reads as grain): terrain's furrows draw the ridges
	# and the weeds on them, run along x.
	var bare := 0
	for plot: Rect2i in plots:
		for y in range(plot.position.y, plot.end.y):
			for x in range(plot.position.x, plot.end.x):
				if str(kinds.get(Vector2i(x, y), "")) == "dirt" and not weeds.has(Vector2i(x, y)):
					bare += 1
	var furrowed: Array = []
	for furrow: Dictionary in wilds["terrain"].get("furrows", []):
		furrowed.append([furrow["rect"], furrow["along"]])
	var lanterns: Array = wilds["terrain"].get("lanterns", []).filter(func(at: Vector2i) -> bool: return Vector2(at - Vector2i(118, 150)).length() <= 14.0)
	_check(cottage is Rect2i and (cottage as Rect2i).has_point(Vector2i(119, 139)) and barn is Rect2i and (barn as Rect2i).has_point(Vector2i(75, 143))
		and lanterns.is_empty(),
		"the old farmstead's cottage in ruin over its cache, the barn in ruin, no lantern left (%s, %s, %s)" % [cottage, barn, lanterns])
	var cottage_entry: Dictionary = {}
	for building: Dictionary in wilds["buildings"]:
		if building.get("kind") == "cottage" and building.get("ruined", false):
			cottage_entry = building
	_check(not cottage_entry.is_empty() and (cottage_entry["doors"] as Array).is_empty() and (cottage_entry["open"] as Array).size() == 3
		and Terrain.edge_key(Vector2i(120, 142), Vector2i(0, 1)) in cottage_entry["open"],
		"the ruin's gaps its entry's own (no doorway; the door's gap and a fallen corner open), not its kind's (%s)" % [cottage_entry.get("open")])
	_check(bare == 80 and furrowed == [[plots[0], Vector2i(1, 0)], [plots[1], Vector2i(1, 0)]]
		and str(kinds.get(Vector2i(127, 147), "")) == "dirt" and not Vector2i(127, 147) in wilds["terrain"]["water"],
		"two fallow fields beside the cottage, bare dirt under terrain's furrows along x, and the well dry (%d of 80 bare; %s)" % [bare, furrowed])
	var farm_decor := {}
	for piece: Dictionary in wilds["terrain"]["decor"]:
		if piece["kind"] in ["well_dry", "scarecrow_leaning", "scarecrow_fallen"]:
			farm_decor[piece["kind"]] = farm_decor.get(piece["kind"], []) + [piece["cell"]]
	_check(farm_decor.get("well_dry", []) == [Vector2i(127, 147)] and farm_decor.get("scarecrow_leaning", []).size() == 1
		and plots[0].has_point(farm_decor["scarecrow_leaning"][0]) and not farm_decor.has("scarecrow_fallen"),
		"the dry well's ring on its old cell, and a scarecrow still leaning on its pole in the first field, the fallen one gone (%s)" % [farm_decor])


## A hearth (825, "hill cave rest"): a place's "fire_ring" a cell within
## Level.FIRE_RING_REACH of it (else warned and left out); none laid in any level
## yet (the hill cave's switch puts the first). In the hills, one made there:
## E from beside it lights it (the "hearth" command), from farther off not; lit,
## it is fire and warms the rest as a camp's fire does (777), till its burn
## runs out and it goes cold; the save keeps a burning one.
## 777 amended (2): a town's hearth and its burning fire warm as a camp's:
## the Mughouse's hearth, the square's fire in Umbrage; a few cells off, or
## just hit, nothing.
func _test_town_warm_rests() -> void:
	print("\n== 777 amended (2): a town's hearth and its fire are warm rests ==")
	_check(_main.load_map("umbrage_tavern"), "the Mughouse loads")
	var player := _player()
	_check(_main._town_warm_cells(World.zone.name).has(Vector2i(0, 6)), "its hearth (0, 6) a warm rest (%s)" % [_main._town_warm_cells(World.zone.name)])
	for at: Array in [[Vector2i(2, 6), true, "by the hearth"], [Vector2i(6, 6), false, "across the room"]]:
		_put(player, at[0])
		player.buffs = {}
		player.hurt_tick = World.tick - _main.WARM_UNHIT_TICKS - 1
		_main._warm_rests()
		_check((World.buff(player, "heal") == _main.WARM_HEAL) == at[1], "%s at %s, unhurt: %s (%.1f)" % [at[2], at[0], "warmed" if at[1] else "not", World.buff(player, "heal")])
	_put(player, Vector2i(2, 6))
	player.buffs = {}
	player.hurt_tick = World.tick
	_main._warm_rests()
	_check(World.buff(player, "heal") == 0.0, "by the hearth, just hit: not warmed")
	player.buffs = {}
	_check(_main.load_map("wilds"), "the wilds load")
	player = _player()
	var pit := Vector2i(194, 211)
	_check(World.is_fire(pit) and _main._town_warm_cells(World.zone.name).has(pit), "the square's fire burns at %s, a warm rest" % pit)
	for at: Array in [[Vector2i(196, 210), true, "on a seat beside it"], [Vector2i(199, 211), false, "five cells off"]]:
		_put(player, at[0])
		player.buffs = {}
		player.hurt_tick = World.tick - _main.WARM_UNHIT_TICKS - 1
		_main._warm_rests()
		_check((World.buff(player, "heal") == _main.WARM_HEAL) == at[1], "%s at %s, unhurt: %s (%.1f)" % [at[2], at[0], "warmed" if at[1] else "not", World.buff(player, "heal")])
	player.buffs = {}
	_main.load_map("test_room")


func _test_hearth() -> void:
	print("
== a hearth (825): lit from beside it, fire while it burns, warming the rest, saved ==")
	var warnings: Array[String] = []
	var places := Level.places_from({"places": {
		"cave_camp": {"at": [10, 10], "kind": "rest", "name": "a camp", "fire_ring": [9, 10]},
		"far_camp": {"at": [30, 10], "kind": "rest", "name": "a camp", "fire_ring": [40, 10]}}}, warnings)
	var hearth_warned := warnings.filter(func(w: String) -> bool: return w.contains("fire ring"))
	_check(Level.fire_rings_of(places) == [Vector2i(9, 10)] and hearth_warned.size() == 1,
		"a place's hearth beside it kept, one 10 off warned and left out (%s; %s)" % [Level.fire_rings_of(places), hearth_warned])
	var laid := {}
	for level_name: String in ["hills", "wilds", "forest", "foothills"]:
		var rings: Array = Level.load_level(level_name)["terrain"].get("fire_rings", [])
		if not rings.is_empty():
			laid[level_name] = rings
	var hills_rings: Array = laid.get("hills", [])
	_check(laid.size() == 1 and hills_rings == [Vector2i(51, 176)],
		"the one fire ring laid is the hill cave's, at (51, 176) under its lip, where terrain draws it (%s)" % [laid])
	_check(_main.load_map("hills"), "the hills load")
	var player := _player()
	var ring := Vector2i(50, 176)
	var zone_name: String = World.zone.name
	World._hearth_cells[zone_name] = {ring: true}
	var told := [0]
	var count := func(_level: String) -> void: told[0] += 1
	World.hearths_changed.connect(count)
	_put(player, ring + Vector2i(3, 0))
	_main._on_command(player, "hearth", {"at": [ring.x, ring.y]})
	var far_lit := World.is_fire(ring)
	_put(player, ring + Vector2i(1, 0))
	_main._on_command(player, "hearth", {"at": [ring.x, ring.y]})
	_check(not far_lit and World.is_fire(ring) and World.lit_hearths(zone_name) == [ring] and told[0] == 1,
		"three off, not lit; beside it, lit and fire (%s), told once (%d)" % [World.lit_hearths(zone_name), told[0]])
	player.buffs = {}
	player.hurt_tick = World.tick - _main.WARM_UNHIT_TICKS - 1
	_main._warm_rests()
	_check(World.buff(player, "heal") == _main.WARM_HEAL, "beside it, unhurt: warmed as by a camp's fire (%.1f a second)" % World.buff(player, "heal"))
	var saved: Variant = JSON.parse_string(JSON.stringify(World.hearths_to_dict()))
	World.hearths_lit.clear()
	World.hearths_from_dict(saved)
	var left: int = int(World.hearths_lit.get(zone_name, {}).get(ring, 0)) - World.tick
	_check(World.is_fire(ring) and left > World.HEARTH_BURN_TICKS - 20 and left <= World.HEARTH_BURN_TICKS,
		"the save keeps it burning, its burn left (%d ticks)" % left)
	World.hearths_lit[zone_name][ring] = World.tick
	told[0] = 0
	World.burn_hearths()
	player.buffs = {}
	_main._warm_rests()
	_check(not World.is_fire(ring) and World.lit_hearths(zone_name).is_empty() and told[0] == 1 and World.buff(player, "heal") == 0.0,
		"its burn run out: cold, told (%d), warming nobody" % told[0])
	World.hearths_changed.disconnect(count)
	World.hearths_lit.clear()
	World._hearth_cells.erase(zone_name)
	player.buffs = {}
	_main.load_map("test_room")


func _test_world_plane() -> void:
	print("\n== the world plane (650): every outdoor level laid on it, the links' ends meeting ==")
	var plane := Level.world_plane()
	_check(plane["warnings"].is_empty(), "levels/world_plane.json reads clean (%s)" % [plane["warnings"]])
	var zones: Dictionary = plane["zones"]
	var levels := {}
	for folder in ResourceLoader.list_directory(Level.DIR):
		var level_name := folder.trim_suffix("/")
		if folder.ends_with("/") and level_name != "prefabs" and ResourceLoader.exists(Level.DIR + level_name + "/layout.png"):
			levels[level_name] = Level.load_level(level_name)
	# A dev level (Level.DEV_LEVELS: bear_yard, 780) is reached by --map, never laid on the plane.
	var outdoor := levels.keys().filter(func(level_name: String) -> bool: return Level.zone_of(Level.template_config(level_name)) == "outdoors" and level_name not in Level.DEV_LEVELS)
	var missing := outdoor.filter(func(level_name: String) -> bool: return not zones.has(level_name))
	var indoor_laid := zones.keys().filter(func(level_name: String) -> bool: return not level_name in outdoor)
	_check(missing.is_empty() and indoor_laid.is_empty(), "every outdoor level has an origin, nothing else does (%s; missing %s, not outdoor %s)" % [outdoor, missing, indoor_laid])
	var rects := {}
	for level_name: String in zones:
		if levels.has(level_name):
			rects[level_name] = Rect2i(zones[level_name]["origin"], levels[level_name]["size"])
	var overlaps := []
	var names: Array = rects.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			if (rects[names[i]] as Rect2i).intersects(rects[names[j]]):
				overlaps.append([names[i], names[j]])
	_check(overlaps.is_empty(), "no two outdoor levels overlap on it (%s)" % [overlaps])
	for level_name: String in rects:
		var level: Dictionary = levels[level_name]
		for link: Dictionary in level["links"]:
			var far := str(link["to_map"])
			if not rects.has(far) or far < level_name:
				continue
			var a: Rect2i = rects[level_name]
			var b: Rect2i = rects[far]
			var back: Array = levels[far]["links"].filter(func(each: Dictionary) -> bool: return str(each["to_map"]) == level_name)
			if back.is_empty():
				_check(false, "%s's link to %s has a way back" % [level_name, far])
				continue
			var here: Vector2i = a.position + (link["tile"] as Vector2i)
			var there: Vector2i = b.position + (back[0]["tile"] as Vector2i)
			# They touch along one side: across it the two link cells line up.
			var side_by_side := a.end.x == b.position.x or b.end.x == a.position.x
			var above_below := a.end.y == b.position.y or b.end.y == a.position.y
			var lined := (side_by_side and here.y == there.y) or (above_below and here.x == there.x)
			var rise := absf(_ground(level, link["tile"]) + float(zones[level_name]["height"]) - _ground(levels[far], back[0]["tile"]) - float(zones[far]["height"]))
			_check(lined and rise <= 0.05, "%s and %s meet edge to edge, the link at %s across from %s, %.2f m apart in height" % [level_name, far, here, there, rise])
	var ids := {}
	for mark: Dictionary in plane["landmarks"]:
		ids[mark["id"]] = true
	_check(ids.has("castle") and ids.has("tower_over_the_mine") and ids.size() == plane["landmarks"].size(),
		"the castle and the tower over the mine are landmarks, each its own id (%s)" % [ids.keys()])
	# 745: the castle is reached through the foothills, so the wilds no longer
	# link to it and see it as a far landmark; till step 5 builds the new
	# castle, the far castle stands on the castle level's own place, at its
	# height, never where the castle stood before it moved.
	var far_castle: Array = plane["landmarks"].filter(func(mark: Dictionary) -> bool: return mark["id"] == "castle")
	_check(rects.has("castle") and far_castle.size() == 1 and (rects["castle"] as Rect2i).has_point(far_castle[0]["at"])
			and absf(float(far_castle[0]["base"]) - float(zones["castle"]["height"])) <= 0.05,
		"the far castle stands on the castle's own place on the plane, at its height (745; %s, the castle at %s)" % [far_castle, rects.get("castle")])
	# 650 amended: the places no level holds yet and the named lands, each
	# its own id, agreed or a draft; no place on a built level's ground.
	var listed: Array = plane["places"] + plane["regions"]
	var place_ids := {}
	for entry: Dictionary in listed:
		place_ids[entry["id"]] = true
	var on_levels := []
	for place: Dictionary in plane["places"]:
		for level_name: String in rects:
			if (place["rect"] as Rect2i).intersects(rects[level_name]):
				on_levels.append([place["id"], level_name])
	_check(place_ids.size() == listed.size() and place_ids.has("mine") and place_ids.has("stronghold")
			and listed.all(func(entry: Dictionary) -> bool: return entry["status"] in Level.PLANE_STATUSES),
		"the places and lands each their own id, agreed or a draft (%s)" % [place_ids.keys()])
	_check(on_levels.is_empty(), "no place lore names lies on a built level's ground (%s)" % [on_levels])


func _ground(level: Dictionary, cell: Vector2i) -> float:
	var terrain: Dictionary = level["terrain"]
	return Relief.at(terrain["relief"], terrain["relief_size"], cell) if terrain.has("relief") else 0.0


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
	_hold_free(player, Vector2(1, 0), 3)
	_check(player.tile == Vector2i(3, 2), "Player walks up the stair (%s)" % player.free_pos)
	_hold_free(player, Vector2(0, -1), 4)
	_check(World.height_at(player.tile) == 1, "along the top, still on level 1 (%s)" % player.free_pos)
	_put(player, Vector2i(3, 1))
	_hold_free(player, Vector2(-1, 0), 4)
	_check(player.tile == Vector2i(3, 1), "and does not walk off the ledge (%s)" % player.free_pos)
	var path := World.find_path(Vector2i(1, 1), Vector2i(3, 1), true)
	_check(not path.is_empty() and Vector2i(2, 2) in path and Vector2i(3, 2) in path, "a path to level 1 goes by the stair: %s" % [path])
	_check(World.find_path(Vector2i(1, 1), Vector2i(4, 1)).is_empty(), "and none reaches level 2, which no stair joins")
	var bad := Level.parse(Level.image_from_rows(_rows(1, 2, 1, 1), {Vector2i(1, 1): "stair"}), null, {})
	_check(bad["terrain"]["stairs"].is_empty() and str(bad["warnings"]).contains("no cell one level up"),
			"a stair with nothing above it is floor, and said so")


## Shipped levels with a known trap, until their owner fixes it: level -> owner
## (783, physics' side (2)). Their traps print as EXPECTED FAIL, not a failure.
const PIT_TRAPS_EXPECTED := {
}


## 783, physics' side (2): every drop has a way back up. For each shipped
## level's terrain, as World walks it, every ledge a body can be knocked over
## lands where it can walk back to its rim or to a way out (_trap_landings).
func _test_pit_ways_out() -> void:
	print("
== every drop has a way back up: a fall lands where it can walk to its rim or a way out (783) ==")
	var drops := [0]
	for folder in DirAccess.get_directories_at(Level.DIR):
		if Level.DIR + folder + "/" == Prefab.DIR or not FileAccess.file_exists(Level.DIR + folder + "/layout.png"):
			continue
		var level := Level.load_level(folder)
		if level.is_empty():
			continue
		World.load_terrain(level["terrain"])
		var named := _trap_landings(level, drops)
		if not named.is_empty() and PIT_TRAPS_EXPECTED.has(folder):
			print("  EXPECTED FAIL  %s: %d pits with no way out, landing at %s (%s fixes it)" % [folder, named.size(), named.slice(0, 8), PIT_TRAPS_EXPECTED[folder]])
			continue
		_check(named.is_empty(), "%s: every drop lands where its rim or a way out can be walked to (%d trap pits, landing at %s)" % [folder, named.size(), named.slice(0, 8)])
		if named.is_empty() and PIT_TRAPS_EXPECTED.has(folder):
			print("  NOTE  %s is fixed: take it out of PIT_TRAPS_EXPECTED" % folder)
	# 790 (the coordinator): a level marked "regenerate" is laid again on the
	# box, so its generations are checked too, two of each, laid as Regen
	# lays them and read as Level reads them.
	for level_name in Regen.marked_levels():
		for generation in [1, 2]:
			var made := Regen.generate(level_name, generation)
			_check(not made.is_empty(), "%s: generation %d is made" % [level_name, generation])
			if made.is_empty():
				continue
			var level := Level.parse(made["layout"], made["height"], made["config"])
			level["name"] = level_name
			World.load_terrain(level["terrain"])
			# 794 (physics): a generation's track rolls as a laid level's must.
			var faults := _track_faults()
			_check(faults.is_empty(), "%s generation %d: its track rolls (%s)" % [level_name, generation, faults.slice(0, 8)])
			if level_name == "hollowfell":
				_mine_fights(level, made["config"], "%s generation %d" % [level_name, generation])
			var named := _trap_landings(level, drops)
			if not named.is_empty() and PIT_TRAPS_EXPECTED.has(level_name):
				print("  EXPECTED FAIL  %s generation %d: %d pits with no way out, landing at %s (%s fixes it)" % [level_name, generation, named.size(), named.slice(0, 8), PIT_TRAPS_EXPECTED[level_name]])
				continue
			_check(named.is_empty(), "%s generation %d: every drop lands where its rim or a way out can be walked to (%d trap pits, landing at %s)" % [level_name, generation, named.size(), named.slice(0, 8)])
	_check(drops[0] > 0, "the levels have drops to check (%d ledge steps)" % drops[0])
	# The check itself: the test room with a sheer pit sunk in it, then with a
	# stair cut up its side.
	var room := Level.load_level("test_room")
	World.load_terrain(room["terrain"])
	var low := Vector2i(1 << 20, 1 << 20)
	var high := -low
	for cell: Vector2i in room["terrain"]["floor"]:
		low = low.min(cell)
		high = high.max(cell)
	var size := high + Vector2i(2, 2)
	var pit := Rect2i(low + Vector2i(2, 2), Vector2i(2, 2))
	var field := PackedFloat32Array()
	field.resize(size.x * size.y)
	for y in size.y:
		for x in size.x:
			field[y * size.x + x] = 0.0 if pit.has_point(Vector2i(x, y)) else 4 * Relief.LEVEL_M
	World._relief = field
	World._relief_size = size
	var shut := _trap_landings(room, [0])
	_check(shut.size() == 1 and str(shut[0]).contains("(4 cells, 4 levels down"), "a sheer pit four levels deep is named a trap (%s in %s)" % [shut, pit])
	# A slope out: the four cells east of the pit's top row rising 0.4 m
	# each (under Relief.WALK_RISE) to the room's 2 m.
	for i in 4:
		var at := Vector2i(pit.end.x + i, pit.position.y)
		field[at.y * size.x + at.x] = (i + 1) * 0.4
	World._relief = field
	var sloped := _trap_landings(room, [0])
	_check(sloped.is_empty(), "with a slope up its east side it is not (%s)" % [sloped])


## Decision 794: every shipped level's mine track ("mine_track" decor, as
## World loads it into _track) is one a cart can roll: no cell with three
## or more track neighbours, a bend piece (2) only where its two neighbours
## turn, a straight (1) only where they run on, every end a buffer (3), and
## no track across a wall or cliff or on a stair (_track_faults).
func _test_mine_track() -> void:
	print("\n== mine track a cart can roll: no forks, bends on bends, buffers at ends, no cliffs or stairs (794) ==")
	var pieces := 0
	for folder in DirAccess.get_directories_at(Level.DIR):
		if Level.DIR + folder + "/" == Prefab.DIR or not FileAccess.file_exists(Level.DIR + folder + "/layout.png"):
			continue
		var level := Level.load_level(folder)
		if level.is_empty():
			continue
		World.load_terrain(level["terrain"])
		if World._track.is_empty():
			continue
		pieces += World._track.size()
		var faults := _track_faults()
		_check(faults.is_empty(), "%s: its %d track pieces roll (%s)" % [folder, World._track.size(), faults.slice(0, 8)])
	_check(pieces > 0, "the levels have track to check (%d pieces)" % pieces)
	# The check itself, on the test room's floor.
	var room := Level.load_level("test_room")
	World.load_terrain(room["terrain"])
	var good := {Vector2i(2, 2): 3, Vector2i(3, 2): 1, Vector2i(4, 2): 2, Vector2i(4, 3): 1, Vector2i(4, 4): 3}
	World._track.assign(good)
	_check(_track_faults().is_empty(), "a run, a bend and a buffer at each end rolls (%s)" % [_track_faults()])
	var bad := {
		"a fork": {Vector2i(4, 1): 3},
		"a straight on the bend": {Vector2i(4, 2): 1},
		"a bend on a straight": {Vector2i(3, 2): 2},
		"an open end": {Vector2i(4, 4): 1},
	}
	for name: String in bad:
		World._track.assign(good)
		World._track.merge(bad[name], true)
		_check(not _track_faults().is_empty(), "%s is named (%s)" % [name, _track_faults()])
	World._track.clear()


## World._step_blocked, the step check read from find_path's step cache,
## gives what _terrain_blocks_step does: over each shipped level's cells by
## an edge (walls, doors) and a spread of the rest, every way, opening
## doors or not. A level's first difference is named.
func _test_step_cache() -> void:
	print("\n== a step's check from the paths' cache answers as the full check does (perf) ==")
	var asked := 0
	for folder in DirAccess.get_directories_at(Level.DIR):
		if Level.DIR + folder + "/" == Prefab.DIR or not FileAccess.file_exists(Level.DIR + folder + "/layout.png"):
			continue
		var level := Level.load_level(folder)
		if level.is_empty():
			continue
		World.load_terrain(level["terrain"])
		var edged := {}
		for key: Vector3i in level["terrain"].get("edges", {}):
			edged[Vector2i(key.x, key.y)] = true
			edged[Vector2i(key.x, key.y) + (Vector2i(1, 0) if key.z == Terrain.EAST else Vector2i(0, 1))] = true
		var cells: Array = level["terrain"]["floor"].keys() if level["terrain"]["floor"] is Dictionary else level["terrain"]["floor"]
		var stride := maxi(1, cells.size() / 1500)
		var picked: Array[Vector2i] = []
		var edge_stride := maxi(1, edged.size() / 3000)
		var n := 0
		for cell: Vector2i in edged:
			if n % edge_stride == 0:
				picked.append(cell)
			n += 1
		for i in range(0, cells.size(), stride):
			picked.append(cells[i])
		var differ := ""
		for cell in picked:
			for direction: Vector2i in World.DIRECTIONS:
				for opens in [false, true]:
					asked += 1
					var full := World._terrain_blocks_step(cell, direction, opens)
					if World._step_blocked(cell, direction, opens) != full and differ.is_empty():
						differ = "%s %s opens=%s: full %s" % [cell, direction, opens, full]
		_check(differ.is_empty(), "%s: %d cells, the cache's answers the full check's (%s)" % [folder, picked.size(), differ if not differ.is_empty() else "none differ"])
	_check(asked > 0, "steps compared (%d)" % asked)


## What in World's loaded track a cart can't roll (decision 794): each
## fault as "cell: what".
func _track_faults() -> Array:
	var out := []
	var ways: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for cell: Vector2i in World._track:
		var variant: int = World._track[cell]
		var near: Array[Vector2i] = []
		for way in ways:
			if World._track.has(cell + way):
				near.append(way)
				if World._terrain_blocks_step(cell, way, false, true):
					out.append("%s: across a wall or cliff %s" % [cell, way])
		if World.stair_at(cell) != Vector2i.ZERO:
			out.append("%s: on a stair" % cell)
		var turns := near.size() == 2 and near[0] != -near[1]
		if near.size() >= 3:
			out.append("%s: %d track neighbours" % [cell, near.size()])
		elif near.size() <= 1 and variant != 3:
			out.append("%s: an end not a buffer" % cell)
		elif variant == 2 and not turns:
			out.append("%s: a bend piece on a straight" % cell)
		elif variant == 1 and turns:
			out.append("%s: a straight piece on a bend" % cell)
	return out


## The landing cells (with the region's size, the drop and its rim), one per region, of ledges in World's loaded terrain that
## lead where neither the rim nor a way out can be walked to. Regions are
## filled over walking steps (_terrain_blocks_step with heights, doors
## opened); a way out is a link not closed or a cell on an edge with a
## neighbour (level.json "neighbours"). A ledge is an orthogonal step down
## (height_step > 0) from rim A to floor B with no wall between. [param drops]
## [0] counts the ledges seen.
func _trap_landings(level: Dictionary, drops: Array) -> Array:
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	var size: Vector2i = level.get("size", Vector2i.ZERO)
	var neighbours: Dictionary = level.get("neighbours", {})
	var exits := {}
	for link: Dictionary in level["links"]:
		if not link["closed"]:
			exits[link["tile"]] = true
	var region := {}
	var has_exit: Array[bool] = []
	for start: Vector2i in level["terrain"]["floor"]:
		if region.has(start) or not World.is_walkable(start):
			continue
		var id := has_exit.size()
		var out := false
		region[start] = id
		var queue: Array[Vector2i] = [start]
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_back()
			if exits.has(cell):
				out = true
			for d: Vector2i in dirs.slice(0, 4):
				var side := WorldMap.side_off(size, cell + d)
				if not side.is_empty() and neighbours.has(side):
					out = true
			for d: Vector2i in dirs:
				var next := cell + d
				if region.has(next) or World._terrain_blocks_step(cell, d, true, true):
					continue
				region[next] = id
				queue.append(next)
		has_exit.append(out)
	var traps := {}
	for rim: Vector2i in region:
		for d: Vector2i in dirs.slice(0, 4):
			var below := rim + d
			if not region.has(below) or World.height_step(rim, d) <= 0 or World.edge_blocks(rim, d, true):
				continue
			drops[0] += 1
			var landing: int = region[below]
			if landing != region[rim] and not has_exit[landing] and not traps.has(landing):
				traps[landing] = [below, rim, World.height_step(rim, d)]
	var cells := {}
	for at: Vector2i in region:
		cells[region[at]] = int(cells.get(region[at], 0)) + 1
	var named: Array = []
	for landing: int in traps:
		var trap: Array = traps[landing]
		named.append("%s (%d cells, %d levels down from %s)" % [trap[0], cells[landing], trap[2], trap[1]])
	named.sort()
	return named


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


## levels/hills (decision 525's relief, tools/make_hills.gd): a bot walks
## from the link up the plateau's spur onto its top and back down; a body
## pushed off its sheer face falls by the drop's levels; the plateau sees
## the valley below (its low wall gone, 776); the ridge hides
## the valley from the west.
func _test_hills() -> void:
	print("
== levels/hills: relief to walk, fall from and see over ==")
	_check(_main.load_map("hills") and World.outdoor and World.has_relief(), "hills loads, outdoors, its ground in metres")
	var player := _player()
	# 756: the plateau east of column 168, its face straight from the fall to
	# its spur; the valley's flank below it.
	var plateau := Vector2i(180, 44)
	var foot := Vector2i(160, 44)
	_check(World.elevation_at(plateau) - World.elevation_at(foot) > 4.0, "the plateau stands over the valley (%.1f m over %.1f)" % [World.elevation_at(plateau), World.elevation_at(foot)])
	var path := World.find_path(player.tile, plateau)
	_check(not path.is_empty(),
		"a way up to the plateau (%d steps)" % path.size())
	_walk_free(player, plateau)
	_check(player.tile == plateau, "the bot walks up there, round by the spur (%s)" % player.tile)
	_walk_free(player, foot)
	_check(player.tile == foot, "and back down to the valley (%s)" % player.tile)
	# The rim on row 38 (776: no low wall below it now): the first cell east of the
	# valley standing well over the one west of it.
	var rim := Vector2i(168, 38)
	for x in range(160, 174):
		if World.elevation_at(Vector2i(x, 38)) - World.elevation_at(Vector2i(x - 1, 38)) > 2.0:
			rim = Vector2i(x, 38)
			break
	var imp: Monster = _main._spawn({"script": Level.MONSTER, "shape": "capsule", "name": "Faller", "tile": rim, "props": {"sight_range": 0, "max_hp": 200}})
	_put(player, rim + Vector2i(1, 0))
	_pushes.clear()
	var hp := imp.hp
	var drop := World.elevation_at(rim) - World.elevation_at(rim - Vector2i(1, 0))
	World._push(player, imp, Vector2i(-1, 0), 3.0)
	# 783: fall_hp_per_level a level, and fall_lethal_levels or more kills outright.
	var levels := Relief.levels(drop)
	var owed: int = hp if levels >= World.fall_lethal_levels else World.fall_hp_per_level * levels
	_check(imp.tile.x < rim.x and hp - imp.hp == owed,
			"pushed off the face: it falls %.1f m, %d levels, for %d (%s, %s)" % [drop, Relief.levels(drop), hp - imp.hp, imp.tile, _pushes.back()["stopped_by"]])
	World.despawn(imp)
	_check(World.has_line_of_sight(rim + Vector2i(1, -1), Vector2i(156, 38)), "from the plateau's rim the valley below is seen")
	# Along the west escarpment (756: its face near columns 36 to 44) there
	# is ground behind its crest: some of it hidden from the valley floor.
	var hidden := []
	for row in range(20, 200, 6):
		if not World.is_walkable(Vector2i(56, row)):
			continue
		var crest := Vector2i(-1, row)
		for x in range(0, 46):
			var cell := Vector2i(x, row)
			if World.is_walkable(cell) and (crest.x < 0 or World.elevation_at(cell) > World.elevation_at(crest)):
				crest = cell
		for x in range(0, crest.x - 1):
			var behind := Vector2i(x, row)
			if World.is_walkable(behind) and not World.has_line_of_sight(Vector2i(56, row), behind):
				hidden.append(behind)
	_check(hidden.size() >= 1, "the ridge hides ground behind its crest from the valley floor (%d cells)" % hidden.size())


## The console's "move" (decision 531): the player by name to the nearest
## walkable cell in a zone (by travel, which brings a companion along: the
## link tests'); refused with
## nothing moved for no such player, zone, a cell off the map or with no
## floor near it; no id in any reply.
func _test_admin_move() -> void:
	print("== admin: move a player ==")
	_main.load_map("test_room")
	var player := _player()
	var record: PlayerRecord = _main._records.get(_main._peer_ids.get(player.owner_peer, ""))
	# The name they joined with: the node's own (Player1) may change as it
	# is spawned again in another zone.
	var who := record.name
	var reply: String = _main.admin_command("move %s 13 15 sample" % who)
	var moved := _player()
	_check(moved != null and moved.zone == "sample" and World.distance(moved.tile, Vector2i(13, 15)) <= 1 and reply.begins_with("moved %s" % who),
		"move %s 13 15 sample: there (%s; %s)" % [who, moved.tile if moved else "none", reply])
	reply = _main.admin_command("move %s 2 6" % who)
	_check(_player().zone == "sample" and World.distance(_player().tile, Vector2i(2, 6)) <= 1, "no zone: within their own (%s)" % reply)
	var at := _player().tile
	var refusals := {"move Nobody 3 3": "no player Nobody online", "move %s 3 3 no_such_zone" % who: "no zone no_such_zone",
		"move %s 900 3" % who: "off sample's map", "move %s x 3" % who: "move <player> <x> <y>"}
	for line: String in refusals:
		reply = _main.admin_command(line)
		_check(refusals[line] in reply and _player().tile == at and _player().zone == "sample", "%s: refused, not moved (%s)" % [line, reply])
	_check(record == null or not record.player_id in reply, "no id in the reply")
	var far := {"terrain": {"floor": [Vector2i(20, 20)]}}
	_check(_main._walkable_near(far, Vector2i(0, 0)) == World.NO_CELL and _main._walkable_near(far, Vector2i(14, 15)) == Vector2i(20, 20),
		"nothing walkable within %d: none (refused); within it, the nearest floor" % _main.MOVE_REACH)
	_main.load_map("test_room")


## A solid building (decision 550): building.mound's footprint is no floor
## but its door (the front row's middle), in terrain "solid", no inside, no
## open edges said; it stops sight and a walker, routes go round; refused
## off clear floor like any building; the wilds' mound on the barrow's link.
func _test_solid() -> void:
	print("== a solid building: the mound ==")
	var rows: Array[String] = []
	for y in 2 * 18 - 1:
		rows.append(".".repeat(2 * 20 - 1))
	var config := {"outdoor": true, "buildings": [{"slot": "building.mound", "at": [4, 3], "facing": [0, 1]}]}
	var level := Level.parse(Level.image_from_rows(rows, {Vector2i(1, 1): "start"}), null, config)
	var terrain: Dictionary = level["terrain"]
	var mound: Dictionary = level["buildings"][0] if not level["buildings"].is_empty() else {}
	# 12 x 12 (Jeff's mound at twice its first size): its door the west of
	# the front row's middle pair.
	_check(mound.get("door") == Vector2i(9, 14) and terrain["solid"].size() == 143 and Vector2i(9, 14) in terrain["floor"]
		and not Vector2i(9, 8) in terrain["floor"] and Vector2i(9, 8) in terrain["solid"], "its cells no floor but its door, the front row's middle (%s)" % [mound.get("door")])
	_check(level["warnings"].is_empty() and not level["building_cells"].has(Vector2i(9, 8)), "no inside, no open edges said (%s)" % [level["warnings"]])
	var uneven := Level.parse(Level.image_from_rows(rows, {Vector2i(1, 1): "start", Vector2i(5, 4): "water"}), null, config)
	_check(uneven["buildings"].is_empty() and not uneven["terrain"]["solid"].size(), "off clear floor it is left out, like any building")
	Level.register("lt_mound", Level.image_from_rows(rows, {Vector2i(1, 1): "start"}), null, config)
	_check(_main.load_map("lt_mound"), "the level loads")
	_check(not World.is_walkable(Vector2i(9, 8)) and World.is_walkable(Vector2i(9, 14)), "nobody walks onto it; its door is walked")
	_check(not World.has_line_of_sight(Vector2i(9, 1), Vector2i(9, 16)) and World.has_line_of_sight(Vector2i(1, 1), Vector2i(18, 1)), "it stops sight across it, not beside it")
	var path := World.find_path(Vector2i(9, 1), Vector2i(9, 16))
	_check(not path.is_empty() and path.all(func(cell: Vector2i) -> bool: return not cell in terrain["solid"]), "a path goes round it (%d steps)" % path.size())
	_main.load_map("test_room")
	Level.unregister("lt_mound")
	var wilds := Level.load_level("wilds")
	var mounds: Array = wilds["buildings"].filter(func(b: Dictionary) -> bool: return b["slot"] == "building.mound")
	var link: Array = wilds["links"].filter(func(l: Dictionary) -> bool: return l["to_map"] == "barrow" and l["to_spawn"] == "from_breach")
	_check(mounds.size() == 1 and not link.is_empty() and mounds[0]["door"] == link[0]["tile"] and wilds["spawn_points"].get("from_barrow") == Vector2i(160, 159)
		and not Vector2i(160, 159) in wilds["terrain"]["solid"], "the wilds' mound stands, its door on the barrow's link, from_barrow outside (%s)" % [wilds["warnings"]])
	# The testing kit's chests by Snagfin's stall are gone (Jeff, 11-05: "remove chests from town";
	# 734 amended (7)): a saved world's kit goes to the town's store (_test_removed_to_temple).
	var kit: Array = wilds["entities"].filter(func(spec: Dictionary) -> bool:
		return spec["tile"] in [Vector2i(205, 208), Vector2i(206, 208), Vector2i(206, 207)])
	_check(kit.is_empty(), "no testing kit's chest by the stall now (%s)" % [kit])
	# 599, maps' side: the old farmstead's cache in the north hut, the hut's kits moved into it.
	var cache: Array = wilds["entities"].filter(func(spec: Dictionary) -> bool: return spec["tile"] == Vector2i(119, 139))
	var props: Dictionary = cache[0].get("props", {}) if cache.size() == 1 else {}
	var kits: Array = wilds["entities"].filter(func(spec: Dictionary) -> bool:
			return spec["tile"] in [Vector2i(122, 138), Vector2i(120, 152)] and "bandaging_kit" in Array(spec.get("props", {}).get("slots", [])))
	_check(props.get("cache") == "farmstead_cache" and props.get("cache_place") == "the old farmstead" and Array(props.get("slots", [])).all(func(id: String) -> bool: return id.is_empty())
			and kits.is_empty() and not wilds["warnings"].any(func(w: String) -> bool: return "119, 139" in w),
			"the farmstead's cache stands at (119, 139), its slots empty, the hut chests' kits gone (%s)" % [props])


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


## levels/forest (decision 464): the way to the elven stronghold, under a
## canopy, its clearings listed for terrain and environment; in from the
## wilds on the west, the way on east closed (463), walkable from one to
## the other.
func _test_forest() -> void:
	print("== levels/forest ==")
	var forest := Level.load_level("forest")
	var links: Array = forest.get("links", [])
	# The boar's lair is held back (820) till the boar king's package: no link then.
	var lairs: Array = links.slice(2).filter(func(link: Dictionary) -> bool: return link["to_map"] != "boar_lair" or not Level.SHELVED.has("boar_lair"))
	_check(forest.get("display_name") == "The Forest" and links.size() == 2 + lairs.size() and links[0]["to_map"] == "wilds"
		and links[1]["to_map"] == "stronghold" and links[1]["closed"]
		and lairs.map(func(link: Dictionary) -> String: return link["to_map"]) == (["wolf_cave"] if Level.SHELVED.has("boar_lair") else ["boar_lair", "wolf_cave"])
		and lairs.all(func(link: Dictionary) -> bool: return not link["closed"]),
		"The Forest: back to the wilds, on to the stronghold closed, the wolves' cave open, the boar's lair open or held back (%s)" % [links])
	_check(_main.load_map("forest") and World.outdoor, "forest loads, outdoors")
	var player := _player()
	var east: Vector2i = links[1]["tile"]
	var path := World.find_path(player.tile, east)
	_check(not path.is_empty(), "a way from the way in to the way on (%d steps)" % path.size())
	# Safe paths, places near them (760; Jeff: "zones need to have safe paths with activities
	# not too far off the paths"): every refuge and clearing within 20 cells' walk of a path.
	var floor := {}
	for cell: Vector2i in forest["terrain"]["floor"]:
		floor[cell] = true
	var off := {}
	var todo: Array[Vector2i] = []
	for cell: Vector2i in forest["terrain"]["kinds"]:
		if forest["terrain"]["kinds"][cell] == "dirt" and floor.has(cell):
			off[cell] = 0
			todo.append(cell)
	var head := 0
	while head < todo.size():
		var at := todo[head]
		head += 1
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if floor.has(at + step) and not off.has(at + step):
				off[at + step] = off[at] + 1
				todo.append(at + step)
	var far := []
	for key: String in forest["places"]:
		var place: Dictionary = forest["places"][key]
		if place["kind"] == "refuge" and int(off.get(place["cell"], 999)) > 20:
			far.append([key, off.get(place["cell"], "unreached")])
	for clearing: Dictionary in forest.get("clearings", []):
		var centre := Vector2i(int(clearing["centre"][0]), int(clearing["centre"][1]))
		if int(off.get(centre, 999)) > 20:
			far.append([centre, off.get(centre, "unreached")])
	_check(not todo.is_empty() and far.is_empty(), "every refuge and clearing within 20 cells' walk of a path (%d path cells; too far: %s)" % [off.values().count(0), far])
	_check(_main.load_map("test_room"), "back to the test room")
	var sample := Level.load_level("sample")
	var bridges: Array = sample["buildings"].filter(func(b: Dictionary) -> bool: return b["slot"] == Level.BRIDGE)
	_check(sample["terrain"]["streams"].size() == 1 and Array(sample["terrain"]["fords"]) == [Vector2i(12, 8)] and bridges.size() == 1
		and Array(sample["terrain"]["bridged"]) == [Vector2i(12, 10)], "the sample's stream, with its ford and its bridge (decision 505)")
	var markets := WorldMap.build().markets()
	_check(markets.get("market:castle", {}).get("cell") == Vector2i(16, 9) and markets["market:castle"]["area"] == "castle"
		and markets["market:castle"]["name"] == "the castle market", "the castle market, in the keep (decision 504; %s)" % [markets])
	var warnings: Array[String] = []
	Level.markets_from({"markets": {"x": {"name": "no cell"}}}, warnings)
	_check(warnings.size() == 1, "a market with no cell warns (%s)" % [warnings])


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


func _test_fold() -> void:
	print("
== a sheep fold: open to the sky, fenced, its gate the front's middle two cells (decision 640) ==")
	var map := LevelMap.new(Vector2i(10, 10))
	for y in 10:
		for x in 10:
			map.set_cell(Vector2i(x, y), "grass")
	map.set_cell(Vector2i(0, 0), "start")
	var config := _stamp(map, {}, "building_fold", Vector2i(1, 1))
	var level := Level.parse(map.to_image(), null, config)
	var folds := (level["buildings"] as Array).filter(func(b: Dictionary) -> bool: return b["slot"] == "building.fold")
	var said := (level["warnings"] as Array).filter(func(text: String) -> bool: return text.contains("building") or text.contains("fold"))
	_check(folds.size() == 1 and folds[0]["rect"] == Rect2i(2, 2, 6, 6) and folds[0]["facing"] == Vector2i(0, 1) and said.is_empty(),
			"the prefab's fold is 6 x 6, its front south, its gate not said to be open (%s, %s)" % [folds, level["warnings"]])
	var edges: Dictionary = level["terrain"]["edges"]
	var open := Level.outline(Rect2i(2, 2, 6, 6)).filter(func(key: Vector3i) -> bool: return edges.get(key) != Terrain.Edge.WALL)
	open.sort()
	_check(open == [Vector3i(4, 7, Terrain.SOUTH), Vector3i(5, 7, Terrain.SOUTH)], "fenced all round but the gate, two cells wide (%s)" % [open])
	Level.register("test_fold", map.to_image(), null, config)
	_check(_main.load_map("test_fold"), "the level with a fold loads")
	_check(World.edge_blocks(Vector2i(2, 4), Vector2i(-1, 0)) and World.edge_blocks(Vector2i(6, 7), Vector2i(0, 1)), "the fence stops a walker")
	_check(not World.edge_blocks(Vector2i(4, 7), Vector2i(0, 1)) and not World.edge_blocks(Vector2i(5, 7), Vector2i(0, 1)),
			"the gate lets two abreast through")
	_check(World.has_line_of_sight(Vector2i(0, 4), Vector2i(9, 4)), "sight crosses the fence")
	_check(Level.rect_cells(Rect2i(2, 2, 6, 6)).all(func(cell: Vector2i) -> bool: return not World.fields._roofed.has(cell)),
			"nothing of the fold is roofed")
	Level.unregister("test_fold")


func _test_canopy() -> void:
	print("
== a canopy: trunks from a grown stand, cover from the trunks, open in a clearing ==")
	var map := LevelMap.new(Vector2i(16, 12))
	for y in 12:
		for x in 16:
			map.set_cell(Vector2i(x, y), "grass")
	map.set_cell(Vector2i(0, 0), "start")
	map.set_cell(Vector2i(6, 6), "dirt")
	var trees_path := preload("res://tests/test_ports.gd").scratch("canopy_trees.json")
	DirAccess.make_dir_recursive_absolute(trees_path.get_base_dir())
	var trees := [{"at": [3.4, 3.6], "height": 12.0}, {"at": [5.2, 3.1], "height": 9.0, "state": "snag"},
		{"at": [6.5, 6.5], "height": 11.0}, {"at": [8.5, 4.5], "height": 1.2}, {"at": [0.5, 0.5], "height": 10.0}]
	var file := FileAccess.open(trees_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"trees": trees}))
	file.close()
	_check(ForestPack.from_trees(map, trees_path) == 2 and map.cell(Vector2i(3, 3)) == "void" and map.cell(Vector2i(5, 3)) == "void",
			"ForestPack makes a trunk under each tree of 3 m or more, a snag too")
	_check(map.cell(Vector2i(6, 6)) == "dirt" and map.cell(Vector2i(8, 4)) == "grass" and map.cell(Vector2i(0, 0)) == "start",
			"but never on the path's dirt or a marker, nor for undergrowth")
	_check(ForestPack.from_trees(map, trees_path + ".missing") == 0, "no trees file: no trunks")
	var config := {"canopy": {"kind": "evergreen"}, "clearings": [{"centre": [12.5, 8.5], "radius": 2.0}, {"centre": "x"}]}
	# A void cell out by the clearing, so it would be shaded but for it.
	map.set_cell(Vector2i(13, 7), "void")
	var level := Level.parse(map.to_image(), null, config)
	var cover: Dictionary = level["terrain"]["canopy"]
	var expect := func(cell: Vector2i) -> float:
		var total := 0.0
		for trunk: Vector2i in [Vector2i(3, 3), Vector2i(5, 3), Vector2i(13, 7)]:
			var d := Vector2(cell - trunk).length()
			if d < Level.CANOPY_REACH:
				total += 1.0 - d / Level.CANOPY_REACH
		return minf(total, 1.0)
	var near := Vector2i(2, 5)
	_check(is_equal_approx(cover.get(near, 0.0), expect.call(near)) and cover.get(near, 0.0) > 0.2 and cover.get(near, 0.0) < 0.5
			and is_equal_approx(cover.get(Vector2i(4, 3), 0.0), 1.0),
			"cover adds 1 - d / %s from each trunk, capped at 1 (%.2f at %s, %.2f between the trunks)" % [Level.CANOPY_REACH, cover.get(near, 0.0), near, cover.get(Vector2i(4, 3), 0.0)])
	_check(not cover.has(Vector2i(9, 9)) and not cover.has(Vector2i(12, 8)) and cover.has(Vector2i(13, 6)),
			"none far from a trunk, none in the clearing, some past its radius")
	var said := (level["warnings"] as Array).filter(func(text: String) -> bool: return text.contains("clearing"))
	_check(level["terrain"]["canopy_kind"] == "evergreen" and level["terrain"]["clearings"].size() == 1 and said.size() == 1,
			"the kind read, the bad clearing left out and said (%s)" % [said])
	var odd := Level.parse(map.to_image(), null, {"canopy": {"kind": "palm"}})
	_check(odd["terrain"]["canopy_kind"] == "evergreen" and (odd["warnings"] as Array).any(func(text: String) -> bool: return text.contains("palm")),
			"a kind not known is said and read as evergreen")
	_check((Level.parse(map.to_image(), null, {})["terrain"]["canopy"] as Dictionary).is_empty(), "no canopy in level.json: no cover, trunks or not")
	Level.register("test_canopy", map.to_image(), null, config)
	_check(_main.load_map("test_canopy"), "the level with a canopy loads")
	_check(is_equal_approx(World.fields.canopy_at(near), cover[near]) and World.fields.canopy_at(Vector2i(12, 8)) == 0.0
			and World.fields.canopy_kind == "evergreen" and World.fields.clearings.size() == 1, "and World's fields answer canopy_at from it")
	_check(not World.is_walkable(Vector2i(3, 3)) and not World.has_line_of_sight(Vector2i(2, 3), Vector2i(4, 3)), "a trunk stops walkers and sight")
	Level.unregister("test_canopy")
	DirAccess.remove_absolute(trees_path)


## Building kinds (decision 488): every kind's every size is blocks that
## meet and do not overlap, its doors on its outline and one in its front;
## stamped from its prefab at each of four turns it stands with nothing
## said, walled round its blocks but its doors; an L-house loaded: its
## wing inside and roofed, the corner its box leaves empty neither; a ruin
## has no inside and no roof.
func _test_kinds() -> void:
	print("\n== building kinds: blocks, doors, stamped at four turns, an L-house inside, a ruin ==")
	var bad: Array[String] = []
	for kind: String in Level.kinds():
		for size: String in Level.kinds()[kind]["sizes"]:
			var entry := {"kind": kind, "size": size, "at": [0, 0]}
			var blocks := Level.building_blocks(entry)
			var cells := Level._union(blocks)
			var area := 0
			for block in blocks:
				area += block.get_area()
			var reached := {cells[0]: true}
			var todo: Array[Vector2i] = [cells[0]]
			while not todo.is_empty():
				var at: Vector2i = todo.pop_back()
				for side: Vector2i in Level.SIDES.values():
					if cells.has(at + side) and not reached.has(at + side):
						reached[at + side] = true
						todo.append(at + side)
			var outline := Level.blocks_outline(cells)
			var doors := Level.kind_doors(entry) + Level.kind_open(entry)
			var rect: Rect2i = Level.building_rect(entry)
			if area != cells.size() or reached.size() != cells.size() or doors.is_empty() \
					or not doors.all(func(key: Vector3i) -> bool: return key in outline) \
					or not doors.any(func(key: Vector3i) -> bool: return key.z == Terrain.SOUTH and key.y == rect.end.y - 1):
				bad.append("%s %s" % [kind, size])
	_check(bad.is_empty() and Prefab.kind_names().size() >= 30, "every kind's sizes: blocks meeting, not overlapping, a door in front (%d prefabs; bad %s)" % [Prefab.kind_names().size(), bad])
	var cramped: Array[String] = []
	for kind: String in Level.kinds():
		for size: String in Level.kinds()[kind]["sizes"]:
			var main := Level.main_block(Level.kinds()[kind]["sizes"][size])
			if mini(main.size.x, main.size.y) < Level.MIN_ROOM:
				cramped.append("%s %s %s" % [kind, size, main.size])
	_check(cramped.is_empty(), "every kind's main block at least %d x %d floor cells (Jeff's minimum; under: %s)" % [Level.MIN_ROOM, Level.MIN_ROOM, cramped])
	var unfit: Array[String] = []
	for kind: String in Level.kinds():
		var plot := Level.plot_of(kind)
		var stage := str(Level.kinds()[kind].get("stage", ""))
		if not stage in Level.STAGES and stage != Level.SET_STAGE or plot == Vector2i.ZERO:
			unfit.append(kind)
		for size: String in Level.kinds()[kind]["sizes"]:
			var frame := Level._frame(Level.kinds()[kind]["sizes"][size])
			if frame.x > plot.x or frame.y > plot.y:
				unfit.append("%s %s %s in %s" % [kind, size, frame, plot])
	var hamlet := Level.kinds_at("hamlet")
	_check(unfit.is_empty() and "inn" in hamlet and "temple" in hamlet and not "house" in hamlet and "house" in Level.kinds_at("village")
			and not "market" in Level.kinds_at("town") and Level.kinds_at("city").size() == Level.kinds().size() - 1
			and not "tower_room" in Level.kinds_at("city") and Level.kinds_at("ruin").is_empty(),
			"each kind a stage and a plot class it fits (591): a hamlet's %d kinds (its inn and temple), a city every one but the set piece's room (unfit %s)" % [hamlet.size(), unfit])
	# A settlement raises its camp alone (649): open all round, no roof, no inside.
	var narrow: Array[String] = []
	for kind: String in Level.kinds():
		for size: String in Level.kinds()[kind]["sizes"]:
			if not Level.narrow_joins(Level.kinds()[kind]["sizes"][size]).is_empty():
				narrow.append("%s %s" % [kind, size])
	var pinched := Level.narrow_joins({"blocks": [[0, 0, 5, 5, "main"], [5, 4, 3, 3, "wing"]]})
	var small_classes := Level.PLOT_CLASSES.keys().filter(func(each: String) -> bool:
		return mini(Level.PLOT_CLASSES[each].x, Level.PLOT_CLASSES[each].y) < Level.MIN_ROOM)
	_check(narrow.is_empty() and pinched.size() == 1 and small_classes.is_empty(),
			"no kind's blocks meet across one cell (a pinched pair found: %s; narrow %s), no plot class under %d (%s)" % [pinched, narrow, Level.MIN_ROOM, small_classes])
	var camp_map := LevelMap.new(Vector2i(9, 9))
	for y in 9:
		for x in 9:
			camp_map.set_cell(Vector2i(x, y), "grass")
	camp_map.set_cell(Vector2i(0, 0), "start")
	var camp_level := Level.parse(camp_map.to_image(), null, {"outdoor": true, "buildings": [{"kind": "camp", "size": "large", "at": [1, 1], "facing": [0, 1]}]})
	var camps := (camp_level["buildings"] as Array).filter(func(each: Dictionary) -> bool: return each.get("kind", "") == "camp")
	var camp: Dictionary = camps[0] if camps.size() == 1 else {}
	var walled := Level.building_outline(camp).filter(func(key: Vector3i) -> bool: return camp_level["terrain"]["edges"].has(key)) if not camp.is_empty() else []
	_check(Level.kinds_at("settlement") == ["camp"] and "camp" in Level.kinds_at("hamlet") and not camp.is_empty()
			and Level.roofless(camp) and not Level.has_inside(camp) and walled.is_empty() and Level.plot_of("camp") == Level.PLOT_CLASSES["S"],
			"a settlement's one kind the camp (649): roofless, no inside, no wall round it (%s, %s)" % [Level.kinds_at("settlement"), walled])
	var unsaid: Array[String] = []
	for prefab_name in Prefab.kind_names():
		for turns in 4:
			var prefab := Prefab.rotated(Prefab.load_prefab(prefab_name), turns)
			var config: Dictionary = prefab["config"]
			var level := Level.parse(prefab["map"].to_image(), null, config)
			var said := (level["warnings"] as Array).filter(func(text: String) -> bool: return not text.begins_with("no player start"))
			var standing: Array = level["buildings"]
			# Walled round but its open edges (a forge's front), and a way in.
			if not said.is_empty() or standing.size() != 1 or Level.building_outline(standing[0]).any(func(key: Vector3i) -> bool:
					return not level["terrain"]["edges"].has(key) and not key in standing[0]["open"]) 					or not Level.building_outline(standing[0]).any(func(key: Vector3i) -> bool:
					return level["terrain"]["edges"].get(key) == Terrain.Edge.DOOR or key in standing[0]["open"]):
				unsaid.append("%s turned %d: %s" % [prefab_name, turns, said])
	_check(unsaid.is_empty(), "each kind's prefab at four turns: walled round its blocks but its open edges, a way in, nothing said (%s)" % [unsaid])
	var forge := Prefab.load_prefab("building_forge_small")
	var forged := Level.parse(forge["map"].to_image(), null, forge["config"])
	var smithy: Dictionary = forged["buildings"][0]
	var front_open := (smithy["open"] as Array).size() == 6 and (smithy["open"] as Array).all(func(key: Vector3i) -> bool:
		return not forged["terrain"]["edges"].has(key))
	var site := Level.site_cells(smithy)
	_check(front_open and (smithy["doors"] as Array).is_empty() and not Level.building_cells(smithy).has(smithy["front"])
			and Level.building_cells(smithy).has(site["work"]),
			"the forge: its lean-to's front open (no wall, no door), its front and its work found from it (%s)" % [smithy["front"]])
	# An L-house and a ruined hut, loaded.
	var map := LevelMap.new(Vector2i(24, 14))
	for y in 14:
		for x in 24:
			map.set_cell(Vector2i(x, y), "grass")
	map.set_cell(Vector2i(0, 0), "start")
	var config := _stamp(map, {}, "building_l_house_small", Vector2i(1, 1))
	config = _stamp(map, config, "building_hut_small", Vector2i(14, 1))
	(config["buildings"] as Array)[1]["ruined"] = true
	var level := Level.parse(map.to_image(), null, config)
	var house: Dictionary = level["buildings"][0]
	_check(house["kind"] == "l_house" and house["blocks"] == [Rect2i(2, 2, 6, 8), Rect2i(8, 6, 4, 4)] and house["rect"] == Rect2i(2, 2, 10, 8)
			and house["words"] == "a house" and house["front"] == Vector2i(4, 10),
			"the L-house: its main block and wing, its box, its words and the cell before its door (%s)" % [house])
	_check(level["building_cells"].size() == 64 and level["building_cells"].get(Vector2i(9, 7)) == 0 and not level["building_cells"].has(Vector2i(9, 3))
			and not level["building_cells"].has(Vector2i(15, 3)), "inside: the main block and wing (64 cells), not the empty corner, not the ruin")
	Level.register("test_kinds", map.to_image(), null, config)
	_check(_main.load_map("test_kinds"), "the level with kinds loads")
	_check(Companion.building_at(Vector2i(9, 7)).get("kind") == "l_house" and Companion.building_at(Vector2i(9, 3)).is_empty()
			and Companion.building_at(Vector2i(15, 3)).is_empty(), "a companion is inside the house in its wing, not in its corner, not in the ruin")
	_check(World.fields._roofed.has(Vector2i(9, 7)) and not World.fields._roofed.has(Vector2i(9, 3)) and not World.fields._roofed.has(Vector2i(15, 3)),
			"roofed over the wing; not the corner, not the ruin")
	_check(World.edge_blocks(Vector2i(9, 5), Vector2i(0, 1)) and not World.edge_blocks(Vector2i(8, 7), Vector2i(-1, 0)),
			"a wall where the wing meets the corner; none between the wing and the main block")
	Level.unregister("test_kinds")


## Work places and the town they work for (decision 517).
func _test_place_towns() -> void:
	print("
== work places and their town ==")
	var warnings: Array[String] = []
	var places := Level.places_from({"places": {"square": {"at": [8, 5], "kind": "stockpile"},
		"wood": {"at": [2, 2], "kind": "woodlot", "town": "square"}, "hunt": {"at": [3, 3], "kind": "hunting_ground", "town": "wood"},
		"pit": {"at": [4, 4], "kind": "quarry"}}}, warnings)
	_check(places["wood"]["kind"] == "woodlot" and places["wood"].get("town") == "square", "a woodlot working for the square's town")
	_check(places["hunt"]["kind"] == "hunting_ground" and not places["hunt"].has("town")
		and warnings.size() == 1 and "works for town \"wood\": no stockpile place" in warnings[0], "a town that is no stockpile: said, none (%s)" % [warnings])
	_check(places["pit"]["kind"] == "quarry" and not places["pit"].has("town"), "a quarry, working for none")


## A building carries a level link (decision 715: the temple's way down goes
## where the temple goes): its cell in the building's frame turned with its
## facing, no marker, its code on it, kept clear and cued as any link; one
## off its inside, on its door or front, or with no to_map, said and left
## out. The wilds' temple carries the stair down to the Ossuary.
func _test_building_level_link() -> void:
	print("\n== a building's level link (715) ==")
	var rows: Array[String] = []
	for y in 2 * 14 - 1:
		rows.append(".".repeat(2 * 14 - 1))
	var layout := Level.image_from_rows(rows, {Vector2i(1, 1): "start"})
	var parse_with := func(facing: Array, given: Dictionary) -> Dictionary:
		var config := {"outdoor": true, "buildings": [{"slot": "building.temple", "at": [3, 3], "facing": facing, "level_link": given}]}
		return Level.parse(layout, null, config)
	var said := func(level: Dictionary) -> Array:
		return level["warnings"].filter(func(w: String) -> bool: return "level_link" in w)
	var down := {"cell": [0, 0], "to_map": "barrow_deep", "to_spawn": "from_temple", "sealed": "draugr"}
	var level: Dictionary = parse_with.call([0, 1], down)
	var link: Dictionary = level["links"][0] if level["links"].size() == 1 else {}
	_check(link.get("tile") == Vector2i(3, 3) and link.get("to_map") == "barrow_deep" and link.get("to_spawn") == "from_temple" and link.get("sealed") == "draugr"
		and link.get("building") == level["buildings"][0]["code"] and Vector2i(3, 3) in level["terrain"]["links_at"] and level["terrain"]["ways_out"].is_empty()
		and said.call(level).is_empty(), "facing south, its back-left cell is the link, no marker, the temple's code on it (%s %s)" % [link, said.call(level)])
	var cue: Array = level["terrain"]["link_cues"].filter(func(c: Dictionary) -> bool: return c["tile"] == Vector2i(3, 3))
	_check(cue.size() == 1 and cue[0]["cue"] == "sealed", "it is cued as a sealed way (%s)" % [cue])
	# The temple is 4 x 6: its frame's (0, 0) turned with it, as a kind's doors are.
	var turned := {[0, -1]: Vector2i(6, 8), [1, 0]: Vector2i(3, 6), [-1, 0]: Vector2i(8, 3)}
	for facing: Array in turned:
		var links: Array = parse_with.call(facing, down)["links"]
		_check(links.size() == 1 and links[0]["tile"] == turned[facing], "facing %s it is at %s (%s)" % [facing, turned[facing], links])
	# Its door (front row's middle, (4, 8)) and the front before it; outside; no to_map.
	for bad: Dictionary in [{"cell": [1, 5], "to_map": "x"}, {"cell": [1, 6], "to_map": "x"}, {"cell": [9, 0], "to_map": "x"}, {"cell": [1, 1]}]:
		var refused: Dictionary = parse_with.call([0, 1], bad)
		_check(refused["links"].is_empty() and refused["terrain"]["links_at"].is_empty() and said.call(refused).size() == 1,
			"%s: said and left out (%s)" % [bad, said.call(refused)])
	var wilds := Level.load_level("wilds")
	var temple: Array = wilds["buildings"].filter(func(b: Dictionary) -> bool: return b.get("kind", "") == "temple")
	var stair: Array = wilds["links"].filter(func(l: Dictionary) -> bool: return l["to_spawn"] == "from_chapel")
	_check(temple.size() == 1 and stair.size() == 1 and stair[0]["tile"] == Vector2i(199, 199) and stair[0]["building"] == temple[0]["code"]
		and stair[0]["sealed"] == "" and stair[0]["to_map"] == "barrow" and not Vector2i(217, 193) in wilds["terrain"]["links_at"]
		and wilds["warnings"].filter(func(w: String) -> bool: return "link" in w).is_empty(),
		"the wilds' temple carries the chapel stair down in its back corner, (199, 199) (774: it faces west; 832 switched on: open, into the First Hall); the old one behind it is gone (%s)" % [stair])
	# 734 amended (2): Umbrage's temple is the chapel, the temple kind; since
	# 774 at the square's centre, its doors west down the main road, its
	# counter and the shortcut's landing inside.
	if temple.size() == 1:
		var chapel: Dictionary = temple[0]
		var floor_cells: Array = wilds["terrain"]["floor"]
		var counter: Array = wilds["entities"].filter(func(spec: Dictionary) -> bool: return bool(spec.get("props", {}).get("temple", false)))
		var landing: Vector2i = Vector2i(wilds["spawn_points"]["from_crypt"]) if wilds["spawn_points"].get("from_crypt") is Vector2i else Vector2i(-1, -1)
		var temple_said: Array = wilds["warnings"].filter(func(w: String) -> bool: return "temple" in w)
		_check(chapel["rect"] == Rect2i(190, 199, 10, 6) and chapel["size"] == "small" and chapel["place"] == "temple" and chapel["use"] == "temple"
			and chapel["doors"] == [Vector3i(189, 201, Terrain.EAST), Vector3i(189, 202, Terrain.EAST)] and chapel["front"] == Vector2i(189, 201)
			and wilds["places"].has("temple@189,201") and counter.size() == 1 and (chapel["rect"] as Rect2i).has_point(counter[0]["tile"])
			and (chapel["rect"] as Rect2i).has_point(landing) and floor_cells.has(landing) and temple_said.is_empty(),
			"Umbrage's temple is the chapel: 10 x 6 facing west, doors on (189, 201) and (189, 202), its place at the front, the counter and the chapel stair's landing, from_crypt, inside (%s, %s, %s)" % [chapel["rect"], landing, temple_said])
		# The stair's own place (npc's crypt pointer key "wilds/crypt_stair"):
		# on the stair, a cell wide, no one's, worth nothing, no found-place reward.
		var stair_place: Dictionary = wilds["places"].get("crypt_stair", {})
		_check(stair_place.get("cell") == Vector2i(199, 199) and stair_place.get("kind") == "other" and stair_place.get("radius") == 1
			and stair_place.get("worth") == 0 and stair_place.get("holder") == "nobody" and stair_place.get("name") == "the crypt stair"
			and not bool(stair_place.get("explore", true)) and (chapel["rect"] as Rect2i).has_point(Vector2i(199, 199)),
			"the crypt stair is a place of its own on the stair, inside the temple: other, a cell wide, nobody's, worth 0, no found-place reward (%s)" % [stair_place])
	# The places Umbrage's temple and the healer's turf house make go by lore's
	# names (ui-design's zone map audit: "Temple", "Healers Hut" were the kinds capitalised).
	var named := {"temple@189,201": "the temple", "healers_hut@152,232": "the healer's hut"}
	var names_now := {}
	for key: String in named:
		names_now[key] = wilds["places"].get(key, {}).get("name", "")
	_check(names_now == named and wilds["places"]["temple@189,201"].get("kind") == "temple" and wilds["places"]["healers_hut@152,232"].get("kind") == "healers_hut",
		"the temple's and the healer's hut's places go by lore's names, on their buildings' front cells (%s)" % [names_now])


## The kind lists (816): each one entry a line, sorted, so two trees adding
## kinds touch different lines; sorted also means no kind twice. A dictionary
## keeps its keys in the order written, so its keys are the source's order.
func _test_kind_lists() -> void:
	print("== The kind lists, sorted (816) ==")
	var lists := {"BUILDINGS": Level.BUILDINGS.keys(), "SOLID": Level.SOLID, "DOORLESS": Level.DOORLESS,
		"OPEN_AIR": Level.OPEN_AIR, "FADES_ON_LINE": Level.FADES_ON_LINE}
	for name: String in lists:
		var kinds: Array = lists[name]
		var out_of_order: Array = []
		for i in range(1, kinds.size()):
			if not (str(kinds[i - 1]) < str(kinds[i])):
				out_of_order.append("%s then %s" % [kinds[i - 1], kinds[i]])
		_check(out_of_order.is_empty(), "Level.%s sorted, no kind twice (%s)" % [name, out_of_order])
	# One a line, in the source: from each list's const line to its closing
	# bracket, no line holds two kinds.
	var source := FileAccess.get_file_as_string("res://sim/level.gd").split("
")
	var crowded: Array = []
	for name: String in lists:
		var inside := false
		for line: String in source:
			if line.begins_with("const %s" % name):
				inside = true
			elif not inside:
				continue
			if line.strip_edges().begins_with("#"):
				continue
			if line.split("#")[0].count("\"") > 2:
				crowded.append("%s: %s" % [name, line.strip_edges()])
			if line == "]" or line == "}":
				break
	_check(crowded.is_empty(), "each kind a line of its own in sim/level.gd (%s)" % [crowded])


## The Reed Pond (805, maps' side; economy's fishing slice 1): the wilds'
## west pond's fishing place. Enlarged (Jeff, v0.1.206: "wren doesn't fish at
## the reed pond"; the coordinator): 8 x 6 water at least, a reed margin (tall
## grass), and the place on its bank, its radius taking in all of
## it and every dry cell within World.FISH_REACH of it (companions' check:
## pond_at's covers is the place's circle).
func _test_reed_pond() -> void:
	print("
== The Reed Pond (805): all its water and banks its fishing place's ==")
	var wilds := Level.load_level("wilds")
	var place: Dictionary = wilds["places"].get("reed_pond", {})
	var terrain: Dictionary = wilds["terrain"]
	var at: Vector2i = place.get("cell", Vector2i(-1, -1))
	var radius: int = place.get("radius", 0)
	var all_water: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in terrain.get("water", []):
		all_water[cell] = true
	var pond: Dictionary[Vector2i, bool] = {}
	# The pond: the water beside the place's (dry) cell, and all joined to it.
	var frontier: Array[Vector2i] = []
	for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if all_water.has(at + step):
			frontier.append(at + step)
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		if pond.has(cell) or not all_water.has(cell):
			continue
		pond[cell] = true
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			frontier.append(cell + step)
	var covers := func(cell: Vector2i) -> bool: return (cell - at).length_squared() <= radius * radius
	var open_water: Array = pond.keys().filter(func(cell: Vector2i) -> bool: return not covers.call(cell))
	var open_bank: Array = []
	var reeds := 0
	var bank := 0
	var tall: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in terrain.get("tall_grass", []):
		tall[cell] = true
	for cell: Vector2i in terrain["floor"]:
		if maxi(absi(cell.x - at.x), absi(cell.y - at.y)) > radius + 3:
			continue
		var by := false
		var beside := false
		for each: Vector2i in pond:
			var d := maxi(absi(each.x - cell.x), absi(each.y - cell.y))
			by = by or d <= World.FISH_REACH
			beside = beside or d == 1
		if by and not covers.call(cell):
			open_bank.append(cell)
		if beside:
			bank += 1
			if tall.has(cell):
				reeds += 1
	# 8 x 6 whole: some 8-wide run in 6 rows running.
	var rows := 0
	var most := 0
	for y in range(at.y - 6, at.y + 7):
		var run := 0
		var longest := 0
		for x in range(at.x - 10, at.x + 11):
			run = run + 1 if pond.has(Vector2i(x, y)) else 0
			longest = maxi(longest, run)
		rows = rows + 1 if longest >= 8 else 0
		most = maxi(most, rows)
	_check(place.get("kind", "") == "fishing" and place.get("name", "") == "the pond" and place.get("holder", "") == Factions.NOBODY
			and pond.size() >= 48 and most >= 6 and open_water.is_empty() and open_bank.is_empty() and reeds * 2 >= bank,
		"reed_pond: fishing, nobody's, %d water cells by %s (%d rows 8 wide), radius %d; outside it: water %s, bank %s; reeds on %d of %d bank cells"
			% [pond.size(), at, most, radius, open_water, open_bank.slice(0, 4), reeds, bank])


## Umbrage's locker (722): one chest prop {"locker": true}, since 737 in
## the player's house, its back to the house's south wall, the cell before
## it open floor.
func _test_beds() -> void:
	print("
== the dwellings' beds (751, buildings' side) ==")
	var cells: Array[Vector2i] = []
	for y in 40:
		for x in 40:
			cells.append(Vector2i(x, y))
	var open_ground := {"floor": cells, "edges": {}, "heights": {}, "water": []}
	var short: Array[String] = []
	var bad: Array[String] = []
	for kind: String in Level.BEDS:
		if kind.begins_with("building."):
			continue
		for size: String in ["small", "large"]:
			for facing: Array in [[0, 1], [0, -1], [1, 0], [-1, 0]]:
				var warnings: Array[String] = []
				var built := Level.buildings_from({"buildings": [{"kind": kind, "size": size, "at": [5, 5], "facing": facing}]}, open_ground, warnings)
				var building: Dictionary = built[0]
				var beds: Array = building.get("beds", [])
				if beds.size() != int(Level.BEDS[kind][2 if size == "large" else 1]):
					short.append("%s %s %s: %d" % [kind, size, facing, beds.size()])
				var why := _beds_wrong(building, beds, {})
				if not why.is_empty():
					bad.append("%s %s %s: %s" % [kind, size, facing, why])
	_check(short.is_empty(), "every kind's beds all fit, small and large, every facing (%s)" % [short])
	_check(bad.is_empty(), "each bed inside, its head on a wall, off the door line, the floor left one with two-cell ways (%s)" % [bad])
	var ruin := Level.buildings_from({"buildings": [{"kind": "house", "at": [5, 5], "facing": [0, 1], "ruined": true}]}, open_ground, [] as Array[String])
	_check(not ruin[0].has("beds"), "a ruin has no beds")
	var wilds := Level.load_level("wilds")
	var blocked := {}
	for spec: Dictionary in wilds["entities"]:
		blocked[spec["tile"]] = true
	var listed: Array[String] = []
	var wrong: Array[String] = []
	var by_slot := {}
	for building: Dictionary in wilds["buildings"]:
		var beds: Array = building.get("beds", [])
		listed.append("%s %s %s: %d" % [building["slot"], (building["rect"] as Rect2i).position, building.get("use", ""), beds.size()])
		by_slot[building["slot"]] = int(by_slot.get(building["slot"], 0)) + (1 if not beds.is_empty() else 0)
		var why := _beds_wrong(building, beds, blocked, wilds["terrain"]["edges"]) if not beds.is_empty() and not building["slot"] in Level.ART_WALLED else ""
		if not why.is_empty():
			wrong.append("%s: %s" % [building["rect"], why])
		for bed: Dictionary in beds:
			for cell: Vector2i in bed["cells"]:
				if bool(bed.get("solid", false)) == wilds["terrain"]["floor"].has(cell):
					wrong.append("%s: bed cell %s %s" % [building["rect"], cell, "floor" if bed.get("solid", false) else "not floor"])
	var homes: Array = wilds["buildings"].filter(func(building: Dictionary) -> bool: return building.get("home", false))
	var huts: Array = wilds["buildings"].filter(func(building: Dictionary) -> bool: return building["slot"] == "building.hut")
	var forge: Array = wilds["buildings"].filter(func(building: Dictionary) -> bool: return building.get("use", "") == "forge")
	var turf: Array = wilds["buildings"].filter(func(building: Dictionary) -> bool: return building["slot"] == "building.turf_house")
	_check(homes.size() == 1 and (homes[0].get("beds", []) as Array).size() == 3 and huts.size() == 2
		and huts.all(func(hut: Dictionary) -> bool: return (hut.get("beds", []) as Array).size() == 1)
		and forge.size() == 1 and not forge[0].has("beds") and wilds["buildings"].all(func(b: Dictionary) -> bool: return b.get("use", "") != "temple" or not b.has("beds"))
		and turf.size() == 1 and (turf[0]["beds"] as Array).size() == 1 and bool(turf[0]["beds"][0]["solid"]),
		"Umbrage: three beds in the player's house, one in each 3 x 3 hut, none in the forge or the temple, the turf hut its own (%s)" % [listed])
	_check(wrong.is_empty(), "Umbrage's beds on floor, off the locker and every entity, two-cell ways kept (%s)" % [wrong])


## Why [param beds] in [param building] break its rules, "" if none: each
## inside, its two cells side by side, its head cell on a wall the way it
## points, not on a line in from a door nor beside a door's cell, no two on
## a cell nor on [param blocked]; the floor left all one, no single-width run.
func _beds_wrong(building: Dictionary, beds: Array, blocked: Dictionary, edges: Dictionary = {}) -> String:
	var inside := {}
	for cell in Level.building_cells(building):
		inside[cell] = true
	var line := {}
	for edge: Vector3i in Level.entrances(building) if building.has("kind") else Level.building_outline(building).filter(func(key: Vector3i) -> bool:
			return edges.get(key) == Terrain.Edge.DOOR):
		var sides := Terrain.edge_cells(edge)
		var cell: Vector2i = sides[0] if inside.has(sides[0]) else sides[1]
		var inward: Vector2i = cell - (sides[1] if cell == sides[0] else sides[0])
		line[cell + Vector2i(inward.y, inward.x)] = true
		line[cell - Vector2i(inward.y, inward.x)] = true
		while inside.has(cell):
			line[cell] = true
			cell += inward
	var taken := {}
	for cell: Vector2i in blocked:
		if inside.has(cell):
			taken[cell] = true
	for bed: Dictionary in beds:
		var head: Vector2i = bed["cells"][0]
		var foot: Vector2i = bed["cells"][1]
		if head - foot != bed["head"] or inside.has(head + bed["head"]) or not inside.has(head) or not inside.has(foot):
			return "a bed not lying head to wall inside (%s)" % [bed]
		if line.has(head) or line.has(foot) or taken.has(head) or taken.has(foot):
			return "a bed on the door line, another bed or an entity (%s)" % [bed]
		taken[head] = true
		taken[foot] = true
	var free: Array[Vector2i] = []
	for cell: Vector2i in inside:
		if not taken.has(cell):
			free.append(cell)
	var open := func(cell: Vector2i, way: Vector2i) -> bool: return inside.has(cell + way) and not taken.has(cell + way)
	var runs := Level.narrow_runs_by(free, open)
	if not runs.is_empty():
		return "single-width runs %s" % [runs.keys()]
	var reached := {free[0]: true}
	var queue: Array[Vector2i] = [free[0]]
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		for way: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			if open.call(at, way) and not reached.has(at + way):
				reached[at + way] = true
				queue.append(at + way)
	if reached.size() != free.size():
		return "the floor left in pieces"
	return ""


func _test_umbrage_locker() -> void:
	print("\n== Umbrage's locker (722), in the player's house (737) ==")
	var wilds := Level.load_level("wilds")
	var lockers: Array = wilds["entities"].filter(func(spec: Dictionary) -> bool: return bool((spec.get("props", {}) as Dictionary).get("locker", false)))
	var at := Vector2i(172, 193)
	_check(lockers.size() == 1 and lockers[0]["tile"] == at
		and wilds["terrain"]["edges"].get(Terrain.edge_key(at, Vector2i(0, -1))) == Terrain.Edge.WALL
		and wilds["terrain"]["floor"].has(at + Vector2i(0, 1)) and not wilds["terrain"]["edges"].has(Terrain.edge_key(at, Vector2i(0, 1)))
		and wilds["entities"].all(func(spec: Dictionary) -> bool: return spec["tile"] != at + Vector2i(0, 1)),
		"one locker, at (172, 193), its back to the house's north wall (774: its door is in the south), the cell before it clear floor (%s)" % [lockers])
	var homes: Array = wilds["buildings"].filter(func(building: Dictionary) -> bool: return building.get("home", false))
	_check(homes.size() == 1 and (homes[0]["rect"] as Rect2i) == Rect2i(170, 193, 4, 6) and Level.building_cells(homes[0]).has(at)
		and str(homes[0].get("use", "")).is_empty(),
		"one house marked the player's (737), the house at (170, 193) on the main road (774), the locker inside it (%d)" % homes.size())
	# 736: the weapon stall, solid and doorless, faces the square; its seller stands behind it.
	# 774: Rolf's on the square's north-east rim facing in, Snagfin's on its south-east.
	var stalls: Array = wilds["buildings"].filter(func(building: Dictionary) -> bool: return building["slot"] == "building.market_stall")
	var place: Dictionary = wilds["places"].get("weapon_stall", {})
	_check(stalls.size() == 2 and stalls[0]["rect"] == Rect2i(203, 197, 2, 1) and stalls[0]["facing"] == Vector2i(0, 1)
		and stalls[1]["rect"] == Rect2i(203, 207, 2, 1) and stalls[1]["facing"] == Vector2i(0, -1)
		and not wilds["terrain"]["floor"].has(Vector2i(203, 197)) and not wilds["terrain"]["floor"].has(Vector2i(204, 197))
		and wilds["terrain"]["solid"].has(Vector2i(203, 197)) and wilds["terrain"]["floor"].has(Vector2i(203, 198)) and wilds["terrain"]["floor"].has(Vector2i(204, 198)),
		"Rolf's weapon stall at (203, 197), 2 x 1 facing south into the square, solid, the square before it floor; Snagfin's at (203, 207) (%s)" % [stalls])
	_check(place.get("cell") == Vector2i(203, 196) and place.get("kind") == "stall" and place.get("radius") == 1 and place.get("worth") == 0
		and place.get("town") == "store" and wilds["terrain"]["floor"].has(Vector2i(203, 196)) and wilds["terrain"]["floor"].has(Vector2i(204, 196))
		and wilds["entities"].all(func(spec: Dictionary) -> bool: return not Rect2i(203, 196, 2, 3).has_point(spec["tile"])),
		"the place weapon_stall, a stall worth nothing, at (203, 196) behind it on floor, no marker in or about it (%s)" % [place])


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


func _test_regenerate_mark() -> void:
	print("\n== a level marked \"regenerate\" (decision 465): a link outside an anchor warns ==")
	var layout := Level.image_from_rows(_rows(1, 6, 1, 1), {Vector2i(1, 1): "start", Vector2i(6, 1): "link"})
	var config := {"links": [{"at": [6, 1], "to_map": "test_link_b", "to_spawn": "gate"}],
		"regenerate": {"generator": "maze", "every_days": 2, "anchors": [{"rect": [1, 1, 2, 1], "name": "gate"}]}}
	var level := Level.parse(layout, null, config)
	_check(level["regenerate"]["generator"] == "maze" and level["regenerate"]["every_days"] == 2 and level["regenerate"]["anchors"].size() == 1,
		"the mark is read (%s)" % [level["regenerate"]])
	var said: Array = level["warnings"].filter(func(text: String) -> bool: return text.contains("outside every anchor"))
	_check(said.size() == 1 and said[0].contains("link at (6, 1)"), "the link at (6, 1), outside the anchor, is warned of (%s)" % [level["warnings"]])
	_check(Level.parse(layout, null, {"links": config["links"]})["regenerate"].is_empty(), "a level without the mark has no \"regenerate\"")


func _test_level_links() -> void:
	print("\n== level links: the player who steps on one goes through ==")
	_main.load_map("test_link_a")
	var player := _player()
	_put(player, Vector2i(3, 1))
	_hold_free(player, Vector2(1, 0), 6)
	await get_tree().process_frame
	await get_tree().process_frame
	var arrived := _player()
	_check(_main.map_name == "test_link_b", "the map is now test_link_b (%s)" % _main.map_name)
	_check(arrived != null and arrived.tile == Vector2i(2, 2), "and Player arrives at its spawn point gate, (2, 2) (%s)" % [arrived.tile if arrived else "none"])
	_check(World.zones.has("test_link_a") and arrived != null and arrived.zone == "test_link_b",
		"in the zone test_link_b; test_link_a stays loaded")


## A level link's cell is a player's way out alone (decision 571): no other
## body steps onto it, one put there steps off, nothing is put down on it,
## and a player stepping at it while a body stands there takes the link.
func _test_links_kept_clear() -> void:
	print("
== links kept clear (571): a body on a link's cell never shuts the way ==")
	_main.load_map("test_link_a")
	var link := Vector2i(4, 1)
	_check(World.is_link_cell(link) and not World.is_link_cell(Vector2i(3, 1)), "the link's cell is known as one")
	var body := Resident.new()
	body.name = "Tam"
	_check(World.spawn(body, Vector2i(3, 1)), "(a resident beside the link)")
	_wait_for_step(body)
	_check(not World.try_move(body, Vector2i(1, 0)) and body.tile == Vector2i(3, 1), "a resident does not step onto the link's cell")
	World._relocate(body, link)
	for i in 20:
		World.step()
		if body.tile != link:
			break
	_check(body.tile != link, "one put on it steps off it (%s)" % [body.tile])
	if body.spawned:
		World.despawn(body)
	var player := _player()
	_put(player, Vector2i(2, 1))
	# Another player on it: a resident put there steps off before it is reached.
	var other := Player.new()
	other.name = "Tam"
	World.spawn(other, link)
	_hold_free(player, Vector2(1, 0), 8)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_main.map_name == "test_link_b", "a player walking at it with a body on it takes the link (%s)" % _main.map_name)
	if is_instance_valid(other):
		if other.spawned:
			World.despawn(other)
		other.free()
	_main.load_map("test_link_a")
	var uid := World.items.mint("bandaging_kit", "made")
	var landed := World.put_on_ground(uid, link)
	_check(landed != link and landed != World.NO_CELL, "nothing is put down on the link's cell (%s)" % [landed])
	if is_instance_valid(body):
		if body.spawned:
			World.despawn(body)
		body.free()


func _test_sealed_link() -> void:
	print("\n== a sealed link (decision 540): open to the marked alone ==")
	_check(Level.parse(Level.template("test_link_s")["layout"], null, Level.template_config("test_link_s"))["links"][0]["sealed"] == "draugr",
		"the link reads its mark")
	_main.load_map("test_link_s")
	var player := _player()
	var id: String = _main._peer_ids[Net.local_id]
	var record: PlayerRecord = _main._records[id]
	_check(record.marks.is_empty() and not _main.mark_player(id, "", true) and not _main.mark_player("nobody", "draugr"),
		"no marks to start; no mark with no word or no record")
	_put(player, Vector2i(3, 1))
	_hold_free(player, Vector2(1, 0), 6)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_main.map_name == "test_link_s" and _player() == player, "Player walking onto the sealed link stays (%s)" % _main.map_name)
	_check(_main.party_log.last(1) == ["The way is sealed."] and _heard.slice(-1) == ["The way is sealed."],
		"told the way is sealed, on their screen (%s %s)" % [_main.party_log.last(1), _heard.slice(-1)])
	_check(_main.admin_command("mark Player -draugr") == "Player lacks draugr already", "the console takes no mark off that is not there")
	var answer: String = _main.admin_command("mark Player draugr")
	_check(answer == "Player marked draugr; marks: draugr" and record.marks == ["draugr"], "the console marks the player (%s)" % answer)
	_check(_main.admin_command("mark Player draugr") == "Player carries draugr already", "and says so twice")
	_check(_main.admin_command("mark Player not a word") == "mark: a mark is one word of letters, digits and underscores (not a word)" or
		_main.admin_command("mark Nobody draugr") == "mark: no player Nobody online", "a bad mark or an unknown player is refused")
	_put(player, Vector2i(3, 1))
	_hold_free(player, Vector2(1, 0), 6)
	await get_tree().process_frame
	await get_tree().process_frame
	var arrived := _player()
	_check(_main.map_name == "test_link_b" and arrived != null and arrived.tile == Vector2i(2, 2), "marked, walking onto it again goes through to test_link_b's gate (%s)" % _main.map_name)
	_check(PlayerRecord.from_dict(record.to_dict().merged({"player_id": record.player_id})).marks == ["draugr"], "the mark is saved with the record")
	_main.mark_player(id, "draugr", false)
	_check(record.marks.is_empty(), "and taken off again")


## A temple counter's town from the real loaded wilds (434 amended,
## playtest's store run 3): Level.building_rect of a loaded building is its
## laid rect, and Main.temple_town finds wilds' temple's town over its cells.
func _test_temple_town() -> void:
	print("\n== a temple counter's town, from the loaded wilds (434 amended) ==")
	var houses: Array = WorldMap.build(["wilds"]).areas.get("wilds", {}).get("buildings", [])
	var temples := houses.filter(func(each: Dictionary) -> bool: return str(each.get("use", "")) == "temple")
	_check(not temples.is_empty() and Level.building_rect(temples[0]) is Rect2i and Level.building_rect(temples[0]) == temples[0]["rect"],
		"a loaded building's rect is its own (%s)" % [temples.map(func(each: Dictionary) -> Variant: return each.get("rect"))])
	if temples.is_empty():
		return
	var rect: Rect2i = temples[0]["rect"]
	_check(Main.temple_town(houses, "wilds", rect.position + rect.size / 2) == "wilds/%s" % temples[0]["town"] and not str(temples[0]["town"]).is_empty(),
		"a counter inside the temple: its town (%s)" % Main.temple_town(houses, "wilds", rect.position + rect.size / 2))
	_check(Main.temple_town(houses, "wilds", rect.position - Vector2i(3, 3)).is_empty(), "outside it: none")


## The temple's stair (714, dungeon's side (2), on buildings' 715): the
## way up from the level below comes out beside the stair the building
## carries, wherever it stands, and the stair down sealed says its own line.
func _test_temple_stair() -> void:
	print("
== the temple's stair (714): up beside it, wherever the temple stands; barred from below ==")
	var rows: Array[String] = []
	for y in 2 * 14 - 1:
		rows.append(".".repeat(2 * 14 - 1))
	var layout := Level.image_from_rows(rows, {Vector2i(1, 1): "start"})
	for at: Array in [[3, 3], [7, 5]]:
		var name := "lt_temple_%d" % at[0]
		Level.register(name, layout, null, {"outdoor": true, "spawn_points": {"from_below": [12, 12]},
			"buildings": [{"slot": "building.temple", "at": at, "facing": [0, 1], "level_link": {"cell": [0, 0], "to_map": "test_room", "to_spawn": ""}}]})
		var parsed := Level.load_level(name)
		var stair := Main.building_link_back(parsed, "test_room")
		_check(stair == Vector2i(at[0], at[1]) and Main.building_link_back(parsed, "barrow") == World.NO_CELL,
			"the stair the temple at %s carries back to the level below is found at %s; none to another level" % [at, stair])
		_main.load_map("test_room")
		_main.travel(Net.local_id, name, "from_below")
		await get_tree().process_frame
		var player := _player()
		_check(_main.map_name == name and player != null and (player.tile - stair).length_squared() == 1 and not player.tile in parsed["terrain"]["links_at"],
			"come up from below: beside the stair at %s, not at the old spawn point (%s)" % [stair, player.tile if player != null else null])
		_main.load_map("test_room")
		Level.unregister(name)
	Level.register("lt_temple_shut", layout, null, {"outdoor": true,
		"buildings": [{"slot": "building.temple", "at": [3, 3], "facing": [0, 1], "level_link": {"cell": [0, 0], "to_map": "barrow_deep", "to_spawn": "from_temple", "sealed": "draugr"}}]})
	_main.load_map("lt_temple_shut")
	var walker := _player()
	var id: String = _main._peer_ids[Net.local_id]
	_main.mark_player(id, "draugr", false)
	_put(walker, Vector2i(3, 4))
	_hold_free(walker, Vector2(0, -1), 6)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_main.map_name == "lt_temple_shut" and _main.party_log.last(1) == ["The stair down is barred from below."]
		and _heard.slice(-1) == ["The stair down is barred from below."],
		"unblessed at the stair down: it stays shut, barred from below, told on their screen (%s %s)" % [_main.party_log.last(1), _heard.slice(-1)])
	_main.load_map("test_room")
	Level.unregister("lt_temple_shut")


## The draugr's win as the record keeps it (decision 573, dungeon's side):
## the deal's charges up to the capacity, the spill said, the count on the
## player, a zone's sum, a record from before migrated.
func _test_barrow_won() -> void:
	print("\n== the barrow's charges (573, 573 amended; 714): the win's amulet uncharged and the sepulcher's relic, its charges on the altar, the capacity, the zone's sum ==")
	_main.load_map("test_link_s")
	var player := _player()
	var id: String = _main._peer_ids[Net.local_id]
	var record: PlayerRecord = _main._records[id]
	record.marks.erase("draugr")
	record.barrow = {}
	var had := World.totem_of(id)
	if had != 0:
		World.items.set_charges(had, 0)
	_main._sync_charges(record)
	_check(player.charges == 0 and player.charge_room == 0 and _main.charges_in_zone("test_link_s") == 0, "unblessed: no charges, no room, none in the zone")
	# 714, dungeon's side (2): the win gives the amulet uncharged and, from
	# the sepulcher, a relic of the generation's knight at the deal's tier;
	# the charges come when Aldous lays it on the altar (charge_from_relic).
	var kept: Variant = _main._regen.get("barrow_deep")
	_main._regen["barrow_deep"] = {"generation": 2, "at_step": 0}
	var knight: String = _main.barrow_knight()
	var relics := func() -> Array:
		return Array(World.slot_uids(player)).filter(func(each: int) -> bool: return World.relic_of(each).get("knight") == knight)
	var relics_before: int = relics.call().size()
	_check(_main.barrow_won([id], "normal") == 1 and record.barrow == {"best": "normal", "containers": []} and "draugr" in record.marks,
		"laid to rest at the normal deal: blessed, best normal, no count on the record (%s)" % [record.barrow])
	var uid := World.totem_of(id)
	var won: Array = relics.call()
	_check(uid != 0 and World.soulbound(uid) and World.totem_charges(uid) == 0 and player.slots.has(World.TOTEM) and player.charges == 0 and player.charge_room == 50,
		"the amulet is minted into their pack, bound for life, uncharged: the win gives no charges (0 of 50)")
	_check(not knight.is_empty() and won.size() == relics_before + 1 and World.relic_of(won[-1]) == {"knight": knight, "tier": 1} and World.soulbound(won[-1]),
		"from the sepulcher, the holy remains of %s at the normal deal's tier, bound to the winner, in their pack (%s)" % [knight, World.relic_of(won[-1]) if not won.is_empty() else {}])
	_check(_main.party_log.last(3) == ["The draugr yields. %s is blessed and takes up the %s, uncharged." % [record.name, Items.name_of(World.TOTEM)],
			Main.SEPULCHER_PLAQUE % knight, "%s takes the holy remains, for the altar." % record.name],
		"the win, the plaque as its own line and the taking kept in the party log in the third person (%s)" % [_main.party_log.last(3)])
	_check(_heard.slice(-3) == ["The draugr yields. You are blessed, and take up the %s, uncharged." % Items.name_of(World.TOTEM),
			Main.SEPULCHER_PLAQUE % knight, "You take the holy remains, for the altar."],
		"and on the winner's screen as said to them (133 amended (2)): \"You are blessed\", the plaque's carved words, \"You take\" (%s)" % [_heard.slice(-3)])
	var others_from := _heard.size()
	var another := Net.local_id + 1000  # A peer not this one: its you-line goes to it, never here.
	var both: Array[int] = [Net.local_id, another]
	_main.say_to_pair(another, "You test the line.", "Someone tests the line.", both)
	_check(_heard.slice(others_from) == ["Someone tests the line."] and _main.party_log.last(1) == ["Someone tests the line."],
		"say_to_pair: a line about another player reaches the rest in the third person, never their you-form (%s)" % [_heard.slice(others_from)])
	_check(_main.charge_from_relic(player, 1) == 10 and player.charges == 10 and _main.charges_in_zone("test_link_s") == 10 and _main.charges_in_zone("wilds") == 0,
		"the relic on the altar: the deal's 10 charges, 10 of 50; the zone's sum is 10, another zone's 0")
	_main.barrow_won([id], "easy")
	_check(World.totem_of(id) == uid and World.totem_charges(uid) == 10 and record.barrow["best"] == "normal"
		and _main.party_log.last(3)[0] == "The draugr yields. %s stands over him again." % record.name and World.relic_of(relics.call()[-1])["tier"] == 0
		and _heard.slice(-3)[0] == "The draugr yields. You stand over him again.",
		"won again at an easier deal: the same amulet, no charges, best kept, an easy relic (%s %s)" % [_main.party_log.last(3), _heard.slice(-3)])
	_check(_main.charge_from_relic(player, 0) == 5 and World.totem_charges(uid) == 15, "its relic adds its 5")
	World.items.set_charges(uid, 45)
	_check(_main.charge_from_relic(player, 0) == 5 and World.totem_charges(uid) == 50, "at the room's edge what fits is taken")
	_check(_main.charge_from_relic(player, 0) == 0 and World.totem_charges(uid) == 50 and _main.party_log.last(1) == ["The relic's gift spills: 5 more than %s can hold." % record.name],
		"full: the gift spills and is said (%s)" % [_main.party_log.last(1)])
	_main.barrow_won([id], "hard")
	_check(_main.charge_from_relic(player, 2) == 15 and World.totem_charges(uid) == 65 and record.barrow["best"] == "hard" and player.charge_room == 75,
		"the hard deal raises best and the room to 75; its relic's 15: 65 of 75")
	var saved := PlayerRecord.from_dict(JSON.parse_string(JSON.stringify(record.to_dict())).merged({"player_id": id}))
	_check(saved.barrow == record.barrow, "best and containers are kept through a save and a load (%s)" % [saved.barrow])
	# A record from before 573 amended: its count moves onto the totem on join (items' Main.migrate_totem).
	record.barrow["tokens"] = 4
	_check(_main.migrate_totem(record) == uid and World.totem_charges(uid) == 69 and not record.barrow.has("tokens"),
		"a count from before moves onto the totem on join (%d)" % World.totem_charges(uid))
	_check(_main.barrow_won(["nobody"], "easy") == 0, "no record: nobody blessed")
	# 714 amended (3): beaten unpaid, the knight's remains all the same: no tier, nothing else, the plaque said.
	var marks_were: Array = record.marks.duplicate()
	var charges_were := World.totem_charges(uid)
	var best_was: Dictionary = record.barrow.duplicate(true)
	var unpaid_of := func() -> int:
		return relics.call().filter(func(each: int) -> bool: return int(World.relic_of(each).get("tier", 0)) == Main.RELIC_UNPAID).size()
	var unpaid_before: int = unpaid_of.call()
	_check(_main.remains_unpaid([id, "nobody"]) == 1 and unpaid_of.call() == unpaid_before + 1 and World.totem_charges(uid) == charges_were
		and record.marks == marks_were and record.barrow == best_was
		and _main.party_log.last(2) == [Main.SEPULCHER_PLAQUE % knight, "%s takes the holy remains, for the altar." % record.name]
		and _heard.slice(-2) == [Main.SEPULCHER_PLAQUE % knight, "You take the holy remains, for the altar."],
		"beaten unpaid: the holy remains of %s at no tier, the plaque and the taking said as a winner's are; no charge, no mark, best unchanged; nobody without a record (%s %s)" % [knight, _main.party_log.last(2), _heard.slice(-2)])
	# 714, dungeon's side (1): a relic laid on the altar charges the amulet
	# with its tier's deal, up to the room; the spill said.
	_check(_main.charge_from_relic(player, 0) == 5 and World.totem_charges(uid) == 74 and player.charges == 74,
		"a relic of the least deal adds its 5: 74 of 75, the player told")
	_check(_main.charge_from_relic(player, 1) == 1 and World.totem_charges(uid) == 75
		and _main.party_log.last(1) == ["The relic's gift spills: 9 more than %s can hold." % record.name],
		"a normal deal's 10 at the room's edge: 1 taken, the 9 spilled and said (%s)" % [_main.party_log.last(1)])
	_check(_main.charge_from_relic(player, 1) == 0 and _main.charge_from_relic(player, 7) == 0 and _main.charge_from_relic(player, -1) == 0,
		"full, nothing taken; no such tier, nothing")
	# 672 amended, dungeon's side: quests reset, the barrow as if never come.
	_main._draft_told["%s@lt_niche" % id] = 1
	var cleared: Array[String] = _main.reset_barrow(id)
	_check(cleared == ["the draugr's blessing", "the deal won", "the totem's charges", "the draft felt"]
		and not "draugr" in record.marks and record.barrow.is_empty() and World.totem_charges(uid) == 0
		and not _main._draft_told.has("%s@lt_niche" % id) and player.charges == 0 and player.charge_room == 0,
		"reset_barrow: the blessing off, the deal won gone, the totem emptied, the draft said again, the player told (%s)" % [cleared])
	_check(_main.reset_barrow(id).is_empty() and _main.reset_barrow("nobody").is_empty(), "nothing more to clear the second time; no record, nothing")
	# 714 (1): the amulet taken away (items' reset_totem), a relic mints one,
	# uncharged while they are unblessed (no room); blessed again, it fills.
	World.reset_totem(id)
	_check(World.totem_of(id) == 0 and _main.charge_from_relic(player, 2) == 0 and World.totem_of(id) != 0
		and World.totem_charges(World.totem_of(id)) == 0, "no amulet: the relic mints one, empty, as there is no room unblessed")
	record.barrow = {"best": "easy", "containers": []}
	_check(_main.charge_from_relic(player, 2) == 15 and _main.charge_from_relic(player, 2) == 10 and World.totem_charges(World.totem_of(id)) == 25,
		"blessed at the easy deal (room 25): a hard relic's 15, then 10 of the next, full at 25 (%d)" % World.totem_charges(World.totem_of(id)))
	# 870, riding it: a blessed hand at zero is told the true way to more,
	# Aldous's for a holy knight's remains (714), not the draugr's.
	_main.mark_player(id, Main.BLESSED)  # reset_barrow above took the blessing off; the reset below takes it again.
	World.items.set_charges(World.totem_of(id), 0)
	_main._sync_charges(record)
	World.lay_downed(player, 300)
	_heard.clear()
	_check(not _main._start_channel(player, player) and _heard.slice(-1) == [Main.SPENT_LINE_ALTAR]
		and Main.SPENT_LINE_ALTAR == "Your amulet is spent. The knight in the crypt's First Hall blesses it again when you lay a holy knight's remains on his altar.",
		"at zero charges: no return, and the spent amulet's line on their screen, the knight's altar its way back since 896's switch-on (%s)" % [_heard.slice(-1)])
	World.raise_downed(player, player.max_hp)
	_main.reset_barrow(id)
	# 714 (1): the generation's knight, lore's fourteen, drawn by its seed.
	var knights: Array = Regen.config_of("barrow_deep").get("knights", [])
	_main._regen.erase("barrow_deep")
	_check(knights.size() == 14 and _main.barrow_knight() == "", "before barrow_deep's first generation, no knight; lore's fourteen listed")
	var named: Array[String] = []
	for generation in range(1, 9):
		_main._regen["barrow_deep"] = {"generation": generation, "at_step": 0}
		named.append(_main.barrow_knight())
	_main._regen["barrow_deep"] = {"generation": 3, "at_step": 0}
	_check(named.all(func(knight: String) -> bool: return knight in knights) and _main.barrow_knight() == named[2]
		and named.any(func(knight: String) -> bool: return knight != named[0]),
		"each generation names one of them, the same each time asked, not always the same (%s)" % [named])
	if kept == null:
		_main._regen.erase("barrow_deep")
	else:
		_main._regen["barrow_deep"] = kept


## The draugr's hall door held shut (573 amended, dungeon's side): the door
## edges on the lair anchor's rim lock behind the first player in (a key
## nobody holds, stone), no walk or E opens them, and let go they open.
func _test_hall_door() -> void:
	print("\n== the draugr's hall door (573 amended): held shut, no way through, let go ==")
	_register_hall("lt_hall")
	_main.load_map("lt_hall")
	var player := _player()
	var key := Terrain.edge_key(Vector2i(5, 4), Vector2i(0, -1))
	var door := World.door_on(key)
	_check(door != null and not door.open and door.lock.is_empty() and _main._hall_doors("lt_hall").size() == 1 and _main._hall_doors("lt_hall")[0] == door,
		"the hall's one door, on its lair anchor's north wall, is found (%s)" % [door])
	_put(player, Vector2i(5, 3))
	var heard: Array[String] = []
	var hear := func(kind: String, data: Dictionary) -> void:
		if kind == "party":
			heard.append(str(data.get("text", "")))
	Net.message_received.connect(hear)
	_main._told_dead.clear()
	_main._hold_hall_door("lt_hall", true)
	_check(door != null and not door.open and door.lock == "draugr_hall" and door.body_material == GridEntity.BodyMaterial.STONE
		and _main.party_log.last(1) == ["The hall's door shuts behind you."] and _heard.slice(-1) == ["The hall's door shuts behind you."],
		"held: shut, locked with a key nobody holds, stone, and said to those in the zone (%s %s)" % [_main.party_log.last(1), _heard.slice(-1)])
	_hold_free(player, Vector2(0, 1), 8)
	_check(player.tile == Vector2i(5, 3) and player.free_pos.y < 3.6, "no walk goes through it: stopped at its face (%s)" % player.free_pos)
	_check(not heard.has(_main.DEAD_LINE), "a challenge's held door says nothing of the dead to a walk into it (%s)" % [heard])
	_check(not World.try_toggle_door(player, key) and not door.open, "and E rattles it")
	_main._hold_hall_door("lt_hall", false)
	_check(door.lock.is_empty() and not door.open and _main.party_log.last(1) == ["The hall's door opens."] and _heard.slice(-1) == ["The hall's door opens."],
		"let go: the lock lifted, still shut till opened, and said to them (%s)" % [_heard.slice(-1)])
	await get_tree().process_frame
	_check(World.try_toggle_door(player, key) and door.open, "E opens it now")
	# 608 amended (3): the warning ahead of his Hall, once a visit, while he sits waiting.
	var draugr := _main._spawn({"script": "res://sim/draugr.gd", "shape": "capsule", "name": "LtHallDraugr",
		"tile": Vector2i(5, 7), "props": Level.MONSTER_TYPES["draugr"].duplicate()}) as Draugr
	draugr.acts = false
	heard.clear()
	_main._told_hall.clear()
	_put(player, Vector2i(5, 2))
	_check(heard.is_empty(), "a step short of the Hall's door: nothing said (%s)" % [heard])
	_put(player, Vector2i(5, 3))
	_check(heard == [_main.HALL_AHEAD_LINE], "at the open Hall door, the draugr seated within: told what waits (%s)" % [heard])
	_put(player, Vector2i(5, 2))
	_put(player, Vector2i(5, 3))
	_check(heard.count(_main.HALL_AHEAD_LINE) == 1, "once a visit: back at the door, not again (%s)" % [heard])
	_main._told_hall[player.owner_peer] = "lt_elsewhere"
	_put(player, Vector2i(5, 2))
	_put(player, Vector2i(5, 3))
	_check(heard.count(_main.HALL_AHEAD_LINE) == 2, "a visit after one elsewhere: told again (%s)" % [heard])
	for state: Draugr.State in [Draugr.State.PACT, Draugr.State.AT_REST]:
		draugr.state = state
		_main._told_hall.clear()
		_put(player, Vector2i(5, 2))
		_put(player, Vector2i(5, 3))
	_check(heard.count(_main.HALL_AHEAD_LINE) == 2, "in a pact or at rest he asks nothing: nothing said (%s)" % [heard])
	World.despawn(draugr)
	_main._told_hall.clear()
	# The dead's seal (666): held while they stand, entry only, under a challenge's lock.
	_main._seal_hall("lt_hall", true)
	_check(not door.open and door.lock == _main.DEAD_LOCK and door.body_material == GridEntity.BodyMaterial.STONE and not World.try_toggle_door(player, key),
		"the Ossuary's dead standing: the hall's door sealed with a key nobody holds, E rattles it (%s)" % door.lock)
	heard.clear()
	_hold_free(player, Vector2(0, 1), 8)
	_check(player.tile == Vector2i(5, 3) and player.free_pos.y < 3.6, "and stops a walk at its face (%s)" % player.free_pos)
	_check(heard.count(_main.DEAD_LINE) == 1, "walking into it tells them \"%s\" once, not every step (%s)" % [_main.DEAD_LINE, heard])
	_main._told_dead[player.owner_peer] -= roundi(_main.DEAD_TOLD_S * World.TICK_RATE)
	_hold_free(player, Vector2(0, 1), 2)
	_check(heard.count(_main.DEAD_LINE) == 2, "and again once %.0f s have passed while they keep at it (%s)" % [_main.DEAD_TOLD_S, heard])
	Net.message_received.disconnect(hear)
	_main._told_dead.clear()
	_main._seal_hall("lt_hall", false)
	_check(door.lock.is_empty(), "every one of them down: the seal lifted")
	await get_tree().process_frame
	World.try_toggle_door(player, key)
	_hold_free(player, Vector2(0, 1), 8)
	_check(door.open and player.tile.y >= 5, "opened, it is walked through into the hall (%s)" % [player.tile])
	_put(player, Vector2i(5, 6))
	_main._seal_hall("lt_hall", true)
	_check(door.lock.is_empty(), "risen while a living player stands in the hall: no seal, nobody shut in by the dead")
	_put(player, Vector2i(5, 3))
	for i in _main.HALL_SEAL_EVERY:
		World.step()
	_check(door.lock == _main.DEAD_LOCK, "the hall empty, the waiting seal takes hold within a second")
	_main._hold_hall_door("lt_hall", true)
	_check(door.lock == "draugr_hall", "a challenge's lock goes over the seal")
	_main._hold_hall_door("lt_hall", false)
	_check(door.lock == _main.DEAD_LOCK, "and when it lets go, the dead's seal holds again by its own rule")
	_main._hall_seals.erase("lt_hall")
	World.hold_door(door, false, _main.DEAD_LOCK)
	_main._hold_hall_door("nowhere", true)
	_check(_main._hall_doors("test_room").is_empty(), "a level with no lair anchor has no hall door; an unknown zone is let be")
	# A retired level (666): its saved players moved to its heir's cell, its saved state dropped.
	var kept_records: Dictionary = _main._records.duplicate()
	var gone := PlayerRecord.new()
	gone.player_id = "lt-retired"
	gone.zone = "barrow_lair"
	gone.tile = Vector2i(49, 60)
	gone.companion = {"tile": Vector2i(48, 60)}
	var stays := PlayerRecord.new()
	stays.player_id = "lt-stays"
	stays.zone = "barrow"
	stays.tile = Vector2i(40, 2)
	_main._records[gone.player_id] = gone
	_main._records[stays.player_id] = stays
	_main._regen["barrow_lair"] = {"generation": 4}
	_main._move_off_retired({"zones": {"barrow_lair": {"entities": []}}})
	_check(gone.zone == "barrow_deep" and gone.tile == Vector2i(49, 2) and gone.companion.get("tile") == null and stays.zone == "barrow" and stays.tile == Vector2i(40, 2)
		and not _main._regen.has("barrow_lair"), "one saved in the dark below wakes at the Ossuary's stair foot, its generation dropped; others are let be (%s %s)" % [gone.zone, gone.tile])
	_main._records = kept_records
	_main.load_map("test_room")
	Level.unregister("lt_hall")


## Umbrage re-laid round its chapel (Relaid, 774): a save on the old layout
## carried over once, nothing dropped: the chapel's place keys renamed
## (holdings, its stockpile, the item book, a player's map), Snagfin's chest
## keyed and stood at its new marker with its things, a pile and a player on
## a cell that is no floor now moved onto the nearest floor; the next boot
## moves nothing; a new world is only marked done.
func _test_relaid() -> void:
	print("
== Umbrage re-laid in place: its saved state carried over once (774) ==")
	var plan: Dictionary = Relaid.RELAID["wilds"]
	var wilds := Level.load_level("wilds")
	var floor := {}
	for cell: Vector2i in wilds["terrain"]["floor"]:
		floor[cell] = true
	var old_temple := "wilds/temple@217,201"
	var new_temple: String = plan["places"][old_temple]
	_check(wilds["places"].has(new_temple.trim_prefix("wilds/")), "the chapel's place is where the mover renames it to (%s)" % new_temple)
	var gone: Array = []  # Snagfin's three, moved by his stall, then gone from town (734 amended (7)).
	for removal: Dictionary in Relaid.REMOVED:
		if removal["level"] == "wilds":
			gone.append_array((removal["removed"] as Dictionary).keys())
	for key: String in plan["markers"]:
		var to: Array = plan["markers"][key]
		var found := (wilds["entities"] as Array).filter(func(spec: Dictionary) -> bool: return spec["tile"] == Vector2i(to[0], to[1]))
		var removed := "%d,%d" % [to[0], to[1]] in gone
		_check(found.size() == (0 if removed else 1), "the marker from %s %s %s in the level (%d)" % [key, "is gone from" if removed else "stands at", to, found.size()])
	# No level entity stands on an old marker cell now (each moved is in the map, so none is laid twice).
	for key: String in plan["markers"]:
		var old := Vector2i(int(key.get_slice(",", 0)), int(key.get_slice(",", 1)))
		_check((wilds["entities"] as Array).all(func(spec: Dictionary) -> bool: return spec["tile"] != old), "no marker left at the old %s" % key)
	var well: Vector2i = Vector2i(194, 190)
	_check(not floor.has(well), "the well's water is no floor")
	var record := PlayerRecord.new()
	record.player_id = "lt-relaid"
	record.zone = "wilds"
	record.tile = well
	record.known_places.assign(["wilds/store", old_temple])
	# A saved world from before the re-lay, as the game writes it, read back as the box's boot reads it.
	var chest := {"script": "res://sim/chest.gd", "shape": "chest", "name": "chest", "tile": [221, 225], "hp": 1, "stamina": 0,
		"facing": [0, 1], "props": {}, "spawn": 4, "spawn_key": "221,225", "slots": ["coin"], "items": [7]}
	var path: String = preload("res://tests/test_ports.gd").scratch("relaid_world.json")
	_check(Snapshot.write(path, {"version": Snapshot.VERSION, "players": [record.to_dict()], "remade": {"hills": 756},
		"holdings": {old_temple: {"holder": "nobody", "strength": 0, "age": 3}},
		"stockpile": {"stockpile:" + old_temple: {"x": 1}},
		"items": {"7": {"at": "stockpile:" + old_temple}, "8": {"at": "wilds@194,190"}},
		"zones": {"wilds": {"tick": 9, "entities": [chest], "respawns": [{"spawn": 3, "spawn_key": "209,199", "ticks_left": 5}],
			"ground": [{"cell": [well.x, well.y], "ids": ["coin"], "items": [8], "gold": 0}], "records": []}}}), "(the old world written)")
	var snapshot := Snapshot.load(path)
	var done: Dictionary = snapshot.get("remade", {})
	_removals_done(done)  # 807's removals have a test of their own (_test_removed).
	var level_of := func(_level: String) -> Dictionary: return wilds
	# An overlay copy laid out the old way (edited before the re-lay) shadows the new one: nothing moves, nothing marked.
	var shadowed := Relaid.move(snapshot, done, func(_level: String) -> Dictionary: return {"places": {}, "entities": [], "terrain": {"floor": []}})
	_check(shadowed.size() == 1 and "not re-laid" in shadowed[0] and not done.has(Relaid.done_key("wilds")) and snapshot["holdings"].has(old_temple)
		and snapshot["zones"]["wilds"]["entities"][0]["spec"]["spawn_key"] == "221,225", "an old-layout level loading here: nothing moved, not marked, it waits (%s)" % [shadowed])
	var lines := Relaid.move(snapshot, done, level_of)
	var moved: PlayerRecord = snapshot["players"][0]
	var pile: Dictionary = snapshot["zones"]["wilds"]["ground"][0]
	chest = snapshot["zones"]["wilds"]["entities"][0]
	_check(lines.size() == 1 and done.get(Relaid.done_key("wilds")) == 774 and done.get("hills") == 756 and not done.has("wilds"),
		"one count-only line, the level marked done under its own key, a remake's mark kept (%s, %s)" % [lines, done])
	_check(lines[0].ends_with(", 0 left where they were (no floor near)") and not "lt-relaid" in lines[0], "nothing left off the floor; no id in the line")
	_check(snapshot["zones"]["wilds"]["entities"].size() == 1 and snapshot["zones"]["wilds"]["ground"].size() == 1 and snapshot["players"].size() == 1,
		"nothing dropped: the chest, the pile and the player all there")
	_check(snapshot["holdings"].has(new_temple) and not snapshot["holdings"].has(old_temple) and snapshot["stockpile"].has("stockpile:" + new_temple)
		and snapshot["items"]["7"]["at"] == "stockpile:" + new_temple and new_temple in moved.known_places and not old_temple in moved.known_places,
		"the chapel's place keys renamed: holdings, its stockpile, the item book, the player's map")
	_check(chest["spec"]["spawn_key"] == "205,208" and chest["spec"]["tile"] == Vector2i(205, 208) and chest["slots"] == ["coin"]
		and snapshot["zones"]["wilds"]["respawns"][0]["spawn_key"] == "190,196", "Snagfin's chest keyed and stood at its new marker, its things kept; a dead timer follows its marker")
	_check(floor.has(moved.tile) and floor.has(pile["cell"]) and pile["ids"] == ["coin"]
		and snapshot["items"]["8"]["at"] == "wilds@%d,%d" % [pile["cell"].x, pile["cell"].y],
		"a player and a pile in the new well's water moved onto floor beside it, the pile's things following it (%s, %s)" % [moved.tile, pile["cell"]])
	_check(Relaid.move(snapshot, done, level_of).is_empty(), "the next boot moves nothing")
	var far := wilds.duplicate()
	far["terrain"] = {"floor": [Vector2i(0, 0)]}
	var lost := {"ok": true, "players": [], "zones": {"wilds": {"entities": [], "respawns": [], "records": [],
		"ground": [{"cell": Vector2i(100, 100), "ids": ["coin"], "items": [], "gold": 0}]}}}
	var far_done := {}
	_removals_done(far_done)
	var far_lines := Relaid.move(lost, far_done, func(_level: String) -> Dictionary: return far)
	_check(far_lines.size() == 1 and far_lines[0].ends_with(", 1 left where they were (no floor near)") and lost["zones"]["wilds"]["ground"][0]["cell"] == Vector2i(100, 100),
		"a pile with no floor near is kept where it was and counted, never dropped (%s)" % [far_lines])
	var fresh := {}
	_check(Relaid.move({"ok": false, "zones": {}, "players": []}, fresh, level_of).is_empty() and fresh.get(Relaid.done_key("wilds")) == 774, "a new world has nothing to move: only marked done")
	_test_town_places(wilds)
	_test_explorables()
	_test_forest_camps()
	_test_boar_lair()
	_test_wolf_cave()
	_test_grey_den()
	_test_bear_den()
	_test_removed(wilds)
	var hills := Level.load_level("hills")
	_test_caches(wilds, hills)
	_test_carved(hills)
	_test_tavern_zone(wilds)
	_test_smithy_inside()
	_test_spots(wilds)  # 853.
	_test_temple_furnished(wilds)
	_test_removed_to_temple(wilds)
	_test_storey_stairs()
	_test_shelled(wilds)
	_test_perches(hills)


## The lands' hidden caches (807 amended): the farmstead's under a
## floorboard, the old camp's pack (off the removed chest's cell, so 807's
## removal never waits on it), and the cairn's in the hills on its side away
## from the road; each a chest with its own table and art, and no other
## cache out in the lands (the town's counters and stalls are buildings').
func _test_caches(wilds: Dictionary, hills: Dictionary) -> void:
	print("== The lands' caches (807 amended) ==")
	var want := {
		"wilds": {Vector2i(119, 139): ["farmstead_cache", "prop.cache_floorboard"], Vector2i(198, 83): ["camp_pack", "prop.cache_pack"]},
		"hills": {Vector2i(114, 80): ["cairn_cache", "prop.cache_stones"]}}
	for level: String in want:
		var loaded: Dictionary = wilds if level == "wilds" else hills
		var chests := {}
		for spec: Dictionary in loaded.get("entities", []):
			if spec.get("script") == Level.CHEST and (spec.get("props", {}) as Dictionary).has("cache"):
				chests[spec["tile"]] = spec
		_check(chests.keys().size() == want[level].size() and chests.keys().all(func(at: Vector2i) -> bool: return want[level].has(at)),
			"%s: its caches are these alone (%s)" % [level, chests.keys()])
		for at: Vector2i in want[level]:
			var spec: Dictionary = chests.get(at, {})
			var props: Dictionary = spec.get("props", {})
			_check(str(props.get("cache", "")) == want[level][at][0] and Items.has_loot(want[level][at][0]) and str(spec.get("art", "")) == want[level][at][1]
				and not str(props.get("cache_place", "")).is_empty(),
				"%s %s: the %s cache, drawn as %s, a place to name (%s)" % [level, at, want[level][at][0], want[level][at][1], spec])
	for plan: Dictionary in Relaid.REMOVED:
		for key: String in plan["removed"]:
			var cell := Vector2i(int(key.get_slice(",", 0)), int(key.get_slice(",", 1)))
			_check(not (want.get(plan["level"], {}) as Dictionary).has(cell), "%s %s: no cache on a removed chest's cell" % [plan["level"], key])
	var cairn := Rect2i()
	for building: Dictionary in hills.get("buildings", []):
		if building.get("slot") == "building.cairn":
			cairn = building["rect"]
	_check(cairn.grow(1).has_point(Vector2i(114, 80)) and not cairn.has_point(Vector2i(114, 80)),
		"the cairn's cache stands against the cairn (%s)" % [cairn])



## The boar's lair (780 amended (12), forest phase D): a thorn-roofed den
## (indoors, lit plainly, a skylight by the door) with one way out, a
## two-cell way up to its link to the forest; the den at its "lair" place;
## an open middle of 12 x 12 with nothing laid in it; three boars 3 to 4
## cells from the den; no chest, no entity. In the forest its mouth is
## sealed till enemy-ai's phase 2, the thicket behind it no floor, a
## trampled dirt pad before it with bones on it and the clawed tree, solid,
## at its side, "from_boar_lair" on the pad.
func _test_boar_lair() -> void:
	print("== The boar's lair (780 amended (12)) ==")
	var lair := Level.load_level("boar_lair")
	var config := Level.template_config("boar_lair")
	var floor := {}
	for cell: Vector2i in lair["terrain"]["floor"]:
		floor[cell] = true
	var links: Array = lair["links"]
	_check(lair["warnings"].is_empty() and not lair["terrain"]["outdoor"] and lair["terrain"]["ambience"] == "thicket"
		and lair["terrain"]["walls"] == "thicket" and float(lair["terrain"]["ambient"]) >= 0.25,
		"read with no warning, indoors (thorn-roofed), lit plainly, thicket walls and sound (%s)" % [lair["warnings"]])
	_check(links.size() == 1 and links[0]["to_map"] == "forest" and links[0]["to_spawn"] == "from_boar_lair",
		"one way out, up to the forest (%s)" % [links])
	var way: Vector2i = links[0]["tile"]
	_check(floor.has(way + Vector2i(1, 0)) or floor.has(way + Vector2i(-1, 0)), "the way out two cells wide at its link")
	var places := Level.places_from(config, [] as Array[String])
	var den := Vector2i(-1, -1)
	if places.has("boar_lair"):
		den = places["boar_lair"]["den"]
	_check(places.size() == 1 and places.has("boar_lair") and places["boar_lair"]["kind"] == "lair"
		and places["boar_lair"]["holder"] == "nobody" and places["boar_lair"]["cell"] == den and floor.has(den)
		and places["boar_lair"].get("explore") == true and places["boar_lair"]["name"] == "the boar's lair",
		"its one place, the boar's lair, held by nobody, at its den, explored (%s)" % [places])
	var boars: Array[Vector2i] = []
	var kings: Array[Vector2i] = []
	var caches: Array = []
	var others: Array = []
	for entity: Dictionary in lair["entities"]:
		if str(entity.get("kind", "")) == "boar":
			boars.append(entity["tile"])
		elif str(entity.get("kind", "")) == "boar_king":
			kings.append(entity["tile"])
		elif str(entity.get("props", {}).get("cache", "")) == "boar_lair_cache":
			caches.append(entity)
		else:
			others.append(entity)
	# The boar king's package, maps' piece: his marker on his bed (Apex's, never
	# spawned by Main), no den keeper (no loose boar at the mouth beyond his
	# sounder, the coordinator, before v0.1.209), the wallow's find.
	_check(kings == [den] and Apex.holds_marker({"kind": "boar_king", "spawn": {}}, "boar_lair"),
		"the boar king's marker on his bed, the den, Apex's (%s)" % [kings])
	_check(boars.is_empty(), "no den keeper, no boar but his sounder (%s)" % [boars])
	var wallows: Array = lair["terrain"].get("decor", []).filter(func(entry: Dictionary) -> bool: return entry["kind"] == "wallow")
	_check(caches.size() == 1 and caches[0].get("art") == "prop.cache_pack" and floor.has(caches[0]["tile"])
		and wallows.any(func(entry: Dictionary) -> bool: return Vector2(entry["cell"] - caches[0]["tile"]).length() <= 1.5),
		"the find (boar_lair_cache, a pack) at a wallow's edge (%s)" % [caches])
	_check(others.is_empty(), "no chest, no other entity in the lair (%s)" % [others])
	var open := Rect2i(8, 8, 12, 12)
	var open_floor := true
	for y in range(open.position.y, open.end.y):
		for x in range(open.position.x, open.end.x):
			open_floor = open_floor and floor.has(Vector2i(x, y))
	var in_open: Array = lair["terrain"].get("decor", []).filter(func(entry: Dictionary) -> bool: return open.has_point(entry["cell"]))
	_check(open_floor and in_open.is_empty(), "an open middle of 12 x 12, floor, nothing laid in it (%s)" % [in_open])
	var by_door: bool = lair["terrain"]["skylights"].any(func(light: Dictionary) -> bool: return Vector2(light["at"] - way).length() <= 6.0)
	_check(by_door, "a skylight by the door, so the first meeting is fair")
	var forest := Level.load_level("forest")
	var mouth: Dictionary = {}
	for link: Dictionary in forest["links"]:
		if link["to_map"] == "boar_lair":
			mouth = link
	var forest_floor := {}
	for cell: Vector2i in forest["terrain"]["floor"]:
		forest_floor[cell] = true
	if Level.SHELVED.has("boar_lair"):
		_check_shelved("boar_lair", "forest", Vector2i(122, 175))
		return
	var spawn: Array = Level.template_config("forest")["spawn_points"].get("from_boar_lair", [])
	var at: Vector2i = mouth.get("tile", Vector2i(-1, -1))
	_check(not mouth.is_empty() and not mouth["closed"] and mouth["to_spawn"] == "from_forest" and spawn.size() == 2
		and forest_floor.has(Vector2i(spawn[0], spawn[1])) and Vector2(Vector2i(spawn[0], spawn[1]) - at).length() == 2.0,
		"the forest's mouth open, its spawn two cells out on the pad (%s, %s)" % [mouth, spawn])
	var behind := at - Vector2i(1, 0)
	_check(not forest_floor.has(behind) and not forest_floor.has(at + Vector2i(0, 1)) and not forest_floor.has(at + Vector2i(0, -1)),
		"the thicket behind and beside the mouth is no floor")
	var clawed: Array = forest["buildings"].filter(func(building: Dictionary) -> bool: return building.get("slot") == "tree.clawed")
	var bones: Array = forest["terrain"].get("decor", []).filter(func(entry: Dictionary) -> bool:
		return entry["kind"] == "scattered_bones" and Vector2(entry["cell"] - at).length() <= 3.0)
	_check(clawed.size() == 1 and Vector2(clawed[0]["cell"] - at).length() <= 3.0
		and not forest_floor.has(clawed[0]["cell"]) and bones.size() >= 2,
		"a clawed tree (solid) and bones at the mouth, a sign of what lives there (%s, %d bones)" % [clawed, bones.size()])
	_check_lair_sight(at, Vector2i(1, 0), forest_floor)


## A level held back (820): not among Level.names() nor playable, players
## saved there bound for its land at a floor cell by its old mouth; in its
## land no link to it, no spawn from it, no bones or clawed tree within 4
## cells of where its mouth was. The level itself still reads clean.
func _check_shelved(level_name: String, land: String, mouth_at: Vector2i) -> void:
	var level := Level.load_level(land)
	var config := Level.template_config(land)
	var floor := {}
	for cell: Vector2i in level["terrain"]["floor"]:
		floor[cell] = true
	var heir: Array = Level.SHELVED.get(level_name, [])
	var links: Array = level["links"].filter(func(link: Dictionary) -> bool: return link["to_map"] == level_name)
	var signs: Array = level["terrain"].get("decor", []).filter(func(entry: Dictionary) -> bool:
		return str(entry["kind"]).contains("bones") and Vector2(entry["cell"] - mouth_at).length() <= 4.0)
	var clawed: Array = level["buildings"].filter(func(building: Dictionary) -> bool:
		return building.get("slot") == "tree.clawed" and Vector2(building["cell"] - mouth_at).length() <= 4.0)
	_check(level_name not in Level.names() and not Level.playable(level_name) and Level.exists(level_name)
		and heir.size() == 2 and heir[0] == land and floor.has(heir[1]),
		"%s held back (820): not opened, a player saved there put back in %s at %s" % [level_name, land, heir])
	_check(links.is_empty() and not config["spawn_points"].has("from_" + level_name) and signs.is_empty() and clawed.is_empty(),
		"%s: no mouth for %s, no spawn, no bones or clawed tree where it was (%s)" % [land, level_name, links])


## A lair's sightline (780 amended (12), the coordinator, terrain's still):
## out from its mouth along "open" to 8 cells, 3 across in the first two rows
## past the pad, 5 after, no trunk (every cell floor) and no tree from
## trees.json standing in it, grown or young.
func _check_lair_sight(at: Vector2i, open: Vector2i, forest_floor: Dictionary) -> void:
	var side := Vector2i(absi(open.y), absi(open.x))
	var sight_blocked: Array = []
	for out in range(3, 9):
		var half := 2 if out >= 5 else 1
		for across in range(-half, half + 1):
			var cell := at + open * out + side * across
			if not forest_floor.has(cell):
				sight_blocked.append(cell)
	var grown: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://levels/forest/trees.json"))
	var middle := Vector2(at) + Vector2(0.5, 0.5)
	for tree: Dictionary in (grown as Dictionary).get("trees", []):
		var off := Vector2(float(tree["at"][0]), float(tree["at"][1])) - middle
		var along := off.dot(Vector2(open))
		if along >= 2.5 and along < 8.5 and absf(off.dot(Vector2(side))) < 2.5:
			sight_blocked.append(tree["at"])
	_check(sight_blocked.is_empty(), "a clear sightline to the mouth across the pad, no tree in it (%s)" % [sight_blocked])


## The wolves' cave (forest phase E): a pack's den in rock, its own lair
## place ("explore": a first visit's float; enemy-ai's lair rule makes
## clearing it a deed); a skylit mouth chamber with two watchers, a short
## two-wide passage, a den with a pillar to circle round (no floor), two
## wolves by the den; dim but never black (ambient 0.1 or more, a shaft
## in the den); the traveller's pack a cache (599) at the den's back; the
## wolves back after a game day or more. In the forest its mouth is open,
## "from_wolf_cave" two cells out, the rock behind it no floor.
func _test_wolf_cave() -> void:
	print("== The wolves' cave (forest phase E) ==")
	var cave := Level.load_level("wolf_cave")
	var config := Level.template_config("wolf_cave")
	var floor := {}
	for cell: Vector2i in cave["terrain"]["floor"]:
		floor[cell] = true
	_check(cave["warnings"].is_empty() and cave["terrain"]["zone"] == "cave" and float(cave["terrain"]["ambient"]) >= 0.1
		and cave["terrain"]["ambience"] == "cave_lair", "read with no warning, a cave, dim but never black (%s)" % [cave["warnings"]])
	var links: Array = cave["links"]
	_check(links.size() == 1 and links[0]["to_map"] == "forest" and links[0]["to_spawn"] == "from_wolf_cave" and not links[0]["closed"],
		"one way out, up to the forest (%s)" % [links])
	var places := Level.places_from(config, [] as Array[String])
	var place: Dictionary = places.get("wolf_cave", {})
	_check(places.size() == 1 and place.get("kind") == "lair" and place.get("holder") == "nobody" and place.get("explore") == true
		and place.get("name") == "the wolves' cave", "its place: the wolves' cave, a lair, nobody's, explored (%s)" % [place])
	var den: Vector2i = place.get("cell", Vector2i(-1, -1))
	var wolves: Array[Vector2i] = []
	var caches: Array = []
	for entity: Dictionary in cave["entities"]:
		if str(entity.get("kind", "")) == "wolf":
			wolves.append(entity["tile"])
		elif str(entity.get("props", {}).get("cache", "")) == "wolf_cave_cache":
			caches.append(entity)
	var by_den := wolves.filter(func(at: Vector2i) -> bool: return Vector2(at - den).length() <= 4.0)
	_check(wolves.size() == 4 and by_den.size() == 2, "four wolves, two by the den (%s)" % [wolves])
	_check(caches.size() == 1 and Vector2(caches[0]["tile"] - den).length() <= 2.5 and caches[0].get("art") == "prop.cache_pack",
		"the traveller's pack, a cache at the den's back (%s)" % [caches])
	var mouth := links[0]["tile"] as Vector2i
	var watchers := wolves.filter(func(at: Vector2i) -> bool: return Vector2(at - mouth).length() <= 10.0)
	var lit: Array = cave["terrain"]["skylights"].filter(func(light: Dictionary) -> bool: return Vector2(light["at"] - mouth).length() <= 8.0)
	var shaft: Array = cave["terrain"]["skylights"].filter(func(light: Dictionary) -> bool: return Vector2(light["at"] - den).length() <= 8.0)
	_check(watchers.size() == 2 and lit.size() >= 1 and shaft.size() >= 1, "two watchers in a skylit mouth chamber, a shaft in the den")
	var pillar := Vector2i(19, 12)
	var ring := true
	for step: Vector2i in [Vector2i(-2, 0), Vector2i(3, 0), Vector2i(0, -2), Vector2i(0, 3)]:
		ring = ring and floor.has(pillar + step)
	_check(not floor.has(pillar) and ring, "a pillar in the den, floor all round it to circle")
	_check(int(config.get("respawn_s", {}).get("wolf", 0)) >= DayNight.DEFAULT_DAY_MINUTES * 60, "the wolves back after a game day or more")
	var forest := Level.load_level("forest")
	var forest_floor := {}
	for cell: Vector2i in forest["terrain"]["floor"]:
		forest_floor[cell] = true
	var door: Dictionary = {}
	for link: Dictionary in forest["links"]:
		if link["to_map"] == "wolf_cave":
			door = link
	var spawn: Array = Level.template_config("forest")["spawn_points"].get("from_wolf_cave", [])
	var at: Vector2i = door.get("tile", Vector2i(-1, -1))
	_check(not door.is_empty() and not door["closed"] and spawn.size() == 2 and forest_floor.has(Vector2i(spawn[0], spawn[1]))
		and not forest_floor.has(at + Vector2i(0, 1)), "the forest's mouth open, its spawn on the pad, rock behind it (%s, %s)" % [door, spawn])
	_check_lair_sight(at, Vector2i(0, -1), forest_floor)

## The old grey's den (780 amended (14)): the old wolf's lair off the
## foothills, its mouth at (97, 31) opening south under the high scarp
## (terrain's "den" cue: its footprint void, no cliff at the link or beside
## it), a two-wide run that turns once so the den is out of sight from the
## door, his bed at the den's back with the hunter's pack at its foot, one
## keeper (780 amended (15): him and three wolves at home, with his escort of
## two), and its place, nobody's.
func _test_grey_den() -> void:
	print("== The old grey's den (780 amended (14)) ==")
	var den_level := Level.load_level("grey_den")
	var config := Level.template_config("grey_den")
	var floor := {}
	for cell: Vector2i in den_level["terrain"]["floor"]:
		floor[cell] = true
	_check(den_level["terrain"]["zone"] == "cave" and float(den_level["terrain"]["ambient"]) >= 0.1
		and den_level["terrain"]["ambience"] == "cave_lair", "a cave, dim but never black, the lair's ambience")
	var links: Array = den_level["links"]
	_check(links.size() == 1 and links[0]["to_map"] == "foothills" and links[0]["to_spawn"] == "from_grey_den" and not links[0]["closed"],
		"one way out, to the foothills (%s)" % [links])
	var places := Level.places_from(config, [] as Array[String])
	var place: Dictionary = places.get("grey_den", {})
	_check(places.size() == 1 and place.get("kind") == "lair" and place.get("holder") == "nobody" and place.get("explore") == true
		and place.get("name") == "the old grey's den", "its place: the old grey's den, a lair, nobody's, explored (%s)" % [place])
	var bed: Vector2i = place.get("cell", Vector2i(-1, -1))
	var wolves: Array[Vector2i] = []
	var caches: Array = []
	for entity: Dictionary in den_level["entities"]:
		if str(entity.get("kind", "")) == "wolf":
			wolves.append(entity["tile"])
		elif str(entity.get("props", {}).get("cache", "")) == "grey_den_cache":
			caches.append(entity)
	_check(wolves.size() == 1 and wolves.all(func(at: Vector2i) -> bool: return Vector2(at - bed).length() <= 6.0),
		"one den keeper, in the den (%s)" % [wolves])
	_check(caches.size() == 1 and Vector2(caches[0]["tile"] - bed).length() <= 1.5 and caches[0].get("art") == "prop.cache_pack",
		"the hunter's pack at the bed's foot (%s)" % [caches])
	_check(int(config.get("respawn_s", {}).get("wolf", 0)) >= DayNight.DEFAULT_DAY_MINUTES * 60, "the keepers back after a game day or more")
	# Walked from the way in: every cell reached, none on a one-cell leg, the
	# bed not in a straight line north of the link (the run turns once).
	var mouth: Vector2i = links[0]["tile"]
	var start := mouth + Vector2i(0, -1)
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if floor.has(cell + step) and not seen.has(cell + step):
				seen[cell + step] = true
				queue.append(cell + step)
	var narrow: Array[Vector2i] = []
	for cell: Vector2i in floor:
		var across_x := floor.has(cell + Vector2i(1, 0)) or floor.has(cell + Vector2i(-1, 0))
		var across_y := floor.has(cell + Vector2i(0, 1)) or floor.has(cell + Vector2i(0, -1))
		if cell != mouth and not (across_x and across_y):
			narrow.append(cell)
	_check(seen.size() >= floor.size() - 1 and floor.has(bed) and narrow.is_empty(),
		"one piece from the way in, no leg under two wide (%d of %d, narrow %s)" % [seen.size(), floor.size(), narrow])
	var hidden := true
	for y in range(bed.y, mouth.y):
		hidden = hidden and not (floor.has(Vector2i(mouth.x, y)) and Vector2(Vector2i(mouth.x, y) - bed).length() <= 5.0)
	_check(floor.size() >= 130 and floor.size() <= 210 and hidden and absi(bed.x - mouth.x) >= 8,
		"small (%d cells), the den off the door's line" % floor.size())
	# The foothills' side: held back (820) till the old grey's package.
	if Level.SHELVED.has("grey_den"):
		_check_shelved("grey_den", "foothills", Vector2i(97, 31))
		return
	var hills := Level.load_level("foothills")
	var hills_floor := {}
	for cell: Vector2i in hills["terrain"]["floor"]:
		hills_floor[cell] = true
	var door: Dictionary = {}
	for link: Dictionary in hills["links"]:
		if link["to_map"] == "grey_den":
			door = link
	var at: Vector2i = door.get("tile", Vector2i(-1, -1))
	var entry: Dictionary = {}
	for given: Dictionary in Level.template_config("foothills").get("links", []):
		if given.get("to_map") == "grey_den":
			entry = given
	var spawn: Array = Level.template_config("foothills")["spawn_points"].get("from_grey_den", [])
	_check(at == Vector2i(97, 31) and not door["closed"] and entry.get("mouth") == "den" and spawn.size() == 2
		and Vector2i(spawn[0], spawn[1]) == Vector2i(97, 33) and hills_floor.has(Vector2i(97, 33)),
		"the foothills' den mouth at (97, 31), open, its spawn on the pad (%s, %s)" % [door, spawn])
	var footprint: Array[Vector2i] = []
	for back in range(0, 3):
		for across in range(-2, 3):
			if back > 0 or across != 0:
				footprint.append(at + Vector2i(across, -back))
	var dug: Array = footprint.filter(func(cell: Vector2i) -> bool: return hills_floor.has(cell))
	_check(footprint.size() == 14 and dug.is_empty(), "its footprint's 14 cells void, for terrain's den (%s)" % [dug])
	var relief: PackedFloat32Array = hills["terrain"]["relief"]
	var size: Vector2i = hills["terrain"]["relief_size"]
	var cliffs: Array = []
	for cell: Vector2i in [at, at + Vector2i(-1, 1), at + Vector2i(0, 1), at + Vector2i(1, 1), at + Vector2i(0, 2)]:
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)]:
			var next := cell + step
			if (hills_floor.has(next) or next == at) and Relief.cliff_between(Relief.at(relief, size, cell), Relief.at(relief, size, next)):
				cliffs.append([cell, next])
	_check(cliffs.is_empty(), "no cliff at the link, its pad or beside them (%s)" % [cliffs])
	var strip: Array[Vector2i] = []
	for out in range(3, 9):
		for across in range(-(2 if out >= 5 else 1), (2 if out >= 5 else 1) + 1):
			if not hills_floor.has(at + Vector2i(across, out)):
				strip.append(at + Vector2i(across, out))
	_check(strip.is_empty(), "its sightline south open ground, no clump on it (%s)" % [strip])
	var pads: Array = [Vector2i(128, 93), Vector2i(128, 2)]
	_check(pads.all(func(pad: Vector2i) -> bool: return Vector2(pad - at).length() >= 30.0), "30 cells or more from either pad")

## The forest's camps (793, maps' side; forest phase C): seven, each a camp
## building with its place at its fire, 6 to 12 cells off a path and 24
## apart; bandit and mixed camps the bandits', with their band round the
## fire; traders' and mixed camps a trader by the fire, his bed and cart in
## the camp; C3's captive at its edge; something at every camp, never a
## chest (Jeff: chests are the dungeons').
func _test_forest_camps() -> void:
	print("== The forest's camps (793, maps' side) ==")
	var warnings: Array[String] = []
	var forest := Level.load_level("forest")
	var floor := {}
	for cell: Vector2i in forest["terrain"]["floor"]:
		floor[cell] = true
	var config := Level.template_config("forest")
	var places := Level.places_from(config, warnings)
	_check(warnings.is_empty(), "the forest's places read without a warning (%s)" % [warnings])
	var camps := {}
	for key: String in places:
		if places[key]["kind"] == "camp":
			camps[key] = places[key]
	_check(camps.size() == 7, "seven camps (%s)" % [camps.keys()])
	_check(Factions.read().hostile("bandits", "town"), "the camps' holder, the bandits, is hostile to the town (793)")
	var rects := {}
	for building: Dictionary in forest["buildings"]:
		if building.get("kind") == "camp":
			rects[Level.camp_fire(building)] = building["rect"]
	var wrong: Array[String] = []
	var band := {}
	for spec: Dictionary in forest["entities"]:
		if str(spec.get("kind", "")).begins_with("bandit"):
			band[spec["tile"]] = spec["kind"]
		if str(spec.get("kind", "")) == "chest" or str(spec.get("name", "")).begins_with("Chest"):
			wrong.append("a chest at %s" % [spec["tile"]])
	for key: String in camps:
		var camp: Dictionary = camps[key]
		var fire: Vector2i = camp["cell"]
		if not rects.has(fire):
			wrong.append("%s: no camp building with its fire at %s" % [key, fire])
			continue
		var rect: Rect2i = rects[fire]
		var mix: String = camp.get("mix", "")
		if camp["holder"] != ("nobody" if mix == "trader" else "bandits"):
			wrong.append("%s (%s) held by %s" % [key, mix, camp["holder"]])
		var in_band := 0
		for at: Vector2i in band:
			if rect.has_point(at):
				in_band += 1
		if (mix == "trader") != (in_band == 0):
			wrong.append("%s (%s): %d bandits" % [key, mix, in_band])
		if mix != "bandit":
			var trader: Dictionary = places.get(key + "_trader", {})
			if trader.get("kind") != "trader" or not rect.has_point(trader.get("bed", Vector2i(-1, -1))) or trader.get("rect") != rect 					or trader["cell"] + trader.get("facing", Vector2i.ZERO) != fire:
				wrong.append("%s: its trader (%s)" % [key, trader])
		for other: String in camps:
			if other != key and Vector2(camps[other]["cell"] - fire).length() < 24.0:
				wrong.append("%s within 24 of %s" % [key, other])
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if not floor.has(Vector2i(x, y)):
					wrong.append("%s: (%d, %d) in it is no floor" % [key, x, y])
	_check(wrong.is_empty(), "each camp's building, holder, band and trader as its mix says, 24 apart, on floor, no chest (%s)" % [wrong])
	var captive: Dictionary = places.get("loop_camp_captive", {})
	var loop_rect: Rect2i = rects.get(camps.get("loop_camp", {}).get("cell", Vector2i(-1, -1)), Rect2i())
	_check(captive.get("kind") == "captive" and not loop_rect.has_point(captive["cell"]) and floor.has(captive["cell"])
		and Vector2(captive["cell"] - camps["loop_camp"]["cell"]).length() < 6.0,
		"C3's captive stands at its camp's edge, outside it (%s)" % [captive])
	var decor_at := {}
	for piece: Dictionary in forest["terrain"]["decor"]:
		decor_at[piece["cell"]] = piece["kind"]
	var bare: Array[String] = []
	for key: String in camps:
		var rect: Rect2i = rects.get(camps[key]["cell"], Rect2i())
		var things := 0
		for at: Vector2i in decor_at:
			if rect.has_point(at):
				things += 1
		if things == 0:
			bare.append(key)
	_check(bare.is_empty(), "every camp has goods or plunder lying in it besides its fire and people (bare: %s)" % [bare])


## The places a player is rewarded for reaching (decision 804, maps'
## side): the named refuges, rests, workings and forts out in the lands
## (the hills' six, the Old Tower), never a town's store, stall, tavern,
## fire, post or temple, nor a place with no name of its own.
func _test_explorables() -> void:
	print("== The places worth reaching (804, maps' side) ==")
	var town_kinds := ["stockpile", "stall", "tavern", "fire", "post", "temple", "healers_hut", "keep", "gate"]
	var wrong: Array[String] = []
	var by_level := {}
	for level_name: String in ["wilds", "hills", "held", "forest", "foothills", "castle_halls"]:
		var listed: Dictionary = Level.template_config(level_name).get("places", {})
		var warnings: Array[String] = []
		var places := Level.places_from(Level.template_config(level_name), warnings)
		var reached: Array[String] = []
		for key: String in places:
			if not places[key]["explore"]:
				continue
			reached.append(key)
			if places[key]["kind"] in town_kinds or (listed[key] as Dictionary).get("name", "") == "":
				wrong.append("%s/%s" % [level_name, key])
		reached.sort()
		by_level[level_name] = reached
	_check(wrong.is_empty(), "no town place and no unnamed place is worth reaching (%s)" % [wrong])
	var hill_found: Array = ["bridge_camp", "herders_hut", "hill_cave", "hill_shieling", "spur_camp"]
	if not preload("res://tools/make_hills.gd").SHELTER_BUILT:
		hill_found.erase("hill_cave")  # Its package waits on terrain's shelter (820's rule).
	_check(by_level["hills"] == hill_found and by_level["held"] == ["old_tower"],
		"the hills' refuges and camps and the Old Tower are; Hollowfell's mouth is not, the zone counts (%s)" % [by_level])
	_check(not by_level["wilds"].has("store") and by_level["wilds"].has("old_farmstead") and not by_level["forest"].has("boar_path"),
		"the wilds' farmstead is, its store is not, nor the forest's path to the hunters' camps (a way, not a place) (%s)" % [by_level])
	var shown := {}
	for level_name: String in ["wilds", "hills", "forest"]:
		var warnings: Array[String] = []
		var places := Level.places_from(Level.template_config(level_name), warnings)
		for key: String in places:
			if places[key]["shown"] != places[key]["name"]:
				shown[key] = places[key]["shown"]
	_check(shown == {"far_bank": "the far bank", "hill_shieling": "the shieling", "woodcutters_lean_to": "a woodcutters' lean-to", "thick_wood": "the thick of the forest"},
		"voice's shown names where the name is a where-phrase (%s)" % [shown])


## The bear yard's den (780's dev level; combat's ask, through the
## coordinator): its rock crescent backs the den on the west with an arm on
## the north only, so a player fighting it in the den's south corner has
## open ground to step out to, not a pocket (playtest's bear13 duel was
## boxed in at (7..10, 24..27)).
func _test_bear_den() -> void:
	print("== The bear yard's den opens east and south ==")
	var yard := Level.load_level("bear_yard")
	var floor := {}
	for cell: Vector2i in yard["terrain"]["floor"]:
		floor[cell] = true
	var den := Vector2i(8, 22)
	var shut: Array[Vector2i] = []
	var open: Array[Vector2i] = []
	for y in range(den.y - 3, den.y + 6):
		for x in range(den.x - 2, den.x + 3):
			var cell := Vector2i(x, y)
			if x > den.x - 2 and y > den.y + 2 and not floor.has(cell):
				shut.append(cell)
			elif x == den.x - 2 and y >= den.y - 3 and y <= den.y + 3 and floor.has(cell):
				open.append(cell)
	_check(floor.has(den) and shut.is_empty() and open.is_empty(),
		"the den at %s: rock behind it on the west, none to its south (shut south: %s; gaps in the back: %s)" % [den, shut, open])



## The hill cat's perches (maps' side): three "perch" places in the hills,
## held by nobody, each with a "watch" of 8 or more cells within 4 of it;
## the perch and every watch cell floor, 6 or more cells from every safe
## path (the road and the tracks), the watch lower than the perch by 1 to
## 2.5 m; the perches 45 or more apart.
func _test_perches(hills: Dictionary) -> void:
	print("== The hill cat's perches ==")
	var config := Level.template_config("hills")
	var warnings: Array[String] = []
	var places := Level.places_from(config, warnings)
	var safe := Level.safe_paths(hills["terrain"])
	var floor := {}
	for cell: Vector2i in hills["terrain"]["floor"]:
		floor[cell] = true
	var perches: Array[Dictionary] = []
	for key: String in places:
		if places[key]["kind"] == "perch":
			perches.append(places[key])
	_check(warnings.is_empty() and perches.size() == 3 and perches.all(func(perch: Dictionary) -> bool: return perch["holder"] == "nobody"),
		"three perches, held by nobody, read with no warning (%s)" % [warnings])
	var near_safe := func(at: Vector2i) -> bool:
		return safe.keys().any(func(cell: Vector2i) -> bool: return Vector2(cell - at).length() < 6.0)
	for perch in perches:
		var at: Vector2i = perch["cell"]
		var watch: Array = perch.get("watch", [])
		var top := Level._elevation(hills["terrain"], at)
		var bad := watch.filter(func(cell: Vector2i) -> bool:
			var drop := top - Level._elevation(hills["terrain"], cell)
			return not floor.has(cell) or Vector2(cell - at).length() > 4.0 or near_safe.call(cell) or drop < 0.99 or drop > 2.51)
		_check(floor.has(at) and not near_safe.call(at) and watch.size() >= 8 and bad.is_empty(),
			"%s at %s: off every safe path, %d watch cells below it within 4 (bad %s)" % [perch["key"], at, watch.size(), bad])
	var close := false
	for i in perches.size():
		for j in range(i + 1, perches.size()):
			close = close or Vector2(perches[i]["cell"] - perches[j]["cell"]).length() < 45.0
	_check(not close, "the perches 45 or more apart: one walk, one cat")

## The hills' carved stones (800, maps' side): the two milestones read
## "Umbrage" and "Shieling" on milestone variant 2, the two waystones "Hut"
## (arrow left) and "Cave" (arrow right) on waystone variant 3, and the fork's
## "Mine" (arrow left, MINE_TRACK); no other stone in the hills is carved.
func _test_carved(hills: Dictionary) -> void:
	print("== The hills' carved stones (800) ==")
	var want := {"Umbrage": ["building.milestone", 2, ""], "Shieling": ["building.milestone", 2, ""],
		"Hut": ["building.waystone", 3, "left"], "Cave": ["building.waystone", 3, "right"],
		"Mine": ["building.waystone", 3, "left"]}
	if not preload("res://tools/make_hills.gd").SHELTER_BUILT:
		want.erase("Cave")  # W4 waits on the hill cave's shelter (820's rule).
	var carved := {}
	for building: Dictionary in hills.get("buildings", []):
		if building.has("carved"):
			carved[building["carved"]] = [building["slot"], int(building.get("variant", 1)), str(building.get("arrow", ""))]
	_check(carved == want, "the milestones and waystones carry their words, variants and arrows, and nothing else does (%s)" % [carved])


## Marks every Relaid.REMOVED entry done in [param done].
static func _removals_done(done: Dictionary) -> void:
	for plan: Dictionary in Relaid.REMOVED:
		done[Relaid.done_key_of(plan["level"], plan["decision"])] = plan["decision"]


## Chests only in dungeons (807): the removed markers are gone from their
## levels, and a save from before has their saved chests dropped once, what
## they held (slots, and a stacked unit the book has at it) laid on a pile on
## the cell, the book following; a chest kept elsewhere untouched; the line
## counts only; the next boot does nothing; a level still holding a removed
## marker (an overlay copy) waits.
func _test_removed(wilds: Dictionary) -> void:
	print("
== Chests only in dungeons: the outdoor chests removed, their things on the ground (807) ==")
	for plan: Dictionary in Relaid.REMOVED:
		var level := Level.load_level(plan["level"])
		var tiles: Array = (level["entities"] as Array).map(func(spec: Dictionary) -> Vector2i: return spec["tile"])
		for key: String in plan["removed"]:
			_check(not Vector2i(int(key.get_slice(",", 0)), int(key.get_slice(",", 1))) in tiles, "%s: no marker at %s now" % [plan["level"], key])
	var full := {"script": "res://sim/chest.gd", "shape": "chest", "name": "Chest7", "tile": [201, 83], "hp": 1, "stamina": 0,
		"facing": [0, 1], "props": {}, "spawn": 2, "spawn_key": "201,83", "slots": ["bandaging_kit", "", "arrows", ""], "items": [11, 0, 12, 0]}
	var empty := {"script": "res://sim/chest.gd", "shape": "chest", "name": "Chest3", "tile": [122, 138], "hp": 1, "stamina": 0,
		"facing": [0, 1], "props": {}, "spawn": 1, "spawn_key": "122,138", "slots": ["", "", "", ""], "items": [0, 0, 0, 0]}
	var stays := {"script": "res://sim/chest.gd", "shape": "chest", "name": "Chest9", "tile": [119, 139], "hp": 1, "stamina": 0,
		"facing": [0, 1], "props": {}, "spawn": 0, "spawn_key": "119,139", "slots": ["knife"], "items": [14]}
	var path: String = preload("res://tests/test_ports.gd").scratch("removed_world.json")
	_check(Snapshot.write(path, {"version": Snapshot.VERSION, "players": [], "remade": {"relaid/wilds": 774},
		"items": {"next": 20, "book": {"11": {"id": "bandaging_kit", "at": "wilds/Chest7"}, "12": {"id": "arrows", "at": "wilds/Chest7"},
			"13": {"id": "arrows", "at": "wilds/Chest7"}, "14": {"id": "knife", "at": "wilds/Chest9"}}},
		"zones": {"wilds": {"tick": 9, "entities": [full, empty, stays], "respawns": [], "ground": [], "records": []}}}), "(the old world written)")
	var snapshot := Snapshot.load(path)
	var done: Dictionary = snapshot.get("remade", {})
	var key := Relaid.done_key_of("wilds", 807)
	var waits := Relaid.move(snapshot, done, func(level: String) -> Dictionary:
			return {"entities": [{"tile": Vector2i(201, 83)}], "terrain": {"floor": []}} if level == "wilds" else Level.load_level(level))
	_check(waits.any(func(line: String) -> bool: return "wait" in line and line.begins_with("[level] wilds")) and not done.has(key)
		and snapshot["zones"]["wilds"]["entities"].size() == 3, "a wilds still holding a removed marker: nothing removed, not marked (%s)" % [waits])
	var lines := Relaid.move(snapshot, done, func(level: String) -> Dictionary: return wilds if level == "wilds" else Level.load_level(level))
	var section: Dictionary = snapshot["zones"]["wilds"]
	var line: String = lines.filter(func(each: String) -> bool: return each.begins_with("[level] removed in wilds"))[0] if lines.size() > 0 else ""
	_check(done.get(key) == 807 and done.get("relaid/wilds") == 774 and done.has(Relaid.done_key_of("held", 807)) and done.has(Relaid.done_key_of("castle", 807)),
		"each removal marked done under its own key, 774's kept (%s)" % [done])
	_check(line == "[level] removed in wilds (807): 2 saved entities removed, 1 holding things, 3 things laid on the ground, 0 left where they were (no floor near)",
		"one count-only line for the wilds (%s)" % [lines])
	_check(section["entities"].size() == 1 and section["entities"][0]["spec"]["spawn_key"] == "119,139" and section["entities"][0]["slots"] == ["knife"]
		and snapshot["items"]["book"]["14"]["at"] == "wilds/Chest9", "the farmstead's cache, kept, is untouched")
	var pile: Dictionary = section["ground"][0] if section["ground"].size() == 1 else {}
	var at := "wilds@%d,%d" % [pile.get("cell", Vector2i(-1, -1)).x, pile.get("cell", Vector2i(-1, -1)).y]
	_check(pile.get("cell") == Vector2i(201, 83) and pile.get("ids") == ["bandaging_kit", "arrows", "arrows"] and pile.get("items") == [11, 12, 13]
		and ["11", "12", "13"].all(func(uid: String) -> bool: return snapshot["items"]["book"][uid]["at"] == at),
		"the camp chest's kit and arrows, and the stacked arrow the book had at it, lie on its cell, the book following (%s)" % [pile])
	_check(Relaid.move(snapshot, done, func(level: String) -> Dictionary: return wilds if level == "wilds" else Level.load_level(level)).is_empty(), "the next boot does nothing")
	var odd := {"ok": true, "items": {"book": {}}, "zones": {"wilds": {"entities": [{"spec": {"name": "Chest7", "tile": Vector2i(201, 83), "spawn_key": "201,83"},
		"slots": ["knife"], "items": [21]}], "respawns": [], "ground": [], "records": []}}}
	var odd_line := Relaid._remove(odd, {}, func(_level: String) -> Dictionary: return wilds,
		{"level": "wilds", "decision": 999, "removed": {"201,83": {"to": "somewhere_new"}}})
	_check(odd_line.ends_with(", 1 with an unknown destination laid on the ground") and odd["zones"]["wilds"]["ground"].size() == 1
		and odd["zones"]["wilds"]["ground"][0]["ids"] == ["knife"], "a destination this build does not know: on the ground, counted, never dropped (%s)" % odd_line)


## The inn become a shell (811): what was saved inside its footprint (a
## pile, an entity, a player and their companion) carried out once onto the
## nearest floor outside it, the pile's item-book place with it; a level
## loading with no shell (an overlay copy) waits unmarked; the next boot
## moves nothing.
func _test_shelled(wilds: Dictionary) -> void:
	print("
== the inn become a shell: what was saved inside carried out once (811) ==")
	var plan: Dictionary = Relaid.SHELLS["wilds"]
	var rect := Rect2i(plan["rect"][0], plan["rect"][1], plan["rect"][2], plan["rect"][3])
	var inside := Vector2i(173, 207)
	var record := PlayerRecord.new()
	record.player_id = "lt-shelled"
	record.zone = "wilds"
	record.tile = inside
	record.companion = {"tile": [174, 207]}
	var crate := {"script": "res://sim/chest.gd", "shape": "chest", "name": "chest", "tile": [174, 210], "hp": 1, "stamina": 0,
		"facing": [0, 1], "props": {}, "spawn": -1, "spawn_key": "", "slots": [], "items": []}
	var path: String = preload("res://tests/test_ports.gd").scratch("shelled_world.json")
	_check(Snapshot.write(path, {"version": Snapshot.VERSION, "players": [record.to_dict()], "remade": {"relaid/wilds": 774},
		"items": {"9": {"at": "wilds@176,206"}},
		"zones": {"wilds": {"tick": 9, "entities": [crate], "respawns": [],
			"ground": [{"cell": [176, 206], "ids": ["coin"], "items": [9], "gold": 0}], "records": []}}}), "(the world before the shell written)")
	var snapshot := Snapshot.load(path)
	var done: Dictionary = snapshot.get("remade", {})
	var waits := Relaid.shell(snapshot, done, func(_level: String) -> Dictionary: return {"buildings": [], "terrain": {"floor": []}})
	_check(waits.size() == 1 and "not shelled" in waits[0] and not done.has(Relaid.done_key_of("wilds", 811)), "no shell where it loads: nothing moved, it waits (%s)" % [waits])
	var lines := Relaid.shell(snapshot, done, func(_level: String) -> Dictionary: return wilds)
	var pile: Dictionary = snapshot["zones"]["wilds"]["ground"][0]
	var moved: PlayerRecord = snapshot["players"][0]
	var spec: Dictionary = snapshot["zones"]["wilds"]["entities"][0]["spec"]
	var floor := {}
	for cell: Vector2i in wilds["terrain"]["floor"]:
		floor[cell] = true
	var out := func(cell: Variant) -> bool: return cell is Vector2i and floor.has(cell) and not rect.has_point(cell)
	var cell: Variant = Snapshot.vector(pile["cell"]) if not pile["cell"] is Vector2i else pile["cell"]
	_check(lines.size() == 1 and lines[0].begins_with("[level] shelled wilds (811): 1 saved entities, 1 ground piles and 1 players moved out")
		and lines[0].ends_with(", 0 left where they were (no floor near)") and not "lt-shelled" in lines[0] and done.get(Relaid.done_key_of("wilds", 811)) == 811
		and done.get("relaid/wilds") == 774, "one count-only line, marked done under its own key beside the re-lay's (%s)" % [lines])
	_check(out.call(cell) and out.call(spec["tile"]) and out.call(moved.tile) and moved.companion.get("tile") == null
		and snapshot["items"]["9"]["at"] == "wilds@%d,%d" % [cell.x, cell.y],
		"the pile, the entity and the player outside the inn on floor, the companion beside them, the item book following the pile")
	_check(Relaid.shell(snapshot, done, func(_level: String) -> Dictionary: return wilds).is_empty(), "the next boot moves nothing")


## Umbrage's tavern as its own zone (the tavern zone design; Jeff: "allows
## multi floors, attics, rooms etc"): tools/make_interior.py's three floors
## parse clean, each Umbrage's and naming the building's storeys; the
## wilds inn's two-cell way in leads to the ground floor's arrival and
## closes while the inn isn't standing; every link's far spawn exists;
## every floor cell is reached from where one arrives; the tavern (its
## counter, eight seats, hearth) on the ground floor, Umbrage's; the beds
## counted over every floor; the stores drawn as decor.
## Every building with floors (811 amended (5); Jeff: "in the tavern there's
## no way to get down from the 2nd floor"): each level under levels/ whose
## level.json names its "storeys", taken a building at a time. Every floor
## reaches the ground floor (its first storey) by its links and is reached
## from it; every link's cell and its arrival are floor; and every stair's
## cue stands off the floor's south row (the outer wall nearest the view
## hid the Mughouse's) and faces the way its link says.
func _test_storey_stairs() -> void:
	print("
== Every floor of every building: down to the ground and back, its stairs in sight (811 amended (5)) ==")
	var buildings := {}
	for name: String in DirAccess.get_directories_at("res://levels"):
		if not FileAccess.file_exists("res://levels/%s/level.json" % name):
			continue
		var storeys: Variant = Level.template_config(name).get("storeys")
		if storeys is Array and not (storeys as Array).is_empty():
			buildings[str(storeys[0])] = storeys
	_check(buildings.has("umbrage_tavern"), "the buildings with floors found, the Mughouse among them (%s)" % [buildings.keys()])
	for ground: String in buildings:
		var names: Array = buildings[ground]
		var floors := {}
		for name: Variant in names:
			floors[str(name)] = Level.load_level(str(name))
		var ways := {}
		var bad: Array[String] = []
		for name: String in floors:
			var level: Dictionary = floors[name]
			var floor := {}
			for cell: Vector2i in level["terrain"]["floor"]:
				floor[cell] = true
			var own := {}
			for entry: Variant in Level.template_config(name).get("links", []):
				if entry is Dictionary and Level._tile(entry.get("at")) != null:
					own[Level._tile(entry.get("at"))] = entry
			for link: Dictionary in level["links"]:
				var to := str(link["to_map"])
				if not floors.has(to):
					continue
				ways[name + ">" + to] = true
				var arrival: Variant = (floors[to] as Dictionary)["spawn_points"].get(str(link["to_spawn"]))
				var there := {}
				for cell: Vector2i in floors[to]["terrain"]["floor"]:
					there[cell] = true
				if not floor.has(link["tile"]) or arrival == null or not there.has(arrival):
					bad.append("%s %s: its cell or arrival %s not floor" % [name, link["tile"], arrival])
			for cue: Dictionary in level["terrain"].get("link_cues", []):
				if cue["cue"] not in ["up", "down"]:
					continue
				var at: Vector2i = cue["tile"]
				var said: Variant = Level._tile((own.get(at, {}) as Dictionary).get("facing"))
				if at.y >= (level["size"] as Vector2i).y - 1 or said == null or cue["facing"] != said:
					bad.append("%s %s: on the south row or not facing as said (%s, %s)" % [name, at, cue["facing"], said])
		var reach := func(from: String, back: bool) -> Array:
			var seen := [from]
			var i := 0
			while i < seen.size():
				for other: Variant in names:
					var key: String = (str(other) + ">" + str(seen[i])) if back else (str(seen[i]) + ">" + str(other))
					if ways.has(key) and str(other) not in seen:
						seen.append(str(other))
				i += 1
			return seen
		var down: Array = reach.call(ground, true)
		var up: Array = reach.call(ground, false)
		_check(down.size() == names.size() and up.size() == names.size() and bad.is_empty(),
			"%s: all %d floors reach the ground and back (down %s, up %s), every stair in sight (bad %s)" % [ground, names.size(), down, up, bad])


func _test_tavern_zone(wilds: Dictionary) -> void:
	print("
== Umbrage's tavern, its own zone: three floors, its way in, its tavern and beds ==")
	var names: Array[String] = ["umbrage_tavern", "umbrage_tavern_up", "umbrage_tavern_attic"]
	var floors := {}
	for name in names:
		floors[name] = Level.load_level(name)
		var level: Dictionary = floors[name]
		_check(not level.is_empty() and (level["warnings"] as Array).is_empty() and level["town"] == "wilds/store" and level["storeys"] == names
			and not level["terrain"]["outdoor"], "%s: parses clean, indoors, Umbrage's, its storeys the building's (%s)" % [name, level.get("warnings")])
	floors["wilds"] = wilds
	var ins := (wilds["links"] as Array).filter(func(link: Dictionary) -> bool: return link["to_map"] == "umbrage_tavern")
	var tiles := ins.map(func(link: Dictionary) -> Vector2i: return link["tile"])
	tiles.sort()
	_check(tiles == [Vector2i(178, 208), Vector2i(178, 209)] and ins.all(func(link: Dictionary) -> bool:
		return link["to_spawn"] == "from_wilds" and link.get("stands", {}) == {"town": "wilds/store", "use": "inn"}),
		"the inn's way in: two cells inside its door, to the ground floor, closed unless the inn stands (%s)" % [tiles])
	var unpaired: Array[String] = []
	for name: String in floors:
		for link: Dictionary in floors[name]["links"]:
			var far: Dictionary = floors.get(link["to_map"], {})
			if (name != "wilds" or link["to_map"].begins_with("umbrage_tavern")) and not far.get("spawn_points", {}).has(link["to_spawn"]):
				unpaired.append("%s %s -> %s/%s" % [name, link["tile"], link["to_map"], link["to_spawn"]])
	_check(unpaired.is_empty(), "every link in and out lands on a spawn on its far side (%s)" % [unpaired])
	# Its way out a door in its wall (Jeff, 2026-11-06: "no door to exit.
	# just a spot on the ground"): each link to the wilds on a doorstep
	# beyond a door edge from the common room, one arriving just inside it.
	var tavern_floor: Dictionary = floors["umbrage_tavern"]
	var outs: Array = (tavern_floor["links"] as Array).filter(func(link: Dictionary) -> bool: return link["to_map"] == "wilds")
	var through_door := outs.all(func(link: Dictionary) -> bool:
		return int(tavern_floor["terrain"]["edges"].get(Terrain.edge_key(link["tile"], Vector2i(0, -1)), Terrain.Edge.OPEN)) == Terrain.Edge.DOOR)
	_check(outs.size() == 2 and through_door and tavern_floor["spawn_points"]["from_wilds"] == Vector2i(5, 13)
		and outs.all(func(link: Dictionary) -> bool: return (link["tile"] as Vector2i).y == 14),
		"the tavern's way out through a door in its south wall, the link on its doorstep, one arriving just inside (%s)" % [outs.map(func(link: Dictionary) -> Vector2i: return link["tile"])])
	for name in names:
		var level: Dictionary = floors[name]
		var floor := {}
		for cell: Vector2i in level["terrain"]["floor"]:
			floor[cell] = true
		var edges: Dictionary = level["terrain"]["edges"]
		var from: Vector2i = level["spawn_points"].values()[0]
		var seen := {from: true}
		var todo: Array[Vector2i] = [from]
		while not todo.is_empty():
			var cell: Vector2i = todo.pop_back()
			for way: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
				var next := cell + way
				if floor.has(next) and not seen.has(next) and int(edges.get(Terrain.edge_key(cell, way), Terrain.Edge.OPEN)) != Terrain.Edge.WALL:
					seen[next] = true
					todo.append(next)
		_check(seen.size() == floor.size(), "%s: all %d floor cells reached from %s (%d)" % [name, floor.size(), from, seen.size()])
	var ground: Dictionary = floors["umbrage_tavern"]
	var tavern: Dictionary = Level.tavern_of(ground).get("wilds/store", {})
	var cells: Array[Vector2i] = []
	if not tavern.is_empty():
		cells.assign([tavern["counter"]] + tavern["seats"])
	var ground_floor := {}
	for cell: Vector2i in ground["terrain"]["floor"]:
		ground_floor[cell] = true
	_check(Level.tavern_of(ground).keys() == ["wilds/store"] and tavern["seats"].size() == 8 and (ground["terrain"]["fire"] as Array).has(tavern["hearth"])
		and cells.all(func(cell: Vector2i) -> bool: return (tavern["rect"] as Rect2i).has_point(cell) and ground_floor.has(cell)),
		"the tavern on the ground floor, Umbrage's: its counter and eight seats on floor in the common room, its hearth a fire")
	# Its lit candles (811 amended (4)): one on each table's middle, where its
	# four cells meet, at the table's top, and one on the bar's middle.
	var on_pieces: Array[String] = []
	for entry: Dictionary in ground["terrain"].get("lit_candles", []):
		var at: Vector2 = entry["at"]
		for building: Dictionary in ground["buildings"]:
			var rect: Rect2i = building["rect"]
			if Rect2(Vector2(rect.position) - Vector2(0.5, 0.5), Vector2(rect.size)).has_point(at):
				on_pieces.append("%s %.2f" % [building["slot"], float(entry["top"])])
	on_pieces.sort()
	_check(on_pieces == ["building.bar_counter 1.05", "building.tavern_table 0.79", "building.tavern_table 0.79",
			"building.tavern_table 0.79", "building.tavern_table 0.79"]
		and (floors["umbrage_tavern_up"]["terrain"].get("lit_candles", []) as Array).is_empty(),
		"the Mughouse's lit candles on its four tables and its bar, at their tops, none upstairs (%s)" % [on_pieces])
	var storeys := Level.storeys_of("umbrage_tavern")
	var beds: Array = storeys["beds"]
	var laid := beds.filter(func(bed: Dictionary) -> bool:
		var floor: Array = floors[bed["level"]]["terrain"]["floor"]
		return (bed["cells"] as Array).all(func(cell: Vector2i) -> bool: return floor.has(cell)))
	_check(storeys["storeys"] == names and beds.size() == 6 and laid.size() == 6
		and beds.filter(func(bed: Dictionary) -> bool: return bed["level"] == "umbrage_tavern_up").size() == 5,
		"its beds over every floor: the keeper's below, five hired rooms upstairs (%d)" % beds.size())
	var stores := func(level: Dictionary) -> Array: return (level["terrain"]["decor"] as Array).map(func(piece: Dictionary) -> String: return piece["kind"])
	_check(stores.call(ground) == ["wall_hearth", "crate", "barrel"] and stores.call(floors["umbrage_tavern_attic"]) == ["crate", "barrel", "sack", "crate"],
		"the kitchen's and the attic's stores drawn as decor, nothing to open (%s)" % [stores.call(floors["umbrage_tavern_attic"])])
	# Its common room furnished (811 amended, art-kit's Mughouse pieces): the
	# counter with the taverner behind it, the tap rack against the wall
	# behind him, four tables (two laid), all solid, every seat and the
	# taverner on the floor left; the fireplace over the hearth's two fire
	# cells against the west wall; the tavern lore's last_light.
	var pieces := {}
	for building: Dictionary in ground["buildings"]:
		pieces[building["rect"]] = [building["slot"], int(building.get("variant", 1))]
	var want := {Rect2i(8, 3, 3, 1): ["building.bar_counter", 1], Rect2i(9, 0, 2, 1): ["building.tap_rack", 1],
		Rect2i(3, 6, 2, 2): ["building.tavern_table", 1], Rect2i(8, 6, 2, 2): ["building.tavern_table", 2],
		Rect2i(3, 10, 2, 2): ["building.tavern_table", 1], Rect2i(8, 10, 2, 2): ["building.tavern_table", 2]}
	var solid := want.keys().all(func(rect: Rect2i) -> bool:
		return Level.rect_cells(rect).all(func(cell: Vector2i) -> bool: return not ground_floor.has(cell)))
	_check(pieces == want and solid and tavern["counter"] == Vector2i(9, 2),
		"the common room's counter, tap rack and four tables where laid, solid, the taverner behind the counter (%s)" % [pieces])
	var hearth: Array = (ground["terrain"]["decor"] as Array).filter(func(piece: Dictionary) -> bool: return piece["kind"] == "wall_hearth")
	_check(hearth.size() == 1 and hearth[0]["cell"] == Vector2i(0, 6) and hearth[0]["out"] == Vector2i(-1, 0)
		and [Vector2i(0, 6), Vector2i(0, 7)].all(func(cell: Vector2i) -> bool: return (ground["terrain"]["fire"] as Array).has(cell)),
		"the fireplace against the west wall over the hearth's two fire cells (%s)" % [hearth])
	var tavern_place: Dictionary = ground["places"].get("tavern", {})
	_check(tavern_place.get("lore_id") == "last_light" and Lore.entries().get("last_light", {}).get("type") == "place",
		"the tavern is lore's last_light, a place (%s)" % [tavern_place.get("lore_id")])
	var signs: Array = (wilds["terrain"]["decor"] as Array).filter(func(piece: Dictionary) -> bool: return piece["kind"] == "inn_sign")
	var inn_rect: Rect2i = (wilds["buildings"] as Array).filter(func(building: Dictionary) -> bool: return building.get("use") == "inn")[0]["rect"]
	_check(signs.size() == 1 and signs[0]["cell"] == Vector2i(180, 207) and not inn_rect.has_point(signs[0]["cell"])
		and inn_rect.has_point(signs[0]["cell"] + signs[0]["out"]), "the inn's sign on its street front, out of its wall (%s)" % [signs])
	# The chapel yard's grate (806, buildings' side) over the barrow's first
	# hall, whose light shaft and skylight stand under it at (46, 13).
	var grates: Array = (wilds["terrain"]["decor"] as Array).filter(func(piece: Dictionary) -> bool: return piece["kind"] == "yard_grate")
	var barrow := Level.load_level("barrow")
	var lit: Array = (barrow["terrain"]["skylights"] as Array).filter(func(sky: Dictionary) -> bool: return sky["at"] == Vector2i(46, 13))
	var roofed := (wilds["buildings"] as Array).any(func(building: Dictionary) -> bool: return (building["rect"] as Rect2i).has_point(Vector2i(201, 202)))
	_check(grates.size() == 1 and grates[0]["cell"] == Vector2i(201, 202) and int(grates[0]["variant"]) == 1 and not roofed and lit.size() == 1,
		"the chapel yard's grate at (201, 202) in the open, over the first hall's skylight (%s, %s)" % [grates, lit])


## Umbrage's smithy inside (811 amended (2), the smithy's package, off): one
## stone floor, Umbrage's, held back (SHELVED) till its switch-on; its forge
## hall's forge, anvil, quench trough, grindstone and bench where laid,
## solid; the smith's place by the anvil with npc's trade and face, lore's
## smithy; his tools gone from the wall; the stores' heaps; his bed in his
## room, its head to the east wall; every floor cell reached from the door, which leads out a wall;
## a place's bad "face" warned and left out.
func _test_spots(wilds: Dictionary) -> void:
	print("\n== where people stand and sit (853): level.json spots, read and kept ==")
	var warnings: Array[String] = []
	var floor := {Vector2i(5, 5): true, Vector2i(6, 5): true, Vector2i(5, 6): true, Vector2i(7, 7): true}
	var config := {"spots": [
		{"use": "fire", "cell": [5, 5], "face": [6, 6], "pose": "sit", "town": "store"},
		{"use": "work", "trade": "cook", "cell": [6, 5], "face": [6, 4], "town": "store"},
		{"use": "work", "cell": [5, 6], "face": [5, 7], "town": "store"},
		{"use": "dance", "cell": [7, 7], "face": [7, 8], "town": "store"},
		{"use": "well", "cell": [9, 9], "face": [9, 8], "town": "store"},
		{"use": "square", "cell": [5, 5], "face": [5, 4], "town": "store"},
		{"use": "square", "cell": [7, 7], "face": [7, 5], "town": "store"},
		{"use": "talk", "cell": [7, 7], "face": [7, 6], "pose": "sit", "town": "store", "pair": "a"}]}
	var spots := Level.spots_from(config, warnings, floor)
	_check(spots.size() == 3 and spots[0] == {"use": "fire", "cell": Vector2i(5, 5), "face": Vector2i(6, 6), "pose": "sit", "town": "store", "trade": "", "pair": ""}
		and spots[1]["pose"] == "stand" and spots[1]["trade"] == "cook" and spots[2]["use"] == "talk" and spots[2]["pair"] == "a",
		"a fire seat, the cook's work spot (stood when no pose), a sat talk spot read (%s)" % [spots])
	_check(warnings.size() == 5 and warnings.all(func(line: String) -> bool: return line.begins_with("the spot at (")),
		"five left out, each warning naming its cell: no trade, an unknown use, off the floor, a taken cell, a face two off (%s)" % [warnings])
	var moved := LevelMap.moved_config(config, func(cell: Vector2i) -> Variant: return cell + Vector2i(2, 0) if cell.x < 9 else null)
	_check((moved["spots"] as Array).size() == 7 and moved["spots"][0]["cell"] == [7, 5] and moved["spots"][0]["face"] == [8, 6],
		"a shifted map takes its spots with it, cell and face; one off the map is dropped (%d kept)" % (moved["spots"] as Array).size())
	var kept := Regen.generated_config(config, [{"rect": Rect2i(0, 0, 8, 8)}], 2)
	_check((kept.get("spots", []) as Array).size() == 7 and kept["spots"][0] == config["spots"][0],
		"a regeneration keeps the spots in its anchors as written (%d)" % (kept.get("spots", []) as Array).size())
	_check(wilds.get("spots") is Array, "a level's spots reach Level.load_level (the wilds: %d)" % (wilds.get("spots", []) as Array).size())


## Umbrage's temple furnished (734 amended (7)): its pews in the nave, clear
## of every cell its visitors keep off (Main._temple_keep: its doors', its
## counter's, its respawn's and those about them) and of the way down at
## (199, 199) and its landing; a candle's light by the stair; and no chest
## drawn in the town ("no chests in town"): the depot, shop and locker drawn
## as nothing, the old kit's three gone (_test_removed_to_temple). 734
## amended (8): its altar against the east wall at (199, 201..202), facing
## the nave, solid, two candles burning on its top; the counter drawn as the
## offering table; and from just inside the door, walked in the loaded
## wilds, the counter's front, the way down and its landing still reached.
func _test_temple_furnished(wilds: Dictionary) -> void:
	print("
== Umbrage's temple furnished (734 amended (7)): its pews, its candles, no chest drawn in town ==")
	var temple: Dictionary = {}
	for building: Dictionary in wilds["buildings"]:
		if str(building.get("kind", "")) == "temple" and building.get("rect") is Rect2i and (building["rect"] as Rect2i).has_point(Vector2i(199, 199)):
			temple = building
	_check(not temple.is_empty() and temple["rect"] == Rect2i(190, 199, 10, 6), "the chapel over x 190..199, y 199..204 (%s)" % [temple.get("rect")])
	if temple.is_empty():
		return
	var near: Array[Vector2i] = [Vector2i(198, 201), Vector2i(189, 201)]  # Its counter, its respawn (the place's cell).
	for edge: Variant in Level.entrances(temple):
		if edge is Vector3i:
			near.append_array(Terrain.edge_cells(edge))
	var keep := {}
	for at: Vector2i in near + [Vector2i(199, 199), Vector2i(198, 199)]:  # And the way down, and its landing.
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				keep[at + Vector2i(dx, dy)] = true
	var pews: Array = (wilds["terrain"]["decor"] as Array).filter(func(piece: Dictionary) -> bool: return piece["kind"] == "bench")
	var cells: Array = pews.map(func(piece: Dictionary) -> Vector2i: return piece["cell"])
	cells.sort()
	_check(cells == [Vector2i(193, 200), Vector2i(193, 203), Vector2i(195, 200), Vector2i(195, 203)]
		and pews.all(func(piece: Dictionary) -> bool: return piece["out"] == Vector2i(1, 0)),
		"four pews in the nave, each facing the altar to the east (%s)" % [cells])
	_check(cells.all(func(cell: Vector2i) -> bool: return (temple["rect"] as Rect2i).has_point(cell) and not keep.has(cell) and cell.y != 201 and cell.y != 202),
		"each inside, off the cells its visitors keep off, the way down and its landing, and off the aisle")
	var lit: Array = wilds["terrain"].get("lit_candles", [])
	_check(lit.any(func(entry: Dictionary) -> bool: return entry["at"] == Vector2(199, 200) and entry.get("slot") == "prop.candle_stand" and is_equal_approx(float(entry["top"]), 0.0)),
		"a candle stand burning on the floor beside the way down (868's paragraph) (%s)" % [lit])
	var drawn: Array = []
	for spec: Dictionary in wilds["entities"]:
		if str(spec.get("script", "")) == Level.CHEST and not spec.get("props", {}).has("cache") and str(spec.get("art", "")) != Level.UNDRAWN_ART 				and Rect2i(150, 170, 80, 60).has_point(spec["tile"]) and spec.get("props", {}).get("temple", false) != true:
			drawn.append(spec["tile"])
	_check(drawn.is_empty(), "no chest drawn in Umbrage: its depot, shop and locker drawn as nothing (%s)" % [drawn])
	var undrawn: Array = wilds["entities"].filter(func(spec: Dictionary) -> bool: return str(spec.get("art", "")) == Level.UNDRAWN_ART) 		.map(func(spec: Dictionary) -> Vector2i: return spec["tile"])
	undrawn.sort()
	_check(undrawn == [Vector2i(172, 193), Vector2i(190, 196), Vector2i(193, 196)], "the three drawn as nothing (%s)" % [undrawn])
	var altars: Array = wilds["buildings"].filter(func(building: Dictionary) -> bool: return str(building.get("slot", "")) == "building.temple_altar")
	_check(altars.size() == 1 and altars[0]["rect"] == Rect2i(199, 201, 1, 2) and altars[0]["facing"] == Vector2i(-1, 0)
		and "building.temple_altar" in Level.SOLID and "building.temple_altar" in Level.DOORLESS,
		"the altar against the east wall at (199, 201..202), facing the nave, solid, doorless (%s)" % [altars])
	var on_altar: Array = lit.filter(func(entry: Dictionary) -> bool:
		return is_equal_approx(float(entry["top"]), 1.006) and Rect2(198.5, 200.5, 2, 3).has_point(Vector2(entry["at"]) + Vector2(0.5, 0.5)))
	_check(on_altar.size() == 2,
		"two candles burning on the altar's top, 1.006 m up (%s)" % [lit])
	var counter: Array = wilds["entities"].filter(func(spec: Dictionary) -> bool: return spec["tile"] == Vector2i(198, 201))
	_check(counter.size() == 1 and counter[0].get("art") == "prop.offering_table" and counter[0].get("props", {}).get("temple", false) == true,
		"the temple's counter drawn as the offering table (%s)" % [counter])
	# Level.STANDS_INSIDE: an altar stands only inside a temple, clear of another furnishing.
	var floor_cells: Array[Vector2i] = []
	for y in 12:
		for x in 16:
			floor_cells.append(Vector2i(x, y))
	var said: Array[String] = []
	var laid := Level.buildings_from({"buildings": [{"kind": "temple", "size": "small", "at": [0, 0], "facing": [0, 1]},
		{"slot": "building.temple_altar", "at": [2, 1], "facing": [0, 1]}, {"slot": "building.temple_altar", "at": [3, 1], "facing": [0, 1]},
		{"slot": "building.temple_altar", "at": [10, 1], "facing": [0, 1]}]},
		{"floor": floor_cells, "water": [], "edges": {}, "heights": {}}, said)
	var stood: Array = laid.filter(func(building: Dictionary) -> bool: return building["slot"] == "building.temple_altar").map(func(building: Dictionary) -> Vector2i: return building["cell"])
	_check(stood == [Vector2i(2, 1)] and said.filter(func(line: String) -> bool: return "the floor inside a temple" in line).size() == 2,
		"an altar stands inside a temple; one on another's cell and one outside any temple are left out, said (%s, %s)" % [stood, said])
	_check(_main.load_map("wilds"), "(the wilds loaded, to walk the chapel)")
	_check(not World.is_walkable(Vector2i(199, 201)) and not World.is_walkable(Vector2i(199, 202)), "nobody walks onto the altar")
	var reached := {Vector2i(191, 201): true}
	var queue: Array[Vector2i] = [Vector2i(191, 201)]
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := at + step
			if reached.has(next) or not (temple["rect"] as Rect2i).has_point(next) or not World.is_walkable(next) or World.edge_blocks(at, step, true):
				continue
			reached[next] = true
			queue.append(next)
	_check(reached.has(Vector2i(197, 201)) and reached.has(Vector2i(198, 199)) and reached.has(Vector2i(198, 200)),
		"from inside the door: the counter's front, the way down's landing and the candles' cell beside it reached (%d cells)" % reached.size())
	_main.load_map("test_room")


## The old kit's three chests by Umbrage's stall removed (734 amended (7),
## Relaid.REMOVED "to" "temple"), on a world made by hand: one a single
## player carried, held for them at the temple; the kit's own piece, one two
## players carried and one the item book never had, on the town's shop (the
## coordinator: nothing out of every player's reach); none in the store,
## none held for no one, nothing on the ground, nothing destroyed; a
## count-only line; the next boot does nothing.
func _test_removed_to_temple(wilds: Dictionary) -> void:
	print("\n== The old kit's chests removed, what they held to the temple (734 amended (7)) ==")
	var chest := func(name: String, key: String, slots: Array, uids: Array) -> Dictionary:
		var at := Vector2i(int(key.get_slice(",", 0)), int(key.get_slice(",", 1)))
		return {"script": "res://sim/chest.gd", "shape": "chest", "name": name, "tile": [at.x, at.y], "hp": 1, "stamina": 0,
			"facing": [0, 1], "props": {}, "spawn": 3, "spawn_key": key, "slots": slots, "items": uids}
	var stocked := func(id: String, tile: Array, carriers: Array) -> Dictionary:
		return {"id": id, "made": 1, "at": "", "holder": "", "carriers": carriers,
			"events": [{"kind": "stocked", "step": 1, "zone": "wilds", "tile": tile, "what": "chest"}]}
	var row := func(who: String) -> Dictionary:
		return {"who": who, "name": "", "since": -1, "held": 40, "deeds": {}, "ill": 0.0, "ill_at": 0}
	var done_before := {"relaid/wilds": 774}
	for plan: Dictionary in Relaid.REMOVED:
		if int(plan["decision"]) != 734:
			done_before[Relaid.done_key_of(plan["level"], plan["decision"])] = int(plan["decision"])
	var path: String = preload("res://tests/test_ports.gd").scratch("removed_temple_world.json")
	_check(Snapshot.write(path, {"version": Snapshot.VERSION, "players": [], "remade": done_before,
		"towns": {"wilds/store": {"buildings": {}}}, "stockpile": {"wilds/store": {"resources": {}, "items": [5]}},
		"items": {"next": 30, "book": {"5": {"id": "hammer", "made": 0, "at": "stockpile:wilds/store", "holder": "", "carriers": [], "events": []},
			"21": stocked.call("bow", [205, 208], []), "22": stocked.call("sword", [205, 208], [row.call("player:p1")]),
			"24": stocked.call("dagger", [206, 208], [row.call("player:p1"), row.call("player:p2")])}},
		"zones": {"wilds": {"tick": 9, "entities": [chest.call("Chest5", "205,208", ["bow", "sword", "", ""], [21, 22, 0, 0]),
			chest.call("Chest6", "206,208", ["dagger", "arrows", "", ""], [24, 0, 0, 0]), chest.call("Chest7", "206,207", ["", "", "", ""], [0, 0, 0, 0])],
			"respawns": [], "ground": [], "records": []}}}), "(the old world written)")
	var snapshot := Snapshot.load(path)
	var done: Dictionary = snapshot.get("remade", {})
	for boot in 2:
		var lines := Relaid.move(snapshot, done, func(level: String) -> Dictionary: return wilds if level == "wilds" else Level.load_level(level))
		var ours: Array = lines.filter(func(line: String) -> bool: return line.begins_with("[level] removed in wilds (734)"))
		if boot == 1:
			_check(ours.is_empty() and done.get(Relaid.done_key_of("wilds", 734)) == 734, "the next boot does nothing: done under its own key (%s)" % [lines])
			break
		_check(ours == ["[level] removed in wilds (734): 3 saved entities removed, 2 holding things, 1 kit things to the shop, 1 players' things held for 1 owners at the temple, 2 of no known owner to the shop, 0 laid on the ground"],
			"one count-only line, no names, ids or uids (%s)" % [lines])
		var book: Dictionary = snapshot["items"]["book"]
		var held: Dictionary = snapshot["towns"]["wilds/store"].get("held_for", {})
		_check(snapshot["zones"]["wilds"]["entities"].is_empty() and (snapshot["zones"]["wilds"]["ground"] as Array).is_empty(),
			"the three gone, nothing laid on the ground")
		var store: Dictionary = snapshot["stockpile"]["wilds/store"]
		var shelf: Array = (store.get("shop", []) as Array).map(func(uid: Variant) -> int: return int(uid))
		_check((store["items"] as Array).map(func(uid: Variant) -> int: return int(uid)) == [5], "nothing from the old chests in the town's store")
		_check(shelf.size() == 3 and shelf[0] == 21 and shelf[1] == 24 and book.has(str(shelf[2])) and book[str(shelf[2])]["id"] == "arrows"
			and int(snapshot["items"]["next"]) > shelf[2]
			and shelf.all(func(uid: int) -> bool: return book[str(uid)]["at"] == Stockpile.shop_holder("wilds/store") and not book[str(uid)].has(ItemBook.RETURNED)),
			"on the town's shop: the kit's own bow, the dagger two carried, the arrows the book never had (given an instance) (%s)" % [shelf])
		_check(held.get("player:p1") == [22] and book["22"]["at"] == "temple:wilds/store" and book["22"].get(ItemBook.RETURNED) == ItemBook.FROM_OLD_CHESTS,
			"the sword one player carried, held for them at the temple, marked from the old chests (%s)" % [held])
		_check(held.keys() == ["player:p1"], "nothing held for no one (%s)" % [held])
		var stock := Stockpile.new(snapshot["stockpile"], Callable(), ItemBook.from_dict(snapshot["items"]))
		_check(stock.shop("wilds/store").size() == 3 and stock.items("wilds/store").size() == 1 and stock.items("wilds/store")[0] == 5, "the shop loads as the game loads it (%s)" % [stock.shop("wilds/store")])
		_check(ItemBook.from_dict(snapshot["items"]).returned_from(22) == ItemBook.FROM_OLD_CHESTS, "the mark kept through the book's load")


func _test_smithy_inside() -> void:
	print("
== Umbrage's smithy inside (811 amended (2)): held back, furnished, the smith's place and bed ==")
	var level := Level.load_level("umbrage_smithy")
	_check(not level.is_empty() and (level["warnings"] as Array).is_empty() and level["town"] == "wilds/store"
		and level["storeys"] == ["umbrage_smithy"] and not level["terrain"]["outdoor"],
		"umbrage_smithy parses clean, indoors, Umbrage's, one storey (%s)" % [level.get("warnings")])
	_check_shelved("umbrage_smithy", "wilds", Vector2i(215, 200))
	var floor := {}
	for cell: Vector2i in level["terrain"]["floor"]:
		floor[cell] = true
	var pieces := {}
	for building: Dictionary in level["buildings"]:
		pieces[building["rect"]] = building["slot"]
	var want := {Rect2i(1, 0, 2, 1): "building.smithy_forge", Rect2i(2, 2, 1, 1): "prop.anvil", Rect2i(4, 0, 1, 1): "building.quench_trough",
		Rect2i(0, 4, 1, 1): "building.grindstone", Rect2i(4, 4, 2, 1): "building.smith_bench"}
	var solid := want.keys().all(func(rect: Rect2i) -> bool:
		return Level.rect_cells(rect).all(func(cell: Vector2i) -> bool: return not floor.has(cell)))
	_check(pieces == want and solid, "the forge hall's forge, anvil, trough, grindstone and bench where laid, solid (%s)" % [pieces])
	var smithy: Dictionary = level["places"].get("smithy", {})
	_check(smithy.get("cell") == Vector2i(3, 2) and smithy.get("kind") == "smithy" and smithy.get("trade") == "smith"
		and smithy.get("face") == Vector2i(2, 2) and smithy.get("lore_id") == "smithy" and smithy.get("name") == "the smithy"
		and floor.has(Vector2i(3, 2)) and Lore.entries().has("smithy"),
		"the smith's place by the anvil, facing it, his trade smith, lore's smithy (%s)" % [smithy])
	var decor: Array = (level["terrain"]["decor"] as Array).map(func(piece: Dictionary) -> String:
		return "%s %d" % [piece["kind"], int(piece.get("variant", 1))])
	_check(decor == ["tool_wall 2", "heap_ore 1", "heap_charcoal 1", "stack_iron_bars 1"],
		"his tools gone from the wall (variant 2) and the stores' ore, charcoal and bars, drawn only (%s)" % [decor])
	var beds: Array = Level.storeys_of("umbrage_smithy")["beds"]
	_check(beds.size() == 1 and beds[0]["cells"] == [Vector2i(9, 5), Vector2i(8, 5)] and beds[0]["head"] == Vector2i(1, 0),
		"the smith's bed in his room at (9, 5), its head to the east wall (%s)" % [beds])
	var rooms: Dictionary = Level.template_config("umbrage_smithy").get("rooms", {})
	var named: Array = rooms.values().map(func(room: Dictionary) -> String: return str(room.get("name", "")))
	named.sort()
	_check(named == ["Forge", "Smith's room", "Stores"], "its rooms named in voice's words (%s)" % [named])
	var edges: Dictionary = level["terrain"]["edges"]
	var from: Vector2i = level["spawn_points"]["from_wilds"]
	var seen := {from: true}
	var todo: Array[Vector2i] = [from]
	while not todo.is_empty():
		var cell: Vector2i = todo.pop_back()
		for way: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var next := cell + way
			if floor.has(next) and not seen.has(next) and int(edges.get(Terrain.edge_key(cell, way), Terrain.Edge.OPEN)) != Terrain.Edge.WALL:
				seen[next] = true
				todo.append(next)
	var outs: Array = (level["links"] as Array).filter(func(link: Dictionary) -> bool: return link["to_map"] == "wilds")
	_check(seen.size() == floor.size() and from == Vector2i(2, 8) and outs.size() == 2 and outs.all(func(link: Dictionary) -> bool:
		return int(edges.get(Terrain.edge_key(link["tile"], Vector2i(0, -1)), Terrain.Edge.OPEN)) == Terrain.Edge.DOOR),
		"every floor cell reached from just inside its door (%d of %d), its way out through the door in its south wall" % [seen.size(), floor.size()])
	var warnings: Array[String] = []
	var places := Level.places_from({"places": {"a": {"at": [1, 1], "face": "north"}, "b": {"at": [2, 2]}}}, warnings)
	_check(not places["a"].has("face") and not places["b"].has("face") and not places["b"].has("trade") and warnings.size() == 1,
		"a place's bad face warned and left out, none where unsaid (%s)" % [warnings])


## Umbrage's watch posts, tavern, square fire and store lamp (771 amended
## (4), 772 amended, 774; npc's and environment's readers): read by their
## Level calls, on floor, the tavern the town's inn with its counter, seats
## and hearth clear of its beds; a malformed shape warned and left out.
func _test_town_places(wilds: Dictionary) -> void:
	print("
== Umbrage's posts, tavern, fire and lamp, as npc and environment read them ==")
	var floor := {}
	for cell: Vector2i in wilds["terrain"]["floor"]:
		floor[cell] = true
	var posts := Level.posts_of(wilds)
	var ids: Array = (posts.get("wilds/store", []) as Array).map(func(post: Dictionary) -> String: return post["id"])
	_check(posts.keys() == ["wilds/store"] and ids == ["post_barrow", "post_crossroads", "post_healer", "post_hill_road", "post_smithy", "post_woodlot"],
		"six posts, one per spoke, the town's (%s)" % [posts.keys()])
	for post: Dictionary in posts.get("wilds/store", []):
		var rect: Rect2i = post["rect"]
		var clear := true
		for x in range(rect.position.x, rect.end.x):
			for y in range(rect.position.y, rect.end.y):
				clear = clear and floor.has(Vector2i(x, y))
		_check(clear and rect.has_point(post["brazier"]) and not str(post["name"]).is_empty(), "%s: its 3 x 3 on floor, its brazier in it (%s)" % [post["id"], rect])
	_check(Level.posts_of(Level.load_level("forest")).is_empty(), "a level with no posts: {}")
	# The inn a shell (the tavern zone): its inside the tavern's own levels,
	# no beds nor tavern of its own in the wilds.
	var inn: Array = (wilds["buildings"] as Array).filter(func(building: Dictionary) -> bool: return str(building.get("use", "")) == "inn")
	_check(inn.size() == 1 and str(inn[0].get("inside", "")) == "umbrage_tavern" and str(inn[0].get("town", "")) == "store"
		and Level.beds_in(inn[0], wilds["terrain"]).is_empty() and not inn[0].has("beds") and Level.tavern_of(wilds).is_empty(),
		"the inn a shell: its inside umbrage_tavern, no beds nor tavern in the wilds (%s)" % [Level.tavern_of(wilds).keys()])
	var fires := Level.fires_of(wilds)
	_check(fires.size() == 1 and fires[0]["id"] == "square_fire" and fires[0]["cell"] == Vector2i(194, 211) and fires[0]["town"] == "wilds/store"
		and (wilds["terrain"]["fire"] as Array).has(Vector2i(194, 211)) and fires[0]["seats"].size() == 8
		and (fires[0]["seats"] as Array).all(func(cell: Vector2i) -> bool: return floor.has(cell)), "the square's fire: a fire cell, eight seats on floor round it")
	_check(wilds["places"]["store"].get("lamp") == Vector2i(191, 194) and floor.has(Vector2i(191, 194)), "the store's lamp, on floor")
	var warnings: Array[String] = []
	var odd := Level.places_from({"places": {"a": {"at": [1, 1], "kind": "post", "rect": [1, 1, 0, 3], "brazier": "x", "seats": [[1, 1], 2]}}}, warnings)
	_check(not odd["a"].has("rect") and not odd["a"].has("brazier") and not odd["a"].has("seats") and warnings.size() == 3, "a malformed rect, cell or seats: warned, left out (%s)" % [warnings])


## A 12 x 10 level [param level_name]: open floor, a lair anchor
## (2, 4, 8, 5) walled along its north edge with one door at (5, 4).
func _register_hall(level_name: String) -> void:
	var rows: Array[String] = []
	for py in 10 * 2 - 1:
		var row := ""
		for px in 12 * 2 - 1:
			var floor_here := px % 2 == 0 and py % 2 == 0
			var north_wall := py == 7 and px % 2 == 0 and px / 2 >= 2 and px / 2 <= 9
			row += ("+" if px / 2 == 5 else "#") if north_wall else ("." if floor_here else " ")
		rows.append(row)
	Level.register(level_name, Level.image_from_rows(rows, {Vector2i(5, 1): "start"}), null,
		{"regenerate": {"anchors": [{"rect": [2, 4, 8, 5], "name": "lair"}]}})


## A 12 x 10 level [param level_name]: open floor walled across between
## y 3 and 4 from x 2 to 9, with doors side by side at x 5 and 6 (and a
## third, lone one at x 8, locked when [param locked]);
## [param generated] gives it a regenerate block.
func _register_pair(level_name: String, generated: bool) -> void:
	var rows: Array[String] = []
	for py in 10 * 2 - 1:
		var row := ""
		for px in 12 * 2 - 1:
			var floor_here := px % 2 == 0 and py % 2 == 0
			var north_wall := py == 7 and px % 2 == 0 and px / 2 >= 2 and px / 2 <= 9
			row += ("+" if px / 2 in [5, 6, 8] else "#") if north_wall else ("." if floor_here else " ")
		rows.append(row)
	var config := {"regenerate": {"anchors": [{"rect": [0, 4, 12, 6], "name": "below"}]}} if generated else {}
	Level.register(level_name, Level.image_from_rows(rows, {Vector2i(5, 4): "start"}), null, config)


## The robbers' clear (714, dungeon's side (4)): in the robbers' barrow the
## hidden niche gives and its draft is felt only once none of them stands,
## dead or fled; the first time, it latches for the generation (saved), and
## robbers come back do not undo it.
func _test_robbers_latch() -> void:
	print("
== the robbers' clear (714): the hidden way only once the band is down, latched for the generation ==")
	if World.economy == null:
		_check(false, "no economy to read the robbers from")
		return
	var rules: Dictionary = World.economy.rules.get("robbers", {}).duplicate(true)
	World.economy.rules["robbers"] = rules.merged({"barrow": "lt_niche"}, true)
	_register_niche("lt_niche")
	_main.load_map("lt_niche")
	var kept: Variant = _main._regen.get("lt_niche")
	_main._regen["lt_niche"] = {"generation": 1, "at_step": 0}
	var player := _player()
	var key := Terrain.edge_key(Vector2i(6, 1), Vector2i(0, -1))
	var door := World.door_on(key)
	var spawn_robber := func(at: Vector2i) -> GridEntity:
		return _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "kind": "robber", "name": "Robber%d" % at.x, "tile": _main._nearest_free(at)})
	var robber: GridEntity = spawn_robber.call(Vector2i(1, 4))
	_check(robber != null and not _main.robbers_cleared("lt_niche") and _main.robbers_cleared("test_room"),
		"a robber stands in their barrow: not cleared; another level has none to clear")
	var heard: Array[String] = []
	var hear := func(kind: String, data: Dictionary) -> void:
		if kind == "party":
			heard.append(str(data.get("text", "")))
	Net.message_received.connect(hear)
	_main._tell_draft(player, Vector2i(3, 3))
	_put(player, Vector2i(6, 1))
	for i in 6:
		_hold_free(player, Vector2(0, -1), 1)
	_check(not door.open and door.lock == Main.HIDDEN_LOCK and _main.party_log.last(1) == ["Only the dead lie here."]
		and not heard.any(func(text: String) -> bool: return "draft" in text),
		"with one up, the hidden niche is any niche: shut, \"Only the dead lie here.\", no draft (%s)" % [_main.party_log.last(1)])
	World.damage(robber, 999)
	_check(bool(_main._regen["lt_niche"].get("robbers_down", false)) and _main.robbers_cleared("lt_niche"),
		"the last one falls: the clear latches for the generation (%s)" % [_main._regen["lt_niche"]])
	var back: GridEntity = spawn_robber.call(Vector2i(2, 4))
	_check(back != null and _main.robbers_cleared("lt_niche") and Regen.states_from(JSON.parse_string(JSON.stringify(_main._regen)))["lt_niche"].get("robbers_down") == true,
		"one come back after does not undo it, and a save keeps it")
	_main._draft_told.erase("%s@lt_niche" % player.player_id)  # _test_hidden_niche's, told already this generation.
	_main._tell_draft(player, Vector2i(3, 3))
	_check(not heard.has("You feel a cool draught coming from one of the niches.") and not _main.way_revealed(player.player_id, "lt_niche"),
		"cleared, but the way is not revealed to them (747: the fallen knight's quest not done): no draft (%s)" % [heard])
	_main.mark_player(player.player_id, Main.QUEST_DONE)
	_main._tell_draft(player, Vector2i(3, 3))
	_check(heard.has("You feel a cool draught coming from one of the niches."), "his quest done: now the draft is felt (%s)" % [heard])
	_put(player, Vector2i(6, 1))
	for i in 10:
		_hold_free(player, Vector2(0, -1), 1)
		if door.open:
			break
	_check(door.open, "and the hidden niche gives")
	# Fled out (702: despawned at a way out) counts as down too.
	_main._regen["lt_niche"] = {"generation": 2, "at_step": 0}
	_check(not _main.robbers_cleared("lt_niche"), "a new generation: the one come back stands, not cleared")
	World.despawn(back)
	_check(bool(_main._regen["lt_niche"].get("robbers_down", false)), "he gets away out of the barrow: down, latched")
	# The coordinator (714 (4)): with a 5-minute rise, each of the band fallen
	# once this generation is clear, though one has risen again.
	_check(_main.band_ids("barrow") == ["brand", "crake", "mott", "nabb", "wicket", "fenn", "rook", "sedge", "tull"],
		"the barrow's band, Brand and the eight (%s)" % [_main.band_ids("barrow")])
	_main._regen["lt_niche"] = {"generation": 3, "at_step": 0}
	var named_one := func(id: String, at: Vector2i) -> Monster:
		var monster := spawn_robber.call(at) as Monster
		if monster != null:
			monster.named_id = id
		return monster
	var t1: Monster = named_one.call("t1", Vector2i(1, 4))
	var t2: Monster = named_one.call("t2", Vector2i(3, 4))
	World.damage(t1, 999)
	var risen: Monster = named_one.call("t1", Vector2i(1, 4))
	_check(_main._regen["lt_niche"].get("robbers_fallen", []) == ["t1"] and not _main._band_fallen("lt_niche", ["t1", "t2"])
		and not bool(_main._regen["lt_niche"].get("robbers_down", false)),
		"one of two fallen, risen again: kept as fallen, not yet clear (%s)" % [_main._regen["lt_niche"]])
	World.damage(t2, 999)
	_check(_main._band_fallen("lt_niche", ["t1", "t2"]) and risen != null and risen.hp > 0
		and (Regen.states_from(JSON.parse_string(JSON.stringify(_main._regen)))["lt_niche"].get("robbers_fallen", []) as Array) == ["t1", "t2"],
		"the other falls: each fallen once though the first stands again, and the fallen saved (%s)" % [_main._regen["lt_niche"]])
	World.despawn(risen)
	_main.mark_player(player.player_id, Main.QUEST_DONE, false)
	Net.message_received.disconnect(hear)
	World.economy.rules["robbers"] = rules
	if kept == null:
		_main._regen.erase("lt_niche")
	else:
		_main._regen["lt_niche"] = kept
	_main.load_map("test_room")
	Level.unregister("lt_niche")


## The generated halls' doors two edges wide (725): the pair side by side
## swings as one (World.door_partner, the client's Level.door_pairs), the
## lone third its own; a level that does not regenerate keeps 403's rule,
## each edge its own door.
func _test_double_doors() -> void:
	print("
== the generated halls' double doors swing as one (725) ==")
	var pairs := Level.door_pairs([Vector3i(5, 3, 1), Vector3i(6, 3, 1), Vector3i(7, 3, 1), Vector3i(9, 3, 1), Vector3i(10, 3, 1)], func(_key: Vector3i) -> bool: return true)
	_check(pairs == {Vector3i(5, 3, 1): Vector3i(6, 3, 1), Vector3i(9, 3, 1): Vector3i(10, 3, 1)},
		"pairs two at a time from a run's start, a third left on its own (%s)" % [pairs])
	for generated: bool in [true, false]:
		var name := "lt_pair" if generated else "lt_pair_plain"
		_register_pair(name, generated)
		_main.load_map(name)
		var player := _player()
		var left := World.door_on(Terrain.edge_key(Vector2i(5, 4), Vector2i(0, -1)))
		var right := World.door_on(Terrain.edge_key(Vector2i(6, 4), Vector2i(0, -1)))
		var lone := World.door_on(Terrain.edge_key(Vector2i(8, 4), Vector2i(0, -1)))
		player.next_move_tick = 0
		var opened := World.try_toggle_door(player, left.key)
		if generated:
			_check(opened and left.open and right.open and not lone.open and World.door_partner(left) == right and World.door_partner(right) == left and World.door_partner(lone) == null,
				"in a generated hall the pair opens as one, the lone door stays shut (%s %s %s)" % [left.open, right.open, lone.open])
			player.next_move_tick = 0
			World.try_toggle_door(player, left.key)
			_check(not left.open and not right.open, "and shuts as one")
		else:
			_check(opened and left.open and not right.open and World.door_partner(left) == null,
				"a level that does not regenerate: each edge its own door (403)")
		_main.load_map("test_room")
		Level.unregister(name)


## An 8 x 6 level [param level_name]: a room x 1..6, y 1..4 in the rock,
## three niches in its north wall at (2, 1), (4, 1) and (6, 1), the last the
## hidden one with its alcove at (6, 0) behind a door edge and the stair
## link in it.
func _register_niche(level_name: String) -> void:
	var rows: Array[String] = []
	for py in 6 * 2 - 1:
		var row := ""
		for px in 8 * 2 - 1:
			var cell := Vector2i(px / 2, py / 2)
			var floor_here := px % 2 == 0 and py % 2 == 0 and (cell.x >= 1 and cell.x <= 6 and cell.y >= 1 and cell.y <= 4 or cell == Vector2i(6, 0))
			row += "+" if px == 12 and py == 1 else ("." if floor_here else " ")
		rows.append(row)
	Level.register(level_name, Level.image_from_rows(rows, {Vector2i(3, 3): "start", Vector2i(6, 0): "link"}), null,
		{"niches": [[2, 1, 0, -1, "a", 1], [4, 1, 0, -1, "c", 2], [6, 1, 0, -1, "hidden", 1]],
			"links": [{"at": [6, 0], "to_map": "test_room", "to_spawn": "", "hidden": true}],
			"spawn_points": {"from_below": [6, 1]},
			"regenerate": {"generator": "labyrinth", "anchors": [{"name": "hall", "rect": [0, 0, 8, 6]}], "entrance": "hall"}})


## The hidden door (608): the first hall's one true niche is a door spawned
## locked and stone; a step into any niche presses on it ("Only the dead
## lie here." once a stand), the true one gives, the stair behind it is
## taken, and a climb from below pushes it open from behind.
func _test_hidden_niche() -> void:
	print("\n== the hidden door (608): niches pressed, the true one found, the stair behind it, opened from below; the draft felt (608 amended) ==")
	_register_niche("lt_niche")
	var parsed := Level.load_level("lt_niche")
	_check(parsed["warnings"].is_empty() and parsed["terrain"]["niches"].size() == 3 and parsed["links"][0]["hidden"],
		"the level parses: three niches on the north wall, the stair link hidden (%s)" % [parsed["warnings"]])
	_main.load_map("lt_niche")
	var player := _player()
	var key := Terrain.edge_key(Vector2i(6, 1), Vector2i(0, -1))
	var door := World.door_on(key)
	_check(door != null and not door.open and door.lock == "hidden_niche" and door.body_material == GridEntity.BodyMaterial.STONE
		and World.niche_edges.size() == 3 and World.niche_edges.get(key) == "hidden" and World.niche_edges.get(Terrain.edge_key(Vector2i(2, 1), Vector2i(0, -1))) == "a",
		"the hidden niche's door spawns shut, locked with a key nobody holds and stone; World knows the three niche edges (%s)" % [World.niche_edges])
	# 608 amended: the marker every clue reads, the hall, and the draft line
	# to the player alone on their first step in the hall, once a generation,
	# while the door is shut.
	var heard: Array[String] = []
	var hear := func(kind: String, data: Dictionary) -> void:
		if kind == "party":
			heard.append(str(data.get("text", "")))
	Net.message_received.connect(hear)
	var draft := "You feel a cool draught coming from one of the niches."
	_check(_main.hall_rect("lt_niche") == Rect2i(0, 0, 8, 6) and _main.hall_rect("test_room") == Rect2i(),
		"the hall is the entrance anchor's rect, none for a level that does not regenerate (%s)" % [_main.hall_rect("lt_niche")])
	_check(World.hidden_niche() == {"cell": Vector2i(6, 1), "edge": key, "open": false},
		"World.hidden_niche is the marker: its floor cell, its door's edge, shut (%s)" % [World.hidden_niche()])
	_hold_free(player, Vector2(1, 0), 3)
	_check(player.tile == Vector2i(4, 3) and heard.count(draft) == 1,
		"the first cell crossed in the hall says the draft line to the player alone (%s)" % [heard])
	_hold_free(player, Vector2(1, 0), 3)
	_check(player.tile == Vector2i(5, 3) and heard.count(draft) == 1, "the next says it no more")
	_put(player, Vector2i(2, 1))
	_hold_free(player, Vector2(0, -1), 6)
	var line := "Only the dead lie here."
	_check(player.tile == Vector2i(2, 1) and _main.party_log.last(1) == [line] and heard.count(line) == 1,
		"pressing into a plain niche is stopped and says the line, to the player's screen (%s)" % [heard])
	var told: Array = _main.party_log.last(3)
	_hold_free(player, Vector2(0, -1), 6)
	_check(_main.party_log.last(3) == told, "pressing on at it says nothing more")
	_put(player, Vector2i(4, 1))
	_hold_free(player, Vector2(0, -1), 6)
	_check(_main.party_log.last(2) == [line, line] and heard.count(line) == 2, "another niche says it again (%s)" % [heard])
	_put(player, Vector2i(6, 1))
	_check(not World.may_open(player, door) and not World.try_toggle_door(player, key) and not door.open, "no walk opens the hidden niche's door and E rattles it")
	for i in 10:
		_hold_free(player, Vector2(0, -1), 1)
		if door.open:
			break
	_check(player.tile == Vector2i(6, 1) and door.open and door.lock == "hidden_niche"
		and _main.party_log.last(1) == ["The slab swings aside: a stair goes down into the dark."] and heard.has("The slab swings aside: a stair goes down into the dark."),
		"pressing into the hidden niche finds it, said on the finder's screen too: the door open, its lock kept (747: shut, it gives only to those it is revealed to), and said (%s)" % [_main.party_log.last(1)])
	_check(World.hidden_niche()["open"], "the marker says open")
	# 608 amended (2): the finder stands while the slab gives way, pressing
	# on or not; the stair behind is not taken through the shut slab.
	_check(World.free_held(player), "the finder is held while the slab gives way")
	_hold_free(player, Vector2(0, -1), 5)
	_check(player.tile == Vector2i(6, 1) and World.zone.name == "lt_niche", "pressing on, held: still before it, the stair not yet taken (%s)" % [player.tile])
	# 608 amended (2): a shut, locked door before a link shuts the way: the
	# press finds the niche (again, here: held anew), it never takes the
	# stair through the slab.
	door.open = false
	door.lock = "hidden_niche"
	var taken: Array = []
	var on_bump := func(by: GridEntity, at: Vector2i) -> void: taken.append(at)
	World.link_bumped.connect(on_bump)
	World._step_refused(player, Vector2i(0, -1))
	_check(taken.is_empty(), "a step at the link through the locked slab is no bump on the link (%s)" % [taken])
	# The same through a free body's press (_free_pressed), free walk on.
	_hold_free(player, Vector2(0, 0), Main.NICHE_FOUND_HOLD)
	door.open = false
	door.lock = "hidden_niche"
	for i in 10:
		_hold_free(player, Vector2(0, -1), 1)
		if door.open:
			break
	World.link_bumped.disconnect(on_bump)
	_check(World.free_body(player) and taken.is_empty() and door.open and player.tile == Vector2i(6, 1) and World.zone.name == "lt_niche",
		"pressed with free walk on: the slab found, the stair behind it not taken through it (%s, %s)" % [taken, player.tile])
	_check(door.open and door.lock == "hidden_niche", "the press found it again")
	_hold_free(player, Vector2(0, 0), Main.NICHE_FOUND_HOLD)
	# 608 amended: found, no draft, not even in a new generation; laid again
	# with the door shut, it is felt again.
	_main._regen["lt_niche"] = {"generation": 1, "at_step": 0}
	_hold_free(player, Vector2(-1, 0), 4)
	_check(player.tile == Vector2i(5, 1) and heard.count(draft) == 1,
		"found, a cell crossed in the hall feels no draft (%s)" % [heard])
	World.hold_door(door, true, "hidden_niche")
	_hold_free(player, Vector2(1, 0), 4)
	_check(not door.open and player.tile == Vector2i(6, 1) and heard.count(draft) == 2,
		"laid again with the door shut, the draft is felt once more (%s)" % [heard])
	Net.message_received.disconnect(hear)
	World.hold_door(door, false, "hidden_niche")
	door.open = true
	_hold_free(player, Vector2(0, -1), 6)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(World.zone.name == "test_room" or World.peer_zone.get(Net.local_id, "") == "test_room", "the alcove behind it is walked into and its stair taken (%s)" % [World.peer_zone.get(Net.local_id, "")])
	# Shut and locked again (a restart lays the door locked): a climb from
	# below pushes it open from behind.
	var there: Zone = World.zones["lt_niche"]
	var was := World.enter(there)
	World.hold_door(door, true, "hidden_niche")
	World.enter(was)
	_check(not door.open and door.lock == "hidden_niche", "locked again")
	_main.travel(Net.local_id, "lt_niche", "from_below")
	_check(door.open and door.lock.is_empty() and _player().tile == Vector2i(6, 1) and _main.party_log.last(2)[0] == "The slab swings aside from behind."
		and _heard.has("The slab swings aside from behind."),
		"come up from below, the slab is pushed open from behind and said, on their screen too; the player stands before it (%s)" % [_main.party_log.last(2)])
	# 672 amended, dungeon's side: the world's barrow is every player's,
	# laid again by the console's zone reset, the slab shut and locked.
	_main.admin_command("zone reset lt_niche")
	var laid := World.door_on(key)
	_check(laid != null and not laid.open and laid.lock == "hidden_niche", "zone reset lays the found niche shut and locked again")
	_main.load_map("test_room")
	_main._regen.erase("lt_niche")
	Level.unregister("lt_niche")


func _test_barrow_level() -> void:
	print("\n== levels/barrow, barrow_deep (decisions 542, 580, 666): the barrow in two depths, the Hall off the Ossuary; a test run never writes them ==")
	var barrow := Level.load_level("barrow")
	var deep := Level.load_level("barrow_deep")
	_check(barrow["display_name"] == "The Crypt of the Fallen" and barrow["size"] == Vector2i(80, 60) and barrow["warnings"].is_empty(),
		"The Crypt of the Fallen, 80 x 60 (580), parses with no warning (%s)" % [barrow["warnings"]])
	_check(deep["display_name"] == "The Ossuary" and deep["size"] == Vector2i(100, 80) and deep["warnings"].is_empty()
		and not Level.exists("barrow_lair") and not Level.overlaid("barrow_lair") and Level.RETIRED.get("barrow_lair") == ["barrow_deep", Vector2i(49, 2)],
		"the Ossuary, 100 x 80, parses with no warning; the dark below is retired, its players bound for the Ossuary's stair foot (666; %s)" % [deep["warnings"]])
	# Moss and webs (647): the templates' own, the rest rolled by a generation.
	var corner_webs := func(level: Dictionary) -> int:
		return level["terrain"]["decor"].filter(func(d: Dictionary) -> bool: return d["kind"] == "web_corner").size()
	# 806 amended (3): and the light shaft under the temple yard's grate, its skylight.
	var shafts: Array = barrow["terrain"]["decor"].filter(func(d: Dictionary) -> bool: return d["kind"] == "light_shaft")
	var skylights: Array = barrow["terrain"]["skylights"]
	# And the band's bedding in its camp (870; the coordinator's ruling, combat's ask: the kits lie by it).
	var bedding: Array = barrow["terrain"]["decor"].filter(func(d: Dictionary) -> bool: return d["kind"] == "bedroll")
	_check(barrow["terrain"]["decor"].size() == 6 and bedding.size() == 2 and corner_webs.call(barrow) == 2 and shafts.size() == 1 and skylights.size() == 1
			and shafts[0]["cell"] == Vector2i(46, 13) and skylights[0]["at"] == Vector2i(46, 13)
			and deep["terrain"]["decor"].size() == 30 and corner_webs.call(deep) == 4,
		"the first hall holds two cobwebbed corners, a strip of moss and the light shaft under its skylight, the Ossuary's Hall of Fallen Souls its moss and four webbed corners (%d, %s, %d)" % [barrow["terrain"]["decor"].size(), skylights, deep["terrain"]["decor"].size()])
	_check(Regen.marked("barrow") and Regen.config_of("barrow")["anchors"].size() == 5 and int(Regen.config_of("barrow").get("layer", 0)) == 1
		and Regen.marked("barrow_deep") and Regen.config_of("barrow_deep")["anchors"].size() == 2 and int(Regen.config_of("barrow_deep").get("layer", 0)) == 2
		and Regen.config_of("barrow_deep")["anchors"][1]["name"] == "lair" and Regen.config_of("barrow_deep").get("monsters") == {"skeleton": 6, "skeleton_guard": 3}
		and int(Regen.config_of("barrow").get("ways", 0)) == 5 and int(Regen.config_of("barrow_deep").get("ways", 0)) == 5,
		"both depths are marked to regenerate in the barrow style, layers 1 and 2, every way five wide; the Ossuary's far anchor the lair, its dead three grave guards each leading two skeletons (823, dungeon's side)")
	var kinds := {}
	var grave_marked := {}
	var guards_marked := 0
	for level: Dictionary in [barrow, deep]:
		for spec: Dictionary in level["entities"]:
			var kind := str(spec.get("kind", spec["name"].rstrip("0123456789").to_lower()))
			kinds[kind] = int(kinds.get(kind, 0)) + 1
			# Grave goods (555, dungeon's side): the level key marks the altar,
			# the guards and the draugr; the runner's pack, a robber's, is exempt.
			var marked: bool = spec.get("props", {}).get("grave", false) == true
			grave_marked[spec["name"]] = marked
			if kind == "skeleton_guard" and marked:
				guards_marked += 1
	_check(kinds.get("skeleton_guard", 0) == 2 and kinds.get("draugr", 0) == 1 and kinds.get("offering stone", 0) == 1 and kinds.get("runner's pack", 0) == 1
		and kinds.get("robbers' chest", 0) == 1 and kinds.get("astral_knight", 0) == 1
		and kinds.get("robbers' bundle", 0) == 1 and barrow["places"].has("niche") and barrow["entities"].size() == 7 and deep["entities"].size() == 2 and kinds.get("chest", 0) == 1,
		"the altar with its two guards and the fallen knight (747), Pip's niche, the Runner's pack and the robbers' chest (742), the Robbers' bundle by their bedding (870) on the first layer, the draugr in his hall in the Ossuary and its chest by the throne (%s)" % [kinds])
	_check(grave_marked.get("Offering stone", false) and grave_marked.get("Draugr", false) and not grave_marked.get("Runner's pack", true) and not grave_marked.get("Robbers' bundle", true) and guards_marked == 2,
		"grave_goods marks the altar, the guards and the draugr as grave goods, the runner's pack exempt (%s)" % [grave_marked])
	_check(barrow["links"].size() == 3 and barrow["links"][0]["to_map"] == "wilds" and barrow["links"][0]["to_spawn"] == "from_crypt"
		and barrow["links"][1]["to_map"] == "barrow_deep" and barrow["links"][1]["to_spawn"] == "from_above"
		and barrow["links"][2]["tile"] == Vector2i(31, 52) and barrow["links"][2]["to_map"] == "wilds" and barrow["links"][2]["to_spawn"] == "from_barrow"
		and deep["links"].size() == 1 and deep["links"][0]["to_map"] == "barrow" and deep["links"][0]["to_spawn"] == "from_below"
		and not deep["spawn_points"].has("from_temple") and barrow["spawn_points"].has("from_deep") and barrow["terrain"]["floor"].has(Vector2i(30, 8))
		and not deep["terrain"]["floor"].has(Vector2i(49, 77)),
		"the stairs link the depths both ways; 832 switched on: the First Hall's stair up to the chapel, the camp's breach out by the mound; 896 switched on: no shortcut either way, (30,8) plain floor, (49,77) rock, from_temple gone, from_deep kept for the throne's sitter (%s)" % [barrow["links"]])
	# The rooms named on entering (666, ui's 665 card).
	var barrow_rooms: Dictionary = Level.template_config("barrow").get("rooms", {})
	var deep_rooms: Dictionary = Level.template_config("barrow_deep").get("rooms", {})
	_check(barrow_rooms.keys() == ["entrance", "altar", "camp"] and str(barrow_rooms["entrance"]["name"]) == "The First Hall"
		and deep_rooms.keys() == ["entrance", "lair"] and str(deep_rooms["lair"]["name"]) == "The Hall of Fallen Souls" and Level.town_wall_rect(deep_rooms["lair"]) == Rect2i(34, 56, 32, 22)
		and str(deep_rooms["entrance"]["name"]) == "The Charnel Vault" and Level.town_wall_rect(deep_rooms["entrance"]) == Rect2i(46, 1, 8, 6),
		"the first hall, the altar room and the camp are named on the barrow, the Charnel Vault (714) and the Hall of Fallen Souls on the Ossuary, each on its anchor (%s %s)" % [barrow_rooms.keys(), deep_rooms.keys()])
	# The hidden door (608): the template's stair lies behind the south-east
	# niche's door, the link hidden; the 14 niches read.
	var niches: Array = barrow["terrain"]["niches"]
	var hidden: Array = niches.filter(func(n: Dictionary) -> bool: return n["kind"] == "hidden")
	_check(barrow["links"][1]["hidden"] and barrow["links"][1]["tile"] == Vector2i(52, 16) and not barrow["links"][0]["hidden"] and not deep["links"][0]["hidden"]
		and niches.size() == 14 and hidden.size() == 1 and hidden[0]["cell"] == Vector2i(51, 16) and hidden[0]["edge"] == Terrain.edge_key(Vector2i(51, 16), Vector2i(1, 0))
		and hidden[0]["out"] == Vector2i(-1, 0) and barrow["terrain"]["edges"][hidden[0]["edge"]] == Terrain.Edge.DOOR and barrow["spawn_points"]["from_below"] == Vector2i(51, 16),
		"the template's stair down is hidden behind the first hall's south-east niche, a door edge, from_below before it; 14 niches on the hall's walls (%d, %s)" % [niches.size(), hidden])
	var floor_ok := true
	for pair: Array in [[barrow, "from_chapel"], [barrow, "from_deep"], [barrow, "from_breach"], [barrow, "from_below"], [deep, "from_above"]]:
		var level: Dictionary = pair[0]
		if not level["spawn_points"].has(pair[1]) or not level["terrain"]["floor"].has(level["spawn_points"][pair[1]]):
			floor_ok = false
	var wilds := Level.load_level("wilds")
	var shortcut: Array = barrow["links"].filter(func(l: Dictionary) -> bool: return l["to_spawn"] == "from_temple")
	var chapel_stair: Array = wilds["links"].filter(func(l: Dictionary) -> bool: return l["to_spawn"] == "from_chapel")
	_check(floor_ok and shortcut.is_empty()
		and chapel_stair.size() == 1 and chapel_stair[0]["to_map"] == "barrow" and chapel_stair[0]["sealed"] == ""
		and wilds["links"].filter(func(l: Dictionary) -> bool: return l["to_map"] == "barrow_deep").is_empty(),
		"every spawn point the stairs and the wilds come in by is floor; no quick way down from the First Hall (896 switched on), the wilds' temple stair open into the First Hall, none from the wilds into the deep")
	_check(Level.template_config("barrow_deep").get("stills", []) == ["barrow"] and not Level.template_config("barrow_deep").has("damp")
		and not Level.template_config("barrow_deep").has("ambient") and not Level.template_config("barrow_deep").has("dead"),
		"his rest stills the barrow above as well as his own zone; the dark below's damp, light and word on the dead are gone with it (666)")
	# The halls dressed (580 step 3): the burial table and the pillars are
	# solid doorless buildings (their cells out of the floor, sight stopped),
	# the dais one level up with its front row stairs and its sides ledges,
	# and no way in the dressed halls is one cell wide (612, heights seen).
	var king_table: Array = barrow["buildings"].filter(func(b: Dictionary) -> bool: return b["slot"] == "building.burial_table")
	var pillars: Array = deep["buildings"].filter(func(b: Dictionary) -> bool: return b["slot"] == "building.crypt_pillar")
	_check(king_table.size() == 1 and king_table[0]["rect"] == Rect2i(38, 8, 3, 2) and barrow["terrain"]["solid"].size() == 6
		and not barrow["terrain"]["floor"].has(Vector2i(39, 8)) and pillars.size() == 5 and deep["terrain"]["solid"].size() == 20 + 9 + 8 and deep["terrain"]["floor"].has(Vector2i(49, 70))
		and not deep["terrain"]["floor"].has(Vector2i(49, 60)) and deep["terrain"]["floor"].has(Vector2i(48, 62)),
		"the burial table (3 x 2), the five pillars (2 x 2; none before his seat, 580 amended (2)), the round table (3 x 3) and the four broken tables (2 x 1) stand as solid buildings, their cells out of the floor (%d, %d solid)" % [barrow["terrain"]["solid"].size(), deep["terrain"]["solid"].size()])
	# The feast (3b): the chairs and the throne are walked onto, the throne at
	# the draugr's cell facing the hall, the broken tables along the walls.
	var by_slot := {}
	for b: Dictionary in deep["buildings"]:
		by_slot[b["slot"]] = int(by_slot.get(b["slot"], 0)) + 1
	var throne: Array = deep["buildings"].filter(func(b: Dictionary) -> bool: return b["slot"] == "building.throne")
	var broken: Array = deep["buildings"].filter(func(b: Dictionary) -> bool: return b["slot"] == "building.broken_table")
	var draugr: Array = deep["entities"].filter(func(spec: Dictionary) -> bool: return spec["name"] == "Draugr")
	_check(by_slot.get("building.hall_chair", 0) == 8 and by_slot.get("building.round_table", 0) == 1 and broken.size() == 4
		and throne.size() == 1 and throne[0]["rect"] == Rect2i(49, 75, 1, 1) and throne[0]["facing"] == Vector2i(0, -1)
		and draugr.size() == 1 and draugr[0]["tile"] == Vector2i(49, 75) and deep["terrain"]["floor"].has(Vector2i(49, 75)) and deep["terrain"]["floor"].has(Vector2i(48, 63))
		and not deep["terrain"]["floor"].has(Vector2i(49, 65)) and broken.all(func(b: Dictionary) -> bool: return (b["rect"] as Rect2i).size == Vector2i(1, 2) and (b["rect"] as Rect2i).position.x in [34, 65]),
		"eight chairs and the throne walked onto, the throne at the draugr's cell facing the hall, the round table solid, the broken tables two cells along the east and west walls (%s)" % [by_slot])
	var dais_ok := true
	for cell in Level.rect_cells(Rect2i(44, 74, 12, 4)):
		if int(deep["terrain"]["heights"].get(cell, 0)) != 1:
			dais_ok = false
	var stairs: Dictionary = deep["terrain"]["stairs"]
	var stairs_ok := stairs.size() == 12
	for x in range(44, 56):
		if stairs.get(Vector2i(x, 73)) != Vector2i(0, 1):
			stairs_ok = false
	_check(dais_ok and stairs_ok and int(deep["terrain"]["heights"].get(Vector2i(43, 75), 0)) == 0 and int(deep["terrain"]["heights"].get(Vector2i(49, 73), 0)) == 0
		and deep["terrain"]["floor"].has(Vector2i(49, 76)),
		"the dais is one level up, its front row twelve stairs climbing south, its back row against the wall, the cell behind the throne floor (%d stairs)" % stairs.size())
	_check(Level.narrow_runs(barrow["terrain"]).is_empty() and Level.narrow_runs(deep["terrain"]).is_empty(),
		"no way in the dressed halls is one cell wide, the table, the pillars and the dais's ledges seen (%s)" % [Level.narrow_runs(deep["terrain"]).slice(0, 8)])
	var made := Regen.generate("barrow", 1)
	var made_deep := Regen.generate("barrow_deep", 1)
	_check(not made.is_empty() and Regen.connected(LevelMap.from_image(made["layout"], made["config"]), made["anchors"])
		and not made_deep.is_empty() and Regen.connected(LevelMap.from_image(made_deep["layout"], made_deep["config"]), made_deep["anchors"]),
		"a generation of each depth is laid and joins every anchor (%d and %d tries)" % [made.get("tries", 0), made_deep.get("tries", 0)])
	var gen_barrow := Level.parse(made["layout"], made["height"], made["config"])
	# 806 amended (5): each chest's guard holds its post (Idle.GUARD), the
	# robbers' chest's (Brand, named and guarding) among them.
	var posts: Array[Vector2i] = []
	var brand_guards := false
	for spec: Dictionary in gen_barrow["entities"]:
		if (spec.get("idle", {}) as Dictionary).get("mode", "") == "guard":
			posts.append(spec["tile"])
			brand_guards = brand_guards or spec.get("named", "") == "brand"
	var loose: Array = []
	for spec: Dictionary in gen_barrow["entities"]:
		if str(spec.get("script", "")) == Level.CHEST and (spec.get("props", {}) as Dictionary).has("cache") 				and not posts.any(func(p: Vector2i) -> bool: return _cells_apart(p, spec["tile"]) <= 4):
			loose.append(spec["tile"])
	_check(loose.is_empty() and posts.size() >= 3 and brand_guards,
		"the barrow's chests each with a guard holding its post within 4 cells, Brand at the robbers' chest (%d posts, loose %s)" % [posts.size(), loose])
	var gen_deep := Level.parse(made_deep["layout"], made_deep["height"], made_deep["config"])
	# The crypt's (806 amended): the First Hall's table, and each tomb's
	# sarcophagi and the chapel's bier the generation lays, all solid.
	var laid_solid := 0
	for building: Dictionary in gen_barrow["buildings"]:
		laid_solid += (building["rect"] as Rect2i).get_area()
	# 832: the deep laid by the crypt (its switch-on) adds its tomb chambers'
	# sarcophagi, all solid, to the Hall's own 37 (pillars, table, throne).
	var deep_laid := 0
	if str(Regen.config_of("barrow_deep").get("generator", "")) == "crypt":
		var hall_pieces: Array = Level.template_config("barrow_deep").get("buildings", []).map(func(b: Dictionary) -> Vector2i: return Vector2i(int(b["at"][0]), int(b["at"][1])))
		for building: Dictionary in gen_deep["buildings"]:
			if not (building["rect"] as Rect2i).position in hall_pieces:
				deep_laid += (building["rect"] as Rect2i).get_area()
	_check(gen_barrow["warnings"].is_empty() and gen_deep["warnings"].is_empty() and gen_barrow["terrain"]["solid"].size() == laid_solid and laid_solid > 6 and gen_deep["terrain"]["solid"].size() == 20 + 9 + 8 + deep_laid
		and gen_deep["terrain"]["stairs"].size() == 12 and int(gen_deep["terrain"]["heights"].get(Vector2i(49, 75), 0)) == 1 and made_deep["height"] != null
		and Level.narrow_runs(gen_barrow["terrain"]).is_empty() and Level.narrow_runs(gen_deep["terrain"]).is_empty()
		and made["config"].get("rooms", {}).size() == 3 and made_deep["config"].get("rooms", {}).has("lair"),
		"a generation keeps the dressed halls: the table and pillars solid, the dais raised with its stairs, no way one cell wide, and the named rooms (%s %s; solid %d of %d laid; deep solid %d of %d; narrow %s)" % [gen_barrow["warnings"], gen_deep["warnings"],
			gen_barrow["terrain"]["solid"].size(), laid_solid, gen_deep["terrain"]["solid"].size(), 37 + deep_laid, Level.narrow_runs(gen_barrow["terrain"]).slice(0, 8)])
	# The co-op family tomb (crypt landing 2): one plate set, two plates at
	# least three apart, its door a door edge with the vault's cache chest
	# behind it and a boulder in the tomb; one loose niche with voice's three
	# clues; the co-op rule clean; and the secrets never in the terrain
	# message a client is sent.
	var plates: Array = gen_barrow["terrain"]["plates"]
	var secrets: Array = gen_barrow["secrets"]
	var plate_ok := plates.size() == 1 and (plates[0]["cells"] as Array).size() == 2
	var behind := {}
	var boulders := 0
	for spec: Dictionary in gen_barrow["entities"]:
		if spec.get("script") == Level.CHEST and not str(spec.get("props", {}).get("cache", "")).is_empty():
			behind[spec["tile"]] = true
		elif spec.get("script") == Level.PUSHABLE:
			boulders += 1
	if plate_ok:
		var cells: Array = plates[0]["cells"]
		var gap: Vector2i = (cells[0] as Vector2i) - (cells[1] as Vector2i)
		var sides := Terrain.edge_cells(plates[0]["edge"])
		plate_ok = absi(gap.x) + absi(gap.y) >= 3 and int(gen_barrow["terrain"]["edges"].get(plates[0]["edge"], 0)) == Terrain.Edge.DOOR \
			and (behind.has(sides[0]) or behind.has(sides[1])) and boulders >= 1
	var coop_faults := Regen.layout_faults(made, Regen.config_of("barrow")).filter(func(fault: Dictionary) -> bool: return fault["rule"] == "coop")
	_check(plate_ok and secrets.size() == 1 and (secrets[0]["clues"] as Array).size() == 3 and coop_faults.is_empty(),
		"the crypt's sealed vault is the co-op tomb: two plates three apart, a cache behind its bricked door, a boulder for a lone player, a loose niche with three clues (%s; %s; %s)" % [plates, secrets.map(func(secret: Dictionary) -> Array: return [secret["cell"], secret["clues"]]), coop_faults])
	Level.register("coop_secrets_test", made["layout"], made["height"], made["config"])
	var sent: Dictionary = BuilderHost.terrain_message("coop_secrets_test")["config"]
	_check(not sent.has("secrets") and made["config"].has("secrets") and Level.secrets_of("coop_secrets_test").size() == 1,
		"a level's secrets stay on the server: its terrain message has none, its level still does")
	Level.unregister("coop_secrets_test")
	# Armour as grave goods (622, dungeon's side): the Ossuary's chests roll
	# mail shirts; every generated chest's goods carry the grave mark; nowhere
	# else gives armour. The rolls are seeded by level and cell, so which
	# generation gives what is fixed. The Hall's one chest, on the dais beside
	# the throne, rolls its own table, plate among it (666, the coordinator).
	var first_mail := 0
	var first_plate := 0
	var unmarked := 0
	var chests_seen := 0
	for generation in range(1, 25):
		var laid := Regen.generate("barrow_deep", generation)
		var parsed := Level.parse(laid["layout"], laid["height"], laid["config"])
		for spec: Dictionary in parsed["entities"]:
			if str(spec.get("script", "")) != Level.CHEST:
				continue
			chests_seen += 1
			var props: Dictionary = spec.get("props", {})
			if props.get("grave", false) != true:
				unmarked += 1
			# 599 amended (2): a loot chest is laid as its table's cache, so its goods
			# are what that table gives (rolled here by the generation and cell).
			var goods: Array = Array(Items.roll_loot(str(props["cache"]), "deep%d:%s" % [generation, spec["tile"]], 64, true)) if props.has("cache") \
					else props.get("slots", [])
			if spec["tile"] == Sheet.LAIR_CHEST:
				if goods.has("plate_armour") and first_plate == 0:
					first_plate = generation
			elif goods.has("mail_armour") and first_mail == 0:
				first_mail = generation
		if first_mail > 0 and first_plate > 0 and chests_seen >= 6:  # 832: the crypt deep lays three and the Hall's one a generation
			break
	var hall_entry: Array = Level.template_config("barrow_deep").get("entities", []).filter(func(e: Dictionary) -> bool: return Vector2i(int(e["at"][0]), int(e["at"][1])) == Sheet.LAIR_CHEST)
	_check(first_mail > 0 and unmarked == 0 and chests_seen >= 6 and hall_entry.size() == 1 and hall_entry[0].get("loot") == "fallen_grave",
		"a generation places mail in the Ossuary, every chest's goods grave marked; the Hall's chest rolls fallen_grave (first mail in generation %d; %d chests, %d unmarked)" % [first_mail, chests_seen, unmarked])
	_check(first_plate > 0, "a generation puts plate in the Hall's chest (first in generation %d of 24)" % first_plate)
	var armour_elsewhere: Array[String] = []
	for table: String in Items.loot_tables():
		if table in ["ossuary_grave", "fallen_grave"]:
			continue
		for row: Dictionary in Items.loot_tables()[table]:
			if Items.has_tag(str(row["item"]), "armour") and table not in armour_elsewhere:
				armour_elsewhere.append(table)
	_check(armour_elsewhere.is_empty() and Level.template_config("barrow_deep").get("loot", {}).get("chest", "") == "ossuary_grave" and not Level.template_config("barrow").has("loot"),
		"the crypt's chests are the only loot that gives armour: the Ossuary's table, none on the first layer (%s)" % [armour_elsewhere])
	_check(not Net.regenerate and not Regen.may_write() and not _main._regenerate_if_due("barrow") and not Level.overlaid("barrow"),
		"off unless the server runs --regenerate: nothing is laid, the barrow stays its template")
	_check(_main.admin_command("regenerate on") == "regenerate on: the shifting levels are laid again when due" and Net.regenerate, "the console switches it on")
	_check(Regen.in_test_run() and not Regen.may_write() and not _main._regenerate_if_due("barrow") and not Level.overlaid("barrow"),
		"and even on, a test run on the shared overlay writes nothing there")
	_check(Regen.is_test_scene(PackedStringArray(["--headless", "--scene", "tests/level_test.tscn"])) and Regen.is_test_scene(PackedStringArray(["res://tests" + char(92) + "x.tscn"]))
		and not Regen.is_test_scene(PackedStringArray(["--scene", "tools/make_hills.tscn"])) and not Regen.is_test_scene(PackedStringArray(["--server", "--regenerate"])),
		"a scene under tests/ is a test run without the marker too (199 amended); a tool's scene or the server is not")
	var listed: String = _main.admin_command("regenerate")
	_check(listed.begins_with("regenerate on") and "barrow: generation 0, every 3 days" in listed and "barrow_deep: generation 0, every 3 days" in listed
		and not "barrow_lair" in listed, "the console lists both depths, the retired one not (%s)" % listed.replace("\n", "; "))
	_check(_main.admin_command("regenerate off").begins_with("regenerate off") and not Net.regenerate, "and switches it off")
	_check(_main.admin_command("regenerate now barrow") == "regenerate now: refused in a test run on the shared overlay" and not Level.overlaid("barrow"),
		"regenerate now (541 amended) is refused in a test run on the shared overlay: the barrow stays its template")
	_check(_main.admin_command("regenerate now castle").begins_with("regenerate now: castle is no shifting level"), "and names a level that does not shift")


## Moss and webs (647): level.json's "decor" read by Level.decor_from,
## each kind held to its place, the bad ones said and left out.
func _test_decor() -> void:
	print("\n== moss and webs (647): a patch on the floor, a strip at a wall's foot, a web in a corner or across an open niche; the misplaced left out ==")
	# The hidden door's 8 x 6 room again: three niches in its north wall,
	# the east one hidden with its alcove behind a door edge.
	var rows: Array[String] = []
	for py in 6 * 2 - 1:
		var row := ""
		for px in 8 * 2 - 1:
			var cell := Vector2i(px / 2, py / 2)
			var floor_here := px % 2 == 0 and py % 2 == 0 and (cell.x >= 1 and cell.x <= 6 and cell.y >= 1 and cell.y <= 4 or cell == Vector2i(6, 0))
			row += "+" if px == 12 and py == 1 else ("." if floor_here else " ")
		rows.append(row)
	Level.register("lt_decor", Level.image_from_rows(rows, {Vector2i(3, 3): "start", Vector2i(6, 0): "link"}), null,
		{"niches": [[2, 1, 0, -1, "a", 1], [4, 1, 0, -1, "c", 2], [6, 1, 0, -1, "hidden", 1]],
			"links": [{"at": [6, 0], "to_map": "test_room", "to_spawn": "", "hidden": true}],
			"decor": [[3, 3, 0, 0, "moss_patch", 3], [2, 4, 0, 1, "moss_strip", 2], [1, 1, -1, -1, "web_corner", 1], [2, 1, 0, -1, "web_niche", 2],
				[4, 1, 0, -1, "web_niche", 1], [6, 1, 0, -1, "web_niche", 1], [3, 2, 1, 0, "moss_strip", 1], [3, 3, 1, 0, "moss_patch", 1],
				[3, 3, 1, 1, "web_corner", 1], [3, 2, 0, 0, "moss_patch", 4], [3, 3, 0, 0, "moss_patch", 1], [5, 5, 0, 0, "moss_patch", 1], [1, 1, "x"],
				# 658: a faced flat piece and a rolled one, an edge piece on a wall edge and on an open one; a flat piece on a diagonal and an edge piece with no step are not.
				[5, 2, 1, 0, "fallen_guard", 2], [5, 3, 0, 0, "fallen_guard", 1], [1, 2, -1, 0, "grave_fence", 3], [4, 3, 0, -1, "grave_fence", 1],
				[5, 4, 1, 1, "fallen_guard", 1], [4, 4, 0, 0, "grave_fence", 1]]})
	var parsed := Level.load_level("lt_decor")
	var decor: Array = parsed["terrain"]["decor"]
	var kinds := decor.map(func(d: Dictionary) -> String: return d["kind"])
	_check(decor.size() == 8 and kinds == ["moss_patch", "moss_strip", "web_corner", "web_niche", "fallen_guard", "fallen_guard", "grave_fence", "grave_fence"],
		"the eight well placed are read in order: a patch, a strip, a corner web, a niche web, two fallen guards, two fence sections (%s)" % [kinds])
	_check(decor.size() == 8 and decor[0]["out"] == Vector2i.ZERO and not decor[0].has("edge") and decor[0]["variant"] == 3
		and decor[1]["edge"] == Terrain.edge_key(Vector2i(2, 4), Vector2i(0, 1)) and decor[1]["out"] == Vector2i(0, 1)
		and decor[2]["out"] == Vector2i(-1, -1) and not decor[2].has("edge")
		and decor[3]["edge"] == parsed["terrain"]["niches"][0]["edge"] and decor[3]["out"] == Vector2i(0, -1) and decor[3]["variant"] == 2,
		"each as terrain reads it: the patch with no edge, the strip and the niche web with theirs, the corner web with its diagonal (%s)" % [decor])
	_check(decor.size() == 8 and decor[4]["out"] == Vector2i(1, 0) and not decor[4].has("edge") and decor[4]["variant"] == 2 and decor[5]["out"] == Vector2i.ZERO
		and decor[6]["edge"] == Terrain.edge_key(Vector2i(1, 2), Vector2i(-1, 0)) and decor[7]["edge"] == Terrain.edge_key(Vector2i(4, 3), Vector2i(0, -1))
		and int(parsed["terrain"]["edges"].get(decor[7]["edge"], Terrain.Edge.OPEN)) == Terrain.Edge.OPEN,
		"658: the faced guard keeps his facing and no edge, the rolled one his (0, 0); the fence sections carry their edge, the wall's and the open one's alike (%s)" % [decor.slice(4)])
	var warnings: Array = parsed["warnings"].filter(func(w: String) -> bool: return w.begins_with("decor "))
	_check(warnings.size() == 11 and parsed["warnings"].size() == 11,
		"the eleven misplaced are said and left out: a web on a sealed niche, on the hidden one, a strip on an open edge, a patch with a step, a corner with no wall, a variant the kind has not, a second patch on the cell, one in the rock, one malformed, a guard on a diagonal, a fence with no step (%s)" % [warnings])
	Level.register("lt_decor_bad", Level.image_from_rows(rows, {Vector2i(3, 3): "start"}), null, {"decor": {"moss": 1}})
	_check(Level.load_level("lt_decor_bad")["warnings"] == ["\"decor\" in level.json is not a list"], "a \"decor\" that is no list is said")
	# Out of doors (658; maps' grave fence on Held, 654): an edge piece on an
	# open grass edge and on the map's own edge, a flat piece on grass, read
	# in with nothing said.
	var grass := Image.create_empty(6 * 2 + 1, 4 * 2 + 1, false, Image.FORMAT_RGBA8)
	grass.fill(Color(str(Level.LEGEND["grass"])))
	grass.set_pixel(2, 2, Color(str(Level.LEGEND["start"])))
	Level.register("lt_decor_out", grass, null, {"name": "Fenced", "outdoor": true,
		"decor": [[2, 1, 0, 1, "grave_fence", 2], [3, 1, 0, 1, "grave_fence", 1], [0, 0, -1, 0, "grave_fence", 3], [4, 2, -1, 0, "fallen_guard", 1]]})
	var out := Level.load_level("lt_decor_out")
	var fence: Array = out["terrain"]["decor"]
	_check(out["warnings"].is_empty() and fence.size() == 4 and fence[0]["edge"] == Terrain.edge_key(Vector2i(2, 1), Vector2i(0, 1))
		and fence[1]["edge"] == Terrain.edge_key(Vector2i(3, 1), Vector2i(0, 1)) and fence[2]["edge"] == Terrain.edge_key(Vector2i(0, 0), Vector2i(-1, 0))
		and fence[3]["kind"] == "fallen_guard" and fence[3]["out"] == Vector2i(-1, 0),
		"out of doors a fence runs along two open grass edges and the map's edge, a body lies on the grass facing west, nothing said (%s; %s)" % [out["warnings"], fence])


## The Dwarven Halls under the castle (613, dungeon's side): the template,
## its stair both ways with the castle's guardroom (maps' side), the
## smith's place between the forge's anvils.
func _test_castle_halls_level() -> void:
	print("\n== levels/castle_halls (613): the Dwarven Halls and the castle's guardroom stair ==")
	var halls := Level.load_level("castle_halls")
	var castle := Level.load_level("castle")
	_check(halls["display_name"] == "The Dwarven Halls" and halls["size"] == Vector2i(90, 70) and halls["warnings"].is_empty()
		and int(Level.template("castle_halls")["config"].get("depth", 0)) == 1,
		"The Dwarven Halls, 90 x 70, depth 1, parse with no warning (%s)" % [halls["warnings"]])
	var block := Regen.config_of("castle_halls")
	_check(Regen.marked("castle_halls") and block.get("style") == "dwarven" and int(block.get("ways", 0)) == 5 and block["anchors"].size() == 3 and block.get("entrance") == "stair_foot"
		and block.get("monsters") == {"imp": 4, "sneak": 3, "brute": 1} and block.get("packs") is Dictionary and block["packs"].keys() == ["sneak"] and str(block["packs"]["sneak"].get("of")) == "sneak" and int(block["packs"]["sneak"].get("size", 0)) == 3 and block.get("uses") == "hold" and block.get("heart") == "forge",
		"marked to regenerate in the dwarven style, ways five wide, three anchors, depth from the stair foot, enemy-ai's four imps, three sneaks as a pack (824) and a brute (806 amended (4): one a room, a guard before the forge), the hold's uses, the forge its heart (%s)" % [block.keys()])
	_check(halls["links"].size() == 1 and halls["links"][0]["tile"] == Vector2i(44, 1) and halls["links"][0]["to_map"] == "castle" and halls["links"][0]["to_spawn"] == "from_halls"
		and halls["spawn_points"].get("from_castle") == Vector2i(44, 2) and halls["terrain"]["floor"].has(Vector2i(44, 2)),
		"the stair up in the stair foot's north wall leads to the castle's from_halls; from_castle on the floor beside it")
	var down: Array = castle["links"].filter(func(link: Dictionary) -> bool: return link["to_map"] == "castle_halls")
	_check(down.size() == 1 and down[0]["tile"] == Vector2i(11, 18) and down[0]["to_spawn"] == "from_castle" and castle["spawn_points"].get("from_halls") == Vector2i(12, 18)
		and castle["terrain"]["floor"].has(Vector2i(12, 18)) and castle["terrain"]["floor"].has(Vector2i(11, 18)),
		"the castle's stair down stands in the guardroom at (11, 18), from_halls beside it on the floor (613, maps' side)")
	_check(castle["terrain"]["edges"].get(Terrain.edge_key(Vector2i(13, 19), Vector2i(1, 0))) == Terrain.Edge.DOOR
		and castle["terrain"]["edges"].get(Terrain.edge_key(Vector2i(11, 17), Vector2i(0, -1))) == Terrain.Edge.WALL
		and castle["terrain"]["edges"].get(Terrain.edge_key(Vector2i(11, 18), Vector2i(-1, 0))) == Terrain.Edge.WALL,
		"the guardroom's door opens onto the gate passage's west jamb; its north and west sides are walled")
	var place: Dictionary = halls["places"].get("dwarven_forge", {})
	_check(place.get("cell") == Vector2i(43, 64) and place.get("kind") == "refuge" and place.get("radius") == 3 and place.get("where") == "castle_dungeon",
		"the smith's refuge, dwarven_forge, stands between the forge's anvils, a refuge under the castle (%s)" % [place])
	var pillars: Array = halls["buildings"].filter(func(building: Dictionary) -> bool: return building["slot"] == "building.crypt_pillar")
	_check(pillars.size() == 4 and pillars.all(func(building: Dictionary) -> bool: return int(building.get("variant", 1)) == 2),
		"four dwarven pillars (crypt_pillar, variant 2)")
	# 613 amended: the forge and the rack stand solid, the guards lie where they fell.
	var forge: Array = halls["buildings"].filter(func(building: Dictionary) -> bool: return building["slot"] == "building.dwarven_forge")
	var rack: Array = halls["buildings"].filter(func(building: Dictionary) -> bool: return building["slot"] == "building.weapon_rack")
	_check(forge.size() == 1 and forge[0]["rect"] == Rect2i(42, 65, 6, 3) and forge[0]["facing"] == Vector2i(0, -1)
		and not halls["terrain"]["floor"].has(Vector2i(42, 65)) and not halls["terrain"]["floor"].has(Vector2i(47, 67)) and halls["terrain"]["solid"].has(Vector2i(44, 66))
		and halls["terrain"]["floor"].has(Vector2i(43, 64)),
		"the great forge stands 6 x 3 against the south wall facing north, solid, the stand cell before its anvils floor (%s)" % [forge])
	_check(rack.size() == 1 and rack[0]["rect"] == Rect2i(50, 67, 2, 1) and rack[0]["facing"] == Vector2i(0, -1)
		and not halls["terrain"]["floor"].has(Vector2i(50, 67)) and not halls["terrain"]["floor"].has(Vector2i(51, 67)) and halls["terrain"]["floor"].has(Vector2i(49, 67)) and halls["terrain"]["floor"].has(Vector2i(52, 67)),
		"the goblins' weapon rack stands 2 x 1 against the south wall east of the forge, solid, floor either side (%s)" % [rack])
	var guards: Array = halls["terrain"]["decor"].filter(func(d: Dictionary) -> bool: return d["kind"] == "fallen_guard")
	_check(halls["terrain"]["decor"].size() == 3 and guards.size() == 3 and guards[0]["cell"] == Vector2i(23, 30) and guards[0]["out"] == Vector2i(1, 0)
		and guards[1]["out"] == Vector2i(0, -1) and guards[1]["variant"] == 2 and guards[2]["out"] == Vector2i(-1, 0) and guards[2]["variant"] == 2
		and guards.all(func(d: Dictionary) -> bool: return Level.in_anchors(Regen.config_of("castle_halls")["anchors"], d["cell"])),
		"three of the smith's guards lie in the ambush, each with a facing, so all read as fallen from the usual camera: one on his side facing the cart, one face down running north, one face down toward the west wall (%s)" % [guards])
	_check(halls["entities"].size() == 5 and halls["links"][0]["cue"] == "up" and down[0]["cue"] == "down",
		"the template's five markers alone stand in the halls (the cart, two crates, two chests); the stairs cue up and down (%d, %s, %s)" % [halls["entities"].size(), halls["links"][0]["cue"], down[0]["cue"]])
	# 757, dungeon's side: every plain chest in the halls, the template's and
	# each generation's, rolls economy's dwarven_hoard (no armour: 622).
	var hoard: Array = (Items.loot_tables().get("dwarven_hoard", []) as Array).map(func(row: Dictionary) -> String: return str(row["item"]))
	var chests_seen := 0
	var stocked := 0
	var strays: Array = []
	for generation in range(1, 7):
		var laid := Regen.generate("castle_halls", generation)
		var parsed := Level.parse(laid["layout"], laid["height"], laid["config"])
		for spec: Dictionary in parsed["entities"]:
			var props: Dictionary = spec.get("props", {})
			if str(spec.get("script", "")) != Level.CHEST or props.get("depot", false) or props.get("shop", false) or props.has("cache"):
				continue
			chests_seen += 1
			var goods: Array = (props.get("slots", []) as Array).filter(func(id: String) -> bool: return not id.is_empty())
			if not goods.is_empty():
				stocked += 1
			for id: String in goods:
				if id not in hoard or Items.has_tag(id, "armour"):
					strays.append(id)
	# 806 amended (4): the generations' chests are caches (castle_cache, the
	# armoury's armoury); the forge's two, the refuge's hoard, stay stocked.
	_check(Level.template_config("castle_halls").get("loot", {}).get("chest", "") == "dwarven_hoard" and not hoard.is_empty()
		and chests_seen == 6 * 2 and stocked == chests_seen and strays.is_empty(),
		"the forge's hoard chests roll dwarven_hoard every generation, no armour; the rest are caches (%d chests, %d stocked, strays %s)" % [chests_seen, stocked, strays])


func _test_edge_links() -> void:
	print("
== edge links: walk off one map's edge, arrive at the next one's ==")
	_main.load_map("test_edge_w")
	_check(_main.level["size"] == Vector2i(4, 3) and _main.level["neighbours"] == {"east": "test_edge_e"},
		"test_edge_w is 4 x 3 cells with test_edge_e east (%s, %s)" % [_main.level["size"], _main.level["neighbours"]])
	var player := _player()
	_put(player, Vector2i(3, 0))
	_hold_free(player, Vector2(0, -1), 6)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_main.map_name == "test_edge_w" and player.tile == Vector2i(3, 0), "walking into the north edge, which has no neighbour, is a wall: Player stays (%s)" % _main.map_name)
	player = _player()
	_put(player, Vector2i(3, 2))
	_hold_free(player, Vector2(1, 0), 6)
	await get_tree().process_frame
	await get_tree().process_frame
	var arrived := _player()
	_check(_main.map_name == "test_edge_e" and arrived != null and arrived.zone == "test_edge_e", "it takes Player to test_edge_e (%s)" % _main.map_name)
	_check(arrived != null and arrived.tile == Vector2i(0, 2), "arriving on its west edge at the same row, (0, 2) (%s)" % [arrived.tile if arrived else "none"])
	_put(arrived, Vector2i(0, 4))
	_hold_free(arrived, Vector2(-1, 0), 6)
	await get_tree().process_frame
	await get_tree().process_frame
	var back := _player()
	_check(_main.map_name == "test_edge_w" and back != null and back.tile == Vector2i(3, 2),
		"back west from row 4, past test_edge_w's last row: its east edge's last cell, (3, 2) (%s)" % [back.tile if back else "none"])


## Every way out of the barrow lands at its own door (Jeff, v0.1.194: "when
## exiting the barrows after the quest is complete - the game placed me by
## the foothills zone line in the wilds"): each real link taken by the
## server's own handler (Main._take_link), the arrival read off the player.
## The mound's door to the wilds at the mound, the Ossuary's shortcut and the
## temple's stair by the temple, the niche and the stair between the depths
## at their feet. A private overlay: a depth laid on opening is never written
## to the shared one.
func _test_barrow_exits() -> void:
	print("
== the barrow's ways out: each lands at its own mound, temple or stair foot ==")
	var overlay := Level.overlay_dir
	Level.overlay_dir = preload("res://tests/test_ports.gd").scratch("level_test/barrow_exits/")
	var id: String = _main._peer_ids[Net.local_id]
	_main.mark_player(id, "draugr")  # The shortcut and the temple's stair open to the blessed.
	var wilds := Level.load_level("wilds")
	var temple_stair := Main.building_link_back(wilds, "barrow")
	# [from level, link cell, to level, where it should land, within]. 832
	# switched on: the First Hall's stair up comes out beside the chapel
	# stair, the camp's breach at the mound (its named spawn, not the stair).
	# 896 switched on: the sealed shortcut both ways is gone; the throne is
	# the way home (_test_throne_home).
	var ways: Array = [
		["barrow", Vector2i(40, 1), "wilds", temple_stair, 1],
		["barrow", Vector2i(31, 52), "wilds", wilds["spawn_points"]["from_barrow"], 1],
		["barrow", Vector2i(52, 16), "barrow_deep", Vector2i(49, 2), 1],
		["barrow_deep", Vector2i(49, 1), "barrow", Vector2i(51, 16), 1],
	]
	var landed := {}
	for way: Array in ways:
		_main.load_map("test_room")
		_main.travel(Net.local_id, way[0], "")
		await get_tree().process_frame
		var player := _player()
		var linked := false
		for link: Dictionary in _main.level.get("links", []):
			linked = linked or link["tile"] == way[1] and link["to_map"] == way[2]
		_main._take_link(player, way[1])
		await get_tree().process_frame
		await get_tree().process_frame
		player = _player()
		var at: Vector2i = player.tile if player != null else World.NO_CELL
		_check(linked and _main.map_name == way[2] and player != null and World.distance(at, way[3]) <= way[4],
			"%s's way out at %s lands in %s within %d of %s (%s, at %s)" % [way[0], way[1], way[2], way[4], way[3], _main.map_name, at])
		landed[way[1]] = at
	# 832 switched on (Main.travel): two ways out of the barrow into the wilds;
	# the breach's named spawn stands at the mound's door, another way back
	# down, so it holds, where the First Hall's stair follows the temple's.
	var by_breach: Vector2i = landed.get(Vector2i(31, 52), World.NO_CELL)
	var by_stair: Vector2i = landed.get(Vector2i(40, 1), World.NO_CELL)
	_check(World.distance(by_breach, Vector2i(160, 159)) <= 1 and World.distance(by_stair, temple_stair) <= 1 and World.distance(by_breach, by_stair) > 20,
		"from the barrow by the breach one comes out at the mound (%s), by the First Hall's stair beside the temple's stair (%s): a named spawn beside another way back down holds" % [by_breach, by_stair])
	# 749 amended: spawn safety counts only monsters that are not peaceable:
	# the cell behind the throne (the shortcut's end till 896 switched on),
	# his draugr peaceable beside it, is safe; provoked, it is not.
	_main.load_map("test_room")
	_main.travel(Net.local_id, "barrow_deep", "")
	var by_throne := Vector2i(49, 76)
	var seated: Array = World.get_entities().filter(func(e: GridEntity) -> bool: return e is Draugr and e.spawned)
	_check(seated.size() == 1 and (seated[0] as Draugr).peaceable and World.distance(seated[0].tile, by_throne) <= 1
		and _main._safe_tile_near(by_throne) == by_throne,
		"behind the throne, the draugr peaceable beside it: a safe cell (%s)" % [_main._safe_tile_near(by_throne)])
	if seated.size() == 1:
		(seated[0] as Draugr).peaceable = false  # As provoked, the same tick (Draugr._sim_tick).
		var moved: Vector2i = _main._safe_tile_near(by_throne)
		_check(moved != by_throne and (moved == World.NO_CELL or World.distance(moved, seated[0].tile) > Main.SPAWN_SAFE_DISTANCE),
			"the draugr provoked, spawn safety moves an arrival there off (to %s)" % [moved])
	_main.mark_player(id, "draugr", false)
	_main.load_map("test_room")
	Level.overlay_dir = overlay


## Spawn safety's nearest safe cell (decision 749; Jeff, v0.1.194:
## a monster 4 from the mound's arrival sent him to the wilds' farthest
## start, by the foothills line): an arrival with a monster within
## SPAWN_SAFE_DISTANCE lands on the nearest safe cell reachable from it;
## the zone's safest start only when there is none on its own side of a wall.
func _test_spawn_near() -> void:
	print("
== spawn safety (749): the nearest safe cell from the arrival, the safest start only when none ==")
	# 40 x 9 cells, a wall down the east side of x 9, the start far east.
	var walls: Array[Vector3i] = []
	for y in 9:
		walls.append(Vector3i(9, y, Terrain.EAST))
	var cases := {
		"lt_spawn_open": {"monster": Vector2i(4, 1), "door": Vector2i(4, 4), "walls": [] as Array[Vector3i]},
		"lt_spawn_walled": {"monster": Vector2i(5, 4), "door": Vector2i(2, 4), "walls": walls},
	}
	for name: String in cases:
		var case: Dictionary = cases[name]
		var rows := _rows(0, 39, 0, 8, case["walls"])
		Level.register(name, Level.image_from_rows(rows, {Vector2i(36, 4): "start", case["monster"]: "monster_brute"}), null,
			{"spawn_points": {"door": [case["door"].x, case["door"].y]}})
		_main.load_map("test_room")
		_main.travel(Net.local_id, name, "door")
		await get_tree().process_frame
		var player := _player()
		var at: Vector2i = player.tile if player != null else World.NO_CELL
		var monster: Vector2i = case["monster"]
		if name == "lt_spawn_open":
			_check(_main.map_name == name and World.distance(at, case["door"]) <= _main.SPAWN_NEAR_TILES and World.distance(at, monster) > _main.SPAWN_SAFE_DISTANCE
				and at != Vector2i(36, 4),
				"a monster 3 from the arrival %s: the nearest safe cell, not the far start (at %s)" % [case["door"], at])
			_check(World.distance(at, case["door"]) == 3, "the nearest: 3 cells off, the first out of its reach (at %s)" % [at])
		else:
			_check(_main.map_name == name and at == Vector2i(36, 4),
				"every cell on the arrival's side of the wall within reach of the monster: never across the wall, the safest start (at %s)" % [at])
		_main.load_map("test_room")
		Level.unregister(name)


func _test_castle() -> void:
	print("\n== the castle, and the way there from the test room ==")
	var castle := Level.load_level("castle")
	_check(not castle.is_empty() and castle["display_name"] == "The Castle" and castle["warnings"].is_empty(),
			"levels/castle is \"The Castle\" and loads cleanly (%s)" % [castle.get("warnings", "missing")])
	_check(load("res://levels/castle/layout.png") is Image, "its layout.png is imported as an Image")
	_check(castle["links"].size() == 3 and str(castle["links"].slice(0, 2)) == str([{"tile": Vector2i(27, 12), "to_map": "test_room", "to_spawn": "from_castle", "one_way": false, "closed": false, "sealed": "", "hidden": false, "cue": "none"},
			{"tile": Vector2i(16, 23), "to_map": "foothills", "to_spawn": "from_castle", "one_way": false, "closed": false, "sealed": "", "hidden": false, "cue": "waystones"}])
			and castle["links"][2]["tile"] == Vector2i(11, 18) and castle["links"][2]["to_map"] == "castle_halls" and castle["links"][2]["to_spawn"] == "from_castle",
			"its link at (27, 12) goes to the test room, at the foot of its road to the foothills (the wilds till 745), and from the guardroom down to the Dwarven Halls (613) (%s)" % [castle["links"]])
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
	_hold_free(player, Vector2(0, 1), 6)
	await get_tree().process_frame
	await get_tree().process_frame
	var there := _player()
	_check(World.outdoor and castle["terrain"]["outdoor"] and not room["terrain"]["outdoor"],
			"the castle is outdoors (level.json \"outdoor\"), the test room is not")
	_check(_main.map_name == "castle" and there != null and there.tile == Vector2i(26, 13),
			"Player walks onto it and arrives in the castle beside its link, at (26, 13) (%s %s)" % [_main.map_name, there.tile if there else "none"])
	_hold_free(there, Vector2(1, -1).normalized(), 8)
	await get_tree().process_frame
	await get_tree().process_frame
	var home := _player()
	_check(not World.outdoor, "walking onto the castle's link, World is indoors again in the test room")
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


## [param player]'s free body held on [param intent] for [param ticks] ticks.
func _hold_free(player: Player, intent: Vector2, ticks: int) -> void:
	for i in ticks:
		World.free_input(player, intent, World.TICK_DT)
		World.step()


## [param player]'s free body walked to [param to] along World.find_path's
## way, cell by cell, as a click's route is (a free body takes no move
## order, 688).
func _walk_free(player: Player, to: Vector2i) -> void:
	for cell: Vector2i in World.find_path(player.tile, to):
		for i in 20:
			var way := Vector2(cell) - player.free_pos
			if way.length() < 0.1:
				break
			World.free_input(player, way.normalized() if way.length() > 0.4 else way / 0.4, World.TICK_DT)
			World.step()


## 832 (the crypt's ways in): the barrow's arrivals, from_chapel and
## from_deep in the First Hall and from_breach in the Robbers' Camp, inside
## an anchor and on floor in the template and every generation, so the
## switch-on's links (maps') land on ground.
func _test_crypt_ways() -> void:
	print("
== the crypt's ways in (832): the barrow's arrivals ==")
	var template := Level.load_level("barrow")
	var arrivals := {"from_chapel": "entrance", "from_deep": "entrance", "from_breach": "breach"}  # 832: the breach a dig off the camp, out of its sight
	var wrong: Array[String] = []
	var anchors: Dictionary = {}
	for anchor: Dictionary in Regen.config_of("barrow")["anchors"]:
		var rect: Variant = anchor["rect"]
		anchors[str(anchor["name"])] = rect if rect is Rect2i else Rect2i(rect[0], rect[1], rect[2], rect[3])
	for spawn: String in arrivals:
		var at: Variant = template["spawn_points"].get(spawn)
		if not at is Vector2i or not (anchors[arrivals[spawn]] as Rect2i).has_point(at):
			wrong.append("template: %s at %s, not in %s" % [spawn, at, arrivals[spawn]])
	for generation in range(1, 4):
		var made := Regen.generate("barrow", generation)
		var level := Level.parse(made["layout"], made["height"], made["config"])
		var map := LevelMap.from_image(made["layout"], made["config"])
		for spawn: String in arrivals:
			var at: Variant = level["spawn_points"].get(spawn)
			if not at is Vector2i or not map.walkable(at):
				wrong.append("g%d: %s at %s" % [generation, spawn, at])
		# 832 (the coordinator: no arrival puts a player inside a fight); 747
		# amended (8): the knight reached from each but the robbers' own door.
		for fault: Dictionary in LAYOUT_SENSE.arrival_faults(level, str(Regen.config_of("barrow").get("foes_door", ""))):
			wrong.append("g%d: %s" % [generation, fault["what"]])
	_check(wrong.is_empty() and template["warnings"].is_empty(), "the barrow's three arrivals in their anchors and on floor in the template and generations 1-3, each beyond every foe's reach (%s %s)" % [wrong, template["warnings"]])
	# The breach a dig off the camp's south side, its way out and arrival at
	# its far end, round its bend from the camp: the camp's every cell beyond
	# a wandering robber's reach of it (ARRIVAL_CLEAR and WANDER_RADIUS).
	var breach: Vector2i = template["spawn_points"]["from_breach"]
	var nearest := 1 << 30
	for cell in Level.rect_cells(anchors["camp"]):
		nearest = mini(nearest, maxi(absi(cell.x - breach.x), absi(cell.y - breach.y)))
	var way_out: Array = template["links"].filter(func(l: Dictionary) -> bool: return l["tile"] == Vector2i(31, 52))
	_check(nearest >= LAYOUT_SENSE.ARRIVAL_CLEAR + Monster.WANDER_RADIUS and (anchors["breach"] as Rect2i).has_point(Vector2i(31, 52)) and way_out.size() == 1,
		"the breach comes in at the dig's far end, %d cells from the nearest of the camp (%d wanted), its way out beside it (%s)" % [nearest, LAYOUT_SENSE.ARRIVAL_CLEAR + Monster.WANDER_RADIUS, way_out])


## 747 amended (8) (Jeff: "it makes more sense if the knight is at the
## beginning by the actual altar"; the coordinator's ruling): the quest
## giver is reached from every arrival without passing the band, GIVER_CLEAR
## beyond a hostile's reach; the one arrival not asked, the barrow's
## breach, the robbers' own door, named in its block alone.
func _test_giver_rule() -> void:
	print("
== layout sense: the quest giver reached clear of the band from every arrival (747 amended (8)) ==")
	var floor: Array[Vector2i] = []
	for y in 3:
		for x in 31:
			floor.append(Vector2i(x, y))
	var knight := {"tile": Vector2i(30, 1), "home": Vector2i(30, 1), "kind": "astral_knight"}
	var guard := {"tile": Vector2i(15, 1), "home": Vector2i(15, 1), "kind": "brute", "idle": {"mode": "guard"}}
	var hall := func(entities: Array, door := "") -> Array:
		return LAYOUT_SENSE.arrival_faults({"spawn_points": {"from_test": Vector2i(0, 1)}, "entities": entities, "terrain": {"floor": floor}}, door)
	_check(hall.call([knight]).is_empty(), "the giver down an empty hall: reached")
	var barred: Array = hall.call([knight, guard])
	_check(barred.size() == 1 and str(barred[0]["what"]).contains("from_test") and str(barred[0]["what"]).contains("brute"),
		"a foe standing on the way between: a fault naming the arrival and the nearest foe (%s)" % [barred])
	_check(hall.call([knight, guard], "from_test").is_empty(), "the foes' own door is not asked the walk")
	_check(hall.call([guard]).is_empty(), "no giver, no walk asked")
	var doors := {}
	for level_name: String in DirAccess.get_directories_at(Level.DIR):
		var block: Variant = Level.template_config(level_name).get("regenerate", {})
		if block is Dictionary and (block as Dictionary).has("foes_door"):
			doors[level_name] = block["foes_door"]
	_check(doors == {"barrow": "from_breach"}, "the one arrival exempt anywhere: the barrow's breach, the robbers' own door (%s)" % [doors])
	var tries: Array[int] = []
	var faults := {}
	var unbundled := {}
	var hidden_at := {}
	var untold := {}
	var at := Vector2i(-1, -1)
	var facing := Vector2i.ZERO
	for generation in range(1, 9):
		var made := Regen.generate("barrow", generation)
		if made.is_empty():
			faults[generation] = "not laid"
			continue
		tries.append(int(made["tries"]))
		hidden_at[generation] = _hidden_niche_of(made["config"])
		var level := Level.parse(made["layout"], made["height"], made["config"])
		var tells: Array = (level["terrain"].get("decor", []) as Array).filter(func(piece: Dictionary) -> bool: return piece["kind"] == "candle_draft")
		if tells.size() != 1 or tells[0]["cell"] != hidden_at[generation]:
			untold[generation] = tells.map(func(piece: Dictionary) -> Vector2i: return piece["cell"])
		var found := LAYOUT_SENSE.arrival_faults(level, "from_breach")
		if not found.is_empty():
			faults[generation] = found.map(func(fault: Dictionary) -> String: return str(fault["what"]))
		# The two kits by the band's bedding (870, combat's ask), kept by every generation.
		var bundles: Array = level.get("entities", []).filter(func(spec: Dictionary) -> bool: return str(spec.get("name", "")) == "Robbers' bundle")
		var beds: Array = (level["terrain"].get("decor", []) as Array).filter(func(piece: Dictionary) -> bool: return piece["kind"] == "bedroll")
		if bundles.size() != 1 or bundles[0]["tile"] != Vector2i(6, 48) or Array(bundles[0]["props"].get("slots", [])).count("bandaging_kit") != 2 or beds.size() != 2:
			unbundled[generation] = [bundles.map(func(spec: Dictionary) -> String: return "%s %s" % [spec["tile"], spec["props"].get("slots")]), beds.size()]
		for spec: Dictionary in level.get("entities", []):
			if str(spec.get("kind", "")) == "astral_knight":
				at = spec["tile"]
				facing = spec.get("facing", Vector2i.ZERO)
	_check(unbundled.is_empty(), "the barrow's generations 1-8: the Robbers' bundle at (6, 48) holding two bandaging kits, by the band's two bedrolls (%s)" % [unbundled])
	_check(faults.is_empty(), "the barrow's generations 1-8: from the temple stair, the start, from_deep and from_below the knight is reached clear, and every arrival clear (tries %s; %s)" % [tries, faults])
	_check(at == Vector2i(39, 10) and facing == Vector2i(0, -1), "the knight behind the First Hall's bier, facing the stair (%s, %s)" % [at, facing])
	# 608 amended (3) (the coordinator: "a secret off the main way, never a
	# far corner"): the hidden niche only on the First Hall's west wall,
	# within 4 cells of its way out (27, 9)-(27, 10), on these generations and
	# later ones; still moving between them.
	for generation: int in [118, 119, 120, 121]:
		var made := Regen.generate("barrow", generation)
		hidden_at[generation] = _hidden_niche_of(made.get("config", {}))
	var astray := hidden_at.keys().filter(func(generation: int) -> bool:
		var cell: Vector2i = hidden_at[generation]
		return cell.x != 28 or mini(absi(cell.y - 9), absi(cell.y - 10)) > 4)
	var places := {}
	for generation: int in hidden_at:
		places[hidden_at[generation]] = true
	_check(astray.is_empty() and places.size() >= 2,
		"the hidden niche on the west wall within 4 of the hall's way out, on generations 1-8 and 118-121, moving among them (%s)" % [hidden_at])
	_check(untold.is_empty(), "its tell (the block's hidden_tell, art-kit's candles bent by the draught) laid at the hidden niche and nowhere else, each of generations 1-8, kept by the parse (608 amended (3)) (%s)" % [untold])


## The hall cell before the hidden niche in a generated config's "niches"
## (608), or (-1, -1).
func _hidden_niche_of(config: Dictionary) -> Vector2i:
	for niche: Variant in config.get("niches", []):
		if niche is Array and str(niche[4]) == "hidden":
			return Vector2i(int(niche[0]), int(niche[1]))
	return Vector2i(-1, -1)


func _test_arrival_rule() -> void:
	print("
== layout sense: no arrival inside a fight (832) ==")
	var spawn := Vector2i(20, 20)
	var at := func(entities: Array) -> Array:
		return LAYOUT_SENSE.arrival_faults({"spawn_points": {"from_test": spawn}, "entities": entities})
	var guard := {"tile": Vector2i(29, 20), "home": Vector2i(29, 20), "kind": "brute", "idle": {"mode": "guard"}}
	var guard_far := {"tile": Vector2i(30, 20), "home": Vector2i(30, 20), "kind": "brute", "idle": {"mode": "guard"}}
	var wanderer := {"tile": Vector2i(32, 24), "home": Vector2i(32, 24), "kind": "robber"}
	var wanderer_far := {"tile": Vector2i(33, 20), "home": Vector2i(33, 20), "kind": "robber"}
	var draugr := {"tile": Vector2i(21, 20), "home": Vector2i(21, 20), "kind": "draugr"}
	var patrol := {"tile": Vector2i(40, 20), "home": Vector2i(40, 20), "kind": "sneak", "idle": {"mode": "patrol", "route": [Vector2i(40, 20), Vector2i(25, 20)]}}
	_check(at.call([guard]).size() == 1 and at.call([guard_far]).is_empty(), "a standing foe 9 cells off is a fault, 10 off is not (%s)" % [at.call([guard])])
	_check(at.call([wanderer]).size() == 1 and at.call([wanderer_far]).is_empty(), "a wanderer 12 off is a fault (its reach 3 more), 13 off is not")
	_check(at.call([draugr]).is_empty(), "the seated draugr beside an arrival is no fight")
	_check(at.call([patrol]).size() == 1, "a patrol's waypoint 5 off is a fault though its post is 20 off")
	_check(LAYOUT_SENSE.RULES.has("arrival"), "arrival is one of layout sense's rules")
	var holding: Array[String] = []
	var as_held: bool = Regen.layout_options({"held": ["door", "arrival"]}).get("arrival") == true and Regen.layout_options({"held": ["door"]}).get("arrival") == false
	for level_name: String in Regen.marked_levels():
		var block := Regen.config_of(level_name)
		as_held = as_held and Regen.layout_options(block).get("arrival") == ("arrival" in (block.get("held", []) as Array))
		if "arrival" in (block.get("held", []) as Array):
			holding.append(level_name)
	_check(as_held, "checked in generation only where a block holds it (806 amended (11): off till 832's switch-on holds it in both barrow depths; held now: %s)" % [holding])
	# A block holding it: the crypt lays its monsters clear of the arrivals
	# (the barrow, from_breach left out: main's unused one sits in the camp
	# till 832 moves it), and a try with an arrival fault is never laid (an
	# arrival put in the camp, by its robbers).
	var prepared := Regen.prepare("barrow")
	if not "arrival" in (prepared["config"]["held"] as Array):
		(prepared["config"]["held"] as Array).append("arrival")
	var kept: Dictionary = prepared["made"]["config"]["spawn_points"].duplicate()
	kept["in_camp"] = [10, 45]
	prepared["made"]["config"]["spawn_points"].erase("from_breach")
	prepared["config"]["arrivals"].erase("from_breach")
	var clear := true
	for generation in [1, 2, 3]:
		var made := Regen.generate_prepared(prepared, generation)
		clear = clear and not made.is_empty() and Regen.layout_faults(made, prepared["config"]).all(func(f: Dictionary) -> bool: return f["rule"] != "arrival")
	_check(clear, "a barrow held to it: generations 1-3 laid with every arrival clear, the crypt laying its robbers clear")
	prepared["made"]["config"]["spawn_points"] = kept
	_check(Regen.generate_prepared(prepared, 1).is_empty(), "and with an arrival no try can clear (one in the robbers' camp), none is laid: the last laid copy stands")
	# The rule's scope (the coordinator): every level a player can reach, laid
	# by hand or a template, its arrivals clear: each start, and each spawn
	# point some link names (main's barrow from_breach, named by none till
	# 832, is not one); the test levels exempt, castle maps' to mend.
	var named := {}
	var folders := DirAccess.get_directories_at(Level.DIR)
	for folder: String in folders:
		var config := Level.template_config(folder)
		for link: Variant in config.get("links", []):
			if link is Dictionary:
				named["%s/%s" % [link.get("to_map", ""), link.get("to_spawn", "")]] = true
	var faulted: Array = []
	var read := 0
	for folder: String in folders:
		if folder in LAYOUT_SENSE.ARRIVAL_EXEMPT or LAYOUT_SENSE.ARRIVAL_NOT_YET.has(folder) or not FileAccess.file_exists(Level.DIR + folder + "/layout.png") or not FileAccess.file_exists(Level.DIR + folder + "/level.json"):
			continue
		read += 1
		var made := Level.template(folder)
		var laid := Level.parse(made["layout"], made.get("height"), made["config"], made.get("relief"))
		var reached := {}
		for spawn_name: Variant in laid.get("spawn_points", {}):
			if named.has("%s/%s" % [folder, spawn_name]):
				reached[spawn_name] = laid["spawn_points"][spawn_name]
		laid["spawn_points"] = reached
		for fault: Dictionary in LAYOUT_SENSE.arrival_faults(laid, str(Regen.config_of(folder).get("foes_door", ""))):
			faulted.append("%s: %s" % [folder, fault["what"]])
	_check(read >= 15 and faulted.is_empty(), "every level a player reaches (%d read; sample and test_room exempt, castle maps' to mend) has its arrivals clear (%s)" % [read, faulted])
	var castle := Level.template("castle")
	_check(not LAYOUT_SENSE.arrival_faults(Level.parse(castle["layout"], castle.get("height"), castle["config"], castle.get("relief"))).is_empty(),
		"castle's arrivals still want mending (drop it from ARRIVAL_NOT_YET once maps has)")


## 832 (the coordinator's ruling): the quick way down kept. The First Hall's
## sealed link at (30,8) to barrow_deep / from_temple, sealed "draugr",
## replaces the wilds temple's stair as the reward for beating him. It reads
## as a shut way (the slab cue the temple stair had, no words), and a player
## whose saved record already holds the mark finds it open from the first
## build it is in. 896 switched on (the full circle; Jeff: "drop the short
## cut in") took it out of the barrow; the sealed way stays a level.json
## link of any level, tried here on a copy of the barrow (HALL_SHORTCUT).
const HALL_SHORTCUT := {"at": [30, 8], "to_map": "barrow_deep", "to_spawn": "from_temple", "sealed": "draugr"}
func _test_hall_shortcut() -> void:
	print("
== the First Hall's sealed way down (832) ==")
	var level_name := "barrow"
	var template := Level.template("barrow")
	var config: Dictionary = (template["config"] as Dictionary).duplicate(true)
	if not (config["links"] as Array).any(func(l: Dictionary) -> bool: return l["at"] == HALL_SHORTCUT["at"]):
		var layout: Image = (template["layout"] as Image).duplicate()
		layout.set_pixel(HALL_SHORTCUT["at"][0] * 2, HALL_SHORTCUT["at"][1] * 2, Color("#ff00ff"))
		config["links"].append(HALL_SHORTCUT.duplicate(true))
		level_name = "hall_shortcut_test"
		Level.register(level_name, layout, template.get("height"), config)
	var level := Level.parse(Level.template(level_name)["layout"], Level.template(level_name).get("height"), config)
	var link: Dictionary = {}
	for each: Dictionary in level["links"]:
		if each["tile"] == Vector2i(30, 8):
			link = each
	var cue: Dictionary = {}
	for each: Dictionary in level["terrain"]["link_cues"]:
		if each["tile"] == Vector2i(30, 8):
			cue = each
	_check(link.get("to_map") == "barrow_deep" and link.get("to_spawn") == "from_temple" and link.get("sealed") == "draugr"
			and level_name == "hall_shortcut_test" and level["warnings"].is_empty(),
		"the First Hall's way down at (30,8): to the Ossuary's from_temple, sealed by the draugr (%s, %s)" % [link, level["warnings"]])
	_check(cue.get("cue") == "sealed" and not cue.has("words") and not cue.has("text"),
		"it reads as a shut way: the sealed slab, no words (%s)" % [cue])
	var id: String = _main._peer_ids.get(Net.local_id, "")
	var record: PlayerRecord = _main._records.get(id)
	if record == null:
		_check(false, "a player record to try the way with")
		return
	var kept_marks := record.marks.duplicate()
	var kept_hers: Variant = record.companion.get("marks", []).duplicate()
	record.companion["marks"] = []
	record.marks.assign([])
	_check(not _main.sealed_open(link, Net.local_id), "unmarked, the way stays shut")
	record.marks.assign(["draugr"])
	var saved := PlayerRecord.from_dict(record.to_dict().merged({"player_id": record.player_id}))
	_main._records[id] = saved
	_check("draugr" in saved.marks and _main.sealed_open(link, Net.local_id),
		"a player who beat him before the build (the mark in their saved record) finds it open")
	_main._records[id] = record
	record.marks.assign(kept_marks)
	record.companion["marks"] = kept_hers


## The crypt bar (crypt_bar.md section 5; the coordinator's picks P1 and O1):
## the band's posts kept out of each other's join reach (barrow "apart"
## robber [10, 7], Labyrinth.in_sight; main's 4 had 10-19 pairs inside the
## reach on generations 1-8, up to 6 at one post), and the Ossuary's packs
## kept 11 apart wall or no wall, so no two of its rooms wake together (on
## main, two packs within 10 on g1-5, 7 and 118). The first robber a player
## meets from the chapel stair stands alone (the held "first" rule; playtest's
## walk on v0.1.211: four came within 6 s of the first).
func _test_crypt_spacing() -> void:
	print("
== the crypt bar: band posts out of join reach, the Ossuary's packs apart ==")
	var pairs := {}
	var most := 0
	var unalone := {}
	var known := {}
	var was := str(World.zone.name)
	for generation in range(1, 9):
		var made := Regen.generate("barrow", generation)
		var map := LevelMap.from_image(made["layout"], made["config"])
		var posts: Array[Vector2i] = []
		for cell: Vector2i in map.cells:
			if map.cells[cell] in ["monster_robber", "monster_robber_brute"]:
				posts.append(cell)
		var count := 0
		for a in posts:
			var near := 0
			for b in posts:
				if a != b and LABYRINTH._too_near(map, a, b, 10, 7):
					near += 1
					count += 1
			most = maxi(most, near)
		pairs[generation] = count / 2
		var level := Level.parse(made["layout"], made["height"], made["config"])
		var walks := LAYOUT_SENSE.band_walks(level, ["robber", "robber_brute"], Regen.first_alone(made["config"].get("regenerate", {})), "from_breach")
		var met: Array = walks.get("from_chapel", [])
		if met.is_empty() or not (met[0]["callers"] as Array).is_empty():
			unalone[generation] = met[0] if not met.is_empty() else "no post met"
		# 870 with 806 amended (17): the band's own measure on the laid level
		# (Monster.knows_of_fight: heard within RALLY_HEAR, seen within
		# RALLY_SEE in World's line of sight). No mate knows of the first
		# post's fight, so the rally never answers it; if the grid's in_sight
		# and World's sight ever part, this says so.
		World.load_terrain(level["terrain"])
		var mates := {}
		for arrival: String in walks:
			for post: Dictionary in walks[arrival]:
				mates[post["at"]] = true
		if not met.is_empty():
			var first: Vector2i = met[0]["at"]
			var knowing: Array = mates.keys().filter(func(cell: Vector2i) -> bool: return cell != first and Monster.knows_of_fight(cell, first))
			if not knowing.is_empty():
				known[generation] = [first, knowing]
	_check(pairs.values().all(func(n: int) -> bool: return n <= 8) and most <= 4,
		"the barrow's generations 1-8: at most 8 band pairs inside the join reach and 4 at one post (pairs %s, most %d; main's 4 apart had 10-19 and 6)" % [pairs, most])
	_main.load_map(was)
	_check(Regen.first_alone({"held": ["first"]}) == [Monster.RALLY_SEE, Monster.RALLY_HEAR] and Regen.first_alone({}).is_empty(),
		"the first-alone rule reads the band's rally, seen and heard, from the AI's own constants (806 amended (17)): %s" % [Regen.first_alone({"held": ["first"]})])
	_check(unalone.is_empty(), "the barrow's generations 1-8: the first robber met from the chapel stair has no other post within the rally's reach, %d in sight, %d through a wall (870, first-alone; %s)" % [Monster.RALLY_SEE, Monster.RALLY_HEAR, unalone])
	_check(known.is_empty(), "the barrow's generations 1-8, laid: no mate of the band knows of the first post's fight by the rally's own measure (Monster.knows_of_fight), so none answers it (%s)" % [known])
	var near_packs := {}
	for generation: int in [1, 2, 3, 4, 5, 6, 7, 8, 109, 118]:
		var made := Regen.generate("barrow_deep", generation)
		var packs := {}
		for spec: Dictionary in made["config"].get("entities", []):
			var id := str(spec.get("props", {}).get("pack", ""))
			if not id.is_empty():
				(packs.get_or_add(id, []) as Array).append(Vector2i(spec["at"][0], spec["at"][1]))
		var ids := packs.keys()
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				for a: Vector2i in packs[ids[i]]:
					for b: Vector2i in packs[ids[j]]:
						if maxi(absi(a.x - b.x), absi(a.y - b.y)) <= 10:
							near_packs[generation] = [a, b]
		if ids.size() != 3:
			near_packs[generation] = "%d packs" % ids.size()
	_check(near_packs.is_empty(), "the Ossuary's generations 1-8, 109 and 118: three packs, no two within 10 cells (%s)" % [near_packs])


## 832 (the crypt's ways in): the deep laid by the crypt generator, its
## "deep" block (the switch-on's keys, DEEP_SWITCH, until barrow_deep
## carries them): generations 1-6 each with an ossuary and tomb chambers
## only, the wing old_graves of two rooms or more (or none), the
## block's guard packs whole (one shared "pack" each, three of three), the
## draugr in the lair, both links kept, no torches out of the anchors, and
## no fault of any layout rule, where the old caverns have a dozen.
const DEEP_SWITCH := {"generator": "crypt", "heart": "lair", "deep": {"wing": "old_graves"}, "chests": 3,
	"held": ["door", "purpose", "wrap", "dead_end", "spine", "loop", "chest", "coop", "arrival"]}
## 806 amended (15): a chest only where its guard can stand. On main the
## barrow kept an unguarded cache chest on generations 56, 191 and 215 (the
## saturn sweep, 3 of 300), each in a room by from_below inside the arrival
## rule's reach; now no chest goes to such a room and a kept chest fault
## ranks worst, so each lays every chest guarded: three, or fewer where too
## few rooms can hold a guard (191 lays two; the saturn sweep, 6 of 300 short,
## main 2).
func _test_chest_guardable() -> void:
	print("
== a chest only where its guard can stand (806 amended (15)) ==")
	var kept := {}
	var counted := {}
	for generation: int in [56, 191, 215, 1, 2]:
		var made := Regen.generate("barrow", generation)
		var block := Regen.config_of("barrow")
		var chests := (made["config"].get("entities", []) as Array).filter(func(spec: Dictionary) -> bool:
			return str(spec.get("props", {}).get("cache", "")) == str(block.get("cache", "")))
		var faults := Regen.held_faults(made, block, block.get("held", [])).filter(func(fault: Dictionary) -> bool: return fault["rule"] == "chest")
		counted[generation] = chests.size()
		if not faults.is_empty() or chests.is_empty() or chests.size() > int(block.get("chests", 0)):
			kept[generation] = [chests.size(), faults.map(func(fault: Dictionary) -> String: return str(fault["what"]))]
	_check(kept.is_empty(), "the barrow's generations 56, 191, 215 (main's unguarded three), 1 and 2: every cache chest guarded, at most the block's three, fewer where too few rooms can hold a guard (%s; laid %s)" % [kept, counted])


func _test_deep_crypt() -> void:
	print("
== the deep laid as a crypt (832) ==")
	var template := Level.template("barrow_deep")
	var config: Dictionary = (template["config"] as Dictionary).duplicate(true)
	if not config["regenerate"].has("deep"):
		config["regenerate"].merge(DEEP_SWITCH, true)
	Level.register("deep_crypt_test", template["layout"], template.get("height"), config)
	var block: Dictionary = config["regenerate"]
	_check(LAYOUT_SENSE.RULES.all(func(rule: String) -> bool: return rule in block.get("held", [])),
		"the deep holds every layout rule (step 4; %s)" % [block.get("held")])
	for generation in range(1, 7):
		var made := Regen.generate("deep_crypt_test", generation)
		if made.is_empty():
			_check(false, "deep crypt generation %d made" % generation)
			continue
		var laid_config: Dictionary = made["config"]
		var level := Level.parse(made["layout"], made["height"], laid_config)
		var uses := {}
		var wing: Array = []
		for laid: Dictionary in laid_config.get("laid_rooms", []):
			uses[laid["use"]] = int(uses.get(laid["use"], 0)) + 1
			if laid.has("wing"):
				wing.append(laid)
		var packs := {}
		var kinds := {}
		for spec: Dictionary in level["entities"]:
			kinds[str(spec.get("kind", ""))] = int(kinds.get(str(spec.get("kind", "")), 0)) + 1
			var id := str((spec.get("props", {}) as Dictionary).get("pack", ""))
			if not id.is_empty():
				packs[id] = int(packs.get(id, 0)) + 1
		var rooms_ok: bool = int(uses.get("ossuary", 0)) == 1 and int(uses.get("tomb_chamber", 0)) >= 4 			and uses.keys().all(func(use: String) -> bool: return use in ["ossuary", "tomb_chamber", "entrance", "lair"])
		var wing_ok: bool = wing.is_empty() or (wing.size() >= 2 and wing.all(func(laid: Dictionary) -> bool: return laid["wing"] == "old_graves"))
		var packs_ok: bool = packs.size() == 3 and packs.values().all(func(n: int) -> bool: return n == 3)
		var links: Array = level["links"].map(func(link: Dictionary) -> Vector2i: return link["tile"])
		var torches := 0
		var map := LevelMap.from_image(made["layout"], laid_config)
		# The coordinator's condition on lit_way: the spine only; no torch in a
		# room (the Old Graves' among them); _torches lays none off the way.
		var in_rooms := {}
		for laid: Dictionary in laid_config.get("laid_rooms", []):
			for pair: Variant in laid.get("cells", []):
				in_rooms[Vector2i(int(pair[0]), int(pair[1]))] = true
		var stray: Array[Vector2i] = []
		for cell: Vector2i in map.cells:
			if map.cells[cell] == "torch" and not Level.in_anchors(Regen.config_of("deep_crypt_test")["anchors"], cell):
				torches += 1
				if in_rooms.has(cell):
					stray.append(cell)
		var faults: Array = LAYOUT_SENSE.check(level, laid_config.get("laid_rooms", []), Regen.layout_options(block))
		_check(rooms_ok and wing_ok and packs_ok and int(kinds.get("draugr", 0)) == 1 and Vector2i(49, 1) in links and not Vector2i(49, 77) in links
				and torches >= 4 and stray.is_empty() and faults.is_empty() and level["warnings"].is_empty(),
				"deep crypt generation %d: uses %s, the wing %d rooms, packs %s, the draugr, the stair up and no way behind the throne (896), %d torches along its way (lit_way, the Umbrage crypt follow-up), none in a room %s, faults %s %s"
				% [generation, uses, wing.size(), packs.values(), torches, stray, LAYOUT_SENSE.counts(faults), level["warnings"]])


## 714, dungeon's side (4): the barrow's robbers are enemy-ai's named band
## (716): each generation lays Brand the Ox (robber_brute) and the eight,
## each spawn named (Regen.band_of, Level.parse's "named").
func _test_band() -> void:
	print("
== the barrow's named band (714 (4)) ==")
	var want := ["brand", "crake", "fenn", "mott", "nabb", "rook", "sedge", "tull", "wicket"]
	var wrong: Array[String] = []
	for generation in range(1, 6):
		var made := Regen.generate("barrow", generation)
		if made.is_empty():
			wrong.append("g%d: not made" % generation)
			continue
		var level := Level.parse(made["layout"], made["height"], made["config"])
		var named := {}
		for spec: Dictionary in level["entities"]:
			if spec.has("named"):
				named[str(spec["named"])] = str(spec.get("kind", ""))
		var ids: Array = named.keys()
		ids.sort()
		if ids != want or named.get("brand") != "robber_brute" or named.values().count("robber") != 8:
			wrong.append("g%d: %s" % [generation, named])
		var knights := (level["entities"] as Array).filter(func(spec: Dictionary) -> bool: return spec.get("kind") == "astral_knight")
		if knights.size() != 1:
			wrong.append("g%d: %d fallen knights" % [generation, knights.size()])  # 747: he stays in the Altar Room.
		if (level["warnings"] as Array).any(func(w: String) -> bool: return "names an entity" in w):
			wrong.append("g%d warned: %s" % [generation, level["warnings"]])
	_check(wrong.is_empty(), "five generations: the nine named, Brand the brute and eight robbers, each a spawn, and the fallen knight (%s)" % [wrong])


## 742, amended (Jeff: "the chest only opens with a key from the boss and
## only hold gold once per player"): the barrow's camp holds the robbers'
## chest; it opens only with Brand's key (given to his slayer, used up),
## puts economy's camp gold into the purse once per player for good, then
## is empty.
func _test_camp_chest() -> void:
	print("
== the robbers' camp chest (742 amended): Brand's key, once per player ==")
	var camp: Dictionary = _main._camp_rules()
	var barrow := Level.load_level("barrow")
	var placed := (barrow.get("entities", []) as Array).filter(func(spec: Dictionary) -> bool:
		return spec.get("tile") == Vector2i(14, 43) and spec.get("props", {}).get("cache") == "robbers_camp")
	_check(int(camp.get("gold", 0)) == 25 and camp.get("lock") == "robbers_camp" and camp.get("cache") == "robbers_camp" and placed.size() == 1
		and Items.opens_of(Main.CAMP_KEY) == "robbers_camp"
		and not (barrow.get("warnings", []) as Array).any(func(w: String) -> bool: return "robbers_camp" in w),
		"economy's camp rule (25 gold, Brand's key's lock), the key opens it, and the chest in the barrow's camp (%s)" % [camp])
	var player := _player()
	if player == null:
		_check(false, "a player to search with")
		return
	var beside := Vector2i(-1, -1)
	for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if World.is_free(player.tile + step):
			beside = player.tile + step
			break
	if beside == Vector2i(-1, -1):
		print("  (no free cell beside the player: skipped)")
		return
	var chest := _main._spawn({"script": Level.CHEST, "shape": "cube", "name": "CampChestTest", "tile": beside,
		"props": {"cache": "robbers_camp", "cache_place": "the robbers' chest"}}) as Chest
	if chest == null:
		_check(false, "a camp chest spawned beside the player")
		return
	var id := str(player.player_id)
	var record: PlayerRecord = _main._records.get(id)
	var caches_were := record.caches.duplicate()
	record.caches.erase("robbers_camp")
	var gold_was := World.gold_of(id)
	_check(not _main.search(player, chest) and World.gold_of(id) == gold_was, "no key: locked, no gold (742 amended)")
	# Brand felled by them: his key in their pack.
	var brand := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "kind": "robber_brute", "name": "KeyBrand%d" % World.tick,
		"tile": _main._nearest_free(player.tile + Vector2i(0, 2))}) as Monster
	brand.named_id = Main.CAMP_KEY_FROM
	brand.note_struck(player)
	World.damage(brand, 9999)
	var keys := func() -> int: return Array(player.slots).count(Main.CAMP_KEY)
	_check(keys.call() == 1 and _heard.slice(-1) == ["You take the key from Brand's belt."]
		and _main.party_log.last(4).has("%s takes the key from Brand's belt." % _main._display_name(player)),
		"Brand felled by them: his key in their pack, and said on their screen (%s %s)" % [player.slots, _heard.slice(-1)])
	var first: bool = _main.search(player, chest)
	var after_first := World.gold_of(id)
	_check(first and after_first == gold_was + 25 and keys.call() == 0 and "robbers_camp" in record.caches,
		"opened with his key: 25 gold to the purse, the key used up (%d -> %d)" % [gold_was, after_first])
	var brand2 := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "kind": "robber_brute", "name": "KeyBrand%d" % World.tick,
		"tile": _main._nearest_free(player.tile + Vector2i(0, 2))}) as Monster
	brand2.named_id = Main.CAMP_KEY_FROM
	brand2.note_struck(player)
	World.damage(brand2, 9999)
	_check(not _main.search(player, chest) and World.gold_of(id) == after_first and keys.call() == 1,
		"once per player for good: with another key, empty, the key kept")
	var rec2 := PlayerRecord.from_dict(JSON.parse_string(JSON.stringify(record.to_dict())))
	_check("robbers_camp" in rec2.caches, "the opening is saved with their record")
	for slot in player.slots.size():
		if player.slots[slot] == Main.CAMP_KEY:
			var slots := player.slots.duplicate()
			var uids := World.slot_uids(player)
			slots[slot] = ""
			uids[slot] = 0
			World.set_slots(player, slots, uids)
	World.add_gold(id, gold_was - World.gold_of(id), "test")
	record.caches.assign(caches_were)
	World.despawn(chest)


## 752, dungeon's side (the playtest's "AstralKnight1"): a monster is never
## called by its node name. [param knight] is the fallen knight, spawned.
func _test_monster_names(knight: AstralKnight) -> void:
	var node_name := RegEx.create_from_string("^[A-Za-z_]+\\d+$")
	var sir: String = _main.barrow_knight()
	var robber := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "kind": "robber", "name": "NameRobber%d" % World.tick,
		"tile": _main._nearest_free(knight.tile + Vector2i(0, 2))}) as Monster
	var words := []
	for monster: Monster in [knight, robber]:
		words.append(_main._display_name(monster))
		words.append(_main._speaker_name(monster))
	_check(words.all(func(word: String) -> bool: return node_name.search(word) == null and not word.is_empty()),
		"no node name for a monster, in a sentence or as a speaker: %s" % [words])
	_check(_main._display_name(knight) == (sir if not sir.is_empty() else Main.KNIGHT_UNNAMED)
		and _main._speaker_name(knight) == Main.capital_first(sir if not sir.is_empty() else Main.KNIGHT_UNNAMED),
		"the knight is the generation's sepulcher knight (%s)" % _main._speaker_name(knight))
	_check(_main._display_name(robber) == "the grave robber" and _main._speaker_name(robber) == "The grave robber",
		"an unnamed robber: \"the grave robber\", \"The grave robber\" as a speaker")
	robber.given_name = "Crake"
	_check(_main._display_name(robber) == "Crake" and _main._speaker_name(robber) == "Crake", "a named one by its given name (752)")
	var log := PartyLog.new()
	log.add("the draugr hits you.")
	_check(log.last(1) == ["The draugr hits you."], "a party-log line opening on a monster's name has its capital")
	World.despawn(robber)


## The fallen knight's quest (747; Jeff: "a astral projection of a fallen
## knight in the altar room that gives the quest ... stop the grave robbers
## and ill then give access to the crypt"; 747 amended (8): "at the
## beginning by the actual altar"): he stands in the First Hall behind its
## bier and is never hurt; his ask, the nine named robbers on the taker's
## list once each (own and own companion's kills, this generation's before
## the taking counted at it),
## the turn-in sets the flag and reveals the way; an old record loads as no
## quest; the reset clears it.
func _test_barrow_quest() -> void:
	print("
== the fallen knight's quest (747): his ask, the nine on the list, the turn-in, the way revealed ==")
	_main.altar_turn_in = false  # The turn-in's own end first; the altar step below (896, on since its switch-on).
	var barrow := Level.load_level("barrow")
	var knights := (barrow.get("entities", []) as Array).filter(func(spec: Dictionary) -> bool: return spec.get("kind") == "astral_knight")
	_check(knights.size() == 1 and knights[0]["script"] == "res://sim/astral_knight.gd" and knights[0]["tile"] == Vector2i(39, 10),
		"the barrow's First Hall has the fallen knight, behind its bier (747 amended (8)) (%s)" % [knights.map(func(k: Dictionary) -> Variant: return k.get("tile"))])
	var player := _player()
	var id := player.player_id
	var record: PlayerRecord = _main._records.get(id)
	if record == null:
		_check(false, "no record for the test player")
		return
	var kept := {"marks": record.marks.duplicate(), "task": record.barrow_task.duplicate(true)}
	_main.mark_player(id, Main.QUEST_DONE, false)
	record.barrow_task = {}
	_main._sync_quest(record)
	var band: Array = _main.band_ids("barrow")
	var knight := _main._spawn({"script": "res://sim/astral_knight.gd", "shape": "capsule", "kind": "astral_knight", "name": "QuestKnight%d" % World.tick,
		"tile": _main._nearest_free(player.tile + Vector2i(2, 0)), "props": Level.MONSTER_TYPES["astral_knight"].duplicate()}) as AstralKnight
	var hp := knight.hp
	World.damage(knight, 50, player)
	_check(knight.spawned and knight.hp == hp and knight.talks and knight.peaceable and _main.talks_peaceably(knight) and not knight.threatens(player),
		"he talks peaceably, threatens nobody, and a blow passes through him (%d -> %d)" % [hp, knight.hp])
	var ids := func() -> Array: return knight.offers_for(id).map(func(offer: Dictionary) -> String: return str(offer["id"]).get_slice(":", 2))
	_check(_main.barrow_quest_of(id) == "ask" and ids.call() == ["ask"] and player.quest.is_empty() and not _main.way_revealed(id, "barrow"),
		"a stranger: his ask, no quest yet, the way not revealed (%s)" % [ids.call()])
	_test_monster_names(knight)
	var sir: String = _main.barrow_knight()
	var asked := str(knight.offers_for(id)[0].get("words", ""))
	_check(asked == (AstralKnight.ASK_UNNAMED if sir.is_empty() else AstralKnight.ASK_WORDS % sir),
		"his ask names him, the generation's sepulcher knight (747 amended (2)): %s" % asked.get_slice(",", 0))
	var slay := func(named: String, by: GridEntity) -> void:
		var robber := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "kind": "robber", "name": "QuestRobber%d" % World.tick,
			"tile": _main._nearest_free(player.tile + Vector2i(0, 2))}) as Monster
		robber.named_id = named
		if by != null:
			robber.note_struck(by)
		World.damage(robber, 999)
	# 747 amended (8) (the coordinator; Jeff reached the knight over the band's dead): a band
	# member felled this generation before the taking counts at it; nobody's kill does not.
	_main._plain_band_slain.clear()
	if _main._regen.has("barrow"):
		(_main._regen["barrow"] as Dictionary).erase("band_slain")
	slay.call(band[1], player)
	slay.call(band[1], player)
	slay.call(band[3], null)
	_check(record.barrow_task.is_empty() and _main._band_slain_by(id) == [band[1]],
		"%s felled twice before the taking (risen): kept once for the generation, not yet on a list (%s)" % [band[1], _main._band_slain_by(id)])
	var saved_slain: Variant = JSON.parse_string(JSON.stringify({"barrow": {"generation": 2, "at_step": 5, "band_slain": {band[1]: [id]}}}))
	_check(Regen.states_from(saved_slain)["barrow"].get("band_slain") == {band[1]: [id]},
		"whom they felled is saved and read back with the generation: a restart keeps it (747 amended (8))")
	_main._monster_accepts(knight, player, {"id": "quest:%d:ask" % knight.id}, 0)
	var took := {"ok": _main.barrow_quest_of(id) == "open"}
	_check(_heard.slice(-1) == ["You take up the fallen knight's task."] and _main.party_log.last(1) == ["%s takes up the fallen knight's task." % player.name],
		"the deal's line (the knight's taking) reaches the screens there, not the party log alone (%s)" % [_heard.slice(-1)])
	var items: Array = player.quest.get("items", [])
	_check(took["ok"] and _main.barrow_quest_of(id) == "open" and ids.call() == ["not_yet"]
		and player.quest.get("title") == Main.QUEST_TITLE and player.quest.get("giver") == "the fallen knight" and items.size() == 9
		and items[0] == {"name": "Brand the Ox", "done": false} and items[1]["done"] == true and items[3]["done"] == false
		and not bool(player.quest.get("ready", true)) and record.barrow_task.get("slain") == [band[1]],
		"taken: open, \"not yet\"; the tracker's nine, the one felled before checked, nobody's kill not (%s)" % [player.quest])
	# 747 amended (6): the card shows only in the quest's own place, named from the level data.
	_check(player.quest.get("zones") == ["barrow", "barrow_deep"] and _main.quest_zones() == ["barrow", "barrow_deep"],
		"its card's places: the band's barrow and its depths, the knight among them (%s)" % [player.quest.get("zones")])
	slay.call(band[1], player)
	slay.call(band[1], player)
	_check(record.barrow_task.get("slain") == [band[1]] and (player.quest["items"] as Array)[1]["done"] == true,
		"%s felled twice more (risen): on the list once, checked (%s)" % [band[1], record.barrow_task])
	slay.call(band[2], null)
	_check(not (band[2] in record.barrow_task.get("slain", [])), "a kill not theirs is not on their list")
	var old := record.to_dict()
	old.erase("barrow_task")
	_check(PlayerRecord.from_dict(JSON.parse_string(JSON.stringify(record.to_dict()))).barrow_task == record.barrow_task
		and PlayerRecord.from_dict(JSON.parse_string(JSON.stringify(old))).barrow_task.is_empty(),
		"saved and loaded the same; a record saved before 747 loads as no quest")
	_check(not knight.accept_offer(player, {"id": "quest:%d:turn_in" % knight.id}, 0)["ok"], "no turn-in before all nine")
	for named: String in band:
		if named != band[1]:
			slay.call(named, player)
	_check(_main.barrow_quest_of(id) == "ready" and ids.call() == ["turn_in"] and bool(player.quest.get("ready", false))
		and (player.quest["items"] as Array).all(func(item: Dictionary) -> bool: return item["done"]),
		"all nine: ready, the turn-in, every box checked")
	var turned: Dictionary = knight.accept_offer(player, {"id": "quest:%d:turn_in" % knight.id}, 0)
	_check(turned["ok"] and Main.QUEST_DONE in record.marks and record.barrow_task.is_empty() and player.quest.is_empty()
		and _main.barrow_quest_of(id) == "" and ids.call() == ["done"] and _main.way_revealed(id, "barrow"),
		"turned in: the flag set, the tracker gone, the way revealed to them, only his closing words offered")
	# 747 amended (5) (Jeff on v0.1.197: "fallen knight was not interactable"): done, a click
	# still opens his window: DONE alone, accept "none", no gold; no record, nothing.
	var closing: Array = knight.offers_for(id)
	_check(closing.size() == 1 and closing[0]["words"] == AstralKnight.DONE and closing[0]["accept"] == AstralKnight.WORDS_ONLY
		and str(closing[0]["title"]).is_empty() and int(closing[0]["cost"]) == 0 and DealPanel.is_quest(closing[0])
		and knight.offers_for("no-such-player").is_empty(),
		"done, his window still opens: his closing words alone, accept \"none\" (%s)" % [closing])
	_check(_main.reset_barrow(id).has("the fallen knight's quest") and _main.barrow_quest_of(id) == "ask" and not _main.way_revealed(id, "barrow"),
		"the reset (quests reset all's reset_barrow): the flag cleared, his ask again")
	_check(_main._band_slain_by(id).is_empty(), "and the reset forgets whom they felled this generation (747 amended (8))")
	for named: String in band:
		slay.call(named, player)
	var over_the_dead: Dictionary = knight.accept_offer(player, {"id": "quest:%d:ask" % knight.id}, 0)
	_check(over_the_dead["ok"] and _main.barrow_quest_of(id) == "ready" and ids.call() == ["turn_in"] and bool(player.quest.get("ready", false)),
		"taken over the whole band felled first: straight to ready, the turn-in offered (747 amended (8))")
	# 896 ("full circle"): the altar step on, the turn-in goes on to his remains, laid by his row.
	_drop_relics(player)  # An earlier case's remains (714 amended (3)) are not his to lay here.
	_main.altar_turn_in = true
	var revealed: Dictionary = knight.accept_offer(player, {"id": "quest:%d:turn_in" % knight.id}, 0)
	_check(revealed["ok"] and _main.barrow_quest_of(id) == "altar" and not (Main.QUEST_DONE in record.marks) and ids.call() == ["await"]
		and player.quest.get("items", []) == [{"name": Main.ALTAR_STEP, "done": false}] and not bool(player.quest.get("ready", true))
		and str(knight.offers_for(id)[0]["words"]) == AstralKnight.AWAIT,
		"altar on, turned in: not yet done, the card's one step to the altar, his words that the remains wait (%s)" % [player.quest])
	slay.call(band[2], player)
	_check(not record.barrow_task.has("slain"), "a robber felled after the turn-in counts nowhere (%s)" % [record.barrow_task])
	var relic := World.mint_relic(sir if not sir.is_empty() else "Sir Test", 0, player)
	World.into_pack(player, relic)
	_main._sync_quest(record)
	_check(_main.barrow_quest_of(id) == "carried" and ids.call() == ["lay"] and bool(player.quest.get("ready", false))
		and str(knight.offers_for(id)[0]["title"]) == AstralKnight.LAY_TITLE,
		"his remains in the pack: carried, his row to lay them, the card ready (%s)" % [ids.call()])
	var laid: Dictionary = knight.accept_offer(player, {"id": "quest:%d:lay" % knight.id}, 0)
	_check(laid["ok"] and Main.QUEST_DONE in record.marks and record.barrow_task.is_empty() and player.quest.is_empty()
		and _main.knights_relic_slot(player) < 0 and str(knight.offers_for(id)[0]["words"]) == AstralKnight.DONE_LAID
		and knight.remains_laid and knight.spawn_spec["props"].get("remains_laid") == true,
		"laid by his row: the remains gone from the pack, the quest done, the card closed, his thanks after (%s)" % [laid])
	_main.altar_turn_in = false
	_main.reset_barrow(id)
	World.despawn(knight)
	for state: Dictionary in _main._regen.values() + [_main._plain_band_slain]:
		state.erase("remains_laid")  # The bier bare again for the tests after (remains_laid_in).
	for slot in player.slots.size():
		if player.slots[slot] == Main.CAMP_KEY:  # Brand's, from the nine.
			var slots := player.slots.duplicate()
			var uids := World.slot_uids(player)
			slots[slot] = ""
			uids[slot] = 0
			World.set_slots(player, slots, uids)
	record.marks.assign(kept["marks"])
	record.barrow_task = kept["task"]
	_main.altar_turn_in = true
	_main._sync_quest(record)


## 747 amended (6) with ui's half (747 amended (7)): a taken quest carries
## its zones to the player and the HUD's own card (Main.quest_panel, ui's
## QuestPanel, reading the local player as the client does) shows only on
## the crypt's two floors: travelled to each place as a player is, the card
## drawn in the barrow and barrow_deep, gone in the bear's cave and the wilds
## (Umbrage).
func _test_quest_card_place() -> void:
	print("
== the quest card only in its own place (747 amended (6)): the HUD's card, place by place ==")
	var player := _player()
	if player == null or _main.quest_panel == null:
		_check(false, "a player and the HUD's quest card to test with")
		return
	var id := player.player_id
	var record: PlayerRecord = _main._records.get(id)
	var was := str(World.zone.name)
	var kept := {"marks": record.marks.duplicate(), "task": record.barrow_task.duplicate(true)}
	_main.mark_player(id, Main.QUEST_DONE, false)
	record.barrow_task = {"taken": true, "slain": []}
	var seen := {}
	var joined := {}
	for place: String in ["barrow", "barrow_deep", "bear_cave", "wilds"]:
		_main.load_map(place)
		var here := _player()
		_main._sync_quest(record)
		_main.quest_panel.step(1.0)
		_main.quest_panel.step(1.0)
		seen[place] = [here.zone if here != null else "", (here.quest.get("zones", []) if here != null else []), _main.quest_panel.visible]
		# 747 amended (9): as a joined client stands here. Its World.zone has
		# no name and its bodies none (World.spawn writes the zone's); the
		# level loaded names the place. The host-only check above passed while
		# the card hid everywhere on a client (playtest's walk on b411043ec).
		var zone_name := str(World.zone.name)
		var body_zone := here.zone if here != null else ""
		World.zone.name = ""
		if here != null:
			here.zone = ""
		_main.quest_panel.step(1.0)
		_main.quest_panel.step(1.0)
		joined[place] = [_main._quest_zone(), _main.quest_panel.visible]
		World.zone.name = zone_name
		if here != null:
			here.zone = body_zone
	_check(seen["barrow"][2] and seen["barrow_deep"][2] and not seen["bear_cave"][2] and not seen["wilds"][2]
		and seen.values().all(func(row: Array) -> bool: return row[1] == ["barrow", "barrow_deep"]),
		"the card on both crypt floors, gone in the bear's cave and the wilds; the quest's zones reach the player in each (%s)" % [seen])
	_check(joined["barrow"] == ["barrow", true] and joined["barrow_deep"] == ["barrow_deep", true]
		and joined["bear_cave"] == ["bear_cave", false] and joined["wilds"] == ["wilds", false],
		"a joined client (its zone unnamed, its body's too): the card on both crypt floors, gone in the bear's cave and the wilds (Umbrage), each place named by the level loaded (%s)" % [joined])
	record.marks.assign(kept["marks"])
	record.barrow_task = kept["task"]
	_main.load_map(was)
	_main._sync_quest(record)


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


## Steps the world until [param entity] may move again.
func _wait_for_step(entity: GridEntity) -> void:
	for i in 10:
		if World.tick >= entity.next_move_tick and not World.is_stunned(entity):
			return
		World.step()


## The tower's floors (659): the sample tower in memory, each floor parsing
## clean, the stairs linking floor to floor both ways with their cues up and
## down, the foot's door out an arch and its way down to the mine sealed.
func _test_tower_levels() -> void:
	print("
== the tower's floors (659): stairs both ways, the door and the sealed hatch at the foot ==")
	var floors := Sheet.TOWER_FLOORS
	for floor in range(1, floors + 1):
		var sample := Sheet.sample_tower(floor, floors, "lt_tower")
		Level.register("lt_tower_%d" % floor, sample["layout"], null, sample["config"])
	var c := Sheet.TOWER_ACROSS / 2
	var cue_at := func(level: Dictionary, at: Vector2i) -> String:
		for cue: Dictionary in level["terrain"]["link_cues"]:
			if cue["tile"] == at:
				return str(cue["cue"])
		return ""
	var link_at := func(level: Dictionary, at: Vector2i) -> Dictionary:
		for link: Dictionary in level["links"]:
			if link["tile"] == at:
				return link
		return {}
	for floor in range(1, floors + 1):
		var level := Level.load_level("lt_tower_%d" % floor)
		_check(not level.is_empty() and level["warnings"].is_empty() and level["size"] == Vector2i(Sheet.TOWER_ACROSS, Sheet.TOWER_ACROSS)
			and Regen.marked("lt_tower_%d" % floor) and Regen.config_of("lt_tower_%d" % floor).get("style") == "tower",
			"floor %d parses with no warning, marked to regenerate in the tower style (%s)" % [floor, level.get("warnings")])
		if floor < floors:
			var above := Level.load_level("lt_tower_%d" % (floor + 1))
			var up: Dictionary = link_at.call(level, Vector2i(c + 1, c))
			_check(up.get("to_map") == "lt_tower_%d" % (floor + 1) and up.get("to_spawn") == "from_below" and cue_at.call(level, Vector2i(c + 1, c)) == "up"
				and above["spawn_points"].get("from_below") == Vector2i(c - 1, c + 1) and above["terrain"]["floor"].has(Vector2i(c - 1, c + 1)),
				"floor %d's stair up (cue up) leads to floor %d's from_below, a floor cell beside its stair down (%s)" % [floor, floor + 1, up])
		else:
			_check(link_at.call(level, Vector2i(c + 1, c)).is_empty(), "the top floor has no stair up")
		if floor > 1:
			var below := Level.load_level("lt_tower_%d" % (floor - 1))
			var down: Dictionary = link_at.call(level, Vector2i(c - 1, c))
			_check(down.get("to_map") == "lt_tower_%d" % (floor - 1) and down.get("to_spawn") == "from_above" and cue_at.call(level, Vector2i(c - 1, c)) == "down"
				and below["spawn_points"].get("from_above") == Vector2i(c + 1, c + 1) and below["terrain"]["floor"].has(Vector2i(c + 1, c + 1)),
				"floor %d's stair down (cue down) leads to floor %d's from_above, a floor cell beside its stair up (%s)" % [floor, floor - 1, down])
		else:
			_check(link_at.call(level, Vector2i(c - 1, c)).is_empty(), "the foot has no stair down")
			var door: Dictionary = link_at.call(level, Vector2i(c, Sheet.TOWER_ACROSS - 2))
			var arch: Array = level["terrain"]["link_cues"].filter(func(cue: Dictionary) -> bool: return cue["tile"] == Vector2i(c, Sheet.TOWER_ACROSS - 2))
			_check(door.get("to_map") == "lt_tower_outside" and cue_at.call(level, Vector2i(c, Sheet.TOWER_ACROSS - 2)) == "arch"
				and arch.size() == 1 and arch[0]["variant"] == 3 and level["spawn_points"].get("from_outside") == Vector2i(c, Sheet.TOWER_ACROSS - 3),
				"the foot's door out at the south edge is the dark arch (variant 3) with from_outside inside it (%s)" % [door])
			var hatch: Dictionary = link_at.call(level, Vector2i(c, 2))
			_check(hatch.get("to_map") == "lt_tower_mine" and hatch.get("sealed") == "tower_mine" and cue_at.call(level, Vector2i(c, 2)) == "sealed",
				"the mine's way down under the north wall is a sealed link (%s)" % [hatch])


const LABYRINTH := preload("res://sim/level_gen/labyrinth.gd")
const LAYOUT_SENSE := preload("res://sim/layout_sense.gd")


## Layout sense in every generated map (the roadmap's step 4, dungeon
## leads): every level marked to regenerate holds all of layout_sense's
## rules (its block's "held", so Regen retries a try that faults), and
## its generations 1-4 lay with no fault of any rule. SENSE_NOT_YET names
## the ones still to come and what they wait on; a level there is checked
## all the same once its block holds every rule. SENSE_RULES_NOT_YET names
## a rule a level holds later, and on what; the level is checked on the rest.
const SENSE_NOT_YET := {"hollowfell": "the mine's spine and purpose faults, next in step 4"}
const SENSE_RULES_NOT_YET := {}
func _test_sense_everywhere() -> void:
	print("
== layout sense in every generated map (step 4) ==")
	var checked: Array[String] = []
	for level_name: String in Regen.marked_levels():
		if not FileAccess.file_exists(Level.DIR + level_name + "/level.json"):
			continue  # A test's level, registered in memory.
		var block: Dictionary = Regen.config_of(level_name)
		var held: Array = block.get("held", [])
		var later: Dictionary = SENSE_RULES_NOT_YET.get(level_name, {})
		var holds_all := LAYOUT_SENSE.RULES.all(func(rule: String) -> bool: return rule in held or later.has(rule))
		for rule: String in later:
			if not rule in held:
				print("  (not yet: %s's %s, %s)" % [level_name, rule, later[rule]])
		if not holds_all and SENSE_NOT_YET.has(level_name):
			print("  (not yet: %s, %s)" % [level_name, SENSE_NOT_YET[level_name]])
			continue
		checked.append(level_name)
		_check(holds_all, "%s holds every layout rule (%s)" % [level_name, held])
		var faults := {}
		var tries: Array[int] = []
		for generation in range(1, 5):
			var made := Regen.generate(level_name, generation)
			if made.is_empty():
				faults[generation] = "not made"
				continue
			tries.append(int(made.get("tries", 0)))
			var found: Array = Regen.layout_faults(made, block)
			if not found.is_empty():
				faults[generation] = LAYOUT_SENSE.counts(found)
		_check(faults.is_empty(), "%s generations 1-4 lay with no layout fault (tries %s; %s)" % [level_name, tries, faults])
	_check(checked.has("barrow") and checked.has("castle_halls"), "the barrow and the castle halls among them (%s)" % [checked])


## castle_halls under the layout rules (806 (c), the coordinator's plan):
## two generations, each room laid with a use; the cold forge, a broken
## rack and the relief laid; each use's main piece lit (a torch within
## four cells); every cache chest guarded (a monster within three cells),
## the brute at the armoury's; the forge (a refuge, its hoard tagged so)
## reached past a guard on its approach; the held rules clean, "prefer"
## spine and wrap reported.
func _test_castle_hold() -> void:
	print("\n== castle_halls (806 (c)): rooms with uses, lit pieces, guarded finds, a guard before the forge ==")
	var block: Dictionary = Regen.config_of("castle_halls")
	for generation in [1, 2]:
		var made := Regen.generate("castle_halls", generation)
		if made.is_empty():
			_check(false, "castle_halls generation %d is made" % generation)
			continue
		var config: Dictionary = made["config"]
		var map := LevelMap.from_image(made["layout"], config)
		var torches: Array[Vector2i] = []
		var monsters: Array[Vector2i] = []
		for cell: Vector2i in map.cells:
			if map.cells[cell] == "torch":
				torches.append(cell)
			elif str(map.cells[cell]).begins_with("monster_"):
				monsters.append(cell)
		var lit := func(at: Vector2i) -> bool: return torches.any(func(t: Vector2i) -> bool: return _cells_apart(t, at) <= 5)
		var uses := {}
		for room: Dictionary in config.get("laid_rooms", []):
			uses[str(room["use"])] = int(uses.get(str(room["use"]), 0)) + 1
		var unused: Array = config.get("laid_rooms", []).filter(func(room: Dictionary) -> bool: return str(room.get("use", "")).is_empty())
		var slots := {}
		var dark: Array = []
		for building: Dictionary in config.get("buildings", []):
			var slot := "%s v%d" % [building["slot"], int(building.get("variant", 1))]
			slots[slot] = true
			if slot == "building.set_cold_forge v1" and not lit.call(Vector2i(int(building["at"][0]), int(building["at"][1]))):
				dark.append(slot)
			if slot == "building.weapon_rack v2" and lit.call(Vector2i(int(building["at"][0]), int(building["at"][1]))):
				slots["armoury lit"] = true
		var reliefs: Array = config.get("decor", []).filter(func(row: Array) -> bool: return row[4] == "relief")
		for row: Array in reliefs:
			if not lit.call(Vector2i(int(row[0]), int(row[1]))):
				dark.append("relief")
		_check(unused.is_empty() and uses.has("guardroom") and uses.has("armoury") and uses.has("store") and uses.has("cold_forge")
				and uses.has("relief_hall") and slots.has("building.set_cold_forge v1") and slots.has("building.weapon_rack v2")
				and reliefs.size() == 1 and dark.is_empty() and slots.has("armoury lit"),
				"castle_halls generation %d: every room a use, the cold forge, a broken rack and the relief laid, each lit (%s; dark %s)" % [generation, uses, dark])
		var unguarded: Array = []
		var tables := {}
		for entity: Dictionary in config.get("entities", []):
			var props: Dictionary = entity.get("props", {})
			# The forge's store (813 amended (4)): kept by its shutter, no guard's.
			if not props.has("cache") or props.get("cache_place") == LABYRINTH.FORGE_PLACE:
				continue
			var at := Vector2i(int(entity["at"][0]), int(entity["at"][1]))
			tables[str(props["cache"])] = true
			if not monsters.any(func(m: Vector2i) -> bool: return maxi(absi(m.x - at.x), absi(m.y - at.y)) <= 3):
				unguarded.append(at)
		# 806 amended (5): every cache chest has a guard on its post within 3.
		var posts: Array[Vector2i] = []
		for row: Dictionary in config.get("entities", []):
			if (row.get("idle", {}) as Dictionary).get("mode", "") == "guard":
				posts.append(Vector2i(int(row["at"][0]), int(row["at"][1])))
		for entity: Dictionary in config.get("entities", []):
			if (entity.get("props", {}) as Dictionary).has("cache") and entity["props"].get("cache_place") != LABYRINTH.FORGE_PLACE:
				var spot := Vector2i(int(entity["at"][0]), int(entity["at"][1]))
				if not posts.any(func(p: Vector2i) -> bool: return _cells_apart(p, spot) <= 3):
					unguarded.append(spot)
		_check(unguarded.is_empty() and tables.has("armoury") and tables.has("castle_cache"),
				"castle_halls generation %d: each find guarded, the armoury's chest its own table (%s; unguarded %s)" % [generation, tables.keys(), unguarded])
		# The refuge's approach: a monster within two cells of the walk's
		# last eight cells before the forge.
		var forge := Rect2i()
		var stair := Rect2i()
		for anchor: Dictionary in block.get("anchors", []):
			var rect: Rect2i = anchor["rect"] if anchor["rect"] is Rect2i else Rect2i(int(anchor["rect"][0]), int(anchor["rect"][1]), int(anchor["rect"][2]), int(anchor["rect"][3]))
			if anchor["name"] == "forge":
				forge = rect
			elif anchor["name"] == "stair_foot":
				stair = rect
		var path := LABYRINTH._path_to(map, stair.position + stair.size / 2, forge.position + forge.size / 2)
		var enter := -1
		for index in path.size():
			if forge.has_point(path[index]):
				enter = index
				break
		var before := path.slice(maxi(0, enter - 8), maxi(0, enter))
		var watched := before.any(func(cell: Vector2i) -> bool: return monsters.any(func(m: Vector2i) -> bool: return maxi(absi(m.x - cell.x), absi(m.y - cell.y)) <= 2))
		var refuge: Array = config.get("entities", []).filter(func(entity: Dictionary) -> bool: return (entity.get("props", {}) as Dictionary).get("role", "") == "refuge")
		_check(enter > 0 and watched and refuge.size() == 2,
				"castle_halls generation %d: the forge (a refuge, its hoard tagged so) is reached past a guard on its approach (%d steps)" % [generation, enter])
		# 813 amended (4), switched on (its pieces, sounds and flare in): the
		# cold forge's set in every generation, its store the forge_cache table.
		_check(block.get("coop_forge", false) == true and block.get("forge_cache") == "forge_cache",
				"castle_halls generation %d: the block wakes the cold forge, its store forge_cache (%s, %s)" % [generation, block.get("coop_forge"), block.get("forge_cache")])
		_check_cold_forge(generation, made, block, monsters)
		_check_sneak_pack(generation, map, config)


## Sneak packs (823, dungeon's side, amended) in castle_halls generation
## [param generation]: the three sneaks one pack, wandering one guardroom,
## each with the same "pack"; or, with no guardroom of two ways in, none and
## seven imps. Eight foes either way.
func _check_sneak_pack(generation: int, map: LevelMap, config: Dictionary) -> void:
	var sneaks: Array[Vector2i] = []
	var count := 0
	var imps := 0
	for cell: Vector2i in map.cells:
		var what := str(map.cells[cell])
		if what.begins_with("monster_"):
			count += 1
		if what == "monster_sneak":
			sneaks.append(cell)
		elif what == "monster_imp":
			imps += 1
	var rows := {}
	for row: Dictionary in config.get("entities", []):
		if row.get("at") is Array:
			rows[Vector2i(int(row["at"][0]), int(row["at"][1]))] = row
	var packs := {}
	var wander := true
	for cell in sneaks:
		var row: Dictionary = rows.get(cell, {})
		packs[str((row.get("props", {}) as Dictionary).get("pack", ""))] = true
		wander = wander and (row.get("idle", {}) as Dictionary).get("mode") == "wander"
	var rooms := 0
	for laid: Dictionary in config.get("laid_rooms", []):
		var inside := {}
		for at: Variant in laid.get("cells", []):
			inside[Vector2i(int(at[0]), int(at[1]))] = true
		if laid.get("use") == "guardroom" and not sneaks.is_empty() and sneaks.all(func(cell: Vector2i) -> bool: return inside.has(cell)):
			rooms += 1
	var one_pack := sneaks.size() == 3 and packs.size() == 1 and not packs.has("") and wander and rooms == 1
	_check(count == 8 and (one_pack or sneaks.is_empty() and imps == 7),
			"castle_halls generation %d: the sneaks one pack wandering a guardroom, or none and seven imps; eight foes (%d sneaks %s, packs %s, wander %s, rooms %d, foes %d)"
			% [generation, sneaks.size(), sneaks, packs.keys(), wander, rooms, count])


## The cold forge woken (813 amended (4)) in castle_halls generation
## [param generation] ([param made]): one plate set of kind "forge" in the
## cold forge's room, the bellows beside the forge and the lever FORGE_APART
## off at least, each FORGE_NEED; no monster on either; a cart within the
## checker's reach; the shutter's door into the store, its chest the
## block's forge_cache with the store's place; the mechanism's three clues;
## and no coop fault.
func _check_cold_forge(generation: int, made: Dictionary, block: Dictionary, monsters: Array[Vector2i]) -> void:
	var config: Dictionary = made["config"]
	var level := Level.parse(made["layout"], made["height"], config)
	var sets: Array = level["terrain"].get("plates", []).filter(func(plate: Dictionary) -> bool: return plate.get("kind") == "forge")
	var room := ""
	for laid: Dictionary in config.get("laid_rooms", []):
		if laid.get("use") == "cold_forge":
			room = str(laid["id"])
	if sets.size() != 1:
		_check(false, "castle_halls generation %d: one forge plate set (%d)" % [generation, sets.size()])
		return
	var plate: Dictionary = sets[0]
	var cells: Array = plate["cells"]
	var forge: Variant = plate.get("forge")
	var sides := Terrain.edge_cells(plate["edge"])
	var store: Array = config.get("entities", []).filter(func(entity: Dictionary) -> bool:
		var at := Vector2i(int(entity["at"][0]), int(entity["at"][1]))
		return at in sides and (entity.get("props", {}) as Dictionary).get("cache") == block.get("forge_cache") \
			and entity["props"].get("cache_place") == LABYRINTH.FORGE_PLACE)
	var forge_rect := Rect2i()
	for building: Dictionary in config.get("buildings", []):
		if building["slot"] == "building.set_cold_forge":
			forge_rect = Level.building_rect(building)
	var beside: bool = forge is Vector2i and forge_rect.position == forge and forge_rect.grow(1).has_point(cells[0]) and not forge_rect.has_point(cells[0])
	var gap: Vector2i = (cells[1] as Vector2i) - (cells[0] as Vector2i)
	var mechanism: Array = level.get("secrets", []).filter(func(secret: Dictionary) -> bool:
		return secret.get("kind") == "mechanism" and secret.get("plates") == "forge" and secret.get("room") == room)
	var faults: Array = LAYOUT_SENSE.check(level, config.get("laid_rooms", []), Regen.layout_options(block)).filter(func(fault: Dictionary) -> bool:
		return fault["rule"] == "coop")
	_check(plate["room"] == room and plate.get("pieces") == ["bellows", "lever"] and int(config["plates"][0].get("need", 0)) == LABYRINTH.FORGE_NEED
			and beside and absi(gap.x) + absi(gap.y) >= LABYRINTH.FORGE_APART and not cells.any(func(cell: Vector2i) -> bool: return cell in monsters)
			and store.size() == 1 and mechanism.size() == 1 and (mechanism[0]["clues"] as Array).size() == 3 and faults.is_empty(),
			"castle_halls generation %d: the cold forge woken: bellows by the forge, the lever %d off, no monster on them, the shutter on its store (%s), three clues, no coop fault (%s)"
			% [generation, absi(gap.x) + absi(gap.y), store.size(), faults])


## Hollowfell phase B (790 amended (3), the coordinator's plan):
## two generations, each chamber sunk a level with one way in down a stair
## two wide; Grull at the east stair's foot facing up it and Skeech side-on
## in the south's dark (no lamp within 6), each named, on guard, with his
## two; each chief's find (a hollowfell_cache chest) by him; the shrine (its
## look) and the windlass laid, lit, the windlass solid.
func _test_hollow_chiefs() -> void:
	print("\n== hollowfell phase B (790 amended (3)): sunk chambers, the chiefs and their finds, the shrine and the windlass ==")
	for generation in [1, 2]:
		var made := Regen.generate("hollowfell", generation)
		if made.is_empty():
			_check(false, "hollowfell generation %d is made" % generation)
			continue
		var config: Dictionary = made["config"]
		var map := LevelMap.from_image(made["layout"], config)
		var height: Image = made["height"]
		var level_at := func(cell: Vector2i) -> int: return roundi(height.get_pixel(2 * cell.x, 2 * cell.y).r8 / float(Level.GREY_PER_LEVEL))
		var wrong: Array = []
		for chamber: Array in [[Rect2i(80, 20, 14, 10), [Vector2i(80, 24), Vector2i(80, 25)], [Vector2i(81, 24), Vector2i(81, 25)]],
				[Rect2i(70, 56, 12, 10), [Vector2i(75, 56), Vector2i(76, 56)], [Vector2i(75, 57), Vector2i(76, 57)]]]:
			for cell in Level.rect_cells(chamber[0]):
				if not map.walkable(cell):
					continue
				var want := 3 if cell in chamber[1] else 2
				if level_at.call(cell) != want or (cell in chamber[2]) != (map.cell(cell) == "stair"):
					wrong.append(cell)
		_check(wrong.is_empty(), "hollowfell generation %d: both chambers a level down, their one way in a stair two wide (wrong at %s)" % [generation, wrong])
		var parsed := Level.parse(made["layout"], made["height"], config)
		var chiefs := {}
		var monsters: Array[Vector2i] = []
		var finds: Array[Vector2i] = []
		for spec: Dictionary in parsed["entities"]:
			if spec.has("named") and (spec.get("idle", {}) as Dictionary).get("mode", "") == "guard":
				chiefs[spec["named"]] = [spec["tile"], spec.get("facing")]
			if str(spec.get("script", "")) == Level.MONSTER:
				monsters.append(spec["tile"])
			if str(spec.get("script", "")) == Level.CHEST and (spec.get("props", {}) as Dictionary).get("cache", "") == "hollowfell_cache":
				finds.append(spec["tile"])
		var lamps: Array[Vector2i] = []
		for cell: Vector2i in map.cells:
			if map.cells[cell] == "lantern":
				lamps.append(cell)
		var dark := not lamps.any(func(cell: Vector2i) -> bool: return _cells_apart(cell, Vector2i(71, 58)) <= 6)
		var guarded := finds.all(func(at: Vector2i) -> bool:
			return monsters.filter(func(m: Vector2i) -> bool: return _cells_apart(m, at) <= 8).size() >= 2)
		_check(chiefs.get("grull", []) == [Vector2i(82, 24), Vector2i(-1, 0)] and chiefs.get("skeech", []) == [Vector2i(71, 58), Vector2i(1, 0)]
				and dark and finds.size() == 2 and guarded,
				"hollowfell generation %d: Grull at the east stair's foot facing up it, Skeech side-on in the south's dark, each on guard, each find guarded (%s; dark %s; finds %s)" % [generation, chiefs, dark, finds])
		var shrines: Array = config.get("decor", []).filter(func(row: Array) -> bool: return row[4] == "miners_shrine")
		var looks: Array = config.get("carvings", []).filter(func(row: Dictionary) -> bool: return not str(row.get("look", "")).is_empty())
		var windlass: Array = config.get("buildings", []).filter(func(row: Dictionary) -> bool: return row["slot"] == "building.set_windlass")
		var lit := func(at: Vector2i) -> bool: return lamps.any(func(cell: Vector2i) -> bool: return _cells_apart(cell, at) <= 4)
		var solid: Variant = parsed["terrain"]["solid"]
		_check(shrines.size() == 1 and looks.size() == 1 and windlass.size() == 1
				and lit.call(Vector2i(int(shrines[0][0]), int(shrines[0][1]))) and lit.call(Vector2i(int(windlass[0]["at"][0]), int(windlass[0]["at"][1])))
				and solid.has(Vector2i(int(windlass[0]["at"][0]), int(windlass[0]["at"][1]))) and solid.has(Vector2i(int(windlass[0]["at"][0]) + 1, int(windlass[0]["at"][1]))),
				"hollowfell generation %d: the miners' shrine with its look and the windlass laid in the bays, each lit, the windlass solid (%d, %d, %d)" % [generation, shrines.size(), looks.size(), windlass.size()])


static func _cells_apart(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _test_layout_sense() -> void:
	print("\n== 806: layout sense: doors lead somewhere, rooms have purposes, no corridor wraps a room, dead ends hold something, a spine, loops through rooms ==")
	# The checker itself, on small made-up floors (ways 2: a room is where a
	# 3 x 3 square fits).
	var clean := _ls_level([Rect2i(0, 0, 6, 6), Rect2i(6, 2, 6, 2), Rect2i(12, 0, 6, 6)], [], [Vector2i(2, 2)], [Vector2i(15, 3)])
	var faults := LAYOUT_SENSE.check(clean, [], {"ways": 2})
	_check(faults.is_empty(), "two rooms, each holding something, joined straight: no faults (%s)" % [faults])
	# A door off the first room into a short blind way with nothing in it.
	var stub := _ls_level([Rect2i(0, 0, 6, 6), Rect2i(6, 2, 6, 2), Rect2i(12, 0, 6, 6), Rect2i(2, 6, 2, 3)],
			[[Vector2i(2, 5), Vector2i(0, 1), Terrain.Edge.DOOR], [Vector2i(3, 5), Vector2i(0, 1), Terrain.Edge.DOOR]],
			[Vector2i(2, 2)], [Vector2i(15, 3)])
	var counts := LAYOUT_SENSE.counts(LAYOUT_SENSE.check(stub, [], {"ways": 2}))
	_check(counts["door"] == 1 and counts["dead_end"] == 1, "a door to an empty stub is a door fault and a dead end (%s)" % [counts])
	# A third room holding nothing.
	var empty := _ls_level([Rect2i(0, 0, 6, 6), Rect2i(6, 2, 6, 2), Rect2i(12, 0, 6, 6), Rect2i(18, 2, 4, 2), Rect2i(22, 0, 6, 6)], [],
			[Vector2i(2, 2)], [Vector2i(15, 3)])
	counts = LAYOUT_SENSE.counts(LAYOUT_SENSE.check(empty, [], {"ways": 2}))
	_check(counts["purpose"] == 1, "a room holding nothing has no purpose (%s)" % [counts])
	_check(LAYOUT_SENSE.counts(LAYOUT_SENSE.check(empty, [{"rect": [0, 0, 6, 6], "use": "tomb"},
			{"rect": [12, 0, 6, 6], "use": ""}, {"rect": [22, 0, 6, 6], "use": "store"}], {}))["purpose"] >= 2,
			"named rooms: one with no use, one holding nothing, are both named")
	# Jeff, 11-04: an enemy alone is enough for a room ("anything but an empty square").
	var guarded := empty.duplicate(true)
	guarded["entities"].append({"tile": Vector2i(25, 3), "name": "Ghoul", "home": Vector2i(25, 3)})
	counts = LAYOUT_SENSE.counts(LAYOUT_SENSE.check(guarded, [], {"ways": 2}))
	_check(counts["purpose"] == 0, "a room holding an enemy is not empty (%s)" % [counts])
	# A hall with a pillar in it is one room, and the pillar no loop.
	var hall := _ls_level([Rect2i(0, 0, 6, 6), Rect2i(6, 2, 6, 2), Rect2i(12, 0, 7, 7)], [], [Vector2i(2, 2)], [Vector2i(17, 5)])
	hall["terrain"]["floor"].erase(Vector2i(15, 3))
	counts = LAYOUT_SENSE.counts(LAYOUT_SENSE.check(hall, [], {"ways": 2, "pillars": 4}))
	_check(counts["loop"] == 0 and counts["purpose"] == 0, "a pillar in a hall is part of the hall, not a loop (%s)" % [counts])
	# A way that splits round a block of plain rock and joins again.
	var ring := _ls_level([Rect2i(0, 0, 6, 6), Rect2i(6, 1, 9, 2), Rect2i(6, 5, 9, 2), Rect2i(6, 3, 2, 2), Rect2i(13, 3, 2, 2),
			Rect2i(15, 1, 2, 2), Rect2i(17, 0, 6, 6)], [], [Vector2i(2, 2)], [Vector2i(20, 3)])
	counts = LAYOUT_SENSE.counts(LAYOUT_SENSE.check(ring, [], {"ways": 2}))
	_check(counts["loop"] >= 1, "a corridor ring round plain rock is a loop with no meaning (%s)" % [counts])
	# A way hugging two sides of a room before it goes in (walled off it).
	var hug_floor := [Rect2i(0, 0, 6, 6), Rect2i(6, 0, 2, 10), Rect2i(8, 8, 8, 2), Rect2i(8, 2, 6, 6), Rect2i(14, 2, 2, 6)]
	var walls := []
	for y in range(2, 6):
		walls.append([Vector2i(5, y), Vector2i(1, 0), Terrain.Edge.WALL])
	for y in range(2, 8):
		walls.append([Vector2i(7, y), Vector2i(1, 0), Terrain.Edge.WALL])
	for x in range(8, 14):
		walls.append([Vector2i(x, 7), Vector2i(0, 1), Terrain.Edge.WALL])
	var hug := _ls_level(hug_floor, walls, [Vector2i(2, 2)], [Vector2i(10, 4)])
	counts = LAYOUT_SENSE.counts(LAYOUT_SENSE.check(hug, [], {"ways": 2}))
	_check(counts["wrap"] >= 1, "a corridor running along two sides of a room wraps it (%s)" % [counts])
	# Chests (Jeff: every chest gives something, in a dungeon, guarded).
	var vault := _ls_level([Rect2i(0, 0, 6, 6), Rect2i(6, 2, 6, 2), Rect2i(12, 0, 6, 6)], [], [Vector2i(2, 2)], [])
	vault["entities"] = [{"tile": Vector2i(15, 3), "name": "Chest", "script": Level.CHEST, "props": {"slots": ["", ""]}}]
	var said := LAYOUT_SENSE.check_chests(vault, {"dungeon": true})
	_check(said.size() == 2, "an empty chest with no guard is named twice: it gives nothing, and it is unguarded (%s)" % [said])
	vault["entities"] = [{"tile": Vector2i(15, 3), "name": "Chest", "script": Level.CHEST, "props": {"cache": "robbers_camp"}},
		{"tile": Vector2i(14, 1), "name": "Imp1", "script": Level.MONSTER, "home": Vector2i(14, 1)}]
	said = LAYOUT_SENSE.check_chests(vault, {"dungeon": true})
	_check(said.is_empty(), "a cache with an imp beside it passes (%s)" % [said])
	said = LAYOUT_SENSE.check_chests(vault, {"dungeon": false})
	_check(said.size() == 1, "the same chest outside a dungeon is named (%s)" % [said])
	vault["entities"] = [{"tile": Vector2i(15, 3), "name": "Altar", "script": Level.CHEST, "props": {"role": "offering", "slots": [""]}}]
	_check(LAYOUT_SENSE.check_chests(vault, {"dungeon": true}).is_empty(), "a chest with a role of its own (an offering altar) is left out")
	# The co-op tomb (crypt landing 2): a room, an alcove behind a door on
	# its east wall with a chest in it, two plates three apart, a boulder by
	# one; then plates side by side, no boulder, an empty alcove, one clue.
	var tomb := _ls_level([Rect2i(0, 0, 6, 6), Rect2i(6, 2, 1, 1)], [[Vector2i(5, 2), Vector2i(1, 0), Terrain.Edge.DOOR]], [Vector2i(2, 2)], [])
	var door_edge := Terrain.edge_key(Vector2i(5, 2), Vector2i(1, 0))
	var coop_counts := func(plates: Array, entities: Array, clues: Array) -> int:
		var level := tomb.duplicate(true)
		level["terrain"]["plates"] = [{"id": "vault", "cells": plates, "edge": door_edge, "room": "tomb"}]
		level["entities"] = entities
		level["secrets"] = [{"id": "loose", "cell": Vector2i(0, 4), "side": Vector2i(-1, 0), "clues": clues}]
		return int(LAYOUT_SENSE.counts(LAYOUT_SENSE.check(level, [], {"ways": 2}))["coop"])
	var boulder := {"tile": Vector2i(2, 4), "name": "Boulder", "script": Level.PUSHABLE}
	var cached := {"tile": Vector2i(6, 2), "name": "Chest", "script": Level.CHEST, "props": {"cache": "crypt_cache"}}
	var three := ["a", "b", "c"]
	var coop_said := [coop_counts.call([Vector2i(1, 1), Vector2i(1, 4)], [boulder, cached], three),
		coop_counts.call([Vector2i(1, 1), Vector2i(2, 1)], [boulder, cached], three),
		coop_counts.call([Vector2i(1, 1), Vector2i(1, 4)], [cached], three),
		coop_counts.call([Vector2i(1, 1), Vector2i(1, 4)], [boulder], three),
		coop_counts.call([Vector2i(1, 1), Vector2i(1, 4)], [boulder, cached], ["a"])]
	_check(coop_said == [0, 1, 1, 1, 1],
		"the co-op rule: a clean tomb passes; plates one body holds, no stand-in for a lone player, nothing behind the door, a secret of one clue are each named (%s)" % [coop_said])
	# Every level's chests today (reported).
	for folder in DirAccess.get_directories_at(Level.DIR):
		if Level.DIR + folder + "/" == Prefab.DIR or not FileAccess.file_exists(Level.DIR + folder + "/layout.png"):
			continue
		var laid := Level.load_level(folder)
		if laid.is_empty():
			continue
		var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(Level.DIR + folder + "/level.json"))
		var depth := int((config as Dictionary).get("depth", 0)) if config is Dictionary else 0
		var chest_faults := LAYOUT_SENSE.check_chests(laid, {"dungeon": depth > 0 or laid.get("regenerate") is Dictionary})
		if not chest_faults.is_empty():
			print("  REPORT  %s chests: %s" % [folder, chest_faults.map(func(f: Dictionary) -> String: return "%s %s" % [f["cell"], f["what"]])])
	# Every generation of every regenerating level, measured (reported; a
	# rule fails only once its block's "held" lists it).
	for level_name in Regen.marked_levels():
		var totals := {}
		for generation in [1, 2]:
			var made := Regen.generate(level_name, generation)
			if made.is_empty():
				continue
			var level := Level.parse(made["layout"], made["height"], made["config"])
			var block: Dictionary = made["config"].get("regenerate", {})
			var found := LAYOUT_SENSE.check(level, made["config"].get("laid_rooms", []), Regen.layout_options(block))
			var by_rule := LAYOUT_SENSE.counts(found)
			for rule: String in by_rule:
				totals[rule] = int(totals.get(rule, 0)) + int(by_rule[rule])
			# The rules its "regenerate" block holds it to ("held", 806 amended
			# (a)); the rest are reported, not failed.
			for rule: String in block.get("held", []):
				_check(int(by_rule.get(rule, 0)) == 0, "%s generation %d: no %s faults (%s)" % [level_name, generation, rule,
						found.filter(func(f: Dictionary) -> bool: return f["rule"] == rule).slice(0, 6)])
		print("  REPORT  %s, two generations: %s" % [level_name, totals])


## A made-up level for the checker: [param rects] floor, [param edges]
## [[cell, way, Terrain.Edge], ...], a start at each of [param starts], a
## thing with a purpose (a bier) at each of [param things].
## 806 amended (playtest's tour: mouth to both chambers, not one fight):
## each chamber but the entrance has a monster within GUARD_STEPS walked
## steps of it, and most monsters stand within ROUTE_NEAR of the walk from
## the entrance to the chambers.
const GUARD_STEPS := 10
const ROUTE_NEAR := 5


func _mine_fights(level: Dictionary, config: Dictionary, label: String) -> void:
	var regen: Dictionary = config.get("regenerate", {})
	var floor := {}
	for cell: Vector2i in level["terrain"]["floor"]:
		floor[cell] = true
	var monsters: Array[Vector2i] = []
	for spec: Dictionary in level["entities"]:
		if spec.has("home") and spec.get("tile") is Vector2i:
			monsters.append(spec["tile"])
	var rects := {}
	for anchor: Dictionary in regen.get("anchors", []):
		var r: Array = anchor["rect"]
		rects[str(anchor["name"])] = Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
	var walk := func(from: Array) -> Dictionary:
		var dist := {}
		var queue: Array = []
		for cell: Vector2i in from:
			dist[cell] = 0
			queue.append(cell)
		var at := 0
		while at < queue.size():
			var cell: Vector2i = queue[at]
			at += 1
			for way: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if floor.has(cell + way) and not dist.has(cell + way):
					dist[cell + way] = int(dist[cell]) + 1
					queue.append(cell + way)
		return dist
	var entrance := str(regen.get("entrance", ""))
	var from_mouth: Dictionary = walk.call(Level.rect_cells(rects[entrance]).filter(func(c: Vector2i) -> bool: return floor.has(c)))
	var route := {}
	for name: String in rects:
		if name == entrance:
			continue
		var inside: Array = Level.rect_cells(rects[name]).filter(func(c: Vector2i) -> bool: return floor.has(c))
		var near: Dictionary = walk.call(inside)
		var guarded := monsters.filter(func(m: Vector2i) -> bool: return int(near.get(m, 1 << 20)) <= GUARD_STEPS)
		_check(not guarded.is_empty(), "%s: a fight before %s, within %d steps (monsters at %s)" % [label, name, GUARD_STEPS, monsters])
		# The walk back from the chamber's nearest cell to the mouth.
		var cell: Vector2i = inside[0]
		for each: Vector2i in inside:
			if int(from_mouth.get(each, 1 << 20)) < int(from_mouth.get(cell, 1 << 20)):
				cell = each
		while from_mouth.has(cell) and int(from_mouth[cell]) > 0:
			route[cell] = true
			for way: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if int(from_mouth.get(cell + way, 1 << 20)) == int(from_mouth[cell]) - 1:
					cell = cell + way
					break
	var on_route := monsters.filter(func(m: Vector2i) -> bool:
		for dy in range(-ROUTE_NEAR, ROUTE_NEAR + 1):
			for dx in range(-ROUTE_NEAR, ROUTE_NEAR + 1):
				if route.has(m + Vector2i(dx, dy)):
					return true
		return false)
	# A cart's track runs where the tunnel is four across at least, so a cart
	# on it leaves a way past (the tour stalled at one in a two-cell way).
	var narrow := []
	var laid := 0
	for row: Dictionary in level["terrain"].get("decor", []):
		if row.get("kind") != "mine_track":
			continue
		laid += 1
		var out: Vector2i = row["out"]
		var q := Vector2i(absi(out.y), absi(out.x))
		var across := 1
		for side: Vector2i in [q, -q]:
			var k := 1
			while floor.has(row["cell"] + side * k) and k <= 8:
				k += 1
			across += k - 1
		if across < 4:
			narrow.append(row["cell"])
	_check(laid > 0 and narrow.is_empty(), "%s: %d track pieces, each in a tunnel four across or more (narrower at %s)" % [label, laid, narrow.slice(0, 6)])
	var off := monsters.filter(func(m: Vector2i) -> bool: return not m in on_route)
	_check(on_route.size() * 3 >= monsters.size() * 2, "%s: most monsters by the way from the mouth to the chambers (%d of %d; off it %s)" % [label, on_route.size(), monsters.size(), off])


func _ls_level(rects: Array, edges: Array, starts: Array, things: Array) -> Dictionary:
	var floor: Array[Vector2i] = []
	for rect: Rect2i in rects:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if not Vector2i(x, y) in floor:
					floor.append(Vector2i(x, y))
	var kinds := {}
	for row: Array in edges:
		kinds[Terrain.edge_key(row[0], row[1])] = row[2]
	var starts_typed: Array[Vector2i] = []
	starts_typed.assign(starts)
	var entities := []
	for cell: Vector2i in things:
		entities.append({"tile": cell, "name": "Bier"})
	return {"terrain": {"floor": floor, "edges": kinds}, "starts": starts_typed, "entities": entities, "links": []}


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
## The way behind the throne under the fight lock (540 amended (1); Jeff's report,
## 2026-11-12: "draugr room to the rear his throne there is a exit to return
## to the crypt entrance"; his rule, "the door closes when you enter"). 896
## switched on took that way out both ends (the throne is the way home): the
## held Hall has no way out in it and no way from the barrow arrives in it;
## the lock still holds a way laid in a held lair, whatever level lays one.
func _test_throne_way_held() -> void:
	print("\n== no way out behind the throne; the held lair holds any way in it (540 amended (1), 896) ==")
	_main.load_map("test_room")
	_main.travel(Net.local_id, "barrow_deep", "")
	await get_tree().process_frame
	_main._hold_hall_door("barrow_deep", true)
	var lair: Rect2i = _main.hall_lair_rect("barrow_deep")
	var in_lair: Array = _main.level.get("links", []).filter(func(link: Dictionary) -> bool: return lair.has_point(link["tile"]))
	_check(_main.map_name == "barrow_deep" and _main.hall_held("barrow_deep") and lair.has_area() and in_lair.is_empty(),
		"the Hall held: no way out in its lair (%s, %s)" % [lair, in_lair])
	var into: Array = Level.load_level("barrow").get("links", []).filter(func(link: Dictionary) -> bool:
		return link["to_map"] == "barrow_deep" and _main.hall_link_held(link, "barrow"))
	_check(into.is_empty(), "no way from the barrow arrives in the held Hall (%s)" % [into])
	var laid := {"tile": Vector2i(49, 77), "to_map": "barrow", "to_spawn": "from_deep", "sealed": "draugr"}
	_check(_main.hall_link_held(laid), "a way laid in the held lair would be held all the same")
	_main._hold_hall_door("barrow_deep", false)
	_check(not _main.hall_held("barrow_deep") and not _main.hall_link_held(laid), "let go: not held")
	_main.load_map("test_room")


## The draugr's throne, the way home once he is downed (896, "full circle";
## Jeff, 2026-11-12: "it would be cool if sitting on the throne kicks you
## back to the entrance, but only possible if the draugr is downed"). Off,
## a click on it is nothing; on, while he holds it he is told THRONE_HIS once;
## at rest, a stand on it alone sends no one, a sit is undone by a step off
## or another order, and a sit held THRONE_SIT_S sends the sitter to the
## First Hall's from_deep.
func _test_throne_home() -> void:
	print("\n== the draugr's throne: the way home once he is downed (896) ==")
	var kept_switch: bool = _main.throne_home
	_main.load_map("test_room")
	_main.travel(Net.local_id, "barrow_deep", "")
	await get_tree().process_frame
	var throne := Vector2i(49, 75)
	var draugr: Draugr = null
	for entity in World.get_entities():
		if entity is Draugr:
			draugr = entity as Draugr
	var player := _player()
	if draugr == null or player == null or _main.throne_at("barrow_deep", throne).is_empty():
		_check(false, "barrow_deep's draugr, a player and the throne at %s (%s, %s)" % [throne, draugr, player])
		_main.throne_home = kept_switch
		_main.load_map("test_room")
		return
	var heard: Array[String] = []
	var hear := func(kind: String, data: Dictionary) -> void:
		if kind == "party":
			heard.append(str(data.get("text", "")))
	Net.message_received.connect(hear)
	var front: Vector2i = _main._beside(throne, throne + Vector2i(0, -2))
	_put(player, front)
	_main.throne_home = false
	_main._told_throne.erase(Net.local_id)
	_main._on_command(player, "throne", {"at": [throne.x, throne.y]})
	_check(player.seated == "" and heard.count(_main.THRONE_HIS) == 0 and not _main._throne_sits.has(Net.local_id),
		"off: asked from beside it, nothing (%s, %s)" % [player.seated, heard])
	_main.throne_home = true
	_main._on_command(player, "throne", {"at": [throne.x, throne.y]})
	_main._on_command(player, "throne", {"at": [throne.x, throne.y]})
	_check(draugr.state == Draugr.State.SEATED and player.seated == "" and heard.count(_main.THRONE_HIS) == 1,
		"on, while he sits it: told once that it is his, not sat (%s, %s)" % [player.seated, heard])
	# Laid to rest by the test-only console (896's switch-on, for playtest's walk): unknown without --test-hp.
	var had_hp: bool = Net.test_hp
	Net.test_hp = false
	var refused: String = _main.admin_command("rest draugr")
	Net.test_hp = true
	var rested: String = _main.admin_command("rest draugr")
	var again: String = _main.admin_command("rest draugr")
	Net.test_hp = had_hp
	_check(refused.begins_with("unknown command") and rested == "rest draugr: barrow_deep's draugr laid to rest" and draugr.resting()
		and again == "rest draugr: the draugr in barrow_deep already rests",
		"the test-only console lays him to rest, once; without --test-hp it is unknown, as on the box (%s / %s / %s)" % [refused, rested, again])
	_put(player, throne)
	for i in roundi(_main.THRONE_SIT_S * World.TICK_RATE) + 3:
		World.step()
	_check(_main.map_name == "barrow_deep" and player.seated == "",
		"downed, a walk onto it alone sends no one (%s, %s)" % [_main.map_name, player.seated])
	_main._on_command(player, "throne", {"at": [throne.x, throne.y]})
	_check(player.seated == "throne" and player.facing == Vector2i(0, -1) and _main._throne_sits.has(Net.local_id),
		"asked on it while he rests: she sits, facing the hall (%s, %s)" % [player.seated, player.facing])
	World.step()
	_put(player, front)
	World.step()
	_check(player.seated == "" and not _main._throne_sits.has(Net.local_id) and _main.map_name == "barrow_deep",
		"a step off before the send stands her up, sent nowhere (%s, %s)" % [player.seated, _main.map_name])
	_put(player, throne)
	_main._on_command(player, "throne", {"at": [throne.x, throne.y]})
	_main._on_command(player, "stance", {"kind": ""})
	_check(player.seated == "" and not _main._throne_sits.has(Net.local_id), "another order stands her up as well (%s)" % player.seated)
	_main._on_command(player, "throne", {"at": [throne.x, throne.y]})
	_main._on_command(player, "say", {"text": "home"})
	_check(player.seated == "throne", "talk leaves her seated (%s)" % player.seated)
	for i in roundi(_main.THRONE_SIT_S * World.TICK_RATE) + 2:
		World.step()
		if _main.map_name != "barrow_deep":
			break
	await get_tree().process_frame
	await get_tree().process_frame
	player = _player()
	var at: Vector2i = player.tile if player != null else World.NO_CELL
	_check(_main.map_name == "barrow" and World.distance(at, Vector2i(31, 8)) <= 1 and player.seated == "" and _main._throne_sits.is_empty(),
		"held THRONE_SIT_S, she is sent home to the First Hall's from_deep (%s, at %s)" % [_main.map_name, at])
	Net.message_received.disconnect(hear)
	var deep: Zone = World.zones.get("barrow_deep")
	if deep != null:
		var was := World.zone
		World.enter(deep)
		for entity in World.get_entities():
			if entity is Draugr:
				(entity as Draugr)._rise_again()
		World.enter(was)
	_main.throne_home = kept_switch
	_main.load_map("test_room")


## Package "full circle" switched on (896): one switch turns the throne
## and the altar together, on by default; the shortcut's two ends gone, so
## an arrival by its old spawn or a saved stand on its old cell lands on
## open floor; no cell a player lays from beside the bier is the knight's.
func _test_full_circle_on() -> void:
	print("\n== package full circle switched on (896) ==")
	_check(_main.full_circle and _main.throne_home and _main.altar_turn_in and AstralKnight.altar_on, "on by default: the throne, the altar and his words")
	# The test-only relic verb (playtest's walk): a brother's remains in the pack, by name.
	var had_hp: bool = Net.test_hp
	Net.test_hp = true
	var me := _player()
	var my_record: PlayerRecord = _main._records.get(me.player_id) if me != null else null
	var my_name := my_record.name if my_record != null else ""
	var given: String = _main.admin_command("relic %s Sir Ansel the Faithful" % my_name)
	Net.test_hp = had_hp
	var brother_slot := -1
	if me != null:
		for slot in me.slots.size():
			if str(World.relic_of(World.slot_uid(me, slot)).get("knight", "")) == "Sir Ansel the Faithful":
				brother_slot = slot
	_check(given == "relic: the remains of Sir Ansel the Faithful at %s's pack" % my_name and brother_slot >= 0,
		"the test-only relic verb puts a named knight's remains in the pack (%s)" % given)
	if brother_slot >= 0:
		World.consume(me, World.slot_uid(me, brother_slot), "test")
	# The test-only strike verb: the player's blow of all its hp, the player its slayer.
	_main.load_map("test_room")
	_main.travel(Net.local_id, "barrow_deep", "")
	await get_tree().process_frame
	me = _player()
	# The template lays no monsters of its own (a generation does), so one is spawned beside the player.
	var foe: Monster = null
	if me != null:
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(2, 0), Vector2i(0, 2)]:
			if World.is_walkable(me.tile + step):  # An occupied cell: World.spawn refuses it, _spawn gives null.
				foe = _main._spawn({"script": Level.MONSTER, "shape": "capsule", "name": "Struck_test", "tile": me.tile + step, "props": {"sight_range": 0}})
				if foe != null:
					break
	Net.test_hp = true
	var struck_words: String = _main.admin_command("strike %s %s" % [my_name, _main.monster_name(foe)]) if foe != null else ""
	var nobody: String = _main.admin_command("strike %s nobody at all" % my_name)
	Net.test_hp = had_hp
	var refused: String = _main.admin_command("strike %s nobody at all" % my_name)
	_check(foe != null and struck_words.begins_with("strike: %s struck " % my_name) and (not is_instance_valid(foe) or foe.hp <= 0 or foe.struck_by == me),
		"the test-only strike verb fells a monster in the player's zone, the player its slayer (%s)" % struck_words)
	_check(nobody.begins_with("strike: no monster in barrow_deep") and not refused.begins_with("strike"),
		"a name nobody bears strikes nothing, and without --test-hp the verb is unknown (%s / %s)" % [nobody, refused])
	_main.full_circle = false
	_check(not _main.throne_home and not _main.altar_turn_in and not AstralKnight.altar_on, "the one switch turns both halves off together")
	_main.full_circle = true
	_check(_main.throne_home and _main.altar_turn_in and AstralKnight.altar_on, "and on again")
	# Mid-crossing at the switch-on: a send still naming from_temple, and a
	# player saved on (49,77), the shortcut's cell, now rock.
	_main.load_map("test_room")
	_main.travel(Net.local_id, "barrow_deep", "from_temple")
	await get_tree().process_frame
	var player := _player()
	var at: Vector2i = player.tile if player != null else World.NO_CELL
	_check(_main.map_name == "barrow_deep" and World.is_walkable(at), "sent by the old spawn: in the Ossuary on open floor (at %s)" % [at])
	_main.load_map("test_room")
	_main.travel(Net.local_id, "barrow_deep", "", {}, Vector2i(49, 77))
	await get_tree().process_frame
	player = _player()
	at = player.tile if player != null else World.NO_CELL
	_check(_main.map_name == "barrow_deep" and at != Vector2i(49, 77) and World.is_walkable(at),
		"saved on the shortcut's old cell: placed on open floor, not in the rock (at %s)" % [at])
	_main.load_map("test_room")
	_main.travel(Net.local_id, "barrow", "", {}, Vector2i(30, 8))
	await get_tree().process_frame
	player = _player()
	at = player.tile if player != null else World.NO_CELL
	_check(_main.map_name == "barrow" and World.is_walkable(at) and World.distance(at, Vector2i(30, 8)) <= 1,
		"saved on the First Hall's old way down: plain floor there (at %s)" % [at])
	# No laying cell is the knight's (the coordinator's (1), 11-13: he holds his cell).
	var bier: Rect2i = _main.knights_altar("barrow")
	var knight: GridEntity = null
	for entity in World.get_entities():
		if entity is AstralKnight:
			knight = entity
	var on_him: Array[Vector2i] = []
	if bier.has_area() and knight != null:
		# From every walkable cell, his own among them (a shove or a bring-back
		# could put a player there): the pick never names a cell another body
		# holds; only the caller's own cell, held by a player, may be named.
		for cell in Level.rect_cells(bier.grow(4)):
			if not World.is_walkable(cell):
				continue
			var picked: Vector2i = _main.altar_beside(bier, cell)
			var holder: GridEntity = World.get_entity_at(picked) if picked != Main.NONE else null
			if picked == knight.tile or holder != null and not (picked == cell and holder is Player):
				on_him.append(cell)
	_check(bier.has_area() and knight != null and World.get_entity_at(knight.tile) == knight and on_him.is_empty(),
		"from any cell near the bier, the cell to lay from is never the knight's (%s, from %s)" % [knight.tile if knight != null else World.NO_CELL, on_him])
	# A click on the bier sends with any holy knight's remains in the pack,
	# not only the quest's ready step (playtest's look_circle: a later run's
	# or a brother's were never sent, nor refused aloud).
	var walker := _player()
	if walker != null and bier.has_area():
		var stand: Vector2i = _main.altar_beside(bier, walker.tile)
		_put(walker, stand)
		var had_quest: Dictionary = walker.quest
		walker.quest = {}
		_drop_relics(walker)
		var bare: bool = _main._altar_click(walker, Vector2i(38, 8))
		var brother: int = World.mint_relic("Sir Ansel the Faithful", 0, walker)
		World.into_pack(walker, brother)
		var carrying: bool = _main._altar_click(walker, Vector2i(38, 8))
		_check(not bare and carrying, "a click on the bier: with nothing to lay it walks; with a brother's remains in the pack, no quest ready, it asks the server (%s, %s)" % [bare, carrying])
		_drop_relics(walker)
		walker.quest = had_quest
	_main.load_map("test_room")


## The knight's thanks charges the amulet (896 amended (1), Jeff's answer):
## off the quest the altar takes any holy knight's remains a player carries,
## his own again or a brother's, charges by their tier and says which; an
## amulet that can hold no more, or one never blessed, keeps them; remains
## won unpaid are laid with no charge; the hidden way is the player's on the
## altar step; a record saved on that step keeps it.
func _test_altar_charges() -> void:
	print("\n== the knight's altar charges the amulet (896 amended (1)) ==")
	var player := _player()
	var id := player.player_id
	var record: PlayerRecord = _main._records.get(id)
	if record == null:
		_check(false, "no record for the test player")
		return
	var kept := {"marks": record.marks.duplicate(), "task": record.barrow_task.duplicate(true), "barrow": record.barrow.duplicate(true)}
	_main.load_map("test_room")
	_main.travel(Net.local_id, "barrow", "")
	await get_tree().process_frame
	player = _player()
	var bier: Rect2i = _main.knights_altar("barrow")
	var knight: AstralKnight = null
	for entity in World.get_entities():
		if entity is AstralKnight:
			knight = entity
	var said: Array[String] = []
	var hear := func(words: String) -> void: said.append(words)
	if knight == null or not bier.has_area():
		_check(false, "the knight and his bier in the barrow (%s)" % [bier])
		return
	knight.said.connect(hear)
	_put(player, _main.altar_beside(bier, player.tile))
	_drop_relics(player)
	var deals := Economy.deals(_main._field_rules())
	record.barrow = {"best": str(deals[0].get("name", "")), "containers": []}  # Blessed once: room on the amulet.
	_main.mark_player(id, Main.QUEST_DONE)
	record.barrow_task = {}
	_main.altar_turn_in = true
	var sir: String = _main.barrow_knight()
	var own := sir if not sir.is_empty() else "Sir Test"
	var charges := func() -> int: return World.totem_charges(World.totem_of(id))
	var lay := func(name: String, tier: int) -> int:
		var uid := World.mint_relic(name, tier, player)
		World.into_pack(player, uid)
		said.clear()
		_main._on_command(player, "altar", {"at": [bier.position.x, bier.position.y]})
		return uid
	var before: int = charges.call()
	var uid: int = lay.call(own, 0)
	_check(not player.slot_items.has(uid) and charges.call() > before and said == [AstralKnight.LAID_AGAIN] and Main.QUEST_DONE in record.marks,
		"a later run, his own remains: laid, the amulet charged, his thanks again (%s, %d -> %d)" % [said, before, charges.call()])
	before = charges.call()
	uid = lay.call("Sir Brother of the Test", 0)
	_check(not player.slot_items.has(uid) and charges.call() > before and said == [Main.laid_words(false, 1, 0, "Sir Brother of the Test", sir)],
		"an earlier generation's knight: taken, charged, his thanks by whose they are (%s)" % [said])
	_check(Main.laid_words(false, 1, 0, "Sir Brother of the Test", "Sir Own") == AstralKnight.LAID_BROTHER
		and Main.laid_words(false, 1, 0, "Sir Own", "Sir Own") == AstralKnight.LAID_AGAIN and Main.laid_words(false, 0, -1, "Sir Own", "Sir Own") == AstralKnight.LAID_NO_BLESSING
		and Main.laid_words(true, 3, 0, "Sir Own", "Sir Own") == AstralKnight.LAID_QUEST and Main.laid_words(true, 0, 0, "Sir Own", "Sir Own") == AstralKnight.LAID,
		"his words by whose remains: a brother's when a generation names another knight, his own again, unpaid, the quest's charged or not")
	World.totem_add(World.totem_of(id), 1000, Economy.barrow_capacity(record.barrow, _main._field_rules()))  # Full.
	before = charges.call()
	uid = lay.call(own, 0)
	_check(player.slot_items.has(uid) and charges.call() == before and said == [AstralKnight.LAID_FULL],
		"an amulet that holds no more: kept, nothing laid, he says why (%s)" % [said])
	World.consume(player, uid, "test")
	record.barrow = {}  # Never blessed (or a quest reset).
	uid = lay.call(own, 0)
	_check(player.slot_items.has(uid) and said == [AstralKnight.LAID_UNBLESSED], "never blessed below: kept, he says why (%s)" % [said])
	World.consume(player, uid, "test")
	before = charges.call()
	uid = lay.call(own, Main.RELIC_UNPAID)
	_check(not player.slot_items.has(uid) and charges.call() == before and said == [AstralKnight.LAID_NO_BLESSING],
		"remains won unpaid: laid though never blessed, no charge, no blessing on them (%s)" % [said])
	_main.altar_turn_in = false
	uid = lay.call(own, 0)
	_check(player.slot_items.has(uid) and said.is_empty(), "off: the bier takes nothing")
	_main.altar_turn_in = true
	World.consume(player, uid, "test")
	# The hidden way on the altar step, and the step kept by a save.
	var robbers_zone := str(World.economy.rules.get("robbers", {}).get("barrow", "")) if World.economy != null else ""
	_main.mark_player(id, Main.QUEST_DONE, false)
	record.barrow_task = {"taken": true, "step": "altar"}
	_check(robbers_zone.is_empty() or _main.way_revealed(id, robbers_zone), "turned in, his remains still below: the hidden way is theirs (way_revealed)")
	var back := PlayerRecord.from_dict(record.to_dict())
	_check(str(back.barrow_task.get("step", "")) == "altar" and bool(back.barrow_task.get("taken", false)),
		"a record saved on the altar step loads on it (%s)" % [back.barrow_task])
	record.barrow_task = {"taken": true, "slain": []}
	_check(robbers_zone.is_empty() or not _main.way_revealed(id, robbers_zone), "taken, not turned in: not yet")
	var saved := record.to_dict()
	saved["barrow_task"] = {"taken": true, "slain": ["7"]}  # As a record before 896 amended (1) was saved.
	back = PlayerRecord.from_dict(saved)
	_check(back.barrow_task == {"taken": true, "slain": ["7"]}, "a record saved before the change, mid-quest, loads as it was (%s)" % [back.barrow_task])
	knight.said.disconnect(hear)
	record.marks.assign(kept["marks"])
	record.barrow_task = kept["task"]
	record.barrow = kept["barrow"]
	_main._sync_quest(record)
	_main.load_map("test_room")


## The knight's altar in the barrow itself (896, "full circle"): the bier
## he stands by is the First Hall's (38-40 by 8-9); off, a click on it lays
## nothing; on, from beside it with his remains, it is laid there and the
## quest is done.
func _test_knights_altar() -> void:
	print("\n== the knight's altar: his remains laid on the First Hall's bier (896) ==")
	var player := _player()
	var id := player.player_id
	var record: PlayerRecord = _main._records.get(id)
	if record == null:
		_check(false, "no record for the test player")
		return
	var kept := {"marks": record.marks.duplicate(), "task": record.barrow_task.duplicate(true)}
	_main.load_map("test_room")
	_main.travel(Net.local_id, "barrow", "")
	await get_tree().process_frame
	player = _player()
	var bier: Rect2i = _main.knights_altar("barrow")
	var knight: AstralKnight = null
	for entity in World.get_entities():
		if entity is AstralKnight:
			knight = entity
	var was_laid := knight != null and knight.remains_laid
	_check(bier == Rect2i(38, 8, 3, 2), "the altar is the bier the knight stands by, 38-40 by 8-9 (%s)" % [bier])
	_main.mark_player(id, Main.QUEST_DONE, false)
	record.barrow_task = {"taken": true, "step": "altar"}
	var sir: String = _main.barrow_knight()
	_drop_relics(player)
	var relic := World.mint_relic(sir if not sir.is_empty() else "Sir Test", 0, player)
	World.into_pack(player, relic)
	var beside: Vector2i = _main.altar_beside(bier, player.tile)
	_check(beside != Main.NONE and not bier.has_point(beside) and World.is_walkable(beside), "a free cell beside the bier to stand on (%s)" % [beside])
	_put(player, beside)
	_main.altar_turn_in = false
	_main._on_command(player, "altar", {"at": [38, 8]})
	_check(_main.knights_relic_slot(player) >= 0 and not (Main.QUEST_DONE in record.marks), "off: a click on the bier lays nothing")
	_main.altar_turn_in = true
	_main._on_command(player, "altar", {"at": [38, 8]})
	_check(_main.knights_relic_slot(player) < 0 and Main.QUEST_DONE in record.marks and record.barrow_task.is_empty() and player.quest.is_empty(),
		"on, from beside it with his remains: laid, the quest done, the card closed (%s, %s)" % [beside, record.barrow_task])
	_check(not was_laid and knight != null and knight.remains_laid, "and his remains lie on the bier for the generation (remains_laid, for art-kit's piece)")
	# Kept through a restart: in the level's regen state, which a save keeps
	# and a new generation replaces; a knight made again there is laid.
	var regen_state: Dictionary = _main._regen.get("barrow", _main._plain_band_slain)
	var round_trip: Dictionary = Regen.states_from(JSON.parse_string(JSON.stringify({"barrow": regen_state})))
	var again: AstralKnight = null
	if knight != null:
		var spec: Dictionary = knight.spawn_spec.duplicate(true)
		(spec.get_or_add("props", {}) as Dictionary).erase("remains_laid")
		spec["tile"] = knight.tile
		World.despawn(knight)
		await get_tree().process_frame
		again = _main._spawn(spec) as AstralKnight
	_check(_main.remains_laid_in("barrow") and bool(round_trip.get("barrow", {}).get("remains_laid", false)) and again != null and again.remains_laid,
		"and through a restart: the level's state keeps them through a save, and the knight made again there has them laid")
	if _main._regen.has("barrow"):
		_main._regen["barrow"].erase("remains_laid")
	_main._plain_band_slain.erase("remains_laid")
	_main.altar_turn_in = true
	record.marks.assign(kept["marks"])
	record.barrow_task = kept["task"]
	_main._sync_quest(record)
	_main.load_map("test_room")


## Every relic off [param player] (896's cases): only the one a case mints is theirs to lay.
func _drop_relics(player: Player) -> void:
	for slot in player.slots.size():
		var uid := World.slot_uid(player, slot)
		if not World.relic_of(uid).is_empty():
			World.consume(player, uid, "test")
