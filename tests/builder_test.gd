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
	_check("set_building gives one in the area a use (forge, inn, kitchen)" in BuilderSession.system_prompt(), "Claude is told the uses, from the economy rules")
	_check("building {" in session.grid(doc.map, doc.config, Rect2i(5, 5, 12, 10), Rect2i(5, 5, 12, 10)), "and sees the buildings in the area, with theirs")


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
			== ["paint", "edges", "path", "pond", "grove", "scatter", "fence", "place", "stamp", "mark_place", "set_building", "look", "new_area"], "and the tools")


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
			and made.config.get("name") == "Ashen Wood" and made.config.get("about") == "a burnt wood" and made.config.get("zone") == "outdoors",
			"the new level: 32 x 24, joined back on its west, named, outdoors like the field it leads from")
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


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
