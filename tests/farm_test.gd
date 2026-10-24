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
## a building waiting on wood. The sought (613): a farmer wanted is sought,
## placed, freed, lost, found again and brought home; held at a camp, home
## with its fall; answered by another; saved.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const TOWN := "fm/store"
const DAY := 54000

var _failures := 0
var _now := 0
var _rules := {}
## The rules with decline (649); _rules has none, so the other tests' towns
## never fall into disrepair for want of wood.
var _full := {}
var _rain := 0.11
var _storm := false


func _ready() -> void:
	World.set_process(false)
	DayNight.day_steps = DAY
	Season.season_days = 7
	Season.year_phase = 0.0
	Season.year_anchor = 0
	_full = Production.read_rules()
	_rules = _full.duplicate(true)
	_rules.erase("decline")
	_test_years()
	_test_missed()
	_test_farmer_comes()
	_test_look()
	_test_woodcutter()
	_test_felling()
	_test_stages()
	_test_decline()
	_test_ruin_regrows()
	_test_flock()
	_test_butcher()
	_test_season_scale()
	_test_maker_comes()
	_test_sought()
	_test_herders()
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


## The forest real (591, economy's side): a cut takes its trees from maps'
## fell, wood_per_tree each; a lot cut bare brings deadwood, said once; the
## walk growing is said.
func _test_felling() -> void:
	print("
== wood from the forest standing ==")
	var rule: Dictionary = _rules["woodcutter"]
	_check(int(rule["wood_per_tree"]) == 2 and int(rule["deadwood"]) == 1, "2 wood a tree, 1 of deadwood (economy.json)")
	var towns := _towns(1, false)
	towns.note_rescue(TOWN, "w1", "Bran", "woodcutter")
	var asked: Array = []
	var standing := [3]
	towns.fell = func(town: String, site_id: String, wanted: int) -> int:
		asked.append([town, site_id, wanted])
		var took := mini(wanted, standing[0])
		standing[0] -= took
		return took
	var worker := towns.production.worker("w1")
	var site := {"id": "fm/woodlot", "area": "fm", "cell": Vector2i(10, 10)}
	_check(towns._felled(TOWN, site, 3, worker) == 4 and asked.back() == [TOWN, "fm/woodlot", 2], "a cut of 3 asks for 2 trees and brings their 4 wood (%s)" % [asked])
	_check(towns._felled(TOWN, site, 3, worker) == 2 and standing[0] == 0, "the last tree: 2 wood")
	var said := func(text: String) -> int: return towns.log_of(TOWN).filter(func(line: Dictionary) -> bool: return str(line["what"]).begins_with(text)).size()
	_check(towns._felled(TOWN, site, 3, worker) == 1 and towns._felled(TOWN, site, 3, worker) == 1 and said.call("the woodlot is cut bare") == 1,
		"cut bare: deadwood, never none, and said once")
	standing[0] = 5
	_check(towns._felled(TOWN, site, 3, worker) == 4 and not bool(towns._town(TOWN).get("lot_bare", false)), "the lot moved on: trees again")
	towns._town(TOWN)["lot_walk"] = 100
	towns._felled(TOWN, site, 3, worker)
	_check(said.call("the woodlot has moved out") == 1, "the walk grown: said")
	var plain := _towns(1, false)
	plain.note_rescue(TOWN, "w1", "Bran", "woodcutter")
	_year(plain, 1)
	_check(plain.production.stockpile.count(TOWN, "wood") > 0, "no fell set: a cut brings its wood as before")


## Stages toward a city (591, economy's side; 649): a settlement from the
## start, a hamlet with 4 residents, a field and wood 20, a village with 8
## residents, a temple, an inn, a forge, a pasture and its priest; never
## lowered by _stage_turn (only decline lowers it).
func _test_stages() -> void:
	print("
== settlement, hamlet, village, town, city ==")
	var towns := _towns(1, false)
	var rose: Array = []
	towns.stage_changed.connect(func(town: String) -> void: rose.append(town))
	towns._stage_turn(TOWN)
	_check(towns.stage(TOWN) == "settlement" and rose == [TOWN], "a settlement from the start")
	for i in 4:
		towns.production.add_worker("v%d" % i, "V%d" % i, ["hauler"], TOWN, "test")
		towns._town(TOWN)["residents"].append("v%d" % i)
	towns._stage_turn(TOWN)
	_check(towns.stage(TOWN) == "settlement", "4 and a field, no wood: not yet a hamlet")
	towns.production.stockpile.deposit(TOWN, "wood", 20, "test")
	towns._stage_turn(TOWN)
	_check(towns.stage(TOWN) == "hamlet" and rose.size() == 2, "wood 20: a hamlet (%s)" % towns.stage(TOWN))
	for i in range(4, 7):
		towns.production.add_worker("v%d" % i, "V%d" % i, ["hauler"], TOWN, "test")
		towns._town(TOWN)["residents"].append("v%d" % i)
	towns.production.add_worker("pr", "Osric", ["priest"], TOWN, "appointed")
	towns._town(TOWN)["residents"].append("pr")
	for kind: String in ["temple", "inn", "forge"]:
		towns._town(TOWN)["buildings"][kind] = {"kind": kind, "level": 1, "state": Towns.STANDING, "since": 0, "job": 0}
	towns._stage_turn(TOWN)
	_check(towns.stage(TOWN) == "hamlet", "no pasture: not yet a village")
	towns._town(TOWN)["buildings"]["pasture"] = {"kind": "pasture", "level": 1, "state": Towns.STANDING, "since": 0, "job": 0}
	towns._stage_turn(TOWN)
	_check(towns.stage(TOWN) == "village" and rose.size() == 3, "8 residents, temple, inn, forge, pasture, priest: a village (%s)" % towns.stage(TOWN))
	towns._town(TOWN)["buildings"]["inn"]["state"] = Towns.DAMAGED
	towns._stage_turn(TOWN)
	_check(towns.stage(TOWN) == "village", "the inn damaged: _stage_turn never lowers")
	var saved := Towns.new(JSON.parse_string(JSON.stringify(towns.to_dict())), towns.production, _rules, func() -> int: return _now)
	_check(saved.stage(TOWN) == "village", "the stage saved")


## Towns fall as well as rise (649): a hamlet short of residents gains a
## day of strain a day and falls back at strain_days; a captive adds
## captive_strain; a day with nothing short takes one off. Upkeep paid
## nearest the store first: a short store leaves the furthest owing, and
## unkept_days later it is in disrepair (out of use), a level lost a season,
## a ruin, then gone: ruined told with its cells, never seeded again; all
## saved.
func _test_decline() -> void:
	print("
== towns fall as well as rise ==")
	var rule: Dictionary = _full["decline"]
	var towns := _towns(1, false, _full)
	towns._town(TOWN)["stage"] = "hamlet"
	var fell: Array = []
	towns.stage_changed.connect(func(town: String) -> void: fell.append(town))
	var days := int(rule["strain_days"])
	for day in days - 1:
		towns._strain_turn(TOWN, rule)
	_check(towns.stage(TOWN) == "hamlet" and towns.strain(TOWN)["days"] == days - 1 and towns.strain(TOWN)["why"].begins_with("too few people"),
		"no people: %d days of strain, still a hamlet (%s)" % [days - 1, towns.strain(TOWN)])
	towns._strain_turn(TOWN, rule)
	_check(towns.stage(TOWN) == "settlement" and fell == [TOWN] and towns.strain(TOWN)["days"] == 0,
		"the %dth day: back to a settlement (%s)" % [days, towns.stage(TOWN)])
	towns._strain_turn(TOWN, rule)
	_check(towns.stage(TOWN) == "settlement" and towns.strain(TOWN)["days"] == 0, "a settlement never falls further")
	towns._town(TOWN)["stage"] = "hamlet"
	for i in 4:
		towns.production.add_worker("h%d" % i, "H%d" % i, ["hauler"], TOWN, "test")
		towns._town(TOWN)["residents"].append("h%d" % i)
	towns._town(TOWN)["strain"] = 2
	towns._strain_turn(TOWN, rule)
	_check(towns.strain(TOWN)["days"] == 1, "a day with nothing short: a day off")
	towns._take(TOWN, "h3", "goblins", "")
	_check(towns.strain(TOWN)["days"] == 1 + int(rule["captive_strain"]), "a captive: %d days more" % rule["captive_strain"])
	# Hunger: three of the four hungry; food in the store, a purse's problem.
	towns.note_rescue(TOWN, "h4", "H4", "hauler")
	for id: String in ["h0", "h1", "h2"]:
		towns.production._workers[id]["fed"] = "hungry"
	var larder := towns.production.stockpile
	larder.take(TOWN, "food", larder.count(TOWN, "food"), "test")
	larder.deposit(TOWN, "food", 3, "test")
	towns._town(TOWN)["strain"] = 0
	towns._strain_turn(TOWN, rule)
	_check(towns.strain(TOWN)["days"] == 0, "hungry with food in the store: no strain (%s)" % [towns.strain(TOWN)])
	larder.take(TOWN, "food", 1, "test")
	towns._strain_turn(TOWN, rule)
	_check(towns.strain(TOWN)["days"] == 1 and towns.strain(TOWN)["why"] == "hunger", "the hungry more than the store's food: hunger (%s)" % [towns.strain(TOWN)])
	towns.production.set_owed("h4", 5)
	for id: String in ["h0", "h1", "h2"]:
		towns.production._workers[id]["fed"] = ""
	towns._strain_turn(TOWN, rule)
	_check(towns.strain(TOWN)["days"] == 0, "fed again: a day off; an unpaid resident is no strain")
	# Upkeep: the field near, the inn far; wood for one of them.
	var far := {"field": 2.0, "inn": 30.0}
	var told: Array = []
	towns.placed = func(_town: String, kind: String) -> Dictionary: return {"zone": "fm", "cells": [Vector2i(1, 1), Vector2i(2, 1)], "distance": far.get(kind, 0.0)}
	towns.ruined.connect(func(town: String, kind: String, zone: String, cells: Array[Vector2i]) -> void: told.append([town, kind, zone, cells.size()]))
	towns._town(TOWN)["buildings"]["inn"] = {"kind": "inn", "level": 2, "state": Towns.STANDING, "since": 0, "job": 0}
	towns.note_rescue(TOWN, "f1", "Tam", "farmer")  # The field's trade at home.
	var store := towns.production.stockpile
	store.take(TOWN, "wood", store.count(TOWN, "wood"), "test")
	store.deposit(TOWN, "wood", int(rule["upkeep"]["cost"]["wood"]), "test")
	var every := int(rule["upkeep"]["every"])
	var round := int(rule["upkeep"]["cost"]["wood"]) * 3
	_check(towns.upkeep_due(TOWN) == {"wood": round}, "a round of upkeep: the field 1 and the inn 2 levels (%s)" % [towns.upkeep_due(TOWN)])
	store.deposit(TOWN, "wood", round + 3, "test")  # With the 1 there: a round and 4.
	_check(towns.production._keeps(TOWN, {"recipe": "forge", "cost": {"wood": 4}}) and not towns.production._keeps(TOWN, {"recipe": "forge", "cost": {"wood": 5}})
		and towns.production._keeps(TOWN, {"recipe": Towns.REPAIR + "inn", "cost": {"wood": 99}}),
		"a new build keeps a round of upkeep in the store; a repair may use it")
	store.take(TOWN, "wood", round + 3, "test")
	towns._upkeep_turn(TOWN, rule, 0)
	_check(not towns.building(TOWN, "inn").has("owed") and store.count(TOWN, "wood") == 1, "first seen: nothing paid yet, nothing owed")
	towns._upkeep_turn(TOWN, rule, every)
	_check(not towns.building(TOWN, "field").has("owed") and towns.building(TOWN, "inn").get("owed") == every and store.count(TOWN, "wood") == 0,
		"wood for one: the field (nearest) kept, the inn (the edge) owing")
	var unkept := int(rule["unkept_days"])
	for day in range(every, every + unkept + 1):
		towns._neglect_turn(TOWN, rule, day)
	_check(towns.building(TOWN, "inn")["state"] == Towns.DISREPAIR and not towns._stands(TOWN, "inn") and towns.building(TOWN, "field")["state"] == Towns.STANDING,
		"%d days owing: the inn in disrepair, the field standing" % unkept)
	var season := Season.season_days
	var day := every + unkept
	towns._neglect_turn(TOWN, rule, day + season)
	_check(towns.building(TOWN, "inn")["level"] == 1 and towns.building(TOWN, "inn")["state"] == Towns.DISREPAIR, "a season on: down a level")
	towns._neglect_turn(TOWN, rule, day + 2 * season)
	_check(towns.building(TOWN, "inn")["state"] == Towns.RUIN and not towns.walls_up(TOWN, "inn"), "another: a ruin, its walls down (walked over)")
	var again := Towns.new(JSON.parse_string(JSON.stringify(towns.to_dict())), towns.production, _full, func() -> int: return _now)
	_check(again.building(TOWN, "inn")["state"] == Towns.RUIN and again.building(TOWN, "inn").has("ruin") and again.strain(TOWN)["days"] == towns.strain(TOWN)["days"],
		"the ruin and the strain saved")
	towns._neglect_turn(TOWN, rule, day + 3 * season)
	_check(towns.building(TOWN, "inn").is_empty() and told == [[TOWN, "inn", "fm", 2]] and towns.buildings_of(TOWN).get("inn", {}).get("state") == "gone" and towns.buildings_of(TOWN)["inn"]["walls"] == false,
		"a season a ruin: gone, its cells given back (%s)" % [told])
	var world_map := WorldMap.new()
	world_map.areas["fm"] = {"places": {}, "buildings": [{"use": "inn", "town": "store"}]}
	towns.seed_from(world_map)
	_check(towns.building(TOWN, "inn").is_empty(), "gone: the map's inn not seeded again")
	# A fresh town given the map's buildings starts at a hamlet, not tents.
	var fresh := _towns(1, false, _full)
	fresh._town(TOWN)["buildings"].clear()
	var mapped := WorldMap.new()
	mapped.areas["fm"] = {"places": {}, "buildings": [{"use": "inn", "town": "store"}, {"use": "temple", "town": "store"}]}
	fresh.seed_from(mapped)
	_check(fresh.stage(TOWN) == "hamlet", "a town seeded with the map's inn and temple: a hamlet from the start (%s)" % fresh.stage(TOWN))
	fresh._stage_turn(TOWN)
	_check(fresh.stage(TOWN) == "hamlet", "and never back to a settlement by _stage_turn")
	var saved_stage := _towns(1, false, _full)
	saved_stage._town(TOWN)["stage"] = "village"
	saved_stage.seed_from(mapped)
	_check(saved_stage.stage(TOWN) == "village", "a saved stage kept")


## A ruin's ground through the real Clearing (649 amended): the town's ruin
## gone, Towns.ruined handed to Clearing.unbuild as Main does: its cells
## stumps from that day, grown back over seasons to kept trunks; the kind
## built again, Towns.reclaimed to Clearing.build: built over, never growing.
func _test_ruin_regrows() -> void:
	print("
== a ruin's ground back to the forest, and built again ==")
	var size := Vector2i(24, 14)
	var colour := func(meaning: String) -> Color: return Color(str(Level.LEGEND[meaning]))
	var image := Image.create_empty(size.x * 2 + 1, size.y * 2 + 1, false, Image.FORMAT_RGBA8)
	image.fill(colour.call("grass"))
	image.set_pixel(2, 2, colour.call("start"))
	const ZONE := "fm_ruin"
	Level.register(ZONE, image, null, {"name": "Ruin Farm", "outdoor": true})
	var day := [0]
	var clearing := Clearing.new()
	clearing.clock = func() -> int: return day[0]
	var rule: Dictionary = _full["decline"]
	var towns := _towns(1, false, _full)
	var cells: Array[Vector2i] = [Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6)]
	towns.placed = func(_town: String, _kind: String) -> Dictionary: return {"zone": ZONE, "cells": cells, "distance": 5.0}
	# As Main._on_town_ruined and _on_town_reclaimed do.
	towns.ruined.connect(func(_town: String, _kind: String, zone: String, given: Array[Vector2i]) -> void: clearing.unbuild(zone, given, day[0]))
	towns.reclaimed.connect(func(_town: String, _kind: String, zone: String, taken: Array[Vector2i]) -> void: clearing.build(zone, taken))
	towns._town(TOWN)["buildings"]["inn"] = {"kind": "inn", "level": 0, "state": Towns.RUIN, "since": 0, "job": 0, "ruin": 0}
	day[0] = Season.season_days
	towns._neglect_turn(TOWN, rule, day[0])
	_check(towns.building(TOWN, "inn").is_empty() and cells.all(func(cell: Vector2i) -> bool: return clearing.felled.get(ZONE, {}).has(cell) and int(clearing.felled[ZONE][cell][0]) == 0),
		"the ruin gone: its cells stumps in the real Clearing")
	for season in range(2, 14):
		day[0] = Season.season_days * season
		clearing.daily(day[0])
	_check(cells.all(func(cell: Vector2i) -> bool: return clearing._kept(ZONE, cell)), "seasons on: the forest has it, kept trunks")
	towns._town(TOWN)["xp"] = 1000
	_check(towns.unlock(TOWN, "inn") and cells.all(func(cell: Vector2i) -> bool: return clearing.built_over.get(ZONE, {}).has(cell) and not clearing._kept(ZONE, cell)),
		"the inn built again: its ground cleared and built over")
	Level.unregister(ZONE)


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


## The meat chain (decision 590): a flock of butcher.from builds a
## butchery, which brings a butcher; the autumn cull drives the flock to
## butcher.keep of the pasture's room, live sheep into the store; the
## butcher makes each into meat and hide.
func _test_butcher() -> void:
	print("
== the herder, the butcher, the cook ==")
	var rule: Dictionary = _rules["butcher"]
	_check(int(rule["from"]) == 8 and float(rule["keep"]) == 0.5 and int(rule["meat"]) == 3 and int(rule["hide"]) == 1
		and int(_rules["value"]["sheep"]) == 5 and "sheep" in Stockpile.RESOURCES, "the rules are economy.json's (%s)" % [rule])
	var towns := _towns()
	towns._town(TOWN)["xp"] = 1000
	towns._town(TOWN)["buildings"]["pasture"] = {"kind": "pasture", "level": 1, "state": Towns.STANDING, "since": 0, "job": 0}
	towns.note_rescue(TOWN, "s1", "Wat", "shepherd")
	towns._town(TOWN)["flock"] = {"count": 7.0, "season": Season.name_at(_now), "sheared": false, "worked": 0, "at": _now}
	_check(towns.choose(TOWN) != "butchery", "a flock of 7: no butchery (%s)" % towns.choose(TOWN))
	towns._town(TOWN)["flock"]["count"] = 10.0
	_check(towns.choose(TOWN) == "butchery", "a flock of 10: the town would build a butchery (%s)" % towns.choose(TOWN))
	var flock: Dictionary = towns._town(TOWN)["flock"]
	towns._cull(TOWN, flock)
	_check(towns.production.stockpile.count(TOWN, "sheep") == 0 and float(flock["count"]) == 10.0, "no butcher: no cull")
	towns._town(TOWN)["xp"] = 0  # Nothing to spend on raising it while the butcher comes.
	towns._town(TOWN)["buildings"]["butchery"] = {"kind": "butchery", "level": 1, "state": Towns.STANDING, "since": _now, "job": 0}
	_year(towns, int(rule["growth_days"]) + 1)
	var butchers := towns.residents(TOWN).filter(func(id: String) -> bool: return "butcher" in towns.production.worker(id)["trades"])
	_check(butchers.size() == 1 and towns.production.manned(TOWN + ":butchery"), "the butchery brings a butcher, at his block (%s)" % [butchers])
	flock["count"] = 10.0
	towns._cull(TOWN, flock)
	_check(towns.production.stockpile.count(TOWN, "sheep") == 4 and float(flock["count"]) == 6.0,
		"the autumn cull: 10 down to 6 (half the pasture's 12), 4 sheep to the store (%d)" % towns.production.stockpile.count(TOWN, "sheep"))
	var meat := towns.production.stockpile.count(TOWN, "meat")
	var hide := towns.production.stockpile.count(TOWN, "hide")
	_year(towns, 1)
	_check(towns.production.stockpile.count(TOWN, "sheep") == 0 and towns.production.stockpile.count(TOWN, "meat") - meat == 12
		and towns.production.stockpile.count(TOWN, "hide") - hide == 4, "a day: the butcher dresses the 4, 12 meat and 4 hide (%d, %d)"
		% [towns.production.stockpile.count(TOWN, "meat") - meat, towns.production.stockpile.count(TOWN, "hide") - hide])
	var saved := Towns.new(JSON.parse_string(JSON.stringify(towns.to_dict())), towns.production, _rules, func() -> int: return _now)
	_check(saved.residents(TOWN).size() == towns.residents(TOWN).size() and int(saved._town(TOWN).get("butchers_came", 0)) == 1, "saved and loaded: his coming kept")


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
	# A newcomer's name is one the town doesn't have (552 amended).
	var names := ["Pip", "Wat", "Lise"]
	towns._town(TOWN)["dead_names"] = ["Wat"]
	_check(towns._free_name(TOWN, names, 0) == "Lise", "not a resident's name, nor a dead one's (%s)" % towns._free_name(TOWN, names, 0))
	_check(towns._free_name(TOWN, ["Pip"], 0) == "Pip", "every one taken: the first pick")



func _test_sought() -> void:
	print("
== the sought (613 amended): the farmer's story ==")
	var towns := _towns(1, false)
	var laid := {}  # Place key -> {place, where}: what maps has laid.
	var asked := []
	towns.place_sought = func(town: String, trade: String, variant: Dictionary, id: String) -> Variant:
		asked.append([town, trade, variant, id])
		return laid.get(str(variant.get("place", "")), "")
	var farmers := func(of: Towns) -> Array:
		return of.residents(TOWN).filter(func(id: String) -> bool: return "farmer" in of.production.worker(id)["trades"])
	var story: Dictionary = _rules["sought"]["trades"]["farmer"]
	_year(towns, int(_rules["crop"]["growth_days"]) + 1)
	var entries: Array = towns.sought(TOWN)
	_check(farmers.call(towns).is_empty() and entries.size() == 1 and str(entries[0]["trade"]) == "farmer" and str(entries[0]["place"]) == "",
		"no farmer walks in: one is sought, waiting while the farmstead isn't laid (%s)" % [entries])
	var id := str(entries[0]["id"]) if not entries.is_empty() else ""
	var worker: Dictionary = towns.production.worker(id)
	_check(worker.get("origin") == "sought" and bool(worker.get("away")) and id not in towns.residents(TOWN),
		"a worker of the town, away, not a resident (%s)" % [worker])
	_check(not asked.is_empty() and asked[0][2] == story and asked[0][1] == "farmer", "maps asked with the farmer's story (%s)" % [asked.back() if not asked.is_empty() else []])
	var tries := asked.size()
	_year(towns, 1)
	_check(asked.size() - tries <= 2, "tried about once a day (%d)" % (asked.size() - tries))
	laid[str(story["place"])] = {"place": "wilds/%s" % story["place"], "where": "wilds"}
	_year(towns, 2)
	var entry: Dictionary = towns.sought_entry(id)
	_check(entry.get("place") == "wilds/%s" % story["place"] and entry.get("where") == "wilds" and entry.get("holder") == ""
		and entry.get("story") == str(story["story"]) and entry.get("town") == TOWN, "then at the old farmstead, lost, his story's (%s)" % [entry])
	_check(towns.sought(TOWN).size() == 1 and farmers.call(towns).is_empty(), "only one sought, and still no farmer")
	_check(towns.free_sought(id, "p1") and not towns.free_sought(id, "p2") and towns.sought_entry(id)["freed_by"] == "p1", "freed by p1, once")
	_check(towns.sought_lost(id) and towns.sought_entry(id)["place"] == "" and towns.sought_entry(id)["freed_by"] == "", "lost on the way: unplaced again")
	towns.camps = func() -> Array: return [{"id": "wilds/camp_1", "area": "wilds", "cell": Vector2i.ZERO, "faction": "goblins"}]
	towns.home_of = func(_camp: String) -> String: return TOWN
	_year(towns, int(_rules["sought"]["restock_days"]) - 1)
	_check(towns.sought_entry(id)["place"] == "", "not placed again before restock_days")
	_year(towns, 2)
	entry = towns.sought_entry(id)
	_check(entry["place"] == "wilds/camp_1" and entry["holder"] == "goblins" and entry["story"] == str(story["alt"]["story"]) and towns.captive_held(id, "wilds/camp_1"),
		"a second time out: his story's other variant, held at the goblins' camp (%s)" % [entry])
	# Saved and loaded.
	var again := Towns.new(towns.to_dict(), towns.production, _rules, towns.clock)
	_check(again.sought_entry(id).get("story") == str(story["alt"]["story"]) and int(again.sought_entry(id).get("tries", 0)) == 2, "saved and loaded")
	var xp := towns.xp(TOWN)
	towns.camp_taken("wilds/camp_1", "goblins", Factions.NOBODY)
	_check(farmers.call(towns) == [id] and not bool(towns.production.worker(id)["away"]) and towns.sought(TOWN).is_empty() and towns.xp(TOWN) > xp
		and towns.captives(TOWN).is_empty(), "the camp falls: home, a resident farmer at work, rescue experience (%s)" % [farmers.call(towns)])

	print("
== wandering off, low too long ==")
	var gone := []
	towns.wandered.connect(func(town: String, who: String) -> void: gone.append([town, who]))
	towns.production.set_owed(id, 5)
	towns.note_rescue(TOWN, "h1", "Wat", "hunter")
	towns.production.set_owed("h1", 5)
	var leave := int(_rules["sought"]["leave_days"])
	var shop := towns.production.workshop_of(id)
	_year(towns, leave - 1)
	_check(gone.is_empty() and id in towns.residents(TOWN), "not before leave_days")
	_year(towns, 2)
	entry = towns.sought_entry(id)
	_check(gone == [[TOWN, id]] and id not in towns.residents(TOWN) and bool(entry.get("wandered")) and bool(towns.production.worker(id)["away"])
		and towns.sought(TOWN).filter(func(each: Dictionary) -> bool: return each["trade"] == "farmer").size() == 1,
		"owed too long: the farmer wanders off, the same worker, sought again (%s %s)" % [entry, gone])
	_check(entry.get("door") == (shop if not shop.is_empty() else "inn"), "the note on the door of the shop they kept (%s, %s)" % [entry.get("door"), shop])
	_check(towns.sought(TOWN).all(func(each: Dictionary) -> bool: return each["door"] == "" or bool(each["wandered"])), "one who never came has no door")
	_check("h1" in towns.residents(TOWN), "a hunter (no story of his trade) stays")
	_check(entry.get("place") == "wilds/%s" % story["place"] or entry.get("place") == "wilds/camp_1", "back to a place of his story (%s)" % entry.get("place"))
	_check(_year(towns, 1) >= 0 and towns.free_sought(id, "p1") and towns.sought_home(id) and id in towns.residents(TOWN), "found again and home")
	# Low again at once: not within wander_every_days of the last (613 amended, tuned).
	var every := int(_rules["sought"]["wander_every_days"])
	gone.clear()
	towns.production.set_owed(id, 5)
	towns._town(TOWN)["low"] = {id: _now - (leave + 1) * DAY}  # Low past leave_days already.
	towns._town(TOWN)["wandered_at"] = _now
	_year(towns, every - 1)
	_check(gone.is_empty(), "low past leave_days, but one went %d days ago: stays (%s)" % [every - 1, gone])
	_year(towns, 2)
	_check(gone.size() == 1, "past wander_every_days: goes (%s)" % [gone])

	print("
== the sought answered by another ==")
	towns = _towns(1, false)
	towns.place_sought = func(_t: String, _tr: String, _v: Dictionary, _i: String) -> String: return "wilds/x"
	_year(towns, int(_rules["crop"]["growth_days"]) + 1)
	id = str(towns.sought(TOWN)[0]["id"]) if not towns.sought(TOWN).is_empty() else ""
	towns.note_rescue(TOWN, "f9", "Ada", "farmer")
	_year(towns, 1)
	_check(towns.sought(TOWN).is_empty() and towns.production.worker(id).is_empty() and farmers.call(towns) == ["f9"], "a farmer came another way: the word called off, the sought gone")

	print("
== the smith under the castle, held by the goblins ==")
	towns = _towns(1, false)
	towns.place_sought = func(_t: String, _tr: String, variant: Dictionary, _i: String) -> Dictionary:
		return {"place": "castle/%s" % variant["place"], "where": variant["where"]}
	towns._seek(TOWN, "s1", "Bram", "smith")
	_year(towns, 1)
	entry = towns.sought_entry("s1")
	_check(entry.get("place") == "castle/dwarven_forge" and entry.get("holder") == "goblins" and entry.get("story") == "sought.smith",
		"at the great dwarven forge, held by the goblins (%s)" % [entry])
	_check(towns._story("medicine_man").is_empty(), "no story for the medicine man yet: he walks in")


## The hill herders (decision 640, economy's side): a herder comes to each
## hills refuge keyed in herder.places, with his start sheep; he lambs in
## spring, and every few days walks all but keep down to the town with a
## butchery, the fold's count dropping while he is away; the town buys
## what its treasury pays; what it doesn't comes home with him. No
## butchery: he stays home. Saved and loaded.
func _test_herders() -> void:
	print("
== the hill herders ==")
	var rule: Dictionary = _rules["herder"]
	_check(rule["places"] == ["herders_hut", "hill_shieling"] and int(rule["start"]) == 4 and int(rule["keep"]) == 2,
		"the rules are economy.json's (%s)" % [rule])
	var rows: Array[String] = []
	for y in 20:
		rows.append(".".repeat(40))
	Level.register("fh", Level.image_from_rows(rows), null, {"places": {
		"store": {"at": [4, 4], "kind": "stockpile", "radius": 3, "holder": "town"},
		"herders_hut": {"at": [30, 10], "kind": "other", "radius": 2, "holder": "nobody"}}})
	_now = 0
	var clock := func() -> int: return _now
	var holdings := Holdings.new(WorldMap.build(["fh"] as Array[String]), null, {}, clock)
	var stock := Stockpile.new({}, clock, ItemBook.new(clock))
	var work := Production.new({}, stock, holdings, clock, _rules)
	var towns := Towns.new({}, work, _rules, clock)
	const STORE := "fh/store"
	const HUT := "fh/herders_hut"
	var sold: Array = []
	var pays := [99]
	towns.drove = func(town: String, who: String, count: int, _food: int) -> int:
		var bought := mini(count, int(pays[0]))
		sold.append([town, who, count, bought])
		return bought
	towns._town(STORE)
	var day := DayNight.day_steps
	var tick_to := func(step: int) -> void:
		while _now < step:
			_now += World.WORLD_TICK_STEPS
			towns.tick()
	tick_to.call(int(rule["growth_days"]) * day - World.WORLD_TICK_STEPS)
	_check(work.worker("herder:" + HUT).is_empty(), "not before growth_days")
	tick_to.call(int(rule["growth_days"]) * day + World.WORLD_TICK_STEPS)
	var who := "herder:" + HUT
	_check(not work.worker(who).is_empty() and stock.count(HUT, "sheep") == 4 and towns.folds() == {HUT: 4} and work.outside(who),
		"a herder at the hut, with 4 sheep of his own; outside any town's purse (%s)" % [work.worker(who)])
	tick_to.call(_now + int(rule["every"]) * day + World.WORLD_TICK_STEPS)
	_check(sold.is_empty() and stock.count(HUT, "sheep") == 4, "no town with a butchery: no drove")
	towns._town(STORE)["buildings"]["butchery"] = {"kind": "butchery", "level": 1, "state": Towns.STANDING, "since": _now, "job": 0}
	_check(towns.drove_town(HUT) == STORE, "the town with a butchery buys")
	pays[0] = 1
	tick_to.call(_now + int(rule["every"]) * day + World.WORLD_TICK_STEPS)
	_check(sold.size() == 1 and sold[0] == [STORE, who, 2, 1] and stock.count(HUT, "sheep") == 2 and bool(work.worker(who)["away"]),
		"he drives 2 down (all but 2), the town pays for 1, the fold shows 2 while he walks (%s)" % [sold])
	tick_to.call(_now + int(rule["walk_steps"]) + World.WORLD_TICK_STEPS)
	_check(not bool(work.worker(who)["away"]) and stock.count(HUT, "sheep") == 3, "home with the unsold one: 3 (%d)" % stock.count(HUT, "sheep"))
	var saved := Towns.new({}, work, _rules, clock)
	saved.herders_from_dict(JSON.parse_string(JSON.stringify(towns.herders_to_dict())))
	_check(saved.herders_to_dict()[HUT]["next"] == towns.herders_to_dict()[HUT]["next"], "saved and loaded")
	Level.unregister("fh")
