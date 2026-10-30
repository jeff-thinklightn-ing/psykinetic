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


func _ready() -> void:
	World.set_process(false)
	Net.port = preload("res://tests/test_ports.gd").of(17790)
	Net.companions = false
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	World.entity_pushed.connect(func(entity: GridEntity, _by: GridEntity, _direction: Vector2i, tiles: int, impact: int, stopped_by: String) -> void:
		_pushes.append({"entity": entity, "tiles": tiles, "impact": impact, "stopped_by": stopped_by}))
	_register_maps()
	_check(_player() == null or World.free_body(_player()), "a player is a free body: every player's walk below is one (6b, 703)")

	_test_test_room_unchanged()
	_test_every_level()
	_test_round_trip()
	_test_edges_and_doors()
	_test_markers()
	_test_heights_and_stairs()
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
	_test_place_towns()
	_test_regenerate_mark()
	_test_town_walls()
	_test_roofs()
	await _test_level_links()
	await _test_links_kept_clear()
	await _test_sealed_link()
	await _test_temple_stair()
	_test_barrow_won()
	await _test_hall_door()
	await _test_hidden_niche()
	_test_double_doors()
	_test_camp_chest()
	_test_decor()
	_test_barrow_level()
	_test_castle_halls_level()
	_test_tower_levels()
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
			"the wilds' way to the castle: a stone arch facing north, out to it (%s)" % [castle_way])
	var gate: Dictionary = cue_of.call("castle", Vector2i(16, 23))
	_check(gate.get("cue") == "waystones" and gate.get("facing") == Vector2i(0, 1), "the castle's way out at its edge: waystones (%s)" % [gate])
	_check(cue_of.call("barrow_deep", Vector2i(49, 1)).get("cue") == "up" and cue_of.call("barrow_deep", Vector2i(49, 77)).get("cue") == "sealed",
			"the barrow's depths: the Ossuary's stair up to the shallower, the sealed shortcut behind the throne its slab (666)")
	_check(cue_of.call("wilds", Vector2i(170, 180)).get("cue") == "none" and cue_of.call("wilds", Vector2i(216, 195)).get("cue") == "sealed",
			"the mound's door is its own cue; the sealed shortcut (in the temple since 715) its slab")
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
	_check(level["display_name"] == "Umbrage", "its name is the town's, Umbrage (Jeff; the id stays held: %s)" % level["display_name"])
	var links: Array = level["links"]
	var to_wilds: Array = links.filter(func(link: Dictionary) -> bool: return link["to_map"] == "wilds")
	var wilds := Level.load_level("wilds")
	var town_cells: Array = [wilds["places"]["store"]["cell"], wilds["places"]["woodlot"]["cell"]]
	for building: Dictionary in wilds["buildings"]:
		if str(building.get("town", "")) != "":
			town_cells.append(building["cell"])
	_check(town_cells.all(func(cell: Vector2i) -> bool: return Level.room_at(wilds, cell) == "umbrage") and wilds["rooms"]["umbrage"]["name"] == "Umbrage"
			and Level.room_at(wilds, Vector2i(70, 202)) == "",
		"the wilds' town ground is named Umbrage while the town stands there (665's rooms; the store, the woodlot, the town's buildings), the standing stones not (%s: %s)"
			% [town_cells, town_cells.map(func(cell: Vector2i) -> String: return Level.room_at(wilds, cell))])
	var back: Array = wilds["links"].filter(func(link: Dictionary) -> bool: return link["to_map"] == "held")
	_check(to_wilds.size() == 1 and (to_wilds[0]["tile"] as Vector2i).x == 191 and back.size() == 1 and (back[0]["tile"] as Vector2i).x <= 20
			and level["spawn_points"].has("from_wilds") and wilds["spawn_points"].has("from_held"),
		"its east edge links to the wilds' west edge and back (%s, %s)" % [to_wilds.map(func(link: Dictionary) -> Vector2i: return link["tile"]), back.map(func(link: Dictionary) -> Vector2i: return link["tile"])])
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
	_check(tags.size() == 12, "twelve refuges laid, the smith's forge under the castle among them (%s)" % [tags.keys()])
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://levels/economy.json"))
	var trades: Dictionary = rules.get("sought", {}).get("trades", {})
	var wanted := []
	for trade: String in trades:
		for variant: Variant in [trades[trade], trades[trade].get("alt")]:
			if variant is Dictionary and str(variant.get("place", "camp")) != "camp":
				wanted.append(str(variant["place"]))
	var missing := wanted.filter(func(tag: String) -> bool: return not tags.has(tag))
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
	var outdoor := levels.keys().filter(func(level_name: String) -> bool: return Level.zone_of(Level.template_config(level_name)) == "outdoors")
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
## over the valley's low wall, the valley floor does not; the ridge hides
## the valley from the west.
func _test_hills() -> void:
	print("
== levels/hills: relief to walk, fall from and see over ==")
	_check(_main.load_map("hills") and World.outdoor and World.has_relief(), "hills loads, outdoors, its ground in metres")
	var player := _player()
	var plateau := Vector2i(72, 30)
	var foot := Vector2i(58, 30)
	_check(World.elevation_at(plateau) - World.elevation_at(foot) > 4.0, "the plateau stands over the valley (%.1f m over %.1f)" % [World.elevation_at(plateau), World.elevation_at(foot)])
	var path := World.find_path(player.tile, plateau)
	_check(not path.is_empty(),
		"a way up to the plateau (%d steps)" % path.size())
	_walk_free(player, plateau)
	_check(player.tile == plateau, "the bot walks up there, round by the spur (%s)" % player.tile)
	_walk_free(player, foot)
	_check(player.tile == foot, "and back down to the valley (%s)" % player.tile)
	# The rim on row 38: the face wanders (585), so the first cell east of the
	# valley standing well over the one west of it.
	var rim := Vector2i(62, 38)
	for x in range(58, 70):
		if World.elevation_at(Vector2i(x, 38)) - World.elevation_at(Vector2i(x - 1, 38)) > 2.0:
			rim = Vector2i(x, 38)
			break
	var imp: Monster = _main._spawn({"script": Level.MONSTER, "shape": "capsule", "name": "Faller", "tile": rim, "props": {"sight_range": 0, "max_hp": 200}})
	_put(player, rim + Vector2i(1, 0))
	_pushes.clear()
	var hp := imp.hp
	var drop := World.elevation_at(rim) - World.elevation_at(rim - Vector2i(1, 0))
	World._push(player, imp, Vector2i(-1, 0), 3.0)
	_check(imp.tile.x < rim.x and hp - imp.hp == World.FALL_IMPACT_PER_LEVEL * Relief.levels(drop),
			"pushed off the face: it falls %.1f m, %d levels, for %d (%s, %s)" % [drop, Relief.levels(drop), hp - imp.hp, imp.tile, _pushes.back()["stopped_by"]])
	World.despawn(imp)
	_check(World.has_line_of_sight(Vector2i(63, 37), Vector2i(53, 38)), "from the plateau's rim the valley beyond the low wall is seen")
	# Where the ridge bends east (rows 30-38, 84-90) there is ground behind
	# its crest: some of it hidden from the valley floor.
	var hidden := []
	for row in range(30, 39) + range(84, 91):
		var crest := Vector2i(-1, row)
		for x in range(0, 36):
			var cell := Vector2i(x, row)
			if World.is_walkable(cell) and (crest.x < 0 or World.elevation_at(cell) > World.elevation_at(crest)):
				crest = cell
		for x in range(0, crest.x - 1):
			var behind := Vector2i(x, row)
			if World.is_walkable(behind) and not World.has_line_of_sight(Vector2i(46, row), behind):
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
	var link: Array = wilds["links"].filter(func(l: Dictionary) -> bool: return l["to_map"] == "barrow" and l["to_spawn"] == "from_wilds")
	_check(mounds.size() == 1 and not link.is_empty() and mounds[0]["door"] == link[0]["tile"] and wilds["spawn_points"].get("from_barrow") == Vector2i(170, 179)
		and not Vector2i(170, 179) in wilds["terrain"]["solid"], "the wilds' mound stands, its door on the barrow's link, from_barrow outside (%s)" % [wilds["warnings"]])
	# Jeff: "add some of the melee weapons to the town chest for testing": two chests beside it.
	var held := []
	for spec: Dictionary in wilds["entities"]:
		if spec["tile"] in [Vector2i(219, 226), Vector2i(219, 225)] and str(spec.get("script", "")).ends_with("chest.gd"):
			held.append_array(Array(spec.get("props", {}).get("slots", [])))
	_check(["sword", "spear", "hammer", "shield", "giant_axe", "dagger", "buckler"].all(func(id: String) -> bool: return id in held),
			"the town chest's two beside it hold a sword, a spear, a hammer, a shield, a giant axe, a dagger and a buckler (%s)" % [held])
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
	_check(forest.get("display_name") == "The Forest" and links.size() == 2 and links[0]["to_map"] == "wilds"
		and links[1]["to_map"] == "stronghold" and links[1]["closed"], "The Forest: back to the wilds, on to the stronghold closed (%s)" % [links])
	_check(_main.load_map("forest") and World.outdoor, "forest loads, outdoors")
	var player := _player()
	var east: Vector2i = links[1]["tile"]
	var path := World.find_path(player.tile, east)
	_check(not path.is_empty(), "a way from the way in to the way on (%d steps)" % path.size())
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
	var temple: Array = wilds["buildings"].filter(func(b: Dictionary) -> bool: return b["slot"] == "building.temple")
	var stair: Array = wilds["links"].filter(func(l: Dictionary) -> bool: return l["to_map"] == "barrow_deep")
	_check(temple.size() == 1 and stair.size() == 1 and stair[0]["tile"] == (temple[0]["rect"] as Rect2i).position and stair[0]["building"] == temple[0]["code"]
		and stair[0]["sealed"] == "draugr" and stair[0]["to_spawn"] == "from_temple" and not Vector2i(217, 193) in wilds["terrain"]["links_at"]
		and wilds["warnings"].filter(func(w: String) -> bool: return "link" in w).is_empty(),
		"the wilds' temple carries the sealed stair down in its north-west back corner; the old one behind it is gone (%s)" % [stair])


## Umbrage's locker (722): one chest prop {"locker": true}, since 737 in
## the player's house, its back to the house's south wall, the cell before
## it open floor.
func _test_umbrage_locker() -> void:
	print("\n== Umbrage's locker (722), in the player's house (737) ==")
	var wilds := Level.load_level("wilds")
	var lockers: Array = wilds["entities"].filter(func(spec: Dictionary) -> bool: return bool((spec.get("props", {}) as Dictionary).get("locker", false)))
	var at := Vector2i(195, 220)
	_check(lockers.size() == 1 and lockers[0]["tile"] == at
		and wilds["terrain"]["edges"].get(Terrain.edge_key(at, Vector2i(0, 1))) == Terrain.Edge.WALL
		and wilds["terrain"]["floor"].has(at + Vector2i(0, -1)) and not wilds["terrain"]["edges"].has(Terrain.edge_key(at, Vector2i(0, -1)))
		and wilds["entities"].all(func(spec: Dictionary) -> bool: return spec["tile"] != at + Vector2i(0, -1)),
		"one locker, at (195, 220), its back to the house's south wall, the cell before it clear floor (%s)" % [lockers])
	var homes: Array = wilds["buildings"].filter(func(building: Dictionary) -> bool: return building.get("home", false))
	_check(homes.size() == 1 and (homes[0]["rect"] as Rect2i) == Rect2i(194, 215, 4, 6) and Level.building_cells(homes[0]).has(at)
		and str(homes[0].get("use", "")).is_empty(),
		"one house marked the player's (737), the free house at (194, 215), the locker inside it (%d)" % homes.size())


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
	_check(_main.party_log.last(1) == ["The way is sealed."], "told the way is sealed (%s)" % [_main.party_log.last(1)])
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
	_check(_main.map_name == "lt_temple_shut" and _main.party_log.last(1) == ["The stair down is barred from below."],
		"unblessed at the stair down: it stays shut, barred from below (%s)" % [_main.party_log.last(1)])
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
	_check(_main.party_log.last(2) == ["The draugr yields. %s is blessed and takes up the %s, uncharged." % [record.name, Items.name_of(World.TOTEM)],
			Main.SEPULCHER_PLAQUE % knight + " %s takes the holy remains, for the altar." % record.name],
		"the win and the plaque said (%s)" % [_main.party_log.last(2)])
	_check(_main.charge_from_relic(player, 1) == 10 and player.charges == 10 and _main.charges_in_zone("test_link_s") == 10 and _main.charges_in_zone("wilds") == 0,
		"the relic on the altar: the deal's 10 charges, 10 of 50; the zone's sum is 10, another zone's 0")
	_main.barrow_won([id], "easy")
	_check(World.totem_of(id) == uid and World.totem_charges(uid) == 10 and record.barrow["best"] == "normal"
		and _main.party_log.last(2)[0] == "The draugr yields. %s stands over him again." % record.name and World.relic_of(relics.call()[-1])["tier"] == 0,
		"won again at an easier deal: the same amulet, no charges, best kept, an easy relic (%s)" % [_main.party_log.last(2)])
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
	_main._hold_hall_door("lt_hall", true)
	_check(door != null and not door.open and door.lock == "draugr_hall" and door.body_material == GridEntity.BodyMaterial.STONE
		and _main.party_log.last(1) == ["The hall's door shuts behind you."], "held: shut, locked with a key nobody holds, stone, and said (%s)" % [_main.party_log.last(1)])
	_hold_free(player, Vector2(0, 1), 8)
	_check(player.tile == Vector2i(5, 3) and player.free_pos.y < 3.6, "no walk goes through it: stopped at its face (%s)" % player.free_pos)
	_check(not World.try_toggle_door(player, key) and not door.open, "and E rattles it")
	_main._hold_hall_door("lt_hall", false)
	_check(door.lock.is_empty() and not door.open and _main.party_log.last(1) == ["The hall's door opens."], "let go: the lock lifted, still shut till opened, and said")
	await get_tree().process_frame
	_check(World.try_toggle_door(player, key) and door.open, "E opens it now")
	# The dead's seal (666): held while they stand, entry only, under a challenge's lock.
	_main._seal_hall("lt_hall", true)
	_check(not door.open and door.lock == _main.DEAD_LOCK and door.body_material == GridEntity.BodyMaterial.STONE and not World.try_toggle_door(player, key),
		"the Ossuary's dead standing: the hall's door sealed with a key nobody holds, E rattles it (%s)" % door.lock)
	_hold_free(player, Vector2(0, 1), 8)
	_check(player.tile == Vector2i(5, 3) and player.free_pos.y < 3.6, "and stops a walk at its face (%s)" % player.free_pos)
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
	var draft := "You feel a cool draft coming from one of the niches."
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
	_check(player.tile == Vector2i(2, 1) and _main.party_log.last(1) == [line],
		"pressing into a plain niche is stopped and says the line (%s)" % [_main.party_log.last(1)])
	var told: Array = _main.party_log.last(3)
	_hold_free(player, Vector2(0, -1), 6)
	_check(_main.party_log.last(3) == told, "pressing on at it says nothing more")
	_put(player, Vector2i(4, 1))
	_hold_free(player, Vector2(0, -1), 6)
	_check(_main.party_log.last(2) == [line, line], "another niche says it again")
	_put(player, Vector2i(6, 1))
	_check(not World.may_open(player, door) and not World.try_toggle_door(player, key) and not door.open, "no walk opens the hidden niche's door and E rattles it")
	for i in 10:
		_hold_free(player, Vector2(0, -1), 1)
		if door.open:
			break
	_check(player.tile == Vector2i(6, 1) and door.open and door.lock.is_empty()
		and _main.party_log.last(1) == ["The slab swings aside: a stair goes down into the dark."],
		"pressing into the hidden niche finds it: the lock lifted, the door open, and said (%s)" % [_main.party_log.last(1)])
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
	_check(door.open and door.lock.is_empty(), "the press found it again")
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
	_check(door.open and door.lock.is_empty() and _player().tile == Vector2i(6, 1) and _main.party_log.last(2)[0] == "The slab swings aside from behind.",
		"come up from below, the slab is pushed open from behind and said; the player stands before it (%s)" % [_main.party_log.last(2)])
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
	_check(barrow["display_name"] == "The Barrow" and barrow["size"] == Vector2i(80, 60) and barrow["warnings"].is_empty(),
		"The Barrow, 80 x 60 (580), parses with no warning (%s)" % [barrow["warnings"]])
	_check(deep["display_name"] == "The Ossuary" and deep["size"] == Vector2i(100, 80) and deep["warnings"].is_empty()
		and not Level.exists("barrow_lair") and not Level.overlaid("barrow_lair") and Level.RETIRED.get("barrow_lair") == ["barrow_deep", Vector2i(49, 2)],
		"the Ossuary, 100 x 80, parses with no warning; the dark below is retired, its players bound for the Ossuary's stair foot (666; %s)" % [deep["warnings"]])
	# Moss and webs (647): the templates' own, the rest rolled by a generation.
	var corner_webs := func(level: Dictionary) -> int:
		return level["terrain"]["decor"].filter(func(d: Dictionary) -> bool: return d["kind"] == "web_corner").size()
	_check(barrow["terrain"]["decor"].size() == 3 and corner_webs.call(barrow) == 2 and deep["terrain"]["decor"].size() == 30 and corner_webs.call(deep) == 4,
		"the first hall holds two cobwebbed corners and a strip of moss, the Ossuary's Hall of Fallen Souls its moss and four webbed corners (%d, %d)" % [barrow["terrain"]["decor"].size(), deep["terrain"]["decor"].size()])
	_check(Regen.marked("barrow") and Regen.config_of("barrow")["anchors"].size() == 4 and int(Regen.config_of("barrow").get("layer", 0)) == 1
		and Regen.marked("barrow_deep") and Regen.config_of("barrow_deep")["anchors"].size() == 2 and int(Regen.config_of("barrow_deep").get("layer", 0)) == 2
		and Regen.config_of("barrow_deep")["anchors"][1]["name"] == "lair" and Regen.config_of("barrow_deep").get("monsters") == {"skeleton": 12, "skeleton_guard": 2}
		and int(Regen.config_of("barrow").get("ways", 0)) == 5 and int(Regen.config_of("barrow_deep").get("ways", 0)) == 5,
		"both depths are marked to regenerate in the barrow style, layers 1 and 2, every way five wide; the Ossuary's far anchor the lair, its dead twelve skeletons and two grave guards (666)")
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
	_check(kinds.get("skeleton_guard", 0) == 2 and kinds.get("draugr", 0) == 1 and kinds.get("altar", 0) == 1 and kinds.get("runner's pack", 0) == 1
		and kinds.get("robbers' chest", 0) == 1
		and barrow["places"].has("niche") and barrow["entities"].size() == 5 and deep["entities"].size() == 2 and kinds.get("chest", 0) == 1,
		"the altar with its two guards, Pip's niche, the Runner's pack and the robbers' chest (742) on the first layer, the draugr in his hall in the Ossuary and its chest by the throne (%s)" % [kinds])
	_check(grave_marked.get("Altar", false) and grave_marked.get("Draugr", false) and not grave_marked.get("Runner's pack", true) and guards_marked == 2,
		"grave_goods marks the altar, the guards and the draugr as grave goods, the runner's pack exempt (%s)" % [grave_marked])
	_check(barrow["links"].size() == 2 and barrow["links"][0]["to_map"] == "wilds" and barrow["links"][1]["to_map"] == "barrow_deep" and barrow["links"][1]["to_spawn"] == "from_above"
		and deep["links"].size() == 2 and deep["links"][0]["to_map"] == "barrow" and deep["links"][0]["to_spawn"] == "from_below"
		and deep["links"][1]["sealed"] == "draugr" and deep["links"][1]["to_spawn"] == "from_barrow_shortcut",
		"the stairs link the depths both ways, and the temple's sealed shortcut ends behind the draugr's throne in the Ossuary")
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
	for pair: Array in [[barrow, "from_wilds"], [barrow, "from_below"], [deep, "from_above"], [deep, "from_temple"]]:
		var level: Dictionary = pair[0]
		if not level["spawn_points"].has(pair[1]) or not level["terrain"]["floor"].has(level["spawn_points"][pair[1]]):
			floor_ok = false
	var wilds := Level.load_level("wilds")
	var shortcut: Array = wilds["links"].filter(func(l: Dictionary) -> bool: return l["to_spawn"] == "from_temple")
	_check(floor_ok and shortcut.size() == 1 and shortcut[0]["to_map"] == "barrow_deep" and shortcut[0]["sealed"] == "draugr",
		"every spawn point the stairs and the wilds come in by is floor; the wilds' sealed shortcut leads to the draugr's hall in the Ossuary (666, maps' nod)")
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
		and deep["spawn_points"]["from_temple"] == Vector2i(49, 76) and deep["links"][1]["tile"] == Vector2i(49, 77),
		"the dais is one level up, its front row twelve stairs climbing south, its back row against the wall, the shortcut's end behind the throne (%d stairs)" % stairs.size())
	_check(Level.narrow_runs(barrow["terrain"]).is_empty() and Level.narrow_runs(deep["terrain"]).is_empty(),
		"no way in the dressed halls is one cell wide, the table, the pillars and the dais's ledges seen (%s)" % [Level.narrow_runs(deep["terrain"]).slice(0, 8)])
	var made := Regen.generate("barrow", 1)
	var made_deep := Regen.generate("barrow_deep", 1)
	_check(not made.is_empty() and Regen.connected(LevelMap.from_image(made["layout"], made["config"]), made["anchors"])
		and not made_deep.is_empty() and Regen.connected(LevelMap.from_image(made_deep["layout"], made_deep["config"]), made_deep["anchors"]),
		"a generation of each depth is laid and joins every anchor (%d and %d tries)" % [made.get("tries", 0), made_deep.get("tries", 0)])
	var gen_barrow := Level.parse(made["layout"], made["height"], made["config"])
	var gen_deep := Level.parse(made_deep["layout"], made_deep["height"], made_deep["config"])
	_check(gen_barrow["warnings"].is_empty() and gen_deep["warnings"].is_empty() and gen_barrow["terrain"]["solid"].size() == 6 and gen_deep["terrain"]["solid"].size() == 20 + 9 + 8
		and gen_deep["terrain"]["stairs"].size() == 12 and int(gen_deep["terrain"]["heights"].get(Vector2i(49, 75), 0)) == 1 and made_deep["height"] != null
		and Level.narrow_runs(gen_barrow["terrain"]).is_empty() and Level.narrow_runs(gen_deep["terrain"]).is_empty()
		and made["config"].get("rooms", {}).size() == 3 and made_deep["config"].get("rooms", {}).has("lair"),
		"a generation keeps the dressed halls: the table and pillars solid, the dais raised with its stairs, no way one cell wide, and the named rooms (%s %s)" % [gen_barrow["warnings"], gen_deep["warnings"]])
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
			if spec["tile"] == Sheet.LAIR_CHEST:
				if (props.get("slots", []) as Array).has("plate_armour") and first_plate == 0:
					first_plate = generation
			elif (props.get("slots", []) as Array).has("mail_armour") and first_mail == 0:
				first_mail = generation
		if first_mail > 0 and first_plate > 0:
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
		and block.get("monsters") == {"imp": 5, "brute": 1},
		"marked to regenerate in the dwarven style, ways five wide, three anchors, depth from the stair foot, enemy-ai's five imps and a brute (%s)" % [block.keys()])
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


func _test_castle() -> void:
	print("\n== the castle, and the way there from the test room ==")
	var castle := Level.load_level("castle")
	_check(not castle.is_empty() and castle["display_name"] == "The Castle" and castle["warnings"].is_empty(),
			"levels/castle is \"The Castle\" and loads cleanly (%s)" % [castle.get("warnings", "missing")])
	_check(load("res://levels/castle/layout.png") is Image, "its layout.png is imported as an Image")
	_check(castle["links"].size() == 3 and str(castle["links"].slice(0, 2)) == str([{"tile": Vector2i(27, 12), "to_map": "test_room", "to_spawn": "from_castle", "one_way": false, "closed": false, "sealed": "", "hidden": false, "cue": "none"},
			{"tile": Vector2i(16, 23), "to_map": "wilds", "to_spawn": "from_castle", "one_way": false, "closed": false, "sealed": "", "hidden": false, "cue": "waystones"}])
			and castle["links"][2]["tile"] == Vector2i(11, 18) and castle["links"][2]["to_map"] == "castle_halls" and castle["links"][2]["to_spawn"] == "from_castle",
			"its link at (27, 12) goes to the test room, at the foot of its road to the wilds, and from the guardroom down to the Dwarven Halls (613) (%s)" % [castle["links"]])
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


## 742 (Jeff: "have them respawn on a 5 min timer - the game is in
## pre-alpha, there doesn't need to be enforce scarcity"): the barrow's camp
## holds the robbers' chest, a cache whose search puts economy's camp gold
## into the purse, once per player each every_s; sooner, empty.
func _test_camp_chest() -> void:
	print("
== the robbers' camp chest (742) ==")
	var camp: Dictionary = _main._camp_rules()
	var barrow := Level.load_level("barrow")
	var placed := (barrow.get("entities", []) as Array).filter(func(spec: Dictionary) -> bool:
		return spec.get("tile") == Vector2i(14, 43) and spec.get("props", {}).get("cache") == "robbers_camp")
	_check(int(camp.get("gold", 0)) == 25 and int(camp.get("every_s", 0)) == 300 and camp.get("cache") == "robbers_camp" and placed.size() == 1
		and not (barrow.get("warnings", []) as Array).any(func(w: String) -> bool: return "robbers_camp" in w),
		"economy's camp rule (25 gold, 300 s) and the chest in the barrow's camp, its table known (%s)" % [camp])
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
	var had_taken: Variant = _main._camp_taken.get(id)
	_main._camp_taken.erase(id)
	var gold_was := World.gold_of(id)
	var first: bool = _main.search(player, chest)
	var after_first := World.gold_of(id)
	var again: bool = _main.search(player, chest)
	_check(first and after_first == gold_was + 25 and not again and World.gold_of(id) == after_first
		and (chest.slots as Array).all(func(each: Variant) -> bool: return str(each).is_empty() or int(each) == 0),
		"searched: 25 gold to the purse, nothing in its slots; at once again, empty (%d -> %d -> %d)" % [gold_was, after_first, World.gold_of(id)])
	_main._camp_taken[id] -= 300 * World.TICK_RATE
	_check(_main.search(player, chest) and World.gold_of(id) == after_first + 25, "five minutes on, full again: 25 more")
	World.add_gold(id, gold_was - World.gold_of(id), "test")
	if had_taken == null:
		_main._camp_taken.erase(id)
	else:
		_main._camp_taken[id] = had_taken
	World.despawn(chest)


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


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
