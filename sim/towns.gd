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
## itself (tick, from World's world tick). Damage and repair (step 6) act
## on the same records.

## Building id ("forge") -> state: planned (unlocked, not yet built),
## building (being built or raised a level), standing, damaged.
const PLANNED := "planned"
const BUILDING := "building"
const STANDING := "standing"
const DAMAGED := "damaged"
const LOG_SIZE := 50

var rules := {}
var production: Production
## () -> int: the World's steps.
var clock := Callable()

## Town -> {xp, spent, residents: Array[String] (worker ids), buildings:
## {kind: {kind, level, state, since, job}}, objectives (done, by id),
## log: Array[{step, what}]}.
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
	if not production.add_worker(who_id, name, [trade], town, "rescued:%s" % (origin if not origin.is_empty() else who_id)):
		return false
	record["residents"].append(who_id)
	_note(town, "%s the %s, rescued, is a resident" % [name, trade])
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
## player: a resident working [param trade] (its card's; levels/companions.json
## until cards come), seated as a rescued person is. Back to work where it
## left off if it was here before.
func note_companion_in(town: String, companion_name: String, trade: String) -> void:
	var who := "companion:%s" % companion_name
	var record := _town(town)
	if production.worker(who).is_empty():
		production.add_worker(who, companion_name, [trade], town, who)
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
		if production.building_in(town):
			continue
		var kind := choose(town)
		if not kind.is_empty():
			unlock(town, kind)


## The building [param town] wants next ("" for none it can afford).
func choose(town: String) -> String:
	var kinds: Dictionary = rules.get("buildings", {})
	var wants: Array[String] = []
	if production.tier(town) == Production.DEFEND and kinds.has("walls"):
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
	var by := str(spec.get("built_by", ""))
	if by.is_empty():
		_built(town, kind)
	else:
		entry["job"] = production.order_build(town, kind, by, cost, int(spec.get("steps", 1)) * level)
	return true


## Production.on_built: [param kind] in [param town] is up a level and
## standing; its trade's workshop opens and waiting residents are seated.
func _built(town: String, kind: String) -> void:
	var record := _town(town)
	var entry: Dictionary = record["buildings"].get(kind, {"kind": kind, "level": 0, "job": 0})
	entry["level"] = int(entry["level"]) + 1
	entry["state"] = STANDING
	entry["since"] = now()
	entry["job"] = 0
	record["buildings"][kind] = entry
	_note(town, "the %s stands, level %d" % [kind, entry["level"]])
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
			var waiting := "%s the %s waits for a %s" % [worker["name"], trade, kind]
			if not log_of(town).any(func(line: Dictionary) -> bool: return line["what"] == waiting):
				_note(town, waiting)
			continue
		var shop_id := "%s:%s" % [town, kind if not kind.is_empty() else trade]
		if production.workshop(shop_id).is_empty():
			production.add_workshop(shop_id, trade, town)
		if production.workshop(shop_id)["worker"] == "" and production.assign(shop_id, who):
			_note(town, "%s the %s works at %s" % [worker["name"], trade, shop_id])


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
		_towns[town] = {"xp": 0, "spent": 0, "residents": [], "buildings": {}, "objectives": [], "log": []}
	return _towns[town]


# --- Saving --------------------------------------------------------------------------

## For the snapshot: town -> {xp, spent, residents, buildings, objectives, log}.
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
		for line: Variant in entry.get("log", []):
			if line is Dictionary:
				record["log"].append({"step": int(line.get("step", 0)), "what": str(line.get("what", ""))})
