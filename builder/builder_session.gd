class_name BuilderSession
extends RefCounted
## One builder-mode request and its follow-ups: a player picked an area of
## a level and asked for something there ("a pond here", "a goblin camp
## guarding a chest"). The session asks Claude, through [member client],
## with the area, what is in it, the legend and the prefabs, and tools that
## change a working copy of the level: paint cells, set edges, lay a path,
## the area tools (pond, grove, scatter, fence), place things, stamp a
## prefab, and look at the area again. What the tools change is the
## proposal: [method proposal] gives it as one change set (MapDoc), shown
## as a ghost until the player accepts it ([method accept], one undo step
## on the MapDoc) or discards it. A follow-up ("bigger", "move it north")
## goes on in the same conversation, from the level as it was before the
## proposal: Claude remakes the whole proposal, seeing what it did.
##
## Every edit is kept inside the area. The conversation is only ever added
## to (Claude's turns are sent back as they came), so the long system
## prompt and the earlier turns are read from the cache.

const MAX_TURNS := 16
## A grid line per row of the area, a character per cell: CHARS.
const CHARS := {
	"void": "#", "stone": "_", "grass": ".", "dirt": ",", "water": "~", "fire": "*", "stair": "^",
	"start": "S", "monster_imp": "i", "monster_brute": "b", "monster_sneak": "s", "crate": "k",
	"boulder": "o", "cart": "a", "chest": "h", "torch": "t", "lantern": "l", "link": ">",
}
## What place() can put down, by the names Claude uses.
const THINGS := {
	"imp": "monster_imp", "brute": "monster_brute", "sneak": "monster_sneak", "crate": "crate",
	"boulder": "boulder", "cart": "cart", "chest": "chest", "torch": "torch", "lantern": "lantern",
}
const GROUNDS: Array[String] = ["stone", "grass", "dirt", "water", "fire", "void", "stair"]
const SIDES := {"north": Vector2i(0, -1), "east": Vector2i(1, 0), "south": Vector2i(0, 1), "west": Vector2i(-1, 0)}
## Context shown round the area, in cells.
const MARGIN := 3
## level.json keys a proposal may change as a whole (beyond entries and links).
const CONFIG_KEYS: Array[String] = ["neighbours", "places", "buildings", "town_walls"]

## Asks Claude: send(body: Dictionary) -> Dictionary (a Messages API
## response, or {"error": "..."}), awaited (ClaudeClient, StubClaude).
var client: Object
var doc: MapDoc
var area: Rect2i
var map_name := ""
var prefab_dir := Prefab.DIR
var model := ClaudeClient.DEFAULT_MODEL
var effort := "medium"
## The most one request (with its tool turns) may cost, in dollars.
var max_cost := 1.0

var messages: Array = []
## The level as the proposal is being made: a copy of the doc's.
var working: MapDoc
## What this session has cost: tokens and dollars, all requests.
var usage := {"input": 0, "output": 0, "cache_read": 0, "cache_write": 0, "cost": 0.0, "requests": 0}
## Claude's last words to the player.
var summary := ""
var busy := false
## A new level beyond the map's edge, proposed by new_area ({} for none):
## {name, side (of this level), size, seed, description, gate, footprint}.
var new_area := {}
## Accepted: the new level made (its MapDoc, saved by the caller), and its name.
var created_doc: MapDoc
var created := ""


func _init(level_doc: MapDoc, selected: Rect2i, level_name: String, claude: Object) -> void:
	doc = level_doc
	area = selected.intersection(Rect2i(Vector2i.ZERO, level_doc.map.size))
	map_name = level_name
	client = claude
	_fresh_working()


func _fresh_working() -> void:
	new_area = {}
	working = MapDoc.new()
	working.folder = doc.folder
	working.map = doc.map.copy()
	working.config = doc.config.duplicate(true)
	working.had_heights = doc.had_heights


## Asks for [param text] (the first request, or a follow-up), running
## Claude's tool calls until it is done. Returns {ok, summary, cost (this
## request's), error}; the proposal is then [method proposal].
func ask(text: String) -> Dictionary:
	if busy:
		return {"ok": false, "error": "still working on the last request"}
	busy = true
	_fresh_working()
	var first := messages.is_empty()
	var prompt := (_situation() + "\n\nThe request: " + text) if first \
			else "A follow-up to the same area: %s\nRemake the whole proposal (the area is back as it was before it): call the tools again, then say what you did." % text
	messages.append({"role": "user", "content": prompt})
	var spent := 0.0
	var result := {"ok": false, "summary": "", "cost": 0.0, "error": ""}
	for turn in MAX_TURNS:
		var response: Dictionary = await client.send(_body())
		if response.has("error"):
			result["error"] = str(response["error"])
			break
		spent += _count(response)
		var content: Array = response.get("content", [])
		messages.append({"role": "assistant", "content": content})
		var stop := str(response.get("stop_reason", ""))
		if stop == "tool_use":
			var results: Array = []
			for block: Dictionary in content:
				if block.get("type") == "tool_use":
					var outcome := run_tool(str(block.get("name")), block.get("input", {}))
					results.append({"type": "tool_result", "tool_use_id": block.get("id"),
						"content": outcome["text"], "is_error": not outcome["ok"]})
			messages.append({"role": "user", "content": results})
			if spent > max_cost:
				result["error"] = "stopped: this request reached its spending limit ($%.2f)" % max_cost
				break
			continue
		if stop == "pause_turn":
			continue
		summary = _text_of(content)
		if stop == "refusal":
			result["error"] = "Claude declined this request"
		elif stop == "max_tokens":
			result["error"] = "Claude's answer was cut off (max_tokens)"
		else:
			result["ok"] = true
		break
	if not result["ok"] and result["error"].is_empty():
		result["error"] = "Claude did not finish in %d turns" % MAX_TURNS
	result["summary"] = summary
	result["cost"] = spent
	busy = false
	return result


## The request body: the stable system prompt and tools first (cached), the conversation after.
func _body() -> Dictionary:
	return {
		"model": model,
		"max_tokens": 16000,
		"output_config": {"effort": effort},
		"system": [{"type": "text", "text": system_prompt(prefab_dir), "cache_control": {"type": "ephemeral"}}],
		"tools": TOOLS,
		"messages": messages,
		"cache_control": {"type": "ephemeral"},
	}


## Adds [param response]'s usage to [member usage]; returns its cost in dollars.
func _count(response: Dictionary) -> float:
	var used: Dictionary = response.get("usage", {})
	var input := int(used.get("input_tokens", 0))
	var output := int(used.get("output_tokens", 0))
	var read := int(used.get("cache_read_input_tokens", 0))
	var write := int(used.get("cache_creation_input_tokens", 0))
	var cost := ClaudeClient.cost(str(response.get("model", model)), input, output, read, write)
	usage["input"] += input
	usage["output"] += output
	usage["cache_read"] += read
	usage["cache_write"] += write
	usage["cost"] += cost
	usage["requests"] += 1
	return cost


static func _text_of(content: Array) -> String:
	var parts: PackedStringArray = []
	for block: Dictionary in content:
		if block.get("type") == "text":
			parts.append(str(block.get("text", "")).strip_edges())
	return "\n".join(parts).strip_edges()


# --- What Claude is told -----------------------------------------------------------------

## The system prompt: what the map is, how it is drawn, what the tools do,
## the prefabs; the same for every request (cached).
static func system_prompt(prefabs_from := Prefab.DIR) -> String:
	var legend := PackedStringArray()
	for meaning: String in CHARS:
		legend.append("%s %s" % [CHARS[meaning], meaning.trim_prefix("monster_")])
	var prefabs := PackedStringArray()
	for prefab_name in Prefab.names(prefabs_from):
		var prefab := Prefab.load_prefab(prefab_name, prefabs_from)
		if prefab.is_empty():
			continue
		var piece: LevelMap = prefab["map"]
		# The grid shows cells only: a building is said in words.
		var buildings: Array = prefab["config"].get("buildings", []) if prefab["config"].get("buildings") is Array else []
		var kinds := PackedStringArray(buildings.map(func(entry: Variant) -> String:
			return str(entry.get("slot", "")).trim_prefix("building.") if entry is Dictionary else ""))
		prefabs.append("%s (%d x %d)%s:\n%s" % [prefab_name, piece.size.x, piece.size.y,
			", a building: %s" % ", ".join(kinds) if not kinds.is_empty() else "",
			grid(piece, prefab["config"], Rect2i(Vector2i.ZERO, piece.size), Rect2i(Vector2i.ZERO, piece.size))])
	return """You build places in Psykinetic, a top-down co-op game on a grid of cells, where players fight goblins with physics (pushing, throwing, knocking down) and explore with talking companions. A player in builder mode has picked an area of a level and asked for something there. Change the area with the tools, then say in a sentence or two what you made; the player sees your changes as a ghost and accepts or discards them.

Make places with something to do, not only scenery: a chest worth opening (and something guarding it), a camp to clear, a captive to free, a larder, a puzzle of crates and boulders. Monsters are few and matter: a camp is two to five, gathered round its fire. Leave ways in: what you make must be reachable on foot from the rest of the area.

The map. Cells are x to the east, y to the south, (0, 0) the top-left of the level. A cell is ground (stone, grass, dirt), water (not walkable; nothing is built along it), fire (walkable, burns), a stair, void, or a thing standing on ground. Outdoors, void is forest: a void cell next to land is drawn as a tree, so scattered void cells are scattered trees and a block of void is a wood. Walls and doors stand on the edges between two cells; an edge between land and void is a wall of its own (outdoors, the forest's edge). Things: start (where players join), imp (small goblin), brute (big goblin), sneak (quick goblin), crate (pushable), boulder (heavy, pushable), cart, chest (4 slots of items), torch (light and a little heat), lantern (light), link (to another level; not yours to place).

The grid shows the area and a margin round it, one character a cell (the margin is shown for context; only the area may change):
%s
Each row starts with its y; the first line says the x of the first column. Walls and doors are listed after the grid by the cell and its side.

Monsters idle until someone comes: guard (stands, glances about), wander (strolls near its cell, a radius), patrol (walks a route of cells, round or back and forth), gather (stands or sits round a point, such as a fire: every monster gathering at one cell is one group), none. Without one, imps wander, brutes guard and sneaks patrol. Chests hold item ids; the items there are: %s.

Levels join at their edges: walking off one edge arrives on the neighbour's opposite edge, at the same row (east, west) or column (north, south). When the area touches the map's edge with nothing beyond it, new_area makes a new level there (its own map; a first draft of grass, groves and forest round it, open where the way arrives) and carves a way out to the edge through the area. Use it when asked for somewhere new beyond the edge ("a new area east", "the woods past here"), not for changes inside the area.

Places are what factions hold (the goblins, the town, or nobody): a camp, a keep, a farm, a gate, a mine. Each is a cell and a radius; the ground within the radius is its holder's, and no one else's group may walk through it. mark_place names one (its key, kind, cell, radius, who holds it at the start). Mark a place when you build one: a camp's place on its gather point (where its monsters gather), a farmstead's in its yard. Some prefabs bring their place with them. A building prefab is a roofed building players walk into: stamp it whole, door and all, rather than drawing its walls yourself. A building can serve a town: set_building gives one in the area a use (%s) and its town, the key of a stockpile place in this level (a place of kind stockpile, held by the town). A town has one building of each use. Stamping over a building drops its use: set it again. town_wall walls a town in: give the rectangle of cells it encloses (its buildings, its store, room to walk) and the wall stands on the edges just outside it, with gates (doors) where roads come in, one in the middle of each side if you name none. One wall per town; it looks as strong as the town has built it (a bank of rubble at first).

Prefabs to stamp (their top-left at a cell, turned 0-3 quarter turns clockwise; their # is void and leaves the map as it was):
%s""" % [", ".join(legend), ", ".join(Items.ids()), ", ".join(building_uses()), "\n\n".join(prefabs) if not prefabs.is_empty() else "(none)"]


## What the first request starts with: the level, the area, what is in it.
func _situation() -> String:
	var zone := Level.zone_of(doc.config)
	var shown := area.grow(MARGIN).intersection(Rect2i(Vector2i.ZERO, doc.map.size))
	var text := "The level: %s (\"%s\"), %d x %d cells, %s. The area: x %d to %d, y %d to %d (%d x %d cells).\n\n%s" % [
		map_name, str(doc.config.get("name", map_name)), doc.map.size.x, doc.map.size.y,
		"outdoors (void is forest)" if zone == "outdoors" else "%s (void is nothing, walled off)" % {"indoors": "indoors", "cave": "a cave", "dungeon": "a dungeon"}.get(zone, zone),
		area.position.x, area.end.x - 1, area.position.y, area.end.y - 1, area.size.x, area.size.y,
		grid(doc.map, doc.config, shown, area)]
	var edges := edges_touched()
	if not edges.is_empty():
		var beyond := PackedStringArray()
		for side in edges:
			var neighbour := str(doc.config.get("neighbours", {}).get(side, ""))
			beyond.append("%s (%s)" % [side, "beyond it: %s" % neighbour if not neighbour.is_empty() else "nothing beyond it yet: new_area can make a level there"])
		text += "\n\nThe area touches the map's edge on the " + ", ".join(beyond) + "."
	var places := PackedStringArray()
	var listed: Dictionary = Level.places_from(doc.config, [] as Array[String])
	for key: String in listed:
		var place: Dictionary = listed[key]
		if area.grow(MARGIN).has_point(place["cell"]):
			places.append("%s (%s at %s, radius %d, held by %s)" % [key, place["kind"], place["cell"], place["radius"], place["holder"]])
	if not places.is_empty():
		text += "\n\nPlaces here: " + ", ".join(places) + "."
	return text


## The map edges [param area] touches: "north", "east", "south", "west".
func edges_touched() -> Array[String]:
	var out: Array[String] = []
	if area.position.y == 0:
		out.append("north")
	if area.end.x == doc.map.size.x:
		out.append("east")
	if area.end.y == doc.map.size.y:
		out.append("south")
	if area.position.x == 0:
		out.append("west")
	return out


## [param shown] of [param map] as a grid of CHARS, a row a line labelled
## by its y, after a line saying the x of the first column and where
## [param inside] (the area) is; then the walls and doors and the settings
## (level.json's entries and links) of the things in it.
static func grid(map: LevelMap, config: Dictionary, shown: Rect2i, inside: Rect2i) -> String:
	var lines := PackedStringArray()
	lines.append("x from %d%s" % [shown.position.x, "" if shown == inside else " (area: x %d-%d, y %d-%d)" % [
		inside.position.x, inside.end.x - 1, inside.position.y, inside.end.y - 1]])
	for y in range(shown.position.y, shown.end.y):
		var row := ""
		for x in range(shown.position.x, shown.end.x):
			row += str(CHARS.get(map.cell(Vector2i(x, y)), "?"))
		lines.append("%4d %s" % [y, row])
	var walls := PackedStringArray()
	for key: Vector3i in map.edges:
		var ends := Terrain.edge_cells(key)
		if shown.has_point(ends[0]) or shown.has_point(ends[1]):
			walls.append("%s %s of (%d, %d)" % [map.edges[key], "east" if key.z == Terrain.EAST else "south", key.x, key.y])
	walls.sort()
	if not walls.is_empty():
		lines.append("Walls and doors: " + "; ".join(walls))
	var notes := PackedStringArray()
	for entry: Variant in config.get("entities", []):
		if entry is Dictionary:
			var at: Variant = Level._tile(entry.get("at"))
			if at != null and shown.has_point(at):
				notes.append(JSON.stringify(entry))
	for link: Variant in config.get("links", []):
		if link is Dictionary:
			var at: Variant = Level._tile(link.get("at"))
			if at != null and shown.has_point(at):
				notes.append("link " + JSON.stringify(link))
	for building: Variant in config.get("buildings", []):
		var rect: Variant = Level.building_rect(building)
		if rect != null and shown.intersects(rect):
			notes.append("building " + JSON.stringify(building))
	if not notes.is_empty():
		lines.append("Settings of things here: " + "; ".join(notes))
	return "\n".join(lines)


# --- The tools ---------------------------------------------------------------------------

const _CELL := {"type": "array", "items": {"type": "integer"}, "minItems": 2, "maxItems": 2, "description": "[x, y]"}
const _RECT := {"type": "object", "description": "a rectangle of cells: its top-left x, y and its width and height",
	"properties": {"x": {"type": "integer"}, "y": {"type": "integer"}, "w": {"type": "integer"}, "h": {"type": "integer"}},
	"required": ["x", "y", "w", "h"]}
const _SEED := {"type": "integer", "description": "any number; another gives another shape"}

const TOOLS := [
	{"name": "paint", "description": "Sets cells to a ground (stone, grass, dirt), water, fire, a stair or void (forest outdoors). Give rectangles, single cells, or both. A thing on a painted cell is gone.",
		"input_schema": {"type": "object", "properties": {
			"ground": {"type": "string", "enum": ["stone", "grass", "dirt", "water", "fire", "void", "stair"]},
			"rects": {"type": "array", "items": _RECT},
			"cells": {"type": "array", "items": _CELL}},
			"required": ["ground"]}},
	{"name": "edges", "description": "Sets walls, doors or clear (no wall) on the sides of cells: each item is a cell, a side and what goes there. For a wall round a rectangle use fence.",
		"input_schema": {"type": "object", "properties": {
			"set": {"type": "array", "items": {"type": "object", "properties": {
				"at": _CELL, "side": {"type": "string", "enum": ["north", "east", "south", "west"]},
				"kind": {"type": "string", "enum": ["wall", "door", "clear"]}}, "required": ["at", "side", "kind"]}}},
			"required": ["set"]}},
	{"name": "path", "description": "A winding path through the points in order, crossing anything (water and void too) and opening the walls it runs through.",
		"input_schema": {"type": "object", "properties": {
			"points": {"type": "array", "items": _CELL, "minItems": 2},
			"width": {"type": "integer", "minimum": 1, "maximum": 6},
			"ground": {"type": "string", "enum": ["dirt", "stone", "grass"]},
			"seed": _SEED},
			"required": ["points"]}},
	{"name": "pond", "description": "An uneven pond of water in one piece filling the rectangle, with a shore of dirt round it.",
		"input_schema": {"type": "object", "properties": {"rect": _RECT, "shore": {"type": "integer", "minimum": 0, "maximum": 4}, "seed": _SEED},
			"required": ["rect"]}},
	{"name": "grove", "description": "Trees (void cells) scattered over the ellipse in the rectangle, thickest in its middle; density 0.1 to 1; a clearing of grass in its middle if asked. Only on ground; things and water are left.",
		"input_schema": {"type": "object", "properties": {"rect": _RECT, "density": {"type": "number"}, "clearing": {"type": "boolean"}, "seed": _SEED},
			"required": ["rect"]}},
	{"name": "scatter", "description": "Boulders, crates and/or trees scattered over the ground of the rectangle, a share of its cells (0.01 to 0.3), never two side by side.",
		"input_schema": {"type": "object", "properties": {"rect": _RECT,
			"things": {"type": "array", "items": {"type": "string", "enum": ["boulder", "crate", "tree"]}},
			"density": {"type": "number"}, "seed": _SEED},
			"required": ["rect", "things"]}},
	{"name": "fence", "description": "A wall round the rectangle (on the edges between it and outside it) with a gate (a door) in the middle of one side, or none.",
		"input_schema": {"type": "object", "properties": {"rect": _RECT,
			"gate": {"type": "string", "enum": ["north", "east", "south", "west", "none"]}},
			"required": ["rect"]}},
	{"name": "place", "description": "Puts a thing on a cell (its ground stays), with its settings: a monster's facing and idling, a chest's items, a name.",
		"input_schema": {"type": "object", "properties": {
			"at": _CELL,
			"thing": {"type": "string", "enum": ["imp", "brute", "sneak", "crate", "boulder", "cart", "chest", "torch", "lantern"]},
			"name": {"type": "string", "description": "optional, e.g. \"Gutrot\""},
			"facing": {"type": "string", "enum": ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]},
			"idle": {"type": "object", "properties": {
				"mode": {"type": "string", "enum": ["guard", "wander", "patrol", "gather", "none"]},
				"radius": {"type": "integer", "minimum": 1, "maximum": 8},
				"route": {"type": "array", "items": _CELL},
				"loop": {"type": "boolean"},
				"point": _CELL}, "required": ["mode"]},
			"items": {"type": "array", "items": {"type": "string"}, "maxItems": 4, "description": "a chest's items, by id"}},
			"required": ["at", "thing"]}},
	{"name": "stamp", "description": "Stamps a prefab with its top-left at a cell, turned 0-3 quarter turns clockwise. Its void cells leave the map as it was.",
		"input_schema": {"type": "object", "properties": {"prefab": {"type": "string"}, "at": _CELL,
			"turns": {"type": "integer", "minimum": 0, "maximum": 3}},
			"required": ["prefab", "at"]}},
	{"name": "mark_place", "description": "Marks a place factions hold: a cell in the area and a radius of ground round it, held at the start by the goblins, the town or nobody. A key already used is moved or changed.",
		"input_schema": {"type": "object", "properties": {
			"key": {"type": "string", "description": "lower case letters, digits and _, e.g. \"goblin_camp\""},
			"kind": {"type": "string", "enum": ["camp", "keep", "farm", "gate", "mine", "stockpile", "other"]},
			"at": _CELL,
			"radius": {"type": "integer", "minimum": 1, "maximum": 32},
			"holder": {"type": "string", "enum": ["goblins", "town", "nobody"]},
			"name": {"type": "string", "description": "optional, how it is called, e.g. \"the old farmstead\""}},
			"required": ["key", "kind", "at", "holder"]}},
	{"name": "set_building", "description": "Gives a building in the area its use and the town it serves, or makes it scenery again (no use, no town).",
		"input_schema": {"type": "object", "properties": {
			"at": _CELL,
			"use": {"type": "string", "description": "what the town does there (the uses are in the system prompt); empty for none"},
			"town": {"type": "string", "description": "the key of a stockpile place in this level; empty for none"}},
			"required": ["at"]}},
	{"name": "town_wall", "description": "Walls a town in: a wall on the edges just outside a rectangle of cells, gates (doors) in it, recorded as that town's wall (a town walled again gets the new one). Leaves the cells as they are.",
		"input_schema": {"type": "object", "properties": {
			"town": {"type": "string", "description": "the key of the town's stockpile place in this level"},
			"rect": _RECT,
			"gates": {"type": "array", "items": _CELL, "description": "cells just inside the wall where a gate goes (on the rectangle's border); none given: one in the middle of each side"}},
			"required": ["town", "rect"]}},
	{"name": "look", "description": "The area as it is now, with your changes so far, as a grid.",
		"input_schema": {"type": "object", "properties": {}}},
	{"name": "new_area", "description": "Makes a new level beyond the map's edge on a side the area touches (one with nothing beyond it yet), joined both ways, and carves a way from the middle of the area out to that edge. The new level is a first draft, its size given in cells (16 to 256).",
		"input_schema": {"type": "object", "properties": {
			"side": {"type": "string", "enum": ["north", "east", "south", "west"]},
			"width": {"type": "integer", "minimum": 16, "maximum": 256},
			"height": {"type": "integer", "minimum": 16, "maximum": 256},
			"name": {"type": "string", "description": "a short name for it, e.g. \"Ashen Wood\""},
			"description": {"type": "string", "description": "what it is, a sentence"},
			"seed": _SEED},
			"required": ["side", "width", "height", "name"]}},
]

const FACINGS := {"north": Vector2i(0, -1), "north-east": Vector2i(1, -1), "east": Vector2i(1, 0), "south-east": Vector2i(1, 1),
	"south": Vector2i(0, 1), "south-west": Vector2i(-1, 1), "west": Vector2i(-1, 0), "north-west": Vector2i(-1, -1)}


## Runs tool [param tool] with [param input] on the working copy: {ok, text}.
func run_tool(tool: String, input: Variant) -> Dictionary:
	if not input is Dictionary:
		return _no("the input is not an object")
	var given: Dictionary = input
	match tool:
		"paint":
			var ground := str(given.get("ground", ""))
			if ground not in GROUNDS:
				return _no("no ground \"%s\"" % ground)
			var cells: Dictionary[Vector2i, String] = {}
			for rect_value: Variant in given.get("rects", []):
				var rect: Variant = _rect(rect_value)
				if rect == null:
					return _no("a rectangle needs x, y, w and h")
				for y in range(rect.position.y, rect.end.y):
					for x in range(rect.position.x, rect.end.x):
						cells[Vector2i(x, y)] = ground
			for cell_value: Variant in given.get("cells", []):
				var at: Variant = Level._tile(cell_value)
				if at == null:
					return _no("a cell is [x, y]")
				cells[at] = ground
			return _lay({"cells": cells}, "painted %d cells %s" % [cells.size(), ground])
		"edges":
			var edges: Dictionary[Vector3i, String] = {}
			for item: Variant in given.get("set", []):
				if not item is Dictionary:
					return _no("each item is {at, side, kind}")
				var at: Variant = Level._tile(item.get("at"))
				var side := str(item.get("side", ""))
				var kind := str(item.get("kind", ""))
				if at == null or not SIDES.has(side) or kind not in ["wall", "door", "clear"]:
					return _no("each item is {at: [x, y], side: north|east|south|west, kind: wall|door|clear}")
				edges[Terrain.edge_key(at, SIDES[side])] = kind
			return _lay({"edges": edges}, "set %d edges" % edges.size())
		"path":
			var points: Array[Vector2i] = []
			for point: Variant in given.get("points", []):
				var at: Variant = Level._tile(point)
				if at == null:
					return _no("a point is [x, y]")
				points.append(at)
			if points.size() < 2:
				return _no("a path needs two points or more")
			return _lay(AreaTools.path(working.map, points, int(given.get("seed", 1)), clampi(int(given.get("width", 2)), 1, 6),
				str(given.get("ground", "dirt"))), "a path through %d points" % points.size())
		"pond", "grove", "scatter", "fence":
			var rect: Variant = _rect(given.get("rect"))
			if rect == null:
				return _no("rect needs x, y, w and h")
			var changes := {}
			match tool:
				"pond":
					changes = AreaTools.pond(working.map, rect, int(given.get("seed", 1)), clampi(int(given.get("shore", 1)), 0, 4))
				"grove":
					changes = AreaTools.grove(working.map, rect, int(given.get("seed", 1)),
						clampf(float(given.get("density", 0.5)), 0.1, 1.0), bool(given.get("clearing", false)))
				"scatter":
					var things: Array[String] = []
					for thing: Variant in given.get("things", []):
						things.append(str(thing))
					changes = AreaTools.scatter(working.map, rect, int(given.get("seed", 1)), things,
						clampf(float(given.get("density", 0.05)), 0.01, 0.3))
				"fence":
					var gate := str(given.get("gate", "south"))
					changes = AreaTools.fence(working.map, rect, "" if gate == "none" else gate)
			return _lay(changes, tool)
		"place":
			return _place(given)
		"stamp":
			var prefab_name := str(given.get("prefab", ""))
			var at: Variant = Level._tile(given.get("at"))
			if at == null:
				return _no("at is [x, y]")
			var prefab := Prefab.load_prefab(prefab_name, prefab_dir)
			if prefab.is_empty():
				return _no("no prefab \"%s\" (there are: %s)" % [prefab_name, ", ".join(Prefab.names(prefab_dir))])
			prefab = Prefab.rotated(prefab, int(given.get("turns", 0)))
			var size: Vector2i = (prefab["map"] as LevelMap).size
			if not area.encloses(Rect2i(at, size)):
				return _no("%s turned so is %d x %d: at %s it does not fit in the area" % [prefab_name, size.x, size.y, at])
			return _lay(Prefab.stamp_changes(prefab, working.map, at, working.config), "stamped %s" % prefab_name)
		"mark_place":
			return _mark_place(given)
		"set_building":
			return _set_building(given)
		"town_wall":
			return _town_wall(given)
		"look":
			return {"ok": true, "text": grid(working.map, working.config, area, area)}
		"new_area":
			return _new_area(given)
	return _no("no tool \"%s\"" % tool)


## A level by that name, or a folder under levels/ that is not one
## (levels/lore, levels/prefabs: data), whose files an export would mix with.
static func _name_taken(level_name: String) -> bool:
	return Level.exists(level_name) or DirAccess.dir_exists_absolute(Level.DIR + level_name)


func _new_area(given: Dictionary) -> Dictionary:
	var side := str(given.get("side", ""))
	if side not in edges_touched():
		return _no("the area does not touch the %s edge (it touches: %s)" % [side, ", ".join(edges_touched()) if not edges_touched().is_empty() else "none"])
	var neighbour := str(doc.config.get("neighbours", {}).get(side, ""))
	if not neighbour.is_empty():
		return _no("beyond the %s edge is %s already" % [side, neighbour])
	var title := str(given.get("name", "")).strip_edges()
	var level_name := Prefab.tidy_name(title)
	if level_name.is_empty():
		level_name = "%s_%s" % [map_name, side]
	if _name_taken(level_name):
		level_name = "%s_%s" % [map_name, level_name]
	if _name_taken(level_name):
		return _no("there is a level %s already: another name" % level_name)
	var size := Vector2i(clampi(int(given.get("width", 64)), 16, 256), clampi(int(given.get("height", 64)), 16, 256))
	# The way out: from the middle of the area to the middle of its edge.
	var middle := area.position + area.size / 2
	var exit := middle
	match side:
		"east":
			exit.x = doc.map.size.x - 1
		"west":
			exit.x = 0
		"north":
			exit.y = 0
		"south":
			exit.y = doc.map.size.y - 1
	var points: Array[Vector2i] = [middle, exit]
	var draft_seed := int(given.get("seed", 1))
	_lay(AreaTools.path(working.map, points, draft_seed, 3, "dirt"), "")
	var neighbours: Dictionary = (working.config.get("neighbours", {}) as Dictionary).duplicate()
	neighbours[side] = level_name
	working.apply_changes({"config": {"neighbours": neighbours}})
	var along := exit.y if side in ["east", "west"] else exit.x
	var gate := clampi(along, 0, (size.y if side in ["east", "west"] else size.x) - 1)
	var footprint := {"east": Rect2i(doc.map.size.x, 0, size.x, size.y), "west": Rect2i(-size.x, 0, size.x, size.y),
		"south": Rect2i(0, doc.map.size.y, size.x, size.y), "north": Rect2i(0, -size.y, size.x, size.y)}[side] as Rect2i
	new_area = {"name": level_name, "title": title if not title.is_empty() else level_name.capitalize(), "side": side,
		"size": size, "seed": draft_seed, "description": str(given.get("description", "")).strip_edges(),
		"gate": gate, "footprint": footprint}
	return {"ok": true, "text": "a new level %s (%d x %d) beyond the %s edge, a way out to it from the middle of the area" % [
		level_name, size.x, size.y, side]}


func _mark_place(given: Dictionary) -> Dictionary:
	var key := str(given.get("key", ""))
	var at: Variant = Level._tile(given.get("at"))
	var kind := str(given.get("kind", "other"))
	var holder := str(given.get("holder", Factions.NOBODY))
	if RegEx.create_from_string("^[a-z0-9_]{1,32}$").search(key) == null or at == null:
		return _no("mark_place needs a key (lower case letters, digits, _) and at: [x, y]")
	if not area.has_point(at):
		return _no("%s is outside the area" % [at])
	if working.map.cell(at) in ["void", "water"]:
		return _no("%s is %s: a place stands on ground" % [at, working.map.cell(at)])
	if kind not in Level.PLACE_KINDS:
		return _no("kind is one of %s" % ", ".join(Level.PLACE_KINDS))
	if not Factions.read().has(holder):
		return _no("holder is goblins, town or nobody")
	var places: Dictionary = (working.config["places"] as Dictionary).duplicate(true) if working.config.get("places") is Dictionary else {}
	var place := {"at": [at.x, at.y], "kind": kind, "radius": clampi(int(given.get("radius", Level.PLACE_RADIUS)), 1, 32), "holder": holder}
	if given.has("name"):
		place["name"] = str(given["name"])
	var again := places.has(key)
	places[key] = place
	working.apply_changes({"config": {"places": places}})
	return {"ok": true, "text": "%s the place %s: a %s at %s, radius %d, held by %s" % ["changed" if again else "marked", key, kind, at, place["radius"], holder]}


## The uses a map building may have: the economy rules' buildings (the
## town wall is a record of its own, not a building's use).
static func building_uses() -> Array[String]:
	var out: Array[String] = []
	for use: Variant in Production.read_rules().get("buildings", {}):
		if str(use) != "walls":
			out.append(str(use))
	out.sort()
	return out


func _set_building(given: Dictionary) -> Dictionary:
	var at: Variant = Level._tile(given.get("at"))
	if at == null:
		return _no("set_building needs at: [x, y], a cell of the building")
	if not area.has_point(at):
		return _no("%s is outside the area" % [at])
	var buildings: Array = (working.config["buildings"] as Array).duplicate(true) if working.config.get("buildings") is Array else []
	var index := buildings.find_custom(func(entry: Variant) -> bool:
		var rect: Variant = Level.building_rect(entry)
		return rect != null and rect.has_point(at))
	if index < 0:
		return _no("no building stands on %s: stamp a building prefab first" % [at])
	var use := str(given.get("use", "")).strip_edges()
	var town := str(given.get("town", "")).strip_edges()
	if not use.is_empty() and use not in building_uses():
		return _no("use is one of %s, or empty" % ", ".join(building_uses()))
	if not town.is_empty():
		var places: Dictionary = Level.places_from(working.config, [] as Array[String])
		if not places.has(town) or places[town]["kind"] != "stockpile":
			var stockpiles := places.keys().filter(func(key: String) -> bool: return places[key]["kind"] == "stockpile")
			return _no("town is the key of a stockpile place here (%s)" % (", ".join(stockpiles) if not stockpiles.is_empty() else "there is none: mark_place one, kind stockpile"))
	if not use.is_empty() and not town.is_empty():
		for other: Variant in buildings:
			if other != buildings[index] and other is Dictionary and str(other.get("use", "")) == use and str(other.get("town", "")) == town:
				return _no("%s has its %s already, at %s" % [town, use, other.get("at")])
	var entry: Dictionary = buildings[index]
	for key: String in {"use": use, "town": town}:
		var value := use if key == "use" else town
		if value.is_empty():
			entry.erase(key)
		else:
			entry[key] = value
	working.apply_changes({"config": {"buildings": buildings}})
	var what := "%s at %s" % [entry["slot"], entry.get("at")]
	if use.is_empty() and town.is_empty():
		return {"ok": true, "text": "the %s is scenery now" % what}
	if town.is_empty():
		return {"ok": true, "text": "the %s is a %s, but in no town: it does nothing until it has one" % [what, use]}
	return {"ok": true, "text": "the %s %s, in %s" % [what, "is a %s" % use if not use.is_empty() else "has no use", town]}


func _town_wall(given: Dictionary) -> Dictionary:
	var town := str(given.get("town", ""))
	var rect: Variant = _rect(given.get("rect"))
	if rect == null or rect.size.x < 2 or rect.size.y < 2:
		return _no("town_wall needs a town and a rect (x, y, w, h), 2 x 2 or more")
	var places: Dictionary = Level.places_from(working.config, [] as Array[String])
	if not places.has(town) or places[town]["kind"] != "stockpile":
		var stockpiles := places.keys().filter(func(key: String) -> bool: return places[key]["kind"] == "stockpile")
		return _no("town is the key of a stockpile place here (%s)" % (", ".join(stockpiles) if not stockpiles.is_empty() else "there is none: mark_place one, kind stockpile"))
	var ring := Level.outline(rect).filter(func(key: Vector3i) -> bool: return working.map.edge_in_bounds(key))
	for key: Vector3i in ring:
		var ends := Terrain.edge_cells(key)
		if not area.has_point(ends[0]) or not area.has_point(ends[1]):
			return _no("the wall stands just outside the rect, so the rect must be a cell in from the area's sides (the area: x %d-%d, y %d-%d)" % [
				area.position.x, area.end.x - 1, area.position.y, area.end.y - 1])
	# A gate: a border cell, through the side it is on (a corner's: north or south first).
	var sides := {"north": Vector2i(0, -1), "south": Vector2i(0, 1), "west": Vector2i(-1, 0), "east": Vector2i(1, 0)}
	var gates: Array[Vector3i] = []
	var asked: Array = given.get("gates", []) if given.get("gates") is Array else []
	if asked.is_empty():
		var middle: Vector2i = rect.position + rect.size / 2
		for at in [Vector2i(middle.x, rect.position.y), Vector2i(middle.x, rect.end.y - 1), Vector2i(rect.position.x, middle.y), Vector2i(rect.end.x - 1, middle.y)]:
			asked.append([at.x, at.y])
	for value: Variant in asked:
		var at: Variant = Level._tile(value)
		if at == null or not rect.has_point(at):
			return _no("a gate is a cell on the rect's border: %s is not" % [value])
		var on := ""
		for side: String in sides:
			var beyond: Vector2i = at + sides[side]
			if not rect.has_point(beyond):
				on = side
				break
		if on.is_empty():
			return _no("a gate is a cell on the rect's border: %s is inside it" % [value])
		var key := Terrain.edge_key(at, sides[on])
		if key in ring and key not in gates:
			gates.append(key)
	var changes := {"edges": {}}
	for key: Vector3i in ring:
		changes["edges"][key] = "door" if key in gates else "wall"
	var walls: Array = (working.config["town_walls"] as Array).duplicate(true) if working.config.get("town_walls") is Array else []
	var again := walls.any(func(entry: Variant) -> bool: return entry is Dictionary and str(entry.get("town", "")) == town)
	walls = walls.filter(func(entry: Variant) -> bool: return not (entry is Dictionary and str(entry.get("town", "")) == town))
	walls.append({"town": town, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]})
	changes["config"] = {"town_walls": walls}
	var laid := _lay(changes, "")
	if not laid["ok"]:
		return laid
	var text := "%s %s's wall round x %d-%d, y %d-%d: %d edges, %d of them gates" % ["moved" if again else "built", town,
		rect.position.x, rect.end.x - 1, rect.position.y, rect.end.y - 1, ring.size(), gates.size()]
	if not rect.has_point(places[town]["cell"]):
		text += "; the store's place %s is outside it" % [places[town]["cell"]]
	return {"ok": true, "text": text}


func _place(given: Dictionary) -> Dictionary:
	var at: Variant = Level._tile(given.get("at"))
	var thing := str(given.get("thing", ""))
	if at == null or not THINGS.has(thing):
		return _no("place needs at: [x, y] and a thing (%s)" % ", ".join(THINGS.keys()))
	if not area.has_point(at):
		return _no("%s is outside the area" % [at])
	if working.map.cell(at) in ["void", "water"]:
		return _no("%s is %s: paint ground there first" % [at, working.map.cell(at)])
	var meaning: String = THINGS[thing]
	var entry := {"at": [at.x, at.y]}
	if given.has("name"):
		entry["name"] = str(given["name"])
	if meaning.begins_with("monster_"):
		if FACINGS.has(str(given.get("facing", ""))):
			var facing: Vector2i = FACINGS[str(given["facing"])]
			entry["facing"] = [facing.x, facing.y]
		var idle: Variant = given.get("idle")
		if idle is Dictionary:
			var warnings: Array[String] = []
			var read := Level.idle_from(idle, warnings, at)
			if not warnings.is_empty():
				return _no(warnings[0])
			var out := {"mode": read["mode"]}
			for key in ["radius", "loop"]:
				if idle.has(key):
					out[key] = idle[key]
			for key in ["route", "point"]:
				if read.has(key):
					out[key] = [read[key].x, read[key].y] if key == "point" else read[key].map(func(cell: Vector2i) -> Array: return [cell.x, cell.y])
			entry["idle"] = out if out.size() > 1 else out["mode"]
	elif meaning == "chest" and given.has("items"):
		var slots := Items.tidy(given["items"], Chest.SLOTS)
		var unknown: Array = (given["items"] as Array).filter(func(id: Variant) -> bool: return not Items.exists(str(id)))
		if not unknown.is_empty():
			return _no("no items %s (there are: %s)" % [unknown, ", ".join(Items.ids())])
		entry["props"] = {"slots": Array(slots)}
	var changes := {"cells": {at: meaning}, "covers": [at]}
	if entry.size() > 1:
		changes["entries"] = [entry]
	return _lay(changes, "placed %s at %s" % [thing, at])


## Lays [param changes] on the working copy, kept to the area; {ok, text}.
func _lay(changes: Dictionary, done: String) -> Dictionary:
	var kept := {}
	var outside := 0
	var cells: Dictionary = {}
	for cell: Vector2i in changes.get("cells", {}):
		if area.has_point(cell):
			cells[cell] = changes["cells"][cell]
		else:
			outside += 1
	kept["cells"] = cells
	var edges: Dictionary = {}
	for key: Vector3i in changes.get("edges", {}):
		var ends := Terrain.edge_cells(key)
		if area.has_point(ends[0]) and area.has_point(ends[1]):
			edges[key] = changes["edges"][key]
		else:
			outside += 1
	kept["edges"] = edges
	var heights: Dictionary = {}
	for cell: Vector2i in changes.get("heights", {}):
		if area.has_point(cell):
			heights[cell] = changes["heights"][cell]
	kept["heights"] = heights
	for list in ["entries", "links"]:
		kept[list] = (changes.get(list, []) as Array).filter(func(entry: Dictionary) -> bool:
			return area.has_point(Level._tile(entry.get("at"))))
	kept["covers"] = (changes.get("covers", cells.keys()) as Array).filter(func(cell: Vector2i) -> bool: return area.has_point(cell))
	if changes.has("config"):
		# A stamped prefab's places and buildings (it fits in the area, so they do).
		kept["config"] = changes["config"]
	working.apply_changes(kept)
	return {"ok": true, "text": "%s%s" % [done, " (%d cells or edges outside the area left out)" % outside if outside > 0 else ""]}


static func _no(text: String) -> Dictionary:
	return {"ok": false, "text": text}


static func _rect(value: Variant) -> Variant:
	if not value is Dictionary:
		return null
	for key in ["x", "y", "w", "h"]:
		if not value.has(key):
			return null
	return Rect2i(int(value["x"]), int(value["y"]), maxi(1, int(value["w"])), maxi(1, int(value["h"])))


# --- The proposal ------------------------------------------------------------------------

## What the working copy changes from the doc, as one change set
## (MapDoc.apply_changes): every cell, edge and height that differs, and the
## entries and links of the cells where any differs.
func proposal() -> Dictionary:
	var cells: Dictionary[Vector2i, String] = {}
	var edges: Dictionary[Vector3i, String] = {}
	var heights: Dictionary[Vector2i, int] = {}
	var covers: Array[Vector2i] = []
	var entries: Array = []
	var links: Array = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var at := Vector2i(x, y)
			if working.map.cell(at) != doc.map.cell(at):
				cells[at] = working.map.cell(at)
			if int(working.map.heights.get(at, 0)) != int(doc.map.heights.get(at, 0)):
				heights[at] = int(working.map.heights.get(at, 0))
			var entry := working.entry_of(at)
			var link := working.link_of(at)
			if cells.has(at) or str(entry) != str(doc.entry_of(at)) or str(link) != str(doc.link_of(at)):
				covers.append(at)
				if not entry.is_empty():
					entries.append(entry.duplicate(true))
				if not link.is_empty():
					links.append(link.duplicate(true))
			for side in [Terrain.EAST, Terrain.SOUTH]:
				var key := Vector3i(x, y, side)
				if working.map.edge(key) != doc.map.edge(key):
					edges[key] = working.map.edge(key)
	var out := {"cells": cells, "edges": edges, "heights": heights, "covers": covers, "entries": entries, "links": links}
	var config := {}
	for key in CONFIG_KEYS:
		if str(working.config.get(key)) != str(doc.config.get(key)):
			config[key] = working.config.get(key)
	if not config.is_empty():
		out["config"] = config
	if not new_area.is_empty():
		out["new_area"] = new_area.duplicate()
	return out


## Lays the proposal on the doc as one undo step. Whether it changed
## anything. With a new area, [member created_doc] is the new level (not
## saved: the caller saves it, first) and [member created] its name.
func accept() -> bool:
	var changes := proposal()
	created_doc = null
	created = ""
	if not new_area.is_empty():
		# A level beyond an edge is out of doors unless the one it leads from says otherwise.
		var zone := Level.zone_of(doc.config) if doc.config.has("zone") or doc.config.has("outdoor") else "outdoors"
		created_doc = draft_level(new_area, map_name, zone)
		created = str(new_area["name"])
	var changed := doc.apply_changes(changes)
	_fresh_working()
	return changed


## The new level [param plan] (new_area's) as a MapDoc to save in the
## overlay, joined back to [param beside] on its opposite side, its
## [param zone] (DayNight.ZONES: how it is lit) that of the level it leads from.
static func draft_level(plan: Dictionary, beside: String, zone: String) -> MapDoc:
	var joined: String = Level.OPPOSITE[plan["side"]]
	var made := MapDoc.new()
	made.folder = Level.overlay_dir + str(plan["name"]) + "/"
	made.map = AreaDraft.draft(plan["size"], int(plan["seed"]), joined, int(plan["gate"]))
	made.config = {"name": plan["title"], "zone": zone}
	if not str(plan.get("description", "")).is_empty():
		made.config["about"] = plan["description"]
	WorldMap.put_neighbours(made, {joined: beside})
	made.dirty = true
	return made


## Forgets the proposal (the conversation stays, for a new follow-up).
func discard() -> void:
	_fresh_working()
