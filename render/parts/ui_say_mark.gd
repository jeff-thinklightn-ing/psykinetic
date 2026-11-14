class_name UiSayMark
extends Control
## The speech mark at a typing line's left (the trader mock, C:/dev/review/ui-design/trader/: a small
## flame bubble before the caret, in every state of the line): a rounded rect with its tail down and
## left, drawn at the SayMark size. Takes no input.
## Made a child of its LineEdit (whose variation is SayLine, the room left for it in its own left
## margin), it places itself inside the field: SayMark's inset from the field's left, centred down
## it, and kept there as the field changes size; it is drawn in SayMark's mark while the field has
## the keys, mark_idle else (the mock's lit and resting line). Anywhere else, the caller places it.

var _field: LineEdit


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = &"SayMark"
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_ENTER_TREE:
		custom_minimum_size = Vector2(get_theme_constant(&"width", &"SayMark"), get_theme_constant(&"height", &"SayMark"))
		size = custom_minimum_size
		_place()
		queue_redraw()
	if what == NOTIFICATION_PARENTED:
		_field = get_parent() as LineEdit
		if _field != null:
			_field.resized.connect(_place)
			_field.focus_entered.connect(queue_redraw)
			_field.focus_exited.connect(queue_redraw)
	elif what == NOTIFICATION_UNPARENTED:
		if _field != null and is_instance_valid(_field):
			_field.resized.disconnect(_place)
			_field.focus_entered.disconnect(queue_redraw)
			_field.focus_exited.disconnect(queue_redraw)
		_field = null


## Inside its field: the inset from the field's left, centred down it.
func _place() -> void:
	if _field == null:
		return
	position = Vector2(get_theme_constant(&"inset", &"SayMark"), roundf((_field.size.y - size.y) / 2.0))


func _draw() -> void:
	var lit := _field == null or _field.has_focus()
	var colour := get_theme_color(&"mark" if lit else &"mark_idle", &"SayMark")
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
