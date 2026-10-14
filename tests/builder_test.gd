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
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## A 40 x 30 level of grass, outdoors, with a brute at (30, 5).
func _doc() -> MapDoc:
	var doc := MapDoc.new()
	doc.folder = "user://builder_test/"
	doc.map = LevelMap.new(Vector2i(40, 30))
	for y in 30:
		for x in 40:
			doc.map.set_cell(Vector2i(x, y), "grass")
	doc.map.set_cell(Vector2i(30, 5), "monster_brute")
	doc.config = {"name": "Test Field", "outdoor": true, "entities": [{"at": [30, 5], "idle": "guard"}]}
	return doc


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
			== ["paint", "edges", "path", "pond", "grove", "scatter", "fence", "place", "stamp", "look"], "and the tools")


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


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
