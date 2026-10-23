extends Node

const Tools := preload("res://sim/level_gen/gen_tools.gd")
## The labyrinth generator (decision 470): rooms and halls between the
## anchors in the dwarven style and caverns and crooked ways in the old
## style, on the plan sheet's sample halls: the anchors verbatim, every
## anchor reached, rooms in the rock, doors and torches in the dwarven
## style only, the markers the block asks for laid, the same seed the same
## map and another generation another map, the block's own keys passed
## through Level.regenerate_from, and the plan sheet written. Run it with
## tests/run.ps1 or tests/run.sh.

const Sheet := preload("res://tools/plan_sheet.gd")

var _failures := 0


func _ready() -> void:
	World.set_process(false)
	Net.port = preload("res://tests/test_ports.gd").of(17861)
	for style in ["dwarven", "old", "barrow", "barrow_deep", "barrow_lair"]:
		var sample := Sheet.sample_halls(style)
		Level.register("lab_" + style, sample["layout"], null, sample["config"])
	_test_block()
	_test_style("dwarven")
	_test_style("old")
	_test_barrow()
	_test_sheet()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_block() -> void:
	print("\n== the block's own keys reach the generator ==")
	var warnings: Array[String] = []
	var read := Level.regenerate_from(Sheet.sample_halls("old")["config"], warnings)
	_check(read["generator"] == "labyrinth" and read["style"] == "old" and read["rooms"] == {"count": [8, 12], "size": [[3, 3], [7, 6]]}
		and read["loops"] == 0.2 and read["chests"] == 3 and read["crates"] == 4 and read["monsters"] == {"imp": 6, "brute": 2, "sneak": 2}
		and warnings.is_empty(), "style, rooms, loops, chests and crates come through beside the rest (%s)" % [read.keys()])
	_check(Regen.marked("lab_dwarven") and Regen.config_of("lab_dwarven")["anchors"].size() == 4, "the sample halls regenerate, four anchors")
	_check(Regen.config_of("lab_barrow")["anchors"].size() == 4 and Regen.config_of("lab_barrow")["near"] == {"robber": "altar"} and Regen.config_of("lab_barrow_deep")["anchors"].size() == 2 and Regen.config_of("lab_barrow_lair")["anchors"].size() == 2, "the sample barrow's layers regenerate: four anchors, then two, then two (580), the robbers sent near the altar")


func _test_style(style: String) -> void:
	print("\n== the %s style ==" % style)
	var name := "lab_" + style
	var first := Regen.generate(name, 1)
	var second := Regen.generate(name, 2)
	_check(not first.is_empty() and not second.is_empty(), "generations 1 and 2 are made (%d and %d tries)" % [first.get("tries", 0), second.get("tries", 0)])
	if first.is_empty() or second.is_empty():
		return
	var config: Dictionary = first["config"]
	var anchors: Array = first["anchors"]
	var template := LevelMap.from_image(Level.template(name)["layout"], config)
	var a := LevelMap.from_image(first["layout"], config)
	var b := LevelMap.from_image(second["layout"], config)
	var inside_same := true
	var outside_differ := 0
	var outside_floor := 0
	var blocks := 0  # 3 x 3 blocks of floor outside the anchors: rooms.
	for y in Sheet.SIZE.y:
		for x in Sheet.SIZE.x:
			var cell := Vector2i(x, y)
			if Level.in_anchors(anchors, cell):
				if a.cell(cell) != template.cell(cell) or b.cell(cell) != template.cell(cell):
					inside_same = false
				for side in [Terrain.EAST, Terrain.SOUTH]:
					var key := Vector3i(x, y, side)
					if a.edge(key) != template.edge(key) or b.edge(key) != template.edge(key):
						inside_same = false
				continue
			if a.cell(cell) != b.cell(cell):
				outside_differ += 1
			if a.walkable(cell):
				outside_floor += 1
				var block := true
				for dy in 3:
					for dx in 3:
						var other := cell + Vector2i(dx, dy)
						if Level.in_anchors(anchors, other) or not a.walkable(other):
							block = false
				if block:
					blocks += 1
	_check(inside_same, "inside the anchors both generations are the template, cell for cell and edge for edge")
	_check(outside_differ > 50, "outside them they differ (%d cells)" % outside_differ)
	_check(outside_floor > 150, "rooms and ways fill the rock between (%d cells)" % outside_floor)
	_check(blocks >= 6, "rooms, not only corridors: %d cells start a 3 x 3 block of floor" % blocks)
	_check(Regen.connected(a, anchors) and Regen.connected(b, anchors), "every anchor reaches every other in both")
	_check(Tools.narrow_runs(a).is_empty() and Tools.narrow_runs(b).is_empty(), "no passage is one cell wide in either (%s; %s)" % [Tools.sorted_cells(Tools.narrow_runs(a)).slice(0, 8), Tools.sorted_cells(Tools.narrow_runs(b)).slice(0, 8)])
	_check(_cut_off(a, Vector2i(4, 4)).is_empty() and _cut_off(b, Vector2i(4, 4)).is_empty(), "no room is cut off from the gatehouse")
	var again := Regen.generate(name, 1)
	_check(again["seed"] == first["seed"] and again["layout"].get_data() == first["layout"].get_data(), "the same seed gives the same map (seed %d)" % first["seed"])
	var level := Level.parse(first["layout"], null, config)
	var doors := 0
	var doors_between_floor := true
	var floor_set := {}
	for cell: Vector2i in level["terrain"]["floor"]:
		floor_set[cell] = true
	for key: Vector3i in level["terrain"]["edges"]:
		if level["terrain"]["edges"][key] == Terrain.Edge.DOOR:
			doors += 1
			var sides := Terrain.edge_cells(key)
			if not floor_set.has(sides[0]) or not floor_set.has(sides[1]):
				doors_between_floor = false
	var torches: int = level["terrain"]["torches"].size()
	if style == "dwarven":
		_check(doors >= 4 and doors_between_floor, "doors where the ways meet the rooms, each between two floor cells (%d)" % doors)
		_check(torches >= 4, "torches along the ways and inside the doors (%d)" % torches)
	else:
		_check(doors == 0 and torches == 0, "no doors and no torches in the old labyrinths (%d, %d)" % [doors, torches])
	var kinds := {}
	for spec: Dictionary in level["entities"]:
		var kind := str(spec.get("kind", spec["name"].rstrip("0123456789").to_lower()))
		kinds[kind] = int(kinds.get(kind, 0)) + 1
	_check(kinds.get("imp", 0) == 6 and kinds.get("brute", 0) == 2 and kinds.get("sneak", 0) == 2 and kinds.get("chest", 0) == 3 and kinds.get("crate", 0) == 4,
		"six imps, two brutes, two sneaks, three chests and four crates laid (%s)" % [kinds])
	var beside := 0
	for spec: Dictionary in level["entities"]:
		for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if Level.in_anchors(anchors, spec["tile"] + direction):
				beside += 1
	_check(beside == 0, "none of them beside an anchor")
	_check(level["warnings"].is_empty() and level["links"].size() == 2 and level["spawn_points"].size() == 2,
		"no warnings; the links and spawn points in the anchors kept (%s)" % [level["warnings"]])


func _test_barrow() -> void:
	print("\n== the barrow style in layers (decisions 541, 580): the town's tombs shallow, the Ossuary by depth, the dark below all deep ==")
	# Layer 1: the first hall, the altar room and the town's tombs, every room shallow.
	var first := Regen.generate("lab_barrow", 1)
	var second := Regen.generate("lab_barrow", 2)
	_check(not first.is_empty() and not second.is_empty(), "layer 1: generations 1 and 2 are made (%d and %d tries)" % [first.get("tries", 0), second.get("tries", 0)])
	if first.is_empty() or second.is_empty():
		return
	var config: Dictionary = first["config"]
	var anchors: Array = first["anchors"]
	var template := LevelMap.from_image(Level.template("lab_barrow")["layout"], config)
	var a := LevelMap.from_image(first["layout"], config)
	var b := LevelMap.from_image(second["layout"], config)
	# The hall's columns (x 27 and 52) hold the hidden niche's alcove, the one
	# change a generation makes inside an anchor (608).
	var columns := func(cell: Vector2i) -> bool:
		return Sheet.HALL.has_point(cell) and (cell.x == Sheet.HALL.position.x or cell.x == Sheet.HALL.end.x - 1)
	var kept := _anchors_kept(template, a, b, anchors, Sheet.BARROW_SIZE, columns)
	var floor_cells := _floor_of(a, Sheet.BARROW_SIZE)
	_check(kept["same"], "inside the four anchors both generations are the template: the first hall with its table, the altar and its guards, Pip's niche, the camp with the Runner's pack")
	_check(kept["differ"] > 50 and floor_cells.size() > 800, "the tombs between differ (%d cells) and fill the rock (%d floor cells)" % [kept["differ"], floor_cells.size()])
	_check(Regen.connected(a, anchors) and Regen.connected(b, anchors), "every anchor reaches every other in both")
	_check(Tools.narrow_runs(a).is_empty() and Tools.narrow_runs(b).is_empty(), "no passage is one cell wide in either (%s; %s)" % [Tools.sorted_cells(Tools.narrow_runs(a)).slice(0, 8), Tools.sorted_cells(Tools.narrow_runs(b)).slice(0, 8)])
	_check(_cut_off(a, Sheet.BARROW_FROM_WILDS).is_empty() and _cut_off(b, Sheet.BARROW_FROM_WILDS).is_empty(),
		"nothing is cut off from the first hall (%s; %s)" % [_cut_off(a, Sheet.BARROW_FROM_WILDS).slice(0, 6), _cut_off(b, Sheet.BARROW_FROM_WILDS).slice(0, 6)])
	var hall_floor := 0
	var in_walls := 0
	for cell in floor_cells:
		if Sheet.HALL.has_point(cell):
			hall_floor += 1
			if cell.x == Sheet.HALL.position.x or cell.x == Sheet.HALL.end.x - 1:
				in_walls += 1
	_check(hall_floor == 24 * 16 - 6 + 5 and in_walls == 5 and not a.walkable(Vector2i(39, 8)),
		"the first hall: 24 x 16 of floor less the table's six cells, a bay two rows tall each side and the hidden niche's alcove in the walls (%d floor, %d in the walls)" % [hall_floor, in_walls])
	var level := Level.parse(first["layout"], null, config)
	var doors := 0
	for key: Vector3i in level["terrain"]["edges"]:
		if level["terrain"]["edges"][key] == Terrain.Edge.DOOR:
			doors += 1
	var kinds := _kinds(level)
	_check(doors >= 4 and level["terrain"]["torches"].size() >= 8,
		"layer 1 is all shallow: the town's tombs have doors and the ways their torches (%d doors, %d torches)" % [doors, level["terrain"]["torches"].size()])
	_check(kinds.get("robber", 0) == 4 and kinds.get("chest", 0) == 3 and kinds.get("altar", 0) == 1 and kinds.get("skeleton_guard", 0) == 2
		and kinds.get("runner's pack", 0) == 1 and kinds.get("skeleton", 0) == 0,
		"four robbers and three chests laid; the altar, its two guards and the Runner's pack kept; no dead walk (%s)" % [kinds])
	var altar := Sheet.BARROW_ALTAR
	var robber_to_altar := 0.0
	var all_to_altar := 0.0
	for spec: Dictionary in level["entities"]:
		if str(spec.get("kind", "")) == "robber":
			robber_to_altar += absi(spec["tile"].x - altar.x) + absi(spec["tile"].y - altar.y)
	for cell in floor_cells:
		all_to_altar += absi(cell.x - altar.x) + absi(cell.y - altar.y)
	_check(kinds.get("robber", 0) == 4 and robber_to_altar / 4.0 < all_to_altar / floor_cells.size(),
		"the robbers, sent near the altar, stand closer to it than the floor's mean (%.1f against %.1f)" % [robber_to_altar / 4.0, all_to_altar / floor_cells.size()])
	_check(config.get("graves", []).is_empty(), "layer 1 lists no graves: no dead walk it")
	# The hidden door (608): one of the first hall's 14 niches, picked with
	# the seed, its alcove carved behind a door edge with the stair in it.
	var niches: Array = config.get("niches", [])
	var hidden: Array = niches.filter(func(n: Array) -> bool: return str(n[4]) == "hidden")
	var kinds_ok := niches.all(func(n: Array) -> bool: return str(n[4]) in ["a", "c", "hidden"] and int(n[5]) in [1, 2])
	var on_walls := true
	for n: Array in niches:
		var cell := Vector2i(int(n[0]), int(n[1]))
		var step := Vector2i(int(n[2]), int(n[3]))
		var on_wall: bool = cell.x == 28 and step == Vector2i(-1, 0) or cell.x == 51 and step == Vector2i(1, 0)
		if not a.walkable(cell) or int(n[1]) not in Sheet.HALL_NICHE_ROWS or not on_wall or a.walkable(cell + step) != (str(n[4]) == "hidden"):
			on_walls = false
	_check(niches.size() == 14 and hidden.size() == 1 and kinds_ok and on_walls,
		"the first hall's 14 niches are listed on its two long walls, arches and hollows with a slab now and then, rock behind each but the hidden one (%s)" % [niches])
	if hidden.size() == 1:
		var before := Vector2i(int(hidden[0][0]), int(hidden[0][1]))
		var alcove := before + Vector2i(int(hidden[0][2]), int(hidden[0][3]))
		var key := Terrain.edge_key(before, alcove - before)
		_check(a.cell(alcove) == "link" and a.edge(key) == "door" and level["terrain"]["edges"].get(key) == Terrain.Edge.DOOR
			and level["links"][1]["tile"] == alcove and level["links"][1]["hidden"] and level["spawn_points"]["from_below"] == before
			and level["terrain"]["niches"].size() == 14 and level["terrain"]["niches"].filter(func(n: Dictionary) -> bool: return n["kind"] == "hidden")[0]["edge"] == key,
			"the hidden niche's alcove holds the stair link (hidden) behind a door edge, from_below before it, and the parse reads all 14 (%s %s)" % [before, alcove])
		_check(alcove == Sheet.BARROW_STAIR or not a.walkable(Sheet.BARROW_STAIR) and a.edge(Terrain.edge_key(Sheet.BARROW_FROM_BELOW, Vector2i(1, 0))) == "clear",
			"the template's own alcove is rock again, its door edge gone, unless it is the pick (%s)" % [alcove])
	var picks := {}
	for generation in range(1, 7):
		var made := Regen.generate("lab_barrow", generation)
		for n: Array in made.get("config", {}).get("niches", []):
			if str(n[4]) == "hidden":
				picks[Vector2i(int(n[0]), int(n[1]))] = true
	_check(picks.size() >= 2, "the pick moves between generations (%d different over six)" % picks.size())
	_check(level["warnings"].is_empty() and level["links"].size() == 2 and level["links"][1]["to_map"] == "barrow_deep" and level["spawn_points"].size() == 2 and level["places"].has("niche"),
		"no warnings; the way up and the stair down kept, the spawn points, Pip's niche place (%s)" % [level["warnings"]])
	_check(_broad(a, floor_cells) * 10 >= floor_cells.size() * 8, "the ways are five wide: most floor cells have floor on two opposite sides (%d of %d)" % [_broad(a, floor_cells), floor_cells.size()])
	_check(Regen.generate("lab_barrow", 1)["layout"].get_data() == first["layout"].get_data(), "the same seed gives the same layer")
	# Layer 2: the Ossuary, the tombs by depth from the stair foot, ways five wide.
	var deep := Regen.generate("lab_barrow_deep", 1)
	var deep2 := Regen.generate("lab_barrow_deep", 2)
	_check(not deep.is_empty() and not deep2.is_empty(), "layer 2: generations 1 and 2 are made (%d and %d tries)" % [deep.get("tries", 0), deep2.get("tries", 0)])
	if deep.is_empty() or deep2.is_empty():
		return
	config = deep["config"]
	anchors = deep["anchors"]
	template = LevelMap.from_image(Level.template("lab_barrow_deep")["layout"], config)
	a = LevelMap.from_image(deep["layout"], config)
	b = LevelMap.from_image(deep2["layout"], config)
	kept = _anchors_kept(template, a, b, anchors, Sheet.DEEP_SIZE)
	floor_cells = _floor_of(a, Sheet.DEEP_SIZE)
	_check(kept["same"], "inside the two anchors both generations are the template: the stair foot and the stair down")
	_check(kept["differ"] > 100 and floor_cells.size() > 1200, "the tombs between differ (%d cells) and fill the rock (%d floor cells)" % [kept["differ"], floor_cells.size()])
	_check(Regen.connected(a, anchors) and Regen.connected(b, anchors), "every anchor reaches every other in both")
	_check(Tools.narrow_runs(a).is_empty() and Tools.narrow_runs(b).is_empty(), "no passage is one cell wide in either (%s; %s)" % [Tools.sorted_cells(Tools.narrow_runs(a)).slice(0, 8), Tools.sorted_cells(Tools.narrow_runs(b)).slice(0, 8)])
	_check(_cut_off(a, Sheet.DEEP_FROM_ABOVE).is_empty() and _cut_off(b, Sheet.DEEP_FROM_ABOVE).is_empty(),
		"nothing is cut off from the stair foot (%s; %s)" % [_cut_off(a, Sheet.DEEP_FROM_ABOVE).slice(0, 6), _cut_off(b, Sheet.DEEP_FROM_ABOVE).slice(0, 8)])
	# Depth from the stair foot's centre, (50, 4); the farthest corner lies
	# 125 cells off, so the shallow band ends under 42.5 and the middle
	# under 83.75: a cell 43 or more away lies below the shallow band. A
	# tomb is shallow by its centre and up to 16 x 12, and a way through it
	# gets a door on its far side too (612), so its doors and torches may
	# lie up to 14 cells deeper than its band: 57 is the line for those.
	var entrance := Vector2i(50, 4)
	var depth := func(cell: Vector2i) -> int: return absi(cell.x - entrance.x) + absi(cell.y - entrance.y)
	level = Level.parse(deep["layout"], null, config)
	doors = 0
	var deep_doors := 0
	for key: Vector3i in level["terrain"]["edges"]:
		if level["terrain"]["edges"][key] == Terrain.Edge.DOOR:
			doors += 1
			var sides := Terrain.edge_cells(key)
			if not Level.in_anchors(anchors, sides[0]) and not Level.in_anchors(anchors, sides[1]) and depth.call(sides[0]) >= 57:
				deep_doors += 1
	var torches: Array = level["terrain"]["torches"]
	var deep_torches: int = torches.filter(func(cell: Vector2i) -> bool: return depth.call(cell) >= 57).size()
	_check(doors >= 2 and deep_doors == 0, "doors on the shallow tombs alone (%d doors, %d below the band)" % [doors, deep_doors])
	_check(torches.size() >= 2 and deep_torches == 0, "torches in the shallow band alone (%d, %d below it)" % [torches.size(), deep_torches])
	var mean_floor := 0.0
	for cell in floor_cells:
		mean_floor += depth.call(cell)
	mean_floor /= floor_cells.size()
	kinds = _kinds(level)
	var chest_depth := 0.0
	var skeleton_depth := 0.0
	for spec: Dictionary in level["entities"]:
		var kind := str(spec.get("kind", spec["name"].rstrip("0123456789").to_lower()))
		if kind == "chest":
			chest_depth += depth.call(spec["tile"])
		elif kind == "skeleton":
			skeleton_depth += depth.call(spec["tile"])
	_check(kinds.get("skeleton", 0) == 6 and kinds.get("chest", 0) == 5 and kinds.get("robber", 0) == 0 and not kinds.has("altar"),
		"six skeletons and five chests laid; no robbers, no altar (%s)" % [kinds])
	if kinds.get("skeleton", 0) == 6 and kinds.get("chest", 0) == 5:
		_check(chest_depth / 5.0 > mean_floor and skeleton_depth / 6.0 > mean_floor,
			"the grave goods and the dead lie deeper than the floor's mean depth (%.1f, %.1f over %.1f)" % [chest_depth / 5.0, skeleton_depth / 6.0, mean_floor])
	_check(level["warnings"].is_empty() and level["links"].size() == 2 and level["links"][0]["to_map"] == "barrow" and level["links"][1]["to_map"] == "barrow_lair"
		and level["spawn_points"].size() == 2, "no warnings; the stairs up and down and the spawn points (%s)" % [level["warnings"]])
	_check(Regen.generate("lab_barrow_deep", 1)["layout"].get_data() == deep["layout"].get_data(), "the same seed gives the same Ossuary")
	# The graves (542 amended): every dead end outside the anchors, bar the
	# chests, with its band.
	var graves: Array = config.get("graves", [])
	var dead_ends := 0
	var chests_in := 0
	var bands_ok := true
	for cell in floor_cells:
		var open := 0
		for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if a.walkable(cell + direction) and a.edge(Terrain.edge_key(cell, direction)) != "wall":
				open += 1
		if open == 1 and a.cell(cell) != "chest":
			dead_ends += 1
	for grave: Array in graves:
		var cell := Vector2i(int(grave[0]), int(grave[1]))
		if a.cell(cell) == "chest" or Level.in_anchors(anchors, cell):
			chests_in += 1
		var band_wanted := 0 if depth.call(cell) < 43 else (1 if depth.call(cell) < 84 else 2)
		if int(grave[2]) != band_wanted:
			bands_ok = false
	_check(graves.size() >= 6 and graves.size() == dead_ends and chests_in == 0 and bands_ok,
		"the generated config lists every dead end outside the anchors as a grave with its band, none on a chest (%d graves, %d dead ends)" % [graves.size(), dead_ends])
	# The Ossuary's niches (608): cut into the galleries' walls, rock behind
	# each, shelves and columbarium cells with a hollow here and there.
	niches = config.get("niches", [])
	var deep_niches_ok := niches.size() >= 10
	var cells_used := {}
	var deep_kinds := {}
	for niche: Array in niches:
		var cell := Vector2i(int(niche[0]), int(niche[1]))
		var step := Vector2i(int(niche[2]), int(niche[3]))
		deep_kinds[str(niche[4])] = int(deep_kinds.get(str(niche[4]), 0)) + 1
		if not a.walkable(cell) or a.walkable(cell + step) or a.edge(Terrain.edge_key(cell, step)) == "door" or Level.in_anchors(anchors, cell) \
				or str(niche[4]) not in ["b", "c", "d"] or int(niche[5]) not in [1, 2] or cells_used.has(cell):
			deep_niches_ok = false
		cells_used[cell] = true
	_check(deep_niches_ok and deep_kinds.has("b") and deep_kinds.has("d") and level["terrain"]["niches"].size() == niches.size(),
		"the Ossuary's niches are cut into its walls with rock behind, one a cell, shelves and columbarium cells with hollows among them, none in an anchor, and the parse keeps every one (%d: %s)" % [niches.size(), deep_kinds])
	_check(_broad(a, floor_cells) * 10 >= floor_cells.size() * 8, "the ways are five wide: most floor cells have floor on two opposite sides (%d of %d)" % [_broad(a, floor_cells), floor_cells.size()])
	# Layer 3: the dark below, every room deep, and the Hall of Fallen Souls kept whole.
	var dark := Regen.generate("lab_barrow_lair", 1)
	var dark2 := Regen.generate("lab_barrow_lair", 2)
	_check(not dark.is_empty() and not dark2.is_empty(), "layer 3: generations 1 and 2 are made (%d and %d tries)" % [dark.get("tries", 0), dark2.get("tries", 0)])
	if dark.is_empty() or dark2.is_empty():
		return
	config = dark["config"]
	anchors = dark["anchors"]
	template = LevelMap.from_image(Level.template("lab_barrow_lair")["layout"], config)
	a = LevelMap.from_image(dark["layout"], config)
	b = LevelMap.from_image(dark2["layout"], config)
	kept = _anchors_kept(template, a, b, anchors, Sheet.LAIR_SIZE)
	floor_cells = _floor_of(a, Sheet.LAIR_SIZE)
	_check(kept["same"], "inside the two anchors both generations are the template: the stair foot, and the hall with its pillars, table, throne and the hidden way out")
	_check(Regen.connected(a, anchors) and Regen.connected(b, anchors) and _cut_off(a, Sheet.LAIR_FROM_ABOVE).is_empty() and _cut_off(b, Sheet.LAIR_FROM_ABOVE).is_empty(),
		"the hall is reached from the stair foot in both, nothing cut off (%s; %s)" % [_cut_off(a, Sheet.LAIR_FROM_ABOVE).slice(0, 6), _cut_off(b, Sheet.LAIR_FROM_ABOVE).slice(0, 6)])
	_check(Tools.narrow_runs(a).is_empty() and Tools.narrow_runs(b).is_empty(), "no passage is one cell wide in the dark below either (%s; %s)" % [Tools.sorted_cells(Tools.narrow_runs(a)).slice(0, 8), Tools.sorted_cells(Tools.narrow_runs(b)).slice(0, 8)])
	level = Level.parse(dark["layout"], null, config)
	doors = 0
	for key: Vector3i in level["terrain"]["edges"]:
		if level["terrain"]["edges"][key] == Terrain.Edge.DOOR:
			doors += 1
	kinds = _kinds(level)
	_check(doors == 1 and level["terrain"]["torches"].is_empty() and config.get("niches", []).is_empty(), "the dark below: no door but the hall's own, no torches, no niches, every room a cavern (%d doors, %d torches)" % [doors, level["terrain"]["torches"].size()])
	_check(kinds.get("skeleton", 0) == 6 and kinds.get("chest", 0) == 4 and kinds.get("draugr", 0) == 1 and kinds.get("robber", 0) == 0,
		"six of the oldest dead and four chests laid; the draugr kept on his throne (%s)" % [kinds])
	var in_hall := 0
	for spec: Dictionary in level["entities"]:
		if Sheet.LAIR_HALL.has_point(spec["tile"]) and str(spec.get("kind", "")) != "draugr":
			in_hall += 1
	_check(in_hall == 0 and not a.walkable(Vector2i(49, 53)) and not a.walkable(Vector2i(39, 48)) and a.walkable(Vector2i(49, 44)) and a.walkable(Vector2i(49, 43)) == a.walkable(Vector2i(49, 43)),
		"nothing is laid in his hall; the round table and the pillars are rock; the door cell in the north wall is floor")
	_check(level["links"].size() == 2 and level["links"][1]["sealed"] == "draugr" and level["links"][1]["tile"] == Sheet.LAIR_SHORTCUT_LINK and Sheet.LAIR_DAIS.has_point(level["links"][1]["tile"]),
		"the sealed shortcut's end lies on the dais behind the throne")
	_check(Regen.generate("lab_barrow_lair", 1)["layout"].get_data() == dark["layout"].get_data(), "the same seed gives the same dark")


## Whether every anchor's cells and edges are the template's in both
## [param a] and [param b] (but cells [param loose] says may move, and
## the edges touching them), and how many cells outside differ between them.
func _anchors_kept(template: LevelMap, a: LevelMap, b: LevelMap, anchors: Array, size: Vector2i, loose := Callable()) -> Dictionary:
	var same := true
	var differ := 0
	var moves := func(cell: Vector2i) -> bool: return loose.is_valid() and loose.call(cell)
	for y in size.y:
		for x in size.x:
			var cell := Vector2i(x, y)
			if Level.in_anchors(anchors, cell):
				if moves.call(cell):
					continue
				if a.cell(cell) != template.cell(cell) or b.cell(cell) != template.cell(cell):
					same = false
				for side in [Terrain.EAST, Terrain.SOUTH]:
					var key := Vector3i(x, y, side)
					if moves.call(Terrain.edge_cells(key)[1]):
						continue
					if a.edge(key) != template.edge(key) or b.edge(key) != template.edge(key):
						same = false
			elif a.cell(cell) != b.cell(cell):
				differ += 1
	return {"same": same, "differ": differ}


func _floor_of(map: LevelMap, size: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			if map.walkable(Vector2i(x, y)):
				out.append(Vector2i(x, y))
	return out


func _kinds(level: Dictionary) -> Dictionary:
	var kinds := {}
	for spec: Dictionary in level["entities"]:
		var kind := str(spec.get("kind", spec["name"].rstrip("0123456789").to_lower()))
		kinds[kind] = int(kinds.get(kind, 0)) + 1
	return kinds


## How many of [param floor_cells] have floor on two opposite sides: the
## ways' width (541 amended).
func _broad(map: LevelMap, floor_cells: Array[Vector2i]) -> int:
	var broad := 0
	for cell in floor_cells:
		if (map.walkable(cell + Vector2i(1, 0)) and map.walkable(cell - Vector2i(1, 0))) or (map.walkable(cell + Vector2i(0, 1)) and map.walkable(cell - Vector2i(0, 1))):
			broad += 1
	return broad


func _test_sheet() -> void:
	print("\n== the plan sheet ==")
	var out: String = preload("res://tests/test_ports.gd").scratch_path("labyrinth_sheet.png")
	if FileAccess.file_exists(out):
		DirAccess.remove_absolute(out)
	_check(Sheet.write_sheet("lab_dwarven", 1, out, 4) == 0, "written for the dwarven sample at scale 4")
	var image := Image.load_from_file(out) if FileAccess.file_exists(out) else null
	_check(image != null and image.get_size() == Vector2i((Sheet.SIZE.x * 2 - 1) * 4, (Sheet.SIZE.y * 2 - 1) * 4),
		"a PNG the layout's size times four (%s)" % [image.get_size() if image else null])
	var grey: Variant = image.get_pixel(4 * 2 * 4 + 1, 3 * 2 * 4 + 1) if image != null else null
	_check(grey != null and grey.is_equal_approx(Color("#9a9a9a")), "the gatehouse's floor at (4, 3) is stone grey on it (%s)" % [grey.to_html(false) if grey else null])
	_check(Sheet.write_sheet("lab_old", 1, "", 4) == 2 and Sheet.write_sheet("no_such_level", 1, out, 4) == 2, "no out, or a level there is not: refused")
	_check(Sheet.write_sheet("castle", 1, out, 4) == 0, "a level that does not regenerate is drawn as it stands (580)")
	DirAccess.remove_absolute(out)


## The walkable cells of [param map] no walk from [param start] reaches
## (through open and door edges).
func _cut_off(map: LevelMap, start: Vector2i) -> Array[Vector2i]:
	var seen: Dictionary[Vector2i, bool] = {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var here: Vector2i = queue.pop_front()
		for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := here + direction
			if seen.has(next) or not map.in_bounds(next) or not map.walkable(next) or map.edge(Terrain.edge_key(here, direction)) == "wall":
				continue
			seen[next] = true
			queue.append(next)
	var out: Array[Vector2i] = []
	for y in map.size.y:
		for x in map.size.x:
			var cell := Vector2i(x, y)
			if map.walkable(cell) and not seen.has(cell):
				out.append(cell)
	return out


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
