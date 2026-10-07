class_name WallEdge
extends Node2D
## One wall edge: a face standing on the cell boundary line, full height,
## one flat neutral grey (`Main.WALL_VALUE`) whatever way it faces, with no
## top strip, no end face and nothing drawn on the ground. The top of a
## wall is where the face ends. The node sits in the Y-sorted layer with
## the cell on the edge's -x / -y side, a hair nearer the camera, so it is
## in front of what stands on that cell and behind the next.
##
## Occlusion windows. A creature a face is drawn in front of shows through
## it: the face gets a soft circular cutout centred on the creature's
## sprite, RADIUS wide, fading the face to a quarter at the centre and
## back to opaque at the edge (render/wall_cutout.gdshader, one material
## per face, up to MAX_CUTOUTS centres). A cutout fades in over
## CUTOUT_SECONDS when the sprite comes to overlap the face and out again
## when it leaves. Main feeds every wall the creatures each frame
## (update_cutouts); nothing here reads the sim.
##
## Corners. Two faces of one value meeting at an L or a T would merge, so
## where another wall meets an end of this one at an angle (doors count as
## nothing), a 1 px line one step darker than the face runs up that end. A
## free end and a straight continuation get nothing.

## Thickness of a door panel's top, in px (walls have none).
const STRIP := 4.0
## How much darker than the face a corner line is.
const CORNER_STEP := 0.05
## Cutout radius in world px: about a tile.
const RADIUS := float(Iso.TILE_SIZE.x)
const CUTOUT_SECONDS := 0.15
const MAX_CUTOUTS := 8
const SHADER := preload("res://render/wall_cutout.gdshader")

var key := Vector3i.ZERO
## The face's grey, 0..1.
var value := 0.18
## Per end: whether another wall meets it at an angle.
var _corner: Array[bool] = [false, false]
## Creature instance id -> {"center": Vector2, "strength": float, "in": bool}.
var _cutouts: Dictionary[int, Dictionary] = {}
## The face's extent in the parent's space, for the overlap test.
var _bounds := Rect2()


# --- Geometry shared with Door ----------------------------------------------

## A grid vector on screen.
static func screen(grid: Vector2) -> Vector2:
	return Vector2((grid.x - grid.y) * Iso.HALF.x, (grid.x + grid.y) * Iso.HALF.y)


## Where an edge runs, in the local space of its -x / -y cell's centre:
## the two corners of that cell's diamond it joins, start to end.
static func endpoints(edge: Vector3i) -> Array[Vector2]:
	var e := Vector2(Iso.HALF.x, 0)
	var s := Vector2(0, Iso.HALF.y)
	var w := Vector2(-Iso.HALF.x, 0)
	if edge.z == Terrain.EAST:
		return [s, e]
	return [w, s]


## Grid direction along the edge, start to end, and across it to its far
## side (-x for an east edge, -y for a south edge).
static func along_grid(edge: Vector3i) -> Vector2:
	return Vector2(0, -1) if edge.z == Terrain.EAST else Vector2(1, 0)


static func across_grid(edge: Vector3i) -> Vector2:
	return Vector2(-1, 0) if edge.z == Terrain.EAST else Vector2(0, -1)


static func full_height() -> float:
	return Iso.height_px("wall")


## Position of the vertex (shared diamond corner) an edge end sits on, as
## the cell whose north corner it is.
static func vertex_at(edge: Vector3i, end: int) -> Vector2i:
	var c := Vector2i(edge.x, edge.y)
	if edge.z == Terrain.EAST:
		return c + (Vector2i(1, 1) if end == 0 else Vector2i(1, 0))
	return c + (Vector2i(0, 1) if end == 0 else Vector2i(1, 1))


## The four edges that can meet at the vertex that is [param v]'s north
## corner, each with the end of it that sits on v.
static func edges_at_vertex(v: Vector2i) -> Array[Array]:
	return [
		[Vector3i(v.x - 1, v.y - 1, Terrain.EAST), 0],
		[Vector3i(v.x - 1, v.y, Terrain.EAST), 1],
		[Vector3i(v.x, v.y - 1, Terrain.SOUTH), 0],
		[Vector3i(v.x - 1, v.y - 1, Terrain.SOUTH), 1],
	]


## Screen direction an edge runs in, away from the vertex at [param end].
static func away_from(edge: Vector3i, end: int) -> Vector2:
	var ends := endpoints(edge)
	return (ends[1] - ends[0] if end == 0 else ends[0] - ends[1]).normalized()


## Draws a face from line [param a]-[param b] up [param h] px with a top
## [param offset] px thick in [param top] along it: a door panel, which
## unlike a wall shows its thickness as it turns.
static func draw_wall(on: CanvasItem, a: Vector2, b: Vector2, h: float, offset: Vector2,
		color: Color, top: Color) -> void:
	var up := Vector2(0, -h)
	on.draw_colored_polygon(PackedVector2Array([a, b, b + up, a + up]), color)
	on.draw_colored_polygon(PackedVector2Array([a + up, b + up, b + offset + up, a + offset + up]), top)


# --- This edge -----------------------------------------------------------------

func setup(edge: Vector3i, kind_at: Callable, grey: float) -> void:
	key = edge
	value = grey
	position = Iso.tile_to_local(Vector2i(edge.x, edge.y)) + Vector2(0, 0.5)
	for end in 2:
		_corner[end] = _meets_wall_at(end, kind_at)
	var ends := endpoints(edge)
	var up := Vector2(0, -full_height())
	_bounds = Rect2(position + ends[0], Vector2.ZERO).expand(position + ends[1]) \
			.expand(position + ends[0] + up).expand(position + ends[1] + up)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("radius", RADIUS)
	self.material = material
	queue_redraw()


## Whether a wall that is not this one's continuation meets its [param end].
func _meets_wall_at(end: int, kind_at: Callable) -> bool:
	var v := vertex_at(key, end)
	var mine := away_from(key, end)
	for entry: Array in edges_at_vertex(v):
		var other: Vector3i = entry[0]
		if other == key or kind_at.call(other) != Terrain.Edge.WALL:
			continue
		if away_from(other, entry[1]).dot(mine) > -0.9:
			return true
	return false


## Once a frame, from Main: [param creatures] are the creature sprites on
## screen as {"id", "center", "rect", "y"} in the parent's space. A sprite
## whose rect overlaps this face while the face is drawn in front of it
## (further down the Y-sort) gets a cutout; it animates in, and out once
## the overlap ends.
func update_cutouts(creatures: Array[Dictionary], delta: float) -> void:
	var seen: Dictionary[int, bool] = {}
	for creature in creatures:
		if creature["y"] >= position.y or not _bounds.intersects(creature["rect"]):
			continue
		var id: int = creature["id"]
		seen[id] = true
		if not _cutouts.has(id):
			_cutouts[id] = {"center": creature["center"], "strength": 0.0, "in": true}
		_cutouts[id]["center"] = creature["center"]
		_cutouts[id]["in"] = true
	if _cutouts.is_empty():
		return
	var step := delta / CUTOUT_SECONDS
	for id in _cutouts.keys():
		var cutout: Dictionary = _cutouts[id]
		if not seen.has(id):
			cutout["in"] = false
		cutout["strength"] = move_toward(cutout["strength"], 1.0 if cutout["in"] else 0.0, step)
		if not cutout["in"] and cutout["strength"] <= 0.0:
			_cutouts.erase(id)
	_push_cutouts()


## The strongest MAX_CUTOUTS cutouts to the shader.
func _push_cutouts() -> void:
	var cutouts := _cutouts.values()
	cutouts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["strength"] > b["strength"])
	var centers := PackedVector2Array()
	var strengths := PackedFloat32Array()
	for cutout: Dictionary in cutouts.slice(0, MAX_CUTOUTS):
		centers.append(cutout["center"])
		strengths.append(cutout["strength"])
	var count := centers.size()
	centers.resize(MAX_CUTOUTS)
	strengths.resize(MAX_CUTOUTS)
	var shader_material := material as ShaderMaterial
	shader_material.set_shader_parameter("count", count)
	shader_material.set_shader_parameter("centers", centers)
	shader_material.set_shader_parameter("strengths", strengths)


func _draw() -> void:
	var ends := endpoints(key)
	var up := Vector2(0, -full_height())
	var face := Color(value, value, value)
	draw_colored_polygon(PackedVector2Array([ends[0], ends[1], ends[1] + up, ends[0] + up]), face)
	var step := maxf(value - CORNER_STEP, 0.0)
	var line := Color(step, step, step)
	for end in 2:
		if _corner[end]:
			draw_line(ends[end], ends[end] + up, line, 1.0)
