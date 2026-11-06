class_name CardPage
extends PanelContainer
## Her card page (decision 618, ui's side; companions' 576 and 577; Jeff's
## "spider chart where you only have say 100% focus"): C opens it in the
## middle of the screen, Esc or C closes it. Her name as the title; under it,
## in her own voice, what she has learned (the world message's "capabilities"
## {companion, held: [{id, words, teacher}]}: the mark's words and who
## taught it, never an id) and how she fights: her focus ("focus" {companion,
## fight, magic, stealth}) drawn as three points on a small triangle, the
## focus's names at the corners (Fighting, Magic, Stealth: the sim's three,
## 577), with one sentence of her lean beside it (CompanionCard.lean_of, the
## words companion_traits.json "focus" gives her own voice, said as "I"). No
## numbers anywhere. Her purse
## is a row once companions' "companion_gold" {companion, gold} is in the
## state, absent till then. "Regard": her bond's tier word
## as the party line says it (Companion.bond_step, on her node since 555:
## apart, sullen, wary, cooling, fond, close, devoted) and its newest
## reason under it (bond_why), the same words the known world shows.
## Main feeds it world_state (show_state) on open and on every world
## message. The look is the shared theme's (UiTheme, docs/ui_style.md).

const WIDTH := 980.0
## The heading over her needs (voice's word).
const NEEDS_HEADING := "Needs"
const CHART_RADIUS := 170.0
## The share a chart point reaches the corner at: a lean (45) reads as
## three quarters of the way out, an even split a little past half.
const CHART_FULL := 60.0
## Her needs as her card lists them (companions' 803 amended (2)), each named and
## coloured as its Gains track (voice's words: Ease, Venture, Wonder, Faith, Shelter, Company).
const NEEDS: Array[String] = ["leisure", "adventure", "wonder", "faith", "safety", "company"]
## Her bond's steps, coldest first (555): a move up one pulses the bar.
const STEPS: Array[String] = ["apart", "sullen", "wary", "cooling", "fond", "close", "devoted"]
## A bar's rise and pulse (804's flourish).
const RISE_SECONDS := 0.6
const BAR_HEIGHT := 18.0
const NEED_BAR_HEIGHT := 12.0
## The three axes, from the top clockwise: the focus key and its name on the card.
const AXES: Array[Array] = [["fight", "Fighting"], ["magic", "Magic"], ["stealth", "Stealth"]]

var _title: Label
var _learned_heading: Label
var _learned: VBoxContainer
var _bent_heading: Label
var _chart: FocusChart
var _lean: Label
var _purse: Label
var _alone: Label
var _feels_heading: Label
var _feels: Label
var _feels_why: Label
## Her bond toward its next warmer step (804's bars, Landing B), under her tier word.
var _bond: GrowBar
var _needs_heading: Label
## Her needs' bars, by need (NEEDS), each named with its Gains word.
var _needs: Dictionary[String, GrowBar] = {}
var _needs_grid: GridContainer
## Her bond's step as last shown: a warmer one pulses the bar.
var _step_shown := ""


func _init() -> void:
	name = "CardPage"
	visible = false
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiTheme.constant("row"))
	add_child(column)
	_title = Label.new()
	_title.theme_type_variation = &"Title"
	column.add_child(_title)
	_alone = Label.new()
	_alone.text = alone_words()
	_alone.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_alone)
	_learned_heading = _heading(column, "Learned")
	_learned = VBoxContainer.new()
	_learned.add_theme_constant_override("separation", UiTheme.constant("row"))
	column.add_child(_learned)
	_bent_heading = _heading(column, "Fighting")
	var centre := CenterContainer.new()
	column.add_child(centre)
	_chart = FocusChart.new()
	centre.add_child(_chart)
	_lean = Label.new()
	_lean.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lean.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_lean)
	_purse = Label.new()
	_purse.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_purse)
	_feels_heading = _heading(column, "Regard")
	_feels = Label.new()
	column.add_child(_feels)
	_bond = GrowBar.new(Color.html(str(Gains.TRACKS["bond"]["color"])), BAR_HEIGHT)
	column.add_child(_bond)
	_feels_why = Label.new()
	_feels_why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feels_why.add_theme_color_override("font_color", UiTheme.color("text_dim"))
	column.add_child(_feels_why)
	_needs_heading = _heading(column, NEEDS_HEADING)
	_needs_grid = GridContainer.new()
	_needs_grid.columns = 2
	_needs_grid.add_theme_constant_override("h_separation", UiTheme.constant("section"))
	_needs_grid.add_theme_constant_override("v_separation", UiTheme.constant("row"))
	column.add_child(_needs_grid)
	for need: String in NEEDS:
		var track: Dictionary = Gains.TRACKS[need]
		var name_label := Label.new()
		name_label.text = str(track["label"])
		name_label.theme_type_variation = &"Caption"
		_needs_grid.add_child(name_label)
		var bar := GrowBar.new(Color.html(str(track["color"])), NEED_BAR_HEIGHT)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_needs_grid.add_child(bar)
		_needs[need] = bar
	show_bars(Vector2i.ZERO, {}, "")


func _heading(column: VBoxContainer, words: String) -> Label:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, UiTheme.constant("section") - UiTheme.constant("row"))
	column.add_child(gap)
	var heading := Label.new()
	heading.theme_type_variation = &"Heading"
	heading.text = words
	column.add_child(heading)
	return heading


## The page from [param state] (Main.world_state) for the companion named
## [param her] by the sim (her body here), "" for none known that way: the
## state's "companion" names her otherwise. Nobody: the page says so.
## [param bond_step] and [param bond_why] are her body's (Companion), ""
## for none: the feelings row stays away without a step.
func show_state(state: Dictionary, her := "", bond_step := "", bond_why := "") -> void:
	var name_shown := her_name(state, her)
	var known := not name_shown.is_empty()
	_title.text = name_shown if known else "Your companion"
	_alone.visible = not known
	_learned_heading.visible = known
	_learned.visible = known
	_bent_heading.visible = known
	_chart.visible = known
	_lean.visible = known
	for child in _learned.get_children():
		child.queue_free()
	if known:
		var held := held_of(state)
		if held.is_empty():
			_add_line(_learned, nothing_learned_words())
		for entry: Dictionary in held:
			_add_line(_learned, held_words(entry))
		var focus := focus_of(state)
		_chart.focus = focus
		_chart.lean = CompanionCard.lean_of(focus) if not focus.is_empty() else ""
		_chart.queue_redraw()
		_lean.text = lean_words(_chart.lean) if not focus.is_empty() else unknown_bent_words()
	var purse := purse_words(state)
	_purse.visible = known and not purse.is_empty()
	_purse.text = purse
	var feels := feels_words(bond_step)
	_feels_heading.visible = known and not feels.is_empty()
	_feels.visible = _feels_heading.visible
	_feels.text = feels
	_feels_why.visible = _feels.visible and not bond_why.strip_edges().is_empty()
	_feels_why.text = bond_why.strip_edges() if _feels_why.visible else ""


func _add_line(into: VBoxContainer, words: String) -> void:
	var line := Label.new()
	line.text = words
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	into.add_child(line)


## Her bars from her body (Companion.bond_bar, needs, bond_step), while the
## page shows (Main: on open and every few frames): the bond's fill is x / y
## of its step, full at devoted (y 0); each need 0..1. A rise tweens and
## pulses, a warmer step pulses; a fall is shown at once, without a flourish
## (only what she gains is shown: 804). Her bond bar hides without a step,
## her needs without any.
func show_bars(bond_bar: Vector2i, needs: Dictionary, bond_step: String) -> void:
	var step := bond_step.strip_edges().to_lower()
	_bond.visible = _feels.visible and not step.is_empty()
	var warmer := STEPS.find(step) > STEPS.find(_step_shown) and not _step_shown.is_empty()
	_step_shown = step
	_bond.show_share(bond_share(bond_bar), warmer)
	var any := false
	for need: String in NEEDS:
		var has := needs.has(need)
		any = any or has
		_needs[need].show_share(clampf(float(needs.get(need, 0.0)), 0.0, 1.0), false)
	_needs_heading.visible = _title.text != "Your companion" and any
	_needs_grid.visible = _needs_heading.visible


## Her bond bar's fill: x of y into her step, full at devoted (y 0).
static func bond_share(bond_bar: Vector2i) -> float:
	return 1.0 if bond_bar.y <= 0 else clampf(float(bond_bar.x) / bond_bar.y, 0.0, 1.0)


## The bars as shown (tests): {"bond": share or -1 hidden, need: share... (shown ones)}.
func bars_shown() -> Dictionary:
	var out := {"bond": _bond.target if _bond.visible else -1.0}
	if _needs_grid.visible:
		for need: String in NEEDS:
			out[need] = _needs[need].target
	return out


## A bar that grows (804's flourish): its fill tweens up over RISE_SECONDS
## with a light pulse round it; a fall snaps. No numbers.
class GrowBar:
	extends Control
	var colour := Color.WHITE
	## The share shown now (tweened) and the one it is going to.
	var share := 0.0
	var target := 0.0
	var pulse := 0.0
	var _tween: Tween

	func _init(fill: Color, height: float) -> void:
		colour = fill
		custom_minimum_size = Vector2(0, height)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func show_share(to: float, stepped: bool) -> void:
		if is_equal_approx(to, target) and not stepped:
			return
		var rise := to > target + 0.0001 or stepped
		target = to
		if _tween != null:
			_tween.kill()
			_tween = null
		if rise and is_visible_in_tree():
			_tween = create_tween().set_parallel()
			_tween.tween_property(self, "share", to, CardPage.RISE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			pulse = 1.0
			_tween.tween_property(self, "pulse", 0.0, CardPage.RISE_SECONDS)
			_tween.tween_method(func(_v: float) -> void: queue_redraw(), 0.0, 1.0, CardPage.RISE_SECONDS)
		else:
			share = to
			pulse = 0.0
		queue_redraw()

	func _draw() -> void:
		var whole := Rect2(Vector2.ZERO, size)
		draw_rect(whole, UiTheme.color("backing_deep"))
		var inner := whole.grow(-2)
		if share > 0.0:
			draw_rect(Rect2(inner.position, Vector2(inner.size.x * clampf(share, 0.0, 1.0), inner.size.y)), colour)
		draw_rect(whole, UiTheme.color("edge") if pulse <= 0.0 else UiTheme.color("edge").lerp(colour.lightened(0.4), pulse), false, 2.0)


## The lines under "Learned" as shown (tests).
func learned_shown() -> PackedStringArray:
	var out := PackedStringArray()
	for child in _learned.get_children():
		if child is Label and not child.is_queued_for_deletion():
			out.append((child as Label).text)
	return out


func title_shown() -> String:
	return _title.text


func lean_shown() -> String:
	return _lean.text if _lean.visible else ""


func purse_shown() -> String:
	return _purse.text if _purse.visible else ""


func feels_shown() -> String:
	return _feels.text if _feels.visible else ""


func feels_why_shown() -> String:
	return _feels_why.text if _feels_why.visible else ""


## Her bond's tier as the party line says it: "Devoted.", "Wary."; "" for
## no step (the row stays away).
static func feels_words(bond_step: String) -> String:
	var word := bond_step.strip_edges()
	return word.capitalize() + "." if not word.is_empty() else ""


## Her name: the sim's, else the one the state's "focus" or "capabilities"
## carries, else "".
static func her_name(state: Dictionary, her := "") -> String:
	if not her.is_empty():
		return her
	for key in ["focus", "capabilities", "companion_gold"]:
		if state.get(key) is Dictionary and not str((state[key] as Dictionary).get("companion", "")).is_empty():
			return str((state[key] as Dictionary).get("companion"))
	return ""


## The state's held capabilities, each {id, words, teacher} (576), in the
## catalog's order; [] for none.
static func held_of(state: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state.get("capabilities") is Dictionary and (state["capabilities"] as Dictionary).get("held") is Array:
		for entry: Variant in (state["capabilities"] as Dictionary)["held"]:
			if entry is Dictionary:
				out.append(entry)
	return out


## The state's focus shares {fight, magic, stealth} (577); {} for none yet.
static func focus_of(state: Dictionary) -> Dictionary:
	if not state.get("focus") is Dictionary:
		return {}
	var out := {}
	for axis: Array in AXES:
		if (state["focus"] as Dictionary).has(axis[0]):
			out[axis[0]] = int((state["focus"] as Dictionary)[axis[0]])
	return out if out.size() == AXES.size() else {}


## One learned thing in her voice: "I hold the draugr's blessing; the
## draugr taught it to me." The id is never shown.
static func held_words(entry: Dictionary) -> String:
	var words := str(entry.get("words", "")).strip_edges()
	if words.is_empty():
		return ""
	var teacher := str(entry.get("teacher", "")).strip_edges()
	if teacher.is_empty():
		return "I hold %s." % words
	return "I hold %s; %s taught it to me." % [words, teacher]


## Her lean beside the chart: the sentence companion_traits.json "focus"
## "words" gives her own voice for it (Companion.focus_words, said to her
## as "you"), here said by her as "I", so the card and her mouth agree.
static func lean_words(lean: String) -> String:
	var words: Variant = CompanionCard.focus_rules().get("words", {})
	return first_person(str(words.get(lean, words.get("", ""))) if words is Dictionary else "")


## [param said] to her ("You lean to strength: in a fight you trust your
## arm.") as she says it ("I lean to strength: in a fight I trust my arm.").
static func first_person(said: String) -> String:
	var out := said
	for pair: Array in [["You are", "I am"], ["you are", "I am"], ["Your", "My"], ["your", "my"], ["You", "I"], ["you", "I"]]:
		out = out.replace(pair[0], pair[1])
	return out


## Her purse, once companions' "companion_gold" {companion, gold} is in the
## state (614): "" till then, and the row stays away.
static func purse_words(state: Dictionary) -> String:
	if not state.get("companion_gold") is Dictionary or not (state["companion_gold"] as Dictionary).has("gold"):
		return ""
	var gold := int((state["companion_gold"] as Dictionary)["gold"])
	if gold <= 0:
		return "My purse is empty."
	return "I carry %d gold for you. Only you may take it back." % gold


static func nothing_learned_words() -> String:
	return "Nothing yet. Each land we cross will teach me something."


static func unknown_bent_words() -> String:
	return "You have not seen me fight yet."


static func alone_words() -> String:
	return "No one travels with you."


## The chart's three points for [param focus] round [param centre]: each
## share's way out along its axis (the top, then clockwise), CHART_FULL at
## the corner.
static func chart_points(focus: Dictionary, centre: Vector2, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in AXES.size():
		var share := float(focus.get(AXES[i][0], 0))
		out.append(centre + axis_way(i) * radius * clampf(share / CHART_FULL, 0.0, 1.0))
	return out


## The unit vector of axis [param i]: up for the first, then clockwise.
static func axis_way(i: int) -> Vector2:
	return Vector2.from_angle(-PI / 2.0 + i * TAU / AXES.size())


## The drawn chart: a triangle in the panel's edge colour with a spoke to
## each corner, Jeff's word at each, her shares filled in the companion's
## colour, and a mark on the corner she leans to.
class FocusChart:
	extends Control
	const LABEL_ROOM := 70.0
	var focus: Dictionary = {}
	var lean := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2.ONE * (CardPage.CHART_RADIUS + LABEL_ROOM) * 2.0

	func _draw() -> void:
		var centre := size / 2.0
		var radius := CardPage.CHART_RADIUS
		var edge := UiTheme.color("edge")
		var corners := PackedVector2Array()
		for i in CardPage.AXES.size():
			corners.append(centre + CardPage.axis_way(i) * radius)
		for i in corners.size():
			draw_line(centre, corners[i], Color(edge, 0.7), 2.0, true)
			draw_line(corners[i], corners[(i + 1) % corners.size()], edge, 3.0, true)
		# The inner ring at half way, so the eye has a scale without a number.
		var half := PackedVector2Array()
		for i in corners.size():
			half.append(centre + CardPage.axis_way(i) * radius * 0.5)
		for i in half.size():
			draw_line(half[i], half[(i + 1) % half.size()], Color(edge, 0.5), 1.5, true)
		if not focus.is_empty():
			var points := CardPage.chart_points(focus, centre, radius)
			var friend := UiTheme.color("friend")
			draw_colored_polygon(points, Color(friend, 0.35))
			var closed := PackedVector2Array(points)
			closed.append(points[0])
			draw_polyline(closed, friend, 4.0, true)
			for i in CardPage.AXES.size():
				if CardPage.AXES[i][0] == lean:
					draw_circle(points[i], 9.0, UiTheme.color("brass"))
		var font := UiTheme.font("sans")
		var font_size := UiTheme.size("caption")
		var text := UiTheme.color("text")
		for i in CardPage.AXES.size():
			var word: String = CardPage.AXES[i][1]
			var width := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var at := corners[i] + CardPage.axis_way(i) * (LABEL_ROOM * 0.55)
			draw_string(font, Vector2(at.x - width / 2.0, at.y + font_size * 0.35), word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text)
