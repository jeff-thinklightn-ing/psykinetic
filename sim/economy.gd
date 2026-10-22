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
## Player [param player_id] gave [param gold] toward [param town]'s
## [param kind] (decision 499): Main thanks them in town experience
## ([param xp]).
signal contributed(town: String, player_id: String, kind: String, gold: int, xp: int)
## Caravan [param id] of [param town] sold its goods at [param market] for
## [param proceeds], [param wages] of it to its members (decision 504,
## for npc's road news: whether the wagon sold well).
signal caravan_sold(id: String, town: String, market: String, proceeds: int, wages: int)

const PATH := "res://levels/economy.json"
const TREASURY := "the town"
const SELL := "sell"
const BUY := "buy"
## A counter's fence state (586): the fence's by day, by night; "" any
## other counter.
const FENCE_DAY := "day"
const FENCE_NIGHT := "night"
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
## (town) -> {kind, job, steps, needs}: what the town's next build lacks
## (Towns.shortfall, set by Main; decision 499). {} while unset.
var shortfall := Callable()
## (town) -> [{id, market, eta (world ticks), risk (0..1)}]: the trade
## routes from the town to a market (maps' TradeRoutes, set by Main;
## decision 504). None while unset.
var trade_routes := Callable()
## (route_id, cargo {items, goods, members}, from_end) -> caravan id, ""
## for none: TradeRoutes.send, set by Main.
var send_caravan := Callable()
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
## Maker id -> the step their apprentice's wage was last paid (498 amended).
var _apprentice_paid: Dictionary = {}
## Town -> building id -> gold players gave toward it, not yet spent (499).
var _funds: Dictionary = {}
## Caravan id -> {town, route, market, risk, eta, members, goods, home}:
## the town's caravans on the road (504; home true on the way back).
var _caravans: Dictionary = {}
## Market id -> resource -> how much it bought lately (its price falls).
var _bought: Dictionary = {}
## The day (now / day_steps) caravans were last thought of, and the
## market's buying last eased.
var _trade_day := -1
## The temple's alms by town (decision 546): the offerings for being
## brought back, paying the priest's wage first, the rest the altar's.
var _alms: Dictionary = {}
## The gold laid below at the barrow's altar by town (546), and the day it
## last went down (-1: never).
var _below: Dictionary = {}
var _down_day: Dictionary = {}
## The day of the last wage floor turn (decision 528), -1 before the first.
var _floor_day := -1
## The grave robbers' purse by barrow level (580, economy's side), and the
## day they last lifted from the altars.
var _bands: Dictionary = {}
var _band_day := -1
## What each worker the town owes is owed for: worker id -> [resource]
## (522 amended: the head build's suppliers paid first).
var _owed_what: Dictionary = {}
## Each import on the shelf's landed cost: uid -> gold (decision 514).
var _landed: Dictionary = {}
## A rich resident's want the shelf couldn't meet, a commission for the
## next caravan (514 amended): town -> worker id.
var _commissions: Dictionary = {}
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


# --- The healer's care (decision 584 amended) --------------------------------------

## The ways into a healer's care: the bypass, handed at his hut (gold, herbs,
## antlers), and his first errand done (quest, npc's).
const CARE_WAYS: Array[String] = ["gold", "herbs", "antlers", "quest"]
## The ways that count as his first errand done, opening his further
## errands (npc's chain): five herbs, however handed.
const CARE_QUEST_WAYS: Array[String] = ["herbs", "quest"]


## What a healer's hut takes for his care (rules' return.care; Jeff: "5
## herbs, 5 antlers or 10 gold to bypass the quest"), {retainer, herbs,
## antlers, sick, word_days}: any one puts a player in his care at once.
## sick and word_days (npc's kin errand) only at a hut in a town
## ([param in_town]); a hut out in the land (Hob's) asks the rest alone.
func care_rule(in_town: bool) -> Dictionary:
	var rule: Dictionary = rules.get("return", {}).get("care", {})
	return {"retainer": int(rule.get("retainer", 10)), "herbs": int(rule.get("herbs", 5)), "antlers": int(rule.get("antlers", 5)),
		"sick": int(rule.get("sick", 1)) if in_town else 0, "word_days": int(rule.get("word_days", 1)) if in_town else 0}


## [param had] (a record's way in, "" for none) after [param way]: the way
## kept, "" if [param way] changes nothing. His first errand done upgrades a
## paid way (gold, antlers) to it; nothing else replaces a way in.
static func care_after(had: String, way: String) -> String:
	if way not in CARE_WAYS:
		return ""
	if had.is_empty():
		return way
	if way in CARE_QUEST_WAYS and had not in CARE_QUEST_WAYS:
		return way
	return ""


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
	if rules.get("maker_only", {}).has(id):
		return str(rules["maker_only"][id])  # Only its maker buys it (562: the herbs).
	if short_of(town, id, cat) <= 0.0:
		return "the town has enough of that"
	var pays: int = Economy.taxed(price(town, id, BUY, cat), "buy", rules)[1]
	if stockpile.count(town, "gold") - pays < int(rules.get("gold_floor", 0)):
		return "the town can't pay for it now"
	return ""


## [param town]'s shop, for a shop panel: [{uid, id, price}] by uid.
func goods(town: String, fence := "") -> Array[Dictionary]:
	var cat: Dictionary = catalog.call()
	var out: Array[Dictionary] = []
	var uids := stockpile.shop(town)
	uids.sort()
	for uid in uids:
		var id := stockpile.book.id_of(uid)
		out.append({"uid": uid, "id": id, "price": fence_markup(item_price(town, uid, cat), fence)})
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


## Barter's offers (decision 560): what [param town] pays for each of
## [param ids], the tax taken, and how many it takes at that price before
## it has enough: id -> {gold, up_to}; the ones it won't buy left out.
func buys(town: String, ids: Array) -> Dictionary:
	var cat: Dictionary = catalog.call()
	var paid := offers(town, ids)
	var out := {}
	for id: String in paid:
		out[id] = {"gold": int(paid[id]), "up_to": up_to(town, id, cat)}
	return out


## How many [param id] [param town] takes before it has enough of it: for
## a raw good the most of its yields that fit under rules' "comfort", for
## gear the most room under any of its tags' "wants". At least 1 for a
## thing it is short of now, 0 for one it is not.
func up_to(town: String, id: String, cat := {}) -> int:
	if cat.is_empty():
		cat = catalog.call()
	if short_of(town, id, cat) <= 0.0:
		return 0
	var def: Dictionary = cat.get(id, {})
	var most := 1
	var yields: Variant = def.get("yield", {})
	if yields is Dictionary and not yields.is_empty():
		var comfort: Dictionary = rules.get("comfort", {})
		for what: String in yields:
			var room := int(comfort.get(what, 0)) - stockpile.count(town, what)
			if room > 0 and int(yields[what]) > 0:
				most = maxi(most, ceili(float(room) / int(yields[what])))
		return most
	var wants: Dictionary = rules.get("wants", {})
	var extra: Dictionary = rules.get("uneasy_extra", {}) if production.tier(town) == Production.DEFEND else {}
	var have := _gear_by_tag(town, cat)
	for tag: Variant in def.get("tags", []):
		if wants.has(tag):
			most = maxi(most, int(wants[tag]) + int(extra.get(tag, 0)) - int(have.get(tag, 0)))
	return most


## What [param town] pays for grave goods (decision 560: the coordinator's
## ruling, Jeff's to move): the merchant takes them fenced, at half the
## town's price [param paid] (at least 1); the other half stays in the
## treasury.
static func fenced(paid: int, factor := 0.5) -> int:
	return maxi(floori(paid * factor), 1)


# --- The fence (decision 586: Snagfin) ------------------------------------------

## The fence's rules (economy.json "fence"): {by (a settled resident's
## id), factor, day_markup}.
func fence_rule() -> Dictionary:
	var rule: Variant = rules.get("fence", {})
	return rule if rule is Dictionary else {}


## The fence's worker id, if he is in his town now ("" if none, or away).
func fence_by() -> String:
	var by := str(fence_rule().get("by", ""))
	var who := production.worker(by) if not by.is_empty() else {}
	return by if not who.is_empty() and not bool(who.get("away", false)) else ""


## Whether it is night (dark under the open sky): the fence buys then.
func is_night() -> bool:
	return DayNight.daylight(now()) < DayNight.DARK_LIGHT


## What the fence pays for a thing the town would pay [param paid] for.
func fence_price(paid: int) -> int:
	return Economy.fenced(paid, float(fence_rule().get("factor", 0.5)))


## [param asked] marked up at the fence's counter by day ([param fence]
## "day"), else as asked.
func fence_markup(asked: int, fence: String) -> int:
	return ceili(asked * float(fence_rule().get("day_markup", 1.0))) if fence == FENCE_DAY else asked


## Why grave goods aren't bought at a counter whose fence state is
## [param fence] ("" bought: the fence's at night).
static func fence_refuses(fence: String) -> String:
	return "" if fence == FENCE_NIGHT else "not by day" if fence == FENCE_DAY else "won't buy that"


# --- A maker barters (decision 562, barter's phase 2) ------------------------------

## The trades of worker [param worker_id]'s recipes' materials: resource ->
## how many their shelf's worth of makes uses (each recipe of their trade
## its "stock", else shop_cap, times its from).
func maker_materials(worker_id: String, cat := {}) -> Dictionary:
	if cat.is_empty():
		cat = catalog.call()
	var trades: Array = production.worker(worker_id).get("trades", [])
	var out := {}
	for id: String in cat:
		var made: Variant = cat[id].get("made", {})
		if not made is Dictionary or str(made.get("by", "")) not in trades:
			continue
		var shelf := int(made.get("stock", rules.get("shop_cap", 6)))
		var from: Dictionary = made.get("from", {})
		for what: String in from:
			if what in Stockpile.RESOURCES:
				out[what] = int(out.get(what, 0)) + shelf * int(from[what])
	return out


## Worker [param worker_id]'s own make on their town's shelf, for the
## barter window: [{uid, id, price}] by uid, at maker_price.
func maker_goods(worker_id: String) -> Array[Dictionary]:
	var town := str(production.worker(worker_id).get("town", ""))
	var cat: Dictionary = catalog.call()
	var out: Array[Dictionary] = []
	for each in goods(town):
		if stockpile.maker_of(town, int(each["uid"])) == worker_id:
			each["price"] = maker_price(town, int(each["uid"]), cat)
			out.append(each)
	return out


## What a maker asks for their own make [param uid] at [param town]: the
## shop's price, never under its worth (value_of: the medicine man's potion
## 4, though his hut wants none of it).
func maker_price(town: String, uid: int, cat := {}) -> int:
	if cat.is_empty():
		cat = catalog.call()
	return maxi(item_price(town, uid, cat), value_of(stockpile.book.id_of(uid), cat))


## What maker [param worker_id] pays from their own purse for each of
## [param ids] (a player's things): only those yielding their recipes'
## materials, each yield at its value times the maker's own need (their
## shelf's worth of makes, less their store's: factor), id -> {gold,
## up_to}; up_to as many as that need takes and their purse pays for.
func maker_buys(worker_id: String, ids: Array) -> Dictionary:
	var cat: Dictionary = catalog.call()
	var who := production.worker(worker_id)
	var town := str(who.get("town", ""))
	var wants := maker_materials(worker_id, cat)
	var purse := int(who.get("purse", 0))
	var out := {}
	for raw: Variant in ids:
		var id := str(raw)
		var yields: Variant = cat.get(id, {}).get("yield", {})
		if id.is_empty() or out.has(id) or not yields is Dictionary or yields.is_empty():
			continue
		var gold := 0.0
		var most := 0
		for what: String in yields:
			if not wants.has(what):
				gold = 0.0
				break
			var have := stockpile.count(town, what)
			gold += float(rules.get("value", {}).get(what, 1)) * factor(_short(have, int(wants[what]))) * int(yields[what])
			most = maxi(most, ceili(float(int(wants[what]) - have) / maxi(int(yields[what]), 1)))
		var each := maxi(roundi(gold), 1)
		if gold <= 0.0 or most <= 0 or purse < each:
			continue
		out[id] = {"gold": each, "up_to": mini(most, purse / each)}
	return out


## A barter with maker [param worker_id] priced (decision 562), as
## barter_quote: [param gives] the player's things ([{id}]) bought from the
## maker's purse, [param takes] uids of their own make off their town's
## shelf at maker_price. {ok, gives, takes, balance, why}.
func maker_quote(worker_id: String, player_id: String, gives: Array, takes: Array) -> Dictionary:
	var cat: Dictionary = catalog.call()
	var town := str(production.worker(worker_id).get("town", ""))
	var out := {"ok": false, "gives": [], "takes": [], "balance": 0, "why": ""}
	var offered := maker_buys(worker_id, gives.map(func(give: Dictionary) -> String: return str(give["id"])))
	var counts := {}
	var paid := 0
	for give: Dictionary in gives:
		var id := str(give["id"])
		if bool(give.get("fenced", false)):
			out["why"] = Economy.fence_refuses("")  # Only the fence buys grave goods (586).
			return out
		counts[id] = int(counts.get(id, 0)) + 1
		if not offered.has(id) or int(counts[id]) > int(offered[id]["up_to"]):
			out["why"] = "%s has no use for that" % production.worker(worker_id).get("name", "they") if not offered.has(id) 					else "%s has enough of that" % production.worker(worker_id).get("name", "they")
			return out
		out["gives"].append(int(offered[id]["gold"]))
		paid += int(offered[id]["gold"])
	if paid > int(production.worker(worker_id).get("purse", 0)):
		out["why"] = "%s can't pay for it now" % production.worker(worker_id).get("name", "they")
		return out
	var cost := 0
	var shelf := stockpile.shop(town)
	for uid: int in takes:
		if uid not in shelf or takes.count(uid) > 1 or stockpile.maker_of(town, uid) != worker_id:
			out["why"] = "that is no longer for sale"
			return out
		var each := maker_price(town, uid, cat)
		out["takes"].append(each)
		cost += each
	if gold(player_id) + paid < cost:
		out["why"] = "not enough gold (%d)" % (cost - paid)
		return out
	out["balance"] = paid - cost
	out["ok"] = true
	return out


## Maker [param worker_id] buys a [param id] from [param player_id] for
## [param at] gold (priced by maker_quote) from their own purse: the
## maker's expense ("makers have more expense"), earned back as the maker's
## share of what they make of it. The thing is the caller's to bank in the
## maker's store. False, nothing paid, if they can't.
func maker_sell(worker_id: String, player_id: String, id: String, at: int) -> bool:
	if not production.spend(worker_id, at, "bought %s from a player" % id):
		return false
	add_gold(player_id, at, "sold %s to %s" % [id, production.worker(worker_id).get("name", "")])
	return true


## A barter at [param town]'s shop priced (decision 560): [param gives]
## the player's things ([{id, fenced}]), [param takes] uids off its shelf.
## {ok, gives: [gold each], takes: [gold each], balance (what the player
## gets, less what they pay), why}. All or nothing: each give the town
## would buy, no more of an id than up_to, each take still for sale, the
## treasury able to pay the gives above gold_floor, and [param player_id]
## able to pay the takes with what the gives bring. Each priced as its
## hover showed it: no bundle price.
func barter_quote(town: String, player_id: String, gives: Array, takes: Array, fence := "") -> Dictionary:
	var cat: Dictionary = catalog.call()
	var out := {"ok": false, "gives": [], "takes": [], "balance": 0, "why": ""}
	var ids: Array = gives.map(func(give: Dictionary) -> String: return str(give["id"]))
	var offered := buys(town, ids)
	var counts := {}
	var paid := 0
	for give: Dictionary in gives:
		var id := str(give["id"])
		if bool(give.get("fenced", false)) and not Economy.fence_refuses(fence).is_empty():
			out["why"] = Economy.fence_refuses(fence)  # Only the fence, by night (586).
			return out
		if not offered.has(id):
			out["why"] = refuses(town, id, cat)
			if str(out["why"]).is_empty():
				out["why"] = "the town won't buy that"
			return out
		counts[id] = int(counts.get(id, 0)) + 1
		if int(counts[id]) > int(offered[id]["up_to"]):
			out["why"] = "the town has enough of that"
			return out
		var gold_each := int(offered[id]["gold"])
		if bool(give.get("fenced", false)):
			gold_each = fence_price(gold_each)
		out["gives"].append(gold_each)
		paid += gold_each
	var cost := 0
	var shelf := stockpile.shop(town)
	for uid: int in takes:
		if uid not in shelf or takes.count(uid) > 1:
			out["why"] = "that is no longer for sale"
			return out
		var each := fence_markup(item_price(town, uid, cat), fence)
		out["takes"].append(each)
		cost += each
	if paid > 0 and stockpile.count(town, "gold") - paid < int(rules.get("gold_floor", 0)):
		out["why"] = "the town can't pay for it now"
		return out
	if gold(player_id) + paid < cost:
		out["why"] = "not enough gold (%d)" % (cost - paid)
		return out
	out["balance"] = paid - cost
	out["ok"] = true
	return out


# --- Trade ---------------------------------------------------------------------------

## [param player_id] buys [param uid] from [param town]'s shop at its price
## (or [param at], a barter's quoted price, decision 560): {ok, price, why}. On ok the thing is out of the shop, held by nothing
## (the caller puts it somewhere), the gold paid out.
func buy(player_id: String, town: String, uid: int, at := -1, fence := "") -> Dictionary:
	if uid not in stockpile.shop(town):
		return {"ok": false, "why": "that is no longer for sale"}
	var id := stockpile.book.id_of(uid)
	var cost := fence_markup(item_price(town, uid), fence) if at < 0 else at
	if gold(player_id) < cost:
		return {"ok": false, "price": cost, "why": "not enough gold (%d)" % cost}
	var maker := stockpile.maker_of(town, uid)
	if not stockpile.take_from_shop(town, uid, "sold:%s" % player_id):
		return {"ok": false, "why": "that is no longer for sale"}
	add_gold(player_id, -cost, "bought %s" % id)
	_sale(town, maker, id, cost, "sale:%s" % player_id, "sold %s" % id, -1, int(_landed.get(uid, -1)))
	_landed.erase(uid)
	stockpile.book.note(uid, "bought", "by %s at %s for %d gold" % [player_id, town, cost])
	production.note_sale(town, id, 1)
	return {"ok": true, "price": cost, "id": id}


## [param town] buys [param id] from [param player_id], if it would
## (refuses): {ok, paid, why}, the treasury paying, the buy tax kept in it;
## half that for grave goods ([param is_fenced], decision 560), or
## [param at] when given (a barter priced by barter_quote, its checks made).
## The thing itself is the caller's to bank (World._bank_thing, or the shop).
func sell(player_id: String, town: String, id: String, is_fenced := false, at := -1, fence := "") -> Dictionary:
	var cat: Dictionary = catalog.call()
	var why := Economy.fence_refuses(fence) if is_fenced and at < 0 else ""
	if why.is_empty():
		why = refuses(town, id, cat) if at < 0 else ""
	if not why.is_empty():
		return {"ok": false, "why": why}
	var pays: int = Economy.taxed(price(town, id, BUY, cat), "buy", rules)[1] if at < 0 else at
	if is_fenced and at < 0:
		pays = fence_price(pays)
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
	_band_turn()
	var folk: Dictionary = rules.get("folk", {})
	var needs: Dictionary = folk.get("needs", {})
	if needs.is_empty():
		return
	var cat: Dictionary = catalog.call()
	var at := now()
	_pay_head_first()
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
		_apprentice_turn(id, str(who["town"]))
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
	_drop_funds()
	_trade_turn(towns.keys())
	_floor_turn()
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
	if bool(rule.get("luxury", false)):
		_indulge(id, cat)
	elif rule.has("tags"):
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
func _sale(town: String, maker: String, id: String, cost: int, by: String, why: String, base := -1, bought_for := -1) -> String:
	var worker := production.worker(maker) if not maker.is_empty() else {}
	if worker.is_empty():
		stockpile.deposit(town, "gold", cost, by, why)
		return TREASURY
	# An import the merchant paid [param bought_for] for (decision 514): the
	# tax on his margin only, the rest his.
	if bought_for >= 0:
		var cut := mini(Economy.taxed(maxi((base if base >= 0 else cost) - bought_for, 0), goods_class(id), rules)[0], cost)
		if cut > 0:
			stockpile.deposit(town, "gold", cut, "tax:sale", "%s: tax %d on the margin" % [why, cut])
		production.pay(maker, cost - cut, why)
		return str(worker["name"])
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
	# A service earned while the payee's purse is above luxury.above pays
	# tax.trade_rich (decision 528, on Jeff's "taxes can be most higher on
	# luxury goods which the rich prefer then wages are paid by town").
	var tax_kind := kind
	if kind == "trade" and int(worker["purse"]) > int(rules.get("luxury", {}).get("above", 60)) and rules.get("tax", {}).has("trade_rich"):
		tax_kind = "trade_rich"
	var tax := mini(Economy.taxed(base if base >= 0 else amount, tax_kind, rules)[0], amount)
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
	var unit := maxf(raw_price(town, what) * float(store.get("buy", 1.0)), maker_floor(town, id, what))
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
		_owe_or_pay(town, hauler, fee, "hauling %d %s" % [count, what], what)
	_owe_or_pay(town, id, price - fee, "%d %s delivered" % [count, what], what)
	return true


## The least [param town]'s store pays worker [param id] for one of raw
## [param what] they made from raws (decision 528, on 498; Jeff: "makers
## have more expense"): what its inputs cost at the store (as
## buy_materials asks) and store.make_margin for the job, over the job's
## yield. 0 for one they didn't make (a gatherer's, a player's), so the
## want's discount (raw_price) works only above it.
func maker_floor(town: String, id: String, what: String) -> float:
	var trades: Array = production.worker(id).get("trades", [])
	var cat: Dictionary = catalog.call()
	var sell := float(rules.get("store", {}).get("sell", 1.1))
	for item: String in cat:
		var made: Variant = cat[item].get("made", {})
		var yields := Items.yield_of(item)
		if not made is Dictionary or not yields.has(what) or str(made.get("by", "")) not in trades:
			continue
		var cost := float(rules.get("store", {}).get("make_margin", 0))
		var from: Dictionary = made.get("from", {})
		for input: String in from:
			if input not in Stockpile.RESOURCES:
				return 0.0
			cost += maxf(float(raw_price(town, input)), float(_paid.get(town, {}).get(input, 0.0))) * sell * int(from[input])
		return cost / maxi(int(yields[what]), 1)
	return 0.0


## [param amount] paid to worker [param id] from [param town]'s treasury
## above gold_floor, the rest owed them.
func _owe_or_pay(town: String, id: String, amount: int, why: String, what := "") -> void:
	if amount <= 0:
		return
	# A delivery the next build lacks: what players gave toward it pays first (499).
	var given := 0
	if not what.is_empty() and shortfall.is_valid():
		var short: Dictionary = shortfall.call(town)
		if short.get("needs", {}).has(what):
			given = _from_fund(town, str(short["kind"]), amount)
			if given > 0:
				production.pay(id, given, "%s (given toward the %s)" % [why, short["kind"]])
	var paid := mini(amount - given, maxi(stockpile.count(town, "gold") - int(rules.get("gold_floor", 0)), 0))
	if paid > 0 and stockpile.take(town, "gold", paid, "paid:%s" % id):
		production.pay(id, paid, why)
	else:
		paid = 0
	paid += given
	if paid < amount:
		production.set_owed(id, int(production.worker(id).get("owed", 0)) + amount - paid)
		if not why.begins_with("the town's wage floor"):
			production.note_earned(id, amount - paid)
		if not what.is_empty():
			var owed_for: Array = _owed_what.get_or_add(id, [])
			if what not in owed_for:
				owed_for.append(what)


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
		owed -= paid
		if owed <= 0:
			_owed_what.erase(id)
	# The treasury at its floor: what players gave pays the town's debts (499).
	for kind: String in _funds.get(town, {}).keys():
		if owed <= 0:
			break
		var given := _from_fund(town, kind, owed)
		if given > 0:
			production.pay(id, given, "what the town owed (given toward the %s)" % kind)
			owed -= given
			production.set_owed(id, owed)


## The town pays worker [param id] [param amount] for [param why] from its
## treasury above its floor, the rest owed them (Production's work on the
## town's account, 522 amended (2)); [param what] the resource it was for.
func owe_or_pay(town: String, id: String, amount: int, why: String, what := "") -> void:
	_owe_or_pay(town, id, amount, why, what)


## Once a day (decision 528; Jeff: "someone paid to do it", "wages are
## paid by town"): each resident of a trade in wage_floor.trades whose work
## earned them less than wage_floor.gold a day since the last turn is paid
## the rest by the town, from its treasury above its floor or owed them
## (as the head build's supplier first when their good is what it lacks:
## the trade's good in wage_floor.trades).
func _floor_turn() -> void:
	var rule: Dictionary = rules.get("wage_floor", {})
	var day := now() / maxi(DayNight.day_steps, 1)
	if rule.is_empty() or day == _floor_day:
		return
	var days := day - _floor_day if _floor_day >= 0 else 0
	_floor_day = day
	_acolyte_turn(days)
	var trades: Dictionary = rule.get("trades", {})
	for id in production.worker_ids():
		var who := production.worker(id)
		var earned := production.take_earned(id)
		var trade := ""
		for each: String in who["trades"]:
			if trades.has(each):
				trade = each
		if days <= 0 or trade.is_empty() or str(who["town"]).is_empty():
			continue
		var short := int(rule.get("gold", 0)) * days - earned
		if short <= 0:
			continue
		var town := str(who["town"])
		var owed := int(who.get("owed", 0))
		_owe_or_pay(town, id, short, "the town's wage floor", str(trades[trade]))
		var now_owed := int(production.worker(id).get("owed", 0)) - owed
		print("[economy] %s the %s earned %d: the wage floor's %d more, %d paid and %d owed, step %d" % [who["name"], trade, earned, short,
			short - now_owed, now_owed, now()])


# --- The temple's offering and the gold below (decision 546) -------------------------

## Player [param player_id] makes the offering for being brought back at
## [param town]'s temple (Jeff's crypt.md: "a gold offering, until
## blessed"): return.offering, or what they hold if less (they are brought
## back anyway), into the town's alms; nothing when [param waived] (the
## fallen carries return.waived_by, the draugr's mark). A companion's is
## her player's to pay. Spending, the only way a player loses gold. The
## gold paid.
func temple_offering(town: String, player_id: String, waived: bool, for_name := "") -> int:
	if waived or town.is_empty() or player_id.is_empty():
		return 0
	var paid := mini(int(rules.get("return", {}).get("offering", 0)), gold(player_id))
	if paid <= 0:
		return 0
	add_gold(player_id, -paid, "an offering at the temple%s" % (" for " + for_name if not for_name.is_empty() else ""))
	_alms[town] = int(_alms.get(town, 0)) + paid
	stockpile.note(town, "gold", paid, "alms:%s" % player_id, "alms at the temple, %d" % paid)
	return paid


## The acolyte lives on the alms (546 amended; the coordinator's ruling
## for Pip, Aldous's acolyte): each resident of return.acolyte.trade is
## paid return.acolyte.keep a day for [param days] days from their town's
## alms after the priest's share (altar_gold); what the alms can't keep,
## the treasury pays as it does the priest's wage, or owes it (never past
## store.owed_cap), after the officials (the temple's second man, the
## coordinator's ruling). Their loan stands as any resident's.
func _acolyte_turn(days: int) -> void:
	var rule: Dictionary = rules.get("return", {}).get("acolyte", {})
	if rule.is_empty() or days <= 0:
		return
	var trade := str(rule.get("trade", "acolyte"))
	for id in production.worker_ids():
		var who := production.worker(id)
		var town := str(who["town"])
		if trade not in who["trades"] or town.is_empty():
			continue
		var due := int(rule.get("keep", 1)) * days
		var keep := mini(due, altar_gold(town))
		if keep > 0:
			_alms[town] = alms(town) - keep
			production.pay(id, keep, "an acolyte's keep from the alms")
			print("[economy] %s the %s is kept %d gold from %s's alms, %d left, step %d" % [who["name"], trade, keep, town, alms(town), now()])
		var rest := mini(due - keep, maxi(int(rules.get("store", {}).get("owed_cap", 30)) - int(who.get("owed", 0)), 0))
		if rest > 0:
			_owe_or_pay(town, id, rest, "an acolyte's keep from the treasury")


## [param town]'s alms held at the temple.
func alms(town: String) -> int:
	return int(_alms.get(town, 0))


## Production.wage_from: the priest's wage paid from [param town]'s alms
## first (decision 546), as far as they go; other officials' never. The
## part paid.
func wage_from_alms(town: String, _id: String, trade: String, wage: int) -> int:
	if trade != str(rules.get("return", {}).get("places", {}).get("temple", {}).get("trade", "priest")):
		return 0
	var paid := mini(wage, alms(town))
	_alms[town] = alms(town) - paid
	return paid


## The priest's wage for a day, kept back in the alms for him.
func _priest_day(town: String) -> int:
	var trade := str(rules.get("return", {}).get("places", {}).get("temple", {}).get("trade", "priest"))
	var rule: Dictionary = rules.get("official", {}).get(trade, {})
	if rule.is_empty() or not production.worker_ids(town).any(func(id: String) -> bool: return trade in production.worker(id)["trades"]):
		return 0
	return ceili(float(rule.get("wage", 0)) * DayNight.day_steps / maxf(float(rule.get("every", 54000)), 1.0))


## The altar's gold of [param town]: its alms above a day of the priest's
## wage, waiting to go down (npc's runner, 546).
func altar_gold(town: String) -> int:
	return maxi(alms(town) - _priest_day(town), 0)


## Takes the altar's gold of [param town] for a run down: the gold taken.
func take_altar(town: String) -> int:
	var taken := altar_gold(town)
	_alms[town] = alms(town) - taken
	return taken


## [param amount] laid at [param town]'s barrow altar (a run, or a player
## keeping Aldous's promise): the gold below, the day it went down.
func altar_down(town: String, amount: int) -> void:
	if amount <= 0:
		return
	_below[town] = below_gold(town) + amount
	_down_day[town] = now() / maxi(DayNight.day_steps, 1)
	print("[economy] %d gold laid at %s's altar below, %d there now, step %d" % [amount, town, below_gold(town), now()])


## The gold at [param town]'s barrow altar.
func below_gold(town: String) -> int:
	return int(_below.get(town, 0))


## The day gold last went down to [param town]'s altar, -1 for never
## (the creep reads it: enemy-ai's).
func last_down_day(town: String) -> int:
	return int(_down_day.get(town, -1))


## The draugr's deals (decision 573, economy's side): rules' return.field
## "deals", [{name, gold, charges}] from the least to the most, the gold a
## player gives him buying the highest step it reaches. [param field] is
## return.field.
static func deals(field: Dictionary) -> Array:
	var out: Array = []
	for each: Variant in field.get("deals", []):
		if each is Dictionary:
			out.append(each)
	return out


## The deal [param gold] buys: the highest step it reaches; {} under the least.
static func deal_for(gold: int, field: Dictionary) -> Dictionary:
	var best := {}
	for each: Dictionary in deals(field):
		if gold >= int(each.get("gold", 0)):
			best = each
	return best


## The charges deal [param deal] (a name: easy, normal, hard) gives; before
## 573 the rules' "uses" by difficulty, read one cut more.
static func field_tokens(deal: String, field: Dictionary) -> int:
	for each: Dictionary in deals(field):
		if str(each.get("name", "")) == deal:
			return int(each.get("charges", 0))
	return int(field.get("uses", {}).get(deal, 0))


## How hard deal [param deal] is: its place among the deals (0 the least);
## -1 for none.
static func _deal_rank(deal: String, field: Dictionary) -> int:
	var names: Array = deals(field).map(func(each: Dictionary) -> String: return str(each.get("name", "")))
	if names.is_empty():
		names = ["easy", "normal", "hard"]
	return names.find(deal)


## The most charges [param barrow] may hold: capacity_step for each step of
## the hardest deal beaten (25, 50, 75), and one more for each container
## (a named source, each once); 0 unblessed. Derived, never stored, so it
## follows the rules.
static func barrow_capacity(barrow: Dictionary, field: Dictionary) -> int:
	var rank := _deal_rank(str(barrow.get("best", "")), field)
	if rank < 0:
		return 0
	var containers: Variant = barrow.get("containers", [])
	return int(field.get("capacity_step", 25)) * (1 + rank + (containers.size() if containers is Array else 0))


## The draugr beaten at [param deal]: [param barrow] with best raised if
## the deal is harder (never lowered); the charges themselves go on the
## Draugr's Totem (573 amended: Main adds field_tokens(deal) with
## World.totem_add up to barrow_capacity). {barrow: the new record}.
static func barrow_won(barrow: Dictionary, deal: String, field: Dictionary) -> Dictionary:
	var out: Dictionary = {"best": str(barrow.get("best", "")),
		"containers": (barrow.get("containers", []) as Array).duplicate() if barrow.get("containers", []) is Array else []}
	if _deal_rank(deal, field) > _deal_rank(out["best"], field):
		out["best"] = deal
	return {"barrow": out}


## A saved barrow record as 573 keeps it: one from before ({uses, of,
## difficulty, day}) becomes {tokens: uses, best: difficulty, containers}
## ("easy" for a blessed one with uses and no difficulty).
static func barrow_migrated(saved: Dictionary) -> Dictionary:
	if saved.has("tokens") or saved.has("best") or saved.has("containers"):
		# 573's shape, with or without a count: since 573 amended the Draugr's
		# Totem holds the charges and the record keeps best and containers; a
		# "tokens" count still saved is kept for Main.migrate_totem on the join.
		var containers: Variant = saved.get("containers", [])
		var out := {"best": str(saved.get("best", "")),
			"containers": (containers as Array).map(func(each: Variant) -> String: return str(each)) if containers is Array else []}
		if saved.has("tokens"):
			out["tokens"] = maxi(int(saved["tokens"]), 0)
		return out
	var uses := maxi(int(saved.get("uses", 0)), 0)
	var best := str(saved.get("difficulty", ""))
	if best.is_empty() and (uses > 0 or saved.has("of")):
		best = "easy"
	return {"tokens": uses, "best": best, "containers": []}


## The robbers' rules (economy.json "robbers", 580 economy's side).
func _robbers() -> Dictionary:
	var rule: Variant = rules.get("robbers", {})
	return rule if rule is Dictionary else {}


## The gold the grave robbers of [param barrow] (a level) hold among them.
func band_gold(barrow: String) -> int:
	return int(_bands.get(barrow, 0))


## [param gold] into [param barrow]'s robbers' purse, from [param why].
func band_add(barrow: String, gold: int, why: String) -> void:
	if gold <= 0 or barrow.is_empty():
		return
	_bands[barrow] = band_gold(barrow) + gold
	print("[economy] the robbers of %s take %d gold (%s): %d now, step %d" % [barrow, gold, why, band_gold(barrow), now()])


## Once a game day the robbers lift robbers.altar_share of the gold below
## at every town's altar (the plunder: what angers the old gods in lore,
## the pilferers), into their purse.
func _band_turn() -> void:
	var rule := _robbers()
	var barrow := str(rule.get("barrow", ""))
	var day := now() / maxi(DayNight.day_steps, 1)
	if barrow.is_empty() or day == _band_day:
		return
	_band_day = day
	var towns: Array = _below.keys()
	towns.sort()
	for town: String in towns:
		band_add(barrow, lift_below(town, floori(below_gold(town) * float(rule.get("altar_share", 0.0)))), "%s's altar" % town)


## The thief's cut to the robbers (robbers.thief_cut of what he lifted):
## what [param thief] of [param production] pays from his purse to move it.
func thief_cut(production: Production, thief: String, lifted: int) -> int:
	var rule := _robbers()
	var cut := floori(lifted * float(rule.get("thief_cut", 0.0)))
	if cut <= 0 or not production.spend(thief, cut, "the robbers' cut"):
		return 0
	band_add(str(rule.get("barrow", "")), cut, "%s's cut" % production.worker(thief).get("name", thief))
	return cut


## A robber of [param barrow] fallen with [param standing] of the band up
## (him among them): his share of the purse, taken out of it, in whole
## purses (the purse item's gold) and at most robbers.most. 0 if empty.
func band_share(barrow: String, standing: int) -> int:
	var rule := _robbers()
	var each := int(Items.def(str(rule.get("purse", "coin_purse"))).get("yield", {}).get("gold", 10))
	var share := mini(band_gold(barrow) / maxi(standing, 1), int(rule.get("most", 40)))
	share -= share % maxi(each, 1)
	if share <= 0:
		return 0
	_bands[barrow] = band_gold(barrow) - share
	print("[economy] a robber of %s falls with %d gold, %d left them, step %d" % [barrow, share, band_gold(barrow), now()])
	return share


## Robbers or a player lift [param amount] from [param town]'s altar: what
## was there to take.
func lift_below(town: String, amount: int) -> int:
	var taken := clampi(amount, 0, below_gold(town))
	_below[town] = below_gold(town) - taken
	if taken > 0:
		print("[economy] %d gold lifted from %s's altar below, %d left, step %d" % [taken, town, below_gold(town), now()])
	return taken


## Whether worker [param id] holds an official job the town pays
## (economy.json "official": the guard, the priest, the lawspeaker).
func is_official(id: String) -> bool:
	var official: Dictionary = rules.get("official", {})
	return production.worker(id).get("trades", []).any(func(trade: String) -> bool: return official.has(trade))


## Before anyone else, the treasury pays those it owes for what each
## town's next build lacks (522 amended, the coordinator: the tanner while
## the inn waits on leather), so the build isn't held up by a debt the
## town pays to others first. The rest are paid as before, in turn.
func _pay_head_first() -> void:
	# The town's officials before anyone (528 amended: "the town pays
	# official jobs"): what it owes them, from its treasury above its floor.
	for id in production.worker_ids():
		if is_official(id) and int(production.worker(id).get("owed", 0)) > 0:
			_pay_owed(id, str(production.worker(id)["town"]))
	if not shortfall.is_valid():
		return
	var ids: Array = _owed_what.keys()
	ids.sort()
	var lacking := {}
	for id: String in ids:
		var who := production.worker(id)
		if who.is_empty() or int(who.get("owed", 0)) <= 0:
			_owed_what.erase(id)
			continue
		var town := str(who["town"])
		if not lacking.has(town):
			lacking[town] = shortfall.call(town).get("needs", {})
		if (_owed_what[id] as Array).any(func(what: Variant) -> bool: return lacking[town].has(str(what))):
			_pay_owed(id, town)


## The hauler of [param town] to carry the next load (in town, not away,
## not [param gatherer]: the one who carried longest ago), "" for none.
func _hauler_for(town: String, gatherer: String, trade: String) -> String:
	if trade.is_empty():
		return ""
	var best := ""
	for id in production.worker_ids(town):
		var who := production.worker(id)
		if id == gatherer or Production.off_work(who) or production.outside(id) or trade not in who["trades"] or not str(who.get("master", "")).is_empty():
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
## gift, said in the ledger. A resource only its maker buys (maker_only:
## the herbs, 562) is banked unpaid. The gold paid now (the caller's to give).
func bank_sale(town: String, player_id: String, yields: Dictionary) -> int:
	var store: Dictionary = rules.get("store", {})
	var owed := int(_player_owed.get(player_id, {}).get(town, 0))
	if owed >= int(store.get("owed_cap", 30)):
		stockpile.note(town, "gold", 0, "gift:%s" % player_id, "the town can't pay %s for more: %s given" % [player_id, yields])
		return 0
	var price := 0
	for what: String in yields:
		if rules.get("maker_only", {}).has(what):
			continue  # The town has no use for it: only its maker buys it (562).
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


# --- Players' contributions (decision 499) ------------------------------------------

## What [param town]'s next build still needs in gold, for a player who
## would give toward it (Jeff: "players bank goods for gold and if they want
## they spend gold later to help the town with upgrades and defences"):
## {kind, gold}: the materials the store lacks at what it pays for them
## (raw_price x store.buy), what the town owes its gatherers and haulers,
## and the builder's fee, less what was given already. {} for no build
## waiting.
func contribution_wanted(town: String) -> Dictionary:
	var short: Dictionary = shortfall.call(town) if shortfall.is_valid() else {}
	if short.is_empty():
		return {}
	var buy := float(rules.get("store", {}).get("buy", 1.0))
	var gold := production.town_work_fee(int(short.get("steps", 0)))
	for what: String in short["needs"]:
		gold += ceili(raw_price(town, what) * buy * int(short["needs"][what]))
	for id in production.worker_ids(town):
		gold += int(production.worker(id).get("owed", 0))
	gold -= fund(town, str(short["kind"]))
	return {"kind": str(short["kind"]), "gold": maxi(gold, 0)}


## Player [param player_id] gives up to [param amount] of their gold toward
## [param town]'s next build (decision 499): never more than it still
## needs (contribution_wanted) or they have. Kept in a fund for that build,
## not the treasury: it pays first for deliveries of what the build lacks,
## then what the town owes its workers, then the builder's fee when it
## stands (settle_fund), the rest the town's; kept by the town if the plan
## is dropped. Thanked in town experience, contribute.gold_per_xp gold a
## point (contributed). The gold given (the caller tells the player).
func contribute(town: String, player_id: String, amount: int) -> int:
	var wanted := contribution_wanted(town)
	var give := mini(mini(amount, int(wanted.get("gold", 0))), gold(player_id))
	if give <= 0:
		return 0
	var kind := str(wanted["kind"])
	add_gold(player_id, -give, "given toward the town's %s" % kind)
	if not _funds.has(town):
		_funds[town] = {}
	_funds[town][kind] = fund(town, kind) + give
	stockpile.note(town, "gold", 0, "given:%s" % player_id, "%s gave %d gold toward the %s" % [player_id, give, kind])
	var xp := maxi(give / maxi(int(rules.get("contribute", {}).get("gold_per_xp", 2)), 1), 1)
	contributed.emit(town, player_id, kind, give, xp)
	return give


## Gold given toward [param town]'s [param kind], not yet spent.
func fund(town: String, kind: String) -> int:
	return int(_funds.get(town, {}).get(kind, 0))


## Up to [param amount] of [param town]'s fund for [param kind] taken to
## pay with: what it took.
func _from_fund(town: String, kind: String, amount: int) -> int:
	var have := fund(town, kind)
	var took := mini(have, maxi(amount, 0))
	if took <= 0:
		return 0
	if have - took > 0:
		_funds[town][kind] = have - took
	else:
		_funds[town].erase(kind)
		if _funds[town].is_empty():
			_funds.erase(town)
	return took


## [param kind] built in [param town] (Production's settle_fund): its fund
## pays builder [param worker_id] up to [param fee], the rest goes to the
## treasury ("kept by the town"). The gold paid to the builder.
func settle_fund(town: String, kind: String, worker_id: String, fee: int) -> int:
	var paid := _from_fund(town, kind, fee)
	if paid > 0:
		production.pay(worker_id, paid, "building the %s (given toward it)" % kind)
	_keep_fund(town, kind, "built")
	return paid


## What is left of [param town]'s fund for [param kind] goes to its treasury.
func _keep_fund(town: String, kind: String, why: String) -> void:
	var rest := _from_fund(town, kind, fund(town, kind))
	if rest > 0:
		stockpile.deposit(town, "gold", rest, "given:%s" % kind, "what was given toward the %s, kept (%s)" % [kind, why])


## A fund whose build is no longer planned (no build job of it in its town)
## is the town's.
func _drop_funds() -> void:
	for town: String in _funds.keys():
		for kind: String in _funds[town].keys():
			var planned := production.jobs().any(func(id: int) -> bool:
				var each := production.job(id)
				return each["kind"] == "build" and each["town"] == town and each["recipe"] == kind)
			if not planned:
				_keep_fund(town, kind, "no longer planned")


# --- Caravans to market (decision 504, economy's side) -------------------------------

## Whether goods of [param kind] are food, which a raid on a caravan takes
## (TradeRoutes.is_food): the store's food and meat, or a thing tagged food.
func is_food(kind: String) -> bool:
	return kind in ["food", "meat"] or "food" in Items.def(kind).get("tags", [])


## Once a day: the markets' buying eases (trade.caravan.recover), and each
## of [param town_ids] with a route to a market and no caravan out may send
## one (_send_caravan).
func _trade_turn(town_ids: Array) -> void:
	var day := now() / maxi(DayNight.day_steps, 1)
	if day == _trade_day:
		return
	var ease := float(rules.get("trade", {}).get("caravan", {}).get("recover", 0.0)) * (day - _trade_day if _trade_day >= 0 else 0)
	_trade_day = day
	for market: String in _bought:
		for what: String in _bought[market]:
			_bought[market][what] = maxf(float(_bought[market][what]) - ease, 0.0)
	town_ids.sort()
	for town: String in town_ids:
		if not trade_routes.is_valid() or _caravans.values().any(func(each: Dictionary) -> bool: return each["town"] == town):
			continue
		for way: Dictionary in trade_routes.call(town):
			if _send_caravan(town, way):
				break


## What the market [param market] pays for one [param what] from a town
## over a route of [param risk] (Jeff's trade routes; the coordinator's
## approval): its value x the market's want x (1 + risk_premium x risk), x
## 1 / (1 + bought / saturation) as it has bought more of it lately. The
## castle market's gold has no end in phase 2: saturation is its only
## brake.
func market_price(market: String, what: String, risk: float, more := 0) -> float:
	var rule: Dictionary = rules.get("trade", {}).get("caravan", {})
	var want := float(rules.get("trade", {}).get("markets", {}).get(market, {}).get("wants", {}).get(what, 0.0))
	var bought := float(_bought.get(market, {}).get(what, 0.0)) + more
	return float(rules.get("value", {}).get(what, 1)) * want * (1.0 + float(rule.get("risk_premium", 0.0)) * risk) \
		/ (1.0 + bought / maxf(float(rule.get("saturation", 20)), 1.0))


## [param count] of [param what] sold at [param market], each unit at the
## price after the last: the gold.
func _sale_of(market: String, what: String, count: int, risk: float) -> int:
	var gold := 0.0
	for i in count:
		gold += market_price(market, what, risk, i)
	return roundi(gold)


## The trip wage of a caravan's [param members] over [param eta] world
## ticks each way: trade.caravan.wage a day each.
func _trip_wage(eta: int) -> int:
	var days := 2.0 * eta * World.WORLD_TICK_STEPS / maxf(float(DayNight.day_steps), 1.0)
	return ceili(float(rules.get("trade", {}).get("caravan", {}).get("wage", 0)) * days)


## [param town] sends a caravan over route [param way] if it pays: who
## goes (one free traveller of trade.caravan.goes, never the seated
## merchant, 471, and a free hauler: both away while on the road), the
## store's surplus the market wants most (above its comfort or
## trade.caravan.keep and what a queued build needs), up to
## trade.caravan.load each; only when what it would fetch beats the trip
## wages and risk x the load's value. True if it went.
func _send_caravan(town: String, way: Dictionary) -> bool:
	var rule: Dictionary = rules.get("trade", {}).get("caravan", {})
	var market := str(way["market"])
	var wants: Dictionary = rules.get("trade", {}).get("markets", {}).get(market, {}).get("wants", {})
	if wants.is_empty():
		return false
	var members: Array[String] = []
	var goes: Array = rule.get("goes", [])
	var hauler := str(rules.get("haul", {}).get("trade", "hauler"))
	for wanted: Array in [goes, [hauler]]:
		for id in production.worker_ids(town):
			var who := production.worker(id)
			if id in members or Production.off_work(who) or production.outside(id) or not str(who.get("master", "")).is_empty() \
					or not str(who.get("apprentice", "")).is_empty() or not who["trades"].any(func(trade: String) -> bool: return trade in wanted):
				continue
			members.append(id)
			break
	if members.is_empty():
		return false
	var build: Dictionary = shortfall.call(town) if shortfall.is_valid() else {}
	var held: Dictionary = (production.job(int(build.get("job", 0))).get("cost", {}) if not build.is_empty() else {}).duplicate()
	# And what the town makes what the build lacks from (the tanner's hides
	# for the inn's leather), so a caravan never sells it away.
	var lacking: Dictionary = build.get("needs", {})
	if not lacking.is_empty() and catalog.is_valid():
		var cat: Dictionary = catalog.call()
		for id: String in cat:
			var made: Variant = cat[id].get("made", {})
			var yields: Variant = cat[id].get("yield", {})
			if not made is Dictionary or not yields is Dictionary:
				continue
			for what: String in yields:
				if lacking.has(what) and int(yields[what]) > 0:
					var batches := ceili(float(lacking[what]) / int(yields[what]))
					var from: Dictionary = made.get("from", {})
					for input: String in from:
						held[input] = int(held.get(input, 0)) + int(from[input]) * batches
	var kinds: Array = wants.keys()
	kinds.sort_custom(func(a: String, b: String) -> bool: return float(wants[a]) > float(wants[b]) or wants[a] == wants[b] and a < b)
	var room := int(rule.get("load", 10)) * members.size()
	var goods := {}
	var worth := 0.0
	var fetch := 0
	for what: String in kinds:
		var keep := maxi(int(rules.get("comfort", {}).get(what, 0)), int(rule.get("keep", 5))) + int(held.get(what, 0))
		var spare := mini(stockpile.count(town, what) - keep, room)
		if spare <= 0 or float(wants[what]) <= 0.0:
			continue
		goods[what] = spare
		room -= spare
		worth += float(rules.get("value", {}).get(what, 1)) * spare
		fetch += _sale_of(market, what, spare, float(way["risk"]))
		if room <= 0:
			break
	var wages := _trip_wage(int(way["eta"])) * members.size()
	if goods.is_empty() or float(fetch) <= wages + float(way["risk"]) * worth:
		return false
	var order := _luxury_order(town, market, int(way["eta"]))
	for what: String in goods:
		stockpile.take(town, what, int(goods[what]), "caravan to %s" % market)
	for id in members:
		production.set_away(id, true)
	var caravan := str(send_caravan.call(str(way["id"]), {"items": [], "goods": goods, "members": members}, town)) if send_caravan.is_valid() else ""
	if caravan.is_empty():
		for what: String in goods:
			stockpile.deposit(town, what, int(goods[what]), "caravan", "a caravan that couldn't set out")
		for id in members:
			production.set_away(id, false)
		return false
	_caravans[caravan] = {"town": town, "route": str(way["id"]), "market": market, "risk": float(way["risk"]), "eta": int(way["eta"]),
		"members": members.duplicate(), "goods": goods.duplicate(), "home": false, "order": order}
	print("[economy] %s sends a caravan to %s with %s (%s), to fetch about %d gold, step %d" % [town, market, goods,
		", ".join(members.map(func(id: String) -> String: return str(production.worker(id).get("name", id)))), fetch, now()])
	return true


## TradeRoutes.caravan_arrived: one of the town's caravans at the market
## sells there (the proceeds, whole and untaxed, to the treasury, the trip
## wages paid from them; trade.caravan.buy_share of the rest buys what the
## store is shortest of, carried home); one home again unloads into the
## store and its people are back.
func caravan_arrived(id: String, route_id: String, at_end: String, cargo: Dictionary) -> void:
	if not _caravans.has(id):
		return
	var caravan: Dictionary = _caravans[id]
	_caravans.erase(id)
	var town := str(caravan["town"])
	var members: Array = cargo.get("members", [])
	if bool(caravan["home"]):
		for what: String in cargo.get("goods", {}):
			if is_luxury(what):
				_stock_import(town, what, int(cargo["goods"][what]), caravan)
				continue
			stockpile.deposit(town, what, int(cargo["goods"][what]), "caravan", "brought home from %s" % caravan["market"])
		for who: String in members:
			production.set_away(who, false)
		print("[economy] %s's caravan is home from %s with %s, step %d" % [town, caravan["market"], cargo.get("goods", {}), now()])
		return
	var market := at_end
	var rule: Dictionary = rules.get("trade", {}).get("caravan", {})
	var proceeds := 0
	for what: String in cargo.get("goods", {}):
		var count := int(cargo["goods"][what])
		proceeds += _sale_of(market, what, count, float(caravan["risk"]))
		if not _bought.has(market):
			_bought[market] = {}
		_bought[market][what] = float(_bought[market].get(what, 0.0)) + count
	var wage := _trip_wage(int(caravan["eta"]))
	var wages := 0
	for who: String in members:
		var paid := mini(wage, proceeds - wages)
		if paid > 0:
			production.pay(who, paid, "the trip to %s" % market)
			wages += paid
	var rest := proceeds - wages
	var home := {}
	var order: Dictionary = caravan.get("order", {})
	if not order.is_empty():
		home[str(order["id"])] = 1
		rest -= int(order["cost"])
		print("[economy] %s's caravan buys a %s at %s for %d gold, for %s, step %d" % [town, Items.name_of(str(order["id"])), market,
			int(order["cost"]), order.get("name", TREASURY), now()])
	var budget := floori(rest * float(rule.get("buy_share", 0.0)))
	var sells: Array = rules.get("trade", {}).get("markets", {}).get(market, {}).get("sells", [])
	var shortest := ""
	for what: String in sells:
		if is_luxury(what):
			continue
		var need := float(stockpile.count(town, what)) / maxf(float(rules.get("comfort", {}).get(what, 1)), 1.0)
		if shortest.is_empty() or need < float(stockpile.count(town, shortest)) / maxf(float(rules.get("comfort", {}).get(shortest, 1)), 1.0):
			shortest = what
	if not shortest.is_empty() and budget > 0 and rest > 0:
		var unit := float(rules.get("value", {}).get(shortest, 1)) * float(rule.get("sell", 1.2))
		var count := mini(floori(budget / maxf(unit, 0.01)), int(rule.get("load", 10)) * maxi(members.size(), 1))
		if count > 0:
			home[shortest] = count
			rest -= ceili(count * unit)
	if rest > 0:
		stockpile.deposit(town, "gold", rest, "trade:%s" % market, "sold %s at %s for %d (wages %d)" % [cargo.get("goods", {}), market, proceeds, wages])
	elif rest < 0:
		# The order cost more than the sale fetched: the rest from what the
		# merchant paid in on the going (decision 514).
		stockpile.take(town, "gold", mini(-rest, stockpile.count(town, "gold")), "trade:%s" % market)
	print("[economy] %s's caravan sells %s at %s for %d gold: %d in wages, %d to the treasury, %s bought to bring home, step %d" % [town,
		cargo.get("goods", {}), market, proceeds, wages, maxi(rest, 0), home, now()])
	caravan_sold.emit(id, town, market, proceeds, wages)
	if members.is_empty():
		return
	var back := str(send_caravan.call(route_id, {"items": [], "goods": home, "members": members}, market)) if send_caravan.is_valid() else ""
	if back.is_empty():
		_caravan_home(town, home, members, "no way back")
		return
	caravan["home"] = true
	caravan["goods"] = home
	caravan["members"] = members.duplicate()
	_caravans[back] = caravan


## Goods [param goods] and people [param members] of [param town]'s
## caravan home at once (no way to walk): unloaded, and back.
func _caravan_home(town: String, goods: Dictionary, members: Array, why: String) -> void:
	for what: String in goods:
		stockpile.deposit(town, what, int(goods[what]), "caravan", "a caravan home (%s)" % why)
	for who: String in members:
		production.set_away(str(who), false)


## TradeRoutes.caravan_raided: what a camp took (food and people only:
## Jeff's rule; the people already captives, Towns) is off the caravan.
func caravan_raided(id: String, _route_id: String, camp_id: String, taken: Dictionary) -> void:
	if not _caravans.has(id):
		return
	var caravan: Dictionary = _caravans[id]
	for who: Variant in taken.get("members", []):
		caravan["members"].erase(str(who))
	for what: String in taken.get("goods", {}):
		caravan["goods"][what] = int(caravan["goods"].get(what, 0)) - int(taken["goods"][what])
		if int(caravan["goods"][what]) <= 0:
			caravan["goods"].erase(what)
	print("[economy] %s's caravan is struck by %s, who take %s, step %d" % [caravan["town"], camp_id, taken, now()])


## TradeRoutes.caravan_lost: the goods are gone (never gold: none travels);
## with no way on, its people come home.
func caravan_lost(id: String, _route_id: String, why: String) -> void:
	if not _caravans.has(id):
		return
	var caravan: Dictionary = _caravans[id]
	_caravans.erase(id)
	if why != "taken":
		_caravan_home(str(caravan["town"]), {}, caravan["members"], why)
	print("[economy] %s's caravan is lost (%s), with %s, step %d" % [caravan["town"], why, caravan["goods"], now()])


## The town's caravans on the road: id -> {town, market, goods, members, home}.
func caravans() -> Dictionary:
	return _caravans.duplicate(true)


# --- Luxuries (decision 514) ---------------------------------------------------------

## Whether thing [param id] is a luxury (decision 514; Jeff: "luxury goods
## that traders seek, sell to the rich"): tagged "luxury", taxed at
## tax_class luxury.
func is_luxury(id: String, cat := {}) -> bool:
	if cat.is_empty():
		cat = catalog.call()
	return "luxury" in cat.get(id, {}).get("tags", [])


## The luxuries in [param town]'s shop.
func _luxuries(town: String) -> Array[int]:
	var cat: Dictionary = catalog.call()
	var out: Array[int] = []
	for uid in stockpile.shop(town):
		if is_luxury(stockpile.book.id_of(uid), cat):
			out.append(uid)
	return out


## [param town]'s rich: residents whose purse stands above luxury.above.
func rich(town: String) -> Array[String]:
	var above := int(rules.get("luxury", {}).get("above", 60))
	var out: Array[String] = []
	for id in production.worker_ids(town):
		if int(production.worker(id)["purse"]) > above:
			out.append(id)
	return out


## [param town]'s merchant (a resident of trade luxury.trade, in town and
## at work): "" for none.
func _merchant(town: String) -> String:
	var trade := str(rules.get("luxury", {}).get("trade", "merchant"))
	for id in production.worker_ids(town):
		var who := production.worker(id)
		if trade in who["trades"] and not Production.off_work(who) and not production.outside(id):
			return id
	return ""


## What one [param id] costs landed from a market [param eta] steps away:
## value x caravan.sell, dearer by luxury.carry a day of the round trip.
func landed_cost(id: String, eta: int) -> int:
	var days := 2.0 * eta * World.WORLD_TICK_STEPS / maxf(float(DayNight.day_steps), 1.0)
	var sell := float(rules.get("trade", {}).get("caravan", {}).get("sell", 1.2))
	return ceili(value_of(id) * sell * (1.0 + float(rules.get("luxury", {}).get("carry", 0.0)) * days))


## A going caravan's order (decision 514): one luxury the market sells, the
## kind the shop has fewest of, while the town has a rich resident and its
## shop under luxury.stock. The merchant pays its landed cost into the
## treasury now (on a loan under the bank's cap if he must), the caravan
## buys it out of the sale; with no merchant, or one who can't pay, the
## treasury orders it above its floor. {} for none.
func _luxury_order(town: String, market: String, eta: int) -> Dictionary:
	var rule: Dictionary = rules.get("luxury", {})
	if rule.is_empty() or rich(town).is_empty():
		return {}
	var shelf := _luxuries(town)
	if shelf.size() >= int(rule.get("stock", 3)):
		return {}
	var cat: Dictionary = catalog.call()
	var kinds: Array = rules.get("trade", {}).get("markets", {}).get(market, {}).get("sells", []).filter(func(what: Variant) -> bool:
		return is_luxury(str(what), cat))
	if kinds.is_empty():
		return {}
	var held := {}
	for uid in shelf:
		held[stockpile.book.id_of(uid)] = int(held.get(stockpile.book.id_of(uid), 0)) + 1
	kinds.sort_custom(func(a: String, b: String) -> bool:
		return int(held.get(a, 0)) < int(held.get(b, 0)) or int(held.get(a, 0)) == int(held.get(b, 0)) and a < b)
	# Among the kinds the shelf has fewest of, a different one each day.
	var fewest := kinds.filter(func(what: Variant) -> bool: return int(held.get(what, 0)) == int(held.get(kinds[0], 0)))
	var id := str(fewest[int(now() / maxi(DayNight.day_steps, 1)) % fewest.size()])
	var cost := landed_cost(id, eta)
	var merchant := _merchant(town)
	if not merchant.is_empty() and _afford(merchant, town, cost):
		production.spend(merchant, cost, "a %s ordered from %s" % [Items.name_of(id), market])
		stockpile.deposit(town, "gold", cost, "order:%s" % merchant, "%s ordered a %s from %s" % [production.worker(merchant)["name"], Items.name_of(id), market])
		return {"id": id, "cost": cost, "merchant": merchant, "name": str(production.worker(merchant)["name"])}
	# A commission (514 amended): the rich resident whose want found the
	# shelf empty pays the landed cost up front, into the treasury as the
	# order; the merchant fetches it with no gold of his own.
	var buyer := str(_commissions.get(town, ""))
	_commissions.erase(town)
	var them := production.worker(buyer)
	if not them.is_empty() and str(them["town"]) == town and int(them["purse"]) >= cost:
		var asks := _folk_price(maxi(ceili(cost * float(rule.get("markup", 1.0))), value_of(id, cat)), buyer, merchant)
		if int(them["purse"]) >= asks:
			production.spend(buyer, cost, "a %s commissioned from %s" % [Items.name_of(id), market])
			stockpile.deposit(town, "gold", cost, "commission:%s" % buyer, "%s commissioned a %s from %s" % [them["name"], Items.name_of(id), market])
			print("[economy] %s commissions a %s from %s through %s, paying %d up front, step %d" % [them["name"], Items.name_of(id), market,
				production.worker(merchant).get("name", TREASURY), cost, now()])
			return {"id": id, "cost": cost, "merchant": merchant, "name": str(production.worker(merchant).get("name", TREASURY)), "for": buyer}
	if stockpile.count(town, "gold") - cost < int(rules.get("gold_floor", 0)):
		return {}
	return {"id": id, "cost": cost, "merchant": "", "name": TREASURY}


## [param count] of luxury [param id] home with [param caravan]: minted,
## on the shelf as its orderer's (the merchant's, or the town's), each at
## its landed cost (_landed) for the margin's tax.
func _stock_import(town: String, id: String, count: int, caravan: Dictionary) -> void:
	var order: Dictionary = caravan.get("order", {})
	var merchant := str(order.get("merchant", "")) if str(order.get("id", "")) == id else ""
	if not production.worker(merchant).is_empty() and str(production.worker(merchant)["town"]) != town:
		merchant = ""
	var cost := int(order.get("cost", landed_cost(id, int(caravan.get("eta", 0)))))
	if str(order.get("id", "")) == id and not str(order.get("for", "")).is_empty() and count > 0:
		_deliver_commission(town, id, cost, str(order["for"]), merchant, caravan)
		count -= 1
	for i in count:
		var uid := stockpile.book.mint(id, "imported", "from %s" % caravan["market"])
		stockpile.stock_shop(town, uid, "caravan from %s" % caravan["market"], merchant)
		_landed[uid] = cost
		print("[economy] %s puts a %s on the shelf at %s (landed %d, asks %d), step %d" % [production.worker(merchant).get("name", TREASURY),
			Items.name_of(id), town, cost, item_price(town, uid), now()])


## A commissioned [param id] home: its buyer [param buyer] pays the rest of
## the merchant's price (landed x markup, at least its value, by their
## factors) over the [param cost] they paid up front; the luxury tax on his
## margin to the treasury, the rest his (all the treasury's with no
## merchant). A buyer gone or short of the rest: it goes on the shelf,
## what they paid the town's.
func _deliver_commission(town: String, id: String, cost: int, buyer: String, merchant: String, caravan: Dictionary) -> void:
	var uid := stockpile.book.mint(id, "imported", "from %s" % caravan["market"])
	var them := production.worker(buyer)
	var base := maxi(ceili(cost * float(rules.get("luxury", {}).get("markup", 1.0))), value_of(id))
	var asks := _folk_price(base, buyer, merchant)
	var rest := maxi(asks - cost, 0)
	if them.is_empty() or str(them["town"]) != town or not production.spend(buyer, rest, "the rest for a %s" % Items.name_of(id)):
		stockpile.stock_shop(town, uid, "caravan from %s" % caravan["market"], merchant)
		_landed[uid] = cost
		return
	var before := stockpile.count(town, "gold")
	var seller := TREASURY
	if production.worker(merchant).is_empty():
		if rest > 0:
			stockpile.deposit(town, "gold", rest, "commission:%s" % buyer, "the rest for a %s" % Items.name_of(id))
	else:
		var cut := mini(Economy.taxed(maxi(base - cost, 0), goods_class(id), rules)[0], rest)
		if cut > 0:
			stockpile.deposit(town, "gold", cut, "tax:sale", "a %s for %s: tax %d on the margin" % [Items.name_of(id), them["name"], cut])
		production.pay(merchant, rest - cut, "a %s for %s" % [Items.name_of(id), them["name"]])
		seller = str(production.worker(merchant)["name"])
	_owned(uid, buyer, id, asks, seller, merchant)
	print("[economy] %s's commissioned %s is home: %d more to %s, %d of it tax to %s's treasury, step %d" % [them["name"], Items.name_of(id),
		rest, seller, stockpile.count(town, "gold") - before if seller != TREASURY else rest, town, now()])


## What [param town]'s shop asks for [param uid]: its price, and an import
## never under its landed cost x luxury.markup, a luxury never under its
## value (no want of the town's sets it: the rich pay it whole).
func item_price(town: String, uid: int, cat := {}) -> int:
	var id := stockpile.book.id_of(uid)
	var asked := price(town, id, SELL, cat)
	if is_luxury(id, cat):
		asked = maxi(asked, value_of(id, cat))
	if _landed.has(uid):
		asked = maxi(asked, ceili(int(_landed[uid]) * float(rules.get("luxury", {}).get("markup", 1.0))))
	return asked


## A rich resident's daily want of a luxury (decision 514): above
## luxury.above gold, with chance (purse - above) / luxury.span, they buy
## the cheapest luxury on the shelf they can pay from their purse (never on
## a loan), not one they made. Wine and spice are enjoyed; one tagged as
## luxury.kept (the ring) is theirs to keep. The seller's sale pays the
## luxury tax (tax_class luxury) into the treasury: on the merchant's
## margin, on a made one's price.
func _indulge(id: String, cat: Dictionary) -> void:
	var rule: Dictionary = rules.get("luxury", {})
	var who := production.worker(id)
	var town := str(who["town"])
	var purse := int(who["purse"])
	var above := int(rule.get("above", 60))
	if rule.is_empty() or purse <= above:
		return
	var chance := minf(float(purse - above) / maxf(float(rule.get("span", 100)), 1.0), 1.0)
	if float(absi(hash([id, now(), "luxury"])) % 1000) / 1000.0 >= chance:
		return
	var best := 0
	var best_cost := 0
	var best_base := 0
	for uid in _luxuries(town):
		var maker := stockpile.maker_of(town, uid)
		if maker == id:
			continue
		var base := item_price(town, uid, cat)
		var cost := _folk_price(base, id, maker)
		if cost <= purse and (best == 0 or cost < best_cost or cost == best_cost and uid < best):
			best = uid
			best_cost = cost
			best_base = base
	if best == 0:
		if not _commissions.has(town):
			_commissions[town] = id
		return
	var what := stockpile.book.id_of(best)
	var thing := Items.name_of(what)
	var maker := stockpile.maker_of(town, best)
	var before := stockpile.count(town, "gold")
	stockpile.take_from_shop(town, best, "folk:%s" % id)
	production.spend(id, best_cost, "a %s" % thing)
	var seller := _sale(town, maker, what, best_cost, "folk:%s" % id, "sold a %s to %s" % [thing, who["name"]], best_base, int(_landed.get(best, -1)))
	_landed.erase(best)
	_owned(best, id, what, best_cost, seller, maker)
	print("[economy] %s buys a %s from %s for %d gold, %d of it tax to %s's treasury, step %d" % [who["name"], thing, seller, best_cost,
		stockpile.count(town, "gold") - before if seller != TREASURY else 0, town, now()])


## Luxury [param uid] ([param what]) is now resident [param id]'s, bought
## for [param cost] from [param seller] (made or stocked by
## [param maker]): kept if tagged luxury.kept, else enjoyed; the card's
## trade both ways.
func _owned(uid: int, id: String, what: String, cost: int, seller: String, maker: String) -> void:
	var who := production.worker(id)
	var town := str(who["town"])
	var thing := Items.name_of(what)
	var kept: Array = rules.get("luxury", {}).get("kept", [])
	if catalog.call().get(what, {}).get("tags", []).any(func(tag: Variant) -> bool: return tag in kept):
		stockpile.book.place(uid, "resident:%s" % id, id, str(who["name"]))
		stockpile.book.note(uid, "bought", "by %s at %s for %d gold" % [who["name"], town, cost])
	else:
		stockpile.book.end(uid, "enjoyed", "by %s at %s" % [who["name"], town])
	production.note_trade(id, "bought a %s" % thing, cost, seller)
	if seller != TREASURY and not maker.is_empty():
		production.note_trade(maker, "sold a %s" % thing, cost, who["name"])
	stockpile.note(town, what, cost, "folk:%s" % id, "%s bought a %s from %s for %d gold" % [who["name"], thing, seller, cost])


## A maker's apprentice (decision 498 amended; Jeff: "makers have more
## expense - raw material and apprentices"): a maker (Items.TRADES) whose
## purse has stood above apprentice.above for apprentice.days takes one,
## a resident of the apprentice.from trade (the hauler) with no
## master, who then works with them (their jobs apprentice.speed faster,
## Production) for apprentice.wage a day from the maker's purse; let go
## when the purse falls under apprentice.below or can't pay the day's wage.
func _apprentice_turn(id: String, town: String) -> void:
	var rule: Dictionary = rules.get("apprentice", {})
	var who := production.worker(id)
	if rule.is_empty() or not who["trades"].any(func(trade: String) -> bool: return trade in Items.TRADES):
		return
	var purse := int(who["purse"])
	var apprentice := str(who.get("apprentice", ""))
	if not apprentice.is_empty():
		var day := maxi(DayNight.day_steps, 1)
		var wage := int(rule.get("wage", 0))
		var due := now() - int(_apprentice_paid.get(id, now())) >= day
		var name := str(production.worker(apprentice).get("name", apprentice))
		if purse >= int(rule.get("below", 20)) and (not due or wage <= 0 or production.spend(id, wage, "%s's wage" % name)):
			if due:
				_apprentice_paid[id] = now()
				if wage > 0:
					production.pay(apprentice, wage, "an apprentice's wage")
			return
		production.set_apprentice(id, "")
		_apprentice_paid.erase(id)
		_say(town, id, "%s lets %s go" % [who["name"], name])
		return
	_apprentice_paid.erase(id)
	if purse <= int(rule.get("above", 60)):
		production.set_above_since(id, -1)
		return
	if not who.has("above_since"):
		production.set_above_since(id, now())
		return
	if now() - int(who["above_since"]) < int(float(rule.get("days", 3)) * maxi(DayNight.day_steps, 1)):
		return
	var from := str(rule.get("from", "hauler"))
	for other in production.worker_ids(town):
		var them := production.worker(other)
		if other == id or from not in them["trades"] or Production.off_work(them) or not str(them.get("master", "")).is_empty():
			continue
		if production.set_apprentice(id, other):
			production.set_above_since(id, -1)
			_apprentice_paid[id] = now()
			_say(town, id, "%s takes %s as an apprentice" % [who["name"], them["name"]])
			return


## An apprentice taken or let go: the town's ledger and the log.
func _say(town: String, id: String, what: String) -> void:
	stockpile.note(town, "gold", 0, "apprentice:%s" % id, what)
	print("[economy] %s, step %d" % [what, now()])


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
		"player_owed": _player_owed.duplicate(true), "apprentice_paid": _apprentice_paid.duplicate(), "funds": _funds.duplicate(true),
		"caravans": _caravans.duplicate(true), "bought": _bought.duplicate(true), "trade_day": _trade_day, "floor_day": _floor_day, "alms": _alms.duplicate(), "below": _below.duplicate(), "down_day": _down_day.duplicate(), "bands": _bands.duplicate(), "band_day": _band_day, "landed": _landed.duplicate(), "owed_what": _owed_what.duplicate(true),
		"commissions": _commissions.duplicate()}


func from_dict(saved: Dictionary) -> void:
	var paid: Variant = saved.get("paid", {})
	if paid is Dictionary:
		for town: Variant in paid:
			if paid[town] is Dictionary:
				_paid[str(town)] = {}
				for what: Variant in paid[town]:
					_paid[str(town)][str(what)] = maxf(float(paid[town][what]), 0.0)
	var caravans: Variant = saved.get("caravans", {})
	if caravans is Dictionary:
		for id: Variant in caravans:
			if caravans[id] is Dictionary:
				_caravans[str(id)] = (caravans[id] as Dictionary).duplicate(true)
	var bought: Variant = saved.get("bought", {})
	if bought is Dictionary:
		for market: Variant in bought:
			if bought[market] is Dictionary:
				_bought[str(market)] = {}
				for what: Variant in bought[market]:
					_bought[str(market)][str(what)] = maxf(float(bought[market][what]), 0.0)
	_trade_day = int(saved.get("trade_day", -1))
	_floor_day = int(saved.get("floor_day", -1))
	_band_day = int(saved.get("band_day", -1))
	var bands: Variant = saved.get("bands", {})
	if bands is Dictionary:
		for barrow: Variant in bands:
			_bands[str(barrow)] = maxi(int(bands[barrow]), 0)
	for key: String in ["alms", "below", "down_day"]:
		var each: Variant = saved.get(key, {})
		if each is Dictionary:
			var into: Dictionary = {"alms": _alms, "below": _below, "down_day": _down_day}[key]
			for town: Variant in each:
				into[str(town)] = int(each[town])
	var owed_what: Variant = saved.get("owed_what", {})
	if owed_what is Dictionary:
		for id: Variant in owed_what:
			if owed_what[id] is Array:
				_owed_what[str(id)] = (owed_what[id] as Array).map(func(what: Variant) -> String: return str(what))
	var commissions: Variant = saved.get("commissions", {})
	if commissions is Dictionary:
		for town: Variant in commissions:
			_commissions[str(town)] = str(commissions[town])
	var landed: Variant = saved.get("landed", {})
	if landed is Dictionary:
		for uid: Variant in landed:
			_landed[int(uid)] = int(landed[uid])
	var funds: Variant = saved.get("funds", {})
	if funds is Dictionary:
		for town: Variant in funds:
			if funds[town] is Dictionary:
				for kind: Variant in funds[town]:
					if int(funds[town][kind]) > 0:
						if not _funds.has(str(town)):
							_funds[str(town)] = {}
						_funds[str(town)][str(kind)] = int(funds[town][kind])
	var apprentice_paid: Variant = saved.get("apprentice_paid", {})
	if apprentice_paid is Dictionary:
		for id: Variant in apprentice_paid:
			_apprentice_paid[str(id)] = int(apprentice_paid[id])
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
