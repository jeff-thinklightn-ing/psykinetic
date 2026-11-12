extends Node
## Builder mode's session (BuilderSession) against a scripted Claude
## (StubClaude): what it is told, the tools on a working copy kept to the
## area, the proposal as one change set, accept as one undo step, discard,
## follow-ups, errors back to Claude, cost and the spending limit.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

## The soft ceiling on what every builder request sends before the
## conversation (the system prompt and the tools, one cached prefix), in
## tokens at 4 characters a token (841; the coordinator's, 2026-11-10). Only
## the coordinator moves it: when it trips, take the coordinator the prompt's
## paragraphs with how often a request has needed each, not a trim by age.
const PREFIX_CEILING_TOKENS := 20000
var _failures := 0


func _ready() -> void:
	World.set_process(false)
	_test_prompt()
	await _test_session()
	await _test_follow_up_and_errors()
	await _test_spending_limit()
	await _test_new_area()
	await _test_mark_place()
	await _test_stamp_building()
	await _test_set_building()
	await _test_town_wall()
	await _test_store_checks()
	await _test_heights()
	await _test_roof()
	await _test_monster_kinds()
	await _test_loot()
	await _test_stream()
	await _test_kind_building()
	await _test_slopes()
	await _test_captives()
	await _test_work_sites()
	_test_relief()
	_test_codes()
	_test_solid()
	_test_plots()
	_test_visible_work()
	_test_old_tower()
	_test_narrow_ways()
	_test_new_kinds()
	_test_umbrage_kinds()
	_test_workings()
	_test_kind_lines()
	_test_place_cells()
	_test_decor()
	_test_piece()
	_test_cut_off()
	_test_chest_rule()
	await _test_layout_on_accept()
	await _test_arrivals()
	_test_accept_keeps()
	_test_json_keep()
	_test_runner()
	_test_spots()
	_test_named_refusals()
	_test_trades_preview()
	_test_cached_checks()
	await _test_spot_ghost()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## A 40 x 30 level of grass, outdoors, with a brute at (30, 5).
func _doc() -> MapDoc:
	var doc := MapDoc.new()
	doc.folder = preload("res://tests/test_ports.gd").scratch("builder_test/")
	doc.map = LevelMap.new(Vector2i(40, 30))
	for y in 30:
		for x in 40:
			doc.map.set_cell(Vector2i(x, y), "grass")
	doc.map.set_cell(Vector2i(30, 5), "monster_brute")
	doc.config = {"name": "Test Field", "outdoor": true, "entities": [{"at": [30, 5], "idle": "guard"}]}
	return doc


func _test_mark_place() -> void:
	print("
== mark_place: a place factions hold, in the proposal's level.json ==")
	var doc := _doc()
	var stub := StubClaude.new([
		[{"name": "mark_place", "input": {"key": "camp", "kind": "camp", "at": [10, 10], "radius": 6, "holder": "goblins", "name": "the goblin camp"}},
			{"name": "mark_place", "input": {"key": "Bad Key", "kind": "camp", "at": [11, 11], "holder": "goblins"}},
			{"name": "mark_place", "input": {"key": "far", "kind": "camp", "at": [39, 29], "holder": "goblins"}},
			{"name": "mark_place", "input": {"key": "elf", "kind": "camp", "at": [12, 12], "holder": "elves"}}],
		"A goblin camp.",
	])
	var session := BuilderSession.new(doc, Rect2i(5, 5, 12, 10), "test_field", stub)
	await session.ask("a goblin camp")
	var proposal := session.proposal()
	_check(proposal.get("config", {}).get("places") == {"camp": {"at": [10, 10], "kind": "camp", "radius": 6, "holder": "goblins", "name": "the goblin camp"}},
			"the place is in the proposal's level.json; a bad key, a cell outside the area and a holder that is no faction are refused (%s)" % [proposal.get("config")])
	var results: Array = stub.sent[1]["messages"][2]["content"]
	_check(results.slice(1).all(func(result: Dictionary) -> bool: return result.get("is_error", false)), "and Claude is told so")
	session.accept()
	_check(doc.config.get("places", {}).has("camp") and doc.undo_steps.size() == 1, "accepted: in the level, one undo step")


func _test_stamp_building() -> void:
	print("
== stamp a building: its record in the level, turned with it, beside the others ==")
	var doc := _doc()
	doc.config["buildings"] = [{"slot": "building.shed", "at": [20, 20], "facing": [0, 1]}]
	var stub := StubClaude.new([
		[{"name": "stamp", "input": {"prefab": "building_hut", "at": [6, 6], "turns": 1}},
			{"name": "stamp", "input": {"prefab": "building_shed", "at": [11, 6]}}],
		"A hut and a shed.",
	])
	var session := BuilderSession.new(doc, Rect2i(5, 5, 12, 10), "test_field", stub)
	await session.ask("a hut and a shed")
	session.accept()
	var buildings: Array = doc.config.get("buildings", [])
	_check(buildings.size() == 3 and buildings[0]["at"] == [20, 20], "accepted: the map's shed kept, and two more (%s)" % [buildings])
	_check(buildings.size() == 3 and buildings[1] == {"slot": "building.hut", "at": [7, 7], "facing": [-1, 0], "code": "H1"},
			"the hut turned a quarter: its front west (%s)" % [buildings[1] if buildings.size() > 1 else null])
	var level := Level.parse(doc.map.to_image(), null, doc.config)
	_check(level["buildings"].size() == 3 and doc.undo_steps.size() == 1, "all three stand in the level, one undo step (%s)" % [level["warnings"]])
	var prompt := BuilderSession.system_prompt()
	_check(prompt.contains("building_hut (5 x 5), a building: hut") and prompt.contains("building_house (6 x 8), a building: house")
			and prompt.contains("well (5 x 5), a building: well"),
			"Claude is told which prefabs are buildings")


func _test_set_building() -> void:
	print("
== set_building: a building's use and its town ==")
	var doc := _doc()
	var stub := StubClaude.new([
		[{"name": "stamp", "input": {"prefab": "building_hut", "at": [6, 6]}},
			{"name": "mark_place", "input": {"key": "square", "kind": "stockpile", "at": [14, 12], "holder": "town"}},
			{"name": "set_building", "input": {"at": [12, 12], "use": "forge", "town": "square"}},
			{"name": "set_building", "input": {"at": [8, 8], "use": "walls", "town": "square"}},
			{"name": "set_building", "input": {"at": [8, 8], "use": "forge", "town": "nowhere"}},
			{"name": "set_building", "input": {"at": [8, 8], "use": "forge", "town": "square"}}],
		"A forge for the square.",
	])
	var session := BuilderSession.new(doc, Rect2i(5, 5, 12, 10), "test_field", stub)
	await session.ask("a forge")
	var results: Array = stub.sent[1]["messages"][2]["content"]
	_check(results[2]["is_error"] and "no building stands" in str(results[2]["content"]), "a cell with no building: an error (%s)" % results[2]["content"])
	_check(results[3]["is_error"] and "walls" not in str(results[3]["content"]).get_slice("one of", 1), "walls is not a building's use (%s)" % results[3]["content"])
	_check(results[4]["is_error"] and "square" in str(results[4]["content"]), "a town that is no stockpile place here: an error naming those there are (%s)" % results[4]["content"])
	_check(not results[5]["is_error"], "a hut made the square's forge (%s)" % results[5]["content"])
	session.accept()
	var buildings: Array = doc.config.get("buildings", [])
	_check(buildings.size() == 1 and buildings[0].get("use") == "forge" and buildings[0].get("town") == "square", "accepted: the record has its use and town (%s)" % [buildings])
	var level := Level.parse(doc.map.to_image(), null, doc.config)
	var about := (level["warnings"] as Array).filter(func(warning: String) -> bool: return "building" in warning)
	_check(level["buildings"].size() == 1 and about.is_empty(), "the level reads it with nothing to say (%s)" % [about])
	_check("set_building gives one in the area a use (butchery, camp, field, forge, inn, kitchen, loom, pasture, tannery, temple, woodshed)" in BuilderSession.system_prompt(), "Claude is told the uses, from the economy rules")
	_check("building {" in session.grid(doc.map, doc.config, Rect2i(5, 5, 12, 10), Rect2i(5, 5, 12, 10)), "and sees the buildings in the area, with theirs")


func _test_town_wall() -> void:
	print("
== town_wall: a ring of walls round a town, gates in it ==")
	var doc := _doc()
	var stub := StubClaude.new([
		[{"name": "mark_place", "input": {"key": "square", "kind": "stockpile", "at": [12, 11], "holder": "town"}},
			{"name": "town_wall", "input": {"town": "nowhere", "rect": {"x": 8, "y": 8, "w": 10, "h": 8}}},
			{"name": "town_wall", "input": {"town": "square", "rect": {"x": 5, "y": 8, "w": 10, "h": 8}}},
			{"name": "town_wall", "input": {"town": "square", "rect": {"x": 8, "y": 8, "w": 10, "h": 8}, "gates": [[12, 12]]}},
			{"name": "town_wall", "input": {"town": "square", "rect": {"x": 8, "y": 8, "w": 10, "h": 8}}}],
		"A wall round the square.",
	])
	var session := BuilderSession.new(doc, Rect2i(6, 6, 16, 12), "test_field", stub)
	await session.ask("wall the town")
	var results: Array = stub.sent[1]["messages"][2]["content"]
	_check(results[1]["is_error"] and "stockpile" in str(results[1]["content"]), "a town that is no stockpile place: an error (%s)" % results[1]["content"])
	_check(results[2]["is_error"] and "a cell in from the area" in str(results[2]["content"]), "a ring outside the area: an error (%s)" % results[2]["content"])
	_check(results[3]["is_error"] and "inside it" in str(results[3]["content"]), "a gate not on the border: an error (%s)" % results[3]["content"])
	_check(not results[4]["is_error"] and "36 edges, 4 of them gates" in str(results[4]["content"]), "the wall: %s" % results[4]["content"])
	session.accept()
	_check(doc.map.edge(Terrain.edge_key(Vector2i(8, 9), Vector2i(-1, 0))) == "wall" and doc.map.edge(Terrain.edge_key(Vector2i(13, 8), Vector2i(0, -1))) == "door",
			"walls on the ring, a gate in the middle of the north side")
	var level := Level.parse(doc.map.to_image(), null, doc.config)
	var about := (level["warnings"] as Array).filter(func(warning: String) -> bool: return "town wall" in warning)
	_check(level["town_walls"].size() == 1 and about.is_empty(), "the level reads the square's wall, with nothing to say (%s)" % [about])


func _test_store_checks() -> void:
	print("
== the town's store: what a change does to it, said at once and with the proposal ==")
	var doc := _doc()
	var stub := StubClaude.new([
		[{"name": "stamp", "input": {"prefab": "town_store", "at": [6, 6]}},
			{"name": "place", "input": {"at": [20, 12], "thing": "chest", "use": "shop"}}],
		"A store, and a counter out in the field.",
	])
	var session := BuilderSession.new(doc, Rect2i(5, 5, 20, 12), "test_field", stub)
	var result: Dictionary = await session.ask("a store")
	var results: Array = stub.sent[1]["messages"][2]["content"]
	_check("The town's store now" not in str(results[0]["content"]), "the store stamped whole: nothing to say (%s)" % results[0]["content"])
	_check("The town's store now: the shop counter at (20, 12) does nothing" in str(results[1]["content"]), "a counter outside it: Claude is told (%s)" % results[1]["content"])
	_check(result.get("warnings", []).size() == 1, "and the proposal carries it, for the player (%s)" % [result.get("warnings")])
	_check("Stamp town_store for one" in BuilderSession.system_prompt(), "the prompt says how a town's store is made")


func _test_heights() -> void:
	print("
== heights: a hill, a chest cut off on it and told, stairs up to it, the ghost and the save ==")
	var doc := _doc()
	var stub := StubClaude.new([
		[{"name": "place", "input": {"at": [14, 12], "thing": "chest", "use": "shop"}},  # out of doors only a counter's chest (807)
			{"name": "hill", "input": {"at": [14, 12], "radius": 4, "top": 2}},
			{"name": "stairs", "input": {"at": [14, 17], "up": "north"}},
			{"name": "stairs", "input": {"at": [14, 15], "up": "north"}},
			{"name": "height", "input": {"change": "raise", "cells": [[30, 20]]}},
			{"name": "stairs", "input": {"at": [5, 6], "up": "west"}},
			{"name": "look", "input": {}}],
		"A hill with a chest on top.",
	])
	var session := BuilderSession.new(doc, Rect2i(5, 5, 20, 15), "test_field", stub)
	var result: Dictionary = await session.ask("a hill")
	var results: Array = stub.sent[1]["messages"][2]["content"]
	_check("Heights now: (14, 12) is on a patch" in str(results[1]["content"]), "the hill cuts the chest off: Claude is told (%s)" % results[1]["content"])
	_check("Heights now" not in str(results[2]["content"]) and "Heights now" not in str(results[3]["content"]), "a stair a level: nothing new to say")
	_check("outside the area" in str(results[4]["content"]), "a cell outside the area: left out (%s)" % results[4]["content"])
	_check("outside the area" in str(results[5]["content"]) and "Heights now: the stair at (5, 6) has no cell a level up" in str(results[5]["content"]),
			"a stair whose top is outside the area: its top left out, and Claude is told it climbs nowhere (%s)" % results[5]["content"])
	_check("Heights (0 to 6" in str(results[6]["content"]) and "  12 " in str(results[6]["content"]), "look shows a Heights block")
	_check(result["height_warnings"].size() == 1 and "(5, 6)" in result["height_warnings"][0], "the proposal says only that stair: the top is reached (%s)" % [result["height_warnings"]])
	var message := BuilderHost.proposal_message(session)
	_check(message["heights"].has([14, 12, 2]) and message["cells"].has([14, 17, "stair"]), "the ghost: the top at 2, the stairs")
	_check("Ground has a height, 0 to 6" in BuilderSession.system_prompt(), "the prompt says what heights do")
	session.accept()
	_check(doc.map.heights.get(Vector2i(14, 12)) == 2 and doc.heights_dirty, "accepted: the doc has the hill, height.png to write")
	var level := doc.parsed()
	_check(level["terrain"]["stairs"].get(Vector2i(14, 17)) == Vector2i(0, -1) and level["terrain"]["stairs"].get(Vector2i(14, 15)) == Vector2i(0, -1),
			"the level reads both stairs climbing north")


func _test_roof() -> void:
	print("
== roof: over floor of one height, replacing one under it, refused where the level would leave it out, taken away ==")
	var doc := _doc()
	var stub := StubClaude.new([
		[{"name": "roof", "input": {"rect": {"x": 6, "y": 6, "w": 4, "h": 3}}},
			{"name": "roof", "input": {"rect": {"x": 8, "y": 7, "w": 5, "h": 3}, "ridge": "z"}},
			{"name": "height", "input": {"change": "raise", "cells": [[16, 12]]}},
			{"name": "roof", "input": {"rect": {"x": 15, "y": 11, "w": 3, "h": 3}}},
			{"name": "roof", "input": {"rect": {"x": 2, "y": 2, "w": 3, "h": 3}}},
			{"name": "roof", "input": {"rect": {"x": 6, "y": 14, "w": 3, "h": 3}}},
			{"name": "roof", "input": {"rect": {"x": 6, "y": 14, "w": 1, "h": 1}, "remove": true}},
			{"name": "roof", "input": {"rect": {"x": 6, "y": 14, "w": 3, "h": 3}}},
			{"name": "roof", "input": {"rect": {"x": 20, "y": 6, "w": 3, "h": 3}}},
			{"name": "paint", "input": {"ground": "water", "cells": [[21, 7]]}},
			{"name": "roof", "input": {"rect": {"x": 20, "y": 6, "w": 3, "h": 3}}},
			{"name": "roof", "input": {"rect": {"x": 20, "y": 6, "w": 3, "h": 3}, "remove": true}}],
		"A shelter.",
	])
	var session := BuilderSession.new(doc, Rect2i(5, 5, 20, 15), "test_field", stub)
	await session.ask("a market stall")
	var results: Array = stub.sent[1]["messages"][2]["content"]
	_check(not results[0]["is_error"] and "a shingle roof over x 6-9, y 6-8" in str(results[0]["content"]), "a roof over open floor: %s" % results[0]["content"])
	_check(not results[1]["is_error"] and "replacing 1" in str(results[1]["content"]), "one over part of it replaces it: %s" % results[1]["content"])
	_check(results[3]["is_error"] and "one height" in str(results[3]["content"]), "over a raised cell: refused with the level's words (%s)" % results[3]["content"])
	_check(results[4]["is_error"] and "in the area" in str(results[4]["content"]), "outside the area: refused")
	_check("took away 1 roofs" in str(results[6]["content"]), "remove: %s" % results[6]["content"])
	_check(results[10]["is_error"] and "the roof at (20, 6)" in str(results[10]["content"]),
			"the same rect again over water painted under a roof already left out: refused (%s)" % results[10]["content"])
	var message := BuilderHost.proposal_message(session)
	_check(message.get("roofs", []) == [[8, 7, 5, 3], [6, 14, 3, 3]], "the ghost outlines the roofs it adds (%s)" % [message.get("roofs")])
	_check("roof {" in BuilderSession.grid(session.working.map, session.working.config, session.area, session.area), "the grid lists them")
	session.accept()
	var level := doc.parsed()
	_check(level["roofs"].size() == 2 and level["roofs"][0]["ridge"] == "z" and level["roofs"][1]["ridge"] == "z"
			and (level["warnings"] as Array).filter(func(w: String) -> bool: return "roof" in w).is_empty(), "accepted: the level reads both, ridges as asked, a square one along z")


func _test_prompt() -> void:
	print("\n== what Claude is told ==")
	var system := BuilderSession.system_prompt()
	_check("campfire_camp (7 x 7)" in system and "small_house" in system, "the system prompt lists the prefabs, with their size")
	_check("_ stone" in system and "i imp" in system and "bandaging_kit" in system, "the legend and the items")
	var session := BuilderSession.new(_doc(), Rect2i(5, 5, 12, 10), "test_field", StubClaude.new())
	var situation := session._situation()
	_check("x 5 to 16, y 5 to 14 (12 x 10 cells)" in situation and "outdoors" in situation,
			"the request says where the area is: %s" % situation.get_slice("\n", 0))
	var rows := Array(situation.split("\n")).filter(func(line: String) -> bool:
		return line.length() > 5 and line.left(4).strip_edges().is_valid_int() and line.substr(5).replace(".", "").is_empty())
	_check(rows.size() == 16 and rows[0].length() == 5 + 18, "the grid shows the area and a margin of 3: 16 rows of 18 (%d)" % rows.size())
	var body := session._body()
	_check(body["system"][0].has("cache_control") and body["model"] == "claude-opus-5-5" and body["output_config"]["effort"] == "medium",
			"the request: the system prompt cached, Opus 5.5, effort medium")
	_check((body["tools"] as Array).map(func(tool: Dictionary) -> String: return tool["name"])
			== ["paint", "edges", "stream", "path", "pond", "grove", "scatter", "fence", "height", "hill", "stairs", "place", "stamp", "mark_place", "set_building", "building", "move", "link", "skylight", "decor", "spot", "piece", "town_wall", "roof", "look", "new_area"], "and the tools")


func _test_session() -> void:
	print("\n== a request: tool calls on a working copy, the proposal, accept ==")
	var doc := _doc()
	doc.config["depth"] = 1  # a loot chest goes only in a dungeon (806)
	var stub := StubClaude.new([
		[{"name": "pond", "input": {"rect": {"x": 6, "y": 6, "w": 6, "h": 5}, "seed": 3}},
			{"name": "place", "input": {"at": [14, 12], "thing": "chest", "items": ["bandaging_kit"]}}],
		[{"name": "place", "input": {"at": [13, 8], "thing": "imp", "facing": "west", "idle": {"mode": "gather", "point": [14, 9]}}},
			{"name": "paint", "input": {"ground": "fire", "cells": [[14, 9]]}},
			{"name": "look", "input": {}}],
		"A pond, and an imp warming itself by a fire beside a chest.",
	])
	var session := BuilderSession.new(doc, Rect2i(5, 5, 12, 10), "test_field", stub)
	var before := str(doc.map.cells)
	var result: Dictionary = await session.ask("a pond, and a goblin guarding a chest")
	_check(result["ok"] and str(result["summary"]).begins_with("A pond"), "the tool calls run and it says what it made: %s" % result["summary"])
	_check(str(doc.map.cells) == before and doc.undo_steps.is_empty(), "the level itself is not changed yet")
	var proposal := session.proposal()
	var water: Array = proposal["cells"].keys().filter(func(at: Vector2i) -> bool: return proposal["cells"][at] == "water")
	_check(water.size() >= 4 and proposal["cells"].get(Vector2i(14, 9)) == "fire" and proposal["cells"].get(Vector2i(13, 8)) == "monster_imp"
			and proposal["cells"].get(Vector2i(14, 12)) == "chest", "the proposal: the pond, the fire, the imp, the chest (%d cells)" % proposal["cells"].size())
	_check(proposal["cells"].keys().all(func(at: Vector2i) -> bool: return Rect2i(5, 5, 12, 10).has_point(at)), "every cell of it in the area")
	var imp: Array = proposal["entries"].filter(func(entry: Dictionary) -> bool: return Level._tile(entry["at"]) == Vector2i(13, 8))
	_check(imp.size() == 1 and str(imp[0]["idle"]) == str({"mode": "gather", "point": [14, 9]}) and imp[0]["facing"] == [-1, 0],
			"the imp gathers at the fire, facing west (%s)" % [imp])
	var sent: Dictionary = stub.sent[2]
	var messages: Array = sent["messages"]
	_check(messages.size() == 5 and messages[1]["role"] == "assistant" and messages[2]["content"][0]["type"] == "tool_result",
			"each turn goes back with its tool results, the conversation only added to")
	var looked := str(stub.sent.size())
	_check(stub.sent.size() == 3, "three requests to Claude (%s)" % looked)
	_check(is_equal_approx(result["cost"], 3 * (1000 * 4.0 + 200 * 20.0) / 1000000.0) and session.usage["requests"] == 3,
			"what it cost: three requests at Opus prices, $%.4f" % result["cost"])

	_check(session.accept() and doc.undo_steps.size() == 1, "accepted: laid on the level as one undo step")
	_check(doc.map.cell(Vector2i(13, 8)) == "monster_imp" and Level._tile(doc.entry_of(Vector2i(13, 8))["idle"]["point"]) == Vector2i(14, 9)
			and doc.entry_of(Vector2i(14, 12))["props"]["slots"][0] == "bandaging_kit", "the imp and the chest, settings and all")
	var level := doc.parsed()
	var warnings: Array = level["warnings"].filter(func(warning: String) -> bool: return not warning.begins_with("no player start"))
	_check(warnings.is_empty(), "the game reads it cleanly (%s)" % [warnings])
	_check(session.proposal()["cells"].is_empty(), "and the proposal is empty again")
	doc.undo()
	_check(str(doc.map.cells) == before and doc.entry_of(Vector2i(13, 8)).is_empty(), "the editor's undo takes it all back")


func _test_follow_up_and_errors() -> void:
	print("\n== follow-ups, errors back to Claude, discard ==")
	var doc := _doc()
	var stub := StubClaude.new([
		[{"name": "place", "input": {"at": [30, 20], "thing": "imp"}},
			{"name": "stamp", "input": {"prefab": "small_house", "at": [6, 6]}},
			{"name": "stamp", "input": {"prefab": "no_such", "at": [6, 6]}}],
		"A house.",
	])
	var session := BuilderSession.new(doc, Rect2i(5, 5, 12, 10), "test_field", stub)
	await session.ask("a house")
	var results: Array = stub.sent[1]["messages"][2]["content"]
	_check(results[0]["is_error"] and "outside the area" in str(results[0]["content"]), "a thing outside the area: an error back to Claude (%s)" % results[0]["content"])
	_check(not results[1]["is_error"] and results[2]["is_error"] and "small_house" in str(results[2]["content"]),
			"a prefab that is not there: an error naming the ones that are")
	var first := session.proposal()
	_check(first["cells"].get(Vector2i(8, 7)) == "stone" and doc.map.cell(Vector2i(30, 20)) == "grass", "the house is proposed; nothing outside the area")
	stub.turns = [[{"name": "stamp", "input": {"prefab": "small_house", "at": [10, 8], "turns": 1}}], "Moved it."]
	await session.ask("move it south-east")
	var second := session.proposal()
	_check(second["cells"].get(Vector2i(8, 7)) == null and second["cells"].get(Vector2i(12, 10)) == "stone",
			"a follow-up remakes the proposal from the level as it was")
	var last: Array = stub.sent.back()["messages"]
	_check(str(last[0]) == str(stub.sent[0]["messages"][0]) and "follow-up" in str(last[4]["content"]),
			"in the same conversation, its start unchanged")
	session.discard()
	_check(session.proposal()["cells"].is_empty() and doc.undo_steps.is_empty(), "discarded: nothing proposed, nothing laid")


func _test_spending_limit() -> void:
	print("\n== the spending limit ==")
	var looping: Array = []
	for i in 10:
		looping.append([{"name": "look", "input": {}}])
	var session := BuilderSession.new(_doc(), Rect2i(5, 5, 12, 10), "test_field", StubClaude.new(looping))
	session.max_cost = 0.02
	var result: Dictionary = await session.ask("look forever")
	_check(not result["ok"] and "spending limit" in str(result["error"]) and session.usage["requests"] == 3,
			"a request stops when it passes its limit: %s after %d requests" % [result["error"], session.usage["requests"]])


func _test_new_area() -> void:
	print("
== a new area beyond the edge ==")
	var doc := _doc()
	var area := Rect2i(30, 10, 10, 8)
	var stub := StubClaude.new([
		[{"name": "new_area", "input": {"side": "west", "width": 32, "height": 24, "name": "Nope"}},
			{"name": "new_area", "input": {"side": "east", "width": 32, "height": 24, "name": "Ashen Wood", "description": "a burnt wood", "seed": 4}}],
		"A way east, into the Ashen Wood.",
	])
	doc.config["region"] = "blood_rot_lands"
	var session := BuilderSession.new(doc, area, "test_field", stub)
	_check("touches the map's edge on the east (nothing beyond it yet" in session._situation(), "Claude is told the area touches the east edge, with nothing beyond")
	var result: Dictionary = await session.ask("a new area to the east")
	var results: Array = stub.sent[1]["messages"][2]["content"]
	_check(results[0]["is_error"] and "does not touch the west edge" in str(results[0]["content"]), "a side the area does not touch: an error (%s)" % results[0]["content"])
	_check(result["ok"] and not results[1]["is_error"], "the east edge: done (%s)" % results[1]["content"])
	var proposal := session.proposal()
	var exit := Vector2i(39, 14)
	_check(proposal["cells"].get(exit) == "dirt" and proposal["cells"].get(Vector2i(35, 14)) == "dirt", "a way of dirt out to the edge at %s" % exit)
	_check(proposal.get("config", {}).get("neighbours") == {"east": "ashen_wood"}, "the level names its new neighbour (%s)" % [proposal.get("config")])
	_check(proposal.get("new_area", {}).get("footprint") == Rect2i(40, 0, 32, 24), "and where it lies, past the edge, for the ghost")

	_check(session.accept() and session.created == "ashen_wood" and doc.undo_steps.size() == 1, "accepted: one undo step, the new level made")
	var made := session.created_doc
	_check(made.map.size == Vector2i(32, 24) and made.config.get("neighbours") == {"west": "test_field"}
			and made.config.get("name") == "Ashen Wood" and made.config.get("about") == "a burnt wood" and made.config.get("zone") == "outdoors"
			and made.config.get("region") == "blood_rot_lands",
			"the new level: 32 x 24, joined back on its west, named, outdoors and in the same land as the field it leads from")
	var arrive := WorldMap.arrival("east", exit + Vector2i(1, 0), made.map.size)
	_check(made.map.walkable(arrive) and made.map.walkable(arrive + Vector2i(3, 0)), "walking off the edge at %s arrives on open ground at %s" % [exit, arrive])
	_check(made.map.cell(Vector2i(31, 0)) == "void" and made.map.cell(Vector2i(16, 23)) == "void", "with forest round its other sides")
	var level := Level.parse(made.map.to_image(), null, made.config)
	_check(level["warnings"].is_empty() and level["starts"].size() == 1, "the game reads it cleanly, a start by the way in (%s)" % [level["warnings"]])
	doc.undo()
	_check(not doc.config.has("neighbours") and doc.map.cell(exit) == "grass", "undo takes the way and the neighbour back")
	session.discard()
	stub.turns = [[{"name": "new_area", "input": {"side": "east", "width": 20, "height": 20, "name": "Again"}}], "x"]
	doc.config["neighbours"] = {"east": "somewhere"}
	await session.ask("another")
	var again: Array = stub.sent.back()["messages"][-1]["content"]
	_check(again[0]["is_error"] and "somewhere already" in str(again[0]["content"]), "an edge with a neighbour already: an error")
	session.discard()
	doc.config.erase("neighbours")
	stub.turns = [[{"name": "new_area", "input": {"side": "east", "width": 20, "height": 20, "name": "Prefabs"}}], "x"]
	await session.ask("one more")
	_check(session.proposal().get("new_area", {}).get("name") == "test_field_prefabs",
			"a name of a folder under levels/ that is not a level (prefabs, lore) is not used: %s" % [session.proposal().get("new_area", {}).get("name")])


func _test_monster_kinds() -> void:
	print("\n== monster kinds from data (507): offered, said, drawn, placed with a legend colour ==")
	var kinds := BuilderSession.monster_kinds()
	_check(kinds.has("imp") and kinds.has("brute") and kinds.has("wolf") and kinds.has("rabbit"), "monsters.json's kinds are offered (%s)" % [kinds])
	var own := BuilderSession.monster_kinds({"monsters": {"wraith": {"hp": 3}}})
	_check(own.back() == "wraith" and BuilderSession.things({"monsters": {"wraith": {"hp": 3}}}).get("wraith") == "monster_wraith", "and a level's own kind")
	var chars := BuilderSession.chars({"monsters": {"wraith": {"hp": 3}}})
	var unique := {}
	for meaning: String in chars:
		unique[chars[meaning]] = true
	_check(unique.size() == chars.size() and chars["monster_imp"] == "i" and chars["monster_rabbit"] == "r" and chars["monster_wolf"] == "W",
			"a character each, none shared, the goblins' as they were (%s)" % [chars])
	var place: Dictionary = BuilderSession.tools().filter(func(tool: Dictionary) -> bool: return tool["name"] == "place")[0]
	var offered: Array = place["input_schema"]["properties"]["thing"]["enum"]
	_check(offered.has("wolf") and offered.has("sneak") and offered.has("chest"), "place's enum has every kind and the things (%s)" % [offered])
	var system := BuilderSession.system_prompt()
	_check("- imp: a Blood Rot goblin" in system and "- brute: an orc" in system and "(idles: guard)" in system
			and "- wolf: a wolf, a wild animal: hunts in the wilds, worse at night; hunts rabbit, deer, stag" in system and "W wolf" in system,
			"the prompt says each kind in lore's words or its row's, and how it idles")
	var doc := _doc()
	var stub := StubClaude.new([
		[{"name": "place", "input": {"at": [10, 10], "thing": "wolf"}},
			{"name": "place", "input": {"at": [11, 10], "thing": "wolf"}},
			{"name": "place", "input": {"at": [12, 10], "thing": "dragon"}}],
		"Two wolves.",
	])
	var session := BuilderSession.new(doc, Rect2i(5, 5, 12, 10), "test_field", stub)
	await session.ask("a pair of wolves")
	var results: Array = stub.sent[1]["messages"][2]["content"]
	_check(not results[0]["is_error"] and not results[1]["is_error"] and results[2]["is_error"] and "wolf" in str(results[2]["content"]),
			"wolves placed; a kind there is none of refused, naming the kinds")
	var legend: Dictionary = session.proposal().get("config", {}).get("legend", {})
	_check(legend.keys() == ["monster_wolf"] and Color(str(legend["monster_wolf"])) not in Array(Level.LEGEND.values()).map(func(hex: String) -> Color: return Color(hex)),
			"the proposal gives the wolf a colour of its own in level.json's legend (%s)" % [legend])
	_check(".WW" in BuilderSession.grid(session.working.map, session.working.config, session.area, session.area), "the grid draws them")
	session.accept()
	var reread := LevelMap.from_image(doc.map.to_image(), doc.config)
	_check(reread.cell(Vector2i(10, 10)) == "monster_wolf", "accepted: layout.png holds it, not void")
	var wolves := (doc.parsed()["entities"] as Array).filter(func(spec: Dictionary) -> bool: return spec.get("kind") == "wolf")
	_check(wolves.size() == 2 and wolves[0]["script"] == Level.ANIMAL, "the level spawns two wolves, as animals")


func _test_loot() -> void:
	print("\n== loot (509): the tables offered by name and said with their items ==")
	var place: Dictionary = BuilderSession.tools().filter(func(tool: Dictionary) -> bool: return tool["name"] == "place")[0]
	var tables: Array = place["input_schema"]["properties"]["loot"]["enum"]
	_check(tables == Items.loot_tables().keys() and tables.has("supplies"), "place's loot is an enum of the tables (%s)" % [tables])
	var line := BuilderSession.loot_line()
	_check("supplies (" in line and "ration" in line.get_slice("supplies (", 1).get_slice(")", 0), "the prompt lists each table with its items (%s)" % line)
	_check(line in BuilderSession.system_prompt(), "in the system prompt")
	var doc := _doc()
	doc.config["depth"] = 1  # a loot chest goes only in a dungeon (806)
	var stub := StubClaude.new([
		[{"name": "place", "input": {"at": [10, 10], "thing": "chest", "loot": "supplies"}},
			{"name": "place", "input": {"at": [11, 10], "thing": "chest", "loot": "treasure"}},
			{"name": "place", "input": {"at": [12, 10], "thing": "chest", "items": ["ration", "moonstone"]}}],
		"A chest.",
	])
	var session := BuilderSession.new(doc, Rect2i(5, 5, 12, 10), "test_field", stub)
	await session.ask("a chest of supplies")
	var results: Array = stub.sent[1]["messages"][2]["content"]
	_check(not results[0]["is_error"] and results[1]["is_error"] and "supplies" in str(results[1]["content"])
			and results[2]["is_error"] and "moonstone" in str(results[2]["content"]),
			"a table by name placed; a table or an item there is none of refused, saying what there is")


func _test_stream() -> void:
	print("\n== stream (510): water along its course, a ford, a bridge, its path in level.json ==")
	var doc := _doc()
	var stub := StubClaude.new([
		[{"name": "stream", "input": {"points": [[5, 10], [16, 10]], "width": 2,
				"fords": [[[8, 9], [8, 10], [8, 11], [8, 12]]], "bridges": [[[13, 8], [13, 9], [13, 10], [13, 11], [13, 12], [13, 13]]]}},
			{"name": "height", "input": {"change": "raise", "cells": [[10, 8]]}},
			{"name": "stream", "input": {"points": [[5, 6], [16, 6]], "width": 9,
				"bridges": [[[10, 4], [10, 5], [10, 6], [10, 7], [10, 8]], [[5, 13], [6, 14]]]}},
			{"name": "stream", "input": {"points": [[5, 6], [30, 6]]}},
			{"name": "paint", "input": {"ground": "tall_grass", "cells": [[15, 13]]}}],
		"A stream.",
	])
	var session := BuilderSession.new(doc, Rect2i(5, 5, 12, 10), "test_field", stub)
	await session.ask("a stream with a ford and a bridge")
	var results: Array = stub.sent[1]["messages"][2]["content"]
	_check(not results[0]["is_error"] and "a stream, 2 wide, 12 cells from (5, 10) to (16, 10), 2 fords, 1 bridges" in str(results[0]["content"]),
			"laid: %s" % results[0]["content"])
	var map := session.working.map
	_check(map.cell(Vector2i(6, 10)) == "water" and map.cell(Vector2i(6, 11)) == "water" and map.cell(Vector2i(8, 10)) == "ford"
			and map.cell(Vector2i(8, 12)) == "grass", "two cells wide, the ford where its crossing meets it")
	_check(not results[2]["is_error"] and "a stream, 3 wide" in str(results[2]["content"]) and "two heights" in str(results[2]["content"])
			and "never runs over the stream" in str(results[2]["content"]),
			"the width kept to 3; a bridge Level leaves out (banks of two heights) and one not straight are said, the stream kept (%s)" % results[2]["content"])
	_check(results[3]["is_error"] and "outside the area" in str(results[3]["content"]), "a point outside the area: refused")
	var proposal := session.proposal()
	var streams: Array = proposal.get("config", {}).get("streams", [])
	_check(streams.size() == 2 and (streams[0]["path"] as Array).size() == 12 and streams[0]["path"][0] == [5, 10], "both streams' paths in the proposal's level.json")
	var grid := BuilderSession.grid(map, session.working.config, session.area, session.area)
	_check("=" in grid and "\"" in grid, "the grid draws the ford and the tall grass")
	session.accept()
	var level := doc.parsed()
	var bridges := (level["buildings"] as Array).filter(func(b: Dictionary) -> bool: return b["slot"] == Level.BRIDGE)
	_check((level["terrain"]["streams"] as Array).size() == 2 and bridges.size() == 1 and bridges[0]["cell"] == Vector2i(13, 10),
			"accepted: Level reads both streams and the one bridge, at (13, 10)")


func _test_kind_building() -> void:
	print("\n== a composed kind (511): said in its words, given a use ==")
	var system := BuilderSession.system_prompt()
	_check("building_longhouse_large (" in system and ": a building, longhouse: a longhouse (large)" in system
			and ": a building, cottage: a stone cottage (small)" in system, "each kind's prefab is said in its words and size")
	var doc := _doc()
	var stub := StubClaude.new([
		[{"name": "stamp", "input": {"prefab": "building_cottage_small", "at": [8, 8]}}],
		"A cottage.",
	])
	var session := BuilderSession.new(doc, Rect2i(5, 5, 20, 15), "test_field", stub)
	await session.ask("a cottage")
	var entries: Array = (session.working.config.get("buildings", []) as Array).filter(func(entry: Dictionary) -> bool: return entry.get("kind") == "cottage")
	_check(entries.size() == 1, "stamped: a cottage entry (%s)" % [session.working.config.get("buildings")])
	if entries.is_empty():
		return
	var cell: Vector2i = Level.building_rect(entries[0]).position
	var use: String = BuilderSession.building_uses()[0]
	var answer := session.run_tool("set_building", {"at": [cell.x, cell.y], "use": use})
	_check(answer.get("ok", false) and "the cottage at" in str(answer["text"]) and use in str(answer["text"]),
			"set_building gives a composed building a use, named by its kind (%s)" % answer)


func _test_slopes() -> void:
	print("\n== slopes and rock (510 amended, maps' 513) ==")
	var doc := _doc()
	doc.config["depth"] = 1  # a loot chest goes only in a dungeon (806)
	var stub := StubClaude.new([
		[{"name": "height", "input": {"change": "set", "level": 2, "rects": [{"x": 5, "y": 5, "w": 12, "h": 3}]}},
			{"name": "place", "input": {"at": [8, 6], "thing": "chest", "loot": "supplies"}},
			{"name": "stairs", "input": {"at": [10, 8], "up": "north", "slope": true}},
			{"name": "paint", "input": {"ground": "rock", "cells": [[14, 12]]}}],
		"A bank with a ramp.",
	])
	var session := BuilderSession.new(doc, Rect2i(5, 5, 12, 10), "test_field", stub)
	await session.ask("a bank with a ramp up")
	var results: Array = stub.sent[1]["messages"][2]["content"]
	var map := session.working.map
	_check(not results[2]["is_error"] and "slopes climbing north" in str(results[2]["content"])
			and map.cell(Vector2i(10, 8)) == "slope" and map.cell(Vector2i(10, 9)) == "slope", "a flight of slopes onto the bank (%s)" % results[2]["content"])
	_check(session.height_checks().is_empty() and HeightTools.climbs(map, Vector2i(10, 9)) == Vector2i(0, -1),
			"the slopes climb, so nothing is cut off (%s)" % [session.height_checks()])
	var grid := BuilderSession.grid(map, session.working.config, session.area, session.area)
	_check("/" in grid and "R" in grid and not map.walkable(Vector2i(14, 12)), "the grid draws slopes and rock; rock is not walked")
	session.accept()
	var warnings := (doc.parsed()["warnings"] as Array).filter(func(w: String) -> bool: return "slope" in w)
	_check(warnings.is_empty(), "Level reads the slopes as made (%s)" % [warnings])


func _test_captives() -> void:
	print("\n== captives a camp holds (519, on npc's 518) ==")
	var doc := _doc()
	doc.config["places"] = {"store": {"at": [20, 20], "kind": "stockpile", "holder": "town"}}
	var hold := {"town": "test_field/store", "resident": "the smith's daughter", "name": "Tam"}
	var stub := StubClaude.new([
		[{"name": "mark_place", "input": {"key": "camp", "kind": "camp", "at": [10, 10], "holder": "goblins", "holds": [hold]}},
			{"name": "mark_place", "input": {"key": "camp2", "kind": "camp", "at": [12, 12], "holder": "goblins",
				"holds": [{"town": "nowhere/store", "resident": "Bran"}]}},
			{"name": "mark_place", "input": {"key": "farm", "kind": "farm", "at": [14, 12], "holder": "town", "holds": [hold]}}],
		"A camp holding a captive.",
	])
	var session := BuilderSession.new(doc, Rect2i(5, 5, 20, 20), "test_field", stub)
	await session.ask("a goblin camp holding the smith's daughter")
	_check("Towns a camp may hold captives from: " in str(stub.sent[0]["messages"][0]["content"])
			and "test_field/store" in str(stub.sent[0]["messages"][0]["content"]), "the request lists the towns")
	var results: Array = stub.sent[1]["messages"][2]["content"]
	_check(not results[0]["is_error"] and "holding 1 captives" in str(results[0]["content"]), "a camp holds one: %s" % results[0]["content"])
	_check(results[1]["is_error"] and "no town nowhere/store" in str(results[1]["content"]) and "test_field/store" in str(results[1]["content"]),
			"a town there is none of refused, naming the towns")
	_check(results[2]["is_error"] and "camp only" in str(results[2]["content"]), "holds on a farm refused")
	var places: Dictionary = session.proposal()["config"]["places"]
	_check(places["camp"]["holds"] == [hold] and not places.has("camp2"), "the proposal's level.json has the hold as given")
	_check(BuilderHost.camps_holding(session.working.config) == ["camp"], "the host knows which camps hold captives (to free a gone one's)")
	session.accept()
	var level_places: Dictionary = Level.places_from(doc.config, [] as Array[String])
	var kept: Array = level_places["camp"].get("holds", [])
	_check(kept.size() == 1 and kept[0]["town"] == hold["town"] and kept[0]["resident"] == hold["resident"] and kept[0]["name"] == "Tam",
			"Level keeps the hold (%s)" % [kept])


func _test_work_sites() -> void:
	print("\n== work sites (520, on maps' 517): a town's woodlot, checked held and reached ==")
	var place: Dictionary = BuilderSession.tools().filter(func(tool: Dictionary) -> bool: return tool["name"] == "mark_place")[0]
	var kinds: Array = place["input_schema"]["properties"]["kind"]["enum"]
	_check(kinds.has("woodlot") and kinds.has("hunting_ground") and kinds.has("quarry") and kinds.has("camp"), "mark_place offers Level's kinds (%s)" % [kinds])
	_check("A town's work sites are places too" in BuilderSession.system_prompt(), "the prompt says what a work site is for")
	_check("worked by no one, and the tool's answer says so. A town's woodcutter works the first woodlot marked for it, its hunter" in BuilderSession.system_prompt(), "the prompt says which trade works which site, from economy.json (%s)" % BuilderSession.site_line())
	var doc := _doc()
	doc.config["places"] = {"store": {"at": [20, 20], "kind": "stockpile", "holder": "town"}}
	doc.map.set_cell(Vector2i(4, 8), "void")  # A tree by the woodlot (566).
	var walls := []
	for side in ["north", "east", "south", "west"]:
		walls.append({"at": [8, 8], "side": side, "kind": "wall"})
	var stub := StubClaude.new([
		[{"name": "mark_place", "input": {"key": "woods", "kind": "woodlot", "at": [8, 8], "holder": "town", "town": "store"}},
			{"name": "mark_place", "input": {"key": "pit", "kind": "quarry", "at": [10, 8], "holder": "town", "town": "nowhere"}},
			{"name": "mark_place", "input": {"key": "game", "kind": "hunting_ground", "at": [12, 8], "holder": "goblins", "town": "store"}},
			{"name": "edges", "input": {"set": walls}}],
		"A woodlot.",
	])
	var session := BuilderSession.new(doc, Rect2i(5, 5, 20, 20), "test_field", stub)
	await session.ask("a woodlot for the town")
	var results: Array = stub.sent[1]["messages"][2]["content"]
	_check(not results[0]["is_error"] and "worked by the town of store" in str(results[0]["content"]) and not "Work sites now" in str(results[0]["content"]),
			"a woodlot worked by its town, reached: %s" % results[0]["content"])
	_check(results[1]["is_error"] and "store" in str(results[1]["content"]), "a town that is no stockpile place here: refused, naming the stores")
	_check(not results[2]["is_error"] and "held by goblins, not by its town" in str(results[2]["content"]), "a site the goblins hold: said (%s)" % results[2]["content"])
	_check("woodlot woods at (8, 8) can't be reached on foot" in str(results[3]["content"]), "walled off from its town: said (%s)" % results[3]["content"])
	_check(session.proposal()["config"]["places"]["woods"].get("town") == "store", "the proposal's level.json has its town")
	_check(HeightTools.reaches(doc.map, Vector2i(20, 20), Vector2i(8, 8)) and not HeightTools.reaches(session.working.map, Vector2i(20, 20), Vector2i(8, 8)),
			"HeightTools.reaches: open ground reached, a walled cell not")


func _test_codes() -> void:
	print("\n== building codes (537): stable from level.json, never given again ==")
	var entries := [{"slot": "building.hut", "at": [1, 1]}, {"kind": "house", "at": [8, 1]}, {"slot": "building.shed", "at": [14, 1]}]
	_check(Array(Level.building_codes(entries, {})) == ["H1", "H2", "S1"], "derived in order, a letter each: %s" % [Level.building_codes(entries, {})])
	var config := {"buildings": entries.duplicate(true)}
	_check(Level.fill_codes(config) and config["buildings"][1]["code"] == "H2" and config["building_codes"] == {"H": 2, "S": 1}, "fill_codes writes them in, and the counter")
	config["buildings"].remove_at(0)
	config["buildings"].append({"slot": "building.house", "at": [20, 1]})
	Level.fill_codes(config)
	_check(config["buildings"][0]["code"] == "H2" and config["buildings"][2]["code"] == "H3", "one taken away, one added: the others keep theirs, H1 is not given again (%s)" % [config["buildings"]])
	config["buildings"].append(config["buildings"][0].duplicate())
	Level.fill_codes(config)
	_check(config["buildings"][3]["code"] == "H4", "a copy repeating H2 gets its own")
	_check(not Level.fill_codes(config), "nothing to fill: unchanged")
	var doc := _doc()
	doc.config["places"] = {"store": {"at": [20, 20], "kind": "stockpile", "holder": "town"}}
	var session := BuilderSession.new(doc, Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([]))
	session.run_tool("stamp", {"prefab": "building_hut", "at": [6, 6]})
	session.run_tool("stamp", {"prefab": "building_hut", "at": [12, 6]})
	var codes: Array = session.working.config["buildings"].map(func(entry: Dictionary) -> String: return str(entry.get("code", "")))
	_check(codes == ["H1", "H2"], "two huts stamped from one prefab: H1, H2 (%s)" % [codes])
	var set: Dictionary = session.run_tool("set_building", {"code": "h2", "use": "inn", "town": "store"})
	_check(set["ok"] and session.working.config["buildings"][1].get("use") == "inn", "set_building by code (%s)" % set["text"])
	_check(not session.run_tool("set_building", {"code": "Q9"})["ok"], "a code no building has: refused")
	session.accept()
	_check("Buildings in this level, by code" in session._situation() and "H2 hut at (13, 7)" in session._situation(), "the request lists the codes")
	var parsed := doc.parsed()
	var hut: Dictionary = parsed["buildings"][1]
	_check(hut["code"] == "H2" and BuilderUI.building_words(hut) == "H2 hut", "Level.parse gives each building its code: %s" % BuilderUI.building_words(hut))
	_check(BuilderUI.building_line(hut) == "H2 hut at 13, 7, facing south, use: inn, town: store", "the party log line: %s" % BuilderUI.building_line(hut))
	# How far its town has built it (566), from the "town" message's buildings state.
	hut["town_id"] = "test_field/store"  # As Level.load names a building's town.
	var states := {hut["town_id"]: {"inn": {"state": Towns.PLANNED, "level": 0, "progress": 0.4}}}
	_check(BuilderUI.building_line(hut, states).ends_with("town: store, being built 40%"), "a build under way: %s" % BuilderUI.building_line(hut, states))
	states[hut["town_id"]]["inn"] = {"state": Towns.PLANNED, "level": 0}
	_check(BuilderUI.build_state(hut, states) == "planned", "planned, no job yet")
	states[hut["town_id"]]["inn"] = {"state": Towns.STANDING, "level": 1}
	_check(BuilderUI.build_state(hut, states) == "" and BuilderUI.build_state(hut, {}) == "", "standing, or no record: nothing said")
	states[hut["town_id"]]["inn"] = {"state": Towns.DAMAGED, "level": 1}
	_check(BuilderUI.build_state(hut, states) == "damaged" and BuilderUI.build_state(parsed["buildings"][0], states) == "", "damaged; a building with no use: nothing")
	# The cursor hint: the code only in builder mode (the coordinator's fix to 537).
	var landmark := hut.duplicate()
	landmark["slot"] = "building.tower_ruin"
	_check(BuilderUI.hint_words(hut, states, true) == "H2 hut, damaged" and BuilderUI.hint_words(parsed["buildings"][0], states, true) == "H1 hut"
		and BuilderUI.hint_words(landmark, states, true).begins_with("H2 "), "builder mode: every building by its code")
	_check(BuilderUI.hint_words(hut, states, false) == "hut, damaged", "outside it: a town's building by its plain name and state (%s)" % BuilderUI.hint_words(hut, states, false))
	_check(BuilderUI.hint_words(parsed["buildings"][0], states, false) == "" and BuilderUI.hint_words(landmark, states, false) == "",
		"outside it: a building serving no town, or a solid doorless one, says nothing")
	_check(BuilderUI.building_at(parsed["buildings"], Vector2i(13, 7)) == hut and BuilderUI.building_at(parsed["buildings"], Vector2i(30, 20)).is_empty(), "the building under a cell")
	_check(BuilderUI.coords_text(Vector2i(212, 207), Vector2i(210, 205), Vector2i(-1, -1)) == "212, 207      you 210, 205", "the coordinates line")
	var front: Vector2i = preload("res://main.gd").front_of(hut)
	_check(not (hut["rect"] as Rect2i).has_point(front) and front.y == (hut["rect"] as Rect2i).end.y, "a move to H2 lands at its front: %s" % front)


func _test_solid() -> void:
	print("\n== solid buildings (maps' 550): a mound is walked round, entered at its door, given no use ==")
	_check("A solid building (a mound" in BuilderSession.system_prompt(), "the prompt says what a solid building is")
	var doc := _doc()
	doc.config["buildings"] = [{"slot": "building.mound", "at": [10, 10], "facing": [0, 1]}]
	doc.config["places"] = {"store": {"at": [12, 22], "kind": "stockpile", "holder": "town"},
		"inside": {"at": [11, 11], "kind": "woodlot", "holder": "town", "town": "store"},
		"door": {"at": [15, 22], "kind": "hunting_ground", "holder": "town", "town": "store"},
		"behind": {"at": [12, 6], "kind": "quarry", "holder": "town", "town": "store"}}
	var session := BuilderSession.new(doc, Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([]))
	var ground := session.walk_ground()
	_check((ground.get("solid", {}) as Dictionary).size() == 143 and not ground["solid"].has(Vector2i(15, 21)), "its 144 cells but the door are solid (12 x 12, 579; %d)" % (ground.get("solid", {}) as Dictionary).size())
	var sites := session.site_checks()
	_check(sites.size() == 1 and "woodlot inside at (11, 11) can't be reached" in sites[0], "a site inside the mound can't be reached; its door and the ground behind it can (%s)" % [sites])
	var used: Dictionary = session.run_tool("set_building", {"at": [12, 12], "use": "inn", "town": "store"})
	_check(not used["ok"] and "solid" in str(used["text"]), "no use for a mound (%s)" % used["text"])
	_check(session.run_tool("set_building", {"at": [12, 12]})["ok"], "scenery it may be")
	_check(session.height_checks().is_empty(), "nothing said of a mound on flat ground (%s)" % [session.height_checks()])
	doc.config["buildings"].append({"slot": "building.cairn", "at": [30, 10], "facing": [0, 1]})
	var with_cairn := BuilderSession.new(doc, Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([]))
	var stones: Dictionary = with_cairn.walk_ground().get("solid", {})
	_check(stones.has(Vector2i(30, 10)) and stones.has(Vector2i(31, 11)) and BuilderSession.solid_door(doc.config["buildings"][1]) == Level.NO_DOOR
		and with_cairn.height_checks().is_empty(), "a cairn (567) is solid through, no door, nothing said (%s)" % [with_cairn.height_checks()])


func _test_plots() -> void:
	print("\n== plots (564): listed for the request, a door on the plot's street side, a town's door on a street ==")
	_check("A plot (the request lists those here)" in BuilderSession.system_prompt(), "the prompt says what a plot is")
	var high: int = (Level.building_rect({"slot": "building.hut", "at": [0, 0]}) as Rect2i).size.y
	var doc := _doc()
	doc.config["places"] = {"store": {"at": [12, 22], "kind": "stockpile", "holder": "town"}}
	doc.config["plots"] = [{"key": "p1", "rect": [4, 4, 6, 6], "facing": [0, 1]}, {"rect": [30, 2, 4, 4]}]
	doc.config["roads"] = [{"points": [[0, 15, 2], [39, 15, 2]], "kind": "stone"}]
	doc.config["buildings"] = [
		{"slot": "building.hut", "at": [5, 5], "facing": [0, -1]},
		{"slot": "building.hut", "at": [20, 2], "facing": [0, 1], "use": "inn", "town": "store"},
		{"slot": "building.hut", "at": [28, 14 - high], "facing": [0, 1], "use": "forge", "town": "store"},
		{"slot": "building.hut", "at": [34, 2], "facing": [0, 1]}]
	Level.fill_codes(doc.config)
	_check(BuilderSession.plots_from(doc.config).size() == 1, "a plot with no key is left out")
	var session := BuilderSession.new(doc, Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([]))
	var streets := session.street_checks()
	_check(streets.size() == 2 and "the H1 hut on the plot p1 faces north, but the plot's street is to the south" in streets[0]
		and "the door of the H2 hut at (20, 2) does not open onto a street" in streets[1],
		"a hut turned from its plot's street, an inn far from the road: said; a forge at the road, a hut with no use: not (%s)" % [streets])
	_check(BuilderSession.new(doc, Rect2i(18, 0, 6, 6), "test_field", StubClaude.new([])).street_checks().size() == 1, "only the area's buildings")
	_check("Plots here (ground the town keeps for new buildings): p1 at (4, 4), 6 x 6, its street to the south." in session._situation(), "the request lists the plots")
	doc.config.erase("roads")
	_check(BuilderSession.new(doc, Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([])).street_checks().size() == 1, "no roads in the level: only the plot's side is said")
	(doc.config["plots"] as Array).append({"key": "p2", "rect": [30, 20, 4, 6], "facing": [0, 1]})
	var small := BuilderSession.new(doc, Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([])).street_checks()
	_check(small.size() == 2 and "the plot p2 is 4 x 6: too small for a building, whose room is 5 x 5 at least" in small[0],
		"a plot under Level.MIN_ROOM one way: said (%s)" % [small])
	_check(BuilderSession.new(doc, Rect2i(0, 0, 20, 20), "test_field", StubClaude.new([])).street_checks().size() == 1, "a small plot outside the area: not said")
	var moved := LevelMap.moved_config(doc.config, func(cell: Vector2i) -> Vector2i: return Vector2i(29 - cell.y, cell.x), 1)
	var plot: Dictionary = moved["plots"][0]
	_check(plot["rect"] == [20, 4, 6, 6] and plot["facing"] == [-1, 0], "a quarter turn moves a plot and turns its street side (%s)" % [plot])
	# The towns' laid plots (591 amended), from a stand-in World.clearing.
	var kept_clearing := World.clearing
	World.clearing = Clearing.new()
	World.clearing.lay_plot(Level.zone_of(doc.config), "store", "forge", Rect2i(2, 18, 7, 7), Vector2i(0, 1))
	World.clearing.lay_plot("hills", "store", "inn", Rect2i(10, 18, 7, 7), Vector2i(0, 1))
	(doc.config["plots"] as Array).pop_back()
	(doc.config["buildings"] as Array).append({"slot": "building.hut", "at": [4, 20], "facing": [0, -1]})
	Level.fill_codes(doc.config)
	var laid := BuilderSession.new(doc, Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([]))
	_check(BuilderSession.laid_plots(doc.config).size() == 1 and BuilderSession.laid_plots(doc.config)[0]["rect"] == Rect2i(3, 19, 5, 5),
		"a laid plot of this zone, its footprint inside the ring; another zone's not")
	_check(laid.street_checks().any(func(said: String) -> bool: return "on the plot forge (laid by store) faces north, but the plot's street is to the south" in said),
		"a hut turned from a laid plot's street: said (%s)" % [laid.street_checks()])
	_check("Plots the towns laid here themselves as they grew (their buildings rise there on their own): forge (laid by store) at (3, 19), 5 x 5, its street to the south." in laid._situation(),
		"the request lists the laid plots apart")
	World.clearing.lay_plot(Level.zone_of(doc.config), "store", "barn", Rect2i(30, 20, 5, 6), Vector2i(0, 1))
	_check(laid.street_checks().any(func(said: String) -> bool: return "the plot barn (laid by store) is 3 x 4: too small" in said), "a laid plot under Level.MIN_ROOM: said")
	World.clearing = kept_clearing


func _test_visible_work() -> void:
	print("\n== visible work (566, builder's side): somewhere to stand at a woodlot, builds with no site listed ==")
	_check("a woodlot needs such a cell within its radius" in BuilderSession.system_prompt(), "the prompt says where a woodcutter stands")
	var doc := _doc()
	doc.config["places"] = {"store": {"at": [20, 20], "kind": "stockpile", "holder": "town"},
		"woods": {"at": [10, 10], "kind": "woodlot", "holder": "town", "town": "store", "radius": 3},
		"game": {"at": [30, 20], "kind": "hunting_ground", "holder": "town", "town": "store", "radius": 2}}
	var session := BuilderSession.new(doc, Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([]))
	var sites := session.site_checks()
	_check(sites.size() == 1 and "the woodlot woods at (10, 10) has no walkable cell beside the forest within its radius 3" in sites[0], "a woodlot in open grass: no tree to fell (%s)" % [sites])
	session.working.map.set_cell(Vector2i(13, 11), "void")
	session.working.revision += 1
	_check(session.site_checks().is_empty(), "a tree 3 cells off, its neighbour inside the radius: somewhere to stand")
	session.working.map.set_cell(Vector2i(13, 11), "grass")
	session.working.map.set_cell(Vector2i(14, 12), "void")
	session.working.revision += 1
	_check(session.site_checks().size() == 1, "a tree whose neighbours are all past the radius: not")
	session.working.config["outdoor"] = false
	session.working.revision += 1
	_check(session.stand_problem(Level.places_from(session.working.config, [] as Array[String])["woods"]).begins_with("the woodlot woods is not outdoors"), "a woodlot indoors: no trees")
	# Builds in hand with no building marked for them.
	doc = _doc()
	doc.config["places"] = {"store": {"at": [20, 20], "kind": "stockpile", "holder": "town"}}
	doc.config["buildings"] = [{"slot": "building.hut", "at": [6, 6], "use": "forge", "town": "store"}]
	session = BuilderSession.new(doc, Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([]))
	var towns := Towns.new()
	towns.from_dict({"test_field/store": {"buildings": {
		"inn": {"kind": "inn", "level": 0, "state": Towns.PLANNED, "job": 3},
		"forge": {"kind": "forge", "level": 0, "state": Towns.PLANNED, "job": 4},
		"loom": {"kind": "loom", "level": 1, "state": Towns.BUILDING, "job": 5},
		"well": {"kind": "well", "level": 1, "state": Towns.STANDING, "job": 0},
		"walls": {"kind": "walls", "level": 0, "state": Towns.PLANNED, "job": 6}}}})
	session.towns = towns
	_check(Array(session.builds_without_site()) == ["store: inn, loom"], "the inn and the loom have no site; the forge has, the well stands, the wall is no building (%s)" % [session.builds_without_site()])
	_check("Builds the towns here have in hand with no building marked for them yet (place one, on a plot first, and set_building it to the use): store: inn, loom." in session._situation(), "the request lists them")
	session.towns = null
	_check(session.builds_without_site().is_empty(), "no towns' records: nothing listed")


func _test_narrow_ways() -> void:
	print("\n== no way one cell wide (600 amended): named in the tool's answer ==")
	_check("a doorway is the one cell allowed" in BuilderSession.system_prompt(), "the prompt says ways are two cells wide")
	var doc := _doc()
	for y in range(5, 10):
		doc.map.set_edge(Terrain.edge_key(Vector2i(10, y), Vector2i.RIGHT), "wall")
		doc.map.set_edge(Terrain.edge_key(Vector2i(11, y), Vector2i.RIGHT), "wall")
	var session := BuilderSession.new(doc, Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([]))
	_check(session.narrow_ways() == [Vector2i(11, 5), Vector2i(11, 6), Vector2i(11, 7), Vector2i(11, 8), Vector2i(11, 9)],
		"a lane between two walls a cell apart (%s)" % [session.narrow_ways()])
	_check(session.street_checks().any(func(warning: String) -> bool: return warning.begins_with("a way one cell wide at (11, 5), (11, 6)")), "said in the street checks")
	_check(BuilderSession.new(doc, Rect2i(20, 0, 20, 30), "test_field", StubClaude.new([])).narrow_ways().is_empty(), "only the area's")
	for y in range(5, 10):
		doc.map.set_edge(Terrain.edge_key(Vector2i(11, y), Vector2i.RIGHT), "clear")
		doc.map.set_edge(Terrain.edge_key(Vector2i(12, y), Vector2i.RIGHT), "wall")
	_check(BuilderSession.new(doc, Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([])).narrow_ways().is_empty(), "two cells apart: none")


func _test_old_tower() -> void:
	print("\n== the Old Tower (600): ways in at the gate and the breach, the room's door, the counter, the tower and the stone solid ==")
	var prefab := Prefab.load_prefab("old_tower")
	_check(prefab["map"].size == Vector2i(17, 17), "17 x 17 (%s)" % [prefab["map"].size])
	var level := Level.parse(prefab["map"].to_image(), null, prefab["config"])
	var floor := {}
	for cell: Vector2i in level["terrain"]["floor"]:
		floor[cell] = true
	var edges: Dictionary = level["terrain"]["edges"]
	# Who can walk where from a cell, through open edges and doors.
	var reach := func(from: Vector2i, closed: Array) -> Dictionary:
		var seen := {from: true}
		var queue: Array[Vector2i] = [from]
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_front()
			for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next := cell + step
				var key := Terrain.edge_key(cell, step)
				if floor.has(next) and not seen.has(next) and edges.get(key) != Terrain.Edge.WALL and key not in closed:
					seen[next] = true
					queue.append(next)
		return seen
	var inside: Dictionary = reach.call(Vector2i(8, 12), [])
	_check(inside.has(Vector2i(16, 8)) and inside.has(Vector2i(12, 0)) and inside.has(Vector2i(5, 3)),
		"from the yard: out at the gate, out at the breach, and in at the door to Snagfin's place behind the counter")
	var gate_shut := [Terrain.edge_key(Vector2i(15, 7), Vector2i.RIGHT), Terrain.edge_key(Vector2i(15, 8), Vector2i.RIGHT),
		Terrain.edge_key(Vector2i(15, 9), Vector2i.RIGHT), Terrain.edge_key(Vector2i(12, 1), Vector2i.UP), Terrain.edge_key(Vector2i(13, 1), Vector2i.UP)]
	_check(not reach.call(Vector2i(8, 12), gate_shut).has(Vector2i(16, 12)), "the gate and the breach shut: the curtain holds all round")
	_check(not floor.has(Vector2i(1, 1)) and not floor.has(Vector2i(9, 11)) and not floor.has(Vector2i(15, 6)), "the tower, the column and the rubble are solid")
	# No way one cell wide (Jeff, 2026-10-22: players walk with companions):
	# no cell inside the curtain shut in on both sides, across or along.
	var shut := func(cell: Vector2i, step: Vector2i) -> bool:
		return not floor.has(cell + step) or edges.get(Terrain.edge_key(cell, step)) == Terrain.Edge.WALL
	var narrow: Array[Vector2i] = []
	for y in range(1, 16):
		for x in range(1, 16):
			var cell := Vector2i(x, y)
			if floor.has(cell) and ((shut.call(cell, Vector2i.LEFT) and shut.call(cell, Vector2i.RIGHT)) or (shut.call(cell, Vector2i.UP) and shut.call(cell, Vector2i.DOWN))):
				narrow.append(cell)
	_check(narrow.is_empty(), "no way one cell wide in the yard or the room (%s)" % [narrow])
	var room: Array = level["buildings"].filter(func(b: Dictionary) -> bool: return b.get("kind") == "tower_room")
	_check(room.size() == 1 and room[0]["front"] == Vector2i(5, 9), "the roofed room's door opens onto the path (%s)" % [room])
	_check(level["entities"].any(func(e: Dictionary) -> bool: return e["tile"] == Vector2i(5, 4) and e["script"] == Level.CHEST), "the counter at the room's back")
	_check(level["places"].has("old_tower") and level["places"]["old_tower"]["kind"] == "fort", "its place, a fort")


func _test_relief() -> void:
	print("\n== relief (527, on maps' 525): pads flat, cliffs cut ways, height tools refused ==")
	_check("a rise of more than 0.45 m between neighbours is a cliff" in BuilderSession.system_prompt(), "the prompt says what relief means")
	var size := Vector2i(40, 30)
	var field := PackedFloat32Array()
	field.resize(size.x * size.y)
	for y in size.y:
		for x in size.x:
			# A plateau 2 m up east of x 24, a gentle 0.3 m rise at x 15, a 0.1 m bump at (7, 7).
			field[y * size.x + x] = 2.0 if x >= 25 else 0.3 if x >= 15 else 0.0
	field[7 * size.x + 7] = 0.1
	var doc := _doc()
	doc.map.relief = field
	doc.map.set_cell(Vector2i(18, 27), "void")  # A tree by the woodlot (566).
	doc.config["places"] = {"store": {"at": [10, 20], "kind": "stockpile", "holder": "town"},
		"woods": {"at": [18, 20], "kind": "woodlot", "holder": "town", "town": "store"},
		"high": {"at": [30, 20], "kind": "hunting_ground", "holder": "town", "town": "store"}}
	var session := BuilderSession.new(doc, Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([]))
	var bumpy: Dictionary = session.run_tool("stamp", {"prefab": "building_hut", "at": [6, 6]})
	_check(not bumpy["ok"] and "is not flat: (7, 7) is +0.10 m off the rest" in str(bumpy["text"]), "a hut over a 0.1 m bump: refused, naming the cell (%s)" % bumpy["text"])
	var cut: Dictionary = session.run_tool("stamp", {"prefab": "building_hut", "at": [6, 6], "pad": true})
	_check(cut["ok"] and "the ground cut flat under it" in str(cut["text"]) and session.pad_problem(session.working.config["buildings"][0]).is_empty(),
		"stamped with pad: the ground cut flat under it (%s)" % cut["text"])
	_check(is_equal_approx(session.doc.map.relief_at(Vector2i(7, 7)), 0.1) and session.proposal().get("relief", {}).has(Vector2i(7, 7)),
		"the cut is the working copy's, and in the proposal")
	_check(not (session.proposal().get("relief", {}) as Dictionary).keys().any(func(cell: Vector2i) -> bool: return not Rect2i(4, 4, 10, 10).has_point(cell)),
		"only under the hut and its apron")
	session.working.undo()
	session.working.undo()
	var flat: Dictionary = session.run_tool("stamp", {"prefab": "building_hut", "at": [2, 12]})
	_check(flat["ok"] and (session.working.config.get("buildings", []) as Array).size() == 1, "on flat ground: stamped (%s)" % flat["text"])
	var sites := session.site_checks()
	_check(sites.size() == 1 and "hunting_ground high at (30, 20) can't be reached on foot" in sites[0],
		"a 0.3 m rise is walked, a 1.7 m cliff is not (%s)" % [sites])
	_check(HeightTools.reaches(session.working.map, Vector2i(10, 20), Vector2i(30, 20)), "with no relief the same ground is one height: reached")
	var heights := session.height_checks()
	_check(heights.size() == 1 and "(30, 5) is on a patch of 450 cells at 2.00 m with cliffs round it" in heights[0], "the brute up on the plateau: said (%s)" % [heights])
	var hill: Dictionary = session.run_tool("hill", {"at": [20, 10]})
	_check(not hill["ok"] and "shaped in metres" in str(hill["text"]), "hill refused on a relief level (%s)" % hill["text"])
	_check(not session.run_tool("height", {"change": "raise", "cells": [[3, 3]]})["ok"], "height refused too")
	var grid := BuilderSession.grid(session.working.map, session.working.config, Rect2i(20, 20, 10, 1), session.area, session.relief())
	_check("in half metres" in grid and "  20 111114444" in grid, "the grid's Heights are half metres (%s)" % grid)
	_check(BuilderSession.new(_doc(), Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([])).run_tool("hill", {"at": [20, 10]})["ok"],
		"a level with no relief keeps hill")


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


func _test_new_kinds() -> void:
	print("
== 792: the new kinds' places, buildings, markers and links, placed and moved ==")
	var doc := _doc()
	var session := BuilderSession.new(doc, Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([]))
	# mark_place: a post's rect and brazier, held by any faction.
	var post := session.run_tool("mark_place", {"key": "post_road", "kind": "other", "at": [10, 10], "holder": "orcs",
		"rect": {"x": 9, "y": 9, "w": 3, "h": 3}, "brazier": [10, 10], "seats": [[9, 9], [11, 11]], "radius": 1})
	var places: Dictionary = session.working.config.get("places", {})
	_check(post.get("ok", false) and places.get("post_road", {}).get("rect") == [9, 9, 3, 3] and places["post_road"].get("brazier") == [10, 10]
		and places["post_road"].get("seats") == [[9, 9], [11, 11]] and places["post_road"].get("holder") == "orcs",
		"mark_place keeps a rect, a brazier and seats, held by the orcs (%s)" % [places.get("post_road")])
	var outside := session.run_tool("mark_place", {"key": "post_two", "kind": "other", "at": [20, 10], "holder": "town",
		"rect": {"x": 19, "y": 9, "w": 3, "h": 3}, "brazier": [25, 10]})
	_check(not outside.get("ok", true) and "outside the rect" in str(outside.get("text")), "a brazier outside its rect: refused (%s)" % outside)
	var elves := session.run_tool("mark_place", {"key": "elf", "kind": "camp", "at": [12, 12], "holder": "elves"})
	_check(not elves.get("ok", true) and "orcs" in str(elves.get("text")), "a holder that is no faction: refused, naming them (%s)" % elves)
	var holders: Array = BuilderSession.tools().filter(func(tool: Dictionary) -> bool: return tool["name"] == "mark_place")[0]["input_schema"]["properties"]["holder"]["enum"]
	_check("orcs" in holders and "nobody" in holders, "Claude is offered every faction (%s)" % [holders])
	# move a place: its cell, rect, brazier and seats together.
	var moved := session.run_tool("move", {"place": "post_road", "by": [5, 0]})
	places = session.working.config.get("places", {})
	_check(moved.get("ok", false) and places["post_road"].get("at") == [15, 10] and places["post_road"].get("rect") == [14, 9, 3, 3]
		and places["post_road"].get("brazier") == [15, 10] and places["post_road"].get("seats") == [[14, 9], [16, 11]],
		"move: the post goes 5 east with its rect, brazier and seats (%s)" % [places.get("post_road")])
	# building: a camp built facing north, its place beside it, moved, taken away.
	var built := session.run_tool("building", {"kind": "camp", "size": "small", "at": [4, 18], "facing": "north"})
	var camps: Array = (session.working.config.get("buildings", []) as Array).filter(func(entry: Dictionary) -> bool: return entry.get("kind") == "camp")
	_check(built.get("ok", false) and camps.size() == 1 and camps[0].get("facing") == [0, -1], "building: a small camp, its front north (%s; %s)" % [built, camps])
	if camps.size() != 1:
		return
	var rect: Rect2i = Level.building_rect(camps[0])
	var fire := rect.position + rect.size / 2
	var kept := session.run_tool("mark_place", {"key": "road_camp", "kind": "camp", "at": [fire.x, fire.y], "holder": "orcs", "radius": 3, "mix": "bandit"})
	_check(kept.get("ok", false) and session.working.config["places"]["road_camp"].get("mix") == "bandit", "a forest camp's mix (%s)" % kept)
	_check(not session.run_tool("mark_place", {"key": "post_mix", "kind": "other", "at": [20, 12], "holder": "town", "mix": "bandit"}).get("ok", true), "mix on a place not a camp: refused")
	var walls_before := Level.blocks_outline(Level._union(Level.building_blocks(camps[0]))).filter(func(key: Vector3i) -> bool: return session.working.map.edge(key) != "")
	var shifted := session.run_tool("move", {"building": str(camps[0]["code"]), "by": [6, 0]})
	camps = (session.working.config.get("buildings", []) as Array).filter(func(entry: Dictionary) -> bool: return entry.get("kind") == "camp")
	places = session.working.config.get("places", {})
	_check(shifted.get("ok", false) and camps.size() == 1 and Level.building_rect(camps[0]).position == rect.position + Vector2i(6, 0)
		and places["road_camp"].get("at") == [fire.x + 6, fire.y], "move: the camp goes 6 east, its place with it (%s; %s)" % [shifted, places.get("road_camp")])
	var old_left := walls_before.filter(func(key: Vector3i) -> bool: return session.working.map.edge(key) != "" and session.working.map.edge(key) != "clear")
	_check(old_left.size() < walls_before.size() or walls_before.is_empty(), "its old walls are gone (%d of %d left)" % [old_left.size(), walls_before.size()])
	var level := Level.parse(session.working.map.to_image(), null, session.working.config)
	_check(level["buildings"].size() == 1, "the level reads the moved camp (%s)" % [level["warnings"]])
	var gone := session.run_tool("building", {"remove": true, "code": str(camps[0]["code"])})
	_check(gone.get("ok", false) and (session.working.config.get("buildings", []) as Array).is_empty(), "building remove: the camp taken away (%s)" % gone)
	# move a marker: the brute at (30, 5), its entry with it, grass left behind.
	var walked := session.run_tool("move", {"at": [30, 5], "to": [32, 6]})
	_check(walked.get("ok", false) and session.working.map.cell(Vector2i(32, 6)) == "monster_brute" and session.working.map.cell(Vector2i(30, 5)) == "grass"
		and session.working.entry_of(Vector2i(32, 6)).get("idle") == "guard", "move: a monster marker and its entry, grass behind it (%s)" % walked)
	var into := session.run_tool("move", {"at": [32, 6], "to": [45, 6]})
	_check(not into.get("ok", true), "a move out of the area: refused (%s)" % into)
	# link: a way to the wilds, its arrival point beside it; moved together.
	var bad := session.run_tool("link", {"at": [20, 20], "to_map": "wilds", "to_spawn": "nowhere"})
	_check(not bad.get("ok", true) and "from_hills" in str(bad.get("text")), "a spawn point the level lacks: refused, naming its own (%s)" % bad)
	var way := session.run_tool("link", {"at": [20, 20], "to_map": "wilds", "to_spawn": "from_hills", "arrive": [21, 20]})
	_check(way.get("ok", false) and session.working.link_of(Vector2i(20, 20)).get("to_spawn") == "from_hills"
		and session.working.config.get("spawn_points", {}).get("from_wilds") == [21, 20], "link: a way to the wilds and where folk arrive (%s)" % way)
	var door := session.run_tool("move", {"at": [20, 20], "by": [0, 2]})
	_check(door.get("ok", false) and session.working.link_of(Vector2i(20, 22)).get("to_map") == "wilds" and session.working.link_of(Vector2i(20, 20)).is_empty()
		and session.working.config.get("spawn_points", {}).get("from_wilds") == [21, 22], "move: the lair door and its arrival point 2 south (%s)" % door)
	# A way shut and opened where it stands; laid again, it keeps its other keys.
	var shut := session.run_tool("link", {"at": [20, 22], "closed": true})
	_check(shut.get("ok", false) and session.working.link_of(Vector2i(20, 22)).get("closed") == true
		and session.working.link_of(Vector2i(20, 22)).get("to_spawn") == "from_hills", "link: shut, still to the wilds (%s)" % shut)
	var opened := session.run_tool("link", {"at": [20, 22], "closed": false})
	_check(opened.get("ok", false) and not session.working.link_of(Vector2i(20, 22)).has("closed")
		and session.working.link_of(Vector2i(20, 22)).get("to_map") == "wilds", "link: opened (%s)" % opened)
	_check(not session.run_tool("link", {"at": [25, 25], "closed": false}).get("ok", true), "opening a cell with no way: refused")
	var marked := session.working.link_of(Vector2i(20, 22)).duplicate(true)
	marked["cue"] = "sealed"
	marked["closed"] = true
	session.working.apply_changes({"cells": {}, "covers": [Vector2i(20, 22)], "links": [marked]})
	session.run_tool("link", {"at": [20, 22], "to_map": "wilds", "to_spawn": "from_hills"})
	_check(session.working.link_of(Vector2i(20, 22)).get("cue") == "sealed" and session.working.link_of(Vector2i(20, 22)).get("closed") == true,
		"a way laid again keeps its cue and stays shut (%s)" % [session.working.link_of(Vector2i(20, 22))])
	session.run_tool("move", {"at": [20, 22], "by": [1, 0]})
	_check(session.working.link_of(Vector2i(21, 22)).get("cue") == "sealed" and session.working.link_of(Vector2i(21, 22)).get("closed") == true,
		"a way moved keeps its cue and stays shut (%s)" % [session.working.link_of(Vector2i(21, 22))])
	var looked := session.run_tool("link", {"at": [21, 22], "cue": "down"})
	_check(looked.get("ok", false) and session.working.link_of(Vector2i(21, 22)).get("cue") == "down" and session.working.link_of(Vector2i(21, 22)).get("closed") == true,
		"link: its cue set where it stands, still shut (%s)" % looked)
	session.run_tool("link", {"at": [21, 22], "cue": ""})
	_check(not session.working.link_of(Vector2i(21, 22)).has("cue"), "an empty cue: worked out again")
	_check(not session.run_tool("link", {"at": [21, 22], "cue": "portal"}).get("ok", true), "a cue not in Level.CUES: refused")
	# skylight (797): indoors only, its radius 1..4, moved and closed.
	var sky := session.run_tool("skylight", {"at": [6, 6]})
	_check(not sky.get("ok", true) and "outdoors" in str(sky.get("text")), "a skylight outdoors: refused (%s)" % sky)
	session.working.config.erase("outdoor")
	session.working.revision += 1
	_check(not session.run_tool("skylight", {"at": [6, 6], "radius": 6}).get("ok", true), "a skylight's radius past 4: refused")
	sky = session.run_tool("skylight", {"at": [6, 6], "radius": 3})
	var warnings: Array[String] = []
	var read := Level.skylights_from(session.working.config, warnings)
	_check(sky.get("ok", false) and read.size() == 1 and read[0]["at"] == Vector2i(6, 6) and read[0]["radius"] == 3.0 and warnings.is_empty(),
		"skylight: a gap at (6, 6), radius 3, as the level reads it (%s)" % [read])
	session.run_tool("skylight", {"at": [6, 6], "radius": 2})
	_check((session.working.config["skylights"] as Array).size() == 1 and session.working.config["skylights"][0]["radius"] == 2.0, "a skylight on the same cell is replaced")
	var slid := session.run_tool("move", {"skylight": [6, 6], "to": [8, 7]})
	_check(slid.get("ok", false) and session.working.config["skylights"][0]["at"] == [8, 7], "move: the skylight to (8, 7) (%s)" % slid)
	var closed := session.run_tool("skylight", {"at": [8, 7], "remove": true})
	_check(closed.get("ok", false) and (session.working.config["skylights"] as Array).is_empty(), "skylight remove: the gap closed (%s)" % closed)
	_check(BuilderSession.system_prompt() != "", "the prompt still builds")


## 792's follow-up: 774's real entries in the wilds (posts, the tavern, the
## square's fire, the inn), read from levels/wilds/level.json and never written.
func _test_umbrage_kinds() -> void:
	print("
== 792: Umbrage's posts, tavern, fire and inn (774) as builder mode moves them ==")
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://levels/wilds/level.json"))
	_check(config is Dictionary, "the wilds' level.json reads")
	if not config is Dictionary:
		return
	var places: Dictionary = config.get("places", {})
	var shaped := places.keys().filter(func(key: String) -> bool: return places[key] is Dictionary and str(places[key].get("kind")) in ["post", "tavern", "fire"])
	_check(shaped.size() >= 3, "774's posts, tavern and fire are there (%s)" % [shaped])
	var moved := {}
	for key: String in shaped:
		var place: Dictionary = BuilderSession._place_moved(places[key], Vector2i(2, -1))
		moved[key] = place
		var shifted := true
		for shape_key: String in Level.PLACE_SHAPES:
			if not places[key].has(shape_key):
				continue
			var was: Variant = places[key][shape_key]
			var now: Variant = place[shape_key]
			match Level.PLACE_SHAPES[shape_key]:
				"cell":
					shifted = shifted and now == [int(was[0]) + 2, int(was[1]) - 1]
				"rect":
					shifted = shifted and now == [int(was[0]) + 2, int(was[1]) - 1, int(was[2]), int(was[3])]
				"cells":
					for i: int in (was as Array).size():
						shifted = shifted and now[i] == [int(was[i][0]) + 2, int(was[i][1]) - 1]
		_check(shifted and place["at"] == [int(places[key]["at"][0]) + 2, int(places[key]["at"][1]) - 1], "%s moves with every shape it has (%s)" % [key, place])
	var warnings: Array[String] = []
	var all_moved := places.duplicate(true)
	all_moved.merge(moved, true)
	var read := Level.places_from({"places": all_moved}, warnings)
	_check(warnings.is_empty() and shaped.all(func(key: String) -> bool: return read.has(key) and (moved[key].has("rect") == read[key].has("rect"))),
		"the level reads them back moved, shapes and all (%s)" % [warnings])
	_check("post" in Level.PLACE_KINDS and "tavern" in Level.PLACE_KINDS and "fire" in Level.PLACE_KINDS, "mark_place offers post, tavern and fire")
	var kinds: Array = BuilderSession.tools().filter(func(tool: Dictionary) -> bool: return tool["name"] == "building")[0]["input_schema"]["properties"]["kind"]["enum"]
	var inns := (config.get("buildings", []) as Array).filter(func(entry: Dictionary) -> bool: return entry.get("kind") == "inn")
	_check(not inns.is_empty() and "inn" in kinds, "the building tool offers the inn's kind (%d in the wilds)" % inns.size())


## 792 amended: lore's line for each kind, the new cues said, the apex
## bosses drawn but never placed.
func _test_kind_lines() -> void:
	print("
== 792 amended: lore's lines for the kinds, the new cues, no apex placed ==")
	var prompt := BuilderSession.system_prompt()
	var tools := JSON.stringify(BuilderSession.tools())
	print("  (the prompt %d characters, the tools %d: about %d tokens a request together, at 4 a token)" % [prompt.length(), tools.length(), (prompt.length() + tools.length()) / 4])
	_check((prompt.length() + tools.length()) / 4 <= PREFIX_CEILING_TOKENS, "the prompt and tools stay under the coordinator's ceiling of %d tokens (%d)" % [PREFIX_CEILING_TOKENS, (prompt.length() + tools.length()) / 4])
	var apex := ["great_bear", "old_wolf", "boar_king"]
	_check(apex.all(func(kind: String) -> bool: return BuilderSession.is_apex(kind)), "the great bear, the old grey and the boar king are apex")
	var offered: Array = BuilderSession.tools().filter(func(tool: Dictionary) -> bool: return tool["name"] == "place")[0]["input_schema"]["properties"]["thing"]["enum"]
	_check(not apex.any(func(kind: String) -> bool: return kind in offered) and "wolf" in offered and "skeleton" in offered, "place offers no apex, still the wolf and the skeleton")
	_check(apex.all(func(kind: String) -> bool: return BuilderSession.chars().has("monster_" + kind)), "the grid still draws one where it stands")
	_check(not apex.any(func(kind: String) -> bool: return ("- %s:" % kind) in prompt), "the prompt's monster lines leave them out")
	_check("one of the barrow's dead, angry at being disturbed" in prompt and "an outlaw from the forest's camps" in prompt and "lies up in the rocks" in prompt,
		"the prompt has lore's lines (the skeleton, the bandit, the hill cat)")
	var unsaid := BuilderSession.monster_kinds().filter(func(kind: String) -> bool: return not BuilderSession.is_apex(kind) and not BuilderSession.KIND_WORDS.has(kind))
	if not unsaid.is_empty():
		print("  (kinds with no line of lore's yet, said by their label: %s)" % [unsaid])
	var session := BuilderSession.new(_doc(), Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([]))
	var bear := session.run_tool("place", {"at": [10, 10], "thing": "great_bear"})
	_check(not bear.get("ok", true) and "one of a kind" in str(bear.get("text")) and "great bear" in str(bear.get("text")),
		"a request naming the great bear is refused in words (%s)" % bear)
	_check(not session.working.config.get("entities", []).any(func(entry: Variant) -> bool: return entry is Dictionary and str(entry.get("at")) == str([10, 10])),
		"and nothing is laid")
	var cue: String = BuilderSession.tools().filter(func(tool: Dictionary) -> bool: return tool["name"] == "link")[0]["input_schema"]["properties"]["cue"]["description"]
	_check("thicket" in cue and "den" in cue and "mine" in cue, "the link's cue says thicket, den and mine")


## Hollowfell's workings (790) as builder mode places and moves it: a plain
## place, its key kept, its cell moved (the coordinator's job, dungeon's plan).
func _test_workings() -> void:
	print("
== 790: Hollowfell's workings, placed and moved in builder mode ==")
	var kinds: Array = BuilderSession.tools().filter(func(tool: Dictionary) -> bool: return tool["name"] == "mark_place")[0]["input_schema"]["properties"]["kind"]["enum"]
	_check("workings" in kinds, "mark_place offers the workings kind")
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://levels/hills/level.json"))
	_check(config is Dictionary and config.get("places", {}).get("hollowfell", {}).get("kind") == "workings", "the hills hold Hollowfell's workings")
	if not config is Dictionary:
		return
	var real: Dictionary = config["places"]["hollowfell"]
	var session := BuilderSession.new(_doc(), Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([]))
	var placed := session.run_tool("mark_place", {"key": "hollowfell", "kind": "workings", "at": [10, 10],
		"radius": int(real.get("radius", 3)), "holder": str(real.get("holder", "goblins")), "name": str(real.get("name", "Hollowfell"))})
	var places: Dictionary = session.working.config.get("places", {})
	_check(placed.get("ok", false) and places.get("hollowfell", {}).get("kind") == "workings" and places["hollowfell"].get("holder") == real.get("holder"),
		"mark_place lays a workings like the hills' (%s)" % [places.get("hollowfell", placed)])
	var moved := session.run_tool("move", {"place": "hollowfell", "by": [3, 2]})
	places = session.working.config.get("places", {})
	_check(moved.get("ok", false) and places.keys().filter(func(key: String) -> bool: return places[key].get("kind") == "workings") == ["hollowfell"]
		and places["hollowfell"].get("at") == [13, 12] and places["hollowfell"].get("name") == real.get("name"),
		"move: the workings goes 3 east, 2 south, its key, name and holder kept (%s)" % [places.get("hollowfell", moved)])
	var warnings: Array[String] = []
	var read := Level.places_from({"places": {"hollowfell": BuilderSession._place_moved(real, Vector2i(1, 1))}}, warnings)
	_check(warnings.is_empty() and read.has("hollowfell"), "the hills' own entry, moved, reads back (%s)" % [warnings])


## mark_place's own cells (792 amended (2)): a refuge's where (needed), a
## shown name, a trader's bed and facing, a perch's watch (named near a road),
## each on its own kind only; move carries them and a lair's den; marking a
## place again keeps the fields builder mode doesn't write.
func _test_place_cells() -> void:
	print("
== 792 amended (2): a refuge's where, a trader's bed and facing, a perch's watch ==")
	var props: Dictionary = BuilderSession.tools().filter(func(tool: Dictionary) -> bool: return tool["name"] == "mark_place")[0]["input_schema"]["properties"]
	_check(props["where"]["enum"] == Level.REFUGE_WHERE.duplicate() and props.has("shown") and props.has("bed") and props.has("watch")
		and not props.has("den") and not props.has("truce") and not props.has("lore_id"), "mark_place offers where, shown, bed, facing and watch, never den, truce or lore_id")
	_check("draft until voice has seen it" in str(props["name"]["description"]) and "draft" in str(props["shown"]["description"]), "name and shown are said to be drafts for voice")
	var doc := _doc()
	doc.config["roads"] = [{"points": [[0, 25, 2], [39, 25, 2]], "kind": "stone"}]
	var session := BuilderSession.new(doc, Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([]))
	# A refuge: its where needed, one of Level.REFUGE_WHERE.
	var bare := session.run_tool("mark_place", {"key": "shieling", "kind": "refuge", "at": [8, 8], "holder": "nobody", "name": "a shieling high on the hill"})
	_check(not bare.get("ok", true) and "needs where" in str(bare.get("text")) and not session.working.config.get("places", {}).has("shieling"), "a refuge with no where: refused (%s)" % bare)
	_check(not session.run_tool("mark_place", {"key": "shieling", "kind": "refuge", "at": [8, 8], "holder": "nobody", "where": "moon"}).get("ok", true), "a where not of REFUGE_WHERE: refused")
	_check(not session.run_tool("mark_place", {"key": "farm", "kind": "farm", "at": [8, 8], "holder": "town", "where": "hills"}).get("ok", true), "a where on a farm: refused")
	var refuge := session.run_tool("mark_place", {"key": "shieling", "kind": "refuge", "at": [8, 8], "holder": "nobody",
		"name": "a shieling high on the hill", "shown": "the shieling", "where": "hills"})
	var places: Dictionary = session.working.config.get("places", {})
	_check(refuge.get("ok", false) and places["shieling"].get("where") == "hills" and places["shieling"].get("shown") == "the shieling"
		and "draft until voice" in str(refuge.get("text")), "a refuge in the hills, its shown name, the answer saying its name is a draft (%s)" % refuge)
	var warnings: Array[String] = []
	var read := Level.places_from({"places": places}, warnings)
	_check(warnings.is_empty() and read["shieling"].get("where") == "hills" and read["shieling"].get("shown") == "the shieling", "Level reads its where and shown (%s)" % [warnings])
	# A trader: his bed within the radius, the side he faces as a step.
	var trader := session.run_tool("mark_place", {"key": "camp_trader", "kind": "trader", "at": [20, 10], "radius": 2, "holder": "nobody", "bed": [19, 10], "facing": "north"})
	places = session.working.config.get("places", {})
	_check(trader.get("ok", false) and places["camp_trader"].get("bed") == [19, 10] and places["camp_trader"].get("facing") == [0, -1], "a trader's bed and facing north, written [0, -1] (%s)" % [places.get("camp_trader", trader)])
	var far_bed := session.run_tool("mark_place", {"key": "camp_trader", "kind": "trader", "at": [20, 10], "radius": 2, "holder": "nobody", "bed": [24, 10]})
	_check(not far_bed.get("ok", true) and "beyond the place's radius" in str(far_bed.get("text")), "a bed beyond his radius: refused (%s)" % far_bed)
	_check(not session.run_tool("mark_place", {"key": "camp2", "kind": "camp", "at": [20, 12], "holder": "nobody", "bed": [20, 13]}).get("ok", true), "a bed on a camp: refused")
	_check(not session.run_tool("mark_place", {"key": "camp_trader", "kind": "trader", "at": [20, 10], "holder": "nobody", "facing": "up"}).get("ok", true), "a facing not a side: refused")
	# A perch: its watch within the radius, the cells near the road named.
	var watch := [[30, 18], [31, 18], [30, 22]]
	var perch := session.run_tool("mark_place", {"key": "cat_rocks", "kind": "perch", "at": [30, 20], "radius": 4, "holder": "nobody", "watch": watch})
	places = session.working.config.get("places", {})
	_check(perch.get("ok", false) and places["cat_rocks"].get("watch") == watch, "a perch's watch cells kept (%s)" % [places.get("cat_rocks", perch)])
	_check("(30, 22)" in str(perch.get("text")) and not "(30, 18)" in str(perch.get("text")) and "from a road" in str(perch.get("text")),
		"the answer names the watch cell under 6 from the road, not the far ones (%s)" % perch)
	_check(not session.run_tool("mark_place", {"key": "cat_far", "kind": "perch", "at": [30, 10], "radius": 2, "holder": "nobody", "watch": [[30, 14]]}).get("ok", true), "a watch cell beyond the radius: refused")
	_check(not session.run_tool("mark_place", {"key": "camp_trader", "kind": "trader", "at": [20, 10], "holder": "nobody", "watch": [[20, 11]]}).get("ok", true), "a watch on a trader: refused")
	# Move carries the bed, the watch and a lair's den; marking again keeps the den and lore_id.
	places = (session.working.config["places"] as Dictionary).duplicate(true)
	places["lair"] = {"at": [10, 20], "kind": "lair", "radius": 3, "holder": "nobody", "den": [11, 20], "lore_id": "some_lair"}
	session.working.apply_changes({"config": {"places": places}})
	session.run_tool("move", {"place": "camp_trader", "by": [2, 0]})
	session.run_tool("move", {"place": "cat_rocks", "by": [-1, 0]})
	session.run_tool("move", {"place": "lair", "by": [0, -2]})
	places = session.working.config.get("places", {})
	_check(places["camp_trader"].get("bed") == [21, 10] and places["camp_trader"].get("facing") == [0, -1], "move: the trader's bed goes with him, his facing kept (%s)" % [places["camp_trader"]])
	_check(places["cat_rocks"].get("watch") == [[29, 18], [30, 18], [29, 22]], "move: the perch's watch goes with it (%s)" % [places["cat_rocks"]])
	_check(places["lair"].get("den") == [11, 18], "move: the lair's den goes with it (%s)" % [places["lair"]])
	var again := session.run_tool("mark_place", {"key": "lair", "kind": "lair", "at": [10, 18], "radius": 4, "holder": "nobody"})
	places = session.working.config.get("places", {})
	_check(again.get("ok", false) and places["lair"].get("den") == [11, 18] and places["lair"].get("lore_id") == "some_lair" and places["lair"].get("radius") == 4
		and "kept its den, lore_id" in str(again.get("text")), "marked again: its den and lore_id kept, said (%s)" % again)
	_check("A refuge (where a sought newcomer is found) says where it is" in BuilderSession.system_prompt(), "the prompt says a refuge's where, a trader's bed and a perch's watch")
	# No stall place: none marked, Umbrage's weapon_stall neither changed nor moved, alone or with its stall.
	var kinds: Array = props["kind"]["enum"]
	_check(not "stall" in kinds and "trader" in kinds, "mark_place offers no stall kind")
	var stall := session.run_tool("mark_place", {"key": "a_stall", "kind": "stall", "at": [25, 10], "holder": "town"})
	_check(not stall.get("ok", true) and "a stall's seller isn't designed yet, so no stall place can be marked" in str(stall.get("text"))
		and not session.working.config["places"].has("a_stall"), "a stall place: refused in words, nothing marked (%s)" % stall)
	places = (session.working.config["places"] as Dictionary).duplicate(true)
	places["weapon_stall"] = {"at": [25, 9], "kind": "stall", "holder": "town", "radius": 1}
	var buildings: Array = (session.working.config.get("buildings", []) as Array).duplicate(true)
	buildings.append({"slot": "building.market_stall", "at": [25, 10], "facing": [0, 1]})
	session.working.apply_changes({"config": {"places": places, "buildings": buildings}})
	var remark := session.run_tool("mark_place", {"key": "weapon_stall", "kind": "other", "at": [27, 9], "holder": "town"})
	var shift := session.run_tool("move", {"place": "weapon_stall", "by": [2, 0]})
	var carry := session.run_tool("move", {"at": [25, 10], "by": [0, 3]})
	places = session.working.config.get("places", {})
	_check(not remark.get("ok", true) and not shift.get("ok", true) and "economy's" in str(shift.get("text")) and not carry.get("ok", true) and "weapon_stall" in str(carry.get("text"))
		and places["weapon_stall"] == {"at": [25, 9], "kind": "stall", "holder": "town", "radius": 1},
		"the weapon_stall place: marked again, moved, carried with its stall: each refused, it stays (%s; %s; %s)" % [remark, shift, carry])


## The decor tool (841): each hand-laid kind laid and read back by
## Level.parse; a bulky piece closing a two-cell way refused; a wall_hearth
## outdoors off a building refused, indoors laid; a kept-out kind and a
## generator's refused in words; remove; the prompt's words.
func _test_decor() -> void:
	print("
== 841: the decor tool, its kinds laid and read back ==")
	var offered: Array = BuilderSession.tools().filter(func(tool: Dictionary) -> bool: return tool["name"] == "decor")[0]["input_schema"]["properties"]["kind"]["enum"]
	_check(offered == BuilderSession.DECOR_WORDS.keys() and offered.all(func(kind: String) -> bool: return Level.DECOR_KINDS.has(kind))
		and not "fence" in offered and not "crate" in offered and not "inn_sign" in offered and not "captive_post" in offered and not "mine_arch" in offered,
		"decor offers the hand-laid kinds, all Level's, none kept out (%s)" % [offered])
	var prompt := BuilderSession.system_prompt()
	_check("decor sets a piece on a floor cell, drawn only" in prompt and "dark elven runes on a wall, only in the tower over the mine" in prompt
		and "never in the barrow" in prompt and "set it against a wall or in a corner" in prompt, "the prompt says each kind, lore's lines, and where bulky pieces go")
	var doc := _doc()
	# A lane two cells wide (x 11 and 12, y 5 to 9), and a long wall in the open (east of x 20).
	for y in range(5, 10):
		doc.map.set_edge(Terrain.edge_key(Vector2i(10, y), Vector2i.RIGHT), "wall")
		doc.map.set_edge(Terrain.edge_key(Vector2i(12, y), Vector2i.RIGHT), "wall")
	for y in range(10, 20):
		doc.map.set_edge(Terrain.edge_key(Vector2i(20, y), Vector2i.RIGHT), "wall")
	var session := BuilderSession.new(doc, Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([]))
	_check(session.narrow_ways().is_empty(), "the lane is two cells wide to start")
	var laid := {
		"barrel": [[20, 10], "east"], "sack": [[20, 11], ""], "broken_cart": [[4, 20], "south"], "campfire_cold": [[8, 20], ""], "bones": [[20, 14], ""],
		"bedroll": [[12, 20], "west"], "scattered_bones": [[14, 20], ""], "candles": [[16, 20], ""], "rune_strip": [[20, 16], "east"], "carving": [[20, 18], "east"]}
	for kind: String in laid:
		var given := {"at": laid[kind][0], "kind": kind}
		if not str(laid[kind][1]).is_empty():
			given["side"] = laid[kind][1]
		var out := session.run_tool("decor", given)
		_check(out.get("ok", false), "decor: a %s at %s (%s)" % [kind, laid[kind][0], out])
	var level := Level.parse(session.working.map.to_image(), null, session.working.config)
	var read: Array = level["terrain"]["decor"]
	_check(laid.keys().all(func(kind: String) -> bool: return read.any(func(piece: Dictionary) -> bool: return piece["kind"] == kind and piece["cell"] == Vector2i(laid[kind][0][0], laid[kind][0][1]))),
		"Level reads every piece back (%d of %d; %s)" % [read.size(), laid.size(), level["warnings"].filter(func(warning: String) -> bool: return "decor" in warning)])
	_check(read.any(func(piece: Dictionary) -> bool: return piece["kind"] == "barrel" and piece["out"] == Vector2i(1, 0)), "the barrel faces east, [1, 0]")
	var gap := session.run_tool("decor", {"at": [20, 8], "kind": "sack"})
	_check(not gap.get("ok", true) and "one cell wide at (20, 9)" in str(gap.get("text")), "a sack a cell off the barrel along the wall: refused, the gap between them named (%s)" % gap)
	# Refusals.
	var lane := session.run_tool("decor", {"at": [11, 7], "kind": "barrel"})
	_check(not lane.get("ok", true) and "one cell wide at (12, 7)" in str(lane.get("text")) and "against a wall or in a corner" in str(lane.get("text")),
		"a barrel in the two-cell lane: refused, naming the way it leaves (%s)" % lane)
	_check(session.run_tool("decor", {"at": [11, 7], "kind": "candles"}).get("ok", false) and session.narrow_ways().is_empty(), "candles there: laid, low, the lane still two cells")
	var no_wall := session.run_tool("decor", {"at": [30, 20], "kind": "rune_strip", "side": "east"})
	_check(not no_wall.get("ok", true) and "there is no wall on the east side of (30, 20)" in str(no_wall.get("text")), "a rune strip with no wall: refused by Level.decor_from, in plain words (%s)" % no_wall)
	session.working.map.set_cell(Vector2i(25, 25), "water")
	session.working.revision += 1
	var wet := session.run_tool("decor", {"at": [25, 25], "kind": "candles"})
	_check(not wet.get("ok", true) and "(25, 25) is water, not floor" in str(wet.get("text")), "candles on water: refused, saying so (%s)" % wet)
	_check(not session.run_tool("decor", {"at": [20, 16], "kind": "carving"}).get("ok", true), "a wall piece with no side: refused")
	_check(not session.run_tool("decor", {"at": [16, 22], "kind": "candles", "side": "north"}).get("ok", true), "candles given a side: refused")
	var hearth := session.run_tool("decor", {"at": [20, 10], "kind": "wall_hearth", "side": "east"})
	_check(not hearth.get("ok", true) and "inside wall" in str(hearth.get("text")), "a wall_hearth on a wall in the open: refused (%s)" % hearth)
	var fence := session.run_tool("decor", {"at": [25, 20], "kind": "fence"})
	_check(not fence.get("ok", true) and "the fence tool" in str(fence.get("text")), "a fence: refused in words (%s)" % fence)
	var arch := session.run_tool("decor", {"at": [25, 20], "kind": "mine_arch"})
	_check(not arch.get("ok", true) and "not by hand" in str(arch.get("text")), "a generator's kind: refused in words (%s)" % arch)
	_check(not session.run_tool("decor", {"at": [20, 10], "kind": "barrel", "side": "east"}).get("ok", true), "a second barrel on the same cell: refused")
	var gone := session.run_tool("decor", {"at": [20, 11], "remove": true})
	_check(gone.get("ok", false) and not (session.working.config["decor"] as Array).any(func(entry: Array) -> bool: return entry[0] == 20 and entry[1] == 11),
		"remove: the sack taken away (%s)" % gone)
	# Indoors, a wall_hearth on any wall.
	var indoors := _doc()
	indoors.config["outdoor"] = false
	for x in range(5, 10):
		indoors.map.set_edge(Terrain.edge_key(Vector2i(x, 5), Vector2i.UP), "wall")
	var inside := BuilderSession.new(indoors, Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([]))
	var fire := inside.run_tool("decor", {"at": [6, 5], "kind": "wall_hearth", "side": "north"})
	var hall := Level.parse(inside.working.map.to_image(), null, inside.working.config)
	_check(fire.get("ok", false) and (hall["terrain"]["decor"] as Array).any(func(piece: Dictionary) -> bool: return piece["kind"] == "wall_hearth"),
		"indoors: a wall_hearth on the north wall, read back (%s)" % fire)


## The piece tool (842): a milestone carved with a reachable name (never a
## shelved level's or nowhere's), a hunter's blind, a lean-to and an empty
## stall laid and read back; the shrine and the grave not yet; a piece
## leaving a one-cell way, by an arrival or before a door refused; remove.
func _test_piece() -> void:
	print("
== 842: the piece tool, its standing pieces laid and read back ==")
	var props: Dictionary = BuilderSession.tools().filter(func(tool: Dictionary) -> bool: return tool["name"] == "piece")[0]["input_schema"]["properties"]
	_check(props["kind"]["enum"] == ["milestone", "hunters_blind", "lean_to", "market_stall"] and props["arrow"]["enum"] == Level.CARVED_ARROWS.duplicate(),
		"piece offers the milestone, the blind, the lean-to and the stall, never the shrine or the grave (%s)" % [props["kind"]["enum"]])
	var prompt := BuilderSession.system_prompt()
	_check("piece lays a standing piece" in prompt and "an empty stall where nobody sells" in prompt and not "wayside_shrine (" in prompt, "the prompt says each piece, the stall empty")
	var was := WorldMap.settings_path
	WorldMap.settings_path = "res://levels/world_map.json"
	var names := BuilderSession.reachable_names()
	_check(names.has("umbrage") and names.has("shieling") and names.has("hills") and not names.has("boar's lair"),
		"reachable: Umbrage (the wilds' town), the shieling, the Hills; never the shelved boar's lair (%d names)" % names.size())
	var doc := _doc()
	doc.config["roads"] = [{"points": [[0, 28, 2], [39, 28, 2]], "kind": "stone"}]
	doc.config["spawn_points"] = {"from_hills": [5, 24]}
	var session := BuilderSession.new(doc, Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([]))
	var stone := session.run_tool("piece", {"at": [10, 27], "kind": "milestone", "facing": "south", "carved": "Umbrage", "arrow": "left"})
	_check(stone.get("ok", false) and "carved \"Umbrage\", its arrow left (a draft until voice has seen it)" in str(stone.get("text")) and not "no road" in str(stone.get("text")),
		"a milestone by the road carved Umbrage, its arrow left, a draft (%s)" % stone)
	var nowhere := session.run_tool("piece", {"at": [14, 26], "kind": "milestone", "carved": "Nowhere"})
	_check(not nowhere.get("ok", true) and "no level, town or named place a player can reach is called Nowhere" in str(nowhere.get("text"))
		and "Umbrage" in str(nowhere.get("text")) and not "boar's lair" in str(nowhere.get("text")), "a milestone to nowhere: refused, the list naming no shelved place")
	_check(not session.run_tool("piece", {"at": [14, 26], "kind": "milestone", "carved": "The boar's lair"}).get("ok", true), "a milestone to the shelved boar's lair: refused")
	_check(not session.run_tool("piece", {"at": [14, 26], "kind": "milestone"}).get("ok", true), "a milestone with nothing carved: refused")
	var far := session.run_tool("piece", {"at": [30, 4], "kind": "milestone", "carved": "the Hills"})
	_check(far.get("ok", false) and "no road is at or beside it" in str(far.get("text")), "a milestone off the road: laid, the answer saying so (%s)" % far)
	WorldMap.settings_path = was
	_check(not session.run_tool("piece", {"at": [20, 4], "kind": "lean_to", "carved": "Umbrage"}).get("ok", true), "words on a lean-to: refused")
	_check(session.run_tool("piece", {"at": [20, 4], "kind": "hunters_blind", "facing": "east"}).get("ok", false), "a hunter's blind laid")
	_check(session.run_tool("piece", {"at": [25, 4], "kind": "lean_to"}).get("ok", false), "a lean-to laid")
	var places_before: Variant = session.working.config.get("places", {}).duplicate(true)
	var stall := session.run_tool("piece", {"at": [30, 10], "kind": "market_stall"})
	_check(stall.get("ok", false) and "nobody sells there" in str(stall.get("text")) and session.working.config.get("places", {}) == places_before,
		"a market stall laid, empty, said so, no place written (%s)" % stall)
	for kind in ["wayside_shrine", "grave"]:
		var held := session.run_tool("piece", {"at": [34, 14], "kind": kind})
		_check(not held.get("ok", true) and "not yet" in str(held.get("text")), "a %s: not yet (%s)" % [kind, held])
	var level := Level.parse(session.working.map.to_image(), null, session.working.config)
	var slots: Array = level["buildings"].map(func(building: Dictionary) -> String: return str(building.get("slot", "")))
	_check(["building.milestone", "building.hunters_blind", "building.lean_to", "building.market_stall"].all(func(slot: String) -> bool: return slot in slots)
		and level["buildings"].any(func(building: Dictionary) -> bool: return building.get("carved") == "Umbrage" and building.get("arrow") == "left")
		and not Vector2i(10, 27) in level["terrain"]["floor"], "Level reads each piece back, the milestone's words with it, its cell solid (%s)" % [level["warnings"]])
	# Kept clear: an arrival, a door, a one-cell way.
	var arrival := session.run_tool("piece", {"at": [6, 24], "kind": "milestone", "carved": "Umbrage"})
	_check(not arrival.get("ok", true) and "arrival from_hills" in str(arrival.get("text")), "a piece beside an arrival: refused (%s)" % arrival)
	var built := session.run_tool("building", {"kind": "camp", "size": "small", "at": [4, 4], "facing": "south"})
	var camps: Array = (session.working.config.get("buildings", []) as Array).filter(func(entry: Dictionary) -> bool: return entry.get("kind") == "camp")
	if built.get("ok", false) and camps.size() == 1:
		var front := Level.front_cell(Level.building_rect(camps[0]), Vector2i(0, 1))
		var door := session.run_tool("piece", {"at": [front.x, front.y + 1], "kind": "lean_to"})
		_check(not door.get("ok", true) and "door" in str(door.get("text")), "a lean-to before a door: refused (%s)" % door)
	else:
		_check(false, "a camp to stand a door (%s)" % built)
	for y in range(14, 19):
		session.working.map.set_edge(Terrain.edge_key(Vector2i(16, y), Vector2i.RIGHT), "wall")
		session.working.map.set_edge(Terrain.edge_key(Vector2i(18, y), Vector2i.RIGHT), "wall")
	session.working.revision += 1
	WorldMap.settings_path = "res://levels/world_map.json"
	var lane := session.run_tool("piece", {"at": [17, 16], "kind": "milestone", "carved": "Umbrage"})
	WorldMap.settings_path = was
	_check(not lane.get("ok", true) and "one cell wide at (18, 16)" in str(lane.get("text")), "a milestone in a two-cell lane: refused, naming the way (%s)" % lane)
	var gone := session.run_tool("piece", {"at": [25, 4], "remove": true})
	_check(gone.get("ok", false) and not (session.working.config["buildings"] as Array).any(func(entry: Dictionary) -> bool: return entry.get("slot") == "building.lean_to"),
		"remove: the lean-to taken away (%s)" % gone)
	var stall_place := session.run_tool("mark_place", {"key": "a_stall", "kind": "stall", "at": [30, 12], "holder": "town"})
	_check("lay a market_stall with piece, dressing only" in str(stall_place.get("text")), "mark_place's stall refusal names piece now")


## The cut-off check (844): an edit that leaves ground unreachable from
## every start and arrival is undone and refused, naming what is cut off;
## a detour passes; a removal never trips it; its time on the hills.
func _test_cut_off() -> void:
	print("
== 844: no edit cuts ground off from the starts and arrivals ==")
	var doc := _doc()
	doc.config["starts"] = [[2, 2]]
	doc.config["links"] = [{"at": [30, 10], "to": "wilds", "to_spawn": "from_test"}]
	# A wall down x 20 (its east edges), open only at y 10 and 11: the east side's one way in.
	for y in 30:
		if y != 10 and y != 11:
			doc.map.set_edge(Terrain.edge_key(Vector2i(20, y), Vector2i.RIGHT), "wall")
	var session := BuilderSession.new(doc, Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([]))
	_check(session.reached().has(Vector2i(35, 25)) and session.narrow_ways().is_empty(), "the east side is reached through the two-cell gap")
	var blind := session.run_tool("piece", {"at": [21, 10], "kind": "hunters_blind"})
	_check(not blind.get("ok", true) and "cut off the way off the level at (30, 10) (to wilds)" in str(blind.get("text"))
		and not (session.working.config.get("buildings", []) as Array).any(func(entry: Dictionary) -> bool: return entry.get("slot") == "building.hunters_blind"),
		"a 2 x 2 blind filling the gap: refused, naming the link beyond, and undone (%s)" % blind)
	var one := session.run_tool("decor", {"at": [21, 10], "kind": "barrel"})
	var row := session.run_tool("decor", {"at": [21, 11], "kind": "barrel"})
	_check(one.get("ok", false) and not row.get("ok", true) and "cut off" in str(row.get("text")) and (session.working.config.get("decor", []) as Array).size() == 1,
		"a row of barrels across the gap: the first laid, the second refused, undone (%s; %s)" % [one, row])
	var gone := session.run_tool("decor", {"at": [21, 10], "remove": true})
	_check(gone.get("ok", false), "removing the barrel: never refused (%s)" % gone)
	var stall := session.run_tool("piece", {"at": [21, 10], "kind": "lean_to"})
	_check(not stall.get("ok", true) and "the way off the level at (30, 10)" in str(stall.get("text")), "a lean-to over the only path to the link: refused, naming it (%s)" % stall)
	# A second gap lower down: the same lean-to leaves a longer way round, and passes.
	session.working.map.set_edge(Terrain.edge_key(Vector2i(20, 20), Vector2i.RIGHT), "clear")
	session.working.map.set_edge(Terrain.edge_key(Vector2i(20, 21), Vector2i.RIGHT), "clear")
	session.working.revision += 1
	session._reached = {}
	var detour := session.run_tool("piece", {"at": [21, 10], "kind": "lean_to"})
	_check(detour.get("ok", false) and session.reached().has(Vector2i(35, 25)), "with a way round by y 20: the lean-to laid (%s)" % detour)
	var removed := session.run_tool("piece", {"at": [21, 10], "remove": true})
	_check(removed.get("ok", false), "removing the lean-to: never refused (%s)" % removed)
	# Its time on the biggest level.
	var hills := MapDoc.from_level("hills")
	var big := BuilderSession.new(hills, Rect2i(0, 0, 10, 10), "hills", StubClaude.new([]))
	var began := Time.get_ticks_usec()
	var reach := big.reached()
	print("  (the hills, %d x %d: %d cells reached in %d ms)" % [hills.map.size.x, hills.map.size.y, reach.size(), (Time.get_ticks_usec() - began) / 1000])
	_check(reach.size() > 1000, "the hills are flooded from their starts and arrivals")


## Jeff's chest rule (806) in builder mode: a chest of loot only in a dungeon,
## never empty; a town's depot or shop counter spared.
func _test_chest_rule() -> void:
	print("
== 807 amended (4): a chest of loot only in a dungeon, and never empty ==")
	var doc := _doc()
	var session := BuilderSession.new(doc, Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([]))
	var out := session.run_tool("place", {"at": [10, 10], "thing": "chest", "loot": "supplies"})
	_check(not out.get("ok", true) and "only in a dungeon" in str(out.get("text")) and session.working.map.cell(Vector2i(10, 10)) == "grass",
		"a chest of loot outdoors: refused (%s)" % out)
	_check(session.run_tool("place", {"at": [11, 10], "thing": "chest", "use": "shop"}).get("ok", false), "a shop counter's chest outdoors: placed")
	_check(session.run_tool("place", {"at": [12, 10], "thing": "chest", "use": "depot"}).get("ok", false), "a depot's chest outdoors: placed")
	session.working.config["depth"] = 1
	session.working.revision += 1
	var empty := session.run_tool("place", {"at": [13, 10], "thing": "chest"})
	_check(not empty.get("ok", true) and "hold something" in str(empty.get("text")), "an empty chest in a dungeon: refused (%s)" % empty)
	_check(session.run_tool("place", {"at": [13, 10], "thing": "chest", "loot": "supplies"}).get("ok", false), "a chest with a loot table in a dungeon: placed")
	_check(session.run_tool("place", {"at": [14, 10], "thing": "chest", "items": ["ration"]}).get("ok", false), "a chest with items in a dungeon: placed")
	session.working.config.erase("depth")
	session.working.config["regenerate"] = {}
	session.working.config["loot"] = {"chest": "supplies"}
	session.working.revision += 1
	_check(session.run_tool("place", {"at": [15, 10], "thing": "chest"}).get("ok", false), "a regenerated level's chest with the level's chest loot: placed")
	_check(BuilderSession.is_dungeon({"depth": 2}) and not BuilderSession.is_dungeon({"outdoor": true}), "a dungeon: below ground or regenerated")
	_check("only in a dungeon" in BuilderSession.system_prompt(), "the prompt says the rule")


## A 40 x 30 dungeon (depth 1, indoors) of rock: hall A (4..11, 4..9) with
## a brute at (6, 6), a way two wide (12..19, 6..7) east to hall B
## (20..27, 4..9), empty.
func _dungeon_doc() -> MapDoc:
	var doc := MapDoc.new()
	doc.folder = preload("res://tests/test_ports.gd").scratch("builder_test/")
	doc.map = LevelMap.new(Vector2i(40, 30))
	for y in 30:
		for x in 40:
			var hall := (x >= 4 and x < 12 or x >= 20 and x < 28) and y >= 4 and y < 10
			var way := x >= 12 and x < 20 and y >= 6 and y < 8
			doc.map.set_cell(Vector2i(x, y), "stone" if hall or way else "void")
	doc.map.set_cell(Vector2i(6, 6), "monster_brute")
	doc.config = {"name": "Test Delve", "depth": 1, "entities": [{"at": [6, 6], "idle": "guard"}]}
	return doc


func _test_layout_on_accept() -> void:
	print("
== 806 amended (7): accept refuses only the layout faults the change adds ==")
	var doc := _dungeon_doc()
	var had := BuilderSession.layout_faults(doc)
	print("  the level's own faults: %s" % [had])
	_check(had.any(func(fault: Dictionary) -> bool: return fault["rule"] == "purpose"), "hall B, empty, is the level's own fault")
	var session := BuilderSession.new(doc, Rect2i(0, 0, 40, 30), "test_delve", StubClaude.new([]))
	_check(session.layout_news().is_empty(), "nothing done: nothing new")
	# Hall C south of B, empty, and a way down to it.
	session.run_tool("paint", {"ground": "stone", "rects": [{"x": 22, "y": 10, "w": 2, "h": 4}, {"x": 20, "y": 14, "w": 8, "h": 6}]})
	var news := session.layout_news()
	_check(news.any(func(fault: String) -> bool: return fault.begins_with("purpose")), "an empty hall added: a new purpose fault (%s)" % [news])
	_check(not session.accept() and "purpose" in session.refused and doc.undo_steps.is_empty() and doc.map.cell(Vector2i(22, 16)) == "void",
			"accept refuses it, saying why, and the level is untouched (%s)" % session.refused)
	# The same with a monster in it, and a chest of loot by it.
	session.run_tool("paint", {"ground": "stone", "rects": [{"x": 22, "y": 10, "w": 2, "h": 4}, {"x": 20, "y": 14, "w": 8, "h": 6}]})
	session.run_tool("place", {"at": [23, 16], "thing": "brute"})
	session.run_tool("place", {"at": [25, 17], "thing": "chest", "loot": "supplies"})
	news = session.layout_news()
	_check(news.is_empty(), "a guarded hall: nothing new, B's old fault not counted (%s)" % [news])
	_check(session.accept() and session.refused.is_empty() and doc.map.cell(Vector2i(25, 17)) == "chest", "accepted")
	# An unguarded chest of loot far from any monster.
	session.run_tool("paint", {"ground": "stone", "rects": [{"x": 28, "y": 6, "w": 10, "h": 2}, {"x": 32, "y": 8, "w": 6, "h": 20}]})
	session.run_tool("place", {"at": [35, 26], "thing": "chest", "loot": "supplies"})
	news = session.layout_news()
	_check(news.any(func(fault: String) -> bool: return fault.begins_with("chest") and "unguarded" in fault), "a chest left unguarded: a new chest fault (%s)" % [news])
	_check(not session.accept() and "unguarded" in session.refused, "accept refuses it")
	session.discard()
	# Claude is told as it goes, and the summary carries what's left.
	var stub := StubClaude.new([
		[{"name": "paint", "input": {"ground": "stone", "rects": [{"x": 22, "y": 10, "w": 2, "h": 4}, {"x": 20, "y": 14, "w": 8, "h": 6}]}}],
		"A hall.",
	])
	var asked := BuilderSession.new(_dungeon_doc(), Rect2i(0, 0, 40, 30), "test_delve", stub)
	var result: Dictionary = await asked.ask("a hall south")
	var told := str(stub.sent[1]["messages"][2]["content"][0]["content"])
	_check("Layout now" in told and "purpose" in told, "the tool's result tells Claude (%s)" % told)
	_check((result["layout_warnings"] as Array).size() > 0, "the result's layout_warnings say it (%s)" % [result["layout_warnings"]])
	# Out of doors only the chest rule: the grass field's open ground is no room.
	var field := BuilderSession.new(_doc(), Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([]))
	field.run_tool("paint", {"ground": "stone", "rects": [{"x": 10, "y": 10, "w": 8, "h": 8}]})
	_check(field.layout_news().is_empty() and BuilderSession.layout_faults(field.working).is_empty(), "outdoors: no room faults")
	_check("layout rules hold" in BuilderSession.system_prompt(), "the prompt says the layout rules")
	# The real dungeons (read only, from levels/): their own faults are theirs, nothing new untouched.
	for level_name in ["castle_halls", "barrow"]:
		var real := BuilderSession.new(MapDoc.open("res://levels/%s/" % level_name), Rect2i(0, 0, 8, 8), level_name, StubClaude.new([]))
		var started := Time.get_ticks_msec()
		var own := BuilderSession.layout_faults(real.doc)
		var took := Time.get_ticks_msec() - started
		_check(real.layout_news(own).is_empty(), "%s untouched: nothing new (its own: %s, checked in %d ms)" % [level_name, BuilderSession.LAYOUT_SENSE.counts(own), took])


func _test_arrivals() -> void:
	print("\n== 806 amended (13): a way in inside a fight warned of, never refused ==")
	var doc := _doc()
	doc.config["starts"] = [[2, 2]]
	var session := BuilderSession.new(doc, Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([]))
	var own := session.arrival_faults(doc)
	_check(own.is_empty() and session.arrival_news(own).is_empty(), "the start far from the brute: nothing (%s)" % [own])
	var placed := session.run_tool("place", {"at": [6, 4], "thing": "brute"})
	var news := session.arrival_news(own)
	_check(placed.get("ok", false) and news.size() == 1 and news[0].begins_with("arrival at (2, 2): the arrival start 1 is 4 cells from where a brute roams"),
		"a brute laid 4 cells from the start: warned, by the start and the nearest (%s; %s)" % [placed, news])
	_check(session.accept() and session.refused.is_empty() and doc.map.cell(Vector2i(6, 4)) == "monster_brute", "accepted all the same: a warning, never a refusal (%s)" % session.refused)
	# The level's own is the baseline: once accepted, the same start is no news.
	var after := BuilderSession.new(doc, Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([]))
	var had := after.arrival_faults(doc)
	_check(had.size() == 1 and after.arrival_news(had).is_empty(), "the level's own arrival fault: not the edit's (%s)" % [had])
	# A spawn point a link lands on, in any zone: indoors too.
	after.working.config["spawn_points"] = {"from_wilds": [34, 6]}
	after.working.revision += 1
	_check(after.arrival_news(had).any(func(fault: String) -> bool: return "from_wilds" in fault), "a spawn point by the first brute: warned (%s)" % [after.arrival_news(had)])
	after.working.config.erase("spawn_points")
	after.working.revision += 1
	# Claude is told as it goes, and the preview's summary carries it.
	var stub := StubClaude.new([
		[{"name": "place", "input": {"at": [5, 2], "thing": "imp"}}],
		"An imp.",
	])
	var fresh := _doc()
	fresh.config["starts"] = [[2, 2]]
	var asked := BuilderSession.new(fresh, Rect2i(0, 0, 40, 30), "test_field", stub)
	var result: Dictionary = await asked.ask("an imp by the start")
	var told := str(stub.sent[1]["messages"][2]["content"][0]["content"])
	_check("Arrivals now (" + BuilderSession.ARRIVAL_SAYS + "): arrival at (2, 2)" in told, "the tool's result tells Claude (%s)" % told)
	_check((result["arrival_warnings"] as Array).size() == 1 and (result["layout_warnings"] as Array).is_empty(), "the result's arrival_warnings say it, the layout's not (%s)" % [result["arrival_warnings"]])
	# None on the test levels and those held back, nor where the layout rules hold it (refused there, by layout_news).
	var exempt := BuilderSession.new(fresh, Rect2i(0, 0, 40, 30), "test_room", StubClaude.new([]))
	var held_back := BuilderSession.new(fresh, Rect2i(0, 0, 40, 30), "castle", StubClaude.new([]))
	_check(exempt.arrival_faults(asked.working).is_empty() and held_back.arrival_faults(asked.working).is_empty(), "test_room and castle (ARRIVAL_EXEMPT, ARRIVAL_NOT_YET): none")
	_check(BuilderSession.holds_arrival({"regenerate": {"held": ["arrival"]}}) and not BuilderSession.holds_arrival({"regenerate": {}})
		and not BuilderSession.holds_arrival({"outdoor": true}), "a regenerating level holding the rule: its layout's, not a warning")
	_check("keeps %d cells clear of where a hostile monster stands or roams" % BuilderSession.LAYOUT_SENSE.ARRIVAL_CLEAR in BuilderSession.system_prompt(), "the prompt says the rule, at ARRIVAL_CLEAR")


func _test_accept_keeps() -> void:
	print("\n== 841 amended (1): accept keeps every config key a tool writes ==")
	# Each tool's config writes reach the level on accept: decor and skylights were left out of the proposal.
	var field := BuilderSession.new(_doc(), Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([]))
	var laid := field.run_tool("decor", {"at": [10, 10], "kind": "barrel"})
	_check(laid.get("ok", false) and field.proposal().get("config", {}).has("decor"), "decor laid: the proposal carries it (%s)" % [field.proposal().get("config", {}).keys()])
	_check(field.accept() and (field.doc.config.get("decor", []) as Array).size() == 1, "accepted: the barrel is in the level (%s)" % [field.doc.config.get("decor")])
	var cave := _doc()
	cave.config.erase("outdoor")
	cave.config["zone"] = "cave"
	var under := BuilderSession.new(cave, Rect2i(0, 0, 40, 30), "test_cave", StubClaude.new([]))
	var gap := under.run_tool("skylight", {"at": [12, 12], "radius": 2})
	_check(gap.get("ok", false) and under.accept() and (under.doc.config.get("skylights", []) as Array).size() == 1, "a skylight accepted: it is in the level (%s; %s)" % [gap, under.doc.config.get("skylights")])
	# Every key a tool writes to the working copy's config is one the proposal carries.
	var source := FileAccess.get_file_as_string("res://builder/builder_session.gd")
	var found := RegEx.create_from_string("\"config\": \\{\"([a-z_]+)\"").search_all(source)
	var written := found.map(func(hit: RegExMatch) -> String: return hit.get_string(1))
	var missing := written.filter(func(key: String) -> bool: return key not in BuilderSession.CONFIG_KEYS)
	_check(written.size() >= 5 and missing.is_empty(), "every config key a tool writes is carried on accept (%d writes; missing %s)" % [written.size(), missing])


## The lines of [param a] and [param b] that differ, by line number, and
## the difference in their counts.
func _lines_apart(a: String, b: String) -> int:
	var one := a.split("\n")
	var two := b.split("\n")
	var apart := absi(one.size() - two.size())
	for i in mini(one.size(), two.size()):
		if one[i] != two[i]:
			apart += 1
	return apart


## Removes [param path] (an absolute folder) and all in it, if there.
func _remove_folder(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		_remove_folder(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


## [param text] (a level.json) without what 537's building codes add: each
## building's "code" line, the "building_codes" block, and the commas
## either brings before it.
func _without_codes(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var in_block := false
	for line in text.split("\n"):
		if line.begins_with("\t\"building_codes\": {"):
			in_block = not line.ends_with("}") and not line.ends_with("},")
			continue
		if in_block:
			in_block = not (line == "\t}" or line == "\t},")
			continue
		if line.strip_edges().begins_with("\"code\": "):
			continue
		out.append(line.trim_suffix(","))
	return out


func _test_json_keep() -> void:
	print("\n== level.json written in its own words (851) ==")
	var keep := MapDoc.JSON_KEEP
	for level_name: String in ["wilds", "barrow", "barrow_deep", "test_room"]:
		var text := FileAccess.get_file_as_string(Level.DIR + level_name + "/level.json")
		var config: Dictionary = JSON.parse_string(text)
		_check(keep.write(text, config) == text, "%s: no change writes the file byte for byte" % level_name)
		var named := config.duplicate(true)
		named["name"] = str(named["name"]) + " (renamed)"
		var renamed: String = keep.write(text, named)
		_check(_lines_apart(text, renamed) == 1 and keep.same(JSON.parse_string(renamed), named), "%s: one value changed changes one line" % level_name)
		# npc's "spots" (a new top-level list) written, read back, kept, and one changed in one line.
		var spotted := config.duplicate(true)
		spotted["spots"] = [{"use": "fire", "cell": [3.0, 4.0], "face": [4, 4], "pose": "sit", "town": "store"},
			{"use": "work", "trade": "cook", "cell": [6, 4], "face": [6, 5], "pose": "stand", "town": "store"}]
		var with_spots: String = keep.write(text, spotted)
		_check(keep.same(JSON.parse_string(with_spots), spotted) and keep.write(with_spots, JSON.parse_string(with_spots)) == with_spots
			and "\"cell\": [3, 4]" in with_spots and not "3.0" in with_spots.substr(with_spots.find("\"spots\"")),
			"%s: spots written (a cell on one line, whole numbers without .0) and kept as they are" % level_name)
		var sitting: Dictionary = JSON.parse_string(with_spots)
		sitting["spots"][1]["pose"] = "lean"
		_check(_lines_apart(with_spots, keep.write(with_spots, sitting)) == 1, "%s: a spot's pose changed changes one line" % level_name)
	# Hand-kept short lines stay short when one value in them changes.
	var short := "{\n\t\"doors\": [{\"cell\": [3, 8], \"to\": \"inn\"}, {\"cell\": [4, 8], \"to\": \"inn\"}],\n\t\"n\": 181\n}\n"
	var moved: Dictionary = JSON.parse_string(short)
	moved["doors"][1]["cell"] = [5, 8]
	moved["doors"].append({"cell": [6, 8], "to": "inn"})
	_check(keep.write(short, moved) == "{\n\t\"doors\": [{\"cell\": [3, 8], \"to\": \"inn\"}, {\"cell\": [5, 8], \"to\": \"inn\"}, {\"cell\": [6, 8], \"to\": \"inn\"}],\n\t\"n\": 181\n}\n",
		"a short line kept short with a value moved and a door added (%s)" % keep.write(short, moved).c_escape())
	# The doc's own save with no edit: the file in its own words, the one change
	# a save makes of itself (537: each building's code written in) the only lines added.
	var kept_overlay := Level.overlay_dir
	Level.overlay_dir = preload("res://tests/test_ports.gd").scratch("builder_test_keep/")
	# A save left here by the last run is an overlay MapDoc would load in
	# place of the repo's file, so a change to a level.json since then read as
	# the save's own: start from none.
	_remove_folder(ProjectSettings.globalize_path(Level.overlay_dir))
	for level_name: String in ["wilds", "barrow_deep", "test_room"]:
		var doc := MapDoc.from_level(level_name)
		var repo := FileAccess.get_file_as_string(Level.DIR + level_name + "/level.json")
		var coded: Dictionary = JSON.parse_string(repo)
		Level.fill_codes(coded)
		var saved := FileAccess.get_file_as_string(doc.folder + "level.json") if doc.save() else ""
		_check(saved == keep.write(repo, coded) and _without_codes(saved) == _without_codes(repo),
			"%s: MapDoc saved with no edit: the file in its own words, %d lines more, all building codes" % [level_name, saved.split("\n").size() - repo.split("\n").size()])
		var images: Array[String] = preload("res://tools/builder_run.gd").changed_files(doc.folder, Level.DIR + level_name + "/")
		_check(images.all(func(file: String) -> bool: return file == "level.json"), "%s: its images read as the game reads them are unchanged by the save (%s)" % [level_name, images])
	Level.overlay_dir = kept_overlay


func _test_runner() -> void:
	print("\n== tools/builder_run: builder's tools run headless on a level (851) ==")
	var runner := preload("res://tools/builder_run.gd")
	var ports := preload("res://tests/test_ports.gd")
	var out := ports.scratch_path("builder_run") + "/"
	var calls := ports.scratch_path("builder_run_calls.json")
	var overlay_had := DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(Level.OVERLAY + "test_room"))
	var kept_overlay := Level.overlay_dir
	var write_calls := func(list: Array) -> void:
		var file := FileAccess.open(calls, FileAccess.WRITE)
		file.store_string(JSON.stringify(list))
		file.close()
	write_calls.call([{"tool": "decor", "input": {"at": [3, 1], "kind": "barrel"}}])
	var code: int = runner.run(PackedStringArray(["--level=test_room", "--calls=" + calls, "--out=" + out]))
	var made := FileAccess.get_file_as_string(out + "test_room/level.json")
	var coded_room: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Level.DIR + "test_room/level.json"))
	Level.fill_codes(coded_room)
	var was := MapDoc.JSON_KEEP.write(FileAccess.get_file_as_string(Level.DIR + "test_room/level.json"), coded_room)
	var laid := runner.changed_files(out + "test_room/", Level.DIR + "test_room/")
	_check(code == 0 and laid == ["level.json"] and "barrel" in made and _lines_apart(was, made) <= 10,
		"a barrel laid: level.json alone changed (%s), by a few lines at its end (%d apart: %s)" % [laid, _lines_apart(was, made), made.substr(made.find("\"decor\"")).c_escape()])
	write_calls.call([{"tool": "paint", "input": {"ground": "dirt", "cells": [[11, 4]]}}])
	code = runner.run(PackedStringArray(["--level=test_room", "--calls=" + calls, "--out=" + out]))
	var painted := runner.changed_files(out + "test_room/", Level.DIR + "test_room/")
	_check(code == 0 and "layout.png" in painted and not "barrel" in FileAccess.get_file_as_string(out + "test_room/level.json")
		and FileAccess.get_file_as_string(out + "test_room/level.json") == was, "a cell painted: layout.png changed (%s), and the barrel of the run before gone with its folder" % [painted])
	write_calls.call([{"tool": "decor", "input": {"at": [-3, -3], "kind": "barrel"}}, {"tool": "paint", "input": {"ground": "dirt", "cells": [[11, 4]]}}])
	code = runner.run(PackedStringArray(["--level=test_room", "--calls=" + calls, "--out=" + out]))
	_check(code == 2 and not FileAccess.file_exists(out + "test_room/layout.png"), "a refusal stops the run, nothing written")
	_check(runner.run(PackedStringArray(["--level=test_room", "--calls=" + calls, "--out=" + Level.OVERLAY])) == 1
		and runner.run(PackedStringArray(["--level=test_room", "--calls=" + calls, "--out=res://levels/"])) == 1
		and runner.run(PackedStringArray(["--level=no_such_level", "--calls=" + calls, "--out=" + out])) == 1, "the shared overlay, the project and an unknown level refused")
	_check(Level.overlay_dir == kept_overlay and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(Level.OVERLAY + "test_room")) == overlay_had,
		"the shared overlay neither read nor written: Level.overlay_dir put back, no test_room there")


func _test_spots() -> void:
	print("\n== the spot tool: where townsfolk stand, sit and lean (859, npc's 853) ==")
	# Umbrage's square fire (wilds' square_fire, its seats) and the weapon stall's counter.
	var wilds := BuilderSession.new(MapDoc.from_level("wilds"), Rect2i(185, 190, 25, 25), "wilds", StubClaude.new([]))
	var steps := wilds.working.undo_steps.size()
	var seat := wilds.run_tool("spot", {"at": [192, 210], "use": "fire", "face": [193, 211], "pose": "sit"})
	var seat_text := str(seat.get("text"))
	_check(seat.get("ok", false) and wilds.working.config.get("spots") == [{"use": "fire", "cell": [192, 210], "face": [193, 211], "pose": "sit", "town": "store"}]
		and wilds.working.undo_steps.size() == steps + 1 and not "Warning" in seat_text,
		"a sit spot on the fire's seat: npc's shape, the store its town by default, one undo step, no seat warning (%s)" % seat_text)
	if not Client3D.ACTIVITIES.has("sit"):
		_check("sit draws as stand until its clip lands" in seat_text, "it says the sit draws as a stand until animation's clip lands")
	var turned := wilds.run_tool("spot", {"at": [192, 210], "use": "fire", "face": [193, 209], "pose": "sit"})
	_check(turned.get("ok", false) and "changed it to" in str(turned.get("text")) and (wilds.working.config["spots"] as Array).size() == 1
		and wilds.working.config["spots"][0]["face"] == [193, 209], "laid again on its cell: the spot turned, still one (%s)" % turned.get("text"))
	var refusals := {
		"its face is not one of the eight cells about it": {"at": [192, 212], "use": "fire", "face": [195, 215]},
		"its use \"dance\" is none of": {"at": [192, 212], "use": "dance", "face": [193, 212]},
		"a work spot names no trade": {"at": [192, 212], "use": "work", "face": [193, 212]},
		"trade is for a work spot": {"at": [192, 212], "use": "fire", "face": [193, 212], "trade": "cook"},
		"pair is for a talk spot": {"at": [192, 212], "use": "fire", "face": [193, 212], "pair": "a"},
	}
	for words: String in refusals:
		var out := wilds.run_tool("spot", refusals[words])
		_check(not out.get("ok", true) and words in str(out.get("text")), "refused: %s (%s)" % [words, out.get("text")])
	var fire := wilds.run_tool("spot", {"at": [194, 211], "use": "fire", "face": [194, 210]})
	_check(not fire.get("ok", true), "on the fire itself: refused (%s)" % fire.get("text"))
	# The keeper behind his counter; who comes (residents.json's settled people, read without a world).
	var keeper := wilds.run_tool("spot", {"at": [204, 196], "use": "work", "trade": "merchant", "face": [204, 197]})
	var keeper_text := str(keeper.get("text"))
	_check(keeper.get("ok", false) and "work (merchant) in store (1 spot)" in keeper_text and "Snagfin" in keeper_text,
		"a merchant's spot behind the counter: laid, and who comes read (%s)" % keeper_text)
	if World.towns == null:
		_check("residents.json's settled people only" in keeper_text, "with no world, said: the settled people only")
	var gone := wilds.run_tool("spot", {"at": [192, 210], "remove": true})
	_check(gone.get("ok", false) and "took away the fire spot at (192, 210)" in str(gone.get("text")) and (wilds.working.config["spots"] as Array).size() == 1, "removed (%s)" % gone.get("text"))
	wilds.working.undo()
	_check((wilds.working.config["spots"] as Array).size() == 2, "undone: the fire spot back")
	var preview := wilds.spot_preview()
	_check(preview.size() == 3 and preview[2].begins_with("the town's trades in store") and "square, fire and talk in store (1 spot" in preview[0], "the proposal's reading: one line a kind (%s)" % [preview])
	var shown := BuilderSession.spot_words(wilds.working.config)
	_check(wilds.accept() and (wilds.doc.config.get("spots") as Array).size() == 2 and "fire sit at (192, 210) facing (193, 209)" in shown,
		"accepted: both spots in the level, said in the situation (%s)" % shown)
	# A field with no town, then with one: the seat warning, a doorway, a way closed, ground not reached.
	var field := _doc()
	field.config["starts"] = [[2, 2]]
	var session := BuilderSession.new(field, Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([]))
	var townless := session.run_tool("spot", {"at": [10, 10], "use": "square", "face": [11, 10]})
	_check(not townless.get("ok", true) and "no town's store" in str(townless.get("text")), "no town on the level: refused (%s)" % townless.get("text"))
	session.working.config["places"] = {"store": {"at": [20, 15], "kind": "stockpile", "holder": "town"}, "far_store": {"at": [38, 28], "kind": "stockpile", "holder": "town"}}
	session.working.revision += 1
	var bare := session.run_tool("spot", {"at": [10, 10], "use": "square", "face": [11, 10], "pose": "sit"})
	_check(bare.get("ok", false) and "Warning: nothing at (10, 10) is sat on" in str(bare.get("text")) and session.working.config["spots"][0]["town"] == "store",
		"a sit spot on bare grass: laid with a warning; the nearest store its town (%s)" % bare.get("text"))
	session.working.map.set_edge(Terrain.edge_key(Vector2i(14, 10), Vector2i.RIGHT), "door")
	session.working.revision += 1
	var doorway := session.run_tool("spot", {"at": [14, 10], "use": "square", "face": [13, 10]})
	_check(not doorway.get("ok", true) and "in a doorway" in str(doorway.get("text")), "in a doorway: refused (%s)" % doorway.get("text"))
	session.run_tool("paint", {"ground": "rock", "rects": [{"x": 25, "y": 0, "w": 1, "h": 10}, {"x": 25, "y": 11, "w": 1, "h": 19}]})
	var plug := session.run_tool("spot", {"at": [25, 10], "use": "square", "face": [24, 10]})
	_check(not plug.get("ok", true) and "would close the only way through: it cuts off" in str(plug.get("text")), "the one gap in a wall: refused, what it cuts off named (%s)" % str(plug.get("text")).left(160))
	# Walled in by hand (the paint tool's own 844 check undoes an edit that cuts ground off).
	for x in range(30, 35):
		session.working.map.set_cell(Vector2i(x, 20), "rock")
		session.working.map.set_cell(Vector2i(x, 24), "rock")
	for y in range(21, 24):
		session.working.map.set_cell(Vector2i(30, y), "rock")
		session.working.map.set_cell(Vector2i(34, y), "rock")
	session.working.revision += 1
	session._reached = {}
	var shut := session.run_tool("spot", {"at": [32, 22], "use": "square", "face": [32, 21]})
	_check(not shut.get("ok", true) and "not reached" in str(shut.get("text")), "ground walled in, reached from nowhere: refused (%s)" % shut.get("text"))
	# Rolf's rule: a stall's square wider than its counter, the keeper's spot behind it only.
	session.working.config["places"]["stall"] = {"at": [10, 20], "kind": "stall", "holder": "town", "town": "store", "radius": 2}
	session.working.config["buildings"] = [{"slot": "building.market_stall", "at": [10, 21], "facing": [0, 1]}]
	session.working.revision += 1
	session._reached = {}
	var front := session.run_tool("spot", {"at": [12, 22], "use": "work", "trade": "merchant", "face": [11, 22]})
	_check(not front.get("ok", true) and "customers' side of the counter at (10, 21)" in str(front.get("text")), "a merchant's spot out front of his counter: refused (%s)" % front.get("text"))
	var behind := session.run_tool("spot", {"at": [12, 19], "use": "work", "trade": "merchant", "face": [11, 19]})
	_check(behind.get("ok", false), "behind it: laid (%s)" % behind.get("text"))
	var vendor := session.run_tool("spot", {"at": [12, 22], "use": "work", "trade": "vendor", "face": [11, 22]})
	_check(not vendor.get("ok", true) and "customers' side" in str(vendor.get("text")), "Rolf's \"vendor\" spot out front: refused as any keeper's (%s)" % vendor.get("text"))
	var cook := session.run_tool("spot", {"at": [12, 22], "use": "work", "trade": "cook", "face": [11, 22]})
	_check(cook.get("ok", false), "a cook's spot there, no keeper: laid (%s)" % cook.get("text"))
	# The prompt says it, and the tool is offered with npc's uses and poses.
	var offered: Array = BuilderSession.tools().filter(func(tool: Dictionary) -> bool: return tool["name"] == "spot")
	_check(not offered.is_empty() and offered[0]["input_schema"]["properties"]["use"]["enum"] == Level.SPOT_USES and "spot lays where one townsperson stands" in BuilderSession.system_prompt(),
		"the tool offered (npc's uses and poses) and the prompt says it")


func _test_named_refusals() -> void:
	print("\n== what stands there, named (voice's words) ==")
	# Umbrage's store and temple: each chest by what it is.
	var wilds := BuilderSession.new(MapDoc.from_level("wilds"), Rect2i(185, 190, 25, 25), "wilds", StubClaude.new([]))
	var named := {
		Vector2i(190, 196): "the store chest", Vector2i(193, 196): "the shop counter", Vector2i(198, 201): "the temple's chest",
	}
	for at: Vector2i in named:
		var out := wilds.run_tool("spot", {"at": [at.x, at.y], "use": "square", "face": [at.x, at.y + 1]})
		var said := "%s holds %s; lay the spot beside it" % [at, named[at]]
		_check(not out.get("ok", true) and str(out.get("text")) == said, "a spot on %s: refused, \"%s\" (%s)" % [named[at], said, out.get("text")])
	# A field: a way off, a monster and a crate, each by name, to the spot tool and to a move.
	var field := _doc()
	field.config["starts"] = [[2, 2]]
	field.config["places"] = {"store": {"at": [20, 15], "kind": "stockpile", "holder": "town"}}
	var session := BuilderSession.new(field, Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([]))
	session.working.apply_changes({"cells": {Vector2i(6, 6): "monster_imp", Vector2i(7, 7): "crate"}, "covers": [Vector2i(6, 6), Vector2i(7, 7)]})
	session.working.put_link(Vector2i(5, 5), {"at": [5, 5], "to_map": "wilds", "to_spawn": "from_test_field"})
	var imp := BuilderSession._a(str(Monster.kinds().get("imp", {}).get("label", "imp")).to_lower())
	var cases := {
		Vector2i(5, 5): "(5, 5) is the way to wilds; lay the spot beside it",
		Vector2i(6, 6): "(6, 6) holds %s; lay the spot beside it" % imp,
		Vector2i(7, 7): "(7, 7) holds a crate; lay the spot beside it",
	}
	for at: Vector2i in cases:
		var out := session.run_tool("spot", {"at": [at.x, at.y], "use": "square", "face": [at.x + 1, at.y]})
		_check(not out.get("ok", true) and str(out.get("text")) == cases[at], "a spot there: \"%s\" (%s)" % [cases[at], out.get("text")])
	_check(session._cant_take(Vector2i(7, 7)) == "(7, 7) holds a crate already" and session._cant_take(Vector2i(5, 5)) == "(5, 5) is the way to wilds already"
		and session._cant_take(Vector2i(7, 7), [Vector2i(7, 7)]).is_empty(),
		"moved onto them: what is there, named (%s; %s)" % [session._cant_take(Vector2i(7, 7)), session._cant_take(Vector2i(5, 5))])


func _test_trades_preview() -> void:
	print("\n== the town's trades, by economy's rules, against the work spots (859 amended (1)) ==")
	var wilds := BuilderSession.new(MapDoc.from_level("wilds"), Rect2i(185, 190, 25, 25), "wilds", StubClaude.new([]))
	var before := wilds.trade_preview("store")
	for words: String in ["the town's trades in store, by economy's rules: ", "smith at the forge, works about ", "cook at the kitchen",
			"taverner at the inn (if economy seats one)", "priest at the temple (if economy seats one)", "woodcutter at the woodlot woodlot",
			"vendor at the stall weapon_stall"]:
		_check(words in before, "Umbrage's trades: \"%s\" (%s)" % [words, before])
	_check(not "spots laid, no building" in before and "no work spot yet" in before, "no work spot laid yet: said, and no mismatch the other way")
	var named := false
	for name: String in ["Margery", "Dunstan", "Aldous", "Brother Cuth", "Ned", "Old Tam"]:
		named = named or name in before
	_check(not named, "no name of economy's lists read into it")
	var keeper := wilds.run_tool("spot", {"at": [204, 196], "use": "work", "trade": "merchant", "face": [204, 197]})
	var keeper_text := str(keeper.get("text"))
	_check(keeper.get("ok", false) and "the town's trades in store" in keeper_text and "merchant: spots laid, no building" in keeper_text,
		"a merchant's spot, nothing in town calling for one: said both ways (%s)" % keeper_text)
	var lines := wilds.spot_preview()
	_check(lines.size() == 2 and lines[1].begins_with("the town's trades in store"), "the proposal's reading ends with the trades line (%s)" % [lines])
	var empty := BuilderSession.new(_doc(), Rect2i(0, 0, 40, 30), "test_field", StubClaude.new([]))
	_check("none (no building with a use, no work site)" in empty.trade_preview("store"), "a town with nothing that calls for a trade: said so")


## A parse's whole reading, as one string's hash: what a cached and a fresh one must share.
func _parse_print(parsed: Dictionary) -> int:
	return hash(str(parsed))


func _test_cached_checks() -> void:
	print("\n== what builder reads once a change, kept by revision (867) ==")
	# The outdoor chest check: the same faults without the room layout it never read (dungeon's OK).
	var sense := BuilderSession.LAYOUT_SENSE
	for level_name: String in ["wilds", "barrow"]:
		var level := MapDoc.from_level(level_name).parsed()
		for options: Dictionary in [{"dungeon": false}, {"dungeon": true}]:
			var old: Array = []
			sense._chests(level, sense._lay(level, [], options), options, old)
			_check(str(sense.check_chests(level, options)) == str(old), "%s, dungeon %s: check_chests' faults as before (%d)" % [level_name, options["dungeon"], old.size()])
	var session := BuilderSession.new(MapDoc.from_level("wilds"), Rect2i(176, 186, 40, 32), "wilds", StubClaude.new([]))
	var first := session.parsed_of(session.working)
	_check(is_same(session.parsed_of(session.working), first), "read twice with no change: one parse")
	var agree := func(when: String) -> void:
		var fresh := session.working.parsed()
		var kept := session.parsed_of(session.working)
		_check(_parse_print(kept) == _parse_print(fresh)
			and str(BuilderSession.layout_faults(session.working, kept)) == str(BuilderSession.layout_faults(session.working))
			and str(session.arrival_faults(session.working, kept)) == str(session.arrival_faults(session.working))
			and _parse_print(kept) == _parse_print(fresh), "%s: the kept parse and its faults agree with fresh ones, and reading them wrote nothing into it" % when)
	session.run_tool("paint", {"ground": "dirt", "cells": [[186, 200]]})
	_check(not is_same(session.parsed_of(session.working), first), "a tool's change: parsed again")
	agree.call("after a paint")
	# A plain chest outdoors, put in by hand (the place tool refuses one): a layout fault of the edit's own.
	var chest_from := session.working.revision
	session.working.apply_changes({"cells": {Vector2i(200, 205): "chest"}, "covers": [Vector2i(200, 205)]})
	_check(session.working.revision > chest_from and session.working.map.cell(Vector2i(200, 205)) == "chest", "a chest put in by hand: the revision on")
	agree.call("after a chest placed")
	session.working.undo()
	agree.call("after an undo")
	session.working.redo()
	agree.call("after a redo")
	var revision := session.working.revision
	session.run_tool("look", {})
	_check(session.working.revision == revision, "a look changes nothing: the revision stands")
	# The level's own faults, kept by its revision; accept never trusts a kept parse.
	var baseline := session.doc_layout_faults()
	_check(is_same(session.doc_layout_faults(), baseline) and str(baseline) == str(BuilderSession.layout_faults(session.doc)), "the level's own faults: kept, and as read fresh")
	var poisoned := session.working.parsed()
	poisoned["entities"] = []
	session._parses[session.working.get_instance_id()] = {"revision": session.working.revision, "parsed": poisoned}
	var news := session.layout_news(baseline)
	_check(not session.accept() and "the change breaks the layout rules" in session.refused and not news.is_empty(),
		"a kept parse made wrong (the chest left out of it): accept parses fresh and still refuses the chest (%s)" % session.refused)
	session.working.undo()
	session._parses.clear()
	_check(session.accept() and session.doc.revision > 0 and not is_same(session.doc_layout_faults(), baseline), "accepted with the chest undone: the doc's revision on, its faults read again")
	# The spot tool's before is the last spot's after, when nothing changed between.
	session.run_tool("spot", {"at": [192, 210], "use": "fire", "face": [193, 211], "pose": "sit"})
	var kept_reach: Dictionary = session._held.get("reach", {})
	var held := {Vector2i(192, 210): true}
	_check(not kept_reach.is_empty() and is_same(session._held_reach(held), kept_reach) and kept_reach.size() == session.reached_round(held).size(),
		"the reach with the spots held: kept from the last spot, the same as flooded fresh")


func _test_spot_ghost() -> void:
	print("\n== the proposal carries the area's spots for the ghost (859 amended (2)) ==")
	var field := _doc()
	field.config["starts"] = [[2, 2]]
	field.config["places"] = {"store": {"at": [20, 15], "kind": "stockpile", "holder": "town"}}
	field.config["spots"] = [{"use": "square", "cell": [10, 10], "face": [11, 10], "pose": "stand", "town": "store"},
		{"use": "fire", "cell": [12, 10], "face": [12, 11], "pose": "sit", "town": "store"},
		{"use": "square", "cell": [14, 10], "face": [15, 10], "pose": "stand", "town": "store"},
		{"use": "square", "cell": [38, 28], "face": [37, 28], "pose": "stand", "town": "store"}]
	var session := BuilderSession.new(field, Rect2i(0, 0, 30, 20), "test_field", StubClaude.new([]))
	_check(not BuilderHost.proposal_message(session).has("spots") or BuilderHost.proposal_spots(session).all(func(row: Array) -> bool: return row[6] == "kept"),
		"nothing changed: every spot in the area kept")
	session.run_tool("spot", {"at": [12, 10], "use": "fire", "face": [13, 10], "pose": "sit"})
	session.run_tool("spot", {"at": [14, 10], "remove": true})
	session.run_tool("spot", {"at": [16, 12], "use": "work", "trade": "cook", "face": [16, 13], "pose": "lean"})
	var rows: Array = BuilderHost.proposal_message(session).get("spots", [])
	var by := {}
	for row: Array in rows:
		by[Vector2i(int(row[0]), int(row[1]))] = row
	_check(rows.size() == 4 and by.get(Vector2i(10, 10), [])[6] == "kept" and by.get(Vector2i(12, 10), [])[6] == "changed"
		and by.get(Vector2i(14, 10), [])[6] == "gone" and by.get(Vector2i(16, 12), []) == [16, 12, 16, 13, "lean", "work", "new"]
		and not by.has(Vector2i(38, 28)),
		"the proposal's spots: kept, changed, gone and new, none outside the area (%s)" % [rows])
	# The stub's spots, for a shot of the ghost: laid where they can be, a refusal passed on in its words.
	var wilds := BuilderSession.new(MapDoc.from_level("wilds"), Rect2i(185, 190, 25, 25), "wilds", BuilderHost.stub_spots("spots 192,210;194,213 190,196"))
	var asked: Dictionary = await wilds.ask("spots 192,210 194,213 190,196")
	var ghost: Array = BuilderHost.proposal_spots(wilds)
	_check(asked.get("ok", false) and ghost.size() >= 2 and "(190, 196) holds the store chest; lay the spot beside it" in str(asked.get("summary")),
		"the stub lays spots and passes on the refused one's reason (%s; %s)" % [asked.get("summary"), ghost])
