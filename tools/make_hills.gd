extends Node
## Writes levels/hills, a showcase of the ground's relief (decision 525;
## before it, of whole levels: 358), and its link from the wilds' east edge:
##   Godot --headless --path . res://tools/make_hills.tscn
## Rebuilt bigger in layout A's step 3 (decision 756; Jeff: "hills and forest
## both bigger than the demos"): 224 x 224 east of the wilds (world (256,
## 16), in world_plane.json, edited by hand), the link on its west edge
## across from the wilds' (239, 128).
## (a scene, not a --script run: saving parses the level, which needs the
## autoloads).
##
## 224 x 224 cells under the sky, its edge an uneven band of forest, its
## ground in metres (relief.png, laid by Relief.lay):
## - two valleys winding north to south, west of the middle and east of
##   it, their floors falling to the south, each with its river (2 to 3
##   wide) looping across its floor (Relief.lay "rivers", decision 559):
##   the west one crossed by a ford and by the road's bridge, the east one
##   by a ford;
## - hills rolling 2 m either way over 70 cells, and two escarpments
##   (Relief.lay "escarpments", 525 amended (2); Jeff: "big ledge with
##   slope looks quite good"): to the west one running north to south, a
##   3 m face east over the valley and a long walkable slope up to it from
##   the west, a way up through its face, its highest ground crowned with
##   trees (void); south-east of the valley one 2.5 m high facing north
##   to the plateau's foot, so the valley has a shape from both sides;
## - to the east, a plateau 6 m up, its west side a sheer cliff (the map's
##   one), bare dirt along its rim, its south side falling away as a long
##   walkable spur: the way up;
## - flanks mostly 0.3 m a step, the full walkable 0.4 in bands, and the
##   ground's kinds by its slope (Relief.lay "kinds", 525 amended): bare
##   dirt on the steep bands, the crests and the banks, grass elsewhere, no
##   stone on the slopes (the stone ground draws as paving; the cliff's
##   face is the rock);
## - a few boulders and crates by the rim to push off (the low wall on the
##   valley floor below the cliff went in 776: Jeff, "the lone wall that
##   doesn't make sense");
## - its rivers streams, waded anywhere (776; Jeff: "the river is more like
##   a stream and should be fordable anywhere"): every water cell a ford
##   but each fall's pool, their banks graded to a walk (_wade); the bridge
##   and the old fords still the dry crossings;
## - starts on a levelled pad by the link to the wilds (west edge), the
##   road from it down through the west escarpment's way, over the bridge
##   and on east toward the east valley's ford;
## - the faces (the escarpments', the plateau's cliff) along curves that
##   wander WANDER cells either way of their lines, and level.json's
##   "ledges" traced from them (decision 585: MapDoc.save traces them).
## - the sought's refuges (613 amended), two of them herders' holdings
##   (640, maps' side): a hut and a fold on a levelled pad (HERDERS).
## No monsters, no buildings but the bridge and the herders'. The same seed
## makes the same map.

const SIZE := Vector2i(224, 224)
const SEED := 525
const FOLDER := "res://levels/hills/"
const WILDS := "res://levels/wilds/"
## The wilds' end of the link (maps-80; 743: its east edge): the land's last
## cell on row 128, its arrival two cells in.
const WILDS_LINK := Vector2i(239, 128)
const WILDS_ARRIVAL := Vector2i(237, 128)
## The link's row on this map's west edge (world row 128: the hills' origin
## is at world y 16).
const LINK_ROW := 112
## The plateau: its cliff face at this column, north of row FOOT, PLATEAU_WIDE
## across; how far in from the face its top is rock; how high it stands
## (the 96-cell hills' plateau, 106 cells east).
const CLIFF_X := 168
const PLATEAU_WIDE := 56
const FOOT := 72
const RIM := 4
const PLATEAU_HEIGHT := 6.0
## The ground's middle height, and how it leans (metres a cell, north up).
const BASE := 8.0
const TILT := Vector2.ZERO
## The valleys' lines, west and east of the middle.
const VALLEY: Array[Vector2i] = [Vector2i(80, 0), Vector2i(72, 60), Vector2i(86, 130), Vector2i(76, 223)]
## The east one, its plateau and fall are the 96-cell hills' (525, 570) moved
## 106 cells east, as they were measured to work: the valley's held floor
## near the cliff's foot where the fall comes off it (ground left between
## the two is eased up toward the fall's lip and the face sinks to a step).
const EAST_VALLEY: Array[Vector2i] = [Vector2i(152, 0), Vector2i(148, 30), Vector2i(153, 60), Vector2i(150, 95), Vector2i(140, 150), Vector2i(148, 223)]
## The escarpments: their lines, which way their faces look, how high.
const WEST_SCARP: Array[Vector2i] = [Vector2i(42, 10), Vector2i(36, 80), Vector2i(44, 150), Vector2i(38, 214)]
const SOUTH_SCARP: Array[Vector2i] = [Vector2i(156, 124), Vector2i(212, 136)]
## Between the valleys, to the south: a third, facing north as the south one.
const MID_SCARP: Array[Vector2i] = [Vector2i(92, 162), Vector2i(132, 172)]
const SCARP_HEIGHT := 3.0
## How far the escarpments' and the plateau's faces wander either way of
## their lines (585: smooth, off the cells' lines).
const WANDER := 1.5
## Where the plateau's face is still: the fall's lip, so the fall lands
## below its line, its pool whole.
const FALL_LIP := Vector2i(168, 15)
## The faces' wander seeds (added to SEED's) tried in turn, each with the
## west river's loop seeds (added to RIVER_SEED's): the first pair whose
## traced ledges keep within LEDGE_FIT of the cliff edges (level_test's
## bound is 0.45: 745's lesson) and whose every floor cell is walked to from
## the link is kept.
const WANDER_SEEDS: Array[int] = [0, 1, 2, 3, 4, 5]
const WEST_RIVER_SEEDS: Array[int] = [1, 2, 3]
const LEDGE_FIT := 0.42
## The most floor cells left cut off that are laid as scree (the slots the
## rivers' kept banks and the plateau's foot leave); more is a seed's miss.
const SCREE_MOST := 12
## Where along the west escarpment its way up is (the road goes up it):
## about row LINK_ROW.
const WEST_WAY := 0.5
## The road: its width, and where it ends past the bridge and the east
## valley's ford (the coordinator, 11-01: "it stops dead ... have it lead
## somewhere"): at the foot of the plateau's south spur, the way up (the
## open cell nearest).
## A little over the bridge's two rows: laid along its second row, a road
## exactly 2 wide leaves the first row's cells on its edge, not on it
## (Curves.cells takes a cell nearer than half the width).
const ROAD_WIDTH := 2.2
const ROAD_END := Vector2i(176, 88)
## The rivers down the valleys (Relief.lay "rivers", decision 559; Jeff: "a
## meandering stream not a straight line"): their width, wandering
## between the two.
const RIVER_WIDTH: Array[float] = [1.6, 3.2]
## Their loops' length and swing either way, in cells, and how unevenly (Relief's loop_vary, swing_vary, swing_reach; the
## coordinator, 11-01: like sine waves, "the same size at the same spacing
## all the way down"): straight reaches and tight loops, the swing's wander
## a few loops long, eased in over a whole loop by the map's edge; the east
## river's loops shorter and its own, so the two don't mirror.
const WEST_RIVER := {"wavelength": 30.0, "amplitude": 7.5, "loop_vary": 0.5, "swing_vary": 0.75, "swing_reach": 3.0, "ease": 1.0}
const EAST_RIVER := {"wavelength": 22.0, "amplitude": 5.5, "loop_vary": 0.5, "swing_vary": 0.7, "swing_reach": 2.5, "ease": 1.0}
## A valley's floor either side of its line, held as laid, the river's
## loops on it (wider reaches into the escarpments' feet and flattens their
## faces).
const RIVER_FLOOR := 9.0
## The fall's stream (570): off the plateau's top west over its cliff (6 m)
## into a pool at its foot, then down to the east valley's river, its line
## ending in the river's water (so the way on from it is the river's).
## Its head well inside the plateau, so its top joins round it (a head by
## the map's edge fenced the strip north of it off).
const FALL_STREAM: Array[Vector2i] = [Vector2i(200, 17), Vector2i(188, 14), Vector2i(176, 15), Vector2i(160, 15), Vector2i(151, 16)]
## The rivers' loops' seeds (added to SEED's): the east one's the 96-cell
## hills' river's, so its loops lie as they did and the fall's stream ends in
## its water (a stream ending on dry ground left its banks standing over the
## valley's flank, the face sunk to a step: measured); the west one's that
## plus each of WEST_RIVER_SEEDS in turn.
const RIVER_SEED := 5
## The rows the fords and the bridge cross their streams nearest to (the
## nearest each runs through, the bridge at least 7 rows from the west
## ford), each within its valley's columns (x from, x to).
const FORD_ROW := 60
const BRIDGE_ROW := 112
const EAST_FORD_ROW := 112
## And one in the north, into the low ground between the east river, the
## cliff and the fall's stream, closed in on its other sides (the fall's
## ford comes out on its south bank's foot, under the river's raised bank).
const EAST_NORTH_FORD_ROW := 8
const WEST_COLUMNS := Vector2i(50, 112)
const EAST_COLUMNS := Vector2i(118, 166)
## The fords' banks are walked to over this many rows either side of them
## (the stream's banks further off kept as laid).
const FORD_FREE := 4
## The streams waded (776): each fall's pool, water within FALL_POOL of its
## cell, stays deep; a bank higher than WADE_RISE over its water is brought
## down to it, and the ground behind it eased down WADE_RISE a step, over
## WADE_RINGS rings at most, where that bank stands under WADE_MOST over its
## water (a deeper cutting, a fall's gorge, is left a bank).
## Filling the hills, phase 1 (777; Jeff: "points of interest, road side
## camps to rest at ... ground items that could be picked up"; maps' plan,
## C:/dev/review/lands/fill_hills): side tracks (the safe-paths fixes, dirt
## road curves TRACK_WIDTH wide) from the road to each refuge, by their
## places' cells, each from the road cell nearest its junction; two rest
## camps (649's camp kind, small, on a levelled pad; a "rest" place at its
## fire); forage patches (level.json "forage") about 12 s of walking apart.
const TRACK_WIDTH := 1.4
const TRACKS := [{"to": "herders_hut", "from": Vector2i(20, 112)}, {"to": "hill_cave", "from": Vector2i(50, 111)},
	{"to": "hill_shieling", "from": ROAD_END}]
const CAMPS: Array[Dictionary] = [
	{"key": "bridge_camp", "name": "the camp by the bridge", "at": Vector2i(88, 116), "facing": Vector2i(0, -1)},
	{"key": "spur_camp", "name": "the camp under the spur", "at": Vector2i(177, 95), "facing": Vector2i(-1, 0)}]
const CAMP_SIZE := 5
## Hollowfell's mouth (790, dungeon's mine below the plateau): a link at the
## face's foot opening west into the hills, its arrival two cells out, and
## the workings place between them, held by the goblins in it; the ground
## before it levelled (HOLLOWFELL_PAD).
const HOLLOWFELL := {"at": Vector2i(167, 58), "open": Vector2i(-1, 0), "to_map": "hollowfell",
	"place": "hollowfell", "name": "Hollowfell", "holder": "goblins"}
const HOLLOWFELL_PAD := Rect2i(164, 56, 4, 5)
## The apex lairs' mouths here (enemy-ai's lair rule; the coordinator's
## fill_forest plan, phase B): each a link cell at "at" into its own small
## level, "open" the side its trampled ground lies on (toward the road);
## a hill of rock LAIR_HILL behind it (terrain's cue draws a hillock and an
## arch over it, the facing coming out into the hill), dirt LAIR_TRAMPLED
## in front, and the lair's "from_<lair>" spawn two cells out.
const LAIRS: Array[Dictionary] = [
	{"to_map": "bear_cave", "at": Vector2i(117, 102), "open": Vector2i(0, 1), "cue": "cave", "closed": true}]
const LAIR_HILL := Vector2i(7, 5)
const LAIR_TRAMPLED := 1
## Each lair's bank (the coordinator: "the cave is a hole in the face of a
## bank"): the hill's rock cells stand LAIR_RISE metres over the link's
## ground (terrain draws the hill on them: the face, a broken rim, grass
## over the top); being no floor they are left out of the lay, so no face
## or capped slope runs past them. Round them the grass rises in a knoll
## (LAIR_KNOLL: metres at its crest, cells out; the crest at LAIR_KNOLL_AT
## from the mouth), kept low before
## the mouth by the levelled front, and held grass LAIR_GRASS cells round
## the hill (the slope's dirt otherwise rings it).
const LAIR_RISE := 3.1
const LAIR_KNOLL := Vector2(4.0, 12.0)
## Where the crest stands from the mouth: cells back, and across (+x for a
## south-facing mouth; leaning it east lost the west shoulder for little).
const LAIR_KNOLL_AT := Vector2i(10, 0)
const LAIR_GRASS := 10
## Each patch {at, kinds}: its setting's kinds (items' 777 rows; "herbs" grows
## meanwhile, a kind Items lacks is skipped by Forage).
const PATCHES: Array[Dictionary] = [
	{"at": Vector2i(31, 115), "kinds": ["flint", "feathers"]}, {"at": Vector2i(70, 107), "kinds": ["reeds", "herbs"]},
	{"at": Vector2i(115, 116), "kinds": ["berries", "herbs"]}, {"at": Vector2i(152, 108), "kinds": ["reeds", "herbs"]},
	{"at": Vector2i(14, 85), "kinds": ["berries", "herbs"]}, {"at": Vector2i(45, 140), "kinds": ["berries", "mushrooms", "herbs"]},
	{"at": Vector2i(172, 64), "kinds": ["flint", "feathers"]}]
const PATCH_RADIUS := 4
## Phase 2 (778): the landmarks, roadside sights and story pieces, bare (no
## words: lore's facts wait on Jeff). Each {key, at: its planned cell (a
## building's footprint's top-left), and slot (a building) or decor (a
## prop.<kind> lying faced), facing: a side, or ROADWARD to face the nearest
## path cell}. Laid on the walkable cell nearest the planned one whose
## footprint is grass or plain dirt, off every path by SIGHT_OFF_PATH and
## clear of the others; the multi-cell ones' planned ground levelled
## (keep_flat, _sight_pads).
const ROADWARD := Vector2i.ZERO
const SIGHTS: Array[Dictionary] = [
	{"key": "watchtower", "slot": "building.tower_ruin", "at": Vector2i(186, 18), "facing": Vector2i(-1, 0)},
	{"key": "great_oak", "slot": "building.great_tree", "at": Vector2i(111, 159), "facing": Vector2i(0, -1)},
	{"key": "standing_stone", "slot": "building.standing_stone", "at": Vector2i(199, 70), "facing": Vector2i(-1, 0)},
	{"key": "milestone_west", "slot": "building.milestone", "at": Vector2i(43, 110), "facing": ROADWARD},
	{"key": "milestone_east", "slot": "building.milestone", "at": Vector2i(140, 108), "facing": ROADWARD},
	{"key": "broken_cart", "decor": "broken_cart", "at": Vector2i(124, 115), "facing": ROADWARD},
	{"key": "shrine", "slot": "building.wayside_shrine", "at": Vector2i(160, 102), "facing": ROADWARD},
	{"key": "woodpile", "slot": "building.woodpile", "at": Vector2i(173, 87), "facing": ROADWARD},
	{"key": "hunters_blind", "slot": "building.hunters_blind", "at": Vector2i(52, 156), "facing": Vector2i(1, 0)},
	{"key": "waystone_hut", "slot": "building.waystone", "at": Vector2i(20, 110), "facing": ROADWARD},
	{"key": "waystone_cave", "slot": "building.waystone", "at": Vector2i(51, 114), "facing": ROADWARD},
	{"key": "dead_traveller", "decor": "fallen_guard", "at": Vector2i(45, 69), "facing": Vector2i(1, 0)},
	{"key": "cairn", "slot": "building.cairn", "at": Vector2i(114, 81), "facing": Vector2i(0, 1)},
	{"key": "rusted_gear", "decor": "rusted_gear", "at": Vector2i(21, 153), "facing": Vector2i(0, 1)},
	{"key": "grave", "slot": "building.grave", "at": Vector2i(75, 150), "facing": Vector2i(0, 1)},
	{"key": "lean_to", "slot": "building.lean_to", "at": Vector2i(146, 125), "facing": Vector2i(0, 1), "cold_fire": true}]
## How far a sight keeps off a path (road or track cell), and from another.
const SIGHT_OFF_PATH := 1
const SIGHT_REACH := 6
const FALL_POOL := 2.5
const WADE_RISE := 0.42
const WADE_RINGS := 4
const WADE_MOST := 1.6
## The sought's refuges here (613 amended: one place a story, its key the
## story's tag), each {at, name}.
const REFUGES := {"hill_cave": {"at": Vector2i(52, 176), "name": "a hill cave"}}
## The herders' holdings (640, maps' side; Jeff: "herders exist as people"):
## refuges economy's herder.places names, each a building.fold (6 x 6, its
## gate the front row's middle two edges, open) whose gate looks across a
## 2-cell way at a building.hut's door, both on one levelled pad, the
## place's cell the way's cell before the door. Each {key, name, fold (its
## rect), gate (the way it opens)}.
const HERDERS: Array[Dictionary] = [
	{"key": "herders_hut", "name": "the herder's hut", "fold": Rect2i(16, 44, 6, 6), "gate": Vector2i(0, 1)},
	{"key": "hill_shieling", "name": "a shieling high on the hill", "fold": Rect2i(186, 40, 6, 6), "gate": Vector2i(1, 0)}]
## The way between a fold's gate and its hut's door, in cells.
const HERDER_WAY := 2

const CONFIG := {"name": "The Hills", "outdoor": true, "zone": "outdoors", "region": "town_lands", "border": "forest", "walls": "stone", "floors": "cave"}
var map := LevelMap.new(SIZE)
var config: Dictionary = {}
var entries: Array = []
## The ford's row, once laid (the bridge keeps away from it).
var _ford_row := -100
## The east valley's ford (EAST_FORD_ROW), once laid: the road crosses it.
var _east_ford: Array[Vector2i] = []
## The escarpments' faces as laid (edge keys), kept by the ford's limiting.
var _faces: Dictionary = {}
## What a build failed to lay (a ford, the road): a seed's miss.
var _missed: Array[String] = []
## The road's cells, once laid (777: the tracks leave from it).
var _road_cells: Array[Vector2i] = []
## The tracks' cells (777), for the sights to keep off (778).
var _track_cells: Dictionary = {}


func _ready() -> void:
	for wander_seed in WANDER_SEEDS:
		for river_seed in WEST_RIVER_SEEDS:
			_build(wander_seed, river_seed)
			var cut := _cut_off()
			if not cut.is_empty() and cut.size() <= SCREE_MOST:
				# One-cell slots left under a raised bank or a face's foot,
				# walled in: scree, no floor.
				for at: Vector2i in cut:
					map.set_cell(at, "rock")
				print("[hills] scree in the cut-off slots %s" % [cut])
				_save()
				cut = _cut_off()
			var miss := _ledge_miss()
			print("[hills] wander seed %d, west river seed %d: ledges within %.2f of the cliff edges, %d floor cells cut off %s" % [wander_seed, river_seed, miss, cut.size(), _span(cut)])
			if miss <= LEDGE_FIT and cut.is_empty() and _missed.is_empty():
				_link_wilds()
				get_tree().quit()
				return
	push_error("[hills] no seeds fit; the last kept")
	get_tree().quit()


func _build(wander_seed: int, river_seed: int) -> void:
	map = LevelMap.new(SIZE)
	config = CONFIG.duplicate(true)
	entries = []
	_ford_row = -100
	_east_ford = []
	_faces = {}
	_missed = []
	var edge := _noise(SEED, 0.05)
	# The land: in from the border by 3 to 9 cells, unevenly; grass and dirt.
	for y in SIZE.y:
		for x in SIZE.x:
			var inward := mini(mini(x, y), mini(SIZE.x - 1 - x, SIZE.y - 1 - y))
			if inward > 3 + 6.0 * (edge.get_noise_2d(x, y) * 0.5 + 0.5):
				map.set_cell(Vector2i(x, y), "grass")
	var arrival := _link()
	_lair_rock()
	var east_river := EAST_RIVER.merged({"line": EAST_VALLEY, "width": RIVER_WIDTH, "seed": RIVER_SEED})
	var laid := Relief.lay(map, Rect2i(Vector2i.ZERO, SIZE), SEED, {
		"base": BASE, "amplitude": 2.0, "scale": 110.0, "octaves": 2, "tilt": TILT,
		"escarpments": [
			{"line": WEST_SCARP, "face": "east", "height": SCARP_HEIGHT, "back": 22.0, "ways": [WEST_WAY], "wander": WANDER, "wander_seed": wander_seed},
			{"line": SOUTH_SCARP, "face": "north", "height": SCARP_HEIGHT - 0.5, "back": 20.0, "ways": [0.3], "wander": WANDER, "wander_seed": wander_seed},
			{"line": MID_SCARP, "face": "north", "height": SCARP_HEIGHT - 0.5, "back": 20.0, "ways": [0.5], "wander": WANDER, "wander_seed": wander_seed}],
		"ridges": _lair_knolls(),
		"slope": 0.3, "steep_bands": 0.3, "rock_step": Relief.MAX_M, "dirt_step": 0.33,
		"valleys": [VALLEY, EAST_VALLEY], "valley_depth": 4.5, "valley_floor": RIVER_FLOOR, "valley_fall": 5.0, "valley_width": 30.0, "kinds": true, "min_flow": 30,
		"plateaus": [{"rect": Rect2i(CLIFF_X, 0, PLATEAU_WIDE, FOOT), "height": PLATEAU_HEIGHT, "faces": ["west"], "spur": 0.25, "wander": 0.0, "still": [FALL_LIP]}],
		"keep_flat": [Rect2i(arrival - Vector2i(2, 3), Vector2i(4, 7))] + _herder_pads() + _camp_pads() + _sight_pads() + [HOLLOWFELL_PAD] + _lair_pads(),
		"streams": 0, "keep_clear": {},
		"rivers": [WEST_RIVER.merged({"line": VALLEY, "width": RIVER_WIDTH, "seed": RIVER_SEED + river_seed}),
			east_river,
			{"line": _fall_line(east_river), "wavelength": 14.0, "amplitude": 2.0, "width": [1.4, 2.2]}]})
	map.relief = PackedFloat32Array()
	map.relief.resize(SIZE.x * SIZE.y)
	var filled := PackedByteArray()
	filled.resize(SIZE.x * SIZE.y)
	for at: Vector2i in laid["relief"]:
		map.relief[at.y * SIZE.x + at.x] = laid["relief"][at]
		filled[at.y * SIZE.x + at.x] = 1
	# The forest round the land stands at its edge's height.
	LevelMap._fill_gaps(map.relief, filled, SIZE)
	for at: Vector2i in laid["cells"]:
		map.set_cell(at, laid["cells"][at])
	_lair_ground()
	# The river is its curve (decision 559): Level lays its cells and its
	# "streams" path from it on load.
	config["waters"] = laid["waters"].map(func(water: Dictionary) -> Dictionary:
		return {"points": Curves.to_json(water["points"], water["widths"])})
	var water := {}
	for at: Vector2i in laid["cells"]:
		if laid["cells"][at] == "water":
			water[at] = true
	_faces = laid["faces"]
	if laid["streams"].size() > 2:
		_fall_ford(laid["streams"][2], water)
	_ford(water, FORD_ROW, WEST_COLUMNS)
	_ford(water, EAST_FORD_ROW, EAST_COLUMNS)
	_ford(water, EAST_NORTH_FORD_ROW, EAST_COLUMNS)
	_bridge(water)
	_rock()
	_knoll()
	_road(arrival)
	_places()
	_tracks()
	_camps()
	_hollowfell()
	_lairs()
	_patches()
	_wade(laid["falls"])
	_sights()
	# Boulders and crates by the rim, to push off.
	for at in [Vector2i(CLIFF_X + 1, 24), Vector2i(CLIFF_X + 2, 40)]:
		map.set_cell(at, "boulder")
	for at in [Vector2i(CLIFF_X + 1, 34), Vector2i(CLIFF_X + 1, 36)]:
		map.set_cell(at, "crate")
	_soften()
	_save()


## The fall's stream's line: FALL_STREAM, its last point moved onto the east
## river's curve where that runs nearest its row (Relief.lay lays the east
## river second: its seed SEED + 10 + 1 + its own), so the stream ends in the
## river's water however the river loops.
func _fall_line(east_river: Dictionary) -> Array[Vector2i]:
	var line: Array[Vector2i] = FALL_STREAM.duplicate()
	var curve := Relief.river_curve(east_river, SEED + 10 + 1 + int(east_river["seed"]))
	var end := line[-1]
	var best := INF
	for point: Vector2 in curve["points"]:
		var d := absf(point.y - float(end.y)) + 0.25 * absf(point.x - float(end.x))
		if point.x < float(line[-2].x) - 2.0 and d < best:
			best = d
			line[-1] = Vector2i(point.round())
	return line


## The level written (its relief from the map's) and its cliffs said.
func _save() -> void:
	var doc := MapDoc.open(FOLDER, SIZE)
	doc.map = map
	doc.config = config
	doc.config_dirty = true
	doc.relief_dirty = true
	doc.heights_dirty = false
	doc.had_heights = false
	doc.save()
	print("[hills] " + doc.report)
	for old in ["height.png", "height.png.import"]:
		if FileAccess.file_exists(FOLDER + old):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(FOLDER + old))
	_say_cliffs()


## How far the saved level's ledges stray from its cliff edges, or its cliff
## edges from its ledges, at worst: level_test's measure (the walked and wet
## cells as Level loads them, a cliff between two of a kind).
func _ledge_miss() -> float:
	var terrain: Dictionary = Level.load_level("hills")["terrain"]
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
	var worst := 0.0
	for ledge: Dictionary in terrain["ledges"]:
		for point: Vector2 in ledge["curve"]["points"]:
			var near := INF
			for edge: Array in edges:
				near = minf(near, point.distance_to(Geometry2D.get_closest_point_to_segment(point, edge[0], edge[1])))
			worst = maxf(worst, near)
	for edge: Array in edges:
		var middle: Vector2 = (edge[0] + edge[1]) / 2.0
		var near := INF
		for ledge: Dictionary in terrain["ledges"]:
			var points: PackedVector2Array = ledge["curve"]["points"]
			for i in range(1, points.size()):
				near = minf(near, middle.distance_to(Geometry2D.get_closest_point_to_segment(middle, points[i - 1], points[i])))
		worst = maxf(worst, near)
	return worst


## Where [param cells] lie: their bounding box, or "" for none.
static func _span(cells: Array) -> String:
	if cells.is_empty():
		return ""
	var low: Vector2i = cells[0]
	var high: Vector2i = cells[0]
	for cell: Vector2i in cells:
		low = low.min(cell)
		high = high.max(cell)
	return "(%s to %s)" % [low, high]


## The saved level's floor cells not walked to from the link's arrival:
## relief_test's measure (WorldRoutes' flood over its relief, edges and
## stairs).
func _cut_off() -> Array:
	var level := Level.load_level("hills")
	var terrain: Dictionary = level["terrain"]
	var size: Vector2i = terrain["relief_size"]
	var floor: Dictionary = {}
	for cell: Vector2i in terrain["floor"]:
		floor[cell] = true
	var area := {"relief": Level.walk_relief(terrain), "relief_size": size, "stairs": terrain["stairs"], "heights": {}, "edges": terrain["edges"], "floor": floor, "size": size}
	var reached := PackedFloat32Array()
	reached.resize(size.x * size.y)
	reached.fill(-1.0)
	WorldRoutes._flood(area, level["spawn_points"]["from_wilds"], {}, reached)
	return floor.keys().filter(func(cell: Vector2i) -> bool: return reached[cell.y * size.x + cell.x] < 0.0)


## A ford: the stream's cells on the row nearest [param row] it crosses
## within [param columns] (x from, x to: one valley's), its banks set a walk
## over its water and the ground round them brought down to them
## (Relief._limit), the stream's other banks kept.
func _ford(water: Dictionary, row: int, columns: Vector2i) -> void:
	var across := _crossing(water, row, columns, true)
	if across.is_empty():
		_missed.append("no ford near row")
		push_error("[hills] no ford near row %d" % row)
		return
	for at in across:
		map.set_cell(at, "ford")
	if columns == WEST_COLUMNS:
		_ford_row = across[0].y
	if row == EAST_FORD_ROW and columns == EAST_COLUMNS:
		_east_ford = across
	print("[hills] a ford at %s" % [across])
	var surface := map.relief_at(across[0])
	var heights := {}
	var fixed := {}
	var wet := {}
	# The plateau's top: its north-east corner stands on it.
	var top := map.relief_at(Vector2i(CLIFF_X + PLATEAU_WIDE - 8, 4))
	for at: Vector2i in map.cells:
		if map.walkable(at) or map.cell(at) == "water":
			heights[at] = map.relief_at(at)
			# The foot the plateau's face wanders over held as laid (585: the
			# face is no one column to keep); its top eases to its spur.
			if at.x >= CLIFF_X and at.y < FOOT and heights[at] < top - PLATEAU_HEIGHT / 2.0:
				fixed[at] = true
	for at: Vector2i in water:
		fixed[at] = true
		if map.cell(at) == "water":
			wet[at] = true
		for step: Vector2i in Relief.FOUR:
			if heights.has(at + step) and not water.has(at + step) and (absi(at.y - across[0].y) > FORD_FREE or absi(at.x - across[0].x) > 12):
				fixed[at + step] = true
	for bank: Vector2i in [across[0] - Vector2i(1, 0), across[across.size() - 1] + Vector2i(1, 0)]:
		heights[bank] = surface + 0.3
		fixed[bank] = true
	Relief._limit(heights, fixed, wet, Relief.LAY_SLOPE, _faces)
	for at: Vector2i in heights:
		map.set_relief(at, heights[at])


## A ford across the fall's stream (570) in the valley below the cliff:
## the first column west of the cliff's foot where the stream's water runs
## one or two cells across with walkable ground either side, so the ground
## between the river, the stream and the cliff is still walked to.
func _fall_ford(path: Array, water: Dictionary) -> void:
	for cell: Vector2i in path:
		# Clear of the pool below the fall, short of the river.
		if cell.x >= CLIFF_X - 5 or cell.x < CLIFF_X - 9:
			continue
		var across: Array[Vector2i] = []
		for y in range(cell.y - 2, cell.y + 3):
			if water.has(Vector2i(cell.x, y)):
				across.append(Vector2i(cell.x, y))
		if across.is_empty() or across.size() > 2 or across[-1].y - across[0].y != across.size() - 1:
			continue
		if not map.walkable(across[0] - Vector2i(0, 1)) or not map.walkable(across[-1] + Vector2i(0, 1)):
			continue
		for at in across:
			map.set_cell(at, "ford")
		# Its banks a walk over it, the ground near brought down to them.
		var surface := map.relief_at(across[0])
		var heights := {}
		var fixed := {}
		var wet := {}
		for at: Vector2i in map.cells:
			if map.walkable(at) or map.cell(at) == "water":
				heights[at] = map.relief_at(at)
				if at.distance_to(across[0]) > 5.0 or map.cell(at) in ["water", "ford"]:
					fixed[at] = true
				if map.cell(at) == "water":
					wet[at] = true
		for bank: Vector2i in [across[0] - Vector2i(0, 1), across[-1] + Vector2i(0, 1)]:
			heights[bank] = surface + 0.3
			fixed[bank] = true
		Relief._limit(heights, fixed, wet, Relief.LAY_SLOPE, _faces)
		for at: Vector2i in heights:
			map.set_relief(at, heights[at])
		print("[hills] the fall's stream forded at %s" % [across])
		return
	_missed.append("no ford over the fall's stream")
	push_error("[hills] no ford over the fall's stream")


## The bridge over the stream on the row nearest BRIDGE_ROW: its banks
## levelled at the higher of them (a bridge's banks are of one height).
func _bridge(water: Dictionary) -> void:
	var across := _crossing(water, BRIDGE_ROW, WEST_COLUMNS, false, 2)
	if across.is_empty():
		return
	var west := across[0]
	var east := across[across.size() - 1]
	var banks: Array[Vector2i] = [west - Vector2i(1, 0), east + Vector2i(1, 0), west + Vector2i(-1, 1), east + Vector2i(1, 1)]
	var top := maxf(maxf(map.relief_at(banks[0]), map.relief_at(banks[1])), maxf(map.relief_at(banks[2]), map.relief_at(banks[3])))
	for bank in banks:
		map.set_relief(bank, top)
	config["buildings"] = [{"slot": "bridge", "at": [west.x, west.y], "facing": [1, 0], "length": across.size(), "width": 2}]


## The water cells of the row nearest [param row] that the stream crosses
## within [param columns] (x from, x to) with water only, west to east
## (where it runs [param straight] and level, for a ford), the same cells
## water on the [param rows] - 1 rows south of it too (a 2-wide bridge's).
func _crossing(water: Dictionary, row: int, columns: Vector2i, straight := false, rows := 1) -> Array[Vector2i]:
	for offset in range(0, SIZE.y):
		for y in [row + offset, row - offset]:
			if absi(y - _ford_row) <= 6 and columns == WEST_COLUMNS:
				continue
			var cells: Array[Vector2i] = []
			for x in range(columns.x, columns.y + 1):
				if water.has(Vector2i(x, y)) and map.cell(Vector2i(x, y)) == "water":
					cells.append(Vector2i(x, y))
			if cells.size() >= 1 and cells.size() <= 3 and cells[cells.size() - 1].x - cells[0].x == cells.size() - 1 					and (not straight or _straight(water, cells)) and _wide(water, cells, rows):
				return cells
	return []


## Whether [param cells] are water on the [param rows] - 1 rows south of
## them too, and only them on each such row of the crossing's span.
func _wide(water: Dictionary, cells: Array[Vector2i], rows: int) -> bool:
	for k in range(1, rows):
		for cell in cells:
			if not water.has(cell + Vector2i(0, k)) or map.cell(cell + Vector2i(0, k)) != "water":
				return false
		for side: Vector2i in [cells[0] - Vector2i(1, -k), cells[-1] + Vector2i(1, k)]:
			if water.has(side):
				return false
	if rows < 2:
		return true
	# A bridge's: its ends dry a row past it either way and two cells out, so
	# the road comes onto it at its full width (a river bending under one end
	# narrowed it off the bridge's corner: measured).
	for k in range(-1, rows + 1):
		for out in [1, 2]:
			if water.has(cells[0] + Vector2i(-out, k)) or water.has(cells[-1] + Vector2i(out, k)):
				return false
	return true


## Whether the stream runs straight through [param cells] (water on the
## same columns a row either way) and nearly level (within 0.25 m of
## them), so a crossing's banks can stand a walk over it and a lip over the
## water beside them.
func _straight(water: Dictionary, cells: Array[Vector2i]) -> bool:
	var surface := map.relief_at(cells[0])
	for cell in cells:
		for side: Vector2i in [Vector2i(0, -1), Vector2i(0, 1)]:
			if not water.has(cell + side) or absf(map.relief_at(cell + side) - surface) > 0.25:
				return false
	return true


## Bare dirt along the plateau's rim, in from its face (stone ground drew
## as paving on a cliff top: the face's own rock is the rock).
func _rock() -> void:
	for y in FOOT:
		for x in range(CLIFF_X, CLIFF_X + RIM):
			var at := Vector2i(x, y)
			if map.cell(at) == "grass":
				map.set_cell(at, "dirt")


## The highest ground west of the valley (the west escarpment's crest),
## crowned with trees.
func _knoll() -> void:
	var top := Vector2i(-1, -1)
	for at: Vector2i in map.cells:
		if at.x < 36 and at.y > 60 and at.y < 160 and map.cell(at) in ["grass", "dirt"] and (top.x < 0 or map.relief_at(at) > map.relief_at(top)):
			top = at
	for cell in _disc(top, 2.2):
		if map.cell(cell) in ["grass", "dirt"]:
			map.set_cell(cell, "void")


## The road (decision 563): dirt, from the link's arrival east down through
## the west escarpment's way, over the bridge, through the east valley's
## ford and on to the spur's foot (ROAD_END), laid as a curve (Relief.road),
## its cells bare dirt (the ford's kept).
func _road(arrival: Vector2i) -> void:
	if not config.has("buildings"):
		return
	var bridge: Dictionary = config["buildings"][0]
	var west := Vector2i(int(bridge["at"][0]), int(bridge["at"][1]))
	var length := int(bridge["length"])
	var crossings := {}
	for i in length:
		for row in int(bridge.get("width", 1)):
			crossings[west + Vector2i(i, row)] = true
	# A road ROAD_WIDTH wide laid through the second row covers both (make_held's, 505 amended (2)).
	west += Vector2i(0, int(bridge.get("width", 1)) - 1)
	var via: Array = [west - Vector2i(1, 0), west + Vector2i(length, 0)]
	if not _east_ford.is_empty():
		for at in _east_ford:
			crossings[at] = true
		via.append(_east_ford[0] - Vector2i(1, 0))
		via.append(_east_ford[-1] + Vector2i(1, 0))
	var beyond := ROAD_END
	var best := INF
	for y in range(ROAD_END.y - 8, ROAD_END.y + 9):
		for x in range(ROAD_END.x - 8, ROAD_END.x + 9):
			var at := Vector2i(x, y)
			if map.walkable(at) and map.cell(at) != "water" and Vector2(at).distance_to(Vector2(ROAD_END)) < best:
				best = Vector2(at).distance_to(Vector2(ROAD_END))
				beyond = at
	var laid := Relief.road(map, arrival, via, beyond, ROAD_WIDTH, crossings)
	if laid.is_empty():
		_missed.append("no way for the road")
		push_error("[hills] no way for the road")
		return
	_road_cells.clear()
	for cell: Vector2i in laid["cells"]:
		_road_cells.append(cell)
		if map.cell(cell) in ["grass", "dirt"]:
			map.set_cell(cell, "dirt")
	config["roads"] = [{"points": Curves.to_json(laid["points"], laid["widths"]), "kind": "dirt"}]
	print("[hills] the road: %d control points, %d cells" % [laid["points"].size(), laid["cells"].size()])


## The point [param fraction] of the way along the polyline [param line].
func _along(line: Array[Vector2i], fraction: float) -> Vector2:
	var total := 0.0
	for i in range(1, line.size()):
		total += Vector2(line[i]).distance_to(Vector2(line[i - 1]))
	var left := total * fraction
	for i in range(1, line.size()):
		var span := Vector2(line[i]).distance_to(Vector2(line[i - 1]))
		if left <= span:
			return Vector2(line[i - 1]).lerp(Vector2(line[i]), left / span)
		left -= span
	return Vector2(line[-1])


## A herder's hut (HERDERS): 3 x 3, HERDER_WAY cells out from the fold's
## gate, its door's cell in line with the gate's second cell.
static func _herder_hut(herder: Dictionary) -> Rect2i:
	var fold: Rect2i = herder["fold"]
	match herder["gate"]:
		Vector2i(0, 1):
			return Rect2i(fold.position.x + 2, fold.end.y + HERDER_WAY, 3, 3)
		Vector2i(0, -1):
			return Rect2i(fold.position.x + 2, fold.position.y - HERDER_WAY - 3, 3, 3)
		Vector2i(1, 0):
			return Rect2i(fold.end.x + HERDER_WAY, fold.position.y + 2, 3, 3)
	return Rect2i(fold.position.x - HERDER_WAY - 3, fold.position.y + 2, 3, 3)


## Each herder's pad: its fold, its hut and the way between.
static func _herder_pads() -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for herder in HERDERS:
		out.append((herder["fold"] as Rect2i).merge(_herder_hut(herder)))
	return out


## The refuges and the herders' holdings (HERDERS): each fold's outline a
## fence (wall edges) but its gate, each hut's walls but its door facing
## the fold, both in "buildings"; the places in "places".
func _places() -> void:
	var places := {}
	for key: String in REFUGES:
		var at: Vector2i = REFUGES[key]["at"]
		places[key] = {"at": [at.x, at.y], "kind": "refuge", "where": "hills", "radius": 3, "name": REFUGES[key]["name"]}
	for herder in HERDERS:
		var fold: Rect2i = herder["fold"]
		var gate: Vector2i = herder["gate"]
		var hut := _herder_hut(herder)
		var door := hut.position + Vector2i(1, 1) - gate  # The hut's front middle cell.
		var gates: Array[Vector3i] = []
		for i in [2, 3]:
			var cell := fold.position + (Vector2i(i, fold.size.y - 1) if gate.y > 0 else Vector2i(i, 0) if gate.y < 0
				else Vector2i(fold.size.x - 1, i) if gate.x > 0 else Vector2i(0, i))
			gates.append(Terrain.edge_key(cell, gate))
		for key in Level.blocks_outline(_cells_of(fold)):
			map.set_edge(key, "clear" if key in gates else "wall")
		for key in Level.blocks_outline(_cells_of(hut)):
			map.set_edge(key, "door" if key == Terrain.edge_key(door, -gate) else "wall")
		config["buildings"].append({"slot": "building.fold", "at": [fold.position.x, fold.position.y], "facing": [gate.x, gate.y]})
		config["buildings"].append({"slot": "building.hut", "at": [hut.position.x, hut.position.y], "facing": [-gate.x, -gate.y]})
		var stand := door - gate
		places[herder["key"]] = {"at": [stand.x, stand.y], "kind": "refuge", "where": "hills", "radius": 3, "name": herder["name"]}
	config["places"] = places


## The side tracks (777): from the road cell nearest each TRACKS "from" to
## its place's cell, by Relief.road (the road's way: walkable, no cliff, no
## water, the climb dearer), TRACK_WIDTH wide; their cells dirt, their
## curves after the road's in config "roads", so each is a safe path (763).
func _tracks() -> void:
	if not config.has("roads") or config["roads"].is_empty():
		return
	var road_cells: Array[Vector2i] = []
	for cell: Vector2i in _road_cells:
		if map.walkable(cell) and map.cell(cell) != "water":
			road_cells.append(cell)
	for track: Dictionary in TRACKS:
		var place: Dictionary = config["places"][track["to"]]
		var to := Vector2i(int(place["at"][0]), int(place["at"][1]))
		var from: Vector2i = road_cells[0]
		for cell in road_cells:
			if Vector2(cell - track["from"]).length() < Vector2(from - track["from"]).length():
				from = cell
		var laid := Relief.road(map, from, [], to, TRACK_WIDTH)
		if laid.is_empty():
			_missed.append("no track to %s" % track["to"])
			push_error("[hills] no track to %s" % track["to"])
			continue
		for cell: Vector2i in laid["cells"]:
			if map.cell(cell) in ["grass", "dirt"]:
				map.set_cell(cell, "dirt")
			_track_cells[cell] = true
		config["roads"].append({"points": Curves.to_json(laid["points"], laid["widths"]), "kind": "dirt"})
		print("[hills] a track to %s from %s: %d cells" % [track["to"], from, laid["cells"].size()])


## The rest camps' pads, levelled by Relief.lay (keep_flat).
static func _camp_pads() -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for camp in CAMPS:
		out.append(Rect2i(camp["at"], Vector2i(CAMP_SIZE, CAMP_SIZE)))
	return out


## Hollowfell's mouth (790): its link cell to the mine's "from_hills", the
## "from_hollowfell" arrival two cells out from the face, and the workings
## place on the cell between.
func _hollowfell() -> void:
	var at: Vector2i = HOLLOWFELL["at"]
	var open: Vector2i = HOLLOWFELL["open"]
	map.set_cell(at, "link")
	config["links"].append({"at": [at.x, at.y], "to_map": HOLLOWFELL["to_map"], "to_spawn": "from_hills"})
	var arrival := at + open * 2
	config["spawn_points"]["from_" + str(HOLLOWFELL["to_map"])] = [arrival.x, arrival.y]
	var middle := at + open
	config["places"][HOLLOWFELL["place"]] = {"at": [middle.x, middle.y], "kind": "workings", "radius": 3,
		"name": HOLLOWFELL["name"], "holder": HOLLOWFELL["holder"]}


## The rest camps (777): each a building {kind camp, size small} on its pad,
## and a "rest" place at its fire (Level.camp_fire), held by nobody.
func _camps() -> void:
	for camp in CAMPS:
		var at: Vector2i = camp["at"]
		var facing: Vector2i = camp["facing"]
		var building := {"kind": "camp", "size": "small", "at": [at.x, at.y], "facing": [facing.x, facing.y]}
		config["buildings"].append(building)
		var fire := Level.camp_fire({"kind": "camp", "rect": Rect2i(at, Vector2i(CAMP_SIZE, CAMP_SIZE)), "facing": facing})
		config["places"][camp["key"]] = {"at": [fire.x, fire.y], "kind": "rest", "radius": 3, "name": camp["name"]}
		for cell in _cells_of(Rect2i(at, Vector2i(CAMP_SIZE, CAMP_SIZE))):
			if map.cell(cell) == "dirt":
				map.set_cell(cell, "grass")


## The ground before each lair's mouth, levelled by Relief.lay (keep_flat,
## its one-cell apron reaching the link but not the bank's top): the
## trampled dirt's width, from a cell out to its last row.
static func _lair_pads() -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for lair in LAIRS:
		var at: Vector2i = lair["at"]
		var open: Vector2i = lair["open"]
		var side := Vector2i(absi(open.y), absi(open.x))
		var a: Vector2i = at + open - side * LAIR_TRAMPLED
		var b: Vector2i = at + open * 2 + side * LAIR_TRAMPLED
		out.append(Rect2i(a.min(b), (a - b).abs() + Vector2i.ONE))
	return out


## Each lair's hill laid as rock before the ground is (no floor: the lay
## leaves it out).
func _lair_rock() -> void:
	for lair in LAIRS:
		for cell in _cells_of(_lair_hill(lair)):
			map.set_cell(cell, "rock")


## Each lair's knoll: a ridge of one point LAIR_KNOLL_AT behind its
## mouth (not over the front, which it would lift with it), the levelled
## front's slope cap shaping its shoulders down toward the mouth.
static func _lair_knolls() -> Array:
	var out := []
	for lair in LAIRS:
		var at: Vector2i = lair["at"]
		var open: Vector2i = lair["open"]
		var side := Vector2i(absi(open.y), absi(open.x))
		out.append({"line": [at - open * LAIR_KNOLL_AT.x + side * LAIR_KNOLL_AT.y], "height": LAIR_KNOLL.x, "width": LAIR_KNOLL.y})
	return out


## After the lay: each hill's rock cells LAIR_RISE over its link's ground,
## and the ground round it held grass (but water).
func _lair_ground() -> void:
	for lair in LAIRS:
		var at: Vector2i = lair["at"]
		var hill := _lair_hill(lair)
		var top := map.relief[at.y * SIZE.x + at.x] + LAIR_RISE
		for cell in _cells_of(hill):
			map.relief[cell.y * SIZE.x + cell.x] = top
		for cell in _cells_of(hill.grow(LAIR_GRASS)):
			if map.cell(cell) == "dirt":
				map.set_cell(cell, "grass")


## The rock cells behind a lair's mouth: LAIR_HILL across by deep, the side
## away from "open", the mouth's column (or row) in its middle.
static func _lair_hill(lair: Dictionary) -> Rect2i:
	var at: Vector2i = lair["at"]
	var open: Vector2i = lair["open"]
	var side := Vector2i(absi(open.y), absi(open.x))
	var half := LAIR_HILL.x / 2
	var a := at - open - side * half
	var b := at - open * LAIR_HILL.y + side * half
	return Rect2i(a.min(b), (a - b).abs() + Vector2i.ONE)


## The lairs' mouths (LAIRS): rock behind, trampled dirt in front, the link
## cell, its link {at, to_map, to_spawn "from_hills", cue, closed if so} and the
## "from_<lair>" spawn two cells out.
func _lairs() -> void:
	for lair in LAIRS:
		var at: Vector2i = lair["at"]
		var open: Vector2i = lair["open"]
		for cell in _cells_of(_lair_hill(lair)):
			map.set_cell(cell, "rock")
		var side := Vector2i(absi(open.y), absi(open.x))
		for step in range(0, 3):
			for across in range(-LAIR_TRAMPLED, LAIR_TRAMPLED + 1):
				map.set_cell(at + open * step + side * across, "dirt")
		map.set_cell(at, "link")
		var spawn := at + open * 2
		var link := {"at": [at.x, at.y], "to_map": lair["to_map"], "to_spawn": "from_hills", "cue": lair["cue"]}
		if lair.get("closed", false):
			link["closed"] = true  # Sealed till its lair's rule is in (the coordinator; terrain draws a rockfall).
		config["links"].append(link)
		config["spawn_points"]["from_" + str(lair["to_map"])] = [spawn.x, spawn.y]


## The forage patches (777): level.json "forage", each PATCH_RADIUS round,
## its middle the grass cell nearest its planned one (a road, a track or a
## bank's dirt may have come to lie there).
func _patches() -> void:
	var out: Array = []
	for patch: Dictionary in PATCHES:
		var at := _nearest_grass(patch["at"])
		out.append({"at": [at.x, at.y], "radius": PATCH_RADIUS, "kinds": patch["kinds"]})
	config["forage"] = out


func _nearest_grass(from: Vector2i) -> Vector2i:
	for reach in range(0, PATCH_RADIUS + 1):
		for y in range(from.y - reach, from.y + reach + 1):
			for x in range(from.x - reach, from.x + reach + 1):
				var at := Vector2i(x, y)
				if maxi(absi(x - from.x), absi(y - from.y)) == reach and map.cell(at) == "grass":
					return at
	_missed.append("no grass near the forage patch at %s" % from)
	return from


## A sight's footprint at [param at] facing [param facing] (Level.BUILDINGS,
## across by deep facing north or south); one cell for a decor piece.
static func _sight_rect(sight: Dictionary, at: Vector2i, facing: Vector2i) -> Rect2i:
	if not sight.has("slot"):
		return Rect2i(at, Vector2i.ONE)
	var size: Vector2i = Level.BUILDINGS[sight["slot"]]
	if facing.x != 0:
		size = Vector2i(size.y, size.x)
	return Rect2i(at, size)


## The multi-cell sights' planned ground and a cell round it, levelled by
## Relief.lay (keep_flat).
static func _sight_pads() -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for sight in SIGHTS:
		var facing: Vector2i = sight["facing"] if sight["facing"] != ROADWARD else Vector2i(0, 1)
		var rect := _sight_rect(sight, sight["at"], facing)
		if rect.size != Vector2i.ONE:
			out.append(rect.grow(1))
	return out


## The landmarks, roadside sights and story pieces (778, SIGHTS): each on
## the nearest fitting cell to its plan, a building into "buildings", a
## decor piece into "decor", faced as said or toward the nearest path cell.
func _sights() -> void:
	var paths := _track_cells.duplicate()
	for cell in _road_cells:
		paths[cell] = true
	var taken := {}
	for building: Dictionary in config["buildings"]:
		var at := Vector2i(int(building["at"][0]), int(building["at"][1]))
		var size := Vector2i.ONE
		if building.has("kind"):
			size = Vector2i(CAMP_SIZE, CAMP_SIZE)
		elif building.has("length"):
			size = Vector2i(int(building["length"]), int(building["width"]))
		elif Level.BUILDINGS.has(building["slot"]):
			size = Level.BUILDINGS[building["slot"]]
			if building.has("facing") and int(building["facing"][0]) != 0:
				size = Vector2i(size.y, size.x)
		for cell in _cells_of(Rect2i(at, size).grow(1)):
			taken[cell] = true
	if not config.has("decor"):
		config["decor"] = []
	for sight in SIGHTS:
		var planned: Vector2i = sight["at"]
		var placed := false
		for reach in range(0, SIGHT_REACH + 1):
			for y in range(planned.y - reach, planned.y + reach + 1):
				for x in range(planned.x - reach, planned.x + reach + 1):
					var at := Vector2i(x, y)
					if placed or maxi(absi(x - planned.x), absi(y - planned.y)) != reach:
						continue
					var facing: Vector2i = sight["facing"]
					if facing == ROADWARD:
						facing = _toward_path(at, paths)
					var rect := _sight_rect(sight, at, facing)
					if not _sight_fits(rect, paths, taken):
						continue
					for cell in _cells_of(rect.grow(1)):
						taken[cell] = true
					if sight.has("slot"):
						config["buildings"].append({"slot": sight["slot"], "at": [at.x, at.y], "facing": [facing.x, facing.y]})
					if sight.get("cold_fire", false):
						# Its cold hearth (art-kit's prop.campfire_cold) a cell out from its open front's middle.
						var front := rect.position + (rect.size - Vector2i.ONE) / 2 + facing * (rect.size.y / 2 + 2 if facing.y != 0 else rect.size.x / 2 + 2)
						if map.cell(front) in ["grass", "dirt"]:
							config["decor"].append([front.x, front.y, facing.x, facing.y, "campfire_cold", 1])
						else:
							_missed.append("no ground for the lean-to's cold hearth at %s" % front)
					if sight.has("decor"):
						config["decor"].append([at.x, at.y, facing.x, facing.y, sight["decor"], 1])
					if at != planned:
						print("[hills] %s laid at %s, not %s" % [sight["key"], at, planned])
					placed = true
		if not placed:
			_missed.append("no ground for %s near %s" % [sight["key"], planned])
			push_error("[hills] no ground for %s near %s" % [sight["key"], planned])
	print("[hills] sights: %d buildings, %d decor" % [config["buildings"].size(), config["decor"].size()])


## Whether every cell of [param rect] is grass or plain dirt (no path, no
## water, no ford, no cliff's foot), SIGHT_OFF_PATH clear of every path
## cell and clear of [param taken], on ground of one height within 0.6 m.
func _sight_fits(rect: Rect2i, paths: Dictionary, taken: Dictionary) -> bool:
	var low := INF
	var high := -INF
	for cell in _cells_of(rect):
		if not map.cell(cell) in ["grass", "dirt"] or taken.has(cell):
			return false
		low = minf(low, map.relief_at(cell))
		high = maxf(high, map.relief_at(cell))
	if high - low > 0.6:
		return false
	for cell in _cells_of(rect.grow(SIGHT_OFF_PATH)):
		if paths.has(cell):
			return false
	return true


## The side of [param at] nearest a path cell (its front faced to the road).
static func _toward_path(at: Vector2i, paths: Dictionary) -> Vector2i:
	var best := Vector2i(0, 1)
	var nearest := INF
	for step: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		for d in range(1, 8):
			if paths.has(at + step * d):
				if d < nearest:
					nearest = d
					best = step
				break
	return best


static func _cells_of(rect: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			out.append(Vector2i(x, y))
	return out


## The streams waded anywhere (776): every water cell a ford (floor, slow,
## its footing the ground round it, 505) but those within FALL_POOL of a
## fall's cell ([param falls], Relief.lay's), and each bank over its water
## by more than WADE_RISE (and under WADE_MOST) brought down to WADE_RISE
## over it, the land behind eased down to WADE_RISE a step, ring by ring,
## never across a face (_faces) nor onto other water.
func _wade(falls: Array) -> void:
	var fords := {}
	var pools := 0
	for at: Vector2i in map.cells:
		if map.cell(at) != "water":
			continue
		if falls.any(func(fall: Dictionary) -> bool: return Vector2(at - (fall["cell"] as Vector2i)).length() <= FALL_POOL):
			pools += 1
			continue
		fords[at] = true
	for at: Vector2i in fords:
		map.set_cell(at, "ford")
	var wet := func(at: Vector2i) -> bool: return map.cell(at) in ["water", "ford"]
	var ring: Dictionary = {}
	var graded := 0
	var was: Dictionary = {}  # cell -> its height before, for _unwade
	for at: Vector2i in fords:
		for step: Vector2i in Relief.FOUR:
			var bank: Vector2i = at + step
			if not map.walkable(bank) or wet.call(bank) or _faces.has(Terrain.edge_key(at, step)):
				continue
			var over := map.relief_at(bank) - map.relief_at(at)
			if over > WADE_RISE and over < WADE_MOST:
				if not was.has(bank):
					was[bank] = map.relief_at(bank)
				map.set_relief(bank, minf(map.relief_at(bank), map.relief_at(at) + WADE_RISE))
				ring[bank] = true
				graded += 1
	var eased := 0
	for i in WADE_RINGS:
		var next: Dictionary = {}
		for at: Vector2i in ring:
			for step: Vector2i in Relief.FOUR:
				var behind: Vector2i = at + step
				if not map.walkable(behind) or wet.call(behind) or _faces.has(Terrain.edge_key(at, step)):
					continue
				var over := map.relief_at(behind) - map.relief_at(at)
				if over > WADE_RISE and over < Relief.FACE_LEAST:
					if not was.has(behind):
						was[behind] = map.relief_at(behind)
					map.set_relief(behind, map.relief_at(at) + WADE_RISE)
					next[behind] = true
					eased += 1
		ring = next
	var kept := _unwade(was)
	print("[hills] streams waded: %d ford cells, %d kept deep in %d falls' pools; %d banks graded, %d cells behind eased, %d put back (a cliff they made)" % [fords.size(), pools, falls.size(), graded, eased, kept])


## The cells _wade lowered ([param was]: cell -> height before) that stand
## at a cliff to dry land they did not before put back as they were, again
## till none is (the grading stops short there, the bank kept): how many.
func _unwade(was: Dictionary) -> int:
	var back := 0
	for i in 64:
		var changed := false
		for at: Vector2i in was:
			if is_equal_approx(map.relief_at(at), was[at]):
				continue
			for step: Vector2i in Relief.FOUR:
				var next: Vector2i = at + step
				if not map.walkable(next) or map.cell(next) in ["water", "ford"]:
					continue
				var before: float = was.get(next, map.relief_at(next)) if not was.has(next) or is_equal_approx(map.relief_at(next), was[next]) else was[next]
				if Relief.cliff_between(map.relief_at(at), map.relief_at(next)) and not Relief.cliff_between(was[at], before):
					map.set_relief(at, was[at])
					back += 1
					changed = true
					break
		if not changed:
			break
	return back


## Says the cliff edges the relief has (the plateau's face and the
## escarpments' are meant; any other is a stray).
func _say_cliffs() -> void:
	var count := 0
	var off_face := 0
	var strays: Array[Vector2i] = []
	for at: Vector2i in map.cells:
		if not map.walkable(at):
			continue
		for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			if map.walkable(at + step) and Relief.cliff_between(map.relief_at(at), map.relief_at(at + step)):
				count += 1
				if not (step == Vector2i(1, 0) and at.x == CLIFF_X - 1 and at.y < FOOT):
					off_face += 1
					if not _faces.has(Terrain.edge_key(at, step)):
						strays.append(at)
	print("[hills] %d cliff edges, %d off the plateau's face, %d of them on no escarpment%s" % [count, off_face, strays.size(),
		"" if strays.is_empty() else " (east or south of %s)" % [strays.slice(0, 6)]])


## The link to the wilds on the west edge at LINK_ROW, its arrival two
## cells in, the starts round that; the arrival.
func _link() -> Vector2i:
	var link := Vector2i(0, LINK_ROW)
	while map.cell(link) == "void":
		link.x += 1
	var arrival := link + Vector2i(2, 0)
	for cell in _disc(arrival, 3.0):
		if map.cell(cell) == "void":
			map.set_cell(cell, "grass")
	map.set_cell(link, "link")
	var starts := []
	for dy in [-1, 1, -2, 2]:
		var start := arrival + Vector2i(1, dy)
		map.set_cell(start, "start")
		starts.append([start.x, start.y])
	config["centre"] = [arrival.x, arrival.y]
	config["starts"] = starts
	config["spawn_points"] = {"from_wilds": [arrival.x, arrival.y]}
	config["links"] = [{"at": [link.x, link.y], "to_map": "wilds", "to_spawn": "from_hills"}]
	config["entities"] = entries
	return arrival


## The wilds' end: a link cell at WILDS_LINK and its "from_hills" arrival,
## left as they are if they are there already.
func _link_wilds() -> void:
	var doc := MapDoc.open(WILDS)
	if str(doc.link_of(WILDS_LINK).get("to_map", "")) == "hills" and doc.config.get("spawn_points", {}).has("from_hills"):
		print("[hills] wilds: its link is there already")
		return
	var changes := {"cells": {WILDS_LINK: "link"},
		"links": [{"at": [WILDS_LINK.x, WILDS_LINK.y], "to_map": "hills", "to_spawn": "from_wilds"}]}
	doc.apply_changes(changes)
	var points: Dictionary = doc.config.get("spawn_points", {}).duplicate()
	points["from_hills"] = [WILDS_ARRIVAL.x, WILDS_ARRIVAL.y]
	if str(points) != str(doc.config.get("spawn_points", {})):
		doc.set_config("spawn_points", points)
	if doc.dirty:
		doc.save()
	print("[hills] wilds: " + doc.report)


func _disc(centre: Vector2i, radius: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var reach := ceili(radius)
	for y in range(-reach, reach + 1):
		for x in range(-reach, reach + 1):
			var at := centre + Vector2i(x, y)
			if map.in_bounds(at) and Vector2(x, y).length() <= radius:
				out.append(at)
	return out


func _noise(noise_seed: int, frequency: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = frequency
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	return noise


## Relief.soften_low_steps over the map as it now stands (585: what reads
## as a slope must be climbable), after the steps that move the ground
## once laid.
func _soften() -> void:
	var heights := {}
	var water := {}
	for at: Vector2i in map.cells:
		if map.cell(at) in ["water", "ford"]:
			water[at] = true
		if map.walkable(at) or water.has(at):
			heights[at] = map.relief_at(at)
	Relief.soften_low_steps(heights, water)
	for at: Vector2i in heights:
		map.set_relief(at, heights[at])
