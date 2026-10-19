extends Node
## Builder mode's session (BuilderSession) against a scripted Claude
## (StubClaude): what it is told, the tools on a working copy kept to the
## area, the proposal as one change set, accept as one undo step, discard,
## follow-ups, errors back to Claude, cost and the spending limit.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

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
	_check(buildings.size() == 3 and buildings[1] == {"slot": "building.hut", "at": [7, 7], "facing": [-1, 0]},
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
	_check("set_building gives one in the area a use (field, forge, inn, kitchen, tannery, temple, woodshed)" in BuilderSession.system_prompt(), "Claude is told the uses, from the economy rules")
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
		[{"name": "place", "input": {"at": [14, 12], "thing": "chest"}},
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
			== ["paint", "edges", "stream", "path", "pond", "grove", "scatter", "fence", "height", "hill", "stairs", "place", "stamp", "mark_place", "set_building", "town_wall", "roof", "look", "new_area"], "and the tools")


func _test_session() -> void:
	print("\n== a request: tool calls on a working copy, the proposal, accept ==")
	var doc := _doc()
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
			and "- wolf: wolf, a wild animal: hunts rabbit, deer, stag" in system and "W wolf" in system,
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
	var stub := StubClaude.new([
		[{"name": "height", "input": {"change": "set", "level": 2, "rects": [{"x": 5, "y": 5, "w": 12, "h": 3}]}},
			{"name": "place", "input": {"at": [8, 6], "thing": "chest"}},
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
	var doc := _doc()
	doc.config["places"] = {"store": {"at": [20, 20], "kind": "stockpile", "holder": "town"}}
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


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
