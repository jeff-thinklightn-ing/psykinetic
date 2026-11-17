class_name WorldMapPanel
extends Control
## The known world (decision 968, ui's side; ui-design's mock4, variant B; before it ui's step 5,
## decisions 194 to 206 and 445): a window, the theme's panel with the title, a close button and
## the hint line, and the map in it. Each known outdoor area is a box at its place on the world
## plane (WorldMapModel, from WorldMap.plane_layout, decision 755), north up. The player's own
## area is the minimap's picture (Main gives it: picture, picture_cells) with its known places
## ringed and labelled at their cells, the labels folded into one where they would overlap (into
## the town's own name, where_name, opening out as the wheel zooms); every other known area is a
## box with its name and a row for each known place, a ring in a fixed slot left of the name (the
## slot a reached dot will take later, not built: the wire carries counts, not ids). Where a way
## goes down or out of an area a ring stands at its mouth and a chip names the level once it is
## known, else a "?" on a short stub; a "?" stub leaves a side whose neighbour is unknown, a short
## brass bar marks a shared edge; a hidden or closed way is drawn nowhere (608). The opening zoom
## fits what is known; the wheel zooms and a drag pans. What 551 (the guide's marks and ask box),
## 555 (the party's lines), 504 and 515 (the trade routes and their caravans), 353 (a town's
## read-out) and the factions' holdings did stay, on a box and on the picture alike. M after the
## zone's big map opens it (Main), Esc closes it, and while it is open the HUD's place labels, name
## plates, compass and corner map are hidden (Main). The look is the shared theme's (UiTheme,
## docs/ui_style.md); built on the client from WorldMap.build (the levels the client ships).

const FACTIONS_PATH := "res://levels/factions.json"

## The world's graph; null until the first open (built then).
var world: WorldMap
## world.plane_layout(), read when the graph is built.
var layout: Dictionary = {}
## The player's area and cell (Main), "" for none.
var own_area := ""
var own_cell := Vector2i(-1, -1)
## The player's area as the minimap draws it (Main: minimap.texture, one pixel a cell; and its size in
## cells), none before the first rebuild.
var picture: Texture2D
var picture_cells := Vector2i.ZERO
## Where a folded label's town is named: the place's name at a cell of the player's area (Main:
## Level.where_name), the HUD's own place words; none given, the nearest place's name.
var where_name: Callable
## This zone's party members: [{name, area, kind}] (Main; phase B adds the rest).
var party: Array[Dictionary] = []
## Place id ("<area>/<key>") -> [faction, strength] (maps' world_state
## "holdings", phase B; empty before it lands).
var holdings: Dictionary = {}
## Area names and place ids the player has seen (maps' "known_areas" and
## "known_places"; empty means everything is drawn as known).
var known_areas: Dictionary = {}
var known_places: Dictionary = {}
## The places reached of each known area (maps' "explored", 804; Main's world_state): area -> [have, need].
## The count is no longer written on the map (the coordinator, 11-17); the reached ids are not sent.
var explored: Dictionary = {}
## The trade routes through known areas (decision 504; Main's world_state
## "trade"): [{id, from_area, to_area, areas, caravans: [{area, fraction}]}].
var trade: Array = []
## ZOOMS' index: 0 is the fit.
var zoom_step := 0
var _dragging := false
var _factions: Dictionary = {}
## The caravan dot under the cursor (decision 515): {route, caravan}, or {}.
var _hover_caravan: Dictionary = {}
## How near the cursor must come to a caravan's dot, in canvas units.
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
## The rows and labels drawn this frame: place id or area name -> the rect of its words (screen), for
## the hover and the click.
var _rows: Dictionary = {}
## The row she knows the way to under the cursor ("" for none), and the one the ask box stands beside.
var _hover_row := ""
## Each area box's party line rect and the first bond reason on it (555,
## ui's side), and the area whose line is hovered: the reason in a box.
var _party_rows: Dictionary = {}
var _hover_party := ""
var _ask := ""
var _ask_box := Rect2()
## The picture's label groups drawn this frame: [{ids, rect, folded}].
var _groups: Array[Dictionary] = []
## Where the left button went down; a release within CLICK_SLOP of it is a
## click on a row, further is the drag it always was.
var _press_at := Vector2(-1.0e9, -1.0e9)
const CLICK_SLOP := 4.0
## The mark after a row she knows the way to, in canvas units.
const GUIDE_MARK := 5.0
## A click on the ask box or Enter: ask her to lead the player to [param to]
## (Main sends the "guide" command, 551).
signal guide_asked(to: String)
## A click on a town's row (624, ui's side): Main opens its sheet.
signal town_clicked(id: String)
## The towns the client has been told (Main.town_states' keys): their rows
## open the town sheet on a click.
var towns: Dictionary = {}
## What WorldMap.build() read when the graph was built (Client3D's key: the
## levels registered and the overlay's files): open() builds again on a
## different one. Only open() compares, so the HUD's place words, asked each
## frame while she leads, never read every level's files.
var _built_key := ""
## The fitted scale (pixels to a cell), the world cell at the middle of the map, and what the fit was
## made for.
var _fit := 1.0
var _view_centre := Vector2.ZERO
var _fitted := ""
## What WorldMapModel worked out (areas, mouths, chips, stubs, bars), read again when the world state,
## the player's area or the graph changes.
var _model: Dictionary = {}
var _model_dirty := true
## The window (the theme's panel, centred; KnownWorld's window_width and window_height), its hint
## line, the close mark and the map's drawing room (clipped; everything on it is in its own pixels).
var _window: PanelContainer
var _hint: Label
var _close_mark: UiClose
var _canvas: MapCanvas


## The map's drawing room: a child that clips what is drawn to the window's map area, hands its
## drawing and its mouse back to the panel, and so reads every point in its own pixels.
class MapCanvas extends Control:
	var panel: WorldMapPanel

	func _draw() -> void:
		panel._draw_content(self)

	func _gui_input(event: InputEvent) -> void:
		panel._map_input(event)

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
	explored = (state.get("explored") as Dictionary).duplicate(true) if state.get("explored") is Dictionary else {}
	trade = (state.get("trade", []) as Array).duplicate(true) if state.get("trade") is Array else []
	guide = (state.get("guide") as Dictionary).duplicate(true) if state.get("guide") is Dictionary else {}
	if not knows_way(_ask):
		_ask = ""
	party.clear()
	party.append_array(here)
	for member: Variant in state.get("party", []):
		if member is Dictionary:
			party.append(member)
	_model_dirty = true
	_refresh_hint()
	_redraw()


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


## The ask box's yes: guide_asked with the place, the box gone (Main sends
## the command and closes the map).
func confirm_ask() -> void:
	if _ask.is_empty():
		return
	var to := _ask
	_ask = ""
	_redraw()
	guide_asked.emit(to)


## The ask box opened beside [param id] when she knows the way there
## (tests, --test-show=guide_map).
func show_ask(id: String) -> void:
	_ask = id if knows_way(id) else ""
	_redraw()


## The place or area the ask box stands beside, "" for none.
func ask_pending() -> String:
	return _ask


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


## Whether a place's holding ([faction, strength]) names a holder to draw: none for an unclaimed
## place ("nobody"), which has no faction row to name or colour it.
static func holder_named(held: Variant) -> bool:
	return held is Array and (held as Array).size() >= 1 and str(held[0]) != Factions.NOBODY


## Levels made for testing, which the known world draws no box for (a dev level, 673; the default
## map, test_room, the editor's sample): the map's boxes are the game's places. Where the player stands
## in one it is drawn all the same.
const TEST_LEVELS: Array[String] = [Level.DEFAULT_MAP, "sample"]


## Whether [param area_name]'s box is drawn: every area but a test level, and that where the player is.
func area_shown(area_name: String) -> bool:
	return area_name == own_area or (area_name not in Level.DEV_LEVELS and area_name not in TEST_LEVELS)


func _init() -> void:
	name = "WorldMap"
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# The window: the theme's panel, centred; in it the header (the title and the close mark), the hint
	# line, and the map's drawing room that takes the rest.
	_window = PanelContainer.new()
	_window.set_anchors_preset(Control.PRESET_CENTER)
	_window.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_window.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_window)
	var column := VBoxContainer.new()
	column.theme_type_variation = &"Stack"
	_window.add_child(column)
	var head := HBoxContainer.new()
	head.theme_type_variation = &"Strip"
	column.add_child(head)
	var title := Label.new()
	title.text = "The known world"
	title.theme_type_variation = &"Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_close_mark = UiClose.new()
	_close_mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_close_mark.pressed.connect(close)
	head.add_child(_close_mark)
	_hint = Label.new()
	_hint.theme_type_variation = &"Caption"
	column.add_child(_hint)
	_canvas = MapCanvas.new()
	_canvas.panel = self
	_canvas.clip_contents = true
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.resized.connect(_redraw)
	column.add_child(_canvas)


## The KnownWorld theme part's measure and colour [param part] (ui-design's; canvas units of 3840x2160).
func _k(part: StringName) -> float:
	return float(get_theme_constant(part, &"KnownWorld"))


func _kc(part: StringName) -> Color:
	return get_theme_color(part, &"KnownWorld")


## Opened: the graph built the first time, and again when a level changed
## since it was built (197 amended (2): a builder's accept the server sent
## as a "terrain" message, a regenerated level), the window sized and the
## view fitted to what is known.
func open() -> void:
	if world != null and Client3D._world_map_key() != _built_key:
		world = null
	_ensure_world()
	visible = true
	_lay_window()
	_refresh_hint()
	_model_dirty = true
	_panned = false
	zoom_step = 0
	_fitted = ""
	_redraw()


## True once a drag has moved the view: the fit then no longer takes it back as areas are learned.
var _panned := false


## The graph built if there is none (the HUD's place words may ask before
## the first open).
func _ensure_world() -> void:
	if world == null:
		_built_key = Client3D._world_map_key()
		world = WorldMap.build()
		layout = world.plane_layout()
		_model_dirty = true
		_read_factions()


## Everything drawn again (the map is a child's drawing).
func _redraw() -> void:
	queue_redraw()
	if _canvas != null:
		_canvas.queue_redraw()


## Closed; the ask box goes with it (551).
func close() -> void:
	visible = false
	_ask = ""
	_hover_row = ""
	_hover_party = ""
	_dragging = false


## The window centred at the theme's size (KnownWorld window_width, window_height).
func _lay_window() -> void:
	var width := _k(&"window_width")
	var height := _k(&"window_height")
	_window.offset_left = -width * 0.5
	_window.offset_right = width * 0.5
	_window.offset_top = -height * 0.5
	_window.offset_bottom = height * 0.5


## The hint line under the title: how to move the map and leave it, and what a marked place is when she
## has a way to show (551).
func _refresh_hint() -> void:
	var how := "wheel: zoom   drag: pan   Esc or M: close"
	var companion := str(guide.get("companion", ""))
	if not companion.is_empty():
		how += "   a marked place: ask %s to lead you there" % companion
	_hint.text = how


## What WorldMapModel makes of the plane and what is known, read again when it changes.
func _rebuild_model() -> void:
	_model_dirty = false
	if world == null:
		_model = {"areas": [] as Array[String], "mouths": [] as Array[Dictionary], "chips": [] as Array[Dictionary],
			"stubs": [] as Array[Dictionary], "bars": [] as Array[Dictionary]}
		return
	var areas := WorldMapModel.shown(layout, known_areas, own_area, TEST_LEVELS)
	var mouths := WorldMapModel.mouths(layout, world.ways, known_areas, own_area, areas)
	_model = {"areas": areas, "mouths": mouths, "chips": WorldMapModel.chips(layout, mouths, known_areas),
		"stubs": WorldMapModel.stubs(layout, world.ways, mouths, known_areas, own_area, areas), "bars": WorldMapModel.bars(layout, areas)}


## What the fit is for: the areas shown, the stubs, and the room.
func _signature() -> String:
	return "%s|%d|%s" % [_model.get("areas", []), (_model.get("stubs", []) as Array).size(), _canvas.size]


## The view fitted to the known boxes with room for the "?" stubs (KnownWorld fit_margin): the opening
## zoom, the middle of what is known in the middle of the map.
func _refit() -> void:
	if _model_dirty:
		_rebuild_model()
	var boxes_in: Array[Rect2] = []
	for area_name: String in _model["areas"]:
		boxes_in.append(WorldMapModel.box_of(layout, area_name))
	var bounds := WorldMapModel.bounds(boxes_in)
	_fit = WorldMapModel.fit_scale(bounds, _canvas.size, _k(&"fit_margin"))
	_view_centre = bounds.get_center()
	zoom_step = 0
	_fitted = _signature()


## The zooms, each a share of the fitted scale: 1, then each step (KnownWorld zoom_step, per cent) on the
## last, the last at most zoom_most per cent: 1, 1.5, 2.25, 3.375, 4.
func _zooms() -> Array[float]:
	var out: Array[float] = [1.0]
	var step := maxf(_k(&"zoom_step") / 100.0, 1.05)
	var most := maxf(_k(&"zoom_most") / 100.0, 1.0)
	while out[-1] < most:
		out.append(minf(out[-1] * step, most))
	return out


## Pixels to a cell now.
func _scale() -> float:
	return _fit * _zooms()[mini(zoom_step, _zooms().size() - 1)]


## Where world cell [param cell] falls on the map (its own pixels).
func _to_screen(cell: Vector2) -> Vector2:
	return _canvas.size * 0.5 + (cell - _view_centre) * _scale()


## [param box] (world cells) on the map.
func _screen_rect(box: Rect2) -> Rect2:
	return Rect2(_to_screen(box.position), box.size * _scale())


## The view put so [param area]'s box is in the middle of the map.
func centre_on(area: String) -> void:
	if world == null or not (layout.get("zones", {}) as Dictionary).has(area):
		return
	_view_centre = WorldMapModel.box_of(layout, area).get_center()
	_redraw()


func zoom(step: int) -> void:
	zoom_step = clampi(zoom_step + step, 0, _zooms().size() - 1)
	_redraw()


## The areas laid out, in world cells: name -> Rect2 (tests).
func boxes() -> Dictionary:
	if world == null:
		return {}
	if _model_dirty:
		_rebuild_model()
	var out := {}
	for area_name: String in _model["areas"]:
		out[area_name] = WorldMapModel.box_of(layout, area_name)
	return out


## Where the player is on the map, in world cells: on their area's box at their cell, else at the
## mouth of the level below they stand in; Vector2.INF for none.
func you_at() -> Vector2:
	if own_area.is_empty() or own_cell == Vector2i(-1, -1) or world == null:
		return Vector2.INF
	if _model_dirty:
		_rebuild_model()
	if (layout.get("zones", {}) as Dictionary).has(own_area):
		return WorldMapModel.box_of(layout, own_area).position + Vector2(own_cell) + Vector2(0.5, 0.5)
	for chip: Dictionary in _model["chips"]:
		if chip["level"] == own_area:
			return chip["at"]
	for mouth: Dictionary in _model["mouths"]:
		if mouth["level"] == own_area:
			return mouth["at"]
	return Vector2.INF


## The ids of [param area_name]'s known places, in level order.
func known_place_ids(area_name: String) -> Array[String]:
	var out: Array[String] = []
	var area: Variant = world.areas.get(area_name) if world != null else null
	if not area is Dictionary:
		return out
	for key: String in (area as Dictionary).get("places", {}):
		var id := "%s/%s" % [area_name, key]
		if known_places.is_empty() or known_places.has(id):
			out.append(id)
	return out


## A place's words and colour on a row or a label: its name, its holder's name after it where it has
## one (the faction's colour), "> <she> leads you here" in the friend colour when she leads the player
## there (551).
func place_look(id: String, plain: Color) -> Dictionary:
	var area_name := id.get_slice("/", 0)
	var place: Dictionary = (world.areas[area_name].get("places", {}) as Dictionary).get(id.get_slice("/", 1), {})
	var words := str(place.get("name", id.get_slice("/", 1)))
	var colour := plain
	var held: Variant = holdings.get(id)
	if holder_named(held):
		var look := faction_look(str(held[0]))
		colour = look["colour"]
		words += ", %s" % look["name"]
	if id == str(led.get("to", "")) and not str(led.get("by", "")).is_empty():
		words = leads_words(str(led["by"]))
		colour = UiTheme.color("friend")
	return {"words": words, "colour": colour}


## A trade route's way on the map: its areas' box middles, set off a little so it runs beside a
## bar; the areas not shown left out.
func trade_line(route: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	if world == null:
		return out
	if _model_dirty:
		_rebuild_model()
	for area: Variant in route.get("areas", []):
		var area_name := str(area)
		if area_name in (_model["areas"] as Array[String]):
			out.append(_screen_rect(WorldMapModel.box_of(layout, area_name)).get_center() + Vector2(0.0, 18.0))
	return out


## The caravan whose dot is within CARAVAN_GRIP of [param at] (the map's pixels), as
## {route, caravan}; {} for none (decision 515).
func caravan_at(at: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_away := CARAVAN_GRIP
	for route: Dictionary in trade:
		var line := trade_line(route)
		if line.is_empty():
			continue
		for caravan: Variant in route.get("caravans", []):
			if caravan is Dictionary:
				var away := _caravan_point(line, caravan).distance_to(at)
				if away <= best_away:
					best_away = away
					best = {"route": route, "caravan": caravan}
	return best


## Where a caravan's dot is: along its route by its fraction; one that is in the player's area, whose
## picture the client has no cell for it on, at the picture's edge, not across it.
func _caravan_point(line: PackedVector2Array, caravan: Dictionary) -> Vector2:
	var point := point_along(line, float(caravan.get("fraction", 0.0)))
	if str(caravan.get("area", "")) == own_area and (layout.get("zones", {}) as Dictionary).has(own_area) and picture != null:
		var rect := _screen_rect(WorldMapModel.box_of(layout, own_area))
		if rect.has_point(point):
			var out := point - rect.get_center()
			var half := rect.size * 0.5
			var edge := minf(half.x / maxf(absf(out.x), 0.001), half.y / maxf(absf(out.y), 0.001))
			return rect.get_center() + out * edge
	return point


## The map's mouse (the canvas hands it over, in its own pixels): the wheel zooms, a drag pans, a still
## click is a click.
func _map_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and click.pressed:
		zoom(1 if click.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
		_canvas.accept_event()
	elif click != null and click.button_index == MOUSE_BUTTON_LEFT:
		if click.pressed:
			_press_at = click.position
			_dragging = true
		else:
			_dragging = false
			if _press_at.distance_to(click.position) <= CLICK_SLOP:
				_clicked(click.position)  # Still: a click (551); moved: the drag.
		_canvas.accept_event()
	var motion := event as InputEventMouseMotion
	if motion != null:
		if _dragging:
			_view_centre -= motion.relative / _scale()
			_panned = true
			_redraw()
		var row := row_at(motion.position)
		if row != _hover_row:
			_hover_row = row
			_redraw()
		var line := party_at(motion.position)
		if line != _hover_party:
			_hover_party = line
			_redraw()
		var dot := caravan_at(motion.position)
		if dot != _hover_caravan:
			_hover_caravan = dot
			_redraw()


## A click, not a drag, at [param at] (the map's pixels): on the ask box, the ask goes; on a folded
## label of a town, its sheet opens (624); on a row she knows the way to (its words or its mark), the
## box opens beside it; anywhere else closes the box.
func _clicked(at: Vector2) -> void:
	if not _ask.is_empty() and _ask_box.has_point(at):
		confirm_ask()
		return
	for group: Dictionary in _groups:
		if bool(group["folded"]) and (group["rect"] as Rect2).has_point(at):
			_ask = ""
			_redraw()
			for id: Variant in group["ids"]:
				if towns.has(str(id)):
					town_clicked.emit(str(id))
					return
			return
	var row := row_at(at)
	_ask = row if knows_way(row) else ""
	_redraw()
	if towns.has(row):
		town_clicked.emit(row)  # 624, ui's side: the town's sheet (the ask box stays under it).


## The mark after a row she knows the way to (551): a small friend-coloured
## dot past the words' end.
func _mark_row(c: Control, at: Vector2, words_width: float, height: float) -> void:
	c.draw_circle(Vector2(at.x + words_width + 12.0, at.y - height * 0.32), GUIDE_MARK, UiTheme.color("friend"))


## Words on a backing (KnownWorld label_back, the label's padding), the backing's top left at
## [param top_left]; the rect it takes.
func _backed_text(c: Control, words: String, top_left: Vector2, font: Font, font_size: int, colour: Color) -> Rect2:
	var pad := Vector2(_k(&"label_pad_x"), _k(&"label_pad_y"))
	var rect := Rect2(top_left, font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size) + pad * 2.0)
	c.draw_rect(rect, _kc(&"label_back"))
	c.draw_string(font, top_left + Vector2(pad.x, pad.y + font.get_ascent(font_size)), words, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)
	return rect


## A place's ring: KnownWorld ring, filled ring_fill, ringed in the dim text.
func _draw_ring(c: Control, at: Vector2) -> void:
	c.draw_circle(at, _k(&"ring"), _kc(&"ring_fill"))
	c.draw_arc(at, _k(&"ring"), 0.0, TAU, 24, UiTheme.color("text_dim"), _k(&"ring_line"), true)


## A "?" in its circle at [param at]: KnownWorld ask, filled backing_deep, ringed in the edge.
func _draw_ask(c: Control, at: Vector2) -> void:
	var sans := UiTheme.font("sans")
	var heading := UiTheme.size("heading")
	c.draw_circle(at, _k(&"ask"), UiTheme.color("backing_deep"))
	c.draw_arc(at, _k(&"ask"), 0.0, TAU, 28, UiTheme.color("edge"), _k(&"ask_line"), true)
	var mark_size := sans.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, heading)
	c.draw_string(sans, at + Vector2(-mark_size.x * 0.5, sans.get_ascent(heading) * 0.36), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, heading, UiTheme.color("text_dim"))


## A box of words beside [param anchor] (the row's right end), the caravan
## box's shape (515); its rect, for the click.
func _words_box(c: Control, anchor: Vector2, words: String) -> Rect2:
	var sans := UiTheme.font("sans")
	var caption := UiTheme.size("caption")
	var text_size := sans.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, caption)
	var pad := Vector2(_k(&"chip_pad_x"), _k(&"chip_pad_y"))
	var box := Rect2(anchor + Vector2(10.0, -text_size.y - pad.y * 3.0), text_size + pad * 2.0)
	if box.end.x > _canvas.size.x:
		box.position.x = maxf(0.0, anchor.x - box.size.x - 10.0)
	if box.position.y < 0.0:
		box.position.y = anchor.y + 6.0
	c.draw_rect(box, _kc(&"label_back"))
	c.draw_rect(box, UiTheme.color("brass"), false, _k(&"chip_line"))
	c.draw_string(sans, box.position + Vector2(pad.x, pad.y + sans.get_ascent(caption)), words, HORIZONTAL_ALIGNMENT_LEFT, -1, caption, UiTheme.color("text"))
	return box


## A dashed line from [param a] to [param b], left out where it runs inside one of [param covered].
func _dashes_outside(c: Control, a: Vector2, b: Vector2, covered: Array[Rect2], colour: Color) -> void:
	var length := a.distance_to(b)
	if length < 1.0:
		return
	var direction := (b - a) / length
	var dash := _k(&"stub_dash")
	var at := 0.0
	while at < length:
		var to := minf(at + dash, length)
		var middle := a + direction * (at + to) * 0.5
		if not covered.any(func(rect: Rect2) -> bool: return rect.has_point(middle)):
			c.draw_line(a + direction * at, a + direction * to, colour, _k(&"stub_width"), true)
		at += dash * 2.0


## The dim behind the window (KnownWorld dim).
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _kc(&"dim"))


## The map: boxes (the player's own the picture), gates, trade routes, stubs, rings and chips, the
## picture's labels, the rows' marks, the caravans, the guide's words, the "you" mark over all.
func _draw_content(c: Control) -> void:
	_rows.clear()
	_party_rows.clear()
	_groups.clear()
	if world == null or not visible:
		return
	if _model_dirty:
		_rebuild_model()
	if _fitted != _signature() and zoom_step == 0 and not _panned:
		_refit()
	var serif := UiTheme.font("serif")
	var sans := UiTheme.font("sans")
	var heading := UiTheme.size("heading")
	var caption := UiTheme.size("caption")
	var areas: Array[String] = _model["areas"]
	var rects := {}
	var covered: Array[Rect2] = []
	for area_name: String in areas:
		rects[area_name] = _screen_rect(WorldMapModel.box_of(layout, area_name))
		covered.append(rects[area_name])
	var pictured := picture != null and picture_cells.x > 0 and picture_cells.y > 0 and rects.has(own_area)
	var inset := _k(&"box_inset")
	# The boxes: backing, then the picture or the name and rows, then the edge.
	for area_name: String in areas:
		var rect: Rect2 = rects[area_name]
		var own := area_name == own_area
		var inner := rect.grow(-inset)
		c.draw_rect(inner, UiTheme.color("backing"))
		if own and pictured:
			c.draw_texture_rect(picture, inner, false, _kc(&"picture_tint"))
			_backed_text(c, str(world.areas[area_name].get("display_name", area_name)), inner.position + Vector2(_k(&"name_left"), _k(&"name_top")), serif, heading, UiTheme.color("text"))
		else:
			_draw_box_rows(c, area_name, inner, serif, sans, heading, caption)
		c.draw_rect(inner, UiTheme.color("brass_bright") if own else UiTheme.color("edge"), false, _k(&"own_edge") if own else _k(&"box_edge"))
	for bar: Dictionary in _model["bars"]:
		var at := _to_screen(bar["at"])
		var half := Vector2(0.0, _k(&"gate_length") * 0.5) if bool(bar["vertical"]) else Vector2(_k(&"gate_length") * 0.5, 0.0)
		c.draw_line(at - half, at + half, UiTheme.color("brass"), _k(&"gate_width"))
	# The trade routes: dim dashes between the boxes, none across a box.
	for route: Dictionary in trade:
		var line := trade_line(route)
		for i in range(1, line.size()):
			_dashes_outside(c, line[i - 1], line[i], covered, UiTheme.color("edge"))
	# The rings at the mouths of ways down or out (brass for a level known, the edge's for one not).
	var keep_off: Array[Rect2] = []
	for mouth: Dictionary in _model["mouths"]:
		var at := _to_screen(mouth["at"])
		c.draw_circle(at, _k(&"mouth"), UiTheme.color("backing_deep"))
		c.draw_arc(at, _k(&"mouth"), 0.0, TAU, 24, UiTheme.color("brass") if bool(mouth["known"]) else UiTheme.color("edge"), _k(&"mouth_line"), true)
	# The "?" stubs: out of a side whose neighbour is unknown, and below a mouth whose level is.
	for stub: Dictionary in _model["stubs"]:
		var from := _to_screen(stub["at"])
		if stub["kind"] == "edge":
			var to: Vector2 = from + (stub["dir"] as Vector2) * _k(&"stub_length")
			c.draw_dashed_line(from, to, UiTheme.color("edge"), _k(&"stub_width"), _k(&"stub_dash"), true)
			_draw_ask(c, to + (stub["dir"] as Vector2) * (_k(&"ask_gap") + _k(&"ask")))
		else:
			_draw_ask(c, from + Vector2(0.0, _k(&"mouth") + _k(&"ask_gap") + _k(&"ask")))
	# A chip for each level known below.
	var chip_pad := Vector2(_k(&"chip_pad_x"), _k(&"chip_pad_y"))
	for chip: Dictionary in _model["chips"]:
		var at := _to_screen(chip["at"])
		var words := _area_words(str(chip["level"]))
		var chip_size := sans.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, caption) + chip_pad * 2.0
		var rect := Rect2(at + Vector2(-chip_size.x * 0.5, _k(&"chip_drop") + float(chip["depth"]) * (chip_size.y + 4.0)), chip_size)
		c.draw_rect(rect, _kc(&"label_back"))
		c.draw_rect(rect, UiTheme.color("brass"), false, _k(&"chip_line"))
		c.draw_string(sans, rect.position + Vector2(chip_pad.x, chip_pad.y + sans.get_ascent(caption)), words, HORIZONTAL_ALIGNMENT_LEFT, -1, caption, UiTheme.color("text"))
		keep_off.append(rect)
	var you := you_at()
	var you_px := _to_screen(you) if you != Vector2.INF else Vector2.INF
	if you_px != Vector2.INF:
		keep_off.append(Rect2(you_px - Vector2.ONE * _k(&"you_clear"), Vector2.ONE * _k(&"you_clear") * 2.0))
	# The player's picture: a ring at each known place, its label, folded where they would overlap.
	if pictured:
		_draw_picture_places(c, (rects[own_area] as Rect2).grow(-inset), keep_off, sans, caption)
	_draw_feet(c, rects, serif, sans, caption)
	# The caravans over the boxes.
	for route: Dictionary in trade:
		var line := trade_line(route)
		for caravan: Variant in route.get("caravans", []):
			if caravan is Dictionary and line.size() >= 1:
				var hovered: bool = not _hover_caravan.is_empty() and _hover_caravan["route"] == route and _hover_caravan["caravan"] == caravan
				c.draw_circle(_caravan_point(line, caravan), 9.0 if hovered else 7.0, UiTheme.color("brass_bright"))
	# The hovered caravan's words, in a box beside its dot (decision 515).
	if not _hover_caravan.is_empty():
		var route: Dictionary = _hover_caravan["route"]
		var line := trade_line(route)
		if not line.is_empty():
			var dot := _caravan_point(line, _hover_caravan["caravan"])
			_words_box(c, dot + Vector2(4.0, 14.0), caravan_words(route, _hover_caravan["caravan"]))
	# The guide (551): the ask box beside the row clicked, else the hovered mark's words.
	var companion := str(guide.get("companion", ""))
	_ask_box = Rect2()
	if not _ask.is_empty() and _rows.has(_ask):
		var row: Rect2 = _rows[_ask]
		_ask_box = _words_box(c, Vector2(row.end.x, row.position.y + row.size.y * 0.5), ask_words(companion))
	elif not _hover_row.is_empty() and _rows.has(_hover_row) and knows_way(_hover_row):
		var row: Rect2 = _rows[_hover_row]
		_words_box(c, Vector2(row.end.x, row.position.y + row.size.y * 0.5), knows_words(companion))
	elif not _hover_party.is_empty() and _party_rows.has(_hover_party) and not str(_party_rows[_hover_party]["why"]).is_empty():
		# Her bond's reason, beside the party line (555, ui's side).
		var line: Rect2 = _party_rows[_hover_party]["rect"]
		_words_box(c, Vector2(line.end.x, line.position.y + line.size.y * 0.5), str(_party_rows[_hover_party]["why"]))
	# You: the halo, the ring and the dot, over everything.
	if you_px != Vector2.INF:
		c.draw_arc(you_px, _k(&"you_halo"), 0.0, TAU, 40, _kc(&"you_halo"), _k(&"you_line"), true)
		c.draw_circle(you_px, _k(&"you_ring"), UiTheme.color("backing_deep"))
		c.draw_arc(you_px, _k(&"you_ring"), 0.0, TAU, 32, UiTheme.color("brass_bright"), _k(&"you_line"), true)
		c.draw_circle(you_px, _k(&"you_dot"), UiTheme.color("brass_bright"))


## An area's box that is not the player's picture: its name, a row for each known place (a ring in the
## slot left of the words, the words after it), a town's read-out dim under them.
func _draw_box_rows(c: Control, area_name: String, rect: Rect2, serif: Font, sans: Font, heading: int, caption: int) -> void:
	var area: Dictionary = world.areas[area_name]
	var left := rect.position.x + _k(&"name_left")
	var at := Vector2(left, rect.position.y + _k(&"name_top") + serif.get_ascent(heading))
	var area_words := str(area.get("display_name", area_name))
	c.draw_string(serif, at, area_words, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - _k(&"name_left") * 2.0, heading, UiTheme.color("text"))
	var width := serif.get_string_size(area_words, HORIZONTAL_ALIGNMENT_LEFT, -1, heading).x
	_rows[area_name] = Rect2(at.x, at.y - heading, width + 20.0, heading * 1.3)
	if knows_way(area_name):  # She knows the way to the area itself (551).
		_mark_row(c, at, width, heading)
	var step := caption * 1.3
	at.y += heading * 0.5 + step
	for id: String in known_place_ids(area_name):
		if at.y > rect.end.y - step:
			break
		var look := place_look(id, UiTheme.color("text_dim"))
		var words := str(look["words"])
		var text_x := left + _k(&"slot") + _k(&"slot_gap")
		_draw_ring(c, Vector2(left + _k(&"slot") * 0.5, at.y - caption * 0.32))
		c.draw_string(sans, Vector2(text_x, at.y), words, HORIZONTAL_ALIGNMENT_LEFT, rect.end.x - text_x - _k(&"name_left"), caption, look["colour"])
		var words_width := sans.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, caption).x
		_rows[id] = Rect2(left, at.y - caption, text_x - left + words_width + 20.0, step)
		if knows_way(id):
			_mark_row(c, Vector2(text_x, at.y), words_width, caption)
		at.y += step
	var note := str(notes.get(area_name, ""))
	if not note.is_empty():
		c.draw_multiline_string(sans, at, note, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - _k(&"name_left") * 2.0, int(caption * 0.85), -1, UiTheme.color("text_dim"))


## The player's picture's places: a ring at each known place's cell and its label, labels folded
## where they would overlap or cover a chip or the "you" mark.
func _draw_picture_places(c: Control, rect: Rect2, keep_off: Array[Rect2], sans: Font, caption: int) -> void:
	var cell_px := rect.size / Vector2(picture_cells)
	var box := WorldMapModel.box_of(layout, own_area)
	var chip_mouths: Array[Vector2] = []
	for chip: Dictionary in _model["chips"]:
		chip_mouths.append(chip["at"])
	var pad := Vector2(_k(&"label_pad_x"), _k(&"label_pad_y"))
	var labels: Array[Dictionary] = []
	var looks := {}
	var places: Dictionary = world.areas[own_area].get("places", {})
	for id: String in known_place_ids(own_area):
		var place: Dictionary = places[id.get_slice("/", 1)]
		var cell := Vector2(place.get("cell", Vector2i(-1000, -1000)))
		var radius := float(maxi(int(place.get("radius", 1)), 1)) + 0.5
		var world_cell := box.position + cell + Vector2(0.5, 0.5)
		# A place on the mouth of a level whose chip is drawn takes the chip alone.
		if chip_mouths.any(func(mouth: Vector2) -> bool: return mouth.distance_to(world_cell) <= radius):
			continue
		var at := rect.position + (cell + Vector2(0.5, 0.5)) * cell_px
		_draw_ring(c, at)
		var look := place_look(id, UiTheme.color("text"))
		looks[id] = look
		labels.append({"id": id, "at": at, "size": sans.get_string_size(str(look["words"]), HORIZONTAL_ALIGNMENT_LEFT, -1, caption) + pad * 2.0})
	var name_of := func(ids: Array, at: Vector2) -> String:
		return _fold_name(ids, at, rect, cell_px)
	var measure := func(words: String) -> Vector2:
		return sans.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, caption) + pad * 2.0
	for group: Dictionary in WorldMapModel.fold(labels, keep_off, _k(&"ring") + pad.x, name_of, measure):
		var ids: Array = group["ids"]
		var folded := bool(group["folded"])
		var look: Dictionary = {"words": group["name"], "colour": UiTheme.color("text")} if folded else looks[ids[0]]
		var label_rect := _backed_text(c, str(look["words"]), (group["rect"] as Rect2).position, sans, caption, look["colour"])
		if ids.any(func(id: Variant) -> bool: return knows_way(str(id))):
			_mark_row(c, Vector2(label_rect.position.x + pad.x, label_rect.end.y - pad.y), label_rect.size.x - pad.x * 2.0, caption)
			label_rect.size.x += 20.0
		_groups.append({"ids": ids, "rect": label_rect, "folded": folded})
		if not folded:
			_rows[str(ids[0])] = label_rect


## The words of a folded label: the town's own name at the middle of its rings (where_name, the HUD's
## place words) when that names somewhere smaller than the whole area, else the name of the nearest of
## its places.
func _fold_name(ids: Array, at: Vector2, rect: Rect2, cell_px: Vector2) -> String:
	if where_name.is_valid():
		var cell := Vector2i(((at - rect.position) / cell_px).floor())
		var named := str(where_name.call(cell))
		if not named.is_empty() and named != str(world.areas[own_area].get("display_name", own_area)):
			return named
	var nearest := ""
	var best := INF
	var places: Dictionary = world.areas[own_area].get("places", {})
	for id: Variant in ids:
		var place: Dictionary = places[str(id).get_slice("/", 1)]
		var there := rect.position + (Vector2(place.get("cell", Vector2i.ZERO)) + Vector2(0.5, 0.5)) * cell_px
		if there.distance_to(at) < best:
			best = there.distance_to(at)
			nearest = str(place.get("name", id))
	return nearest


## The feet: under each box (the picture's under its edge) the area's read-out, dim, and the party
## in it, the bond's reason on hover (555); a box that is not the picture holds them inside its foot.
func _draw_feet(c: Control, rects: Dictionary, serif: Font, sans: Font, caption: int) -> void:
	var left_margin := _k(&"name_left")
	for area_name: String in rects:
		var rect: Rect2 = rects[area_name]
		var pictured := area_name == own_area and picture != null and picture_cells.x > 0 and picture_cells.y > 0
		var foot := Vector2(rect.position.x + left_margin, rect.end.y + caption * 1.4 if pictured else rect.end.y - caption * 0.5)
		if pictured:
			var note := str(notes.get(area_name, ""))
			if not note.is_empty():
				var note_size := int(caption * 0.85)
				c.draw_multiline_string(sans, foot, note, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - left_margin * 2.0, note_size, -1, UiTheme.color("text_dim"))
				foot.y += sans.get_multiline_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - left_margin * 2.0, note_size).y + caption * 0.6
		var here: Array[String] = []
		var why := ""  # The first bond reason on the line, for the hover (555, ui's side).
		for member: Dictionary in party:
			if str(member.get("area", "")) == area_name:
				here.append(party_words(member))
				if why.is_empty():
					why = str(member.get("why", ""))
		if here.is_empty():
			continue
		var line_words := ", ".join(here)
		c.draw_string(serif, foot, line_words, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - left_margin * 2.0, caption, UiTheme.color("friend"))
		var line_width := minf(serif.get_string_size(line_words, HORIZONTAL_ALIGNMENT_LEFT, -1, caption).x, rect.size.x - left_margin * 2.0)
		_party_rows[area_name] = {"rect": Rect2(foot.x, foot.y - caption, line_width, caption * 1.3), "why": why}
