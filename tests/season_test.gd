extends Node
## The seasons on the world clock (Season, decision 362): the year follows
## World.steps and is saved; the sun's path follows it (a winter noon low,
## its days short, the sim's daylight with them); the seasons blend at
## their boundaries; snow falls and lies in the cold, by the region's
## climate; the view's sky takes the season's tint.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

var _failures := 0


func _ready() -> void:
	DayNight.reset()
	Weather.reload()
	World.steps = 0
	_test_year()
	_test_sun()
	_test_blend()
	_test_snow()
	_test_saved()
	_test_look()
	Weather.reload()
	DayNight.reset()
	World.steps = 0
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_year() -> void:
	print("\n== the year on the clock ==")
	_check(Season.name_at(0) == "spring", "a new world starts in spring")
	var season := int(DayNight.day_steps * Season.season_days)
	_check(Season.name_at(season) == "summer" and Season.name_at(season * 2) == "autumn" and Season.name_at(season * 3) == "winter"
			and Season.name_at(season * 4) == "spring", "a season every %d days, the year round" % Season.season_days)
	World.steps = 12345
	Season.set_season("winter")
	_check(Season.name_at(World.steps) == "winter" and is_equal_approx(Season.year_fraction(World.steps), 0.875), "season winter: midwinter now")
	var before := Season.year_fraction(World.steps)
	DayNight.set_day_minutes(5.0)
	_check(is_equal_approx(Season.year_fraction(World.steps), before), "a shorter day keeps the year where it is")
	Season.set_season_days(2)
	_check(is_equal_approx(Season.year_fraction(World.steps), before) and Season.season_days == 2, "so does a shorter season")
	DayNight.reset()
	World.steps = 0


func _test_sun() -> void:
	print("\n== the sun's path by the season ==")
	var summer := Season.DECLINATION
	var winter := -Season.DECLINATION
	var high := DayNight.elevation_at(0.5, summer)
	var low := DayNight.elevation_at(0.5, winter)
	_check(absf(high - 60.0) < 0.01 and absf(low - 30.0) < 0.01, "noon: 60° in midsummer, 30° in midwinter (%.1f, %.1f)" % [high, low])
	var rise_summer := _sunrise(summer)
	var rise_winter := _sunrise(winter)
	_check(rise_summer > 4.5 and rise_summer < 5.5 and rise_winter > 6.5 and rise_winter < 7.5,
			"the sun rises about 5:00 in midsummer, 7:00 in midwinter (%.2f, %.2f)" % [rise_summer, rise_winter])
	_check(DayNight.daylight_at(7.0 / 24.0, winter) < DayNight.daylight_at(7.0 / 24.0, summer),
			"at 7:00 the sim's daylight is dimmer in winter")
	_check(is_equal_approx(DayNight.daylight_at(0.5, winter), 1.0), "a winter noon is still full day")
	World.steps = 0
	Season.set_season("summer")
	_check(is_equal_approx(DayNight.elevation(DayNight.anchor + (0.5 - DayNight.phase) * DayNight.day_steps), 60.0),
			"the clock's sun follows the season it is")
	DayNight.reset()


## The world step at the year's [param at] (fraction), on today's clock.
func _steps_at(at: float) -> float:
	return Season.year_anchor + fposmod(at - Season.year_phase, 1.0) * Season.year_steps()


func _sunrise(tilt: float) -> float:
	var at := 0.0
	while DayNight.elevation_at(at, tilt) < 0.0:
		at += 1.0 / 1440.0
	return at * 24.0


func _test_blend() -> void:
	print("\n== the seasons blend at their boundaries ==")
	var sums_ok := true
	for i in 400:
		var weights := Season.weights(i / 400.0)
		var total := 0.0
		for name: String in Season.NAMES:
			total += weights[name]
		if not is_equal_approx(total, 1.0):
			sums_ok = false
	_check(sums_ok, "the weights always sum to 1")
	var day := 1.0 / (4.0 * Season.season_days)
	var mid := Season.weights(0.125)
	var edge := Season.weights(0.25)
	var near := Season.weights(0.25 - day)
	_check(is_equal_approx(mid["spring"], 1.0), "mid-spring is spring alone")
	_check(is_equal_approx(edge["spring"], 0.5) and is_equal_approx(edge["summer"], 0.5), "at the boundary, half each")
	_check(is_equal_approx(near["spring"], 1.0), "a day before it, spring alone")
	var autumn := Season.at("town_lands", _steps_at(0.625))
	var summer := Season.at("town_lands", _steps_at(0.375))
	_check(autumn["turn"] > 0.9 and summer["turn"] == 0.0 and summer["green"] > autumn["green"], "autumn turns the land, summer is green")


func _test_snow() -> void:
	print("\n== snow in the cold ==")
	Weather.use({"default": {"weights": {"clear": 1}}, "cold_lands": {"cold": 0.3, "weights": {"clear": 1}},
		"warm_lands": {"cold": -0.5, "weights": {"clear": 1}}})
	var midwinter := Season.at("default", _steps_at(0.875))
	var midsummer := Season.at("default", _steps_at(0.375))
	_check(midwinter["snow"] > 0.9 and midsummer["snow"] == 0.0, "snow lies in midwinter, not midsummer (%.2f)" % midwinter["snow"])
	var spring_early := Season.at("default", _steps_at(0.05))
	_check(spring_early["snow"] == 0.0 and Season.at("cold_lands", _steps_at(0.05))["snow"] > 0.0,
			"in early spring the snow is gone, but in a colder region it lies on")
	_check(Season.at("warm_lands", _steps_at(0.875))["snow"] == 0.0, "a warm region has none even in midwinter")
	Weather.overrides = {"default": {"kind": "storm", "from": -100000000, "until": 100000000}}
	var winter_storm := Weather.at("default", _steps_at(0.875))
	var summer_storm := Weather.at("default", _steps_at(0.375))
	_check(winter_storm["snow"] > 0.9 and winter_storm["rain"] < 0.1, "a midwinter storm falls as snow (%.2f)" % winter_storm["snow"])
	_check(summer_storm["snow"] == 0.0 and is_equal_approx(summer_storm["rain"], 1.0), "a summer storm as rain")
	_check(Weather.sight_factor(winter_storm) < Weather.sight_factor(Weather.KINDS["clear"]) and Weather.sight_factor(winter_storm) > Weather.sight_factor(summer_storm),
			"falling snow cuts sight, less than rain")
	_check(Weather.hearing_factor(winter_storm) > Weather.hearing_factor(summer_storm), "and covers less noise")
	Weather.overrides = {}
	Weather.use({"default": {"weights": {"clear": 1}, "seasons": {"winter": {"weights": {"fog": 1}}}}})
	var spell := Weather.spell_steps("default")
	_check(Weather.kind_of("default", int(_steps_at(0.875) / spell)) == "fog" and Weather.kind_of("default", int(_steps_at(0.375) / spell)) == "clear",
			"a climate's winter weights hold in winter only")
	Weather.reload()


func _test_saved() -> void:
	print("\n== the year is saved and sent with the clock ==")
	World.steps = 500
	Season.set_season_days(3)
	Season.set_season("autumn")
	var data := DayNight.to_dict()
	DayNight.reset()
	_check(Season.season_days == Season.DEFAULT_SEASON_DAYS, "reset: the default year")
	DayNight.from_dict(data)
	_check(Season.season_days == 3 and Season.name_at(500) == "autumn" and is_equal_approx(Season.year_fraction(500), 0.625),
			"DayNight.to_dict / from_dict carry it")
	DayNight.reset()
	DayNight.from_dict({"day_steps": 54000, "phase": 0.5, "anchor": 0})
	_check(Season.season_days == Season.DEFAULT_SEASON_DAYS and Season.name_at(0) == "spring", "an old save without it starts in spring")
	DayNight.reset()
	World.steps = 0


func _test_look() -> void:
	print("\n== the view's sky by the season ==")
	var noon := Client3D.sky_look(45.0)
	var winter := Client3D.seasoned_look(noon, {"winter": 1.0, "snow": 1.0})
	var summer := Client3D.seasoned_look(noon, {"summer": 1.0})
	_check(winter["energy"] < noon["energy"] and winter["light"].b / winter["light"].r > noon["light"].b / noon["light"].r, "winter's sun is weaker and cooler")
	_check(winter["ambient_energy"] > noon["ambient_energy"], "snow on the ground lifts the ambient")
	_check(summer["light"].r >= summer["light"].b, "summer's light is warm")
	var spring := Client3D.seasoned_look(noon, {"spring": 1.0})
	_check(spring["light"] == noon["light"] and is_equal_approx(spring["energy"], noon["energy"]), "spring leaves the day as it is")


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
