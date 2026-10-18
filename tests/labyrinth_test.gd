extends Node
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
	for style in ["dwarven", "old"]:
		var sample := Sheet.sample_halls(style)
		Level.register("lab_" + style, sample["layout"], null, sample["config"])
	_test_block()
	_test_style("dwarven")
	_test_style("old")
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
	_check(Sheet.write_sheet("lab_old", 1, "", 4) == 2 and Sheet.write_sheet("castle", 1, out, 4) == 2, "no out, or a level that does not regenerate: refused")
	DirAccess.remove_absolute(out)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
