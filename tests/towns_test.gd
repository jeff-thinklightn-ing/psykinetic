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
	_towns.note_rescue(TOWN, "bram", "Bram", "smith")
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
	_at(5700)
	_check(_towns.building(TOWN, "forge")["state"] == Towns.PLANNED, "at 5700, still being built")
	_at(6000)
	_check(_towns.building(TOWN, "forge").get("state") == Towns.STANDING and _towns.building(TOWN, "forge")["level"] == 1,
		"at 6000 the forge stands, level 1")
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
	rules["build_wait"] = {"days": 2, "most": 3}
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

