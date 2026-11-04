class_name TownSheet
extends Control
## The town window (decision 768; Jeff: "town needs to have a status page
## that shows towns supply level ... contribution transactions ... similar to
## the store"; round 2 approved, C:/dev/review/town_status/round2). One
## window for a town, two tabs (voice's words):
## - "Stores", the front page as approved: the town's stock as squares in the
##   store's look, each with its level up the left edge (rust when short, brass
##   while filling, green at enough) and "have/enough" in a chip; the building
##   going up, a coin square that a click puts 10 gold toward (a right click
##   takes 10 back) and its fund as a bar; a column of status: the player's
##   regard (its ladder word, a rise or fall for its last move), the town's state (Under
##   threat, Thriving, Healer away, Hungry, a building going up) and the
##   zone's asks (lit while open). What the player's own last acts moved is
##   marked with a small rise (economy's "recent"). At the town's store or
##   depot (economy's "at") the pack shows what the town pays for each thing
##   and a click picks it; one button, "Donate (2 items)" or "Donate (20
##   gold)", its Total on hover (the store's, 765), sends "contribute" {town,
##   give, gold}.
## - "Ledger", the town status sheet of 624 (ui's side; Jeff, 2026-10-22: "a
##   town status sheet... the population, the faction, the needs, hunger
##   etc."): the heading "Umbrage, a village", who holds it, its buildings,
##   its people from the Resident bodies seen, the dole line, economy's rows
##   (economy_lines) and the season and day, in words.
## N opens it for the town whose ground the player stands on, a town's row in
## the known world for that town, read-only anywhere; Esc or N closes it.
## Beside the pack while the pack shows (the store's place), else in the
## middle. The look is the shared theme's (UiTheme, docs/ui_style.md); the
## squares and chips are the store's (BarterPanel).

const WIDTH := 980.0
## A building job's progress as a word (the "town" message's "progress").
const BEGUN := 0.34
const HALF := 0.67
## Stock squares a line.
const COLUMNS := 5
## What a click on the coin square puts toward the building.
const FUND_STEP := 10
## The gap between the window and the pack.
const GAP := 20
## Voice's words (768).
const TAB_WORDS := ["Stores", "Ledger"]
const ENOUGH_WORDS := "The town has enough of that."
const NO_USE_WORDS := "The town has no use for that."

## Donate pressed: the town, the player's uids, the gold (Main sends
## "contribute").
signal donate_asked(town: String, give: Array, gold: int)

## The pack panel the window sits beside (its boxes the player's side).
var pack: PackPanel
## The town shown (its id, "<zone>/<key>"), "" for none.
var town := ""
## Economy's town_sheet message as last shown ({} till it comes).
var sheet: Dictionary = {}
## The tab shown: 0 Stores, 1 Ledger.
var tab := 0
## Picked: the player's uids to give, the gold toward the building.
var give: Dictionary = {}
var gift := 0

var _box: PanelContainer
var _title: Label
var _tabs: Array[Button] = []
var _stores: HBoxContainer
var _stock: GridContainer
var _asking: Label
var _build_row: HBoxContainer
var _fund_box: TownBox
var _build_name: Label
var _fund_bar: FundBar
var _fund_words: Label
var _regard_mark: Diamond
var _regard_word: Label
var _regard_step: Step
var _state: GridContainer
var _asks: GridContainer
var _hover: Label
var _foot: HBoxContainer
var _button: Button
var _short: Label
var _ledger: VBoxContainer
var _held: Label
var _people: Label
var _buildings: Label
var _dole: Label
var _economy: VBoxContainer
var _when: Label
var _none: Label
var _total: PanelContainer
var _total_chip: HBoxContainer
var _tip: PanelContainer
var _tip_words: Label
var _hover_words := ""
var _marks: Dictionary = {}
var _prev_select: Callable
var _prev_hover: Callable
## Whether the window holds the pack open and shows the town's prices on it.
var _holding := false
var _icons_due := false


## One square of the Stores page: a stock id ("stock"), the coin square
## ("fund"), a state or an ask (by index) or the regard. Hovered for its
## name; the stock's level and the rise drawn over it.
class TownBox:
	extends Panel
	var window: TownSheet
	var kind := ""
	var key: Variant
	var words := ""
	var icon: TextureRect
	var overlay: Control
	var chips: VBoxContainer
	## The stock's level (have / enough, short), -1 for none.
	var level := -1.0
	var short := 0.0
	## A small rise in the corner: the player's own act moved it.
	var rose := false
	## A drawn sign in place of a picture: "thriving", "threatened", "away".
	var drawn := ""

	func _ready() -> void:
		mouse_entered.connect(func() -> void: window._show_tip(self))
		mouse_exited.connect(func() -> void: window._hide_tip())

	func _gui_input(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			window.click_box(kind, key, click.button_index == MOUSE_BUTTON_RIGHT)
			accept_event()

	func draw_over() -> void:
		var area := overlay.size
		if level >= 0.0:
			var bar := Rect2(8, 10, 10, area.y - 20)
			overlay.draw_rect(bar, Color(0.1, 0.08, 0.06, 0.85))
			var filled := bar.size.y * clampf(level, 0.0, 1.0)
			if filled > 0.0:
				overlay.draw_rect(Rect2(bar.position.x + 2, bar.end.y - filled, 6, filled - 2), TownSheet.level_color(short))
		if rose:
			TownSheet.draw_rise(overlay, Vector2(area.x - 26, 22), 12.0, UiTheme.color("brass_bright"))
		match drawn:
			"thriving":
				for k in 3:
					TownSheet.draw_rise(overlay, Vector2(area.x / 2, area.y / 2 + 26 - k * 24), 24.0, UiTheme.color("friend"))
			"threatened":
				var middle := area / 2.0
				var rust := UiTheme.color("rust")
				var shield := PackedVector2Array([middle + Vector2(-32, -36), middle + Vector2(32, -36), middle + Vector2(32, 0),
					middle + Vector2(0, 40), middle + Vector2(-32, 0), middle + Vector2(-32, -36)])
				overlay.draw_polyline(shield, rust, 5.0, true)
				overlay.draw_line(middle + Vector2(0, -24), middle + Vector2(0, 6), rust, 7.0)
				overlay.draw_circle(middle + Vector2(0, 20), 5.0, rust)
			"away":
				overlay.draw_line(Vector2(24, area.y - 24), Vector2(area.x - 24, 24), UiTheme.color("rust"), 6.0, true)


## The regard's mark: a diamond in the ladder word's colour.
class Diamond:
	extends Control
	var colour := Color.WHITE

	func _init() -> void:
		custom_minimum_size = Vector2(52, 52)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		var r := 22.0
		var points := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		draw_colored_polygon(points, colour)
		points.append(points[0])
		draw_polyline(points, UiTheme.color("brass").darkened(0.4), 2.0, true)


## The regard's last move (economy's "last": -1, 0 or 1): a small rise in
## bright brass or a fall in rust, nothing for none.
class Step:
	extends Control
	var direction := 0

	func _init() -> void:
		custom_minimum_size = Vector2(36, 52)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if direction == 0:
			return
		var c := size / 2.0
		var colour := UiTheme.color("brass_bright") if direction > 0 else UiTheme.color("rust")
		var tip := Vector2(0, -8 * direction)
		var foot := Vector2(14, 8 * direction)
		draw_polyline(PackedVector2Array([c + Vector2(-foot.x, foot.y), c + tip, c + foot]), colour, 5.0, true)


## The building fund's bar: what is in it in brass, the gift picked bright.
class FundBar:
	extends Control
	var fund := 0
	var wants := 1
	var gift := 0

	func _init() -> void:
		custom_minimum_size = Vector2(360, 30)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var inner := Rect2(Vector2(3, 3), size - Vector2(6, 6))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.08, 0.06, 0.85))
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.color("brass").darkened(0.4), false, 2.0)
		var whole := maxf(float(wants), 1.0)
		var have := inner.size.x * clampf(fund / whole, 0.0, 1.0)
		draw_rect(Rect2(inner.position, Vector2(have, inner.size.y)), UiTheme.color("brass"))
		var more := inner.size.x * clampf(gift / whole, 0.0, 1.0 - fund / whole)
		if more > 0.0:
			draw_rect(Rect2(inner.position + Vector2(have, 0), Vector2(more, inner.size.y)), UiTheme.color("brass_bright"))


func _init() -> void:
	name = "TownSheet"
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_box = PanelContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_STOP
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiTheme.constant("row"))
	_box.add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UiTheme.constant("row"))
	column.add_child(head)
	_title = Label.new()
	_title.theme_type_variation = &"Title"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var group := ButtonGroup.new()
	for i in TAB_WORDS.size():
		var button := Button.new()
		button.text = TAB_WORDS[i]
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(show_tab.bind(i))
		head.add_child(button)
		_tabs.append(button)
	_build_stores(column)
	_build_ledger(column)
	_hover = Label.new()
	_hover.theme_type_variation = &"Caption"
	_hover.add_theme_color_override("font_color", BarterPanel.DIM)
	_hover.visible = false
	column.add_child(_hover)
	_foot = HBoxContainer.new()
	_foot.add_theme_constant_override("separation", UiTheme.constant("row"))
	column.add_child(_foot)
	_button = Button.new()
	_button.focus_mode = Control.FOCUS_NONE
	_button.pressed.connect(_confirm)
	_button.mouse_entered.connect(_show_total)
	_button.mouse_exited.connect(func() -> void: _total.visible = false)
	_foot.add_child(_button)
	_short = Label.new()
	_short.theme_type_variation = &"Caption"
	_short.add_theme_color_override("font_color", BarterPanel.OUT)
	_short.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_foot.add_child(_short)
	add_child(_box)
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
	_tip = PanelContainer.new()
	_tip.theme_type_variation = &"Tip"
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	_tip_words = Label.new()
	_tip.add_child(_tip_words)
	add_child(_tip)
	if pack != null:
		# The store's hooks stay underneath: the window takes a click only
		# while it holds the pack (at the town's store or depot).
		_prev_select = pack.select_hook
		_prev_hover = pack.hover_hook
		pack.select_hook = _select_mine
		pack.hover_hook = _hover_mine
	visibility_changed.connect(_on_visibility)
	_rebuild()


func _build_stores(column: VBoxContainer) -> void:
	_stores = HBoxContainer.new()
	_stores.add_theme_constant_override("separation", UiTheme.constant("section"))
	column.add_child(_stores)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", UiTheme.constant("section"))
	_stores.add_child(left)
	_stock = GridContainer.new()
	_stock.columns = COLUMNS
	_stock.add_theme_constant_override("h_separation", UiTheme.constant("slot_gap"))
	_stock.add_theme_constant_override("v_separation", UiTheme.constant("slot_gap"))
	left.add_child(_stock)
	_asking = Label.new()
	_asking.theme_type_variation = &"Caption"
	_asking.add_theme_color_override("font_color", BarterPanel.DIM)
	left.add_child(_asking)
	_build_row = HBoxContainer.new()
	_build_row.add_theme_constant_override("separation", UiTheme.constant("slot_gap"))
	left.add_child(_build_row)
	_fund_box = _make_box("fund", "fund", "")
	_fund_box.icon.texture = null
	var coin := BarterPanel.Coin.new(34)
	coin.set_anchors_preset(Control.PRESET_CENTER)
	coin.grow_horizontal = Control.GROW_DIRECTION_BOTH
	coin.grow_vertical = Control.GROW_DIRECTION_BOTH
	_fund_box.add_child(coin)
	_fund_box.move_child(coin, 1)
	_build_row.add_child(_fund_box)
	var build_words := VBoxContainer.new()
	build_words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build_words.alignment = BoxContainer.ALIGNMENT_CENTER
	build_words.add_theme_constant_override("separation", 8)
	_build_row.add_child(build_words)
	_build_name = Label.new()
	build_words.add_child(_build_name)
	_fund_bar = FundBar.new()
	build_words.add_child(_fund_bar)
	var fund_row := HBoxContainer.new()
	fund_row.add_theme_constant_override("separation", 6)
	fund_row.add_child(BarterPanel.Coin.new())
	_fund_words = Label.new()
	_fund_words.theme_type_variation = &"Caption"
	_fund_words.add_theme_color_override("font_color", BarterPanel.PRICE)
	fund_row.add_child(_fund_words)
	build_words.add_child(fund_row)
	_stores.add_child(VSeparator.new())
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", UiTheme.constant("section"))
	_stores.add_child(right)
	var regard := HBoxContainer.new()
	regard.add_theme_constant_override("separation", 12)
	regard.mouse_filter = Control.MOUSE_FILTER_STOP
	regard.mouse_entered.connect(func() -> void: _tip_at(regard, "Regard"))
	regard.mouse_exited.connect(_hide_tip)
	_regard_mark = Diamond.new()
	regard.add_child(_regard_mark)
	_regard_word = Label.new()
	_regard_word.theme_type_variation = &"Heading"
	regard.add_child(_regard_word)
	_regard_step = Step.new()
	regard.add_child(_regard_step)
	right.add_child(regard)
	for i in 2:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", UiTheme.constant("slot_gap"))
		grid.add_theme_constant_override("v_separation", UiTheme.constant("slot_gap"))
		right.add_child(grid)
		if i == 0:
			_state = grid
		else:
			_asks = grid


func _build_ledger(column: VBoxContainer) -> void:
	_ledger = VBoxContainer.new()
	_ledger.add_theme_constant_override("separation", UiTheme.constant("row"))
	_ledger.custom_minimum_size = Vector2(WIDTH, 0)
	column.add_child(_ledger)
	_none = _line(_ledger)
	_held = _line(_ledger)
	_people = _line(_ledger)
	_buildings = _line(_ledger)
	_dole = _line(_ledger)
	_economy = VBoxContainer.new()
	_economy.add_theme_constant_override("separation", UiTheme.constant("row"))
	_ledger.add_child(_economy)
	_when = _line(_ledger)
	_when.add_theme_color_override("font_color", UiTheme.color("text_dim"))


func _line(column: VBoxContainer) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(label)
	return label


## The window for town [param id] (Main's town_states key), named [param
## town_name] (the known world's place words), at [param stage] ("" before
## 591's stages); held by [param holder] (the known world's faction words,
## "" for nobody); its [param buildings] as the "town" message has them;
## [param trades] the trade of each resident body seen on its ground, or
## null from elsewhere; [param dole] the dole line as the town said it;
## [param season] and [param day] as the HUD knows them; [param given]
## economy's "town_sheet" message for it ({} till it comes). No town: the
## window says so.
func show_town(id: String, town_name: String, stage: String, holder: String, buildings: Dictionary, trades: Variant,
		dole: String, season: String, day: int, given: Dictionary = {}) -> void:
	if id != town or not bool(given.get("at", false)):
		_clear_picks()  # Another town, or away from its store: nothing stays picked.
	town = id
	sheet = given
	var known := not id.is_empty()
	_title.text = title_words(town_name, stage) if known else "No town"
	_none.visible = not known
	_none.text = none_words() if not known else ""
	_held.text = held_words(holder) if known else ""
	_held.visible = known and not _held.text.is_empty()
	_people.text = people_words(trades) if known else ""
	_people.visible = known
	_buildings.text = buildings_words(buildings) if known else ""
	_buildings.visible = known and not _buildings.text.is_empty()
	_dole.text = dole.strip_edges() if known else ""
	_dole.visible = known and not _dole.text.is_empty()
	for child in _economy.get_children():
		_economy.remove_child(child)  # Gone now, not at the frame's end: a second show in the same frame reads clean.
		child.queue_free()
	if known:
		for words in economy_lines(sheet):
			var line := Label.new()
			line.text = words
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_economy.add_child(line)
	_when.text = when_words(season, day) if known else ""
	_when.visible = known
	for uid: Variant in give.keys():
		if pack_entry(int(uid)).is_empty() or pays_for(int(uid)) <= 0:
			give.erase(uid)
	gift = mini(gift, gift_room())
	_rebuild()


## Tab [param index] shown: 0 Stores, 1 Ledger.
func show_tab(index: int) -> void:
	tab = clampi(index, 0, TAB_WORDS.size() - 1)
	_hide_tip()
	_rebuild()


## Whether the player stands at the town's store or depot (economy's "at"):
## only then does Donate work.
func is_at() -> bool:
	return bool(sheet.get("at", false)) and not town.is_empty()


## The player's pack entry for [param uid] in economy's "pack" (765's
## form: {slot, uid, uids, id, count}), {} for none.
func pack_entry(uid: int) -> Dictionary:
	for each: Variant in sheet.get("pack", []):
		if each is Dictionary and (int(each.get("uid", 0)) == uid or BarterPanel.stack_units(each).has(uid)):
			return each
	return {}


func pack_entry_at(slot: int) -> Dictionary:
	for each: Variant in sheet.get("pack", []):
		if each is Dictionary and int(each.get("slot", -1)) == slot:
			return each
	return {}


## What the town pays for the player's [param uid] (economy's "pays"
## {id: {gold, up_to}}), 0 when it takes none.
func pays_for(uid: int) -> int:
	var entry := pack_entry(uid)
	var pays: Variant = sheet.get("pays", {})
	if entry.is_empty() or not pays is Dictionary or not pays.has(entry.get("id", "")):
		return 0
	var row: Variant = pays[entry["id"]]
	return int(row.get("gold", 0)) if row is Dictionary else int(row)


## How many of [param id] the town takes now (its "up_to"), a large number
## when it does not say.
func up_to(id: String) -> int:
	var pays: Variant = sheet.get("pays", {})
	if not pays is Dictionary or not pays.has(id):
		return 0
	var row: Variant = pays[id]
	return int(row.get("up_to", 1000000)) if row is Dictionary else 1000000


## The gold the coin square can still put toward the building: the purse,
## as far as the building still wants.
func gift_room() -> int:
	var build: Variant = sheet.get("build", {})
	if not build is Dictionary or (build as Dictionary).is_empty():
		return 0
	var room := maxi(int(build.get("wants", 0)) - int(build.get("fund", 0)), 0)
	return mini(room, maxi(int(sheet.get("gold", 0)), 0))


## What the picks come to: {words, total ([[kind, amount]]), gold}; {} for
## none.
func action() -> Dictionary:
	if gift > 0:
		return {"words": "Donate (%d gold)" % gift, "total": [["gold", gift]], "gold": gift}
	if give.is_empty():
		return {}
	var paid := 0
	for uid: Variant in give:
		paid += pays_for(int(uid))
	return {"words": BarterPanel.button_words("Donate", give.size()), "total": [["gold", paid]], "gold": 0}


## A click on one of the Stores squares: the coin square puts FUND_STEP
## toward the building ([param back]: takes it back).
func click_box(kind: String, _key: Variant, back := false) -> void:
	if kind != "fund" or not is_at():
		return
	if back:
		gift = maxi(gift - FUND_STEP, 0)
	else:
		give.clear()
		gift = mini(gift + FUND_STEP, gift_room())
	_rebuild()


## A click on one of the player's things (by uid): picked to donate, or
## unpicked; one the town takes none of, or past its up_to, stays unpicked
## and the line under the page says why.
func toggle_give(uid: int) -> void:
	if not is_at():
		return
	if give.has(uid):
		give.erase(uid)
		_rebuild()
		return
	var entry := pack_entry(uid)
	if entry.is_empty():
		return
	if pays_for(uid) <= 0:
		_hover_words = NO_USE_WORDS
		_rebuild()
		return
	var same := 0
	for other: Variant in give:
		if str(pack_entry(int(other)).get("id", "")) == str(entry.get("id", "")):
			same += 1
	if same >= up_to(str(entry.get("id", ""))):
		_hover_words = ENOUGH_WORDS
		_rebuild()
		return
	gift = 0
	give[uid] = true
	_rebuild()


func _clear_picks() -> void:
	give.clear()
	gift = 0
	_hover_words = ""


func _confirm() -> void:
	var act := action()
	if act.is_empty() or not is_at():
		return
	donate_asked.emit(town, give.keys(), gift)
	_clear_picks()
	_total.visible = false
	_rebuild()


## PackPanel's select hook: while the window holds the pack, a click on one
## of the player's things picks it (a stack: all of it, as far as the town
## takes, or unpicks it all; shift one more); otherwise the store's.
func _select_mine(mine: bool, index: int, shift := false) -> bool:
	if not (visible and _holding and tab == 0):
		return _prev_select.call(mine, index, shift) if _prev_select.is_valid() else false
	if not mine:
		return false
	var entry := pack_entry_at(index)
	if entry.is_empty():
		return false
	var units := BarterPanel.stack_units(entry)
	var given := 0
	for uid: int in units:
		if give.has(uid):
			given += 1
	if units.size() <= 1:
		toggle_give(int(entry.get("uid", 0)))
	elif shift and given < units.size():
		toggle_give(units[given])
	elif given > 0:
		for uid: int in units:
			give.erase(uid)
		_rebuild()
	else:
		for uid: int in units:
			var before := give.size()
			toggle_give(uid)
			if give.size() == before:
				break
	return true


func _hover_mine(mine: bool, index: int) -> void:
	if not (visible and _holding):
		if _prev_hover.is_valid():
			_prev_hover.call(mine, index)
		return
	var entry := pack_entry_at(index) if mine and index >= 0 else {}
	var given := 0
	for uid: int in BarterPanel.stack_units(entry):
		if give.has(uid):
			given += 1
	_hover_words = BarterPanel.stack_words(given, BarterPanel.stack_units(entry).size()).replace("give", "donate") if not entry.is_empty() else ""
	_show_words()


func _on_visibility() -> void:
	if not visible:
		_clear_picks()
		_hide_tip()
		if _total != null:
			_total.visible = false
		_release_pack()
	else:
		_rebuild()


func _release_pack() -> void:
	if _holding and pack != null:
		pack.set_selected([])
		pack.set_prices({})
		pack.held_open = false
	_holding = false


func _rebuild() -> void:
	if not is_node_ready():
		return
	for i in _tabs.size():
		_tabs[i].set_pressed_no_signal(i == tab)
	_stores.visible = tab == 0
	_ledger.visible = tab == 1
	for grid: GridContainer in [_stock, _state, _asks]:
		for child: Node in grid.get_children():
			grid.remove_child(child)
			child.queue_free()
	var stock: Array = sheet.get("stock", []) if sheet.get("stock") is Array else []
	var recent := recent_ids()
	for each: Variant in stock:
		if not each is Dictionary:
			continue
		var id := str(each.get("id", ""))
		var have := int(each.get("have", 0))
		var enough := int(each.get("enough", 0))
		var box := _make_box("stock", id, stock_words(id))
		var picture := str(each.get("item", id))
		box.icon.texture = _icon(picture)
		if box.icon.texture == null:
			_caption(box, stock_words(id))
		var short := float(each.get("short", 1.0 - float(have) / enough if enough > 0 else 0.0))
		box.level = float(have) / enough if enough > 0 else 1.0
		box.short = short
		box.rose = recent.has(id)
		if have == 0:
			box.icon.modulate.a = 0.45
		if short >= 0.5:
			_frame(box, BarterPanel.OUT, 3)
		box.chips.add_child(BarterPanel.make_chip("time", "%d/%d" % [have, enough], null))
		_stock.add_child(box)
	_asking.text = str(sheet.get("why", "")).strip_edges() if sheet.has("why") else ("" if not stock.is_empty() else "asking...")
	_asking.visible = not _asking.text.is_empty() and not town.is_empty()
	var build: Dictionary = sheet["build"] if sheet.get("build") is Dictionary else {}
	_build_row.visible = not build.is_empty()
	if not build.is_empty():
		var wants := int(build.get("wants", 0))
		var fund := int(build.get("fund", 0))
		_build_name.text = build_words(str(build.get("kind", "")))
		_fund_box.words = _build_name.text
		_fund_box.rose = recent.has("gold")
		for chip: Node in _fund_box.chips.get_children():
			_fund_box.chips.remove_child(chip)
			chip.queue_free()
		if gift > 0:
			_fund_box.chips.add_child(BarterPanel.make_chip("gold", gift, null))
			_frame(_fund_box, BarterPanel.SELECT, 4)
		else:
			_fund_box.remove_theme_stylebox_override("panel")
		_fund_box.modulate.a = 1.0 if is_at() and gift_room() > 0 else 0.6
		_fund_bar.fund = fund
		_fund_bar.wants = maxi(wants, 1)
		_fund_bar.gift = gift
		_fund_bar.queue_redraw()
		_fund_box.overlay.queue_redraw()
		_fund_words.text = "%d of %d" % [fund + gift, wants]
	var regard: Dictionary = sheet["regard"] if sheet.get("regard") is Dictionary else {}
	_regard_mark.get_parent().visible = not regard.is_empty()
	if not regard.is_empty():
		var word := str(regard.get("word", ""))
		if word.is_empty():
			word = "stranger"  # Economy's "": the town hasn't heard of you yet.
		var colour := regard_color(float(regard.get("score", 0.0)))
		_regard_mark.colour = colour
		_regard_mark.queue_redraw()
		_regard_word.text = word
		_regard_word.add_theme_color_override("font_color", colour)
		_regard_step.direction = signi(int(regard.get("last", 0)))
		_regard_step.queue_redraw()
	var states: Array = sheet.get("state", []) if sheet.get("state") is Array else []
	for i in states.size():
		if states[i] is Dictionary:
			_state.add_child(_status_box("state", i, states[i]))
	var asks: Array = sheet.get("asks", []) if sheet.get("asks") is Array else []
	for i in asks.size():
		if asks[i] is Dictionary:
			_asks.add_child(_status_box("ask", i, asks[i]))
	_show_words()
	var act := action()
	var at := is_at() and tab == 0
	_foot.visible = at
	_button.text = str(act.get("words", "Donate"))
	_button.disabled = act.is_empty()
	_short.text = ""
	_short.visible = false
	_hold_pack(at)


## Holds the pack open with the town's prices on it while Donate works;
## lets it go otherwise.
func _hold_pack(hold: bool) -> void:
	if pack == null:
		return
	if not hold or not visible:
		_release_pack()
		return
	_holding = true
	var slots := []
	for uid: Variant in give:
		slots.append(int(pack_entry(int(uid)).get("slot", -1)))
	pack.set_selected(slots)
	var prices := {}
	for each: Variant in sheet.get("pack", []):
		if each is Dictionary:
			prices[int(each.get("slot", -1))] = pays_for(int(each.get("uid", 0)))
	pack.set_prices(prices)
	pack.held_open = true


## A state's or an ask's square: its picture or drawn sign, its words on
## hover; an ask unlit while it is not open.
func _status_box(kind: String, index: int, entry: Dictionary) -> TownBox:
	var what := str(entry.get("kind", ""))
	var words := state_words(entry) if kind == "state" else ask_words(entry)
	var box := _make_box(kind, index, words)
	var picture := status_picture(kind, entry)
	if picture.begins_with("sign:"):
		box.drawn = picture.trim_prefix("sign:")
		if box.drawn == "away":
			box.icon.texture = mark_of("care")
			box.icon.modulate.a = 0.35
	elif not picture.is_empty():
		box.icon.texture = _icon(picture)
		if box.icon.texture == null:
			_caption(box, words)
	var lit := kind == "state" or bool(entry.get("open", false))
	if not lit:
		box.modulate.a = 0.45
	elif kind == "state":
		_frame(box, BarterPanel.OUT if what == "threatened" else UiTheme.color("friend") if what == "thriving" else BarterPanel.PRICE, 3)
	else:
		_frame(box, UiTheme.color("brass_bright"), 3)
	box.overlay.queue_redraw()
	return box


## One square in the store's look: an icon, a drawn layer over it, chips
## over its bottom-right corner.
func _make_box(kind: String, key: Variant, words: String) -> TownBox:
	var box := TownBox.new()
	box.window = self
	box.kind = kind
	box.key = key
	box.words = words
	box.custom_minimum_size = PackPanel.SLOT_SIZE
	box.theme_type_variation = &"Inset"
	var picture := TextureRect.new()
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["offset_left", "offset_top"]:
		picture.set(side, PackPanel.ICON_INSET)
	for side: String in ["offset_right", "offset_bottom"]:
		picture.set(side, -PackPanel.ICON_INSET)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(picture)
	box.icon = picture
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(box.draw_over)
	box.add_child(overlay)
	box.overlay = overlay
	var chips := VBoxContainer.new()
	chips.add_theme_constant_override("separation", 4)
	chips.alignment = BoxContainer.ALIGNMENT_END
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	chips.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	chips.grow_vertical = Control.GROW_DIRECTION_BEGIN
	chips.offset_right = -5
	chips.offset_bottom = -5
	box.add_child(chips)
	box.chips = chips
	return box


## No icon (headless, not drawn yet): the short name in the square.
func _caption(box: TownBox, words: String) -> void:
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.add_theme_font_size_override("font_size", PackPanel.CAPTION_SIZE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = words
	box.add_child(label)
	box.move_child(label, 1)


static func _frame(box: Panel, colour: Color, width: int) -> void:
	var style := PackPanel.selected_style()
	style.border_color = colour
	style.set_border_width_all(width)
	box.add_theme_stylebox_override("panel", style)


## [param id]'s picture: an item's icon, else the kit's "item.<id>" by slot
## (art-kit's stock pictures, 92916670: wool, fish, sheep); null while drawn
## or headless.
func _icon(id: String) -> Texture2D:
	if pack == null or pack.icons == null:
		return null
	var key := id if Items.exists(id) else "item.%s" % id
	var picture := pack.icons.icon(key)
	if picture == null and pack.icons.enabled and not pack.icons.icon_ready.is_connected(_icon_arrived):
		pack.icons.icon_ready.connect(_icon_arrived)
	return picture


func _icon_arrived(_id: String) -> void:
	if not _icons_due:
		_icons_due = true
		_relay_out.call_deferred()


func _relay_out() -> void:
	_icons_due = false
	if visible:
		_rebuild()


func mark_of(service: String) -> Texture2D:
	if not _marks.has(service):
		var path := "res://art/ui/marks/mark_%s.png" % service
		_marks[service] = load(path) if ResourceLoader.exists(path) else null
	return _marks[service]


## The ids the player's own last acts moved (economy's "recent": donated,
## sold or brought home; "gold" for gold given toward the building).
func recent_ids() -> Dictionary:
	var out := {}
	for each: Variant in sheet.get("recent", []):
		if not each is Dictionary:
			continue
		var kind := str(each.get("kind", ""))
		if kind == "gave_gold":
			out["gold"] = true
		elif kind in ["donated", "sold", "brought_home"]:
			out[str(each.get("id", ""))] = true
	return out


## A stock square's name on hover: the item's short name ("Herbs"), else its
## id in words ("Wool").
static func stock_words(id: String) -> String:
	if Items.exists(id):
		return Items.short_of(id)
	return id.replace("_", " ").capitalize()


## "Smithy going up" (voice) from the building's kind.
static func build_words(kind: String) -> String:
	return "%s going up" % kind.replace("_", " ").capitalize()


## A state's words on hover (voice, 768): "Wolves in the lanes", "Raiders
## in the town" or "Under threat"; "Thriving"; "Healer away"; "Hungry";
## "Smithy going up".
static func state_words(entry: Dictionary) -> String:
	match str(entry.get("kind", "")):
		"threatened":
			match str(entry.get("by", "")):
				"wolves":
					return "Wolves in the lanes"
				"raiders":
					return "Raiders in the town"
			return "Under threat"
		"thriving":
			return "Thriving"
		"healer_away":
			return "Healer away"
		"hungry":
			return "Hungry"
		"building":
			return build_words(str(entry.get("building", "")))
		"seeking":
			return "%s wanted" % str(entry.get("trade", "")).capitalize()  # Voice: "Carpenter wanted".
	return str(entry.get("kind", "")).replace("_", " ").capitalize()


## An ask's words on hover (voice): "Wolves at the fold", "Raid",
## "Caravan", "Herbs wanted" (a healer's want of herbs) or "Healer's need".
static func ask_words(entry: Dictionary) -> String:
	match str(entry.get("kind", "")):
		"balance":
			return "Wolves at the fold"
		"raid":
			return "Raid"
		"caravan":
			return "Caravan"
		"healer":
			return "Herbs wanted" if healer_wants(entry).has("herbs") else "Healer's need"
	return str(entry.get("kind", "")).replace("_", " ").capitalize()


## A status square's picture: an item's id, or "sign:<drawn>".
static func status_picture(kind: String, entry: Dictionary) -> String:
	var what := str(entry.get("kind", ""))
	if kind == "state":
		match what:
			"thriving":
				return "sign:thriving"
			"threatened":
				return "sign:threatened"
			"healer_away":
				return "sign:away"
			"hungry":
				return "food_sack"
			"building":
				return "hammer"
			"seeking":
				return str(TRADE_PICTURES.get(str(entry.get("trade", "")), ""))
		return ""
	match what:
		"balance":
			return "antlers"
		"raid":
			return "battle_axe"
		"caravan":
			return "spice"
		"healer":
			for want in healer_wants(entry):
				if Items.exists(want):
					return want  # The first thing the healer wants that has a picture.
			return "herbs"
	return ""


## A healer's ask's wants (economy's raw ids, an Array; one id read too).
static func healer_wants(entry: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var wants: Variant = entry.get("wants", [])
	for want: Variant in (wants if wants is Array else [wants]):
		if not str(want).is_empty():
			out.append(str(want))
	return out


## The picture for a town seeking a trade's newcomer (613 amended): a thing
## of that trade (the fish and the sheep are art-kit's slots, 92916670).
const TRADE_PICTURES := {"butcher": "knife", "carpenter": "nails", "cook": "ration", "farmer": "food_sack",
	"fisherman": "fish", "fletcher": "arrows", "shepherd": "sheep", "smith": "hammer", "tanner": "hide",
	"weaver": "cloth_bolt", "woodcutter": "wood_bundle"}


## The regard's colour by its score (-1..1): rust when wronged, brass
## between, bright when trusted.
static func regard_color(score: float) -> Color:
	if score < -0.2:
		return BarterPanel.OUT
	if score > 0.5:
		return UiTheme.color("brass_bright")
	return BarterPanel.PRICE


## A stock level's colour by its shortage: rust at half short or worse,
## brass while short, green at enough.
static func level_color(short: float) -> Color:
	if short >= 0.5:
		return UiTheme.color("rust")
	if short > 0.0:
		return UiTheme.color("brass")
	return UiTheme.color("friend")


## A small rise (a chevron) centred on [param at].
static func draw_rise(on: CanvasItem, at: Vector2, half: float, colour: Color) -> void:
	on.draw_polyline(PackedVector2Array([at + Vector2(-half, half * 0.6), at + Vector2(0, -half * 0.4), at + Vector2(half, half * 0.6)]),
		colour, 5.0, true)


func _show_words() -> void:
	if _hover != null:
		_hover.text = _hover_words
		_hover.visible = not _hover_words.is_empty()


func _show_tip(box: TownBox) -> void:
	_tip_at(box, box.words)


func _tip_at(over: Control, words: String) -> void:
	if words.is_empty() or _tip == null:
		return
	_tip_words.text = words
	_tip.reset_size()
	var rect := over.get_global_rect()
	_tip.global_position = Vector2(rect.position.x, rect.position.y - _tip.size.y - 6)
	_tip.visible = true


func _hide_tip() -> void:
	if _tip != null:
		_tip.visible = false


func _show_total() -> void:
	var act := action()
	if act.is_empty() or not is_at() or tab != 0:
		return
	for child: Node in _total_chip.get_children():
		_total_chip.remove_child(child)
		child.queue_free()
	for pay: Array in act["total"]:
		_total_chip.add_child(BarterPanel.Coin.new(13))
		var number := Label.new()
		number.text = str(int(pay[1]))
		number.add_theme_color_override("font_color", BarterPanel.PRICE)
		_total_chip.add_child(number)
	_total.reset_size()
	var rect := _button.get_global_rect()
	_total.global_position = Vector2(rect.end.x + GAP, rect.position.y + (rect.size.y - _total.size.y) / 2.0)
	_total.visible = true


func _process(_delta: float) -> void:
	if not visible:
		return
	var began := Time.get_ticks_usec()
	_place()
	UiCost.add("town", Time.get_ticks_usec() - began)


## Beside the pack, to its left, its foot on the pack's, while the pack
## shows (the store's place); else in the middle of the screen.
func _place() -> void:
	_box.reset_size()
	var pack_shown := pack != null and pack.visible
	if pack_shown:
		_box.global_position = pack.beside(_box.size, GAP)  # Clear of the character sheet too (787).
	else:
		_box.position = (size - _box.size) / 2.0


## The tab's words as shown (tests): "Stores" or "Ledger".
func tab_shown() -> String:
	return TAB_WORDS[tab]


## The Stores squares (tests): "<kind> <key> <words> <chips>[ rose]" each.
func boxes_shown() -> Array[String]:
	var out: Array[String] = []
	for grid: GridContainer in [_stock, _state, _asks]:
		for box: Node in grid.get_children():
			if box is TownBox:
				var chips := PackedStringArray()
				for chip: Node in (box as TownBox).chips.get_children():
					chips.append(str(chip.get_meta("words", "")))
				out.append(("%s %s %s %s%s" % [box.kind, box.key, box.words, " ".join(chips), " rose" if box.rose else ""]).strip_edges())
	return out


func regard_shown() -> String:
	if not _regard_mark.get_parent().visible:
		return ""
	return "%s%s" % [_regard_word.text, {1: " rise", -1: " fall"}.get(_regard_step.direction, "")]


func fund_shown() -> String:
	return "%s: %s" % [_build_name.text, _fund_words.text] if _build_row.visible else ""


func button_shown() -> String:
	return _button.text if _foot.visible else ""


func hover_shown() -> String:
	return _hover.text


func total_shown() -> String:
	var act := action()
	return "Total gold %d" % int(act["total"][0][1]) if not act.is_empty() else ""


## Whether the window holds the pack (Donate works).
func holds_pack() -> bool:
	return _holding


## The Ledger's lines shown, top to bottom, the title first (tests).
func lines_shown() -> PackedStringArray:
	var out := PackedStringArray([_title.text])
	for label: Label in [_none, _held, _people, _buildings, _dole]:
		if label.visible and not label.text.is_empty():
			out.append(label.text)
	for line: Label in _economy.get_children():
		out.append(line.text)
	if _when.visible and not _when.text.is_empty():
		out.append(_when.text)
	return out


## "Umbrage, a village"; "Umbrage" before the stages.
static func title_words(town_name: String, stage: String) -> String:
	var word := stage.strip_edges()
	if word.is_empty():
		return town_name
	return "%s, %s %s" % [town_name, "an" if word[0] in "aeiou" else "a", word]


## "Held by the Blood Rot." as the known world names the holder; "" for
## nobody.
static func held_words(holder: String) -> String:
	return "Held by %s." % holder if not holder.strip_edges().is_empty() else ""


## The people from the bodies seen: "12 people: 4 farmers, 2 hunters, a
## priest."; "No one is about." for none seen; the away words for null
## (the player is not on the town's ground).
static func people_words(trades: Variant) -> String:
	if not trades is Array:
		return away_words()
	var seen: Array = trades
	if seen.is_empty():
		return "No one is about."
	var counts := {}
	for trade: Variant in seen:
		var word := str(trade).strip_edges().replace("_", " ")
		if word.is_empty():
			word = "other"
		counts[word] = int(counts.get(word, 0)) + 1
	var words: Array[String] = []
	var order: Array = counts.keys()
	order.sort_custom(func(a: String, b: String) -> bool:
		return counts[a] > counts[b] if counts[a] != counts[b] else a < b)
	for word: String in order:
		var n: int = counts[word]
		words.append("%d %ss" % [n, word] if n > 1 else "%s %s" % ["an" if word[0] in "aeiou" else "a", word])
	return "%d %s: %s." % [seen.size(), "person" if seen.size() == 1 else "people", ", ".join(words)]


static func away_words() -> String:
	return "You haven't seen who lives here."


static func none_words() -> String:
	return "No town is known here."


## The buildings in words from the "town" message's dictionary (kind ->
## {state, progress?}): "Standing: the forge, the kitchen. Building: the
## temple, half built. Damaged: the walls. Planned: the well." Each group
## only when it has a kind; "" for none told.
static func buildings_words(buildings: Dictionary) -> String:
	var standing: Array[String] = []
	var building: Array[String] = []
	var damaged: Array[String] = []
	var planned: Array[String] = []
	var kinds: Array = buildings.keys()
	kinds.sort()
	for kind: Variant in kinds:
		var entry: Variant = buildings[kind]
		if not entry is Dictionary:
			continue
		var state := str(entry.get("state", ""))
		var progress := float(entry.get("progress", -1.0))
		var name := "the %s" % str(kind).replace("_", " ")
		if state == "standing":
			standing.append(name)
		elif state == "damaged":
			damaged.append("%s, being mended" % name if progress >= 0.0 else name)
		elif progress >= 0.0:
			building.append("%s, %s" % [name, progress_words(progress)])
		elif state == "planned":
			planned.append(name)
	var parts: Array[String] = []
	if not standing.is_empty():
		parts.append("Standing: %s." % ", ".join(standing))
	if not building.is_empty():
		parts.append("Building: %s." % ", ".join(building))
	if not damaged.is_empty():
		parts.append("Damaged: %s." % ", ".join(damaged))
	if not planned.is_empty():
		parts.append("Planned: %s." % ", ".join(planned))
	return " ".join(parts)


## A job's progress (0..1) as a word: begun, half built, nearly done.
static func progress_words(progress: float) -> String:
	if progress < BEGUN:
		return "begun"
	if progress < HALF:
		return "half built"
	return "nearly done"


## "Summer, day 14."
static func when_words(season: String, day: int) -> String:
	var word := season.strip_edges()
	if word.is_empty():
		return "Day %d." % day
	return "%s, day %d." % [word.capitalize(), day]


## Economy's rows (624, economy's side) from its "town_sheet" message, each
## only when its key is there: a why alone ("you don't know that town");
## "Umbrage is uneasy." (faction {name} and the mood stand-in); "Treasury: 150
## gold."; the officials, "unpaid" after one owed a wage; "3 fed by the
## town, 2 hungry, 1 sick."; "Needs: wood, badly (bring 20); herbs, a
## little (bring 4)."; "Umbrage seeks a smith and a healer."; "To be a
## village: 3 more people, a priest, 40 more gold."
static func economy_lines(sheet: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if sheet.is_empty():
		return out
	var why := str(sheet.get("why", "")).strip_edges()
	if not why.is_empty():
		out.append(why.left(1).to_upper() + why.substr(1))
		return out
	var town_name := str(sheet.get("name", "The town"))
	var mood := str(sheet.get("mood", "")).strip_edges()
	if not mood.is_empty():
		out.append("%s is %s." % [town_name, mood])
	if sheet.has("treasury"):
		out.append("Treasury: %d gold." % int(sheet["treasury"]))
	if sheet.get("officials") is Array and not (sheet["officials"] as Array).is_empty():
		var names: Array[String] = []
		for each: Variant in sheet["officials"]:
			if each is Dictionary:
				var who := str(each.get("name", "")).strip_edges()
				var trade := str(each.get("trade", "")).replace("_", " ")
				var words := "%s the %s" % [who, trade] if not who.is_empty() and not trade.is_empty() else (who if not who.is_empty() else "the %s" % trade)
				if each.has("paid") and not bool(each["paid"]):
					words += " (unpaid)"
				names.append(words)
		if not names.is_empty():
			out.append("Officials: %s." % ", ".join(names))
	var fed: Array[String] = []
	if sheet.has("dole"):
		fed.append("%d fed by the town" % int(sheet["dole"]))
	if sheet.has("hungry"):
		fed.append("%d hungry" % int(sheet["hungry"]))
	if sheet.has("sick"):
		fed.append("%d sick" % int(sheet["sick"]))
	if not fed.is_empty():
		var fed_words := ", ".join(fed)
		out.append(fed_words.left(1).to_upper() + fed_words.substr(1) + ".")
	if sheet.get("needs") is Array and not (sheet["needs"] as Array).is_empty():
		var needs: Array[String] = []
		for each: Variant in sheet["needs"]:
			if each is Dictionary:
				var id := str(each.get("id", "")).replace("_", " ")
				var words := "%s, %s" % [id, short_words(float(each.get("short", 0.0)))]
				if int(each.get("bring", 0)) > 0:
					words += " (bring %d)" % int(each["bring"])
				needs.append(words)
		out.append("Needs: %s." % "; ".join(needs))
	if sheet.get("sought") is Array and not (sheet["sought"] as Array).is_empty():
		var wanted: Array[String] = []
		for each: Variant in sheet["sought"]:
			var trade := str(each.get("trade", "") if each is Dictionary else each).replace("_", " ")
			if not trade.is_empty():
				wanted.append("%s %s" % ["an" if trade[0] in "aeiou" else "a", trade])
		if not wanted.is_empty():
			out.append("%s seeks %s." % [town_name, join_and(wanted)])
	if sheet.get("next_stage") is Dictionary:
		var next: Dictionary = sheet["next_stage"]
		var stage := str(next.get("stage", "")).strip_edges()
		var wants: Array[String] = []
		for each: Variant in next.get("needs", []):
			if each is Dictionary:
				wants.append(need_words(each))
		if not stage.is_empty() and not wants.is_empty():
			out.append("To be %s %s: %s." % ["an" if stage[0] in "aeiou" else "a", stage, join_and(wants)])
	if sheet.get("strain") is Dictionary:
		var strained := strain_words(sheet["strain"])
		if not strained.is_empty():
			out.append(strained)
	return out


## The strain line (649, ui's side; economy's "strain" {days, of, why}):
## "Strained 4 days of 10: hunger, the store short of food."; the days
## alone when no reason is recorded (a captive carried off adds days
## without one); nothing while the town is not strained. After a fall
## (649 amended (3), ui's side; economy's "settling" {days, of} in the
## dict while the town waits to rise again): "Settling, 3 of 7 days
## calm.", after the strain sentence when there is one (a strained day
## puts the calm days back to 0).
static func strain_words(strain: Dictionary) -> String:
	var out: Array[String] = []
	var days := int(strain.get("days", 0))
	if days > 0:
		var of := int(strain.get("of", 0))
		var head := "Strained %d %s of %d" % [days, "day" if days == 1 else "days", of] if of > 0 else "Strained %d %s" % [days, "day" if days == 1 else "days"]
		var why := str(strain.get("why", ""))
		if why == "hunger":
			why = "hunger, the store short of food"
		out.append("%s: %s." % [head, why] if not why.is_empty() else "%s." % head)
	if strain.get("settling") is Dictionary:
		var settling: Dictionary = strain["settling"]
		var calm := int(settling.get("days", 0))
		var needed := int(settling.get("of", 0))
		out.append("Settling, %d of %d days calm." % [calm, needed] if needed > 0 else "Settling, %d %s calm." % [calm, "day" if calm == 1 else "days"])
	return " ".join(out)


## A next-stage need {what, have, need} in words: "3 more people", "a
## priest", "40 more gold", "the walls standing".
static func need_words(need: Dictionary) -> String:
	var what := str(need.get("what", "")).replace("_", " ")
	var short := maxi(int(need.get("need", 0)) - int(need.get("have", 0)), 0)
	if what in ["people", "residents"]:
		return "%d more %s" % [short, "person" if short == 1 else "people"]
	if what in ["gold", "wood", "food", "ore"]:
		return "%d more %s" % [short, what]
	if what.begins_with("standing:") or what.begins_with("building:"):
		return "the %s standing" % what.get_slice(":", 1).replace("_", " ")
	if short > 1:
		return "%d %ss" % [short, what]
	return "%s %s" % ["an" if not what.is_empty() and what[0] in "aeiou" else "a", what]


## A shortage (0..1) as a word: badly past two thirds, some past a third, a
## little otherwise.
static func short_words(short: float) -> String:
	if short >= HALF:
		return "badly"
	if short >= BEGUN:
		return "some"
	return "a little"


## "a smith", "a smith and a healer", "a smith, a healer and a guard".
static func join_and(words: Array[String]) -> String:
	if words.size() <= 1:
		return "".join(words)
	return "%s and %s" % [", ".join(words.slice(0, words.size() - 1)), words[words.size() - 1]]
