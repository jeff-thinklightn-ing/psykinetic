class_name WallEdge
extends Node2D
## One wall edge: a face standing on the cell boundary line, full height,
## one flat neutral grey (`Main.WALL_VALUE`) whatever way it faces, with no
## top strip and no end face; a 1 px line one step darker runs along its
## top and up a corner. Nothing is drawn on the ground.
##
## Near and far. An edge is the south or east edge of its -x / -y cell and
## the north or west edge of the next. A wall whose camera-facing side has
## walkable floor behind it is near (is_near): it is drawn translucent, at
## `Main.NEAR_WALL_ALPHA`, so what stands on that floor shows through. At
## any azimuth in Iso's range that side is the +x / +y one, so a near wall
## is the south or east edge of a walkable cell; a wall whose -x / -y cell
## is nothing is the north or west edge of the floor beyond, faces away,
## and is opaque. An interior partition is near or far by the same cell.
## The classification follows Iso.faces_camera, so a wider range would
## swap sides with the view. Main puts near walls
## in one CanvasGroup (`NearWalls`) with the alpha on the group, so where
## near faces overlap on screen they still show at that one alpha and a
## row of them never stacks up to opaque; far walls go in the Y-sorted
## layer. The lines are drawn with the face and take the same alpha.
## A drawing rule only: the sim knows nothing of it.
##
## Corners. Two faces of one value meeting at an L or a T would merge, so
## where another wall meets an end of this one at an angle (doors count as
## nothing), the corner line runs up that end. A free end and a straight
## continuation get only the top line.

## Thickness of a door panel's top, in px (walls have none).
const STRIP := 4.0
## How much darker than the face its lines are.
const CORNER_STEP := 0.05

var key := Vector3i.ZERO
## The face's grey, 0..1.
var value := 0.18
## Per end: whether another wall meets it at an angle.
var _corner: Array[bool] = [false, false]


# --- Geometry shared with Door ----------------------------------------------

## A grid vector on screen, at the current azimuth.
static func screen(grid: Vector2) -> Vector2:
	return Iso.project(grid)


## Where an edge runs, in the local space of its -x / -y cell's centre:
## the two corners of that cell it joins, start to end (the cell's south
## and east corners for an east edge, west and south for a south edge, as
## named in the azimuth-0 view).
static func endpoints(edge: Vector3i) -> Array[Vector2]:
	var e := Iso.project(Vector2(0.5, -0.5))
	var s := Iso.project(Vector2(0.5, 0.5))
	var w := Iso.project(Vector2(-0.5, 0.5))
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


## The near rule: a wall with walkable floor behind its camera-facing
## side is drawn translucent. That side is the +x / +y one while the
## edge's outward face points at the camera (Iso.faces_camera), with the
## -x / -y cell behind it; otherwise the other. [param floor_at] says
## whether a cell is walkable.
static func is_near(edge: Vector3i, floor_at: Callable) -> bool:
	var behind := Vector2i(edge.x, edge.y)
	if not Iso.faces_camera(edge.z):
		behind += Vector2i(1, 0) if edge.z == Terrain.EAST else Vector2i(0, 1)
	return floor_at.call(behind)


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
	for end in 2:
		_corner[end] = _meets_wall_at(end, kind_at)
	refresh()


## Places and redraws the face for the current azimuth.
func refresh() -> void:
	position = Iso.tile_to_local(Vector2i(key.x, key.y)) + Vector2(0, 0.5)
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


func _draw() -> void:
	var ends := endpoints(key)
	var up := Vector2(0, -full_height())
	var face := Color(value, value, value)
	draw_colored_polygon(PackedVector2Array([ends[0], ends[1], ends[1] + up, ends[0] + up]), face)
	var step := maxf(value - CORNER_STEP, 0.0)
	var line := Color(step, step, step)
	draw_line(ends[0] + up, ends[1] + up, line, 1.0)
	for end in 2:
		if _corner[end]:
			draw_line(ends[end], ends[end] + up, line, 1.0)
