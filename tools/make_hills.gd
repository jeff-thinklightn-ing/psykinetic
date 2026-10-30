extends Node
## Writes levels/hills, a showcase of the ground's relief (decision 525;
## before it, of whole levels: 358), and its link from the wilds' west edge:
##   Godot --headless --path . res://tools/make_hills.tscn
## Stale since decision 743 (layout A: the hills east of the wilds, their
## link moved by hand to the west edge at (7, 38), the bridge (505 amended
## (2)) by hand): a rerun writes the old east-edge link. The hills are
## rebuilt bigger in 743's step 3; until then edit levels/hills by hand.
## (a scene, not a --script run: saving parses the level, which needs the
## autoloads).
##
## 96 x 96 cells under the sky, its edge an uneven band of forest, its
## ground in metres (relief.png, laid by Relief.lay):
## - a valley winding north to south down the middle, its floor falling to
##   the south, its river (2 to 3 wide) looping across the valley's floor
##   (Relief.lay "rivers", decision 559), crossed by a ford and a bridge;
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
## - a low stone wall on the valley floor below the cliff, which the plateau
##   sees over; a few boulders and crates by the rim to push off;
## - starts on a levelled pad by the link to the wilds (east edge);
## - the faces (the escarpments', the plateau's cliff) along curves that
##   wander WANDER cells either way of their lines, and level.json's
##   "ledges" traced from them (decision 585: MapDoc.save traces them).
## - the sought's refuges (613 amended), two of them herders' holdings
##   (640, maps' side): a hut and a fold on a levelled pad (HERDERS).
## No monsters, no buildings but the bridge and the herders'. The same seed
## makes the same map.

const SIZE := Vector2i(96, 96)
const SEED := 525
const FOLDER := "res://levels/hills/"
const WILDS := "res://levels/wilds/"
## The wilds' end of the link (maps-80): the land's first cell on row 128,
## its arrival two cells in.
const WILDS_LINK := Vector2i(14, 128)
const WILDS_ARRIVAL := Vector2i(16, 128)
## The link's row on this map's east edge.
const LINK_ROW := 70
## The plateau: its cliff face at this column, north of row FOOT; how far
## in from the face its top is rock; how high it stands.
const CLIFF_X := 62
const FOOT := 46
const RIM := 4
const PLATEAU_HEIGHT := 6.0
## The ground's middle height, and how it leans (metres a cell, north up).
const BASE := 8.0
const TILT := Vector2.ZERO
## The valley's line.
const VALLEY: Array[Vector2i] = [Vector2i(46, 0), Vector2i(42, 30), Vector2i(50, 60), Vector2i(44, 95)]
## The escarpments: their lines, which way their faces look, how high.
const WEST_SCARP: Array[Vector2i] = [Vector2i(30, 4), Vector2i(27, 36), Vector2i(32, 66)]
const SOUTH_SCARP: Array[Vector2i] = [Vector2i(50, 57), Vector2i(87, 65)]
const SCARP_HEIGHT := 3.0
## How far the escarpments' and the plateau's faces wander either way of
## their lines (585: smooth, off the cells' lines).
const WANDER := 1.5
## The plateau's face's wander's seed (added to SEED's), and where it is
## still: the fall's lip, so the fall lands below its line, its pool whole.
const PLATEAU_WANDER_SEED := 0
const FALL_LIP := Vector2i(62, 21)
## The escarpments' wander's seed (added to SEED's).
const SCARP_WANDER_SEED := 0
## Where along the west escarpment its way up is (the road goes up it).
const WEST_WAY := 0.55
## The road: its width, and how far west past the way it runs.
const ROAD_WIDTH := 2.0
const ROAD_END_WEST := 14
## The river down the valley (Relief.lay "rivers", decision 559; Jeff: "a
## meandering stream not a straight line"): its loops' length and swing
## either way, in cells, and its width, wandering between the two.
const RIVER_WAVELENGTH := 26.0
const RIVER_AMPLITUDE := 7.0
const RIVER_WIDTH: Array[float] = [1.6, 3.2]
## The valley's floor either side of its line, held as laid, the river's
## loops on it (wider reaches into the escarpments' feet and flattens their
## faces).
const RIVER_FLOOR := 9.0
## The fall's stream (570): off the plateau's top west over its cliff (6 m)
## into a pool at its foot, then down to the river, its line ending in the
## river's water (so the way on from it is the river's).
const FALL_STREAM: Array[Vector2i] = [Vector2i(84, 12), Vector2i(74, 16), Vector2i(66, 19), Vector2i(59, 21), Vector2i(53, 22)]
## Its loops' seed (added to SEED's): the one whose loops keep clear of the
## south escarpment's foot.
const RIVER_SEED := 5
## The rows the ford and the bridge cross the stream nearest to (the
## nearest it runs through, the bridge at least 7 rows from the ford).
const FORD_ROW := 38
const BRIDGE_ROW := 78
## The ford's banks are walked to over this many rows either side of it
## (the stream's banks further off kept as laid).
const FORD_FREE := 4
## The low wall: its column (the edge east of it) and rows.
const WALL_X := 55
const WALL_ROWS := Vector2i(34, 42)
## The sought's refuges here (613 amended: one place a story, its key the
## story's tag), each {at, name}.
const REFUGES := {"hill_cave": {"at": Vector2i(23, 56), "name": "a hill cave"}}
## The herders' holdings (640, maps' side; Jeff: "herders exist as people"):
## refuges economy's herder.places names, each a building.fold (6 x 6, its
## gate the front row's middle two edges, open) whose gate looks across a
## 2-cell way at a building.hut's door, both on one levelled pad, the
## place's cell the way's cell before the door. Each {key, name, fold (its
## rect), gate (the way it opens)}.
const HERDERS: Array[Dictionary] = [
	{"key": "herders_hut", "name": "the herder's hut", "fold": Rect2i(11, 18, 6, 6), "gate": Vector2i(0, 1)},
	{"key": "hill_shieling", "name": "a shieling high on the hill", "fold": Rect2i(68, 23, 6, 6), "gate": Vector2i(1, 0)}]
## The way between a fold's gate and its hut's door, in cells.
const HERDER_WAY := 2

var map := LevelMap.new(SIZE)
var config := {"name": "The Hills", "outdoor": true, "zone": "outdoors", "region": "town_lands", "border": "forest", "walls": "stone", "floors": "cave"}
var entries: Array = []
## The ford's row, once laid (the bridge keeps away from it).
var _ford_row := -100
## The escarpments' faces as laid (edge keys), kept by the ford's limiting.
var _faces: Dictionary = {}


func _ready() -> void:
	var edge := _noise(SEED, 0.05)
	# The land: in from the border by 3 to 9 cells, unevenly; grass and dirt.
	for y in SIZE.y:
		for x in SIZE.x:
			var inward := mini(mini(x, y), mini(SIZE.x - 1 - x, SIZE.y - 1 - y))
			if inward > 3 + 6.0 * (edge.get_noise_2d(x, y) * 0.5 + 0.5):
				map.set_cell(Vector2i(x, y), "grass")
	var arrival := _link()
	var laid := Relief.lay(map, Rect2i(Vector2i.ZERO, SIZE), SEED, {
		"base": BASE, "amplitude": 2.0, "scale": 70.0, "octaves": 2, "tilt": TILT,
		"escarpments": [
			{"line": WEST_SCARP, "face": "east", "height": SCARP_HEIGHT, "back": 22.0, "ways": [WEST_WAY], "wander": WANDER, "wander_seed": SCARP_WANDER_SEED},
			{"line": SOUTH_SCARP, "face": "north", "height": SCARP_HEIGHT - 0.5, "back": 20.0, "ways": [0.3], "wander": WANDER, "wander_seed": SCARP_WANDER_SEED}],
		"slope": 0.3, "steep_bands": 0.3, "rock_step": Relief.MAX_M, "dirt_step": 0.33,
		"valleys": [VALLEY], "valley_depth": 4.5, "valley_floor": RIVER_FLOOR, "valley_fall": 5.0, "valley_width": 30.0, "kinds": true, "min_flow": 30,
		"plateaus": [{"rect": Rect2i(CLIFF_X, 0, SIZE.x - CLIFF_X, FOOT), "height": PLATEAU_HEIGHT, "faces": ["west"], "spur": 0.25, "wander": WANDER, "wander_seed": PLATEAU_WANDER_SEED, "still": [FALL_LIP]}],
		"keep_flat": [Rect2i(arrival - Vector2i(2, 3), Vector2i(4, 7))] + _herder_pads(),
		"streams": 0, "keep_clear": {},
		"rivers": [{"line": VALLEY, "wavelength": RIVER_WAVELENGTH, "amplitude": RIVER_AMPLITUDE, "width": RIVER_WIDTH, "seed": RIVER_SEED},
			{"line": FALL_STREAM, "wavelength": 14.0, "amplitude": 2.0, "width": [1.4, 2.2]}]})
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
	# The river is its curve (decision 559): Level lays its cells and its
	# "streams" path from it on load.
	config["waters"] = laid["waters"].map(func(water: Dictionary) -> Dictionary:
		return {"points": Curves.to_json(water["points"], water["widths"])})
	var water := {}
	for at: Vector2i in laid["cells"]:
		if laid["cells"][at] == "water":
			water[at] = true
	_faces = laid["faces"]
	if laid["streams"].size() > 1:
		_fall_ford(laid["streams"][1], water)
	_ford(water)
	_bridge(water)
	_rock()
	_knoll()
	_wall()
	_road(arrival)
	_places()
	# Boulders and crates by the rim, to push off.
	for at in [Vector2i(CLIFF_X + 1, 24), Vector2i(CLIFF_X + 2, 40)]:
		map.set_cell(at, "boulder")
	for at in [Vector2i(CLIFF_X + 1, 34), Vector2i(CLIFF_X + 1, 36)]:
		map.set_cell(at, "crate")
	_soften()
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
	_link_wilds()
	get_tree().quit()


## The ford: the stream's cells on the row nearest FORD_ROW it crosses,
## its banks set a walk over its water and the ground round them brought
## down to them (Relief._limit), the stream's other banks kept.
func _ford(water: Dictionary) -> void:
	var across := _crossing(water, FORD_ROW, true)
	if across.is_empty():
		return
	for at in across:
		map.set_cell(at, "ford")
	_ford_row = across[0].y
	var surface := map.relief_at(across[0])
	var heights := {}
	var fixed := {}
	var wet := {}
	# The plateau's top: its north-east corner stands on it.
	var top := map.relief_at(Vector2i(SIZE.x - 8, 4))
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
			if heights.has(at + step) and not water.has(at + step) and absi(at.y - across[0].y) > FORD_FREE:
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
	push_error("[hills] no ford over the fall's stream")


## The bridge over the stream on the row nearest BRIDGE_ROW: its banks
## levelled at the higher of them (a bridge's banks are of one height).
func _bridge(water: Dictionary) -> void:
	var across := _crossing(water, BRIDGE_ROW)
	if across.is_empty():
		return
	var west := across[0]
	var east := across[across.size() - 1]
	var banks: Array[Vector2i] = [west - Vector2i(1, 0), east + Vector2i(1, 0)]
	var top := maxf(map.relief_at(banks[0]), map.relief_at(banks[1]))
	for bank in banks:
		map.set_relief(bank, top)
	config["buildings"] = [{"slot": "bridge", "at": [west.x, west.y], "facing": [1, 0], "length": across.size()}]


## The water cells of the row nearest [param row] that the stream crosses
## with water only, west to east (where it runs [param straight] and
## level, for a ford).
func _crossing(water: Dictionary, row: int, straight := false) -> Array[Vector2i]:
	for offset in range(0, SIZE.y):
		for y in [row + offset, row - offset]:
			if absi(y - _ford_row) <= 6:
				continue
			var cells: Array[Vector2i] = []
			for x in SIZE.x:
				if water.has(Vector2i(x, y)) and map.cell(Vector2i(x, y)) == "water":
					cells.append(Vector2i(x, y))
			if cells.size() >= 1 and cells.size() <= 3 and cells[cells.size() - 1].x - cells[0].x == cells.size() - 1 					and (not straight or _straight(water, cells)):
				return cells
	return []


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
		if at.x < 36 and map.cell(at) in ["grass", "dirt"] and (top.x < 0 or map.relief_at(at) > map.relief_at(top)):
			top = at
	for cell in _disc(top, 2.2):
		if map.cell(cell) in ["grass", "dirt"]:
			map.set_cell(cell, "void")


## The road (decision 563): dirt, from the link's arrival west over the
## bridge and up through the west escarpment's way to ROAD_END_WEST cells
## past it, laid as a curve (Relief.road), its cells bare dirt.
func _road(arrival: Vector2i) -> void:
	if not config.has("buildings"):
		return
	var bridge: Dictionary = config["buildings"][0]
	var west := Vector2i(int(bridge["at"][0]), int(bridge["at"][1]))
	var length := int(bridge["length"])
	var crossings := {}
	for i in length:
		crossings[west + Vector2i(i, 0)] = true
	var way := _along(WEST_SCARP, WEST_WAY)
	var beyond := Vector2i(roundi(way.x) - ROAD_END_WEST, roundi(way.y))
	while not map.walkable(beyond) and beyond.x < roundi(way.x):
		beyond.x += 1
	var laid := Relief.road(map, arrival, [west + Vector2i(length, 0), west - Vector2i(1, 0)], beyond, ROAD_WIDTH, crossings)
	if laid.is_empty():
		push_error("[hills] no way for the road")
		return
	for cell: Vector2i in laid["cells"]:
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


static func _cells_of(rect: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			out.append(Vector2i(x, y))
	return out


## The low wall below the cliff: the edges east of WALL_X over WALL_ROWS.
func _wall() -> void:
	for y in range(WALL_ROWS.x, WALL_ROWS.y):
		map.set_edge(Vector3i(WALL_X, y, Terrain.EAST), "wall")


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


## The link to the wilds on the east edge at LINK_ROW, its arrival two
## cells in, the starts round that; the arrival.
func _link() -> Vector2i:
	var link := Vector2i(SIZE.x - 1, LINK_ROW)
	while map.cell(link) == "void":
		link.x -= 1
	var arrival := link - Vector2i(2, 0)
	for cell in _disc(arrival, 3.0):
		if map.cell(cell) == "void":
			map.set_cell(cell, "grass")
	map.set_cell(link, "link")
	var starts := []
	for dy in [-1, 1, -2, 2]:
		var start := arrival + Vector2i(-1, dy)
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
