extends Node
## Writes levels/hills, a showcase of the ground's relief (decision 525;
## before it, of whole levels: 358), and its link from the wilds' west edge:
##   Godot --headless --path . res://tools/make_hills.tscn
## (a scene, not a --script run: saving parses the level, which needs the
## autoloads).
##
## 96 x 96 cells under the sky, its edge an uneven band of forest, its
## ground in metres (relief.png, laid by Relief.lay):
## - a valley 6 m deep winding north to south down the middle, falling to
##   the south, its stream (2 wide) found by the water's own way down,
##   crossed by a ford and a bridge;
## - to the west, hills rolling 3.5 m either way over 70 cells and a ridge
##   9 m over them, 22 cells out, running north to south, its highest knoll
##   crowned with trees (void): from its crest you look down 14 m and more
##   into the valley;
## - across the stream, a knoll 7 m high, so the valley has a shape from
##   both sides;
## - to the east, a plateau 6 m up, its west side a sheer cliff (the map's
##   one), rock along its rim, its south side falling away as a long
##   walkable spur: the way up;
## - the ground's kinds by its slope (Relief.lay "kinds", 525 amended):
##   rock on the steep, bare dirt on steeper ground and the crests, grass in
##   the hollows, dirt banks by the stream;
## - a low stone wall on the valley floor below the cliff, which the plateau
##   sees over; a few boulders and crates by the rim to push off;
## - starts on a levelled pad by the link to the wilds (east edge).
## No monsters, no buildings but the bridge. The same seed makes the same
## map.

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
## The valley's line, the ridge's, and the knoll across the stream.
const VALLEY: Array[Vector2i] = [Vector2i(46, 0), Vector2i(42, 30), Vector2i(50, 60), Vector2i(44, 95)]
const RIDGE: Array[Vector2i] = [Vector2i(8, 10), Vector2i(17, 34), Vector2i(12, 62), Vector2i(19, 88)]
const KNOLL := Vector2i(68, 76)
## The rows the ford and the bridge cross the stream nearest to (the
## nearest it runs through, the bridge at least 7 rows from the ford).
const FORD_ROW := 38
const BRIDGE_ROW := 78
## The low wall: its column (the edge east of it) and rows.
const WALL_X := 55
const WALL_ROWS := Vector2i(34, 42)

var map := LevelMap.new(SIZE)
var config := {"name": "The Hills", "outdoor": true, "zone": "outdoors", "region": "town_lands", "border": "forest", "walls": "stone", "floors": "cave"}
var entries: Array = []
## The ford's row, once laid (the bridge keeps away from it).
var _ford_row := -100


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
		"ridges": [RIDGE, {"line": [KNOLL], "height": 6.0, "width": 20.0}], "ridge_height": 6.5, "ridge_width": 34.0,
		"valleys": [VALLEY], "valley_depth": 3.5, "valley_floor": 3.0, "valley_fall": 5.0, "valley_width": 30.0, "kinds": true, "min_flow": 30,
		"plateaus": [{"rect": Rect2i(CLIFF_X, 0, SIZE.x - CLIFF_X, FOOT), "height": PLATEAU_HEIGHT, "faces": ["west"], "spur": 0.25}],
		"keep_flat": [Rect2i(arrival - Vector2i(2, 3), Vector2i(4, 7))],
		"streams": 1, "width": 2, "keep_clear": {}})
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
	var stream: Array[Vector2i] = []
	if not laid["streams"].is_empty():
		stream = laid["streams"][0]
		var path: Array = []
		for cell in stream:
			path.append([cell.x, cell.y])
		config["streams"] = [{"path": path}]
	var water := {}
	for at: Vector2i in laid["cells"]:
		if laid["cells"][at] == "water":
			water[at] = true
	_ford(water)
	_bridge(water)
	_rock()
	_knoll()
	_wall()
	# Boulders and crates by the rim, to push off.
	for at in [Vector2i(CLIFF_X + 1, 24), Vector2i(CLIFF_X + 2, 40)]:
		map.set_cell(at, "boulder")
	for at in [Vector2i(CLIFF_X + 1, 34), Vector2i(CLIFF_X + 1, 36)]:
		map.set_cell(at, "crate")
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
	for at: Vector2i in map.cells:
		if map.walkable(at) or map.cell(at) == "water":
			heights[at] = map.relief_at(at)
	for at: Vector2i in water:
		fixed[at] = true
		if map.cell(at) == "water":
			wet[at] = true
		for step: Vector2i in Relief.FOUR:
			if heights.has(at + step) and not water.has(at + step) and absi(at.y - across[0].y) > 2:
				fixed[at + step] = true
	for bank: Vector2i in [across[0] - Vector2i(1, 0), across[across.size() - 1] + Vector2i(1, 0)]:
		heights[bank] = surface + 0.3
		fixed[bank] = true
	var face := {}
	for y in FOOT:
		face[Terrain.edge_key(Vector2i(CLIFF_X - 1, y), Vector2i(1, 0))] = true
	Relief._limit(heights, fixed, wet, Relief.LAY_SLOPE, face)
	for at: Vector2i in heights:
		map.set_relief(at, heights[at])


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
			if cells.size() >= 1 and cells.size() <= 2 and cells[cells.size() - 1].x - cells[0].x == cells.size() - 1 					and (not straight or _straight(water, cells)):
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


## Rock (stone) along the plateau's rim, in from its face.
func _rock() -> void:
	for y in FOOT:
		for x in range(CLIFF_X, CLIFF_X + RIM):
			var at := Vector2i(x, y)
			if map.cell(at) in ["grass", "dirt"]:
				map.set_cell(at, "stone")


## The ridge's highest knoll west of the valley, crowned with trees.
func _knoll() -> void:
	var top := Vector2i(-1, -1)
	for at: Vector2i in map.cells:
		if at.x < 36 and map.cell(at) in ["grass", "dirt"] and (top.x < 0 or map.relief_at(at) > map.relief_at(top)):
			top = at
	for cell in _disc(top, 2.2):
		if map.cell(cell) in ["grass", "dirt"]:
			map.set_cell(cell, "void")


## The low wall below the cliff: the edges east of WALL_X over WALL_ROWS.
func _wall() -> void:
	for y in range(WALL_ROWS.x, WALL_ROWS.y):
		map.set_edge(Vector3i(WALL_X, y, Terrain.EAST), "wall")


## Says the cliff edges the relief has (the plateau's face is meant).
func _say_cliffs() -> void:
	var count := 0
	var off_face := 0
	for at: Vector2i in map.cells:
		if not map.walkable(at):
			continue
		for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			if map.walkable(at + step) and Relief.cliff_between(map.relief_at(at), map.relief_at(at + step)):
				count += 1
				if not (step == Vector2i(1, 0) and at.x == CLIFF_X - 1 and at.y < FOOT):
					off_face += 1
	print("[hills] %d cliff edges, %d off the plateau's face" % [count, off_face])


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
