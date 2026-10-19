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
	_test_scoundrel_hooks()
	_test_delivery()
	_test_apprentice()
	_test_contribute()
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
	_check(int(rules["commissions"]["rescue"]) == 10 and int(rules["commissions"]["camp"]) == 20 and int(rules["commissions"]["fetch"]) == 1
		and int(rules["commissions"]["dispute"]) == 5 and int(rules["commissions"]["escort"]) == 8, "commissions' rates in the rules")


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


## The scoundrel's hooks (decision 492, economy's side): a made thing told
## before it is shelved, his trade a little dear, no repaying on his own.
func _test_scoundrel_hooks() -> void:
	print("
== the scoundrel's hooks ==")
	_now = 0
	var clock := func() -> int: return _now
	var stock := Stockpile.new({}, clock, ItemBook.new(clock))
	var work := Production.new({}, stock, null, clock, _rules)
	var economy := Economy.new({}, stock, work, clock, _rules)
	work.add_worker("s1", "Grub", ["cook"], TOWN, "test", "scoundrel")
	work.add_worker("h1", "Ash", ["hauler"], TOWN, "test", "steady")
	var rule: Dictionary = _rules["scoundrel"]
	_check(is_equal_approx(economy.folk_factor("s1", "sell"), float(rule["sell"])) and is_equal_approx(economy.folk_factor("s1", "buy"), float(rule["buy"]))
		and economy.folk_factor("h1", "sell") == 1.0, "he sells at %.2f, buys at %.2f; anyone else at 1" % [economy.folk_factor("s1", "sell"), economy.folk_factor("s1", "buy")])
	_check(economy._folk_price(10, "h1", "s1") == roundi(10 * float(rule["sell"])), "a neighbour pays him a little dear (%d for 10)" % economy._folk_price(10, "h1", "s1"))
	for id in ["s1", "h1"]:
		work.pay(id, 20)
		work.set_loan(id, 10.0)
		economy._bank_turn(id, TOWN)
	_check(int(work.worker("s1")["purse"]) == 20 and is_equal_approx(float(work.worker("s1")["loan"]), 10.0), "he pays nothing back on his own (owes %.0f)" % float(work.worker("s1")["loan"]))
	_check(int(work.worker("h1")["purse"]) < 20 and float(work.worker("h1")["loan"]) < 10.0, "a steady one does")
	var told := []
	work.made.connect(func(town: String, who: String, uid: int) -> void: told.append([town, who, uid, uid in stock.all_items()]))
	work.add_workshop("k1", "cook", TOWN)
	work.assign("k1", "s1")
	stock.deposit(TOWN, "food", 5)
	work.order("k1", "ration")
	var until := _now + 20000
	while _now < until and told.is_empty():
		_now += World.WORLD_TICK_STEPS
		work.tick()
	_check(told.size() == 1 and told[0][0] == TOWN and told[0][1] == "s1" and stock.book.id_of(int(told[0][2])) == "ration"
		and not told[0][3] and int(told[0][2]) in stock.all_items(), "made: the town, the maker and the ration's uid, before it is shelved (%s)" % [told])


## Gathered, hauled and paid for (decision 498): a delivery bought at the
## shop's raw price, a hauler's fee a load out of it, the rest owed when the
## treasury is at its floor and paid as gold comes in, no more bought past
## owed_cap; a maker paying for materials, never under what the store paid.
func _test_delivery() -> void:
	print("
== gathered, hauled and paid for ==")
	_now = 0
	var clock := func() -> int: return _now
	var stock := Stockpile.new({}, clock, ItemBook.new(clock))
	var work := Production.new({}, stock, null, clock, _rules)
	var economy := Economy.new({}, stock, work, clock, _rules)
	work.deliver = economy.deliver
	work.buy_materials = economy.buy_materials
	var floor_gold := int(_rules["gold_floor"])
	work.add_worker("w1", "Bran", ["woodcutter"], TOWN, "test", "steady")
	stock.deposit(TOWN, "gold", 100)
	var unit := economy.raw_price(TOWN, "wood") * float(_rules["store"]["buy"])
	_check(work.deliver_to(TOWN, "w1", "wood", 4, "w", "test") and stock.count(TOWN, "wood") == 4
		and int(work.worker("w1")["purse"]) == roundi(unit * 4) and stock.count(TOWN, "gold") == 100 - roundi(unit * 4),
		"4 wood delivered: banked, the woodcutter paid %d from the treasury" % int(work.worker("w1")["purse"]))
	work.add_worker("h1", "Ash", ["hauler"], TOWN, "test", "steady")
	var before := int(work.worker("w1")["purse"])
	var price := roundi(economy.raw_price(TOWN, "wood") * float(_rules["store"]["buy"]) * 12)
	var fee := ceili(12.0 / int(_rules["haul"]["load"])) * int(_rules["haul"]["fee"])
	work.deliver_to(TOWN, "w1", "wood", 12, "w", "test")
	_check(int(work.worker("h1")["purse"]) == fee and int(work.worker("w1")["purse"]) - before == price - fee,
		"12 hauled in %d loads: the hauler %d, the woodcutter the rest (%d)" % [fee, fee, price - fee])
	stock.take(TOWN, "gold", stock.count(TOWN, "gold") - floor_gold)
	before = int(work.worker("w1")["purse"])
	work.deliver_to(TOWN, "w1", "wood", 10, "w", "test")
	var owed := int(work.worker("w1")["owed"])
	_check(owed > 0 and int(work.worker("w1")["purse"]) == before and stock.count(TOWN, "gold") == floor_gold, "the treasury at its floor: owed %d" % owed)
	stock.deposit(TOWN, "gold", 100)
	economy._pay_owed("w1", TOWN)
	_check(int(work.worker("w1")["owed"]) == 0 and int(work.worker("w1")["purse"]) == before + owed, "paid when gold comes in")
	stock.take(TOWN, "gold", stock.count(TOWN, "gold") - floor_gold)
	var wood := stock.count(TOWN, "wood")
	while int(work.worker("w1")["owed"]) < int(_rules["store"]["owed_cap"]):
		work.deliver_to(TOWN, "w1", "wood", 10, "w", "test")
	wood = stock.count(TOWN, "wood")
	_check(not work.deliver_to(TOWN, "w1", "wood", 10, "w", "test") and stock.count(TOWN, "wood") == wood
		and stock.ledger(TOWN).any(func(line: Dictionary) -> bool: return "can't pay Bran for more wood" in str(line.get("from", "")) + str(line.get("what", "")) + str(line)),
		"owed its cap: the store takes no more, and says so")
	work.add_worker("m1", "Odo", ["smith"], TOWN, "test", "steady")
	work.pay("m1", 40)
	var paid_unit := float(economy._paid[TOWN]["wood"])
	var cost := ceili(maxf(float(economy.raw_price(TOWN, "wood")), paid_unit) * float(_rules["store"]["sell"]) * 3)
	var treasury := stock.count(TOWN, "gold")
	_check(economy.buy_materials(TOWN, "m1", {"wood": 3}) and int(work.worker("m1")["purse"]) == 40 - cost and stock.count(TOWN, "gold") == treasury + cost
		and cost >= ceili(paid_unit * 3), "a maker pays %d for 3 wood, not under the %.1f a unit the store paid" % [cost, paid_unit])
	work.add_worker("m2", "Pell", ["carpenter"], TOWN, "test", "steady")
	work.set_loan("m2", float(_rules["bank"]["cap"]))
	_check(not economy.buy_materials(TOWN, "m2", {"wood": 3}) and int(work.worker("m2")["purse"]) == 0, "one who can't pay or borrow: no materials")
	work.add_worker("c1", "Mags", ["cook"], TOWN, "test", "steady")
	work.set_loan("c1", float(_rules["bank"]["cap"]))
	work.add_workshop("k1", "cook", TOWN)
	work.assign("k1", "c1")
	stock.deposit(TOWN, "food", 5)
	work.order("k1", "ration")
	var until := _now + 3 * World.WORLD_TICK_STEPS
	while _now < until:
		_now += World.WORLD_TICK_STEPS
		work.tick()
	_check(work.jobs().any(func(job_id: int) -> bool: return work.job(job_id)["workshop"] == "k1" and work.job(job_id)["state"] == "working")
		and int(work.worker("c1")["purse"]) == 0, "a cook at her loan cap still cooks: the town's meals on its account")
	stock.take(TOWN, "gold", stock.count(TOWN, "gold") - floor_gold - 2)
	var sale := roundi(economy.raw_price(TOWN, "hide") * float(_rules["store"]["buy"]) * 5)
	var now_paid := economy.bank_sale(TOWN, "p1", {"hide": 5})
	_check(now_paid == mini(sale, 2) and economy.owed_to("p1", TOWN) == sale - now_paid, "a player banks 5 hides: %d paid now, %d owed" % [now_paid, economy.owed_to("p1", TOWN)])
	var told := []
	economy.owed_paid.connect(func(id: String, gold: int) -> void: told.append([id, gold]))
	stock.deposit(TOWN, "gold", 100)
	economy._pay_player("p1")
	_check(economy.owed_to("p1", TOWN) == 0 and economy.gold("p1") == sale - now_paid and told == [["p1", sale - now_paid]], "the rest paid as gold comes in, and told")
	# A bunch of herbs banked (items' herbs, 501 amended): a sale like any raw.
	stock.deposit(TOWN, "gold", 100)
	var herb_price := roundi(economy.raw_price(TOWN, "herbs") * float(_rules["store"]["buy"]))
	_check(Items.yield_of("herbs") == {"herbs": 1} and herb_price >= 1 and economy.bank_sale(TOWN, "p1", Items.yield_of("herbs")) == herb_price,
		"a bunch of herbs banked: %d gold" % herb_price)
	# Leather pays for its hides and the work (2 hides a piece): the tanner
	# no longer makes it at a loss (by the value table, as stocks move both).
	var value: Dictionary = _rules["value"]
	var hides := float(value["hide"]) * float(_rules["store"]["sell"]) * int(Items.def("leather")["made"]["from"]["hide"])
	_check(float(value["leather"]) * float(_rules["store"]["buy"]) > hides,
		"leather bought for more than its hides cost the tanner (%s > %s)" % [value["leather"], hides])


## Apprentices (decision 498 amended): a maker above apprentice.above for
## apprentice.days takes a hauler, pays them a wage a day, works faster
## with them, and lets them go under apprentice.below.
func _test_apprentice() -> void:
	print("
== an apprentice ==")
	_now = 0
	var clock := func() -> int: return _now
	var stock := Stockpile.new({}, clock, ItemBook.new(clock))
	var work := Production.new({}, stock, null, clock, _rules)
	var economy := Economy.new({}, stock, work, clock, _rules)
	var rule: Dictionary = _rules["apprentice"]
	work.add_worker("c1", "Mags", ["cook"], TOWN, "test", "steady")
	work.add_worker("h1", "Ash", ["hauler"], TOWN, "test", "steady")
	work.pay("c1", int(rule["above"]) + 40)
	economy._apprentice_turn("c1", TOWN)
	_check(str(work.worker("c1")["apprentice"]).is_empty(), "rich today: not yet")
	_now = int(float(rule["days"]) * DayNight.day_steps) + 1
	economy._apprentice_turn("c1", TOWN)
	_check(work.worker("c1")["apprentice"] == "h1" and work.worker("h1")["master"] == "c1", "rich for %d days: takes Ash" % int(rule["days"]))
	_check(economy._hauler_for(TOWN, "x", "hauler").is_empty(), "an apprentice carries no loads")
	work.add_workshop("k1", "cook", TOWN)
	work.assign("k1", "c1")
	stock.deposit(TOWN, "food", 5)
	work.order("k1", "ration")
	var steps := int(Items.def("ration")["made"]["steps"])
	var start := _now
	var per_tick := 0
	while _now < start + steps * 2 and per_tick == 0:
		_now += World.WORLD_TICK_STEPS
		var before_tick := {}
		for job_id in work.jobs():
			if work.job(job_id)["state"] == "working":
				before_tick[job_id] = int(work.job(job_id)["worked"])
		work.tick()
		for job_id in before_tick:
			if work.job(job_id).get("state") == "working" and per_tick == 0:
				per_tick = int(work.job(job_id)["worked"]) - int(before_tick[job_id])
	var purse := int(work.worker("c1")["purse"])
	economy._apprentice_turn("c1", TOWN)
	_check(int(work.worker("h1")["purse"]) == 0, "no wage before the day is out")
	_now = start + DayNight.day_steps
	economy._apprentice_turn("c1", TOWN)
	_check(int(work.worker("h1")["purse"]) == int(rule["wage"]) and int(work.worker("c1")["purse"]) == purse - int(rule["wage"]),
		"a day on: Ash paid %d by Mags" % int(rule["wage"]))
	_check(per_tick == roundi(World.WORLD_TICK_STEPS * float(rule["speed"])), "made faster with help: %d work a tick of %d" % [per_tick, World.WORLD_TICK_STEPS])
	work.spend("c1", int(work.worker("c1")["purse"]) - int(rule["below"]) + 1)
	economy._apprentice_turn("c1", TOWN)
	_check(str(work.worker("c1")["apprentice"]).is_empty() and str(work.worker("h1")["master"]).is_empty(), "under %d: lets Ash go" % int(rule["below"]))


## Players' contributions (decision 499): gold given toward the next build,
## never more than it needs, kept in its fund; pays deliveries of what it
## lacks, then the builder's fee, the rest the town's; thanked in xp.
func _test_contribute() -> void:
	print("
== given toward the town ==")
	_now = 0
	var clock := func() -> int: return _now
	var stock := Stockpile.new({}, clock, ItemBook.new(clock))
	var work := Production.new({}, stock, null, clock, _rules)
	var economy := Economy.new({}, stock, work, clock, _rules)
	var towns := Towns.new({}, work, _rules, clock)
	work.deliver = economy.deliver
	economy.shortfall = towns.shortfall
	work.settle_fund = economy.settle_fund
	var thanked: Array = []
	economy.contributed.connect(func(town: String, player_id: String, kind: String, gold: int, xp: int) -> void: thanked.append([kind, gold, xp]))
	var floor_gold := int(_rules["gold_floor"])
	stock.deposit(TOWN, "gold", floor_gold)
	economy.add_gold("p1", 100)
	_check(economy.contribution_wanted(TOWN).is_empty() and economy.contribute(TOWN, "p1", 10) == 0 and economy.gold("p1") == 100,
		"nothing planned: nothing taken")
	stock.deposit(TOWN, "wood", 4)
	var job := work.order_build(TOWN, "inn", "carpenter", {"wood": 10}, 1200)
	var wanted := economy.contribution_wanted(TOWN)
	var expect := work.town_work_fee(1200) + ceili(economy.raw_price(TOWN, "wood") * float(_rules["store"]["buy"]) * 6)
	_check(wanted.get("kind") == "inn" and int(wanted["gold"]) == expect, "the inn lacks 6 wood and its fee: %s gold wanted" % [wanted.get("gold")])
	var given := economy.contribute(TOWN, "p1", 1000)
	_check(given == expect and economy.gold("p1") == 100 - expect and economy.fund(TOWN, "inn") == expect and stock.count(TOWN, "gold") == floor_gold,
		"gives %d, no more than wanted, into the inn's fund, not the treasury" % given)
	_check(thanked.size() == 1 and thanked[0][2] == maxi(expect / int(_rules["contribute"]["gold_per_xp"]), 1), "thanked in town experience (%s)" % [thanked])
	_check(economy.contribute(TOWN, "p1", 10) == 0, "nothing more wanted: nothing more taken")
	work.add_worker("w1", "Bran", ["woodcutter"], TOWN, "test", "steady")
	var price := roundi(economy.raw_price(TOWN, "wood") * float(_rules["store"]["buy"]) * 3)
	var had := economy.fund(TOWN, "inn")
	work.deliver_to(TOWN, "w1", "wood", 3, "w", "test")
	_check(int(work.worker("w1")["purse"]) == price and int(work.worker("w1")["owed"]) == 0 and economy.fund(TOWN, "inn") == had - price
		and stock.count(TOWN, "gold") == floor_gold, "the treasury at its floor: 3 wood paid from the fund (%d)" % price)
	work.add_worker("c1", "Pell", ["carpenter"], TOWN, "test", "steady")
	had = economy.fund(TOWN, "inn")
	var fee := work.town_work_fee(1200)
	_check(economy.settle_fund(TOWN, "inn", "c1", fee) == fee and int(work.worker("c1")["purse"]) == fee and economy.fund(TOWN, "inn") == 0
		and stock.count(TOWN, "gold") == floor_gold + had - fee, "built: the carpenter's fee from it, the rest the town's")
	work.cancel(job)
	stock.take(TOWN, "wood", stock.count(TOWN, "wood"))
	work.order_build(TOWN, "woodshed", "carpenter", {"wood": 5}, 600)
	var shed := economy.contribute(TOWN, "p1", 5)
	work.cancel(work.jobs().filter(func(id: int) -> bool: return work.job(id)["recipe"] == "woodshed")[0])
	var treasury := stock.count(TOWN, "gold")
	economy._drop_funds()
	_check(shed == 5 and economy.fund(TOWN, "woodshed") == 0 and stock.count(TOWN, "gold") == treasury + 5 and economy.gold("p1") == 100 - expect - 5,
		"the plan dropped: what was given is the town's, the player's gold not returned")

func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
