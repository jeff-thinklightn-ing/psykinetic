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
## breaking roofs, the same ones on a replay. Under a forest's canopy
## (decision 477): the sky's light cut by the cover, drips during and after
## rain, the look darker, the shafts by day in clear air.
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
	_test_low_view()
	_test_between()
	_test_roofs()
	_test_canopy()
	_test_night_town()
	_test_mine_light()
	_test_skylights()
	_test_fish_feeding()
	_test_rain_rings()
	_test_rain_at_night()
	_test_roofs_drawn()
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
	_check(is_equal_approx(storm["energy"], noon["energy"] * (1.0 - Client3D.CLOUD_SUN)) and storm["energy"] < noon["energy"] and storm["ambient_energy"] == noon["ambient_energy"],
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
	# The clouds' decal: the view never more than half a period from its
	# middle, the middle on the drift's grid, so moving it shows nothing.
	var period := WeatherView.CLOUD_PERIOD
	var near := true
	var on_grid := true
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 400:
		var target := Vector2(rng.randf_range(-500.0, 500.0), rng.randf_range(-500.0, 500.0))
		var drift := Vector2(rng.randf_range(-300.0, 300.0), rng.randf_range(-300.0, 300.0))
		var middle := WeatherView.cloud_middle(target, drift)
		var away := (middle - target).abs()
		near = near and away.x <= period * 0.5 + 0.001 and away.y <= period * 0.5 + 0.001
		var grid := (middle - drift) / period
		on_grid = on_grid and absf(grid.x - roundf(grid.x)) < 0.001 and absf(grid.y - roundf(grid.y)) < 0.001
	_check(near, "the cloud shadow's decal keeps the view within half a period of its middle")
	_check(on_grid and (WeatherView.CLOUD_TILES - 1) * period * 0.5 >= 30.0,
			"on the drift's grid, its edge %.0f m off the view at least" % ((WeatherView.CLOUD_TILES - 1) * period * 0.5))
	var a := WeatherView.cloud_middle(Vector2(10.0, 0.0), Vector2(35.9, 0.0))
	var b := WeatherView.cloud_middle(Vector2(10.0, 0.0), Vector2(36.1, 0.0))
	_check(absf(a.x - b.x) < 0.5, "the drift wrapping a period moves it smoothly (%.2f to %.2f)" % [a.x, b.x])


## The low camera (623, environment's side): the haze scaled so the aim
## reads as in ortho, the horizon toward the haze's colour, the rain, fog
## and clouds sized for the view; ortho exactly as before.
func _test_low_view() -> void:
	print("\n== under the low camera ==")
	var noon := Client3D.sky_look(60.0)
	var storm := Client3D.weathered_look(noon, Weather.KINDS["storm"])
	var base := float(storm["fog_density"]) - float(storm["fog_weather"])
	var weather := float(storm["fog_weather"])
	var near := Client3D.CAMERA_DISTANCE * Client3D.LOW_DISTANCE_SHARE
	var low := Client3D.hazed_density(base, weather, true, near)
	_check(is_equal_approx(Client3D.hazed_density(base, weather, false, near), storm["fog_density"]) and weather > 0.0,
			"ortho's haze is the look's, as ever")
	# Through the weather's share alone, the aim as far off as ortho's.
	_check(is_equal_approx(low * near, weather * Client3D.CAMERA_DISTANCE),
			"under the low camera the storm's haze to the aim reads as ortho's (%.4f over %.0f, %.4f over %.0f)" % [low, near, weather, Client3D.CAMERA_DISTANCE])
	_check(is_equal_approx(Client3D.hazed_density(base, weather, true, 8.0), low) and Client3D.hazed_density(base, weather, true, near * 2.0) < low,
			"zoomed in nearer than the rest, the storm's haze no thicker; further out, thinner")
	var clear := Client3D.weathered_look(noon, Weather.KINDS["clear"])
	_check(is_zero_approx(Client3D.hazed_density(clear["fog_density"], clear["fog_weather"], true, near)),
			"clear air: no haze but the low camera's depth haze")
	# 623 amended (3): depth haze, clear to LOW_CLEAR, full at LOW_EDGE;
	# the weather pulls both in, a fog or storm's clear stretch gone.
	var calm := Client3D.low_haze(0.0)
	var foggy := Client3D.low_haze(Client3D.hazed_density(0.0, float(Client3D.weathered_look(noon, Weather.KINDS["fog"])["fog_weather"]), true, near))
	var stormy := Client3D.low_haze(low)
	_check(is_equal_approx(calm.x, Client3D.LOW_CLEAR) and is_equal_approx(calm.y, Client3D.LOW_EDGE)
			and foggy.y < calm.y * 0.6 and foggy.x < 10.0 and stormy.y < Client3D.LOW_EDGE and stormy.x < calm.x,
			"the low haze: clear to %.0f m, full at %.0f; in fog %.0f to %.0f; in a storm %.0f to %.0f" % [calm.x, calm.y, foggy.x, foggy.y, stormy.x, stormy.y])
	_check(is_equal_approx(Client3D.low_dusk(2.0), 1.0) and is_equal_approx(Client3D.low_dusk(-3.0), 1.0)
			and is_zero_approx(Client3D.low_dusk(60.0)) and is_zero_approx(Client3D.low_dusk(-30.0))
			and Client3D.low_dusk(10.0) > 0.0 and Client3D.low_dusk(10.0) < 1.0,
			"dusk's lift under the low camera: whole near the horizon, none at noon or deep night, easing between")
	var grey := Client3D.hazed_horizon(storm, Weather.KINDS["storm"])
	_check(Client3D.hazed_horizon(clear, Weather.KINDS["clear"]) == clear["horizon"] and grey.is_equal_approx(storm["fog"]),
			"the horizon: the sky's in clear air, the haze's colour in a storm")
	var view := WeatherView.new()
	add_child(view)
	view.set_outdoor(true)
	for i in 30:
		view.ease_toward(Weather.KINDS["storm"], 0.1)
	var rain := view._rain
	var ortho_box := view._rain_process.emission_box_extents
	var ortho_drops := rain.amount
	var ortho_size := (view._fog[0].mesh as PlaneMesh).size
	var ortho_clouds := view._clouds.size
	var target := Vector3(100.0, 0.0, 100.0)
	view.set_view(true, Vector3(100.0, 8.0, 120.0), Vector2(0.0, -1.0))
	view.place(target, 0.1, Color.GRAY, 1.0, func(way: Vector3) -> Vector3: return way)
	var box := view._rain_process.emission_box_extents * 2.0
	var middle := rain.global_position
	var deep := rain.global_transform.basis.z
	_check(box.z > box.x and box.z >= WeatherView.LOW_BOX.z and rain.amount <= roundi(WeatherView.RAIN_DROPS * WeatherView.LOW_DROPS) and rain.amount > ortho_drops,
			"the rain's box runs deep along the view, its drops more but at most %.1f times" % WeatherView.LOW_DROPS)
	_check(absf(deep.dot(Vector3(0.0, 0.0, -1.0))) > 0.99 and middle.z < 120.0 - WeatherView.LOW_BOX.z * 0.4 and absf(middle.x - 100.0) < 0.01,
			"from the camera out ahead (its middle at %.0f, %.0f)" % [middle.x, middle.z])
	var plane := (view._fog[0].mesh as PlaneMesh).size
	var fog_at := view._fog[0].global_position
	_check(plane.x >= ortho_size.x * WeatherView.LOW_FOG_WIDE - 0.01 and fog_at.z < target.z - 10.0
			and view._fog_material[0].get_shader_parameter("rim") == 1.0,
			"the fog's layers %.0f m wide, ahead of the aim, faded to their rims" % plane.x)
	_check(range(3).all(func(i: int) -> bool: return view._fog[i].visible and float(view._fog_material[i].get_shader_parameter("shown")) == 1.0),
			"the eye well over the fog: every layer shows")
	view.set_view(true, Vector3(100.0, 1.7, 120.0), Vector2(0.0, -1.0))
	view.place(target, 0.1, Color.GRAY, 1.0, func(way: Vector3) -> Vector3: return way)
	var shown: Array = range(3).map(func(i: int) -> float: return float(view._fog_material[i].get_shader_parameter("shown")) if view._fog[i].visible else 0.0)
	_check(shown[0] == 1.0 and shown[1] > 0.5 and shown[1] < 1.0 and shown[2] == 0.0 and not view._fog[2].visible,
			"the eye 1.7 m up: the low layer whole, the middle fading, the one over the eye gone (%s)" % [shown])
	var code := WeatherView.FOG_SHADER
	_check(range(3).all(func(i: int) -> bool: return float(view._fog_material[i].get_shader_parameter("soft")) == WeatherView.FOG_SOFT)
			and WeatherView.FOG_SOFT > 0.0 and code.contains("hint_depth_texture") and not code.contains("sin("),
			"the fog thins against what stands in it (depth fade over %.2f m of height) and its noise has no sin hash" % WeatherView.FOG_SOFT)
	_check(view._clouds.size.x == WeatherView.CLOUD_PERIOD * WeatherView.LOW_CLOUD_TILES and (view._clouds.texture_albedo as ImageTexture).get_width() == 128 * WeatherView.LOW_CLOUD_TILES,
			"the clouds' decal %.0f m wide" % view._clouds.size.x)
	view.set_view(false, Vector3(100.0, 30.0, 130.0), Vector2(-0.7, -0.7))
	view.place(target, 0.1, Color.GRAY, 1.0, func(way: Vector3) -> Vector3: return way)
	_check(view._rain_process.emission_box_extents == ortho_box and rain.amount == ortho_drops and rain.global_basis.is_equal_approx(Basis.IDENTITY)
			and (view._fog[0].mesh as PlaneMesh).size == ortho_size and view._fog_material[0].get_shader_parameter("rim") == 0.0
			and view._fog[0].global_position.x == target.x and view._clouds.size == ortho_clouds and view._roofs.follow_camera_enabled
			and view._fog[2].visible and float(view._fog_material[2].get_shader_parameter("shown")) == 1.0,
			"back in ortho, all as it was")
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


func _test_canopy() -> void:
	print("
== under a forest's canopy ==")
	Weather.use({"default": {"weights": {"clear": 1}}})
	World.steps = 0
	var fields := Fields.new()
	fields.daylight = true
	fields.outdoor = true
	fields.canopy = {Vector2i(1, 0): 1.0, Vector2i(2, 0): 0.5}
	fields.canopy_kind = "evergreen"
	fields.update_weather(0)
	DayNight.light = 1.0
	var roof := fields.ambient_at(Vector2i(1, 0))
	_check(is_equal_approx(fields.ambient_at(Vector2i(0, 0)), 1.0), "a clearing has the full sky")
	_check(absf(roof - 0.44) < 0.01 and roof > Senses.DARK, "noon under a full roof: about 0.44, not dark (%.2f)" % roof)
	_check(fields.ambient_at(Vector2i(2, 0)) > roof and fields.ambient_at(Vector2i(2, 0)) < 1.0, "half cover, between")
	DayNight.light = 0.6
	_check(fields.ambient_at(Vector2i(1, 0)) < Senses.DARK and fields.ambient_at(Vector2i(0, 0)) > Senses.DARK,
			"in the morning's light it is dark under the roof, not in the clearing")
	DayNight.light = DayNight.NIGHT
	_check(is_equal_approx(fields.ambient_at(Vector2i(1, 0)), DayNight.NIGHT), "at night the roof makes it no darker than night")
	DayNight.light = 1.0
	var winter := Season.year_anchor + fposmod(0.875 - Season.year_phase, 1.0) * Season.year_steps()
	_check(is_equal_approx(DayNight.canopy_shade("evergreen", "default", winter), DayNight.CANOPY_SHADE)
			and DayNight.canopy_shade("broadleaf", "default", winter) < DayNight.CANOPY_SHADE * 0.6
			and DayNight.canopy_shade("", "default", 0) == 0.0, "an evergreen roof is as dark in winter; a broadleaf one lets light in; none none")
	# Drips: during the rain, then fading by the cover.
	Weather.set_override("default", "rain", 2.0, true)
	_check(is_equal_approx(Weather.drip_at("default", 600, 0.8), 0.8) and Weather.drip_at("default", 600, 0.0) == 0.0,
			"while it rains a roof drips as its cover; the open none")
	var dry := 1200
	while float(Weather.at("default", dry)["rain"]) >= Weather.DRIP_RAIN:
		dry += 10
	var full := Weather.drip_at("default", dry + 300, 1.0)
	var half := Weather.drip_at("default", dry + 300, 0.5)
	_check(absf(full - (1.0 - 30.0 / 90.0)) < 0.06, "30 s after the rain a full roof still drips (%.2f)" % full)
	_check(absf(half - 0.5 * (1.0 - 30.0 / 45.0)) < 0.06, "half a roof drips half as long (%.2f)" % half)
	_check(Weather.drip_at("default", dry + 1000, 1.0) == 0.0, "100 s after, none")
	Weather.set_override("default", "auto", 0.0)
	Weather.use({"default": {"weights": {"clear": 1}}, "wet": {"weights": {"rain": 1}}})
	_check(Weather.drip_at("wet", winter, 1.0) == 0.0, "snow does not drip")
	# The look and the shafts.
	var noon := Client3D.sky_look(60.0)
	var under := Client3D.canopied_look(noon, 1.0)
	_check(under["ambient_energy"] < noon["ambient_energy"] * 0.5 and under["ambient"].g > under["ambient"].b
			and under["energy"] == noon["energy"], "under the roof the ambient darker and greener; the sun's left to the crowns' shadows")
	_check(Client3D.canopied_look(noon, 0.0) == noon, "no canopy, no change")
	var dusk_under := Client3D.canopied_look(noon, 1.0, Client3D.LOW_DUSK_CANOPY)
	_check(is_equal_approx(dusk_under["ambient_energy"], float(noon["ambient_energy"]) * (1.0 - Client3D.LOW_DUSK_CANOPY))
			and dusk_under["ambient_energy"] > under["ambient_energy"],
			"at dusk under the low camera the canopy cuts the ambient less (623 amended (3))")
	var LightShafts := preload("res://client3d/light_shafts.gd")
	var clear: float = LightShafts.strength_for(1.0, Weather.KINDS["clear"])
	_check(clear > 0.5 and LightShafts.strength_for(0.0, Weather.KINDS["clear"]) == 0.0
			and LightShafts.strength_for(1.0, Weather.KINDS["rain"]) == 0.0, "shafts by day in clear air; none at night or in rain")
	_check(LightShafts.strength_for(1.0, {"fog": 0.3}) > clear and LightShafts.strength_for(1.0, Weather.KINDS["fog"]) < 0.1,
			"light haze shows them best, thick fog hides them")
	var canopy := {}
	for y in 30:
		for x in 30:
			canopy[Vector2i(x, y)] = 1.0
	canopy[Vector2i(20, 20)] = 0.3
	canopy[Vector2i(21, 20)] = 0.6
	var shafts: Node3D = LightShafts.new()
	add_child(shafts)
	shafts.setup([{"centre": Vector2(6, 6), "radius": 5.0}], canopy, func(cell: Vector2i) -> Vector3: return Vector3(cell.x, 0.0, cell.y))
	_check(shafts.spot_count() == 3 + 1, "three in a clearing, one in the gap (%d)" % shafts.spot_count())
	shafts.place(Vector3(10, 0, 10), Vector3(0.3, 0.8, 0.2), 1.0)
	var shown := shafts.get_children().filter(func(each: Node) -> bool: return each.visible).size()
	_check(shown == 4, "by day all four hang (%d)" % shown)
	shafts.place(Vector3(10, 0, 10), Vector3(0.95, 0.1, 0.0), 1.0)
	_check(shafts.get_children().all(func(each: Node) -> bool: return not each.visible), "the sun low: none")
	shafts.free()
	Weather.reload()
	World.steps = 0


## Skylights (797): read from level.json, the cells lit, Fields' light there
## by day and night, the client's look.
func _test_skylights() -> void:
	print("
== skylights ==")
	var warnings: Array[String] = []
	var read := Level.skylights_from({"skylights": [{"at": [5, 6], "radius": 9}, {"at": [1]}]}, warnings)
	_check(read.size() == 1 and read[0]["at"] == Vector2i(5, 6) and read[0]["radius"] == Level.SKYLIGHT_RADIUS.y and warnings.size() == 1,
			"a skylight read, its radius capped; a bad one left out and said")
	var cells := Level.skylit_cells([{"at": Vector2i(0, 0), "radius": 2.0}])
	_check(cells[Vector2i(0, 0)] == 1.0 and cells[Vector2i(1, 0)] == 1.0 and is_equal_approx(cells[Vector2i(2, 0)], Level.SKYLIGHT_EDGE)
			and not cells.has(Vector2i(2, 2)), "full under the gap, fading to its edge, none past it")
	_check(Fields.skylight_at(1.0, DayNight.NIGHT) >= Fields.SKYLIGHT_NIGHT and Fields.skylight_at(1.0, 1.0) > Fields.skylight_at(1.0, DayNight.NIGHT)
			and Fields.skylight_at(0.5, 1.0) < Fields.skylight_at(1.0, 1.0), "the sky's light through the gap: faint at night, never out")
	var fields := Fields.new()
	fields.load({"ambient": 0.03, "zone": "cave", "skylights": [{"at": Vector2i(4, 4), "radius": 2.0}]})
	var was := DayNight.light
	DayNight.light = 1.0
	var under := fields.ambient_at(Vector2i(4, 4))
	var away := fields.ambient_at(Vector2i(9, 9))
	DayNight.light = was
	_check(under > 0.5 and is_equal_approx(away, 0.03), "Senses' light: the gap's by day, the cave's away from it (%.2f, %.2f)" % [under, away])
	fields.load({"outdoor": true, "skylights": [{"at": Vector2i(4, 4), "radius": 2.0}]})
	_check(fields.skylit.is_empty(), "none outdoors")
	var night: Array = Client3D.skylight_look(DayNight.NIGHT)
	var day: Array = Client3D.skylight_look(1.0)
	_check(float(night[0]) > 0.0 and is_equal_approx(float(day[0]), Client3D.SKYLIGHT_ENERGY) and (night[1] as Color).b > (night[1] as Color).r,
			"the view: bluer and faint at night, full by day")
	# 797 amended: a cave's mouth. A corridor x 0..6 on row 2,
	# a wall at x 3 on row 4 apart from a side passage row 4 x 4..6 joined
	# only at x 6: the mouth's light walks the floor, never through the wall.
	var floor: Array = []
	for x in range(0, 7):
		floor.append(Vector2i(x, 2))
	for x in range(4, 7):
		floor.append(Vector2i(x, 4))
	floor.append(Vector2i(6, 3))
	floor.append(Vector2i(2, 3))
	floor.append(Vector2i(2, 4))
	warnings.clear()
	var mouths := Level.mouths_from({"mouths": [{"at": [0, 2], "reach": 20}, {"at": [9, 9]}, {"at": [9]}]}, floor, warnings)
	_check(mouths.size() == 1 and mouths[0]["toward"] == Vector2i(1, 0) and mouths[0]["reach"] == Level.MOUTH_REACH.y and warnings.size() == 2,
			"a mouth read, its way in found from the floor, its reach capped; one with no floor or a bad entry left out and said (%s)" % [warnings])
	var lit := Level.mouth_cells([{"at": Vector2i(0, 2), "toward": Vector2i(1, 0), "reach": 4}], floor)
	_check(lit[Vector2i(0, 2)] == 1.0 and lit[Vector2i(1, 2)] == 1.0 and is_equal_approx(lit[Vector2i(4, 2)], Level.MOUTH_EDGE)
			and not lit.has(Vector2i(5, 2)) and lit.has(Vector2i(2, 4)) and not lit.has(Vector2i(4, 4)),
			"full at the mouth, fading to its reach along the floor, round a corner, not through a wall (%s)" % [lit])
	fields.load({"ambient": 0.03, "zone": "cave", "floor": floor, "mouths": [{"at": Vector2i(0, 2), "toward": Vector2i(1, 0), "reach": 4}]})
	DayNight.light = 1.0
	var inside := fields.ambient_at(Vector2i(1, 2))
	DayNight.light = DayNight.NIGHT
	var dark := fields.ambient_at(Vector2i(1, 2))
	DayNight.light = was
	_check(inside > 0.5 and dark >= Fields.SKYLIGHT_NIGHT and dark < inside and is_equal_approx(fields.ambient_at(Vector2i(6, 4)), 0.03),
			"Senses' light at the mouth: the day's, faint at night; the cave's past its reach (%.2f, %.2f)" % [inside, dark])


## The mine's light (769 amended (6)): a level's own ambient as a share of
## its zone's, the wall lamp's flame where the piece hangs, the nearest lit.
func _test_mine_light() -> void:
	print("\n== the mine's light ==")
	_check(is_equal_approx(Client3D.ambient_share({"zone": "indoors", "ambient": 0.03}), 0.075)
			and Client3D.ambient_share({"zone": "cave", "ambient": DayNight.base_ambient("cave")}) == 1.0
			and Client3D.ambient_share({"zone": "dungeon"}) == 1.0 and Client3D.ambient_share({"zone": "dungeon", "ambient": 0.9}) == 1.0,
			"a level's own ambient is that share of its zone's (0.03 indoors: 0.075), unset or brighter 1")
	var decor := [{"cell": Vector2i(3, 4), "out": Vector2i(0, -1), "kind": "mine_arch"},
		{"cell": Vector2i(5, 4), "out": Vector2i(1, 0), "kind": "mine_lamp"}]
	_check(Client3D.wall_lamp_out(decor, Vector2i(5, 4)) == Vector2i(1, 0) and Client3D.wall_lamp_out(decor, Vector2i(3, 4)) == Vector2i.ZERO,
			"a lantern cell with a mine_lamp row hangs on its wall; an arch's carries none")
	var flame := Client3D.wall_lamp_flame(Vector2i(5, 4), Vector2i(1, 0), 2.0)
	var row: Dictionary = Level.DECOR_KINDS["mine_lamp"]
	var wall_x := 5.0 + 0.5 - float(row["inset"])
	_check(absf(flame.x - wall_x) < 0.1 and absf(flame.z - 4.0) < 0.05 and flame.y > 2.0 + float(row["lift"]) and flame.y < 2.0 + float(row["lift"]) + 0.4,
			"the flame burns in the lantern hung on the wall, lifted (%s)" % [flame])
	# 769 amended (8): the light stands off the wall into the passage, lower.
	var lamp := Client3D.wall_lamp_light(flame, Vector2i(1, 0))
	_check(is_equal_approx(flame.x - lamp.x, Client3D.WALL_LAMP_OFF) and is_equal_approx(lamp.z, flame.z)
			and is_equal_approx(flame.y - lamp.y, Client3D.WALL_LAMP_DROP) and Client3D.WALL_LAMP_RANGE >= 7.0,
			"the lamp's light stands %.1f m off the wall, %.1f m under the flame, reaching %.0f m (%s)" % [Client3D.WALL_LAMP_OFF, Client3D.WALL_LAMP_DROP, Client3D.WALL_LAMP_RANGE, lamp])
	var lights: Array[OmniLight3D] = []
	for x: int in [9, 1, 5, 20]:
		var light := OmniLight3D.new()
		light.position = Vector3(x, 0.0, 0.0)
		lights.append(light)
	var near := Client3D.nearest_lights(lights, Vector2(4.0, 0.0), 2)
	_check(near.size() == 2 and near[0] == lights[2] and near[1] == lights[1], "the nearest lamps to the camera's aim are lit")
	for light: OmniLight3D in lights:
		light.free()


## The night town (782): fire pools by cluster, door lanterns' place, who
## carries a lantern, Main's night places, the nearest carriers lit.
func _test_night_town() -> void:
	print("
== the night town ==")
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 1), Vector2i(5, 5), Vector2i(6, 5), Vector2i(9, 0)]
	var clusters := Client3D.fire_clusters(cells)
	_check(clusters.size() == 3 and clusters[0].size() == 2 and clusters[1].size() == 2 and clusters[2] == [Vector2i(9, 0)],
			"fire cells touching (side or corner) make one pool: 5 cells, 3 clusters")
	var at := Client3D.door_lamp_at(Vector3(10.0, 0.0, 10.0), Vector2i(0, 1))
	_check(is_equal_approx(at.z, 10.0 - 0.5 + Client3D.DOOR_LAMP_OUT) and is_equal_approx(absf(at.x - 10.0), Client3D.DOOR_LAMP_ASIDE)
			and is_equal_approx(at.y, Client3D.DOOR_LAMP_UP) and Client3D.DOOR_LAMP_OUT > 0.25,
			"a door lantern hangs beside the door, %.2f m proud of its edge (clear of the chapel's 0.5 m wall), %.1f m up" % [Client3D.DOOR_LAMP_OUT, Client3D.DOOR_LAMP_UP])
	var off_wall := Client3D.DOOR_LAMP_OUT + Client3D.DOOR_LAMP_LIGHT.z
	_check(off_wall >= 0.9 and Client3D.DOOR_LAMP_LIGHT.y < 0.0 and Client3D.DOOR_LAMP_LIGHT.y > -1.0,
			"its light stands %.2f m off the wall, under the lantern, so the stone beside it isn't burned white (782 amended)" % off_wall)
	# Art-kit's lantern (489 amended (4)) keeps it so: its light off its flame.
	var flame: Variant = Flames.socket_of(Client3D.DOOR_LAMP_SLOT)
	var art_light: Vector3 = (flame if flame != null else Vector3(0.57, 1.92, 0.0)) + Client3D.DOOR_LAMP_ART_LIGHT
	_check(art_light.x >= 0.9 and art_light.y < 1.6 and art_light.y > 1.3 and Client3D.HOUSE_DOOR_LAMP_ENERGY < Client3D.DOOR_LAMP_ENERGY
			and Client3D.HOUSE_DOOR_LAMP_RANGE == 3.5,
			"art-kit's lantern's light %.2f m off the wall, %.2f m up; a house's dimmer and shorter than a trade's (environment)" % [art_light.x, art_light.y])
	var buildings := [{"rect": Rect2i(0, 0, 4, 6), "facing": Vector2i(0, 1)}, {"rect": Rect2i(10, 0, 3, 3), "facing": Vector2i(1, 0)}]
	_check(Client3D.building_holding(buildings, Vector2i(11, 1)) == buildings[1] and Client3D.building_holding(buildings, Vector2i(7, 1)).is_empty(),
			"a counter's building is the one whose rect holds it; none in the open")
	_check(Client3D.carries_lantern(true, "", false, 0.5, ""), "a townsperson walking out of doors at night carries a lantern")
	_check(not Client3D.carries_lantern(false, "", false, 0.5, ""), "not by day")
	_check(not Client3D.carries_lantern(true, "", true, 0.5, ""), "not indoors")
	_check(not Client3D.carries_lantern(true, "sleep", false, 0.5, ""), "not asleep")
	_check(not Client3D.carries_lantern(true, "", false, Client3D.CARRIED_HOLD + 1.0, ""), "not standing about (walkers only, the coordinator)")
	_check(not Client3D.carries_lantern(true, "", false, 0.5, "shield"), "not with the left hand full")
	var places := {"post_a": {"kind": "post", "cell": Vector2i(1, 1), "brazier": [3, 4]},
		"post_b": {"kind": "post", "cell": Vector2i(1, 1), "rect": Rect2i(10, 10, 3, 3)},
		"store": {"kind": "stockpile", "cell": Vector2i(5, 5)}, "well": {"kind": "other", "cell": Vector2i(2, 2)}}
	var night := Main.night_places(places)
	var posts: Array = night[0]
	var stores: Array = night[1]
	_check(posts.size() == 2 and Vector2i(3, 4) in posts and Vector2i(11, 11) in posts,
			"a post's brazier at its \"brazier\" cell, else its rect's middle")
	_check(stores.size() == 1 and stores[0][0] == Vector2i(5, 5) and stores[0][1] == Vector2(5, 5) + Main.NIGHT_STORE_ASIDE,
			"the store's lantern post beside its cell (no \"lamp\" given)")
	places["store"]["lamp"] = [7, 8]
	_check((Main.night_places(places)[1] as Array)[0][1] == Vector2(7, 8), "or at its \"lamp\" cell")
	var carriers := {}
	var made: Array[Node3D] = []
	for i in 6:
		var lantern := Node3D.new()
		add_child(lantern)
		lantern.global_position = Vector3(float(i) * 3.0, 0.0, 0.0)
		lantern.visible = i != 1
		carriers[i] = lantern
		made.append(lantern)
	var near := Client3D.nearest_carriers(carriers, Vector2(0.0, 0.0), Client3D.CARRIED_NEAR)
	_check(near.size() == Client3D.CARRIED_NEAR and near[0] == carriers[0] and near[1] == carriers[2] and not carriers.has(1),
			"the %d carriers nearest the camera light the ground, nearest first; a lantern put away drops out" % Client3D.CARRIED_NEAR)
	var own: Node3D = made[5]
	var with := Client3D.with_own(near, own, Client3D.CARRIED_NEAR)
	_check(with.size() == Client3D.CARRIED_NEAR and with[0] == own and with[1] == near[0] and not near[near.size() - 1] in with
			and Client3D.with_own(near, near[2], Client3D.CARRIED_NEAR) == near and Client3D.with_own(near, null, Client3D.CARRIED_NEAR) == near,
			"the followed player's aura is always lit: put first if it was left out, the farthest dropped (789)")
	for lantern in made:
		lantern.free()
	_check(Client3D.aura_glow(0.34) == Vector2(Client3D.AURA_REACH.x, Client3D.AURA_ENERGY.x) and Client3D.aura_glow(1.0) == Vector2(Client3D.AURA_REACH.y, Client3D.AURA_ENERGY.y)
			and Client3D.aura_glow(0.67).x > Client3D.AURA_REACH.x and Client3D.aura_glow(0.67).x < Client3D.AURA_REACH.y and Client3D.AURA_REACH == Vector2(3.0, 6.0),
			"an aura's light: 3 m at 0.35 (and the least aura, 1/3) to 6 m at 1, growing between (789)")
	_check(Client3D.aura_shows(0.34, true, true) and Client3D.aura_shows(0.34, false, false) and not Client3D.aura_shows(0.34, false, true) and not Client3D.aura_shows(0.0, true, false),
			"an aura shows after sunset or under a roof, never by day in the open, never with none")
	_check(Client3D.aura_motes(0.0) == 0 and Client3D.aura_motes(0.33) == 5 and Client3D.aura_motes(0.5) == 8 and Client3D.aura_motes(1.0) == 16
			and Client3D.aura_motes(0.01) == 1,
			"an aura's motes: none with none, 5 for a new charm, 8 at a half, 16 at full, one at the least (789 amended)")
	_check(is_equal_approx(Client3D.aura_mote_glow(1.0, true), Client3D.AURA_MOTE_GLOW * Client3D.AURA_MOTE_DAY)
			and is_equal_approx(Client3D.aura_mote_glow(0.0, true), Client3D.AURA_MOTE_GLOW)
			and is_equal_approx(Client3D.aura_mote_glow(1.0, false), Client3D.AURA_MOTE_GLOW),
			"the motes faint by day in the open, full at night or under a roof (789 amended)")


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


## Fish feeding (805 amended (10), "fish rise"): keenest about dawn and dusk,
## low at midday and night, raised by rain but not a storm; the wait for a
## bite only ever comes sooner, and at feeding 0 it is exactly 805's.
func _test_fish_feeding() -> void:
	print("
== fish feeding: dawn, dusk and rain bring the bite sooner (805 amended (10)) ==")
	Weather.use({"default": {"weights": {"clear": 1}}, "wet": {"weights": {"rain": 1}}, "wild": {"weights": {"storm": 1}}})
	var at_hour := func(hour: float) -> float:
		return fposmod((hour / 24.0 - DayNight.phase) * DayNight.day_steps, float(DayNight.day_steps)) + DayNight.anchor
	# Sunrise and sunset today: where the sun crosses the horizon.
	var rise := -1.0
	var sets := -1.0
	for i in 24 * 60:
		var a := DayNight.elevation(at_hour.call(i / 60.0))
		var b := DayNight.elevation(at_hour.call((i + 1) / 60.0))
		if a < 0.0 and b >= 0.0:
			rise = i / 60.0
		elif a >= 0.0 and b < 0.0:
			sets = i / 60.0
	var keen := {}
	for hour: float in [rise, sets, 12.0, 0.0, 3.0, 23.0]:
		keen[hour] = Weather.fish_feeding("default", at_hour.call(hour))
	_check(is_equal_approx(DayNight.hour(at_hour.call(6.5)), 6.5), "the clock read back at the hour asked (%.2f)" % DayNight.hour(at_hour.call(6.5)))
	_check(rise > 3.0 and sets > rise and keen[rise] > 0.95 and keen[sets] > 0.95,
			"keenest at sunrise %.2f h and sunset %.2f h (%.2f, %.2f)" % [rise, sets, keen[rise], keen[sets]])
	# The year's longest and shortest days (whole days on, so the hours line
	# up): the peak sits at their sunrise and sunset, which move with the season.
	var days := maxi(roundi(Season.year_steps() / DayNight.day_steps), 1)
	var longest := 0
	var shortest := 0
	for d in days:
		var tilt := Season.declination(at_hour.call(12.0) + d * DayNight.day_steps)
		if tilt > Season.declination(at_hour.call(12.0) + longest * DayNight.day_steps):
			longest = d
		if tilt < Season.declination(at_hour.call(12.0) + shortest * DayNight.day_steps):
			shortest = d
	var edges := {}
	for d: int in [longest, shortest]:
		var on := float(d * DayNight.day_steps)
		var up := -1.0
		var down := -1.0
		for i in 24 * 60:
			var a := DayNight.elevation(at_hour.call(i / 60.0) + on)
			var b := DayNight.elevation(at_hour.call((i + 1) / 60.0) + on)
			if a < 0.0 and b >= 0.0:
				up = i / 60.0
			elif a >= 0.0 and b < 0.0:
				down = i / 60.0
		edges[d] = [up, down, Weather.fish_feeding("default", at_hour.call(up) + on), Weather.fish_feeding("default", at_hour.call(down) + on)]
	var summer: Array = edges[longest]
	var winter: Array = edges[shortest]
	_check(winter[0] - summer[0] > 0.5 and summer[2] > 0.95 and summer[3] > 0.95 and winter[2] > 0.95 and winter[3] > 0.95,
			"the peak follows the sun through the year: the longest day's sunrise %.2f h and sunset %.2f h (%.2f, %.2f), the shortest's %.2f and %.2f (%.2f, %.2f)"
			% [summer[0], summer[1], summer[2], summer[3], winter[0], winter[1], winter[2], winter[3]])
	_check(keen[12.0] < 0.3 and keen[3.0] < 0.3 and keen[0.0] < 0.3, "low at midday and at night (%.2f, %.2f, %.2f)" % [keen[12.0], keen[3.0], keen[0.0]])
	var all_in := true
	for i in 96:
		for region: String in ["default", "wet", "wild"]:
			var k := Weather.fish_feeding(region, at_hour.call(i * 0.25))
			all_in = all_in and k >= 0.0 and k <= 1.0
	_check(all_in, "always 0..1, every quarter hour, dry, wet and stormy")
	var noon := at_hour.call(12.0) as float
	var dry := Weather.fish_feeding("default", noon)
	var wet := Weather.fish_feeding("wet", noon)
	var wild := Weather.fish_feeding("wild", noon)
	_check(float(Weather.at("wet", noon)["rain"]) > 0.3, "the wet region rains at noon (%.2f; not snow)" % float(Weather.at("wet", noon)["rain"]))
	_check(wet > dry + 0.3 and absf(wild - dry) < 0.01, "rain raises it (%.2f from %.2f), a storm's downpour doesn't (%.2f)" % [wet, dry, wild])
	_check(World.fish_wait_most(0.0) == World.FISH_WAIT_MOST and World.FISH_WAIT_MOST == 270 and World.FISH_WAIT_LEAST == 120,
			"at feeding 0 the wait is 805's, 120 to 270 ticks: nothing worse for anyone")
	var never_later := true
	for i in 21:
		var most := World.fish_wait_most(i / 20.0)
		never_later = never_later and most <= World.FISH_WAIT_MOST and most >= World.FISH_WAIT_LEAST
	_check(never_later and World.fish_wait_most(1.0) == World.FISH_WAIT_KEEN and World.FISH_WAIT_KEEN < World.FISH_WAIT_MOST,
			"keener, sooner: at most %d at full feeding, never past 270 nor under 120" % World.fish_wait_most(1.0))
	Weather.reload()


# Rain on water (309 amended (2)): the share of the water's drop cells that
# ring, from the drawn rain. A dry day rings none, exactly; a downpour every
# cell; it rises with the rain, so a shower's end thins the rings as the drawn
# rain eases down rather than stopping them at once; indoors none.
func _test_rain_rings() -> void:
	_check(WeatherView.ring_share(0.0) == 0.0 and WeatherView.ring_share(WeatherView.RINGS_FROM) == 0.0,
			"no rain, no rings: the share at rain 0 is exactly 0")
	_check(WeatherView.ring_share(1.0) == 1.0, "a downpour rings every cell")
	var rising := true
	for i in range(1, 21):
		rising = rising and WeatherView.ring_share(i / 20.0) >= WeatherView.ring_share((i - 1) / 20.0)
	var steady := WeatherView.ring_share(Weather.KINDS["rain"]["rain"])
	_check(rising and steady > 0.3 and steady < 1.0, "more rain, more rings (steady rain %.2f)" % steady)
	var view := WeatherView.new()
	add_child(view)
	view.set_outdoor(true)
	var place := func() -> void: view.place(Vector3(100.0, 0.0, 100.0), 0.1, Color.GRAY, 1.0, func(way: Vector3) -> Vector3: return way)
	for i in 30:
		view.ease_toward(Weather.KINDS["storm"], 0.1)
	place.call()
	var storm := view.rings
	var follows := storm == WeatherView.ring_share(view.weather["rain"])
	var after: Array[float] = []
	for i in 6:
		view.ease_toward(Weather.KINDS["clear"], 0.1)
		place.call()
		after.append(view.rings)
	_check(storm > 0.9 and follows,
			"in a storm the water rings nearly everywhere (%.2f)" % storm)
	_check(after[0] < storm and after[0] > 0.0 and after[5] < after[0],
			"as the shower ends the rings thin out with the eased rain (%.2f, %.2f), not all at once" % [after[0], after[5]])
	for i in 60:
		view.ease_toward(Weather.KINDS["clear"], 0.1)
	place.call()
	_check(view.rings == 0.0, "cleared, none")
	view.ease_toward(Weather.KINDS["storm"], 1.0)
	view.set_outdoor(false)
	place.call()
	_check(view.rings == 0.0, "indoors none")
	view.free()
	var code := FileAccess.get_file_as_string("res://client3d/water.gdshader")
	_check(code.contains("global uniform float rain_rings") and not code.contains("sin("),
			"the water reads the rain_rings global, its drops hashed without sin")
	_check(ProjectSettings.has_setting("shader_globals/rain_rings"), "and project.godot declares it")
	_check((load("res://client3d/water.gdshader") as Shader).get_shader_uniform_list().size() > 0,
			"and it compiles (a bad shader lists no uniforms)")
	_check_drops_kept(code)


# 309 amended (5): the drops' own colour by day (emission, nothing lit, as
# before), lit by the scene as the day goes, so at night a drop shows where a
# light catches it, not as a pale pole; the nearest thinned. The day's share
# reaches both drop materials (rain and drips) each frame.
func _test_rain_at_night() -> void:
	var code := WeatherView.DROP_SHADER
	var head := code.substr(0, code.find(";", code.find("render_mode")))
	_check(not head.contains("unshaded") and code.contains("EMISSION = colour.rgb * max(day, night_glow)") and WeatherView.DROP_NIGHT_GLOW > 0.0 and WeatherView.DROP_NIGHT_GLOW < 0.5
			and code.contains("ALBEDO = colour.rgb * (1.0 - day)") and code.contains("BACKLIGHT"),
			"the drops are lit by the scene as the day goes, keep their own colour by day and DROP_NIGHT_GLOW of it at night (%.2f)" % WeatherView.DROP_NIGHT_GLOW)
	_check(code.contains("smoothstep(near_from, near_to, -VERTEX.z)")
			and WeatherView.DROP_NEAR_FROM < WeatherView.DROP_NEAR_TO
			and WeatherView.DROP_NEAR_TO < Client3D.CAMERA_DISTANCE * Client3D.LOW_DISTANCE_SHARE * Client3D.LOW_ZOOM_MIN,
			"the nearest drops thin out, and the player stands beyond the fade at the nearest zoom (%.1f m < %.1f m)" % [
			WeatherView.DROP_NEAR_TO, Client3D.CAMERA_DISTANCE * Client3D.LOW_DISTANCE_SHARE * Client3D.LOW_ZOOM_MIN])
	var view := WeatherView.new()
	add_child(view)
	view.set_outdoor(true)
	view.ease_toward(Weather.KINDS["rain"], 1.0)
	var days := []
	for daylight: float in [1.0, 0.0, 0.4]:
		view.place(Vector3(100.0, 0.0, 100.0), 0.1, Color.GRAY, daylight, func(way: Vector3) -> Vector3: return way)
		var each := []
		for material in view._drop_materials:
			each.append(float(material.get_shader_parameter("day")))
			each.append(float(material.get_shader_parameter("near_to")))
		days.append(each)
	var near := WeatherView.DROP_NEAR_TO
	_check(view._drop_materials.size() == 2 and days[0] == [1.0, near, 1.0, near] and days[1] == [0.0, near, 0.0, near]
			and is_equal_approx(days[2][0], 0.4), "rain's and drips' drops told the day's share each frame (%s)" % [days])
	view.free()
	var shader := Shader.new()
	shader.code = code
	var names := []
	for uniform: Dictionary in shader.get_shader_uniform_list():
		names.append(uniform["name"])
	_check(names.has("day") and names.has("near_from") and names.has("colour") and names.has("night_glow"), "and the drop shader compiles (%s)" % [names])


# 309 amended (3)'s seam guard: a drop ring drawn from the furthest-out centre
# its size allows (water.gdshader's keep in from the edge) is spent, its band and
# its slope under REACH_SPENT, at its cell's edge, for the smallest, the largest
# and sizes between; the drops' ring math as drops() draws it, with the
# shader's own constants.
const REACH_SPENT := 0.02

func _check_drops_kept(code: String) -> void:
	var c := {}
	for name in ["DROP_CELL", "DROP_WIDEST", "DROP_BAND", "DROP_SMALLEST", "DROP_FAINTEST",
			"DROP_KEEP_FROM", "DROP_KEEP_PER", "DROP_RATE_LO", "DROP_RATE_HI"]:
		var found := RegEx.create_from_string("const float " + name + " = ([0-9.]+);").search(code)
		c[name] = found.get_string(1).to_float() if found else -1.0
	var worst := 0.0
	var keeps: Array[float] = []
	for step in 5:
		var pick := step / 4.0
		var size: float = lerpf(c["DROP_SMALLEST"], 1.0, pick)
		var strength: float = lerpf(c["DROP_FAINTEST"], 1.0, pick)
		var keep: float = c["DROP_KEEP_FROM"] + c["DROP_KEEP_PER"] * size
		keeps.append(keep)
		for edge in 20:
			# from the edge outward into the next cell, where nothing draws it
			var d := keep + edge * 0.01
			for a in 101:
				var age := a / 100.0
				var r: float = age * size * c["DROP_WIDEST"] * 0.5 / c["DROP_CELL"]
				var x: float = (d - r) / c["DROP_BAND"]
				var wave := exp(-x * x)
				worst = maxf(worst, maxf(wave, absf(x) * wave) * (1.0 - age) * (1.0 - age) * strength)
	_check(c.values().min() > 0.0 and worst < REACH_SPENT and keeps[4] < 0.5,
			"a drop ring from its furthest-out centre is spent at its cell's edge (%.3f, the centres %.2f..%.2f in for the smallest, %.2f..%.2f for the largest)"
			% [worst, keeps[0], 1.0 - keeps[0], keeps[4], 1.0 - keeps[4]])
	_check(c["DROP_SMALLEST"] < 1.0 and c["DROP_RATE_LO"] < 1.0 and c["DROP_RATE_HI"] > 1.0,
			"the drops ring at rates and sizes of their own, so none fall in rows")


## 309 amended (6): the roofs' heightfield is drawn only while rain or snow
## falls and while the last drops still fall; dry, indoors or after, not.
func _test_roofs_drawn() -> void:
	var view := WeatherView.new()
	add_child(view)
	view.set_outdoor(true)
	var place := func(delta: float) -> void: view.place(Vector3(100.0, 0.0, 100.0), delta, Color.GRAY, 1.0, func(way: Vector3) -> Vector3: return way)
	for i in 60:
		view.ease_toward(Weather.KINDS["clear"], 0.1)
	place.call(0.1)
	_check(not view._roofs.visible, "clear weather: the roofs' heightfield is not drawn")
	for i in 30:
		view.ease_toward(Weather.KINDS["storm"], 0.1)
	place.call(0.1)
	_check(view._rain.emitting and view._roofs.visible, "rain falling: the roofs are drawn")
	for i in 60:
		view.ease_toward(Weather.KINDS["clear"], 0.1)
	place.call(0.1)
	var falling := view._roofs.visible
	var linger := maxf(view._rain.lifetime, view._snow.lifetime)
	place.call(linger + 0.5)
	_check(not view._rain.emitting and falling and not view._roofs.visible,
			"stopped: drawn while the last drops fall (%.1f s), then not" % linger)
	view.ease_toward(Weather.KINDS["storm"], 1.0)
	place.call(0.1)
	view.set_outdoor(false)
	_check(not view._roofs.visible, "indoors: not drawn")
	view.free()
