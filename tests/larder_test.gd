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
	_test_larder_reserve()
	_test_thief_hooks()
	_test_scoundrel_hooks()
	_test_delivery()
	_test_hut_account()
	_test_hut_decay()
	_test_apprentice()
	_test_contribute()
	_test_caravan()
	_test_founding_caravan()
	_test_luxury()
	_test_head_first()
	_test_account()
	_test_livings()
	_test_offering()
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


## The founding larder (652 amended (2), the coordinator's ruling): a cook
## makes nothing from food that would leave the store under the town's
## larder_for (Towns: its people's food to the first crop, before it; none
## after), though the meals still come from it.
func _test_larder_reserve() -> void:
	print("
== the cook leaves the founding larder ==")
	var work := _work()
	var larder := [10]
	work.larder_for = func(_town: String) -> int: return larder[0]
	work.stockpile.deposit(TOWN, "food", 10)
	work.add_worker("c1", "Mags", ["cook"], TOWN)
	work.add_workshop(TOWN + ":kitchen", "cook", TOWN)
	work.assign(TOWN + ":kitchen", "c1")
	_check(_started(work, 4000).is_empty() and work.stockpile.count(TOWN, "food") == 10, "the store at its larder: no ration made from it")
	larder[0] = 0
	_check("ration" in _started(work, 4000), "nothing kept: rations again")
	var towns := Towns.new({}, Production.new({}, Stockpile.new({}, func() -> int: return _now, ItemBook.new(func() -> int: return _now)), null, func() -> int: return _now, _rules), _rules, func() -> int: return _now)
	towns._found(TOWN)
	_check(towns.larder_for(TOWN) == towns.founding_food(TOWN) and towns.larder_for(TOWN) > 0 and towns.production.larder_for.is_valid(),
		"Towns: before the first crop, its people's food to it (%d)" % towns.larder_for(TOWN))
	towns._town(TOWN)["harvests"] = 1
	_check(towns.larder_for(TOWN) == 0, "after it, none")


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
	var first := maxi(int(_rules["start_food"]), towns.founding_food(TOWN))
	_check(work.stockpile.count(TOWN, "food") == first, "founded with start_food or its people's food to the first autumn in the store (%d)" % work.stockpile.count(TOWN, "food"))
	# The days to its first crop of any kind (652 amended), from when its
	# field can stand (field_days on, none standing): this autumn's harvest
	# from spring's start, the winter's roots from summer's.
	var founding: Dictionary = _rules["founding"]
	var heads := int(founding["heads"])
	var phase := Season.year_phase
	var anchor := Season.year_anchor
	Season.year_anchor = _now
	Season.year_phase = 0.0
	var spring := towns.founding_food(TOWN)
	Season.year_phase = 0.25
	var summer := towns.founding_food(TOWN)
	Season.year_phase = phase
	Season.year_anchor = anchor
	var margin := float(founding.get("margin_days", 0))
	_check(spring == ceili(float(founding["per_head_day"]) * heads * (2 * Season.season_days + margin))
		and summer == ceili(float(founding["per_head_day"]) * heads * (2 * Season.season_days + margin)),
		"founded at spring's start: food for two seasons a head, to the autumn (%d); at summer's, two, to the winter's roots (%d)" % [spring, summer])
	# Founded before its people are counted: topped up once they are here.
	var had := work.stockpile.count(TOWN, "food")
	for i in heads + 4:
		towns.note_rescue(TOWN, "fl%d" % i, "Folk%d" % i, "hauler")
	towns._spread(TOWN)
	var topped := work.stockpile.count(TOWN, "food") - had
	_check(topped == maxi(towns.founding_food(TOWN) - first, 0) and topped > 0, "its people counted: the stores topped up by %d" % topped)
	towns._spread(TOWN)
	_check(work.stockpile.count(TOWN, "food") == had + topped, "once")
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


## A healer's hut (no town's store, no treasury; the box's huts waited for
## ever, "its maker can't pay for the materials"): its medicine man makes a
## remedy from the herbs he banked there, nothing bought, his purse 0 and the
## hut's gold 0. A town's workshop still buys them.
func _test_hut_account() -> void:
	print("\n== a healer's hut works on its own account ==")
	_now = 0
	var clock := func() -> int: return _now
	var stock := Stockpile.new({}, clock, ItemBook.new(clock))
	var no_areas: Array[String] = []
	var holdings := Holdings.new(WorldMap.build(no_areas), null, {}, clock)
	const HUT := "lt/healers_hut@1,1"
	holdings._places[HUT] = {"id": HUT, "area": "lt", "key": "healers_hut@1,1", "cell": Vector2i(1, 1), "name": "the healer's hut",
		"kind": "healers_hut", "radius": 2, "worth": 0, "start": ""}
	holdings._places[TOWN] = {"id": TOWN, "area": "lt", "key": "store", "cell": Vector2i(9, 9), "name": "the store",
		"kind": Stockpile.KIND, "radius": 2, "worth": 0, "start": ""}
	var work := Production.new({}, stock, holdings, clock, _rules)
	var economy := Economy.new({}, stock, work, clock, _rules)
	work.buy_materials = economy.buy_materials
	for at: String in [HUT, TOWN]:
		var id := "mm_" + at.get_slice("/", 1)
		work.add_worker(id, "Hob", ["medicine_man"], at, "test", "steady")
		work.set_loan(id, float(_rules["bank"]["cap"]))
		work.add_workshop(at + ":hut", "medicine_man", at)
		work.assign(at + ":hut", id)
		stock.deposit(at, "herbs", 4)
		work.order(at + ":hut", "remedy")
	_now += World.WORLD_TICK_STEPS
	work.tick()
	var working := func(shop: String) -> bool: return work.jobs().any(func(job_id: int) -> bool:
		return work.job(job_id)["workshop"] == shop and work.job(job_id)["state"] == "working")
	_check(working.call(HUT + ":hut") and stock.count(HUT, "herbs") == 2 and stock.count(HUT, "gold") == 0,
		"the hut's remedy started from its own herbs, nothing bought (herbs %d)" % stock.count(HUT, "herbs"))
	_check(not working.call(TOWN + ":hut") and stock.count(TOWN, "herbs") == 4, "a town's medicine man at his loan cap still can't buy the town's herbs")


## A healer's hut nobody keeps decays and its keeper mends it (733): empty
## decline.unkept_days, disrepair; a season on, a ruin, never gone; a new
## keeper buys healers.repair.ruin's supplies from the town's store and mends
## it as his own workshop's job; standing again; kept in the save.
func _test_hut_decay() -> void:
	print("
== a healer's hut decays empty and its keeper mends it ==")
	_now = 0
	var clock := func() -> int: return _now
	var day := DayNight.day_steps
	var stock := Stockpile.new({}, clock, ItemBook.new(clock))
	var no_areas: Array[String] = []
	var holdings := Holdings.new(WorldMap.build(no_areas), null, {}, clock)
	const HUT := "lt/healers_hut@1,1"
	holdings._places[HUT] = {"id": HUT, "area": "lt", "key": "healers_hut@1,1", "cell": Vector2i(1, 1), "name": "the healer's hut",
		"kind": "healers_hut", "radius": 2, "worth": 0, "start": ""}
	holdings._places[TOWN] = {"id": TOWN, "area": "lt", "key": "store", "cell": Vector2i(9, 9), "name": "the store",
		"kind": Stockpile.KIND, "radius": 2, "worth": 0, "start": ""}
	var work := Production.new({}, stock, holdings, clock, _rules)
	var towns := Towns.new({}, work, _rules, clock)
	var economy := Economy.new({}, stock, work, clock, _rules)
	work.buy_materials = economy.buy_materials
	towns.hut_supplies = func(hut_id: String, keeper: String, needs: Dictionary) -> bool: return economy.hut_supplies(TOWN, hut_id, keeper, needs)
	var told := {"n": 0}
	towns.hut_changed.connect(func(_id: String) -> void: told["n"] += 1)
	work.add_worker("mm1", "Hob", ["medicine_man"], HUT, "test", "steady")
	work.add_workshop(HUT, "medicine_man", HUT)
	work.assign(HUT, "mm1")
	towns._huts_turn()
	_check(towns.hut(HUT) == {"state": Towns.STANDING, "level": 1}, "kept: standing (%s)" % [towns.hut(HUT)])
	work.remove_worker("mm1")
	var unkept := int(_rules["decline"]["unkept_days"])
	for i in unkept + 1:
		_now += day
		towns._huts_turn()
	_check(towns.hut(HUT)["state"] == Towns.DISREPAIR and towns.hut(HUT).has("empty_since") and told["n"] == 1,
		"empty %d days: disrepair, empty_since told (%s)" % [unkept, towns.hut(HUT)])
	for i in Season.season_days * 3:
		_now += day
		towns._huts_turn()
	_check(towns.hut(HUT)["state"] == Towns.RUIN and told["n"] == 2, "a season on, a ruin, and never gone (%s)" % [towns.hut(HUT)])
	var needs: Dictionary = _rules["healers"]["repair"]["ruin"]["needs"]
	work.add_worker("mm2", "Gile", ["medicine_man"], HUT, "test", "steady")
	work.assign(HUT, "mm2")
	_now += day
	towns._huts_turn()
	_check(int(towns._huts[HUT]["job"]) == 0, "no supplies in the store: nothing ordered yet")
	for what: String in needs:
		stock.deposit(TOWN, what, int(needs[what]), "test")
	work.pay("mm2", 100, "test")
	var gold := stock.count(TOWN, "gold")
	_now += day
	towns._huts_turn()
	var job := int(towns._huts[HUT]["job"])
	_check(job != 0 and stock.count(TOWN, "wood") == 0 and stock.count(TOWN, "gold") > gold and not towns.hut(HUT).has("empty_since"),
		"kept again: the supplies bought from the town (%d gold) and the mend ordered" % (stock.count(TOWN, "gold") - gold))
	var worked_by := ""
	for i in 400:
		_now += World.WORLD_TICK_STEPS
		work.tick()
		if not work.job(job).is_empty():
			worked_by = str(work.job(job)["worker"]) if worked_by.is_empty() else worked_by
		if towns.hut(HUT)["state"] == Towns.STANDING:
			break
	_check(worked_by == "mm2", "the keeper works the mend himself (%s)" % worked_by)
	_check(towns.hut(HUT) == {"state": Towns.STANDING, "level": 1} and told["n"] == 3, "mended: standing again (%s)" % [towns.hut(HUT)])
	# A second Towns takes over the production's hooks: last.
	var saved := Towns.new({}, work, _rules, clock)
	saved.huts_from_dict(JSON.parse_string(JSON.stringify(towns.huts_to_dict())))
	_check(saved.hut(HUT) == towns.hut(HUT), "kept in the save")


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
	# A bunch of herbs banked (items' herbs, 501 amended): only the medicine
	# man buys herbs (562, Jeff: "other npcs don't find herbs useful"), so the
	# town banks them unpaid.
	stock.deposit(TOWN, "gold", 100)
	var owed_before := economy.owed_to("p1", TOWN)
	_check(Items.yield_of("herbs") == {"herbs": 1} and economy.bank_sale(TOWN, "p1", Items.yield_of("herbs")) == 0
		and economy.owed_to("p1", TOWN) == owed_before, "a bunch of herbs banked at the town: nothing paid, nothing owed")
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

## A founding town's caravan keeps its stores (652, the coordinator's
## ruling): food's comfort is comfort_per_head x its people, and till the
## first harvest is in it keeps founding.keep_days of food a head; after,
## the surplus over comfort may go.
func _test_founding_caravan() -> void:
	print("
== a founding town's caravan keeps its food ==")
	_now = 0
	var clock := func() -> int: return _now
	var stock := Stockpile.new({}, clock, ItemBook.new(clock))
	var work := Production.new({}, stock, null, clock, _rules)
	var economy := Economy.new({}, stock, work, clock, _rules)
	var towns := Towns.new({}, work, _rules, clock)
	economy.before_harvest = towns.before_harvest
	var way := {"id": "r1", "market": "market:castle", "eta": 20, "risk": 0.0}
	economy.trade_routes = func(_town: String) -> Array: return [way]
	var sent: Array = []
	economy.send_caravan = func(_route_id: String, cargo: Dictionary, _from_end: String) -> String:
		sent.append(cargo.duplicate(true))
		return "c%d" % sent.size()
	for i in 12:
		work.add_worker("w%d" % i, "Folk%d" % i, ["hauler"], TOWN, "test", "steady")
	_check(work.comfort(TOWN, "food") == maxi(int(_rules["comfort"]["food"]), ceili(float(_rules["comfort_per_head"]["food"]) * 12)),
		"food's comfort scales with its people (%d for 12)" % work.comfort(TOWN, "food"))
	towns._found(TOWN)
	var food := stock.count(TOWN, "food")
	_now = DayNight.day_steps
	economy._trade_turn([TOWN])
	var keep := int(_rules["founding"]["keep_days"]) * 12
	_check(sent.all(func(cargo: Dictionary) -> bool: return not cargo["goods"].has("food")) or stock.count(TOWN, "food") >= keep,
		"day 0 of a founding town: no food sold under a month's a head (%d of %d left, %s)" % [stock.count(TOWN, "food"), food, sent])
	stock.deposit(TOWN, "food", keep + 30 - stock.count(TOWN, "food"))
	sent.clear()
	for id in work.worker_ids(TOWN):
		work.set_away(id, false)
	economy._send_caravan(TOWN, way)
	_check(stock.count(TOWN, "food") >= keep, "before the first harvest a caravan leaves %d food (%d)" % [keep, stock.count(TOWN, "food")])
	towns._town(TOWN)["harvests"] = 1
	_check(not towns.before_harvest(TOWN), "the first harvest in")
	sent.clear()
	for id in work.worker_ids(TOWN):
		work.set_away(id, false)
	economy._send_caravan(TOWN, way)
	_check(sent.size() == 1 and sent[0]["goods"].has("food"), "after it, the food over comfort may go (%s)" % [sent])


## Caravans to market (decision 504, economy's side): the surplus the
## market wants most goes with a hauler when it pays; sold whole to the
## treasury less the trip wages; some bought home; the market's price
## falls with what it bought; a raid takes the people, never gold.
func _test_caravan() -> void:
	print("
== a caravan to market ==")
	_now = 0
	var clock := func() -> int: return _now
	var stock := Stockpile.new({}, clock, ItemBook.new(clock))
	var work := Production.new({}, stock, null, clock, _rules)
	var economy := Economy.new({}, stock, work, clock, _rules)
	var rule: Dictionary = _rules["trade"]["caravan"]
	var eta := 20
	var way := {"id": "r1", "market": "market:castle", "eta": eta, "risk": 0.0}
	economy.trade_routes = func(_town: String) -> Array: return [way]
	var sent: Array = []
	economy.send_caravan = func(route_id: String, cargo: Dictionary, from_end: String) -> String:
		sent.append([route_id, cargo.duplicate(true), from_end])
		return "c%d" % sent.size()
	stock.deposit(TOWN, "leather", 20)
	stock.deposit(TOWN, "wood", 40)
	economy._trade_turn([TOWN])
	_check(sent.is_empty(), "nobody to go: no caravan")
	work.add_worker("h1", "Ash", ["hauler"], TOWN, "test", "steady")
	_now = DayNight.day_steps
	economy._trade_turn([TOWN])
	var load := int(rule["load"])
	_check(sent.size() == 1 and sent[0][1]["goods"] == {"leather": load} and sent[0][1]["members"] == ["h1"] and sent[0][2] == TOWN
		and stock.count(TOWN, "leather") == 20 - load and bool(work.worker("h1")["away"]),
		"the leather the market wants most goes, %d a member, the hauler away (%s)" % [load, sent])
	economy._trade_turn([TOWN])
	_now += DayNight.day_steps
	economy._trade_turn([TOWN])
	_check(sent.size() == 1, "one caravan out at a time")
	var before := economy.market_price("market:castle", "leather", 0.0)
	var proceeds := economy._sale_of("market:castle", "leather", load, 0.0)
	var wage := economy._trip_wage(eta)
	var treasury := stock.count(TOWN, "gold")
	var sold: Array = []
	economy.caravan_sold.connect(func(id: String, town: String, market: String, gold: int, paid: int) -> void: sold.append([id, town, market, gold, paid]))
	economy.caravan_arrived("c1", "r1", "market:castle", sent[0][1])
	_check(int(work.worker("h1")["purse"]) == wage, "the hauler paid the trip's wage (%d)" % wage)
	_check(sold == [["c1", TOWN, "market:castle", proceeds, wage]], "caravan_sold says what it fetched (%s)" % [sold])
	_check(sent.size() == 2 and sent[1][2] == "market:castle" and sent[1][1]["members"] == ["h1"], "sets out home (%s)" % [sent[-1]])
	var home: Dictionary = sent[1][1]["goods"]
	var spent := 0
	for what: String in home:
		spent += ceili(int(home[what]) * float(_rules["value"][what]) * float(rule["sell"]))
	_check(stock.count(TOWN, "gold") - treasury == proceeds - wage - spent and proceeds - wage - spent > 0,
		"sold for %d: %d to the treasury, untaxed, after the wage and %s bought" % [proceeds, proceeds - wage - spent, home])
	_check(economy.market_price("market:castle", "leather", 0.0) < before, "the market pays less for leather now (%.2f < %.2f)" % [economy.market_price("market:castle", "leather", 0.0), before])
	var had := {}
	for what: String in home:
		had[what] = stock.count(TOWN, what)
	economy.caravan_arrived("c2", "r1", TOWN, sent[1][1])
	_check(not bool(work.worker("h1")["away"]) and home.keys().all(func(what: String) -> bool: return stock.count(TOWN, what) == int(had[what]) + int(home[what]))
		and economy.caravans().is_empty(), "home: unloaded, the hauler back")
	way["eta"] = 20000
	_now += DayNight.day_steps
	economy._trade_turn([TOWN])
	_check(sent.size() == 2, "a road too long to pay its wages: no caravan")
	way["eta"] = eta
	_now += DayNight.day_steps
	economy._trade_turn([TOWN])
	var gold_before := stock.count(TOWN, "gold")
	economy.caravan_raided("c3", "r1", "camp:x", {"goods": {}, "members": ["h1"]})
	economy.caravan_lost("c3", "r1", "taken")
	_check(sent.size() == 3 and economy.caravans().is_empty() and stock.count(TOWN, "gold") == gold_before, "struck and lost: its goods gone, no gold lost")
	_check(economy.is_food("meat") and economy.is_food("ration") and not economy.is_food("leather"), "food is food, meat and things tagged food")
	# The hides the inn's lacking leather is made from stay home.
	work.add_worker("h2", "Bea", ["hauler"], TOWN, "test", "steady")
	stock.take(TOWN, "leather", stock.count(TOWN, "leather"))
	stock.take(TOWN, "wood", stock.count(TOWN, "wood"))
	stock.deposit(TOWN, "hide", 20)
	economy.shortfall = func(_town: String) -> Dictionary: return {"kind": "inn", "job": 0, "steps": 0, "needs": {"leather": 3}}
	_now += DayNight.day_steps
	economy._trade_turn([TOWN])
	var kept := maxi(int(_rules.get("comfort", {}).get("hide", 0)), int(rule["keep"])) + 2 * 3
	_check(sent.size() == 4 and sent[3][1]["goods"] == {"hide": 20 - kept}, "the hides for the inn's leather kept: %d sent (%s)" % [20 - kept, sent[-1]])

func _test_luxury() -> void:
	print("\n== luxuries for the rich (514) ==")
	_now = 0
	var clock := func() -> int: return _now
	var stock := Stockpile.new({}, clock, ItemBook.new(clock))
	var work := Production.new({}, stock, null, clock, _rules)
	var economy := Economy.new({}, stock, work, clock, _rules)
	var cat: Dictionary = economy.catalog.call()
	_check(economy.is_luxury("wine") and economy.is_luxury("silver_ring") and not economy.is_luxury("leather")
		and Economy.goods_class("wine") == "luxury", "wine and the ring are luxuries, taxed as such")
	var eta := 20
	var way := {"id": "r1", "market": "market:castle", "eta": eta, "risk": 0.0}
	economy.trade_routes = func(_town: String) -> Array: return [way]
	var sent: Array = []
	economy.send_caravan = func(route_id: String, cargo: Dictionary, from_end: String) -> String:
		sent.append([route_id, cargo.duplicate(true), from_end])
		return "c%d" % sent.size()
	work.add_worker("h1", "Ash", ["hauler"], TOWN, "test", "steady")
	work.add_worker("m1", "Snagfin", ["merchant"], TOWN, "test", "merchant")
	work.add_worker("c1", "Pell", ["carpenter"], TOWN, "test", "steady")
	work.add_worker("s1", "Odo", ["smith"], TOWN, "test", "steady")
	work.add_worker("p1", "Nix", ["hauler"], TOWN, "test", "steady")
	stock.deposit(TOWN, "food", 60)
	stock.deposit(TOWN, "gold", 100)
	work.pay("m1", 40, "test")
	_now = DayNight.day_steps
	economy._trade_turn([TOWN])
	_check(sent.size() == 1 and economy.caravans()["c1"].get("order", {}).is_empty(), "nobody rich: nothing ordered")
	economy.caravan_arrived("c1", "r1", "market:castle", sent[0][1])
	economy.caravan_arrived("c2", "r1", TOWN, sent[1][1])
	work.pay("c1", 300, "test")
	work.pay("s1", 300, "test")
	var cost := economy.landed_cost("spice", eta)
	var treasury := stock.count(TOWN, "gold")
	_now += DayNight.day_steps
	economy._trade_turn([TOWN])
	var order: Dictionary = economy.caravans()["c3"].get("order", {})
	_check(order.get("id", "") == "spice" and int(order["cost"]) == cost and int(work.worker("m1")["purse"]) == 40 - cost
		and stock.count(TOWN, "gold") == treasury + cost, "the rich in town: the merchant orders a spice for %d, paid into the treasury (%s)" % [cost, order])
	economy.caravan_arrived("c3", "r1", "market:castle", sent[2][1])
	_check(sent[3][1]["goods"].get("spice", 0) == 1, "the caravan brings it home (%s)" % [sent[3][1]])
	economy.caravan_arrived("c4", "r1", TOWN, sent[3][1])
	var shelf := stock.shop(TOWN)
	_check(shelf.size() == 1 and stock.book.id_of(shelf[0]) == "spice" and stock.maker_of(TOWN, shelf[0]) == "m1"
		and economy.item_price(TOWN, shelf[0]) >= ceili(cost * float(_rules["luxury"]["markup"])),
		"on the merchant's shelf, asking at least its landed cost x markup (%d)" % economy.item_price(TOWN, shelf[0]))
	var ring := stock.book.mint("silver_ring", "made", TOWN)
	stock.stock_shop(TOWN, ring, "Odo", "s1")
	# The smith never buys his own ring; he buys the spice, the cheaper one he didn't make.
	var spice := shelf[0]
	var asks := economy._folk_price(economy.item_price(TOWN, spice), "s1", "m1")
	var merchant := int(work.worker("m1")["purse"])
	treasury = stock.count(TOWN, "gold")
	_now += 1
	economy._indulge("s1", cat)
	var tax: int = Economy.taxed(asks, "luxury", _rules)[0]
	_check(spice not in stock.shop(TOWN) and ring in stock.shop(TOWN) and int(work.worker("s1")["purse"]) == 300 - asks,
		"the smith buys the spice for %d, not his own ring" % asks)
	var margin_tax := stock.count(TOWN, "gold") - treasury
	_check(margin_tax > 0 and int(work.worker("m1")["purse"]) == merchant + asks - margin_tax and margin_tax < tax,
		"the luxury tax on the merchant's margin only: %d to the treasury, %d his" % [margin_tax, asks - margin_tax])
	_check(not stock.book.has(spice), "the spice is enjoyed, gone from the book")
	_now += 1
	economy._indulge("s1", cat)
	_check(ring in stock.shop(TOWN), "the smith still won't buy his own ring")
	work.pay("p1", 20, "test")
	_now += 1
	economy._indulge("p1", cat)
	_check(ring in stock.shop(TOWN), "a purse of 20 buys no luxury")
	treasury = stock.count(TOWN, "gold")
	_now += 1
	economy._indulge("c1", cat)
	_check(ring not in stock.shop(TOWN) and stock.book.has(ring) and stock.count(TOWN, "gold") > treasury,
		"the carpenter buys the ring and keeps it; its tax to the treasury (%d)" % (stock.count(TOWN, "gold") - treasury))
	var saved := economy.to_dict()
	_check(saved.has("landed"), "landed costs are saved")
	# A commission (514 amended): the merchant broke, the shelf empty.
	work.spend("m1", int(work.worker("m1")["purse"]), "test")
	stock.take(TOWN, "gold", stock.count(TOWN, "gold") - int(_rules.get("gold_floor", 0)))
	_check(economy._commissions.get(TOWN, "") == "s1", "the smith's want that found only his own ring is a commission")
	economy._commissions.erase(TOWN)
	_now += 1
	economy._indulge("c1", cat)
	var pell := int(work.worker("c1")["purse"])
	treasury = stock.count(TOWN, "gold")
	_now += DayNight.day_steps
	economy._trade_turn([TOWN])
	order = economy.caravans()["c5"].get("order", {})
	cost = int(order.get("cost", 0))
	_check(order.get("for", "") == "c1" and int(work.worker("c1")["purse"]) == pell - cost and stock.count(TOWN, "gold") == treasury + cost,
		"the shelf empty and the merchant broke: Pell commissions a %s, paying %d up front (%s)" % [order.get("id", ""), cost, order])
	economy.caravan_arrived("c5", "r1", "market:castle", sent[4][1])
	merchant = int(work.worker("m1")["purse"])
	pell = int(work.worker("c1")["purse"])
	treasury = stock.count(TOWN, "gold")
	economy.caravan_arrived("c6", "r1", TOWN, sent[5][1])
	var rest := pell - int(work.worker("c1")["purse"])
	var cut := stock.count(TOWN, "gold") - treasury
	_check(stock.shop(TOWN).size() == 0 and rest > 0 and cut > 0 and int(work.worker("m1")["purse"]) == merchant + rest - cut,
		"home, it's Pell's: %d more, %d to Snagfin and %d tax to the treasury" % [rest, rest - cut, cut])


## The treasury pays first those it owes for what the next build lacks
## (522 amended): the tanner before the weaver while the inn waits on
## leather.
func _test_head_first() -> void:
	print("
== the head build's suppliers paid first ==")
	_now = 0
	var clock := func() -> int: return _now
	var stock := Stockpile.new({}, clock, ItemBook.new(clock))
	var work := Production.new({}, stock, null, clock, _rules)
	var economy := Economy.new({}, stock, work, clock, _rules)
	var towns := Towns.new({}, work, _rules, clock)
	economy.shortfall = towns.shortfall
	var floor_gold := int(_rules["gold_floor"])
	stock.deposit(TOWN, "gold", floor_gold)
	work.add_worker("a1", "Wenna", ["weaver"], TOWN, "test", "steady")
	work.add_worker("z1", "Hew", ["tanner"], TOWN, "test", "steady")
	work.order_build(TOWN, "inn", "carpenter", {"wood": 0, "leather": 5}, 1200)
	economy.deliver(TOWN, "a1", "cloth", 3, "test")
	economy.deliver(TOWN, "z1", "leather", 1, "test")
	var weaver := int(work.worker("a1")["owed"])
	var tanner := int(work.worker("z1")["owed"])
	_check(weaver > 0 and tanner > 0, "the treasury at its floor: both owed (weaver %d, tanner %d)" % [weaver, tanner])
	stock.deposit(TOWN, "gold", tanner)
	_now += 1
	economy.tick()
	_check(int(work.worker("z1")["owed"]) == 0 and int(work.worker("a1")["owed"]) == weaver,
		"gold comes in: the tanner, whose leather the inn lacks, is paid first; the weaver waits (%d, %d)" % [int(work.worker("z1")["owed"]), int(work.worker("a1")["owed"])])


## While the next build lacks a raw, its maker makes it on the town's
## account (522 amended (2)): materials from the store at no charge, the
## raw the town's, a wage for the work; a broke tanner still makes the
## inn's leather.
func _test_account() -> void:
	print("
== made on the town's account for its build ==")
	_now = 0
	var clock := func() -> int: return _now
	var stock := Stockpile.new({}, clock, ItemBook.new(clock))
	var work := Production.new({}, stock, null, clock, _rules)
	var economy := Economy.new({}, stock, work, clock, _rules)
	var towns := Towns.new({}, work, _rules, clock)
	work.deliver = economy.deliver
	work.buy_materials = economy.buy_materials
	work.build_lacks = func(town: String) -> Dictionary: return towns.shortfall(town).get("needs", {})
	work.town_pays = economy.owe_or_pay
	economy.shortfall = towns.shortfall
	var floor_gold := int(_rules["gold_floor"])
	stock.deposit(TOWN, "gold", floor_gold + 50)
	stock.deposit(TOWN, "hide", 4)
	work.add_worker("t1", "Hew", ["tanner"], TOWN, "test", "steady")
	work.set_loan("t1", float(_rules["bank"]["cap"]))
	work.add_workshop("%s:tannery" % TOWN, "tanner", TOWN)
	work.assign("%s:tannery" % TOWN, "t1")
	towns._town(TOWN)["buildings"]["tannery"] = {"kind": "tannery", "level": 1, "state": Towns.STANDING, "since": 0, "job": 0}
	for i in 10:
		_now += 300
		work.tick()
	_check(stock.count(TOWN, "leather") == 0, "no build waiting: a tanner at his loan cap makes nothing (he can't buy hides)")
	work.order_build(TOWN, "inn", "carpenter", {"wood": 0, "leather": 5}, 1200)
	var gold := stock.count(TOWN, "gold")
	for i in 20:
		_now += 300
		work.tick()
	var wage := int(_rules["store"]["account_wage"])
	_check(stock.count(TOWN, "leather") == 2 and stock.count(TOWN, "hide") == 0, "the inn lacks leather: he makes it from the store's hides (%d leather)" % stock.count(TOWN, "leather"))
	_check(int(work.worker("t1")["purse"]) == 2 * wage and stock.count(TOWN, "gold") == gold - 2 * wage,
		"paid %d a piece for the work, by the treasury; nothing for the leather, the town's" % wage)
	# The hooks hold economy and towns, which hold the production: let go, or they outlive the test.
	work.build_lacks = Callable()
	work.town_pays = Callable()


## A living for the trades that need one (decision 528): the store never
## buys a maker's raw for less than its inputs and a margin; the wage
## floor tops a day up; a service earned by the rich is taxed higher.
func _test_livings() -> void:
	print("
== livings ==")
	_now = 0
	var clock := func() -> int: return _now
	var stock := Stockpile.new({}, clock, ItemBook.new(clock))
	var work := Production.new({}, stock, null, clock, _rules)
	var economy := Economy.new({}, stock, work, clock, _rules)
	var floor_gold := int(_rules["gold_floor"])
	stock.deposit(TOWN, "gold", floor_gold + 200)
	stock.deposit(TOWN, "leather", 40)  # Plenty: the want's price is low.
	work.add_worker("t1", "Hew", ["tanner"], TOWN, "test", "steady")
	work.add_worker("h1", "Hob", ["hunter"], TOWN, "test", "steady")
	var sell := float(_rules["store"]["sell"])
	var hides := float(economy.raw_price(TOWN, "hide")) * sell * 2 + int(_rules["store"]["make_margin"])
	_check(is_equal_approx(economy.maker_floor(TOWN, "t1", "leather"), hides) and economy.maker_floor(TOWN, "h1", "hide") == 0.0,
		"the tanner's leather: no less than two hides at the store and the margin (%.1f); the hunter's hide: no floor" % hides)
	var purse := int(work.worker("t1")["purse"])
	economy.deliver(TOWN, "t1", "leather", 1, "test")
	_check(int(work.worker("t1")["purse"]) - purse >= floori(hides) and economy.raw_price(TOWN, "leather") < hides,
		"a full store wants little leather, but he is paid %d, not %d" % [int(work.worker("t1")["purse"]) - purse, economy.raw_price(TOWN, "leather")])
	# B: the wage floor.
	work.add_worker("s1", "Bryn", ["shepherd"], TOWN, "test", "steady")
	work.take_earned("t1")
	economy._floor_turn()
	work.note_earned("s1", 1)
	_now += DayNight.day_steps
	purse = int(work.worker("s1")["purse"])
	economy._floor_turn()
	var floor_day := int(_rules["wage_floor"]["gold"])
	_check(int(work.worker("s1")["purse"]) - purse == floor_day - 1, "a shepherd who earned 1 in a day: the town pays him %d more" % (floor_day - 1))
	_check(int(work.worker("h1")["purse"]) == 0, "the hunter's trade has no floor")
	stock.take(TOWN, "gold", stock.count(TOWN, "gold") - floor_gold)
	_now += DayNight.day_steps
	economy._floor_turn()
	_check(int(work.worker("s1")["owed"]) == floor_day, "the treasury at its floor: the day's floor owed him (%d)" % int(work.worker("s1")["owed"]))
	# C: the service tax by the earner's purse.
	work.add_worker("c1", "Pell", ["carpenter"], TOWN, "test", "steady")
	var gold := stock.count(TOWN, "gold")
	economy._pay(TOWN, "c1", 10, "trade", "test")
	var poor := stock.count(TOWN, "gold") - gold
	work.pay("c1", 100, "test")
	gold = stock.count(TOWN, "gold")
	economy._pay(TOWN, "c1", 10, "trade", "test")
	var rich := stock.count(TOWN, "gold") - gold
	_check(poor == 1 and rich == 5, "a service fee taxed 0.1 for a purse under luxury.above, 0.5 above it (528 amended (2): Jeff's \"rich tax can be 50%%\") (%d, %d)" % [poor, rich])
	# The officials first (528 amended): a wage the treasury can't pay is owed, and paid before anyone's.
	stock.take(TOWN, "gold", stock.count(TOWN, "gold") - floor_gold)
	work.add_worker("g1", "Gar", ["guard"], TOWN, "test", "steady")
	var wage := int(_rules["official"]["guard"]["wage"])
	var every := int(_rules["official"]["guard"]["every"])
	work._official_wages(_now)
	work._official_wages(_now + every)
	_check(int(work.worker("g1")["owed"]) == wage, "the guard's wage at the floor: owed him (%d), not lost" % int(work.worker("g1")["owed"]))
	stock.deposit(TOWN, "gold", wage)
	var shepherd := int(work.worker("s1")["owed"])
	economy._pay_head_first()
	_check(int(work.worker("s1")["owed"]) == shepherd, "gold comes in: the guard's debt paid before the shepherd's")
	_check(int(work.worker("g1")["owed"]) == 0 and int(work.worker("g1")["purse"]) == wage, "the guard paid what he was owed, first")


## The temple's offering (decision 546): a player brought back pays it
## into the alms, waived by the draugr's mark; the alms pay the priest's
## wage first, the rest is the altar's gold, taken down and laid below.
func _test_offering() -> void:
	print("
== the temple's offering ==")
	_now = 0
	var clock := func() -> int: return _now
	var stock := Stockpile.new({}, clock, ItemBook.new(clock))
	var work := Production.new({}, stock, null, clock, _rules)
	var economy := Economy.new({}, stock, work, clock, _rules)
	work.wage_from = economy.wage_from_alms
	var offering := int(_rules["return"]["offering"])
	economy.add_gold("p1", 20)
	economy.add_gold("p2", 3)
	_check(economy.temple_offering(TOWN, "p1", false) == offering and economy.gold("p1") == 20 - offering and economy.alms(TOWN) == offering,
		"brought back at the temple: %d gold into the alms" % offering)
	_check(economy.temple_offering(TOWN, "p2", false) == 3 and economy.gold("p2") == 0, "one holding less pays what they hold")
	_check(economy.temple_offering(TOWN, "p1", true) == 0 and economy.gold("p1") == 20 - offering, "the draugr's mark: no offering")
	work.add_worker("pr", "Aldous", ["priest"], TOWN, "test", "steady")
	var wage := int(_rules["official"]["priest"]["wage"])
	var alms := economy.alms(TOWN)
	_check(economy.altar_gold(TOWN) == alms - wage, "the altar's gold: the alms less a day of the priest's wage (%d)" % economy.altar_gold(TOWN))
	var treasury := stock.count(TOWN, "gold")
	work._official_wages(_now)
	work._official_wages(_now + int(_rules["official"]["priest"]["every"]))
	_check(int(work.worker("pr")["purse"]) == wage and stock.count(TOWN, "gold") == treasury and economy.alms(TOWN) == alms - wage,
		"the priest paid from the alms, not the treasury")
	var taken := economy.take_altar(TOWN)
	_check(taken == alms - 2 * wage and economy.alms(TOWN) == wage and economy.last_down_day(TOWN) == -1,
		"a run takes the altar's gold (%d), a day of the priest's wage kept back" % taken)
	_now = 3 * DayNight.day_steps
	economy.altar_down(TOWN, taken)
	_check(economy.below_gold(TOWN) == taken and economy.last_down_day(TOWN) == 3, "laid at the altar below on day 3")
	_check(economy.lift_below(TOWN, 100) == taken and economy.below_gold(TOWN) == 0, "robbers lift what is there, no more")
	var saved := Economy.new(economy.to_dict(), stock, work, clock, _rules)
	_check(saved.last_down_day(TOWN) == 3, "saved and loaded")
	# The acolyte lives on the alms after the priest's share (546 amended).
	work.add_worker("ac", "Pip", ["acolyte"], TOWN, "test", "steady")
	var keep := int(_rules["return"]["acolyte"]["keep"])
	economy._alms[TOWN] = wage + 2 * keep
	economy._floor_turn()
	_now += DayNight.day_steps
	economy._floor_turn()
	_check(int(work.worker("ac")["purse"]) == keep and economy.alms(TOWN) == wage + keep, "the acolyte kept %d a day from the alms" % keep)
	_now += DayNight.day_steps
	economy._floor_turn()
	_check(int(work.worker("ac")["purse"]) == 2 * keep and economy.alms(TOWN) == wage, "never from the priest's share (%d left)" % economy.alms(TOWN))
	# The alms short: the treasury keeps him, as it pays the priest.
	var floor := int(_rules.get("gold_floor", 0))
	stock.deposit(TOWN, "gold", floor + 5, "test", "test")
	var before := stock.count(TOWN, "gold")
	_now += DayNight.day_steps
	economy._floor_turn()
	_check(int(work.worker("ac")["purse"]) == 3 * keep and stock.count(TOWN, "gold") == before - keep and economy.alms(TOWN) == wage,
		"the alms short: the treasury keeps him (%d)" % stock.count(TOWN, "gold"))
	stock.take(TOWN, "gold", stock.count(TOWN, "gold") - floor, "test")
	_now += DayNight.day_steps
	economy._floor_turn()
	_check(int(work.worker("ac")["purse"]) == 3 * keep and int(work.worker("ac").get("owed", 0)) == keep, "the treasury at its floor: owed him")


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
