class_name Production
extends RefCounted
## The town's work (economy, step 3): workers, workshops and jobs, run on
## the world tick (World.world_tick, slice 0) and timed in World.steps, so
## they wait while the server is down and go on while players are away.
##
## A worker is a record (a placeholder until rescued people and town NPCs
## fill them): a trade or two, a town (a stockpile place id) and a purse.
## A workshop is a record too: a trade, a town and the worker in it. A job
## takes its materials from the town's stockpile when it starts (so two jobs
## can't count on the same ore), is worked while its worker is at its
## workshop, and when done puts what it made (a new instance, "made") or
## reworked (the same instance, "reworked") in the town's shop. A cancelled
## job gives its materials back.
##
## Nobody orders the work (Production.order is for tests and the console):
## each town's workshops choose it from the town's state. Signals (safety
## from Holdings and raids, stock against wants, how busy the town is, raws
## players sold) set the town's tier: DEFEND (arms and repairs first),
## WORK_UP (work up what players sold), STOCK (the scarcest essential
## first), SURPLUS (goods for the shop, reworks) or IDLE. Every free
## workshop bids for its tier's top want it can make; bids are granted in
## the tier's priority order, each taking its materials, and those that
## find them gone wait (a workshop that has lost STARVE_AFTER times goes
## first). Recipes come from the item catalog: a definition's "made"
## ({by: trade, from: {resource or item id: count}, steps}). A rework is
## any banked gear whose recipe is the worker's trade: half its steps and
## one of its first resource.
##
## Workers are paid rules' "wage" from the town's gold when a job is done
## (none in the game's rules: makers earn from sales; decision 353), and
## official trades a wage of their own every so often, never below rules'
## gold_floor; they pay rent from their purse every rent_every
## steps, into the town's treasury (counted as its upkeep). Rules: levels/economy.json.
## World keeps one (World.production), made by Main at boot; saved in the
## snapshot ("production": to_dict). Server only.

const PATH := "res://levels/economy.json"
const DEFEND := "defend"
const WORK_UP := "work_up"
const STOCK := "stock"
const SURPLUS := "surplus"
const IDLE := "idle"
const THREATENED := "threatened"
const UNEASY := "uneasy"
const SAFE := "safe"
const QUIET := "quiet"
const STEADY := "steady"
const BUSY := "busy"

var rules := {}
var stockpile: Stockpile
## Null with no territory (tests): every town is safe.
var holdings: Holdings
## () -> int: the World's steps.
var clock := Callable()
## () -> Dictionary: id -> {id, tags, made}, the recipes (items_catalog).
var catalog := Callable()
## (workshop) -> bool: whether a workshop may work (its building stands;
## Towns sets it). Every workshop may by default.
var workshop_open := Callable()
## (workshop) -> int: its level (its building's; Towns sets it), 1 by
## default. Each level past the first makes its jobs level_speed faster.
var workshop_level := Callable()
## (town, building id) -> void: a "build" job is done (Towns sets it).
var on_built := Callable()
## (town, building id, worker_id, fee) -> int: what players gave toward a
## build pays its fee first, the rest kept by the town (Economy.settle_fund,
## decision 499); the gold it paid. Unset, the treasury pays it all.
var settle_fund := Callable()
## (job) -> void: a "return" job is done (decision 396; Main sets it): its
## who and who_kind brought back at its workshop by its worker ("by"), or,
## "fallback" true, given up on (nobody there for rules' return.give_up).
var returned := Callable()
## (town) -> String: a hunter of [param town] hunts its area's herds
## (decision 407; Main sets it: Herds.hunt_one near its store): the kind
## caught, or "" for no game.
var hunt := Callable()
## (town, site place) -> the kind caught: a hunter hunting at the town's
## hunting ground (decision 521); hunt's at the store without one.
var hunt_at := Callable()
## (town) -> {resource: count} the town's next build lacks (Towns.shortfall's
## needs; 522 amended (2)): a maker working one of those works on the
## town's account.
var build_lacks := Callable()
## (town, worker id, gold, why, resource): Economy.owe_or_pay, the town's
## wage for work on its account, owed when the treasury is at its floor.
var town_pays := Callable()
## Workers on the way to or at their trade's site: worker id -> the step
## they are back (decision 521).
var _trips: Dictionary = {}
## Each site's last state said (decision 521): site id -> why ("" worked).
var _site_said: Dictionary = {}
## (town, worker_id, what, count, why) -> bool: a gatherer's delivery to
## the town's store, bought and hauled (Economy.deliver, decision 498);
## false when the store won't take it. Unset (tests), it is banked free.
var deliver := Callable()
## (town, worker_id, needs: {resource: count}) -> bool: a maker pays the
## store for a job's materials (Economy.buy_materials, decision 498);
## false when they can't. Unset, they are free.
var buy_materials := Callable()
## (shop) -> float: how fast [param shop]'s work goes now, 1 normal (Towns
## sets it: a dry well halves the kitchen's, decision 426); unset, 1.
var work_rate := Callable()

## What worker [param worker_id] owes the town's bank changed (set_loan):
## for npc's cards.
signal loan_changed(worker_id: String, owed: float, working_off: bool)
## A hunter of [param town] came home from a hunt ([param kind] caught, ""
## for none): for the town's log.
signal hunted(town: String, worker_id: String, kind: String)
## A "work" job on a thing for someone ([param job]: its uid in uids, its
## effect, for (an owner's carrier key), town) is done (decision 434): Towns
## holds a blessed thing for its owner.
signal work_done(job: Dictionary)
## Worker [param worker_id] of [param town] made a thing, [param uid], just
## minted: before a raw's yield is banked as stock or a thing goes on their
## shelf, so npc's scoundrel can measure it short first (decision 492).
signal made(town: String, worker_id: String, uid: int)

## Id -> {id, name, trades, town, origin, purse, rent_due, away, needs
## (need -> step due), fed, hungry_since, last_trade, wage_due, hunt_due, loan
## (owed to the town's bank, decision 354), working_off, type (hidden, npc's)
## and the MIND (each 1..10; neither a companion's), card (npc's, kept as
## it is) and heard (companions' Hearsay's, kept as it is)}.
var _workers: Dictionary[String, Dictionary] = {}
## Id -> {id, trade, town, worker, job, waited}.
var _workshops: Dictionary[String, Dictionary] = {}
## Id -> {id, kind (make, rework), recipe, town, workshop, worker, state
## (queued, working), ordered, resources, uids, needed, worked, last}.
var _jobs: Dictionary[int, Dictionary] = {}
## Workshop id -> what it was last said to wait for (not saved): a wait
## is told when it starts or what it is short of changes, not each tick.
var _waits_told: Dictionary = {}
## Workshop id -> true while its worker can't pay for a job's materials.
var _unpaid: Dictionary = {}
var _next_job := 1
## Town -> {tier, pending, held, sales: [{step, what, count}], upkeep}.
var _towns: Dictionary[String, Dictionary] = {}


func _init(saved := {}, with_stockpile: Stockpile = null, with_holdings: Holdings = null, with_clock := Callable(),
		with_rules := {}, with_catalog := Callable()) -> void:
	clock = with_clock
	stockpile = with_stockpile if with_stockpile != null else Stockpile.new({}, with_clock)
	holdings = with_holdings
	rules = with_rules if not with_rules.is_empty() else read_rules()
	catalog = with_catalog if with_catalog.is_valid() else Production.items_catalog
	from_dict(saved)


## The rules in [param path] ({} with a warning if it can't be read).
static func read_rules(path := PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not parsed is Dictionary:
		push_warning("[production] %s is missing or not a JSON object: no rules" % path)
		return {}
	return parsed


## The item catalog's recipes: every definition with a "made".
static func items_catalog() -> Dictionary:
	var out := {}
	for id: String in Items.ids():
		var def := Items.def(id)
		var made: Variant = def.get("made", {})
		var mend := Items.mend_of(id)
		if made is Dictionary and not made.is_empty() or not mend.is_empty():
			out[id] = {"id": id, "tags": def.get("tags", []), "made": made if made is Dictionary else {}}
			if not mend.is_empty():
				out[id]["mend"] = mend  # Items' 413: how a worn one is mended (decision 414).
	return out


## [param amount] of gold changing hands in a [param kind] of transaction
## ("sale", "buy", "trade", "wage": rules' "tax"), split [to the town, to
## the payee]: the tax rounded down, the payee the rest.
## Economy.taxed's, kept here for the callers that had it.
static func taxed(amount: int, kind: String, with_rules: Dictionary) -> Array[int]:
	return Economy.taxed(amount, kind, with_rules)


func now() -> int:
	return int(clock.call()) if clock.is_valid() else 0


func book() -> ItemBook:
	return stockpile.book


# --- Workers and workshops -----------------------------------------------------------

## A worker [param id] called [param worker_name], of [param trades], living
## in [param town]. False if the id is taken.
## [param type]: their hidden personality type (npc's; type_of's roll if
## none is given, "" for a companion).
func add_worker(id: String, worker_name: String, trades: Array, town: String, origin := "placeholder", type := "") -> bool:
	if id.is_empty() or _workers.has(id):
		return false
	var list: Array[String] = []
	list.assign(trades.map(func(trade: Variant) -> String: return str(trade)))
	_workers[id] = {"id": id, "name": worker_name, "trades": list, "town": town, "origin": origin, "purse": 0,
		"rent_due": now() + int(rules.get("rent_every", 6000)), "away": false,
		"needs": {}, "fed": "", "hungry_since": 0, "last_trade": {}, "wage_due": 0, "hunt_due": 0,
		"loan": 0.0, "working_off": false, "heard": [], "card": {}, "owed": 0, "sick": false, "apprentice": "", "master": ""}
	# Their mind (companions' Hearsay, decision 378): a hidden type (npc's
	# roll), and the four rolled about their trade's and type's profile by
	# the id, so the same every load; a companion's comes from her card.
	if not id.begins_with("companion:"):
		if type.is_empty() and type_of.is_valid():
			type = str(type_of.call(id))
		_workers[id]["type"] = type
		var trade: String = list[0] if not list.is_empty() else ""
		for each: String in MIND:
			_workers[id][each] = mind_of(id, trade, each, type)
	_town(town)
	return true


## Worker [param worker_id]'s card, as npc writes it whole ({traits, came,
## facts, card, card_by}; stored as given; nothing for an unknown id).
func set_card(worker_id: String, card: Dictionary) -> void:
	if _workers.has(worker_id):
		_workers[worker_id]["card"] = card.duplicate(true)


## What worker [param worker_id] has heard, as companions' Hearsay keeps
## it (stored as given; nothing for an unknown id).
func set_heard(worker_id: String, heard: Array) -> void:
	if _workers.has(worker_id):
		_workers[worker_id]["heard"] = heard.duplicate(true)


## Worker [param worker_id]'s [param quality] of MIND, 1..10: a companion
## resting in town brings hers from her card (decision 442); nothing for an
## unknown id.
func set_mind(worker_id: String, quality: String, value: int) -> void:
	if _workers.has(worker_id) and quality in MIND:
		_workers[worker_id][quality] = clampi(value, 1, 10)


## A resident's mind (decision 378): each 1..10, rolled within MIND_SPREAD
## of their trade's profile (profile_of), else MIND_MIDDLE.
const MIND: Array[String] = ["intellect", "superstition", "creativity", "integrity"]
const MIND_SPREAD := 2
const MIND_MIDDLE := 5
## A profile's words as numbers.
const MIND_WORDS := {"low": 2, "mid": 5, "middle": 5, "high": 8}
## (trade, type) -> {intellect, superstition, creativity, integrity: 1..10
## or a word}, lore's role profiles, the type's over the trade's
## (Lore.profile; Main sets it before the snapshot loads). Unset, or {} for
## a trade with none: townsfolk's.
static var profile_of := Callable()
## (worker id) -> String: a resident's hidden personality type, rolled by
## the id (npc's Townsfolk.roll_type; Main sets it). Unset: "" (steady).
static var type_of := Callable()


## [param id]'s [param quality] (one of MIND), a resident of [param trade]
## and [param type]: about their profile, by the id.
static func mind_of(id: String, trade: String, quality: String, type := "") -> int:
	var middle := MIND_MIDDLE
	var profile: Variant = profile_of.call(trade, type) if profile_of.is_valid() else {}
	if not profile is Dictionary or profile.is_empty():
		profile = profile_of.call("townsfolk", type) if profile_of.is_valid() else {}
	var value: Variant = profile.get(quality) if profile is Dictionary else null
	if value is float or value is int:
		middle = int(value)
	elif value is String and MIND_WORDS.has(value):
		middle = MIND_WORDS[value]
	var roll := int(("%s:%s" % [id, quality]).md5_buffer().decode_u32(0) % (MIND_SPREAD * 2 + 1)) - MIND_SPREAD
	return clampi(middle + roll, 1, 10)


## Every worker's id ([param town]'s only, if given), sorted.
func worker_ids(town := "") -> Array[String]:
	var out: Array[String] = []
	for id: String in _workers:
		if town.is_empty() or _workers[id]["town"] == town:
			out.append(id)
	out.sort()
	return out


# --- Residents' own trade (decision 353; Economy.tick does the buying) ---------------

## What the town owes worker [param worker_id] for deliveries it could not
## pay for yet (decision 498).
func set_owed(worker_id: String, gold: int) -> void:
	if _workers.has(worker_id):
		_workers[worker_id]["owed"] = maxi(gold, 0)


## [param what] x [param count] brought into [param town]'s store by
## worker [param worker_id] ([param by] in the ledger): through the deliver
## hook when set (bought, hauled), else banked free. False when the store
## would not take it.
func deliver_to(town: String, worker_id: String, what: String, count: int, by: String, why: String) -> bool:
	if count < 1:
		return false
	if deliver.is_valid() and not worker(worker_id).is_empty():
		return bool(deliver.call(town, worker_id, what, count, why))
	return stockpile.deposit(town, what, count, by, why, worker_id)


## The worker at workshop [param workshop_id] ("" for none).
func worker_at(workshop_id: String) -> String:
	return str(_workshops.get(workshop_id, {}).get("worker", ""))


## Takes [param amount] gold from worker [param worker_id]'s purse: false
## (nothing taken) if it hasn't that much.
func spend(worker_id: String, amount: int, why := "") -> bool:
	if not _workers.has(worker_id) or amount < 0 or int(_workers[worker_id]["purse"]) < amount:
		return false
	_workers[worker_id]["purse"] = int(_workers[worker_id]["purse"]) - amount
	print("[production] %s spent %d gold (%s), step %d (%d left)" % [_workers[worker_id]["name"], amount, why, now(),
		_workers[worker_id]["purse"]])
	return true


## When worker [param worker_id]'s [param need] is next due (0: not yet set).
func need_due(worker_id: String, need: String) -> int:
	return int(_workers.get(worker_id, {}).get("needs", {}).get(need, 0))


func set_need_due(worker_id: String, need: String, at: int) -> void:
	if _workers.has(worker_id):
		_workers[worker_id]["needs"][need] = at


## How worker [param worker_id] last ate: "bought" (from the shop),
## "store" (the store's food, paid for), "dole" (fed by the town) or
## "hungry" (nothing to eat); hungry_since is the step they first went
## without, 0 once fed.
func note_meal(worker_id: String, how: String) -> void:
	if not _workers.has(worker_id):
		return
	var worker_record: Dictionary = _workers[worker_id]
	worker_record["fed"] = how
	if how == "hungry":
		if int(worker_record["hungry_since"]) == 0:
			worker_record["hungry_since"] = maxi(now(), 1)
	else:
		worker_record["hungry_since"] = 0


## Worker [param worker_id]'s last trade, for their voice:
## {step, what, gold, with} (with: the other side's name, or "the town").
func note_trade(worker_id: String, what: String, gold: int, with_whom: String) -> void:
	if _workers.has(worker_id):
		_workers[worker_id]["last_trade"] = {"step": now(), "what": what, "gold": gold, "with": with_whom}


## What worker [param worker_id] owes the town's bank now
## ([param working_off]: working it off as town labour; decision 354).
func set_loan(worker_id: String, owed: float, working_off := false) -> void:
	if _workers.has(worker_id):
		var was: float = _workers[worker_id]["loan"]
		var was_working: bool = _workers[worker_id]["working_off"]
		_workers[worker_id]["loan"] = maxf(owed, 0.0)
		_workers[worker_id]["working_off"] = working_off and owed > 0.0
		if not is_equal_approx(was, _workers[worker_id]["loan"]) or was_working != _workers[worker_id]["working_off"]:
			loan_changed.emit(worker_id, _workers[worker_id]["loan"], _workers[worker_id]["working_off"])


## How many of [param town]'s workers (not away) the town fed, or who went
## hungry, at their last meal: the dole, which makes food its first want.
func on_dole(town: String) -> int:
	var count := 0
	for id in worker_ids(town):
		if not _workers[id]["away"] and str(_workers[id]["fed"]) in ["dole", "hungry"]:
			count += 1
	return count


## A workshop [param id] of [param trade] in [param town]. False if the id is taken.
func add_workshop(id: String, trade: String, town: String) -> bool:
	if id.is_empty() or _workshops.has(id):
		return false
	_workshops[id] = {"id": id, "trade": trade, "town": town, "worker": "", "job": 0, "waited": 0}
	_town(town)
	return true


## [param worker_id] works at [param workshop_id] ("" leaves it empty): of
## its trade and town, and at no other. False if not.
func assign(workshop_id: String, worker_id: String) -> bool:
	if not _workshops.has(workshop_id):
		return false
	var shop: Dictionary = _workshops[workshop_id]
	if worker_id.is_empty():
		shop["worker"] = ""
		return true
	var worker: Dictionary = _workers.get(worker_id, {})
	if worker.is_empty() or shop["trade"] not in worker["trades"] or worker["town"] != shop["town"]:
		return false
	for other: Dictionary in _workshops.values():
		if other["worker"] == worker_id and other != shop:
			return false
	shop["worker"] = worker_id
	return true


## [param worker_id] is away (true) or back: an away worker's job waits.
## Their work is counted up to now first, so it goes by when they left.
func set_away(worker_id: String, away: bool) -> void:
	if not _workers.has(worker_id) or _workers[worker_id]["away"] == away:
		return
	var at := now()
	for each: Dictionary in _jobs.values():
		if each["state"] == "working" and each["worker"] == worker_id:
			if _present(worker_id, each["workshop"]):
				each["worked"] = int(each["worked"]) + at - int(each["last"])
			each["last"] = at
	_workers[worker_id]["away"] = away


## [param worker_id] is sick (true) or well (npc's sickness, decision 501):
## kept from work as one away is (their job waits, counted to now first),
## but their needs still come due.
func set_sick(worker_id: String, sick: bool) -> void:
	if not _workers.has(worker_id) or bool(_workers[worker_id].get("sick", false)) == sick:
		return
	var at := now()
	for each: Dictionary in _jobs.values():
		if each["state"] == "working" and each["worker"] == worker_id:
			if _present(worker_id, each["workshop"]):
				each["worked"] = int(each["worked"]) + at - int(each["last"])
			each["last"] = at
	_workers[worker_id]["sick"] = sick


## [param master] takes [param apprentice] (decision 498 amended: Jeff's
## "makers have more expense - raw material and apprentices"), or, with
## apprentice "", lets theirs go. False if either is unknown or taken.
func set_apprentice(master: String, apprentice: String) -> bool:
	if not _workers.has(master):
		return false
	var had := str(_workers[master].get("apprentice", ""))
	if apprentice.is_empty():
		if _workers.has(had):
			_workers[had]["master"] = ""
		_workers[master]["apprentice"] = ""
		return true
	if not had.is_empty() or not _workers.has(apprentice) or not str(_workers[apprentice].get("master", "")).is_empty() \
			or not str(_workers[apprentice].get("apprentice", "")).is_empty() or apprentice == master:
		return false
	_workers[master]["apprentice"] = apprentice
	_workers[apprentice]["master"] = master
	return true


## When worker [param worker_id]'s purse first stood above the apprentice
## line this run (-1 for not above), for Economy's apprentice turn.
func set_above_since(worker_id: String, at: int) -> void:
	if _workers.has(worker_id):
		if at < 0:
			_workers[worker_id].erase("above_since")
		else:
			_workers[worker_id]["above_since"] = at


## Whether [param worker_record] is kept from work: away, or sick (501).
static func off_work(worker_record: Dictionary) -> bool:
	return bool(worker_record.get("away", false)) or bool(worker_record.get("sick", false))


## Worker [param worker_id] gone for good (Towns.died, decision 501): out
## of their workshop (a job in progress back to the queue) and the records.
func remove_worker(worker_id: String) -> void:
	if not _workers.has(worker_id):
		return
	for shop: Dictionary in _workshops.values():
		if shop["worker"] == worker_id:
			shop["worker"] = ""
	for each: Dictionary in _jobs.values():
		if each["worker"] == worker_id and each["state"] == "working":
			each["state"] = "queued"
			each["worker"] = ""
	set_apprentice(worker_id, "")
	var master := str(_workers[worker_id].get("master", ""))
	if _workers.has(master):
		_workers[master]["apprentice"] = ""
	_workers.erase(worker_id)


## Where worker [param worker_id] came from, said again (a companion's
## player, once known: Towns.note_companion_in).
func set_origin(worker_id: String, origin: String) -> void:
	if _workers.has(worker_id):
		_workers[worker_id]["origin"] = origin


## The workshop [param worker_id] works at ("" for none).
func workshop_of(worker_id: String) -> String:
	for id: String in _workshops:
		if _workshops[id]["worker"] == worker_id:
			return id
	return ""


## A "return" job (decision 396) at [param workshop_id], under way at
## once, worked by whoever works there: [param who] ([param who_kind]:
## player, companion, resident) brought back after rules' return.steps, at
## Holdings place [param place]. Its id; 0 if the workshop has nobody.
func open_return(workshop_id: String, who: String, who_kind: String, place := "") -> int:
	var shop: Dictionary = _workshops.get(workshop_id, {})
	if shop.is_empty() or str(shop["worker"]).is_empty():
		return 0
	var id := _new_job("return", who, shop)
	var each: Dictionary = _jobs[id]
	each["state"] = "working"
	each["worker"] = shop["worker"]
	each["needed"] = maxi(int(rules.get("return", {}).get("steps", 600)), 1)
	each["last"] = now()
	each["opened"] = now()
	each["who"] = who
	each["who_kind"] = who_kind
	each["place"] = place
	print("[production] %s (%s) to be brought back at %s by %s" % [who, who_kind, workshop_id, _workers[shop["worker"]]["name"]])
	return id


## A thing, [param uid], handed in at [param workshop_id] for
## [param owner] (a carrier key) to be worked on with [param effect]
## ("bless": rules' bless.steps; "reforge" into [param to_id], decision
## 436: [param materials] taken from the town's stock now, [param steps]
## of work), by its worker, held by the job; its own job, not the
## workshop's slot. Its id, or 0 if nobody works there or the town lacks
## the materials. [param fee] and [param payer]: what the owner paid, kept
## on the job to give back if the work can't be done.
func open_work(workshop_id: String, uid: int, effect: String, owner: String, to_id := "", materials := {},
		steps := 0, fee := 0, payer := "") -> int:
	var shop: Dictionary = _workshops.get(workshop_id, {})
	if shop.is_empty() or str(shop["worker"]).is_empty():
		return 0
	for what: String in materials:
		if stockpile.count(shop["town"], what) < int(materials[what]):
			return 0
	var id := _new_job("work", book().id_of(uid), shop)
	var each: Dictionary = _jobs[id]
	for what: String in materials:
		stockpile.take(shop["town"], what, int(materials[what]), "job #%d" % id)
		each["resources"][what] = int(materials[what])
	each["state"] = "working"
	each["worker"] = shop["worker"]
	each["effect"] = effect
	each["for"] = owner
	each["to_id"] = to_id if not to_id.is_empty() else book().id_of(uid)
	each["uids"] = [uid]
	each["fee"] = fee
	each["payer"] = payer
	each["needed"] = steps if steps > 0 else maxi(int(rules.get(effect, {}).get("steps", 600)), 1)
	each["last"] = now()
	book().place(uid, "job:%d" % id)
	print("[production] %s (#%d) handed in at %s to %s for %s" % [book().id_of(uid), uid, workshop_id, effect, owner])
	return id


## Whether someone works at [param workshop_id] now (there, not away, its
## building standing): a place to bring the fallen back.
func manned(workshop_id: String) -> bool:
	return _present(str(_workshops.get(workshop_id, {}).get("worker", "")), workshop_id)


## Whether [param worker_id] lives outside any town's purse (rules'
## return.places with "outside": the medicine man): no rent, no needs.
func outside(worker_id: String) -> bool:
	if _trips.has(worker_id):
		return true
	var trades: Array = _workers.get(worker_id, {}).get("trades", [])
	for place: Dictionary in rules.get("return", {}).get("places", {}).values():
		if bool(place.get("outside", false)) and str(place.get("trade", "")) in trades:
			return true
	return false


## Whether [param town] has a "build" job queued or under way.
func building_in(town: String) -> bool:
	return _jobs.values().any(func(each: Dictionary) -> bool: return each["kind"] == "build" and each["town"] == town)


## Whether every build [param town] has in hand is stalled (decision 522):
## queued, its materials not in the store, ordered build_wait.days ago or
## more (a build saved before 522 has no "at": long ago), and fewer than
## build_wait.most of them; then the town may order
## its next build, the stalled one kept at the head (499's shortfall, the
## builder's first choice once its materials come).
func builds_stalled(town: String) -> bool:
	var rule: Dictionary = rules.get("build_wait", {})
	var wait := int(float(rule.get("days", 0)) * maxi(DayNight.day_steps, 1))
	if wait <= 0:
		return false
	var builds := _jobs.values().filter(func(each: Dictionary) -> bool: return each["kind"] == "build" and each["town"] == town)
	if builds.is_empty() or builds.size() >= int(rule.get("most", 3)):
		return false
	for each: Dictionary in builds:
		if each["state"] != "queued" or now() - int(each.get("at", 0)) < wait or _affords(town, {"from": each.get("cost", {})}, false):
			return false
	return true


func worker(id: String) -> Dictionary:
	return _workers.get(id, {}).duplicate(true)


func workshop(id: String) -> Dictionary:
	return _workshops.get(id, {}).duplicate(true)


func job(id: int) -> Dictionary:
	return _jobs.get(id, {}).duplicate(true)


## Every job's id, in order.
func jobs() -> Array[int]:
	var out: Array[int] = []
	out.assign(_jobs.keys())
	out.sort()
	return out


## [param town]'s tier now ("" before its first tick).
func tier(town: String) -> String:
	return str(_towns.get(town, {}).get("tier", ""))


## The gold [param town]'s residents have paid in rent, all told.
func upkeep(town: String) -> int:
	return int(_towns.get(town, {}).get("upkeep", 0))


## Every uid a job holds (ItemBook.orphans' known).
func all_items() -> Array[int]:
	var out: Array[int] = []
	for each: Dictionary in _jobs.values():
		out.append_array(each["uids"])
	return out


# --- Orders and sales ----------------------------------------------------------------

## A job of [param recipe] at [param workshop_id], ahead of what the town
## would choose (tests, the console); with [param rework_uid], a rework of
## that banked thing. Its id, or 0 if the workshop or recipe isn't there.
func order(workshop_id: String, recipe: String, rework_uid := 0) -> int:
	var cat: Dictionary = catalog.call()
	if not _workshops.has(workshop_id) or not cat.has(recipe):
		return 0
	var id := _new_job("rework" if rework_uid != 0 else "make", recipe, _workshops[workshop_id])
	_jobs[id]["ordered"] = true
	if rework_uid != 0:
		_jobs[id]["rework"] = rework_uid
	return id


## Job [param id] is cancelled: what it took goes back to the stockpile.
func cancel(id: int) -> bool:
	if not _jobs.has(id):
		return false
	var each: Dictionary = _jobs[id]
	_give_back(each)
	var shop: Dictionary = _workshops.get(each["workshop"], {})
	if not shop.is_empty() and shop["job"] == id:
		shop["job"] = 0
	_jobs.erase(id)
	print("[production] job #%d (%s) cancelled at %s; its materials go back" % [id, each["recipe"], each["workshop"]])
	return true


## Players sold [param amount] of resource [param what] to [param town]'s
## shop (the shop calls this; tests too): its workshops work it up.
## Pays [param amount] gold into worker [param worker_id]'s purse (a sale of
## what they made, the tax already taken) for [param why].
func pay(worker_id: String, amount: int, why := "") -> void:
	if not _workers.has(worker_id) or amount <= 0:
		return
	_workers[worker_id]["purse"] = int(_workers[worker_id]["purse"]) + amount
	print("[production] %s paid %d gold (%s), step %d" % [_workers[worker_id]["name"], amount, why, now()])


## Thief [param thief_id] lifts up to [param gold] from worker
## [param worker_id]'s purse (never more than it holds) into their own
## (npc's thief, decision 461): what was taken. Gold only moves.
func lift_gold(worker_id: String, gold: int, thief_id: String) -> int:
	if not _workers.has(worker_id) or not _workers.has(thief_id) or worker_id == thief_id or gold <= 0:
		return 0
	var taken := mini(gold, int(_workers[worker_id]["purse"]))
	if taken <= 0:
		return 0
	spend(worker_id, taken, "lifted")
	pay(thief_id, taken, "lifted")
	stockpile.note(str(_workers[worker_id]["town"]), "gold", 0, "lifted:%s" % worker_id,
		"%d gold went missing from %s's purse" % [taken, _workers[worker_id]["name"]])
	return taken


## A caught thief [param thief_id] gives back up to [param gold] to
## [param victim_id] (never more than they hold): what was given back.
func return_gold(thief_id: String, victim_id: String, gold: int) -> int:
	if not _workers.has(thief_id) or not _workers.has(victim_id) or gold <= 0:
		return 0
	var back := mini(gold, int(_workers[thief_id]["purse"]))
	if back <= 0:
		return 0
	spend(thief_id, back, "returned what was lifted")
	pay(victim_id, back, "given back")
	stockpile.note(str(_workers[victim_id]["town"]), "gold", 0, "returned:%s" % victim_id,
		"%d gold given back to %s" % [back, _workers[victim_id]["name"]])
	return back


func note_sale(town: String, what: String, amount: int) -> void:
	_town(town)["sales"].append({"step": now(), "what": what, "count": amount})


# --- The world tick ------------------------------------------------------------------

## Moves the work on to now: jobs advance and finish, rent falls due, each
## town's tier is weighed and its free workshops choose and start work.
## Deterministic: by id throughout, timed by the clock alone.
func tick() -> void:
	var at := now()
	var cat: Dictionary = catalog.call()
	_advance(at, cat)
	_rent(at)
	_official_wages(at)
	_hunts(at)
	var towns: Array[String] = []
	towns.assign(_towns.keys())
	towns.sort()
	for town in towns:
		var signals := signals_of(town, cat)
		_weigh(town, signals)
		_choose(town, signals, cat)


func _advance(at: int, cat: Dictionary) -> void:
	for id in jobs():
		var each: Dictionary = _jobs[id]
		if each["state"] != "working":
			continue
		if _present(each["worker"], each["workshop"]):
			var rate := float(work_rate.call(_workshops.get(each["workshop"], {}))) if work_rate.is_valid() else 1.0
			# An apprentice at hand works the job faster (498 amended).
			var helper := str(_workers.get(each["worker"], {}).get("apprentice", ""))
			if not helper.is_empty() and _workers.has(helper) and not off_work(_workers[helper]):
				rate *= float(rules.get("apprentice", {}).get("speed", 1.0))
			each["worked"] = int(each["worked"]) + roundi((at - int(each["last"])) * rate)
		each["last"] = at
		if each["kind"] == "return" and int(each["worked"]) < int(each["needed"]) 				and at - int(each["opened"]) >= int(rules.get("return", {}).get("give_up", 6000)):
			each["fallback"] = true  # Nobody there to do it: brought back as before.
			_finish(each, cat)
		elif int(each["worked"]) >= int(each["needed"]):
			_finish(each, cat)


func _present(worker_id: String, workshop_id: String) -> bool:
	var worker_record: Dictionary = _workers.get(worker_id, {})
	var shop: Dictionary = _workshops.get(workshop_id, {})
	return not worker_record.is_empty() and not off_work(worker_record) and shop.get("worker", "") == worker_id \
			and (not workshop_open.is_valid() or workshop_open.call(shop))


func _finish(each: Dictionary, cat: Dictionary) -> void:
	if each["kind"] == "return":
		_jobs.erase(int(each["id"]))
		var done := each.duplicate(true)
		done["by"] = str(_workers.get(each["worker"], {}).get("name", ""))
		print("[production] %s %s at %s by %s, step %d" % [each["who"], "given up on, brought back as before" if done.get("fallback", false)
			else "brought back", each["workshop"], done["by"], now()])
		if returned.is_valid():
			returned.call(done)
		return
	var worker_record: Dictionary = _workers[each["worker"]]
	var made_at := "%s at %s" % [worker_record["name"], each["workshop"]]
	var uid := 0
	if each["kind"] == "build":
		if on_built.is_valid():
			on_built.call(each["town"], each["recipe"])
		_town_work_fee(each, worker_record)
	elif each["kind"] == "rework":
		uid = int(each["uids"][0])
		book().place(uid, "")
		book().note(uid, "reworked", made_at)
	elif each["kind"] == "work" and str(each.get("effect", "mend")) != "mend":
		# A thing someone handed in (decision 434): blessed for its owner,
		# then held for them (work_done: Towns).
		var worked_on := int(each["uids"][0])
		book().place(worked_on, "")
		if each["effect"] == "bless":
			book().bless(worked_on, str(each["for"]))
		elif each["effect"] == "reforge" and not book().reforge(worked_on, str(each["to_id"])):
			# Refused now (it lost its name, say): its materials back to the
			# town, the fee back to its payer (World, on work_done).
			_give_back(each)
			each["failed"] = true
		each["worked_on"] = worked_on
		each["by"] = str(worker_record["name"])
		work_done.emit(each.duplicate(true))
	elif each["kind"] == "work":
		# The same thing (its history, its name) back to its most, banked
		# where it was taken from, not put up for sale (decision 414).
		var mended := int(each["uids"][0])
		book().place(mended, "")
		book().set_condition(mended, Items.condition_max(book().id_of(mended)))
		book().note(mended, "mended", made_at)
		stockpile.bank(each["town"], mended, worker_record["name"], "a mend", "", Vector2i(-1, -1), "")
		each["mended"] = mended
	else:
		uid = book().mint(each["recipe"], "made", made_at)
		# Gear it was made from is in what it became.
		for used: int in each["uids"]:
			book().end(used, "used", "made into %s #%d" % [each["recipe"], uid])
		# Told before its yield is read or it is shelved: a scoundrel's
		# measures it short here (492, items' 493).
		made.emit(str(each["town"]), str(worker_record["id"]), uid)
	each["uids"] = []
	var yields := book().yields_of(uid) if uid != 0 else {}  # A short one's share (decision 493).
	var taken := not yields.is_empty()
	if taken:
		# A raw made from raws (the tanner's leather) is the town's stock, for
		# its own work to use (the mend, the buckler: decision 405 amended),
		# bought from its maker (498); one the store won't take stays theirs.
		for what: String in yields:
			if bool(each.get("account", false)):
				# Made on the town's account for its build: the town's, its
				# maker paid a wage for the work (522 amended (2)).
				taken = stockpile.deposit(each["town"], what, int(yields[what]), worker_record["name"], "made at %s for the town's build" % each["workshop"], str(worker_record["id"])) and taken
			else:
				taken = deliver_to(each["town"], str(worker_record["id"]), what, int(yields[what]), worker_record["name"], "made at %s" % each["workshop"]) and taken
		if bool(each.get("account", false)) and town_pays.is_valid():
			town_pays.call(each["town"], str(worker_record["id"]), int(rules.get("store", {}).get("account_wage", 0)),
				"making %s for the town's build" % each["recipe"], yields.keys()[0] if not yields.is_empty() else "")
		if taken:
			book().end(uid, "banked", "%s by %s" % [each["town"], worker_record["name"]])
	if not taken and uid != 0:
		stockpile.stock_shop(each["town"], uid, worker_record["name"], worker_record["id"])
	# The wage, less its tax, which stays in the treasury.
	var wage: int = taxed(int(rules.get("wage", 0)), "wage", rules)[1]
	var floor_gold := int(rules.get("gold_floor", 0))
	var paid := wage > 0 and stockpile.count(each["town"], "gold") - wage >= floor_gold \
			and stockpile.take(each["town"], "gold", wage, "wage:%s" % worker_record["id"])
	if paid:
		worker_record["purse"] = int(worker_record["purse"]) + wage
	print("[production] %s finished %s #%d (%s), step %d; %s" % [made_at, each["recipe"], uid if uid != 0 else int(each.get("mended", each.get("worked_on", 0))),
		each.get("effect", each["kind"]), now(),
		"paid %d gold" % wage if paid else "unpaid (the town's gold is at its floor)" if wage > 0 else "no wage"])
	var shop: Dictionary = _workshops.get(each["workshop"], {})
	if not shop.is_empty() and shop["job"] == each["id"]:
		shop["job"] = 0
	_jobs.erase(int(each["id"]))


## Work the town ordered (a build or repair job, [param each]) is paid
## from the treasury to [param worker_record] who did it, as a resident
## pays the carpenter (decision 353 amended): rules' "town_work" fee for
## each per_steps of the work, at least 1; what the treasury has above
## gold_floor if less, none at the floor.
func _town_work_fee(each: Dictionary, worker_record: Dictionary) -> void:
	var town_work: Dictionary = rules.get("town_work", {})
	var fee := int(town_work.get("fee", 0))
	if fee <= 0:
		return
	var town: String = each["town"]
	var owed := town_work_fee(int(each["needed"]))
	var given := int(settle_fund.call(town, str(each["recipe"]), str(worker_record["id"]), owed)) if settle_fund.is_valid() else 0
	var paid := mini(owed - given, stockpile.count(town, "gold") - int(rules.get("gold_floor", 0)))
	if paid > 0 and stockpile.take(town, "gold", paid, "town_work:%s" % worker_record["id"]):
		worker_record["purse"] = int(worker_record["purse"]) + paid
	print("[production] %s paid %d of %d gold by %s for %s, step %d" % [worker_record["name"], maxi(paid, 0) + given, owed, town,
		each["recipe"], now()])


## The town's fee for [param steps] of its work (rules' town_work): 0 for
## no fee, else at least 1.
func town_work_fee(steps: int) -> int:
	var town_work: Dictionary = rules.get("town_work", {})
	var fee := int(town_work.get("fee", 0))
	if fee <= 0:
		return 0
	return maxi(int(steps / maxf(float(town_work.get("per_steps", 600)), 1.0) * fee), 1)


func _rent(at: int) -> void:
	var every := int(rules.get("rent_every", 6000))
	var rent := int(rules.get("rent", 0))
	var ids: Array[String] = []
	ids.assign(_workers.keys())
	ids.sort()
	for id in ids:
		var worker_record: Dictionary = _workers[id]
		if at < int(worker_record["rent_due"]) or outside(id):
			continue
		worker_record["rent_due"] = at + every
		var pay := mini(rent, int(worker_record["purse"]))
		if pay <= 0:
			continue
		worker_record["purse"] = int(worker_record["purse"]) - pay
		var town := _town(worker_record["town"])
		# Into the treasury, the town's bank (Jeff: "they collect the 'tax'
		# but its just there as loans to keep the economy going"): gold only
		# moves. upkeep counts what was paid.
		town["upkeep"] = int(town["upkeep"]) + pay
		stockpile.deposit(worker_record["town"], "gold", pay, "rent:%s" % id, "%s paid %d gold rent" % [worker_record["name"], pay])
		print("[production] %s paid %d gold rent to %s's treasury, step %d (%d left)" % [worker_record["name"], pay,
			worker_record["town"], at, worker_record["purse"]])


## The town pays wages only for its official jobs (rules' "official":
## trade -> {wage, every}, a guard's; decision 353 amended): every "every"
## steps from the treasury while it stays at gold_floor or above (else it
## waits till next due), to each worker of that trade there, not away.
## Makers earn from what they sell.
## Each hunter (rules' hunter.trade, in town and not away) every
## hunter.every steps: the hunt hook's catch, its kind's drops (the least of
## each, monsters.json) into the town's store, a resource as its yield and
## a trophy as a thing banked there (decision 407).
func _hunts(at: int) -> void:
	var rule: Dictionary = rules.get("hunter", {})
	var trade := str(rule.get("trade", ""))
	if trade.is_empty() or not hunt.is_valid():
		return
	var every := maxi(int(rule.get("every", 3000)), 1)
	for id in worker_ids():
		var worker_record: Dictionary = _workers[id]
		if trade not in worker_record["trades"] or off_work(worker_record) and not _trips.has(id):
			continue
		if int(worker_record["hunt_due"]) == 0:
			worker_record["hunt_due"] = at + every
			continue
		if at < int(worker_record["hunt_due"]):
			continue
		var town: String = worker_record["town"]
		var trip := site_turn(town, id, trade)
		if trip == WALKING:
			continue
		worker_record["hunt_due"] = at + every
		if trip == BLOCKED:
			continue
		var site := site_of(town, trade)
		var kind := str(hunt_at.call(town, site)) if not site.is_empty() and hunt_at.is_valid() else str(hunt.call(town))
		var by := "hunter:%s" % id
		for drop: Variant in Monster.kinds().get(kind, {}).get("drops", []):
			var item := str(drop.get("item", "")) if drop is Dictionary else ""
			var count: Variant = drop.get("count", [1, 1]) if drop is Dictionary else []
			var least := int(count[0]) if count is Array and count.size() > 0 else 1
			if item.is_empty() or least <= 0:
				continue
			var yields := Items.yield_of(item)
			for what: String in yields:
				deliver_to(town, id, what, int(yields[what]) * least, by, "%s's hunt" % worker_record["name"])
			if yields.is_empty():
				for i in least:
					stockpile.bank(town, book().mint(item, "hunted", worker_record["name"]), by, "%s's hunt" % worker_record["name"])
		hunted.emit(town, id, kind)


func _official_wages(at: int) -> void:
	var official: Dictionary = rules.get("official", {})
	if official.is_empty():
		return
	var floor_gold := int(rules.get("gold_floor", 0))
	for id in worker_ids():
		var worker_record: Dictionary = _workers[id]
		var trade := ""
		for each: String in worker_record["trades"]:
			if official.has(each):
				trade = each
				break
		if trade.is_empty() or off_work(worker_record):
			continue
		var every := maxi(int(official[trade].get("every", 54000)), 1)
		if int(worker_record["wage_due"]) == 0:
			worker_record["wage_due"] = at + every
			continue
		if at < int(worker_record["wage_due"]):
			continue
		worker_record["wage_due"] = at + every
		var wage := int(official[trade].get("wage", 0))
		var town: String = worker_record["town"]
		if wage <= 0 or stockpile.count(town, "gold") - wage < floor_gold 				or not stockpile.take(town, "gold", wage, "wage:%s" % id):
			print("[production] %s the %s goes unpaid: %s's treasury is at its floor, step %d" % [worker_record["name"], trade, town, at])
			continue
		worker_record["purse"] = int(worker_record["purse"]) + wage
		print("[production] %s the %s is paid %d gold by %s, step %d" % [worker_record["name"], trade, wage, town, at])


# --- Signals and tiers ---------------------------------------------------------------

## What [param town]'s workshops go by: {safety, short (want -> shortfall
## 0..1, for wants below target), full (every resource at comfort), busy,
## sold (resource -> count sold by players in the window), raw_tier}.
func signals_of(town: String, cat: Dictionary) -> Dictionary:
	var at := now()
	var window := int(rules.get("window", 6000))
	var safety := _safety(town, at - window)
	var have := _gear_by_tag(town, cat)
	var short := {}
	var extra: Dictionary = rules.get("uneasy_extra", {}) if safety != SAFE else {}
	var wants: Dictionary = rules.get("wants", {})
	for want: String in wants:
		var target := int(wants[want]) + int(extra.get(want, 0))
		if target > 0 and int(have.get(want, 0)) < target:
			short[want] = float(target - int(have.get(want, 0))) / target
	# Anyone on the dole makes food the town's first want (decision 353).
	var dole := on_dole(town)
	if dole > 0 and wants.has("food"):
		short["food"] = 1.0
	var full := true
	var comfort: Dictionary = rules.get("comfort", {})
	for what: String in comfort:
		if stockpile.count(town, what) < int(comfort[what]):
			full = false
	var lines := stockpile.ledger(town).filter(func(line: Dictionary) -> bool: return int(line["step"]) >= at - window).size()
	lines += _jobs.values().filter(func(each: Dictionary) -> bool: return each["town"] == town).size()
	var busy_rules: Dictionary = rules.get("busy", {})
	var busy := QUIET if lines < int(busy_rules.get("quiet_below", 4)) \
			else BUSY if lines >= int(busy_rules.get("busy_from", 20)) else STEADY
	var sold := {}
	for sale: Dictionary in _towns.get(town, {}).get("sales", []):
		if int(sale["step"]) >= at - window:
			sold[sale["what"]] = int(sold.get(sale["what"], 0)) + int(sale["count"])
	var raw := DEFEND if safety == THREATENED else WORK_UP if not sold.is_empty() \
			else STOCK if not short.is_empty() else SURPLUS if full else IDLE
	return {"safety": safety, "short": short, "full": full, "busy": busy, "sold": sold, "raw_tier": raw, "dole": dole}


func _safety(town: String, since: int) -> String:
	for line: Dictionary in stockpile.ledger(town):
		if int(line["step"]) >= since and str(line["by"]).begins_with("raid:"):
			return THREATENED
	if holdings == null or holdings.place(town).is_empty():
		return SAFE
	var place := holdings.place(town)
	if holdings.holder(town) != Stockpile.TOWN or holdings.strength(town) <= 0 \
			or holdings.ground(place["area"], place["cell"]) == Factions.CONTESTED:
		return THREATENED
	for id in holdings.places_in(place["area"]):
		if holdings.factions.hostile(Stockpile.TOWN, holdings.holder(id)):
			return UNEASY
	# A work site of its own the town doesn't hold (decision 521).
	for trade: String in rules.get("sites", {}).get("trades", {}):
		var site := site_of(town, trade)
		if not site.is_empty() and not site_blocked(town, site).is_empty():
			return UNEASY
	return SAFE


# --- Work sites (decision 521) -----------------------------------------------------

## site_turn's answers: no site (today's yield, at once), the site held by
## another or contested (no yield), the worker walking there and back (the
## yield when back), back from it (the yield now).
const NO_SITE := ""
const BLOCKED := "blocked"
const WALKING := "walking"
const BACK := "back"


## [param town]'s site for [param trade] (decision 521, on maps' 517 and
## builder's 520): the first Holdings place of the kind economy.json's
## sites.trades names for it whose town is [param town]; {} for none.
func site_of(town: String, trade: String) -> Dictionary:
	var kind := str(rules.get("sites", {}).get("trades", {}).get(trade, ""))
	if kind.is_empty() or holdings == null:
		return {}
	for id in holdings.all_places():
		var place := holdings.place(id)
		if str(place.get("kind", "")) == kind and str(place.get("town", "")) == town:
			return place
	return {}


## Why [param town] can't work [param site] now: "" when it holds it (its
## faction's, strength left, its ground not contested), else "contested" or
## "held by <faction>".
func site_blocked(town: String, site: Dictionary) -> String:
	var id := str(site["id"])
	if holdings.ground(str(site["area"]), site["cell"]) == Factions.CONTESTED:
		return "contested"
	if holdings.holder(id) != Stockpile.TOWN or holdings.strength(id) <= 0:
		return "held by %s" % holdings.holder(id)
	return ""


## Steps for [param town]'s worker to walk to [param site] and back: the
## cells between its store and the site there and back at
## sites.steps_per_cell, sites.other_area for one in another area.
func site_walk(town: String, site: Dictionary) -> int:
	var rule: Dictionary = rules.get("sites", {})
	var home := holdings.place(town) if holdings != null else {}
	if home.is_empty() or str(home["area"]) != str(site["area"]):
		return int(rule.get("other_area", 3000))
	var cells := Vector2(site["cell"] - home["cell"]).length()
	return 2 * ceili(cells * float(rule.get("steps_per_cell", 4)))


## Worker [param id] of [param town], their [param trade]'s work due: whether
## it yields now (decision 521). NO_SITE with no site of its kind (today's
## yield); BLOCKED when the town doesn't hold it, said once a change, the
## work not done; WALKING while the worker is on the way there and back
## (outside the walls, at no other work), BACK when they are home and it
## yields. A trip in hand when the site is lost ends: home with nothing.
func site_turn(town: String, id: String, trade: String) -> String:
	var site := site_of(town, trade)
	if site.is_empty():
		_trips.erase(id)
		return NO_SITE
	var why := site_blocked(town, site)
	if why != str(_site_said.get(site["id"], "")):
		_site_said[site["id"]] = why
		var who := str(_workers.get(id, {}).get("name", id))
		if why.is_empty():
			print("[production] %s's %s is the town's again: %s works it, step %d" % [town, site["kind"].replace("_", " "), who, now()])
		else:
			print("[production] %s's %s is %s: %s gets nothing from it, step %d" % [town, site["kind"].replace("_", " "), why, who, now()])
	if not why.is_empty():
		_trips.erase(id)
		return BLOCKED
	if not _trips.has(id):
		var walk := site_walk(town, site)
		if walk <= 0:
			return BACK
		_trips[id] = now() + walk
		return WALKING
	if now() < int(_trips[id]):
		return WALKING
	_trips.erase(id)
	return BACK


## Whether [param town]'s [param trade] may work its site now: no site, or
## one the town holds (the farmer's field work, decision 521).
func site_works(town: String, trade: String) -> bool:
	var site := site_of(town, trade)
	return site.is_empty() or site_blocked(town, site).is_empty()


## [param town]'s gear (store and shop) counted by tag.
func _gear_by_tag(town: String, cat: Dictionary) -> Dictionary:
	var out := {}
	var uids := stockpile.items(town)
	uids.append_array(stockpile.shop(town))
	for uid in uids:
		for tag: Variant in _tags_of(book().id_of(uid), cat):
			out[str(tag)] = int(out.get(str(tag), 0)) + 1
	return out


## [param id]'s tags, from the recipes or the item catalog.
func tags_of(id: String) -> Array:
	return _tags_of(id, catalog.call())


func _tags_of(id: String, cat: Dictionary) -> Array:
	return cat[id]["tags"] if cat.has(id) else Items.def(id).get("tags", [])


## The town's tier follows its raw tier once that has held tier_hold ticks.
func _weigh(town: String, signals: Dictionary) -> void:
	var state := _town(town)
	var raw: String = signals["raw_tier"]
	if state["tier"] == "":
		state["tier"] = raw
		print("[production] %s starts %s (%s)" % [town, raw.to_upper(), _why(signals)])
		return
	if raw == state["tier"]:
		state["pending"] = ""
		state["held"] = 0
		return
	if raw == state["pending"]:
		state["held"] = int(state["held"]) + 1
	else:
		state["pending"] = raw
		state["held"] = 1
	if int(state["held"]) >= int(rules.get("tier_hold", 2)):
		print("[production] %s goes from %s to %s (%s), step %d" % [town, str(state["tier"]).to_upper(), raw.to_upper(),
			_why(signals), now()])
		state["tier"] = raw
		state["pending"] = ""
		state["held"] = 0


func _why(signals: Dictionary) -> String:
	return "safety %s, short of %s, %s, %s, sold %s" % [signals["safety"],
		", ".join(signals["short"].keys()) if not signals["short"].is_empty() else "nothing",
		"full" if signals["full"] else "not full", signals["busy"], signals["sold"] if not signals["sold"].is_empty() else "nothing"]


## [param town]'s wants for its tier, most pressing first.
func _wants(town: String, signals: Dictionary) -> Array[String]:
	var tiers: Dictionary = rules.get("tiers", {})
	var out: Array[String] = []
	match tier(town):
		DEFEND:
			out.assign(tiers.get(DEFEND, []))
		WORK_UP:
			var sold: Array = signals["sold"].keys()
			sold.sort()
			for what: String in sold:
				for want: Variant in rules.get("work_up", {}).get(what, []):
					if str(want) not in out:
						out.append(str(want))
			for want: Variant in tiers.get(STOCK, []):
				if str(want) not in out:
					out.append(str(want))
		STOCK:
			var short: Dictionary = signals["short"]
			var order: Array = tiers.get(STOCK, [])
			out.assign(order.filter(func(want: Variant) -> bool: return short.has(str(want))))
			out.sort_custom(func(a: String, b: String) -> bool:
				return short[a] > short[b] or short[a] == short[b] and order.find(a) < order.find(b))
		SURPLUS:
			out.assign(tiers.get(SURPLUS, []))
	if signals["busy"] == QUIET and "rework" not in out:
		out.append("rework")
	# Raws worked up into a raw (the tanner's leather, decision 405) whatever
	# the tier, last: no other trade makes a thing of those tags.
	for want: Variant in rules.get("always_want", []):
		if str(want) not in out:
			out.append(str(want))
	return out


# --- Choosing work -------------------------------------------------------------------

func _choose(town: String, signals: Dictionary, cat: Dictionary) -> void:
	var wants := _wants(town, signals)
	var bids: Array[Dictionary] = []
	var ids: Array[String] = []
	ids.assign(_workshops.keys())
	ids.sort()
	for id in ids:
		var shop: Dictionary = _workshops[id]
		if shop["town"] != town or shop["job"] != 0 or not _present(shop["worker"], id):
			continue
		var bid := _bid(shop, wants, signals, cat)
		if not bid.is_empty():
			bids.append(bid)
	bids.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _before(a["key"], b["key"]))
	for bid in bids:
		var shop: Dictionary = _workshops[bid["workshop"]]
		if _start(bid, cat):
			shop["waited"] = 0
			_waits_told.erase(bid["workshop"])
		else:
			shop["waited"] = int(shop["waited"]) + 1
			var short := _short_of(town, bid, cat) if not _unpaid.has(bid["workshop"]) else ""
			var told := "%s %s" % [bid["recipe"], short]
			if _waits_told.get(bid["workshop"], "") != told:
				_waits_told[bid["workshop"]] = told
				print("[production] %s waits for %s: %s, step %d" % [bid["workshop"], bid["recipe"],
					"short of %s" % short if not short.is_empty() else "its maker can't pay for the materials" if _unpaid.has(bid["workshop"])
					else "its materials went to work that came first", now()])


## The work [param shop] would take on, with its place in the queue
## ({workshop, recipe, kind, want, job (an order's), rework, key}); {} for none.
func _bid(shop: Dictionary, wants: Array[String], signals: Dictionary, cat: Dictionary) -> Dictionary:
	var starved := 0 if int(shop["waited"]) >= int(rules.get("starve_after", 3)) else 1
	# Orders first: the first one; of the town's builds, the first whose
	# materials are in the store, else the first (decision 522: a stalled
	# build kept at the head, the next one built meanwhile).
	var first_build := 0
	for id in jobs():
		var each: Dictionary = _jobs[id]
		var builds_here: bool = each["kind"] == "build" and each["workshop"] == "" and each["trade"] == shop["trade"] \
				and each["town"] == shop["town"]
		if each["state"] != "queued" or not (each["workshop"] == shop["id"] or builds_here):
			continue
		if builds_here and not _affords(shop["town"], {"from": each.get("cost", {})}, false):
			if first_build == 0:
				first_build = id
			continue
		return _order_bid(shop, id, starved)
	if first_build != 0:
		return _order_bid(shop, first_build, starved)
	var recipes: Array = cat.values().filter(func(entry: Dictionary) -> bool:
		return _recipe_ok(entry) and entry["made"]["by"] == shop["trade"])
	recipes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		# A recipe marked "first" (the cook's roast, decision 405) is tried
		# before the others: what the hunt brings home is cooked, not left.
		if bool(a["made"].get("first", false)) != bool(b["made"].get("first", false)):
			return bool(a["made"].get("first", false))
		if signals["busy"] == BUSY and int(a["made"]["steps"]) != int(b["made"]["steps"]):
			return int(a["made"]["steps"]) < int(b["made"]["steps"])
		return str(a["id"]) < str(b["id"]))
	for want in wants:
		if want == "repair":
			var mend := _mend_bid(shop, cat)
			if not mend.is_empty():
				mend["key"] = [starved, 1, _tier_key(shop, cat[mend["recipe"]], want, signals), -int(shop["waited"]), shop["id"]]
				mend["want"] = want
				return mend
			continue
		for entry: Dictionary in recipes:
			var rework := 0
			if want == "rework":
				rework = _reworkable(shop["town"], entry["id"])
				if rework == 0:
					continue
			elif want == "repair" or not _serves(shop["town"], entry, want, cat):
				continue
			if not _affords(shop["town"], entry["made"], rework != 0):
				continue
			return {"workshop": shop["id"], "recipe": entry["id"], "kind": "rework" if rework != 0 else "make",
				"want": want, "job": 0, "rework": rework,
				"key": [starved, 1, _tier_key(shop, entry, want, signals), -int(shop["waited"]), shop["id"]]}
	return {}


## A mend [param shop] could take on (decision 414): the first thing banked
## in its town's store, by uid, worn below its most whose mend is by the
## shop's trade and whose mend's "from" the store has ({} for none).
func _mend_bid(shop: Dictionary, cat: Dictionary) -> Dictionary:
	for uid in stockpile.items(shop["town"]):
		var id := book().id_of(uid)
		var mend: Dictionary = cat.get(id, {}).get("mend", {})
		if not _mends(shop, str(mend.get("by", ""))) or book().condition_of(uid) < 0 or book().condition_of(uid) >= Items.condition_max(id):
			continue
		if _affords(shop["town"], mend, false):
			return {"workshop": shop["id"], "recipe": id, "kind": "work", "effect": "mend", "job": 0, "rework": uid}
	return {}


## Whether [param shop] does work that is [param by]'s: its trade, or the
## trade standing in for it (rules' stand_in: the carpenter for a fletcher)
## while its town has no one of that trade there (decision 428).
func _mends(shop: Dictionary, by: String) -> bool:
	if shop["trade"] == by:
		return true
	if str(rules.get("stand_in", {}).get(by, "")) != shop["trade"]:
		return false
	return not worker_ids(shop["town"]).any(func(id: String) -> bool:
		return by in _workers[id]["trades"] and not off_work(_workers[id]))


func _recipe_ok(entry: Dictionary) -> bool:
	var made: Variant = entry.get("made")
	return made is Dictionary and made.get("by") is String and made.get("from", {}) is Dictionary \
			and (made.get("steps") is int or made.get("steps") is float) and int(made["steps"]) > 0


## Whether making [param entry] serves [param want] in [param town]: of
## that tag ("goods": anything), and the shop not yet holding shop_cap of it.
func _serves(town: String, entry: Dictionary, want: String, cat: Dictionary) -> bool:
	if want != "goods" and want not in _tags_of(entry["id"], cat):
		return false
	var in_shop := stockpile.shop(town).filter(func(uid: int) -> bool: return book().id_of(uid) == entry["id"]).size()
	# A luxury (the smith's ring, decision 514) only up to luxury.stock: the
	# rich are few.
	if "luxury" in _tags_of(entry["id"], cat):
		return in_shop < int(rules.get("luxury", {}).get("stock", rules.get("shop_cap", 6)))
	return in_shop < int(rules.get("shop_cap", 6))


## A banked thing of [param id] no job holds (0 for none).
func _reworkable(town: String, id: String) -> int:
	for uid in stockpile.items(town):
		if book().id_of(uid) == id:
			return uid
	return 0


## A bid for queued job [param id] at [param shop].
func _order_bid(shop: Dictionary, id: int, starved: int) -> Dictionary:
	var each: Dictionary = _jobs[id]
	return {"workshop": shop["id"], "recipe": each["recipe"], "kind": each["kind"], "want": "order", "job": id,
		"rework": int(each.get("rework", 0)), "key": [starved, 0, 0.0, -int(shop["waited"]), shop["id"]]}


## Whether [param recipe] yields a raw [param town]'s next build lacks
## (522 amended (2)).
func _for_build(town: String, recipe: String, cat: Dictionary) -> bool:
	if not build_lacks.is_valid():
		return false
	var yields := Items.yield_of(recipe)
	if yields.is_empty() or not cat.has(recipe):
		return false
	var lacking: Dictionary = build_lacks.call(town)
	return yields.keys().any(func(what: Variant) -> bool: return lacking.has(str(what)))


## Whether [param town]'s stockpile has what [param made] needs: its
## "from", or for a rework one of its first resource.
## What [param town]'s store lacks for [param bid] ("wood 8 of 8, ore 1 of
## 5": short, of needed), "" when nothing (another workshop took it).
func _short_of(town: String, bid: Dictionary, cat: Dictionary) -> String:
	var queued: Dictionary = _jobs.get(int(bid["job"]), {})
	var made: Dictionary = {}
	if bid["kind"] == "build":
		made = {"from": queued.get("cost", {})}
	elif cat.has(bid["recipe"]):
		made = cat[bid["recipe"]].get("mend" if bid["kind"] == "work" else "made", {})
	var rework: bool = int(bid["rework"]) != 0 and bid["kind"] != "work"
	var parts: Array[String] = []
	var needs := _needs(made, rework)
	for what: String in needs:
		var lacking := int(needs[what]) - stockpile.count(town, what)
		if lacking > 0:
			parts.append("%s %d of %d" % [what, lacking, int(needs[what])])
	return ", ".join(parts)


func _affords(town: String, made: Dictionary, rework: bool) -> bool:
	for what: String in _needs(made, rework):
		var have := stockpile.count(town, what)
		if have < int(_needs(made, rework)[what]):
			return false
	return true


func _needs(made: Dictionary, rework: bool) -> Dictionary:
	var from: Dictionary = made.get("from", {})
	if not rework:
		return from
	for what: String in from:
		if what in Stockpile.RESOURCES:
			return {what: 1}
	return {}


func _tier_key(shop: Dictionary, entry: Dictionary, want: String, signals: Dictionary) -> float:
	match tier(shop["town"]):
		DEFEND:
			var order: Array = rules.get("defend_trades", [])
			return float(order.find(shop["trade"]) if shop["trade"] in order else order.size())
		WORK_UP:
			for what: String in entry["made"].get("from", {}):
				if signals["sold"].has(what):
					return 0.0
			return 1.0
		STOCK:
			return -float(signals["short"].get(want, 0.0))
	return 0.0


static func _before(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false


## Starts [param bid]: its materials taken from the stockpile, its worker
## on it. False (nothing taken) if they're no longer there.
func _start(bid: Dictionary, cat: Dictionary) -> bool:
	var shop: Dictionary = _workshops[bid["workshop"]]
	var town: String = shop["town"]
	var queued: Dictionary = _jobs.get(int(bid["job"]), {})
	if int(bid["job"]) != 0 and queued.get("state") != "queued":
		return false  # Another workshop took it this tick.
	var mending: bool = bid["kind"] == "work"
	var made: Dictionary = {"from": queued["cost"], "steps": queued["steps"]} if bid["kind"] == "build" \
			else cat[bid["recipe"]]["mend"] if mending else cat[bid["recipe"]]["made"]
	var rework := int(bid["rework"])
	if rework != 0 and rework not in stockpile.items(town):
		return false
	var needs := _needs(made, rework != 0 and not mending)
	if not _affords(town, made, rework != 0 and not mending):
		return false
	# The town's meals (store.town_account tags: a cook's food) are made on
	# the town's account, like its own work: a cook at her loan cap still cooks.
	var on_town: bool = cat.has(bid["recipe"]) and cat[bid["recipe"]].get("tags", []).any(func(tag: Variant) -> bool:
		return str(tag) in rules.get("store", {}).get("town_account", []))
	# So is a raw the town's next build lacks (522 amended (2): the
	# tanner's leather while the inn waits on it), whatever its maker's purse.
	var for_build: bool = bid["kind"] == "make" and _for_build(town, bid["recipe"], cat)
	on_town = on_town or for_build
	if buy_materials.is_valid() and bid["kind"] in ["make", "rework"] and not on_town:
		var raws := {}
		for what: String in needs:
			if what in Stockpile.RESOURCES:
				raws[what] = int(needs[what])
		if not raws.is_empty() and not bool(buy_materials.call(town, str(shop["worker"]), raws)):
			_unpaid[bid["workshop"]] = true
			return false
	_unpaid.erase(bid["workshop"])
	var id: int = bid["job"] if int(bid["job"]) != 0 else _new_job(bid["kind"], bid["recipe"], shop)
	var each: Dictionary = _jobs[id]
	if for_build:
		each["account"] = true
	var reason := "job #%d" % id
	for what: String in needs:
		if what in Stockpile.RESOURCES:
			stockpile.take(town, what, int(needs[what]), reason)
			each["resources"][what] = int(needs[what])
		else:
			for i in int(needs[what]):
				var uid := _reworkable(town, what)
				stockpile.take_item(town, uid, reason)
				book().place(uid, "job:%d" % id)
				each["uids"].append(uid)
	if rework != 0:
		stockpile.take_item(town, rework, reason)
		book().place(rework, "job:%d" % id)
		each["uids"].append(rework)
	if mending:
		# The general job on a thing (decision 434): a mend is its effect
		# "mend", for the town (""), to_id the same id.
		each["kind"] = "work"
		each["effect"] = str(bid.get("effect", "mend"))
		each["for"] = ""
		each["to_id"] = bid["recipe"]
	elif each["kind"] != "build":
		each["kind"] = "rework" if rework != 0 else "make"
	each["workshop"] = shop["id"]
	each["state"] = "working"
	each["worker"] = shop["worker"]
	var level := int(workshop_level.call(shop)) if workshop_level.is_valid() else 1
	var speed := 1.0 + float(rules.get("level_speed", 0.25)) * maxi(level - 1, 0)
	each["needed"] = ceili(int(made["steps"]) / (2.0 if rework != 0 and not mending else 1.0) / speed)
	each["worked"] = 0
	each["last"] = now()
	shop["job"] = id
	print("[production] %s (%s) starts %s%s #%d at %s for %s, step %d; takes %s; done in %d steps" % [
		_workers[shop["worker"]]["name"], shop["trade"], "a mend of " if mending else "a rework of " if rework != 0 else "", bid["recipe"], id,
		bid["workshop"], bid["want"], now(), needs if not needs.is_empty() else "nothing", each["needed"]])
	return true


func _new_job(kind: String, recipe: String, shop: Dictionary) -> int:
	var id := _next_job
	_next_job += 1
	_jobs[id] = {"id": id, "kind": kind, "recipe": recipe, "town": shop["town"], "workshop": shop["id"], "worker": "",
		"state": "queued", "ordered": false, "rework": 0, "resources": {}, "uids": [], "needed": 0, "worked": 0, "last": 0,
		"trade": shop.get("trade", ""), "cost": {}, "steps": 0}
	return id


## A job building [param building_id] in [param town]: taken by the first
## free workshop of [param trade] there, ahead of what the town would
## choose; [param cost] taken from the stockpile when it starts,
## [param steps] of work; on_built when done. Its id.
func order_build(town: String, building_id: String, trade: String, cost: Dictionary, steps: int) -> int:
	var id := _new_job("build", building_id, {"town": town, "id": "", "trade": trade})
	_jobs[id]["ordered"] = true
	_jobs[id]["cost"] = cost.duplicate()
	_jobs[id]["steps"] = maxi(steps, 1)
	_jobs[id]["at"] = now()
	_town(town)
	print("[production] %s orders %s built by a %s (%s, %d steps)" % [town, building_id, trade, cost, steps])
	return id


## What [param each] took goes back to its town's stockpile.
func _give_back(each: Dictionary) -> void:
	var reason := "cancel job #%d" % int(each["id"])
	for what: String in each["resources"]:
		stockpile.deposit(each["town"], what, int(each["resources"][what]), reason)
	for uid: int in each["uids"]:
		stockpile.bank(each["town"], uid, reason, "", "", Vector2i(-1, -1), "")
	each["resources"] = {}
	each["uids"] = []


func _town(town: String) -> Dictionary:
	if not _towns.has(town):
		_towns[town] = {"tier": "", "pending": "", "held": 0, "sales": [], "upkeep": 0}
	return _towns[town]


# --- Saving --------------------------------------------------------------------------

## For the snapshot: {workers, workshops, jobs, next_job, towns}.
func to_dict() -> Dictionary:
	var saved_jobs := {}
	for id: int in _jobs:
		saved_jobs[str(id)] = _jobs[id].duplicate(true)
	var towns := {}
	for town: String in _towns:
		var state: Dictionary = _towns[town].duplicate(true)
		var window := int(rules.get("window", 6000))
		state["sales"] = state["sales"].filter(func(sale: Dictionary) -> bool: return int(sale["step"]) >= now() - window)
		towns[town] = state
	return {"trips": _trips.duplicate(), "workers": _workers.duplicate(true), "workshops": _workshops.duplicate(true), "jobs": saved_jobs,
		"next_job": _next_job, "towns": towns}


## to_dict's [param saved] over what is here (after the stockpile and the
## book). Anything that makes no sense is left out with a word; a job whose
## workshop is gone gives its materials back.
func from_dict(saved: Dictionary) -> void:
	var workers: Variant = saved.get("workers", {})
	if workers is Dictionary:
		for id: String in workers:
			var entry: Variant = workers[id]
			if not entry is Dictionary or not entry.get("trades") is Array:
				print("[production] the snapshot's worker %s makes no sense; left out" % id)
				continue
			add_worker(id, str(entry.get("name", id)), entry["trades"], str(entry.get("town", "")), str(entry.get("origin", "placeholder")),
				str(entry.get("type", "")))
			_workers[id]["purse"] = maxi(int(entry.get("purse", 0)), 0)
			_workers[id]["rent_due"] = int(entry.get("rent_due", _workers[id]["rent_due"]))
			_workers[id]["away"] = bool(entry.get("away", false))
			# Saves from before decision 353 have no needs: they come due afresh.
			var needs: Variant = entry.get("needs", {})
			if needs is Dictionary:
				for need: Variant in needs:
					_workers[id]["needs"][str(need)] = int(needs[need])
			_workers[id]["fed"] = str(entry.get("fed", ""))
			_workers[id]["wage_due"] = maxi(int(entry.get("wage_due", 0)), 0)
			_workers[id]["hunt_due"] = maxi(int(entry.get("hunt_due", 0)), 0)
			_workers[id]["owed"] = maxi(int(entry.get("owed", 0)), 0)
			_workers[id]["sick"] = bool(entry.get("sick", false))
			_workers[id]["apprentice"] = str(entry.get("apprentice", ""))
			_workers[id]["master"] = str(entry.get("master", ""))
			if entry.has("above_since"):
				_workers[id]["above_since"] = int(entry["above_since"])
			_workers[id]["loan"] = maxf(float(entry.get("loan", 0.0)), 0.0)
			_workers[id]["working_off"] = bool(entry.get("working_off", false)) and float(_workers[id]["loan"]) > 0.0
			_workers[id]["hungry_since"] = maxi(int(entry.get("hungry_since", 0)), 0)
			for each: String in MIND:
				if _workers[id].has(each) and (entry.get(each) is float or entry.get(each) is int):
					_workers[id][each] = clampi(int(entry[each]), 1, 10)
			# What they have heard, as companions' Hearsay keeps it.
			if entry.get("heard") is Array:
				_workers[id]["heard"] = entry["heard"].duplicate(true)
			# npc's card of them, kept as it is.
			if entry.get("card") is Dictionary:
				_workers[id]["card"] = entry["card"].duplicate(true)
			var last: Variant = entry.get("last_trade", {})
			if last is Dictionary and not last.is_empty():
				_workers[id]["last_trade"] = {"step": int(last.get("step", 0)), "what": str(last.get("what", "")),
					"gold": int(last.get("gold", 0)), "with": str(last.get("with", ""))}
	var workshops: Variant = saved.get("workshops", {})
	if workshops is Dictionary:
		for id: String in workshops:
			var entry: Variant = workshops[id]
			if not entry is Dictionary:
				continue
			add_workshop(id, str(entry.get("trade", "")), str(entry.get("town", "")))
			assign(id, str(entry.get("worker", "")))
			_workshops[id]["waited"] = int(entry.get("waited", 0))
	var towns: Variant = saved.get("towns", {})
	if towns is Dictionary:
		for town: String in towns:
			var entry: Variant = towns[town]
			if entry is Dictionary:
				var state := _town(town)
				state["tier"] = str(entry.get("tier", ""))
				state["pending"] = str(entry.get("pending", ""))
				state["held"] = int(entry.get("held", 0))
				state["upkeep"] = int(entry.get("upkeep", 0))
				for sale: Variant in entry.get("sales", []):
					if sale is Dictionary:
						state["sales"].append({"step": int(sale.get("step", 0)), "what": str(sale.get("what", "")),
							"count": int(sale.get("count", 0))})
	_next_job = maxi(int(saved.get("next_job", 1)), 1)
	var trips: Variant = saved.get("trips", {})
	if trips is Dictionary:
		for id: Variant in trips:
			_trips[str(id)] = int(trips[id])
	var saved_jobs: Variant = saved.get("jobs", {})
	if saved_jobs is Dictionary:
		for key: Variant in saved_jobs:
			var entry: Variant = saved_jobs[key]
			if not entry is Dictionary:
				continue
			var each := {"id": int(key), "kind": str(entry.get("kind", "make")), "recipe": str(entry.get("recipe", "")),
				"town": str(entry.get("town", "")), "workshop": str(entry.get("workshop", "")), "worker": str(entry.get("worker", "")),
				"state": str(entry.get("state", "queued")), "ordered": bool(entry.get("ordered", false)),
				"rework": int(entry.get("rework", 0)), "resources": {}, "uids": [], "needed": int(entry.get("needed", 0)),
				"worked": int(entry.get("worked", 0)), "last": int(entry.get("last", 0)),
				"trade": str(entry.get("trade", "")), "cost": {}, "steps": int(entry.get("steps", 0))}
			if each["kind"] in ["mend", "work"]:
				# 414's "mend" jobs are the general job's effect "mend" now.
				each["effect"] = str(entry.get("effect", "mend"))
				each["kind"] = "work"
				each["for"] = str(entry.get("for", ""))
				each["to_id"] = str(entry.get("to_id", each["recipe"]))
				each["fee"] = maxi(int(entry.get("fee", 0)), 0)
				each["payer"] = str(entry.get("payer", ""))
			if each["kind"] == "return":
				each["who"] = str(entry.get("who", ""))
				each["who_kind"] = str(entry.get("who_kind", ""))
				each["opened"] = int(entry.get("opened", 0))
				each["place"] = str(entry.get("place", ""))
			var cost: Variant = entry.get("cost", {})
			if cost is Dictionary:
				for what: String in cost:
					each["cost"][what] = int(cost[what])
			var resources: Variant = entry.get("resources", {})
			if resources is Dictionary:
				for what: String in resources:
					each["resources"][what] = int(resources[what])
			for uid: Variant in entry.get("uids", []):
				if (uid is float or uid is int) and book().has(int(uid)):
					each["uids"].append(int(uid))
			_next_job = maxi(_next_job, each["id"] + 1)
			_jobs[each["id"]] = each
			# A return whose place is gone gives up in time (_advance), and a
			# thing handed in for someone stays theirs in its job: never lost.
			var own_job: bool = each["kind"] == "return" or not str(each.get("for", "")).is_empty()
			if not _workshops.has(each["workshop"]) and not (each["kind"] == "build" and each["state"] == "queued") 					and not own_job:
				print("[production] the snapshot's job #%d is at %s, which is gone; its materials go back" % [each["id"], each["workshop"]])
				_give_back(each)
				_jobs.erase(each["id"])
			elif each["state"] == "working" and not own_job:
				_workshops[each["workshop"]]["job"] = each["id"]
