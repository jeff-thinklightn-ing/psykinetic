class_name TradeRoutes
extends RefCounted
## Trade routes and the caravans that walk them (decision 504; economy's
## phase 2 of the gold economy). A route joins two ends: a town (its store's
## place id) and a market ("market:<key>", a level's "markets" cell: the
## castle market), or two towns. Its way is the world routes' open layer
## (a caravan is the town's: held ground is no wall to it; a closed link,
## 463, is no way at all). Economy sends a caravan (send) with goods, items
## and the residents who go; it walks on the world tick, saved in the
## snapshot, and arrives (caravan_arrived), where economy settles the goods
## and sends the bought ones home. Where its way crosses ground nobody holds
## within RAID_REACH of a camp hostile to the town (exposed), that camp may
## strike as it passes: a raid takes food and people only (Jeff), the
## people as captives held at the camp (Towns' resident-taken path), and a
## caravan with nobody left is lost, its items left at the camp. Abstract
## on the world map for now: position() is where a visible trader would be.
## Server only.

## A caravan left, arrived at [param at_end], was struck (what [param taken]:
## {goods, members}), or was lost ([param why]: "taken", nobody left after
## a raid; "no way", its way closed).
signal caravan_left(id: String, route_id: String, cargo: Dictionary)
signal caravan_arrived(id: String, route_id: String, at_end: String, cargo: Dictionary)
signal caravan_raided(id: String, route_id: String, camp_id: String, taken: Dictionary)
signal caravan_lost(id: String, route_id: String, why: String)

## levels/economy.json trade.routes, these unless it says otherwise.
const DEFAULTS := {
	# Route steps a caravan covers a world tick (a raid group's 12: loaded
	# carts go no faster).
	"steps_per_world_tick": 10.0,
	# How near a camp a stretch of the way is in its reach, in cells.
	"raid_reach": 30.0,
	# A camp of full worth (raids' size_full) strikes a caravan passing in
	# its reach with this chance a world tick; less worth, less.
	"strike_chance": 0.15,
	# A stretch of the way is looked at every this many steps.
	"sample_steps": 4.0,
}
const RULES := "res://levels/economy.json"
const MARKET := "market:"

var world_map: WorldMap
var holdings: Holdings
var towns: Towns
var rules := {}
## () -> WorldRoutes: the routes to walk (Main: the raid groups', one set of
## distance fields for both); its own when not set.
var get_routes := Callable()
## (kind) -> bool: whether goods of that kind are food (economy's Economy);
## "food" and "meat" when not set.
var is_food := Callable()
## (camp place id) -> 0..1: the chance that camp strikes a caravan in its
## reach this world tick (enemy-ai's to replace); strike_chance by its worth
## when not set.
var strike := Callable()
## () -> int: the World's steps, for ids.
var clock := func() -> int: return 0
var rng := RandomNumberGenerator.new()
## Id -> {id, route, from (end), to (end), town, cargo {items, goods,
## members}, walked (steps)}.
var caravans: Dictionary[String, Dictionary] = {}
var _own_routes: WorldRoutes
## Route id -> {id, from, to, legs, steps, areas, exposed}, made when asked.
var _routes: Dictionary[String, Dictionary] = {}
var _routes_made := false
## Caravan id -> {legs, steps, exposed}: its way, made again when wanted.
var _ways: Dictionary[String, Dictionary] = {}


func _init(map: WorldMap, with_holdings: Holdings, with_towns: Towns, saved := {}, with_rules := {}) -> void:
	world_map = map
	holdings = with_holdings
	towns = with_towns
	rules = DEFAULTS.duplicate()
	var read: Variant = with_rules if not with_rules.is_empty() else _read_rules()
	if read is Dictionary:
		rules.merge(read, true)
	if holdings != null:
		holdings.place_taken.connect(_on_place_taken)
	from_dict(saved)


static func _read_rules() -> Dictionary:
	if not FileAccess.file_exists(RULES):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(RULES)) != OK or not json.data is Dictionary:
		return {}
	var trade: Variant = (json.data as Dictionary).get("trade", {})
	var routes_rules: Variant = trade.get("routes", {}) if trade is Dictionary else {}
	return routes_rules if routes_rules is Dictionary else {}


func routes_now() -> WorldRoutes:
	if get_routes.is_valid():
		return get_routes.call()
	if _own_routes == null:
		_own_routes = holdings.make_routes(world_map)
	return _own_routes


## Waits for its own routes' fields, if it made them: before the server quits.
func finish() -> void:
	if _own_routes != null:
		_own_routes.wait()


## The world as [param map] has it now (a level regenerated, 465): every
## route and caravan's way made again when next wanted.
func use_map(map: WorldMap) -> void:
	finish()
	world_map = map
	_own_routes = null
	_dirty()


func _dirty() -> void:
	_routes.clear()
	_routes_made = false
	_ways.clear()


func _on_place_taken(_id: String, _from: String, _to: String) -> void:
	_dirty()  # Who holds what moved what is exposed, and whose towns these are.


# --- Ends and routes ------------------------------------------------------------

## End [param end]'s {id, area, cell, name, town (its town id, "" for a
## market)}; {} if there is none.
func end_of(end: String) -> Dictionary:
	if end.begins_with(MARKET):
		var market: Dictionary = world_map.markets().get(end, {})
		return {} if market.is_empty() else {"id": end, "area": market["area"], "cell": market["cell"], "name": market["name"], "town": ""}
	var place := holdings.place(end)
	if place.is_empty() or towns == null or not towns.to_dict().has(end):
		return {}
	return {"id": end, "area": place["area"], "cell": place["cell"], "name": place["name"], "town": end}


## Every route there is: each town to each market, and each pair of towns,
## that can be walked; {id, from, to, legs, steps, areas, exposed: [{at
## (steps along), camp}]}, from -> to.
func routes() -> Array[Dictionary]:
	_make_routes()
	var out: Array[Dictionary] = []
	var ids := _routes.keys()
	ids.sort()
	for id: String in ids:
		out.append(_routes[id])
	return out


func route(route_id: String) -> Dictionary:
	_make_routes()
	return _routes.get(route_id, {})


func _make_routes() -> void:
	if _routes_made:
		return
	_routes_made = true
	var town_ids: Array = towns.to_dict().keys() if towns != null else []
	town_ids.sort()
	var market_ids := world_map.markets().keys()
	market_ids.sort()
	var pairs: Array[Array] = []
	for i in town_ids.size():
		for market: String in market_ids:
			pairs.append([town_ids[i], market])
		for j in range(i + 1, town_ids.size()):
			pairs.append([town_ids[i], town_ids[j]])
	for pair: Array in pairs:
		var way := _way(pair[0], pair[1])
		if way.is_empty():
			continue
		var id := "%s>%s" % pair
		way["id"] = id
		way["from"] = pair[0]
		way["to"] = pair[1]
		_routes[id] = way


## The way from end [param from] to end [param to]: {legs, steps, areas,
## exposed}; {} if it cannot be walked.
func _way(from: String, to: String) -> Dictionary:
	var a := end_of(from)
	var b := end_of(to)
	if a.is_empty() or b.is_empty():
		return {}
	var routes := routes_now()
	var legs := routes.route(a["area"], a["cell"], b["area"], b["cell"])
	if legs.is_empty():
		return {}
	var steps := WorldRoutes.CROSSING * (legs.size() - 1)
	var areas: Array[String] = []
	for leg: Dictionary in legs:
		steps += float(leg["steps"])
		if leg["area"] not in areas:
			areas.append(leg["area"])
	var town: String = a["town"] if not a["town"].is_empty() else b["town"]
	return {"legs": legs, "steps": steps, "areas": areas, "exposed": _exposed(legs, steps, town)}


## Where along [param legs] ([param steps] long) the way is in a hostile
## camp's reach on ground nobody holds: [{at, camp}], one a sample_steps.
func _exposed(legs: Array[Dictionary], steps: float, town: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var side := holdings.holder(town) if not town.is_empty() else Stockpile.TOWN
	var hostile: Array[Dictionary] = []
	for camp: Dictionary in holdings.camps():
		if holdings.factions.hostile(camp["faction"], side):
			hostile.append(camp)
	if hostile.is_empty():
		return out
	var reach := float(rules["raid_reach"])
	var routes := routes_now()
	var at := 0.0
	while at <= steps:
		var here := routes.along(legs, at)
		if not here.is_empty() and holdings.ground(here["area"], here["cell"]) == Factions.NOBODY:
			var nearest := ""
			var nearest_d := INF
			for camp: Dictionary in hostile:
				if camp["area"] != here["area"]:
					continue
				var d := Vector2(camp["cell"] - here["cell"]).length()
				if d <= reach and d < nearest_d:
					nearest = camp["id"]
					nearest_d = d
			if nearest != "":
				out.append({"at": at, "camp": nearest})
		at += float(rules["sample_steps"])
	return out


## World ticks a caravan takes over route [param route_id]; -1 for no route.
func eta(route_id: String) -> int:
	var way := route(route_id)
	return -1 if way.is_empty() else ceili(float(way["steps"]) / float(rules["steps_per_world_tick"]))


## The chance, 0..1, a caravan over route [param route_id] is struck at
## least once on the way: each world tick spent in a camp's reach a chance
## of that camp's strike.
func risk(route_id: String) -> float:
	var way := route(route_id)
	if way.is_empty():
		return 0.0
	var safe := 1.0
	var per_tick := float(rules["sample_steps"]) / float(rules["steps_per_world_tick"])
	for each: Dictionary in way["exposed"]:
		safe *= pow(1.0 - _strike_chance(each["camp"]), per_tick)
	return clampf(1.0 - safe, 0.0, 1.0)


func _strike_chance(camp_id: String) -> float:
	if strike.is_valid():
		return clampf(float(strike.call(camp_id)), 0.0, 1.0)
	var worth := float(holdings.place(camp_id).get("worth", 1))
	return clampf(float(rules["strike_chance"]) * clampf(worth / 10.0, 0.0, 1.0), 0.0, 1.0)


# --- Caravans ---------------------------------------------------------------------

## A caravan over [param route_id] from its end [param from_end] (either
## end), carrying [param cargo] {items: [uids], goods: {kind: n}, members:
## [resident ids]}: its id, or "" for no such route or end.
func send(route_id: String, cargo: Dictionary, from_end: String) -> String:
	var way := route(route_id)
	if way.is_empty() or from_end not in [way["from"], way["to"]]:
		return ""
	var to_end: String = way["to"] if from_end == way["from"] else way["from"]
	var id := "caravan:%s:%d" % [from_end, int(clock.call())]
	while caravans.has(id):
		id += "+"
	var carried := {"items": cargo.get("items", []).duplicate(), "goods": cargo.get("goods", {}).duplicate(),
		"members": cargo.get("members", []).duplicate()}
	var town: String = way["from"] if not way["from"].begins_with(MARKET) else way["to"]
	caravans[id] = {"id": id, "route": route_id, "from": from_end, "to": to_end, "town": town, "cargo": carried, "walked": 0.0}
	print("[trade] %s sets out from %s for %s with %s" % [id, from_end, to_end, carried])
	caravan_left.emit(id, route_id, carried)
	return id


## Where caravan [param id] is: {area, cell, fraction (of its way)}; {} for
## none.
func position(id: String) -> Dictionary:
	if not caravans.has(id):
		return {}
	var way := _caravan_way(id)
	if way.is_empty():
		return {}
	var walked := float(caravans[id]["walked"])
	var here := routes_now().along(way["legs"], walked)
	return {"area": here["area"], "cell": here["cell"], "fraction": clampf(walked / maxf(float(way["steps"]), 1.0), 0.0, 1.0)}


## The days (game days, a float) until caravan [param id] reaches the end
## it is bound for: the steps left at steps_per_world_tick a world tick (ui's
## hover: "two days out"); -1 for none.
func days_left(id: String) -> float:
	if not caravans.has(id):
		return -1.0
	var way := _caravan_way(id)
	if way.is_empty():
		return -1.0
	var left := maxf(float(way["steps"]) - float(caravans[id]["walked"]), 0.0)
	return left / float(rules["steps_per_world_tick"]) * World.WORLD_TICK_STEPS / float(DayNight.day_steps)


func _caravan_way(id: String) -> Dictionary:
	if not _ways.has(id):
		var caravan := caravans[id]
		_ways[id] = _way(caravan["from"], caravan["to"])
	return _ways[id]


## Every caravan's step, its raids, its arrival.
func world_tick() -> void:
	for id: String in caravans.keys():
		if caravans.has(id):
			_move(id)


func _move(id: String) -> void:
	var caravan := caravans[id]
	var way := _caravan_way(id)
	if way.is_empty():
		print("[trade] %s has no way on to %s: lost" % [id, caravan["to"]])
		_lose(id, "no way", "")
		return
	var before := float(caravan["walked"])
	var after := before + float(rules["steps_per_world_tick"])
	caravan["walked"] = after
	var struck := {}
	for each: Dictionary in way["exposed"]:
		var at := float(each["at"])
		if at > before and at <= after and not struck.has(each["camp"]):
			struck[each["camp"]] = true
			if rng.randf() < _strike_chance(each["camp"]):
				_raid(id, each["camp"])
				if not caravans.has(id):
					return
	if after >= float(way["steps"]):
		print("[trade] %s arrives at %s" % [id, caravan["to"]])
		var cargo: Dictionary = caravan["cargo"]
		_end(id)
		caravan_arrived.emit(id, caravan["route"], caravan["to"], cargo)


## Camp [param camp_id] strikes caravan [param id]: its food and its people
## taken, nothing else (Jeff: raids take food and people only).
func _raid(id: String, camp_id: String) -> void:
	var caravan := caravans[id]
	var cargo: Dictionary = caravan["cargo"]
	var faction := holdings.holder(camp_id)
	var taken := {"goods": {}, "members": []}
	for kind: String in cargo["goods"].keys():
		if _food(kind):
			taken["goods"][kind] = cargo["goods"][kind]
			cargo["goods"].erase(kind)
	for who: String in cargo["members"].duplicate():
		if towns != null and towns.resident_taken(caravan["town"], who, id, faction):
			towns.captive_held(who, camp_id)
		taken["members"].append(who)
		cargo["members"].erase(who)
	if taken["goods"].is_empty() and taken["members"].is_empty():
		print("[trade] %s is struck by %s: nothing it takes" % [id, camp_id])
		return
	print("[trade] %s is struck by %s, who take %s" % [id, camp_id, taken])
	caravan_raided.emit(id, caravan["route"], camp_id, taken)
	if cargo["members"].is_empty():
		_lose(id, "taken", camp_id)


func _food(kind: String) -> bool:
	return bool(is_food.call(kind)) if is_food.is_valid() else kind in ["food", "meat"]


## Caravan [param id] gone, for [param why]; struck by [param camp_id],
## its things are left at the camp (ItemBook, as raid plunder is).
func _lose(id: String, why: String, camp_id: String) -> void:
	var caravan := caravans[id]
	if not camp_id.is_empty() and towns != null and towns.production != null:
		var book := towns.production.book()
		for uid: Variant in caravan["cargo"]["items"]:
			if book.has(int(uid)):
				book.place(int(uid), "camp:%s" % camp_id)
				book.note(int(uid), "taken from a caravan", "by %s (%s)" % [holdings.holder(camp_id), id])
	_end(id)
	caravan_lost.emit(id, caravan["route"], why)


func _end(id: String) -> void:
	caravans.erase(id)
	_ways.erase(id)


## What the world map shows of the routes touching [param areas] (a
## player's known areas; every route when empty): [{id, from_area, to_area,
## areas, caravans: [{area, fraction}]}] (the "world" message's "trade").
func shown(areas: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for way: Dictionary in routes():
		if not areas.is_empty() and not way["areas"].any(func(area: String) -> bool: return area in areas):
			continue
		var on_it: Array[Dictionary] = []
		for id: String in caravans:
			if caravans[id]["route"] != way["id"]:
				continue
			var at := position(id)
			if not at.is_empty():
				var fraction: float = at["fraction"] if caravans[id]["from"] == way["from"] else 1.0 - float(at["fraction"])
				on_it.append({"area": at["area"], "fraction": snappedf(fraction, 0.01), "days": snappedf(days_left(id), 0.01)})
		out.append({"id": way["id"], "from_area": way["areas"][0], "to_area": way["areas"][-1], "areas": way["areas"].duplicate(),
			"caravans": on_it})
	return out


# --- Saved ----------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"caravans": caravans.duplicate(true)}


func from_dict(saved: Dictionary) -> void:
	caravans.clear()
	_ways.clear()
	var listed: Variant = saved.get("caravans", {})
	if listed is Dictionary:
		for id: String in listed:
			var caravan: Variant = listed[id]
			if caravan is Dictionary and caravan.has("route") and caravan.has("from") and caravan.has("to"):
				var restored: Dictionary = (caravan as Dictionary).duplicate(true)
				restored["walked"] = float(restored.get("walked", 0.0))
				caravans[id] = restored
