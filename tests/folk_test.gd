extends Node
## Residents' trade and a town's starting gold (decision 353, amended), on a
## clock of its own with the real rules (levels/economy.json) and a test
## catalog: a town is founded once, its start_gold spread evenly over its
## residents (none to the treasury, none to those who come later); residents buy meals from the shop
## (the maker paid, the sale tax to the treasury, keep_in_shop left for
## players), else the store's food, else the town feeds them (the dole,
## which makes food the town's first want), else they go hungry; they pay
## the carpenter and the smith for services and the inn for a bed, never
## into debt; a rich one spends sooner; each trade is a ledger line and the
## worker's last_trade; gold only moves; a made thing's materials are the
## treasury's; and over three game days the treasury, filled by sales,
## pays the official jobs (a guard, haulers) and the walls it orders, every
## purse bounded and everyone fed. Reads the repo's levels, never the shared overlay.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const TOWN := "ft/store"
const CATALOG := {
	"meal": {"id": "meal", "tags": ["food"], "made": {"by": "cook", "from": {"food": 2}, "steps": 600}},
}
const DAY := 54000

var _failures := 0
var _now := 0
var _rules := {}
var _stock: Stockpile
var _work: Production
var _economy: Economy
var _told: Array[Array] = []
var _inn := true


func _ready() -> void:
	World.set_process(false)
	_rules = Production.read_rules()
	_test_founded()
	_test_meals()
	_test_services()
	_test_days()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _setup() -> void:
	_now = 0
	_told.clear()
	var clock := func() -> int: return _now
	var cat := func() -> Dictionary: return CATALOG
	_stock = Stockpile.new({}, clock, ItemBook.new(clock))
	_work = Production.new({}, _stock, null, clock, _rules, cat)
	_economy = Economy.new({}, _stock, _work, clock, _rules, cat)
	_economy.building_stands = func(_town: String, kind: String) -> bool: return kind == "inn" and _inn
	_economy.dole_changed.connect(func(town: String, count: int) -> void: _told.append([town, count]))


func _meal(maker := "c1") -> int:
	var uid := _stock.book.mint("meal", "made", "test")
	_stock.stock_shop(TOWN, uid, "test", maker)
	return uid


## A maker's share of a meal sold for [param cost]: past its materials,
## less the sale tax.
func _labour(cost: int) -> int:
	var rest := cost - mini(_economy.materials("meal"), cost)
	return rest - int(floor(rest * float(_rules["tax"]["sale"])))


func _gold() -> int:
	var total := _stock.count(TOWN, "gold")
	for id in _work.worker_ids():
		total += int(_work.worker(id)["purse"])
	return total


func _test_founded() -> void:
	print("\n== a town is founded with its starting gold, once ==")
	var overlay := Level.overlay_dir
	Level.overlay_dir = preload("res://tests/test_ports.gd").scratch("folk_test/no_overlay/")
	var world_map := WorldMap.build()
	Level.overlay_dir = overlay
	var stock := Stockpile.new({}, Callable(), ItemBook.new(Callable()))
	var work := Production.new({}, stock, null, Callable(), _rules)
	var towns := Towns.new({}, work, _rules)
	towns.seed_from(world_map)
	var gold := int(_rules["start_gold"])
	_check(gold == 150 and stock.count("wilds/store", "gold") == 0 and towns.to_dict()["wilds/store"]["to_spread"] == gold,
		"founded: the treasury starts empty, its %d gold waits for residents (%s)" % [gold, towns.to_dict()["wilds/store"]["to_spread"]])
	for each in [["r1", "Odo", "smith"], ["r2", "Mags", "cook"], ["r3", "Ash", "hauler"], ["r4", "Bea", "hauler"]]:
		towns.note_rescue("wilds/store", each[0], each[1], each[2])
	towns.tick()
	var purses: Array = ["r1", "r2", "r3", "r4"].map(func(id: String) -> int: return int(work.worker(id)["purse"]))
	_check(purses == [gold / 4 + 1, gold / 4 + 1, gold / 4, gold / 4] and stock.count("wilds/store", "gold") == 0,
		"spread evenly over the residents, the first by id a coin more (%s), none to the treasury" % [purses])
	towns.note_rescue("wilds/store", "r5", "Cole", "hauler")
	towns.tick()
	towns.seed_from(world_map)
	_check(int(work.worker("r5")["purse"]) == 0 and int(work.worker("r1")["purse"]) == gold / 4 + 1,
		"one who comes later gets none; seeded again, nothing more")
	var again := Towns.new(towns.to_dict(), work, _rules)
	again.seed_from(world_map)
	again.tick()
	_check(int(work.worker("r1")["purse"]) == gold / 4 + 1, "after a restart: nothing more (founded is saved)")
	var old := towns.to_dict()
	old["wilds/store"].erase("founded")
	old["wilds/store"].erase("to_spread")
	var stock_old := Stockpile.new({}, Callable(), ItemBook.new(Callable()))
	var older := Towns.new(old, Production.new({}, stock_old, null, Callable(), _rules), _rules)
	older.seed_from(world_map)
	_check(older.to_dict()["wilds/store"]["to_spread"] == gold, "a save from before it is founded once")


func _test_meals() -> void:
	print("\n== meals: the shop, the store, the dole, hunger ==")
	_setup()
	_stock.deposit(TOWN, "food", 3)
	_stock.deposit(TOWN, "gold", 30)
	_work.add_worker("c1", "Mags", ["cook"], TOWN)
	_work.add_worker("h1", "Ash", ["hauler"], TOWN)
	_work.add_worker("p1", "Pell", ["carpenter"], TOWN)
	_work.add_worker("s1", "Odo", ["smith"], TOWN)
	_work.pay("c1", 10)
	_work.pay("h1", 100)
	_work.pay("s1", 10)
	for i in 3:
		_meal()
	var meal_every := int(_rules["folk"]["needs"]["meal"]["every"])
	_economy.tick()
	_check(_work.need_due("h1", "meal") == meal_every, "a meal first falls due one 'every' on (%d)" % _work.need_due("h1", "meal"))
	var before := _gold()
	var price := int(_economy.goods(TOWN)[0]["price"])
	_now = meal_every
	_economy.tick()
	_check(_gold() == before, "gold only moved (%d, %d)" % [before, _gold()])
	_check(_stock.shop(TOWN).size() == 1, "two meals bought; keep_in_shop leaves one for players (%d)" % _stock.shop(TOWN).size())
	var mags := _work.worker("c1")
	var ash := _work.worker("h1")
	var second := int(ash["last_trade"].get("gold", 0))
	_check(_economy.materials("meal") == 2, "a meal's materials are worth 2 (2 food)")
	_check(mags["fed"] == "bought" and int(mags["purse"]) == 10 - price + _labour(price) + _labour(second),
		"Mags (cook) bought her own meal and was paid her labour for both: the materials and the tax to the treasury (%d gold, %d then %d: dearer as the shop runs short)" % [mags["purse"], price, second])
	_check(ash["fed"] == "bought" and ash["last_trade"].get("with") == "Mags" and int(ash["last_trade"].get("gold", 0)) == 100 - int(ash["purse"]),
		"Ash bought a meal from Mags: his last_trade says so (%s)" % [ash["last_trade"]])
	_check(_stock.ledger(TOWN).any(func(line: Dictionary) -> bool: return line["by"] == "folk:h1" and str(line["from"]).contains("Ash bought a meal from Mags")),
		"the ledger has it: Ash bought a meal from Mags")
	var odo := _work.worker("s1")
	_check(odo["fed"] == "store" and _stock.count(TOWN, "food") == 1, "Odo, the shop down to its last, bought the store's food (%s, food %d)" % [odo["fed"], _stock.count(TOWN, "food")])
	var pell := _work.worker("p1")
	_check(pell["fed"] == "dole" and _work.on_dole(TOWN) == 1, "Pell, with no gold, was fed by the town: the dole (%s)" % pell["fed"])
	_check(_told == [[TOWN, 1]], "dole_changed told 1 on the dole (%s)" % [_told])
	_check(_stock.ledger(TOWN).any(func(line: Dictionary) -> bool: return line["by"] == "dole:p1"), "the ledger has the dole")
	var signals := _work.signals_of(TOWN, CATALOG)
	_check(signals["dole"] == 1 and is_equal_approx(float(signals["short"].get("food", 0.0)), 1.0) and signals["raw_tier"] == Production.STOCK,
		"the dole makes food the town's first want (%s)" % [signals])
	_check(_work.need_due("h1", "meal") == meal_every + int(meal_every * float(_rules["folk"]["rich_every"])),
		"Ash, rich (over %d), eats again sooner (%d)" % [_rules["folk"]["rich_above"], _work.need_due("h1", "meal")])
	# The store's last food goes; then there is nothing.
	_now = meal_every * 2
	_economy.tick()
	_now = meal_every * 3
	_economy.tick()
	_check(_work.worker("p1")["fed"] == "hungry" and int(_work.worker("p1")["hungry_since"]) > 0,
		"with nothing in the store, Pell goes hungry (since %d)" % _work.worker("p1")["hungry_since"])
	_check(_stock.ledger(TOWN).any(func(line: Dictionary) -> bool: return line["by"] == "hungry:p1"), "the ledger says so")
	_stock.deposit(TOWN, "food", 5)
	_now = meal_every * 4
	_economy.tick()
	_check(_work.worker("p1")["hungry_since"] == 0, "fed again, he is hungry no longer")
	var saved := Production.new(_work.to_dict(), _stock, null, Callable(), _rules, func() -> Dictionary: return CATALOG)
	_check(saved.worker("h1")["last_trade"] == _work.worker("h1")["last_trade"] and saved.need_due("h1", "meal") == _work.need_due("h1", "meal")
		and saved.worker("p1")["fed"] == _work.worker("p1")["fed"], "needs, fed and last_trade are saved")
	var plain := _work.to_dict()
	for id: String in plain["workers"]:
		for key in ["needs", "fed", "hungry_since", "last_trade"]:
			plain["workers"][id].erase(key)
	var old := Production.new(plain, _stock, null, Callable(), _rules)
	_check(old.worker("h1")["needs"].is_empty() and old.worker("h1")["fed"] == "" and int(old.worker("h1")["purse"]) == int(_work.worker("h1")["purse"]),
		"a save from before them loads: needs come due afresh")


func _test_services() -> void:
	print("\n== services: the carpenter, the smith, the inn ==")
	_setup()
	_work.add_worker("h1", "Ash", ["hauler"], TOWN)
	_work.add_worker("p1", "Pell", ["carpenter"], TOWN)
	_work.add_worker("s1", "Odo", ["smith"], TOWN)
	_work.add_worker("x1", "Bea", ["hauler"], TOWN)
	_work.pay("h1", 20)
	_work.pay("s1", 20)
	_work.pay("x1", 1)
	var needs: Dictionary = _rules["folk"]["needs"]
	_economy.tick()
	_check(_work.need_due("p1", "mend") == 0 and _work.need_due("s1", "tools") == 0, "the carpenter doesn't mend for himself, nor the smith")
	var before := _gold()
	_now = int(needs["mend"]["every"])
	_inn = false
	_economy.tick()
	var mend := int(needs["mend"]["fee"])
	var tools := int(needs["tools"]["fee"])
	var ash := _work.worker("h1")
	_check(int(ash["purse"]) == 20 - mend - tools, "Ash paid for mending and tool work, and no inn stands (%d left)" % ash["purse"])
	var pell := _work.worker("p1")
	var odo := _work.worker("s1")
	var trade_tax := float(_rules["tax"]["trade"])
	_check(int(pell["purse"]) == 2 * (mend - int(floor(mend * trade_tax))), "Pell was paid by Ash and Odo (%d)" % pell["purse"])
	_check(int(odo["purse"]) == 20 - mend + tools - int(floor(tools * trade_tax)), "Odo paid Pell and was paid by Ash (%d)" % odo["purse"])
	_check(int(_work.worker("x1")["purse"]) == 1 and _work.need_due("x1", "mend") > _now, "Bea, with 1 gold, pays nothing and owes nothing: it waits")
	_check(_stock.ledger(TOWN).any(func(line: Dictionary) -> bool: return line["by"] == "folk:h1" and str(line["from"]).contains("Ash paid Pell")),
		"the ledger: Ash paid Pell")
	_check(_gold() == before, "gold only moved (%d, %d)" % [before, _gold()])
	_inn = true
	_now = int(needs["bed"]["every"]) * 3
	var had := _stock.count(TOWN, "gold")
	_economy.tick()
	var bed := int(needs["bed"]["fee"])
	_check(_stock.count(TOWN, "gold") >= had + bed and _work.worker("h1")["last_trade"].get("with") == Economy.TREASURY,
		"with the inn standing, a bed is paid to the treasury (%d to %d)" % [had, _stock.count(TOWN, "gold")])


func _test_days() -> void:
	print("
== three days of work, rent and trade on the founding gold ==")
	_setup()
	_stock.deposit(TOWN, "food", 400)
	var folk := [["c1", "Mags", "cook"], ["c2", "Tilda", "cook"], ["s1", "Odo", "smith"], ["p1", "Pell", "carpenter"],
		["g1", "Wat", "guard"], ["h1", "Ash", "hauler"], ["h2", "Bea", "hauler"], ["h3", "Cole", "hauler"]]
	var gold := int(_rules["start_gold"])
	for i in folk.size():
		_work.add_worker(folk[i][0], folk[i][1], [folk[i][2]], TOWN)
		_work.pay(folk[i][0], gold / folk.size() + (1 if i < gold % folk.size() else 0))
	_work.add_workshop(TOWN + ":kitchen", "cook", TOWN)
	_work.assign(TOWN + ":kitchen", "c1")
	_work.add_workshop(TOWN + ":kitchen2", "cook", TOWN)
	_work.assign(TOWN + ":kitchen2", "c2")
	_work.add_workshop(TOWN + ":yard", "carpenter", TOWN)
	_work.assign(TOWN + ":yard", "p1")
	_stock.deposit(TOWN, "wood", 10)
	var start := _gold()
	var richest := 0
	var ordered := false
	var most_dole := 0
	var guard_paid := 0
	var haulers_paid := 0
	var town_work := 0
	var day_lines: Array[String] = []
	while _now < 3 * DAY:
		_now += World.WORLD_TICK_STEPS
		if not ordered and _now >= DAY:
			ordered = true
			_work.order_build(TOWN, "walls", "carpenter", {"wood": 10}, 3000)
		_work.tick()
		_economy.tick()
		most_dole = maxi(most_dole, _work.on_dole(TOWN))
		for id in _work.worker_ids():
			richest = maxi(richest, int(_work.worker(id)["purse"]))
		if _now % DAY == 0:
			day_lines.append("day %d: treasury %d, purses %s, on the dole %d" % [_now / DAY, _stock.count(TOWN, "gold"),
				_work.worker_ids().map(func(id: String) -> String: return "%s %d" % [_work.worker(id)["name"], _work.worker(id)["purse"]]),
				_work.on_dole(TOWN)])
	var meals := 0
	var services := 0
	for line: Dictionary in _stock.ledger(TOWN):
		if str(line["by"]) == "wage:g1":
			guard_paid += 1
		if str(line["by"]).begins_with("wage:h"):
			haulers_paid += 1
		if str(line["by"]) == "town_work:p1":
			town_work = -int(line["count"])
		if str(line["from"]).contains("bought a meal"):
			meals += 1
		elif str(line["by"]).begins_with("folk:") and str(line["from"]).contains(" paid "):
			services += 1
	for line in day_lines:
		print("  " + line)
	print("  haulers paid %d times; Pell paid %d by the town for the walls" % [haulers_paid, town_work])
	print("  meals bought %d, services and beds %d, the guard paid %d times, the most on the dole at once %d, rent %d" % [
		meals, services, guard_paid, most_dole, _work.upkeep(TOWN)])
	_check(start == gold, "the town starts with its %d gold in its residents' purses" % gold)
	_check(_gold() + _work.upkeep(TOWN) == start, "gold conserved but for rent, the sink (%d + %d upkeep = %d)" % [_gold(), _work.upkeep(TOWN), start])
	_check(_stock.count(TOWN, "gold") > 0 and meals > 0, "the treasury filled from what was sold (%d)" % _stock.count(TOWN, "gold"))
	_check(guard_paid > 0, "the guard, an official job, was paid by the town (%d times)" % guard_paid)
	_check(haulers_paid > 0, "haulers, the town's own labour, were paid (%d times)" % haulers_paid)
	_check(town_work > 0, "the town paid Pell for the walls it ordered (%d)" % town_work)
	_check(richest <= gold, "no purse ran away (the most: %d)" % richest)
	_check(_work.worker_ids().all(func(id: String) -> bool: return _work.worker(id)["fed"] not in ["", "hungry"]),
		"everyone ate, nobody hungry")


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
