extends Node
## The town's store in builder mode (decision 301): the town_store prefab
## stamped by the builder brings a stockpile place the town holds, a depot
## and a shop counter facing the yard, and Stockpile.check finds nothing
## wrong; the place tool's use makes a chest a depot or a shop counter,
## and refuses it on anything else or with items; Stockpile.check says
## what is wrong with a store: a counter outside it, a store held by the
## goblins, two that overlap, one with no depot, a depot given items.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

var _failures := 0


func _ready() -> void:
	World.set_process(false)
	_test_prefab()
	_test_place_use()
	_test_check()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _doc() -> MapDoc:
	var doc := MapDoc.new()
	doc.folder = preload("res://tests/test_ports.gd").scratch("town_store_test/")
	doc.map = LevelMap.new(Vector2i(30, 20))
	for y in 20:
		for x in 30:
			doc.map.set_cell(Vector2i(x, y), "grass")
	doc.config = {"name": "Test Town", "outdoor": true}
	return doc


func _test_prefab() -> void:
	print("\n== the town_store prefab, stamped by the builder ==")
	_check("town_store" in Prefab.names() and "town_store (7 x 5)" in BuilderSession.system_prompt(), "the builder is told of town_store (7 x 5)")
	var session := BuilderSession.new(_doc(), Rect2i(5, 5, 15, 10), "test_town", StubClaude.new())
	var done := session.run_tool("stamp", {"prefab": "town_store", "at": [8, 7]})
	_check(done["ok"], "stamped at (8, 7) (%s)" % done["text"])
	var config: Dictionary = session.working.config
	var store: Dictionary = config.get("places", {}).get("store", {})
	_check(store.get("kind") == "stockpile" and store.get("holder") == "town" and store.get("at") == [11, 9] and store.get("radius") == 4,
		"it brings the store: a stockpile the town holds at (11, 9), radius 4 (%s)" % [store])
	var entries: Array = config.get("entities", [])
	var depot: Array = entries.filter(func(entry: Dictionary) -> bool: return entry.get("props", {}).get("depot") == true)
	var shop: Array = entries.filter(func(entry: Dictionary) -> bool: return entry.get("props", {}).get("shop") == true)
	_check(depot.size() == 1 and Level._tile(depot[0]["at"]) == Vector2i(10, 8) and shop.size() == 1
		and Level._tile(shop[0]["at"]) == Vector2i(12, 8) and Level._tile(shop[0].get("facing")) == Vector2i(0, 1) and session.working.map.cell(Vector2i(12, 8)) == "chest",
		"a depot at (10, 8) and a shop counter at (12, 8), chests facing the yard (%s)" % [entries])
	var nearby_walls := 0
	for x in range(8, 15):
		for y in range(7, 12):
			for side in [Terrain.EAST, Terrain.SOUTH]:
				if session.working.map.edge(Vector3i(x, y, side)) != "clear":
					nearby_walls += 1
	_check(nearby_walls == 0, "an open yard: no wall or door in it to hide them")
	_check(Stockpile.check(config).is_empty(), "nothing wrong with it (%s)" % [Stockpile.check(config)])
	session.run_tool("stamp", {"prefab": "town_store", "at": [12, 7]})
	var warnings := Stockpile.check(session.working.config)
	_check(session.working.config["places"].has("store_2") and warnings.any(func(line: String) -> bool: return "overlap" in line),
		"a second one beside it: store_2, and check says the two overlap (%s)" % [warnings])


func _test_place_use() -> void:
	print("\n== the place tool's use: a depot or a shop counter ==")
	var session := BuilderSession.new(_doc(), Rect2i(5, 5, 15, 10), "test_town", StubClaude.new())
	session.run_tool("mark_place", {"key": "store", "kind": "stockpile", "at": [10, 10], "radius": 3, "holder": "town"})
	_check(session.run_tool("place", {"at": [9, 9], "thing": "chest", "use": "depot"})["ok"], "a chest placed with use depot")
	_check(session.run_tool("place", {"at": [11, 9], "thing": "chest", "use": "shop", "facing": "east"})["ok"], "and one with use shop, facing east")
	var entries: Array = session.working.config.get("entities", [])
	_check(entries.any(func(entry: Dictionary) -> bool: return entry["at"] == [9, 9] and entry["props"] == {"depot": true} and entry["facing"] == [0, 1])
		and entries.any(func(entry: Dictionary) -> bool: return entry["at"] == [11, 9] and entry["props"] == {"shop": true} and entry["facing"] == [1, 0]),
		"their props: depot facing south by default, shop facing east (%s)" % [entries])
	_check(Stockpile.check(session.working.config).is_empty(), "inside the store: nothing wrong")
	var refused := session.run_tool("place", {"at": [12, 12], "thing": "crate", "use": "shop"})
	_check(not refused["ok"] and "chest only" in refused["text"], "use on a crate: refused (%s)" % refused["text"])
	refused = session.run_tool("place", {"at": [12, 12], "thing": "chest", "use": "shop", "items": ["bandaging_kit"]})
	_check(not refused["ok"] and "no items" in refused["text"], "a shop counter given items: refused (%s)" % refused["text"])
	session.run_tool("place", {"at": [18, 13], "thing": "chest", "use": "shop"})
	var warnings := Stockpile.check(session.working.config)
	_check(warnings == ["the shop counter at (18, 13) does nothing: no store the town holds covers it"],
		"a counter placed outside the store: check says so (%s)" % [warnings])


func _test_check() -> void:
	print("\n== Stockpile.check ==")
	var goblins := {"places": {"store": {"at": [5, 5], "kind": "stockpile", "radius": 3, "holder": "goblins"}},
		"entities": [{"at": [5, 4], "props": {"depot": true}}]}
	var warnings := Stockpile.check(goblins)
	_check(warnings.size() == 2 and "does nothing" in warnings[0] and "held by goblins" in warnings[1] and warnings == Stockpile.check(goblins),
		"a store the goblins hold: its depot does nothing, and it isn't the town's, sorted (%s)" % [warnings])
	var bare := {"places": {"store": {"at": [5, 5], "kind": "stockpile", "radius": 3, "holder": "town"}, "camp": {"at": [1, 1], "kind": "camp"}}}
	_check(Stockpile.check(bare) == ["the store store has no depot: what is put down there is banked, but nothing can be put in"],
		"a store with no depot: said; a camp is no concern of it (%s)" % [Stockpile.check(bare)])
	var stocked := {"places": bare["places"], "entities": [{"at": [5, 5], "props": {"depot": true, "slots": ["bandaging_kit", "", "", ""]}}]}
	_check(Stockpile.check(stocked) == ["the depot at (5, 5) keeps nothing: its items would be lost"], "a depot given items: said")
	_check(Stockpile.check({}).is_empty() and Stockpile.check({"places": 3, "entities": "x"}).is_empty(), "no places, or nonsense: nothing to say")


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
