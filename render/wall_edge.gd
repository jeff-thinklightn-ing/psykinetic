class_name WallEdge
extends Node2D
## One wall edge, drawn on the cell boundary line with no ground thickness:
## a face standing on the line and a lit strip along its top. It is in the
## Y-sorted layer with the cell on its -x / -y side, a hair nearer the camera
## than what stands on that cell, so it is in front of that and behind the
## next cell. Floor is never drawn under a wall; a wall stands on the line
## between two floors.
##
## Near walls are low. Both edges drawn here face the camera as seen from
## their -x / -y cell; when that cell is floor the wall is in front of it and
## would hide it, so it is drawn as a stub a third of a tile tall. When that
## cell is nothing the wall is the far side of the cell beyond, and stands
## full height. A drawing rule only: the sim knows nothing of it.
##
## Where a wall ends, turns, or meets a door, a dark line marks the end.

const FACE_EAST := Color(0.263, 0.278, 0.353)  # The south-east side of a cell.
const FACE_SOUTH := Color(0.353, 0.373, 0.45)  # The south-west side, lit.
const TOP := Color(0.6, 0.625, 0.72)
const END := Color(0.12, 0.12, 0.16, 0.9)
const TOP_STRIP := 4.0
const STUB_FRACTION := 1.0 / 3.0

var key := Vector3i.ZERO
var near := false
var end_at_start := false
var end_at_end := false


## Where an edge runs, in the local space of its -x / -y cell's centre:
## the two corners of that cell's diamond it joins, start to end.
static func endpoints(edge: Vector3i) -> Array[Vector2]:
	var e := Vector2(Iso.HALF.x, 0)
	var s := Vector2(0, Iso.HALF.y)
	var w := Vector2(-Iso.HALF.x, 0)
	if edge.z == Terrain.EAST:
		return [s, e]
	return [w, s]


## Drawn height of an edge whose -x / -y cell is or is not floor.
static func height(near_side_is_floor: bool) -> float:
	var full := Iso.height_px("wall")
	return Iso.TILE_SIZE.y * STUB_FRACTION if near_side_is_floor else full


## Position of the vertex (shared diamond corner) an edge end sits on, as
## the cell whose north corner it is.
static func vertex_at(edge: Vector3i, end: int) -> Vector2i:
	var c := Vector2i(edge.x, edge.y)
	if edge.z == Terrain.EAST:
		return c + (Vector2i(1, 1) if end == 0 else Vector2i(1, 0))
	return c + (Vector2i(0, 1) if end == 0 else Vector2i(1, 1))


## The four edges that can meet at the vertex that is [param v]'s north
## corner, paired by direction: [east-running pair, south-running pair].
static func edges_at_vertex(v: Vector2i) -> Array:
	return [
		[Vector3i(v.x - 1, v.y - 1, Terrain.EAST), Vector3i(v.x - 1, v.y, Terrain.EAST)],
		[Vector3i(v.x, v.y - 1, Terrain.SOUTH), Vector3i(v.x - 1, v.y - 1, Terrain.SOUTH)],
	]


## An end mark goes where the edges meeting at a vertex are not exactly two
## walls running straight through it. [param kind_at] gives Terrain.Edge for
## a key (OPEN if none).
static func needs_end(v: Vector2i, kind_at: Callable) -> bool:
	var walls := 0
	var doors := 0
	var straight := false
	for pair: Array in edges_at_vertex(v):
		var a: int = kind_at.call(pair[0])
		var b: int = kind_at.call(pair[1])
		for kind in [a, b]:
			if kind == Terrain.Edge.WALL:
				walls += 1
			elif kind == Terrain.Edge.DOOR:
				doors += 1
		if a == Terrain.Edge.WALL and b == Terrain.Edge.WALL:
			straight = true
	return doors > 0 or not (straight and walls == 2)


## Draws a face of [param h] pixels standing on the line [param a]-[param b]
## with the lit strip along its top. Shared with Door.
static func draw_face(on: CanvasItem, a: Vector2, b: Vector2, h: float, color: Color) -> void:
	var up := Vector2(0, -h)
	var strip := Vector2(0, -maxf(h - TOP_STRIP, 0.0))
	on.draw_colored_polygon(PackedVector2Array([a, b, b + strip, a + strip]), color)
	on.draw_colored_polygon(PackedVector2Array([a + strip, b + strip, b + up, a + up]), TOP)


func setup(edge: Vector3i, kind_at: Callable, floor_at: Callable) -> void:
	key = edge
	position = Iso.tile_to_local(Vector2i(edge.x, edge.y)) + Vector2(0, 0.5)
	near = floor_at.call(Vector2i(edge.x, edge.y))
	end_at_start = needs_end(vertex_at(edge, 0), kind_at)
	end_at_end = needs_end(vertex_at(edge, 1), kind_at)
	queue_redraw()


func _draw() -> void:
	var ends := endpoints(key)
	var h := height(near)
	draw_face(self, ends[0], ends[1], h, FACE_EAST if key.z == Terrain.EAST else FACE_SOUTH)
	var up := Vector2(0, -h)
	if end_at_start:
		draw_line(ends[0], ends[0] + up, END)
	if end_at_end:
		draw_line(ends[1], ends[1] + up, END)
