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
	_check(economy.stockpile.count(TOWN, "gold") == 103 and int(economy.production.worker("bram")["purse"]) == 15,
		"the sale tax (3) to the treasury, 15 to Bram who made it (%d, %s)" % [economy.stockpile.count(TOWN, "gold"), economy.production.worker("bram")])
	_check(not economy.stockpile.shop(TOWN).has(uid) and economy.stockpile.book.at_of(uid) == ""
		and economy.stockpile.book.history(uid)["events"].any(func(event: Dictionary) -> bool: return event["kind"] == "bought"),
		"out of the shop, held by nothing until put somewhere, its history says bought")
	_check(economy.production.signals_of(TOWN, CATALOG)["sold"] == {"sword": 1}, "the town notes the sale (its workshops work it up)")
	_check(not economy.buy("p1", TOWN, uid)["ok"], "it can't be bought twice")
	var bought := economy.stockpile.book.mint("crown", "found", "test")
	economy.stockpile.stock_shop(TOWN, bought, "sold:p2")
	economy.buy("p1", TOWN, bought)
	_check(economy.stockpile.count(TOWN, "gold") == 123 and economy.gold("p1") == 12,
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
	remove_child(_main)
	_main.free()
	World.clear_zones()
	World.economy = null
	DirAccess.remove_absolute(Net.state_path)
	Net.state_path = ""
	Net.map_name = ""
	Level.unregister(ZONE)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
