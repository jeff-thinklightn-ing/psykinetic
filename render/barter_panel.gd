class_name BarterPanel
extends Control
## The barter window (decision 560, ui's side; Jeff, 2026-10-21: "the window
## should show the npc's inventory of goods, next your pack, hovering over
## an item would show what the npc will pay in gold, or what they'll take in
## gold... click to select what you want to trade, it would show a sum in
## the bottom... the button changes to +sword -hide +10g = Confirm"). The
## merchant's goods as a row of slot boxes in the pack's look, beside the
## pack; the pack's own boxes are the player's side (PackPanel's select and
## hover hooks). Hover: "takes 10 gold" over theirs, "pays 20 gold" (or
## "pays 5 gold, fenced", or "won't buy") over the player's. A click selects
## on either side, a second unselects; the foot's one button reads the sum
## from the player's side, "+sword -hide +10g = Confirm", and sends
## economy's "trade" command (trade_asked; Main sends it). The server
## prices the trade and answers with the barter message again
## (show_barter), a refusal's why under the foot in rust (refused: Main's
## error sound). Economy's wire (560, economy's side; 562: the trade is
## with a person, "resident" in place of "shop"): "barter" {resident,
## town, gold, goods: [{uid, id, price}], buys: {id: {gold, up_to}},
## fenced: {uid: gold}, pack: [{slot, uid, id}], why}; "trade" {resident,
## give: [uids], take: [uids], gold}. In the shared theme's look (UiTheme,
## docs/ui_style.md); sizes in the HUD's 3840 x 2160 units.

const GAP := 20
const ROW_WIDTH := 1100.0
## The theme's: a price in brass, gold going out and a refusal in rust,
## the hover's words dim, a selected box's frame in bright brass.
static var PRICE: Color = UiTheme.color("brass")
static var OUT: Color = UiTheme.color("rust")
static var DIM: Color = UiTheme.color("text_dim")
static var SELECT: Color = UiTheme.color("brass_bright")

## Confirm: the trade for Main to send ([param gold] signed from the
## player's side, positive when they receive).
signal trade_asked(with: GridEntity, give: Array, take: Array, gold: int)
## The server refused the trade: [param why].
signal refused(why: String)

## The pack panel the window sits beside (its boxes are the player's side).
var pack: PackPanel
## What is traded at or with: the shop's counter (560, a Chest; the town's
## shop, the merchant's) or a maker in person (562, a Resident; their own
## make, the message's "resident"); null closed, or a test's sample.
var with: GridEntity
## Who fronts it, for the title ("Snagfin's shop", "Oda's goods"); "" for
## "The shop".
var merchant := ""
## The barter message as last received.
var data: Dictionary = {}
## Selected: the player's uids to give, the shop's uids to take.
var give: Dictionary = {}
var take: Dictionary = {}

var _open := false
var _box: PanelContainer
var _title: Label
var _goods: HBoxContainer
var _hover: Label
var _foot: Label
var _button: Button
var _why: Label
var _hover_words := ""


## One of the merchant's things: a box in the pack's look, clicked to
## select, hovered for its price.
class GoodBox:
	extends Panel
	var window: BarterPanel
	var uid := 0
	var id := ""
	var label: Label
	var icon: TextureRect

	func _ready() -> void:
		mouse_entered.connect(func() -> void: window._hover_theirs(uid))
		mouse_exited.connect(func() -> void: window._hover_none())

	func _gui_input(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			window.toggle_take(uid)
			accept_event()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = PanelContainer.new()
	_box.visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiTheme.constant("row"))
	_box.add_child(column)
	_title = Label.new()
	_title.theme_type_variation = &"Heading"
	column.add_child(_title)
	_goods = HBoxContainer.new()
	_goods.add_theme_constant_override("separation", UiTheme.constant("slot_gap"))
	column.add_child(_goods)
	_hover = Label.new()
	_hover.theme_type_variation = &"Caption"
	_hover.add_theme_color_override("font_color", DIM)
	_hover.custom_minimum_size.x = ROW_WIDTH
	column.add_child(_hover)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", UiTheme.constant("row"))
	column.add_child(foot)
	_button = Button.new()
	_button.focus_mode = Control.FOCUS_NONE
	_button.pressed.connect(_confirm)
	foot.add_child(_button)
	_foot = Label.new()
	_foot.theme_type_variation = &"Caption"
	_foot.add_theme_color_override("font_color", OUT)
	_foot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_foot)
	_why = Label.new()
	_why.add_theme_color_override("font_color", OUT)
	_why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_why.custom_minimum_size.x = ROW_WIDTH
	column.add_child(_why)
	add_child(_box)
	if pack != null:
		pack.select_hook = _select_mine
		pack.hover_hook = _hover_mine
	_rebuild()


## Opens the window for a trade with [param person] (their name [param
## who]); the goods come with the server's barter message (Main sends the
## "barter" command).
func open(person: GridEntity, who := "") -> void:
	if person != with:
		data = {}
	with = person
	merchant = who
	give.clear()
	take.clear()
	_open = true
	_hover_words = ""
	_rebuild()


func close() -> void:
	_open = false
	with = null
	give.clear()
	take.clear()
	data = {}
	_hover_words = ""
	_rebuild()


func is_open() -> bool:
	return _open


## The server's barter message: for the person open (its "resident" path,
## or 560's "shop" until economy retires it; a sample names neither, tests
## and shots); a selection of something gone is dropped; a refusal's why
## shown and said (refused).
func show_barter(given: Dictionary) -> void:
	if not _open:
		return
	if is_instance_valid(with) and with.is_inside_tree() and not for_path(given, str(with.get_path())):
		return
	data = given
	for uid: Variant in take.keys():
		if not goods_have(int(uid)):
			take.erase(uid)
	for uid: Variant in give.keys():
		if pack_entry(int(uid)).is_empty():
			give.erase(uid)
	var why := str(data.get("why", ""))
	if not why.is_empty():
		refused.emit(why)
	_rebuild()


## Whether a barter message [param given] is for [param path] (the person
## traded with, or 560's counter): its "resident", else its "shop", else
## nobody named (a sample).
static func for_path(given: Dictionary, path: String) -> bool:
	var named := str(given.get("resident", ""))
	if named.is_empty():
		named = str(given.get("shop", ""))
	return named.is_empty() or named == path


## The window's title: the shop's at a counter ("Snagfin's shop", "The
## shop"), a maker's own goods in person ("Oda's goods").
static func title_words(who: String, in_person: bool) -> String:
	if in_person:
		return "%s's goods" % who if not who.is_empty() else "Their goods"
	return "%s's shop" % who if not who.is_empty() else "The shop"


## The words where the goods would be when [param given] has none:
## "nothing to trade" when they buy nothing either (a maker with a bare
## shelf who needs nothing now, 562), else "nothing for sale".
static func empty_words(given: Dictionary) -> String:
	var buys: Variant = given.get("buys", {})
	return "nothing for sale" if buys is Dictionary and not buys.is_empty() else "nothing to trade"


## Whether the merchant still has [param uid] for sale.
func goods_have(uid: int) -> bool:
	for each: Variant in data.get("goods", []):
		if each is Dictionary and int(each.get("uid", 0)) == uid:
			return true
	return false


## The goods entry for [param uid], {} for none.
func goods_entry(uid: int) -> Dictionary:
	for each: Variant in data.get("goods", []):
		if each is Dictionary and int(each.get("uid", 0)) == uid:
			return each
	return {}


## The player's pack entry {slot, uid, id} for [param uid], {} for none.
func pack_entry(uid: int) -> Dictionary:
	for each: Variant in data.get("pack", []):
		if each is Dictionary and int(each.get("uid", 0)) == uid:
			return each
	return {}


## The player's pack entry at [param slot], {} for an empty one.
func pack_entry_at(slot: int) -> Dictionary:
	for each: Variant in data.get("pack", []):
		if each is Dictionary and int(each.get("slot", -1)) == slot:
			return each
	return {}


## What the merchant pays for the player's [param uid]: the fenced half when
## it is grave goods, else the town's price for its kind; 0 when they won't
## buy it.
func pays_for(uid: int) -> int:
	var fenced: Variant = data.get("fenced", {})
	if fenced is Dictionary and fenced.has(uid):
		return int(fenced[uid])
	if fenced is Dictionary and fenced.has(str(uid)):
		return int(fenced[str(uid)])
	var entry := pack_entry(uid)
	var buys: Variant = data.get("buys", {})
	if entry.is_empty() or not buys is Dictionary or not buys.has(entry.get("id", "")):
		return 0
	var row: Variant = buys[entry["id"]]
	return int(row.get("gold", 0)) if row is Dictionary else int(row)


## Whether the player's [param uid] is bought fenced (grave goods, 555).
func is_fenced(uid: int) -> bool:
	var fenced: Variant = data.get("fenced", {})
	return fenced is Dictionary and (fenced.has(uid) or fenced.has(str(uid)))


## How many of [param id] the town takes before it has enough (buys'
## up_to), a large number when it does not say.
func up_to(id: String) -> int:
	var buys: Variant = data.get("buys", {})
	if not buys is Dictionary or not buys.has(id):
		return 0
	var row: Variant = buys[id]
	return int(row.get("up_to", 1000000)) if row is Dictionary else 1000000


## The signed balance from the player's side for [param gives] and [param
## takes] (uids): what the merchant pays less what they ask, so positive
## when the player receives gold.
func balance_of(gives: Array, takes: Array) -> int:
	var sum := 0
	for uid: Variant in gives:
		sum += pays_for(int(uid))
	for uid: Variant in takes:
		sum -= int(goods_entry(int(uid)).get("price", 0))
	return sum


## The sum's words, Jeff's form: "+sword -hide +10g" (what the player
## takes with +, what they give with -, the gold they receive or pay);
## "" for nothing selected.
static func sum_words(takes: Array, gives: Array, gold: int) -> String:
	var parts := PackedStringArray()
	for name: Variant in takes:
		parts.append("+%s" % name)
	for name: Variant in gives:
		parts.append("-%s" % name)
	if gold != 0 and not parts.is_empty():
		parts.append("%+dg" % gold)
	return " ".join(parts)


## The hover's words for one of theirs ([param price]) or one of the
## player's ([param pays], 0 when they won't buy; [param fenced] for the
## half price of grave goods).
static func hover_words(theirs: bool, price: int, pays: int, fenced: bool) -> String:
	if theirs:
		return "takes %d gold" % price
	if pays <= 0:
		return "won't buy"
	return "pays %d gold, fenced" % pays if fenced else "pays %d gold" % pays


## The button's words: the sum then "= Confirm"; "Confirm" alone with
## nothing selected.
static func button_words(sum: String) -> String:
	return "%s = Confirm" % sum if not sum.is_empty() else "Confirm"


## What the foot says under the sum: the shortfall when the purse can't
## cover the gold owed, else "".
static func shortfall_words(gold: int, purse: int) -> String:
	return "you need %d more gold" % (-gold - purse) if gold < 0 and -gold > purse else ""


## A click on one of the merchant's things: selected or unselected.
func toggle_take(uid: int) -> void:
	if not _open:
		return
	if take.has(uid):
		take.erase(uid)
	elif goods_have(uid):
		take[uid] = true
	_rebuild()


## A click on one of the player's things (by uid): selected to give, or
## unselected; one the merchant won't buy, or past the town's up_to for its
## kind, stays unselected and the hover says why.
func toggle_give(uid: int) -> void:
	if not _open:
		return
	if give.has(uid):
		give.erase(uid)
		_rebuild()
		return
	var entry := pack_entry(uid)
	if entry.is_empty():
		return
	if pays_for(uid) <= 0:
		_hover_words = "won't buy"
		_rebuild()
		return
	var same := 0
	for other: Variant in give:
		if str(pack_entry(int(other)).get("id", "")) == str(entry.get("id", "")):
			same += 1
	if same >= up_to(str(entry.get("id", ""))):
		_hover_words = "the town has enough of that"
		_rebuild()
		return
	give[uid] = true
	_rebuild()


## The names selected, for the sum's words (tests): the short names in
## lower case, Jeff's "+sword -hide".
func gives_shown() -> Array:
	var out := []
	for uid: Variant in give:
		out.append(Items.short_of(str(pack_entry(int(uid)).get("id", ""))).to_lower())
	return out


func takes_shown() -> Array:
	var out := []
	for uid: Variant in take:
		out.append(Items.short_of(str(goods_entry(int(uid)).get("id", ""))).to_lower())
	return out


func button_shown() -> String:
	return _button.text


func hover_shown() -> String:
	return _hover.text


func why_shown() -> String:
	return _why.text


func title_shown() -> String:
	return _title.text


## Confirm: the trade asked of the server, nothing selected does nothing.
func _confirm() -> void:
	if not _open or (give.is_empty() and take.is_empty()):
		return
	var gives: Array = give.keys()
	var takes: Array = take.keys()
	trade_asked.emit(with, gives, takes, balance_of(gives, takes))


## PackPanel's select hook: a left click on one of the player's boxes while
## the window is open selects it (true: the click is taken, no drag).
func _select_mine(mine: bool, index: int) -> bool:
	if not _open or not mine:
		return false
	var entry := pack_entry_at(index)
	if entry.is_empty():
		return false
	toggle_give(int(entry.get("uid", 0)))
	return true


## PackPanel's hover hook: over one of the player's boxes, what the
## merchant pays for it.
func _hover_mine(mine: bool, index: int) -> void:
	if not _open:
		return
	if not mine or index < 0:
		_hover_none()
		return
	var entry := pack_entry_at(index)
	if entry.is_empty():
		_hover_none()
		return
	var uid := int(entry.get("uid", 0))
	_hover_words = hover_words(false, 0, pays_for(uid), is_fenced(uid))
	_show_words()


func _hover_theirs(uid: int) -> void:
	_hover_words = hover_words(true, int(goods_entry(uid).get("price", 0)), 0, false)
	_show_words()


func _hover_none() -> void:
	_hover_words = ""
	_show_words()


func _show_words() -> void:
	if _hover != null:
		_hover.text = _hover_words


func _rebuild() -> void:
	if not is_node_ready():
		return
	for child: Node in _goods.get_children():
		_goods.remove_child(child)
		child.queue_free()
	if not _open:
		if pack != null:
			pack.set_selected([])
		_box.visible = false
		return
	_title.text = title_words(merchant, with is Resident)
	var goods: Variant = data.get("goods", [])
	if goods is Array:
		for each: Variant in goods:
			if each is Dictionary:
				_goods.add_child(_good_box(each))
	if goods is Array and goods.is_empty():
		var empty := Label.new()
		empty.theme_type_variation = &"Caption"
		empty.add_theme_color_override("font_color", DIM)
		empty.text = empty_words(data) if not data.is_empty() else "asking..."
		_goods.add_child(empty)
	_hover.text = _hover_words
	var gives: Array = give.keys()
	var takes: Array = take.keys()
	var gold := balance_of(gives, takes)
	var sum := sum_words(takes_shown(), gives_shown(), gold)
	_button.text = button_words(sum)
	var short := shortfall_words(gold, int(data.get("gold", 0)))
	_button.disabled = sum.is_empty() or not short.is_empty()
	_foot.text = short
	_foot.visible = not short.is_empty()
	var why := str(data.get("why", ""))
	_why.text = why
	_why.visible = not why.is_empty()
	if pack != null:
		var slots := []
		for uid: Variant in give:
			slots.append(int(pack_entry(int(uid)).get("slot", -1)))
		pack.set_selected(slots)
	_box.visible = true


## One of the merchant's things as a box: its icon and short name, the
## pack's look, framed when selected.
func _good_box(each: Dictionary) -> GoodBox:
	var box := GoodBox.new()
	box.window = self
	box.uid = int(each.get("uid", 0))
	box.id = str(each.get("id", ""))
	box.custom_minimum_size = PackPanel.SLOT_SIZE
	box.theme_type_variation = &"Inset"
	box.tooltip_text = ""
	var picture := TextureRect.new()
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	picture.offset_left = PackPanel.ICON_INSET
	picture.offset_top = PackPanel.ICON_INSET
	picture.offset_right = -PackPanel.ICON_INSET
	picture.offset_bottom = -PackPanel.ICON_INSET
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.texture = pack.icons.icon(box.id) if pack != null and pack.icons != null else null
	box.add_child(picture)
	box.icon = picture
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM if picture.texture != null else VERTICAL_ALIGNMENT_CENTER
	# The caption size either way: a name without an icon ("Bandages") must
	# fit the box on one row, never break mid-word.
	label.add_theme_font_size_override("font_size", PackPanel.CAPTION_SIZE)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF if picture.texture != null else TextServer.AUTOWRAP_WORD
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = Items.short_of(box.id)
	label.add_theme_color_override("font_color", Items.color_of(box.id))
	box.add_child(label)
	box.label = label
	if take.has(box.uid):
		box.add_theme_stylebox_override("panel", PackPanel.selected_style())
	return box


func _process(_delta: float) -> void:
	var began := Time.get_ticks_usec()
	_place()
	UiCost.add("barter", Time.get_ticks_usec() - began)


## Beside the pack, to its left, its foot on the pack's (ShopPanel's
## place, 280); hidden with the pack.
func _place() -> void:
	if _open and not is_instance_valid(with) and with != null:
		close()
	var pack_shown := pack != null and pack.visible
	_box.visible = _open and pack_shown
	if not _box.visible:
		return
	var rect := pack.get_global_rect()
	_box.reset_size()
	_box.global_position = Vector2(rect.position.x - _box.size.x - GAP, rect.end.y - _box.size.y)
