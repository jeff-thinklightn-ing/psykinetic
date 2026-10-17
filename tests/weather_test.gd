extends Node
## The weather on the world clock (Weather, decisions 307 and 308): each
## spell's kind is the same however often it is asked, and follows the
## region's climate; a change is blended; the console's override comes in
## and goes out over a change; a level's region is a lore region; outdoors
## the weather dims the sky's light and cuts sight and hearing, not under a
## roof and not indoors; climates.json names only lore regions. How it
## looks (decision 309): cloud greys the sky and takes the sun, fog
## thickens the haze, and the drawn weather eases toward the sim's. In
## the towns (decision 384): storms and rain between two steps, and storms
## breaking roofs, the same ones on a replay.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

var _failures := 0


func _ready() -> void:
	DayNight.reset()
	Weather.reload()
	World.steps = 0
	_test_schedule()
	_test_override()
	_test_regions()
	_test_in_the_field()
	_test_climates_file()
	_test_view()
	_test_between()
	_test_roofs()
	Weather.reload()
	DayNight.reset()
	World.steps = 0
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_schedule() -> void:
	print("\n== spells on the clock, by the climate ==")
	Weather.use({"default": {"weights": {"clear": 1}}, "foggy": {"spell": 0.25, "change": 0.1, "weights": {"fog": 9, "clear": 1}},
		"mixed": {"weights": {"clear": 1, "rain": 1, "storm": 1}}})
	var same := true
	for spell in 50:
		if Weather.kind_of("mixed", spell) != Weather.kind_of("mixed", spell):
			same = false
	_check(same, "a spell's kind is the same however often it is asked")
	var fog := 0
	var kinds := {}
	for spell in 400:
		if Weather.kind_of("foggy", spell) == "fog":
			fog += 1
		kinds[Weather.kind_of("mixed", spell)] = true
	_check(fog > 320 and fog < 400, "a climate weighted 9 to 1 for fog is mostly fog (%d of 400)" % fog)
	_check(kinds.size() == 3, "an even climate has every kind it names (%s)" % [kinds.keys()])
	_check(Weather.kind_of("nowhere", 3) == "clear", "a region with no climate has the default's")
	var spell := Weather.spell_steps("foggy")
	_check(spell == DayNight.day_steps / 4, "a spell is a quarter day (%d steps)" % spell)
	# Find a change from clear to fog and look at it.
	var index := 1
	while not (Weather.kind_of("foggy", index - 1) == "clear" and Weather.kind_of("foggy", index) == "fog"):
		index += 1
	var start: Dictionary = Weather.at("foggy", index * spell)
	var middle: Dictionary = Weather.at("foggy", index * spell + spell * 0.05)
	var done: Dictionary = Weather.at("foggy", index * spell + spell * 0.1)
	_check(is_zero_approx(start["fog"]) and middle["fog"] > 0.2 and middle["fog"] < 0.7 and is_equal_approx(done["fog"], Weather.KINDS["fog"]["fog"]),
			"from clear to fog it rolls in over the change (%.2f, %.2f, %.2f)" % [start["fog"], middle["fog"], done["fog"]])
	_check(done["kind"] == "fog" and done["wind_dir"] is Vector2 and is_equal_approx(done["wind_dir"].length(), 1.0),
			"its kind is the spell's, and the wind has a way")


func _test_override() -> void:
	print("\n== the console's override ==")
	Weather.use({"default": {"weights": {"clear": 1}}})
	World.steps = 1000
	Weather.set_override("all", "storm", 10.0)
	var change := Weather.spell_steps("default") * Weather.DEFAULT_CHANGE
	_check(is_zero_approx(Weather.at("default", 1000)["rain"]), "set now, the storm has not begun")
	_check(is_equal_approx(Weather.at("default", 1000 + change)["rain"], 1.0) and Weather.at("default", 1000 + change)["kind"] == "storm",
			"a change on, a full storm")
	var until := 1000 + 10 * 60 * World.TICK_RATE
	_check(is_equal_approx(Weather.at("default", until)["rain"], 1.0) and is_zero_approx(Weather.at("default", until + change)["rain"]),
			"ten minutes on it ends, over a change")
	_check(Weather.live_overrides(until).has("default") and not Weather.live_overrides(until + Weather.spell_steps("default")).has("default"),
			"kept (saved, sent) only while it runs or is ending")
	Weather.set_override("all", "auto", 0.0)
	_check(Weather.overrides.is_empty(), "auto: the climate's again")
	World.steps = 0


func _test_regions() -> void:
	print("\n== a level's region ==")
	var warnings: Array[String] = []
	_check(Level.region_of({}, warnings) == "town_lands" and warnings.is_empty(), "none named: the town's lands, nothing said")
	_check(Level.region_of({"region": "blood_rot_lands"}, warnings) == "blood_rot_lands", "a lore region")
	_check(Level.region_of({"region": "mine"}, warnings) == "town_lands" and warnings.size() == 1,
			"a lore place that is no region is said, and read as the town's lands (%s)" % [warnings])
	var level := Level.parse(Level.image_from_rows(["S."], {}, {}), null, {"region": "blood_rot_lands", "outdoor": true})
	_check(level["terrain"]["region"] == "blood_rot_lands", "Level.parse keeps it in the terrain")


func _test_in_the_field() -> void:
	print("\n== outdoors the weather dims the light and cuts sight and hearing; not under a roof, not indoors ==")
	var floor_cells: Array[Vector2i] = []
	for y in 6:
		for x in 8:
			floor_cells.append(Vector2i(x, y))
	var terrain := {"floor": floor_cells, "fire": [], "edges": {}, "ambient": 0.4, "daylight": true, "outdoor": true,
		"zone": "outdoors", "region": "town_lands", "buildings": [{"slot": "building.hut", "rect": Rect2i(4, 1, 3, 3)}]}
	Weather.use({"default": {"weights": {"clear": 1}}})
	World._set_terrain(terrain)
	DayNight.update()
	_check(is_equal_approx(World.light_at(Vector2i(1, 1), false), 1.0) and World.weather_sight_at(Vector2i(1, 1)) > 0.9,
			"a clear noon: full light, full sight")
	Weather.overrides = {"town_lands": {"kind": "storm", "from": -1000000, "until": 1000000}}
	World.step()
	var light := World.light_at(Vector2i(1, 1), false)
	_check(light < 1.0 and light >= Senses.DARK, "a storm's noon is dimmer, still seen by (%.2f)" % light)
	_check(World.weather_sight_at(Vector2i(1, 1)) < 0.8 and World.weather_hearing_at(Vector2i(1, 1)) < 0.6,
			"and sight and hearing are cut (%.2f, %.2f)" % [World.weather_sight_at(Vector2i(1, 1)), World.weather_hearing_at(Vector2i(1, 1))])
	_check(World.weather_sight_at(Vector2i(5, 2)) == 1.0 and World.weather_hearing_at(Vector2i(5, 2)) == 1.0,
			"under the hut's roof, in the same world, nothing")
	terrain["outdoor"] = false
	terrain["daylight"] = false
	terrain["zone"] = "indoors"
	World._set_terrain(terrain)
	World.step()
	_check(World.weather_sight_at(Vector2i(1, 1)) == 1.0 and is_equal_approx(World.light_at(Vector2i(1, 1), false), 0.4),
			"indoors the storm is nothing")
	Weather.overrides = {}
	World._set_terrain({"floor": floor_cells, "fire": [], "edges": {}})


func _test_climates_file() -> void:
	print("\n== levels/climates.json ==")
	Weather.reload()
	var all := Weather.climates()
	_check(all.has("default"), "it has a default")
	var bad: Array[String] = []
	for region: String in all:
		var entry: Variant = Lore.entries().get(region)
		if region != "default" and not (entry is Dictionary and entry.get("type") == "region"):
			bad.append(region)
		for kind: String in all[region].get("weights", {}):
			if not Weather.KINDS.has(kind):
				bad.append("%s.%s" % [region, kind])
	_check(bad.is_empty(), "every key is a lore region, every weight a kind (%s)" % [bad])
	var fog_town := 0
	var fog_rot := 0
	for spell in 400:
		fog_town += 1 if Weather.kind_of("town_lands", spell) == "fog" else 0
		fog_rot += 1 if Weather.kind_of("blood_rot_lands", spell) == "fog" else 0
	_check(fog_rot > fog_town * 2, "the Blood Rot's land is foggier than the town's (%d to %d of 400)" % [fog_rot, fog_town])


func _test_view() -> void:
	print("
== how it looks ==")
	var noon := Client3D.sky_look(60.0)
	var clear := Client3D.weathered_look(noon, Weather.KINDS["clear"])
	_check(clear["top"] == noon["top"] and is_equal_approx(clear["energy"], noon["energy"]) and is_equal_approx(clear["fog_density"], noon["fog_density"]),
			"clear weather leaves the sky as the hour has it")
	var storm := Client3D.weathered_look(noon, Weather.KINDS["storm"])
	_check(storm["energy"] < noon["energy"] * 0.5 and storm["ambient_energy"] == noon["ambient_energy"],
			"a storm takes the sun's light, not the ambient (%.2f of %.2f)" % [storm["energy"], noon["energy"]])
	_check(storm["top"].s < noon["top"].s * 0.6, "and greys the sky")
	var fog := Client3D.weathered_look(noon, Weather.KINDS["fog"])
	_check(fog["fog_density"] > noon["fog_density"] * 5.0 and fog["fog_height_density"] > 0.0, "fog thickens the haze and lies on the ground")
	var view := WeatherView.new()
	add_child(view)
	view.set_outdoor(true)
	for i in 10:
		view.ease_toward(Weather.KINDS["storm"], 0.1)
	_check(view.weather["rain"] > 0.5 and view.weather["rain"] < 1.0, "the drawn rain eases toward the sim's (%.2f after 1 s)" % view.weather["rain"])
	view.set_outdoor(false)
	_check(not view.ease_toward(Weather.KINDS["storm"], 1.0) and view.weather["rain"] == 0.0 and not view.visible,
			"indoors none is drawn")
	view.free()


func _test_between() -> void:
	print("\n== storms and rain between two steps ==")
	Weather.use({"default": {"weights": {"clear": 1}}, "stormy": {"weights": {"storm": 1}}, "mixed": {"weights": {"clear": 1, "storm": 1}}})
	var spell := Weather.spell_steps("stormy")
	var day := float(DayNight.day_steps)
	_check(Weather.storms_between("default", 0, day * 4).is_empty(), "a clear climate has none")
	var storms := Weather.storms_between("stormy", 0, day)
	_check(storms.size() == 4 and storms[0]["id"] == "storm:stormy:0" and is_equal_approx(storms[0]["at"], spell * 0.5)
			and is_equal_approx(storms[0]["strength"], 1.0), "all storms: four a day, each at its spell's middle, full (%s)" % [storms.slice(0, 1)])
	var halves := Weather.storms_between("stormy", 0, day * 0.5) + Weather.storms_between("stormy", day * 0.5, day)
	_check(halves.map(func(each: Dictionary) -> String: return each["id"]) == storms.map(func(each: Dictionary) -> String: return each["id"]),
			"cut in two, the same storms, each counted once")
	var mixed := Weather.storms_between("mixed", 0, day * 10).size()
	_check(mixed > 8 and mixed < 32, "an even climate: about half its spells (%d of 40)" % mixed)
	World.steps = 1000
	Weather.set_override("default", "storm", 10.0)
	var override := Weather.storms_between("default", 0, 1000 + day)
	_check(override.size() == 1 and str(override[0]["id"]).begins_with("storm:default:override:") and override[0]["strength"] > 0.9,
			"a storm called from the console counts once (%s)" % [override])
	Weather.set_override("default", "auto", 0.0)
	World.steps = 0
	Weather.use({"default": {"weights": {"clear": 1}}, "wet": {"weights": {"rain": 1}}})
	_check(is_zero_approx(Weather.rain_between("default", 0, day)), "a clear day: no rain")
	var wet := Weather.rain_between("wet", 0, day * 2)
	_check(absf(wet - 2.0 * Weather.KINDS["rain"]["rain"]) < 0.01, "two days of rain: two days of it, at rain's strength (%.3f)" % wet)
	var winter := Season.year_anchor + fposmod(0.875 - Season.year_phase, 1.0) * Season.year_steps()
	_check(Weather.rain_between("wet", winter, winter + day) < 0.05, "in midwinter it falls as snow, not counted")
	Weather.reload()


func _test_roofs() -> void:
	print("\n== storms break roofs ==")
	var map := LevelMap.new(Vector2i(24, 24))
	for y in 24:
		for x in 24:
			map.set_cell(Vector2i(x, y), "grass")
	var listed := []
	for y in 10:
		for x in 10:
			listed.append({"rect": [x * 2 + 1, y * 2 + 1, 1, 1]})
	var terrain: Dictionary = Level.parse(map.to_image(), null, {"outdoor": true, "roofs": listed})["terrain"]
	terrain["level"] = "storm_fixture"
	var zone := Zone.new("storm_fixture")
	zone.fields.load(terrain)
	zone.fields.outdoor = true
	World.zones["storm_fixture"] = zone
	var areas := {"storm_fixture": {"roofs": terrain["roofs"], "region": "stormy"}}
	Weather.use({"default": {"weights": {"clear": 1}}, "stormy": {"weights": {"storm": 1}}, "calm": {"weights": {"clear": 1}}})
	var spell := Weather.spell_steps("stormy")
	Weather.storms_checked = -1
	_check(Weather.break_roofs(areas, 100).is_empty() and Weather.storms_checked == 100, "the first check only starts the count")
	var broke := Weather.break_roofs(areas, 100 + spell)
	_check(broke.size() > 10 and broke.size() < 45, "one full storm breaks about a quarter of %d roofs (%d)" % [listed.size(), broke.size()])
	_check(World.damaged_roofs("storm_fixture").size() == broke.size(), "through World.damage_roof")
	var first: Array = World.damaged_roofs("storm_fixture")
	for index in listed.size():
		World.repair_roof("storm_fixture", index)
	Weather.storms_checked = 100
	Weather.break_roofs(areas, 100 + spell)
	_check(World.damaged_roofs("storm_fixture") == first, "a replay breaks the same ones")
	for index in listed.size():
		World.repair_roof("storm_fixture", index)
	areas["storm_fixture"]["region"] = "calm"
	Weather.storms_checked = 100
	_check(Weather.break_roofs(areas, 100 + spell * 8).is_empty(), "no storm, no broken roofs")
	Weather.use({"default": {"weights": {"clear": 1}}, "weak": {"weights": {"rain": 1}}, "stormy": {"weights": {"storm": 1}, "roof_chance": 0.0}})
	areas["storm_fixture"]["region"] = "stormy"
	Weather.storms_checked = 100
	_check(Weather.break_roofs(areas, 100 + spell * 8).is_empty(), "a climate's roof_chance 0: none")
	Weather.use({"default": {"weights": {"clear": 1}}, "stormy": {"weights": {"storm": 1}}})
	Weather.storms_checked = 0
	var long_gap := int(DayNight.day_steps * 30)
	Weather.break_roofs(areas, long_gap)
	var after_gap := World.damaged_roofs("storm_fixture").size()
	_check(after_gap < listed.size() and Weather.storms_checked == long_gap, "a month away counts only the last two days' storms (%d broken)" % after_gap)
	for index in listed.size():
		World.repair_roof("storm_fixture", index)
	World.zones.erase("storm_fixture")
	Weather.reload()


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
