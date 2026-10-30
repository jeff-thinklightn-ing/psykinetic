class_name Offers
## What a town's person can offer when spoken to (decision 435, the data
## side of ui's step 4): from records only, never invented. At most one
## offer per kind and "offers.max" (3) in all, in this order: a shop line
## (a thing in the town's shop that this resident's trade makes, at
## economy's price), one true commission (kin held captive brought home, a
## raiders' camp cleared), a rumour (the newest believed hearsay, 378; an
## official offers the weightiest lore fact it knows instead) and a plea
## (help with a loan, or a word carried to a neighbour the resident holds a
## grudge against).
##
## The rule for commissions (Jeff, 2026-10-18, 435 amended): "try to
## minimize quests that are just 'go get object A from location B'", and
## "if those types of quests exist, make them so they are auto completed,
## no need to talk to the NPC first. Just give player a notice that it was
## completed and the reward, and the NPC will remember they completed it."
## So a commission comes from people and what is between them (kin to
## bring home, a camp to clear, a word to carry, a loan to cover; later a
## dispute for the lawspeaker, sick kin to the healer, someone walked home),
## never a fetch; a thing the town is short of is talk (the voice has it)
## and banking it pays on its own. And no commission needs accepting: the
## event that would complete one completes it whether or not it was taken
## on, with the party-log notice and the pay, and the card remembers;
## "take" only records interest and keeps the ask open on the card.
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
## The words a line to a resident may be (decision 536: talk with no panel):
## an ask for wares, work or news, a yes, a no, or an amount said ("give 25").
## residents.json offers "asks" replaces any list, so Jeff can tune them.
const ASKS := {
	"wares": ["sell", "buy", "wares", "for sale", "have you got", "what do you have", "what have you"],
	"work": ["work", "job", "errand", "need", "help you", "anything i can do", "can i do"],
	"news": ["news", "what's new", "anything new", "heard", "going on", "tell me"],
	"yes": ["yes", "aye", "all right", "alright", "i will", "i'll take it", "i'll do it", "i'll bring", "done", "deal", "take it", "agreed", "very well", "gladly"],
	"no": ["no", "nay", "not now", "no thanks", "never mind", "not today"],
	"amount": ["give", "lend", "pay", "here is", "here's", "take"]}
const DEFAULTS := {"max": 3, "per_player": 3, "days": 7, "fetch": 6, "give_most": 10, "asks": ASKS}
const SHOP := "shop"
const COMMISSION := "commission"
## The priest's crypt commissions (decision 546, npc's side, part 3): sub OFFERING (carry
## the temple's offering down to the altar) and RUNNER (find what became of Pip).
const OFFERING := "offering"
## A knight's remains given back to the priest (decision 714, npc's side): ctx
## "relics" lists the player's; Main lays one on the altar (Main._relic_returned).
const RELIC := "relic"
const RUNNER := "runner"
const RUMOUR := "rumour"
const PLEA := "plea"
## A page read to the player (decision 491: the scholar's chronicle); its
## accept word "read" records nothing: the lines come back as "read".
const PAGE := "page"
const READ := "read"
const BUY := "buy"
## A visitor's body (711, npc's side): "visitor:" + their Towns.visitors id;
## no worker, no card. A pedlar's things are WARES, sold by WARES.
const VISITOR := "visitor:"
const WARES := "wares"
const TAKE := "take"
const LEND := "lend"
const CARRY := "carry"
## A gift of gold toward the town's next build (decision 499, npc's side).
const GIVE := "give"
## What the treasury pays when economy's rules have no line for a key yet
## (economy.json "commissions"; decisions 486 and 487).
const DEFAULT_PAY := {"dispute": 5, "escort": 8, "healing": 6}
const RESCUE := "rescue"
const CAMP := "camp"
const FETCH := "fetch"
## The medicine man's care paid ahead (decision 584 amended, npc's side): accept pays economy's retainer.
const CARE := "care"
## His pleas' subs (all TAKE): the herbs that are his first quest, then the chain it opens.
const CARE_HERBS := "care_herbs"
const CARE_SICK := "care_sick"
const CARE_BREW := "care_brew"
## The brew's makings, brought to him over any number of visits.
const BREW_HERBS := 3
const BREW_ANTLERS := 1
## What he hands back for the brew (items.json; his own make).
const BREW_POTION := "stamina_potion"
## The last count short of its number (584 amended (2)): {"n", "left"} for a
## way in, {"brew": true, "herbs", "antlers"} for the brew; {} when the
## last hand-over counted nothing or met its number. gift reads it.
static var counted := {}
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


## residents.json "sought" (decision 613, npc's side): the sought's set lines by trade (the story's id once
## economy's amendment carries one), "_" the fallback: freed (said when the escort starts) and arrival (at the
## town's store); held and lost are the thought's words (Resident.facts_now).
static var _sought_words: Dictionary = {}
static var _note_words: Dictionary = {}
## The words of a sought's door note and the town's rumour for [param story]
## ("sought.<trade>" / "sought.camp", economy's entry.story; decision 643):
## the words file's "notes" by story over its "default", {note (with the
## where), rumour (name, trade, where)}; lore's lines by story land after
## Jeff's wording check, the defaults carry the mechanism till then.
static func note_words(story: String) -> Dictionary:
	if _note_words.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE)) if FileAccess.file_exists(FILE) else null
		_note_words = data.get("notes", {}).duplicate(true) if data is Dictionary and data.get("notes") is Dictionary else {}
		if not _note_words.get("default") is Dictionary:
			_note_words["default"] = {"note": "Away %s. Back when I can.", "rumour": "%s the %s has gone off, %s they say."}
	var out: Dictionary = (_note_words["default"] as Dictionary).duplicate()
	if _note_words.get(story) is Dictionary:
		out.merge(_note_words[story], true)
	return out


static func sought_words(trade: String) -> Dictionary:
	if _sought_words.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE)) if FileAccess.file_exists(FILE) else null
		_sought_words = data.get("sought", {}).duplicate(true) if data is Dictionary and data.get("sought") is Dictionary else {}
		if not _sought_words.get("default") is Dictionary:
			_sought_words["default"] = {"freed": "Lead on.", "arrival": "I am the %s you sent for."}
	var out: Dictionary = (_sought_words["default"] as Dictionary).duplicate()
	if _sought_words.get(trade) is Dictionary:
		out.merge(_sought_words[trade], true)
	return out


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


## What a player is called where others will hear it: their record's name
## (ctx "name_of"), else TRAVELLER, never their id, which is the key to
## their record.
const TRAVELLER := "a traveller"


static func name_of(given: Dictionary, player_id: String) -> String:
	var name: Variant = _call(given, "name_of", [player_id]) if not player_id.is_empty() else null
	if not name is String or name.is_empty() or name == player_id:
		return TRAVELLER
	return name


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
	if worker_id.begins_with(VISITOR):
		return _visitor_offers(worker_id, given)
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
	for relic: Dictionary in _relic_offers(worker_id, who, card, player_id, given):
		out.append(relic)  # The priest takes a knight home from anyone, wronged or not (714, npc's side).
	var regard := Standing.words(card, player_id)
	var trusted := regard == "trusted"
	var fresh: Array[Dictionary] = []
	if regard != "wronged":
		var shop := _shop_offer(worker_id, who, town, given)
		for crypt: Dictionary in _crypt_offers(worker_id, who, town, player_id, open, given):
			fresh.append(crypt)  # Aldous's, to one who knows the secret (546, npc's side, part 3).
		var job := {}
		if card.get("asks", []).size() < (2 if trusted else 1) and open < (2 if trusted else 1):
			job = _commission_offer(worker_id, who, card, town, given)
		for offer: Dictionary in ([job, shop] if trusted else [shop, job]):
			if not offer.is_empty():
				fresh.append(offer)
		for care: Dictionary in _care_offers(worker_id, who, town, player_id, given):
			fresh.append(care)  # The medicine man's care and the quests behind it, after his counter (584 amended, npc's side).
		var page := _page_offer(worker_id, who, town, given)
		if not page.is_empty():
			fresh.push_front(page)  # The desk is what you came for (decision 491).
		var rumour := _rumour_offer(worker_id, who, given)
		if not rumour.is_empty():
			fresh.append(rumour)
		var gifts := _give_offers(worker_id, who, town, player_id, given)
		for i in gifts.size():
			fresh.insert(i, gifts[i])  # The town's building fund, first at the official's counter (decision 499, npc's side).
	if open == 0:
		var plea := _plea_offer(worker_id, who, card, town, given)
		if not plea.is_empty():
			fresh.append(plea)
	out.append_array(fresh.slice(0, int(settings().get("max", 3))))
	return out


## The town's official (the appointed one, 404) at the store offers gold toward
## the next build (decision 499, npc's side; Jeff: "any amount"): while
## economy's contribution_wanted(town) says gold > 0, one GIVE line at wanted
## when it is within "give_most" (residents.json offers, 10), else two: the
## step and the rest at min(wanted, the player's gold). The title names no
## sum (the panel draws each row's gold beside it; ui, 499 amended) and the
## first line's words say what the build waits on (Towns.shortfall), the
## second's are empty. Nothing while nothing is planned.
static func _give_offers(worker_id: String, who: Dictionary, town: String, player_id: String, given: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if str(who.get("origin", "")) != "appointed" or town.is_empty():
		return out
	var wanted: Variant = _call(given, "contribution_wanted", [town])
	if not wanted is Dictionary or int(wanted.get("gold", 0)) <= 0:
		return out
	var gold := int(wanted["gold"])
	var kind := _build_words(str(wanted.get("kind", "")))
	var lack: Variant = _call(given, "shortfall", [town])
	var needs := _needs_words(lack.get("needs", {}) if lack is Dictionary else {})
	var words := "%s waits on %s%d gold; what you give goes to it." % [kind.capitalize() if not kind.begins_with("the ") else "The " + kind.trim_prefix("the "), needs + " and " if not needs.is_empty() else "", gold]
	var step := int(settings().get("give_most", 10))
	if gold <= step:
		out.append(_offer(worker_id, GIVE, "give:all", "Give toward %s" % kind, words, {"gold": gold, "kind": str(wanted.get("kind", "")), "town": town}, GIVE, gold))
		return out
	out.append(_offer(worker_id, GIVE, "give:step", "Give toward %s" % kind, words, {"gold": step, "kind": str(wanted.get("kind", "")), "town": town}, GIVE, step))
	var purse: Variant = _call(given, "gold_of", [player_id])
	var rest := mini(gold, int(purse)) if purse is int or purse is float else gold
	if rest > step:
		out.append(_offer(worker_id, GIVE, "give:rest", "Give the rest" if rest == gold else "Give what you have", "", {"gold": rest, "kind": str(wanted.get("kind", "")), "town": town}, GIVE, rest))
	return out


## "the inn" for a build kind ("inn", "healers_hut").
static func _build_words(kind: String) -> String:
	if kind.is_empty():
		return "the next building"
	return "the " + kind.replace("_", " ").replace("healers hut", "healer's hut")


## "6 wood and 2 stone" from economy's needs ({item: count}, or a list, or words).
static func _needs_words(needs: Variant) -> String:
	var parts: Array[String] = []
	if needs is Dictionary:
		var keys: Array = needs.keys()
		keys.sort()
		for what: Variant in keys:
			if int(needs[what]) > 0:
				parts.append("%d %s" % [int(needs[what]), Items.name_of(str(what)) if Items.exists(str(what)) else str(what)])
	elif needs is Array:
		for what: Variant in needs:
			parts.append(str(what))
	elif needs is String and not str(needs).is_empty():
		parts.append(str(needs))
	if parts.size() <= 1:
		return "".join(parts)
	return ", ".join(parts.slice(0, parts.size() - 1)) + " and " + parts[parts.size() - 1]


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
## A pedlar's wares (711, npc's side): a line for each thing in their stock
## (ctx "visitor": the Towns.visitors entry of the body's id), at the
## The priest's "Give him the remains of <knight>" (decision 714, npc's
## side), one for each relic [param player_id] holds (ctx "relics":
## [{uid, knight}]); none from anyone else.
static func _relic_offers(worker_id: String, who: Dictionary, card: Dictionary, player_id: String, given: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if "priest" not in who.get("trades", []):
		return out
	var relics: Variant = _call(given, "relics", [player_id])
	for relic: Variant in relics if relics is Array else []:
		var uid := int(relic.get("uid", 0)) if relic is Dictionary else 0
		if uid == 0:
			continue
		var knight := str(relic.get("knight", "the knight"))
		out.append(_offer(worker_id, RELIC, str(uid), "Give %s the remains of %s" % [_them(card), knight],
			"%s's remains, brought up from the barrow, for the altar." % knight, {"uid": uid, "knight": knight}, RELIC))
	return out


## price economy will take (ctx "visitor_price"). A traveller or a pilgrim
## offers nothing.
static func _visitor_offers(worker_id: String, given: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var entry: Variant = _call(given, "visitor", [worker_id])
	if not entry is Dictionary or str(entry.get("kind", "")) != "pedlar":
		return out
	var catalog: Variant = _call(given, "catalog")
	var stock: Dictionary = entry.get("stock", {})
	var items: Array = stock.keys()
	items.sort()
	for item: Variant in items:
		var price: Variant = _call(given, "visitor_price", [str(item)])
		if int(stock[item]) <= 0 or not price is int:
			continue
		var name := str(catalog.get(str(item), {}).get("name", str(item).replace("_", " "))) if catalog is Dictionary else str(item).replace("_", " ")
		out.append(_offer(worker_id, WARES, str(item), "%s, %d gold" % [_upper_first(Companion._a(name)), price],
			"I can let you have %s for %d gold." % [Companion._a(name), price], {"item": str(item), "price": price}, WARES, price))
	return out


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
## The priest's crypt commissions (decision 546, npc's side, part 3), to a
## player Aldous has told the secret (ctx "crypt_asks" (town, player_id) ->
## {offering: the gold at the altar, 0 for none or an untold player; runner:
## the lost runner's name, "" for none}): "Take the offering down" while
## gold waits at the altar, "Find the runner" while Pip is lost below; each
## once (not while the player's own ask of it stands).
static func _crypt_offers(worker_id: String, who: Dictionary, town: String, player_id: String, open: int, given: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if "priest" not in who.get("trades", []):
		return out
	var asks: Variant = _call(given, "crypt_asks", [town, player_id])
	if not asks is Dictionary:
		return out
	var production: Production = given["production"]
	var standing: Array = Townsfolk.card_of(production, worker_id).get("asks", []).filter(func(ask: Dictionary) -> bool: return str(ask.get("by", "")) == player_id)
	var has := func(sub: String) -> bool: return standing.any(func(ask: Dictionary) -> bool: return str(ask.get("sub", "")) == sub)
	var gold := int(asks.get("offering", 0))
	if gold > 0 and not has.call(OFFERING):
		out.append(_offer(worker_id, COMMISSION, OFFERING + ":" + town, "Take the offering down",
			"Carry the temple's offering, %d gold, down to the altar in the barrow and lay it there. Tell no one." % gold,
			{"sub": OFFERING, "gold": gold, "town": town}, TAKE))
	var runner := str(asks.get("runner", ""))
	if not runner.is_empty() and not has.call(RUNNER):
		out.append(_offer(worker_id, COMMISSION, RUNNER + ":" + town, "Find the runner",
			"%s went down with the offering and has not come back. Find what became of him." % runner,
			{"sub": RUNNER, "name": runner, "town": town}, TAKE))
	return out


## A crypt commission met (Main, on reach: the Altar laid, the Runner's pack
## found): closed with its fact, its standing key and, for the offering, the
## gold down (ctx "altar_down"). False if [param player_id] holds no such ask
## of [param town]'s priest.
static func crypt_done(town: String, player_id: String, sub: String, given: Dictionary = ctx) -> bool:
	var production: Production = given.get("production")
	if production == null:
		return false
	for pair: Array in _asks(production):
		var ask: Dictionary = pair[1]
		if str(ask.get("by", "")) != player_id or str(ask.get("sub", "")) != sub or str(ask.get("town", "")) != town:
			continue
		var by := str(ask.get("by_name", "someone"))
		var name := str(production.worker(pair[0]).get("name", pair[0]))
		if sub == OFFERING:
			var gold := int(ask.get("what", {}).get("gold", 0))
			_call(given, "altar_down", [town, gold])
			_close(pair[0], ask, "%s carried the temple's offering down and laid it at the altar." % by,
				"%s laid the offering at the altar, as promised to %s." % [by, name], "", 1, given, OFFERING, "carried the offering down")
		else:
			var runner := str(ask.get("what", {}).get("name", "Pip"))
			_close(pair[0], ask, "%s found %s's pack in the robbers' camp under the mound: he fell to them on his way." % [by, runner],
				"%s found %s's pack in the robbers' camp, and told %s." % [by, runner, name], "", 1, given, RUNNER, "found the runner's pack")
			Townsfolk._remember(town, "%s's pack was found in the robbers' camp under the mound" % runner, pair[0], false, production.now())
		return true
	return false


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
	return {}  # Never a fetch (the rule above): what the town is short of is talk.


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
	if Lore.binding(trade, type) == "official":
		# The word the town sent out (decision 613, npc's side): an official says who is sought and where they were seen, before his lore.
		var sought: Variant = _call(given, "sought_words", [str(who.get("town", ""))])
		if sought is Array and not sought.is_empty():
			return _offer(worker_id, RUMOUR, "sought", "The word the town sent out", str(sought[0]), {"sought": true}, "")
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


## The scholar's chronicle (decision 491): at home (their desk, by the
## routine, 404) a scholar offers to read it; nothing elsewhere, nothing
## from anyone else.
static func _page_offer(worker_id: String, who: Dictionary, town: String, given: Dictionary) -> Dictionary:
	if str(who.get("type", "")) != SCHOLAR or town.is_empty():
		return {}
	var production: Production = given["production"]
	var at := production.now()
	var hour := DayNight.hour(at)
	if is_nan(hour) or is_inf(hour):
		return {}
	if Townsfolk.whereabouts(_trade_of(who), hour, Season.name_at(at), SCHOLAR, worker_id, Townsfolk.day_of(at)) != "home":
		return {}
	var name := str(who.get("name", worker_id))
	return _offer(worker_id, PAGE, "chronicle", "Read the chronicle",
		"%s keeps the town's chronicle here at %s desk, and will read it to you." % [name, _their(who.get("card", {}))], {"page": "chronicle"}, READ)


## "her", "his" or "their" for [param their_card]'s pronoun.
static func _their(their_card: Variant) -> String:
	var pronoun := str(their_card.get("traits", {}).get("pronoun", "")) if their_card is Dictionary else ""
	return {"she": "her", "he": "his"}.get(pronoun, "their")


## The chronicle's lines (TownMemory.chronicle) for [param worker_id]'s
## town, from Main's context: the memory log, the town's name, lore's
## facts, the proposals' statuses ("statuses", 458's page); the newest
## "chronicle.lines" memories, "chronicle.lore" facts when nothing is set
## down (residents.json).
static func chronicle_of(worker_id: String, town: String, given: Dictionary = ctx) -> Array[String]:
	var production: Production = given.get("production")
	if production == null:
		return []
	var log: Variant = _call(given, "memory", [town])
	var town_name := str(_call(given, "town_name", [town]))
	if town_name.is_empty() or town_name == "<null>":
		town_name = town.get_slice("/", 0)
	var who := production.worker(worker_id)
	var keeper := "%s the %s" % [who.get("name", worker_id), _trade_of(who).replace("_", " ")] if not _trade_of(who).is_empty() else str(who.get("name", worker_id))
	var lore: Variant = _call(given, "lore", [town])
	var statuses: Variant = _call(given, "statuses")
	var rule: Dictionary = Townsfolk.days().get("chronicle", {})
	var names: Array = []
	for id: String in production.worker_ids(town):
		names.append(str(production.worker(id).get("name", "")))
	if log is Array:
		for entry: Variant in log:
			if entry is Dictionary and str(entry.get("said_by", "")).begins_with(TownMemory.PLAYER):
				names.append(name_of(given, str(entry["said_by"]).trim_prefix(TownMemory.PLAYER)))
	return TownMemory.chronicle(log if log is Array else [], town_name, keeper, func(id: String) -> String: return str(production.worker(id).get("name", id)),
		lore if lore is Array else [], statuses if statuses is Dictionary else {}, town, int(rule.get("lines", 12)), int(rule.get("lore", 6)), names)


## Help with a loan (economy's pay_loan), else a word to one the resident
## holds a grudge against.
static func _plea_offer(worker_id: String, who: Dictionary, card: Dictionary, town: String, given: Dictionary) -> Dictionary:
	var production: Production = given["production"]
	# Kin sick in bed (decision 501): bring the medicine man, or take them to the healer. First of all.
	var kin: Dictionary = card.get("kin", {})
	var kin_ids: Array = kin.keys()
	kin_ids.sort()
	for kin_id: Variant in kin_ids:
		if production.worker(str(kin_id)).is_empty() or not Townsfolk.is_sick(production, str(kin_id)):
			continue
		var sick := Townsfolk.sickness_of(production, str(kin_id))
		if int(sick.get("treated", -1)) >= 0:
			continue
		var name := str(production.worker(str(kin_id)).get("name", kin_id))
		var theirs := Townsfolk.card_of(production, str(kin_id))
		var healer := str(_call(given, "healer_of", [town]))
		if not healer.is_empty() and healer != "<null>":
			return _offer(worker_id, PLEA, "heal:" + str(kin_id), "Bring the medicine man",
				"My %s %s lies sick with %s; the medicine man is out at his hut. Fetch him to %s." % [_relation(str(kin[kin_id]), theirs), name, sick.get("kind", "a fever"), _them(theirs)],
				{"sick": str(kin_id), "name": name, "healer": healer, "sub": "healing"}, TAKE)
		var hut := str(_call(given, "healers_hut", [town]))
		if not hut.is_empty() and hut != "<null>":
			return _offer(worker_id, PLEA, "heal:" + str(kin_id), "Take %s to the healer" % name,
				"My %s %s lies sick with %s. If you could walk %s to the healer's hut, the healer would see to %s." % [_relation(str(kin[kin_id]), theirs), name, sick.get("kind", "a fever"), _them(theirs), _them(theirs)],
				{"sick": str(kin_id), "name": name, "hut": hut, "sub": "healing"}, TAKE)
	# Kin lost beyond the walls (decision 487): walk them home.
	for kin_id: Variant in kin_ids:
		var theirs := Townsfolk.card_of(production, str(kin_id))
		if theirs.is_empty() or not theirs.get(Townsfolk.STRAYED) is Dictionary or production.worker(str(kin_id)).is_empty():
			continue
		var name := str(production.worker(str(kin_id)).get("name", kin_id))
		return _offer(worker_id, PLEA, "walk:" + str(kin_id), "Walk %s home" % name,
			"My %s %s has not come back from beyond the walls; if you find %s out there, walk %s home." % [_relation(str(kin[kin_id]), theirs), name, _them(theirs), _them(theirs)],
			{"stray": str(kin_id), "name": name, "sub": "escort"}, TAKE)
	var owed := ceili(float(who.get("loan", 0.0)))
	var can_lend: Variant = given.get("pay_loan")
	if owed > 0 and can_lend is Callable and can_lend.is_valid():
		return _offer(worker_id, PLEA, "loan", "Help with a debt", "I owe the town %d gold; could you spare some of it?" % owed,
			{"loan": owed, "town": town}, LEND, owed)
	var law := _law_sitting(town, given)
	for other: Variant in card.get("grudge", []):
		var theirs := production.worker(str(other))
		if theirs.is_empty():
			continue
		var name := str(theirs.get("name", other))
		if not law.is_empty() and law != worker_id and law != str(other):
			# A quarrel for the lawspeaker (decision 486): speak for them when you see him.
			return _offer(worker_id, PLEA, "quarrel:" + str(other), "Speak for me",
				"Lay my quarrel with %s before the lawspeaker when you see %s; say I was wronged." % [name, _them(production.worker(law).get("card", {}))],
				{"other": str(other), "name": name, "law": law}, CARRY)
		return _offer(worker_id, PLEA, "word:" + str(other), "A word for %s" % name,
			"If you see %s, tell %s the matter between us is forgotten." % [name, _them(theirs.get("card", {}))],
			{"to": str(other), "name": name}, CARRY)
	return {}


## The medicine man's care (decision 584 amended, npc's side; Jeff: "5 herbs, 5
## antlers or 10 gold to bypass the quest, but doing his 1st quest can open
## up further quests"): economy holds who is in his care and the way in
## (care_via: gold, antlers, herbs or quest; "" for not in care). Here, to one
## not in care, the retainer paid ahead (CARE; economy's retain); to one whose
## way in was not the herbs, his first quest, the herbs (a TAKE plea, met when
## his card's count for the player reaches return.care.herbs, by gift or by
## economy's window through herbs_taken; antlers likewise through
## antlers_taken, a way in and no quest). The quest done (via herbs or quest)
## opens the chain, one ask at a time: a sick townsman walked to his hut
## (CARE_SICK, met in healed), the brew's makings brought (CARE_BREW, met in
## gift when BREW_HERBS and BREW_ANTLERS are counted; his potion handed back).
static func _care_offers(worker_id: String, who: Dictionary, town: String, player_id: String, given: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var hut := _hut_of(worker_id, given)  # His hut's place (economy's _care_hut_of): the care is the hut's.
	var rule: Variant = _call(given, "care_rule", [hut]) if not hut.is_empty() else null
	if _trade_of(who) != "medicine_man" or not rule is Dictionary or player_id.is_empty():
		return out
	if _call(given, "hut_ruined", [hut]) == true:
		return out  # No care at a ruin: he mends it first (733, npc's side).
	var production: Production = given.get("production")
	var words: Dictionary = settings().get("care", {})
	var via := _via(player_id, hut, given)
	var card := Townsfolk.card_of(production, worker_id)
	var retainer := int(rule.get("retainer", 0))
	if via.is_empty() and retainer > 0:
		out.append(_offer(worker_id, CARE, "care", str(words.get("pay_title", "Pay ahead for his care")),
			str(words.get("pay", "Pay me %d gold now and I'll see to you after: fall where you will and you wake here, in my care.")) % retainer,
			{"gold": retainer, "hut": hut}, CARE, retainer))
	var herbs := int(rule.get("herbs", 0))
	if not _quest_done(via):
		var had := int(_given(player_id, hut, given).get("herbs", 0))
		if herbs > 0 and had < herbs and not _has_ask(card, player_id, CARE_HERBS):
			out.append(_offer(worker_id, PLEA, CARE_HERBS, str(words.get("herbs_title", "Bring him herbs")),
				str(words.get("herbs", "Bring me %d handfuls of herbs and I'll count you in my care, and there is more you could do for me after.")) % (herbs - had),
				{"sub": CARE_HERBS, "hut": hut, "herbs": herbs}, TAKE))
		return out
	# The chain (his first quest done): the sick while someone is sick, else the brew; each once.
	for ask: Dictionary in card.get("asks", []).duplicate():
		if str(ask.get("by", "")) == player_id and str(ask.get("sub", "")) == CARE_HERBS:
			# The herbs came through economy's window (retain, pay herbs) while his plea stood: met all the same.
			var name := str(production.worker(worker_id).get("name", worker_id))
			_close(worker_id, ask, "%s brought the herbs." % str(ask.get("by_name", "They")), str(words.get("kept", "%s is in %s's care now: fall where they will, he will see to them.")) % [str(ask.get("by_name", "They")), name], "", 1, given)
			card = Townsfolk.card_of(production, worker_id)
	var done: Dictionary = card.get("care_done", {}).get(player_id, {})
	if int(rule.get("sick", 0)) > 0 and not done.get("sick", false) and not _has_ask(card, player_id, CARE_SICK) and not _sick_in(production, town).is_empty():
		out.append(_offer(worker_id, PLEA, CARE_SICK, str(words.get("sick_title", "Walk the sick to him")),
			str(words.get("sick", "There is sickness in the town and I cannot be everywhere. Find one who is sick and walk them to my door.")),
			{"sub": CARE_SICK, "hut": hut}, TAKE))
	elif not done.get("brew", false) and not _has_ask(card, player_id, CARE_BREW):
		out.append(_offer(worker_id, PLEA, CARE_BREW, str(words.get("brew_title", "The makings of a brew")),
			str(words.get("brew", "Bring me %d handfuls of herbs and a pair of antlers and I'll brew you something for the road; the potion is yours.")) % BREW_HERBS,
			{"sub": CARE_BREW, "hut": hut, "herbs": BREW_HERBS, "antlers": BREW_ANTLERS}, TAKE))
	return out


## [param player_id]'s way into the care of the hut [param hut] (economy's
## care_via): "" for not in care.
static func _via(player_id: String, hut: String, given: Dictionary) -> String:
	var via: Variant = _call(given, "care_via", [player_id, hut])
	return str(via) if via is String and via != "<null>" else ""


## The tally toward the care of [param hut] (Main.care_given; 584 amended
## (2)): what [param player_id] has handed so far, {} for nothing.
static func _given(player_id: String, hut: String, given: Dictionary) -> Dictionary:
	var tally: Variant = _call(given, "care_given", [player_id, hut])
	return tally if tally is Dictionary else {}


## The medicine man [param worker_id]'s hut (economy's _care_hut_of: his
## town's healer's hut), "" for none.
static func _hut_of(worker_id: String, given: Dictionary) -> String:
	var hut: Variant = _call(given, "care_hut", [worker_id])
	return str(hut) if hut is String and hut != "<null>" else ""


## Whether [param via] says his first quest is done: the herbs, by his plea
## or economy's window (the same act).
static func _quest_done(via: String) -> bool:
	return via in ["herbs", "quest"]


## Whether [param card]'s asks hold an open one by [param player_id] with [param sub].
static func _has_ask(card: Dictionary, player_id: String, sub: String) -> bool:
	for ask: Dictionary in card.get("asks", []):
		if str(ask.get("by", "")) == player_id and str(ask.get("sub", "")) == sub:
			return true
	return false


## The sick of [param town] (its store's id) now, by id; [] with no town.
static func _sick_in(production: Production, town: String) -> Array[String]:
	var out: Array[String] = []
	if town.is_empty() or town == "<null>":
		return out
	for id: String in production.worker_ids(town):
		if Townsfolk.is_sick(production, id):
			out.append(id)
	return out


## [param player_id] is in the medicine man [param worker_id]'s care from now
## by [param how] (economy's grant_care of [param hut]: "quest" for his herbs,
## "antlers" for the pair): his card learns it, the player's standing rises,
## his open herb pleas to them close met.
static func _grant_care(worker_id: String, player_id: String, player_name: String, hut: String, how: String, why: String, given: Dictionary) -> void:
	var production: Production = given.get("production")
	if production == null:
		return
	_call(given, "grant_care", [player_id, hut, how])
	var name := str(production.worker(worker_id).get("name", worker_id))
	Townsfolk.learn(production, worker_id, "%s %s; %s is in %s's care now." % [player_name, why, player_name, name])
	_regard(production, worker_id, player_id, Standing.setting("gave"), why)
	for ask: Dictionary in Townsfolk.card_of(production, worker_id).get("asks", []).duplicate():
		if str(ask.get("by", "")) == player_id and str(ask.get("sub", "")) == CARE_HERBS:
			_close(worker_id, ask, "%s %s." % [player_name, why], str(settings().get("care", {}).get("kept", "%s is in %s's care now: fall where they will, he will see to them.")) % [player_name, name], "", 1, given)


## Herbs into the medicine man [param worker_id]'s hands from [param player_id]
## ([param count] of them, by gift or economy's window), counted on his card:
## toward his first quest while it is not done (care granted at
## return.care.herbs, by "quest"), else toward the brew while that ask is
## open. True when a count was just met.
static func herbs_taken(player_id: String, player_name: String, worker_id: String, count: int, given: Dictionary = ctx) -> bool:
	var production: Production = given.get("production")
	if production == null or player_id.is_empty():
		return false
	var who := production.worker(worker_id)
	if _trade_of(who) != "medicine_man":
		return false
	var hut := _hut_of(worker_id, given)
	var rule: Variant = _call(given, "care_rule", [hut]) if not hut.is_empty() else null
	if not rule is Dictionary:
		return false
	var card := Townsfolk.card_of(production, worker_id)
	if _quest_done(_via(player_id, hut, given)):
		return _brew_taken(worker_id, player_id, player_name, card, hut, "herbs", count, given)
	if int(rule.get("herbs", 0)) <= 0:
		return false
	var total := int(_call(given, "care_give", [player_id, hut, "herbs", count]))  # The record's tally (584 amended (2)).
	if total < int(rule["herbs"]):
		counted = {"n": total, "left": int(rule["herbs"]) - total}
		return false
	_grant_care(worker_id, player_id, player_name, hut, "quest", "brought %d handfuls of herbs" % total, given)
	return true


## A pair of antlers into his hands from [param player_id]: a way into his
## care at return.care.antlers (no quest) while not in care; toward the brew
## once his first quest is done; nothing between.
static func antlers_taken(player_id: String, player_name: String, worker_id: String, count: int, given: Dictionary = ctx) -> bool:
	var production: Production = given.get("production")
	if production == null or player_id.is_empty():
		return false
	var who := production.worker(worker_id)
	if _trade_of(who) != "medicine_man":
		return false
	var hut := _hut_of(worker_id, given)
	var rule: Variant = _call(given, "care_rule", [hut]) if not hut.is_empty() else null
	if not rule is Dictionary:
		return false
	var card := Townsfolk.card_of(production, worker_id)
	var via := _via(player_id, hut, given)
	if _quest_done(via):
		return _brew_taken(worker_id, player_id, player_name, card, hut, "antlers", count, given)
	if not via.is_empty() or int(rule.get("antlers", 0)) <= 0:
		return false
	var total := int(_call(given, "care_give", [player_id, hut, "antlers", count]))  # The record's tally (584 amended (2)).
	if total < int(rule["antlers"]):
		counted = {"n": total, "left": int(rule["antlers"]) - total}
		return false
	_grant_care(worker_id, player_id, player_name, hut, "antlers", "brought %d pairs of antlers" % total, given)
	return true


## [param kind] ("herbs" or "antlers") toward the brew, while the player's
## CARE_BREW ask is open: counted on their record's tally for [param hut]
## (brew_herbs, brew_antlers; 584 amended (2)); at BREW_HERBS and
## BREW_ANTLERS the ask is met, his potion handed to them (main's hand_item),
## the brew marked done and the tally cleared. True when just met.
static func _brew_taken(worker_id: String, player_id: String, player_name: String, card: Dictionary, hut: String, kind: String, count: int, given: Dictionary) -> bool:
	var production: Production = given.get("production")
	var open: Dictionary = {}
	for ask: Dictionary in card.get("asks", []):
		if str(ask.get("by", "")) == player_id and str(ask.get("sub", "")) == CARE_BREW:
			open = ask
	if open.is_empty():
		return false
	_call(given, "care_give", [player_id, hut, "brew_" + kind, count])
	var mine := _given(player_id, hut, given)
	var herbs_now := int(mine.get("brew_herbs", 0))
	var antlers_now := int(mine.get("brew_antlers", 0))
	if herbs_now < BREW_HERBS or antlers_now < BREW_ANTLERS:
		counted = {"brew": true, "herbs": herbs_now, "antlers": antlers_now}
		return false
	_call(given, "care_clear", [player_id, hut, ["brew_herbs", "brew_antlers"]])
	var name := str(production.worker(worker_id).get("name", worker_id))
	var done: Dictionary = card.get("care_done", {})
	var theirs: Dictionary = done.get(player_id, {})
	theirs["brew"] = true
	done[player_id] = theirs
	card["care_done"] = done
	production.set_card(worker_id, card)
	_call(given, "hand_item", [player_id, BREW_POTION, name])
	_close(worker_id, open, "%s brought %s the makings of a brew and took the potion." % [player_name, name],
		str(settings().get("care", {}).get("brew_done", "%s brews what %s brought and hands them the potion.")) % [name, player_name], "", 1, given, "gave", "brought the makings of a brew")
	return true


## [param town]'s sitting lawspeaker's id when there is one and rulings are
## on (Main's "lawspeaker_of" and "model"; off on a server without the
## flag, when quarrels stay as they were); "" otherwise.
static func _law_sitting(town: String, given: Dictionary) -> String:
	var law := str(_call(given, "lawspeaker_of", [town]))
	var model := str(_call(given, "model"))
	if law.is_empty() or law == "<null>" or model.is_empty() or model == "off" or model == "<null>":
		return ""
	var production: Production = given.get("production")
	return law if production != null and not production.worker(law).is_empty() else ""


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
		RELIC:
			out["relic"] = int(offer["what"].get("uid", 0))  # Laid on the altar by Main (_relic_returned), 714.
			out["ok"] = int(out["relic"]) > 0
		WARES:
			out["ware"] = str(offer["what"].get("item", ""))  # Sold by Main (Towns.visitor_sell), 711.
			out["ok"] = not out["ware"].is_empty()
		READ:
			# A page read (decision 491): the lines back to Main, nothing on the card but that they met.
			var card := Townsfolk.card_of(production, worker_id)
			if not card.is_empty() and Standing.met(card, player_id, now):
				production.set_card(worker_id, card)
			out["read"] = chronicle_of(worker_id, str(who.get("town", "")), given)
			out["ok"] = not out["read"].is_empty()
		TAKE:
			if _open_count(production, player_id) >= int(settings().get("per_player", 3)):
				out["line"] = "%s has taken on enough already." % player_name
				return out
			var ask := {"id": offer_id, "kind": COMMISSION, "sub": str(offer["what"].get("sub", "")), "by": player_id, "by_name": player_name,
				"step": now, "town": str(who.get("town", "")), "worker": worker_id, "title": offer["title"], "words": offer["words"],
				"what": offer["what"].duplicate(true)}
			if ask["sub"] == OFFERING:
				# The temple's gold into their purse, to carry down (546, npc's side, part 3; economy's take_altar).
				var took: Variant = _call(given, "take_altar", [str(who.get("town", ""))])
				var carried := int(took) if took is int or took is float else int(offer["what"].get("gold", 0))
				if carried <= 0:
					out["line"] = "There is nothing at the altar to carry."
					return out
				ask["what"]["gold"] = carried
				_call(given, "give_gold", [player_id, carried, "the temple's offering, to carry down"])
			_add_ask(production, worker_id, ask)
			_call(given, "asked", [player_id, ask])
			Townsfolk.learn(production, worker_id, "%s promised %s: %s" % [player_name, name, _promise(ask)])
			out["line"] = "%s takes %s's commission: %s." % [player_name, name, _promise(ask)]
			if ask["sub"] == OFFERING:
				out["line"] = "%s takes the temple's offering, %d gold, to carry down to the altar." % [player_name, int(ask["what"]["gold"])]
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
		GIVE:
			# Gold toward the next build (decision 499, npc's side): economy takes what it still wants and the player has.
			var town := str(who.get("town", ""))
			var asked_gold := gold if gold > 0 else int(offer["what"].get("gold", 0))  # A number said takes that much (decision 536).
			var given_gold := int(_call(given, "contribute", [town, player_id, maxi(asked_gold, 0)]))
			if given_gold > 0:
				var kind := _build_words(str(offer["what"].get("kind", "")))
				Townsfolk.learn(production, worker_id, "%s gave %d gold toward %s." % [player_name, given_gold, kind])
				_regard(production, worker_id, player_id, Standing.setting("gave"), "gave %d gold toward %s" % [given_gold, kind])
				_notice(player_id, town, "gave:" + str(offer["what"].get("kind", "")), "You gave %d gold toward %s." % [given_gold, kind], "", 1, given)
				out["line"] = "%s gives %d gold toward %s." % [player_name, given_gold, kind]
				out["ok"] = true
		CARE:
			# The retainer paid ahead (584 amended, npc's side): economy takes it into his purse, or says why not.
			var took: Variant = _call(given, "retain", [player_id, worker_id, "gold"])
			if took is Dictionary and bool(took.get("ok", false)):
				var paid_gold := int(offer["what"].get("gold", 0))
				Townsfolk.learn(production, worker_id, "%s paid %s %d gold ahead for care; %s is in %s's care now." % [player_name, name, paid_gold, player_name, name])
				_regard(production, worker_id, player_id, Standing.setting("gave"), "paid %d gold ahead for care" % paid_gold)
				out["line"] = "%s pays %s %d gold ahead, and is in his care: fall where they will, he will see to them." % [player_name, name, paid_gold]
				out["ok"] = true
			else:
				var why := str(took.get("why", "")) if took is Dictionary else ""
				out["line"] = why if not why.is_empty() else str(settings().get("care", {}).get("refuse", "Not now."))
		CARRY:
			var quarrel: bool = offer["what"].has("law")  # A quarrel for the lawspeaker (486), else a word carried (435).
			var ask := {"id": offer_id, "kind": ERRAND, "sub": "quarrel" if quarrel else ERRAND, "by": player_id, "by_name": player_name, "step": now,
				"town": str(who.get("town", "")), "worker": worker_id, "title": offer["title"], "words": offer["words"],
				"what": offer["what"].duplicate(true)}
			_add_ask(production, worker_id, ask)
			_call(given, "asked", [player_id, ask])
			if quarrel:
				Townsfolk.learn(production, worker_id, "%s promised to lay %s's quarrel with %s before the lawspeaker." % [player_name, name, offer["what"].get("name", "")])
				out["line"] = "%s will speak for %s before the lawspeaker." % [player_name, name]
			else:
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
		"escort":
			return "to walk %s home" % what.get("name", "")
		"quarrel":
			return "to lay the quarrel with %s before the lawspeaker" % what.get("name", "")
		OFFERING:
			return "to carry the temple's offering, %d gold, down to the altar" % int(what.get("gold", 0))
		RUNNER:
			return "to find what became of %s" % what.get("name", "Pip")
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
	# The medicine man's care and his brew (584 amended, npc's side): herbs and antlers count, one at a time
	# (584 amended (2)): short of his number he says how many more.
	counted = {}
	if item_id == "herbs" and herbs_taken(player_id, player_name, worker_id, 1, given):
		return "%s gives %s %s, and that is herbs enough." % [player_name, who, Companion._a(name)]
	if item_id == "antlers" and antlers_taken(player_id, player_name, worker_id, 1, given):
		return "%s gives %s %s, and that is what he asked." % [player_name, who, Companion._a(name)]
	if not counted.is_empty():
		var words: Dictionary = settings().get("care", {})
		var said := str(words.get("counted_brew", "That's %d of the herbs and %d of the antlers; bring me the rest.")) % [int(counted.get("herbs", 0)), int(counted.get("antlers", 0))] \
				if bool(counted.get("brew", false)) else str(words.get("counted", "That's %d. %d more and you're in my care.")) % [int(counted.get("n", 0)), int(counted.get("left", 0))]
		return "%s gives %s %s. \"%s\"" % [player_name, who, Companion._a(name), said]
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

## Something done for the town with no ask taken (the rule above): the
## treasury's pay to [param player_id] through economy ([param pay_key] times
## [param units]), the party-log notice through Main ("done", an ask-shaped
## record of kind "notice"), and nothing on any card here (the callers move
## standing and facts). The gold paid.
static func _notice(player_id: String, town: String, key: String, line: String, pay_key: String, units := 1, given: Dictionary = ctx) -> int:
	var paid := 0
	var pay: Variant = _call(given, "pay")
	var each := int(pay.get(pay_key, DEFAULT_PAY.get(pay_key, 0))) if pay is Dictionary else int(DEFAULT_PAY.get(pay_key, 0))
	if each * units > 0:
		paid = int(_call(given, "pay_commission", [player_id, town, each * units]))
	var production: Production = given.get("production")
	_call(given, "done", [player_id, {"id": SEP.join(["notice", key, str(production.now() if production != null else 0)]), "kind": "notice",
		"by": player_id, "town": town}, line + (" The town pays %d gold." % paid if paid > 0 else ""), paid])
	return paid


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
		var each := int(pay.get(pay_key, DEFAULT_PAY.get(pay_key, 0))) if pay is Dictionary else int(DEFAULT_PAY.get(pay_key, 0))
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
		var thanked: Array[String] = []
		for id: String in production.worker_ids(town):
			var card: Dictionary = production.worker(id).get("card", {})
			if id in asked or not card.get("kin", {}).has(who_id):
				continue
			thanked.append(str(production.worker(id).get("name", id)))
			for player_id: String in rescuers:
				_regard(production, id, player_id, Standing.setting("kin_home"), "brought %s home" % name)
				Townsfolk.learn(production, id, "%s brought %s home." % [name_of(given, player_id), name])
		if not thanked.is_empty() and asked.is_empty():
			# Done with no ask taken: the notice and the pay, once per rescuer.
			for player_id: String in rescuers:
				_notice(player_id, town, RESCUE + ":" + who_id, "%s is home; %s's thanks." % [name, " and ".join(thanked)], RESCUE, 1, given)
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
	var asked_by := {}  # town -> [player ids] whose ask closes below
	for pair: Array in _asks(production):
		var ask: Dictionary = pair[1]
		if str(ask.get("sub", "")) == CAMP and str(ask.get("what", {}).get("camp", "")) == camp_id:
			asked_by.get_or_add(str(ask.get("town", "")), []).append(str(ask.get("by", "")))
	# Done with no ask taken (the rule above): every town the camp's faction
	# threatened, whose people saw raiders, pays the players standing there.
	if to != _from and not _from.is_empty():
		var camps: Variant = _call(given, "camps")
		var area := _camp_area(camps, camp_id)
		var there: Variant = _call(given, "players_in", [area]) if not area.is_empty() else null
		if there is Array and not there.is_empty():
			var towns := {}
			for id: String in production.worker_ids():
				var town := str(production.worker(id).get("town", ""))
				if not town.is_empty() and not id.begins_with(Townsfolk.COMPANION):
					towns.get_or_add(town, []).append(id)
			var faction := ResidentCard.faction_name(_from)
			for town: String in towns:
				if not bool(_call(given, "hostile", [_from, town])):
					continue
				var saw: Array[String] = []
				for id: String in towns[town]:
					for fact: Variant in production.worker(id).get("card", {}).get("facts", []):
						if fact is Dictionary and str(fact.get("text", "")).containsn("raid"):
							saw.append(id)
							break
				if saw.is_empty():
					continue
				for player_id: Variant in there:
					if str(player_id) in asked_by.get(town, []):
						continue
					for id: String in saw:
						_regard(production, id, str(player_id), Standing.setting("met"), "cleared the camp of %s" % faction)
						Townsfolk.learn(production, id, "%s cleared the camp of %s." % [name_of(given, player_id), faction])
					_notice(str(player_id), town, CAMP + ":" + camp_id, "The camp of %s is cleared; the town's thanks." % faction, CAMP, 1, given)
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
	if production == null or not by_id.begins_with("player:") or count <= 0:
		return
	var player_id := by_id.trim_prefix("player:")
	# What the store was short of, banked by a player: paid then and there
	# (the rule above), the town's people a little the better for it.
	var short: Variant = _call(given, "short", [place])
	var owed_by_ask := false
	for pair: Array in _asks(production, place):
		var held: Dictionary = pair[1]
		if str(held.get("sub", "")) == FETCH and str(held.get("by", "")) == player_id and str(held.get("what", {}).get("item", "")) == what:
			owed_by_ask = true
	if short is Array and what in short and not owed_by_ask:
		var item := what.replace("_", " ")
		var thanks: Array[String] = []
		for id: String in production.worker_ids(place):
			if id.begins_with(Townsfolk.COMPANION):
				continue
			_regard(production, id, player_id, Standing.setting("fetch"), "brought %s the town was short of" % item)
			if thanks.size() < 2:
				thanks.append(str(production.worker(id).get("name", id)))
		_notice(player_id, place, FETCH + ":" + what, "The store was short of %s%s." % [item, "; " + " and ".join(thanks) + "'s thanks" if not thanks.is_empty() else ""], FETCH, count, given)
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
	# A word to the medicine man (decision 501): with a plea to fetch him open,
	# speaking to him sends him to the sick one's bed (Main puts the visit on
	# his day; the visit treats them). Nothing handed in.
	for pair: Array in _asks(production):
		var ask: Dictionary = pair[1]
		if str(ask.get("by", "")) != player_id or str(ask.get("what", {}).get("healer", "")) != worker_id:
			continue
		var sick_id := str(ask["what"].get("sick", ""))
		if Townsfolk.is_sick(production, sick_id) and int(Townsfolk.sickness_of(production, sick_id).get("treated", -1)) < 0:
			if _call(given, "send_healer", [worker_id, sick_id, player_id]) == true:
				Townsfolk.learn(production, worker_id, "%s asked %s to see to %s." % [ask.get("by_name", "someone"), production.worker(worker_id).get("name", worker_id), production.worker(sick_id).get("name", sick_id)])
	# A quarrel laid before the lawspeaker (decision 486): speaking to him with
	# the plea open marks the pair's dispute as brought by this player, so his
	# batch takes it first and his request names them; nothing is handed in.
	for pair: Array in _asks(production):
		var ask: Dictionary = pair[1]
		if str(ask.get("kind", "")) != ERRAND or str(ask.get("by", "")) != player_id or str(ask.get("what", {}).get("law", "")) != worker_id:
			continue
		var town := str(ask.get("town", ""))
		var log: Variant = _call(given, "memory", [town])
		if not log is Array:
			continue
		var from_id: String = pair[0]
		var other := str(ask["what"].get("other", ""))
		Townsfolk.note_disputes(production, town, log, production.now())
		var entry := Townsfolk.dispute_of(log, from_id, other)
		if entry.is_empty() or entry.has("brought"):
			continue
		entry["brought"] = {"by": player_id, "by_name": str(ask.get("by_name", "")), "step": production.now()}
		entry["tier"] = TownMemory.CANDIDATE
		_call(given, "set_memory", [town, log])
		Townsfolk.learn(production, worker_id, "%s laid %s's quarrel with %s before %s." % [ask.get("by_name", "someone"),
			production.worker(from_id).get("name", from_id), production.worker(other).get("name", other), production.worker(worker_id).get("name", worker_id)])
		_regard(production, from_id, player_id, Standing.setting("heard"), "laid their quarrel before the lawspeaker")


## The lawspeaker ruled on [param entry], a dispute with a "pair" (decision
## 486; Lawspeaker.apply): whichever the ruling ([param kind], its
## [param memory] sentence), the quarrel is closed: both cards drop the
## grudge and learn the ruling; every player holding the plea to speak for
## one of them gets the notice, the treasury's "dispute" pay, standing
## "word" from the one they spoke for and one more from the other when the
## ruling reconciled them. Nobody holding it, the matter still closes and
## nobody is paid: the world moved on its own.
static func ruled(town: String, entry: Dictionary, kind: String, memory: String, _step: int, given: Dictionary = ctx) -> void:
	var production: Production = given.get("production")
	if production == null or not entry.get("pair") is Array or entry["pair"].size() != 2:
		return
	var a := str(entry["pair"][0])
	var b := str(entry["pair"][1])
	var a_name := str(production.worker(a).get("name", a))
	var b_name := str(production.worker(b).get("name", b))
	var said := memory.trim_suffix(".") if not memory.is_empty() else "the matter may lie"
	var fact := "The lawspeaker ruled on the quarrel between %s and %s: %s." % [a_name, b_name, said]
	for id: String in [a, b]:
		var card := Townsfolk.card_of(production, id)
		if card.is_empty():
			continue
		var other := b if id == a else a
		card["grudge"] = card.get("grudge", []).filter(func(each: Variant) -> bool: return str(each) != other)
		production.set_card(id, card)
		Townsfolk.learn(production, id, fact)
	for pair: Array in _asks(production, town):
		var ask: Dictionary = pair[1]
		if str(ask.get("kind", "")) != ERRAND or not ask.get("what", {}).has("law"):
			continue
		var mine: String = pair[0]
		var other := str(ask["what"].get("other", ""))
		if not ((mine == a and other == b) or (mine == b and other == a)):
			continue
		var by := str(ask.get("by_name", "someone"))
		var mine_name := str(production.worker(mine).get("name", mine))
		var other_name := str(production.worker(other).get("name", other))
		_close(mine, ask, "%s spoke for %s before the lawspeaker, who ruled: %s." % [by, mine_name, said],
			"The lawspeaker has ruled on %s's quarrel with %s: %s. %s remembers that %s spoke for %s." % [mine_name, other_name, said, mine_name, by, _them(production.worker(mine).get("card", {}))],
			"dispute", 1, given, "word", "spoke for them before the lawspeaker")
		if kind == "reconcile":
			_regard(production, other, str(ask.get("by", "")), 1, "brought the quarrel with %s to a reconciling" % mine_name)


## The sick [param who_id] of [param town] was seen to (decision 501;
## Townsfolk.treat) by [param player_id] ([param player_name], [param how]:
## "the medicine man", "the healer", "a remedy"), or the sickness ended on
## its own ("recovered") or in death ("died"), with no player: every plea
## to see to them is met: the player who brought the cure gets the notice,
## the treasury's "healing" pay and standing "healed" from the kin who
## asked and from the sick one; a cure by another's hand or the medicine
## man's own rounds closes a plea with the notice and no pay; recovered or
## died, with the fact and no lapse against anyone (illness is nobody's
## promise broken).
static func healed(town: String, who_id: String, player_id: String, player_name: String, how: String, given: Dictionary = ctx) -> void:
	var production: Production = given.get("production")
	if production == null:
		return
	var who_name := str(production.worker(who_id).get("name", who_id))
	var their := Townsfolk._their(Townsfolk.card_of(production, who_id))
	var by_name := name_of(given, player_id)
	if by_name == TRAVELLER and not player_name.is_empty():
		by_name = player_name
	var paid_this := false
	for pair: Array in _asks(production, town):
		var ask: Dictionary = pair[1]
		if str(ask.get("what", {}).get("sick", "")) != who_id:
			continue
		var kin_id: String = pair[0]
		if how == "died":
			_close(kin_id, ask, "%s died of the sickness before anyone saw to %s." % [who_name, _them(Townsfolk.card_of(production, who_id))],
				"%s died of the sickness." % who_name, "", 1, given)
		elif how == "recovered":
			_close(kin_id, ask, "%s got over the sickness on %s own." % [who_name, their], "%s is on %s feet again on %s own." % [who_name, their, their], "", 1, given)
		elif not player_id.is_empty() and str(ask.get("by", "")) == player_id:
			paid_this = true
			_close(kin_id, ask, "%s brought %s to %s, and %s mended." % [by_name, how, who_name, who_name],
				"%s saw to %s with %s. %s remembers it." % [by_name, who_name, how, production.worker(kin_id).get("name", kin_id)],
				"healing", 1, given, "healed", "saw to %s" % who_name)
		else:
			_close(kin_id, ask, "%s was seen to by %s." % [who_name, player_name if not player_name.is_empty() else how],
				"%s was seen to by %s before %s could help." % [who_name, player_name if not player_name.is_empty() else how, ask.get("by_name", "you")], "", 1, given)
	if player_id.is_empty() or how in ["died", "recovered"]:
		return
	_regard(production, who_id, player_id, Standing.setting("healed"), "saw to them when they were sick")
	# Walked to the hut and treated there (501's escort): the medicine man's CARE_SICK ask met (584 amended, npc's side).
	if how == "the healer":
		var healer := str(_call(given, "healer_of", [town]))
		if healer.is_empty() or healer == "<null>":
			return
		var card := Townsfolk.card_of(production, healer)
		for ask: Dictionary in card.get("asks", []).duplicate():
			if str(ask.get("by", "")) != player_id or str(ask.get("sub", "")) != CARE_SICK:
				continue
			var done: Dictionary = card.get("care_done", {})
			var theirs: Dictionary = done.get(player_id, {})
			theirs["sick"] = true
			done[player_id] = theirs
			card["care_done"] = done
			production.set_card(healer, card)
			var healer_name := str(production.worker(healer).get("name", healer))
			_close(healer, ask, "%s walked %s to %s's door, sick." % [by_name, who_name, healer_name],
				str(settings().get("care", {}).get("sick_done", "%s walked %s to %s, who saw to them.")) % [by_name, who_name, healer_name], "", 1, given, "healed", "walked %s to the hut" % who_name)
			break
	if not paid_this:
		_notice(player_id, town, "healing:" + who_id, "%s saw to %s with %s." % [by_name, who_name, how], "healing", 1, given)


## The lost [param who_id] of [param town] is home (decision 487; Main on
## the body reaching the town's ground, or Townsfolk.came_home on their
## own): every plea to walk them home is met: by [param player_id] (named
## [param player_name]), who gets the notice, the treasury's "escort" pay
## and standing "walked_home" from the kin who asked and from the one
## walked home (a player who never took the plea is paid the same: the
## arrival is the event); by nobody ("") when they found their own way,
## with the fact and no pay. The cards remember.
static func walked_home(town: String, who_id: String, player_id: String, player_name: String, given: Dictionary = ctx) -> void:
	var production: Production = given.get("production")
	if production == null:
		return
	var who_name := str(production.worker(who_id).get("name", who_id))
	var their := Townsfolk._their(Townsfolk.card_of(production, who_id))
	var paid_this := false
	for pair: Array in _asks(production, town):
		var ask: Dictionary = pair[1]
		if str(ask.get("what", {}).get("stray", "")) != who_id:
			continue
		var kin_id: String = pair[0]
		if player_id.is_empty():
			_close(kin_id, ask, "%s found %s own way home; nobody walked %s." % [who_name, their, _them(Townsfolk.card_of(production, who_id))],
				"%s came home on %s own." % [who_name, their], "", 1, given)
		elif str(ask.get("by", "")) == player_id:
			paid_this = true
			_close(kin_id, ask, "%s walked %s home from beyond the walls." % [player_name, who_name],
				"%s walked %s home. %s remembers it." % [player_name, who_name, production.worker(kin_id).get("name", kin_id)],
				"escort", 1, given, "walked_home", "walked %s home" % who_name)
		else:
			_close(kin_id, ask, "%s walked %s home from beyond the walls." % [player_name, who_name],
				"%s walked %s home before %s could." % [player_name, who_name, ask.get("by_name", "you")], "", 1, given)
	if player_id.is_empty():
		return
	_regard(production, who_id, player_id, Standing.setting("walked_home"), "walked them home")
	if not paid_this:
		_notice(player_id, town, "escort:" + who_id, "%s walked %s home to the town." % [player_name, who_name], "escort", 1, given)


## Asks older than "offers.days" lapse, with a fact told once.
static func tick(given: Dictionary = ctx) -> void:
	var production: Production = given.get("production")
	if production == null:
		return
	var limit := int(settings().get("days", 7)) * maxi(DayNight.day_steps, 1)
	# A quarrel waits for the lawspeaker's pace (486): a batch and his rest.
	var law_limit := maxi(limit, Lawspeaker.setting("every") + Lawspeaker.setting("rest_days") * maxi(DayNight.day_steps, 1))
	var now := production.now()
	for pair: Array in _asks(production):
		var ask: Dictionary = pair[1]
		if now - int(ask.get("step", now)) <= (law_limit if ask.get("what", {}).has("law") else limit):
			continue
		var by := str(ask.get("by_name", "someone"))
		var name := str(production.worker(pair[0]).get("name", pair[0]))
		if str(ask.get("sub", "")) == OFFERING:
			# The temple's gold kept (546, npc's side, part 3): the "cheated" standing key, Jeff's list.
			_close(pair[0], ask, "%s took the temple's offering to carry down and kept it: %d gold." % [by, int(ask.get("what", {}).get("gold", 0))],
				"%s kept the temple's offering; %s knows it." % [by, name], "", 1, given, "cheated", "kept the temple's offering")
			continue
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



# --- Talk with no panel (decision 536) ------------------------------------------------

## What [param line], said to a resident, asks for: "wares", "work", "news",
## "yes", "no" (a short line beginning with such a word), or "" for a line of
## its own, which the mind answers. By the "asks" word lists.
static func ask_kind(line: String) -> String:
	var said := _plain(line)
	if said.is_empty():
		return ""
	var asks: Dictionary = settings().get("asks", ASKS)
	var words := said.split(" ", false)
	if words.size() <= 4:
		for kind: String in ["yes", "no"]:
			for word: Variant in asks.get(kind, []):
				if said == str(word) or said.begins_with(str(word) + " "):
					return kind
	for kind: String in ["wares", "work", "news"]:
		for word: Variant in asks.get(kind, []):
			if _has_word(said, str(word)):
				return kind
	return ""


## The amount [param line] says ("give 25", "lend 5", "here is 10", or a bare
## number), 0 for none.
static func amount_said(line: String) -> int:
	var said := _plain(line)
	if said.is_valid_int():
		return maxi(int(said), 0)
	var asks: Dictionary = settings().get("asks", ASKS)
	for word: Variant in asks.get("amount", []):
		var found := RegEx.create_from_string("(?:^|[^a-z])%s (\\d+)" % _escape(str(word))).search(said)
		if found != null:
			return maxi(int(found.get_string(1)), 0)
	return 0


## The offer [param worker_id] speaks to [param player_id] for [param ask]
## ("wares": the shop line; "work": a commission, a plea, the building fund,
## the scholar's page; "news": the rumour, the page): the first fresh one of
## those kinds, or the one after [param after_id] when that is among them
## (asked again, the next, round and round). {} for none.
static func to_speak(worker_id: String, player_id: String, ask: String, after_id := "", given: Dictionary = ctx) -> Dictionary:
	var kinds: Array[String] = []
	match ask:
		"wares":
			kinds = [SHOP]
		"work":
			kinds = [COMMISSION, PLEA, GIVE, PAGE]
		"news":
			kinds = [RUMOUR, PAGE]
	if kinds.is_empty():
		return {}
	var fresh: Array[Dictionary] = []
	for offer: Dictionary in of(worker_id, player_id, given):
		if not bool(offer.get("open", false)) and str(offer.get("kind", "")) in kinds:
			fresh.append(offer)
	if fresh.is_empty():
		return {}
	for i in fresh.size():
		if str(fresh[i].get("id", "")) == after_id:
			return fresh[(i + 1) % fresh.size()]
	return fresh[0]


## The fresh offer of [param worker_id] that [param line] names: the shop
## thing's name, the person of a commission or plea, "the rest" / "what I
## have" for the building fund's second line, "debt" or "loan", "page" or
## "chronicle". The first that matches; {} for none.
static func named(worker_id: String, player_id: String, line: String, given: Dictionary = ctx) -> Dictionary:
	var said := _plain(line)
	if said.is_empty():
		return {}
	for offer: Dictionary in of(worker_id, player_id, given):
		if bool(offer.get("open", false)):
			continue
		for name: String in names_of(offer):
			if _has_word(said, name):
				return offer
	return {}


## The words that name [param offer] when said back, lower-cased.
static func names_of(offer: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var what: Dictionary = offer.get("what", {})
	var key := str(offer.get("id", "")).get_slice(SEP, 2)
	match str(offer.get("kind", "")):
		SHOP:
			var id := str(what.get("id", ""))
			if not id.is_empty():
				out.append(id.replace("_", " ").to_lower())
				if Items.exists(id):
					out.append(Items.name_of(id).to_lower())
		COMMISSION, PLEA:
			if not str(what.get("name", "")).is_empty():
				out.append(str(what["name"]).to_lower())
			if what.has("loan"):
				out.append_array(["debt", "loan"])
		GIVE:
			if key == "give:rest":
				out.append_array(["the rest", "what i have", "the whole", "all of it"])
		PAGE:
			out.append_array(["page", "chronicle", "book"])
	return out


## Why [param amount] gold cannot go to [param offer] from a purse of
## [param purse]: over the purse ("You have but 9 gold."), over what the
## fund still wants (ctx contribution_wanted) or the debt owed; "" when it
## can.
static func amount_refusal(offer: Dictionary, amount: int, purse: int, given: Dictionary = ctx) -> String:
	if amount <= 0:
		return ""
	if amount > purse:
		return "You have but %d gold." % purse
	var what: Dictionary = offer.get("what", {})
	match str(offer.get("kind", "")):
		GIVE:
			var wanted: Variant = _call(given, "contribution_wanted", [str(what.get("town", ""))])
			var cap := int(wanted.get("gold", 0)) if wanted is Dictionary else int(what.get("gold", 0))
			if amount > cap:
				return "%s wants but %d gold more." % [_upper_first(_build_words(str(what.get("kind", "")))), cap]
		PLEA:
			if what.has("loan") and amount > int(what["loan"]):
				return "I owe but %d." % int(what["loan"])
	return ""


## [param line] lower-cased, its punctuation gone, one space between words.
static func _plain(line: String) -> String:
	var said := line.to_lower().strip_edges()
	said = RegEx.create_from_string("[^a-z0-9' ]+").sub(said, " ", true)
	return RegEx.create_from_string(" +").sub(said, " ", true).strip_edges()


static func _has_word(said: String, word: String) -> bool:
	if word.is_empty():
		return false
	return RegEx.create_from_string("(?:^|[^a-z0-9])%s(?:$|[^a-z0-9])" % _escape(word)).search(said) != null


static func _escape(word: String) -> String:
	var out := ""
	for ch: String in word:
		out += ("\\" + ch) if ch in ".^$*+?()[]{}|\\" else ch
	return out


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
	# One in the medicine man's care (584 amended, npc's side): his voice knows it, and whether they earned it.
	var production: Production = given.get("production")
	if production != null and _trade_of(production.worker(worker_id)) == "medicine_man":
		var via := _via(player_id, _hut_of(worker_id, given), given)
		if not via.is_empty():
			parts.append(str(settings().get("care", {}).get("voice", "%s is in your care: if they fall anywhere, they wake at your hut and you see to them. Say so when it fits, briefly.")) % player_name)
			if _quest_done(via):
				parts.append(str(settings().get("care", {}).get("voice_quest", "%s gathered your herbs, and you trust them with more.")) % player_name)
	return " ".join(parts)


static func offer_as_ask(offer: Dictionary) -> Dictionary:
	return {"sub": str(offer.get("what", {}).get("sub", "")), "what": offer.get("what", {}), "title": offer.get("title", "")}


## Whether [param offer] is a deal already paid for (548 amended: the
## draugr's "again" for one who paid): kind "deal", cost 0, no steps of
## gold; taken with none, by a bare yes as well as a button.
static func free_deal(offer: Dictionary) -> bool:
	return str(offer.get("kind", "")) == "deal" and offer.has("cost") and int(offer["cost"]) == 0 and (offer.get("what", {}).get("steps", []) as Array).is_empty()
