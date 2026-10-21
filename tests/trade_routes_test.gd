extends Node
## Trade routes (decision 504) on three strips of open ground side by side:
## the town's store in the west one, a goblin camp beside the way in the
## middle one, a market in the east one (level.json "markets"). The route
## from the town to the market is found, its way through the camp's reach
## on ground nobody holds is exposed, eta and risk follow from it; a caravan
## walks it and arrives with its cargo; struck, it loses its food and its
## people (held at the camp, rescuable) and keeps its other goods and its
## items; struck with no food and nobody, nothing is taken; with nobody
## left it is lost, its items left at the camp; a closed way loses it too;
## a restart keeps it where it was; the world map is shown the route and
## the caravan on it. Run it with tests/run.ps1 or tests/run.sh.

const RaidsTest := preload("res://tests/raids_test.gd")
const TOWN := "tr_town/store"
const MARKET := "market:far"
const ROUTE := "tr_town/store>market:far"
const CAMP := "tr_mid/camp"

var _failures := 0
var _now := 0
var _towns: Towns
var _holdings: Holdings
var _trade: TradeRoutes
var _events: Array[Array] = []


func _ready() -> void:
	World.set_process(false)
	_register(true)
	_fresh({})
	_test_route()
	_test_arrives()
	_test_raided()
	_test_nothing_to_take()
	_test_lost()
	_test_closed_way()
	_test_saved()
	_test_shown()
	_test_before_fields()
	_trade.finish()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## Three strips 30 by 5, joined east to west ([param joined]: the middle
## one's way east open).
func _register(joined: bool) -> void:
	var rows: Array[String] = []
	for y in 2 * 5 - 1:
		rows.append(".".repeat(2 * 30 - 1))
	var strip := Level.image_from_rows(rows)
	Level.register("tr_town", strip, null, {"neighbours": {"east": "tr_mid"},
		"places": {"store": {"at": [10, 2], "kind": "stockpile", "holder": "town", "radius": 3}}})
	Level.register("tr_mid", strip, null, {"neighbours": {"west": "tr_town", "east": "tr_far"} if joined else {"west": "tr_town"},
		"places": {"camp": {"at": [15, 0], "kind": "camp", "holder": "goblins", "worth": 10}}})
	Level.register("tr_far", strip, null, {"neighbours": {"west": "tr_mid"} if joined else {},
		"markets": {"far": {"at": [20, 2], "name": "the far market"}}})


func _fresh(saved: Dictionary) -> void:
	var clock := func() -> int: return _now
	var book := ItemBook.new(clock)
	var stock := Stockpile.new({}, clock, book)
	var work := Production.new({}, stock, null, clock, RaidsTest.RULES, func() -> Dictionary: return RaidsTest.CATALOG)
	_towns = Towns.new({}, work, RaidsTest.RULES, clock)
	_towns.note_rescue(TOWN, "dag", "Dag", "carpenter")
	_towns.note_rescue(TOWN, "ada", "Ada", "carpenter")
	var names: Array[String] = ["tr_town", "tr_mid", "tr_far"]
	var map := WorldMap.build(names)
	_holdings = Holdings.new(map, Factions.read(), {}, clock)
	if _trade != null:
		_trade.finish()
	_trade = TradeRoutes.new(map, _holdings, _towns, saved, {"strike_chance": 1.0})
	_trade.clock = clock
	_trade.routes_now().wait()
	_events.clear()
	for pair: Array in [["caravan_left", "left"], ["caravan_arrived", "arrived"], ["caravan_raided", "raided"], ["caravan_lost", "lost"]]:
		_trade.connect(pair[0], _note.bind(pair[1]))


## 504 amended: before the routes' distance fields are in, no route is
## made (and none cached empty), a caravan on its way keeps still rather
## than being lost, and its days are not told; once in, all as before.
func _test_before_fields() -> void:
	print("== before the routes' fields are in ==")
	_fresh({})
	_holdings.take(CAMP, Factions.NOBODY)
	var id := _trade.send(ROUTE, {"items": [], "goods": {"cloth": 1}, "members": []}, TOWN)
	_fresh({"caravans": {}})
	var fields := {"in": false}  # A lambda holds a copy of a local, not the local.
	_trade.fields_in = func() -> bool: return fields["in"]
	_check(_trade.routes().is_empty() and _trade.route(ROUTE).is_empty() and _trade.eta(ROUTE) == -1, "no route yet, nothing walked")
	_trade.fields_in = Callable()
	var sent := _trade.send(ROUTE, {"items": [], "goods": {"cloth": 1}, "members": []}, TOWN)
	_trade.fields_in = func() -> bool: return fields["in"]
	_trade._dirty()
	_tick(3)
	_check(_trade.caravans.has(sent) and float(_trade.caravans[sent]["walked"]) == 0.0 and not "lost" in _kinds() and _trade.days_left(sent) == -1.0,
		"a caravan on its way keeps still, not lost (%s)" % [_kinds()])
	_check(_trade.routes().is_empty(), "the route made before is let go with the rest, and not made again yet")
	fields["in"] = true
	_check(_trade.routes().size() == 1, "in: the route is made")
	_tick()
	_check(_trade.caravans.has(sent) and float(_trade.caravans[sent]["walked"]) > 0.0 and _trade.days_left(sent) > 0.0,
		"and the caravan walks on (%s, %s)" % [_trade.caravans.get(sent, {}).get("walked"), _kinds()])
	_trade.fields_in = Callable()
	_holdings.take(CAMP, "goblins")


func _note(a: Variant, b: Variant, c: Variant = null, d: Variant = null, what := "") -> void:
	# Signals of three and four arguments both land here, the name bound last.
	var args := [a, b, c, d].filter(func(each: Variant) -> bool: return each != null)
	var name := str(args.pop_back()) if what.is_empty() else what
	_events.append([name] + args)


func _kinds() -> Array:
	return _events.map(func(event: Array) -> String: return event[0])


func _tick(times := 1) -> void:
	for i in times:
		_now += 600
		_trade.world_tick()


func _test_route() -> void:
	print("== the route ==")
	var all := _trade.routes()
	_check(all.size() == 1 and all[0]["id"] == ROUTE, "the town to the market, one route (%s)" % [all.map(func(r: Dictionary) -> String: return r["id"])])
	var way := _trade.route(ROUTE)
	_check(way.get("areas", []) == ["tr_town", "tr_mid", "tr_far"], "through the three strips (%s)" % [way.get("areas")])
	var exposed: Array = way.get("exposed", [])
	_check(not exposed.is_empty() and exposed.all(func(each: Dictionary) -> bool: return each["camp"] == CAMP),
		"its way past the camp is exposed (%d samples)" % exposed.size())
	var steps := float(way.get("steps", 0.0))
	_check(_trade.eta(ROUTE) == ceili(steps / 10.0), "eta: its steps over 10 a world tick (%d ticks, %.1f steps)" % [_trade.eta(ROUTE), steps])
	_check(_trade.risk(ROUTE) > 0.9, "risk: a camp that always strikes makes it near certain (%.2f)" % _trade.risk(ROUTE))
	_holdings.take(CAMP, Factions.NOBODY)
	_check(_trade.route(ROUTE)["exposed"].is_empty() and _trade.risk(ROUTE) == 0.0, "the camp fallen: nothing exposed, no risk")
	_holdings.take(CAMP, "goblins")
	_check(_trade.eta("nowhere") == -1 and _trade.send("nowhere", {}, TOWN) == "", "no such route: no eta, no caravan")


func _test_arrives() -> void:
	print("== a caravan walks there ==")
	_holdings.take(CAMP, Factions.NOBODY)
	var id := _trade.send(ROUTE, {"items": [], "goods": {"cloth": 3}, "members": ["dag"]}, TOWN)
	_check(id != "" and _kinds() == ["left"], "it sets out (%s)" % [_events])
	_tick()
	var at := _trade.position(id)
	_check(at.get("area") == "tr_town" and float(at.get("fraction", 0.0)) > 0.0, "a world tick on, it is on its way (%s)" % [at])
	_tick(_trade.eta(ROUTE))
	_check(not _trade.caravans.has(id) and _kinds() == ["left", "arrived"], "it arrives (%s)" % [_kinds()])
	var arrived: Array = _events[-1] if not _events.is_empty() else []
	_check(arrived.size() == 5 and arrived[3] == MARKET and arrived[4]["goods"] == {"cloth": 3} and arrived[4]["members"] == ["dag"],
		"at the market with its cloth and Dag (%s)" % [arrived])
	var back := _trade.send(ROUTE, {"goods": {"wine": 2}, "members": ["dag"]}, MARKET)
	_tick(_trade.eta(ROUTE))
	_check(not _trade.caravans.has(back) and _events[-1][3] == TOWN, "and back home from the market the same way")
	_holdings.take(CAMP, "goblins")
	_events.clear()


func _test_raided() -> void:
	print("== struck on the way ==")
	var book := _towns.production.book()
	var sword := book.mint("sword", "stocked")
	var id := _trade.send(ROUTE, {"items": [sword], "goods": {"food": 5, "cloth": 2}, "members": ["dag", "ada"]}, TOWN)
	_tick(_trade.eta(ROUTE) + 1)
	var raided := _events.filter(func(event: Array) -> bool: return event[0] == "raided")
	_check(raided.size() == 1 and raided[0][3] == CAMP, "the camp strikes as it passes (%s)" % [raided])
	var taken: Dictionary = raided[0][4] if not raided.is_empty() else {}
	_check(taken.get("goods") == {"food": 5} and taken.get("members") == ["dag", "ada"], "it takes the food and the people (%s)" % [taken])
	var held := _towns.captives(TOWN).map(func(each: Dictionary) -> String: return "%s@%s" % [each["id"], each.get("held_by", "")])
	_check(held.has("dag@" + CAMP) and held.has("ada@" + CAMP), "held at the camp, to be rescued (%s)" % [held])
	_check(_events[-1][0] == "lost" and _events[-1][3] == "taken" and not _trade.caravans.has(id), "nobody left: the caravan is lost")
	_check(book.at_of(sword) == "camp:" + CAMP, "its sword left at the camp, not taken by the raid (%s)" % book.at_of(sword))
	_events.clear()


func _test_nothing_to_take() -> void:
	print("== struck with no food and nobody ==")
	var id := _trade.send(ROUTE, {"goods": {"cloth": 4}, "members": []}, TOWN)
	_tick(_trade.eta(ROUTE))
	_check(_kinds() == ["left", "arrived"] and _events[-1][4]["goods"] == {"cloth": 4},
		"nothing a raid takes: it walks on and arrives with its cloth (%s)" % [_kinds()])
	_check(not _trade.caravans.has(id), "and is done")
	_events.clear()


func _test_lost() -> void:
	print("== a market's way gone ==")
	_register(false)
	var names: Array[String] = ["tr_town", "tr_mid", "tr_far"]
	var map := WorldMap.build(names)
	_trade.use_map(map)
	_trade.routes_now().wait()
	_check(_trade.routes().is_empty(), "no way to the market: no route")
	_register(true)
	_trade.use_map(WorldMap.build(names))
	_trade.routes_now().wait()


func _test_closed_way() -> void:
	print("== a caravan whose way closes ==")
	_holdings.take(CAMP, Factions.NOBODY)
	var id := _trade.send(ROUTE, {"goods": {"cloth": 1}, "members": ["ada"]}, TOWN)
	_tick()
	_register(false)
	var names: Array[String] = ["tr_town", "tr_mid", "tr_far"]
	_trade.use_map(WorldMap.build(names))
	_trade.routes_now().wait()  # Till they are in, it keeps still (504 amended).
	_tick()
	_check(not _trade.caravans.has(id) and _events[-1][0] == "lost" and _events[-1][3] == "no way", "lost: no way on (%s)" % [_events.back()])
	_register(true)
	_trade.use_map(WorldMap.build(names))
	_trade.routes_now().wait()
	_holdings.take(CAMP, "goblins")
	_events.clear()


func _test_saved() -> void:
	print("== a restart ==")
	_holdings.take(CAMP, Factions.NOBODY)
	_towns.note_rescue(TOWN, "bo", "Bo", "carpenter")
	var id := _trade.send(ROUTE, {"goods": {"cloth": 2}, "members": ["bo"]}, TOWN)
	_tick(2)
	var walked := float(_trade.caravans[id]["walked"])
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_trade.to_dict()))
	_fresh(saved)
	_holdings.take(CAMP, Factions.NOBODY)  # A fresh world holds it again.
	_check(_trade.caravans.has(id) and is_equal_approx(float(_trade.caravans[id]["walked"]), walked),
		"the caravan is still on its way, as far along (%.1f)" % walked)
	_tick(_trade.eta(ROUTE))
	_check(_events.size() == 1 and _events[0][0] == "arrived", "and arrives (%s)" % [_kinds()])
	_holdings.take(CAMP, "goblins")


func _test_shown() -> void:
	print("== on the world map ==")
	var id := _trade.send(ROUTE, {"goods": {"cloth": 1}, "members": []}, TOWN)
	_tick()
	var shown := _trade.shown(["tr_town"])
	_check(shown.size() == 1 and shown[0]["from_area"] == "tr_town" and shown[0]["to_area"] == "tr_far"
		and shown[0]["caravans"].size() == 1 and shown[0]["caravans"][0]["area"] == "tr_town",
		"a player who knows the town is shown the route and the caravan on it (%s)" % [shown])
	_check(_trade.shown(["elsewhere"]).is_empty(), "one who knows none of its areas is not")
	var days := float(shown[0]["caravans"][0].get("days", -1.0))
	var expected := (_trade.eta(ROUTE) - 1) * World.WORLD_TICK_STEPS / float(DayNight.day_steps)
	_check(days > 0.0 and absf(days - expected) <= 0.01 + float(World.WORLD_TICK_STEPS) / DayNight.day_steps,
		"with the days it has still to go (%.2f, about %.2f)" % [days, expected])
	var state := WorldNews.merge({}, {"full": true, "trade": shown})
	_check(state["trade"] == shown and WorldNews.merge(state, {"full": false, "party": []})["trade"] == shown,
		"the client keeps it till it is sent again")
	_trade.caravans.erase(id)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
