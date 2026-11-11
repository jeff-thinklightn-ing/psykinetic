extends Node
## Builder mode's own tools run headless on one level (decision 851, for
## maps laying Umbrage's spots and place rects as data): the same tools,
## refusals and warnings as a player's builder session on the server, no
## Claude call and no key, written as the level's own files for a diff.
##   godot --headless --path <repo> --scene res://tools/builder_run.tscn -- --level=wilds --calls=<calls.json>
##       [--area=x,y,w,h] [--out=<dir>] [--go-on] [--into-repo]
## calls.json is a list of {"tool": <a builder tool's name>, "input": {...}}
## (the tools' inputs as BuilderSession.tools() gives them). Each is run in
## turn and its answer printed ("TOOL <name> ok: ..." or "TOOL <name>
## refused: ..."); the first refusal stops the run with nothing written
## unless --go-on. Then the layout and arrival warnings the change adds, the
## change accepted (a refusal there stops it too), the level saved and the
## world map's new problems said. The area is the whole level unless --area.
##
## Written to --out (default user://builder_run_<checkout>/), which is the
## run's own private overlay (Level.overlay_dir), so every level is read
## from levels/ and the shared user://levels/ overlay is never read or
## written. Each file that differs from levels/<level>/ is named
## ("CHANGED levels/wilds/level.json"); --into-repo copies those into
## levels/<level>/, level.json in the file's own words where unchanged
## (MapDoc's JSON_KEEP), so the diff shows only the change. What lands is
## the caller's own data change; the runner never commits. Exit 0 done,
## 1 bad arguments, 2 refused (nothing written to the repo).

const TEST_PORTS := preload("res://tests/test_ports.gd")
## The files of a level the runner writes and compares.
const FILES := ["level.json", "layout.png", "height.png", "relief.png"]
## The marker a folder the runner may empty carries.
const MARK := ".builder_run"


func _ready() -> void:
	get_tree().quit(run(OS.get_cmdline_user_args()))


## Runs the arguments [param words]; the exit code.
static func run(words: PackedStringArray) -> int:
	var args := {}
	for arg in words:
		if arg.begins_with("--") and arg.contains("="):
			args[arg.substr(2, arg.find("=") - 2)] = arg.substr(arg.find("=") + 1)
		elif arg.begins_with("--"):
			args[arg.substr(2)] = true
	var level_name := str(args.get("level", ""))
	if level_name.is_empty() or not ResourceLoader.exists(Level.DIR + level_name + "/layout.png"):
		return _bad("--level=<a level under levels/> is needed (got \"%s\")" % level_name)
	var calls: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(args.get("calls", ""))))
	if not calls is Array:
		return _bad("--calls=<a json file holding a list of {\"tool\", \"input\"}> is needed")
	var out := str(args.get("out", "user://builder_run_%s/" % TEST_PORTS.checkout())).replace("\\", "/")
	if not out.ends_with("/"):
		out += "/"
	var refused := _out_refused(out)
	if not refused.is_empty():
		return _bad(refused)
	_clear(out)
	var kept_overlay := Level.overlay_dir
	Level.overlay_dir = out
	var code := _run_in(level_name, calls, args, out)
	Level.overlay_dir = kept_overlay
	return code


static func _run_in(level_name: String, calls: Array, args: Dictionary, out: String) -> int:
	var doc := MapDoc.from_level(level_name)
	var area := Rect2i(Vector2i.ZERO, doc.map.size)
	if args.has("area"):
		var parts := str(args["area"]).split(",")
		if parts.size() != 4:
			return _bad("--area=x,y,w,h (got %s)" % args["area"])
		area = Rect2i(int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3]))
	var session := BuilderSession.new(doc, area, level_name, null)
	print("builder_run: %s, area %s, %d calls" % [level_name, session.area, calls.size()])
	var layout_before := BuilderSession.layout_faults(doc)
	var arrivals_before := session.arrival_faults(doc)
	var problems_before := WorldMap.build().problems()
	var stopped := false
	for call: Variant in calls:
		if not call is Dictionary or not (call as Dictionary).has("tool"):
			return _bad("a call is {\"tool\": <name>, \"input\": {...}} (got %s)" % [call])
		var answer := session.run_tool(str(call["tool"]), call.get("input", {}))
		var ok := bool(answer.get("ok", false))
		print("TOOL %s %s: %s" % [call["tool"], "ok" if ok else "refused", answer.get("text", answer)])
		if not ok and not args.has("go-on"):
			stopped = true
			break
	if stopped:
		print("builder_run: stopped at the refusal; nothing written (--go-on runs on past one)")
		return 2
	for news in session.layout_news(layout_before):
		print("LAYOUT %s" % news)
	for news in session.arrival_news(arrivals_before):
		print("ARRIVAL %s (%s)" % [news, BuilderSession.ARRIVAL_SAYS])
	if not session.accept():
		print("builder_run: not accepted: %s; nothing written" % (session.refused if not session.refused.is_empty() else "no change"))
		return 2
	if session.created_doc != null:
		print("builder_run: a new area beyond the edge (%s) is not written by the runner" % session.created)
	if not doc.save():
		print("builder_run: not saved: %s" % doc.report)
		return 2
	print("builder_run: %s" % doc.report)
	for problem in WorldMap.build().problems():
		if problem not in problems_before:
			print("WORLD %s" % problem)
	var changed := changed_files(out + level_name + "/", Level.DIR + level_name + "/")
	for file in changed:
		print("CHANGED levels/%s/%s" % [level_name, file])
	if changed.is_empty():
		print("builder_run: no file differs from levels/%s/" % level_name)
	if args.has("into-repo"):
		for file in changed:
			var into := ProjectSettings.globalize_path(Level.DIR + level_name + "/" + file)
			var copied := DirAccess.copy_absolute(ProjectSettings.globalize_path(out + level_name + "/" + file), into)
			print("WROTE %s%s" % [into, "" if copied == OK else " FAILED (%s)" % error_string(copied)])
	else:
		print("builder_run: written to %s (--into-repo copies the changed files into levels/%s/)" % [ProjectSettings.globalize_path(out + level_name + "/"), level_name])
	return 0


## The files of [constant FILES] in [param made] that differ from
## [param from]'s: level.json by its text, the images as the game reads
## them (each through LevelMap and back: MapDoc writes the pixels between
## cells, which nothing reads, black where a hand-laid file may hold a
## colour, so pixel for pixel every save would differ).
static func changed_files(made: String, from: String) -> Array[String]:
	var out: Array[String] = []
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(from + "level.json")) if FileAccess.file_exists(from + "level.json") else {}
	var mine := _read(made, config if config is Dictionary else {})
	var theirs := _read(from, config if config is Dictionary else {})
	for file: String in FILES:
		if not FileAccess.file_exists(made + file):
			continue
		if file.ends_with(".json"):
			if not FileAccess.file_exists(from + file) or FileAccess.get_file_as_string(made + file) != FileAccess.get_file_as_string(from + file):
				out.append(file)
		elif theirs.get(file) == null or mine.get(file) == null or not _same_pixels(mine[file], theirs[file]):
			out.append(file)
	return out


## Level [param folder]'s images as the game reads them, written again by
## LevelMap: file name -> Image (null where the folder has none).
static func _read(folder: String, config: Dictionary) -> Dictionary:
	var layout: Image = Image.load_from_file(ProjectSettings.globalize_path(folder + "layout.png")) if FileAccess.file_exists(folder + "layout.png") else Level._image(folder + "layout.png")
	if layout == null:
		return {}
	var map := LevelMap.from_image(layout, config)
	var out := {"layout.png": map.to_image(), "height.png": null, "relief.png": null}
	var height: Image = Image.load_from_file(ProjectSettings.globalize_path(folder + "height.png")) if FileAccess.file_exists(folder + "height.png") else Level._image(folder + "height.png")
	if height != null and map.read_heights(height):
		out["height.png"] = map.to_height_image()
	var relief: Image = Image.load_from_file(ProjectSettings.globalize_path(folder + "relief.png")) if FileAccess.file_exists(folder + "relief.png") else Level._image(folder + "relief.png")
	if relief != null and map.read_relief(relief):
		out["relief.png"] = map.to_relief_image()
	return out


static func _same_pixels(a: Image, b: Image) -> bool:
	if a.get_size() != b.get_size():
		return false
	var first := a.duplicate() as Image
	var second := b.duplicate() as Image
	first.convert(Image.FORMAT_RGBA8)
	second.convert(Image.FORMAT_RGBA8)
	return first.get_data() == second.get_data()


## Why [param out] may not hold the run, or "": never the shared overlay,
## never inside the project, and a folder already there only when it is
## an earlier run's (it carries [constant MARK]) or empty.
static func _out_refused(out: String) -> String:
	var where := ProjectSettings.globalize_path(out).simplify_path().to_lower()
	var overlay := ProjectSettings.globalize_path(Level.OVERLAY).simplify_path().to_lower()
	var project := ProjectSettings.globalize_path("res://").simplify_path().to_lower()
	if where == overlay or where.begins_with(overlay + "/") or overlay.begins_with(where + "/"):
		return "--out may not be the shared overlay (%s) or hold it" % overlay
	if where == project or where.begins_with(project + "/") or project.begins_with(where + "/"):
		return "--out may not be inside the project or hold it (%s)" % project
	if DirAccess.dir_exists_absolute(where) and not FileAccess.file_exists(where + "/" + MARK):
		var found := DirAccess.get_files_at(where).size() + DirAccess.get_directories_at(where).size()
		if found > 0:
			return "--out %s holds files that are not a builder_run's: name an empty folder" % where
	return ""


## Empties [param out] (an earlier run's, checked by _out_refused), so no
## level of an earlier run is read as edited, and marks it.
static func _clear(out: String) -> void:
	var where := ProjectSettings.globalize_path(out)
	DirAccess.make_dir_recursive_absolute(where)
	for level_name in DirAccess.get_directories_at(where):
		for file in DirAccess.get_files_at(where + level_name):
			DirAccess.remove_absolute(where + level_name + "/" + file)
		DirAccess.remove_absolute(where + level_name)
	var mark := FileAccess.open(where + MARK, FileAccess.WRITE)
	mark.store_string("builder_run's folder (decision 851): emptied at each run\n")
	mark.close()


static func _bad(why: String) -> int:
	printerr("builder_run: " + why)
	return 1
