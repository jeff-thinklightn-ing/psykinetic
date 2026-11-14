class_name UiNamePlates
extends Control
## Names over heads, drawn on the HUD (decision 865; the coordinator's approval of
## the mock, 11-11, C:/dev/review/ui-design/names/): each visible name as bone
## text (NameText) on a soft dark pill (NamePlate), at one screen size at every
## zoom and depth, its foot just over the head. Nearer names are placed first; a
## plate that would meet a placed one steps up one plate, and one that still
## meets fades to SHADED. A boss's name carries its skull, left of the words.
## On the screen's edge (865, the coordinator's note on animation's Umbrage
## film, 11-11): a head off the screen, or nearer the lens than NEAR, has no
## plate; a plate whose head is on the screen but whose words would cross its
## edge is held inside it, EDGE in; and a step up that would leave the top
## fades in place instead. A name is never clipped and never grows.
## The view says what to draw: [member source] returns this frame's names, each
## {key, text, tint, plain, at (the head's screen point), depth, boss, named, bar, share,
## max_hp}; which names show, their words and tints stay the view's (Client3D.name_plates).
## A shown bar is drawn even where its name is not (hidden by the view, or nearer than NEAR):
## the bar alone, its foot just over the head, held inside the screen like a plate.
## Nothing is made a frame but the draw: widths are kept per text, the placed
## plates come from a pool, and the names are sorted where they lie.
##
## A body's health bar is a strip in its row (865 amended (3), the coordinator's yes to
## C:/dev/review/ui-design/bar_mock, 11-14): the theme's HpBar, its gap under the plate,
## per_hp long for each hp of its max (least to most), its fill the share left (fill_high,
## fill_mid under MID, fill_low under LOW), drawn while the view's "bar" shows it, faded by it.
## The row (plate and bar) is what meets another and steps up. Drawn, a row that has stepped
## stays up till the two would be clear by the theme's hold (and, met there by a third, fades
## where it is rather than dropping back), and moves to its place and its fade over STEP_EASE
## seconds, so two bodies brushing past each other never flicker between places.

## A plate past its one step that still meets another: this much of itself.
const SHADED := 0.4
## Between the head and the plate's foot, and between two stacked plates.
const LIFT := 10.0
const GAP := 6.0
## A head nearer the camera than this (in metres along its view) has no plate:
## its body fills that part of the view and the plate would cover it.
const NEAR := 1.5
## A plate held inside the screen stays this far from its edge.
const EDGE := 8.0
## The bar's fill turns fill_mid under this share of hp left, fill_low under LOW.
const MID := 0.5
const LOW := 0.25
## A stepped row comes to its new place in about this many seconds (95%), up and down.
const STEP_EASE := 0.15
## A key's step state is forgotten once unseen this many seconds.
const FORGET := 2.0

## Returns this frame's names (Client3D.name_plates).
var source: Callable
## Each text's measured width at the size it was measured, kept till it changes.
var _widths: Dictionary[String, float] = {}
var _measured_at := -1
var _skull: Texture2D
var _placed: Array[Dictionary] = []
var _pool: Array[Dictionary] = []
var _nearer := func(a: Dictionary, b: Dictionary) -> bool: return float(a["depth"]) < float(b["depth"])
## Per key: {up (stepped), off (its drawn offset, eased), seen (msec)}.
var _steps: Dictionary = {}
## Per StyleBoxFlat drawn faded: its one kept copy, whose colours are set for each draw.
var _faded: Dictionary = {}
var _drawn_ms := 0


func _init() -> void:
	name = "NamePlates"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if source.is_valid():
		queue_redraw()


func _draw() -> void:
	if not source.is_valid():
		return
	var font := get_theme_font(&"font", &"NameText")
	var size := get_theme_font_size(&"font_size", &"NameText")
	var plate := get_theme_stylebox(&"panel", &"NamePlate")
	var colour := get_theme_color(&"font_color", &"NameText")
	var now := Time.get_ticks_msec()
	var seconds := float(now - _drawn_ms) / 1000.0 if _drawn_ms > 0 else 1.0
	_drawn_ms = now
	for one: Dictionary in place(source.call(), font, size, plate, get_rect(), seconds):
		var rect: Rect2 = one["rect"]
		var alpha: float = one["alpha"]
		var entry: Dictionary = one["entry"]
		if one["bar"] != null:
			_draw_bar(one["bar"] as Rect2, float(entry.get("share", 1.0)), alpha * float(entry.get("bar", 0.0)))
		if not bool(one["named"]):
			continue
		_draw_faded(plate, rect, alpha)
		var ink: Color = colour if bool(entry.get("plain", true)) else (entry["tint"] as Color)
		ink.a *= alpha
		var x := rect.position.x + plate.get_margin(SIDE_LEFT)
		if bool(entry.get("boss", false)):
			var px := float(size)
			draw_texture_rect(_skull_texture(), Rect2(x, rect.position.y + (rect.size.y - px) / 2.0, px, px), false, ink)
			x += px + plate.get_margin(SIDE_LEFT) * 0.5
		var base := rect.position.y + plate.get_margin(SIDE_TOP) + font.get_ascent(size)
		draw_string(font, Vector2(x, base), str(entry["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)


## A health bar in [param rect] (the strip itself; its backing stands out by its own margins),
## [param share] of it filled, at [param alpha].
func _draw_bar(rect: Rect2, share: float, alpha: float) -> void:
	_draw_faded(get_theme_stylebox(&"panel", &"HpBar"), rect, alpha)
	var track := get_theme_color(&"track", &"HpBar")
	track.a *= alpha
	draw_rect(rect, track)
	var fill := get_theme_color(bar_fill(share), &"HpBar")
	fill.a *= alpha
	if share > 0.0:
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(share, 0.0, 1.0), rect.size.y)), fill)


## The theme's HpBar colour for [param share] of hp left.
static func bar_fill(share: float) -> StringName:
	if share < LOW:
		return &"fill_low"
	if share < MID:
		return &"fill_mid"
	return &"fill_high"


## [param box] drawn at [param alpha]: a StyleBoxFlat through one kept copy whose colours are
## set for each draw (a draw reads them as it is made), any other as it is.
func _draw_faded(box: StyleBox, rect: Rect2, alpha: float) -> void:
	if not box is StyleBoxFlat or alpha >= 1.0:
		draw_style_box(box, rect)
		return
	if not _faded.has(box):
		_faded[box] = box.duplicate()
	var flat := box as StyleBoxFlat
	var copy := _faded[box] as StyleBoxFlat
	copy.bg_color = Color(flat.bg_color, flat.bg_color.a * alpha)
	copy.border_color = Color(flat.border_color, flat.border_color.a * alpha)
	copy.shadow_color = Color(flat.shadow_color, flat.shadow_color.a * alpha)
	draw_style_box(copy, rect)


## [param entries] laid out: each its plate's rect and alpha, its bar's rect (or null) and its
## row (the two together, where it rests), nearer first, the rest stepped up one row or faded where
## they would meet a placed one. Sorts [param entries] in place; the result is this part's own
## array, reused. With [param screen], heads off it or nearer than NEAR get no plate and each
## row is held EDGE inside it. With [param seconds] (the time since the last draw), a row's
## step is held and eased (the theme's HpBar hold, STEP_EASE); without, each is laid afresh.
func place(entries: Array, font: Font, size: int, plate: StyleBox, screen := Rect2(), seconds := -1.0) -> Array[Dictionary]:
	if _measured_at != size:
		_widths.clear()
		_measured_at = size
	entries.sort_custom(_nearer)
	_placed.clear()
	var height := font.get_height(size) + plate.get_margin(SIDE_TOP) + plate.get_margin(SIDE_BOTTOM)
	var gap := float(get_theme_constant(&"gap", &"HpBar"))
	var bar_high := float(get_theme_constant(&"height", &"HpBar"))
	var per_hp := float(get_theme_constant(&"per_hp", &"HpBar"))
	var least := float(get_theme_constant(&"least", &"HpBar"))
	var most := float(get_theme_constant(&"most", &"HpBar"))
	var hold := float(get_theme_constant(&"hold", &"HpBar"))
	var held := screen.has_area()
	var inside := screen.grow(-EDGE)
	var remember := seconds >= 0.0
	var now := Time.get_ticks_msec()
	for entry: Dictionary in entries:
		if held and not screen.has_point(entry["at"]):
			continue
		# The row: the plate, and under it the bar while it shows. The bar is drawn whenever it shows, the
		# name hidden or not (the coordinator, 11-14: a hurt foe at arm's length is the bar most needed);
		# a name nearer than NEAR, or one the view hides ("named" false), is left out of its row.
		var barred := float(entry.get("bar", 0.0)) > 0.001
		var named := bool(entry.get("named", true)) and not (held and float(entry["depth"]) < NEAR)
		if not named and not barred:
			continue
		var width := 0.0
		if named:
			var text := str(entry["text"])
			if not _widths.has(text):
				_widths[text] = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			width = _widths[text] + plate.get_margin(SIDE_LEFT) + plate.get_margin(SIDE_RIGHT)
			if bool(entry.get("boss", false)):
				width += size + plate.get_margin(SIDE_LEFT) * 0.5
		var bar_wide := clampf(per_hp * float(entry.get("max_hp", 0)), least, most) if barred else 0.0
		var name_high := height if named else 0.0
		var row_high := name_high + ((gap if named else 0.0) + bar_high if barred else 0.0)
		var row_wide := maxf(width, bar_wide)
		var at: Vector2 = entry["at"]
		var row := Rect2(at.x - row_wide / 2.0, at.y - LIFT - row_high, row_wide, row_high)
		if held:
			row.position = row.position.clamp(inside.position, (inside.end - row.size).max(inside.position))
		var key: Variant = entry.get("key", null)
		var step: Dictionary = _steps.get(key, {}) if remember and key != null else {}
		var alpha := 1.0
		var target := row
		# A stepped row stays up while it is within hold of a placed one; a row on its stand steps on touching.
		var was_up := bool(step.get("up", false))
		var hit: Variant = _meets(row.grow(hold) if was_up else row)
		var up := hit != null
		if up:
			var lifted := row
			lifted.position.y = (hit as Rect2).position.y - row_high - GAP
			var past_top := held and lifted.position.y < inside.position.y
			if past_top or _meets(lifted) != null:
				if was_up and not past_top:
					# Up already, it stays up and fades there where a third now meets it: dropping to fade on its
					# stand for a frame and stepping back was the flicker bar_row4 caught (35 ms down and up).
					target = lifted
				else:
					up = false
				if was_up or _meets(row) != null:
					alpha = SHADED
			else:
				target = lifted
		var off := target.position.y - row.position.y
		if remember and key != null:
			var ease := pow(0.05, minf(seconds, 1.0) / STEP_EASE)
			var drawn := float(step.get("off", off))
			drawn = off + (drawn - off) * ease
			var shade := float(step.get("alpha", alpha))
			shade = alpha + (shade - alpha) * ease
			_steps[key] = {"up": up, "off": drawn, "alpha": shade, "seen": now}
			off = drawn
			alpha = shade
		var shown := row
		shown.position.y += off
		if _pool.size() <= _placed.size():
			_pool.append({})
		var one: Dictionary = _pool[_placed.size()]
		one["rect"] = Rect2(shown.position.x + (row_wide - width) / 2.0, shown.position.y, width, name_high)
		one["named"] = named
		one["bar"] = Rect2(shown.position.x + (row_wide - bar_wide) / 2.0, shown.position.y + row_high - bar_high, bar_wide, bar_high) if barred else null
		one["row"] = target
		one["alpha"] = alpha
		one["entry"] = entry
		_placed.append(one)
	if remember:
		for key: Variant in _steps.keys():
			if now - int((_steps[key] as Dictionary)["seen"]) > int(FORGET * 1000.0):
				_steps.erase(key)
	return _placed


## The first placed row's rect that meets [param rect], or null.
func _meets(rect: Rect2) -> Variant:
	for one: Dictionary in _placed:
		var other: Rect2 = one["row"]
		if other.intersects(rect):
			return other
	return null


func _skull_texture() -> Texture2D:
	if _skull == null:
		_skull = BossBar.skull_texture(64, Color.WHITE)
	return _skull
