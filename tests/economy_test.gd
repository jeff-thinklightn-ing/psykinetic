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
	_test_barter()
	_test_maker_barter()
	_test_barrow_charges()
	_test_robbers_band()
	_test_restart()
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
	_check(economy.stockpile.count(TOWN, "gold") == 26 and economy.refuses(TOWN, "ore_sack") == "the town can't pay for it now",
		"26 gold, a floor of 20: it can't pay 9 for ore")


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
	_check(economy.barter_quote(TOWN, "p1", [{"id": "ore_sack"}], [])["why"] == "the town can't pay for it now", "25 gold over a floor of 20: can't pay 9")


## The medicine man's barter (decision 562; Jeff: "hob can have a stamina
## potion ... and trades for herbs - other npcs don't find herbs useful").
func _test_robbers_band() -> void:
	print("
== the grave robbers' purse (580, economy's side) ==")
	var robbers: Dictionary = Production.read_rules(Economy.PATH)["robbers"]
	_check(float(robbers["altar_share"]) == 0.5 and float(robbers["thief_cut"]) == 0.25 and int(robbers["most"]) == 40
		and robbers["kinds"] == ["robber"] and robbers["barrow"] == "barrow", "the rules are economy.json's (%s)" % [robbers])
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
	_check(economy.band_share("barrow", 3) == 10 and economy.band_gold("barrow") == 29, "one of three falls: 39 / 3 is 13, a whole purse of 10")
	economy.band_add("barrow", 200, "test")
	_check(economy.band_share("barrow", 1) == 40, "at most 40 on one robber")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(economy.to_dict()))
	var loaded := Economy.new(saved, stock, work, clock, rules, func() -> Dictionary: return CATALOG)
	_check(loaded.band_gold("barrow") == 189 and loaded._band_day == 1, "the purse and its day saved (%d)" % loaded.band_gold("barrow"))
	_check(_fresh().band_share("barrow", 1) == 0, "no rules, no gold: empty pockets")


func _test_barrow_charges() -> void:
	print("== the draugr's deals and a player's charges (573, economy's side) ==")
	var field: Dictionary = Production.read_rules()["return"]["field"]
	_check(Economy.deal_for(19, field).is_empty(), "under 20 gold: no deal")
	_check(Economy.deal_for(20, field).get("name") == "easy" and Economy.deal_for(99, field).get("name") == "normal"
		and Economy.deal_for(500, field).get("name") == "hard", "20 buys easy, 99 normal, 500 hard: the highest step reached")
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
	_check(buys == {"herbs": {"gold": 2, "up_to": 5}}, "herbs at 2 (none in store: twice their value), as many as his 10 gold pays: 5; no ore (%s)" % [buys])
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
	_check(_main.shop_panel.shop == counter and _main.shop_panel.rows_shown() == ["bandaging kit 1 gold"],
		"opened, the panel shows the kit at 1 gold (%s)" % [_main.shop_panel.rows_shown()])
	_check(_main.shop_panel.gold_shown() == "0 gold", "and the host's gold: none")
	_main._buy(counter, kit)
	_check(_main.shop_panel.why_shown() == "not enough gold (1)" and host.slots[0] == "", "Buy with no gold: refused, said why")
	World.add_gold(me, 10, "purse")
	_check(_main.gold == 10 and _main.shop_panel.gold_shown() == "10 gold", "a purse opened: the client shows 10 gold")
	_main._buy(counter, kit)
	_check(host.slots[0] == "bandaging_kit" and World.slot_uid(host, 0) == kit and _main.gold == 9,
		"bought: the kit in the host's pack, 9 gold left (%s, %d)" % [Array(host.slots), _main.gold])
	_check(_main.shop_panel.rows_shown().is_empty() and _main.shop_panel.why_shown() == "", "the panel: nothing left for sale")
	var ore := World.items.mint("ore_sack", "found", "test")
	World.put_item(host, host, 1, ore)
	_main.open_other(counter)
	_main._send_shop(host, counter)
	_check(_main.shop_panel._offer_label.text.contains("sack of ore 9 gold"), "the town would pay 9 for the sack of ore (%s)" % _main.shop_panel._offer_label.text)
	_check(World.try_transfer(host, host, 1, counter, 0), "the host puts the sack in the counter: sold")
	_check(host.slots[1] == "" and counter.slots[0] == "" and World.stockpile.count(STORE, "ore") == 5 and _main.gold == 18,
		"the slot empty, the counter keeps nothing, 5 ore banked, 18 gold (%d)" % _main.gold)
	var purse := World.items.mint("coin_purse", "found", "test")
	World.put_item(host, host, 1, purse)
	_check(not World.try_transfer(host, host, 1, counter, 0) and host.slots[1] == "coin_purse"
		and _main.shop_panel.why_shown().begins_with("gold is given"), "a coin purse in the counter: refused, said why")
	_main._save_state()
	_check(Snapshot.load(Net.state_path)["economy"]["purses"].get(me) == 18, "the snapshot keeps the host's 18 gold")
	await _test_barter_in_town(host, counter)
	_test_robber_falls(host)
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
		and kit in World.slot_uids(host) and ore not in World.slot_uids(host) and kit not in World.stockpile.shop(STORE),
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
	var dropped := Array(World.ground_at(at)).filter(func(id: String) -> bool: return id == "coin_purse")
	_check(dropped.size() == 2 and World.economy.band_gold(World.zone.name) == 30, "one of two falls: 25 is two purses of 10, 30 left the band (%s)"
		% [Array(World.ground_at(at))])
	var none: GridEntity = _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "kind": "skeleton", "name": "Bones",
		"tile": _main._nearest_free(host.tile + Vector2i(-3, 2))})
	var bones_at: Vector2i = none.tile
	var before := Array(World.ground_at(bones_at)).count("coin_purse")
	World.damage(none, 999)
	_check(Array(World.ground_at(bones_at)).count("coin_purse") == before and World.economy.band_gold(World.zone.name) == 30,
		"a skeleton carries none of it (%s)" % [Array(World.ground_at(bones_at))])
	World.damage(robbers[1], 999)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
