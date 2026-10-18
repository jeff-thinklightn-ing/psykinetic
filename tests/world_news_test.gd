extends Node
## The world message (decision 446), WorldNews with stand-ins for Main: a
## player's full message once they are in (their known areas and places,
## the holdings of those only, the party in other zones); standing in an
## area makes it known, coming within 7 cells of a place makes it known,
## each sent as it happens with the place's holding; a place taken goes
## only to players who know it; the party is sent again when someone
## changes zone, never with the receiver or their own zone's; the known
## lists survive a record's save; and the client folds the messages into
## Main.world_state. Run it with tests/run.ps1 or tests/run.sh.

var _failures := 0
var _sent: Array = []  # [peer, data]
var _peers := {1: "ann", 2: "bo"}
var _records := {}
var _members: Array = []


func _ready() -> void:
	World.set_process(false)
	var rows: Array[String] = []
	for y in 2 * 20 - 1:
		rows.append(".".repeat(2 * 40 - 1))
	var ground := Level.image_from_rows(rows)
	Level.register("wn_town", ground, null, {"outdoor": true, "neighbours": {"east": "wn_wild"}, "places": {
		"store": {"at": [5, 5], "kind": "stockpile", "holder": "town", "radius": 3}}})
	Level.register("wn_wild", ground, null, {"outdoor": true, "neighbours": {"west": "wn_town"}, "places": {
		"camp": {"at": [30, 10], "kind": "camp", "holder": "goblins", "radius": 2, "worth": 4}}})
	var names: Array[String] = ["wn_town", "wn_wild"]
	var holdings := Holdings.new(WorldMap.build(names), Factions.read(), {})
	for id: String in _peers.values():
		var record := PlayerRecord.new()
		record.player_id = id
		record.name = id.capitalize()
		_records[id] = record
	_members = [{"name": "Ann", "area": "wn_town", "kind": "player", "peer": 1},
		{"name": "Bo", "area": "wn_town", "kind": "player", "peer": 2},
		{"name": "Wren", "area": "wn_wild", "kind": "companion", "peer": 1}]
	var news := WorldNews.new(holdings)
	news.send = func(peer: int, data: Dictionary) -> void: _sent.append([peer, data])
	news.peers = func() -> Dictionary: return _peers
	news.record_of = func(id: String) -> PlayerRecord: return _records.get(id)
	news.members = func() -> Array: return _members

	print("== in the game ==")
	news.observe(1, "wn_town", Vector2i(6, 6))
	news.update()
	var ann := _to(1)
	_check(ann.size() == 1 and ann[0]["full"] == true, "Ann gets one full message once she is in")
	_check(ann[0]["known"] == {"areas": ["wn_town"], "places": ["wn_town/store"]} and ann[0]["holdings"] == {"wn_town/store": ["town", 1]},
		"her town and its store, near her, with who holds it (%s)" % [ann[0]])
	_check(ann[0]["party"] == [{"name": "Wren", "area": "wn_wild", "kind": "companion"}],
		"the party out of her zone: her companion in the wilds, not Bo beside her (%s)" % [ann[0]["party"]])
	_sent.clear()
	news.update()
	_check(_sent.is_empty(), "nothing again while nothing changes")

	print("== seen ==")
	news.observe(1, "wn_wild", Vector2i(2, 10))
	ann = _to(1)
	_check(ann.size() == 1 and ann[0]["known"] == {"areas": ["wn_wild"], "places": []} and not ann[0].has("party"),
		"standing in the wilds: the area is known, the camp far off is not (%s)" % [ann])
	_sent.clear()
	news.observe(1, "wn_wild", Vector2i(22, 10))
	_check(_to(1).is_empty(), "8 cells off the camp: still unknown")
	news.observe(1, "wn_wild", Vector2i(23, 10))
	ann = _to(1)
	_check(ann.size() == 1 and ann[0]["known"]["places"] == ["wn_wild/camp"] and ann[0]["holdings"] == {"wn_wild/camp": ["goblins", 1]},
		"within 7 cells: the camp is known, and whose (%s)" % [ann])

	print("== changes ==")
	news.observe(2, "wn_town", Vector2i(30, 15))
	news.update()
	_sent.clear()
	holdings.take("wn_wild/camp", Factions.NOBODY)
	_check(_to(1).size() == 1 and _to(1)[0]["holdings"] == {"wn_wild/camp": [Factions.NOBODY, 1]} and _to(2).is_empty(),
		"the camp taken: told to Ann, who knows it, not to Bo (%s)" % [_sent])
	_sent.clear()
	_members[0]["area"] = "wn_wild"
	news.update()
	ann = _to(1)
	var bo := _to(2)
	_check(ann.size() == 1 and ann[0]["party"] == [{"name": "Bo", "area": "wn_town", "kind": "player"}],
		"Ann goes to the wilds: her party is Bo in town now, Wren beside her left out (%s)" % [ann])
	_check(bo.size() == 1 and bo[0]["party"].size() == 2, "and Bo's has Ann and Wren in the wilds (%s)" % [bo])

	print("== kept ==")
	var again := PlayerRecord.from_dict(JSON.parse_string(JSON.stringify(_records["ann"].to_dict())))
	_check(again.known_areas == _strings(["wn_town", "wn_wild"]) and again.known_places == _strings(["wn_town/store", "wn_wild/camp"]),
		"Ann's known areas and places survive her record's save (%s, %s)" % [again.known_areas, again.known_places])
	var old: Dictionary = _records["bo"].to_dict()
	old.erase("known_areas")
	old.erase("known_places")
	_check(PlayerRecord.from_dict(old).known_areas.is_empty(), "a record from before knows nothing yet")

	print("== the client ==")
	var state := WorldNews.merge({}, {"full": true, "holdings": {"a/x": ["town", 1]}, "known": {"areas": ["a"], "places": ["a/x"]}, "party": []})
	state = WorldNews.merge(state, {"full": false, "known": {"areas": ["b"], "places": ["b/y"]}, "holdings": {"b/y": ["goblins", 2]}})
	state = WorldNews.merge(state, {"full": false, "holdings": {"a/x": ["nobody", 0]}})
	state = WorldNews.merge(state, {"full": false, "party": [{"name": "Bo", "area": "b", "kind": "player"}]})
	_check(state["known_areas"] == ["a", "b"] and state["known_places"] == ["a/x", "b/y"]
		and state["holdings"] == {"a/x": ["nobody", 0], "b/y": ["goblins", 2]} and state["party"].size() == 1,
		"world_state folds each in (%s)" % [state])
	state = WorldNews.merge(state, {"full": true, "holdings": {}, "known": {"areas": ["c"], "places": []}, "party": []})
	_check(state["known_areas"] == ["c"] and state["holdings"].is_empty(), "a full one starts it again")
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _to(peer: int) -> Array:
	return _sent.filter(func(each: Array) -> bool: return each[0] == peer).map(func(each: Array) -> Dictionary: return each[1])


func _strings(values: Array) -> Array[String]:
	var out: Array[String] = []
	out.assign(values)
	return out


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
