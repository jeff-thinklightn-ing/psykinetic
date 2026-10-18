class_name HintPanel
extends PanelContainer
## The controls, one to a line, in small text on a soft backing down the
## HUD's left side. H shows and hides it (Main; remembered in settings.cfg
## as hints=). Sizes in the HUD's 3840 x 2160 units; the look is the shared
## theme's (UiTheme, docs/ui_style.md), a key in brass.

var _list: VBoxContainer
var _lines: Array[String] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2(UiTheme.constant("margin"), 110)
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
		var parts := line.split("\t", true, 1)
		row.text = "[color=#%s]%s[/color]  %s" % [UiTheme.color("brass").to_html(true), parts[0], parts[1] if parts.size() > 1 else ""] \
				if parts.size() > 1 else line
		row.custom_minimum_size = Vector2(560, 0)
		_list.add_child(row)
	reset_size()


func lines() -> Array[String]:
	return _lines.duplicate()
