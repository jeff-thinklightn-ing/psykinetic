extends Node
## Prices, players' gold and trade with the town (Economy, decision 280).
## First on a clock of its own with a test catalog and rules: what things
## are worth (a catalog value, what they are made of and the work in them, a
## yield); dearer when the town is short, cheaper with plenty; a purchase
## paid from the player's gold, the sale tax to the treasury and the rest to
## the resident who made it; the town buying only what it is short of, at
## half its price less the buy tax, and never below its gold floor; gold
## never taken but by buying; a restart keeps it. Then in a test town (made
## in code) with a shop counter: the panel shows the goods and the gold, the
## host buys a bandaging kit into the pack, sells a sack of ore by putting
## it in the counter, and is told why the town won't take a coin purse.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const TOWN := "ec/store"
const CATALOG := {
	"sword": {"id": "sword", "tags": ["weapon"], "made": {"by": "smith", "from": {"ore": 3, "wood": 1}, "steps": 3000}},
	"crown": {"id": "crown", "tags": ["goods"], "value": 40},
	"ore_sack": {"id": "ore_sack", "tags": ["resource"], "yield": {"ore": 5}},
	"coin_purse": {"id": "coin_purse", "tags": ["resource"], "yield": {"gold": 10}},
}
const RULES := {
	"window": 6000, "tier_hold": 2, "starve_after": 3,
	"comfort": {"gold": 50, "ore": 20, "wood": 5, "cloth": 2, "food": 4},
	"wants": {"weapon": 2},
	"tiers": {}, "work_up": {}, "busy": {"quiet_below": 0, "busy_from": 100000},
	"tax": {"sale": 0.2, "buy": 0.1},
	"gold_floor": 20,
	"value": {"gold": 1, "food": 1, "wood": 1, "ore": 2, "cloth": 3},
	"labour": 1,
	"trade": {"buy_ratio": 0.5, "min_factor": 0.5, "max_factor": 2.0},
}

const ZONE := "ec_town"
const STORE := "ec_town/store"

var _failures := 0
var _now := 0
var _main: Node


func _ready() -> void:
	World.set_process(false)
	_test_prices()
	_test_buying()
	_test_selling()
	_test_counter_raws()
	_test_barter()
	_test_vendor()
	_test_camp_traders()
	_test_ponds()
	_test_maker_barter()
	_test_barrow_charges()
	_test_robbers_band()
	_test_restart()
	_test_give_gold()
	await _test_in_town()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _fresh() -> Economy:
	_now = 0
	var clock := func() -> int: return _now
	var book := ItemBook.new(clock)
	var stock := Stockpile.new({}, clock, book)
	stock.deposit(TOWN, "gold", 100, "test")
	var work := Production.new({}, stock, null, clock, RULES, func() -> Dictionary: return CATALOG)
	work.add_worker("bram", "Bram", ["smith"], TOWN, "rescued:bram")
	return Economy.new({}, stock, work, clock, RULES, func() -> Dictionary: return CATALOG)


func _shop_sword(economy: Economy) -> int:
	var uid := economy.stockpile.book.mint("sword", "made", "Bram at the forge")
	economy.stockpile.stock_shop(TOWN, uid, "Bram", "bram")
	return uid


func _test_prices() -> void:
	print("\n== what things are worth, and the town's need ==")
	var economy := _fresh()
	_check(economy.value_of("sword") == 12, "a sword: 3 ore (6) and a wood (1) and 3000 steps of work (5): 12 (%d)" % economy.value_of("sword"))
	_check(economy.value_of("crown") == 40 and economy.value_of("ore_sack") == 10 and economy.value_of("nothing") == 1,
		"a catalog value stands; a sack of 5 ore is worth 10; an unknown thing 1")
	_check(economy.price("ec/store", "sword") == 24, "no swords at all, 2 wanted: twice its value, 24 (%d)" % economy.price(TOWN, "sword"))
	_shop_sword(economy)
	_check(economy.price(TOWN, "sword") == 18, "one of two: half short, 18 (%d)" % economy.price(TOWN, "sword"))
	_shop_sword(economy)
	_check(economy.price(TOWN, "sword") == 12, "two of two: its value, 12")
	_shop_sword(economy)
	_shop_sword(economy)
	_check(economy.price(TOWN, "sword") == 6, "four, twice what it wants: half, 6 (%d)" % economy.price(TOWN, "sword"))
	_check(economy.price(TOWN, "crown") == 20, "a crown the town doesn't want: half its value, 20")
	_check(economy.price(TOWN, "ore_sack") == 20 and economy.price(TOWN, "ore_sack", Economy.BUY) == 10,
		"no ore, 20 wanted: a sack sells at 20, the town pays 10 before tax")


func _test_buying() -> void:
	print("\n== a player buys from the shop ==")
	var economy := _fresh()
	var uid := _shop_sword(economy)
	var deal := economy.buy("p1", TOWN, uid)
	_check(not deal["ok"] and economy.stockpile.shop(TOWN).has(uid), "no gold: refused, the sword stays (%s)" % [deal])
	_check(economy.add_gold("p1", 50, "purse") == 50, "a purse opened: 50 gold")
	_now = 700
	deal = economy.buy("p1", TOWN, uid)
	_check(deal["ok"] and deal["price"] == 18 and economy.gold("p1") == 32, "bought at 18: 32 left (%s, %d)" % [deal, economy.gold("p1")])
	_check(economy.materials("sword") == 7 and economy.stockpile.count(TOWN, "gold") == 109 and int(economy.production.worker("bram")["purse"]) == 9,
		"its materials (7: 3 ore, a wood) and the sale tax on the rest (2) to the treasury, 9 to Bram who made it (decision 353 amended; %d, %s)" % [economy.stockpile.count(TOWN, "gold"), economy.production.worker("bram")])
	_check(not economy.stockpile.shop(TOWN).has(uid) and economy.stockpile.book.at_of(uid) == ""
		and economy.stockpile.book.history(uid)["events"].any(func(event: Dictionary) -> bool: return event["kind"] == "bought"),
		"out of the shop, held by nothing until put somewhere, its history says bought")
	_check(economy.production.signals_of(TOWN, CATALOG)["sold"] == {"sword": 1}, "the town notes the sale (its workshops work it up)")
	_check(not economy.buy("p1", TOWN, uid)["ok"], "it can't be bought twice")
	var bought := economy.stockpile.book.mint("crown", "found", "test")
	economy.stockpile.stock_shop(TOWN, bought, "sold:p2")
	economy.buy("p1", TOWN, bought)
	_check(economy.stockpile.count(TOWN, "gold") == 129 and economy.gold("p1") == 12,
		"a crown no resident made (the town bought it): all 20 to the treasury")
	_check(economy.add_gold("p1", -50, "a test") == 0, "gold never goes below none")


## The counter buys meat and hides as the depot banks them, up to their
## comfort (652 amended (3), economy.json's own rules); a town short of
## them still counts its store full for its surplus work.
func _test_counter_raws() -> void:
	print("\n== the counter buys meat and hides, up to comfort ==")
	_now = 0
	var clock := func() -> int: return _now
	var rules := Production.read_rules(Economy.PATH)
	var cat := {"meat": {"id": "meat", "tags": ["resource"], "yield": {"meat": 1}},
		"hide": {"id": "hide", "tags": ["resource"], "yield": {"hide": 1}}}
	var catalog := func() -> Dictionary: return cat
	var stock := Stockpile.new({}, clock, ItemBook.new(clock))
	stock.deposit(TOWN, "gold", 500, "test")
	var work := Production.new({}, stock, null, clock, rules, catalog)
	var economy := Economy.new({}, stock, work, clock, rules, catalog)
	var raws := economy.buys(TOWN, ["meat", "hide"])
	_check(raws.has("meat") and int(raws["meat"]["up_to"]) == 20 and raws.has("hide") and int(raws["hide"]["up_to"]) == 10,
		"none in store: the counter buys meat up to 20, hides up to 10 (%s)" % [raws])
	stock.deposit(TOWN, "meat", 20, "test")
	_check(economy.refuses(TOWN, "meat") == "the town has enough of that" and economy.refuses(TOWN, "hide").is_empty(),
		"20 meat in store: no more meat; a hide still")
	for what: String in rules["comfort"]:
		if what not in ["meat", "hide"]:
			stock.deposit(TOWN, what, maxi(work.comfort(TOWN, what) - stock.count(TOWN, what), 0), "test")
	stock.take(TOWN, "meat", 20, "test")
	_check(work.signals_of(TOWN, cat)["full"], "every other raw at comfort, no meat or hides: the store still counts full (its surplus work goes on)")


func _test_selling() -> void:
	print("\n== the town buys what it is short of ==")
	var economy := _fresh()
	var deal := economy.sell("p1", TOWN, "ore_sack")
	_check(deal["ok"] and deal["paid"] == 9 and economy.gold("p1") == 9 and economy.stockpile.count(TOWN, "gold") == 91,
		"no ore: a sack bought for 10, 1 kept as the buy tax, 9 paid (%s)" % [deal])
	_check(economy.refuses(TOWN, "crown") == "the town has enough of that", "a crown it doesn't want: refused")
	_check(economy.refuses(TOWN, "coin_purse").begins_with("gold is given"), "a coin purse: given, not sold")
	_check(economy.offers(TOWN, ["ore_sack", "crown", "", "ore_sack", "sword"]) == {"ore_sack": 9, "sword": 11},
		"what it would pay for what a player carries: ore 9, a sword 11 (%s)" % [economy.offers(TOWN, ["ore_sack", "crown", "sword"])])
	economy.stockpile.deposit(TOWN, "ore", 20, "test")
	_check(not economy.sell("p1", TOWN, "ore_sack")["ok"], "with 20 ore, it has enough")
	economy.stockpile.take(TOWN, "ore", 20, "test")
	economy.stockpile.take(TOWN, "gold", 65, "test")
	_check(economy.stockpile.count(TOWN, "gold") == 26 and economy.refuses(TOWN, "ore_sack").is_empty(),
		"26 gold, a floor of 20: it still buys ore (826: never \"can't pay\")")
	economy.stockpile.take(TOWN, "gold", 22, "test")
	var short := economy.sell("p1", TOWN, "ore_sack")
	var credit_most := int(economy.rules.get("trade_credit", {}).get("most", 120))
	var per_day := int(economy.rules.get("trade_credit", {}).get("per_day", 60))
	_check(short["ok"] and int(short["paid"]) == 9 and economy.stockpile.count(TOWN, "gold") == 4 and economy.trade_debt(TOWN) == 0
		and economy.trade_purse(TOWN) == credit_most - 9,
		"4 gold in the treasury, under its floor: the sack paid 9 in full from the trade's credit, the town's own gold untouched (%s, credit %d)" % [short, economy.trade_purse(TOWN)])
	economy._trade_purse[TOWN]["gold"] = 0
	economy.sell("p1", TOWN, "ore_sack")
	_check(economy.trade_debt(TOWN) == 9 and economy.gold("p1") >= 18, "its credit spent: still paid in full, a debt of 9 booked")
	_now += DayNight.day_steps
	economy._repay_trade()
	_check(economy.trade_debt(TOWN) == 0 and economy.trade_purse(TOWN) == per_day - 9 and economy.stockpile.count(TOWN, "gold") == 4,
		"a day on: the refill pays the debt first, %d left in credit, the town's gold untouched" % economy.trade_purse(TOWN))


## The starter vendor (736): one of the wares at vendor.price from the
## purse, the gold to nobody (no treasury), how many one buys; refused
## without the gold or for what it doesn't sell.
func _test_vendor() -> void:
	print("
== the starter vendor: 1 gold, to nobody ==")
	var economy := _fresh()
	economy.rules = economy.rules.duplicate(true)
	economy.rules["vendor"] = Production.read_rules()["vendor"]
	economy.add_gold("p1", 3, "test")
	var treasury := economy.stockpile.count(TOWN, "gold")
	var sale := economy.vendor_sale("p1", "arrows")
	_check(sale["ok"] and int(sale["gold"]) == 1 and int(sale["count"]) == 1 and economy.gold("p1") == 2
		and economy.stockpile.count(TOWN, "gold") == treasury, "arrows for 1 gold, a bundle, no treasury's (%s)" % [sale])
	_check(not economy.vendor_sale("p1", "crown")["ok"] and economy.gold("p1") == 2, "not one of its wares: refused")
	_check(not economy.vendor_sale("p2", "sword")["ok"] and economy.gold("p2") == 0, "no gold: refused")
	economy.add_gold("p1", 1, "test")
	var rod := economy.vendor_sale("p1", "fishing_rod")
	_check(rod["ok"] and int(rod["gold"]) == 3 and economy.gold("p1") == 0, "Rolf's fishing rod: 3 gold (805; %s)" % [rod])
	economy.add_gold("p1", 8, "test")
	var cloak := economy.vendor_sale("p1", "cloak")
	_check(cloak["ok"] and int(cloak["gold"]) == 8 and economy.gold("p1") == 0, "Rolf's woollen cloak: 8 gold (788 amended; %s)" % [cloak])


## A forest camp's trader (799, economy's side): stock drawn from his mix,
## kept until restock_days; sells at value x 1.15 (x 1.5 toll, x 0.8 for his
## freer), buys raws at value x 0.85 while his 30-gold purse lasts, gives his
## freer one ware; saved and loaded.
func _test_camp_traders() -> void:
	print("
== a camp trader: stock, prices, his purse, the gift (799) ==")
	var economy := _fresh()
	economy.rules = economy.rules.duplicate(true)
	economy.rules["camp_traders"] = Production.read_rules()["camp_traders"]
	economy.catalog = Economy.items_defs
	const CAMP := "forest/test_camp"
	var stock := economy.camp_stock(CAMP, "trader")
	_check(stock.size() >= 5 and stock.size() <= 6, "a trader camp shows 5 or 6 wares (%d)" % stock.size())
	_check(economy.camp_stock(CAMP, "trader") == stock, "asked again the same day: the same stock")
	_check(economy.camp_stock("forest/other_camp", "mixed").size() in [4, 5], "a mixed camp shows 4 or 5")
	_check(economy.camp_price(CAMP, "spice") == 14 and economy.camp_price(CAMP, "spice", true) == 21
		and economy.camp_price(CAMP, "spice", true, true) == 17 and economy.camp_price(CAMP, "spice", false, true) == 11,
		"spice (12): 14, tolled 21, tolled for his freer 17, freer 11")
	var item := str(stock[0]["item"])
	var had := int(stock[0]["count"])
	var cost := economy.camp_price(CAMP, item)
	var treasury := economy.stockpile.count(TOWN, "gold")
	var refused := economy.camp_sale(CAMP, "trader", "p1", item)
	_check(not refused["ok"] and refused["why"] == "gold" and str(refused["say"]).contains(str(cost)), "no gold: refused, the price said (%s)" % [refused])
	economy.add_gold("p1", 100, "test")
	var sold := economy.camp_sale(CAMP, "trader", "p1", item)
	_check(sold["ok"] and int(sold["price"]) == cost and economy.gold("p1") == 100 - cost
		and economy.stockpile.count(TOWN, "gold") == treasury, "bought one %s for %d, no town's gold (%s)" % [item, cost, sold])
	var left := 0
	for line: Dictionary in economy.camp_stock(CAMP, "trader"):
		if line["item"] == item:
			left = int(line["count"])
	_check(left == had - 1, "his stock one fewer (%d of %d)" % [left, had])
	for i in had:
		economy.camp_sale(CAMP, "trader", "p1", item)
	var none := economy.camp_sale(CAMP, "trader", "p1", item)
	_check(not none["ok"] and none["why"] == "stock", "sold out: refused")

	var wont := economy.camp_buy(CAMP, "trader", "p1", "spice", 1)
	_check(not wont["ok"] and wont["why"] == "wont" and int(wont["count"]) == 0, "spice: not a thing he buys")
	var before := economy.gold("p1")
	var hides := economy.camp_buy(CAMP, "trader", "p1", "hide", 20)
	_check(hides["ok"] and int(hides["count"]) == 5 and int(hides["gold"]) == 15 and economy.gold("p1") == before + 15,
		"20 hides at 3: he takes his day's 5, paid in full (826) (%s)" % [hides])
	var enough := economy.camp_buy(CAMP, "trader", "p1", "hide", 1)
	_check(not enough["ok"] and enough["why"] == "enough" and enough["say"] == "I've enough of that for now." and economy.camp_room(CAMP, "trader", "hide") == 0,
		"a sixth hide today: he has enough (%s)" % [enough])
	_check(economy.camp_buy(CAMP, "trader", "p1", "feathers", 30)["count"] == 5 and economy.camp_room(CAMP, "trader", "spice") == 0,
		"feathers: his own day's 5, not held back by the hides; spice he doesn't buy, no room")

	var again := Economy.new(economy.to_dict(), economy.stockpile, economy.production, economy.clock, economy.rules, economy.catalog)
	_check(again.camp_stock(CAMP, "trader") == economy.camp_stock(CAMP, "trader") and not again.camp_buy(CAMP, "trader", "p1", "hide", 1)["ok"],
		"saved and loaded: the same stock, still enough hides today")
	_now += DayNight.day_steps
	_check(economy.camp_room(CAMP, "trader", "hide") == 5, "a day on: he takes 5 hides again (%d)" % economy.camp_room(CAMP, "trader", "hide"))
	var pelt := economy.camp_buy(CAMP, "trader", "p1", "hill_cat_pelt", 1)
	_check(pelt["ok"] and int(pelt["gold"]) == 17 and economy.camp_room(CAMP, "trader", "hill_cat_pelt") == 4,
		"the hill cat's pelt: 17 gold, 4 more today (%s)" % [pelt])

	var gift := economy.camp_gift(CAMP, "trader")
	_check(not gift.is_empty() and economy.value_of(gift) <= 12, "freed, he gives a ware worth 12 at most (%s)" % gift)
	_check(economy.camp_captive(CAMP).is_empty(), "the captive's side is npc's")


## A pond's fish and its wanderer (805): 8 to start, a catch under 0.6
## takes one, refilled 2 a game day up to 8 and saved; a player fishing past
## wanderer.after gets one boar, then nothing more there that game day, and a
## later visit another; the stall's rod at its own price.
func _test_ponds() -> void:
	print("
== a pond: 8 fish, 2 a day back, a boar while you fish (805) ==")
	var economy := _fresh()
	economy.rules = economy.rules.duplicate(true)
	economy.rules["ponds"] = Production.read_rules()["ponds"]
	const POND := "wilds/test_pond"
	_check(economy.pond_fish(POND) == 8, "a new pond holds 8 fish")
	_check(not economy.pond_catch(POND, "p1", 0.7) and economy.pond_fish(POND) == 8, "a roll of 0.7: nothing, the pond keeps its fish")
	for i in 8:
		economy.pond_catch(POND, "p1", 0.1)
	_check(economy.pond_fish(POND) == 0 and not economy.pond_catch(POND, "p1", 0.0), "8 caught: the pond is empty and a good roll catches nothing")
	_now += DayNight.day_steps
	_check(economy.pond_fish(POND) == 2, "a game day on: 2 fish back (%d)" % economy.pond_fish(POND))
	_now += 10 * DayNight.day_steps
	_check(economy.pond_fish(POND) == 8, "ten days on: full at 8, no more")
	economy.pond_catch(POND, "p1", 0.1)
	var again := Economy.new(economy.to_dict(), economy.stockpile, economy.production, economy.clock, economy.rules, economy.catalog)
	_check(again.pond_fish(POND) == 7, "saved and loaded: 7 fish")

	var sent: Array = []
	economy.wanderer_due.connect(func(pond: String, player_id: String, kind: String, at: Vector2i) -> void: sent.append([pond, player_id, kind, at]))
	economy.pond_cast(POND, "p1", Vector2i(32, 116))
	var start := _now
	while _now - start < 1500:
		_now += 300
		economy.pond_cast(POND, "p1")
		economy.tick()
	_check(sent == [[POND, "p1", "boar", Vector2i(32, 116)]], "fishing 2.5 minutes: one boar sent to the cast's cell (%s)" % [sent])
	for i in 6:
		_now += 300
		economy.pond_cast(POND, "p1")
		economy.tick()
	_check(sent.size() == 1, "fishing on: no second one")
	_now += 2000
	economy.tick()
	economy.pond_cast(POND, "p1")
	for i in 6:
		_now += 300
		economy.pond_cast(POND, "p1")
		economy.tick()
	_check(sent.size() == 1, "a new visit the same game day: none")
	_now += DayNight.day_steps
	economy.pond_cast(POND, "p1")
	for i in 6:
		_now += 300
		economy.pond_cast(POND, "p1")
		economy.tick()
	_check(sent.size() == 2 and str(sent[1][2]) in ["boar", "wolf"], "the next game day, a second visit: another (%s)" % [sent])

	economy.rules["vendor"] = {"price": 1, "wares": [{"item": "fishing_rod", "count": 1, "price": 3}, {"item": "arrows", "count": 1}]}
	economy.add_gold("p3", 5, "test")
	var rod := economy.vendor_sale("p3", "fishing_rod")
	_check(rod["ok"] and int(rod["gold"]) == 3 and economy.gold("p3") == 2 and int(economy.vendor_sale("p3", "arrows")["gold"]) == 1,
		"the stall's rod at its own 3 gold, arrows still 1 (%s)" % [rod])


func _test_barter() -> void:
	print("
== barter: what the town takes, how many, grave goods fenced, all or nothing (decision 560) ==")
	var economy := _fresh()
	var offered := economy.buys(TOWN, ["ore_sack", "sword", "crown", "ore_sack"])
	_check(offered == {"ore_sack": {"gold": 9, "up_to": 4}, "sword": {"gold": 11, "up_to": 2}},
		"ore at 9, four sacks to its 20; a sword at 11, two to its want; no crown (%s)" % [offered])
	_check(Economy.fenced(9) == 4 and Economy.fenced(1) == 1, "fenced: half, at least 1")
	var graves := [{"id": "ore_sack"}, {"id": "ore_sack", "fenced": true}]
	_check(economy.barter_quote(TOWN, "p1", graves, [])["why"] == "won't buy that", "grave goods at any counter but the fence's: won't buy (586)")
	_check(economy.barter_quote(TOWN, "p1", graves, [], Economy.FENCE_DAY)["why"] == "not by day", "at the fence's by day: not by day")
	var quote := economy.barter_quote(TOWN, "p1", graves, [], Economy.FENCE_NIGHT)
	_check(quote["ok"] and quote["gives"] == [9, 4] and quote["balance"] == 13, "at the fence's by night: 9 and 4 fenced, 13 to the player (%s)" % [quote])
	var five: Array = []
	for i in 5:
		five.append({"id": "ore_sack"})
	_check(economy.barter_quote(TOWN, "p1", five, [])["why"] == "the town has enough of that", "a fifth sack: past up_to, refused")
	_check(economy.barter_quote(TOWN, "p1", [{"id": "crown"}], [])["why"] == "the town has enough of that", "a crown: refused, the town's own why")
	var sword := _shop_sword(economy)
	quote = economy.barter_quote(TOWN, "p1", [{"id": "ore_sack"}], [sword])
	_check(not quote["ok"] and quote["why"] == "not enough gold (9)", "a sack (9) for a sword (18) with no gold: 9 short (%s)" % [quote])
	quote = economy.barter_quote(TOWN, "p1", [{"id": "ore_sack"}, {"id": "ore_sack"}], [sword])
	_check(quote["ok"] and quote["takes"] == [18] and quote["balance"] == 0, "two sacks for the sword: even (%s)" % [quote])
	_check(economy.barter_quote(TOWN, "p1", [], [sword, sword])["why"] == "that is no longer for sale", "one sword can't be taken twice")
	var sold := economy.sell("p1", TOWN, "ore_sack", false, 9)
	var again := economy.sell("p1", TOWN, "ore_sack", false, 9)
	var bought := economy.buy("p1", TOWN, sword, 18)
	_check(sold["paid"] == 9 and again["paid"] == 9 and bought["ok"] and bought["price"] == 18 and economy.gold("p1") == 0,
		"settled at the quoted prices, though the town's need moved between (%s, %s, %s)" % [sold, again, bought])
	var now_pays := int(economy.offers(TOWN, ["ore_sack"])["ore_sack"])
	_check(economy.sell("p1", TOWN, "ore_sack", true)["why"] == "won't buy that", "a grave goods sack at a counter: won't buy")
	_check(economy.sell("p1", TOWN, "ore_sack", true, -1, Economy.FENCE_NIGHT)["paid"] == Economy.fenced(now_pays),
		"at the fence's counter by night: fenced, half of %d" % now_pays)
	var with_fence: Dictionary = economy.rules.duplicate(true)
	with_fence["fence"] = Production.read_rules(Economy.PATH)["fence"]
	economy.rules = with_fence
	_check(economy.rules["fence"]["by"] == "snagfin" and float(economy.rules["fence"]["factor"]) == 0.5 and float(economy.rules["fence"]["day_markup"]) == 1.3,
		"the fence's rules are economy.json's: Snagfin, half, 1.3 by day")
	var other := _shop_sword(economy)
	_check(economy.goods(TOWN, Economy.FENCE_DAY).filter(func(each: Dictionary) -> bool: return each["uid"] == other)[0]["price"] == ceili(18 * 1.3)
		and economy.goods(TOWN, Economy.FENCE_NIGHT).filter(func(each: Dictionary) -> bool: return each["uid"] == other)[0]["price"] == 18,
		"his goods by day: 18 marked up to %d; by night 18" % ceili(18 * 1.3))
	_check(economy.fence_by() == "", "no Snagfin in this town: no fence")
	economy.production.add_worker("snagfin", "Snagfin", ["merchant"], TOWN, "settled", "merchant")
	_check(economy.fence_by() == "snagfin", "Snagfin in town: the fence")
	economy.production.set_away("snagfin", true)
	_check(economy.fence_by() == "", "Snagfin away: none")
	economy.production.set_away("snagfin", false)
	var night_at := -1
	var noon_at := -1
	for step in range(0, DayNight.day_steps, maxi(DayNight.day_steps / 48, 1)):
		if night_at < 0 and DayNight.daylight(step) < DayNight.DARK_LIGHT:
			night_at = step
		if noon_at < 0 and DayNight.daylight(step) >= DayNight.DARK_LIGHT:
			noon_at = step
	_now = night_at
	var at_night := economy.is_night()
	_now = noon_at
	_check(at_night and not economy.is_night(), "night when it is dark under the sky (step %d), day when not (%d)" % [night_at, noon_at])
	economy.stockpile.take(TOWN, "gold", economy.stockpile.count(TOWN, "gold") - 25, "test")
	_check(economy.barter_quote(TOWN, "p1", [{"id": "ore_sack"}], [])["ok"], "25 gold over a floor of 20: the sack still bought (826: paid in full)")


## The medicine man's barter (decision 562; Jeff: "hob can have a stamina
## potion ... and trades for herbs - other npcs don't find herbs useful").
func _test_robbers_band() -> void:
	print("
== the grave robbers' purse (580, economy's side) ==")
	var robbers: Dictionary = Production.read_rules(Economy.PATH)["robbers"]
	_check(float(robbers["altar_share"]) == 0.5 and float(robbers["thief_cut"]) == 0.25 and int(robbers["most"]) == 40
		and robbers["kinds"] == ["robber", "robber_brute"] and robbers["barrow"] == "barrow", "the rules are economy.json's (%s)" % [robbers])
	var rules := RULES.duplicate(true)
	rules["robbers"] = robbers
	_now = 0
	var clock := func() -> int: return _now
	var stock := Stockpile.new({}, clock, ItemBook.new(clock))
	var work := Production.new({}, stock, null, clock, rules, func() -> Dictionary: return CATALOG)
	var economy := Economy.new({}, stock, work, clock, rules, func() -> Dictionary: return CATALOG)
	economy.altar_down(TOWN, 50)
	economy._band_turn()
	_check(economy.band_gold("barrow") == 25 and economy.below_gold(TOWN) == 25, "a day: the robbers lift half the altar's gold (%d, %d left)"
		% [economy.band_gold("barrow"), economy.below_gold(TOWN)])
	economy._band_turn()
	_check(economy.band_gold("barrow") == 25, "and once a day only")
	_now = DayNight.day_steps
	economy._band_turn()
	_check(economy.band_gold("barrow") == 37 and economy.below_gold(TOWN) == 13, "the next day half again (%d)" % economy.band_gold("barrow"))
	work.add_worker("nell", "Nell", ["weaver"], TOWN)
	work.pay("nell", 8, "test")
	_check(economy.thief_cut(work, "nell", 8) == 2 and int(work.worker("nell")["purse"]) == 6 and economy.band_gold("barrow") == 39,
		"the thief pays a quarter of his lift to the robbers (%d left him)" % int(work.worker("nell")["purse"]))
	_check(economy.band_share("barrow", 3) == 13 and economy.band_gold("barrow") == 26, "one of three falls: 39 / 3 is 13, whole gold (601 amended)")
	economy.band_add("barrow", 200, "test")
	_check(economy.band_share("barrow", 1) == 40, "at most 40 on one robber")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(economy.to_dict()))
	var loaded := Economy.new(saved, stock, work, clock, rules, func() -> Dictionary: return CATALOG)
	_check(loaded.band_gold("barrow") == 186 and loaded._band_day == 1, "the purse and its day saved (%d)" % loaded.band_gold("barrow"))
	_check(_fresh().band_share("barrow", 1) == 0, "no rules, no gold: empty pockets")


func _test_barrow_charges() -> void:
	print("== the draugr's deals and a player's charges (573, economy's side) ==")
	var field: Dictionary = Production.read_rules()["return"]["field"]
	_check(Economy.deal_for(9, field).is_empty(), "under 10 gold (Jeff: \"make it start at 10 gold\"): no deal")
	_check(Economy.deal_for(10, field).get("name") == "easy" and Economy.deal_for(99, field).get("name") == "normal"
		and Economy.deal_for(500, field).get("name") == "hard", "10 buys easy, 99 normal, 500 hard: the highest step reached")
	_check(Economy.field_tokens("easy", field) == 5 and Economy.field_tokens("normal", field) == 10 and Economy.field_tokens("hard", field) == 15,
		"charges by deal: 5, 10, 15")
	_check(Economy.field_tokens("normal", {"uses": {"normal": 7}}) == 7, "before the deals, the rules' uses read")
	var none := {}
	_check(Economy.barrow_capacity(none, field) == 0, "unblessed: no capacity")
	var barrow: Dictionary = Economy.barrow_won(none, "easy", field)["barrow"]
	_check(barrow == {"best": "easy", "containers": []}, "easy beaten: best easy, the charges the totem's (573 amended) (%s)" % [barrow])
	_check(Economy.barrow_capacity(barrow, field) == 25, "capacity 25")
	var won: Dictionary = Economy.barrow_won(barrow, "hard", field)["barrow"]
	_check(won["best"] == "hard" and Economy.barrow_capacity(won, field) == 75, "hard beaten: capacity 75")
	var after: Dictionary = Economy.barrow_won(won, "easy", field)["barrow"]
	_check(after["best"] == "hard", "an easier win never lowers best")
	var with_one: Dictionary = after.duplicate(true)
	with_one["containers"] = ["a boss"]
	_check(Economy.barrow_capacity(with_one, field) == 100, "a named container: 25 more")
	_check(Economy.barrow_migrated({"uses": 7, "of": 10, "difficulty": "normal", "day": 3}) == {"tokens": 7, "best": "normal", "containers": []},
		"a saved blessing migrates: uses to charges, its difficulty best")
	_check(Economy.barrow_migrated({"uses": 2, "of": 5}).get("best") == "easy", "blessed with no difficulty: easy")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(after))
	_check(Economy.barrow_migrated(saved) == after, "and a 573 record comes back as it was")


func _test_maker_barter() -> void:
	print("
== a maker barters: the medicine man's potions for herbs from his own purse (decision 562) ==")
	var cat := CATALOG.duplicate(true)
	cat["herbs"] = {"id": "herbs", "tags": ["resource"], "yield": {"herbs": 1}, "value": 1}
	cat["a_potion"] = {"id": "a_potion", "tags": ["medical", "drink"], "made": {"by": "medicine_man", "from": {"herbs": 3}, "steps": 600, "stock": 3}}
	cat["remedy"] = {"id": "remedy", "tags": ["medical"], "value": 4, "made": {"by": "medicine_man", "from": {"herbs": 2}, "steps": 600}}
	var rules := RULES.duplicate(true)
	rules["value"]["herbs"] = 1
	rules["shop_cap"] = 6
	rules["maker_only"] = {"herbs": "the medicine man buys herbs"}
	rules["first_when_sick"] = ["remedy"]
	_now = 0
	var clock := func() -> int: return _now
	var book := ItemBook.new(clock)
	var stock := Stockpile.new({}, clock, book)
	stock.deposit(TOWN, "gold", 100, "test")
	var catalog := func() -> Dictionary: return cat
	var work := Production.new({}, stock, null, clock, rules, catalog)
	work.add_worker("bram", "Bram", ["smith"], TOWN, "rescued:bram")
	work.add_worker("hob", "Hob", ["medicine_man"], TOWN, "rescued:hob")
	work.pay("hob", 10, "a test purse")
	var economy := Economy.new({}, stock, work, clock, rules, catalog)
	_check(economy.maker_materials("hob") == {"herbs": 21}, "his shelf's worth of makes: 3 potions of 3 herbs, 6 remedies of 2: 21 herbs (%s)" % [economy.maker_materials("hob")])
	var buys := economy.maker_buys("hob", ["herbs", "ore_sack", "herbs"])
	_check(buys == {"herbs": {"gold": 2, "up_to": 21}}, "herbs at 2 (none in store: twice their value), as many as his shelf needs, whatever his purse (562 amended (9)): 21; no ore (%s)" % [buys])
	_check(economy.refuses(TOWN, "herbs") == "the medicine man buys herbs" and not economy.offers(TOWN, ["herbs"]).has("herbs")
		and economy.bank_sale(TOWN, "p1", {"herbs": 3}) == 0, "the town won't buy herbs, nor pay for them banked")
	var potion := book.mint("a_potion", "made", "Hob")
	stock.stock_shop(TOWN, potion, "Hob", "hob")
	var sword := _shop_sword(economy)
	var goods := economy.maker_goods("hob")
	_check(goods.size() == 1 and int(goods[0]["uid"]) == potion, "his goods: his own potion, not Bram's sword (%s)" % [goods])
	_check(int(goods[0]["price"]) == 4, "at its worth, 4, though the town wants none (%s)" % [goods])
	var quote := economy.maker_quote("hob", "p1", [{"id": "herbs"}, {"id": "herbs"}], [potion])
	_check(quote["ok"] and quote["gives"] == [2, 2] and quote["takes"] == [4] and quote["balance"] == 0, "two herbs for a potion: even (%s)" % [quote])
	_check(economy.maker_quote("hob", "p1", [], [sword])["why"] == "that is no longer for sale", "Bram's sword is not his to sell")
	# 562 amended (8): a potion left by a keeper no longer here is his to sell; a living one's is not.
	var left := book.mint("a_potion", "made", "Old Tam")
	stock.stock_shop(TOWN, left, "Old Tam", "gone_tam")
	work.add_worker("ned", "Ned", ["medicine_man"], TOWN, "rescued:ned")
	var neds := book.mint("a_potion", "made", "Ned")
	stock.stock_shop(TOWN, neds, "Ned", "ned")
	var hobs: Array = economy.maker_goods("hob").map(func(each: Dictionary) -> int: return int(each["uid"]))
	_check(left in hobs and potion in hobs and neds not in hobs and sword not in hobs,
		"a gone keeper's potion is his to sell too; Ned's, a living maker's, is not (%s)" % [hobs])
	_check(economy.maker_quote("hob", "p1", [], [neds])["why"] == "that is no longer for sale", "nor can he be asked for Ned's")
	stock.take_from_shop(TOWN, left)
	stock.take_from_shop(TOWN, neds)
	work.remove_worker("ned")
	_check(economy.maker_quote("hob", "p1", [{"id": "ore_sack"}], [])["why"] == "Hob has no use for that", "ore: no use to him")
	_check(economy.maker_sell("hob", "p1", "herbs", 2) and int(work.worker("hob")["purse"]) == 8 and economy.gold("p1") == 2,
		"a herb bought from his purse: 8 left him, 2 to the player")
	# The workshop: up to its stock of potions, the remedy first while anyone is sick.
	work.add_workshop("hut", "medicine_man", TOWN)
	work.assign("hut", "hob")
	stock.deposit(TOWN, "herbs", 10, "test")
	var shop := work.workshop("hut")
	var wants: Array[String] = ["medical"]
	var signals := work.signals_of(TOWN, cat)
	_check(str(work._bid(shop, wants, signals, cat).get("recipe")) == "a_potion", "nobody sick: the potion first (by id)")
	work.set_card("bram", {"look": "test"})
	Townsfolk._set_sickness(work, "bram", {"kind": "a cough", "day": 0})
	_check(str(work._bid(shop, wants, signals, cat).get("recipe")) == "remedy", "Bram sick: the remedy first")
	for i in 2:
		stock.stock_shop(TOWN, book.mint("a_potion", "made", "Hob"), "Hob", "hob")
	_check(not work._serves(TOWN, cat["a_potion"], "medical", cat) and work._serves(TOWN, cat["remedy"], "medical", cat),
		"three potions on the shelf: its stock, no more made; remedies still")


func _test_restart() -> void:
	print("\n== a restart keeps players' gold and who made what ==")
	var economy := _fresh()
	economy.add_gold("p1", 40, "purse")
	var uid := _shop_sword(economy)
	var clock := func() -> int: return _now
	var saved: Array = JSON.parse_string(JSON.stringify([economy.stockpile.book.to_dict(), economy.stockpile.to_dict(),
		economy.production.to_dict(), economy.to_dict()]))
	var book := ItemBook.from_dict(saved[0], clock)
	var stock := Stockpile.new(saved[1], clock, book)
	var work := Production.new(saved[2], stock, null, clock, RULES, func() -> Dictionary: return CATALOG)
	var again := Economy.new(saved[3], stock, work, clock, RULES, func() -> Dictionary: return CATALOG)
	_check(again.gold("p1") == 40 and again.gold_log("p1").size() == 1, "the same gold and its log")
	_check(stock.maker_of(TOWN, uid) == "bram", "the shop still knows Bram made the sword")
	var odd := Economy.new({"purses": {"p1": -5, "p2": "lots", "p3": 7.0}}, stock, work, clock, RULES)
	_check(odd.gold("p1") == 0 and odd.gold("p2") == 0 and odd.gold("p3") == 7, "nonsense saved: under 0 and not numbers left out")


# --- In a town ----------------------------------------------------------------------

## ec_town: open stone; the store (a stockpile the town holds) at (5, 3),
## radius 2, its shop counter at (5, 2).
func _register_town() -> void:
	var rows: Array[String] = []
	for y in 10:
		rows.append("#".repeat(14) if y == 0 or y == 9 else "#" + ".".repeat(12) + "#")
	var markers := {Vector2i(2, 2): "start", Vector2i(5, 2): "chest"}
	Level.register(ZONE, Level.image_from_rows(rows, markers), null, {
		"name": "Economy town", "centre": [6, 4], "starts": [[2, 2]],
		"entities": [{"at": [5, 2], "name": "Counter", "props": {"shop": true}}],
		"places": {"store": {"at": [5, 3], "kind": "stockpile", "radius": 2, "holder": "town", "name": "the market"}},
	})


func _test_in_town() -> void:
	print("\n== in a town: the shop panel, buying and selling ==")
	Net.port = preload("res://tests/test_ports.gd").of(17795)
	Net.companions = false
	Net.state_path = preload("res://tests/test_ports.gd").scratch("economy_test_world.json")
	if FileAccess.file_exists(Net.state_path):
		DirAccess.remove_absolute(Net.state_path)
	_register_town()
	Net.map_name = ZONE
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	var names := Level.names()
	names.append(ZONE)
	World.holdings.rebind(WorldMap.build(names))
	for i in 3:
		World.step()
	var host: Player = _main._players.get(Net.local_id)
	var counter: Chest = null
	for entity in World.get_entities():
		if entity.name == "Counter":
			counter = entity
	_check(counter != null and counter.shop and World.shop_place(counter) == STORE, "the counter is a shop in the town's market")
	var me := host.player_id
	World.stockpile.deposit(STORE, "gold", 100, "test")
	var kit := World.items.mint("bandaging_kit", "made", "test")
	World.production.add_worker("wren", "Wren", ["cook"], STORE)
	World.stockpile.stock_shop(STORE, kit, "Wren", "wren")
	World._relocate(host, Vector2i(5, 3))
	_main.open_other(counter)
	var price := World.economy.value_of("bandaging_kit")  # 280 amended: the kit is worth 5; the town's need sets the price.
	var rows: Array = _main.shop_panel.rows_shown()
	if rows.size() == 1 and str(rows[0]).begins_with("bandaging kit ") and str(rows[0]).ends_with(" gold"):
		price = int(str(rows[0]).trim_prefix("bandaging kit ").trim_suffix(" gold"))
	_check(_main.shop_panel.shop == counter and rows.size() == 1 and price >= 1 and price < 10,
		"opened, the panel shows the kit at %d gold (%s)" % [price, rows])
	_check(_main.shop_panel.gold_shown() == "0 gold", "and the host's gold: none")
	_main._buy(counter, kit)
	_check(_main.shop_panel.why_shown() == "not enough gold (%d)" % price and host.slots[0] == "", "Buy with no gold: refused, said why")
	World.add_gold(me, 10, "purse")
	_check(_main.gold == 10 and _main.shop_panel.gold_shown() == "10 gold", "a purse opened: the client shows 10 gold")
	_main._buy(counter, kit)
	_check(host.slots[0] == "bandaging_kit" and World.slot_uid(host, 0) == kit and _main.gold == 10 - price,
		"bought: the kit in the host's pack, %d gold left (%s, %d)" % [10 - price, Array(host.slots), _main.gold])
	_check(_main.shop_panel.rows_shown().is_empty() and _main.shop_panel.why_shown() == "", "the panel: nothing left for sale")
	var ore := World.items.mint("ore_sack", "found", "test")
	World.put_item(host, host, 1, ore)
	_main.open_other(counter)
	_main._send_shop(host, counter)
	_check(_main.shop_panel._offer_label.text.contains("sack of ore 9 gold"), "the town would pay 9 for the sack of ore (%s)" % _main.shop_panel._offer_label.text)
	_check(World.try_transfer(host, host, 1, counter, 0), "the host puts the sack in the counter: sold")
	_check(host.slots[1] == "" and counter.slots[0] == "" and World.stockpile.count(STORE, "ore") == 5 and _main.gold == 19 - price,
		"the slot empty, the counter keeps nothing, 5 ore banked, %d gold (%d)" % [19 - price, _main.gold])
	var herbs := World.items.mint("herbs", "found", "test")  # 601 amended: no coin purse to refuse now.
	World.put_item(host, host, 1, herbs)
	_check(not World.try_transfer(host, host, 1, counter, 0) and host.slots[1] == "herbs"
		and _main.shop_panel.why_shown() == "the medicine man buys herbs", "herbs in the counter: refused, said why (only their maker buys them)")
	World.items.end(World.take_item(host, host, 1), "gone")
	# A stack sold (722: sacks stack 5): each unit sold and paid, none lost.
	var sacks := [World.items.mint("ore_sack", "found", "test"), World.items.mint("ore_sack", "found", "test")]
	World.put_item(host, host, 1, sacks[0])
	World.put_item(host, host, 1, sacks[1])
	var ore_was := World.stockpile.count(STORE, "ore")
	var gold_was: int = _main.gold
	_check(World.slot_count(host, 1) == 2 and World.try_transfer(host, host, 1, counter, 0) and host.slots[1] == ""
		and World.stockpile.count(STORE, "ore") == ore_was + 10 and _main.gold > gold_was,
		"a stack of 2 sacks sold: both banked (ore +10), paid for, the slot empty (%d -> %d gold)" % [gold_was, _main.gold])
	var sold_gold: int = _main.gold
	_main._save_state()
	_check(Snapshot.load(Net.state_path)["economy"]["purses"].get(me) == sold_gold, "the snapshot keeps the host's gold (%d)" % sold_gold)
	await _test_barter_in_town(host, counter)
	_test_robber_falls(host)
	await _test_give_in_town(host)
	await _test_town_sheet(host)
	_test_drove()
	_test_makers_command()
	remove_child(_main)
	_main.free()
	World.clear_zones()
	World.economy = null
	DirAccess.remove_absolute(Net.state_path)
	Net.state_path = ""
	Net.map_name = ""
	Level.unregister(ZONE)


## Barter at the counter (decision 560): the "barter" message, a trade all
## or nothing through the "trade" command, grave goods fenced.
func _test_barter_in_town(host: Player, counter: Chest) -> void:
	print("
== in a town: barter at the counter ==")
	World.take_item(host, host, 1)
	# Starter gear (736): no counter takes it back.
	var starter := World.items.mint("sword", "made", "test")
	World.mark_starter(starter)
	World.put_item(host, host, 1, starter)
	World.command(host, "trade", {"shop": str(counter.get_path()), "give": [starter], "take": [], "gold": 0})
	_check(_main.barter_data.get("why") == World.STARTER_REFUSED and host.slots[1] == "sword", "starter gear: refused (%s)" % _main.barter_data.get("why"))
	World.take_item(host, host, 1)
	var kit := World.items.mint("bandaging_kit", "made", "test")
	World.stockpile.stock_shop(STORE, kit, "Wren", "wren")
	var ore := World.items.mint("ore_sack", "found", "test")
	World.items.mark_grave(ore, "Altar")
	World.put_item(host, host, 1, ore)
	World.command(host, "barter", {"shop": str(counter.get_path())})
	var told: Dictionary = _main.barter_data
	_check(told.get("fence") == "" and told.get("fenced", {}).is_empty(), "a counter not the fence's: no fence, nothing fenced (586)")
	World.command(host, "trade", {"shop": str(counter.get_path()), "give": [ore], "take": [], "gold": 0})
	_check(_main.barter_data.get("why") == "won't buy that" and host.slots[1] == "ore_sack", "grave goods: won't buy (%s)" % _main.barter_data.get("why"))
	# Snagfin keeps this counter for the test (his settled entry moved here), by night.
	var days: Dictionary = Townsfolk.days().duplicate(true)
	days["settled"]["snagfin"]["town"] = STORE
	days["settled"]["snagfin"]["home"] = [counter.tile.x, counter.tile.y]
	Townsfolk.use_days(days)
	if World.production.worker("snagfin").is_empty():
		World.production.add_worker("snagfin", "Snagfin", ["merchant"], STORE, "settled", "merchant")
	var was_steps := World.steps
	while DayNight.daylight(World.steps) >= DayNight.DARK_LIGHT:
		World.steps += 600
	World.command(host, "barter", {"shop": str(counter.get_path())})
	told = _main.barter_data
	var paid := int(told.get("buys", {}).get("ore_sack", {}).get("gold", 0))
	var fenced := int(told.get("fenced", {}).get(ore, 0))
	var asks := 0
	for each: Dictionary in told.get("goods", []):
		if int(each["uid"]) == kit:
			asks = int(each["price"])
	_check(told.get("fence") == "night" and told.get("town") == STORE and paid > 0 and fenced == Economy.fenced(paid) and asks > 0
		and told.get("pack", []).any(func(each: Dictionary) -> bool: return int(each["uid"]) == ore and int(each["slot"]) == 1),
		"the message: the kit asked %d, the sack's %d fenced to %d, the sack in the pack at slot 1 (%s)" % [asks, paid, fenced, told])
	var gold := World.gold_of(host.player_id)
	World.command(host, "trade", {"shop": str(counter.get_path()), "give": [ore], "take": [kit], "gold": fenced - asks + 1})
	_check(_main.barter_data.get("why") == "the prices have moved" and host.slots[1] == "ore_sack" and World.gold_of(host.player_id) == gold,
		"a stale sum: refused, nothing moved (%s)" % _main.barter_data.get("why"))
	World.command(host, "trade", {"shop": str(counter.get_path()), "give": [ore], "take": [kit], "gold": fenced - asks})
	_check(_main.barter_data.get("why") == "" and World.gold_of(host.player_id) == gold + fenced - asks
		and World.slot_of_unit(host, kit) >= 0 and ore not in World.slot_uids(host) and kit not in World.stockpile.shop(STORE),
		"traded: the sack banked, the kit in the pack, %d gold (%s, %d)" % [gold + fenced - asks, Array(host.slots), World.gold_of(host.player_id)])
	while DayNight.daylight(World.steps) < DayNight.DARK_LIGHT:
		World.steps += 600
	World.command(host, "barter", {"shop": str(counter.get_path())})
	_check(_main.barter_data.get("fence") == "day", "by day his counter says so (%s)" % _main.barter_data.get("fence"))
	World.steps = was_steps
	Townsfolk.use_days({})
	World._relocate(host, Vector2i(11, 7))
	World.command(host, "barter", {"shop": str(counter.get_path())})
	_check(_main.barter_data.get("why") == "too far from the counter", "away from the counter and any merchant: too far")
	await get_tree().process_frame


## A robber falls in the barrow (580, economy's side; the test's zone stands
## for it): his share of the band's purse lies where he fell as coin purses.
func _test_robber_falls(host: Player) -> void:
	print("
== a grave robber falls with gold on him ==")
	World.economy.rules["robbers"] = Production.read_rules(Economy.PATH)["robbers"].duplicate(true)
	World.economy.rules["robbers"]["barrow"] = World.zone.name
	var robbers: Array[GridEntity] = []
	for i in 2:
		robbers.append(_main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "kind": "robber", "name": "Robber%d" % i,
			"tile": _main._nearest_free(host.tile + Vector2i(3 + i, 2))}))
	_check(robbers.all(func(each: GridEntity) -> bool: return each != null), "two robbers stand")
	World.economy.band_add(World.zone.name, 50, "test")
	var at := robbers[0].tile
	World.damage(robbers[0], 999)
	_check(World.ground_gold(at) == 25 and World.economy.band_gold(World.zone.name) == 25 and not "coin_purse" in World.ground_at(at),
		"one of two falls: 25 gold where he fell, a count (601 amended), 25 left the band (%d)" % World.ground_gold(at))
	var none: GridEntity = _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "kind": "skeleton", "name": "Bones",
		"tile": _main._nearest_free(host.tile + Vector2i(-3, 2))})
	var bones_at: Vector2i = none.tile
	var before := World.ground_gold(bones_at)
	World.damage(none, 999)
	_check(World.ground_gold(bones_at) == before and World.economy.band_gold(World.zone.name) == 25,
		"a skeleton carries none of it (%d)" % World.ground_gold(bones_at))
	World.damage(robbers[1], 999)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


## Giving gold (decision 614): a transfer between records, both logs naming
## the other; nothing for too much, none, or to oneself; a companion's purse.
func _test_give_gold() -> void:
	print("
== giving gold ==")
	var economy := _fresh()
	economy.add_gold("a", 30, "test")
	_check(economy.give_gold("a", "b", 12, "Ann", "Bo") == 12 and economy.gold("a") == 18 and economy.gold("b") == 12,
		"12 gold from Ann to Bo, no more and no less in the world")
	_check(economy.gold_log("a").back()["why"] == "gave to Bo" and economy.gold_log("b").back()["why"] == "given by Ann", "each log names the other")
	_check(economy.give_gold("a", "b", 19) == 0 and economy.give_gold("a", "b", 0) == 0 and economy.give_gold("a", "a", 5) == 0 and economy.gold("a") == 18,
		"nothing for more than she has, for none, or to herself")
	var pet := Economy.companion_purse("a")
	_check(pet == "companion:a" and economy.give_gold("a", pet, 8) == 8 and economy.give_gold(pet, "a", 3) == 3 and economy.gold(pet) == 5,
		"a companion's purse, given to and taken from")
	var again := Economy.new(economy.to_dict(), economy.stockpile, economy.production, economy.clock, RULES, func() -> Dictionary: return CATALOG)
	_check(again.gold(pet) == 5, "her purse saved")


## The town sheet (624, economy's side): the "town_sheet" command answered
## for the host's own town, its officials, needs and next stage, and refused
## for a town they don't know.
func _test_town_sheet(host: Player) -> void:
	print("
== the town sheet ==")
	World.towns.move_in(STORE, "aldo", "Aldo", "priest")
	World.production.set_owed("aldo", 3)
	var sheet: Dictionary = _main.ask_town_sheet(host, {"town": STORE})
	_check(not sheet.has("why") and sheet["treasury"] == World.stockpile.count(STORE, "gold") and sheet["population"] == World.towns.residents(STORE).size(),
		"answered for the host's town: its treasury and people (%s)" % sheet.get("why", ""))
	_check(sheet["officials"].any(func(each: Dictionary) -> bool: return each["name"] == "Aldo" and each["trade"] == "priest" and not each["paid"]),
		"the priest an official, owed so not paid (%s)" % [sheet["officials"]])
	var wood: Array = sheet["needs"].filter(func(each: Dictionary) -> bool: return each["id"] == "wood")
	var want := int(World.economy.rules["comfort"]["wood"])
	_check(wood.size() == 1 and wood[0]["bring"] == want - World.stockpile.count(STORE, "wood") and not sheet["needs"].any(func(each: Dictionary) -> bool: return each["id"] == "gold"),
		"wood wanted, as much as comfort lacks; gold never a need (%s)" % [sheet["needs"]])
	var next: Dictionary = sheet["next_stage"]
	_check(not next.is_empty() and next["needs"] == World.towns.stage_short(STORE, World.economy.rules["stages"][World.economy.rules["stages"].map(func(each: Dictionary) -> String: return each["name"]).find(next["stage"])]),
		"the next stage and what it lacks (%s)" % [next])
	_check(sheet["mood"] in ["safe", "uneasy", "on guard"] and sheet["season"] != "" and sheet["sought"] is Array, "the mood, season and sought")
	_check(sheet["strain"] == World.towns.strain(STORE) and sheet["strain"].has("days") and sheet["strain"].has("why"), "its strain toward falling (649): %s" % [sheet["strain"]])
	_check(_main.ask_town_sheet(host, {"town": "nowhere/store"}).get("why") == "you don't know that town", "a town they don't know: refused")
	await _test_town_window(host)
	_test_person_takes(host)
	_test_trophies(host)
	_test_charm_inputs(host)
	_test_truffles(host)
	_test_admin_stock(host)


## The give path's data (804's hand-in to people; ui's Give tab): wood goes
## to the town's carpenter alone, with what it does for the town and the gold;
## gear to the stall's keeper, never a starter ware; the keeper takes a raw
## nobody's trade takes.
func _test_person_takes(host: Player) -> void:
	print("
== giving to people: who takes what, and what it does (804's give path) ==")
	World.production.add_worker("give_cora", "Cora", ["carpenter"], STORE, "test")
	var carp: String = _main.receiver_for(STORE, "wood")
	_check(not carp.is_empty() and "carpenter" in World.production.worker(carp)["trades"], "wood goes to a carpenter (%s)" % carp)
	var me: String = _main._id_of_player(host)
	for i in 2:
		_main._hand_item(me, "wood_bundle", "test")
	var vendor: Dictionary = World.economy.rules.get("vendor", {}).duplicate(true)
	World.economy.rules["vendor"] = {"towns": [STORE], "name": "Rolf", "price": 1, "wares": []}
	_main._hand_item(me, "sword", "test")
	_main._hand_item(me, "dagger", "test", true)
	var takes: Array = _main.person_takes(host, carp)
	var wood: Array = takes.filter(func(row: Dictionary) -> bool: return row["what"] == "wood_bundle")
	var had := World.stockpile.count(STORE, "wood")
	_check(wood.size() == 1 and int(wood[0]["count"]) >= 2 and int(wood[0]["uid"]) > 0 and int(wood[0]["have"]) == had + 5 * int(wood[0]["count"])
		and wood[0]["for"]["kind"] in ["build", "stores"] and not str(wood[0]["for"]["name"]).is_empty() and int(wood[0]["need"]) > 0
		and wood[0]["raw"] == "wood" and str(host.slots[int(wood[0]["slot"])]) == "wood_bundle",
		"the carpenter takes the wood: the stack, what it is for, have and need after (%s)" % [wood])
	_check((int(wood[0]["gold"]) > 0 and not wood[0].has("owed")) if not wood.is_empty() else false, "and the gold it pays, in full (826)")
	_check(not takes.any(func(row: Dictionary) -> bool: return row["what"] in ["sword", "dagger"]), "the carpenter takes no gear")
	var keeper: Array = _main.person_takes(host, Offers.VENDOR + STORE)
	var gift_row := func(what: String) -> bool:
		return keeper.any(func(row: Dictionary) -> bool: return row["what"] == what and int(row["gold"]) == 0 and (row["for"] as Dictionary).is_empty())
	# The starter dagger too, for nothing (807 amended (5): starter gear goes back to him, Donate).
	_check(gift_row.call("sword") and gift_row.call("dagger") and not keeper.any(func(row: Dictionary) -> bool: return row["what"] == "wood_bundle"),
		"the keeper takes the sword and the starter dagger as gifts, not the carpenter's wood (%s)" % [keeper.map(func(row: Dictionary) -> String: return row["what"])])
	var no_smith := not World.production.worker_ids(STORE).any(func(id: String) -> bool: return "smith" in World.production.worker(id)["trades"])
	_check(not no_smith or _main.receiver_for(STORE, "ore") == Offers.VENDOR + STORE, "ore with no smith in town: the keeper takes it")

	# The give (802 amended (2)): the wood to Cora, banked, thanked by name with "worker"; the sword
	# to her refused (not hers to take); then the sword to the keeper.
	var wood_uid := int(wood[0]["uid"]) if not wood.is_empty() else 0
	var sword_uid := int(keeper.filter(func(row: Dictionary) -> bool: return row["what"] == "sword")[0]["uid"])
	var stock := World.stockpile.count(STORE, "wood")
	var bundles := World.count_of(host, "wood_bundle")
	var given: Array = _main.give_to(host, carp, "Cora", [wood_uid, sword_uid])
	var thanks: Dictionary = _main.rewards_given.filter(func(each: Dictionary) -> bool: return each["player"] == me and each["data"]["track"] == "item").back()["data"]
	_check(given.size() == bundles and World.count_of(host, "wood_bundle") == 0 and World.stockpile.count(STORE, "wood") == stock + 5 * bundles
		and World.count_of(host, "sword") >= 1, "the whole stack of wood given and banked, the sword kept (%d given)" % given.size())
	_check(str(thanks.get("words", "")).begins_with("Cora takes ") and thanks.get("worker") == carp,
		"thanked by name, the reward naming her (%s)" % [thanks])
	var gift: Array = _main.give_to(host, Offers.VENDOR + STORE, "Rolf", [sword_uid])
	_check(gift.size() == 1 and _main.rewards_given.back()["data"].get("worker") == Offers.VENDOR + STORE
		and str(_main.rewards_given.back()["data"]["words"]).begins_with("Rolf takes"), "the sword to the keeper, a gift (%s)" % [_main.rewards_given.back()["data"]])
	_check(_main.give_to(host, carp, "Cora", [sword_uid]).is_empty(), "a thing no longer theirs: nothing given")

	# The store chest refuses players (802 amended (3)), saying who takes it, in voice's words.
	_check(_main.depot_pointer(STORE, "wood_bundle") == "Wood goes to the carpenter." and _main.depot_pointer(STORE, "sword") == "That goes to Rolf at the stall.",
		"the pointers: wood to the carpenter, gear to Rolf (%s, %s)" % [_main.depot_pointer(STORE, "wood_bundle"), _main.depot_pointer(STORE, "sword")])
	# A thing held is never offered as a gift (802 amended (4); playtest's pick in hand).
	_main._hand_item(me, "sword", "test")
	var packed: int = Array(host.slots).find("sword")
	if packed != Items.RIGHT_HAND and str(host.slots[Items.RIGHT_HAND]).is_empty():
		World.try_transfer(host, host, packed, host, Items.RIGHT_HAND)
	var into_hand: bool = str(host.slots[Items.RIGHT_HAND]) == "sword"
	var offered: Array = _main.person_takes(host, Offers.VENDOR + STORE)
	_check(into_hand and str(host.slots[Items.RIGHT_HAND]) == "sword"
		and not offered.any(func(row: Dictionary) -> bool: return int(row["slot"]) == Items.RIGHT_HAND),
		"a sword in hand: not offered to the keeper (%s; slots %s)" % [offered.map(func(row: Dictionary) -> String: return "%s@%d" % [row["what"], row["slot"]]), Array(host.slots)])
	# The takers (802 amended (5)): who in town takes each raw, for ui's hint; sent once till it changes.
	var started := Time.get_ticks_usec()
	var takers: Dictionary = _main.takers_of(STORE)
	print("[test] takers_of(%s) took %d us" % [STORE, Time.get_ticks_usec() - started])
	var wood_taker: Dictionary = takers["takers"].get("wood", {})
	_check(takers["town"] == STORE and wood_taker.get("trade") == "carpenter" and wood_taker.get("name") == "Cora" and wood_taker.get("store") is bool
		and takers.get("gear", {}).get("trade") == "vendor" and takers["gear"].get("name") == "Rolf",
		"802 amended (5): the takers: wood to Cora the carpenter, gear to Rolf (%s)" % [takers])
	_check(takers["takers"].keys().all(func(raw: String) -> bool: return takers["takers"][raw]["store"] == (_main.give_outcome(STORE, "", raw, 1)["for"]["kind"] == "stores"))
		and takers.get("gear", {}).get("body") == (String(_main._resident_body(Offers.VENDOR + STORE).get_path()) if _main._resident_body(Offers.VENDOR + STORE) != null else ""),
		"each raw's store flag as give_outcome says, the bodies as found one by one (perf: built once)")
	var cora_id := ""
	for id: String in World.production.worker_ids(STORE):
		if World.production.worker(id)["name"] == "Cora":
			cora_id = id
	_check(is_same(_main.takers_of(STORE), _main.takers_of(STORE)), "802 amended (7): nothing changed, the last build again (not rebuilt)")
	World.production.set_away(cora_id, true)
	var away: Dictionary = _main.takers_of(STORE)
	World.production.set_away(cora_id, false)
	_check(away["takers"].get("wood", {}).get("name") != "Cora" and _main.takers_of(STORE)["takers"].get("wood", {}).get("name") == "Cora",
		"Cora away: built again, wood to another; home: to her again (%s)" % [away["takers"].get("wood", {})])
	# Each thing a build reads moves it (the coordinator: a stale stamp would name the wrong taker).
	_check(not _main.takers_of(STORE)["takers"].has("hide") or _main.takers_of(STORE)["takers"]["hide"].get("trade") != "tanner", "no tanner yet")
	World.production.add_worker("zz_stamp_tanner", "Wat", ["tanner"], STORE, "test")
	_check(_main.takers_of(STORE)["takers"].get("hide", {}).get("name") == "Wat", "a tanner hired: hide to him, built again")
	World.production.remove_worker("zz_stamp_tanner")
	_check(_main.takers_of(STORE)["takers"].get("hide", {}).get("name") != "Wat", "and gone again: not to him")
	var body := _main._spawn({"script": Main.RESIDENT, "shape": "capsule", "name": "Resident_stamp_cora", "label": "Cora, carpenter",
		"tile": _main._nearest_free(Vector2i(4, 4))}) as Resident
	body.worker_id = cora_id
	var with_body: Dictionary = _main.takers_of(STORE)["takers"].get("wood", {})
	World.despawn(body)
	var no_body: Dictionary = _main.takers_of(STORE)["takers"].get("wood", {})
	_check(str(with_body.get("body", "")).ends_with("Resident_stamp_cora") and not str(no_body.get("body", "")).ends_with("Resident_stamp_cora"),
		"her body spawned: its path; despawned: gone (%s, %s)" % [with_body.get("body"), no_body.get("body")])
	# The town's queued build (the temple here): a raw it lacks is for the build, enough of it for the stores.
	var short := World.towns.shortfall(STORE)
	var queued := World.production.job(int(short.get("job", 0)))
	var raw := ""
	for what: String in queued.get("cost", {}):
		if _main.takers_of(STORE)["takers"].has(what):
			raw = what
			break
	var cost := int(queued.get("cost", {}).get(raw, 0))
	var raw_had := World.stockpile.count(STORE, raw)
	if raw_had >= cost:
		World.stockpile.take(STORE, raw, raw_had - cost + 1, "test")
	_check(not raw.is_empty() and _main.takers_of(STORE)["takers"][raw]["store"] == false, "the %s lacks %s: it is for the build (%s)" % [short.get("kind"), raw, short])
	World.stockpile.deposit(STORE, raw, 1, "test")
	_check(_main.takers_of(STORE)["takers"][raw]["store"] == true, "one more %s in the store: the build lacks none, for the stores" % raw)
	World.stockpile.take(STORE, raw, 1, "test")
	_check(_main.takers_of(STORE)["takers"][raw]["store"] == false, "one taken again: for the build again")
	World.production.cancel(int(short["job"]))
	_check(_main.takers_of(STORE)["takers"][raw]["store"] == true, "the build gone: for the stores")
	World.production.order_build(STORE, str(short["kind"]), str(queued.get("trade", "carpenter")), queued.get("cost", {}), int(short.get("steps", 0)))
	_check(_main.takers_of(STORE)["takers"][raw]["store"] == false, "a build queued again that lacks it: for the build")
	if raw_had > World.stockpile.count(STORE, raw):
		World.stockpile.deposit(STORE, raw, raw_had - World.stockpile.count(STORE, raw), "test")
	_main._takers_sent.erase(Net.local_id)
	_main._takers_by_zone.clear()
	_main.takers_here = {}
	_main._tell_takers(Net.local_id, STORE.get_slice("/", 0))
	var first: Dictionary = _main.takers_here
	_main.takers_here = {}
	_main._tell_takers(Net.local_id, STORE.get_slice("/", 0))
	_check(first.get("town") == STORE and _main.takers_here.is_empty(), "told on entering, not again while the same (%s)" % [first.get("town")])
	World.economy.rules["vendor"] = {}
	_main._tell_takers(Net.local_id, STORE.get_slice("/", 0))
	_check(_main.takers_here.is_empty(), "within one pass the zone's takers are shared, not built again")
	_main._takers_by_zone.clear()  # The next pass (_tell_world clears it after each).
	_main._tell_takers(Net.local_id, STORE.get_slice("/", 0))
	_check(_main.takers_here.get("town") == STORE and not _main.takers_here.has("gear"), "told again when it changes: no stall, no gear")
	# 297 amended: the "town" message's residents' trades, sent again when they change.
	var trades_from := Time.get_ticks_usec()
	_main._tell_town_trades()
	print("[test] _tell_town_trades over %d towns took %d us" % [World.towns.ids().size(), Time.get_ticks_usec() - trades_from])
	_main.town_trades.erase(STORE)
	World.towns.move_in(STORE, "zz_trades_weaver", "Mabyn", "weaver")
	_main._tell_town_trades()
	_check((_main.town_trades.get(STORE, []) as Array).has("weaver") and _main.town_has_trade(STORE, "weaver") and not _main.town_has_trade(STORE, "fisherman"),
		"a weaver moves in: the town told again, its trades with her (%s)" % [_main.town_trades.get(STORE)])
	_check(_main._town_message(STORE).get("trades") == World.towns.resident_trades(STORE), "the town message carries the residents' trades")
	_main._tell_takers(Net.local_id, "nowhere")
	_check(_main.takers_here == {"town": "", "takers": {}}, "an area with no town: told so")
	_check(_main.depot_pointer(STORE, "sword") == "Nobody here takes that.", "no stall here: nobody takes gear")
	_main._hand_item(me, "wood_bundle", "test")
	var chest := Chest.new()
	chest.depot = true
	chest.tile = World.holdings.place(STORE)["cell"]
	chest.zone = host.zone
	var told: Array = []
	var hear := func(by: GridEntity, why: String) -> void: told.append(why)
	World.slot_refused.connect(hear)
	var slot := Array(host.slots).find("wood_bundle")
	var before := World.stockpile.count(STORE, "wood")
	_check(not World._bank(host, host, slot, chest) and World.stockpile.count(STORE, "wood") == before and host.slots[slot] == "wood_bundle"
		and told == ["Wood goes to the carpenter."], "a player's wood at the store chest: refused, kept, told who takes it (%s)" % [told])
	World.slot_refused.disconnect(hear)
	chest.free()
	World.economy.rules["vendor"] = vendor


## Trophies bought by Give (821; the coordinator's ruling: the bear's loot
## needs a buyer the player can reach): with no tanner seated, Rolf at the
## stall buys a bear's claw at value x store.trophy, "for selling on"; with
## one, the tanner buys the pelt "for tanning" and Rolf no longer offers for
## it; the gold paid (in full, 826) reaches the player and the thanks; the
## takers' tooltip and the store chest's pointer name the tanner.
func _test_trophies(host: Player) -> void:
	print("\n== 821: trophies bought by Give ==")
	var me: String = _main._id_of_player(host)
	var economy: Economy = World.economy
	var vendor: Dictionary = economy.rules.get("vendor", {}).duplicate(true)
	economy.rules["vendor"] = {"towns": [STORE], "name": "Rolf", "price": 1, "wares": []}
	var away: Array[String] = []
	for id: String in World.production.worker_ids(STORE):
		if "tanner" in World.production.worker(id)["trades"] and not World.production.worker(id).get("away", false):
			World.production.set_away(id, true)  # Put back at the end.
			away.append(id)
	_check(economy.trophy_trade("bear_claw") == "tanner" and economy.trophy_trade("sword") == "" and economy.trophy_price("bear_claw") == 3
		and economy.trophy_price("bear_pelt") == 20, "the tanner's trophies, at half their worth: claw 3, pelt 20")
	for slot: int in [Items.PACK_SLOTS[0], Items.PACK_SLOTS[1]]:  # Room in the pack: a trophy in hand is never offered.
		if not str(host.slots[slot]).is_empty():
			World.take_item(host, host, slot)
	_main._hand_item(me, "bear_claw", "test")
	_main._hand_item(me, "bear_claw", "test")
	var held: int = Array(host.slots).find("bear_claw")
	if held not in Items.PACK_SLOTS:
		World.try_transfer(host, host, held, host, Items.PACK_SLOTS[0])  # Handed into a free hand: to the pack.
	_check(_main.trophy_taker(STORE, "bear_claw") == Offers.VENDOR + STORE, "no tanner seated: Rolf buys trophies")
	var rows: Array = _main.person_takes(host, Offers.VENDOR + STORE).filter(func(row: Dictionary) -> bool: return row["what"] == "bear_claw")
	var row: Dictionary = rows[0] if rows.size() == 1 else {}
	_check(row.get("for", {}).get("kind") == "maker" and row.get("for", {}).get("name") == "selling on" and row.get("raw") == ""
		and int(row.get("need", -1)) == 0 and int(row.get("gold", 0)) == 3 * int(row.get("count", 0)) and int(row.get("count", 0)) >= 2 and not row.has("owed"),
		"Rolf's row: for selling on, 3 gold a claw, paid in full (%s)" % [row])
	var purse := economy.gold(me)
	var given: Array = _main.give_to(host, Offers.VENDOR + STORE, "Rolf", [int(row.get("uid", 0))])
	var thanks: Dictionary = _main.rewards_given.filter(func(each: Dictionary) -> bool: return each["player"] == me and each["data"]["track"] == "item").back()["data"]
	_check(not row.is_empty() and given.size() == int(row.get("count", 0)) and economy.gold(me) == purse + int(row.get("gold", 0)) and int(thanks.get("gold", 0)) == int(row.get("gold", 0))
		and World.stockpile.count(STORE, "bear_claw") >= given.size(),
		"given: banked, paid what the row said, the thanks carrying it (%d gold; %s)" % [economy.gold(me) - purse, thanks])
	_check(_main.depot_pointer(STORE, "bear_claw") == "That goes to Rolf at the stall.", "the chest's pointer: to Rolf")
	World.production.add_worker("trophy_tan", "Tamsin", ["tanner"], STORE, "test")
	_main._hand_item(me, "bear_pelt", "test")
	_check(_main.trophy_taker(STORE, "bear_pelt") == "trophy_tan", "a tanner seated: the tanner buys them")
	_check(not _main.person_takes(host, Offers.VENDOR + STORE).any(func(each: Dictionary) -> bool: return each["what"] == "bear_pelt"), "and Rolf no longer offers for the pelt")
	var pelt: Array = _main.person_takes(host, "trophy_tan").filter(func(each: Dictionary) -> bool: return each["what"] == "bear_pelt")
	_check(pelt.size() == 1 and pelt[0]["for"]["name"] == "tanning" and int(pelt[0]["gold"]) == 20,
		"the tanner's row: for tanning, 20 gold (%s)" % [pelt])
	var takers: Dictionary = _main.takers_of(STORE)
	_check(Main.taker_entry(takers, "bear_pelt").get("trade") == "tanner" and Main.taker_entry(takers, "bear_pelt").get("name") == "Tamsin",
		"the pack's tooltip: the pelt to Tamsin the tanner (%s)" % [takers.get("trophies", {})])
	_check(_main.depot_pointer(STORE, "bear_pelt") == "Pelts and trophies go to the tanner.", "the chest's pointer: to the tanner (%s)" % _main.depot_pointer(STORE, "bear_pelt"))
	purse = economy.gold(me)
	var sold: Array = _main.give_to(host, "trophy_tan", "Tamsin", [int(pelt[0]["uid"]) if not pelt.is_empty() else 0])
	_check(sold.size() == 1 and World.count_of(host, "bear_pelt") == 0 and economy.gold(me) == purse + (int(pelt[0]["gold"]) if not pelt.is_empty() else -1),
		"the pelt to the tanner: banked and paid")
	World.production.remove_worker("trophy_tan")
	for id in away:
		World.production.set_away(id, false)
	economy.rules["vendor"] = vendor


## 780 amended (16), economy's side: the boar king's find. The Mughouse's
## taverner buys truffles by Give, "for the pot", at half their worth (821's
## trophy path; else Rolf, selling on); the forest camps' traders buy them by
## Sell; the tanner takes the boar king's hide and tusk.
func _test_truffles(host: Player) -> void:
	print("
== 780 amended (16): truffles, the boar king's hide and tusk ==")
	var me: String = _main._id_of_player(host)
	var economy: Economy = World.economy
	var vendor: Dictionary = economy.rules.get("vendor", {}).duplicate(true)
	economy.rules["vendor"] = {"towns": [STORE], "name": "Rolf", "price": 1, "wares": []}
	_check(Items.def("truffles").get("value", 0) == 8 and economy.trophy_trade("truffles") == "taverner" and economy.trophy_for("truffles") == "the pot"
		and economy.trophy_price("truffles") == 4, "truffles: the taverner's, for the pot, 4 gold (half of 8)")
	_check(economy.trophy_trade("boar_king_hide") == "tanner" and economy.trophy_for("boar_king_hide") == "tanning"
		and economy.trophy_trade("boar_king_tusk") == "tanner" and economy.trophy_for("boar_king_tusk") == "trimming leather"
		and economy.trophy_price("boar_king_hide") == 15 and economy.trophy_price("boar_king_tusk") == 5,
		"the boar king's hide (15, tanning) and tusk (5, trimming leather) go to the tanner")
	var camps := _fresh()
	camps.rules = camps.rules.duplicate(true)
	camps.rules["camp_traders"] = Production.read_rules()["camp_traders"]
	camps.catalog = Economy.items_defs
	_check(camps.camp_offer("truffles") == 7, "a camp trader buys truffles at 7 (%d)" % camps.camp_offer("truffles"))
	var away: Array[String] = []
	for id: String in World.production.worker_ids(STORE):
		if "taverner" in World.production.worker(id)["trades"] and not World.production.worker(id).get("away", false):
			World.production.set_away(id, true)  # Put back at the end.
			away.append(id)
	for slot: int in [Items.PACK_SLOTS[0], Items.PACK_SLOTS[1], Items.PACK_SLOTS[2]]:
		if not str(host.slots[slot]).is_empty():
			World.take_item(host, host, slot)
	_main._hand_item(me, "truffles", "test")
	_check(_main.trophy_taker(STORE, "truffles") == Offers.VENDOR + STORE, "no taverner seated: Rolf buys truffles")
	World.production.add_worker("truff_tav", "Tess", ["taverner"], STORE, "test")
	_check(_main.trophy_taker(STORE, "truffles") == "truff_tav", "a taverner seated: she buys them")
	_check(not _main.person_takes(host, Offers.VENDOR + STORE).any(func(each: Dictionary) -> bool: return each["what"] == "truffles"), "and Rolf no longer offers for them")
	var rows: Array = _main.person_takes(host, "truff_tav").filter(func(each: Dictionary) -> bool: return each["what"] == "truffles")
	_check(rows.size() == 1 and rows[0]["for"]["name"] == "the pot" and int(rows[0]["gold"]) == 4 * int(rows[0]["count"]),
		"her row: for the pot, 4 gold a truffle, paid in full (%s)" % [rows])
	_check(_main.depot_pointer(STORE, "truffles") == "That goes to the Mughouse.", "the chest's pointer: to the Mughouse (%s)" % _main.depot_pointer(STORE, "truffles"))
	var purse := economy.gold(me)
	var sold: Array = _main.give_to(host, "truff_tav", "Tess", [int(rows[0]["uid"]) if rows.size() == 1 else 0])
	_check(sold.size() == 1 and World.count_of(host, "truffles") == 0 and economy.gold(me) == purse + (int(rows[0]["gold"]) if rows.size() == 1 else -1)
		and World.stockpile.count(STORE, "truffles") >= 1, "given: banked, paid what the row said")
	World.production.remove_worker("truff_tav")
	for id in away:
		World.production.set_away(id, false)
	economy.rules["vendor"] = vendor


## 821 amended: a maker buys his own recipes' non-resource inputs by Give
## (the medicine man the claw, feathers and flint for the charm), before the
## tanner or Rolf; off while receives.inputs.recipes is empty; banked by id,
## the charm's bid follows once "charm" is wanted.
func _test_charm_inputs(host: Player) -> void:
	print("\n== 821 amended: a maker buys his own inputs ==")
	var me: String = _main._id_of_player(host)
	var economy: Economy = World.economy
	var inputs: Dictionary = economy.rules["receives"].get("inputs", {}).duplicate(true)
	var vendor: Dictionary = economy.rules.get("vendor", {}).duplicate(true)
	economy.rules["vendor"] = {"towns": [STORE], "name": "Rolf", "price": 1, "wares": []}
	var hut_lists: Dictionary = World.production.rules.get("return", {}).get("places", {}).get("healers_hut", {}).get("makes", {})
	_check(inputs.get("recipes", []) == ["bear_claw_charm", "bear_grease_draught"] and inputs.get("only_listed", []) == ["bear_claw_charm", "bear_grease_draught"]
		and World.production.rules.get("receives", {}).get("inputs", {}).get("only_listed", []) == inputs["only_listed"]
		and "charm" in World.production.rules.get("always_want", []) and "bear_claw_charm" in hut_lists.get("wilds", [])
		and "bear_grease_draught" in hut_lists.get("wilds", []) and "bear_claw_charm" not in hut_lists.get("_default", []),
		"switched on: both recipes bought for, made only where a list names them, the wilds hut's list naming both")
	var away: Array[String] = []
	for id: String in World.production.worker_ids(STORE):
		var trades: Array = World.production.worker(id)["trades"]
		if ("medicine_man" in trades or "tanner" in trades) and not World.production.worker(id).get("away", false):
			World.production.set_away(id, true)  # Put back at the end.
			away.append(id)
	_check(str(_main.bought_by(STORE, "bear_claw").get("worker", "")) == Offers.VENDOR + STORE, "no medicine man: the claw still Rolf's to buy (821)")
	# Lore's one medicine man (the coordinator's check): one seated in a town, at a shop with no
	# makes list (every recipe of his trade), with every part in the store, never bids the charm
	# or the draught, nor buys their parts; the claw goes to the tanner.
	var hut := "test_charm_hut"
	World.production.add_worker("charm_mm", "Probewort", ["medicine_man"], STORE, "test")
	World.production.add_workshop(hut, "medicine_man", STORE)
	World.production.assign(hut, "charm_mm")
	World.production.add_worker("charm_tan", "Tamsin", ["tanner"], STORE, "test")
	var parts: Array[int] = []
	for id: String in ["bear_claw", "feathers", "flint", "bear_grease"]:
		parts.append(World.items.mint(id, "found", "test"))
		World.stockpile.bank(STORE, parts.back(), "test")
	World.stockpile.deposit(STORE, "herbs", 4, "test")
	var cat_off := Production.items_catalog()
	var signals_off := World.production.signals_of(STORE, cat_off)
	var bid_off: Dictionary = World.production._bid(World.production.workshop(hut), ["charm", "medical", "goods"] as Array[String], signals_off, cat_off)
	_check(not World.production.makes(hut, "bear_claw_charm") and not World.production.makes(hut, "bear_grease_draught") and World.production.makes(hut, "remedy")
		and str(bid_off.get("recipe", "")) not in ["bear_claw_charm", "bear_grease_draught"],
		"a town's medicine man, his parts all in the store: neither the charm nor the draught (bid %s)" % [bid_off.get("recipe", "")])
	_check(str(_main.bought_by(STORE, "bear_claw").get("worker", "")) == "charm_tan" and _main.input_taker(STORE, "bear_claw").is_empty(),
		"nor buys the claw: still the tanner's (821)")
	World.production.remove_worker("charm_tan")
	for uid: int in parts:
		World.stockpile.take_item(STORE, uid, "test")
		World.items.end(uid, "gone")
	World.stockpile.take(STORE, "herbs", 4, "test")
	World.production.remove_worker("charm_mm")
	# The wilds hut's medicine man: the test shop given the wilds hut's makes list.
	var old_makes: Callable = World.production.workshop_makes
	var wilds_list: Array = hut_lists.get("wilds", [])
	World.production.workshop_makes = func(id: String) -> Array: return wilds_list if id == hut else (old_makes.call(id) if old_makes.is_valid() else [])
	_check(economy.input_ids() == ["bear_claw", "bear_grease", "feathers", "flint"] and economy.input_recipes("herbs").is_empty(),
		"on: the claw, grease, feathers and flint; herbs stay a raw (%s)" % [economy.input_ids()])
	_check(_main.input_taker(STORE, "feathers").is_empty() and _main.bought_by(STORE, "feathers").is_empty(), "no medicine man: nobody buys feathers")
	World.production.add_worker("charm_mm", "Probewort", ["medicine_man"], STORE, "test")
	World.production.assign(hut, "charm_mm")
	_check(_main.input_taker(STORE, "bear_claw") == ["charm_mm", "bear_claw_charm"] and _main.bought_by(STORE, "bear_claw")["for"] == "a bear's-claw charm",
		"the wilds hut's medicine man seated: he buys the claw, for a bear's-claw charm (%s)" % [_main.bought_by(STORE, "bear_claw")])
	for slot: int in [Items.PACK_SLOTS[0], Items.PACK_SLOTS[1], Items.PACK_SLOTS[2]]:
		if not str(host.slots[slot]).is_empty():
			World.take_item(host, host, slot)
	for id: String in ["bear_claw", "feathers", "flint"]:
		_main._hand_item(me, id, "test")
		var held: int = Array(host.slots).find(id)
		if held not in Items.PACK_SLOTS:
			World.try_transfer(host, host, held, host, Items.PACK_SLOTS[["bear_claw", "feathers", "flint"].find(id)])
	var rolf: Array = _main.person_takes(host, Offers.VENDOR + STORE).filter(func(row: Dictionary) -> bool: return row["what"] in ["bear_claw", "feathers", "flint"])
	_check(rolf.is_empty(), "Rolf no longer offers for them (%s)" % [rolf])
	var rows: Array = _main.person_takes(host, "charm_mm").filter(func(row: Dictionary) -> bool: return row["what"] in ["bear_claw", "feathers", "flint"])
	var paid := {}
	for row: Dictionary in rows:
		if row["for"].get("kind") == "maker" and row["for"].get("name") == "a bear's-claw charm" and int(row["count"]) == 1:
			paid[row["what"]] = int(row["gold"])
	_check(paid == {"bear_claw": 3, "feathers": 1, "flint": 1}, "his rows: for a bear's-claw charm, 3 for the claw, 1 each for feathers and flint (%s)" % [rows])
	var takers: Dictionary = _main.takers_of(STORE)
	_check(Main.taker_line(takers, "feathers") == "For the medicine man" and Main.taker_entry(takers, "bear_claw").get("name") == "Probewort",
		"the pack's tooltip: for the medicine man (%s)" % [takers.get("trophies", {})])
	var had := {}
	for id: String in ["bear_claw", "feathers", "flint"]:
		had[id] = World.stockpile.count(STORE, id)
	var purse := economy.gold(me)
	var given: Array = _main.give_to(host, "charm_mm", "Probewort", rows.map(func(row: Dictionary) -> int: return int(row["uid"])))
	var gold := 0
	for row: Dictionary in rows:
		gold += int(row["gold"])
	_check(given.size() == 3 and ["bear_claw", "feathers", "flint"].all(func(id: String) -> bool: return World.stockpile.count(STORE, id) == int(had[id]) + 1)
		and economy.gold(me) == purse + gold, "given: each banked by id, paid what the rows said (%d gold)" % (economy.gold(me) - purse))
	var cat := Production.items_catalog()
	var signals := World.production.signals_of(STORE, cat)
	var wants := World.production._wants(STORE, signals)
	var bid: Dictionary = World.production._bid(World.production.workshop(hut), ["charm"] as Array[String], signals, cat)
	_check("charm" in wants and str(bid.get("recipe", "")) == "bear_claw_charm", "with charm wanted, his bid: the charm from the store's parts (%s)" % [bid])
	World.production.remove_worker("charm_mm")
	World.production._workshops.erase(hut)
	_check(str(_main.bought_by(STORE, "bear_claw").get("worker", "")) == Offers.VENDOR + STORE, "no maker again: the claw back to Rolf (821)")
	World.production.workshop_makes = old_makes
	for id in away:
		World.production.set_away(id, false)
	economy.rules["vendor"] = vendor


## The admin's stock and give (709 amended; playtest's 804 tour): a store's
## raw and treasury set either way, logged as the admin's; new items handed a
## player; nonsense refused.
func _test_admin_stock(host: Player) -> void:
	print("
== the admin's stock and give (709 amended) ==")
	var reply: String = _main.admin_command("stock %s wood 3" % STORE)
	_check(World.stockpile.count(STORE, "wood") == 3, "stock wood 3: the store holds 3 wood (%s)" % reply)
	_main.admin_command("stock %s wood 41" % STORE)
	_main.admin_command("stock %s gold 0" % STORE)
	_check(World.stockpile.count(STORE, "wood") == 41 and World.stockpile.count(STORE, "gold") == 0, "raised to 41 wood, the treasury emptied")
	_check(_main.admin_command("stock %s crowns 2" % STORE).begins_with("stock: crowns isn't a raw")
		and _main.admin_command("stock nowhere/store wood 2").begins_with("stock: no town store")
		and _main.admin_command("stock %s wood -1" % STORE).begins_with("usage"), "a thing that isn't a raw, no such store, a count under 0: refused")
	var had := World.count_of(host, "wood_bundle")
	reply = _main.admin_command("give %s wood_bundle 4" % host.name)
	_check(World.count_of(host, "wood_bundle") == had + 4, "give: 4 bundles of wood in their pack (%s)" % reply)
	_check("wood_bundle" in _main.admin_command("give %s wood 2" % host.name), "a raw named: told what carries it")
	_check(_main.admin_command("give %s nothing_such 2" % host.name).begins_with("give: no item")
		and _main.admin_command("give nobody wood 2").begins_with("no player"), "no such item, no such player: refused")
	_main.admin_command("stock %s gold 100" % STORE)


## The town window (768, economy's side): the sheet's new fields for the
## player at the store, Donate ("contribute") banking a thing the town is
## short of with the town's regard moved and the effect noted, the day's cap,
## and the refusal away from the store.
func _test_town_window(host: Player) -> void:
	print("\n== the town window (768) ==")
	var me := host.player_id
	var sheet: Dictionary = _main.ask_town_sheet(host, {"town": STORE})
	_check(sheet.get("at") == true and sheet["gold"] == World.gold_of(me) and sheet["pack"] == _main._pack_rows(host),
		"at the store: at, their gold, their pack as the barter lists it")
	_check(["stock", "pays", "build", "regard", "state", "asks", "recent"].all(func(key: String) -> bool: return sheet.has(key)) and not sheet.has("owed"),
		"every field there (%s)" % [sheet.keys()])
	var wood_row: Array = sheet["stock"].filter(func(row: Dictionary) -> bool: return row["id"] == "wood")
	_check(wood_row.size() == 1 and int(wood_row[0]["enough"]) >= int(World.economy.rules["comfort"]["wood"]) and wood_row[0]["item"] == "wood",
		"wood in stock: enough at least its comfort, drawn as wood (%s)" % [wood_row])
	_check(sheet["stock"].any(func(row: Dictionary) -> bool: return row["id"] == "weapon" and row.get("item") == "sword")
		and not sheet["stock"].any(func(row: Dictionary) -> bool: return row["id"] in ["gold", "herbs"]), "a weapon row drawn as a sword; no gold or herbs")
	_check(sheet["regard"]["word"] == "" and sheet["regard"]["score"] == 0.0 and sheet["regard"]["last"] == 0, "a stranger to the town at first")
	# Wood short: a bundle donated is banked, paid in full, and moves its regard.
	_no_wood()
	var bundle := World.items.mint("wood_bundle", "found", "test")
	World.put_item(host, host, 1, bundle)
	sheet = _main.ask_town_sheet(host, {"town": STORE})
	_check(sheet["pays"].has("wood_bundle") and int(sheet["pays"]["wood_bundle"]["gold"]) > 0, "the bundle in pays (%s)" % [sheet["pays"]])
	var gold_was := World.gold_of(me)
	var given: Dictionary = _main.contribute(host, {"town": STORE, "give": [bundle], "gold": 0})
	_check(host.slots[1] == "" and World.stockpile.count(STORE, "wood") == 5 and int(given.get("paid", -1)) == World.gold_of(me) - gold_was,
		"donated: the slot empty, 5 wood banked, paid said (%s)" % given.get("paid"))
	var regard: Dictionary = given["regard"]
	_check(regard["word"] == "known" and regard["score"] > 0.0 and regard["last"] == 1 and regard["why"].back() == Towns.REGARD_SHORT % "wood",
		"the town's regard up for wood it was short of (%s)" % [regard])
	_check(given["recent"].back() == {"kind": "sold", "id": "wood", "amount": 5}, "noted among their recent effects (%s)" % [given["recent"]])
	# 804, economy's side: one rise and one thanks for the hand-in, shown.
	var sent: Array = _main.rewards_given.filter(func(each: Dictionary) -> bool: return each["player"] == me).slice(-3)
	var rise: Dictionary = sent[0]["data"] if sent.size() == 3 else {}
	_check(rise.get("track") == "regard" and rise.get("words") == Towns.REGARD_SHORT % "wood"
		and is_equal_approx(float(rise.get("amount", 0)), int(World.economy.rules["town_regard"]["short"]) / 2.0)
		and rise.get("step") == "known" and rise.get("big") == true and str(rise.get("banner", "")).ends_with(" knows you"),
		"804: the regard's rise sent, its words and amount; a stranger's first, a step bannered \"... knows you\" (%s)" % [rise])
	var thanks: Dictionary = sent[1]["data"] if sent.size() == 3 else {}
	_check(thanks.get("track") == "item" and thanks.get("of") == "the market" and thanks.get("words") == "The store takes 5 wood" and int(thanks.get("amount", 0)) == 5
		and int(thanks.get("gold", 0)) == int(given["paid"]) and thanks.get("bars", []).any(func(bar: Dictionary) -> bool: return bar["id"] == "wood" and int(bar["have"]) == 5)
		and thanks.get("place") == STORE and thanks.get("given") == {"wood": 5} and thanks.get("counted") == "5 wood",
		"804: then the store's thanks: its words, the count, the gold paid, wood's bar, the place and what was given (%s)" % [thanks])
	var pay: Dictionary = sent[2]["data"] if sent.size() == 3 else {}
	_check(pay.get("track") == "gold" and int(pay.get("amount", 0)) == int(given["paid"]) and pay.get("words") == Main.PAID_WORDS % int(given["paid"]),
		"804, economy's side: the gold paid floats as gold (%s)" % [pay])
	# Wood at its enough, under twice it: handed in (World.donate, thanked at the frame's end), a
	# half for what the town can use.
	var enough := int(_main.town_stock(STORE).filter(func(row: Dictionary) -> bool: return row["id"] == "wood")[0]["enough"])
	World.stockpile.deposit(STORE, "wood", enough - World.stockpile.count(STORE, "wood"), "test")
	var halves_was := int(World.towns.to_dict()[STORE]["regard"][me]["halves"])
	var handed := World.items.mint("wood_bundle", "found", "test")
	World.put_item(host, host, 1, handed)
	_check(World.donate(host, handed, STORE), "(a bundle handed in)")
	await get_tree().process_frame
	var used: Dictionary = World.towns.to_dict()[STORE]["regard"][me]
	_check(int(used["halves"]) == halves_was + int(World.economy.rules["town_regard"]["use"]) and used["why"].back() == Towns.REGARD_USE % "wood",
		"at its enough, under twice it: a half for wood the town can use (%s)" % [used["why"].back()])
	# The day's cap: two more short gifts move it only to day_most.
	for i in 2:
		_no_wood()
		var more := World.items.mint("wood_bundle", "found", "test")
		World.put_item(host, host, 1, more)
		_main.contribute(host, {"town": STORE, "give": [more], "gold": 0})
	var halves := int(World.towns.to_dict()[STORE]["regard"][me]["halves"])
	_check(halves == int(World.economy.rules["town_regard"]["day_most"]), "a day's gains capped at day_most halves (%d)" % halves)
	await _test_build_credit(host)
	# Away from the store: voice's refusal, nothing moved.
	var was := host.tile
	host.tile = Vector2i(-50, -50)
	var refused: Dictionary = _main.contribute(host, {"town": STORE, "give": [], "gold": 5})
	_check(refused.get("why") == Main.DONATE_AWAY and _main.ask_town_sheet(host, {"town": STORE}).get("at") == false
		and _main.ask_town_sheet(host, {"town": STORE})["pack"] == [], "away: refused in voice's words; the sheet not at, no pack")
	host.tile = was
	var treasury: int = World.stockpile.count(STORE, "gold")
	World.stockpile.take(STORE, "gold", treasury, "test")
	_main._hand_item(me, "hide", "test")
	var hide_uid: int = World.slot_uid(host, Array(host.slots).find("hide"))
	var count_before: int = _main.rewards_given.size()
	World.donate(host, hide_uid, STORE)
	await get_tree().process_frame
	var after: Array = _main.rewards_given.slice(count_before).map(func(each: Dictionary) -> Dictionary: return each["data"])
	var gold_floats: Array = after.filter(func(data: Dictionary) -> bool: return data["track"] == "gold")
	_check(after.any(func(data: Dictionary) -> bool: return data["track"] == "item" and data.get("counted") == "1 hide")
		and gold_floats.size() == 1 and not gold_floats[0].has("owed") and int(gold_floats[0]["amount"]) > 0 and World.stockpile.count(STORE, "gold") == 0,
		"826: an empty treasury: the hide thanked and paid in full, the trade's credit paying (%s)" % [after])
	World.stockpile.deposit(STORE, "gold", treasury, "test")
	World.economy._trade_debt.erase(STORE)  # The test's own debt: not left for later checks.


## 804 amended, the build credit: raws a queued build lacked, handed in,
## and gold given toward it are kept on its entry; when it stands, each
## giver is told in voice's words, and it keeps them as built_by.
func _test_build_credit(host: Player) -> void:
	var me := host.player_id
	World.towns.add_xp(STORE, 500, "test")
	var kind := ""
	for each: String in ["temple", "forge", "kitchen", "inn"]:
		if World.towns.unlock(STORE, each):
			kind = each
			break
	var short := World.towns.shortfall(STORE)
	_check(not kind.is_empty() and not short.is_empty(), "(a build begun and queued: %s, %s)" % [kind, short])
	if short.is_empty():
		return
	kind = str(short["kind"])
	var lacks: Dictionary = short["needs"]
	var raw := "ore" if lacks.has("ore") else str(lacks.keys()[0]) if not lacks.is_empty() else ""
	if not raw.is_empty():
		var sack := World.items.mint({"ore": "ore_sack", "wood": "wood_bundle"}.get(raw, "ore_sack"), "found", "test")
		World.put_item(host, host, 1, sack)
		World.donate(host, sack, STORE)
		await get_tree().process_frame
	var given := World.economy.contribute(STORE, me, 5) if World.gold_of(me) >= 5 else 0
	var entry: Dictionary = World.towns.to_dict()[STORE]["buildings"].get(kind.trim_prefix(Towns.REPAIR), {})
	var by: Dictionary = entry.get("by", {}).get(me, {})
	_check((raw.is_empty() or int(by.get(raw, 0)) > 0) and (given == 0 or int(by.get("gold", 0)) == given),
		"what it lacked, handed in, and the gold given are credited to the build (%s)" % [by])
	World.towns._built(STORE, kind)
	var last: Dictionary = _main.rewards_given.back()["data"] if not _main.rewards_given.is_empty() else {}
	_check(last.get("track") == "deed" and last.get("big") == true and str(last.get("words", "")).begins_with("The %s stands, built with your " % Main._building_words(kind))
		and World.towns.to_dict()[STORE]["buildings"][kind].get("built_by", {}).has(me) and not World.towns.to_dict()[STORE]["buildings"][kind].has("by"),
		"when it stands, the giver told in a banner (%s); built_by kept" % last.get("words"))


func _no_wood() -> void:
	if World.stockpile.count(STORE, "wood") > 0:
		World.stockpile.take(STORE, "wood", World.stockpile.count(STORE, "wood"), "test")


## A herder's drove bought by the town (640, economy's side): as many as
## the treasury pays above gold_floor at the store's sheep price, the gold
## to the herder (taxed as a sale), never owed; then food bought for their
## keep, the gold back to the treasury.
func _test_drove() -> void:
	print("
== a herder's drove ==")
	var economy := World.economy
	var stock := World.stockpile
	World.production.add_worker("herder:test", "Grim", ["herder"], "nowhere/hut")
	var unit := maxi(roundi(economy.raw_price(STORE, "sheep") * float(economy.rules["store"]["buy"])), 1)
	var floor_gold := int(economy.rules.get("gold_floor", 0))
	var gold := stock.count(STORE, "gold")
	if gold > floor_gold + unit * 2:
		stock.take(STORE, "gold", gold - floor_gold - unit * 2, "test")
	var sheep := stock.count(STORE, "sheep")
	stock.deposit(STORE, "food", 5, "test")
	var food := stock.count(STORE, "food")
	_check(economy.buy_drove(STORE, "herder:test", 5, 0) == 2 and stock.count(STORE, "sheep") == sheep + 2 and stock.count(STORE, "gold") == floor_gold + int(Economy.taxed(unit * 2, "sale", economy.rules)[0])
		and int(World.production.worker("herder:test")["owed"]) == 0 and int(World.production.worker("herder:test")["purse"]) > 0,
		"a treasury with 2 sheep's worth over its floor buys 2 of 5, owing nothing (%d)" % stock.count(STORE, "sheep"))
	var purse := int(World.production.worker("herder:test")["purse"])
	var each := economy.raw_price(STORE, "food")
	stock.deposit(STORE, "gold", unit * 3, "test")
	var before := stock.count(STORE, "gold")
	var bought := economy.buy_drove(STORE, "herder:test", 1, 2)
	var ate := mini(2, floori(float(purse + unit) / each))
	_check(bought == 1 and stock.count(STORE, "food") == food - ate, "with the gold, food for their keep (%d eaten)" % (food - stock.count(STORE, "food")))
	_check(stock.count(STORE, "gold") == before - unit + int(Economy.taxed(unit, "sale", economy.rules)[0]) + ate * each, "the food's gold back to the treasury")
	World.production.remove_worker("herder:test")


## The "give_gold" command (614) in Main: to a second player beside the
## host, both told; refused out of reach, over the purse, to a resident.
func _test_give_in_town(host: Player) -> void:
	print("
== the give_gold command ==")
	_main._admit(4242, "11111111-0000-4000-8000-000000004242", "Bo")
	await get_tree().process_frame
	var bo: Player = null
	for entity in World.get_entities():
		if entity is Player and entity != host:
			bo = entity
	_check(bo != null, "a second player")
	if bo == null:
		return
	World._relocate(host, Vector2i(5, 3))
	World._relocate(bo, Vector2i(6, 3))
	var me := host.player_id
	World.add_gold(me, 20, "test")
	var had := World.gold_of(me)
	var bo_had := World.gold_of(bo.player_id)
	_check(_main.give_gold(host, {"to": str(bo.get_path()), "amount": 7}) == 7 and World.gold_of(me) == had - 7 and World.gold_of(bo.player_id) == bo_had + 7,
		"7 gold to Bo beside the host")
	_check(_main.give_gold(host, {"to": str(bo.get_path()), "amount": had + 1}) == 0 and World.gold_of(me) == had - 7, "not more than the host has")
	_check(_main.give_gold(host, {"from": str(bo.get_path()), "amount": 1}) == 0, "never taken from another player")
	World._relocate(bo, Vector2i(5 + World.COMPANION_REACH + 2, 3))
	_check(_main.give_gold(host, {"to": str(bo.get_path()), "amount": 1}) == 0 and World.gold_of(bo.player_id) == bo_had + 7, "nor out of reach")


## The console's "makers" (the coordinator's ask, after Hob's empty shelf):
## a maker's trade and town, their own make on the shelf counted, never a
## name; one with nothing says so; a smith's sword is not the medicine man's.
func _test_makers_command() -> void:
	print("\n== the console's makers: each maker's own goods on the shelf, by count, no names ==")
	var maker := "medicine_man:%s" % STORE
	var line := "medicine_man at %s" % STORE
	_check(World.production.add_worker(maker, "Probewort", ["medicine_man"], STORE, "test"), "(a medicine man in the town)")
	var empty: String = _main._makers_command(PackedStringArray(["makers", "medicine_man"]))
	_check("%s: nothing on the shelf" % line in empty and not "Probewort" in empty, "none made yet: nothing on the shelf (%s)" % empty)
	var potions := [World.items.mint("remedy", "made", "test"), World.items.mint("remedy", "made", "test")]
	for uid: int in potions:
		World.stockpile.stock_shop(STORE, uid, "Probewort", maker)
	var full: String = _main._makers_command(PackedStringArray(["makers"]))
	_check("%s: remedy x2" % line in full and not "Probewort" in full, "two remedies of his own, counted, his name kept out (%s)" % full)
	var town_line := Array(full.split("\n")).filter(func(each: String) -> bool: return each.begins_with("%s: shelf " % STORE))
	_check(town_line.size() == 1 and "remedy x2" in town_line[0] and "; store " in town_line[0], "the town's line: its whole shelf and its store's raws (%s)" % [town_line])
	_check(_main._makers_command(PackedStringArray(["makers", "no_such_trade"])) == "no makers matching no_such_trade", "a filter matching none says so")
	# A companion who stays to work for the town (767 amended): listed so, nameless.
	var stays := Townsfolk.COMPANION + "probe_stays"
	World.production.add_worker(stays, "Probehild", ["carpenter"], STORE, "test")
	World.towns._town(STORE)["residents"].append(stays)
	var with_her: String = _main._makers_command(PackedStringArray(["makers", "carpenter"]))
	_check("carpenter (a companion) at %s" % STORE in with_her and not "Probehild" in with_her, "a staying companion: '(a companion)', no name (%s)" % with_her)
	World.towns._town(STORE)["residents"].erase(stays)
	World.production.remove_worker(stays)
	for uid: int in potions:
		World.stockpile.take_from_shop(STORE, uid, "test")
		World.items.end(uid, "gone")
	World.production.remove_worker(maker)
