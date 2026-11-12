class_name UiClose
extends Button
## A window's close (decision 886; the parts' design, C:/dev/review/ui-design/
## parts_design.md: UiClose, the drawn x, top right of every window): the
## theme's button face, a target of the Close type's size (72 units) with the
## x drawn in it, bone at rest and flame under the pointer or pressed. The
## caller connects pressed (a window's Esc does the same).


func _init() -> void:
	theme_type_variation = &"Close"
	focus_mode = Control.FOCUS_NONE
	tooltip_text = ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_ENTER_TREE:
		var side := float(get_theme_constant(&"size", &"Close"))
		custom_minimum_size = Vector2(side, side)


func _draw() -> void:
	var name := &"icon_normal_color"
	if is_pressed() or get_draw_mode() == DRAW_PRESSED:
		name = &"icon_pressed_color"
	elif is_hovered():
		name = &"icon_hover_color"
	var colour := get_theme_color(name, &"Close")
	var stroke := float(get_theme_constant(&"stroke", &"Close"))
	var middle := size / 2.0
	var arm := minf(size.x, size.y) * 0.22
	draw_line(middle + Vector2(-arm, -arm), middle + Vector2(arm, arm), colour, stroke, true)
	draw_line(middle + Vector2(arm, -arm), middle + Vector2(-arm, arm), colour, stroke, true)
