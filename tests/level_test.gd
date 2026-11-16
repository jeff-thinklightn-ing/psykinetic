extends "res://tests/level_test_base.gd"
## Levels from pixel maps (sim/level.gd), the land half: the test room unchanged, every
## level and prefab loading cleanly, a round trip through PNG, edge walls and doors from
## wall and door pixels, heights, stairs, falls, pits and the mine, sight over lower walls,
## hills, the forest, fields and folds, the canopy, the world plane, its roads, water, ledges
## and ways on foot, buildings and their kinds, links in and out, beds and lockers, towns,
## walls, roofs and temples, a leaving set down outside a building with an inside, level and
## edge links, the console, and layout sense over every level. The laid levels (barrows,
## crypts, the castle and its halls, towers, camps) are level_dungeons_test; the shared part
## is tests/level_test_base.gd.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.


func _ready() -> void:
	Net.port = preload("res://tests/test_ports.gd").of(17790)
	_setup()
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
	await _test_out_of_the_shell()
	_test_temple_town()
	_test_niche_click()
	await _test_edge_links()
	_test_console()
	await _test_spawn_near()
	_test_reed_pond()
	_test_fishin_hole()
	_test_kind_lists()
	_finish()


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
	_test_jeffs_pond_corner()
	_test_hearth()
	_test_starts()
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
	var town_starts: Array = wilds["starts"].filter(func(cell: Vector2i) -> bool: return cell.y > 100)
	_check(Level.where_name(wilds, Vector2i(208, 205)) == "Umbrage" and town_starts.size() == 4
			and town_starts.all(func(cell: Vector2i) -> bool: return Level.where_name(wilds, cell) == "Umbrage")
			and Level.where_name(wilds, Vector2i(128, 128)) == "The Wilds" and Level.where_name({}, Vector2i(1, 1)) == ""
			and Level.where_name({"display_name": "A Cave"}, Vector2i(1, 1)) == "A Cave",
		"where_name: a room's name inside it (the town's four starts), the level's name outside every room, nothing for neither (665 amended)")
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
## Jeff's own build at Snagfin's shack, from the box (c027f4bc7, 10-14): his
## pond's eleven water cells, the dock's three dirt cells running from under the
## shack's door to his water, and the shack's four dirt floor cells. His hand
## work: no town plan, water tool or wholesale re-lay may repaint them (774 laid
## the floor and dock over with grass and 568's river took (222, 226); both put
## back by the pond take, the coordinator's ruling). Snagfin's bigger pond grows
## from his east and south only, so the pool keeps its first cell (221, 224)
## and its key, pool_221_224: levels/economy.json stocks that key (40 fish, 40
## back a day, 805 amended (16)) and economy_test and companion_test name it; a
## reshape that moves the first cell fails here by name, not by dropping the
## pond quietly to the default stock.
func _test_jeffs_pond_corner() -> void:
	print("\n== Jeff's own build at Snagfin's shack (c027f4bc7) and its pool's key ==")
	var wilds := Level.load_level("wilds")
	var terrain: Dictionary = wilds["terrain"]
	var kinds: Dictionary = terrain["kinds"]
	var water := {}
	for cell: Vector2i in terrain.get("water", []):
		water[cell] = true
	var his_water: Array[Vector2i] = [Vector2i(221, 224), Vector2i(222, 224), Vector2i(223, 224), Vector2i(222, 225),
		Vector2i(223, 225), Vector2i(222, 226), Vector2i(223, 226), Vector2i(223, 227), Vector2i(221, 228),
		Vector2i(222, 228), Vector2i(223, 228)]
	var dock: Array[Vector2i] = [Vector2i(220, 227), Vector2i(221, 227), Vector2i(222, 227)]
	var floor_cells: Array[Vector2i] = [Vector2i(220, 225), Vector2i(221, 225), Vector2i(220, 226), Vector2i(221, 226)]
	var lost: Array = his_water.filter(func(cell: Vector2i) -> bool: return not water.has(cell))
	_check(lost.is_empty(), "his pond's eleven cells are water (none lost: %s)" % [lost])
	var not_dirt: Array = (dock + floor_cells).filter(func(cell: Vector2i) -> bool:
		return water.has(cell) or str(kinds.get(cell, "")) != "dirt")
	_check(not_dirt.is_empty(), "his dock (220..222, 227) and the shack's floor (220..221 x 225..226) are dirt (not: %s)" % [not_dirt])
	var keys := World.fish_waters_of(terrain)
	_check(str(keys.get(Vector2i(221, 224), "")) == "pool_221_224" and str(keys.get(Vector2i(230, 230), "")) == "pool_221_224",
		"the shack's pond, his crescent and the water grown east and south of it, keeps the key pool_221_224 (%s, %s): economy's stock" \
		% [keys.get(Vector2i(221, 224), "none"), keys.get(Vector2i(230, 230), "none")])
	var first := Vector2i(9999, 9999)
	for cell: Vector2i in keys:
		if keys[cell] == "pool_221_224" and (cell.y < first.y or cell.y == first.y and cell.x < first.x):
			first = cell
	_check(first == Vector2i(221, 224), "its first cell is his (221, 224): nothing north of row 224 or west of it on that row (%s)" % first)


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
	# 613 amended (6), maps' word: the sought farmer waits in the yard by the cottage's south door gap,
	# the place's cell (Main._sought_here: its nearest free cell), on dirt, in no building, off the cache.
	var farm_spot: Dictionary = wilds["places"].get("old_farmstead", {})
	var raw: Variant = farm_spot.get("cell", farm_spot.get("at", []))
	var yard: Vector2i = raw if raw is Vector2i else Vector2i(int(raw[0]), int(raw[1])) if raw is Array and (raw as Array).size() == 2 else Vector2i(-1, -1)
	var in_building: bool = (wilds["buildings"] as Array).any(func(each: Dictionary) -> bool: return each.get("rect") is Rect2i and (each["rect"] as Rect2i).has_point(yard))
	_check(yard == Vector2i(120, 143) and int(farm_spot.get("radius", 0)) == 5 and str(kinds.get(yard, "")) == "dirt" and not in_building and yard != Vector2i(119, 139),
		"the old farmstead's cell in the yard by the cottage's south gap, on dirt, in no building, off the cache (%s, %s)" % [yard, kinds.get(yard, "")])
	# The old prefab's stone floor left under the road by the farm, (129, 146..148), drew as cobbles in
	# the dirt (terrain's trace, the coordinator 11-13; 613 amended (6), the road to the first rescue):
	# the road from the west road's end (134, 201) north past the farmstead lies on no stone floor.
	var paved: Array[Vector2i] = []
	for road_row: Variant in Level.template_config("wilds").get("roads", []):
		var road_points: Array = (road_row as Dictionary).get("points", []) if road_row is Dictionary else []
		for i in range(road_points.size() - 1):
			var from_point := Vector2(float(road_points[i][0]), float(road_points[i][1]))
			var to_point := Vector2(float(road_points[i + 1][0]), float(road_points[i + 1][1]))
			var reach := (float(road_points[i][2]) * 0.5 if (road_points[i] as Array).size() > 2 else 1.0) + 0.5
			for step in 21:
				var along := from_point.lerp(to_point, step / 20.0)
				if along.y < 137.0 or along.y > 201.0 or along.x < 120.0 or along.x > 140.0:
					continue
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						var spot := Vector2i(roundi(along.x) + dx, roundi(along.y) + dy)
						if Vector2(spot).distance_to(along) <= reach and str(kinds.get(spot, "")) == "stone" and not paved.has(spot):
							paved.append(spot)
	_check(paved.is_empty(), "no stone floor under the road from the west road's end to the old farmstead (%s)" % [paved])
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


## Every level's starts (maps, 2026-11-15; the coordinator's ruling: the wilds' second start stood inside
## hut H2, so a second newcomer arrived beside its bed): none inside any building's cells, each on floor with
## nothing solid and no entity on it, and each walked to from the first over the level's floor (a wall or a
## solid cell stops the walk, a door doesn't), none further than START_SPREAD from the first (774 amended (4): the
## wilds' four painted north markers stood starts 5 to 8, about 190 from the town). The wilds' second start also
## stands open all round, near the first, on no spot; the foothills' way in still arrives at (128, 22).
func _test_starts() -> void:
	print("\n== every level's starts: open floor, outside every building, walked to from the first ==")
	for folder in DirAccess.get_directories_at(Level.DIR):
		if Level.DIR + folder + "/" == Prefab.DIR or not FileAccess.file_exists(Level.DIR + folder + "/layout.png"):
			continue
		var level := Level.load_level(folder)
		if level.is_empty() or level["starts"].is_empty():
			continue
		var terrain: Dictionary = level["terrain"]
		var solid: Variant = terrain.get("solid", {})
		var built := {}
		for building: Dictionary in level["buildings"]:
			for cell: Vector2i in Level.building_cells(building):
				built[cell] = str(building.get("code", building.get("slot", "")))
		var taken := {}
		for spec: Dictionary in level["entities"]:
			taken[spec["tile"]] = str(spec.get("name", ""))
		var bad: Array[String] = []
		var first: Vector2i = level["starts"][0]
		for start: Vector2i in level["starts"]:
			if built.has(start):
				bad.append("%s inside %s" % [start, built[start]])
			elif not terrain["floor"].has(start) or solid.has(start):
				bad.append("%s not open floor" % [start])
			elif taken.has(start):
				bad.append("%s under %s" % [start, taken[start]])
			elif World.distance(start, first) > START_SPREAD:
				bad.append("%s %d from the first %s" % [start, World.distance(start, first), first])
			elif start != first and not _floor_walks(terrain, first, start):
				bad.append("%s not walked to from %s" % [start, first])
		_check(bad.is_empty(), "%s: its %d start(s) open, outside every building, within %d of the first, walked to from it (%s)" % [folder, level["starts"].size(), START_SPREAD, bad])
	# The foothills' way in still arrives where it did: the start markers that came out sat on its arrival.
	var foothills := Level.load_level("foothills")
	var way_in: Array = foothills["links"].filter(func(link: Dictionary) -> bool: return link["to_map"] == "wilds")
	var wilds_level := Level.load_level("wilds")
	var arrival: Vector2i = wilds_level["spawn_points"].get("from_foothills", Vector2i(-1, -1))
	var way_out: Array = wilds_level["links"].filter(func(link: Dictionary) -> bool: return link["to_map"] == "foothills")
	_check(way_in.size() == 1 and way_in[0]["to_spawn"] == "from_foothills" and arrival == Vector2i(128, 22)
		and way_out.size() == 1 and way_out[0]["tile"] == Vector2i(128, 20) and wilds_level["terrain"]["floor"].has(arrival) and not wilds_level["starts"].has(arrival)
		and _floor_walks(wilds_level["terrain"], arrival, wilds_level["starts"][0]),
		"a walk in from the foothills arrives at the wilds' %s, open floor, no start, walked from there to the town's start" % [arrival])
	_test_way_in(wilds_level)
	_test_clicked_things_clear(wilds_level)


## The way in (934, the flow page's (A); the coordinator's rulings, 2026-11-15): the wilds' four starts together on
## open grass south-east of the inn, the inn's lit front where the first view looks; the north road free of the old
## generator's dirt beside it, so it reads as one road; the hill and breach roads joined to the roads they meet.
func _test_way_in(wilds: Dictionary) -> void:
	print("
== the way in: the wilds' starts face the inn, the north road reads as one road, the roads joined ==")
	var terrain: Dictionary = wilds["terrain"]
	var first: Vector2i = wilds["starts"][0]
	var bad: Array[String] = []
	for start: Vector2i in wilds["starts"]:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var cell := start + Vector2i(dx, dy)
				if not terrain["floor"].has(cell) or terrain["solid"].has(cell):
					bad.append("%s beside %s not open" % [cell, start])
		if World.distance(start, first) > 3:
			bad.append("%s %d from the first" % [start, World.distance(start, first)])
		if wilds["spots"].any(func(spot: Dictionary) -> bool: return spot["cell"] == start):
			bad.append("%s on a spot" % [start])
	_check(bad.is_empty(), "the wilds' starts within 3 of the first %s, open floor all round each, none on a spot (%s)" % [first, bad])
	# The first view (yaw 0) looks north-west: the inn's front within 15 of the first start, north-west of it, nothing
	# built on the line between.
	var inn: Dictionary = {}
	var built := {}
	for building: Dictionary in wilds["buildings"]:
		if str(building.get("code", "")) == "I1":
			inn = building
		for cell: Vector2i in Level.building_cells(building):
			built[cell] = str(building.get("code", building.get("slot", "")))
	var front := Level.front_cell(inn["rect"], inn["facing"]) if not inn.is_empty() else World.NO_CELL
	var between: Array[String] = []
	for k in range(1, 40):
		var cell := Vector2i((Vector2(first).lerp(Vector2(front), k / 40.0)).round())
		if built.has(cell) and not between.has(built[cell]):
			between.append(built[cell])
	_check(not inn.is_empty() and World.distance(first, front) <= 15 and front.x < first.x and front.y < first.y and between.is_empty(),
		"the inn's front %s within 15 of the first start %s, north-west of it, nothing built between (%s)" % [front, first, between])
	# The north road (roads 0, 3 and 7: the north link to the crossroads, south, east into the town) has no painted dirt
	# within 6 of it but its own and the other roads' margins (2 cells): the generator's trails start off in the grass.
	var roads: Array = terrain["roads"]
	var road_cells := {}
	var north := {}
	for index in roads.size():
		for cell: Vector2i in Curves.cells(roads[index]["curve"], false):
			road_cells[cell] = true
			if index in [0, 3, 7]:
				north[cell] = true
	var margin := {}
	for cell: Vector2i in road_cells:
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				margin[cell + Vector2i(dx, dy)] = true
	var near_north := {}
	for cell: Vector2i in north:
		for dx in range(-6, 7):
			for dy in range(-6, 7):
				near_north[cell + Vector2i(dx, dy)] = true
	# Kept: the old farmstead's yard (within 12 of its place) and round its fallow fields' furrows.
	var config := Level.template_config("wilds")
	var farm: Array = config["places"]["old_farmstead"]["at"]
	var kept := {}
	for dx in range(-12, 13):
		for dy in range(-12, 13):
			kept[Vector2i(int(farm[0]) + dx, int(farm[1]) + dy)] = true
	for furrow: Dictionary in config.get("furrows", []):
		var r: Array = furrow["rect"]
		for x in range(int(r[0]) - 2, int(r[0]) + int(r[2]) + 2):
			for y in range(int(r[1]) - 2, int(r[1]) + int(r[3]) + 2):
				kept[Vector2i(x, y)] = true
	var left: Array[Vector2i] = []
	for cell: Vector2i in terrain["kinds"]:
		if terrain["kinds"][cell] == "dirt" and near_north.has(cell) and not margin.has(cell) and not kept.has(cell):
			left.append(cell)
	left.sort()
	_check(left.is_empty(), "the north road: no painted dirt within 6 of it outside the roads' margins, the farmstead's yard and its fields (%d: %s)" % [left.size(), left.slice(0, 12)])
	# Its band clean (the coordinator, on ui-design's look at (125, 74): a grass notch and an island in the road's dirt):
	# out of the town's ground and the farmstead's, every one of its own cells painted dirt where the layout has grass,
	# and no painted dirt in its 2-cell margin outside every road's own cells.
	var islands: Array[Vector2i] = []
	var edge: Array[Vector2i] = []
	for cell: Vector2i in near_north:
		if kept.has(cell) or (cell.x >= 165 and cell.y >= 185) or not terrain["kinds"].has(cell):
			continue
		var kind := str(terrain["kinds"][cell])
		if north.has(cell) and kind == "grass":
			islands.append(cell)
		elif kind == "dirt" and margin.has(cell) and not road_cells.has(cell):
			var by_north := false
			for dx in range(-2, 3):
				for dy in range(-2, 3):
					by_north = by_north or north.has(cell + Vector2i(dx, dy))
			if by_north:
				edge.append(cell)
	islands.sort()
	edge.sort()
	print("  north road band: islands %s; edge %s" % [islands, edge])
	_check(islands.is_empty() and edge.is_empty(), "the north road's band: no grass in its own cells, no painted dirt in its margin (%d islands, %d edge: %s %s)" % [
		islands.size(), edge.size(), islands.slice(0, 6), edge.slice(0, 6)])
	# The hill road (9) reaches the hills road (2) at the hills arrival; the breach's road (10) reaches the barrow road (8).
	var joined := func(a: int, b: int) -> bool:
		var b_cells := Curves.cells(roads[b]["curve"], false)
		var a_cells := Curves.cells(roads[a]["curve"], false)
		return a_cells.keys().any(func(cell: Vector2i) -> bool: return b_cells.has(cell))
	_check(joined.call(9, 2) and joined.call(10, 8), "the hill road meets the hills road (%s), the breach's road the barrow road (%s)" % [joined.call(9, 2), joined.call(10, 8)])
	# 934 amended (1) (b): the pool by (113, 59) beside the north road has no bare dirt pad round it (terrain's
	# worst2 still: it read as a yard or a cut-off trail start); the pool itself is kept.
	var pool: Array[Vector2i] = []
	for cell: Vector2i in terrain["water"]:
		if cell.x >= 105 and cell.x < 122 and cell.y >= 52 and cell.y < 66:
			pool.append(cell)
	var pad: Array[Vector2i] = []
	for cell: Vector2i in pool:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var by := cell + Vector2i(dx, dy)
				if str(terrain["kinds"].get(by, "")) == "dirt" and not by in pad:
					pad.append(by)
	pad.sort()
	_check(pool.size() >= 20 and pad.is_empty(), "the pool by (113, 59): its %d water cells kept, no painted dirt beside them (%s)" % [pool.size(), pad])
	# 934 amended (1) (a): a 2 m lane (road 11, terrain's points) from road 6, where the line from the first start to
	# the inn's door crosses it, to the ground outside the door, so the newcomer's ground goes to the door and not past
	# it into the square (terrain's worst1 still); nothing built, solid or a spot on it.
	var lane: Dictionary = Curves.cells(roads[11]["curve"], false) if roads.size() > 11 else {}
	var door_out := [Vector2i(180, 208), Vector2i(180, 209)]
	var in_way: Array[String] = []
	for cell: Vector2i in lane:
		if built.has(cell) or terrain["solid"].has(cell) or not terrain["floor"].has(cell):
			in_way.append("%s %s" % [cell, built.get(cell, "solid or off the floor")])
		if wilds["spots"].any(func(spot: Dictionary) -> bool: return spot["cell"] == cell):
			in_way.append("%s a spot" % [cell])
	# Nothing a body bumps (the level's entities; the two handcarts once at the cobble's corner, (186, 212) and
	# (188, 214), moved to the store's side by 774 amended (6), _test_clicked_things_clear) on the lane or on the line from the first start to its mouth, and the lane one piece from there to the door, so
	# a player walking it is neither blocked nor steered round (the coordinator, 11-15).
	var things := {}
	for spec: Dictionary in wilds["entities"]:
		things[spec["tile"]] = str(spec.get("name", ""))
	var mouth := Vector2i((roads[11]["points"] as PackedVector2Array)[0].round()) if roads.size() > 11 else first
	for k in range(0, 21):
		var cell := Vector2i((Vector2(first).lerp(Vector2(mouth), k / 20.0)).round())
		if things.has(cell):
			in_way.append("%s %s on the way to its mouth" % [cell, things[cell]])
	for cell: Vector2i in lane:
		if things.has(cell):
			in_way.append("%s %s" % [cell, things[cell]])
	var reached := {mouth: true} if lane.has(mouth) else {}
	var queue: Array[Vector2i] = []
	queue.assign(reached.keys())
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var next := cell + Vector2i(dx, dy)
				if lane.has(next) and not reached.has(next):
					reached[next] = true
					queue.append(next)
	if reached.size() != lane.size():
		in_way.append("the lane in pieces (%d of %d from its mouth %s)" % [reached.size(), lane.size(), mouth])
	var at_door := door_out.any(func(cell: Vector2i) -> bool: return lane.has(cell))
	_check(not lane.is_empty() and joined.call(11, 6) and at_door and in_way.is_empty(),
		"the lane to the inn's door: joins road 6 (%s), reaches the door's outside cells %s (%s), %d cells, nothing in its way (%s)" % [
			joined.call(11, 6) if not lane.is_empty() else false, door_out, at_door, lane.size(), in_way])
	var safe := Level.safe_paths(terrain)
	print("  the wilds' safe paths: %d cells" % safe.size())
	_test_guide_cells(wilds)


## 774 amended (7) (the coordinator's approval, 11-15, for companions' 945, "the first five minutes": she leads a newcomer
## to the Mughouse's door, says what it is and stops; he chooses whether to go in): her stop as level data, the wilds'
## level.json spawn_points "guide_inn" (183, 206) and "guide_inn_2" (183, 205) when the first is taken, north-east of
## the door, off the lane, on no door cell or the cell before it, in sight of the lit front, on level ground as every
## spawn point is (relief_test: (181, 206) and (182, 206), first offered, lie on the inn front's slope). Unseen and unused until
## companions' switch. Nothing that places a player or a body reads those names: the readers of spawn_points checked
## are Main.travel (a link's to_spawn by name, else the level's first start), World._steps_from_spawn
## (a "from" by name), WorldMap's and WorldRoutes' ways (a link's to_spawn), Apex's lair doors ("from_" + a land),
## Main.place_dummies (the practice hall's names beginning "dummy"), Guide._arrival_of (a level's first start, a spawn
## point only for a level with none), the generators' arrivals ("from_" names) and the builder's keep-clear (which
## only keeps building off them); the tours start by cells, never by a spawn name.
func _test_guide_cells(wilds: Dictionary) -> void:
	print("
== her stop by the Mughouse's door: two named cells clear of its door and the lane, never where a body is placed ==")
	var terrain: Dictionary = wilds["terrain"]
	var spawns: Dictionary = wilds["spawn_points"]
	var cells: Array[Vector2i] = []
	for key: String in ["guide_inn", "guide_inn_2"]:
		if spawns.has(key):
			cells.append(spawns[key])
	var inn: Dictionary = {}
	var doors := {}
	for building: Dictionary in wilds["buildings"]:
		if str(building.get("code", "")) == "I1":
			inn = building
		for cell: Vector2i in Main.door_cells(building):
			doors[cell] = str(building.get("code", building.get("slot", "")))
	var inside := Level.building_cells(inn) if not inn.is_empty() else []
	var front: Array[Vector2i] = []
	for cell: Vector2i in Main.door_cells(inn) if not inn.is_empty() else []:
		if not cell in inside:
			front.append(cell)
	var roads: Array = terrain["roads"]
	var lane: Dictionary = Curves.cells(roads[11]["curve"], false) if roads.size() > 11 else {}
	var taken := {}
	for spot: Dictionary in wilds["spots"]:
		taken[spot["cell"]] = "a %s spot" % spot.get("use", "")
	for piece: Variant in terrain.get("decor", []):
		if piece is Dictionary:
			taken[piece["cell"]] = "a %s" % piece.get("kind", "decor piece")
	for spec: Dictionary in wilds["entities"]:
		taken[spec["tile"]] = str(spec.get("name", "an entity"))
	var bad: Array[String] = []
	for cell: Vector2i in cells:
		if not terrain["floor"].has(cell) or terrain["solid"].has(cell):
			bad.append("%s off the floor or solid" % [cell])
		if doors.has(cell):
			bad.append("%s a door cell of %s" % [cell, doors[cell]])
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if lane.has(cell + Vector2i(dx, dy)) and not bad.has("%s on or beside the lane" % [cell]):
					bad.append("%s on or beside the lane" % [cell])
		if taken.has(cell):
			bad.append("%s on %s" % [cell, taken[cell]])
		var near := 99
		for at: Vector2i in front:
			near = mini(near, World.distance(cell, at))
		if near > 3:
			bad.append("%s %d from the door's front %s" % [cell, near, front])
	_check(cells == [Vector2i(183, 206), Vector2i(183, 205)] and front.size() == 2 and not lane.is_empty() and bad.is_empty(),
		"the wilds' guide_inn %s and guide_inn_2: floor, on no door cell or its front %s, off the lane and beside it, no spot, decor or entity, within 3 of the front (%s)" % [
			cells, front, bad])
	# Never a place a body appears: no link in any level names either as where it arrives, the wilds has starts (so a
	# first-start reader never falls back to a spawn point), and neither name is one a reader takes by its prefix.
	var named: Array[String] = []
	for level_name: String in Level.names():
		for link: Dictionary in Level.load_level(level_name).get("links", []):
			if str(link.get("to_spawn", "")).begins_with("guide_"):
				named.append("%s's link at %s" % [level_name, link.get("tile")])
	var keys: Array = spawns.keys()
	_check(named.is_empty() and not (wilds["starts"] as Array).is_empty() and keys.find("guide_inn") > keys.find("from_tavern")
		and not keys.any(func(key: String) -> bool: return key.begins_with("guide_") and (key.begins_with("dummy") or key.begins_with("from_"))),
		"nothing places a body on them: no link arrives at a guide_ point (%s), the wilds has its starts, they come after the arrivals, no reader's prefix" % [named])


## 774 amended (6) (the coordinator's ruling, 11-15, on environment's walk from the new arrival to the Mughouse: it
## stopped twice at a parked cart and a click meant as a walk opened an empty "Cart" window): nothing a click opens
## (a cart, a crate, a chest: Level.CARGO and Level.CHEST) stands (1) within 2 cells of the line from any of the wilds'
## starts to the Mughouse's door, (2) on or beside the newcomer's lane, (3) on any of the wilds' roads; and (4) in
## every level, on a building's door cell or the cell in front of it (Main.door_cells), off the floor or on a solid
## cell, on a cell a closed building stands on (one entered by a link or with no rooms of its own), on a decor piece
## (a mine's cart on its track excepted), or on a resident's spot or a place's seat; one drawn as nothing (the house's
## locker) is never opened by a click and is not counted. Umbrage's two carts moved from (186, 212) and (188, 214) to the store's
## side, (184, 193) and (185, 192) (level.json "moved_markers": a saved world's carts follow, Main._level_spec_for).
func _test_clicked_things_clear(wilds: Dictionary) -> void:
	print("
== nothing a click opens stands in the newcomer's walk, on a door, a building, a decor piece, a spot or a seat ==")
	# Drawn as nothing (Level.UNDRAWN_ART: the house's locker), a click never opens it (734 amended (7)).
	var opened := func(spec: Dictionary) -> bool: return str(spec.get("script", "")) in [Level.CARGO, Level.CHEST] and str(spec.get("art", "")) != Level.UNDRAWN_ART
	var terrain: Dictionary = wilds["terrain"]
	var roads: Array = terrain["roads"]
	var door := Vector2(180, 208.5)
	var lane: Dictionary = Curves.cells(roads[11]["curve"], false) if roads.size() > 11 else {}
	var road_cells := {}
	for road: Dictionary in roads:
		for cell: Vector2i in Curves.cells(road["curve"], false):
			road_cells[cell] = true
	var in_walk: Array[String] = []
	var carts: Array[Vector2i] = []
	for spec: Dictionary in wilds["entities"]:
		if not opened.call(spec):
			continue
		var cell: Vector2i = spec["tile"]
		if str(spec.get("script", "")) == Level.CARGO:
			carts.append(cell)
		for start: Vector2i in wilds["starts"]:
			var a := Vector2(start)
			var t := clampf((Vector2(cell) - a).dot(door - a) / (door - a).length_squared(), 0.0, 1.0)
			if Vector2(cell).distance_to(a.lerp(door, t)) <= 2.0:
				in_walk.append("%s %s within 2 of the line from %s to the Mughouse's door" % [cell, spec.get("name", ""), start])
				break
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if lane.has(cell + Vector2i(dx, dy)) and not in_walk.has("%s on or beside the lane" % [cell]):
					in_walk.append("%s on or beside the lane" % [cell])
		if road_cells.has(cell):
			in_walk.append("%s %s on a road" % [cell, spec.get("name", "")])
	carts.sort()
	_check(not lane.is_empty() and in_walk.is_empty() and Vector2i(184, 193) in carts and Vector2i(185, 192) in carts
		and not Vector2i(186, 212) in carts and not Vector2i(188, 214) in carts,
		"the wilds: no cart, crate or chest by the newcomer's line to the Mughouse's door, on or beside the lane, or on a road; the two carts by the store (%s; %s)" % [carts, in_walk])
	var where := Regen.moved_markers("wilds")
	_check(where == {"186,212": Vector2i(184, 193), "188,214": Vector2i(185, 192)},
		"the wilds' level.json moves the two carts' markers by its word, so a saved world's carts follow them (%s)" % [where])
	var placed: Array[String] = []
	var levels := 0
	for level_name: String in Level.names():
		var level := Level.load_level(level_name)
		if level.is_empty():
			continue
		levels += 1
		var lt: Dictionary = level["terrain"]
		var floor_cells := {}
		for cell: Vector2i in lt["floor"]:
			floor_cells[cell] = true
		var why := {}
		for building: Dictionary in level.get("buildings", []):
			var bname := str(building.get("code", building.get("slot", building.get("kind", "building"))))
			for cell: Vector2i in Main.door_cells(building):
				why[cell] = "the door of %s" % bname
			if building.has("inside") or not building.has("kind"):
				for cell: Vector2i in Level.building_cells(building):
					if not why.has(cell):
						why[cell] = "%s's footprint" % bname
		var tracks := {}
		for piece: Variant in lt.get("decor", []):
			if piece is Dictionary:
				why[piece["cell"]] = "a %s" % str(piece.get("kind", "decor piece"))
				if str(piece.get("kind", "")) == "mine_track":
					tracks[piece["cell"]] = true
		for spot: Variant in level.get("spots", []):
			if spot is Dictionary and spot.get("cell") is Vector2i:
				why[spot["cell"]] = "a %s spot" % str(spot.get("use", ""))
		for key: Variant in level.get("places", {}):
			var place: Variant = level["places"][key]
			if place is Dictionary:
				for seat: Variant in place.get("seats", []):
					if seat is Vector2i:
						why[seat] = "a seat of %s" % key
		for spec: Dictionary in level.get("entities", []):
			if not opened.call(spec):
				continue
			var cell: Vector2i = spec["tile"]
			if not floor_cells.has(cell) or lt.get("solid", {}).has(cell):
				placed.append("%s %s %s off the floor or solid" % [level_name, spec.get("name", ""), cell])
			elif why.has(cell) and not (tracks.has(cell) and str(spec.get("script", "")) == Level.CARGO):  # A mine's cart rides its track.
				placed.append("%s %s %s on %s" % [level_name, spec.get("name", ""), cell, why[cell]])
	_check(levels > 10 and placed.is_empty(), "in all %d levels, no cart, crate or chest on a door or the cell before it, off the floor, on a closed building, a decor piece, a spot or a seat (%d: %s)" % [
		levels, placed.size(), placed.slice(0, 12)])


## Whether [param to] is walked to from [param from] over [param terrain]'s floor: four steps, a wall edge or a
## solid cell stopping it, a door not.
static func _floor_walks(terrain: Dictionary, from: Vector2i, to: Vector2i) -> bool:
	var open := {}
	for cell: Vector2i in terrain["floor"]:
		open[cell] = true
	for cell: Vector2i in terrain.get("solid", []):
		open.erase(cell)
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		if cell == to:
			return true
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := cell + step
			if seen.has(next) or not open.has(next):
				continue
			if terrain["edges"].get(Terrain.edge_key(cell, step)) == Terrain.Edge.WALL:
				continue
			seen[next] = true
			queue.append(next)
	return false


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
## Snagfin's Fishin' Hole (Jeff, 11-12: "Reed Pond and Snagfins Fishin Hole"; the coordinator's
## 803 amended (13) id): the crescent by Snagfin's shack is a fishing place keyed by its pool's own
## key, "pool_221_224", so economy's stock and every pond_at keep the id when terrain grows the
## water; nobody's, a found place by Jeff's name, its circle taking in the crescent's water and no
## other body's.
func _test_fishin_hole() -> void:
	print("\n== Snagfin's Fishin' Hole: the crescent's fishing place keeps its pool's key ==")
	var config := Level.template_config("wilds")
	var warnings: Array[String] = []
	var place: Dictionary = Level.places_from(config, warnings).get("pool_221_224", {})
	var waters := World.fish_waters_of(Level.load_level("wilds")["terrain"])
	var at: Vector2i = place.get("cell", Vector2i(-1, -1))
	var radius: int = place.get("radius", 0)
	var inside := {}
	for cell: Vector2i in waters:
		if (cell - at).length_squared() <= radius * radius:
			inside[waters[cell]] = true
	_check(place.get("kind", "") == "fishing" and place.get("name", "") == "Snagfin's Fishin' Hole" and place.get("holder", "") == Factions.NOBODY
			and place.get("explore", false) == true and inside.size() == 1,
		"pool_221_224: fishing, nobody's, Snagfin's Fishin' Hole, a found place; its circle (%s, %d) takes in one body of water (%s; its own key moves with its first cell, the place's id doesn't)" % [at, radius, inside.keys()])
	# Terrain's bigger pond (559 amended (2)): the whole of that body inside the circle, as at Reed Pond, from a cell on its dry shore.
	var left_out: Array[Vector2i] = []
	for cell: Vector2i in waters:
		if inside.has(waters[cell]) and (cell - at).length_squared() > radius * radius:
			left_out.append(cell)
	_check(inside.size() == 1 and left_out.is_empty() and not at in waters, "the Fishin' Hole's circle holds all of Snagfin's pond (%d cells outside: %s), from a dry cell %s" % [left_out.size(), left_out.slice(0, 6), at])


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
	_check(place.get("kind", "") == "fishing" and place.get("name", "") == "Reed Pond" and place.get("holder", "") == Factions.NOBODY
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
	# Package "Umbrage: the pedlar's stand" (maps' side, in economy's switch take): the visiting pedlar's place at
	# his keeper's cell behind M3, which faces north into the square; he keeps (202..204, 208) (413b0f7b4), served from the north; both rows behind it are checked clear floor.
	var pedlar: Dictionary = wilds["places"].get("pedlar_stall", {})
	var pedlar_side := Rect2i(202, 208, 3, 2)
	var side_clear := true
	for x in range(pedlar_side.position.x, pedlar_side.end.x):
		for y in range(pedlar_side.position.y, pedlar_side.end.y):
			side_clear = side_clear and wilds["terrain"]["floor"].has(Vector2i(x, y)) and not wilds["terrain"]["solid"].has(Vector2i(x, y))
	_check(pedlar.get("cell") == Vector2i(203, 208) and pedlar.get("kind") == "stall" and pedlar.get("radius") == 1 and pedlar.get("worth") == 0
		and pedlar.get("town") == "store" and pedlar.get("holder") == "town" and pedlar.get("explore") == false
		and pedlar.get("name") == "the pedlar's stall" and side_clear
		and wilds["entities"].all(func(spec: Dictionary) -> bool: return not pedlar_side.has_point(spec["tile"])),
		"the place pedlar_stall, a stall worth nothing, at (203, 208) behind M3, his side (202..204, 208..209) clear floor, no marker on it (%s)" % [pedlar])


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
## 947 (Jeff 11-15 18:48: "often you end up in the shell of the mughouse instead of the
## zone"): out of the tavern he stands outside the inn's door, facing away, never in its
## footprint; and set down on a way back, it does not take him till he steps off or his card lifts.
## Since the pocket (811 amended (8)) no arrival stands in a shell, so the hold's rows use a way back
## with no shell, registered in memory; the real levels are searched for a named arrival on one.
func _test_out_of_the_shell() -> void:
	print("
== out of the Mughouse (947): outside its door, facing away; set down on a way back, held till a step off or the lift ==")
	var wilds := Level.load_level("wilds")
	var inns: Array = (wilds["buildings"] as Array).filter(func(each: Dictionary) -> bool: return str(each.get("inside", "")) == "umbrage_tavern")
	_check(inns.size() == 1, "the wilds' inn with the Mughouse inside (%d)" % inns.size())
	if inns.size() != 1:
		return
	var rect: Rect2i = inns[0]["rect"]
	var ins: Array = (wilds["links"] as Array).filter(func(link: Dictionary) -> bool: return link["to_map"] == "umbrage_tavern")
	_main.load_map("test_room")
	_main.travel(Net.local_id, "umbrage_tavern", "from_wilds")
	await get_tree().process_frame
	var tavern := Level.load_level("umbrage_tavern")
	var outs: Array = (tavern["links"] as Array).filter(func(link: Dictionary) -> bool: return link["to_map"] == "wilds")
	_main.travel(Net.local_id, "wilds", str(outs[0]["to_spawn"]) if not outs.is_empty() else "from_tavern")
	await get_tree().process_frame
	var player := _player()
	var at: Vector2i = player.tile if player != null else World.NO_CELL
	_check(_main.map_name == "wilds" and player != null and not rect.has_point(at) and World.distance(at, Rect2i(rect.position - Vector2i.ONE, rect.size + 2 * Vector2i.ONE).get_center()) < 12,
		"out of the tavern: in the wilds, outside the inn's footprint %s, by it (%s)" % [rect, at])
	var inward := Vector2i(clampi(rect.get_center().x - at.x, -1, 1), clampi(rect.get_center().y - at.y, -1, 1))
	_check(player != null and player.facing != Vector2i.ZERO and player.facing.x * inward.x + player.facing.y * inward.y < 0, "facing away from it (%s, the inn %s)" % [player.facing if player else null, inward])
	# Set down off the ways back, he has stood off them: a way in straight away takes him (a fresh click).
	var link_in: Vector2i = ins[0]["tile"] if not ins.is_empty() else World.NO_CELL
	_main._take_link(player, link_in)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_main.map_name == "umbrage_tavern", "arrived off the ways back: the way in takes him at once (%s)" % _main.map_name)
	# Set down on the inn's inside door cell (179,209), in its shell: since the pocket (811 amended (8)) an
	# arrival in a shell's footprint is put outside its door, off the ways back, and the way in takes him at
	# once (terrain's row, changed in maps' take with terrain's yes). Without the pocket he stands on it, held.
	var door_cell := Vector2i(rect.end.x - 1, link_in.y)
	var ways_in: Array = (wilds["links"] as Array).map(func(link: Dictionary) -> Vector2i: return link["tile"])
	_check(rect.has_point(door_cell), "the inn's inside door cell %s lies in its footprint %s" % [door_cell, rect])
	_main.travel(Net.local_id, "wilds", "from_tavern", {}, door_cell)
	await get_tree().process_frame
	player = _player()
	at = player.tile if player != null else World.NO_CELL
	_check(_main.map_name == "wilds" and player != null and not rect.has_point(at) and not at in ways_in,
		"set down on the door cell %s: put outside the inn's footprint, off the ways back (%s)" % [door_cell, at])
	_main._take_link(player, link_in)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_main.map_name == "umbrage_tavern", "and the way in takes him at once (%s)" % _main.map_name)
	# 947's hold stays for a way back with no shell (the console's move, a return to a cell, a builder's
	# level): coming from test_link_b, set down on test_link_a's way to it at (4, 1), held till he steps off,
	# or his card lifts.
	var way_back := Vector2i(4, 1)
	_check(Main.shell_of(Level.load_level("test_link_a"), way_back).is_empty(), "test_link_a's way back to test_link_b at %s has no shell" % way_back)
	_main.load_map("test_link_b")
	for ends: String in ["step", "lift"]:
		_main.travel(Net.local_id, "test_link_a", "", {}, way_back)
		await get_tree().process_frame
		player = _player()
		_main._take_link(player, way_back)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(_main.map_name == "test_link_a" and player != null and player.tile == way_back, "set down on the way back %s, no shell, the way taken before %s: held" % [way_back, ends])
		if ends == "step":
			_main._on_entity_moved(player, way_back, way_back + Vector2i(-1, 0))
		else:
			_main._on_command(player, "view_ready", {"zone": player.zone})
		_main._take_link(player, way_back)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(_main.map_name == "test_link_b", "after his %s, the way back takes him (%s)" % [ends, _main.map_name])
	# Which real levels can still set a player down on a way back by a named arrival: the spawn a link
	# names (or the level's first start) standing on a link back to where he came from, with no building's
	# stair to come out beside. None: the hold guards the console's move, a return to a cell and builders' levels.
	var levels := {}
	for folder in DirAccess.get_directories_at(Level.DIR):
		if Level.DIR + folder + "/" != Prefab.DIR and FileAccess.file_exists(Level.DIR + folder + "/layout.png"):
			levels[folder] = Level.load_level(folder)
	var on_way_back: Array[String] = []
	for from_name: String in levels:
		for link: Dictionary in (levels[from_name] as Dictionary).get("links", []):
			var to_level: Dictionary = levels.get(str(link["to_map"]), {})
			if to_level.is_empty() or Main.building_link_back(to_level, from_name) != World.NO_CELL:
				continue
			var spawns: Dictionary = to_level.get("spawn_points", {})
			var starts: Array = to_level.get("starts", [])
			var arrival: Variant = spawns.get(str(link.get("to_spawn", "")), starts[0] if not starts.is_empty() else null)
			if arrival == null:
				continue
			for back: Dictionary in to_level.get("links", []):
				if back["tile"] == Vector2i(arrival) and str(back["to_map"]) == from_name:
					on_way_back.append("%s to %s at %s" % [from_name, link["to_map"], back["tile"]])
	_check(on_way_back.is_empty(), "no real level's named arrival stands on its way back (%s)" % [on_way_back])
	# Every shell in the wilds: its way out stands outside it, on a free cell, by its rule.
	var was := World.enter_named("wilds")
	var bad: Array[String] = []
	for link: Dictionary in wilds["links"]:
		var shell: Dictionary = Main.shell_of(wilds, link["tile"])
		if shell.is_empty():
			continue
		var out: Array = _main.out_of_shell(wilds, shell, World.NO_CELL)
		if (shell["rect"] as Rect2i).has_point(out[0]) or not World.is_free(out[0]) or (out[1] as Vector2i) == Vector2i.ZERO:
			bad.append("%s %s" % [link["tile"], out])
	World.enter(was)
	_check(bad.is_empty(), "every shell's way out by its doors: outside, free, facing out (%s)" % [bad])
	_main.load_map("test_room")


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
	_test_insides_closed()
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


## 811 amended (8) (the coordinator's bar on Jeff's report, 11-15: "often you end up in the shell of the mughouse instead
## of the zone"): in every level, no cell of a building that has an "inside" level can be stood on from outside it
## but its doorway's cells, each a step from a link, without crossing one: walked from the floor before each of its doors (WorldRoutes._flood, the routes' own
## steps, diagonals and edges), the links as walls, it reaches none of the footprint. On main before the mend the
## Mughouse's links stood a cell in from its door's inside cells, and its other 76 cells were walked to round them.
func _test_insides_closed() -> void:
	print("
== no building with an inside level can be stood in from outside without its links ==")
	var open: Array[String] = []
	var closed := 0
	for level_name: String in Level.names():
		var level := Level.load_level(level_name)
		if level.is_empty():
			continue
		var area: Dictionary = {}
		for building: Dictionary in level.get("buildings", []):
			var inside := str(building.get("inside", ""))
			if inside.is_empty():
				continue
			if area.is_empty():
				area = WorldMap.build([level_name]).areas[level_name]
			var foot := {}
			for cell: Vector2i in Level.building_cells(building):
				foot[cell] = true
			var links := {}
			for link: Dictionary in level["links"]:
				if str(link.get("to_map", "")) == inside:
					links[link["tile"]] = true
			var fronts: Array[Vector2i] = []
			for edge: Vector3i in Level.entrances(building):
				for cell: Vector2i in Terrain.edge_cells(edge):
					if not foot.has(cell) and (area["floor"] as Dictionary).has(cell):
						fronts.append(cell)
			var reached := {}
			for front: Vector2i in fronts:
				reached.merge(WorldRoutes._flood(area, front, foot, PackedFloat32Array(), links))
			# Its doorway's cells beside a link are the step before the crossing: stood on, and the next step is in.
			for cell: Vector2i in reached.keys():
				if fronts.any(func(front: Vector2i) -> bool: return World.distance(front, cell) <= 1) 						and links.keys().any(func(link: Vector2i) -> bool: return (link - cell).abs().x + (link - cell).abs().y == 1):
					reached.erase(cell)
			if fronts.is_empty() or links.is_empty() or not reached.is_empty():
				open.append("%s %s: %d of %d cells walked to from %s without its links %s" % [level_name, building.get("code", building.get("slot", "")),
					reached.size(), foot.size(), fronts, links.keys()])
			else:
				closed += 1
	_check(closed >= 1 and open.is_empty(), "every building with an inside level (%d) is entered only by its links: none of its cells stood on from outside (%s)" % [closed, open])


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
		"the inn's way in: a cell in from its door, to the ground floor, closed unless the inn stands (%s)" % [tiles])
	# 811 amended (8): its footprint's floor is its links and its door's two inside cells, the rest solid.
	var mughouse: Dictionary = (wilds["buildings"] as Array).filter(func(b: Dictionary) -> bool: return str(b.get("code", "")) == "I1")[0]
	var floor_in: Array[Vector2i] = []
	var solid_in := 0
	var solid_set := {}
	for cell: Vector2i in wilds["terrain"]["solid"]:
		solid_set[cell] = true
	var floor_set := {}
	for cell: Vector2i in wilds["terrain"]["floor"]:
		floor_set[cell] = true
	for cell: Vector2i in Level.building_cells(mughouse):
		if floor_set.has(cell):
			floor_in.append(cell)
		elif solid_set.has(cell):
			solid_in += 1
	floor_in.sort()
	_check(floor_in == [Vector2i(178, 208), Vector2i(178, 209), Vector2i(179, 208), Vector2i(179, 209)] and solid_in == Level.building_cells(mughouse).size() - 4
		and Level.shell_pocket(wilds, mughouse).size() == 4,
		"the Mughouse's floor is its two links and its door's two inside cells, its other %d cells solid (floor %s)" % [solid_in, floor_in])
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
	var stores := func(level: Dictionary) -> Array: return (level["terrain"]["decor"] as Array).map(func(piece: Dictionary) -> String: return piece["kind"]).filter(func(kind: String) -> bool: return kind != "stool")
	_check(stores.call(ground) == ["wall_hearth", "crate", "barrel"] and stores.call(floors["umbrage_tavern_attic"]) == ["crate", "barrel", "sack", "crate"],
		"the kitchen's and the attic's stores drawn as decor, nothing to open (%s)" % [stores.call(floors["umbrage_tavern_attic"])])
	# Its stools (875, maps' side): one under every sit spot, the five round the hearth and the tables' eight seats.
	var stools: Array = (ground["terrain"]["decor"] as Array).filter(func(piece: Dictionary) -> bool: return piece["kind"] == "stool").map(func(piece: Dictionary) -> Vector2i: return piece["cell"])
	var seats: Array = (ground["places"]["tavern"].get("seats", []) as Array)
	var sits: Array = (ground.get("spots", []) as Array).filter(func(spot: Dictionary) -> bool: return spot["pose"] == "sit").map(func(spot: Dictionary) -> Vector2i: return spot["cell"])
	_check(stools.size() == 13 and seats.all(func(seat: Vector2i) -> bool: return stools.has(seat)) and sits.all(func(cell: Vector2i) -> bool: return stools.has(cell)),
		"the Mughouse's thirteen stools: every table seat and every sit spot has one (%d stools, %d sits)" % [stools.size(), sits.size()])
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


## A click on a niche's stone (608 amended (8); Jeff's report, reproduced on
## main 11-16: on the niche's floor cell a click on it did nothing): Main's
## click (_niche_click) walks to its floor cell and leans into the stone,
## so the server's press answers: a plain niche's line from its floor cell
## and from the hall; the hidden one, its way not revealed, the same line and
## shut; revealed, it opens from the hall and from its floor cell, and the
## found hold holds the client's own route too (_found_hold); under the keys'
## scheme a click is no niche's; a click elsewhere drops a far one.
func _test_niche_click() -> void:
	print("\n== a click on a niche's stone (608 amended (8)): walked to, leaned into, pressed; every niche; the hidden one revealed and not; the found hold ==")
	if World.economy == null:
		_check(false, "no economy to read the robbers' barrow from")
		return
	var rules: Dictionary = World.economy.rules.get("robbers", {}).duplicate(true)
	World.economy.rules["robbers"] = rules.merged({"barrow": "lt_niche"}, true)
	_register_niche("lt_niche")
	_main.load_map("lt_niche")
	var kept: Variant = _main._regen.get("lt_niche")
	_main._regen["lt_niche"] = {"generation": 1, "at_step": 0, "robbers_down": true}
	var player := _player()
	var own = _main._free_own(player)
	var key := Terrain.edge_key(Vector2i(6, 1), Vector2i(0, -1))
	var door := World.door_on(key)
	var controls: String = Net.controls
	Net.controls = "click"
	_main.mark_player(player.player_id, Main.QUEST_DONE, false)
	var heard: Array[String] = []
	var hear := func(kind: String, data: Dictionary) -> void:
		if kind == "party":
			heard.append(str(data.get("text", "")))
	Net.message_received.connect(hear)
	var ready := own != null and World.free_body(player) and door != null and not door.open
	_check(ready, "the player's free body, its own view, the hidden niche shut")
	if ready:
		_check(_main.niche_at(Vector2i(2, 0)) == {"edge": Terrain.edge_key(Vector2i(2, 1), Vector2i(0, -1)), "floor": Vector2i(2, 1), "way": Vector2(0, -1)}
			and _main.niche_at(Vector2i(2, 1)).is_empty() and _main.niche_at(Vector2i(3, 0)).is_empty() and not _main.niche_at(Vector2i(6, 0)).is_empty(),
			"niche_at: a niche's stone names it (its edge, its floor cell, the way in); its floor cell and the wall beside it are none (%s)" % [_main.niche_at(Vector2i(2, 0))])
		var shut := Main.NICHE_SHUT_LINE
		var slab := "The slab swings aside: a stair goes down into the dark."
		_put(player, Vector2i(2, 1))
		var told := _click_niche(player, Vector2i(2, 0), heard, 240)
		_check(told == [shut] and player.tile == Vector2i(2, 1), "on a plain niche's floor cell, a click on its stone presses it: the shut line (%s, at %s)" % [told, player.tile])
		_put(player, Vector2i(4, 4))
		told = _click_niche(player, Vector2i(4, 0), heard, 1200)
		_check(told == [shut] and player.tile == Vector2i(4, 1), "from the hall, a click on another niche's stone walks to it and presses it (%s, at %s)" % [told, player.tile])
		_put(player, Vector2i(5, 4))
		told = _click_niche(player, Vector2i(6, 0), heard, 1200)
		_check(told == [shut] and not door.open and player.tile == Vector2i(6, 1),
			"the hidden niche, its way not revealed, clicked from the hall: walked to, the shut line, shut (%s, at %s)" % [told, player.tile])
		_main._told_niche.erase(player.owner_peer)  # Said once a stand: a new stand for the next.
		told = _click_niche(player, Vector2i(6, 0), heard, 240)
		_check(told == [shut] and not door.open, "and clicked from its floor cell: the shut line, shut (%s)" % [told])
		_main.mark_player(player.player_id, Main.QUEST_DONE)
		_put(player, Vector2i(5, 4))
		told = _click_niche(player, Vector2i(6, 0), heard, 1200)
		_check(told == [slab] and door.open and player.tile == Vector2i(6, 1), "revealed, clicked from the hall: walked to, the slab opens (%s, at %s)" % [told, player.tile])
		_main._update_niche()
		_check(_main._free_own(player) != null and _main._free_own(player).held_by_server(player), "found beside me, the client's own body is held through the slab's swing (FreeNet.Own.hold_until)")
		_hold_free(player, Vector2.ZERO, Main.NICHE_FOUND_HOLD + 1)
		door.open = false
		door.lock = Main.HIDDEN_LOCK
		_main._update_niche()
		told = _click_niche(player, Vector2i(6, 0), heard, 240)
		_check(told == [slab] and door.open, "shut again, clicked from its floor cell: the slab opens (%s)" % [told])
		_hold_free(player, Vector2.ZERO, Main.NICHE_FOUND_HOLD + 1)
		_main._niche_lean = {}
		_check(_main.niche_at(Vector2i(6, 0)).is_empty(), "its door open, its stone is no niche to press: a click there walks to the stair")
		_put(player, Vector2i(3, 3))
		_check(_main._niche_click(player, Vector2i(2, 0)) and not _main._niche_wanted.is_empty(), "a far niche's click waits for the walk")
		_main._move_click(player, Vector2i(1, 4))
		_check(_main._niche_wanted.is_empty(), "a click elsewhere after it drops it")
		Net.controls = "wasd"
		_check(not _main._niche_click(player, Vector2i(2, 0)), "under the keys' scheme a click is no niche's (a key walk into a niche presses as ever)")
	_main._niche_lean = {}
	_main._niche_wanted = {}
	_main._free["path"] = []  # The last click's route walked by no later test.
	Net.controls = controls
	Net.message_received.disconnect(hear)
	_main.mark_player(player.player_id, Main.QUEST_DONE, false)
	World.economy.rules["robbers"] = rules
	if kept == null:
		_main._regen.erase("lt_niche")
	else:
		_main._regen["lt_niche"] = kept
	_main.load_map("test_room")
	Level.unregister("lt_niche")


## Main's click on a niche's [param stone] (_niche_click), then its frames
## as a player's: _free_drive and _update_niche each frame, the world a tick
## every 6 frames (the throne's click rows' drive), till a "party" line is
## heard or [param frames] pass; the lines heard since.
func _click_niche(player: Player, stone: Vector2i, heard: Array[String], frames: int) -> Array[String]:
	var before := heard.size()
	player.free_view = null
	player.free_halt_until = 0
	if not _main._niche_click(player, stone):
		return ["(no niche click)"]
	for i in frames:
		player.free_allowance = World.FREE_COMMANDS_PER_SECOND  # The test runs faster than the clock.
		_main._free_drive(1.0 / 60.0)
		_main._update_niche()
		if i % 6 == 5:
			World.step()
		if heard.size() > before:
			break
	_main._niche_lean = {}
	return heard.slice(before)


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


## Steps the world until [param entity] may move again.
func _wait_for_step(entity: GridEntity) -> void:
	for i in 10:
		if World.tick >= entity.next_move_tick and not World.is_stunned(entity):
			return
		World.step()


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
