class_name HintPanel
extends PanelContainer
## The controls, one to a line, in small text on a soft backing down the
## HUD's left side. H shows and hides it (Main; remembered in settings.cfg
## as hints=). Two columns, a key in brass. Off by default since step 3
## (the context hint over what the cursor is on says what the keys do
## there); H shows the whole list. Sizes in the HUD's 3840 x 2160 units;
## the look is the shared theme's (UiTheme, docs/ui_style.md).

var _list: HBoxContainer
var _columns: Array[VBoxContainer] = []
var _lines: Array[String] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2(UiTheme.constant("margin"), 110)
	_list = HBoxContainer.new()
	_list.add_theme_constant_override("separation", UiTheme.constant("section"))
	add_child(_list)
	for i in 2:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		_list.add_child(column)
		_columns.append(column)


## [param lines], each "key<TAB>what it does": the key drawn in its own colour.
func set_lines(lines: Array[String]) -> void:
	if lines == _lines:
		return
	_lines = lines.duplicate()
	for column in _columns:
		for child in column.get_children():
			column.remove_child(child)
			child.queue_free()
	var half := ceili(lines.size() / 2.0)
	for i in lines.size():
		var line := lines[i]
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
		_columns[0 if i < half else 1].add_child(row)
	reset_size()


func lines() -> Array[String]:
	return _lines.duplicate()
