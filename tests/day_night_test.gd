extends Node
## The day on the world clock (DayNight, decisions 290–292): the hour
## follows World.steps and is saved; the sun rises in the east, stands in
## the south and sets in the west; outdoors, out from under a roof, the
## light field takes the sky's light, NIGHT under the moon, while roofed
## cells and indoor levels keep their own; level.json's "zone" and the older
## "outdoor"; the view's sky blends its keys.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const TestPorts := preload("res://tests/test_ports.gd")

var _failures := 0


func _ready() -> void:
	DayNight.reset()
	_test_clock()
	_test_sun()
	_test_daylight_in_the_field()
	_test_zones()
	_test_saved()
	_test_sky_look()
	DayNight.reset()
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_clock() -> void:
	print("\n== the hour follows the world clock ==")
	World.steps = 0
	_check(is_equal_approx(DayNight.hour(0), 12.0), "a new world starts at noon (%.2f)" % DayNight.hour(0))
	_check(DayNight.day_steps == 90 * 60 * World.TICK_RATE, "a day is 90 minutes of steps by default (%d)" % DayNight.day_steps)
	_check(is_equal_approx(DayNight.hour(DayNight.day_steps / 4.0), 18.0), "a quarter day on, it is 18:00")
	_check(is_equal_approx(DayNight.hour(DayNight.day_steps), 12.0), "a day on, noon again")
	World.steps = 5000
	DayNight.set_hour(6.0)
	_check(is_equal_approx(DayNight.hour(5000), 6.0) and is_equal_approx(DayNight.hour(5000 + DayNight.day_steps / 2.0), 18.0),
			"set_hour(6): 6:00 now, 18:00 half a day on")
	DayNight.set_day_minutes(1.0)
	_check(DayNight.day_steps == 600 and is_equal_approx(DayNight.hour(5000), 6.0),
			"set_day_minutes(1): a day of 600 steps, the hour kept (%.2f)" % DayNight.hour(5000))
	_check(is_equal_approx(DayNight.hour(5150), 12.0), "and a quarter of it on, noon")
	DayNight.reset()
	World.steps = 0


func _test_sun() -> void:
	print("\n== the sun rises in the east, stands south, sets in the west ==")
	var dawn := DayNight.sun_at(0.25 + 0.01)
	var noon := DayNight.sun_at(0.5)
	var dusk := DayNight.sun_at(0.75 - 0.01)
	var midnight := DayNight.sun_at(0.0)
	_check(dawn.x > 0.9 and dawn.y > 0.0, "just after 6:00, low in the east (%s)" % dawn)
	_check(is_equal_approx(DayNight.elevation_at(0.5), DayNight.MAX_ELEVATION) and noon.z > 0.0 and absf(noon.x) < 0.001,
			"at noon, highest, to the south (%s)" % noon)
	_check(dusk.x < -0.9 and dusk.y > 0.0, "just before 18:00, low in the west (%s)" % dusk)
	_check(midnight.y < -0.8, "at midnight, under the world (%s)" % midnight)
	_check(is_equal_approx(DayNight.daylight(0), 1.0), "daylight at noon is 1")
	DayNight.set_hour(0.0)
	_check(is_equal_approx(DayNight.daylight(World.steps), DayNight.NIGHT), "at midnight, NIGHT (%.2f)" % DayNight.daylight(World.steps))
	_check(DayNight.NIGHT > Senses.GLIMPSE and DayNight.NIGHT < Senses.DARK,
			"night outdoors is glimpsed, not seen: GLIMPSE %.2f < %.2f < DARK %.2f" % [Senses.GLIMPSE, DayNight.NIGHT, Senses.DARK])
	# Through the dawn, the light only grows.
	var last := 0.0
	var grows := true
	for minute in range(4 * 60, 9 * 60):
		var light := DayNight.daylight(DayNight.day_steps * (minute / 1440.0 - 0.0))
		if light < last - 0.0001:
			grows = false
		last = light
	_check(grows, "from 4:00 to 9:00 the light only grows")
	DayNight.reset()


func _test_daylight_in_the_field() -> void:
	print("\n== the light field takes the sky's light outdoors, not under a roof ==")
	var floor_cells: Array[Vector2i] = []
	for y in 6:
		for x in 8:
			floor_cells.append(Vector2i(x, y))
	var roofed := Rect2i(4, 1, 3, 3)
	var terrain := {"floor": floor_cells, "fire": [], "edges": {}, "torches": [Vector2i(0, 5)], "ambient": 1.0,
		"daylight": true, "outdoor": true, "zone": "outdoors", "buildings": [{"slot": "building.hut", "rect": roofed}]}
	World._set_terrain(terrain)
	World.steps = 0
	DayNight.update()
	_check(is_equal_approx(World.light_at(Vector2i(7, 5), false), 1.0), "at noon the open ground is fully lit")
	DayNight.set_hour(0.0)
	var open := World.light_at(Vector2i(7, 5), false)
	_check(is_equal_approx(open, DayNight.NIGHT), "at midnight the open ground has the moon's light (%.2f)" % open)
	var inside := World.light_at(Vector2i(5, 2), false)
	_check(is_equal_approx(inside, 1.0), "under the hut's roof, its own light, not the sky's (%.2f)" % inside)
	var by_torch := World.light_at(Vector2i(0, 4), false)
	_check(by_torch >= Senses.DARK, "beside a torch at night, light enough to be seen (%.2f)" % by_torch)
	_check(is_equal_approx(World.light_at(Vector2i(7, 5), false, false), 1.0),
			"without the sky (the view's floor shading), the level's ambient light (%.2f)" % World.light_at(Vector2i(7, 5), false, false))
	# A step on, the field follows with no recompute of its own.
	World.steps += 1
	DayNight.update()
	_check(is_equal_approx(World.light_at(Vector2i(7, 5), false), DayNight.daylight(World.steps)), "a step on, it follows the clock")
	# An indoor level: no sky.
	terrain["daylight"] = false
	terrain["ambient"] = 0.4
	World._set_terrain(terrain)
	_check(is_equal_approx(World.light_at(Vector2i(7, 5), false), 0.4), "an indoor level keeps its ambient light at any hour")
	DayNight.reset()
	World.steps = 0
	DayNight.update()
	World._set_terrain({"floor": floor_cells, "fire": [], "edges": {}})


func _test_zones() -> void:
	print("\n== level.json's zone ==")
	var rows: Array[String] = ["S."]
	var image := Level.image_from_rows(rows, {}, {})
	_check(Level.zone_of({}) == "indoors" and Level.zone_of({"outdoor": true}) == "outdoors"
			and Level.zone_of({"zone": "cave"}) == "cave" and Level.zone_of({"zone": "cave", "outdoor": true}) == "cave",
			"zone_of: no key indoors, \"outdoor\": true outdoors, \"zone\" first")
	var old := Level.parse(image, null, {"outdoor": true})
	_check(old["terrain"]["zone"] == "outdoors" and old["terrain"]["outdoor"] and old["terrain"]["daylight"],
			"\"outdoor\": true still reads as outdoors, lit by the sky")
	var cave := Level.parse(image, null, {"zone": "cave"})
	_check(cave["terrain"]["zone"] == "cave" and not cave["terrain"]["outdoor"] and not cave["terrain"]["daylight"]
			and is_equal_approx(cave["terrain"]["ambient"], DayNight.base_ambient("cave")),
			"a cave: no sky, its kind's ambient light")
	var fixed := Level.parse(image, null, {"zone": "outdoors", "ambient": 0.3})
	_check(fixed["terrain"]["outdoor"] and not fixed["terrain"]["daylight"] and is_equal_approx(fixed["terrain"]["ambient"], 0.3),
			"outdoors with \"ambient\" set: that light, at any hour")
	var bad := Level.parse(image, null, {"zone": "swamp"})
	_check(bad["terrain"]["zone"] == "indoors" and bad["warnings"].any(func(w: String) -> bool: return w.contains("\"zone\"")),
			"an unknown zone is said and read as indoors (%s)" % [bad["warnings"]])
	_check(Level.load_level("castle")["terrain"]["zone"] == "outdoors",
			"the castle is outdoors")


func _test_saved() -> void:
	print("\n== the clock is saved and comes back ==")
	World.steps = 1234
	DayNight.set_day_minutes(30.0)
	DayNight.set_hour(21.5)
	var path := TestPorts.scratch_path("day_night_state.json")
	var zones := {}
	Snapshot.save(path, zones, [], {"steps": World.steps, "sky": DayNight.to_dict()})
	DayNight.reset()
	var loaded := Snapshot.load(path)
	DayNight.from_dict(loaded["sky"])
	_check(DayNight.day_steps == 30 * 60 * World.TICK_RATE and is_equal_approx(DayNight.hour(loaded["steps"]), 21.5),
			"day length and hour as saved (%d steps, %.2f)" % [DayNight.day_steps, DayNight.hour(loaded["steps"])])
	DirAccess.remove_absolute(path)
	DayNight.reset()
	World.steps = 0


func _test_sky_look() -> void:
	print("\n== the view's sky by the sun's height ==")
	var noon := Client3D.sky_look(DayNight.MAX_ELEVATION)
	var night := Client3D.sky_look(-60.0)
	var dawn := Client3D.sky_look(3.0)
	_check(noon["light"] == Client3D.DAY_SUN and noon["ambient"] == Client3D.DAY_AMBIENT, "midday is the day look")
	_check(night["light"].b > night["light"].r and night["energy"] < noon["energy"], "night: a cool blue, dim light")
	_check(dawn["light"].r > dawn["light"].b and dawn["energy"] > 0.0, "dawn: warm gold")
	var at_swap := Client3D.sky_look(Client3D.MOON_BELOW)
	_check(at_swap["energy"] < 0.05, "where the sun hands over to the moon, the light is out, so the swap does not show")


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
