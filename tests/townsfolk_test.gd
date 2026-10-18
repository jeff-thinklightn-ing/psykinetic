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
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
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


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
