extends Node
## Writes levels/forest, the way to the elven stronghold (decision 464),
## rebuilt bigger (decision 760, layout A step 3; plan
## C:/dev/review/lands/step3.md, the coordinator's approval):
##   Godot --headless --path . res://tools/make_forest.tscn
## (a scene, not a --script run: saving parses the level, which needs the
## autoloads). The links and the world plane are edited by hand (as 745's
## and 756's): the plane's forest at (-224, 80), west of the wilds; this
## writes the links on the right edges, so a rerun is safe.
##
## 224 x 224 cells under an evergreen canopy (terrain's "canopy": its
## interior void cells drawn as tall pines), its edge an uneven band of
## forest:
## - grass ground, walkable everywhere but the trunks; dirt only on the
##   paths (terrain's forest_grow.py tells them apart: trees stand on grass);
## - clearings (level.json "clearings": no canopy, environment's light
##   shafts): by the way in from the wilds (east), by the way on (north), the
##   healer's, and more through the wood, a few deep in it;
## - the path 2 wide winding from the way in to the way on, and side paths
##   from it to the other clearings;
## - trunks: grown offline by terrain's tools/forest_grow.py (decision 467)
##   over what this lays, into levels/forest/trees.json; ForestPack.from_trees
##   (466) makes each tree of 3 m or more a void cell, last. Run this, then
##   forest_grow.py --level levels/forest, then this again; with no
##   trees.json the map is laid without trunks;
## - the link back to the wilds on the east edge (world row 128, the wilds'
##   (14, 128)), and the way on to the stronghold, Cravenhold, on the north
##   edge (world column -56, as before), closed (level.json "closed");
## - the sought's refuges (613 amended), by name, and the healer's turf
##   house (718) where it stood: its cells and walls copied from the level
##   as it is, so its place key (forest/healers_hut@45,31, Level's
##   building_places on its front cell) and its keeper stay (718's way).
## No monsters, no buildings but the healer's. The same seed makes the same map.

const SIZE := Vector2i(224, 224)
const SEED := 452
const FOLDER := "res://levels/forest/"
const WILDS := "res://levels/wilds/"
## The wilds' row the link is on: the land's last cell on it, its arrival
## two cells in.
const WILDS_ROW := 128
## This map's link to the wilds: the land's last cell on this row going
## east (world row 128 at origin y 80).
const EAST_ROW := 48
## Its column: one in from the map's edge.
const LINK_X := 222
## The way on to the stronghold: the land's first cell on this column going
## south (world column -56 at origin x -224, where it was).
const NORTH_COLUMN := 168
## The healer's turf house (718) as it stands: its rect's corner and size
## (Level.BUILDINGS' turf house, 7 x 5), facing south; the cells and walls
## of HUT_COPY copied from the level as it is.
const HUT := {"at": Vector2i(42, 27), "facing": Vector2i(0, 1), "code": "H1"}
const HUT_COPY := Rect2i(40, 25, 11, 10)
## The clearings, {centre, radius}: 0 by the way in, 1 by the way on, 2 the
## healer's (round his hut), the rest through the wood.
const CLEARINGS := [
	{"centre": Vector2i(206, 48), "radius": 8},
	{"centre": Vector2i(168, 18), "radius": 7},
	{"centre": Vector2i(45, 32), "radius": 10},
	{"centre": Vector2i(176, 74), "radius": 9},
	{"centre": Vector2i(118, 102), "radius": 10},
	{"centre": Vector2i(64, 70), "radius": 7},
	{"centre": Vector2i(112, 40), "radius": 7},
	{"centre": Vector2i(82, 150), "radius": 8},
	{"centre": Vector2i(150, 166), "radius": 7},
	{"centre": Vector2i(192, 140), "radius": 6},
	{"centre": Vector2i(34, 188), "radius": 5},
	{"centre": Vector2i(118, 200), "radius": 5},
]
## The paths between clearings (indexes, the link ends as -1 for the way in
## and -2 for the way on): the main path first, from the way in to the way
## on, then the side paths.
const PATHS := [
	[-1, 0], [0, 3], [3, 1], [1, -2],
	[3, 4], [4, 6], [6, 1], [4, 5], [5, 2], [4, 7], [7, 10], [4, 8], [8, 9], [9, 0], [8, 11],
]
const PATH_WIDTH := 2
## The middle clearing's crossing (the coordinator: a six-way star read as
## drawn): a short track across the clearing, west to east, and each path
## into it joining the track at its own cell, a few apart, north of it
## from the north, south from the south; offsets from the clearing's centre
## by the path's other end.
const CROSSING := {"clearing": 4, "from": Vector2i(-8, 0), "to": Vector2i(8, 0),
	"joins": {5: Vector2i(-6, -1), 6: Vector2i(-1, -1), 3: Vector2i(6, -1), 7: Vector2i(-4, 1), 8: Vector2i(3, 1)}}
## How far a path winds either side of its line (cells), and the length of
## its bends.
const PATH_SWING := 7.0
const PATH_BEND := 26.0
## The sought's refuges here (613 amended: one place a story, its key the
## story's tag), each {at, name}.
## Each a short walk off a path, 20 cells at most (Jeff: "zones need to have
## safe paths with activities not too far off the paths"): the thickest
## trees 17 off, in a thick stand between the middle's paths.
const REFUGES := {
	"hunters_lean_to": {"at": Vector2i(84, 152), "name": "the hunters' lean-to"},
	"woodcutters_lean_to": {"at": Vector2i(34, 189), "name": "a woodcutters' lean-to deep in the forest"},
	"thick_wood": {"at": Vector2i(82, 124), "name": "where the trees are thickest"},
	"boar_path": {"at": Vector2i(100, 126), "name": "the path to the hunters' camps"},
	"fletchers_tree": {"at": Vector2i(202, 42), "name": "the fletcher's tree"}}
const FOREST_PACK := "res://editor/forest_pack.gd"
const TREES := "res://levels/forest/trees.json"

var map := LevelMap.new(SIZE)
var config := {"name": "The Forest", "outdoor": true, "zone": "outdoors", "border": "forest",
	"canopy": {"kind": "evergreen"}}
var keep_clear: Dictionary[Vector2i, bool] = {}


func _ready() -> void:
	# The healer's house as it stands, read before the level is written over.
	var old := MapDoc.open(FOLDER)
	var hut_cells: Dictionary[Vector2i, String] = {}
	var hut_edges: Dictionary[Vector3i, String] = {}
	for y in range(HUT_COPY.position.y, HUT_COPY.end.y):
		for x in range(HUT_COPY.position.x, HUT_COPY.end.x):
			hut_cells[Vector2i(x, y)] = old.map.cell(Vector2i(x, y))
	for key: Vector3i in old.map.edges:
		var sides := Terrain.edge_cells(key)
		if HUT_COPY.has_point(sides[0]) and HUT_COPY.has_point(sides[1]):
			hut_edges[key] = old.map.edges[key]
	var edge := _noise(SEED, 0.05)
	# The land: in from the border by 3 to 9 cells, unevenly; grass (the
	# paths' dirt comes after).
	for y in SIZE.y:
		for x in SIZE.x:
			var inward := mini(mini(x, y), mini(SIZE.x - 1 - x, SIZE.y - 1 - y))
			if inward > 3 + 6.0 * (edge.get_noise_2d(x, y) * 0.5 + 0.5):
				map.set_cell(Vector2i(x, y), "grass")
	# The way in cut through the border band to the map's edge (step3.md: the
	# link at local x 221..223, facing the wilds' (14, 128)), 7 wide: the
	# starts beside the arrival on it.
	var band_end := _link_cell(Vector2i(SIZE.x - 1, EAST_ROW), Vector2i(-1, 0))
	for x in range(band_end.x, LINK_X + 1):
		for dy in range(-3, 4):
			map.set_cell(Vector2i(x, EAST_ROW + dy), "grass")
	var east := Vector2i(LINK_X, EAST_ROW)
	var north := _link_cell(Vector2i(NORTH_COLUMN, 0), Vector2i(0, 1))
	var clearings := []
	for each: Dictionary in CLEARINGS:
		for cell in _disc(each["centre"], each["radius"]):
			_clear(cell, "grass")
		clearings.append({"centre": [each["centre"].x, each["centre"].y], "radius": each["radius"]})
	config["clearings"] = clearings
	var ends := {-1: east + Vector2i(-2, 0), -2: north + Vector2i(0, 2)}
	for k in PATHS.size():
		var pair: Array = PATHS[k]
		var from := _path_end(pair[0], pair[1], ends)
		var to := _path_end(pair[1], pair[0], ends)
		_path(from, to, SEED + k)
	var middle: Vector2i = CLEARINGS[CROSSING["clearing"]]["centre"]
	_path(middle + CROSSING["from"], middle + CROSSING["to"], SEED + PATHS.size(), 1.0)
	# The links' last cells clear to the land's edge.
	for x in range(east.x - 2, east.x + 1):
		_clear(Vector2i(x, east.y), "dirt")
	for y in range(north.y, north.y + 3):
		_clear(Vector2i(north.x, y), "dirt")
	# The healer's house where it stood, over the paths.
	for at: Vector2i in hut_cells:
		if hut_cells[at] != "void":  # The old wood's trunks round it stay the new clearing's ground.
			map.set_cell(at, hut_cells[at])
		keep_clear[at] = true
	for key: Vector3i in hut_edges:
		map.set_edge(key, hut_edges[key])
	_trunks()
	_places()
	_links(east, north)
	_close_pockets(east + Vector2i(-2, 0))
	var doc := MapDoc.open(FOLDER, SIZE)
	doc.map = map
	doc.config = config
	doc.config_dirty = true
	doc.save()
	print("[forest] " + doc.report)
	_link_wilds()
	get_tree().quit()


## Where a path between clearing (or link end) [param at] and [param other]
## ends at [param at]: a link's arrival, its own join on the middle
## clearing's crossing, else the clearing's centre.
func _path_end(at: int, other: int, ends: Dictionary) -> Vector2i:
	if at < 0:
		return ends[at]
	var centre: Vector2i = CLEARINGS[at]["centre"]
	if at == CROSSING["clearing"] and CROSSING["joins"].has(other):
		return centre + CROSSING["joins"][other]
	return centre


## The land's outermost cell from [param start] stepping [param step]
## inward: where a link marker goes.
func _link_cell(start: Vector2i, step: Vector2i) -> Vector2i:
	var at := start
	while map.cell(at) == "void":
		at += step
	return at


## [param cell] kept clear of trunks, as ground ([param ground] where it
## was the border's void).
func _clear(cell: Vector2i, ground: String) -> void:
	if not map.in_bounds(cell):
		return
	if map.cell(cell) == "void":
		map.set_cell(cell, ground)
	keep_clear[cell] = true


## A dirt path PATH_WIDTH wide from [param from] to [param to], winding:
## [param swing_by] (PATH_SWING) either side of its line in bends about PATH_BEND long,
## wandering by [param path_seed], eased to nothing at its ends.
func _path(from: Vector2i, to: Vector2i, path_seed: int, swing_by := PATH_SWING) -> void:
	var length := Vector2(from).distance_to(Vector2(to))
	var steps := maxi(1, ceili(length * 2.0))
	var across := Vector2(to - from).orthogonal().normalized()
	var wander := _noise(path_seed, 1.0 / PATH_BEND)
	for i in steps + 1:
		var t := float(i) / steps
		var ease := sin(t * PI)
		var swing := wander.get_noise_1d(t * length) * 1.6 + 0.35 * sin(t * length / PATH_BEND * TAU)
		var middle := Vector2(from).lerp(Vector2(to), t) + across * clampf(swing, -1.0, 1.0) * swing_by * ease
		for dx in PATH_WIDTH:
			for dy in PATH_WIDTH:
				var cell := Vector2i(roundi(middle.x), roundi(middle.y)) + Vector2i(dx, dy)
				if map.in_bounds(cell):
					if not keep_clear.has(cell) or map.cell(cell) == "grass" or map.cell(cell) == "void":
						map.set_cell(cell, "dirt")
					keep_clear[cell] = true


## The trunks: forest_grow.py's trees.json made void cells by terrain's
## ForestPack.from_trees, when both are there; none until then.
func _trunks() -> void:
	if not ResourceLoader.exists(FOREST_PACK) or not FileAccess.file_exists(TREES):
		print("[forest] no %s or %s yet: laid without trunks" % [FOREST_PACK, TREES])
		return
	var pack: GDScript = load(FOREST_PACK)
	var count: int = pack.call("from_trees", map, TREES)
	print("[forest] %d trunks from the grown trees" % count)


## Floor not reached from [param arrival] (a few cells in the border
## band's ragged edge, closed off by its noise or the trunks) made the
## border's wood again, so every floor cell is walked to; said by count.
func _close_pockets(arrival: Vector2i) -> void:
	var reached: Dictionary[Vector2i, bool] = {arrival: true}
	var todo: Array[Vector2i] = [arrival]
	while not todo.is_empty():
		var at: Vector2i = todo.pop_back()
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := at + step
			if map.in_bounds(next) and not reached.has(next) and map.cell(next) != "void":
				reached[next] = true
				todo.append(next)
	var closed := 0
	for y in SIZE.y:
		for x in SIZE.x:
			var at := Vector2i(x, y)
			if map.cell(at) != "void" and not reached.has(at):
				map.set_cell(at, "void")
				closed += 1
	print("[forest] %d cut-off floor cells closed" % closed)


## The refuges in "places", and the healer's turf house in "buildings" (its
## walls and door copied with its cells).
func _places() -> void:
	var places := {}
	for key: String in REFUGES:
		var at: Vector2i = REFUGES[key]["at"]
		places[key] = {"at": [at.x, at.y], "kind": "refuge", "where": "forest", "radius": 3, "name": REFUGES[key]["name"]}
	config["places"] = places
	var at: Vector2i = HUT["at"]
	var facing: Vector2i = HUT["facing"]
	config["buildings"] = [{"slot": "building.turf_house", "at": [at.x, at.y], "facing": [facing.x, facing.y], "code": HUT["code"]}]
	config["building_codes"] = {"H": 1}


## The links: back to the wilds at [param east], on to the stronghold
## (closed) at [param north]; arrivals two cells in, the starts by the way in.
func _links(east: Vector2i, north: Vector2i) -> void:
	var arrival := east + Vector2i(-2, 0)
	map.set_cell(east, "link")
	map.set_cell(north, "link")
	var starts := []
	for dy in [-1, 1, -2, 2]:
		var start := arrival + Vector2i(-1, dy)
		map.set_cell(start, "start")
		starts.append([start.x, start.y])
	config["centre"] = [arrival.x, arrival.y]
	config["starts"] = starts
	config["spawn_points"] = {"from_wilds": [arrival.x, arrival.y], "from_stronghold": [north.x, north.y + 2]}
	config["links"] = [
		{"at": [east.x, east.y], "to_map": "wilds", "to_spawn": "from_forest"},
		{"at": [north.x, north.y], "to_map": "stronghold", "to_spawn": "from_forest", "closed": true},
	]
	config["entities"] = []


## The wilds' end: its link to the forest and its "from_forest" arrival,
## left as they are when there (the wilds' west edge, (14, 128)).
func _link_wilds() -> void:
	var doc := MapDoc.open(WILDS)
	var links: Array = doc.config.get("links", [])
	var there := links.any(func(link: Dictionary) -> bool: return link.get("to_map") == "forest")
	var points: Dictionary = doc.config.get("spawn_points", {})
	print("[forest] wilds: %s" % ("its link is there already" if there and points.has("from_forest") else "NO LINK TO THE FOREST: edit it by hand"))


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
