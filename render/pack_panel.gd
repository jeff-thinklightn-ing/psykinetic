class_name PackPanel
extends UiGlass
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
## The theme's caption size: a chip's number, a store square's name with no icon.
static var CAPTION_SIZE: int = UiTheme.size("caption")
## Room round an icon in its box (765: no caption under it; the name on hover).
## Jeff: the items too small in their squares; 3 (8 before).
const ICON_INSET := 3
## A named thing's caption (decision 365): the theme's brass_bright.
static var NAMED_COLOR: Color = UiTheme.color("brass_bright")
## One kept from its namer (World.KEPT_MARK; decision 370): rust.
static var KEPT_COLOR: Color = UiTheme.color("rust")

## The close mark pressed (Main closes as Esc does: a chest or the companion's pack, else the pack).
signal close_pressed

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
## Shown without anything else open (I). Closed at join (787 amended (3), the window rules' rule 7).
var shown := false:
	set(value):
		shown = value
		if is_node_ready():
			_refresh()

## The barter window's hooks (BarterPanel, 560): a left click on one of the
## player's boxes goes to select_hook(mine, index) first (true: taken, no
## drag); the mouse over one, or off (index -1), to hover_hook; the slots
## selected to give are framed (set_selected) and never dragged.
var select_hook: Callable
## A double-click on a box (decision 722): called (mine, index); Main
## equips, deposits or withdraws.
var double_click: Callable
## The personal chest's "Deposit unequipped" button (722): Main sends deposit_all.
var deposit_all: Callable
var hover_hook: Callable
var selected: Dictionary = {}
## While a store is open (765): what its seller pays for the thing in each
## of the player's slots, a chip over the square's top-right corner; 0 for
## won't buy, the thing dimmed. Empty: no chips.
var prices: Dictionary = {}
## Each art's [peak, fading] as combat's owner-only "arts" message last
## told it (766 amended), {} before it comes: the practice bars' notch and
## dimming.
var art_marks: Dictionary = {}
## While a store is open (765): the pack shows though hidden (I), the store
## window beside it.
var held_open := false:
	set(value):
		if value == held_open:
			return
		held_open = value
		if is_node_ready():
			_refresh()

## 852: the store window owns the pack while it is open: the pack and sheet are not
## drawn (they come back as they were when it closes).
var suppressed := false:
	set(value):
		if value == suppressed:
			return
		suppressed = value
		if is_node_ready():
			_refresh()

var _other_title: Label
## The open row's title and, for a companion, her bond's step beside it
## (555, ui's side): ", sullen" dim, nothing at fond; hover: her reason.
var _other_head: HBoxContainer
var _other_mood: Label
var _other_row: HBoxContainer
var _player_title: Label
## The close mark at the head's right end (UiClose; Esc does the same).
var _close: UiClose
var _player_row: HBoxContainer
## The character sheet (787), the window's left side since the sheet pass:
## the player's hands, armour and worn things on a figure, the load drawn.
var sheet: CharacterSheet
## The player's load lines as last shown (676, ui's side; since 787 the
## sheet's bar's hover words).
var _load_lines := PackedStringArray()
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
## The foot line (UiLine): a refused move says why in rust until the next move; nothing on success.
var _foot: UiLine
## The square the last drag, double click or right click acted on, and when (msec): the "Server" party line that
## answers within ACT_WAIT_MSEC is its refusal (no protocol change: the server sends no square).
var _acted := {"mine": true, "index": -1, "at": -100000}
const ACT_WAIT_MSEC := 1500
## The resurrection charges the player holds, "charges 23 of 50" (dungeon's
## 573: Player.charges and charge_room, replicated; shown once blessed,
## charge_room over 0; no bar).
var _charges: Label
## The hover tip, a sibling above the panel (made on the first hover).
var tip: ItemTip
## Who in the player's town takes what (Main.takers_here, 802 amended (5)):
## the tip of a thing in the player's own pack says who ("For the smith").
static var takers: Dictionary = {}
## Each row's entity and contents as last shown: an item new in a slot is
## one that landed there.
var _last: Dictionary[HBoxContainer, Array] = {}


## One slot's box. Dragged from when it holds something; dropped on always.
## Weapon memory on a square (766, ui's side; the coordinator's approval of
## C:/dev/review/weapon_memory): a thin bar along the bottom filled to the
## art's memory (Player.art_feel, 0..1); its peak a faint notch past the
## fill and the fill dimmed while the art cools (combat's owner-only "arts"
## message, 766 amended, when it comes). No words.
class PracticeBar:
	extends Control
	var fill := 0.0
	var peak := 0.0
	var fading := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		offset_left = 10
		offset_right = -10
		offset_top = -18
		offset_bottom = -9
		visible = false

	func _draw() -> void:
		var whole := Rect2(Vector2.ZERO, size)
		draw_rect(whole, Color(0.1, 0.08, 0.06, 0.85))
		var inner := whole.grow(-2)
		if fill > 0.0:
			var brass := UiTheme.color("brass")
			draw_rect(Rect2(inner.position, Vector2(inner.size.x * clampf(fill, 0.0, 1.0), inner.size.y)),
				brass.darkened(0.55) if fading else brass)
		if peak > fill + 0.01:
			var x := inner.position.x + inner.size.x * clampf(peak, 0.0, 1.0)
			draw_line(Vector2(x, -3), Vector2(x, size.y + 1), UiTheme.color("text_dim"), 3.0)


class SlotBox:
	extends UiSlot
	var panel: PackPanel
	var mine := true
	var index := 0
	## The no-picture name over the picture (a Label in the square's face), the picture (UiSlot's own).
	var label: Label
	var icon: TextureRect
	## The slot's note (World._show_notes), for the tip.
	var note := ""
	## A named thing's frame colour (365: brass_bright; kept, rust), clear for a
	## plain one: the gilding the caption carried before 765.
	var gild := Color(0, 0, 0, 0)
	## The stack's count in the corner (619, ui's side): "5", nothing alone (UiSlot's own label).
	var count: Label
	## What an open store's seller pays for it (765): gold, -1 for no chip (UiSlot's UiPrice at the corner).
	var price_gold := -1
	## A hand's square keeps a brass rim (the mock: the two hands).
	var hand := false
	## Weapon memory (766, ui's side): the art's practice along its bottom.
	var practice: PracticeBar
	## Shown but not to be changed (787: another's companion on the sheet):
	## no drag from it or onto it, no click's equip or use; the tip still shows.
	var read_only := false

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
		if read_only or not is_instance_valid(entity) or index >= entity.slots.size() or entity.slots[index].is_empty():
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
		if read_only:
			return
		# Taken now: what a click does can rebuild these squares, this one out of the tree,
		# and accept_event() then marks nothing, so the press walked (Jeff on v0.1.202).
		var viewport := get_viewport()
		var click := event as InputEventMouseButton
		# The barter window open (560): a left click selects the thing to give.
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT and panel.select_hook.is_valid() \
				and panel.select_hook.call(mine, index, click.shift_pressed):
			viewport.set_input_as_handled()
			return
		# 722: a double-click equips, or with a chest open deposits or withdraws.
		if click != null and click.pressed and click.double_click and click.button_index == MOUSE_BUTTON_LEFT \
				and panel.double_click.is_valid():
			var entity_clicked := owner_entity()
			if is_instance_valid(entity_clicked) and index < entity_clicked.slots.size() and not entity_clicked.slots[index].is_empty():
				panel.acted(mine, index)
				panel.double_click.call(mine, index)
				viewport.set_input_as_handled()
				return
		if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_RIGHT or not mine:
			return
		var entity := owner_entity()
		if is_instance_valid(entity) and index < entity.slots.size() and not entity.slots[index].is_empty() and panel.use.is_valid():
			panel.acted(mine, index)
			panel.use.call(index)
			viewport.set_input_as_handled()

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return not read_only and data is Dictionary and data.has("slots_of") and is_instance_valid(owner_entity())

	func _drop_data(_at: Vector2, data: Variant) -> void:
		panel.drop(data["slots_of"], int(data["slot"]), owner_entity(), index, int(data.get("count", 0)))


## A companion's row, "Wren's gear and pack" (787 amended (4): it shows her worn slots and her carried ones
## under this one title; the player's own are headed Gear and Pack); a chest is "Chest", or its own name where
## it has one (787 amended (5), title_name).
static func title_of(entity: GridEntity) -> String:
	if entity is Locker:
		return "Your chest"  # Decision 722: the same 48 at every town's locker.
	if entity is Chest:
		var named := title_name(String(entity.name))
		return named if not named.is_empty() else "Chest"
	if entity is Cargo:
		return "Cart" if entity.capacity > Chest.SLOTS else "Crate"
	var who := entity.label if not entity.label.is_empty() else String(entity.name)
	return "%s's gear and pack" % who


## A chest's own name as its window's title: [param name] stripped, when it begins with a capital
## and holds only letters, spaces, apostrophes and hyphens ("Runner's pack", "Offering stone");
## "" for any other (a working name such as "Chest1" or "KitChest2", a lowercase tag, an id), which
## the window then titles "Chest". A name voice has not read stays out of a title (voice's page
## mirrors this rule in tools/voice_inventory.py and names tests/chest_test.gd's _test_chest_titles).
static func title_name(name: String) -> String:
	var trimmed := name.strip_edges()
	if trimmed.is_empty():
		return ""
	var first := trimmed.substr(0, 1)
	if first.to_upper() != first or first.to_lower() == first:
		return ""
	for i in range(1, trimmed.length()):
		var letter := trimmed.substr(i, 1)
		if letter.to_upper() == letter.to_lower() and letter not in [" ", "'", "’", "-"]:
			return ""
	return trimmed


func _ready() -> void:
	super()  # UiGlass: the frost and its group.
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
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_other_head.add_child(spacer)
	var deposit := Button.new()
	deposit.name = "Deposit"
	deposit.text = "Deposit unequipped"
	deposit.tooltip_text = "Everything in your pack (not your hands or armour) into your chest"
	deposit.focus_mode = Control.FOCUS_NONE
	deposit.visible = false
	deposit.pressed.connect(func() -> void:
		if deposit_all.is_valid():
			deposit_all.call())
	_other_head.add_child(deposit)
	_other_row = _row(false)
	column.add_child(_other_row)
	# One window (the coordinator's sheet pass, Jeff: "keep iterating"): the
	# character sheet on the left, the pack on the right, their titles on one
	# row, the same squares.
	var mine := HBoxContainer.new()
	mine.name = "Mine"
	mine.add_theme_constant_override("separation", UiTheme.constant("slot_gap") * 4)
	column.add_child(mine)
	sheet = CharacterSheet.new()
	sheet.build(self)
	mine.add_child(sheet)
	var pack_side := VBoxContainer.new()
	pack_side.add_theme_constant_override("separation", UiTheme.constant("row"))
	pack_side.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mine.add_child(pack_side)
	var pack_head := HBoxContainer.new()  # The title, the gold at its right end (ShopPanel), the close mark (pack-1080).
	pack_side.add_child(pack_head)
	_player_title = _title()
	_player_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pack_head.add_child(_player_title)
	_close = UiClose.new()
	_close.pressed.connect(func() -> void: close_pressed.emit())
	pack_head.add_child(_close)
	# The two titles and the close mark on one row: both titles as tall as the mark, their words centred on it (pack-1080).
	var head_side := float(_close.get_theme_constant(&"size", &"Close"))
	for head: Label in [_player_title, sheet.title]:
		head.custom_minimum_size.y = head_side
		head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_player_row = _row(true)
	pack_side.add_child(_player_row)
	_promised = Label.new()
	_promised.theme_type_variation = &"Caption"
	_promised.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_promised.add_theme_color_override("font_color", UiTheme.color("brass"))
	column.add_child(_promised)
	_charges = Label.new()
	_charges.theme_type_variation = &"Caption"
	_charges.add_theme_color_override("font_color", UiTheme.color("text_dim"))
	column.add_child(_charges)
	_foot = UiLine.new()  # The foot: empty until a move is refused (the approved window).
	column.add_child(_foot)
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
	var taker := ""
	if entity is Player and (entity as Player).owner_peer == Net.local_id and Items.is_pack(box.index):
		taker = Main.taker_line(takers, str(entity.slots[box.index]))
	tip.show_for(entity.slots[box.index], box.note, box.get_global_rect().position, taker)


func hide_tip() -> void:
	if tip != null:
		tip.visible = false


## "carrying 21.6 of 80 kg: burdened" for the player's load (tests; the
## sheet's body bar says it on hover, 787).
func weight_shown() -> String:
	return _load_lines[0] if not _load_lines.is_empty() else ""


## The arms' and the body's lines, one a line (tests).
func load_shown() -> String:
	return "\n".join(_load_lines.slice(1))


func _title() -> Label:
	var title := Label.new()
	title.theme_type_variation = &"Title"
	return title


## A row's layout for [param entity] (decision 722, ui's side): "carrier"
## (a player's or a companion's Items.CARRIED: the pack's twelve in a 4 x 3
## grid, the hands and the armour beside), "locker" (a personal chest's 48,
## LOCKER_COLUMNS a line) or "line:<n>" (a chest, crate or cart, one line).
static func layout_of(entity: GridEntity) -> String:
	if entity == null or entity.slots.size() == Items.CARRIED:
		return "carrier"
	if entity is Locker:
		return "locker"
	return "line:%d" % entity.slots.size()


## A personal chest's boxes a line.
const LOCKER_COLUMNS := 12
## The pack's grid, boxes a line (4 x 3: decision 722, 819).
const PACK_COLUMNS := 4


func _row(mine: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.constant("slot_gap") * 4)
	_lay_out(row, mine, "carrier")
	return row


## [param row]'s boxes made again for [param layout] (layout_of), if it
## changed; the boxes in GridContainers, each its slot's index.
func _lay_out(row: HBoxContainer, mine: bool, layout: String) -> void:
	if row.get_meta(&"layout", "") == layout:
		return
	row.set_meta(&"layout", layout)
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	var gap := UiTheme.constant("slot_gap")
	var grids: Array[Array] = []  # [columns, indices]
	if layout == "carrier":
		grids.append([PACK_COLUMNS, Items.ALL_PACK_SLOTS])  # 3 x 4 (819).
		if not mine:  # The player's hands and armour are on the sheet (787).
			grids.append([2, [Items.RIGHT_HAND, Items.LEFT_HAND, Items.ARMOUR]])
	elif layout == "locker":
		grids.append([LOCKER_COLUMNS, range(Locker.LOCKER_SLOTS)])
	else:
		var n := maxi(layout.get_slice(":", 1).to_int(), 1)
		grids.append([n, range(n)])
	for each: Array in grids:
		var grid := GridContainer.new()
		grid.columns = int(each[0])
		grid.add_theme_constant_override("h_separation", gap)
		grid.add_theme_constant_override("v_separation", gap)
		grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		for i: int in each[1]:
			grid.add_child(_box(mine, i, layout == "carrier" and not Items.is_pack(i)))
		row.add_child(grid)


## The pack's rect and the sheet's beside it (787): what a window placed
## beside the pack keeps clear of.
func flank_rect() -> Rect2:
	var rect := get_global_rect()
	if is_instance_valid(sheet) and sheet.visible and sheet.is_inside_tree():
		rect = rect.merge(sheet.get_global_rect())
	return rect


## Where a window of [param window_size] goes beside the pack (the store's,
## 765; the shop's, 280): left of the sheet, its foot level with theirs; when
## that runs off the screen's left, above them, its right edge on the pack's.
func beside(window_size: Vector2, gap: float) -> Vector2:
	var rect := flank_rect()
	var margin := float(UiTheme.constant("margin"))
	var at := Vector2(rect.position.x - window_size.x - gap, rect.end.y - window_size.y)
	if at.x < margin:
		at = Vector2(rect.end.x - window_size.x, maxf(rect.position.y - window_size.y - gap * 4, margin))
	return at


## The boxes of [param row], in no set order.
static func boxes_of(row: HBoxContainer) -> Array[SlotBox]:
	var out: Array[SlotBox] = []
	for grid in row.get_children():
		for box in grid.get_children():
			if box is SlotBox and not box.is_queued_for_deletion():
				out.append(box)
	return out


## [param row]'s boxes; the player's with the sheet's three (787).
func row_boxes(row: HBoxContainer) -> Array[SlotBox]:
	var out := boxes_of(row)
	if row == _player_row and sheet != null:
		out.append_array(sheet.boxes.values())
	return out


## The box for slot [param index] in the open row ([param mine] false) or
## the player's, or null.
func box_in(mine: bool, index: int) -> SlotBox:
	for box in row_boxes(_player_row if mine else _other_row):
		if box.index == index:
			return box
	return null


## ui-design's reserved rect for the bottom-right windows (the HUD's rects, 11-11): 2128, 1056, 1672 x 1064 in the HUD's 3840 x 2160
## units, read from [param screen]'s own bottom-right corner as the pack is anchored. The person window docks left of it.
static func reserved_rect(screen: Rect2) -> Rect2:
	return Rect2(Vector2(2128.0, 1056.0) + (screen.end - Vector2(3840.0, 2160.0)), Vector2(1672.0, 1064.0))


## The pack's title's rect on screen ("Pack"), the gold at its right end
## (ShopPanel).
func pack_title_rect() -> Rect2:
	return _player_title.get_global_rect()


## What an empty worn square shows, faint and grey (the approved mock, 854 amended (7)): the item's own picture.
const EMPTY_PICTURES := {Items.HEAD: "felt_hat", Items.NECK: "encolpion_amulet", Items.BACK: "cloak",
	Items.ARMOUR: "leather_armour", Items.RIGHT_HAND: "sword", Items.LEFT_HAND: "shield", Items.RING_1: "signet_ring",
	Items.RING_2: "signet_ring", Items.CHARM: "bear_claw_charm", Items.FEET: "soft_boots", Items.BAG: "satchel"}


func _box(mine: bool, i: int, hand: bool) -> SlotBox:
	var box := SlotBox.new()
	box.panel = self
	box.mine = mine
	box.index = i
	box.hand = hand
	# The shared square (UiSlot, ui-design's parts): its size, picture, count, chip and rim states.
	# On the sheet no letters (the sheet pass): a worn square's name on hover while empty. A
	# companion's hands and armour, beside her pack, keep R, L, A.
	if hand and not mine and i in [Items.RIGHT_HAND, Items.LEFT_HAND, Items.ARMOUR]:
		var mark := Label.new()
		mark.text = "R" if i == Items.RIGHT_HAND else "L" if i == Items.LEFT_HAND else "A"  # The armour worn (622).
		mark.theme_type_variation = &"Small"
		mark.add_theme_color_override("font_color", UiTheme.color("brass"))
		mark.position = Vector2(10, 4)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(mark)
	box.icon = box._picture
	box.count = box._count
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	box.label = label
	box._face.add_child(label)
	if mine:
		box.practice = PracticeBar.new()
		box._face.add_child(box.practice)
	if hand:
		_frame(box)
	return box


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


## [param box]'s practice bar (766, ui's side): shown on the player's own
## square holding a weapon with an art (World.ARTS) once that art has any
## memory; its peak and cooling from art_marks.
func _show_practice(box: SlotBox, entity: GridEntity, item: String) -> void:
	var art := str(World.ARTS.get(item, ""))
	var feel: Dictionary = (entity as Player).art_feel if is_instance_valid(entity) and entity is Player else {}
	var fill := float(feel.get(art, 0.0)) if not art.is_empty() else 0.0
	var marks: Variant = art_marks.get(art, [])
	var peak := float(marks[0]) if marks is Array and (marks as Array).size() >= 2 else fill
	var fading := bool(marks[1]) if marks is Array and (marks as Array).size() >= 2 else false
	box.practice.visible = fill > 0.0
	if box.practice.fill != fill or box.practice.peak != peak or box.practice.fading != fading:
		box.practice.fill = fill
		box.practice.peak = peak
		box.practice.fading = fading
		box.practice.queue_redraw()


## A square's practice as shown (tests): [fill, peak, fading], [] for none.
func practice_shown(index: int) -> Array:
	var box := box_in(true, index)
	if box == null or box.practice == null or not box.practice.visible:
		return []
	return [box.practice.fill, box.practice.peak, box.practice.fading]


## Everything the rows are laid out from: whose, shown or not, the icon
## source and each entity's slots and notes (copies: they change in place
## under replication). Arrays compare by value, so a frame with the same
## signature draws nothing again.
func _signature() -> Array:
	var who := player if is_instance_valid(player) else null
	var opened := other if is_instance_valid(other) else null
	var sig: Array = [who, opened, shown, held_open, prices.duplicate(), icons != null, _icons_seen, promised.duplicate(), charges_of(who)]
	if who != null:
		sig.append_array([who.load_arms, who.load_body, World.load_free, World.load_heavy, World.load_overloaded])  # 676: F7's edges, live.
	for entity in [who, opened]:
		if entity != null:
			sig.append(entity.slots.duplicate())
			sig.append(entity.slot_notes.duplicate())
			sig.append(entity.slot_counts.duplicate())  # The badges (619, ui's side).
	if who is Player:
		sig.append((who as Player).art_feel.duplicate())  # The practice bars (766).
		sig.append(art_marks.duplicate())
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
	acted(to == player, to_slot)
	if transfer.is_valid() and is_instance_valid(from) and is_instance_valid(to):
		transfer.call(from, from_slot, to, to_slot, count)


## A move was started on square [param index] of the player's row ([param mine]) or the open row: the foot clears,
## and a refusal that answers within ACT_WAIT_MSEC is said in it (refuse_words).
func acted(mine: bool, index: int) -> void:
	_acted = {"mine": mine, "index": index, "at": Time.get_ticks_msec()}
	if _foot != null:
		_foot.clear()


## The server's "Server" party line [param words] while a move is waiting for its answer: said in the foot in rust,
## the acted-on square's rim flashing; true when taken (the move was just made), false for any other line.
func refuse_words(words: String) -> bool:
	if _foot == null or int(_acted["index"]) < 0 or Time.get_ticks_msec() - int(_acted["at"]) > ACT_WAIT_MSEC:
		return false
	_foot.refuse(words)
	var box := box_in(bool(_acted["mine"]), int(_acted["index"]))
	if box != null:
		box.flash_refused()
	_acted["index"] = -1
	return true


## The foot as shown (tests): the words and whether it is a refusal.
func foot_shown() -> String:
	return _foot.text.strip_edges() if _foot != null else ""


func foot_is_refused() -> bool:
	return _foot != null and _foot.refused


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
	var box := box_in(mine, index)
	return box.count.text if box != null and box.count.visible else ""


## What box [param index] of the open row ([param mine] false) or the
## player's shows: the item's short name, "" for empty.
func shown_in(mine: bool, index: int) -> String:
	var box := box_in(mine, index)
	return box.label.text if box != null else ""


## The icon box [param index] of the open row or the player's shows, or
## null (names only).
func icon_in(mine: bool, index: int) -> Texture2D:
	var box := box_in(mine, index)
	return box.icon.texture if box != null else null


## The player's slots selected to give in a barter (560): [param indices]
## framed in the selected style, the rest as they were.
func set_selected(indices: Array) -> void:
	selected.clear()
	for index: Variant in indices:
		if int(index) >= 0:
			selected[int(index)] = true
	if _player_row == null:
		return
	for box: SlotBox in row_boxes(_player_row):
		_frame(box)


## [param box]'s frame: picked for a barter, the bright frame; else a named
## thing's thin gilt (or a kept one's rust, 765: the caption that carried it
## is gone); else the theme's.
func _frame(box: SlotBox) -> void:
	if box.mine and selected.has(box.index):
		box.remove_theme_stylebox_override("panel")
		box.set_state("picked")  # UiSlot's brass rim: picked to give.
		return
	if box.state == "picked":
		box.set_state("hand" if box.hand else "rest")
	elif box.state in UiSlot.RESTING:
		box.set_state("hand" if box.hand else "rest")  # A held hand's square: the theme's WellHand (854 amended (6)).
	if box.gild.a > 0.0:
		var style := selected_style()
		style.border_color = box.gild
		style.set_border_width_all(2)
		box.add_theme_stylebox_override("panel", style)
	else:
		box.remove_theme_stylebox_override("panel")


## [param box]'s frame colour as shown (tests): the gilt, clear for none.
func gild_shown(mine: bool, index: int) -> Color:
	var box := box_in(mine, index)
	return box.gild if box != null else Color(0, 0, 0, 0)


## An open store's prices for the player's slots (765): [param by_slot]
## {slot: gold}, 0 for won't buy; {} for none (the store closed).
func set_prices(by_slot: Dictionary) -> void:
	if by_slot == prices:
		return
	prices = by_slot.duplicate()
	if is_node_ready():
		_refresh()


## [param box]'s price chip while a store is open and it holds a thing
## ([param held]): the seller's price over its top-right corner, the thing
## dimmed when they won't buy it; none otherwise.
func _show_price(box: SlotBox, held: bool) -> void:
	var gold := int(prices.get(box.index, -1)) if held and not prices.is_empty() else -1
	box.icon.modulate.a = 0.4 if gold == 0 else 1.0
	if gold != box.price_gold:
		box.price_gold = gold if gold > 0 else -1
		if box.price_gold > 0:
			box.price().set_gold(box.price_gold)  # UiSlot's chip at the corner.
		else:
			box.clear_price()


## The price chips shown over the player's slots (tests): {slot: gold}.
func prices_shown() -> Dictionary:
	var out := {}
	if _player_row != null:
		for box: SlotBox in row_boxes(_player_row):
			if box.price_gold > 0:
				out[box.index] = box.price_gold
	return out


## The frame of a box selected for barter: the inset's backing with a bright
## brass border (the theme's colours).
static func selected_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.color("slot")
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
	visible = (shown or other != null or held_open) and is_instance_valid(player) and not suppressed
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
	# 787: the pack is "Pack" (voice), the player's name heads the sheet.
	_player_title.text = "Pack" if is_instance_valid(player) else ""
	var landed: GridEntity = null
	_lay_out(_other_row, false, layout_of(other))
	_other_head.get_node(^"Deposit").visible = other is Locker
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
		for box: SlotBox in row_boxes(row):
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
			var gild := KEPT_COLOR if kept else NAMED_COLOR if named else Color(0, 0, 0, 0)
			if gild != box.gild:
				box.gild = gild
				_frame(box)
			box.count.text = count_words(World.slot_count(entity, box.index)) if has and not item.is_empty() else ""
			box.count.visible = not box.count.text.is_empty()
			_show_icon(box, icons.icon(item) if icons != null and not item.is_empty() else null)
			if EMPTY_PICTURES.has(box.index) and icons != null:
				box.set_empty_picture(icons.icon(str(EMPTY_PICTURES[box.index])))  # What goes in a worn square, faint while empty.
			_show_price(box, row == _player_row and has and not item.is_empty())
			if box.practice != null:
				_show_practice(box, entity if has else null, item)
	if sheet != null and is_instance_valid(player) and sheet.boxes.has(Items.BAG):
		# The satchel's square shows only while one is worn: its package is off (nothing sells or drops one yet),
		# so an empty square would read as a place to fill (the coordinator).
		sheet.boxes[Items.BAG].visible = player.slots.size() > Items.BAG and not player.slots[Items.BAG].is_empty()
	if landed != null and sound.is_valid():
		sound.call(SoundKit.opening(landed), landed)
	var lines := load_lines(player) if is_instance_valid(player) else PackedStringArray()
	_load_lines = lines
	# The sheet (787), the pack's left side: the load drawn, the empty squares named.
	if sheet != null and visible:
		sheet.show_for(player, lines)
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


## [param picture] in [param box], filling it, its name on hover alone
## (765, Jeff: the pack's squares as the store's, no caption); null: the
## name in the middle (headless, or the icon not drawn yet).
func _show_icon(box: SlotBox, picture: Texture2D) -> void:
	if box.icon.texture == picture:
		return
	box.set_picture(picture)  # Shows and hides the faint empty picture under it (854 amended (7)).
	box.label.visible = picture == null
	box.label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER if picture == null else VERTICAL_ALIGNMENT_BOTTOM
	box.label.add_theme_font_size_override("font_size", FONT_SIZE if picture == null else CAPTION_SIZE)
	box.label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if picture == null else TextServer.AUTOWRAP_OFF
	box.label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING if picture == null else TextServer.OVERRUN_TRIM_ELLIPSIS
	box.label.clip_text = picture != null
