class_name TuningPanel
extends PanelContainer
## Feel tuning's window (decision 673, ui's side; combat's Tuning holds the
## fields): F7 in a local host only (Tuning.allowed; Main.tuning_panel_toggled).
## The Fields tab lists Tuning.fields() by group, each row its kind's
## control: a slider with a typed number for an int or a float, a checkbox
## for a bool, a typed list ("4, 8, 12") for ints or floats. A change applies
## at once (Tuning.apply); a changed row is marked and has its own reset,
## and the tab has reset all, a filter, save, copy to review and load (the
## saves in Tuning.save_dir). The Arena tab: a monster kind spawned, fighting
## or standing, or a dummy, at the next cell clicked in the world; clear;
## an item given to the player; full hp and stamina; the hall reset; and
## the time keys' buttons (F8 the scale, F9 pause, "." a tick). No message
## or command: a local host is the world, so Tuning's calls are direct.
## The look is the shared theme's (UiTheme, docs/ui_style.md).

## Reset the practice hall (Main: the zone laid again, the tuning kept).
signal reset_hall

## In the 3840 by 2160 base (project.godot): a row's path, slider, typed
## number and reset on one line, and a long list of rows.
const WIDTH := 1300.0
const HEIGHT := 1500.0
## A slider's steps for a float field's range.
const FLOAT_STEPS := 200.0
const LIST_HINT := "numbers, comma-separated"

## Who the arena's give and full go to (Main's local player); null for none.
var player: Callable
## The arena's pick waiting for a click in the world: "", "dummy" or a
## monsters.json kind; and whether a spawned kind fights.
var picking := ""
var fights := true

var _tabs: TabContainer
var _filter: LineEdit
var _rows_box: VBoxContainer
var _status: Label
var _saves: OptionButton
var _kinds: OptionButton
var _items: OptionButton
var _fights: CheckBox
var _time: Label
## path -> {row, control, value, mark, reset, kind}
var _rows := {}


func _init() -> void:
	name = "TuningPanel"
	visible = false
	set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
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
	title.text = "Tuning"
	column.add_child(title)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_tabs)
	_tabs.add_child(_fields_tab())
	_tabs.add_child(_arena_tab())
	_status = Label.new()
	_status.theme_type_variation = &"Caption"
	_status.add_theme_color_override("font_color", UiTheme.color("text_dim"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Changes apply at once and live in this game only; Save keeps them."
	column.add_child(_status)


func _fields_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = "Fields"
	tab.add_theme_constant_override("separation", UiTheme.constant("row"))
	_filter = LineEdit.new()
	_filter.placeholder_text = "Filter the fields"
	_filter.text_changed.connect(func(_text: String) -> void: _show_rows())
	tab.add_child(_filter)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab.add_child(scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_box)
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", UiTheme.constant("row"))
	tab.add_child(buttons)
	buttons.add_child(_button("Reset all", reset_all))
	buttons.add_child(_button("Save", save))
	buttons.add_child(_button("Copy to review", copy_to_review))
	_saves = OptionButton.new()
	_saves.focus_mode = Control.FOCUS_NONE
	buttons.add_child(_saves)
	buttons.add_child(_button("Load", _load_picked))
	return tab


func _arena_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = "Arena"
	tab.add_theme_constant_override("separation", UiTheme.constant("row"))
	var spawn := HFlowContainer.new()
	spawn.add_theme_constant_override("h_separation", UiTheme.constant("row"))
	tab.add_child(spawn)
	_kinds = OptionButton.new()
	_kinds.focus_mode = Control.FOCUS_NONE
	spawn.add_child(_kinds)
	_fights = CheckBox.new()
	_fights.text = "Fights"
	_fights.button_pressed = true
	_fights.focus_mode = Control.FOCUS_NONE
	_fights.toggled.connect(func(on: bool) -> void: fights = on)
	spawn.add_child(_fights)
	spawn.add_child(_button("Spawn at a click", func() -> void: pick(_kinds.get_item_text(_kinds.selected) if _kinds.selected >= 0 else "")))
	spawn.add_child(_button("Dummy at a click", pick.bind("dummy")))
	spawn.add_child(_button("Clear", clear_arena))
	var gear := HFlowContainer.new()
	gear.add_theme_constant_override("h_separation", UiTheme.constant("row"))
	tab.add_child(gear)
	_items = OptionButton.new()
	_items.focus_mode = Control.FOCUS_NONE
	gear.add_child(_items)
	gear.add_child(_button("Give me", func() -> void: give(_items.get_item_text(_items.selected) if _items.selected >= 0 else "")))
	gear.add_child(_button("Full hp and stamina", full))
	gear.add_child(_button("Reset the hall", func() -> void: reset_hall.emit()))
	var time := HFlowContainer.new()
	time.add_theme_constant_override("h_separation", UiTheme.constant("row"))
	tab.add_child(time)
	time.add_child(_button("Time scale (F8)", func() -> void:
		Tuning.cycle_scale()
		_show_time()))
	time.add_child(_button("Pause (F9)", func() -> void:
		Tuning.toggle_pause()
		_show_time()))
	time.add_child(_button("One tick (.)", func() -> void:
		Tuning.step_once()
		_show_time()))
	_time = Label.new()
	time.add_child(_time)
	return tab


func _button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(pressed)
	return button


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## Shown, the fields read afresh (a tree's source may have come since).
func open() -> void:
	if not Tuning.allowed():
		return
	visible = true
	build_rows()
	_fill_saves()
	_fill_arena()
	_show_time()


func close() -> void:
	visible = false
	picking = ""
	var focus := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focus != null and is_ancestor_of(focus):
		focus.release_focus()


## Whether a typed field has the keys (Main.is_typing: no walking meanwhile).
func is_typing() -> bool:
	if not visible or not is_inside_tree():
		return false
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit and is_ancestor_of(focus)


## The rows from Tuning.fields(), under a heading a group (a group whose
## fields take at a spawn says so).
func build_rows() -> void:
	for child in _rows_box.get_children():
		child.queue_free()
		_rows_box.remove_child(child)
	_rows.clear()
	var groups := {}
	var order: Array[String] = []
	for row in Tuning.fields():
		var group := str(row.get("group", ""))
		if not groups.has(group):
			groups[group] = []
			order.append(group)
		groups[group].append(row)
	for group in order:
		var heading := Label.new()
		heading.theme_type_variation = &"Hud"
		heading.add_theme_color_override("font_color", UiTheme.color("brass_bright"))
		var spawn: bool = (groups[group] as Array).any(func(row: Dictionary) -> bool: return row.get("takes") == "spawn")
		heading.text = group + (" (new spawns only)" if spawn else "")
		heading.set_meta("group", group)
		_rows_box.add_child(heading)
		for row: Dictionary in groups[group]:
			_rows_box.add_child(_row_for(row))
	_mark_all()
	_show_rows()


func _row_for(field: Dictionary) -> Control:
	var path: String = field["path"]
	var kind: String = field.get("kind", "")
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", UiTheme.constant("row"))
	line.set_meta("path", path)
	var label := Label.new()
	label.text = path
	label.tooltip_text = "%s (%s, %s's)" % [path, kind, field.get("owner", "")]
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.custom_minimum_size.x = 560.0
	label.clip_text = true
	line.add_child(label)
	var entry := {"row": line, "kind": kind, "mark": label, "control": null, "value": null}
	match kind:
		"bool":
			var box := CheckBox.new()
			box.focus_mode = Control.FOCUS_NONE
			box.toggled.connect(func(on: bool) -> void: set_value(path, on))
			box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(box)
			entry["control"] = box
		"int", "float":
			var slider := HSlider.new()
			slider.min_value = float(field.get("min", 0))
			slider.max_value = maxf(float(field.get("max", 1)), slider.min_value + 1.0)
			slider.step = 1.0 if kind == "int" else (slider.max_value - slider.min_value) / FLOAT_STEPS
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			slider.focus_mode = Control.FOCUS_NONE
			slider.value_changed.connect(func(v: float) -> void:
				if not line.has_meta("showing"):
					set_value(path, v))
			line.add_child(slider)
			entry["control"] = slider
			var typed := LineEdit.new()
			typed.custom_minimum_size.x = 170.0
			typed.text_submitted.connect(func(text: String) -> void: _typed(path, text))
			typed.focus_exited.connect(func() -> void: _show_value(path))
			line.add_child(typed)
			entry["value"] = typed
		_:
			var list := LineEdit.new()
			list.placeholder_text = LIST_HINT
			list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			list.text_submitted.connect(func(text: String) -> void: _typed(path, text))
			list.focus_exited.connect(func() -> void: _show_value(path))
			line.add_child(list)
			entry["value"] = list
	var reset_button := _button("Reset", func() -> void: reset(path))
	line.add_child(reset_button)
	entry["reset"] = reset_button
	_rows[path] = entry
	_show_value(path)
	return line


## [param path] set to [param v] (Tuning.apply); its row marked. Whether it took.
func set_value(path: String, v: Variant) -> bool:
	var took := Tuning.apply(path, v)
	if not took:
		_status.text = "%s: not taken (%s)" % [path, v]
	_show_value(path)
	_mark(path)
	return took


## A typed number or list for [param path]: "12", "0.5", "4, 8, 12".
func _typed(path: String, text: String) -> void:
	var entry: Dictionary = _rows.get(path, {})
	var kind: String = entry.get("kind", "")
	var parsed: Variant = parse_typed(text, kind)
	if parsed == null:
		_status.text = "%s: \"%s\" is not %s" % [path, text, "a number" if kind in ["int", "float"] else LIST_HINT]
		_show_value(path)
		return
	set_value(path, parsed)


## [param text] as [param kind]'s value: a number, or a list of numbers
## (commas or spaces between); null when it is not one.
static func parse_typed(text: String, kind: String) -> Variant:
	var said := text.strip_edges()
	if kind in ["int", "float"]:
		return float(said) if said.is_valid_float() else null
	if kind in ["ints", "floats"]:
		var out := []
		for each in said.replace(",", " ").split(" ", false):
			if not each.is_valid_float():
				return null
			out.append(float(each))
		return out if not out.is_empty() else null
	return null


## [param v] as the panel writes it: a list "4, 8, 12", a float trimmed.
static func shown(v: Variant) -> String:
	if v is Array:
		return ", ".join((v as Array).map(func(each: Variant) -> String: return shown(each)))
	if v is float:
		return String.num(v, 3)
	return str(v)


func _show_value(path: String) -> void:
	var entry: Dictionary = _rows.get(path, {})
	if entry.is_empty():
		return
	var v: Variant = Tuning.value(path)
	var line: Control = entry["row"]
	line.set_meta("showing", true)
	if entry["control"] is CheckBox:
		(entry["control"] as CheckBox).set_pressed_no_signal(bool(v))
	elif entry["control"] is HSlider and v != null:
		(entry["control"] as HSlider).set_value_no_signal(float(v))
	if entry["value"] is LineEdit and not (entry["value"] as LineEdit).has_focus():
		(entry["value"] as LineEdit).text = shown(v)
	line.remove_meta("showing")


func _mark(path: String) -> void:
	var entry: Dictionary = _rows.get(path, {})
	if entry.is_empty():
		return
	var changed := Tuning.changes().has(path)
	var label: Label = entry["mark"]
	label.text = ("* " if changed else "") + path
	label.add_theme_color_override("font_color", UiTheme.color("rust" if changed else "text"))
	(entry["reset"] as Button).disabled = not changed


func _mark_all() -> void:
	for path: String in _rows:
		_show_value(path)
		_mark(path)


## Whether [param path]'s row shows as changed.
func marked(path: String) -> bool:
	return _rows.has(path) and str((_rows[path]["mark"] as Label).text).begins_with("* ")


## How many rows the filter shows.
func shown_rows() -> int:
	var count := 0
	for path: String in _rows:
		if (_rows[path]["row"] as Control).visible:
			count += 1
	return count


func _show_rows() -> void:
	var wanted := _filter.text.strip_edges().to_lower()
	for child in _rows_box.get_children():
		if child.has_meta("path"):
			var path := str(child.get_meta("path"))
			child.visible = wanted.is_empty() or path.to_lower().contains(wanted)
	# A heading shows while any row under it does.
	var heading: Control = null
	var any := false
	for child in _rows_box.get_children():
		if child.has_meta("group"):
			if heading != null:
				heading.visible = any
			heading = child
			any = false
		elif child.visible:
			any = true
	if heading != null:
		heading.visible = any


func reset(path: String) -> void:
	Tuning.reset(path)
	_show_value(path)
	_mark(path)


func reset_all() -> void:
	Tuning.reset_all()
	_mark_all()
	_status.text = "Every field back to the repo's value."


## The changes saved (Tuning.save); the file's path, "" for none.
func save() -> String:
	var path := Tuning.save()
	_status.text = "Saved %s" % path if not path.is_empty() else "Nothing changed to save."
	_fill_saves()
	return path


## The newest save copied for review (Tuning.copy_to_review), saving first
## when there are changes not yet saved.
func copy_to_review() -> String:
	var newest := save() if not Tuning.changes().is_empty() else _newest_save()
	var copied := Tuning.copy_to_review(newest) if not newest.is_empty() else ""
	_status.text = "Copied for review: %s" % copied if not copied.is_empty() else "Nothing saved to copy."
	return copied


## The saves in Tuning.save_dir, newest first.
static func saves() -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(Tuning.save_dir):
		return out
	for file in DirAccess.get_files_at(Tuning.save_dir):
		if file.ends_with(".json"):
			out.append(file)
	out.sort()
	out.reverse()
	return out


func _newest_save() -> String:
	var all := saves()
	return Tuning.save_dir.path_join(all[0]) if not all.is_empty() else ""


func _fill_saves() -> void:
	_saves.clear()
	for file in saves():
		_saves.add_item(file)


## A save read back in (Tuning.load_file); how many fields took.
func load_save(file: String) -> int:
	var took := Tuning.load_file(Tuning.save_dir.path_join(file))
	_status.text = "Loaded %s: %d fields" % [file, took] if took >= 0 else "%s: not a save" % file
	_mark_all()
	return took


func _load_picked() -> void:
	if _saves.selected >= 0:
		load_save(_saves.get_item_text(_saves.selected))


func _fill_arena() -> void:
	if _kinds.item_count == 0:
		var kinds: Array = Monster.kinds().keys()
		kinds.sort()
		for kind: String in kinds:
			_kinds.add_item(kind)
	if _items.item_count == 0:
		var ids: Array = Items.ids()
		ids.sort()
		for id: String in ids:
			_items.add_item(id)


## The next cell clicked in the world gets [param what] ("dummy" or a kind).
func pick(what: String) -> void:
	if what.is_empty():
		return
	picking = what
	_status.text = "Click a cell for the %s (Esc to stop)." % what


## The pick placed at [param cell] (Main, on the click); what was made.
func place(cell: Vector2i) -> GridEntity:
	var what := picking
	picking = ""
	if what.is_empty():
		return null
	var made := Tuning.spawn_dummy(cell) if what == "dummy" else Tuning.spawn_kind(what, cell, fights)
	_status.text = "%s at %s" % [what, cell] if made != null else "No %s at %s." % [what, cell]
	return made


func clear_arena() -> void:
	Tuning.clear()
	_status.text = "The arena's spawns gone."


func give(id: String) -> bool:
	var who: Variant = player.call() if player.is_valid() else null
	var took := Tuning.give(who as GridEntity, id) if who is GridEntity else false
	_status.text = "Given %s" % id if took else "Could not give %s." % id
	return took


func full() -> void:
	var who: Variant = player.call() if player.is_valid() else null
	if who is GridEntity:
		Tuning.full(who)
		_status.text = "Full hp and stamina."


func _show_time() -> void:
	if _time != null:
		_time.text = "time x%s%s" % [Tuning.time_scale(), ", paused" if Tuning.paused else ""]
