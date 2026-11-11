class_name UiNamePlates
extends Control
## Names over heads, drawn on the HUD (decision 865; the coordinator's approval of
## the mock, 11-11, C:/dev/review/ui-design/names/): each visible name as bone
## text (NameText) on a soft dark pill (NamePlate), at one screen size at every
## zoom and depth, its foot just over the head. Nearer names are placed first; a
## plate that would meet a placed one steps up one plate, and one that still
## meets fades to SHADED. A boss's name carries its skull, left of the words.
## The view says what to draw: [member source] returns this frame's names, each
## {key, text, tint, plain, at (the head's screen point), depth, boss}; which
## names show, their words and tints stay the view's (Client3D.name_plates).
## Nothing is made a frame but the draw: widths are kept per text, the placed
## plates come from a pool, and the names are sorted where they lie.

## A plate past its one step that still meets another: this much of itself.
const SHADED := 0.4
## Between the head and the plate's foot, and between two stacked plates.
const LIFT := 10.0
const GAP := 6.0

## Returns this frame's names (Client3D.name_plates).
var source: Callable
## Each text's measured width at the size it was measured, kept till it changes.
var _widths: Dictionary[String, float] = {}
var _measured_at := -1
var _skull: Texture2D
var _shaded: StyleBoxFlat
var _shaded_from: StyleBox
var _placed: Array[Dictionary] = []
var _pool: Array[Dictionary] = []
var _nearer := func(a: Dictionary, b: Dictionary) -> bool: return float(a["depth"]) < float(b["depth"])


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
	for one: Dictionary in place(source.call(), font, size, plate):
		var rect: Rect2 = one["rect"]
		var alpha: float = one["alpha"]
		var entry: Dictionary = one["entry"]
		if alpha >= 1.0:
			draw_style_box(plate, rect)
		else:
			draw_style_box(_shaded_box(plate), rect)
		var ink: Color = colour if bool(entry.get("plain", true)) else (entry["tint"] as Color)
		ink.a *= alpha
		var x := rect.position.x + plate.get_margin(SIDE_LEFT)
		if bool(entry.get("boss", false)):
			var px := float(size)
			draw_texture_rect(_skull_texture(), Rect2(x, rect.position.y + (rect.size.y - px) / 2.0, px, px), false, ink)
			x += px + plate.get_margin(SIDE_LEFT) * 0.5
		var base := rect.position.y + plate.get_margin(SIDE_TOP) + font.get_ascent(size)
		draw_string(font, Vector2(x, base), str(entry["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)


## [param entries] laid out: each its plate's rect and alpha, nearer first, the
## rest stepped up one plate or faded where they would meet a placed one.
## Sorts [param entries] in place; the result is this part's own array, reused.
func place(entries: Array, font: Font, size: int, plate: StyleBox) -> Array[Dictionary]:
	if _measured_at != size:
		_widths.clear()
		_measured_at = size
	entries.sort_custom(_nearer)
	_placed.clear()
	var height := font.get_height(size) + plate.get_margin(SIDE_TOP) + plate.get_margin(SIDE_BOTTOM)
	for entry: Dictionary in entries:
		var text := str(entry["text"])
		if not _widths.has(text):
			_widths[text] = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var width: float = _widths[text] + plate.get_margin(SIDE_LEFT) + plate.get_margin(SIDE_RIGHT)
		if bool(entry.get("boss", false)):
			width += size + plate.get_margin(SIDE_LEFT) * 0.5
		var at: Vector2 = entry["at"]
		var rect := Rect2(at.x - width / 2.0, at.y - LIFT - height, width, height)
		var alpha := 1.0
		var hit: Variant = _meets(rect)
		if hit != null:
			rect.position.y = (hit as Rect2).position.y - height - GAP
			if _meets(rect) != null:
				alpha = SHADED
		if _pool.size() <= _placed.size():
			_pool.append({})
		var one: Dictionary = _pool[_placed.size()]
		one["rect"] = rect
		one["alpha"] = alpha
		one["entry"] = entry
		_placed.append(one)
	return _placed


## The first placed plate's rect that meets [param rect], or null.
func _meets(rect: Rect2) -> Variant:
	for one: Dictionary in _placed:
		var other: Rect2 = one["rect"]
		if other.intersects(rect):
			return other
	return null


## [param plate] at SHADED, made once a theme.
func _shaded_box(plate: StyleBox) -> StyleBox:
	if not plate is StyleBoxFlat:
		return plate
	if _shaded_from != plate:
		_shaded_from = plate
		_shaded = plate.duplicate() as StyleBoxFlat
		_shaded.bg_color.a *= SHADED
		_shaded.border_color.a *= SHADED
		_shaded.shadow_color.a *= SHADED
	return _shaded


func _skull_texture() -> Texture2D:
	if _skull == null:
		_skull = BossBar.skull_texture(64, Color.WHITE)
	return _skull
