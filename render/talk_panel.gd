class_name TalkPanel
extends PanelContainer
## What has been said this session: companions' speech, their last words
## and players' chat, newest at the bottom, the last MAX_LINES of them,
## each with who said it and when (this machine's clock). Tab shows and
## hides it (Main); it is kept for the session, never saved. In the shared
## theme's look (UiTheme, docs/ui_style.md): the speaker's name in the
## serif face, brass_bright; what was said aloud in bone; a party line
## (it crosses zones) in the party colour and marked; the time is the
## line's tooltip, not printed.

const MAX_LINES := 20
## The colours, the theme's.
static var SPEAKER: Color = UiTheme.color("brass_bright")
static var CHAT: Color = UiTheme.color("aloud")
static var PARTY: Color = UiTheme.color("party")

var _list: VBoxContainer
## [time, speaker, text, is_chat] each, oldest first.
var lines: Array[Array] = []


func _init() -> void:
	name = "TalkPanel"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list = VBoxContainer.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_theme_constant_override("separation", 4)
	add_child(_list)


## A line was added (Main's UiSounds: a chat ping, a party chime).
signal line_added(speaker: String, is_chat: bool, party: bool)


## [param party]: a party chat line (Main), shown apart from what is said
## around the player.
func add_line(speaker: String, text: String, is_chat := false, party := false) -> void:
	line_added.emit(speaker, is_chat, party)
	var at := Time.get_time_string_from_system().substr(0, 8)
	lines.append([at, speaker, text, is_chat])
	if lines.size() > MAX_LINES:
		lines.pop_front()
	var label := RichTextLabel.new()
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 900
	# Hover for when it was said; the rows take the mouse for that alone.
	label.tooltip_text = at
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	var said := PARTY if party else CHAT
	if party:
		label.push_color(PARTY)
		label.add_text("[party] ")
		label.pop()
	label.push_font(UiTheme.font("serif"))
	label.push_color(SPEAKER)
	label.add_text("%s: " % speaker)
	label.pop()
	label.pop()
	label.push_color(said)
	label.add_text(text)
	label.pop()
	_list.add_child(label)
	while _list.get_child_count() > MAX_LINES:
		var oldest := _list.get_child(0)
		_list.remove_child(oldest)
		oldest.queue_free()
