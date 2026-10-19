class_name Prefab
extends RefCounted
## A prefab is a piece of map saved to stamp elsewhere: levels/prefabs/<name>/
## in a level's own format (layout.png, level.json, optional height.png;
## docs/levels.md), its top-left cell at (0, 0). level.json keeps what goes
## with the piece: the entities' entries (names, props such as a chest's
## slots, facing, idling with its route or gather point) and links, and
## the legend and monster types it uses; not starts, spawn points or a centre.
##
## Stamping lays it on a map with its top-left at a cell, turned a number of
## quarter turns clockwise: each of its cells that is not void replaces the
## map's (and its height), each edge between two of its cells with one of
## them not void is set to the prefab's (clear where it has none), and its
## entries go to where their cells land. Void cells leave the map as it was,
## so a round camp stamps round.

const DIR := "res://levels/prefabs/"
## level.json keys a prefab keeps.
const KEEP: Array[String] = ["entities", "links", "legend", "monsters", "places", "buildings", "roofs"]
## What the editor's clipboard keeps (decision 516): a prefab's, and the
## names a saved prefab leaves out (stamp_changes renames a taken one).
const CLIPBOARD_KEEP: Array[String] = ["entities", "links", "legend", "monsters", "places", "buildings", "roofs",
	"spawn_points", "starts", "markets", "streams"]


## The building kinds as prefabs (decision 488): "building_<kind>_<size>",
## each made from levels/buildings.json as it is read (kind_prefab), never
## saved, so the kinds file is their one source.
const KIND_PREFIX := "building_"


## The prefabs there are, by name, sorted.
static func names(dir := DIR) -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		return out
	for each in DirAccess.get_directories_at(ProjectSettings.globalize_path(dir)):
		if FileAccess.file_exists(dir + each + "/layout.png"):
			out.append(each)
	out.sort()
	return out


## The building kinds' prefabs' names, "building_<kind>_<size>", sorted.
static func kind_names() -> Array[String]:
	var out: Array[String] = []
	for kind: String in Level.kinds():
		for size: String in Level.kinds()[kind].get("sizes", {}):
			out.append("%s%s_%s" % [KIND_PREFIX, kind, size])
	out.sort()
	return out


## Kind building prefab [param prefab_name] ({} if it names no kind and
## size): its blocks' cells as ground (stone under a floor set, else dirt),
## walls round their union but its doors, a ring of dirt round it so the
## walls are its own, and its entry {kind, size, at, facing south}.
static func kind_prefab(prefab_name: String) -> Dictionary:
	if not prefab_name.begins_with(KIND_PREFIX):
		return {}
	var named := prefab_name.trim_prefix(KIND_PREFIX)
	var size := named.get_slice("_", named.get_slice_count("_") - 1)
	var kind := named.trim_suffix("_" + size)
	var entry := {"kind": kind, "size": size, "at": [1, 1], "facing": [0, 1]}
	var rect: Variant = Level.building_rect(entry)
	if not Level.kinds().has(kind) or rect == null:
		return {}
	var map := LevelMap.new(rect.size + Vector2i(2, 2))
	for y in map.size.y:
		for x in map.size.x:
			map.set_cell(Vector2i(x, y), "dirt")
	var ground := "stone" if not str(Level.kinds()[kind].get("floor_set", "")).is_empty() else "dirt"
	var cells := Level._union(Level.building_blocks(entry))
	for cell in cells:
		map.set_cell(cell, ground)
	var doors := Level.kind_doors(entry)
	for key in Level.blocks_outline(cells):
		map.set_edge(key, "door" if key in doors else "wall")
	return {"map": map, "config": {"buildings": [entry]}}


## The area [param rect] of [param map] with its part of [param config], as
## a prefab {map, config}: what was at rect.position is at (0, 0).
static func extract(map: LevelMap, config: Dictionary, rect: Rect2i, keys: Array[String] = KEEP) -> Dictionary:
	var inside := func(at: Vector2i) -> Variant:
		return at - rect.position if rect.has_point(at) else null
	var piece := map.transformed(rect.size, inside)
	var moved := LevelMap.moved_config(config, inside)
	var kept := {}
	for key in keys:
		if moved.has(key) and not (moved[key] is Array and (moved[key] as Array).is_empty()):
			kept[key] = moved[key]
	return {"map": piece, "config": kept}


## [param prefab] turned [param turns] quarter turns clockwise: cells, edges,
## heights, entries, their facings, routes and points.
static func rotated(prefab: Dictionary, turns: int) -> Dictionary:
	var map: LevelMap = prefab["map"]
	var config: Dictionary = prefab["config"]
	var out := {"map": map, "config": config}
	for i in posmod(turns, 4):
		var height: int = (out["map"] as LevelMap).size.y
		var turn := func(at: Vector2i) -> Variant: return Vector2i(height - 1 - at.y, at.x)
		var size: Vector2i = (out["map"] as LevelMap).size
		out = {"map": (out["map"] as LevelMap).transformed(Vector2i(size.y, size.x), turn),
			"config": LevelMap.moved_config(out["config"], turn, 1)}
	return out


## What stamping [param prefab] with its top-left at [param at] on
## [param map] (as it is) sets: {cells: cell -> meaning ("void" for none
## here), edges: key -> kind, heights: cell -> level, entries: their entries,
## moved, links: theirs, moved, covers: the map cells the prefab's cells land on,
## and, if the prefab has places, config: {places: [param config]'s (the
## map's level.json) with the prefab's added, moved, a key the map has
## already taking _2, _3...}; if it has buildings or lands on the map's,
## config buildings: the map's that it does not land on, and its own,
## moved, and roofs so}. Only what lands on the map.
static func stamp_changes(prefab: Dictionary, map: LevelMap, at: Vector2i, config := {}) -> Dictionary:
	var piece: LevelMap = prefab["map"]
	var cells: Dictionary[Vector2i, String] = {}
	var heights: Dictionary[Vector2i, int] = {}
	var edges: Dictionary[Vector3i, String] = {}
	var covers: Array[Vector2i] = []
	for cell: Vector2i in piece.cells:
		var to := cell + at
		if map.in_bounds(to):
			cells[to] = piece.cells[cell]
			heights[to] = int(piece.heights.get(cell, 0))
			covers.append(to)
	for y in piece.size.y:
		for x in piece.size.x:
			for side in [Terrain.EAST, Terrain.SOUTH]:
				var key := Vector3i(x, y, side)
				if not piece.edge_in_bounds(key):
					continue
				var ends := Terrain.edge_cells(key)
				if piece.cell(ends[0]) == "void" and piece.cell(ends[1]) == "void":
					continue
				var moved := Vector3i(x + at.x, y + at.y, side)
				if map.edge_in_bounds(moved):
					edges[moved] = piece.edge(key)
	var shift := func(cell: Vector2i) -> Variant:
		return cell + at if map.in_bounds(cell + at) else null
	var moved_config := LevelMap.moved_config(prefab["config"], shift)
	var out := {"cells": cells, "edges": edges, "heights": heights, "covers": covers,
		"entries": moved_config.get("entities", []), "links": moved_config.get("links", [])}
	# Places, and a copy's spawn points and markets (decision 516): the
	# map's with the prefab's added, a taken name _2, _3...
	for named: String in ["places", "spawn_points", "markets"]:
		var listed: Variant = moved_config.get(named, {})
		if listed is Dictionary and not listed.is_empty():
			var merged: Dictionary = (config.get(named, {}) as Dictionary).duplicate(true) if config.get(named) is Dictionary else {}
			for key: String in listed:
				var free := key
				var n := 2
				while merged.has(free):
					free = "%s_%d" % [key, n]
					n += 1
				merged[free] = listed[key]
			var named_changed: Dictionary = out.get("config", {})
			named_changed[named] = merged
			out["config"] = named_changed
	# A copy's starts, added where the map has none, and its streams.
	var starts: Variant = moved_config.get("starts", [])
	if starts is Array and not starts.is_empty():
		var all_starts: Array = (config.get("starts", []) as Array).duplicate(true) if config.get("starts") is Array else []
		for start: Variant in starts:
			if not all_starts.any(func(had: Variant) -> bool: return Level._tile(had) == Level._tile(start)):
				all_starts.append(start)
		var starts_changed: Dictionary = out.get("config", {})
		starts_changed["starts"] = all_starts
		out["config"] = starts_changed
	var streams: Variant = moved_config.get("streams", [])
	if streams is Array and not streams.is_empty():
		var all_streams: Array = (config.get("streams", []) as Array).duplicate(true) if config.get("streams") is Array else []
		all_streams.append_array(streams)
		var streams_changed: Dictionary = out.get("config", {})
		streams_changed["streams"] = all_streams
		out["config"] = streams_changed
	# Buildings: the map's, but for those whose footprint the prefab's cells
	# land on, and the prefab's, moved.
	var landed: Dictionary[Vector2i, bool] = {}
	for cell in covers:
		landed[cell] = true
	var had: Array = config.get("buildings", []) if config.get("buildings") is Array else []
	var buildings := had.filter(func(entry: Variant) -> bool:
		var rect: Variant = Level.building_rect(entry)
		return rect == null or Level._union(Level.building_blocks(entry)).all(func(cell: Vector2i) -> bool: return not landed.has(cell)))
	buildings.append_array(moved_config.get("buildings", []))
	if buildings.size() != had.size() or not moved_config.get("buildings", []).is_empty():
		var changed: Dictionary = out.get("config", {})
		changed["buildings"] = buildings.duplicate(true)
		out["config"] = changed
	# Roofs as buildings are.
	var had_roofs: Array = config.get("roofs", []) if config.get("roofs") is Array else []
	var roofs := had_roofs.filter(func(entry: Variant) -> bool:
		var rect: Variant = Level.town_wall_rect(entry)
		return rect == null or Level.rect_cells(rect).all(func(cell: Vector2i) -> bool: return not landed.has(cell)))
	roofs.append_array(moved_config.get("roofs", []))
	if roofs.size() != had_roofs.size() or not moved_config.get("roofs", []).is_empty():
		var changed: Dictionary = out.get("config", {})
		changed["roofs"] = roofs.duplicate(true)
		out["config"] = changed
	return out


## Reads prefab [param prefab_name] ({} if there is none): a saved one,
## else a kind's (kind_prefab).
static func load_prefab(prefab_name: String, dir := DIR) -> Dictionary:
	var folder := dir + prefab_name + "/"
	var image := Level._image(folder + "layout.png") if FileAccess.file_exists(folder + "layout.png") else null
	if image == null:
		return kind_prefab(prefab_name)
	var config := {}
	if FileAccess.file_exists(folder + "level.json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder + "level.json"))
		if parsed is Dictionary:
			config = parsed
	var map := LevelMap.from_image(image, config)
	map.read_heights(Level._image(folder + "height.png"))
	return {"map": map, "config": config}


## Writes [param prefab] as prefab [param prefab_name]: layout.png (and
## height.png if it has heights) with .imports as Image, and level.json.
## OK, or the error.
static func save(prefab_name: String, prefab: Dictionary, dir := DIR) -> Error:
	var folder := dir + prefab_name + "/"
	var path := ProjectSettings.globalize_path(folder)
	DirAccess.make_dir_recursive_absolute(path)
	var map: LevelMap = prefab["map"]
	var error := map.to_image().save_png(path.path_join("layout.png"))
	if error != OK:
		return error
	LevelMap.ensure_image_import(path.path_join("layout.png"), folder + "layout.png")
	if not map.heights.is_empty():
		error = map.to_height_image().save_png(path.path_join("height.png"))
		if error != OK:
			return error
		LevelMap.ensure_image_import(path.path_join("height.png"), folder + "height.png")
	elif FileAccess.file_exists(folder + "height.png"):
		DirAccess.remove_absolute(path.path_join("height.png"))
		DirAccess.remove_absolute(path.path_join("height.png.import"))
	var json := FileAccess.open(path.path_join("level.json"), FileAccess.WRITE)
	if json == null:
		return FileAccess.get_open_error()
	json.store_string(JSON.stringify(prefab["config"], "\t", false) + "\n")
	json.close()
	return OK


## A prefab's name made safe for a folder: lower case, letters, digits and
## underscores ("" if nothing is left).
static func tidy_name(text: String) -> String:
	var out := ""
	for c in text.strip_edges().to_lower().replace(" ", "_").replace("-", "_"):
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_":
			out += c
	return out
