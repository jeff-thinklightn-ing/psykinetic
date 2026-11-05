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
##
## Gains (decision 804): the button over the lines shows instead what the
## player has gained this session (Gains.lines, by gains_of), newest at the
## bottom, each in its track's colour with its words dim after it; pressed
## again, the talk.

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
## A resident's aside (npc's 336 amended, ui's side): how the line was said,
## dim after the speech.
static var ASIDE: Color = UiTheme.color("text_dim")
## What sets an aside off from the speech on its row.
const ASIDE_DASH := " — "

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
## () -> Gains.lines (Main); none: no Gains button.
var gains_of: Callable
## Whether the Gains list shows in place of the talk.
var showing_gains := false
var _gains_button: Button
var _gains_list: VBoxContainer


func _init() -> void:
	name = "TalkPanel"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_entered.connect(func() -> void: _hovering = true)
	mouse_exited.connect(func() -> void: _hovering = false)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiTheme.constant("row"))
	add_child(column)
	_gains_button = Button.new()
	_gains_button.name = "GainsButton"
	_gains_button.text = "Gains"  # Voice's (804).
	_gains_button.toggle_mode = true
	_gains_button.theme_type_variation = &"Small"
	_gains_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_gains_button.focus_mode = Control.FOCUS_NONE
	_gains_button.visible = false
	_gains_button.toggled.connect(show_gains)
	column.add_child(_gains_button)
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
	var lists := VBoxContainer.new()
	lists.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lists.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(lists)
	lists.add_child(_list)
	_gains_list = VBoxContainer.new()
	_gains_list.name = "GainsList"
	_gains_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gains_list.mouse_filter = Control.MOUSE_FILTER_PASS
	_gains_list.add_theme_constant_override("separation", 4)
	_gains_list.visible = false
	lists.add_child(_gains_list)
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
## around the player. [param aside]: a resident's one clause of how the line
## was said (npc's 336 amended; "his voice steady despite the rain"), shown
## after the speech on the same row, dim, in the sans, set off by a spaced
## dash, no quotes; "" shows nothing (players and companions carry none).
func add_line(speaker: String, text: String, is_chat := false, party := false, aside := "") -> void:
	var at := Time.get_time_string_from_system().substr(0, 8)
	lines.append([at, speaker, text, is_chat, aside])
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
	if not aside.is_empty():
		label.push_font(UiTheme.font("sans"))
		label.push_color(ASIDE)
		label.add_text(ASIDE_DASH + aside)
		label.pop()
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


## The Gains list in place of the talk ([param on]), or the talk again.
func show_gains(on: bool) -> void:
	showing_gains = on and gains_of.is_valid()
	_gains_button.set_pressed_no_signal(showing_gains)
	_list.visible = not showing_gains
	_gains_list.visible = showing_gains
	if showing_gains:
		refresh_gains()
	_scroll_to_end()


## The Gains list redrawn from gains_of (Gains.logged, while it shows).
func refresh_gains() -> void:
	if not showing_gains or not gains_of.is_valid():
		return
	for child in _gains_list.get_children():
		_gains_list.remove_child(child)
		child.queue_free()
	for line: Dictionary in gains_of.call():
		var label := RichTextLabel.new()
		label.fit_content = true
		label.scroll_active = false
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.tooltip_text = str(line.get("time", ""))
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.push_color(Gains.color_of(str(line.get("track", ""))))
		label.add_text(str(line.get("text", "")))
		label.pop()
		var words := str(line.get("words", ""))
		if not words.is_empty() and words != str(line.get("of", "")):
			label.push_color(ASIDE)
			label.add_text(ASIDE_DASH + words)
			label.pop()
		_gains_list.add_child(label)
	_scroll_to_end()


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
	_gains_button.visible = gains_of.is_valid() and (pinned or _hovering or showing_gains)
	# As tall as its lines, up to LIST_HEIGHT while pinned (then it scrolls).
	var shown_list := _gains_list if showing_gains else _list
	_scroll.custom_minimum_size.y = minf(shown_list.get_combined_minimum_size().y, LIST_HEIGHT)
	UiCost.add("talk", Time.get_ticks_usec() - began)


func _show_channel() -> void:
	if _box == null:
		return
	_channel.text = "party" if _box.text.begins_with("/p") else "say"


## Scrolls to the end on the next frame, once however often it is asked in one
## frame. A one-shot connection, not an await: a panel freed before that frame
## drops its connection, where a resumed await raised an engine error (economy_test,
## a hand-in's narrated thanks arriving as the test closed).
func _scroll_to_end() -> void:
	if not is_inside_tree() or get_tree().process_frame.is_connected(_scroll_now):
		return
	get_tree().process_frame.connect(_scroll_now, CONNECT_ONE_SHOT)


func _scroll_now() -> void:
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
