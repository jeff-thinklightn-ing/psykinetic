extends Node
## A plan sheet of a regenerating level's generation (decision 470), for
## Jeff: the generated layout drawn large in the legend's colours (rock
## black, floor grey, walls dark brown, doors orange, torches yellow,
## chests brown, crates tan, monsters reds, links magenta, starts cyan),
## each anchor outlined in blue. Headless:
##   godot --headless --path <repo> --scene res://tools/plan_sheet.tscn -- --level=<name> --generation=<n> --out=<png> [--scale=8]
##   godot --headless --path <repo> --scene res://tools/plan_sheet.tscn -- --sample=dwarven|old|barrow --generation=<n> --out=<png>
##   godot --headless --path <repo> --scene res://tools/plan_sheet.tscn -- --tower=<floors> --generation=<n> --out=<png>
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
## rock the niches are cut into, every other row, but the two bays, two
## rows each (612: no passage one wide), where the ways come in and the
## hidden niche's alcove (BARROW_STAIR).
const HALL_NICHE_ROWS: Array[int] = [2, 4, 6, 8, 12, 14, 16]
const HALL_BAY_ROWS: Array[int] = [9, 10]
const HALL_TABLE := Rect2i(38, 8, 3, 2)
const BARROW_ANCHORS := [
	{"rect": [27, 1, 26, 16], "name": "entrance"},
	{"rect": [30, 24, 18, 14], "name": "altar", "walled": ["east", "south"]},
	{"rect": [26, 28, 2, 2], "name": "niche", "walled": ["north", "west", "south"]},
	{"rect": [6, 42, 10, 8], "name": "camp", "walled": ["north", "west", "south"]}]
const BARROW_LINK := Vector2i(40, 1)
const BARROW_START := Vector2i(39, 2)
const BARROW_FROM_WILDS := Vector2i(40, 2)
const BARROW_STAIR := Vector2i(52, 16)
const BARROW_FROM_BELOW := Vector2i(51, 16)
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
## The feast (580 step 3b): eight chairs on the ring round the table facing
## in, four broken tables against the east and west walls between the
## pillar rows (their long side along the wall, never a cell off it: 612).
const LAIR_CHAIRS: Array = [[Vector2i(48, 51), Vector2i(0, 1)], [Vector2i(50, 51), Vector2i(0, 1)],
	[Vector2i(48, 55), Vector2i(0, -1)], [Vector2i(50, 55), Vector2i(0, -1)],
	[Vector2i(47, 52), Vector2i(1, 0)], [Vector2i(47, 54), Vector2i(1, 0)],
	[Vector2i(51, 52), Vector2i(-1, 0)], [Vector2i(51, 54), Vector2i(-1, 0)]]
const LAIR_BROKEN_TABLES: Array = [[Vector2i(34, 52), Vector2i(1, 0)], [Vector2i(34, 55), Vector2i(1, 0)],
	[Vector2i(65, 52), Vector2i(-1, 0)], [Vector2i(65, 55), Vector2i(-1, 0)]]
## The dais (580 step 3): one height level up, its back row against the
## hall's south wall (no strip a cell wide behind it: 612), the row before it
## twelve stair cells, its sides ledges.
const LAIR_DAIS := Rect2i(44, 62, 12, 4)
const LAIR_STAIR_ROW := 61
const LAIR_LINK_UP := Vector2i(49, 1)
const LAIR_START := Vector2i(50, 2)
const LAIR_FROM_ABOVE := Vector2i(49, 2)
const LAIR_DRAUGR := Vector2i(49, 63)
const LAIR_FROM_TEMPLE := Vector2i(49, 64)
const LAIR_SHORTCUT_LINK := Vector2i(49, 65)
## The barrow's legend: enemy-ai's kinds (547, 548), the barrow's own level.json
## colours, never Level.LEGEND's.
## The first hall's own decor (647): webs in the two corners by the way
## in, where nobody walks, and a strip of moss at the south wall's foot.
const BARROW_DECOR: Array = [[28, 1, -1, -1, "web_corner", 1], [51, 1, 1, -1, "web_corner", 2], [33, 16, 0, 1, "moss_strip", 1]]
## The Hall of Fallen Souls' own decor (647; the damp hall): moss along
## its walls' feet between the furniture, patches on its floor off the
## ways, webs in its four corners.
const LAIR_DECOR: Array = [
	[34, 44, -1, -1, "web_corner", 1], [65, 44, 1, -1, "web_corner", 2], [34, 65, -1, 1, "web_corner", 2], [65, 65, 1, 1, "web_corner", 1],
	[34, 46, -1, 0, "moss_strip", 1], [34, 49, -1, 0, "moss_strip", 2], [34, 58, -1, 0, "moss_strip", 1], [34, 61, -1, 0, "moss_strip", 2],
	[65, 47, 1, 0, "moss_strip", 2], [65, 50, 1, 0, "moss_strip", 1], [65, 59, 1, 0, "moss_strip", 2], [65, 62, 1, 0, "moss_strip", 1],
	[37, 44, 0, -1, "moss_strip", 1], [43, 44, 0, -1, "moss_strip", 2], [56, 44, 0, -1, "moss_strip", 1], [62, 44, 0, -1, "moss_strip", 2],
	[37, 65, 0, 1, "moss_strip", 2], [41, 65, 0, 1, "moss_strip", 1], [58, 65, 0, 1, "moss_strip", 1], [62, 65, 0, 1, "moss_strip", 2],
	[37, 47, 0, 0, "moss_patch", 1], [44, 50, 0, 0, "moss_patch", 2], [55, 50, 0, 0, "moss_patch", 3], [62, 47, 0, 0, "moss_patch", 1],
	[38, 58, 0, 0, "moss_patch", 2], [61, 58, 0, 0, "moss_patch", 3], [45, 57, 0, 0, "moss_patch", 1], [54, 57, 0, 0, "moss_patch", 2],
	[40, 63, 0, 0, "moss_patch", 3], [59, 63, 0, 0, "moss_patch", 1]]
const BARROW_LEGEND := {"monster_skeleton": "#d8d0b0", "monster_skeleton_guard": "#988c64", "monster_robber": "#8a5a2a", "monster_draugr": "#5a4636"}
## The Dwarven Halls under the castle (613, dungeon's side; Jeff: the smith
## sought a great dwarven forge deep below, his guards were ambushed, he is
## held there forging goblin weapons): one level in the dwarven style, three
## rooms kept through every generation. The stair foot under the gatehouse
## (the link up to the castle's "from_halls", the spawn "from_castle"), the
## ambush a third of the way down (the smith's wagon and baggage where his
## guards fell: markers, and three of the guards where they fell, art-kit's
## prop.fallen_guard as decor with a facing, 613 amended), and the great
## forge at the deepest point: the forge 6 x 3 against its south wall
## (art-kit's building.dwarven_forge, solid, facing into the room), the
## stand cell between its anvils the refuge place "dwarven_forge" the
## sought smith is held at (economy's 613; its "where" is castle_dungeon,
## the goblins' band stands there: enemy-ai's), the goblins' weapon rack
## against the south wall east of the forge (building.weapon_rack, 2 x 1,
## solid: no fight stands a body in the blades), four pillars in two rows,
## a chest in each back corner, torches. Every way five cells clear, every
## piece of furniture with a two-cell way round it (612).
const HALLS_SIZE := Vector2i(90, 70)
const HALLS_ANCHORS := [
	{"rect": [40, 1, 10, 8], "name": "stair_foot", "walled": ["north", "east", "west"]},
	{"rect": [18, 26, 14, 10], "name": "ambush", "walled": ["north", "south"]},
	{"rect": [35, 54, 20, 14], "name": "forge", "walled": ["east", "south", "west"]}]
const HALLS_LINK_UP := Vector2i(44, 1)
const HALLS_START := Vector2i(45, 2)
const HALLS_FROM_CASTLE := Vector2i(44, 2)
const HALLS_FORGE := Rect2i(42, 65, 6, 3)
const HALLS_STAND := Vector2i(43, 64)  # Between the two anvils along the forge's front (art-kit: it faces [0, -1], into the room).
const HALLS_PILLARS: Array[Rect2i] = [Rect2i(38, 57, 2, 2), Rect2i(50, 57, 2, 2), Rect2i(38, 61, 2, 2), Rect2i(50, 61, 2, 2)]
const HALLS_CHESTS: Array[Vector2i] = [Vector2i(36, 66), Vector2i(53, 66)]
const HALLS_TORCHES: Array[Vector2i] = [Vector2i(41, 2), Vector2i(48, 2), Vector2i(36, 55), Vector2i(53, 55), Vector2i(36, 63), Vector2i(53, 63)]
const HALLS_CART := Vector2i(24, 30)
const HALLS_CRATES: Array[Vector2i] = [Vector2i(22, 31), Vector2i(27, 29)]
## The goblins' weapon rack (613 amended): its west cell, its back to the
## forge room's south wall, east of the forge.
const HALLS_RACK := Vector2i(50, 67)
## The smith's fallen guards (613 amended): [x, y, dx, dy, "fallen_guard",
## variant]; one on his side facing the cart he guarded, one face down
## running north, one face down toward the west wall (613 amended (2): a
## rolled yaw ran his body toward the usual camera and read as kneeling);
## none on a marker's cell or in the ways in.
const HALLS_GUARDS: Array = [[23, 30, 1, 0, "fallen_guard", 1], [26, 31, 0, -1, "fallen_guard", 2], [21, 29, -1, 0, "fallen_guard", 2]]


## The tower's inside (659; Jeff: "The tower's inside shifts too"): a tower
## of TOWER_FLOORS floors, each a small level of its own, TOWER_ACROSS cells
## square with an octagonal footprint, laid by the labyrinth's tower style
## and joined to the floors above and below by stair links kept in the
## shaft anchor at the same cells on every floor (the stair down west of
## the middle, the stair up east, the arriving spawns beside them, two
## clear cells round each whatever the floor rolls). The foot has the door
## out at its south edge and the mine's way down under the north wall, a
## sealed link; the top floor's shaft opens into the chamber. A sample in
## memory for the tests and the sheet: no real tower until Jeff places it.
const TOWER_FLOORS := 4
const TOWER_ACROSS := 22


## Floor [param floor] (1 the foot, [param floors] the top) of a sample
## tower [param across] cells square, its floors named "<prefix>_<floor>",
## the door out to "<prefix>_outside" and the sealed way down to
## "<prefix>_mine": {layout, config}.
static func sample_tower(floor: int, floors: int, prefix := "lab_tower", across := TOWER_ACROSS) -> Dictionary:
	var size := Vector2i(across, across)
	var c := across / 2
	var anchors: Array = [{"rect": [c - 3, c - 2, 7, 6], "name": "shaft"}]
	if floor == 1:
		anchors.append({"rect": [c - 2, across - 4, 5, 3], "name": "door", "walled": ["east", "west"]})
		anchors.append({"rect": [c - 1, 1, 3, 3], "name": "hatch", "walled": ["north", "east", "west"]})
	if floor == floors:
		anchors.append({"rect": [c - 5, 2, 10, c - 4], "name": "chamber", "walled": ["north", "east", "west", "south"]})
	var rows := _blank_rows(size)
	_lay_anchors(rows, anchors)
	if floor == floors:
		for x in range(c - 3, c + 4):
			_edge(rows, Vector2i(x, c - 3), "south", " ")  # The chamber opens onto the shaft below it.
	var down := Vector2i(c - 1, c)
	var up := Vector2i(c + 1, c)
	var markers := {}
	var links: Array = []
	var spawns := {}
	var start := Vector2i(c, c - 1)
	if floor < floors:
		markers[up] = "link"
		links.append({"at": [up.x, up.y], "to_map": "%s_%d" % [prefix, floor + 1], "to_spawn": "from_below", "cue": "up", "variant": 3})
		spawns["from_above"] = [c + 1, c + 1]
	if floor > 1:
		markers[down] = "link"
		links.append({"at": [down.x, down.y], "to_map": "%s_%d" % [prefix, floor - 1], "to_spawn": "from_above", "cue": "down", "variant": 3})
		spawns["from_below"] = [c - 1, c + 1]
	if floor == 1:
		var door := Vector2i(c, across - 2)
		markers[door] = "link"
		links.append({"at": [door.x, door.y], "to_map": "%s_outside" % prefix, "to_spawn": "", "cue": "arch"})
		spawns["from_outside"] = [c, across - 3]
		start = Vector2i(c + 1, across - 3)
		var hatch := Vector2i(c, 2)
		markers[hatch] = "link"
		links.append({"at": [hatch.x, hatch.y], "to_map": "%s_mine" % prefix, "to_spawn": "", "sealed": "tower_mine", "cue": "sealed"})
	if floor == floors:
		markers[Vector2i(c - 4, 3)] = "torch"
		markers[Vector2i(c + 3, 3)] = "torch"
	markers[start] = "start"
	var layout := Level.image_from_rows(_lines(rows), markers)
	var config := {"name": "Sample tower, floor %d of %d" % [floor, floors], "outdoor": false, "walls": "stone", "floors": "stone",
		"starts": [[start.x, start.y]], "spawn_points": spawns, "links": links,
		"regenerate": {"generator": "labyrinth", "style": "tower", "footprint": "octagon", "every_days": 3, "anchors": anchors,
			"rooms": {"count": [4, 7], "size": [[3, 3], [7, 6]]}, "loops": 0.15, "chests": 1}}
	return {"layout": layout, "config": config}


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
	# south; the niches cut into the long walls every other row (608); the
	# bays, two rows each, open to the rock (the ways come in there); the
	# burial table a block of rock at the centre.
	_rock_rect(rows, HALL)
	var inner := Rect2i(HALL.position.x + 1, HALL.position.y, HALL.size.x - 2, HALL.size.y)
	_floor_rect(rows, inner)
	_wall_side(rows, inner, "north")
	_wall_side(rows, inner, "south")
	for side_x: int in [HALL.position.x, HALL.end.x - 1]:
		for y: int in HALL_BAY_ROWS:
			rows[y * 2][side_x * 2] = "."
		_edge(rows, Vector2i(side_x, HALL_BAY_ROWS[0]), "north", "#")
		_edge(rows, Vector2i(side_x, HALL_BAY_ROWS[-1]), "south", "#")
	# The hidden niche's alcove (608): the stair's cell behind a door edge in
	# the east wall, walled on its other sides.
	rows[BARROW_STAIR.y * 2][BARROW_STAIR.x * 2] = "."
	_edge(rows, BARROW_FROM_BELOW, "east", "+")
	for side: String in ["north", "south", "east"]:
		_edge(rows, BARROW_STAIR, side, "#")
	var markers := {BARROW_LINK: "link", BARROW_START: "start", BARROW_STAIR: "link", BARROW_ALTAR: "chest", BARROW_PACK: "chest"}
	for guard: Vector2i in BARROW_GUARDS:
		markers[guard] = "monster_skeleton_guard"
	for torch: Vector2i in BARROW_TORCHES:
		markers[torch] = "torch"
	var layout := Level.image_from_rows(_lines(rows), markers, {"legend": BARROW_LEGEND})
	var config := {"name": "The Barrow", "outdoor": false, "depth": 1, "walls": "stone", "floors": "stone", "grave_goods": true,
		"buildings": [{"slot": "building.burial_table", "at": [HALL_TABLE.position.x, HALL_TABLE.position.y]}],  # The old king's table (580 step 3).
		"starts": [[BARROW_START.x, BARROW_START.y]],
		"spawn_points": {"from_wilds": [BARROW_FROM_WILDS.x, BARROW_FROM_WILDS.y], "from_below": [BARROW_FROM_BELOW.x, BARROW_FROM_BELOW.y]},
		"links": [{"at": [BARROW_LINK.x, BARROW_LINK.y], "to_map": "wilds", "to_spawn": "from_barrow"},
			{"at": [BARROW_STAIR.x, BARROW_STAIR.y], "to_map": "barrow_deep", "to_spawn": "from_above", "hidden": true}],
		"niches": barrow_niches(),
		"decor": BARROW_DECOR,  # Webs in the entry corners, moss at the south wall (647).
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
		"loot": {"chest": "ossuary_grave"},  # Mail shirts among the dead's goods (622, dungeon's side).
		"starts": [[DEEP_START.x, DEEP_START.y]],
		"spawn_points": {"from_above": [DEEP_FROM_ABOVE.x, DEEP_FROM_ABOVE.y], "from_below": [DEEP_FROM_BELOW.x, DEEP_FROM_BELOW.y]},
		"links": [{"at": [DEEP_LINK_UP.x, DEEP_LINK_UP.y], "to_map": "barrow", "to_spawn": "from_below"},
			{"at": [DEEP_LINK_DOWN.x, DEEP_LINK_DOWN.y], "to_map": "barrow_lair", "to_spawn": "from_above"}],
		"entities": [],
		"regenerate": {"generator": "labyrinth", "style": "barrow", "layer": 2, "ways": 5, "every_days": 3, "anchors": DEEP_ANCHORS,
			"entrance": "entrance", "rooms": {"count": [10, 14], "size": [[8, 7], [16, 12]]}, "loops": 0.15,
			"monsters": {"skeleton": 14}, "chests": 5},  # 14 a draft (decision 631; Jeff: not enough skeletons), spread by band.
		"legend": BARROW_LEGEND, "respawn_s": {"skeleton": 600}}
	return {"layout": layout, "config": config}


## Layer 3, the dark caverns and the Hall of Fallen Souls: {layout, config},
## LAIR_SIZE cells (decision 580).
static func sample_barrow_lair() -> Dictionary:
	var rows := _blank_rows(LAIR_SIZE)
	_lay_anchors(rows, LAIR_ANCHORS)
	_edge(rows, LAIR_DOOR, "north", "+")  # The hall's one door, where the way comes in (held shut behind the first player in, 573 amended).
	var markers := {LAIR_LINK_UP: "link", LAIR_START: "start", LAIR_SHORTCUT_LINK: "link", LAIR_DRAUGR: "monster_draugr"}
	var heights := {}
	for cell in Level.rect_cells(LAIR_DAIS):
		heights[cell] = 1
	for x in range(LAIR_DAIS.position.x, LAIR_DAIS.end.x):
		markers[Vector2i(x, LAIR_STAIR_ROW)] = "stair"
	var layout := Level.image_from_rows(_lines(rows), markers, {"legend": BARROW_LEGEND})
	var pillars: Array = []
	for pillar in LAIR_PILLARS:
		pillars.append({"slot": "building.crypt_pillar", "at": [pillar.position.x, pillar.position.y]})
	# The feast (3b): the round table in place of its rock block, the chairs
	# round it, the broken tables against the walls, the throne at his cell
	# facing the hall.
	pillars.append({"slot": "building.round_table", "at": [LAIR_TABLE.position.x, LAIR_TABLE.position.y]})
	for chair: Array in LAIR_CHAIRS:
		pillars.append({"slot": "building.hall_chair", "at": [chair[0].x, chair[0].y], "facing": [chair[1].x, chair[1].y]})
	for table: Array in LAIR_BROKEN_TABLES:
		pillars.append({"slot": "building.broken_table", "at": [table[0].x, table[0].y], "facing": [table[1].x, table[1].y]})
	pillars.append({"slot": "building.throne", "at": [LAIR_DRAUGR.x, LAIR_DRAUGR.y], "facing": [0, -1]})
	var config := {"name": "Hall of Fallen Souls", "outdoor": false, "depth": 3, "walls": "stone", "floors": "stone", "grave_goods": true,
		"loot": {"chest": "fallen_grave"},  # Mail, and plate rare, with the oldest dead (622, dungeon's side).
		"buildings": pillars,  # The six pillars and the feast (580 step 3).
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
		"decor": LAIR_DECOR,  # The damp hall's moss and its cobwebbed corners (647).
		"legend": BARROW_LEGEND, "respawn_s": {"skeleton": 600}}
	return {"layout": layout, "height": Level.height_image(layout, heights), "config": config}


func _ready() -> void:
	var level := ""
	var sample := ""
	var tower := 0
	var generation := 1
	var out := ""
	var scale := 8
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			level = arg.trim_prefix("--level=")
		elif arg.begins_with("--sample="):
			sample = arg.trim_prefix("--sample=")
		elif arg.begins_with("--tower="):
			tower = arg.trim_prefix("--tower=").to_int()
		elif arg.begins_with("--generation="):
			generation = arg.trim_prefix("--generation=").to_int()
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--scale="):
			scale = arg.trim_prefix("--scale=").to_int()
	if tower > 0:
		# The sample tower's floors in a row (659), the foot at the left.
		for floor in range(1, tower + 1):
			var made := sample_tower(floor, tower)
			Level.register("sample_tower_%d" % floor, made["layout"], null, made["config"])
		get_tree().quit(write_tower_sheet("sample_tower", tower, generation, out, scale))
		return
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
	var sheet := sheet_image(made, scale)
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


## A generation [param made] (Regen.generate's shape: layout, anchors) drawn
## at [param scale] pixels a layout pixel, each anchor outlined.
static func sheet_image(made: Dictionary, scale: int) -> Image:
	var layout: Image = made["layout"]
	var sheet := Image.create_empty(layout.get_width() * scale, layout.get_height() * scale, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.BLACK)
	var big := layout.duplicate() as Image
	big.convert(Image.FORMAT_RGBA8)  # A layout saved without alpha blends onto the sheet all the same.
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
	return sheet


## A tower's floors (659) as one sheet, the foot at the left and the top
## at the right, a strip of black between: generation [param generation]
## of each of the [param floors] levels "<prefix>_<floor>" (registered
## already) at [param scale], written to [param out]; 0 when written, 1
## when a floor could not be laid or the file not written.
static func write_tower_sheet(prefix: String, floors: int, generation: int, out: String, scale := 8) -> int:
	var images: Array[Image] = []
	var width := 0
	var height := 0
	for floor in range(1, floors + 1):
		var name := "%s_%d" % [prefix, floor]
		var made := Regen.generate(name, maxi(generation, 1))
		if made.is_empty():
			printerr("plan_sheet: no map of %s joined every anchor" % name)
			return 1
		var image := sheet_image(made, scale)
		images.append(image)
		width += image.get_width() + (scale * 2 if floor > 1 else 0)
		height = maxi(height, image.get_height())
		print("plan_sheet: %s generation %d (seed %d, %d of %d tries)" % [name, maxi(generation, 1), made["seed"], made["tries"], Regen.TRIES])
	var sheet := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.BLACK)
	var x := 0
	for image in images:
		sheet.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(x, 0))
		x += image.get_width() + scale * 2
	var error := sheet.save_png(ProjectSettings.globalize_path(out) if out.begins_with("user://") or out.begins_with("res://") else out)
	if error != OK:
		printerr("plan_sheet: could not write %s (%s)" % [out, error_string(error)])
		return 1
	print("plan_sheet: %s, %d floors -> %s" % [prefix, floors, out])
	return 0


## The Dwarven Halls: {layout, config}, HALLS_SIZE cells (613, dungeon's side).
static func sample_castle_halls() -> Dictionary:
	var rows := _blank_rows(HALLS_SIZE)
	_lay_anchors(rows, HALLS_ANCHORS)
	var markers := {HALLS_LINK_UP: "link", HALLS_START: "start", HALLS_CART: "cart"}
	for chest: Vector2i in HALLS_CHESTS:
		markers[chest] = "chest"
	for torch: Vector2i in HALLS_TORCHES:
		markers[torch] = "torch"
	for crate: Vector2i in HALLS_CRATES:
		markers[crate] = "crate"
	var layout := Level.image_from_rows(_lines(rows), markers)
	var pillars: Array = []
	for pillar in HALLS_PILLARS:
		pillars.append({"slot": "building.crypt_pillar", "at": [pillar.position.x, pillar.position.y], "variant": 2})  # The dwarven band (art-kit's variant 2).
	# The forge against the south wall, its front north into the room, the stand cell before its anvils; the rack east of it (613 amended).
	var buildings: Array = [{"slot": "building.dwarven_forge", "at": [HALLS_FORGE.position.x, HALLS_FORGE.position.y], "facing": [0, -1]},
		{"slot": "building.weapon_rack", "at": [HALLS_RACK.x, HALLS_RACK.y], "facing": [0, -1]}]
	buildings.append_array(pillars)
	var config := {"name": "The Dwarven Halls", "outdoor": false, "depth": 1, "walls": "stone", "floors": "stone",
		"buildings": buildings,
		"decor": HALLS_GUARDS.duplicate(true),
		"starts": [[HALLS_START.x, HALLS_START.y]],
		"spawn_points": {"from_castle": [HALLS_FROM_CASTLE.x, HALLS_FROM_CASTLE.y]},
		"links": [{"at": [HALLS_LINK_UP.x, HALLS_LINK_UP.y], "to_map": "castle", "to_spawn": "from_halls"}],
		"places": {"dwarven_forge": {"at": [HALLS_STAND.x, HALLS_STAND.y], "kind": "refuge", "where": "castle_dungeon", "radius": 3,
			"name": "the great dwarven forge"}},  # The sought smith's refuge (613): maps' kind and where.
		"entities": [],
		"regenerate": {"generator": "labyrinth", "style": "dwarven", "ways": 5, "every_days": 3, "anchors": HALLS_ANCHORS,
			"entrance": "stair_foot", "rooms": {"count": [8, 11], "size": [[8, 7], [16, 12]]}, "loops": 0.2,
			"monsters": {"imp": 5, "brute": 1}, "chests": 3},  # Enemy-ai's first count: the brute holds a post, the imps wander.
		"respawn_s": {"imp": 600, "brute": 600}}
	return {"layout": layout, "config": config}


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
	if style == "castle_halls":
		return sample_castle_halls()
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
