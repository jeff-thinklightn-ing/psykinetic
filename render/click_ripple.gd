class_name ClickRipple
extends Node2D
## The ring that answers a move click: drawn on the floor at the target
## cell's centre, it grows from a few px to a tile across over a quarter
## second and fades as it goes. One ring at a time; a new click restarts it
## where the click landed. Drawing only.

const SECONDS := 0.25
const RADIUS_FROM := 4.0
## Tile-sized at the end: a diamond's half extents.
const RADIUS_TO := float(Iso.HALF.x)
## A step lighter than the floor, no fill.
const COLOR := Color(0.58, 0.76, 0.69)
const SEGMENTS := 32

## Seconds since the ring started, past SECONDS when there is none.
var _age := SECONDS


## Starts a ring at [param at], in the parent's space.
func start(at: Vector2) -> void:
	position = at
	_age = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if _age >= SECONDS:
		return
	_age = minf(_age + delta, SECONDS)
	queue_redraw()


func _draw() -> void:
	if _age >= SECONDS:
		return
	var t := _age / SECONDS
	var radius := lerpf(RADIUS_FROM, RADIUS_TO, t)
	var color := COLOR
	color.a = 1.0 - t
	# A ring lying on the floor is an ellipse at the tile's 2:1 aspect.
	var points := PackedVector2Array()
	for i in SEGMENTS + 1:
		var angle := TAU * i / SEGMENTS
		points.append(Vector2(cos(angle) * radius, sin(angle) * radius * 0.5))
	draw_polyline(points, color, 1.5)
