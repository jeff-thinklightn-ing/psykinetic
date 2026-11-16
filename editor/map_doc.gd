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
## level.json written in its own words where unchanged (decision 851).
const JSON_KEEP := preload("res://editor/json_keep.gd")

## Where its files are (res://levels/<map>/; tests use user://).
var folder := ""
var map: LevelMap
var config := {}
## The level.json text [member config] was read from ("" for none): save
## writes the file in its words wherever a value is unchanged (851).
var source_text := ""
## Bumped by every change made through it (decision 867): what a cached
## parse of it is good for. An edit straight to map or config does not
## bump it; whoever makes one bumps it (BuilderSession after fill_codes).
var revision := 0
## Anything unsaved; level.json has changes; height.png was there when
## loaded; height.png has changes.
var dirty := false
var config_dirty := false
var had_heights := false
var heights_dirty := false
## Whether relief.png (decision 525: map.relief) has changes to write.
var relief_dirty := false
## Whether the relief was changed here since it was read or last saved (867 amended (2)): the ledges are
## traced again from it only then. relief_dirty is also set on a level read with no overlay yet, whose
## relief.png is written as it was read: tracing its ledges again was a parse for nothing.
var relief_changed := false
## The images a level not yet in the overlay was read from (867 amended (5)): {layout, height, relief},
## from_level's. A first save on the caller's word that nothing but level.json changed (save_config)
## encodes these as they were read, not LevelMap.to_image's (about 400 ms on the wilds) of the same cells.
var _read_images := {}
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
		var text := FileAccess.get_file_as_string(json_path)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			doc.config = parsed
			doc.source_text = text
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
			doc.map.read_relief(Image.load_from_file(ProjectSettings.globalize_path(level_folder + "relief.png")))
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
	if FileAccess.file_exists(Level.folder_of(level_name) + "level.json"):
		doc.source_text = FileAccess.get_file_as_string(Level.folder_of(level_name) + "level.json")
	doc.map = LevelMap.from_image(made["layout"], doc.config)
	doc.had_heights = made["height"] != null
	if doc.had_heights:
		doc.map.read_heights(made["height"])
	doc.map.read_relief(made.get("relief"))
	if not Level.overlaid(level_name):
		doc.config_dirty = true
		doc.heights_dirty = doc.had_heights
		doc.relief_dirty = doc.map.has_relief()
		doc._read_images = {"layout": made["layout"], "height": made["height"], "relief": made.get("relief")}
	doc.report = "loaded %s: %d x %d cells" % [level_name, doc.map.size.x, doc.map.size.y]
	return doc


## level.json alone, on the caller's word that nothing but the config changed
## since the last save (867 amended (2): builder mode's spots-only accept, told so
## by its proposal; [member dirty] is set by any change, a config one too), and
## the folder holds the layout already. Else save(false): no layout there yet
## (the overlay is a whole level), every file. False if it could not;
## [member report] says.
## [param into] (956): the folder the files are written in instead of [member folder] (a builder's
## accept writes the whole level beside it, then swaps the two), the level's other files copied there first.
func save_config(into := "") -> bool:
	if heights_dirty or relief_dirty or not FileAccess.file_exists(ProjectSettings.globalize_path(folder + "layout.png")):
		# The level's first save (the box's levels have no overlay until a builder's accept): every file,
		# the images as they were read (an exported game holds them imported, no file to copy), encoded
		# from the images themselves, the cells being unchanged on the caller's word (867 amended (5)).
		return save(false, _read_images, into)
	var dir := into if not into.is_empty() else folder
	if dir != folder and not _copy_files_into(dir):
		return false
	if Level.fill_codes(config):
		config_dirty = true
	if config_dirty:
		var json := FileAccess.open(ProjectSettings.globalize_path(dir + "level.json"), FileAccess.WRITE)
		if json == null:
			report = "could not save %slevel.json" % folder
			return false
		var written := JSON_KEEP.write(source_text, config)
		json.store_string(written)
		json.close()
		source_text = written
		config_dirty = false
	dirty = false
	report = "saved %slevel.json" % folder
	return true


## Writes layout.png and its .import (as Image), level.json if it changed,
## height.png if it changed. False if it could not; [member report] says.
## The ledges are traced again only when the relief was changed here
## ([member relief_changed]), not when it is written as it was read (a level's
## first save to the overlay; on the box those two parses, the trace and the
## report's, were most of an accept's 744 ms save). [param with_report] false
## (builder mode, which shows a report only when a save fails, before it
## would parse): the report without the level's parse. [param as_read] (save_config's first save, 867
## amended (5)): the images the level was read from, written in place of the map's own, which hold the
## same cells; empty, the map's. [param into] (956): the folder the files are written in instead of
## [member folder] (a builder's accept writes the whole level beside it, then swaps the two): the level's
## files copied there first, those this save writes written over them, each .import naming the files'
## place in [member folder], where they will stand.
func save(with_report := true, as_read := {}, into := "") -> bool:
	var dir := into if not into.is_empty() else folder
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if dir != folder and not _copy_files_into(dir):
		return false
	var png := folder + "layout.png"
	var image: Image = as_read["layout"] if as_read.get("layout") is Image else map.to_image()
	var error := image.save_png(ProjectSettings.globalize_path(dir + "layout.png"))
	if error != OK:
		report = "could not save %s (%s)" % [dir + "layout.png", error_string(error)]
		return false
	var imported := LevelMap.ensure_image_import(ProjectSettings.globalize_path(dir + "layout.png"), png)
	# Each building's code written in, so it stays its own (decision 537).
	if Level.fill_codes(config):
		config_dirty = true
	# The ledges traced again from the relief as it now is (decision 585).
	if relief_changed and map.has_relief():
		var terrain: Dictionary = Level.parse(image, map.to_height_image() if had_heights or heights_dirty else null, config, map.to_relief_image(), parse_templates)["terrain"]
		var ledges := Level.ledges_of(terrain)
		if ledges != config.get("ledges", []):
			if ledges.is_empty():
				config.erase("ledges")
			else:
				config["ledges"] = ledges
			config_dirty = true
	if config_dirty:
		var json := FileAccess.open(ProjectSettings.globalize_path(dir + "level.json"), FileAccess.WRITE)
		if json == null:
			report = "could not save %slevel.json" % dir
			return false
		var written := JSON_KEEP.write(source_text, config)
		json.store_string(written)
		json.close()
		source_text = written
		config_dirty = false
	if heights_dirty:
		var heights_png := folder + "height.png"
		error = map.to_height_image().save_png(ProjectSettings.globalize_path(dir + "height.png"))
		if error != OK:
			report = "could not save %s (%s)" % [dir + "height.png", error_string(error)]
			return false
		LevelMap.ensure_image_import(ProjectSettings.globalize_path(dir + "height.png"), heights_png)
		had_heights = true
		heights_dirty = false
	if relief_dirty and map.has_relief():
		var relief_png := folder + "relief.png"
		error = map.to_relief_image().save_png(ProjectSettings.globalize_path(dir + "relief.png"))
		if error != OK:
			report = "could not save %s (%s)" % [dir + "relief.png", error_string(error)]
			return false
		LevelMap.ensure_image_import(ProjectSettings.globalize_path(dir + "relief.png"), relief_png)
		relief_dirty = false
	relief_changed = false
	dirty = false
	# The overlay holds the level now: what it was read from is no save's any more (a later first-save
	# fallback must never write the pack's layout over a builder's cells).
	_read_images = {}
	if not with_report:
		report = "saved %s (%d x %d cells)" % [png, map.size.x, map.size.y]
		return true
	var level := Level.parse(image, map.to_height_image() if had_heights else null, config, map.to_relief_image())
	var warnings: Array = level["warnings"]
	report = "saved %s (%d x %d cells, %d floor, %d things)%s%s" % [png, map.size.x, map.size.y,
		(level["terrain"]["floor"] as Array).size(), (level["entities"] as Array).size(),
		"; import set to Image" if imported else "",
		"; warnings: " + "; ".join(warnings) if not warnings.is_empty() else ""]
	return true


## Every file in [member folder] copied into [param dir] (956): what a save there does not write stays as
## it was, and the swap that puts [param dir] in its place drops nothing. False, and [member report] says,
## if one could not be.
func _copy_files_into(dir: String) -> bool:
	var from := ProjectSettings.globalize_path(folder)
	var to := ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(to):
		DirAccess.make_dir_recursive_absolute(to)
	if not DirAccess.dir_exists_absolute(from):
		return true  # Nothing there yet: the level's first save writes every file.
	for each: String in DirAccess.get_files_at(from):
		if DirAccess.copy_absolute(from.path_join(each), to.path_join(each)) != OK:
			report = "could not copy %s%s" % [folder, each]
			return false
	return true


## The linked levels' configs a parse here reads (Level.parse's templates, 933), read on the main thread
## first when this doc is saved off it (956); empty, Level.parse reads them itself.
var parse_templates := {}


## A copy of this doc (956: a builder's accept changes and saves it off the main thread, then this doc
## takes it whole: take_laid): its map, config, files' text,
## revision, undo and redo, and what is still to write. The images it was read from are shared, read only.
func copy() -> MapDoc:
	var out := MapDoc.new()
	out.folder = folder
	out.map = map.copy()
	out.config = config.duplicate(true)
	out.source_text = source_text
	out.revision = revision
	out.dirty = dirty
	out.config_dirty = config_dirty
	out.had_heights = had_heights
	out.heights_dirty = heights_dirty
	out.relief_dirty = relief_dirty
	out.relief_changed = relief_changed
	out._read_images = _read_images
	out.undo_steps = undo_steps.duplicate()
	out.redo_steps = redo_steps.duplicate()
	return out


## What [param saved] (copy()'s, changed as this doc has just been and saved, 956) made of the save
## taken: its config as written (building codes filled, ledges traced), the text written, what is left to
## write (nothing) and whether the level has heights.
func take_saved(saved: MapDoc) -> void:
	config = saved.config
	source_text = saved.source_text
	dirty = saved.dirty
	config_dirty = saved.config_dirty
	had_heights = saved.had_heights
	heights_dirty = saved.heights_dirty
	relief_dirty = saved.relief_dirty
	relief_changed = saved.relief_changed
	_read_images = saved._read_images
	report = saved.report


## [param laid] (copy()'s of this doc, changed and saved on a builder's worker, 956) taken whole: its map,
## undo and redo steps and revision (the change as apply_changes or undo made it there, so it is not made
## twice), and its save (take_saved). Said once, as a change here would be.
func take_laid(laid: MapDoc) -> void:
	map = laid.map
	undo_steps = laid.undo_steps
	redo_steps = laid.redo_steps
	revision = laid.revision
	take_saved(laid)
	changed.emit()


## The level as Level.parse reads it from what is here now (saved or not).
## [param templates]: Level.parse's (933), the linked levels' configs read on the main thread first.
func parsed(templates: Dictionary = {}) -> Dictionary:
	return Level.parse(map.to_image(), map.to_height_image() if had_heights or not map.heights.is_empty() else null, config, map.to_relief_image(), templates)


## A change made: the revision on, and said (867).
func _bump() -> void:
	revision += 1
	changed.emit()


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
	_bump()
	return true


func redo() -> bool:
	if redo_steps.is_empty():
		return false
	undo_steps.append(_swap(redo_steps.pop_back()))
	_bump()
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
		elif key == "relief state":
			back[key] = _relief_state()
			map.relief = step[key]["relief"]
			map.heights = step[key]["heights"]
			relief_dirty = true
			relief_changed = true
			heights_dirty = true
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
				"relief":
					back[key] = set_relief(at, float(step[key]))
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
	var relief: Dictionary = changes.get("relief", {})
	if not relief.is_empty() and not map.has_relief():
		# The map's first relief: the whole state is the step (undone at once).
		step["relief state"] = _relief_state()
		_start_relief()
	for cell: Vector2i in relief:
		var old := set_relief(cell, float(relief[cell]))
		if not is_equal_approx(old, snappedf(float(relief[cell]), 0.01)) and not step.has("relief state"):
			step["relief %d %d" % [cell.x, cell.y]] = old
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
	_bump()
	return true


## Sets level.json's [param key] to [param value] (null takes it out).
func set_config(key: String, value: Variant) -> void:
	revision += 1
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
	revision += 1
	var old: int = map.heights.get(at, 0)
	if level <= 0:
		map.heights.erase(at)
	else:
		map.heights[at] = level
	if old != level:
		heights_dirty = true
		dirty = true
	return old


## Sets cell [param at]'s elevation (decision 525) to [param metres];
## returns what it was. A change means relief.png is written on save.
func set_relief(at: Vector2i, metres: float) -> float:
	revision += 1
	if not map.has_relief():
		_start_relief()
	var old := map.set_relief(at, metres)
	if not is_equal_approx(old, map.relief_at(at)):
		relief_dirty = true
		relief_changed = true
		dirty = true
	return old


## The map's relief and heights, to put back (an undo step's).
func _relief_state() -> Dictionary:
	return {"relief": map.relief.duplicate(), "heights": map.heights.duplicate()}


## Gives the map relief (decision 525) from its heights, which it then has
## none of (height.png written black: relief.png is the ground).
func _start_relief() -> void:
	map.relief = Relief.derived(map.heights, map.size)
	if not map.heights.is_empty():
		map.heights.clear()
		heights_dirty = true
	relief_dirty = true
	relief_changed = true
	dirty = true


## level.json's entry for the entity at [param at] ({} for none).
func entry_of(at: Vector2i) -> Dictionary:
	return _listed_at("entities", at)


## Puts [param entry] as the entry for [param at]: replaced where it is in
## the list, added at the end, or ({} or only "at") taken out.
func put_entry(at: Vector2i, entry: Dictionary) -> void:
	revision += 1
	var empty := entry.keys().all(func(key: Variant) -> bool: return str(key) == "at")
	_put_listed("entities", at, {} if empty else entry)


## level.json's link on [param at] ({} for none).
func link_of(at: Vector2i) -> Dictionary:
	return _listed_at("links", at)


## Puts [param link] as the link on [param at] ({} takes it out).
func put_link(at: Vector2i, link: Dictionary) -> void:
	revision += 1
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
	_bump()
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
