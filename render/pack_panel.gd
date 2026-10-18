class_name PackPanel
extends PanelContainer
## The player's pack ("Jeff's Pack"), and above it whatever they have open:
## a chest, or their companion's pack ("Wren's Pack"); at the HUD's bottom
## right, a box a slot, the item's icon in it (ItemIcons) over its short
## name, or the name alone while there is no icon (headless, not drawn yet,
## no art). Drag an item onto
## another slot to move it there (swapping with what is in it); the move
## goes to the server as a command (Main._transfer) and the boxes show what
## comes back, so every peer shows the same. I shows and hides it (Main);
## opening a chest or a companion's pack shows it with that row. When an
## item lands in a row on show, sound plays there what that container
## sounds like opening (SoundKit.opening: a chest's thud, a crate's, a pack's leather), once a
## frame. A player's or a companion's last two boxes are their hands
## (Items.RIGHT_HAND, LEFT_HAND), edged in brass and marked R and L.
## Sizes in the HUD's 3840 x 2160 units, its look the shared theme's
## (UiTheme, docs/ui_style.md): the panel's box, a slot the Inset
## variation, a hand's HandSlot.

## A slot's box, the theme's "slot" constant square.
static var SLOT_SIZE: Vector2 = Vector2.ONE * UiTheme.constant("slot")
## The theme's body size: a name alone in its box, a title.
static var FONT_SIZE: int = UiTheme.size("body")
## The theme's caption size: the short name under an icon.
static var CAPTION_SIZE: int = UiTheme.size("caption")
## Room round an icon in its box, and under it for the caption.
const ICON_INSET := 8
const ICON_CAPTION := 30
## A named thing's caption (decision 365): the theme's brass_bright.
static var NAMED_COLOR: Color = UiTheme.color("brass_bright")
## One kept from its namer (World.KEPT_MARK; decision 370): rust.
static var KEPT_COLOR: Color = UiTheme.color("rust")

## Called with (from, from_slot, to, to_slot) when an item is dropped.
var transfer: Callable
## Called with (sound set name, entity) for an item landing.
var sound: Callable
## Called with (slot) for a right click on a thing in the player's own row:
## use it.
var use: Callable
## Where icons come from; null: names only.
var icons: ItemIcons
## Whose pack the bottom row shows; null for none (no player).
var player: GridEntity:
	set(value):
		var changed := value != player
		player = value
		if changed and is_node_ready():
			_refresh()
## The open chest or companion, or null.
var other: GridEntity
## Shown without anything else open (I).
var shown := true:
	set(value):
		shown = value
		if is_node_ready():
			_refresh()

var _other_title: Label
var _other_row: HBoxContainer
var _player_title: Label
var _player_row: HBoxContainer
## Each row's entity and contents as last shown: an item new in a slot is
## one that landed there.
var _last: Dictionary[HBoxContainer, Array] = {}


## One slot's box. Dragged from when it holds something; dropped on always.
class SlotBox:
	extends Panel
	var panel: PackPanel
	var mine := true
	var index := 0
	var label: Label
	var icon: TextureRect

	func owner_entity() -> GridEntity:
		return panel.player if mine else panel.other

	func _get_drag_data(_at: Vector2) -> Variant:
		var entity := owner_entity()
		if not is_instance_valid(entity) or index >= entity.slots.size() or entity.slots[index].is_empty():
			return null
		if icon.texture != null:
			var picture := TextureRect.new()
			picture.texture = icon.texture
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			picture.size = PackPanel.SLOT_SIZE
			picture.modulate.a = 0.85
			set_drag_preview(picture)
		else:
			var preview := Label.new()
			preview.text = Items.short_of(entity.slots[index])
			preview.add_theme_font_size_override("font_size", PackPanel.FONT_SIZE)
			set_drag_preview(preview)
		return {"slots_of": entity, "slot": index}

	func _gui_input(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_RIGHT or not mine:
			return
		var entity := owner_entity()
		if is_instance_valid(entity) and index < entity.slots.size() and not entity.slots[index].is_empty() and panel.use.is_valid():
			panel.use.call(index)
			accept_event()

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("slots_of") and is_instance_valid(owner_entity())

	func _drop_data(_at: Vector2, data: Variant) -> void:
		panel.drop(data["slots_of"], int(data["slot"]), owner_entity(), index)


## "Jeff's Pack"; a chest is "Chest".
static func title_of(entity: GridEntity) -> String:
	if entity is Chest:
		return "Chest"
	if entity is Cargo:
		return "Cart" if entity.capacity > Chest.SLOTS else "Crate"
	var who := entity.label if not entity.label.is_empty() else String(entity.name)
	return "%s's Pack" % who


func _ready() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_right = -UiTheme.constant("margin")
	offset_bottom = -UiTheme.constant("margin")
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiTheme.constant("row"))
	add_child(column)
	_other_title = _title()
	column.add_child(_other_title)
	_other_row = _row(false)
	column.add_child(_other_row)
	_player_title = _title()
	column.add_child(_player_title)
	_player_row = _row(true)
	column.add_child(_player_row)
	_refresh()


func _title() -> Label:
	var title := Label.new()
	title.theme_type_variation = &"Heading"
	return title


func _row(mine: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.constant("slot_gap"))
	for i in maxi(Player.SLOTS, Cargo.MAX):
		var box := SlotBox.new()
		box.panel = self
		box.mine = mine
		box.index = i
		box.custom_minimum_size = SLOT_SIZE
		var hand := i >= Items.PACK
		box.theme_type_variation = &"HandSlot" if hand else &"Inset"
		if hand:
			var mark := Label.new()
			mark.text = "R" if i == Items.RIGHT_HAND else "L"
			mark.theme_type_variation = &"Small"
			mark.add_theme_color_override("font_color", UiTheme.color("brass"))
			mark.position = Vector2(10, 4)
			mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(mark)
		var picture := TextureRect.new()
		picture.set_anchors_preset(Control.PRESET_FULL_RECT)
		picture.offset_left = ICON_INSET
		picture.offset_top = ICON_INSET
		picture.offset_right = -ICON_INSET
		picture.offset_bottom = -ICON_CAPTION
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.icon = picture
		box.add_child(picture)
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


## Shows [param opened]'s row, a chest or a companion (null closes it).
func open(opened: GridEntity) -> void:
	if opened != other and is_instance_valid(other) and sound.is_valid() and SoundKit.closing(other) != "":
		sound.call(SoundKit.closing(other), other)
	other = opened
	_refresh()


## Moves an item, by way of transfer.
func drop(from: GridEntity, from_slot: int, to: GridEntity, to_slot: int) -> void:
	if transfer.is_valid() and is_instance_valid(from) and is_instance_valid(to):
		transfer.call(from, from_slot, to, to_slot)


## What box [param index] of the open row ([param mine] false) or the
## player's shows: the item's short name, "" for empty.
func shown_in(mine: bool, index: int) -> String:
	var row := _player_row if mine else _other_row
	return (row.get_child(index) as SlotBox).label.text


## The icon box [param index] of the open row or the player's shows, or
## null (names only).
func icon_in(mine: bool, index: int) -> Texture2D:
	var row := _player_row if mine else _other_row
	return (row.get_child(index) as SlotBox).icon.texture


## The title over the open row ([param mine] false) or the player's.
func title_shown(mine: bool) -> String:
	return (_player_title if mine else _other_title).text


func _refresh() -> void:
	if not is_instance_valid(other):
		other = null
	visible = (shown or other != null) and is_instance_valid(player)
	_other_title.visible = other != null
	_other_row.visible = other != null
	_other_title.text = title_of(other) if other != null else ""
	_player_title.text = title_of(player) if is_instance_valid(player) else ""
	var landed: GridEntity = null
	for row: HBoxContainer in [_other_row, _player_row]:
		var entity: GridEntity = player if row == _player_row else other
		if not is_instance_valid(entity) or not row.visible or not visible:
			_last.erase(row)
		else:
			var before: Array = _last.get(row, [])
			if not before.is_empty() and before[0] == entity:
				for i in entity.slots.size():
					var item := entity.slots[i]
					if not item.is_empty() and i < before[1].size() and before[1][i] != item:
						landed = entity
			_last[row] = [entity, entity.slots.duplicate()]
		for box: SlotBox in row.get_children():
			var has := is_instance_valid(entity) and box.index < entity.slots.size()
			box.visible = has or not is_instance_valid(entity)
			var item := entity.slots[box.index] if has else ""
			box.label.text = Items.short_of(item) if not item.is_empty() else ""
			# A named thing (decision 365) is gilded, and says its name and strength on hover.
			var noted := has and box.index < entity.slot_notes.size() and not entity.slot_notes[box.index].is_empty()
			box.tooltip_text = entity.slot_notes[box.index] if noted else ""
			# A plain thing's note (a bundle's condition) starts with its catalog
			# name; a named one's with its name (decision 375).
			var named := noted and not entity.slot_notes[box.index].begins_with(Items.name_of(item))
			var kept := named and World.KEPT_MARK in entity.slot_notes[box.index]
			box.label.add_theme_color_override("font_color", KEPT_COLOR if kept else NAMED_COLOR if named else Items.color_of(item))
			_show_icon(box, icons.icon(item) if icons != null and not item.is_empty() else null)
	if landed != null and sound.is_valid():
		sound.call(SoundKit.opening(landed), landed)


## [param picture] in [param box], its name a caption under it; null: the
## name alone, in the middle.
func _show_icon(box: SlotBox, picture: Texture2D) -> void:
	if box.icon.texture == picture:
		return
	box.icon.texture = picture
	box.label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER if picture == null else VERTICAL_ALIGNMENT_BOTTOM
	box.label.add_theme_font_size_override("font_size", FONT_SIZE if picture == null else CAPTION_SIZE)
	box.label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if picture == null else TextServer.AUTOWRAP_OFF
	box.label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING if picture == null else TextServer.OVERRUN_TRIM_ELLIPSIS
	box.label.clip_text = picture != null
