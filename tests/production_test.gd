extends Node
## The town's work (Production) on a clock of its own: a test town (made in
## code) with a stockpile place and a goblin camp beside it, three
## placeholder workers (a smith, a carpenter, a cook) in three workshops,
## and a test catalog of recipes and rules. Workshops choose their work
## from the town's tier (STOCK: the scarcest first; DEFEND: arms first;
## WORK UP: what players sold; SURPLUS: goods and reworks; IDLE) and
## compete for the same raws, the loser waiting; a tier holds two ticks
## before it changes; jobs take their materials at the start, advance
## only while their worker is there, finish into the shop on time and
## after a restart, give their materials back when cancelled; a rework
## keeps the thing; wages are taxed and stop at the gold floor; rent leaves
## the economy; World's world tick runs it.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const TOWN := "pt_town"
const STORE := "pt_town/store"
const CAMP := "pt_town/camp"

const CATALOG := {
	"sword": {"id": "sword", "tags": ["weapon"], "made": {"by": "smith", "from": {"ore": 3, "wood": 1}, "steps": 3000}},
	"shield": {"id": "shield", "tags": ["shield"], "made": {"by": "carpenter", "from": {"wood": 3}, "steps": 2000}},
	"bandage_roll": {"id": "bandage_roll", "tags": ["bandage"], "made": {"by": "cook", "from": {"cloth": 1}, "steps": 1000}},
	"meal": {"id": "meal", "tags": ["food"], "made": {"by": "cook", "from": {"food": 2}, "steps": 600}},
}
const RULES := {
	"window": 6000, "tier_hold": 2, "starve_after": 3,
	"comfort": {"gold": 50, "ore": 5, "wood": 5, "cloth": 2, "food": 4},
	"wants": {"weapon": 2, "shield": 1, "bandage": 2, "food": 2},
	"uneasy_extra": {"weapon": 1},
	"shop_cap": 3,
	"tiers": {"defend": ["repair", "weapon", "shield", "bandage", "food"], "stock": ["bandage", "food", "weapon", "shield"],
		"surplus": ["goods", "rework"]},
	"work_up": {"ore": ["weapon", "shield"], "wood": ["shield", "weapon"], "cloth": ["bandage"], "food": ["food"]},
	"defend_trades": ["smith", "carpenter", "cook"],
	"busy": {"quiet_below": 0, "busy_from": 100000},
	"wage": 10, "tax": {"wage": 0.1, "sale": 0.2}, "rent": 3, "rent_every": 6000, "gold_floor": 20,
}

var _failures := 0
var _now := 0
var _holdings: Holdings
var _stock: Stockpile
var _book: ItemBook
var _work: Production


func _ready() -> void:
	World.set_process(false)
	_register_town()

	_test_taxed()
	_test_competing()
	_test_tier_holds()
	_test_defend_and_work_up()
	_test_away_and_restart()
	_test_cancel_and_rework()
	_test_surplus_and_idle()
	_test_wages_and_rent()
	_test_world_tick()

	Level.unregister(TOWN)
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## pt_town: 20 x 10 cells; the store (a stockpile the town holds) at
## (4, 4), radius 3; a camp nobody holds at (15, 5), radius 3.
func _register_town() -> void:
	var rows: Array[String] = []
	for y in 19:
		rows.append(".".repeat(39))
	Level.register(TOWN, Level.image_from_rows(rows), null, {"places": {
		"store": {"at": [4, 4], "kind": "stockpile", "radius": 3, "holder": "town"},
		"camp": {"at": [15, 5], "kind": "camp", "radius": 3, "holder": "nobody"},
	}})


## A fresh town at step 0 with [param resources] banked: Bram the smith at
## the forge, Dag the carpenter at the bench, Cora the cook at the kitchen.
func _fresh(resources: Dictionary, rules := RULES) -> void:
	_now = 0
	var clock := func() -> int: return _now
	_holdings = Holdings.new(WorldMap.build(_strings([TOWN])), null, {}, clock)
	_book = ItemBook.new(clock)
	_stock = Stockpile.new({}, clock, _book)
	for what: String in resources:
		_stock.deposit(STORE, what, int(resources[what]), "test")
	_work = Production.new({}, _stock, _holdings, clock, rules, func() -> Dictionary: return CATALOG)
	_work.add_worker("bram", "Bram", ["smith"], STORE)
	_work.add_worker("dag", "Dag", ["carpenter"], STORE)
	_work.add_worker("cora", "Cora", ["cook"], STORE)
	_work.add_workshop("forge", "smith", STORE)
	_work.add_workshop("bench", "carpenter", STORE)
	_work.add_workshop("kitchen", "cook", STORE)
	_work.assign("forge", "bram")
	_work.assign("bench", "dag")
	_work.assign("kitchen", "cora")


func _at(step: int) -> void:
	_now = step
	_work.tick()


func _job_at(workshop_id: String) -> Dictionary:
	return _work.job(int(_work.workshop(workshop_id)["job"]))


func _shop_ids() -> Array[String]:
	var out: Array[String] = []
	for uid in _stock.shop(STORE):
		out.append(_book.id_of(uid))
	return out


func _test_taxed() -> void:
	print("\n== tax: a cut of every transaction, rounded down ==")
	_check(Production.taxed(10, "wage", RULES) == [1, 9] and Production.taxed(7, "sale", RULES) == [1, 6]
		and Production.taxed(10, "gift", RULES) == [0, 10], "10 in wages: 1 to the town, 9 paid; a sale of 7: 1 and 6; untaxed: all of it")


func _test_competing() -> void:
	print("\n== STOCK: the scarcest first, and workshops compete for the same wood ==")
	_fresh({"gold": 100, "ore": 6, "wood": 3, "cloth": 2, "food": 4})
	_check(not _work.assign("forge", "dag") and not _work.assign("bench", "bram"), "a worker works only at a workshop of their trade")
	_at(0)
	_check(_work.tier(STORE) == Production.STOCK, "short of everything: STOCK (%s)" % _work.tier(STORE))
	_check(_job_at("bench").get("recipe") == "shield" and _job_at("kitchen").get("recipe") == "bandage_roll",
		"the carpenter starts a shield, the cook a bandage roll")
	_check(_job_at("forge").is_empty() and _work.workshop("forge")["waited"] == 1,
		"the smith's sword needed wood the shield took first: the forge waits (%s)" % [_work.workshop("forge")])
	_check(_stock.count(STORE, "wood") == 0 and _stock.count(STORE, "cloth") == 1 and _stock.count(STORE, "ore") == 6,
		"materials were taken as the jobs started (%s)" % [_stock.resources(STORE)])
	_at(1000)
	_check(_shop_ids() == _strings(["bandage_roll"]), "at step 1000 the bandage roll is in the shop (%s)" % [_shop_ids()])
	var roll := _stock.shop(STORE)[0]
	_check(_book.history(roll)["events"][0]["kind"] == "made" and _book.at_of(roll) == Stockpile.shop_holder(STORE),
		"a new thing, made, at the shop (%s)" % [_book.history(roll)])
	_check(_job_at("kitchen").get("recipe") == "meal", "the cook goes on to a meal: food is short too (%s)" % [_job_at("kitchen")])
	_stock.deposit(STORE, "wood", 5, "test")
	_at(2000)
	_check(_shop_ids() == _strings(["bandage_roll", "shield", "meal"]), "the shield and the meal are done, in job order (%s)" % [_shop_ids()])
	_check(_job_at("forge").get("recipe") == "sword" and _work.workshop("forge")["waited"] == 0,
		"with wood banked the smith starts his sword (%s)" % [_job_at("forge")])
	_check(_job_at("bench").is_empty(), "the carpenter idles: the shop has the one shield the town wants")
	_at(5000)
	_check(_shop_ids().count("sword") == 1, "the sword is done at step 5000 (%s)" % [_shop_ids()])


func _test_tier_holds() -> void:
	print("\n== a tier changes only once the town's state has held two ticks ==")
	_fresh({"gold": 100, "ore": 30, "wood": 30, "cloth": 10, "food": 20})
	_at(0)
	_check(_work.tier(STORE) == Production.STOCK, "STOCK to begin with")
	_holdings.take(STORE, "goblins")
	_at(300)
	_check(_work.tier(STORE) == Production.STOCK, "the goblins take the store: still STOCK after one tick")
	_holdings.take(STORE, "town")
	_at(600)
	_check(_work.tier(STORE) == Production.STOCK, "the town takes it back: STOCK, nothing pending")
	_holdings.take(STORE, "goblins")
	_at(900)
	_check(_work.tier(STORE) == Production.STOCK, "the goblins again: one tick, STOCK")
	_at(1200)
	_check(_work.tier(STORE) == Production.DEFEND, "two ticks: DEFEND")


func _test_defend_and_work_up() -> void:
	print("\n== DEFEND puts arms first; WORK UP works up what players sold ==")
	_fresh({"gold": 100, "ore": 3, "wood": 3, "cloth": 10, "food": 20})
	_holdings.take(STORE, "goblins")
	_at(0)
	_check(_work.tier(STORE) == Production.DEFEND, "the store held by goblins: DEFEND from the start")
	_check(_job_at("forge").get("recipe") == "sword" and _job_at("bench").is_empty() and _work.workshop("bench")["waited"] == 1,
		"the smith goes first and takes the wood for a sword; the carpenter's shield waits (%s)" % [_job_at("bench")])
	_check(_job_at("kitchen").get("recipe") == "bandage_roll", "the cook makes bandages before meals")
	_holdings.take(STORE, "town")
	_holdings.take(CAMP, "goblins")
	_work.note_sale(STORE, "wood", 6)
	_stock.deposit(STORE, "wood", 6, "sale:test")
	_at(300)
	_at(600)
	_check(_work.tier(STORE) == Production.WORK_UP, "players sold wood: WORK UP (%s)" % _work.tier(STORE))
	_check(_job_at("bench").get("recipe") == "shield", "the carpenter works the wood into a shield (%s)" % [_job_at("bench")])
	_at(600 + 6001)
	_check(_work.tier(STORE) == Production.WORK_UP, "a window later, one tick: still WORK UP")
	_at(600 + 6301)
	_check(_work.tier(STORE) != Production.WORK_UP, "the sale is out of the window: not WORK UP now (%s)" % _work.tier(STORE))
	_check(_work.signals_of(STORE, CATALOG)["safety"] == Production.UNEASY, "with goblins at the camp next door the town is uneasy")


func _test_away_and_restart() -> void:
	print("\n== a job advances only while its worker is there, and survives a restart ==")
	_fresh({"gold": 100, "ore": 3, "wood": 1, "cloth": 0, "food": 0})
	_at(0)
	var sword := _job_at("forge")
	_check(sword.get("recipe") == "sword" and sword["needed"] == 3000, "the smith starts a sword: 3000 steps")
	_now = 1000
	_work.set_away("bram", true)
	_check(_job_at("forge")["worked"] == 1000, "Bram goes away at step 1000, 1000 steps in")
	_at(2000)
	_check(_job_at("forge")["worked"] == 1000, "away: no work done by step 2000")
	_now = 2500
	_work.set_away("bram", false)
	_check(_job_at("forge")["worked"] == 1000, "back at 2500, between ticks: none counted for the time away")
	# The server stops here and starts again: book, store and work from their saves.
	var clock := func() -> int: return _now
	var saved_book: Variant = JSON.parse_string(JSON.stringify(_book.to_dict()))
	var saved_stock: Variant = JSON.parse_string(JSON.stringify(_stock.to_dict()))
	var saved_work: Variant = JSON.parse_string(JSON.stringify(_work.to_dict()))
	_book = ItemBook.from_dict(saved_book, clock)
	_stock = Stockpile.new(saved_stock, clock, _book)
	_work = Production.new(saved_work, _stock, _holdings, clock, RULES, func() -> Dictionary: return CATALOG)
	_check(_job_at("forge").get("worked") == 1000 and _work.worker("bram")["away"] == false, "after the restart the job is 1000 steps in")
	_at(4499)
	_check(_shop_ids().is_empty(), "at step 4499, not done")
	_at(4500)
	_check(_shop_ids() == _strings(["sword"]), "at step 4500 the sword is done: 3000 steps worked (%s)" % [_shop_ids()])


func _test_cancel_and_rework() -> void:
	print("\n== cancelled jobs give back; a rework keeps the thing ==")
	_fresh({"gold": 100, "ore": 10, "wood": 10, "cloth": 0, "food": 0})
	var id := _work.order("forge", "sword")
	_check(id > 0 and _work.job(id)["state"] == "queued", "an order for a sword waits for the next tick")
	_at(0)
	_check(_work.job(id)["state"] == "working" and _stock.count(STORE, "ore") == 7, "it starts ahead of anything else, taking 3 ore")
	var wood := _stock.count(STORE, "wood")
	_check(_work.cancel(id) and _stock.count(STORE, "ore") == 10 and _stock.count(STORE, "wood") == wood + 1 and _work.job(id).is_empty(),
		"cancelled: its 3 ore and 1 wood go back (%s)" % [_stock.resources(STORE)])
	var old := _book.mint("sword", "found", "the castle")
	_stock.bank(STORE, old, "Jeff", "the castle")
	var rework := _work.order("forge", "sword", old)
	_at(300)
	_check(_work.job(rework)["kind"] == "rework" and _work.job(rework)["needed"] == 1500 and old not in _stock.items(STORE)
		and _book.at_of(old) == "job:%d" % rework, "the smith takes the old sword to rework: 1500 steps, 1 ore (%s)" % [_work.job(rework)])
	_check(_stock.count(STORE, "ore") == 9, "one ore taken (%d)" % _stock.count(STORE, "ore"))
	_check(_work.all_items() == _ints([old]), "the job holds it meanwhile")
	_at(1800)
	_check(_stock.shop(STORE) == _ints([old]), "the same sword is in the shop (%s)" % [_stock.shop(STORE)])
	var events: Array = _book.history(old)["events"]
	_check(events[0]["kind"] == "found" and events.back()["kind"] == "reworked", "its history goes on: found, banked, reworked (%s)" % [events])


func _test_surplus_and_idle() -> void:
	print("\n== SURPLUS makes goods and reworks; IDLE does nothing ==")
	_fresh({"gold": 100, "ore": 20, "wood": 20, "cloth": 10, "food": 20})
	for item: String in ["sword", "sword", "shield", "bandage_roll", "bandage_roll", "meal", "meal"]:
		var uid := _book.mint(item, "made", "before")
		_stock.bank(STORE, uid, "test")
	_at(0)
	_check(_work.tier(STORE) == Production.SURPLUS, "everything at its want, every resource at comfort: SURPLUS (%s)" % _work.tier(STORE))
	_check(_job_at("kitchen").get("recipe") == "bandage_roll" and _job_at("forge").get("recipe") == "sword",
		"goods for the shop, by id: the cook's bandage roll, the smith's sword")
	_fresh({"gold": 10, "ore": 0, "wood": 0, "cloth": 0, "food": 0})
	for item: String in ["sword", "sword", "shield", "bandage_roll", "bandage_roll", "meal", "meal"]:
		_stock.bank(STORE, _book.mint(item, "made", "before"), "test")
	_at(0)
	_check(_work.tier(STORE) == Production.IDLE and _work.jobs().is_empty(), "wants met, nothing in store: IDLE, nobody works")
	var quiet := RULES.duplicate(true)
	quiet["busy"] = {"quiet_below": 100000, "busy_from": 200000}
	_fresh({"gold": 10, "ore": 2, "wood": 0, "cloth": 0, "food": 0}, quiet)
	for item: String in ["sword", "sword", "shield", "bandage_roll", "bandage_roll", "meal", "meal"]:
		_stock.bank(STORE, _book.mint(item, "made", "before"), "test")
	_at(0)
	_check(_job_at("forge").get("kind") == "rework", "a quiet town reworks even when IDLE (%s)" % [_job_at("forge")])


func _test_wages_and_rent() -> void:
	print("\n== wages, taxed, down to the floor; rent leaves the economy ==")
	_fresh({"gold": 31, "ore": 0, "wood": 0, "cloth": 2, "food": 0})
	_at(0)
	_at(1000)
	_check(_work.worker("cora")["purse"] == 9 and _stock.count(STORE, "gold") == 22, "a bandage roll: Cora is paid 9 (10 less 1 tax), the town 31 -> 22")
	_at(2000)
	_check(_work.worker("cora")["purse"] == 9 and _stock.count(STORE, "gold") == 22, "the next: 9 more would take the town below 20; unpaid")
	_at(6000)
	_check(_work.worker("cora")["purse"] == 6 and _work.upkeep(STORE) == 3 and _stock.count(STORE, "gold") == 25,
		"rent: Cora pays 3 at step 6000 into the treasury (22 -> 25), counted as upkeep")
	_check(_work.worker("bram")["purse"] == 0 and _work.upkeep(STORE) == 3, "Bram, with nothing, pays nothing and owes nothing")


func _test_world_tick() -> void:
	print("\n== the world tick runs the work ==")
	_fresh({"gold": 100, "ore": 3, "wood": 1, "cloth": 0, "food": 0})
	var steps_was := World.steps
	World.steps = 0
	_now = 0
	World.production = _work
	World.world_tick(0)
	_check(_job_at("forge").get("recipe") == "sword", "the world tick's first slice starts the sword")
	_now = 3000
	World.world_tick(1)
	_check(_shop_ids().is_empty(), "another slice leaves it be")
	World.world_tick(0)
	_check(_shop_ids() == _strings(["sword"]), "the first slice again finishes it")
	World.production = null
	World.steps = steps_was


func _strings(values: Array) -> Array[String]:
	var out: Array[String] = []
	out.assign(values)
	return out


func _ints(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
