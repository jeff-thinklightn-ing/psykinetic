class_name PathPreview
extends Node2D
## A faint dotted line on the floor from the local player to the hovered
## cell, along the path the client would predict, through any door on the
## way. Drawn above walls so the route reads even where a wall stands in
## front of it. Presentation only. Main sets the points and clears them on
## a click.

const DOT := Color(1, 1, 1, 0.45)
const DOT_RADIUS := 1.2
const DOT_SPACING := 6.0

var _points: Array[Vector2] = []


func show_path(points: Array[Vector2]) -> void:
	if points == _points:
		return
	_points = points
	queue_redraw()


func clear() -> void:
	show_path([])


func _draw() -> void:
	# Dots at a fixed spacing along each segment, carrying the remainder
	# over so the spacing is even round corners.
	var carry := 0.0
	for i in range(1, _points.size()):
		var a := _points[i - 1]
		var b := _points[i]
		var length := a.distance_to(b)
		var along := (b - a) / maxf(length, 0.001)
		var at := carry
		while at < length:
			draw_circle(a + along * at, DOT_RADIUS, DOT)
			at += DOT_SPACING
		carry = at - length
