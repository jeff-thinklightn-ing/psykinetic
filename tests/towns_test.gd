extends Node
## How a town grows (Towns) on a clock of its own, with Production and a
## stockpile beneath it and a test catalog and rules: experience from a
## story objective (once) and from rescues; a rescued carpenter works at
## once, a rescued smith waits for a forge; the town chooses the forge by
## itself, spends its experience, and the carpenter builds it with wood and
## ore over time; the smith then works there, faster once it is raised a
## level; a companion left in town works its trade and its work waits while
## it is away; a crowded town wants an inn; a damaged forge stops the work;
## a restart keeps it all; World's world tick runs it.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const TOWN := "tt/store"

const CATALOG := {
	"sword": {"id": "sword", "tags": ["weapon"], "made": {"by": "smith", "from": {"ore": 3, "wood": 1}, "steps": 3000}},
	"meal": {"id": "meal", "tags": ["food"], "made": {"by": "cook", "from": {"food": 2}, "steps": 600}},
}
const RULES := {
	"window": 6000, "tier_hold": 2, "starve_after": 3,
	"comfort": {"gold": 50, "ore": 5, "wood": 5, "cloth": 2, "food": 4},
	"wants": {"weapon": 2, "food": 2},
	"shop_cap": 3,
	"tiers": {"defend": ["weapon", "food"], "stock": ["food", "weapon"], "surplus": ["goods", "rework"]},
	"work_up": {}, "defend_trades": ["smith", "carpenter", "cook"],
	"busy": {"quiet_below": 0, "busy_from": 100000},
	"wage": 0, "rent": 0, "rent_every": 6000, "gold_floor": 0, "level_speed": 0.25,
	"xp": {"rescue": 10, "objective": 50},
	"residents": {"base": 3, "per_inn": 3},
	"buildings": {
		"forge": {"trade": "smith", "built_by": "carpenter", "xp": 20, "cost": {"wood": 10, "ore": 5}, "steps": 6000, "max_level": 2},
		"kitchen": {"trade": "cook", "built_by": "carpenter", "xp": 10, "cost": {"wood": 6}, "steps": 3000, "max_level": 3},
		"inn": {"built_by": "carpenter", "xp": 30, "cost": {"wood": 15, "cloth": 5}, "steps": 9000, "max_level": 3},
	},
}

var _failures := 0
var _now := 0
var _book: ItemBook
var _stock: Stockpile
var _work: Production
var _towns: Towns


func _ready() -> void:
	World.set_process(false)
	_fresh()
	_test_experience()
	_test_rescues_and_the_forge()
	_test_companion_and_inn()
	_test_damage_and_restart()
	_test_world_tick()
	_test_stalled_build()
	_test_unmeetable_build()
	_test_stands_states()
	_test_boot_line()
	_test_day_line()
	_test_newcomer_want()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _fresh() -> void:
	_now = 0
	var clock := func() -> int: return _now
	_book = ItemBook.new(clock)
	_stock = Stockpile.new({}, clock, _book)
	for what: String in {"gold": 100, "ore": 30, "wood": 60, "cloth": 10, "food": 10}:
		_stock.deposit(TOWN, what, {"gold": 100, "ore": 30, "wood": 60, "cloth": 10, "food": 10}[what], "test")
	_work = Production.new({}, _stock, null, clock, RULES, func() -> Dictionary: return CATALOG)
	_towns = Towns.new({}, _work, RULES, clock)


func _at(step: int) -> void:
	_now = step
	_towns.tick()
	_work.tick()


func _test_experience() -> void:
	print("\n== experience: a story objective once, nothing ever taken ==")
	_check(_towns.note_objective(TOWN, "smith_home", 2) == 100, "the smith brought home, worth 2: 100 experience")
	_check(_towns.note_objective(TOWN, "smith_home", 2) == 100, "the same objective again: nothing more")
	_check(_towns.add_xp(TOWN, 5, "a test") == 105 and _towns.add_xp(TOWN, -50, "a loss") == 105, "add_xp adds; nothing takes it away")


func _test_rescues_and_the_forge() -> void:
	print("\n== rescued people; the town chooses and builds a forge ==")
	_check(_towns.note_rescue(TOWN, "dag", "Dag", "carpenter"), "Dag the carpenter, rescued, reaches the town")
	_check(_work.worker("dag").get("origin") == "rescued:dag" and _work.workshop_of("dag") == "%s:carpenter" % TOWN,
		"a resident, working at once: no building houses a carpenter (%s)" % _work.workshop_of("dag"))
	_check(not _towns.note_rescue(TOWN, "dag", "Dag", "carpenter"), "rescued twice: once a resident")
	_check(not _towns.has_resident(TOWN, "smith") and _towns.resident_trades(TOWN).has("carpenter") and not _towns.resident_trades(TOWN).has("smith"),
		"297 amended: no smith yet; the carpenter a resident (%s)" % [_towns.resident_trades(TOWN)])
	_towns._seek(TOWN, "wyn", "Wyn", "weaver")
	_check(_towns._has_trade(TOWN, "weaver") and not _towns.has_resident(TOWN, "weaver") and not _towns.resident_trades(TOWN).has("weaver"),
		"a weaver sought: the town waits for one, but has none living there")
	_towns.note_rescue(TOWN, "bram", "Bram", "smith")
	_check(_towns.has_resident(TOWN, "smith") and _towns.resident_trades(TOWN).has("smith"), "Bram rescued: a smith lives there, waiting for his forge or not")
	_check(_work.workshop_of("bram") == "" and _towns.log_of(TOWN).any(func(line: Dictionary) -> bool:
		return line["what"] == "Bram the smith waits for a forge"), "Bram the smith waits for a forge")
	_check(_towns.xp(TOWN) == 125, "20 experience for the two rescues (%d)" % _towns.xp(TOWN))
	_check(_towns.choose(TOWN) == "forge", "the town wants a forge for its waiting smith (%s)" % _towns.choose(TOWN))
	_at(0)
	var forge := _towns.building(TOWN, "forge")
	_check(forge.get("state") == Towns.PLANNED and _towns.xp(TOWN) == 105 and _work.building_in(TOWN),
		"it spends 20 experience: a forge planned, a build job ordered (%s)" % [forge])
	var job := _work.job(int(forge["job"]))
	_check(job.get("state") == "working" and job.get("worker") == "dag" and _stock.count(TOWN, "wood") == 50
		and _stock.count(TOWN, "ore") == 25, "Dag starts on it at once, taking 10 wood and 5 ore (%s)" % [job])
	_check(not _towns.allows({"trade": "smith", "town": TOWN}), "no forge stands yet: a smith's workshop may not work")
	# Seen being built (decision 566): progress, the walls stage, told again at each stage.
	var told: Array[String] = []
	var on_told := func(_town: String, kind: String) -> void: told.append(kind)
	_towns.building_changed.connect(on_told)
	_check(is_equal_approx(float(_towns.buildings_of(TOWN)["forge"].get("progress", -1.0)), 0.0) and not _towns.walls_up(TOWN, "forge"),
		"planned and begun: progress 0, no walls yet (%s)" % [_towns.buildings_of(TOWN)["forge"]])
	_at(1800)
	_towns._stages(TOWN)  # (The tick reads the stage before the work moves on: here after.)
	var at_frame := told.size()
	_check(is_equal_approx(_towns.build_progress(TOWN, "forge"), 0.3) and not _towns.walls_up(TOWN, "forge") and at_frame >= 1 and told.has("forge"),
		"at 1800: 0.3 built, past the frame (0.1) so the views are told, no walls (%.2f, %s)" % [_towns.build_progress(TOWN, "forge"), told])
	_at(2400)
	_towns._stages(TOWN)
	_check(_towns.walls_up(TOWN, "forge") and _towns.buildings_of(TOWN)["forge"]["walls"] == true and told.size() == at_frame + 1,
		"at 2400: 0.4, past the walls stage: walls up, told again")
	_at(2650)
	_towns._stages(TOWN)
	_check(told.size() == at_frame + 1, "nothing more to tell at 0.44")
	var before_awake := told.size()
	_towns.set_awake(TOWN, "H3", true)
	_towns.set_awake(TOWN, "H3", true)
	_towns.set_awake(TOWN, "H4", false)
	_check(_towns.awake_of(TOWN) == {"H3": true, "H4": false} and told.size() == before_awake + 2, "awake by map building, told on each change only (%s)" % [_towns.awake_of(TOWN)])
	_towns.building_changed.disconnect(on_told)
	_at(5700)
	_check(_towns.building(TOWN, "forge")["state"] == Towns.PLANNED, "at 5700, still being built")
	_at(6000)
	_check(_towns.building(TOWN, "forge").get("state") == Towns.STANDING and _towns.building(TOWN, "forge")["level"] == 1,
		"at 6000 the forge stands, level 1")
	_check(not _towns.buildings_of(TOWN)["forge"].has("progress") and _towns.walls_up(TOWN, "forge"), "standing: no progress, walls up")
	_check(_work.workshop_of("bram") == "%s:forge" % TOWN, "Bram works at it (%s)" % _work.workshop_of("bram"))
	var forge_shop := "%s:forge" % TOWN
	var sword := _work.job(int(_work.workshop(forge_shop)["job"]))
	_check(sword.get("recipe") == "sword" and sword["needed"] == 3000, "he starts a sword: 3000 steps (%s)" % [sword])
	_at(6300)
	_check(_towns.building(TOWN, "forge").get("state") == Towns.BUILDING and _towns.xp(TOWN) == 65,
		"with 105 experience left, the town raises its forge a level next: 40 spent (%s, %d)" % [_towns.building(TOWN, "forge"), _towns.xp(TOWN)])
	_check(_towns.allows({"trade": "smith", "town": TOWN}) and _work.job(int(sword["id"])).get("worked") == 300,
		"the smith works on while it is raised")
	_at(9000)
	_at(12000)
	_at(18000)
	_check(_towns.building(TOWN, "forge").get("level") == 1, "at 18000, still level 1")
	_at(18300)
	_check(_towns.building(TOWN, "forge").get("level") == 2, "at 18300 it is level 2 (%s)" % [_towns.building(TOWN, "forge")])
	var id := _work.order(forge_shop, "sword")
	_at(18600)
	_check(_work.job(id).get("needed") == 2400, "a sword at a level 2 forge: 2400 steps, a quarter faster (%s)" % [_work.job(id)])


func _test_companion_and_inn() -> void:
	print("\n== a companion left in town works; a crowded town wants an inn ==")
	_towns.note_companion_in(TOWN, "Wren", "cook")
	_check("companion:Wren" in _towns.residents(TOWN) and _work.worker("companion:Wren").get("origin") == "companion:Wren",
		"Wren stays in town: a resident cook")
	_check(_towns.residents(TOWN).size() == 3 and _towns.room(TOWN) == 3, "three residents, room for three")
	var wants := _towns.choose(TOWN)
	_check(wants == "kitchen", "the town wants a kitchen for its cook first (%s)" % wants)
	_towns.unlock(TOWN, "kitchen")
	_at(18600)
	_at(21600)
	_check(_work.workshop_of("companion:Wren") == "%s:kitchen" % TOWN, "the kitchen stands: Wren cooks there")
	_at(21900)
	var meal := _work.job(int(_work.workshop("%s:kitchen" % TOWN)["job"]))
	_check(meal.get("recipe") == "meal", "a meal on (%s)" % [meal])
	_now = 22000
	_towns.note_companion_out(TOWN, "Wren")
	_at(23000)
	_check(_work.job(int(meal["id"])).get("worked") == 400, "Wren goes adventuring at 22000: her meal (from 21600) waits, 400 steps in")
	_now = 24000
	_towns.note_companion_in(TOWN, "Wren", "cook")
	_at(24500)
	_check(_work.job(int(meal["id"])).is_empty() and _stock.shop(TOWN).any(func(uid: int) -> bool: return _book.id_of(uid) == "meal"),
		"back at 24000, she finishes it by 24500")
	_towns.add_xp(TOWN, 100, "a test")
	_check(int(_towns.building(TOWN, "inn").get("job", 0)) != 0 and _towns.choose(TOWN) != "inn",
		"with no one waiting and the town full, an inn: ordered, and not chosen again while it is built (%s)" % [_towns.building(TOWN, "inn")])


func _test_damage_and_restart() -> void:
	print("\n== a damaged forge stops the work; a restart keeps it all ==")
	var forge_shop := "%s:forge" % TOWN
	_towns._towns[TOWN]["buildings"]["forge"]["state"] = Towns.DAMAGED
	var id := int(_work.workshop(forge_shop)["job"])
	var before := int(_work.job(id).get("worked", 0))
	_at(_now + 1000)
	_check(id == 0 or _work.job(id).get("worked") == before, "the forge damaged: no work on Bram's sword")
	_towns._towns[TOWN]["buildings"]["forge"]["state"] = Towns.STANDING
	var clock := func() -> int: return _now
	var saved: Array = [_book.to_dict(), _stock.to_dict(), _work.to_dict(), _towns.to_dict()]
	saved = JSON.parse_string(JSON.stringify(saved))
	var xp := _towns.xp(TOWN)
	var residents := _towns.residents(TOWN)
	_book = ItemBook.from_dict(saved[0], clock)
	_stock = Stockpile.new(saved[1], clock, _book)
	_work = Production.new(saved[2], _stock, null, clock, RULES, func() -> Dictionary: return CATALOG)
	_towns = Towns.new(saved[3], _work, RULES, clock)
	_check(_towns.xp(TOWN) == xp and _towns.residents(TOWN) == residents and _towns.building(TOWN, "forge")["level"] == 2,
		"after a restart: the same experience, residents and level 2 forge")
	_check(_work.workshop_of("bram") == forge_shop and _towns.allows({"trade": "smith", "town": TOWN}), "Bram still at his forge")
	_check(_towns.note_objective(TOWN, "smith_home") == xp, "an objective done before the restart is still done")


func _test_world_tick() -> void:
	print("\n== the world tick runs it ==")
	_fresh()
	_towns.add_xp(TOWN, 20, "a test")
	_towns.note_rescue(TOWN, "dag", "Dag", "carpenter")
	_towns.note_rescue(TOWN, "bram", "Bram", "smith")
	World.production = _work
	World.towns = _towns
	World.world_tick(0)
	_check(_towns.building(TOWN, "forge").get("state") == Towns.PLANNED, "the first slice: the town chooses its forge")
	World.production = null
	World.towns = null


## The boot line (the coordinator's ask, 11-12): counts and trades only, never a
## name or an id; room used of room().
func _test_boot_line() -> void:
	print("
== the town's boot line ==")
	_fresh()
	_towns.note_rescue(TOWN, "dag", "Dag", "carpenter")
	_towns.note_rescue(TOWN, "bram", "Bram", "smith")
	_towns.note_rescue(TOWN, "brom", "Brom", "smith")
	var line := _towns.boot_line(TOWN)
	var stage := _towns.stage(TOWN) if not _towns.stage(TOWN).is_empty() else "none"
	_check(line.begins_with("town %s: %s; residents 3 (carpenter 1, smith 2); visitors 0; room 3 of 3; buildings " % [TOWN, stage]), "residents by trade, room used of room (%s)" % line)
	# 613 amended (5): its buildings by kind, state and level, the kinds gone to the wild, and its sought by trade.
	var record: Dictionary = _towns._town(TOWN)
	var kept_houses: Dictionary = record["buildings"].duplicate(true)
	record["buildings"] = {"field": {"kind": "field", "level": 0, "state": Towns.RUIN, "since": 0, "job": 0},
		"inn": {"kind": "inn", "level": 1, "state": Towns.STANDING, "since": 0, "job": 0}}
	record["gone"] = ["pasture"]
	record["sought"] = {"s1": {"id": "s1", "name": "Edda", "trade": "farmer"}}
	var tail := "; buildings " + _towns.boot_line(TOWN).get_slice("; buildings ", 1)  # The inn standing adds room: cut at the new parts.
	# A field at level 0 (this ruin) is the town's first: no experience asked (613 amended (8)).
	_check(tail == "; buildings field ruin 0, inn standing 1; gone pasture; sought 1 (farmer 1); can build field yes (xp %d of 0)" % _towns.xp(TOWN),
		"buildings, gone, sought and the field's price told (%s)" % tail)
	_check(not "Edda" in _towns.boot_line(TOWN), "no sought name in it")
	record["buildings"] = kept_houses
	record.erase("gone")
	record.erase("sought")
	_check("; gone none; sought 0; can build " in _towns.boot_line(TOWN), "none gone, none sought (%s)" % _towns.boot_line(TOWN))
	line = _towns.boot_line(TOWN)
	_check(not ["Dag", "dag", "Bram", "bram", "Brom", "brom"].any(func(word: String) -> bool: return word in line), "no name or id in it")
	_check(_towns.boot_lines() == [line], "one line per town (%s)" % [_towns.boot_lines()])
	_check(_towns.move_in(TOWN, "cass", "Cass", "carpenter", "settled"), "a settled one past the room cap")
	_check(_towns._told.get(TOWN) == 3, "boot_lines keeps the count it told (%s)" % [_towns._told])
	_at(0)
	_check(not _towns._told.has(TOWN), "a changed count is told again at the next tick, once (%s)" % [_towns._told])

## The day line (the coordinator's ask, 11-12): food, fed by the town, hungry, sick, and the
## day's dead only when someone died; counts only.
func _test_day_line() -> void:
	print("
== the town's day line ==")
	_fresh()
	_towns.note_rescue(TOWN, "dag", "Dag", "carpenter")
	_towns.note_rescue(TOWN, "bram", "Bram", "smith")
	_towns.note_rescue(TOWN, "brom", "Brom", "smith")
	_work._workers["dag"]["fed"] = "hungry"
	_work._workers["bram"]["fed"] = "dole"
	var line := _towns.day_line(TOWN, 4)
	_check(line == "day 4 town %s: food 10; fed by the town 1, hungry 1; sick 0" % TOWN, "food, fed, hungry, sick (%s)" % line)
	_check(_towns.died(TOWN, "brom", "a fever"), "Brom dies")
	line = _towns.day_line(TOWN, 4)
	_check(line.ends_with("; dead 1") and not ["Dag", "dag", "Bram", "bram", "Brom", "brom"].any(func(word: String) -> bool: return word in line),
		"a death that day counted, no name or id (%s)" % line)
	_towns._day_told = 3
	_towns._tell_day()
	_check(_towns._dead_today.is_empty() and _towns._day_told == Townsfolk.day_of(_now), "told once the day turns, the dead count cleared")

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


## A build stalled on its materials (decision 522): after build_wait.days
## the town orders the next one it can build, the stalled one kept at the
## head and built first once its materials come.
func _test_stalled_build() -> void:
	print("
== a stalled build ==")
	var rules := RULES.duplicate(true)
	rules["build_wait"] = {"days": 2, "behind_days": 7}
	_now = 0
	var clock := func() -> int: return _now
	_book = ItemBook.new(clock)
	_stock = Stockpile.new({}, clock, _book)
	_stock.deposit(TOWN, "wood", 40, "test")
	_work = Production.new({}, _stock, null, clock, rules, func() -> Dictionary: return CATALOG)
	_towns = Towns.new({}, _work, rules, clock)
	_towns.note_rescue(TOWN, "dag", "Dag", "carpenter")
	_towns.note_rescue(TOWN, "cora", "Cora", "cook")
	_towns.add_xp(TOWN, 200, "a test")
	_towns.unlock(TOWN, "inn")
	var inn := int(_towns.building(TOWN, "inn")["job"])
	_at(300)
	_check(_work.job(inn).get("state") == "queued" and _towns.building(TOWN, "kitchen").is_empty(), "the inn waits on cloth; nothing else ordered yet")
	var day := DayNight.day_steps
	_at(2 * day - 300)
	_check(_towns.building(TOWN, "kitchen").is_empty(), "not before build_wait.days")
	_at(2 * day + 300)
	var kitchen := int(_towns.building(TOWN, "kitchen").get("job", 0))
	_check(kitchen != 0 and _work.job(inn).get("state") == "queued", "two days stalled: the kitchen ordered too, the inn still queued")
	_at(2 * day + 600)
	_check(_work.job(kitchen).get("state") == "working", "the carpenter builds the kitchen meanwhile (%s)" % [_work.job(kitchen)])
	_check(int(_towns.shortfall(TOWN).get("job", 0)) == inn, "the inn stays at the head (what players give goes to it)")
	_at(2 * day + 3600)
	_stock.deposit(TOWN, "cloth", 5, "test")
	_at(2 * day + 3900)
	_check(_work.job(inn).get("state") == "working", "its cloth in: the inn is built next (%s)" % [_work.job(inn)])


## What a newcomer is told the town wants (931, economy's side): only economy.json newcomer_wants' rows,
## the shortest under its comfort, the asker the first of its trades by id who is here and well.
func _test_newcomer_want() -> void:
	print("
== a newcomer's want: something to eat, firewood or a sought one, never a build's materials; the asker here and well (931, economy's side) ==")
	var rules: Dictionary = RULES.duplicate(true)
	rules["newcomer_wants"] = [{"good": "food", "words": "food", "counts": ["food", "meat", "fish"], "enough": "food", "trades": ["cook"]},
		{"good": "wood", "words": "firewood", "counts": ["wood"], "enough": "wood", "trades": ["carpenter", "woodcutter"]},
		{"good": "sought", "words": "someone brought home", "short": 0.5, "trades": []}]
	rules["newcomer_wants_least"] = 0.25
	_now = 0
	var clock := func() -> int: return _now
	_book = ItemBook.new(clock)
	_stock = Stockpile.new({}, clock, _book)
	for what: String in {"gold": 100, "ore": 30, "wood": 60, "food": 10}:
		_stock.deposit(TOWN, what, {"gold": 100, "ore": 30, "wood": 60, "food": 10}[what], "test")
	_work = Production.new({}, _stock, null, clock, rules, func() -> Dictionary: return CATALOG)
	_towns = Towns.new({}, _work, rules, clock)
	_check(_towns.newcomer_want(TOWN).is_empty(), "food 10 and wood 60 over their comfort (4, 5): nothing asked")
	_stock.take(TOWN, "ore", 30, "test")
	_check(_towns.newcomer_want(TOWN).is_empty(), "no ore at all: still nothing (a build's or a trade's stock is never asked)")
	_stock.take(TOWN, "food", 9, "test")
	var want := _towns.newcomer_want(TOWN)
	_check(want.get("good") == "food" and want.get("words") == "food" and is_equal_approx(float(want.get("short", 0)), 0.75)
		and want.get("worker") == "" and want.get("person") == "", "1 food of 4: food, nobody to ask yet (%s)" % [want])
	_towns.note_rescue(TOWN, "cob", "Cob", "cook")
	_towns.note_rescue(TOWN, "cara", "Cara", "cook")
	want = _towns.newcomer_want(TOWN)
	_check(want.get("worker") == "cara" and want.get("person") == "Cara" and want.get("trade") == "cook", "two cooks: the first by id asks (%s)" % [want])
	_check(_towns.newcomer_want(TOWN) == want, "the same state: the same answer")
	_work.set_away("cara", true)
	_check(_towns.newcomer_want(TOWN).get("worker") == "cob", "Cara away: Cob asks")
	Townsfolk._set_sickness(_work, "cob", {"kind": "the shakes", "since": 0, "day": 0})
	want = _towns.newcomer_want(TOWN)
	_check(want.get("good") == "food" and want.get("worker") == "", "Cob abed too: the want still, nobody named (%s)" % [want])
	_stock.deposit(TOWN, "fish", 2, "test")
	_stock.deposit(TOWN, "meat", 1, "test")
	_check(_towns.newcomer_want(TOWN).is_empty(), "fish and meat count as food: 4 of 4, nothing asked")
	_stock.take(TOWN, "wood", 59, "test")
	want = _towns.newcomer_want(TOWN)
	_check(want.get("good") == "wood" and want.get("words") == "firewood" and want.get("worker") == "", "1 wood of 5: firewood, no carpenter here (%s)" % [want])
	_stock.deposit(TOWN, "wood", 59, "test")
	_towns._seek(TOWN, "wyn", "Wyn", "weaver")
	want = _towns.newcomer_want(TOWN)
	_check(want.get("good") == "sought" and want.get("worker") == "", "a weaver sought, the stores full: someone brought home (%s)" % [want])
	_towns._town(TOWN)["sought"]["wyn"]["freed_by"] = "p1"
	_check(_towns.newcomer_want(TOWN).is_empty(), "led home by a player already: nothing asked")
	_fresh()


## 522 amended (3), the box's shape (Umbrage from 10-25): three repairs queued, all short
## (two want ore that never comes), a woodcutter waiting unseated for a woodshed that costs
## nothing. build_wait.most (3) froze it: three builds in hand never counted as stalled, so
## nothing more was ever ordered. Now the stall is counted however many builds there are,
## and a build short at the head for build_wait.behind_days goes behind the rest, never
## dropped; what a player gave stays in the store for whichever build next takes it.
func _test_unmeetable_build() -> void:
	print("
== a build that can't be met: the town builds what it can, the head goes behind (522 amended (3)) ==")
	var rules := RULES.duplicate(true)
	rules["build_wait"] = {"days": 2, "behind_days": 7}
	rules["raids"] = {"repair": {"share": 0.5}}
	rules["buildings"]["temple"] = {"built_by": "carpenter", "xp": 20, "cost": {"wood": 10, "ore": 10}, "steps": 6000, "max_level": 2}
	rules["buildings"]["woodshed"] = {"trade": "woodcutter", "built_by": "carpenter", "xp": 10, "cost": {}, "steps": 1500, "max_level": 2}
	_now = 0
	var clock := func() -> int: return _now
	_book = ItemBook.new(clock)
	_stock = Stockpile.new({}, clock, _book)
	_stock.deposit(TOWN, "wood", 2, "test")  # Short of every repair, as the box was before the wood came.
	_work = Production.new({}, _stock, null, clock, rules, func() -> Dictionary: return CATALOG)
	_towns = Towns.new({}, _work, rules, clock)
	_towns.note_rescue(TOWN, "dag", "Dag", "carpenter")
	_towns.note_rescue(TOWN, "wil", "Wil", "woodcutter")
	for kind: String in ["forge", "kitchen", "temple"]:
		_towns._towns[TOWN]["buildings"][kind] = {"kind": kind, "level": 1, "state": Towns.DAMAGED, "since": 0, "job": 0}
	for i in 3:
		_towns._repair(TOWN)
	var forge := int(_towns.building(TOWN, "forge")["job"])
	var kitchen := int(_towns.building(TOWN, "kitchen")["job"])
	var temple := int(_towns.building(TOWN, "temple")["job"])
	_check(forge != 0 and kitchen != 0 and temple != 0 and _towns.xp(TOWN) >= _towns.xp_price(TOWN, "woodshed"),
		"three repairs queued (forge %s, kitchen %s, temple %s), xp %d for the woodshed" % [_work.job(forge).get("cost"), _work.job(kitchen).get("cost"), _work.job(temple).get("cost"), _towns.xp(TOWN)])
	var day := DayNight.day_steps
	_run_to(2 * day - 600)
	_check(_towns.building(TOWN, "woodshed").is_empty(), "not before build_wait.days")
	_run_to(2 * day + 600)
	var shed := int(_towns.building(TOWN, "woodshed").get("job", 0))
	_check(shed != 0, "three builds in hand, every one short for two days: stalled all the same, the woodshed ordered (was frozen under build_wait.most)")
	_run_to(2 * day + 3600)
	_check(int(_towns.building(TOWN, "woodshed").get("level", 0)) == 1, "it costs nothing, so the carpenter builds it: the woodcutter can be seated (%s)" % [_towns.building(TOWN, "woodshed")])
	_check(int(_towns.shortfall(TOWN).get("job", 0)) == forge, "the head is the first ordered, the forge's repair")
	_run_to(7 * day + 600)
	var order := _work.build_order().filter(func(id: int) -> bool: return id in [forge, kitchen, temple])
	_check(int(_towns.shortfall(TOWN).get("job", 0)) == kitchen and order == [kitchen, temple, forge],
		"seven days short at the head: the forge's repair goes behind, the kitchen's heads (%s)" % [order])
	_check(_work.job(forge).get("state") == "queued", "never dropped: the forge's repair still queued")
	_stock.deposit(TOWN, "wood", 3, "test")
	_run_to(7 * day + 3600)
	_check(_towns.building(TOWN, "kitchen").get("state", "") == Towns.STANDING, "its wood in: the kitchen is repaired (%s)" % [_towns.building(TOWN, "kitchen")])
	_check(int(_towns.shortfall(TOWN).get("job", 0)) == temple, "the temple's repair heads next: what players are asked for is the temple's")
	_stock.deposit(TOWN, "ore", 3, "a player, toward the temple")  # Banked while the temple heads.
	_run_to(14 * day + 3600)
	_check(int(_towns.shortfall(TOWN).get("job", 0)) == forge and _work.job(temple).get("state") == "queued",
		"seven days on the temple is still short: it goes behind, the forge's repair heads again")
	_check(_stock.count(TOWN, "ore") == 3, "the ore given toward the temple is still in the store: nothing lost")
	_stock.deposit(TOWN, "wood", 5, "test")
	_run_to(14 * day + 4800)
	_check(_work.job(forge).get("state") == "working" and _stock.count(TOWN, "ore") == 0,
		"the forge heads when the builder starts: it takes the ore given while the temple headed (%s)" % [_work.job(forge)])
	_run_to(15 * day)
	var lone := _towns.shortfall(TOWN)
	_check(int(lone.get("job", 0)) == temple and _work.build_order().filter(func(id: int) -> bool: return _work.job(id).get("state") == "queued" and _work.job(id).get("kind") == "build").size() == 1,
		"the forge repaired; the temple's repair alone in the queue (%s)" % [lone])
	var went_behind: Variant = _work.job(temple).get("behind")
	_run_to(23 * day)
	_check(int(_towns.shortfall(TOWN).get("job", 0)) == temple and _work.job(temple).get("behind") == went_behind and _work.job(temple).get("state") == "queued",
		"a lone queued build keeps the head, past behind_days, never dropped")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_work.to_dict()))
	_stock.deposit(TOWN, "ore", 7, "test")
	_stock.deposit(TOWN, "wood", 5, "test")
	_work = Production.new(saved, _stock, null, clock, rules, func() -> Dictionary: return CATALOG)
	_towns = Towns.new(JSON.parse_string(JSON.stringify(_towns.to_dict())), _work, rules, clock)
	_run_to(23 * day + 1200)
	_check(_work.job(temple).get("state") == "working", "after a restart, its ore and wood in at last: the temple's repair is taken (%s)" % [_work.job(temple)])


## 522 amended (3): what stands for _stands' five readers (newcomers, crop, butcher, stages,
## visitors) and _farmed, by a building's state. Only a raise of a standing building changed:
## BUILDING at level 1 or more stands at the level it has, as allows reads it; a first raise
## (PLANNED, level 0), a damaged building under its repair (DAMAGED, its job set), one in disrepair
## or a ruin stand for none of them, as on main.
func _test_stands_states() -> void:
	print("
== what stands: a raise keeps its level, a first raise or a repair doesn't (522 amended (3)) ==")
	_fresh()
	_towns.note_rescue(TOWN, "tam", "Tam", "farmer")
	var cases := [
		["standing at level 1", {"level": 1, "state": Towns.STANDING, "job": 0}, true],
		["raised to its second level (BUILDING, level 1)", {"level": 1, "state": Towns.BUILDING, "job": 7}, true],
		["a first raise, nothing stood yet (PLANNED, level 0)", {"level": 0, "state": Towns.PLANNED, "job": 7}, false],
		["damaged, its repair ordered (DAMAGED, level 1)", {"level": 1, "state": Towns.DAMAGED, "job": 7}, false],
		["in disrepair (level 1)", {"level": 1, "state": Towns.DISREPAIR, "job": 0}, false],
		["a ruin (level 0)", {"level": 0, "state": Towns.RUIN, "job": 0}, false],
	]
	for each: Array in cases:
		for kind: String in ["kitchen", "field"]:
			var entry: Dictionary = (each[1] as Dictionary).duplicate()
			entry["kind"] = kind
			entry["since"] = 0
			_towns._town(TOWN)["buildings"][kind] = entry
		var allowed := _towns.allows({"trade": "cook", "town": TOWN})
		_check(_towns._stands(TOWN, "kitchen") == each[2] and _towns._farmed(TOWN) == each[2] and allowed == (each[2] as bool),
			"%s: stands for the five and the field is farmed: %s; its bench works: %s" % [each[0], _towns._stands(TOWN, "kitchen"), allowed])


## Towns' and Production's turns every 600 steps up to [param step].
func _run_to(step: int) -> void:
	while _now + 600 <= step:
		_at(_now + 600)
	if _now < step:
		_at(step)
