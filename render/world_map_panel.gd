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
## ZOOMS' index: 1.5 at the start, so a box's words read at 1080p.
var zoom_step := 3
var pan := Vector2.ZERO
var _dragging := false
var _factions: Dictionary = {}
var _hover := ""


func _init() -> void:
	name = "WorldMap"
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


## Opened: the graph built the first time, the view centred on the
## player's area.
func open() -> void:
	if world == null:
		world = WorldMap.build()
		_read_layout()
		_lay_out()
		_read_factions()
	visible = true
	centre_on(own_area)
	queue_redraw()


func close() -> void:
	visible = false


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
	party.clear()
	party.append_array(here)
	for member: Variant in state.get("party", []):
		if member is Dictionary:
			party.append(member)
	queue_redraw()


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
		_dragging = click.pressed
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
	for way: Dictionary in world.ways:
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
		draw_string(serif, at, str(area.get("display_name", area_name)), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0 * scale,
			int(heading * scale), UiTheme.color("text"))
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
			draw_string(sans, at, words, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0 * scale, int(caption * scale), colour)
			at.y += caption * 1.2 * scale
		var here: Array[String] = []
		for member: Dictionary in party:
			if str(member.get("area", "")) == area_name:
				here.append(str(member.get("name", "")))
		if not here.is_empty():
			draw_string(serif, Vector2(rect.position.x + 18.0 * scale, rect.end.y - 12.0 * scale), ", ".join(here),
				HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0 * scale, int(caption * scale), UiTheme.color("friend"))
	# The title and how to leave.
	draw_string(serif, Vector2(UiTheme.constant("margin"), UiTheme.constant("margin") + heading), "The known world",
		HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.size("title"), UiTheme.color("text"))
	draw_string(sans, Vector2(UiTheme.constant("margin"), UiTheme.constant("margin") + heading + caption * 1.6),
		"wheel: zoom   drag: pan   Esc or M: close", HORIZONTAL_ALIGNMENT_LEFT, -1, caption, UiTheme.color("text_dim"))
