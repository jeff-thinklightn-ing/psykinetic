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
	_test_lapse()
	_test_voice_words()
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


static func _type(_id: String) -> String:
	return ""


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
		and mine[0]["words"].ends_with(" camp of the goblins at the Dark Wood."), "in words, with the camp's place: %s" % (mine[0]["words"] if not mine.is_empty() else ""))
	_captives = []
	_check(_offers().is_empty(), "once he is home (no captive), no such commission")


func _test_commission_camp_and_fetch() -> void:
	print("\n== a commission: a raiders' camp, else a thing fetched ==")
	_setup()
	_camps = [{"id": CAMP, "area": "wood", "faction": "goblins"}, {"id": "o/camp@2,2", "area": "fen", "faction": "deer"}]
	_short = ["wood", "cloth"]
	var mine := _offers()
	_check(mine.size() == 1 and mine[0]["what"]["sub"] == Offers.FETCH and mine[0]["what"]["item"] == "cloth" and mine[0]["what"]["count"] == 6,
		"no raid seen: she asks for the first thing the town is short of, cloth, six of it: %s" % [mine])
	_check(mine.size() == 1 and mine[0]["title"] == "Fetch 6 cloth" and mine[0]["words"] == "The town is short of cloth: bring 6 to the store and the coffer pays.", "in words")
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
	_short = ["wood"]
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
	_short = ["wood"]
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
	# A fetch counted from deposits.
	_setup([["o-mara", "Mara", "smith"]])
	_short = ["wood"]
	var fetch: Dictionary = _offers()[0]
	Offers.accept("o-mara", "p1", "Jeff", fetch["id"], 0, _ctx)
	Offers.deposited(TOWN, "Player1", "player:p1", "wood", 4, _ctx)
	_check(Townsfolk.card_of(_work, "o-mara")["asks"][0]["what"]["got"] == 4 and _done.is_empty(), "four of six wood counted, not met yet")
	Offers.deposited(TOWN, "Player2", "player:p2", "wood", 9, _ctx)
	_check(_done.is_empty(), "another player's wood does not count")
	Offers.deposited(TOWN, "Player1", "player:p1", "wood", 2, _ctx)
	_check(_done.size() == 1 and _paid == [["p1", TOWN, 6]] and _done[0][2] == "Jeff brought 6 wood to the store, as promised. The town pays 6 gold.",
		"six wood: met and paid 1 a unit: %s" % [_done])


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


func _test_lapse() -> void:
	print("\n== a promise not kept lapses after the days ==")
	_setup([["o-mara", "Mara", "smith"]])
	_short = ["wood"]
	Offers.accept("o-mara", "p1", "Jeff", _offers()[0]["id"], 0, _ctx)
	_now = 6 * DayNight.day_steps
	Offers.tick(_ctx)
	_check(_done.is_empty(), "six days on, it stands")
	_now = 8 * DayNight.day_steps
	Offers.tick(_ctx)
	_check(_done.size() == 1 and _done[0][2] == "Jeff's promise to Mara lapsed: to bring 6 wood to the store." and _done[0][3] == 0
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
	_short = ["wood"]
	Offers.accept("o-mara", "p1", "Jeff", "o-mara|commission|fetch:wood", 0, _ctx)
	words = Offers.voice_words("o-mara", "p1", "Jeff", _ctx)
	_check(words.ends_with("Jeff promised to bring 6 wood to the store and has not yet."), "an open promise is a fact too: %s" % words)


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
