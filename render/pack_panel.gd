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
## frame. A player's or a companion's boxes after the pack are their hands
## (Items.RIGHT_HAND, LEFT_HAND), edged in brass and marked R and L, and
## the armour worn (Items.ARMOUR, decision 622), marked A: armour is put on
## by dragging it there and taken off by dragging it out, as a weapon moves
## into a hand (no click verb); the server refuses anything else there, or
## armour in a hand, with a party line (World.slot_refused), and the hover
## reads the kind's note (ItemTip, the catalog's "about").
## Sizes in the HUD's 3840 x 2160 units, its look the shared theme's
## (UiTheme, docs/ui_style.md): the panel's box, a slot the Inset
## variation, a hand's HandSlot. Hover a slot for what its thing is
## (ItemTip: name, kind, strength, condition, kills, story); under the
## player's row, their load against their own mass, its band, and what the
## arms' and the body's parts slow (decision 676, ui's side).

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
## Where icons come from; null: names only. An icon that finishes loading
## (icon_ready) is a change to show.
var icons: ItemIcons:
	set(value):
		if icons == value:
			return
		if icons != null and icons.icon_ready.is_connected(_icon_arrived):
			icons.icon_ready.disconnect(_icon_arrived)
		icons = value
		if icons != null:
			icons.icon_ready.connect(_icon_arrived)
		_icons_seen += 1
## Counts the icons that arrived, part of the shown signature.
var _icons_seen := 0
## What the rows showed at the last refresh (_signature): the panel lays
## itself out again only when it differs (ui's perf pass; it ran every frame).
var _signature_shown: Array = []
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

## The barter window's hooks (BarterPanel, 560): a left click on one of the
## player's boxes goes to select_hook(mine, index) first (true: taken, no
## drag); the mouse over one, or off (index -1), to hover_hook; the slots
## selected to give are framed (set_selected) and never dragged.
var select_hook: Callable
var hover_hook: Callable
var selected: Dictionary = {}

var _other_title: Label
## The open row's title and, for a companion, her bond's step beside it
## (555, ui's side): ", sullen" dim, nothing at fond; hover: her reason.
var _other_head: HBoxContainer
var _other_mood: Label
var _other_row: HBoxContainer
var _player_title: Label
var _player_row: HBoxContainer
var _weight: Label
## The arms' and the body's lines under the load (676, ui's side).
var _load: Label
## What the player has promised the townsfolk (open commissions, npc's
## "offers" with "open"; 536, ui's side): a caption in the foot, "Promised:
## Bring Bram home", nothing when none.
var promised: Array[String] = []:
	set(value):
		if value == promised:
			return
		promised = value
		if is_node_ready():
			_refresh()
var _promised: Label
## The resurrection charges the player holds, "charges 23 of 50" (dungeon's
## 573: Player.charges and charge_room, replicated; shown once blessed,
## charge_room over 0; no bar).
var _charges: Label
## The hover tip, a sibling above the panel (made on the first hover).
var tip: ItemTip
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
	## The slot's note (World._show_notes), for the tip.
	var note := ""
	## The stack's count in the corner (619, ui's side): "5", nothing alone.
	var count: Label

	func _ready() -> void:
		mouse_entered.connect(func() -> void:
			panel.show_tip(self)
			if panel.hover_hook.is_valid():
				panel.hover_hook.call(mine, index))
		mouse_exited.connect(func() -> void:
			panel.hide_tip()
			if panel.hover_hook.is_valid():
				panel.hover_hook.call(mine, -1))

	func owner_entity() -> GridEntity:
		return panel.player if mine else panel.other

	## What a drag from this box carries: {slots_of, slot, count} (count 1
	## for one unit of a stack with Shift held, 619; 0 for the whole slot),
	## null for nothing to drag.
	func drag_payload() -> Variant:
		var entity := owner_entity()
		if not is_instance_valid(entity) or index >= entity.slots.size() or entity.slots[index].is_empty():
			return null
		if mine and panel.selected.has(index):
			return null  # Selected for barter (560): it stays put until unselected.
		# Shift held: one unit off the stack (619, ui's side); else the whole slot.
		var one := PackPanel.shift_down() and World.slot_count(entity, index) > 1
		return {"slots_of": entity, "slot": index, "count": 1 if one else 0}

	func _get_drag_data(_at: Vector2) -> Variant:
		var data: Variant = drag_payload()
		if data == null:
			return null
		var entity := owner_entity()
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
		return data

	func _gui_input(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		# The barter window open (560): a left click selects the thing to give.
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT and panel.select_hook.is_valid() \
				and panel.select_hook.call(mine, index, click.shift_pressed):
			accept_event()
			return
		if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_RIGHT or not mine:
			return
		var entity := owner_entity()
		if is_instance_valid(entity) and index < entity.slots.size() and not entity.slots[index].is_empty() and panel.use.is_valid():
			panel.use.call(index)
			accept_event()

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("slots_of") and is_instance_valid(owner_entity())

	func _drop_data(_at: Vector2, data: Variant) -> void:
		panel.drop(data["slots_of"], int(data["slot"]), owner_entity(), index, int(data.get("count", 0)))


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
	_other_head = HBoxContainer.new()
	_other_head.add_theme_constant_override("separation", 0)
	column.add_child(_other_head)
	_other_title = _title()
	_other_title.mouse_filter = Control.MOUSE_FILTER_PASS  # For the reason's tooltip.
	_other_head.add_child(_other_title)
	_other_mood = Label.new()
	_other_mood.theme_type_variation = &"Caption"
	_other_mood.add_theme_color_override("font_color", UiTheme.color("text_dim"))
	_other_mood.size_flags_vertical = Control.SIZE_SHRINK_END
	_other_mood.mouse_filter = Control.MOUSE_FILTER_PASS
	_other_head.add_child(_other_mood)
	_other_row = _row(false)
	column.add_child(_other_row)
	_player_title = _title()
	column.add_child(_player_title)
	_player_row = _row(true)
	column.add_child(_player_row)
	_weight = Label.new()
	_weight.theme_type_variation = &"Caption"
	column.add_child(_weight)
	_load = Label.new()
	_load.theme_type_variation = &"Caption"
	_load.add_theme_color_override("font_color", UiTheme.color("text_dim"))
	column.add_child(_load)
	_promised = Label.new()
	_promised.theme_type_variation = &"Caption"
	_promised.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_promised.add_theme_color_override("font_color", UiTheme.color("brass"))
	column.add_child(_promised)
	_charges = Label.new()
	_charges.theme_type_variation = &"Caption"
	_charges.add_theme_color_override("font_color", UiTheme.color("text_dim"))
	column.add_child(_charges)
	_refresh()


## The tip for [param box]'s thing, over the slot; nothing for an empty one.
func show_tip(box: SlotBox) -> void:
	var entity := box.owner_entity()
	if not is_instance_valid(entity) or box.index >= entity.slots.size() or entity.slots[box.index].is_empty():
		hide_tip()
		return
	if tip == null:
		tip = ItemTip.new()
		(get_parent() if get_parent() != null else self).add_child(tip)
	tip.show_for(entity.slots[box.index], box.note, box.get_global_rect().position)


func hide_tip() -> void:
	if tip != null:
		tip.visible = false


## "carrying 21.6 of 80 kg: burdened" for the player's load (tests).
func weight_shown() -> String:
	return _weight.text


## The arms' and the body's lines, one a line (tests).
func load_shown() -> String:
	return _load.text


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
		var hand := i < Items.CARRIED and not Items.is_pack(i)
		box.theme_type_variation = &"HandSlot" if hand else &"Inset"
		if hand:
			var mark := Label.new()
			mark.text = "R" if i == Items.RIGHT_HAND else "L" if i == Items.LEFT_HAND else "A"  # The armour worn (622).
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
		# The stack's count, small in brass in the bottom-right corner (619,
		# ui's side), over the caption's end.
		var count := Label.new()
		count.theme_type_variation = &"Small"
		count.add_theme_color_override("font_color", UiTheme.color("brass"))
		count.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		count.grow_vertical = Control.GROW_DIRECTION_BEGIN
		count.offset_right = -6
		count.offset_bottom = -2
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count.visible = false
		box.count = count
		box.add_child(count)
		row.add_child(box)
	return row


func _process(_delta: float) -> void:
	if Net.mode == Net.Mode.SERVER:
		set_process(false)  # Nobody sees a dedicated server's pack (decision 469).
		return
	var began := Time.get_ticks_usec()
	if _signature() != _signature_shown:
		_refresh()
	UiCost.add("pack", Time.get_ticks_usec() - began)


func _icon_arrived(_id: String) -> void:
	_icons_seen += 1


## Everything the rows are laid out from: whose, shown or not, the icon
## source and each entity's slots and notes (copies: they change in place
## under replication). Arrays compare by value, so a frame with the same
## signature draws nothing again.
func _signature() -> Array:
	var who := player if is_instance_valid(player) else null
	var opened := other if is_instance_valid(other) else null
	var sig: Array = [who, opened, shown, icons != null, _icons_seen, promised.duplicate(), charges_of(who)]
	if who != null:
		sig.append_array([who.load_arms, who.load_body, World.load_free, World.load_heavy, World.load_overloaded])  # 676: F7's edges, live.
	for entity in [who, opened]:
		if entity != null:
			sig.append(entity.slots.duplicate())
			sig.append(entity.slot_notes.duplicate())
			sig.append(entity.slot_counts.duplicate())  # The badges (619, ui's side).
	return sig


## Shows [param opened]'s row, a chest or a companion (null closes it).
func open(opened: GridEntity) -> void:
	if opened != other and is_instance_valid(other) and sound.is_valid() and SoundKit.closing(other) != "":
		sound.call(SoundKit.closing(other), other)
	other = opened
	_refresh()


## Moves an item, by way of transfer; [param count] units of a stack, 0 for
## all of them (619).
func drop(from: GridEntity, from_slot: int, to: GridEntity, to_slot: int, count := 0) -> void:
	if transfer.is_valid() and is_instance_valid(from) and is_instance_valid(to):
		transfer.call(from, from_slot, to, to_slot, count)


## The corner badge's words for a slot holding [param count] things (619,
## ui's side): the number above one, nothing for one or none (a lone thing
## shows no number, as before).
static func count_words(count: int) -> String:
	return str(count) if count > 1 else ""


## Whether Shift is held, for a one-unit drag; tests set test_shift.
static var test_shift := false
static func shift_down() -> bool:
	return test_shift or Input.is_key_pressed(KEY_SHIFT)


## The badge box [param index] of the open row or the player's shows (tests).
func count_in(mine: bool, index: int) -> String:
	var row := _player_row if mine else _other_row
	var box := row.get_child(index) as SlotBox
	return box.count.text if box.count.visible else ""


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


## The player's slots selected to give in a barter (560): [param indices]
## framed in the selected style, the rest as they were.
func set_selected(indices: Array) -> void:
	selected.clear()
	for index: Variant in indices:
		if int(index) >= 0:
			selected[int(index)] = true
	if _player_row == null:
		return
	for box: SlotBox in _player_row.get_children():
		if selected.has(box.index):
			box.add_theme_stylebox_override("panel", selected_style())
		else:
			box.remove_theme_stylebox_override("panel")


## The frame of a box selected for barter: the inset's backing with a bright
## brass border (the theme's colours).
static func selected_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.color("backing_deep")
	style.border_color = UiTheme.color("brass_bright")
	style.set_border_width_all(4)
	style.set_corner_radius_all(6)
	return style


## The title over the open row ([param mine] false) or the player's.
func title_shown(mine: bool) -> String:
	return (_player_title if mine else _other_title).text


## Her bond's step beside the open row's title (", sullen"; "" at fond or
## for a chest) and the reason its hover gives (555, ui's side).
func mood_shown() -> String:
	return _other_mood.text


func mood_hover() -> String:
	return _other_mood.tooltip_text


func _refresh() -> void:
	if not is_instance_valid(other):
		other = null
	visible = (shown or other != null) and is_instance_valid(player)
	_other_head.visible = other != null
	_other_title.visible = other != null
	_other_row.visible = other != null
	_other_title.text = title_of(other) if other != null else ""
	# 555, ui's side: her bond's step after her name, the reason on hover.
	var mood := Main.bond_shown(str((other as Companion).bond_step)) if other is Companion else ""
	var why := Main.reason_short(str((other as Companion).bond_why)) if other is Companion else ""
	_other_mood.text = ", %s" % mood if not mood.is_empty() else ""
	_other_mood.visible = not mood.is_empty()
	_other_mood.tooltip_text = why
	_other_title.tooltip_text = why
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
			box.note = entity.slot_notes[box.index] if noted else ""
			# A plain thing's note (a bundle's condition) starts with its catalog
			# name; a named one's with its name (decision 375).
			var named := noted and not entity.slot_notes[box.index].begins_with(Items.name_of(item))
			var kept := named and World.KEPT_MARK in entity.slot_notes[box.index]
			box.label.add_theme_color_override("font_color", KEPT_COLOR if kept else NAMED_COLOR if named else Items.color_of(item))
			box.count.text = count_words(World.slot_count(entity, box.index)) if has and not item.is_empty() else ""
			box.count.visible = not box.count.text.is_empty()
			_show_icon(box, icons.icon(item) if icons != null and not item.is_empty() else null)
	if landed != null and sound.is_valid():
		sound.call(SoundKit.opening(landed), landed)
	var lines := load_lines(player) if is_instance_valid(player) else PackedStringArray()
	_weight.text = lines[0] if not lines.is_empty() else ""
	_weight.visible = not _weight.text.is_empty()
	_load.text = "\n".join(lines.slice(1))
	_load.visible = not _load.text.is_empty()
	_promised.text = "Promised: %s" % ", ".join(promised) if not promised.is_empty() else ""
	_promised.visible = not promised.is_empty()
	var held := charges_of(player if is_instance_valid(player) else null)
	_charges.text = charges_words(held[0], held[1])
	_charges.visible = not _charges.text.is_empty()
	_signature_shown = _signature()


## [param who]'s load lines (decision 676, ui's side; physics' numbers,
## replicated): what they carry against their own mass and its band, then
## the arms' and the body's parts and what each slows; none carrying nothing.
static func load_lines(who: GridEntity) -> PackedStringArray:
	var arms := who.load_arms
	var body := who.load_body
	if arms + body <= 0.0:
		return PackedStringArray()
	var lines := PackedStringArray(["carrying %s of %s kg: %s" % [kg_words(arms + body), kg_words(World.load_capacity(who)), World.load_band(who)]])
	if arms > 0.0:
		lines.append(part_words("arms", arms, "slows the draw and the swing", World.arms_load(who)))
	if body > 0.0:
		lines.append(part_words("body", body, "slows the walk and the breath", World.walk_load(who)))
	return lines


## "arms 5.6 kg: slows the draw and the swing (+10%)"; under the free share
## (a multiple of 1) the kg alone: "arms 1.6 kg".
static func part_words(part: String, kilos: float, slows: String, multiple: float) -> String:
	var percent := roundi(snappedf((multiple - 1.0) * 100.0, 0.01))  # x1.025 is +3%, not float's 2.4999.
	if percent <= 0:
		return "%s %s kg" % [part, kg_words(kilos)]
	return "%s %s kg: %s (+%d%%)" % [part, kg_words(kilos), slows, percent]


## Kilograms to a tenth, a whole number without its ".0": "16", "5.6".
static func kg_words(kilos: float) -> String:
	var tenth := snappedf(kilos, 0.1)
	return str(roundi(tenth)) if is_equal_approx(tenth, roundf(tenth)) else str(tenth)


## The pack's line for the resurrection charges (573, ui's side): "charges
## 23 of 50"; "" unblessed (no room yet).
static func charges_words(charges: int, room: int) -> String:
	return "charges %d of %d" % [charges, room] if room > 0 else ""


## [param who]'s replicated charges and room, read by name ([charges,
## room]; [0, 0] for nobody or a body without them).
static func charges_of(who: GridEntity) -> Array[int]:
	if who == null:
		return [0, 0]
	var charges: Variant = who.get("charges")
	var room: Variant = who.get("charge_room")
	return [int(charges) if charges is int else 0, int(room) if room is int else 0]


## The charges line shown (tests).
func charges_shown() -> String:
	return _charges.text if _charges.visible else ""


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
