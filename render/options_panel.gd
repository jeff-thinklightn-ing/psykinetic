class_name OptionsPanel
extends PanelContainer
## The game's options, O shows and hides it (Main). One panel with a titled
## section per kind of option: add one with add_section(title) and put
## controls in the box it returns, rather than giving each its own key.
## Sound is the first: a slider (0 to 100%) per volume, applied as it moves
## (Net.set_volume) and written to settings.cfg when let go or when the
## panel is hidden. Character: the body the player wears (decision 388),
## written at once and sent with the next join (a character creation flow
## will replace it). Video: the 3D view's anti-aliasing, a button per kind
## (Net.ANTIALIAS), applied and written at a click (Net.set_antialias,
## decision 385), the window (fullscreen or windowed, Net.set_fullscreen)
## and the windowed resolution (Net.set_window_size). Controls: the scheme
## (click to move or WASD, Net.set_controls) and whether the controls list
## shows (H; Net.set_hints, hints_changed for Main). Sizes in the HUD's
## 3840 x 2160 units; its look is the shared theme's (UiTheme,
## docs/ui_style.md): the title the Title variation, a section's name a
## Heading, a note a Caption.

## The controls list turned on or off here (Main shows or hides it).
signal hints_changed(shown: bool)

## The theme's body size, for a label of another size's sake (_label).
static var FONT_SIZE: int = UiTheme.size("body")
const WIDTH := 760.0
const SLIDER_WIDTH := 420.0
## The sound section's sliders: [Net's setting, the label].
const VOLUMES := [["master_volume", "Master"], ["sfx_volume", "Effects"], ["voice_volume", "Voices"],
	["ambience_volume", "Ambience"], ["ui_volume", "Interface"]]

var _column: VBoxContainer
## Character's body: Net.BODIES' labels, in their order.
const BODY_LABELS := ["Male", "Female"]
## Net's setting -> its slider.
var sliders: Dictionary[String, HSlider] = {}
## The Video section's buttons: Net.ANTIALIAS's value -> its button.
const ANTIALIAS_NAMES := {"off": "Off", "fxaa": "FXAA", "smaa": "SMAA", "msaa4": "MSAA 4x"}
var antialias_buttons: Dictionary[String, Button] = {}
## The windowed sizes offered; the window's own size is added when it is none of them.
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3440, 1440), Vector2i(3840, 2160)]
## A choice row's buttons by its setting ("window", "controls", "hints"): value -> button.
var choices: Dictionary[String, Dictionary] = {}
## The Resolution drop-down.
var resolution: OptionButton
## A slider moved since the settings were last written.
var _unsaved := false
## Which body the player wears (Net.player_body).
var body_choice: OptionButton


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	position = Vector2((3840.0 - WIDTH) * 0.5, 180)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", UiTheme.constant("row"))
	add_child(_column)
	var title := Label.new()
	title.text = "Options"
	title.theme_type_variation = &"Title"
	_column.add_child(title)
	# Who you are first: what a new player sets before anything else.
	var character := add_section("Character")
	character.add_child(_body_row())
	var sound := add_section("Sound")
	for volume: Array in VOLUMES:
		sound.add_child(_slider_row(volume[0], volume[1]))
	var video := add_section("Video")
	video.add_child(_antialias_row())
	video.add_child(_choice_row("Window", "window", [["windowed", "Windowed"], ["fullscreen", "Fullscreen"]],
		func() -> String: return "fullscreen" if Net.fullscreen else "windowed",
		func(value: String) -> void: Net.set_fullscreen(value == "fullscreen")))
	video.add_child(_resolution_row())
	var controls := add_section("Controls")
	controls.add_child(_choice_row("Move", "controls", [["click", "Click to move"], ["wasd", "WASD and aim"]],
		func() -> String: return Net.controls, Net.set_controls))
	controls.add_child(_choice_row("Controls list", "hints", [["on", "Shown"], ["off", "Hidden"]],
		func() -> String: return "on" if Net.hints else "off",
		func(value: String) -> void:
			Net.set_hints(value == "on")
			hints_changed.emit(value == "on")))


## A titled section, its controls to be added to the box returned.
func add_section(title: String) -> VBoxContainer:
	var heading := Label.new()
	heading.text = title
	heading.theme_type_variation = &"Heading"
	_column.add_child(heading)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiTheme.constant("unit"))
	_column.add_child(box)
	return box


## Shown or hidden; hiding writes the volumes if a slider moved.
func toggle() -> void:
	visible = not visible
	if visible:
		for key: String in sliders:
			sliders[key].set_value_no_signal(float(Net.get(key)))
		body_choice.select(Net.BODIES.find(Net.player_body))
		for value: String in antialias_buttons:
			antialias_buttons[value].set_pressed_no_signal(value == Net.antialias)
		for key: String in choices:
			var current: String = choices[key]["current"].call()
			for value: String in choices[key]["buttons"]:
				(choices[key]["buttons"][value] as Button).set_pressed_no_signal(value == current)
		_show_resolution()
	elif _unsaved:
		_unsaved = false
		Net.save_view_settings()


func _slider_row(key: String, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var name := _label(text, FONT_SIZE)
	name.custom_minimum_size = Vector2(200, 0)
	row.add_child(name)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(Net.get(key))
	slider.custom_minimum_size = Vector2(SLIDER_WIDTH, 40)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	row.add_child(slider)
	var percent := _label("%d%%" % roundi(slider.value * 100.0), FONT_SIZE)
	row.add_child(percent)
	slider.value_changed.connect(func(value: float) -> void:
		percent.text = "%d%%" % roundi(value * 100.0)
		Net.set_volume(key, value, false)
		_unsaved = true)
	slider.drag_ended.connect(func(changed: bool) -> void:
		if changed:
			_unsaved = false
			Net.save_view_settings())
	sliders[key] = slider
	return row


## Body: a choice of Net.BODIES, saved when picked; it shows from the next join.
func _body_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var name := _label("Body", FONT_SIZE)
	name.custom_minimum_size = Vector2(200, 0)
	row.add_child(name)
	body_choice = OptionButton.new()
	for text: String in BODY_LABELS:
		body_choice.add_item(text)
	body_choice.select(Net.BODIES.find(Net.player_body))
	body_choice.focus_mode = Control.FOCUS_NONE
	row.add_child(body_choice)
	var note := Label.new()
	note.text = "from your next join"
	note.theme_type_variation = &"Caption"
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(note)
	body_choice.item_selected.connect(func(index: int) -> void:
		Net.player_body = Net.BODIES[index]
		Net.save_view_settings())
	return row


## Anti-aliasing: a button per Net.ANTIALIAS, applied and saved at a click.
func _antialias_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var name := _label("Anti-aliasing", FONT_SIZE)
	name.custom_minimum_size = Vector2(200, 0)
	row.add_child(name)
	var group := ButtonGroup.new()
	for value: String in Net.ANTIALIAS:
		var button := Button.new()
		button.text = ANTIALIAS_NAMES.get(value, value)
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = value == Net.antialias
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: Net.set_antialias(value))
		row.add_child(button)
		antialias_buttons[value] = button
	return row


## A row of toggle buttons for setting [param key]: [param options] are
## [value, label] pairs, [param current] says which is on, [param pick] is
## called with the value chosen (applied and saved by Net).
func _choice_row(text: String, key: String, options: Array, current: Callable, pick: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var name := _label(text, FONT_SIZE)
	name.custom_minimum_size = Vector2(200, 0)
	row.add_child(name)
	var group := ButtonGroup.new()
	var buttons: Dictionary[String, Button] = {}
	var now: String = current.call()
	for option: Array in options:
		var value: String = option[0]
		var button := Button.new()
		button.text = option[1]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = value == now
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: pick.call(value))
		row.add_child(button)
		buttons[value] = button
	choices[key] = {"current": current, "buttons": buttons}
	return row


## Resolution: the windowed size, a drop-down of RESOLUTIONS (and the
## window's own size when it is none of them), applied and saved at a pick.
func _resolution_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var name := _label("Resolution", FONT_SIZE)
	name.custom_minimum_size = Vector2(200, 0)
	row.add_child(name)
	resolution = OptionButton.new()
	resolution.focus_mode = Control.FOCUS_NONE
	_show_resolution()
	resolution.item_selected.connect(func(index: int) -> void:
		Net.set_window_size(resolution.get_item_metadata(index)))
	row.add_child(resolution)
	var note := _label("windowed", 0)
	note.theme_type_variation = &"Caption"
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(note)
	return row


func _show_resolution() -> void:
	resolution.clear()
	var sizes: Array[Vector2i] = RESOLUTIONS.duplicate()
	if Net.window_size not in sizes:
		sizes.append(Net.window_size)
		sizes.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * a.y < b.x * b.y)
	for size: Vector2i in sizes:
		resolution.add_item("%d x %d" % [size.x, size.y])
		resolution.set_item_metadata(resolution.item_count - 1, size)
	resolution.select(sizes.find(Net.window_size))


## A label in the theme's body text; [param size] only when another size
## is wanted (the theme's sizes, UiTheme.size).
func _label(text: String, size: int = 0) -> Label:
	var label := Label.new()
	label.text = text
	if size > 0 and size != FONT_SIZE:
		label.add_theme_font_size_override("font_size", size)
	return label
