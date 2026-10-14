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
	_clear()
	await _test_monsters()
	_clear()
	await _test_resize()
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


func _test_monsters() -> void:
	print("\n== monsters: select, turn, how they idle, saved in level.json ==")
	var dir := ProjectSettings.globalize_path(FOLDER)
	DirAccess.make_dir_recursive_absolute(dir)
	var markers := {Vector2i(2, 2): "monster_brute", Vector2i(5, 2): "monster_sneak", Vector2i(3, 4): "monster_imp"}
	# Double resolution: 27 x 23 pixels are 14 x 12 cells.
	var rows: Array[String] = []
	for y in 23:
		rows.append(".".repeat(27))
	Level.image_from_rows(rows, markers).save_png(dir.path_join("layout.png"))
	var json := FileAccess.open(dir.path_join("level.json"), FileAccess.WRITE)
	json.store_string(JSON.stringify({"name": "Monsters", "entities": [{"at": [3, 4], "name": "Grub"}]}, "\t"))
	json.close()
	var editor: LevelEditor = preload("res://editor/level_editor.tscn").instantiate()
	editor.map_name = "editor_test"
	editor.folder = FOLDER
	add_child(editor)
	await get_tree().process_frame
	var order_before: Array = Level.parse(editor.map.to_image(), null, editor.config)["entities"].map(
			func(spec: Dictionary) -> String: return "%s@%s" % [spec["name"], spec["tile"]])

	_key(editor, KEY_V)
	_check(editor.brush == "select", "V picks the select tool")
	editor.begin_stroke(MOUSE_BUTTON_LEFT, Vector2(2.5, 2.5))
	editor.end_stroke()
	_check(editor.selected == Vector2i(2, 2) and editor._panel.get_parent().visible, "a click picks the brute, and its panel shows")
	_check(editor.map.cell(Vector2i(2, 2)) == "monster_brute", "and paints nothing")
	var own := Monster.own_facing("Brute1")
	_check(editor.facing_of(Vector2i(2, 2)) == [own, false], "it faces its own way to start (%s)" % own)
	_key(editor, KEY_E)
	_check(editor.facing_of(Vector2i(2, 2)) == [Monster.turned(own, 1), true], "E turns it an eighth clockwise")
	_key(editor, KEY_Q)
	_key(editor, KEY_Q)
	var facing: Vector2i = Monster.turned(own, -1)
	_check(editor.entry_of(Vector2i(2, 2)).get("facing") == [facing.x, facing.y], "Q back the other way, set in its entry")
	editor.set_idle_mode("guard")
	_check(editor.entry_of(Vector2i(2, 2)).get("idle") == "guard", "and it guards")

	editor.begin_stroke(MOUSE_BUTTON_LEFT, Vector2(5.5, 2.5))
	editor.end_stroke()
	editor.set_idle_mode("patrol")
	editor.editing_route = true
	for at: Vector2 in [Vector2(5.5, 2.5), Vector2(9.5, 2.5), Vector2(9.5, 6.5), Vector2(12.5, 9.5)]:
		editor.begin_stroke(MOUSE_BUTTON_LEFT, at)
		editor.end_stroke()
	editor.begin_stroke(MOUSE_BUTTON_RIGHT, Vector2(1.5, 1.5))
	editor.end_stroke()
	editor.set_route_loop(false)
	var idle: Dictionary = editor.entry_of(Vector2i(5, 2)).get("idle", {})
	_check(idle.get("mode") == "patrol" and idle.get("route") == [[5, 2], [9, 2], [9, 6]] and idle.get("loop") == false,
			"the sneak patrols a route of clicks, the last taken back, back and forth (%s)" % [idle])
	_check(editor.selected == Vector2i(5, 2), "clicks on the route did not pick anything else")
	_key(editor, KEY_ESCAPE)
	_check(not editor.editing_route and editor.selected == Vector2i(5, 2), "Esc ends the route")

	editor.begin_stroke(MOUSE_BUTTON_LEFT, Vector2(3.5, 4.5))
	editor.end_stroke()
	editor.set_idle_mode("gather")
	editor.setting_point = true
	editor.begin_stroke(MOUSE_BUTTON_LEFT, Vector2(6.5, 6.5))
	editor.end_stroke()
	var grub := editor.entry_of(Vector2i(3, 4))
	_check(grub.get("idle") == {"mode": "gather", "point": [6, 6]} and grub.get("name") == "Grub",
			"Grub gathers at the point clicked, its name kept (%s)" % [grub])
	_key(editor, KEY_Z, true)
	_check(editor.entry_of(Vector2i(3, 4)).get("idle", {}).get("point") == [4, 4], "Ctrl+Z puts the point back as it was")
	_key(editor, KEY_Y, true)
	_check(editor.entry_of(Vector2i(3, 4)).get("idle", {}).get("point") == [6, 6], "and Ctrl+Y again")
	_key(editor, KEY_ESCAPE)
	_check(editor.selected == Vector2i(-1, -1) and not editor._panel.get_parent().visible, "Esc lets go of it")

	_key(editor, KEY_S, true)
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(FOLDER + "level.json"))
	_check(saved is Dictionary and saved.get("name") == "Monsters", "Ctrl+S writes level.json, the rest of it kept")
	var level := Level.parse(Image.load_from_file(dir.path_join("layout.png")), null, saved)
	var by_name := {}
	for spec: Dictionary in level["entities"]:
		by_name[spec["name"]] = spec
	_check(by_name.has("Brute1") and by_name["Brute1"].get("facing") == facing and by_name["Brute1"].get("idle", {}).get("mode") == "guard",
			"the game reads the brute's facing and guard")
	_check(by_name.has("Sneak1") and by_name["Sneak1"]["idle"].get("route") == [Vector2i(5, 2), Vector2i(9, 2), Vector2i(9, 6)],
			"the sneak's route")
	_check(by_name.has("Grub") and by_name["Grub"]["idle"].get("point") == Vector2i(6, 6), "and Grub's point")
	var order_after: Array = level["entities"].map(func(spec: Dictionary) -> String: return "%s@%s" % [spec["name"], spec["tile"]])
	_check(order_after == order_before, "every monster keeps its name and place in the order (%s)" % [order_after])
	editor.queue_free()
	await get_tree().process_frame
	var again: LevelEditor = preload("res://editor/level_editor.tscn").instantiate()
	again.map_name = "editor_test"
	again.folder = FOLDER
	add_child(again)
	await get_tree().process_frame
	_check(again.facing_of(Vector2i(2, 2)) == [facing, true] and again.idle_of(Vector2i(5, 2)).get("loop") == false,
			"opened again, it is as saved")
	again.queue_free()
	await get_tree().process_frame


func _test_resize() -> void:
	print("
== resize: grow and shrink from any side, level.json and height.png move with it ==")
	var dir := ProjectSettings.globalize_path(FOLDER)
	DirAccess.make_dir_recursive_absolute(dir)
	# 10 x 8 cells of stone; a brute, a sneak on a route, a start, a link.
	var rows: Array[String] = []
	for y in 15:
		rows.append(".".repeat(19))
	var markers := {Vector2i(2, 2): "monster_brute", Vector2i(8, 6): "monster_sneak", Vector2i(1, 1): "start", Vector2i(9, 7): "link"}
	var layout := Level.image_from_rows(rows, markers)
	layout.save_png(dir.path_join("layout.png"))
	Level.height_image(layout, {Vector2i(3, 3): 2}).save_png(dir.path_join("height.png"))
	var json := FileAccess.open(dir.path_join("level.json"), FileAccess.WRITE)
	json.store_string(JSON.stringify({"name": "Resize", "centre": [5, 4], "starts": [[1, 1]],
		"spawn_points": {"door": [9, 6]}, "links": [{"at": [9, 7], "to_map": "test_room", "to_spawn": ""}],
		"entities": [{"at": [2, 2], "facing": [1, 0], "idle": {"mode": "gather", "point": [3, 3]}},
			{"at": [8, 6], "idle": {"mode": "patrol", "route": [[8, 6], [8, 2], [2, 6]], "loop": true}}]}, "	"))
	json.close()
	var editor: LevelEditor = preload("res://editor/level_editor.tscn").instantiate()
	editor.map_name = "editor_test"
	editor.folder = FOLDER
	add_child(editor)
	await get_tree().process_frame
	_check(editor.map.size == Vector2i(10, 8) and editor.map.heights == {Vector2i(3, 3): 2}, "a 10 x 8 map with one raised cell")

	editor.resize(3, 2, 0, 0)
	var shift := Vector2i(3, 2)
	_check(editor.map.size == Vector2i(13, 10), "3 more on the left, 2 on top: 13 x 10")
	_check(editor.map.cell(Vector2i(2, 2) + shift) == "monster_brute" and editor.map.cell(Vector2i(0, 0) + shift) == "stone"
			and editor.map.cell(Vector2i(0, 0)) == "void", "every cell keeps its place on the ground; the new strip is void")
	_check(editor.map.heights == {Vector2i(3, 3) + shift: 2}, "and so does the height")
	var brute := editor.entry_of(Vector2i(5, 4))
	_check(brute.get("idle", {}).get("point") == [6, 5] and Level.facing_from(brute.get("facing")) == Vector2i(1, 0), "the brute's entry and gather point moved (%s)" % [brute])
	_check(editor.entry_of(Vector2i(11, 8)).get("idle", {}).get("route") == [[11, 8], [11, 4], [5, 8]], "the sneak's route moved")
	_check(editor.config["starts"] == [[4, 3]] and editor.config["centre"] == [8, 6] and editor.config["spawn_points"]["door"] == [12, 8]
			and editor.config["links"][0]["at"] == [12, 9], "starts, centre, spawn points and links moved")

	var lost := editor.resize(0, 0, -4, 0)
	_check(editor.map.size == Vector2i(9, 10) and editor.map.cell(Vector2i(11, 8)) == "void", "4 off the right: 9 x 10, the sneak's column gone")
	_check(editor.entry_of(Vector2i(11, 8)).is_empty() and (editor.config["links"] as Array).is_empty()
			and not editor.config["spawn_points"].has("door"), "its entry, the link and the spawn point there are dropped")
	_check("dropped" in lost and "link" in lost, "and it says so: %s" % lost)
	_key(editor, KEY_Z, true)
	_check(editor.map.size == Vector2i(13, 10) and editor.entry_of(Vector2i(11, 8)).has("idle"), "Ctrl+Z puts the strip back, entry and all")
	_key(editor, KEY_Z, true)
	_check(editor.map.size == Vector2i(10, 8) and editor.entry_of(Vector2i(2, 2)).has("idle") and editor.map.heights == {Vector2i(3, 3): 2},
			"and again: back as loaded")
	_key(editor, KEY_Y, true)
	_check(editor.map.size == Vector2i(13, 10), "Ctrl+Y grows it again")
	_key(editor, KEY_R, true)
	_check(editor._canvas.visible, "Ctrl+R shows the canvas panel")

	_key(editor, KEY_S, true)
	var image := Image.load_from_file(dir.path_join("layout.png"))
	var heights := Image.load_from_file(dir.path_join("height.png"))
	_check(image.get_size() == Vector2i(25, 19) and heights.get_size() == image.get_size(), "saved: layout.png and height.png both 25 x 19")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(FOLDER + "level.json"))
	var level := Level.parse(image, heights, saved)
	var by_name := {}
	for spec: Dictionary in level["entities"]:
		by_name[spec["name"]] = spec
	_check(level["warnings"].is_empty(), "the game reads it without a warning (%s)" % [level["warnings"]])
	_check(by_name["Brute1"]["tile"] == Vector2i(5, 4) and by_name["Brute1"]["idle"]["point"] == Vector2i(6, 5)
			and by_name["Sneak1"]["idle"]["route"][1] == Vector2i(11, 4), "the brute, its point and the sneak's route where they moved to")
	_check(level["terrain"]["heights"] == {Vector2i(6, 5): 2} and level["starts"] == [Vector2i(4, 3)]
			and level["links"][0]["tile"] == Vector2i(12, 9), "the height, the start and the link too")
	editor.queue_free()
	await get_tree().process_frame


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
