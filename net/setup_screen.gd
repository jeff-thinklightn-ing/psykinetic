class_name SetupScreen
extends CanvasLayer
## First-run screen for an exported client with no settings.cfg: asks for the
## server address and token once. Main writes the file and connects.

signal submitted(address: String, port: int, token: String, player_name: String)

var _address: LineEdit
var _port: LineEdit
var _token: LineEdit
var _name: LineEdit
var _error: Label


func _ready() -> void:
	layer = 20
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.05, 0.08, 0.92)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(420, 0)
	panel.position = Vector2(-210, -120)
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var title := Label.new()
	title.text = "Join a Psykinetic server"
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)

	var hint := Label.new()
	hint.text = "Ask whoever runs the server for these. You only do this once."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	column.add_child(hint)

	_address = _field(column, "Server address", "e.g. 100.64.0.5")
	_port = _field(column, "Port", str(Net.DEFAULT_PORT))
	_port.text = str(Net.DEFAULT_PORT)
	_token = _field(column, "Token", "")
	_token.secret = true
	_name = _field(column, "Your name", "Player")
	_name.text = "Player"

	_error = Label.new()
	_error.modulate = Color(1.0, 0.5, 0.5)
	column.add_child(_error)

	var button := Button.new()
	button.text = "Connect"
	button.pressed.connect(_submit)
	column.add_child(button)

	_address.grab_focus()
	for field in [_address, _port, _token, _name]:
		field.text_submitted.connect(func(_text: String) -> void: _submit())


func _field(parent: Control, label_text: String, placeholder: String) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	parent.add_child(edit)
	return edit


func _submit() -> void:
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
	queue_free()
