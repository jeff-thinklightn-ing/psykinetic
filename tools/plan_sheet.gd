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
## anchors, or the sample barrow's layers (sample_barrow, sample_barrow_deep,
## sample_barrow_lair; decision 580). A level with no "regenerate" is drawn
## as it stands, its own "anchors" outlined. Writes
## nothing but --out; the level is read, never written.

const SIZE := Vector2i(48, 40)
const ANCHORS := [{"rect": [2, 2, 6, 5], "name": "gatehouse"}, {"rect": [4, 18, 7, 5], "name": "west hall"},
	{"rect": [37, 14, 7, 5], "name": "east hall"}, {"rect": [40, 33, 6, 5], "name": "deepest chamber"}]
const OUTLINE := Color(0.25, 0.6, 1.0)
## The barrow in layers (decision 580, Jeff: "crypt is still too cramped",
## and his answers on what each layer holds; 541 amended before it): three
## levels, one place. Each sample is the real level's twin (levels/barrow,
## levels/barrow_deep, levels/barrow_lair are written from them): the
## sizes, the anchors with the sides they are walled on, the named cells.
## Every way is five cells clear and every room 8 x 7 or more (Jeff:
## "halls need to be at least 2 tiles wider than the walls").
##
## Layer 1, "barrow": the town's newer dead, the wealthy's. The first hall
## under the mound (a large room, the burial table at its centre as a block
## of rock, seven niches a side cut into its east and west walls holding
## the town's dead, art-kit's wall.crypt pieces on the edges, a bay each
## side where the ways come in), the stair down behind one of them, the
## hidden door (608: a locked stone door on that niche's edge with one
## alcove cell behind it, found by pressing on it; the generator moves it
## each generation), the altar room with its guards and the tombs
## the generator lays off it, Pip's niche, the robbers' camp with the
## Runner's pack; the robbers walk it, after the altar's gold.
const BARROW_SIZE := Vector2i(80, 60)
const HALL := Rect2i(27, 1, 26, 16)
## The hall's floor is x 28..51; the columns outside it (x 27 and 52) are
## rock the niches are cut into, every other row, but the two bays on row 9
## where the ways come in and the hidden niche's alcove (BARROW_STAIR).
const HALL_NICHE_ROWS: Array[int] = [2, 4, 6, 8, 10, 12, 14]
const HALL_BAY_ROW := 9
const HALL_TABLE := Rect2i(38, 8, 3, 2)
const BARROW_ANCHORS := [
	{"rect": [27, 1, 26, 16], "name": "entrance"},
	{"rect": [30, 24, 18, 14], "name": "altar", "walled": ["east", "south"]},
	{"rect": [26, 28, 2, 2], "name": "niche", "walled": ["north", "west", "south"]},
	{"rect": [6, 42, 10, 8], "name": "camp", "walled": ["north", "west", "south"]}]
const BARROW_LINK := Vector2i(40, 1)
const BARROW_START := Vector2i(39, 2)
const BARROW_FROM_WILDS := Vector2i(40, 2)
const BARROW_STAIR := Vector2i(52, 14)
const BARROW_FROM_BELOW := Vector2i(51, 14)
const BARROW_ALTAR := Vector2i(38, 30)
const BARROW_GUARDS := [Vector2i(36, 30), Vector2i(40, 30)]
const BARROW_NICHE := Vector2i(26, 28)
const BARROW_PACK := Vector2i(7, 43)
const BARROW_TORCHES: Array[Vector2i] = [Vector2i(30, 2), Vector2i(49, 2), Vector2i(30, 15), Vector2i(49, 15)]
## Layer 2, "barrow_deep", the Ossuary: the ancient dead the town moved
## down, walking home; ways five wide and big rooms, the tombs and graves
## along them; the stair foot at the top (the entrance the bands count
## from) and the stair down at the far side.
const DEEP_SIZE := Vector2i(100, 80)
const DEEP_ANCHORS := [
	{"rect": [46, 1, 8, 6], "name": "entrance", "walled": ["north", "east", "west"]},
	{"rect": [67, 40, 6, 6], "name": "stair", "walled": ["north", "east", "south"]}]
const DEEP_LINK_UP := Vector2i(49, 1)
const DEEP_START := Vector2i(50, 2)
const DEEP_FROM_ABOVE := Vector2i(49, 2)
const DEEP_LINK_DOWN := Vector2i(70, 43)
const DEEP_FROM_BELOW := Vector2i(69, 43)
## Layer 3, "barrow_lair": the oldest dead, moved as far down as the town
## dared; damp and dark caverns (every room deep: no doors, no torches),
## and the Hall of Fallen Souls kept whole through every generation: a
## castle hall with pillars, the round table at its middle, the dais at the
## far end with the draugr on his throne and the hidden way out behind it
## (the temple's sealed shortcut); the one door in its north wall.
const LAIR_SIZE := Vector2i(100, 80)
const LAIR_HALL := Rect2i(34, 44, 32, 22)
const LAIR_ANCHORS := [
	{"rect": [46, 1, 8, 6], "name": "entrance", "walled": ["north", "east", "west"]},
	{"rect": [34, 44, 32, 22], "name": "lair", "walled": ["north", "east", "south", "west"]}]
const LAIR_DOOR := Vector2i(49, 44)
const LAIR_PILLARS: Array[Rect2i] = [Rect2i(39, 48, 2, 2), Rect2i(49, 48, 2, 2), Rect2i(59, 48, 2, 2),
	Rect2i(39, 58, 2, 2), Rect2i(49, 58, 2, 2), Rect2i(59, 58, 2, 2)]
const LAIR_TABLE := Rect2i(48, 52, 3, 3)
const LAIR_DAIS := Rect2i(44, 61, 12, 4)
const LAIR_LINK_UP := Vector2i(49, 1)
const LAIR_START := Vector2i(50, 2)
const LAIR_FROM_ABOVE := Vector2i(49, 2)
const LAIR_DRAUGR := Vector2i(49, 62)
const LAIR_FROM_TEMPLE := Vector2i(49, 63)
const LAIR_SHORTCUT_LINK := Vector2i(49, 64)
## The barrow's legend: enemy-ai's kinds (547, 548), the barrow's own level.json
## colours, never Level.LEGEND's.
const BARROW_LEGEND := {"monster_skeleton": "#d8d0b0", "monster_skeleton_guard": "#988c64", "monster_robber": "#8a5a2a", "monster_draugr": "#5a4636"}


## Blank rows (void) for a level [param size] cells across, two pixels a cell.
static func _blank_rows(size: Vector2i) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	for py in size.y * 2 - 1:
		var row := PackedStringArray()
		row.resize(size.x * 2 - 1)
		row.fill(" ")
		rows.append(row)
	return rows


static func _floor_rect(rows: Array[PackedStringArray], rect: Rect2i) -> void:
	for cell in Level.rect_cells(rect):
		rows[cell.y * 2][cell.x * 2] = "."


static func _rock_rect(rows: Array[PackedStringArray], rect: Rect2i) -> void:
	for cell in Level.rect_cells(rect):
		rows[cell.y * 2][cell.x * 2] = " "


## The edge of [param cell] on [param side] set to [param mark] ("#" a
## wall, "+" a door, " " open); the map's own rim has no edge pixel.
static func _edge(rows: Array[PackedStringArray], cell: Vector2i, side: String, mark: String) -> void:
	var px := cell * 2
	match side:
		"north": px.y -= 1
		"south": px.y += 1
		"west": px.x -= 1
		"east": px.x += 1
	if px.y < 0 or px.x < 0 or px.y >= rows.size() or px.x >= rows[0].size():
		return
	rows[px.y][px.x] = mark


## [param rect] walled along [param side].
static func _wall_side(rows: Array[PackedStringArray], rect: Rect2i, side: String) -> void:
	for cell in Level.rect_cells(rect):
		match side:
			"north":
				if cell.y == rect.position.y:
					_edge(rows, cell, side, "#")
			"south":
				if cell.y == rect.end.y - 1:
					_edge(rows, cell, side, "#")
			"west":
				if cell.x == rect.position.x:
					_edge(rows, cell, side, "#")
			"east":
				if cell.x == rect.end.x - 1:
					_edge(rows, cell, side, "#")


## The anchors of [param anchors] laid as floor, walled on their "walled" sides.
static func _lay_anchors(rows: Array[PackedStringArray], anchors: Array) -> void:
	for anchor: Dictionary in anchors:
		var rect: Rect2i = Level.town_wall_rect(anchor)
		_floor_rect(rows, rect)
		for side: String in anchor.get("walled", []):
			_wall_side(rows, rect, side)


static func _lines(rows: Array[PackedStringArray]) -> Array[String]:
	var lines: Array[String] = []
	for row in rows:
		lines.append("".join(row))
	return lines


## Layer 1: {layout, config}, BARROW_SIZE cells (decision 580).
static func sample_barrow() -> Dictionary:
	var rows := _blank_rows(BARROW_SIZE)
	_lay_anchors(rows, BARROW_ANCHORS)
	# The first hall: its floor between the niche columns, walled north and
	# south; the niches every other row, walled on their three outer sides;
	# the bays on row 9 open to the rock (the ways come in there); the
	# burial table a block of rock at the centre.
	_rock_rect(rows, HALL)
	var inner := Rect2i(HALL.position.x + 1, HALL.position.y, HALL.size.x - 2, HALL.size.y)
	_floor_rect(rows, inner)
	_wall_side(rows, inner, "north")
	_wall_side(rows, inner, "south")
	for side_x: int in [HALL.position.x, HALL.end.x - 1]:
		var bay := Vector2i(side_x, HALL_BAY_ROW)
		rows[bay.y * 2][bay.x * 2] = "."
		_edge(rows, bay, "north", "#")
		_edge(rows, bay, "south", "#")
	# The hidden niche's alcove (608): the stair's cell behind a door edge in
	# the east wall, walled on its other sides.
	rows[BARROW_STAIR.y * 2][BARROW_STAIR.x * 2] = "."
	_edge(rows, BARROW_FROM_BELOW, "east", "+")
	for side: String in ["north", "south", "east"]:
		_edge(rows, BARROW_STAIR, side, "#")
	_rock_rect(rows, HALL_TABLE)
	var markers := {BARROW_LINK: "link", BARROW_START: "start", BARROW_STAIR: "link", BARROW_ALTAR: "chest", BARROW_PACK: "chest"}
	for guard: Vector2i in BARROW_GUARDS:
		markers[guard] = "monster_skeleton_guard"
	for torch: Vector2i in BARROW_TORCHES:
		markers[torch] = "torch"
	var layout := Level.image_from_rows(_lines(rows), markers, {"legend": BARROW_LEGEND})
	var config := {"name": "The Barrow", "outdoor": false, "depth": 1, "walls": "stone", "floors": "stone", "grave_goods": true,
		"starts": [[BARROW_START.x, BARROW_START.y]],
		"spawn_points": {"from_wilds": [BARROW_FROM_WILDS.x, BARROW_FROM_WILDS.y], "from_below": [BARROW_FROM_BELOW.x, BARROW_FROM_BELOW.y]},
		"links": [{"at": [BARROW_LINK.x, BARROW_LINK.y], "to_map": "wilds", "to_spawn": "from_barrow"},
			{"at": [BARROW_STAIR.x, BARROW_STAIR.y], "to_map": "barrow_deep", "to_spawn": "from_above", "hidden": true}],
		"niches": barrow_niches(),
		"places": {"niche": {"at": [BARROW_NICHE.x, BARROW_NICHE.y], "kind": "other", "radius": 1, "name": "a niche in the wall"}},
		"entities": [{"at": [BARROW_ALTAR.x, BARROW_ALTAR.y], "name": "Altar", "props": {"slots": ["", "", "", ""]}},
			{"at": [BARROW_PACK.x, BARROW_PACK.y], "name": "Runner's pack", "props": {"grave": false, "slots": ["", "", "", ""]}}],
		"regenerate": {"generator": "labyrinth", "style": "barrow", "layer": 1, "ways": 5, "every_days": 3, "anchors": BARROW_ANCHORS,
			"entrance": "entrance", "rooms": {"count": [8, 11], "size": [[8, 7], [14, 11]]}, "loops": 0.15,
			"monsters": {"robber": 4}, "near": {"robber": "altar"}, "chests": 3},
		"legend": BARROW_LEGEND, "respawn_s": {"robber": 300, "skeleton_guard": 600}}
	return {"layout": layout, "config": config}


## The first hall's niches as the template lists them (608): seven a side
## on the floor cells by the hall's west and east walls, each facing its
## wall ([x, y, dx, dy, kind, variant]: the town's dead in arches, "a", and
## hollows, "c", a slab, variant 2, now and then), the south-east one
## "hidden" (the stair's door, BARROW_STAIR behind it). The generator
## re-rolls the kinds and the pick each generation (Labyrinth.niche_plan).
static func barrow_niches() -> Array:
	var out: Array = []
	for i in HALL_NICHE_ROWS.size():
		var y: int = HALL_NICHE_ROWS[i]
		var kind := "a" if i % 2 == 0 else "c"
		out.append([HALL.position.x + 1, y, -1, 0, kind, 2 if i == 2 else 1])
		var east := Vector2i(HALL.end.x - 2, y)
		if east == BARROW_FROM_BELOW:
			out.append([east.x, east.y, 1, 0, "hidden", 1])
		else:
			out.append([east.x, east.y, 1, 0, kind, 2 if i == 4 else 1])
	return out


## Layer 2, the Ossuary: {layout, config}, DEEP_SIZE cells (decision 580).
static func sample_barrow_deep() -> Dictionary:
	var rows := _blank_rows(DEEP_SIZE)
	_lay_anchors(rows, DEEP_ANCHORS)
	var markers := {DEEP_LINK_UP: "link", DEEP_START: "start", DEEP_LINK_DOWN: "link"}
	var layout := Level.image_from_rows(_lines(rows), markers, {"legend": BARROW_LEGEND})
	var config := {"name": "The Ossuary", "outdoor": false, "depth": 2, "walls": "stone", "floors": "stone", "grave_goods": true,
		"starts": [[DEEP_START.x, DEEP_START.y]],
		"spawn_points": {"from_above": [DEEP_FROM_ABOVE.x, DEEP_FROM_ABOVE.y], "from_below": [DEEP_FROM_BELOW.x, DEEP_FROM_BELOW.y]},
		"links": [{"at": [DEEP_LINK_UP.x, DEEP_LINK_UP.y], "to_map": "barrow", "to_spawn": "from_below"},
			{"at": [DEEP_LINK_DOWN.x, DEEP_LINK_DOWN.y], "to_map": "barrow_lair", "to_spawn": "from_above"}],
		"entities": [],
		"regenerate": {"generator": "labyrinth", "style": "barrow", "layer": 2, "ways": 5, "every_days": 3, "anchors": DEEP_ANCHORS,
			"entrance": "entrance", "rooms": {"count": [10, 14], "size": [[8, 7], [16, 12]]}, "loops": 0.15,
			"monsters": {"skeleton": 6}, "chests": 5},
		"legend": BARROW_LEGEND, "respawn_s": {"skeleton": 600}}
	return {"layout": layout, "config": config}


## Layer 3, the dark caverns and the Hall of Fallen Souls: {layout, config},
## LAIR_SIZE cells (decision 580).
static func sample_barrow_lair() -> Dictionary:
	var rows := _blank_rows(LAIR_SIZE)
	_lay_anchors(rows, LAIR_ANCHORS)
	_edge(rows, LAIR_DOOR, "north", "+")  # The hall's one door, where the way comes in (held shut behind the first player in, 573 amended).
	for pillar in LAIR_PILLARS:
		_rock_rect(rows, pillar)
	_rock_rect(rows, LAIR_TABLE)
	var markers := {LAIR_LINK_UP: "link", LAIR_START: "start", LAIR_SHORTCUT_LINK: "link", LAIR_DRAUGR: "monster_draugr"}
	var layout := Level.image_from_rows(_lines(rows), markers, {"legend": BARROW_LEGEND})
	var config := {"name": "Hall of Fallen Souls", "outdoor": false, "depth": 3, "walls": "stone", "floors": "stone", "grave_goods": true,
		"starts": [[LAIR_START.x, LAIR_START.y]],
		"spawn_points": {"from_above": [LAIR_FROM_ABOVE.x, LAIR_FROM_ABOVE.y], "from_temple": [LAIR_FROM_TEMPLE.x, LAIR_FROM_TEMPLE.y]},
		"links": [{"at": [LAIR_LINK_UP.x, LAIR_LINK_UP.y], "to_map": "barrow_deep", "to_spawn": "from_below"},
			{"at": [LAIR_SHORTCUT_LINK.x, LAIR_SHORTCUT_LINK.y], "to_map": "wilds", "to_spawn": "from_barrow_shortcut", "sealed": "draugr"}],
		"entities": [{"at": [LAIR_DRAUGR.x, LAIR_DRAUGR.y], "name": "Draugr"}],
		"regenerate": {"generator": "labyrinth", "style": "barrow", "layer": 3, "ways": 5, "every_days": 3, "anchors": LAIR_ANCHORS,
			"entrance": "entrance", "rooms": {"count": [10, 14], "size": [[10, 8], [16, 12]]}, "loops": 0.15,
			"monsters": {"skeleton": 6}, "chests": 4},
		"stills": ["barrow_deep", "barrow"], "dead": {"temper": "bold", "sees_in_dark": true, "graves": false},
		"damp": true, "ambient": 0.03,
		"legend": BARROW_LEGEND, "respawn_s": {"skeleton": 600}}
	return {"layout": layout, "config": config}


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
	var made := {}
	if Regen.marked(level_name):
		made = Regen.generate(level_name, maxi(generation, 1))
		if made.is_empty():
			printerr("plan_sheet: no map of %s joined every anchor" % level_name)
			return 1
	else:
		# Drawn by hand, never laid again (the draugr's hall, 580): the
		# template as it stands, its own top-level "anchors" outlined.
		var template := Level.template(level_name)
		if template.get("layout") == null:
			printerr("plan_sheet: %s is no level" % level_name)
			return 2
		var warnings: Array[String] = []
		var anchors: Array = Level.regenerate_from({"regenerate": {"anchors": template["config"].get("anchors", [])}}, warnings)["anchors"]
		made = {"layout": template["layout"], "config": template["config"], "anchors": anchors, "seed": 0, "tries": 0}
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
	if style == "barrow_deep":
		return sample_barrow_deep()
	if style == "barrow_lair":
		return sample_barrow_lair()
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
