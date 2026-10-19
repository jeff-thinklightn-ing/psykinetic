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
## A grid line per row of the area, a character per cell: CHARS, and one
## for each other monster kind (chars, decision 507).
const CHARS := {
	"void": "#", "stone": "_", "grass": ".", "dirt": ",", "water": "~", "fire": "*", "stair": "^", "ford": "=", "tall_grass": "\"", "slope": "/", "rock": "R",
	"start": "S", "monster_imp": "i", "monster_brute": "b", "monster_sneak": "s", "crate": "k",
	"boulder": "o", "cart": "a", "chest": "h", "torch": "t", "lantern": "l", "link": ">",
}
## The characters a monster kind not in CHARS takes, its own initial first
## (lower case, then upper), else the first of these free.
const SPARE_CHARS := "rdwgfjmnpquvxyzcekRDWGFJMNPQUVXYZCEKABHILOT"
## What place() can put down besides monsters, by the names Claude uses
## (monsters by their kind: things).
const THINGS := {
	"crate": "crate", "boulder": "boulder", "cart": "cart", "chest": "chest", "torch": "torch", "lantern": "lantern",
}
## The goblins and their allies in lore's words (docs/lore/primer.md); any
## other kind is said by its row in levels/monsters.json (label, role).
const KIND_WORDS := {
	"imp": "a Blood Rot goblin, small, darts in and out",
	"brute": "an orc, ally of the Blood Rot, big and heavy",
	"sneak": "a kobold, ally of the Blood Rot, quick, comes at its prey from the side",
}
## What a wild animal's role (levels/monsters.json) does, said to Claude.
const ROLE_WORDS := {
	"prey": "bolts from anyone it notices, never fights",
	"game": "bolts, but charges when struck or cornered",
	"predator": "hunts %s; players only at night or with its pack about",
}
## The grid's Heights over relief (decision 527): a character per half
## metre, 0 for the lowest; past the last, the last.
const HALF_METRES := "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
const GROUNDS: Array[String] =["stone", "grass", "dirt", "tall_grass", "water", "ford", "fire", "void", "stair", "slope", "rock"]
const SIDES := {"north": Vector2i(0, -1), "east": Vector2i(1, 0), "south": Vector2i(0, 1), "west": Vector2i(-1, 0)}
## Context shown round the area, in cells.
const MARGIN := 3
## level.json keys a proposal may change as a whole (beyond entries and links).
const CONFIG_KEYS: Array[String] = ["neighbours", "places", "buildings", "town_walls", "roofs", "legend", "streams"]

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
## request's), error, warnings (Stockpile.check's on the proposal)}; the
## proposal is then [method proposal].
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
					var before := Stockpile.check(working.config)
					var ground_before := height_checks()
					var sites_before := site_checks()
					var outcome := run_tool(str(block.get("name")), block.get("input", {}))
					# What the change did to the town's store, said at once (decision 301).
					var new := Stockpile.check(working.config).filter(func(warning: String) -> bool: return warning not in before)
					if not new.is_empty():
						outcome["text"] += "
The town's store now: " + "; ".join(new)
					# And to the ways up and down (decision 356).
					var ground := height_checks().filter(func(warning: String) -> bool: return warning not in ground_before)
					if not ground.is_empty():
						outcome["text"] += "
Heights now: " + "; ".join(ground)
					# And to the work sites' ways to their towns (decision 520).
					var sites := site_checks().filter(func(warning: String) -> bool: return warning not in sites_before)
					if not sites.is_empty():
						outcome["text"] += "\nWork sites now: " + "; ".join(sites)
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
	result["warnings"] = Stockpile.check(working.config)
	result["height_warnings"] = height_checks()
	result["site_warnings"] = site_checks()
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
		"tools": tools(doc.config),
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

## The monster kinds place() offers (decision 507): levels/monsters.json's
## (Monster.kinds), then [param config]'s own ("monsters"), so a new kind
## needs nothing here.
static func monster_kinds(config := {}) -> Array[String]:
	var out: Array[String] = []
	for kind: String in Monster.kinds():
		out.append(kind)
	if config.get("monsters") is Dictionary:
		for kind: String in config["monsters"]:
			if kind not in out:
				out.append(kind)
	return out


## CHARS with a character for every monster kind (monster_kinds): its
## initial if free (lower case, then upper), else the first free of SPARE_CHARS.
static func chars(config := {}) -> Dictionary:
	var out := CHARS.duplicate()
	var used := {}
	for meaning: String in out:
		used[out[meaning]] = true
	for kind in monster_kinds(config):
		var meaning := "monster_" + kind
		if out.has(meaning):
			continue
		var initial := kind.left(1)
		for pick: String in [initial.to_lower(), initial.to_upper()] + Array(SPARE_CHARS.split("")):
			if not used.has(pick):
				out[meaning] = pick
				used[pick] = true
				break
	return out


## What place() can put down: each monster kind by its name, then THINGS.
static func things(config := {}) -> Dictionary:
	var out := {}
	for kind in monster_kinds(config):
		out[kind] = "monster_" + kind
	out.merge(THINGS)
	return out


## [param kind] in a few words for the prompt: lore's (KIND_WORDS) or its
## row's label and role, and how it idles when its entry does not say.
static func kind_line(kind: String) -> String:
	var row: Dictionary = Monster.kinds().get(kind, {})
	var words := str(KIND_WORDS.get(kind, ""))
	if words.is_empty() and row.is_empty():
		words = "this level's own kind"
	elif words.is_empty():
		var label := str(row.get("label", "")).to_lower()
		words = label if not label.is_empty() else kind
		if Animal.is_wild(kind):
			var role := str(row.get("role", ""))
			var does := str(ROLE_WORDS.get(role, ""))
			if role == "predator":
				does = does % (", ".join(row.get("diet", [])) if not (row.get("diet", []) as Array).is_empty() else "what it can")
			words += ", a wild animal" + (": " + does if not does.is_empty() else "")
	var idle := "none"
	if not row.is_empty():
		idle = str(Monster.IDLE_MODES.find_key(row["idle"]))
	return "- %s: %s (idles: %s)" % [kind, words, idle]


## The loot tables (levels/loot.json, decision 509) and the items each can
## give, for the prompt: "supplies (ration, bandaging_kit), ...".
static func loot_line() -> String:
	var tables := PackedStringArray()
	for table: String in Items.loot_tables():
		var items := PackedStringArray()
		for row: Dictionary in Items.loot_tables()[table]:
			if str(row["item"]) not in items:
				items.append(str(row["item"]))
		tables.append("%s (%s)" % [table, ", ".join(items)])
	return ", ".join(tables) if not tables.is_empty() else "none"


## Which trade works which work site (economy.json sites.trades, economy's
## 521), for the prompt: "A town's woodcutter works the first woodlot marked
## for it, its hunter the first hunting ground, ...".
static func site_line() -> String:
	var trades: Dictionary = Production.read_rules().get("sites", {}).get("trades", {})
	var worked := PackedStringArray()
	for trade: String in trades:
		worked.append(("%s works the first %s marked for it" if worked.is_empty() else "its %s the first %s")
			% [trade, str(trades[trade]).replace("_", " ")])
	var idle := PackedStringArray()
	for kind: String in Level.PLACE_KINDS:
		if kind in ["woodlot", "hunting_ground", "quarry", "farm", "mine"] and kind not in trades.values():
			idle.append(kind.replace("_", " "))
	if worked.is_empty():
		return "No trade works a site yet."
	return "A town's %s, walking there and back from its store, so the farther the site the longer each trip%s." % [", ".join(worked),
		" (no one works a %s yet)" % " or ".join(idle) if not idle.is_empty() else ""]


## TOOLS with place()'s things as [param config]'s level offers them, and
## its loot tables (decision 509).
static func tools(config := {}) -> Array:
	var out := TOOLS.duplicate(true)
	for tool: Dictionary in out:
		if tool["name"] == "place":
			tool["input_schema"]["properties"]["thing"]["enum"] = things(config).keys()
			tool["input_schema"]["properties"]["loot"]["enum"] = Items.loot_tables().keys()
		elif tool["name"] == "mark_place":
			tool["input_schema"]["properties"]["kind"]["enum"] = Level.PLACE_KINDS.duplicate()
	return out


## A colour for [param meaning] in level.json's legend, none of [param taken]'s
## (a kind with none in Level.LEGEND; its hue from its name, the same each time).
static func kind_colour(meaning: String, taken: Array) -> Color:
	var used := {}
	for colour: Color in taken:
		used[colour.to_html(false)] = true
	var hue := float(absi(hash(meaning)) % 360) / 360.0
	var colour := Color.from_hsv(hue, 0.5, 0.7)
	while used.has(colour.to_html(false)):
		hue = fmod(hue + 0.013, 1.0)
		colour = Color.from_hsv(hue, 0.5, 0.7)
	return colour


## The system prompt: what the map is, how it is drawn, what the tools do,
## the prefabs; the same for every request (cached).
static func system_prompt(prefabs_from := Prefab.DIR) -> String:
	var legend := PackedStringArray()
	var chars_now := chars()
	for meaning: String in chars_now:
		legend.append("%s %s" % [chars_now[meaning], meaning.trim_prefix("monster_")])
	var monsters := PackedStringArray()
	for kind in monster_kinds():
		monsters.append(kind_line(kind))
	var prefabs := PackedStringArray()
	for prefab_name in Prefab.names(prefabs_from) + Prefab.kind_names():
		var prefab := Prefab.load_prefab(prefab_name, prefabs_from)
		if prefab.is_empty():
			continue
		var piece: LevelMap = prefab["map"]
		# The grid shows cells only: a building is said in words.
		var buildings: Array = prefab["config"].get("buildings", []) if prefab["config"].get("buildings") is Array else []
		var kinds := PackedStringArray(buildings.map(func(entry: Variant) -> String:
			return str(entry.get("slot", entry.get("kind", ""))).trim_prefix("building.") if entry is Dictionary else ""))
		if prefab_name.begins_with(Prefab.KIND_PREFIX) and Prefab.kind_names().has(prefab_name):
			# A building kind (decision 488): walls round its blocks, its doors in front; said, not drawn.
			# Its kind's words (levels/buildings.json, decision 511), so a longhouse is told from a cottage.
			var words := PackedStringArray(buildings.map(func(entry: Variant) -> String:
				var kind: Dictionary = Level.kinds().get(str(entry.get("kind", "")), {}) if entry is Dictionary else {}
				return str(kind.get("words", "")) + (" (%s)" % entry.get("size", Level.KIND_SIZE) if not kind.is_empty() else "")))
			prefabs.append("%s (%d x %d): a building, %s: %s" % [prefab_name, piece.size.x, piece.size.y, ", ".join(kinds), ", ".join(words)])
			continue
		prefabs.append("%s (%d x %d)%s:\n%s" % [prefab_name, piece.size.x, piece.size.y,
			", a building: %s" % ", ".join(kinds) if not kinds.is_empty() else "",
			grid(piece, prefab["config"], Rect2i(Vector2i.ZERO, piece.size), Rect2i(Vector2i.ZERO, piece.size))])
	return """You build places in Psykinetic, a top-down co-op game on a grid of cells, where players fight goblins with physics (pushing, throwing, knocking down) and explore with talking companions. A player in builder mode has picked an area of a level and asked for something there. Change the area with the tools, then say in a sentence or two what you made; the player sees your changes as a ghost and accepts or discards them.

Make places with something to do, not only scenery: a chest worth opening (and something guarding it), a camp to clear, a captive to free, a larder, a puzzle of crates and boulders. Monsters are few and matter: a camp is two to five, gathered round its fire. Leave ways in: what you make must be reachable on foot from the rest of the area.

The map. Cells are x to the east, y to the south, (0, 0) the top-left of the level. A cell is ground (stone, grass, dirt, or tall grass: hides who stands in it, slows a step, trampled flat), water (not walkable; nothing is built along it), a ford (shallow water, waded slowly), fire (walkable, burns), a stair, void, or a thing standing on ground. Outdoors, void is forest: a void cell next to land is drawn as a tree, so scattered void cells are scattered trees and a block of void is a wood. Walls and doors stand on the edges between two cells; an edge between land and void is a wall of its own (outdoors, the forest's edge). Things: start (where players join), crate (pushable), boulder (heavy, pushable), cart, chest (4 slots of items), torch (light and a little heat), lantern (light), link (to another level; not yours to place), and monsters by their kind:
%s

The grid shows the area and a margin round it, one character a cell (the margin is shown for context; only the area may change):
%s
Each row starts with its y; the first line says the x of the first column. Walls and doors are listed after the grid by the cell and its side.

Monsters idle until someone comes: guard (stands, glances about), wander (strolls near its cell, a radius), patrol (walks a route of cells, round or back and forth), gather (stands or sits round a point, such as a fire: every monster gathering at one cell is one group), none. Without one, a monster idles as its kind does (said above). Wild animals are of no faction: goblins leave them be, and they keep to their herd (grazing as they stroll), so put two to six of a herd together on open ground, never in a camp. Chests hold item ids; the items there are: %s. A loot table (place's loot, for a chest or a monster) is rolled as the level is built, the same every time; the tables and what each can give: %s.

Running water is a stream: the stream tool lays its course, from where it rises to where it goes. Give it a ford or a bridge wherever a path meets it, or the far bank is cut off; a bridge needs level banks of floor at both ends.

Levels join at their edges: walking off one edge arrives on the neighbour's opposite edge, at the same row (east, west) or column (north, south). When the area touches the map's edge with nothing beyond it, new_area makes a new level there (its own map; a first draft of grass, groves and forest round it, open where the way arrives) and carves a way out to the edge through the area. Use it when asked for somewhere new beyond the edge ("a new area east", "the woods past here"), not for changes inside the area.

Places are what factions hold (the goblins, the town, or nobody): a camp, a keep, a farm, a gate, a mine. Each is a cell and a radius; the ground within the radius is its holder's, and no one else's group may walk through it. mark_place names one (its key, kind, cell, radius, who holds it at the start). Mark a place when you build one: a camp's place on its gather point (where its monsters gather), a farmstead's in its yard. A goblin camp can hold captives from the start (mark_place's holds), each taken from a town (the request lists them): someone of that town, or kin of one of its workers ("the smith's daughter"). In town their kin asks players to bring them home, and they go free when the camp falls, so a camp holding a captive is worth clearing. A town's work sites are places too: a woodlot (woods its woodcutter fells: put it at the forest's edge), a hunting ground (open land with game, its hunter's), a quarry (rock to cut stone from), a farm (fields), a mine. Mark one with the town it works for (mark_place's town: the key of the town's stockpile place), held by the town, not far from it, and with a way on foot from the store to it: a site the goblins hold, or that can't be reached, is worked by no one, and the tool's answer says so. %s Some prefabs bring their place with them. A building prefab is a roofed building players walk into: stamp it whole, door and all, rather than drawing its walls yourself. A building can serve a town: set_building gives one in the area a use (%s) and its town, the key of a stockpile place in this level (a place of kind stockpile, held by the town). A town has one building of each use. Stamping over a building drops its use: set it again. town_wall walls a town in: give the rectangle of cells it encloses (its buildings, its store, room to walk) and the wall stands on the edges just outside it, with gates (doors) where roads come in, one in the middle of each side if you name none. One wall per town; it looks as strong as the town has built it (a bank of rubble at first). roof puts a roof over a rectangle of floor of one height that no building covers: a room you walled yourself, or an open shelter (a market stall, a woodshed) on posts at its corners; give it a use and town and it serves the town as a building does.

Ground has a height, 0 to 6 (the grid's Heights block, shown when any cell has one). A step of a level or more between two cells is a ledge: a wall to anyone walking, though a body pushed off it falls to the ground below, and higher ground sees over walls. Stairs join one level to the next: a stair climbs to the one cell beside it a level up. A slope is a stair that looks like a ramp of earth: use slopes outdoors (on hills, banks, outcrops) and stairs in and round buildings; hill and stairs make slopes when asked. Rock is bare rock standing out of the ground, walled round: no one walks on or through it. height raises, lowers or sets cells; hill makes a rounded hill of rings a level each, with stairs up the sides asked; stairs puts a stair or a flight onto a ledge or up from flat ground. Whatever stands on raised ground (things, starts, buildings) needs stairs to it, and a building stands on one height: when a change leaves something cut off or a stair climbing nowhere, the tool's answer says so: put it right. Some outdoor levels have their ground shaped in metres (the request says so): there the Heights block is in half metres (0-9, then a, b, c ...), a rise of more than 0.45 m between neighbours is a cliff no one walks, height, hill and stairs are refused (the ground is shaped in the editor), and a building needs ground flat within 0.05 m under it: stamp it where the ground is flat, or stamp it with pad to cut the ground flat under it (the only shaping you do: a house on a hillside sits on a cut pad).

A town keeps what players bring home in its store: a place of kind stockpile that the town holds. Stamp town_store for one (an open yard with its depot, its shop counter and the store's place, all in one), once per town, near the middle of town on open ground reachable from the gate, its counter facing where players will stand. A depot is a chest placed with use depot: what is put in it is banked. A shop counter is a chest placed with use shop: players buy what the town's workers made and sell what it is short of. Either works only inside the town's store, and is never given items. When a change leaves the store wrong, the tool's answer says so: put it right.

Prefabs to stamp (their top-left at a cell, turned 0-3 quarter turns clockwise; their # is void and leaves the map as it was):
%s""" % ["\n".join(monsters), ", ".join(legend), ", ".join(Items.ids()), loot_line(), site_line(), ", ".join(building_uses()), "\n\n".join(prefabs) if not prefabs.is_empty() else "(none)"]


## What the first request starts with: the level, the area, what is in it.
func _situation() -> String:
	var zone := Level.zone_of(doc.config)
	var shown := area.grow(MARGIN).intersection(Rect2i(Vector2i.ZERO, doc.map.size))
	var text := "The level: %s (\"%s\"), %d x %d cells, %s. The area: x %d to %d, y %d to %d (%d x %d cells).\n\n%s" % [
		map_name, str(doc.config.get("name", map_name)), doc.map.size.x, doc.map.size.y,
		"outdoors (void is forest)" if zone == "outdoors" else "%s (void is nothing, walled off)" % {"indoors": "indoors", "cave": "a cave", "dungeon": "a dungeon"}.get(zone, zone),
		area.position.x, area.end.x - 1, area.position.y, area.end.y - 1, area.size.x, area.size.y,
		grid(doc.map, doc.config, shown, area, relief())]
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
	if not relief().is_empty():
		text += "\n\nThis level's ground is shaped in metres: the Heights block is in half metres."
	var towns := town_ids()
	if not towns.is_empty():
		text += "\n\nTowns a camp may hold captives from: " + ", ".join(towns) + "."
	var chars_here := chars(doc.config)
	var own := PackedStringArray()
	for kind in monster_kinds(doc.config):
		if not Monster.kinds().has(kind):
			own.append("%s (%s on the grid)" % [kind, chars_here["monster_" + kind]])
	if not own.is_empty():
		text += "\n\nThis level has monster kinds of its own: " + ", ".join(own) + "."
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
static func grid(map: LevelMap, config: Dictionary, shown: Rect2i, inside: Rect2i, ground := {}) -> String:
	var lines := PackedStringArray()
	lines.append("x from %d%s" % [shown.position.x, "" if shown == inside else " (area: x %d-%d, y %d-%d)" % [
		inside.position.x, inside.end.x - 1, inside.position.y, inside.end.y - 1]])
	var chars_here := chars(config)
	for y in range(shown.position.y, shown.end.y):
		var row := ""
		for x in range(shown.position.x, shown.end.x):
			row += str(chars_here.get(map.cell(Vector2i(x, y)), "?"))
		lines.append("%4d %s" % [y, row])
	# Heights, when any cell shown has one: a digit a cell, the same rows;
	# over relief (decision 527) its half metres, a character a cell.
	var heights: Dictionary = map.heights if ground.is_empty() else Relief.whole_levels(ground["field"], ground["size"])
	var raised := not ground.is_empty()
	for at: Variant in heights if not raised else {}:
		if shown.has_point(at):
			raised = true
			break
	if raised:
		lines.append("Heights (0 to 6, a digit a cell, the same rows):" if ground.is_empty()
			else "Heights (the ground in half metres, %s a character a cell, the same rows):" % HALF_METRES.substr(0, 12))
		for y in range(shown.position.y, shown.end.y):
			var row := ""
			for x in range(shown.position.x, shown.end.x):
				var level := int(heights.get(Vector2i(x, y), 0))
				row += "#" if map.cell(Vector2i(x, y)) == "void" else str(level) if ground.is_empty() \
					else HALF_METRES[clampi(level, 0, HALF_METRES.length() - 1)]
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
	for roof: Variant in config.get("roofs", []) if config.get("roofs") is Array else []:
		var rect: Variant = Level.town_wall_rect(roof)
		if rect != null and shown.intersects(rect):
			notes.append("roof " + JSON.stringify(roof))
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
	{"name": "paint", "description": "Sets cells to a ground (stone, grass, dirt, tall grass), water, a ford, fire, a stair or a slope, rock or void (forest outdoors). Give rectangles, single cells, or both. A thing on a painted cell is gone.",
		"input_schema": {"type": "object", "properties": {
			"ground": {"type": "string", "enum": ["stone", "grass", "dirt", "tall_grass", "water", "ford", "fire", "void", "stair", "slope", "rock"]},
			"rects": {"type": "array", "items": _RECT},
			"cells": {"type": "array", "items": _CELL}},
			"required": ["ground"]}},
	{"name": "edges", "description": "Sets walls, doors or clear (no wall) on the sides of cells: each item is a cell, a side and what goes there. For a wall round a rectangle use fence.",
		"input_schema": {"type": "object", "properties": {
			"set": {"type": "array", "items": {"type": "object", "properties": {
				"at": _CELL, "side": {"type": "string", "enum": ["north", "east", "south", "west"]},
				"kind": {"type": "string", "enum": ["wall", "door", "clear"]}}, "required": ["at", "side", "kind"]}}},
			"required": ["set"]}},
	{"name": "stream", "description": "A stream of running water through the points in order, from where it rises to where it goes, 1 to 3 cells wide; a ford (shallow, waded slowly) where each ford crossing meets it, and a bridge where each bridge crossing (a straight row or column of cells from bank to bank) runs over it.",
		"input_schema": {"type": "object", "properties": {
			"points": {"type": "array", "items": _CELL, "minItems": 2},
			"width": {"type": "integer", "minimum": 1, "maximum": 3},
			"fords": {"type": "array", "items": {"type": "array", "items": _CELL}, "description": "crossings, each a list of cells across the stream"},
			"bridges": {"type": "array", "items": {"type": "array", "items": _CELL}, "description": "crossings, each a straight list of cells from one bank to the other"}},
			"required": ["points"]}},
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
	{"name": "height", "description": "Raises or lowers cells a level (change raise or lower), or sets them to a height (change set, with level 0 to 6). Give rectangles, single cells, or both. Void takes no height.",
		"input_schema": {"type": "object", "properties": {
			"change": {"type": "string", "enum": ["raise", "lower", "set"]},
			"level": {"type": "integer", "minimum": 0, "maximum": 6},
			"rects": {"type": "array", "items": _RECT},
			"cells": {"type": "array", "items": _CELL}},
			"required": ["change"]}},
	{"name": "hill", "description": "A rounded hill on the disc of a radius round a cell: rings a level each up to top levels above the lowest ground under it (no more levels than the radius), never lowering higher ground, with a flight of stairs from its foot to its top up each side asked.",
		"input_schema": {"type": "object", "properties": {
			"at": _CELL, "radius": {"type": "integer", "minimum": 1, "maximum": 30},
			"top": {"type": "integer", "minimum": 1, "maximum": 6},
			"stairs": {"type": "array", "items": {"type": "string", "enum": ["north", "east", "south", "west"]}, "description": "the sides a flight of stairs climbs up from"},
			"slope": {"type": "boolean", "description": "its stairs as slopes (a ramp of earth, outdoors)"}},
			"required": ["at", "radius", "top"]}},
	{"name": "stairs", "description": "Stairs at a cell climbing toward a side. Beside a ledge that way, a flight up onto it (a stair a level, the cell given the top one, starting as many cells back); otherwise count stairs in a row climbing a level each from the cell's height, the cell after the last one the landing. Other sides a level above a stair are walled, so it climbs only the way asked.",
		"input_schema": {"type": "object", "properties": {
			"at": _CELL, "up": {"type": "string", "enum": ["north", "east", "south", "west"]},
			"count": {"type": "integer", "minimum": 1, "maximum": 6},
			"slope": {"type": "boolean", "description": "slopes (a ramp of earth, outdoors) rather than stairs"}},
			"required": ["at", "up"]}},
	{"name": "place", "description": "Puts a thing on a cell (its ground stays), with its settings: a monster's facing and idling, a chest's items, a loot table for a chest or a monster, a name.",
		"input_schema": {"type": "object", "properties": {
			"at": _CELL,
			"thing": {"type": "string", "enum": [], "description": "a monster by its kind, or a thing"},
			"name": {"type": "string", "description": "optional, e.g. \"Gutrot\""},
			"facing": {"type": "string", "enum": ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]},
			"idle": {"type": "object", "properties": {
				"mode": {"type": "string", "enum": ["guard", "wander", "patrol", "gather", "none"]},
				"radius": {"type": "integer", "minimum": 1, "maximum": 8},
				"route": {"type": "array", "items": _CELL},
				"loop": {"type": "boolean"},
				"point": _CELL}, "required": ["mode"]},
			"items": {"type": "array", "items": {"type": "string"}, "maxItems": 4, "description": "a chest's items, by id"},
			"loot": {"type": "string", "description": "a chest or a monster: a loot table by name (levels/loot.json), rolled as the level is built: a chest's empty slots filled, a monster carrying it and dropping it where it falls"},
			"use": {"type": "string", "enum": ["depot", "shop"], "description": "a chest only: the town's depot (what is put in is banked) or shop counter (players buy and sell); inside the town's store, and given no items"}},
			"required": ["at", "thing"]}},
	{"name": "stamp", "description": "Stamps a prefab with its top-left at a cell, turned 0-3 quarter turns clockwise. Its void cells leave the map as it was.",
		"input_schema": {"type": "object", "properties": {"prefab": {"type": "string"}, "at": _CELL,
			"turns": {"type": "integer", "minimum": 0, "maximum": 3},
			"pad": {"type": "boolean", "description": "on ground shaped in metres: cut the ground flat under each building it brings (and a cell round it) first"}},
			"required": ["prefab", "at"]}},
	{"name": "mark_place", "description": "Marks a place factions hold: a cell in the area and a radius of ground round it, held at the start by the goblins, the town or nobody. A key already used is moved or changed.",
		"input_schema": {"type": "object", "properties": {
			"key": {"type": "string", "description": "lower case letters, digits and _, e.g. \"goblin_camp\""},
			"kind": {"type": "string", "enum": [], "description": "what it is (Level.PLACE_KINDS)"},
			"town": {"type": "string", "description": "a work site only (woodlot, hunting_ground, quarry, farm, mine): the key of the stockpile place here whose town works it"},
			"at": _CELL,
			"radius": {"type": "integer", "minimum": 1, "maximum": 32},
			"holder": {"type": "string", "enum": ["goblins", "town", "nobody"]},
			"name": {"type": "string", "description": "optional, how it is called, e.g. \"the old farmstead\""},
			"holds": {"type": "array", "description": "a camp only: captives it holds from the start, each taken from a town (its id from the list of towns)",
				"items": {"type": "object", "properties": {
					"town": {"type": "string", "description": "a town's id, \"<level>/<store key>\""},
					"resident": {"type": "string", "description": "who: a resident's name, or their kin, e.g. \"the smith's daughter\" (a <trade>'s son, daughter, brother, sister, father, mother or cousin)"},
					"name": {"type": "string", "description": "optional, the captive's name"},
					"trade": {"type": "string", "description": "optional, the captive's own trade"}},
					"required": ["town", "resident"]}}},
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
	{"name": "roof", "description": "Roofs a rectangle of cells (a room you walled, or an open shelter on posts: no walls needed), drawn in a set of roof pieces, its ridge along x or z (along the long side if not given), with a use and town as a building's if it serves one. The cells must be floor of one height, clear of buildings and other roofs. A roof already over any of the cells is replaced; remove takes the roofs over the rectangle away.",
		"input_schema": {"type": "object", "properties": {
			"rect": _RECT,
			"set": {"type": "string", "enum": Level.ROOF_SETS},
			"remove": {"type": "boolean", "description": "true: take away the roofs over the rectangle instead"},
			"ridge": {"type": "string", "enum": ["x", "z"]},
			"use": {"type": "string", "description": "a building use, or empty for none"},
			"town": {"type": "string", "description": "the key of a stockpile place in this level; empty for none"}},
			"required": ["rect"]}},
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
	if tool in ["height", "hill", "stairs"] and working.map.has_relief():
		# Whole levels the relief would hide (decision 527).
		return _no("this level's ground is shaped in metres: shape it in the editor")
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
		"stream":
			return _stream(given)
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
		"height":
			var cells: Array[Vector2i] = []
			for rect_value: Variant in given.get("rects", []):
				var rect: Variant = _rect(rect_value)
				if rect == null:
					return _no("a rectangle needs x, y, w and h")
				for y in range(rect.position.y, rect.end.y):
					for x in range(rect.position.x, rect.end.x):
						cells.append(Vector2i(x, y))
			for cell_value: Variant in given.get("cells", []):
				var at: Variant = Level._tile(cell_value)
				if at == null:
					return _no("a cell is [x, y]")
				cells.append(at)
			match str(given.get("change", "")):
				"raise":
					return _lay(HeightTools.raise(working.map, cells, 1), "raised %d cells a level" % cells.size())
				"lower":
					return _lay(HeightTools.raise(working.map, cells, -1), "lowered %d cells a level" % cells.size())
				"set":
					var level := clampi(int(given.get("level", 0)), 0, Level.MAX_HEIGHT)
					return _lay(HeightTools.level(working.map, cells, level), "set %d cells to height %d" % [cells.size(), level])
			return _no("change is raise, lower or set")
		"hill":
			var at: Variant = Level._tile(given.get("at"))
			if at == null:
				return _no("at is [x, y]")
			var sides: Array[Vector2i] = []
			for side: Variant in given.get("stairs", []):
				if SIDES.has(str(side)):
					sides.append(SIDES[str(side)])
			var radius := clampi(int(given.get("radius", 4)), 1, 30)
			return _lay(_sloped(HeightTools.hill(working.map, at, radius, clampi(int(given.get("top", 2)), 1, Level.MAX_HEIGHT), sides), given),
				"a hill round %s, radius %d" % [at, radius])
		"stairs":
			var at: Variant = Level._tile(given.get("at"))
			var up := str(given.get("up", ""))
			if at == null or not SIDES.has(up):
				return _no("at is [x, y]; up is north, east, south or west")
			var dir: Vector2i = SIDES[up]
			var count := clampi(int(given.get("count", 1)), 1, Level.MAX_HEIGHT)
			var ledge := HeightTools.height_of(working.map, at + dir) > HeightTools.height_of(working.map, at) + 1
			var changes := HeightTools.stair(working.map, at, dir) if ledge or count == 1 \
					else HeightTools.flight(working.map, at, at + dir * count)
			return _lay(_sloped(changes, given), "%d %s climbing %s" % [(changes["cells"] as Dictionary).size(), "slopes" if bool(given.get("slope", false)) else "stairs", up])
		"place":
			return _place(given)
		"stamp":
			var prefab_name := str(given.get("prefab", ""))
			var at: Variant = Level._tile(given.get("at"))
			if at == null:
				return _no("at is [x, y]")
			var prefab := Prefab.load_prefab(prefab_name, prefab_dir)
			if prefab.is_empty():
				return _no("no prefab \"%s\" (there are: %s)" % [prefab_name, ", ".join(Prefab.names(prefab_dir) + Prefab.kind_names())])
			prefab = Prefab.rotated(prefab, int(given.get("turns", 0)))
			var size: Vector2i = (prefab["map"] as LevelMap).size
			if not area.encloses(Rect2i(at, size)):
				return _no("%s turned so is %d x %d: at %s it does not fit in the area" % [prefab_name, size.x, size.y, at])
			var stamped := Prefab.stamp_changes(prefab, working.map, at, working.config)
			var had: Array = working.config.get("buildings", []) if working.config.get("buildings") is Array else []
			var placed: Array = (stamped.get("config", {}).get("buildings", []) as Array).filter(func(entry: Variant) -> bool: return entry not in had)
			if bool(given.get("pad", false)) and working.map.has_relief():
				return _padded(stamped, placed, "stamped %s" % prefab_name)
			for entry: Variant in placed:
				var uneven := pad_problem(entry)
				if not uneven.is_empty():
					return _no(uneven + " (stamp with pad to cut it flat)")
			return _lay(stamped, "stamped %s" % prefab_name)
		"mark_place":
			return _mark_place(given)
		"set_building":
			return _set_building(given)
		"town_wall":
			return _town_wall(given)
		"roof":
			return _roof(given)
		"look":
			return {"ok": true, "text": grid(working.map, working.config, area, area, relief())}
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
	var town := str(given.get("town", "")).strip_edges()
	if not town.is_empty():
		# The town that works this site (maps' 517, decision 520): a stockpile place here.
		var stockpiles := places.keys().filter(func(other: String) -> bool:
			return other != key and places[other] is Dictionary and str(places[other].get("kind", "")) == "stockpile")
		if town not in stockpiles:
			return _no("town is the key of a stockpile place here (%s)" % (", ".join(stockpiles) if not stockpiles.is_empty() else "there is none: mark_place one, kind stockpile"))
		place["town"] = town
	if given.has("holds"):
		# Captives held from the start (npc's 518, decision 519), each from a real town.
		if kind != "camp" or not given["holds"] is Array:
			return _no("holds is a list, and for a camp only")
		var towns := town_ids()
		var holds: Array = []
		for hold: Variant in given["holds"]:
			if not hold is Dictionary or str(hold.get("town", "")).is_empty() or str(hold.get("resident", "")).is_empty():
				return _no("each hold is {town, resident}")
			if str(hold["town"]) not in towns:
				return _no("no town %s (there are: %s)" % [hold["town"], ", ".join(towns) if not towns.is_empty() else "none yet: a town's store is a stockpile place"])
			var kept := {"town": str(hold["town"]), "resident": str(hold["resident"])}
			for field in ["name", "trade"]:
				if not str(hold.get(field, "")).is_empty():
					kept[field] = str(hold[field])
			holds.append(kept)
		if not holds.is_empty():
			place["holds"] = holds
	var again := places.has(key)
	places[key] = place
	working.apply_changes({"config": {"places": places}})
	return {"ok": true, "text": "%s the place %s: a %s at %s, radius %d, held by %s%s" % ["changed" if again else "marked", key, kind, at, place["radius"], holder,
		", holding %d captives" % (place["holds"] as Array).size() if place.has("holds") else ""] \
		+ (", worked by the town of %s" % town if place.has("town") else "")}


## The towns a camp may hold captives from (decision 519): every stockpile
## place on the world map, "<level>/<key>", this level's as it is being made.
func town_ids() -> Array[String]:
	var out: Array[String] = []
	var world_map := WorldMap.build()
	for area_name: String in world_map.areas:
		if area_name == map_name:
			continue
		var places: Dictionary = world_map.areas[area_name].get("places", {})
		for key: String in places:
			if str(places[key].get("kind", "")) == "stockpile":
				out.append("%s/%s" % [area_name, key])
	var here: Dictionary = Level.places_from(working.config, [] as Array[String])
	for key: String in here:
		if here[key]["kind"] == "stockpile":
			out.append("%s/%s" % [map_name, key])
	out.sort()
	return out


## The uses a map building may have: the economy rules' buildings (the
## town wall is a record of its own, not a building's use).
static func building_uses() -> Array[String]:
	var out: Array[String] = []
	for use: Variant in Production.read_rules().get("buildings", {}):
		if str(use) != "walls":
			out.append(str(use))
	out.sort()
	return out


## The level's relief (relief.png, maps' 525: LevelMap.relief) as
## HeightTools reads it, {field, size}, or {} with none (decision 527).
func relief() -> Dictionary:
	if not working.map.has_relief():
		return {}
	return {"field": working.map.relief_field(), "size": working.map.size}


## [param stamped] laid with the ground under each of [param placed] (the
## buildings it brings) cut flat first (Relief.pad, a cell's apron round
## it; decision 527 amended): builder shapes ground only under a building
## it places. Undone and refused if one still isn't flat (water under it).
func _padded(stamped: Dictionary, placed: Array, done: String) -> Dictionary:
	var ground := {}
	for entry: Variant in placed:
		var rect: Variant = Level.building_rect(entry)
		if rect != null and str(entry.get("slot", "")) not in Level.SPANS_WATER:
			ground.merge(Relief.pad(working.map, rect, 1)["relief"], true)
	var before := relief()["field"] as PackedFloat32Array
	var cutting := _kept({"relief": ground})
	cutting.erase("outside")
	working.apply_changes(cutting)
	var cut := 0
	for cell: Vector2i in ground:
		if area.has_point(cell) and absf(Relief.at(before, working.map.size, cell) - working.map.relief_at(cell)) > Relief.EPSILON:
			cut += 1
	for entry: Variant in placed:
		var uneven := pad_problem(entry)
		if not uneven.is_empty():
			working.undo()
			return _no(uneven)
	var laid := _lay(stamped, done)
	if laid["ok"] and cut > 0:
		laid["text"] += " (the ground cut flat under it: %d cells)" % cut
	return laid


## Why the building [param entry] can't stand on this level's relief
## (decision 527): its cells not within Relief.PAD_FLAT of each other
## (Level.parse would leave it out), naming the cell furthest off; "" if
## they are, or the level has no relief (whole levels: height_checks).
## A bridge's banks are Level's own check.
func pad_problem(entry: Variant) -> String:
	var ground := relief()
	if ground.is_empty() or not entry is Dictionary or str(entry.get("slot", "")) in Level.SPANS_WATER:
		return ""
	var cells: Array[Vector2i] = []
	for rect in Level.building_blocks(entry):
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if Vector2i(x, y) not in cells:
					cells.append(Vector2i(x, y))
	if cells.is_empty() or Relief.flat(ground["field"], ground["size"], cells):
		return ""
	# Measured from the pad's middle height, so one bump is the cell named.
	var levels: Array[float] = []
	for cell in cells:
		levels.append(Relief.at(ground["field"], ground["size"], cell))
	levels.sort()
	var middle := levels[levels.size() / 2]
	var furthest := cells[0]
	for cell in cells:
		if absf(Relief.at(ground["field"], ground["size"], cell) - middle) > absf(Relief.at(ground["field"], ground["size"], furthest) - middle):
			furthest = cell
	return "the ground under the %s at %s is not flat: %s is %+.2f m off the rest, and a building needs its cells within %.2f m" % [
		str(entry.get("slot", entry.get("kind", "building"))).trim_prefix("building."), Level._tile(entry.get("at")), furthest,
		Relief.at(ground["field"], ground["size"], furthest) - middle, Relief.PAD_FLAT]


func _set_building(given: Dictionary) -> Dictionary:
	var at: Variant = Level._tile(given.get("at"))
	if at == null:
		return _no("set_building needs at: [x, y], a cell of the building")
	if not area.has_point(at):
		return _no("%s is outside the area" % [at])
	var buildings: Array = (working.config["buildings"] as Array).duplicate(true) if working.config.get("buildings") is Array else []
	var index := buildings.find_custom(func(entry: Variant) -> bool:
		return Level.building_blocks(entry).any(func(rect: Rect2i) -> bool: return rect.has_point(at)))
	if index < 0:
		return _no("no building stands on %s: stamp a building prefab first" % [at])
	var uneven := pad_problem(buildings[index])
	if not uneven.is_empty():
		return _no(uneven + ": the level leaves it out, so it serves no town")
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
	# A slot building names its slot, a composed one its kind (decision 511).
	var what := "%s at %s" % [str(entry.get("slot", entry.get("kind", "building"))).trim_prefix("building."), entry.get("at")]
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


## A roof over [param given]'s rect (decision 364's records), replacing
## any over its cells, or none over them (remove); refused, laying
## nothing, if Level.parse would leave it out.
func _roof(given: Dictionary) -> Dictionary:
	var rect: Variant = _rect(given.get("rect"))
	if rect == null:
		return _no("rect needs x, y, w and h")
	if not area.encloses(rect):
		return _no("the roof must be in the area (x %d-%d, y %d-%d)" % [area.position.x, area.end.x - 1, area.position.y, area.end.y - 1])
	var roof_set := str(given.get("set", Level.ROOF_SETS[0]))
	if roof_set not in Level.ROOF_SETS:
		return _no("set is one of %s" % ", ".join(Level.ROOF_SETS))
	var old: Array = (working.config["roofs"] as Array).duplicate(true) if working.config.get("roofs") is Array else []
	var roofs := old.filter(func(entry: Variant) -> bool:
		var at: Variant = Level.town_wall_rect(entry)
		return at == null or not (at as Rect2i).intersects(rect))
	var gone := old.size() - roofs.size()
	if bool(given.get("remove", false)):
		working.apply_changes({"config": {"roofs": roofs}})
		return {"ok": true, "text": "took away %d roofs" % gone}
	var entry := {"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "set": roof_set}
	if str(given.get("ridge", "")) in ["x", "z"]:
		entry["ridge"] = str(given["ridge"])
	for key in ["use", "town"]:
		if not str(given.get(key, "")).is_empty():
			entry[key] = str(given[key])
	roofs.append(entry)
	var before: Array = working.parsed()["warnings"]
	working.apply_changes({"config": {"roofs": roofs}})
	var parsed := working.parsed()
	var new := (parsed["warnings"] as Array).filter(func(warning: String) -> bool: return warning not in before)
	# Asked of Level whether it kept the roof, not read from the new warnings:
	# a roof it replaced, over the same rect and already left out, had the same words.
	if not (parsed["roofs"] as Array).any(func(roof: Dictionary) -> bool: return roof["rect"] == rect):
		working.apply_changes({"config": {"roofs": old}})
		var why := (parsed["warnings"] as Array).filter(func(warning: String) -> bool: return warning.begins_with("the roof at %s" % rect.position))
		return _no("; ".join(why) if not why.is_empty() else "the level left the roof out")
	if new.any(func(warning: String) -> bool: return "left out" in warning):
		working.apply_changes({"config": {"roofs": old}})
		return _no("; ".join(new))
	return {"ok": true, "text": "a %s roof over x %d-%d, y %d-%d%s%s" % [roof_set, rect.position.x, rect.end.x - 1, rect.position.y, rect.end.y - 1,
		" (replacing %d)" % gone if gone > 0 else "", "; " + "; ".join(new) if not new.is_empty() else ""]}


## A stream as the editor lays one (lay_stream, maps' 505; decision 510):
## water [param given] width wide along Streams.course through its points
## (a ford already on the middle stays one), fords where a ford crossing
## meets it, bridges (Streams.bridge_over) where a bridge crossing runs
## over it, and the middle as a level.json "streams" path. Refused and
## taken back if Level leaves the stream out; a bridge it leaves out is
## said, the stream kept.
func _stream(given: Dictionary) -> Dictionary:
	var points: Array[Vector2i] = []
	for point: Variant in given.get("points", []):
		var at: Variant = Level._tile(point)
		if at == null:
			return _no("a point is [x, y]")
		if not area.has_point(at):
			return _no("%s is outside the area: a stream runs inside it" % [at])
		points.append(at)
	if points.size() < 2:
		return _no("a stream needs two points or more: where it rises and where it goes")
	var width := clampi(int(given.get("width", 2)), 1, 3)
	var middle := Streams.course(points)
	var cells: Dictionary[Vector2i, String] = {}
	for cell in Streams.widen(middle, width):
		if area.has_point(cell):
			cells[cell] = "water"
	for cell in middle:
		if working.map.cell(cell) == "ford":
			cells.erase(cell)
	var wet: Dictionary = {}
	for cell: Vector2i in cells:
		wet[cell] = true
	for cell in middle:
		wet[cell] = true
	var crossings := {"fords": [], "bridges": []}
	for key: String in crossings:
		for crossing: Variant in given.get(key, []):
			var run: Array[Vector2i] = []
			for value: Variant in (crossing if crossing is Array else []):
				var at: Variant = Level._tile(value)
				if at == null:
					return _no("each of %s is a list of cells [x, y]" % key)
				run.append(at)
			crossings[key].append(run)
	var fords := 0
	for run: Array[Vector2i] in crossings["fords"]:
		for cell in run:
			if wet.has(cell):
				cells[cell] = "ford"
				fords += 1
	var notes: Array[String] = []
	var buildings: Array = (working.config["buildings"] as Array).duplicate(true) if working.config.get("buildings") is Array else []
	var bridges := 0
	for run: Array[Vector2i] in crossings["bridges"]:
		var bridge := Streams.bridge_over(run, wet)
		if bridge.is_empty():
			notes.append("the bridge crossing from %s never runs over the stream in a straight line: no bridge" % [run[0] if not run.is_empty() else "nowhere"])
			continue
		buildings.append(bridge)
		bridges += 1
	var course := []
	for cell in middle:
		course.append([cell.x, cell.y])
	var streams: Array = (working.config["streams"] as Array).duplicate(true) if working.config.get("streams") is Array else []
	var index := streams.size()
	streams.append({"path": course})
	var config := {"streams": streams}
	if bridges > 0:
		config["buildings"] = buildings
	var before: Array = working.parsed()["warnings"]
	var laid := _lay({"cells": cells, "config": config}, "a stream, %d wide, %d cells from %s to %s%s%s" % [width, middle.size(), middle[0], middle[-1],
		", %d fords" % fords if fords > 0 else "", ", %d bridges" % bridges if bridges > 0 else ""])
	var new := (working.parsed()["warnings"] as Array).filter(func(warning: String) -> bool: return warning not in before)
	var left_out := new.filter(func(warning: String) -> bool: return warning.begins_with("stream %d:" % index) or warning.begins_with("stream %d " % index))
	if not left_out.is_empty():
		working.undo()
		return _no("; ".join(left_out))
	notes.append_array(new)
	if not notes.is_empty():
		laid["text"] += "; " + "; ".join(notes)
	return laid


func _place(given: Dictionary) -> Dictionary:
	var at: Variant = Level._tile(given.get("at"))
	var thing := str(given.get("thing", ""))
	var offered := things(working.config)
	if at == null or not offered.has(thing):
		return _no("place needs at: [x, y] and a thing (%s)" % ", ".join(offered.keys()))
	if not area.has_point(at):
		return _no("%s is outside the area" % [at])
	if working.map.cell(at) in ["void", "water"]:
		return _no("%s is %s: paint ground there first" % [at, working.map.cell(at)])
	var meaning: String = offered[thing]
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
	if given.has("use"):
		var use := str(given["use"])
		if meaning != "chest" or use not in ["depot", "shop"]:
			return _no("use is for a chest only: depot or shop")
		if given.has("items") and not (given["items"] as Array).is_empty():
			return _no("a %s keeps nothing: give it no items" % ("depot" if use == "depot" else "shop counter"))
		entry["props"] = {use: true}
		entry["facing"] = [0, 1]
		if FACINGS.has(str(given.get("facing", ""))):
			var faces: Vector2i = FACINGS[str(given["facing"])]
			entry["facing"] = [faces.x, faces.y]
	elif meaning == "chest" and given.has("items"):
		var slots := Items.tidy(given["items"], Chest.SLOTS)
		var unknown: Array = (given["items"] as Array).filter(func(id: Variant) -> bool: return not Items.exists(str(id)))
		if not unknown.is_empty():
			return _no("no items %s (there are: %s)" % [unknown, ", ".join(Items.ids())])
		entry["props"] = {"slots": Array(slots)}
	if given.has("loot"):
		var table := str(given["loot"])
		if not (meaning == "chest" or meaning.begins_with("monster_")) or given.has("use"):
			return _no("loot is for a monster or a chest (not a depot or a shop counter)")
		if not Items.has_loot(table):
			return _no("no loot table %s (there are: %s)" % [table, ", ".join(Items.loot_tables().keys())])
		entry["loot"] = table
	var changes := {"cells": {at: meaning}, "covers": [at]}
	if entry.size() > 1:
		changes["entries"] = [entry]
	if not working.map.colours.has(meaning):
		# A kind past Level.LEGEND: level.json's legend gives it a colour, so layout.png holds it.
		var legend: Dictionary = (working.config["legend"] as Dictionary).duplicate() if working.config.get("legend") is Dictionary else {}
		legend[meaning] = "#" + kind_colour(meaning, working.map.colours.values()).to_html(false)
		changes["config"] = {"legend": legend}
	return _lay(changes, "placed %s at %s" % [thing, at])


## [param changes] with its stairs made slopes when [param given] asks
## ("slope": true; maps' 513, a stair to the sim, a ramp to the eye).
static func _sloped(changes: Dictionary, given: Dictionary) -> Dictionary:
	if bool(given.get("slope", false)):
		for at: Vector2i in changes.get("cells", {}):
			if changes["cells"][at] == "stair":
				changes["cells"][at] = "slope"
	return changes


## Lays [param changes] on the working copy, kept to the area; {ok, text}.
func _lay(changes: Dictionary, done: String) -> Dictionary:
	if not str(changes.get("reason", "")).is_empty():
		return _no(changes["reason"])
	if changes.has("warnings"):
		done += " (" + "; ".join(changes["warnings"]) + ")"
	var kept := _kept(changes)
	var outside: int = kept["outside"]
	kept.erase("outside")
	working.apply_changes(kept)
	return {"ok": true, "text": "%s%s" % [done, " (%d cells or edges outside the area left out)" % outside if outside > 0 else ""]}


## [param changes] kept to the area, with "outside" the count left out.
func _kept(changes: Dictionary) -> Dictionary:
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
		else:
			outside += 1
	kept["heights"] = heights
	var ground: Dictionary = {}
	for cell: Vector2i in changes.get("relief", {}):
		if area.has_point(cell):
			ground[cell] = changes["relief"][cell]
		else:
			outside += 1
	if not ground.is_empty():
		kept["relief"] = ground
	for list in ["entries", "links"]:
		kept[list] = (changes.get(list, []) as Array).filter(func(entry: Dictionary) -> bool:
			return area.has_point(Level._tile(entry.get("at"))))
	kept["covers"] = (changes.get("covers", cells.keys()) as Array).filter(func(cell: Vector2i) -> bool: return area.has_point(cell))
	if changes.has("config"):
		# A stamped prefab's places and buildings (it fits in the area, so they do).
		kept["config"] = changes["config"]
	kept["outside"] = outside
	return kept


## Each work site that names its town (decision 520) and can't serve it:
## held by someone else, or cut off on foot from the town's store
## (HeightTools.reaches: walls, ledges or cliffs, water, forest).
func site_checks() -> Array[String]:
	var out: Array[String] = []
	var places: Dictionary = Level.places_from(working.config, [] as Array[String])
	var ground := relief()
	for key: String in places:
		var town := str(places[key].get("town", ""))
		if town.is_empty() or not places.has(town):
			continue
		var site: Dictionary = places[key]
		if site["holder"] != places[town]["holder"]:
			out.append("the %s %s is held by %s, not by its town %s: its worker can't work it until the town holds it" % [site["kind"], key, site["holder"], town])
		elif not HeightTools.reaches(working.map, places[town]["cell"], site["cell"], 70000, ground):
			out.append("the %s %s at %s can't be reached on foot from its town's store %s at %s: open a way" % [site["kind"], key, site["cell"], town, places[town]["cell"]])
	return out


## What is wrong with the area's heights on the working copy: a stair
## that climbs nowhere or could climb two ways (Level.parse's rule), and a
## thing, start or building cut off by ledges (HeightTools.ledge_warnings)
## or a building standing on more than one height. Over the level's relief
## (decision 527) a stair climbs half a level to Relief.STAIR_RISE, a ledge
## is a cliff, and a building's pad is pad_problem's.
func height_checks() -> Array[String]:
	var out: Array[String] = []
	var map := working.map
	var ground := relief()
	if ground.is_empty() and map.heights.is_empty() and doc.map.heights.is_empty():
		return out
	var things: Array[Vector2i] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var at := Vector2i(x, y)
			var meaning := map.cell(at)
			if meaning in ["stair", "slope"]:
				var ups := HeightTools.FOUR.filter(func(side: Vector2i) -> bool:
					return map.walkable(at + side) and _climbs_to(at, side, ground) and map.edge(Terrain.edge_key(at, side)) == "clear")
				if ups.is_empty():
					out.append("the %s at %s has no cell a level up beside it: it is floor" % [meaning, at])
				elif ups.size() > 1:
					out.append("the %s at %s could climb two ways: wall one or level it" % [meaning, at])
			elif meaning not in GROUNDS and meaning not in ["water", "void"]:
				things.append(at)
	for building: Variant in working.config.get("buildings", []):
		var rect: Variant = Level.building_rect(building)
		if rect == null or not area.intersects(rect):
			continue
		if not ground.is_empty():
			var uneven := pad_problem(building)
			if not uneven.is_empty():
				out.append(uneven)
			things.append(rect.position)
			continue
		var levels := {}
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if map.walkable(Vector2i(x, y)):
					levels[int(map.heights.get(Vector2i(x, y), 0))] = true
		if levels.size() > 1:
			out.append("the building at %s stands on more than one height: level it" % rect.position)
		things.append(rect.position)
	out.append_array(HeightTools.ledge_warnings(map, things, ground))
	return out


## Whether the ground beside [param at] toward [param side] stands where a
## stair climbs: a level up, or over [param ground] (relief) half a level
## to Relief.STAIR_RISE up.
func _climbs_to(at: Vector2i, side: Vector2i, ground: Dictionary) -> bool:
	if ground.is_empty():
		return int(working.map.heights.get(at + side, 0)) == int(working.map.heights.get(at, 0)) + 1
	var rise := Relief.at(ground["field"], ground["size"], at + side) - Relief.at(ground["field"], ground["size"], at)
	return rise >= Relief.LEVEL_M * 0.5 and rise <= Relief.STAIR_RISE + Relief.EPSILON


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
	var ground: Dictionary[Vector2i, float] = {}
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
			if working.map.has_relief() and absf(working.map.relief_at(at) - doc.map.relief_at(at)) > Relief.EPSILON:
				ground[at] = working.map.relief_at(at)
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
	if not ground.is_empty():
		out["relief"] = ground
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
		created_doc = draft_level(new_area, map_name, zone, Level.region_of(doc.config))
		created = str(new_area["name"])
	var changed := doc.apply_changes(changes)
	_fresh_working()
	return changed


## The new level [param plan] (new_area's) as a MapDoc to save in the
## overlay, joined back to [param beside] on its opposite side, its
## [param zone] (DayNight.ZONES: how it is lit) and [param region] (a lore
## region: its weather) those of the level it leads from.
static func draft_level(plan: Dictionary, beside: String, zone: String, region := Level.DEFAULT_REGION) -> MapDoc:
	var joined: String = Level.OPPOSITE[plan["side"]]
	var made := MapDoc.new()
	made.folder = Level.overlay_dir + str(plan["name"]) + "/"
	made.map = AreaDraft.draft(plan["size"], int(plan["seed"]), joined, int(plan["gate"]))
	made.config = {"name": plan["title"], "zone": zone, "region": region}
	if not str(plan.get("description", "")).is_empty():
		made.config["about"] = plan["description"]
	WorldMap.put_neighbours(made, {joined: beside})
	made.dirty = true
	return made


## Forgets the proposal (the conversation stays, for a new follow-up).
func discard() -> void:
	_fresh_working()
