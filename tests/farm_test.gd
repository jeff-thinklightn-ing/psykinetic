extends Node
## Farms (decision 449), on a clock of their own with the real rules
## (levels/economy.json "crop", buildings.field) and Season's year from
## the first day of spring: a field's crop sown by its farmer in spring,
## grown in summer by the rain (a normal year about one, a drought less), a
## summer storm flattening half, brought in in autumn as harvest x level x
## growth food, roots in winter; no farmer in spring: no crop; away in
## autumn: it rots; a field at level 2 gives twice; a field with no farmer
## gets a newcomer after growth_days; the crop saved and loaded.
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
	_check(towns.residents(TOWN).size() == 1, "and only one")


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
