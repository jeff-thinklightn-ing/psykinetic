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
	_test_sites()
	_test_fisherman()
	_test_made_needs()
	_test_mail_never_made()
	_test_workshop_makes()

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
		"woodlot": {"at": [30, 4], "kind": "woodlot", "radius": 2, "holder": "town", "town": "store"},
		"grounds": {"at": [30, 14], "kind": "hunting_ground", "radius": 2, "holder": "town", "town": "store"},
		"fishing": {"at": [36, 9], "kind": "fishing", "radius": 2, "holder": "town", "town": "store"},
		"fort": {"at": [20, 15], "kind": "fort", "radius": 2, "holder": "nobody", "town": "store"},
	}})


## A fresh town at step 0 with [param resources] banked: Bram the smith at
## the forge, Dag the carpenter at the bench, Cora the cook at the kitchen.
func _fresh(resources: Dictionary, rules := RULES, catalog := CATALOG) -> void:
	_now = 0
	var clock := func() -> int: return _now
	_holdings = Holdings.new(WorldMap.build(_strings([TOWN])), null, {}, clock)
	_book = ItemBook.new(clock)
	_stock = Stockpile.new({}, clock, _book)
	for what: String in resources:
		_stock.deposit(STORE, what, int(resources[what]), "test")
	_work = Production.new({}, _stock, _holdings, clock, rules, func() -> Dictionary: return catalog)
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


## The fisherman and the fort (594): a work-site trade at the town's
## fishing place on the bank, a newcomer at village; a counter in a fort
## that names the town is the town's shop.
func _test_fisherman() -> void:
	print("
== the fisherman, and Snagfin's fort ==")
	var file := Production.read_rules()
	var rules := RULES.duplicate(true)
	rules["sites"] = {"trades": {"fisherman": "fishing"}, "steps_per_cell": 4, "work_steps": 120, "other_area": 3000}
	rules["fisherman"] = file["fisherman"]
	rules["stages"] = file["stages"]
	_check(int(file["fisherman"]["catch"]) == 2 and file["fisherman"]["stage"] == "village" and "fish" in Stockpile.RESOURCES
		and int(file["value"]["fish"]) == 1 and "fish" in file["folk"]["needs"]["meal"]["store"], "the rules are economy.json's: 2 fish, at village, eaten as meat is")
	_fresh({}, rules)
	_check(Stockpile.place_at(_holdings, TOWN, Vector2i(20, 15)) == STORE and Stockpile.place_at(_holdings, TOWN, Vector2i(15, 5)) == "",
		"a counter in the fort that names the town is its shop; the camp's is nobody's")
	var config := {"places": {"store": {"at": [4, 4], "kind": "stockpile", "radius": 3, "holder": "town"},
		"fort": {"at": [20, 15], "kind": "fort", "radius": 2, "town": "store"}},
		"entities": [{"at": [4, 4], "props": {"depot": true}}, {"at": [20, 15], "props": {"shop": true}}]}
	_check(Stockpile.check(config).is_empty(), "builder's check: the fort's counter is no stray (%s)" % [Stockpile.check(config)])
	var towns := Towns.new({}, _work, rules, func() -> int: return _now)
	towns._town(STORE)
	towns.tick()
	_check(towns.stage(STORE) == "settlement", "a settlement")
	_now += 4 * DayNight.day_steps
	towns.tick()
	_check(not towns.residents(STORE).any(func(id: String) -> bool: return "fisherman" in _work.worker(id)["trades"]), "a settlement: no fisherman yet")
	towns._town(STORE)["stage"] = "village"
	towns.tick()
	_now += 4 * DayNight.day_steps
	towns.tick()
	var fishers := towns.residents(STORE).filter(func(id: String) -> bool: return "fisherman" in _work.worker(id)["trades"])
	_check(fishers.size() == 1, "a village with a fishing place: a fisherman comes (%s)" % [fishers])
	var until := _now + 7000
	while _now < until:
		_now += World.WORLD_TICK_STEPS
		towns.tick()
	_check(_stock.count(STORE, "fish") >= 2, "he walks to the bank and back with his catch: %d fish in the store" % _stock.count(STORE, "fish"))
	_holdings.take("pt_town/fishing", "goblins")
	var had := _stock.count(STORE, "fish")
	until = _now + 7000
	while _now < until:
		_now += World.WORLD_TICK_STEPS
		towns.tick()
	_check(_stock.count(STORE, "fish") == had, "goblins on the bank: no fish")


## Work sites (decision 521): a trade works from its town's site of its
## kind, the worker away for the walk there and back; a site the town
## doesn't hold yields nothing and makes it uneasy.
func _test_sites() -> void:
	print("
== work sites ==")
	var rules := RULES.duplicate(true)
	rules["sites"] = {"trades": {"woodcutter": "woodlot", "hunter": "hunting_ground"}, "steps_per_cell": 4, "work_steps": 120, "other_area": 3000}
	rules["hunter"] = {"trade": "hunter", "every": 100}
	_fresh({}, rules)
	_check(_holdings.place("pt_town/woodlot")["town"] == STORE and _holdings.place(CAMP)["town"] == "",
		"a place's town is its stockpile place's id (517), \"\" for none")
	_work.add_worker("wc", "Wynn", ["woodcutter"], STORE)
	_check(str(_work.site_of(STORE, "woodcutter").get("id", "")) == "pt_town/woodlot" and _work.site_of(STORE, "smith").is_empty(),
		"the woodcutter's site is the town's woodlot; the smith has none")
	var walk := _work.site_walk(STORE, _work.site_of(STORE, "woodcutter"))
	_check(walk == 2 * ceili(26.0 * 4) + 120, "the walk there and back and a spell at the site (521 amended): %d steps" % walk)
	_check(_work.site_turn(STORE, "wc", "woodcutter") == Production.WALKING and _work.outside("wc"), "due: off to the woodlot, outside the walls")
	var trip := _work.trip("wc")
	_check(str(trip.get("site", {}).get("id", "")) == "pt_town/woodlot" and int(trip.get("from", -1)) == 0 and int(trip.get("back_at", -1)) == walk,
		"the trip (decision 566): to the woodlot, from 0, back at %d (%s)" % [walk, trip])
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_work.to_dict()))
	_check(int(saved.get("trip_from", {}).get("wc", -1)) == 0, "its start saved")
	_now = walk - 1
	_check(_work.site_turn(STORE, "wc", "woodcutter") == Production.WALKING, "still on the way")
	_now = walk
	_check(_work.site_turn(STORE, "wc", "woodcutter") == Production.BACK and not _work.outside("wc") and _work.trip("wc").is_empty(),
		"back: the wood comes in, no trip")
	_check(_work._safety(STORE, 0) == Production.SAFE, "the town holds its sites: safe")
	_holdings.take("pt_town/woodlot", "goblins")
	_check(_work.site_turn(STORE, "wc", "woodcutter") == Production.BLOCKED and not _work.site_works(STORE, "woodcutter"),
		"goblins hold the woodlot: no wood")
	_check(_work._safety(STORE, 0) == Production.UNEASY, "and the town is uneasy")
	_holdings.take("pt_town/woodlot", "town")
	_check(_work.site_turn(STORE, "wc", "woodcutter") == Production.WALKING, "retaken: worked again at once")
	var at_site: Array = []
	_work.hunt_at = func(_town: String, site: Dictionary) -> String:
		at_site.append(site["id"])
		return ""
	_work.hunt = func(_town: String) -> String:
		at_site.append("store")
		return ""
	_work.add_worker("hn", "Hob", ["hunter"], STORE)
	for i in 12:
		_at(_now + 100)
	_check(not at_site.is_empty() and at_site.all(func(id: String) -> bool: return id == "pt_town/grounds"),
		"the hunter hunts at the town's hunting ground (%s)" % [at_site])
	# The catch is rolled as the trip sets out and kept on it (566 amended,
	# npc's game carried home); its drops land BACK, never rolled again.
	for i in 50:
		if _work.trip("hn").is_empty():
			break
		_at(_now + 100)
	var rolls := [0]
	_work.hunt_at = func(_town: String, _site: Dictionary) -> String:
		rolls[0] += 1
		return "rabbit"
	var hunted: Array = []
	_work.hunted.connect(func(_town: String, _id: String, kind: String) -> void: hunted.append(kind))
	for i in 50:
		if not _work.trip("hn").is_empty():
			break
		_at(_now + 100)
	_check(rolls[0] == 1 and _work.trip("hn").get("catch") == "rabbit" and hunted.is_empty(),
		"the trip sets out with its catch rolled: rabbit (%s)" % [_work.trip("hn")])
	_check(Production.new(_work.to_dict(), _stock, null, func() -> int: return _now, _work.rules).trip("hn").get("catch") == "rabbit", "kept in the save")
	for i in 50:
		if _work.trip("hn").is_empty():
			break
		_at(_now + 100)
	_check(rolls[0] == 1 and hunted == ["rabbit"], "home: the rabbit's drops land, nothing rolled again (%d rolls, %s)" % [rolls[0], hunted])
	_check(_work.trip("wc").get("catch", "") == "", "another trade's trip carries no catch")



## A recipe's made.needs (622, economy's side): plate at the smith only once
## the town stands a forge and is a village (Towns.has_for_make through
## Production.town_has); before, the smith never starts it.
func _test_made_needs() -> void:
	print("
== plate: a village's forge first ==")
	var catalog := CATALOG.duplicate(true)
	catalog["plate"] = {"id": "plate", "tags": ["weapon"], "made": {"by": "smith", "from": {"ore": 8}, "steps": 600, "needs": {"kind": "forge", "stage": "village"}}}
	var rules := RULES.duplicate(true)
	rules["stages"] = Production.read_rules()["stages"]
	_fresh({"gold": 100, "ore": 40}, rules, catalog)
	_check(_job_at("forge").is_empty(), "no town to ask yet")
	_at(0)
	_check(_job_at("forge").is_empty(), "with no town_has, the smith never starts plate (%s)" % [_job_at("forge")])
	var towns := Towns.new({}, _work, rules, func() -> int: return _now)
	towns._town(STORE)["stage"] = "hamlet"
	towns._town(STORE)["buildings"]["forge"] = {"kind": "forge", "level": 1, "state": Towns.STANDING, "since": 0, "job": 0}
	_at(300)
	_at(600)
	_check(_job_at("forge").is_empty() and not towns.has_for_make(STORE, {"kind": "forge", "stage": "village"}),
		"a hamlet with a forge: no plate (%s)" % [_job_at("forge")])
	towns._town(STORE)["stage"] = "village"
	_at(900)
	_check(towns.has_for_make(STORE, {"kind": "forge", "stage": "village"}) and _job_at("forge").get("recipe") == "plate",
		"a village with its forge: the smith starts plate (%s)" % [_job_at("forge")])
	towns._town(STORE)["buildings"].erase("forge")
	_check(not towns.has_for_make(STORE, {"kind": "forge", "stage": "village"}), "a village without a forge has not what plate needs")
	_check(Items.made_problem({"by": "smith", "from": {"ore": 8}, "steps": 600, "needs": {"kind": "forge", "stage": "village"}}, {}) == ""
		and Items.made_problem({"by": "smith", "from": {"ore": 8}, "steps": 600, "needs": {"kind": "forge", "stage": "hamlet town"}}, {}) != ""
		and Items.made_problem({"by": "smith", "from": {"ore": 8}, "steps": 600, "needs": {"kind": "no_such", "stage": "village"}}, {}) != "",
		"Items checks a needs' kind and stage")


## Mail is never made (622, economy's side; "nothing appearing in stock
## from nowhere"): no recipe in the real catalog makes it and no market
## sells it, so over days of work with every resource to hand, no shop
## shows a mail shirt; plate, its town no village with a forge, neither.
func _test_mail_never_made() -> void:
	print("
== mail never made, plate not before its forge ==")
	var catalog := Production.items_catalog()
	var file := Production.read_rules()
	_check(not catalog.has("mail_armour") and catalog.get("plate_armour", {}).get("made", {}).get("needs", {}) == {"kind": "forge", "stage": "village"},
		"the real catalog: no recipe for mail; plate's needs a village's forge")
	var markets: Dictionary = file.get("trade", {}).get("markets", {})
	_check(not markets.is_empty() and not markets.values().any(func(market: Dictionary) -> bool: return "mail_armour" in market.get("sells", []) or "plate_armour" in market.get("sells", [])),
		"no market sells mail or plate")
	_fresh({"gold": 500, "ore": 200, "wood": 200, "cloth": 100, "food": 100, "leather": 50}, RULES, catalog)
	var seen := {}
	for day in 20:
		for tick in 10:
			_at(_now + 600)
		for id in _shop_ids():
			seen[id] = true
		_stock.deposit(STORE, "ore", 40, "test")
	_check(not seen.has("mail_armour") and not seen.has("plate_armour"), "twenty days' work: no mail, no plate in the shop (%s)" % [seen.keys()])


## A workshop's own list (641: each healer's hut its own potions): with
## workshop_makes naming only the meal, the cook never starts a bandage
## roll, though the town wants bandages first.
func _test_workshop_makes() -> void:
	print("
== a workshop makes its own list ==")
	_fresh({"gold": 100, "cloth": 10, "food": 10})
	_work.workshop_makes = func(workshop_id: String) -> Array: return ["meal"] if workshop_id == "kitchen" else []
	_at(0)
	_check(_job_at("kitchen").get("recipe") == "meal" and not _work.makes("kitchen", "bandage_roll") and _work.makes("forge", "sword"),
		"the kitchen makes the meal alone (%s)" % [_job_at("kitchen")])
