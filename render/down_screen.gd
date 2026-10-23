class_name DownScreen
extends Control
## The down screen (decision 587, ui's side; Jeff's "mortally wounded"):
## over the view's grey while the local player lies downed, MORTALLY
## WOUNDED in big letters with the countdown under it, a bone ring behind
## them that swells and settles at the heart's pace (Player.heart beats a
## minute, replicated: 120, 80, 40), and two buttons: Slow Heart (Hold),
## which fills while the button is held (the heart steps down a beat at
## once and one every two seconds while held, companions' side) and is dim
## for the unblessed with the reason under it, and Bleed Out (Respawn).
## "ALL HAVE FALLEN" with its own count replaces the title when the
## return message says so (economy's {all_fallen: seconds}; 0 calls it
## off). Main feeds it each HUD tick (show) and sends the commands
## (slow_heart {held}, bleed_out). No bar, no number beyond the seconds,
## the theme's look (UiTheme, docs/ui_style.md).

signal slow_heart(held: bool)
signal bleed_out

const RING_RADIUS := 220.0
## How much the ring swells on a beat, and how fast it settles.
const RING_SWELL := 0.18
const RING_SETTLE := 6.0
## The hold's fill runs over the heart's step (two seconds a beat).
const HOLD_STEP_SECONDS := 2.0
const UNBLESSED_WHY := "only the draugr's blessed can hold on"

var _ring: RingControl
var _title: Label
var _count: Label
var _hold: Button
var _hold_fill: ColorRect
var _why: Label
var _bleed: Button
var _held := false
var _held_since := 0.0
var _heart := 0
var _beat_phase := 0.0
var _swell := 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _ready() -> void:
	_ring = RingControl.new()
	_ring.set_anchors_preset(Control.PRESET_CENTER)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ring)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", UiTheme.constant("row"))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	_title = Label.new()
	_title.theme_type_variation = &"Display"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)
	_count = Label.new()
	_count.theme_type_variation = &"Hud"
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_count)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, UiTheme.constant("section") * 2)
	column.add_child(gap)
	_hold = Button.new()
	_hold.text = "Slow Heart (Hold)"
	_hold.focus_mode = Control.FOCUS_NONE
	_hold.custom_minimum_size = Vector2(640, 0)
	_hold.button_down.connect(_hold_down)
	_hold.button_up.connect(_hold_up)
	_hold_fill = ColorRect.new()
	_hold_fill.color = Color(UiTheme.color("brass"), 0.35)
	_hold_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hold_fill.show_behind_parent = true
	_hold_fill.size = Vector2.ZERO
	_hold.add_child(_hold_fill)
	column.add_child(_hold)
	_why = Label.new()
	_why.theme_type_variation = &"Caption"
	_why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_why.add_theme_color_override("font_color", UiTheme.color("text_dim"))
	column.add_child(_why)
	_bleed = Button.new()
	_bleed.text = "Bleed Out (Respawn)"
	_bleed.focus_mode = Control.FOCUS_NONE
	_bleed.custom_minimum_size = Vector2(640, 0)
	_bleed.pressed.connect(func() -> void: bleed_out.emit())
	column.add_child(_bleed)


## Each HUD tick: shown while [param downed]; [param seconds] left before
## the blood runs out, [param heart] the beats a minute, [param blessed]
## whether the hold is theirs, [param all_fallen] seconds of everyone's
## wait (0 for none).
func show_state(downed: bool, seconds: int, heart: int, blessed: bool, all_fallen: int) -> void:
	if not downed:
		if visible:
			_let_go()
		visible = false
		return
	visible = true
	_heart = heart
	_title.text = title_words(all_fallen > 0)
	_count.text = count_words(seconds, all_fallen)
	_hold.disabled = not blessed
	_why.text = "" if blessed else UNBLESSED_WHY
	_why.visible = not blessed


## The title: everyone's fall replaces the player's own.
static func title_words(all_fallen: bool) -> String:
	return "ALL HAVE FALLEN" if all_fallen else "MORTALLY WOUNDED"


## The count under it: the seconds the blood lasts, or everyone's wait.
static func count_words(seconds: int, all_fallen: int) -> String:
	if all_fallen > 0:
		return "all come back in %d s" % all_fallen
	return "%d s" % maxi(seconds, 0)


## The hold's fill (0 to 1) [param held_for] seconds into the hold: one
## heart step's worth, wrapping each step.
static func hold_fill(held_for: float) -> float:
	return fmod(maxf(held_for, 0.0), HOLD_STEP_SECONDS) / HOLD_STEP_SECONDS if held_for > 0.0 else 0.0


func _hold_down() -> void:
	if _hold.disabled or _held:
		return
	_held = true
	_held_since = Time.get_ticks_msec() / 1000.0
	slow_heart.emit(true)


func _hold_up() -> void:
	if _held:
		_let_go()


func _let_go() -> void:
	_held = false
	_hold_fill.size = Vector2.ZERO
	slow_heart.emit(false)


func is_held() -> bool:
	return _held


func _process(delta: float) -> void:
	if not visible:
		return
	if _held:
		var fill := hold_fill(Time.get_ticks_msec() / 1000.0 - _held_since)
		_hold_fill.size = Vector2(_hold.size.x * fill, _hold.size.y)
	# The pulse: a swell on each beat at the heart's pace, settling between.
	if _heart > 0:
		var before := _beat_phase
		_beat_phase = fmod(_beat_phase + delta * _heart / 60.0, 1.0)
		if _beat_phase < before:
			_swell = 1.0
	_swell = move_toward(_swell, 0.0, delta * RING_SETTLE)
	_ring.swell = _swell
	_ring.queue_redraw()


## The bone ring behind the words, swelling with the heart.
class RingControl:
	extends Control
	var swell := 0.0

	func _draw() -> void:
		var radius := DownScreen.RING_RADIUS * (1.0 + DownScreen.RING_SWELL * swell)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 96, Color(UiTheme.color("text"), 0.18 + 0.25 * swell), 6.0, true)
