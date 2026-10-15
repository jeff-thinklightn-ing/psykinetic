extends Node
## Writes levels/hills, a showcase of the ground's heights (decision 358),
## and its link from the wilds' west edge:
##   Godot --headless --path . res://tools/make_hills.tscn
## (a scene, not a --script run: saving parses the level, which needs the
## autoloads).
##
## 96 x 96 cells under the sky, its edge an uneven band of forest:
## - a valley floor (level 0) down the middle, with a stream winding north
##   to south (water, 2 wide), crossed by a ford (dirt) and a stone run
##   (where a bridge piece goes once there is one: prop.bridge);
## - to the west, rolling rises: a hill of 2 with a dry gully cut into it,
##   a low rise of 1, and a knoll of 2 crowned with trees (void), each up
##   by a stair flight;
## - to the east, a plateau at 4 with a sheer cliff face over the valley,
##   a flight of four stairs standing out from it (open both sides, a
##   ledge to fall from), and the safe way up, terraces of 1, 2 and 3 to its
##   south with a stair between each;
## - a low stone wall on the valley floor below the cliff, which the
##   plateau sees over;
## - grass, dirt and stone (rock) ground, a few boulders and crates by the
##   rim, starts on the valley floor by the link to the wilds (east edge).
## No monsters, no buildings. The same seed makes the same map.

const SIZE := Vector2i(96, 96)
const SEED := 358
const FOLDER := "res://levels/hills/"
const WILDS := "res://levels/wilds/"
## The wilds' end of the link (maps-80): the land's first cell on row 128,
## its arrival two cells in.
const WILDS_LINK := Vector2i(14, 128)
const WILDS_ARRIVAL := Vector2i(16, 128)
## The link's row on this map's east edge.
const LINK_ROW := 70
## The plateau: its west face (the cliff) at this column, north of row
## FOOT - 1; terraces of 3, 2, 1 below it, TERRACE rows each.
const CLIFF_X := 62
const FOOT := 50
const TERRACE := 4
## How far in from the cliff the plateau's top is rock.
const RIM := 4
## The safe way up: the column of the terraces' stairs.
const STAIR_X := 76
## The cliff's flight: its row, standing out west of the face.
const FLIGHT_ROW := 30
## The stream's middle column, and its crossings' rows.
const STREAM_X := 46
const FORD_ROW := 38
const BRIDGE_ROW := 78
## The low wall: its column (the edge east of it) and rows.
const WALL_X := 55
const WALL_ROWS := Vector2i(34, 42)

var map := LevelMap.new(SIZE)
var config := {"name": "The Hills", "outdoor": true, "zone": "outdoors", "region": "town_lands", "border": "forest", "walls": "stone", "floors": "cave"}
var entries: Array = []


func _ready() -> void:
	var edge := _noise(SEED, 0.05)
	var dirt := _noise(SEED + 1, 0.07)
	var wobble := _noise(SEED + 2, 0.12)
	# The land: in from the border by 3 to 9 cells, unevenly; grass and dirt.
	for y in SIZE.y:
		for x in SIZE.x:
			var inward := mini(mini(x, y), mini(SIZE.x - 1 - x, SIZE.y - 1 - y))
			if inward > 3 + 6.0 * (edge.get_noise_2d(x, y) * 0.5 + 0.5):
				map.set_cell(Vector2i(x, y), "dirt" if dirt.get_noise_2d(x, y) > 0.3 else "grass")
	_plateau(wobble)
	_lay(HeightTools.hill(map, Vector2i(20, 50), 11, 2, [Vector2i(0, -1)]))
	_gully(Vector2i(31, 50), Vector2i(24, 50), 1)
	_lay(HeightTools.hill(map, Vector2i(24, 77), 9, 1, [Vector2i(1, 0), Vector2i(0, -1)]))
	_lay(HeightTools.hill(map, Vector2i(22, 22), 8, 2, [Vector2i(0, 1)]))
	# The knoll's crown: trees.
	for cell in _disc(Vector2i(22, 22), 2.2):
		map.set_cell(cell, "void")
		map.heights.erase(cell)
	_stream()
	_wall()
	# Boulders and crates by the rim and the flight, to push off.
	for at in [Vector2i(CLIFF_X + 1, 24), Vector2i(CLIFF_X + 2, 40)]:
		map.set_cell(at, "boulder")
	for at in [Vector2i(CLIFF_X + 1, 34), Vector2i(CLIFF_X + 1, 36), Vector2i(CLIFF_X - 3, FLIGHT_ROW + 3)]:
		map.set_cell(at, "crate")
	_link()
	var cells: Array[Vector2i] = []
	cells.assign(map.cells.keys())
	for warning in HeightTools.ledge_warnings(map, cells):
		print("[hills] " + warning)
	var doc := MapDoc.open(FOLDER, SIZE)
	doc.map = map
	doc.config = config
	doc.config_dirty = true
	doc.heights_dirty = true
	doc.save()
	print("[hills] " + doc.report)
	_link_wilds()
	get_tree().quit()


## The plateau at 4 east of CLIFF_X north of FOOT, the terraces of 3, 2 and 1
## below it, rock (stone) but for the plateau's top in from its rim; the
## cliff's flight and the terraces' stairs.
func _plateau(wobble: FastNoiseLite) -> void:
	var levels: Array[Array] = [[], [], [], []]
	for y in range(0, FOOT + TERRACE * 3):
		for x in range(CLIFF_X, SIZE.x):
			var at := Vector2i(x, y)
			if map.cell(at) == "void":
				continue
			# The terraces' fronts waver, but not by the stairs.
			var shift := 0 if absi(x - STAIR_X) <= 2 else roundi(wobble.get_noise_2d(x, 0.0) * 1.4)
			var level := 4 - clampi(floori(float(y - FOOT - shift) / TERRACE) + 1, 0, 4)
			if level <= 0:
				continue
			levels[level - 1].append(at)
			# Rock on the terraces and along the rim; the top keeps its grass.
			if level < 4 or x < CLIFF_X + RIM:
				map.set_cell(at, "stone")
	for level in 4:
		var cells: Array[Vector2i] = []
		cells.assign(levels[level])
		_lay(HeightTools.level(map, cells, level + 1))
	# The safe way: a stair at the foot of each terrace's front, on the
	# lower side.
	for y in range(FOOT - 1, FOOT + TERRACE * 3 + 2):
		var at := Vector2i(STAIR_X, y)
		if map.heights.get(at, 0) == map.heights.get(at - Vector2i(0, 1), 0) - 1:
			_lay(HeightTools.stair(map, at, Vector2i(0, -1)))
	# The cliff's flight: four stairs west from the face, each a level up
	# toward it, with the valley floor either side.
	_lay(HeightTools.flight(map, Vector2i(CLIFF_X - 4, FLIGHT_ROW), Vector2i(CLIFF_X, FLIGHT_ROW)))


## A dry gully: a dirt channel at level 0, 2 * [param half] + 1 wide, from
## [param mouth] (on the valley floor) in to [param end].
func _gully(mouth: Vector2i, end: Vector2i, half: int) -> void:
	var way := (end - mouth).sign()
	var at := mouth
	var cells: Array[Vector2i] = []
	while true:
		for side in range(-half, half + 1):
			var cell := at + Vector2i(way.y, way.x) * side
			cells.append(cell)
			map.set_cell(cell, "dirt")
		if at == end:
			break
		at += way
	_lay(HeightTools.level(map, cells, 0))


## The stream: 2 wide, winding north to south through the valley, its
## banks dirt; a ford of dirt across it at FORD_ROW, a stone run at
## BRIDGE_ROW.
func _stream() -> void:
	for y in SIZE.y:
		var middle := STREAM_X + roundi(sin(y / 9.0) * 4.0 + sin(y / 4.3) * 1.2)
		for x in range(middle - 2, middle + 2):
			var at := Vector2i(x, y)
			if map.cell(at) == "void":
				continue
			map.heights.erase(at)
			var bank := x == middle - 2 or x == middle + 1
			if y in [FORD_ROW, FORD_ROW + 1]:
				map.set_cell(at, "dirt")
			elif y in [BRIDGE_ROW, BRIDGE_ROW + 1]:
				map.set_cell(at, "stone")
			else:
				map.set_cell(at, "dirt" if bank else "water")


## The low wall below the cliff: the edges east of WALL_X over WALL_ROWS.
func _wall() -> void:
	for y in range(WALL_ROWS.x, WALL_ROWS.y):
		map.set_edge(Vector3i(WALL_X, y, Terrain.EAST), "wall")


## The link to the wilds on the east edge at LINK_ROW, its arrival two
## cells in, the starts round that.
func _link() -> void:
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


## The wilds' end: a link cell at WILDS_LINK and its "from_hills" arrival,
## left as they are if they are there already.
func _link_wilds() -> void:
	var doc := MapDoc.open(WILDS)
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


## Lays HeightTools' [param changes] on the map, saying any warnings.
func _lay(changes: Dictionary) -> void:
	for warning: String in changes.get("warnings", []):
		print("[hills] " + warning)
	if changes.has("reason"):
		print("[hills] not made: " + str(changes["reason"]))
	for at: Vector2i in changes["heights"]:
		if changes["heights"][at] <= 0:
			map.heights.erase(at)
		else:
			map.heights[at] = changes["heights"][at]
	for at: Vector2i in changes["cells"]:
		map.set_cell(at, changes["cells"][at])
	for key: Vector3i in changes["edges"]:
		map.set_edge(key, changes["edges"][key])


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
