extends Node
## Wells and roofs (decision 426), on a clock of its own with the real rules
## (levels/economy.json "water", "roof") and stand-ins for the world: a
## town's water starts full, its wells' spring and the rain fill it to cap a
## well, its residents draw it; dry and wet again are said once each; while
## dry the kitchen works at dry_rate (provisional, Jeff's to confirm), the
## smith as ever; a town with no well has no water; saved and loaded. A
## season of the town lands' real rain is printed for 10 and for 4
## residents. A storm-broken roof is mended by the carpenter, one at a
## time, priced in wood by its size, after a building's repair; whole
## already when he comes, the wood is still spent and the log says so.
## Reads the repo's levels, never the shared overlay.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const TOWN := "wt/store"
const DAY := 54000

var _failures := 0
var _now := 0
var _rules := {}
var _rain := 0.0


func _ready() -> void:
	World.set_process(false)
	DayNight.day_steps = DAY
	_rules = Production.read_rules()
	_test_water()
	_test_season()
	_test_roofs()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _towns(people: int, well_count := 1) -> Towns:
	_now = 0
	var clock := func() -> int: return _now
	var stock := Stockpile.new({}, clock, ItemBook.new(clock))
	var work := Production.new({}, stock, null, clock, _rules)
	var towns := Towns.new({}, work, _rules, clock)
	towns.wells = func(_town: String) -> int: return well_count
	towns.rain = func(_town: String, from: float, to: float) -> float: return _rain * (to - from) / DAY
	for i in people:
		towns.note_rescue(TOWN, "h%d" % i, "Folk%d" % i, "hauler")
	return towns


func _days(towns: Towns, days: float) -> void:
	var until := _now + int(days * DAY)
	while _now < until:
		_now += World.WORLD_TICK_STEPS * 10
		towns.tick()


func _test_water() -> void:
	print("\n== a town's water ==")
	var rule: Dictionary = _rules["water"]
	var towns := _towns(20)
	towns.tick()
	_check(towns.water(TOWN) == float(rule["cap"]) and not towns.dry(TOWN), "it starts full (%.1f)" % towns.water(TOWN))
	_rain = 0.0
	# Everyone there draws, the officials a town of twenty appoints too.
	var per_day := float(rule["spring"]) - towns.residents(TOWN).size() * float(rule["draw"])
	_days(towns, 1.0)
	_check(absf(towns.water(TOWN) - (float(rule["cap"]) + per_day)) < 0.1, "no rain: spring less its residents' draw a day (%.1f)" % towns.water(TOWN))
	_days(towns, ceilf(float(rule["cap"]) / -per_day) + 1.0)
	_check(towns.dry(TOWN) and towns.water(TOWN) == 0.0, "it runs dry")
	_check(towns.log_of(TOWN).filter(func(line: Dictionary) -> bool: return line["what"] == "the well is dry").size() == 1, "the log says so once")
	var kitchen := {"id": TOWN + ":kitchen", "trade": "cook", "town": TOWN}
	var forge := {"id": TOWN + ":forge", "trade": "smith", "town": TOWN}
	_check(towns.production.work_rate.call(kitchen) == float(rule["dry_rate"]) and towns.production.work_rate.call(forge) == 1.0,
		"while dry the kitchen works at %.1f, the forge as ever" % float(rule["dry_rate"]))
	_rain = 1.0
	_days(towns, 1.0)
	_check(not towns.dry(TOWN) and towns.log_of(TOWN).any(func(line: Dictionary) -> bool: return line["what"] == "the well has water again"),
		"a day of rain: water again (%.1f)" % towns.water(TOWN))
	_check(towns.production.work_rate.call(kitchen) == 1.0, "and the kitchen as ever")
	_days(towns, 20.0)
	_check(towns.water(TOWN) == float(rule["cap"]), "never past cap a well (%.1f)" % towns.water(TOWN))
	var saved := Towns.new(JSON.parse_string(JSON.stringify(towns.to_dict())), towns.production, _rules, func() -> int: return _now)
	_check(saved.water(TOWN) == towns.water(TOWN) and not saved.dry(TOWN), "saved and loaded")
	var none := _towns(10, 0)
	_days(none, 3.0)
	_check(not none.to_dict().get(TOWN, {}).has("water") and not none.dry(TOWN), "no well: no water kept, never dry")


## The town lands' real rain over a season (90 days), with 10 and with 4
## residents: the water each 10 days and the days dry, for tuning.
func _test_season() -> void:
	print("\n== a season of the town lands' rain ==")
	for people in [10, 4]:
		var towns := _towns(people)
		towns.rain = func(_town: String, from: float, to: float) -> float: return Weather.rain_between("town_lands", from, to)
		towns.tick()
		var line: Array[String] = []
		var dry_days := 0
		for day in 90:
			_days(towns, 1.0)
			if towns.dry(TOWN):
				dry_days += 1
			if day % 10 == 9:
				line.append("%d" % roundi(towns.water(TOWN)))
		print("  %d residents: water every 10 days %s; %d days dry of 90 (%.1f days of full rain fell)" % [people, ", ".join(line), dry_days,
			Weather.rain_between("town_lands", 0.0, 90.0 * DAY)])
		_check(dry_days < 90, "%d residents: not dry the whole season" % people)


func _test_roofs() -> void:
	print("\n== a storm-broken roof ==")
	var towns := _towns(0, 0)
	towns._town(TOWN)  # A town with nobody yet still has its roofs.
	var work := towns.production
	var broken := {2: 24}
	var mended: Array[int] = []
	towns.roofs = func(_town: String) -> Array:
		var out := []
		for index: int in broken:
			out.append({"index": index, "cells": broken[index]})
		return out
	towns.mend_roof = func(_town: String, index: int) -> bool:
		mended.append(index)
		return broken.erase(index)
	work.stockpile.deposit(TOWN, "wood", 10)
	work.add_worker("p1", "Pell", ["carpenter"], TOWN)
	work.add_workshop(TOWN + ":carpenter", "carpenter", TOWN)
	work.assign(TOWN + ":carpenter", "p1")
	var rule: Dictionary = _rules["roof"]
	var wood := int(rule["wood_base"]) + 24 / int(rule["wood_cells"])
	towns.tick()
	_check(work.building_in(TOWN) and towns.log_of(TOWN).back()["what"] == "a roof broken by the storm is to be mended (%d wood)" % wood,
		"a broken roof is ordered mended, %d wood for 24 cells" % wood)
	broken[5] = 8
	towns.tick()
	_check(work.jobs().size() == 1, "one roof at a time")
	_run(towns, int(rule["steps"]) + 600)
	_check(mended == [2], "the carpenter mends it (%s)" % [mended])
	_check(towns.log_of(TOWN).any(func(line: Dictionary) -> bool: return line["what"] == "a roof is mended"), "the log says so")
	_run(towns, int(rule["steps"]) + 1200)
	_check(mended == [2, 5], "then the next (%s)" % [mended])
	var small := int(rule["wood_base"]) + 8 / int(rule["wood_cells"])
	_check(work.stockpile.count(TOWN, "wood") == 10 - wood - small, "the wood used: %d and %d" % [wood, small])
	_check(work.jobs().is_empty() and broken.is_empty(), "and nothing left to do")
	broken[7] = 8
	towns.tick()
	broken.erase(7)  # Mended some other way before he gets there.
	_run(towns, int(rule["steps"]) + 600)
	_check(towns.log_of(TOWN).any(func(line: Dictionary) -> bool: return line["what"] == "a roof the carpenter came to was whole already"),
		"whole already when he comes: the log says so")


func _run(towns: Towns, steps: int) -> void:
	var until := _now + steps
	while _now < until:
		_now += World.WORLD_TICK_STEPS
		towns.production.tick()
		towns.tick()


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
