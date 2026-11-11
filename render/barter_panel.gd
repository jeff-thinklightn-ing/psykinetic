class_name BarterPanel
extends Control
## The store window (decision 765; Jeff approved the round-2 mocks,
## C:/dev/review/store_layout/round2: "the method is select item, then
## click buy, i'd like the gold and number to be an overlay over the icons,
## when items are selected it says Buy ("x" items) and hovering over the
## button shows a Total on a pop-up"). One window beside the pack for every
## seller, the barter window of 560 grown to hold them all:
## - a shop's or a maker's goods (economy's "barter" message, 560 and 562),
##   with what they pay for the player's things as a chip over each pack
##   square (PackPanel.prices) and the things they won't buy dimmed;
## - the healer's care (584 amended): Healing, a square for each way to pay
##   (gold, herbs, antlers), the "retain" command;
## - a townsperson's wares (Rolf's stall, 736; a pedlar's pack, 711): the
##   "offers" lines whose accept is a ware, one "offer" command a pick (they
##   were DealPanel's buttons before 765);
## - the temple's and the smith's counter (economy's "counter" message, 438;
##   CounterPanel's rows before 765): the player's own things that can be
##   worked, each with the work's mark (art-kit's art/ui/marks, 3b0a2f3c),
##   the work in hand with its time left, and the work ready, a bright frame
##   that a click collects.
## Every square in the pack's look, the price a chip over its corner (a coin,
## or what is paid, and the number); hover: the name alone (Jeff: no
## explaining captions), voice's words for the services. A click picks a
## square, a second unpicks it; the one button names what is done and how
## many (voice's verbs: Buy, Sell or Trade for goods, Pay for Healing, the
## work's own verb at a counter: "Bless (2 items)"); hovering it shows the
## Total (a pop-up beside it). A pick of another kind (Healing, or another
## kind of work) lets the last go. The server prices it all and answers with
## its message again; a refusal's why under the grid in rust (refused:
## Main's error sound). Sizes in the HUD's 3840 x 2160 units; the look the
## shared theme's (UiTheme, docs/ui_style.md).
##
## The townsperson window (decision 802, ui's side; Jeff: one window per
## townsperson): the same window, opened by a click on the person, carries
## their name, a chat area (their lines and the player's while it is open,
## CHAT_LINES high, scrolling) and the typing line, focused on open, above
## their squares; for one with no trade, the chat alone; a visitor's or the
## stall keeper's (who answer clicks only), no typing line. Enter speaks
## (said: Main sends "say" with "to"), Esc closes. person is whose window it
## is, though `with` is the counter a merchant fronts. Out of reach for a
## trade (near false, Main's) the button dims, "Step closer to trade".
##
## Give (802, Jeff: things handed to a person, not a chest): with what the
## person takes from the player's pack (economy's "takes" rows in their
## sheet, person_takes), a Give toggle beside the name (Sell where they pay,
## else Donate: give_word, 802 amended (8)); on, the pack's
## squares they take are lit (a coin where they pay now), the rest dim, a
## click picks a row, the lines under say what it does (voice's: "For the
## new forge: 12 of 20 ore", "Pays 3 gold", "A gift")
## and the button gives ("Sell (2 items)", "Donate (2 items)": Main sends "give" {entity,
## uids}). Opened while carrying something they take, the window opens on
## Give. Nothing they take: no toggle.

const GAP := 20
## Squares a line before the grid wraps.
const COLUMNS := 6
## A price chip: its height, and the coin's radius.
const CHIP_HEIGHT := 40
## The price row under a store's square: the gap above it, and its height
## with the gap (CHIP_HEIGHT; more for a job's two chips, which widen it).
const PRICE_GAP := 4
const PRICE_ROW := CHIP_HEIGHT + PRICE_GAP
const COIN_RADIUS := 11
## The theme's: a price in brass, a refusal in rust, the hover's words dim,
## a picked square's frame bright brass.
static var PRICE: Color = UiTheme.color("brass")
static var OUT: Color = UiTheme.color("rust")
static var DIM: Color = UiTheme.color("text_dim")
static var SELECT: Color = UiTheme.color("brass_bright")

## Voice's names for the services, the hover over their squares.
const SERVICE_NAMES := {"care": "Healing", "bless": "Blessing", "reforge": "Remaking", "mend": "Mending"}
## Voice's verbs for work ordered at a counter, the button's first word.
const WORK_VERBS := {"bless": "Bless", "reforge": "Remake", "mend": "Mend"}
## The counter's title by its kind (CounterPanel's before 765).
const COUNTER_TITLES := {"temple": "The temple's counter", "shop": "The smith's counter"}
## The ways into the healer's care (584 amended; Jeff: 10 gold, 5 herbs or 5
## antlers handed to him): a square each while its price is above 0.
const CARE_PAYS: Array[String] = ["gold", "herbs", "antlers"]
## A true minus sign for a Trade's Total (voice).
const MINUS := "\u2212"

## Goods: the trade asked (gold signed from the player's side, positive when
## they receive).
signal trade_asked(with: GridEntity, give: Array, take: Array, gold: int)
## The server refused: [param why].
signal refused(why: String)
## Healing: the player asks for [param with]'s care, paid by [param pay].
signal care_asked(with: GridEntity, pay: String)
## A ware: its offer id and its cost (Main sends "offer").
signal offer_asked(id: String, gold: int)
## Work at a counter: the slot, the effect, the target id ("" but for a reforge).
signal order_asked(slot: int, effect: String, to_id: String)
## Work ready at a counter: the thing's uid (Main sends "counter" collect).
signal collect_asked(uid: int)
## 802: the typing line's words, Enter pressed (Main sends "say" {to}).
signal said(text: String)
## 802 Give: the rows' uids handed to [param to] (Main sends "give").
signal give_asked(to: GridEntity, uids: Array)
## Rolf's stall (807 amended (3)): his Open locker button (the player's
## locker opened beside him, "locker" {keeper}). His Take practice kit went
## with the kit (807 amended (5): Jeff, "a 'take practice kit' button that
## just fills your inventory with junk you can't trade").
signal locker_asked(keeper: GridEntity)
## 852: the store window's answer came: "bought", "sold" (a sale, or a hand-over paid in gold) or "left" (a gift, a hand-back), for the cue (Main plays it).
signal told(what: String)

## 802: the chat area's height in lines, and how many lines it keeps.
const CHAT_LINES := 6
const CHAT_KEPT := 40
const CHAT_WIDTH := 600
## 802: the typing line's longest line (Main.CHAT_MAX_CHARS's).
const LINE_MOST := 200
## Voice's words (802): the button's foot while out of reach for a trade.
const STEP_CLOSER := "Step closer to trade."
const ASLEEP_WORDS := "asleep"
## The store window's lines (852; voice's, every one ends with a full stop; %s the
## thing with its article, "a spear", or "the dagger" for your own piece; %d gold).
const BOUGHT_LINE := "Bought %s for %d gold."
const SOLD_LINE := "Sold %s for %d gold."
const HANDED_BACK_LINE := "Handed back %s."
const LEFT_LINE := "Left %s on the shelves for the town."
const WONT_TAKE_LINE := "%s won't take that."
const ENOUGH_LINE := "The town has enough of that."
const ASLEEP_LINE := "%s is asleep. Come back by day."
const STORE_TAB := "Store"
const LOCKER_TAB := "Locker"
## How long a click waits for the server to answer before the line stops expecting it, msec.
const ANSWER_MSEC := 3000
## A keeper's refusal in words (his speech) is read as the answer when the purse has not moved by then, msec.
const SAID_MSEC := 600
## The line waits this long for the pack's squares to change with the purse, then is said anyway, msec.
const PACK_WAIT_MSEC := 500
## The mark of the town's trusted prices (voice's word, the regard ladder's; no hover).
const TRUSTED_WORDS := "Trusted"
## Voice's words for Give (802; 802 amended (8), give_word): the toggle and
## the button's verb, Sell where the person pays, else Donate; a gift's line.
const SELL_WORDS := "Sell"
const DONATE_WORDS := "Donate"
const GIFT_WORDS := "A gift"
## Rolf's button (807 amended (3), voice's words).
const LOCKER_WORDS := "Open locker"
## Offers that are shown as squares or by the counter, never as rows (536 amended).
## The asks seen before the list scrolls (ui-design's ruling, 11-11).
const ASKS_VISIBLE := 4
const NOT_ROWS: Array[String] = [Offers.VENDOR_WARES, Offers.WARES, Offers.CAMP_WARES]

## The pack panel the window sits beside (its boxes are the player's side).
var pack: PackPanel
## What is traded at or with: a shop's counter (560) or a counter (438), a
## maker in person or a ware seller (562, a Resident); null closed, or a
## test's sample.
var with: GridEntity
## Who fronts it, for the title; "" for none.
var merchant := ""
## The barter message as last received ({} at a counter alone).
var data: Dictionary = {}
## The counter message as last received ({} for none).
var counter: Dictionary = {}
## The wares shown (a townsperson's offers whose accept is a ware).
var wares: Array[Dictionary] = []
## The purse as last told (the message's gold, or Main's).
var purse := 0
## Picked: the player's uids to give, the merchant's uids to take, the wares'
## ids (to their cost), the care's way to pay ("" none), the counter's jobs
## (by slot) to order.
var give: Dictionary = {}
var take: Dictionary = {}
var wares_pick: Dictionary = {}
var care_pay := ""
var jobs_pick: Dictionary = {}

var _open := false
## 802: whose window it is (null: a counter's or a chest's, no person).
var person: GridEntity
## 802: the typing line shown (a townsperson who hears typed words).
var talks := false
## 802: whether the squares show (a person with no trade: the chat alone).
var trades := true
## 802: within reach for a trade (Main's, each frame); false dims the button.
var near := true
## 802: the person asleep (Resident's activity), shown under the name.
var asleep := false
## 802 Give: what the person takes from the pack (economy's rows: uid, what,
## count, slot, raw, for {kind, name}, have, need, gold), whether the
## window gives, and the rows picked (uid -> true).
var takes: Array = []
var giving := false
var gift: Dictionary = {}
var _give_due := false
## 852: the approved store window (StoreView), which every goods and wares trade
## uses (a counter's work and the healer's care keep the old window beside the
## pack); this controller hands it a state and takes its clicks.
var _store_view: StoreView
## The foot line's words and whether it is a refusal (rust); said by say_foot.
var _foot_text := ""
var _foot_refused := false
## The click the server has not answered yet: {kind, key, text, purse, at, uid}.
var _pending: Dictionary = {}
## The last words the keeper said (his speech) and when, msec.
var _said := {"text": "", "at": -1000000}
## The thing the pointer is on in the store window, "kind:key" ("" none).
var _store_over := ""
## When the last click was answered (msec): a trade's words from the server, arriving just after, replace its line.
var _answered_msec := -1000000
## Where each thing in the pack that the keeper won't take goes ({item id: words}, the server's depot pointers); the foot line says them.
var points: Dictionary = {}
var _box: PanelContainer
var _title: Label
## "Trusted" (economy's trusted prices, voice's word, no hover) after the
## title, while the barter's prices are the town's trusted ones ("trusted").
var _trusted: Label
var _give_tab: Button
var _locker_button: Button
var _outcome: VBoxContainer
var _state: Label
var _chat_scroll: ScrollContainer
var _chat: VBoxContainer
var _line: LineEdit
## 536 amended: the person's asks as rows (their open offers that are not wares), a click each.
var asks: Array[Dictionary] = []
var ask_why := ""
var _asks_box: VBoxContainer
## The asks' list scrolls past ASKS_VISIBLE rows (ui-design's ruling); the window stops growing there.
var _asks_scroll: ScrollContainer
var _foot_row: HBoxContainer
var _focus_due := false
var _grid: GridContainer
var _hover: Label
var _button: Button
var _foot: Label
var _why: Label
var _total: PanelContainer
var _total_chip: HBoxContainer
var _tip: PanelContainer
var _tip_words: Label
var _hover_words := ""
var _marks: Dictionary = {}
## An icon asked for and not drawn yet: the squares are laid out again when
## it arrives (ItemIcons.icon_ready), as the pack's are.
var _icons_due := false


## A coin, drawn: a brass disc with a ring, the price chips' mark for gold.
class Coin:
	extends Control
	var radius := COIN_RADIUS

	func _init(r := COIN_RADIUS) -> void:
		radius = r
		custom_minimum_size = Vector2.ONE * (2 * r + 2)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var middle := size / 2.0
		draw_circle(middle, radius, UiTheme.color("brass"))
		var brass := UiTheme.color("brass")
		draw_arc(middle, radius, 0.0, TAU, 24, brass.darkened(0.35), 2.0, true)
		draw_arc(middle, radius * 0.5, 0.0, TAU, 16, brass.lightened(0.3), 2.0, true)


## One square: a good, a ware, a way to pay for Healing, a job, the work in
## hand or ready. Clicked to pick, hovered for its name.
class StoreBox:
	extends Panel
	var window: BarterPanel
	## The square itself (the slate, the picked frame); the price row under it.
	var face: Panel
	## What it is: "good" (key a uid), "ware" (an offer id), "care" (a pay),
	## "job" (a slot), "working" or "ready" (a uid).
	var kind := ""
	var key: Variant
	var words := ""
	var icon: TextureRect
	var chips: BoxContainer

	func _ready() -> void:
		mouse_entered.connect(func() -> void: window._show_tip(self))
		mouse_exited.connect(func() -> void: window._hide_tip())

	func _gui_input(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			accept_event()  # First: the click rebuilds the grid, this square out of the tree (Jeff on v0.1.202).
			window.click_box(kind, key)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = PanelContainer.new()
	_box.visible = false
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiTheme.constant("row"))
	_box.add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UiTheme.constant("row"))
	column.add_child(head)
	_title = Label.new()
	_title.theme_type_variation = &"Heading"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_trusted = Label.new()
	_trusted.name = "Trusted"
	_trusted.text = TRUSTED_WORDS
	_trusted.theme_type_variation = &"Caption"
	_trusted.add_theme_color_override("font_color", UiTheme.color("brass"))
	_trusted.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_trusted.visible = false
	head.add_child(_trusted)
	_title.size_flags_horizontal = Control.SIZE_FILL
	var title_spacer := Control.new()
	title_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_spacer)
	_give_tab = Button.new()
	_give_tab.name = "GiveTab"
	_give_tab.text = DONATE_WORDS
	_give_tab.toggle_mode = true
	_give_tab.focus_mode = Control.FOCUS_NONE
	_give_tab.visible = false
	_give_tab.toggled.connect(set_giving)
	head.add_child(_give_tab)
	_locker_button = Button.new()
	_locker_button.name = "LockerButton"
	_locker_button.text = LOCKER_WORDS
	_locker_button.focus_mode = Control.FOCUS_NONE
	_locker_button.visible = false
	_locker_button.pressed.connect(func() -> void:
		if with != null:
			locker_asked.emit(with))
	head.add_child(_locker_button)
	_state = Label.new()
	_state.theme_type_variation = &"Caption"
	_state.add_theme_color_override("font_color", DIM)
	_state.visible = false
	column.add_child(_state)
	_chat_scroll = ScrollContainer.new()
	_chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_chat_scroll.custom_minimum_size.x = CHAT_WIDTH
	_chat_scroll.visible = false
	column.add_child(_chat_scroll)
	_chat = VBoxContainer.new()
	_chat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat.add_theme_constant_override("separation", 2)
	_chat_scroll.add_child(_chat)
	_line = LineEdit.new()
	_line.name = "SayLine"
	_line.max_length = LINE_MOST
	_line.visible = false
	_line.text_submitted.connect(_submit)
	_line.gui_input.connect(_line_input)
	column.add_child(_line)
	_asks_scroll = ScrollContainer.new()
	_asks_scroll.name = "AsksScroll"
	_asks_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_asks_scroll.visible = false
	column.add_child(_asks_scroll)
	_asks_box = VBoxContainer.new()
	_asks_box.name = "Asks"
	_asks_box.theme_type_variation = &"OfferList"  # ui-design defines it (the row constant between rows).
	_asks_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_asks_box.visible = false
	_asks_scroll.add_child(_asks_box)
	column.move_child(_line, _asks_scroll.get_index() + 1)  # The typing line below the asks (ui-design's mock).
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", UiTheme.constant("slot_gap"))
	_grid.add_theme_constant_override("v_separation", UiTheme.constant("slot_gap"))
	column.add_child(_grid)
	_outcome = VBoxContainer.new()
	_outcome.add_theme_constant_override("separation", 2)
	_outcome.visible = false
	column.add_child(_outcome)
	_hover = Label.new()
	_hover.theme_type_variation = &"Caption"
	_hover.add_theme_color_override("font_color", DIM)
	_hover.visible = false
	column.add_child(_hover)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", UiTheme.constant("row"))
	column.add_child(foot)
	_foot_row = foot
	_button = Button.new()
	_button.focus_mode = Control.FOCUS_NONE
	_button.pressed.connect(_confirm)
	_button.mouse_entered.connect(_show_total)
	_button.mouse_exited.connect(func() -> void: _total.visible = false)
	foot.add_child(_button)
	_foot = Label.new()
	_foot.theme_type_variation = &"Caption"
	_foot.add_theme_color_override("font_color", OUT)
	_foot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_foot)
	_why = Label.new()
	_why.theme_type_variation = &"Caption"
	_why.add_theme_color_override("font_color", OUT)
	_why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_why.custom_minimum_size.x = 600
	column.add_child(_why)
	add_child(_box)
	# The Total, a pop-up beside the button while the mouse is on it.
	_total = PanelContainer.new()
	_total.theme_type_variation = &"Tip"
	_total.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_total.visible = false
	var total_row := HBoxContainer.new()
	total_row.add_theme_constant_override("separation", UiTheme.constant("row"))
	var total_word := Label.new()
	total_word.text = "Total"
	total_row.add_child(total_word)
	_total_chip = HBoxContainer.new()
	_total_chip.add_theme_constant_override("separation", 6)
	total_row.add_child(_total_chip)
	_total.add_child(total_row)
	add_child(_total)
	# The name over a square, a tip beside the cursor.
	_tip = PanelContainer.new()
	_tip.theme_type_variation = &"Tip"
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	_tip_words = Label.new()
	_tip.add_child(_tip_words)
	add_child(_tip)
	_store_view = StoreView.new()
	_store_view.icon_of = _icon
	_store_view.square_pressed.connect(_on_store_square)
	_store_view.square_hovered.connect(_on_store_hover)
	_store_view.tab_pressed.connect(_on_store_tab)
	add_child(_store_view)
	move_child(_tip, -1)  # The name over a square draws over the window.
	if pack != null:
		pack.select_hook = _select_mine
		pack.hover_hook = _hover_mine
	_rebuild()


## Opens the window for a trade with [param person] (their name [param
## who]); the goods come with the server's barter message (Main sends the
## "barter" command), a counter's work with its "counter" message.
func open(person: GridEntity, who := "") -> void:
	if person != with:
		data = {}
		counter = {}
		wares = []
		asks = []
		ask_why = ""
	with = person
	merchant = who
	_clear_picks()
	_open = true
	_hover_words = ""
	_rebuild()


## Opens the window on [param person]'s wares among [param offers] (wares_of:
## Rolf's stall, a pedlar's pack), [param gold] in the purse; none closes it
## if it shows theirs.
func show_wares(person: GridEntity, who: String, offers: Array, gold: int) -> void:
	var found := wares_of(offers)
	if found.is_empty():
		if _open and with == person and not wares.is_empty():
			close()
		return
	if not _open or with != person:
		open(person, who)
	wares = found
	purse = gold
	for id: Variant in wares_pick.keys():
		if ware_entry(str(id)).is_empty():
			wares_pick.erase(id)
	_check_answer()
	_rebuild()


## 536 amended: [param body]'s asks among [param offers] (asks_of), shown as rows while the window is
## theirs; [param gold] in the purse. Called with every "offers" message for a townsperson.
func show_asks(body: GridEntity, offers: Array, gold: int) -> void:
	if not _open or with != body:
		return
	asks = asks_of(offers, trades)
	ask_why = ""
	purse = gold
	_rebuild()


## The offers of [param offers] a person's window shows as rows (536 amended): open ones (already
## taken, the pack's Promised line has them), wares (the squares), the camp trader's goods, words
## only ones (accept "") and, where the person has squares of their own, a plain buy are not.
static func asks_of(offers: Array, squares: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for each: Variant in offers:
		if not each is Dictionary or str(each.get("id", "")).is_empty() or bool(each.get("open", false)):
			continue
		var accept := str(each.get("accept", ""))
		if accept.is_empty() or accept == DealPanel.WORDS_ONLY or accept in NOT_ROWS or (squares and accept == Offers.BUY):
			continue
		out.append(each)
	return out


## The asks' height: the rows up to ASKS_VISIBLE and the separations between them, measured from a row's
## own minimum height (so it follows the text scale), the rest scrolling.
func _size_asks() -> void:
	var count := _asks_box.get_child_count()
	var shown := mini(count, ASKS_VISIBLE)
	if shown == 0:
		_asks_scroll.custom_minimum_size = Vector2.ZERO
		return
	var row_h := (_asks_box.get_child(0) as Control).get_combined_minimum_size().y
	var gap := float(_asks_box.get_theme_constant(&"separation"))
	_asks_scroll.custom_minimum_size = Vector2(0.0, shown * row_h + (shown - 1) * gap)


## One row of the asks (the part ui-design swaps for UiRow): [param title] on the left, [param amount] gold on
## the right (-1: none), [param short] when it is more than the purse (shown by the theme, never dimmed).
func _row(title: String, amount: int, short: bool) -> Button:
	var row := Button.new()
	row.theme_type_variation = &"OfferRow"
	row.focus_mode = Control.FOCUS_NONE
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.text = title
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.set_meta("shown", title)
	row.set_meta("gold", str(amount) if amount >= 0 else "")
	row.set_meta("short", short)
	if amount >= 0:
		var price := UiPrice.new()  # ui-design's chip: the coin, rust when it can't be paid.
		price.name = "Price"
		price.set_gold(amount, short)
		price.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		price.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		price.grow_vertical = Control.GROW_DIRECTION_BOTH
		var inset := float(row.get_theme_stylebox(&"normal").get_margin(SIDE_LEFT))  # The words' left inset, on the right too.
		price.offset_right = -inset
		row.add_child(price)
	return row


## A row clicked: the offer asked as it reads ("offer" {id, gold: its cost}); more than the purse is
## refused here, in the window's why line, and nothing is sent; out of reach likewise.
func _ask_pressed(id: String, cost: int) -> void:
	if not _open:
		return
	if not near:
		ask_why = STEP_CLOSER
	elif cost > purse:
		ask_why = shortfall_words(-cost, purse)
	else:
		ask_why = ""
		offer_asked.emit(id, cost)
	_rebuild()


## The rows' titles, then the price shown on each ("title|10", a free one "title|") (tests).
func asks_shown() -> Array[String]:
	var out: Array[String] = []
	for row: Node in _asks_box.get_children():
		if not row.is_queued_for_deletion():
			out.append("%s|%s" % [row.get_meta("shown", ""), row.get_meta("gold", "")])
	return out


## Rolf's button (807 amended (3)) for the stall keeper whose wares show:
## Open locker when [param offers] are his stall's (Offers.VENDOR_WARES).
func set_keeper(offers: Array) -> void:
	var keeper := _open and offers.any(func(each: Variant) -> bool:
		return each is Dictionary and str((each as Dictionary).get("kind", "")) == Offers.VENDOR_WARES)
	if _locker_button != null and _locker_button.visible != keeper:
		_locker_button.visible = keeper
		_rebuild()  # 852: the Locker tab shows with it.


## Whether Rolf's buttons show: [Open locker].
func keeper_buttons() -> Array[bool]:
	return [_locker_button != null and _locker_button.visible]


## The purse as Main last read it (a ware seller's window, no barter message).
func set_purse(gold: int) -> void:
	if gold != purse:
		purse = gold
		_check_answer()
		_rebuild()


## 802: the window is [param body]'s, the townsperson clicked: [param chat]
## shows the typing line (focused), [param trade] their squares. Call after
## open() (a merchant's opens on the counter they front).
func set_person(body: GridEntity, chat: bool, trade: bool) -> void:
	if body != person:
		_clear_chat()
		_line.text = ""
	if body != person:
		_give_due = true  # The first sheet with takes opens on Give (Jeff).
	person = body
	talks = chat
	trades = trade
	near = true
	_rebuild()
	if talks and _open:
		focus_line()


## 802: the typing line takes the keys (a click on it does too); the frame
## the window first shows if it is not shown yet (_place).
func focus_line() -> void:
	if _line == null or not talks or not _open:
		return
	if _line.is_visible_in_tree():
		_line.grab_focus()
		_focus_due = false
	else:
		_focus_due = true


## 802: a click on the world takes the keys back from the typing line.
func release_line() -> void:
	if _line != null and _line.has_focus():
		_line.release_focus()


## 802: whether the typing line has the keys (Main.is_typing: no game key).
func is_typing() -> bool:
	return _open and talks and _line != null and _line.has_focus()


## 802: in reach for a trade or not (Main, each frame).
func set_near(value: bool) -> void:
	if value != near:
		near = value
		_rebuild()


## 802: the person seen asleep or not.
func set_asleep(value: bool) -> void:
	if value != asleep:
		asleep = value
		_rebuild()


## 802: a line in the chat area: [param speaker]'s [param text], an aside dim after it.
func add_said(speaker: String, text: String, aside := "") -> void:
	if not _open or person == null or text.strip_edges().is_empty():
		return
	var label := RichTextLabel.new()
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.push_color(TalkPanel.SPEAKER)
	label.add_text("%s: " % speaker)
	label.pop()
	label.add_text(text)
	if not aside.is_empty():
		label.push_color(TalkPanel.ASIDE)
		label.add_text(TalkPanel.ASIDE_DASH + aside)
		label.pop()
	label.set_meta("words", "%s: %s" % [speaker, text])
	_chat.add_child(label)
	while _chat.get_child_count() > CHAT_KEPT:
		var oldest := _chat.get_child(0)
		_chat.remove_child(oldest)
		oldest.queue_free()
	_chat_scroll.visible = true
	_size_chat.call_deferred()


## 802: the chat area's lines (tests): "speaker: text" each.
func chat_shown() -> Array[String]:
	var out: Array[String] = []
	for line: Node in _chat.get_children():
		out.append(str(line.get_meta("words", "")))
	return out


func _clear_chat() -> void:
	if _chat == null:
		return
	for line: Node in _chat.get_children():
		_chat.remove_child(line)
		line.queue_free()
	_chat_scroll.visible = false


## The chat area as tall as its lines, up to CHAT_LINES, scrolled to the newest.
func _size_chat() -> void:
	if _chat.get_child_count() == 0:
		return
	var line_height := maxf((_chat.get_child(0) as Control).get_combined_minimum_size().y, 1.0)
	_chat_scroll.custom_minimum_size.y = minf(_chat.get_combined_minimum_size().y, line_height * CHAT_LINES)
	_chat_scroll.scroll_vertical = int(_chat.get_combined_minimum_size().y)


func _submit(text: String) -> void:
	var line := text.strip_edges()
	_line.text = ""
	if not line.is_empty():
		said.emit(line)


## Esc in the typing line closes the window (802; Options' "Close").
func _line_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		_line.accept_event()
		close()


func close() -> void:
	_open = false
	with = null
	person = null
	talks = false
	trades = true
	near = true
	asleep = false
	takes = []
	giving = false
	_give_due = false
	if _locker_button != null:
		_locker_button.visible = false
	_focus_due = false
	if _line != null:
		_line.text = ""  # A half-typed line goes with the window (802).
		_line.release_focus()
	_clear_chat()
	_clear_picks()
	data = {}
	counter = {}
	wares = []
	asks = []
	ask_why = ""
	if _asks_box != null:
		for child: Node in _asks_box.get_children():
			_asks_box.remove_child(child)
			child.queue_free()
		_asks_box.visible = false
		_asks_scroll.visible = false
	_hover_words = ""
	_foot_text = ""
	_foot_refused = false
	_pending = {}
	_store_over = ""
	points = {}
	_hide_tip()
	_rebuild()


func is_open() -> bool:
	return _open


## The server's barter message: for the person open (its "resident" path,
## or 560's "shop"; a sample names neither, tests and shots); a pick of
## something gone is dropped; a refusal's why shown and said (refused).
func show_barter(given: Dictionary) -> void:
	if not _open:
		return
	if is_instance_valid(with) and with.is_inside_tree() and not for_path(given, str(with.get_path())):
		return
	data = given
	purse = int(given.get("gold", purse))
	for uid: Variant in take.keys():
		if not goods_have(int(uid)):
			take.erase(uid)
	for uid: Variant in give.keys():
		if pack_entry(int(uid)).is_empty():
			give.erase(uid)
	if not care_pay.is_empty() and not care_open(care_pay):
		care_pay = ""
	var why := str(data.get("why", ""))
	if not why.is_empty():
		refused.emit(why)
		say_foot(why, true)  # 852: the refusal's own words in the window's foot line.
		_pending = {}
	set_takes(given.get("takes", []))


## 802 Give: the person's "takes" rows from their sheet (the barter message,
## or the stall's offers); a pick no longer taken is dropped; none ends Give;
## the first rows after the window opens open it on Give.
func set_takes(rows: Variant) -> void:
	takes = []
	if rows is Array:
		for row: Variant in rows:
			if row is Dictionary:
				takes.append(row)
	for uid: Variant in gift.keys():
		if takes_row(int(uid)).is_empty():
			gift.erase(uid)
	if takes.is_empty():
		giving = false
	_give_due = false  # 852: the window opens on Store, never on Donate (Jeff: "it just says Give").
	_check_answer()
	_rebuild()


func _open_on_give() -> void:
	_clear_picks()
	giving = true


## 802 Give: the window gives ([param on]) or trades; the picks either way dropped.
func set_giving(on: bool) -> void:
	on = on and not takes.is_empty()
	if on == giving:
		_rebuild()
		return
	_clear_picks()
	giving = on
	_total.visible = false
	_rebuild()


## The takes row for [param uid], {} for none.
func takes_row(uid: int) -> Dictionary:
	for row: Dictionary in takes:
		if int(row.get("uid", 0)) == uid:
			return row
	return {}


## The takes row at the pack's [param slot] (its "slot", else the barter
## pack's entry there), {} for none.
func takes_at(slot: int) -> Dictionary:
	for row: Dictionary in takes:
		if row.has("slot") and int(row["slot"]) == slot:
			return row
	var entry := pack_entry_at(slot)
	return takes_row(int(entry.get("uid", 0))) if not entry.is_empty() else {}


## Give's word (802 amended (8), voice's, Jeff: "it just says Give... It
## needs to say Trade or Donate"): "Sell" where one of [param rows] pays
## gold for what is handed over (Rolf's stall, the tanner's trophies),
## "Donate" where none does (ore toward a build, the larder, a gift). The tab
## takes it from all the person's rows; the button from those picked. Every
## sale is paid in full at once (826: no town owes a player), so a row's gold
## says it all (802 amended (9)'s owed row superseded).
static func give_word(rows: Array) -> String:
	for row: Variant in rows:
		if row is Dictionary and int((row as Dictionary).get("gold", 0)) > 0:
			return SELL_WORDS
	return DONATE_WORDS


## The rows picked for Give.
func gift_picked() -> Array:
	var out := []
	for uid: Variant in gift:
		var row := takes_row(int(uid))
		if not row.is_empty():
			out.append(row)
	return out


## A pick of the row [param uid] for Give, or its unpick.
func toggle_gift(uid: int) -> void:
	if not _open or not giving:
		return
	if gift.has(uid):
		gift.erase(uid)
	elif not takes_row(uid).is_empty():
		gift[uid] = true
	_rebuild()


## What giving [param rows] does, voice's lines (802): one a thing it goes
## toward, "For the new forge: 12 of 20 ore" (the row there furthest on,
## have and need as after the give), or "For tanning" alone where it needs
## no count (821: a trophy the tanner or Rolf buys, need 0); "A gift" for gear; then "Pays 3 gold"
## (nothing for none; 826: never owed). No full stops.
static func give_lines(rows: Array) -> Array[String]:
	var toward := {}
	var order: Array[String] = []
	var gifts := false
	var gold := 0
	for row: Variant in rows:
		if not row is Dictionary:
			continue
		gold += int(row.get("gold", 0))
		var target: Variant = row.get("for")
		var name := str(target.get("name", "")) if target is Dictionary else ""
		if name.is_empty():
			gifts = true
			continue
		if not toward.has(name):
			order.append(name)
		if not toward.has(name) or int(row.get("have", 0)) > int(toward[name].get("have", 0)):
			toward[name] = row
	var out: Array[String] = []
	for name: String in order:
		var row: Dictionary = toward[name]
		if int(row.get("need", 0)) <= 0:
			out.append("For %s" % name)  # 821: a trophy bought by its maker, no count toward ("For tanning").
		else:
			out.append("For %s: %d of %d %s" % [name, int(row.get("have", 0)), int(row.get("need", 0)), raw_word(row)])
	if gifts:
		out.append(GIFT_WORDS)
	if gold > 0:
		out.append("Pays %d gold" % gold)
	return out


## A takes row's unit word: its "raw" (economy's), else its thing's id
## without its sack or bundle ("ore_sack": "ore").
static func raw_word(row: Dictionary) -> String:
	var raw := str(row.get("raw", ""))
	if not raw.is_empty():
		return raw
	var what := str(row.get("what", ""))
	for tail: String in ["_sack", "_bundle", "_bolt"]:
		if what.ends_with(tail):
			return what.trim_suffix(tail)
	return what


## The picked rows (Give), in the order the sheet lists them.
func gift_rows() -> Array:
	var out := []
	for row: Dictionary in takes:
		if gift.has(int(row.get("uid", 0))):
			out.append(row)
	return out


## The counter message (economy's, 438) for the counter open; a pick no
## longer offered is dropped; a refusal's why shown and said.
func show_counter(given: Dictionary) -> void:
	if not _open:
		return
	counter = given
	if given.has("gold"):
		purse = int(given["gold"])
	for slot: Variant in jobs_pick.keys():
		if job_at(int(slot)).is_empty():
			jobs_pick.erase(slot)
	var why := str(given.get("why", ""))
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


## The window's title: the seller's name (765: the name alone); at a
## counter with nobody named, the counter's ("The temple's counter"); else
## "The shop".
static func title_words(who: String, counter_kind := "") -> String:
	if not who.is_empty():
		return who
	return str(COUNTER_TITLES.get(counter_kind, "The shop"))


## The words where the squares would be when there are none: "nothing to
## trade" when they buy nothing either (a maker with a bare shelf who needs
## nothing now, 562), else "nothing for sale".
static func empty_words(given: Dictionary) -> String:
	var buys: Variant = given.get("buys", {})
	return "nothing for sale" if buys is Dictionary and not buys.is_empty() else "nothing to trade"


## "Buy (2 items)": the verb and the count (voice: "item" at one).
static func button_words(verb: String, count: int, noun := "item") -> String:
	return "%s (%d %s%s)" % [verb, count, noun, "" if count == 1 else "s"]


## Healing's button: "Pay (10 gold)", "Pay (1 herb)", "Pay (3 herbs)", "Pay
## (1 pair of antlers)" (voice: what is handed over, singular at one; an
## antlers unit is a pair).
static func pay_words(pay: String, amount: int) -> String:
	match pay:
		"herbs":
			return "Pay (%d %s)" % [amount, "herb" if amount == 1 else "herbs"]
		"antlers":
			return "Pay (%d %s of antlers)" % [amount, "pair" if amount == 1 else "pairs"]
	return "Pay (%d %s)" % [amount, pay]


## The Total's number: plain for Buy and Sell (the button says which way);
## a Trade's signed, "+20" when the player comes out ahead, "−20" when they
## pay (voice: a true minus sign).
static func total_words(amount: int, signed: bool) -> String:
	if not signed:
		return str(absi(amount))
	if amount < 0:
		return MINUS + str(-amount)
	return "+%d" % amount


## What the foot says when the purse can't cover what is owed (voice):
## "You need 3 more gold."; "" otherwise.
static func shortfall_words(gold: int, held: int) -> String:
	return "You need %d more gold." % (-gold - held) if gold < 0 and -gold > held else ""


## The hover's stack words (619, ui's side): "3 of 5 to give" over a stack
## with some picked, "" over a lone thing or none picked.
static func stack_words(given: int, count: int) -> String:
	return "%d of %d to give" % [given, count] if count > 1 and given > 0 else ""


## Whether [param offer] is a ware a townsperson sells (its accept the
## starter stall's Offers.VENDOR_WARES or a pedlar's Offers.WARES).
static func is_ware(offer: Variant) -> bool:
	if not offer is Dictionary or str(offer.get("id", "")).is_empty() or bool(offer.get("open", false)):
		return false
	return str(offer.get("accept", "")) in [Offers.VENDOR_WARES, Offers.WARES]


## The wares among [param offers] (is_ware), in their order.
static func wares_of(offers: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for each: Variant in offers:
		if is_ware(each):
			out.append(each)
	return out


## A ware's item id (its what.item).
static func ware_item(offer: Dictionary) -> String:
	var what: Variant = offer.get("what", {})
	return str(what.get("item", "")) if what is Dictionary else ""


func ware_entry(id: String) -> Dictionary:
	for each: Dictionary in wares:
		if str(each.get("id", "")) == id:
			return each
	return {}


## Whether the merchant still has [param uid] for sale.
func goods_have(uid: int) -> bool:
	return not goods_entry(uid).is_empty()


## The goods entry for [param uid], {} for none.
func goods_entry(uid: int) -> Dictionary:
	for each: Variant in data.get("goods", []):
		if each is Dictionary and int(each.get("uid", 0)) == uid:
			return each
	return {}


## The player's pack entry {slot, uid, id, uids, count} for [param uid]
## (its first unit, or any of its stack's; 619), {} for none.
func pack_entry(uid: int) -> Dictionary:
	for each: Variant in data.get("pack", []):
		if each is Dictionary and (int(each.get("uid", 0)) == uid or stack_units(each).has(uid)):
			return each
	return {}


## The units in [param entry]'s slot (619: its "uids", every unit; the one
## uid for an entry before stacks, or a lone thing).
static func stack_units(entry: Dictionary) -> Array:
	var uids: Variant = entry.get("uids", [])
	if uids is Array and not uids.is_empty():
		var out := []
		for each: Variant in uids:
			out.append(int(each))
		return out
	return [int(entry.get("uid", 0))] if entry.has("uid") else []


## How many of [param entry]'s units are picked to give.
func given_of(entry: Dictionary) -> int:
	var n := 0
	for uid: int in stack_units(entry):
		if give.has(uid):
			n += 1
	return n


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


## The care the barter message offers ({} for none), and whether [param
## pay] is a way in now (not held, its price above 0).
func care() -> Dictionary:
	return data["care"] if data.get("care") is Dictionary else {}


func care_open(pay: String) -> bool:
	var offered := care()
	return not offered.is_empty() and not bool(offered.get("in_care", false)) and int(offered.get(pay, 0)) > 0


## What the player has handed toward [param pay] so far: the care's
## "given" {herbs, antlers} (npc's, 584 amended (2)); 0 without it.
static func care_given(offered: Variant, pay: String) -> int:
	if not offered is Dictionary or not offered.get("given") is Dictionary:
		return 0
	return int((offered["given"] as Dictionary).get(pay, 0))


## What paying by [param pay] hands over now: the gold whole; herbs or
## antlers, those held up to what is left to go (instalments, 584 amended (2)).
func care_hands(pay: String) -> int:
	var offered := care()
	var price := int(offered.get(pay, 0))
	if pay == "gold":
		return price
	var held := 0
	for each: Variant in data.get("pack", []):
		if each is Dictionary and str(each.get("id", "")) == pay:
			held += maxi(int(each.get("count", 1)), stack_units(each).size())
	return mini(held, maxi(price - care_given(offered, pay), 0))


## The counter's job for [param slot], {} for none.
func job_at(slot: int) -> Dictionary:
	for each: Variant in counter.get("jobs", []):
		if each is Dictionary and int(each.get("slot", -1)) == slot:
			return each
	return {}


## What the picks come to: {verb, count, noun, gold (signed, the player's
## side), total ([kind, amount] chips), signed (a Trade's), ok}; {} for none.
func action() -> Dictionary:
	if giving:
		if gift.is_empty():
			return {}
		return {"words": button_words(give_word(gift_picked()), gift.size()), "gold": 0, "total": [], "signed": false, "ok": true}
	if not care_pay.is_empty():
		var hands := care_hands(care_pay)
		return {"words": pay_words(care_pay, hands), "gold": -hands if care_pay == "gold" else 0,
			"total": [[care_pay, hands]], "signed": false, "ok": hands > 0}
	if not jobs_pick.is_empty():
		var gold := 0
		var ok := true
		var effect := ""
		for slot: Variant in jobs_pick:
			var job := job_at(int(slot))
			gold += int(job.get("price", 0))
			ok = ok and bool(job.get("ok", true))
			effect = str(job.get("effect", ""))
		return {"words": button_words(str(WORK_VERBS.get(effect, "Order")), jobs_pick.size()), "gold": -gold,
			"total": [["gold", gold]], "signed": false, "ok": ok}
	if not wares_pick.is_empty():
		var cost := 0
		for id: Variant in wares_pick:
			cost += int(wares_pick[id])
		return {"words": button_words("Buy", wares_pick.size()), "gold": -cost, "total": [["gold", cost]], "signed": false, "ok": true}
	if give.is_empty() and take.is_empty():
		return {}
	var balance := balance_of(give.keys(), take.keys())
	var verb := "Trade" if not give.is_empty() and not take.is_empty() else "Sell" if take.is_empty() else "Buy"
	return {"words": button_words(verb, give.size() + take.size()), "gold": balance, "total": [["gold", balance]],
		"signed": verb == "Trade", "ok": true}


## A click on one of the window's squares, by its kind and key.
func click_box(kind: String, key: Variant) -> void:
	if not _open:
		return
	match kind:
		"good":
			toggle_take(int(key))
		"ware":
			toggle_ware(str(key))
		"care":
			toggle_care(str(key))
		"job":
			toggle_job(int(key))
		"ready":
			collect_asked.emit(int(key))


## A pick of [param group] ("goods", "care", or a work's effect) lets the
## picks of any other go: one kind of thing is done at a time.
func _keep_only(group: String) -> void:
	if group != "goods":
		give.clear()
		take.clear()
		wares_pick.clear()
	if group != "care":
		care_pay = ""
	for slot: Variant in jobs_pick.keys():
		if str(job_at(int(slot)).get("effect", "")) != group:
			jobs_pick.erase(slot)


func _clear_picks() -> void:
	gift.clear()
	give.clear()
	take.clear()
	wares_pick.clear()
	care_pay = ""
	jobs_pick.clear()


## A click on one of the merchant's goods: picked or unpicked.
func toggle_take(uid: int) -> void:
	if not _open:
		return
	if take.has(uid):
		take.erase(uid)
	elif goods_have(uid):
		_keep_only("goods")
		take[uid] = true
	_rebuild()


func toggle_ware(id: String) -> void:
	if not _open:
		return
	if wares_pick.has(id):
		wares_pick.erase(id)
	elif not ware_entry(id).is_empty():
		_keep_only("goods")
		wares_pick[id] = int(ware_entry(id).get("cost", 0))
	_rebuild()


func toggle_care(pay: String) -> void:
	if not _open:
		return
	if care_pay == pay:
		care_pay = ""
	elif care_open(pay):
		_keep_only("care")
		care_pay = pay
	_rebuild()


func toggle_job(slot: int) -> void:
	if not _open:
		return
	if jobs_pick.has(slot):
		jobs_pick.erase(slot)
	elif not job_at(slot).is_empty():
		_keep_only(str(job_at(slot).get("effect", "")))
		jobs_pick[slot] = true
	_rebuild()


## A click on one of the player's things (by uid): picked to give, or
## unpicked; one the merchant won't buy, or past the town's up_to for its
## kind, stays unpicked and the line under the grid says why.
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
	_keep_only("goods")
	give[uid] = true
	_rebuild()


func button_shown() -> String:
	return _button.text


func hover_shown() -> String:
	return _hover.text


func why_shown() -> String:
	return _store_view.foot_shown() if _layout_store() and _store_view.foot_is_refused() else _why.text


func title_shown() -> String:
	return _store_view.title_shown() if _layout_store() else _title.text


## "Trusted" while shown, "" otherwise (tests).
func trusted_shown() -> String:
	if _layout_store():
		return TRUSTED_WORDS if data.get("trusted") == true else ""
	return _trusted.text if _trusted.visible else ""


func foot_shown() -> String:
	if _layout_store():
		return _store_view.foot_shown()
	return _foot.text if _foot.visible else ""


## The Total as the pop-up would show it (tests): its chips' words.
func total_shown() -> String:
	var act := action()
	if act.is_empty():
		return ""
	var parts := PackedStringArray()
	for chip: Array in act["total"]:
		parts.append("%s %s" % [chip[0], total_words(int(chip[1]), bool(act["signed"]))])
	return "Total " + ", ".join(parts)


## The squares shown (tests): "<kind> <key> <chips>[ picked]" each.
func boxes_shown() -> Array[String]:
	var out: Array[String] = []
	if _layout_store():
		for line: String in _store_view.squares_shown("goods"):
			var parts := line.split(" ")
			out.append("%s %s gold %s" % [parts[0], parts[1], parts[2]])
		return out
	for box: Node in _grid.get_children():
		if box is StoreBox:
			var chips := PackedStringArray()
			for chip: Node in (box as StoreBox).chips.get_children():
				chips.append(str(chip.get_meta("words", "")))
			var picked := " picked" if _is_picked(box.kind, box.key) else ""
			out.append("%s %s %s%s" % [box.kind, box.key, " ".join(chips), picked])
	return out


## The name a square's hover shows (tests and the tip).
func box_words(kind: String, key: Variant) -> String:
	if _layout_store():
		var square := _store_view.square_for(kind, key)
		return square.words if square != null else ""
	for box: Node in _grid.get_children():
		if box is StoreBox and box.kind == kind and str(box.key) == str(key):
			return box.words
	return ""


## The picked button pressed: what is asked of the server; nothing picked,
## or more owed than the purse holds, does nothing.
func _confirm() -> void:
	var act := action()
	if not _open or act.is_empty() or not bool(act["ok"]) or not shortfall_words(int(act["gold"]), purse).is_empty() or not near:
		return  # Out of reach (802): never sent, the button dim.
	if giving:
		give_asked.emit(person if person != null else with, gift.keys())
		gift.clear()
	elif not care_pay.is_empty():
		care_asked.emit(with, care_pay)
		care_pay = ""
	elif not jobs_pick.is_empty():
		for slot: Variant in jobs_pick:
			var job := job_at(int(slot))
			order_asked.emit(int(slot), str(job.get("effect", "")), str(job.get("to_id", "")))
		jobs_pick.clear()
	elif not wares_pick.is_empty():
		for id: Variant in wares_pick:
			offer_asked.emit(str(id), int(wares_pick[id]))
		wares_pick.clear()
	else:
		var gives: Array = give.keys()
		var takes: Array = take.keys()
		trade_asked.emit(with, gives, takes, balance_of(gives, takes))
	_total.visible = false
	_rebuild()


## PackPanel's select hook: a left click on one of the player's boxes while
## goods are traded picks it (true: the click is taken, no drag). A stack
## (619, ui's side): a click gives the whole stack, as far as the merchant
## takes, or unpicks it all; a shift-click one more unit, or one fewer when
## all are given.
func _select_mine(mine: bool, index: int, shift := false) -> bool:
	if _open and mine and giving:
		var row := takes_at(index)
		if not row.is_empty():
			toggle_gift(int(row.get("uid", 0)))
		return true  # Giving: a square they don't take does nothing.
	if not _open or not mine or data.is_empty():
		return false
	var entry := pack_entry_at(index)
	if entry.is_empty():
		return false
	var units := stack_units(entry)
	if units.size() <= 1:
		toggle_give(int(entry.get("uid", 0)))
		return true
	var given := given_of(entry)
	if shift:
		if given >= units.size():
			give.erase(units[given - 1])
			_rebuild()
		else:
			toggle_give(units[given])
		return true
	if given > 0:
		for uid: int in units:
			give.erase(uid)
		_rebuild()
		return true
	for uid: int in units:
		var before := give.size()
		toggle_give(uid)
		if give.size() == before:
			break  # Won't buy, or the town has enough: the line says.
	return true


## PackPanel's hover hook: over a stack partly picked, how many are given.
func _hover_mine(mine: bool, index: int) -> void:
	if not _open:
		return
	var entry := pack_entry_at(index) if mine and index >= 0 else {}
	_hover_words = stack_words(given_of(entry), stack_units(entry).size()) if not entry.is_empty() else ""
	_show_words()


func _show_words() -> void:
	if _hover != null:
		_hover.text = _hover_words
		_hover.visible = not _hover_words.is_empty()


func _is_picked(kind: String, key: Variant) -> bool:
	match kind:
		"good":
			return take.has(int(key))
		"ware":
			return wares_pick.has(str(key))
		"care":
			return care_pay == str(key)
		"job":
			return jobs_pick.has(int(key))
		"ready":
			return true  # Its bright frame: a click collects.
	return false


func _rebuild() -> void:
	if not is_node_ready():
		return
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	if not _open:
		if pack != null:
			pack.set_selected([])
			pack.set_prices({})
			pack.held_open = false
			pack.suppressed = false
		_box.visible = false
		_total.visible = false
		if _store_view != null:
			_store_view.visible = false
		return
	if _layout_store():
		# 852: the approved window; it owns the pack while it is open (the separate pack and
		# sheet are not drawn, and come back as they were when it closes).
		if pack != null:
			pack.set_selected([])
			pack.set_prices({})
			pack.held_open = false
			pack.suppressed = true
		_box.visible = false
		_total.visible = false
		_store_view.visible = true
		_hide_tip()
		_store_view.show_state(_store_state())
		_show_words()
		return
	if _store_view != null:
		_store_view.visible = false
	if pack != null:
		pack.suppressed = false
	_title.text = title_words(merchant, str(counter.get("kind", "")) if _counter_work() else "")
	_trusted.visible = data.get("trusted") == true
	_state.text = ASLEEP_WORDS
	_state.visible = person != null and asleep
	_line.visible = person != null and talks
	for child: Node in _asks_box.get_children():
		_asks_box.remove_child(child)
		child.queue_free()
	_asks_box.visible = person != null and not asks.is_empty() and not giving
	_asks_scroll.visible = _asks_box.visible
	for each: Dictionary in ([] as Array[Dictionary] if giving else asks):
		var cost := int(each.get("cost", 0))
		var row := _row(str(each.get("title", each.get("words", ""))), cost if cost > 0 else -1, cost > purse)
		row.pressed.connect(_ask_pressed.bind(str(each.get("id", "")), maxi(cost, 0)))
		_asks_box.add_child(row)
	_size_asks()
	_give_tab.visible = trades and not takes.is_empty()
	_give_tab.text = give_word(takes)
	_give_tab.set_pressed_no_signal(giving)
	_grid.visible = trades and not giving
	_foot_row.visible = trades
	for child: Node in _outcome.get_children():
		_outcome.remove_child(child)
		child.queue_free()
	_outcome.visible = trades and giving
	if giving:
		for words: String in give_lines(gift_rows()):
			var line := Label.new()
			line.text = words
			_outcome.add_child(line)
	for each: Variant in ([] if giving else data.get("goods", [])):
		if each is Dictionary:
			_add_box("good", int(each.get("uid", 0)), str(each.get("id", "")), "", [["gold", int(each.get("price", 0))]],
				Items.name_of(str(each.get("id", ""))))
	for each: Dictionary in ([] as Array[Dictionary] if giving else wares):
		var item := ware_item(each)
		_add_box("ware", str(each.get("id", "")), item, "", [["gold", int(each.get("cost", 0))]], Items.name_of(item))
	var offered := {} if giving else care()
	if not offered.is_empty():
		for pay: String in CARE_PAYS:
			var price := int(offered.get(pay, 0))
			if price <= 0:
				continue
			var held := bool(offered.get("in_care", false))
			var box := _add_box("care", pay, "", "care", [] if held else [[pay, maxi(price - care_given(offered, pay), 0)]], SERVICE_NAMES["care"])
			if held and str(offered.get("by", "")) == pay:
				box.face.add_theme_stylebox_override("panel", PackPanel.selected_style())
			if held or not care_hands(pay) > 0 or pay == "gold" and purse < price:
				box.modulate.a = 0.5
	for each: Variant in ([] if giving else counter.get("jobs", [])):
		if each is Dictionary:
			var effect := str(each.get("effect", ""))
			var pays: Array = [["gold", int(each.get("price", 0))]]
			var materials: Variant = each.get("materials", {})
			if materials is Dictionary:
				for raw: Variant in materials:
					pays.append([_material_item(str(raw)), int(materials[raw])])
			var job_box := _add_box("job", int(each.get("slot", -1)), str(each.get("id", "")), effect, pays, str(SERVICE_NAMES.get(effect, effect)),
				not bool(each.get("ok", true)))
			job_box.set_meta("why", str(each.get("why", "")))
	for each: Variant in counter.get("working", []):
		if each is Dictionary:
			var item := str(each.get("id", ""))
			var working := _add_box("working", int(each.get("uid", 0)), item, str(each.get("effect", "")),
				[["time", time_words(int(each.get("left_seconds", 0)))]], "%s, in hand" % Items.name_of(item).capitalize())
			working.icon.modulate.a = 0.45
	for each: Variant in counter.get("waiting", []):
		if each is Dictionary:
			var item := str(each.get("id", ""))
			# Its own words where the server gives them (734 amended (7): one from the old chests), else ready.
			var words := str(each.get("words", ""))
			_add_box("ready", int(each.get("uid", 0)), item, str(each.get("effect", "")), [],
				words if not words.is_empty() else "%s, ready" % Items.name_of(item).capitalize())
	if _grid.get_child_count() == 0 and not giving:
		var empty := Label.new()
		empty.theme_type_variation = &"Caption"
		empty.add_theme_color_override("font_color", DIM)
		empty.text = empty_words(data) if not data.is_empty() else "asking..."
		_grid.add_child(empty)
	_show_words()
	var act := action()
	var short := shortfall_words(int(act.get("gold", 0)), purse) if not act.is_empty() else ""
	var job_why := ""
	for slot: Variant in jobs_pick:
		if not bool(job_at(int(slot)).get("ok", true)):
			job_why = str(job_at(int(slot)).get("why", ""))
	_button.text = str(act.get("words", "Buy"))
	_button.disabled = act.is_empty() or not bool(act["ok"]) or not short.is_empty() or not near
	_foot.text = short if near else STEP_CLOSER
	_foot.visible = not _foot.text.is_empty()
	var why := job_why if not job_why.is_empty() else str(data.get("why", counter.get("why", "")))
	if not ask_why.is_empty():
		why = ask_why
	_why.text = why
	_why.visible = not why.is_empty() and (trades or not ask_why.is_empty())
	if pack != null and giving:
		# Give: the squares they take lit (a coin where they pay now), the rest dim.
		var slots := []
		var lights := {}
		for slot: int in Items.CARRIED:
			lights[slot] = 0
		for row: Dictionary in takes:
			var at := int(row.get("slot", pack_entry(int(row.get("uid", 0))).get("slot", -1)))
			lights[at] = int(row.get("gold", 0)) if int(row.get("gold", 0)) > 0 else -1
			if gift.has(int(row.get("uid", 0))):
				slots.append(at)
		pack.set_selected(slots)
		pack.set_prices(lights)
		pack.held_open = true
	elif pack != null:
		var slots := []
		for uid: Variant in give:
			slots.append(int(pack_entry(int(uid)).get("slot", -1)))
		pack.set_selected(slots)
		var prices := {}
		for each: Variant in data.get("pack", []):
			if each is Dictionary:
				prices[int(each.get("slot", -1))] = pays_for(int(each.get("uid", 0)))
		pack.set_prices(prices)
		pack.held_open = true
	_box.visible = true


## A counter's material ("ore") as the item its chip pictures ("ore_sack").
static func _material_item(raw: String) -> String:
	for id: String in ["%s_sack" % raw, "%s_bundle" % raw, "%s_bolt" % raw, raw]:
		if Items.exists(id):
			return id
	return raw


## The time left on work in hand, short: "2 min", "40 s".
static func time_words(seconds: int) -> String:
	if seconds >= 60:
		return "%d min" % roundi(seconds / 60.0)
	return "%d s" % maxi(seconds, 1)


## One square: [param item]'s icon (or the service's mark alone), the mark
## of [param service] in its corner over an item, the chips [[kind, amount]]
## over its bottom-right corner; [param short]: the chips in rust.
func _add_box(kind: String, key: Variant, item: String, service: String, pays: Array, words: String, short := false) -> StoreBox:
	var box := StoreBox.new()
	box.window = self
	box.kind = kind
	box.key = key
	box.words = words
	# The square, then its price under it (Jeff: "the price under each item").
	box.custom_minimum_size = PackPanel.SLOT_SIZE + Vector2(0, PRICE_ROW)
	box.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var face := Panel.new()
	face.theme_type_variation = &"Inset"
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.position = Vector2.ZERO
	face.size = PackPanel.SLOT_SIZE
	face.custom_minimum_size = PackPanel.SLOT_SIZE
	box.add_child(face)
	box.face = face
	var picture := TextureRect.new()
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["offset_left", "offset_top"]:
		picture.set(side, PackPanel.ICON_INSET)
	for side: String in ["offset_right", "offset_bottom"]:
		picture.set(side, -PackPanel.ICON_INSET)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if item.is_empty():
		picture.texture = mark_of(service)
	else:
		picture.texture = _icon(item)
	face.add_child(picture)
	box.icon = picture
	if not item.is_empty() and picture.texture == null:
		var label := Label.new()
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		label.add_theme_font_size_override("font_size", PackPanel.CAPTION_SIZE)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.text = Items.short_of(item)  # No icon (headless, not drawn yet): the short name.
		face.add_child(label)
	if not item.is_empty() and not service.is_empty():
		var badge := PanelContainer.new()
		badge.theme_type_variation = &"Chip"
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.offset_right = -4
		badge.offset_top = 4
		var mark := TextureRect.new()
		mark.texture = mark_of(service)
		mark.custom_minimum_size = Vector2.ONE * 44
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(mark)
		face.add_child(badge)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 4)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.position = Vector2(0, PackPanel.SLOT_SIZE.y + PRICE_GAP)
	chips.size = Vector2(PackPanel.SLOT_SIZE.x, CHIP_HEIGHT)
	for pay: Array in pays:
		if str(pay[0]) not in ["gold", "time"]:
			_icon(str(pay[0]))
		var chip := make_chip(str(pay[0]), pay[1], pack.icons if pack != null else null, OUT if short else PRICE)
		chips.add_child(chip)
	box.add_child(chips)
	box.chips = chips
	if _is_picked(kind, key):
		face.add_theme_stylebox_override("panel", PackPanel.selected_style())
	_grid.add_child(box)
	return box


## [param item]'s icon from the pack's ItemIcons, null while it is drawn
## (the squares laid out again once it is) or headless.
func _icon(item: String) -> Texture2D:
	if pack == null or pack.icons == null:
		return null
	var picture := pack.icons.icon(item)
	if picture == null and pack.icons.enabled and not pack.icons.icon_ready.is_connected(_icon_arrived):
		pack.icons.icon_ready.connect(_icon_arrived)
	return picture


func _icon_arrived(_id: String) -> void:
	if not _icons_due:
		_icons_due = true
		_relay_out.call_deferred()


func _relay_out() -> void:
	_icons_due = false
	if _open:
		_rebuild()


## A price chip: a dark chip, a coin for gold (or what is paid: herbs'
## icon, ore's) or nothing for a time, then the number in [param color].
## Its words ("gold 10") in its "words" meta, for tests.
static func make_chip(kind: String, amount: Variant, icons: ItemIcons, color: Color = PRICE) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"Chip"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	if kind == "gold":
		row.add_child(Coin.new())
	elif kind != "time":
		var texture: Texture2D = icons.icon(kind) if icons != null else null
		if texture != null:  # Made only when drawn: an unparented one leaked (ui_test's 18 at exit).
			var picture := TextureRect.new()
			picture.custom_minimum_size = Vector2.ONE * 34
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
			picture.texture = texture
			row.add_child(picture)
	var number := Label.new()
	number.theme_type_variation = &"Caption"
	number.add_theme_color_override("font_color", DIM if kind == "time" else color)
	number.text = str(amount)
	if kind not in ["gold", "time"] and row.get_child_count() == 0:
		number.text = "%s %s" % [amount, Items.short_of(kind).to_lower()]  # No icon (headless, not drawn yet): its name.
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(number)
	chip.set_meta("words", "%s %s" % [kind, amount])
	return chip


## A service's mark (art-kit's own art, art/ui/marks, 3b0a2f3c): "care",
## "bless", "reforge", "mend"; null for another.
func mark_of(service: String) -> Texture2D:
	if not _marks.has(service):
		var path := "res://art/ui/marks/mark_%s.png" % service
		_marks[service] = load(path) if ResourceLoader.exists(path) else null
	return _marks[service]


func _show_tip(box: StoreBox) -> void:
	if box.words.is_empty():
		return
	_tip_words.text = box.words
	_tip_words.add_theme_color_override("font_color", SELECT if box.kind in ["good", "ware"] else UiTheme.color("text"))
	_tip.reset_size()
	var rect := box.get_global_rect()
	_tip.global_position = Vector2(rect.position.x, rect.position.y - _tip.size.y - 6)
	_tip.visible = true
	var why := str(box.get_meta("why", "")) if box.has_meta("why") else ""
	if not why.is_empty():
		_hover_words = why
		_show_words()


func _hide_tip() -> void:
	if _tip != null:
		_tip.visible = false


## The Total pop-up, beside the button while the mouse is on it and
## something is picked.
func _show_total() -> void:
	var act := action()
	if act.is_empty() or (act["total"] as Array).is_empty():
		return
	for child: Node in _total_chip.get_children():
		_total_chip.remove_child(child)
		child.queue_free()
	var short := not shortfall_words(int(act["gold"]), purse).is_empty()
	for pay: Array in act["total"]:
		var kind := str(pay[0])
		if kind == "gold":
			_total_chip.add_child(Coin.new(13))
		else:
			var picture := TextureRect.new()
			picture.custom_minimum_size = Vector2.ONE * 44
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			picture.texture = pack.icons.icon(kind) if pack != null and pack.icons != null else null
			_total_chip.add_child(picture)
		var number := Label.new()
		number.text = total_words(int(pay[1]), bool(act["signed"]))
		number.add_theme_color_override("font_color", OUT if short else PRICE)
		_total_chip.add_child(number)
	_total.reset_size()
	var rect := _button.get_global_rect()
	_total.global_position = Vector2(rect.end.x + GAP, rect.position.y + (rect.size.y - _total.size.y) / 2.0)
	_total.visible = true


## 852: whether the approved store window shows now: a trade (not the chat alone), no
## typing line (a townsperson who hears typed words keeps the old window until the
## townsperson window is redone), and no counter's work or the healer's care.
func _layout_store() -> bool:
	return _open and trades and not talks and not _counter_work() and care().is_empty()


## Whether the counter message has any work to show: jobs, work in hand or work ready. A store's own chest is told as a
## counter of kind "shop" too, with none of them (economy's fish_home tour, v0.1.210: its window was titled "The smith's
## counter"): that is no counter work, and neither the title nor the layout follows it.
func _counter_work() -> bool:
	for key: String in ["jobs", "working", "waiting"]:
		var rows: Variant = counter.get(key, [])
		if rows is Array and not (rows as Array).is_empty():
			return true
	return false


## Whether the store window is open and owns the pack: the separate pack and sheet
## are not drawn meanwhile (Main closes the window when I is pressed).
func owns_pack() -> bool:
	return _layout_store()


## A thing as the lines name it (voice): "a spear", "an axe", "the dagger" for your own piece; no article for a plural name.
static func thing_words(id: String, definite: bool) -> String:
	var name := Items.name_of(id).to_lower()
	if definite:
		return "the " + name
	if name.ends_with("s") and not name.ends_with("ss"):
		return name
	return ("an " if name.substr(0, 1) in ["a", "e", "i", "o", "u"] else "a ") + name


## The state the store window draws (StoreView's shape), from what the window knows.
func _store_state() -> Dictionary:
	var player: GridEntity = pack.player if pack != null else null
	var tabs: Array = [{"id": "store", "text": STORE_TAB, "open": not giving}]
	if not takes.is_empty():
		tabs.append({"id": "donate", "text": DONATE_WORDS, "open": giving})
	if _locker_button != null and _locker_button.visible:
		tabs.append({"id": "locker", "text": LOCKER_TAB, "open": false})
	var goods: Array = []
	if not giving:
		for each: Variant in data.get("goods", []):
			if each is Dictionary:
				var price := int(each.get("price", 0))
				goods.append({"kind": "good", "key": int(each.get("uid", 0)), "item": str(each.get("id", "")),
					"words": Items.name_of(str(each.get("id", ""))), "price": price, "short": price > purse})
		for each: Dictionary in wares:
			var item := ware_item(each)
			var cost := int(each.get("cost", 0))
			goods.append({"kind": "ware", "key": str(each.get("id", "")), "item": item, "words": Items.name_of(item),
				"price": cost, "short": cost > purse})
	var mine: Array = []
	if is_instance_valid(player):
		for slot: int in World.pack_slots(player):
			if slot >= player.slots.size():
				continue
			var item := str(player.slots[slot])
			var spec := {"kind": "mine", "key": slot, "item": item, "words": Items.name_of(item) if not item.is_empty() else "",
				"price": -1, "count": World.slot_count(player, slot) if not item.is_empty() else 0}
			if not item.is_empty():
				if giving:
					var row := takes_at(slot)
					spec["lit"] = not row.is_empty()
					if not row.is_empty() and int(row.get("gold", 0)) > 0:
						spec["price"] = int(row["gold"])
				else:
					var entry := pack_entry_at(slot)
					var row := takes_at(slot)
					if not entry.is_empty() and pays_for(int(entry.get("uid", 0))) > 0:
						spec["price"] = pays_for(int(entry.get("uid", 0)))
					elif entry.is_empty() and not row.is_empty() and int(row.get("gold", 0)) > 0:
						spec["price"] = int(row["gold"])  # A keeper with no stock of his own who pays for a trophy (Rolf, economy): a price on the square.
			mine.append(spec)
	var foot := _foot_text
	var refused := _foot_refused
	if asleep and person != null:
		foot = ASLEEP_LINE % merchant
		refused = true
	elif not near:
		foot = STEP_CLOSER
		refused = true
	return {"title": title_words(merchant, ""), "trusted": data.get("trusted") == true, "tabs": tabs,
		"goods_head": ("%s's goods" % merchant if not merchant.is_empty() else "Goods") if not giving else "",
		"goods": goods, "mine_head": "Your pack", "mine": mine, "gold": purse,
		"lines": _donate_lines(), "foot": foot, "refused": refused,
		"load_share": ((player.load_arms + player.load_body) / maxf(World.load_capacity(player), 0.001)) if is_instance_valid(player) else 0.0,
		"load_words": "
".join(PackPanel.load_lines(player)) if is_instance_valid(player) else ""}


## Donate: what handing over the thing the pointer is on does, voice's lines (one a thing), else none.
func _donate_lines() -> Array:
	if not giving or not _store_over.begins_with("mine:"):
		return []
	var row := takes_at(int(_store_over.get_slice(":", 1)))
	return give_lines([row]) if not row.is_empty() else []


## What the foot line says for a thing of yours [param id] the keeper won't take: where it goes when the server
## said ("Pelts and trophies go to the tanner."), else "Rolf won't take that.".
func _wont_take_words(id: String) -> String:
	var pointed := str(points.get(id, ""))
	return pointed if not pointed.is_empty() else WONT_TAKE_LINE % _keeper_name()


## Where the keeper's points are read from: Main passes the server's with each offers message.
func set_points(given: Dictionary) -> void:
	points = given.duplicate()


## The foot line says [param words] ([param refused]: in rust).
func say_foot(words: String, refused := false) -> void:
	_foot_text = words
	_foot_refused = refused
	if _open:
		_rebuild()


## What [param body], the keeper, just said (Main's speech hook): a refusal in words
## (his "That's 3 gold, friend.") is the answer to the click when the purse does not move.
func keeper_said(body: GridEntity, words: String) -> void:
	if _open and (body == with or body == person):
		_said = {"text": words, "at": Time.get_ticks_msec()}


## A click the server will answer: the line shown once the purse or the squares change.
func _expect(pending: Dictionary) -> void:
	pending["purse"] = purse
	pending["slots"] = Array(pack.player.slots).duplicate() if pack != null and is_instance_valid(pack.player) else []
	pending["at"] = Time.get_ticks_msec()
	_pending = pending


## Whether the answer to the pending click has come (the purse moved, the thing left its
## square): its line, and the cue.
func _check_answer() -> void:
	if _pending.is_empty():
		return
	var uid := int(_pending.get("uid", 0))
	var money := false
	var gone := false
	match str(_pending.get("kind", "")):
		"ware":
			money = purse < int(_pending["purse"]) or bool(_pending.get("free", false))
		"good":
			money = purse < int(_pending["purse"]) or not goods_have(uid)
		"mine":
			money = takes_row(uid).is_empty() if giving else (pack_entry(uid).is_empty() or purse > int(_pending["purse"]))
	# The line is said with the pack: the purse and the squares come as two messages, so it waits for
	# both (the thing in the pack, or out of it) and, if the squares never change, for ANSWER_WAIT_MSEC.
	var changed: bool = pack != null and is_instance_valid(pack.player) and Array(pack.player.slots) != _pending.get("slots", [])
	gone = changed or Time.get_ticks_msec() - int(_pending.get("at", 0)) >= PACK_WAIT_MSEC
	if not (money and gone):
		return
	var text := str(_pending.get("text", ""))
	var cue := str(_pending.get("cue", ""))
	_pending = {}
	_answered_msec = Time.get_ticks_msec()
	_foot_text = text
	_foot_refused = false
	if not cue.is_empty():
		told.emit(cue)
	if _open:
		_rebuild()


## The words of a trade the server told with its gain ("trade": "bought" or "sold" on the
## "reward" message, economy's 856) while this window is open: the foot says them, once,
## in place of the line made here (a free thing reads as the server's float reads, never
## "for 0 gold"). They take the foot if it already shows a trade line, else the click
## still waiting for its answer.
func trade_words(words: String, trade: String) -> void:
	if not _open or words.is_empty():
		return
	var kind := str(_pending.get("kind", ""))
	if not kind.is_empty() and (kind == "mine") == (trade == "sold"):
		_pending["text"] = words
		return
	if Time.get_ticks_msec() - _answered_msec < ANSWER_MSEC:
		_foot_text = words
		_foot_refused = false
		_rebuild()


## Each frame: a click not answered in time stops being expected; a keeper's refusal in
## words, with no change to the purse, is the answer.
func _expire_pending() -> void:
	if _pending.is_empty():
		return
	_check_answer()  # The squares may have changed since the purse did.
	if _pending.is_empty():
		return
	var now := Time.get_ticks_msec()
	var at := int(_pending.get("at", now))
	if int(_said["at"]) >= at and now - at >= SAID_MSEC:
		var key: Variant = _pending.get("key")
		var kind := str(_pending.get("kind", ""))
		_pending = {}
		_refuse(kind, key, str(_said["text"]))
	elif now - at > ANSWER_MSEC:
		_pending = {}


## A click that cannot go through: the foot line says why in rust, the square shows its
## rust rim, nothing moves, and the error cue sounds.
func _refuse(kind: String, key: Variant, words: String) -> void:
	_pending = {}
	if _store_view != null:
		_store_view.flash_refused(kind, key)
	refused.emit(words)
	say_foot(words, true)


## Out of reach or the keeper asleep: said and refused (true), else false.
func _stopped(kind: String, key: Variant) -> bool:
	if asleep and person != null:
		_refuse(kind, key, ASLEEP_LINE % merchant)
		return true
	if not near:
		_refuse(kind, key, STEP_CLOSER)
		return true
	return false


## The keeper's name for a refusal line.
func _keeper_name() -> String:
	return merchant if not merchant.is_empty() else "They"


func _on_store_square(kind: String, key: Variant) -> void:
	if not _open:
		return
	match kind:
		"ware":
			_buy_ware(str(key))
		"good":
			_buy_good(int(key))
		"mine":
			if giving:
				_donate(int(key))
			else:
				_sell(int(key))


## One click on a ware: bought at its price, or the line says why not.
func _buy_ware(id: String) -> void:
	var entry := ware_entry(id)
	if entry.is_empty() or _stopped("ware", id):
		return
	var cost := int(entry.get("cost", 0))
	var short := shortfall_words(-cost, purse)
	if not short.is_empty():
		_refuse("ware", id, short)
		return
	# A free ware (the first rod) never says "for 0 gold": its words are the server's float's (trade_words).
	_expect({"kind": "ware", "key": id, "cue": "bought", "free": cost <= 0,
		"text": BOUGHT_LINE % [thing_words(ware_item(entry), false), cost] if cost > 0 else ""})
	offer_asked.emit(id, cost)


## One click on a good of a counter's stock: bought, or the line says why not.
func _buy_good(uid: int) -> void:
	var entry := goods_entry(uid)
	if entry.is_empty() or _stopped("good", uid):
		return
	var price := int(entry.get("price", 0))
	var short := shortfall_words(-price, purse)
	if not short.is_empty():
		_refuse("good", uid, short)
		return
	_expect({"kind": "good", "key": uid, "uid": uid, "cue": "bought", "free": price <= 0,
		"text": BOUGHT_LINE % [thing_words(str(entry.get("id", "")), false), price] if price > 0 else ""})
	trade_asked.emit(with, [], [uid], balance_of([], [uid]))


## One click on a thing of yours: sold for what they pay (a unit of a stack), or the line says why not.
func _sell(slot: int) -> void:
	var entry := pack_entry_at(slot)
	if _stopped("mine", slot):
		return
	if entry.is_empty():
		var paid := takes_at(slot)  # A keeper with no stock of his own who pays for a trophy (Rolf): a sale, by his takes row.
		if not paid.is_empty() and int(paid.get("gold", 0)) > 0:
			var paid_id := str(paid.get("what", ""))
			_expect({"kind": "mine", "key": slot, "uid": int(paid.get("uid", 0)), "cue": "sold", "text": SOLD_LINE % [thing_words(paid_id, false), int(paid["gold"])]})
			give_asked.emit(person if person != null else with, [int(paid.get("uid", 0))])
			return
		if pack != null and is_instance_valid(pack.player) and slot < pack.player.slots.size() and not str(pack.player.slots[slot]).is_empty():
			_refuse("mine", slot, _wont_take_words(str(pack.player.slots[slot])))
		return
	var uid := int(entry.get("uid", 0))
	var id := str(entry.get("id", ""))
	var pay := pays_for(uid)
	if pay <= 0:
		_refuse("mine", slot, _wont_take_words(id))
		return
	if up_to(id) < 1:
		_refuse("mine", slot, ENOUGH_LINE)
		return
	_expect({"kind": "mine", "key": slot, "uid": uid, "cue": "sold", "text": SOLD_LINE % [thing_words(id, false), pay]})
	trade_asked.emit(with, [uid], [], balance_of([uid], []))


## One click on a thing of yours on Donate: handed over, or the line says they won't take it.
func _donate(slot: int) -> void:
	var row := takes_at(slot)
	if _stopped("mine", slot):
		return
	if row.is_empty():
		_refuse("mine", slot, _wont_take_words(str(pack.player.slots[slot]) if pack != null and is_instance_valid(pack.player) and slot < pack.player.slots.size() else ""))
		return
	var uid := int(row.get("uid", 0))
	var id := str(row.get("what", ""))
	var gold := int(row.get("gold", 0))
	var text := SOLD_LINE % [thing_words(id, false), gold] if gold > 0 \
			else HANDED_BACK_LINE % thing_words(id, true) if bool(row.get("starter", false)) \
			else LEFT_LINE % thing_words(id, true)
	_expect({"kind": "mine", "key": slot, "uid": uid, "cue": "sold" if gold > 0 else "left", "text": text})
	give_asked.emit(person if person != null else with, [uid])


func _on_store_tab(id: String) -> void:
	match id:
		"store":
			set_giving(false)
		"donate":
			set_giving(true)
		"locker":
			# Landing A: the locker opens beside the pack, the store window out of the way.
			var keeper := with
			close()
			if keeper != null:
				locker_asked.emit(keeper)


func _on_store_hover(kind: String, key: Variant, words: String, rect: Rect2) -> void:
	if words.is_empty():
		_store_over = ""
		_hide_tip()
	else:
		_store_over = "%s:%s" % [kind, key]
		_tip_words.text = words
		_tip.reset_size()
		_tip.global_position = Vector2(rect.position.x, rect.position.y - _tip.size.y - 6)
		_tip.visible = true
	if giving and _store_view != null:
		_store_view.set_lines(_donate_lines())


func _process(_delta: float) -> void:
	var began := Time.get_ticks_usec()
	_place()
	UiCost.add("barter", Time.get_ticks_usec() - began)


## Beside the pack, to its left, its foot on the pack's (ShopPanel's
## place, 280); hidden with the pack.
func _place() -> void:
	if _open and not is_instance_valid(with) and with != null:
		close()
	_expire_pending()
	if _store_view != null and _store_view.visible:
		# 852: at the screen's bottom right, clear of the player and of the right-hand column.
		_store_view.reset_size()
		var screen := get_viewport_rect().size
		var margin := float(UiTheme.constant("margin"))
		_store_view.position = Vector2(screen.x - _store_view.size.x - margin, screen.y - _store_view.size.y - margin)
		_box.visible = false
		_total.visible = false
		return
	var pack_shown := pack != null and pack.visible
	_box.visible = _open and pack_shown
	if not _box.visible:
		_total.visible = false
		_tip.visible = false
		return
	_box.reset_size()
	_box.global_position = pack.beside(_box.size, GAP)  # Clear of the sheet too (787).
	if _focus_due:
		focus_line()
