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
## Hidden types (npc's 393) with a rules entry of their own here: buy and
## sell factors on their trade, and a scoundrel's repay share.
const TYPE_RULES: Array[String] = ["merchant", "scoundrel"]
signal dole_changed(town: String, count: int)
## A player was paid gold the town owed them for goods they banked
## (decision 498), off any request of theirs: World tells their client.
signal owed_paid(player_id: String, gold: int)

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
## Town -> resource -> the last price a unit the store paid for it
## (decision 498): a maker never buys under it.
var _paid: Dictionary = {}
## Hauler id -> the step they last carried a load (who carries next).
var _hauled: Dictionary = {}
## "<worker>/<what>" told the store can't pay (said once till it can).
var _cant_pay: Dictionary = {}
## Player id -> {town: gold the town owes them for goods they banked}.
var _player_owed: Dictionary = {}
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
	var classes: Dictionary = with_rules.get("tax_class", {})
	var taxes: Dictionary = with_rules.get("tax", {})
	# A class with no rate of its own (rules before tax_class) pays tax.sale.
	var rate := float(classes[kind]) if classes.has(kind) else float(taxes.get(kind, taxes.get("sale", 0.0) if kind in GOODS_CLASSES else 0.0))
	var cut := int(floor(amount * rate))
	return [cut, amount - cut]


const GOODS_CLASSES: Array[String] = ["staple", "made", "luxury"]


## The tax class a sale of thing [param id] pays (decision 498; Jeff: "taxes
## can be most higher on luxury goods which the rich prefer then wages are
## paid by town"): "luxury" for a thing tagged luxury, "staple" for food and
## the raw resources, "made" for the rest. Rates in economy.json tax_class.
static func goods_class(id: String) -> String:
	var tags: Array = Items.def(id).get("tags", []) if not Items.def(id).is_empty() else []
	if "luxury" in tags:
		return "luxury"
	if "food" in tags or id in Stockpile.RESOURCES or not Items.yield_of(id).is_empty():
		return "staple"
	return "made"


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
## a player's buy: materials and tax to the treasury, the rest its
## maker's), only past keep_in_shop of them so players find one; else the
## store's food (its meat when it has none, decision 405) at its value x
## need, paid into the treasury. One short of
## gold borrows the rest from the town's bank (decision 354: _afford);
## only when the bank is empty, or they owe its cap, does the town feed
## them from the store (the dole), or they go hungry. A service is paid to
## a resident of its trade there (the trade tax to the treasury) or, for a
## building's (the inn's bed), to the treasury while it stands; one that
## can't be paid for or got waits till it is next due. Above rich_above
## gold, needs come due rich_every as often. Gold only moves: nothing here
## makes any. Each trade is a ledger line (Stockpile.note) and the
## worker's last_trade; Production.on_dole a signal.
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
		if bool(who["away"]) or str(who["town"]).is_empty() or production.outside(id):
			continue
		towns[who["town"]] = true
		_bank_turn(id, str(who["town"]))
		_pay_owed(id, str(who["town"]))
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
	for player_id: String in _player_owed.keys():
		_pay_player(player_id)
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
	var stores: Array = rule["store"] if rule.get("store") is Array else [rule.get("store", "")]
	# Nobody borrows for the cook's meal while the store has food of its own
	# to sell them at cost (the balance run: the poor borrowed 4-5 gold a
	# meal and their loans only grew; decision 354 amended).
	var store_has := stores.any(func(each: Variant) -> bool: return not str(each).is_empty() and stockpile.has(town, str(each)))
	var tags: Array = rule["tags"]
	var food := goods(town).filter(func(each: Dictionary) -> bool:
		return cat.get(each["id"], {}).get("tags", []).any(func(tag: Variant) -> bool: return tag in tags))
	if food.size() > int(rules.get("folk", {}).get("keep_in_shop", 0)):
		food.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a["price"] < b["price"] or a["price"] == b["price"] and a["uid"] < b["uid"])
		var pick: Dictionary = food[0]
		var maker := stockpile.maker_of(town, pick["uid"])
		var base := int(pick["price"])
		var cost := _folk_price(base, id, maker)
		if _afford(id, town, cost, not store_has):
			var thing := Items.name_of(pick["id"])
			stockpile.take_from_shop(town, pick["uid"], "folk:%s" % id)
			stockpile.book.end(pick["uid"], "eaten", "by %s at %s" % [who["name"], town])
			production.spend(id, cost, "a %s" % thing)
			var seller := _sale(town, maker, pick["id"], cost, "folk:%s" % id, "sold a %s to %s" % [thing, who["name"]], base)
			production.note_meal(id, "bought")
			production.note_trade(id, "bought a %s" % thing, cost, seller)
			if seller != TREASURY:
				production.note_trade(maker, "sold a %s" % thing, cost, who["name"])
			stockpile.note(town, pick["id"], cost, "folk:%s" % id, "%s bought a %s from %s for %d gold" % [who["name"], thing, seller, cost])
			return
	# The store's food, or what stands in for it when there is none (the
	# hunt's meat, decision 405): the first of rule's "store" there is.
	var store := str(stores[0]) if not stores.is_empty() else ""
	for each: Variant in stores:
		if not str(each).is_empty() and stockpile.has(town, str(each)):
			store = str(each)
			break
	if not store.is_empty() and stockpile.has(town, store):
		var cost := _folk_price(raw_price(town, store), id, "")
		if _afford(id, town, cost):
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
	var fee := _folk_price(int(rule.get("fee", 0)), id, "")
	var what := str(rule.get("what", need))
	if fee <= 0 or not building_stands.is_valid() \
			or not building_stands.call(town, str(rule["building"])) or not _afford(id, town, fee):
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
	if fee <= 0:
		return
	# The one of that trade with the least gold, so it spreads.
	var best := ""
	var least := 0
	for other in production.worker_ids(town):
		var them := production.worker(other)
		if other == id or Production.off_work(them) or trade not in them["trades"]:
			continue
		if best.is_empty() or int(them["purse"]) < least:
			best = other
			least = int(them["purse"])
	var base := fee
	fee = _folk_price(base, id, best)
	if best.is_empty() or not _afford(id, town, fee):
		return
	production.spend(id, fee, what)
	var seller := _pay(town, best, fee, "trade", "%s for %s" % [what, who["name"]], base)
	production.note_trade(id, what, fee, seller)
	production.note_trade(best, "%s for %s" % [what, who["name"]], fee, who["name"])
	stockpile.note(town, need, fee, "folk:%s" % id, "%s paid %s %d gold for %s" % [who["name"], seller, fee, what])


## A made thing [param id] sold from [param town]'s shop for
## [param cost], made by worker [param maker] (decision 353 amended): what
## its materials are worth goes to the treasury (the town's food, ore and
## wood paid for), the sale tax on the rest too, and the maker the rest,
## their labour. All of it to the treasury for no such worker. Who was
## paid: the maker's name or TREASURY.
func _sale(town: String, maker: String, id: String, cost: int, by: String, why: String, base := -1) -> String:
	var worker := production.worker(maker) if not maker.is_empty() else {}
	if worker.is_empty():
		stockpile.deposit(town, "gold", cost, by, why)
		return TREASURY
	# Materials and tax on the price before a merchant's factor (decision
	# 440, economy's side): the difference is the maker's alone.
	var listed := base if base >= 0 else cost
	# A maker who bought the materials (decision 498) keeps their share; the
	# town's meals were made on its account (store.town_account): its share.
	var bought: bool = production.buy_materials.is_valid() and not Items.def(id).get("tags", []).any(func(tag: Variant) -> bool:
		return str(tag) in rules.get("store", {}).get("town_account", []))
	var stuff := mini(materials(id), listed) if not bought else 0
	var split := Economy.taxed(listed - stuff, goods_class(id), rules)
	var to_town := mini(stuff + split[0], cost)
	if to_town > 0:
		stockpile.deposit(town, "gold", to_town, "tax:sale", "%s: materials %d, tax %d" % [why, stuff, split[0]])
	production.pay(maker, cost - to_town, why)
	return str(worker["name"])


# --- The town's bank (decision 354) ------------------------------------------------

## Whether worker [param id] can pay [param cost] now: from their purse,
## or with rules' "bank", a loan from [param town]'s treasury (the town's
## bank) for the rest: interest added to what they owe (Production's
## "loan"), never past cap owed, never more than the bank holds, never to
## one working off a debt. False (nothing lent) if not: then the dole, or
## the need waits.
func _afford(id: String, town: String, cost: int, borrow := true) -> bool:
	var who := production.worker(id)
	var purse := int(who["purse"])
	if purse >= cost:
		return true
	var bank: Dictionary = rules.get("bank", {})
	if not borrow or bank.is_empty() or bool(who["working_off"]):
		return false
	var short := cost - purse
	var owed := float(who["loan"])
	var due := short * (1.0 + float(bank.get("interest", 0.0)))
	if owed + due > float(bank.get("cap", 0)) or not stockpile.take(town, "gold", short, "loan:%s" % id):
		return false
	production.pay(id, short, "a loan from the town")
	production.set_loan(id, owed + due)
	stockpile.note(town, "gold", short, "loan:%s" % id, "%s borrowed %d from the town (owes %d)" % [who["name"], short, ceili(owed + due)])
	return true


## A borrower's turn each tick: repay_share of their purse goes back to
## the bank; one who owes within a coin of the cap works it off as town
## labour, work_off a day (no gold moves: the bank is paid in work), till
## they owe work_off_until of the cap, said once in the ledger when it
## starts. A debt is never written off.
func _bank_turn(id: String, town: String) -> void:
	var bank: Dictionary = rules.get("bank", {})
	var who := production.worker(id)
	var owed := float(who["loan"])
	if bank.is_empty() or owed <= 0.0:
		return
	var share := float(bank.get("repay_share", 0.5))
	var by_type: Dictionary = rules.get(str(who.get("type", "")), {}) if str(who.get("type", "")) in TYPE_RULES else {}
	share = float(by_type.get("repay", share))  # A scoundrel's 0: he never pays back on his own.
	var back := mini(ceili(owed), ceili(int(who["purse"]) * share))
	if back > 0 and production.spend(id, back, "paying back the town"):
		owed = maxf(owed - back, 0.0)
		stockpile.deposit(town, "gold", back, "repay:%s" % id, "%s paid back %d to the town (owes %d)" % [who["name"], back, ceili(owed)])
	var cap := float(bank.get("cap", 0))
	var working := owed >= cap - 1.0 or bool(who["working_off"]) and owed > cap * float(bank.get("work_off_until", 0.5))
	if working:
		if not bool(who["working_off"]):
			stockpile.note(town, "labour", 0, "work_off:%s" % id, "%s works off the debt to the town hauling (owes %d)" % [who["name"], ceili(owed)])
		owed = maxf(owed - float(bank.get("work_off", 0)) * World.WORLD_TICK_STEPS / 54000.0, 0.0)
	production.set_loan(id, owed, working and owed > 0.0)


## [param amount] paid to worker [param payee] in [param town] for a
## [param kind] of transaction, the tax to the treasury (all of it, for no
## such worker): who was paid, their name or TREASURY.
func _pay(town: String, payee: String, amount: int, kind: String, why: String, base := -1) -> String:
	var worker := production.worker(payee) if not payee.is_empty() else {}
	if worker.is_empty():
		stockpile.deposit(town, "gold", amount, "folk", why)
		return TREASURY
	# The tax on the fee before a merchant's factor; the rest is the payee's.
	var tax := mini(Economy.taxed(base if base >= 0 else amount, kind, rules)[0], amount)
	if tax > 0:
		stockpile.deposit(town, "gold", tax, "tax:folk", why)
	production.pay(payee, amount - tax, why)
	return str(worker["name"])


# --- Merchants (decision 440, economy's side) --------------------------------------

## How worker [param worker_id]'s hidden type (npc's 393) bends their own
## trade on [param side] ("buy" or "sell"): the type's rules buy or sell for
## a type in TYPE_RULES (a merchant, a scoundrel: decision 492), 1
## for everyone else (and for no worker).
func folk_factor(worker_id: String, side: String) -> float:
	var type := str(production.worker(worker_id).get("type", "")) if not worker_id.is_empty() else ""
	if type not in TYPE_RULES:
		return 1.0
	return float(rules.get(type, {}).get(side, 1.0))


## [param base] as resident [param buyer] pays it to [param seller] (a
## worker, or "" for the town): each one's folk_factor, at least 1 gold
## for anything that cost some.
func _folk_price(base: int, buyer: String, seller: String) -> int:
	if base <= 0:
		return base
	return maxi(roundi(base * folk_factor(buyer, "buy") * folk_factor(seller, "sell")), 1)


# --- Gathered, hauled and paid for (decision 498) -----------------------------------

## Worker [param id]'s [param what] x [param count] delivered to
## [param town]'s store (Production.deliver: the hunter's meat, the
## farmer's harvest, the woodcutter's wood, a maker's raw), bought at
## raw_price x store.buy (the shop's own table) from the treasury above
## gold_floor. Carried by the town's next hauler, if one is in, for
## haul.fee a load of haul.load, out of the gatherer's price; what the
## treasury can't pay now is owed them (Production "owed", paid first as
## gold comes in). False, nothing banked, when the town owes them
## store.owed_cap already: "the town can't pay for more wood".
func deliver(town: String, id: String, what: String, count: int, why: String) -> bool:
	var who := production.worker(id)
	var store: Dictionary = rules.get("store", {})
	var key := "%s/%s" % [id, what]
	if int(who.get("owed", 0)) >= int(store.get("owed_cap", 30)):
		if not _cant_pay.has(key):
			_cant_pay[key] = true
			stockpile.note(town, what, 0, "unpaid:%s" % id, "the town can't pay %s for more %s (owes %d)" % [who["name"], what, int(who["owed"])])
		return false
	_cant_pay.erase(key)
	var unit := raw_price(town, what) * float(store.get("buy", 1.0))
	var price := roundi(unit * count)
	if not stockpile.deposit(town, what, count, str(who["name"]), why, id):
		return false
	if not _paid.has(town):
		_paid[town] = {}
	_paid[town][what] = unit
	var haul: Dictionary = rules.get("haul", {})
	var hauler := _hauler_for(town, id, str(haul.get("trade", "")))
	var fee := 0
	if not hauler.is_empty():
		fee = mini(ceili(float(count) / maxi(int(haul.get("load", 5)), 1)) * int(haul.get("fee", 1)), price)
		_hauled[hauler] = now()
		_owe_or_pay(town, hauler, fee, "hauling %d %s" % [count, what])
	_owe_or_pay(town, id, price - fee, "%d %s delivered" % [count, what])
	return true


## [param amount] paid to worker [param id] from [param town]'s treasury
## above gold_floor, the rest owed them.
func _owe_or_pay(town: String, id: String, amount: int, why: String) -> void:
	if amount <= 0:
		return
	var paid := mini(amount, maxi(stockpile.count(town, "gold") - int(rules.get("gold_floor", 0)), 0))
	if paid > 0 and stockpile.take(town, "gold", paid, "paid:%s" % id):
		production.pay(id, paid, why)
	else:
		paid = 0
	if paid < amount:
		production.set_owed(id, int(production.worker(id).get("owed", 0)) + amount - paid)


## What the town owes worker [param id], paid as its treasury has gold
## above gold_floor, before anything else of theirs.
func _pay_owed(id: String, town: String) -> void:
	var owed := int(production.worker(id).get("owed", 0))
	if owed <= 0:
		return
	var paid := mini(owed, maxi(stockpile.count(town, "gold") - int(rules.get("gold_floor", 0)), 0))
	if paid > 0 and stockpile.take(town, "gold", paid, "owed:%s" % id):
		production.pay(id, paid, "what the town owed")
		production.set_owed(id, owed - paid)


## The hauler of [param town] to carry the next load (in town, not away,
## not [param gatherer]: the one who carried longest ago), "" for none.
func _hauler_for(town: String, gatherer: String, trade: String) -> String:
	if trade.is_empty():
		return ""
	var best := ""
	for id in production.worker_ids(town):
		var who := production.worker(id)
		if id == gatherer or Production.off_work(who) or production.outside(id) or trade not in who["trades"]:
			continue
		if best.is_empty() or int(_hauled.get(id, -1)) < int(_hauled.get(best, -1)):
			best = id
	return best


## Player [param player_id] banks [param yields] (resource -> count) at
## [param town]'s store (Jeff: "players bank goods for gold"): bought as a
## gatherer's delivery, at raw_price x store.buy from the treasury above
## gold_floor (call it before the goods are banked: the price reads the
## store as it was), the rest owed them and paid as gold comes in (owed_paid).
## Past store.owed_cap owed in that town, the goods are the town's as a
## gift, said in the ledger. The gold paid now (the caller's to give).
func bank_sale(town: String, player_id: String, yields: Dictionary) -> int:
	var store: Dictionary = rules.get("store", {})
	var owed := int(_player_owed.get(player_id, {}).get(town, 0))
	if owed >= int(store.get("owed_cap", 30)):
		stockpile.note(town, "gold", 0, "gift:%s" % player_id, "the town can't pay %s for more: %s given" % [player_id, yields])
		return 0
	var price := 0
	for what: String in yields:
		var unit := raw_price(town, what) * float(store.get("buy", 1.0))
		price += roundi(unit * int(yields[what]))
		if not _paid.has(town):
			_paid[town] = {}
		_paid[town][what] = unit
	var paid := mini(price, maxi(stockpile.count(town, "gold") - int(rules.get("gold_floor", 0)), 0))
	if paid > 0 and not stockpile.take(town, "gold", paid, "bought:%s" % player_id):
		paid = 0
	if paid < price:
		if not _player_owed.has(player_id):
			_player_owed[player_id] = {}
		_player_owed[player_id][town] = owed + price - paid
	return paid


## What the towns owe player [param player_id] for banked goods, paid as
## each treasury has gold above gold_floor (owed_paid tells World).
func _pay_player(player_id: String) -> void:
	var owed: Dictionary = _player_owed[player_id]
	var got := 0
	for town: String in owed.keys():
		var paid := mini(int(owed[town]), maxi(stockpile.count(town, "gold") - int(rules.get("gold_floor", 0)), 0))
		if paid > 0 and stockpile.take(town, "gold", paid, "owed:%s" % player_id):
			got += paid
			owed[town] = int(owed[town]) - paid
		if int(owed[town]) <= 0:
			owed.erase(town)
	if owed.is_empty():
		_player_owed.erase(player_id)
	if got > 0:
		owed_paid.emit(player_id, add_gold(player_id, got, "what the town owed for goods banked"))


## What [param town] owes player [param player_id] for goods banked.
func owed_to(player_id: String, town: String) -> int:
	return int(_player_owed.get(player_id, {}).get(town, 0))


## Maker [param id] pays [param town]'s store for a job's materials
## ([param needs]: resource -> count): each at raw_price x store.sell, never
## under what the store last paid for it x store.sell, from their purse or
## a loan (the bank as for anything else). False, nothing taken, if they
## can't.
func buy_materials(town: String, id: String, needs: Dictionary) -> bool:
	var sell := float(rules.get("store", {}).get("sell", 1.1))
	var cost := 0
	for what: String in needs:
		var unit := maxf(float(raw_price(town, what)), float(_paid.get(town, {}).get(what, 0.0)))
		cost += ceili(unit * sell * int(needs[what]))
	if cost <= 0:
		return true
	if not _afford(id, town, cost) or not production.spend(id, cost, "materials from the store"):
		return false
	stockpile.deposit(town, "gold", cost, "materials:%s" % id, "%s bought %s for %d gold" % [production.worker(id)["name"], needs, cost])
	return true

# --- The thief's fence (npc's thief, decision 461) --------------------------------

## A lifted [param what] (a resource) fenced through merchant
## [param merchant_id]: sold back to [param town]'s store at its raw price
## times [param factor], the treasury paying (never below gold_floor;
## nothing moves when it can't), the resource banked by the merchant, who
## keeps [param margin] of the gold, the thief [param thief_id] the rest.
## The gold paid in all.
func fence(town: String, merchant_id: String, thief_id: String, what: String, factor_given: float, margin: float) -> int:
	if what not in Stockpile.RESOURCES or production.worker(merchant_id).is_empty() or production.worker(thief_id).is_empty():
		return 0
	var price := maxi(roundi(raw_price(town, what) * factor_given), 1)
	if stockpile.count(town, "gold") - price < int(rules.get("gold_floor", 0)) or not stockpile.take(town, "gold", price, "dealer:%s" % merchant_id):
		return 0
	stockpile.deposit(town, what, 1, production.worker(merchant_id)["name"], "a dealer")
	var kept := clampi(roundi(price * clampf(margin, 0.0, 1.0)), 0, price)
	production.pay(merchant_id, kept, "dealt %s" % what)
	production.pay(thief_id, price - kept, "fenced %s" % what)
	return price


# --- For npc's offers (decision 435, economy's side) -------------------------------

## Player [param player_id] pays up to [param gold] of worker
## [param worker_id]'s loan to their town's bank: never more than they have
## or it owes. The loan lowered (Production.set_loan: loan_changed), the
## treasury paid, a ledger line. The gold paid.
func pay_loan(player_id: String, worker_id: String, gold_offered: int) -> int:
	var who := production.worker(worker_id)
	if who.is_empty() or player_id.is_empty():
		return 0
	var owed := float(who["loan"])
	var paid := mini(mini(gold_offered, gold(player_id)), ceili(owed))
	if paid <= 0:
		return 0
	var town := str(who["town"])
	add_gold(player_id, -paid, "paid %s's debt to %s" % [who["name"], town])
	stockpile.deposit(town, "gold", paid, "debt:%s" % player_id, "%s paid %d of %s's debt to the town" % [player_id, paid, who["name"]])
	var left := maxf(owed - paid, 0.0)
	production.set_loan(worker_id, left, bool(who["working_off"]) and left > 0.0)
	if left <= 0.0:
		stockpile.note(town, "gold", 0, "debt:%s" % player_id, "%s has paid the town's coffer back" % who["name"])
	return paid


## [param town]'s treasury pays player [param player_id] up to
## [param gold] for a commission met (rules' "commissions" say how much
## for what; npc's), never below gold_floor. The gold paid.
func pay_commission(player_id: String, town: String, gold_owed: int) -> int:
	if player_id.is_empty() or gold_owed <= 0:
		return 0
	var paid := mini(gold_owed, maxi(stockpile.count(town, "gold") - int(rules.get("gold_floor", 0)), 0))
	if paid <= 0 or not stockpile.take(town, "gold", paid, "commission:%s" % player_id):
		return 0
	add_gold(player_id, paid, "a commission from %s" % town)
	stockpile.note(town, "gold", -paid, "commission:%s" % player_id, "paid %s %d gold for a commission" % [player_id, paid])
	return paid


# --- Saving --------------------------------------------------------------------------

## For the snapshot: {purses: {player id: gold}, log}.
func to_dict() -> Dictionary:
	return {"purses": _purses.duplicate(), "log": _log.duplicate(true), "paid": _paid.duplicate(true), "hauled": _hauled.duplicate(),
		"player_owed": _player_owed.duplicate(true)}


func from_dict(saved: Dictionary) -> void:
	var paid: Variant = saved.get("paid", {})
	if paid is Dictionary:
		for town: Variant in paid:
			if paid[town] is Dictionary:
				_paid[str(town)] = {}
				for what: Variant in paid[town]:
					_paid[str(town)][str(what)] = maxf(float(paid[town][what]), 0.0)
	var player_owed: Variant = saved.get("player_owed", {})
	if player_owed is Dictionary:
		for id: Variant in player_owed:
			if player_owed[id] is Dictionary:
				for town: Variant in player_owed[id]:
					if int(player_owed[id][town]) > 0:
						if not _player_owed.has(str(id)):
							_player_owed[str(id)] = {}
						_player_owed[str(id)][str(town)] = int(player_owed[id][town])
	var hauled: Variant = saved.get("hauled", {})
	if hauled is Dictionary:
		for id: Variant in hauled:
			_hauled[str(id)] = int(hauled[id])
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
