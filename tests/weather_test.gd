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
	_check(is_equal_approx((low - base - Client3D.LOW_FOG) * near, weather * Client3D.CAMERA_DISTANCE),
			"under the low camera the storm's haze to the aim reads as ortho's (%.4f over %.0f, %.4f over %.0f)" % [low - base - Client3D.LOW_FOG, near, weather, Client3D.CAMERA_DISTANCE])
	_check(is_equal_approx(Client3D.hazed_density(base, weather, true, 8.0), low) and Client3D.hazed_density(base, weather, true, near * 2.0) < low,
			"zoomed in nearer than the rest, the storm's haze no thicker; further out, thinner")
	var clear := Client3D.weathered_look(noon, Weather.KINDS["clear"])
	_check(is_equal_approx(Client3D.hazed_density(clear["fog_density"], clear["fog_weather"], true, near), float(clear["fog_density"]) + Client3D.LOW_FOG),
			"clear air: only the low camera's own haze added")
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


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
