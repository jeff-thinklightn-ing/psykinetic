extends Node
## Writes levels/held, the map of the town Umbrage (named "Held" until Jeff
## named the town, 2026-10-24: the id stays held; decision 651, step 1; Jeff's
## layout, C:/dev/review/held/held_jeff.png), and its link from the wilds:
##   Godot --headless --path . res://tools/make_held.tscn
## (a scene, not a --script run: saving parses the level, which needs the
## autoloads).
##
## 192 x 192 cells under the sky, forest round everything (void, drawn as
## trees; felled as the town takes wood, 591):
## - a river down the west (Relief.lay "rivers", 559) along x 34..44, its
##   banks kept clear through the forest, crossed by a ford to the north
##   (FORD_ROW) and a bridge by the town (BRIDGE_ROW);
## - the Old Tower across it (600: the old_tower prefab stamped at FORT, its
##   place, its counter), in its own clearing on a levelled pad, the bridge
##   road at its east gate and the ford path at its north-east breach;
## - the town's core, cleared ground (rough at its edge) with the store's
##   cell reserved (STORE, a levelled pad, nothing on it): no houses, the
##   town's settlement is laid there when the town moves (651's step 2);
## - farms and pasture east of it, cleared grass, and the gate road on east
##   to the wilds' link at the east edge (LINK_ROW: Held lies west of the
##   wilds on the world plane, under the hills, so the link is where the
##   wilds' west edge still has land);
## - a fishing spot's clearing by the bridge road, south of it.
## Nothing lives here yet: the town, its people, the barrow and Snagfin stay
## in the wilds until step 2. The same seed makes the same map.

const SIZE := Vector2i(192, 192)
const SEED := 651
const FOLDER := "res://levels/held/"
const WILDS := "res://levels/wilds/"
## The wilds' row its end of the link is on (the land's first cell from the
## west edge, the arrival two cells in), and Held's: WILDS_ROW less Held's
## origin's row on the world plane (levels/world_plane.json, -192 x 156).
const WILDS_ROW := 236
const LINK_ROW := 80
## The river's line, north to south.
const RIVER: Array[Vector2i] = [Vector2i(40, 0), Vector2i(37, 48), Vector2i(41, 96), Vector2i(38, 144), Vector2i(40, 191)]
## Land kept either side of the river's line through the forest, wavering
## by up to RIVER_BANKS_WAVER either way.
const RIVER_BANKS := 7.0
const RIVER_BANKS_WAVER := 3.5
## The rows the ford and the bridge cross the river nearest to.
const FORD_ROW := 75
const BRIDGE_ROW := 94
## The ford's banks are walked to over this many rows either side of it.
const FORD_FREE := 4
## The Old Tower: the prefab's top-left (600); outside its east gate (the
## bridge road's end) and its north-east breach (the ford path's).
const FORT := Vector2i(14, 86)
const FORT_GATE := Vector2i(31, 94)
const FORT_BREACH := Vector2i(27, 85)
## The store's cell, reserved for the town's move (step 2), and its pad.
const STORE := Vector2i(100, 96)
const STORE_PAD := 4
## The ford path's end in the core.
const CORE_NW := Vector2i(82, 84)
## The clearings: {centre, radii}, each edge wavering by CLEARING_WAVER of
## its radius. The core, the farms, the neck to the link, the fort's, the
## fishing spot's, and the lanes between (the bridge road's, the ford path's).
const CLEARINGS: Array[Dictionary] = [
	{"centre": Vector2(100, 96), "radii": Vector2(28, 24)},
	{"centre": Vector2(148, 90), "radii": Vector2(36, 18)},
	{"centre": Vector2(180, 82), "radii": Vector2(14, 9)},
	{"centre": Vector2(22, 94), "radii": Vector2(15, 15)},
	{"centre": Vector2(53, 104), "radii": Vector2(8, 7)},
	{"centre": Vector2(60, 95), "radii": Vector2(18, 5)},
	{"centre": Vector2(62, 79), "radii": Vector2(22, 5)}]
const CLEARING_WAVER := 0.15
## The core's middle, bare of rough ground out to this share of its radii.
const CORE_SMOOTH := 0.6
const ROAD_WIDTH := 2.0

var map := LevelMap.new(SIZE)
var config := {"name": "Umbrage", "outdoor": true, "zone": "outdoors", "region": "town_lands", "border": "forest"}
var _ford_row := -100
var _faces: Dictionary = {}


func _ready() -> void:
	var waver := _noise(SEED, 0.08)
	var rough := _noise(SEED + 1, 0.09)
	var banks := _noise(SEED + 2, 0.06)
	for y in SIZE.y:
		for x in SIZE.x:
			var at := Vector2i(x, y)
			if _in_clearing(Vector2(at), waver) or absf(x - _river_x(y)) <= RIVER_BANKS + RIVER_BANKS_WAVER * banks.get_noise_2d(x, y):
				map.set_cell(at, "grass")
	var arrival := _link()
	var fort_pad := Rect2i(FORT - Vector2i.ONE, Vector2i(19, 19))
	var store_pad := Rect2i(STORE - Vector2i(STORE_PAD, STORE_PAD), Vector2i(STORE_PAD * 2 + 1, STORE_PAD * 2 + 1))
	var laid := Relief.lay(map, Rect2i(Vector2i.ZERO, SIZE), SEED, {
		"base": 6.0, "amplitude": 1.2, "scale": 80.0, "octaves": 2, "tilt": Vector2.ZERO,
		"slope": 0.3, "steep_bands": 0.3, "rock_step": Relief.MAX_M, "dirt_step": 0.33,
		"valleys": [RIVER], "valley_depth": 2.0, "valley_floor": 6.0, "valley_fall": 1.5, "valley_width": 24.0, "kinds": true, "min_flow": 30,
		"keep_flat": [Rect2i(arrival - Vector2i(3, 3), Vector2i(5, 7)), fort_pad, store_pad],
		"streams": 0, "keep_clear": {},
		"rivers": [{"line": RIVER, "wavelength": 30.0, "amplitude": 3.0, "width": [1.8, 3.0], "seed": 0}]})
	map.relief = PackedFloat32Array()
	map.relief.resize(SIZE.x * SIZE.y)
	var filled := PackedByteArray()
	filled.resize(SIZE.x * SIZE.y)
	for at: Vector2i in laid["relief"]:
		map.relief[at.y * SIZE.x + at.x] = laid["relief"][at]
		filled[at.y * SIZE.x + at.x] = 1
	# The forest stands at its edge's height.
	LevelMap._fill_gaps(map.relief, filled, SIZE)
	for at: Vector2i in laid["cells"]:
		map.set_cell(at, laid["cells"][at])
	config["waters"] = laid["waters"].map(_water_json)
	var water := {}
	for at: Vector2i in laid["cells"]:
		if laid["cells"][at] == "water":
			water[at] = true
	_faces = laid["faces"]
	_rough(rough)
	_ford(water)
	_bridge(water)
	_stamp_fort()
	_roads(arrival)
	_soften()
	var doc := MapDoc.open(FOLDER, SIZE)
	doc.map = map
	doc.config = config
	doc.config_dirty = true
	doc.relief_dirty = true
	doc.heights_dirty = false
	doc.had_heights = false
	doc.save()
	print("[held] " + doc.report)
	_link_wilds(map.relief_at(_link_cell()))
	get_tree().quit()


static func _water_json(water: Dictionary) -> Dictionary:
	return {"points": Curves.to_json(water["points"], water["widths"])}


## The river's line's column at row [param y] (RIVER, straight between its
## points; the laid river loops either side of it).
static func _river_x(y: float) -> float:
	for i in range(1, RIVER.size()):
		if y <= RIVER[i].y:
			var a := Vector2(RIVER[i - 1])
			var b := Vector2(RIVER[i])
			return lerpf(a.x, b.x, (y - a.y) / maxf(b.y - a.y, 1.0))
	return float(RIVER[-1].x)


## Whether [param at] is inside one of CLEARINGS, its edge wavering.
static func _in_clearing(at: Vector2, waver: FastNoiseLite) -> bool:
	for each: Dictionary in CLEARINGS:
		var off: Vector2 = (at - each["centre"]) / each["radii"]
		if off.length() <= 1.0 + CLEARING_WAVER * waver.get_noise_2dv(at):
			return true
	return false


## Rough ground round the core's middle (stumps and scrub: bare dirt in
## patches), its middle and the store's pad left grass.
func _rough(noise: FastNoiseLite) -> void:
	var core: Dictionary = CLEARINGS[0]
	for at: Vector2i in map.cells:
		if map.cell(at) != "grass":
			continue
		var off: Vector2 = (Vector2(at) - core["centre"]) / core["radii"]
		if off.length() > CORE_SMOOTH and off.length() <= 1.2 and noise.get_noise_2dv(Vector2(at)) > 0.25:
			map.set_cell(at, "dirt")


## The ford: the river's cells on the row nearest FORD_ROW it crosses
## straight and level, its banks set a walk over its water and the ground
## round them brought down to them (Relief._limit), its other banks kept.
func _ford(water: Dictionary) -> void:
	var across := _crossing(water, FORD_ROW, true)
	if across.is_empty():
		push_error("[held] no ford")
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
			if heights.has(at + step) and not water.has(at + step) and absi(at.y - across[0].y) > FORD_FREE:
				fixed[at + step] = true
	for bank: Vector2i in [across[0] - Vector2i(1, 0), across[across.size() - 1] + Vector2i(1, 0)]:
		heights[bank] = surface + 0.3
		fixed[bank] = true
	Relief._limit(heights, fixed, wet, Relief.LAY_SLOPE, _faces)
	for at: Vector2i in heights:
		map.set_relief(at, heights[at])
	print("[held] the ford at %s" % [across])


## The bridge over the river on the row nearest BRIDGE_ROW: its banks
## levelled at the higher of them.
func _bridge(water: Dictionary) -> void:
	var across := _crossing(water, BRIDGE_ROW)
	if across.is_empty():
		push_error("[held] no bridge")
		return
	var west := across[0]
	var east := across[across.size() - 1]
	var banks: Array[Vector2i] = [west - Vector2i(1, 0), east + Vector2i(1, 0)]
	var top := maxf(map.relief_at(banks[0]), map.relief_at(banks[1]))
	for bank in banks:
		map.set_relief(bank, top)
	config["buildings"] = [{"slot": "bridge", "at": [west.x, west.y], "facing": [1, 0], "length": across.size()}]
	print("[held] the bridge at %s" % [across])


## The water cells of the row nearest [param row] that the river crosses
## with water only, west to east, one to three of them (where it runs
## [param straight] and level, for a ford), away from the ford's row.
func _crossing(water: Dictionary, row: int, straight := false) -> Array[Vector2i]:
	for offset in range(0, SIZE.y):
		for y in [row + offset, row - offset]:
			if y < 0 or y >= SIZE.y or absi(y - _ford_row) <= 6:
				continue
			var cells: Array[Vector2i] = []
			for x in SIZE.x:
				if water.has(Vector2i(x, y)) and map.cell(Vector2i(x, y)) == "water":
					cells.append(Vector2i(x, y))
			if cells.size() >= 1 and cells.size() <= 3 and cells[cells.size() - 1].x - cells[0].x == cells.size() - 1 \
					and (not straight or _straight(water, cells)):
				return cells
	return []


## Whether the river runs straight through [param cells] (water on the
## same columns a row either way) and nearly level.
func _straight(water: Dictionary, cells: Array[Vector2i]) -> bool:
	var surface := map.relief_at(cells[0])
	for cell in cells:
		for side: Vector2i in [Vector2i(0, -1), Vector2i(0, 1)]:
			if not water.has(cell + side) or absf(map.relief_at(cell + side) - surface) > 0.25:
				return false
	return true


## The Old Tower (600): the old_tower prefab stamped with its top-left at
## FORT, its cells, edges, counter, buildings and place joining the map's,
## the place working for no town (the town is still the wilds').
func _stamp_fort() -> void:
	var prefab := Prefab.load_prefab("old_tower")
	var changes := Prefab.stamp_changes(prefab, map, FORT, config)
	for cell: Vector2i in changes["cells"]:
		map.set_cell(cell, changes["cells"][cell])
	for key: Vector3i in changes["edges"]:
		map.set_edge(key, changes["edges"][key])
	config["entities"] = (config.get("entities", []) as Array) + changes["entries"]
	var named: Dictionary = changes.get("config", {})
	for key: String in named:
		config[key] = named[key]
	# Its place works for no town yet: the town and its store are still the
	# wilds' (step 2 gives it back its "town" when the town moves here).
	(config["places"]["old_tower"] as Dictionary).erase("town")


## The roads (563), dirt, as curves (Relief.road): the gate road from the
## link's arrival over the bridge to the Old Tower's gate; the ford path
## from its breach over the ford to the core.
func _roads(arrival: Vector2i) -> void:
	var bridge: Dictionary = config["buildings"][0]
	var west := Vector2i(int(bridge["at"][0]), int(bridge["at"][1]))
	var length := int(bridge["length"])
	var crossings := {}
	for i in length:
		crossings[west + Vector2i(i, 0)] = true
	var ford := _ford_cells()
	var roads := []
	var plans: Array[Array] = [
		[arrival, [west + Vector2i(length, 0), west - Vector2i(1, 0)], FORT_GATE, crossings],
		[FORT_BREACH, [ford[0] - Vector2i(1, 0), ford[-1] + Vector2i(1, 0)] if not ford.is_empty() else [], CORE_NW, {}]]
	for plan in plans:
		var laid := Relief.road(map, plan[0], plan[1], plan[2], ROAD_WIDTH, plan[3])
		if laid.is_empty():
			push_error("[held] no way for the road from %s to %s" % [plan[0], plan[2]])
			continue
		for cell: Vector2i in laid["cells"]:
			if map.cell(cell) in ["grass", "dirt"]:
				map.set_cell(cell, "dirt")
		roads.append({"points": Curves.to_json(laid["points"], laid["widths"]), "kind": "dirt"})
		print("[held] a road from %s to %s: %d cells" % [plan[0], plan[2], laid["cells"].size()])
	config["roads"] = roads


func _ford_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in SIZE.x:
		if map.cell(Vector2i(x, _ford_row)) == "ford":
			out.append(Vector2i(x, _ford_row))
	return out


## The land's outermost cell on LINK_ROW at the east edge.
func _link_cell() -> Vector2i:
	var link := Vector2i(SIZE.x - 1, LINK_ROW)
	while map.cell(link) in ["void", ""]:
		link.x -= 1
	return link


## The link to the wilds on the east edge at LINK_ROW, its arrival two
## cells in, the starts round that; the arrival.
func _link() -> Vector2i:
	var link := _link_cell()
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
	config["links"] = [{"at": [link.x, link.y], "to_map": "wilds", "to_spawn": "from_held"}]
	config["entities"] = []
	return arrival


## The wilds' end: a link cell on WILDS_ROW's first land cell from the west
## and its "from_held" arrival two cells in, written into the layout's
## pixel and level.json's text (the rest of the wilds as it is: it is
## hand-edited, and saving it whole would trace it again), once. Says the
## height the world plane wants for Held (the wilds' ground at its link
## less Held's at [param held_ground]'s link).
func _link_wilds(held_ground: float) -> void:
	var doc := MapDoc.open(WILDS)
	var at := Vector2i(0, WILDS_ROW)
	while doc.map.cell(at) == "void":
		at.x += 1
	var arrival := at + Vector2i(2, 0)
	print("[held] world plane: held's height %.2f (the wilds' ground %.2f at %s, Held's %.2f)" % [
		doc.map.relief_at(at) - held_ground, doc.map.relief_at(at), at, held_ground])
	var path := ProjectSettings.globalize_path(WILDS + "level.json")
	var text := FileAccess.get_file_as_string(path)
	if text.contains("\"to_map\": \"held\""):
		print("[held] wilds: its link is there already, at %s" % [at])
		return
	var link := {"at": [at.x, at.y], "to_map": "held", "to_spawn": "from_wilds"}
	var links_at := text.find("\t\"links\": [")
	var links_close := text.find("\n\t]", links_at)
	text = text.substr(0, links_close) + ",\n\t\t" + JSON.stringify(link, "\t", false).replace("\n", "\n\t\t") + text.substr(links_close)
	var points_at := text.find("\t\"spawn_points\": {")
	var points_close := text.find("\n\t}", points_at)
	text = text.substr(0, points_close) + ",\n\t\t\"from_held\": " + JSON.stringify([arrival.x, arrival.y], "\t", false).replace("\n", "\n\t\t") + text.substr(points_close)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var image := Image.load_from_file(ProjectSettings.globalize_path(WILDS + "layout.png"))
	image.set_pixel(at.x * 2, at.y * 2, Color(str(Level.LEGEND["link"])))
	image.save_png(ProjectSettings.globalize_path(WILDS + "layout.png"))
	print("[held] wilds: link at %s, arrival %s" % [at, arrival])


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


## Relief.soften_low_steps over the map as it now stands (585).
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
