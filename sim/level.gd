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
## no wall: nothing is built along it, and sight passes over it. Tall
## grass (decision 508) is grass ground that hides who stands in it
## (World.cover_at), slows a step and is trampled flat (terrain
## "tall_grass"); a building over it takes it away. A slope (decision 513)
## is a stair outdoors, drawn as a ramp of ground (in terrain "stairs", and
## "slopes" for the look); a rock is no floor, walled round like void (it
## stops a step and sight) but drawn as rock, not a tree (terrain "rocks").
## A height step with neither a stair nor a slope is a cliff.
##
## load() reads a level into {name, terrain, entities, starts, spawn_points,
## links, neighbours, places, buildings, regenerate (decision 465), centre, size (in cells), warnings}; terrain is what World.load_terrain and the
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
	"ford": "#6fa8e0",
	"tall_grass": "#a8c850",
	"slope": "#c8b878",
	"rock": "#6e6a64",
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
const PLACE_KINDS: Array[String] = ["camp", "keep", "farm", "gate", "mine", "stockpile", "temple", "healers_hut",
	"woodlot", "hunting_ground", "quarry", "fishing", "fort", "other"]
## The buildings that make a place of their own where they stand
## (building_places, decision 372): where the fallen come back.
const BUILDING_PLACES := {"building.temple": "temple", "building.healers_hut": "healers_hut"}
## A place's radius when level.json gives none, in cells.
const PLACE_RADIUS := 8
const NORTHS := {"up": Vector2i(0, -1), "down": Vector2i(0, 1), "left": Vector2i(-1, 0), "right": Vector2i(1, 0)}
## The buildings level.json "buildings" may name (art-kit's building.*
## slots, drawn over the footprint: roof, floor, trim), each its footprint
## in cells, across by deep as it faces north or south (the other way round
## facing east or west). The footprint is the inside; its walls and door
## are the map's own edges on its outline (decision 265).
const BUILDINGS := {"building.hut": Vector2i(3, 3), "building.house": Vector2i(4, 6), "building.shed": Vector2i(2, 3),
	"building.well": Vector2i(1, 1), "building.temple": Vector2i(4, 6), "building.healers_hut": Vector2i(3, 3),
	"building.field": Vector2i(4, 4), "building.mound": Vector2i(12, 12),
	"building.great_tree": Vector2i(3, 3), "building.cairn": Vector2i(2, 2), "building.standing_stone": Vector2i(1, 1),
	"building.waystone": Vector2i(1, 1), "building.chopping_block": Vector2i(1, 1), "building.woodpile": Vector2i(1, 1),
	"building.tower_ruin": Vector2i(3, 3), "building.rubble_heap": Vector2i(1, 1), "building.fallen_column": Vector2i(2, 1)}
## The buildings that stand on water, not floor: no inside, no walls (a
## well: its water is what stops walkers, and sight passes over it).
const ON_WATER: Array[String] = ["building.well"]
## The buildings on floor with no inside (decision 452): open to the sky,
## nothing roofed, walked into as ground. Their outline's walls are a fence
## (the slot's own mesh draws it): they stop walkers, not sight, and are
## not drawn as walls; a gap in it is an open edge.
const OPEN_AIR: Array[String] = ["building.field"]
## The buildings that are solid (decision 550): no inside and no floor but
## their door, the front row's middle cell (a barrow's mound: its link is
## there). Their other cells are taken out of the floor (nobody walks onto
## them, routes go round) and listed in terrain "solid", which stops sight
## as a wall does; their outline has no walls (the slot's mesh is the
## mound), none expected.
const SOLID: Array[String] = ["building.mound", "building.great_tree", "building.cairn", "building.standing_stone", "building.waystone",
	"building.chopping_block", "building.woodpile", "building.tower_ruin", "building.rubble_heap", "building.fallen_column"]
## The solid buildings with no door (decision 567: the wilds' landmarks; 566
## amended: the work props, a chopping block and a woodpile a body stands
## beside; 600: the Old Tower's broken tower and fallen stone): every cell
## of theirs out of the floor, none walked onto or into.
const DOORLESS: Array[String] = ["building.great_tree", "building.cairn", "building.standing_stone", "building.waystone",
	"building.chopping_block", "building.woodpile", "building.tower_ruin", "building.rubble_heap", "building.fallen_column"]
## solid_door_of's answer for a DOORLESS building.
const NO_DOOR := Vector2i(-1, -1)
## A bridge (decision 505): a building entry {slot: "bridge", at, facing,
## length, width (1 or 2)} across water, its long axis along its facing,
## from a bank to a bank of one height. Its cells are walked on at the
## banks' height, the water still under them (terrain "bridged"), and its
## long sides have railings: wall edges that stop walkers, not sight
## (terrain "railings", Fields.fences), drawn by its slot (art-kit's
## bridge.<set>.deck, .rail and .end), not as walls.
const BRIDGE := "bridge"
## The buildings that span water rather than stand in it (a well): the
## water is not dried under them, they have no inside and no walls.
const SPANS_WATER: Array[String] = [BRIDGE]
## Building kinds (decision 488), each a composition of blocks of cells in
## sizes: levels/buildings.json's "kinds" (its "_about" says the format).
## A level.json building entry names a "kind" (and "size") instead of a
## "slot"; BuildingComposer draws it.
const KINDS_FILE := "res://levels/buildings.json"
## A kind's size when an entry names none.
const KIND_SIZE := "small"
## The least a kind's main block measures each way, in floor cells (Jeff:
## "building sizes all need space inside, minimum 5x5 - no more 3x3
## shacks"): its walls are the edges round it, so all of it is floor. A
## wing, a bay or an outshot may be less. kinds() says so of any under it.
const MIN_ROOM := 5
## A town's stages (economy's Towns.stage, only ever rising; the growth
## loop, decision 591): a kind names the first it may be built at
## ("stage"), so a town at a stage may build that stage's kinds and every
## earlier one's.
const STAGES: Array[String] = ["hamlet", "village", "town", "city"]
## The "stage" of a kind no town builds: one a set piece stands by hand
## (the Old Tower's room). Never among kinds_at's.
const SET_STAGE := "set"
## The plots a town lays out (maps' plot_for, which adds a ring of a cell
## round for its path and footing): the largest footprint each holds,
## across by deep, its front +y. A kind names its class ("plot"), and each
## of its sizes fits it.
const PLOT_CLASSES := {"S": Vector2i(6, 6), "M": Vector2i(8, 12), "L": Vector2i(13, 16), "long": Vector2i(16, 6)}
## A kind's wall height when it names no "eaves": a storey's.
const STOREY := 3.0
## The sides a kind's door names, in its own frame (front +y).
const DOOR_SIDES := {"N": Vector2i(0, -1), "S": Vector2i(0, 1), "E": Vector2i(1, 0), "W": Vector2i(-1, 0)}
static var _kinds := {}
## A building's facing (the side its front is on) when level.json gives none.
const BUILDING_FACING := Vector2i(0, 1)
## The region of a level that names none (region_of).
const DEFAULT_REGION := "town_lands"
## A canopy (level.json "canopy", decision 466): each trunk (a void cell)
## within CANOPY_REACH cells shades a cell by 1 - its distance over the
## reach, the shares added and capped at 1; a listed clearing's cells are
## open (0). The kinds a canopy is ("kind"): an evergreen one keeps its
## needles, a broadleaf one thins in winter (environment's to draw).
const CANOPY_REACH := 3.2
const CANOPY_KINDS: Array[String] = ["evergreen", "broadleaf"]
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
const ORDERLESS_KEYS: Array[String] = ["at", "facing", "idle", "loot", "wields"]
## What a monster can carry from a loot table (_stock), dropped where it falls.
const MONSTER_CARRIES := 4

## Levels made in code (tests): name -> {layout: Image, height: Image or
## null, config: Dictionary}; load() takes these before the folder.
static var _registered: Dictionary[String, Dictionary] = {}


## Makes a level from images and a config, without files (tests).
static func register(level_name: String, layout: Image, height: Image = null, config := {}, relief: Image = null) -> void:
	_registered[level_name] = {"layout": layout, "height": height, "config": config, "relief": relief}
	Regen.forget()


static func unregister(level_name: String) -> void:
	_registered.erase(level_name)
	Regen.forget()


## The authored files of the levels that regenerate (decision 465): name ->
## {layout, height, config}, kept from before their first generation put a
## generated map in their place (register, the overlay). Regen keeps them.
static var _templates: Dictionary[String, Dictionary] = {}


## Keeps [param made] ({layout, height, config}) as level [param level_name]'s
## template: what each generation starts from.
static func keep_template(level_name: String, made: Dictionary) -> void:
	_templates[level_name] = {"layout": made["layout"], "height": made["height"], "config": made["config"], "relief": made.get("relief")}
	Regen.forget()


## Level [param level_name]'s template: the authored level a generation
## starts from (decision 465): the one kept (keep_template), else the one
## made in code (a test's), else the files in DIR. Never the overlay, which
## holds the last generation. {layout: null, ...} for a level there is not.
static func template(level_name: String) -> Dictionary:
	if _templates.has(level_name):
		return _templates[level_name]
	if _registered.has(level_name):
		return _registered[level_name]
	var folder := DIR + level_name + "/"
	return {"layout": _image(folder + "layout.png"), "height": _image(folder + "height.png"), "config": template_config(level_name),
		"relief": _image(folder + "relief.png")}


## The template's level.json alone (template, without its images read).
static func template_config(level_name: String) -> Dictionary:
	if _templates.has(level_name):
		return _templates[level_name]["config"]
	if _registered.has(level_name):
		return _registered[level_name]["config"]
	var path := DIR + level_name + "/level.json"
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			return parsed
	return {}


## Whether level [param level_name]'s template marks it regenerating
## (level.json "regenerate"; decision 465).
static func regenerates(level_name: String) -> bool:
	return template_config(level_name).get("regenerate") is Dictionary


## The levels made in code (register), sorted: Regen looks at them beside names().
static func registered_names() -> Array[String]:
	var out: Array[String] = []
	out.assign(_registered.keys())
	out.sort()
	return out


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
	return {"layout": _image(folder + "layout.png"), "height": _image(folder + "height.png"), "config": config,
		"relief": _image(folder + "relief.png")}


## Reads level [param level_name] (see the class doc). {} with a warning
## printed when there is none.
static func load_level(level_name: String) -> Dictionary:
	var made := source(level_name)
	var layout: Image = made["layout"]
	if layout == null:
		push_warning("[level] no level %s (%slayout.png)" % [level_name, folder_of(level_name)])
		return {}
	var level := parse(layout, made["height"], made["config"], made.get("relief"))
	level["name"] = level_name
	level["terrain"]["level"] = level_name
	# A linked building's town by its id, as Towns and Holdings name it.
	for building: Dictionary in level["buildings"]:
		building["town_id"] = "%s/%s" % [level_name, building["town"]] if not building["town"].is_empty() else ""
	for ring: Dictionary in level["town_walls"]:
		ring["town_id"] = "%s/%s" % [level_name, ring["town"]]
	for roof: Dictionary in level["roofs"]:
		roof["town_id"] = "%s/%s" % [level_name, roof["town"]] if not roof["town"].is_empty() else ""
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
static func parse(layout: Image, height: Image, config: Dictionary, relief: Image = null) -> Dictionary:
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
	var ford_code: int = code_of.get("ford", -2)
	var tall_code: int = code_of.get("tall_grass", -2)
	var rock_code: int = code_of.get("rock", -2)
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
	var fords: Array[Vector2i] = []
	var tall_grass: Array[Vector2i] = []
	var rocks: Array[Vector2i] = []
	var slope_cells: Array[Vector2i] = []
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
			if code == rock_code:
				# A rock (decision 513): no floor, its footing the ground round it.
				rocks.append(cell)
				kinds[cell] = _ground_around(cell, cell_codes, cells, names)
				continue
			floor_tiles.append(cell)
			if code == ford_code:
				# Shallow water walked through, slowly (decision 505): floor,
				# its footing the ground round it.
				fords.append(cell)
				kinds[cell] = _ground_around(cell, cell_codes, cells, names)
				continue
			if code == tall_code:
				# Grass ground grown tall (decision 508).
				tall_grass.append(cell)
				kinds[cell] = "grass"
				continue
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
				"slope":
					stair_cells.append(cell)
					slope_cells.append(cell)
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
			elif code != VOID and code != rock_code:
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
	# The ground's elevation in metres (decision 525): relief.png's where
	# it is given, else the whole levels'.
	var field := PackedFloat32Array()
	if relief != null:
		field = Relief.read(relief, cells, warnings)
		if not field.is_empty():
			if not heights.is_empty():
				warnings.append("height.png and relief.png are both here: relief.png is the ground")
			heights = Relief.whole_levels(field, cells)
	var given := not field.is_empty()
	if not given:
		field = Relief.derived(heights, cells)
	var stairs: Dictionary[Vector2i, Vector2i] = {}
	var slopes: Dictionary[Vector2i, Vector2i] = {}
	for cell in stair_cells:
		var up: Array[Vector2i] = []
		for direction: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var next := cell + direction
			var next_walks := walks[(next.y + 1) * across + next.x + 1] == 1
			var rise := Relief.at(field, cells, next) - Relief.at(field, cells, cell)
			if next_walks and rise >= Relief.LEVEL_M * 0.5 and rise <= Relief.STAIR_RISE + Relief.EPSILON \
					and not edges.has(Terrain.edge_key(cell, direction)):
				up.append(direction)
		var what := "slope" if cell in slope_cells else "stair"
		if up.is_empty():
			warnings.append("the %s at %s has no cell one level up beside it: it is floor" % [what, cell])
			continue
		if up.size() > 1:
			warnings.append("the %s at %s could climb %s; it climbs %s" % [what, cell, up, up[0]])
		stairs[cell] = up[0]
		if what == "slope":
			slopes[cell] = up[0]
	for key: int in unknown:
		warnings.append("colour #%06x is not in the legend: void" % key)
	var zone := zone_of(config)
	if config.has("zone") and str(config["zone"]) != zone:
		warnings.append("\"zone\" in level.json is %s: one of %s; it is %s" % [config["zone"], ", ".join(DayNight.ZONES), zone])
	var level := {
		"terrain": {
			"floor": floor_tiles, "fire": fire, "edges": edges, "kinds": kinds, "water": water, "fords": fords,
			"tall_grass": tall_grass, "slopes": slopes, "rocks": rocks,
			"heights": heights, "stairs": stairs, "torches": torches, "lanterns": lanterns,
			"relief": field, "relief_size": cells, "relief_given": given,
			"ambient": clampf(float(config.get("ambient", DayNight.base_ambient(zone))), 0.0, 1.0),
			"north": NORTHS.get(str(config.get("north", "up")), Vector2i(0, -1)),
			"zone": zone,
			"region": region_of(config, warnings),
			"outdoor": zone == "outdoors",
			# Lit by the sky on the world clock, unless level.json sets its
			# light outright (decision 291).
			"daylight": zone == "outdoors" and not config.has("ambient"),
			# Too damp for a flame (damp_from).
			"damp": damp_from(config, warnings),
			# The wall and floor sets it is drawn in (decision 285).
			"walls": str(config.get("walls", "castle")),
			"floors": str(config.get("floors", "castle")),
			# Outdoors, what lies past the forest: "forest", or "none".
			"border": str(config.get("border", "forest")),
		},
		"size": cells,
		"warnings": warnings,
	}
	_quench(level["terrain"], warnings)
	var clearings := clearings_from(config, warnings)
	level["terrain"]["clearings"] = clearings
	level["terrain"]["canopy_kind"] = canopy_kind(config, warnings)
	level["terrain"]["canopy"] = canopy_from(cell_codes, cells, clearings) if config.has("canopy") else {}
	_place(level, markers, config, warnings)
	level["regenerate"] = regenerate_from(config, warnings)
	_check_anchors(level, warnings)
	level["buildings"] = buildings_from(config, level["terrain"], warnings)
	_lay_bridges(level)
	_lay_solid(level)
	level["terrain"]["link_cues"] = link_cues(level, config)
	var derived := _lay_curves(level["terrain"], config, warnings)
	level["terrain"]["streams"] = streams_from(derived, level["terrain"], warnings)
	level["terrain"]["niches"] = niches_from(config, level["terrain"], warnings)
	_check_fords(level["terrain"], warnings)
	_check_water(level["terrain"], warnings)
	level["terrain"]["ledges"] = _ledges(level["terrain"], config, warnings)
	level["building_cells"] = inside_cells(level["buildings"])
	_clear_tall_grass(level, warnings)
	building_places(level["buildings"], level["places"])
	# The views draw them (roofs, inside floors) from the terrain they are given.
	level["terrain"]["buildings"] = level["buildings"]
	level["town_walls"] = town_walls_from(config, level["terrain"], cells, warnings)
	level["terrain"]["town_walls"] = level["town_walls"]
	level["roofs"] = roofs_from(config, level["terrain"], level["buildings"], warnings)
	level["terrain"]["roofs"] = level["roofs"]
	return level


## level.json's "damp" (the barrow's deepest: "too moist to light lamps"):
## true, or false when missing or not a bool (said). A damp level's carried
## lights reach Fields.DAMP_REACH as far, and no flame burns in it (_quench).
static func damp_from(config: Dictionary, warnings: Array[String]) -> bool:
	var damp: Variant = config.get("damp", false)
	if damp is bool:
		return damp
	warnings.append("\"damp\" in level.json is %s: true or false; it is false" % [damp])
	return false


## On a damp [param terrain], its torches, lanterns and fire are put out,
## each kind said once.
static func _quench(terrain: Dictionary, warnings: Array[String]) -> void:
	if not terrain["damp"]:
		return
	for kind: String in ["torches", "lanterns", "fire"]:
		var cells: Array = terrain[kind]
		if not cells.is_empty():
			warnings.append("too damp to light: %s put out (%d cells)" % [kind, cells.size()])
			cells.clear()


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
		_stock(props, spec, entry, config, warnings, at)
		_arm(props, spec, entry, warnings, at)
		_style(props, spec, config, warnings, at)
		_grave(props, spec, config, warnings, at)
		if not props.is_empty():
			spec["props"] = props
		if spec.get("script") == MONSTER or _own_class(spec):
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
					"one_way": bool(entry.get("one_way", false)), "closed": bool(entry.get("closed", false)),
					"sealed": str(entry.get("sealed", "")), "hidden": bool(entry.get("hidden", false))})
	for at in link_tiles:
		if links.all(func(link: Dictionary) -> bool: return link["tile"] != at):
			warnings.append("the link marker at %s goes nowhere (no entry in level.json \"links\")" % at)
	var centre: Variant = _tile(config.get("centre"))
	level["neighbours"] = neighbours_from(config, warnings)
	level["places"] = places_from(config, warnings)
	level["markets"] = markets_from(config, warnings)
	level["became"] = became_from(config, warnings)
	level["entities"] = entities
	level["starts"] = starts
	level["spawn_points"] = spawn_points
	level["links"] = links
	# Where they are, for the terrain's readers (World keeps them clear, 571).
	level["terrain"]["links_at"] = links.map(func(link: Dictionary) -> Vector2i: return link["tile"])
	level["centre"] = centre if centre != null else starts[0] if not starts.is_empty() else Vector2i.ZERO
	level["display_name"] = str(config.get("name", ""))


## level.json's "regenerate" (decision 465: a level laid again by a
## generator every few days), as {generator (a script in sim/level_gen/,
## "maze" if not said), every_days (at least 1), anchors: [{rect: Rect2i,
## name}] (the cells copied verbatim each generation), monsters: {kind:
## count} (markers the generator lays)}; {} for a level that does not
## regenerate. An anchor with no rect, or a generator name that is no
## plain word, is said in [param warnings].
static func regenerate_from(config: Dictionary, warnings: Array[String]) -> Dictionary:
	var given: Variant = config.get("regenerate")
	if given == null:
		return {}
	if not given is Dictionary:
		warnings.append("\"regenerate\" in level.json is not an object")
		return {}
	var generator := str(given.get("generator", "maze"))
	if not generator.is_valid_identifier():
		warnings.append("\"regenerate\" names a generator %s: a plain word (a script in sim/level_gen/); it is maze" % generator)
		generator = "maze"
	var anchors: Array[Dictionary] = []
	var listed: Variant = given.get("anchors", [])
	if listed is Array:
		for entry: Variant in listed:
			var rect: Variant = town_wall_rect(entry)
			if rect == null:
				warnings.append("an anchor in \"regenerate\" has no \"rect\": [x, y, w, h] (%s)" % [entry])
				continue
			anchors.append({"rect": rect, "name": str(entry.get("name", "anchor %d" % (anchors.size() + 1)))})
	else:
		warnings.append("\"regenerate\" has no anchors list")
	if anchors.is_empty():
		warnings.append("\"regenerate\" has no anchors: nothing of the level is kept between generations")
	var monsters := {}
	var counts: Variant = given.get("monsters", {})
	if counts is Dictionary:
		for kind: Variant in counts:
			monsters[str(kind)] = maxi(int(counts[kind]), 0)
	var out := {"generator": generator, "every_days": maxi(int(given.get("every_days", 3)), 1), "anchors": anchors, "monsters": monsters}
	# The rest of the block is the generator's own (a style, rooms, loops,
	# chests...: docs/levels.md), passed as written.
	for key: Variant in given:
		if str(key) not in out:
			out[str(key)] = given[key]
	return out


## Whether [param cell] lies in one of [param anchors] (regenerate_from's).
static func in_anchors(anchors: Array, cell: Vector2i) -> bool:
	for anchor: Dictionary in anchors:
		if (anchor["rect"] as Rect2i).has_point(cell):
			return true
	return false


## A regenerating level's links, spawn points and starts must sit inside
## an anchor (decision 465: the rest of the map is laid again); one that
## does not is said in [param warnings].
static func _check_anchors(level: Dictionary, warnings: Array[String]) -> void:
	if level["regenerate"].is_empty():
		return
	var anchors: Array = level["regenerate"]["anchors"]
	for link: Dictionary in level["links"]:
		if not in_anchors(anchors, link["tile"]):
			warnings.append("the link at %s to %s is outside every anchor: a generation loses it" % [link["tile"], link["to_map"]])
	var spawn_points: Dictionary = level["spawn_points"]
	for spawn_name: String in spawn_points:
		if not in_anchors(anchors, spawn_points[spawn_name]):
			warnings.append("the spawn point %s at %s is outside every anchor: a generation loses it" % [spawn_name, spawn_points[spawn_name]])
	for start: Vector2i in level["starts"]:
		if not in_anchors(anchors, start):
			warnings.append("the start at %s is outside every anchor: a generation loses it" % [start])


## level.json's "neighbours", {side: map name} ("east": "wilds": walk off
## the east edge, arrive at the west edge of wilds at the same row), with
## sides that are not north, east, south or west said in [param warnings].
## level.json "became" (decision 471): a level entity's marker cell, "x,y"
## (its spawn key, decision 433), -> what it became ("snagfin"). A save's
## entity of that key is handed over (Main._hand_over), not spawned.
static func became_from(config: Dictionary, warnings: Array[String]) -> Dictionary[String, String]:
	var out: Dictionary[String, String] = {}
	var given: Variant = config.get("became", {})
	if not given is Dictionary:
		warnings.append("level.json \"became\" is not an object of \"x,y\": what it became")
		return out
	for key: Variant in given:
		out[str(key)] = str(given[key])
	return out


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
## start; "nobody" if not said), and town if it works for one (decision 517:
## the key of the stockpile place whose town works it, as a building's
## "town"; a woodlot its woodcutter's, a hunting ground its hunter's)}: the
## places factions hold (Holdings). An entry with no cell, a kind there is
## not, or a town that is no stockpile place here, is said in
## [param warnings].
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
		# A camp's captives from the start (decision 518, npc's): holds [{town, resident, name, trade}], kept when well-formed.
		var holds: Variant = entry.get("holds")
		if holds is Array:
			var kept: Array[Dictionary] = []
			for each: Variant in holds:
				if each is Dictionary and not str(each.get("town", "")).is_empty() and not str(each.get("resident", "")).is_empty():
					kept.append({"town": str(each["town"]), "resident": str(each["resident"]), "name": str(each.get("name", "")), "trade": str(each.get("trade", ""))})
				else:
					warnings.append("the place %s holds an entry with no town or resident: left out" % [key])
			if not kept.is_empty():
				out[str(key)]["holds"] = kept
		elif holds != null:
			warnings.append("the place %s's holds is not a list: left out" % [key])
	for key: String in out:
		var town := str(listed[key].get("town", ""))
		if town.is_empty():
			continue
		if out.get(town, {}).get("kind") != "stockpile":
			warnings.append("the place %s works for town \"%s\": no stockpile place of that key here; it works for none" % [key, town])
			continue
		out[key]["town"] = town
	return out


## level.json's "markets", key -> {key, cell, name}: where trade routes end
## that are no town's store (decision 504; "the castle market"), a cell a
## caravan walks to, priced by economy. Its id is "market:<key>". An entry
## with no cell is said in [param warnings].
static func markets_from(config: Dictionary, warnings: Array[String]) -> Dictionary[String, Dictionary]:
	var out: Dictionary[String, Dictionary] = {}
	var listed: Variant = config.get("markets", {})
	if not listed is Dictionary:
		warnings.append("\"markets\" in level.json is not an object")
		return out
	for key: Variant in listed:
		var entry: Variant = listed[key]
		var at: Variant = _tile(entry.get("at") if entry is Dictionary else null)
		if at == null:
			warnings.append("the market %s has no \"at\" cell" % [key])
			continue
		out[str(key)] = {"key": str(key), "cell": at, "name": str(entry.get("name", "the %s market" % key))}
	return out


## The places [param buildings] make (BUILDING_PLACES; decision 372), put
## in [param places]: a temple and a healer's hut, where the fallen come
## back (economy), each a place of its kind on the cell outside the middle
## of its front, held by nobody, worth nothing, keyed "<kind>@x,y". Made
## from the building, so moving or taking it away in the editor or builder
## moves or takes the place; a key level.json's places already has is left
## as it is.
static func building_places(buildings: Array, places: Dictionary) -> void:
	for building: Dictionary in buildings:
		var kind := str(BUILDING_PLACES.get(building["slot"], building.get("place", "")))
		if kind.is_empty():
			continue
		var cell: Vector2i = building.get("front", front_cell(building["rect"], building["facing"]))
		var key := "%s@%d,%d" % [kind, cell.x, cell.y]
		if not places.has(key):
			places[key] = {"key": key, "cell": cell, "name": kind.replace("_", " ").capitalize(), "kind": kind,
				"radius": 1, "worth": 0, "holder": "nobody"}


## The cell just outside the middle of [param rect]'s side facing
## [param facing] (a building's front: where its door opens onto).
static func front_cell(rect: Rect2i, facing: Vector2i) -> Vector2i:
	var middle := rect.position + (rect.size - Vector2i.ONE) / 2
	match facing:
		Vector2i(0, 1):
			return Vector2i(middle.x, rect.end.y)
		Vector2i(0, -1):
			return Vector2i(middle.x, rect.position.y - 1)
		Vector2i(1, 0):
			return Vector2i(rect.end.x, middle.y)
		Vector2i(-1, 0):
			return Vector2i(rect.position.x - 1, middle.y)
	return middle


## What kind of place level.json [param config] is, one of DayNight.ZONES
## (decision 291): its "zone"; else "outdoors" for the older
## "outdoor": true, else "indoors".
static func zone_of(config: Dictionary) -> String:
	var zone := str(config.get("zone", ""))
	if zone in DayNight.ZONES:
		return zone
	return "outdoors" if bool(config.get("outdoor", false)) else "indoors"


## level.json's "clearings", [{centre: [x, y], radius}] (decision 466):
## open ground under a canopy, as {centre: Vector2, radius: float}; a bad
## entry is left out and said in [param warnings].
static func clearings_from(config: Dictionary, warnings: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Variant in config.get("clearings", []):
		if entry is Dictionary and entry.get("centre") is Array and (entry["centre"] as Array).size() == 2 				and float(entry.get("radius", 0.0)) > 0.0:
			out.append({"centre": Vector2(float(entry["centre"][0]), float(entry["centre"][1])), "radius": float(entry["radius"])})
		else:
			warnings.append("a clearing in level.json is not {centre: [x, y], radius}: left out (%s)" % [entry])
	return out


## The kind of level.json [param config]'s canopy (CANOPY_KINDS), "" for a
## level without one; one not known is said and read as evergreen.
static func canopy_kind(config: Dictionary, warnings: Array[String]) -> String:
	if not config.has("canopy"):
		return ""
	var kind := str((config["canopy"] as Dictionary).get("kind", "evergreen")) if config["canopy"] is Dictionary else "evergreen"
	if kind not in CANOPY_KINDS:
		warnings.append("\"canopy\" kind in level.json is %s, one of %s: it is evergreen" % [kind, ", ".join(CANOPY_KINDS)])
		kind = "evergreen"
	return kind


## Each cell's canopy cover, 0..1, from the trunks (the VOID cells of
## [param codes], a map [param cells] across): {cell: cover}, the cells
## with none left out. The same on every peer, from the same layout.
static func canopy_from(codes: PackedInt32Array, cells: Vector2i, clearings: Array[Dictionary]) -> Dictionary[Vector2i, float]:
	var cover: Dictionary[Vector2i, float] = {}
	var reach := ceili(CANOPY_REACH)
	for y in cells.y:
		for x in cells.x:
			if codes[y * cells.x + x] != VOID:
				continue
			for dy in range(-reach, reach + 1):
				for dx in range(-reach, reach + 1):
					var cell := Vector2i(x + dx, y + dy)
					var d := Vector2(dx, dy).length()
					if d < CANOPY_REACH and cell.x >= 0 and cell.y >= 0 and cell.x < cells.x and cell.y < cells.y:
						cover[cell] = minf(cover.get(cell, 0.0) + 1.0 - d / CANOPY_REACH, 1.0)
	for clearing in clearings:
		var centre: Vector2 = clearing["centre"]
		var radius: float = clearing["radius"]
		for cell: Vector2i in cover.keys():
			if (Vector2(cell) + Vector2(0.5, 0.5)).distance_to(centre) < radius:
				cover.erase(cell)
	return cover


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
## may be open; a well has no walls; an OPEN_AIR one's gate is a gap).
static func buildings_from(config: Dictionary, terrain: Dictionary, warnings: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var listed: Variant = config.get("buildings", [])
	if not listed is Array:
		warnings.append("\"buildings\" in level.json is not a list")
		return out
	var codes := building_codes(listed, config.get("building_codes", {}))
	var index := -1
	var ground: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in terrain["floor"]:
		ground[cell] = true
	var wet: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in terrain.get("water", []):
		wet[cell] = true
	var taken: Dictionary[Vector2i, bool] = {}
	var linked := {}
	for entry: Variant in listed:
		index += 1
		var rect: Variant = building_rect(entry)
		if rect == null:
			warnings.append("the building %s has no \"at\" cell, or no slot of %s or kind of %s" % [entry, ", ".join(BUILDINGS.keys()), ", ".join(kinds().keys())])
			continue
		var blocks: Array[Rect2i] = building_blocks(entry)
		var cells := _union(blocks)
		var what := str(entry.get("slot", entry.get("kind", "")))
		var on_water := str(entry.get("slot", "")) in ON_WATER
		if str(entry.get("slot", "")) in SPANS_WATER:
			var bridge := _bridge(entry, rect, cells, terrain, wet, ground, taken, warnings)
			if not bridge.is_empty():
				out.append(bridge)
			continue
		var under := wet if on_water else ground
		var bad := cells.filter(func(cell: Vector2i) -> bool: return not under.has(cell) or taken.has(cell))
		if bad.is_empty():
			bad = _uneven(terrain, cells)
		if not bad.is_empty():
			warnings.append("the %s at %s is not all on %s of one height (%s): left out" % [what, rect.position, "water" if on_water else "clear floor", bad[0]])
			continue
		for cell in cells:
			taken[cell] = true
		var open: Array[Vector3i] = []
		# A kind's own open edges (its "open": a forge's front) are meant so.
		var meant: Array[Vector3i] = []
		if entry.has("kind"):
			meant = kind_open(entry)
		for key in blocks_outline(cells) if not on_water and not str(entry.get("slot", "")) in OPEN_AIR and not str(entry.get("slot", "")) in SOLID else []:
			if not terrain["edges"].has(key) and not key in meant:
				open.append(key)
		if not open.is_empty():
			warnings.append("the %s at %s has %d open edges on its outline (%s)" % [what, rect.position, open.size(), open[0]])
		var building := {"slot": str(entry.get("slot", "")), "cell": rect.position, "facing": building_facing(entry), "rect": rect,
			"blocks": blocks, "use": "", "town": "", "code": codes[index]}
		# Which of its slot's variants, and a free turn (degrees) over its
		# facing's (decision 567: a ring of stones, each its own).
		if entry.get("variant") is float or entry.get("variant") is int:
			building["variant"] = maxi(1, int(entry["variant"]))
		if entry.get("yaw") is float or entry.get("yaw") is int:
			building["yaw"] = float(entry["yaw"])
		if entry.has("kind"):
			_kind_of(building, entry)
		_link(building, entry, config, linked, warnings)
		out.append(building)
	return out


## Bridge [param entry] over [param cells] ([param rect]) checked: water
## (or a ford) all of it, clear of other buildings, a floor cell of one
## height beyond each end along its facing (the banks); the parsed building
## with "height" (the banks') and "banks" (the cells before its first and
## after its last), or {} and said in [param warnings]. Level banks only
## for now: heights are whole levels, and a ramp between two is a stair's.
static func _bridge(entry: Dictionary, rect: Rect2i, cells: Array[Vector2i], terrain: Dictionary, wet: Dictionary, ground: Dictionary,
		taken: Dictionary, warnings: Array[String]) -> Dictionary:
	var fords: Array = terrain.get("fords", [])
	var bad := cells.filter(func(cell: Vector2i) -> bool: return not (wet.has(cell) or cell in fords) or taken.has(cell))
	if not bad.is_empty():
		warnings.append("the bridge at %s is not all over water (%s): left out" % [rect.position, bad[0]])
		return {}
	var facing := building_facing(entry)
	var along := Vector2i(absi(facing.x), absi(facing.y))
	var first := rect.position - along
	var last := rect.position + Vector2i((rect.size.x - 1) * along.x, (rect.size.y - 1) * along.y) + along
	var banks: Array[Vector2i] = []
	var width := rect.size.x if along.y != 0 else rect.size.y
	for across in width:
		var side := Vector2i(across, 0) if along.y != 0 else Vector2i(0, across)
		banks.append(first + side)
		banks.append(last + side)
	var height: int = terrain["heights"].get(banks[0], 0)
	for bank in banks:
		if not ground.has(bank) or wet.has(bank) or bank in fords:
			warnings.append("the bridge at %s does not end on a bank at %s: left out" % [rect.position, bank])
			return {}
	var uneven := _uneven(terrain, banks)
	if not uneven.is_empty():
		warnings.append("the bridge at %s has banks of two heights (%s): left out (level banks only)" % [rect.position, uneven[0]])
		return {}
	for cell in cells:
		taken[cell] = true
	var blocks: Array[Rect2i] = [rect]
	return {"slot": BRIDGE, "cell": rect.position, "facing": facing, "rect": rect, "blocks": blocks, "use": "", "town": "",
		"height": height, "elevation": _elevation(terrain, banks[0]), "banks": [first, last]}


## The cells of [param cells] off a pad (Relief.flat, decision 525): []
## if they lie within Relief.PAD_FLAT of each other, else the one furthest
## from the first. A terrain with no relief compares whole levels.
static func _uneven(terrain: Dictionary, cells: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not terrain.has("relief"):
		var height: int = terrain["heights"].get(cells[0], 0)
		for cell: Vector2i in cells:
			if terrain["heights"].get(cell, 0) != height:
				out.append(cell)
				break
		return out
	if Relief.flat(terrain["relief"], terrain["relief_size"], cells):
		return out
	var base := _elevation(terrain, cells[0])
	var furthest: Vector2i = cells[0]
	for cell: Vector2i in cells:
		if absf(_elevation(terrain, cell) - base) > absf(_elevation(terrain, furthest) - base):
			furthest = cell
	out.append(furthest)
	return out


## [param terrain]'s elevation at [param cell] in metres (its relief, else
## its whole levels).
static func _elevation(terrain: Dictionary, cell: Vector2i) -> float:
	if terrain.has("relief"):
		return Relief.at(terrain["relief"], terrain["relief_size"], cell)
	return int(terrain["heights"].get(cell, 0)) * Relief.LEVEL_M


## The dungeon rule on width (612, Jeff: "the game is a multiplayer game
## with companions"; a player, their companion and a second player pass
## each other): no passage one cell wide. Of [param cells] (floor), those
## in a single-width run two cells or longer: a cell is narrow along an
## axis when neither side across it is open ([param open]: (cell,
## direction) -> whether a step that way is floor through no wall; a door
## counts as open) and a step along it is; two narrow cells joined along
## their axis make a run. A dead end a cell deep (an alcove, a niche, the
## hidden door's stair cell) is a run of one, allowed; a doorway is a door
## edge, not a cell, so a door between two wide spaces is allowed too.
static func narrow_runs_by(cells: Array[Vector2i], open: Callable) -> Dictionary[Vector2i, int]:
	var narrow: Dictionary[Vector2i, int] = {}  # Cell -> 0 (along x) or 1 (along y).
	for cell in cells:
		var east: bool = open.call(cell, Vector2i(1, 0))
		var west: bool = open.call(cell, Vector2i(-1, 0))
		var south: bool = open.call(cell, Vector2i(0, 1))
		var north: bool = open.call(cell, Vector2i(0, -1))
		if not north and not south and (east or west):
			narrow[cell] = 0
		elif not east and not west and (north or south):
			narrow[cell] = 1
	var out: Dictionary[Vector2i, int] = {}
	for cell: Vector2i in narrow:
		var along := Vector2i(1, 0) if narrow[cell] == 0 else Vector2i(0, 1)
		if narrow.get(cell + along, -1) == narrow[cell] and open.call(cell, along):
			out[cell] = narrow[cell]
			out[cell + along] = narrow[cell]
	return out


## narrow_runs_by over a parsed level's [param terrain] (floor and edges):
## the cells of its single-width runs, in order; empty when it keeps the
## width rule.
static func narrow_runs(terrain: Dictionary) -> Array[Vector2i]:
	var floor := {}
	var cells: Array[Vector2i] = []
	for cell: Vector2i in terrain.get("floor", []):
		floor[cell] = true
		cells.append(cell)
	var edges: Dictionary = terrain.get("edges", {})
	var open := func(cell: Vector2i, direction: Vector2i) -> bool:
		return floor.has(cell + direction) and int(edges.get(Terrain.edge_key(cell, direction), Terrain.Edge.OPEN)) != Terrain.Edge.WALL
	var out: Array[Vector2i] = []
	out.assign(narrow_runs_by(cells, open).keys())
	out.sort()
	return out


## The kinds a burial niche may be (608): art-kit's wall.crypt.niche_a
## (arches), _b (shelves), _c (hollows), _d (columbarium cells), and
## "hidden", the first hall's hidden door (wall.crypt.cracked till found,
## wall.crypt.niche_open after).
const NICHE_KINDS: Array[String] = ["a", "b", "c", "d", "hidden"]


## level.json's "niches" (608, dungeon's barrow; 542 amended's alcove cells
## before): [[x, y, dx, dy, kind, variant], ...], a burial niche cut into a
## wall edge: (x, y) the room's floor cell before it, (dx, dy) the step
## onto the wall (a wall edge with rock behind it; for kind "hidden" a door
## edge with its alcove, a floor cell, behind), kind one of NICHE_KINDS,
## variant 1 or 2; as [{cell, out: the step out of the wall into the room,
## edge: the Terrain edge key, kind, variant}] for terrain to draw the
## wall.crypt piece on, its +x toward the cell, and for World to know what
## a step into that edge presses on. One that is no floor, whose step is
## not one to a side, whose kind or variant is none, or whose edge is not
## such a wall (or door) is said in [param warnings] and left out.
static func niches_from(config: Dictionary, terrain: Dictionary, warnings: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var listed: Variant = config.get("niches", [])
	if not listed is Array:
		warnings.append("\"niches\" in level.json is not a list")
		return out
	var floor := {}
	for cell: Vector2i in terrain.get("floor", []):
		floor[cell] = true
	var edges: Dictionary = terrain.get("edges", {})
	for index in (listed as Array).size():
		var entry: Variant = listed[index]
		if not entry is Array or (entry as Array).size() != 6:
			warnings.append("niche %d is not [x, y, dx, dy, kind, variant]: left out" % index)
			continue
		var cell := Vector2i(int(entry[0]), int(entry[1]))
		var way := Vector2i(int(entry[2]), int(entry[3]))
		var kind := str(entry[4])
		var variant := int(entry[5])
		if not floor.has(cell) or absi(way.x) + absi(way.y) != 1 or kind not in NICHE_KINDS or variant < 1 or variant > 2:
			warnings.append("niche %d at %s (step %s, kind %s, variant %d) is no floor, no side, no kind or no variant: left out" % [index, cell, way, kind, variant])
			continue
		var hidden := kind == "hidden"
		var key := Terrain.edge_key(cell, way)
		if int(edges.get(key, Terrain.Edge.OPEN)) != (Terrain.Edge.DOOR if hidden else Terrain.Edge.WALL) or floor.has(cell + way) != hidden:
			warnings.append("niche %d at %s (step %s) is on no wall with rock behind it%s: left out" % [index, cell, way, " (the hidden one: a door with its alcove behind)" if hidden else ""])
			continue
		out.append({"cell": cell, "out": -way, "edge": key, "kind": kind, "variant": variant})
	return out


## level.json's "waters" and "roads" (decision 559: curves, the cells
## rasterised from them) laid into [param terrain]:
## terrain "waters" and "roads" as Curves.parse has them; each water's
## floor cells (Curves.laid; under the void it runs on unseen) water, but
## a ford's or a bridge's (not floor), a cell the layout has dry made so
## and said in [param warnings] (a curve moved without its cells); each
## road's floor cells not water its kind (decision 563), unsaid.
## Returns [param config] with "streams" from each open water's middle (its
## longest run over the ground, Curves.laid) after level.json's own, for
## streams_from.
static func _lay_curves(terrain: Dictionary, config: Dictionary, warnings: Array[String]) -> Dictionary:
	var waters := Curves.parse(config, "waters", warnings)
	var roads := Curves.parse(config, "roads", warnings)
	terrain["waters"] = waters
	terrain["roads"] = roads
	if waters.is_empty() and roads.is_empty():
		return config
	var wet := {}
	for key in ["water", "fords", "bridged"]:
		for cell: Vector2i in terrain.get(key, []):
			wet[cell] = true
	var floor := {}
	for cell: Vector2i in terrain["floor"]:
		floor[cell] = true
	var streams: Array = (config.get("streams") as Array).duplicate(true) if config.get("streams") is Array else []
	# The cells each water lays are no ground to a later one: a stream into
	# the river ends where it joins it (570), as Relief.lay laid it.
	var claimed := {}
	for index in waters.size():
		var water: Dictionary = waters[index]
		var ground := floor.duplicate()
		ground.merge(wet)
		for cell: Vector2i in claimed:
			ground.erase(cell)
		var laid := Curves.laid(water["curve"], water["closed"], ground)
		claimed.merge(laid["cells"])
		var made := 0
		for cell: Vector2i in laid["cells"]:
			if wet.has(cell):
				continue
			made += 1
			floor.erase(cell)
			terrain["floor"].erase(cell)
			terrain["kinds"].erase(cell)
			terrain["water"].append(cell)
			wet[cell] = true
		if made > 0:
			warnings.append("water %d's curve covers %d cells the layout has dry: water" % [index, made])
		if not water["closed"] and laid["path"].size() >= 2:
			streams.append({"path": laid["path"].map(func(cell: Vector2i) -> Array: return [cell.x, cell.y])})
	# A road's ground is its curve's (a marker on it, whose ground the layout
	# takes from its neighbours, too), so nothing is said.
	for road: Dictionary in roads:
		for cell: Vector2i in Curves.cells(road["curve"], false):
			if floor.has(cell) and not wet.has(cell):
				terrain["kinds"][cell] = road["kind"]
	var out := config.duplicate()
	out["streams"] = streams
	return out


## level.json's "streams" (decision 505): [{"path": [[x, y], ...]}], each a
## stream's cells in order from its source to its mouth along its middle,
## the way it flows (terrain draws the current from the order); as
## [{path: [Vector2i]}]. A path cell that is no water (a ford, or under a
## bridge, is), or that is not beside the one before, is said in
## [param warnings] and the stream left out.
static func streams_from(config: Dictionary, terrain: Dictionary, warnings: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var listed: Variant = config.get("streams", [])
	if not listed is Array:
		warnings.append("\"streams\" in level.json is not a list")
		return out
	var wet := {}
	for key in ["water", "fords", "bridged"]:
		for cell: Vector2i in terrain.get(key, []):
			wet[cell] = true
	for index in (listed as Array).size():
		var entry: Variant = listed[index]
		var raw: Variant = entry.get("path", []) if entry is Dictionary else null
		if not raw is Array or (raw as Array).size() < 2:
			warnings.append("stream %d has no path of two cells or more: left out" % index)
			continue
		var path: Array[Vector2i] = []
		var bad := ""
		for each: Variant in raw:
			var cell: Variant = _tile(each)
			if cell == null or not wet.has(cell):
				bad = "%s is no water" % [each]
				break
			if not path.is_empty():
				var step: Vector2i = cell - path[-1]
				if maxi(absi(step.x), absi(step.y)) != 1:
					bad = "%s is not beside %s" % [cell, path[-1]]
					break
			path.append(cell)
		if not bad.is_empty():
			warnings.append("stream %d: %s: left out" % [index, bad])
			continue
		out.append({"path": path})
	return out


## Tall grass under a building (any footprint) is left out (decision 508).
static func _clear_tall_grass(level: Dictionary, warnings: Array[String]) -> void:
	var grass: Array = level["terrain"]["tall_grass"]
	if grass.is_empty():
		return
	for building: Dictionary in level["buildings"]:
		for cell in building_cells(building):
			if cell in grass:
				grass.erase(cell)
				warnings.append("the tall grass at %s is under a building: left out" % [cell])


## A ford beside no water (nor another ford, nor under a bridge) is in no
## stream: said in [param warnings] (decision 505).
## Water over relief (decision 525): its cells hold its surface, so a
## stream steps only down along its path, a pond (water no stream runs
## through) lies level within Relief.PAD_FLAT, and the ground beside any
## water stands at least Relief.SHORE_LIP over it (the views' bank). What
## is not so is said in [param warnings], once a body; nothing is changed.
## A level with no relief.png's water is level by its whole levels.
## The ledges [param terrain] (a parsed level's) has, as level.json's
## "ledges" (decision 585): Curves.trace_ledges over its relief's cliff
## edges between its walkable cells and its water; [] with no relief. The
## level tools write them, and MapDoc.save writes them again when the relief
## changed, so the editor's height brush and stairs keep them in step.
static func ledges_of(terrain: Dictionary) -> Array:
	if not terrain.has("relief") or (terrain["relief"] as PackedFloat32Array).is_empty():
		return []
	var ground := {}
	var water := {}
	for cell: Vector2i in terrain["floor"]:
		ground[cell] = true
	for key in ["water", "fords", "bridged"]:
		for cell: Vector2i in terrain.get(key, []):
			ground[cell] = true
			water[cell] = true
	return Curves.trace_ledges(terrain["relief"], terrain["relief_size"], ground, water)


## level.json's "ledges" (decision 585: Curves.parse_ledges), the views'
## faces and rims drawn along them; cliff_between still rules the walk. A
## ledge whose cliff the relief does not have (more than a quarter of its
## sampled points that drop more than the walk with no cliff between the
## cells either side of them) is said in [param warnings]: trace again
## (Curves.trace_ledges; MapDoc.save does).
static func _ledges(terrain: Dictionary, config: Dictionary, warnings: Array[String]) -> Array[Dictionary]:
	var ledges := Curves.parse_ledges(config, warnings)
	if ledges.is_empty() or not terrain.has("relief"):
		return ledges
	var field: PackedFloat32Array = terrain["relief"]
	var size: Vector2i = terrain["relief_size"]
	for index in ledges.size():
		var curve: Dictionary = ledges[index]["curve"]
		var points: PackedVector2Array = curve["points"]
		var steep := 0
		var missing := 0
		for i in points.size():
			if float(curve["tops"][i]) - float(curve["feet"][i]) <= Relief.WALK_RISE:
				continue
			steep += 1
			var across := Vector2(-curve["tangents"][i].y, curve["tangents"][i].x) * 0.5
			var one := Vector2i((points[i] + across).round())
			var other := Vector2i((points[i] - across).round())
			if one != other and not Relief.cliff_between(Relief.at(field, size, one), Relief.at(field, size, other)):
				missing += 1
		if missing * 4 > steep:
			warnings.append("ledge %d: %d of its %d steep points have no cliff across them in the relief" % [index, missing, steep])
	return ledges


static func _check_water(terrain: Dictionary, warnings: Array[String]) -> void:
	if not terrain.get("relief_given", false):
		return
	# A bridge's deck is a shore to the water beside it, as walked.
	var field := walk_relief(terrain)
	var size: Vector2i = terrain["relief_size"]
	var bridged: Array = terrain.get("bridged", [])
	var flowing: Dictionary[Vector2i, bool] = {}
	for stream: Dictionary in terrain.get("streams", []):
		var path: Array = stream["path"]
		var last := INF
		for cell: Vector2i in path:
			flowing[cell] = true
			if cell in bridged:
				continue
			var here := Relief.at(field, size, cell)
			if here > last + Relief.EPSILON:
				warnings.append("the stream from %s rises at %s (%.2f m after %.2f m): water runs down" % [path[0], cell, here, last])
				break
			last = here
	var wet: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in terrain.get("water", []):
		wet[cell] = true
	for cell: Vector2i in terrain.get("fords", []):
		wet[cell] = true
	var ground: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in terrain["floor"]:
		ground[cell] = true
	var seen: Dictionary[Vector2i, bool] = {}
	for start: Vector2i in wet:
		if seen.has(start):
			continue
		var body: Array[Vector2i] = [start]
		seen[start] = true
		var i := 0
		while i < body.size():
			for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var next := body[i] + direction
				if wet.has(next) and not seen.has(next):
					seen[next] = true
					body.append(next)
			i += 1
		if not body.any(func(cell: Vector2i) -> bool: return flowing.has(cell)) and not Relief.flat(field, size, body):
			warnings.append("the pond at %s is not level (within %.2f m): water lies level" % [start, Relief.PAD_FLAT])
		var low_shore := _low_shore(field, size, body, wet, ground, bridged)
		if not low_shore.is_empty():
			warnings.append("the water at %s has its shore at %s less than %.1f m over it" % [low_shore[0], low_shore[1], Relief.SHORE_LIP])


## The first water cell of [param body] with a dry floor neighbour (not a
## bridge's) under Relief.SHORE_LIP over it, and that neighbour; [] if none.
static func _low_shore(field: PackedFloat32Array, size: Vector2i, body: Array[Vector2i], wet: Dictionary, ground: Dictionary,
		bridged: Array) -> Array[Vector2i]:
	for cell in body:
		for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var shore := cell + direction
			if ground.has(shore) and not wet.has(shore) and not shore in bridged 					and Relief.at(field, size, shore) < Relief.at(field, size, cell) + Relief.SHORE_LIP - Relief.EPSILON:
				return [cell, shore]
	return []


static func _check_fords(terrain: Dictionary, warnings: Array[String]) -> void:
	var wet := {}
	for key in ["water", "fords", "bridged"]:
		for cell: Vector2i in terrain.get(key, []):
			wet[cell] = true
	for cell: Vector2i in terrain.get("fords", []):
		var beside := false
		for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			beside = beside or wet.has(cell + direction)
		if not beside:
			warnings.append("the ford at %s is beside no water: in no stream" % [cell])


## The cues a link's piece may be (decision 589): "arch" (a gate arch over
## it), "waystones" (a pair either side), "down" (a stair down, a dark
## mouth), "up" (a stair up, or a climb), "sealed" (shut), "none".
const CUES: Array[String] = ["arch", "waystones", "down", "up", "sealed", "none"]
## Each cue's art-kit slot (waystones: two, either side of the link).
const CUE_SLOTS := {"arch": "building.link_arch", "waystones": "building.waystone", "down": "building.stair_down", "up": "building.stair_up"}


## The pieces that show where each of [param level]'s links leads (decision
## 589; Jeff: "strong visual cues of where the zone transition is,
## descending/ascending steps, arches"), drawn only (the cell stays clear,
## 571): [{tile, cue, facing, variant}]. A link's own "cue" wins; else a
## hidden one shows nothing and a sealed one "sealed"; one on a solid
## building's door none (the building is the cue: the barrow's mound); to
## a deeper level (level.json "depth", 0 if not said) "down", a shallower
## "up"; between two outdoor levels an "arch", "waystones" where it stands
## at the map's edge (an arch would hang off it); else none. Facing the
## way out: toward the edge it is on, or away from the open ground it is
## walked into from (an arch's or waystones': toward the map's nearest
## edge). "variant" as the link says (1: a timber arch, a stone
## stair; 2: a stone arch, a timber stair or a ladder).
static func link_cues(level: Dictionary, config: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var size: Vector2i = level["size"]
	var depth := int(config.get("depth", 0))
	var outdoor := zone_of(config) == "outdoors"
	var doors := {}
	for building: Dictionary in level.get("buildings", []):
		var door := solid_door_of(building)
		if door != NO_DOOR:
			doors[door] = true
	var floor := {}
	for cell: Vector2i in level["terrain"]["floor"]:
		floor[cell] = true
	var entries := {}
	for entry: Variant in config.get("links", []):
		if entry is Dictionary and _tile(entry.get("at")) != null:
			entries[_tile(entry.get("at"))] = entry
	for link: Dictionary in level["links"]:
		var at: Vector2i = link["tile"]
		var entry: Dictionary = entries.get(at, {})
		var far := template_config(str(link["to_map"]))
		var cue := "none"
		if str(entry.get("cue", "")) in CUES:
			cue = str(entry["cue"])
		elif link["hidden"]:
			cue = "none"
		elif link["sealed"] != "" or link["closed"]:
			cue = "sealed"
		elif doors.has(at):
			cue = "none"
		elif int(far.get("depth", 0)) > depth:
			cue = "down"
		elif int(far.get("depth", 0)) < depth:
			cue = "up"
		elif outdoor and zone_of(far) == "outdoors":
			cue = "waystones" if _edge_way(at, size) != Vector2i.ZERO else "arch"
		var facing := _edge_way(at, size)
		if cue in ["arch", "waystones"]:
			# An overland way: out toward the map's nearest edge.
			var gaps := {Vector2i(-1, 0): at.x, Vector2i(1, 0): size.x - 1 - at.x, Vector2i(0, -1): at.y, Vector2i(0, 1): size.y - 1 - at.y}
			facing = Vector2i(-1, 0)
			for way: Vector2i in gaps:
				if gaps[way] < gaps[facing]:
					facing = way
		elif facing == Vector2i.ZERO:
			# Away from the open ground it is walked into from.
			var from := Vector2i.ZERO
			for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if floor.has(at + step):
					from += step
			facing = -from.clamp(-Vector2i.ONE, Vector2i.ONE) if from != Vector2i.ZERO else Vector2i(0, 1)
			if facing.x != 0 and facing.y != 0:
				facing.y = 0
		link["cue"] = cue  # The big map marks it (ui).
		out.append({"tile": at, "cue": cue, "facing": facing, "variant": maxi(1, int(entry.get("variant", 1)))})
	return out


## The way to the map's edge from [param at] if it stands within two cells
## of one ([param size] cells), else (0, 0).
static func _edge_way(at: Vector2i, size: Vector2i) -> Vector2i:
	if at.x <= 1:
		return Vector2i(-1, 0)
	if at.x >= size.x - 2:
		return Vector2i(1, 0)
	if at.y <= 1:
		return Vector2i(0, -1)
	if at.y >= size.y - 2:
		return Vector2i(0, 1)
	return Vector2i.ZERO


## A solid building's door, given its entry or its parsed record: the front
## row's middle (550), or NO_DOOR for a DOORLESS one (567).
static func solid_door_of(building: Dictionary) -> Vector2i:
	if str(building.get("slot", "")) in DOORLESS:
		return NO_DOOR
	var rect: Rect2i = building["rect"] if building.has("rect") else building_rect(building)
	var facing: Vector2i = building["facing"] if building.get("facing") is Vector2i else building_facing(building)
	return solid_door(rect, facing)


## A solid building's door (decision 550): the front row's middle.
static func solid_door(rect: Rect2i, facing: Vector2i) -> Vector2i:
	return front_cell(rect, facing) - facing


## The solid buildings in [param level] (SOLID, decision 550) laid into its
## terrain: each footprint cell but its door (the front row's middle, the
## building's "door") out of the floor and into terrain "solid".
static func _lay_solid(level: Dictionary) -> void:
	var terrain: Dictionary = level["terrain"]
	var solid: Array[Vector2i] = []
	for building: Dictionary in level["buildings"]:
		if not str(building["slot"]) in SOLID:
			continue
		var door := solid_door_of(building)
		if door != NO_DOOR:
			building["door"] = door
		for cell in rect_cells(building["rect"]):
			if cell != door:
				terrain["floor"].erase(cell)
				solid.append(cell)
	terrain["solid"] = solid


## The bridges in [param level]'s buildings laid into its terrain: their
## cells floor at the banks' height (footing the banks' ground), no longer
## water but "bridged" (drawn with the water under), railings on their long
## sides ("railings", wall edges).
static func _lay_bridges(level: Dictionary) -> void:
	var terrain: Dictionary = level["terrain"]
	var bridged: Array[Vector2i] = []
	var decks: Dictionary[Vector2i, float] = {}
	var railings: Array[Vector3i] = []
	for building: Dictionary in level["buildings"]:
		if building["slot"] != BRIDGE:
			continue
		var rect: Rect2i = building["rect"]
		var along := Vector2i(absi(building["facing"].x), absi(building["facing"].y))
		var sides: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0)]
		if along.x != 0:
			sides = [Vector2i(0, 1), Vector2i(0, -1)]
		var bank_kind := str(terrain["kinds"].get(building["banks"][0], "stone"))
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var cell := Vector2i(x, y)
				terrain["water"].erase(cell)
				terrain["fords"].erase(cell)
				if not cell in terrain["floor"]:
					terrain["floor"].append(cell)
				terrain["kinds"][cell] = bank_kind
				if int(building["height"]) > 0:
					terrain["heights"][cell] = int(building["height"])
				# Its deck's height apart from the relief, which keeps the water
				# under it (505 amended): walk_relief lays it back for walking.
				decks[cell] = float(building["elevation"])
				bridged.append(cell)
				for side in sides:
					if not rect.has_point(cell + side):
						var key := Terrain.edge_key(cell, side)
						terrain["edges"][key] = Terrain.Edge.WALL
						railings.append(key)
	terrain["bridged"] = bridged
	terrain["railings"] = railings
	terrain["decks"] = decks


## [param terrain]'s relief as it is walked (505 amended): each bridge's
## deck (terrain "decks") laid over the water the relief keeps under it. A
## copy; the terrain's own relief is the ground and the water, the deck
## never in it. World, WorldMap's routes and the view walk and stand bodies
## on this.
static func walk_relief(terrain: Dictionary) -> PackedFloat32Array:
	var field: PackedFloat32Array = (terrain.get("relief", PackedFloat32Array()) as PackedFloat32Array).duplicate()
	var size: Vector2i = terrain.get("relief_size", Vector2i.ZERO)
	var decks: Dictionary = terrain.get("decks", {})
	for cell: Vector2i in decks:
		if Relief.on_map(size, cell) and cell.y * size.x + cell.x < field.size():
			field[cell.y * size.x + cell.x] = float(decks[cell])
	return field


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


## The roof sets a level.json roof may name (art-kit's roof.<set>.*,
## decision 364).
const ROOF_SETS: Array[String] = ["shingle"]


## level.json's "roofs", [{rect: [x, y, w, h], the cells it covers, set:
## one of ROOF_SETS, ridge: "x" or "z" (along the map's x or y; along the
## long side if not given), use and town (as a building's, _link)}], as
## {rect (Rect2i), set, ridge, height (its cells'), use, town}: a roof
## drawn by a tiling set over a room that is no building slot (decision
## 364). A roof covers only floor of one height, clear of the buildings and
## the other roofs: one that does not, or names no set there is, is left
## out, said in [param warnings]. Its outline need not be walled (a
## shelter on posts). A town has one of each use, [param buildings]'
## links counted.
static func roofs_from(config: Dictionary, terrain: Dictionary, buildings: Array[Dictionary], warnings: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var listed: Variant = config.get("roofs", [])
	if not listed is Array:
		warnings.append("\"roofs\" in level.json is not a list")
		return out
	var ground: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in terrain["floor"]:
		ground[cell] = true
	var taken: Dictionary[Vector2i, bool] = {}
	var linked := {}
	for building in buildings:
		for cell in building_cells(building):
			taken[cell] = true
		if not str(building["use"]).is_empty():
			linked[str(building["town"]) + "/" + str(building["use"])] = building["cell"]
	for entry: Variant in listed:
		var rect: Variant = town_wall_rect(entry)
		if rect == null:
			warnings.append("the roof %s has no \"rect\" [x, y, w, h]" % [entry])
			continue
		var roof_set := str(entry.get("set", ROOF_SETS[0]))
		if not roof_set in ROOF_SETS:
			warnings.append("the roof at %s is of set \"%s\": one of %s; left out" % [rect.position, roof_set, ", ".join(ROOF_SETS)])
			continue
		var cells := rect_cells(rect)
		var height: int = terrain["heights"].get(cells[0], 0)
		var bad := cells.filter(func(cell: Vector2i) -> bool: return not ground.has(cell) or taken.has(cell))
		if bad.is_empty():
			bad = _uneven(terrain, cells)
		if not bad.is_empty():
			warnings.append("the roof at %s is not all over clear floor of one height, clear of buildings and roofs (%s): left out" % [rect.position, bad[0]])
			continue
		for cell in cells:
			taken[cell] = true
		var ridge := str(entry.get("ridge", ""))
		if not ridge in ["x", "z"]:
			ridge = "x" if rect.size.x > rect.size.y else "z"
		var roof := {"slot": "roof", "cell": rect.position, "rect": rect, "set": roof_set, "ridge": ridge, "height": height, "use": "", "town": ""}
		_link(roof, entry, config, linked, warnings)
		out.append(roof)
	return out


## The cells of a damaged roof over [param rect] that are broken open to
## the sky: a third of them by a hash of where each is, the same on every
## peer and in the sim (Fields) and the view (holes), and never none.
static func broken_cells(rect: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var least := -1
	var least_cell := rect.position
	for cell in rect_cells(rect):
		var hash := (cell.x * 374761393 + cell.y * 668265263) & 0x7fffffff
		hash = ((hash ^ (hash >> 13)) * 1274126177) & 0x7fffffff
		hash = (hash ^ (hash >> 16)) & 0xffff
		if hash % 3 == 0:
			out.append(cell)
		if least < 0 or hash < least:
			least = hash
			least_cell = cell
	if out.is_empty():
		out.append(least_cell)
	return out


## A level.json town wall's or roof's rect (null if it has none).
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


## A level.json building entry's footprint (null if it has no "at", or no
## slot in BUILDINGS nor a kind and size in kinds()): a kind's the box
## round its blocks (building_blocks).
## A building's code letter (decision 537): its kind's first letter, or
## its slot's (building.house: H), upper case; X for neither.
static func code_letter(entry: Variant) -> String:
	if not entry is Dictionary:
		return "X"
	var name := str(entry.get("kind", "")) if entry.has("kind") else str(entry.get("slot", "")).trim_prefix("building.")
	return name.left(1).to_upper() if not name.is_empty() else "X"


## Each of [param entries]' codes, in order (decision 537): its own
## "code" (written in by fill_codes), else its letter and the next number
## past the highest that letter has had: [param given] (level.json's
## "building_codes", letter -> the last number given) or any code present.
## So a building keeps its code when another is added or taken away, and
## a taken one's code is never given again once written. A code a second
## entry repeats (a pasted copy) is given afresh.
static func building_codes(entries: Variant, given: Variant) -> Array[String]:
	var out: Array[String] = []
	if not entries is Array:
		return out
	var last := {}
	if given is Dictionary:
		for letter: Variant in given:
			last[str(letter)] = int(given[letter])
	for entry: Variant in entries:
		if entry is Dictionary and entry.has("code"):
			var code := str(entry["code"])
			last[code.left(1)] = maxi(int(last.get(code.left(1), 0)), code.substr(1).to_int())
	var seen := {}
	for entry: Variant in entries:
		var code := str(entry.get("code", "")) if entry is Dictionary else ""
		if code.is_empty() or seen.has(code):
			var letter := code_letter(entry)
			last[letter] = int(last.get(letter, 0)) + 1
			code = "%s%d" % [letter, last[letter]]
		seen[code] = true
		out.append(code)
	return out


## Writes building_codes into [param config]'s buildings that lack one
## (or repeat one) and keeps "building_codes" at each letter's highest, so
## a deleted building's code is not given again (decision 537; MapDoc.save
## and builder mode). Whether it changed anything.
static func fill_codes(config: Dictionary) -> bool:
	if not config.get("buildings") is Array or (config["buildings"] as Array).is_empty():
		return false
	var entries: Array = config["buildings"]
	var codes := building_codes(entries, config.get("building_codes", {}))
	var changed := false
	var given: Dictionary = (config.get("building_codes", {}) as Dictionary).duplicate() if config.get("building_codes") is Dictionary else {}
	for i in entries.size():
		if not entries[i] is Dictionary:
			continue
		if str(entries[i].get("code", "")) != codes[i]:
			entries[i]["code"] = codes[i]
			changed = true
		var letter := codes[i].left(1)
		if int(given.get(letter, 0)) < codes[i].substr(1).to_int():
			given[letter] = codes[i].substr(1).to_int()
			changed = true
	if changed:
		config["building_codes"] = given
	return changed


static func building_rect(entry: Variant) -> Variant:
	if not entry is Dictionary:
		return null
	var size: Variant = BUILDINGS.get(str(entry.get("slot", "")))
	if str(entry.get("slot", "")) == BRIDGE:
		size = Vector2i(clampi(int(entry.get("width", 1)), 1, 2), maxi(int(entry.get("length", 1)), 1))
	if size == null:
		var spec := kind_size(entry)
		size = _frame(spec) if not spec.is_empty() else null
	var at: Variant = _tile(entry.get("at"))
	if at == null or size == null:
		return null
	return Rect2i(at, size if building_facing(entry).x == 0 else Vector2i(size.y, size.x))


## levels/buildings.json's kinds (decision 488), read once.
static func kinds() -> Dictionary:
	if _kinds.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(KINDS_FILE))
		if not parsed is Dictionary:
			push_error("Level: %s does not read as JSON: no building kinds" % KINDS_FILE)
		_kinds = parsed.get("kinds", {}) if parsed is Dictionary else {}
		for kind: String in _kinds:
			for size: String in _kinds[kind].get("sizes", {}):
				var main := main_block(_kinds[kind]["sizes"][size])
				if mini(main.size.x, main.size.y) < MIN_ROOM:
					push_error("Level: kind %s %s's main block is %s, under MIN_ROOM %d each way" % [kind, size, main.size, MIN_ROOM])
				var plot: Vector2i = PLOT_CLASSES.get(str(_kinds[kind].get("plot", "")), Vector2i.ZERO)
				var frame := _frame(_kinds[kind]["sizes"][size])
				if frame.x > plot.x or frame.y > plot.y:
					push_error("Level: kind %s %s (%s) does not fit its plot class \"%s\" (%s)" % [kind, size, frame, _kinds[kind].get("plot", ""), plot])
			var stage := str(_kinds[kind].get("stage", ""))
			if not stage in STAGES and stage != SET_STAGE:
				push_error("Level: kind %s names no stage of %s, nor \"%s\"" % [kind, STAGES, SET_STAGE])
	return _kinds


## The kinds a town at [param stage] may build: its stage's and every
## earlier one's, in the kinds file's order.
static func kinds_at(stage: String) -> Array[String]:
	var reached := STAGES.find(stage)
	var out: Array[String] = []
	for kind: String in kinds():
		var first := STAGES.find(str(kinds()[kind].get("stage", "")))
		if first >= 0 and first <= reached:
			out.append(kind)
	return out


## The plot a kind is laid on (PLOT_CLASSES): its class's footprint, across
## by deep, front +y; ZERO for a kind of none.
static func plot_of(kind: String) -> Vector2i:
	return PLOT_CLASSES.get(str(kinds().get(kind, {}).get("plot", "")), Vector2i.ZERO)


## A kind size's main block ({blocks}: the one whose role is "main", else
## its first), in its own frame.
static func main_block(spec: Dictionary) -> Rect2i:
	var blocks: Array = spec.get("blocks", [])
	for block: Array in blocks:
		if block.size() > 4 and str(block[4]) == "main":
			return Rect2i(int(block[0]), int(block[1]), int(block[2]), int(block[3]))
	if blocks.is_empty():
		return Rect2i()
	var first: Array = blocks[0]
	return Rect2i(int(first[0]), int(first[1]), int(first[2]), int(first[3]))


## The size a kind building [param entry] names ({blocks, doors}), {} if
## its kind or size is none there.
static func kind_size(entry: Dictionary) -> Dictionary:
	var kind: Dictionary = kinds().get(str(entry.get("kind", "")), {})
	return kind.get("sizes", {}).get(str(entry.get("size", KIND_SIZE)), {})


## A kind size's frame: across by deep, round its blocks.
static func _frame(spec: Dictionary) -> Vector2i:
	var out := Vector2i.ZERO
	for block: Array in spec.get("blocks", []):
		out = out.max(Vector2i(int(block[0]) + int(block[2]), int(block[1]) + int(block[3])))
	return out


## Cell [param local] of a frame [param size] (its front +y) turned to
## [param facing]: the offset from the turned frame's top-left. The same
## turn as Prefab.rotated's, so a stamped kind turned is its facing's.
static func _turned(local: Vector2i, size: Vector2i, facing: Vector2i) -> Vector2i:
	match facing:
		Vector2i(0, -1):
			return Vector2i(size.x - 1 - local.x, size.y - 1 - local.y)
		Vector2i(1, 0):
			return Vector2i(local.y, size.x - 1 - local.x)
		Vector2i(-1, 0):
			return Vector2i(size.y - 1 - local.y, local.x)
	return local


static func _turned_side(side: Vector2i, facing: Vector2i) -> Vector2i:
	match facing:
		Vector2i(0, -1):
			return -side
		Vector2i(1, 0):
			return Vector2i(side.y, -side.x)
		Vector2i(-1, 0):
			return Vector2i(-side.y, side.x)
	return side


## A level.json building entry's blocks on the map ([] for none): a slot's
## its footprint, a kind's each of its size's, turned to its facing.
static func building_blocks(entry: Variant) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var rect: Variant = building_rect(entry)
	if rect == null:
		return out
	if not entry.has("kind") or BUILDINGS.has(str(entry.get("slot", ""))):
		out.append(rect)
		return out
	var spec := kind_size(entry)
	var size := _frame(spec)
	var facing := building_facing(entry)
	for block: Array in spec["blocks"]:
		var a := _turned(Vector2i(int(block[0]), int(block[1])), size, facing)
		var b := _turned(Vector2i(int(block[0]) + int(block[2]) - 1, int(block[1]) + int(block[3]) - 1), size, facing)
		out.append(Rect2i(rect.position + a.min(b), (a - b).abs() + Vector2i.ONE))
	return out


## A kind building entry's doors on the map, as Terrain edge keys.
static func kind_doors(entry: Dictionary) -> Array[Vector3i]:
	return _kind_edges(entry, "doors")


## The outline edges a kind size leaves open, no wall and no door (its
## "open", [x, y, side] as its doors: a forge's front under its lean-to),
## where [param entry] stands them.
static func kind_open(entry: Dictionary) -> Array[Vector3i]:
	return _kind_edges(entry, "open")


static func _kind_edges(entry: Dictionary, list: String) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var rect: Variant = building_rect(entry)
	var spec := kind_size(entry)
	if rect == null or spec.is_empty():
		return out
	var size := _frame(spec)
	var facing := building_facing(entry)
	for door: Array in spec.get(list, []):
		var cell: Vector2i = rect.position + _turned(Vector2i(int(door[0]), int(door[1])), size, facing)
		out.append(Terrain.edge_key(cell, _turned_side(DOOR_SIDES[str(door[2])], facing)))
	return out


## The ways into a kind [param building]: its doors, then its open edges.
static func entrances(building: Dictionary) -> Array:
	return (building.get("doors", []) as Array) + (building.get("open", []) as Array)


## Sets kind building [param building]'s own from [param entry]: its kind,
## size, its blocks' roles, seed (its entry's, else from its cell, so every peer draws it
## alike), ruined (no roof, no inside), its kind's words, sets, storeys,
## eaves and place, its open edges, and its front (the cell outside its
## first door, else its first open edge).
static func _kind_of(building: Dictionary, entry: Dictionary) -> void:
	var kind: Dictionary = kinds()[str(entry["kind"])]
	var at: Vector2i = building["cell"]
	building["kind"] = str(entry["kind"])
	building["size"] = str(entry.get("size", KIND_SIZE))
	building["seed"] = int(entry["seed"]) if entry.get("seed") is float or entry.get("seed") is int else hash(Vector2i(at))
	building["ruined"] = bool(entry.get("ruined", false))
	building["words"] = str(kind.get("words", "a building"))
	building["wall_set"] = str(kind.get("wall_set", ""))
	building["floor_set"] = str(kind.get("floor_set", ""))
	building["roof"] = str(kind.get("roof", "gable"))
	building["roof_set"] = str(kind.get("roof_set", ""))
	building["storeys"] = int(kind.get("storeys", 1))
	building["eaves"] = float(kind.get("eaves", STOREY * building["storeys"]))
	building["place"] = str(kind.get("place", ""))
	# Each block's role, as its blocks are ordered (main, wing, leanto, ...).
	building["roles"] = (kind_size(entry)["blocks"] as Array).map(func(block: Array) -> String:
		return str(block[4]) if block.size() > 4 else "main")
	building["doors"] = kind_doors(entry)
	building["open"] = kind_open(entry)
	var ways := entrances(building)
	if not ways.is_empty():
		var sides := Terrain.edge_cells(ways[0])
		var cells := _union(building["blocks"])
		building["front"] = sides[1] if cells.has(sides[0]) else sides[0]


## Where the work of [param building]'s build goes on (decision 566,
## buildings' side; npc's goal cells for its carpenter): "work" the cell
## inside its first door, "woodpile" one beside the cell outside it (the
## side its seed picks, else the other: never one of its own cells),
## "sawbuck" the one on its other side (else one further out from the
## door), and "saw" the one beyond the sawbuck from the door, where the
## carpenter stands to saw, facing it (566 amended, the coordinator's: the
## saw lands on the sawbuck). Its first open edge where it has no door;
## a building with neither has its first cell for all.
static func site_cells(building: Dictionary) -> Dictionary:
	var cells := building_cells(building)
	var doors := entrances(building)
	if doors.is_empty():
		return {"work": cells[0], "woodpile": cells[0], "sawbuck": cells[0], "saw": cells[0]}
	var sides := Terrain.edge_cells(doors[0])
	var inside: Vector2i = sides[0] if cells.has(sides[0]) else sides[1]
	var outside: Vector2i = sides[1] if inside == sides[0] else sides[0]
	var across := Vector2i(absi(outside.y - inside.y), absi(outside.x - inside.x))
	var first := 1 if int(building["seed"]) % 2 == 0 else -1
	var woodpile := outside + across * first
	var sawbuck := outside - across * first
	if cells.has(woodpile):
		woodpile = sawbuck
		sawbuck = outside + across * first
	if cells.has(sawbuck) or sawbuck == woodpile:
		sawbuck = outside + (outside - inside)
	return {"work": inside, "woodpile": woodpile, "sawbuck": sawbuck, "saw": sawbuck + (outside - inside)}


## The cells of [param blocks], each once.
static func _union(blocks: Array) -> Array[Vector2i]:
	var seen: Dictionary[Vector2i, bool] = {}
	for rect: Rect2i in blocks:
		for cell in rect_cells(rect):
			seen[cell] = true
	var out: Array[Vector2i] = []
	out.assign(seen.keys())
	return out


## A parsed building's cells: its blocks' (decision 488), its rect's for one
## from before blocks.
static func building_cells(building: Dictionary) -> Array[Vector2i]:
	return _union(building.get("blocks", [building["rect"]]))


## A parsed building's outline: the edges round its blocks' union.
static func building_outline(building: Dictionary) -> Array[Vector3i]:
	return blocks_outline(building_cells(building))


## The edges round [param cells] (Terrain edge keys): each side of a cell
## whose neighbour there is not one of them.
static func blocks_outline(cells: Array[Vector2i]) -> Array[Vector3i]:
	var inside: Dictionary[Vector2i, bool] = {}
	for cell in cells:
		inside[cell] = true
	var out: Array[Vector3i] = []
	for cell in cells:
		for side: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			if not inside.has(cell + side):
				out.append(Terrain.edge_key(cell, side))
	return out


## Whether a parsed building has an inside: walked into under a roof (not a
## well, a field or a ruin).
static func has_inside(building: Dictionary) -> bool:
	return not str(building.get("slot", "")) in ON_WATER and not str(building.get("slot", "")) in OPEN_AIR \
			and not str(building.get("slot", "")) in SOLID \
			and not str(building.get("slot", "")) in SPANS_WATER and not building.get("ruined", false)


## Each cell inside [param buildings] (has_inside) -> that building's index:
## level["building_cells"], what asks which building a cell is in reads.
static func inside_cells(buildings: Array) -> Dictionary[Vector2i, int]:
	var out: Dictionary[Vector2i, int] = {}
	for index in buildings.size():
		if has_inside(buildings[index]):
			for cell in building_cells(buildings[index]):
				out[cell] = index
	return out


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
	var spec := {"script": ANIMAL if Animal.is_wild(type) else MONSTER, "shape": "capsule", "props": props, "kind": type}
	var own_script := str(Monster.kinds().get(type, {}).get("script", ""))
	if not own_script.is_empty():
		spec["script"] = own_script  # A kind of its own class (the draugr, decision 548).
	# Its kind's name over it ("Wild doe"; 397 amended), not its spawn name.
	var label := str(Monster.kinds().get(type, {}).get("label", ""))
	if not label.is_empty():
		spec["label"] = label
	return spec


## A loot table rolled into [param props]' slots (decision 330): the
## entry's "loot", else level.json's "loot" for the kind ("chest"; a
## monster's own kind, else "monster", which leaves wild animals out). A
## chest's empty slots are filled (a depot or a shop counter keeps none); a
## monster carries up to MONSTER_CARRIES. Seeded by the level's name and
## [param at]: the same each time the level is built.
static func _stock(props: Dictionary, spec: Dictionary, entry: Dictionary, config: Dictionary, warnings: Array[String], at: Vector2i) -> void:
	var script := str(spec.get("script", ""))
	if script == CHEST and props.has("cache"):
		# A cache keeps no slots of its own: each player's find is rolled as they search (decision 599).
		if not Items.has_loot(str(props["cache"])):
			warnings.append("cache at %s: no loot table \"%s\" (levels/loot.json has %s)" % [at, props["cache"], ", ".join(Items.loot_tables().keys())])
		if entry.has("loot"):
			warnings.append("loot at %s: a cache rolls its own find (its \"cache\" table); no loot" % at)
		return
	var chest: bool = script == CHEST and not props.get("depot", false) and not props.get("shop", false)
	var monster := script == MONSTER or script == ANIMAL or _own_class(spec)
	var kind := str(spec.get("kind", ""))
	var defaults: Variant = config.get("loot", {})
	var table := ""
	if entry.has("loot"):
		table = str(entry["loot"])
		if not (chest or monster):
			warnings.append("loot at %s: only a chest or a monster takes a loot table" % at)
			return
	elif defaults is Dictionary and chest:
		table = str(defaults.get("chest", ""))
	elif defaults is Dictionary and monster:
		table = str(defaults.get(kind, "" if Animal.is_wild(kind) else defaults.get("monster", "")))
	if table.is_empty():
		return
	if not Items.has_loot(table):
		warnings.append("loot at %s: no loot table \"%s\" (levels/loot.json has %s)" % [at, table, ", ".join(Items.loot_tables().keys())])
		return
	var slots := Items.tidy(props.get("slots", []), Chest.SLOTS if chest else MONSTER_CARRIES)
	var empty: Array[int] = []
	for slot in slots.size():
		if slots[slot].is_empty():
			empty.append(slot)
	var rolled := Items.roll_loot(table, "%s:%d,%d" % [str(config.get("name", "")), at.x, at.y], empty.size())
	for i in rolled.size():
		slots[empty[i]] = rolled[i]
	props["slots"] = slots


## Whether [param spec] is a monster of a kind with a class of its own
## (levels/monsters.json "script", the draugr's, decision 548): a monster
## as Monster's own are, its hands, loot and home given the same.
static func _own_class(spec: Dictionary) -> bool:
	var own := str(Monster.kinds().get(str(spec.get("kind", "")), {}).get("script", ""))
	return not own.is_empty() and spec.get("script") == own


## A monster's hands (decision 338): its entry's "wields", else its
## kind's (levels/monsters.json), {"right": id, "left": id}. Its slots
## become a carrier's (Items.CARRIED: the pack, what loot gave it, then the
## two hands), and it fights with them (World.holds_in_hands). A two-handed
## thing goes in the right hand only, the left then empty; an unknown id,
## one that cannot be held, or a left hand that has no room is warned
## about and left out.
static func _arm(props: Dictionary, spec: Dictionary, entry: Dictionary, warnings: Array[String], at: Vector2i) -> void:
	var script := str(spec.get("script", ""))
	if script != MONSTER and script != ANIMAL and not _own_class(spec):
		if entry.has("wields"):
			warnings.append("wields at %s: only a monster wields things" % at)
		return
	var row: Dictionary = Monster.kinds().get(str(spec.get("kind", "")), {})
	var given: Variant = entry.get("wields", row.get("wields", {}))
	if not given is Dictionary or given.is_empty():
		return
	var slots := Items.tidy(props.get("slots", []), Items.CARRIED)
	for hand: Array in [["right", Items.RIGHT_HAND], ["left", Items.LEFT_HAND]]:
		var id := str(given.get(hand[0], ""))
		if id.is_empty():
			continue
		if not Items.exists(id) or int(Items.def(id)["hands"]) == 0:
			warnings.append("wields at %s: %s cannot be held" % [at, id])
			continue
		var right := slots[Items.RIGHT_HAND]
		if hand[1] == Items.LEFT_HAND and (int(Items.def(id)["hands"]) == 2 or not right.is_empty() and int(Items.def(right)["hands"]) == 2):
			warnings.append("wields at %s: no left hand free for %s" % [at, id])
			continue
		slots[hand[1]] = id
	props["slots"] = slots


## A monster spawned outside a level (a raid's, Raids) armed by its kind's
## "wields" as a level's are (_arm; decision 481: raiders came bare-handed).
static func arm(spec: Dictionary) -> void:
	var props: Dictionary = spec.get("props", {})
	var warnings: Array[String] = []
	var at: Variant = spec.get("tile")
	_arm(props, spec, {}, warnings, at if at is Vector2i else Vector2i.ZERO)
	for warning in warnings:
		push_warning("[level] " + warning)
	if not props.is_empty():
		spec["props"] = props


## Whether [param spec] is a chest, a crate, a cart or a monster: what keeps
## or carries things a make or a grave mark is set on (474, 555). A monster
## kind with a class of its own (levels/monsters.json "script", the draugr's,
## 548) is a monster too.
static func _keeps_things(spec: Dictionary) -> bool:
	var script := str(spec.get("script", ""))
	if script in [CHEST, CARGO, MONSTER]:
		return true
	var kind := str(spec.get("kind", ""))
	return not kind.is_empty() and script == str(Monster.kinds().get(kind, {}).get("script", ""))


## The make of what a chest, a crate or a cart keeps or a monster carries
## and drops (decision 474): its entry's props "style" if it is one of Items.STYLES, else the
## level's "item_style" (dungeon sets it per source: below the castle
## dwarven, the tower dark elven), else none. An unknown one is warned
## about and the next tried. Animals and the rest have none.
static func _style(props: Dictionary, spec: Dictionary, config: Dictionary, warnings: Array[String], at: Vector2i) -> void:
	var own: Variant = props.get("style")
	props.erase("style")
	if not _keeps_things(spec):
		if own != null:
			warnings.append("style at %s: only a chest, a crate, a cart or a monster has a make" % at)
		return
	for given: Variant in [own, config.get("item_style")]:
		if given == null:
			continue
		if str(given) in Items.STYLES:
			props["style"] = str(given)
			return
		warnings.append("style at %s: no make %s (Items.STYLES has %s)" % [at, given, ", ".join(Items.STYLES)])


## Whether what a chest keeps or a monster carries and drops is grave goods
## (decision 555): its entry's props "grave" (true or false) if given, else
## the level's "grave_goods" (dungeon's barrow), else not. Kept as props
## "grave": true for World.grave_from.
static func _grave(props: Dictionary, spec: Dictionary, config: Dictionary, warnings: Array[String], at: Vector2i) -> void:
	var own: Variant = props.get("grave")
	props.erase("grave")
	if not _keeps_things(spec):
		if own != null:
			warnings.append("grave at %s: only a chest, a crate, a cart or a monster holds grave goods" % at)
		return
	var grave: Variant = own if own is bool else config.get("grave_goods", false)
	if own != null and own is not bool:
		warnings.append("grave at %s: %s is not true or false" % [at, own])
	if grave == true:
		props["grave"] = true


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
