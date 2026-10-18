class_name MainMenu
extends CanvasLayer
## The main menu, over everything when an exported client starts (Main
## shows it before going online; --menu forces it, for screenshots): the
## game's name in the serif, Play, Options and Quit, the version in a
## corner. What each does is Main's, through the signals; the look is the
## shared theme's (UiTheme, docs/ui_style.md). Sizes in the HUD's 3840 x
## 2160 units.

signal play_pressed
signal options_pressed
signal quit_pressed

const BUTTON_WIDTH := 560.0

var play: Button
var options: Button
var quit: Button
var version: Label
## The server's status under the buttons (Main, from Net.query_status; maps').
var status: Label


func _init() -> void:
	name = "MainMenu"
	layer = 20


func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(UiTheme.color("outline"), 0.97)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", UiTheme.constant("row"))
	add_child(column)
	var title := Label.new()
	title.text = "Psykinetic"
	title.theme_type_variation = &"Display"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, UiTheme.constant("section") * 2)
	column.add_child(gap)
	play = _button("Play", play_pressed)
	column.add_child(play)
	options = _button("Options", options_pressed)
	column.add_child(options)
	quit = _button("Quit", quit_pressed)
	column.add_child(quit)
	status = Label.new()
	status.theme_type_variation = &"Caption"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.visible = false
	column.add_child(status)
	version = Label.new()
	version.text = "v%s" % Net.version
	version.theme_type_variation = &"Caption"
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.offset_right = -UiTheme.constant("margin")
	version.offset_bottom = -UiTheme.constant("margin")
	add_child(version)
	play.grab_focus()


## "online, v0.1.150, 3 players" under the buttons; "" for none.
func set_status(text: String) -> void:
	status.text = text
	status.visible = not text.is_empty()


func _button(text: String, pressed_signal: Signal) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(BUTTON_WIDTH, 0)
	button.pressed.connect(func() -> void: pressed_signal.emit())
	return button
