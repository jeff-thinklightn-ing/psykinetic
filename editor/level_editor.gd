class_name LevelEditor
extends Node2D
## The level editor (--edit=<map>): levels/<map>/layout.png as a top-down
## grid, made if there is none (--edit-size=WxH, default LevelMap.NEW_SIZE).
##
## A palette of every cell and edge type in the legend (docs/levels.md),
## and level.json's own. With a cell type picked, left click paints the
## cell under the cursor and a drag paints a line of them; with an edge type
## (wall, door, clear) picked, the edge nearest the cursor is lit and a
## click sets it, a drag a straight run along that line. Right click (and
## drag) erases: cells to void, edges to clear. Number keys pick from the
## palette (Shift and Alt for the second and third ten); Ctrl+S saves,
## Ctrl+Z undoes a stroke, Ctrl+Y (or Ctrl+Shift+Z) redoes it. Middle drag
## or the arrow keys pan, the wheel zooms.
##
## The select tool (V) picks a placed monster: Q / E (or the wheel over
## it) turn its facing an eighth at a time, and the panel on the right sets
## how it idles (guard, wander and its radius, patrol and its route, gather
## and its point, none, or its kind's default). Editing a route, a click adds
## a waypoint and a right click takes the last back; setting a point, a
## click sets it. Every monster shows its facing as an arrow (faint: the
## way it faces of its own, none set), a patrol its route, a gatherer its
## point. Esc stops a route or point, then lets go of the monster.
##
## Saving writes the same double-resolution layout.png (LevelMap.to_image)
## and its .import as Image, and says what the game will warn about
## (Level.parse); level.json too, when a monster's facing or idling was
## set, with only those in its entry (the rest of the file as it was).
## height.png is read and written back only when a resize moved it.
##
## Ctrl+R shows the canvas panel: grow or shrink the map from any side.
## Everything on it keeps its place on the ground, and level.json's cells
## (entities, routes, gather points, starts, spawn points, links, the
## centre) and height.png move with it; what falls off a shrunk side is
## dropped, and the status line says what. One undo step per change.

const CELL := 48.0
const GRID := Color(1, 1, 1, 0.07)
const BACKGROUND := Color(0.06, 0.06, 0.07)
const VOID_CELL := Color(0.1, 0.1, 0.11)
const WALL := Color(0.86, 0.8, 0.7)
const AUTO_WALL := Color(0.86, 0.8, 0.7, 0.35)
const DOOR := Color(0.95, 0.6, 0.2)
const HOVER := Color(1.0, 0.9, 0.3, 0.9)
const FONT_SIZE := 30
const PAN_SPEED := 1400.0
const UNDO_LIMIT := 200
const ARROW := Color(1, 1, 1, 0.95)
const ARROW_OWN := Color(1, 1, 1, 0.35)
const ROUTE := Color(0.35, 0.85, 1.0, 0.85)
const ROUTE_FAINT := Color(0.35, 0.85, 1.0, 0.3)
const POINT := Color(1.0, 0.55, 0.15, 0.9)
const SELECTED := Color(0.3, 1.0, 0.5, 0.95)
const NOWHERE := Vector2i(-1, -1)
## The idle modes the panel offers; "" is the kind's own (Monster.IDLE_BY_KIND).
const IDLE_CHOICES: Array[String] = ["", "guard", "wander", "patrol", "gather", "none"]

## Palette order: what the number keys pick, ten to a row.
const PALETTE: Array[String] = [
	"stone", "grass", "dirt", "water", "fire", "stair", "wall", "door", "clear", "void",
	"start", "monster_imp", "monster_brute", "monster_sneak", "crate", "boulder", "cart", "chest", "torch", "lantern",
	"link", "select",
]
const EDGE_BRUSHES: Array[String] = ["wall", "door", "clear"]
## A thing's letter on its cell.
const LETTERS := {"start": "S", "crate": "C", "boulder": "O", "cart": "K", "chest": "H", "torch": "T",
	"lantern": "L", "link": "→", "stair": "^", "monster_sneak": "N"}

var map_name := ""
## Where layout.png lives (res://levels/<map>/; tests use user://).
var folder := ""
var map: LevelMap
var config := {}
## What the palette offers: PALETTE, then level.json's own legend entries.
var palette: Array[String] = []
var brush := "stone"
var dirty := false
## The last save's report, shown in the status line.
var report := ""

## What the cursor is over: {"cell": Vector2i} or {"edge": Vector3i}, or {}.
var hover := {}
var _stroke: Dictionary = {}  # "cell"/"edge" key -> value before the stroke
var _stroke_button := MOUSE_BUTTON_NONE
var _stroke_from: Variant = null
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _panning := false
var _camera: Camera2D
var _status: Label
var _buttons: Dictionary[String, Button] = {}
## The select tool's monster (NOWHERE: none), and whether clicks now edit its
## route or set its gather point.
var selected := NOWHERE
var editing_route := false
var setting_point := false
## level.json has changes to write.
var config_dirty := false
## height.png was there when loaded, and has changes to write.
var had_heights := false
var heights_dirty := false
## Each monster cell's name as the game will give it (for its own facing).
var _names: Dictionary[Vector2i, String] = {}
var _panel: VBoxContainer
var _canvas: PanelContainer
var _canvas_size: Label


func _ready() -> void:
	if map_name.is_empty():
		map_name = Net.edit_map
	if folder.is_empty():
		folder = Level.DIR + map_name + "/"
	load_map()
	_camera = Camera2D.new()
	add_child(_camera)
	_camera.position = Vector2(map.size) * CELL * 0.5
	var fit := minf(3000.0 / (map.size.x * CELL), 1900.0 / (map.size.y * CELL))
	_camera.zoom = Vector2.ONE * clampf(fit, 0.2, 4.0)
	_build_ui()
	pick(brush)
	RenderingServer.set_default_clear_color(BACKGROUND)
	if Net.test_exit_after > 0.0:
		get_tree().create_timer(Net.test_exit_after).timeout.connect(_test_exit)


## --test-exit-after (and --screenshot): quit, after a picture if asked.
func _test_exit() -> void:
	if Net.screenshot_path != "":
		var error := get_viewport().get_texture().get_image().save_png(Net.screenshot_path)
		print("[test] screenshot %s: %s" % [Net.screenshot_path, "saved" if error == OK else error_string(error)])
	get_tree().quit()


## Reads the map (and level.json for its legend), or starts a blank one.
func load_map() -> void:
	config = {}
	var json_path := folder + "level.json"
	if FileAccess.file_exists(json_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
		if parsed is Dictionary:
			config = parsed
	var png := folder + "layout.png"
	var image: Image = null
	if FileAccess.file_exists(png):
		image = Image.load_from_file(ProjectSettings.globalize_path(png))
	if image != null:
		map = LevelMap.from_image(image, config)
		var heights_png := folder + "height.png"
		had_heights = FileAccess.file_exists(heights_png)
		if had_heights:
			map.read_heights(Image.load_from_file(ProjectSettings.globalize_path(heights_png)))
		report = "loaded %s: %d x %d cells%s" % [png, map.size.x, map.size.y,
			", %d pixels of colours not in the legend (void when saved)" % map.unknown_pixels if map.unknown_pixels > 0 else ""]
	else:
		had_heights = false
		map = LevelMap.new(Net.edit_size, config)
		report = "new map %s: %d x %d cells (not saved yet)" % [map_name, map.size.x, map.size.y]
	palette = PALETTE.duplicate()
	selected = NOWHERE
	config_dirty = false
	heights_dirty = false
	_name_cells()
	for meaning: String in map.colours:
		if meaning not in palette and meaning != "door" and meaning != "wall":
			palette.append(meaning)
	print("[editor] " + report)


## Writes layout.png and its .import (as Image). False if it could not.
func save() -> bool:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(folder)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var png := folder + "layout.png"
	var image := map.to_image()
	var error := image.save_png(ProjectSettings.globalize_path(png))
	if error != OK:
		report = "could not save %s (%s)" % [png, error_string(error)]
		print("[editor] " + report)
		return false
	var imported := LevelMap.ensure_image_import(ProjectSettings.globalize_path(png), png)
	if config_dirty:
		var json := FileAccess.open(ProjectSettings.globalize_path(folder + "level.json"), FileAccess.WRITE)
		if json == null:
			report = "could not save %slevel.json" % folder
			print("[editor] " + report)
			return false
		json.store_string(JSON.stringify(config, "	", false) + "
")
		json.close()
		config_dirty = false
	if heights_dirty:
		var heights_png := folder + "height.png"
		error = map.to_height_image().save_png(ProjectSettings.globalize_path(heights_png))
		if error != OK:
			report = "could not save %s (%s)" % [heights_png, error_string(error)]
			print("[editor] " + report)
			return false
		LevelMap.ensure_image_import(ProjectSettings.globalize_path(heights_png), heights_png)
		had_heights = true
		heights_dirty = false
	dirty = false
	var level := Level.parse(image, map.to_height_image() if had_heights else null, config)
	var warnings: Array = level["warnings"]
	report = "saved %s (%d x %d cells, %d floor, %d things)%s%s" % [png, map.size.x, map.size.y,
		(level["terrain"]["floor"] as Array).size(), (level["entities"] as Array).size(),
		"; import set to Image" if imported else "",
		"; warnings: " + "; ".join(warnings) if not warnings.is_empty() else ""]
	print("[editor] " + report)
	return true


# --- Tools and strokes -----------------------------------------------------------

func pick(meaning: String) -> void:
	if meaning not in palette:
		return
	brush = meaning
	if meaning != "select":
		select(NOWHERE)
	for each: String in _buttons:
		_buttons[each].button_pressed = each == meaning
	hover = {}


func is_edge_brush() -> bool:
	return brush in EDGE_BRUSHES


## What the cursor at [param grid] (cells, continuous) points at for the
## current brush: the nearest edge for an edge brush, else the cell. Out of
## bounds: {}.
func target_at(grid: Vector2) -> Dictionary:
	var at := Vector2i(floori(grid.x), floori(grid.y))
	if not is_edge_brush():
		return {"cell": at} if map.in_bounds(at) else {}
	var inside := grid - Vector2(at)
	var nearest := minf(minf(inside.x, 1.0 - inside.x), minf(inside.y, 1.0 - inside.y))
	var key: Vector3i
	if nearest == inside.x:
		key = Vector3i(at.x - 1, at.y, Terrain.EAST)
	elif nearest == 1.0 - inside.x:
		key = Vector3i(at.x, at.y, Terrain.EAST)
	elif nearest == inside.y:
		key = Vector3i(at.x, at.y - 1, Terrain.SOUTH)
	else:
		key = Vector3i(at.x, at.y, Terrain.SOUTH)
	return {"edge": key} if map.edge_in_bounds(key) else {}


## Starts a stroke with [param button] (left paints, right erases) at grid
## point [param grid].
func begin_stroke(button: MouseButton, grid: Vector2) -> void:
	if brush == "select":
		_select_click(button, Vector2i(floori(grid.x), floori(grid.y)))
		return
	_stroke = {}
	_stroke_button = button
	var target := target_at(grid)
	_stroke_from = target.get("cell", target.get("edge"))
	_apply(target)


## The stroke goes on to [param grid]: every cell on the line from the last
## one, or every edge along the first edge's line.
func continue_stroke(grid: Vector2) -> void:
	if _stroke_button == MOUSE_BUTTON_NONE or _stroke_from == null:
		return
	if _stroke_from is Vector2i:
		var to := Vector2i(floori(grid.x), floori(grid.y))
		var from: Vector2i = _stroke_from
		for at in _line(from, to):
			if map.in_bounds(at):
				_apply({"cell": at})
		_stroke_from = to
	else:
		var from: Vector3i = _stroke_from
		var along := floori(grid.y) if from.z == Terrain.EAST else floori(grid.x)
		var start := from.y if from.z == Terrain.EAST else from.x
		var step := 1 if along >= start else -1
		for i in range(start, along + step, step):
			var key := Vector3i(from.x, i, from.z) if from.z == Terrain.EAST else Vector3i(i, from.y, from.z)
			if map.edge_in_bounds(key):
				_apply({"edge": key})


## Ends the stroke: one undo step, if it changed anything.
func end_stroke() -> void:
	_stroke_button = MOUSE_BUTTON_NONE
	_stroke_from = null
	if _stroke.is_empty():
		return
	_name_cells()
	_undo.append(_stroke)
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()
	_redo.clear()
	_stroke = {}


func _apply(target: Dictionary) -> void:
	var erase := _stroke_button == MOUSE_BUTTON_RIGHT
	if target.has("cell"):
		var at: Vector2i = target["cell"]
		var meaning := "void" if erase else brush
		if map.cell(at) == meaning:
			return
		var old := map.set_cell(at, meaning)
		if not _stroke.has(at):
			_stroke[at] = old
	elif target.has("edge"):
		var key: Vector3i = target["edge"]
		var kind := "clear" if erase else brush
		if map.edge(key) == kind:
			return
		var old := map.set_edge(key, kind)
		if not _stroke.has(key):
			_stroke[key] = old
	else:
		return
	dirty = true
	queue_redraw()


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(_swap(_undo.pop_back()))


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(_swap(_redo.pop_back()))


## Puts [param stroke]'s values back; returns the values it replaced.
func _swap(stroke: Dictionary) -> Dictionary:
	var back := {}
	for key: Variant in stroke:
		if key is Vector2i:
			back[key] = map.set_cell(key, stroke[key])
		elif key is Vector3i:
			back[key] = map.set_edge(key, stroke[key])
		elif key == "canvas":
			back[key] = _canvas_state()
			_set_canvas_state(stroke[key])
		else:
			# A monster's entry: "entry x y" -> the entry as it was ({}: none).
			var parts := str(key).split(" ")
			var at := Vector2i(int(parts[1]), int(parts[2]))
			back[key] = entry_of(at).duplicate(true)
			_put_entry(at, stroke[key])
	_name_cells()
	_refresh_panel()
	dirty = true
	queue_redraw()
	return back


## The cells from [param a] to [param b], both ends in (Bresenham).
static func _line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var d := Vector2i(absi(b.x - a.x), -absi(b.y - a.y))
	var s := Vector2i(1 if a.x < b.x else -1, 1 if a.y < b.y else -1)
	var error := d.x + d.y
	var at := a
	while true:
		out.append(at)
		if at == b:
			break
		var e2 := 2 * error
		if e2 >= d.y:
			error += d.y
			at.x += s.x
		if e2 <= d.x:
			error += d.x
			at.y += s.y
	return out


# --- The canvas: resizing ------------------------------------------------------------

## Grows the map [param left], [param top], [param right], [param bottom]
## cells on those sides (negative shrinks it), as one undo step. Returns
## what fell off ("" for nothing).
func resize(left: int, top: int, right: int, bottom: int) -> String:
	var bigger := map.resized(left, top, right, bottom)
	if bigger.size == map.size and left == 0 and top == 0:
		return ""
	var before := _canvas_state()
	var offset := Vector2i(left, top)
	var dropped: Array[String] = []
	var lost := map.cells.keys().filter(func(at: Vector2i) -> bool: return not bigger.in_bounds(at + offset)).size()
	var moved := LevelMap.moved_config(config, func(at: Vector2i) -> Variant:
		return at + offset if bigger.in_bounds(at + offset) else null, 0, dropped)
	_set_canvas_state({"map": bigger, "config": moved})
	_undo.append({"canvas": before})
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()
	_redo.clear()
	if _camera != null:
		_camera.position += Vector2(offset) * CELL
	var lost_text := ""
	if lost > 0 or not dropped.is_empty():
		lost_text = "dropped %d cells%s" % [lost, (", " + ", ".join(dropped)) if not dropped.is_empty() else ""]
	report = "resized to %d x %d cells%s" % [map.size.x, map.size.y, "; " + lost_text if not lost_text.is_empty() else ""]
	print("[editor] " + report)
	return lost_text


## What a resize changes: the map (heights in it) and level.json.
func _canvas_state() -> Dictionary:
	return {"map": map, "config": config.duplicate(true)}


func _set_canvas_state(state: Dictionary) -> void:
	map = state["map"]
	config = state["config"]
	# height.png must match layout.png's size, after an undo too.
	heights_dirty = had_heights or not map.heights.is_empty()
	config_dirty = true
	dirty = true
	if selected != NOWHERE and not is_monster(selected):
		selected = NOWHERE
	_name_cells()
	_refresh_panel()
	queue_redraw()
	if _canvas_size != null:
		_canvas_size.text = "%d x %d cells" % [map.size.x, map.size.y]


func toggle_canvas() -> void:
	if _canvas != null:
		_canvas.visible = not _canvas.visible


# --- Monsters: facing and idling ----------------------------------------------------

## Whether cell [param at] holds a monster.
func is_monster(at: Vector2i) -> bool:
	return map.cell(at).begins_with("monster_")


## Selects the monster at [param at] (NOWHERE, or a cell with none: lets go).
func select(at: Vector2i) -> void:
	selected = at if at != NOWHERE and is_monster(at) else NOWHERE
	editing_route = false
	setting_point = false
	_refresh_panel()
	queue_redraw()


func _select_click(button: MouseButton, at: Vector2i) -> void:
	if not map.in_bounds(at):
		return
	if editing_route and selected != NOWHERE:
		if button == MOUSE_BUTTON_LEFT:
			add_waypoint(at)
		else:
			remove_waypoint()
		return
	if setting_point and selected != NOWHERE and button == MOUSE_BUTTON_LEFT:
		set_gather_point(at)
		setting_point = false
		_refresh_panel()
		return
	if button == MOUSE_BUTTON_LEFT:
		select(at)


## level.json's entry for the entity at [param at] ({} for none).
func entry_of(at: Vector2i) -> Dictionary:
	var listed: Variant = config.get("entities", [])
	if listed is Array:
		for entry: Variant in listed:
			if entry is Dictionary and Level._tile(entry.get("at")) == at:
				return entry
	return {}


## Puts [param entry] as the entry for [param at]: replaced where it is in
## the list, added at the end, or ({} or only "at") taken out.
func _put_entry(at: Vector2i, entry: Dictionary) -> void:
	if not config.get("entities") is Array:
		config["entities"] = []
	var listed: Array = config["entities"]
	var index := -1
	for i in listed.size():
		if listed[i] is Dictionary and Level._tile(listed[i].get("at")) == at:
			index = i
			break
	var empty := entry.keys().all(func(key: Variant) -> bool: return str(key) == "at")
	if empty:
		if index >= 0:
			listed.remove_at(index)
	elif index >= 0:
		listed[index] = entry
	else:
		listed.append(entry)
	if listed.is_empty():
		config.erase("entities")
	config_dirty = true
	dirty = true


## Changes the selected monster's entry with [param change] (given the
## entry to edit), as one undo step.
func _edit_selected(change: Callable) -> void:
	if selected == NOWHERE:
		return
	var before := entry_of(selected).duplicate(true)
	var entry := before.duplicate(true)
	entry["at"] = [selected.x, selected.y]
	change.call(entry)
	if entry == before:
		return
	_put_entry(selected, entry)
	_undo.append({"entry %d %d" % [selected.x, selected.y]: before})
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()
	_redo.clear()
	_refresh_panel()
	queue_redraw()


## The monster at [param at]'s facing: its entry's, or the one it takes of
## its own (Monster.own_facing); and whether it is set.
func facing_of(at: Vector2i) -> Array:
	var set_one: Variant = Level.facing_from(entry_of(at).get("facing"))
	if set_one != null:
		return [set_one, true]
	return [Monster.own_facing(_names.get(at, "")), false]


## Turns the selected monster [param steps] eighths of a turn (clockwise
## for positive), from the way it faces now.
func turn_selected(steps: int) -> void:
	if selected == NOWHERE:
		return
	var now: Vector2i = facing_of(selected)[0]
	var to := Monster.turned(now, steps)
	_edit_selected(func(entry: Dictionary) -> void: entry["facing"] = [to.x, to.y])


## Back to the way it faces of its own: no facing in its entry.
func clear_facing() -> void:
	_edit_selected(func(entry: Dictionary) -> void: entry.erase("facing"))


## The monster at [param at]'s idling as its entry gives it, as a
## Dictionary ({"mode": ""} for its kind's own).
func idle_of(at: Vector2i) -> Dictionary:
	var given: Variant = entry_of(at).get("idle")
	if given is Dictionary:
		return given
	if given is String:
		return {"mode": given}
	return {"mode": ""}


## Sets the selected monster's idle mode ("" for its kind's own), keeping
## what a mode needs that it already has (a route, a point).
func set_idle_mode(mode: String) -> void:
	var at := selected
	_edit_selected(func(entry: Dictionary) -> void:
		if mode.is_empty():
			entry.erase("idle")
			return
		var idle := idle_of(at).duplicate(true)
		idle["mode"] = mode
		if mode == "gather" and not idle.has("point"):
			idle["point"] = [at.x + 1, at.y]
		entry["idle"] = _tidy_idle(idle))


## An idle setting with only what its mode uses: a plain name for one that
## needs nothing else.
static func _tidy_idle(idle: Dictionary) -> Variant:
	var mode := str(idle.get("mode", ""))
	var keep := {"mode": mode}
	match mode:
		"wander":
			if idle.has("radius"):
				keep["radius"] = int(idle["radius"])
		"patrol":
			if idle.has("route"):
				keep["route"] = idle["route"]
				keep["loop"] = bool(idle.get("loop", true))
		"gather":
			if idle.has("point"):
				keep["point"] = idle["point"]
	return keep if keep.size() > 1 else mode


## Changes the selected monster's idling with [param change] (given it as a
## Dictionary), as one undo step.
func _edit_idle(change: Callable) -> void:
	var at := selected
	_edit_selected(func(entry: Dictionary) -> void:
		var idle := idle_of(at).duplicate(true)
		change.call(idle)
		entry["idle"] = _tidy_idle(idle))


## A waypoint at [param at] on the end of the selected monster's route.
func add_waypoint(at: Vector2i) -> void:
	if not map.walkable(at):
		return
	_edit_idle(func(idle: Dictionary) -> void:
		idle["mode"] = "patrol"
		var route: Array = idle.get("route", [])
		if route.is_empty() or Level._tile(route.back()) != at:
			route.append([at.x, at.y])
		idle["route"] = route
		if not idle.has("loop"):
			idle["loop"] = true)


## Takes the last waypoint off its route.
func remove_waypoint() -> void:
	_edit_idle(func(idle: Dictionary) -> void:
		var route: Array = idle.get("route", [])
		if not route.is_empty():
			route.pop_back()
		if route.is_empty():
			idle.erase("route")
		else:
			idle["route"] = route)


func clear_route() -> void:
	_edit_idle(func(idle: Dictionary) -> void: idle.erase("route"))


## Round and round ([param loop] true) or back and forth.
func set_route_loop(loop: bool) -> void:
	_edit_idle(func(idle: Dictionary) -> void: idle["loop"] = loop)


func set_gather_point(at: Vector2i) -> void:
	_edit_idle(func(idle: Dictionary) -> void:
		idle["mode"] = "gather"
		idle["point"] = [at.x, at.y])


## WANDER's radius, at least 1.
func set_wander_radius(radius: int) -> void:
	_edit_idle(func(idle: Dictionary) -> void:
		idle["mode"] = "wander"
		idle["radius"] = maxi(1, radius))


## The idle mode the selected monster's kind has of its own, by name.
func kind_mode(at: Vector2i) -> String:
	var kind := map.cell(at).trim_prefix("monster_")
	var mode: int = Monster.IDLE_BY_KIND.get(kind, Monster.Idle.NONE)
	return str(Monster.IDLE_MODES.find_key(mode))


## Every monster cell's name, as the game will name it (Level.parse).
func _name_cells() -> void:
	_names.clear()
	var level := Level.parse(map.to_image(), null, config)
	for spec: Dictionary in level["entities"]:
		if spec.get("script") == Level.MONSTER:
			_names[spec["tile"]] = str(spec["name"])
	if selected != NOWHERE and not is_monster(selected):
		selected = NOWHERE


## The panel for the selected monster, made again from what it is now.
func _refresh_panel() -> void:
	if _panel == null:
		return
	for child in _panel.get_children():
		_panel.remove_child(child)
		child.queue_free()
	_panel.get_parent().visible = selected != NOWHERE
	if selected == NOWHERE:
		return
	var facing: Array = facing_of(selected)
	var idle := idle_of(selected)
	var mode := str(idle.get("mode", ""))
	_panel_label("%s  (%s)" % [_names.get(selected, "?"), map.cell(selected).trim_prefix("monster_")], 30)
	_panel_label("at %d, %d" % [selected.x, selected.y], 22)
	_panel_label("Facing %s%s   Q / E or wheel" % [World.COMPASS[Monster.AROUND.find(facing[0])],
		"" if facing[1] else " (its own)"], 24)
	var facing_row := HBoxContainer.new()
	_panel.add_child(facing_row)
	_panel_button(facing_row, "Q  turn left", turn_selected.bind(-1))
	_panel_button(facing_row, "E  turn right", turn_selected.bind(1))
	if facing[1]:
		_panel_button(facing_row, "its own", clear_facing)
	_panel_label("Idle", 26)
	var modes := HBoxContainer.new()
	_panel.add_child(modes)
	for choice in IDLE_CHOICES:
		var text := choice if not choice.is_empty() else "kind's (%s)" % kind_mode(selected)
		var button := _panel_button(modes, text, set_idle_mode.bind(choice))
		button.toggle_mode = true
		button.button_pressed = choice == mode
	match mode:
		"wander":
			var radius := int(idle.get("radius", Monster.WANDER_RADIUS))
			var row := HBoxContainer.new()
			_panel.add_child(row)
			_panel_label_in(row, "radius %d" % radius)
			_panel_button(row, "-", set_wander_radius.bind(radius - 1))
			_panel_button(row, "+", set_wander_radius.bind(radius + 1))
		"patrol":
			var route: Array = idle.get("route", [])
			var loop := bool(idle.get("loop", true))
			_panel_label("Route: %d waypoints%s" % [route.size(), "" if not route.is_empty() else " (a loop of its own)"], 22)
			var row := HBoxContainer.new()
			_panel.add_child(row)
			var edit := _panel_button(row, "editing: click adds, right click takes back" if editing_route else "edit route",
					func() -> void:
						editing_route = not editing_route
						setting_point = false
						_refresh_panel())
			edit.toggle_mode = true
			edit.button_pressed = editing_route
			var row2 := HBoxContainer.new()
			_panel.add_child(row2)
			var round_button := _panel_button(row2, "loop", set_route_loop.bind(true))
			round_button.toggle_mode = true
			round_button.button_pressed = loop
			var back_button := _panel_button(row2, "back and forth", set_route_loop.bind(false))
			back_button.toggle_mode = true
			back_button.button_pressed = not loop
			_panel_button(row2, "clear", clear_route)
		"gather":
			var point: Variant = Level._tile(idle.get("point"))
			_panel_label("Point: %s" % (str(point) if point != null else "none"), 22)
			var set_button := _panel_button(_panel, "click a cell..." if setting_point else "set point", func() -> void:
				setting_point = not setting_point
				editing_route = false
				_refresh_panel())
			set_button.toggle_mode = true
			set_button.button_pressed = setting_point
	_panel_label("Esc lets go", 20)


func _panel_label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	_panel.add_child(label)
	return label


func _panel_label_in(row: Container, text: String) -> void:
	var label := Label.new()
	label.text = text + "  "
	label.add_theme_font_size_override("font_size", 22)
	row.add_child(label)


func _panel_button(row: Container, text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(on_press)
	row.add_child(button)
	return button


## Facing arrows on every monster, routes and gather points; the selected
## monster's brighter.
func _draw_monsters() -> void:
	for at: Vector2i in map.cells:
		if not is_monster(at):
			continue
		var mine := at == selected
		var centre := (Vector2(at) + Vector2(0.5, 0.5)) * CELL
		var facing: Array = facing_of(at)
		var way := Vector2(facing[0]).normalized()
		var colour: Color = SELECTED if mine else (ARROW if facing[1] else ARROW_OWN)
		var tip := centre + way * CELL * 0.48
		draw_line(centre, tip, colour, 4.0)
		var side := way.orthogonal() * CELL * 0.13
		draw_colored_polygon(PackedVector2Array([tip + way * CELL * 0.08, tip - way * CELL * 0.12 + side,
			tip - way * CELL * 0.12 - side]), colour)
		var idle := idle_of(at)
		match str(idle.get("mode", "")):
			"patrol":
				var points: Array[Vector2] = []
				for point: Variant in idle.get("route", []):
					var tile: Variant = Level._tile(point)
					if tile != null:
						points.append((Vector2(tile) + Vector2(0.5, 0.5)) * CELL)
				if points.is_empty():
					continue
				var line_colour := ROUTE if mine else ROUTE_FAINT
				draw_line(centre, points[0], line_colour, 2.0)
				for i in points.size() - 1:
					draw_line(points[i], points[i + 1], line_colour, 4.0 if mine else 2.0)
				if bool(idle.get("loop", true)) and points.size() > 2:
					draw_line(points.back(), points[0], line_colour, 4.0 if mine else 2.0)
				for i in points.size():
					draw_circle(points[i], CELL * 0.16, line_colour)
					if mine:
						draw_string(ThemeDB.fallback_font, points[i] + Vector2(-CELL * 0.5, CELL * 0.1), str(i + 1),
								HORIZONTAL_ALIGNMENT_CENTER, CELL, 20, Color.BLACK)
			"gather":
				var point: Variant = Level._tile(idle.get("point"))
				if point != null:
					var spot: Vector2 = (Vector2(point) + Vector2(0.5, 0.5)) * CELL
					draw_line(centre, spot, POINT if mine else Color(POINT, 0.35), 2.0)
					draw_arc(spot, CELL * 0.32, 0.0, TAU, 24, POINT if mine else Color(POINT, 0.5), 4.0)
	if selected != NOWHERE:
		draw_rect(Rect2(Vector2(selected) * CELL, Vector2.ONE * CELL).grow(2.0), SELECTED, false, 5.0)


# --- Input -------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.ctrl_pressed and key.keycode == KEY_S:
			save()
		elif key.ctrl_pressed and (key.keycode == KEY_Y or key.keycode == KEY_Z and key.shift_pressed):
			redo()
		elif key.ctrl_pressed and key.keycode == KEY_Z:
			undo()
		elif key.ctrl_pressed and key.keycode == KEY_R:
			toggle_canvas()
		elif key.keycode == KEY_V and not key.ctrl_pressed:
			pick("select")
		elif key.keycode in [KEY_Q, KEY_E] and selected != NOWHERE:
			turn_selected(-1 if key.keycode == KEY_Q else 1)
		elif key.keycode == KEY_ESCAPE and brush == "select":
			if editing_route or setting_point:
				editing_route = false
				setting_point = false
				_refresh_panel()
			else:
				select(NOWHERE)
		elif key.keycode >= KEY_0 and key.keycode <= KEY_9 and not key.ctrl_pressed:
			var digit := (key.keycode - KEY_0 + 9) % 10  # 1 -> 0, ..., 0 -> 9
			var index := digit + (10 if key.shift_pressed else 20 if key.alt_pressed else 0)
			if index < palette.size():
				pick(palette[index])
		else:
			return
		get_viewport().set_input_as_handled()
		return
	var button := event as InputEventMouseButton
	if button != null:
		if button.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = button.pressed
		elif button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and button.pressed:
			var grid := _mouse_grid()
			if selected != NOWHERE and Vector2i(floori(grid.x), floori(grid.y)) == selected:
				# The wheel over the chosen monster turns it.
				turn_selected(1 if button.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
			else:
				_zoom(1.15 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15)
		elif button.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			if button.pressed and _stroke_button == MOUSE_BUTTON_NONE:
				begin_stroke(button.button_index, _mouse_grid())
			elif not button.pressed and button.button_index == _stroke_button:
				end_stroke()
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		if _panning:
			_camera.position -= motion.relative / _camera.zoom
		continue_stroke(_mouse_grid())


func _zoom(factor: float) -> void:
	var before := _mouse_grid()
	_camera.zoom = (_camera.zoom * factor).clamp(Vector2.ONE * 0.15, Vector2.ONE * 6.0)
	_camera.force_update_scroll()
	_camera.position += (before - _mouse_grid()) * CELL


func _mouse_grid() -> Vector2:
	return get_global_mouse_position() / CELL


func _process(delta: float) -> void:
	var pan := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if pan != Vector2.ZERO:
		_camera.position += pan * PAN_SPEED * delta / _camera.zoom.x
	var now := target_at(_mouse_grid())
	if now != hover:
		hover = now
		queue_redraw()
	_status.text = _status_text()
	var title := "Level editor: %s%s" % [map_name, " *" if dirty else ""]
	if DisplayServer.get_name() != "headless" and get_window().title != title:
		get_window().title = title


func _status_text() -> String:
	var over := ""
	if hover.has("cell"):
		var at: Vector2i = hover["cell"]
		over = "cell %d, %d: %s" % [at.x, at.y, map.cell(at)]
	elif hover.has("edge"):
		var key: Vector3i = hover["edge"]
		over = "edge %s of %d, %d: %s" % ["east" if key.z == Terrain.EAST else "south", key.x, key.y, map.edge(key)]
	var tools := "LMB paint  RMB erase  1-0 / Shift / Alt pick  V select"
	if brush == "select":
		tools = "LMB pick a monster  Q / E turn it  Esc let go" if not editing_route \
				else "LMB add a waypoint  RMB take the last back  Esc done"
		if setting_point:
			tools = "LMB the gather point  Esc never mind"
	return "%s%s   %s   brush: %s   |   %s  Ctrl+R resize  Ctrl+S save  Ctrl+Z undo  Ctrl+Y redo  MMB / arrows pan  wheel zoom\n%s" % [
		map_name, " (unsaved)" if dirty else "", over, brush, tools, report]


# --- Drawing -----------------------------------------------------------------------

func _draw() -> void:
	var font := ThemeDB.fallback_font
	for y in map.size.y:
		for x in map.size.x:
			var at := Vector2i(x, y)
			var rect := Rect2(Vector2(at) * CELL, Vector2.ONE * CELL)
			var meaning := map.cell(at)
			if meaning == "void":
				draw_rect(rect, VOID_CELL)
				continue
			var ground := meaning if meaning in Level.GROUNDS or meaning in ["water", "fire"] else map.ground_under(at)
			draw_rect(rect, map.colours.get(ground, VOID_CELL))
			if ground != meaning:
				draw_rect(rect.grow(-CELL * 0.18), map.colours.get(meaning, Color.MAGENTA))
				var letter: String = LETTERS.get(meaning, meaning.trim_prefix("monster_").left(1).to_upper())
				draw_string(font, rect.position + Vector2(0, CELL * 0.68), letter, HORIZONTAL_ALIGNMENT_CENTER, CELL, 26, Color(0, 0, 0, 0.8))
	for x in map.size.x + 1:
		draw_line(Vector2(x, 0) * CELL, Vector2(x, map.size.y) * CELL, GRID)
	for y in map.size.y + 1:
		draw_line(Vector2(0, y) * CELL, Vector2(map.size.x, y) * CELL, GRID)
	# The outer walls the game builds by itself, where floor meets void.
	for y in range(-1, map.size.y):
		for x in range(-1, map.size.x):
			for side in [Terrain.EAST, Terrain.SOUTH]:
				var key := Vector3i(x, y, side)
				var sides := Terrain.edge_cells(key)
				if map.walkable(sides[0]) != map.walkable(sides[1]) and map.cell(sides[0]) != "water" and map.cell(sides[1]) != "water":
					_draw_edge(key, AUTO_WALL, 4.0)
	for key: Vector3i in map.edges:
		_draw_edge(key, WALL if map.edges[key] == "wall" else DOOR, 8.0, map.edges[key] == "door")
	_draw_monsters()
	if hover.has("cell"):
		draw_rect(Rect2(Vector2(hover["cell"]) * CELL, Vector2.ONE * CELL), HOVER, false, 4.0)
	elif hover.has("edge"):
		_draw_edge(hover["edge"], HOVER, 10.0)
	draw_rect(Rect2(Vector2.ZERO, Vector2(map.size) * CELL), Color(1, 1, 1, 0.3), false, 2.0)


func _draw_edge(key: Vector3i, colour: Color, width: float, door := false) -> void:
	var a := Vector2(key.x + 1, key.y) if key.z == Terrain.EAST else Vector2(key.x, key.y + 1)
	var b := a + (Vector2(0, 1) if key.z == Terrain.EAST else Vector2(1, 0))
	if door:
		var mid := (a + b) * 0.5
		draw_line(a * CELL, (a.lerp(mid, 0.6)) * CELL, colour, width)
		draw_line((b.lerp(mid, 0.6)) * CELL, b * CELL, colour, width)
		draw_line(a.lerp(mid, 0.6) * CELL, b.lerp(mid, 0.6) * CELL, colour, width * 0.4)
	else:
		draw_line(a * CELL, b * CELL, colour, width)


# --- UI ----------------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(30, 140)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.06, 0.88)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	panel.add_child(list)
	var group := ButtonGroup.new()
	for i in palette.size():
		var meaning := palette[i]
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 26)
		button.text = "%s  %s" % ["V   " if meaning == "select" else key_name(i),
			meaning.trim_prefix("monster_") + (" (edge)" if meaning in EDGE_BRUSHES else " (a monster)" if meaning == "select" else "")]
		button.icon = _swatch(meaning)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(pick.bind(meaning))
		list.add_child(button)
		_buttons[meaning] = button
	var side := PanelContainer.new()
	side.add_theme_stylebox_override("panel", style)
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.offset_left = -760.0
	side.offset_right = -30.0
	side.offset_top = 140.0
	side.visible = false
	layer.add_child(side)
	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 8)
	side.add_child(_panel)
	_build_canvas_panel(layer, style)
	_status = Label.new()
	_status.position = Vector2(30, 20)
	_status.add_theme_font_size_override("font_size", FONT_SIZE)
	_status.add_theme_color_override("font_color", Color(0.93, 0.92, 0.88))
	layer.add_child(_status)


## The canvas panel (Ctrl+R): the size, and per side buttons to grow or
## shrink it by 1 or 8 cells.
func _build_canvas_panel(layer: CanvasLayer, style: StyleBox) -> void:
	_canvas = PanelContainer.new()
	_canvas.add_theme_stylebox_override("panel", style)
	_canvas.anchor_left = 0.5
	_canvas.anchor_right = 0.5
	_canvas.offset_left = -330.0
	_canvas.offset_right = 330.0
	_canvas.offset_top = 140.0
	_canvas.visible = false
	layer.add_child(_canvas)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	_canvas.add_child(list)
	var title := Label.new()
	title.text = "Canvas   (Ctrl+R hides)"
	title.add_theme_font_size_override("font_size", 28)
	list.add_child(title)
	_canvas_size = Label.new()
	_canvas_size.text = "%d x %d cells" % [map.size.x, map.size.y]
	_canvas_size.add_theme_font_size_override("font_size", 24)
	list.add_child(_canvas_size)
	var sides: Array[String] = ["left", "top", "right", "bottom"]
	for side in sides:
		var row := HBoxContainer.new()
		list.add_child(row)
		var label := Label.new()
		label.text = side
		label.custom_minimum_size = Vector2(110, 0)
		label.add_theme_font_size_override("font_size", 24)
		row.add_child(label)
		for amount: int in [-8, -1, 1, 8]:
			var grow := [0, 0, 0, 0]
			grow[sides.find(side)] = amount
			_panel_button(row, "%+d" % amount, func() -> void: resize(grow[0], grow[1], grow[2], grow[3]))


## The key that picks palette entry [param index]: "1" .. "0", "Shift+1" ..
## "Alt+1" ..; "" past the thirtieth.
static func key_name(index: int) -> String:
	if index >= 30:
		return "    "
	var digit := str((index % 10 + 1) % 10)
	return ["", "Shift+", "Alt+"][index / 10] + digit


func _swatch(meaning: String) -> Texture2D:
	var image := Image.create(36, 36, false, Image.FORMAT_RGBA8)
	var colour: Color = map.colours.get(meaning, Color.WHITE) if meaning not in ["clear", "select"] else Color(0, 0, 0, 0)
	if meaning == "wall":
		colour = WALL
	image.fill(colour)
	if meaning == "clear":
		for i in 36:
			image.set_pixel(i, i, Color.WHITE)
	return ImageTexture.create_from_image(image)
