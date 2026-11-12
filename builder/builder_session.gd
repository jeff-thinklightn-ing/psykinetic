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
	# lore's lines (792 amended), from facts it holds, with where lore puts each.
	"skeleton": "one of the barrow's dead, angry at being disturbed, attacks whoever comes down; in the barrow",
	"skeleton_guard": "one of the barrow's dead, moved by the draugr's magic, keeps its post; in the barrow",
	"robber": "a Mound-breaker, a grave robber plundering the barrow for its relics; in the robbers' camp in the barrow",
	"robber_brute": "the biggest Mound-breaker, who swings the Tomb Sledge and smashes walls; in the robbers' camp in the barrow",
	"bandit": "an outlaw from the forest's camps who robs travellers on its paths; on forest paths and in camps",
	"bandit_brute": "a bigger, heavier outlaw of the forest's camps; on forest paths and in camps",
	"astral_knight": "the spirit of a fallen holy knight of Theus, keeping watch; in the barrow's First Hall, behind its bier",
	"draugr": "the barrow's undead master, keeper of the Hall of Fallen Souls, bargains for gold, fights those who refuse; beneath the barrow's temple",
	"wolf": "a wolf, a wild animal: hunts in the wilds, worse at night",
	"hill_cat": "a great cat, a wild animal: lies up in the rocks and drops on what passes; in the hill rocks",
	"boar": "a wild boar, a wild animal: flees, but charges when cornered; in the wilds",
	"deer": "a wild doe, a wild animal: grazes, flees with the herd; in the wilds",
	"stag": "a stag, a wild animal: a deer with antlers, keeps with the deer; in the wilds",
	"rabbit": "a wild rabbit, a wild animal: grazes, flees with the others; in the wilds",
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
## A place's shape cells (792; buildings' 774): [x, y] each, seats a list.
const SHAPE_CELLS: Array[String] = ["brazier", "lamp", "hearth", "seats"]
const MAX_SEATS := 16
## A place's cells move carries with it (792 amended (2)): the shape cells,
## a trader's bed, a lair's den (move only: mark_place never writes one) and
## a perch's watch; seats and watch are lists.
const MOVED_CELLS: Array[String] = ["brazier", "lamp", "hearth", "seats", "bed", "den", "watch"]
const LIST_CELLS: Array[String] = ["seats", "watch"]
## A place's fields mark_place doesn't write, kept when it marks one again
## (792 amended (2)): another tree's, set in level.json.
const KEPT_FIELDS: Array[String] = ["den", "truce", "opens", "fire_ring", "explore", "lore_id"]
## How far a perch's watch lies from any road (make_hills' PERCH_OFF_SAFE, 814).
const WATCH_OFF_ROAD := 6
const MAX_WATCH := 32
## Why builder mode marks, changes or moves no "stall" place (792 amended (2),
## the coordinator's ruling on economy's answer): Main._vendor_spot stands a
## vendor town's seller at its first stall place in key order, so a new one
## could move Rolf, and no stall seller is designed. Rolf's spot is economy's.
const STALL_SAYS := "a stall's seller isn't designed yet, so no stall place can be marked"
## The decor kinds (Level.DECOR_KINDS) a request lays by hand (841; the
## coordinator's list), each said in the prompt: what it is, and whether it
## is bulky (in the way) or low. rune_strip and carving are lore's lines.
const DECOR_WORDS := {
	"barrel": "a barrel, bulky",
	"sack": "a sack of goods or plunder, bulky",
	"broken_cart": "a broken cart left by a road, bulky",
	"campfire_cold": "a cold campfire, its stones and ash, bulky",
	"bones": "a heap of skulls and long bones (an ossuary's), bulky",
	"bedroll": "a bedroll on the ground (a camp's, a trader's), low",
	"scattered_bones": "a few bones scattered (set dressing, never a find), low",
	"candles": "a cluster of candles on the floor (a chapel's), low",
	"wall_hearth": "a fireplace against an inside wall, two cells wide, from its cell east or south along the wall: indoors on any wall, outdoors only on a building's wall inside it",
	"rune_strip": "dark elven runes on a wall, only in the tower over the mine (the orcs built it to dark elven designs)",
	"carving": "old marks cut in a stone wall by the ancients, the dwarves or the town's first miners: only at the standing stones and milestones, in the dwarven castle and its halls, and in Hollowfell; never in the barrow, never on a town or farm building",
}
## Decor that counts as in the way for one-cell ways (narrow_ways, 841):
## drawn only, never solid in the game, but a player walking with a
## companion would not walk through a barrel.
const BULKY_DECOR: Array[String] = ["barrel", "sack", "broken_cart", "campfire_cold", "bones"]
## Decor kinds a request may not lay by hand, why in words (841).
const DECOR_KEPT_OUT := {
	"fence": "a fence is laid with the fence tool",
	"crate": "place lays a real crate (one a player can push)",
	"cart": "place lays a real cart",
	"captive_post": "a captive's post comes with its captive's camp, not by hand",
	"inn_sign": "an inn's sign comes with its tavern, not by hand",
}
## The standing pieces (Level.BUILDINGS slots, "building.<kind>"; solid and
## doorless) a request lays by hand with piece (842; the coordinator's
## ruling), each said in the prompt.
const PIECE_WORDS := {
	"milestone": "a squat stone by a road, where the road goes cut in its face (carved, needed: a level, a town or a named place players can reach) with an arrow if given (left, right or up, as one reading its front sees it)",
	"hunters_blind": "a hunter's blind, a screen of branches where a hunter waits unseen for game: at a wood's edge or by a game trail",
	"lean_to": "a lean-to, a rough shelter of poles and boughs, open at its front",
	"market_stall": "a market stall, dressing only: an empty stall where nobody sells; no shop comes with it",
}
## Standing pieces held back, why in words (842): whose a shrine is and
## where a lone grave may lie are world facts that wait on Jeff (lore's W1,
## C:/dev/review/lore/bandits_and_hills_sights.md). Unreachable in builder
## mode till then: not offered, refused when named.
const PIECES_NOT_YET := {
	"wayside_shrine": "not yet: whose a wayside shrine is waits on Jeff's word",
	"grave": "not yet: where a lone grave may lie waits on Jeff's word",
}
## What an empty stall's answer says (842; the coordinator's ruling).
const STALL_EMPTY := "an empty stall, dressing only: nobody sells there, and no shop comes with it"
## The tools that change nothing a walker meets: no cut-off check (844).
const UNCUT_TOOLS: Array[String] = ["look", "new_area"]
## How many cut-off patches a refusal names (844).
const CUT_SHOWN := 3
## Who keeps a forest camp (maps' fill_forest).
const CAMP_MIXES: Array[String] = ["bandit", "trader", "mixed"]
## The quarter turns that face a kind building (south as made) to a side.
const KIND_TURNS := {"south": 0, "west": 1, "north": 2, "east": 3}
## The ground a moved thing, link or building stands on.
const WALKED: Array[String] = ["stone", "grass", "dirt", "tall_grass"]
## How near a link its arrival point (from_<level>) is to go with it, in cells.
const ARRIVAL_NEAR := 4.0
## level.json keys a proposal may change as a whole (beyond entries and links).
## The level.json keys a proposal carries to the level on accept: every key
## a tool writes (841 amended (1): decor and skylights were left out, so accept
## dropped them; builder_test reads the tools for a key missing here).
const CONFIG_KEYS: Array[String] = ["neighbours", "places", "buildings", "building_codes", "town_walls", "roofs", "legend", "streams", "decor", "skylights", "spots"]
## Dungeon's layout rules (806), checked on accept: see layout_news.
const LAYOUT_SENSE := preload("res://sim/layout_sense.gd")

## Asks Claude: send(body: Dictionary) -> Dictionary (a Messages API
## response, or {"error": "..."}), awaited (ClaudeClient, StubClaude).
var client: Object
## The towns' records (World.towns on the server), for the builds in hand
## with no building marked for them (decision 566); null for none.
var towns: Towns = World.towns
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
## Why the last accept() laid nothing ("" when it did, or had nothing to lay).
var refused := ""


func _init(level_doc: MapDoc, selected: Rect2i, level_name: String, claude: Object) -> void:
	doc = level_doc
	# The codes the level's buildings go by (decision 537), as Level.parse derives them.
	Level.fill_codes(doc.config)
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
	_reached = {}
	_parses.clear()


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
	# The level's own layout faults (806), and those the proposal adds already said.
	var layout_before := doc_layout_faults()
	var layout_said: Array[String] = []
	# And the arrivals' (806 amended (13)): the level's own the baseline, what the proposal adds said once, a warning.
	var arrivals_before := doc_arrival_faults()
	var arrivals_said: Array[String] = []
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
					var streets_before := street_checks()
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
					# And to the doors onto the streets and the plots (decision 564).
					var streets := street_checks().filter(func(warning: String) -> bool: return warning not in streets_before)
					if not streets.is_empty():
						outcome["text"] += "\nStreets now: " + "; ".join(streets)
					# And to the layout rules, which accepting it must not break (806).
					var now := parsed_of(working)
					var layout := layout_news(layout_before, now)
					var unsaid := layout.filter(func(fault: String) -> bool: return fault not in layout_said)
					layout_said = layout
					if not unsaid.is_empty():
						outcome["text"] += "\nLayout now (fix it before you finish: the player can't accept a fault): " + "; ".join(unsaid)
					# And to the ways in (806 amended (13)): a warning, never a refusal.
					var arrivals := arrival_news(arrivals_before, now)
					var unwarned := arrivals.filter(func(fault: String) -> bool: return fault not in arrivals_said)
					arrivals_said = arrivals
					if not unwarned.is_empty():
						outcome["text"] += "\nArrivals now (" + ARRIVAL_SAYS + "): " + "; ".join(unwarned)
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
	result["street_warnings"] = street_checks()
	var parsed_now := parsed_of(working)
	result["layout_warnings"] = layout_news(layout_before, parsed_now)
	result["arrival_warnings"] = arrival_news(arrivals_before, parsed_now)
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


## Whether [param kind] is an apex (Monster.is_apex: one of a kind with its
## own lair, the great bear, the old grey, the boar king): drawn on the grid
## where one stands, never placed by a request (the coordinator, 792 amended).
static func is_apex(kind: String) -> bool:
	return Monster.is_apex(kind)


## What place() can put down: each monster kind by its name but an apex,
## then THINGS.
static func things(config := {}) -> Dictionary:
	var out := {}
	for kind in monster_kinds(config):
		if is_apex(kind):
			continue
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
	elif not (row.get("diet", []) as Array).is_empty():
		# What it hunts is the sim's (monsters.json's diet), not lore's: read, so it stays true (the coordinator).
		words += "; hunts " + ", ".join(row["diet"])
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
			tool["input_schema"]["properties"]["kind"]["enum"] = Level.PLACE_KINDS.filter(func(kind: String) -> bool: return kind != "stall")
			tool["input_schema"]["properties"]["holder"]["enum"] = Factions.read().names() + [Factions.NOBODY]
			tool["input_schema"]["properties"]["where"]["enum"] = Level.REFUGE_WHERE.duplicate()
		elif tool["name"] == "building":
			tool["input_schema"]["properties"]["kind"]["enum"] = Level.kinds().keys()
			tool["input_schema"]["properties"]["use"]["enum"] = building_uses() + [""]
		elif tool["name"] == "link":
			tool["input_schema"]["properties"]["cue"]["enum"] = Level.CUES + [""]
		elif tool["name"] == "decor":
			tool["input_schema"]["properties"]["kind"]["enum"] = DECOR_WORDS.keys()
		elif tool["name"] == "spot":
			tool["input_schema"]["properties"]["use"]["enum"] = Level.SPOT_USES.duplicate()
			tool["input_schema"]["properties"]["pose"]["enum"] = Level.SPOT_POSES.duplicate()
		elif tool["name"] == "piece":
			tool["input_schema"]["properties"]["kind"]["enum"] = PIECE_WORDS.keys()
			tool["input_schema"]["properties"]["arrow"]["enum"] = Level.CARVED_ARROWS.duplicate()
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
		if not is_apex(kind):
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

The map. Cells are x to the east, y to the south, (0, 0) the top-left of the level. A cell is ground (stone, grass, dirt, or tall grass: hides who stands in it, slows a step, trampled flat), water (not walkable; nothing is built along it), a ford (shallow water, waded slowly), fire (walkable, burns), a stair, void, or a thing standing on ground. Outdoors, void is forest: a void cell next to land is drawn as a tree, so scattered void cells are scattered trees and a block of void is a wood. Walls and doors stand on the edges between two cells; an edge between land and void is a wall of its own (outdoors, the forest's edge). Things: start (where players join), crate (pushable), boulder (heavy, pushable), cart, chest (4 slots of items), torch (light and a little heat), lantern (light), link (a way to another level: the link tool puts one), and monsters by their kind:
%s

The grid shows the area and a margin round it, one character a cell (the margin is shown for context; only the area may change):
%s
Each row starts with its y; the first line says the x of the first column. Walls and doors are listed after the grid by the cell and its side.

Monsters idle until someone comes: guard (stands, glances about), wander (strolls near its cell, a radius), patrol (walks a route of cells, round or back and forth), gather (stands or sits round a point, such as a fire: every monster gathering at one cell is one group), none. Without one, a monster idles as its kind does (said above). Wild animals are of no faction: goblins leave them be, and they keep to their herd (grazing as they stroll), so put two to six of a herd together on open ground, never in a camp. Chests hold item ids; the items there are: %s. A chest of loot goes only in a dungeon (a level below ground, or one that regenerates) and always holds something: items or a loot table; outside a dungeon a chest is only a town store's depot or a shop counter (use). Indoors and in a dungeon the layout rules hold (a tool's result says any you break as "Layout now"): every room has a use (something in it: a monster, a chest, a sight, a sign, a way on), a chest has a monster near it, no way ends blind for nothing; a change that breaks one can't be accepted. Anywhere, a way in (a spawn point, where a link's way in lands, or a start) keeps 10 cells clear of where a hostile monster stands or roams, so no one arrives inside a fight; the tool's answer warns of one as "Arrivals now". A loot table (place's loot, for a chest or a monster) is rolled as the level is built, the same every time; the tables and what each can give: %s.

Running water is a stream: the stream tool lays its course, from where it rises to where it goes. Give it a ford or a bridge wherever a path meets it, or the far bank is cut off; a bridge needs level banks of floor at both ends.

Levels join at their edges: walking off one edge arrives on the neighbour's opposite edge, at the same row (east, west) or column (north, south). When the area touches the map's edge with nothing beyond it, new_area makes a new level there (its own map; a first draft of grass, groves and forest round it, open where the way arrives) and carves a way out to the edge through the area. Use it when asked for somewhere new beyond the edge ("a new area east", "the woods past here"), not for changes inside the area.

Places are what factions hold (a faction of levels/factions.json, such as the goblins or the town, or nobody): a camp, a keep, a farm, a gate, a mine. Each is a cell and a radius, and some cover ground with cells of their own (mark_place's rect, brazier, lamp, hearth and seats: a watch post's fire basket, a tavern's hearth and benches, the ring round a fire); the ground within the radius is its holder's, and no one else's group may walk through it. mark_place names one (its key, kind, cell, radius, who holds it at the start). A refuge (where a sought newcomer is found) says where it is (mark_place's where); a trader may have his bed and the side he faces, a perch its watch (the cells a hill cat pounces onto from it, 6 cells or more from any road). A name or shown name you write is a draft: it goes to voice when its level is put up to land, never straight into a released level. Mark a place when you build one: a camp's place on its gather point (where its monsters gather), a farmstead's in its yard. A goblin camp can hold captives from the start (mark_place's holds), each taken from a town (the request lists them): someone of that town, or kin of one of its workers ("the smith's daughter"). In town their kin asks players to bring them home, and they go free when the camp falls, so a camp holding a captive is worth clearing. A town's work sites are places too: a woodlot (woods its woodcutter fells: put it at the forest's edge), a hunting ground (open land with game, its hunter's), a quarry (rock to cut stone from), a farm (fields), a mine. Mark one with the town it works for (mark_place's town: the key of the town's stockpile place), held by the town, not far from it, and with a way on foot from the store to it: a site the goblins hold, or that can't be reached, is worked by no one, and the tool's answer says so. %s A woodcutter fells trees standing on a walkable cell beside the forest: a woodlot needs such a cell within its radius. Some prefabs bring their place with them. A solid building (a mound, a barrow's: earth through) stands on flat ground like any, but no one walks its cells but its door, the middle of its front row, and it takes no use; the settings show it, the grid draws its cells as the ground they were. A building prefab is a roofed building players walk into: stamp it whole, door and all, rather than drawing its walls yourself; building lays a kind with its front to a side, its use and town at once. To move something already there (a camp, a post, a building, a lair's den or its door, a way off the level), use move: it carries what belongs to it (a place's cells, a building's walls and what stands in it, a camp's or tavern's place, a link's arrival point); never paint it out and lay it again. Indoors, skylight opens a gap in the roof (a cell and a radius of 1 to 4) that lets the sky's light down on a lair or a chamber; move carries one by its cell. A building can serve a town: set_building gives one in the area a use (%s) and its town, the key of a stockpile place in this level (a place of kind stockpile, held by the town). A town has one building of each use. Stamping over a building drops its use: set it again. town_wall walls a town in: give the rectangle of cells it encloses (its buildings, its store, room to walk) and the wall stands on the edges just outside it, with gates (doors) where roads come in, one in the middle of each side if you name none. One wall per town; it looks as strong as the town has built it (a bank of rubble at first). roof puts a roof over a rectangle of floor of one height that no building covers: a room you walled yourself, or an open shelter (a market stall, a woodshed) on posts at its corners; give it a use and town and it serves the town as a building does. A plot (the request lists those here) is ground the town keeps for a new building: put a new building on an empty plot before anywhere else, whole within it, its door on the plot's street side; and a building that serves a town opens its door onto a street (a road or the paving of a square). The tool's answer says when one doesn't. Players walk with companions: keep every way, corridor and gap between walls, buildings and things at least two cells wide; a doorway is the one cell allowed. The tool's answer names a way one cell wide.

%s

%s

Ground has a height, 0 to 6 (the grid's Heights block, shown when any cell has one). A step of a level or more between two cells is a ledge: a wall to anyone walking, though a body pushed off it falls to the ground below, and higher ground sees over walls. Stairs join one level to the next: a stair climbs to the one cell beside it a level up. A slope is a stair that looks like a ramp of earth: use slopes outdoors (on hills, banks, outcrops) and stairs in and round buildings; hill and stairs make slopes when asked. Rock is bare rock standing out of the ground, walled round: no one walks on or through it. height raises, lowers or sets cells; hill makes a rounded hill of rings a level each, with stairs up the sides asked; stairs puts a stair or a flight onto a ledge or up from flat ground. Whatever stands on raised ground (things, starts, buildings) needs stairs to it, and a building stands on one height: when a change leaves something cut off or a stair climbing nowhere, the tool's answer says so: put it right. Some outdoor levels have their ground shaped in metres (the request says so): there the Heights block is in half metres (0-9, then a, b, c ...), a rise of more than 0.45 m between neighbours is a cliff no one walks, height, hill and stairs are refused (the ground is shaped in the editor), and a building needs ground flat within 0.05 m under it: stamp it where the ground is flat, or stamp it with pad to cut the ground flat under it (the only shaping you do: a house on a hillside sits on a cut pad).

A town keeps what players bring home in its store: a place of kind stockpile that the town holds. Stamp town_store for one (an open yard with its depot, its shop counter and the store's place, all in one), once per town, near the middle of town on open ground reachable from the gate, its counter facing where players will stand. A depot is a chest placed with use depot: what is put in it is banked. A shop counter is a chest placed with use shop: players buy what the town's workers made and sell what it is short of. Either works only inside the town's store, and is never given items. When a change leaves the store wrong, the tool's answer says so: put it right.

Prefabs to stamp (their top-left at a cell, turned 0-3 quarter turns clockwise; their # is void and leaves the map as it was):
%s""" % ["\n".join(monsters), ", ".join(legend), ", ".join(Items.ids()), loot_line(), site_line(), ", ".join(building_uses()), decor_line() + "\n\n" + spot_line(), piece_line(), "\n\n".join(prefabs) if not prefabs.is_empty() else "(none)"]


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
	var decor := PackedStringArray()
	for entry: Variant in doc.config.get("decor", []) if doc.config.get("decor") is Array else []:
		if entry is Array and (entry as Array).size() == 6 and area.grow(MARGIN).has_point(Vector2i(int(entry[0]), int(entry[1]))):
			var step := Vector2i(int(entry[2]), int(entry[3]))
			decor.append("%s at %s%s" % [entry[4], Vector2i(int(entry[0]), int(entry[1])), " (%s)" % side_name(step) if step != Vector2i.ZERO else ""])
	if not decor.is_empty():
		text += "\n\nDecor here: " + ", ".join(decor) + "."
	var spots := spot_words(doc.config)
	if not spots.is_empty():
		text += "\n\nSpots here: " + spots + "."
	if not relief().is_empty():
		text += "\n\nThis level's ground is shaped in metres: the Heights block is in half metres."
	var coded := PackedStringArray()
	for entry: Variant in doc.config.get("buildings", []) if doc.config.get("buildings") is Array else []:
		if entry is Dictionary and entry.has("code"):
			coded.append("%s %s at %s" % [entry["code"], building_name(entry), Level._tile(entry.get("at"))])
	if not coded.is_empty():
		text += "\n\nBuildings in this level, by code (the player may name one so; it is the same entry's \"code\" in the settings): " + ", ".join(coded) + "."
	var plots := PackedStringArray()
	var laid := PackedStringArray()
	for plot: Dictionary in plots_from(doc.config) + laid_plots(doc.config):
		var rect: Rect2i = plot["rect"]
		if area.grow(MARGIN).intersects(rect):
			(laid if plot.has("laid") else plots).append("%s at (%d, %d), %d x %d, its street to the %s" % [plot["key"], rect.position.x, rect.position.y, rect.size.x, rect.size.y, side_name(plot["facing"])])
	if not plots.is_empty():
		text += "\n\nPlots here (ground the town keeps for new buildings): " + ", ".join(plots) + "."
	if not laid.is_empty():
		text += "\n\nPlots the towns laid here themselves as they grew (their buildings rise there on their own): " + ", ".join(laid) + "."
	var unsited := builds_without_site()
	if not unsited.is_empty():
		text += "\n\nBuilds the towns here have in hand with no building marked for them yet (place one, on a plot first, and set_building it to the use): " + "; ".join(unsited) + "."
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
	{"name": "mark_place", "description": "Marks a place factions hold: a cell in the area and a radius of ground round it, held at the start by a faction or nobody, with the ground it covers and its cells (a brazier, a lamp, a hearth, seats) if it has them. A key already used is marked again as given (to shift one with its rect and cells, use move).",
		"input_schema": {"type": "object", "properties": {
			"key": {"type": "string", "description": "lower case letters, digits and _, e.g. \"goblin_camp\""},
			"kind": {"type": "string", "enum": [], "description": "what it is (Level.PLACE_KINDS)"},
			"town": {"type": "string", "description": "a work site only (woodlot, hunting_ground, quarry, farm, mine): the key of the stockpile place here whose town works it"},
			"at": _CELL,
			"radius": {"type": "integer", "minimum": 1, "maximum": 32},
			"holder": {"type": "string", "enum": [], "description": "a faction (levels/factions.json) or nobody"},
			"name": {"type": "string", "description": "optional, how it is called, e.g. \"the old farmstead\": a draft until voice has seen it (it goes to voice when its level is put up to land, never straight into a released level)"},
			"shown": {"type": "string", "description": "optional, the name a player reaching it is shown where its name is a where-phrase (\"the shieling\" for \"a shieling high on the hill\"); a draft as its name is"},
			"where": {"type": "string", "enum": [], "description": "a refuge only, and needed there: where it is, the word the towns say it by"},
			"bed": {"type": "array", "items": {"type": "integer"}, "minItems": 2, "maxItems": 2, "description": "a trader only, optional, [x, y] within its radius: where he sleeps (his bedroll)"},
			"facing": {"type": "string", "enum": ["north", "east", "south", "west"], "description": "a trader only, optional: the side he faces (his fire's)"},
			"watch": {"type": "array", "items": _CELL, "description": "a perch only: the cells within its radius a hill cat pounces onto from it (low grass, kept 6 cells or more from any road)"},
			"rect": {"type": "object", "description": "optional, the ground it covers (a post's 3 x 3, a tavern's room, a fire's ring): top-left x, y, width, height, in the area",
				"properties": _RECT["properties"], "required": _RECT["required"]},
			"brazier": {"type": "array", "items": {"type": "integer"}, "minItems": 2, "maxItems": 2, "description": "optional, [x, y]: a post's fire basket, in its rect (lit at night)"},
			"lamp": {"type": "array", "items": {"type": "integer"}, "minItems": 2, "maxItems": 2, "description": "optional, [x, y]: where a store's lantern stands"},
			"hearth": {"type": "array", "items": {"type": "integer"}, "minItems": 2, "maxItems": 2, "description": "optional, [x, y]: a tavern's hearth, in its rect"},
			"seats": {"type": "array", "items": _CELL, "description": "optional, the cells folk sit on (a tavern's benches, the ring round a fire), in its rect"},
			"mix": {"type": "string", "enum": ["bandit", "trader", "mixed"], "description": "a camp only, at its fire: who keeps it (bandits; traders, held by nobody; or both)"},
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
			"code": {"type": "string", "description": "the building's code (\"H3\"), instead of at"},
			"use": {"type": "string", "description": "what the town does there (the uses are in the system prompt); empty for none"},
			"town": {"type": "string", "description": "the key of a stockpile place in this level; empty for none"}}}},
	{"name": "building", "description": "Builds a building of a kind (the building_<kind>_<size> prefabs) with its top-left at a cell and its front (its door) to a side, given its use and town if it serves one; or, with remove, takes a building away (its record, walls and doors; its floor stays).",
		"input_schema": {"type": "object", "properties": {
			"kind": {"type": "string", "enum": []},
			"size": {"type": "string", "enum": ["small", "large"]},
			"at": _CELL,
			"facing": {"type": "string", "enum": ["north", "east", "south", "west"], "description": "the side its front faces (south if not given)"},
			"use": {"type": "string", "enum": [], "description": "optional, what the town does there"},
			"town": {"type": "string", "description": "optional, the key of a stockpile place here"},
			"name": {"type": "string", "description": "optional, e.g. \"the Drowned Lamb\""},
			"pad": {"type": "boolean", "description": "cut the ground flat under it where it is uneven"},
			"remove": {"type": "boolean", "description": "take away the building with that code or on that cell"},
			"code": {"type": "string", "description": "with remove: the building's code, instead of at"}}}},
	{"name": "move", "description": "Moves one thing with what belongs to it: a place by its key (its rect, brazier, lamp, hearth and seats with it), a building by its code (its walls, doors, floor, what stands in it, and the places on it or beside it: a camp's, a tavern's), or the monster, chest or link on a cell (a lair's den or escort; a way off the level, with the point beside it where folk arrive). Give to (where its cell goes) or by (cells east and south).",
		"input_schema": {"type": "object", "properties": {
			"place": {"type": "string", "description": "a place's key"},
			"building": {"type": "string", "description": "a building's code (\"C1\")"},
			"skylight": _CELL,
			"at": _CELL,
			"to": _CELL,
			"by": {"type": "array", "items": {"type": "integer"}, "minItems": 2, "maxItems": 2, "description": "[x, y]: cells east (+) or west (-), south (+) or north (-)"}}}},
	{"name": "link", "description": "Puts a way off the level at a cell (a cave mouth, a lair's door, a road's end): stepping there takes one to a spawn point in another level; arrive marks where folk from that level arrive here (spawn point from_<level>). Remove takes a way away. Give at and closed alone to shut (true) or open (false) a way already there, keeping where it leads; at and cue alone set how it looks. A cave mouth (cue cave) is a hill of rock drawn on the cells behind the way: keep those rock, open ground in front. The way back is the other level's own link.",
		"input_schema": {"type": "object", "properties": {
			"at": _CELL,
			"to_map": {"type": "string", "description": "the level it leads to"},
			"to_spawn": {"type": "string", "description": "the spawn point there it leads to"},
			"arrive": _CELL,
			"closed": {"type": "boolean", "description": "shut till opened; false opens it"},
			"cue": {"type": "string", "enum": [], "description": "how the way looks (an arch, waystones, a way down or up, sealed, a cave mouth, thicket a way into a bramble mound, den a low hole under a tilted rock shelf, mine a timbered adit cut into a hill of rock); empty: worked out from where it leads"},
			"remove": {"type": "boolean"}},
			"required": ["at"]}},
	{"name": "skylight", "description": "Opens a gap in a cave's roof over a cell (indoors only): the sky's light falls through it on the cells within radius, bright by day, faint by night. A gap already on that cell is replaced; remove closes it.",
		"input_schema": {"type": "object", "properties": {
			"at": _CELL,
			"radius": {"type": "number", "description": "cells its light reaches, 1 to 4 (2 if not given)"},
			"remove": {"type": "boolean"}},
			"required": ["at"]}},
	{"name": "decor", "description": "Sets a piece of decor on a floor cell (the system prompt says each kind): drawn only, never solid, never opened, so players walk through it. A wall piece stands in its cell with its back to the wall on side; a faced piece's front faces side. remove takes away the decor on the cell (of kind, if given).",
		"input_schema": {"type": "object", "properties": {
			"at": _CELL,
			"kind": {"type": "string", "enum": []},
			"side": {"type": "string", "enum": ["north", "east", "south", "west"], "description": "a wall piece: the side of its cell its wall is on (needed); a faced piece: the way its front faces (optional)"},
			"variant": {"type": "integer", "minimum": 1, "description": "the piece's variant (1 if not given)"},
			"remove": {"type": "boolean"}},
			"required": ["at"]}},
	{"name": "spot", "description": "Lays a spot where one townsperson stands, sits or leans (the system prompt says how): its use, the cell its body faces, its pose; a work spot names its trade, a talk spot its pair. A spot on a cell that has one changes it. remove takes away the spot on the cell.",
		"input_schema": {"type": "object", "properties": {
			"at": _CELL,
			"use": {"type": "string", "enum": []},
			"face": _CELL,
			"pose": {"type": "string", "enum": [], "description": "stand when not given"},
			"trade": {"type": "string", "description": "a work spot's trade (cook, smith, ...)"},
			"pair": {"type": "string", "description": "a talk spot's pair: the two spots of a pair share it and face each other"},
			"town": {"type": "string", "description": "the town's place key (its store's); the town whose ground holds the cell when not given"},
			"remove": {"type": "boolean"}},
			"required": ["at"]}},
	{"name": "piece", "description": "Lays a standing piece with no walls or roof (the system prompt says each kind) with its top-left at a cell and its front to a side: solid, no one walks its cells. remove takes away the piece standing on a cell.",
		"input_schema": {"type": "object", "properties": {
			"at": _CELL,
			"kind": {"type": "string", "enum": []},
			"facing": {"type": "string", "enum": ["north", "east", "south", "west"], "description": "the side its front faces (south if not given)"},
			"variant": {"type": "integer", "minimum": 1},
			"carved": {"type": "string", "description": "a milestone only, and needed: where its road goes, cut in its face (a level, a town or a named place players can reach), up to 24 letters; a draft until voice has seen it"},
			"arrow": {"type": "string", "enum": [], "description": "a milestone only, optional: the way the carved arrow points, as one reading its front sees it"},
			"remove": {"type": "boolean"}},
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
	if tool in UNCUT_TOOLS:
		return _run_tool(tool, input)
	var before := reached()
	var last: Variant = working.undo_steps.back() if not working.undo_steps.is_empty() else null
	var out := _run_tool(tool, input)
	var changed := not working.undo_steps.is_empty() and not is_same(working.undo_steps.back(), last)
	if changed and not out.get("ok", false):
		_reached = {}
	elif changed:
		# Ground the edit cut off from every start and arrival (844): the edit undone, said in words.
		_reached = {}
		var after := reached()
		# Cut off: walkable still, reached before and not now; the edit's own cells (now solid) are not.
		var ground := flood_ground()
		var lost := before.keys().filter(func(cell: Vector2i) -> bool: return not after.has(cell) and HeightTools._walks(working.map, ground, cell))
		if not lost.is_empty():
			while not working.undo_steps.is_empty() and not is_same(working.undo_steps.back(), last):
				working.undo()
			working.redo_steps.clear()
			_reached = before
			return _no("that would cut off %s from the level's starts and arrivals: leave a way through (a longer way round is fine)" % cut_off_words(lost))
	# A building it made gets its code now, for the next tool and the answer (decision 537).
	if Level.fill_codes(working.config):
		working.revision += 1
	return out


func _run_tool(tool: String, input: Variant) -> Dictionary:
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
		"building":
			return _building(given)
		"move":
			return _move(given)
		"link":
			return _link(given)
		"skylight":
			return _skylight(given)
		"decor":
			return _decor(given)
		"spot":
			return _spot(given)
		"piece":
			return _piece(given)
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
	if kind == "stall":
		return _no(STALL_SAYS + ": lay a market_stall with piece, dressing only")
	if kind not in Level.PLACE_KINDS:
		return _no("kind is one of %s" % ", ".join(Level.PLACE_KINDS))
	if not Factions.read().has(holder):
		return _no("holder is a faction (%s) or nobody" % ", ".join(Factions.read().names()))
	var shape: Variant = _shape_of(given)
	if shape is String:
		return _no(shape)
	var places: Dictionary = (working.config["places"] as Dictionary).duplicate(true) if working.config.get("places") is Dictionary else {}
	if places.get(key) is Dictionary and str(places[key].get("kind", "")) == "stall":
		return _no("%s is a stall place, where its town's seller stands: %s, and builder mode changes none" % [key, STALL_SAYS])
	var place := {"at": [at.x, at.y], "kind": kind, "radius": clampi(int(given.get("radius", Level.PLACE_RADIUS)), 1, 32), "holder": holder}
	place.merge(shape)
	if given.has("mix"):
		# A forest camp's keepers (maps' fill_forest): bandit, trader or mixed.
		if kind != "camp" or str(given["mix"]) not in CAMP_MIXES:
			return _no("mix is for a camp only: %s" % ", ".join(CAMP_MIXES))
		place["mix"] = str(given["mix"])
	# A refuge says where it is (613 amended; Level.places_from warns on one without).
	var where := str(given.get("where", "")).strip_edges()
	if kind == "refuge" and where not in Level.REFUGE_WHERE:
		return _no("a refuge needs where: one of %s" % ", ".join(Level.REFUGE_WHERE))
	if kind != "refuge" and not where.is_empty():
		return _no("where is for a refuge only")
	if kind == "refuge":
		place["where"] = where
	if given.has("name"):
		place["name"] = str(given["name"])
	if not str(given.get("shown", "")).strip_edges().is_empty():
		place["shown"] = str(given["shown"]).strip_edges()
	var own: Variant = _own_cells(given, kind, at, int(place["radius"]))
	if own is String:
		return _no(own)
	place.merge(own)
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
	var kept: Array[String] = []
	if again and places[key] is Dictionary:
		for field: String in KEPT_FIELDS:
			if (places[key] as Dictionary).has(field):
				place[field] = places[key][field]
				kept.append(field)
	places[key] = place
	working.apply_changes({"config": {"places": places}})
	var text := "%s the place %s: a %s at %s, radius %d, held by %s%s" % ["changed" if again else "marked", key, kind, at, place["radius"], holder,
		", holding %d captives" % (place["holds"] as Array).size() if place.has("holds") else ""] \
		+ (", worked by the town of %s" % town if place.has("town") else "")
	if not kept.is_empty():
		text += "; kept its %s" % ", ".join(kept)
	if place.has("name") or place.has("shown"):
		text += "; its name is a draft until voice has seen it"
	var by_road := _watch_by_road(place.get("watch", []))
	if not by_road.is_empty():
		text += "; the watch cells %s lie less than %d cells from a road: a hill cat's watch keeps off the ways folk walk" % [", ".join(by_road.map(func(cell: Vector2i) -> String: return str(cell))), WATCH_OFF_ROAD]
	return {"ok": true, "text": text}


## A trader's bed and facing and a perch's watch from [param given] (792
## amended (2); Level.PLACE_SHAPES: bed a cell, facing a step, watch cells),
## each on its own kind only, the cells in the area, on ground and within
## [param radius] of [param at]; else what is wrong.
func _own_cells(given: Dictionary, kind: String, at: Vector2i, radius: int) -> Variant:
	var out := {}
	for field: String in ["bed", "facing", "watch"]:
		if not given.has(field):
			continue
		var owner := "perch" if field == "watch" else "trader"
		if kind != owner:
			return "%s is for a %s only" % [field, owner]
		if field == "facing":
			if not SIDES.has(str(given["facing"])):
				return "facing is one of %s" % ", ".join(SIDES.keys())
			var step: Vector2i = SIDES[str(given["facing"])]
			out["facing"] = [step.x, step.y]
			continue
		if field == "watch" and (not given["watch"] is Array or (given["watch"] as Array).size() > MAX_WATCH):
			return "watch is a list of up to %d cells" % MAX_WATCH
		var cells: Array = []
		for value: Variant in (given[field] if field == "watch" else [given[field]]):
			var cell: Variant = Level._tile(value)
			if cell == null:
				return "%s is [x, y]" % ("each watch cell" if field == "watch" else field)
			if not area.has_point(cell):
				return "the %s %s is outside the area" % [field, cell]
			if working.map.cell(cell) in ["void", "water"]:
				return "the %s %s is %s: it lies on ground" % [field, cell, working.map.cell(cell)]
			if (cell - at).length_squared() > radius * radius:
				return "the %s %s is beyond the place's radius %d of %s" % [field, cell, radius, at]
			cells.append([cell.x, cell.y])
		out[field] = cells if field == "watch" else cells[0]
	return out


## Of [param watch] (a perch's [x, y] cells), those less than WATCH_OFF_ROAD
## from a road's cell (level.json's "roads", decision 559).
func _watch_by_road(watch: Variant) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not watch is Array or (watch as Array).is_empty():
		return out
	var roads: Dictionary = {}
	for road: Dictionary in Curves.parse(working.config, "roads", [] as Array[String]):
		roads.merge(Curves.cells(road["curve"], false))
	for value: Variant in watch:
		var cell: Variant = Level._tile(value)
		if cell == null:
			continue
		for road_cell: Variant in roads:
			if road_cell is Vector2i and maxi(absi(road_cell.x - cell.x), absi(road_cell.y - cell.y)) < WATCH_OFF_ROAD:
				out.append(cell)
				break
	return out


## A place's shape fields from [param given] (792; buildings' 774 reads them,
## Level.places_from): {rect: [x, y, w, h], brazier, lamp, hearth: [x, y],
## seats: [[x, y], ...]}, those given, each in the area on ground and the
## brazier, hearth and seats in the rect if there is one; else what is wrong.
func _shape_of(given: Dictionary) -> Variant:
	var out := {}
	var rect: Variant = null
	if given.has("rect"):
		var value: Variant = given["rect"]
		rect = Rect2i(int(value[0]), int(value[1]), int(value[2]), int(value[3])) if value is Array and (value as Array).size() == 4 else _rect(value)
		if rect == null or rect.size.x < 1 or rect.size.y < 1:
			return "rect needs x, y, w and h"
		if not area.encloses(rect):
			return "the rect %s is not all in the area" % [rect]
		out["rect"] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	for field: String in SHAPE_CELLS:
		if not given.has(field):
			continue
		var listed: Array = given[field] if field == "seats" and given[field] is Array else [given[field]]
		if field == "seats" and (not given[field] is Array or listed.size() > MAX_SEATS):
			return "seats is a list of up to %d cells" % MAX_SEATS
		var cells: Array = []
		for value: Variant in listed:
			var cell: Variant = Level._tile(value)
			if cell == null:
				return "%s is [x, y]" % ("each seat" if field == "seats" else field)
			if not area.has_point(cell):
				return "the %s %s is outside the area" % [field.trim_suffix("s"), cell]
			if working.map.cell(cell) in ["void", "water"]:
				return "the %s %s is %s: it stands on ground" % [field.trim_suffix("s"), cell, working.map.cell(cell)]
			if rect != null and field != "lamp" and not rect.has_point(cell):
				return "the %s %s is outside the rect %s" % [field.trim_suffix("s"), cell, rect]
			cells.append([cell.x, cell.y])
		out[field] = cells if field == "seats" else cells[0]
	return out


## [param place] (a level.json "places" entry) moved [param by]: its cell,
## rect and shape cells together (792), and a trader's bed, a lair's den and
## a perch's watch (792 amended (2)).
static func _place_moved(place: Dictionary, by: Vector2i) -> Dictionary:
	var out := place.duplicate(true)
	var at: Variant = Level._tile(place.get("at"))
	if at != null:
		out["at"] = [at.x + by.x, at.y + by.y]
	if place.get("rect") is Array and (place["rect"] as Array).size() == 4:
		out["rect"] = [int(place["rect"][0]) + by.x, int(place["rect"][1]) + by.y, int(place["rect"][2]), int(place["rect"][3])]
	for field: String in MOVED_CELLS:
		var cells: Array = place[field] if field in LIST_CELLS and place.get(field) is Array else [place.get(field)]
		var moved: Array = []
		for value: Variant in cells:
			var cell: Variant = Level._tile(value)
			if cell != null:
				moved.append([cell.x + by.x, cell.y + by.y])
		if place.has(field) and not moved.is_empty():
			out[field] = moved if field in LIST_CELLS else moved[0]
	return out


## The building tool (792): a kind building (levels/buildings.json) laid
## with its front to a side, its use and town given, or one taken away.
func _building(given: Dictionary) -> Dictionary:
	if bool(given.get("remove", false)):
		return _unbuild(given)
	var kind := str(given.get("kind", ""))
	var size := str(given.get("size", Level.KIND_SIZE))
	var at: Variant = Level._tile(given.get("at"))
	var facing := str(given.get("facing", "south"))
	if not Level.kinds().has(kind) or at == null:
		return _no("building needs a kind (%s) and at: [x, y], its top-left cell" % ", ".join(Level.kinds().keys()))
	if not (Level.kinds()[kind].get("sizes", {}) as Dictionary).has(size):
		return _no("a %s comes in %s" % [kind, ", ".join((Level.kinds()[kind].get("sizes", {}) as Dictionary).keys())])
	if not KIND_TURNS.has(facing):
		return _no("facing is north, east, south or west")
	var before := working.undo_steps.size()
	var stamped := _run_tool("stamp", {"prefab": "%s%s_%s" % [Prefab.KIND_PREFIX, kind, size], "at": [at.x - 1, at.y - 1],
		"turns": KIND_TURNS[facing], "pad": bool(given.get("pad", false))})
	if not stamped.get("ok", false):
		return stamped
	var buildings: Array = working.config.get("buildings", [])
	var index := buildings.find_custom(func(entry: Variant) -> bool:
		return entry is Dictionary and str(entry.get("kind", "")) == kind and Level.building_blocks(entry).any(func(rect: Rect2i) -> bool: return rect.has_point(at)))
	if index < 0:
		return stamped
	var said := "a %s %s at %s, its front %s" % [size, kind, at, facing]
	if not str(given.get("use", "")).is_empty() or not str(given.get("town", "")).is_empty():
		var served := _set_building({"at": [at.x, at.y], "use": str(given.get("use", "")), "town": str(given.get("town", ""))})
		if not served.get("ok", false):
			while working.undo_steps.size() > before:
				working.undo()
			return served
		said += "; " + str(served["text"])
	if given.has("name"):
		var named: Array = (working.config["buildings"] as Array).duplicate(true)
		named[index]["name"] = str(given["name"])
		working.apply_changes({"config": {"buildings": named}})
	return {"ok": true, "text": "built " + said}


## A building taken away (792): its record, and the walls and doors on its
## cells' sides; its floor and what stands in it stay.
func _unbuild(given: Dictionary) -> Dictionary:
	var index: Variant = _building_index(given)
	if index is String:
		return _no(index)
	var buildings: Array = (working.config["buildings"] as Array).duplicate(true)
	var entry: Dictionary = buildings[index]
	var edges: Dictionary[Vector3i, String] = {}
	for cell: Vector2i in Level._union(Level.building_blocks(entry)):
		if not area.has_point(cell):
			return _no("the %s at %s is not all in the area" % [building_name(entry), entry.get("at")])
		for side: Vector2i in SIDES.values():
			edges[Terrain.edge_key(cell, side)] = "clear"
	buildings.remove_at(index)
	return _lay({"edges": edges, "covers": [], "config": {"buildings": buildings}},
		"took away the %s at %s (its floor stays; a place of it, a tavern's, stays where it was: move or mark it)" % [building_name(entry), entry.get("at")])


## The index in the working buildings of the one [param given] names by its
## code or a cell of it, in the area; else what is wrong.
func _building_index(given: Dictionary) -> Variant:
	var buildings: Array = working.config.get("buildings", []) if working.config.get("buildings") is Array else []
	var code := str(given.get("code", given.get("building", ""))).strip_edges().to_upper()
	var at: Variant = Level._tile(given.get("at"))
	var index := -1
	if not code.is_empty():
		index = buildings.find_custom(func(entry: Variant) -> bool: return entry is Dictionary and str(entry.get("code", "")) == code)
		if index < 0:
			return "no building here is %s (the request lists the level's buildings)" % code
	elif at != null:
		index = buildings.find_custom(func(entry: Variant) -> bool:
			return Level.building_blocks(entry).any(func(rect: Rect2i) -> bool: return rect.has_point(at)))
		if index < 0:
			return "no building stands on %s" % [at]
	else:
		return "name the building by its code or at: [x, y], a cell of it"
	var cell: Variant = Level._tile(buildings[index].get("at"))
	if cell == null or not area.has_point(cell):
		return "the %s at %s is outside the area" % [building_name(buildings[index]), buildings[index].get("at")]
	return index


## The move tool (792): a place by its key, a building by its code, or the
## thing (a monster, its den or escort; a chest) or the link on a cell,
## shifted by [x, y] or to a cell, with what belongs to it: a place's rect
## and cells; a building's walls, doors, floor, what stands in it and the
## places on or beside it (a camp's, a tavern's); a link's arrival point.
func _move(given: Dictionary) -> Dictionary:
	var from: Variant = null
	var what := ""
	var places: Dictionary = working.config.get("places", {}) if working.config.get("places") is Dictionary else {}
	if given.has("place"):
		what = "place"
		if not places.has(str(given["place"])) or not places[str(given["place"])] is Dictionary:
			return _no("no place %s here (there are: %s)" % [given["place"], ", ".join(places.keys())])
		from = Level._tile(places[str(given["place"])].get("at"))
	elif given.has("building"):
		what = "building"
		var index: Variant = _building_index(given)
		if index is String:
			return _no(index)
		from = Level._tile((working.config["buildings"] as Array)[index].get("at"))
	elif given.has("skylight"):
		what = "skylight"
		from = Level._tile(given["skylight"])
		if from == null or _skylight_index(from) < 0:
			return _no("no skylight is at %s" % [given["skylight"]])
	else:
		from = Level._tile(given.get("at"))
		if from == null:
			return _no("move names a place, a building (its code) or at: [x, y], the cell of a thing or a link")
		what = "thing" if not working.entry_of(from).is_empty() or _is_thing(working.map.cell(from)) else \
				("link" if not working.link_of(from).is_empty() else "building")
	if from == null:
		return _no("it has no cell to move from")
	var to: Variant = Level._tile(given.get("to"))
	var by: Variant = Level._tile(given.get("by"))
	if to == null and by == null:
		return _no("move needs to: [x, y] or by: [x, y], the cells east (+x) and south (+y)")
	var delta: Vector2i = by if to == null else to - from
	if delta == Vector2i.ZERO:
		return _no("it is there already")
	match what:
		"place":
			return _move_place(str(given["place"]), delta)
		"thing":
			return _move_thing(from, delta)
		"link":
			return _move_link(from, delta)
		"skylight":
			return _move_skylight(from, delta)
	return _move_building(given if given.has("building") else {"at": [from.x, from.y]}, delta)


## Whether map meaning [param meaning] is a thing on a cell (a monster, a
## chest...), not ground.
func _is_thing(meaning: String) -> bool:
	return meaning.begins_with("monster_") or meaning in things(working.config).values() and meaning not in GROUNDS


## The ground a thing moved off [param cell] leaves: what most of its
## sides are, else grass outdoors and stone in.
func _ground_near(cell: Vector2i) -> String:
	var counts := {}
	for side: Vector2i in SIDES.values():
		var meaning := working.map.cell(cell + side)
		if meaning in WALKED:
			counts[meaning] = int(counts.get(meaning, 0)) + 1
	var best := "grass" if bool(working.config.get("outdoor", false)) else "stone"
	for meaning: String in counts:
		if int(counts[meaning]) > int(counts.get(best, 0)):
			best = meaning
	return best


## Why [param cell] can't take what is moved there, or "".
func _cant_take(cell: Vector2i, own: Array = []) -> String:
	if not area.has_point(cell):
		return "%s is outside the area" % [cell]
	if cell not in own and holds_thing(cell):
		return "%s holds %s already" % [cell, held_words(cell)]
	if working.map.cell(cell) not in WALKED and cell not in own:
		return "%s is %s: it goes on ground" % [cell, working.map.cell(cell)]
	if cell not in own and not working.link_of(cell).is_empty():
		return "%s is %s already" % [cell, way_words(working.link_of(cell))]
	return ""


func _move_place(key: String, delta: Vector2i) -> Dictionary:
	var places: Dictionary = (working.config["places"] as Dictionary).duplicate(true)
	if str(places[key].get("kind", "")) == "stall":
		return _no("%s is a stall place, where its town's seller stands: moving it is economy's, not builder mode's" % key)
	var moved := _place_moved(places[key], delta)
	var at: Vector2i = Level._tile(moved["at"])
	if not area.has_point(at) or working.map.cell(at) in ["void", "water"]:
		return _no("%s is %s: a place stands on ground in the area" % [at, "outside the area" if not area.has_point(at) else working.map.cell(at)])
	var shape: Variant = _shape_of(moved)
	if shape is String:
		return _no(shape)
	places[key] = moved
	working.apply_changes({"config": {"places": places}})
	return {"ok": true, "text": "moved the place %s to %s%s" % [key, at, " with its %s" % ", ".join(shape.keys()) if not shape.is_empty() else ""]}


func _move_thing(from: Vector2i, delta: Vector2i) -> Dictionary:
	var to := from + delta
	var wrong := _cant_take(to)
	if not wrong.is_empty():
		return _no(wrong)
	var meaning := working.map.cell(from)
	var entry := working.entry_of(from).duplicate(true)
	var changes := {"cells": {from: _ground_near(from), to: meaning}, "covers": [from, to]}
	if not entry.is_empty():
		entry["at"] = [to.x, to.y]
		changes["entries"] = [entry]
	return _lay(changes, "moved the %s from %s to %s" % [meaning.trim_prefix("monster_"), from, to])


func _move_link(from: Vector2i, delta: Vector2i) -> Dictionary:
	var to := from + delta
	var wrong := _cant_take(to)
	if not wrong.is_empty():
		return _no(wrong)
	var link := working.link_of(from).duplicate(true)
	link["at"] = [to.x, to.y]
	var changes := {"cells": {}, "covers": [from], "links": [link]}
	var said := "moved the way to %s from %s to %s" % [link.get("to_map", "?"), from, to]
	# Its arrival point beside it (from_<the level it leads to>) goes with it.
	var spawns: Dictionary = (working.config["spawn_points"] as Dictionary).duplicate(true) if working.config.get("spawn_points") is Dictionary else {}
	var arrival := "from_" + str(link.get("to_map", ""))
	var landing: Variant = Level._tile(spawns.get(arrival))
	if landing != null and (landing - from).length() <= ARRIVAL_NEAR:
		var moved: Vector2i = landing + delta
		var bad := _cant_take(moved)
		if not bad.is_empty():
			return _no("its arrival point %s would move to %s: %s" % [arrival, moved, bad])
		spawns[arrival] = [moved.x, moved.y]
		changes["config"] = {"spawn_points": spawns}
		said += ", and %s (where they arrive from %s) to %s" % [arrival, link.get("to_map", "?"), moved]
	return _lay(changes, said + "; the other level's way here still leads to its spawn")


func _move_building(named: Dictionary, delta: Vector2i) -> Dictionary:
	var index: Variant = _building_index(named)
	if index is String:
		return _no(index)
	var buildings: Array = (working.config["buildings"] as Array).duplicate(true)
	var entry: Dictionary = buildings[index]
	var old: Array[Vector2i] = Level._union(Level.building_blocks(entry))
	var moved := entry.duplicate(true)
	var at: Vector2i = Level._tile(entry["at"])
	moved["at"] = [at.x + delta.x, at.y + delta.y]
	var new: Array[Vector2i] = Level._union(Level.building_blocks(moved))
	var others: Dictionary[Vector2i, bool] = {}
	for other: Variant in buildings:
		if other != entry:
			for cell: Vector2i in Level._union(Level.building_blocks(other)):
				others[cell] = true
	for cell: Vector2i in new:
		var wrong := _cant_take(cell, old)
		if wrong.is_empty() and others.has(cell):
			wrong = "%s is another building's" % [cell]
		if not wrong.is_empty():
			return _no("the %s would stand on %s" % [building_name(entry), wrong])
	var cells: Dictionary[Vector2i, String] = {}
	var edges: Dictionary[Vector3i, String] = {}
	var entries: Array = []
	var floor := _ground_near(old[0]) if not old.is_empty() else "grass"
	for cell: Vector2i in old:
		if _is_thing(working.map.cell(cell)):
			cells[cell] = floor
		for side: Vector2i in SIDES.values():
			edges[Terrain.edge_key(cell, side)] = "clear"
	for cell: Vector2i in old:
		cells[cell + delta] = working.map.cell(cell)
		for side: Vector2i in SIDES.values():
			edges[Terrain.edge_key(cell + delta, side)] = working.map.edge(Terrain.edge_key(cell, side))
		var stands := working.entry_of(cell).duplicate(true)
		if not stands.is_empty():
			stands["at"] = [cell.x + delta.x, cell.y + delta.y]
			entries.append(stands)
	buildings[index] = moved
	var uneven := pad_problem(moved)
	if not uneven.is_empty():
		return _no(uneven)
	# The places on it or beside it (a camp's fire, a tavern's counter) go with it.
	var places: Dictionary = (working.config["places"] as Dictionary).duplicate(true) if working.config.get("places") is Dictionary else {}
	var rect: Rect2i = Level.building_rect(entry)
	var carried: Array[String] = []
	for key: String in places:
		var place_at: Variant = Level._tile(places[key].get("at")) if places[key] is Dictionary else null
		if place_at != null and rect.grow(1).has_point(place_at):
			if str(places[key].get("kind", "")) == "stall":
				return _no("moving it would carry the stall place %s, where its town's seller stands: moving that is economy's, not builder mode's" % key)
			places[key] = _place_moved(places[key], delta)
			carried.append(key)
	var config := {"buildings": buildings}
	if not carried.is_empty():
		config["places"] = places
	var covers: Array = old.duplicate()
	covers.append_array(new)
	return _lay({"cells": cells, "edges": edges, "entries": entries, "covers": covers, "config": config},
		"moved the %s from %s to %s%s" % [building_name(entry), entry["at"], moved["at"], " with the place %s" % ", ".join(carried) if not carried.is_empty() else ""])


## The link tool (792): a way off this level at a cell (to a level's spawn
## point), and where folk from there arrive here; or one taken away.
func _link(given: Dictionary) -> Dictionary:
	var at: Variant = Level._tile(given.get("at"))
	if at == null:
		return _no("link needs at: [x, y]")
	if bool(given.get("remove", false)):
		if working.link_of(at).is_empty():
			return _no("no way off the level is at %s" % [at])
		return _lay({"cells": {}, "covers": [at]}, "took away the way to %s at %s (its arrival point stays)" % [working.link_of(at).get("to_map", "?"), at])
	var there := working.link_of(at)
	var cue := str(given.get("cue", ""))
	if cue != "" and cue not in Level.CUES:
		return _no("a way's cue is one of %s, or empty to work it out" % ", ".join(Level.CUES))
	if not given.has("to_map") and (given.has("closed") or given.has("cue")) and not there.is_empty():
		# Shut, opened or its look set where it stands, still leading where it led.
		var turned := there.duplicate(true)
		var said: Array[String] = []
		if given.has("closed"):
			turned.erase("closed")
			if bool(given["closed"]):
				turned["closed"] = true
			said.append("shut" if bool(given["closed"]) else "opened")
		if given.has("cue"):
			turned.erase("cue")
			if cue != "":
				turned["cue"] = cue
			said.append("gave a %s look to" % cue if cue != "" else "left the look worked out for")
		return _lay({"cells": {}, "covers": [at], "links": [turned]},
			"%s the way to %s at %s" % [" and ".join(said), there.get("to_map", "?"), at])
	var to_map := str(given.get("to_map", ""))
	var to_spawn := str(given.get("to_spawn", ""))
	if not Level.exists(to_map) or to_spawn.is_empty():
		return _no("link needs to_map, a level, and to_spawn, a spawn point there")
	var spawns_there: Variant = _spawn_points_of(to_map)
	if spawns_there is Dictionary and not (spawns_there as Dictionary).has(to_spawn):
		return _no("%s has no spawn point %s (it has: %s)" % [to_map, to_spawn, ", ".join((spawns_there as Dictionary).keys())])
	var wrong := _cant_take(at, [at] if not working.link_of(at).is_empty() else [])
	if not wrong.is_empty():
		return _no(wrong)
	# A way laid again keeps what else it had (its cue), and stays shut
	# unless closed says otherwise.
	var link := there.duplicate(true)
	link.merge({"at": [at.x, at.y], "to_map": to_map, "to_spawn": to_spawn}, true)
	if given.has("closed"):
		link.erase("closed")
		if bool(given["closed"]):
			link["closed"] = true
	if given.has("cue"):
		link.erase("cue")
		if cue != "":
			link["cue"] = cue
	var changes := {"cells": {}, "covers": [at], "links": [link]}
	var said := "a way to %s (%s) at %s" % [to_map, to_spawn, at]
	if given.has("arrive"):
		var arrive: Variant = Level._tile(given["arrive"])
		if arrive == null:
			return _no("arrive is [x, y]")
		var bad := _cant_take(arrive, [arrive])
		if not bad.is_empty():
			return _no("arrive: " + bad)
		var spawns: Dictionary = (working.config["spawn_points"] as Dictionary).duplicate(true) if working.config.get("spawn_points") is Dictionary else {}
		spawns["from_" + to_map] = [arrive.x, arrive.y]
		changes["config"] = {"spawn_points": spawns}
		said += ", and from_%s at %s where folk from there arrive" % [to_map, arrive]
	return _lay(changes, said + "; the way back is %s's own link to from_%s" % [to_map, map_name])


## The skylight tool (792, for 797's "skylights"): a gap in the roof over a
## cell, indoors only, its radius within Level.SKYLIGHT_RADIUS; one per cell.
func _skylight(given: Dictionary) -> Dictionary:
	var at: Variant = Level._tile(given.get("at"))
	if at == null:
		return _no("skylight needs at: [x, y]")
	var skylights: Array = (working.config["skylights"] as Array).duplicate(true) if working.config.get("skylights") is Array else []
	var index := _skylight_index(at)
	if bool(given.get("remove", false)):
		if index < 0:
			return _no("no skylight is at %s" % [at])
		skylights.remove_at(index)
		return _lay({"cells": {}, "config": {"skylights": skylights}}, "closed the gap in the roof at %s" % [at])
	if Level.zone_of(working.config) == "outdoors":
		return _no("a skylight is a gap in a roof: this level is outdoors, where the sky lights every cell")
	var wrong := _skylight_cell(at)
	if not wrong.is_empty():
		return _no(wrong)
	var radius := float(given.get("radius", 2.0))
	if radius < Level.SKYLIGHT_RADIUS.x or radius > Level.SKYLIGHT_RADIUS.y:
		return _no("a skylight's radius is %d to %d cells" % [Level.SKYLIGHT_RADIUS.x, Level.SKYLIGHT_RADIUS.y])
	var gap := {"at": [at.x, at.y], "radius": radius}
	if index >= 0:
		skylights[index] = gap
	else:
		skylights.append(gap)
	return _lay({"cells": {}, "config": {"skylights": skylights}}, "opened a gap in the roof at %s, its light reaching %s cells" % [at, radius])


## Why cell [param cell] can't take a skylight, or "".
func _skylight_cell(cell: Vector2i) -> String:
	if not area.has_point(cell):
		return "%s is outside the area" % [cell]
	if working.map.cell(cell) in ["void", "wall"]:
		return "%s is %s: a skylight lights a floor" % [cell, working.map.cell(cell)]
	return ""


## The index in level.json's "skylights" of the one at [param cell], or -1.
func _skylight_index(cell: Vector2i) -> int:
	var skylights: Variant = working.config.get("skylights")
	if not skylights is Array:
		return -1
	for i: int in (skylights as Array).size():
		var entry: Variant = skylights[i]
		if entry is Dictionary and Level._tile(entry.get("at")) == cell:
			return i
	return -1


func _move_skylight(from: Vector2i, delta: Vector2i) -> Dictionary:
	var to := from + delta
	var wrong := _skylight_cell(to)
	if not wrong.is_empty():
		return _no(wrong)
	if _skylight_index(to) >= 0:
		return _no("a skylight is at %s already" % [to])
	var skylights: Array = (working.config["skylights"] as Array).duplicate(true)
	skylights[_skylight_index(from)]["at"] = [to.x, to.y]
	return _lay({"cells": {}, "config": {"skylights": skylights}}, "moved the gap in the roof from %s to %s" % [from, to])


## Level [param other]'s spawn points as its level.json lists them, or null
## when it has no file to read (a level registered in memory).
static func _spawn_points_of(other: String) -> Variant:
	var path := Level.folder_of(other) + "level.json"
	if not FileAccess.file_exists(path):
		return null
	var read: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return read.get("spawn_points", {}) if read is Dictionary and read.get("spawn_points") is Dictionary else {}


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


## A building entry's name in words (decision 537): its kind, else its
## slot's ("house", "healers hut").
static func building_name(entry: Variant) -> String:
	if not entry is Dictionary:
		return "building"
	return str(entry.get("kind", str(entry.get("slot", "building")).trim_prefix("building."))).replace("_", " ")


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


## The ground as HeightTools walks it: relief() and "solid", each solid
## building's cells but its door (Level.SOLID, maps' 550: a mound is earth
## through, its door the front row's middle; a doorless one, 567, every
## cell), which the map still paints as floor.
func walk_ground() -> Dictionary:
	var out := relief()
	var solid: Dictionary[Vector2i, bool] = {}
	for entry: Variant in working.config.get("buildings", []) if working.config.get("buildings") is Array else []:
		if not entry is Dictionary or str(entry.get("slot", "")) not in Level.SOLID:
			continue
		var rect: Variant = Level.building_rect(entry)
		if rect == null:
			continue
		for cell in Level.rect_cells(rect):
			if cell != solid_door(entry):
				solid[cell] = true
	if not solid.is_empty():
		out["solid"] = solid
	return out


## A solid building entry's door cell (Level.solid_door_of, _lay_solid's
## own), Level.NO_DOOR for a doorless one (567).
static func solid_door(entry: Dictionary) -> Vector2i:
	return Level.solid_door_of(entry)


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
	var code := str(given.get("code", "")).strip_edges().to_upper()
	if not code.is_empty():
		var named: Array = (working.config.get("buildings", []) as Array).filter(func(entry: Variant) -> bool: return entry is Dictionary and str(entry.get("code", "")) == code)
		if named.is_empty():
			return _no("no building here is %s (the request lists the level's buildings)" % code)
		at = Level._tile(named[0].get("at"))
	if at == null:
		return _no("set_building needs at: [x, y], a cell of the building, or its code")
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
	if not use.is_empty() and str(buildings[index].get("slot", "")) in Level.SOLID:
		return _no("the %s at %s is solid (earth through, a door into what lies under it): it has no inside for a use" % [
			building_name(buildings[index]), buildings[index].get("at")])
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
	var before: Array = parsed_of(working)["warnings"]
	working.apply_changes({"config": {"roofs": roofs}})
	var parsed := parsed_of(working)
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
	var before: Array = parsed_of(working)["warnings"]
	var laid := _lay({"cells": cells, "config": config}, "a stream, %d wide, %d cells from %s to %s%s%s" % [width, middle.size(), middle[0], middle[-1],
		", %d fords" % fords if fords > 0 else "", ", %d bridges" % bridges if bridges > 0 else ""])
	var new := (parsed_of(working)["warnings"] as Array).filter(func(warning: String) -> bool: return warning not in before)
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
	if is_apex(thing):
		return _no("%s is one of a kind, with a lair of its own: builder mode never places one" % str(Monster.kinds()[thing].get("label", thing)).to_lower())
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
	if meaning == "chest" and not given.has("use"):
		var wrong := chest_problem(working.config, entry)
		if not wrong.is_empty():
			return _no(wrong)
	var changes := {"cells": {at: meaning}, "covers": [at]}
	if entry.size() > 1:
		changes["entries"] = [entry]
	if not working.map.colours.has(meaning):
		# A kind past Level.LEGEND: level.json's legend gives it a colour, so layout.png holds it.
		var legend: Dictionary = (working.config["legend"] as Dictionary).duplicate() if working.config.get("legend") is Dictionary else {}
		legend[meaning] = "#" + kind_colour(meaning, working.map.colours.values()).to_html(false)
		changes["config"] = {"legend": legend}
	return _lay(changes, "placed %s at %s" % [thing, at])


## Whether level.json [param config] is a dungeon's (Jeff's chest rule, 806):
## dungeon's own test, a depth below ground or a regenerate block.
static func is_dungeon(config: Dictionary) -> bool:
	return int(config.get("depth", 0)) > 0 or config.get("regenerate") is Dictionary


## Why a loot chest [param entry] can't go in the level [param config] is
## for, or "" (Jeff's chest rule, 806): only in a dungeon, and never empty:
## items, a loot table of its own, or the level's chest loot. A depot's or a
## shop counter's chest (a use) is spared.
static func chest_problem(config: Dictionary, entry: Dictionary) -> String:
	if not is_dungeon(config):
		return "a chest of loot goes only in a dungeon (a level below ground or one that regenerates); here a chest is a town store's depot or a shop counter (use)"
	var slots: Array = entry.get("props", {}).get("slots", []) if entry.get("props") is Dictionary else []
	var level_loot: Variant = config.get("loot")
	if slots.any(func(id: Variant) -> bool: return id != null and str(id) != "") or entry.has("loot") \
			or (level_loot is Dictionary and level_loot.has("chest")):
		return ""
	return "a chest must hold something: give it items or a loot table"


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
	var ground := walk_ground()
	for key: String in places:
		var town := str(places[key].get("town", ""))
		if town.is_empty() or not places.has(town):
			continue
		var site: Dictionary = places[key]
		if site["holder"] != places[town]["holder"]:
			out.append("the %s %s is held by %s, not by its town %s: its worker can't work it until the town holds it" % [site["kind"], key, site["holder"], town])
		elif not HeightTools.reaches(working.map, places[town]["cell"], site["cell"], 70000, ground):
			out.append("the %s %s at %s can't be reached on foot from its town's store %s at %s: open a way" % [site["kind"], key, site["cell"], town, places[town]["cell"]])
		else:
			var stand := stand_problem(site)
			if not stand.is_empty():
				out.append(stand)
	return out


## Why a woodlot has nowhere for its woodcutter's body to stand at work
## (decision 566, builder's side), "" if it has: a walkable cell within its
## radius beside the forest (outdoors, the void past the floor). A hunting
## ground's own cell is open ground once site_checks reaches it.
func stand_problem(site: Dictionary) -> String:
	if str(site["kind"]) != "woodlot":
		return ""
	if Level.zone_of(working.config) != "outdoors":
		return "the woodlot %s is not outdoors: no trees for its woodcutter to fell" % site["key"]
	var at: Vector2i = site["cell"]
	var radius: int = site["radius"]
	var solid: Dictionary = walk_ground().get("solid", {})
	for y in range(at.y - radius, at.y + radius + 1):
		for x in range(at.x - radius, at.x + radius + 1):
			var cell := Vector2i(x, y)
			if (cell - at).length_squared() > radius * radius or not working.map.walkable(cell) or solid.has(cell):
				continue
			if [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN].any(func(step: Vector2i) -> bool:
					return working.map.in_bounds(cell + step) and working.map.cell(cell + step) == "void"):
				return ""
	return "the woodlot %s at %s has no walkable cell beside the forest within its radius %d: its woodcutter has no tree to fell (move it to the forest's edge)" % [site["key"], at, radius]


## The builds each town of this level has in hand (Towns' records planned
## or being built, decision 566) with no building here marked for them
## (a building of that use and town): "store: inn, loom". A town's wall
## is a record of its own (town_wall), not a building.
func builds_without_site() -> PackedStringArray:
	var out := PackedStringArray()
	if towns == null:
		return out
	var places: Dictionary = Level.places_from(working.config, [] as Array[String])
	var marked := {}
	for entry: Variant in working.config.get("buildings", []) if working.config.get("buildings") is Array else []:
		if entry is Dictionary and not str(entry.get("use", "")).is_empty():
			marked["%s/%s" % [entry.get("town", ""), entry["use"]]] = true
	for key: String in places:
		if places[key]["kind"] != "stockpile":
			continue
		var records: Dictionary = towns.buildings_of("%s/%s" % [map_name, key])
		var wanting: Array = records.keys().filter(func(kind: String) -> bool:
			return kind != "walls" and records[kind]["state"] in [Towns.PLANNED, Towns.BUILDING] and not marked.has("%s/%s" % [key, kind]))
		if not wanting.is_empty():
			wanting.sort()
			out.append("%s: %s" % [key, ", ".join(wanting)])
	return out


## level.json's "plots" (decision 564): [{key, rect: [x, y, w, h], facing:
## [dx, dy], the side its street is on}], ground a town keeps for new
## buildings, laid out in the editor and filled in builder mode; as [{key,
## rect (Rect2i), facing}]. One without a key or a rect is left out.
static func plots_from(config: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var listed: Variant = config.get("plots", [])
	for entry: Variant in listed if listed is Array else []:
		var rect: Variant = Level.town_wall_rect(entry)
		if rect == null or str(entry.get("key", "")).is_empty():
			continue
		out.append({"key": str(entry["key"]), "rect": rect, "facing": Level.building_facing(entry)})
	return out


## The plots the towns laid themselves in the level's zone as they grow
## (591 amended: World.clearing.plots_of, kept in the snapshot, never in
## level.json), in plots_from's shape with "laid" the town: the rect its
## footprint (the laid rect less its ring of a cell), the key "<use> (laid
## by <town>)". None without World.clearing.
static func laid_plots(config: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if World.clearing == null:
		return out
	for plot: Dictionary in World.clearing.plots_of(Level.zone_of(config)):
		out.append({"key": "%s (laid by %s)" % [plot["use"], plot["town"]], "rect": (plot["rect"] as Rect2i).grow(-1),
			"facing": plot["facing"], "laid": plot["town"]})
	return out


## Each building in the area on a plot that does not face the plot's street, and, in a
## level with roads (level.json's "roads", decision 559), each other
## building serving a town whose door does not open onto a street: no road
## cell, nor a square's paving (paved_street, 564 amended (1)), at its front
## cell or beside it (decision 564). A solid building's door leads under it,
## not to a street: left out.
func street_checks() -> Array[String]:
	var out: Array[String] = []
	var plots := plots_from(working.config) + laid_plots(working.config)
	for plot: Dictionary in plots:
		var room: Rect2i = plot["rect"]
		if area.intersects(room) and mini(room.size.x, room.size.y) < Level.MIN_ROOM:
			out.append("the plot %s is %d x %d: too small for a building, whose room is %d x %d at least: make it bigger" % [plot["key"], room.size.x, room.size.y, Level.MIN_ROOM, Level.MIN_ROOM])
	var streets := {}
	for road: Dictionary in Curves.parse(working.config, "roads", [] as Array[String]):
		streets.merge(Curves.cells(road["curve"], false))
	var paved := {}
	for entry: Variant in working.config.get("buildings", []) if working.config.get("buildings") is Array else []:
		var rect: Variant = Level.building_rect(entry)
		if rect == null or str(entry.get("slot", "")) in Level.SOLID or not area.intersects(rect):
			continue
		var facing := Level.building_facing(entry)
		var name := ("%s %s" % [entry.get("code", ""), building_name(entry)]).strip_edges()
		var on := plots.filter(func(plot: Dictionary) -> bool: return (plot["rect"] as Rect2i).intersects(rect))
		if not on.is_empty():
			if facing != on[0]["facing"]:
				out.append("the %s on the plot %s faces %s, but the plot's street is to the %s: turn it" % [name, on[0]["key"], side_name(facing), side_name(on[0]["facing"])])
			continue
		if streets.is_empty() or str(entry.get("use", "")).is_empty():
			continue
		var front := Level.front_cell(rect, facing)
		if not [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN].any(func(step: Vector2i) -> bool: return streets.has(front + step) or paved_street(front + step, streets, paved)):
			out.append("the door of the %s at %s does not open onto a street (no road or square's paving at or beside %s)" % [name, rect.position, front])
	var narrow := narrow_ways()
	if not narrow.is_empty():
		out.append("a way one cell wide at %s%s: players walk with companions, so make it two cells (a doorway is the one cell allowed)"
			% [", ".join(narrow.slice(0, NARROW_SHOWN).map(func(cell: Vector2i) -> String: return str(cell))),
			" and %d more" % (narrow.size() - NARROW_SHOWN) if narrow.size() > NARROW_SHOWN else ""])
	return out


## How many one-cell ways street_checks names before "and n more".
const NARROW_SHOWN := 8
## A paved patch this many cells or more is a square's paving (564 amended (1)).
const PAVED_SQUARE := 9


## Whether [param cell] is street by its paving (564 amended (1), maps'
## reading of Umbrage: a door onto the square's cobbles is on the town's main
## street, and a road draws nothing on cobble since 563 amended (1)): outdoors,
## the map's "stone", in no building, and joined (four ways, stone to stone,
## outside buildings) to PAVED_SQUARE cells or more, or to a road cell
## ([param streets]). A doorstep slab or a stone floor indoors is not one.
## [param known] keeps each patch's answer for the call.
func paved_street(cell: Vector2i, streets: Dictionary, known: Dictionary) -> bool:
	if known.has(cell):
		return known[cell]
	if Level.zone_of(working.config) != "outdoors" or working.map.cell(cell) != "stone" or _in_building(cell):
		return false
	var patch: Array[Vector2i] = [cell]
	var seen := {cell: true}
	var joined := false
	var i := 0
	while i < patch.size() and not joined and patch.size() < PAVED_SQUARE:
		var at := patch[i]
		i += 1
		for step in HeightTools.FOUR:
			var next: Vector2i = at + step
			if streets.has(next):
				joined = true
			if seen.has(next) or working.map.cell(next) != "stone" or _in_building(next):
				continue
			seen[next] = true
			patch.append(next)
	var paving := joined or patch.size() >= PAVED_SQUARE
	if paving or i >= patch.size():
		for each: Vector2i in patch:
			known[each] = paving
	return paving


## Whether [param cell] is inside a building's rect.
func _in_building(cell: Vector2i) -> bool:
	for entry: Variant in working.config.get("buildings", []) if working.config.get("buildings") is Array else []:
		var rect: Variant = Level.building_rect(entry)
		if rect is Rect2i and (rect as Rect2i).has_point(cell):
			return true
	return false


## The walkable cells in the area shut in on both sides, across or along:
## by a wall edge (not a door: a doorway is the one cell allowed), or a cell
## no one walks (void, water, rock, a solid building's). No way is one cell
## wide where a player walks with a companion (600 amended; the coordinator's
## rule from Jeff's play test of the crypt, 2026-10-22).
func narrow_ways(extra := {}) -> Array[Vector2i]:
	var solid: Dictionary = (walk_ground().get("solid", {}) as Dictionary).duplicate()
	solid.merge(bulky_cells())
	solid.merge(extra)
	var open := func(cell: Vector2i) -> bool:
		return Rect2i(Vector2i.ZERO, working.map.size).has_point(cell) and working.map.walkable(cell) and not solid.has(cell)
	var shut := func(cell: Vector2i, step: Vector2i) -> bool:
		return not open.call(cell + step) or working.map.edge(Terrain.edge_key(cell, step)) not in ["clear", "door"]
	var out: Array[Vector2i] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			if open.call(cell) and ((shut.call(cell, Vector2i.LEFT) and shut.call(cell, Vector2i.RIGHT))
					or (shut.call(cell, Vector2i.UP) and shut.call(cell, Vector2i.DOWN))):
				out.append(cell)
	return out


## The cells of the working copy's bulky decor (BULKY_DECOR, 841), as
## narrow_ways counts them: in the way, though drawn only.
func bulky_cells() -> Dictionary:
	var out := {}
	for entry: Variant in working.config.get("decor", []) if working.config.get("decor") is Array else []:
		if entry is Array and (entry as Array).size() == 6 and str(entry[4]) in BULKY_DECOR:
			out[Vector2i(int(entry[0]), int(entry[1]))] = true
	return out


## The prompt's paragraph on decor (841): the kinds a request lays, each in words.
static func decor_line() -> String:
	var kinds := PackedStringArray()
	for kind: String in DECOR_WORDS:
		kinds.append("%s (%s)" % [kind, DECOR_WORDS[kind]])
	return "decor sets a piece on a floor cell, drawn only: no piece is solid or opened, and players walk through it. The pieces: %s. A bulky piece is in the way all the same: set it against a wall or in a corner, out of the way; the tool refuses one that would leave a way one cell wide. A wall piece stands in its cell with its back to the wall on its side." % "; ".join(kinds)


## The decor tool (841): a piece of a DECOR_WORDS kind laid on a floor cell
## as level.json "decor" [x, y, dx, dy, kind, variant] (647, 658), checked
## by Level.decor_from itself (its warning the refusal), a bulky piece
## refused where it would leave a way one cell wide; or the decor on a cell
## taken away.
func _decor(given: Dictionary) -> Dictionary:
	var at: Variant = Level._tile(given.get("at"))
	if at == null:
		return _no("decor needs at: [x, y]")
	if not area.has_point(at):
		return _no("%s is outside the area" % [at])
	var kind := str(given.get("kind", "")).strip_edges()
	var listed: Array = (working.config["decor"] as Array).duplicate(true) if working.config.get("decor") is Array else []
	if bool(given.get("remove", false)):
		var kept := listed.filter(func(entry: Variant) -> bool:
			return not (entry is Array and (entry as Array).size() == 6 and Vector2i(int(entry[0]), int(entry[1])) == at and (kind.is_empty() or str(entry[4]) == kind)))
		if kept.size() == listed.size():
			return _no("no %s at %s" % [kind if not kind.is_empty() else "decor", at])
		working.apply_changes({"config": {"decor": kept}})
		return {"ok": true, "text": "took away %d piece%s of decor at %s" % [listed.size() - kept.size(), "" if listed.size() - kept.size() == 1 else "s", at]}
	if DECOR_KEPT_OUT.has(kind):
		return _no("%s is not laid with decor: %s" % [kind, DECOR_KEPT_OUT[kind]])
	if Level.DECOR_KINDS.has(kind) and not DECOR_WORDS.has(kind):
		return _no("%s is laid by its level's own maker, not by hand: decor lays %s" % [kind, ", ".join(DECOR_WORDS.keys())])
	if not DECOR_WORDS.has(kind):
		return _no("kind is one of %s" % ", ".join(DECOR_WORDS.keys()))
	var spec: Dictionary = Level.DECOR_KINDS[kind]
	var side := str(given.get("side", ""))
	if not side.is_empty() and not SIDES.has(side):
		return _no("side is one of %s" % ", ".join(SIDES.keys()))
	var step := Vector2i.ZERO
	if str(spec["sits"]) == "wall":
		if side.is_empty():
			return _no("a %s stands against a wall: give side, the side of %s its wall is on" % [kind, at])
		step = SIDES[side]
	elif not side.is_empty():
		if not bool(spec.get("faced", false)):
			return _no("a %s faces no way: leave side out" % kind)
		step = SIDES[side]
	if kind == "wall_hearth":
		var outside := _hearth_outside(at, step)
		if not outside.is_empty():
			return _no(outside)
	var variant := int(given.get("variant", 1))
	var entry := [at.x, at.y, step.x, step.y, kind, variant]
	for other: Variant in listed:
		if other is Array and (other as Array).size() == 6 and str(other[4]) == kind and Vector2i(int(other[0]), int(other[1])) == at and Vector2i(int(other[2]), int(other[3])) == step:
			return _no("a %s is at %s already" % [kind, at])
	var warnings: Array[String] = []
	Level.decor_from({"decor": [entry]}, parsed_of(working)["terrain"], warnings)
	if not warnings.is_empty():
		# decor_from's warning, said in plain words: what, where and why.
		var why := "it fits nothing there"
		if "on no floor" in warnings[0]:
			why = "%s is %s, not floor" % [at, working.map.cell(at)]
		elif str(spec["sits"]) == "wall" and int(spec.get("wide", 1)) > 1:
			why = "it needs a wall on the %s side of %s and of the cell beside it, %s" % [side, at, at + Vector2i(absi(step.y), absi(step.x))]
		elif str(spec["sits"]) == "wall":
			why = "there is no wall on the %s side of %s" % [side, at]
		return _no("a %s does not fit at %s: %s" % [kind, at, why])
	if kind in BULKY_DECOR:
		if not working.link_of(at).is_empty():
			return _no("%s is %s already" % [at, way_words(working.link_of(at))])
		if holds_thing(at):
			return _no("%s holds %s already" % [at, held_words(at)])
		var before := narrow_ways()
		var shut := narrow_ways({at: true}).filter(func(cell: Vector2i) -> bool: return cell not in before)
		if not shut.is_empty():
			return _no("a %s at %s would leave a way one cell wide at %s: players walk with companions; set it against a wall or in a corner, out of the way"
				% [kind, at, ", ".join(shut.slice(0, NARROW_SHOWN).map(func(cell: Vector2i) -> String: return str(cell)))])
	working.apply_changes({"config": {"decor": listed + [entry]}})
	return {"ok": true, "text": "laid a %s at %s%s" % [kind, at,
		(" against its %s wall" if str(spec["sits"]) == "wall" else ", facing %s") % side if not side.is_empty() else ""]}


# --- Spots (859) ---------------------------------------------------------------

## The prompt's paragraph on spots (859, npc's 853 contract).
static func spot_line() -> String:
	return ("spot lays where one townsperson stands, sits or leans while doing something: level.json's spots, read by the town's people. "
		+ "Its use is what they are doing there: work (a trade's spot: its trade named), square, fire, well, inn, temple, talk (two spots of one pair, facing each other); "
		+ "fire and talk spots are taken in the square's hours. Face is the cell the body faces (the fire, the well, the pot, its partner), one of the eight about it. "
		+ "Pose is stand, sit (over a seat laid there) or lean (a rim, a fence, a wall). A spot is on walkable ground the town reaches, never in a doorway, before a door, "
		+ "on a fire, or where a body standing would close the only way through. Lay more spots than people, so no two want one.")


## [param config]'s spots in a line each ("fire sit at (3, 4) facing (4, 4)"), or "".
static func spot_words(config: Dictionary) -> String:
	var words := PackedStringArray()
	for spot: Dictionary in Level.spots_from(config, [] as Array[String]):
		words.append("%s%s %s at %s facing %s%s" % [spot["use"], " (%s)" % spot["trade"] if not str(spot["trade"]).is_empty() else "",
			spot["pose"], spot["cell"], spot["face"], " (pair %s)" % spot["pair"] if not str(spot["pair"]).is_empty() else ""])
	return ", ".join(words)


## The spot tool (859): a level.json "spots" entry in npc's shape (853),
## checked by Level.spots_from itself (its warning on this cell the
## refusal), and by what the contract keeps that the reader cannot see: not
## on a fire, a doorway, the cell before a door or a way off the level; a
## sit spot over a seat; reached from where players come in; and no body
## standing there closing the only way through (the coordinator). One on a
## cell with a spot changes it; remove takes it away.
func _spot(given: Dictionary) -> Dictionary:
	var at: Variant = Level._tile(given.get("at"))
	if at == null:
		return _no("spot needs at: [x, y]")
	if not area.has_point(at):
		return _no("%s is outside the area" % [at])
	var listed: Array = (working.config["spots"] as Array).duplicate(true) if working.config.get("spots") is Array else []
	var on_cell := func(entry: Variant) -> bool: return entry is Dictionary and Level._tile(entry.get("cell")) == at
	var rest := listed.filter(func(entry: Variant) -> bool: return not on_cell.call(entry))
	var was: Array = listed.filter(on_cell)
	if bool(given.get("remove", false)):
		if was.is_empty():
			return _no("no spot at %s" % [at])
		working.apply_changes({"config": {"spots": rest}})
		return {"ok": true, "text": "took away the %s spot at %s" % [was[0].get("use", ""), at]}
	var use := str(given.get("use", "")).strip_edges()
	var pose := str(given.get("pose", "stand")).strip_edges()
	var trade := str(given.get("trade", "")).strip_edges()
	var pair := str(given.get("pair", "")).strip_edges()
	if not trade.is_empty() and use != "work":
		return _no("trade is for a work spot: this one's use is %s" % use)
	if not pair.is_empty() and use != "talk":
		return _no("pair is for a talk spot: this one's use is %s" % use)
	var town := str(given.get("town", "")).strip_edges()
	if town.is_empty():
		town = nearest_town(at)
		if town.is_empty():
			return _no("a spot belongs to a town, and this level has no town's store (a stockpile place): name its town")
	var face: Variant = Level._tile(given.get("face"))
	var entry := {"use": use, "cell": [at.x, at.y], "face": [face.x, face.y] if face is Vector2i else given.get("face"), "pose": pose, "town": town}
	if use == "work":
		entry["trade"] = trade
	if use == "talk" and not pair.is_empty():
		entry["pair"] = pair
	# npc's reader: its warning on this spot is the refusal, in its words.
	var floor := {}
	for cell: Vector2i in parsed_of(working)["terrain"]["floor"]:
		floor[cell] = true
	var warnings: Array[String] = []
	Level.spots_from({"spots": rest + [entry]}, warnings, floor)
	var mine := "the spot at %s " % [at]
	for warning: String in warnings:
		if warning.begins_with(mine):
			return _no(warning.trim_suffix("; left out"))
	var kept_clear := _spot_clear(at)
	if not kept_clear.is_empty():
		return _no(kept_clear)
	var unseated := pose == "sit" and not seat_at(at)
	if not reached().has(at):
		return _no("%s is not reached from where players and townsfolk come in" % [at])
	# A body standing there: the ground reached with every spot's cell solid, before and after.
	var held := {}
	for other: Variant in rest:
		if other is Dictionary and Level._tile(other.get("cell")) != null:
			held[Level._tile(other.get("cell"))] = true
	var before := _held_reach(held)
	held[at] = true
	var after := reached_round(held)
	var cut: Array[Vector2i] = []
	for cell: Vector2i in before:
		if cell != at and not after.has(cell):
			cut.append(cell)
	if not cut.is_empty():
		cut.sort()
		return _no("a body standing at %s would close the only way through: it cuts off %d cell%s (%s)" % [at, cut.size(), "" if cut.size() == 1 else "s",
			", ".join(cut.slice(0, NARROW_SHOWN).map(func(cell: Vector2i) -> String: return str(cell))) + (" and more" if cut.size() > NARROW_SHOWN else "")])
	var front := keeper_front(entry)
	if not front.is_empty():
		return _no(front)
	working.apply_changes({"config": {"spots": rest + [entry]}})
	# What every spot held reaches now: the next spot's before (867).
	_held = {"doc": working, "revision": working.revision, "cells": _cells_key(held), "reach": after}
	var said := "%s a %s spot at %s, %s facing %s%s" % ["changed it to" if not was.is_empty() else "laid", use if use != "work" else "work (%s)" % trade, at, pose,
		face, ", pair %s" % pair if not pair.is_empty() else ""]
	if unseated:
		said += ". Warning: nothing at %s is sat on (%s), so the body sits on the ground" % [at, SEAT_SAYS]
	var users := spot_users(town, use, trade)
	if not users.is_empty():
		said += ". " + users
	if use == "work":
		said += ". " + trade_preview(town)
	return {"ok": true, "text": said}


## Why a spot may not be at [param at], said whole, or "": a fire, a way off
## the level, a thing (by name, voice's words), a doorway (a door edge on one
## of its sides) or the cell in front of a building's door.
func _spot_clear(at: Vector2i) -> String:
	var kept := func(what: String, is_what: String) -> String: return "a spot is not %s: %s is %s" % [what, at, is_what]
	if working.map.cell(at) == "fire":
		return kept.call("on a fire", "a fire")
	# voice's words: what is there by name, and where to lay it instead.
	if not working.link_of(at).is_empty():
		return "%s is %s; lay the spot beside it" % [at, way_words(working.link_of(at))]
	if holds_thing(at):
		return "%s holds %s; lay the spot beside it" % [at, held_words(at)]
	for side in HeightTools.FOUR:
		if working.map.edge(Terrain.edge_key(at, side)) == "door":
			return kept.call("in a doorway", "beside the door on its %s side" % side_name(side))
	for other: Variant in working.config.get("buildings", []) if working.config.get("buildings") is Array else []:
		var their: Variant = Level.building_rect(other)
		if not their is Rect2i:
			continue
		var facing := Level.building_facing(other)
		var door := solid_door(other) if str(other.get("slot", "")) in Level.SOLID else Level.front_cell(their, facing) - facing
		if door != Level.NO_DOOR and at in [door, door + facing]:
			return kept.call("in a doorway or before a door", "the door of the %s or the cell before it" % building_name(other))
	return ""


## What stands on [param at], named for a refusal (voice's words): its own
## name first, then what it is: the store chest (a depot), the shop counter,
## a locker, the temple's chest, a chest, a crate, a barrel; a monster by its
## kind ("a robber").
func held_words(at: Vector2i) -> String:
	var entry := working.entry_of(at)
	if not str(entry.get("name", "")).is_empty():
		return str(entry["name"])
	var props: Dictionary = entry.get("props", {}) if entry.get("props") is Dictionary else {}
	var cell := working.map.cell(at)
	if cell == "chest":
		for use: String in HELD_CHESTS:
			if props.get(use, false):
				return HELD_CHESTS[use]
		return "a chest"
	if cell.begins_with("monster_"):
		var kind := cell.trim_prefix("monster_")
		var label := str(Monster.kinds().get(kind, {}).get("label", kind.replace("_", " "))).to_lower()
		return _a(label)
	if not str(props.get("cache", "")).is_empty():
		return "a cache"
	return _a(cell.replace("_", " "))


## Whether a thing stands on [param at]: an entry there, a thing place() puts
## down, or a monster.
func holds_thing(at: Vector2i) -> bool:
	var cell := working.map.cell(at)
	return not working.entry_of(at).is_empty() or cell in THINGS.values() or cell.begins_with("monster_")


## A chest by its use, as held_words says it (voice).
const HELD_CHESTS := {"depot": "the store chest", "shop": "the shop counter", "locker": "a locker", "temple": "the temple's chest"}


## A way off the level, for a refusal: "the way to <level>" (voice).
static func way_words(link: Dictionary) -> String:
	return "the way to %s" % str(link.get("to_map", "another level"))


static func _a(word: String) -> String:
	return ("an " if not word.is_empty() and word[0] in "aeiou" else "a ") + word


## What a sit spot sits on (859, npc's reading): what the warning names.
const SEAT_SAYS := "a seat of a place (a tavern's, a fire's) or a chair or bench laid there"
## Building slots a body sits on (npc: the barrow's hall chair, the smith's bench).
const SEAT_SLOTS: Array[String] = ["building.hall_chair", "building.smith_bench"]
## The trades that keep a stall or counter (npc's contract: they "tend"),
## and the starter stall's keeper, Rolf, whose work spot names "vendor"
## (Main.VENDOR_TRADE, npc's 853 amended (3); no Production trade).
const KEEPER_TRADES: Array[String] = ["merchant", "taverner", "keeper", Main.VENDOR_TRADE]


## Whether a body sits on something at [param at] (859, npc's reading: the
## code knows no seat cell of its own): a place's "seats" cell (a tavern's,
## a fire's), or a cell of a SEAT_SLOTS building.
func seat_at(at: Vector2i) -> bool:
	var places: Variant = working.config.get("places", {})
	for key: Variant in places if places is Dictionary else {}:
		var place: Variant = places[key]
		for seat: Variant in place.get("seats", []) if place is Dictionary and place.get("seats") is Array else []:
			if Level._tile(seat) == at:
				return true
	for entry: Variant in working.config.get("buildings", []) if working.config.get("buildings") is Array else []:
		if entry is Dictionary and str(entry.get("slot", "")) in SEAT_SLOTS:
			var rect: Variant = Level.building_rect(entry)
			if rect is Rect2i and (rect as Rect2i).has_point(at):
				return true
	return false


## The key of the town a spot at [param at] belongs to by default (859,
## npc): the level's store (a place of kind stockpile), the nearest of
## several by its cell; "" for none.
func nearest_town(at: Vector2i) -> String:
	var best := ""
	var best_far := 0
	var places: Variant = working.config.get("places", {})
	for key: Variant in places if places is Dictionary else {}:
		var place: Variant = places[key]
		var cell: Variant = Level._tile(place.get("at")) if place is Dictionary and str(place.get("kind", "")) == "stockpile" else null
		if cell is Vector2i:
			var far := (cell as Vector2i).distance_squared_to(at)
			if best.is_empty() or far < best_far:
				best = str(key)
				best_far = far
	return best


## Why a keeper's work spot [param entry] stands on its stall's customers'
## side (859, Rolf's rule, npc's reading: Main._behind_counter over the stall
## place's square and its counter), or "". The keeper only ever strolls
## behind his counter, so a spot out front would never be used.
func keeper_front(entry: Dictionary) -> String:
	if str(entry.get("use", "")) != "work" or str(entry.get("trade", "")) not in KEEPER_TRADES:
		return ""
	var at := Vector2i(int(entry["cell"][0]), int(entry["cell"][1]))
	var places: Variant = working.config.get("places", {})
	for key: Variant in places if places is Dictionary else {}:
		var place: Variant = places[key]
		var cell: Variant = Level._tile(place.get("at")) if place is Dictionary and str(place.get("kind", "")) == "stall" else null
		if not cell is Vector2i:
			continue
		var radius := int(place.get("radius", Level.PLACE_RADIUS))
		var square := Rect2i(cell - Vector2i(radius, radius), Vector2i(radius * 2 + 1, radius * 2 + 1))
		if not square.has_point(at):
			continue
		for building: Variant in working.config.get("buildings", []) if working.config.get("buildings") is Array else []:
			if not building is Dictionary or str(building.get("slot", "")) not in Main.COUNTERS:
				continue
			var counter: Variant = Level._tile(building.get("at"))
			if not counter is Vector2i or absi(counter.x - cell.x) > 1 or absi(counter.y - cell.y) > 1:
				continue
			if not Main._behind_counter(square, counter, Level.building_facing(building)).has_point(at):
				return "a %s's work spot at %s is on the customers' side of the counter at %s: he only ever stands behind it" % [entry["trade"], at, counter]
	return ""


## Which world the who-uses-it reading reads ("" for the one running here).
var spot_world := ""


## Who uses the spots of [param town]'s [param use] (and [param trade], a
## work spot's) over one day (859, npc's rule): each resident whose
## Townsfolk.whereabouts word at each hour is the use ("square" for square,
## fire and talk alike; "work" with the trade among theirs), against the
## spots there are. "" when no spot of that kind is laid.
func spot_users(town: String, use: String, trade := "") -> String:
	var spots := Level.spots_from(working.config, [] as Array[String]).filter(func(spot: Dictionary) -> bool:
		return spot["town"] == town and _spot_group(spot["use"]) == _spot_group(use) and (use != "work" or spot["trade"] == trade))
	if spots.is_empty():
		return ""
	var group := _spot_group(use)
	var named := "work (%s)" % trade if use == "work" else ("square, fire and talk" if group == "square" else use)
	var poses := PackedStringArray()
	for spot: Dictionary in spots:
		var pose: String = spot["pose"]
		if pose != "stand" and not Client3D.ACTIVITIES.has(pose) and not poses.has(pose + " draws as stand until its clip lands"):
			poses.append(pose + " draws as stand until its clip lands")
	var head := "%s in %s (%d spot%s%s)" % [named, town, spots.size(), "" if spots.size() == 1 else "s", "; " + ", ".join(poses) if not poses.is_empty() else ""]
	var residents := _spot_residents(town)
	if residents.is_empty():
		return head + ": no residents read%s" % (" (%s)" % spot_world if not spot_world.is_empty() else "")
	var hours := {}
	var wants: Array[int] = []
	wants.resize(24)
	for resident: Dictionary in residents:
		var mine: Array[int] = []
		for hour in 24:
			var word := Townsfolk.whereabouts(str(resident["trade"]), float(hour), "", str(resident["type"]), str(resident["id"]))
			var comes: bool = word == "work" and trade in resident["trades"] if use == "work" else (word == "square" if group == "square" else word == use)
			if comes:
				mine.append(hour)
				wants[hour] += 1
		if not mine.is_empty():
			hours[str(resident["name"])] = mine
	var where := " (%s)" % (spot_world if not spot_world.is_empty() else "this world, now")
	if hours.is_empty():
		return head + ": nobody comes all day" + where
	var who := PackedStringArray()
	for name: String in hours:
		who.append("%s %s" % [name, _spans(hours[name])])
	var over: Array[int] = []
	var most := 0
	for hour in 24:
		most = maxi(most, mini(wants[hour], spots.size()))
		if wants[hour] > spots.size():
			over.append(hour)
	var said := "%s: %s; at most %d at once of %d" % [head, ", ".join(who), most, spots.size()]
	if not over.is_empty():
		var peak := 0
		for hour in over:
			peak = maxi(peak, wants[hour])
		said += "; too few at %s (%d want them): the rest stand anywhere in the place's rect" % [_spans(over), peak]
	return said + where


## A spot use's group (859): square, fire and talk are all the square's hours.
static func _spot_group(use: String) -> String:
	return "square" if use in ["square", "fire", "talk"] else use


## Hours [param hours] (sorted) as spans: "8-12, 18-21" (each span's end the hour after its last).
static func _spans(hours: Array[int]) -> String:
	var out := PackedStringArray()
	var i := 0
	while i < hours.size():
		var j := i
		while j + 1 < hours.size() and hours[j + 1] == hours[j] + 1:
			j += 1
		out.append("%d-%d" % [hours[i], hours[j] + 1])
		i = j + 1
	return ", ".join(out)


## [param town]'s residents as the who-uses-it reading needs them: [{id,
## name, trade, trades, type}]. From the world running here when it holds
## the town (World.towns, its workers' trades; spot_world says which; the
## coordinator: in-process only, said to the builder-mode player who asked
## and never logged, its townsfolk only, never a companion); with
## none (the headless runner), residents.json's settled people of the town
## alone (npc: economy's workers are rolled as a world runs), and
## spot_world says so.
func _spot_residents(town: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var whole := "%s/%s" % [map_name, town]
	if World.towns != null and World.production != null and not World.towns.residents(whole).is_empty():
		for id: String in World.towns.residents(whole):
			var worker := World.production.worker(id)
			# Townsfolk only (the coordinator): a companion left in town is a player's.
			if id.begins_with("companion:") or worker.is_empty() or worker.has("owner"):
				continue
			var trades: Array = worker.get("trades", [])
			out.append({"id": id, "name": str(worker.get("name", id)), "trade": str(trades[0]) if not trades.is_empty() else "",
				"trades": trades, "type": str(worker.get("type", ""))})
		return out
	var settled := Townsfolk.settled()
	for id: String in settled:
		var card: Dictionary = settled[id]
		if str(card.get("town", "")) == whole:
			out.append({"id": id, "name": str(card.get("name", id)), "trade": str(card.get("trade", "")), "trades": [str(card.get("trade", ""))],
				"type": str(card.get("type", ""))})
	if spot_world.is_empty() and not out.is_empty():
		spot_world = "residents.json's settled people only: economy's workers are rolled as a world runs, not read here"
	return out


## Every laid spot kind's reading (859), a line each: the proposal's summary and the runner's.
func spot_preview() -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	for spot: Dictionary in Level.spots_from(working.config, [] as Array[String]):
		var key := "%s|%s|%s" % [spot["town"], _spot_group(spot["use"]), spot["trade"] if spot["use"] == "work" else ""]
		if seen.has(key):
			continue
		seen[key] = true
		out.append(spot_users(spot["town"], spot["use"], spot["trade"]))
	var towns: Array[String] = []
	for spot: Dictionary in Level.spots_from(working.config, [] as Array[String]):
		if spot["town"] not in towns:
			towns.append(spot["town"])
	for town in towns:
		out.append(trade_preview(town))
	return out


## The trades [param town]'s buildings and work sites call for, by economy's
## rules (859 amended (1), npc's readings), against the work spots laid: each
## building of the town with a use, its trade from economy.json's buildings
## (a keeper's, as the inn's taverner, seated once it stands), a temple's or
## healer's hut's from return.places, a work site's (a woodlot's woodcutter)
## from sites, a stall's keeper (Main.VENDOR_TRADE); the hours on the day's
## table alone (no resident's clock: "about"); a trade economy seats "if
## economy seats one" (npc). No name is read. A trade with work spots laid and
## nothing in the town that calls for it is said too (the coordinator).
func trade_preview(town: String) -> String:
	var economy := Production.read_rules(Economy.PATH)
	var rows: Dictionary = economy.get("buildings", {})
	var seats: Dictionary = economy.get("return", {}).get("places", {})
	var sites: Dictionary = economy.get("sites", {}).get("trades", {})
	var needs := {}  # trade -> {where: PackedStringArray, seat: bool, outside: bool}
	var need := func(trade: String, where: String, seat: bool, outside := false) -> void:
		if trade.is_empty():
			return
		var row: Dictionary = needs.get(trade, {"where": PackedStringArray(), "seat": false, "outside": false})
		if not row["where"].has(where):
			row["where"].append(where)
		row["seat"] = row["seat"] or seat
		row["outside"] = row["outside"] or outside
		needs[trade] = row
	for building: Variant in working.config.get("buildings", []) if working.config.get("buildings") is Array else []:
		if not building is Dictionary or str(building.get("town", "")) != town:
			continue
		var use := str(building.get("use", ""))
		var row: Dictionary = rows.get(use, {}) if rows.get(use) is Dictionary else {}
		need.call(str(row.get("trade", "")), "the " + use, false)
		var keeper: Variant = row.get("keeper")
		if keeper is Dictionary:
			need.call(str(keeper.get("trade", "")), "the " + use, true)
		var kind := str(Level.BUILDING_PLACES.get(str(building.get("slot", "")), building.get("kind", "")))
		if seats.get(kind) is Dictionary:
			need.call(str(seats[kind].get("trade", "")), "the " + kind.replace("_", " "), true, bool(seats[kind].get("outside", false)))
	var places: Dictionary = working.config.get("places", {}) if working.config.get("places") is Dictionary else {}
	for key: String in places:
		var place: Variant = places[key]
		if not place is Dictionary or str(place.get("town", "")) != town:
			continue
		var kind := str(place.get("kind", ""))
		for trade: String in sites:
			if str(sites[trade]) == kind:
				need.call(trade, "the %s %s" % [kind.replace("_", " "), key], false)
		if kind == "stall":
			need.call(Main.VENDOR_TRADE, "the stall " + key, false)
	var laid := {}
	for spot: Dictionary in Level.spots_from(working.config, [] as Array[String]):
		if spot["town"] == town and spot["use"] == "work":
			laid[spot["trade"]] = int(laid.get(spot["trade"], 0)) + 1
	var said := PackedStringArray()
	for trade: String in needs:
		var row: Dictionary = needs[trade]
		var hours: Array[int] = []
		for hour in 24:
			if Townsfolk.whereabouts(trade, float(hour)) == "work":
				hours.append(hour)
		var count := int(laid.get(trade, 0))
		said.append("%s at %s%s%s, works about %s: %s" % [trade, ", ".join(row["where"]), " (if economy seats one)" if row["seat"] else "",
			", outside the town" if row["outside"] else "", _spans(hours) if not hours.is_empty() else "no hours on the day's table",
			"no work spot yet" if count == 0 else "%d work spot%s" % [count, "" if count == 1 else "s"]])
	for trade: String in laid:
		if not needs.has(trade):
			said.append("%s: spots laid, no building" % trade)
	if said.is_empty():
		return "the town's trades in %s, by economy's rules: none (no building with a use, no work site)" % town
	return "the town's trades in %s, by economy's rules: %s" % [town, "; ".join(said)]


# --- What is read once a change (867) ---------------------------------------------

## Parses kept per doc and revision: instance id -> {revision, parsed}.
var _parses := {}
## The level's own faults, kept by the doc's revision: kind -> {revision, faults}.
var _baselines := {}
## The ground reached with every spot's cell held (the spot tool's before).
var _held := {}


## [param of] parsed (MapDoc.parsed), kept while its revision stands (867):
## the tool calls of an ask read one parse a change, not one a check. Never
## for accept's refusal, which parses fresh. Read only: a caller that wrote
## into it would change what the next one reads.
func parsed_of(of: MapDoc) -> Dictionary:
	var kept: Variant = _parses.get(of.get_instance_id())
	if kept is Dictionary and int(kept["revision"]) == of.revision:
		return kept["parsed"]
	var parsed := of.parsed()
	_parses[of.get_instance_id()] = {"revision": of.revision, "parsed": parsed}
	return parsed


## The level's own layout faults (layout_faults(doc)), kept by its revision:
## the doc changes only on accept or a host's undo, both through MapDoc (867).
func doc_layout_faults() -> Array:
	return _baseline("layout", func() -> Array: return layout_faults(doc, parsed_of(doc)))


## The level's own arrival faults (arrival_faults(doc)), kept as doc_layout_faults is.
func doc_arrival_faults() -> Array:
	return _baseline("arrival", func() -> Array: return arrival_faults(doc, parsed_of(doc)))


func _baseline(kind: String, read: Callable) -> Array:
	var kept: Variant = _baselines.get(kind)
	if kept is Dictionary and int(kept["revision"]) == doc.revision and is_same(kept["doc"], doc):
		return kept["faults"]
	var faults: Array = read.call()
	_baselines[kind] = {"doc": doc, "revision": doc.revision, "faults": faults}
	return faults


## The ground reached with [param held]'s cells solid: the last spot's after
## when nothing has changed since, else flooded (867).
func _held_reach(held: Dictionary) -> Dictionary:
	if not _held.is_empty() and is_same(_held["doc"], working) and int(_held["revision"]) == working.revision and _held["cells"] == _cells_key(held):
		return _held["reach"]
	return reached_round(held)


static func _cells_key(cells: Dictionary) -> String:
	var listed: Array = cells.keys()
	listed.sort()
	return str(listed)


## Why a wall_hearth at [param at] against its [param step] wall is not on an
## inside wall (841): outdoors, both its cells in a building's rect; indoors
## any wall will do. "" if it is.
func _hearth_outside(at: Vector2i, step: Vector2i) -> String:
	if Level.zone_of(working.config) != "outdoors":
		return ""
	var along := Vector2i(absi(step.y), absi(step.x))
	for entry: Variant in working.config.get("buildings", []) if working.config.get("buildings") is Array else []:
		var rect: Variant = Level.building_rect(entry) if entry is Dictionary else null
		if rect is Rect2i and (rect as Rect2i).has_point(at) and (rect as Rect2i).has_point(at + along):
			return ""
	return "a wall_hearth stands against an inside wall: outdoors, only on a building's wall, inside it"


## The prompt's paragraph on standing pieces (842).
static func piece_line() -> String:
	var kinds := PackedStringArray()
	for kind: String in PIECE_WORDS:
		kinds.append("%s (%s)" % [kind, PIECE_WORDS[kind]])
	return "piece lays a standing piece with no walls or roof, solid (no one walks its cells), its top-left at a cell and its front to a side, on flat ground clear of things, ways off the level, arrivals and doors: %s. Words cut on a milestone are a draft: they go to voice when the level is put up to land." % "; ".join(kinds)


## The names a milestone may carry (842): of every area a player can reach
## from the world's start (WorldMap.root) over ways that are not closed (a
## hidden or sealed link is closed; a shelved level is no area), its name, its
## towns' (a named room, as Main._town_display says a town) and its named
## places' names and shown names; [method _name_key] of each -> as written.
static func reachable_names() -> Dictionary:
	var world := WorldMap.build()
	var seen := {WorldMap.root(): true}
	var queue: Array[String] = [WorldMap.root()]
	while not queue.is_empty():
		var from: String = queue.pop_back()
		for way: Dictionary in world.ways:
			if str(way["from"]) == from and not bool(way.get("closed", false)) and world.areas.has(str(way["to"])) and not seen.has(str(way["to"])):
				seen[str(way["to"])] = true
				queue.append(str(way["to"]))
	var out := {}
	for area_name: String in seen:
		if not world.areas.has(area_name):
			continue
		var names: Array = [world.areas[area_name].get("display_name", "")]
		var config: Dictionary = world._configs.get(area_name, {})
		for key: Variant in config.get("rooms", {}) if config.get("rooms") is Dictionary else {}:
			if config["rooms"][key] is Dictionary:
				names.append(config["rooms"][key].get("name", ""))
		for key: Variant in config.get("places", {}) if config.get("places") is Dictionary else {}:
			if config["places"][key] is Dictionary:
				names.append(config["places"][key].get("name", ""))
				names.append(config["places"][key].get("shown", ""))
		for each: Variant in names:
			if each is String and not _name_key(each).is_empty():
				out[_name_key(each)] = str(each).strip_edges()
	return out


## [param words] as reachable_names keys them: lower case, no "the" or "a" before.
static func _name_key(words: String) -> String:
	return words.strip_edges().to_lower().trim_prefix("the ").trim_prefix("a ").strip_edges()


## The piece tool (842): a standing piece (PIECE_WORDS) laid as a level.json
## "buildings" entry {slot, at, facing, variant, carved, arrow}, solid and
## doorless as Level has it; or the piece on a cell taken away.
func _piece(given: Dictionary) -> Dictionary:
	var at: Variant = Level._tile(given.get("at"))
	if at == null:
		return _no("piece needs at: [x, y]")
	var buildings: Array = (working.config["buildings"] as Array).duplicate(true) if working.config.get("buildings") is Array else []
	if bool(given.get("remove", false)):
		for i in buildings.size():
			var rect: Variant = Level.building_rect(buildings[i])
			if rect is Rect2i and (rect as Rect2i).has_point(at) and str(buildings[i].get("slot", "")).trim_prefix("building.") in PIECE_WORDS:
				var kind_gone := str(buildings[i]["slot"]).trim_prefix("building.")
				buildings.remove_at(i)
				working.apply_changes({"config": {"buildings": buildings}})
				return {"ok": true, "text": "took away the %s at %s" % [kind_gone, at]}
		return _no("no piece stands on %s" % [at])
	var kind := str(given.get("kind", "")).strip_edges()
	if PIECES_NOT_YET.has(kind):
		return _no("%s: %s" % [kind, PIECES_NOT_YET[kind]])
	if not PIECE_WORDS.has(kind):
		return _no("kind is one of %s" % ", ".join(PIECE_WORDS.keys()))
	var facing := str(given.get("facing", "south"))
	if not SIDES.has(facing):
		return _no("facing is one of %s" % ", ".join(SIDES.keys()))
	var entry := {"slot": "building." + kind, "at": [at.x, at.y], "facing": [SIDES[facing].x, SIDES[facing].y]}
	if given.has("variant"):
		entry["variant"] = maxi(1, int(given["variant"]))
	var carved := str(given.get("carved", "")).strip_edges()
	if kind != "milestone" and (not carved.is_empty() or given.has("arrow")):
		return _no("only a milestone has words cut in it")
	if kind == "milestone":
		if carved.is_empty():
			return _no("a milestone says where its road goes: give carved, a level, a town or a named place players can reach")
		if carved.length() > Level.CARVED_MAX:
			return _no("carved is %d letters at most" % Level.CARVED_MAX)
		var names := reachable_names()
		if not names.has(_name_key(carved)):
			var listed: Array = names.values()
			listed.sort()
			return _no("no level, town or named place a player can reach is called %s (there are: %s)" % [carved, ", ".join(listed)])
		entry["carved"] = carved
		if given.has("arrow"):
			if str(given["arrow"]) not in Level.CARVED_ARROWS:
				return _no("arrow is one of %s" % ", ".join(Level.CARVED_ARROWS))
			entry["arrow"] = str(given["arrow"])
	var rect: Rect2i = Level.building_rect(entry)
	if not area.encloses(rect):
		return _no("a %s facing %s is %d x %d: at %s it does not fit in the area" % [kind, facing, rect.size.x, rect.size.y, at])
	for cell in Level.rect_cells(rect):
		if working.map.cell(cell) not in WALKED:
			return _no("%s is %s: a %s stands on ground" % [cell, working.map.cell(cell), kind])
		if not working.entry_of(cell).is_empty() or not working.link_of(cell).is_empty():
			return _no("something stands on %s already" % [cell])
	for other: Variant in buildings:
		var taken: Variant = Level.building_rect(other)
		if taken is Rect2i and (taken as Rect2i).intersects(rect):
			return _no("the %s at %s stands there already" % [building_name(other), (taken as Rect2i).position])
	var kept := _kept_clear(rect)
	if not kept.is_empty():
		return _no("a %s at %s would stand %s: keep it a cell clear" % [kind, at, kept])
	var uneven := pad_problem(entry)
	if not uneven.is_empty():
		return _no(uneven)
	var before := narrow_ways()
	var solid := {}
	for cell in Level.rect_cells(rect):
		solid[cell] = true
	var shut := narrow_ways(solid).filter(func(cell: Vector2i) -> bool: return cell not in before)
	if not shut.is_empty():
		return _no("a %s at %s would leave a way one cell wide at %s: players walk with companions" % [kind, at, ", ".join(shut.slice(0, NARROW_SHOWN).map(func(cell: Vector2i) -> String: return str(cell)))])
	buildings.append(entry)
	working.apply_changes({"config": {"buildings": buildings}})
	var text := "laid a %s at %s, its front %s" % [kind, at, facing]
	if kind == "milestone":
		text += ", carved \"%s\"%s (a draft until voice has seen it)" % [carved, ", its arrow " + str(entry["arrow"]) if entry.has("arrow") else ""]
		var streets := {}
		for road: Dictionary in Curves.parse(working.config, "roads", [] as Array[String]):
			streets.merge(Curves.cells(road["curve"], false))
		if not Level.rect_cells(rect.grow(1)).any(func(cell: Vector2i) -> bool: return streets.has(cell)):
			text += "; no road is at or beside it: a milestone stands by the road it names"
	elif kind == "market_stall":
		text += "; " + STALL_EMPTY
	return {"ok": true, "text": text}


## What [param rect] (a piece's cells) stands on or beside (842), in words,
## or "": a start or an arrival (spawn point), a way off the level, or a
## building's door or the cell before it.
func _kept_clear(rect: Rect2i) -> String:
	var near := rect.grow(1)
	var level := parsed_of(working)
	for start: Vector2i in level.get("starts", []):
		if near.has_point(start):
			return "on or beside the start at %s" % [start]
	var arrivals: Dictionary = level.get("spawn_points", {})
	for spawn_name: String in arrivals:
		if near.has_point(arrivals[spawn_name]):
			return "on or beside the arrival %s at %s" % [spawn_name, arrivals[spawn_name]]
	for link: Variant in working.config.get("links", []) if working.config.get("links") is Array else []:
		var cell: Variant = Level._tile(link.get("at")) if link is Dictionary else null
		if cell is Vector2i and near.has_point(cell):
			return "on or beside the way off the level at %s" % [cell]
	for other: Variant in working.config.get("buildings", []) if working.config.get("buildings") is Array else []:
		var their: Variant = Level.building_rect(other)
		if not their is Rect2i:
			continue
		var facing := Level.building_facing(other)
		var door: Vector2i = Level.NO_DOOR
		if str(other.get("slot", "")) in Level.SOLID:
			door = solid_door(other)
		else:
			door = Level.front_cell(their, facing) - facing
		if door == Level.NO_DOOR:
			continue
		for cell: Vector2i in [door, door + facing]:
			if near.has_point(cell):
				return "on or beside the door of the %s at %s" % [building_name(other), door]
	return ""


## The working copy's walkable cells a player reaches from any start or
## arrival (844): the level's whole floor, flooded from its starts (level.json
## "starts" and start markers), its spawn points and, on an edge with a
## neighbour, that edge's cells, stepping as HeightTools.steps has it (no
## wall edge; a door is open; a ledge or cliff only by a stair) round solid
## buildings and bulky decor (walk_ground, bulky_cells). Kept between tool
## calls: an edit's after is the next one's before.
func reached() -> Dictionary:
	if not _reached.is_empty():
		return _reached
	_reached = reached_round({})
	return _reached


## reached() with the cells of [param extra] solid too (859: a body standing on a spot).
func reached_round(extra: Dictionary) -> Dictionary:
	var ground := flood_ground()
	if not extra.is_empty():
		var solid: Dictionary = (ground.get("solid", {}) as Dictionary).duplicate()
		solid.merge(extra)
		ground["solid"] = solid
	var map := working.map
	var seen: Dictionary = {}
	var queue: Array[Vector2i] = []
	for cell: Vector2i in arrival_cells():
		if not seen.has(cell) and HeightTools._walks(map, ground, cell):
			seen[cell] = true
			queue.append(cell)
	var head := 0
	while head < queue.size():
		var at := queue[head]
		head += 1
		for side in HeightTools.FOUR:
			var next := at + side
			if not seen.has(next) and HeightTools.steps(map, at, next, ground):
				seen[next] = true
				queue.append(next)
	return seen

var _reached: Dictionary = {}


## What reached() steps over (844): walk_ground (the relief and the solid
## buildings) with the bulky decor solid too.
func flood_ground() -> Dictionary:
	var ground := walk_ground()
	var solid: Dictionary = (ground.get("solid", {}) as Dictionary).duplicate()
	solid.merge(bulky_cells())
	ground["solid"] = solid
	return ground


## Where players come into the working copy (844): its starts, its spawn
## points and the cells of each edge with a neighbour beyond it.
func arrival_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var size := working.map.size
	for value: Variant in working.config.get("starts", []) if working.config.get("starts") is Array else []:
		if Level._tile(value) != null:
			out.append(Level._tile(value))
	for y in size.y:
		for x in size.x:
			if working.map.cell(Vector2i(x, y)) == "start":
				out.append(Vector2i(x, y))
	var named: Variant = working.config.get("spawn_points", {})
	for spawn_name: Variant in named if named is Dictionary else {}:
		if Level._tile(named[spawn_name]) != null:
			out.append(Level._tile(named[spawn_name]))
	var neighbours: Variant = working.config.get("neighbours", {})
	for side: Variant in neighbours if neighbours is Dictionary else {}:
		if str(neighbours[side]).is_empty():
			continue
		match str(side):
			"north":
				for x in size.x: out.append(Vector2i(x, 0))
			"south":
				for x in size.x: out.append(Vector2i(x, size.y - 1))
			"west":
				for y in size.y: out.append(Vector2i(0, y))
			"east":
				for y in size.y: out.append(Vector2i(size.x - 1, y))
	return out


## [param lost] (cells cut off) said by what a person knows in each patch of
## it (844): a way off the level, a building's door, a place, else the cell
## and the patch's size; the biggest CUT_SHOWN patches.
func cut_off_words(lost: Array) -> String:
	var left := {}
	for cell: Vector2i in lost:
		left[cell] = true
	var patches: Array[Array] = []
	while not left.is_empty():
		var first: Vector2i = left.keys()[0]
		var patch: Array[Vector2i] = [first]
		left.erase(first)
		var head := 0
		while head < patch.size():
			for side in HeightTools.FOUR:
				var next: Vector2i = patch[head] + side
				if left.has(next):
					left.erase(next)
					patch.append(next)
			head += 1
		patches.append(patch)
	patches.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size())
	var said := PackedStringArray()
	for patch: Array in patches.slice(0, CUT_SHOWN):
		said.append(_known_in(patch))
	if patches.size() > CUT_SHOWN:
		said.append("%d more patches" % (patches.size() - CUT_SHOWN))
	return ", ".join(said)


## The nearest thing a person knows in [param patch] (cells), in words.
func _known_in(patch: Array) -> String:
	var cells := {}
	for cell: Vector2i in patch:
		cells[cell] = true
	for link: Variant in working.config.get("links", []) if working.config.get("links") is Array else []:
		var at: Variant = Level._tile(link.get("at")) if link is Dictionary else null
		if at is Vector2i and cells.has(at):
			return "the way off the level at %s%s" % [at, " (to %s)" % link["to"] if not str(link.get("to", "")).is_empty() else ""]
	for entry: Variant in working.config.get("buildings", []) if working.config.get("buildings") is Array else []:
		var rect: Variant = Level.building_rect(entry)
		if rect is Rect2i and str(entry.get("slot", "")) not in Level.SOLID:
			var door := Level.front_cell(rect, Level.building_facing(entry)) - Level.building_facing(entry)
			if cells.has(door) or cells.has(door + Level.building_facing(entry)):
				return "the door of the %s at %s" % [building_name(entry), door]
	var places: Dictionary = working.config.get("places", {}) if working.config.get("places") is Dictionary else {}
	for key: Variant in places:
		var at: Variant = Level._tile(places[key].get("at")) if places[key] is Dictionary else null
		if at is Vector2i and cells.has(at):
			return "the place %s (a %s) at %s" % [key, places[key].get("kind", "place"), at]
	return "the ground at %s (%d cell%s)" % [patch[0], patch.size(), "" if patch.size() == 1 else "s"]


## A side's word: (0, 1) "south".
static func side_name(side: Vector2i) -> String:
	return {Vector2i(0, -1): "north", Vector2i(1, 0): "east", Vector2i(0, 1): "south", Vector2i(-1, 0): "west"}.get(side, str(side))


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
		var solid := str(building.get("slot", "")) in Level.SOLID
		if not ground.is_empty():
			var uneven := pad_problem(building)
			if not uneven.is_empty():
				out.append(uneven)
			# A doorless one (a standing stone, 567) is no one's to reach.
			if str(building.get("slot", "")) not in Level.DOORLESS:
				things.append(solid_door(building) if solid else rect.position)
			continue
		var levels := {}
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if map.walkable(Vector2i(x, y)):
					levels[int(map.heights.get(Vector2i(x, y), 0))] = true
		if levels.size() > 1:
			out.append("the building at %s stands on more than one height: level it" % rect.position)
		# A solid one (a mound) is reached at its door (decision 550).
		things.append(solid_door(building) if solid else rect.position)
	out.append_array(HeightTools.ledge_warnings(map, things, walk_ground()))
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
## Dungeon's layout faults (806, sim/layout_sense.gd) of [param of] (the
## level, or the working copy): every rule in a dungeon or indoors, by the
## regenerate block's options when it has one (Regen.layout_options); out
## of doors only the chest rule (no interior to judge).
static func layout_faults(of: MapDoc, parsed: Dictionary = {}) -> Array:
	var level := parsed if not parsed.is_empty() else of.parsed()
	var config := of.config
	if Level.zone_of(config) == "outdoors" and not is_dungeon(config):
		return LAYOUT_SENSE.check_chests(level, {"dungeon": false})
	var block: Variant = config.get("regenerate")
	var options := Regen.layout_options(block) if block is Dictionary else {"dungeon": is_dungeon(config)}
	return LAYOUT_SENSE.check(level, config.get("laid_rooms", []), options)


## The layout faults the proposal adds, said ("<rule> at <cell>: <what>"):
## those of the working copy not in [param before] (the level's, by rule
## and cell; layout_faults(doc) when not given). A fault the level already
## had stays its own (the barrow's empty rooms, castle_halls'): only what
## the edit adds is refused, a fault moved with its chest or room included.
func layout_news(before: Variant = null, parsed: Dictionary = {}) -> Array[String]:
	var had := {}
	for fault: Dictionary in (before if before is Array else layout_faults(doc)):
		had["%s %s" % [fault["rule"], fault["cell"]]] = true
	var out: Array[String] = []
	for fault: Dictionary in layout_faults(working, parsed):
		if not had.has("%s %s" % [fault["rule"], fault["cell"]]):
			out.append("%s at %s: %s" % [fault["rule"], fault["cell"], fault["what"]])
	return out


## Dungeon's arrival rule (806 amended (11), layout_sense.arrival_faults)
## over [param of] (the level, or the working copy), in every zone, laid by
## hand or generated (806 amended (13)): a spawn point or start within
## ARRIVAL_CLEAR of where a hostile roams. None on the test levels and those
## held back (ARRIVAL_EXEMPT, ARRIVAL_NOT_YET), nor where the level's layout
## rules hold the rule (its regenerate block's "held"): layout_news says it
## there, and accept refuses it.
func arrival_faults(of: MapDoc, parsed: Dictionary = {}) -> Array:
	if map_name in LAYOUT_SENSE.ARRIVAL_EXEMPT or LAYOUT_SENSE.ARRIVAL_NOT_YET.has(map_name) or holds_arrival(of.config):
		return []
	return LAYOUT_SENSE.arrival_faults(parsed if not parsed.is_empty() else of.parsed())


## Whether [param config]'s layout rules hold the arrival rule (layout_faults' options).
static func holds_arrival(config: Dictionary) -> bool:
	if Level.zone_of(config) == "outdoors" and not is_dungeon(config):
		return false
	var block: Variant = config.get("regenerate")
	return block is Dictionary and bool(Regen.layout_options(block).get("arrival", false))


## The arrival faults the proposal adds, said ("arrival at <cell>: <what>"):
## those of the working copy not in [param before] (the level's own, by
## rule and cell, the baseline: a way in already inside a fight is the
## level's, not the edit's). A warning only (the coordinator): the player
## may accept it.
func arrival_news(before: Array, parsed: Dictionary = {}) -> Array[String]:
	var had := {}
	for fault: Dictionary in before:
		had["%s %s" % [fault["rule"], fault["cell"]]] = true
	var out: Array[String] = []
	for fault: Dictionary in arrival_faults(working, parsed):
		if not had.has("%s %s" % [fault["rule"], fault["cell"]]):
			out.append("%s at %s: %s" % [fault["rule"], fault["cell"], fault["what"]])
	return out


## What an arrival warning asks (806 amended (13)).
const ARRIVAL_SAYS := "a warning: a player coming in there lands inside a fight; move the monster, or the way in, further apart"


func accept() -> bool:
	created_doc = null
	created = ""
	refused = ""
	# 806 amended (7): the proposal may not add a layout fault (an empty
	# room, a chest that gives nothing or stands unguarded, ...).
	# The working copy parsed fresh, never from the cache (867: a stale one could let a fault through).
	var news := layout_news(doc_layout_faults())
	if not news.is_empty():
		refused = "the change breaks the layout rules: " + "; ".join(news)
		return false
	var changes := proposal()
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
