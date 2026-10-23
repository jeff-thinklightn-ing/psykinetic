extends Node
## Writes levels/forest, the way to the elven stronghold (decision 464), and
## its link from the wilds' east edge:
##   Godot --headless --path . res://tools/make_forest.tscn
## (a scene, not a --script run: saving parses the level, which needs the
## autoloads).
##
## 96 x 96 cells under an evergreen canopy (terrain's "canopy": its interior
## void cells drawn as tall pines), its edge an uneven band of forest:
## - grass ground, walkable everywhere but the trunks; dirt only on the path
##   (terrain's forest_grow.py tells them apart: trees stand on grass);
## - clearings (level.json "clearings": no canopy, environment's light
##   shafts) by the way in from the wilds (west), in the middle, to the
##   south, and by the way on (east);
## - a path 2 wide winding between them;
## - trunks: grown offline by terrain's tools/forest_grow.py (decision 467)
##   over what this lays, into levels/forest/trees.json; ForestPack.from_trees
##   (466) makes each tree of 3 m or more a void cell, last. Run this, then
##   forest_grow.py --level levels/forest, then this again; with no
##   trees.json (or no ForestPack yet) the map is laid without trunks;
## - the link back to the wilds on the west edge, and the way on to the
##   stronghold on the east edge, closed for now (level.json "closed").
## - the sought's refuges (613 amended) and a healer's hut (641, HEALER).
## No monsters, no buildings but the healer's. The same seed makes the same map.

const SIZE := Vector2i(96, 96)
const SEED := 452
const FOLDER := "res://levels/forest/"
const WILDS := "res://levels/wilds/"
## The wilds' row the link is on: the land's last cell on it, its arrival
## two cells in.
const WILDS_ROW := 128
## This map's link rows: west (back to the wilds) and east (on).
const WEST_ROW := 48
const EAST_ROW := 44
## The clearings, {centre, radius}; the first and last by the links.
const CLEARINGS := [
	{"centre": Vector2i(14, 48), "radius": 7},
	{"centre": Vector2i(46, 34), "radius": 8},
	{"centre": Vector2i(40, 72), "radius": 6},
	{"centre": Vector2i(80, 44), "radius": 7},
]
const PATH_WIDTH := 2
## The sought's refuges here (613 amended: one place a story, its key the
## story's tag), each {at, name}.
const REFUGES := {
	"hunters_lean_to": {"at": Vector2i(42, 72), "name": "the hunters' lean-to"},
	"woodcutters_lean_to": {"at": Vector2i(75, 15), "name": "a woodcutters' lean-to deep in the forest"},
	"thick_wood": {"at": Vector2i(25, 66), "name": "where the trees are thickest"},
	"boar_path": {"at": Vector2i(44, 60), "name": "the path to the hunters' camps"},
	"fletchers_tree": {"at": Vector2i(80, 40), "name": "the fletcher's tree"}}
## The forest's healer's hut (641, maps' side; Jeff: "multiple huts that
## offer different potions"): a building.healers_hut (its place,
## Level.BUILDING_PLACES) in the middle clearing north of the path, its
## door south toward it; its own medicine man (Main._seat_healers), what
## it makes economy's (healers_hut.makes "forest").
const HEALER := {"at": Vector2i(44, 28), "facing": Vector2i(0, 1)}
const FOREST_PACK := "res://editor/forest_pack.gd"
const TREES := "res://levels/forest/trees.json"

var map := LevelMap.new(SIZE)
var config := {"name": "The Forest", "outdoor": true, "zone": "outdoors", "border": "forest",
	"canopy": {"kind": "evergreen"}}
var keep_clear: Dictionary[Vector2i, bool] = {}


func _ready() -> void:
	var edge := _noise(SEED, 0.05)
	# The land: in from the border by 3 to 9 cells, unevenly; grass (the
	# path's dirt comes after).
	for y in SIZE.y:
		for x in SIZE.x:
			var inward := mini(mini(x, y), mini(SIZE.x - 1 - x, SIZE.y - 1 - y))
			if inward > 3 + 6.0 * (edge.get_noise_2d(x, y) * 0.5 + 0.5):
				map.set_cell(Vector2i(x, y), "grass")
	var west := _link_cell(WEST_ROW, -1)
	var east := _link_cell(EAST_ROW, 1)
	var clearings := []
	for each: Dictionary in CLEARINGS:
		for cell in _disc(each["centre"], each["radius"]):
			_clear(cell, "grass")
		clearings.append({"centre": [each["centre"].x, each["centre"].y], "radius": each["radius"]})
	config["clearings"] = clearings
	# The path: from the way in through the clearings to the way on, and a
	# branch to the south clearing.
	_path(west, CLEARINGS[0]["centre"])
	_path(CLEARINGS[0]["centre"], CLEARINGS[1]["centre"])
	_path(CLEARINGS[1]["centre"], CLEARINGS[3]["centre"])
	_path(CLEARINGS[3]["centre"], east)
	_path(CLEARINGS[1]["centre"], CLEARINGS[2]["centre"])
	_trunks()
	_places()
	_links(west, east)
	var doc := MapDoc.open(FOLDER, SIZE)
	doc.map = map
	doc.config = config
	doc.config_dirty = true
	doc.save()
	print("[forest] " + doc.report)
	_link_wilds()
	get_tree().quit()


## The land's outermost cell on [param row] going [param way] (-1 west, 1
## east): where the link marker goes.
func _link_cell(row: int, way: int) -> Vector2i:
	var at := Vector2i(0 if way < 0 else SIZE.x - 1, row)
	while map.cell(at) == "void":
		at.x -= way
	return at


## [param cell] kept clear of trunks, as ground ([param ground] where it
## was the border's void).
func _clear(cell: Vector2i, ground: String) -> void:
	if not map.in_bounds(cell):
		return
	if map.cell(cell) == "void":
		map.set_cell(cell, ground)
	keep_clear[cell] = true


## A dirt path PATH_WIDTH wide from [param from] to [param to], wavering.
func _path(from: Vector2i, to: Vector2i) -> void:
	var steps := maxi(absi(to.x - from.x), absi(to.y - from.y))
	var across := Vector2(to - from).orthogonal().normalized()
	for i in steps + 1:
		var t := float(i) / maxf(steps, 1)
		var middle := Vector2(from).lerp(Vector2(to), t) + across * sin(t * PI * 2.0) * 3.0 * sin(t * PI)
		for dx in PATH_WIDTH:
			for dy in PATH_WIDTH:
				var cell := Vector2i(roundi(middle.x), roundi(middle.y)) + Vector2i(dx, dy)
				if map.in_bounds(cell):
					if not keep_clear.has(cell) or map.cell(cell) == "grass":
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


## The refuges in "places", and the healer's hut (HEALER): its outline's
## walls and its door, the front's middle edge, in "buildings".
func _places() -> void:
	var places := {}
	for key: String in REFUGES:
		var at: Vector2i = REFUGES[key]["at"]
		places[key] = {"at": [at.x, at.y], "kind": "refuge", "where": "forest", "radius": 3, "name": REFUGES[key]["name"]}
	config["places"] = places
	var facing: Vector2i = HEALER["facing"]
	var rect := Rect2i(HEALER["at"], Level.BUILDINGS["building.healers_hut"])
	var door := Level.front_cell(rect, facing) - facing
	var cells: Array[Vector2i] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			cells.append(Vector2i(x, y))
	for key in Level.blocks_outline(cells):
		map.set_edge(key, "door" if key == Terrain.edge_key(door, facing) else "wall")
	config["buildings"] = [{"slot": "building.healers_hut", "at": [rect.position.x, rect.position.y], "facing": [facing.x, facing.y]}]


## The links: back to the wilds at [param west], on to the stronghold
## (closed) at [param east]; arrivals two cells in, the starts by the west
## one.
func _links(west: Vector2i, east: Vector2i) -> void:
	var arrival := west + Vector2i(2, 0)
	map.set_cell(west, "link")
	map.set_cell(east, "link")
	var starts := []
	for dy in [-1, 1, -2, 2]:
		var start := arrival + Vector2i(1, dy)
		map.set_cell(start, "start")
		starts.append([start.x, start.y])
	config["centre"] = [arrival.x, arrival.y]
	config["starts"] = starts
	config["spawn_points"] = {"from_wilds": [arrival.x, arrival.y], "from_stronghold": [east.x - 2, east.y]}
	config["links"] = [
		{"at": [west.x, west.y], "to_map": "wilds", "to_spawn": "from_forest"},
		{"at": [east.x, east.y], "to_map": "stronghold", "to_spawn": "from_forest", "closed": true},
	]
	config["entities"] = []


## The wilds' end: a link cell on WILDS_ROW's last land cell and its
## "from_forest" arrival two cells in, left as they are if already there.
func _link_wilds() -> void:
	var doc := MapDoc.open(WILDS)
	var at := Vector2i(doc.map.size.x - 1, WILDS_ROW)
	while doc.map.cell(at) == "void":
		at.x -= 1
	if doc.map.cell(at) != "link":
		at.x += 0
	var arrival := at - Vector2i(2, 0)
	var links: Array = doc.config.get("links", []).duplicate(true)
	if links.all(func(link: Dictionary) -> bool: return link.get("to_map") != "forest"):
		doc.apply_changes({"cells": {at: "link"}, "links": [{"at": [at.x, at.y], "to_map": "forest", "to_spawn": "from_wilds"}]})
	var points: Dictionary = doc.config.get("spawn_points", {}).duplicate()
	if not points.has("from_forest"):
		points["from_forest"] = [arrival.x, arrival.y]
		doc.set_config("spawn_points", points)
	if doc.dirty:
		doc.save()
	print("[forest] wilds: link at %s, arrival %s; %s" % [at, arrival, doc.report])


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
