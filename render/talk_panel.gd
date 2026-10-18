class_name TalkPanel
extends PanelContainer
## What has been said this session: companions' speech, their last words
## and players' chat, newest at the bottom, the last MAX_LINES of them,
## each with who said it and when (this machine's clock). Kept for the
## session, never saved. In the shared theme's look (UiTheme,
## docs/ui_style.md): the speaker's name in the serif face, brass_bright;
## what was said aloud in bone; a party line (it crosses zones) in the
## party colour and marked; the time is the line's tooltip, not printed.
##
## One box with the chat box (Main's LineEdit, adopted by set_box): a line
## shows the panel for FADE_AFTER seconds after it comes, then the panel
## goes unless it is pinned (Tab, toggle_pin), the mouse is over it, or
## the chat box is open; the list scrolls (the wheel) while pinned. The
## chat box's channel ("say" or "party", from Main's /p prefix) is named
## beside it. Companions own what the log records (lines[]'s shape, the
## keep); ui the look (decisions 401, step 3).

## A line was added: who said it, a chat line, a party line (sound's).
signal line_added(speaker: String, is_chat: bool, party: bool)

const MAX_LINES := 20
## How long a new line keeps the panel shown, unpinned.
const FADE_AFTER := 8.0
const WIDTH := 900.0
const LIST_HEIGHT := 520.0
## The colours, the theme's.
static var SPEAKER: Color = UiTheme.color("brass_bright")
static var CHAT: Color = UiTheme.color("aloud")
static var PARTY: Color = UiTheme.color("party")

## Tab: kept shown, and scrollable.
var pinned := false
## [time, speaker, text, is_chat] each, oldest first.
var lines: Array[Array] = []

var _list: VBoxContainer
var _scroll: ScrollContainer
var _box_row: HBoxContainer
var _channel: Label
var _box: LineEdit
var _hovering := false
var _shown_until := 0.0


func _init() -> void:
	name = "TalkPanel"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_entered.connect(func() -> void: _hovering = true)
	mouse_exited.connect(func() -> void: _hovering = false)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiTheme.constant("row"))
	add_child(column)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(WIDTH, 0)
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	# The scroll box is the list's own: no inset box inside the panel.
	_scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	column.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.mouse_filter = Control.MOUSE_FILTER_PASS
	_list.add_theme_constant_override("separation", 4)
	_scroll.add_child(_list)
	_box_row = HBoxContainer.new()
	_box_row.add_theme_constant_override("separation", UiTheme.constant("row"))
	_box_row.visible = false
	column.add_child(_box_row)
	_channel = Label.new()
	_channel.theme_type_variation = &"Caption"
	_channel.custom_minimum_size = Vector2(90, 0)
	_channel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_box_row.add_child(_channel)


## Main's chat box, put in the panel under the lines; its channel named
## beside it from its text ("/p " for party, Main.PARTY_PREFIX).
func set_box(box: LineEdit) -> void:
	_box = box
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box_row.add_child(box)
	box.text_changed.connect(func(_text: String) -> void: _show_channel())
	box.visibility_changed.connect(func() -> void:
		_box_row.visible = box.visible
		if box.visible:
			visible = true
			_scroll_to_end()
		_show_channel())
	_show_channel()


## Tab: the panel kept shown (and scrollable) or let fade.
func toggle_pin() -> void:
	pinned = not pinned
	if pinned:
		visible = true
		_scroll_to_end()


## Whether the channel named beside the box is party ("/p ").
func channel_shown() -> String:
	return _channel.text


## [param party]: a party chat line (Main), shown apart from what is said
## around the player.
func add_line(speaker: String, text: String, is_chat := false, party := false) -> void:
	var at := Time.get_time_string_from_system().substr(0, 8)
	lines.append([at, speaker, text, is_chat])
	if lines.size() > MAX_LINES:
		lines.pop_front()
	var label := RichTextLabel.new()
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_shown_until = Time.get_ticks_msec() / 1000.0 + FADE_AFTER
	visible = true
	_scroll_to_end()
	line_added.emit(speaker, is_chat, party)


## Whether the panel is kept shown by a recent line, the pin, the mouse
## or the open chat box (tests).
func keeps_showing() -> bool:
	var typing := _box != null and _box.visible
	return pinned or _hovering or typing or Time.get_ticks_msec() / 1000.0 < _shown_until


func _process(_delta: float) -> void:
	var began := Time.get_ticks_usec()
	if visible and not keeps_showing():
		visible = false
	if _box != null and _box.visible:
		_show_channel()  # Main may set the text (Tab), which text_changed does not say.
	# As tall as its lines, up to LIST_HEIGHT while pinned (then it scrolls).
	_scroll.custom_minimum_size.y = minf(_list.get_combined_minimum_size().y, LIST_HEIGHT)
	UiCost.add("talk", Time.get_ticks_usec() - began)


func _show_channel() -> void:
	if _box == null:
		return
	_channel.text = "party" if _box.text.begins_with("/p") else "say"


func _scroll_to_end() -> void:
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
