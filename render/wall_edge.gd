class_name WallEdge
extends Node2D
## One wall edge: a face standing on the cell boundary line, one flat
## neutral grey (`Main.WALL_VALUE`) whatever way it faces, with no top
## strip, no end face and nothing drawn on the ground. The top of a wall is
## where the face ends. The node sits in the Y-sorted layer with the cell on
## the edge's -x / -y side, a hair nearer the camera, so it is in front of
## what stands on that cell and behind the next.
##
## Height. A wall that would hide floor is a stub a third of a tile tall;
## one that hides nothing stands full height. A full wall hides the cells
## straight behind it (toward -x for an east edge, -y for a south edge) for
## as many cells as it has rows of height, LOOK_BEHIND, so: stub if any of
## those cells is walkable, full if they are all void or off the map. For a
## wall with floor directly behind it this is "a wall on a walkable cell's
## south or east edge is a stub"; walls on the far side of a one-cell void
## strip, where a thick wall used to be, are stubs too, since the floor
## beyond is in their shadow. A drawing rule only: the sim knows nothing of
## it.
##
## Corners. Two faces of one value meeting at an L or a T would merge, so
## where another wall meets an end of this one at an angle (doors count as
## nothing), a 1 px line one step darker than the face runs up that end. A
## free end and a straight continuation get nothing.

## Thickness of a door panel's top, in px (walls have none).
const STRIP := 4.0
const STUB_FRACTION := 1.0 / 3.0
## How much darker than the face a corner line is.
const CORNER_STEP := 0.05
## Cells straight behind a wall that a full-height one would hide: one per
## row of its height (a cell further back is half a tile height up on screen).
const LOOK_BEHIND := int(Iso.HEIGHTS["wall"] * 2)

var key := Vector3i.ZERO
var far_side_floor := false
## The face's grey, 0..1.
var value := 0.18
## Per end: whether another wall meets it at an angle.
var _corner: Array[bool] = [false, false]


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


## The stub rule. [param floor_at] says whether a cell is walkable.
static func is_stub(edge: Vector3i, floor_at: Callable) -> bool:
	var behind := Vector2i(-1, 0) if edge.z == Terrain.EAST else Vector2i(0, -1)
	var cell := Vector2i(edge.x, edge.y)
	for i in LOOK_BEHIND:
		if floor_at.call(cell):
			return true
		cell += behind
	return false


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


## Draws a face from line [param a]-[param b] up [param h] px with a top
## [param offset] px thick in [param top] along it: a door panel, which
## unlike a wall shows its thickness as it turns.
static func draw_wall(on: CanvasItem, a: Vector2, b: Vector2, h: float, offset: Vector2,
		color: Color, top: Color) -> void:
	var up := Vector2(0, -h)
	on.draw_colored_polygon(PackedVector2Array([a, b, b + up, a + up]), color)
	on.draw_colored_polygon(PackedVector2Array([a + up, b + up, b + offset + up, a + offset + up]), top)


# --- This edge -----------------------------------------------------------------

func setup(edge: Vector3i, kind_at: Callable, floor_at: Callable, grey: float) -> void:
	key = edge
	value = grey
	position = Iso.tile_to_local(Vector2i(edge.x, edge.y)) + Vector2(0, 0.5)
	far_side_floor = is_stub(edge, floor_at)
	for end in 2:
		_corner[end] = _meets_wall_at(end, kind_at)
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
	var up := Vector2(0, -height_for(far_side_floor))
	var face := Color(value, value, value)
	draw_colored_polygon(PackedVector2Array([ends[0], ends[1], ends[1] + up, ends[0] + up]), face)
	var step := maxf(value - CORNER_STEP, 0.0)
	var line := Color(step, step, step)
	for end in 2:
		if _corner[end]:
			draw_line(ends[end], ends[end] + up, line, 1.0)
