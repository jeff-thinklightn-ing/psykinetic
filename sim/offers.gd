class_name Offers
## What a town's person can offer when spoken to (decision 435, the data
## side of ui's step 4): from records only, never invented. At most one
## offer per kind and "offers.max" (3) in all, in this order: a shop line
## (a thing in the town's shop that this resident's trade makes, at
## economy's price), one true commission (kin held captive brought home, a
## raiders' camp cleared, a thing the town is short of fetched to the
## store), a rumour (the newest believed hearsay, 378; an official offers
## the weightiest lore fact it knows instead) and a plea (help with a loan,
## or a word carried to a neighbour the resident holds a grudge against).
## Each offer: {id, kind, title (three or four words for a button), words
## (one plain sentence), what (the record it comes from), accept ("buy",
## "take", "lend", "carry" or "" for nothing), cost (gold, 0 for none)}.
##
## Accepting a commission or an errand puts an "ask" on the resident's card
## ("asks": [{id, kind, sub, by, by_name, step, town, worker, what}], saved
## with the worker record, 398), mirrored on the player's record by Main
## (the "asked" and "done" callbacks); at most one open per resident and
## "offers.per_player" (3) per player; one not met in "offers.days" (7)
## lapses with a fact told once. Commissions are met from the world's
## signals (rescued, place_taken, deposited) with the player in the camp's
## area for a rescue or a camp, and paid from the town's treasury by
## economy (pay_commission, economy.json "commissions"); an errand is met
## when the player next speaks to the one it is for. The voice is told the
## offers as facts (voice_words), never lines. No model call.
##
## Main gives [member ctx] (World's records and callables); a test gives
## its own: "production" (Production) and Callables "goods" (town) ->
## [{uid, id, price}], "catalog" () -> {id: entry}, "captives" (town) ->
## [{id, name, by, held_by}], "camps" () -> [{id, area, faction}],
## "hostile" (faction, town) -> bool, "short" (town) -> [item ids],
## "area_name" (area) -> String, "pay_loan" (player_id, worker_id, gold)
## -> paid, "pay_commission" (player_id, town, gold) -> paid, "pay" () ->
## {rescue, camp, fetch}, "zone_of" (player_id) -> area, "name_of"
## (player_id) -> String, "asked" (player_id, ask) -> void, "done"
## (player_id, ask, line, paid) -> void. A Callable missing or invalid
## leaves out what needs it.

const FILE := "res://levels/residents.json"
const DEFAULTS := {"max": 3, "per_player": 3, "days": 7, "fetch": 6}
const SHOP := "shop"
const COMMISSION := "commission"
const RUMOUR := "rumour"
const PLEA := "plea"
const BUY := "buy"
const TAKE := "take"
const LEND := "lend"
const CARRY := "carry"
const RESCUE := "rescue"
const CAMP := "camp"
const FETCH := "fetch"
const ERRAND := "errand"
## Parts of an offer id ("<worker>|<kind>|<key>"; worker ids hold ":").
const SEP := "|"
## The hidden types with offers of their own (decision 440; Townsfolk's).
const SCHOLAR := "scholar"
const MERCHANT := "merchant"
## Talk of goods and prices, which a merchant's rumour prefers.
const TRADE_WORDS := "(?i)\\b(price\\w*|gold|coin\\w*|cost\\w*|sell\\w*|sold|buy\\w*|bought|short of|dear\\w*|cheap\\w*)\\b"
const KIN_WORDS := {"sister or brother": {"she": "sister", "he": "brother"}, "cousin": {}, "parent and child": {}}

static var ctx: Dictionary = {}
static var _settings := {}


static func settings() -> Dictionary:
	if _settings.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE)) if FileAccess.file_exists(FILE) else null
		_settings = DEFAULTS.duplicate()
		if data is Dictionary and data.get("offers") is Dictionary:
			_settings.merge(data["offers"], true)
	return _settings


## Uses [param given] in place of the file's "offers" ({} to read it again): tests.
static func use_settings(given: Dictionary) -> void:
	_settings = {}
	if not given.is_empty():
		_settings = DEFAULTS.duplicate()
		_settings.merge(given, true)


static func _call(given: Dictionary, key: String, args: Array = []) -> Variant:
	var callable: Variant = given.get(key)
	if callable is Callable and callable.is_valid():
		return callable.callv(args)
	return null


# --- The offers -------------------------------------------------------------------------

## [param worker_id]'s offers to [param player_id] now: the player's open
## asks of them first ("open": true), then at most "max" fresh ones.
static func of(worker_id: String, player_id: String, given: Dictionary = ctx) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var production: Production = given.get("production")
	if production == null or worker_id.begins_with(Townsfolk.COMPANION):
		return out
	var who := production.worker(worker_id)
	if who.is_empty():
		return out
	var card := Townsfolk.card_of(production, worker_id)
	if card.is_empty():
		return out
	var town := str(who.get("town", ""))
	var open := 0
	for ask: Dictionary in card.get("asks", []):
		if str(ask.get("by", "")) == player_id:
			out.append(_as_open(ask))
			open += 1
	# What they think of this player scales it (decision 443): one they feel
	# wronged by gets nothing but a plea; one they trust, the commission
	# first and a second open one.
	var regard := Standing.words(card, player_id)
	var trusted := regard == "trusted"
	var fresh: Array[Dictionary] = []
	if regard != "wronged":
		var shop := _shop_offer(worker_id, who, town, given)
		var job := {}
		if card.get("asks", []).size() < (2 if trusted else 1) and open < (2 if trusted else 1):
			job = _commission_offer(worker_id, who, card, town, given)
		for offer: Dictionary in ([job, shop] if trusted else [shop, job]):
			if not offer.is_empty():
				fresh.append(offer)
		var rumour := _rumour_offer(worker_id, who, given)
		if not rumour.is_empty():
			fresh.append(rumour)
	if open == 0:
		var plea := _plea_offer(worker_id, who, card, town, given)
		if not plea.is_empty():
			fresh.append(plea)
	out.append_array(fresh.slice(0, int(settings().get("max", 3))))
	return out


static func _offer(worker_id: String, kind: String, key: String, title: String, words: String, what: Dictionary, accept: String, cost := 0) -> Dictionary:
	return {"id": SEP.join([worker_id, kind, key]), "kind": kind, "title": title, "words": words, "what": what, "accept": accept, "cost": cost}


static func _as_open(ask: Dictionary) -> Dictionary:
	var out := _offer(str(ask.get("worker", "")), str(ask.get("kind", COMMISSION)), str(ask.get("sub", "")), str(ask.get("title", "")),
		str(ask.get("words", "")), ask.get("what", {}), "", 0)
	out["id"] = str(ask.get("id", out["id"]))
	out["open"] = true
	return out


static func _trade_of(who: Dictionary) -> String:
	var trades: Array = who.get("trades", [])
	return str(trades[0]) if not trades.is_empty() else ""


## A thing in the town's shop that this resident's trade makes, the first
## by uid, at the shop's price: "I have a knife at the counter for 12 gold."
static func _shop_offer(worker_id: String, who: Dictionary, town: String, given: Dictionary) -> Dictionary:
	var trade := _trade_of(who)
	var goods: Variant = _call(given, "goods", [town])
	var catalog: Variant = _call(given, "catalog")
	if trade.is_empty() or not goods is Array or not catalog is Dictionary:
		return {}
	# A merchant deals in everything: any good at the counter, the dearest
	# first (decision 440); anyone else, only their own trade's making.
	var merchant := str(who.get("type", "")) == MERCHANT
	var wares: Array = goods.filter(func(each: Variant) -> bool: return each is Dictionary)
	if merchant:
		wares.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("price", 0)) > int(b.get("price", 0)) or int(a.get("price", 0)) == int(b.get("price", 0)) and int(a.get("uid", 0)) < int(b.get("uid", 0)))
	for good: Dictionary in wares:
		var entry: Dictionary = catalog.get(str(good.get("id", "")), {})
		if not merchant and str(entry.get("made", {}).get("by", "")) != trade:
			continue
		var name := str(entry.get("name", str(good.get("id", "")).replace("_", " ")))
		var price := int(good.get("price", 0))
		return _offer(worker_id, SHOP, str(good.get("uid", 0)), "%s, %d gold" % [_upper_first(Companion._a(name)), price],
			"I have %s at the counter for %d gold." % [Companion._a(name), price],
			{"uid": int(good.get("uid", 0)), "id": str(good.get("id", "")), "price": price, "town": town}, BUY, price)
	return {}


## One commission, the first true: kin held captive, a raiders' camp, a
## thing the town is short of.
static func _commission_offer(worker_id: String, who: Dictionary, card: Dictionary, town: String, given: Dictionary) -> Dictionary:
	var production: Production = given["production"]
	var kin: Dictionary = card.get("kin", {})
	var captives: Variant = _call(given, "captives", [town])
	var camps: Variant = _call(given, "camps")
	if not kin.is_empty() and captives is Array:
		var ids: Array = kin.keys()
		ids.sort()
		for other: String in ids:
			for captive: Variant in captives:
				if not captive is Dictionary or str(captive.get("id", "")) != other:
					continue
				var name := str(captive.get("name", production.worker(other).get("name", other)))
				var held_by := str(captive.get("held_by", ""))
				var area := _camp_area(camps, held_by)
				var where := str(_call(given, "area_name", [area])) if not area.is_empty() else ""
				var faction := ResidentCard.faction_name(str(captive.get("by", "")))
				var relation := _relation(str(kin[other]), production.worker(other).get("card", {}))
				var words := "Bring my %s %s home from the camp of %s%s." % [relation, name, faction, " at " + where if not where.is_empty() else ""]
				return _offer(worker_id, COMMISSION, RESCUE + ":" + other, "Bring %s home" % name, words,
					{"sub": RESCUE, "captive": other, "name": name, "held_by": held_by, "area": area, "faction": str(captive.get("by", ""))}, TAKE)
	var saw_raiders := false
	for fact: Variant in card.get("facts", []):
		if fact is Dictionary and str(fact.get("text", "")).containsn("raid"):
			saw_raiders = true
			break
	if saw_raiders and camps is Array:
		var hostile: Array[Dictionary] = []
		for camp: Variant in camps:
			if camp is Dictionary and bool(_call(given, "hostile", [str(camp.get("faction", "")), town])):
				hostile.append(camp)
		hostile.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("id", "")) < str(b.get("id", "")))
		if not hostile.is_empty():
			var camp: Dictionary = hostile[0]
			var area := str(camp.get("area", ""))
			var where := str(_call(given, "area_name", [area]))
			var faction := ResidentCard.faction_name(str(camp.get("faction", "")))
			return _offer(worker_id, COMMISSION, CAMP + ":" + str(camp.get("id", "")), "Clear the camp",
				"Clear the camp of %s%s, before they come again." % [faction, " at " + where if not where.is_empty() else ""],
				{"sub": CAMP, "camp": str(camp.get("id", "")), "area": area, "faction": str(camp.get("faction", ""))}, TAKE)
	var short: Variant = _call(given, "short", [town])
	if short is Array and not short.is_empty():
		var wants: Array = short.duplicate()
		wants.sort()
		var item := str(wants[0])
		var count := int(settings().get("fetch", 6))
		return _offer(worker_id, COMMISSION, FETCH + ":" + item, "Fetch %d %s" % [count, item.replace("_", " ")],
			"The town is short of %s: bring %d to the store and the coffer pays." % [item.replace("_", " "), count],
			{"sub": FETCH, "item": item, "count": count, "got": 0}, TAKE)
	return {}


static func _camp_area(camps: Variant, camp_id: String) -> String:
	if camps is Array:
		for camp: Variant in camps:
			if camp is Dictionary and str(camp.get("id", "")) == camp_id:
				return str(camp.get("area", ""))
	return ""


## "brother" for a sister-or-brother kin who is "he"; the kind's own word
## else ("cousin", "kin").
static func _relation(kind: String, their_card: Variant) -> String:
	var pronoun := str(their_card.get("traits", {}).get("pronoun", "")) if their_card is Dictionary else ""
	var by_pronoun: Dictionary = KIN_WORDS.get(kind, {})
	if by_pronoun.has(pronoun):
		return str(by_pronoun[pronoun])
	return "cousin" if kind == "cousin" else "kin"


## The newest believed hearsay, as told; an official's weightiest lore
## fact instead.
static func _rumour_offer(worker_id: String, who: Dictionary, given: Dictionary) -> Dictionary:
	var trade := _trade_of(who)
	var type := str(who.get("type", ""))
	# An official's, or a scholar's (decision 440), is the weightiest lore
	# fact it knows, never hearsay.
	if Lore.binding(trade, type) == "official" or type == SCHOLAR:
		var facts := Lore.known_by(Lore.knower_for(trade), PackedStringArray(), "agreed", type)
		facts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("weight", 0)) > float(b.get("weight", 0)))
		if facts.is_empty():
			return {}
		var text := str(facts[0].get("text", "")).strip_edges()
		return _offer(worker_id, RUMOUR, "lore", "What %s knows" % who.get("name", "they"), text if text.ends_with(".") else text + ".", {"lore": true}, "")
	var believed := Hearsay.believed(who.get("heard", []))
	if believed.is_empty():
		return {}
	var entry: Dictionary = believed.back()
	if type == MERCHANT:
		# A merchant has an ear for talk of goods and prices (decision 440):
		# the newest such, else the newest.
		var trade_talk := RegEx.create_from_string(TRADE_WORDS)
		for i in range(believed.size() - 1, -1, -1):
			if trade_talk.search(str(believed[i].get("text", ""))) != null:
				entry = believed[i]
				break
	var from := str(entry.get("from", ""))
	var where := Hearsay.place_words(str(entry.get("where", "")))
	return _offer(worker_id, RUMOUR, str(entry.get("id", "h")), "What %s said" % (from if not from.is_empty() else "someone"),
		"%s told me%s that %s." % [from if not from.is_empty() else "Someone", " " + where if not where.is_empty() else "",
		Hearsay._lower_first(str(entry.get("text", "")))], {"heard": str(entry.get("id", ""))}, "")


## Help with a loan (economy's pay_loan), else a word to one the resident
## holds a grudge against.
static func _plea_offer(worker_id: String, who: Dictionary, card: Dictionary, town: String, given: Dictionary) -> Dictionary:
	var production: Production = given["production"]
	var owed := ceili(float(who.get("loan", 0.0)))
	var can_lend: Variant = given.get("pay_loan")
	if owed > 0 and can_lend is Callable and can_lend.is_valid():
		return _offer(worker_id, PLEA, "loan", "Help with a debt", "I owe the town %d gold; could you spare some of it?" % owed,
			{"loan": owed, "town": town}, LEND, owed)
	for other: Variant in card.get("grudge", []):
		var theirs := production.worker(str(other))
		if theirs.is_empty():
			continue
		var name := str(theirs.get("name", other))
		return _offer(worker_id, PLEA, "word:" + str(other), "A word for %s" % name,
			"If you see %s, tell %s the matter between us is forgotten." % [name, _them(theirs.get("card", {}))],
			{"to": str(other), "name": name}, CARRY)
	return {}


static func _upper_first(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1)


static func _them(their_card: Variant) -> String:
	var pronoun := str(their_card.get("traits", {}).get("pronoun", "")) if their_card is Dictionary else ""
	return {"she": "her", "he": "him"}.get(pronoun, "them")


# --- Accepting --------------------------------------------------------------------------

## [param player_id] (named [param player_name]) accepts [param offer_id]
## of [param worker_id], with [param gold] for a loan: {"line": the party
## log's words or "", "buy": a uid for Main to sell them at the counter,
## or 0, "ok": whether anything happened}.
static func accept(worker_id: String, player_id: String, player_name: String, offer_id: String, gold := 0, given: Dictionary = ctx) -> Dictionary:
	var out := {"line": "", "buy": 0, "ok": false}
	var production: Production = given.get("production")
	if production == null:
		return out
	var offer := {}
	for each: Dictionary in of(worker_id, player_id, given):
		if str(each.get("id", "")) == offer_id and not bool(each.get("open", false)):
			offer = each
	if offer.is_empty():
		return out
	var who := production.worker(worker_id)
	var name := str(who.get("name", worker_id))
	var now := production.now()
	match str(offer.get("accept", "")):
		BUY:
			out["buy"] = int(offer["what"].get("uid", 0))
			out["ok"] = out["buy"] > 0
		TAKE:
			if _open_count(production, player_id) >= int(settings().get("per_player", 3)):
				out["line"] = "%s has taken on enough already." % player_name
				return out
			var ask := {"id": offer_id, "kind": COMMISSION, "sub": str(offer["what"].get("sub", "")), "by": player_id, "by_name": player_name,
				"step": now, "town": str(who.get("town", "")), "worker": worker_id, "title": offer["title"], "words": offer["words"],
				"what": offer["what"].duplicate(true)}
			_add_ask(production, worker_id, ask)
			_call(given, "asked", [player_id, ask])
			Townsfolk.learn(production, worker_id, "%s promised %s: %s" % [player_name, name, _promise(ask)])
			out["line"] = "%s takes %s's commission: %s." % [player_name, name, _promise(ask)]
			out["ok"] = true
		LEND:
			var owed := maxi(int(offer["what"].get("loan", 0)), 1)
			var paid := int(_call(given, "pay_loan", [player_id, worker_id, maxi(gold, 0)]))
			if paid > 0:
				Townsfolk.learn(production, worker_id, "%s paid %d gold of %s's debt to the town." % [player_name, paid, name])
				var quarters := int(floor(paid * 4.0 / owed))
				var cleared := float(production.worker(worker_id).get("loan", 0.0)) <= 0.0
				var delta := Standing.setting("loan_quarter") * quarters + (Standing.setting("loan_cleared") if cleared else 0)
				_regard(production, worker_id, player_id, delta, "cleared their debt to the town" if cleared else "paid %d gold of their debt" % paid)
				out["line"] = "%s gives %d gold toward %s's debt." % [player_name, paid, name]
				out["ok"] = true
		CARRY:
			var ask := {"id": offer_id, "kind": ERRAND, "sub": ERRAND, "by": player_id, "by_name": player_name, "step": now,
				"town": str(who.get("town", "")), "worker": worker_id, "title": offer["title"], "words": offer["words"],
				"what": offer["what"].duplicate(true)}
			_add_ask(production, worker_id, ask)
			_call(given, "asked", [player_id, ask])
			Townsfolk.learn(production, worker_id, "%s promised to carry %s's word to %s." % [player_name, name, offer["what"].get("name", "")])
			out["line"] = "%s will carry %s's word to %s." % [player_name, name, offer["what"].get("name", "")]
			out["ok"] = true
	return out


static func _promise(ask: Dictionary) -> String:
	var what: Dictionary = ask.get("what", {})
	match str(ask.get("sub", "")):
		RESCUE:
			return "to bring %s home" % what.get("name", "")
		CAMP:
			return "to clear the camp of %s" % ResidentCard.faction_name(str(what.get("faction", "")))
		FETCH:
			return "to bring %d %s to the store" % [int(what.get("count", 0)), str(what.get("item", "")).replace("_", " ")]
	return str(ask.get("title", "")).to_lower()


static func _add_ask(production: Production, worker_id: String, ask: Dictionary) -> void:
	var card := Townsfolk.card_of(production, worker_id)
	card.get_or_add("asks", []).append(ask)
	production.set_card(worker_id, card)


static func _drop_ask(production: Production, worker_id: String, ask_id: String) -> void:
	var card := Townsfolk.card_of(production, worker_id)
	var asks: Array = card.get("asks", [])
	card["asks"] = asks.filter(func(each: Dictionary) -> bool: return str(each.get("id", "")) != ask_id)
	production.set_card(worker_id, card)


## [param player_id]'s standing with [param worker_id] moved by [param delta]
## for [param why] (decision 443), on the card.
static func _regard(production: Production, worker_id: String, player_id: String, delta: int, why: String) -> void:
	if delta == 0 or player_id.is_empty():
		return
	var card := Townsfolk.card_of(production, worker_id)
	if card.is_empty():
		return
	Standing.bump(card, player_id, delta, why, production.now())
	production.set_card(worker_id, card)


## [param player_id] (named [param player_name]) put [param item_id] into
## [param worker_id]'s hands (decision 443): a gift, worth more when it is
## their favourite food or a tool; the card remembers. The party log's line.
static func gift(player_id: String, player_name: String, worker_id: String, item_id: String, given: Dictionary = ctx) -> String:
	var production: Production = given.get("production")
	if production == null or player_id.is_empty():
		return ""
	var card := Townsfolk.card_of(production, worker_id)
	if card.is_empty():
		return ""
	var catalog: Variant = _call(given, "catalog")
	var entry: Dictionary = catalog.get(item_id, {}) if catalog is Dictionary else {}
	var name := str(entry.get("name", item_id.replace("_", " ")))
	var food := str(card.get("traits", {}).get("food", "")).to_lower()
	var favourite: bool = (not food.is_empty() and (food.contains(name.to_lower()) or name.to_lower().contains(food.trim_suffix("s")))) \
			or "tool" in entry.get("tags", [])
	var who := str(production.worker(worker_id).get("name", worker_id))
	_regard(production, worker_id, player_id, Standing.setting("gift_favourite" if favourite else "gift"), "gave them %s" % Companion._a(name))
	Townsfolk.learn(production, worker_id, "%s gave %s %s." % [player_name, who, Companion._a(name)])
	return "%s gives %s %s%s." % [player_name, who, Companion._a(name), ", and it is what they like best" if favourite else ""]


static func _open_count(production: Production, player_id: String) -> int:
	var count := 0
	for id: String in production.worker_ids():
		for ask: Variant in production.worker(id).get("card", {}).get("asks", []):
			if ask is Dictionary and str(ask.get("by", "")) == player_id:
				count += 1
	return count


## Every open ask in [param town] ("" for all), as [worker_id, ask].
static func _asks(production: Production, town := "") -> Array:
	var out := []
	for id: String in production.worker_ids(town):
		for ask: Variant in production.worker(id).get("card", {}).get("asks", []):
			if ask is Dictionary:
				out.append([id, ask])
	return out


# --- Meeting them -----------------------------------------------------------------------

## An ask met (or not): dropped from the card, the fact on it, the
## treasury's pay to the player through economy, Main told ("done").
static func _close(worker_id: String, ask: Dictionary, fact: String, line: String, pay_key: String, units := 1, given: Dictionary = ctx,
		regard_key := "", regard_why := "") -> void:
	var production: Production = given["production"]
	var player_id := str(ask.get("by", ""))
	var paid := 0
	if not regard_key.is_empty():
		_regard(production, worker_id, player_id, Standing.setting(regard_key), regard_why)
	if not pay_key.is_empty():
		var pay: Variant = _call(given, "pay")
		var each := int(pay.get(pay_key, 0)) if pay is Dictionary else 0
		if each * units > 0:
			paid = int(_call(given, "pay_commission", [player_id, str(ask.get("town", "")), each * units]))
	_drop_ask(production, worker_id, str(ask.get("id", "")))
	Townsfolk.learn(production, worker_id, fact)
	_call(given, "done", [player_id, ask, line + (" The town pays %d gold." % paid if paid > 0 else ""), paid])


## Captive [param who_id] is home in [param town] (Towns.rescued): the
## asks to bring them home are met, by the player when they stand in the
## camp's area, else by another's hand.
static func rescued(town: String, who_id: String, given: Dictionary = ctx) -> void:
	var production: Production = given.get("production")
	if production == null:
		return
	# Kin brought home with no commission asked (decision 443): the players
	# standing in a camp's area are the ones who did it.
	var asked: Array[String] = []
	for pair: Array in _asks(production, town):
		if str(pair[1].get("sub", "")) == RESCUE and str(pair[1].get("what", {}).get("captive", "")) == who_id:
			asked.append(str(pair[0]))
	var camps: Variant = _call(given, "camps")
	var rescuers := {}
	if camps is Array:
		for camp: Variant in camps:
			var there: Variant = _call(given, "players_in", [str(camp.get("area", ""))]) if camp is Dictionary else null
			if there is Array:
				for player_id: Variant in there:
					rescuers[str(player_id)] = true
	if not rescuers.is_empty():
		var name := str(production.worker(who_id).get("name", who_id))
		for id: String in production.worker_ids(town):
			var card: Dictionary = production.worker(id).get("card", {})
			if id in asked or not card.get("kin", {}).has(who_id):
				continue
			for player_id: String in rescuers:
				_regard(production, id, player_id, Standing.setting("kin_home"), "brought %s home" % name)
	for pair: Array in _asks(production, town):
		var ask: Dictionary = pair[1]
		if str(ask.get("sub", "")) != RESCUE or str(ask.get("what", {}).get("captive", "")) != who_id:
			continue
		var name := str(ask["what"].get("name", who_id))
		var by := str(ask.get("by_name", "someone"))
		var there := str(_call(given, "zone_of", [str(ask.get("by", ""))])) == str(ask["what"].get("area", "")) \
				or str(ask["what"].get("area", "")).is_empty()
		if there:
			_close(pair[0], ask, "%s brought %s home." % [by, name], "%s brought %s home, as promised." % [by, name], RESCUE, 1, given,
				RESCUE, "brought %s home" % name)
		else:
			_close(pair[0], ask, "%s came home, though not by %s's hand." % [name, by], "%s is home; %s's promise is kept by another." % [name, by], "", 1, given)


## Camp [param camp_id] changed hands from [param from] to [param to]
## (Holdings.place_taken): the asks to clear it are met when it is no
## longer the raiders' (the player standing in its area).
static func camp_taken(camp_id: String, _from: String, to: String, given: Dictionary = ctx) -> void:
	var production: Production = given.get("production")
	if production == null:
		return
	for pair: Array in _asks(production):
		var ask: Dictionary = pair[1]
		if str(ask.get("sub", "")) != CAMP or str(ask.get("what", {}).get("camp", "")) != camp_id or to == str(ask["what"].get("faction", "")):
			continue
		var by := str(ask.get("by_name", "someone"))
		var faction := ResidentCard.faction_name(str(ask["what"].get("faction", "")))
		if str(_call(given, "zone_of", [str(ask.get("by", ""))])) == str(ask["what"].get("area", "")):
			_close(pair[0], ask, "%s cleared the camp of %s." % [by, faction], "%s cleared the camp of %s, as promised." % [by, faction], CAMP, 1, given,
				"met", "cleared the camp of %s" % faction)
		else:
			_close(pair[0], ask, "The camp of %s was cleared, though not by %s." % [faction, by], "The camp of %s is cleared; %s's promise is kept by another." % [faction, by], "", 1, given)


## [param count] of [param what] banked at [param place] by [param by_id]
## (Stockpile.deposited, "player:<id>"): the asks to fetch it count it;
## met at their count.
static func deposited(place: String, _by: String, by_id: String, what: String, count: int, given: Dictionary = ctx) -> void:
	var production: Production = given.get("production")
	if production == null or not by_id.begins_with("player:"):
		return
	var player_id := by_id.trim_prefix("player:")
	for pair: Array in _asks(production, place):
		var ask: Dictionary = pair[1]
		if str(ask.get("sub", "")) != FETCH or str(ask.get("by", "")) != player_id or str(ask.get("what", {}).get("item", "")) != what:
			continue
		var card := Townsfolk.card_of(production, pair[0])
		for held: Dictionary in card.get("asks", []):
			if str(held.get("id", "")) == str(ask.get("id", "")):
				held["what"]["got"] = int(held["what"].get("got", 0)) + count
				ask = held
		production.set_card(pair[0], card)
		var wanted := int(ask["what"].get("count", 0))
		if int(ask["what"].get("got", 0)) >= wanted:
			var by := str(ask.get("by_name", "someone"))
			var item := what.replace("_", " ")
			_close(pair[0], ask, "%s brought %d %s to the store." % [by, wanted, item], "%s brought %d %s to the store, as promised." % [by, wanted, item], FETCH, wanted, given,
				"met", "brought %d %s to the store" % [wanted, item])


## [param player_id] speaks to [param worker_id]: the errands carrying a
## word to them are met: the grudge dropped on both cards, the fact on both.
static func spoke_to(player_id: String, worker_id: String, given: Dictionary = ctx) -> void:
	var production: Production = given.get("production")
	if production == null:
		return
	for pair: Array in _asks(production):
		var ask: Dictionary = pair[1]
		if str(ask.get("kind", "")) != ERRAND or str(ask.get("by", "")) != player_id or str(ask.get("what", {}).get("to", "")) != worker_id:
			continue
		var from_id: String = pair[0]
		var from_name := str(production.worker(from_id).get("name", from_id))
		var to_name := str(production.worker(worker_id).get("name", worker_id))
		var by := str(ask.get("by_name", "someone"))
		var theirs := Townsfolk.card_of(production, worker_id)
		theirs["grudge"] = theirs.get("grudge", []).filter(func(each: Variant) -> bool: return str(each) != from_id)
		production.set_card(worker_id, theirs)
		var mine := Townsfolk.card_of(production, from_id)
		mine["grudge"] = mine.get("grudge", []).filter(func(each: Variant) -> bool: return str(each) != worker_id)
		production.set_card(from_id, mine)
		Townsfolk.learn(production, worker_id, "%s carried %s's word to %s: the matter between them is forgotten." % [by, from_name, to_name])
		_regard(production, worker_id, player_id, Standing.setting("word"), "carried %s's word" % from_name)
		_close(from_id, ask, "%s carried %s's word to %s: the matter between them is forgotten." % [by, from_name, to_name],
			"%s carried %s's word to %s." % [by, from_name, to_name], "", 1, given, "word", "carried a word to %s" % to_name)


## Asks older than "offers.days" lapse, with a fact told once.
static func tick(given: Dictionary = ctx) -> void:
	var production: Production = given.get("production")
	if production == null:
		return
	var limit := int(settings().get("days", 7)) * maxi(DayNight.day_steps, 1)
	var now := production.now()
	for pair: Array in _asks(production):
		var ask: Dictionary = pair[1]
		if now - int(ask.get("step", now)) <= limit:
			continue
		var by := str(ask.get("by_name", "someone"))
		var name := str(production.worker(pair[0]).get("name", pair[0]))
		_close(pair[0], ask, "%s never kept the promise %s: %s." % [by, "to " + name, _promise(ask)], "%s's promise to %s lapsed: %s." % [by, name, _promise(ask)], "", 1, given,
			"errand_lapsed" if str(ask.get("kind", "")) == ERRAND else "lapsed", "let a promise lapse, %s" % _promise(ask))


## Connects the world's signals, once per instance: the objects are held
## weakly by the signals themselves, the closures hold nothing.
static var _watching: Dictionary = {}

static func watch(towns: Towns, holdings: Holdings, stockpile: Stockpile) -> void:
	if towns != null and not _watching.has(towns.get_instance_id()):
		_watching[towns.get_instance_id()] = weakref(towns)
		towns.rescued.connect(func(town: String, who_id: String, _by: String) -> void: rescued(town, who_id))
	if holdings != null and not _watching.has(holdings.get_instance_id()):
		_watching[holdings.get_instance_id()] = weakref(holdings)
		holdings.place_taken.connect(func(id: String, from: String, to: String) -> void: camp_taken(id, from, to))
	if stockpile != null and stockpile.has_signal("deposited") and not _watching.has(stockpile.get_instance_id()):
		_watching[stockpile.get_instance_id()] = weakref(stockpile)
		stockpile.connect("deposited", func(place: String, by: String, by_id: String, what: String, count: int) -> void:
			deposited(place, by, by_id, what, count))


# --- The voice --------------------------------------------------------------------------

## What the voice is told of its offers to [param player_id] (named
## [param player_name]), facts never lines: "" for none.
static func voice_words(worker_id: String, player_id: String, player_name: String, given: Dictionary = ctx) -> String:
	var fresh: Array[String] = []
	var open: Array[String] = []
	for offer: Dictionary in of(worker_id, player_id, given):
		if bool(offer.get("open", false)):
			open.append("%s promised %s and has not yet." % [player_name, _promise(offer_as_ask(offer))])
		else:
			var said := str(offer.get("words", "")).trim_suffix(".")
			fresh.append(said if said.begins_with("I ") else Hearsay._lower_first(said))
	var parts: Array[String] = []
	if not fresh.is_empty():
		parts.append("What you can offer %s, if it comes up: %s." % [player_name, "; ".join(fresh)])
	parts.append_array(open)
	return " ".join(parts)


static func offer_as_ask(offer: Dictionary) -> Dictionary:
	return {"sub": str(offer.get("what", {}).get("sub", "")), "what": offer.get("what", {}), "title": offer.get("title", "")}
