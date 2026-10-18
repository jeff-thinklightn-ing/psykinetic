extends Node
## The hunt brought into the town (decision 405), on a clock of its own with
## the real rules and items: meat, hide and leather are stock resources
## (each item's yield; a save from before them reads 0); the cook roasts
## meat and food before she bakes rations, and rations again once the meat
## is gone; the tanner makes leather from two hides whatever the tier, in
## his tannery; townsfolk eat the store's meat when it has no food; a raid
## takes meat as it takes food, and a hungry camp's raid (want "food",
## decision 409) more of both and nobody. A town's hunter (decision 407) every
## hunter.every steps brings home what the herds give: a stag's meat and
## hide into the store, its antlers banked; no game, nothing, and the town
## log says so. The carpenter mends a worn bundle of arrows banked in the
## store (decision 414, items' 413 mend): leather and wood used, the same
## uid back to its most, banked again; not a whole one, nor without the
## leather. Reads the repo's levels, never the shared
## overlay.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const TOWN := "lt/store"

var _failures := 0
var _now := 0
var _rules := {}


func _ready() -> void:
	World.set_process(false)
	_rules = Production.read_rules()
	_test_stock()
	_test_cook()
	_test_tanner()
	_test_eating()
	_test_raid()
	_test_hunter()
	_test_mend()
	_test_offers()
	_test_merchant()
	_test_first_stores()
	_test_thief_hooks()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _work() -> Production:
	_now = 0
	var clock := func() -> int: return _now
	var stock := Stockpile.new({}, clock, ItemBook.new(clock))
	return Production.new({}, stock, null, clock, _rules)


## Ticks [param work] until a job of [param recipe] starts there, at most
## [param steps]; the recipes started, in order.
func _started(work: Production, steps: int) -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	var until := _now + steps
	while _now < until:
		_now += World.WORLD_TICK_STEPS
		work.tick()
		for id in work.jobs():
			if not seen.has(id):
				seen[id] = true
				out.append(str(work.job(id)["recipe"]))
	return out


func _test_stock() -> void:
	print("\n== meat, hide and leather are stock ==")
	for what in ["meat", "hide", "leather"]:
		_check(what in Stockpile.RESOURCES and Items.yield_of(what) == {what: 1}, "%s: a stock resource, its item's yield (%s)" % [what, Items.yield_of(what)])
	var stock := Stockpile.new({}, func() -> int: return _now)
	stock.from_dict({TOWN: {"resources": {"gold": 5, "food": 2}, "items": [], "ledger": []}})
	_check(stock.count(TOWN, "meat") == 0 and stock.count(TOWN, "leather") == 0 and stock.count(TOWN, "food") == 2,
		"a save from before them: none of each (%s)" % [stock.resources(TOWN)])


func _test_cook() -> void:
	print("\n== the cook roasts the meat first ==")
	var work := _work()
	work.stockpile.deposit(TOWN, "food", 6)
	work.stockpile.deposit(TOWN, "meat", 1)
	work.add_worker("c1", "Mags", ["cook"], TOWN)
	work.add_workshop(TOWN + ":kitchen", "cook", TOWN)
	work.assign(TOWN + ":kitchen", "c1")
	var made := _started(work, 4000)
	_check(not made.is_empty() and made[0] == "roast", "with meat in the store, a roast first (%s)" % [made])
	_check(made.size() >= 2 and made[1] == "ration", "the meat gone, rations again (%s)" % [made])
	_check(work.stockpile.count(TOWN, "meat") == 0, "the meat was used")


func _test_tanner() -> void:
	print("\n== the tanner and his tannery ==")
	var tannery: Dictionary = _rules["buildings"]["tannery"]
	_check(tannery["trade"] == "tanner" and tannery["built_by"] == "carpenter", "the tannery is the tanner's, built by the carpenter")
	var work := _work()
	var towns := Towns.new({}, work, _rules, func() -> int: return _now)
	_check(towns.kind_for("tanner") == "tannery", "a tanner waits for a tannery")
	work.stockpile.deposit(TOWN, "hide", 3)
	work.add_worker("t1", "Hew", ["tanner"], TOWN)
	work.add_workshop(TOWN + ":tannery", "tanner", TOWN)
	work.assign(TOWN + ":tannery", "t1")
	_check(_started(work, 2000).is_empty(), "no tannery standing: he waits")
	towns._town(TOWN)["buildings"]["tannery"] = {"kind": "tannery", "level": 1, "state": Towns.STANDING, "since": 0, "job": 0}
	var made := _started(work, 4000)
	_check(made == ["leather"], "two hides make leather, whatever the town's tier (%s, %s)" % [made, work.tier(TOWN)])
	_check(work.stockpile.count(TOWN, "hide") == 1, "one hide left, too few for another")
	_check(work.stockpile.count(TOWN, "leather") == 1 and work.stockpile.shop(TOWN).is_empty(),
		"the leather is the town's stock, for its mending and bucklers (%d)" % work.stockpile.count(TOWN, "leather"))


func _test_eating() -> void:
	print("\n== no food: the store's meat ==")
	var rules := _rules.duplicate(true)
	rules.erase("bank")
	_now = 0
	var clock := func() -> int: return _now
	var stock := Stockpile.new({}, clock, ItemBook.new(clock))
	var work := Production.new({}, stock, null, clock, rules)
	var economy := Economy.new({}, stock, work, clock, rules)
	stock.deposit(TOWN, "meat", 2)
	work.add_worker("h1", "Ash", ["hauler"], TOWN)
	work.pay("h1", 20)
	economy.tick()
	_now = int(rules["folk"]["needs"]["meal"]["every"])
	economy.tick()
	_check(work.worker("h1")["fed"] == "store" and stock.count(TOWN, "meat") == 1, "Ash ate the store's meat (%s, %d left)" % [work.worker("h1")["fed"], stock.count(TOWN, "meat")])
	stock.deposit(TOWN, "food", 1)
	_now += int(rules["folk"]["needs"]["meal"]["every"])
	economy.tick()
	_check(stock.count(TOWN, "food") == 0 and stock.count(TOWN, "meat") == 1, "with food there, the food first")


func _test_raid() -> void:
	print("\n== a raid takes meat as food ==")
	var work := _work()
	var towns := Towns.new({}, work, _rules, func() -> int: return _now)
	work.stockpile.deposit(TOWN, "food", 10)
	work.stockpile.deposit(TOWN, "meat", 10)
	work.stockpile.deposit(TOWN, "hide", 10)
	work.stockpile.deposit(TOWN, "gold", 10)
	var report := towns.raid_arrives(TOWN, {"id": "g1", "faction": "goblins", "strength": 100.0, "from": "x"})
	_check(int(report["took"].get("meat", 0)) > 0 and int(report["took"].get("food", 0)) > 0, "meat and food taken (%s)" % [report["took"]])
	_check(work.stockpile.count(TOWN, "hide") == 10 and work.stockpile.count(TOWN, "gold") == 10, "hides and gold left alone")
	var empty: Array[String] = []
	work.holdings = Holdings.new(WorldMap.build(empty), Factions.read())
	var named := Factions.read().display_name("goblins")
	_check(towns.faction_name("goblins") == named and named != "goblins", "the log names a faction by its display name (%s)" % named)
	work.holdings = null
	_check(towns.faction_name("goblins") == "goblins", "with no holdings, by its id")
	for want in ["", "food", "gold"]:
		work = _work()
		towns = Towns.new({}, work, _rules, func() -> int: return _now)
		work.stockpile.deposit(TOWN, "food", 10)
		work.stockpile.deposit(TOWN, "meat", 10)
		towns.note_rescue(TOWN, "r1", "Ann", "carpenter")
		report = towns.raid_arrives(TOWN, {"id": "g2", "faction": "goblins", "strength": 100.0, "from": "x", "want": want})
		var took := [int(report["took"].get("food", 0)), int(report["took"].get("meat", 0)), report["captives"].size()]
		if want == "food":
			_check(took == [7, 7, 0] and report["want"] == "food", "a hungry camp's raid: three quarters of the food and meat, nobody carried off (%s)" % [took])
		else:
			_check(took == [4, 4, 1] and report["want"] == "", "want %s: the raid as ever, half (at 99 of 100 past Ann) and a captive (%s)" % ["\"%s\"" % want, took])


func _test_hunter() -> void:
	print("
== the hunter ==")
	var work := _work()
	var towns := Towns.new({}, work, _rules, func() -> int: return _now)
	var catches: Array[String] = ["stag", ""]
	var asked: Array[String] = []
	work.hunt = func(town: String) -> String:
		asked.append(town)
		return catches.pop_front() if not catches.is_empty() else ""
	work.add_worker("u1", "Hob", ["hunter"], TOWN)
	var every := int(_rules["hunter"]["every"])
	_started(work, every - World.WORLD_TICK_STEPS)
	_check(asked.is_empty(), "not before hunter.every steps")
	_started(work, every + World.WORLD_TICK_STEPS)
	_check(asked == [TOWN], "then he hunts the town's ground (%s)" % [asked])
	_check(work.stockpile.count(TOWN, "meat") == 4 and work.stockpile.count(TOWN, "hide") == 1,
		"a stag: the least of its meat and its hide into the store (%s)" % [work.stockpile.resources(TOWN)])
	_check(work.stockpile.item_ids(TOWN) == ["antlers"], "its antlers banked (%s)" % [work.stockpile.item_ids(TOWN)])
	_check(towns.log_of(TOWN).any(func(line: Dictionary) -> bool: return line["what"] == "Hob the hunter brought home a stag"), "the town log says so")
	_started(work, every)
	_check(asked.size() == 2 and work.stockpile.count(TOWN, "meat") == 4, "no game: nothing")
	_check(towns.log_of(TOWN).any(func(line: Dictionary) -> bool: return line["what"] == "Hob the hunter found no game"), "and the log says that too")
	work.set_away("u1", true)
	_started(work, every * 2)
	_check(asked.size() == 2, "away, he does not hunt")


func _test_mend() -> void:
	print("
== the carpenter mends a bundle of arrows ==")
	var work := _work()
	var book := work.book()
	var worn := book.mint("arrows", "made", "test")
	var whole := book.mint("arrows", "made", "test")
	book.set_condition(worn, 3)
	work.stockpile.bank(TOWN, whole, "Bo")
	work.stockpile.bank(TOWN, worn, "Bo")
	work.add_worker("p1", "Pell", ["carpenter"], TOWN)
	work.add_workshop(TOWN + ":carpenter", "carpenter", TOWN)
	work.assign(TOWN + ":carpenter", "p1")
	_check(_started(work, 1200).is_empty(), "no leather in the store: it waits")
	work.stockpile.deposit(TOWN, "leather", 1)
	work.stockpile.deposit(TOWN, "wood", 3)
	var jobs := _started(work, 1200)
	_check(jobs == ["arrows"], "with leather and wood, a mend (%s)" % [jobs])
	_check(book.condition_of(worn) == Items.condition_max("arrows") and worn in work.stockpile.items(TOWN),
		"the same bundle back to its most (%d), banked again" % book.condition_of(worn))
	_check(work.stockpile.count(TOWN, "leather") == 0 and work.stockpile.count(TOWN, "wood") == 2, "a leather and a wood used")
	_check(book.history(worn)["events"].any(func(event: Dictionary) -> bool: return event["kind"] == "mended"), "its history says mended")
	_check(work.stockpile.shop(TOWN).is_empty(), "not put up for sale")
	work.stockpile.deposit(TOWN, "leather", 1)
	_check(_started(work, 1200).is_empty(), "nothing worn left: no more mending")
	var saved := Production.new(JSON.parse_string(JSON.stringify(work.to_dict())), work.stockpile, null, func() -> int: return _now, _rules)
	_check(saved.jobs().is_empty(), "and nothing left over in a save")


## npc's offers' hooks (decision 435, economy's side): a player pays a
## resident's debt, the store says who banked what, the treasury pays a
## commission never below its floor.
func _test_offers() -> void:
	print("
== hooks for npc's offers ==")
	var rules := _rules.duplicate(true)
	_now = 0
	var clock := func() -> int: return _now
	var stock := Stockpile.new({}, clock, ItemBook.new(clock))
	var work := Production.new({}, stock, null, clock, rules)
	var economy := Economy.new({}, stock, work, clock, rules)
	work.add_worker("h1", "Ash", ["hauler"], TOWN)
	work.set_loan("h1", 7.5, true)
	var told: Array = []
	work.loan_changed.connect(func(id: String, owed: float, working: bool) -> void: told.append([id, owed, working]))
	economy.add_gold("p1", 5, "test")
	_check(economy.pay_loan("p1", "h1", 20) == 5 and economy.gold("p1") == 0 and stock.count(TOWN, "gold") == 5,
		"pay_loan: never more than the player has (5 of 7.5)")
	_check(is_equal_approx(float(work.worker("h1")["loan"]), 2.5) and told.back() == ["h1", 2.5, true], "the loan lowered, loan_changed said")
	economy.add_gold("p1", 10, "test")
	_check(economy.pay_loan("p1", "h1", 10) == 3 and float(work.worker("h1")["loan"]) == 0.0 and not work.worker("h1")["working_off"],
		"never more than it owes (3); paid off")
	_check(stock.ledger(TOWN).any(func(line: Dictionary) -> bool: return "has paid the town's coffer back" in str(line.get("from", ""))), "the ledger says so")
	var banked: Array = []
	stock.deposited.connect(func(place: String, by: String, by_id: String, what: String, count: int) -> void: banked.append([place, by, by_id, what, count]))
	stock.deposit(TOWN, "wood", 5, "Player1", "", "player:p1")
	var uid := stock.book.mint("dagger", "made", "test")
	stock.bank(TOWN, uid, "Player1", "", "", Vector2i(-1, -1), "banked", "player:p1")
	_check(banked == [[TOWN, "Player1", "player:p1", "wood", 5], [TOWN, "Player1", "player:p1", "dagger", 1]], "deposited: who banked what (%s)" % [banked])
	var floor_gold := int(rules.get("gold_floor", 0))
	stock.deposit(TOWN, "gold", floor_gold + 12)
	var have := stock.count(TOWN, "gold")
	var paid := economy.pay_commission("p2", TOWN, 1000)
	_check(paid > 0 and paid == maxi(have - floor_gold, 0) and stock.count(TOWN, "gold") == mini(have, floor_gold) and economy.gold("p2") == paid,
		"pay_commission: what the treasury has above its floor (%d)" % paid)
	_check(int(rules["commissions"]["rescue"]) == 10 and int(rules["commissions"]["camp"]) == 20 and int(rules["commissions"]["fetch"]) == 1, "commissions' rates in the rules")


## A merchant's sharper trades (decision 440, economy's side): buying a
## meal at merchant.buy of its price and selling their own at
## merchant.sell, the difference out of the maker's share; the town's
## materials and tax as for anyone; nobody else's prices changed.
func _test_merchant() -> void:
	print("
== a merchant's own trades ==")
	var rule: Dictionary = _rules["merchant"]
	var got := {}
	for buyer_type in ["steady", "merchant"]:
		for maker_type in ["steady", "merchant"]:
			var rules := _rules.duplicate(true)
			rules.erase("bank")
			_now = 0
			var clock := func() -> int: return _now
			var stock := Stockpile.new({}, clock, ItemBook.new(clock))
			var work := Production.new({}, stock, null, clock, rules)
			var economy := Economy.new({}, stock, work, clock, rules)
			work.add_worker("b1", "Ash", ["hauler"], TOWN, "test", buyer_type)
			work.add_worker("c1", "Mags", ["cook"], TOWN, "test", maker_type)
			work.pay("b1", 50)
			for i in 3:
				stock.stock_shop(TOWN, stock.book.mint("ration", "made", "test"), "test", "c1")
			var price := int(economy.goods(TOWN)[0]["price"])
			var treasury := stock.count(TOWN, "gold")
			economy._eat("b1", rules["folk"]["needs"]["meal"], Production.items_catalog())
			got["%s/%s" % [buyer_type, maker_type]] = {"price": price, "paid": 50 - int(work.worker("b1")["purse"]),
				"maker": int(work.worker("c1")["purse"]), "town": stock.count(TOWN, "gold") - treasury}
	var plain: Dictionary = got["steady/steady"]
	var buys: Dictionary = got["merchant/steady"]
	var sells: Dictionary = got["steady/merchant"]
	_check(plain["paid"] == plain["price"], "steady folk pay the price (%d)" % plain["paid"])
	_check(buys["paid"] == roundi(plain["price"] * float(rule["buy"])) and buys["town"] == plain["town"] and buys["maker"] == plain["maker"] - (plain["paid"] - buys["paid"]),
		"a merchant buys at %.2f: the maker takes the difference, the town's share the same (%s)" % [float(rule["buy"]), buys])
	_check(sells["paid"] == roundi(plain["price"] * float(rule["sell"])) and sells["town"] == plain["town"] and sells["maker"] == plain["maker"] + (sells["paid"] - plain["paid"]),
		"a merchant's own sells at %.2f, the extra the maker's (%s)" % [float(rule["sell"]), sells])
	_check(absi(int(got["merchant/merchant"]["paid"]) - plain["paid"]) <= 1, "two merchants nearly cancel (%d)" % got["merchant/merchant"]["paid"])
	# At a price the factor shows on: 20 gold.
	_now = 0
	var clock := func() -> int: return _now
	var stock := Stockpile.new({}, clock, ItemBook.new(clock))
	var work := Production.new({}, stock, null, clock, _rules)
	var economy := Economy.new({}, stock, work, clock, _rules)
	work.add_worker("m1", "Rook", ["hauler"], TOWN, "test", "merchant")
	work.add_worker("s1", "Odo", ["smith"], TOWN, "test", "steady")
	work.add_worker("m2", "Vell", ["smith"], TOWN, "test", "merchant")
	_check(economy._folk_price(20, "m1", "s1") == roundi(20 * float(rule["buy"])) and economy._folk_price(20, "s1", "m2") == roundi(20 * float(rule["sell"]))
		and economy._folk_price(20, "s1", "s1") == 20 and economy.folk_factor("", "buy") == 1.0, "20 gold: %d to a merchant buying, %d from a merchant selling, 20 otherwise"
		% [economy._folk_price(20, "m1", "s1"), economy._folk_price(20, "s1", "m2")])
	var before := stock.count(TOWN, "gold")
	economy._sale(TOWN, "s1", "sword", 20, "test", "plain")
	var town_plain := stock.count(TOWN, "gold") - before
	var maker_plain := int(work.worker("s1")["purse"])
	before = stock.count(TOWN, "gold")
	economy._sale(TOWN, "s1", "sword", 17, "test", "to a merchant", 20)
	_check(stock.count(TOWN, "gold") - before == town_plain and int(work.worker("s1")["purse"]) - maker_plain == maker_plain - 3,
		"a sale of 20 at 17: the town's materials and tax the same (%d), the maker 3 less" % town_plain)


## A town is founded with start_food in its store (449 amended); a
## resident with no gold, while the store has food, eats the store's at
## cost rather than borrowing for the cook's meal (354 amended).
func _test_first_stores() -> void:
	print("
== a town's first stores; no borrowing for the cook's meal ==")
	var work := _work()
	var towns := Towns.new({}, work, _rules, func() -> int: return _now)
	towns._found(TOWN)  # Its store first seen (seed_from).
	_check(work.stockpile.count(TOWN, "food") == int(_rules["start_food"]), "founded with start_food in the store (%d)" % work.stockpile.count(TOWN, "food"))
	var rules := _rules.duplicate(true)
	_now = 0
	var clock := func() -> int: return _now
	var stock := Stockpile.new({}, clock, ItemBook.new(clock))
	var folk := Production.new({}, stock, null, clock, rules)
	var economy := Economy.new({}, stock, folk, clock, rules)
	folk.add_worker("p1", "Pell", ["hauler"], TOWN)
	folk.add_worker("c1", "Mags", ["cook"], TOWN)
	stock.deposit(TOWN, "gold", 50)
	stock.deposit(TOWN, "food", 5)
	for i in 3:
		stock.stock_shop(TOWN, stock.book.mint("ration", "made", "test"), "test", "c1")
	economy._eat("p1", rules["folk"]["needs"]["meal"], Production.items_catalog())
	_check(folk.worker("p1")["fed"] == "store" and stock.shop(TOWN).size() == 3, "no gold, food in the store: the store's food, not the cook's meal (%s)" % folk.worker("p1")["fed"])
	stock.take(TOWN, "food", stock.count(TOWN, "food"))
	economy._eat("p1", rules["folk"]["needs"]["meal"], Production.items_catalog())
	_check(folk.worker("p1")["fed"] == "bought" and float(folk.worker("p1")["loan"]) > 0.0, "the store empty: then he borrows for the cook's meal")


## npc's thief (decision 461, economy's side): a lift from a purse, its
## return when caught, a lifted resource fenced through a merchant; gold
## only moves.
func _test_thief_hooks() -> void:
	print("
== the thief's hooks ==")
	_now = 0
	var clock := func() -> int: return _now
	var stock := Stockpile.new({}, clock, ItemBook.new(clock))
	var work := Production.new({}, stock, null, clock, _rules)
	var economy := Economy.new({}, stock, work, clock, _rules)
	work.add_worker("v1", "Odo", ["smith"], TOWN)
	work.add_worker("t1", "Nim", ["hauler"], TOWN)
	work.add_worker("m1", "Vell", ["hauler"], TOWN)
	work.pay("v1", 5)
	stock.deposit(TOWN, "gold", 40)
	var all_gold := func() -> int: return stock.count(TOWN, "gold") + int(work.worker("v1")["purse"]) + int(work.worker("t1")["purse"]) + int(work.worker("m1")["purse"])
	var before: int = all_gold.call()
	_check(work.lift_gold("v1", 3, "t1") == 3 and int(work.worker("v1")["purse"]) == 2 and int(work.worker("t1")["purse"]) == 3, "a lift of 3 from Odo's purse")
	_check(work.lift_gold("v1", 9, "t1") == 2 and int(work.worker("v1")["purse"]) == 0, "never more than the purse holds")
	_check(work.return_gold("t1", "v1", 4) == 4 and int(work.worker("v1")["purse"]) == 4, "caught: given back")
	stock.deposit(TOWN, "cloth", 0)
	var price := maxi(roundi(economy.raw_price(TOWN, "cloth") * 0.5), 1)
	var paid := economy.fence(TOWN, "m1", "t1", "cloth", 0.5, 0.4)
	_check(paid == price and stock.count(TOWN, "cloth") == 1 and int(work.worker("m1")["purse"]) == roundi(price * 0.4)
		and int(work.worker("t1")["purse"]) == 1 + price - roundi(price * 0.4), "a cloth fenced: %d paid, the merchant's margin, the rest the thief's" % paid)
	_check(all_gold.call() == before, "gold only moved (%d)" % all_gold.call())
	stock.take(TOWN, "gold", stock.count(TOWN, "gold"))
	_check(economy.fence(TOWN, "m1", "t1", "cloth", 0.5, 0.4) == 0 and stock.count(TOWN, "cloth") == 1, "the treasury at its floor: nothing moves")


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
