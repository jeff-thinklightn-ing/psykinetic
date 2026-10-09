class_name SlotsPanel
extends PanelContainer
## The player's slots, and an open chest's above them, at the HUD's bottom
## right: a box a slot, the item's short name in it. Drag an item onto
## another slot to move it there (swapping with what is in it); the move
## goes to the server as a command (Main._transfer) and the boxes show
## what comes back, so every peer shows the same. I shows and hides it
## (Main); opening a chest shows it with the chest's row. Sizes in the HUD's
## 3840 x 2160 units.

const SLOT_SIZE := Vector2(132, 132)
const FONT_SIZE := 26
const BACKING := Color(0.04, 0.04, 0.06, 0.82)
const SLOT := Color(0.16, 0.15, 0.14, 0.95)
const SLOT_EDGE := Color(0.55, 0.5, 0.42, 0.9)
const TEXT := Color(0.93, 0.92, 0.88, 0.95)

## Called with (from, from_slot, to, to_slot) when an item is dropped.
var transfer: Callable
## Whose slots the bottom row shows; null for none (no player).
var player: GridEntity:
	set(value):
		var changed := value != player
		player = value
		if changed and is_node_ready():
			_refresh()
## The open chest, or null.
var chest: GridEntity
## Shown without a chest open (I).
var shown := true:
	set(value):
		shown = value
		if is_node_ready():
			_refresh()

var _chest_title: Label
var _chest_row: HBoxContainer
var _player_row: HBoxContainer


## One slot's box. Dragged from when it holds something; dropped on always.
class SlotBox:
	extends Panel
	var panel: SlotsPanel
	var mine := true
	var index := 0
	var label: Label

	func owner_entity() -> GridEntity:
		return panel.player if mine else panel.chest

	func _get_drag_data(_at: Vector2) -> Variant:
		var entity := owner_entity()
		if not is_instance_valid(entity) or index >= entity.slots.size() or entity.slots[index].is_empty():
			return null
		var preview := Label.new()
		preview.text = Items.short_of(entity.slots[index])
		preview.add_theme_font_size_override("font_size", SlotsPanel.FONT_SIZE)
		set_drag_preview(preview)
		return {"slots_of": entity, "slot": index}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("slots_of") and is_instance_valid(owner_entity())

	func _drop_data(_at: Vector2, data: Variant) -> void:
		panel.drop(data["slots_of"], int(data["slot"]), owner_entity(), index)


func _ready() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_right = -40
	offset_bottom = -40
	var style := StyleBoxFlat.new()
	style.bg_color = BACKING
	style.set_corner_radius_all(16)
	style.set_content_margin_all(18)
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	_chest_title = _title("Chest")
	column.add_child(_chest_title)
	_chest_row = _row(false)
	column.add_child(_chest_row)
	column.add_child(_title("You"))
	_player_row = _row(true)
	column.add_child(_player_row)
	_refresh()


func _title(text: String) -> Label:
	var title := Label.new()
	title.text = text
	title.add_theme_font_size_override("font_size", FONT_SIZE)
	title.add_theme_color_override("font_color", TEXT)
	return title


func _row(mine: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for i in maxi(Player.SLOTS, Chest.SLOTS):
		var box := SlotBox.new()
		box.panel = self
		box.mine = mine
		box.index = i
		box.custom_minimum_size = SLOT_SIZE
		var style := StyleBoxFlat.new()
		style.bg_color = SLOT
		style.border_color = SLOT_EDGE
		style.set_border_width_all(2)
		style.set_corner_radius_all(8)
		box.add_theme_stylebox_override("panel", style)
		var label := Label.new()
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", FONT_SIZE)
		box.label = label
		box.add_child(label)
		row.add_child(box)
	return row


func _process(_delta: float) -> void:
	_refresh()


## Shows [param opened]'s row (null closes it).
func open(opened: GridEntity) -> void:
	chest = opened
	_refresh()


## Moves an item, by way of transfer.
func drop(from: GridEntity, from_slot: int, to: GridEntity, to_slot: int) -> void:
	if transfer.is_valid() and is_instance_valid(from) and is_instance_valid(to):
		transfer.call(from, from_slot, to, to_slot)


## What box [param index] of the chest's row ([param mine] false) or the
## player's shows: the item's short name, "" for empty.
func shown_in(mine: bool, index: int) -> String:
	var row := _player_row if mine else _chest_row
	return (row.get_child(index) as SlotBox).label.text


func _refresh() -> void:
	if not is_instance_valid(chest):
		chest = null
	visible = (shown or chest != null) and is_instance_valid(player)
	_chest_title.visible = chest != null
	_chest_row.visible = chest != null
	for row: HBoxContainer in [_chest_row, _player_row]:
		var entity: GridEntity = player if row == _player_row else chest
		for box: SlotBox in row.get_children():
			var has := is_instance_valid(entity) and box.index < entity.slots.size()
			box.visible = has or not is_instance_valid(entity)
			var item := entity.slots[box.index] if has else ""
			box.label.text = Items.short_of(item) if not item.is_empty() else ""
			box.label.add_theme_color_override("font_color", Items.color_of(item))
