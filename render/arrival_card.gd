class_name ArrivalCard
extends Control
## The zone arrival card (decision 660, ui's side; perf's phased zone
## arrival): a crossing's frames are no longer frozen for the rebuild, so
## the view fades to a near-dark and the zone's name is said while the
## builders run over frames. begin(zone_name, line) as the crossing starts:
## the dark (the theme's outline colour at DARK_ALPHA, never black) comes in
## over DARK_IN seconds and the name with it, Alegreya at the title size with
## the text outline and no box, a third of the way down; an optional line
## under it, dim; a short bone rule under them breathes while the build
## runs (no spinner, no bar: the no-bars rule, and nothing to count).
## finish() when Client3D.building turns false: the dark lifts over DARK_OUT
## so the world is back as soon as the rebuild is, and the name stays over
## the world until NAME_HOLD from begin (a sub-second crossing still shows
## a readable name), then fades over NAME_OUT. begin() while the card is up
## (a link straight back, a death mid-arrival) restarts the name from the
## dark's current alpha, no flash. Input is held by perf's side; the card
## ignores the mouse. It advances itself each frame (advance); nothing
## lengthens the crossing. Presentation only.

const DARK_ALPHA := 0.92
const DARK_IN := 0.2
const DARK_OUT := 0.3
## Seconds from begin the name stays at least; and its fade after.
const NAME_HOLD := 1.5
const NAME_OUT := 0.4
const BREATH_PERIOD := 1.6
## Where the name sits: this far down the screen.
const NAME_TOP := 1.0 / 3.0
const RULE_SIZE := Vector2(160.0, 4.0)

## True from begin() until the name has faded.
var showing := false
var zone_name := ""
var _building := false
## The dark's alpha now; kept across a begin() while up.
var _dark := 0.0
## Seconds since begin, and since-time of finish (-1 while building).
var _since := 0.0
var _finished_at := -1.0

var _dark_rect: ColorRect
var _column: VBoxContainer
var _name: Label
var _line: Label
var _rule: ColorRect


func _init() -> void:
	name = "ArrivalCard"
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50  # Above every panel of the HUD.


func _ready() -> void:
	_dark_rect = ColorRect.new()
	_dark_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dark_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dark_rect)
	_column = VBoxContainer.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_column.anchor_top = NAME_TOP
	_column.anchor_bottom = NAME_TOP
	_column.grow_vertical = Control.GROW_DIRECTION_BOTH
	_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_column.add_theme_constant_override("separation", UiTheme.constant("row"))
	add_child(_column)
	_name = Label.new()
	_name.theme_type_variation = &"Title"
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.add_theme_color_override("font_outline_color", UiTheme.color("outline"))
	_name.add_theme_constant_override("outline_size", UiTheme.constant("outline"))
	_column.add_child(_name)
	_line = Label.new()
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.add_theme_color_override("font_color", UiTheme.color("text_dim"))
	_line.add_theme_color_override("font_outline_color", UiTheme.color("outline"))
	_line.add_theme_constant_override("outline_size", UiTheme.constant("outline"))
	_line.visible = false
	_column.add_child(_line)
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(centre)
	_rule = ColorRect.new()
	_rule.custom_minimum_size = RULE_SIZE
	_rule.color = UiTheme.color("text")
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(_rule)
	_apply()


func _process(delta: float) -> void:
	advance(delta)


## A crossing into [param zone] starts: the dark comes in (from where it
## is, if the card is up) and the name is said; [param line] under it when
## given. The name is the zone's display name, as the map shows it, never
## a level id (Main.zone_display_name); "" says no name.
func begin(zone: String, line := "") -> void:
	zone_name = zone.strip_edges()
	showing = true
	_building = true
	_since = 0.0
	_finished_at = -1.0
	visible = true
	if _name != null:
		_name.text = zone_name
		_line.text = line.strip_edges()
		_line.visible = not _line.text.is_empty()
	_apply()


## The rebuild is done: the dark lifts; the name stays its while.
func finish() -> void:
	if not showing or not _building:
		return
	_building = false
	_finished_at = _since


## [param delta] seconds on: the dark in or out, the name's time, the rule's breath.
func advance(delta: float) -> void:
	if not showing:
		return
	_since += delta
	if _building:
		_dark = minf(DARK_ALPHA, _dark + delta / DARK_IN * DARK_ALPHA)
	else:
		_dark = maxf(0.0, _dark - delta / DARK_OUT * DARK_ALPHA)
	if not _building and _dark <= 0.0 and name_alpha() <= 0.0:
		showing = false
		visible = false
	_apply()


## The name's alpha now.
func name_alpha() -> float:
	return name_alpha_at(_since, _finished_at)


## The name's alpha [param since] seconds from begin, finish() called at
## [param finished_at] (-1 for not yet): in with the dark over DARK_IN; held
## until NAME_HOLD or until the dark has lifted, whichever is later; then
## out over NAME_OUT.
static func name_alpha_at(since: float, finished_at: float) -> float:
	var alpha := clampf(since / DARK_IN, 0.0, 1.0)
	if finished_at >= 0.0:
		var leave := maxf(NAME_HOLD, finished_at + DARK_OUT)
		if since > leave:
			alpha = minf(alpha, clampf(1.0 - (since - leave) / NAME_OUT, 0.0, 1.0))
	return alpha


## The rule's breath: 0.5 to 0.9 and back each BREATH_PERIOD.
static func breath_at(since: float) -> float:
	return 0.7 + 0.2 * sin(TAU * since / BREATH_PERIOD)


func _apply() -> void:
	if _dark_rect == null:
		return
	var outline := UiTheme.color("outline")
	_dark_rect.color = Color(outline.r, outline.g, outline.b, _dark)
	var alpha := name_alpha()
	_name.modulate = Color(1, 1, 1, alpha)
	_line.modulate = Color(1, 1, 1, alpha)
	# The rule breathes while the build runs and goes with the dark.
	_rule.modulate = Color(1, 1, 1, breath_at(_since) * (_dark / DARK_ALPHA) if _building or _dark > 0.0 else 0.0)
