class_name GameMenu
extends PanelContainer
## Esc with nothing else open: the game's menu in the middle of the screen,
## titled with the zone's name, with Close, Options, Leave and Quit and a
## plain line that the world goes on while it is open. The game never
## pauses (Jeff, 2026-10-17: "there's no pause for the game"; a co-op world
## goes on), so nothing here says pause. What each does is Main's, through
## the signals; Esc again closes it (Main). The look is the shared theme's
## (UiTheme, docs/ui_style.md).

signal close_pressed
signal options_pressed
signal leave_pressed
signal quit_pressed

const WIDTH := 640.0

var close: Button
var options: Button
var leave: Button
var quit: Button
var _title: Label


func _init() -> void:
	name = "GameMenu"
	visible = false


func _ready() -> void:
	# In the middle of the screen: the width fixed, the height grown both ways.
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiTheme.constant("row"))
	add_child(column)
	_title = Label.new()
	_title.text = "Menu"
	_title.theme_type_variation = &"Title"
	column.add_child(_title)
	var note := Label.new()
	note.text = "The world goes on while this is open."
	note.theme_type_variation = &"Caption"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, UiTheme.constant("unit"))
	column.add_child(gap)
	close = _button("Close", close_pressed)
	column.add_child(close)
	options = _button("Options", options_pressed)
	column.add_child(options)
	leave = _button("Leave", leave_pressed)
	leave.tooltip_text = "Back to the main menu"
	column.add_child(leave)
	quit = _button("Quit", quit_pressed)
	column.add_child(quit)


## Shown, titled with [param place] (the zone's name; "Menu" for none),
## Close focused; or hidden.
func open(shown: bool, place := "") -> void:
	visible = shown
	if shown:
		_title.text = place if not place.is_empty() else "Menu"
		close.grab_focus()


func title_shown() -> String:
	return _title.text


func _button(text: String, pressed_signal: Signal) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(func() -> void: pressed_signal.emit())
	return button
