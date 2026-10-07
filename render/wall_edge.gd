class_name WallEdge
extends Node2D
## One wall edge: a face standing on the cell boundary line and, along its
## top, a lit strip 4 px wide lying on the far side of the line (the top of
## a thin wall seen from above). Nothing is drawn on the ground beyond the
## line itself. The node sits in the Y-sorted layer with the cell on the
## edge's -x / -y side, a hair nearer the camera, so it is in front of what
## stands on that cell and behind the next.
##
## Height. For every walkable cell, a wall on its south or east edge is a
## stub a third of a tile tall; a wall on its north or west edge is full
## height. A wall between two walkable cells is the south/east edge of one
## of them, so a stub. Void cells have no say. An edge is the east or south
## edge of its -x / -y cell, so the test is simply whether that cell is
## walkable (is_stub). A drawing rule only: the sim knows nothing of it.
##
## Joins, from the walls meeting at each end (doors count as nothing):
## straight on, the strip simply continues; at an L the two strips miter
## into one shared far vertex; at a T the through strip runs on and the
## joining wall butts into it (trimmed to the through wall's back when it
## comes from the far side); at a free end the strip ends square and a
## short end face closes the wall where that end faces the camera.

const FACE_EAST := Color(0.263, 0.278, 0.353)  # The south-east side of a cell.
const FACE_SOUTH := Color(0.353, 0.373, 0.45)  # The south-west side, lit.
const END_FACE := Color(0.31, 0.325, 0.4)
const TOP := Color(0.6, 0.625, 0.72)
const STRIP := 4.0
const STUB_FRACTION := 1.0 / 3.0

enum Join { STRAIGHT, MITER, BUTT, TRIM, FREE }

var key := Vector3i.ZERO
var far_side_floor := false
## Per end: the join, and the other wall's strip offset where one matters.
var _join: Array[int] = [Join.FREE, Join.FREE]
var _other_offset: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]


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


## The strip's offset from the line: STRIP px across, on the far side.
static func strip_offset(edge: Vector3i) -> Vector2:
	return screen(across_grid(edge)).normalized() * STRIP


static func full_height() -> float:
	return Iso.height_px("wall")


## The stub rule. [param floor_at] says whether a cell is walkable.
static func is_stub(edge: Vector3i, floor_at: Callable) -> bool:
	return floor_at.call(Vector2i(edge.x, edge.y))


static func height_for(stub: bool) -> float:
	return Iso.TILE_SIZE.y * STUB_FRACTION if stub else full_height()


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


## Draws a face from line [param a]-[param b] up [param h] px, with its lit
## strip along the top offset by [param offset]; the strip's far corners
## may be moved for joins.
static func draw_wall(on: CanvasItem, a: Vector2, b: Vector2, h: float, offset: Vector2, color: Color,
		far_a := Vector2.INF, far_b := Vector2.INF) -> void:
	var up := Vector2(0, -h)
	on.draw_colored_polygon(PackedVector2Array([a, b, b + up, a + up]), color)
	var qa := far_a if far_a != Vector2.INF else a + offset
	var qb := far_b if far_b != Vector2.INF else b + offset
	on.draw_colored_polygon(PackedVector2Array([a + up, b + up, qb + up, qa + up]), TOP)


# --- This edge -----------------------------------------------------------------

func setup(edge: Vector3i, kind_at: Callable, floor_at: Callable) -> void:
	key = edge
	position = Iso.tile_to_local(Vector2i(edge.x, edge.y)) + Vector2(0, 0.5)
	far_side_floor = is_stub(edge, floor_at)
	for end in 2:
		_classify_end(end, kind_at)
	queue_redraw()


func _classify_end(end: int, kind_at: Callable) -> void:
	var v := vertex_at(key, end)
	var mine := away_from(key, end)
	var collinear_wall := false
	var crossing: Array[Vector3i] = []
	for entry: Array in edges_at_vertex(v):
		var other: Vector3i = entry[0]
		if other == key or kind_at.call(other) != Terrain.Edge.WALL:
			continue
		if away_from(other, entry[1]).dot(mine) < -0.9:
			collinear_wall = true
		else:
			crossing.append(other)
	_other_offset[end] = Vector2.ZERO
	if collinear_wall:
		_join[end] = Join.STRAIGHT
	elif crossing.size() == 1:
		_join[end] = Join.MITER
		_other_offset[end] = strip_offset(crossing[0])
	elif crossing.size() == 2:
		# The through wall's strip lies on its far side; this wall comes in
		# from that side or from the near side.
		var through := strip_offset(crossing[0])
		_other_offset[end] = through
		_join[end] = Join.TRIM if mine.dot(through) > 0.0 else Join.BUTT
	else:
		_join[end] = Join.FREE


func _draw() -> void:
	var ends := endpoints(key)
	var h := height_for(far_side_floor)
	var up := Vector2(0, -h)
	var offset := strip_offset(key)
	var line: Array[Vector2] = [ends[0], ends[1]]
	var far: Array[Vector2] = [Vector2.INF, Vector2.INF]
	for end in 2:
		var v := ends[end]
		match _join[end]:
			Join.MITER:
				far[end] = v + offset + _other_offset[end]
			Join.TRIM:
				line[end] = v + _other_offset[end]
			Join.FREE:
				# The end face shows where the end points toward the camera:
				# the +y end of an east edge, the +x end of a south edge.
				var faces_camera := (key.z == Terrain.EAST) == (end == 0)
				if faces_camera:
					draw_colored_polygon(PackedVector2Array([v, v + offset, v + offset + up, v + up]), END_FACE)
	draw_wall(self, line[0], line[1], h, offset, FACE_EAST if key.z == Terrain.EAST else FACE_SOUTH, far[0], far[1])
