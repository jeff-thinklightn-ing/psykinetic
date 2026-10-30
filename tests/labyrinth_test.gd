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
const Labyrinth := preload("res://sim/level_gen/labyrinth.gd")
## The sample towers (659): [prefix, floors, across].
const TOWERS: Array = [["lab_tower", 4, 22], ["lab_wide", 2, 30]]

var _failures := 0


func _ready() -> void:
	World.set_process(false)
	Net.port = preload("res://tests/test_ports.gd").of(17861)
	for style in ["dwarven", "old", "barrow", "barrow_deep", "castle_halls"]:
		var sample := Sheet.sample_halls(style)
		Level.register("lab_" + style, sample["layout"], sample.get("height"), sample["config"])  # The lair's dais heights (580 step 3).
	# The tower (659): four floors at the sample's size and two at 30 across.
	for set: Array in TOWERS:
		for floor in range(1, int(set[1]) + 1):
			var sample := Sheet.sample_tower(floor, int(set[1]), str(set[0]), int(set[2]))
			Level.register("%s_%d" % [set[0], floor], sample["layout"], null, sample["config"])
	_test_block()
	_test_style("dwarven")
	_test_style("old")
	_test_barrow()
	_test_castle_halls()
	_test_tower()
	_test_two_cell()
	_test_set_in_rock()
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
	_check(Regen.config_of("lab_barrow")["anchors"].size() == 4 and Regen.config_of("lab_barrow")["near"] == {"robber_brute": "camp"} and Regen.config_of("lab_barrow_deep")["anchors"].size() == 2 and Regen.config_of("lab_barrow_deep")["near"] == {"skeleton_guard": "lair"}, "the sample barrow's two depths regenerate: four anchors, then two (580, 666), Brand sent near the robbers' camp (714 (4)) and the grave guards near the Hall")


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
	print("\n== the barrow style in layers (decisions 541, 580): the town's tombs shallow, the Ossuary by depth with the Hall off it (666) ==")
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
	_check(hall_floor == 24 * 16 + 5 and in_walls == 5 and a.walkable(Vector2i(39, 8)),
		"the first hall: 24 x 16 of floor (the table a building on it, 580 step 3), a bay two rows tall each side and the hidden niche's alcove in the walls (%d floor, %d in the walls)" % [hall_floor, in_walls])
	var level := Level.parse(first["layout"], null, config)
	var doors := 0
	for key: Vector3i in level["terrain"]["edges"]:
		if level["terrain"]["edges"][key] == Terrain.Edge.DOOR:
			doors += 1
	var kinds := _kinds(level)
	_check(doors >= 4 and level["terrain"]["torches"].size() >= 8,
		"layer 1 is all shallow: the town's tombs have doors and the ways their torches (%d doors, %d torches)" % [doors, level["terrain"]["torches"].size()])
	_check(kinds.get("robber", 0) == 8 and kinds.get("robber_brute", 0) == 1 and kinds.get("chest", 0) == 3 and kinds.get("altar", 0) == 1 and kinds.get("skeleton_guard", 0) == 2
		and kinds.get("runner's pack", 0) == 1 and kinds.get("skeleton", 0) == 0,
		"the band laid, eight robbers and Brand (714 (4)), and three chests; the altar, its two guards and the Runner's pack kept; no dead walk (%s)" % [kinds])
	_check(_dead_at_walls(a, anchors).is_empty() and _dead_at_walls(b, anchors).is_empty(),
		"layer 1's robbers stand on open floor in both generations, floor all round and no wall edge (631 amended; %s)" % [_dead_at_walls(a, anchors) + _dead_at_walls(b, anchors)])
	# The coordinator (714 (4)): spread over the rooms, so a lone player
	# never meets the nine at once; Brand by the camp.
	var altar := Sheet.BARROW_ALTAR
	var camp := Vector2i(11, 46)
	var near_altar := 0
	var brand_to_camp := 0.0
	var all_to_camp := 0.0
	var spots: Array[Vector2i] = []
	for spec: Dictionary in level["entities"]:
		if str(spec.get("kind", "")) == "robber":
			spots.append(spec["tile"])
			if absi(spec["tile"].x - altar.x) + absi(spec["tile"].y - altar.y) <= 10:
				near_altar += 1
		elif str(spec.get("kind", "")) == "robber_brute":
			brand_to_camp = absi(spec["tile"].x - camp.x) + absi(spec["tile"].y - camp.y)
	for cell in floor_cells:
		all_to_camp += absi(cell.x - camp.x) + absi(cell.y - camp.y)
	var packed := 0
	for each in spots:
		packed = maxi(packed, spots.filter(func(other: Vector2i) -> bool: return absi(other.x - each.x) + absi(other.y - each.y) <= 6).size())
	_check(spots.size() == 8 and near_altar <= 4 and packed <= 4 and brand_to_camp < all_to_camp / floor_cells.size(),
		"the eight spread, at most four by the altar or within six cells of one another, and Brand nearer the camp than the floor's mean (%d by the altar, %d packed, Brand %.1f against %.1f)"
		% [near_altar, packed, brand_to_camp, all_to_camp / floor_cells.size()])
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
	# Moss and webs (647): the hall's own webs kept, the rest rolled, dry
	# on the first layer; a web on no slab, no shelf and never the hidden
	# niche; the parse keeps every one; none on a way's path.
	var decor := _decor_report(config, level, a, anchors)
	_check(decor["kept_hand"] == 3 and decor["parsed"] and decor["webs_open"] and decor["off_markers"] and decor["strip_share"] >= 0.01 and decor["strip_share"] <= 0.12,
		"the first hall's two webs and its strip of moss are kept; the tombs get a little moss (%.2f of their wall feet) and webs in corners and open niches only, never the hidden one; the parse keeps every one (%s)" % [decor["strip_share"], decor["counts"]])
	_check(Regen.generate("lab_barrow", 1)["config"]["decor"] == config["decor"] and second["config"]["decor"] != config["decor"],
		"the same seed rolls the same decor, another generation another")
	var regen_warnings: Array[String] = []
	var regen_config := Level.regenerate_from(Level.template("lab_barrow")["config"], regen_warnings)
	regen_config["niches"] = Level.template("lab_barrow")["config"].get("niches", [])
	var raw: LevelMap = Labyrinth.generate(template, regen_config, Regen.seed_for("lab_barrow", 1))
	var paths: Dictionary = raw.extras.get("paths", {})
	var rolled: Array = Regen.decor_of(raw, anchors, regen_config, {"niches": [], "spawn_points": {}, "decor": []}, Regen.seed_for("lab_barrow", 1), false)
	var on_path := rolled.filter(func(d: Array) -> bool: return paths.has(Vector2i(int(d[0]), int(d[1]))))
	_check(paths.size() > 50 and rolled.size() > 0 and on_path.is_empty(), "the generator records the ways' cells on the map and the roll keeps off them (%d path cells, %d rolled, %d on a path)" % [paths.size(), rolled.size(), on_path.size()])
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
	_check(kept["same"], "inside the two anchors both generations are the template: the stair foot, and the Hall of Fallen Souls with its pillars, table, throne and the hidden way out (666)")
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
	level = Level.parse(deep["layout"], deep["height"], config)
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
	var dead_by_band := [0, 0, 0]
	for spec: Dictionary in level["entities"]:
		var kind := str(spec.get("kind", spec["name"].rstrip("0123456789").to_lower()))
		if kind == "chest" and spec["tile"] != Sheet.LAIR_CHEST:
			chest_depth += depth.call(spec["tile"])
		elif kind == "skeleton":
			# The generator's measure: the distance over the farthest the map reaches from the entrance.
			var far := 1
			for corner: Vector2i in [Vector2i.ZERO, Vector2i(level["size"].x - 1, 0), Vector2i(0, level["size"].y - 1), level["size"] - Vector2i.ONE]:
				far = maxi(far, depth.call(corner))
			var d := float(depth.call(spec["tile"])) / float(far)
			dead_by_band[0 if d < Regen.BANDS[0] else (1 if d < Regen.BANDS[1] else 2)] += 1
	_check(kinds.get("skeleton", 0) == 12 and kinds.get("skeleton_guard", 0) == 2 and kinds.get("chest", 0) == 6 and kinds.get("draugr", 0) == 1
		and kinds.get("robber", 0) == 0 and not kinds.has("altar"),
		"twelve skeletons and two grave guards (drafts, 666), five chests laid and the Hall's own, the draugr kept on his throne; no robbers, no altar (%s)" % [kinds])
	var guard_off := 0
	for spec: Dictionary in level["entities"]:
		if str(spec.get("kind", "")) == "skeleton_guard":
			var at: Vector2i = spec["tile"]
			guard_off = maxi(guard_off, maxi(absi(at.x - Sheet.LAIR_DOOR.x), absi(at.y - Sheet.LAIR_DOOR.y)))
	_check(guard_off > 0 and guard_off <= 16, "the grave guards stand near the Hall's door (666: the farthest %d cells off)" % guard_off)
	_check(_dead_at_walls(a, anchors).is_empty() and _dead_at_walls(b, anchors).is_empty(),
		"the Ossuary's dead stand on open floor in both generations: never a niche, a grave or a wall's foot (631 amended; %s)" % [_dead_at_walls(a, anchors) + _dead_at_walls(b, anchors)])
	if kinds.get("skeleton", 0) == 12 and kinds.get("chest", 0) == 6:
		# The dead a third to each band (decision 631): the shallow band's share
		# shows up a few rooms in, not only at the far end.
		_check(chest_depth / 5.0 > mean_floor and dead_by_band[0] >= 3 and dead_by_band[1] >= 3 and dead_by_band[2] >= 3,
			"the grave goods lie deeper than the floor's mean depth (%.1f over %.1f); the dead are spread a third to each band (%s)" % [chest_depth / 5.0, mean_floor, dead_by_band])
	_check(level["warnings"].is_empty() and level["links"].size() == 2 and level["links"][0]["to_map"] == "barrow" and level["links"][1]["to_map"] == "wilds"
		and level["links"][1]["sealed"] == "draugr" and level["links"][1]["tile"] == Sheet.DEEP_SHORTCUT_LINK and Sheet.LAIR_DAIS.has_point(level["links"][1]["tile"])
		and level["spawn_points"].size() == 2 and level["spawn_points"].get("from_temple") == Sheet.DEEP_FROM_TEMPLE,
		"no warnings; the stair up, the sealed shortcut's end on the dais behind the throne, the spawn points (%s)" % [level["warnings"]])
	_check(Regen.generate("lab_barrow_deep", 1)["layout"].get_data() == deep["layout"].get_data(), "the same seed gives the same Ossuary")
	# The graves (542 amended; 725: the niches' cells, the two-cell rule
	# leaving no lone ones): every dead end outside the anchors and every
	# wall niche's floor cell, bar the chests, with its band.
	var graves: Array = config.get("graves", [])
	var niche_cells := {}
	for niche: Array in config.get("niches", []):
		niche_cells[Vector2i(int(niche[0]), int(niche[1]))] = true
	var dead_ends := 0
	var chests_in := 0
	var bands_ok := true
	for cell in floor_cells:
		var open := 0
		for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if a.walkable(cell + direction) and a.edge(Terrain.edge_key(cell, direction)) != "wall":
				open += 1
		if (open == 1 or niche_cells.has(cell)) and a.cell(cell) != "chest" and not Level.in_anchors(anchors, cell):
			dead_ends += 1
	for grave: Array in graves:
		var cell := Vector2i(int(grave[0]), int(grave[1]))
		if a.cell(cell) == "chest" or Level.in_anchors(anchors, cell):
			chests_in += 1
		var band_wanted := 0 if depth.call(cell) < 43 else (1 if depth.call(cell) < 84 else 2)
		if int(grave[2]) != band_wanted:
			bands_ok = false
	_check(graves.size() >= 6 and graves.size() == dead_ends and chests_in == 0 and bands_ok,
		"the generated config lists every dead end and niche cell outside the anchors as a grave with its band, none on a chest (%d graves, %d places)" % [graves.size(), dead_ends])
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
	decor = _decor_report(config, level, a, anchors)
	_check(decor["kept_hand"] == Sheet.LAIR_DECOR.size() and decor["parsed"] and decor["webs_open"] and decor["off_markers"] and decor["strip_share"] >= 0.08 and decor["strip_share"] <= 0.25
		and int(decor["counts"].get("moss_patch", 0)) > 0 and int(decor["counts"].get("web_corner", 0)) > 0,
		"the Ossuary's moss is rolled over its galleries (%.2f of the wall feet), patches on the floor, webs in corners and across open hollows only; the Hall keeps its own moss and webs; the parse keeps every one (%s)" % [decor["strip_share"], decor["counts"]])
	_check(_broad(a, floor_cells) * 10 >= floor_cells.size() * 8, "the ways are five wide: most floor cells have floor on two opposite sides (%d of %d)" % [_broad(a, floor_cells), floor_cells.size()])
	# The Hall of Fallen Souls, the Ossuary's far anchor (666).
	var in_hall := 0
	var hall_chest := {}
	for spec: Dictionary in level["entities"]:
		if spec["tile"] == Sheet.LAIR_CHEST:
			hall_chest = spec
		elif Sheet.LAIR_HALL.has_point(spec["tile"]) and str(spec.get("kind", "")) != "draugr":
			in_hall += 1
	var pillars: Array = config.get("buildings", []).filter(func(b: Dictionary) -> bool: return b.get("slot", "") == "building.crypt_pillar")
	var hall_doors := 0
	for key: Vector3i in level["terrain"]["edges"]:
		var sides := Terrain.edge_cells(key)
		if level["terrain"]["edges"][key] == Terrain.Edge.DOOR and Sheet.LAIR_HALL.has_point(sides[0]) != Sheet.LAIR_HALL.has_point(sides[1]):
			hall_doors += 1
	_check(in_hall == 0 and hall_doors == 1 and a.walkable(Sheet.LAIR_DOOR) and a.walkable(Sheet.LAIR_DOOR - Vector2i(0, 1)) and pillars.size() == 5
		and level["terrain"]["solid"].size() == 20 + 9 + 8 and level["terrain"]["stairs"].size() == 12 and level["buildings"].size() == 19
		and not pillars.any(func(b: Dictionary) -> bool: return b.get("at") == [49, 70]) and level["terrain"]["floor"].has(Vector2i(49, 70))
		and config.get("rooms", {}).has("lair") and str(hall_chest.get("script", "")) == Level.CHEST and Sheet.LAIR_DAIS.has_point(Sheet.LAIR_CHEST),
		"nothing is laid in the Hall but its own chest on the dais beside the throne; one door into it, the way reaching it from the north; the pillars (none before his seat, 580 amended (2)), the round table and the broken tables solid, the chairs and throne walked onto, the dais's twelve stairs, the Hall's name kept for its card (%d pillars, %d solid, %d doors)" % [pillars.size(), level["terrain"]["solid"].size(), hall_doors])
	_check(not config.has("damp") and not config.has("ambient") and not config.has("dead") and config.get("stills", []) == ["barrow"],
		"the dark below's keys left with it: no damp, no ambient, no word on the dead; his rest stills the barrow above (%s)" % [config.get("stills")])


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


## The Dwarven Halls (613, dungeon's side): the template's generations in
## the dwarven style under the width rule (ways five wide, pillar blocks),
## the three anchors and the smith's place kept through them.
func _test_castle_halls() -> void:
	print("\n== the Dwarven Halls (613): dwarven, five wide, the forge kept ==")
	var first := Regen.generate("lab_castle_halls", 1)
	var second := Regen.generate("lab_castle_halls", 2)
	_check(not first.is_empty() and not second.is_empty(), "generations 1 and 2 are made (%d and %d tries)" % [first.get("tries", 0), second.get("tries", 0)])
	if first.is_empty() or second.is_empty():
		return
	var config: Dictionary = first["config"]
	var anchors: Array = first["anchors"]
	var template := LevelMap.from_image(Level.template("lab_castle_halls")["layout"], config)
	var a := LevelMap.from_image(first["layout"], config)
	var b := LevelMap.from_image(second["layout"], config)
	var kept := _anchors_kept(template, a, b, anchors, Sheet.HALLS_SIZE, func(_cell: Vector2i) -> bool: return false)
	var floor_cells := _floor_of(a, Sheet.HALLS_SIZE)
	_check(kept["same"], "inside the three anchors both generations are the template: the stair foot, the ambush, the forge room")
	_check(kept["differ"] > 50 and floor_cells.size() > 1200, "the halls between differ (%d cells) and fill the rock (%d floor cells)" % [kept["differ"], floor_cells.size()])
	_check(Regen.connected(a, anchors) and Regen.connected(b, anchors), "every anchor reaches every other in both")
	_check(Tools.narrow_runs(a).is_empty() and Tools.narrow_runs(b).is_empty(), "no passage is one cell wide in either, the great halls' pillar blocks included (%s; %s)" % [Tools.sorted_cells(Tools.narrow_runs(a)).slice(0, 8), Tools.sorted_cells(Tools.narrow_runs(b)).slice(0, 8)])
	_check(_broad(a, floor_cells) * 10 >= floor_cells.size() * 8, "the ways are five wide: most floor cells have floor on two opposite sides (%d of %d)" % [_broad(a, floor_cells), floor_cells.size()])
	var level := Level.parse(first["layout"], null, config)
	var solid: Array = level["buildings"].filter(func(building: Dictionary) -> bool: return building["slot"] in ["building.dwarven_forge", "building.weapon_rack"])
	_check(solid.size() == 2 and not level["terrain"]["floor"].has(Sheet.HALLS_FORGE.position) and not level["terrain"]["floor"].has(Sheet.HALLS_FORGE.end - Vector2i.ONE)
		and not level["terrain"]["floor"].has(Sheet.HALLS_RACK) and level["terrain"]["floor"].has(Sheet.HALLS_STAND) and level["warnings"].is_empty(),
		"the forge and the rack are kept and stand solid (613 amended), the stand cell between the anvils floor, nothing said (%s)" % [level["warnings"]])
	var guards := func(made: Dictionary) -> Array:
		return made["config"].get("decor", []).filter(func(entry: Variant) -> bool: return entry is Array and entry.size() == 6 and str(entry[4]) == "fallen_guard")
	var guard_cells := {}
	for entry: Array in Sheet.HALLS_GUARDS:
		guard_cells[Vector2i(int(entry[0]), int(entry[1]))] = true
	var over_guards := func(made: Dictionary) -> int:
		return made["config"].get("decor", []).filter(func(entry: Variant) -> bool: return entry is Array and entry.size() == 6 and str(entry[4]) != "fallen_guard" and guard_cells.has(Vector2i(int(entry[0]), int(entry[1])))).size()
	_check(guards.call(first) == Sheet.HALLS_GUARDS and guards.call(second) == Sheet.HALLS_GUARDS and over_guards.call(first) == 0 and over_guards.call(second) == 0
		and level["terrain"]["decor"].filter(func(d: Dictionary) -> bool: return d["kind"] == "fallen_guard").size() == 3,
		"the three fallen guards lie in the ambush in both generations, with their facings, and the moss roll keeps off their cells (%s)" % [guards.call(first)])
	var doors := 0
	for key: Vector3i in level["terrain"]["edges"]:
		if level["terrain"]["edges"][key] == Terrain.Edge.DOOR:
			doors += 1
	var kinds := _kinds(level)
	_check(doors >= 4 and level["terrain"]["torches"].size() >= 8, "doors where the ways meet the rooms and torches along them (%d doors, %d torches)" % [doors, level["terrain"]["torches"].size()])
	_check(kinds.get("imp", 0) == 5 and kinds.get("brute", 0) == 1 and kinds.get("chest", 0) == 5 and kinds.get("cart", 0) == 1 and kinds.get("crate", 0) == 2,
		"five imps and a brute laid, three chests beside the forge room's two, the ambush's cart and crates kept (%s)" % [kinds])
	_check(level["places"].has("dwarven_forge") and level["places"]["dwarven_forge"]["cell"] == Sheet.HALLS_STAND and level["places"]["dwarven_forge"]["radius"] == 3,
		"the smith's place, dwarven_forge, is kept at the stand cell (%s)" % [level["places"].get("dwarven_forge")])
	var pillars: Array = level["buildings"].filter(func(building: Dictionary) -> bool: return building["slot"] == "building.crypt_pillar")
	_check(pillars.size() == 4 and pillars.all(func(building: Dictionary) -> bool: return int(building.get("variant", 1)) == 2),
		"four dwarven pillars (crypt_pillar, variant 2) stand in the forge room (%d)" % pillars.size())


## The tower style (659): each floor of the two sample towers laid twice:
## the anchors kept and inside the octagon, every anchor reached, no
## one-wide way, nothing carved outside the footprint, the stairs at the
## same cells on every floor with two clear cells round each stair and
## spawn, the sealed way down on the foot alone, the top chamber bare but
## for its two lamps and four pillars, a chest a floor; in the dark set
## (659 amended): cold lamps for torches, runes rolled along the ways, the
## hatch over the sealed link.
func _test_tower() -> void:
	print("\n== the tower style (659): floors in an octagon, the shaft lining the stairs ==")
	for set: Array in TOWERS:
		var prefix := str(set[0])
		var floors := int(set[1])
		var across := int(set[2])
		var size := Vector2i(across, across)
		var inside := Labyrinth.footprint(size, "octagon")
		var c := across / 2
		var stairs := {}
		for floor in range(1, floors + 1):
			var name := "%s_%d" % [prefix, floor]
			var first := Regen.generate(name, 1)
			var second := Regen.generate(name, 2)
			_check(not first.is_empty() and not second.is_empty(), "%s: generations 1 and 2 are made (%d and %d tries)" % [name, first.get("tries", 0), second.get("tries", 0)])
			if first.is_empty() or second.is_empty():
				continue
			var config: Dictionary = first["config"]
			var anchors: Array = first["anchors"]
			var template := LevelMap.from_image(Level.template(name)["layout"], config)
			var a := LevelMap.from_image(first["layout"], config)
			var b := LevelMap.from_image(second["layout"], config)
			var kept := _anchors_kept(template, a, b, anchors, size, func(_cell: Vector2i) -> bool: return false)
			_check(kept["same"] and kept["differ"] > 20, "%s: the anchors are the template's in both, the floor between differs (%d cells)" % [name, kept["differ"]])
			_check(Regen.connected(a, anchors) and Regen.connected(b, anchors), "%s: every anchor reaches every other in both" % name)
			var cut_off := _cut_off(a, Vector2i(c, c)) + _cut_off(b, Vector2i(c, c))
			_check(cut_off.is_empty(), "%s: every floor cell is walked to from the shaft in both, no room cut off (%s)" % [name, cut_off.slice(0, 8)])
			_check(Tools.narrow_runs(a).is_empty() and Tools.narrow_runs(b).is_empty(), "%s: no way is one cell wide in either (%s)" % [name, Tools.sorted_cells(Tools.narrow_runs(a)).slice(0, 6)])
			var floor_a := _floor_of(a, size)
			var outside := floor_a.filter(func(cell: Vector2i) -> bool: return not inside.has(cell)).size() \
				+ _floor_of(b, size).filter(func(cell: Vector2i) -> bool: return not inside.has(cell)).size()
			var anchors_in := anchors.all(func(anchor: Dictionary) -> bool:
				return Level.rect_cells(anchor["rect"]).all(func(cell: Vector2i) -> bool: return inside.has(cell)))
			_check(outside == 0 and anchors_in and floor_a.size() * 3 >= inside.size(),
				"%s: nothing is carved outside the octagon, the anchors lie inside it, the floor fills a good share of it (%d outside, %d of %d)" % [name, outside, floor_a.size(), inside.size()])
			var level := Level.parse(first["layout"], null, config)
			_check(level["warnings"].is_empty(), "%s: generation 1 parses with no warning (%s)" % [name, level["warnings"]])
			var doors := 0
			for key: Vector3i in level["terrain"]["edges"]:
				if level["terrain"]["edges"][key] == Terrain.Edge.DOOR:
					doors += 1
			var lamps: Array = level["terrain"]["lamps"]
			_check(doors >= 3 and lamps.size() >= 3 and level["terrain"]["torches"].is_empty() and _kinds(level).get("chest", 0) == 1,
				"%s: doors where the ways meet the rooms, cold lamps along them and no torch, one chest (%d doors, %d lamps, %s)" % [name, doors, lamps.size(), _kinds(level)])
			var runes: Array = config.get("decor", []).filter(func(entry: Array) -> bool:
				return entry[4] == "rune_strip" and not Level.in_anchors(anchors, Vector2i(int(entry[0]), int(entry[1]))))
			var placed: int = level["terrain"]["decor"].filter(func(piece: Dictionary) -> bool: return piece["kind"] == "rune_strip").size()
			_check(config["walls"] == "dark" and config["floors"] == "dark" and runes.size() >= 2 and placed >= runes.size(),
				"%s: the dark set, runes rolled along the ways' walls and every one placed (%d rolled, %d placed)" % [name, runes.size(), placed])
			var hatch: Array = level["buildings"].filter(func(b: Dictionary) -> bool: return b["slot"] == "building.hatch_sealed")
			_check((hatch.size() == 1 and (hatch[0]["rect"] as Rect2i).position == Vector2i(c, 2) and a.walkable(Vector2i(c, 2))) if floor == 1 else hatch.is_empty(),
				"%s: the sealed hatch lies over the mine's link, walked onto, on the foot alone (%s)" % [name, hatch])
			# The stairs and the spawns beside them: the same cells on every
			# floor, two clear cells round each, whatever the floor rolled.
			var up_down := {}
			for cue: Dictionary in level["terrain"]["link_cues"]:
				if cue["cue"] in ["up", "down"]:
					up_down[cue["cue"]] = cue["tile"]
			_check((floor < floors) == up_down.has("up") and (floor > 1) == up_down.has("down")
				and up_down.get("up", Vector2i(c + 1, c)) == Vector2i(c + 1, c) and up_down.get("down", Vector2i(c - 1, c)) == Vector2i(c - 1, c),
				"%s: the stair up east of the middle and the stair down west, none up from the top or down from the foot (%s)" % [name, up_down])
			for cue: String in up_down:
				stairs[cue] = stairs.get(cue, up_down[cue])
				_check(stairs[cue] == up_down[cue], "%s: the stair %s is where it is on every floor (%s)" % [name, cue, up_down[cue]])
			var round_cells: Array[Vector2i] = []
			round_cells.append_array(up_down.values())
			for spawn: String in ["from_above", "from_below"]:
				if level["spawn_points"].has(spawn):
					round_cells.append(level["spawn_points"][spawn])
			var crowded := []
			for at in round_cells:
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						var near := at + Vector2i(dx, dy)
						if not a.walkable(near) or not b.walkable(near):
							crowded.append(near)
			_check(round_cells.size() >= 2 and crowded.is_empty(), "%s: two clear cells round every stair and the spawns beside them in both generations (%s)" % [name, crowded.slice(0, 6)])
			var sealed: Array = level["terrain"]["link_cues"].filter(func(cue: Dictionary) -> bool: return cue["cue"] == "sealed")
			_check((sealed.size() == 1 and sealed[0]["tile"] == Vector2i(c, 2) and level["links"].any(func(link: Dictionary) -> bool: return link["tile"] == Vector2i(c, 2) and link["sealed"] == "tower_mine")) if floor == 1 else sealed.is_empty(),
				"%s: the mine's way down is a sealed link under the north wall on the foot alone (%s)" % [name, sealed])
			if floor == floors:
				var chamber: Rect2i = anchors.filter(func(anchor: Dictionary) -> bool: return anchor["name"] == "chamber")[0]["rect"]
				var lit: int = lamps.filter(func(cell: Vector2i) -> bool: return chamber.has_point(cell)).size()
				var things: int = level["entities"].filter(func(spec: Dictionary) -> bool: return chamber.has_point(spec["tile"])).size()
				var pillars: int = level["buildings"].filter(func(b: Dictionary) -> bool: return b["slot"] == "building.dark_pillar").size()
				var solid: int = level["terrain"]["solid"].filter(func(cell: Vector2i) -> bool: return chamber.has_point(cell)).size()
				var wall_runes: int = level["terrain"]["decor"].filter(func(piece: Dictionary) -> bool: return piece["kind"] == "rune_strip" and chamber.has_point(piece["cell"])).size()
				_check(lit == 2 and things == 0 and pillars == 4 and solid == 4 and wall_runes == chamber.size.x and a.walkable(Vector2i(c, c - 3))
					and a.edge(Terrain.edge_key(Vector2i(c, c - 3), Vector2i(0, 1))) != "wall" and Regen.connected(a, anchors),
					"%s: the top chamber holds its two lamps, four solid pillars, runes the length of its north wall and nothing else, open onto the shaft (%d lit, %d things, %d pillars, %d solid, %d runes)" % [name, lit, things, pillars, solid, wall_runes])


## How many of [param floor_cells] have floor on two opposite sides: the
## ways' width (541 amended).
func _broad(map: LevelMap, floor_cells: Array[Vector2i]) -> int:
	var broad := 0
	for cell in floor_cells:
		if (map.walkable(cell + Vector2i(1, 0)) and map.walkable(cell - Vector2i(1, 0))) or (map.walkable(cell + Vector2i(0, 1)) and map.walkable(cell - Vector2i(0, 1))):
			broad += 1
	return broad


## The two-cell rule over many seeds (725; Jeff: "the torches are always
## put in front of door ways. there are still too many 1 tile niches and 1
## tile tight turns, often around doors. doors are still kind of small and
## narrow"): every generated floor cell outside the anchors in a clear 2 x 2,
## every door edge one of a pair, no torch on a door's cell or in its line.
const TWO_CELL_SEEDS := 20
func _test_two_cell() -> void:
	print("
== the two-cell rule, %d generations of each style (725) ==" % TWO_CELL_SEEDS)
	for name: String in ["lab_dwarven", "lab_old", "lab_barrow", "lab_barrow_deep", "lab_castle_halls", "lab_tower_1", "lab_wide_2"]:
		var pinched: Array[String] = []
		var lone: Array[String] = []
		var lit: Array[String] = []
		var doors := 0
		var walled := 0
		for generation in range(1, TWO_CELL_SEEDS + 1):
			var made := Regen.generate(name, generation)
			if made.is_empty():
				pinched.append("g%d: not made" % generation)
				continue
			var map := LevelMap.from_image(made["layout"], made["config"])
			if str(Regen.config_of(name).get("style", "")) == "tower":
				var inside := Labyrinth.footprint(map.size, str(Regen.config_of(name).get("footprint", "square")))
				if not inside.is_empty():
					map.extras["footprint"] = inside
			for at in Tools.pinches(map, made["anchors"]):
				if Tools.against_outline(map, at):
					walled += 1  # The tower's own wall pinches it (659: nothing carved outside).
					continue
				pinched.append("g%d %s" % [generation, at])
			for key: Vector3i in map.edges:
				if map.edges[key] != "door" or Level.in_anchors(made["anchors"], Terrain.edge_cells(key)[0]) or Level.in_anchors(made["anchors"], Terrain.edge_cells(key)[1]):
					continue
				doors += 1
				var step := Vector3i(0, 1, 0) if key.z == Terrain.EAST else Vector3i(1, 0, 0)
				if map.edge(key + step) != "door" and map.edge(key - step) != "door":
					lone.append("g%d %s" % [generation, key])
			var line := Labyrinth.door_line(map)
			for at: Vector2i in map.cells:
				if map.cells[at] in ["torch", "lamp_cold"] and line.has(at):
					lit.append("g%d %s" % [generation, at])
		_check(pinched.is_empty(), "%s: every floor cell outside the anchors in a clear 2 x 2 (%d pinched: %s; %d against the tower's outline)" % [name, pinched.size(), pinched.slice(0, 6), walled])
		_check(lone.is_empty(), "%s: every door two edges wide (%d doors, %d lone: %s)" % [name, doors, lone.size(), lone.slice(0, 6)])
		_check(lit.is_empty(), "%s: no torch on a door's cell or in its line (%s)" % [name, lit.slice(0, 6)])


## Jeff: "barrows still had some odd shaped rooms like a single file
## hallway around a room with a door": the barrow's niche, walled but for
## its mouth (east) in its template ("a niche in the wall"), stays set in
## the rock: no floor in the ring round it but at its mouth, which the way
## reaches, any generation.
func _test_set_in_rock() -> void:
	print("
== a walled anchor stays set in the rock ==")
	var rect := Rect2i()
	for anchor: Dictionary in Regen.config_of("lab_barrow")["anchors"]:
		if str(anchor.get("name", "")) == "niche":
			var given: Variant = anchor["rect"]
			rect = given if given is Rect2i else Rect2i(int(given[0]), int(given[1]), int(given[2]), int(given[3]))
	_check(rect.has_area(), "the sample barrow has its niche anchor (%s)" % rect)
	var ringed: Array[String] = []
	var inside := 0
	for generation in range(1, TWO_CELL_SEEDS + 1):
		var made := Regen.generate("lab_barrow", generation)
		if made.is_empty():
			ringed.append("g%d: not made" % generation)
			continue
		var map := LevelMap.from_image(made["layout"], made["config"])
		var mouth := 0
		for cell in Level.rect_cells(rect.grow(1)):
			if rect.has_point(cell):
				inside += 1 if map.walkable(cell) else 0
			elif cell.x == rect.end.x and cell.y >= rect.position.y and cell.y < rect.end.y:
				mouth += 1 if map.walkable(cell) else 0
			elif map.walkable(cell):
				ringed.append("g%d %s" % [generation, cell])
		if mouth != rect.size.y:
			ringed.append("g%d: its mouth shut (%d open)" % [generation, mouth])
	_check(ringed.is_empty() and inside == 4 * TWO_CELL_SEEDS,
		"%d generations: the niche's four cells kept, its mouth on the way, no floor round it else (%d: %s)" % [TWO_CELL_SEEDS, ringed.size(), ringed.slice(0, 8)])


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
	# The tower's floors in a row (659): the foot at the left.
	_check(Sheet.write_tower_sheet("lab_tower", 4, 1, out, 4) == 0, "the sample tower's four floors are drawn in a row")
	image = Image.load_from_file(out) if FileAccess.file_exists(out) else null
	var one := (Sheet.TOWER_ACROSS * 2 - 1) * 4
	_check(image != null and image.get_size() == Vector2i(one * 4 + 8 * 3, one), "a PNG four floors wide with a strip between (%s)" % [image.get_size() if image else null])
	DirAccess.remove_absolute(out)


## The generated monster markers of [param map] (outside [param anchors])
## not on open floor (631 amended, dungeon's side): a cell with floor on all
## eight sides and no wall or door edge of its own.
func _dead_at_walls(map: LevelMap, anchors: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in map.size.y:
		for x in map.size.x:
			var cell := Vector2i(x, y)
			if not map.cell(cell).begins_with("monster_") or Level.in_anchors(anchors, cell):
				continue
			var open := true
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if not map.walkable(cell + Vector2i(dx, dy)):
						open = false
			for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if map.edge(Terrain.edge_key(cell, direction)) != "clear":
					open = false
			if not open:
				out.append(cell)
	return out


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


## The decor (647) of a generated [param config] against its parse
## [param level] and map [param a]: {counts: by kind, kept_hand: entries
## inside the anchors (the template's own), parsed: the parse keeps every
## listed one, webs_open: every web_niche hangs on a listed niche of kind
## "a" or "c" with variant 1, off_markers: none on a cell that is not plain
## floor (a link, a chest, a spawn point's cell), strip_share: moss strips
## outside the anchors over the floor cells outside them with rock beside}.
func _decor_report(config: Dictionary, level: Dictionary, a: LevelMap, anchors: Array) -> Dictionary:
	var counts := {}
	var kept_hand := 0
	var webs_open := true
	var off_markers := true
	var strips := 0
	var open_niches := {}
	for niche: Array in config.get("niches", []):
		if str(niche[4]) in ["a", "c"] and int(niche[5]) == 1:
			open_niches[Terrain.edge_key(Vector2i(int(niche[0]), int(niche[1])), Vector2i(int(niche[2]), int(niche[3])))] = true
	var spawns := {}
	for at: Variant in config.get("spawn_points", {}).values():
		spawns[Vector2i(int(at[0]), int(at[1]))] = true
	var listed: Array = config.get("decor", [])
	for entry: Array in listed:
		var cell := Vector2i(int(entry[0]), int(entry[1]))
		var step := Vector2i(int(entry[2]), int(entry[3]))
		var kind := str(entry[4])
		counts[kind] = int(counts.get(kind, 0)) + 1
		if Level.in_anchors(anchors, cell) and kind != "web_niche":
			kept_hand += 1
		elif kind == "moss_strip":
			strips += 1
		if kind == "web_niche" and not open_niches.has(Terrain.edge_key(cell, step)):
			webs_open = false
		if a.cell(cell) not in Level.GROUNDS or spawns.has(cell):
			off_markers = false
	var wall_feet := 0
	for cell: Vector2i in a.cells:
		if not a.walkable(cell) or Level.in_anchors(anchors, cell):
			continue
		for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not a.walkable(cell + direction):
				wall_feet += 1
				break
	return {"counts": counts, "kept_hand": kept_hand, "parsed": level["terrain"]["decor"].size() == listed.size(), "webs_open": webs_open,
		"off_markers": off_markers, "strip_share": float(strips) / float(maxi(wall_feet, 1))}


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
