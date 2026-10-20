class_name TerrainBorder
extends Node3D
## Outdoors, what lies past the map's forest (decision 326), so the camera
## never looks past the land into nothing. Drawing only: the sim, paths,
## picks and the minimap never see it.
##
## Past the real trees (Client3D._add_forest, out to FOREST_REACH) the
## forest goes on as a canopy: one sheet at crown height, rolled into
## crowns by noise, from START cells off the land (rising out of the forest
## floor there, among the last real trees) to REACH cells, further than
## the view and its pan reach from anywhere on the land; its colour
## darkens away from the land. Where the land's edge stands high (a map on
## a hill), the canopy beyond it stands as high: hills. Under it all, a far
## floor in the forest floor's colour runs FAR metres past the map, so even
## a peek sees no void. One mesh a CHUNK of cells, flat facets, no shadows.
##
## The canopy is worked out on a worker thread (the walk out from the land
## and the meshes' arrays), and its meshes are added when it is done, so a
## room's build waits for none of it; finish() waits for it (tests).

const START := 6
const REACH := 34
const CHUNK := 16
## The canopy's height above its land, how far crowns roll up and down,
## and how big a crown is (cells).
const CROWN := 3.2
const CROWN_ROLL := 1.0
const CROWN_SIZE := 1.6
## Each corner pushed up or down by up to this much more, so the crowns
## come to points as the trees' do.
const CROWN_PEAK := 0.45
## Its colour at REACH, as a share of its colour at START.
const FAR_SHADE := 0.55
## The far floor: this many metres past the land each way, this far below
## the forest floor.
const FAR := 200.0
const FAR_SINK := 0.05
## The canopy's colours, lighter to darker: the palette's foliage once the
## trees are art-kit's own; while they are the Kenney fill, its greens (as
## drawn in the sun), so the canopy reads as more of the same trees.
const FOLIAGE: Array[Vector2i] = [Vector2i(4, 4), Vector2i(4, 6), Vector2i(4, 7)]
const FILL_FOLIAGE: Array[Color] = [Color("3d9876"), Color("317f66"), Color("27685a")]

## Each chunk's arrays as built: [positions, normals, colours] (kept: a
## headless mesh keeps none).
var chunks: Dictionary[Vector2i, Array] = {}
## The far floor.
var far_floor: MeshInstance3D
var _task := -1
var _material: Material
## Whether the canopy is broadleaf's (dried and turned with the season) or
## the stands' (evergreen: snow only).
var _leaf := true


## Lays the far floor now and starts the canopy past [param land] (its
## cells, never changed after this: the view makes a new one each build),
## [param heights] (the land's ground, copied: a level a cell, or metres with
## [param rise] 1.0, decision 525), each unit [param rise] metres; the forest floor's colour and depth; whether the
## band is [param stands] of pines (PineStands), whose canopy's colours,
## the palette's foliage, the canopy takes.
func build(land: Dictionary[Vector2i, bool], heights: Dictionary, rise: float, floor_colour: Color, floor_depth: float, threaded := true, stands := false) -> void:
	var low := Vector2i(1 << 20, 1 << 20)
	var high := -low
	for cell: Vector2i in land:
		low = low.min(cell)
		high = high.max(cell)
	if land.is_empty():
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2(high - low) + Vector2.ONE * FAR * 2.0
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = floor_colour.darkened(0.15)
	floor_material.roughness = 1.0
	far_floor = MeshInstance3D.new()
	far_floor.name = "FarFloor"
	far_floor.mesh = plane
	# Past pine stands, their needles (decision 423), a shade darker.
	far_floor.material_override = PineStands.floor_material(floor_material.albedo_color, 0.85) if stands else Client3D.season_material(floor_material, false, false)
	far_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	far_floor.position = Vector3((low.x + high.x) * 0.5, -floor_depth - FAR_SINK, (low.y + high.y) * 0.5)
	add_child(far_floor)
	var colours: Array[Color] = []
	if ArtKit.filled_by("tree.broadleaf") == "fill" and not stands:
		colours = FILL_FOLIAGE.duplicate()
	else:
		for at in FOLIAGE:
			colours.append(Client3D.swatch(at.x, at.y))
	_leaf = not stands
	var work := _work.bind(land, heights.duplicate(), rise, colours, -floor_depth - FAR_SINK * 2.0)
	if threaded:
		_task = WorkerThreadPool.add_task(work, false, "terrain border")
		set_process(true)
	else:
		work.call()
		_place()


## Waits for the canopy, and adds it.
func finish() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_place()
	set_process(false)


func _ready() -> void:
	set_process(_task >= 0)


func _process(_delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		finish()


func _exit_tree() -> void:
	# A task must be waited for; its result is dropped with this node.
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## On the worker: how far each cell off the land is (eight ways, out to
## REACH, from the land's outline) and the height of the land it was
## reached from; then each chunk's canopy as arrays. Touches no node.
func _work(land: Dictionary[Vector2i, bool], heights: Dictionary, rise: float, colours: Array[Color], sunk: float) -> void:
	var distance: Dictionary[Vector2i, int] = {}
	var base: Dictionary[Vector2i, float] = {}
	var frontier: Array[Vector2i] = []
	var ways: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	for cell: Vector2i in land:
		for way in ways:
			if not land.has(cell + way):
				distance[cell] = 0
				base[cell] = float(heights.get(cell, 0)) * rise
				frontier.append(cell)
				break
	var head := 0
	while head < frontier.size():
		var cell := frontier[head]
		head += 1
		if distance[cell] >= REACH:
			continue
		for way in ways:
			var next := cell + way
			if not distance.has(next) and not land.has(next):
				distance[next] = distance[cell] + 1
				base[next] = base[cell]
				frontier.append(next)
	var built: Dictionary[Vector2i, Array] = {}
	for cell: Vector2i in distance:
		if distance[cell] < START - 1:
			continue
		var chunk := Vector2i(floori(cell.x / float(CHUNK)), floori(cell.y / float(CHUNK)))
		if not built.has(chunk):
			built[chunk] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray()]
		_cell_canopy(built[chunk], cell, distance, base, colours, sunk)
	chunks = built


## One cell of canopy into [param into]: its corners at crown height (down
## to [param sunk] where a corner is nearer the land than START), two flat
## facets, each a foliage swatch by the crowns, darker in a hollow and
## further off.
static func _cell_canopy(into: Array, cell: Vector2i, distance: Dictionary[Vector2i, int], base: Dictionary[Vector2i, float], colours: Array[Color], sunk: float) -> void:
	var corners: Array[Vector3] = []
	var rolls: Array[float] = []
	for corner: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var at := cell + corner
		# The corner's cells: the nearest to the land says how far up it is.
		var near := REACH + 1
		var ground := 0.0
		for other: Vector2i in [at, at - Vector2i(1, 0), at - Vector2i(0, 1), at - Vector2i(1, 1)]:
			var away: int = distance.get(other, REACH + 1)
			if away < near:
				near = away
				ground = base.get(other, 0.0)
		if near == REACH + 1:
			ground = base.get(cell, 0.0)
			near = distance.get(cell, REACH)
		var place := Vector2(at) - Vector2(0.5, 0.5)
		var roll := Client3D._field(place, CROWN_SIZE, 60) * 0.7 + Client3D._field(place, CROWN_SIZE * 0.45, 61) * 0.3
		var up := clampf((near - (START - 1)) / 2.0, 0.0, 1.0)
		var top := ground + CROWN + (roll - 0.5) * 2.0 * CROWN_ROLL + (Client3D._roll(at, 63) - 0.5) * 2.0 * CROWN_PEAK
		corners.append(Vector3(place.x, lerpf(sunk, top, up), place.y))
		rolls.append(roll)
	var far := clampf(float(distance.get(cell, REACH) - START) / float(REACH - START), 0.0, 1.0)
	for triangle: Array in [[0, 2, 1], [1, 2, 3]]:
		var a := corners[triangle[0]]
		var b := corners[triangle[1]]
		var c := corners[triangle[2]]
		var normal := (b - a).cross(c - a)
		if normal.y < 0.0:
			normal = -normal
			var swap := b
			b = c
			c = swap
		normal = normal.normalized()
		var roll := (rolls[triangle[0]] + rolls[triangle[1]] + rolls[triangle[2]]) / 3.0
		var pick := clampi(int((1.0 - roll) * colours.size() + Client3D._roll(cell, 62 + triangle[0]) * 0.8), 0, colours.size() - 1)
		var shade := lerpf(0.82, 1.12, roll) * lerpf(1.0, FAR_SHADE, far) * lerpf(0.92, 1.06, Client3D._roll(cell, 64 + triangle[0]))
		var colour := Color(colours[pick] * shade, 1.0)
		# Godot's front faces wind clockwise seen from the front.
		into[0].append_array([a, c, b])
		into[1].append_array([normal, normal, normal])
		into[2].append_array([colour, colour, colour])


## The canopy's meshes, a chunk each, from what the worker built.
func _place() -> void:
	if _material == null:
		var base := StandardMaterial3D.new()
		base.vertex_color_use_as_albedo = true
		base.vertex_color_is_srgb = true
		base.roughness = 1.0
		_material = Client3D.season_material(base, _leaf, false)
	for chunk: Vector2i in chunks:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = chunks[chunk][0]
		arrays[Mesh.ARRAY_NORMAL] = chunks[chunk][1]
		arrays[Mesh.ARRAY_COLOR] = chunks[chunk][2]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var drawn := MeshInstance3D.new()
		drawn.name = "Canopy_%d_%d" % [chunk.x, chunk.y]
		drawn.mesh = mesh
		drawn.material_override = _material
		drawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(drawn)
