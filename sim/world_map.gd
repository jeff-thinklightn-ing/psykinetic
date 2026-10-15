class_name WorldMap
extends RefCounted
## The world map: every area (a level) and the ways between them, read from
## the levels themselves, so there is no second file to keep in step. A way
## is a point link (a link marker and its entry in level.json "links") or an
## edge link (level.json "neighbours": walk off one edge, arrive at the
## matching edge of the next area). Needs no scene and no GUI: the editor's
## node map, the builder and the world tick all take it from build().

## Area name -> {name, display_name, size (cells), starts, spawn_points,
## links (as Level reads them), neighbours (side -> area), warnings (the
## level's load warnings), floor (cell -> true), places (as Level reads
## them: key -> {key, cell, name, kind, radius, worth, holder}), and, for walking it
## (WorldRoutes), edges, heights and stairs as Level's terrain has them}.
var areas: Dictionary[String, Dictionary] = {}
## Every way out of every area, in area order: {from, to, kind ("link" or
## "edge"), at (the link's cell; Vector2i.ZERO for an edge), side (the
## edge, "" for a link), to_spawn ("" for an edge), one_way}.
var ways: Array[Dictionary] = []
## What config each area was read with (level.json), for the cell check.
var _configs: Dictionary[String, Dictionary] = {}
var _routes: WorldRoutes = null


## The world map of the levels [param names] (every level by default),
## with [param sources] (area name -> {layout, height, config}, as
## Level.source gives them) read in place of the files: levels being
## edited and not saved yet.
static func build(names: Array[String] = Level.names(), sources: Dictionary = {}) -> WorldMap:
	var out := WorldMap.new()
	for area_name in names:
		out._read(area_name, sources[area_name] if sources.has(area_name) else Level.source(area_name))
	return out


## Each area as last read: name -> {digest (of its layout, height and
## config), area, ways}. A build reads again only the levels that changed
## (an accept parses the one edited, not the whole world: decision 303);
## what is kept is shared by every build, so it is never changed, only
## read: WorldRoutes copies floor and edges, Holdings.rebind each place.
static var _read_before: Dictionary[String, Dictionary] = {}


func _read(area_name: String, made: Dictionary) -> void:
	var layout: Image = made["layout"]
	if layout == null:
		return
	var config: Dictionary = made["config"]
	var digest := _digest(layout, made["height"], config)
	var before: Dictionary = _read_before.get(area_name, {})
	if before.get("digest", "") != digest:
		before = {"digest": digest, "area": {}, "ways": []}
		var ways_before := ways
		ways = []
		_parse_area(area_name, layout, made["height"], config)
		before["area"] = areas[area_name]
		before["ways"] = ways
		ways = ways_before
		_read_before[area_name] = before
	areas[area_name] = before["area"].duplicate()
	_configs[area_name] = config
	for way: Dictionary in before["ways"]:
		ways.append(way.duplicate())


## What [param layout], [param height] and [param config] are, as a string:
## the same for the same level, another for any change to it.
static func _digest(layout: Image, height: Image, config: Dictionary) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_MD5)
	for image: Image in [layout, height]:
		if image == null:
			hashing.update("none".to_utf8_buffer())
			continue
		hashing.update(("%s %d" % [image.get_size(), image.get_format()]).to_utf8_buffer())
		hashing.update(image.get_data())
	hashing.update(var_to_str(config).to_utf8_buffer())
	return hashing.finish().hex_encode()


func _parse_area(area_name: String, layout: Image, height: Image, config: Dictionary) -> void:
	var level := Level.parse(layout, height, config)
	var floor_cells: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in level["terrain"]["floor"]:
		floor_cells[cell] = true
	for cell: Vector2i in level["terrain"]["stairs"]:
		floor_cells[cell] = true
	areas[area_name] = {
		"name": area_name, "display_name": str(level.get("display_name", "")),
		"size": Vector2i((layout.get_width() + 1) / 2, (layout.get_height() + 1) / 2),
		"starts": level["starts"], "spawn_points": level["spawn_points"], "links": level["links"],
		"neighbours": level["neighbours"], "warnings": level["warnings"], "floor": floor_cells,
		"edges": level["terrain"]["edges"], "heights": level["terrain"]["heights"], "stairs": level["terrain"]["stairs"],
		"places": level["places"],
	}
	_configs[area_name] = config
	for link: Dictionary in level["links"]:
		ways.append({"from": area_name, "to": link["to_map"], "kind": "link", "at": link["tile"], "side": "",
			"to_spawn": link["to_spawn"], "one_way": link["one_way"]})
	var neighbours: Dictionary[String, String] = level["neighbours"]
	for side: String in neighbours:
		ways.append({"from": area_name, "to": neighbours[side], "kind": "edge", "at": Vector2i.ZERO, "side": side,
			"to_spawn": "", "one_way": false})


## Where a step from [param cell] by [param direction] in
## [param area_name] goes when it leaves the map across an edge that has a
## neighbour: {to (the area), side, at (the matching cell on the
## neighbour's opposite edge: WorldMap.arrival)}; {} when the step stays on
## the map, or that edge has no neighbour (or one that is no level here).
## Needs no player and no zone: the world tick moves groups with it too.
func crossing(area_name: String, cell: Vector2i, direction: Vector2i) -> Dictionary:
	var area: Dictionary = areas.get(area_name, {})
	if area.is_empty():
		return {}
	var to_cell := cell + direction
	var side := side_off(area["size"], to_cell)
	var to: String = area["neighbours"].get(side, "")
	if side.is_empty() or not areas.has(to):
		return {}
	return {"to": to, "side": side, "at": arrival(side, to_cell, areas[to]["size"])}


## The edge of a map [param size] cells across that [param cell] is beyond
## ("north", "east", "south", "west"), or "" for a cell on the map. A cell
## past a corner is east or west of it.
static func side_off(size: Vector2i, cell: Vector2i) -> String:
	if cell.x < 0:
		return "west"
	if cell.x >= size.x:
		return "east"
	if cell.y < 0:
		return "north"
	if cell.y >= size.y:
		return "south"
	return ""


## Where a step off the [param side] edge into [param cell] (a cell just
## beyond it) arrives on a neighbour [param to_size] cells across: on its
## opposite edge, at the same row (east, west) or column (north, south),
## kept on the map when the neighbour is shorter.
static func arrival(side: String, cell: Vector2i, to_size: Vector2i) -> Vector2i:
	var last := to_size - Vector2i.ONE
	match side:
		"east":
			return Vector2i(0, clampi(cell.y, 0, last.y))
		"west":
			return Vector2i(last.x, clampi(cell.y, 0, last.y))
		"south":
			return Vector2i(clampi(cell.x, 0, last.x), 0)
		"north":
			return Vector2i(clampi(cell.x, 0, last.x), last.y)
	return cell


## Makes [param a] and [param b] (levels being edited) neighbours across
## [param a]'s [param side]: b on a's side, a on b's opposite side, each
## replacing what was there. Returns what to give unjoin's opposite,
## put_neighbours, to undo it: {a: a's neighbours before, b: b's}. Marks
## both level.json as changed; saving is the caller's.
static func join(a: MapDoc, side: String, b: MapDoc) -> Dictionary:
	var before := {"a": neighbours_of(a).duplicate(), "b": neighbours_of(b).duplicate()}
	var a_side := neighbours_of(a)
	a_side[side] = doc_name(b)
	put_neighbours(a, a_side)
	var b_side := neighbours_of(b)
	b_side[Level.OPPOSITE[side]] = doc_name(a)
	put_neighbours(b, b_side)
	return before


## Takes [param a]'s [param side] neighbour away, and [param b]'s opposite
## one where it is [param a]. Returns what was there, as join does.
static func unjoin(a: MapDoc, side: String, b: MapDoc) -> Dictionary:
	var before := {"a": neighbours_of(a).duplicate(), "b": neighbours_of(b).duplicate()}
	var a_side := neighbours_of(a)
	a_side.erase(side)
	put_neighbours(a, a_side)
	var b_side := neighbours_of(b)
	if b_side.get(Level.OPPOSITE[side], "") == doc_name(a):
		b_side.erase(Level.OPPOSITE[side])
	put_neighbours(b, b_side)
	return before


## [param doc]'s level.json "neighbours" ({} for none), a copy.
static func neighbours_of(doc: MapDoc) -> Dictionary:
	var listed: Variant = doc.config.get("neighbours", {})
	return (listed as Dictionary).duplicate() if listed is Dictionary else {}


## Sets [param doc]'s level.json "neighbours" ({} takes the key out).
static func put_neighbours(doc: MapDoc, neighbours: Dictionary) -> void:
	if neighbours.is_empty():
		doc.config.erase("neighbours")
	else:
		doc.config["neighbours"] = neighbours.duplicate()
	doc.config_dirty = true
	doc.dirty = true


## The level name a MapDoc is for: its folder's name.
static func doc_name(doc: MapDoc) -> String:
	return doc.folder.trim_suffix("/").get_file()


## Routing between areas over this map (WorldRoutes), made the first time
## it is asked for: a WorldMap built again (a level edited) makes its own.
func routes() -> WorldRoutes:
	if _routes == null:
		_routes = WorldRoutes.new(self)
	return _routes


## The ways out of [param area_name].
func ways_from(area_name: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(ways.filter(func(way: Dictionary) -> bool: return way["from"] == area_name))
	return out


## The ways into [param area_name].
func ways_into(area_name: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(ways.filter(func(way: Dictionary) -> bool: return way["to"] == area_name))
	return out


## The areas [param from] leads to, itself included, nearest first;
## [param backwards] follows the ways the other way round (the areas that
## lead to it).
func reachable(from: String, backwards := false) -> Array[String]:
	var seen: Array[String] = []
	if areas.has(from):
		seen.append(from)
	var next := 0
	while next < seen.size():
		var here := seen[next]
		next += 1
		for way: Dictionary in ways:
			var there: String = way["from"] if backwards else way["to"]
			if (way["to"] if backwards else way["from"]) == here and areas.has(there) and there not in seen:
				seen.append(there)
	return seen


## What is wrong with how the areas connect, one line each, "<area>: ...";
## [] when nothing is. Unreachable means not from [param root] (the default
## map), or no way back to it. Places are checked against
## [param factions] (levels/factions.json by default).
func problems(root := Level.DEFAULT_MAP, factions: Factions = null) -> Array[String]:
	var out: Array[String] = []
	if factions == null:
		factions = Factions.read()
	for area_name: String in areas:
		var area: Dictionary = areas[area_name]
		for warning: String in area["warnings"]:
			out.append("%s: %s" % [area_name, warning])
		_check_cells(area_name, out)
		_check_places(area_name, factions, out)
	for way: Dictionary in ways:
		_check_way(way, out)
	if areas.has(root):
		var there := reachable(root)
		var back := reachable(root, true)
		for area_name: String in areas:
			if area_name not in there:
				out.append("%s: cannot be reached from %s" % [area_name, root])
			elif area_name not in back:
				out.append("%s: has no way back to %s" % [area_name, root])
	return out


## Cells in level.json that are off the map (every cell a resize would
## move: LevelMap.moved_config), and spawn points and starts on no floor.
func _check_cells(area_name: String, out: Array[String]) -> void:
	var area: Dictionary = areas[area_name]
	var size: Vector2i = area["size"]
	var off: Array[String] = []
	LevelMap.moved_config(_configs[area_name], func(at: Vector2i) -> Variant:
		return at if Rect2i(Vector2i.ZERO, size).has_point(at) else null, 0, off)
	for what in off:
		out.append("%s: %s is off the %d x %d map" % [area_name, what, size.x, size.y])
	var floor_cells: Dictionary = area["floor"]
	var spawn_points: Dictionary = area["spawn_points"]
	var on_map := Rect2i(Vector2i.ZERO, size)
	for spawn_name: String in spawn_points:
		if on_map.has_point(spawn_points[spawn_name]) and not floor_cells.has(spawn_points[spawn_name]):
			out.append("%s: spawn point %s at %s is on no floor" % [area_name, spawn_name, spawn_points[spawn_name]])
	for start: Vector2i in area["starts"]:
		if on_map.has_point(start) and not floor_cells.has(start):
			out.append("%s: the start at %s is on no floor" % [area_name, start])


## Places on no floor, and held by no faction there is.
func _check_places(area_name: String, factions: Factions, out: Array[String]) -> void:
	var area: Dictionary = areas[area_name]
	var floor_cells: Dictionary = area["floor"]
	var size: Vector2i = area["size"]
	for key: String in area["places"]:
		var place: Dictionary = area["places"][key]
		if Rect2i(Vector2i.ZERO, size).has_point(place["cell"]) and not floor_cells.has(place["cell"]):
			out.append("%s: the place %s at %s is on no floor" % [area_name, key, place["cell"]])
		if not factions.has(place["holder"]):
			out.append("%s: the place %s is held by %s, which is no faction (%s, or nobody)" % [
				area_name, key, place["holder"], ", ".join(factions.names())])


func _check_way(way: Dictionary, out: Array[String]) -> void:
	var from: String = way["from"]
	var to: String = way["to"]
	var what := "the link at %s" % way["at"] if way["kind"] == "link" else "the %s neighbour" % way["side"]
	if to.is_empty():
		out.append("%s: %s goes to no area" % [from, what])
		return
	if not areas.has(to):
		out.append("%s: %s goes to %s, which is no level" % [from, what, to])
		return
	var target: Dictionary = areas[to]
	if way["kind"] == "edge":
		var side: String = way["side"]
		var back: Dictionary = target["neighbours"]
		if back.get(Level.OPPOSITE[side], "") != from:
			out.append("%s: %s is %s, but %s's %s neighbour is not %s" % [from, what, to, to, Level.OPPOSITE[side], from])
		return
	var to_spawn: String = way["to_spawn"]
	if not to_spawn.is_empty() and not target["spawn_points"].has(to_spawn):
		out.append("%s: %s goes to spawn point %s, which %s does not have" % [from, what, to_spawn, to])
	if not way["one_way"] and ways.all(func(other: Dictionary) -> bool: return other["from"] != to or other["to"] != from):
		out.append("%s: %s goes to %s, with no way back (\"one_way\": true if that is meant)" % [from, what, to])
