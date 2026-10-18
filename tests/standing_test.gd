extends Node
## Standing (decision 443): what one of the town's people thinks of a
## player, on the card, moved only by the world's events. The words by
## score and by ladder (a resident's, a companion's); the first words; each
## event through offers' hooks (a commission met, by them and by another;
## a lapse; a word carried; a loan paid down and cleared; a gift, plain and
## a favourite; kin brought home with no commission; a raid fought off
## with the player there); hearsay moving it a little and never past its
## own events; gossip passing a strong view; decay toward 0; offers scaled
## by it. Pure sim: no Main, no port, no scratch folder. Reads the repo's
## levels, never the shared overlay. Run it with tests/run.ps1 or
## tests/run.sh. Prints PASS/FAIL per assertion and quits with exit code 1
## if any assertion failed, 0 otherwise.

const TOWN := "s/store"
const CAMP := "s/camp@9,9"
const CATALOG := {"knife": {"id": "knife", "name": "knife", "made": {"by": "smith"}, "tags": ["tool"]},
	"apple": {"id": "apple", "name": "apple", "tags": ["food"]}, "wood": {"id": "wood", "name": "wood"}}

var _failures := 0
var _now := 0
var _stock: Stockpile
var _work: Production
var _ctx := {}
var _done: Array = []
var _paid: Array = []
var _captives: Array = []
var _camps: Array = []
var _short: Array = []
var _zone := ""
var _players: Array = []


func _ready() -> void:
	World.set_process(false)
	_test_words_and_ladders()
	_test_first_words()
	_test_commissions_move_it()
	_test_word_loan_gift()
	_test_kin_home_and_raid()
	_test_heard_and_gossip()
	_test_decay()
	_test_offers_scaled()
	Production.profile_of = Callable()
	Production.type_of = Callable()
	Townsfolk.use_days({})
	Offers.use_settings({})
	Standing.use_settings({})
	Offers.ctx = {}
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


static func _profile(_trade: String, _type := "") -> Dictionary:
	return {"intellect": 5, "superstition": 5, "creativity": 5, "integrity": 5}


static func _type(_id: String) -> String:
	return ""


func _setup(folk: Array = [["s-mara", "Mara", "smith"], ["s-bram", "Bram", "hauler"], ["s-tam", "Tam", "hauler"]]) -> void:
	_now = 1000
	_done.clear()
	_paid.clear()
	_captives = []
	_camps = []
	_short = []
	_zone = ""
	_players = []
	Production.profile_of = _profile
	Production.type_of = _type
	Townsfolk.use_days({"default": {"stints": [{"from": 0, "to": 12, "at": "well"}, {"from": 12, "to": 24, "at": "well"}]}, "offset_hours": 0,
		"gossip": {"every": 100, "places": ["well", "inn", "square", "temple"]}})
	Townsfolk._gossip_due.clear()
	Offers.use_settings({"max": 3, "per_player": 3, "days": 7, "fetch": 6})
	Standing.use_settings({})
	var clock := func() -> int: return _now
	var cat := func() -> Dictionary: return CATALOG
	_stock = Stockpile.new({}, clock, ItemBook.new(clock))
	_work = Production.new({}, _stock, null, clock, Production.read_rules(), cat)
	for each: Array in folk:
		_work.add_worker(each[0], each[1], [each[2]], TOWN)
	for each: Array in folk:
		Townsfolk.card_of(_work, each[0])
	for each: Array in folk:
		var card := Townsfolk.card_of(_work, each[0])
		card["kin"] = {}
		card["grudge"] = []
		card["asks"] = []
		card.erase("standing")
		_work.set_card(each[0], card)
	_ctx = {
		"production": _work,
		"goods": func(_town: String) -> Array: return [],
		"catalog": func() -> Dictionary: return CATALOG,
		"captives": func(_town: String) -> Array: return _captives,
		"camps": func() -> Array: return _camps,
		"hostile": func(faction: String, _town: String) -> bool: return faction == "goblins",
		"short": func(_town: String) -> Array: return _short,
		"area_name": func(area: String) -> String: return area,
		"area_of": func(_town: String) -> String: return "town",
		"pay_commission": func(player_id: String, town: String, gold: int) -> int:
			_paid.append([player_id, town, gold])
			return gold,
		"pay_loan": func(_player_id: String, worker_id: String, gold: int) -> int:
			var owed := float(_work.worker(worker_id).get("loan", 0.0))
			var paid := mini(gold, ceili(owed))
			_work.set_loan(worker_id, owed - paid, false)
			return paid,
		"pay": func() -> Dictionary: return {"rescue": 10, "camp": 20, "fetch": 1},
		"zone_of": func(_player_id: String) -> String: return _zone,
		"players_in": func(area: String) -> Array: return _players if area == _zone else [],
		"name_of": func(player_id: String) -> String: return "Jeff" if player_id == "p1" else player_id,
		"asked": func(_player_id: String, _ask: Dictionary) -> void: pass,
		"done": func(player_id: String, ask: Dictionary, line: String, paid: int) -> void: _done.append([player_id, ask, line, paid]),
	}
	Offers.ctx = _ctx


func _card(id: String) -> Dictionary:
	return Townsfolk.card_of(_work, id)


func _score(id: String, player := "p1") -> int:
	return Standing.score(_card(id), player)


func _why(id: String, player := "p1") -> String:
	var reasons: Array = Standing.entry(_card(id), player).get("why", [])
	return str(reasons.back()) if not reasons.is_empty() else ""


func _test_words_and_ladders() -> void:
	print("\n== the words by score, by the resident's ladder and the companion's ==")
	var card := {}
	_check(Standing.words(card, "p1") == "stranger" and Standing.fact(card, "p1", "Jeff").is_empty(), "no entry: a stranger, nothing to say")
	_check(Standing.met(card, "p1", 10) and Standing.words(card, "p1") == "known" and Standing.fact(card, "p1", "Jeff") == "You have met Jeff before.",
		"the first words make them known: %s" % Standing.fact(card, "p1", "Jeff"))
	Standing.bump(card, "p1", 3, "brought Bram home", 20)
	_check(Standing.words(card, "p1") == "trusted" and Standing.fact(card, "p1", "Jeff") == "You trust Jeff: they brought Bram home.",
		"at 3, trusted, with the reason: %s" % Standing.fact(card, "p1", "Jeff"))
	Standing.bump(card, "p1", -8, "let a promise lapse, to bring Bram home", 30)
	_check(Standing.score(card, "p1") == -5 and Standing.words(card, "p1") == "wronged"
		and Standing.fact(card, "p1", "Jeff") == "Jeff wronged you: they let a promise lapse, to bring Bram home.", "at -5, wronged: %s" % Standing.fact(card, "p1", "Jeff"))
	Standing.bump(card, "p1", 40, "x", 40)
	_check(Standing.score(card, "p1") == 10 and Standing.entry(card, "p1")["why"].size() == 3, "the score stops at most (10) and three reasons are kept")
	var hers := {}
	_check(Standing.words(hers, "p1", Standing.COMPANION) == "fond", "a companion starts fond of her player, with no entry")
	Standing.bump(hers, "p1", 3, "carried you out of the raiders' camp", 5)
	_check(Standing.words(hers, "p1", Standing.COMPANION) == "close" and Standing.fact(hers, "p1", "Jeff", Standing.COMPANION) == "You are close to Jeff: they carried you out of the raiders' camp.",
		"at 3 she is close: %s" % Standing.fact(hers, "p1", "Jeff", Standing.COMPANION))
	Standing.bump(hers, "p1", 3, "fed you through the winter", 6)
	_check(Standing.words(hers, "p1", Standing.COMPANION) == "devoted", "at 6, devoted")
	Standing.bump(hers, "p1", -10, "left you behind", 7)
	_check(Standing.words(hers, "p1", Standing.COMPANION) == "wary" and Standing.words(hers, "p2", Standing.COMPANION) == "fond", "at -4 wary; of another player, fond still")
	_check(Standing.words(card, "p1", Standing.RESIDENT) == "trusted" and Standing.words(card, "p9") == "stranger", "the resident ladder by name; a stranger stays one")


func _test_first_words() -> void:
	print("\n== the first words ==")
	_setup()
	var card := _card("s-mara")
	_check(Standing.met(card, "p1", 1000) and not Standing.met(card, "p1", 1001), "met once, not again")
	_check(Standing.first_words(card, "p1", 1000) and not Standing.first_words(card, "p1", 1001), "the first step is known")
	_work.set_card("s-mara", card)
	_check(Standing.words(_card("s-mara"), "p1") == "known" and Standing.words(_card("s-mara"), "p2") == "stranger", "saved with the card; another player a stranger")


func _test_commissions_move_it() -> void:
	print("\n== a commission met moves it; met by another or lapsed, otherwise ==")
	_setup()
	var card := _card("s-mara")
	card["kin"] = {"s-bram": "sister or brother"}
	_work.set_card("s-mara", card)
	_captives = [{"id": "s-bram", "name": "Bram", "by": "goblins", "held_by": CAMP}]
	_camps = [{"id": CAMP, "area": "wood", "faction": "goblins"}]
	var spoke := _card("s-mara")
	Standing.met(spoke, "p1", _now)  # Their first words, as Main makes them.
	_work.set_card("s-mara", spoke)
	var offer: Dictionary = Offers.of("s-mara", "p1", _ctx)[0]
	Offers.accept("s-mara", "p1", "Jeff", offer["id"], 0, _ctx)
	_check(_score("s-mara") == 0 and Standing.words(_card("s-mara"), "p1") == "known", "taking it on moves nothing yet (known)")
	_zone = "wood"
	_players = ["p1"]
	Offers.rescued(TOWN, "s-bram", _ctx)
	_check(_score("s-mara") == 4 and Standing.words(_card("s-mara"), "p1") == "trusted" and _why("s-mara") == "brought Bram home",
		"brought home by them: +4, trusted, the reason kept (%d, %s)" % [_score("s-mara"), _why("s-mara")])
	_setup()
	card = _card("s-mara")
	card["kin"] = {"s-bram": "sister or brother"}
	_work.set_card("s-mara", card)
	_captives = [{"id": "s-bram", "name": "Bram", "by": "goblins", "held_by": CAMP}]
	_camps = [{"id": CAMP, "area": "wood", "faction": "goblins"}]
	offer = Offers.of("s-mara", "p1", _ctx)[0]
	Offers.accept("s-mara", "p1", "Jeff", offer["id"], 0, _ctx)
	_zone = "town"
	Offers.rescued(TOWN, "s-bram", _ctx)
	_check(_score("s-mara") == 0, "brought home by another's hand: unchanged")
	_setup()
	Townsfolk.learn(_work, "s-mara", "Mara saw raiders at the walls.")
	_camps = [{"id": CAMP, "area": "wood", "faction": "goblins"}]
	Offers.accept("s-mara", "p1", "Jeff", Offers.of("s-mara", "p1", _ctx)[0]["id"], 0, _ctx)
	_now += 8 * DayNight.day_steps
	Offers.tick(_ctx)
	_check(_score("s-mara") == -2 and _why("s-mara").begins_with("let a promise lapse"), "a lapse: -2 (%d, %s)" % [_score("s-mara"), _why("s-mara")])
	_setup()
	_short = ["wood"]
	Offers.deposited(TOWN, "Player1", "player:p1", "wood", 6, _ctx)
	_check(_score("s-mara") == 1 and _score("s-tam") == 1 and _why("s-mara") == "brought wood the town was short of" and _paid == [["p1", TOWN, 6]],
		"what the store was short of, banked: +1 on every card and the pay, with nothing asked (%d, %s)" % [_score("s-mara"), _why("s-mara")])


func _test_word_loan_gift() -> void:
	print("\n== a word carried, a loan paid down, a gift ==")
	_setup()
	var card := _card("s-mara")
	card["grudge"] = ["s-bram"]
	_work.set_card("s-mara", card)
	var his := _card("s-bram")
	his["grudge"] = ["s-mara"]
	_work.set_card("s-bram", his)
	Offers.accept("s-mara", "p1", "Jeff", Offers.of("s-mara", "p1", _ctx)[0]["id"], 0, _ctx)
	Offers.spoke_to("p1", "s-bram", _ctx)
	_check(_score("s-mara") == 2 and _score("s-bram") == 2, "a word carried: +2 on both cards (%d, %d)" % [_score("s-mara"), _score("s-bram")])
	_setup()
	_work.set_loan("s-mara", 12.0, false)
	Offers.accept("s-mara", "p1", "Jeff", Offers.of("s-mara", "p1", _ctx)[0]["id"], 6, _ctx)
	_check(_score("s-mara") == 2 and _why("s-mara") == "paid 6 gold of their debt", "half a loan paid: two quarters, +2 (%d)" % _score("s-mara"))
	Offers.accept("s-mara", "p1", "Jeff", Offers.of("s-mara", "p1", _ctx)[0]["id"], 6, _ctx)
	_check(_score("s-mara") == 8 and _why("s-mara") == "cleared their debt to the town", "the rest, all four quarters of what is left, clears it: +4 and +2 for clearing (%d)" % _score("s-mara"))
	_setup()
	var line := Offers.gift("p1", "Jeff", "s-mara", "wood", _ctx)
	_check(_score("s-mara") == 1 and line == "Jeff gives Mara some wood." or line.begins_with("Jeff gives Mara"), "a gift of wood: +1 (%d): %s" % [_score("s-mara"), line])
	line = Offers.gift("p1", "Jeff", "s-mara", "knife", _ctx)
	_check(_score("s-mara") == 3 and line.ends_with(", and it is what they like best."), "a tool to a smith: +2 (%d): %s" % [_score("s-mara"), line])
	card = _card("s-mara")
	card["traits"]["food"] = "apples"
	_work.set_card("s-mara", card)
	Offers.gift("p1", "Jeff", "s-mara", "apple", _ctx)
	_check(_score("s-mara") == 5 and _why("s-mara") == "gave them an apple", "her favourite food: +2 (%d, %s)" % [_score("s-mara"), _why("s-mara")])


func _test_kin_home_and_raid() -> void:
	print("\n== kin brought home with no commission; a raid fought off with the player there ==")
	_setup()
	var card := _card("s-mara")
	card["kin"] = {"s-bram": "sister or brother"}
	_work.set_card("s-mara", card)
	_camps = [{"id": CAMP, "area": "wood", "faction": "goblins"}]
	_zone = "wood"
	_players = ["p1"]
	Offers.rescued(TOWN, "s-bram", _ctx)
	_check(_score("s-mara") == 4 and _score("s-tam") == 0, "his sister: +4; a neighbour with no kin: nothing (%d, %d)" % [_score("s-mara"), _score("s-tam")])
	_zone = "town"
	Townsfolk._raided(_work, TOWN, {"repelled": true, "faction": "goblins", "captives": []})
	_check(_score("s-mara") == 5 and _score("s-tam") == 1 and _why("s-tam") == "stood with the town when raiders came", "fought off with them there: +1 on every card")
	_players = []
	Townsfolk._raided(_work, TOWN, {"repelled": true, "faction": "goblins", "captives": []})
	_check(_score("s-tam") == 1, "fought off with no player there: nothing")


func _test_heard_and_gossip() -> void:
	print("\n== hearsay moves it a little, never past their own dealings; gossip passes a strong view ==")
	var card := {}
	_check(Standing.heard(card, "p1", 1, "brought Bram home", "Mara", 5) and Standing.score(card, "p1") == 1, "heard well of: +1")
	Standing.heard(card, "p1", 1, "x", "Mara", 6)
	_check(not Standing.heard(card, "p1", 1, "y", "Tam", 7) and Standing.score(card, "p1") == 2, "and no further than 2")
	Standing.bump(card, "p1", -3, "let a promise lapse", 8)
	_check(not Standing.heard(card, "p1", 1, "z", "Mara", 9) and Standing.score(card, "p1") == -1, "with dealings of their own, hearsay moves nothing")
	_setup([["s-mara", "Mara", "smith"], ["s-tam", "Tam", "hauler"]])
	var hers := _card("s-mara")
	Standing.bump(hers, "p1", 4, "brought Bram home", _now)
	_work.set_card("s-mara", hers)
	Townsfolk.gossip(_work)  # Arms.
	var told := false
	for i in 8:
		_now += 100
		Townsfolk.gossip(_work)
		if _score("s-tam") == 1:
			told = true
			break
	var heard: Array = _work.worker("s-tam").get("heard", [])
	_check(told and Standing.words(_card("s-tam"), "p1") == "known" and _why("s-tam") == "Mara says brought Bram home",
		"Tam leans Mara's way: +1, known, remembering who said so (%s)" % _why("s-tam"))
	_check(not heard.is_empty() and str(heard[0].get("text", "")) == "Jeff brought Bram home" and str(heard[0].get("fits", "")) == Hearsay.WITNESSED,
		"and keeps it as hearsay from her: %s" % [heard.map(func(e: Dictionary) -> String: return str(e["text"]))])


func _test_decay() -> void:
	print("\n== standing fades toward 0 ==")
	var card := {}
	Standing.bump(card, "p1", 4, "brought Bram home", 0)
	Standing.bump(card, "p2", -2, "let a promise lapse", 0)
	var day := DayNight.day_steps
	_check(Standing.decay(card, 9 * day).is_empty() and Standing.score(card, "p1") == 4, "nine days on, it stands")
	_check(Standing.decay(card, 10 * day).size() == 2 and Standing.score(card, "p1") == 3 and Standing.score(card, "p2") == -1, "ten days on, one step toward 0 each way")
	_check(Standing.decay(card, 11 * day).is_empty(), "and not again the next day")
	for i in 10:
		Standing.decay(card, (20 + 10 * i) * day)
	_check(Standing.score(card, "p1") == 0 and Standing.score(card, "p2") == 0, "down to 0 and no further")
	_setup([["s-mara", "Mara", "smith"], ["s-tam", "Tam", "hauler"]])
	var hers := _card("s-mara")
	Standing.bump(hers, "p1", 2, "gave them a knife", _now)
	_work.set_card("s-mara", hers)
	Townsfolk.gossip(_work)
	_now += 10 * day + 100
	Townsfolk.gossip(_work)
	_check(_score("s-mara") == 1, "Townsfolk's tick sweeps the residents' cards (%d)" % _score("s-mara"))


func _test_offers_scaled() -> void:
	print("\n== offers scaled by standing ==")
	_setup([["s-mara", "Mara", "smith"], ["s-bram", "Bram", "hauler"]])
	Townsfolk.learn(_work, "s-mara", "Mara saw raiders at the walls.")
	_camps = [{"id": CAMP, "area": "wood", "faction": "goblins"}]
	_ctx["goods"] = func(_town: String) -> Array: return [{"uid": 9, "id": "knife", "price": 12}]
	var card := _card("s-mara")
	card["grudge"] = ["s-bram"]
	_work.set_card("s-mara", card)
	var kinds := Offers.of("s-mara", "p1", _ctx).map(func(e: Dictionary) -> String: return str(e["kind"]))
	_check(kinds == [Offers.SHOP, Offers.COMMISSION, Offers.PLEA], "known: shop, commission, plea (%s)" % [kinds])
	card = _card("s-mara")
	Standing.bump(card, "p1", -3, "let a promise lapse", _now)
	_work.set_card("s-mara", card)
	kinds = Offers.of("s-mara", "p1", _ctx).map(func(e: Dictionary) -> String: return str(e["kind"]))
	_check(kinds == [Offers.PLEA], "wronged: nothing but the plea (%s)" % [kinds])
	card = _card("s-mara")
	Standing.bump(card, "p1", 7, "brought Bram home", _now)
	_work.set_card("s-mara", card)
	kinds = Offers.of("s-mara", "p1", _ctx).map(func(e: Dictionary) -> String: return str(e["kind"]))
	_check(kinds == [Offers.COMMISSION, Offers.SHOP, Offers.PLEA], "trusted: the commission first (%s)" % [kinds])
	Offers.accept("s-mara", "p1", "Jeff", Offers.of("s-mara", "p1", _ctx)[0]["id"], 0, _ctx)
	_camps = [{"id": "s/camp@2,2", "area": "fen", "faction": "goblins"}]
	var again := Offers.of("s-mara", "p1", _ctx)
	_check(again.size() >= 2 and bool(again[0].get("open", false)) and again[1]["kind"] == Offers.COMMISSION, "and a second commission while one is open (%s)" % [again.map(func(e: Dictionary) -> String: return str(e["title"]))])
	_check(Offers.of("s-mara", "p2", _ctx).map(func(e: Dictionary) -> String: return str(e["kind"])) == [Offers.SHOP, Offers.PLEA], "a stranger gets the plain order, and no commission while another's is open")


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
