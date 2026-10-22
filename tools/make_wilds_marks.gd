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
## The valley the river will run down (layer two), north edge to south.
const VALLEY: Array[Vector2i] = [Vector2i(62, 0), Vector2i(70, 56), Vector2i(96, 104), Vector2i(104, 168), Vector2i(118, 255)]
## The town's ground, kept level (Held's own map is undecided: 565 leaves it).
const TOWN := Rect2i(190, 190, 38, 42)
## How far round a link, a spawn point, a start, a building or a placed
## thing its pad reaches.
const PAD := 3
## A pond lies this far under its lowest shore.
const POND_DEPTH := 0.3

var doc: MapDoc


func _ready() -> void:
	doc = MapDoc.open(FOLDER)
	var map := doc.map
	var laid := Relief.lay(map, Rect2i(Vector2i.ZERO, map.size), SEED, {
		"base": BASE, "amplitude": ROLL, "scale": 64.0, "octaves": 2,
		"escarpments": [{"line": RIDGE, "face": Vector2i(-1, 1), "height": RIDGE_HEIGHT, "back": RIDGE_BACK, "taper": 12.0, "ways": [RIDGE_WAY], "way_width": 5.0}],
		"valleys": [VALLEY], "valley_depth": 2.5, "valley_floor": 6.0, "valley_fall": 3.0, "valley_width": 26.0,
		"slope": 0.25, "streams": 0, "keep_flat": _pads()})
	var size := map.size
	map.relief = PackedFloat32Array()
	map.relief.resize(size.x * size.y)
	var filled := PackedByteArray()
	filled.resize(size.x * size.y)
	for at: Vector2i in laid["relief"]:
		map.relief[at.y * size.x + at.x] = laid["relief"][at]
		filled[at.y * size.x + at.x] = 1
	# The forest and the water stand at the height of the ground beside them;
	# then each pond lies level, POND_DEPTH under its lowest shore.
	LevelMap._fill_gaps(map.relief, filled, size)
	_ponds()
	# relief.png alone: the layout and level.json are left as they are.
	var path := FOLDER + "relief.png"
	map.to_relief_image().save_png(ProjectSettings.globalize_path(path))
	LevelMap.ensure_image_import(ProjectSettings.globalize_path(path), path)
	var level := Level.parse(map.to_image(), null, doc.config, map.to_relief_image())
	print("[wilds] relief.png laid; %s" % ("nothing said" if level["warnings"].is_empty() else "; ".join(level["warnings"])))
	_say(laid["faces"])
	get_tree().quit()


## Each body of water (four-way joined water cells) made level at
## POND_DEPTH under the lowest walkable cell beside it.
func _ponds() -> void:
	var map := doc.map
	var seen := {}
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
	for building: Dictionary in doc.config.get("buildings", []):
		spots.append(_cell(building["at"]) + Vector2i(2, 2))
	for spot in spots:
		pads.append(Rect2i(spot - Vector2i(PAD, PAD), Vector2i(PAD * 2 + 1, PAD * 2 + 1)))
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
