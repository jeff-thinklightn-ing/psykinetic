class_name SpeechBubbles
extends Control
## Speech over whoever said it, players and companions alike: a small dark
## rounded bubble, light text, a short tail pointing down at the speaker,
## at most MAX_WIDTH_TILES wide with the words wrapped, just above the name.
## It is drawn on the HUD, so nothing in the world hides it, and scaled with
## the view's zoom (its font set at the zoomed size, so it stays sharp).
## It fades in over FADE_IN, holds HOLD_SECONDS and a
## second more per CHARS_PER_SECOND characters, and fades out over FADE_OUT.
## A new line from the same speaker replaces their bubble; the bubbles of
## different speakers are nudged apart, upward, instead of overlapping.
##
## The view says where a speaker is: [member anchor_of] (key -> the screen
## point just above their name, or null when they are not to be seen) and
## [member tile_px] (screen px per tile now). A key is the speaker's
## instance id (or a corpse puppet's, for last words).

const FADE_IN := 0.1
const FADE_OUT := 0.3
const HOLD_SECONDS := 4.0
const CHARS_PER_SECOND := 40.0
const MAX_WIDTH_TILES := 3.0
const BACKGROUND := Color(0.05, 0.05, 0.07, 0.7)
const TEXT := Color(0.94, 0.94, 0.9)
const FONT_SIZE := 15
## Laid out for this many screen px per tile, then scaled to the view's.
const REFERENCE_TILE_PX := 64.0
const PADDING := Vector2(7, 4)
const CORNER := 6
const TAIL := Vector2(10, 7)
## Space kept between two speakers' bubbles.
const GAP := 3.0
## A speaker's name, under their anchor, in tiles: no bubble covers it.
const NAME_SIZE := Vector2(1.1, 0.35)
## A bubble moves sideways at most this share of its width off its speaker
## to keep clear; further than that, it moves up instead.
const SIDEWAYS_AT_MOST := 0.5

var anchor_of: Callable
var tile_px: Callable

var _bubbles: Dictionary[int, Bubble] = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## How long a line of [param text] stays fully shown.
static func hold_seconds(text: String) -> float:
	return HOLD_SECONDS + floorf(text.length() / CHARS_PER_SECOND)


## Shows [param text] over speaker [param key], replacing their last bubble.
func show_line(key: int, text: String) -> void:
	if text.strip_edges().is_empty():
		return
	var old: Bubble = _bubbles.get(key)
	if old != null:
		old.queue_free()
	var bubble := Bubble.new(text)
	add_child(bubble)
	_bubbles[key] = bubble
	bubble.modulate.a = 0.0
	var fade := bubble.create_tween()
	fade.tween_property(bubble, "modulate:a", 1.0, FADE_IN)
	fade.tween_interval(hold_seconds(text))
	fade.tween_property(bubble, "modulate:a", 0.0, FADE_OUT)
	fade.tween_callback(_drop.bind(key, bubble))
	_layout()


## The text of [param key]'s bubble, "" for none (for tests).
func text_of(key: int) -> String:
	var bubble: Bubble = _bubbles.get(key)
	return bubble.label.text if bubble != null else ""


func count() -> int:
	return _bubbles.size()


## Where [param key]'s bubble is on screen, laid out (for tests).
func rect_of(key: int) -> Rect2:
	var bubble: Bubble = _bubbles.get(key)
	return Rect2(bubble.position, bubble.size) if bubble != null else Rect2()


func _drop(key: int, bubble: Bubble) -> void:
	if _bubbles.get(key) == bubble:
		_bubbles.erase(key)
	bubble.queue_free()


func _process(_delta: float) -> void:
	_layout()


## Places every bubble with its tail on its speaker, the lowest on screen
## first, each kept clear of the bubbles already placed and of every
## speaker's name (just under their anchor): nudged sideways, away from
## what it would cover, when a little is enough, otherwise up.
func _layout() -> void:
	var scale_now := 1.0
	if tile_px.is_valid():
		scale_now = maxf(float(tile_px.call()), 1.0) / REFERENCE_TILE_PX
	var tile := REFERENCE_TILE_PX * scale_now
	var anchors := {}
	for key: int in _bubbles:
		var at: Variant = anchor_of.call(key) if anchor_of.is_valid() else null
		_bubbles[key].visible = at is Vector2
		if at is Vector2:
			anchors[key] = at
	var order: Array = anchors.keys()
	order.sort_custom(func(a: int, b: int) -> bool: return anchors[a].y > anchors[b].y)
	var taken: Array[Rect2] = []
	for key: int in order:
		taken.append(Rect2(anchors[key] + Vector2(-NAME_SIZE.x * 0.5, 0.0) * tile, NAME_SIZE * tile))
	for key: int in order:
		var bubble: Bubble = _bubbles[key]
		bubble.fit(scale_now)
		var at: Vector2 = anchors[key]
		var rect := Rect2(at - Vector2(bubble.size.x * 0.5, bubble.size.y), bubble.size)
		var own_name := taken[order.find(key)]
		var tries := 0
		var moved := true
		while moved and tries < 64:
			moved = false
			tries += 1
			for other in taken:
				if other == own_name or not rect.grow(GAP * 0.5).intersects(other.grow(GAP * 0.5)):
					continue
				var aside := rect
				if at.x >= other.get_center().x:
					aside.position.x = other.end.x + GAP
				else:
					aside.position.x = other.position.x - rect.size.x - GAP
				if absf(aside.get_center().x - at.x) <= rect.size.x * SIDEWAYS_AT_MOST:
					rect = aside
				else:
					rect.position.y = other.position.y - rect.size.y - GAP
				moved = true
		taken.append(rect)
		bubble.position = rect.position
		bubble.tail_x = clampf(at.x - rect.position.x, CORNER * 2.0 * scale_now, rect.size.x - CORNER * 2.0 * scale_now)


## One bubble: the panel with its text, and the tail drawn under it.
class Bubble:
	extends Control

	var panel := PanelContainer.new()
	var label := Label.new()
	var _style := StyleBoxFlat.new()
	var _scale := -1.0
	## Where along the bottom the tail is, pointing at the speaker.
	var tail_x := -1.0

	func _init(text: String) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_style.bg_color = BACKGROUND
		panel.add_theme_stylebox_override("panel", _style)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.text = text
		label.add_theme_color_override("font_color", TEXT)
		label.add_theme_constant_override("line_spacing", 0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel.add_child(label)
		add_child(panel)

	## Sized for [param k] times the reference zoom: font, padding, corner,
	## width and tail, all set at that size. Its size is the panel's and the
	## tail under it.
	func fit(k: float) -> void:
		if absf(k - _scale) > 0.01:
			_scale = k
			var font_size := maxi(roundi(FONT_SIZE * k), 6)
			label.add_theme_font_size_override("font_size", font_size)
			_style.set_corner_radius_all(roundi(CORNER * k))
			_style.content_margin_left = PADDING.x * k
			_style.content_margin_right = PADDING.x * k
			_style.content_margin_top = PADDING.y * k
			_style.content_margin_bottom = PADDING.y * k
			var font := label.get_theme_font("font")
			var widest := (MAX_WIDTH_TILES * REFERENCE_TILE_PX - PADDING.x * 2.0) * k
			var natural := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 2.0
			var width := minf(natural, widest)
			label.custom_minimum_size = Vector2(width, 0.0)
			# The wrapped height is the label's at that width.
			label.size = Vector2(width, 0.0)
			label.custom_minimum_size.y = label.get_minimum_size().y
			panel.size = Vector2.ZERO
		panel.reset_size()
		size = panel.size + Vector2(0.0, TAIL.y * _scale)
		queue_redraw()

	func _draw() -> void:
		var middle := tail_x if tail_x >= 0.0 else panel.size.x * 0.5
		var top := panel.size.y
		var tail := TAIL * _scale
		draw_colored_polygon(PackedVector2Array([Vector2(middle - tail.x * 0.5, top),
			Vector2(middle + tail.x * 0.5, top), Vector2(middle, top + tail.y)]), BACKGROUND)
