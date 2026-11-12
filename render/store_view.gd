class_name StoreView
extends UiGlass
## The store window as Jeff approved it (decision 852; the mock is ui-design's,
## C:/dev/review/ui-design/store/, Jeff 11-10: "store update is what i
## imagined -- approve"; the parts are 854's: UiGlass the pane, UiTabs the head's tabs, UiSlot
## each square with its UiPrice chip, UiLine the foot): one window for every keeper, with the head's tabs
## (Store, Donate, Locker), the keeper's goods on the left and the player's
## pack on the right in the same squares, the player's gold at the pack's
## head, and one line at the foot saying what just happened. It only draws:
## BarterPanel (the controller) hands it a state and gets clicks back. Every
## look is the theme's (Glass, Subhead, Tab, Well and its states, PriceChip,
## ChipPrice, SquareCount, FootLine): no override, colour, font or size here.
##
## State, from BarterPanel._store_state: {title, trusted, asleep (a line or ""),
## tabs: [{id, text, open}], goods_head, goods, mine_head, mine, gold, foot,
## refused}; a square is {kind, key, item, words, price (-1 none), short,
## count, lit}. A press on a square is square_pressed(kind, key); on a tab,
## tab_pressed(id).

## A press on a square: its kind ("ware", "good", "mine") and key.
signal square_pressed(kind: String, key: Variant)
## The pointer on a square (its kind, key, words and rect), or off it ("" words).
signal square_hovered(kind: String, key: Variant, words: String, rect: Rect2)
## A tab pressed: "store", "donate" or "locker".
signal tab_pressed(id: String)
## The close at the head's right end pressed (UiClose; Esc does the same).
signal close_pressed

## Squares a line, both halves.
const COLUMNS := 4
## The goods' rows seen before the half scrolls.
const GOODS_ROWS := 4
## How long a refused square shows its rust rim, seconds.
const REFUSED_SECONDS := 1.0
## The bar's word (voice's, the mock's): its band reads on hover.
const LOAD_WORDS := "Load"
## A free ware's pill (voice: "Free"), the pill for words without a coin.
const FREE_WORDS := "Free"
## A square that just changed (a thing bought or moved in) shows lit this long.
const NEW_SECONDS := 2.0

## Where an item's picture comes from: Callable(item id) -> Texture2D or null.
var icon_of: Callable

var _title: Label
var _trusted: Label
var _close: UiClose
var _tabs: UiTabs
var _tab_ids: Array[String] = []
var _asleep: UiLine
var _goods_head: Label
var _goods_scroll: ScrollContainer
var _goods: GridContainer
var _lines: VBoxContainer
var _mine_head: Label
var _gold: Label
var _mine: GridContainer
var _load: CharacterSheet.LoadBar
var _foot: UiLine
## "kind:key" -> msec the rust rim ends / the lit state ends.
var _refused: Dictionary = {}
var _new: Dictionary = {}
var _squares: Dictionary = {}
var _state: Dictionary = {}


## One square (UiSlot): what it stands for in the window (a ware, a good, a thing of yours).
class Square:
	extends UiSlot
	var kind := ""
	var key: Variant
	var words := ""
	var view: StoreView


func _init() -> void:
	super()
	name = "StoreView"
	visible = false


func _ready() -> void:
	super()  # UiGlass: the frost and its group.
	var column := VBoxContainer.new()
	column.theme_type_variation = &"Stack"
	add_child(column)
	var head := HBoxContainer.new()
	head.theme_type_variation = &"Strip"
	column.add_child(head)
	_title = Label.new()
	_title.theme_type_variation = &"Title"
	head.add_child(_title)
	_trusted = Label.new()
	_trusted.theme_type_variation = &"Caption"
	_trusted.text = BarterPanel.TRUSTED_WORDS
	_trusted.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_trusted)
	_tabs = UiTabs.new()
	_tabs.chosen.connect(func(index: int) -> void:
		if index >= 0 and index < _tab_ids.size():
			tab_pressed.emit(_tab_ids[index]))
	head.add_child(_tabs)
	var gap := Control.new()  # The close at the head's right end.
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(gap)
	_close = UiClose.new()
	_close.pressed.connect(func() -> void: close_pressed.emit())
	head.add_child(_close)
	_asleep = UiLine.new()
	column.add_child(_asleep)
	var halves := HBoxContainer.new()
	halves.theme_type_variation = &"Halves"
	column.add_child(halves)
	var left := VBoxContainer.new()
	left.theme_type_variation = &"Stack"
	halves.add_child(left)
	_goods_head = Label.new()
	_goods_head.theme_type_variation = &"Subhead"
	left.add_child(_goods_head)
	_goods_scroll = ScrollContainer.new()
	_goods_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_goods_scroll.theme_type_variation = &"QuietScroll"  # ui-design's: a ScrollContainer with no panel of its own (the dark box round the goods).
	left.add_child(_goods_scroll)
	_goods = _grid_of()
	_goods_scroll.add_child(_goods)
	_lines = VBoxContainer.new()
	left.add_child(_lines)
	var right := VBoxContainer.new()
	right.theme_type_variation = &"Stack"
	halves.add_child(right)
	var mine_row := HBoxContainer.new()
	right.add_child(mine_row)
	_mine_head = Label.new()
	_mine_head.theme_type_variation = &"Subhead"
	_mine_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mine_row.add_child(_mine_head)
	var purse := HBoxContainer.new()
	purse.theme_type_variation = &"Strip"
	mine_row.add_child(purse)
	purse.add_child(BarterPanel.Coin.new(BarterPanel.COIN_RADIUS))
	_gold = Label.new()
	_gold.theme_type_variation = &"Subhead"
	purse.add_child(_gold)
	_mine = _grid_of()
	right.add_child(_mine)
	var room := Control.new()  # What the pack's rows leave of the goods' four: the load bar sits at the foot.
	room.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(room)
	var load_row := HBoxContainer.new()
	load_row.theme_type_variation = &"Strip"
	right.add_child(load_row)
	var load_word := Label.new()
	load_word.theme_type_variation = &"Caption"
	load_word.text = LOAD_WORDS
	load_word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	load_row.add_child(load_word)
	_load = CharacterSheet.LoadBar.new()
	_load.ticks = false
	_load.custom_minimum_size = Vector2(0, side() * 0.25)
	_load.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_row.add_child(_load)
	_foot = UiLine.new()
	column.add_child(_foot)
	if not _state.is_empty():
		show_state(_state)


## The square's side: the theme's "square" (ui-design), else the pack's slot (a theme without it yet).
static func side() -> float:
	var found := UiTheme.theme()
	if found != null and found.has_constant(&"square", UiTheme.TYPE):
		return float(found.get_constant(&"square", UiTheme.TYPE))
	return PackPanel.SLOT_SIZE.x


## A gap from the theme by [param name], else [param fallback]'s (a theme without it yet).
static func _gap(name: StringName, fallback: StringName) -> int:
	var found := UiTheme.theme()
	if found != null and found.has_constant(name, UiTheme.TYPE):
		return found.get_constant(name, UiTheme.TYPE)
	return UiTheme.constant(fallback)


func _grid_of() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.theme_type_variation = &"Squares"
	return grid


## [param state] drawn (the shape in the class comment); the squares laid out again.
func show_state(state: Dictionary) -> void:
	_state = state
	if _title == null:
		return  # Drawn at _ready.
	_title.text = str(state.get("title", ""))
	_trusted.visible = bool(state.get("trusted", false))
	_asleep.refuse(str(state.get("asleep", "")))
	_asleep.visible = not _asleep.text.is_empty()
	_set_tabs(state.get("tabs", []))
	_goods_head.text = str(state.get("goods_head", ""))
	_mine_head.text = str(state.get("mine_head", ""))
	_gold.text = str(int(state.get("gold", 0)))
	var said := str(state.get("foot", ""))
	if said.is_empty():
		_foot.clear()  # UiLine keeps a line's height, so a buy never moves the window.
	elif bool(state.get("refused", false)):
		_foot.refuse(said)
	else:
		_foot.say(said)
	_foot.visible = true
	_squares.clear()
	_fill(_goods, state.get("goods", []))
	_fill(_mine, state.get("mine", []))
	set_lines(state.get("lines", []))
	var gap := float(_gap(&"square_gap", &"slot_gap"))
	var column := COLUMNS * (side() + gap) - gap
	# Both halves are the same height whatever is in them: four rows of squares, the goods scrolling inside.
	_goods_scroll.custom_minimum_size = Vector2(column, GOODS_ROWS * (side() + gap) - gap)
	_load.share = float(state.get("load_share", 0.0))
	_load.tooltip_text = str(state.get("load_words", ""))
	_load.queue_redraw()


## The lines under the goods' place (Donate: what handing over the thing the pointer is on does).
func set_lines(lines: Array) -> void:
	if _lines == null:
		return
	for child: Node in _lines.get_children():
		_lines.remove_child(child)
		child.queue_free()
	for words: Variant in lines:
		var line := Label.new()
		line.theme_type_variation = &"Caption"
		line.text = str(words)
		_lines.add_child(line)


func _set_tabs(tabs: Array) -> void:
	_tab_ids.clear()
	var names: Array[String] = []
	var open := 0
	for tab: Variant in tabs:
		var each: Dictionary = tab
		if bool(each.get("open", false)):
			open = names.size()
		_tab_ids.append(str(each.get("id", "")))
		names.append(str(each.get("text", "")))
	_tabs.set_tabs(names, open)


func _fill(grid: GridContainer, squares: Array) -> void:
	for child: Node in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	var now := Time.get_ticks_msec()
	for each: Variant in squares:
		var spec: Dictionary = each
		var square := _square(spec)
		var id := "%s:%s" % [spec.get("kind", ""), spec.get("key", "")]
		_squares[id] = square
		_restyle(square, id, now)
		grid.add_child(square)


func _square(spec: Dictionary) -> Square:
	var square := Square.new()
	square.view = self
	square.kind = str(spec.get("kind", ""))
	square.key = spec.get("key")
	square.words = str(spec.get("words", ""))
	square.pressed.connect(func(_slot: UiSlot) -> void: square_pressed.emit(square.kind, square.key))  # UiSlot accepts the press first (854 amended (1)).
	square.mouse_entered.connect(func() -> void: square_hovered.emit(square.kind, square.key, square.words, square.get_global_rect()))
	square.mouse_exited.connect(func() -> void: square_hovered.emit(square.kind, square.key, "", Rect2()))
	var item := str(spec.get("item", ""))
	if not item.is_empty():
		var picture: Texture2D = icon_of.call(item) if icon_of.is_valid() else null
		square.set_picture(picture)
		if picture == null:
			var name := Label.new()  # No picture (headless, not drawn yet): the short name.
			name.set_anchors_preset(Control.PRESET_FULL_RECT)
			name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			name.autowrap_mode = TextServer.AUTOWRAP_WORD
			name.theme_type_variation = &"Caption"  # Readable, until the thing's picture is made.
			name.mouse_filter = Control.MOUSE_FILTER_IGNORE
			name.text = Items.short_of(item)
			square.add_child(name)
	square.set_count(int(spec.get("count", 0)))
	var price := int(spec.get("price", -1))
	if price >= 0:
		var free := price == 0 and str(spec.get("kind", "")) in ["ware", "good"]
		if free:
			square.price().set_words(FREE_WORDS)
		else:
			square.price().set_gold(price, bool(spec.get("short", false)))
		square.set_meta("price", price)
	return square


## [param square]'s look: refused (a rust rim), just changed, or at rest.
func _restyle(square: Square, id: String, now: int) -> void:
	if int(_refused.get(id, 0)) > now:
		square.set_state("refused")
	elif int(_new.get(id, 0)) > now:
		square.set_state("new")
	else:
		square.set_state("rest")


## The square [param kind]:[param key] shows its refused rim for REFUSED_SECONDS.
func flash_refused(kind: String, key: Variant) -> void:
	_stamp(_refused, "%s:%s" % [kind, key], REFUSED_SECONDS)


## The square [param kind]:[param key] shows lit for NEW_SECONDS (a thing that just arrived).
func flash_new(kind: String, key: Variant) -> void:
	_stamp(_new, "%s:%s" % [kind, key], NEW_SECONDS)


func _stamp(into: Dictionary, id: String, seconds: float) -> void:
	into[id] = Time.get_ticks_msec() + int(seconds * 1000.0)
	_apply_looks()
	if is_inside_tree():
		get_tree().create_timer(seconds + 0.05).timeout.connect(_apply_looks)


func _apply_looks() -> void:
	var now := Time.get_ticks_msec()
	for id: String in _squares:
		var square: Square = _squares[id]
		if is_instance_valid(square):
			_restyle(square, id, now)


## The square for [param kind]:[param key], null for none (tests).
func square_for(kind: String, key: Variant) -> Square:
	return _squares.get("%s:%s" % [kind, key])


## The squares shown on a side ("goods" or "mine"), as "kind key price" each (tests).
func squares_shown(side: String) -> Array[String]:
	var out: Array[String] = []
	var grid := _goods if side == "goods" else _mine
	for square: Node in grid.get_children():
		if square is Square and not square.is_queued_for_deletion():
			out.append("%s %s %s" % [(square as Square).kind, (square as Square).key, int(square.get_meta("price", -1))])
	return out


## The tabs shown, as "id" or "id*" for the open one (tests).
func tabs_shown() -> Array[String]:
	var out: Array[String] = []
	for i in _tab_ids.size():
		out.append(_tab_ids[i] + ("*" if i == _tabs.current else ""))
	return out


func foot_shown() -> String:
	return _foot.text.strip_edges() if _foot != null else ""


func foot_is_refused() -> bool:
	return _foot != null and _foot.refused


func title_shown() -> String:
	return _title.text if _title != null else ""


func gold_shown() -> int:
	return int(_gold.text) if _gold != null else 0


func goods_head_shown() -> String:
	return _goods_head.text if _goods_head != null else ""


func lines_shown() -> Array[String]:
	var out: Array[String] = []
	if _lines != null:
		for line: Node in _lines.get_children():
			if not line.is_queued_for_deletion():
				out.append((line as Label).text)
	return out
