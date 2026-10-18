class_name OptionsPanel
extends PanelContainer
## The game's options, O shows and hides it (Main). One panel with a titled
## section per kind of option: add one with add_section(title) and put
## controls in the box it returns, rather than giving each its own key.
## Sound is the first: a slider (0 to 100%) per volume, applied as it moves
## (Net.set_volume) and written to settings.cfg when let go or when the
## panel is hidden. Character (decisions 388, 419, 439): the body the player
## wears and their look (build, height, hair and its colour, beard, skin;
## a "Surprise me" for a new seed and the rest left to it), beside a live
## preview of them (CharacterPreview); written at once (Net.player_body,
## Net.player_look) and sent with the next join. Video: the 3D view's anti-aliasing, a button per kind
## (Net.ANTIALIAS), applied and written at a click (Net.set_antialias,
## decision 385), the window (fullscreen or windowed, Net.set_fullscreen)
## and the windowed resolution (Net.set_window_size). Controls: the scheme
## (click to move or WASD, Net.set_controls) and whether the controls list
## shows (H; Net.set_hints, hints_changed for Main). Credits: who made the
## sounds (credit_providers, decision 406), a line each and a button for the
## full list with each maker's page. Sizes in the HUD's
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
var _scroll: ScrollContainer
## The Character section's rows, beside its preview: [the look's key, its
## label, its choices as [value, label]] (PersonLook.PLAYER_CHOICES' values).
const LOOK_ROWS := [
	["build", "Build", [["lean", "Lean"], ["middling", "Middling"], ["heavy", "Heavy"]]],
	["stature", "Height", [["short", "Short"], ["middling", "Middling"], ["tall", "Tall"]]],
	["hair", "Hair", [["cropped", "Cropped"], ["bound", "Bound"], ["long", "Long"], ["bald", "Bald"]]],
	["beard", "Beard", [["none", "None"], ["short", "Short"], ["full", "Full"]]],
]
## A swatch's size (ui: big enough to hit at 1080p).
const SWATCH := Vector2(56, 56)
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
## The Character section's preview, its swatch rows (the look's key ->
## value -> button) and the beard's row (a man's only).
var preview: CharacterPreview
var swatches: Dictionary[String, Dictionary] = {}
var beard_row: Control


func _ready() -> void:
	# Centred at the top whatever its width (a wide section grows it both ways).
	custom_minimum_size = Vector2(WIDTH, 0)
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	offset_top = 180
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	# The column in a scroll box capped at the screen's height (the wheel scrolls
	# it); no inset look inside the panel.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(_scroll)
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", UiTheme.constant("row"))
	_scroll.add_child(_column)
	var title := Label.new()
	title.text = "Options"
	title.theme_type_variation = &"Title"
	_column.add_child(title)
	# Who you are first: what a new player sets before anything else.
	var character := add_section("Character")
	character.add_child(_character_block())
	var sound := add_section("Sound")
	for volume: Array in VOLUMES:
		sound.add_child(_slider_row(volume[0], volume[1]))
	var video := add_section("Video")
	video.add_child(_antialias_row())
	video.add_child(_choice_row("Window", "window", [["windowed", "Windowed"], ["fullscreen", "Fullscreen"]],
		func() -> String: return "fullscreen" if Net.fullscreen else "windowed",
		func(value: String) -> void: Net.set_fullscreen(value == "fullscreen")))
	video.add_child(_resolution_row())
	video.add_child(_choice_row("Interface size", "ui_scale",
		[["0.80", "Smaller"], ["1.00", "Normal"], ["1.25", "Larger"], ["1.50", "Largest"]],
		func() -> String: return "%.2f" % Net.ui_scale, func(value: String) -> void: Net.set_ui_scale(value.to_float())))
	video.add_child(_choice_row("Text size", "text_scale", [["1.00", "Normal"], ["1.25", "Larger"], ["1.50", "Largest"]],
		func() -> String: return "%.2f" % Net.text_scale, func(value: String) -> void: Net.set_text_scale(value.to_float())))
	var colours := _choice_row("Colours", "colours", [["normal", "Normal"], ["distinct", "Distinct"]],
		func() -> String: return Net.colours, Net.set_colours)
	var note := Label.new()
	note.text = "in full from your next start"
	note.theme_type_variation = &"Caption"
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	colours.add_child(note)
	video.add_child(colours)
	var controls := add_section("Controls")
	controls.add_child(_choice_row("Move", "controls", [["click", "Click to move"], ["wasd", "WASD and aim"]],
		func() -> String: return Net.controls, Net.set_controls))
	controls.add_child(_choice_row("Controls list", "hints", [["on", "Shown"], ["off", "Hidden"]],
		func() -> String: return "on" if Net.hints else "off",
		func(value: String) -> void:
			Net.set_hints(value == "on")
			hints_changed.emit(value == "on")))
	# Filled when first shown: the server builds this panel too, and has no
	# art/audio to credit (2f0db21).
	_credits = add_section("Credits")


## Who made what the game uses (decision 406): a Callable each giving
## {summary, entries: [{title, by, license, url}]}; sound's now, art's, the
## fonts' and the animations' can join here. THIRD_PARTY.md (in the zip)
## has everything.
static func credit_providers() -> Array[Callable]:
	return [SoundKit.credits, ArtKit.credits, UiTheme.credits]


## The Credits section's full list (a plain ScrollContainer, which the
## theme insets, decision 401), shown by its button.
var credits_box: ScrollContainer
var credits_list: VBoxContainer
var credits_button: Button
## The Credits section's box, empty till the panel is first shown.
var _credits: VBoxContainer


## The column shown whole where it fits, else as tall as the screen allows.
func _process(_delta: float) -> void:
	if not visible or _scroll == null:
		return
	var room := get_viewport_rect().size.y - offset_top - UiTheme.constant("margin") - 2 * UiTheme.constant("pad")
	_scroll.custom_minimum_size.y = minf(_column.get_combined_minimum_size().y, maxf(room, 200.0))


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
		_fill_credits()
		for key: String in sliders:
			sliders[key].set_value_no_signal(float(Net.get(key)))
		_show_look()
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


## Character: the choices on the left (the body, then LOOK_ROWS, the hair's
## and skin's colours as swatches, "Surprise me"), the preview on the right.
func _character_block() -> HBoxContainer:
	var block := HBoxContainer.new()
	block.add_theme_constant_override("separation", UiTheme.constant("row"))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", UiTheme.constant("unit"))
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_child(rows)
	rows.add_child(_choice_row("Body", "body", [["male", "Man"], ["female", "Woman"]],
		func() -> String: return String(Net.player_body),
		func(value: String) -> void:
			Net.player_body = StringName(value)
			if value == "female":
				_set_look_word("beard", "")  # Hers are none unless chosen again as a man.
			Net.save_view_settings()
			_show_look()))
	for row: Array in LOOK_ROWS:
		var key: String = row[0]
		var line := _choice_row(row[1], "look_" + key, row[2],
			func() -> String: return str(_look().get(key)),
			func(value: String) -> void: _pick_look(key, value))
		rows.add_child(line)
		if key == "beard":
			beard_row = line
	var hair_colours: Array = []
	for name: String in PersonLook.HAIR_COLOURS:
		hair_colours.append([name, Color(PersonLook.HAIR_COLOURS[name])])
	rows.add_child(_swatch_row("Hair colour", "hair_colour", hair_colours))
	var skins: Array = []
	for i in PersonLook.SKINS.size():
		skins.append([str(i + 1), Color(PersonLook.SKINS[i])])
	rows.add_child(_swatch_row("Skin", "skin", skins))
	var last := HBoxContainer.new()
	last.add_theme_constant_override("separation", 16)
	var surprise := Button.new()
	surprise.text = "Surprise me"
	surprise.focus_mode = Control.FOCUS_NONE
	surprise.pressed.connect(func() -> void:
		Net.player_look = "seed=%d" % randi_range(1, 2147483646)
		Net.save_view_settings()
		_show_look())
	last.add_child(surprise)
	var note := Label.new()
	note.text = "from your next join"
	note.theme_type_variation = &"Caption"
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	last.add_child(note)
	rows.add_child(last)
	preview = CharacterPreview.new()
	preview.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	block.add_child(preview)
	_show_look.call_deferred()
	return block


## A row of colour swatches for the look's [param key]: [param options] are
## [value, colour] pairs.
func _swatch_row(text: String, key: String, options: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name := _label(text, FONT_SIZE)
	name.custom_minimum_size = Vector2(200, 0)
	row.add_child(name)
	var group := ButtonGroup.new()
	var buttons: Dictionary[String, Button] = {}
	for option: Array in options:
		var value: String = option[0]
		var button := Button.new()
		button.custom_minimum_size = SWATCH
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = value.capitalize() if not value.is_valid_int() else ""
		button.set_meta("colour", option[1])
		button.pressed.connect(func() -> void: _pick_look(key, value))
		row.add_child(button)
		buttons[value] = button
	swatches[key] = buttons
	return row


## The player's look as the game will draw it: their words, seeded by their
## id where they have chosen no seed yet (the seed a first pick writes).
func _look() -> PersonLook:
	return PersonLook.make(_look_words(), Net.player_body)


func _look_words() -> String:
	var words := Net.player_look
	if not words.begins_with("seed=") and not " seed=" in words:
		words = "seed=%d" % absi(hash(Net.player_id)) + (" " + words if words != "" else "")
	return words


## [param key] chosen as [param value]: written (with the seed it was seen
## with, so the rest stays as shown) and shown.
func _pick_look(key: String, value: String) -> void:
	_set_look_word(key, value)
	Net.save_view_settings()
	_show_look()


func _set_look_word(key: String, value: String) -> void:
	var kept: Array[String] = []
	for word in _look_words().split(" ", false):
		if not word.begins_with(key + "="):
			kept.append(word)
	if value != "":
		kept.append(key + "=" + value)
	Net.player_look = Net.tidy_look(" ".join(kept))


## Every Character control as the look now is, and the preview.
func _show_look() -> void:
	var look := _look()
	for key: String in choices:
		if key == "body" or key.begins_with("look_"):
			var current: String = choices[key]["current"].call()
			for value: String in choices[key]["buttons"]:
				(choices[key]["buttons"][value] as Button).set_pressed_no_signal(value == current)
	for key: String in swatches:
		var current := str(look.get(key))
		for value: String in swatches[key]:
			var button := swatches[key][value] as Button
			button.set_pressed_no_signal(value == current)
			for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
				button.add_theme_stylebox_override(state, UiTheme.swatch_style(button.get_meta("colour"), value == current))
	if beard_row != null:
		beard_row.visible = look.body == &"male"
	if preview != null:
		preview.show_look(look)


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


## Credits: each provider's summary line, then a button that shows the
## full list, every credited thing with its maker, licence and page. The
## theme styles all of it: nothing is set here but sizes.
func _credits_section(section: VBoxContainer) -> void:
	var providers: Array[Dictionary] = []
	for provider: Callable in credit_providers():
		providers.append(provider.call())
	for given: Dictionary in providers:
		section.add_child(_credit_label(str(given.get("summary", "")), true))
	section.add_child(_credit_label("Every asset and its licence: THIRD_PARTY.md, beside the game.", true))
	credits_button = Button.new()
	credits_button.text = "Show all credits"
	credits_button.focus_mode = Control.FOCUS_NONE
	credits_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	credits_button.pressed.connect(toggle_credits)
	section.add_child(credits_button)
	credits_box = ScrollContainer.new()
	credits_box.custom_minimum_size.y = 600.0
	credits_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	credits_box.visible = false
	section.add_child(credits_box)
	credits_list = VBoxContainer.new()
	credits_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	credits_box.add_child(credits_list)
	for given: Dictionary in providers:
		for entry: Dictionary in given.get("entries", []):
			credits_list.add_child(_credit_label("\"%s\" by %s" % [entry.get("title", ""), entry.get("by", "")], false))
			credits_list.add_child(_credit_label(str(entry.get("license", "")), true))
			var url := str(entry.get("url", ""))
			if url != "":
				var link := LinkButton.new()
				link.text = url
				link.focus_mode = Control.FOCUS_NONE
				link.pressed.connect(OS.shell_open.bind(url))
				credits_list.add_child(link)


## Shows or hides the full credits list.
func toggle_credits() -> void:
	_fill_credits()
	credits_box.visible = not credits_box.visible
	credits_button.text = "Hide credits" if credits_box.visible else "Show all credits"


## The Credits section built, once.
func _fill_credits() -> void:
	if credits_button == null:
		_credits_section(_credits)


## A wrapping line of the credits; [param caption] a dimmer one (the
## theme's Caption).
func _credit_label(text: String, caption: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH - 80.0
	if caption:
		label.theme_type_variation = &"Caption"
	return label


## A label in the theme's body text; [param size] only when another size
## is wanted (the theme's sizes, UiTheme.size).
func _label(text: String, size: int = 0) -> Label:
	var label := Label.new()
	label.text = text
	if size > 0 and size != FONT_SIZE:
		label.add_theme_font_size_override("font_size", size)
	return label
