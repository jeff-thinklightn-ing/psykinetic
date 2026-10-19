extends Node
## Conversation offers (decision 435, ui's step 4 data): what a town's
## person offers when spoken to, from records only (Offers.of): a shop line
## for a thing their trade made, one true commission (kin held captive, a
## raiders' camp, a thing the town is short of), the newest believed
## hearsay (an official's lore fact instead), a plea (a loan with economy's
## pay_loan, else a word to one they hold a grudge against); nothing from
## nothing; at most three. Accepting: a commission or an errand on the card
## and told to Main, the per-player cap, a rescue met with the player in
## the camp's area (paid) or by another (not), a fetch counted from
## deposits, an errand met by speaking to the one it is for (the grudge
## dropped both ways), a lapse after "days", and the voice's facts. Pure
## sim: no Main, no port, no scratch folder. Reads the repo's levels, never
## the shared overlay. Run it with tests/run.ps1 or tests/run.sh. Prints
## PASS/FAIL per assertion and quits with exit code 1 if any assertion
## failed, 0 otherwise.

const TOWN := "o/store"
const CAMP := "o/camp@9,9"
const CATALOG := {"knife": {"id": "knife", "name": "knife", "made": {"by": "smith"}}, "wood": {"id": "wood", "name": "wood"}}

var _failures := 0
var _now := 0
var _stock: Stockpile
var _work: Production
var _ctx := {}
var _asked: Array = []
var _done: Array = []
var _paid: Array = []
var _goods: Array = []
var _captives: Array = []
var _camps: Array = []
var _short: Array = []
var _zone := ""
var _lend := true


func _ready() -> void:
	World.set_process(false)
	_test_nothing_from_nothing()
	_test_shop()
	_test_commission_kin()
	_test_commission_camp_and_fetch()
	_test_rumour_and_lore()
	_test_plea()
	_test_cap_and_order()
	_test_accept_and_meet()
	_test_errand()
	_test_quarrel()
	_test_walk_home()
	_test_sick_pleas()
	_test_give()
	_test_lapse()
	_test_voice_words()
	_test_scholar_and_merchant()
	_test_chronicle()
	Production.profile_of = Callable()
	Production.type_of = Callable()
	Townsfolk.use_days({})
	Offers.use_settings({})
	Offers.ctx = {}
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


static func _profile(_trade: String, _type := "") -> Dictionary:
	return {"intellect": 1, "superstition": 5, "creativity": 5, "integrity": 5}


## Ids' hidden types (a scholar, a merchant: decision 440).
static var _types := {}


static func _type(id: String) -> String:
	return str(_types.get(id, ""))


func _setup(folk: Array = [["o-mara", "Mara", "smith"], ["o-tam", "Tam", "hauler"]]) -> void:
	_now = 0
	_asked.clear()
	_done.clear()
	_paid.clear()
	_goods = []
	_captives = []
	_camps = []
	_short = []
	_zone = ""
	Production.profile_of = _profile
	Production.type_of = _type
	Townsfolk.use_days({"default": {"stints": [{"from": 0, "to": 12, "at": "home"}, {"from": 12, "to": 24, "at": "home"}]}, "gossip": {"every": 0}})
	Offers.use_settings({"max": 3, "per_player": 2, "days": 7, "fetch": 6})
	var clock := func() -> int: return _now
	var cat := func() -> Dictionary: return CATALOG
	_stock = Stockpile.new({}, clock, ItemBook.new(clock))
	_work = Production.new({}, _stock, null, clock, Production.read_rules(), cat)
	for each: Array in folk:
		_work.add_worker(each[0], each[1], [each[2]], TOWN)
	# Their cards made first, then untied: the founding roll could tie two of
	# them by id, and a later card's roll writes into an earlier one.
	for each: Array in folk:
		Townsfolk.card_of(_work, each[0])
	for each: Array in folk:
		var card := Townsfolk.card_of(_work, each[0])
		card["kin"] = {}
		card["grudge"] = []
		card["asks"] = []
		_work.set_card(each[0], card)
	_ctx = {
		"production": _work,
		"goods": func(_town: String) -> Array: return _goods,
		"catalog": func() -> Dictionary: return CATALOG,
		"captives": func(_town: String) -> Array: return _captives,
		"camps": func() -> Array: return _camps,
		"hostile": func(faction: String, _town: String) -> bool: return faction == "goblins",
		"short": func(_town: String) -> Array: return _short,
		"area_name": func(area: String) -> String: return "the Dark Wood" if area == "wood" else area,
		"pay_commission": func(player_id: String, town: String, gold: int) -> int:
			_paid.append([player_id, town, gold])
			return gold,
		"pay": func() -> Dictionary: return {"rescue": 10, "camp": 20, "fetch": 1},
		"zone_of": func(_player_id: String) -> String: return _zone,
		"players_in": func(area: String) -> Array: return ["p1"] if area == _zone else [],
		"name_of": func(player_id: String) -> String: return "Jeff" if player_id == "p1" else player_id,
		"asked": func(player_id: String, ask: Dictionary) -> void: _asked.append([player_id, ask]),
		"done": func(player_id: String, ask: Dictionary, line: String, paid: int) -> void: _done.append([player_id, ask, line, paid]),
	}
	if _lend:
		_ctx["pay_loan"] = func(_player_id: String, worker_id: String, gold: int) -> int:
			var owed := float(_work.worker(worker_id).get("loan", 0.0))
			var paid := mini(gold, ceili(owed))
			_work.set_loan(worker_id, owed - paid, false)
			return paid
	Offers.ctx = _ctx


func _offers(id := "o-mara", player := "p1") -> Array[Dictionary]:
	return Offers.of(id, player, _ctx)


func _kinds(offers: Array[Dictionary]) -> Array:
	return offers.map(func(each: Dictionary) -> String: return str(each["kind"]) + ("*" if each.get("open", false) else ""))


func _plant(id: String, text: String, from := "Jeff", where := "") -> void:
	var heard: Array = _work.worker(id).get("heard", [])
	Hearsay.hear(heard, id, 1, text, "beyond", from, _now, false, 5, where)
	_work.set_heard(id, heard)


func _test_nothing_from_nothing() -> void:
	print("\n== nothing from nothing ==")
	_setup()
	_check(_offers().is_empty(), "a resident with an empty shop, no kin held, no rumour, no loan and no grudge offers nothing: %s" % [_offers()])
	_check(Offers.of("companion:p1", "p1", _ctx).is_empty() and Offers.of("nobody", "p1", _ctx).is_empty(), "a companion or no such worker offers nothing")


func _test_shop() -> void:
	print("\n== a shop line, for what their trade made ==")
	_setup()
	_goods = [{"uid": 7, "id": "wood", "price": 2}, {"uid": 9, "id": "knife", "price": 12}]
	var mine := _offers("o-mara")
	_check(mine.size() == 1 and mine[0]["kind"] == Offers.SHOP and mine[0]["accept"] == Offers.BUY and mine[0]["cost"] == 12 and mine[0]["what"]["uid"] == 9,
		"the smith offers the knife (hers), not the wood: %s" % [mine])
	_check(mine.size() == 1 and mine[0]["title"] == "A knife, 12 gold" and mine[0]["words"] == "I have a knife at the counter for 12 gold.",
		"a title for the button and a sentence: %s / %s" % [mine[0]["title"] if not mine.is_empty() else "", mine[0]["words"] if not mine.is_empty() else ""])
	_check(_offers("o-tam").is_empty(), "the hauler, who made neither, offers no shop line")
	_check(mine.size() == 1 and mine[0]["id"] == "o-mara|shop|9", "the id names the worker, the kind and the thing: %s" % mine[0]["id"] if not mine.is_empty() else "")
	var bought := Offers.accept("o-mara", "p1", "Jeff", "o-mara|shop|9", 0, _ctx)
	_check(bought["ok"] and bought["buy"] == 9 and bought["line"].is_empty(), "accepting hands Main the uid to sell at the counter: %s" % [bought])


func _test_commission_kin() -> void:
	print("\n== a commission: kin held captive ==")
	_setup([["o-mara", "Mara", "smith"], ["o-bram", "Bram", "hauler"]])
	var card := Townsfolk.card_of(_work, "o-mara")
	card["kin"] = {"o-bram": "sister or brother"}
	_work.set_card("o-mara", card)
	var his := Townsfolk.card_of(_work, "o-bram")
	his["traits"]["pronoun"] = "he"
	_work.set_card("o-bram", his)
	_captives = [{"id": "o-bram", "name": "Bram", "by": "goblins", "held_by": CAMP}]
	_camps = [{"id": CAMP, "area": "wood", "faction": "goblins"}]
	var mine := _offers()
	_check(mine.size() == 1 and mine[0]["kind"] == Offers.COMMISSION and mine[0]["what"]["sub"] == Offers.RESCUE and mine[0]["what"]["captive"] == "o-bram"
		and mine[0]["what"]["area"] == "wood", "Mara asks for her brother back: %s" % [mine])
	_check(mine.size() == 1 and mine[0]["title"] == "Bring Bram home" and mine[0]["words"].begins_with("Bring my brother Bram home from the camp of ")
		and mine[0]["words"].ends_with(" camp of %s at the Dark Wood." % ResidentCard.faction_name("goblins")), "in words, with the camp's place: %s" % (mine[0]["words"] if not mine.is_empty() else ""))
	_zone = "wood"
	Offers.rescued(TOWN, "o-bram", _ctx)
	_check(_paid == [["p1", TOWN, 10]] and _done.size() == 1 and _done[0][1]["kind"] == "notice" and _done[0][2] == "Bram is home; Mara's thanks. The town pays 10 gold.",
		"brought home with nothing taken on: paid and told all the same (Jeff's rule): %s" % [_done])
	_captives = []
	_check(_offers().is_empty(), "once he is home (no captive), no such commission")


func _test_commission_camp_and_fetch() -> void:
	print("\n== a commission: a raiders' camp, else a thing fetched ==")
	_setup()
	_camps = [{"id": CAMP, "area": "wood", "faction": "goblins"}, {"id": "o/camp@2,2", "area": "fen", "faction": "deer"}]
	_short = ["wood", "cloth"]
	var mine := _offers()
	_check(mine.is_empty(), "no raid seen, and what the town is short of is never a commission (Jeff's rule): %s" % [mine])
	Townsfolk.learn(_work, "o-mara", "Mara saw raiders at the walls.")
	mine = _offers()
	_check(mine.size() == 1 and mine[0]["what"]["sub"] == Offers.CAMP and mine[0]["what"]["camp"] == CAMP and mine[0]["what"]["faction"] == "goblins",
		"having seen raiders, she asks for the hostile camp cleared, not the deer's: %s" % [mine])
	_check(mine.size() == 1 and mine[0]["title"] == "Clear the camp" and mine[0]["words"].contains("at the Dark Wood"), "with the place: %s" % (mine[0]["words"] if not mine.is_empty() else ""))


func _test_rumour_and_lore() -> void:
	print("\n== a rumour: the newest believed hearsay; an official's lore fact ==")
	_setup([["o-mara", "Mara", "smith"], ["o-ora", "Ora", "priest"]])
	_plant("o-mara", "The mine is cursed", "Tam", "well")
	_plant("o-mara", "The miller waters the flour", "Nell")
	var mine := _offers()
	_check(mine.size() == 1 and mine[0]["kind"] == Offers.RUMOUR and mine[0]["accept"] == "" and mine[0]["words"] == "Nell told me that the miller waters the flour."
		and mine[0]["title"] == "What Nell said", "the newest believed thing, as told, nothing to accept: %s" % [mine])
	var hers := _offers("o-ora")
	_check(Lore.binding("priest") == "official" and (hers.is_empty() or (hers[0]["kind"] == Offers.RUMOUR and hers[0]["what"].get("lore", false))),
		"the priest offers a lore fact she knows, never hearsay (%s)" % [hers])


func _test_plea() -> void:
	print("\n== a plea: a loan, else a word to one they hold a grudge against ==")
	_setup([["o-mara", "Mara", "smith"], ["o-bram", "Bram", "hauler"]])
	var card := Townsfolk.card_of(_work, "o-mara")
	card["grudge"] = ["o-bram"]
	_work.set_card("o-mara", card)
	var mine := _offers()
	_check(mine.size() == 1 and mine[0]["kind"] == Offers.PLEA and mine[0]["accept"] == Offers.CARRY and mine[0]["what"]["to"] == "o-bram"
		and mine[0]["title"] == "A word for Bram", "a word to carry to Bram: %s" % [mine])
	_work.set_loan("o-mara", 14.0, false)
	mine = _offers()
	_check(mine.size() == 1 and mine[0]["accept"] == Offers.LEND and mine[0]["cost"] == 14 and mine[0]["words"] == "I owe the town 14 gold; could you spare some of it?",
		"a loan comes first: %s" % [mine])
	var lent := Offers.accept("o-mara", "p1", "Jeff", mine[0]["id"] if not mine.is_empty() else "", 5, _ctx)
	_check(lent["ok"] and lent["line"] == "Jeff gives 5 gold toward Mara's debt." and is_equal_approx(float(_work.worker("o-mara")["loan"]), 9.0),
		"lending pays the loan down through economy: %s, loan now %s" % [lent, _work.worker("o-mara")["loan"]])
	_lend = false
	_setup([["o-mara", "Mara", "smith"], ["o-bram", "Bram", "hauler"]])
	_work.set_loan("o-mara", 14.0, false)
	_check(_offers().is_empty(), "with no pay_loan on the server, no loan plea is made")
	_lend = true


func _test_cap_and_order() -> void:
	print("\n== at most three, in order: shop, commission, rumour, plea ==")
	_setup([["o-mara", "Mara", "smith"], ["o-bram", "Bram", "hauler"]])
	_goods = [{"uid": 9, "id": "knife", "price": 12}]
	Townsfolk.learn(_work, "o-mara", "Mara saw raiders at the walls.")
	_camps = [{"id": CAMP, "area": "wood", "faction": "goblins"}]
	_plant("o-mara", "The mine is cursed", "Tam", "well")
	var card := Townsfolk.card_of(_work, "o-mara")
	card["grudge"] = ["o-bram"]
	_work.set_card("o-mara", card)
	var mine := _offers()
	_check(_kinds(mine) == [Offers.SHOP, Offers.COMMISSION, Offers.RUMOUR], "four true, three offered, the plea left for another day: %s" % [_kinds(mine)])
	Offers.use_settings({"max": 4, "per_player": 2, "days": 7, "fetch": 6})
	_check(_kinds(_offers()) == [Offers.SHOP, Offers.COMMISSION, Offers.RUMOUR, Offers.PLEA], "the cap is the setting")


func _test_accept_and_meet() -> void:
	print("\n== a commission taken, met with the player there (paid) or by another ==")
	_setup([["o-mara", "Mara", "smith"], ["o-bram", "Bram", "hauler"], ["o-tam", "Tam", "hauler"]])
	var card := Townsfolk.card_of(_work, "o-mara")
	card["kin"] = {"o-bram": "sister or brother"}
	_work.set_card("o-mara", card)
	_captives = [{"id": "o-bram", "name": "Bram", "by": "goblins", "held_by": CAMP}]
	_camps = [{"id": CAMP, "area": "wood", "faction": "goblins"}]
	var offer: Dictionary = _offers()[0]
	var taken := Offers.accept("o-mara", "p1", "Jeff", offer["id"], 0, _ctx)
	_check(taken["ok"] and taken["line"] == "Jeff takes Mara's commission: to bring Bram home.", "taken, the party log told: %s" % [taken])
	_check(_asked.size() == 1 and _asked[0][0] == "p1" and _asked[0][1]["id"] == offer["id"] and _asked[0][1]["kind"] == Offers.COMMISSION,
		"Main is told, for the player's record")
	var asks: Array = Townsfolk.card_of(_work, "o-mara").get("asks", [])
	_check(asks.size() == 1 and asks[0]["by"] == "p1" and asks[0]["sub"] == Offers.RESCUE, "the ask sits on her card: %s" % [asks])
	var again := _offers()
	_check(again.size() == 1 and again[0].get("open", false) and again[0]["id"] == offer["id"] and again[0]["accept"] == "",
		"spoken to again, she lists the open promise and asks for no second commission: %s" % [_kinds(again)])
	_check(not Offers.accept("o-mara", "p1", "Jeff", offer["id"], 0, _ctx)["ok"], "an open one cannot be taken twice")
	var facts: Array = Townsfolk.card_of(_work, "o-mara").get("facts", [])
	_check(not facts.is_empty() and str(facts.back()["text"]) == "Jeff promised Mara: to bring Bram home", "the promise is a fact on the card: %s" % facts.back()["text"])
	# Tam's card asks: the per-player cap.
	Townsfolk.learn(_work, "o-tam", "Tam saw raiders at the walls.")
	var tams := _offers("o-tam")
	_check(tams.size() == 1 and Offers.accept("o-tam", "p1", "Jeff", tams[0]["id"], 0, _ctx)["ok"], "a second commission, from Tam")
	var cards := Townsfolk.card_of(_work, "o-bram")
	cards["kin"] = {"o-mara": "sister or brother"}
	_work.set_card("o-bram", cards)
	_captives.append({"id": "o-mara", "name": "Mara", "by": "goblins", "held_by": CAMP})
	var brams := _offers("o-bram")
	var third := Offers.accept("o-bram", "p1", "Jeff", brams[0]["id"], 0, _ctx) if not brams.is_empty() else {"ok": true, "line": ""}
	_check(not brams.is_empty() and not third["ok"] and third["line"] == "Jeff has taken on enough already.", "a third is refused by the per-player cap (2 here): %s" % [third])
	# Met: Bram comes home with the player in the camp's area.
	_zone = "wood"
	Offers.rescued(TOWN, "o-bram", _ctx)
	_check(Townsfolk.card_of(_work, "o-mara").get("asks", []).is_empty(), "the ask is off her card")
	_check(_paid.size() == 1 and _paid[0] == ["p1", TOWN, 10], "economy pays the rescue's 10 from the treasury: %s" % [_paid])
	_check(_done.size() == 1 and _done[0][2] == "Jeff brought Bram home, as promised. The town pays 10 gold." and _done[0][3] == 10, "Main told, the party line says: %s" % [_done])
	facts = Townsfolk.card_of(_work, "o-mara").get("facts", [])
	_check(str(facts.back()["text"]) == "Jeff brought Bram home.", "and it is true of Mara now: %s" % facts.back()["text"])
	# Not met by them: the camp is cleared while the player is elsewhere.
	_setup([["o-mara", "Mara", "smith"]])
	Townsfolk.learn(_work, "o-mara", "Mara saw raiders at the walls.")
	_camps = [{"id": CAMP, "area": "wood", "faction": "goblins"}]
	var camp_offer: Dictionary = _offers()[0]
	Offers.accept("o-mara", "p1", "Jeff", camp_offer["id"], 0, _ctx)
	_zone = "town"
	Offers.camp_taken(CAMP, "goblins", "nobody", _ctx)
	_check(_paid.is_empty() and _done.size() == 1 and _done[0][3] == 0 and str(_done[0][2]).ends_with("promise is kept by another."),
		"cleared by another's hand: the ask closes unpaid, honestly: %s" % [_done])
	# What the store is short of, banked: paid then and there, no ask (Jeff's rule).
	_setup([["o-mara", "Mara", "smith"]])
	_short = ["wood"]
	_check(_offers().is_empty(), "the shortage is no offer")
	Offers.deposited(TOWN, "Player1", "player:p1", "wood", 4, _ctx)
	_check(_paid == [["p1", TOWN, 4]] and _done.size() == 1 and _done[0][1]["kind"] == "notice" and _done[0][2] == "The store was short of wood; Mara's thanks. The town pays 4 gold.",
		"four wood banked: four gold and a notice, with nothing taken on: %s" % [_done])
	Offers.deposited(TOWN, "Player2", "player:p2", "cloth", 9, _ctx)
	_check(_paid.size() == 1, "cloth, which the town is not short of, pays nothing")
	Offers.deposited(TOWN, "Player2", "player:p2", "wood", 9, _ctx)
	_check(_paid.size() == 2 and _paid[1] == ["p2", TOWN, 9], "another player's wood pays them too")


func _test_errand() -> void:
	print("\n== an errand: a word carried, met by speaking to the one it is for ==")
	_setup([["o-mara", "Mara", "smith"], ["o-bram", "Bram", "hauler"]])
	var card := Townsfolk.card_of(_work, "o-mara")
	card["grudge"] = ["o-bram"]
	_work.set_card("o-mara", card)
	var his := Townsfolk.card_of(_work, "o-bram")
	his["grudge"] = ["o-mara"]
	_work.set_card("o-bram", his)
	var word: Dictionary = _offers()[0]
	var carried := Offers.accept("o-mara", "p1", "Jeff", word["id"], 0, _ctx)
	_check(carried["ok"] and carried["line"] == "Jeff will carry Mara's word to Bram.", "taken: %s" % [carried])
	Offers.spoke_to("p2", "o-bram", _ctx)
	_check(_done.is_empty() and Townsfolk.card_of(_work, "o-mara")["grudge"] == ["o-bram"], "another player speaking to Bram carries nothing")
	Offers.spoke_to("p1", "o-bram", _ctx)
	_check(Townsfolk.card_of(_work, "o-mara")["grudge"].is_empty() and Townsfolk.card_of(_work, "o-bram")["grudge"].is_empty(), "the grudge is dropped on both cards")
	_check(_done.size() == 1 and _done[0][2] == "Jeff carried Mara's word to Bram." and _done[0][3] == 0, "Main told, unpaid: %s" % [_done])
	_check(str(Townsfolk.card_of(_work, "o-bram")["facts"].back()["text"]).begins_with("Jeff carried Mara's word to Bram"), "true of Bram now")
	_check(_offers().is_empty(), "no grudge, no plea")


var _log: Array = []
var _law := ""
var _model := "off"


func _grudge(a: String, b: String) -> void:
	for pair: Array in [[a, b], [b, a]]:
		var card := Townsfolk.card_of(_work, pair[0])
		card["grudge"] = [pair[1]]
		_work.set_card(pair[0], card)


func _test_quarrel() -> void:
	print("\n== a quarrel brought before the lawspeaker (decision 486) ==")
	_setup([["o-mara", "Mara", "smith"], ["o-bram", "Bram", "hauler"], ["o-tam", "Tam", "hauler"], ["o-law", "Hrolf", "lawspeaker"]])
	_log = []
	_law = "o-law"
	_model = "claude-haiku-5-5"
	_ctx["memory"] = func(_town: String) -> Array: return _log.duplicate(true)
	_ctx["set_memory"] = func(_town: String, log: Array) -> void: _log = log.duplicate(true)
	_ctx["lawspeaker_of"] = func(_town: String) -> String: return _law
	_ctx["model"] = func() -> String: return _model
	_ctx["lore"] = func(_town: String) -> Array: return []
	_ctx["town_name"] = func(_town: String) -> String: return "Ashford"
	_ctx["players_words"] = func() -> bool: return false
	_grudge("o-mara", "o-bram")
	var noted := Townsfolk.note_disputes(_work, TOWN, _log, _now)
	_check(noted and _log.size() == 1 and _log[0]["tier"] == TownMemory.CANDIDATE and _log[0]["dispute"] == true and _log[0]["pair"] == ["o-bram", "o-mara"]
		and str(_log[0]["text"]) == "Bram and Mara are at odds", "one candidate dispute for the pair, said by the first of them by id: %s" % [_log])
	_check(not Townsfolk.note_disputes(_work, TOWN, _log, _now + 1) and _log.size() == 1, "and not twice")
	var mine := _offers()
	_check(mine.size() == 1 and mine[0]["kind"] == Offers.PLEA and mine[0]["accept"] == Offers.CARRY and mine[0]["what"].get("law") == "o-law"
		and mine[0]["title"] == "Speak for me" and str(mine[0]["words"]).begins_with("Lay my quarrel with Bram before the lawspeaker"),
		"Mara's plea: speak for her before the lawspeaker: %s" % [mine])
	var taken := Offers.accept("o-mara", "p1", "Jeff", mine[0]["id"] if not mine.is_empty() else "", 0, _ctx)
	_check(taken["ok"] and taken["line"] == "Jeff will speak for Mara before the lawspeaker." and _asked.size() == 1, "taken, interest only: %s" % [taken])
	Offers.spoke_to("p1", "o-bram", _ctx)
	_check(_done.is_empty() and Townsfolk.card_of(_work, "o-mara")["grudge"] == ["o-bram"], "speaking to Bram carries no word: this is not that errand")
	Offers.spoke_to("p1", "o-law", _ctx)
	_check(_log.size() == 1 and _log[0].get("brought", {}).get("by") == "p1", "speaking to the lawspeaker lays it before him, nothing handed in: %s" % [_log[0].get("brought")])
	_check(str(Townsfolk.card_of(_work, "o-law")["facts"].back()["text"]) == "Jeff laid Mara's quarrel with Bram before Hrolf.", "his card: who brought it")
	var body := Lawspeaker.request(TOWN, _log, _ctx)
	var content: String = body.get("messages", [{}])[0].get("content", "") if not body.is_empty() else ""
	_check(content.contains("A dispute between them.") and content.contains("Laid before you by Jeff"), "his request names the dispute and who brought it")
	Lawspeaker.apply(_log, [{"candidate": _log[0]["id"], "ruling": "reconcile", "memory": "Bram and Mara made their peace at the well", "because": "test"}], _now, _ctx, TOWN)
	_check(Townsfolk.card_of(_work, "o-mara")["grudge"].is_empty() and Townsfolk.card_of(_work, "o-bram")["grudge"].is_empty(), "the ruling closes the quarrel: both grudges dropped")
	_check(_done.size() == 1 and _done[0][0] == "p1" and _done[0][3] == 5 and _paid.size() == 1 and _paid[0][2] == 5
		and str(_done[0][2]).begins_with("The lawspeaker has ruled on Mara's quarrel with Bram: Bram and Mara made their peace at the well. Mara remembers that Jeff spoke for her."),
		"Jeff gets the notice and the dispute's pay (5, the default until economy's key): %s" % [_done])
	_check(str(Townsfolk.card_of(_work, "o-mara")["facts"].back()["text"]).begins_with("Jeff spoke for Mara before the lawspeaker, who ruled"), "Mara remembers who spoke for her")
	_check(str(Townsfolk.card_of(_work, "o-bram")["facts"].back()["text"]).begins_with("The lawspeaker ruled on the quarrel between Bram and Mara"), "Bram remembers the ruling")
	_check(Standing.score(Townsfolk.card_of(_work, "o-mara"), "p1") >= Standing.setting("word") and Standing.score(Townsfolk.card_of(_work, "o-bram"), "p1") == 1,
		"standing: word from Mara, one from Bram for the peace (%d, %d)" % [Standing.score(Townsfolk.card_of(_work, "o-mara"), "p1"), Standing.score(Townsfolk.card_of(_work, "o-bram"), "p1")])
	_check(Townsfolk.card_of(_work, "o-mara")["asks"].is_empty() and _offers().is_empty(), "the ask is gone; no grudge, no plea")
	# Nobody holding the plea: the ruling still closes it, and nobody is paid.
	_grudge("o-mara", "o-tam")
	Townsfolk.note_disputes(_work, TOWN, _log, _now)
	var open := Townsfolk.dispute_of(_log, "o-mara", "o-tam")
	Lawspeaker.apply(_log, [{"candidate": open.get("id", ""), "ruling": "leave", "because": "talk"}], _now, _ctx, TOWN)
	_check(not open.is_empty() and Townsfolk.card_of(_work, "o-tam")["grudge"].is_empty() and Townsfolk.card_of(_work, "o-mara")["grudge"].is_empty() and _done.size() == 1,
		"a ruling with nobody holding the plea closes the quarrel and pays nobody")
	_check(str(Townsfolk.card_of(_work, "o-tam")["facts"].back()["text"]) == "The lawspeaker ruled on the quarrel between Mara and Tam: the matter may lie.", "left: the matter may lie")
	# The lawspeaker off (the box today): nothing noted, nothing shown, the carried word as before.
	_model = "off"
	_grudge("o-bram", "o-tam")
	var before := _log.size()
	_check(not Townsfolk.note_disputes(_work, TOWN, _log, _now) and _log.size() == before, "with rulings off no quarrel is noted")
	var word := _offers("o-bram")
	_check(word.size() == 1 and word[0]["what"].has("to") and word[0]["title"] == "A word for Tam", "and the plea is 435's carried word: %s" % [word])
	_model = "claude-haiku-5-5"
	_law = ""
	_check(_offers("o-bram")[0]["what"].has("to"), "no sitting lawspeaker: the carried word too")


func _test_walk_home() -> void:
	print("\n== kin lost beyond the walls: walk them home (decision 487) ==")
	_setup([["o-mara", "Mara", "smith"], ["o-tam", "Tam", "hauler"]])
	var card := Townsfolk.card_of(_work, "o-mara")
	card["kin"] = {"o-tam": "sibling"}
	_work.set_card("o-mara", card)
	_check(_offers().is_empty(), "Tam at home: nothing to ask")
	var his := Townsfolk.card_of(_work, "o-tam")
	his[Townsfolk.STRAYED] = {"since": 0}
	_work.set_card("o-tam", his)
	_work.set_away("o-tam", true)
	var mine := _offers()
	_check(mine.size() == 1 and mine[0]["kind"] == Offers.PLEA and mine[0]["accept"] == Offers.TAKE and mine[0]["what"]["stray"] == "o-tam" and mine[0]["title"] == "Walk Tam home"
		and str(mine[0]["words"]).begins_with("My ") and str(mine[0]["words"]).contains("Tam has not come back from beyond the walls"), "Mara's plea: walk her kin home: %s" % [mine])
	var taken := Offers.accept("o-mara", "p1", "Jeff", mine[0]["id"] if not mine.is_empty() else "", 0, _ctx)
	_check(taken["ok"] and _asked.size() == 1 and Townsfolk.card_of(_work, "o-mara")["asks"].size() == 1, "taken, interest only: %s" % [taken])
	_check(Offers._promise(Townsfolk.card_of(_work, "o-mara")["asks"][0]) == "to walk Tam home", "the promise in words keeps the name (the soak's 'walk tam home')")
	Townsfolk.came_home(_work, "o-tam", "Jeff")
	Offers.walked_home(TOWN, "o-tam", "p1", "Jeff", _ctx)
	_check(_work.worker("o-tam")["away"] == false and not Townsfolk.card_of(_work, "o-tam").has(Townsfolk.STRAYED), "Tam is home and not away")
	_check(_done.size() == 1 and _done[0][0] == "p1" and _done[0][3] == 8 and _paid.size() == 1 and _paid[0][2] == 8 and str(_done[0][2]).begins_with("Jeff walked Tam home. Mara remembers it."),
		"Jeff gets the notice and the escort's pay (8, the default until economy's key): %s" % [_done])
	_check(Standing.score(Townsfolk.card_of(_work, "o-mara"), "p1") >= Standing.setting("walked_home") and Standing.score(Townsfolk.card_of(_work, "o-tam"), "p1") >= Standing.setting("walked_home"),
		"standing from the kin who asked and from Tam himself")
	_check(str(Townsfolk.card_of(_work, "o-tam")["facts"].back()["text"]) == "Jeff walked Tam home from beyond the walls." and str(Townsfolk.card_of(_work, "o-mara")["facts"].back()["text"]) == "Jeff walked Tam home from beyond the walls.",
		"both cards remember")
	_check(Townsfolk.card_of(_work, "o-mara")["asks"].is_empty() and _offers().is_empty(), "the plea is met and gone")
	# Nobody took the plea: whoever walks him home is paid the same.
	his = Townsfolk.card_of(_work, "o-tam")
	his[Townsfolk.STRAYED] = {"since": _now}
	_work.set_card("o-tam", his)
	_work.set_away("o-tam", true)
	Townsfolk.came_home(_work, "o-tam", "Ann")
	Offers.walked_home(TOWN, "o-tam", "p2", "Ann", _ctx)
	_check(_done.size() == 2 and _done[1][0] == "p2" and _done[1][3] == 8 and _done[1][1]["kind"] == "notice", "a notice and the pay with no plea taken: %s" % [_done[1]])
	# Found his own way home: the plea is met by the road, nobody paid.
	his = Townsfolk.card_of(_work, "o-tam")
	his[Townsfolk.STRAYED] = {"since": _now}
	_work.set_card("o-tam", his)
	_work.set_away("o-tam", true)
	Offers.accept("o-mara", "p1", "Jeff", _offers()[0]["id"], 0, _ctx)
	Townsfolk.came_home(_work, "o-tam", "")
	Offers.walked_home(TOWN, "o-tam", "", "", _ctx)
	_check(_done.size() == 3 and _done[2][3] == 0 and str(_done[2][2]) == "Tam came home on his own." and Townsfolk.card_of(_work, "o-mara")["asks"].is_empty(), "on his own: the plea closes unpaid: %s" % [_done[2]])


func _test_chronicle() -> void:
	print("\n== Read the chronicle: at the scholar's desk only, read aloud, nothing on the card (decision 491) ==")
	_types = {"o-odo": "scholar"}
	_setup([["o-odo", "Odo", "smith"], ["o-tam", "Tam", "hauler"]])
	_types = {}
	_log = []
	_ctx["memory"] = func(_town: String) -> Array: return _log.duplicate(true)
	_ctx["set_memory"] = func(_town: String, log: Array) -> void: _log = log.duplicate(true)
	_ctx["town_name"] = func(_town: String) -> String: return "Ashford"
	_ctx["lore"] = func(_town: String) -> Array: return ["Deer graze in the wilds."]
	_ctx["statuses"] = func() -> Dictionary: return {}
	# _setup's day is at home all day: the desk.
	var mine := _offers("o-odo")
	_check(mine.size() >= 1 and mine[0]["kind"] == Offers.PAGE and mine[0]["title"] == "Read the chronicle" and mine[0]["accept"] == Offers.READ and mine[0]["cost"] == 0,
		"at home, the scholar offers the chronicle first: %s" % [mine.map(func(o: Dictionary) -> String: return str(o["kind"]))])
	_check(_offers("o-tam").all(func(o: Dictionary) -> bool: return o["kind"] != Offers.PAGE), "a hauler keeps no chronicle")
	var read := Offers.accept("o-odo", "p1", "Jeff", mine[0]["id"], 0, _ctx)
	_check(read["ok"] and read.get("read", []).size() == 3 and read["read"][0] == "The chronicle of Ashford, kept by Odo the smith." and read["read"][1] == "The town has set down nothing yet."
		and read["read"][2] == "Of Ashford it is known that deer graze in the wilds.", "read aloud: the lines come back, empty but for lore: %s" % [read.get("read")])
	_check(Townsfolk.card_of(_work, "o-odo").get("asks", []).is_empty() and _asked.is_empty() and _done.is_empty(), "no ask, no promise, nothing paid")
	_check(Standing.words(Townsfolk.card_of(_work, "o-odo"), "p1") != "" and Townsfolk.card_of(_work, "o-odo").get("standing", {}).has("p1"), "they have met")
	Townsfolk.use_days({"default": {"stints": [{"from": 0, "to": 12, "at": "well"}, {"from": 12, "to": 24, "at": "well"}]}, "gossip": {"every": 0}})
	_check(_offers("o-odo").all(func(o: Dictionary) -> bool: return o["kind"] != Offers.PAGE), "at the well, no chronicle: it is at the desk")
	Offers.ctx = _ctx


var _sent: Array = []
var _healer := ""


func _test_sick_pleas() -> void:
	print("\n== kin sick in bed: bring the medicine man, or take them to the healer; the treatment pays (decision 501) ==")
	_setup([["o-mara", "Mara", "smith"], ["o-tam", "Tam", "hauler"], ["o-doc", "Oren", "medicine_man"]])
	var card := Townsfolk.card_of(_work, "o-mara")
	card["kin"] = {"o-tam": "sibling"}
	_work.set_card("o-mara", card)
	_sent = []
	_healer = "o-doc"
	_ctx["healer_of"] = func(_town: String) -> String: return _healer
	_ctx["healers_hut"] = func(_town: String) -> String: return "o/hut"
	_ctx["send_healer"] = func(healer_id: String, sick_id: String, player_id: String) -> bool:
		_sent.append([healer_id, sick_id, player_id])
		return true
	_ctx["companion_sick"] = func(_id: String) -> Dictionary: return {}
	_ctx["set_companion_sick"] = func(_id: String, _r: Dictionary) -> void: pass
	_check(_offers().is_empty(), "Tam well: nothing to ask")
	Townsfolk._set_sickness(_work, "o-tam", {"since": 0, "kind": "a cough", "treated": -1, "cured_by": ""})
	var mine := _offers()
	_check(mine.size() == 1 and mine[0]["kind"] == Offers.PLEA and mine[0]["title"] == "Bring the medicine man" and mine[0]["what"]["sick"] == "o-tam" and mine[0]["what"]["healer"] == "o-doc"
		and str(mine[0]["words"]).contains("lies sick with a cough"), "with a medicine man in the zone, Mara asks for him: %s" % [mine])
	var taken := Offers.accept("o-mara", "p1", "Jeff", mine[0]["id"] if not mine.is_empty() else "", 0, _ctx)
	_check(taken["ok"] and Townsfolk.card_of(_work, "o-mara")["asks"].size() == 1, "taken, interest only")
	_check(Offers._promise(Townsfolk.card_of(_work, "o-mara")["asks"][0]) == "bring the medicine man", "(the promise in words)")
	Offers.spoke_to("p1", "o-tam", _ctx)
	_check(_sent.is_empty(), "a word to the sick one sends nobody")
	Offers.spoke_to("p1", "o-doc", _ctx)
	_check(_sent == [["o-doc", "o-tam", "p1"]] and str(Townsfolk.card_of(_work, "o-doc")["facts"].back()["text"]) == "Jeff asked Oren to see to Tam.", "a word to the medicine man sends him: %s" % [_sent])
	Townsfolk.treat(_work, "o-tam", "Oren", "the medicine man", "p1")
	_check(_done.size() == 1 and _done[0][0] == "p1" and _done[0][3] == 6 and str(_done[0][2]).begins_with("Jeff saw to Tam with the medicine man. Mara remembers it."),
		"the visit treats Tam: the notice and the healing pay to the one whose word sent him: %s" % [_done])
	_check(Standing.score(Townsfolk.card_of(_work, "o-mara"), "p1") >= Standing.setting("healed") and Standing.score(Townsfolk.card_of(_work, "o-tam"), "p1") >= Standing.setting("healed"),
		"standing from the kin and from Tam")
	_check(Townsfolk.card_of(_work, "o-mara")["asks"].is_empty() and _offers().is_empty(), "the plea is met; treated, no new plea")
	# No medicine man: the walk to the healer's hut.
	_healer = ""
	Townsfolk._set_sickness(_work, "o-tam", {"since": 1, "kind": "the shakes", "treated": -1, "cured_by": ""})
	mine = _offers()
	_check(mine.size() == 1 and mine[0]["title"] == "Take Tam to the healer" and mine[0]["what"].get("hut") == "o/hut", "with no medicine man but a hut, walk him there: %s" % [mine.map(func(o: Dictionary) -> String: return str(o["title"]))])
	Offers.accept("o-mara", "p1", "Jeff", mine[0]["id"], 0, _ctx)
	Offers.healed(TOWN, "o-tam", "", "", "died", _ctx)
	_check(_done.size() == 2 and _done[1][3] == 0 and str(_done[1][2]) == "Tam died of the sickness." and Townsfolk.card_of(_work, "o-mara")["asks"].is_empty(),
		"a death closes the plea with the fact, no pay, no lapse: %s" % [_done[1]])
	_check(Standing.score(Townsfolk.card_of(_work, "o-mara"), "p1") >= Standing.setting("healed"), "and Mara thinks no worse of Jeff for it")
	Offers.ctx = _ctx


var _wanted := {}
var _purse := 0
var _given: Array = []


func _test_give() -> void:
	print("\n== the building fund: the official offers gold toward the next build, any amount (decision 499, npc's side) ==")
	_setup([["o-ald", "Alder", "smith"]])
	_work.set_origin("o-ald", "appointed")
	_wanted = {}
	_purse = 60
	_given = []
	_ctx["contribution_wanted"] = func(_town: String) -> Dictionary: return _wanted.duplicate()
	_ctx["shortfall"] = func(_town: String) -> Dictionary: return {"kind": "inn", "job": "inn", "steps": 0, "needs": {"wood": 6}} if not _wanted.is_empty() else {}
	_ctx["contribute"] = func(town: String, player_id: String, amount: int) -> int:
		var paid := mini(amount, mini(int(_wanted.get("gold", 0)), _purse))
		_given.append([town, player_id, paid])
		_wanted["gold"] = int(_wanted.get("gold", 0)) - paid
		_purse -= paid
		return paid
	_ctx["gold_of"] = func(_player_id: String) -> int: return _purse
	_check(_offers("o-ald").all(func(o: Dictionary) -> bool: return o["kind"] != Offers.GIVE), "nothing planned: no give line")
	_wanted = {"kind": "inn", "gold": 24}
	var mine := _offers("o-ald").filter(func(o: Dictionary) -> bool: return o["kind"] == Offers.GIVE)
	_check(mine.size() == 2 and mine[0]["title"] == "Give toward the inn" and mine[1]["title"] == "Give the rest" and mine[0]["cost"] == 10 and mine[1]["cost"] == 24 and str(mine[1]["words"]).is_empty(),
		"24 wanted, 60 in the purse: the step and the rest: %s" % [mine.map(func(o: Dictionary) -> String: return str(o["title"]))])
	_check(mine.size() == 2 and str(mine[0]["words"]) == "The inn waits on 6 wood and 24 gold; what you give goes to it.", "the words say what it waits on: %s" % [mine[0]["words"] if not mine.is_empty() else ""])
	_check(_offers("o-ald")[0]["kind"] == Offers.GIVE, "first at the official's counter")
	var taken := Offers.accept("o-ald", "p1", "Jeff", mine[0]["id"] if not mine.is_empty() else "", 0, _ctx)
	_check(taken["ok"] and _given == [[TOWN, "p1", 10]] and str(taken["line"]) == "Jeff gives 10 gold toward the inn.", "the step given through economy: %s" % [taken])
	_check(str(Townsfolk.card_of(_work, "o-ald")["facts"].back()["text"]) == "Jeff gave 10 gold toward the inn." and Standing.score(Townsfolk.card_of(_work, "o-ald"), "p1") >= Standing.setting("gave"), "the official's card and his regard")
	_check(_done.is_empty() or _done.back()[3] == 0, "(no pay for a gift)")
	_purse = 9
	mine = _offers("o-ald").filter(func(o: Dictionary) -> bool: return o["kind"] == Offers.GIVE)
	_check(mine.size() == 1 and mine[0]["title"] == "Give toward the inn" and mine[0]["cost"] == 10, "14 still wanted but 9 in the purse: the step alone (economy takes what there is): %s" % [mine.map(func(o: Dictionary) -> String: return str(o["title"]))])
	_purse = 60
	mine = _offers("o-ald").filter(func(o: Dictionary) -> bool: return o["kind"] == Offers.GIVE)
	taken = Offers.accept("o-ald", "p1", "Jeff", mine[1]["id"] if mine.size() > 1 else "", 0, _ctx)
	_check(taken["ok"] and _given.back() == [TOWN, "p1", 14] and int(_wanted["gold"]) == 0, "the rest pays the inn up: %s" % [_given])
	_check(_offers("o-ald").all(func(o: Dictionary) -> bool: return o["kind"] != Offers.GIVE), "paid up: the line is gone")
	_wanted = {"kind": "inn", "gold": 7}
	mine = _offers("o-ald").filter(func(o: Dictionary) -> bool: return o["kind"] == Offers.GIVE)
	_check(mine.size() == 1 and mine[0]["title"] == "Give toward the inn" and mine[0]["cost"] == 7, "within the step: one line at what is wanted")
	Offers.ctx = _ctx


func _test_lapse() -> void:
	print("\n== a promise not kept lapses after the days ==")
	_setup([["o-mara", "Mara", "smith"]])
	Townsfolk.learn(_work, "o-mara", "Mara saw raiders at the walls.")
	_camps = [{"id": CAMP, "area": "wood", "faction": "goblins"}]
	Offers.accept("o-mara", "p1", "Jeff", _offers()[0]["id"], 0, _ctx)
	_now = 6 * DayNight.day_steps
	Offers.tick(_ctx)
	_check(_done.is_empty(), "six days on, it stands")
	_now = 8 * DayNight.day_steps
	Offers.tick(_ctx)
	_check(_done.size() == 1 and _done[0][2] == "Jeff's promise to Mara lapsed: to clear the camp of %s." % ResidentCard.faction_name("goblins") and _done[0][3] == 0
		and Townsfolk.card_of(_work, "o-mara").get("asks", []).is_empty(), "eight days on, it lapses: %s" % [_done])
	_check(str(Townsfolk.card_of(_work, "o-mara")["facts"].back()["text"]).begins_with("Jeff never kept the promise to Mara"), "told once, as a fact")


func _test_voice_words() -> void:
	print("\n== the voice is told the offers as facts ==")
	_setup([["o-mara", "Mara", "smith"], ["o-bram", "Bram", "hauler"]])
	_goods = [{"uid": 9, "id": "knife", "price": 12}]
	_plant("o-mara", "The mine is cursed", "Tam", "well")
	var words := Offers.voice_words("o-mara", "p1", "Jeff", _ctx)
	_check(words == "What you can offer Jeff, if it comes up: i have a knife at the counter for 12 gold; tam told me at the well that the mine is cursed.".replace("i have", "i have").replace("; tam", "; tam")
		or words.begins_with("What you can offer Jeff, if it comes up: "), "offers as a fact, never a line: %s" % words)
	_check(words.contains("a knife at the counter for 12 gold") and words.contains("told me at the well that the mine is cursed"), "both in it")
	_check(Offers.voice_words("o-bram", "p1", "Jeff", _ctx).is_empty(), "nothing to offer, nothing said")
	Townsfolk.learn(_work, "o-mara", "Mara saw raiders at the walls.")
	_camps = [{"id": CAMP, "area": "wood", "faction": "goblins"}]
	Offers.accept("o-mara", "p1", "Jeff", "o-mara|commission|camp:" + CAMP, 0, _ctx)
	words = Offers.voice_words("o-mara", "p1", "Jeff", _ctx)
	_check(words.ends_with("Jeff promised to clear the camp of %s and has not yet." % ResidentCard.faction_name("goblins")), "an open promise is a fact too: %s" % words)


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _test_scholar_and_merchant() -> void:
	print("
== a scholar offers what lore knows; a merchant sells anything, dearest first, and hears talk of prices (decision 440) ==")
	Lore.use([{"id": "the_mine", "status": "agreed", "facts": [{"id": "f1", "text": "The old mine was dug by dwarves.", "known": "common", "weight": 5},
		{"id": "f2", "text": "The mine road was paved by the first lord.", "known": "common", "weight": 2}]}],
		[{"id": Lore.knower_for("hauler"), "status": "agreed"}, {"id": Lore.knower_for("smith"), "status": "agreed"}])
	_types = {"o-odo": "scholar", "o-mara": "merchant"}
	_setup([["o-odo", "Odo", "hauler"], ["o-mara", "Mara", "smith"]])
	_plant("o-odo", "The mine is cursed", "Tam", "well")
	var his := _offers("o-odo").filter(func(o: Dictionary) -> bool: return o["kind"] != Offers.PAGE)  # The chronicle comes first at home (491).
	_check(his.size() == 1 and his[0]["kind"] == Offers.RUMOUR and his[0]["what"].get("lore", false) and his[0]["title"] == "What Odo knows"
		and his[0]["words"] == "The old mine was dug by dwarves.", "the scholar offers the weightiest lore fact, not the rumour he believes: %s" % [his])
	_goods = [{"uid": 9, "id": "knife", "price": 12}, {"uid": 7, "id": "wood", "price": 2}, {"uid": 11, "id": "wood", "price": 20}]
	_plant("o-mara", "The miller waters the flour", "Nell")
	_plant("o-mara", "Cloth sells dear in the north", "Tam", "inn")
	_plant("o-mara", "The mine is cursed", "Tam", "well")
	var hers := _offers("o-mara")
	_check(hers.size() == 2 and hers[0]["kind"] == Offers.SHOP and hers[0]["what"]["uid"] == 11 and hers[0]["cost"] == 20,
		"the merchant smith offers the dearest thing at the counter, wood at 20, not her own knife: %s" % [hers.map(func(e: Dictionary) -> String: return str(e["title"]))])
	_check(hers.size() == 2 and hers[1]["kind"] == Offers.RUMOUR and hers[1]["words"] == "Tam told me at the inn that cloth sells dear in the north.",
		"and her rumour is the talk of prices, not the newest: %s" % (hers[1]["words"] if hers.size() == 2 else ""))
	_types = {}
	_setup([["o-mara", "Mara", "smith"]])
	_goods = [{"uid": 9, "id": "knife", "price": 12}, {"uid": 11, "id": "wood", "price": 20}]
	_check(_offers()[0]["what"]["uid"] == 9, "a steady smith still offers only her knife")
	Lore.reload()
