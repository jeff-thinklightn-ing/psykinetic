class_name ConnectScreen
extends CanvasLayer
## The join flow in one place, over the game: what the connection is doing
## in plain words ("connecting to 100.64.0.5:7777", "the server is
## restarting; trying again (3)") with dots that move while it works; a
## failure stays on it with Retry and Change server; and the server's
## details (address, port, token, your name) to fill in the first run and
## on Change server. Main drives it: set_state, and the signals for what
## the buttons ask; the causes are Net's and the join and update path is
## maps' (decision 241). Replaces the first-run SetupScreen. The look is
## the shared theme's (UiTheme, docs/ui_style.md).

## The fields filled in and Connect pressed.
signal submitted(address: String, port: int, token: String, player_name: String)
## Retry pressed after a failure.
signal retry_pressed
## Back pressed: to the menu.
signal back_pressed
## Cancel pressed while an update's progress runs (maps' in-game update).
signal cancel_pressed

const WIDTH := 1300.0
const DOTS_EVERY := 0.4

## Filling in the server's details (the first run, Change server).
var editing := false
## The last state was a failure: Retry and Change server are offered.
var failed := false
## Whether Back (to the menu) is offered: there is a menu to go back to.
var has_menu := false

var _status: Label
var _dots: Label
var _progress: ProgressBar
var _server: Label
var _fields: VBoxContainer
var _address: LineEdit
var _port: LineEdit
var _token: LineEdit
var _name: LineEdit
var _error: Label
var _buttons: HBoxContainer
var _connect: Button
var _retry: Button
var _change: Button
var _back: Button
var _cancel: Button
var _since := 0.0
## An update's progress is running (set_progress): Cancel is offered.
var progressing := false


func _init() -> void:
	name = "ConnectScreen"
	layer = 20


func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(UiTheme.color("outline"), 0.92)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(WIDTH, 0)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiTheme.constant("section"))
	panel.add_child(column)
	var title := Label.new()
	title.text = "Join a Psykinetic server"
	title.theme_type_variation = &"Title"
	column.add_child(title)
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 0)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(_status)
	_dots = Label.new()
	_dots.custom_minimum_size = Vector2(60, 0)
	status_row.add_child(_dots)
	column.add_child(status_row)
	_progress = ProgressBar.new()
	_progress.min_value = 0.0
	_progress.max_value = 1.0
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 24)
	_progress.visible = false
	column.add_child(_progress)
	_server = Label.new()
	_server.theme_type_variation = &"Caption"
	_server.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_server.visible = false
	column.add_child(_server)
	_fields = VBoxContainer.new()
	_fields.add_theme_constant_override("separation", UiTheme.constant("row"))
	column.add_child(_fields)
	var hint := Label.new()
	hint.text = "Ask whoever runs the server for these. They are remembered."
	hint.theme_type_variation = &"Caption"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_fields.add_child(hint)
	_address = _field("Server address", "e.g. 100.64.0.5")
	_port = _field("Port", str(Net.DEFAULT_PORT))
	_token = _field("Token", "")
	_token.secret = true
	_name = _field("Your name", "Player")
	_error = Label.new()
	_error.add_theme_color_override("font_color", UiTheme.color("rust"))
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fields.add_child(_error)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", UiTheme.constant("row"))
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(_buttons)
	_back = _button("Back", func() -> void: back_pressed.emit())
	_cancel = _button("Cancel", func() -> void: cancel_pressed.emit())
	_change = _button("Change server", edit)
	_retry = _button("Retry", func() -> void: retry_pressed.emit())
	_connect = _button("Connect", _submit)
	for field in [_address, _port, _token, _name]:
		field.text_submitted.connect(func(_text: String) -> void: _submit())
	_show_parts()


## The details to fill in, with what is known already.
func edit() -> void:
	editing = true
	failed = false
	_address.text = Net.address if Net.address != "127.0.0.1" else ""
	_port.text = str(Net.port)
	_token.text = Net.token
	_name.text = Net.player_name
	_error.text = ""
	_status.text = ""
	_show_parts()
	visible = true
	_address.grab_focus()


## What the connection is doing, in words; [param is_failed] offers Retry
## and Change server and stops the dots.
func set_state(text: String, is_failed := false) -> void:
	editing = false
	failed = is_failed
	progressing = false
	_progress.visible = false
	_status.text = text
	_since = 0.0
	_show_parts()
	visible = true


## An update's progress (maps' in-game update, 430): [param fraction] 0..1
## fills the bar, -1 (not known yet) keeps the dots alone; [param text] says
## what is happening ("downloading v0.1.150: 34 of 112 MB"). Cancel is
## offered. -1 with no words: the progress is over (the bar and Cancel go;
## the state stays as the last set_state left it).
func set_progress(fraction: float, text: String) -> void:
	if fraction < 0.0 and text.is_empty():
		progressing = false
		_progress.visible = false
		_show_parts()
		return
	editing = false
	failed = false
	progressing = true
	_status.text = text
	_progress.visible = fraction >= 0.0
	_progress.value = clampf(fraction, 0.0, 1.0)
	_show_parts()
	visible = true


## The server's status under the fields ("online, v0.1.150, 3 players"),
## from Net.query_status's answer (maps'); "" for none.
func set_status(text: String) -> void:
	_server.text = text
	_server.visible = not text.is_empty()


func status_shown() -> String:
	return _server.text


## The bar's fraction while progressing, -1 when the bar is hidden (tests).
func progress_shown() -> float:
	return _progress.value if _progress.visible else -1.0


## The state shown ("" while editing) and whether it is a failure (tests).
func state_shown() -> String:
	return _status.text


## The buttons offered, in order (tests).
func buttons_shown() -> Array[String]:
	var out: Array[String] = []
	for button: Button in _buttons.get_children():
		if button.visible:
			out.append(button.text)
	return out


func _process(delta: float) -> void:
	if editing or failed or _progress.visible:
		_dots.text = ""
		return
	_since += delta
	_dots.text = ".".repeat(1 + int(_since / DOTS_EVERY) % 3)


func _show_parts() -> void:
	_fields.visible = editing
	_status.get_parent().visible = not editing
	_connect.visible = editing
	_retry.visible = failed
	_change.visible = failed
	_cancel.visible = progressing
	_back.visible = has_menu and (editing or failed)


func _field(label_text: String, placeholder: String) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	label.theme_type_variation = &"Caption"
	_fields.add_child(label)
	var edit_box := LineEdit.new()
	edit_box.placeholder_text = placeholder
	_fields.add_child(edit_box)
	return edit_box


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(300, 0)
	button.pressed.connect(on_pressed)
	_buttons.add_child(button)
	return button


func _submit() -> void:
	if not editing:
		return
	var address := _address.text.strip_edges()
	var token := _token.text.strip_edges()
	var port_text := _port.text.strip_edges()
	if address.is_empty():
		_error.text = "The address is needed."
		return
	if not port_text.is_valid_int() or port_text.to_int() <= 0 or port_text.to_int() > 65535:
		_error.text = "The port must be a number between 1 and 65535."
		return
	if token.is_empty():
		_error.text = "The token is needed."
		return
	var player_name := _name.text.strip_edges()
	if player_name.is_empty():
		player_name = "Player"
	submitted.emit(address, port_text.to_int(), token, player_name)
