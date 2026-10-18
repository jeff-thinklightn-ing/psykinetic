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
## height.png is written whenever a height changed (all black if every
## height went back to 0).
##
## Heights (decision 357; the changes are HeightTools', as builder mode's
## are): the height tool (H) raises the cells under its brush a level with
## a click or a drag (each cell once a stroke), a right click lowers them,
## Shift+click sets them to the picked level, Alt+click picks a cell's
## level; [ and ] size the brush (1, 3, 5, 9). The stairs tool (S): press
## on the low cell and drag the way it climbs, one cell for a stair, more
## for a flight up a level a cell. With an area dragged out, the area panel
## raises, lowers or levels it, or makes a hill in it. While either tool is
## picked (Ctrl+H for always), each cell is tinted by its level, the level
## written on it, cliffs drawn heavier and stairs with their climb; the
## status line says the hovered cell's level.
##
## Ctrl+R shows the canvas panel: grow or shrink the map from any side.
## Everything on it keeps its place on the ground, and level.json's cells
## (entities, routes, gather points, starts, spawn points, links, the
## centre) and height.png move with it; what falls off a shrunk side is
## dropped, and the status line says what. One undo step per change.
##
## Prefabs (Prefab, levels/prefabs/): the area tool (A) drags out a
## rectangle, and its panel saves what is in it as a named prefab. The stamp
## tool (P) lists the prefabs; the picked one follows the cursor as a ghost,
## R turns it a quarter, and a click lays it down as one undo step.
##
## Area tools (AreaTools): with an area dragged out, the panel fills it
## with a pond (water and its shore), a grove (trees, a clearing if asked),
## a scatter (boulders, crates, trees) or a fence round it (a gate on a
## side), each from a seed: "again" takes the last fill back and lays it
## with the next seed. The path tool (T) takes clicked points (right click
## takes the last back) and Enter lays a winding path through them, [ and ]
## its width. Each is one undo step.

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
const ARROW := Color(1, 1, 1, 0.95)
const ARROW_OWN := Color(1, 1, 1, 0.35)
const ROUTE := Color(0.35, 0.85, 1.0, 0.85)
const ROUTE_FAINT := Color(0.35, 0.85, 1.0, 0.3)
const POINT := Color(1.0, 0.55, 0.15, 0.9)
const SELECTED := Color(0.3, 1.0, 0.5, 0.95)
const AREA := Color(0.45, 0.8, 1.0, 0.9)
## A roof's outline and ridge (level.json "roofs", decision 364).
const ROOF := Color(0.85, 0.5, 0.3, 0.9)
const NOWHERE := Vector2i(-1, -1)
## The idle modes the panel offers; "" is the kind's own (Monster.idle_of).
const IDLE_CHOICES: Array[String] = ["", "guard", "wander", "patrol", "gather", "none"]

## Palette order: what the number keys pick, ten to a row.
const PALETTE: Array[String] = [
	"stone", "grass", "dirt", "water", "fire", "stair", "wall", "door", "clear", "void",
	"start", "monster_imp", "monster_brute", "monster_sneak", "crate", "boulder", "cart", "chest", "torch", "lantern",
	"link", "select", "area", "stamp", "path", "height", "stairs",
]
## Tools, not things to paint, and the key that picks each.
const TOOLS := {"select": "V", "area": "A", "stamp": "P", "path": "T", "height": "H", "stairs": "S"}
## The height tool's brush sizes (cells across).
const HEIGHT_BRUSHES: Array[int] = [1, 3, 5, 9]
const CLIFF := Color(0.05, 0.04, 0.03, 0.85)
const CLIMB := Color(1.0, 0.95, 0.5, 0.95)
## What the area panel can fill an area with (AreaTools).
const FILLS: Array[String] = ["pond", "grove", "scatter", "fence"]
const PATH_GROUNDS: Array[String] = ["dirt", "stone", "grass"]
const EDGE_BRUSHES: Array[String] = ["wall", "door", "clear"]
## A thing's letter on its cell.
const LETTERS := {"start": "S", "crate": "C", "boulder": "O", "cart": "K", "chest": "H", "torch": "T",
	"lantern": "L", "link": "→", "stair": "^", "monster_sneak": "N"}

var map_name := ""
## Where layout.png lives (res://levels/<map>/; tests use user://).
var folder := ""
## The level being edited: its map, level.json, undo, saving (MapDoc).
var doc: MapDoc
var map: LevelMap:
	get: return doc.map
	set(value): doc.map = value
var config: Dictionary:
	get: return doc.config
	set(value): doc.config = value
var dirty: bool:
	get: return doc.dirty
	set(value): doc.dirty = value
## The last load, save or change's report, shown in the status line.
var report: String:
	get: return doc.report if doc != null else ""
	set(value): doc.report = value
var _undo: Array[Dictionary]:
	get: return doc.undo_steps
var _redo: Array[Dictionary]:
	get: return doc.redo_steps
## What the palette offers: PALETTE, then level.json's own legend entries.
var palette: Array[String] = []
var brush := "stone"

## What the cursor is over: {"cell": Vector2i} or {"edge": Vector3i}, or {}.
var hover := {}
var _stroke: Dictionary = {}  # "cell"/"edge" key -> value before the stroke
var _stroke_button := MOUSE_BUTTON_NONE
var _stroke_from: Variant = null
var _panning := false
var _camera: Camera2D
var _status: Label
var _buttons: Dictionary[String, Button] = {}
## The select tool's monster (NOWHERE: none), and whether clicks now edit its
## route or set its gather point.
var selected := NOWHERE
var editing_route := false
var setting_point := false
## Each monster cell's name as the game will give it (for its own facing).
var _names: Dictionary[Vector2i, String] = {}
var _panel: VBoxContainer
var _canvas: PanelContainer
## The area tool's rectangle (size zero: none) and the cell a drag began on.
var area := Rect2i()
var _area_from := NOWHERE
## Where prefabs are read from and saved to (tests use user://).
var prefab_dir := Prefab.DIR
## The stamp tool's prefab ("" none), its turn, and it turned ({} none).
var stamp_name := ""
var stamp_turns := 0
var _stamp: Dictionary = {}
var _prefab_name: LineEdit
## The area tools' settings; the seed is shared.
var tool_seed := 1
var pond_shore := 1
var grove_density := 0.5
var grove_clearing := false
var scatter_density := 0.05
var scatter_things: Array[String] = ["boulder", "crate"]
var fence_gate := "south"
## The ridge a roof laid over the area runs along: "x", "z", or "" (along
## its long side).
var roof_ridge := ""
## The path tool's points, width and ground.
var path_points: Array[Vector2i] = []
var path_width := 2
var path_ground := "dirt"
## The last fill, and the undo depth just after it ("again" redoes it only
## while it is the last thing done).
var _last_fill := ""
var _last_fill_depth := -1
var _canvas_size: Label
## The height tool's brush (cells across) and the level Shift+click sets;
## the cells a stroke has changed (each once); the stairs tool's drag
## (NOWHERE: none); the heights tint shown with the other tools too.
var height_brush := 1
var height_level := 1
var _height_touched: Dictionary[Vector2i, bool] = {}
var _stairs_from := NOWHERE
var _stairs_to := NOWHERE
var show_heights := false
var _height_set := false


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
	doc = MapDoc.open(folder, Net.edit_size)
	doc.changed.connect(_on_doc_changed)
	palette = PALETTE.duplicate()
	selected = NOWHERE
	_name_cells()
	for meaning: String in map.colours:
		if meaning not in palette and meaning != "door" and meaning != "wall":
			palette.append(meaning)
	print("[editor] " + report)


## Writes layout.png and its .import (as Image), level.json and height.png
## if they changed (MapDoc.save). False if it could not.
func save() -> bool:
	var ok := doc.save()
	print("[editor] " + report)
	return ok


# --- Tools and strokes -----------------------------------------------------------

func pick(meaning: String) -> void:
	if meaning not in palette:
		return
	brush = meaning
	if meaning != "select":
		select(NOWHERE)
	if meaning != "area":
		area = Rect2i()
	_refresh_panel()
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
## point [param grid]; [param shift] and [param alt] held (the height tool's
## set and pick).
func begin_stroke(button: MouseButton, grid: Vector2, shift := false, alt := false) -> void:
	var cell := Vector2i(floori(grid.x), floori(grid.y))
	if brush == "height" and alt:
		if map.in_bounds(cell):
			_set_tool("height_level", maxi(1, int(map.heights.get(cell, 0))))
			report = "picked level %d (cell %d, %d is %d)" % [height_level, cell.x, cell.y, int(map.heights.get(cell, 0))]
		return
	if brush == "stairs":
		if button == MOUSE_BUTTON_LEFT and map.in_bounds(cell):
			_stairs_from = cell
			_stairs_to = cell
			_stroke_button = button
		queue_redraw()
		return
	if brush == "height":
		_height_touched.clear()
		_height_set = shift and button == MOUSE_BUTTON_LEFT
	if brush == "select":
		_select_click(button, cell)
		return
	if brush == "area":
		if button == MOUSE_BUTTON_RIGHT or not map.in_bounds(cell):
			area = Rect2i()
		else:
			_area_from = cell
			_stroke_button = button
			area = Rect2i(cell, Vector2i.ONE)
		_refresh_panel()
		queue_redraw()
		return
	if brush == "stamp":
		if button == MOUSE_BUTTON_LEFT:
			stamp_at(stamp_corner(grid))
		else:
			rotate_stamp(1)
		return
	if brush == "path":
		if button == MOUSE_BUTTON_LEFT and map.in_bounds(cell):
			path_points.append(cell)
		elif button == MOUSE_BUTTON_RIGHT and not path_points.is_empty():
			path_points.pop_back()
		_refresh_panel()
		queue_redraw()
		return
	_stroke = {}
	_stroke_button = button
	var target := target_at(grid)
	_stroke_from = target.get("cell", target.get("edge"))
	_apply(target)


## The stroke goes on to [param grid]: every cell on the line from the last
## one, or every edge along the first edge's line.
func continue_stroke(grid: Vector2) -> void:
	if _stairs_from != NOWHERE:
		var to := Vector2i(clampi(floori(grid.x), 0, map.size.x - 1), clampi(floori(grid.y), 0, map.size.y - 1))
		if to != _stairs_to:
			_stairs_to = to
			queue_redraw()
		return
	if _area_from != NOWHERE:
		var to := Vector2i(clampi(floori(grid.x), 0, map.size.x - 1), clampi(floori(grid.y), 0, map.size.y - 1))
		var corner := Vector2i(mini(to.x, _area_from.x), mini(to.y, _area_from.y))
		area = Rect2i(corner, (to - _area_from).abs() + Vector2i.ONE)
		_refresh_panel()
		queue_redraw()
		return
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
	_area_from = NOWHERE
	_stroke_button = MOUSE_BUTTON_NONE
	_stroke_from = null
	_height_touched.clear()
	if _stairs_from != NOWHERE:
		var from := _stairs_from
		_stairs_from = NOWHERE
		lay_stairs(from, _stairs_to)
		queue_redraw()
		return
	if _stroke.is_empty():
		return
	_name_cells()
	doc.push(_stroke)
	_stroke = {}


func _apply(target: Dictionary) -> void:
	var erase := _stroke_button == MOUSE_BUTTON_RIGHT
	if brush == "height":
		if target.has("cell"):
			_apply_height(target["cell"], erase)
		return
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
	doc.undo()


func redo() -> void:
	doc.redo()


## After any change to the level through its MapDoc: the names, the panel,
## the picture.
func _on_doc_changed() -> void:
	if selected != NOWHERE and not is_monster(selected):
		selected = NOWHERE
	_name_cells()
	_refresh_panel()
	queue_redraw()
	if _canvas_size != null:
		_canvas_size.text = "%d x %d cells" % [map.size.x, map.size.y]


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
## cells on those sides (negative shrinks it), as one undo step
## (MapDoc.resize). Returns what fell off ("" for nothing).
func resize(left: int, top: int, right: int, bottom: int) -> String:
	var before := map
	var lost := doc.resize(left, top, right, bottom)
	if map == before:
		return ""
	if _camera != null:
		_camera.position += Vector2(left, top) * CELL
	print("[editor] " + report)
	return lost


func toggle_canvas() -> void:
	if _canvas != null:
		_canvas.visible = not _canvas.visible


# --- Prefabs: save an area, stamp it ------------------------------------------------

## Saves the area as prefab [param text] (made a folder name). Returns the
## status it reports.
func save_prefab(text: String) -> String:
	var prefab_name := Prefab.tidy_name(text)
	if area.size == Vector2i.ZERO:
		report = "no area: drag one out with the area tool (A)"
	elif prefab_name.is_empty():
		report = "a prefab needs a name"
	else:
		var prefab := Prefab.extract(map, config, area)
		var error := Prefab.save(prefab_name, prefab, prefab_dir)
		if error == OK:
			report = "saved prefab %s (%d x %d cells, %d things)" % [prefab_name, area.size.x, area.size.y,
				(prefab["config"].get("entities", []) as Array).size()]
		else:
			report = "could not save prefab %s (%s)" % [prefab_name, error_string(error)]
	print("[editor] " + report)
	_refresh_panel()
	return report


## Picks prefab [param prefab_name] to stamp ("" none).
func pick_stamp(prefab_name: String) -> void:
	stamp_name = prefab_name
	_stamp = {}
	if not prefab_name.is_empty():
		var prefab := Prefab.load_prefab(prefab_name, prefab_dir)
		if prefab.is_empty():
			report = "no prefab %s" % prefab_name
			stamp_name = ""
		else:
			_stamp = Prefab.rotated(prefab, stamp_turns)
	_refresh_panel()
	queue_redraw()


## Turns the stamp [param steps] quarter turns clockwise.
func rotate_stamp(steps: int) -> void:
	stamp_turns = posmod(stamp_turns + steps, 4)
	pick_stamp(stamp_name)


## Where the stamp's top-left goes with the cursor at [param grid]: the
## cursor at its middle.
func stamp_corner(grid: Vector2) -> Vector2i:
	if _stamp.is_empty():
		return Vector2i(floori(grid.x), floori(grid.y))
	var size: Vector2i = (_stamp["map"] as LevelMap).size
	return Vector2i(floori(grid.x - size.x / 2.0 + 0.5), floori(grid.y - size.y / 2.0 + 0.5))


## Lays the picked prefab with its top-left at [param at], as one undo step.
func stamp_at(at: Vector2i) -> void:
	if _stamp.is_empty():
		return
	if apply_changes(Prefab.stamp_changes(_stamp, map, at, doc.config)):
		report = "stamped %s at %d, %d" % [stamp_name, at.x, at.y]


## Makes [param changes] as one undo step (MapDoc.apply_changes).
func apply_changes(changes: Dictionary) -> bool:
	return doc.apply_changes(changes)


# --- Area tools ---------------------------------------------------------------------

## What filling the area with [param fill] ("pond", "grove", "scatter",
## "fence") would change, with the settings as they are.
func fill_changes(fill: String) -> Dictionary:
	match fill:
		"pond":
			return AreaTools.pond(map, area, tool_seed, pond_shore)
		"grove":
			return AreaTools.grove(map, area, tool_seed, grove_density, grove_clearing)
		"scatter":
			return AreaTools.scatter(map, area, tool_seed, scatter_things, scatter_density)
		"fence":
			return AreaTools.fence(map, area, fence_gate)
	return {}


## Fills the area with [param fill], as one undo step.
func fill_area(fill: String) -> void:
	if area.size == Vector2i.ZERO:
		return
	var changed := apply_changes(fill_changes(fill))
	_last_fill = fill if changed else ""
	_last_fill_depth = _undo.size()
	report = "%s in %d x %d at %d, %d, seed %d%s" % [fill, area.size.x, area.size.y, area.position.x, area.position.y,
		tool_seed, "" if changed else ": nothing to change"]
	_refresh_panel()


## Roofs the area (level.json "roofs", decision 364) in the first roof set,
## its ridge roof_ridge, replacing any roof over its cells; [param remove]
## takes those away instead. One undo step; none if Level would leave the
## roof out (its warning in the report).
func roof_area(remove := false) -> void:
	if area.size == Vector2i.ZERO:
		return
	var old: Array = (doc.config["roofs"] as Array).duplicate(true) if doc.config.get("roofs") is Array else []
	var roofs := old.filter(func(entry: Variant) -> bool:
		var at: Variant = Level.town_wall_rect(entry)
		return at == null or not (at as Rect2i).intersects(area))
	var gone := old.size() - roofs.size()
	if remove:
		if gone > 0:
			apply_changes({"config": {"roofs": roofs}})
		report = "took away %d roofs" % gone
		_refresh_panel()
		return
	var entry := {"rect": [area.position.x, area.position.y, area.size.x, area.size.y], "set": Level.ROOF_SETS[0]}
	if roof_ridge in ["x", "z"]:
		entry["ridge"] = roof_ridge
	roofs.append(entry)
	apply_changes({"config": {"roofs": roofs}})
	var level := doc.parsed()
	if not (level["roofs"] as Array).any(func(roof: Dictionary) -> bool: return roof["rect"] == area):
		undo()
		var at := "the roof at %s" % [area.position]
		report = "no roof: " + "; ".join((level["warnings"] as Array).filter(func(warning: String) -> bool: return warning.begins_with(at)))
	else:
		report = "a roof over %d x %d at %d, %d%s" % [area.size.x, area.size.y, area.position.x, area.position.y,
			" (replacing %d)" % gone if gone > 0 else ""]
	_refresh_panel()


## The last fill taken back and laid again with the next seed.
func fill_again() -> void:
	if _last_fill.is_empty() or _undo.size() != _last_fill_depth:
		return
	undo()
	tool_seed += 1
	fill_area(_last_fill)


## Lays the path through the points clicked, as one undo step, and starts a new one.
func lay_path() -> void:
	if path_points.is_empty():
		return
	var changed := apply_changes(AreaTools.path(map, path_points, tool_seed, path_width, path_ground))
	report = "a path of %s, %d wide, through %d points%s" % [path_ground, path_width, path_points.size(),
		"" if changed else ": nothing to change"]
	path_points.clear()
	_refresh_panel()
	queue_redraw()


# --- Heights (HeightTools) -----------------------------------------------------------

## The cells under the height brush centred on [param at], in the map.
func height_footprint(at: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var reach := height_brush / 2
	for y in range(at.y - reach, at.y + reach + 1):
		for x in range(at.x - reach, at.x + reach + 1):
			if map.in_bounds(Vector2i(x, y)):
				out.append(Vector2i(x, y))
	return out


## The height stroke reaches [param at]: the cells under the brush it has
## not changed yet go up a level (down with [param lower], to the picked
## level with Shift), into the stroke's undo step.
func _apply_height(at: Vector2i, lower: bool) -> void:
	var fresh: Array[Vector2i] = []
	for cell in height_footprint(at):
		if not _height_touched.has(cell):
			_height_touched[cell] = true
			fresh.append(cell)
	if fresh.is_empty():
		return
	var changes := HeightTools.level(map, fresh, height_level) if _height_set else HeightTools.raise(map, fresh, -1 if lower else 1)
	var heights: Dictionary = changes.get("heights", {})
	for cell: Vector2i in heights:
		var key := "height %d %d" % [cell.x, cell.y]
		var old := doc.set_height(cell, int(heights[cell]))
		if old != int(heights[cell]) and not _stroke.has(key):
			_stroke[key] = old
	queue_redraw()


## A stair from [param from] climbing toward [param to] (the drag's main
## way), or a flight of them when it is more than a cell, as one undo step.
func lay_stairs(from: Vector2i, to: Vector2i) -> bool:
	var along := to - from
	if along == Vector2i.ZERO:
		return false
	along = Vector2i(along.x, 0) if absi(along.x) >= absi(along.y) else Vector2i(0, along.y)
	var dir := along.sign()
	var length := absi(along.x + along.y)
	var changes := HeightTools.stair(map, from, dir) if length == 1 else HeightTools.flight(map, from, from + along)
	var reason := str(changes.get("reason", ""))
	if not reason.is_empty():
		report = "no stair from %d, %d: %s" % [from.x, from.y, reason]
		return false
	var changed := apply_changes(changes)
	report = "%s from %d, %d climbing %s%s" % ["a stair" if length == 1 else "a flight of %d" % length, from.x, from.y,
		World.COMPASS[Monster.AROUND.find(dir)], "" if changed else ": nothing to change"]
	return changed


## The area's heights: raised [param by] levels (lowered if negative).
func raise_area(by: int) -> void:
	_area_heights(HeightTools.raise(map, _area_cells(), by), "raised %d" % by if by > 0 else "lowered %d" % -by)


## The area levelled at the picked level.
func level_area() -> void:
	_area_heights(HeightTools.level(map, _area_cells(), height_level), "levelled at %d" % height_level)


## A hill filling the area, its top the picked level at the middle.
func hill_area() -> void:
	var centre := area.position + area.size / 2
	var radius := maxi(1, mini(area.size.x, area.size.y) / 2)
	_area_heights(HeightTools.hill(map, centre, radius, height_level), "a hill to level %d" % height_level)


func _area_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			out.append(Vector2i(x, y))
	return out


func _area_heights(changes: Dictionary, what: String) -> void:
	if area.size == Vector2i.ZERO:
		return
	var reason := str(changes.get("reason", ""))
	var changed := reason.is_empty() and apply_changes(changes)
	report = "%d x %d at %d, %d %s%s" % [area.size.x, area.size.y, area.position.x, area.position.y, what,
		"" if changed else ": " + (reason if not reason.is_empty() else "nothing to change")]
	_refresh_panel()


func toggle_heights() -> void:
	show_heights = not show_heights
	queue_redraw()


## Whether the heights tint is drawn.
func heights_shown() -> bool:
	return show_heights or brush in ["height", "stairs"]


func _set_tool(setting: String, value: Variant) -> void:
	set(setting, value)
	_refresh_panel()


## level.json's link on [param at] ({} for none).
func link_of(at: Vector2i) -> Dictionary:
	return doc.link_of(at)


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
	return doc.entry_of(at)


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
	doc.put_entry(selected, entry)
	doc.push({"entry %d %d" % [selected.x, selected.y]: before})
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
	var mode: int = Monster.idle_of(kind)
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
	_panel.get_parent().visible = selected != NOWHERE or brush in ["area", "stamp", "path", "height", "stairs"]
	if brush == "area":
		_area_panel()
		return
	if brush == "height":
		_height_panel()
		return
	if brush == "stairs":
		_panel_label("Stairs", 30)
		_panel_label("press on the low cell, drag the way it climbs:\none cell a stair, more a flight (a level a cell)", 22)
		return
	if brush == "stamp":
		_stamp_panel()
		return
	if brush == "path":
		_path_panel()
		return
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


## The level's roofs (level.json "roofs"): each outlined, its ridge a line
## down its middle the way it runs.
func _draw_roofs() -> void:
	for entry: Variant in doc.config.get("roofs", []) if doc.config.get("roofs") is Array else []:
		var at: Variant = Level.town_wall_rect(entry)
		if at == null:
			continue
		var rect := Rect2(Vector2((at as Rect2i).position) * CELL, Vector2((at as Rect2i).size) * CELL)
		draw_rect(rect.grow(-CELL * 0.1), ROOF, false, 3.0)
		var ridge := str(entry.get("ridge", "x" if rect.size.x > rect.size.y else "z"))
		var middle := rect.get_center()
		var half := Vector2(rect.size.x * 0.5 - CELL * 0.1, 0.0) if ridge == "x" else Vector2(0.0, rect.size.y * 0.5 - CELL * 0.1)
		draw_line(middle - half, middle + half, ROOF, 3.0)


## The area tool's panel: the area, and a name to save it under as a prefab.
func _area_panel() -> void:
	_panel_label("Area", 30)
	if area.size == Vector2i.ZERO:
		_panel_label("drag out a rectangle; right click lets go", 22)
		return
	_panel_label("%d x %d cells at %d, %d" % [area.size.x, area.size.y, area.position.x, area.position.y], 22)
	var row := HBoxContainer.new()
	_panel.add_child(row)
	var typed := _prefab_name.text if _prefab_name != null and is_instance_valid(_prefab_name) else ""
	_prefab_name = LineEdit.new()
	_prefab_name.placeholder_text = "prefab name"
	_prefab_name.text = typed
	_prefab_name.custom_minimum_size = Vector2(360, 0)
	_prefab_name.add_theme_font_size_override("font_size", 22)
	_prefab_name.text_submitted.connect(func(text: String) -> void: save_prefab(text))
	row.add_child(_prefab_name)
	_panel_button(row, "save as prefab", func() -> void: save_prefab(_prefab_name.text))
	_panel_label("Fill it with", 26)
	var fills := HBoxContainer.new()
	_panel.add_child(fills)
	for fill in FILLS:
		_panel_button(fills, fill, fill_area.bind(fill))
	var again := _panel_button(fills, "again, next seed", fill_again)
	again.disabled = _last_fill.is_empty() or _undo.size() != _last_fill_depth
	_seed_row()
	var pond_row := HBoxContainer.new()
	_panel.add_child(pond_row)
	_panel_label_in(pond_row, "pond: shore %d" % pond_shore)
	_panel_button(pond_row, "-", _set_tool.bind("pond_shore", maxi(0, pond_shore - 1)))
	_panel_button(pond_row, "+", _set_tool.bind("pond_shore", mini(4, pond_shore + 1)))
	var grove_row := HBoxContainer.new()
	_panel.add_child(grove_row)
	_panel_label_in(grove_row, "grove: %d%%" % roundi(grove_density * 100))
	_panel_button(grove_row, "-", _set_tool.bind("grove_density", maxf(0.1, snappedf(grove_density - 0.1, 0.1))))
	_panel_button(grove_row, "+", _set_tool.bind("grove_density", minf(1.0, snappedf(grove_density + 0.1, 0.1))))
	var clearing := _panel_button(grove_row, "clearing", _set_tool.bind("grove_clearing", not grove_clearing))
	clearing.toggle_mode = true
	clearing.button_pressed = grove_clearing
	var scatter_row := HBoxContainer.new()
	_panel.add_child(scatter_row)
	_panel_label_in(scatter_row, "scatter: %d%%" % roundi(scatter_density * 100))
	_panel_button(scatter_row, "-", _set_tool.bind("scatter_density", maxf(0.01, snappedf(scatter_density - 0.01, 0.01))))
	_panel_button(scatter_row, "+", _set_tool.bind("scatter_density", minf(0.3, snappedf(scatter_density + 0.01, 0.01))))
	for thing in AreaTools.SCATTER_THINGS:
		var others := scatter_things.duplicate()
		if thing in others:
			others.erase(thing)
		else:
			others.append(thing)
		var toggle := _panel_button(scatter_row, thing, _set_tool.bind("scatter_things", others))
		toggle.toggle_mode = true
		toggle.button_pressed = thing in scatter_things
	var fence_row := HBoxContainer.new()
	_panel.add_child(fence_row)
	_panel_label_in(fence_row, "fence: gate")
	for side: String in ["north", "east", "south", "west", ""]:
		var gate := _panel_button(fence_row, side if not side.is_empty() else "none", _set_tool.bind("fence_gate", side))
		gate.toggle_mode = true
		gate.button_pressed = side == fence_gate
	var roof_row := HBoxContainer.new()
	_panel.add_child(roof_row)
	_panel_label_in(roof_row, "roof: ridge")
	for ridge: String in ["", "x", "z"]:
		var along := _panel_button(roof_row, ridge if not ridge.is_empty() else "long side", _set_tool.bind("roof_ridge", ridge))
		along.toggle_mode = true
		along.button_pressed = ridge == roof_ridge
	_panel_button(roof_row, "roof it", roof_area)
	_panel_button(roof_row, "take roofs off", roof_area.bind(true))
	_panel_label("Heights", 26)
	var heights_row := HBoxContainer.new()
	_panel.add_child(heights_row)
	_panel_button(heights_row, "raise", raise_area.bind(1))
	_panel_button(heights_row, "lower", raise_area.bind(-1))
	_panel_button(heights_row, "level", level_area)
	_panel_button(heights_row, "hill", hill_area)
	_height_level_row()


## The height tool's panel: its brush and the level Shift+click sets.
func _height_panel() -> void:
	_panel_label("Height", 30)
	_panel_label("LMB raise  RMB lower  Shift+LMB set  Alt+LMB pick", 22)
	var row := HBoxContainer.new()
	_panel.add_child(row)
	_panel_label_in(row, "brush")
	for size in HEIGHT_BRUSHES:
		var button := _panel_button(row, "%dx%d" % [size, size], _set_tool.bind("height_brush", size))
		button.toggle_mode = true
		button.button_pressed = size == height_brush
	_panel_label_in(row, "[ ]")
	_height_level_row()


## The picked level, to change by hand.
func _height_level_row() -> void:
	var row := HBoxContainer.new()
	_panel.add_child(row)
	_panel_label_in(row, "level %d" % height_level)
	_panel_button(row, "-", _set_tool.bind("height_level", maxi(1, height_level - 1)))
	_panel_button(row, "+", _set_tool.bind("height_level", mini(Level.MAX_HEIGHT, height_level + 1)))


## The seed the area and path tools use, to change by hand.
func _seed_row() -> void:
	var row := HBoxContainer.new()
	_panel.add_child(row)
	_panel_label_in(row, "seed %d" % tool_seed)
	_panel_button(row, "-", _set_tool.bind("tool_seed", tool_seed - 1))
	_panel_button(row, "+", _set_tool.bind("tool_seed", tool_seed + 1))


## The path tool's panel: its points, width, ground and seed.
func _path_panel() -> void:
	_panel_label("Path", 30)
	_panel_label("%d points: click adds one, right click takes the last back" % path_points.size(), 22)
	var row := HBoxContainer.new()
	_panel.add_child(row)
	_panel_label_in(row, "width %d   [ ]" % path_width)
	_panel_button(row, "-", _set_tool.bind("path_width", maxi(1, path_width - 1)))
	_panel_button(row, "+", _set_tool.bind("path_width", mini(6, path_width + 1)))
	for ground in PATH_GROUNDS:
		var button := _panel_button(row, ground, _set_tool.bind("path_ground", ground))
		button.toggle_mode = true
		button.button_pressed = ground == path_ground
	_seed_row()
	var lay := HBoxContainer.new()
	_panel.add_child(lay)
	_panel_button(lay, "lay it (Enter)", lay_path)
	_panel_button(lay, "clear (Esc)", func() -> void:
		path_points.clear()
		_refresh_panel()
		queue_redraw())


## The stamp tool's panel: every prefab, the one picked lit, and its turn.
func _stamp_panel() -> void:
	_panel_label("Stamp a prefab", 30)
	var names := Prefab.names(prefab_dir) + Prefab.kind_names()
	if names.is_empty():
		_panel_label("none yet: save one with the area tool (A)", 22)
	for each in names:
		var button := _panel_button(_panel, each, pick_stamp.bind(each))
		button.toggle_mode = true
		button.button_pressed = each == stamp_name
	_panel_label("R / right click turns it (%d degrees), click lays it" % (stamp_turns * 90), 22)


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
		elif key.keycode == KEY_A and not key.ctrl_pressed:
			pick("area")
		elif key.keycode == KEY_P and not key.ctrl_pressed:
			pick("stamp")
		elif key.keycode == KEY_T and not key.ctrl_pressed:
			pick("path")
		elif key.keycode == KEY_H and key.ctrl_pressed:
			toggle_heights()
		elif key.keycode == KEY_H:
			pick("height")
		elif key.keycode == KEY_S:
			pick("stairs")
		elif brush == "height" and key.keycode in [KEY_BRACKETLEFT, KEY_BRACKETRIGHT]:
			var index := clampi(HEIGHT_BRUSHES.find(height_brush) + (1 if key.keycode == KEY_BRACKETRIGHT else -1), 0, HEIGHT_BRUSHES.size() - 1)
			_set_tool("height_brush", HEIGHT_BRUSHES[index])
		elif brush == "path" and key.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			lay_path()
		elif brush == "path" and key.keycode == KEY_ESCAPE:
			path_points.clear()
			_refresh_panel()
			queue_redraw()
		elif brush == "path" and key.keycode in [KEY_BRACKETLEFT, KEY_BRACKETRIGHT]:
			_set_tool("path_width", clampi(path_width + (1 if key.keycode == KEY_BRACKETRIGHT else -1), 1, 6))
		elif key.keycode == KEY_R and not key.ctrl_pressed and brush == "stamp":
			rotate_stamp(-1 if key.shift_pressed else 1)
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
				begin_stroke(button.button_index, _mouse_grid(), button.shift_pressed, button.alt_pressed)
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
		over = "cell %d, %d: %s, level %d" % [at.x, at.y, map.cell(at), int(map.heights.get(at, 0))]
	elif hover.has("edge"):
		var key: Vector3i = hover["edge"]
		over = "edge %s of %d, %d: %s" % ["east" if key.z == Terrain.EAST else "south", key.x, key.y, map.edge(key)]
	var tools := "LMB paint  RMB erase  1-0 / Shift / Alt pick  V select  A area  P stamp  T path  H height  S stairs  Ctrl+H levels"
	if brush == "select":
		tools = "LMB pick a monster  Q / E turn it  Esc let go" if not editing_route \
				else "LMB add a waypoint  RMB take the last back  Esc done"
		if setting_point:
			tools = "LMB the gather point  Esc never mind"
	elif brush == "area":
		tools = "LMB drag an area  RMB let go  (fill it or save it as a prefab in the panel)"
	elif brush == "stamp":
		tools = "LMB lay %s  R / RMB turn it" % (stamp_name if not stamp_name.is_empty() else "(pick a prefab)")
	elif brush == "path":
		tools = "LMB add a point  RMB take the last back  Enter lay the path  [ ] width  Esc clear"
	elif brush == "height":
		tools = "LMB raise  RMB lower  Shift+LMB set to %d  Alt+LMB pick  [ ] brush %dx%d" % [height_level, height_brush, height_brush]
	elif brush == "stairs":
		tools = "LMB on the low cell, drag the way it climbs (one cell a stair, more a flight)"
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
	if heights_shown():
		_draw_heights()
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
	_draw_roofs()
	_draw_monsters()
	if area.size != Vector2i.ZERO:
		var rect := Rect2(Vector2(area.position) * CELL, Vector2(area.size) * CELL)
		draw_rect(rect, Color(AREA, 0.12))
		draw_rect(rect, AREA, false, 4.0)
	if brush == "stamp" and not _stamp.is_empty():
		_draw_ghost(stamp_corner(_mouse_grid()))
	if brush == "path":
		for i in path_points.size():
			var centre := (Vector2(path_points[i]) + Vector2(0.5, 0.5)) * CELL
			if i > 0:
				draw_line((Vector2(path_points[i - 1]) + Vector2(0.5, 0.5)) * CELL, centre, AREA, 4.0)
			draw_circle(centre, CELL * 0.2, AREA)
	if _stairs_from != NOWHERE:
		var along := _stairs_to - _stairs_from
		along = Vector2i(along.x, 0) if absi(along.x) >= absi(along.y) else Vector2i(0, along.y)
		var a := (Vector2(_stairs_from) + Vector2(0.5, 0.5)) * CELL
		draw_line(a, a + Vector2(along) * CELL, CLIMB, 6.0)
		draw_circle(a, CELL * 0.18, CLIMB)
	if hover.has("cell") and brush == "height":
		for cell in height_footprint(hover["cell"]):
			draw_rect(Rect2(Vector2(cell) * CELL, Vector2.ONE * CELL), Color(HOVER, 0.5), false, 2.0)
	if hover.has("cell"):
		draw_rect(Rect2(Vector2(hover["cell"]) * CELL, Vector2.ONE * CELL), HOVER, false, 4.0)
	elif hover.has("edge"):
		_draw_edge(hover["edge"], HOVER, 10.0)
	draw_rect(Rect2(Vector2.ZERO, Vector2(map.size) * CELL), Color(1, 1, 1, 0.3), false, 2.0)


## Each cell tinted by its level (darker at 0, lighter each level up), its
## level written on it when big enough to read, cliffs heavier the higher
## they are, and each stair's climb (as Level.parse finds it; red: none).
func _draw_heights() -> void:
	var font := ThemeDB.fallback_font
	var numbers := _camera == null or _camera.zoom.x * CELL >= 26.0
	for at: Vector2i in map.cells:
		var level := int(map.heights.get(at, 0))
		var rect := Rect2(Vector2(at) * CELL, Vector2.ONE * CELL)
		draw_rect(rect, Color(0, 0, 0, 0.22) if level == 0 else Color(1, 1, 1, 0.05 + 0.07 * level))
		if numbers and level > 0:
			draw_string(font, rect.position + Vector2(CELL * 0.06, CELL * 0.3), str(level), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0, 0, 0, 0.75))
		for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			var next := at + step
			if map.cell(next) == "void":
				continue
			var rise := absi(int(map.heights.get(next, 0)) - level)
			if rise > 0:
				var key := Terrain.edge_key(at, step)
				var a := Vector2(key.x + 1, key.y) if key.z == Terrain.EAST else Vector2(key.x, key.y + 1)
				var b := a + (Vector2(0, 1) if key.z == Terrain.EAST else Vector2(1, 0))
				draw_line(a * CELL, b * CELL, CLIFF, 2.0 + 2.0 * rise)
	for at: Vector2i in map.cells:
		if map.cell(at) != "stair":
			continue
		var centre := (Vector2(at) + Vector2(0.5, 0.5)) * CELL
		var climb := HeightTools.climbs(map, at)
		if climb == Vector2i.ZERO:
			draw_circle(centre, CELL * 0.2, Color(1, 0.2, 0.2, 0.9))
			continue
		var tip := centre + Vector2(climb) * CELL * 0.42
		draw_line(centre - Vector2(climb) * CELL * 0.3, tip, CLIMB, 4.0)
		var side := Vector2(climb).orthogonal() * CELL * 0.14
		draw_colored_polygon(PackedVector2Array([tip + Vector2(climb) * CELL * 0.06, tip - Vector2(climb) * CELL * 0.16 + side,
			tip - Vector2(climb) * CELL * 0.16 - side]), CLIMB)


## The picked prefab, see-through, with its top-left at [param at].
func _draw_ghost(at: Vector2i) -> void:
	var piece: LevelMap = _stamp["map"]
	for cell: Vector2i in piece.cells:
		var meaning: String = piece.cells[cell]
		var rect := Rect2(Vector2(cell + at) * CELL, Vector2.ONE * CELL)
		draw_rect(rect, Color(map.colours.get(meaning, Color.MAGENTA), 0.55))
		if meaning not in Level.GROUNDS and meaning not in ["water", "fire"]:
			var letter: String = LETTERS.get(meaning, meaning.trim_prefix("monster_").left(1).to_upper())
			draw_string(ThemeDB.fallback_font, rect.position + Vector2(0, CELL * 0.68), letter, HORIZONTAL_ALIGNMENT_CENTER, CELL, 26, Color(0, 0, 0, 0.7))
	for key: Vector3i in piece.edges:
		_draw_edge(key + Vector3i(at.x, at.y, 0), Color(WALL if piece.edges[key] == "wall" else DOOR, 0.7), 8.0, piece.edges[key] == "door")
	draw_rect(Rect2(Vector2(at) * CELL, Vector2(piece.size) * CELL), AREA, false, 3.0)


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
		button.text = "%s  %s" % [TOOLS[meaning] + "   " if TOOLS.has(meaning) else key_name(i),
			meaning.trim_prefix("monster_") + (" (edge)" if meaning in EDGE_BRUSHES else " (a monster)" if meaning == "select"
				else " (fill, prefab)" if meaning == "area" else " (a prefab)" if meaning == "stamp"
				else " (through points)" if meaning == "path" else " (raise, lower)" if meaning == "height"
				else " (a stair, a flight)" if meaning == "stairs" else "")]
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
	var colour: Color = map.colours.get(meaning, Color.WHITE) if meaning not in ["clear", "select", "height"] else Color(0, 0, 0, 0)
	if meaning == "wall":
		colour = WALL
	image.fill(colour)
	if meaning == "clear":
		for i in 36:
			image.set_pixel(i, i, Color.WHITE)
	return ImageTexture.create_from_image(image)
