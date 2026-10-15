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
##                tile (a monster's facing and idling too); the start order;
##                named spawn points; level links; neighbours (the level
##                across each map edge); places (held by factions);
##                buildings (footprints walked into, roofed).
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
## links, neighbours, places, buildings, centre, size (in cells), warnings}; terrain is what World.load_terrain and the
## views take: floor, fire, edges (as Terrain.parse), and kinds (cell ->
## "stone" | "grass" | "dirt"), water, heights (cell -> 1..6; 0 is left
## out), stairs (cell -> the direction it climbs), torches, buildings (as
## level["buildings"], for the views).

const DIR := "res://levels/"
## Levels edited in the running game (builder mode) are saved here, and a
## level here wins over the same level in DIR: an exported server's res://
## is its read-only pck. Tests point it elsewhere.
const OVERLAY := "user://levels/"
static var overlay_dir := OVERLAY
const DEFAULT_MAP := "test_room"
## Grey per height level in height.png.
const GREY_PER_LEVEL := 40
const MAX_HEIGHT := 6

const MONSTER := "res://sim/monster.gd"
## A wild kind's (Animal, decision 315).
const ANIMAL := "res://sim/animal.gd"
const PUSHABLE := "res://sim/pushable.gd"
const CHEST := "res://sim/chest.gd"
const CARGO := "res://sim/cargo.gd"

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
## Map edges a level can have a neighbour across (level.json "neighbours"),
## each the way off the map it is.
const SIDES := {"north": Vector2i(0, -1), "east": Vector2i(1, 0), "south": Vector2i(0, 1), "west": Vector2i(-1, 0)}
const OPPOSITE := {"north": "south", "east": "west", "south": "north", "west": "east"}
## What a place (level.json "places", Holdings) can be.
const PLACE_KINDS: Array[String] = ["camp", "keep", "farm", "gate", "mine", "stockpile", "other"]
## A place's radius when level.json gives none, in cells.
const PLACE_RADIUS := 8
const NORTHS := {"up": Vector2i(0, -1), "down": Vector2i(0, 1), "left": Vector2i(-1, 0), "right": Vector2i(1, 0)}
## The buildings level.json "buildings" may name (art-kit's building.*
## slots, drawn over the footprint: roof, floor, trim), each its footprint
## in cells, across by deep as it faces north or south (the other way round
## facing east or west). The footprint is the inside; its walls and door
## are the map's own edges on its outline (decision 265).
const BUILDINGS := {"building.hut": Vector2i(3, 3), "building.house": Vector2i(4, 6), "building.shed": Vector2i(2, 3),
	"building.well": Vector2i(1, 1)}
## The buildings that stand on water, not floor: no inside, no walls (a
## well: its water is what stops walkers, and sight passes over it).
const ON_WATER: Array[String] = ["building.well"]
## A building's facing (the side its front is on) when level.json gives none.
const BUILDING_FACING := Vector2i(0, 1)
## The region of a level that names none (region_of).
const DEFAULT_REGION := "town_lands"
## What a marker spawns, before level.json's props for that tile: each
## kind's body, from its row in levels/monsters.json (Monster.kinds), where
## its tactics, idling, doors and temperaments are too: the brute plods and
## hits hard and seldom, the sneak is quick and frail.
static var MONSTER_TYPES: Dictionary = Monster.bodies()
## A crate and a cart carry things (Cargo: 4 and 8); props {"slots": [...]}
## say what is in them, as a chest's. "art": the art slot the 3D view draws
## each of these as once the slot has art of its own (ArtKit; decision 264);
## till then the shape, tinted.
const CRATE := {"script": CARGO, "shape": "cube", "tint": Color(0.8, 0.6, 0.35), "art": "prop.crate", "props": {"capacity": 4}}
const BOULDER := {"script": PUSHABLE, "shape": "sphere", "tint": Color(0.55, 0.55, 0.6), "art": "rock.boulder",
	"props": {"mass": 200.0, "body_material": GridEntity.BodyMaterial.STONE}}
const CART := {"script": CARGO, "shape": "slab", "tint": Color(0.55, 0.4, 0.25), "art": "prop.cart", "props": {"mass": 60.0, "capacity": 8}}
## Empty; level.json's props say what is in it ({"slots": ["bandaging_kit"]}).
const CHEST_SPEC := {"script": CHEST, "shape": "cube", "tint": Color(0.5, 0.28, 0.12), "art": "prop.chest"}
## The idle modes level.json may give a monster (Monster.IDLE_MODES).
const IDLE_MODES: Array[String] = ["guard", "wander", "patrol", "gather", "none"]
## An entity entry of only these keys leaves the spawn order as it was.
const ORDERLESS_KEYS: Array[String] = ["at", "facing", "idle"]

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
	return _registered.has(level_name) or overlaid(level_name) or ResourceLoader.exists(DIR + level_name + "/layout.png")


## Whether level [param level_name] has been edited in the game: its files
## are in the overlay, which wins over DIR.
static func overlaid(level_name: String) -> bool:
	return not level_name.is_empty() and FileAccess.file_exists(overlay_dir + level_name + "/layout.png")


## The folder level [param level_name]'s files are read from: the overlay's
## if it is there, else DIR's.
static func folder_of(level_name: String) -> String:
	return (overlay_dir if overlaid(level_name) else DIR) + level_name + "/"


## The levels in the overlay, sorted.
static func overlay_names() -> Array[String]:
	var out: Array[String] = []
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(overlay_dir)):
		for level_name in DirAccess.get_directories_at(ProjectSettings.globalize_path(overlay_dir)):
			if overlaid(level_name):
				out.append(level_name)
	out.sort()
	return out


## Every level in the game: the folders under levels/ with a layout.png
## (prefabs left out; not the levels made in code), and those in the
## overlay (a level made in the game is only there), sorted.
static func names() -> Array[String]:
	var out: Array[String] = overlay_names()
	for folder in ResourceLoader.list_directory(DIR):
		var level_name := folder.trim_suffix("/")
		if folder.ends_with("/") and level_name != "prefabs" and level_name not in out \
				and ResourceLoader.exists(DIR + level_name + "/layout.png"):
			out.append(level_name)
	out.sort()
	return out


## What level [param level_name] is made of: {layout: Image or null,
## height: Image or null, config: Dictionary}, from the levels made in code
## or the folder (the overlay's first). Warns when level.json is not a JSON object.
static func source(level_name: String) -> Dictionary:
	if _registered.has(level_name):
		return _registered[level_name]
	var folder := folder_of(level_name)
	var config := {}
	if FileAccess.file_exists(folder + "level.json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder + "level.json"))
		if parsed is Dictionary:
			config = parsed
		else:
			push_warning("[level] %slevel.json is not a JSON object" % folder)
	return {"layout": _image(folder + "layout.png"), "height": _image(folder + "height.png"), "config": config}


## Reads level [param level_name] (see the class doc). {} with a warning
## printed when there is none.
static func load_level(level_name: String) -> Dictionary:
	var made := source(level_name)
	var layout: Image = made["layout"]
	if layout == null:
		push_warning("[level] no level %s (%slayout.png)" % [level_name, folder_of(level_name)])
		return {}
	var level := parse(layout, made["height"], made["config"])
	level["name"] = level_name
	level["terrain"]["level"] = level_name
	# A linked building's town by its id, as Towns and Holdings name it.
	for building: Dictionary in level["buildings"]:
		building["town_id"] = "%s/%s" % [level_name, building["town"]] if not building["town"].is_empty() else ""
	for ring: Dictionary in level["town_walls"]:
		ring["town_id"] = "%s/%s" % [level_name, ring["town"]]
	for warning: String in level["warnings"]:
		push_warning("[level] %s: %s" % [level_name, warning])
	return level


## An image as imported (the "image" importer, so it loads on a headless
## server too), or, in the project, the file itself; null if neither. Run
## from the project (the editor's build) the file itself wins, so a map
## the level editor has just saved plays without a reimport.
static func _image(path: String) -> Image:
	if path.begins_with("user://"):
		# The overlay: never imported, so the file itself (load would fail, loudly).
		return Image.load_from_file(ProjectSettings.globalize_path(path)) if FileAccess.file_exists(path) else null
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
	# Read from the raw RGBA bytes, a meaning as a code (its index in
	# names; VOID for void or a colour not in the legend): a 256² level is
	# half a million pixels, too many for a call and a Color each (decision 303).
	var pixels := _rgba8(layout).get_data()
	var names: Array[String] = []
	var code_of: Dictionary[String, int] = {}
	var code_by_colour: Dictionary[int, int] = {}
	for key: int in by_colour:
		var meaning := by_colour[key]
		if meaning == "void":
			code_by_colour[key] = VOID
			continue
		if not code_of.has(meaning):
			code_of[meaning] = names.size()
			names.append(meaning)
		code_by_colour[key] = code_of[meaning]
	var wall: int = code_of.get("wall", -2)
	var door: int = code_of.get("door", -2)
	var water_code: int = code_of.get("water", -2)
	# The meaning of the pixel at (px, py), by code; the last colour looked
	# up is kept, as neighbouring pixels are mostly the same colour.
	var last_colour := -1
	var last_code := VOID
	# Cells, by code, row by row (VOID for void, a wall or door on a cell
	# position, and off the map).
	var cell_codes := PackedInt32Array()
	cell_codes.resize(cells.x * cells.y)
	for y in cells.y:
		for x in cells.x:
			var at := (y * 2 * size.x + x * 2) * 4
			var code := VOID
			if pixels[at + 3] >= 128:
				var colour := (pixels[at] << 16) | (pixels[at + 1] << 8) | pixels[at + 2]
				if colour == last_colour:
					code = last_code
				else:
					code = code_by_colour.get(colour, UNKNOWN)
					if code == UNKNOWN:
						unknown[colour] = true
						code = VOID
					else:
						last_colour = colour
						last_code = code
			if code == wall or code == door:
				code = VOID
			cell_codes[y * cells.x + x] = code
	var floor_tiles: Array[Vector2i] = []
	var fire: Array[Vector2i] = []
	var water: Array[Vector2i] = []
	var kinds: Dictionary[Vector2i, String] = {}
	var markers: Array[Dictionary] = []
	var stair_cells: Array[Vector2i] = []
	var torches: Array[Vector2i] = []
	var lanterns: Array[Vector2i] = []
	var ground: Array[bool] = []
	for meaning in names:
		ground.append(meaning in GROUNDS)
	for y in cells.y:
		for x in cells.x:
			var code := cell_codes[y * cells.x + x]
			if code == VOID:
				continue
			var cell := Vector2i(x, y)
			if code == water_code:
				water.append(cell)
				continue
			floor_tiles.append(cell)
			var meaning := names[code]
			if ground[code]:
				kinds[cell] = meaning
				continue
			kinds[cell] = _ground_around(cell, cell_codes, cells, names)
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
	# Whether each cell is walked on (ground, not water), and water, with a
	# border of void a cell wide all round, so the edges along the outline
	# need no bounds check: cell (x, y) is (x + 1, y + 1) here.
	var across := cells.x + 2
	var walks := PackedByteArray()
	walks.resize(across * (cells.y + 2))
	var wet := PackedByteArray()
	wet.resize(walks.size())
	for y in cells.y:
		for x in cells.x:
			var code := cell_codes[y * cells.x + x]
			if code == water_code:
				wet[(y + 1) * across + x + 1] = 1
			elif code != VOID:
				walks[(y + 1) * across + x + 1] = 1
	# Edges: from -1, as in Terrain, so the outline along the top and left is there.
	var edges: Dictionary[Vector3i, int] = {}
	for y in range(-1, cells.y):
		for x in range(-1, cells.x):
			var here := (y + 1) * across + x + 1
			for side in 2:
				var east := side == 0
				var there: int = here + 1 if east else here + across
				# The edge's pixel: east of the cell's, or south of it.
				var px: int = x * 2 + 1 if east else x * 2
				var py: int = y * 2 if east else y * 2 + 1
				var code := VOID
				if px >= 0 and py >= 0 and px < size.x and py < size.y:
					var at := (py * size.x + px) * 4
					if pixels[at + 3] >= 128:
						var colour := (pixels[at] << 16) | (pixels[at + 1] << 8) | pixels[at + 2]
						if colour == last_colour:
							code = last_code
						else:
							code = code_by_colour.get(colour, UNKNOWN)
							if code == UNKNOWN:
								unknown[colour] = true
								code = VOID
							else:
								last_colour = colour
								last_code = code
				var kind := Terrain.Edge.OPEN
				if code == door:
					kind = Terrain.Edge.DOOR
				elif code == wall:
					kind = Terrain.Edge.WALL
				elif walks[here] != walks[there] and wet[here] == 0 and wet[there] == 0:
					kind = Terrain.Edge.WALL
				if kind != Terrain.Edge.OPEN:
					edges[Vector3i(x, y, Terrain.EAST if east else Terrain.SOUTH)] = kind
	# Heights and stairs.
	var heights: Dictionary[Vector2i, int] = {}
	if height != null:
		if height.get_size() != size:
			warnings.append("height.png is %s, layout.png %s: heights ignored" % [height.get_size(), size])
		else:
			var greys := _rgba8(height).get_data()
			for y in cells.y:
				for x in cells.x:
					if cell_codes[y * cells.x + x] == VOID:
						continue
					var level := clampi(roundi(greys[(y * 2 * size.x + x * 2) * 4] / float(GREY_PER_LEVEL)), 0, MAX_HEIGHT)
					if level > 0:
						heights[Vector2i(x, y)] = level
	var stairs: Dictionary[Vector2i, Vector2i] = {}
	for cell in stair_cells:
		var up: Array[Vector2i] = []
		for direction: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var next := cell + direction
			var next_walks := walks[(next.y + 1) * across + next.x + 1] == 1
			if next_walks and heights.get(next, 0) == heights.get(cell, 0) + 1 and not edges.has(Terrain.edge_key(cell, direction)):
				up.append(direction)
		if up.is_empty():
			warnings.append("the stair at %s has no cell one level up beside it: it is floor" % cell)
			continue
		if up.size() > 1:
			warnings.append("the stair at %s could climb %s; it climbs %s" % [cell, up, up[0]])
		stairs[cell] = up[0]
	for key: int in unknown:
		warnings.append("colour #%06x is not in the legend: void" % key)
	var zone := zone_of(config)
	if config.has("zone") and str(config["zone"]) != zone:
		warnings.append("\"zone\" in level.json is %s: one of %s; it is %s" % [config["zone"], ", ".join(DayNight.ZONES), zone])
	var level := {
		"terrain": {
			"floor": floor_tiles, "fire": fire, "edges": edges, "kinds": kinds, "water": water,
			"heights": heights, "stairs": stairs, "torches": torches, "lanterns": lanterns,
			"ambient": clampf(float(config.get("ambient", DayNight.base_ambient(zone))), 0.0, 1.0),
			"north": NORTHS.get(str(config.get("north", "up")), Vector2i(0, -1)),
			"zone": zone,
			"region": region_of(config, warnings),
			"outdoor": zone == "outdoors",
			# Lit by the sky on the world clock, unless level.json sets its
			# light outright (decision 291).
			"daylight": zone == "outdoors" and not config.has("ambient"),
			# The wall and floor sets it is drawn in (decision 285).
			"walls": str(config.get("walls", "castle")),
			"floors": str(config.get("floors", "castle")),
			# Outdoors, what lies past the forest: "forest", or "none".
			"border": str(config.get("border", "forest")),
		},
		"size": cells,
		"warnings": warnings,
	}
	_place(level, markers, config, warnings)
	level["buildings"] = buildings_from(config, level["terrain"], warnings)
	# The views draw them (roofs, inside floors) from the terrain they are given.
	level["terrain"]["buildings"] = level["buildings"]
	level["town_walls"] = town_walls_from(config, level["terrain"], cells, warnings)
	level["terrain"]["town_walls"] = level["town_walls"]
	return level


## A cell's code in parse: no meaning (void, or off the map).
const VOID := -1
## A colour not in the legend (void, with a warning).
const UNKNOWN := -3


## [param image] as RGBA8: itself if it is, else a copy (the level's own is
## left as it was).
static func _rgba8(image: Image) -> Image:
	if image.get_format() == Image.FORMAT_RGBA8:
		return image
	var copy := image.duplicate() as Image
	if copy.is_compressed():
		copy.decompress()
	copy.convert(Image.FORMAT_RGBA8)
	return copy


## The ground kind most of [param cell]'s four neighbours are (stone if
## none), from parse's [param codes] ([param cells] across) and [param names].
static func _ground_around(cell: Vector2i, codes: PackedInt32Array, cells: Vector2i, names: Array[String]) -> String:
	var counts := {}
	for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var next := cell + direction
		if next.x < 0 or next.y < 0 or next.x >= cells.x or next.y >= cells.y:
			continue
		var code := codes[next.y * cells.x + next.x]
		var meaning := names[code] if code != VOID else ""
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
			# An entry that only says how a monster faces and idles (as the
			# editor writes them) does not move it up the order: its name and
			# slot stay what they were.
			if entry.keys().any(func(key: Variant) -> bool: return str(key) not in ORDERLESS_KEYS):
				order.append(at)
			overrides[at] = entry
	for marker in markers:
		if _spawns(str(marker["marker"])) and marker["tile"] not in order:
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
		if spec.get("script") == MONSTER:
			# Where it lives, whatever tile a snapshot later puts it on.
			spec["home"] = at
			var facing: Variant = facing_from(entry.get("facing"))
			if facing != null:
				spec["facing"] = facing
			if entry.has("idle"):
				var idle := idle_from(entry["idle"], warnings, at)
				if not idle.is_empty():
					spec["idle"] = idle
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
			links.append({"tile": at, "to_map": str(entry.get("to_map", "")), "to_spawn": str(entry.get("to_spawn", "")),
					"one_way": bool(entry.get("one_way", false))})
	for at in link_tiles:
		if links.all(func(link: Dictionary) -> bool: return link["tile"] != at):
			warnings.append("the link marker at %s goes nowhere (no entry in level.json \"links\")" % at)
	var centre: Variant = _tile(config.get("centre"))
	level["neighbours"] = neighbours_from(config, warnings)
	level["places"] = places_from(config, warnings)
	level["entities"] = entities
	level["starts"] = starts
	level["spawn_points"] = spawn_points
	level["links"] = links
	level["centre"] = centre if centre != null else starts[0] if not starts.is_empty() else Vector2i.ZERO
	level["display_name"] = str(config.get("name", ""))


## level.json's "neighbours", {side: map name} ("east": "wilds": walk off
## the east edge, arrive at the west edge of wilds at the same row), with
## sides that are not north, east, south or west said in [param warnings].
static func neighbours_from(config: Dictionary, warnings: Array[String]) -> Dictionary[String, String]:
	var out: Dictionary[String, String] = {}
	var listed: Variant = config.get("neighbours", {})
	if not listed is Dictionary:
		warnings.append("\"neighbours\" in level.json is not an object")
		return out
	for side: Variant in listed:
		if not SIDES.has(str(side)):
			warnings.append("\"neighbours\" has a side %s: north, east, south or west" % [side])
			continue
		var to := str(listed[side])
		if not to.is_empty():
			out[str(side)] = to
	return out


## level.json's "places", key -> {key, cell, name, kind (PLACE_KINDS), radius
## (cells, at least 1), worth (at least 0), holder (who holds it at the
## start; "nobody" if not said)}: the places factions hold (Holdings). An
## entry with no cell, or a kind there is not, is said in [param warnings].
static func places_from(config: Dictionary, warnings: Array[String]) -> Dictionary[String, Dictionary]:
	var out: Dictionary[String, Dictionary] = {}
	var listed: Variant = config.get("places", {})
	if not listed is Dictionary:
		warnings.append("\"places\" in level.json is not an object")
		return out
	for key: Variant in listed:
		var entry: Variant = listed[key]
		var at: Variant = _tile(entry.get("at") if entry is Dictionary else null)
		if at == null:
			warnings.append("the place %s has no \"at\" cell" % [key])
			continue
		var kind := str(entry.get("kind", "other"))
		if kind not in PLACE_KINDS:
			warnings.append("the place %s is a %s: one of %s; it is other" % [key, kind, ", ".join(PLACE_KINDS)])
			kind = "other"
		var radius := int(entry.get("radius", PLACE_RADIUS))
		if radius < 1:
			warnings.append("the place %s has a radius under 1: it is 1" % [key])
		out[str(key)] = {"key": str(key), "cell": at, "name": str(entry.get("name", str(key).capitalize())), "kind": kind,
			"radius": maxi(radius, 1), "worth": maxi(int(entry.get("worth", 1)), 0), "holder": str(entry.get("holder", "nobody"))}
	return out


## What kind of place level.json [param config] is, one of DayNight.ZONES
## (decision 291): its "zone"; else "outdoors" for the older
## "outdoor": true, else "indoors".
static func zone_of(config: Dictionary) -> String:
	var zone := str(config.get("zone", ""))
	if zone in DayNight.ZONES:
		return zone
	return "outdoors" if bool(config.get("outdoor", false)) else "indoors"


## The lore region level.json [param config] is in (its "region": an entry
## of type "region" in levels/lore/regions.json), "town_lands" if it names
## none; one that is no lore region is said in [param warnings] and read
## as town_lands. Weather is chosen by it (Weather).
static func region_of(config: Dictionary, warnings: Array[String] = []) -> String:
	var region := str(config.get("region", DEFAULT_REGION))
	var entry: Variant = Lore.entries().get(region)
	if entry is Dictionary and entry.get("type") == "region":
		return region
	warnings.append("\"region\" in level.json is %s, which is no lore region: it is %s" % [region, DEFAULT_REGION])
	return DEFAULT_REGION


## level.json's "buildings", [{slot, at: its footprint's top-left cell,
## facing: [dx, dy], the side its front is on}], as {slot, cell, facing
## (Vector2i), rect (the footprint, Rect2i), use and town (its link to
## the town's records, "" if none: _link)}. A building stands only on
## floor (water, for ON_WATER's) of one height, clear of the others: one
## that does not, or of a slot there is not, is left out and said in
## [param warnings]; one whose outline has open edges stands, said (a shed
## may be open; a well has no walls).
static func buildings_from(config: Dictionary, terrain: Dictionary, warnings: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var listed: Variant = config.get("buildings", [])
	if not listed is Array:
		warnings.append("\"buildings\" in level.json is not a list")
		return out
	var ground: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in terrain["floor"]:
		ground[cell] = true
	var wet: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in terrain.get("water", []):
		wet[cell] = true
	var taken: Dictionary[Vector2i, bool] = {}
	var linked := {}
	for entry: Variant in listed:
		var rect: Variant = building_rect(entry)
		if rect == null:
			warnings.append("the building %s has no \"at\" cell or no slot of %s" % [entry, ", ".join(BUILDINGS.keys())])
			continue
		var cells := rect_cells(rect)
		var on_water := str(entry["slot"]) in ON_WATER
		var under := wet if on_water else ground
		var height: int = terrain["heights"].get(cells[0], 0)
		var bad := cells.filter(func(cell: Vector2i) -> bool:
			return not under.has(cell) or terrain["heights"].get(cell, 0) != height or taken.has(cell))
		if not bad.is_empty():
			warnings.append("the %s at %s is not all on %s of one height (%s): left out" % [entry["slot"], rect.position, "water" if on_water else "clear floor", bad[0]])
			continue
		for cell in cells:
			taken[cell] = true
		var open: Array[Vector3i] = []
		for key in outline(rect) if not on_water else []:
			if not terrain["edges"].has(key):
				open.append(key)
		if not open.is_empty():
			warnings.append("the %s at %s has %d open edges on its outline (%s)" % [entry["slot"], rect.position, open.size(), open[0]])
		var building := {"slot": str(entry["slot"]), "cell": rect.position, "facing": building_facing(entry), "rect": rect, "use": "", "town": ""}
		_link(building, entry, config, linked, warnings)
		out.append(building)
	return out


## A building entry's link to its town's records ("use": what it is to the
## town, one of the economy's buildings; "town": the stockpile place on this
## map whose town it is), set on [param building] if it holds: the town's
## records (Towns, decision 297) give its state. One that does not is said
## in [param warnings] and the building stands unlinked, as scenery.
static func _link(building: Dictionary, entry: Dictionary, config: Dictionary, linked: Dictionary, warnings: Array[String]) -> void:
	var use := str(entry.get("use", ""))
	var town := str(entry.get("town", ""))
	if use.is_empty() and town.is_empty():
		return
	var at: Vector2i = building["cell"]
	var kinds: Dictionary = Production.read_rules().get("buildings", {})
	if not kinds.has(use):
		warnings.append("the %s at %s is used as \"%s\": one of %s; not linked" % [building["slot"], at, use, ", ".join(kinds.keys())])
		return
	var ignored: Array[String] = []
	var place: Dictionary = places_from(config, ignored).get(town, {})
	if place.get("kind") != "stockpile":
		warnings.append("the %s at %s is in town \"%s\": no stockpile place of that key here; not linked" % [building["slot"], at, town])
		return
	if linked.has(town + "/" + use):
		warnings.append("the %s at %s: %s already has its %s at %s; not linked" % [building["slot"], at, town, use, linked[town + "/" + use]])
		return
	linked[town + "/" + use] = at
	building["use"] = use
	building["town"] = town


## level.json's "town_walls", [{town: a stockpile place's key, rect: [x,
## y, w, h], the cells it encloses}], as {town, rect (Rect2i), walls and
## gates (its outline's wall and door edges, Level.outline)}: which ring of
## the map's walls is a town's wall, its look and strength the town's walls
## level (decision 298). The walls are the layout's own. One whose town is
## no stockpile place here, or has a wall already, or whose rect is not on
## the map, is left out, said in [param warnings]; one whose ring has open
## edges, or that does not hold its place's cell, stands, said.
static func town_walls_from(config: Dictionary, terrain: Dictionary, size: Vector2i, warnings: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var listed: Variant = config.get("town_walls", [])
	if not listed is Array:
		warnings.append("\"town_walls\" in level.json is not a list")
		return out
	var ignored: Array[String] = []
	var places := places_from(config, ignored)
	var walled := {}
	for entry: Variant in listed:
		var town := str(entry.get("town", "")) if entry is Dictionary else ""
		var rect: Variant = town_wall_rect(entry)
		if rect == null or not Rect2i(Vector2i.ZERO, size).encloses(rect):
			warnings.append("the town wall %s has no \"rect\" [x, y, w, h] on the map" % [entry])
			continue
		var place: Dictionary = places.get(town, {})
		if place.get("kind") != "stockpile":
			warnings.append("the town wall at %s is round town \"%s\": no stockpile place of that key here; left out" % [rect.position, town])
			continue
		if walled.has(town):
			warnings.append("the town wall at %s: %s has its wall already; left out" % [rect.position, town])
			continue
		walled[town] = true
		var walls: Array[Vector3i] = []
		var gates: Array[Vector3i] = []
		var open: Array[Vector3i] = []
		for key in outline(rect):
			match terrain["edges"].get(key, Terrain.Edge.OPEN):
				Terrain.Edge.WALL:
					walls.append(key)
				Terrain.Edge.DOOR:
					gates.append(key)
				_:
					open.append(key)
		if not open.is_empty():
			warnings.append("the town wall round %s has %d open edges on its ring (%s)" % [town, open.size(), open[0]])
		if not rect.has_point(place["cell"]):
			warnings.append("the town wall round %s does not hold its place's cell %s" % [town, place["cell"]])
		out.append({"town": town, "rect": rect, "walls": walls, "gates": gates})
	return out


## A level.json town wall entry's rect (null if it has none).
static func town_wall_rect(entry: Variant) -> Variant:
	var given: Variant = entry.get("rect") if entry is Dictionary else null
	if not given is Array or given.size() != 4:
		return null
	var rect := Rect2i(int(given[0]), int(given[1]), int(given[2]), int(given[3]))
	return rect if rect.size.x > 0 and rect.size.y > 0 else null


## A level.json building entry's facing: its "facing" if it is one of the
## four sides, else BUILDING_FACING.
static func building_facing(entry: Dictionary) -> Vector2i:
	var facing: Variant = facing_from(entry.get("facing"))
	return facing if facing != null and (facing.x == 0 or facing.y == 0) else BUILDING_FACING


## A level.json building entry's footprint (null if it has no "at" or no
## slot in BUILDINGS).
static func building_rect(entry: Variant) -> Variant:
	if not entry is Dictionary or not BUILDINGS.has(str(entry.get("slot", ""))):
		return null
	var at: Variant = _tile(entry.get("at"))
	if at == null:
		return null
	var size: Vector2i = BUILDINGS[str(entry["slot"])]
	return Rect2i(at, size if building_facing(entry).x == 0 else Vector2i(size.y, size.x))


static func rect_cells(rect: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			out.append(Vector2i(x, y))
	return out


## The edges round [param rect]'s outline, as Terrain edge keys.
static func outline(rect: Rect2i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for x in range(rect.position.x, rect.end.x):
		out.append(Vector3i(x, rect.position.y - 1, Terrain.SOUTH))
		out.append(Vector3i(x, rect.end.y - 1, Terrain.SOUTH))
	for y in range(rect.position.y, rect.end.y):
		out.append(Vector3i(rect.position.x - 1, y, Terrain.EAST))
		out.append(Vector3i(rect.end.x - 1, y, Terrain.EAST))
	return out


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
	return {"script": ANIMAL if Animal.is_wild(type) else MONSTER, "shape": "capsule", "props": props, "kind": type}


## A prop read from JSON: body_material by name, numbers as floats except
## sight_range, slots as known item ids, at most a cart's (Items.tidy; the
## chest or container fits them to its size).
static func _prop(key: String, value: Variant) -> Variant:
	if key == "slots":
		return Items.tidy(value, mini(value.size(), Cargo.MAX) if value is Array else 0)
	if key == "body_material" and value is String:
		return GridEntity.BodyMaterial.get(str(value).to_upper(), GridEntity.BodyMaterial.FLESH)
	if key == "sight_range":
		return int(value)
	return value


## A facing from level.json, [dx, dy] each -1, 0 or 1 (not both 0); null
## for anything else.
static func facing_from(value: Variant) -> Variant:
	var at: Variant = _tile(value)
	if at == null:
		return null
	var direction := Vector2i(clampi(at.x, -1, 1), clampi(at.y, -1, 1))
	return direction if direction != Vector2i.ZERO else null


## A monster's idling from level.json: a mode name ("guard", "wander",
## "patrol", "gather", "none") or {"mode", "route": [[x, y], ...], "loop",
## "point": [x, y], "radius"}, as {mode, route (Array of Vector2i), loop,
## point (Vector2i), radius}; {} with a warning for an unknown mode.
static func idle_from(value: Variant, warnings: Array[String], at: Vector2i) -> Dictionary:
	var given: Dictionary = value if value is Dictionary else {"mode": value}
	var mode := str(given.get("mode", ""))
	if mode not in IDLE_MODES:
		warnings.append("the monster at %s has an unknown idle mode \"%s\" (%s)" % [at, mode, ", ".join(IDLE_MODES)])
		return {}
	var idle := {"mode": mode}
	var route: Array[Vector2i] = []
	var listed: Variant = given.get("route", [])
	if listed is Array:
		for point: Variant in listed:
			var tile: Variant = _tile(point)
			if tile != null:
				route.append(tile)
	if not route.is_empty():
		idle["route"] = route
		idle["loop"] = bool(given.get("loop", true))
	var point: Variant = _tile(given.get("point"))
	if point != null:
		idle["point"] = point
	if given.has("radius"):
		idle["radius"] = int(given["radius"])
	return idle


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
		var hex: Variant = config.get("legend", {}).get(meaning, LEGEND.get(meaning, "#000000"))
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
