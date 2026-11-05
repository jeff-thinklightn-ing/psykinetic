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
		"camp": {"at": [30, 10], "kind": "camp", "holder": "goblins", "radius": 2, "worth": 4},
		"cave": {"at": [10, 18], "kind": "refuge", "where": "wilds", "name": "a cave where the rocks fell", "shown": "a cave", "radius": 2},
		"den": {"at": [36, 18], "kind": "refuge", "where": "wilds", "radius": 2},
		"cairn": {"at": [20, 18], "kind": "other", "name": "the cairn", "radius": 2, "explore": true}}})
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

	print("== trade (decision 504) ==")
	var routes: Array = [{"id": "r", "from_area": "wn_town", "to_area": "wn_wild", "areas": ["wn_town", "wn_wild"], "caravans": []}]
	var asked: Array = []
	news.trade = func(areas: Array) -> Array:
		asked.append(areas.duplicate())
		return routes.duplicate(true)
	_sent.clear()
	news.update()
	ann = _to(1)
	_check(ann.size() == 1 and ann[0]["trade"] == routes and not ann[0].has("party") and asked.has(["wn_town", "wn_wild"]),
		"the trade routes through what Ann knows, sent once they are there (%s)" % [ann])
	_sent.clear()
	news.update()
	_check(_to(1).is_empty(), "not again while they are the same")
	routes[0]["caravans"] = [{"area": "wn_town", "fraction": 0.2}]
	news.update()
	_check(_to(1).size() == 1 and _to(1)[0]["trade"][0]["caravans"].size() == 1, "a caravan on its way: sent again")
	news.trade = Callable()

	print("== told (decision 805) ==")
	_sent.clear()
	_check(news.tell("bo", "wn_wild/camp"), "Bo is told of the camp he has never come near")
	bo = _to(2)
	_check(bo.size() == 1 and bo[0]["known"] == {"areas": [], "places": ["wn_wild/camp"]} and bo[0]["holdings"] == {"wn_wild/camp": [Factions.NOBODY, 1]}
			and _records["bo"].known_places.has("wn_wild/camp") and _to(1).is_empty(),
		"it is known to him now, sent with whose it is, to him only (%s)" % [_sent])
	_sent.clear()
	_check(not news.tell("bo", "wn_wild/camp") and _sent.is_empty(), "told again: nothing new, nothing sent")
	_check(not news.tell("bo", "wn_wild/nowhere") and not news.tell("nobody_here", "wn_wild/camp") and _sent.is_empty(),
		"a place no level has, or a player with no record: nothing")
	var away := PlayerRecord.new()
	away.player_id = "cy"
	_records["cy"] = away
	_check(news.tell("cy", "wn_town/store") and away.known_places == _strings(["wn_town/store"]) and _sent.is_empty(),
		"a player not in the game: kept on the record, sent with the full message when they come")
	_records.erase("cy")

	print("== kept ==")
	var again := PlayerRecord.from_dict(JSON.parse_string(JSON.stringify(_records["ann"].to_dict())))
	_check(again.known_areas == _strings(["wn_town", "wn_wild"]) and again.known_places == _strings(["wn_town/store", "wn_wild/camp"]),
		"Ann's known areas and places survive her record's save (%s, %s)" % [again.known_areas, again.known_places])
	var old: Dictionary = _records["bo"].to_dict()
	old.erase("known_areas")
	old.erase("known_places")
	_check(PlayerRecord.from_dict(old).known_areas.is_empty(), "a record from before knows nothing yet")

	print("== reached (decision 804, maps' side) ==")
	_check(holdings.explorables_in("wn_wild") == _strings(["wn_wild/cairn", "wn_wild/cave"]) and holdings.explorables_in("wn_town").is_empty(),
		"the named refuge and the place marked explore count; the camp, the store and a refuge with no name of its own do not (%s)" % [holdings.explorables_in("wn_wild")])
	_check(news.explore(2, "wn_wild", Vector2i(10, 15)).is_empty() and news.explored_in(2, "wn_wild") == {"have": 0, "need": 2},
		"three cells off the cave (its radius 2): not reached (%s)" % [news.explored_in(2, "wn_wild")])
	var reached := news.explore(2, "wn_wild", Vector2i(10, 16))
	_check(reached == _strings(["wn_wild/cave"]) and _records["bo"].explored_places == _strings(["wn_wild/cave"]) and news.explored_in(2, "wn_wild") == {"have": 1, "need": 2},
		"within its radius: reached once, kept on Bo's record, 1 of the wilds' 2 (%s)" % [reached])
	_check(news.explore(2, "wn_wild", Vector2i(10, 18)).is_empty(), "and never again")
	_check(news.explore(1, "wn_wild", Vector2i(10, 18)) == _strings(["wn_wild/cave"]), "Ann reaches it for herself")
	var joining := WorldNews.new(holdings)
	joining.send = news.send
	joining.peers = news.peers
	joining.record_of = news.record_of
	joining.members = news.members
	_check(joining.explore(2, "wn_wild", Vector2i(20, 18)).is_empty() and not _records["bo"].explored_places.has("wn_wild/cairn"),
		"before their full message (a join's first tick): nothing reached, nothing kept")
	var bo_again := PlayerRecord.from_dict(JSON.parse_string(JSON.stringify(_records["bo"].to_dict())))
	_check(bo_again.explored_places == _strings(["wn_wild/cave"]), "the places reached survive the record's save")
	_check(holdings.place("wn_wild/cave")["shown"] == "a cave" and holdings.place("wn_wild/cairn")["shown"] == "the cairn"
		and Main.banner_of("the Old Tower") == "Old Tower" and Main.banner_of("Hollowfell") == "Hollowfell" and Main.banner_of("a hill cave") == "Hill cave",
		"a place's shown name, else its name; a banner drops the article")
	_sent.clear()
	var fresh := PlayerRecord.new()
	fresh.player_id = "cy"
	fresh.known_areas = _strings(["wn_wild"])
	fresh.explored_places = _strings(["wn_wild/cave"])
	_records["cy"] = fresh
	_peers[3] = "cy"
	news.update()
	var cy := _to(3)
	_check(cy.size() == 1 and cy[0]["explored"] == {"wn_wild": [1, 2]}, "a full message carries each known area's places reached of all (%s)" % [cy])
	_sent.clear()
	news.observe(3, "wn_town", Vector2i(30, 15))
	cy = _to(3)
	_check(cy.size() == 1 and cy[0]["explored"] == {"wn_town": [0, 0]}, "an area newly known: its count with it (%s)" % [cy])
	_peers.erase(3)
	var folded := WorldNews.merge({}, {"full": true, "holdings": {}, "known": {"areas": ["a"], "places": []}, "party": [], "explored": {"a": [1, 3]}})
	folded = WorldNews.merge(folded, {"full": false, "known": {"areas": ["b"], "places": []}, "explored": {"b": [0, 2]}})
	_check(folded["explored"] == {"a": [1, 3], "b": [0, 2]}, "the client keeps each area's count (%s)" % [folded["explored"]])
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
