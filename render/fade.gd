class_name DistanceFade
extends Node2D
## Darkness beyond a distance from the local player: clear out to
## CLEAR_TILES, fading to black by BLACK_TILES, black beyond. Drawn as rings
## in tile distance, which on the 2:1 diamond grid is an ellipse on screen.
## Presentation only: it is moved to the player every frame and knows
## nothing about the sim. Not a lighting system.

const CLEAR_TILES := 9.0
const BLACK_TILES := 12.0
const RINGS := 12
const SEGMENTS := 48
## Far enough to cover any window at any zoom.
const BEYOND := 6000.0


func _ready() -> void:
	# A circle of tile radius r is an ellipse of r * 16 * sqrt(2) by half that.
	scale = Vector2(1.0, 0.5)
	queue_redraw()


func _draw() -> void:
	var unit := Iso.HALF.x * sqrt(2.0)  # Screen x per tile of distance.
	var inner := CLEAR_TILES * unit
	var outer := BLACK_TILES * unit
	for ring in RINGS:
		var a0 := float(ring) / RINGS
		var a1 := float(ring + 1) / RINGS
		_ring(lerpf(inner, outer, a0), lerpf(inner, outer, a1), ease(a0, 1.6), ease(a1, 1.6))
	_ring(outer, BEYOND, 1.0, 1.0)


func _ring(r0: float, r1: float, alpha0: float, alpha1: float) -> void:
	var c0 := Color(0, 0, 0, alpha0)
	var c1 := Color(0, 0, 0, alpha1)
	for i in SEGMENTS:
		var a := TAU * i / SEGMENTS
		var b := TAU * (i + 1) / SEGMENTS
		var p0 := Vector2(cos(a), sin(a))
		var p1 := Vector2(cos(b), sin(b))
		draw_polygon(PackedVector2Array([p0 * r0, p1 * r0, p1 * r1, p0 * r1]),
				PackedColorArray([c0, c0, c1, c1]))
