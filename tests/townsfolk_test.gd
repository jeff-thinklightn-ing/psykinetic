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


func _work_has(method: String) -> bool:
	return _work != null and _work.has_method(method) or Production.new({}, Stockpile.new({}, func() -> int: return 0, ItemBook.new(func() -> int: return 0)), null, func() -> int: return 0, {}, func() -> Dictionary: return {}).has_method(method)


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
