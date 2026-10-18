class_name ConversePanel
extends PanelContainer
## Talking with a town's person (ui's step 4): a narrow box at the left,
## the world and their bubbles untouched. Who is speaking (the resident's
## name and trade; never the hidden type), "thinking" while their answer
## is out, the exchange with them alone, their offers (npc's "offers"
## message: shop, commission, rumour, plea, each with words, a cost and
## what accepting does), what the player owes them (open commissions), and
## quick asks that send ordinary chat lines their voice answers. Main
## opens it (E on a resident, or a line said to one in earshot), feeds it
## lines and offers, and sends what the buttons ask. The look is the
## shared theme's (UiTheme, docs/ui_style.md).

## A quick ask: the chat line to send.
signal ask_pressed(line: String)
## An offer accepted: its id, and the gold for a loan (0 otherwise).
signal offer_accepted(id: String, gold: int)
## Close pressed (Esc closes it too, Main).
signal close_pressed

const WIDTH := 900.0
const MAX_LINES := 8
## How long "thinking" shows after a line is sent, at most (the resident
## mind's own wait, decision 336).
const THINKING_FOR := 15.0
const ASKS := ["What do you sell?", "Any work for me?", "What's the news?"]
## What accepting an offer says on its button, by the offer's "accept".
const ACCEPT_WORDS := {"buy": "Buy", "take": "Take it on", "lend": "Lend", "carry": "Carry it"}
const KIND_WORDS := {"shop": "for sale", "commission": "work", "rumour": "rumour", "plea": "a plea"}

## The resident spoken with (null: closed).
var resident: GridEntity
## The offers shown, as sent.
var offers: Array[Dictionary] = []
var thinking := false

var _name: Label
var _trade: Label
var _dots: Label
var _lines: VBoxContainer
var _offer_rows: VBoxContainer
var _owed: Label
var _asks: HBoxContainer
var _thinking_since := 0.0
var _since := 0.0


func _init() -> void:
	name = "Converse"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_PASS


func _ready() -> void:
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = UiTheme.constant("margin")
	offset_right = UiTheme.constant("margin") + WIDTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiTheme.constant("row"))
	add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UiTheme.constant("row"))
	_name = Label.new()
	_name.theme_type_variation = &"Name"
	_name.add_theme_font_size_override("font_size", UiTheme.size("heading"))
	head.add_child(_name)
	_trade = Label.new()
	_trade.theme_type_variation = &"Caption"
	_trade.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_trade)
	_dots = Label.new()
	_dots.theme_type_variation = &"Caption"
	_dots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_dots)
	column.add_child(head)
	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 4)
	column.add_child(_lines)
	_offer_rows = VBoxContainer.new()
	_offer_rows.add_theme_constant_override("separation", UiTheme.constant("unit"))
	column.add_child(_offer_rows)
	_owed = Label.new()
	_owed.theme_type_variation = &"Caption"
	_owed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_owed.visible = false
	column.add_child(_owed)
	_asks = HBoxContainer.new()
	_asks.add_theme_constant_override("separation", UiTheme.constant("unit"))
	for ask: String in ASKS:
		var button := Button.new()
		button.text = ask
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void:
			ask_pressed.emit(ask)
			set_thinking(true))
		_asks.add_child(button)
	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.size_flags_horizontal = Control.SIZE_SHRINK_END | Control.SIZE_EXPAND
	close.pressed.connect(func() -> void: close_pressed.emit())
	_asks.add_child(close)
	column.add_child(_asks)


## Opened on [param body]: its name and trade from it (Resident.person,
## trade; [param label] is the label over its head, "Mara [cook]", when
## the body has no person yet). The exchange and the offers start empty.
func open(body: GridEntity, label := "") -> void:
	resident = body
	var person := str(body.get("person")) if body != null and body.get("person") != null else ""
	var trade := str(body.get("trade")) if body != null and body.get("trade") != null else ""
	_name.text = person if not person.is_empty() else label
	_trade.text = trade.replace("_", " ")  # The trade's id, in words ("medicine man").
	for child in _lines.get_children():
		_lines.remove_child(child)
		child.queue_free()
	show_offers([], [])
	set_thinking(false)
	visible = true


func close() -> void:
	resident = null
	visible = false


## A line of the exchange: the resident's answer or what the player said.
func add_line(speaker: String, text: String, theirs: bool) -> void:
	var label := RichTextLabel.new()
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(WIDTH - 2 * UiTheme.constant("pad"), 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.push_font(UiTheme.font("serif"))
	label.push_color(UiTheme.color("brass_bright") if theirs else UiTheme.color("text_dim"))
	label.add_text("%s: " % speaker)
	label.pop()
	label.pop()
	label.push_color(UiTheme.color("text"))
	label.add_text(text)
	label.pop()
	_lines.add_child(label)
	while _lines.get_child_count() > MAX_LINES:
		var oldest := _lines.get_child(0)
		_lines.remove_child(oldest)
		oldest.queue_free()
	if theirs:
		set_thinking(false)


## "thinking" beside the name while an answer is out; it clears itself
## after THINKING_FOR.
func set_thinking(on: bool) -> void:
	thinking = on
	_thinking_since = Time.get_ticks_msec() / 1000.0
	_dots.text = "thinking" if on else ""


## [param given]: the resident's offers (npc's shape: id, kind, title, words,
## what, accept, cost); [param owed]: the open commissions the player holds
## for them ("open" true), listed as what they owe.
func show_offers(given: Array, owed: Array) -> void:
	offers.clear()
	for child in _offer_rows.get_children():
		_offer_rows.remove_child(child)
		child.queue_free()
	for each: Variant in given:
		if each is Dictionary:
			offers.append(each)
			_offer_rows.add_child(_offer_row(each))
	var owing: Array[String] = []
	for each: Variant in owed:
		if each is Dictionary:
			owing.append(str(each.get("title", each.get("words", ""))))
	_owed.text = "You owe them: %s" % ", ".join(owing) if not owing.is_empty() else ""
	_owed.visible = not owing.is_empty()


## The offers' titles and their buttons' words, in order (tests).
func offers_shown() -> Array[String]:
	var out: Array[String] = []
	for row: HBoxContainer in _offer_rows.get_children():
		var title: Label = row.find_child("Title", true, false)
		var button: Button = row.get_node_or_null("Accept")
		out.append("%s%s" % [title.text, " [%s]" % button.text if button != null and button.visible else ""])
	return out


func _offer_row(offer: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.constant("row"))
	var kind := Label.new()
	kind.name = "Kind"
	kind.theme_type_variation = &"Small"
	kind.text = str(KIND_WORDS.get(str(offer.get("kind", "")), str(offer.get("kind", ""))))
	kind.custom_minimum_size = Vector2(130, 0)
	row.add_child(kind)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.name = "Title"
	title.text = str(offer.get("title", offer.get("words", "")))
	title.add_theme_font_override("font", UiTheme.font("serif"))
	words.add_child(title)
	var said := Label.new()
	said.theme_type_variation = &"Caption"
	said.text = str(offer.get("words", ""))
	said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	said.visible = not said.text.is_empty() and said.text != title.text
	words.add_child(said)
	row.add_child(words)
	var cost := int(offer.get("cost", 0))
	var accept := str(offer.get("accept", ""))
	if cost > 0 and accept != "lend":
		var price := Label.new()
		price.text = "%d gold" % cost
		price.add_theme_color_override("font_color", UiTheme.color("brass"))
		price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(price)
	if not accept.is_empty():
		var id := str(offer.get("id", ""))
		var amount: HSlider = null
		if accept == "lend":
			# A loan: how much, up to what they ask.
			amount = HSlider.new()
			amount.min_value = 1
			amount.max_value = maxi(cost, 1)
			amount.value = amount.max_value
			amount.custom_minimum_size = Vector2(200, 40)
			amount.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			amount.focus_mode = Control.FOCUS_NONE
			row.add_child(amount)
		var button := Button.new()
		button.name = "Accept"
		button.text = str(ACCEPT_WORDS.get(accept, accept.capitalize()))
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(func() -> void:
			offer_accepted.emit(id, int(amount.value) if amount != null else 0))
		row.add_child(button)
	return row


func _process(delta: float) -> void:
	if not thinking:
		return
	_since += delta
	if Time.get_ticks_msec() / 1000.0 - _thinking_since > THINKING_FOR:
		set_thinking(false)
		return
	_dots.text = "thinking" + ".".repeat(1 + int(_since / 0.4) % 3)
