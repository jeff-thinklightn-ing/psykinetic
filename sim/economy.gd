class_name Economy
extends RefCounted
## What things cost in a town, the players' own gold, and trade between
## them and the town (decision 280). Server only; World keeps one
## (World.economy), made by Main at boot from the snapshot ("economy":
## to_dict).
##
## Prices are worked out when asked, never stored. An item's value is its
## catalog "value", else what it is made from (made.from, each resource at
## rules' "value", each thing at its own value) and the work in it
## (made.steps / 600 x rules' "labour"), else its yield, else 1. The town's
## need scales it: short of what it wants (rules' "wants" by tag, more while
## it is threatened; "comfort" for raws) dearer up to "trade".max_factor,
## plenty cheaper down to min_factor.
##
## A player buys from a shop at its price, from their own gold: what its
## materials are worth and the sale tax on the rest go to the treasury (the
## stockpile's gold), and the rest to the purse of the resident who made it
## (the treasury's if no one did; decision 353 amended). The town buys
## from a player only what it is short of, at buy_ratio of its own price,
## and only while its treasury stays above gold_floor; the buy tax stays in
## the treasury. A player's gold is theirs: nothing takes it but buying.

## A town's count of residents on the dole changed (decision 353).
signal dole_changed(town: String, count: int)

const PATH := "res://levels/economy.json"
const TREASURY := "the town"
const SELL := "sell"
const BUY := "buy"
## A thing made of things is valued that many steps down at most.
const MAX_DEPTH := 4

var rules := {}
var stockpile: Stockpile
var production: Production
## () -> int: the World's steps.
var clock := Callable()
## () -> Dictionary: id -> definition (Items' by default), what prices read.
var catalog := Callable()
## (town, building kind) -> bool: whether it stands (Towns', set by Main),
## for a need met at a building. None stands while unset.
var building_stands := Callable()
## Town -> how many it fed or let go hungry, as last told (dole_changed).
var _dole := {}

## Player id -> gold.
var _purses: Dictionary[String, int] = {}
## Player id -> [{step, count, why, gold}], the last LOG_SIZE changes.
var _log: Dictionary[String, Array] = {}
const LOG_SIZE := 50


func _init(saved := {}, with_stockpile: Stockpile = null, with_production: Production = null, with_clock := Callable(),
		with_rules := {}, with_catalog := Callable()) -> void:
	clock = with_clock
	stockpile = with_stockpile if with_stockpile != null else Stockpile.new({}, with_clock)
	production = with_production if with_production != null else Production.new({}, stockpile, null, with_clock, with_rules)
	rules = with_rules if not with_rules.is_empty() else Production.read_rules(PATH)
	catalog = with_catalog if with_catalog.is_valid() else Economy.items_defs
	from_dict(saved)


## Every item definition, by id.
static func items_defs() -> Dictionary:
	var out := {}
	for id: String in Items.ids():
		out[id] = Items.def(id)
	return out


## [param amount] of gold changing hands in a [param kind] of transaction
## ("sale", "buy", "trade", "wage": rules' "tax"), split [to the town, to
## the payee]: the tax rounded down, the payee the rest.
static func taxed(amount: int, kind: String, with_rules: Dictionary) -> Array[int]:
	var cut := int(floor(amount * float(with_rules.get("tax", {}).get(kind, 0.0))))
	return [cut, amount - cut]


func now() -> int:
	return int(clock.call()) if clock.is_valid() else 0


# --- Players' gold -------------------------------------------------------------------

## [param player_id]'s gold.
func gold(player_id: String) -> int:
	return int(_purses.get(player_id, 0))


## Gives [param player_id] [param amount] gold (taken, for an amount under
## 0, never below none) for [param why] ("purse", "sold sword"...): their
## gold now.
func add_gold(player_id: String, amount: int, why := "") -> int:
	if player_id.is_empty():
		return 0
	var had := gold(player_id)
	var now_gold := maxi(had + amount, 0)
	_purses[player_id] = now_gold
	var lines: Array = _log.get(player_id, [])
	lines.append({"step": now(), "count": now_gold - had, "why": why, "gold": now_gold})
	if lines.size() > LOG_SIZE:
		lines.pop_front()
	_log[player_id] = lines
	print("[economy] %s %s %d gold (%s): %d now, step %d" % [player_id, "got" if now_gold >= had else "spent",
		absi(now_gold - had), why if why != "" else "no reason said", now_gold, now()])
	return now_gold


## [param player_id]'s last changes of gold, oldest first.
func gold_log(player_id: String) -> Array:
	return _log.get(player_id, []).duplicate(true)


# --- Prices --------------------------------------------------------------------------

## What [param id] is worth, before the town's need: at least 1.
func value_of(id: String, cat := {}, depth := 0) -> int:
	if cat.is_empty():
		cat = catalog.call()
	var def: Dictionary = cat.get(id, {})
	if def.has("value") and int(def["value"]) > 0:
		return int(def["value"])
	var values: Dictionary = rules.get("value", {})
	var made: Variant = def.get("made", {})
	if made is Dictionary and not made.is_empty() and depth < MAX_DEPTH:
		var total := 0.0
		var from: Dictionary = made.get("from", {})
		for what: String in from:
			var each := float(values.get(what, 1)) if what in Stockpile.RESOURCES or not cat.has(what) \
					else float(value_of(what, cat, depth + 1))
			total += each * int(from[what])
		total += float(made.get("steps", 0)) / 600.0 * float(rules.get("labour", 1))
		return maxi(roundi(total), 1)
	var yields: Variant = def.get("yield", {})
	if yields is Dictionary and not yields.is_empty():
		var total := 0.0
		for what: String in yields:
			total += float(values.get(what, 1)) * int(yields[what])
		return maxi(roundi(total), 1)
	return 1


## How short [param town] is of [param id]: 0..1 short of what it wants
## (1 for none at all), under 0 for more than it wants (-1 for twice as
## much, or for something it does not want at all).
func short_of(town: String, id: String, cat := {}) -> float:
	if cat.is_empty():
		cat = catalog.call()
	var def: Dictionary = cat.get(id, {})
	var yields: Variant = def.get("yield", {})
	if yields is Dictionary and not yields.is_empty():
		var comfort: Dictionary = rules.get("comfort", {})
		var most := -1.0
		for what: String in yields:
			most = maxf(most, _short(stockpile.count(town, what), int(comfort.get(what, 0))))
		return most
	var wants: Dictionary = rules.get("wants", {})
	var extra: Dictionary = rules.get("uneasy_extra", {}) if production.tier(town) == Production.DEFEND else {}
	var have := _gear_by_tag(town, cat)
	var most := -1.0
	for tag: Variant in def.get("tags", []):
		if wants.has(tag):
			most = maxf(most, _short(int(have.get(tag, 0)), int(wants[tag]) + int(extra.get(tag, 0))))
	return most


static func _short(have: int, want: int) -> float:
	if want <= 0:
		return -1.0
	return clampf(float(want - have) / want, -1.0, 1.0)


## [param town]'s gear (store and shop) counted by tag.
func _gear_by_tag(town: String, cat: Dictionary) -> Dictionary:
	var out := {}
	var uids := stockpile.items(town)
	uids.append_array(stockpile.shop(town))
	for uid in uids:
		for tag: Variant in cat.get(stockpile.book.id_of(uid), {}).get("tags", []):
			out[str(tag)] = int(out.get(str(tag), 0)) + 1
	return out


## The need's scale on a price: up to max_factor when short of all of it,
## down to min_factor for plenty.
func factor(short: float) -> float:
	var trade: Dictionary = rules.get("trade", {})
	var most := float(trade.get("max_factor", 2.0))
	var least := float(trade.get("min_factor", 0.5))
	return 1.0 + short * (most - 1.0) if short >= 0.0 else 1.0 + -short * (least - 1.0)


## What [param town] asks for [param id] in its shop ([param side] SELL),
## or pays a player for one (BUY: buy_ratio of that, before the buy tax).
## At least 1.
func price(town: String, id: String, side := SELL, cat := {}) -> int:
	if cat.is_empty():
		cat = catalog.call()
	var asked := maxi(roundi(value_of(id, cat) * factor(short_of(town, id, cat))), 1)
	if side == BUY:
		return maxi(int(floor(asked * float(rules.get("trade", {}).get("buy_ratio", 0.5)))), 1)
	return asked


## What [param id]'s materials are worth, before the town's need: its
## recipe's from (each resource at rules' "value", each thing at its own
## value); 0 for a thing not made.
func materials(id: String, cat := {}) -> int:
	if cat.is_empty():
		cat = catalog.call()
	var made: Variant = cat.get(id, {}).get("made", {})
	if not made is Dictionary or made.is_empty():
		return 0
	var values: Dictionary = rules.get("value", {})
	var total := 0.0
	var from: Dictionary = made.get("from", {})
	for what: String in from:
		var each := float(values.get(what, 1)) if what in Stockpile.RESOURCES or not cat.has(what) 				else float(value_of(what, cat, 1))
		total += each * int(from[what])
	return roundi(total)


## Whether [param town] would buy [param id] from a player now, and why
## not: "" for yes.
func refuses(town: String, id: String, cat := {}) -> String:
	if cat.is_empty():
		cat = catalog.call()
	if not cat.has(id):
		return "the town has no use for that"
	var yields: Variant = cat[id].get("yield", {})
	if yields is Dictionary and yields.has("gold"):
		return "gold is given, not sold: put it in the depot"
	if short_of(town, id, cat) <= 0.0:
		return "the town has enough of that"
	var pays: int = Economy.taxed(price(town, id, BUY, cat), "buy", rules)[1]
	if stockpile.count(town, "gold") - pays < int(rules.get("gold_floor", 0)):
		return "the town can't pay for it now"
	return ""


## [param town]'s shop, for a shop panel: [{uid, id, price}] by uid.
func goods(town: String) -> Array[Dictionary]:
	var cat: Dictionary = catalog.call()
	var out: Array[Dictionary] = []
	var uids := stockpile.shop(town)
	uids.sort()
	for uid in uids:
		var id := stockpile.book.id_of(uid)
		out.append({"uid": uid, "id": id, "price": price(town, id, SELL, cat)})
	return out


## What [param town] would pay for each of [param ids] (the things a player
## carries): id -> gold paid, the tax taken; the ones it won't buy left out.
func offers(town: String, ids: Array) -> Dictionary:
	var cat: Dictionary = catalog.call()
	var out := {}
	for id: Variant in ids:
		var key := str(id)
		if not key.is_empty() and not out.has(key) and refuses(town, key, cat).is_empty():
			out[key] = Economy.taxed(price(town, key, BUY, cat), "buy", rules)[1]
	return out


# --- Trade ---------------------------------------------------------------------------

## [param player_id] buys [param uid] from [param town]'s shop at its price:
## {ok, price, why}. On ok the thing is out of the shop, held by nothing
## (the caller puts it somewhere), the gold paid out.
func buy(player_id: String, town: String, uid: int) -> Dictionary:
	if uid not in stockpile.shop(town):
		return {"ok": false, "why": "that is no longer for sale"}
	var id := stockpile.book.id_of(uid)
	var cost := price(town, id)
	if gold(player_id) < cost:
		return {"ok": false, "price": cost, "why": "not enough gold (%d)" % cost}
	var maker := stockpile.maker_of(town, uid)
	if not stockpile.take_from_shop(town, uid, "sold:%s" % player_id):
		return {"ok": false, "why": "that is no longer for sale"}
	add_gold(player_id, -cost, "bought %s" % id)
	_sale(town, maker, id, cost, "sale:%s" % player_id, "sold %s" % id)
	stockpile.book.note(uid, "bought", "by %s at %s for %d gold" % [player_id, town, cost])
	production.note_sale(town, id, 1)
	return {"ok": true, "price": cost, "id": id}


## [param town] buys [param id] from [param player_id], if it would
## (refuses): {ok, paid, why}, the treasury paying, the buy tax kept in it.
## The thing itself is the caller's to bank (World._bank_thing, or the shop).
func sell(player_id: String, town: String, id: String) -> Dictionary:
	var cat: Dictionary = catalog.call()
	var why := refuses(town, id, cat)
	if not why.is_empty():
		return {"ok": false, "why": why}
	var pays: int = Economy.taxed(price(town, id, BUY, cat), "buy", rules)[1]
	if not stockpile.take(town, "gold", pays, "bought:%s" % player_id):
		return {"ok": false, "why": "the town can't pay for it now"}
	add_gold(player_id, pays, "sold %s" % id)
	return {"ok": true, "paid": pays, "id": id}


# --- Residents' trade (decision 353) -------------------------------------------------

## Each resident (a Production worker not away) meets their needs from
## their purse on the world tick, each need (rules' "folk" "needs") on its
## own clock: a meal (tags) is bought from the shop at its price (split as
## a player's buy: materials and tax to the treasury, the rest its maker's), only past keep_in_shop of
## them so players find one; else the store's food at its value x need,
## paid into the treasury; else, broke, the town feeds them from the store
## (the dole); else they go hungry. A service is paid to a resident of its
## trade there (the trade tax to the treasury) or, for a building's
## (the inn's bed), to the treasury while it stands. One they can't pay for
## or can't get waits till it is next due: nobody goes into debt. Above
## rich_above gold, needs come due rich_every as often. Gold only moves:
## nothing here makes any. Each trade is a ledger line (Stockpile.note) and
## the worker's last_trade; Production.on_dole a signal.
func tick() -> void:
	var folk: Dictionary = rules.get("folk", {})
	var needs: Dictionary = folk.get("needs", {})
	if needs.is_empty():
		return
	var cat: Dictionary = catalog.call()
	var at := now()
	var names: Array = needs.keys()
	names.sort()
	var skip: Dictionary = folk.get("skip", {})
	var towns := {}
	for id in production.worker_ids():
		var who := production.worker(id)
		if bool(who["away"]) or str(who["town"]).is_empty():
			continue
		towns[who["town"]] = true
		for need: String in names:
			var rule: Dictionary = needs[need]
			var every := int(rule.get("every", 0))
			if every <= 0 or who["trades"].any(func(trade: String) -> bool: return need in skip.get(trade, [])):
				continue
			var due := production.need_due(id, need)
			if due == 0:
				production.set_need_due(id, need, at + every)
				continue
			if at < due:
				continue
			_meet(id, need, rule, cat)
			var rich := folk.has("rich_above") and int(production.worker(id)["purse"]) > int(folk["rich_above"])
			production.set_need_due(id, need, at + maxi(int(every * (float(folk.get("rich_every", 1.0)) if rich else 1.0)), 1))
	for town: String in _dole:
		towns[town] = true
	var keys: Array = towns.keys()
	keys.sort()
	for town: String in keys:
		var count := production.on_dole(town)
		if count != int(_dole.get(town, 0)):
			_dole[town] = count
			dole_changed.emit(town, count)


## What [param town]'s store asks a resident for one of resource
## [param what]: its value, scaled by how short of comfort the town is.
func raw_price(town: String, what: String) -> int:
	var value := float(rules.get("value", {}).get(what, 1))
	var short := _short(stockpile.count(town, what), int(rules.get("comfort", {}).get(what, 0)))
	return maxi(roundi(value * factor(short)), 1)


func _meet(id: String, need: String, rule: Dictionary, cat: Dictionary) -> void:
	if rule.has("tags"):
		_eat(id, rule, cat)
	elif rule.has("building"):
		_stay(id, need, rule)
	elif rule.has("trade"):
		_hire(id, need, rule)


func _eat(id: String, rule: Dictionary, cat: Dictionary) -> void:
	var who := production.worker(id)
	var town: String = who["town"]
	var tags: Array = rule["tags"]
	var food := goods(town).filter(func(each: Dictionary) -> bool:
		return cat.get(each["id"], {}).get("tags", []).any(func(tag: Variant) -> bool: return tag in tags))
	if food.size() > int(rules.get("folk", {}).get("keep_in_shop", 0)):
		food.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a["price"] < b["price"] or a["price"] == b["price"] and a["uid"] < b["uid"])
		var pick: Dictionary = food[0]
		var cost := int(pick["price"])
		if int(who["purse"]) >= cost:
			var thing := Items.name_of(pick["id"])
			var maker := stockpile.maker_of(town, pick["uid"])
			stockpile.take_from_shop(town, pick["uid"], "folk:%s" % id)
			stockpile.book.end(pick["uid"], "eaten", "by %s at %s" % [who["name"], town])
			production.spend(id, cost, "a %s" % thing)
			var seller := _sale(town, maker, pick["id"], cost, "folk:%s" % id, "sold a %s to %s" % [thing, who["name"]])
			production.note_meal(id, "bought")
			production.note_trade(id, "bought a %s" % thing, cost, seller)
			if seller != TREASURY:
				production.note_trade(maker, "sold a %s" % thing, cost, who["name"])
			stockpile.note(town, pick["id"], cost, "folk:%s" % id, "%s bought a %s from %s for %d gold" % [who["name"], thing, seller, cost])
			return
	var store := str(rule.get("store", ""))
	if not store.is_empty() and stockpile.has(town, store):
		var cost := raw_price(town, store)
		if int(who["purse"]) >= cost:
			production.spend(id, cost, "%s from the store" % store)
			stockpile.take(town, store, 1, "folk:%s" % id)
			stockpile.deposit(town, "gold", cost, "folk:%s" % id, "%s bought %s from the store for %d gold" % [who["name"], store, cost])
			production.note_meal(id, "store")
			production.note_trade(id, "bought %s from the store" % store, cost, TREASURY)
			return
		stockpile.take(town, store, 1, "dole:%s" % id)
		stockpile.note(town, store, 0, "dole:%s" % id, "the town fed %s, who has no gold" % who["name"])
		production.note_meal(id, "dole")
		return
	if str(who["fed"]) != "hungry":
		stockpile.note(town, store, 0, "hungry:%s" % id, "%s went hungry: nothing to eat" % who["name"])
	production.note_meal(id, "hungry")


func _stay(id: String, need: String, rule: Dictionary) -> void:
	var who := production.worker(id)
	var town: String = who["town"]
	var fee := int(rule.get("fee", 0))
	var what := str(rule.get("what", need))
	if fee <= 0 or int(who["purse"]) < fee or not building_stands.is_valid() \
			or not building_stands.call(town, str(rule["building"])):
		return
	production.spend(id, fee, what)
	stockpile.deposit(town, "gold", fee, "folk:%s" % id, "%s paid %d gold for %s" % [who["name"], fee, what])
	production.note_trade(id, what, fee, TREASURY)


func _hire(id: String, need: String, rule: Dictionary) -> void:
	var who := production.worker(id)
	var town: String = who["town"]
	var fee := int(rule.get("fee", 0))
	var what := str(rule.get("what", need))
	var trade := str(rule["trade"])
	if fee <= 0 or int(who["purse"]) < fee:
		return
	# The one of that trade with the least gold, so it spreads.
	var best := ""
	var least := 0
	for other in production.worker_ids(town):
		var them := production.worker(other)
		if other == id or bool(them["away"]) or trade not in them["trades"]:
			continue
		if best.is_empty() or int(them["purse"]) < least:
			best = other
			least = int(them["purse"])
	if best.is_empty():
		return
	production.spend(id, fee, what)
	var seller := _pay(town, best, fee, "trade", "%s for %s" % [what, who["name"]])
	production.note_trade(id, what, fee, seller)
	production.note_trade(best, "%s for %s" % [what, who["name"]], fee, who["name"])
	stockpile.note(town, need, fee, "folk:%s" % id, "%s paid %s %d gold for %s" % [who["name"], seller, fee, what])


## A made thing [param id] sold from [param town]'s shop for
## [param cost], made by worker [param maker] (decision 353 amended): what
## its materials are worth goes to the treasury (the town's food, ore and
## wood paid for), the sale tax on the rest too, and the maker the rest,
## their labour. All of it to the treasury for no such worker. Who was
## paid: the maker's name or TREASURY.
func _sale(town: String, maker: String, id: String, cost: int, by: String, why: String) -> String:
	var worker := production.worker(maker) if not maker.is_empty() else {}
	if worker.is_empty():
		stockpile.deposit(town, "gold", cost, by, why)
		return TREASURY
	var stuff := mini(materials(id), cost)
	var split := Economy.taxed(cost - stuff, "sale", rules)
	if stuff + split[0] > 0:
		stockpile.deposit(town, "gold", stuff + split[0], "tax:sale", "%s: materials %d, tax %d" % [why, stuff, split[0]])
	production.pay(maker, split[1], why)
	return str(worker["name"])


## [param amount] paid to worker [param payee] in [param town] for a
## [param kind] of transaction, the tax to the treasury (all of it, for no
## such worker): who was paid, their name or TREASURY.
func _pay(town: String, payee: String, amount: int, kind: String, why: String) -> String:
	var worker := production.worker(payee) if not payee.is_empty() else {}
	if worker.is_empty():
		stockpile.deposit(town, "gold", amount, "folk", why)
		return TREASURY
	var split := Economy.taxed(amount, kind, rules)
	if split[0] > 0:
		stockpile.deposit(town, "gold", split[0], "tax:folk", why)
	production.pay(payee, split[1], why)
	return str(worker["name"])


# --- Saving --------------------------------------------------------------------------

## For the snapshot: {purses: {player id: gold}, log}.
func to_dict() -> Dictionary:
	return {"purses": _purses.duplicate(), "log": _log.duplicate(true)}


func from_dict(saved: Dictionary) -> void:
	var purses: Variant = saved.get("purses", {})
	if purses is Dictionary:
		for id: Variant in purses:
			var value: Variant = purses[id]
			if value is int or value is float:
				_purses[str(id)] = maxi(int(value), 0)
	var lines: Variant = saved.get("log", {})
	if lines is Dictionary:
		for id: Variant in lines:
			if lines[id] is Array:
				_log[str(id)] = lines[id]
