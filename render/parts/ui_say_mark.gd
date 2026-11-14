class_name UiSayMark
extends Control
## The speech mark at a typing line's left (the trader mock, C:/dev/review/ui-design/trader/: a small
## flame bubble before the caret, in every state of the line): a rounded rect with its tail down and
## left, drawn in the theme's SayMark colour at the SayMark size. Takes no input; the caller places it
## inside the line, before the field.


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = &"SayMark"
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_ENTER_TREE:
		custom_minimum_size = Vector2(get_theme_constant(&"width", &"SayMark"), get_theme_constant(&"height", &"SayMark"))
		queue_redraw()


func _draw() -> void:
	var colour := get_theme_color(&"mark", &"SayMark")
	var tail := float(get_theme_constant(&"tail", &"SayMark"))
	var body := Rect2(Vector2.ZERO, Vector2(size.x, maxf(size.y - tail, 1.0)))
	var shape := StyleBoxFlat.new()
	shape.bg_color = colour
	shape.set_corner_radius_all(get_theme_constant(&"radius", &"SayMark"))
	shape.anti_aliasing = true
	draw_style_box(shape, body)
	# The tail: from the body's foot near its left, down and a little left (the mock's (9, 28)-(20, 28)-(7, 40)).
	var foot := body.end.y - 2.0
	var at := body.size.x * 0.2
	draw_colored_polygon(PackedVector2Array([Vector2(at, foot), Vector2(at + body.size.x * 0.25, foot),
		Vector2(at - body.size.x * 0.05, body.end.y + tail)]), colour)
