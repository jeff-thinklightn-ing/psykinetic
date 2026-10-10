extends Node
## The level editor: a map read from layout.png and written back plays the
## same (every level in levels/); painting cells and lines of cells, setting
## edges and runs of them, erasing, undo and redo, the keys, and a save that
## the game reads as painted, with its .import as Image.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const FOLDER := "user://editor_test/"

var _failures := 0


func _ready() -> void:
	World.set_process(false)
	_clear()
	_test_round_trip()
	await _test_painting()
	_test_import_file()
	_clear()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_round_trip() -> void:
	print("\n== every level read into the editor and written back plays the same ==")
	for folder in DirAccess.get_directories_at(Level.DIR):
		var config := {}
		var json := Level.DIR + folder + "/level.json"
		if FileAccess.file_exists(json):
			config = JSON.parse_string(FileAccess.get_file_as_string(json))
		var image := Image.load_from_file(ProjectSettings.globalize_path(Level.DIR + folder + "/layout.png"))
		var map := LevelMap.from_image(image, config)
		var written := map.to_image()
		var before := Level.parse(image, null, config)
		var after := Level.parse(written, null, config)
		_check(written.get_size() == image.get_size(), "%s: the same size (%s)" % [folder, written.get_size()])
		var same := true
		for key: String in ["floor", "fire", "water", "torches", "lanterns", "kinds", "stairs"]:
			if str(before["terrain"][key]) != str(after["terrain"][key]):
				same = false
				print("    %s differs" % key)
		_check(same and before["terrain"]["edges"] == after["terrain"]["edges"],
				"%s: the same cells, walls and doors (%d floor, %d edges)" % [folder, before["terrain"]["floor"].size(), before["terrain"]["edges"].size()])
		_check(str(before["entities"]) == str(after["entities"]) and before["starts"] == after["starts"] and str(before["links"]) == str(after["links"]),
				"%s: the same things, starts and links (%d things)" % [folder, before["entities"].size()])
		_check(map.unknown_pixels == 0, "%s: every colour is in the legend" % folder)


func _test_painting() -> void:
	print("\n== painting a new map ==")
	Net.edit_size = Vector2i(8, 6)
	var editor: LevelEditor = preload("res://editor/level_editor.tscn").instantiate()
	editor.map_name = "editor_test"
	editor.folder = FOLDER
	add_child(editor)
	await get_tree().process_frame
	_check(editor.map.size == Vector2i(8, 6) and editor.map.cells.is_empty(), "a new map: 8 x 6 cells, all void")
	_check(editor.palette.size() >= 21 and "monster_imp" in editor.palette and "chest" in editor.palette and "wall" in editor.palette,
			"the palette has every terrain, thing and edge (%d)" % editor.palette.size())

	_key(editor, KEY_1)
	_check(editor.brush == "stone", "1 picks stone")
	editor.begin_stroke(MOUSE_BUTTON_LEFT, Vector2(1.5, 1.5))
	editor.continue_stroke(Vector2(5.5, 1.5))
	editor.end_stroke()
	_check(range(1, 6).all(func(x: int) -> bool: return editor.map.cell(Vector2i(x, 1)) == "stone") and editor.map.cells.size() == 5,
			"a drag paints the row from (1, 1) to (5, 1)")
	editor.begin_stroke(MOUSE_BUTTON_LEFT, Vector2(1.5, 2.5))
	editor.continue_stroke(Vector2(4.5, 4.5))
	editor.end_stroke()
	_check(editor.map.cell(Vector2i(1, 2)) == "stone" and editor.map.cell(Vector2i(4, 4)) == "stone" and editor.map.cells.size() == 9,
			"a diagonal drag paints the cells along the line (%d)" % editor.map.cells.size())
	editor.undo()
	_check(editor.map.cells.size() == 5, "Ctrl+Z takes the last stroke back")
	editor.redo()
	_check(editor.map.cells.size() == 9, "and redo puts it back")
	_key(editor, KEY_Z, true)
	_check(editor.map.cells.size() == 5, "Ctrl+Z, from the keyboard")

	_key(editor, KEY_1, false, true)
	_check(editor.brush == "start", "Shift+1 picks a player start")
	editor.begin_stroke(MOUSE_BUTTON_LEFT, Vector2(1.2, 1.8))
	editor.end_stroke()
	_key(editor, KEY_5, false, true)
	editor.begin_stroke(MOUSE_BUTTON_LEFT, Vector2(3.5, 1.5))
	editor.end_stroke()
	_key(editor, KEY_1, false, false, true)
	_check(editor.brush == "link", "Alt+1 picks a level link")
	_check(editor.map.cell(Vector2i(1, 1)) == "start" and editor.map.cell(Vector2i(3, 1)) == "crate", "a start and a crate painted on")

	print("\n== edges ==")
	_key(editor, KEY_7)
	_check(editor.brush == "wall" and editor.is_edge_brush(), "7 picks wall, an edge")
	_check(editor.target_at(Vector2(2.92, 1.5)) == {"edge": Vector3i(2, 1, Terrain.EAST)}, "near the line east of (2, 1): that edge")
	_check(editor.target_at(Vector2(2.08, 1.5)) == {"edge": Vector3i(1, 1, Terrain.EAST)}, "near the line west of it: the edge east of (1, 1)")
	_check(editor.target_at(Vector2(2.5, 1.95)) == {"edge": Vector3i(2, 1, Terrain.SOUTH)}, "near the line below: the edge south of it")
	_check(editor.target_at(Vector2(7.95, 1.5)).is_empty(), "the map's own border is no edge to set")
	editor.begin_stroke(MOUSE_BUTTON_LEFT, Vector2(2.95, 0.5))
	editor.continue_stroke(Vector2(3.4, 3.5))
	editor.end_stroke()
	_check(range(0, 4).all(func(y: int) -> bool: return editor.map.edge(Vector3i(2, y, Terrain.EAST)) == "wall") and editor.map.edges.size() == 4,
			"a drag sets a straight run of walls down that line, wherever the cursor wanders (%d)" % editor.map.edges.size())
	_key(editor, KEY_8)
	editor.begin_stroke(MOUSE_BUTTON_LEFT, Vector2(2.95, 1.5))
	editor.end_stroke()
	_check(editor.map.edge(Vector3i(2, 1, Terrain.EAST)) == "door", "8 and a click: a door in it")
	editor.begin_stroke(MOUSE_BUTTON_RIGHT, Vector2(2.95, 3.5))
	editor.end_stroke()
	_check(editor.map.edge(Vector3i(2, 3, Terrain.EAST)) == "clear", "a right click clears an edge")
	_key(editor, KEY_9)
	editor.begin_stroke(MOUSE_BUTTON_LEFT, Vector2(2.95, 2.5))
	editor.end_stroke()
	_check(editor.map.edge(Vector3i(2, 2, Terrain.EAST)) == "clear", "and so does clear")
	_key(editor, KEY_1)
	editor.begin_stroke(MOUSE_BUTTON_RIGHT, Vector2(5.5, 1.5))
	editor.end_stroke()
	_check(editor.map.cell(Vector2i(5, 1)) == "void", "a right click with a cell brush erases the cell")

	print("\n== saving ==")
	_check(editor.dirty, "unsaved changes")
	_key(editor, KEY_S, true)
	var png := FOLDER + "layout.png"
	_check(FileAccess.file_exists(png) and not editor.dirty, "Ctrl+S writes %s" % png)
	var image := Image.load_from_file(ProjectSettings.globalize_path(png))
	_check(image != null and image.get_size() == Vector2i(15, 11), "double resolution: 15 x 11 pixels for 8 x 6 cells")
	var level := Level.parse(image, null, {})
	var floor_tiles: Array = level["terrain"]["floor"]
	var edges: Dictionary = level["terrain"]["edges"]
	_check(floor_tiles.size() == 4 and Vector2i(4, 1) in floor_tiles and Vector2i(1, 1) in floor_tiles, "the game reads the cells painted (%s)" % [floor_tiles])
	_check(edges.get(Vector3i(2, 0, Terrain.EAST)) == Terrain.Edge.WALL and edges.get(Vector3i(2, 1, Terrain.EAST)) == Terrain.Edge.DOOR,
			"a wall and a door where they were set")
	_check(level["starts"] == [Vector2i(1, 1)] and (level["entities"] as Array).size() == 1 and level["entities"][0]["name"] == "Crate1",
			"the start, and Crate1")
	_check("importer=\"image\"" in FileAccess.get_file_as_string(png + ".import"), "its .import says Image")
	_check(editor.report.begins_with("saved "), "the status says so: %s" % editor.report)
	editor.queue_free()
	await get_tree().process_frame

	var again: LevelEditor = preload("res://editor/level_editor.tscn").instantiate()
	again.map_name = "editor_test"
	again.folder = FOLDER
	add_child(again)
	await get_tree().process_frame
	_check(again.map.size == Vector2i(8, 6) and again.map.cells.size() == 4 and again.map.edge(Vector3i(2, 1, Terrain.EAST)) == "door",
			"opened again, it is as saved")
	again.queue_free()
	await get_tree().process_frame
	Net.edit_size = LevelMap.NEW_SIZE


func _test_import_file() -> void:
	print("\n== the .import: Image, whatever was there ==")
	var png := ProjectSettings.globalize_path(FOLDER + "other.png")
	var file := FileAccess.open(png + ".import", FileAccess.WRITE)
	file.store_string('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n')
	file.close()
	_check(LevelMap.ensure_image_import(png, "res://levels/other/layout.png"), "a texture import is replaced")
	var text := FileAccess.get_file_as_string(png + ".import")
	_check('importer="image"' in text and 'type="Image"' in text and "texture" not in text, "with an Image one")
	_check(not LevelMap.ensure_image_import(png, "res://levels/other/layout.png"), "and an Image one is left alone")


func _key(editor: LevelEditor, keycode: Key, ctrl := false, shift := false, alt := false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	event.alt_pressed = alt
	editor._unhandled_input(event)


func _clear() -> void:
	var dir := ProjectSettings.globalize_path(FOLDER)
	if DirAccess.dir_exists_absolute(dir):
		for name in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(name))


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
