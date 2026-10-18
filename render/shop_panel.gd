class_name ShopPanel
extends Control
## The player's gold, over the pack's top right whenever the pack shows, and
## an open shop's goods beside the pack (decision 280): a row each, its name,
## its price and Buy, and under them what the town would pay for the things
## the player carries (put one in the shop's counter to sell it). The
## server sends both ("shop" messages, Main._send_shop); Buy goes back as a
## command (Main._buy) and the answer is the shop again. In the shared
## theme's look (UiTheme, docs/ui_style.md): prices brass, a refusal rust.
## Sizes in the HUD's 3840 x 2160 units.

const ROW_HEIGHT := 64
const GAP := 20
## A refusal's colour, and a price's or the gold's: the theme's.
static var WHY: Color = UiTheme.color("rust")
static var PRICE: Color = UiTheme.color("brass")

## The pack panel it sits beside.
var pack: PackPanel
## Called with (shop, uid) for Buy.
var buy: Callable
## The open shop's counter, or null.
var shop: GridEntity
## The player's gold, as the server last said.
var gold := 0:
	set(value):
		gold = value
		if is_node_ready():
			_gold_label.text = "%d gold" % gold
			_rebuild()

var _goods: Array = []
var _offers: Dictionary = {}
var _why := ""
var _gold_box: PanelContainer
var _gold_label: Label
var _box: PanelContainer
var _title: Label
var _rows: VBoxContainer
var _offer_label: Label
var _why_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gold_box = _panel()
	_gold_label = _label(PRICE)
	_gold_label.text = "%d gold" % gold
	_gold_box.add_child(_gold_label)
	add_child(_gold_box)
	_box = _panel()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_box.add_child(column)
	_title = _label()
	_title.theme_type_variation = &"Heading"
	column.add_child(_title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	column.add_child(_rows)
	_offer_label = _label()
	_offer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_offer_label.custom_minimum_size.x = 640
	column.add_child(_offer_label)
	_why_label = _label(WHY)
	_why_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_why_label.custom_minimum_size.x = 640
	column.add_child(_why_label)
	add_child(_box)
	_rebuild()


## A box in the theme's panel style.
func _panel() -> PanelContainer:
	return PanelContainer.new()


## A label in the theme's text, or in [param color] (one of the theme's).
func _label(color: Variant = null) -> Label:
	var label := Label.new()
	if color is Color:
		label.add_theme_color_override("font_color", color)
	return label


## Opens [param counter]'s shop (null closes it); its goods come with the
## server's answer.
func open(counter: GridEntity) -> void:
	if counter != shop:
		_goods = []
		_offers = {}
		_why = ""
	shop = counter
	_rebuild()


## The server refused what was asked (a purchase): [param why] (Main's
## UiSounds: an error sound).
signal refused(why: String)


## The server's "shop" message for the open shop: its goods, offers and
## any refusal.
func show_shop(data: Dictionary) -> void:
	if not is_instance_valid(shop) or str(data.get("shop", "")) != str(shop.get_path()):
		return
	_goods = data.get("goods", []) if data.get("goods") is Array else []
	_offers = data.get("offers", {}) if data.get("offers") is Dictionary else {}
	_why = str(data.get("why", ""))
	if not _why.is_empty():
		refused.emit(_why)
	_rebuild()


## The goods box's rect on screen while it shows, else an empty rect (the
## counter panel sits above it).
func box_rect() -> Rect2:
	return _box.get_global_rect() if _box.visible else Rect2()


## The rows shown, "name price" each (tests).
func rows_shown() -> Array[String]:
	var out: Array[String] = []
	for row: Node in _rows.get_children():
		if row.is_queued_for_deletion():
			continue
		out.append("%s %s" % [(row.get_child(0) as Label).text, (row.get_child(1) as Label).text])
	return out


## The refusal shown ("" for none) and the gold shown (tests).
func why_shown() -> String:
	return _why_label.text


func gold_shown() -> String:
	return _gold_label.text


func _rebuild() -> void:
	if not is_node_ready():
		return
	for row: Node in _rows.get_children():
		row.queue_free()
	_title.text = "Shop" if _goods.size() > 0 else "Shop: nothing for sale"
	for each: Variant in _goods:
		if not each is Dictionary:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		row.custom_minimum_size.y = ROW_HEIGHT
		var id := str(each.get("id", ""))
		var name_label := _label(Items.color_of(id))
		name_label.text = Items.name_of(id)
		name_label.custom_minimum_size.x = 360
		row.add_child(name_label)
		var price_label := _label(PRICE)
		price_label.text = "%d gold" % int(each.get("price", 0))
		price_label.custom_minimum_size.x = 160
		row.add_child(price_label)
		var button := Button.new()
		button.text = "Buy"
		button.disabled = gold < int(each.get("price", 0))
		var uid := int(each.get("uid", 0))
		button.pressed.connect(func() -> void:
			if buy.is_valid() and is_instance_valid(shop):
				buy.call(shop, uid))
		row.add_child(button)
		_rows.add_child(row)
	var offered: Array[String] = []
	var ids: Array = _offers.keys()
	ids.sort()
	for id: Variant in ids:
		offered.append("%s %d gold" % [Items.name_of(str(id)), int(_offers[id])])
	_offer_label.text = "The town pays: %s (put it in the counter)" % ", ".join(offered) if not offered.is_empty() \
			else "The town wants nothing you carry."
	_why_label.text = _why
	_why_label.visible = not _why.is_empty()


func _process(_delta: float) -> void:
	if not is_instance_valid(shop):
		shop = null
	var pack_shown := pack != null and pack.visible
	_gold_box.visible = pack_shown
	_box.visible = pack_shown and shop != null
	if not pack_shown:
		return
	var rect := pack.get_global_rect()
	_gold_box.reset_size()
	_gold_box.global_position = Vector2(rect.end.x - _gold_box.size.x, rect.position.y - _gold_box.size.y - GAP)
	if _box.visible:
		_box.reset_size()
		_box.global_position = Vector2(rect.position.x - _box.size.x - GAP, rect.end.y - _box.size.y)
