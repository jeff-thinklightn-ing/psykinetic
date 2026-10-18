class_name PausePanel
extends PanelContainer
## Esc with nothing else open: a small panel in the middle of the screen
## with Resume, Options, Leave and Quit, and a line saying the world goes
## on (a co-op world never pauses for one player). What each does is
## Main's, through the signals; Esc again resumes (Main). The look is the
## shared theme's (UiTheme, docs/ui_style.md).

signal resume_pressed
signal options_pressed
signal leave_pressed
signal quit_pressed

const WIDTH := 640.0

var resume: Button
var options: Button
var leave: Button
var quit: Button


func _init() -> void:
	name = "Pause"
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
	var title := Label.new()
	title.text = "Paused"
	title.theme_type_variation = &"Title"
	column.add_child(title)
	var note := Label.new()
	note.text = "The world goes on while you are away."
	note.theme_type_variation = &"Caption"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, UiTheme.constant("unit"))
	column.add_child(gap)
	resume = _button("Resume", resume_pressed)
	column.add_child(resume)
	options = _button("Options", options_pressed)
	column.add_child(options)
	leave = _button("Leave", leave_pressed)
	leave.tooltip_text = "Back to the menu"
	column.add_child(leave)
	quit = _button("Quit", quit_pressed)
	column.add_child(quit)


## Shown, with Resume focused; or hidden.
func open(shown: bool) -> void:
	visible = shown
	if shown:
		resume.grab_focus()


func _button(text: String, pressed_signal: Signal) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(func() -> void: pressed_signal.emit())
	return button
