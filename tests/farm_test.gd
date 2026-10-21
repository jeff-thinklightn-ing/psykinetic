extends Node
## Farms (decision 449), on a clock of their own with the real rules
## (levels/economy.json "crop", buildings.field) and Season's year from
## the first day of spring: a field's crop sown by its farmer in spring,
## grown in summer by the rain (a normal year about one, a drought less), a
## summer storm flattening half, brought in in autumn as harvest x level x
## growth food, roots in winter; no farmer in spring: no crop; away in
## autumn: it rots; a field at level 2 gives twice; a field with no farmer
## gets a newcomer after growth_days; the crop saved and loaded. A
## woodcutter's wood, more with a woodshed, and one coming to a town with
## a building waiting on wood.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const TOWN := "fm/store"
const DAY := 54000

var _failures := 0
var _now := 0
var _rules := {}
var _rain := 0.11
var _storm := false


func _ready() -> void:
	World.set_process(false)
	DayNight.day_steps = DAY
	Season.season_days = 7
	Season.year_phase = 0.0
	Season.year_anchor = 0
	_rules = Production.read_rules()
	_test_years()
	_test_missed()
	_test_farmer_comes()
	_test_look()
	_test_woodcutter()
	_test_flock()
	_test_season_scale()
	_test_maker_comes()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _towns(level := 1, with_farmer := true, rules := _rules) -> Towns:
	_now = 0
	var clock := func() -> int: return _now
	var work := Production.new({}, Stockpile.new({}, clock, ItemBook.new(clock)), null, clock, rules)
	var towns := Towns.new({}, work, rules, clock)
	towns.rain = func(_town: String, from: float, to: float) -> float: return _rain * (to - from) / DAY
	towns.storms = func(_town: String, from: float, to: float) -> Array:
		# One full storm late in summer (day 13), if wanted.
		var at := 13.0 * DAY + 100.0
		return [{"id": "storm:test:1", "strength": 1.0}] if _storm and at >= from and at < to else []
	towns._town(TOWN)["buildings"]["field"] = {"kind": "field", "level": level, "state": Towns.STANDING, "since": 0, "job": 0}
	if with_farmer:
		towns.note_rescue(TOWN, "f1", "Tam", "farmer")
	return towns


## A year of [param towns] from now; the food it brought in.
func _year(towns: Towns, days := 28) -> int:
	var before := towns.production.stockpile.count(TOWN, "food")
	var until := _now + days * DAY
	while _now < until:
		_now += World.WORLD_TICK_STEPS
		towns.tick()
		towns.production.tick()
	return towns.production.stockpile.count(TOWN, "food") - before


func _test_years() -> void:
	print("\n== a year of the crop ==")
	var rule: Dictionary = _rules["crop"]
	var harvest := float(rule["harvest"])
	var roots := int(rule["roots"])
	_rain = 0.11
	_storm = false
	var towns := _towns()
	var normal := _year(towns)
	_check(towns.log_of(TOWN).any(func(line: Dictionary) -> bool: return line["what"] == "the field is sown"), "sown in spring")
	_check(normal >= roundi(harvest * 0.9) + roots and normal <= roundi(harvest * 1.15) + roots,
		"a normal year (rain %.2f a day): about harvest + roots (%d food)" % [_rain, normal])
	_rain = 0.0
	var dry := _year(_towns())
	_check(dry == roundi(harvest * float(rule["growth"]["base"])) + roots, "a drought: base growth only (%d food)" % dry)
	_rain = 0.11
	_storm = true
	var rules := _rules.duplicate(true)
	rules["crop"]["flatten"] = 1.0
	var storm_town := _towns(1, true, rules)
	var flattened := _year(storm_town)
	_check(flattened < normal - roundi(harvest * 0.3) and storm_town.crop(TOWN)["flattened"] >= 0
		and storm_town.log_of(TOWN).any(func(line: Dictionary) -> bool: return line["what"] == "a storm flattened half the crop"),
		"a summer storm flattens it (%d food)" % flattened)
	_storm = false
	var twice := _year(_towns(2))
	_check(absi(twice - 2 * normal) <= 2, "a field at level 2 gives twice (%d)" % twice)
	towns = _towns()
	_year(towns, 12)
	var saved := Towns.new(JSON.parse_string(JSON.stringify(towns.to_dict())), towns.production, _rules, func() -> int: return _now)
	_check(saved.crop(TOWN)["stage"] == "sown" and is_equal_approx(float(saved.crop(TOWN)["growth"]), float(towns.crop(TOWN)["growth"])),
		"the growing crop saved and loaded (%s)" % [saved.crop(TOWN)])


func _test_missed() -> void:
	print("\n== a farmer away ==")
	var rule: Dictionary = _rules["crop"]
	_rain = 0.11
	var towns := _towns()
	towns.production.set_away("f1", true)
	var spring := _year(towns, 7)
	towns.production.set_away("f1", false)
	var rest := _year(towns, 21)
	_check(spring + rest == int(rule["roots"]) and towns.crop(TOWN)["stage"] == "", "away all spring: nothing sown, only the roots (%d)" % (spring + rest))
	towns = _towns()
	_year(towns, 13)
	towns.production.set_away("f1", true)
	_year(towns, 8)  # Through all of autumn (days 14 to 21).
	_check(not towns.log_of(TOWN).any(func(line: Dictionary) -> bool: return str(line["what"]).begins_with("the harvest is in")), "away all autumn: not brought in")
	towns.production.set_away("f1", false)
	_year(towns, 2)
	_check(towns.crop(TOWN)["stage"] == "rotted" and towns.log_of(TOWN).any(func(line: Dictionary) -> bool: return line["what"] == "the crop rotted in the field"),
		"not brought in by winter: it rots")


func _test_farmer_comes() -> void:
	print("\n== a field with no farmer ==")
	var towns := _towns(1, false)
	_year(towns, int(_rules["crop"]["growth_days"]) - 1)
	_check(towns.residents(TOWN).is_empty(), "not before growth_days")
	_year(towns, 2)
	var farmers := towns.residents(TOWN).filter(func(id: String) -> bool: return "farmer" in towns.production.worker(id)["trades"])
	_check(farmers.size() == 1 and towns.production.worker(farmers[0])["origin"] == "growth", "then a farmer comes (%s)" % [farmers])
	_year(towns, 7)
	_check(towns.residents(TOWN).filter(func(id: String) -> bool: return "farmer" in towns.production.worker(id)["trades"]).size() == 1, "and only one")


## The field's look through a year (decision 457), each change told once.
func _test_look() -> void:
	print("
== the field's look ==")
	_rain = 0.11
	_storm = true
	var rules := _rules.duplicate(true)
	rules["crop"]["flatten"] = 1.0
	var towns := _towns(1, true, rules)
	var told: Array[String] = []
	var tell := func(_town: String, kind: String) -> void:
		if kind == "field":
			told.append(towns.buildings_of(TOWN)["field"]["crop"])
	towns.building_changed.connect(tell)
	var seen: Array[String] = []
	var until := _now + 28 * DAY
	while _now < until:
		_now += World.WORLD_TICK_STEPS
		towns.tick()
		towns.production.tick()
		var look := towns.crop_look(TOWN)
		if seen.is_empty() or seen.back() != look:
			seen.append(look)
	# The storm is late in summer (day 13): its day of "flattened" runs into autumn.
	_check(seen == ["", "sown", "growing", "flattened", "ripe", ""], "bare, sown, growing, flattened, ripe, bare (%s)" % [seen])
	_check(told == ["sown", "growing", "flattened", "ripe", ""], "each change told once, with the town's buildings (%s)" % [told])
	_check(not towns.buildings_of(TOWN)["field"].is_empty() and towns.buildings_of(TOWN)["field"].has("crop"), "the field's entry carries it")
	towns.building_changed.disconnect(tell)  # It holds the town: let both go.
	_storm = false


## The woodcutter (decision 497): wood every woodcutter.every steps,
## per_level more for a standing woodshed; a newcomer to a town whose
## building waits on wood with nobody to cut it.
func _test_woodcutter() -> void:
	print("
== the woodcutter ==")
	var rule: Dictionary = _rules["woodcutter"]
	var cuts := DAY / int(rule["every"]) - 1  # The first due one every after joining.
	var towns := _towns(1, false)
	towns.note_rescue(TOWN, "w1", "Bran", "woodcutter")
	var stock := towns.production.stockpile
	_year(towns, 1)
	_check(stock.count(TOWN, "wood") == int(rule["wood"]) * cuts, "a day's cutting: %d wood (%d cuts)" % [stock.count(TOWN, "wood"), cuts])
	towns._town(TOWN)["buildings"]["woodshed"] = {"kind": "woodshed", "level": 1, "state": Towns.STANDING, "since": 0, "job": 0}
	var before := stock.count(TOWN, "wood")
	_year(towns, 1)
	_check(stock.count(TOWN, "wood") - before == (int(rule["wood"]) + int(rule["per_level"])) * (cuts + 1), "with a woodshed: %d more a cut" % int(rule["per_level"]))
	towns.production.set_away("w1", true)
	before = stock.count(TOWN, "wood")
	_year(towns, 1)
	_check(stock.count(TOWN, "wood") == before, "away: none")
	var bare := _towns(1, false)
	_year(bare, int(ceilf(float(rule["growth_days"]))) + 1)
	_check(bare.residents(TOWN).is_empty(), "nothing waiting on wood: nobody comes")
	bare.add_xp(TOWN, 100, "test")
	_check(bare.unlock(TOWN, "tannery") and bare.building(TOWN, "tannery")["state"] == Towns.PLANNED, "a tannery planned, no wood for it")
	_year(bare, int(ceilf(float(rule["growth_days"]))) + 1)
	var cutters := bare.residents(TOWN).filter(func(id: String) -> bool: return "woodcutter" in bare.production.worker(id)["trades"])
	_check(cutters.size() == 1 and bare.production.worker(cutters[0])["origin"] == "growth", "a woodcutter comes (%s)" % [cutters])
	_year(bare, 3)
	_check(bare.residents(TOWN).filter(func(id: String) -> bool: return "woodcutter" in bare.production.worker(id)["trades"]).size() == 1, "and only one")


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


## Sheep and wool (decision 500): a farmed field has the town build a
## pasture, which brings a shepherd with a flock, sheared in spring and
## autumn, lambs each spring; wool in the store has it build a loom, which
## brings a weaver.
func _test_flock() -> void:
	print("
== sheep and wool ==")
	var rule: Dictionary = _rules["flock"]
	var towns := _towns()
	towns._town(TOWN)["xp"] = 1000
	_check(towns.choose(TOWN) == "pasture", "a farmed field: the town would build a pasture (%s)" % towns.choose(TOWN))
	_year(towns, 1)
	_check(towns.flock(TOWN).is_empty(), "no pasture: no shepherd")
	towns._town(TOWN)["buildings"]["pasture"] = {"kind": "pasture", "level": 1, "state": Towns.STANDING, "since": _now, "job": 0}
	_year(towns, int(rule["growth_days"]) - 1)
	_check(towns.flock(TOWN).is_empty(), "no shepherd before growth_days")
	_year(towns, 2)
	var shepherds := towns.residents(TOWN).filter(func(id: String) -> bool: return "shepherd" in towns.production.worker(id)["trades"])
	_check(shepherds.size() == 1 and int(towns.flock(TOWN)["count"]) == int(rule["start"]), "the pasture brings a shepherd and his flock of %d (%s)" % [int(rule["start"]), towns.flock(TOWN)])
	_year(towns, 1)
	var shorn := int(rule["start"]) * int(rule["wool"])
	_check(towns.production.stockpile.count(TOWN, "wool") == shorn, "sheared in spring, %d wool to the store" % shorn)
	_check(towns.choose(TOWN) == "loom", "wool in the store: the town would build a loom (%s)" % towns.choose(TOWN))
	towns._town(TOWN)["buildings"]["loom"] = {"kind": "loom", "level": 1, "state": Towns.STANDING, "since": _now, "job": 0}
	_year(towns, int(rule["weaver"]["growth_days"]) + 1)
	_check(towns.residents(TOWN).any(func(id: String) -> bool: return "weaver" in towns.production.worker(id)["trades"]), "the loom brings a weaver")
	_year(towns, 2)  # Day 12, summer.
	var shearings := func() -> int: return towns.log_of(TOWN).filter(func(line: Dictionary) -> bool: return str(line["what"]).begins_with("the flock is sheared")).size()
	_check(shearings.call() == 1 and towns.production.stockpile.count(TOWN, "cloth") > 0, "not sheared in summer; the weaver weaves the wool (%d cloth)" % towns.production.stockpile.count(TOWN, "cloth"))
	_year(towns, 8)  # Day 20, autumn.
	_check(shearings.call() == 2, "sheared again in autumn")
	_year(towns, 9)  # Day 29, spring again.
	var lambs := int(rule["start"]) * float(rule["lambs"]) * (1.0 - float(rule["start"]) / float(rule["per_level"]))
	_check(is_equal_approx(float(towns.flock(TOWN)["count"]), int(rule["start"]) + lambs), "lambs in spring: %.1f sheep" % float(towns.flock(TOWN)["count"]))
	var saved := Towns.new(JSON.parse_string(JSON.stringify(towns.to_dict())), towns.production, _rules, func() -> int: return _now)
	_check(is_equal_approx(float(saved.flock(TOWN)["count"]), float(towns.flock(TOWN)["count"])), "the flock saved and loaded")


## Longer seasons (decision 533): a 14-day season's harvest is twice a
## 7-day one's, so the food a day stays the same.
func _test_season_scale() -> void:
	print("
== the season's length ==")
	_rain = 0.11
	_storm = false
	var short := _year(_towns())
	Season.season_days = 14
	var long := _year(_towns(), 56)
	Season.season_days = 7
	_check(absi(long - 2 * short) <= 4, "a 14-day year (56 days) brings in twice a 7-day one's food (%d, %d): the same a day" % [long, short])


## A maker's bench left with nobody of its trade (decision 552): a
## newcomer of it after maker_comes.growth_days, seated there; only one.
func _test_maker_comes() -> void:
	print("
== a carpenter's bench with nobody ==")
	var towns := _towns(1, false)
	towns.note_rescue(TOWN, "c1", "Pip", "carpenter")
	var shop := towns.production.workshop_of("c1")
	_check(not shop.is_empty(), "the carpenter is seated (%s)" % shop)
	var carpenters := func() -> Array:
		return towns.residents(TOWN).filter(func(id: String) -> bool: return "carpenter" in towns.production.worker(id)["trades"])
	_year(towns, 5)
	_check(carpenters.call().size() == 1, "none comes while he works")
	# Turned to other work (npc's acolyte): off his bench, another trade.
	towns.production.assign(shop, "")
	towns.production._workers["c1"]["trades"] = ["acolyte"]
	_year(towns, int(_rules["maker_comes"]["growth_days"]) - 1)
	_check(carpenters.call().is_empty(), "not before growth_days")
	_year(towns, 2)
	var came: Array = carpenters.call()
	_check(came.size() == 1 and towns.production.worker(came[0])["origin"] == "growth" and towns.production.workshop_of(came[0]) == shop,
		"then a carpenter comes, at his bench (%s)" % [came])
	_year(towns, 7)
	_check(carpenters.call().size() == 1, "and only one")

