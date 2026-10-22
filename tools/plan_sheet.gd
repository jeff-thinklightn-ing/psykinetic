extends Node
## A plan sheet of a regenerating level's generation (decision 470), for
## Jeff: the generated layout drawn large in the legend's colours (rock
## black, floor grey, walls dark brown, doors orange, torches yellow,
## chests brown, crates tan, monsters reds, links magenta, starts cyan),
## each anchor outlined in blue. Headless:
##   godot --headless --path <repo> --scene res://tools/plan_sheet.tscn -- --level=<name> --generation=<n> --out=<png> [--scale=8]
##   godot --headless --path <repo> --scene res://tools/plan_sheet.tscn -- --sample=dwarven|old|barrow --generation=<n> --out=<png>
## --level names a level under levels/ (or the overlay) marked "regenerate";
## --sample draws the built-in sample halls (sample_halls) in that style,
## a 48 x 40 floor with a gatehouse, two halls and a deepest chamber for
## anchors, or the sample barrow (sample_barrow, decision 541). Writes
## nothing but --out; the level is read, never written.

const SIZE := Vector2i(48, 40)
const ANCHORS := [{"rect": [2, 2, 6, 5], "name": "gatehouse"}, {"rect": [4, 18, 7, 5], "name": "west hall"},
	{"rect": [37, 14, 7, 5], "name": "east hall"}, {"rect": [40, 33, 6, 5], "name": "deepest chamber"}]
const OUTLINE := Color(0.25, 0.6, 1.0)
## The sample barrow (decision 541; 541 amended: 72 x 60, the rooms and
## anchors bigger, Jeff: "way too cramped"): its size and anchors, each
## with the sides it is walled on (the rest open to the tombs). The real
## barrow's template is written from this (levels/barrow, 542).
const BARROW_SIZE := Vector2i(72, 60)
const BARROW_ANCHORS := [
	{"rect": [33, 1, 6, 4], "name": "entrance", "walled": ["north", "east", "west"]},
	{"rect": [24, 27, 12, 10], "name": "altar", "walled": ["east", "south"]},
	{"rect": [36, 31, 7, 3], "name": "passage", "walled": ["north", "south"]},
	{"rect": [43, 27, 12, 11], "name": "lair", "walled": ["north", "east"]},
	{"rect": [55, 30, 3, 4], "name": "shortcut", "walled": ["north", "east", "south"]},
	{"rect": [20, 30, 2, 2], "name": "niche", "walled": ["north", "west", "south"]}]
## The barrow's named cells: the link up and the start in the vestibule,
## the altar with a guard each side, the passage's door on the altar
## room's east wall, the draugr and the Runner's pack in the lair, the
## sealed link in the nook, Pip's niche.
const BARROW_LINK := Vector2i(36, 1)
const BARROW_START := Vector2i(35, 2)
const BARROW_FROM_WILDS := Vector2i(36, 2)
const BARROW_ALTAR := Vector2i(29, 31)
const BARROW_GUARDS := [Vector2i(27, 31), Vector2i(31, 31)]
const BARROW_DOOR_ROW := 32
const BARROW_DRAUGR := Vector2i(49, 32)
const BARROW_PACK := Vector2i(44, 36)
const BARROW_SHORTCUT_LINK := Vector2i(57, 32)
const BARROW_FROM_TEMPLE := Vector2i(56, 32)
const BARROW_NICHE := Vector2i(20, 30)
## The barrow's legend: enemy-ai's kinds (547, 548), the barrow's own level.json
## colours, never Level.LEGEND's.
const BARROW_LEGEND := {"monster_skeleton": "#d8d0b0", "monster_skeleton_guard": "#988c64", "monster_robber": "#8a5a2a", "monster_draugr": "#5a4636"}


func _ready() -> void:
	var level := ""
	var sample := ""
	var generation := 1
	var out := ""
	var scale := 8
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			level = arg.trim_prefix("--level=")
		elif arg.begins_with("--sample="):
			sample = arg.trim_prefix("--sample=")
		elif arg.begins_with("--generation="):
			generation = arg.trim_prefix("--generation=").to_int()
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--scale="):
			scale = arg.trim_prefix("--scale=").to_int()
	if not sample.is_empty():
		var made := sample_halls(sample)
		level = "sample_halls_" + sample
		Level.register(level, made["layout"], null, made["config"])
	get_tree().quit(write_sheet(level, generation, out, scale))


## Generation [param generation] of level [param level_name] drawn to
## [param out] at [param scale] pixels a layout pixel; 0 when written, with
## a line of what is on it, else 1 or 2 (said).
static func write_sheet(level_name: String, generation: int, out: String, scale := 8) -> int:
	if level_name.is_empty() or out.is_empty():
		printerr("plan_sheet: --level=<name> (or --sample=dwarven|old) and --out=<png> are needed")
		return 2
	if not Regen.marked(level_name):
		printerr("plan_sheet: %s is no regenerating level" % level_name)
		return 2
	var made := Regen.generate(level_name, maxi(generation, 1))
	if made.is_empty():
		printerr("plan_sheet: no map of %s joined every anchor" % level_name)
		return 1
	var layout: Image = made["layout"]
	var sheet := Image.create_empty(layout.get_width() * scale, layout.get_height() * scale, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.BLACK)
	var big := layout.duplicate() as Image
	big.resize(layout.get_width() * scale, layout.get_height() * scale, Image.INTERPOLATE_NEAREST)
	sheet.blend_rect(big, Rect2i(Vector2i.ZERO, big.get_size()), Vector2i.ZERO)
	for anchor: Dictionary in made["anchors"]:
		var rect: Rect2i = anchor["rect"]
		var px := Rect2i(rect.position * 2 * scale - Vector2i.ONE * (scale / 2), (rect.size * 2 - Vector2i.ONE) * scale + Vector2i.ONE * scale)
		px = px.intersection(Rect2i(Vector2i.ZERO, sheet.get_size()))
		var line := maxi(scale / 4, 1)
		sheet.fill_rect(Rect2i(px.position, Vector2i(px.size.x, line)), OUTLINE)
		sheet.fill_rect(Rect2i(Vector2i(px.position.x, px.end.y - line), Vector2i(px.size.x, line)), OUTLINE)
		sheet.fill_rect(Rect2i(px.position, Vector2i(line, px.size.y)), OUTLINE)
		sheet.fill_rect(Rect2i(Vector2i(px.end.x - line, px.position.y), Vector2i(line, px.size.y)), OUTLINE)
	var error := sheet.save_png(ProjectSettings.globalize_path(out) if out.begins_with("user://") or out.begins_with("res://") else out)
	if error != OK:
		printerr("plan_sheet: could not write %s (%s)" % [out, error_string(error)])
		return 1
	var level := Level.parse(layout, null, made["config"])
	var doors := 0
	for key: Vector3i in level["terrain"]["edges"]:
		if level["terrain"]["edges"][key] == Terrain.Edge.DOOR:
			doors += 1
	var kinds := {}
	for spec: Dictionary in level["entities"]:
		var kind := str(spec.get("kind", spec["name"].rstrip("0123456789").to_lower()))
		kinds[kind] = int(kinds.get(kind, 0)) + 1
	var names: Array = made["anchors"].map(func(anchor: Dictionary) -> String: return "%s %s" % [anchor["name"], anchor["rect"]])
	print("plan_sheet: %s generation %d (seed %d, %d of %d tries): %d floor cells, %d doors, %d torches, %s; anchors: %s -> %s" % [
		level_name, maxi(generation, 1), made["seed"], made["tries"], Regen.TRIES, level["terrain"]["floor"].size(), doors,
		level["terrain"]["torches"].size(), kinds, ", ".join(names), out])
	return 0


## The sample halls in [param style] ("dwarven" or "old"): {layout, config},
## SIZE cells, its four anchors bare floor, a link and spawn point in the
## gatehouse and in the deepest chamber. "barrow" gives sample_barrow.
static func sample_halls(style: String) -> Dictionary:
	if style == "barrow":
		return sample_barrow()
	var rects: Array[Rect2i] = []
	for anchor: Dictionary in ANCHORS:
		rects.append(Level.town_wall_rect(anchor))
	var rows: Array[String] = []
	for py in SIZE.y * 2 - 1:
		var row := ""
		for px in SIZE.x * 2 - 1:
			var floor_here := false
			if px % 2 == 0 and py % 2 == 0:
				for rect in rects:
					if rect.has_point(Vector2i(px / 2, py / 2)):
						floor_here = true
			row += "." if floor_here else " "
		rows.append(row)
	var layout := Level.image_from_rows(rows, {Vector2i(3, 3): "link", Vector2i(5, 4): "start", Vector2i(44, 36): "link"})
	var config := {"name": "Sample halls (%s)" % style, "walls": "stone", "floors": "stone", "starts": [[5, 4]],
		"spawn_points": {"from_castle": [4, 4], "from_below": [43, 35]},
		"links": [{"at": [3, 3], "to_map": "castle", "to_spawn": "from_halls"}, {"at": [44, 36], "to_map": "halls_2", "to_spawn": "from_above"}],
		"regenerate": {"generator": "labyrinth", "style": style, "every_days": 3, "anchors": ANCHORS,
			"rooms": {"count": [8, 12], "size": [[3, 3], [7, 6]]}, "loops": 0.2,
			"monsters": {"imp": 6, "brute": 2, "sneak": 2}, "chests": 3, "crates": 4}}
	return {"layout": layout, "config": config}


## The sample barrow (decision 541, the shape of the real one): {layout,
## config}, BARROW_SIZE cells, five anchors: the entrance vestibule under
## the mound's door at the top (the link up, the spawn point and a start),
## the altar room with the altar (a chest) and the hidden passage leaving
## its east wall through a door to the lair, the lair with the draugr's
## stand-in (a brute) and the spawn point from the temple, and the
## shortcut's nook off the lair's east side with its sealed link, and Pip's
## niche off the altar room's west side (npc's, 542 amended). Each anchor is
## walled but for the side the tombs come in by.
static func sample_barrow() -> Dictionary:
	var rows: Array[PackedStringArray] = []
	for py in BARROW_SIZE.y * 2 - 1:
		var row := PackedStringArray()
		row.resize(BARROW_SIZE.x * 2 - 1)
		row.fill(" ")
		rows.append(row)
	for anchor: Dictionary in BARROW_ANCHORS:
		var rect: Rect2i = Level.town_wall_rect(anchor)
		for cell in Level.rect_cells(rect):
			rows[cell.y * 2][cell.x * 2] = "."
		for side: String in anchor.get("walled", []):
			for cell in Level.rect_cells(rect):
				match side:
					"north":
						if cell.y == rect.position.y and cell.y > 0:
							rows[cell.y * 2 - 1][cell.x * 2] = "#"
					"south":
						if cell.y == rect.end.y - 1:
							rows[cell.y * 2 + 1][cell.x * 2] = "#"
					"west":
						if cell.x == rect.position.x:
							rows[cell.y * 2][cell.x * 2 - 1] = "#"
					"east":
						if cell.x == rect.end.x - 1:
							rows[cell.y * 2][cell.x * 2 + 1] = "#"
	var altar_rect: Rect2i = Level.town_wall_rect(BARROW_ANCHORS[1])
	rows[BARROW_DOOR_ROW * 2][(altar_rect.end.x - 1) * 2 + 1] = "+"  # The hidden passage's door, behind the altar.
	var lair_rect: Rect2i = Level.town_wall_rect(BARROW_ANCHORS[3])
	var nook_rect: Rect2i = Level.town_wall_rect(BARROW_ANCHORS[4])
	for y in range(nook_rect.position.y, nook_rect.end.y):
		rows[y * 2][(lair_rect.end.x - 1) * 2 + 1] = " "  # The lair's east wall opens on the shortcut's nook.
	var lines: Array[String] = []
	for row in rows:
		lines.append("".join(row))
	var markers := {BARROW_LINK: "link", BARROW_START: "start", BARROW_ALTAR: "chest", BARROW_DRAUGR: "monster_draugr",
		BARROW_PACK: "chest", BARROW_SHORTCUT_LINK: "link"}
	for guard: Vector2i in BARROW_GUARDS:
		markers[guard] = "monster_skeleton_guard"
	var layout := Level.image_from_rows(lines, markers, {"legend": BARROW_LEGEND})
	var config := {"name": "Sample barrow", "walls": "stone", "floors": "stone", "starts": [[BARROW_START.x, BARROW_START.y]], "legend": BARROW_LEGEND,
		"spawn_points": {"from_wilds": [BARROW_FROM_WILDS.x, BARROW_FROM_WILDS.y], "from_temple": [BARROW_FROM_TEMPLE.x, BARROW_FROM_TEMPLE.y]},
		"links": [{"at": [BARROW_LINK.x, BARROW_LINK.y], "to_map": "wilds", "to_spawn": "from_barrow"},
			{"at": [BARROW_SHORTCUT_LINK.x, BARROW_SHORTCUT_LINK.y], "to_map": "wilds", "to_spawn": "from_barrow_shortcut", "sealed": "draugr"}],
		"places": {"niche": {"at": [BARROW_NICHE.x, BARROW_NICHE.y], "kind": "other", "radius": 1, "name": "a niche in the wall"}},
		"entities": [{"at": [BARROW_ALTAR.x, BARROW_ALTAR.y], "name": "Altar", "props": {"slots": ["", "", "", ""]}},
			{"at": [BARROW_DRAUGR.x, BARROW_DRAUGR.y], "name": "Draugr"},
			{"at": [BARROW_PACK.x, BARROW_PACK.y], "name": "Runner's pack", "props": {"grave": false, "slots": ["", "", "", ""]}}],
		"regenerate": {"generator": "labyrinth", "style": "barrow", "every_days": 3, "anchors": BARROW_ANCHORS, "entrance": "entrance",
			"rooms": {"count": [9, 12], "size": [[5, 5], [8, 7]]}, "loops": 0.15,
			"monsters": {"skeleton": 4, "robber": 2}, "near": {"robber": "altar"}, "chests": 4}}
	return {"layout": layout, "config": config}
