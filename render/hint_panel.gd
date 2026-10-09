class_name HintPanel
extends PanelContainer
## The controls, one to a line, in small text on a soft backing down the
## HUD's left side. H shows and hides it (Main; remembered in settings.cfg
## as hints=). Sizes in the HUD's 3840 x 2160 units.

const FONT_SIZE := 30
const BACKING := Color(0.04, 0.04, 0.06, 0.42)
const TEXT := Color(0.93, 0.92, 0.88, 0.92)
const KEY := Color(1.0, 0.86, 0.55, 0.95)

var _list: VBoxContainer
var _lines: Array[String] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2(40, 110)
	var style := StyleBoxFlat.new()
	style.bg_color = BACKING
	style.set_corner_radius_all(16)
	style.content_margin_left = 22
	style.content_margin_right = 26
	style.content_margin_top = 14
	style.content_margin_bottom = 16
	add_theme_stylebox_override("panel", style)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	add_child(_list)


## [param lines], each "key<TAB>what it does": the key drawn in its own colour.
func set_lines(lines: Array[String]) -> void:
	if lines == _lines:
		return
	_lines = lines.duplicate()
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for line in lines:
		var row := RichTextLabel.new()
		row.bbcode_enabled = true
		row.fit_content = true
		row.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.scroll_active = false
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_font_size_override("normal_font_size", FONT_SIZE)
		row.add_theme_color_override("default_color", TEXT)
		var parts := line.split("\t", true, 1)
		row.text = "[color=#%s]%s[/color]  %s" % [KEY.to_html(true), parts[0], parts[1] if parts.size() > 1 else ""] \
				if parts.size() > 1 else line
		row.custom_minimum_size = Vector2(560, 0)
		_list.add_child(row)
	reset_size()


func lines() -> Array[String]:
	return _lines.duplicate()
