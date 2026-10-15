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
## Workers are paid a wage from the town's gold when a job is done, never
## below rules' gold_floor; they pay rent from their purse every rent_every
## steps, which leaves the economy (the town's upkeep). Rules: levels/economy.json.
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

## Id -> {id, name, trades, town, origin, purse, rent_due, away}.
var _workers: Dictionary[String, Dictionary] = {}
## Id -> {id, trade, town, worker, job, waited}.
var _workshops: Dictionary[String, Dictionary] = {}
## Id -> {id, kind (make, rework), recipe, town, workshop, worker, state
## (queued, working), ordered, resources, uids, needed, worked, last}.
var _jobs: Dictionary[int, Dictionary] = {}
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
		if made is Dictionary and not made.is_empty():
			out[id] = {"id": id, "tags": def.get("tags", []), "made": made}
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
func add_worker(id: String, worker_name: String, trades: Array, town: String, origin := "placeholder") -> bool:
	if id.is_empty() or _workers.has(id):
		return false
	var list: Array[String] = []
	list.assign(trades.map(func(trade: Variant) -> String: return str(trade)))
	_workers[id] = {"id": id, "name": worker_name, "trades": list, "town": town, "origin": origin, "purse": 0,
		"rent_due": now() + int(rules.get("rent_every", 6000)), "away": false}
	_town(town)
	return true


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


## Whether [param town] has a "build" job queued or under way.
func building_in(town: String) -> bool:
	return _jobs.values().any(func(each: Dictionary) -> bool: return each["kind"] == "build" and each["town"] == town)


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
			each["worked"] = int(each["worked"]) + at - int(each["last"])
		each["last"] = at
		if int(each["worked"]) >= int(each["needed"]):
			_finish(each, cat)


func _present(worker_id: String, workshop_id: String) -> bool:
	var worker_record: Dictionary = _workers.get(worker_id, {})
	var shop: Dictionary = _workshops.get(workshop_id, {})
	return not worker_record.is_empty() and not worker_record["away"] and shop.get("worker", "") == worker_id \
			and (not workshop_open.is_valid() or workshop_open.call(shop))


func _finish(each: Dictionary, cat: Dictionary) -> void:
	var worker_record: Dictionary = _workers[each["worker"]]
	var made_at := "%s at %s" % [worker_record["name"], each["workshop"]]
	var uid := 0
	if each["kind"] == "build":
		if on_built.is_valid():
			on_built.call(each["town"], each["recipe"])
	elif each["kind"] == "rework":
		uid = int(each["uids"][0])
		book().place(uid, "")
		book().note(uid, "reworked", made_at)
	else:
		uid = book().mint(each["recipe"], "made", made_at)
		# Gear it was made from is in what it became.
		for used: int in each["uids"]:
			book().end(used, "used", "made into %s #%d" % [each["recipe"], uid])
	each["uids"] = []
	if uid != 0:
		stockpile.stock_shop(each["town"], uid, worker_record["name"], worker_record["id"])
	# The wage, less its tax, which stays in the treasury.
	var wage: int = taxed(int(rules.get("wage", 0)), "wage", rules)[1]
	var floor_gold := int(rules.get("gold_floor", 0))
	var paid := wage > 0 and stockpile.count(each["town"], "gold") - wage >= floor_gold \
			and stockpile.take(each["town"], "gold", wage, "wage:%s" % worker_record["id"])
	if paid:
		worker_record["purse"] = int(worker_record["purse"]) + wage
	print("[production] %s finished %s #%d (%s), step %d; %s" % [made_at, each["recipe"], uid, each["kind"], now(),
		"paid %d gold" % wage if paid else "unpaid (the town's gold is at its floor)" if wage > 0 else "no wage"])
	var shop: Dictionary = _workshops.get(each["workshop"], {})
	if not shop.is_empty() and shop["job"] == each["id"]:
		shop["job"] = 0
	_jobs.erase(int(each["id"]))


func _rent(at: int) -> void:
	var every := int(rules.get("rent_every", 6000))
	var rent := int(rules.get("rent", 0))
	var ids: Array[String] = []
	ids.assign(_workers.keys())
	ids.sort()
	for id in ids:
		var worker_record: Dictionary = _workers[id]
		if at < int(worker_record["rent_due"]):
			continue
		worker_record["rent_due"] = at + every
		var pay := mini(rent, int(worker_record["purse"]))
		if pay <= 0:
			continue
		worker_record["purse"] = int(worker_record["purse"]) - pay
		var town := _town(worker_record["town"])
		town["upkeep"] = int(town["upkeep"]) + pay
		print("[production] %s paid %d gold rent to %s's upkeep, step %d (%d left)" % [worker_record["name"], pay,
			worker_record["town"], at, worker_record["purse"]])


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
	return {"safety": safety, "short": short, "full": full, "busy": busy, "sold": sold, "raw_tier": raw}


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
	return SAFE


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
		else:
			shop["waited"] = int(shop["waited"]) + 1
			print("[production] %s waits for %s: its materials went to work that came first (%d time%s)" % [
				bid["workshop"], bid["recipe"], shop["waited"], "" if shop["waited"] == 1 else "s"])


## The work [param shop] would take on, with its place in the queue
## ({workshop, recipe, kind, want, job (an order's), rework, key}); {} for none.
func _bid(shop: Dictionary, wants: Array[String], signals: Dictionary, cat: Dictionary) -> Dictionary:
	var starved := 0 if int(shop["waited"]) >= int(rules.get("starve_after", 3)) else 1
	for id in jobs():
		var each: Dictionary = _jobs[id]
		var builds_here: bool = each["kind"] == "build" and each["workshop"] == "" and each["trade"] == shop["trade"] \
				and each["town"] == shop["town"]
		if each["state"] == "queued" and (each["workshop"] == shop["id"] or builds_here):
			return {"workshop": shop["id"], "recipe": each["recipe"], "kind": each["kind"], "want": "order", "job": id,
				"rework": int(each.get("rework", 0)), "key": [starved, 0, 0.0, -int(shop["waited"]), shop["id"]]}
	var recipes: Array = cat.values().filter(func(entry: Dictionary) -> bool:
		return _recipe_ok(entry) and entry["made"]["by"] == shop["trade"])
	recipes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if signals["busy"] == BUSY and int(a["made"]["steps"]) != int(b["made"]["steps"]):
			return int(a["made"]["steps"]) < int(b["made"]["steps"])
		return str(a["id"]) < str(b["id"]))
	for want in wants:
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
	return in_shop < int(rules.get("shop_cap", 6))


## A banked thing of [param id] no job holds (0 for none).
func _reworkable(town: String, id: String) -> int:
	for uid in stockpile.items(town):
		if book().id_of(uid) == id:
			return uid
	return 0


## Whether [param town]'s stockpile has what [param made] needs: its
## "from", or for a rework one of its first resource.
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
	var made: Dictionary = {"from": queued["cost"], "steps": queued["steps"]} if bid["kind"] == "build" \
			else cat[bid["recipe"]]["made"]
	var rework := int(bid["rework"])
	if rework != 0 and rework not in stockpile.items(town):
		return false
	var needs := _needs(made, rework != 0)
	if not _affords(town, made, rework != 0):
		return false
	var id: int = bid["job"] if int(bid["job"]) != 0 else _new_job(bid["kind"], bid["recipe"], shop)
	var each: Dictionary = _jobs[id]
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
	if each["kind"] != "build":
		each["kind"] = "rework" if rework != 0 else "make"
	each["workshop"] = shop["id"]
	each["state"] = "working"
	each["worker"] = shop["worker"]
	var level := int(workshop_level.call(shop)) if workshop_level.is_valid() else 1
	var speed := 1.0 + float(rules.get("level_speed", 0.25)) * maxi(level - 1, 0)
	each["needed"] = ceili(int(made["steps"]) / (2.0 if rework != 0 else 1.0) / speed)
	each["worked"] = 0
	each["last"] = now()
	shop["job"] = id
	print("[production] %s (%s) starts %s%s #%d at %s for %s, step %d; takes %s; done in %d steps" % [
		_workers[shop["worker"]]["name"], shop["trade"], "a rework of " if rework != 0 else "", bid["recipe"], id,
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
	return {"workers": _workers.duplicate(true), "workshops": _workshops.duplicate(true), "jobs": saved_jobs,
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
			add_worker(id, str(entry.get("name", id)), entry["trades"], str(entry.get("town", "")), str(entry.get("origin", "placeholder")))
			_workers[id]["purse"] = maxi(int(entry.get("purse", 0)), 0)
			_workers[id]["rent_due"] = int(entry.get("rent_due", _workers[id]["rent_due"]))
			_workers[id]["away"] = bool(entry.get("away", false))
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
			if not _workshops.has(each["workshop"]) and not (each["kind"] == "build" and each["state"] == "queued"):
				print("[production] the snapshot's job #%d is at %s, which is gone; its materials go back" % [each["id"], each["workshop"]])
				_give_back(each)
				_jobs.erase(each["id"])
			elif each["state"] == "working":
				_workshops[each["workshop"]]["job"] = each["id"]
