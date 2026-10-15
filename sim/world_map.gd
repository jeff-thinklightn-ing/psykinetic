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
## them: key -> {key, cell, name, kind, radius, worth, holder}), buildings (as
## Level reads them, with their use and town), and, for walking it
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
		"places": level["places"], "buildings": level["buildings"],
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
## Each way out of [param area_name] and where its target lies against it,
## for drawing what is beyond a border (terrain's glimpse, decision 325): one entry a
## link or neighbour whose target is a level here, {kind ("link" | "edge"),
## to_map, from_cell (a link's marker; an edge's: none), side (an edge's
## side; a link's: ""), to_cell (where a link arrives: its spawn point, else
## the target's first start; an edge's: none), out (away from our land),
## to_ours (a Transform2D taking the target's cells into ours), one_way
## (nothing leads back)}. A neighbour abuts as arrival() has it: the same row
## or column, the target's opposite edge next to ours. A link's target is
## turned to face us by the edge its arrival is nearest: that edge put
## [param gap] cells beyond our land along out (where the floor ends going
## out from the marker, not the map's edge: void past the land is not
## crossed), the arrival across from our marker. Cells, not levels' "north": arrival ignores it too, so the two
## always agree.
func ways_out(area_name: String, gap := 3) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not areas.has(area_name):
		return out
	var size: Vector2i = areas[area_name]["size"]
	for way in ways_from(area_name):
		var to: String = way["to"]
		if not areas.has(to):
			continue
		var to_size: Vector2i = areas[to]["size"]
		var back := ways_from(to).any(func(other: Dictionary) -> bool: return other["to"] == area_name)
		var entry := {"kind": way["kind"], "to_map": to, "from_cell": null, "side": way["side"], "to_cell": null,
			"one_way": bool(way["one_way"]) or not back}
		var shift := Vector2i.ZERO
		if way["kind"] == "edge":
			var side: String = way["side"]
			entry["out"] = Level.SIDES[side]
			shift = {"east": Vector2i(size.x, 0), "west": Vector2i(-to_size.x, 0),
				"south": Vector2i(0, size.y), "north": Vector2i(0, -to_size.y)}[side]
		else:
			var marker: Vector2i = way["at"]
			var spawns: Dictionary = areas[to]["spawn_points"]
			var starts: Array = areas[to]["starts"]
			var arrive: Vector2i = spawns.get(way["to_spawn"], starts[0] if not starts.is_empty() else Vector2i.ZERO)
			# The target's edge nearest where one arrives faces our land.
			var near := {"north": arrive.y, "south": to_size.y - 1 - arrive.y, "west": arrive.x, "east": to_size.x - 1 - arrive.x}
			var facing := "south"
			for side: String in near:
				if near[side] < near[facing]:
					facing = side
			var away: Vector2i = -Level.SIDES[facing]
			entry["out"] = away
			entry["from_cell"] = marker
			entry["to_cell"] = arrive
			# Our land's last cell going out from the marker.
			var floor_cells: Dictionary = areas[area_name]["floor"]
			var land := marker
			while floor_cells.has(land + away):
				land += away
			# That edge's row or column lands gap cells past it, the arrival across from the marker.
			match facing:
				"south":
					shift = Vector2i(marker.x - arrive.x, land.y - 1 - gap - (to_size.y - 1))
				"north":
					shift = Vector2i(marker.x - arrive.x, land.y + 1 + gap)
				"east":
					shift = Vector2i(land.x - 1 - gap - (to_size.x - 1), marker.y - arrive.y)
				"west":
					shift = Vector2i(land.x + 1 + gap, marker.y - arrive.y)
		entry["to_ours"] = Transform2D(0.0, Vector2(shift))
		out.append(entry)
	return out


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


## The world's own settings: levels/world_map.json, {"start": {"zone":
## <name>}} (decision 300). A test scene (run from tests/) plays on its own
## fixtures and sees none, unless it points this at a file of its own.
static var settings_path := "" if _in_test_scene() else "res://levels/world_map.json"


## Whether this process runs a scene under tests/ (tests/run.sh's --scene).
static func _in_test_scene() -> bool:
	var args := OS.get_cmdline_args()
	var at := args.find("--scene")
	return at >= 0 and at + 1 < args.size() and args[at + 1].trim_prefix("res://").begins_with("tests/")


## The zone new players start in: world_map.json's start, or "" when it
## names none (Main then falls back to Level.DEFAULT_MAP). A player with a
## record goes back to their own zone, wherever that is.
static func start_zone() -> String:
	if settings_path.is_empty() or not FileAccess.file_exists(settings_path):
		return ""
	var read: Variant = JSON.parse_string(FileAccess.get_file_as_string(settings_path))
	if not read is Dictionary:
		return ""
	var start: Variant = (read as Dictionary).get("start", {})
	return str((start as Dictionary).get("zone", "")) if start is Dictionary else ""


## Where the world is measured from: the start zone, else Level.DEFAULT_MAP.
static func root() -> String:
	var start := start_zone()
	return start if not start.is_empty() else Level.DEFAULT_MAP


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
## [] when nothing is. Unreachable means not from [param from] (the start
## zone, else the default map: root()), or no way back to it. A start zone
## must be a level with starts. Places are checked against
## [param factions] (levels/factions.json by default).
func problems(from := "", factions: Factions = null) -> Array[String]:
	var out: Array[String] = []
	if factions == null:
		factions = Factions.read()
	var start := start_zone()
	if not start.is_empty() and from.is_empty():
		if not areas.has(start):
			out.append("world_map.json: the start zone %s is not a level" % start)
		elif (areas[start]["warnings"] as Array).any(func(warning: String) -> bool: return warning.begins_with("no player start")):
			# Level.parse stands the first floor cell in; not for where everyone begins.
			out.append("%s: it is the start zone (world_map.json) but has no starts" % start)
	var root := from if not from.is_empty() else root()
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
