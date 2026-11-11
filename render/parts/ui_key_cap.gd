class_name UiKeyCap
extends PanelContainer
## One key as the hints draw it (decision 872; the coordinator's approval of the
## hints mock, 11-11, C:/dev/review/ui-design/hints/): a key cap (KeyCap: a dark
## cap with a brass rim, its name in KeyText), or a mouse button as a small
## mouse with that button lit in brass_bright ("LMB", "RMB", "MMB", "Wheel"),
## so a hint line is read by its picture first. row() lays out a set of keys
## with their joins ("+", "/") in KeyJoin. Which keys a line shows, and its
## words, are the caller's (Main.hint_lines).

## The names drawn as a mouse, and the button each lights.
const MOUSE := ["LMB", "RMB", "MMB", "Wheel"]
## The joins drawn as words between caps.
const JOINS := ["+", "/"]

## The key shown ("E", "Enter", "LMB").
var key := ""
var _label: Label
## The mouse's body and its lit button, made once a theme.
var _body: StyleBoxFlat
var _lit: StyleBoxFlat
var _made_at := -1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = &"KeyCap"
	_label = Label.new()
	_label.theme_type_variation = &"KeyText"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)


## Shows [param name]: a mouse for MOUSE's names, else the key's cap.
func set_key(name: String) -> void:
	key = name
	var is_mouse := is_mouse_key(name)
	theme_type_variation = &"KeyMouse" if is_mouse else &"KeyCap"
	_label.visible = not is_mouse
	_label.text = "" if is_mouse else name
	_fit()
	queue_redraw()


func is_mouse() -> bool:
	return is_mouse_key(key)


static func is_mouse_key(name: String) -> bool:
	return name in MOUSE


## A row of [param keys] ("Shift", "+", "LMB"): a cap for each key and KeyJoin
## words for each join, side by side.
static func row(keys: Array) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.theme_type_variation = &"KeyRow"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for one: Variant in keys:
		var name := str(one)
		if name in JOINS:
			var join := Label.new()
			join.theme_type_variation = &"KeyJoin"
			join.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			join.text = name
			box.add_child(join)
		else:
			var cap := UiKeyCap.new()
			cap.set_key(name)
			box.add_child(cap)
	return box


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_body = null
		_fit()


## A mouse is as tall as a cap and a little narrower than tall; a key's cap
## is at least square.
func _fit() -> void:
	var tall := _cap_height()
	custom_minimum_size = Vector2(tall * 0.72, tall) if is_mouse() else Vector2(tall, tall)


func _cap_height() -> float:
	var font := get_theme_font(&"font", &"KeyText")
	var font_size := get_theme_font_size(&"font_size", &"KeyText")
	var box := get_theme_stylebox(&"panel", &"KeyCap")
	return font.get_height(font_size) + box.get_margin(SIDE_TOP) + box.get_margin(SIDE_BOTTOM)


func _draw() -> void:
	if not is_mouse():
		return
	if _body == null or _made_at != size.y:
		_make_mouse()
	var tall := size.y * 0.9
	var wide := tall * 0.74
	var at := Vector2((size.x - wide) / 2.0, (size.y - tall) / 2.0)
	var line := maxf(2.0, tall * 0.055)
	draw_style_box(_body, Rect2(at, Vector2(wide, tall)))
	var split := tall * 0.44
	var inset := line * 1.5
	var half := Vector2(wide / 2.0 - inset, split - inset)
	match key:
		"LMB":
			draw_style_box(_lit, Rect2(at + Vector2(inset, inset), half))
		"RMB":
			draw_style_box(_lit, Rect2(at + Vector2(wide / 2.0, inset), half))
		_:
			var wheel := Vector2(wide * 0.26, split * 0.62)
			draw_rect(Rect2(at + Vector2((wide - wheel.x) / 2.0, (split - wheel.y) / 2.0 + inset * 0.3), wheel), UiTheme.color("brass_bright"))
	var ink := UiTheme.color("text")
	draw_line(at + Vector2(wide / 2.0, line), at + Vector2(wide / 2.0, split), ink, line, true)
	draw_line(at + Vector2(line, split), at + Vector2(wide - line, split), ink, line, true)


func _make_mouse() -> void:
	var tall := size.y * 0.9
	var line := maxf(2.0, tall * 0.055)
	_made_at = size.y
	_body = StyleBoxFlat.new()
	_body.bg_color = UiTheme.color("backing_deep")
	_body.border_color = UiTheme.color("text")
	_body.set_border_width_all(int(line))
	_body.set_corner_radius_all(int(tall * 0.36))
	_body.anti_aliasing = true
	_lit = StyleBoxFlat.new()
	_lit.bg_color = UiTheme.color("brass_bright")
	_lit.set_corner_radius_all(int(tall * 0.14))
	_lit.anti_aliasing = true
