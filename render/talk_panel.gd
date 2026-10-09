class_name TalkPanel
extends PanelContainer
## What has been said this session: companions' speech, their last words
## and players' chat, newest at the bottom, the last MAX_LINES of them,
## each with who said it and when (this machine's clock). Tab shows and
## hides it (Main); it is kept for the session, never saved.

const MAX_LINES := 20
const SPEAKER := Color(1, 0.95, 0.6)
const CHAT := Color(0.7, 0.85, 1.0)
## Party chat, which crosses zones: its own colour, and marked.
const PARTY := Color(0.72, 1.0, 0.7)

var _list: VBoxContainer
## [time, speaker, text, is_chat] each, oldest first.
var lines: Array[Array] = []


func _init() -> void:
	name = "TalkPanel"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.7)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)
	_list = VBoxContainer.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_list)


## [param party]: a party chat line (Main), shown apart from what is said
## around the player.
func add_line(speaker: String, text: String, is_chat := false, party := false) -> void:
	var at := Time.get_time_string_from_system().substr(0, 8)
	lines.append([at, speaker, text, is_chat])
	if lines.size() > MAX_LINES:
		lines.pop_front()
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 900
	label.text = "%s  %s%s: %s" % [at, "[party] " if party else "", speaker, text]
	label.add_theme_color_override("font_color", PARTY if party else CHAT if is_chat else SPEAKER)
	_list.add_child(label)
	while _list.get_child_count() > MAX_LINES:
		var oldest := _list.get_child(0)
		_list.remove_child(oldest)
		oldest.queue_free()
