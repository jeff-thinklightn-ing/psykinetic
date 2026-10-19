class_name MapDoc
extends RefCounted
## A level being edited, without any screen: its map (layout.png and its
## heights, LevelMap), its level.json, what of them is unsaved, and the undo
## and redo of every change. The level editor shows and edits one; builder
## mode (Builder) edits one on the server. Both change it the same ways
## (apply_changes, resize, push), so an edit is undone the same way
## wherever it was made.
##
## An undo step is a Dictionary of what to put back: a cell (Vector2i ->
## meaning), an edge (Vector3i -> kind), "height x y" -> level,
## "entry x y" / "link x y" -> level.json's entry or link there ({} for
## none), "config <key>" -> a level.json key's value (null: not there), or
## "canvas" -> {map, config} as they were before a resize.

## After any change made through it (apply, undo, redo, resize).
signal changed

const UNDO_LIMIT := 200

## Where its files are (res://levels/<map>/; tests use user://).
var folder := ""
var map: LevelMap
var config := {}
## Anything unsaved; level.json has changes; height.png was there when
## loaded; height.png has changes.
var dirty := false
var config_dirty := false
var had_heights := false
var heights_dirty := false
## relief.png as loaded (decision 525; null if the level has none), and
## whether it is to be written on save (a level first saved in the overlay).
var relief: Image = null
var relief_dirty := false
## What the last load, save or resize said.
var report := ""
var undo_steps: Array[Dictionary] = []
var redo_steps: Array[Dictionary] = []


## The level in [param folder] (layout.png, level.json, height.png), or a
## blank one [param new_size] cells big if it has no layout.png.
static func open(level_folder: String, new_size := LevelMap.NEW_SIZE) -> MapDoc:
	var doc := MapDoc.new()
	doc.folder = level_folder
	var json_path := level_folder + "level.json"
	if FileAccess.file_exists(json_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
		if parsed is Dictionary:
			doc.config = parsed
	var png := level_folder + "layout.png"
	var image: Image = null
	if FileAccess.file_exists(png):
		image = Image.load_from_file(ProjectSettings.globalize_path(png))
	if image != null:
		doc.map = LevelMap.from_image(image, doc.config)
		var heights_png := level_folder + "height.png"
		doc.had_heights = FileAccess.file_exists(heights_png)
		if doc.had_heights:
			doc.map.read_heights(Image.load_from_file(ProjectSettings.globalize_path(heights_png)))
		if FileAccess.file_exists(level_folder + "relief.png"):
			doc.relief = Image.load_from_file(ProjectSettings.globalize_path(level_folder + "relief.png"))
		doc.report = "loaded %s: %d x %d cells%s" % [png, doc.map.size.x, doc.map.size.y,
			", %d pixels of colours not in the legend (void when saved)" % doc.map.unknown_pixels if doc.map.unknown_pixels > 0 else ""]
	else:
		doc.map = LevelMap.new(new_size, doc.config)
		doc.report = "new map: %d x %d cells (not saved yet)" % [doc.map.size.x, doc.map.size.y]
	return doc


## Level [param level_name] as the game reads it (Level.source: the overlay
## first, then levels/, from the imports in an exported game), to be saved
## in the overlay (Level.overlay_dir): builder mode's doc on a server, whose
## res:// is read-only. Null if there is no such level. Saved the first
## time, it writes every file, so the overlay is a whole level.
static func from_level(level_name: String) -> MapDoc:
	var made := Level.source(level_name)
	if made["layout"] == null:
		return null
	var doc := MapDoc.new()
	doc.folder = Level.overlay_dir + level_name + "/"
	doc.config = (made["config"] as Dictionary).duplicate(true)
	doc.map = LevelMap.from_image(made["layout"], doc.config)
	doc.had_heights = made["height"] != null
	if doc.had_heights:
		doc.map.read_heights(made["height"])
	doc.relief = made.get("relief")
	if not Level.overlaid(level_name):
		doc.config_dirty = true
		doc.heights_dirty = doc.had_heights
		doc.relief_dirty = doc.relief != null
	doc.report = "loaded %s: %d x %d cells" % [level_name, doc.map.size.x, doc.map.size.y]
	return doc


## Writes layout.png and its .import (as Image), level.json if it changed,
## height.png if it changed. False if it could not; [member report] says.
func save() -> bool:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(folder)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var png := folder + "layout.png"
	var image := map.to_image()
	var error := image.save_png(ProjectSettings.globalize_path(png))
	if error != OK:
		report = "could not save %s (%s)" % [png, error_string(error)]
		return false
	var imported := LevelMap.ensure_image_import(ProjectSettings.globalize_path(png), png)
	if config_dirty:
		var json := FileAccess.open(ProjectSettings.globalize_path(folder + "level.json"), FileAccess.WRITE)
		if json == null:
			report = "could not save %slevel.json" % folder
			return false
		json.store_string(JSON.stringify(config, "\t", false) + "\n")
		json.close()
		config_dirty = false
	if heights_dirty:
		var heights_png := folder + "height.png"
		error = map.to_height_image().save_png(ProjectSettings.globalize_path(heights_png))
		if error != OK:
			report = "could not save %s (%s)" % [heights_png, error_string(error)]
			return false
		LevelMap.ensure_image_import(ProjectSettings.globalize_path(heights_png), heights_png)
		had_heights = true
		heights_dirty = false
	if relief_dirty and relief != null:
		var relief_png := folder + "relief.png"
		error = relief.save_png(ProjectSettings.globalize_path(relief_png))
		if error != OK:
			report = "could not save %s (%s)" % [relief_png, error_string(error)]
			return false
		LevelMap.ensure_image_import(ProjectSettings.globalize_path(relief_png), relief_png)
		relief_dirty = false
	dirty = false
	var level := Level.parse(image, map.to_height_image() if had_heights else null, config, relief)
	var warnings: Array = level["warnings"]
	report = "saved %s (%d x %d cells, %d floor, %d things)%s%s" % [png, map.size.x, map.size.y,
		(level["terrain"]["floor"] as Array).size(), (level["entities"] as Array).size(),
		"; import set to Image" if imported else "",
		"; warnings: " + "; ".join(warnings) if not warnings.is_empty() else ""]
	return true


## The level as Level.parse reads it from what is here now (saved or not).
func parsed() -> Dictionary:
	return Level.parse(map.to_image(), map.to_height_image() if had_heights or not map.heights.is_empty() else null, config, relief)


# --- Undo ----------------------------------------------------------------------------

## [param step] (what to put back) as the newest undo step; redo is cleared.
func push(step: Dictionary) -> void:
	if step.is_empty():
		return
	undo_steps.append(step)
	if undo_steps.size() > UNDO_LIMIT:
		undo_steps.pop_front()
	redo_steps.clear()


func undo() -> bool:
	if undo_steps.is_empty():
		return false
	redo_steps.append(_swap(undo_steps.pop_back()))
	changed.emit()
	return true


func redo() -> bool:
	if redo_steps.is_empty():
		return false
	undo_steps.append(_swap(redo_steps.pop_back()))
	changed.emit()
	return true


## Puts [param step]'s values back; returns the values it replaced.
func _swap(step: Dictionary) -> Dictionary:
	var back := {}
	for key: Variant in step:
		if key is Vector2i:
			back[key] = map.set_cell(key, step[key])
		elif key is Vector3i:
			back[key] = map.set_edge(key, step[key])
		elif key == "canvas":
			back[key] = _canvas_state()
			_set_canvas_state(step[key])
		elif str(key).begins_with("config "):
			var config_key := str(key).trim_prefix("config ")
			back[key] = config.get(config_key)
			set_config(config_key, step[key])
		else:
			var parts := str(key).split(" ")
			var at := Vector2i(int(parts[1]), int(parts[2]))
			match parts[0]:
				"height":
					back[key] = set_height(at, int(step[key]))
				"link":
					back[key] = link_of(at).duplicate(true)
					put_link(at, step[key])
				_:
					back[key] = entry_of(at).duplicate(true)
					put_entry(at, step[key])
	dirty = true
	return back


# --- Changes -------------------------------------------------------------------------

## Makes [param changes] as one undo step: {cells: cell -> meaning, edges:
## key -> kind, and optionally heights: cell -> level, entries and links
## (level.json's, at their cells), covers: the cells whose entries and links
## go first (default: every cell in cells)}, as Prefab.stamp_changes and
## AreaTools give them; config: level.json key -> value (null takes it
## out), such as "neighbours"). Returns whether anything changed.
func apply_changes(changes: Dictionary) -> bool:
	var step := {}
	var keys: Dictionary = changes.get("config", {})
	for config_key: String in keys:
		var old: Variant = config.get(config_key)
		if str(old) != str(keys[config_key]):
			step["config " + config_key] = old.duplicate(true) if old is Dictionary or old is Array else old
			set_config(config_key, keys[config_key])
	var cells: Dictionary = changes.get("cells", {})
	var covers: Array = changes.get("covers", cells.keys())
	for cell: Vector2i in covers:
		# What the map held there goes: its entry and link with its cell.
		if not entry_of(cell).is_empty():
			step["entry %d %d" % [cell.x, cell.y]] = entry_of(cell).duplicate(true)
			put_entry(cell, {})
		if not link_of(cell).is_empty():
			step["link %d %d" % [cell.x, cell.y]] = link_of(cell).duplicate(true)
			put_link(cell, {})
	for cell: Vector2i in cells:
		var old := map.set_cell(cell, cells[cell])
		if old != cells[cell]:
			step[cell] = old
	var edges: Dictionary = changes.get("edges", {})
	for key: Vector3i in edges:
		var old := map.set_edge(key, edges[key])
		if old != edges[key]:
			step[key] = old
	var heights: Dictionary = changes.get("heights", {})
	for cell: Vector2i in heights:
		var old := set_height(cell, heights[cell])
		if old != heights[cell]:
			step["height %d %d" % [cell.x, cell.y]] = old
	for entry: Dictionary in changes.get("entries", []):
		var cell: Vector2i = Level._tile(entry.get("at"))
		var key := "entry %d %d" % [cell.x, cell.y]
		if not step.has(key):
			step[key] = entry_of(cell).duplicate(true)
		put_entry(cell, entry)
	for link: Dictionary in changes.get("links", []):
		var cell: Vector2i = Level._tile(link.get("at"))
		var key := "link %d %d" % [cell.x, cell.y]
		if not step.has(key):
			step[key] = link_of(cell).duplicate(true)
		put_link(cell, link)
	if step.is_empty():
		return false
	dirty = true
	push(step)
	changed.emit()
	return true


## Sets level.json's [param key] to [param value] (null takes it out).
func set_config(key: String, value: Variant) -> void:
	if value == null:
		config.erase(key)
	else:
		config[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	if key == "legend":
		# The map draws its cells in the legend's colours: a meaning new to it is saved, not voided.
		map.colours = LevelMap.legend_colours(config)
	config_dirty = true
	dirty = true


## Sets cell [param at]'s height (0 for none); returns what it was. A
## change means height.png is written on save.
func set_height(at: Vector2i, level: int) -> int:
	var old: int = map.heights.get(at, 0)
	if level <= 0:
		map.heights.erase(at)
	else:
		map.heights[at] = level
	if old != level:
		heights_dirty = true
		dirty = true
	return old


## level.json's entry for the entity at [param at] ({} for none).
func entry_of(at: Vector2i) -> Dictionary:
	return _listed_at("entities", at)


## Puts [param entry] as the entry for [param at]: replaced where it is in
## the list, added at the end, or ({} or only "at") taken out.
func put_entry(at: Vector2i, entry: Dictionary) -> void:
	var empty := entry.keys().all(func(key: Variant) -> bool: return str(key) == "at")
	_put_listed("entities", at, {} if empty else entry)


## level.json's link on [param at] ({} for none).
func link_of(at: Vector2i) -> Dictionary:
	return _listed_at("links", at)


## Puts [param link] as the link on [param at] ({} takes it out).
func put_link(at: Vector2i, link: Dictionary) -> void:
	_put_listed("links", at, link)


func _listed_at(list: String, at: Vector2i) -> Dictionary:
	var listed: Variant = config.get(list, [])
	if listed is Array:
		for each: Variant in listed:
			if each is Dictionary and Level._tile(each.get("at")) == at:
				return each
	return {}


func _put_listed(list: String, at: Vector2i, value: Dictionary) -> void:
	if not config.get(list) is Array:
		config[list] = []
	var listed: Array = config[list]
	var index := -1
	for i in listed.size():
		if listed[i] is Dictionary and Level._tile(listed[i].get("at")) == at:
			index = i
			break
	if value.is_empty():
		if index >= 0:
			listed.remove_at(index)
	elif index >= 0:
		listed[index] = value
	else:
		listed.append(value)
	if listed.is_empty():
		config.erase(list)
	config_dirty = true
	dirty = true


# --- The canvas ----------------------------------------------------------------------

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
	push({"canvas": before})
	var lost_text := ""
	if lost > 0 or not dropped.is_empty():
		lost_text = "dropped %d cells%s" % [lost, (", " + ", ".join(dropped)) if not dropped.is_empty() else ""]
	report = "resized to %d x %d cells%s" % [map.size.x, map.size.y, "; " + lost_text if not lost_text.is_empty() else ""]
	changed.emit()
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
