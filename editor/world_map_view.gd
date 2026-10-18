class_name WorldMapView
extends Control
## The world map editor (--world-map): every level as a box and every way
## between them as a wire (WorldMap), on a GraphEdit.
##
## A box's rows: "in" (where links arrive), its four sides (north, east,
## south, west: its neighbours, level.json "neighbours") and its links (one
## per link marker: its cell, where it goes, the spawn point it arrives at).
## Drag from a side to a side of another box to make the two neighbours,
## both ways (WorldMap.join); drag from a link to a box's "in" to send the
## link there; disconnect a wire (drag its end away) to take a neighbour
## away (both sides) or leave a link going nowhere. A link's spawn point is
## picked from the target's spawn points; x takes the link out of level.json
## (its marker stays: put one in or take it out in the level editor).
## Double-click a box to open that level in the level editor (unsaved
## changes are saved first). A box's title bar takes the colour of its area's
## holder, and a row per place shows who holds it, as the levels start them
## (Holdings: the server's own holdings are not read here). Ctrl+S saves every changed level.json and where
## the boxes are (levels/world_map.json, which is only for this view). The
## panel on the right lists WorldMap.problems() as they stand.

const LAYOUT_PATH := "res://levels/world_map.json"
## Port types: a side joins a side, a link an "in".
const EDGE := 0
const LINK := 1
const EDGE_COLOUR := Color(0.45, 0.9, 0.5)
const LINK_COLOUR := Color(0.4, 0.7, 1.0)
const SIDES: Array[String] = ["north", "east", "south", "west"]
## Space between boxes laid out for the first time.
const GAP := Vector2(120, 60)
## Where the first column starts: clear of GraphEdit's toolbar.
const ORIGIN := Vector2(40, 90)
const PANEL := Color(0.16, 0.17, 0.2)
const TITLE := Color(0.24, 0.26, 0.32)
const SELECTED_TITLE := Color(0.3, 0.45, 0.7)

var graph: GraphEdit
var world_map: WorldMap
## Who holds what, as the levels start it (the server's own is not here).
var holdings: Holdings
## Levels opened for editing (name -> MapDoc), the ones changed or about to be.
var docs: Dictionary[String, MapDoc] = {}
## Box positions, by level name.
var positions: Dictionary[String, Vector2] = {}
## Per box: its ports as GraphEdit numbers them, left ("in" or a side) and
## right (a side, or a link's cell): name -> {left: [..], right: [..]}.
var _ports: Dictionary[String, Dictionary] = {}
var _problems: RichTextLabel
var _status: Label


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.06, 0.06, 0.07))
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var split := HSplitContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(split)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(left)
	_status = Label.new()
	left.add_child(_status)
	graph = GraphEdit.new()
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph.right_disconnects = true
	graph.connection_request.connect(_on_connect)
	graph.disconnection_request.connect(_on_disconnect)
	left.add_child(graph)
	_problems = RichTextLabel.new()
	_problems.custom_minimum_size = Vector2(420, 0)
	_problems.scroll_following = false
	split.add_child(_problems)
	_read_layout()
	refresh()
	if Net.test_exit_after > 0.0:
		get_tree().create_timer(Net.test_exit_after).timeout.connect(_test_exit)


## --test-exit-after (and --screenshot): quit, after a picture if asked.
func _test_exit() -> void:
	if Net.screenshot_path != "":
		var error := get_viewport().get_texture().get_image().save_png(Net.screenshot_path)
		print("[test] screenshot %s: %s" % [Net.screenshot_path, "saved" if error == OK else error_string(error)])
	get_tree().quit()


func _shortcut_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.keycode == KEY_S:
		save()
		get_viewport().set_input_as_handled()


# --- The graph -----------------------------------------------------------------------

## Reads the world map again (unsaved levels as they are here) and redraws
## every box and wire, boxes kept where they were.
func refresh() -> void:
	for node: GraphNode in _boxes():
		positions[node.name] = node.position_offset
	var sources := {}
	for area_name: String in docs:
		var doc := docs[area_name]
		sources[area_name] = {"layout": doc.map.to_image(), "config": doc.config,
			"height": doc.map.to_height_image() if doc.had_heights or not doc.map.heights.is_empty() else null}
	world_map = WorldMap.build(Level.names(), sources)
	holdings = Holdings.new(world_map)
	graph.clear_connections()
	for node: GraphNode in _boxes():
		graph.remove_child(node)
		node.queue_free()
	_ports.clear()
	var boxes: Dictionary[String, GraphNode] = {}
	for area_name: String in world_map.areas:
		boxes[area_name] = _box(area_name)
		graph.add_child(boxes[area_name])
	# In the tree, so the boxes have their theme and so their sizes.
	var place := _default_places(boxes)
	for area_name: String in boxes:
		boxes[area_name].position_offset = positions.get(area_name, place[area_name])
	for way: Dictionary in world_map.ways:
		var to: String = way["to"]
		if not world_map.areas.has(to):
			continue
		var from_port: int = _ports[way["from"]]["right"].find(way["side"] if way["kind"] == "edge" else way["at"])
		var to_port: int = _ports[to]["left"].find(Level.OPPOSITE[way["side"]] if way["kind"] == "edge" else "in")
		graph.connect_node(way["from"], from_port, to, to_port)
	_show_problems()


func _boxes() -> Array[GraphNode]:
	var out: Array[GraphNode] = []
	for child in graph.get_children():
		if child is GraphNode and not child.is_queued_for_deletion():
			out.append(child)
	return out


## Columns by how many ways from the start zone (else the default map:
## WorldMap.root()), rows in order; areas it does not reach in a last
## column. Spaced by the boxes' own sizes.
func _default_places(boxes: Dictionary[String, GraphNode]) -> Dictionary:
	var out := {}
	var depth := {}
	var reached := world_map.reachable(WorldMap.root())
	for area_name in reached:
		if area_name == WorldMap.root():
			depth[area_name] = 0
			continue
		for way: Dictionary in world_map.ways_into(area_name):
			if depth.has(way["from"]):
				depth[area_name] = mini(depth.get(area_name, 1 << 20), depth[way["from"]] + 1)
	var last_column := 0
	for area_name: String in depth:
		last_column = maxi(last_column, depth[area_name])
	var columns: Array[Array] = []
	for area_name: String in world_map.areas:
		var column: int = depth.get(area_name, last_column + 1)
		while columns.size() <= column:
			columns.append([])
		columns[column].append(area_name)
	var x := ORIGIN.x
	for column in columns:
		var y := ORIGIN.y
		var width := 0.0
		for area_name: String in column:
			var size := boxes[area_name].get_combined_minimum_size()
			out[area_name] = Vector2(x, y)
			y += size.y + GAP.y
			width = maxf(width, size.x)
		x += width + GAP.x
	return out


func _box(area_name: String) -> GraphNode:
	var area: Dictionary = world_map.areas[area_name]
	var node := GraphNode.new()
	node.name = area_name
	var display: String = area["display_name"]
	node.title = "%s (%s)" % [display, area_name] if not display.is_empty() and display != area_name else area_name
	if area_name == WorldMap.start_zone():
		node.title += ", start"
	node.tooltip_text = "%d x %d cells; double-click to open it in the level editor" % [area["size"].x, area["size"].y]
	node.gui_input.connect(_on_box_input.bind(area_name))
	node.add_theme_stylebox_override("panel", _style(PANEL, false))
	node.add_theme_stylebox_override("panel_selected", _style(PANEL, false))
	# The title bar is the area's holder's colour (grey: nobody's).
	var held := holdings.area_holder(area_name)
	var title_colour := TITLE.lerp(holdings.factions.colour(held), 0.0 if held == Factions.NOBODY else 0.55)
	node.add_theme_stylebox_override("titlebar", _style(title_colour, true))
	node.add_theme_stylebox_override("titlebar_selected", _style(title_colour.lerp(SELECTED_TITLE, 0.5), true))
	if held != Factions.NOBODY:
		node.title += "  - %s" % holdings.factions.display_name(held)
	var left: Array = []
	var right: Array = []
	var row := 0
	var arrive := Label.new()
	arrive.text = "in"
	node.add_child(arrive)
	node.set_slot(row, true, LINK, LINK_COLOUR, false, LINK, LINK_COLOUR)
	left.append("in")
	row += 1
	var neighbours: Dictionary = area["neighbours"]
	for side in SIDES:
		var label := Label.new()
		label.text = "%s: %s" % [side, neighbours.get(side, "-")]
		node.add_child(label)
		node.set_slot(row, true, EDGE, EDGE_COLOUR, true, EDGE, EDGE_COLOUR)
		left.append(side)
		right.append(side)
		row += 1
	for link: Dictionary in area["links"]:
		node.add_child(_link_row(area_name, link))
		node.set_slot(row, false, LINK, LINK_COLOUR, true, LINK, LINK_COLOUR)
		right.append(link["tile"])
		row += 1
	for id in holdings.places_in(area_name):
		node.add_child(_place_row(id))
	_ports[area_name] = {"left": left, "right": right}
	return node


## A place's row: its holder's colour, key, kind, cell, radius and holder.
func _place_row(id: String) -> HBoxContainer:
	var place := holdings.place(id)
	var held := holdings.holder(id)
	var row := HBoxContainer.new()
	var swatch := ColorRect.new()
	swatch.color = holdings.factions.colour(held)
	swatch.custom_minimum_size = Vector2(18, 18)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)
	var label := Label.new()
	label.text = "%s: %s at %s, r %d, %s" % [place["key"], place["kind"], place["cell"], place["radius"], holdings.factions.display_name(held)]
	row.add_child(label)
	return row


func _style(colour: Color, top: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = colour
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	if top:
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
	else:
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
	return style


## A link's row: its cell, where it goes, its spawn point there, and x.
func _link_row(area_name: String, link: Dictionary) -> HBoxContainer:
	var at: Vector2i = link["tile"]
	var to: String = link["to_map"]
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "link %s -> %s%s" % [at, to if not to.is_empty() else "nowhere", "  |closed|" if link.get("closed", false) else ""]
	row.add_child(label)
	if world_map.areas.has(to):
		var spawn := OptionButton.new()
		var choices: Array[String] = [""]
		for spawn_name: String in world_map.areas[to]["spawn_points"]:
			choices.append(spawn_name)
		if link["to_spawn"] not in choices:
			choices.append(link["to_spawn"])
		for choice in choices:
			spawn.add_item(choice if not choice.is_empty() else "(first start)")
		spawn.select(choices.find(link["to_spawn"]))
		spawn.item_selected.connect(func(index: int) -> void: set_link(area_name, at, to, choices[index]))
		row.add_child(spawn)
	var remove := Button.new()
	remove.text = "x"
	remove.tooltip_text = "take this link out of level.json (the marker stays)"
	remove.pressed.connect(func() -> void: remove_link(area_name, at))
	row.add_child(remove)
	return row


func _on_box_input(event: InputEvent, area_name: String) -> void:
	if event is InputEventMouseButton and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
		open_area(area_name)


func _on_connect(from: StringName, from_port: int, to: StringName, to_port: int) -> void:
	var what: Variant = _ports[from]["right"][from_port]
	if what is String:
		join(from, what, to)
	elif _ports[to]["left"][to_port] == "in":
		set_link(from, what, to, default_spawn(from, to))


func _on_disconnect(from: StringName, from_port: int, to: StringName, _to_port: int) -> void:
	var what: Variant = _ports[from]["right"][from_port]
	if what is String:
		unjoin(from, what, to)
	else:
		set_link(from, what, "", "")


# --- Edits (callable without the mouse: the test drives these) -------------------------

## [param a] and [param b] neighbours across a's [param side], both ways.
func join(a: String, side: String, b: String) -> void:
	WorldMap.join(doc(a), side, doc(b))
	_changed("%s's %s neighbour is %s, and %s's %s is %s" % [a, side, b, b, Level.OPPOSITE[side], a])


## [param a]'s [param side] neighbour [param b] taken away, both ways.
func unjoin(a: String, side: String, b: String) -> void:
	WorldMap.unjoin(doc(a), side, doc(b))
	_changed("%s has no %s neighbour" % [a, side])


## The link on [param at] in [param area_name] goes to [param to] (""
## for nowhere), arriving at [param to_spawn].
func set_link(area_name: String, at: Vector2i, to: String, to_spawn: String) -> void:
	var level_doc := doc(area_name)
	var link := level_doc.link_of(at).duplicate(true)
	if link.is_empty():
		link = {"at": [at.x, at.y]}
	link["to_map"] = to
	link["to_spawn"] = to_spawn
	level_doc.put_link(at, link)
	_mark(level_doc)
	_changed("%s's link at %s goes to %s" % [area_name, at, "%s, %s" % [to, to_spawn if not to_spawn.is_empty() else "its first start"] if not to.is_empty() else "nowhere"])


## The link on [param at] in [param area_name] taken out of level.json.
func remove_link(area_name: String, at: Vector2i) -> void:
	var level_doc := doc(area_name)
	level_doc.put_link(at, {})
	_mark(level_doc)
	_changed("%s's link at %s is gone from level.json (its marker is still on the map)" % [area_name, at])


## The spawn point a new link from [param from] into [param to] arrives
## at: "from_<from>" if there is one, else the first, else "" (its start).
func default_spawn(from: String, to: String) -> String:
	var spawns: Dictionary = world_map.areas[to]["spawn_points"]
	if spawns.has("from_" + from):
		return "from_" + from
	return str(spawns.keys()[0]) if not spawns.is_empty() else ""


## Level [param area_name] opened for editing (once).
func doc(area_name: String) -> MapDoc:
	if not docs.has(area_name):
		docs[area_name] = MapDoc.open(folder_of(area_name))
	return docs[area_name]


## Where level [param area_name]'s files are: the one place this view
## names a folder, to follow Level's own lookup (a user:// overlay first).
static func folder_of(area_name: String) -> String:
	return Level.folder_of(area_name)


func _mark(level_doc: MapDoc) -> void:
	level_doc.config_dirty = true
	level_doc.dirty = true


func _changed(what: String) -> void:
	print("[world map] " + what)
	refresh()
	_status.text += "   " + what


## Saves every changed level and the boxes' places. False if a level could
## not be saved (the status says which).
func save() -> bool:
	var saved: Array[String] = []
	for area_name: String in docs:
		var level_doc := docs[area_name]
		if not level_doc.config_dirty:
			continue
		if not level_doc.save():
			_status.text = "could not save %s: %s" % [area_name, level_doc.report]
			return false
		saved.append(area_name)
	for node: GraphNode in _boxes():
		positions[node.name] = node.position_offset
	var places := {}
	for area_name: String in positions:
		places[area_name] = [roundi(positions[area_name].x), roundi(positions[area_name].y)]
	var file := FileAccess.open(ProjectSettings.globalize_path(LAYOUT_PATH), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"positions": places}, "\t", true) + "\n")
		file.close()
	print("[world map] saved %s" % (", ".join(saved) if not saved.is_empty() else "the layout only"))
	_show_problems()
	_status.text = "saved " + (", ".join(saved) if not saved.is_empty() else "the layout")
	return true


## Opens [param area_name] in the level editor, after saving.
func open_area(area_name: String) -> void:
	if unsaved() and not save():
		return
	Net.edit_map = area_name
	get_tree().change_scene_to_file.call_deferred("res://editor/level_editor.tscn")


## Whether any level.json here has changes not saved.
func unsaved() -> bool:
	return docs.values().any(func(level_doc: MapDoc) -> bool: return level_doc.config_dirty)


func _read_layout() -> void:
	if not FileAccess.file_exists(LAYOUT_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	if not parsed is Dictionary or not parsed.get("positions") is Dictionary:
		return
	for area_name: String in parsed["positions"]:
		var at: Variant = parsed["positions"][area_name]
		if at is Array and at.size() == 2:
			positions[area_name] = Vector2(float(at[0]), float(at[1]))


func _show_problems() -> void:
	var problems := world_map.problems()
	_problems.clear()
	_problems.append_text("[b]Problems[/b] (%d)\n\n" % problems.size())
	for problem in problems:
		_problems.append_text("- %s\n" % problem)
	if problems.is_empty():
		_problems.append_text("none: every way has a way back, every spawn point is there, every area can be reached.\n")
	_status.text = "%d areas, %d ways%s. Side to side: neighbours; link to in: send it there; double-click: open; Ctrl+S: save." % [
		world_map.areas.size(), world_map.ways.size(), "; unsaved" if unsaved() else ""]
