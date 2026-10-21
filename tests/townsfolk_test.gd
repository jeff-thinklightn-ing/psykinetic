extends Node
## Townsfolk (decision 393): the hidden personality types and the thief's
## lift. The roll is by worker id (the same every time), draws only the
## agreed types by levels/townsfolk.json's weights, whose shares over many
## ids match them, is steady past them and none for a companion; the file's
## keys are lore's types and its weights well formed. Economy's Production
## keeps the type on the record through Production.type_of, saves it, and
## rolls one for a worker loaded without (a save from before). A thief in
## town takes one of the store's goods every "every" steps with "chance",
## never gold, never below "leave", nothing while away or when the store is
## short, as a ledger line by "missing" with no name; a steady resident
## never does; the type is never in the label. Reads the repo's levels,
## never the shared overlay. Run it with tests/run.ps1 or tests/run.sh.
## Prints PASS/FAIL per assertion and quits with exit code 1 if any
## assertion failed, 0 otherwise.

const TOWN := "tf/store"
const CATALOG := {}
const DAY := 54000

var _failures := 0
var _now := 0
var _stock: Stockpile
var _work: Production


func _ready() -> void:
	World.set_process(false)
	Production.type_of = Townsfolk.roll_type
	_test_rules_file()
	_test_roll()
	_test_record()
	_test_lift()
	_test_hidden()
	_test_gold_lift()
	_test_fence_and_catch()
	_test_strays()
	_test_scoundrel()
	_test_sickness()
	_test_road_news()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	Offers.ctx = {}  # Static callables into this node would crash the quit.
	get_tree().quit(1 if _failures > 0 else 0)


func _setup(saved := {}) -> void:
	_now = 0
	var clock := func() -> int: return _now
	var cat := func() -> Dictionary: return CATALOG
	_stock = Stockpile.new({}, clock, ItemBook.new(clock))
	_work = Production.new(saved, _stock, null, clock, Production.read_rules(), cat)


func _test_rules_file() -> void:
	print("\n== levels/townsfolk.json: weights over lore's types, the thief's rules ==")
	Townsfolk.use_rules({})
	var weights := Townsfolk.type_weights()
	var all := Lore.types("draft")
	var bad: Array[String] = []
	var agreed_sum := 0.0
	for type: String in weights:
		if not type in all or weights[type] < 0.0:
			bad.append(type)
		if type in Lore.types():
			agreed_sum += weights[type]
	_check(not weights.is_empty() and bad.is_empty(), "every weighted type is one of lore's and its weight is not negative %s" % [bad])
	_check(agreed_sum > 0.0 and agreed_sum < 100.0, "the agreed types' shares leave room for steady (%.0f per 100)" % agreed_sum)
	_check(not Townsfolk.STEADY in weights, "steady has no weight: it is the rest")
	var thief: Dictionary = Townsfolk.rules().get("thief", {})
	_check(int(thief.get("every", 0)) > 0 and float(thief.get("chance", 0.0)) > 0.0 and float(thief.get("chance", 2.0)) <= 1.0
		and int(thief.get("leave", -1)) >= 1 and thief.get("takes") is Array and not "gold" in thief.get("takes", []),
		"the thief's every, chance (0..1), leave and takes (no gold) are set")


func _test_roll() -> void:
	print("\n== the roll: by id, weighted, steady the rest, none for a companion ==")
	Townsfolk.use_rules({"type_weights": {"thief": 10.0, "bard": 20.0, "scoundrel": 0.0, "wizard": 50.0}})
	var first := Townsfolk.roll_type("resident:bram")
	_check(first == Townsfolk.roll_type("resident:bram"), "the same id rolls the same type (%s)" % first)
	_check(Townsfolk.roll_type("companion:jeff").is_empty() and Townsfolk.roll_type("").is_empty(), "a companion resting in town, or no id, has no type")
	var counts := {}
	var n := 4000
	for i in n:
		var type := Townsfolk.roll_type("w%d" % i)
		counts[type] = int(counts.get(type, 0)) + 1
	var thieves := float(counts.get("thief", 0)) / n * 100.0
	var bards := float(counts.get("bard", 0)) / n * 100.0
	var steady := float(counts.get(Townsfolk.STEADY, 0)) / n * 100.0
	_check(absf(thieves - 10.0) < 2.0 and absf(bards - 20.0) < 2.5 and absf(steady - 70.0) < 3.0,
		"over %d ids the shares match the weights (thief %.1f, bard %.1f, steady %.1f per 100)" % [n, thieves, bards, steady])
	_check(not counts.has("scoundrel"), "a type weighted 0 is never rolled")
	_check(not counts.has("wizard"), "a weighted type lore does not know, or has not agreed, is never rolled")
	var kinds: Array = counts.keys()
	kinds.sort()
	_check(kinds == ["bard", "steady", "thief"], "nothing else comes out of the roll %s" % [kinds])
	Townsfolk.use_rules({})


func _test_record() -> void:
	print("\n== economy's record keeps the type: rolled at founding, saved, rolled for a save from before ==")
	Townsfolk.use_rules({"type_weights": {"thief": 100.0}})
	_setup()
	_work.add_worker("w_thief", "Sly", ["cook"], TOWN)
	_work.add_worker("companion:jeff", "Wren", ["cook"], TOWN, "companion:jeff")
	_check(_work.worker("w_thief").get("type", "") == "thief", "a worker made with no type is rolled one (%s)" % _work.worker("w_thief").get("type", ""))
	_check(str(_work.worker("companion:jeff").get("type", "")).is_empty(), "a companion's record has none")
	var saved := _work.to_dict()
	Townsfolk.use_rules({"type_weights": {}})
	_setup(saved)
	_check(_work.worker("w_thief").get("type", "") == "thief", "the type is saved and loaded, not rolled again")
	var before := {"workers": {"w_old": {"name": "Old", "trades": ["smith"], "town": TOWN}}}
	Townsfolk.use_rules({"type_weights": {"thief": 100.0}})
	_setup(before)
	_check(_work.worker("w_old").get("type", "") == Townsfolk.roll_type("w_old") and _work.worker("w_old")["type"] == "thief",
		"a worker from a save before this is rolled on load, by id")
	Townsfolk.use_rules({})


func _test_lift() -> void:
	print("\n== the thief's lift: on the clock, with the chance, goods only, never the last, nothing away ==")
	var rules := {"type_weights": {}, "thief": {"every": DAY, "chance": 1.0, "leave": 2, "takes": ["cloth", "ore", "wood", "food"]}}
	Townsfolk.use_rules(rules)
	_setup()
	_work.add_worker("w_thief", "Sly", ["cook"], TOWN, "placeholder", "thief")
	_work.add_worker("w_plain", "Ann", ["cook"], TOWN, "placeholder", Townsfolk.STEADY)
	_stock.deposit(TOWN, "gold", 20, "test")
	_stock.deposit(TOWN, "food", 5, "test")
	_stock.deposit(TOWN, "ore", 2, "test")
	Townsfolk.tick(_work, _stock)
	_check(_stock.count(TOWN, "food") == 5 and _work.need_due("w_thief", Townsfolk.LIFT) == DAY, "the first tick sets the clock and takes nothing")
	_check(_work.need_due("w_plain", Townsfolk.LIFT) == 0, "a steady resident has no lift clock")
	_now = DAY - 1
	Townsfolk.tick(_work, _stock)
	_check(_stock.count(TOWN, "food") == 5, "nothing before it is due")
	_now = DAY
	Townsfolk.tick(_work, _stock)
	var lines := _stock.ledger(TOWN).filter(func(line: Dictionary) -> bool: return line["by"] == Townsfolk.MISSING)
	_check(_stock.count(TOWN, "food") == 4 and _stock.count(TOWN, "ore") == 2 and _stock.count(TOWN, "gold") == 20,
		"due, one food goes (ore is at leave, gold is never taken): food %d, ore %d, gold %d" % [_stock.count(TOWN, "food"), _stock.count(TOWN, "ore"), _stock.count(TOWN, "gold")])
	_check(lines.size() == 1 and lines[0]["what"] == "food" and lines[0]["count"] == -1 and lines[0]["from"] == "",
		"the ledger says only that something is missing %s" % [lines])
	_check(_work.need_due("w_thief", Townsfolk.LIFT) == 2 * DAY, "the clock is set a day on")
	_now = 2 * DAY
	_work.set_away("w_thief", true)
	Townsfolk.tick(_work, _stock)
	_check(_stock.count(TOWN, "food") == 4, "carried off (away), nothing goes")
	_work.set_away("w_thief", false)
	for day in range(3, 6):
		_now = day * DAY
		Townsfolk.tick(_work, _stock)
	_check(_stock.count(TOWN, "food") == 2, "the store is never taken below leave (food %d after three more days)" % _stock.count(TOWN, "food"))
	_now = 6 * DAY
	_stock.deposit(TOWN, "cloth", 3, "test")
	Townsfolk.tick(_work, _stock)
	_check(_stock.count(TOWN, "cloth") == 2 and _stock.count(TOWN, "food") == 2, "the dearest goods above leave go first (cloth before food)")
	rules["thief"]["chance"] = 0.0
	Townsfolk.use_rules(rules)
	_stock.deposit(TOWN, "cloth", 3, "test")
	_now = 7 * DAY
	Townsfolk.tick(_work, _stock)
	_check(_stock.count(TOWN, "cloth") == 5 and _work.need_due("w_thief", Townsfolk.LIFT) == 8 * DAY, "with no chance nothing goes, and the clock still moves on")
	rules["thief"]["chance"] = 0.5
	Townsfolk.use_rules(rules)
	var took := 0
	for day in range(8, 48):
		_now = day * DAY
		_stock.deposit(TOWN, "cloth", 1, "test")
		var had := _stock.count(TOWN, "cloth")
		Townsfolk.tick(_work, _stock)
		took += had - _stock.count(TOWN, "cloth")
	_check(took > 8 and took < 32, "at chance 0.5 about half the days lift (%d of 40)" % took)
	Townsfolk.use_rules({})


func _test_hidden() -> void:
	print("\n== never shown ==")
	_check(Resident.label_of("Sly", "cook") == "Sly [cook]", "the label is name and profession, no type")
	var body := Resident.new()
	body.worker_id = "w_thief"
	body.person = "Sly"
	body.trade = "cook"
	body.type = "thief"
	var words := body.card_words()
	_check(words.ends_with("Sly is a thief, and keeps it hidden."), "a thief's card tells its voice so, as a fact kept hidden")
	body.type = Townsfolk.STEADY
	_check(not "hidden" in body.card_words(), "a steady resident's card says nothing of a type")
	body.free()


## A town with a thief, a rich smith, a poor hauler and a guard; the thief's
## lift due now. Townsfolk reads the routines table for who stands where.
func _thief_town(with_merchant := false) -> void:
	Townsfolk.use_rules({"type_weights": {}, "thief": {"every": 100, "chance": 1.0, "leave": 2, "takes": ["cloth"],
		"gold_take": 3, "fence": 0.5, "margin": 0.4, "caught": 0.0, "caught_guard": 0.0, "lie_low_days": 30, "caught_season_days": 90, "caught_before_lying_low": 3}})
	_setup()
	Townsfolk.use_days({"default": {"stints": [{"from": 0, "to": 12, "at": "well"}, {"from": 12, "to": 24, "at": "well"}]}, "offset_hours": 0,
		"types": {"thief": [{"from": 0, "to": 12, "at": "well"}, {"from": 12, "to": 24, "at": "well"}]}, "gossip": {"every": 0}})
	Townsfolk._gossip_due.clear()
	Offers.ctx = {"production": _work, "memory": func(_town: String) -> Array: return _memory.duplicate(true),
		"set_memory": func(_town: String, log: Array) -> void: _memory = log.duplicate(true)}
	_memory = []
	# Types given outright (add_worker's last argument), the roll aside.
	Production.type_of = Callable()
	_work.add_worker("t-sly", "Sly", ["hauler"], TOWN, "placeholder", "thief")
	for each: Array in [["t-odo", "Odo", "smith"], ["t-nell", "Nell", "hauler"], ["t-gar", "Gar", "guard"]] + ([["t-mab", "Mab", "hauler", "merchant"]] if with_merchant else []):
		_work.add_worker(each[0], each[1], [each[2]], TOWN, "placeholder", each[3] if each.size() > 3 else "")
	Production.type_of = Townsfolk.roll_type
	_work.pay("t-odo", 40, "test")
	_work.pay("t-nell", 10, "test")
	_work.pay("t-gar", 30, "test")
	_stock.deposit(TOWN, "cloth", 5, "test")
	# Economy's line for a rich purse is its rules' (economy.json folk.rich_above): 25 here, whatever the file says.
	_economy = Economy.new({}, _stock, _work, func() -> int: return _now, {"folk": {"rich_above": 25}, "gold_floor": 0, "value": {"cloth": 10}}, func() -> Dictionary: return CATALOG)
	Townsfolk.tick(_work, _stock, _economy)  # Arms the lift's clock.
	_now += 100


var _memory: Array = []
var _economy: Economy


func _test_gold_lift() -> void:
	print("\n== the thief lifts gold from the richest purse above the line, never the poor or the coffer (decision 461) ==")
	if not _work_has("lift_gold"):
		_check(true, "(economy's lift_gold is not here yet: skipped)")
		return
	_thief_town()
	var coffer := _stock.count(TOWN, "gold")
	Townsfolk.tick(_work, _stock, _economy)
	_check(_work.worker("t-odo")["purse"] == 37 and _work.worker("t-sly")["purse"] == 3, "3 gold moved from Odo (40, the richest) to Sly (%d, %d)" % [_work.worker("t-odo")["purse"], _work.worker("t-sly")["purse"]])
	_check(_work.worker("t-nell")["purse"] == 10 and _work.worker("t-gar")["purse"] == 30 and _stock.count(TOWN, "gold") == coffer, "Nell, Gar and the coffer untouched")
	_check(_stock.count(TOWN, "cloth") == 5, "gold found: no goods lifted that day")
	var facts: Array = Townsfolk.card_of(_work, "t-odo").get("facts", [])
	_check(not facts.is_empty() and str(facts.back()["text"]) == "Odo missed 3 gold from his purse" or str(facts.back()["text"]).begins_with("Odo missed 3 gold"), "Odo's card: a loss with no name (%s)" % (facts.back()["text"] if not facts.is_empty() else ""))
	_work.spend("t-odo", 20, "test")
	_work.note_meal("t-gar", "dole")
	_now += 100
	Townsfolk.tick(_work, _stock, _economy)
	_check(_work.worker("t-gar")["purse"] == 30 and _work.worker("t-odo")["purse"] == 17 and _stock.count(TOWN, "cloth") == 4,
		"nobody rich above 25 who is not on the dole: the store is lifted instead (cloth 5 -> %d)" % _stock.count(TOWN, "cloth"))


func _test_fence_and_catch() -> void:
	print("\n== fenced through a merchant; caught by the victim or a guard ==")
	if not _work_has("lift_gold") or not _work_has("return_gold"):
		_check(true, "(economy's hooks are not here yet: skipped)")
		return
	_thief_town(true)
	var economy := _economy
	if not economy.has_method("fence"):
		_check(true, "(economy's fence is not here yet: skipped)")
		return
	_work.spend("t-odo", 40, "test")
	_work.spend("t-gar", 30, "test")
	_stock.deposit(TOWN, "gold", 50, "test")
	var coffer := _stock.count(TOWN, "gold")
	Townsfolk.tick(_work, _stock, economy)
	var mab: int = _work.worker("t-mab")["purse"]
	var sly: int = _work.worker("t-sly")["purse"]
	var price := coffer - _stock.count(TOWN, "gold")  # Economy's raw price (its glut factor) times the fence's half.
	_check(_stock.count(TOWN, "cloth") == 5 and price > 0 and mab == roundi(price * 0.4) and sly == price - mab,
		"the cloth comes back through Mab at half its price, the coffer pays, Mab keeps 0.4 of it and Sly the rest (coffer %d -> %d; Mab %d, Sly %d)" % [coffer, _stock.count(TOWN, "gold"), mab, sly])
	_check(coffer - _stock.count(TOWN, "gold") == mab + sly, "gold conserved: what the coffer paid is what the two hold")
	# Caught every time: the victim at the well with him.
	Townsfolk.use_rules({"type_weights": {}, "thief": {"every": 100, "chance": 1.0, "leave": 2, "takes": ["cloth"],
		"gold_take": 3, "fence": 0.5, "margin": 0.4, "caught": 1.0, "caught_guard": 0.0, "lie_low_days": 30, "caught_season_days": 90, "caught_before_lying_low": 3}})
	_work.pay("t-odo", 40, "test")
	var sly_before: int = _work.worker("t-sly")["purse"]
	_now += 100
	Townsfolk.tick(_work, _stock, economy)
	_check(_work.worker("t-odo")["purse"] == 40 and _work.worker("t-sly")["purse"] == sly_before, "caught by Odo at the well: the gold is back")
	_check(str(Townsfolk.card_of(_work, "t-odo")["facts"].back()["text"]) == "Odo caught Sly with a hand in Odo's purse." and "t-sly" in Townsfolk.card_of(_work, "t-odo")["grudge"],
		"Odo's card: the catch, and a grudge against Sly")
	_check(str(Townsfolk.card_of(_work, "t-sly")["facts"].back()["text"]).begins_with("Sly was caught with a hand in Odo's purse"), "Sly's card: caught")
	_check(_memory.size() == 1 and _memory[0]["dispute"] == true and _memory[0]["said_by"] == "t-odo" and _memory[0]["tier"] == TownMemory.CANDIDATE
		and _memory[0]["pair"] == ["t-odo", "t-sly"], "a dispute for the lawspeaker in the town's log, a candidate at once, the pair named (486): %s" % [_memory])
	for i in 2:
		_now += 100
		Townsfolk.tick(_work, _stock, economy)
	var card := Townsfolk.card_of(_work, "t-sly")
	_check(int(card.get("lie_low_until", 0)) > _now and card.get("caught", []).is_empty(), "caught thrice in a season: he lies low")
	_work.pay("t-odo", 10, "test")
	_now += 100
	Townsfolk.tick(_work, _stock, economy)
	_check(_work.worker("t-odo")["purse"] == 50, "and lifts nothing while he does")


func _test_strays() -> void:
	print("\n== someone loses their way beyond the walls, and comes home on their own (decision 487) ==")
	Townsfolk.use_rules({"type_weights": {}, "thief": {"every": 0}, "strays": {"every": 100, "chance": 1.0, "days": 3, "far": 24, "trades": ["hauler"]}})
	_setup()
	Townsfolk._stray_due.clear()
	Production.type_of = Callable()
	_work.add_worker("s-nell", "Nell", ["hauler"], TOWN, "placeholder")
	_work.add_worker("s-odo", "Odo", ["smith"], TOWN, "placeholder")
	_work.add_worker("s-reeve", "Reeve", ["hauler"], TOWN, "appointed")
	_work.add_worker("s-mab", "Mab", ["hauler"], TOWN, "placeholder", "merchant")
	Production.type_of = Townsfolk.roll_type
	Townsfolk.tick(_work, _stock)  # Arms the clock.
	_now += 100
	Townsfolk.tick(_work, _stock)
	var lost := Townsfolk.strayed_of(_work, TOWN)
	_check(lost.keys() == ["s-nell"] and _work.worker("s-nell")["away"] == true, "the one hauler who is neither an official nor the merchant is lost, and away (%s)" % [lost])
	_check(str(Townsfolk.card_of(_work, "s-nell")["facts"].back()["text"]).ends_with("lost her way beyond the walls.") or str(Townsfolk.card_of(_work, "s-nell")["facts"].back()["text"]).ends_with("way beyond the walls."), "her card says so")
	_check(Townsfolk.stray_cell(_work, "s-nell") == null, "where she stands is Main's to choose: nothing yet")
	Townsfolk.set_stray_cell(_work, "s-nell", Vector2i(40, 7))
	_check(Townsfolk.stray_cell(_work, "s-nell") == Vector2i(40, 7), "and kept on the card once chosen")
	_now += 100
	Townsfolk.tick(_work, _stock)
	_check(Townsfolk.strayed_of(_work, TOWN).size() == 1, "one at a time per town")
	# Her kin's plea, taken by a player: it closes unpaid when she comes home on her own (the soak had it lapse against the player).
	var kin := Townsfolk.card_of(_work, "s-odo")
	kin["asks"] = [{"id": "o|plea|walk:s-nell", "kind": "commission", "sub": "escort", "by": "p1", "by_name": "Jeff", "step": _now, "town": TOWN, "worker": "s-odo",
		"title": "Walk Nell home", "words": "", "what": {"stray": "s-nell", "name": "Nell", "sub": "escort"}}]
	_work.set_card("s-odo", kin)
	var done: Array = []
	Offers.ctx = {"production": _work, "pay": func() -> Dictionary: return {}, "pay_commission": func(_p: String, _t: String, g: int) -> int: return g,
		"done": func(player_id: String, ask: Dictionary, line: String, paid: int) -> void: done.append([player_id, ask, line, paid])}
	_now += 3 * DayNight.day_steps
	Townsfolk.tick(_work, _stock)
	_check(Townsfolk.strayed_of(_work, TOWN).is_empty() and _work.worker("s-nell")["away"] == false, "after three days she found her own way home: back, not away")
	_check(done.size() == 1 and done[0][3] == 0 and str(done[0][2]) == "Nell came home on her own." and Townsfolk.card_of(_work, "s-odo")["asks"].is_empty(),
		"her kin's plea closed unpaid, no lapse against the player: %s" % [done])
	_check(Standing.score(Townsfolk.card_of(_work, "s-odo"), "p1") == 0, "and Odo thinks no worse of Jeff for it")
	Offers.ctx = {}
	_check(str(Townsfolk.card_of(_work, "s-nell")["facts"].back()["text"]).contains("found") and str(Townsfolk.card_of(_work, "s-nell")["facts"].back()["text"]).contains("own way home"),
		"her card: %s" % [Townsfolk.card_of(_work, "s-nell")["facts"].back()["text"]])
	Townsfolk._stray_due.clear()


var _memory2: Array = []


func _test_scoundrel() -> void:
	print("\n== the scoundrel: short measures on what he makes, a debt ridden to the cap and talked of (decision 492) ==")
	Townsfolk.use_rules({"type_weights": {}, "thief": {"every": 0}, "strays": {"every": 0}, "scoundrel": {"short": 1.0, "weight": 0.6}})
	_setup()
	Townsfolk.watch(_work, null)
	Production.type_of = Callable()
	_work.add_worker("c-sly", "Sly", ["cook"], TOWN, "placeholder", "scoundrel")
	_work.add_worker("c-odo", "Odo", ["smith"], TOWN, "placeholder")
	_work.add_worker("c-ald", "Aldous", ["priest"], TOWN, "appointed")
	Production.type_of = Townsfolk.roll_type
	_work.pay("c-odo", 40, "test")
	var book: ItemBook = _stock.book
	if book.has_method("make_short") and Callable(Items, "measured").is_valid():
		var sack := book.mint("food_sack", "made", "Sly")
		var knife := book.mint("knife", "made", "Sly")
		_check(Townsfolk.made_short(_work, TOWN, "c-sly", sack, book), "a food sack he made comes out short (chance 1)")
		_check(not Townsfolk.made_short(_work, TOWN, "c-sly", knife, book), "a knife never does: no tiers on gear")
		_check(not Townsfolk.made_short(_work, TOWN, "c-odo", book.mint("food_sack", "made", "Odo"), book), "a steady cook's sack is whole")
	else:
		_check(true, "(items' make_short is not here yet: the short measure is skipped)")
	# The debt: at the cap, the official learns it and his card too; once per climb.
	_memory2 = []
	Offers.ctx = {"production": _work, "memory": func(_town: String) -> Array: return _memory2.duplicate(true),
		"set_memory": func(_town: String, log: Array) -> void: _memory2 = log.duplicate(true),
		"lawspeaker_of": func(_town: String) -> String: return "c-ald", "model": func() -> String: return "claude-haiku-5-5"}
	var cap := Townsfolk.bank_cap()
	_work.set_loan("c-sly", 10.0, false)
	_check(not Townsfolk.card_of(_work, "c-ald")["facts"].any(func(f: Dictionary) -> bool: return str(f["text"]).contains("owes the town all")), "a small debt is nobody's business")
	_work.set_loan("c-sly", float(cap), false)
	_check(str(Townsfolk.card_of(_work, "c-ald")["facts"].back()["text"]) == "Sly owes the town all it will lend and pays nothing back.", "at the cap the priest, the town's official, knows it as a thing seen")
	_check(Townsfolk.card_of(_work, "c-sly")["facts"].any(func(f: Dictionary) -> bool: return str(f["text"]).begins_with("Sly owes the town %d gold" % cap)), "and his own card says what he owes")
	_check(_memory2.size() == 1 and _memory2[0]["dispute"] == true and _memory2[0]["tier"] == TownMemory.CANDIDATE and _memory2[0]["said_by"] == "c-ald" and not _memory2[0].has("pair"),
		"with rulings on, a dispute before the lawspeaker, the town's quarrel: %s" % [_memory2])
	_work.set_loan("c-sly", float(cap) - 0.5, true)
	_check(Townsfolk.card_of(_work, "c-ald")["facts"].filter(func(f: Dictionary) -> bool: return str(f["text"]).contains("owes the town all")).size() == 1, "said once per climb")
	_work.set_loan("c-sly", float(cap) * 0.4, true)
	_work.set_loan("c-sly", float(cap), false)
	_check(_memory2.size() == 1, "worked down and up again: the same words are the same entry")
	# Rulings off: the talk, no dispute.
	Offers.ctx["model"] = func() -> String: return "off"
	_memory2 = []
	Production.type_of = Callable()
	_work.add_worker("c-nix", "Nix", ["cook"], TOWN, "placeholder", "scoundrel")
	Production.type_of = Townsfolk.roll_type
	_work.set_loan("c-nix", float(cap), false)
	_check(str(Townsfolk.card_of(_work, "c-ald")["facts"].back()["text"]) == "Nix owes the town all it will lend and pays nothing back." and _memory2.is_empty(),
		"with the lawspeaker off: the official knows, nothing before him")
	Offers.ctx = {}


var _died: Array = []
var _her_sick := {}


func _test_sickness() -> void:
	print("\n== sickness: to bed, its course, the old of the town's own may die (never a rescued one), treated it breaks that night (decision 501) ==")
	Townsfolk.use_rules({"type_weights": {}, "thief": {"every": 0}, "strays": {"every": 0},
		"sick": {"chance": 1.0, "winter": 1, "hungry": 1, "old": 1, "days": 2, "death_old": 1.0, "visit_hours": 2, "kinds": ["a fever"]}})
	_setup()
	Townsfolk._sick_due.clear()
	Production.type_of = Callable()
	_work.add_worker("k-ada", "Ada", ["cook"], TOWN, "placeholder")
	_work.add_worker("k-bram", "Bram", ["smith"], TOWN, "placeholder")
	_work.add_worker("k-ren", "Ren", ["hauler"], TOWN, "rescued:p1")
	Production.type_of = Townsfolk.roll_type
	for id: String in ["k-ada", "k-bram", "k-ren"]:
		var c := Townsfolk.card_of(_work, id)
		c["kin"] = {}
		c["grudge"] = []
		_work.set_card(id, c)
	var ada := Townsfolk.card_of(_work, "k-ada")
	ada["kin"] = {"k-bram": "sister or brother"}
	ada["look"]["age"] = "old"
	ada["traits"]["pronoun"] = "she"
	_work.set_card("k-ada", ada)
	var ren := Townsfolk.card_of(_work, "k-ren")
	ren["look"]["age"] = "old"
	ren["traits"]["pronoun"] = "he"
	_work.set_card("k-ren", ren)
	var bram := Townsfolk.card_of(_work, "k-bram")
	bram["traits"]["pronoun"] = "he"
	_work.set_card("k-bram", bram)
	_died = []
	_her_sick = {}
	var done: Array = []
	Offers.ctx = {"production": _work, "pay": func() -> Dictionary: return {"healing": 6}, "pay_commission": func(_p: String, _t: String, g: int) -> int: return g,
		"done": func(player_id: String, ask: Dictionary, line: String, paid: int) -> void: done.append([player_id, ask, line, paid]),
		"died": func(town: String, id: String, why: String) -> bool:
			_died.append([town, id, why])
			_work.set_away(id, true)  # Economy's Towns.died takes them out of the town.
			return true,
		"lawspeaker_of": func(_t: String) -> String: return "", "model": func() -> String: return "off",
		"companion_sick": func(_id: String) -> Dictionary: return _her_sick.duplicate(true),
		"set_companion_sick": func(_id: String, record: Dictionary) -> void: _her_sick = record.duplicate(true)}
	var day := DayNight.day_steps
	_check(Townsfolk.sick_days() == 2, "the untreated length reads from the rule (%d)" % Townsfolk.sick_days())
	Townsfolk.sicken(_work)
	_check(Townsfolk.is_sick(_work, "k-ada") and not Townsfolk.is_sick(_work, "k-bram"), "one new case a town a day: Ada, the first by id (chance 1)")
	_check(str(Townsfolk.card_of(_work, "k-ada")["facts"].back()["text"]) == "Ada took to her bed with a fever." and str(Townsfolk.card_of(_work, "k-bram")["facts"].back()["text"]).begins_with("Ada, his sister, lies sick at home"),
		"her card and her brother's say so: %s" % [Townsfolk.card_of(_work, "k-bram")["facts"].back()["text"]])
	if _work.has_method("set_sick"):
		_check(_work.worker("k-ada").get("sick", false) == true, "economy counts her sick")
	Townsfolk.sicken(_work)
	_check(not Townsfolk.is_sick(_work, "k-bram"), "not twice the same day")
	_now += day
	Townsfolk.sicken(_work)
	_check(Townsfolk.is_sick(_work, "k-ada") and Townsfolk.is_sick(_work, "k-bram"), "the next day Ada is still abed and Bram falls sick")
	_now += day
	Townsfolk.sicken(_work)
	_check(not Townsfolk.is_sick(_work, "k-ada") and _died == [[TOWN, "k-ada", "a fever"]], "after two days untreated, Ada, old and the town's own, dies (death_old 1): %s" % [_died])
	_check(str(Townsfolk.card_of(_work, "k-bram")["facts"].back()["text"]) == "Ada died of a fever.", "her brother's card")
	_check(Townsfolk.treat(_work, "k-bram", "Jeff", "a remedy", "p1") and int(Townsfolk.sickness_of(_work, "k-bram")["treated"]) >= 0, "Bram is treated with a remedy")
	_check(not Townsfolk.treat(_work, "k-bram", "Jeff", "a remedy", "p1"), "and not twice")
	_now += day
	Townsfolk.sicken(_work)
	_check(not Townsfolk.is_sick(_work, "k-bram") and str(Townsfolk.card_of(_work, "k-bram")["facts"].back()["text"]) == "Bram is on his feet again." and _died.size() == 1,
		"the next morning he is on his feet; nobody else died")
	# The guard: Ren, old, rescued by a player, never dies of it this step.
	Townsfolk._set_sickness(_work, "k-ren", {"since": Townsfolk.day_of(_now), "kind": "a fever", "treated": -1, "cured_by": ""})
	_now += 3 * day
	Townsfolk.sicken(_work)
	_check(not Townsfolk.is_sick(_work, "k-ren") and _died.size() == 1 and str(Townsfolk.card_of(_work, "k-ren")["facts"].back()["text"]).contains("on his feet again after a fever, thinner"),
		"a rescued captive, old, gets over it thinner: the death roll never touches a named arrival")
	# A companion resting in town rolls too: her record goes to her player's card, never to a townsfolk card.
	Production.type_of = Callable()
	_work.add_worker("companion:p9", "Isolde", ["hauler"], TOWN, "companion:p9")
	Production.type_of = Townsfolk.roll_type
	_now += day
	Townsfolk.sicken(_work)
	_check(not _her_sick.is_empty() and _her_sick.get("kind") == "a fever" and Townsfolk.is_sick(_work, "companion:p9"), "Isolde, resting in town, falls sick and it is kept on her player's card: %s" % [_her_sick])
	_now += 2 * day
	Townsfolk.sicken(_work)
	_check(_her_sick.is_empty() and _died.size() == 1, "she gets over it on her own; a companion never dies of it")
	Offers.ctx = {}
	Townsfolk._sick_due.clear()


func _work_has(method: String) -> bool:
	return _work != null and _work.has_method(method) or Production.new({}, Stockpile.new({}, func() -> int: return 0, ItemBook.new(func() -> int: return 0)), null, func() -> int: return 0, {}, func() -> Dictionary: return {}).has_method(method)



## Maps' TradeRoutes, as the road's news needs it: a route's ends and its eta.
class RoadStub extends RefCounted:
	var town := ""
	func route(_id: String) -> Dictionary:
		return {"from": town, "to": "market:castle", "areas": ["wilds", "hills", "castle"]}
	func eta(_id: String) -> int:
		return 360  # x 300 steps x 2 ways / 54000 a day = 4 days.


var _road_memory: Array = []
var _road_news_got: Array = []

## The road's news (decision 504, npc's side): what a wagon's people, their
## kin and the officials say of it, the raid as a candidate memory.
func _test_road_news() -> void:
	print("\n== the road's news: a wagon out, struck, home and lost, as card facts and the town's memory (decision 504, npc's side) ==")
	Townsfolk.use_rules({"type_weights": {}, "thief": {"every": 0}, "strays": {"every": 0}, "sick": {"chance": 0.0}})
	_setup()
	Townsfolk._wagons.clear()
	Production.type_of = Callable()
	_work.add_worker("w-ren", "Ren", ["hauler"], TOWN, "placeholder")
	_work.add_worker("w-oda", "Oda", ["tanner"], TOWN, "placeholder")
	_work.add_worker("w-bram", "Bram", ["smith"], TOWN, "placeholder")
	_work.add_worker("w-ada", "Ada", ["cook"], TOWN, "placeholder")
	_work.add_worker("w-law", "Ulf", ["lawspeaker"], TOWN, "appointed")
	Production.type_of = Townsfolk.roll_type
	for id: String in ["w-ren", "w-oda", "w-bram", "w-ada", "w-law"]:
		var c := Townsfolk.card_of(_work, id)
		c["kin"] = {}
		c["grudge"] = []
		c["traits"]["pronoun"] = "he"
		_work.set_card(id, c)
	var ren := Townsfolk.card_of(_work, "w-ren")
	ren["kin"] = {"w-bram": "sister or brother"}
	_work.set_card("w-ren", ren)
	var bram := Townsfolk.card_of(_work, "w-bram")
	bram["kin"] = {"w-ren": "sister or brother"}
	_work.set_card("w-bram", bram)
	_road_memory = []
	Offers.ctx = {"production": _work, "memory": func(_t: String) -> Array: return _road_memory,
		"set_memory": func(_t: String, log: Array) -> void: _road_memory = log,
		"lawspeaker_of": func(_t: String) -> String: return "w-law", "model": func() -> String: return "off",
		"holder_of": func(_place: String) -> String: return "blood_rot", "value_of": func(_kind: String) -> int: return 2,
		"town_name": func(_t: String) -> String: return "Tf",
		"players_in": func(_area: String) -> Array: return ["p-one"],
		"road_news": func(_t: String, news: Dictionary) -> void: _road_news_got.append(news)}
	_road_news_got = []
	var road := RoadStub.new()
	road.town = TOWN
	var raiders := ResidentCard.faction_name("blood_rot")
	var last := func(id: String) -> String: return str(Townsfolk.card_of(_work, id).get("facts", [{}]).back().get("text", ""))
	var count := func(id: String) -> int: return Townsfolk.card_of(_work, id).get("facts", []).size()
	var ada_facts: int = count.call("w-ada")
	for who: String in ["w-ren", "w-oda"]:
		_work.set_away(who, true)  # Economy's: away on the road.
	Townsfolk.wagon_left(_work, road, "c1", "r1", {"items": [], "goods": {"leather": 10, "hide": 4}, "members": ["w-ren", "w-oda"]})
	_check(last.call("w-ren") == "Ren went with the wagon to the castle market, a trip of about four days there and back.", "the traveller's card: %s" % last.call("w-ren"))
	_check(last.call("w-bram") == "Ren, his brother, has gone to the castle market with the wagon, back in about four days.", "his brother's: %s" % last.call("w-bram"))
	_check(last.call("w-law") == "Ren and Oda left with the wagon for the castle market, due back in about four days.", "the official's: %s" % last.call("w-law"))
	_check(count.call("w-ada") == ada_facts, "nobody else is told: the rest hear it by gossip")
	Townsfolk.wagon_arrived(_work, road, "c1", "r1", "market:castle", {"items": [], "goods": {"leather": 10, "hide": 4}, "members": ["w-ren", "w-oda"]})
	_check(count.call("w-ada") == ada_facts and last.call("w-ren").begins_with("Ren went"), "at the market nothing is said at home")
	Townsfolk.wagon_sold("c1", 40, 8)  # Economy's optional signal: 40 for goods worth 28.
	Townsfolk.wagon_raided(_work, road, "c1", "r1", "camp:x", {"goods": {"food": 3}, "members": ["w-oda"]})
	_check(last.call("w-oda") == "Oda was carried off from the wagon by %s on the road to the castle market." % raiders, "the taken one's card: %s" % last.call("w-oda"))
	var ren_facts: Array = Townsfolk.card_of(_work, "w-ren")["facts"].map(func(f: Dictionary) -> String: return str(f["text"]))
	_check("Ren saw Oda carried off from the wagon by %s on the road to the castle market." % raiders in ren_facts and "%s took the wagon's food on the road to the castle market." % Townsfolk._upper_first(raiders) in ren_facts,
		"the survivor saw it, and the food go: %s" % [ren_facts.slice(-2)])
	var candidates: Array = _road_memory.filter(func(e: Dictionary) -> bool: return str(e.get("tier", "")) == TownMemory.CANDIDATE)
	_check(candidates.size() == 1 and str(candidates[0]["text"]) == "%s struck the town's wagon on the road to the castle market and carried off Oda" % Townsfolk._upper_first(raiders) and str(candidates[0]["said_by"]) == "w-ren",
		"the town's memory holds the raid as a candidate, by the survivor: %s" % [candidates.map(func(e: Dictionary) -> String: return str(e["text"]))])
	# The road's news to companions (decision 551, npc's side): once per event, after the memory line.
	_check(_road_news_got.size() == 1 and str(_road_news_got[0]["kind"]) == "raided" and str(_road_news_got[0]["camp"]) == "camp:x" and str(_road_news_got[0]["far"]) == "market:castle"
		and Array(_road_news_got[0]["members"]) == ["w-ren", "w-oda"] and Array(_road_news_got[0]["areas"]) == ["wilds", "hills", "castle"] and Array(_road_news_got[0]["told"]) == ["p-one"]
		and str(_road_news_got[0]["text"]) == str(candidates[0]["text"]) and str(_road_news_got[0]["goods"]) == Townsfolk._goods_words({"food": 3}) and int(_road_news_got[0]["day"]) == Townsfolk.day_of(_work.now()),
		"the raid's news: kind, camp, far end, crew, the route's areas, who was in town, the memory's text, the food taken: %s" % [_road_news_got])
	# The way home: a new id from the market with the same people, then home.
	Townsfolk.wagon_left(_work, road, "c2", "r1", {"items": [], "goods": {"cloth": 6}, "members": ["w-ren"]})
	_check(not Townsfolk._wagons.has("c1") and Townsfolk._wagons.has("c2") and last.call("w-law").begins_with("Ren and Oda left"), "the way home moves the record to the new id, nothing said")
	_work.set_away("w-ren", false)
	Townsfolk.wagon_arrived(_work, road, "c2", "r1", TOWN, {"items": [], "goods": {"cloth": 6}, "members": ["w-ren"]})
	var took := Townsfolk._goods_words({"leather": 10, "hide": 4})
	var back := Townsfolk._goods_words({"cloth": 6})
	_check(last.call("w-ren") == "Ren came home from the castle market: the wagon took %s, and brought back %s. It sold well." % [took, back], "home, what went and came back and how it sold: %s" % last.call("w-ren"))
	_check(last.call("w-ada") == "Ada saw Ren come home from the castle market with the wagon." and last.call("w-bram") == "Bram saw Ren come home from the castle market with the wagon.", "the town saw him come: %s" % last.call("w-ada"))
	_check(last.call("w-oda").begins_with("Oda was carried off"), "the captive hears nothing")
	var beliefs: Array = _road_memory.filter(func(e: Dictionary) -> bool: return str(e.get("tier", "")) == TownMemory.BELIEF)
	_check(beliefs.size() == 1 and str(beliefs[0]["text"]) == "Ren's wagon came home from the castle market with %s" % back, "a small memory of the homecoming, a belief: %s" % [beliefs.map(func(e: Dictionary) -> String: return str(e["text"]))])
	_check(_road_news_got.size() == 2 and str(_road_news_got[1]["kind"]) == "arrived" and str(_road_news_got[1]["goods"]) == back and str(_road_news_got[1]["camp"]).is_empty() and str(_road_news_got[1]["text"]) == str(beliefs[0]["text"]),
		"the homecoming's news, nothing at the market: %s" % [_road_news_got[1]["kind"]])
	# Lost: the road closed, a word on the officials' cards; taken, a candidate by the lawspeaker.
	Townsfolk.wagon_left(_work, road, "c3", "r1", {"items": [], "goods": {}, "members": ["w-bram"]})
	Townsfolk.wagon_lost(_work, road, "c3", "r1", "no way")
	_check(last.call("w-law") == "The wagon to the castle market turned back: the road is closed." and last.call("w-ada").begins_with("Ada saw Ren"), "no way: the official's word, nobody else's: %s" % last.call("w-law"))
	Townsfolk.wagon_left(_work, road, "c4", "r1", {"items": [], "goods": {"food": 5}, "members": ["w-ada"]})
	Townsfolk.wagon_raided(_work, road, "c4", "r1", "camp:x", {"goods": {"food": 5}, "members": ["w-ada"]})
	Townsfolk.wagon_lost(_work, road, "c4", "r1", "taken")
	candidates = _road_memory.filter(func(e: Dictionary) -> bool: return str(e.get("tier", "")) == TownMemory.CANDIDATE)
	_check(candidates.size() == 3 and str(candidates.back()["text"]) == "The wagon to the castle market was lost on the road to %s, and Ada with it" % raiders and str(candidates.back()["said_by"]) == "w-law",
		"taken: the lawspeaker's candidate: %s" % [candidates.map(func(e: Dictionary) -> String: return str(e["text"]))])
	_check(not Townsfolk._wagons.has("c4") and not Townsfolk._wagons.has("c3"), "the records are let go")
	_check(_road_news_got.size() == 4 and str(_road_news_got[2]["kind"]) == "raided" and str(_road_news_got[3]["kind"]) == "lost" and Array(_road_news_got[3]["members"]) == ["w-ada"] and str(_road_news_got[3]["text"]) == str(candidates.back()["text"]),
		"the road closed is no news; the loss is, with the crew lost: %s" % [_road_news_got.slice(2).map(func(n: Dictionary) -> String: return str(n["kind"]))])
	Townsfolk._wagons.clear()
	Offers.ctx = {}

func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
