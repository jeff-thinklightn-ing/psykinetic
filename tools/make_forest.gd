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
## - the camps (793, maps' side; CAMPS): seven camp buildings off the paths,
##   their bands, traders and plunder; their pads and tracks cleared, the
##   grown trees on them taken out of trees.json once by hand (72).
## No monsters but the camps' bands, no buildings but the healer's and the
## camps. The same seed makes the same map.

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
## story's tag), each {at, name, and shown or explore for 804's Wayfaring: the
## name a reached place's gain shows, or false where it is no place to reach}.
## Each a short walk off a path, 20 cells at most (Jeff: "zones need to have
## safe paths with activities not too far off the paths"): the thickest
## trees 17 off, in a thick stand between the middle's paths.
const REFUGES := {
	"hunters_lean_to": {"at": Vector2i(84, 152), "name": "the hunters' lean-to"},
	"woodcutters_lean_to": {"at": Vector2i(34, 189), "name": "a woodcutters' lean-to deep in the forest", "shown": "a woodcutters' lean-to"},
	"thick_wood": {"at": Vector2i(82, 124), "name": "where the trees are thickest", "shown": "the thick of the forest"},
	"boar_path": {"at": Vector2i(100, 126), "name": "the path to the hunters' camps", "explore": false},
	"fletchers_tree": {"at": Vector2i(202, 42), "name": "the fletcher's tree"}}
## The camps (793, maps' side; forest phase C, C:/dev/review/lands/fill_forest):
## seven, each a camp building (649) on a pad cleared in the wood, 6 to 12
## cells off a path, with a short track to it, at least 24 apart. Each
## {key, centre, size small (5) or large (6), mix bandit / trader / mixed,
## name, bandits and brutes (the band standing round its fire), and what
## lies about it (decor: sacks of plunder, a trader's cart and bedroll)}.
## A bandit or mixed camp is held by the bandits (factions.json, 793), a
## traders' camp by nobody; a trader or mixed camp has a "<key>_trader"
## place by its fire (npc's: kind trader, facing the fire, rect the camp,
## bed his night cell with a bedroll); C3's trader is the bandits' captive
## ("<key>_captive", at the camp's edge). No chests (Jeff: chests are the
## dungeons'): a camp's things are on its band. Names are plain until
## lore's names are Jeff's.
const CAMPS: Array[Dictionary] = [
	{"key": "north_traders_camp", "centre": Vector2i(152, 38), "size": 5, "mix": "trader", "name": "a traders' camp"},
	{"key": "east_bandit_camp", "centre": Vector2i(190, 90), "size": 5, "mix": "bandit", "name": "a bandit camp", "bandits": 2, "brutes": 1},
	{"key": "loop_camp", "centre": Vector2i(100, 70), "size": 6, "mix": "mixed", "name": "a bandit camp", "bandits": 2, "brutes": 1, "captive": true},
	{"key": "west_bandit_camp", "centre": Vector2i(77, 94), "size": 6, "mix": "bandit", "name": "a bandit camp", "bandits": 3, "brutes": 1},
	{"key": "south_traders_camp", "centre": Vector2i(124, 145), "size": 5, "mix": "trader", "name": "a traders' camp"},
	{"key": "southwest_bandit_camp", "centre": Vector2i(51, 165), "size": 5, "mix": "bandit", "name": "a bandit camp", "bandits": 2, "brutes": 1},
	{"key": "southeast_camp", "centre": Vector2i(171, 172), "size": 6, "mix": "mixed", "name": "a bandit camp", "bandits": 2, "brutes": 1, "truce": true},
]
## Cells cleared round a camp's footprint, and the bandits' marker colours.
const CAMP_MARGIN := 2
const CAMP_LEGEND := {"monster_bandit": "#b4643c", "monster_bandit_brute": "#6e3218"}
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
	var camps := _camp_grounds()
	_trunks()
	_places()
	_camps(camps)
	_links(east, north)
	_close_pockets(east + Vector2i(-2, 0))
	var doc := MapDoc.open(FOLDER, SIZE)
	doc.map = map
	doc.config = config
	doc.map.colours = LevelMap.legend_colours(config)
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
		for extra: String in ["shown", "explore"]:
			if REFUGES[key].has(extra):
				places[key][extra] = REFUGES[key][extra]
	config["places"] = places
	var at: Vector2i = HUT["at"]
	var facing: Vector2i = HUT["facing"]
	config["buildings"] = [{"slot": "building.turf_house", "at": [at.x, at.y], "facing": [facing.x, facing.y], "code": HUT["code"]}]
	config["building_codes"] = {"H": 1}


## The camps' grounds, laid before the trunks: each camp's footprint
## (CAMPS) centred on its cell, facing the nearest path, its pad (the
## footprint and CAMP_MARGIN round it) kept clear, and a track from its
## front to that path. Returns each camp with its "rect" and "facing".
func _camp_grounds() -> Array[Dictionary]:
	var paths: Array[Vector2i] = []
	for at: Vector2i in map.cells:
		if map.cell(at) == "dirt":
			paths.append(at)
	var out: Array[Dictionary] = []
	for camp: Dictionary in CAMPS:
		var centre: Vector2i = camp["centre"]
		var size: int = camp["size"]
		var rect := Rect2i(centre - Vector2i(size / 2, size / 2), Vector2i(size, size))
		var nearest := paths[0]
		for at in paths:
			if Vector2(at - centre).length_squared() < Vector2(nearest - centre).length_squared():
				nearest = at
		var way := nearest - centre
		var facing := Vector2i(signi(way.x), 0) if absi(way.x) >= absi(way.y) else Vector2i(0, signi(way.y))
		for y in range(rect.position.y - CAMP_MARGIN, rect.end.y + CAMP_MARGIN):
			for x in range(rect.position.x - CAMP_MARGIN, rect.end.x + CAMP_MARGIN):
				_clear(Vector2i(x, y), "grass")
		var front := centre + facing * ((size + 1) / 2)
		_path(front, nearest, SEED + 100 + out.size(), 1.5)
		var laid := camp.duplicate()
		laid["rect"] = rect
		laid["facing"] = facing
		out.append(laid)
	return out


## The camps (793, maps' side) on their grounds, after the trunks: each pad
## grass again where a grown trunk stood; the camp building and its place
## at its fire (Level.camp_fire), held by the bandits or by nobody; the
## band's markers round the fire; a trader's place, bed and cart; C3's
## captive at the camp's edge; what lies about in "decor".
func _camps(camps: Array[Dictionary]) -> void:
	var legend: Dictionary = config.get("legend", {})
	legend.merge(CAMP_LEGEND)
	config["legend"] = legend
	var decor: Array = config.get("decor", [])
	for camp: Dictionary in camps:
		var rect: Rect2i = camp["rect"]
		var facing: Vector2i = camp["facing"]
		var side := Vector2i(-facing.y, facing.x)
		for y in range(rect.position.y - CAMP_MARGIN, rect.end.y + CAMP_MARGIN):
			for x in range(rect.position.x - CAMP_MARGIN, rect.end.x + CAMP_MARGIN):
				if map.cell(Vector2i(x, y)) == "void":
					map.set_cell(Vector2i(x, y), "grass")
		config["buildings"].append({"kind": "camp", "size": "small" if camp["size"] == 5 else "large",
			"at": [rect.position.x, rect.position.y], "facing": [facing.x, facing.y]})
		var fire := Level.camp_fire({"kind": "camp", "rect": rect, "facing": facing})
		# The canopy open over it (a clearing: light on the camp, its smoke out).
		config["clearings"].append({"centre": [fire.x, fire.y], "radius": camp["size"] / 2 + CAMP_MARGIN})
		var mix: String = camp["mix"]
		config["places"][camp["key"]] = {"at": [fire.x, fire.y], "kind": "camp", "radius": 4, "name": camp["name"],
			"holder": "nobody" if mix == "trader" else "bandits", "worth": 2 if camp["size"] == 6 else 1, "mix": mix}
		if camp.get("truce", false):
			config["places"][camp["key"]]["truce"] = true  # The Toll Camp's truce (799, enemy-ai's side).
		var taken: Dictionary[Vector2i, bool] = {fire: true}
		if mix != "bandit":
			var stand := fire + side
			var bed := fire + side - facing
			config["places"][camp["key"] + "_trader"] = {"at": [stand.x, stand.y], "kind": "trader", "radius": 2,
				"name": "a trader", "facing": [-side.x, -side.y], "bed": [bed.x, bed.y],
				"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]}
			var cart := fire + side * 2 + facing
			decor.append([bed.x, bed.y, -side.x, -side.y, "bedroll", 1])
			decor.append([cart.x, cart.y, facing.x, facing.y, "cart", 1])
			for cell in [stand, bed, cart]:
				taken[cell] = true
		if camp.get("captive", false):
			var stake := fire - side * (rect.size.x / 2 + 1)
			if rect.has_point(stake):
				stake -= side
			config["places"][camp["key"] + "_captive"] = {"at": [stake.x, stake.y], "kind": "captive", "radius": 1, "name": "a captive"}
			taken[stake] = true
		# The band round the fire: brutes first, at the back, then the rest.
		var spots: Array[Vector2i] = [fire - facing, fire - side, fire - facing - side, fire + facing - side,
			fire - facing + side, fire + facing, fire + facing + side, fire - side * 2]
		var band: Array[String] = []
		for i in int(camp.get("brutes", 0)):
			band.append("monster_bandit_brute")
		for i in int(camp.get("bandits", 0)):
			band.append("monster_bandit")
		for spot in spots:
			if band.is_empty():
				break
			if taken.has(spot) or not rect.has_point(spot):
				continue
			map.set_cell(spot, band.pop_front())
			taken[spot] = true
		if not band.is_empty():
			push_error("[forest] %s: no room for %d of its band" % [camp["key"], band.size()])
		# Plunder, or a trader's goods: sacks at the back of the camp.
		for i in (2 if mix != "trader" else 1):
			var sack := rect.position + Vector2i(i, 0) if facing.y > 0 else rect.end - Vector2i.ONE - Vector2i(i, 0)
			if facing.x != 0:
				sack = Vector2i(rect.position.x if facing.x > 0 else rect.end.x - 1, rect.position.y + i)
			if not taken.has(sack):
				decor.append([sack.x, sack.y, facing.x, facing.y, "sack", 1])
				taken[sack] = true
	config["decor"] = decor


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
