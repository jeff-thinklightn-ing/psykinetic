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
## The shared theme's (UiTheme, docs/ui_style.md): a panel's backing, bone
## text in the serif face, at the theme's speech size.
static var BACKGROUND: Color = UiTheme.color("backing")
static var TEXT: Color = UiTheme.color("text")
static var FONT_SIZE: int = UiTheme.size("speech")
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
## 865 amended (10), A: a bubble is set at its zoom only until the view is at zoom 1.0 (the
## view CAMERA_SIZE tiles tall); nearer, it stays that size, as the name plates do.
const MOST_TILES_TALL := Client3D.CAMERA_SIZE
## C: a bubble is held this far inside the screen's edge (HUD px).
const EDGE := 16.0
## A speaker's face and what is round it, under their plate, in tiles: a bubble beside the plate
## keeps off it where it can.
const FACE_SIZE := Vector2(1.0, 1.0)
## Where a bubble's tail points: down at a head under it, up at a head off the screen's top, or
## sideways at a head beside it.
enum Tail { DOWN, UP, LEFT, RIGHT }

var anchor_of: Callable
var tile_px: Callable
## The speaker's own name row as drawn (UiNamePlates.placed_rect: key -> Rect2 in HUD px), empty for
## none. The tail's tip stands GAP over it and nothing of the bubble covers it (B).
var plate_of: Callable
## The HUD's own blocks a bubble keeps off (the compass and its place name, the minimap, the hint
## lines): a Callable returning Rects in HUD px; empty ones are skipped (D).
var keep_off: Callable

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


## Which side [param key]'s tail is on (Tail), -1 for no bubble (for tests).
func tail_of(key: int) -> int:
	var bubble: Bubble = _bubbles.get(key)
	return bubble.tail if bubble != null else -1


func count() -> int:
	return _bubbles.size()


## Where [param key]'s bubble is on screen, laid out (for tests).
func rect_of(key: int) -> Rect2:
	var bubble: Bubble = _bubbles.get(key)
	return Rect2(bubble.position, bubble.size) if bubble != null else Rect2()


## The speaker whose bubble is under [param at] (the bubbles never take the mouse, and a click
## over one goes to what is beneath, 560 amended), 0 for none (for tests).
func key_at(at: Vector2) -> int:
	for key: int in _bubbles:
		var bubble: Bubble = _bubbles[key]
		if bubble.visible and Rect2(bubble.position, bubble.size).has_point(at):
			return key
	return 0


func _drop(key: int, bubble: Bubble) -> void:
	if _bubbles.get(key) == bubble:
		_bubbles.erase(key)
	bubble.queue_free()


func _process(_delta: float) -> void:
	queue_redraw()


## The bubbles are laid out in this part's draw, after the name plates' (drawn before it: the HUD
## keeps them under the bubbles) have placed this frame's rows: a bubble read the last frame's plate
## from its own _process, and beside a moving speaker stood over it by the plate's one step (865
## amended (10): ui-design's P2_pullin_z04, the tail's tip 8 px into the plate).
func _draw() -> void:
	_layout()


## Places every bubble with its tail on its speaker, the lowest on screen
## first, each kept clear of the bubbles already placed and of every
## speaker's name: nudged sideways, away from what it would cover, when a
## little is enough, otherwise up (865 amended (10)):
## [br]A: one size from zoom 1.0 in (MOST_TILES_TALL).
## [br]B: the tail's tip GAP over the speaker's own plate, nothing of the bubble on that plate;
## on the head (the anchor) when no plate is drawn.
## [br]C: held inside the screen: where it would go over the top it stands beside the plate, its
## tail sideways, on the side clear of the speaker's face and of the HUD's blocks (the side toward
## the screen's middle first); with no plate drawn (the head off the top) it keeps to the top, its
## tail up toward the head.
## [br]D: off the HUD's blocks, by the shortest step that stays on the screen and off the plate.
func _layout() -> void:
	var screen := get_rect()
	if screen.size.y <= 0.0:
		screen = get_viewport_rect()
	var real_tile := REFERENCE_TILE_PX
	if tile_px.is_valid():
		real_tile = maxf(float(tile_px.call()), 1.0)
	var scale_now := minf(real_tile, screen.size.y / MOST_TILES_TALL) / REFERENCE_TILE_PX
	var inside := screen.grow(-EDGE)
	var blocks: Array = keep_off.call() if keep_off.is_valid() else []
	var anchors := {}
	for key: int in _bubbles:
		var at: Variant = anchor_of.call(key) if anchor_of.is_valid() else null
		_bubbles[key].visible = at is Vector2
		if at is Vector2:
			anchors[key] = at
	var order: Array = anchors.keys()
	order.sort_custom(func(a: int, b: int) -> bool: return anchors[a].y > anchors[b].y)
	var taken: Array[Rect2] = []
	var plates := {}
	var faces := {}
	var drawn := {}
	for key: int in order:
		var plate: Rect2 = plate_of.call(key) if plate_of.is_valid() else Rect2()
		drawn[key] = plate.has_area() and inside.intersects(plate)
		if not plate.has_area():
			plate = Rect2(anchors[key] + Vector2(-NAME_SIZE.x * 0.5, 0.0) * real_tile, NAME_SIZE * real_tile)
		plates[key] = plate
		faces[key] = Rect2(Vector2(plate.get_center().x - FACE_SIZE.x * real_tile * 0.5, plate.end.y), FACE_SIZE * real_tile)
		taken.append(plate)
	for key: int in order:
		var bubble: Bubble = _bubbles[key]
		bubble.point(Tail.DOWN)
		bubble.fit(scale_now)
		var at: Vector2 = anchors[key]
		var own_name: Rect2 = plates[key]
		var face: Rect2 = faces[key]
		var rect := Rect2(Vector2(at.x - bubble.size.x * 0.5, own_name.position.y - GAP - bubble.size.y), bubble.size)
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
		var aim := at
		if rect.position.y < inside.position.y:
			if not drawn[key] and at.y < inside.position.y:
				bubble.point(Tail.UP)
				bubble.fit(scale_now)
				rect = Rect2(Vector2(at.x - bubble.size.x * 0.5, inside.position.y), bubble.size)
			else:
				# The plate drawn, or the head on the screen with its plate hidden (behind another person: the anchor's own): beside it, the tail sideways.
				var beside := _beside(bubble, scale_now, own_name, face, inside, blocks)
				rect = beside[0]
				aim = beside[1]
		rect = _held(rect, inside)
		var stepped_off := false
		for block: Rect2 in blocks:
			if not block.has_area() or not rect.intersects(block.grow(GAP)):
				continue
			var steps: Array[Rect2] = []
			for to: Vector2 in [Vector2(block.position.x - GAP - rect.end.x, 0.0), Vector2(block.end.x + GAP - rect.position.x, 0.0),
					Vector2(0.0, block.end.y + GAP - rect.position.y), Vector2(0.0, block.position.y - GAP - rect.end.y)]:
				var stepped := Rect2(rect.position + to, rect.size)
				if inside.encloses(stepped) and not stepped.intersects(own_name):
					steps.append(stepped)
			var here := rect
			steps.sort_custom(func(a: Rect2, b: Rect2) -> bool:
				if a.intersects(face) != b.intersects(face):
					return b.intersects(face)
				return a.position.distance_to(here.position) < b.position.distance_to(here.position))
			if not steps.is_empty():
				rect = steps[0]
				stepped_off = true
		if stepped_off and bubble.tail == Tail.DOWN and (at.x < rect.position.x or at.x > rect.end.x):
			# A step that left the speaker outside the bubble's width: beside its plate instead, the tail still on the speaker.
			var beside := _beside(bubble, scale_now, own_name, face, inside, blocks)
			rect = beside[0]
			aim = beside[1]
		taken.append(rect)
		bubble.position = rect.position
		var pad := CORNER * 2.0 * scale_now
		if bubble.tail == Tail.LEFT or bubble.tail == Tail.RIGHT:
			bubble.tail_x = clampf(aim.y - rect.position.y, pad, maxf(rect.size.y - pad, pad))
		else:
			bubble.tail_x = clampf(at.x - rect.position.x, pad, maxf(rect.size.x - pad, pad))


## [param bubble] beside the speaker's plate [param own_name], its tail sideways: [rect, where the
## tail points]. The side toward the screen's middle first; a side is passed over that is off the
## screen or on one of [param blocks], and the places clear of the speaker's [param face] come before
## those that only clear the plate. The bubble is left set for the side it is given.
func _beside(bubble: Bubble, scale_now: float, own_name: Rect2, face: Rect2, inside: Rect2, blocks: Array) -> Array:
	var rights := [true, false] if own_name.get_center().x < inside.get_center().x else [false, true]
	var first := []
	for over: Rect2 in [own_name.merge(face), own_name]:
		for right: bool in rights:
			bubble.point(Tail.LEFT if right else Tail.RIGHT)
			bubble.fit(scale_now)
			var aim := Vector2(over.end.x + GAP if right else over.position.x - GAP, own_name.get_center().y)
			var rect := Rect2(Vector2(aim.x if right else aim.x - bubble.size.x, aim.y - bubble.size.y * 0.5), bubble.size)
			rect.position.y = clampf(rect.position.y, inside.position.y, maxf(inside.end.y - rect.size.y, inside.position.y))
			if first.is_empty():
				first = [rect, aim, right]
			if inside.encloses(rect) and _clear(rect, blocks):
				return [rect, aim]
	# No side is clear: the first (clear of the face, toward the middle), held on the screen after.
	bubble.point(Tail.LEFT if first[2] else Tail.RIGHT)
	bubble.fit(scale_now)
	return [first[0], first[1]]


## Whether [param rect] meets none of [param blocks].
static func _clear(rect: Rect2, blocks: Array) -> bool:
	for block: Rect2 in blocks:
		if block.has_area() and rect.intersects(block.grow(GAP)):
			return false
	return true


## [param rect] moved the least to lie inside [param inside].
static func _held(rect: Rect2, inside: Rect2) -> Rect2:
	rect.position.x = clampf(rect.position.x, inside.position.x, maxf(inside.end.x - rect.size.x, inside.position.x))
	rect.position.y = clampf(rect.position.y, inside.position.y, maxf(inside.end.y - rect.size.y, inside.position.y))
	return rect


## One bubble: the panel with its text, and the tail drawn beside it.
class Bubble:
	extends Control

	var panel := PanelContainer.new()
	var label := Label.new()
	var _style := StyleBoxFlat.new()
	var _scale := -1.0
	## Where along its side the tail is, pointing at the speaker.
	var tail_x := -1.0
	## Which side the tail is on (SpeechBubbles.Tail); the next fit lays the panel for it.
	var tail: int = SpeechBubbles.Tail.DOWN

	func point(side: int) -> void:
		tail = side

	func _init(text: String) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_style.bg_color = SpeechBubbles.BACKGROUND
		panel.add_theme_stylebox_override("panel", _style)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.text = text
		label.add_theme_color_override("font_color", SpeechBubbles.TEXT)
		label.add_theme_font_override("font", UiTheme.font("serif"))
		label.add_theme_constant_override("line_spacing", 0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel.add_child(label)
		add_child(panel)

	## Sized for [param k] times the reference zoom: font, padding, corner,
	## width and tail, all set at that size. Its size is the panel's and the
	## tail beside it, the panel placed in it for the tail's side.
	func fit(k: float) -> void:
		if absf(k - _scale) > 0.01:
			_scale = k
			var font_size := maxi(roundi(SpeechBubbles.FONT_SIZE * k), 6)
			label.add_theme_font_size_override("font_size", font_size)
			_style.set_corner_radius_all(roundi(SpeechBubbles.CORNER * k))
			_style.content_margin_left = SpeechBubbles.PADDING.x * k
			_style.content_margin_right = SpeechBubbles.PADDING.x * k
			_style.content_margin_top = SpeechBubbles.PADDING.y * k
			_style.content_margin_bottom = SpeechBubbles.PADDING.y * k
			var font := label.get_theme_font("font")
			var widest := (SpeechBubbles.MAX_WIDTH_TILES * SpeechBubbles.REFERENCE_TILE_PX - SpeechBubbles.PADDING.x * 2.0) * k
			var natural := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 2.0
			var width := minf(natural, widest)
			label.custom_minimum_size = Vector2(width, 0.0)
			# The wrapped height is the label's at that width.
			label.size = Vector2(width, 0.0)
			label.custom_minimum_size.y = label.get_minimum_size().y
			panel.size = Vector2.ZERO
		panel.reset_size()
		var t := SpeechBubbles.TAIL.y * _scale
		match tail:
			SpeechBubbles.Tail.UP:
				panel.position = Vector2(0.0, t)
				size = panel.size + Vector2(0.0, t)
			SpeechBubbles.Tail.LEFT:
				panel.position = Vector2(t, 0.0)
				size = panel.size + Vector2(t, 0.0)
			SpeechBubbles.Tail.RIGHT:
				panel.position = Vector2.ZERO
				size = panel.size + Vector2(t, 0.0)
			_:
				panel.position = Vector2.ZERO
				size = panel.size + Vector2(0.0, t)
		queue_redraw()

	func _draw() -> void:
		var w := SpeechBubbles.TAIL.x * _scale * 0.5
		var h := SpeechBubbles.TAIL.y * _scale
		var p := panel.position
		var s := panel.size
		var vertical := tail == SpeechBubbles.Tail.LEFT or tail == SpeechBubbles.Tail.RIGHT
		var along := tail_x if tail_x >= 0.0 else (s.y if vertical else s.x) * 0.5
		var points: PackedVector2Array
		match tail:
			SpeechBubbles.Tail.UP:
				points = [Vector2(along - w, p.y), Vector2(along + w, p.y), Vector2(along, 0.0)]
			SpeechBubbles.Tail.LEFT:
				points = [Vector2(p.x, along - w), Vector2(p.x, along + w), Vector2(0.0, along)]
			SpeechBubbles.Tail.RIGHT:
				points = [Vector2(s.x, along - w), Vector2(s.x, along + w), Vector2(s.x + h, along)]
			_:
				points = [Vector2(along - w, s.y), Vector2(along + w, s.y), Vector2(along, s.y + h)]
		draw_colored_polygon(points, SpeechBubbles.BACKGROUND)
