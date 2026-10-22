extends Node
## Lays the wilds' landmarks over the hand-edited levels/wilds (Jeff: "wilds
## needs better land marks, in the wilds its tough to know where you are"),
## a layer a landing:
##   Godot --headless --path . res://tools/make_wilds_marks.tscn
## (a scene, not a --script run: saving parses the level, which needs the
## autoloads).
## - relief (decision 565): the ground in metres where it was flat, laid by
##   Relief.lay: a gentle roll, a long ridge across the north-east with an
##   escarpment's face looking south-west over the middle and a way up it,
##   and a broad valley from the north edge to the south; each pond level
##   under its shore. Only relief.png is written: every cell keeps its kind,
##   so whatever stands or is saved on one stays on floor. The town, the
##   links, the spawn points, the starts, the buildings and the camp stand
##   on level pads.
## - marks (decision 567): the landmarks (art-kit's slots, solid, no door)
##   placed in open ground near MARKS' spots, on level pads like any
##   building: a great tree in the west, a cairn on the ridge's back, a ring
##   of standing stones in the south-west, a waystone where the roads will
##   meet. Each goes in level.json's "buildings" (written into the file's
##   text, the rest of it as it was) once; the relief is laid again round
##   them.
## - water (decision 568): a river laid as a curve (Relief.lay "rivers")
##   down the valley from the north edge to the south, a ford across it
##   near FORD_ROW and a bridge near BRIDGE_ROW (where the hills road will
##   cross), and the ponds of POND_LEAST cells or more traced from their
##   cells into closed curves (Curves.trace), their cells then the curve's;
##   level.json "waters" and the bridge written into its text, the layout's
##   water cells and relief.png. Once: with "waters" in level.json the ponds
##   are left as they are and the river laid again the same.
## - roads (decision 569): dirt roads laid as curves (Relief.road) from the
##   castle's, the hills' and the forest's links to the crossroads round the
##   waystone, the hills road over the bridge; their cells bare dirt,
##   level.json "roads" written into its text. Once, as the water.
## - the woodlot (566 amended, npc's visible work): the town's "woodlot"
##   place at the copse south-west of it, a chopping block in it, a
##   woodpile in the store's yard. Once.
## The same seed lays the same ground.

const FOLDER := "res://levels/wilds/"
const SEED := 565
## The ground's middle, and how far the roll goes either way.
const BASE := 6.0
const ROLL := 1.5
## The ridge: its line (south-west of it the face, north-east its long back),
## how high its face, how far back its slope runs, where its way up is.
const RIDGE: Array[Vector2i] = [Vector2i(140, 30), Vector2i(178, 46), Vector2i(215, 70)]
const RIDGE_HEIGHT := 3.5
const RIDGE_BACK := 30.0
const RIDGE_WAY := 0.45
## The valley the river runs down (568), north edge to south.
const VALLEY: Array[Vector2i] = [Vector2i(62, 0), Vector2i(70, 56), Vector2i(96, 104), Vector2i(104, 168), Vector2i(118, 255)]
## The town's ground, kept level (Held's own map is undecided: 565 leaves it).
const TOWN := Rect2i(190, 190, 38, 42)
## How far round a link, a spawn point, a start, a building or a placed
## thing its pad reaches.
const PAD := 3
## The river (568): its loops' length and swing (cells), its width, its
## seed (added to SEED's); the valley's floor wide enough for its loops.
const RIVER_WAVELENGTH := 34.0
const RIVER_AMPLITUDE := 7.0
const RIVER_WIDTH: Array[float] = [2.0, 3.2]
const RIVER_SEED := 0
const RIVER_FLOOR := 11.0
## The rows the ford and the bridge cross the river nearest to.
const FORD_ROW := 40
const BRIDGE_ROW := 128
## The ford's banks walked to over this many rows either side of it.
const FORD_FREE := 4
## The roads (569): each from its link's spawn point to its end beside the
## waystone (its cell is solid), and its width.
const ROADS := [
	{"from": "from_castle", "to": Vector2i(128, 125)},
	{"from": "from_hills", "to": Vector2i(125, 128)},
	{"from": "from_forest", "to": Vector2i(131, 128)},
]
const ROAD_WIDTH := 2.0
## The woodlot (566 amended): the place's cell and reach, its chopping block,
## and the woodpile by the store (each its side cell toward the store
## walkable: (195, 225) and (196, 226) by the block, (208, 201) by the pile).
const WOODLOT := Vector2i(194, 227)
const WOODLOT_RADIUS := 4
const CHOPPING_BLOCK := Vector2i(195, 226)
const WOODPILE := Vector2i(207, 201)
## Their wander either side of the way walked, and its turns' length (cells):
## more than the hills' (Relief.ROAD_SWING), the roads long and the ground open.
const ROAD_SWING := 7.0
const ROAD_WAVE := 48.0
## A body of water this many cells or more is a pond traced into a curve
## (a well's lone cell is left).
const POND_LEAST := 6
## A pond lies this far under its lowest shore.
const POND_DEPTH := 0.3

## The marks (567): each slot near its spot, its footprint's size, how
## many cells round it must be open ground (no forest, no water).
const MARKS := [
	{"slot": "building.great_tree", "near": Vector2i(52, 140), "size": Vector2i(3, 3), "open": 8},
	{"slot": "building.cairn", "near": Vector2i(184, 40), "size": Vector2i(2, 2), "open": 5},
	{"slot": "building.waystone", "near": Vector2i(128, 128), "size": Vector2i(1, 1), "open": 4},
]
## The stone ring: its middle (sought near), its radius, how many stones.
const RING_NEAR := Vector2i(64, 196)
const RING_RADIUS := 6.0
const RING_STONES := 8

var doc: MapDoc


func _ready() -> void:
	doc = MapDoc.open(FOLDER)
	var map := doc.map
	_place_marks()
	_place_woodlot()
	var new_waters := not doc.config.has("waters")
	if not new_waters:
		_unlay_river()
	_clear_groves()
	var ponds: Array = _trace_ponds() if new_waters else []
	var laid := Relief.lay(map, Rect2i(Vector2i.ZERO, map.size), SEED, {
		"base": BASE, "amplitude": ROLL, "scale": 64.0, "octaves": 2,
		"escarpments": [{"line": RIDGE, "face": Vector2i(-1, 1), "height": RIDGE_HEIGHT, "back": RIDGE_BACK, "taper": 12.0, "ways": [RIDGE_WAY], "way_width": 5.0}],
		"valleys": [VALLEY], "valley_depth": 2.5, "valley_floor": RIVER_FLOOR, "valley_fall": 3.0, "valley_width": 26.0,
		"slope": 0.25, "streams": 0, "keep_flat": _pads(),
		"rivers": [_river_option()]})
	var size := map.size
	map.relief = PackedFloat32Array()
	map.relief.resize(size.x * size.y)
	var filled := PackedByteArray()
	filled.resize(size.x * size.y)
	for at: Vector2i in laid["relief"]:
		map.relief[at.y * size.x + at.x] = laid["relief"][at]
		filled[at.y * size.x + at.x] = 1
	# The forest and the water stand at the height of the ground beside them;
	# then each pond lies level, POND_DEPTH under its lowest shore (the
	# river falls as laid).
	LevelMap._fill_gaps(map.relief, filled, size)
	var river := {}
	for at: Vector2i in laid["cells"]:
		if laid["cells"][at] == "water":
			map.set_cell(at, "water")
			river[at] = true
	_ford(river, laid["faces"])
	var bridge := _bridge(river)
	_ponds(river)
	_check_clear(river)
	var new_roads := not doc.config.has("roads")
	var roads: Array = _roads(bridge) if new_roads else []
	var path := FOLDER + "relief.png"
	map.to_relief_image().save_png(ProjectSettings.globalize_path(path))
	LevelMap.ensure_image_import(ProjectSettings.globalize_path(path), path)
	var layout := FOLDER + "layout.png"
	map.to_image().save_png(ProjectSettings.globalize_path(layout))
	LevelMap.ensure_image_import(ProjectSettings.globalize_path(layout), layout)
	if new_waters:
		var waters: Array = laid["waters"].map(func(water: Dictionary) -> Dictionary:
			return {"points": Curves.to_json(water["points"], water["widths"])})
		waters.append_array(ponds)
		doc.config["waters"] = waters
		_write_key("waters", waters)
		if not bridge.is_empty():
			doc.config["buildings"].append(bridge)
			_write_buildings([bridge] as Array[Dictionary])
	if new_roads and not roads.is_empty():
		doc.config["roads"] = roads
		_write_key("roads", roads)
	var level := Level.parse(map.to_image(), null, doc.config, map.to_relief_image())
	print("[wilds] relief.png laid; %s" % ("nothing said" if level["warnings"].is_empty() else "; ".join(level["warnings"])))
	_say(laid["faces"])
	get_tree().quit()


## Each body of water (four-way joined water cells) but [param river]'s
## made level at POND_DEPTH under the lowest walkable cell beside it.
func _ponds(river: Dictionary) -> void:
	var map := doc.map
	var seen := river.duplicate()
	for start: Vector2i in map.cells:
		if seen.has(start) or map.cell(start) != "water":
			continue
		var body: Array[Vector2i] = [start]
		seen[start] = true
		var shore := INF
		var i := 0
		while i < body.size():
			var at := body[i]
			i += 1
			for step in Relief.FOUR:
				var next := at + step
				if seen.has(next):
					continue
				if map.cell(next) == "water":
					seen[next] = true
					body.append(next)
				elif map.walkable(next):
					shore = minf(shore, map.relief_at(next))
		if shore < INF:
			for at in body:
				map.set_relief(at, shore - POND_DEPTH)


## The woodlot (566 amended), once: the store's "woodlot" place at
## WOODLOT (WOODLOT_RADIUS round), a chopping block at CHOPPING_BLOCK in it
## and a woodpile at WOODPILE in the store's yard (npc's woodcutter stands
## on the block's side cell nearest the store, the logs land by the pile);
## the place written into level.json's "places", the two into its
## "buildings", as text.
func _place_woodlot() -> void:
	var places: Dictionary = doc.config.get("places", {})
	if places.has("woodlot"):
		return
	var place := {"at": [WOODLOT.x, WOODLOT.y], "kind": "woodlot", "holder": "town", "town": "store", "radius": WOODLOT_RADIUS, "name": "the woodlot"}
	places["woodlot"] = place
	doc.config["places"] = places
	_write_place("woodlot", place)
	var added: Array[Dictionary] = [
		{"slot": "building.chopping_block", "at": [CHOPPING_BLOCK.x, CHOPPING_BLOCK.y], "facing": [0, 1]},
		{"slot": "building.woodpile", "at": [WOODPILE.x, WOODPILE.y], "facing": [0, 1], "variant": 2}]
	(doc.config["buildings"] as Array).append_array(added)
	_write_buildings(added)
	print("[wilds] the woodlot at %s, its block at %s, the woodpile at %s" % [WOODLOT, CHOPPING_BLOCK, WOODPILE])


## [param value] written into level.json's "places" object as text, after
## its last entry (the rest of the file as it was).
func _write_place(key: String, value: Dictionary) -> void:
	var path := ProjectSettings.globalize_path(FOLDER + "level.json")
	var text := FileAccess.get_file_as_string(path)
	var start := text.find('	"places": {')
	var close := text.find("
	}", start)
	var entry := "		" + JSON.stringify(key) + ": " + JSON.stringify(value, "	", false).replace("
", "
		")
	text = text.substr(0, close) + ",
" + entry + text.substr(close)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## The marks placed, once: each landmark at the nearest cell to its spot
## whose footprint and the cells MARK "open" round it are walkable ground
## (grass or dirt, no forest, no water), off the town, the other buildings'
## ground and the ridge's face; the stones round the ring's middle, each a
## variant in turn and turned its own way. Added to doc.config (so they get
## their pads) and written into level.json's text.
func _place_marks() -> void:
	var listed: Array = doc.config.get("buildings", [])
	var have := listed.map(func(entry: Dictionary) -> String: return str(entry.get("slot", "")))
	var added: Array[Dictionary] = []
	for mark: Dictionary in MARKS:
		if mark["slot"] in have:
			continue
		var at := _open_spot(mark["near"], mark["size"], mark["open"])
		if at.x < 0:
			push_error("[wilds] no open ground for %s near %s" % [mark["slot"], mark["near"]])
			continue
		added.append({"slot": mark["slot"], "at": [at.x, at.y], "facing": [0, 1]})
	if not "building.standing_stone" in have:
		var middle := _open_spot(RING_NEAR, Vector2i.ONE * int(RING_RADIUS * 2 + 1), 3)
		if middle.x < 0:
			push_error("[wilds] no open ground for the stone ring near %s" % RING_NEAR)
		else:
			var centre := Vector2(middle) + Vector2.ONE * RING_RADIUS
			for i in RING_STONES:
				var angle := TAU * i / RING_STONES
				var cell := Vector2i((centre + Vector2.from_angle(angle) * RING_RADIUS).round())
				# Each stone's broad face to the ring's middle, a little off.
				var yaw := rad_to_deg(atan2(centre.x - cell.x, centre.y - cell.y)) + (i * 37 % 21) - 10.0
				added.append({"slot": "building.standing_stone", "at": [cell.x, cell.y], "facing": [0, 1], "variant": 1 + i % 3, "yaw": snappedf(yaw, 1.0)})
	if added.is_empty():
		return
	listed.append_array(added)
	doc.config["buildings"] = listed
	_write_buildings(added)
	print("[wilds] marks placed: %s" % [added.map(func(entry: Dictionary) -> String: return "%s at %s" % [entry["slot"], entry["at"]])])


## The nearest cell to [param near] (searching outward) where a [param size]
## footprint and [param open] cells round it are all walkable ground (grass
## or dirt), clear of the town, other buildings and the ridge's face; (-1, -1)
## if none within 30 cells.
func _open_spot(near: Vector2i, size: Vector2i, open: int) -> Vector2i:
	var map := doc.map
	var taken: Array[Rect2i] = [TOWN]
	for entry: Dictionary in doc.config.get("buildings", []):
		var rect: Variant = Level.building_rect(entry)
		if rect != null:
			taken.append((rect as Rect2i).grow(PAD + 2))
	for reach in 31:
		for y in range(near.y - reach, near.y + reach + 1):
			for x in range(near.x - reach, near.x + reach + 1):
				if maxi(absi(x - near.x), absi(y - near.y)) != reach:
					continue
				var rect := Rect2i(Vector2i(x, y), size)
				var round := rect.grow(open)
				if taken.any(func(other: Rect2i) -> bool: return other.intersects(round)):
					continue
				if Relief._distance_to_line(rect.get_center(), RIDGE) < open + 3:
					continue
				var clear := true
				for cy in range(round.position.y, round.end.y):
					for cx in range(round.position.x, round.end.x):
						if map.cell(Vector2i(cx, cy)) not in ["grass", "dirt"]:
							clear = false
							break
					if not clear:
						break
				if clear:
					return Vector2i(x, y)
	return Vector2i(-1, -1)


## [param added] (building entries) written into level.json's "buildings"
## list as text, after its last entry: the rest of the file (its numbers,
## its order) as it was.
func _write_buildings(added: Array[Dictionary]) -> void:
	var path := ProjectSettings.globalize_path(FOLDER + "level.json")
	var text := FileAccess.get_file_as_string(path)
	var start := text.find('	"buildings": [')
	var close := text.find("
	]", start)
	var lines: Array[String] = []
	for entry in added:
		lines.append("		" + JSON.stringify(entry, "	", false).replace("
", "
		"))
	text = text.substr(0, close) + ",
" + ",
".join(lines) + text.substr(close)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## The groves (void inside the land, not joined to the forest round it)
## under the river's curve (Relief.river_curve, what lay will lay) and a
## cell round it made grass, so the river runs on unbroken (its cells are
## laid only on the ground); the forest round the land is left, the river
## running on unseen under it at the edges.
func _clear_groves() -> void:
	var map := doc.map
	var made := Relief.river_curve(_river_option(), SEED + 10 + RIVER_SEED)
	var raster := Curves.cells(Curves.sample(made["points"], made["widths"]), false)
	var border := {}
	var queue: Array[Vector2i] = []
	for i in map.size.x:
		for at: Vector2i in [Vector2i(i, 0), Vector2i(i, map.size.y - 1)]:
			if map.cell(at) == "void" and not border.has(at):
				border[at] = true
				queue.append(at)
	for i in map.size.y:
		for at: Vector2i in [Vector2i(0, i), Vector2i(map.size.x - 1, i)]:
			if map.cell(at) == "void" and not border.has(at):
				border[at] = true
				queue.append(at)
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		for step in Relief.FOUR:
			var next: Vector2i = at + step
			if map.in_bounds(next) and not border.has(next) and map.cell(next) == "void":
				border[next] = true
				queue.append(next)
	var cleared := 0
	for cell: Vector2i in raster:
		for y in range(-1, 2):
			for x in range(-1, 2):
				var near: Vector2i = cell + Vector2i(x, y)
				if map.in_bounds(near) and map.cell(near) == "void" and not border.has(near):
					map.set_cell(near, "grass")
					cleared += 1
	print("[wilds] groves cleared under the river: %d cells" % cleared)


## The river level.json has made ground again (its water and ford cells
## grass), so the lay carves it again as it was: a layer laid again over
## the water once laid (569 over 568).
func _unlay_river() -> void:
	var map := doc.map
	var made := Relief.river_curve(_river_option(), SEED + 10 + RIVER_SEED)
	for cell: Vector2i in Curves.cells(Curves.sample(made["points"], made["widths"]), false):
		if map.cell(cell) in ["water", "ford"]:
			map.set_cell(cell, "grass")


## The river's Relief.lay "rivers" entry.
func _river_option() -> Dictionary:
	return {"line": VALLEY, "wavelength": RIVER_WAVELENGTH, "amplitude": RIVER_AMPLITUDE, "width": RIVER_WIDTH, "seed": RIVER_SEED}


## Each pond of POND_LEAST cells or more traced into a closed curve
## (Curves.trace) and its cells made the curve's (Curves.laid: inside it on
## the ground or the water, water; the old water outside it grass), as
## level.json "waters" entries.
func _trace_ponds() -> Array:
	var map := doc.map
	var out: Array = []
	var seen := {}
	for start: Vector2i in map.cells:
		if seen.has(start) or map.cell(start) != "water":
			continue
		var body := {start: true}
		seen[start] = true
		var queue: Array[Vector2i] = [start]
		while not queue.is_empty():
			var at: Vector2i = queue.pop_back()
			for step in Relief.FOUR:
				var next: Vector2i = at + step
				if not seen.has(next) and map.cell(next) == "water":
					seen[next] = true
					body[next] = true
					queue.append(next)
		if body.size() < POND_LEAST:
			continue
		var points := Curves.trace(body)
		var widths := PackedFloat32Array()
		widths.resize(points.size())
		var ground := {}
		for cell: Vector2i in body:
			for y in range(-3, 4):
				for x in range(-3, 4):
					var near: Vector2i = cell + Vector2i(x, y)
					if map.cell(near) in ["grass", "dirt", "water"]:
						ground[near] = true
		var inside: Dictionary = Curves.laid(Curves.sample(points, widths, true), true, ground)["cells"]
		for cell: Vector2i in body:
			if not inside.has(cell):
				map.set_cell(cell, "grass")
		for cell: Vector2i in inside:
			map.set_cell(cell, "water")
		out.append({"points": Curves.to_json(points, widths), "closed": true})
		print("[wilds] pond at %s: %d cells traced into %d points, %d cells now" % [start, body.size(), points.size(), inside.size()])
	return out


## The ford: [param river]'s cells on the row nearest FORD_ROW it crosses
## straight, 1 to 3 wide; its banks set a walk over the water and the
## ground round them brought down to them (Relief._limit, the ridge's
## [param faces] kept; the ground off its reach held), the river's other
## banks kept (make_hills' ford).
func _ford(river: Dictionary, faces: Dictionary) -> void:
	var map := doc.map
	var across := _crossing(river, FORD_ROW, true)
	if across.is_empty():
		push_error("[wilds] no ford")
		return
	for at in across:
		map.set_cell(at, "ford")
	var surface := map.relief_at(across[0])
	var heights := {}
	var fixed := {}
	var wet := {}
	for at: Vector2i in map.cells:
		if map.walkable(at) or map.cell(at) == "water":
			heights[at] = map.relief_at(at)
	for at: Vector2i in heights:
		if absi(at.y - across[0].y) > FORD_FREE + 8 or absi(at.x - across[0].x) > 16:
			fixed[at] = true
	for at: Vector2i in river:
		fixed[at] = true
		if map.cell(at) == "water":
			wet[at] = true
		for step: Vector2i in Relief.FOUR:
			if heights.has(at + step) and not river.has(at + step) and absi(at.y - across[0].y) > FORD_FREE:
				fixed[at + step] = true
	for bank: Vector2i in [across[0] - Vector2i(1, 0), across[across.size() - 1] + Vector2i(1, 0)]:
		heights[bank] = surface + 0.3
		fixed[bank] = true
	Relief._limit(heights, fixed, wet, Relief.LAY_SLOPE, faces)
	for at: Vector2i in heights:
		map.set_relief(at, heights[at])
	print("[wilds] the ford: %s" % [across])


## The bridge over [param river] on the row nearest BRIDGE_ROW: its banks
## levelled at the higher of them; its building entry, or {} if none.
func _bridge(river: Dictionary) -> Dictionary:
	var map := doc.map
	var across := _crossing(river, BRIDGE_ROW, false)
	if across.is_empty():
		push_error("[wilds] no bridge")
		return {}
	var west := across[0]
	var banks: Array[Vector2i] = [west - Vector2i(1, 0), across[across.size() - 1] + Vector2i(1, 0)]
	var top := maxf(map.relief_at(banks[0]), map.relief_at(banks[1]))
	for bank in banks:
		map.set_relief(bank, top)
	print("[wilds] the bridge: %s" % [across])
	return {"slot": "bridge", "at": [west.x, west.y], "facing": [1, 0], "length": across.size()}


## The river's water cells on the row nearest [param row] that it crosses
## 1 to 3 wide, west to east, with walkable ground either side (where it
## runs [param straight] and level, for a ford: water on the same columns a
## row either way, within 0.25 m).
func _crossing(river: Dictionary, row: int, straight: bool) -> Array[Vector2i]:
	var map := doc.map
	for offset in 60:
		for y: int in [row + offset, row - offset]:
			var cells: Array[Vector2i] = []
			for x in map.size.x:
				if river.has(Vector2i(x, y)) and map.cell(Vector2i(x, y)) == "water":
					cells.append(Vector2i(x, y))
			if cells.is_empty() or cells.size() > 3 or cells[-1].x - cells[0].x != cells.size() - 1:
				continue
			if not map.walkable(cells[0] - Vector2i(1, 0)) or not map.walkable(cells[-1] + Vector2i(1, 0)):
				continue
			if straight:
				var surface := map.relief_at(cells[0])
				var level := true
				for cell in cells:
					for side: Vector2i in [Vector2i(0, -1), Vector2i(0, 1)]:
						level = level and river.has(cell + side) and absf(map.relief_at(cell + side) - surface) <= 0.25
				if not level:
					continue
			return cells
	return []


## The roads (569): each of ROADS laid by Relief.road from its link's spawn
## point to its end by the waystone, the bridge's cells its crossings (by
## [param bridge], or the one level.json has); their cells made bare dirt
## where they are grass. As level.json "roads" entries.
func _roads(bridge: Dictionary) -> Array:
	var map := doc.map
	var crossings := {}
	var entry := bridge
	if entry.is_empty():
		for listed: Dictionary in doc.config.get("buildings", []):
			if str(listed.get("slot", "")) == "bridge":
				entry = listed
	if not entry.is_empty():
		for i in int(entry["length"]):
			crossings[Vector2i(int(entry["at"][0]) + i, int(entry["at"][1]))] = true
	var spawns: Dictionary = doc.config.get("spawn_points", {})
	var out: Array = []
	for road: Dictionary in ROADS:
		var from := _cell(spawns[road["from"]])
		var laid := Relief.road(map, from, [], road["to"], ROAD_WIDTH, crossings, ROAD_SWING, ROAD_WAVE)
		if laid.is_empty():
			push_error("[wilds] no way for the road from %s" % road["from"])
			continue
		for cell: Vector2i in laid["cells"]:
			if map.cell(cell) == "grass":
				map.set_cell(cell, "dirt")
		out.append({"points": Curves.to_json(laid["points"], laid["widths"]), "kind": "dirt"})
		print("[wilds] the road %s: %d control points, %d cells" % [road["from"], laid["points"].size(), laid["cells"].size()])
	return out


## Says whether [param river] touches a pad (the town, a link, a spawn
## point, a start, a building, the camp): it must not.
func _check_clear(river: Dictionary) -> void:
	var touched := []
	for pad: Rect2i in _pads():
		for at: Vector2i in river:
			if pad.has_point(at):
				touched.append(pad)
				break
	print("[wilds] the river: %d cells; %s" % [river.size(), "clear of every pad" if touched.is_empty() else "TOUCHES %s" % [touched]])


## [param value] written into level.json's text as top-level [param key]
## before its closing brace (the rest of the file as it was).
func _write_key(key: String, value: Variant) -> void:
	var path := ProjectSettings.globalize_path(FOLDER + "level.json")
	var text := FileAccess.get_file_as_string(path)
	var close := text.rfind("}")
	var body := text.substr(0, close).rstrip("\n\t ")
	text = body + ",\n\t" + JSON.stringify(key) + ": " + JSON.stringify(value, "\t", false).replace("\n", "\n\t") + "\n}\n"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## The level pads: the town; round each link, spawn point, start, building
## and camp (a monster's gathering point), PAD cells. Things lying on the
## ground (a kit, a chest) need none.
func _pads() -> Array:
	var pads: Array = [TOWN]
	var spots: Array[Vector2i] = []
	for link: Dictionary in doc.config.get("links", []):
		spots.append(_cell(link["at"]))
	for at: Variant in (doc.config.get("spawn_points", {}) as Dictionary).values():
		spots.append(_cell(at))
	for at: Variant in doc.config.get("starts", []):
		spots.append(_cell(at))
	for entity: Dictionary in doc.config.get("entities", []):
		if entity.has("idle") and entity["idle"].has("point"):
			spots.append(_cell(entity["idle"]["point"]))
	var ring := Rect2i()
	for building: Dictionary in doc.config.get("buildings", []):
		var slot := str(building.get("slot", ""))
		if slot in Level.SPANS_WATER:
			continue  # A bridge spans the river; its banks are levelled apart.
		if slot in Level.SOLID and not slot in Level.DOORLESS:
			# A mound (579: 12 x 12): its footprint and a cell round it.
			pads.append((Level.building_rect(building) as Rect2i).grow(1))
		elif not slot in Level.DOORLESS:
			spots.append(_cell(building["at"]) + Vector2i(2, 2))
		elif slot == "building.standing_stone":
			# The stone ring is one pad, so no step lies between two stones.
			var stone: Rect2i = Level.building_rect(building)
			ring = stone if ring.size == Vector2i.ZERO else ring.merge(stone)
		else:
			# A landmark's own footprint and a cell round it.
			pads.append((Level.building_rect(building) as Rect2i).grow(1))
	# A solid building's pad (579: the mound) holds its door and the spawn
	# by it level; their own pads, at their own height, would break it.
	var solid_pads: Array[Rect2i] = []
	for building: Dictionary in doc.config.get("buildings", []):
		var slot := str(building.get("slot", ""))
		if slot in Level.SOLID and not slot in Level.DOORLESS:
			solid_pads.append((Level.building_rect(building) as Rect2i).grow(2))
	for spot in spots:
		var pad := Rect2i(spot - Vector2i(PAD, PAD), Vector2i(PAD * 2 + 1, PAD * 2 + 1))
		if solid_pads.any(func(solid: Rect2i) -> bool: return solid.intersects(pad.grow(1))):
			continue
		pads.append(pad)
	if ring.size != Vector2i.ZERO:
		pads.append(ring.grow(1))
	return pads


func _cell(at: Variant) -> Vector2i:
	return Vector2i(int(at[0]), int(at[1]))


## Says the cliff edges the relief has: the ridge's face is meant, any other
## is a stray (named).
func _say(faces: Dictionary) -> void:
	var map := doc.map
	var count := 0
	var strays: Array[Vector2i] = []
	for at: Vector2i in map.cells:
		if not map.walkable(at):
			continue
		for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			if map.walkable(at + step) and Relief.cliff_between(map.relief_at(at), map.relief_at(at + step)):
				count += 1
				if not faces.has(Terrain.edge_key(at, step)):
					strays.append(at)
	print("[wilds] %d cliff edges, %d on no face%s" % [count, strays.size(), "" if strays.is_empty() else " (%s)" % [strays.slice(0, 6)]])
