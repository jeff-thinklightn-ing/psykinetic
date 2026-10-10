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
## Saving writes the same double-resolution layout.png (LevelMap.to_image)
## and its .import as Image, and says what the game will warn about
## (Level.parse). height.png and level.json are left as they are.

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

## Palette order: what the number keys pick, ten to a row.
const PALETTE: Array[String] = [
	"stone", "grass", "dirt", "water", "fire", "stair", "wall", "door", "clear", "void",
	"start", "monster_imp", "monster_brute", "monster_sneak", "crate", "boulder", "cart", "chest", "torch", "lantern",
	"link",
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
		report = "loaded %s: %d x %d cells%s" % [png, map.size.x, map.size.y,
			", %d pixels of colours not in the legend (void when saved)" % map.unknown_pixels if map.unknown_pixels > 0 else ""]
	else:
		map = LevelMap.new(Net.edit_size, config)
		report = "new map %s: %d x %d cells (not saved yet)" % [map_name, map.size.x, map.size.y]
	palette = PALETTE.duplicate()
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
	dirty = false
	var level := Level.parse(image, null, config)
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
		else:
			back[key] = map.set_edge(key, stroke[key])
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
	return "%s%s   %s   brush: %s   |   LMB paint  RMB erase  1-0 / Shift / Alt pick  Ctrl+S save  Ctrl+Z undo  Ctrl+Y redo  MMB / arrows pan  wheel zoom\n%s" % [
		map_name, " (unsaved)" if dirty else "", over, brush, report]


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
		button.text = "%s  %s" % [key_name(i), meaning.trim_prefix("monster_") + (" (edge)" if meaning in EDGE_BRUSHES else "")]
		button.icon = _swatch(meaning)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(pick.bind(meaning))
		list.add_child(button)
		_buttons[meaning] = button
	_status = Label.new()
	_status.position = Vector2(30, 20)
	_status.add_theme_font_size_override("font_size", FONT_SIZE)
	_status.add_theme_color_override("font_color", Color(0.93, 0.92, 0.88))
	layer.add_child(_status)


## The key that picks palette entry [param index]: "1" .. "0", "Shift+1" ..
## "Alt+1" ..; "" past the thirtieth.
static func key_name(index: int) -> String:
	if index >= 30:
		return "    "
	var digit := str((index % 10 + 1) % 10)
	return ["", "Shift+", "Alt+"][index / 10] + digit


func _swatch(meaning: String) -> Texture2D:
	var image := Image.create(36, 36, false, Image.FORMAT_RGBA8)
	var colour: Color = map.colours.get(meaning, Color.WHITE) if meaning != "clear" else Color(0, 0, 0, 0)
	if meaning == "wall":
		colour = WALL
	image.fill(colour)
	if meaning == "clear":
		for i in 36:
			image.set_pixel(i, i, Color.WHITE)
	return ImageTexture.create_from_image(image)
