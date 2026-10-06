class_name WallBlock
extends Node2D
## One wall tile drawn as a block: a top face and whichever of the two
## camera-facing sides (+x, south-east on screen; +y, south-west) are not
## hidden by a neighbouring wall. Adjacent blocks therefore join into
## continuous walls, and corners, end caps and straight runs fall out of the
## neighbours with no tile choosing of their own. Placeholder colours; no
## texture.
##
## A block three tiles tall hides what stands behind it, so while any entity
## is in the region it covers, the block is drawn translucent (Main asks
## hides() each frame). Otherwise walls are solid.

const TOP := Color(0.54, 0.565, 0.66)
const SIDE_Y := Color(0.353, 0.373, 0.45)  # +y face, lit side.
const SIDE_X := Color(0.263, 0.278, 0.353)  # +x face, shaded side.
const EDGE := Color(0.12, 0.12, 0.16, 0.8)
const SEE_THROUGH_ALPHA := 0.4
## The block's height in rows of (x + y): each row is HALF.y of screen height.
const ROWS_TALL := int(Iso.HEIGHTS["wall"] * 2)

var tile := Vector2i.ZERO
## Faces: which sides are exposed; rims: which top edges border no wall.
var face_x := true
var face_y := true
var rim_minus_x := true  # Top edge along the north-east side.
var rim_minus_y := true  # Top edge along the north-west side.


## [param wall_at] answers whether a tile holds a wall; the four neighbours
## of [param at] decide the faces.
func setup(at: Vector2i, wall_at: Callable) -> void:
	tile = at
	position = Iso.tile_to_local(at)
	face_x = not wall_at.call(at + Vector2i(1, 0))
	face_y = not wall_at.call(at + Vector2i(0, 1))
	rim_minus_x = not wall_at.call(at + Vector2i(-1, 0))
	rim_minus_y = not wall_at.call(at + Vector2i(0, -1))
	queue_redraw()


## Would this block be drawn over something standing on [param other]? The
## block covers its own screen column (one tile either side) from its tile
## up to its top, ROWS_TALL rows of x + y above.
func hides(other: Vector2i) -> bool:
	var d := other - tile
	return d.x <= 0 and d.y <= 0 and d != Vector2i.ZERO \
			and d.x + d.y >= -ROWS_TALL and absi(d.x - d.y) <= 1


func set_see_through(on: bool) -> void:
	modulate.a = SEE_THROUGH_ALPHA if on else 1.0


func _draw() -> void:
	var h := Iso.height_px("wall")
	var up := Vector2(0, -h)
	# Diamond corners, clockwise from the north point.
	var n := Vector2(0, -Iso.HALF.y)
	var e := Vector2(Iso.HALF.x, 0)
	var s := Vector2(0, Iso.HALF.y)
	var w := Vector2(-Iso.HALF.x, 0)
	if face_y:
		draw_colored_polygon(PackedVector2Array([w, s, s + up, w + up]), SIDE_Y)
	if face_x:
		draw_colored_polygon(PackedVector2Array([s, e, e + up, s + up]), SIDE_X)
	draw_colored_polygon(PackedVector2Array([n + up, e + up, s + up, w + up]), TOP)
	# Rims on the top face where it ends, and the vertical edges of open faces.
	if face_y:
		draw_line(w + up, s + up, EDGE)
		draw_line(w, w + up, EDGE)
	if face_x:
		draw_line(s + up, e + up, EDGE)
		draw_line(e, e + up, EDGE)
	if face_x or face_y:
		draw_line(s, s + up, EDGE)
	if rim_minus_x:
		draw_line(n + up, e + up, EDGE)
	if rim_minus_y:
		draw_line(w + up, n + up, EDGE)
