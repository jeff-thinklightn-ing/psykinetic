extends Node
## Residents' trade and a town's starting gold (decision 353), on a clock of
## its own with the real rules (levels/economy.json) and a test catalog: a
## town is founded with start_gold once; residents buy meals from the shop
## (the maker paid, the sale tax to the treasury, keep_in_shop left for
## players), else the store's food, else the town feeds them (the dole,
## which makes food the town's first want), else they go hungry; they pay
## the carpenter and the smith for services and the inn for a bed, never
## into debt; a rich one spends sooner; each trade is a ledger line and the
## worker's last_trade; gold only moves; and three game days of work, rent
## and trade keep the treasury at its floor or above, every purse bounded
## and everyone fed. Reads the repo's levels, never the shared overlay.
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
	_check(_rules.get("start_gold") == 50.0 and stock.count("wilds/store", "gold") == 50,
		"the wilds store has the 50 starting gold (%d)" % stock.count("wilds/store", "gold"))
	towns.seed_from(world_map)
	_check(stock.count("wilds/store", "gold") == 50, "seeded again: still 50")
	var again := Towns.new(towns.to_dict(), work, _rules)
	again.seed_from(world_map)
	_check(stock.count("wilds/store", "gold") == 50, "after a restart: still 50 (founded is saved)")
	var old := towns.to_dict()
	old["wilds/store"].erase("founded")
	var stock_old := Stockpile.new({}, Callable(), ItemBook.new(Callable()))
	var older := Towns.new(old, Production.new({}, stock_old, null, Callable(), _rules), _rules)
	older.seed_from(world_map)
	_check(stock_old.count("wilds/store", "gold") == 50, "a save from before it gets the 50 once")


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
	var tax := int(floor(price * float(_rules["tax"]["sale"])))
	var mags := _work.worker("c1")
	var ash := _work.worker("h1")
	var second := int(ash["last_trade"].get("gold", 0))
	_check(mags["fed"] == "bought" and int(mags["purse"]) == 10 - price + (price - tax) + second - int(floor(second * float(_rules["tax"]["sale"]))),
		"Mags (cook) bought her own meal and was paid for both, less the tax (%d gold, %d then %d: dearer as the shop runs short)" % [mags["purse"], price, second])
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
	print("\n== three days of work, rent and trade ==")
	_setup()
	_stock.deposit(TOWN, "gold", int(_rules["start_gold"]))
	_stock.deposit(TOWN, "food", 400)
	var folk := [["c1", "Mags", "cook"], ["c2", "Tilda", "cook"], ["s1", "Odo", "smith"], ["p1", "Pell", "carpenter"],
		["h1", "Ash", "hauler"], ["h2", "Bea", "hauler"], ["h3", "Cole", "hauler"], ["h4", "Dara", "hauler"]]
	for each in folk:
		_work.add_worker(each[0], each[1], [each[2]], TOWN)
	_work.add_workshop(TOWN + ":kitchen", "cook", TOWN)
	_work.assign(TOWN + ":kitchen", "c1")
	_work.add_workshop(TOWN + ":kitchen2", "cook", TOWN)
	_work.assign(TOWN + ":kitchen2", "c2")
	var start := _gold()
	var floor_gold := int(_rules["gold_floor"])
	var lowest := _stock.count(TOWN, "gold")
	var richest := 0
	var meals := 0
	var steps := 0
	while _now < 3 * DAY:
		_now += World.WORLD_TICK_STEPS
		steps += 1
		_work.tick()
		_economy.tick()
		lowest = mini(lowest, _stock.count(TOWN, "gold"))
		for id in _work.worker_ids():
			richest = maxi(richest, int(_work.worker(id)["purse"]))
	for line: Dictionary in _stock.ledger(TOWN):
		if str(line["from"]).contains("bought a meal"):
			meals += 1
	_check(lowest >= mini(floor_gold, int(_rules["start_gold"])), "the treasury never went under its floor (lowest %d)" % lowest)
	_check(_gold() + _work.upkeep(TOWN) == start, "gold conserved but for rent, the sink (%d + %d upkeep = %d)" % [_gold(), _work.upkeep(TOWN), start])
	_check(_work.upkeep(TOWN) > 0, "rent was paid (%d)" % _work.upkeep(TOWN))
	_check(richest <= 200, "no purse ran away (the most: %d)" % richest)
	_check(meals > 0, "residents bought meals the cooks made (%d in the ledger)" % meals)
	_check(_work.worker_ids().all(func(id: String) -> bool: return _work.worker(id)["fed"] != "" and _work.worker(id)["fed"] != "hungry"),
		"everyone ate, nobody hungry (%s)" % [_work.worker_ids().map(func(id: String) -> String: return "%s %s %d" % [id, _work.worker(id)["fed"], _work.worker(id)["purse"]])])
	print("  after 3 days: treasury %d, purses %s, upkeep %d" % [_stock.count(TOWN, "gold"),
		_work.worker_ids().map(func(id: String) -> int: return int(_work.worker(id)["purse"])), _work.upkeep(TOWN)])


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
