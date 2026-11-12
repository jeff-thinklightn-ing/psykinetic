class_name BuilderPanel
extends UiGlass
## Builder mode's window (decision 885; ui-design's mock, approved by the
## coordinator, 11-12: C:/dev/review/ui-design/builder/; its parts and theme
## types are 886): a glass pane at the left under the status line, clear of
## the area being built. Top down: the head ("Builder", the area's corner
## cell and size, the close: Esc's discard); Claude's words; a layout fault
## in its own block (the proposal can't be accepted while it stands, and the
## foot's Enter says so); each other part's head and a bullet line a thing, a
## part of more than FOLD_OVER lines showing FOLD_SHOWN and "N more", which
## unfolds in place; the typing box; the foot's keys and the cost. A
## building's code ("[T1]" as BuilderHost.panel_parts marks it) is a chip
## (UiCodeChip), so T1 never reads "Ti". A coordinate, "(190, 199)", never
## breaks across lines.
##
## The look is the theme's (ui-design's types and parts); this lays out and
## fills. BuilderUI says what the keys do.

## A part of more lines than this folds ...
const FOLD_OVER := 4
## ... showing this many, the rest under "N more".
const FOLD_SHOWN := 3
## Where the pane sits (HUD canvas units, 2 a pixel at 1080): the left edge,
## under the status line, and its width.
const LEFT := 48.0
const TOP := 220.0
const WIDTH := 1560.0
## Room kept under the pane at the screen's foot; past it the answer scrolls.
const FOOT_ROOM := 48.0
## The no-break space that holds a coordinate or a size together.
const HOLD := "\u00a0"

## Esc's discard, from the close.
signal closed

var box: LineEdit
var _area_words: Label
var _scroll: ScrollContainer
var _body: VBoxContainer
var _enter_words: Label
var _keys_row: HBoxContainer
var _cost: Label
## Whether the shown answer can be accepted (no layout fault).
var acceptable := true
static var _whole: RegEx


func _init() -> void:
	super()
	name = "BuilderPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	offset_left = LEFT
	offset_top = TOP
	offset_right = LEFT + WIDTH
	var column := VBoxContainer.new()
	column.theme_type_variation = &"Stack"
	add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	var title := Label.new()
	title.theme_type_variation = &"Title"
	title.text = "Builder"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_area_words = Label.new()
	_area_words.name = "Area"
	_area_words.theme_type_variation = &"Note"
	_area_words.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_area_words)
	var close := UiClose.new()
	close.name = "Close"
	close.pressed.connect(func() -> void: closed.emit())
	head.add_child(close)
	_scroll = ScrollContainer.new()
	_scroll.theme_type_variation = &"QuietScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	column.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.name = "Answer"
	_body.theme_type_variation = &"Stack"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	box = LineEdit.new()
	box.name = "BuilderBox"
	box.max_length = BuilderHost.MAX_TEXT
	column.add_child(box)
	var foot := HBoxContainer.new()
	foot.name = "Foot"
	column.add_child(foot)
	_keys_row = HBoxContainer.new()
	_keys_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_keys_row)
	_cost = Label.new()
	_cost.name = "Cost"
	_cost.theme_type_variation = &"Note"
	_cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(_cost)


## The pane open on [param area] with nothing said yet: the box asks.
func asking(area: Rect2i, placeholder: String) -> void:
	_set_area(area)
	_clear()
	acceptable = true
	box.placeholder_text = placeholder
	_cost.text = ""
	_keys([["Enter", "ask"], ["Esc", "cancel"]])
	_fit()


## A line while the server works ("Asking: a pond here ..."), or why it
## couldn't.
func working(words: String) -> void:
	_clear()
	_body.add_child(_paragraph(words), true)
	_keys([["Esc", "cancel"], ["Ctrl", "+", "Z", "take back"]])
	_fit()


## The server's proposal: its parts (BuilderHost.panel_parts), or, from a
## server before 885, its summary string as the words; [param beyond] a new
## level's line, said after the words.
func show_answer(data: Dictionary, beyond := "") -> void:
	_set_area(_rect_of(data.get("area", [])))
	_clear()
	var parts: Array = data.get("parts", [])
	if parts.is_empty():
		parts = [{"head": "", "lines": [str(data.get("summary", ""))], "fault": false}]
	acceptable = not parts.any(func(part: Variant) -> bool: return part is Dictionary and bool(part.get("fault", false)))
	for part: Variant in parts:
		if not part is Dictionary:
			continue
		var head := str(part.get("head", ""))
		var lines: Array = part.get("lines", [])
		if head.is_empty():
			for line: Variant in lines:
				for paragraph in str(line).split("\n", false):
					_body.add_child(_paragraph(paragraph), true)
			if not beyond.is_empty():
				_body.add_child(_paragraph(beyond), true)
		elif bool(part.get("fault", false)):
			_body.add_child(_fault(head, lines), true)
		else:
			_body.add_child(_part(head, lines), true)
	box.placeholder_text = "Say what to change (\"bigger\", \"move it north\")"
	_cost.text = "$%.3f   this area $%.3f" % [float(data.get("cost", 0.0)), float(data.get("total", 0.0))]
	_keys([["Enter", "accept" if acceptable else "can't accept yet"], ["Esc", "discard"], ["Ctrl", "+", "Z", "take back"]])
	_fit()


## What the foot's Enter says ("accept", "can't accept yet", "ask").
func enter_words() -> String:
	return _enter_words.text if _enter_words != null else ""


## [param text] with each coordinate "(190, 199)" and size "14 x 10" held
## together by no-break spaces, so a line never breaks inside one.
static func keep_whole(text: String) -> String:
	if _whole == null:
		_whole = RegEx.create_from_string("\\((-?[0-9]+), (-?[0-9]+)\\)|([0-9]+) x ([0-9]+)")
	var out := ""
	var at := 0
	for found in _whole.search_all(text):
		out += text.substr(at, found.get_start() - at) + found.get_string().replace(" ", HOLD)
		at = found.get_end()
	return out + text.substr(at)


func _set_area(area: Rect2i) -> void:
	_area_words.text = "" if area.size == Vector2i.ZERO else "(%d, %d)  %d x %d" % [area.position.x, area.position.y, area.size.x, area.size.y]


static func _rect_of(given: Array) -> Rect2i:
	return Rect2i(int(given[0]), int(given[1]), int(given[2]), int(given[3])) if given.size() == 4 else Rect2i()


func _clear() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()


## The foot: each [keys..., words] as key caps and their words; an Enter
## that can't accept says so in the refused words.
func _keys(sets: Array) -> void:
	for child in _keys_row.get_children():
		_keys_row.remove_child(child)
		child.queue_free()
	_enter_words = null
	for one: Array in sets:
		var pair := HBoxContainer.new()
		pair.add_child(UiKeyCap.row(one.slice(0, one.size() - 1)))
		var words := Label.new()
		words.text = str(one.back())
		words.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		words.theme_type_variation = &"WordsRefused" if one[0] == "Enter" and not acceptable else &"HintWords"
		if one[0] == "Enter":
			_enter_words = words
		pair.add_child(words)
		_keys_row.add_child(pair)


## Claude's words: a paragraph, wrapped.
func _paragraph(text: String) -> Control:
	var words := Label.new()
	words.name = "Words"
	words.theme_type_variation = &"Body"
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.text = keep_whole(text)
	return words


## The layout fault's block: its head and a bullet line a fault.
func _fault(head: String, lines: Array) -> Control:
	var block := PanelContainer.new()
	block.name = "Fault"
	block.theme_type_variation = &"FaultBlock"
	var column := VBoxContainer.new()
	block.add_child(column)
	var title := Label.new()
	title.theme_type_variation = &"FaultHead"
	title.text = head
	column.add_child(title)
	for line: Variant in lines:
		column.add_child(_bullet(str(line)), true)
	return block


## A part: its head, a bullet line a thing, folded past FOLD_OVER lines.
func _part(head: String, lines: Array) -> Control:
	var column := VBoxContainer.new()
	column.name = "Part"
	var title := Label.new()
	title.theme_type_variation = &"Subhead"
	title.text = head
	column.add_child(title)
	var shown := lines.size() if lines.size() <= FOLD_OVER else FOLD_SHOWN
	var folded: Array[Control] = []
	for i in lines.size():
		var row := _bullet(str(lines[i]))
		row.visible = i < shown
		if i >= shown:
			folded.append(row)
		column.add_child(row, true)
	if not folded.is_empty():
		var more := Button.new()
		more.name = "More"
		more.theme_type_variation = &"FoldLink"
		more.text = "▶ %d more" % folded.size()
		more.focus_mode = Control.FOCUS_NONE
		more.alignment = HORIZONTAL_ALIGNMENT_LEFT
		more.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		more.pressed.connect(func() -> void:
			for row in folded:
				row.visible = true
			more.queue_free()
			_fit.call_deferred())
		column.add_child(more)
	return column


## One bullet line: the dot, and the line wrapping under its own words, its
## codes as chips.
func _bullet(text: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "Line"
	var dot := Label.new()
	dot.theme_type_variation = &"Body"
	dot.text = "•"
	row.add_child(dot)
	var rich := RichTextLabel.new()
	rich.name = "Text"
	rich.theme_type_variation = &"Lines"
	rich.fit_content = true
	rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rich.scroll_active = false
	rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rich.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiCodeChip.add_line(rich, keep_whole(text))
	row.add_child(rich)
	return row


## The pane grows with its answer down to the screen's foot, then scrolls.
func _fit() -> void:
	if _scroll == null or not is_inside_tree():
		return
	var holder := get_parent_control()
	var screen := holder.size.y if holder != null else get_viewport_rect().size.y
	var others := get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = clampf(_body.get_combined_minimum_size().y, 0.0, maxf(screen - TOP - FOOT_ROOM - others, 0.0))
	reset_size.call_deferred()
