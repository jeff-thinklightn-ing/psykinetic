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
## decision 385). Sizes in the HUD's 3840 x 2160 units; its look is the
## shared theme's (UiTheme, docs/ui_style.md): the title the Title
## variation, a section's name a Heading, a note a Caption.

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
	add_section("Video").add_child(_antialias_row())


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


## A label in the theme's body text; [param size] only when another size
## is wanted (the theme's sizes, UiTheme.size).
func _label(text: String, size: int = 0) -> Label:
	var label := Label.new()
	label.text = text
	if size > 0 and size != FONT_SIZE:
		label.add_theme_font_size_override("font_size", size)
	return label
