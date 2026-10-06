class_name WallEdge
extends Node2D
## One wall edge drawn as a thin face standing on the cell boundary, as tall
## as the scale table says, in the Y-sorted layer with the cell on its
## -x / -y side. Where the wall ends, turns a corner, or meets a door, a post
## is drawn at that end; where it runs straight on, nothing, so runs read as
## one wall. Placeholder colours, no texture.
##
## Main fades a face that would draw over the local player's cell.

const FACE_EAST := Color(0.263, 0.278, 0.353)  # The south-east side of a cell.
const FACE_SOUTH := Color(0.353, 0.373, 0.45)  # The south-west side, lit.
const TOP := Color(0.54, 0.565, 0.66)
const EDGE := Color(0.12, 0.12, 0.16, 0.8)
const POST := Color(0.3, 0.3, 0.38)
const POST_WIDTH := 3.0
const HIDING_ALPHA := 0.3

var key := Vector3i.ZERO
var post_at_start := false
var post_at_end := false


## Where an edge runs, in the local space of its -x / -y cell's centre:
## the two corners of that cell's diamond it joins, start to end.
static func endpoints(edge: Vector3i) -> Array[Vector2]:
	var e := Vector2(Iso.HALF.x, 0)
	var s := Vector2(0, Iso.HALF.y)
	var w := Vector2(-Iso.HALF.x, 0)
	if edge.z == Terrain.EAST:
		return [s, e]
	return [w, s]


## Position of the vertex (shared diamond corner) an edge end sits on, as
## the cell whose north corner it is.
static func vertex_at(edge: Vector3i, end: int) -> Vector2i:
	var c := Vector2i(edge.x, edge.y)
	if edge.z == Terrain.EAST:
		# South corner of c is the north corner of c + (1, 1); east corner, of c + (1, 0).
		return c + (Vector2i(1, 1) if end == 0 else Vector2i(1, 0))
	# West corner of c is the north corner of c + (0, 1); south corner, of c + (1, 1).
	return c + (Vector2i(0, 1) if end == 0 else Vector2i(1, 1))


## The four edges that can meet at the vertex that is [param v]'s north
## corner, paired by direction: [east-running pair, south-running pair].
static func edges_at_vertex(v: Vector2i) -> Array:
	return [
		[Vector3i(v.x - 1, v.y - 1, Terrain.EAST), Vector3i(v.x - 1, v.y, Terrain.EAST)],
		[Vector3i(v.x, v.y - 1, Terrain.SOUTH), Vector3i(v.x - 1, v.y - 1, Terrain.SOUTH)],
	]


## A post is drawn where the edges meeting at a vertex are not exactly two
## walls running straight through it. [param kind_at] gives Terrain.Edge for
## a key (OPEN if none).
static func needs_post(v: Vector2i, kind_at: Callable) -> bool:
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


static func draw_post(on: CanvasItem, at: Vector2, up: Vector2, color: Color) -> void:
	var half := Vector2(POST_WIDTH * 0.5, 0)
	on.draw_colored_polygon(PackedVector2Array([at - half, at + half, at + half + up, at - half + up]), color)
	on.draw_line(at - half + up, at + half + up, TOP)


func setup(edge: Vector3i, kind_at: Callable) -> void:
	key = edge
	position = Iso.tile_to_local(Vector2i(edge.x, edge.y)) + Vector2(0, 0.5)
	post_at_start = needs_post(vertex_at(edge, 0), kind_at)
	post_at_end = needs_post(vertex_at(edge, 1), kind_at)
	queue_redraw()


## The face in local space.
func face_polygon() -> PackedVector2Array:
	var ends := endpoints(key)
	var up := Vector2(0, -Iso.height_px("wall"))
	return PackedVector2Array([ends[0], ends[1], ends[1] + up, ends[0] + up])


func set_hiding(on: bool) -> void:
	modulate.a = HIDING_ALPHA if on else 1.0


func _draw() -> void:
	var ends := endpoints(key)
	var up := Vector2(0, -Iso.height_px("wall"))
	var face := face_polygon()
	draw_colored_polygon(face, FACE_EAST if key.z == Terrain.EAST else FACE_SOUTH)
	draw_line(face[3], face[2], TOP, 2.0)
	draw_line(face[0], face[1], EDGE)
	if post_at_start:
		draw_post(self, ends[0], up, POST)
	if post_at_end:
		draw_post(self, ends[1], up, POST)
