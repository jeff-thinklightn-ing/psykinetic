class_name UiNamePlates
extends Control
## Names over heads, drawn on the HUD (decision 865; the coordinator's approval of
## the mock, 11-11, C:/dev/review/ui-design/names/): each visible name as bone
## text (NameText) on a soft dark pill (NamePlate), at one screen size at every
## zoom and depth, its foot just over the head. Nearer names are placed first; a
## plate that would meet a placed one climbs above it and past each next, so none
## overlap; past the screen's top the farther drops (the plate pass). A boss's name carries its skull, left of the words.
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

## A faded plate's backing: this much of itself; its name is drawn at SHADED * (2 - SHADED), 0.84 (the coordinator,
## 11-14: at 0.4 "Snagfin" and "Maud" were barely legible on cobbles).
const SHADED := 0.6
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
		ink.a *= alpha * (2.0 - alpha)  # A faded name stays readable over its fainter backing.
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
	# The local player's body box (an entry with "own_body") is placed first: a deeper row that would sit on his
	# body goes above it, faded to SHADED (the plate-back mock, 11-14).
	var own_depth := INF
	for i in entries.size():
		if (entries[i] as Dictionary).has("own_body"):
			var own: Dictionary = entries[i]
			own_depth = float(own["depth"])
			entries.remove_at(i)
			entries.insert(0, own)
			break
	# A focused body's row (talked to, targeted or hovered) is placed next, on its stand: never faded, never dropped;
	# the rest climb round it.
	var front := 1 if own_depth < INF else 0
	for i in range(front, entries.size()):
		if bool((entries[i] as Dictionary).get("focus", false)):
			var lead: Dictionary = entries[i]
			entries.remove_at(i)
			entries.insert(front, lead)
			front += 1
	_placed.clear()
	_own_rect = Rect2()
	_own_core = Rect2()
	_own_torso = Rect2()
	for e: Dictionary in entries:
		if e.get("own_body") is Rect2:
			_own_rect = e["own_body"]
			_own_core = e.get("own_core", Rect2())
			_own_torso = e.get("own_torso", Rect2())
			break
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
		var own_box: Variant = entry.get("own_body", null)
		if not named and not barred and own_box == null:
			continue
		if not named and not barred:
			if _pool.size() <= _placed.size():
				_pool.append({})
			var box_only: Dictionary = _pool[_placed.size()]
			box_only["rect"] = Rect2()
			box_only["named"] = false
			box_only["bar"] = null
			box_only["row"] = own_box
			box_only["plate"] = Rect2()
			box_only["own"] = true
			box_only["alpha"] = 1.0
			box_only["entry"] = entry
			_placed.append(box_only)
			continue
		var behind := float(entry["depth"]) > own_depth
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
		# The climb (the coordinator's plate rules, 11-14): a row that meets a placed one goes above it, a GAP
		# between, and on up past each it meets next, so no two rows ever overlap; it stays over its own head's
		# line. One step over a plain row is plain; past more than one, or off the player's body, it fades to
		# SHADED, unless its body is focused (talked to, targeted or hovered: never faded). A row whose climb
		# would leave the screen's top is the farther one (nearer rows are placed first) and drops: not drawn.
		# A stepped row stays up while it is within hold of a placed one; a row on its stand steps on touching.
		var focus := bool(entry.get("focus", false))
		# Hidden (the coordinator, 11-14): a body behind mine whose head's own screen point falls inside my body's
		# drawn width (own_core: his head and neck, HIDE_HEAD either side; own_torso: shoulders down, HIDE_HALF) has no row, unless focused.
		if behind and not focus and ((_own_core.has_area() and _own_core.has_point(at)) or (_own_torso.has_area() and _own_torso.has_point(at))):
			continue
		var was_up := bool(step.get("up", false))
		var hit: Variant = _meets(row.grow(hold) if was_up else row, behind)
		var on_own := hit != null and _met_own
		var up := hit != null
		var gone := false
		var sided := false
		if up and on_own:
			# Sideways first (the coordinator, 11-14): a row that meets my body steps off it toward its own
			# body's side, a GAP clear, and climbs only if it finds no room there.
			var side := row
			if at.x < _own_rect.get_center().x:
				side.position.x = _own_rect.position.x - GAP - row_wide
			else:
				side.position.x = _own_rect.end.x + GAP
			if _meets(side, behind) == null and (not held or inside.encloses(side)):
				target = side
				sided = true
				if not focus:
					alpha = SHADED
		if up and not sided:
			var lifted := row
			var climbs := 0
			while hit != null and climbs < 12:
				climbs += 1
				lifted.position.y = (hit as Rect2).position.y - row_high - GAP
				hit = _meets(lifted, behind)
				on_own = on_own or (hit != null and _met_own)
			if hit != null or (held and lifted.position.y < inside.position.y):
				gone = true
			else:
				target = lifted
				if (climbs > 1 or on_own) and not focus:
					alpha = SHADED
		if gone:
			alpha = 0.0
		var off := target.position.y - row.position.y
		var off_x := target.position.x - row.position.x
		if remember and key != null:
			var ease := pow(0.05, minf(seconds, 1.0) / STEP_EASE)
			var drawn := float(step.get("off", off))
			drawn = off + (drawn - off) * ease
			var drawn_x := float(step.get("off_x", off_x))
			drawn_x = off_x + (drawn_x - off_x) * ease
			var shade := float(step.get("alpha", alpha))
			shade = alpha + (shade - alpha) * ease
			_steps[key] = {"up": up, "off": drawn, "off_x": drawn_x, "alpha": shade, "seen": now}
			off = drawn
			off_x = drawn_x
			alpha = shade
		var shown := row
		shown.position.y += off
		shown.position.x += off_x
		if _pool.size() <= _placed.size():
			_pool.append({})
		var one: Dictionary = _pool[_placed.size()]
		one["rect"] = Rect2(shown.position.x + (row_wide - width) / 2.0, shown.position.y, width, name_high)
		one["named"] = named
		one["bar"] = Rect2(shown.position.x + (row_wide - bar_wide) / 2.0, shown.position.y + row_high - bar_high, bar_wide, bar_high) if barred else null
		one["row"] = target.merge(own_box) if own_box != null else target
		# His plate and bar alone, kept apart from his body: what a row at his depth or nearer meets.
		one["plate"] = target
		one["own"] = own_box != null
		one["gone"] = gone
		one["alpha"] = alpha
		one["entry"] = entry
		_placed.append(one)
	if remember:
		for key: Variant in _steps.keys():
			if now - int((_steps[key] as Dictionary)["seen"]) > int(FORGET * 1000.0):
				_steps.erase(key)
	return _placed


## The row drawn for [param key] (Client3D.name_plates' key: its puppet's id) at the
## last draw, in this part's coordinates (the HUD's): its plate merged with its bar, the bar
## alone for a bar-only row, empty if it had none or dropped at the top (gone). Read only (885 amended (1): the builder
## panel's home keeps off the player's and his companion's).
func placed_rect(key: int) -> Rect2:
	for one: Dictionary in _placed:
		if int((one["entry"] as Dictionary).get("key", 0)) == key:
			if bool(one.get("gone", false)):
				return Rect2()
			var drawn := Rect2()
			if bool(one["named"]):
				drawn = one["rect"]
			if one["bar"] != null:
				drawn = (one["bar"] as Rect2) if not drawn.has_area() else drawn.merge(one["bar"] as Rect2)
			return drawn
	return Rect2()


## The first placed row's rect that meets [param rect], or null. The local player's row is his plate and his
## body box for a row [param behind] him, and his plate alone (its "plate") for a row at his depth or nearer, so a
## body beside him steps off his plate and none sits on it (the coordinator, 11-15: Rhea's row over mine). [member
## _met_own] says whether it was his body's box (behind him); meeting his plate alone is a plain meeting.
var _met_own := false
## The local player's body box this frame (its entry's "own_body"), empty when none.
var _own_rect := Rect2()
## The local player's head and neck as drawn ("own_core": his head to feet, HIDE_HEAD either side): a head inside it is hidden.
var _own_core := Rect2()
## His torso as drawn ("own_torso": his shoulders to feet, HIDE_HALF either side): a head inside it is hidden.
var _own_torso := Rect2()


func _meets(rect: Rect2, behind := false) -> Variant:
	_met_own = false
	for one: Dictionary in _placed:
		if bool(one.get("gone", false)):
			continue
		var mine := bool(one.get("own", false))
		var other: Rect2 = one["row"] if behind or not mine else one.get("plate", Rect2())
		if other.has_area() and other.intersects(rect):
			_met_own = mine and behind
			return other
	return null


## The top (screen y) of the row drawn over [param key]'s body this frame, or INF when it has none: a toast over that
## body (ui's Gains) rises above it, never lying on a plate (the coordinator's plate rule 4, ui-design's call: the toast
## moves, the plate stays).
func top_over(key: Variant) -> float:
	for one: Dictionary in _placed:
		if (one["entry"] as Dictionary).get("key") != key or bool(one.get("gone", false)):
			continue
		var top := INF
		if bool(one.get("named", false)):
			top = (one["rect"] as Rect2).position.y
		if one.get("bar") != null:
			top = minf(top, (one["bar"] as Rect2).position.y)
		return top
	return INF


func _skull_texture() -> Texture2D:
	if _skull == null:
		_skull = BossBar.skull_texture(64, Color.WHITE)
	return _skull
