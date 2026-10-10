class_name Level
extends RefCounted
## A level is a folder, levels/<name>/, of:
##
##   layout.png   the map, in double resolution (as Terrain's ASCII maps
##                are): the pixel at (2x, 2y) is cell (x, y); the pixel at
##                (2x + 1, 2y) the edge east of it, (2x, 2y + 1) the edge
##                south of it; (odd, odd) pixels are corners and ignored.
##                Each pixel is a colour from the legend (docs/levels.md).
##   height.png   optional, the same size: a cell pixel's grey is its height,
##                level n = grey n * 40 (0..240), 0..6 levels.
##   level.json   name; legend overrides; the entities' names and props by
##                tile; the start order; named spawn points; level links.
##
## A cell pixel is ground (stone, grass, dirt), fire, water, a stair, void
## (also any pixel more than half transparent), or a marker: a player start,
## a monster spawn by type, a crate, a boulder, a cart, a chest, a torch, a
## level link; a marker's cell is ground of the kind most of its neighbours are.
## An edge pixel is a wall or a door, or open: a wall pixel between two
## walkable cells is a thin wall on that edge, and an edge between a
## walkable cell and void is a wall whatever its pixel says (the outer
## wall), so a map may draw its outline in wall pixels or leave it out; a
## wall or door pixel on a cell position is void. (These are Terrain's
## ASCII rules, pixel for character.) Water is not walkable, but it is
## no wall: nothing is built along it, and sight passes over it.
##
## load() reads a level into {name, terrain, entities, starts, spawn_points,
## links, centre, warnings}; terrain is what World.load_terrain and the
## views take: floor, fire, edges (as Terrain.parse), and kinds (cell ->
## "stone" | "grass" | "dirt"), water, heights (cell -> 1..6; 0 is left
## out), stairs (cell -> the direction it climbs), torches.

const DIR := "res://levels/"
const DEFAULT_MAP := "test_room"
## Grey per height level in height.png.
const GREY_PER_LEVEL := 40
const MAX_HEIGHT := 6

const MONSTER := "res://sim/monster.gd"
const PUSHABLE := "res://sim/pushable.gd"
const CHEST := "res://sim/chest.gd"

## The default legend: a meaning per colour (hex, RGB). level.json "legend"
## overrides or adds ({"wall": "#402a20", "monster_wraith": "#c0c0ff"}).
const LEGEND := {
	"void": "#000000",
	"stone": "#9a9a9a",
	"grass": "#4f9a3c",
	"dirt": "#8a6440",
	"water": "#2f6fd0",
	"fire": "#ff6a00",
	"wall": "#3c2a22",
	"door": "#c88a3c",
	"stair": "#e8d44a",
	"start": "#00ffff",
	"monster_imp": "#ff3030",
	"monster_brute": "#a00000",
	"monster_sneak": "#ff80a0",
	"crate": "#f0b070",
	"boulder": "#5a5a78",
	"cart": "#7a3cb4",
	"chest": "#8c4a1c",
	"torch": "#ffe000",
	"lantern": "#fff0b0",
	"link": "#ff00ff",
}
const GROUNDS: Array[String] = ["stone", "grass", "dirt"]
const MARKERS: Array[String] = ["start", "crate", "boulder", "cart", "chest", "torch", "lantern", "link"]
## level.json "north": which way in layout.png is north.
const NORTHS := {"up": Vector2i(0, -1), "down": Vector2i(0, 1), "left": Vector2i(-1, 0), "right": Vector2i(1, 0)}
## What a marker spawns, before level.json's props for that tile.
const MONSTER_TYPES := {
	"imp": {"mass": 40.0},
	"brute": {"mass": 70.0},
	"sneak": {"mass": 25.0},
}
const CRATE := {"script": PUSHABLE, "shape": "cube", "tint": Color(0.8, 0.6, 0.35)}
const BOULDER := {"script": PUSHABLE, "shape": "sphere", "tint": Color(0.55, 0.55, 0.6),
	"props": {"mass": 200.0, "body_material": GridEntity.BodyMaterial.STONE}}
const CART := {"script": PUSHABLE, "shape": "slab", "tint": Color(0.55, 0.4, 0.25), "props": {"mass": 60.0}}
## Empty; level.json's props say what is in it ({"slots": ["bandaging_kit"]}).
const CHEST_SPEC := {"script": CHEST, "shape": "cube", "tint": Color(0.5, 0.28, 0.12)}

## Levels made in code (tests): name -> {layout: Image, height: Image or
## null, config: Dictionary}; load() takes these before the folder.
static var _registered: Dictionary[String, Dictionary] = {}


## Makes a level from images and a config, without files (tests).
static func register(level_name: String, layout: Image, height: Image = null, config := {}) -> void:
	_registered[level_name] = {"layout": layout, "height": height, "config": config}


static func unregister(level_name: String) -> void:
	_registered.erase(level_name)


## Whether there is a level called [param level_name].
static func exists(level_name: String) -> bool:
	return _registered.has(level_name) or ResourceLoader.exists(DIR + level_name + "/layout.png")


## Reads level [param level_name] (see the class doc). {} with a warning
## printed when there is none.
static func load_level(level_name: String) -> Dictionary:
	var layout: Image = null
	var height: Image = null
	var config := {}
	if _registered.has(level_name):
		var made: Dictionary = _registered[level_name]
		layout = made["layout"]
		height = made["height"]
		config = made["config"]
	else:
		var folder := DIR + level_name + "/"
		layout = _image(folder + "layout.png")
		height = _image(folder + "height.png")
		if FileAccess.file_exists(folder + "level.json"):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder + "level.json"))
			if parsed is Dictionary:
				config = parsed
			else:
				push_warning("[level] %slevel.json is not a JSON object" % folder)
	if layout == null:
		push_warning("[level] no level %s (%slayout.png)" % [level_name, DIR + level_name + "/"])
		return {}
	var level := parse(layout, height, config)
	level["name"] = level_name
	for warning: String in level["warnings"]:
		push_warning("[level] %s: %s" % [level_name, warning])
	return level


## An image as imported (the "image" importer, so it loads on a headless
## server too), or, in the project, the file itself; null if neither. Run
## from the project (the editor's build) the file itself wins, so a map
## the level editor has just saved plays without a reimport.
static func _image(path: String) -> Image:
	if OS.has_feature("editor") and FileAccess.file_exists(path):
		var fresh := Image.load_from_file(ProjectSettings.globalize_path(path))
		if fresh != null:
			return fresh
	if ResourceLoader.exists(path):
		var resource: Resource = load(path)
		if resource is Image:
			return resource
		if resource is Texture2D:
			return (resource as Texture2D).get_image()
	if FileAccess.file_exists(path):
		return Image.load_from_file(ProjectSettings.globalize_path(path))
	return null


## The legend in use: colour (RGB8 as int) -> meaning.
static func legend(config: Dictionary) -> Dictionary[int, String]:
	var by_colour: Dictionary[int, String] = {}
	var meanings := LEGEND.duplicate()
	var overrides: Variant = config.get("legend", {})
	if overrides is Dictionary:
		for meaning: String in overrides:
			meanings[meaning] = str(overrides[meaning])
	for meaning: String in meanings:
		by_colour[_rgb(Color(str(meanings[meaning])))] = meaning
	return by_colour


static func _rgb(colour: Color) -> int:
	return (colour.r8 << 16) | (colour.g8 << 8) | colour.b8


## The level in [param layout] (and [param height]) with [param config]:
## see the class doc for what comes back.
static func parse(layout: Image, height: Image, config: Dictionary) -> Dictionary:
	var by_colour := legend(config)
	var warnings: Array[String] = []
	var unknown: Dictionary[int, bool] = {}
	var size := layout.get_size()
	var cells := Vector2i((size.x + 1) / 2, (size.y + 1) / 2)
	var meaning_at := func(pixel: Vector2i) -> String:
		if pixel.x < 0 or pixel.y < 0 or pixel.x >= size.x or pixel.y >= size.y:
			return "void"
		var colour := layout.get_pixelv(pixel)
		if colour.a < 0.5:
			return "void"
		var key := _rgb(colour)
		if not by_colour.has(key):
			unknown[key] = true
			return "void"
		return by_colour[key]
	# Cells.
	var cell_meaning: Dictionary[Vector2i, String] = {}
	for y in cells.y:
		for x in cells.x:
			var meaning: String = meaning_at.call(Vector2i(x, y) * 2)
			if meaning in ["wall", "door"]:
				meaning = "void"
			if meaning != "void":
				cell_meaning[Vector2i(x, y)] = meaning
	var walkable := func(cell: Vector2i) -> bool:
		return cell_meaning.has(cell) and cell_meaning[cell] != "water"
	var floor_tiles: Array[Vector2i] = []
	var fire: Array[Vector2i] = []
	var water: Array[Vector2i] = []
	var kinds: Dictionary[Vector2i, String] = {}
	var markers: Array[Dictionary] = []
	var stair_cells: Array[Vector2i] = []
	var torches: Array[Vector2i] = []
	var lanterns: Array[Vector2i] = []
	for y in cells.y:
		for x in cells.x:
			var cell := Vector2i(x, y)
			if not cell_meaning.has(cell):
				continue
			var meaning: String = cell_meaning[cell]
			if meaning == "water":
				water.append(cell)
				continue
			floor_tiles.append(cell)
			if meaning in GROUNDS:
				kinds[cell] = meaning
				continue
			kinds[cell] = _ground_around(cell, cell_meaning)
			match meaning:
				"fire":
					fire.append(cell)
				"stair":
					stair_cells.append(cell)
				"torch":
					torches.append(cell)
				"lantern":
					lanterns.append(cell)
				_:
					markers.append({"tile": cell, "marker": meaning})
	# Edges: from -1, as in Terrain, so the outline along the top and left is there.
	var edges: Dictionary[Vector3i, int] = {}
	for y in range(-1, cells.y):
		for x in range(-1, cells.x):
			var cell := Vector2i(x, y)
			for side in [Terrain.EAST, Terrain.SOUTH]:
				var key := Vector3i(x, y, side)
				var other: Vector2i = Terrain.edge_cells(key)[1]
				var meaning: String = meaning_at.call(cell * 2 + (Vector2i(1, 0) if side == Terrain.EAST else Vector2i(0, 1)))
				var a_walks: bool = walkable.call(cell)
				var b_walks: bool = walkable.call(other)
				var by_water: bool = cell_meaning.get(cell, "") == "water" or cell_meaning.get(other, "") == "water"
				var kind := Terrain.Edge.OPEN
				if meaning == "door":
					kind = Terrain.Edge.DOOR
				elif meaning == "wall":
					kind = Terrain.Edge.WALL
				elif a_walks != b_walks and not by_water:
					kind = Terrain.Edge.WALL
				if kind != Terrain.Edge.OPEN:
					edges[key] = kind
	# Heights and stairs.
	var heights: Dictionary[Vector2i, int] = {}
	if height != null:
		if height.get_size() != size:
			warnings.append("height.png is %s, layout.png %s: heights ignored" % [height.get_size(), size])
		else:
			for cell: Vector2i in cell_meaning:
				var grey := height.get_pixelv(cell * 2)
				var level := clampi(roundi(grey.r8 / float(GREY_PER_LEVEL)), 0, MAX_HEIGHT)
				if level > 0:
					heights[cell] = level
	var stairs: Dictionary[Vector2i, Vector2i] = {}
	for cell in stair_cells:
		var up: Array[Vector2i] = []
		for direction: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var next := cell + direction
			if walkable.call(next) and heights.get(next, 0) == heights.get(cell, 0) + 1 \
					and not edges.has(Terrain.edge_key(cell, direction)):
				up.append(direction)
		if up.is_empty():
			warnings.append("the stair at %s has no cell one level up beside it: it is floor" % cell)
			continue
		if up.size() > 1:
			warnings.append("the stair at %s could climb %s; it climbs %s" % [cell, up, up[0]])
		stairs[cell] = up[0]
	for key: int in unknown:
		warnings.append("colour #%06x is not in the legend: void" % key)
	var level := {
		"terrain": {
			"floor": floor_tiles, "fire": fire, "edges": edges, "kinds": kinds, "water": water,
			"heights": heights, "stairs": stairs, "torches": torches, "lanterns": lanterns,
			"ambient": clampf(float(config.get("ambient", 1.0)), 0.0, 1.0),
			"north": NORTHS.get(str(config.get("north", "up")), Vector2i(0, -1)),
		},
		"warnings": warnings,
	}
	_place(level, markers, config, warnings)
	return level


## The ground kind most of [param cell]'s four neighbours are (stone if none).
static func _ground_around(cell: Vector2i, cell_meaning: Dictionary[Vector2i, String]) -> String:
	var counts := {}
	for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var meaning: String = cell_meaning.get(cell + direction, "")
		if meaning in GROUNDS:
			counts[meaning] = int(counts.get(meaning, 0)) + 1
	var best := "stone"
	var most := 0
	for kind in GROUNDS:
		if int(counts.get(kind, 0)) > most:
			best = kind
			most = int(counts[kind])
	return best


## The markers as entities, starts, links; level.json says names, props,
## order, spawn points and the camera's first centre.
static func _place(level: Dictionary, markers: Array[Dictionary], config: Dictionary, warnings: Array[String]) -> void:
	var monster_types := MONSTER_TYPES.duplicate(true)
	var extra_types: Variant = config.get("monsters", {})
	if extra_types is Dictionary:
		for type: String in extra_types:
			monster_types[type] = extra_types[type]
	var by_tile: Dictionary[Vector2i, Dictionary] = {}
	for marker in markers:
		by_tile[marker["tile"]] = marker
	# Entities: level.json's list first, in its order, then the rest by scan.
	var entities: Array[Dictionary] = []
	var taken: Dictionary[Vector2i, bool] = {}
	var counts := {}
	var listed: Variant = config.get("entities", [])
	var order: Array[Vector2i] = []
	var overrides: Dictionary[Vector2i, Dictionary] = {}
	if listed is Array:
		for entry: Variant in listed:
			var at: Variant = _tile(entry.get("at") if entry is Dictionary else null)
			if at == null:
				warnings.append("an entity in level.json has no \"at\": [x, y]")
				continue
			if not by_tile.has(at) or not _spawns(str(by_tile[at]["marker"])):
				warnings.append("level.json names an entity at %s, where there is no crate, boulder, cart, chest or monster" % at)
				continue
			order.append(at)
			overrides[at] = entry
	for marker in markers:
		if _spawns(str(marker["marker"])) and not overrides.has(marker["tile"]):
			order.append(marker["tile"])
	for at in order:
		if taken.has(at):
			continue
		taken[at] = true
		var marker: String = by_tile[at]["marker"]
		var spec := _spec_for(marker, monster_types)
		if spec.is_empty():
			warnings.append("no monster type \"%s\" (at %s)" % [marker.trim_prefix("monster_"), at])
			continue
		var base := _base_name(marker)
		counts[base] = int(counts.get(base, 0)) + 1
		spec["name"] = "%s%d" % [base, counts[base]]
		spec["tile"] = at
		var entry: Dictionary = overrides.get(at, {})
		if entry.has("name"):
			spec["name"] = str(entry["name"])
		if entry.has("tint"):
			spec["tint"] = Color(str(entry["tint"]))
		var props: Dictionary = spec.get("props", {}).duplicate()
		var more: Variant = entry.get("props", {})
		if more is Dictionary:
			for key: String in more:
				props[key] = _prop(key, more[key])
		if not props.is_empty():
			spec["props"] = props
		entities.append(spec)
	# Starts: level.json's order, then any other start marker by scan.
	var starts: Array[Vector2i] = []
	var listed_starts: Variant = config.get("starts", [])
	if listed_starts is Array:
		for value: Variant in listed_starts:
			var at: Variant = _tile(value)
			if at != null and at not in starts:
				starts.append(at)
	for marker in markers:
		if marker["marker"] == "start" and marker["tile"] not in starts:
			starts.append(marker["tile"])
	if starts.is_empty():
		warnings.append("no player start: the first floor cell is one")
		var floor_tiles: Array[Vector2i] = level["terrain"]["floor"]
		if not floor_tiles.is_empty():
			starts.append(floor_tiles[0])
	# Named spawn points, for links into this level.
	var spawn_points: Dictionary[String, Vector2i] = {}
	var named: Variant = config.get("spawn_points", {})
	if named is Dictionary:
		for spawn_name: String in named:
			var at: Variant = _tile(named[spawn_name])
			if at != null:
				spawn_points[spawn_name] = at
	# Links, on link markers.
	var links: Array[Dictionary] = []
	var listed_links: Variant = config.get("links", [])
	var link_tiles: Array[Vector2i] = []
	for marker in markers:
		if marker["marker"] == "link":
			link_tiles.append(marker["tile"])
	if listed_links is Array:
		for entry: Variant in listed_links:
			var at: Variant = _tile(entry.get("at") if entry is Dictionary else null)
			if at == null or at not in link_tiles:
				warnings.append("a level link in level.json is not on a link marker (%s)" % [entry])
				continue
			links.append({"tile": at, "to_map": str(entry.get("to_map", "")), "to_spawn": str(entry.get("to_spawn", ""))})
	for at in link_tiles:
		if links.all(func(link: Dictionary) -> bool: return link["tile"] != at):
			warnings.append("the link marker at %s goes nowhere (no entry in level.json \"links\")" % at)
	var centre: Variant = _tile(config.get("centre"))
	level["entities"] = entities
	level["starts"] = starts
	level["spawn_points"] = spawn_points
	level["links"] = links
	level["centre"] = centre if centre != null else starts[0] if not starts.is_empty() else Vector2i.ZERO
	level["display_name"] = str(config.get("name", ""))


static func _spawns(marker: String) -> bool:
	return marker in ["crate", "boulder", "cart", "chest"] or marker.begins_with("monster_")


static func _base_name(marker: String) -> String:
	if marker.begins_with("monster_"):
		return marker.trim_prefix("monster_").capitalize().replace(" ", "")
	return marker.capitalize()


static func _spec_for(marker: String, monster_types: Dictionary) -> Dictionary:
	match marker:
		"crate":
			return CRATE.duplicate(true)
		"boulder":
			return BOULDER.duplicate(true)
		"cart":
			return CART.duplicate(true)
		"chest":
			return CHEST_SPEC.duplicate(true)
	var type := marker.trim_prefix("monster_")
	if not monster_types.has(type):
		return {}
	var props := {}
	var type_props: Variant = monster_types[type]
	if type_props is Dictionary:
		for key: String in type_props:
			props[key] = _prop(key, type_props[key])
	return {"script": MONSTER, "shape": "capsule", "props": props, "kind": type}


## A prop read from JSON: body_material by name, numbers as floats except
## sight_range, slots as a chest's (Items.tidy).
static func _prop(key: String, value: Variant) -> Variant:
	if key == "slots":
		return Items.tidy(value, Chest.SLOTS)
	if key == "body_material" and value is String:
		return GridEntity.BodyMaterial.get(str(value).to_upper(), GridEntity.BodyMaterial.FLESH)
	if key == "sight_range":
		return int(value)
	return value


static func _tile(value: Variant) -> Variant:
	if value is Array and value.size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	return null


# --- Writing ------------------------------------------------------------------

## A layout image from an ASCII map in Terrain's double resolution ("." floor,
## "~" fire, "#" wall, "+" door, anything else void), with [param markers]
## (tile -> legend meaning) on their cells: how the old test room became
## levels/test_room.
static func image_from_rows(rows: Array[String], markers: Dictionary = {}, config := {}) -> Image:
	var width := 1
	for row in rows:
		width = maxi(width, row.length())
	var image := Image.create_empty(width, maxi(rows.size(), 1), false, Image.FORMAT_RGBA8)
	var colour_of := func(meaning: String) -> Color:
		var hex: Variant = config.get("legend", {}).get(meaning, LEGEND[meaning])
		return Color(str(hex))
	image.fill(colour_of.call("void"))
	for y in rows.size():
		for x in rows[y].length():
			var meaning := ""
			match rows[y][x]:
				".": meaning = "stone"
				"~": meaning = "fire"
				"#": meaning = "wall"
				"+": meaning = "door"
			if not meaning.is_empty():
				image.set_pixel(x, y, colour_of.call(meaning))
	for tile: Vector2i in markers:
		image.set_pixelv(tile * 2, colour_of.call(str(markers[tile])))
	return image


## A greyscale height image the size of [param layout] from [param heights]
## (cell -> level).
static func height_image(layout: Image, heights: Dictionary) -> Image:
	var image := Image.create_empty(layout.get_width(), layout.get_height(), false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	for cell: Vector2i in heights:
		var grey := clampi(int(heights[cell]), 0, MAX_HEIGHT) * GREY_PER_LEVEL / 255.0
		image.set_pixelv(cell * 2, Color(grey, grey, grey))
	return image
