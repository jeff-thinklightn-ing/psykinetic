class_name WorldMapPanel
extends Control
## The world map (ui's step 5; maps' world graph, decisions 194 to 206):
## every area as a box in the serif with its places listed, the ways
## between them as lines (an edge way joins two sides, a point link runs
## between marked cells), the player's own area edged in brass with their
## place marked, this zone's party members named on it, and a faction's
## holding as a coloured edge on a place with the faction's name (phase B,
## from maps' "world" message; phase A colours nothing). M after the zone's
## big map opens it (Main), Esc closes it; the wheel zooms, a drag pans.
## A hidden link (608) is drawn nowhere here (ways_drawn; 589 amended).
## Built on the client from WorldMap.build (the levels the client ships),
## the editor's box positions (levels/world_map.json "positions", read and
## never written) where an area has one, the rest laid out from the edge
## neighbours and the point links. The look is the shared theme's (UiTheme,
## docs/ui_style.md).

const BOX := Vector2(360.0, 0.0)
const BOX_MIN_HEIGHT := 120.0
const GAP := 90.0
const LINE_WIDTH := 4.0
const ZOOMS: Array[float] = [0.5, 0.75, 1.0, 1.5, 2.0]
const LAYOUT_PATH := "res://levels/world_map.json"
const FACTIONS_PATH := "res://levels/factions.json"

## The world's graph; null until the first open (built then).
var world: WorldMap
## Area name -> the box's top left in map units.
var positions: Dictionary[String, Vector2] = {}
## Area name -> its box's size.
var sizes: Dictionary[String, Vector2] = {}
## The player's area and cell (Main), "" for none.
var own_area := ""
var own_cell := Vector2i(-1, -1)
## This zone's party members: [{name, area, kind}] (Main; phase B adds the rest).
var party: Array[Dictionary] = []
## Place id ("<area>/<key>") -> [faction, strength] (maps' world_state
## "holdings", phase B; empty before it lands).
var holdings: Dictionary = {}
## Area names and place ids the player has seen (maps' "known_areas" and
## "known_places"; empty means everything is drawn as known).
var known_areas: Dictionary = {}
var known_places: Dictionary = {}
## The trade routes through known areas (decision 504; Main's world_state
## "trade"): [{id, from_area, to_area, areas, caravans: [{area, fraction}]}].
var trade: Array = []
## ZOOMS' index: 1.5 at the start, so a box's words read at 1080p.
var zoom_step := 3
var pan := Vector2.ZERO
var _dragging := false
var _factions: Dictionary = {}
var _hover := ""
## The caravan dot under the cursor (decision 515): {route, caravan}, or {}.
var _hover_caravan: Dictionary = {}
## How near the cursor must come to a caravan's dot, in canvas units at zoom 1.
const CARAVAN_GRIP := 14.0
## What the player's companion knows the way to (companions' 551; Main's
## world_state "guide"): {companion, places: [place ids], areas: [names]};
## {} for none.
var guide: Dictionary = {}
## The local player led (Player.led_by, led_to): {"by": her name, "to": the
## place id or area name}; "" when not led.
var led: Dictionary = {"by": "", "to": ""}
## A town's read-out by area name (Main.town_notes: the dole line, 353),
## drawn dim under the area's places; the talk log no longer carries it.
var notes: Dictionary = {}
## The rows drawn this frame she knows the way to: place id or area name ->
## the rect of its words and mark (screen), for the hover and the click.
var _rows: Dictionary = {}
## The known row under the cursor ("" for none), and the one the ask box
## stands beside.
var _hover_row := ""
## Each area box's party line rect and the first bond reason on it (555,
## ui's side), and the area whose line is hovered: the reason in a box.
var _party_rows: Dictionary = {}
var _hover_party := ""
var _ask := ""
var _ask_box := Rect2()
## Where the left button went down; a release within CLICK_SLOP of it is a
## click on a row, further is the drag it always was.
var _press_at := Vector2(-1.0e9, -1.0e9)
const CLICK_SLOP := 4.0
## The mark after a row she knows the way to, in canvas units at zoom 1.
const GUIDE_MARK := 5.0
## A click on the ask box or Enter: ask her to lead the player to [param to]
## (Main sends the "guide" command, 551).
signal guide_asked(to: String)


func _init() -> void:
	name = "WorldMap"
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


## Opened: the graph built the first time, the view centred on the
## player's area.
func open() -> void:
	_ensure_world()
	visible = true
	centre_on(own_area)
	queue_redraw()


## The graph built once (the HUD's place words may ask before the first open).
func _ensure_world() -> void:
	if world == null:
		world = WorldMap.build()
		_read_layout()
		_lay_out()
		_read_factions()


## Closed; the ask box goes with it (551).
func close() -> void:
	visible = false
	_ask = ""
	_hover_row = ""
	_hover_party = ""
	_dragging = false


## Maps' world_state (phase B): {holdings: {place_id: [faction, strength]},
## known_areas: [...], known_places: [...], party: [{name, area, kind}]};
## the party given here is merged with this zone's (Main).
func set_world_state(state: Dictionary, here: Array[Dictionary]) -> void:
	holdings = state.get("holdings", {}) if state.get("holdings") is Dictionary else {}
	known_areas.clear()
	for area_name: Variant in state.get("known_areas", []):
		known_areas[str(area_name)] = true
	known_places.clear()
	for id: Variant in state.get("known_places", []):
		known_places[str(id)] = true
	trade = (state.get("trade", []) as Array).duplicate(true) if state.get("trade") is Array else []
	guide = (state.get("guide") as Dictionary).duplicate(true) if state.get("guide") is Dictionary else {}
	if not knows_way(_ask):
		_ask = ""
	party.clear()
	party.append_array(here)
	for member: Variant in state.get("party", []):
		if member is Dictionary:
			party.append(member)
	queue_redraw()


## Each trade route a dashed brass way through the boxes of the areas it
## crosses, beside their own ways (decision 504).
func _draw_trade(scale: float) -> void:
	for route: Dictionary in trade:
		var line := trade_line(route, scale)
		for i in range(1, line.size()):
			draw_dashed_line(line[i - 1], line[i], UiTheme.color("brass"), LINE_WIDTH * 0.75 * scale, 14.0 * scale, true)


## [param route]'s way on screen: its areas' box middles, set off a little
## so it runs beside the ways between them; the areas not laid out left out.
func trade_line(route: Dictionary, scale: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for area: Variant in route.get("areas", []):
		var area_name := str(area)
		if positions.has(area_name):
			out.append((positions[area_name] + sizes[area_name] * 0.5 + Vector2(0.0, 18.0)) * scale + pan)
	return out


## The point [param fraction] of the way along [param line].
static func point_along(line: PackedVector2Array, fraction: float) -> Vector2:
	if line.size() == 1:
		return line[0]
	var total := 0.0
	for i in range(1, line.size()):
		total += line[i - 1].distance_to(line[i])
	var left := clampf(fraction, 0.0, 1.0) * total
	for i in range(1, line.size()):
		var part := line[i - 1].distance_to(line[i])
		if left <= part or i == line.size() - 1:
			return line[i - 1].lerp(line[i], clampf(left / maxf(part, 0.001), 0.0, 1.0))
		left -= part
	return line[-1]


## The view put so [param area]'s box is in the middle of the screen.
func centre_on(area: String) -> void:
	if not positions.has(area):
		return
	var box := Rect2(positions[area], sizes.get(area, BOX))
	pan = get_viewport_rect().size * 0.5 - box.get_center() * ZOOMS[zoom_step]
	queue_redraw()


func zoom(step: int) -> void:
	var middle := get_viewport_rect().size * 0.5
	var before := (middle - pan) / ZOOMS[zoom_step]
	zoom_step = clampi(zoom_step + step, 0, ZOOMS.size() - 1)
	pan = middle - before * ZOOMS[zoom_step]
	queue_redraw()


## The areas laid out, in map units: name -> Rect2 (tests).
func boxes() -> Dictionary:
	var out := {}
	for area in positions:
		out[area] = Rect2(positions[area], sizes.get(area, BOX))
	return out


## The ways the map draws: every way but a hidden link's (608: behind a
## door nobody has found; the map must not say where it leads; 589 amended).
func ways_drawn() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world == null:
		return out
	for way: Dictionary in world.ways:
		if not bool(way.get("hidden", false)):
			out.append(way)
	return out


## The editor's positions, where it has them (never written here).
func _read_layout() -> void:
	if not FileAccess.file_exists(LAYOUT_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	if not parsed is Dictionary or not parsed.get("positions") is Dictionary:
		return
	for area_name: String in parsed["positions"]:
		var at: Variant = parsed["positions"][area_name]
		if at is Array and at.size() == 2 and world.areas.has(area_name):
			positions[area_name] = Vector2(float(at[0]), float(at[1]))


## Every area without a position laid out from the start zone outward: an
## edge neighbour on its side, a point link's far end in the next free
## slot to the right, the rest in rows below.
func _lay_out() -> void:
	for area_name: String in world.areas:
		var places: Dictionary = world.areas[area_name].get("places", {})
		sizes[area_name] = Vector2(BOX.x, maxf(BOX_MIN_HEIGHT, 90.0 + 36.0 * places.size()))
	var order: Array[String] = []
	var start := WorldMap.start_zone()
	if world.areas.has(start):
		order.append(start)
	for area_name: String in world.areas:
		if area_name not in order:
			order.append(area_name)
	var queue: Array[String] = order.duplicate()
	if not positions.has(start) and world.areas.has(start):
		positions[start] = Vector2.ZERO
	var sides := {"north": Vector2(0, -1), "south": Vector2(0, 1), "west": Vector2(-1, 0), "east": Vector2(1, 0)}
	var changed := true
	while changed:
		changed = false
		for area_name: String in queue:
			if not positions.has(area_name):
				continue
			var neighbours: Dictionary = world.areas[area_name].get("neighbours", {})
			for side: String in neighbours:
				var other := str(neighbours[side])
				if positions.has(other) or not world.areas.has(other) or not sides.has(side):
					continue
				var step: Vector2 = sides[side]
				positions[other] = positions[area_name] + step * (Vector2(BOX.x, sizes[area_name].y) + Vector2(GAP, GAP))
				changed = true
			for link: Dictionary in world.areas[area_name].get("links", []):
				var other := str(link.get("to_map", ""))
				if positions.has(other) or not world.areas.has(other):
					continue
				positions[other] = _free_slot(positions[area_name] + Vector2(BOX.x + GAP, 0.0))
				changed = true
	var row := Vector2(0.0, 0.0)
	for area_name: String in order:
		if positions.has(area_name):
			row.y = maxf(row.y, positions[area_name].y + sizes[area_name].y + GAP)
	for area_name: String in order:
		if not positions.has(area_name):
			positions[area_name] = _free_slot(row)
			row.x += BOX.x + GAP


## [param wanted], or the first spot right of it no box covers.
func _free_slot(wanted: Vector2) -> Vector2:
	var at := wanted
	for i in 64:
		var free := true
		for area_name: String in positions:
			if Rect2(positions[area_name], sizes[area_name]).grow(GAP * 0.5).intersects(Rect2(at, BOX + Vector2(0, BOX_MIN_HEIGHT))):
				free = false
		if free:
			return at
		at.x += BOX.x + GAP
	return at


func _read_factions() -> void:
	if not FileAccess.file_exists(FACTIONS_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FACTIONS_PATH))
	if parsed is Dictionary:
		_factions = parsed


## A faction's shown name and colour (levels/factions.json; lore's names).
func faction_look(id: String) -> Dictionary:
	var row: Dictionary = _factions.get(id, {}) if _factions.get(id) is Dictionary else {}
	return {"name": str(row.get("name", id)), "colour": Color.html(str(row.get("colour", "#b8322a")))}


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and click.pressed:
		zoom(1 if click.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
		accept_event()
	elif click != null and click.button_index == MOUSE_BUTTON_LEFT:
		if click.pressed:
			_press_at = click.position
			_dragging = true
		else:
			_dragging = false
			if _press_at.distance_to(click.position) <= CLICK_SLOP:
				_clicked(click.position)  # Still: a click (551); moved: the drag.
		accept_event()
	var motion := event as InputEventMouseMotion
	if motion != null:
		if _dragging:
			pan += motion.relative
			queue_redraw()
		var over := _area_at(motion.position)
		if over != _hover:
			_hover = over
			queue_redraw()
		var row := row_at(motion.position)
		if row != _hover_row:
			_hover_row = row
			queue_redraw()
		var line := party_at(motion.position)
		if line != _hover_party:
			_hover_party = line
			queue_redraw()
		var dot := caravan_at(motion.position)
		if dot != _hover_caravan:
			_hover_caravan = dot
			queue_redraw()


## Enter while the ask box stands: the ask goes (551).
func _input(event: InputEvent) -> void:
	if not visible or _ask.is_empty():
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		confirm_ask()
		get_viewport().set_input_as_handled()


## Whether the companion knows the way to [param id], a place id or an area
## name (world_state "guide", companions' 551).
func knows_way(id: String) -> bool:
	if id.is_empty() or guide.is_empty():
		return false
	return (guide.get("places", []) as Array).has(id) or (guide.get("areas", []) as Array).has(id)


## The row she knows the way to whose words or mark are under [param at]
## (screen); "" for none.
func row_at(at: Vector2) -> String:
	for id: String in _rows:
		if (_rows[id] as Rect2).has_point(at):
			return id
	return ""


## The area whose party line is under [param at], "" for none (555, ui's side).
func party_at(at: Vector2) -> String:
	for area_name: String in _party_rows:
		if (_party_rows[area_name]["rect"] as Rect2).has_point(at):
			return area_name
	return ""


## A party member's words on the area box (555, ui's side): "Wren, sullen"
## with her bond's step when it is not the plain one (Main.bond_shown), a
## player's name alone.
static func party_words(member: Dictionary) -> String:
	var mood := str(member.get("mood", ""))
	return "%s, %s" % [member.get("name", ""), mood] if not mood.is_empty() else str(member.get("name", ""))


## A click, not a drag, at [param at]: on the ask box, the ask goes; on a
## row she knows the way to (its words or its mark), the box opens beside
## it; anywhere else closes the box.
func _clicked(at: Vector2) -> void:
	if not _ask.is_empty() and _ask_box.has_point(at):
		confirm_ask()
		return
	var row := row_at(at)
	_ask = row if knows_way(row) else ""
	queue_redraw()


## The ask box's yes: guide_asked with the place, the box gone (Main sends
## the command and closes the map).
func confirm_ask() -> void:
	if _ask.is_empty():
		return
	var to := _ask
	_ask = ""
	queue_redraw()
	guide_asked.emit(to)


## The ask box opened beside [param id] when she knows the way there
## (tests, --test-show=guide_map).
func show_ask(id: String) -> void:
	_ask = id if knows_way(id) else ""
	queue_redraw()


## The place or area the ask box stands beside, "" for none.
func ask_pending() -> String:
	return _ask


## Hovering a marked row: "Wren knows the way".
static func knows_words(name: String) -> String:
	return "%s knows the way" % name


## The ask box's words.
static func ask_words(name: String) -> String:
	return "ask %s to lead you there   (Enter: yes, Esc: no)" % name


## A row's words while she leads the player there.
static func leads_words(name: String) -> String:
	return "> %s leads you here" % name


## The shown name of [param id]: a place's name for "<area>/<key>", an
## area's display name for an area, the id itself for anything else, "" for
## "". Builds the graph if need be.
func place_words(id: String) -> String:
	if id.is_empty():
		return ""
	_ensure_world()
	var area_name := id.get_slice("/", 0)
	var area: Variant = world.areas.get(area_name)
	if not area is Dictionary:
		return id
	if not id.contains("/"):
		return str(area.get("display_name", id))
	var key := id.get_slice("/", 1)
	var places: Variant = (area as Dictionary).get("places", {})
	var place: Variant = places.get(key) if places is Dictionary else null
	return str(place.get("name", key)) if place is Dictionary else key


## The mark after a row she knows the way to (551): a small friend-coloured
## dot past the words' end; the row's rect, words and mark, kept for the
## hover and the click.
func _mark_row(id: String, at: Vector2, words_width: float, height: float, scale: float) -> void:
	var middle := Vector2(at.x + words_width + 12.0 * scale, at.y - height * 0.32)
	draw_circle(middle, GUIDE_MARK * scale, UiTheme.color("friend"))
	_rows[id] = Rect2(at.x, at.y - height, words_width + 20.0 * scale, height * 1.3)


## A box of words beside [param anchor] (the row's right end), the caravan
## box's shape (515); its rect, for the click.
func _words_box(anchor: Vector2, words: String, scale: float, caption: float, sans: Font) -> Rect2:
	var text_size := sans.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, int(caption * scale))
	var pad := 10.0 * scale
	var box := Rect2(anchor + Vector2(10.0 * scale, -text_size.y - pad * 1.5), text_size + Vector2(pad * 2.0, pad * 2.0))
	if box.end.x > size.x:
		box.position.x = maxf(0.0, anchor.x - box.size.x - 10.0 * scale)
	if box.position.y < 0.0:
		box.position.y = anchor.y + 6.0 * scale
	draw_rect(box, UiTheme.color("backing_deep"))
	draw_rect(box, UiTheme.color("brass"), false, 1.0 * scale)
	draw_string(sans, box.position + Vector2(pad, pad + text_size.y * 0.78), words, HORIZONTAL_ALIGNMENT_LEFT, -1, int(caption * scale), UiTheme.color("text"))
	return box


## The caravan whose dot is within CARAVAN_GRIP of [param at] (screen), as
## {route, caravan}; {} for none (decision 515).
func caravan_at(at: Vector2) -> Dictionary:
	var scale := ZOOMS[zoom_step]
	var best: Dictionary = {}
	var best_away := CARAVAN_GRIP * scale
	for route: Dictionary in trade:
		var line := trade_line(route, scale)
		if line.is_empty():
			continue
		for caravan: Variant in route.get("caravans", []):
			if caravan is Dictionary:
				var away := point_along(line, float(caravan.get("fraction", 0.0))).distance_to(at)
				if away <= best_away:
					best_away = away
					best = {"route": route, "caravan": caravan}
	return best


## What hovering a caravan's dot says (decision 515), from what the wire
## has: "the wagon from The Wilds, bound for The Castle, in The Forest",
## and ", N days out" when maps sends "days" with the caravan.
func caravan_words(route: Dictionary, caravan: Dictionary) -> String:
	var words := "the wagon from %s, bound for %s" % [_area_words(str(route.get("from_area", ""))), _area_words(str(route.get("to_area", "")))]
	var where := _area_words(str(caravan.get("area", "")))
	if not where.is_empty():
		words += ", in %s" % where
	if caravan.has("days"):
		# Maps' days_left (504 amended): game days still to go, a float.
		var days := float(caravan["days"])
		if days < 0.75:
			words += ", less than a day out"
		else:
			var whole := roundi(days)
			words += ", a day out" if whole == 1 else ", %d days out" % whole
	return words


## An area's display name, or its id when the map has none ("" for "").
func _area_words(area_name: String) -> String:
	if area_name.is_empty() or world == null:
		return area_name
	var area: Variant = world.areas.get(area_name)
	return str(area.get("display_name", area_name)) if area is Dictionary else area_name


## The area whose box is under [param at] (screen), "" for none.
func _area_at(at: Vector2) -> String:
	var scale := ZOOMS[zoom_step]
	for area_name: String in positions:
		if Rect2(positions[area_name] * scale + pan, sizes[area_name] * scale).has_point(at):
			return area_name
	return ""


func _draw() -> void:
	if world == null:
		return
	var scale := ZOOMS[zoom_step]
	draw_rect(Rect2(Vector2.ZERO, size), Color(UiTheme.color("outline"), 0.8))
	var serif := UiTheme.font("serif")
	var sans := UiTheme.font("sans")
	var heading := UiTheme.size("heading")
	var caption := UiTheme.size("caption")
	# The ways first, under the boxes.
	for way: Dictionary in ways_drawn():
		var from := str(way.get("from", ""))
		var to := str(way.get("to", ""))
		if not positions.has(from) or not positions.has(to):
			continue
		var a := (positions[from] + sizes[from] * 0.5) * scale + pan
		var b := (positions[to] + sizes[to] * 0.5) * scale + pan
		var edge := str(way.get("kind", "")) == "edge"
		draw_line(a, b, Color(UiTheme.color("edge"), 0.9 if edge else 0.6), LINE_WIDTH * scale, true)
		if not edge:
			draw_circle(b, 6.0 * scale, UiTheme.color("brass"))
	_draw_trade(scale)
	_rows.clear()
	_party_rows.clear()
	for area_name: String in positions:
		var rect := Rect2(positions[area_name] * scale + pan, sizes[area_name] * scale)
		var area: Dictionary = world.areas[area_name]
		var is_known := known_areas.is_empty() or known_areas.has(area_name)
		draw_rect(rect, UiTheme.color("backing"))
		var edge_colour := UiTheme.color("brass_bright") if area_name == own_area else UiTheme.color("edge")
		draw_rect(rect, edge_colour, false, (3.0 if area_name == own_area else 2.0) * scale)
		if not is_known:
			continue
		var at := rect.position + Vector2(18.0, 18.0 + heading * 0.8) * scale
		var area_words := str(area.get("display_name", area_name))
		draw_string(serif, at, area_words, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0 * scale,
			int(heading * scale), UiTheme.color("text"))
		if knows_way(area_name):  # She knows the way to the area itself (551).
			_mark_row(area_name, at, serif.get_string_size(area_words, HORIZONTAL_ALIGNMENT_LEFT, -1, int(heading * scale)).x, heading * scale, scale)
		at.y += caption * 1.3 * scale
		var places: Dictionary = area.get("places", {})
		for key: String in places:
			var place: Dictionary = places[key]
			var id := "%s/%s" % [area_name, key]
			if not known_places.is_empty() and not known_places.has(id):
				continue
			var held: Variant = holdings.get(id)
			var colour := UiTheme.color("text_dim")
			var words := str(place.get("name", key))
			if held is Array and (held as Array).size() >= 1:
				var look := faction_look(str(held[0]))
				colour = look["colour"]
				words += ", %s" % look["name"]
			if area_name == own_area and own_cell != Vector2i(-1, -1):
				var cell: Vector2i = place.get("cell", Vector2i(-1000, -1000))
				var radius := maxi(int(place.get("radius", 1)), 1)
				if Vector2(own_cell - cell).length_squared() <= radius * radius:
					words = "> " + words
					colour = UiTheme.color("brass_bright")
			if id == str(led.get("to", "")) and not str(led.get("by", "")).is_empty():
				words = leads_words(str(led["by"]))  # She leads the player here (551).
				colour = UiTheme.color("friend")
			draw_string(sans, at, words, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0 * scale, int(caption * scale), colour)
			if knows_way(id):
				_mark_row(id, at, sans.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, int(caption * scale)).x, caption * scale, scale)
			at.y += caption * 1.2 * scale
		var note := str(notes.get(area_name, ""))
		if not note.is_empty():
			var note_size := int(caption * 0.85 * scale)
			var note_width := rect.size.x - 36.0 * scale
			draw_multiline_string(sans, at, note, HORIZONTAL_ALIGNMENT_LEFT, note_width, note_size, -1, UiTheme.color("text_dim"))
			at.y += sans.get_multiline_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, note_width, note_size).y + caption * 0.3 * scale
		var here: Array[String] = []
		var why := ""  # The first bond reason on the line, for the hover (555, ui's side).
		for member: Dictionary in party:
			if str(member.get("area", "")) == area_name:
				here.append(party_words(member))
				if why.is_empty():
					why = str(member.get("why", ""))
		if not here.is_empty():
			var line_words := ", ".join(here)
			var at_party := Vector2(rect.position.x + 18.0 * scale, rect.end.y - 12.0 * scale)
			draw_string(serif, at_party, line_words, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0 * scale, int(caption * scale), UiTheme.color("friend"))
			var line_width := minf(serif.get_string_size(line_words, HORIZONTAL_ALIGNMENT_LEFT, -1, int(caption * scale)).x, rect.size.x - 36.0 * scale)
			_party_rows[area_name] = {"rect": Rect2(at_party.x, at_party.y - caption * scale, line_width, caption * 1.3 * scale), "why": why}
	# The caravans over the boxes.
	for route: Dictionary in trade:
		var line := trade_line(route, scale)
		for caravan: Variant in route.get("caravans", []):
			if caravan is Dictionary and line.size() >= 1:
				var hovered: bool = not _hover_caravan.is_empty() and _hover_caravan["route"] == route and _hover_caravan["caravan"] == caravan
				draw_circle(point_along(line, float(caravan.get("fraction", 0.0))), (9.0 if hovered else 7.0) * scale, UiTheme.color("brass_bright"))
	# The hovered caravan's words, in a box beside its dot (decision 515).
	if not _hover_caravan.is_empty():
		var route: Dictionary = _hover_caravan["route"]
		var caravan: Dictionary = _hover_caravan["caravan"]
		var line := trade_line(route, scale)
		if not line.is_empty():
			var dot := point_along(line, float(caravan.get("fraction", 0.0)))
			var words := caravan_words(route, caravan)
			var text_size := sans.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, int(caption * scale))
			var pad := 10.0 * scale
			var box := Rect2(dot + Vector2(14.0, -14.0) * scale - Vector2(0.0, text_size.y + pad * 2.0), text_size + Vector2(pad * 2.0, pad * 2.0))
			if box.end.x > size.x:
				box.position.x = dot.x - 14.0 * scale - box.size.x
			if box.position.y < 0.0:
				box.position.y = dot.y + 14.0 * scale
			draw_rect(box, UiTheme.color("backing_deep"))
			draw_rect(box, UiTheme.color("brass"), false, 1.0 * scale)
			draw_string(sans, box.position + Vector2(pad, pad + text_size.y * 0.78), words, HORIZONTAL_ALIGNMENT_LEFT, -1, int(caption * scale), UiTheme.color("text"))
	# The guide (551): the ask box beside the row clicked, else the hovered
	# mark's words.
	var companion := str(guide.get("companion", ""))
	_ask_box = Rect2()
	if not _ask.is_empty() and _rows.has(_ask):
		var row: Rect2 = _rows[_ask]
		_ask_box = _words_box(Vector2(row.end.x, row.position.y + row.size.y * 0.5), ask_words(companion), scale, caption, sans)
	elif not _hover_row.is_empty() and _rows.has(_hover_row):
		var row: Rect2 = _rows[_hover_row]
		_words_box(Vector2(row.end.x, row.position.y + row.size.y * 0.5), knows_words(companion), scale, caption, sans)
	elif not _hover_party.is_empty() and _party_rows.has(_hover_party) and not str(_party_rows[_hover_party]["why"]).is_empty():
		# Her bond's reason, beside the party line (555, ui's side).
		var line: Rect2 = _party_rows[_hover_party]["rect"]
		_words_box(Vector2(line.end.x, line.position.y + line.size.y * 0.5), str(_party_rows[_hover_party]["why"]), scale, caption, sans)
	# The title and how to leave.
	draw_string(serif, Vector2(UiTheme.constant("margin"), UiTheme.constant("margin") + heading), "The known world",
		HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.size("title"), UiTheme.color("text"))
	var how := "wheel: zoom   drag: pan   Esc or M: close"
	if not guide.is_empty():
		how += "   a marked place: ask %s to lead you there" % companion
	draw_string(sans, Vector2(UiTheme.constant("margin"), UiTheme.constant("margin") + heading + caption * 1.6),
		how, HORIZONTAL_ALIGNMENT_LEFT, -1, caption, UiTheme.color("text_dim"))
