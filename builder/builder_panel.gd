class_name BuilderPanel
extends UiGlass
## Builder mode's window (decision 885; ui-design's mock, approved by the
## coordinator, 11-12: C:/dev/review/ui-design/builder/; its parts and theme
## types are 886): a glass pane under the status line, clear of the area
## being built. Top down: the head ("Builder", the area's corner cell and
## size, the close: Esc's discard); Claude's words; a layout fault in its own
## block (the proposal can't be accepted while it stands, and the foot's
## Enter says so); each other part's head and a bullet line a thing, a part
## of more than FOLD_OVER lines showing FOLD_SHOWN and "N more", which
## unfolds in place; the typing box; the foot's keys. A building's code
## ("[T1]" as BuilderHost.panel_parts marks it) is a chip (UiCodeChip), so T1
## never reads "Ti". A coordinate, "(190, 199)", never breaks across lines.
##
## 885 amended (1) (ui-design's mock, C:/dev/review/ui-design/builder_panel/,
## the coordinator's yes, 11-14): two homes, the left (LEFT, TOP) and the
## right (RIGHT_GAP in from the right edge, RIGHT_TOP down, under the corner
## map); BuilderUI picks one (place) before the pane is drawn. An answer
## shows cut down while he reads the ghost (reading): the head, the words'
## first BRIEF_LINES lines, a layout fault's head and its first line, and the
## keys with "Tab more"; Tab or a click opens it whole (full), Tab again
## goes back. Asking and working are cut down too: NARROW wide, the full
## pane WIDTH. No cost in any state.
##
## The look is the theme's (ui-design's types and parts); this lays out and
## fills. BuilderUI says what the keys do.

## A part of more lines than this folds ...
const FOLD_OVER := 4
## ... showing this many, the rest under "N more".
const FOLD_SHOWN := 3
## Where the left home sits (HUD canvas units, 2 a pixel at 1080): the left
## edge, under the status line; the full pane's width.
const LEFT := 48.0
const TOP := 220.0
const WIDTH := 1560.0
## The cut-down width (asking, working, reading), one in every state: the
## reading keys row at KeyGroups' 40 and the pane's margins (ui-design,
## 2026-11-14, on the joined stills; the mock's 1270 was under it).
const NARROW := 1286.0
## The right home: its right edge this far in, its top under the corner map
## and its "World map" label (they end at 690).
const RIGHT_GAP := 48.0
const RIGHT_TOP := 720.0
## The words' lines while he reads.
const BRIEF_LINES := 2
## The working line's dots (ui-design's mock: three flame dots), and how much of the asked words it
## keeps before them, so the line never widens the pane (an ellipsis past it).
const WORKING_DOTS := "• • •"
const WORKING_CHARS := 64
## Room kept under the pane at the screen's foot; past it the answer scrolls.
const FOOT_ROOM := 48.0
## The no-break space that holds a coordinate or a size together.
const HOLD := "\u00a0"

## Esc's discard, from the close.
signal closed
## Tab's or a click's "more" / "less": the pane opened whole or cut down again.
signal full_changed(full: bool)

var box: LineEdit
## "left" or "right" (place).
var home := "left"
## An answer shown whole; false while he reads it cut down.
var full := false
var _area_words: Label
var _brief: VBoxContainer
var _brief_words: Label
var _brief_fault: PanelContainer
var _brief_fault_head: Label
var _brief_fault_line: Label
var _scroll: ScrollContainer
var _body: VBoxContainer
var _enter_words: Label
var _keys_row: HBoxContainer
## The working line's dots, after its words (ui-design's WorkingDots).
var _working_dots: Label
## An answer is shown (reading or full), not asking or working.
var _answer := false
## Whether the shown answer can be accepted (no layout fault).
var acceptable := true
static var _whole: RegEx
var _fit_queued := false


func _init() -> void:
	super()
	# ui-design's spacing (886 amended (3)): the pane's own margins, set after UiGlass's "Glass".
	theme_type_variation = &"AnswerGlass"
	name = "BuilderPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column := VBoxContainer.new()
	column.theme_type_variation = &"Stack"
	add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	var head_rule := HSeparator.new()
	head_rule.name = "HeadRule"
	head_rule.theme_type_variation = &"HeadRule"
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
	column.add_child(head_rule)
	# The cut-down answer (reading) and the working line: the words' first lines, ending in an ellipsis
	# when there are more, and a layout fault's head and first line; while the server works, the words
	# and then the flame dots (WorkingDots, ui-design's).
	_brief = VBoxContainer.new()
	_brief.name = "Brief"
	_brief.theme_type_variation = &"Stack"
	_brief.visible = false
	column.add_child(_brief)
	var brief_line := HBoxContainer.new()
	brief_line.name = "BriefLine"
	_brief.add_child(brief_line)
	_brief_words = Label.new()
	_brief_words.name = "BriefWords"
	_brief_words.theme_type_variation = &"Body"
	brief_line.add_child(_brief_words)
	_working_dots = Label.new()
	_working_dots.name = "WorkingDots"
	_working_dots.theme_type_variation = &"WorkingDots"
	_working_dots.text = WORKING_DOTS
	_working_dots.visible = false
	brief_line.add_child(_working_dots)
	_brief_wraps(true)
	_brief_fault = PanelContainer.new()
	_brief_fault.name = "BriefFault"
	_brief_fault.theme_type_variation = &"FaultBlock"
	_brief.add_child(_brief_fault)
	var fault_column := VBoxContainer.new()
	_brief_fault.add_child(fault_column)
	_brief_fault_head = Label.new()
	_brief_fault_head.theme_type_variation = &"FaultHead"
	fault_column.add_child(_brief_fault_head)
	_brief_fault_line = Label.new()
	_brief_fault_line.name = "BriefFaultLine"
	_brief_fault_line.theme_type_variation = &"Body"
	_brief_fault_line.clip_text = true
	_brief_fault_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_WORD_ELLIPSIS
	fault_column.add_child(_brief_fault_line)
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
	# A RichTextLabel knows its height only once it has its width: fit again
	# whenever the answer's height settles, so the pane hugs it (885, the
	# sheet: no glass standing empty under a short answer).
	_body.minimum_size_changed.connect(_queue_fit)
	box = LineEdit.new()
	box.name = "BuilderBox"
	box.max_length = BuilderHost.MAX_TEXT
	column.add_child(box)
	var foot := HBoxContainer.new()
	foot.name = "Foot"
	column.add_child(foot)
	_keys_row = HBoxContainer.new()
	_keys_row.theme_type_variation = &"KeyGroups"
	_keys_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_keys_row)
	place("left")


## The brief's words wrapped to the pane's width (reading: up to BRIEF_LINES, an ellipsis past them),
## or one line as long as its words with the dots after it (working).
func _brief_wraps(wraps: bool) -> void:
	_brief_words.size_flags_horizontal = Control.SIZE_EXPAND_FILL if wraps else Control.SIZE_SHRINK_BEGIN
	_brief_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wraps else TextServer.AUTOWRAP_OFF
	_brief_words.text_overrun_behavior = TextServer.OVERRUN_TRIM_WORD_ELLIPSIS if wraps else TextServer.OVERRUN_NO_TRIMMING


## The pane open on [param area] with nothing said yet: the box asks.
func asking(area: Rect2i, placeholder: String) -> void:
	_set_area(area)
	_clear()
	_answer = false
	full = false
	acceptable = true
	box.placeholder_text = placeholder
	_show(false, false, true)
	_keys([["Enter", "ask"], ["Esc", "cancel"]])
	_fit()


## A line while the server works ("Asking: a pond here", then the dots, with
## [param busy]), or why it couldn't: one line, cut to fit.
func working(words: String, busy := false) -> void:
	_clear()
	_answer = false
	full = false
	_brief_wraps(not busy)
	_working_dots.visible = busy
	_brief_words.text = keep_whole(words if not busy or words.length() <= WORKING_CHARS else words.left(WORKING_CHARS - 1) + "…")
	_brief_words.max_lines_visible = 1
	_brief_fault.visible = false
	_show(true, false, false)
	_keys([["Esc", "cancel"], ["Ctrl", "+", "Z", "take back"]])
	_fit()


## The server's proposal: its parts (BuilderHost.panel_parts), or, from a
## server before 885, its summary string as the words; [param beyond] a new
## level's line, said after the words. Shown cut down (reading) until Tab or
## a click opens it whole.
func show_answer(data: Dictionary, beyond := "") -> void:
	_set_area(_rect_of(data.get("area", [])))
	_clear()
	var parts: Array = data.get("parts", [])
	if parts.is_empty():
		parts = [{"head": "", "lines": [str(data.get("summary", ""))], "fault": false}]
	acceptable = not parts.any(func(part: Variant) -> bool: return part is Dictionary and bool(part.get("fault", false)))
	var said := PackedStringArray()
	var fault := {}
	for part: Variant in parts:
		if not part is Dictionary:
			continue
		var head := str(part.get("head", ""))
		var lines: Array = part.get("lines", [])
		if head.is_empty():
			for line: Variant in lines:
				for paragraph in str(line).split("\n", false):
					_body.add_child(_paragraph(paragraph), true)
					said.append(paragraph)
			if not beyond.is_empty():
				_body.add_child(_paragraph(beyond), true)
				said.append(beyond)
		elif bool(part.get("fault", false)):
			_body.add_child(_fault(head, lines), true)
			if fault.is_empty():
				fault = {"head": head, "line": str(lines[0]) if not lines.is_empty() else ""}
		else:
			_body.add_child(_part(head, lines), true)
	_brief_wraps(true)
	_working_dots.visible = false
	_brief_words.text = keep_whole(brief_of(said))
	_brief_words.max_lines_visible = BRIEF_LINES
	_brief_fault.visible = not fault.is_empty()
	_brief_fault_head.text = str(fault.get("head", ""))
	# One line cut with an ellipsis is a Label's (a RichTextLabel cuts none), so its codes read as their
	# letters and figures ("[T1]" as "T1"), without the chip the whole answer draws.
	var fault_line := RegEx.create_from_string(UiCodeChip.MARK).sub(str(fault.get("line", "")), "$1", true)
	_brief_fault_line.text = keep_whole(fault_line.left(1).to_upper() + fault_line.substr(1))
	box.placeholder_text = "Say what to change (\"bigger\", \"move it north\")"
	_answer = true
	set_full(false)


## The shown answer whole ([param on]) or cut down; nothing while there is
## no answer (asking, working).
func set_full(on: bool) -> void:
	if not _answer:
		return
	var changed := on != full
	full = on
	_show(not on, on, on)
	var enter := ["Enter", "accept" if acceptable else "can't accept yet"]
	_keys([enter, ["Esc", "discard"], ["Ctrl", "+", "Z", "take back"], ["Tab", "less" if on else "more"]])
	_fit()
	if changed:
		full_changed.emit(on)


## Whether an answer is shown (reading or full).
func has_answer() -> bool:
	return _answer


## At [param at] ("left" or "right"): the left home's corner at LEFT, TOP;
## the right home's right edge RIGHT_GAP in from the screen's, its top at
## RIGHT_TOP. Its width is the state's (NARROW, or WIDTH whole).
func place(at: String) -> void:
	home = at if at == "right" else "left"
	_lay_home()


## The rect [param at] would take for a pane [param pane_size] on a screen
## [param screen] wide and tall (HUD canvas units): BuilderUI's choice of
## home, made before the pane is drawn.
static func home_rect(at: String, pane_size: Vector2, screen: Vector2) -> Rect2:
	if at == "right":
		return Rect2(screen.x - RIGHT_GAP - pane_size.x, RIGHT_TOP, pane_size.x, pane_size.y)
	return Rect2(LEFT, TOP, pane_size.x, pane_size.y)


## The pane's size as it is now laid out (width by state, the height its contents').
func pane_size() -> Vector2:
	return Vector2(_width(), get_combined_minimum_size().y)


func _width() -> float:
	return WIDTH if _answer and full else NARROW


## The state's width is the pane's least (so _fit's reset_size keeps it), and
## the right home grows leftward (so a reset keeps its right edge in place).
func _lay_home() -> void:
	var width := _width()
	custom_minimum_size.x = width
	if home == "right":
		grow_horizontal = Control.GROW_DIRECTION_BEGIN
		anchor_left = 1.0
		anchor_right = 1.0
		offset_right = -RIGHT_GAP
		offset_left = -RIGHT_GAP - width
		offset_top = RIGHT_TOP
	else:
		grow_horizontal = Control.GROW_DIRECTION_END
		anchor_left = 0.0
		anchor_right = 0.0
		offset_left = LEFT
		offset_right = LEFT + width
		offset_top = TOP


## Which parts show: the cut-down lines, the whole answer, the typing box.
func _show(brief: bool, whole: bool, typing: bool) -> void:
	_brief.visible = brief
	_scroll.visible = whole
	box.visible = typing
	_lay_home()


## A click on the cut-down answer opens it whole (the mock's "or a click").
func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT and _answer and not full:
		set_full(true)
		accept_event()


## What the foot's Enter says ("accept", "can't accept yet", "ask").
func enter_words() -> String:
	return _enter_words.text if _enter_words != null else ""


## The cut-down answer's words and fault line, as shown (tests and shots).
func brief_text() -> String:
	return "%s|%s|%s" % [_brief_words.text, _brief_fault_head.text if _brief_fault.visible else "", _brief_fault_line.text if _brief_fault.visible else ""]


## [param text] with each coordinate "(190, 199)" and size "14 x 10" held
## together by no-break spaces, so a line never breaks inside one.
## The answer's lines as the cut-down pane reads them, one line (ui-design, 2026-11-16, on
## builderlook_bd50a9723: joined by a space the stub's results ran into one another): joined with "; ", a
## result line being a clause; after a line ending in ":" (a head) or a sentence's own stop, a plain space.
## Blank lines and runs of them count as none; the overrun's ellipsis is the Label's, after no separator.
static func brief_of(lines: PackedStringArray) -> String:
	var out := ""
	for line in lines:
		var said := line.strip_edges()
		if said.is_empty():
			continue
		if not out.is_empty():
			out += " " if out.right(1) in [":", ".", "!", "?"] else "; "
		out += said
	return out


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
## that can't accept says so in the refused words; Tab's words a fold link
## (the flame of "N more"), pressed as Tab is.
func _keys(sets: Array) -> void:
	for child in _keys_row.get_children():
		_keys_row.remove_child(child)
		child.queue_free()
	_enter_words = null
	for one: Array in sets:
		var pair := HBoxContainer.new()
		pair.add_child(UiKeyCap.row(one.slice(0, one.size() - 1)))
		if one[0] == "Tab":
			var link := Button.new()
			link.name = "TabWords"
			link.theme_type_variation = &"FoldLink"
			link.text = str(one.back())
			link.focus_mode = Control.FOCUS_NONE
			link.pressed.connect(func() -> void: set_full(not full))
			pair.add_child(link)
			_keys_row.add_child(pair)
			continue
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


## Every folded part opened, as its "N more" pressed (859 amended (3): a
## shot's still can't press it; --test-builder's "*" request).
func unfold_all() -> void:
	for more: Node in find_children("More", "Button", true, false):
		(more as Button).pressed.emit()


## One bullet line: the dot, and the line wrapping under its own words, its
## codes as chips.
func _bullet(text: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "Line"
	var dot := Label.new()
	dot.name = "Bullet"
	dot.theme_type_variation = &"LineBullet"
	dot.text = "•"
	# On the first line, the wrapped lines hanging level with the words.
	dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
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
func _queue_fit() -> void:
	if not _fit_queued:
		_fit_queued = true
		_fit.call_deferred()


func _fit() -> void:
	_fit_queued = false
	if _scroll == null or not is_inside_tree():
		return
	var holder := get_parent_control()
	var screen := holder.size.y if holder != null else get_viewport_rect().size.y
	var others := get_combined_minimum_size().y - (_scroll.get_combined_minimum_size().y if _scroll.visible else 0.0)
	_scroll.custom_minimum_size.y = clampf(_body.get_combined_minimum_size().y, 0.0, maxf(screen - offset_top - FOOT_ROOM - others, 0.0))
	reset_size.call_deferred()
