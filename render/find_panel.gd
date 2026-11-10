class_name FindPanel
extends PanelContainer
## A cache chest's find (599 amended, ui's side; items' "find" message,
## Main.find_data): the place as its title (items' "title", voice's label),
## a row a thing with its icon (ItemIcons) and count in the rolled order,
## the gold, and one button, Take all (voice's words), which asks the
## server for the lot (Main.take_find_all) and closes; a click on a row (the
## gold's too) takes that one (one loot window: Main.take_find_one), the
## server sending what is left, and a find with nothing left closes it
## (Jeff: "on 4 square chests, you can only drag and drop loot"). Closing (its X, Esc,
## or walking off from the chest) leaves the find in the chest; the server
## sends it again when the chest is opened. The server's party line says
## what was taken and what fell at the feet. In the shared theme's look
## (UiTheme); sizes in the HUD's 3840 x 2160 units.

const TAKE_WORDS := "Take all"
## A row's height and its icon's side.
const ROW_HEIGHT := 72
const ICON_SIDE := 64
## The window's middle, down the screen's height.
const AT := 0.4
## Cells from the chest past which the window closes (a step back is fine).
const REACH := 3

## Take all pressed.
signal take_asked
## A row clicked: its thing's id, "gold" for the gold.
signal take_one(id: String)
## Closed without taking (its X).
signal closed

## Where icons come from; null: names only.
var icons: ItemIcons:
	set(value):
		if icons != null and icons.icon_ready.is_connected(_icon_arrived):
			icons.icon_ready.disconnect(_icon_arrived)
		icons = value
		if icons != null:
			icons.icon_ready.connect(_icon_arrived)
## The find shown: Main.find_data's form.
var data := {}

var _title: Label
var _rows: VBoxContainer
var _gold: Label
var _take: Button


func _init() -> void:
	name = "FindPanel"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 24)
	column.add_child(head)
	_title = Label.new()
	_title.theme_type_variation = &"Heading"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var shut := Button.new()
	shut.name = "Close"
	shut.text = "X"
	shut.flat = true
	shut.pressed.connect(close_untaken)
	head.add_child(shut)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	column.add_child(_rows)
	_gold = Label.new()
	_gold.add_theme_color_override("font_color", UiTheme.color("brass"))
	_takes_on_click(_gold, "gold")
	column.add_child(_gold)
	_take = Button.new()
	_take.name = "Take"
	_take.text = TAKE_WORDS
	_take.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_take.pressed.connect(func() -> void: take_asked.emit())
	column.add_child(_take)
	_rebuild()


## Shows [param find] (a "find" message); an empty one, or one with nothing
## left (rows [], gold 0: all taken), closes.
func show_find(find: Dictionary) -> void:
	var rows: Variant = find.get("rows", [])
	var left := (rows is Array and not (rows as Array).is_empty()) or int(find.get("gold", 0)) > 0
	data = find if left else {}
	visible = left
	_rebuild()


## [param control] takes [param id] on a left click (a double click's
## second press asks nothing more), lit while the pointer is over it.
func _takes_on_click(control: Control, id: String) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_STOP
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	control.mouse_entered.connect(func() -> void: control.modulate = Color(1.25, 1.2, 1.1))
	control.mouse_exited.connect(func() -> void: control.modulate = Color.WHITE)
	control.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			control.accept_event()
			if not click.double_click:
				take_one.emit(id))


## Closes, the find left in the chest.
func close_untaken() -> void:
	if visible:
		close()
		closed.emit()


func close() -> void:
	data = {}
	visible = false


func is_open() -> bool:
	return visible


## The rows shown, "name xcount" each, and the gold line (tests).
func rows_shown() -> Array[String]:
	var out: Array[String] = []
	for row: Node in _rows.get_children():
		if not row.is_queued_for_deletion():
			out.append(str(row.get_meta("shown", "")))
	return out


func gold_shown() -> String:
	return _gold.text if _gold.visible else ""


func title_shown() -> String:
	return _title.text


func _rebuild() -> void:
	if not is_node_ready():
		return
	for row: Node in _rows.get_children():
		row.queue_free()
	_title.text = str(data.get("title", ""))
	var rows: Array = data.get("rows", []) if data.get("rows") is Array else []
	for each: Variant in rows:
		if not each is Dictionary:
			continue
		var id := str(each.get("id", ""))
		var count := int(each.get("count", 1))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		row.custom_minimum_size.y = ROW_HEIGHT
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.custom_minimum_size = Vector2(ICON_SIDE, ICON_SIDE)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = icons.icon(id) if icons != null else null
		row.add_child(icon)
		var label := Label.new()
		label.add_theme_color_override("font_color", Items.color_of(id))
		var shown := Gains.counted(Items.name_of(id), count) if count > 1 else Items.name_of(id)
		label.text = ("%d %s" % [count, shown]) if count > 1 else shown
		row.add_child(label)
		row.set_meta("id", id)
		row.set_meta("shown", label.text)
		_takes_on_click(row, id)
		_rows.add_child(row)
	var gold := int(data.get("gold", 0))
	_gold.text = "%d gold" % gold
	_gold.visible = gold > 0
	_take.disabled = rows.is_empty() and gold <= 0


func _icon_arrived(id: String) -> void:
	for row: Node in _rows.get_children():
		if str(row.get_meta("id", "")) == id and icons != null:
			(row.get_node("Icon") as TextureRect).texture = icons.icon(id)


func _process(_delta: float) -> void:
	if not visible:
		return
	reset_size()
	var view := get_viewport_rect().size
	position = Vector2((view.x - size.x) / 2.0, view.y * AT - size.y / 2.0)
