class_name Towns
extends RefCounted
## How each town grows (economy, step 4): its experience, its residents and
## its buildings. A town is a stockpile place (by id). World keeps one
## (World.towns), made by Main at boot after Production; saved in the
## snapshot ("towns": to_dict). Server only.
##
## Experience comes in through hooks that whatever decides these things
## calls: add_xp (anything), note_rescue (a rescued person reaches the town
## alive, once freed), note_objective (a story objective done: the big
## reward). Nothing ever takes it; it goes only on what the town spends.
## A companion left in town is a resident too while it stays
## (note_companion_in / note_companion_out).
##
## A rescued person becomes a resident: a Production worker ("rescued:<who>")
## seated at a workshop of their trade, if the town has the building their
## trade works in (rules "buildings", each with the trade it houses, if
## any); until then they wait for it. A trade no building houses (the
## carpenter) works from the start. Buildings are unlocked with experience
## and then built as Production "build" jobs (materials from the stockpile,
## time on the world tick); each level costs and takes as much again as the
## first times the level. A workshop works only while its building stands
## (Production.workshop_open), and each level past the first makes it
## faster (Production.workshop_level). The town chooses what to build by
## itself (tick, from World's world tick). A building the map already has,
## linked to the town, stands at level 1 if the town has no record of it
## (seed_from, at boot and after a builder change).
##
## Raids (step 6, decision 295): a raiding group that reaches the town's
## stockpile ground, travelled there by maps on the world tick or walked
## there in a played zone, alike, calls raid_arrives. The town's defence
## (its walls by level, its residents in town) fights it; what gets past
## takes food and people only (rules' "raids" takes, never gold, materials,
## experience or buildings), may damage a building (repaired by a
## carpenter's "repair:<kind>" job, first of all) and carries residents off
## as captives, kept here (captives) until rescued (note_rescue). The
## report goes back to the caller and out on raided. threat is what maps'
## camps say of a town; Holdings' safety until they do.

## Building id ("forge") -> state: planned (unlocked, not yet built),
## building (being built or raised a level), standing, damaged.
const PLANNED := "planned"
const BUILDING := "building"
const STANDING := "standing"
const DAMAGED := "damaged"
const LOG_SIZE := 50
## A repair job's building id: REPAIR + the kind.
const REPAIR := "repair:"

## A raid reached [param town]: raid_arrives' report.
signal raided(town: String, report: Dictionary)
## A building of [param town]'s changed state or level (unlocked, built,
## raised, damaged, repaired): the views redraw it (buildings_of).
signal building_changed(town: String, kind: String)

var rules := {}
var production: Production
## () -> int: the World's steps.
var clock := Callable()
## (town) -> float 0..1: how threatened [param town] is (maps' camps set
## it); by default from Holdings' safety (rules' raids threat_default).
var threat := Callable()
## Companions as captives (decision 314; Main sets these): (town) -> bool,
## whether [param town]'s zone is in play (its raiders are real there and
## take a companion by beating her down, not here); (player_id, group) ->
## bool, Main.companion_taken; (player_id, town) -> bool,
## Main.companion_freed; (player_id) -> {name, trade}, her record's.
var in_play := Callable()
var companion_taken := Callable()
var companion_freed := Callable()
var companion_of := Callable()

## Town -> {xp, spent, residents: Array[String] (worker ids), buildings:
## {kind: {kind, level, state, since, job}}, objectives (done, by id),
## captives: Array[{id, name, trade, origin, purse, taken_at, by,
## held_by}], log: Array[{step, what}]}.
var _towns: Dictionary[String, Dictionary] = {}


func _init(saved := {}, with_production: Production = null, with_rules := {}, with_clock := Callable()) -> void:
	production = with_production if with_production != null else Production.new()
	rules = with_rules if not with_rules.is_empty() else production.rules
	clock = with_clock if with_clock.is_valid() else production.clock
	production.workshop_open = allows
	production.workshop_level = level_for
	production.on_built = _built
	from_dict(saved)


func now() -> int:
	return int(clock.call()) if clock.is_valid() else 0


# --- Reading -------------------------------------------------------------------------

## Experience [param town] has to spend.
func xp(town: String) -> int:
	var record: Dictionary = _towns.get(town, {})
	return int(record.get("xp", 0)) - int(record.get("spent", 0))


## Experience [param town] has earned, all told.
func xp_earned(town: String) -> int:
	return int(_towns.get(town, {}).get("xp", 0))


func residents(town: String) -> Array[String]:
	var out: Array[String] = []
	out.assign(_towns.get(town, {}).get("residents", []))
	return out


## [param town]'s building [param kind]: {kind, level, state, since, job};
## {} if it has none.
func building(town: String, kind: String) -> Dictionary:
	return _towns.get(town, {}).get("buildings", {}).get(kind, {}).duplicate(true)


## Every building of [param town]: kind -> {state, level}, for the views.
func buildings_of(town: String) -> Dictionary:
	var out := {}
	var houses: Dictionary = _towns.get(town, {}).get("buildings", {})
	for kind: String in houses:
		out[kind] = {"state": houses[kind]["state"], "level": houses[kind]["level"]}
	return out


## How many times worker [param worker_id] has been carried off by
## raiders, from any town (rescued or not): for residents' voices.
func taken_before(worker_id: String) -> int:
	var count := 0
	for town: String in _towns:
		count += int(_towns[town].get("taken", {}).get(worker_id, 0))
	return count


## How many residents [param town] has room for: rules' residents base,
## and per_inn more for each level of a standing inn.
func room(town: String) -> int:
	var per: Dictionary = rules.get("residents", {})
	var inn := building(town, "inn")
	var inn_levels := int(inn.get("level", 0)) if inn.get("state") in [STANDING, BUILDING] else 0
	return int(per.get("base", 3)) + int(per.get("per_inn", 3)) * inn_levels


## The town's log, oldest first: [{step, what}].
func log_of(town: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_towns.get(town, {}).get("log", []))
	return out


## The building kind that houses [param trade] ("" if none: it works anywhere).
func kind_for(trade: String) -> String:
	var kinds: Dictionary = rules.get("buildings", {})
	var names: Array = kinds.keys()
	names.sort()
	for kind: String in names:
		if str(kinds[kind].get("trade", "")) == trade:
			return kind
	return ""


## Production.workshop_open: whether [param shop] may work: its trade needs
## no building, or the town's stands (and has been built at least once:
## raising a level doesn't stop the work).
func allows(shop: Dictionary) -> bool:
	var kind := kind_for(str(shop.get("trade", "")))
	if kind.is_empty():
		return true
	var house := building(str(shop.get("town", "")), kind)
	return int(house.get("level", 0)) >= 1 and house.get("state") in [STANDING, BUILDING]


## Production.workshop_level: the level of [param shop]'s building (1 if none).
func level_for(shop: Dictionary) -> int:
	var kind := kind_for(str(shop.get("trade", "")))
	return maxi(int(building(str(shop.get("town", "")), kind).get("level", 1)), 1) if not kind.is_empty() else 1


# --- The hooks -----------------------------------------------------------------------

## [param town] gains [param amount] experience for [param reason]. Its
## experience to spend after.
func add_xp(town: String, amount: int, reason: String) -> int:
	if amount <= 0:
		return xp(town)
	var record := _town(town)
	record["xp"] = int(record["xp"]) + amount
	_note(town, "+%d experience: %s" % [amount, reason])
	return xp(town)


## [param name] ([param who_id]), rescued, has reached [param town]: a
## resident, of [param trade], working if the town has the building for it,
## waiting for it if not. Experience for the rescue. False if they are a
## resident already.
func note_rescue(town: String, who_id: String, name: String, trade: String, origin := "") -> bool:
	var record := _town(town)
	if who_id in record["residents"]:
		return false
	var held: Array = record["captives"].filter(func(each: Dictionary) -> bool: return each["id"] == who_id)
	if not held.is_empty() and who_id.begins_with("companion:"):
		# A companion (decision 314): Main frees her into this town, a
		# resident working her trade till her player comes.
		record["captives"].erase(held[0])
		_note(town, "%s, a companion taken by %s, is rescued and home" % [held[0]["name"], held[0]["by"]])
		add_xp(town, int(rules.get("xp", {}).get("rescue", 10)), "%s rescued" % held[0]["name"])
		if companion_freed.is_valid():
			companion_freed.call(who_id.trim_prefix("companion:"), town)
		return true
	if not held.is_empty() and not production.worker(who_id).is_empty():
		# Taken in a raid: back as themselves, their work where it was.
		record["captives"].erase(held[0])
		record["residents"].append(who_id)
		production.set_away(who_id, false)
		_note(town, "%s the %s, taken by %s, is rescued and home" % [held[0]["name"], str(held[0]["trade"]).replace("_", " "), held[0]["by"]])
		add_xp(town, int(rules.get("xp", {}).get("rescue", 10)), "%s rescued" % held[0]["name"])
		_seat(town)
		return true
	if not production.add_worker(who_id, name, [trade], town, "rescued:%s" % (origin if not origin.is_empty() else who_id)):
		return false
	record["residents"].append(who_id)
	_note(town, "%s the %s, rescued, is a resident" % [name, trade.replace("_", " ")])
	if record["residents"].size() > room(town):
		_note(town, "%d residents, room for %d: the town is crowded" % [record["residents"].size(), room(town)])
	add_xp(town, int(rules.get("xp", {}).get("rescue", 10)), "%s rescued" % name)
	_seat(town)
	return true


## A story objective [param objective_id] was completed for [param town]
## ("the smith brought home"): the big reward, [param worth] times rules'
## objective, once per objective. Its experience to spend after.
func note_objective(town: String, objective_id: String, worth := 1) -> int:
	var record := _town(town)
	if objective_id in record["objectives"]:
		return xp(town)
	record["objectives"].append(objective_id)
	return add_xp(town, int(rules.get("xp", {}).get("objective", 50)) * maxi(worth, 1), "objective %s" % objective_id)


## Companion [param companion_name] is in [param town], away from its
## player: a resident working [param trade] (from its record's traits,
## levels/companion_traits.json), seated as a rescued person is. Back to work where it
## left off if it was here before. [param player_id], her player's, is
## her origin ("companion:<player id>"), by which a raid takes her.
func note_companion_in(town: String, companion_name: String, trade: String, player_id := "") -> void:
	var who := "companion:%s" % companion_name
	var record := _town(town)
	if production.worker(who).is_empty():
		production.add_worker(who, companion_name, [trade], town, who)
	if not player_id.is_empty():
		production.set_origin(who, "companion:%s" % player_id)
	production.set_away(who, false)
	if who not in record["residents"]:
		record["residents"].append(who)
		_note(town, "%s, a companion, stays and works as a %s" % [companion_name, trade])
	_seat(town)


## Companion [param companion_name] has left [param town] with its player:
## its job waits (its materials kept) until it comes back.
func note_companion_out(town: String, companion_name: String) -> void:
	var who := "companion:%s" % companion_name
	if production.worker(who).is_empty():
		return
	production.set_away(who, true)
	_note(town, "%s goes adventuring; its work waits" % companion_name)


# --- Choosing upgrades ---------------------------------------------------------------

## The world tick (after Production's): each town with experience to spend
## and nothing being built chooses its next building by itself, from its
## state: walls when threatened, the building a resident waits for, an inn
## when crowded, else the lowest building that houses a trade. Nothing if
## it can't afford it.
func tick() -> void:
	var towns: Array[String] = []
	towns.assign(_towns.keys())
	towns.sort()
	for town in towns:
		_spread(town)
		_appoint(town)
		if production.building_in(town):
			continue
		if _repair(town):
			continue
		var kind := choose(town)
		if not kind.is_empty():
			unlock(town, kind)


## Each place the fallen come back at that is [param town]'s building
## (rules' return.places, not "outside": the temple) given its official
## (its trade: the priest) once it stands, if the town has none: a resident
## named from the place's names by the town, seated there (decision 396).
func _appoint(town: String) -> void:
	var places: Dictionary = rules.get("return", {}).get("places", {})
	var record := _town(town)
	for kind: String in places:
		var rule: Dictionary = places[kind]
		var trade := str(rule.get("trade", ""))
		if bool(rule.get("outside", false)) or trade.is_empty() or building(town, kind).get("state") != STANDING:
			continue
		if record["residents"].any(func(who: String) -> bool: return trade in production.worker(who).get("trades", [])):
			continue
		var who := "%s:%s" % [trade, town]
		var names: Array = rule.get("names", [])
		var name := str(names[absi(hash(town)) % names.size()]) if not names.is_empty() else trade.capitalize()
		if not production.add_worker(who, name, [trade], town, "appointed"):
			continue
		record["residents"].append(who)
		_note(town, "%s comes to be the town's %s" % [name, trade.replace("_", " ")])
		_seat(town)


## The building [param town] wants next ("" for none it can afford).
func choose(town: String) -> String:
	var kinds: Dictionary = rules.get("buildings", {})
	var wants: Array[String] = []
	if kinds.has("walls") and (production.tier(town) == Production.DEFEND
			or threat_of(town) >= float(rules.get("raids", {}).get("walls_from", 1.0))):
		wants.append("walls")
	for who in residents(town):
		var worker := production.worker(who)
		if not worker.is_empty() and not _seated(who) and not worker["away"]:
			var kind := kind_for(worker["trades"][0])
			if not kind.is_empty() and kind not in wants:
				wants.append(kind)
	if residents(town).size() >= room(town) and kinds.has("inn"):
		wants.append("inn")
	var housing: Array = kinds.keys().filter(func(kind: String) -> bool:
		return not str(kinds[kind].get("trade", "")).is_empty() and int(building(town, kind).get("level", 0)) >= 1)
	housing.sort_custom(func(a: String, b: String) -> bool:
		var la := int(building(town, a)["level"])
		var lb := int(building(town, b)["level"])
		return la < lb or la == lb and a < b)
	wants.append_array(housing)
	for kind in wants:
		var level := int(building(town, kind).get("level", 0)) + 1
		var top := int(kinds[kind].get("max_level", 3))
		if level <= top and xp(town) >= int(kinds[kind].get("xp", 0)) * level:
			return kind
	return ""


# --- Building ------------------------------------------------------------------------

## [param town] spends experience on [param kind]'s next level: a build job
## for it (its cost and steps times the level). False, and nothing spent,
## for no such kind, not enough experience, or one already being built.
func unlock(town: String, kind: String) -> bool:
	var kinds: Dictionary = rules.get("buildings", {})
	if not kinds.has(kind):
		return false
	var spec: Dictionary = kinds[kind]
	var house := building(town, kind)
	if house.get("state") in [PLANNED, BUILDING] and int(house.get("job", 0)) != 0:
		return false
	var level := int(house.get("level", 0)) + 1
	var price := int(spec.get("xp", 0)) * level
	if xp(town) < price:
		return false
	var record := _town(town)
	record["spent"] = int(record["spent"]) + price
	var cost := {}
	for what: String in spec.get("cost", {}):
		cost[what] = int(spec["cost"][what]) * level
	var entry: Dictionary = record["buildings"].get(kind, {"kind": kind, "level": 0, "state": PLANNED, "since": now(), "job": 0})
	entry["state"] = BUILDING if int(entry["level"]) >= 1 else PLANNED
	record["buildings"][kind] = entry
	_note(town, "%d experience spent on a %s, level %d" % [price, kind, level])
	building_changed.emit(town, kind)
	var by := str(spec.get("built_by", ""))
	if by.is_empty():
		_built(town, kind)
	else:
		entry["job"] = production.order_build(town, kind, by, cost, int(spec.get("steps", 1)) * level)
	return true


## The buildings the map already has (decision 306): each of
## [param world_map]'s buildings linked to a town ("use" one of rules'
## buildings, "town" a stockpile place: Level._link) stands in that town at
## level 1 if the town has no record of that kind yet; one it has a record
## of is left as it is (never lowered, nor its damage undone). Main calls it
## at boot and after a builder change. The "town/kind" ids seeded, sorted.
func seed_from(world_map: WorldMap) -> Array[String]:
	var out: Array[String] = []
	var kinds: Dictionary = rules.get("buildings", {})
	var names: Array = world_map.areas.keys()
	names.sort()
	for area_name: String in names:
		var places: Dictionary = world_map.areas[area_name].get("places", {})
		var keys: Array = places.keys()
		keys.sort()
		for key: String in keys:
			if places[key].get("kind") == "stockpile" and places[key].get("holder") == Stockpile.TOWN:
				_found("%s/%s" % [area_name, key])
	for area_name: String in world_map.areas:
		for house: Dictionary in world_map.areas[area_name].get("buildings", []):
			var kind := str(house.get("use", ""))
			if kind.is_empty() or str(house.get("town", "")).is_empty() or not kinds.has(kind):
				continue
			var town := "%s/%s" % [area_name, house["town"]]
			var record := _town(town)
			if record["buildings"].has(kind):
				continue
			record["buildings"][kind] = {"kind": kind, "level": 1, "state": STANDING, "since": now(), "job": 0}
			_note(town, "the %s stands, level 1, as the map has it" % kind)
			building_changed.emit(town, kind)
			_seat(town)
			out.append("%s/%s" % [town, kind])
	out.sort()
	return out


## A town is founded once, the first time its store is seen (a save from
## before decision 353 too): "founded" on its record. Its treasury starts
## empty; rules' start_gold is its people's, spread evenly over its
## residents' purses (Jeff, 353 amended), the first when there are any
## ("to_spread" waits till then). Residents who come later get none.
func _found(town: String) -> void:
	var record := _town(town)
	if record["founded"]:
		return
	record["founded"] = true
	record["to_spread"] = maxi(int(rules.get("start_gold", 0)), 0)
	_note(town, "founded")
	_spread(town)


## [param town]'s founding gold, if it waits and the town has residents of
## its own (not companions): split evenly, the first by id a coin more
## for what doesn't divide.
func _spread(town: String) -> void:
	var record := _town(town)
	var gold := int(record["to_spread"])
	if gold <= 0:
		return
	var folk: Array[String] = []
	for who: String in record["residents"]:
		if not who.begins_with("companion:") and not str(production.worker(who).get("origin", "")).begins_with("companion:"):
			folk.append(who)
	if folk.is_empty():
		return
	folk.sort()
	record["to_spread"] = 0
	for i in folk.size():
		var share := gold / folk.size() + (1 if i < gold % folk.size() else 0)
		production.pay(folk[i], share, "the town's founding gold")
	_note(town, "its founding gold, %d, spread over %d residents" % [gold, folk.size()])


## Production.on_built: [param kind] in [param town] is up a level and
## standing; its trade's workshop opens and waiting residents are seated.
func _built(town: String, kind: String) -> void:
	var record := _town(town)
	if kind.begins_with(REPAIR):
		var repaired: Dictionary = record["buildings"].get(kind.trim_prefix(REPAIR), {})
		if not repaired.is_empty():
			repaired["state"] = STANDING
			repaired["since"] = now()
			repaired["job"] = 0
			_note(town, "the %s is repaired, level %d" % [repaired["kind"], repaired["level"]])
			building_changed.emit(town, str(repaired["kind"]))
			_seat(town)
		return
	var entry: Dictionary = record["buildings"].get(kind, {"kind": kind, "level": 0, "job": 0})
	entry["level"] = int(entry["level"]) + 1
	entry["state"] = STANDING
	entry["since"] = now()
	entry["job"] = 0
	record["buildings"][kind] = entry
	_note(town, "the %s stands, level %d" % [kind, entry["level"]])
	building_changed.emit(town, kind)
	_seat(town)


## Seats [param town]'s residents who have no workshop at one of their
## trade: a free one if there is, a new one if their trade's building
## stands (or needs none); otherwise they wait, and say so once.
func _seat(town: String) -> void:
	var record := _town(town)
	for who: String in record["residents"]:
		var worker := production.worker(who)
		if worker.is_empty() or _seated(who):
			continue
		var trade: String = worker["trades"][0]
		var kind := kind_for(trade)
		if not kind.is_empty() and not allows({"trade": trade, "town": town}):
			var waiting := "%s the %s waits for a %s" % [worker["name"], trade.replace("_", " "), kind]
			if not log_of(town).any(func(line: Dictionary) -> bool: return line["what"] == waiting):
				_note(town, waiting)
			continue
		var shop_id := "%s:%s" % [town, kind if not kind.is_empty() else trade]
		if production.workshop(shop_id).is_empty():
			production.add_workshop(shop_id, trade, town)
		if production.workshop(shop_id)["worker"] == "" and production.assign(shop_id, who):
			_note(town, "%s the %s works at %s" % [worker["name"], trade.replace("_", " "), shop_id])


## Orders a repair of [param town]'s first damaged building with none
## ordered (rules' raids repair share of its cost and time at its level, no
## experience): true if it did.
func _repair(town: String) -> bool:
	var kinds: Dictionary = rules.get("buildings", {})
	var share := float(rules.get("raids", {}).get("repair", {}).get("share", 0.5))
	var record := _town(town)
	var names: Array = record["buildings"].keys()
	names.sort()
	for kind: String in names:
		var entry: Dictionary = record["buildings"][kind]
		if entry["state"] != DAMAGED or int(entry["job"]) != 0 or not kinds.has(kind):
			continue
		var spec: Dictionary = kinds[kind]
		var level := maxi(int(entry["level"]), 1)
		var cost := {}
		for what: String in spec.get("cost", {}):
			var amount := ceili(int(spec["cost"][what]) * level * share)
			if amount > 0:
				cost[what] = amount
		var by := str(spec.get("built_by", ""))
		if by.is_empty():
			_built(town, REPAIR + kind)
			return true
		entry["job"] = production.order_build(town, REPAIR + kind, by, cost, maxi(ceili(int(spec.get("steps", 1)) * level * share), 1))
		_note(town, "the %s is to be repaired" % kind)
		return true
	return false


# --- Raids ---------------------------------------------------------------------------

## How threatened [param town] is, 0..1: threat's, else from its safety
## (rules' raids threat_default, by Production's safety).
func threat_of(town: String) -> float:
	if threat.is_valid():
		return clampf(float(threat.call(town)), 0.0, 1.0)
	var safety := str(production.signals_of(town, production.catalog.call())["safety"])
	return clampf(float(rules.get("raids", {}).get("threat_default", {}).get(safety, 0.0)), 0.0, 1.0)


## [param town]'s defence against a raid now: its walls (standing, by
## level) and its residents in town, at rules' raids defence.
func defence(town: String) -> float:
	var per: Dictionary = rules.get("raids", {}).get("defence", {})
	var walls := building(town, "walls")
	var levels := int(walls.get("level", 0)) if walls.get("state") in [STANDING, BUILDING] else 0
	var present := residents(town).filter(func(who: String) -> bool:
		return not production.worker(who).is_empty() and not production.worker(who)["away"]).size()
	return levels * float(per.get("per_wall_level", 0)) + present * float(per.get("per_resident", 0))


## The people taken from [param town] and not yet rescued, oldest first:
## [{id, name, trade, origin, purse, taken_at, by, held_by}].
func captives(town: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(_towns.get(town, {}).get("captives", []).duplicate(true))
	return out


## Captive [param who_id] is held by [param holder] now (a camp's place
## id once the group is home, another group...): maps says so. False for
## no such captive.
func captive_held(who_id: String, holder: String) -> bool:
	for town: String in _towns:
		for each: Dictionary in _towns[town]["captives"]:
			if each["id"] == who_id:
				each["held_by"] = holder
				return true
	return false


## Raid group [param group_id] of [param faction] is home with
## [param captives] (the ids it carries, as Raids and raid_arrives name
## them) from its raid on [param town], held by [param holder] (its camp's
## place): each is a captive held there. A companion it took in play
## ("companion:<player id>", beaten down: decision 314) has no entry yet;
## she gets one in [param town], her name and trade from companion_of.
## The ids now held, in order.
func carried_home(town: String, group_id: String, faction: String, captives: Array, holder: String) -> Array[String]:
	var out: Array[String] = []
	for each: Variant in captives:
		var who := str(each)
		if captive_held(who, holder):
			out.append(who)
			continue
		if not who.begins_with("companion:"):
			continue
		var her: Dictionary = companion_of.call(who.trim_prefix("companion:")) if companion_of.is_valid() else {}
		var her_name := str(her.get("name", who))
		_town(town)["captives"].append({"id": who, "name": her_name, "trade": str(her.get("trade", "")), "origin": who,
			"purse": 0, "taken_at": now(), "by": faction, "held_by": holder})
		_note(town, "%s, a companion, is held by %s (%s)" % [her_name, faction, group_id])
		out.append(who)
	return out


## A raiding [param group] ({id, faction, strength, from}: its strength
## after anything done to it on the way) has reached [param town]'s ground,
## travelled there or walked there in play, alike. Its strength less the
## town's defence is what gets past (margin); none, and it is fought off.
## Else it takes rules' raids takes in order, each scaled by margin /
## strength (only food: never gold, materials, experience or buildings),
## damages one building past damage.margin and carries off up to
## captives.count residents (the newest first; a companion by her player's
## id, "companion:<player id>", Main told: companion_taken) past
## captives.margin, only when the town is not in play (in play the
## raiders' blows take people: resident_taken). The report, also emitted on raided: {town, group,
## faction, repelled, margin, took: {resource: count, items: [uids]},
## damaged (a kind or ""), captives: [{id, name, trade}]}: what the group
## carries off is maps' to move home with it.
func raid_arrives(town: String, group: Dictionary) -> Dictionary:
	var raids: Dictionary = rules.get("raids", {})
	var faction := str(group.get("faction", raids.get("raiders", "")))
	var group_id := str(group.get("id", ""))
	var strength := maxf(float(group.get("strength", 0.0)), 0.0)
	var margin := strength - defence(town)
	var report := {"town": town, "group": group_id, "faction": faction, "repelled": margin <= 0.0,
		"margin": margin, "took": {"items": []}, "damaged": "", "captives": []}
	var by := "raid:%s" % faction
	if margin <= 0.0:
		_note(town, "a raid by %s (%.1f) is fought off (defence %.1f)" % [faction, strength, defence(town)])
		raided.emit(town, report)
		return report
	var scale := clampf(margin / strength, 0.0, 1.0)
	var stock := production.stockpile
	var book := production.book()
	for take: Variant in raids.get("takes", []):
		if not take is Dictionary:
			continue
		var what := str(take.get("what", ""))
		if what in Stockpile.RESOURCES:
			var amount := floori(stock.count(town, what) * float(take.get("share", 0.0)) * scale)
			if amount > 0 and stock.take(town, what, amount, by):
				report["took"][what] = int(report["took"].get(what, 0)) + amount
		elif take.has("tag"):
			var count := roundi(int(take.get("count", 0)) * scale)
			var tag := str(take["tag"])
			var uids := stock.shop(town)
			uids.append_array(stock.items(town))
			for uid in uids:
				if count <= 0:
					break
				if tag not in production.tags_of(book.id_of(uid)):
					continue
				var taken := stock.take_from_shop(town, uid, by) if uid in stock.shop(town) else stock.take_item(town, uid, by)
				if taken:
					book.place(uid, "raid:%s" % group_id)
					book.note(uid, "taken", "by %s (%s) from %s" % [faction, group_id, town])
					report["took"]["items"].append(uid)
					count -= 1
	var damage: Dictionary = raids.get("damage", {})
	if margin >= float(damage.get("margin", INF)):
		var record := _town(town)
		for kind: Variant in damage.get("prefer", []):
			var entry: Dictionary = record["buildings"].get(str(kind), {})
			if entry.get("state") == STANDING:
				entry["state"] = DAMAGED
				entry["since"] = now()
				report["damaged"] = str(kind)
				building_changed.emit(town, str(kind))
				break
	var taking: Dictionary = raids.get("captives", {})
	# In play the raiders' blows decide who is taken (resident_taken, Main's
	# companion_taken): nobody is carried off by the numbers as well.
	if margin >= float(taking.get("margin", INF)) and not (in_play.is_valid() and in_play.call(town)):
		var record := _town(town)
		var people: Array = record["residents"].duplicate()
		people.reverse()
		for who: String in people:
			if report["captives"].size() >= int(taking.get("count", 0)):
				break
			var worker := production.worker(who)
			if worker.is_empty() or worker["away"]:
				continue
			# A companion only by her player's id (decision 331).
			if who.begins_with("companion:") and not _take_companion(town, who, faction, group_id):
				continue
			if not who.begins_with("companion:"):
				_take(town, who, faction, group_id)
			var taken: Dictionary = record["captives"].back()
			report["captives"].append({"id": taken["id"], "name": taken["name"], "trade": taken["trade"]})
	_note(town, "a raid by %s (%.1f against %.1f) took %s%s%s" % [faction, strength, strength - margin,
		report["took"], ", damaged the %s" % report["damaged"] if report["damaged"] != "" else "",
		", carried off %s" % ", ".join(report["captives"].map(func(each: Dictionary) -> String: return each["name"]))
			if not report["captives"].is_empty() else ""])
	raided.emit(town, report)
	return report


## Resident [param who] of [param town] beaten down by raiders in play
## (World.entity_taken on a Resident body, decision 331): taken as
## raid_arrives takes one, a captive of [param faction] (rules' raiders if
## none) held by group [param by]. False if no such resident (or a
## companion: her own body goes through Main.companion_taken).
func resident_taken(town: String, who: String, by: String, faction := "") -> bool:
	if who.begins_with("companion:") or who not in _towns.get(town, {}).get("residents", []) or production.worker(who).is_empty():
		return false
	_take(town, who, faction if not faction.is_empty() else str(rules.get("raids", {}).get("raiders", "raiders")), by)
	_note(town, "%s is beaten down and carried off by %s" % [production.worker(who)["name"], by])
	return true


## [param who] of [param town] a captive of [param faction], held by group
## [param by]: no resident now, the work waits.
func _take(town: String, who: String, faction: String, by: String) -> void:
	var record := _town(town)
	var worker := production.worker(who)
	record["residents"].erase(who)
	production.set_away(who, true)
	record["captives"].append({"id": who, "name": worker["name"], "trade": worker["trades"][0],
		"origin": worker["origin"], "purse": worker["purse"], "taken_at": now(), "by": faction, "held_by": by})
	record["taken"][who] = int(record["taken"].get(who, 0)) + 1


## Companion resident [param who] taken by her player's id, Main told;
## false if her player isn't known.
func _take_companion(town: String, who: String, faction: String, by: String) -> bool:
	var worker := production.worker(who)
	var origin := str(worker["origin"])
	if origin == who or not origin.begins_with("companion:"):
		return false
	var record := _town(town)
	record["residents"].erase(who)
	production.set_away(who, true)
	record["captives"].append({"id": origin, "name": worker["name"], "trade": worker["trades"][0],
		"origin": origin, "purse": 0, "taken_at": now(), "by": faction, "held_by": by})
	record["taken"][who] = int(record["taken"].get(who, 0)) + 1
	if companion_taken.is_valid():
		companion_taken.call(origin.trim_prefix("companion:"), by)
	return true


func _seated(who: String) -> bool:
	return production.workshop_of(who) != ""


func _note(town: String, what: String) -> void:
	var record := _town(town)
	record["log"].append({"step": now(), "what": what})
	if record["log"].size() > LOG_SIZE:
		record["log"].pop_front()
	print("[towns] %s: %s, step %d" % [town, what, now()])


func _town(town: String) -> Dictionary:
	if not _towns.has(town):
		_towns[town] = {"xp": 0, "spent": 0, "residents": [], "buildings": {}, "objectives": [], "captives": [], "taken": {}, "log": [], "founded": false, "to_spread": 0}
	return _towns[town]


# --- Saving --------------------------------------------------------------------------

## For the snapshot: town -> {xp, spent, residents, buildings, objectives,
## captives, taken (worker id -> times carried off), log, founded,
## to_spread}.
func to_dict() -> Dictionary:
	return _towns.duplicate(true)


## to_dict's [param saved] over what is here (after Production). Anything
## that makes no sense is left out with a word.
func from_dict(saved: Dictionary) -> void:
	for town: Variant in saved:
		var entry: Variant = saved[town]
		if not entry is Dictionary:
			print("[towns] the snapshot's town %s makes no sense; left out" % [town])
			continue
		var record := _town(str(town))
		record["xp"] = maxi(int(entry.get("xp", 0)), 0)
		record["founded"] = bool(entry.get("founded", false))
		record["to_spread"] = maxi(int(entry.get("to_spread", 0)), 0)
		record["spent"] = clampi(int(entry.get("spent", 0)), 0, record["xp"])
		for who: Variant in entry.get("residents", []):
			if not production.worker(str(who)).is_empty():
				record["residents"].append(str(who))
		var buildings: Variant = entry.get("buildings", {})
		if buildings is Dictionary:
			for kind: String in buildings:
				var house: Variant = buildings[kind]
				if house is Dictionary and str(house.get("state", "")) in [PLANNED, BUILDING, STANDING, DAMAGED]:
					record["buildings"][kind] = {"kind": kind, "level": maxi(int(house.get("level", 0)), 0),
						"state": str(house["state"]), "since": int(house.get("since", 0)), "job": int(house.get("job", 0))}
		for done: Variant in entry.get("objectives", []):
			record["objectives"].append(str(done))
		var taken: Variant = entry.get("taken", {})
		if taken is Dictionary:
			for who: Variant in taken:
				record["taken"][str(who)] = maxi(int(taken[who]), 0)
		for each: Variant in entry.get("captives", []):
			# A companion captive is her player's (no worker by that id).
			if each is Dictionary and (not production.worker(str(each.get("id", ""))).is_empty() or str(each.get("id", "")).begins_with("companion:")):
				record["captives"].append({"id": str(each["id"]), "name": str(each.get("name", "")),
					"trade": str(each.get("trade", "")), "origin": str(each.get("origin", "")),
					"purse": int(each.get("purse", 0)), "taken_at": int(each.get("taken_at", 0)),
					"by": str(each.get("by", "")), "held_by": str(each.get("held_by", ""))})
		for line: Variant in entry.get("log", []):
			if line is Dictionary:
				record["log"].append({"step": int(line.get("step", 0)), "what": str(line.get("what", ""))})
