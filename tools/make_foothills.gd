extends Node
## Writes levels/foothills (decision 745, layout A's step 2): the land
## between the wilds' north edge and the castle, rising north toward the
## mountain, built from the pieces the hills use:
##   Godot --headless --audio-driver Dummy --path . res://tools/make_foothills.tscn
## (a scene, not a --script run: saving parses the level, which needs the
## autoloads). It writes only levels/foothills; the wilds' and the castle's
## links to it, and the world plane, are edited by hand (745).
##
## 256 x 96 cells under the sky at world (0, -96), the wilds' width, its edge
## an uneven band of forest, its ground in metres (relief.png, Relief.lay):
## - rising north: the whole land leaning TILT, and two escarpments facing
##   south across it (Relief.lay "escarpments"), the low one the map's width,
##   the high one east of the river, each with ways up where the road climbs
##   and one more;
## - the river from the north edge down its valley in the west to the south
##   edge at x 62, where the wilds' river enters the wilds' north edge (one
##   water); where it crosses the low escarpment it falls into a pool (570):
##   the falls lore named above the wilds;
## - the north road from the wilds' link (south edge, x 128) up the ways to
##   the castle's link (north edge, x 128), the castle a stand-in for the new
##   castle off the north edge (layout A, step 5);
## - sparse trees: small clumps (void) off the road, the river and the faces;
## - the ground's kinds by slope (Relief.lay "kinds"), and level.json's
##   "ledges" traced from the faces (585: MapDoc.save traces them);
## - starts on a levelled pad by the link to the wilds.
## No monsters, no people, no buildings. The same seed makes the same map.

const SIZE := Vector2i(256, 96)
const SEED := 745
const FOLDER := "res://levels/foothills/"
## Both links' column (the wilds' north road comes in on it, and the castle's
## link sits on it); the lane of open ground through the border band either
## side of it.
const ROAD_X := 128
const LANE := 4.0
## The river's line, source first (it enters the wilds at x 62), and the open
## ground either side of it through the border band.
const RIVER: Array[Vector2i] = [Vector2i(74, 0), Vector2i(68, 30), Vector2i(62, 58), Vector2i(60, 78), Vector2i(62, 95)]
const RIVER_LANE := 9.0
const RIVER_WIDTH: Array[float] = [1.8, 2.8]
## The ground's middle height and its lean (metres a cell; north higher).
const BASE := 8.0
const TILT := Vector2(0.0, -0.07)
## The escarpments, each facing south, zigzagging (a near-level face's
## long runs and lone jogs pull its traced ledge off the cliff): lines, heights, how far back the
## ground rises to them, where along them the ways up are.
const LOW_SCARP: Array[Vector2i] = [Vector2i(4, 62), Vector2i(30, 56), Vector2i(58, 63), Vector2i(90, 57), Vector2i(120, 64), Vector2i(150, 58), Vector2i(180, 64), Vector2i(212, 57), Vector2i(252, 63)]
const HIGH_SCARP: Array[Vector2i] = [Vector2i(92, 27), Vector2i(120, 21), Vector2i(150, 29), Vector2i(172, 24), Vector2i(188, 24), Vector2i(212, 30), Vector2i(252, 23)]
const LOW_HEIGHT := 4.0
const HIGH_HEIGHT := 3.0
const WANDER := 1.5
## Tree clumps: how many tried, and how far each keeps from the road, the
## river's line, the faces' lines and the links.
const CLUMPS := 70
const CLUMP_CLEAR := {"road": 6.0, "river": 11.0, "face": 5.0, "link": 9.0}
const ROAD_WIDTH := 2.0
## The faces' wander seeds tried in turn (added to SEED's): the first whose
## traced ledges keep within LEDGE_FIT of the cliff edges is kept
## (level_test's bound is 0.45; a face's one-cell jog after a long run
## can pull a ledge's curve further off).
const WANDER_SEEDS: Array[int] = [3, 1, 2, 0]
const LEDGE_FIT := 0.42
const CONFIG := {"name": "The Foothills", "outdoor": true, "zone": "outdoors", "region": "town_lands", "border": "forest", "walls": "stone", "floors": "cave"}

var map: LevelMap
var config: Dictionary
var _faces: Dictionary = {}


func _ready() -> void:
	for wander_seed in WANDER_SEEDS:
		_build(wander_seed)
		var miss := _ledge_miss()
		print("[foothills] wander seed %d: ledges within %.2f of the cliff edges" % [wander_seed, miss])
		if miss <= LEDGE_FIT:
			break
	get_tree().quit()


func _build(wander_seed: int) -> void:
	map = LevelMap.new(SIZE)
	config = CONFIG.duplicate(true)
	var edge := _noise(SEED, 0.05)
	for y in SIZE.y:
		for x in SIZE.x:
			var at := Vector2i(x, y)
			var inward := mini(mini(x, y), mini(SIZE.x - 1 - x, SIZE.y - 1 - y))
			var band := 3 + 6.0 * (edge.get_noise_2d(x, y) * 0.5 + 0.5)
			if inward > band or absf(x - ROAD_X) <= LANE + 1.5 * edge.get_noise_2d(x * 3, y) \
					or _to_line(Vector2(at), RIVER) <= RIVER_LANE:
				map.set_cell(at, "grass")
	var south := Vector2i(ROAD_X, SIZE.y - 1)
	var north := Vector2i(ROAD_X, 0)
	var arrivals := _links(south, north)
	var laid := Relief.lay(map, Rect2i(Vector2i.ZERO, SIZE), SEED, {
		"base": BASE, "amplitude": 1.5, "scale": 60.0, "octaves": 2, "tilt": TILT,
		"escarpments": [
			{"line": LOW_SCARP, "face": "south", "height": LOW_HEIGHT, "back": 26.0, "ways": [_fraction(LOW_SCARP, ROAD_X), _fraction(LOW_SCARP, 214)], "wander": WANDER, "wander_seed": wander_seed},
			{"line": HIGH_SCARP, "face": "south", "height": HIGH_HEIGHT, "back": 20.0, "ways": [_fraction(HIGH_SCARP, ROAD_X), _fraction(HIGH_SCARP, 226)], "wander": WANDER, "wander_seed": wander_seed}],
		"slope": 0.3, "steep_bands": 0.3, "rock_step": Relief.MAX_M, "dirt_step": 0.33,
		"valleys": [RIVER], "valley_depth": 1.5, "valley_floor": 8.0, "valley_fall": 3.0, "valley_width": 16.0, "kinds": true, "min_flow": 30,
		"keep_flat": [Rect2i(arrivals[0] - Vector2i(3, 2), Vector2i(7, 5)), Rect2i(arrivals[1] - Vector2i(3, 2), Vector2i(7, 5))],
		"streams": 0, "keep_clear": {},
		"rivers": [{"line": RIVER, "wavelength": 24.0, "amplitude": 4.0, "width": RIVER_WIDTH}]})
	map.relief = PackedFloat32Array()
	map.relief.resize(SIZE.x * SIZE.y)
	var filled := PackedByteArray()
	filled.resize(SIZE.x * SIZE.y)
	for at: Vector2i in laid["relief"]:
		map.relief[at.y * SIZE.x + at.x] = laid["relief"][at]
		filled[at.y * SIZE.x + at.x] = 1
	LevelMap._fill_gaps(map.relief, filled, SIZE)
	for at: Vector2i in laid["cells"]:
		map.set_cell(at, laid["cells"][at])
	config["waters"] = laid["waters"].map(func(water: Dictionary) -> Dictionary:
		return {"points": Curves.to_json(water["points"], water["widths"])})
	_faces = laid["faces"]
	print("[foothills] falls: %s" % [laid.get("falls", [])])
	var road := _road(arrivals[0], arrivals[1])
	_clumps(road)
	_soften()
	var doc := MapDoc.open(FOLDER, SIZE)
	doc.map = map
	doc.config = config
	doc.config_dirty = true
	doc.relief_dirty = true
	doc.heights_dirty = false
	doc.had_heights = false
	doc.save()
	print("[foothills] " + doc.report)
	_say_cliffs()
	for at in [south, arrivals[0], north, arrivals[1]]:
		print("[foothills] ground at %s: %.2f" % [at, map.relief_at(at)])
	var water: Array = config["waters"][0]["points"]
	print("[foothills] the river leaves the south edge at %s" % [water[water.size() - 1]])


## How far the saved level's ledges stray from its cliff edges, or its cliff
## edges from its ledges, at worst: level_test's measure (the walked and wet
## cells as Level loads them, a cliff between two of a kind).
func _ledge_miss() -> float:
	var terrain: Dictionary = Level.load_level("foothills")["terrain"]
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


## The links on the south edge (to the wilds) and the north edge (to the
## castle), each with its arrival two cells in; the starts by the south one.
## Returns the arrivals, south first.
func _links(south: Vector2i, north: Vector2i) -> Array[Vector2i]:
	var from_wilds := south - Vector2i(0, 2)
	var from_castle := north + Vector2i(0, 2)
	for centre in [from_wilds, from_castle]:
		for cell in _disc(centre, 3.0):
			if map.cell(cell) == "void":
				map.set_cell(cell, "grass")
	map.set_cell(south, "link")
	map.set_cell(north, "link")
	var starts := []
	for dx in [-1, 1, -2, 2]:
		var start := from_wilds + Vector2i(dx, -1)
		map.set_cell(start, "start")
		starts.append([start.x, start.y])
	config["centre"] = [from_wilds.x, from_wilds.y]
	config["starts"] = starts
	config["spawn_points"] = {"from_wilds": [from_wilds.x, from_wilds.y], "from_castle": [from_castle.x, from_castle.y]}
	config["links"] = [{"at": [south.x, south.y], "to_map": "wilds", "to_spawn": "from_foothills"},
		{"at": [north.x, north.y], "to_map": "castle", "to_spawn": "from_foothills", "variant": 2}]
	config["entities"] = []
	return [from_wilds, from_castle]


## The north road from the wilds' arrival up the escarpments' ways to the
## castle's (Relief.road), its cells bare dirt. Returns its cells (cell -> anything).
func _road(from: Vector2i, to: Vector2i) -> Dictionary:
	var laid := Relief.road(map, from, [], to, ROAD_WIDTH, {})
	if laid.is_empty():
		push_error("[foothills] no way for the road")
		return {}
	for cell: Vector2i in laid["cells"]:
		if map.cell(cell) in ["grass", "dirt"]:
			map.set_cell(cell, "dirt")
	config["roads"] = [{"points": Curves.to_json(laid["points"], laid["widths"]), "kind": "dirt"}]
	print("[foothills] the road: %d control points, %d cells" % [laid["points"].size(), laid["cells"].size()])
	return laid["cells"]


## Small clumps of trees (void) on open ground, clear of the road, the river,
## the faces and the links.
func _clumps(road: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var laid := 0
	for i in CLUMPS:
		var at := Vector2i(rng.randi_range(8, SIZE.x - 9), rng.randi_range(8, SIZE.y - 9))
		var radius := rng.randf_range(1.5, 3.4)
		var clear: bool = road.keys().all(func(cell: Vector2i) -> bool: return Vector2(cell).distance_to(Vector2(at)) > CLUMP_CLEAR["road"]) \
			and _to_line(Vector2(at), RIVER) > CLUMP_CLEAR["river"] \
			and _to_line(Vector2(at), LOW_SCARP) > CLUMP_CLEAR["face"] and _to_line(Vector2(at), HIGH_SCARP) > CLUMP_CLEAR["face"] \
			and absi(at.x - ROAD_X) > CLUMP_CLEAR["link"]
		if not clear or map.cell(at) not in ["grass", "dirt"]:
			continue
		for cell in _disc(at, radius):
			if map.cell(cell) in ["grass", "dirt"]:
				map.set_cell(cell, "void")
		laid += 1
	print("[foothills] %d tree clumps" % laid)


## How far along [param line] (0 to 1) it crosses column [param x].
static func _fraction(line: Array[Vector2i], x: int) -> float:
	var total := 0.0
	for i in range(1, line.size()):
		total += Vector2(line[i]).distance_to(Vector2(line[i - 1]))
	var gone := 0.0
	for i in range(1, line.size()):
		var a := Vector2(line[i - 1])
		var b := Vector2(line[i])
		if (a.x - x) * (b.x - x) <= 0.0 and a.x != b.x:
			return (gone + a.distance_to(b) * (x - a.x) / (b.x - a.x)) / total
		gone += a.distance_to(b)
	return 0.5


## The distance from [param at] to the polyline [param line].
static func _to_line(at: Vector2, line: Array[Vector2i]) -> float:
	var best := INF
	for i in range(1, line.size()):
		best = minf(best, at.distance_to(Geometry2D.get_closest_point_to_segment(at, Vector2(line[i - 1]), Vector2(line[i]))))
	return best


func _say_cliffs() -> void:
	var count := 0
	var strays: Array[Vector2i] = []
	for at: Vector2i in map.cells:
		if not map.walkable(at):
			continue
		for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			if map.walkable(at + step) and Relief.cliff_between(map.relief_at(at), map.relief_at(at + step)):
				count += 1
				if not _faces.has(Terrain.edge_key(at, step)):
					strays.append(at)
	print("[foothills] %d cliff edges, %d of them on no escarpment%s" % [count, strays.size(),
		"" if strays.is_empty() else " (east or south of %s)" % [strays.slice(0, 6)]])


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
