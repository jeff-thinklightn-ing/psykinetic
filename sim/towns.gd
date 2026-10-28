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
## building (being built or raised a level), standing, damaged; out of
## use for want of keep (disrepair, losing a level a season) and at last a
## ruin, kept a season and then gone (649).
const PLANNED := "planned"
const BUILDING := "building"
const STANDING := "standing"
const DAMAGED := "damaged"
const DISREPAIR := "disrepair"
const RUIN := "ruin"
const LOG_SIZE := 50
## A repair job's building id: REPAIR + the kind.
const REPAIR := "repair:"
## The build progress at which the views are told again (decision 566: a
## building drawn in stages; buildings' composer reads them): the frame, the
## walls (BUILD_STAGES[1]: from it they stand and block, walls_up, the
## coordinator's ruling), the walls' steps, the rafters, the covering.
const BUILD_STAGES: Array[float] = [0.1, 0.35, 0.45, 0.55, 0.65, 0.75, 0.9]
## A roof's build job's id prefix: "roof:<index>" (decision 426).
const ROOF := "roof:"

## A raid reached [param town]: raid_arrives' report.
signal raided(town: String, report: Dictionary)
## [param who_id] came home to [param town] rescued ([param by]: the
## faction that had taken them, "" if none did): for npc's cards.
signal rescued(town: String, who_id: String, by: String)
## Resident [param who_id] ([param name]) of [param town] died by npc's word
## (Towns.died, decision 501): for their card and kin.
signal resident_died(town: String, who_id: String, name: String, why: String)
## A building of [param town]'s changed state or level (unlocked, built,
## raised, damaged, repaired): the views redraw it (buildings_of).
signal building_changed(town: String, kind: String)
## [param town]'s sought entry [param id] was made, placed, freed, lost or
## came home (decision 613): npc's bodies and maps' holders read sought().
signal sought_changed(town: String, id: String)
## Resident [param id] of [param town] wandered off, low too long (613
## amended): sought again at their story's place; npc's officials say so.
signal wandered(town: String, id: String)
## [param town] rose a stage toward a city (591): Towns.stage.
signal stage_changed(town: String)
## [param town]'s ruined [param kind] is gone (649): its record dropped, its
## [param cells] in [param zone] (placed's) for the forest to take back.
signal ruined(town: String, kind: String, zone: String, cells: Array[Vector2i])
## [param town] builds its gone [param kind] again (649 amended): its
## [param cells] in [param zone] (placed's) to be cleared and built over.
signal reclaimed(town: String, kind: String, zone: String, cells: Array[Vector2i])

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
## Wells and roofs (decision 426; Main sets them, tests stand in):
## (town) -> int, the wells in its area; (town, from, to) -> float, the
## rain that fell on it between two steps in days of full rain
## (Weather.rain_between); (town) -> [{index, cells}], its level's damaged
## roofs; (town, index) -> bool, mends one (World.repair_roof).
## Rescues (decision 428; Main sets them): () -> the hostile camps
## ({id, area, cell, faction}: Holdings.camps); (camp id) -> the town its
## freed go home to (the nearest held store by routes).
var camps := Callable()
var home_of := Callable()
## The sought (decision 613; maps sets it from Main): (town, trade, the
## story's variant {place, where, holder, story}, id) -> {place, where}
## for the variant's place key in the levels now, or "" while it isn't
## laid. Unset, a town's newcomers walk in as before.
var place_sought := Callable()
var wells := Callable()
## (town, from, to) -> [{id, strength}]: the storms over the town between
## two steps that count (strength at least its climate's storm_min; Main:
## Weather.storms_between), for its crop (decision 449).
var storms := Callable()
var rain := Callable()
## (town, site id, wanted) -> int: the trees maps' Clearing.fell takes at a
## woodlot's edge nearest the town (591; Main sets it); unset, a cut brings
## its wood as before.
var fell := Callable()
var roofs := Callable()
var mend_roof := Callable()
## (town, herder id, count, food) -> int: the sheep [param town] buys of a
## herder's drove (640; Main: Economy.buy_drove); unset, no drove is sold.
var drove := Callable()
## (town, kind) -> {zone, cells: Array[Vector2i], distance} (649; Main, from
## the world map's building of that use): where it stands and how far from
## its store; {} unknown (as near as can be, nothing to give back).
var placed := Callable()
## A herder's fold changed its count (640): [param place_id]'s sheep, for
## the "folds" message the views draw it by.
signal folds_changed(place_id: String)
## A visitor came to [param town] or left it (711): its Towns.visitors
## entry by [param id], for npc's bodies.
signal visitor_came(town: String, id: String)
signal visitor_left(town: String, id: String)
## (town) -> Array of place names a visitor to it may come from (711; Main,
## from the world plane); "the road" while unset.
var visitor_from := Callable()
## (town, entry) -> String: what a visitor does as they come (711;
## Economy.visitor_arrives, set by Main): words for the log, "" for nothing.
var visitor_arrives := Callable()
## (town, entry, player_id, item) -> {ok, say, gold}: a pedlar's sale's gold
## (711; Economy.visitor_sale, set by Main). No sale while unset.
var visitor_sale := Callable()

## Town -> {xp, spent, residents: Array[String] (worker ids), buildings:
## {kind: {kind, level, state, since, job}}, objectives (done, by id),
## captives: Array[{id, name, trade, origin, purse, taken_at, by,
## held_by}], log: Array[{step, what}]}.
var _towns: Dictionary[String, Dictionary] = {}
## Town id -> {map building code: awake} (set_awake; not saved).
var _awake: Dictionary = {}
## Herder place id -> {since (first seen, for the herder's coming), season
## (the last seen), lambs (the part-lamb), next (the step of his next
## drove), back (the step they are home), unsold (sheep walking home with
## them)} (640). Saved beside the towns (herders_to_dict).
var _herders: Dictionary = {}


func _init(saved := {}, with_production: Production = null, with_rules := {}, with_clock := Callable()) -> void:
	production = with_production if with_production != null else Production.new()
	rules = with_rules if not with_rules.is_empty() else production.rules
	clock = with_clock if with_clock.is_valid() else production.clock
	production.workshop_open = allows
	production.workshop_level = level_for
	production.on_built = _built
	production.town_has = has_for_make
	production.keep_for = upkeep_due
	production.official_paid = official_paid
	production.larder_for = larder_for
	production.work_rate = _work_rate
	production.hunted.connect(_on_hunted)
	production.work_done.connect(_on_work_done)
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


## Every building of [param town]: kind -> {state, level, walls
## (walls_up)}, for the views; "progress" (build_progress) while a job
## builds, raises or repairs it (decision 566).
func buildings_of(town: String) -> Dictionary:
	var out := {}
	var houses: Dictionary = _towns.get(town, {}).get("buildings", {})
	for kind: String in houses:
		out[kind] = {"state": houses[kind]["state"], "level": houses[kind]["level"]}
		var progress := build_progress(town, kind)
		if progress >= 0.0:
			out[kind]["progress"] = progress
		out[kind]["walls"] = walls_up(town, kind)  # Whether its walls block (566; maps' open_walls).
	for kind: Variant in _towns.get(town, {}).get("gone", []):
		out[str(kind)] = {"state": "gone", "level": 0, "walls": false}  # A ruin gone (649): the map's piece no more.
	if out.has("field"):
		out["field"]["crop"] = crop_look(town)  # The field's look (decision 457).
	return out


## How far [param town]'s [param kind] is built (decision 566: visible
## work): its job's worked / needed steps, 0..1, while one builds it (a
## planned one, a raise: "building", a repair: "damaged"); -1 with no job.
func build_progress(town: String, kind: String) -> float:
	var job_id := int(_towns.get(town, {}).get("buildings", {}).get(kind, {}).get("job", 0))
	var job := production.job(job_id) if job_id != 0 else {}
	if job.is_empty():
		return -1.0
	return clampf(float(job.get("worked", 0)) / maxf(float(job.get("needed", 0)), 1.0), 0.0, 1.0)


## Whether [param town]'s [param kind] has walls that block (566, the
## coordinator's ruling: from the walls stage): standing or damaged, or a
## level already up (a raise), or built to BUILD_STAGES[1].
func walls_up(town: String, kind: String) -> bool:
	var house := building(town, kind)
	if house.is_empty():
		return false
	if house["state"] in [STANDING, DAMAGED] or int(house["level"]) >= 1:
		return true
	return build_progress(town, kind) >= BUILD_STAGES[1]


## Each building of [param town] whose build crossed one of BUILD_STAGES since
## the views were last told: told again (building_changed).
func _stages(town: String) -> void:
	var houses: Dictionary = _towns.get(town, {}).get("buildings", {})
	for kind: String in houses:
		var progress := build_progress(town, kind)
		var stage := BUILD_STAGES.filter(func(at: float) -> bool: return progress >= at).size() if progress >= 0.0 else -1
		if stage != int(houses[kind].get("stage", -1)):
			houses[kind]["stage"] = stage
			if progress >= 0.0:
				building_changed.emit(town, kind)


## Whether the people of map building [param code] (its decision 537 code,
## "H3") of [param town] are awake (decision 566: npc's bodies set it, the
## window light reads it). Not saved: the bodies set it again.
func set_awake(town: String, code: String, awake: bool) -> void:
	var told: Dictionary = _awake.get_or_add(town, {})
	if told.get(code) == awake:
		return
	told[code] = awake
	building_changed.emit(town, "")


## [param town]'s map buildings as set_awake left them: code -> bool.
func awake_of(town: String) -> Dictionary:
	return _awake.get(town, {}).duplicate()


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


## Captive [param who_id] let go from every town's captives (672 amended,
## the admin's quest reset): no rescue, no experience, nobody told (the
## caller frees her). False if no town held it.
func drop_captive(who_id: String) -> bool:
	var dropped := false
	for town: String in _towns:
		var held: Array = _towns[town].get("captives", [])
		for each: Dictionary in held.duplicate():
			if str(each.get("id", "")) == who_id:
				held.erase(each)
				dropped = true
	return dropped


## [param name] ([param who_id]), rescued, has reached [param town]: a
## resident, of [param trade], working if the town has the building for it,
## waiting for it if not. Experience for the rescue. False if they are a
## resident already.
func note_rescue(town: String, who_id: String, name: String, trade: String, origin := "") -> bool:
	var record := _town(town)
	if who_id in record["residents"]:
		return false
	if record.get("sought", {}).has(who_id):
		return sought_home(who_id)  # Sought, held at a camp that fell (613).
	var held: Array = record["captives"].filter(func(each: Dictionary) -> bool: return each["id"] == who_id)
	if not held.is_empty() and who_id.begins_with("companion:"):
		# A companion (decision 314): Main frees her into this town, a
		# resident working her trade till her player comes.
		record["captives"].erase(held[0])
		_note(town, "%s, a companion taken by %s, is rescued and home" % [held[0]["name"], faction_name(str(held[0]["by"]))])
		add_xp(town, int(rules.get("xp", {}).get("rescue", 10)), "%s rescued" % held[0]["name"])
		if companion_freed.is_valid():
			companion_freed.call(who_id.trim_prefix("companion:"), town)
		rescued.emit(town, who_id, str(held[0]["by"]))
		return true
	if not held.is_empty() and not production.worker(who_id).is_empty():
		# Taken in a raid: back as themselves, their work where it was.
		record["captives"].erase(held[0])
		record["residents"].append(who_id)
		production.set_away(who_id, false)
		_note(town, "%s the %s, taken by %s, is rescued and home" % [held[0]["name"], str(held[0]["trade"]).replace("_", " "), faction_name(str(held[0]["by"]))])
		add_xp(town, int(rules.get("xp", {}).get("rescue", 10)), "%s rescued" % held[0]["name"])
		_seat(town)
		rescued.emit(town, who_id, str(held[0]["by"]))
		return true
	if not production.add_worker(who_id, name, [trade], town, "rescued:%s" % (origin if not origin.is_empty() else who_id)):
		return false
	record["residents"].append(who_id)
	_note(town, "%s the %s, rescued, is a resident" % [name, trade.replace("_", " ")])
	if record["residents"].size() > room(town):
		_note(town, "%d residents, room for %d: the town is crowded" % [record["residents"].size(), room(town)])
	add_xp(town, int(rules.get("xp", {}).get("rescue", 10)), "%s rescued" % name)
	_seat(town)
	rescued.emit(town, who_id, "")
	return true


## Resident [param who_id] of [param town] dies of [param why] (npc's
## sickness, decision 501): out of the residents and the workers, their
## workshop freed, the house given up (_seat), "<Name> died of <why>" in the
## log. Their gold is not lost: their purse pays any loan to the bank, the
## rest to the treasury; what the town owed them is cleared. Not a
## companion (hers is her own death and revival). False for no such
## resident.
func died(town: String, who_id: String, why: String) -> bool:
	var record := _town(town)
	if who_id.begins_with("companion:") or who_id not in record["residents"]:
		return false
	var worker := production.worker(who_id)
	if worker.is_empty():
		return false
	var name := str(worker["name"])
	var purse := int(worker["purse"])
	var loan := ceili(float(worker["loan"]))
	if purse > 0 and production.spend(who_id, purse, "left to the town at their death"):
		var to_bank := mini(purse, loan)
		if to_bank > 0:
			production.stockpile.deposit(town, "gold", to_bank, "repay:%s" % who_id, "%s's loan, paid from what they left" % name)
		if purse - to_bank > 0:
			production.stockpile.deposit(town, "gold", purse - to_bank, "estate:%s" % who_id, "what %s left" % name)
	record["residents"].erase(who_id)
	production.remove_worker(who_id)
	# Remembered, so no newcomer takes their name (552 amended).
	var dead: Array = record.get("dead_names", [])
	dead.append(name)
	record["dead_names"] = dead.slice(-DEAD_NAMES)
	_note(town, "%s died of %s" % [name, why])
	_seat(town)
	resident_died.emit(town, who_id, name, why)
	return true


## Someone the town remembers moves in (decisions 460 and 471): false when
## [param town]'s residents are at its room (the growth rescued captives
## use, so the town's talk never crowds them out; not for [param origin]
## "settled", 471's Snagfin, who brings his own stall and is not the
## town's growth, nor "placed", a level's placed captive (npc's, decision
## 518), counted out the moment its camp takes them) or [param who_id] is a worker already; else a resident of [param origin] working [param trade]
## (a [param type] like a thief's, 461, when given), seated, with no
## founding gold, no rescue xp and no rescued signal.
func move_in(town: String, who_id: String, name: String, trade: String, origin := "remembered", type := "") -> bool:
	var record := _town(town)
	if who_id in record["residents"] or (origin != "settled" and origin != "placed" and record["residents"].size() >= room(town)):
		return false
	if not production.add_worker(who_id, name, [trade], town, origin, type):
		return false
	record["residents"].append(who_id)
	_note(town, "%s is found to have lived here all along" % name)
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


## Companion worker [param companion_id] out of every town's residents and
## gone (686, companions' side): she is to settle in another town, one
## with none of her name, so is seated there afresh. Each town she left is
## seated again (as died does). Her purse, which goes with her worker:
## the caller pays it to the worker she becomes. 0, and nothing done, for
## no such worker or one not a companion's.
func drop_companion(companion_id: String) -> int:
	if not companion_id.begins_with("companion:") or production.worker(companion_id).is_empty():
		return 0
	var purse := int(production.worker(companion_id).get("purse", 0))
	var left: Array[String] = []
	for town: String in _towns:
		if (_towns[town]["residents"] as Array).has(companion_id):
			(_towns[town]["residents"] as Array).erase(companion_id)
			left.append(town)
	production.remove_worker(companion_id)
	for town in left:
		_seat(town)
	return purse


## Companion worker [param companion_id] handed back for good (686, npc's
## side; Townsfolk.settle): a resident of her town as [param new_id],
## origin "settled" (room-exempt, as move_in has it; no old-age death),
## working her trades, in her place among the residents; the companion
## worker gone. False when she is no worker or [param new_id] is one.
func settle_companion(companion_id: String, new_id: String) -> bool:
	var who := production.worker(companion_id)
	if who.is_empty() or not production.worker(new_id).is_empty():
		return false
	var town := str(who.get("town", ""))
	var name := str(who.get("name", new_id))
	if not production.add_worker(new_id, name, who.get("trades", []), town, "settled"):
		return false
	# Her purse, what the town owes her and any loan go with her (not earned anew).
	production.pay(new_id, int(who.get("purse", 0)), "what the town owed: %s's own purse, settling" % name)
	production.set_owed(new_id, int(who.get("owed", 0)))
	production.set_loan(new_id, float(who.get("loan", 0.0)), bool(who.get("working_off", false)))
	var record := _town(town)
	var at: int = record["residents"].find(companion_id)
	if at >= 0:
		record["residents"][at] = new_id
	else:
		record["residents"].append(new_id)
	production.remove_worker(companion_id)
	_note(town, "%s settles in the town for good" % name)
	_seat(town)
	return true


# --- Choosing upgrades ---------------------------------------------------------------

## The world tick (after Production's): each town with experience to spend
## and nothing being built chooses its next building by itself, from its
## state: walls when threatened, the building a resident waits for, an inn
## when crowded, else the lowest building that houses a trade. Nothing if
## it can't afford it.
func tick() -> void:
	_stock_camps()
	_herders_turn()
	var towns: Array[String] = []
	towns.assign(_towns.keys().filter(is_town))
	towns.sort()
	for town in towns:
		_spread(town)
		_appoint(town)
		_water(town)
		_crop(town)
		_crop_shown(town)
		_stages(town)
		_farmer_comes(town)
		_flock_turn(town)
		_shepherd_comes(town)
		_weaver_comes(town)
		_butcher_comes(town)
		_butcher(town)
		_woodcut(town)
		_woodcutter_comes(town)
		_fish(town)
		_fisherman_comes(town)
		_stage_turn(town)
		_decline(town)
		_maker_comes(town)
		_sought_turn(town)
		_visitors_turn(town)
		# One build at a time, unless the one in hand has stalled on its
		# materials (decision 522).
		if production.building_in(town) and not production.builds_stalled(town):
			continue
		if _repair(town):
			continue
		if _roof(town):
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
	# An official the town grows into (rules' official "appoint", at its
	# "stage", and "from": residents of its own; the lawspeaker, npc's 459,
	# with the town stage since 652): one, named from its names, with no
	# building (their work place is npc's: the square).
	var official: Dictionary = rules.get("official", {})
	var names_of: Array = official.keys()
	names_of.sort()
	for trade: String in names_of:
		var rule: Dictionary = official[trade]
		if not rule.has("from") and not bool(rule.get("appoint", false)) or not reached(town, str(rule.get("stage", ""))):
			continue
		var own: Array = record["residents"].filter(func(who: String) -> bool:
			return not who.begins_with("companion:") and not str(production.worker(who).get("origin", "")).begins_with("companion:"))
		if own.size() < int(rule.get("from", 0)) or record["residents"].any(func(who: String) -> bool: return trade in production.worker(who).get("trades", [])):
			continue
		var who := "%s:%s" % [trade, town]
		var names: Array = rule.get("names", [])
		var name := str(names[absi(hash(town + trade)) % names.size()]) if not names.is_empty() else trade.capitalize()
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
		if not worker.is_empty() and not _seated(who) and not Production.off_work(worker):
			var kind := kind_for(worker["trades"][0])
			if not kind.is_empty() and kind not in wants:
				wants.append(kind)
	if residents(town).size() >= room(town) and kinds.has("inn"):
		wants.append("inn")
	# A pasture once a field is farmed, a loom once the store holds wool
	# (decision 500): built first, their newcomer comes to it.
	if kinds.has("pasture") and int(building(town, "pasture").get("level", 0)) < 1 and _farmed(town):
		wants.append("pasture")
	if kinds.has("butchery") and int(building(town, "butchery").get("level", 0)) < 1 \
			and float(_town(town).get("flock", {}).get("count", 0.0)) >= float(rules.get("butcher", {}).get("from", 8)):
		wants.append("butchery")  # Decision 590: a butcher's block once the flock can feed one.
	if kinds.has("loom") and int(building(town, "loom").get("level", 0)) < 1 			and production.stockpile.count(town, "wool") >= int(rules.get("flock", {}).get("weaver", {}).get("wool", 6)):
		wants.append("loom")
	var housing: Array = kinds.keys().filter(func(kind: String) -> bool:
		return not str(kinds[kind].get("trade", "")).is_empty() and int(building(town, kind).get("level", 0)) >= 1)
	housing.sort_custom(func(a: String, b: String) -> bool:
		var la := int(building(town, a)["level"])
		var lb := int(building(town, b)["level"])
		return la < lb or la == lb and a < b)
	wants.append_array(housing)
	for kind in wants:
		if int(building(town, kind).get("job", 0)) != 0:
			continue  # Being built already (a stalled one, decision 522).
		var level := int(building(town, kind).get("level", 0)) + 1
		var top := int(kinds[kind].get("max_level", 3))
		if level <= top and xp(town) >= int(kinds[kind].get("xp", 0)) * level:
			return kind
	return ""


# --- Building ------------------------------------------------------------------------

## What [param town]'s next build lacks (decision 499, for players'
## contributions): {kind (the job's building id, "repair:walls" for a
## repair), job, steps, needs: {resource: how many the store lacks}} for
## the first build job still queued (its materials not yet taken), {} for
## none. Walls are the town's defences.
func shortfall(town: String) -> Dictionary:
	for id in production.jobs():
		var each := production.job(id)
		if each["kind"] != "build" or each["town"] != town or each["state"] != "queued":
			continue
		var needs := {}
		for what: String in each.get("cost", {}):
			var lacking := int(each["cost"][what]) - production.stockpile.count(town, what)
			if lacking > 0:
				needs[what] = lacking
		return {"kind": str(each["recipe"]), "job": id, "steps": int(each.get("steps", 0)), "needs": needs}
	return {}


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
	if kind in record.get("gone", []):  # Built again (649): its ground taken back from the forest.
		record["gone"].erase(kind)
		var where: Dictionary = placed.call(town, kind) if placed.is_valid() else {}
		var cells: Array[Vector2i] = []
		cells.assign(where.get("cells", []))
		if not cells.is_empty():
			reclaimed.emit(town, kind, str(where.get("zone", "")), cells)
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
	# A world that starts at tents (649: rules' start "tents") seeds no
	# building: each is built up from the settlement.
	if str(rules.get("start", "")) == "tents":
		return out
	for area_name: String in world_map.areas:
		for house: Dictionary in world_map.areas[area_name].get("buildings", []):
			var kind := str(house.get("use", ""))
			if kind.is_empty() or str(house.get("town", "")).is_empty() or not kinds.has(kind):
				continue
			var town := "%s/%s" % [area_name, house["town"]]
			var record := _town(town)
			if record["buildings"].has(kind) or kind in record.get("gone", []):
				continue
			record["buildings"][kind] = {"kind": kind, "level": 1, "state": STANDING, "since": now(), "job": 0}
			_note(town, "the %s stands, level 1, as the map has it" % kind)
			building_changed.emit(town, kind)
			_seat(town)
			out.append("%s/%s" % [town, kind])
	out.sort()
	for town: String in _towns:
		if stage(town).is_empty() and not _towns[town]["buildings"].is_empty():
			_seeded_stage(town)
	return out


## A town given the map's buildings with no stage yet (649): not a
## settlement of tents, but at least the second stage (a hamlet), and as
## far up as it meets each next stage's needs. A saved stage is kept.
func _seeded_stage(town: String) -> void:
	var stages: Array = rules.get("stages", [])
	var names: Array = stages.map(func(each: Variant) -> String: return str(each.get("name", "")) if each is Dictionary else "")
	if names.size() < 2:
		return
	var at := 1
	while at + 1 < stages.size() and stages[at + 1] is Dictionary and _meets(town, stages[at + 1]):
		at += 1
	_town(town)["stage"] = names[at]
	_note(town, "%s is a %s, as the map has it" % [town, names[at]])
	stage_changed.emit(town)


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
	# Its first stores: enough to reach its first harvest (decision 449
	# amended), rules' start_food or its people's food to the first autumn
	# it can sow for (652), whichever is more.
	var food := maxi(int(rules.get("start_food", 0)), founding_food(town))
	if food > 0:
		production.stockpile.deposit(town, "food", food, "founding", "the town's first stores")
	record["larder"] = food  # Topped up for its people once they are here (_larder).
	_note(town, "founded")
	_spread(town)


## The food [param town]'s people eat before its first crop (652 amended,
## the coordinator's ruling): rules' founding.per_head_day x its residents
## (at least founding.heads) x the days from now to the first crop of any
## kind it can reap, counted from when its field can stand (now if it
## stands, else founding.field_days on): the autumn harvest if spring has
## more than a day left then (else next year's), or the winter's roots,
## whichever comes first, and founding.margin_days more (a late crop, a
## mouth more). 0 without a founding rule.
func founding_food(town: String) -> int:
	var rule: Dictionary = rules.get("founding", {})
	if rule.is_empty():
		return 0
	var heads := maxi(residents(town).size(), int(rule.get("heads", 0)))
	var days := float(maxi(Season.season_days, 1))
	var place := Season.year_fraction(float(now())) * 4.0  # Seasons into the year: spring 0, autumn 2, winter 3.
	var field := place if _stands(town, "field") else place + float(rule.get("field_days", 0)) / days
	var year := floorf(field / 4.0) * 4.0
	var harvest := year + 2.0 if field - year < 1.0 - 1.0 / days else year + 6.0
	var roots := year + 3.0 if field - year < 3.0 else field
	return ceili(float(rule.get("per_head_day", 1)) * heads * ((minf(harvest, roots) - place) * days + float(rule.get("margin_days", 0))))


## The food [param town]'s store keeps from its workshops (652 amended (2),
## the coordinator's ruling: the cook draws on the founding larder only
## above what its people eat till the first crop): founding_food from now
## before its first harvest, 0 after (Production.larder_for).
func larder_for(town: String) -> int:
	return founding_food(town) if before_harvest(town) else 0


## Whether [param town]'s first crop (a harvest or the winter's roots) is
## still to come (652:
## Economy.before_harvest, its caravans keep its food till then).
func before_harvest(town: String) -> bool:
	return int(_towns.get(town, {}).get("harvests", 0)) == 0


## A founded town's first stores topped up, once, the first time it has
## residents (652 amended: founded before its people are counted, it was
## stocked for founding.heads): to founding_food for them, if more.
func _larder(town: String) -> void:
	var record := _town(town)
	if not record.has("larder") or residents(town).is_empty():
		return
	var more := founding_food(town) - int(record["larder"])
	record.erase("larder")
	if more > 0:
		production.stockpile.deposit(town, "food", more, "founding", "the first stores, for its people")


## [param town]'s founding gold, if it waits and the town has residents of
## its own (not companions): split evenly, the first by id a coin more
## for what doesn't divide.
func _spread(town: String) -> void:
	var record := _town(town)
	_larder(town)
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
	if kind.begins_with(ROOF):
		var index := int(kind.trim_prefix(ROOF))
		var mended := mend_roof.is_valid() and bool(mend_roof.call(town, index))
		_note(town, "a roof is mended" if mended else "a roof the carpenter came to was whole already")
		return
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
		if not entry["state"] in [DAMAGED, DISREPAIR] or int(entry["job"]) != 0 or not kinds.has(kind):
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


# --- The town's memory, npc's lawspeaker (npc's decision, economy's side) ------------

## [param town]'s memory: npc's log, kept as it is ({id, tier, text,
## said_by, holders, spread, tags, ruling...}); a deep copy, [] for none.
func memory(town: String) -> Array:
	return (_towns.get(town, {}).get("memory", []) as Array).duplicate(true)


## [param town]'s memory set to [param log], saved with the town as it is.
func set_memory(town: String, log: Array) -> void:
	_town(town)["memory"] = log.duplicate(true)


## [param town]'s lawspeaker ({name, last_round, rulings}: npc's); {} for none.
func lawspeaker(town: String) -> Dictionary:
	return (_towns.get(town, {}).get("lawspeaker", {}) as Dictionary).duplicate(true)


func set_lawspeaker(town: String, record: Dictionary) -> void:
	_town(town)["lawspeaker"] = record.duplicate(true)


# --- Held for their owners (decision 434) ------------------------------------------

## The things [param town] holds for [param owner] (a carrier key) at its
## temple: blessed, waiting to be collected. Uids, oldest first.
func held(town: String, owner: String) -> Array[int]:
	var out: Array[int] = []
	out.assign(_towns.get(town, {}).get("held_for", {}).get(owner, []))
	return out


## Every owner [param town] holds something for.
func held_owners(town: String) -> Array[String]:
	var out: Array[String] = []
	out.assign(_towns.get(town, {}).get("held_for", {}).keys())
	out.sort()
	return out


## [param uid] is no longer held for [param owner] at [param town] (they
## took it). Whether it was.
func release_held(town: String, owner: String, uid: int) -> bool:
	var held_for: Dictionary = _towns.get(town, {}).get("held_for", {})
	if not uid in held_for.get(owner, []):
		return false
	held_for[owner].erase(uid)
	if held_for[owner].is_empty():
		held_for.erase(owner)
	return true


## A thing handed in is done (Production.work_done): held at the town's
## temple for whoever it was done for, however long they are away.
func _on_work_done(job: Dictionary) -> void:
	var town := str(job.get("town", ""))
	var owner := str(job.get("for", ""))
	var uid := int(job.get("worked_on", 0))
	if town.is_empty() or owner.is_empty() or uid == 0:
		return
	var record := _town(town)
	record["held_for"] = record.get("held_for", {})
	if not record["held_for"].has(owner):
		record["held_for"][owner] = []
	record["held_for"][owner].append(uid)
	var where := "temple" if job.get("effect") == "bless" else "forge"
	production.book().place(uid, "%s:%s" % [where, town])
	production.book().note(uid, "held", "at %s's %s for %s, %s by %s" % [town, where, owner, job.get("effect", ""), job.get("by", "")])
	var done: String = {"bless": "blessed", "reforge": "reforged"}.get(str(job.get("effect", "")), "worked on")
	if bool(job.get("failed", false)):
		done = "could not reforge"
	_note(town, "%s %s a %s, held for its owner" % [job.get("by", "someone"), done, Items.name_of(production.book().id_of(uid))])


# --- Rescues (decision 428) ---------------------------------------------

## Camp [param camp] (a Holdings place) went from [param from] to
## [param to] (Holdings.place_taken): taken by the town or freed of its
## holder, everyone it held comes home (each town's captives held there,
## through note_rescue) and so do the strangers it held, to the town
## home_of names, each a resident of their trade. Taken by another
## hostile faction: nothing yet.
func camp_taken(camp: String, _from: String, to: String) -> void:
	if to != Stockpile.TOWN and to != Factions.NOBODY:
		return
	free_held(camp)
	var names: Array[String] = []
	names.assign(_towns.keys())
	names.sort()
	for town in names:
		var record := _town(town)
		var strangers: Dictionary = record.get("strangers", {})
		if not strangers.has(camp):
			continue
		var home := str(home_of.call(camp)) if home_of.is_valid() else town
		for each: Dictionary in strangers[camp]:
			if note_rescue(home if not home.is_empty() else town, str(each["id"]), str(each["name"]), str(each["trade"]), "camp:%s" % camp):
				_note(home if not home.is_empty() else town, "%s the %s was held at %s" % [each["name"], str(each["trade"]).replace("_", " "), camp])
		strangers.erase(camp)
		record["restock"] = record.get("restock", {})
		record["restock"][camp] = now() + int(float(rules.get("rescue", {}).get("restock_days", 5)) * maxi(DayNight.day_steps, 1))


## Every captive held by [param holder] (a camp's place id, or a raid
## group's id while it carries them) freed home to their town, through
## note_rescue: maps calls it for a group that breaks up on the way. The
## ids freed.
func free_held(holder: String) -> Array[String]:
	var out: Array[String] = []
	var names: Array[String] = []
	names.assign(_towns.keys())
	names.sort()
	for town in names:
		for held: Dictionary in _town(town)["captives"].duplicate():
			if str(held.get("held_by", "")) == holder 					and note_rescue(town, str(held["id"]), str(held["name"]), str(held["trade"]), str(held.get("origin", ""))):
				out.append(str(held["id"]))
	return out


## [param town]'s strangers held at camps, {camp id: [{id, name, trade}]}.
func strangers(town: String) -> Dictionary:
	return _towns.get(town, {}).get("strangers", {}).duplicate(true)


## Each hostile camp with nobody held for its home town gets rules'
## rescue.per_camp strangers once its restock time is past: a trade drawn
## by the camp and how many it has held, by rescue.trades' weights, times
## rescue.lacking for a trade the town has nobody of yet.
func _stock_camps() -> void:
	if not camps.is_valid():
		return
	var rule: Dictionary = rules.get("rescue", {})
	for camp: Dictionary in camps.call():
		var id := str(camp["id"])
		var town := str(home_of.call(id)) if home_of.is_valid() else ""
		if town.is_empty():
			continue
		var record := _town(town)
		var held: Dictionary = record.get("strangers", {})
		if held.has(id) or now() < int(record.get("restock", {}).get(id, 0)):
			continue
		var made: Array = []
		var count := int(record.get("strangers_made", 0))
		for i in int(rule.get("per_camp", 1)):
			count += 1
			var draw := RandomNumberGenerator.new()
			draw.seed = hash("%s/%s/%d" % [town, id, count])
			var trade := _draw_trade(town, draw)
			var names_list: Array = rule.get("names", ["Someone"])
			var name := str(names_list[draw.randi_range(0, names_list.size() - 1)])
			made.append({"id": "%s_%s_%d" % [trade, town.replace("/", "_"), count], "name": name, "trade": trade})
		record["strangers_made"] = count
		held[id] = made
		record["strangers"] = held


func _draw_trade(town: String, draw: RandomNumberGenerator) -> String:
	var rule: Dictionary = rules.get("rescue", {})
	var weights: Dictionary = rule.get("trades", {"carpenter": 1})
	var have := {}
	for who in residents(town):
		for trade: String in production.worker(who).get("trades", []):
			have[trade] = true
	var names: Array = weights.keys()
	names.sort()
	var total := 0.0
	var each_weight: Array[float] = []
	for trade: String in names:
		var weight := float(weights[trade]) * (1.0 if have.has(trade) else float(rule.get("lacking", 3)))
		each_weight.append(weight)
		total += weight
	var roll := draw.randf() * total
	for i in names.size():
		roll -= each_weight[i]
		if roll < 0.0:
			return str(names[i])
	return str(names[-1])


# --- Farms (decision 449) -------------------------------------------------------------

## The season length economy.json's season-bound yields are set for (533).
const SEASON_DAYS_RULED := 7.0

## What a season's yields are scaled by (decision 533, environment's
## longer seasons): the season's days over the 7 economy.json's crop.harvest,
## crop.roots and flock.wool are set for, so a day's food and wool stay
## the same whatever the season's length (7 days: 1; 14: 2).
static func season_scale() -> float:
	return float(maxi(Season.season_days, 1)) / SEASON_DAYS_RULED


## [param town]'s crop this year ({} with no field): {stage ("" | "sown" |
## "harvested" | "rotted"), growth, worked (steps sowing or harvesting),
## season (the last seen), roots (dug this winter), at}.
func crop(town: String) -> Dictionary:
	return _towns.get(town, {}).get("crop", {}).duplicate()


## How [param town]'s field looks (decision 457; art-kit's state
## parts): "sown" in spring once sown, "growing" in summer ("flattened" for
## a day after a storm flattened it), "ripe" in autumn till brought in, ""
## otherwise (unsown, harvested, rotted, winter, no field).
func crop_look(town: String) -> String:
	var crop_now: Dictionary = _towns.get(town, {}).get("crop", {})
	if crop_now.get("stage") != "sown":
		return ""
	match str(crop_now.get("season", "")):
		"spring":
			return "sown"
		"summer":
			var flattened := int(crop_now.get("flattened", -1))
			return "flattened" if flattened >= 0 and now() - flattened < maxi(DayNight.day_steps, 1) else "growing"
		"autumn":
			return "ripe"
	return ""


## Whether [param town]'s farmer's work counts toward its crop now (566
## amended, npc's hoe): its field standing (or building), the farm manned
## and its site held, and spring with the crop unsown or autumn with it
## sown, as _crop works it.
func field_work(town: String) -> bool:
	if int(building(town, "field").get("level", 0)) < 1 or building(town, "field").get("state") not in [STANDING, BUILDING]:
		return false
	if not production.manned("%s:field" % town) or not production.site_works(town, "farmer"):
		return false
	var crop_now: Dictionary = _towns.get(town, {}).get("crop", {})
	var season := Season.name_at(now())
	var stage := str(crop_now.get("stage", ""))
	match season:
		"spring":
			return stage == "" or str(crop_now.get("season", "")) != season  # A new year's, before _crop clears last year's.
		"autumn":
			return stage == "sown"
	return false


## The year's crop moved on to now (Season.name_at): sown in spring by the
## farmer's sow_steps of work; in summer growth a day, clamp(base + rain x
## the day's rain, least, most) / season_days, each storm flattening it
## (by half) with chance flatten; in autumn brought in by his
## harvest_steps of work as harvest x the field's level x growth food,
## rotting if not by winter; in winter roots x level food, dug once. A
## season passed by with no farmer leaves the crop as it is.
func _crop(town: String) -> void:
	var level := int(building(town, "field").get("level", 0))
	if level < 1 or building(town, "field").get("state") not in [STANDING, BUILDING]:
		return
	var rule: Dictionary = rules.get("crop", {})
	var record := _town(town)
	var at := now()
	var crop_now: Dictionary = record.get("crop", {"stage": "", "growth": 0.0, "worked": 0, "season": "", "roots": false, "at": at, "flattened": -1})
	record["crop"] = crop_now
	var since := maxi(at - int(crop_now["at"]), 0)
	crop_now["at"] = at
	var season := Season.name_at(at)
	if season != crop_now["season"]:
		_crop_turn(town, crop_now, str(crop_now["season"]), season)
		crop_now["season"] = season
	# Only while the town holds its farm, if it has one (decision 521).
	var farming := production.manned("%s:field" % town) and production.site_works(town, "farmer")
	match season:
		"spring":
			if crop_now["stage"] == "" and farming:
				crop_now["worked"] = int(crop_now["worked"]) + since
				if int(crop_now["worked"]) >= int(rule.get("sow_steps", 3000)):
					crop_now["stage"] = "sown"
					crop_now["worked"] = 0
					_note(town, "the field is sown")
		"summer":
			if crop_now["stage"] == "sown" and since > 0:
				var days := float(since) / maxi(DayNight.day_steps, 1)
				var fell := float(rain.call(town, float(at - since), float(at))) if rain.is_valid() else 0.0
				var growth: Dictionary = rule.get("growth", {})
				var per_day := clampf(float(growth.get("base", 0.7)) + float(growth.get("rain", 3.0)) * fell / maxf(days, 0.0001),
					float(growth.get("least", 0.4)), float(growth.get("most", 1.3)))
				crop_now["growth"] = float(crop_now["growth"]) + per_day * days / maxi(Season.season_days, 1)
				if storms.is_valid():
					for storm: Dictionary in storms.call(town, float(at - since), float(at)):
						if Weather._unit("%s:%s:crop" % [storm["id"], town]) < float(rule.get("flatten", 0.5)):
							crop_now["growth"] = float(crop_now["growth"]) * 0.5
							crop_now["flattened"] = at  # For the field's look later: "flattened".
							_note(town, "a storm flattened half the crop")
		"autumn":
			if crop_now["stage"] == "sown" and farming:
				crop_now["worked"] = int(crop_now["worked"]) + since
				if int(crop_now["worked"]) >= int(rule.get("harvest_steps", 3000)):
					var food := roundi(float(rule.get("harvest", 150)) * season_scale() * level * float(crop_now["growth"]))
					production.deliver_to(town, production.worker_at("%s:field" % town), "food", food, "harvest", "the harvest")
					crop_now["stage"] = "harvested"
					crop_now["worked"] = 0
					_note(town, "the harvest is in: %d food" % food)
					record["harvests"] = int(record.get("harvests", 0)) + 1
		"winter":
			if not bool(crop_now["roots"]) and farming:
				var roots := roundi(float(rule.get("roots", 20)) * season_scale()) * level
				production.deliver_to(town, production.worker_at("%s:field" % town), "food", roots, "roots", "roots dug in winter")
				crop_now["roots"] = true
				_note(town, "roots dug: %d food" % roots)
				record["harvests"] = int(record.get("harvests", 0)) + 1  # A crop too (652 amended): the first may be the roots.


## When [param town]'s field's look changed, building_changed for it: Main
## sends the town's buildings ("town"), the look with them.
func _crop_shown(town: String) -> void:
	var record: Dictionary = _towns.get(town, {})
	if not record.has("crop"):
		return
	var look := crop_look(town)
	if look != str(record["crop"].get("look", "")):
		record["crop"]["look"] = look
		building_changed.emit(town, "field")


## A season ended for [param town]'s crop: a crop not brought in by winter
## rots; a new year's spring starts bare.
func _crop_turn(town: String, crop_now: Dictionary, was: String, now_season: String) -> void:
	if now_season == "winter" and crop_now["stage"] == "sown" and was != "":
		crop_now["stage"] = "rotted"
		_note(town, "the crop rotted in the field")
	if now_season == "spring":
		crop_now["stage"] = ""
		crop_now["growth"] = 0.0
		crop_now["worked"] = 0
		crop_now["roots"] = false


## A town whose field stands with no farmer gets one, a newcomer, once it
## has stood growth_days without one (by growth; a rescue may bring one
## first).
func _farmer_comes(town: String) -> void:
	var house := building(town, "field")
	if int(house.get("level", 0)) < 1 or house.get("state") != STANDING:
		return
	if _has_trade(town, "farmer"):
		return
	var rule: Dictionary = rules.get("crop", {})
	var record := _town(town)
	var waiting_since := int(record.get("farmer_wanted", -1))
	if waiting_since < 0:
		record["farmer_wanted"] = now()
		return
	if now() - waiting_since < int(float(rule.get("growth_days", 5)) * maxi(DayNight.day_steps, 1)):
		return
	var count := int(record.get("farmers_came", 0)) + 1
	record["farmers_came"] = count
	record.erase("farmer_wanted")
	var names: Array = rule.get("names", ["Tam"])
	var name := _free_name(town, names, absi(hash("%s/%d" % [town, count])))
	var id := "farmer_%s_%d" % [town.replace("/", "_"), count]
	_arrive(town, id, name, "farmer", "%s the farmer comes to work the field" % name)


# --- Sheep and wool (decision 500) ---------------------------------------------------

## The hill herders (decision 640, economy's side; Jeff: "herders exist as
## people"): each Holdings place whose key is one of rules' herder.places
## (the hills' refuges) is a herder's holding of its own, as a healer's hut
## is. One with no herder gets one, "<trade>:<place>", once it has stood
## herder.growth_days, with herder.start sheep of their own (the place's
## "sheep" in the stockpile, held by nobody). Each spring their drove lambs
## as the town's flock does, toward herder.most. Every herder.every days,
## home, the herder walks all but herder.keep down to the town they sell to
## (drove_town): the fold's count drops at once, they are away
## herder.walk_steps, and what the town didn't buy (drove: its treasury
## pays, never owes) comes home with them.
func _herders_turn() -> void:
	var rule: Dictionary = rules.get("herder", {})
	if rule.is_empty() or production.holdings == null:
		return
	var at := now()
	var day := maxi(DayNight.day_steps, 1)
	var trade := str(rule.get("trade", "herder"))
	var stock := production.stockpile
	for id in production.holdings.all_places():
		var place := production.holdings.place(id)
		if str(place.get("key", "")) not in rule.get("places", []):
			continue
		if not _herders.has(id):
			_herders[id] = {"since": at, "season": "", "lambs": 0.0, "next": 0, "back": 0, "unsold": 0}
		var herd: Dictionary = _herders[id]
		var who := "%s:%s" % [trade, id]
		if production.worker(who).is_empty():
			if at - int(herd["since"]) < float(rule.get("growth_days", 3)) * day:
				continue
			var names: Array = rule.get("names", [])
			var name := str(names[absi(hash(id)) % names.size()]) if not names.is_empty() else trade.capitalize()
			production.add_worker(who, name, [trade], id, str(place.get("area", "")))
			stock.deposit(id, "sheep", int(rule.get("start", 4)), name, "a drove of their own")
			herd["next"] = at + int(float(rule.get("every", 3)) * day)
			print("[towns] %s the %s keeps %s, %d sheep" % [name, trade, id, stock.count(id, "sheep")])
			folds_changed.emit(id)
			continue
		if bool(production.worker(who).get("away", false)):
			if at < int(herd["back"]):
				continue
			production.set_away(who, false)
			herd.erase("buyer")
			if int(herd["unsold"]) > 0:
				stock.deposit(id, "sheep", int(herd["unsold"]), str(production.worker(who)["name"]), "home unsold")
				herd["unsold"] = 0
			folds_changed.emit(id)
		var season := Season.name_at(at)
		if season != str(herd["season"]):
			if season == "spring" and not str(herd["season"]).is_empty():
				var count := float(stock.count(id, "sheep"))
				var lambs := float(herd["lambs"]) + maxf(count * float(rule.get("lambs", 0.6)) * (1.0 - count / maxf(float(rule.get("most", 8)), 1.0)), 0.0)
				var born := floori(lambs)
				herd["lambs"] = lambs - born
				if born > 0:
					stock.deposit(id, "sheep", born, str(production.worker(who)["name"]), "lambs")
					folds_changed.emit(id)
			herd["season"] = season
		if at < int(herd["next"]):
			continue
		herd["next"] = at + int(float(rule.get("every", 3)) * day)
		var count := stock.count(id, "sheep") - int(rule.get("keep", 2))
		var buyer := drove_town(id)
		if count < 1 or buyer.is_empty() or not drove.is_valid():
			continue
		stock.take(id, "sheep", count, "driven to %s" % buyer)
		var sold := int(drove.call(buyer, who, count, int(rule.get("food", 2))))
		herd["unsold"] = count - sold
		herd["buyer"] = buyer  # Where they are while away (npc's body stands at its store).
		herd["back"] = at + int(rule.get("walk_steps", 3000))
		production.set_away(who, true)
		print("[towns] %s drives %d sheep to %s, sells %d" % [production.worker(who)["name"], count, buyer, sold])
		folds_changed.emit(id)


## Whether [param id] is a town and not a holding with workers of its own
## (a herder's fold, a healer's hut: their workers' "town" is the place,
## so a record may be made for it): any id Holdings doesn't know (a test's
## town), or one it knows as a stockpile.
func is_town(id: String) -> bool:
	if production.holdings == null:
		return true
	var place := production.holdings.place(id)
	return place.is_empty() or str(place.get("kind", "")) == "stockpile"


## The town herder place [param id]'s drove goes to: one whose butchery
## stands and whose store holds under butcher.from sheep, in the place's
## own area first, then by id; "" for none.
func drove_town(id: String) -> String:
	var area := str(production.holdings.place(id).get("area", "")) if production.holdings != null else ""
	var under := int(rules.get("butcher", {}).get("from", 8))
	var towns: Array = _towns.keys().filter(func(town: String) -> bool:
		return is_town(town) and _stands(town, "butchery") and production.stockpile.count(town, "sheep") < under)
	towns.sort_custom(func(a: String, b: String) -> bool:
		var near_a := str(production.holdings.place(a).get("area", "")) == area if production.holdings != null else false
		var near_b := str(production.holdings.place(b).get("area", "")) == area if production.holdings != null else false
		return near_a and not near_b or near_a == near_b and a < b)
	return str(towns[0]) if not towns.is_empty() else ""


## The herders' folds in [param area_name] (every area: ""): place id ->
## its sheep at home (640, the "folds" message).
func folds(area_name := "") -> Dictionary:
	var out := {}
	for id: String in _herders:
		if area_name.is_empty() or production.holdings != null and str(production.holdings.place(id).get("area", "")) == area_name:
			out[id] = production.stockpile.count(id, "sheep")
	return out


## [param town]'s flock ({} for none; Jeff: "sheep and wool yes"): {count
## (a float: lambs come in parts), season (the last seen), sheared (this
## season), worked (steps shearing)}. The count is the sheep there are, the
## source for drawn sheep at the pasture.
func flock(town: String) -> Dictionary:
	return _towns.get(town, {}).get("flock", {}).duplicate()


## The flock moved on to now: each spring lambs, count x flock.lambs x (1 -
## count / room), room flock.per_level a level of a standing pasture (the
## shepherd's own start with none); in spring and in autumn, once each, the
## shepherd at the pasture works shear_steps and the flock's wool (count x
## flock.wool) goes to the store, bought from him (Production.deliver_to).
## A season passed by with nobody at the pasture is not sheared.
func _flock_turn(town: String) -> void:
	var record := _town(town)
	if not record.has("flock"):
		return
	var rule: Dictionary = rules.get("flock", {})
	var flock_now: Dictionary = record["flock"]
	var at := now()
	var since := maxi(at - int(flock_now.get("at", at)), 0)
	flock_now["at"] = at
	var season := Season.name_at(at)
	if season != str(flock_now.get("season", "")):
		if season == "spring" and str(flock_now.get("season", "")) != "":
			var house := building(town, "pasture")
			var levels := int(house.get("level", 0)) if house.get("state") in [STANDING, BUILDING] else 0
			var room := float(rule.get("per_level", 12)) * levels if levels > 0 else float(rule.get("start", 6))
			var count := float(flock_now["count"])
			var lambs := maxf(count * float(rule.get("lambs", 0.5)) * (1.0 - count / maxf(room, 1.0)), 0.0)
			flock_now["count"] = count + lambs
			if floori(count + lambs) > floori(count):
				var born := floori(count + lambs) - floori(count)
				_note(town, "%s in the flock, %d sheep now" % ["a lamb" if born == 1 else "%d lambs" % born, floori(count + lambs)])
		flock_now["season"] = season
		flock_now["sheared"] = false
		flock_now["worked"] = 0
	if season not in ["spring", "autumn"] or bool(flock_now.get("sheared", false)) or not production.manned("%s:pasture" % town):
		return
	flock_now["worked"] = int(flock_now.get("worked", 0)) + since
	if int(flock_now["worked"]) < int(rule.get("shear_steps", 2000)):
		return
	var wool := floori(float(flock_now["count"]) * float(rule.get("wool", 1)) * season_scale())
	flock_now["sheared"] = true
	flock_now["worked"] = 0
	if wool > 0:
		production.deliver_to(town, production.worker_at("%s:pasture" % town), "wool", wool, "shearing", "the %s shearing" % season)
		_note(town, "the flock is sheared: %d wool" % wool)
	if season == "autumn":
		_cull(town, flock_now)


## The autumn cull (decision 590: Jeff's "the herder, the butcher, the cook
## - its a supply chain"): with a butcher in town, the shepherd drives the
## flock down to butcher.keep of the pasture's room, the culled sheep into
## the store live ("sheep"), delivered at its price.
func _cull(town: String, flock_now: Dictionary) -> void:
	var rule: Dictionary = rules.get("butcher", {})
	var trade := str(rule.get("trade", "butcher"))
	if rule.is_empty() or not residents(town).any(func(who: String) -> bool: return trade in production.worker(who).get("trades", [])):
		return
	var house := building(town, "pasture")
	var levels := int(house.get("level", 0)) if house.get("state") in [STANDING, BUILDING] else 0
	var room := float(rules.get("flock", {}).get("per_level", 12)) * levels if levels > 0 else float(rules.get("flock", {}).get("start", 6))
	var culled := floori(float(flock_now["count"]) - room * float(rule.get("keep", 0.5)))
	if culled < 1:
		return
	flock_now["count"] = float(flock_now["count"]) - culled
	production.deliver_to(town, production.worker_at("%s:pasture" % town), "sheep", culled, "culling", "the autumn cull")
	_note(town, "the shepherd culls %d sheep for the butcher, %d left in the flock" % [culled, floori(float(flock_now["count"]))])


## A town whose butchery stands (built once its flock reaches butcher.from:
## choose) with no butcher gets one, a newcomer, once it has stood
## butcher.growth_days without (decision 590).
func _butcher_comes(town: String) -> void:
	var rule: Dictionary = rules.get("butcher", {})
	var wanted: bool = not rule.is_empty() and _stands(town, "butchery")
	_comes(town, str(rule.get("trade", "butcher")), wanted, float(rule.get("growth_days", 3)), rule.get("names", ["Hew"]), "butcher")


## The butcher at his manned butchery works the store's sheep: each
## butcher.steps of work one sheep becomes butcher.meat meat and
## butcher.hide hide, delivered into the store at their price (decision
## 590); the meat joins the hunter's in the one pool.
func _butcher(town: String) -> void:
	var rule: Dictionary = rules.get("butcher", {})
	var record := _town(town)
	var at := now()
	var since := maxi(at - int(record.get("butcher_at", at)), 0)
	record["butcher_at"] = at
	var shop := "%s:butchery" % town
	if rule.is_empty() or production.stockpile.count(town, "sheep") < 1 or not production.manned(shop):
		record["butcher_worked"] = 0
		return
	record["butcher_worked"] = int(record.get("butcher_worked", 0)) + since
	var steps := maxi(int(rule.get("steps", 900)), 1)
	var who := production.worker_at(shop)
	while int(record["butcher_worked"]) >= steps and production.stockpile.count(town, "sheep") >= 1:
		record["butcher_worked"] = int(record["butcher_worked"]) - steps
		production.stockpile.take(town, "sheep", 1, "butchered by %s" % production.worker(who).get("name", who))
		production.deliver_to(town, who, "meat", int(rule.get("meat", 3)), "butchering", "a sheep butchered")
		production.deliver_to(town, who, "hide", int(rule.get("hide", 1)), "butchering", "a sheep butchered")
		_note(town, "the butcher dresses a sheep: %d meat, %d hide" % [int(rule.get("meat", 3)), int(rule.get("hide", 1))])


## Whether [param town]'s field stands and has its farmer.
func _farmed(town: String) -> bool:
	var field := building(town, "field")
	return int(field.get("level", 0)) >= 1 and field.get("state") == STANDING 			and residents(town).any(func(who: String) -> bool: return "farmer" in production.worker(who).get("trades", []))


## Whether [param town]'s [param kind] stands (at least level 1).
func _stands(town: String, kind: String) -> bool:
	var house := building(town, kind)
	return int(house.get("level", 0)) >= 1 and house.get("state") == STANDING


## A town whose pasture stands (built once its field is farmed: choose)
## with no shepherd gets one, a newcomer with flock.start sheep of their own
## (the town's flock from then), once it has stood flock.growth_days without
## (as a field gets its farmer).
func _shepherd_comes(town: String) -> void:
	var rule: Dictionary = rules.get("flock", {})
	var wanted: bool = not rule.is_empty() and _stands(town, "pasture")
	_comes(town, str(rule.get("trade", "shepherd")), wanted, float(rule.get("growth_days", 3)), rule.get("names", ["Wat"]), "shepherd")


## A town whose loom stands (built once the store holds flock.weaver.wool
## wool: choose) with no weaver gets one, a newcomer, once it has stood
## flock.weaver.growth_days without; the weaver makes the bolt of cloth
## from wool (items' 500).
func _weaver_comes(town: String) -> void:
	var rule: Dictionary = rules.get("flock", {}).get("weaver", {})
	var wanted: bool = not rule.is_empty() and _stands(town, "loom")
	_comes(town, str(rule.get("trade", "weaver")), wanted, float(rule.get("growth_days", 3)), rule.get("names", ["Joan"]), "weaver")


## A newcomer of [param trade] to [param town] while [param wanted] and the
## town has none, once it has been wanted [param days] days: named from
## [param names] by the town and the count come, moved in by growth. True
## the tick one comes.
func _comes(town: String, trade: String, wanted: bool, days: float, names: Array, key: String) -> bool:
	var record := _town(town)
	if not wanted or _has_trade(town, trade):
		record.erase("%s_wanted" % key)
		return false
	var waiting_since := int(record.get("%s_wanted" % key, -1))
	if waiting_since < 0:
		record["%s_wanted" % key] = now()
		return false
	if now() - waiting_since < int(days * maxi(DayNight.day_steps, 1)):
		return false
	var count := int(record.get("%ss_came" % key, 0)) + 1
	record["%ss_came" % key] = count
	record.erase("%s_wanted" % key)
	var name := _free_name(town, names, absi(hash("%s/%s/%d" % [town, key, count]))) if not names.is_empty() else trade.capitalize()
	var id := "%s_%s_%d" % [key, town.replace("/", "_"), count]
	return _arrive(town, id, name, trade, "%s the %s comes to %s" % [name, trade, town])


## A town with a workshop of a maker's trade (Items.TRADES) or of a
## building's built_by trade (the carpenter, who builds everything) and no
## resident of that trade (died, or turned to other work: npc's Pip, made
## Aldous's acolyte) gets one, a newcomer, once it has gone maker_comes.
## growth_days without (decision 552). Not while one of the trade is held
## captive: they may come back. One trade at a time, by name.
func _maker_comes(town: String) -> void:
	var rule: Dictionary = rules.get("maker_comes", {})
	if rule.is_empty():
		return
	var builders := {}
	for kind: String in rules.get("buildings", {}):
		builders[str(rules["buildings"][kind].get("built_by", ""))] = true
	var held: Array = _town(town).get("captives", []).map(func(each: Dictionary) -> String: return str(each.get("trade", "")))
	var trades := {}
	for id in production.workshop_ids(town):
		var trade := str(production.workshop(id)["trade"])
		if (trade in Items.TRADES or builders.has(trade)) and trade not in held:
			trades[trade] = true
	var names: Array = trades.keys()
	names.sort()
	for trade: String in names:
		# _comes forgets the wait once one of the trade is there.
		_comes(town, trade, true, float(rule.get("growth_days", 3)), rule.get("names", []), "%s_newcomer" % trade)


# --- The sought (decision 613) -------------------------------------------------------

## Whether [param town] has someone of [param trade]: a resident, or one
## sought for it (613: the town waits for them to be found).
func _has_trade(town: String, trade: String) -> bool:
	for each: Dictionary in _town(town).get("sought", {}).values():
		if str(each["trade"]) == trade:
			return true
	return residents(town).any(func(who: String) -> bool: return trade in production.worker(who).get("trades", []))


## [param trade]'s story (613 amended, Jeff: "every npc has their own
## place and story of how they got there"): rules' sought.trades row
## {place (maps' or dungeon's place key, or "camp"), where, holder (a
## faction, "" lost), band (enemy-ai's), story (lore's id), alt (a second
## variant, the same keys)}; {} for a trade lore has no story for yet.
func _story(trade: String) -> Dictionary:
	return rules.get("sought", {}).get("trades", {}).get(trade, {})


## Whether a newcomer of [param trade] is found rather than walks in (613,
## Jeff: "npcs for the town are found in the wilds, the hills, or forest,
## or under the castle in the dungeons. rescue and return to town"): maps'
## place_sought set and the trade has a story. A trade without one walks
## in meanwhile (the coordinator: an interim only).
func _seeking(trade: String) -> bool:
	return place_sought.is_valid() and not _story(trade).is_empty()


## A newcomer [param id] ([param name], of [param trade]) for
## [param town]: sought (613) when the trade's newcomers are found, else
## moved in by growth as before, the log saying [param line]. True when
## they are in town now.
func _arrive(town: String, id: String, name: String, trade: String, line: String) -> bool:
	if _seeking(trade):
		_seek(town, id, name, trade)
		return false
	if not production.add_worker(id, name, [trade], town, "growth"):
		return false
	_town(town)["residents"].append(id)
	_note(town, line)
	_seat(town)
	_arrived(town, trade)
	return true


## What a newcomer of [param trade] brings to [param town] on coming:
## the shepherd his flock (500).
func _arrived(town: String, trade: String) -> void:
	var rule: Dictionary = rules.get("flock", {})
	var record := _town(town)
	if not rule.is_empty() and trade == str(rule.get("trade", "shepherd")) and not record.has("flock"):
		record["flock"] = {"count": float(rule.get("start", 6)), "season": Season.name_at(now()), "sheared": false, "worked": 0, "at": now()}
		_note(town, "the shepherd brings a flock of %d" % int(rule.get("start", 6)))


## [param town] wants one of [param trade]: [param id] ([param name]) is
## made a worker of the town away from day one (origin "sought": no work,
## meals, rent or wage, not a resident) and an entry kept until they are
## found and brought home (sought_home). A resident who wandered off
## ([param wandered], 613 amended) is the same worker made away again, their
## card, memory and purse kept, and "door" where they leave their note
## (Jeff: "a small note saying where they went" on their "door or shop"):
## the workshop they kept, else "inn" (their bed's); "" for one who never
## came. Placed by _sought_turn.
func _seek(town: String, id: String, name: String, trade: String, wandered := false) -> void:
	var record := _town(town)
	var door := ""
	if wandered:
		door = production.workshop_of(id)
		door = door if not door.is_empty() else "inn"
		record["residents"].erase(id)
	elif not production.add_worker(id, name, [trade], town, "sought"):
		return
	production.set_away(id, true)
	record["sought"] = record.get("sought", {})
	record["sought"][id] = {"id": id, "name": name, "trade": trade, "place": "", "where": "", "holder": "", "story": "",
		"since": now(), "next_try": now(), "freed_by": "", "tries": int(record.get("sought_tries", {}).get(trade, 0)), "wandered": wandered, "door": door}
	if not wandered:
		_note(town, "%s has no %s: word goes out for one" % [town, trade.replace("_", " ")])
	sought_changed.emit(town, id)


## [param town]'s sought entries: [{id, name, trade, place ("" not yet
## placed), where (the place's where-word: wilds, hills, forest,
## castle_dungeon, camp), holder (the faction holding them, "" lost),
## story (lore's id for this time out), since, next_try, freed_by (the
## player leading them home, ""), tries (times the trade was placed
## before), wandered (a resident who left, 613 amended)}].
func sought(town: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var record: Dictionary = _towns.get(town, {}).get("sought", {})
	var ids: Array = record.keys()
	ids.sort()
	for id: String in ids:
		out.append((record[id] as Dictionary).duplicate())
	return out


## The sought entry [param id] with its "town", {} if none.
func sought_entry(id: String) -> Dictionary:
	for town: String in _towns:
		var record: Dictionary = _towns[town].get("sought", {})
		if record.has(id):
			var out: Dictionary = (record[id] as Dictionary).duplicate()
			out["town"] = town
			return out
	return {}


## Each turn for [param town]: a resident low too long wanders off
## (_wander_turn); an entry whose trade a resident now has (a stranger freed
## from a camp, say) and nobody leads home is dropped; an unplaced one past
## its next_try is placed by its trade's story: the first time out its own
## place, then its variants in turn (lore: "a second time out draws a
## different variant from the last where it can"). A place key is maps' or
## dungeon's (place_sought: {place, where}, or "" while it isn't laid:
## tried again a day on); "camp" is a hostile camp whose freed go home here
## (518's path: a captive held there, freed with the camp).
func _sought_turn(town: String) -> void:
	_wander_turn(town)
	var record := _town(town)
	if not record.has("sought"):
		return
	var ids: Array = record["sought"].keys()
	ids.sort()
	for id: String in ids:
		var entry: Dictionary = record["sought"][id]
		var trade := str(entry["trade"])
		if str(entry["freed_by"]).is_empty() and residents(town).any(func(who: String) -> bool: return trade in production.worker(who).get("trades", [])):
			_unhold(town, id)
			record["sought"].erase(id)
			if bool(entry.get("wandered", false)):
				production.set_away(id, false)  # Theirs is taken: back at the town, out of work, as a worker of it.
				record["residents"].append(id)
				_seat(town)
			else:
				production.remove_worker(id)
			_note(town, "%s has a %s again: the word for one is called off" % [town, trade.replace("_", " ")])
			sought_changed.emit(town, id)
			continue
		if not str(entry["place"]).is_empty() or now() < int(entry["next_try"]):
			continue
		var story := _story(trade)
		var variants: Array = [story]
		if story.get("alt") is Dictionary and not (story["alt"] as Dictionary).is_empty():
			variants.append(story["alt"])
		var variant := {}
		# This time out's variant first; one that can't be placed now (no
		# camp holds for the town, a place not laid yet) gives way to the next.
		for k in (variants.size() if not story.is_empty() else 0):
			variant = variants[(int(entry.get("tries", 0)) + k) % variants.size()]
			if _place_variant(town, id, entry, variant):
				break
		if str(entry["place"]).is_empty():
			entry["holder"] = ""
			entry["next_try"] = now() + maxi(DayNight.day_steps, 1)
			continue
		entry["story"] = str(variant.get("story", ""))
		var tries: Dictionary = record.get("sought_tries", {})
		tries[trade] = int(tries.get(trade, 0)) + 1
		record["sought_tries"] = tries
		entry["tries"] = int(tries[trade])
		_note(town, "word is %s the %s was seen %s" % [entry["name"], trade.replace("_", " "), where_words(str(entry["where"]))])
		sought_changed.emit(town, id)


## Sought [param id] ([param entry]) of [param town] placed by the story's
## [param variant]: "camp" a hostile camp whose freed go home here, held
## there as a captive (518's path); else maps' or dungeon's place for its
## key (place_sought), held by its holder. False if it can't be now.
func _place_variant(town: String, id: String, entry: Dictionary, variant: Dictionary) -> bool:
	if str(variant.get("place", "")) == "camp":
		if not camps.is_valid():
			return false
		for camp: Dictionary in camps.call():
			var id_camp := str(camp["id"])
			if home_of.is_valid() and str(home_of.call(id_camp)) != town:
				continue
			entry["place"] = id_camp
			entry["where"] = "camp"
			entry["holder"] = str(camp["faction"])
			_town(town)["captives"].append({"id": id, "name": entry["name"], "trade": entry["trade"], "origin": "sought:%s" % id_camp,
				"purse": 0, "taken_at": now(), "by": entry["holder"], "held_by": id_camp})
			return true
		return false
	if not place_sought.is_valid():
		return false
	var found: Variant = place_sought.call(town, str(entry["trade"]), variant, id)
	if found is Dictionary and not str(found.get("place", "")).is_empty():
		entry["place"] = str(found["place"])
		entry["where"] = str(found.get("where", variant.get("where", "")))
	elif found is String and not found.is_empty():
		entry["place"] = found
		entry["where"] = str(variant.get("where", ""))
	else:
		return false
	entry["holder"] = str(variant.get("holder", ""))
	return true


## Wandering off (613 amended; Jeff: "for replayablity sake they may wander
## off (get re-captured) if they run low on resources or funds"): a
## resident of a trade with a story is low while hungry (not on the dole),
## owed wages the town hasn't paid, or seated with work queued at their
## workshop and none going (waiting on stock); low past rules'
## sought.leave_days, they go back to their story's place, sought again as
## themselves (_seek wandered), the log saying so and the wandered signal
## for the words. Never a companion or one away (a captive, one being led
## home); one a town each sought.wander_every_days.
func _wander_turn(town: String) -> void:
	var rule: Dictionary = rules.get("sought", {})
	if not place_sought.is_valid() or rule.is_empty():
		return
	var record := _town(town)
	var low: Dictionary = record.get("low", {})
	record["low"] = low
	var day := maxi(DayNight.day_steps, 1)
	var due := int(float(rule.get("leave_days", 5)) * day)
	var leaving := ""
	for id: String in residents(town):
		var worker := production.worker(id)
		var trades: Array = worker.get("trades", [])
		if trades.is_empty() or _story(str(trades[0])).is_empty() or str(worker.get("origin", "")).begins_with("companion:") \
				or bool(worker.get("away", false)) or not _low(id, worker):
			low.erase(id)
			continue
		if not low.has(id):
			low[id] = now()
		elif now() - int(low[id]) >= due and leaving.is_empty():
			leaving = id
	var every := int(float(rule.get("wander_every_days", 1)) * day)
	if leaving.is_empty() or record.has("wandered_at") and now() - int(record["wandered_at"]) < every:
		return
	low.erase(leaving)
	record["wandered_at"] = now()
	var worker := production.worker(leaving)
	var trade := str(worker["trades"][0])
	_note(town, "%s the %s has gone, low too long; they say back where they were found" % [worker["name"], trade.replace("_", " ")])
	_seek(town, leaving, str(worker["name"]), trade, true)
	_seat(town)
	wandered.emit(town, leaving)


## Whether worker [param id] ([param worker]) is low (613 amended): hungry
## and not on the dole, owed unpaid wages, or seated with work queued at
## their workshop and none of it going.
func _low(id: String, worker: Dictionary) -> bool:
	if str(worker.get("fed", "")) == "hungry" or int(worker.get("owed", 0)) > 0:
		return true
	var shop := production.workshop_of(id)
	if shop.is_empty():
		return false
	var queued := false
	for job_id: int in production.jobs():
		var job := production.job(job_id)
		if str(job.get("workshop", "")) != shop:
			continue
		if job.get("state") == "working":
			return false
		if job.get("state") == "queued":
			queued = true
	return queued


## The words for a sought's [param where] ("in the hills", "under the
## castle"), for the log and npc's officials.
static func where_words(where: String) -> String:
	match where:
		"camp":
			return "held at a camp"
		"castle_dungeon":
			return "under the castle"
		"wilds":
			return "in the wilds"
		"":
			return "somewhere out there"
	return "in the %s" % where.replace("_", " ")


## Sought [param id] is freed by player [param by] (npc: a word to the
## lost, or to the held when no holder sees them) and follows them home:
## out of a camp's held so its fall doesn't bring them too. False if not
## placed or led already.
func free_sought(id: String, by: String) -> bool:
	var entry := sought_entry(id)
	if entry.is_empty() or str(entry["place"]).is_empty() or not str(entry["freed_by"]).is_empty():
		return false
	var town := str(entry["town"])
	_unhold(town, id)
	_town(town)["sought"][id]["freed_by"] = by
	_note(town, "%s the %s is found and led home" % [entry["name"], str(entry["trade"]).replace("_", " ")])
	sought_changed.emit(town, id)
	return true


## Sought [param id] lost on the way (left, or downed and not roused, by
## npc's word): back to unplaced, tried again after rules'
## sought.restock_days, somewhere else. False for no such entry.
func sought_lost(id: String) -> bool:
	var entry := sought_entry(id)
	if entry.is_empty():
		return false
	var town := str(entry["town"])
	_unhold(town, id)
	var kept: Dictionary = _town(town)["sought"][id]
	kept["place"] = ""
	kept["where"] = ""
	kept["holder"] = ""
	kept["freed_by"] = ""
	kept["next_try"] = now() + int(float(rules.get("sought", {}).get("restock_days", 5)) * maxi(DayNight.day_steps, 1))
	_note(town, "%s the %s was lost on the way" % [entry["name"], str(entry["trade"]).replace("_", " ")])
	sought_changed.emit(town, id)
	return true


## Sought [param id] reached their town (npc's came_home): a resident of
## their trade from now, at work if the town has the building, rescue
## experience, the rescued signal with by "sought:<place>", and what their
## trade brings (the shepherd's flock). Also how a camp's fall brings a
## held one (note_rescue). False for no such entry.
func sought_home(id: String) -> bool:
	var entry := sought_entry(id)
	if entry.is_empty():
		return false
	var town := str(entry["town"])
	var record := _town(town)
	_unhold(town, id)
	record["sought"].erase(id)
	production.set_away(id, false)
	if id not in record["residents"]:
		record["residents"].append(id)
	_note(town, "%s the %s, found %s, comes home to %s" % [entry["name"], str(entry["trade"]).replace("_", " "), where_words(str(entry["where"])), town])
	add_xp(town, int(rules.get("xp", {}).get("rescue", 10)), "%s found" % entry["name"])
	_seat(town)
	_arrived(town, str(entry["trade"]))
	rescued.emit(town, id, "sought:%s" % entry["place"])
	sought_changed.emit(town, id)
	return true


## Sought [param id] no longer a captive held at a camp (518's path).
func _unhold(town: String, id: String) -> void:
	var record := _town(town)
	for held: Dictionary in record["captives"].duplicate():
		if held["id"] == id:
			record["captives"].erase(held)


# --- Woodcutters (decision 497) --------------------------------------------------

## Each woodcutter of [param town] (rules' woodcutter.trade, a resident in
## town and not away) every woodcutter.every steps brings wood into the
## store: wood, and per_level more for each level of a standing woodshed.
## Wood is what every building costs: without it a town builds nothing
## (npc's soak, 2026-10-18).
func _woodcut(town: String) -> void:
	var rule: Dictionary = rules.get("woodcutter", {})
	var trade := str(rule.get("trade", ""))
	if trade.is_empty():
		return
	var record := _town(town)
	var due: Dictionary = record.get("cut_due", {})
	record["cut_due"] = due
	var every := maxi(int(rule.get("every", 3000)), 1)
	var shed := building(town, "woodshed")
	var levels := int(shed.get("level", 0)) if shed.get("state") in [STANDING, BUILDING] else 0
	for who in residents(town):
		var worker := production.worker(who)
		if worker.is_empty() or trade not in worker.get("trades", []) or Production.off_work(worker):
			continue
		if not due.has(who):
			due[who] = now() + every
			continue
		if now() < int(due[who]):
			continue
		# At the town's woodlot, if it has one (decision 521).
		var trip := production.site_turn(town, who, trade)
		if trip == Production.WALKING:
			continue
		if trip == Production.NO_SITE and production.outside(who):
			continue
		due[who] = now() + every
		if trip == Production.BLOCKED:
			continue
		var wood := int(rule.get("wood", 2)) + int(rule.get("per_level", 1)) * levels
		var site := production.site_of(town, trade)
		if fell.is_valid() and not site.is_empty():
			wood = _felled(town, site, wood, worker)
		production.deliver_to(town, who, "wood", wood, "woodcutter:%s" % who, "%s's cutting" % worker["name"])


## The wood a cut at [param site] brings once the forest is real (591,
## economy's side; Held's growth): the trees maps' fell takes at the lot's
## edge nearest the town, woodcutter.wood_per_tree each, for the
## [param wood] a cut would bring. A lot cut bare brings
## woodcutter.deadwood, never none, so the town never starves of wood while
## the lot steps out and the forest regrows; the log says so, and says when
## the walk to the lot grows.
func _felled(town: String, site: Dictionary, wood: int, worker: Dictionary) -> int:
	var rule: Dictionary = rules.get("woodcutter", {})
	var per_tree := maxi(int(rule.get("wood_per_tree", 2)), 1)
	var trees := int(fell.call(town, str(site.get("id", "")), ceili(float(wood) / per_tree)))
	var record := _town(town)
	var walk := production.site_walk(town, site)
	if walk > int(record.get("lot_walk", walk)):
		_note(town, "the woodlot has moved out: %s walks %d steps there and back now" % [worker["name"], walk])
	record["lot_walk"] = walk
	if trees > 0:
		record.erase("lot_bare")
		return trees * per_tree
	if not bool(record.get("lot_bare", false)):
		_note(town, "the woodlot is cut bare: %s brings deadwood till it moves on or grows back" % worker["name"])
	record["lot_bare"] = true
	return int(rule.get("deadwood", 1))


## The fisherman at the river (594; Jeff: "town can have fisherman that go
## to river and back with fish"): every fisherman.every steps he walks to
## the town's fishing place on the bank and back (Production.site_turn, as
## the woodcutter) and brings fisherman.catch fish, the season's scale of
## it, into the store at its price. A bank the town doesn't hold yields
## nothing; no fishing place, no fishing.
func _fish(town: String) -> void:
	var rule: Dictionary = rules.get("fisherman", {})
	var trade := str(rule.get("trade", ""))
	if trade.is_empty() or production.site_of(town, trade).is_empty():
		return
	var record := _town(town)
	var due: Dictionary = record.get("fish_due", {})
	record["fish_due"] = due
	var every := maxi(int(rule.get("every", 3000)), 1)
	for who in residents(town):
		var worker := production.worker(who)
		if worker.is_empty() or trade not in worker.get("trades", []) or Production.off_work(worker):
			continue
		if not due.has(who):
			due[who] = now() + every
			continue
		if now() < int(due[who]):
			continue
		var trip := production.site_turn(town, who, trade)
		if trip == Production.WALKING:
			continue
		due[who] = now() + every
		if trip != Production.BACK:
			continue
		var fish := floori(int(rule.get("catch", 2)) * season_scale())
		if fish > 0:
			production.deliver_to(town, who, "fish", fish, "fisherman:%s" % who, "%s's catch" % worker["name"])


## A town that holds a fishing place on its river's bank and has reached
## fisherman.stage gets a fisherman, a newcomer, once it has waited
## fisherman.growth_days (594).
func _fisherman_comes(town: String) -> void:
	var rule: Dictionary = rules.get("fisherman", {})
	var trade := str(rule.get("trade", "fisherman"))
	var stages: Array = rules.get("stages", []).map(func(each: Variant) -> String: return str(each.get("name", "")) if each is Dictionary else "")
	var wanted: bool = not rule.is_empty() and not production.site_of(town, trade).is_empty() \
			and stages.find(stage(town)) >= stages.find(str(rule.get("stage", "")))
	_comes(town, trade, wanted, float(rule.get("growth_days", 3)), rule.get("names", ["Finn"]), "fisherman")


## Whether [param town] has reached stage [param name] of rules' "stages"
## (or one past it); "" or a name not among them is reached by any town.
func reached(town: String, name: String) -> bool:
	var names: Array = rules.get("stages", []).map(func(each: Variant) -> String: return str(each.get("name", "")) if each is Dictionary else "")
	return name.is_empty() or name not in names or names.find(stage(town)) >= names.find(name)


## Whether [param town] pays its [param trade] official yet (652, the
## coordinator's ruling: "the officials come with the stages"; a
## settlement has none, the guard with the hamlet, the priest with the
## village, the lawspeaker with the town): rules' official.<trade>.stage
## reached (Production.official_paid).
func official_paid(town: String, trade: String) -> bool:
	return reached(town, str(rules.get("official", {}).get(trade, {}).get("stage", "")))


## [param town]'s stage toward a city (591, economy's side): the name of the
## highest of rules' "stages" it has reached, "" for none. Raised by
## _stage_turn, one step at a time; lowered by _decline (649).
func stage(town: String) -> String:
	return str(_towns.get(town, {}).get("stage", ""))


## Raises [param town] to the next of rules' "stages" when it meets all of
## that stage's needs: residents, standing kinds, trades counted among its
## residents, gold in the treasury, wood in the store; after a fall, only
## once it has settled (649 amended (3)). Logged.
func _stage_turn(town: String) -> void:
	var stages: Array = rules.get("stages", [])
	var record := _town(town)
	var names: Array = stages.map(func(each: Variant) -> String: return str(each.get("name", "")) if each is Dictionary else "")
	var at := names.find(stage(town))
	if at + 1 >= stages.size() or not stages[at + 1] is Dictionary or not _meets(town, stages[at + 1]):
		return
	# A town that fell rises only after decline.rise_after_days calm days in a
	# row (649 amended (3), the coordinator's: no fall and rise ticks apart).
	if record.has("settling") and int(record["settling"]) < int(rules.get("decline", {}).get("rise_after_days", 0)):
		return
	record.erase("settling")
	record["stage"] = names[at + 1]
	_note(town, "%s is a %s now" % [town, names[at + 1]])
	stage_changed.emit(town)


# --- Decline (649: towns fall as well as rise) ----------------------------------------

## Once a day: each building's keep (_upkeep_turn, _neglect_turn), then the
## town's strain toward falling a stage (_strain_turn). rules' "decline".
func _decline(town: String) -> void:
	var rule: Dictionary = rules.get("decline", {})
	if rule.is_empty():
		return
	var record := _town(town)
	var day := now() / maxi(DayNight.day_steps, 1)
	if record.has("decline_day") and int(record["decline_day"]) >= day:
		return
	record["decline_day"] = day
	_upkeep_turn(town, rule, day)
	_neglect_turn(town, rule, day)
	_strain_turn(town, rule)


## Each decline.upkeep.every days (the first that many after the town is
## first seen, so a fresh world pays nothing before its first gathering) a
## building in use or out of it pays its keep from the store (a kind's own "upkeep", else decline.upkeep.cost,
## times its level; {} for none: a camp wants none, 649), the nearest to
## the store first, so the edge goes short first: one that can't is
## "owed" from that day till it pays.
func _upkeep_turn(town: String, rule: Dictionary, day: int) -> void:
	var upkeep: Dictionary = rule.get("upkeep", {})
	var record := _town(town)
	var every := maxi(int(upkeep.get("every", 7)), 1)
	if not record.has("upkeep_day"):
		record["upkeep_day"] = day + every
	if day < int(record["upkeep_day"]):
		return
	record["upkeep_day"] = day + every
	var houses: Dictionary = record["buildings"]
	var kinds: Dictionary = rules.get("buildings", {})
	for kind: String in _inner_first(town):
		var entry: Dictionary = houses[kind]
		if not entry["state"] in [STANDING, DAMAGED, DISREPAIR] or int(entry["level"]) < 1:
			continue
		var cost: Dictionary = kinds.get(kind, {}).get("upkeep", upkeep.get("cost", {}))
		var paid := true
		for what: String in cost:
			if production.stockpile.count(town, what) < int(cost[what]) * int(entry["level"]):
				paid = false
		if paid:
			for what: String in cost:
				if int(cost[what]) > 0:
					production.stockpile.take(town, what, int(cost[what]) * int(entry["level"]), "the %s's upkeep" % kind)
			entry.erase("owed")
		elif not entry.has("owed"):
			entry["owed"] = day


## A round of [param town]'s upkeep (649; Production.keep_for, kept back
## from a new build): each building in use or out of it, its cost times its
## level; {} without decline.
func upkeep_due(town: String) -> Dictionary:
	var upkeep: Dictionary = rules.get("decline", {}).get("upkeep", {})
	var kinds: Dictionary = rules.get("buildings", {})
	var out := {}
	if upkeep.is_empty():
		return out
	var houses: Dictionary = _towns.get(town, {}).get("buildings", {})
	for kind: String in houses:
		var entry: Dictionary = houses[kind]
		if not entry["state"] in [STANDING, DAMAGED, DISREPAIR] or int(entry["level"]) < 1:
			continue
		var cost: Dictionary = kinds.get(kind, {}).get("upkeep", upkeep.get("cost", {}))
		for what: String in cost:
			out[what] = int(out.get(what, 0)) + int(cost[what]) * int(entry["level"])
	return out


## [param town]'s building kinds, the nearest its store first (placed's
## distance; unknown ones nearest), then by name.
func _inner_first(town: String) -> Array[String]:
	var out: Array[String] = []
	out.assign(_town(town)["buildings"].keys())
	var far := {}
	for kind in out:
		far[kind] = float(placed.call(town, kind).get("distance", 0.0)) if placed.is_valid() else 0.0
	out.sort_custom(func(a: String, b: String) -> bool: return far[a] < far[b] or far[a] == far[b] and a < b)
	return out


## A building neglected (its keep owed, damaged, or none of its trade among
## the residents) decline.unkept_days days running falls into disrepair: out
## of use (not standing; repaired as a damaged one is). In disrepair it
## loses a level each season (Season.season_days), and at none it is a
## ruin; a ruin is kept a season, then its record goes and ruined is told.
func _neglect_turn(town: String, rule: Dictionary, day: int) -> void:
	var record := _town(town)
	var houses: Dictionary = record["buildings"]
	var kinds: Dictionary = rules.get("buildings", {})
	var season := maxi(Season.season_days, 1)
	var trades := {}
	for who: String in record["residents"]:
		for trade: Variant in production.worker(who).get("trades", []):
			trades[str(trade)] = true
	var names: Array = houses.keys()
	names.sort()
	for kind: String in names:
		var entry: Dictionary = houses[kind]
		if entry["state"] == RUIN:
			if day - int(entry.get("ruin", day)) >= season:
				var where: Dictionary = placed.call(town, kind) if placed.is_valid() else {}
				houses.erase(kind)
				if not kind in record.get_or_add("gone", []):
					record["gone"].append(kind)  # The map's piece is not seeded again.
				_note(town, "the ruin of the %s is gone; the wild takes the ground back" % kind)
				building_changed.emit(town, kind)
				var cells: Array[Vector2i] = []
				cells.assign(where.get("cells", []))
				ruined.emit(town, kind, str(where.get("zone", "")), cells)
			continue
		if not entry["state"] in [STANDING, DAMAGED, DISREPAIR] or int(entry["level"]) < 1:
			continue
		if entry["state"] == DISREPAIR:
			if int(entry["job"]) != 0 or day - int(entry.get("decay", day)) < season:
				continue
			entry["decay"] = day
			entry["level"] = int(entry["level"]) - 1
			if int(entry["level"]) <= 0:
				entry["state"] = RUIN
				entry["ruin"] = day
				entry.erase("decay")
				_note(town, "the %s is a ruin" % kind)
			else:
				_note(town, "the %s, in disrepair, is down to level %d" % [kind, entry["level"]])
			building_changed.emit(town, kind)
			continue
		var trade := str(kinds.get(kind, {}).get("trade", ""))
		var neglected: bool = entry.has("owed") or entry["state"] == DAMAGED or not trade.is_empty() and not trades.has(trade)
		if not neglected:
			entry.erase("neglect")
			continue
		if not entry.has("neglect"):
			entry["neglect"] = day
		if day - int(entry["neglect"]) >= int(rule.get("unkept_days", 14)) and int(entry["job"]) == 0:
			entry["state"] = DISREPAIR
			entry["decay"] = day
			entry.erase("neglect")
			_note(town, "the %s has fallen into disrepair" % kind)
			building_changed.emit(town, kind)


## A day's strain on [param town] (649, Jeff's list: the people fall, the
## resources can't keep up, raids and captives): its stage short of the
## residents it needs, a standing kind it needs out of use (disrepair, a
## ruin), or more than decline.hungry_share of its residents hungry with
## the store unable to feed them adds a day; a day with none takes one off. At decline.strain_days it falls a
## stage (never below the first) and starts again.
func _strain_turn(town: String, rule: Dictionary) -> void:
	var record := _town(town)
	var stages: Array = rules.get("stages", [])
	var names: Array = stages.map(func(each: Variant) -> String: return str(each.get("name", "")) if each is Dictionary else "")
	var at := names.find(stage(town))
	# After a fall, its calm days in a row toward rising again (649 amended (3)).
	if record.has("settling"):
		var calm: bool = at < 0 or not stages[at] is Dictionary or _falling(town, stages[at], rule).is_empty()
		record["settling"] = int(record["settling"]) + 1 if calm else 0
	if at <= 0 or not stages[at] is Dictionary:
		record.erase("strain")
		record.erase("falling")
		return
	var why := _falling(town, stages[at], rule)
	if why.is_empty():
		record["strain"] = maxi(int(record.get("strain", 0)) - 1, 0)
		if int(record["strain"]) == 0:
			record.erase("falling")
		return
	record["falling"] = why
	record["strain"] = int(record.get("strain", 0)) + 1
	if int(record["strain"]) < int(rule.get("strain_days", 10)):
		return
	record["stage"] = names[at - 1]
	record["strain"] = 0
	record["settling"] = 0
	_note(town, "%s falls back to a %s: %s" % [town, names[at - 1], why])
	stage_changed.emit(town)


## What strains [param town] at stage [param need] today, "" for nothing:
## the first of too few residents, a needed kind out of use, hunger the
## store can't feed (the hungry more than its food, meat and fish: hunger
## with food in the store is a purse's, not the town's). A needed kind
## never built doesn't count: a stage is
## lost for what goes, not for a need added after it was reached.
func _falling(town: String, need: Dictionary, rule: Dictionary) -> String:
	var people := residents(town)
	if people.size() < int(need.get("residents", 0)):
		return "too few people (%d of %d)" % [people.size(), int(need["residents"])]
	for kind: Variant in need.get("standing", []):
		if building(town, str(kind)).get("state") in [DISREPAIR, RUIN]:
			return "the %s out of use" % kind
	var hungry := 0
	for who in people:
		var worker := production.worker(who)
		if str(worker.get("fed", "")) == "hungry" and not bool(worker.get("away", false)):
			hungry += 1
	var food := 0
	for what: String in ["food", "meat", "fish"]:
		food += production.stockpile.count(town, what)
	if not people.is_empty() and hungry > float(rule.get("hungry_share", 0.5)) * people.size() and hungry > food:
		return "hunger"
	return ""


## A resident carried off adds decline.captive_strain days of strain (649).
func _captive_strain(record: Dictionary) -> void:
	var add := int(rules.get("decline", {}).get("captive_strain", 0))
	if add > 0 and not str(record.get("stage", "")).is_empty():
		record["strain"] = int(record.get("strain", 0)) + add


## [param town]'s strain toward falling (the town sheet, 649): {days, of,
## why}; days 0 and why "" when nothing strains it. Since a fall, also
## settling: {days (calm in a row), of (decline.rise_after_days)} till it
## rises again (649 amended (3)).
func strain(town: String) -> Dictionary:
	var record: Dictionary = _towns.get(town, {})
	var out := {"days": int(record.get("strain", 0)), "of": int(rules.get("decline", {}).get("strain_days", 10)), "why": str(record.get("falling", ""))}
	if record.has("settling"):  # Since a fall: calm days toward rising again (649 amended (3)).
		out["settling"] = {"days": int(record["settling"]), "of": int(rules.get("decline", {}).get("rise_after_days", 0))}
	return out


## Whether [param town] has what a recipe's made.needs asks (622, economy's
## side; Production.town_has): its building [param needs] kind standing,
## and the town at or past its stage (rules' "stages" order).
func has_for_make(town: String, needs: Dictionary) -> bool:
	var names: Array = rules.get("stages", []).map(func(each: Variant) -> String: return str(each.get("name", "")) if each is Dictionary else "")
	var wanted := names.find(str(needs.get("stage", "")))
	return _stands(town, str(needs.get("kind", ""))) and (str(needs.get("stage", "")).is_empty() or wanted >= 0 and names.find(stage(town)) >= wanted)


## Whether [param town] meets stage [param need]'s needs.
func _meets(town: String, need: Dictionary) -> bool:
	return stage_short(town, need).is_empty()


## What [param town] lacks of stage [param need]'s needs: [{what, have,
## need}], what "residents", a standing kind, a trade, "gold" or "wood"
## (have and need counts, a kind's 0 or 1), in the rule's order.
func stage_short(town: String, need: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var people := residents(town)
	if people.size() < int(need.get("residents", 0)):
		out.append({"what": "residents", "have": people.size(), "need": int(need["residents"])})
	for kind: Variant in need.get("standing", []):
		if not _stands(town, str(kind)):
			out.append({"what": str(kind), "have": 0, "need": 1})
	var trades: Variant = need.get("trades", {})
	if trades is Dictionary:
		for trade: String in trades:
			var have := people.filter(func(who: String) -> bool: return trade in production.worker(who).get("trades", [])).size()
			if have < int(trades[trade]):
				out.append({"what": trade, "have": have, "need": int(trades[trade])})
	for what: String in ["gold", "wood"]:
		var have := production.stockpile.count(town, what)
		if have < int(need.get(what, 0)):
			out.append({"what": what, "have": have, "need": int(need[what])})
	return out


## [param town]'s next stage and what it lacks of it (the town sheet, 624):
## {stage, needs: stage_short}; {} at the last stage.
func next_stage(town: String) -> Dictionary:
	var stages: Array = rules.get("stages", [])
	var names: Array = stages.map(func(each: Variant) -> String: return str(each.get("name", "")) if each is Dictionary else "")
	var at := names.find(stage(town))
	if at + 1 >= stages.size() or not stages[at + 1] is Dictionary:
		return {}
	return {"stage": names[at + 1], "needs": stage_short(town, stages[at + 1])}


## A town with a building waiting on wood and no woodcutter gets one, a
## newcomer, once it has waited woodcutter.growth_days (a rescue may bring
## one first), as a field gets its farmer (449).
func _woodcutter_comes(town: String) -> void:
	var rule: Dictionary = rules.get("woodcutter", {})
	var trade := str(rule.get("trade", ""))
	var record := _town(town)
	var short := false
	for kind: String in record["buildings"]:
		var house: Dictionary = record["buildings"][kind]
		var job := production.job(int(house.get("job", 0))) if int(house.get("job", 0)) != 0 else {}
		if house.get("state") == PLANNED and int(job.get("cost", {}).get("wood", 0)) > production.stockpile.count(town, "wood"):
			short = true
	if trade.is_empty() or not short or _has_trade(town, trade):
		record.erase("woodcutter_wanted")
		return
	var waiting_since := int(record.get("woodcutter_wanted", -1))
	if waiting_since < 0:
		record["woodcutter_wanted"] = now()
		return
	if now() - waiting_since < int(float(rule.get("growth_days", 2)) * maxi(DayNight.day_steps, 1)):
		return
	var count := int(record.get("woodcutters_came", 0)) + 1
	record["woodcutters_came"] = count
	record.erase("woodcutter_wanted")
	var names: Array = rule.get("names", ["Bran"])
	var name := _free_name(town, names, absi(hash("%s/wood/%d" % [town, count])))
	var id := "woodcutter_%s_%d" % [town.replace("/", "_"), count]
	_arrive(town, id, name, trade, "%s the woodcutter comes: the town has building to do and no wood" % name)


# --- Wells and roofs (decision 426) -------------------------------------------------

## [param town]'s water now ({} with no well: nothing of this applies).
func water(town: String) -> float:
	return float(_towns.get(town, {}).get("water", 0.0))


## Whether [param town]'s wells are dry (it has some, and no water).
func dry(town: String) -> bool:
	return bool(_towns.get(town, {}).get("dry", false))


## [param town]'s water moved on to now: each well's spring a day and its
## catch of the rain that fell, up to cap a well; its residents' draw a
## day each. Dry and wet again said once each in the log.
func _water(town: String) -> void:
	var count := int(wells.call(town)) if wells.is_valid() else 0
	if count <= 0:
		return
	var rule: Dictionary = rules.get("water", {})
	var record := _town(town)
	var at := now()
	if not record.has("water_at"):
		record["water"] = float(rule.get("cap", 30)) * count
		record["water_at"] = at
		record["dry"] = false
		return
	var days := float(at - int(record["water_at"])) / maxi(DayNight.day_steps, 1)
	if days <= 0.0:
		return
	var fell := float(rain.call(town, float(record["water_at"]), float(at))) if rain.is_valid() else 0.0
	record["water_at"] = at
	var gained := (float(rule.get("spring", 4)) * days + float(rule.get("catch", 12)) * fell) * count
	var drawn := float(rule.get("draw", 1)) * days * residents(town).size()
	record["water"] = clampf(float(record["water"]) + gained - drawn, 0.0, float(rule.get("cap", 30)) * count)
	var now_dry := float(record["water"]) <= 0.0
	if now_dry != bool(record["dry"]):
		record["dry"] = now_dry
		_note(town, "the well is dry" if now_dry else "the well has water again")


## Production.work_rate: rules' water dry_slows trade (the cook) works at
## dry_rate while its town is dry. PROVISIONAL (decision 426): Jeff's to
## confirm what a dry well does.
func _work_rate(shop: Dictionary) -> float:
	var rule: Dictionary = rules.get("water", {})
	if str(shop.get("trade", "")) == str(rule.get("dry_slows", "")) and dry(str(shop.get("town", ""))):
		return float(rule.get("dry_rate", 0.5))
	return 1.0


## Orders the mending of [param town]'s first damaged roof, if no other
## is open: a build job by rules' roof.by, priced in wood by its size.
## True if it did.
func _roof(town: String) -> bool:
	if not roofs.is_valid():
		return false
	var rule: Dictionary = rules.get("roof", {})
	for roof: Dictionary in roofs.call(town):
		var wood := int(rule.get("wood_base", 1)) + int(int(roof.get("cells", 0)) / maxi(int(rule.get("wood_cells", 8)), 1))
		production.order_build(town, ROOF + str(roof["index"]), str(rule.get("by", "carpenter")), {"wood": wood}, int(rule.get("steps", 1200)))
		_note(town, "a roof broken by the storm is to be mended (%d wood)" % wood)
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


## Why resident [param worker_id] of [param town] can't be spared to follow
## a player (companions' recruiting, the coordinator's): "the only <trade>"
## when they are its only resident not away of a trade it needs (a standing
## or building kind's trade, one its stage counts, a build's while one is
## open); "" when they can go.
func sole_needed(town: String, worker_id: String) -> String:
	var who := production.worker(worker_id)
	if who.is_empty() or worker_id not in residents(town):
		return ""
	var needed := {}
	var kinds: Dictionary = rules.get("buildings", {})
	for kind: String in kinds:
		var trade := str(kinds[kind].get("trade", "")) if kinds[kind] is Dictionary else ""
		if not trade.is_empty() and building(town, kind).get("state") in [STANDING, BUILDING]:
			needed[trade] = true
	for each: Variant in rules.get("stages", []):
		if each is Dictionary and str(each.get("name", "")) == stage(town):
			for trade: String in each.get("trades", {}):
				needed[trade] = true
	for id in production.jobs():
		var job := production.job(id)
		if job["kind"] == "build" and job["town"] == town and not str(job.get("trade", "")).is_empty():
			needed[str(job["trade"])] = true
	var trades: Array = who.get("trades", [])
	for trade: String in trades:
		if not needed.has(trade):
			continue
		var others := residents(town).filter(func(other: String) -> bool:
			var them := production.worker(other)
			return other != worker_id and not them.is_empty() and trade in them.get("trades", []) and not bool(them.get("away", false)))
		if others.is_empty():
			return "the only %s" % trade.replace("_", " ")
	return ""


## [param town]'s defence against a raid now: its walls (standing, by
## level) and its residents in town, at rules' raids defence.
func defence(town: String) -> float:
	var per: Dictionary = rules.get("raids", {}).get("defence", {})
	var walls := building(town, "walls")
	var levels := int(walls.get("level", 0)) if walls.get("state") in [STANDING, BUILDING] else 0
	var present := residents(town).filter(func(who: String) -> bool:
		return not production.worker(who).is_empty() and not Production.off_work(production.worker(who))).size()
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
		_note(town, "%s, a companion, is held by %s (%s)" % [her_name, faction_name(faction), group_id])
		out.append(who)
	return out


## A raiding [param group] ({id, faction, strength, from}: its strength
## after anything done to it on the way) has reached [param town]'s ground,
## travelled there or walked there in play, alike. Its strength less the
## town's defence is what gets past (margin); none, and it is fought off.
## Else it takes rules' raids takes in order (a group's "want" in rules'
## raids wants, decision 409: a hungry camp's "food" its own takes and no
## captives), each scaled by margin /
## strength (only food, the hunt's meat with it, decision 405: never gold,
## materials, experience or buildings),
## damages one building past damage.margin and carries off up to
## captives.count residents (the newest first; a companion by her player's
## id, "companion:<player id>", Main told: companion_taken) past
## captives.margin, only when the town is not in play (in play the
## raiders' blows take people: resident_taken). The report, also emitted on raided: {town, group,
## faction, repelled, margin, want (the group's, if the rules know it),
## took: {resource: count, items: [uids]},
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
		_note(town, "a raid by %s (%.1f) is fought off (defence %.1f)" % [faction_name(faction), strength, defence(town)])
		raided.emit(town, report)
		return report
	var scale := clampf(margin / strength, 0.0, 1.0)
	var stock := production.stockpile
	var book := production.book()
	# What the group came for (maps' hungry camps: "food"): its own takes,
	# and captives or not; unknown or "", the raid as ever.
	var wanting: Dictionary = raids.get("wants", {}).get(str(group.get("want", "")), {})
	report["want"] = str(group.get("want", "")) if not wanting.is_empty() else ""
	for take: Variant in wanting.get("takes", raids.get("takes", [])):
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
	if margin >= float(taking.get("margin", INF)) and not (in_play.is_valid() and in_play.call(town)) 			and bool(wanting.get("captives", true)):
		var record := _town(town)
		var people: Array = record["residents"].duplicate()
		people.reverse()
		for who: String in people:
			if report["captives"].size() >= int(taking.get("count", 0)):
				break
			var worker := production.worker(who)
			if worker.is_empty() or Production.off_work(worker):
				continue
			# A companion only by her player's id (decision 331).
			if who.begins_with("companion:") and not _take_companion(town, who, faction, group_id):
				continue
			if not who.begins_with("companion:"):
				_take(town, who, faction, group_id)
			var taken: Dictionary = record["captives"].back()
			report["captives"].append({"id": taken["id"], "name": taken["name"], "trade": taken["trade"]})
	_note(town, "a raid by %s (%.1f against %.1f) took %s%s%s" % [faction_name(faction), strength, strength - margin,
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
	var taker := faction if not faction.is_empty() else str(rules.get("raids", {}).get("raiders", "raiders"))
	_take(town, who, taker, by)
	_note(town, "%s is beaten down and carried off by %s (%s)" % [production.worker(who)["name"], faction_name(taker), by])
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
	_captive_strain(record)


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
	_captive_strain(record)
	if companion_taken.is_valid():
		companion_taken.call(origin.trim_prefix("companion:"), by)
	return true


## A hunter came home (Production.hunted, decision 407): the town log says
## what with, or that there was no game, the first time only after a catch
## (most tries in a day find the day's game taken: npc's soak, 484 lines a
## month).
func _on_hunted(town: String, who: String, kind: String) -> void:
	var name := str(production.worker(who).get("name", who))
	var missed: Dictionary = _town(town).get("hunter_missed", {})
	_town(town)["hunter_missed"] = missed
	if kind.is_empty():
		if not missed.has(who):
			missed[who] = true
			_note(town, "%s the hunter found no game" % name)
		return
	missed.erase(who)
	_note(town, "%s the hunter brought home a %s" % [name, kind])


## Faction [param id] as the town's log names it (Factions.display_name:
## "the Blood Rot"); the id itself with no holdings (tests). Records keep
## the id.
func faction_name(id: String) -> String:
	if production.holdings != null and production.holdings.factions != null:
		return production.holdings.factions.display_name(id)
	return id


## How many of a town's dead it remembers by name (552 amended).
const DEAD_NAMES := 40


## A newcomer's name for [param town] from [param names], [param pick]
## first (552 amended, the two Bryns): the first from there on that no
## resident, captive or remembered dead of the town already has; [param
## pick]'s own when every one is taken.
func _free_name(town: String, names: Array, pick: int) -> String:
	var record := _town(town)
	var used := {}
	for who: String in record["residents"]:
		used[str(production.worker(who).get("name", ""))] = true
	for each: Dictionary in record["captives"]:
		used[str(each.get("name", ""))] = true
	for each: Dictionary in record.get("sought", {}).values():
		used[str(each.get("name", ""))] = true
	for name: Variant in record.get("dead_names", []):
		used[str(name)] = true
	for i in names.size():
		var name := str(names[(pick + i) % names.size()])
		if not used.has(name):
			return name
	return str(names[pick % names.size()])


func _seated(who: String) -> bool:
	return production.workshop_of(who) != ""


# --- Visitors (decision 711) -----------------------------------------------------------

## [param town]'s visitors (711; Jeff: strangers come and go, the town never
## grows by them): [{id, kind, name, from, came, leaves (steps), stock (item
## id -> count, a pedlar's), news (npc's, set_visitor_news)}]. Never
## residents: no worker, no rent, no needs, not counted for a stage.
func visitors(town: String) -> Array:
	return (_towns.get(town, {}).get("visitors", []) as Array).duplicate(true)


## npc's news for visitor [param id] of [param town], set once as they come.
func set_visitor_news(town: String, id: String, news: Array) -> void:
	for entry: Dictionary in _towns.get(town, {}).get("visitors", []):
		if str(entry["id"]) == id:
			entry["news"] = news.duplicate(true)


## Player [param player_id] buys one [param item] from pedlar [param
## visitor_id] (711): {ok, say, gold (paid)}; the gold through
## visitor_sale, one off the pedlar's stock.
func visitor_sell(visitor_id: String, player_id: String, item: String) -> Dictionary:
	for town: String in _towns:
		for entry: Dictionary in _towns[town].get("visitors", []):
			if str(entry["id"]) != visitor_id:
				continue
			var stock: Dictionary = entry.get("stock", {})
			if int(stock.get(item, 0)) <= 0:
				return {"ok": false, "say": "I've none of that left.", "gold": 0}
			if not visitor_sale.is_valid():
				return {"ok": false, "say": "Not today.", "gold": 0}
			var done: Dictionary = visitor_sale.call(town, entry, player_id, item)
			if bool(done.get("ok", false)):
				stock[item] = int(stock[item]) - 1
				if int(stock[item]) <= 0:
					stock.erase(item)
			return done
	return {"ok": false, "say": "", "gold": 0}


## [param town]'s visitors' day (711): those whose time is up go on; then
## once a day, with fewer than rules' visitors.most and people of its own,
## one comes at visitors.chance: a kind drawn by weight among those whose
## "needs" building stands, staying visitors.days (a range) days, a
## pedlar's wares drawn from the lines no trade of the town's makes (each
## line's "unless").
func _visitors_turn(town: String) -> void:
	var rule: Dictionary = rules.get("visitors", {})
	if rule.is_empty():
		return
	var record := _town(town)
	var here: Array = record.get("visitors", [])
	for entry: Dictionary in here.duplicate():
		if now() >= int(entry["leaves"]):
			here.erase(entry)
			_note(town, "%s the %s goes on from %s" % [entry["name"], entry["kind"], town])
			visitor_left.emit(town, str(entry["id"]))
	var day := now() / maxi(DayNight.day_steps, 1)
	if int(record.get("visitor_day", -1)) == day:
		return
	record["visitor_day"] = day
	if here.size() >= int(rule.get("most", 2)) or residents(town).is_empty():
		return
	var draw := RandomNumberGenerator.new()
	draw.seed = hash("%s/visitor/%d" % [town, day])
	if draw.randf() >= float(rule.get("chance", 0.35)):
		return
	var kinds: Dictionary = rule.get("kinds", {})
	var open: Array[String] = []
	var total := 0.0
	for kind: String in kinds:
		var needs := str(kinds[kind].get("needs", ""))
		if needs.is_empty() or _stands(town, needs):
			open.append(kind)
			total += float(kinds[kind].get("weight", 1))
	if open.is_empty() or total <= 0.0:
		return
	open.sort()
	var roll := draw.randf() * total
	var kind := open[-1]
	for each in open:
		roll -= float(kinds[each].get("weight", 1))
		if roll < 0.0:
			kind = each
			break
	var kind_rule: Dictionary = kinds[kind]
	var names: Array = kind_rule.get("names", ["A stranger"])
	var places: Array = visitor_from.call(town) if visitor_from.is_valid() else []
	var days: Array = rule.get("days", [1, 3])
	var count := int(record.get("visitors_made", 0)) + 1
	record["visitors_made"] = count
	var entry := {"id": "visitor_%s_%d" % [town.replace("/", "_"), count], "kind": kind,
		"name": str(names[draw.randi_range(0, names.size() - 1)]),
		"from": str(places[draw.randi_range(0, places.size() - 1)]) if not places.is_empty() else "the road",
		"came": now(), "leaves": now() + draw.randi_range(int(days[0]), int(days[-1])) * maxi(DayNight.day_steps, 1),
		"stock": {}, "news": []}
	var trades := {}
	for who in residents(town):
		for trade: Variant in production.worker(who).get("trades", []):
			trades[str(trade)] = true
	var wares: Array = (kind_rule.get("wares", []) as Array).filter(func(line: Variant) -> bool:
		return line is Dictionary and not trades.has(str(line.get("unless", ""))))
	var draws: Array = kind_rule.get("draw", [3, 5])
	for i in draw.randi_range(int(draws[0]), int(draws[-1])) if not wares.is_empty() else 0:
		var weight := 0.0
		for line: Dictionary in wares:
			weight += float(line.get("weight", 1))
		var pick := draw.randf() * weight
		for line: Dictionary in wares:
			pick -= float(line.get("weight", 1))
			if pick < 0.0:
				var item := str(line["item"])
				entry["stock"][item] = int(entry["stock"].get(item, 0)) + int(line.get("count", 1))
				break
	here.append(entry)
	record["visitors"] = here
	var did := str(visitor_arrives.call(town, entry)) if visitor_arrives.is_valid() else ""
	_note(town, "%s the %s from %s comes to %s%s" % [entry["name"], kind, entry["from"], town, ": " + did if not did.is_empty() else ""])
	visitor_came.emit(town, str(entry["id"]))


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


## The hill herders' records (640), saved beside the towns ("herders").
func herders_to_dict() -> Dictionary:
	return _herders.duplicate(true)


## herders_to_dict's [param saved] over what is here.
func herders_from_dict(saved: Dictionary) -> void:
	for id: Variant in saved:
		if saved[id] is Dictionary:
			var herd: Dictionary = saved[id]
			_herders[str(id)] = {"since": int(herd.get("since", 0)), "season": str(herd.get("season", "")),
				"lambs": float(herd.get("lambs", 0.0)), "next": int(herd.get("next", 0)), "back": int(herd.get("back", 0)),
				"unsold": maxi(int(herd.get("unsold", 0)), 0)}
			if herd.has("buyer"):
				_herders[str(id)]["buyer"] = str(herd["buyer"])


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
		if entry.has("larder"):
			record["larder"] = int(entry["larder"])
		# Its harvests in (652); a town founded before has had its first.
		record["harvests"] = maxi(int(entry.get("harvests", 1 if record["founded"] else 0)), 0)
		record["to_spread"] = maxi(int(entry.get("to_spread", 0)), 0)
		record["spent"] = clampi(int(entry.get("spent", 0)), 0, record["xp"])
		for who: Variant in entry.get("residents", []):
			if not production.worker(str(who)).is_empty():
				record["residents"].append(str(who))
		var buildings: Variant = entry.get("buildings", {})
		if buildings is Dictionary:
			for kind: String in buildings:
				var house: Variant = buildings[kind]
				if house is Dictionary and str(house.get("state", "")) in [PLANNED, BUILDING, STANDING, DAMAGED, DISREPAIR, RUIN]:
					record["buildings"][kind] = {"kind": kind, "level": maxi(int(house.get("level", 0)), 0),
						"state": str(house["state"]), "since": int(house.get("since", 0)), "job": int(house.get("job", 0))}
					for day_key: String in ["owed", "neglect", "decay", "ruin"]:  # Its keep (649).
						if house.has(day_key):
							record["buildings"][kind][day_key] = int(house[day_key])
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
		var held_at: Variant = entry.get("strangers", {})
		if held_at is Dictionary:
			for camp: Variant in held_at:
				if held_at[camp] is Array:
					record["strangers"] = record.get("strangers", {})
					record["strangers"][str(camp)] = (held_at[camp] as Array).filter(func(each: Variant) -> bool:
						return each is Dictionary and str(each.get("id", "")) != "" and str(each.get("trade", "")) != "")
		# npc's memory and lawspeaker, kept as they are.
		if entry.get("memory") is Array:
			record["memory"] = (entry["memory"] as Array).duplicate(true)
		if entry.get("lawspeaker") is Dictionary:
			record["lawspeaker"] = (entry["lawspeaker"] as Dictionary).duplicate(true)
		if entry.has("stage"):
			record["stage"] = str(entry["stage"])
		for key: String in ["strain", "decline_day", "upkeep_day", "settling"]:  # Its decline (649; settling, 649 amended (3)).
			if entry.has(key):
				record[key] = int(entry[key])
		if entry.has("falling"):
			record["falling"] = str(entry["falling"])
		if entry.get("gone") is Array:
			record["gone"] = (entry["gone"] as Array).map(func(kind: Variant) -> String: return str(kind))
		if entry.has("lot_walk"):
			record["lot_walk"] = int(entry["lot_walk"])
		record["lot_bare"] = bool(entry.get("lot_bare", false))
		var held_for: Variant = entry.get("held_for", {})
		if held_for is Dictionary:
			for owner: Variant in held_for:
				var uids: Array = []
				for uid: Variant in held_for[owner] if held_for[owner] is Array else []:
					if (uid is int or uid is float) and production.book().has(int(uid)):
						uids.append(int(uid))
				if not uids.is_empty():
					record["held_for"] = record.get("held_for", {})
					record["held_for"][str(owner)] = uids
		var restock: Variant = entry.get("restock", {})
		if restock is Dictionary:
			record["restock"] = {}
			for camp: Variant in restock:
				record["restock"][str(camp)] = int(restock[camp])
		record["strangers_made"] = maxi(int(entry.get("strangers_made", 0)), 0)
		# Its visitors (711), as they are; one without an id or a kind dropped.
		if entry.get("visitors") is Array:
			record["visitors"] = (entry["visitors"] as Array).filter(func(each: Variant) -> bool:
				return each is Dictionary and str(each.get("id", "")) != "" and str(each.get("kind", "")) != "").duplicate(true)
		for key: String in ["visitors_made", "visitor_day"]:
			if entry.has(key):
				record[key] = int(entry[key])
		var sought_saved: Variant = entry.get("sought", {})
		if sought_saved is Dictionary:
			for id: Variant in sought_saved:
				var each: Variant = sought_saved[id]
				# A sought is a worker (613): one whose worker is gone is dropped.
				if each is Dictionary and not production.worker(str(id)).is_empty():
					record["sought"] = record.get("sought", {})
					record["sought"][str(id)] = {"id": str(id), "name": str(each.get("name", "")), "trade": str(each.get("trade", "")),
						"place": str(each.get("place", "")), "where": str(each.get("where", "")), "holder": str(each.get("holder", "")),
						"since": int(each.get("since", 0)), "next_try": int(each.get("next_try", 0)), "freed_by": str(each.get("freed_by", "")),
						"story": str(each.get("story", "")), "tries": maxi(int(each.get("tries", 0)), 0), "wandered": bool(each.get("wandered", false)), "door": str(each.get("door", ""))}
		# The trade's times out (613 amended: its variants in turn), the low and when one last wandered off.
		for key: String in ["sought_tries", "low"]:
			if entry.get(key) is Dictionary:
				record[key] = {}
				for each: Variant in entry[key]:
					record[key][str(each)] = int(entry[key][each])
		if entry.has("wandered_at"):
			record["wandered_at"] = int(entry["wandered_at"])
		var crop_saved: Variant = entry.get("crop", {})
		if crop_saved is Dictionary and not crop_saved.is_empty():
			record["crop"] = {"stage": str(crop_saved.get("stage", "")), "growth": maxf(float(crop_saved.get("growth", 0.0)), 0.0),
				"worked": maxi(int(crop_saved.get("worked", 0)), 0), "season": str(crop_saved.get("season", "")),
				"roots": bool(crop_saved.get("roots", false)), "at": int(crop_saved.get("at", 0)), "flattened": int(crop_saved.get("flattened", -1)),
				"look": str(crop_saved.get("look", ""))}
		if entry.has("farmer_wanted"):
			record["farmer_wanted"] = int(entry["farmer_wanted"])
		record["farmers_came"] = maxi(int(entry.get("farmers_came", 0)), 0)
		var cut_due: Variant = entry.get("cut_due", {})
		if cut_due is Dictionary:
			record["cut_due"] = {}
			for who: Variant in cut_due:
				record["cut_due"][str(who)] = int(cut_due[who])
		if entry.has("woodcutter_wanted"):
			record["woodcutter_wanted"] = int(entry["woodcutter_wanted"])
		record["woodcutters_came"] = maxi(int(entry.get("woodcutters_came", 0)), 0)
		var flock_saved: Variant = entry.get("flock", {})
		if flock_saved is Dictionary and not flock_saved.is_empty():
			record["flock"] = {"count": maxf(float(flock_saved.get("count", 0.0)), 0.0), "season": str(flock_saved.get("season", "")),
				"sheared": bool(flock_saved.get("sheared", false)), "worked": maxi(int(flock_saved.get("worked", 0)), 0), "at": int(flock_saved.get("at", 0))}
		if entry.has("butcher_at"):
			record["butcher_at"] = int(entry["butcher_at"])
			record["butcher_worked"] = maxi(int(entry.get("butcher_worked", 0)), 0)
		if entry.get("fish_due") is Dictionary:
			record["fish_due"] = {}
			for who: Variant in entry["fish_due"]:
				record["fish_due"][str(who)] = int(entry["fish_due"][who])
		for key: String in ["shepherd", "weaver", "butcher", "fisherman"]:
			if entry.has("%s_wanted" % key):
				record["%s_wanted" % key] = int(entry["%s_wanted" % key])
			record["%ss_came" % key] = maxi(int(entry.get("%ss_came" % key, 0)), 0)
		if entry.has("water_at"):
			record["water"] = maxf(float(entry.get("water", 0.0)), 0.0)
			record["water_at"] = int(entry["water_at"])
			record["dry"] = bool(entry.get("dry", false))
