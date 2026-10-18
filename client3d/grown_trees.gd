class_name GrownTrees
extends Node3D
## A grown forest's trees (decision 467): the stand tools/forest_grow.py
## grew for a level with a canopy (decision 466), read from its trees.json
## and drawn as grown: a tapering trunk, needles in small pads along every
## live branch, a bare stick for each dead one still on, a snag grey and
## broken. Drawing only: the sim knows a tall tree as its void cell
## (ForestPack), and no more.
##
## Which trees: one of TRUNK_HEIGHT or more where its cell is not land (the
## trunk ForestPack made), a smaller one where its cell is land (undergrowth,
## walked through); any other the level no longer agrees with is left out.
## A tree's cell is its "at" floored: the grower's cell x spans x to x + 1,
## the view's x - 0.5 to x + 0.5.
##
## Each CHUNK x CHUNK cells are drawn two ways: far, a trunk and one pad a whorl,
## built for every chunk when the room is; near, every branch's pads, built
## on a worker for the chunks within NEAR_REACH of the view's middle and
## dropped past DROP_REACH, the far shown till it is in. Both in the
## season's colours, and a shadow-only twin each, so the sun's shadows and
## the dark under the roof stay whole whatever is seen through.
##
## The see-through (Jeff: "use transparency that moves with player to see
## through the tree tops since its a isometric game"; then "larger circle,
## probably even most of visible screen"): round the line from the player's
## body toward the camera (see_through.gdshaderinc), whatever is above their
## knees is faded toward the near walls' NEAR_ALPHA, softly at its edge,
## moving with them; how wide is a share of the view (set_see, Net's
## see_through), so the roof stays as a rim at the screen's edges and
## corners at any zoom. The chunks near enough the player to reach it
## draw with three passes: opaque but for that region (season_cut), its
## depth (season_see_depth), then its colour faded (season_see), so only
## the nearest surface shows, as a near wall does (decision 188); the rest
## with the opaque pass alone. No crown is the
## same: a tree's droop, pad size and shape, branch length and tone come
## from its place; a pad low enough to meet a head droops and thickens to a
## branch's tip.

const FILE := "trees.json"
## As forest_grow.py's TRUNK_HEIGHT and ForestPack's.
const TRUNK_HEIGHT := 3.0
const CHUNK := 8
## Near pads for the chunks whose middle is within NEAR_REACH (metres) of the
## focus, dropped past DROP_REACH.
const NEAR_REACH := 34.0
const DROP_REACH := 46.0
## Below this (metres off the ground), a tall tree's live branch has no
## pads, only its stick: nothing the size of a shelf at head height.
const PAD_CLEAR := 2.1
## Below this, a pad droops and thickens: a branch's tip.
const HEAD_HIGH := 3.4
## How soft the see-through's edge is (metres), and how much further than
## its outer edge a chunk's middle may be from the player and still draw
## it: a 13 m crown stands about 11 m off them toward the camera, and a
## chunk's middle is up to 6 m from its corner.
const SEE_SOFT := 3.5
const SEE_BEYOND := 17.0

## Tests: a level's trees by its name, read before the file.
static var registered: Dictionary[String, Dictionary] = {}

## Each chunk's pieces: {"far": Node3D, "near": Node3D or null}.
var chunks: Dictionary[Vector2i, Dictionary] = {}
## How many trees are drawn.
var tree_count := 0
var _trees: Dictionary[Vector2i, Array] = {}
var _heights: Dictionary = {}
var _rise := 0.0
var _colours: Dictionary = {}
## The opaque pass alone; with the see-through's passes after it; those
## two passes (all share the focus).
var _material: ShaderMaterial
var _see: ShaderMaterial
var _see_colour: ShaderMaterial
var _see_depth: ShaderMaterial
var _shadow: StandardMaterial3D
var _focus_chunk := Vector2i(1 << 30, 0)
var _player := Vector3(1 << 20, 0.0, 0.0)
var _see_chunk := Vector2i(1 << 30, 0)
## The see-through's outer edge round the line to the camera (metres).
var see_outer := 4.5
## Near chunks being built: chunk -> task id; built ones waiting to be added.
var _tasks: Dictionary[Vector2i, int] = {}
var _built: Dictionary[Vector2i, Array] = {}
var _mutex := Mutex.new()


## The trees grown for [param level_name]: registered, else its trees.json
## (the level's own, never an overlay's), else {}.
static func data_for(level_name: String) -> Dictionary:
	if registered.has(level_name):
		return registered[level_name]
	var path := Level.DIR + level_name + "/" + FILE
	if level_name.is_empty() or not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


## The cell a tree of [param data] stands on.
static func cell_of(tree: Dictionary) -> Vector2i:
	return Vector2i(floori(float(tree["at"][0])), floori(float(tree["at"][1])))


## The trunks of [param data] standing where the level has no [param land]
## (its floor and water cells): the void cells the view leaves to these
## trees, not the forest's ring.
static func trunk_cells(data: Dictionary, land: Dictionary) -> Dictionary[Vector2i, bool]:
	var out: Dictionary[Vector2i, bool] = {}
	for tree: Dictionary in data.get("trees", []):
		var cell := cell_of(tree)
		if float(tree.get("height", 0.0)) >= TRUNK_HEIGHT and not land.has(cell):
			out[cell] = true
	return out


## Lays out [param data]'s trees: a tall one on a cell not in [param land],
## a small one on [param ground] (land, not water); the ground [param heights]
## (a level a cell) of [param rise] metres; [param leaf] for a broadleaf
## canopy's season. The far chunks are made now; the near as the focus
## comes (set_focus).
func build(data: Dictionary, land: Dictionary, ground: Dictionary, heights: Dictionary, rise: float, leaf := false) -> void:
	_heights = heights.duplicate()
	_rise = rise
	_colours = {
		"bark": [Client3D.swatch(2, 5), Client3D.swatch(2, 6)],
		"needles": [Client3D.swatch(4, 3), Client3D.swatch(4, 4), Client3D.swatch(4, 6), Client3D.swatch(4, 7)],
	}
	_material = _season(preload("res://client3d/season_cut.gdshader"), leaf)
	_see = _season(preload("res://client3d/season_cut.gdshader"), leaf)
	_see_colour = _season(preload("res://client3d/season_see.gdshader"), leaf)
	_see_colour.set_shader_parameter("alpha", Client3D.NEAR_ALPHA)
	_see_colour.render_priority = Client3D.NEAR_PRIORITY
	_see_depth = ShaderMaterial.new()
	_see_depth.shader = preload("res://client3d/season_see_depth.gdshader")
	_see_depth.render_priority = Client3D.NEAR_DEPTH_PRIORITY
	_see.next_pass = _see_colour
	_see_colour.next_pass = _see_depth
	set_see(see_outer - SEE_SOFT * 0.5, true)
	_shadow = StandardMaterial3D.new()
	_shadow.cull_mode = BaseMaterial3D.CULL_DISABLED
	for tree: Dictionary in data.get("trees", []):
		var cell := cell_of(tree)
		var tall := float(tree.get("height", 0.0)) >= TRUNK_HEIGHT
		if tall == land.has(cell) or not tall and not ground.has(cell):
			continue
		var key := Vector2i(floori(cell.x / float(CHUNK)), floori(cell.y / float(CHUNK)))
		if not _trees.has(key):
			_trees[key] = []
		_trees[key].append(tree)
		tree_count += 1
	for key: Vector2i in _trees:
		var arrays := _new_arrays()
		for tree: Dictionary in _trees[key]:
			_draw(arrays, tree, false)
		var piece := _piece(arrays, "Far_%d_%d" % [key.x, key.y])
		chunks[key] = {"far": piece, "near": null}
		add_child(piece)


## The see-through on [param at] (the player's feet), drawn by the chunks
## round it; the near chunks round [param view] (the view's middle, panned
## or not): those come in on workers (the far shown till then), those far
## off dropped.
func set_focus(at: Vector3, view: Vector3) -> void:
	if _material == null:
		return
	for material: ShaderMaterial in _materials():
		material.set_shader_parameter("focus", at + Vector3.UP * 0.9)
	_player = at
	var by := Vector2i(floori(at.x / CHUNK), floori(at.z / CHUNK))
	if by != _see_chunk:
		_see_chunk = by
		for chunk: Vector2i in chunks:
			_dress(chunk)
	var key := Vector2i(floori(view.x / CHUNK), floori(view.z / CHUNK))
	if key == _focus_chunk:
		return
	_focus_chunk = key
	var flat := Vector2(view.x, view.z)
	for chunk: Vector2i in chunks:
		var away := (Vector2(chunk * CHUNK) + Vector2.ONE * CHUNK * 0.5).distance_to(flat)
		var near: Node3D = chunks[chunk]["near"]
		if away <= NEAR_REACH and near == null and not _tasks.has(chunk):
			_tasks[chunk] = WorkerThreadPool.add_task(_work.bind(chunk), false, "grown trees")
		elif away > DROP_REACH and near != null:
			near.queue_free()
			chunks[chunk]["near"] = null
			_show(chunk, false)
	set_process(true)


## Waits for every near chunk asked for, and adds it (tests).
func finish() -> void:
	for chunk: Vector2i in _tasks.keys():
		WorkerThreadPool.wait_for_task_completion(_tasks[chunk])
	_tasks.clear()
	_place(true)


func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	for chunk: Vector2i in _tasks.keys():
		if WorkerThreadPool.is_task_completed(_tasks[chunk]):
			WorkerThreadPool.wait_for_task_completion(_tasks[chunk])
			_tasks.erase(chunk)
	_place()
	_mutex.lock()
	var waiting := not _built.is_empty()
	_mutex.unlock()
	if _tasks.is_empty() and not waiting:
		set_process(false)


func _exit_tree() -> void:
	# A task must be waited for; its result is dropped with this node.
	for chunk: Vector2i in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[chunk])
	_tasks.clear()


## On a worker: [param chunk]'s near arrays. Touches no node.
func _work(chunk: Vector2i) -> void:
	var arrays := _new_arrays()
	for tree: Dictionary in _trees[chunk]:
		_draw(arrays, tree, true)
	_mutex.lock()
	_built[chunk] = arrays
	_mutex.unlock()


## A near chunk the workers finished, in place of its far: one a frame, so
## no frame takes several chunks' meshes ([param all]: every one, tests).
func _place(all := false) -> void:
	while true:
		_mutex.lock()
		var chunk: Variant = _built.keys()[0] if not _built.is_empty() else null
		var arrays: Array = _built[chunk] if chunk != null else []
		if chunk != null:
			_built.erase(chunk)
		_mutex.unlock()
		if chunk == null:
			return
		if chunks[chunk]["near"] == null:
			var piece := _piece(arrays, "Near_%d_%d" % [chunk.x, chunk.y])
			add_child(piece)
			chunks[chunk]["near"] = piece
			_dress(chunk)
			_show(chunk, true)
		if not all:
			return


## How wide the see-through is: [param middle] metres from the line to
## the camera to the middle of its soft edge (Client3D: Net's see_through
## times the view's half-height). The chunks that draw it are worked out
## again when it changes by more than a step.
func set_see(middle: float, force := false) -> void:
	var outer := maxf(middle, 0.5) + SEE_SOFT * 0.5
	if not force and absf(outer - see_outer) < 0.05:
		return
	var wider := absf(outer - see_outer) >= 1.0
	see_outer = outer
	for material: ShaderMaterial in _materials():
		material.set_shader_parameter("see_radius", see_outer)
		material.set_shader_parameter("see_soft", SEE_SOFT)
	if wider:
		for chunk: Vector2i in chunks:
			_dress(chunk)


## [param chunk]'s pieces drawn with the see-through's passes if its middle
## is within the see-through's outer edge and SEE_BEYOND of the player,
## else the opaque one alone.
func _dress(chunk: Vector2i) -> void:
	var middle := Vector2(chunk * CHUNK) + Vector2.ONE * CHUNK * 0.5
	var material := _see if middle.distance_to(Vector2(_player.x, _player.z)) <= see_outer + SEE_BEYOND else _material
	for piece: Node3D in [chunks[chunk]["far"], chunks[chunk]["near"]]:
		if piece != null:
			(piece.get_node("Drawn") as MeshInstance3D).material_override = material


func _materials() -> Array[ShaderMaterial]:
	return [_material, _see, _see_colour, _see_depth]


## A season material on [param shader] for the trees' vertex colours.
static func _season(shader: Shader, leaf: bool) -> ShaderMaterial:
	var made := ShaderMaterial.new()
	made.shader = shader
	made.set_shader_parameter("use_vertex_color", true)
	made.set_shader_parameter("vertex_srgb", true)
	made.set_shader_parameter("roughness", 0.9)
	made.set_shader_parameter("leaf", leaf)
	return made


## Shows [param chunk]'s near, or its far.
func _show(chunk: Vector2i, near: bool) -> void:
	var far: Node3D = chunks[chunk]["far"]
	far.visible = not near


## A drawn mesh and its shadow-only twin from [param arrays].
func _piece(arrays: Array, piece_name: String) -> Node3D:
	var piece := Node3D.new()
	piece.name = piece_name
	var surface := []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = arrays[0]
	surface[Mesh.ARRAY_NORMAL] = arrays[1]
	surface[Mesh.ARRAY_COLOR] = arrays[2]
	var mesh := ArrayMesh.new()
	if not arrays[0].is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	var drawn := MeshInstance3D.new()
	drawn.name = "Drawn"
	drawn.mesh = mesh
	drawn.material_override = _material
	drawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	piece.add_child(drawn)
	var twin := MeshInstance3D.new()
	twin.name = "Shadow"
	twin.mesh = mesh
	twin.material_override = _shadow
	twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	piece.add_child(twin)
	return piece


static func _new_arrays() -> Array:
	return [PackedVector3Array(), PackedVector3Array(), PackedColorArray()]


## [param tree] into [param into]: every branch's pads if [param near], else
## one pad a whorl.
func _draw(into: Array, tree: Dictionary, near: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2(float(tree["at"][0]), float(tree["at"][1])))
	var cell := cell_of(tree)
	var base := Vector3(float(tree["at"][0]) - 0.5, float(_heights.get(cell, 0)) * _rise, float(tree["at"][1]) - 0.5)
	var lean := Vector3(float(tree["lean"][0]), 0.0, float(tree["lean"][1]))
	var high := float(tree["height"])
	var snag := str(tree["state"]) == "snag"
	var tall := high >= TRUNK_HEIGHT
	var radius := clampf(float(tree["radius"]), 0.03, 0.32)
	var barks: Array = _colours["bark"]
	var needles: Array = _colours["needles"]
	var bark: Color = barks[0].lerp(barks[1], rng.randf())
	if snag:
		bark = bark.lerp(Color(0.55, 0.52, 0.48), 0.55)
		high *= rng.randf_range(0.7, 0.9)
	# This tree's own: how its branches droop, its pads' size and shape,
	# how far out they reach and how dense, its tone.
	var droop := rng.randf_range(0.12, 0.34)
	var pad_size := rng.randf_range(0.8, 1.15)
	var pad_wide := rng.randf_range(0.5, 0.72)
	var reach := rng.randf_range(0.88, 1.1)
	var spacing := rng.randf_range(0.62, 0.88)
	var tone := rng.randf_range(-0.2, 0.2)
	var turn := rng.randf_range(-0.3, 0.3)
	var sides := 5 if near else 4
	var steps := clampi(int(high / 2.0), 2, 6) if near else 2
	for s in steps:
		var y0 := high * s / steps
		var y1 := high * (s + 1) / steps
		_pipe(into, base + lean * y0 + Vector3.UP * y0, base + lean * y1 + Vector3.UP * y1,
			lerpf(radius, 0.03, y0 / high), lerpf(radius, 0.03 if not snag else radius * 0.4, y1 / high), bark, sides)
	var whorls: Array = tree["whorls"]
	var crown := high
	for whorl: Dictionary in whorls:
		crown = minf(crown, float(whorl["y"]))
	var top := float(tree["height"])
	for whorl: Dictionary in whorls:
		var y := float(whorl["y"])
		var h := clampf((y - crown) / maxf(top - crown, 0.5) + tone, 0.0, 1.0)
		var lit := _ramp([needles[3], needles[2], needles[1]], h)
		var under := _ramp([needles[3].darkened(0.4), needles[3]], h)
		var from := base + lean * y + Vector3.UP * y
		var branches: Array = whorl["branches"]
		if not near:
			# One pad a whorl, as wide as its branches reach.
			var mean := 0.0
			for branch: Array in branches:
				mean += float(branch[1])
			mean = mean / maxf(branches.size(), 1) * reach
			if branches.is_empty() or tall and y < PAD_CLEAR:
				continue
			_pad(into, from + Vector3.DOWN * mean * droop * 0.6, maxf(mean * 0.9, 0.3), Vector3.RIGHT.rotated(Vector3.UP, turn + y), 1.0, rng, lit, under, 0.12, 0.08)
			continue
		for branch: Array in branches:
			var d := Vector3(cos(float(branch[0]) + turn), 0.0, sin(float(branch[0]) + turn))
			var length := float(branch[1]) * reach
			var low := y < HEAD_HIGH
			var bend := droop * (1.6 if low else 1.0)
			var tip := from + d * length + Vector3.DOWN * (bend * length)
			if length > 0.5:
				_pipe(into, from, tip, 0.03, 0.012, bark, 3)
			if tall and y < PAD_CLEAR:
				continue
			# Needles along the outer part: a pad each `spacing`, none
			# bigger than 0.55 m; low ones a tip's, drooped and thick.
			var pads := maxi(1, ceili(length / spacing))
			for p in pads:
				var t := lerpf(0.4, 1.0, (p + 0.5) / pads) if pads > 1 else 0.6
				var size := minf(length * 0.55 + 0.18, 0.55) * lerpf(0.8, 1.05, t) * pad_size
				var at := from.lerp(tip, t) + Vector3.DOWN * (bend * length * 0.35 * t * t)
				_pad(into, at, size, d, pad_wide, rng, lit, under, 0.1, 0.22 if low else 0.08)
	if not whorls.is_empty():
		_pad(into, base + lean * (top - 0.3) + Vector3.UP * (top - 0.3), 0.3, Vector3.RIGHT, 1.0, rng,
			_ramp([needles[1], needles[0]], 0.8 + tone), needles[2], 1.1, 0.08)
	if not near:
		return
	var dry := bark.lerp(Color(0.5, 0.46, 0.4), 0.4)
	for stick: Array in tree["dead"]:
		var y := float(stick[0])
		if y > high:
			continue
		var d := Vector3(cos(float(stick[1])), 0.0, sin(float(stick[1])))
		var length := float(stick[2]) * rng.randf_range(0.35, 0.8)
		if length < 0.15:
			continue
		var from := base + lean * y + Vector3.UP * y
		_pipe(into, from, from + d * length + Vector3.DOWN * (0.3 * length), 0.022, 0.008, dry, 3)


## A tapering pipe from [param a] to [param b], [param sides] faces round.
static func _pipe(into: Array, a: Vector3, b: Vector3, ra: float, rb: float, colour: Color, sides: int) -> void:
	var axis := (b - a).normalized()
	var u := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	var w := axis.cross(u)
	for s in sides:
		var t0 := TAU * s / sides
		var t1 := TAU * (s + 1) / sides
		var d0 := u * cos(t0) + w * sin(t0)
		var d1 := u * cos(t1) + w * sin(t1)
		var out := d0 + d1
		_tri(into, a + d0 * ra, b + d1 * rb, a + d1 * ra, out, colour)
		_tri(into, a + d0 * ra, b + d0 * rb, b + d1 * rb, out, colour)


## A pad of needles at [param at]: a low hexagonal tent [param size] along
## [param along], [param wide] of that across, lit above and darker under,
## [param thick] of its size deep below.
static func _pad(into: Array, at: Vector3, size: float, along: Vector3, wide: float, rng: RandomNumberGenerator, lit: Color, under: Color, peak: float, thick: float) -> void:
	var across := along.cross(Vector3.UP).normalized()
	var rim: Array[Vector3] = []
	for i in 6:
		var angle := TAU * i / 6.0 + rng.randf_range(-0.15, 0.15)
		var r := size * rng.randf_range(0.85, 1.1)
		rim.append(at + along * cos(angle) * r + across * sin(angle) * r * wide + Vector3.DOWN * (size * 0.18 + rng.randf_range(0.0, 0.04)))
	var crest := at + Vector3.UP * size * peak * 2.0
	var belly := at + Vector3.DOWN * size * thick
	for i in 6:
		_tri(into, crest, rim[i], rim[(i + 1) % 6], Vector3.UP, lit)
		_tri(into, belly, rim[i], rim[(i + 1) % 6], Vector3.DOWN, under)


## A flat triangle facing [param facing]'s side, wound so (Godot's front
## faces wind clockwise seen from the front).
static func _tri(into: Array, a: Vector3, b: Vector3, c: Vector3, facing: Vector3, colour: Color) -> void:
	var normal := (c - a).cross(b - a)
	if normal.dot(facing) < 0.0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	normal = normal.normalized()
	into[0].append_array([a, b, c])
	into[1].append_array([normal, normal, normal])
	into[2].append_array([colour, colour, colour])


static func _ramp(colours: Array, t: float) -> Color:
	var at := clampf(t, 0.0, 1.0) * (colours.size() - 1)
	var i := mini(int(at), colours.size() - 2)
	return (colours[i] as Color).lerp(colours[i + 1], at - i)
