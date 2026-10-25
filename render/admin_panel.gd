class_name AdminPanel
extends PanelContainer
## The in-game admin panel (decision 672; Jeff: "i need a admin command
## list in game that i can reset quests, spawn in different zones, etc."):
## F10 opens it for an admin only (Main.admin_allowed: the server's
## PSYKINETIC_ADMIN_IDS said so in the "admin" message, or this is the
## host). It runs the server console's own commands (Main.admin_command,
## the dispatcher stdin and the admin port use) through the "admin"
## command and shows each "admin_reply". The help lines (the "help"
## command's, one a command) with a filter, a typed line with history
## (Up/Down, the last HISTORY), the replies, and buttons for the common
## ones: go to a zone, reset quests (all or one quest giver here), reset
## this room, regenerate this level, the hour and the weather. A
## destructive button asks once: press it again within CONFIRM_MSEC. Esc
## closes it. The server checks every command; the panel only asks. The
## look is the shared theme's (UiTheme, docs/ui_style.md).

## A line to run on the server (Main.send_admin).
signal ran(line: String)

const WIDTH := 760.0
const HEIGHT := 560.0
const HISTORY := 30
const CONFIRM_MSEC := 3000
## The hours the time buttons set.
const HOURS: Array = [["Dawn", 6], ["Noon", 12], ["Dusk", 18], ["Night", 0]]

var _help: ItemList
var _filter: LineEdit
var _replies: RichTextLabel
var _line: LineEdit
var _zones: OptionButton
var _givers: OptionButton
var _weather: OptionButton
var _reset_room: Button
var _regenerate: Button
## The help lines as last heard, the typed lines (oldest first), and where
## Up/Down is in them (-1: at the new line).
var help_lines: Array[String] = []
var history: Array[String] = []
var _back := -1
## A destructive button pressed once: which, and when (msec).
var _armed: Button = null
var _armed_at := 0
## The zone the player is in and its quest givers' names, for the buttons.
var zone := ""
var givers: Array[String] = []


func _init() -> void:
	name = "AdminPanel"
	visible = false
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 40


func _ready() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiTheme.constant("row"))
	add_child(column)
	var title := Label.new()
	title.theme_type_variation = &"Heading"
	title.text = "Admin"
	column.add_child(title)
	# The common ones.
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", UiTheme.constant("row"))
	buttons.add_theme_constant_override("v_separation", UiTheme.constant("row"))
	column.add_child(buttons)
	_zones = OptionButton.new()
	_zones.focus_mode = Control.FOCUS_NONE
	buttons.add_child(_zones)
	buttons.add_child(_button("Go", _go))
	_givers = OptionButton.new()
	_givers.focus_mode = Control.FOCUS_NONE
	buttons.add_child(_givers)
	buttons.add_child(_button("Reset quests", _reset_quests))
	_reset_room = _button("Reset this room", _reset_this_room)
	buttons.add_child(_reset_room)
	_regenerate = _button("Regenerate this level", _regenerate_this)
	buttons.add_child(_regenerate)
	for hour: Array in HOURS:
		buttons.add_child(_button(str(hour[0]), run.bind("hour %d" % int(hour[1]))))
	_weather = OptionButton.new()
	_weather.focus_mode = Control.FOCUS_NONE
	_weather.add_item("auto")
	for kind: String in Weather.KINDS.keys():
		_weather.add_item(kind)
	buttons.add_child(_weather)
	buttons.add_child(_button("Weather", _set_weather))
	# The commands, the replies, the line.
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", UiTheme.constant("row"))
	column.add_child(split)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.45
	split.add_child(left)
	_filter = LineEdit.new()
	_filter.placeholder_text = "Filter the commands"
	_filter.text_changed.connect(func(_text: String) -> void: _show_help())
	left.add_child(_filter)
	_help = ItemList.new()
	_help.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_help.item_activated.connect(_help_picked)
	_help.item_selected.connect(_help_picked)
	left.add_child(_help)
	_replies = RichTextLabel.new()
	_replies.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_replies.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_replies.scroll_following = true
	_replies.selection_enabled = true
	split.add_child(_replies)
	_line = LineEdit.new()
	_line.placeholder_text = "A command (Enter runs it; Up and Down for the last ones; Esc closes)"
	_line.text_submitted.connect(_submitted)
	_line.gui_input.connect(_line_input)
	column.add_child(_line)
	var caption := Label.new()
	caption.theme_type_variation = &"Caption"
	caption.add_theme_color_override("font_color", UiTheme.color("text_dim"))
	caption.text = "Runs on the server as its console does. Reset and regenerate ask twice."
	column.add_child(caption)


func _button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(pressed)
	return button


## Opens (asking the server for its help lines the first time) or closes.
func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	visible = true
	_fill_zones()
	_fill_givers()
	if help_lines.is_empty():
		ran.emit("help")
	_line.grab_focus()


func close() -> void:
	visible = false
	_armed = null
	if _line.has_focus():
		_line.release_focus()


## Whether its line has the keys (Main.is_typing: no walking meanwhile).
func is_typing() -> bool:
	return visible and _line != null and _line.has_focus()


## Runs [param line] (shown, kept in the history).
func run(line: String) -> void:
	var said := line.strip_edges()
	if said.is_empty():
		return
	if history.is_empty() or history.back() != said:
		history.append(said)
		if history.size() > HISTORY:
			history.pop_front()
	_back = -1
	_replies.append_text("[color=#%s]> %s[/color]\n" % [UiTheme.color("text_dim").to_html(false), _escaped(said)])
	ran.emit(said)


## The server's answer {line, text}: shown; "help"'s fills the list.
func on_reply(data: Dictionary) -> void:
	var line := str(data.get("line", ""))
	var text := str(data.get("text", ""))
	if line.strip_edges() == "help":
		help_lines = help_from(text)
		_show_help()
		if not visible:
			return
	_replies.append_text("%s\n" % _escaped(text))


## The "help" reply as its lines, one a command; blank lines dropped.
static func help_from(text: String) -> Array[String]:
	var out: Array[String] = []
	for each: String in text.split("\n"):
		if not each.strip_edges().is_empty():
			out.append(each.strip_edges())
	return out


func _show_help() -> void:
	if _help == null:
		return
	_help.clear()
	var wanted := _filter.text.strip_edges().to_lower()
	for each: String in help_lines:
		if wanted.is_empty() or each.to_lower().contains(wanted):
			_help.add_item(each)


## A help line picked: its command, up to the first ":", in the line to fill in.
func _help_picked(index: int) -> void:
	var picked := _help.get_item_text(index)
	var colon := picked.find(":")
	_line.text = (picked.substr(0, colon) if colon > 0 else picked).strip_edges() + " "
	_line.grab_focus()
	_line.caret_column = _line.text.length()


func _submitted(text: String) -> void:
	run(text)
	_line.text = ""


## Up and Down walk the history; Esc closes.
func _line_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode == KEY_ESCAPE:
		close()
		accept_event()
	elif key.keycode == KEY_UP and not history.is_empty():
		_back = history.size() - 1 if _back < 0 else maxi(_back - 1, 0)
		_line.text = history[_back]
		_line.caret_column = _line.text.length()
		accept_event()
	elif key.keycode == KEY_DOWN and _back >= 0:
		_back += 1
		_line.text = history[_back] if _back < history.size() else ""
		if _back >= history.size():
			_back = -1
		_line.caret_column = _line.text.length()
		accept_event()


## [param button] pressed: true the second time within CONFIRM_MSEC (and
## its words back), else armed with "again to confirm".
func confirmed(button: Button, words: String) -> bool:
	var now := Time.get_ticks_msec()
	if _armed == button and now - _armed_at <= CONFIRM_MSEC:
		_armed = null
		button.text = words
		return true
	if _armed != null and _armed != button:
		_armed.text = _armed.get_meta("words", _armed.text)
	_armed = button
	_armed_at = now
	button.set_meta("words", words)
	button.text = "%s: again to confirm" % words
	return false


func _process(_delta: float) -> void:
	if _armed != null and Time.get_ticks_msec() - _armed_at > CONFIRM_MSEC:
		_armed.text = _armed.get_meta("words", _armed.text)
		_armed = null


func _fill_zones() -> void:
	_zones.clear()
	for each: String in Level.names():
		var shown := str(Level.load_level(each).get("display_name", "")).strip_edges()
		_zones.add_item("%s (%s)" % [shown, each] if not shown.is_empty() and shown != each else each)
		_zones.set_item_metadata(_zones.item_count - 1, each)
		if each == zone:
			_zones.select(_zones.item_count - 1)


func _fill_givers() -> void:
	_givers.clear()
	_givers.add_item("all")
	for each: String in givers:
		_givers.add_item(each)


func _go() -> void:
	if _zones.selected >= 0:
		run("go %s" % str(_zones.get_item_metadata(_zones.selected)))


func _reset_quests() -> void:
	var giver := _givers.get_item_text(_givers.selected) if _givers.selected >= 0 else "all"
	run("quests reset %s" % giver)


func _reset_this_room() -> void:
	if not zone.is_empty() and confirmed(_reset_room, "Reset this room"):
		run("zone reset %s" % zone)


func _regenerate_this() -> void:
	if not zone.is_empty() and confirmed(_regenerate, "Regenerate this level"):
		run("regenerate now %s" % zone)


func _set_weather() -> void:
	run("weather %s" % _weather.get_item_text(maxi(_weather.selected, 0)))


static func _escaped(text: String) -> String:
	return text.replace("[", "[lb]")
