extends Node
## The 3D view's combat readability, against the real room in main.tscn on
## a host: HP bars, deaths and corpses, and which sounds the server's
## events play. Tweens and fades run on real frames, so tests wait for
## them. Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per
## assertion and quits with exit code 1 if any assertion failed, 0
## otherwise.

var _failures := 0
var _main: Node
var _rig: Client3D


## Its base port: not 7777 (the editor may be hosting there), nor any other
## test's or eval's. view_land_test has its own.
func _base_port() -> int:
	return preload("res://tests/test_ports.gd").of(17791)


## Whether this run is the plane lands' half (278 amended: view_land_test,
## the same script with its own port, runs the sections that build the
## world plane's big outdoor levels, each a rebuild of seconds, beside this
## scene in the suite; this scene runs the rest). Each half keeps the
## sections' order.
func _land() -> bool:
	return false


func _ready() -> void:
	World.set_process(false)
	Net.port = _base_port()
	Client3D.feel_path = ""  # 673 step 2: the defaults, whatever the tuned file holds.
	_main = preload("res://main.tscn").instantiate()
	_main.returns = false  # The old respawn (decision 396 is return_test's).
	add_child(_main)
	_rig = preload("res://client3d/client3d.tscn").instantiate()
	_main.add_child(_rig)
	_rig.indoor_view = false  # The test room is walled in (671); _test_indoor_camera turns it on.
	_rig.setup(_main._terrain)
	_main._client3d = _rig
	_rig.bubbles = _main.bubbles
	_rig._process(0.0)
	_rig.sfx.hear_everything = true  # Which sounds events make; who hears them is _test_heard_as_monsters_hear.

	if _land():
		_test_horizon()
		_test_eye_kept_out()
		_test_doors_fade_inside()
		_test_sky()
		_test_far_landmarks()
		_test_arc_on_ground()
		_test_hills()
		_test_shore()
		_test_curves_meet()
		_test_built_water()
		_test_ledge_curves()
		_test_forest_edge()
		_test_forest_floor_whole()
		_test_curve_passes()
		_test_clearing()
		_test_roads()
		_test_relief()
		_test_sight()
		_test_ground_fields()
		_test_glimpses_meet()
		_test_world_map_kept()
	else:
		_test_every_sound_has_its_files()
		await _test_hp_bars()
		await _test_sounds_follow_events()
		await _test_bow_sounds()
		await _test_armour_footfalls()
		_test_work_strokes()
		_test_wade_drip()
		_test_bridge_ends()
		_test_far_cry()
		_test_mine_sounds()
		_test_idle_voices()
		await _test_monster_death()
		_test_aura()
		await _test_forge()
		await _test_companion_death()
		await _test_down_grey()
		await _test_player_death()
		_test_settings()
		_test_ground_colours()
		await _test_fade()
		await _test_fight_fade()
		_test_outdoor()
		await _test_low_camera()
		_test_indoor_camera()
		_test_camera_feel()
		_test_camera_turn()
		_test_draw_pull()
		_test_low_scatter()
		await _test_far_restart()
		await _test_low_pick()
		await _test_reach_ease()
		await _test_low_names()
		_test_cone_lift()
		_test_bent_walk()
		_test_pine_stands()
		_test_ground_textures()
		_test_canopy_mask()
		_test_grown_trees()
		await _test_warm_ups()
		_test_seasons()
		_test_heights()
		_test_damp_look()
		_test_night_look_2()
		_test_dais()
		_test_dark_set()
		_test_lair()
		_test_faced_decor()
		_test_solid_ground()
		_test_water()
		_test_streams()
		_test_bridge_walked()
		_test_tall_grass()
		_test_blood()
		_test_tracks()
		_test_cave_mouth()
		_test_mine_mouth()
		_test_shelter()
		_test_thicket_mouth()
		_test_den_mouth()
		_test_rocks()
		_test_niches()
		_test_fire()
		_test_cold_lamp()
		await _test_wall_runs()
		_test_cave_walls()
		_test_mass()
		_test_skylights()
		_test_scatter()
		_test_buildings()
		_test_roofs()
		_test_wall_heights()
		await _test_double_doors()
		_test_field()
		_test_folds()
		_test_kinds()
		_test_roof_damage()
		_test_building_states()
		_test_town_walls()
		await _test_near_miss_picks()
		await _test_seen_through()
		_test_telegraph_smooth()
		_test_telegraph_closing()
		_test_telegraph_fill_honest()
		_test_telegraph_disc_rim()
		await _test_target_marked()
		await _test_goblin()
		_test_humans()
		_test_worn()
		_test_worn_gear()
		_test_satchel_worn()
		_test_asleep()
		_test_person_looks()
		_test_person_garb()
		_test_attach_points()
		_test_bow()
		_test_standing_turn()
		_test_visible_work()
		_test_head_socket()
		_test_sleeper()
		_test_townsfolk_spots()
		await _test_two_hands()  # It lets frames run (the pose the modifiers leave): after the tests that read a pose unrun.
		await _test_blows_seen()  # It lets frames run too.
		_test_gait_holds()
		await _test_shield_seen()
		await _test_reel_clock()
		await _test_barrow_deaths()
		await _test_rest()
		_test_wet()
		_test_sword_whiff()
		await _test_teeter()  # Lets frames run: the rocking is timed.
		_test_crouch()
		await _test_pick_meets_seam()  # Lets frames run to the swing's contact.
		_test_bow_back()  # Reads a draw's pose on the wall clock: right after the pick's swing, as fitted.
		_test_sheathed()
		await _test_fishing_pose()  # Lets frames run: the rod's tip is read off the pose.
		_test_fish_rise()
		await _test_axe_edge_leads()
		_test_guard_arms()
		await _test_goblins_differ()
		_test_allies()
		_test_barrow_dead()
		_test_person_monster()
		await _test_told_lunge()
		_test_steadied_heard()
		await _test_blow_wait_outlives_body()
		_test_bandit_look()
		_test_shadows_in_view()
		_test_no_2d_under_3d()
		await _test_doors_swing()
		await _test_door_states()
		_test_art_puppets()
		_test_undrawn_puppet()
		_test_breakable_hooked_once()
		await _test_phased_build()
		await _test_kept_fields()
		await _test_indoor_phased_build()
		await _test_neighbour_swap()
		await _test_creature_puppets()
		await _test_boar_king_clips()
		await _test_hill_cat_clips()
		await _test_old_wolf_leap()
		await _test_apex_sweep()
		await _test_creature_down()
		await _test_creature_tells()
		await _test_steadied()
		_test_piles()
		_test_heard_as_monsters_hear()
		_test_ambience_runs()
		_test_heartbeat()
		_test_bandaging()
		_test_title_music()
		_test_level_music()
		_test_room_music()
		_test_options_panel()

	# Every sound stopped and let go before quitting: the audio server lets
	# a stopped sound's stream go a mix or two later, and one still held at
	# exit is reported as a leak. The ambience stopped first: its next frame
	# would start a bed again, on a stream let go.
	_rig.ambience.set_process(false)
	for player in _rig.find_children("*", "AudioStreamPlayer", true, false) + _rig.find_children("*", "AudioStreamPlayer3D", true, false):
		player.stop()
		player.stream = null
	for i in 3:
		await get_tree().process_frame
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_heard_as_monsters_hear() -> void:
	print("\n== what you hear is what monsters hear: a sound is played where a monster there hears its noise, muffled as it is ==")
	# A listener beside a door, so some noises come round walls and through it.
	var door: Door = World.get_doors()[0]
	var near := Vector2i(door.key.x, door.key.y)
	var listener := near
	for d in range(0, 4):
		for dy in range(-d, d + 1):
			for dx in range(-d, d + 1):
				if listener == near and World.is_walkable(near + Vector2i(dx, dy)) and World.get_entity_at(near + Vector2i(dx, dy)) == null:
					listener = near + Vector2i(dx, dy)
	var imp := _spawn_imp(listener)
	var counts := {"same": 0, "differ": 0, "heard": 0, "muffled": 0, "unheard": 0}
	var differ: Array[String] = []
	for noise: Array in [["sfx.hit_flesh", &"fight"], ["sfx.door_wood_open", &"door"], ["sfx.footstep", &"step"], ["sfx.break_wood", &"break"]]:
		var radius := SoundKit.reach(noise[0])
		for dy in range(-radius - 2, radius + 3):
			for dx in range(-radius - 2, radius + 3):
				var at := listener + Vector2i(dx, dy)
				imp.senses.heard.clear()
				World.noise(at, radius, noise[1])
				var monster := not imp.senses.heard.is_empty()
				var heard := Sfx.hearing(noise[0], at, listener)
				if monster == bool(heard.heard) and (not monster or bool(imp.senses.heard[0]["muffled"]) == bool(heard.muffled)):
					counts.same += 1
				else:
					counts.differ += 1
					if differ.size() < 5:
						differ.append("%s at %s: monster %s, sound %s" % [noise[1], at, imp.senses.heard, heard])
				counts.heard += 1 if heard.heard else 0
				counts.muffled += 1 if heard.heard and heard.muffled else 0
				counts.unheard += 0 if heard.heard else 1
	_check(counts.differ == 0, "every noise: heard and muffled alike (%s) %s" % [counts, differ])
	_check(counts.heard > 0 and counts.muffled > 0 and counts.unheard > 0, "some heard, some through a wall or door, some out of reach")
	var close := Sfx.hearing("sfx.hit_flesh", listener + Vector2i(1, 0), listener)
	_check(not close.heard or is_equal_approx(float(close.db), 0.0) or close.muffled, "a cell off: full loudness (%s)" % [close])
	World.despawn(imp)
	print("\n== the view plays from the local player: a blow far off is not played ==")
	var player := _rig._local_player()
	_rig._process(0.0)
	if player != null:
		_check(_rig.sfx.listener == player.tile, "the listener is the local player's cell (%s, player %s)" % [_rig.sfx.listener, player.tile])
	_rig.sfx.hear_everything = false
	_rig.sfx.listener = listener
	var before := _rig.sfx.unheard.size()
	var played := _rig.sfx.played.size()
	_rig.sfx.play("sfx.hit_flesh", Vector3(listener.x + 9, 0.0, listener.y))
	_check(_rig.sfx.unheard.size() == before + 1 and _rig.sfx.played.size() == played, "nine cells off, past a fight's 5: not played")
	_rig.sfx.play("sfx.hit_flesh", Vector3(listener.x, 0.0, listener.y))
	_check(_rig.sfx.played.size() == played + 1, "at the listener: played")
	_rig.sfx.hear_everything = true


func _test_ambience_runs() -> void:
	print("
== the view's ambience weighs its beds from the listener ==")
	_rig.sfx.listener = _rig._local_player().tile if _rig._local_player() != null else Vector2i(1, 1)
	# From silence: the frames the tests before let run (660's rooms built
	# over frames) played what their rooms weighed, still fading here.
	for bed: String in _rig.ambience.players:
		_rig.ambience.players[bed].stop()
	_rig.ambience.levels.clear()
	_rig.ambience._weigh()
	_check(_rig.ambience.targets.size() == Ambience.BEDS.size(), "a weight for every bed (%s)" % [_rig.ambience.targets])
	for i in 10:
		_rig.ambience._process(0.2)
	var playing: Array[String] = []
	for bed: String in _rig.ambience.players:
		if _rig.ambience.players[bed].playing:
			playing.append(bed)
	_check(playing.all(func(bed: String) -> bool: return _rig.ambience.targets[bed] >= Ambience.SILENT),
			"only beds with weight play (%s)" % [playing])
	# A stream (decision 505) heard from the point of its course across from
	# the listener; none where its takes aren't (other checkouts).
	var listener: Vector2i = _rig.sfx.listener
	var had: Variant = _rig._terrain.get("streams")
	var course: Array[Vector2i] = [listener + Vector2i(-3, 2), listener + Vector2i(3, 2)]
	_rig._terrain["streams"] = [{"path": course}]
	_rig.ambience._weigh()
	var takes := not SoundKit.files("amb.stream").is_empty()
	var held: Variant = _rig.ambience._streams.get(0)
	_check(held == null if not takes else held is AudioStreamPlayer3D
			and (held as AudioStreamPlayer3D).position.distance_to(_rig._tile_position(listener + Vector2i(0, 2))) < 0.01,
			"a stream two cells off: its loop across from the listener (%s)" % ("held" if held != null else "no takes"))
	_rig._terrain["streams"] = [{"path": [listener + Vector2i(60, 0), listener + Vector2i(60, 5)] as Array[Vector2i]}]
	_rig.ambience._weigh()
	_check(_rig.ambience._streams.is_empty() and (held == null or (held as Node).is_queued_for_deletion()),
			"a stream out of reach: none held, the old one let go")
	if had == null:
		_rig._terrain.erase("streams")
	else:
		_rig._terrain["streams"] = had
	_rig.ambience._weigh()
	# A stream's fall (decision 557) heard from the fall, as loud as its drop.
	var had_falls: Array[Dictionary] = _rig.stream_falls
	var fall_takes := not SoundKit.files("amb.falls").is_empty()
	_rig.stream_falls = [{"cell": listener + Vector2i(2, 0), "drop": 0.46}] as Array[Dictionary]
	_rig.ambience._weigh()
	var falling: Variant = _rig.ambience._falls.get(0)
	_check(falling == null if not fall_takes else falling is AudioStreamPlayer3D
			and (falling as AudioStreamPlayer3D).position.distance_to(_rig._tile_position(listener + Vector2i(2, 0))) < 0.01,
			"a fall two cells off: its loop there (%s)" % ("held" if falling != null else "no takes"))
	_rig.stream_falls = [{"cell": listener + Vector2i(40, 0), "drop": 0.46}] as Array[Dictionary]
	_rig.ambience._weigh()
	_check(_rig.ambience._falls.is_empty() and (falling == null or (falling as Node).is_queued_for_deletion()), "a fall out of reach: none held")
	_rig.stream_falls = had_falls
	_rig.ambience._weigh()
	# A camp's fire (777, sound's side): its crackle from its fire ring
	# (Level.camp_fire), a raid camp's as a rest camp's; none once dropped
	# or out of reach.
	var camp := {"kind": "camp", "rect": Rect2i(listener + Vector2i(1, -2), Vector2i(4, 4)), "facing": Vector2i(0, 1)}
	var ring := Level.camp_fire(camp)
	_rig._buildings.append({"rect": camp["rect"], "kind": camp, "plot": true})
	_check(ring in _rig.campfire_cells(), "a camp's fire among the camp fires (%s)" % [ring])
	_rig.ambience._weigh()
	var crackle: AudioStreamPlayer3D = _rig.ambience.points.get("amb.campfire")
	_check(SoundKit.files("amb.campfire").is_empty() or crackle != null and crackle.playing
			and crackle.position.distance_to(_rig._tile_position(ring) + Vector3.UP) < 0.01,
			"by a camp: its fire's crackle from the ring (%s)" % ("held" if crackle != null else "no takes"))
	_rig.sfx.listener = ring + Vector2i(SoundKit.reach("amb.campfire") + 2, 0)
	_rig.ambience._weigh()
	_check(crackle == null or not crackle.playing, "a camp's fire out of reach: no crackle")
	_rig.sfx.listener = listener
	_rig._buildings[-1]["dropped"] = true
	_rig.ambience._weigh()
	_check(crackle == null or not crackle.playing, "a dropped camp: no crackle")
	_rig._buildings.pop_back()
	_rig.ambience._weigh()
	# A fire place's fire (Umbrage's square): heard as a camp's fire from its
	# cell, never as a torch; a terrain fire on no fire place stays a torch.
	var hearth := listener + Vector2i(2, 1)
	var by_road := listener + Vector2i(-2, 0)
	var places := {"square_fire": {"kind": "fire", "cell": hearth}, "well": {"kind": "other", "cell": by_road},
		"camp": {"kind": "camp", "cell": listener}}
	_check(Main.fire_places(places) == ([hearth] as Array[Vector2i]), "the fire places: the fire kind's cells (%s)" % [Main.fire_places(places)])
	var had_torches: Array[Vector2i] = _rig.torch_cells.duplicate()
	var had_places: Array[Vector2i] = _rig.fire_places
	_rig.torch_cells.append_array([hearth, by_road] as Array[Vector2i])
	_rig.fire_places = [hearth] as Array[Vector2i]
	_check(_rig.place_fires() == ([hearth] as Array[Vector2i]) and hearth in _rig.campfire_cells()
			and not hearth in _rig.torch_fires() and by_road in _rig.torch_fires(),
			"the square's fire among the camp fires, not the torches; the other fire a torch")
	_rig.ambience._weigh()
	crackle = _rig.ambience.points.get("amb.campfire")
	var torch: AudioStreamPlayer3D = _rig.ambience.points.get("amb.torch_fire")
	_check(SoundKit.files("amb.campfire").is_empty() or crackle != null and crackle.playing
			and crackle.position.distance_to(_rig._tile_position(hearth) + Vector3.UP) < 0.01,
			"by the square's fire: a camp's crackle from its cell (%s)" % ("held" if crackle != null else "no takes"))
	_check(SoundKit.files("amb.torch_fire").is_empty() or torch != null and torch.playing
			and torch.position.distance_to(_rig._tile_position(hearth) + Vector3.UP) > 0.01,
			"and the torch's loop from a torch, never the square's fire (%s)" % ("held" if torch != null else "no takes"))
	_rig.fire_places = [] as Array[Vector2i]
	_check(not hearth in _rig.campfire_cells() and hearth in _rig.torch_fires(), "no fire place: the same fire a torch again")
	_rig.torch_cells = had_torches
	_rig.fire_places = had_places
	_rig.ambience._weigh()
	# The hidden door's draft (608 amended): from its edge's middle while
	# its Door is shut, none once it opens or from out of reach.
	var draft_takes := not SoundKit.files("amb.draft").is_empty()
	var door: Door = World.get_doors()[0]
	var was_open := door.open
	var had_niches: Variant = _rig._terrain.get("niches")
	var sides := Terrain.edge_cells(door.key)
	_rig._terrain["niches"] = [{"cell": sides[0], "out": sides[1] - sides[0], "edge": door.key, "kind": "hidden", "variant": 1}]
	door.open = false
	_rig.sfx.listener = sides[1] + (sides[1] - sides[0])
	_rig.ambience._weigh()
	var draft: AudioStreamPlayer3D = _rig.ambience._draft
	var middle := (_rig._tile_position(sides[0]) + _rig._tile_position(sides[1])) / 2.0 + Vector3.UP
	_check(not draft_takes or draft != null and draft.playing and draft.position.distance_to(middle) < 0.01,
			"by the hidden door, shut: its draft from the edge (%s)" % ("held" if draft != null else "no takes"))
	door.open = true
	_rig.ambience._weigh()
	_check(draft == null or not draft.playing, "the hidden door open: no draft")
	door.open = false
	_rig.sfx.listener = sides[1] + (sides[1] - sides[0]) * 8
	_rig.ambience._weigh()
	_check(draft == null or not draft.playing, "the hidden door out of reach: no draft")
	door.open = was_open
	_rig.sfx.listener = listener
	if had_niches == null:
		_rig._terrain.erase("niches")
	else:
		_rig._terrain["niches"] = had_niches
	_rig.ambience._weigh()


## 587, sound's side: the downed local player's heart over the ducked mix.
func _test_heartbeat() -> void:
	print("
== Mortally Wounded: the heart at its pace, the mix ducked, a last beat at bleed out ==")
	var heart := Client3D.Heartbeat.new()
	heart.view = _rig
	var played := _rig.sfx.played.size()
	heart.step(0.01, 120, false)
	_check(heart.beats == ["beat"] and _rig.sfx.played.size() == played + 1 and _rig.sfx.played[-1][2] == "UI",
			"downed: a beat at once, on the UI bus (%s)" % [heart.beats])
	for i in 60:
		heart.step(0.01, 120, false)
	_check(heart.beats.size() == 2, "at 120 a minute: the next half a second on (%d)" % heart.beats.size())
	_check(is_equal_approx(Sfx.duck_db, Client3D.Heartbeat.DUCK_DB)
			and is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")),
				linear_to_db(maxf(Net.sfx_volume, 0.0001)) + Client3D.Heartbeat.DUCK_DB)
			and is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("UI")), linear_to_db(maxf(Net.ui_volume, 0.0001))),
			"the mix ducked under it, the UI bus not (%.1f dB)" % Sfx.duck_db)
	for i in 100:
		heart.step(0.01, 40, false)
	_check(heart.beats.size() == 3, "Slow Heart to 40: the step heard at the next beat, then a beat in 1.5 s (%d)" % heart.beats.size())
	heart.step(0.01, 0, true)
	for i in 300:
		heart.step(0.01, 0, true)
	_check(heart.beats.size() == 3 and Sfx.duck_db == 0.0, "revived: no last beat, the mix back (%s, %.1f dB)" % [heart.beats, Sfx.duck_db])
	heart.step(0.01, 80, false)
	heart.step(0.01, 0, false)
	_check(heart.beats.slice(-2) == ["beat", "last"], "bled out: a last beat (%s)" % [heart.beats])
	heart.step(0.5, 0, false)
	_check(Sfx.duck_db < Client3D.Heartbeat.DUCK_DB, "then silence (%.1f dB)" % Sfx.duck_db)
	for i in 100:
		heart.step(0.1, 0, false)
	_check(Sfx.duck_db == 0.0, "after it, the mix back (%.1f dB)" % Sfx.duck_db)
	heart.free()


## Bandaging heard: a cloth ruffle from the bandager while it runs, soft
## when the patient mends, short when broken off.
func _test_level_music() -> void:
	print("
== a level's own music: the barrow's, eased in on arrival, out on leaving (668) ==")
	var music: Music = _rig.music
	if music == null or Music.muted():
		_check(true, "no music here (muted or none): skipped")
		return
	var level_was: Variant = _rig._terrain.get("level")
	_rig._terrain["level"] = "barrow"
	music._weigh(0.25)
	var wanted := float(music.targets.get("music.barrow", 0.0))
	_check(wanted >= 0.5 and float(music.targets.get("music.dungeon_base", 0.0)) == 0.0, "in the barrow: its own music wanted, less half the tension near (%.2f)" % wanted)
	music._process(Music.LEVEL_FADE)
	var player: AudioStreamPlayer = music.players.get("music.barrow")
	_check(float(music.levels.get("music.barrow", 0.0)) > 0.9 * wanted and player != null and player.playing,
		"eased in within %.1f s, playing (%.2f of %.2f)" % [Music.LEVEL_FADE, float(music.levels.get("music.barrow", 0.0)), wanted])
	_rig._terrain["level"] = "barrow_deep"
	music._weigh(0.25)
	_check(music.targets.get("music.barrow") == 0.0, "gone below: wanted at 0, so it eases out")
	music._process(Music.LEVEL_FADE * 2.0)
	_check(float(music.levels.get("music.barrow", 1.0)) < Music.SILENT and not player.playing, "eased out and stopped")
	_rig._terrain["level"] = "barrow"
	music._weigh(0.25)
	music._process(Music.LEVEL_FADE)
	_rig._terrain["level"] = "practice"
	music._weigh(0.25)
	var sounding := music.players.values().filter(func(p: AudioStreamPlayer) -> bool: return p.playing)
	_check(music.targets.is_empty() and sounding.is_empty() and not music.sting("danger"),
		"the practice hall (728): no music at all, what played stopped, no stinger (%d playing)" % sounding.size())
	if level_was == null:
		_rig._terrain.erase("level")
	else:
		_rig._terrain["level"] = level_was
	music._weigh(0.25)


func _test_room_music() -> void:
	print("
== a room's own music: Umbrage's in the wilds, eased in on entering, out on leaving (668 amended) ==")
	var music: Music = _rig.music
	if music == null or Music.muted():
		_check(true, "no music here (muted or none): skipped")
		return
	var level_was: Variant = _rig._terrain.get("level")
	var listener_was: Variant = _rig.sfx.listener
	_rig._terrain["level"] = "wilds"
	_rig.sfx.listener = Vector2i(200, 200)
	music._weigh(0.25)
	var wanted := float(music.targets.get("music.umbrage", 0.0))
	_check(wanted >= 0.5 and float(music.targets.get("music.town_base", 0.0)) == 0.0 and float(music.targets.get("music.wilds_base", 0.0)) == 0.0,
		"in Umbrage: the town's music wanted, the zone's ground out (%.2f)" % wanted)
	var fade_in := Music.own_fade("music.umbrage", true)
	music._process(fade_in * 0.5)
	_check(float(music.levels.get("music.umbrage", 0.0)) < 0.9 * wanted, "half its fade-in in, not yet full: it comes in slowly (%.2f of %.2f)" % [float(music.levels.get("music.umbrage", 0.0)), wanted])
	music._process(fade_in * 0.5)
	var player: AudioStreamPlayer = music.players.get("music.umbrage")
	_check(float(music.levels.get("music.umbrage", 0.0)) > 0.9 * wanted and player != null and player.playing,
		"eased in within %.1f s, playing (%.2f of %.2f)" % [fade_in, float(music.levels.get("music.umbrage", 0.0)), wanted])
	_rig.sfx.listener = Vector2i(70, 202)
	music._weigh(0.25)
	_check(music.targets.get("music.umbrage") == 0.0, "out of the town: wanted at 0, so it eases out")
	music._process(Music.LEVEL_FADE * 2.0)
	_check(float(music.levels.get("music.umbrage", 1.0)) < Music.SILENT and not player.playing, "eased out and stopped")
	_rig.sfx.listener = listener_was
	if level_was == null:
		_rig._terrain.erase("level")
	else:
		_rig._terrain["level"] = level_was
	music._weigh(0.25)


func _test_title_music() -> void:
	print("
== the title screen: music.title faded in with the main menu, out as the world loads (656) ==")
	var hud_was: bool = _main.get_node("HUD").visible
	var went_online: bool = _main._went_online
	_main._went_online = true  # Play goes on as the host already in, never online again.
	_main._show_menu()
	var title: Node = _main.title_music
	var player: AudioStreamPlayer = title.player if title != null else null
	_check(player != null and player.playing and player.bus == "Music" and player.stream.resource_path.ends_with("music.title/music.title.ogg"),
		"the menu shows: music.title plays on the Music bus, Jeff's own take")
	_check(player != null and not (player.stream as AudioStreamOggVorbis).loop and is_equal_approx(player.volume_db, title.SILENT_DB),
		"a whole track, not looped by the stream, and it starts silent")
	title._tween.custom_step(title.FADE_IN)
	_check(player != null and is_equal_approx(player.volume_db, SoundKit.volume_db("music.title")), "faded in over %.1f s to the slot's level" % title.FADE_IN)
	# 656 amended: Jeff's theme rounds faded, its end never clicking into its start.
	var length := player.stream.get_length() if player != null else 0.0
	_check(length > 30.0, "music.title is Jeff's theme, a whole track (%.1f s)" % length)
	if player != null:
		player.seek(length - 0.5)
		title._process(0.0)
		title._tween.custom_step(0.6)
		_check(title._ending and player.volume_db <= title.SILENT_DB + 0.01, "its last %.1f s: faded out (%.1f dB)" % [title.FADE_OUT, player.volume_db])
		title._again()
		_check(player.playing and player.get_playback_position() < 0.5 and not title._ending and is_equal_approx(player.volume_db, title.SILENT_DB),
				"played through: again from its start, silent")
		title._tween.custom_step(title.FADE_IN)
		_check(is_equal_approx(player.volume_db, SoundKit.volume_db("music.title")), "and faded in again")
	_main._show_menu()
	_check(_main.title_music == title, "the menu again: the same title, not a second")
	_main._play()
	_check(_main.title_music == null and title.stopping and not title.playing() and not _main.main_menu.visible, "a host's Play: its world is here, the title fades out")
	title._tween.custom_step(title.FADE_OUT + 0.01)
	_check(title.is_queued_for_deletion() and player.volume_db <= title.SILENT_DB + 0.01,
		"faded out over %.1f s, then gone (%.1f dB, %s)" % [title.FADE_OUT, player.volume_db, title.is_queued_for_deletion()])
	# A client holds it through the connect screen till its first "map", the world loading.
	_main._show_menu()
	var again: Node = _main.title_music
	_check(again != null and again != title and again.playing(), "the menu once more: a new title")
	_main._on_message("map", {"name": _main.map_name, "generation": _main.map_generation, "server": Net.server_version})
	_check(_main.title_music == null and again.stopping, "the server's \"map\" (the world loading): the title fades out")
	_main.main_menu.visible = false
	_main._went_online = went_online
	_main.get_node("HUD").visible = hud_was


func _test_bandaging() -> void:
	print("
== bandaging: a cloth ruffle while it runs, faded when done, cut when broken off ==")
	var bandaging := Client3D.Bandaging.new()
	bandaging.view = _rig
	var here := Vector3(2.0, 0.0, 3.0)
	# Held only with a take (other trees lack art/audio/external).
	var takes := not SoundKit.files("sfx.bandage").is_empty()
	bandaging.update({"A": here}, {})
	var ruffle: AudioStreamPlayer3D = bandaging.ruffles.get("A")
	_check(not takes or ruffle != null and ruffle.playing and _rig.sfx.played[-1][0] == "sfx.bandage", "started: the ruffle held, playing")
	bandaging.update({"A": here + Vector3.RIGHT}, {})
	_check(not takes or bandaging.ruffles.size() == 1 and ruffle.position.is_equal_approx(here + Vector3.RIGHT), "still running: the same ruffle, where the bandager is")
	bandaging.update({}, {"A": true})
	_check(bandaging.ruffles.is_empty() and (not takes or bandaging.ended[-1] == ["A", "done"]), "done: ended softly (%s)" % [bandaging.ended])
	bandaging.update({"B": here}, {})
	bandaging.update({}, {"B": false})
	_check(not takes or bandaging.ended[-1] == ["B", "cut"], "broken off: cut short (%s)" % [bandaging.ended])
	# Who bandages, read from the roster: tending (626), the patient's mending how it ended.
	var player := Player.new()
	player.name = "Bandager"
	var patient := Player.new()
	patient.name = "Patient"
	var roster: Array[GridEntity] = [player, patient]
	var active: Dictionary[String, Vector3] = {}
	var done: Dictionary[String, bool] = {}
	patient.mending = 1
	bandaging.read(roster, active, done)
	_check(active.is_empty(), "the patient's mending alone: nobody heard (tending is the one source)")
	player.tending = "Patient"
	bandaging.read(roster, active, done)
	_check(active.keys() == ["Bandager"], "tending the patient: heard from the bandager (%s)" % [active.keys()])
	player.tending = ""
	patient.mending = 2
	active.clear()
	done.clear()
	bandaging.read(roster, active, done)
	_check(active.is_empty() and done.get("Bandager") == true, "done, the patient mending: soft")
	player.tending = "Patient"
	patient.mending = 1
	bandaging.read(roster, active, done)
	player.tending = ""
	patient.mending = 0
	active.clear()
	done.clear()
	bandaging.read(roster, active, done)
	_check(active.is_empty() and done.get("Bandager") == false, "broken off, the patient not mending: a cut")
	player.tending = "Patient"
	patient.mending = 1
	bandaging.read(roster, active, done)
	player.tending = ""
	player.downed_until = World.tick + 100
	active.clear()
	done.clear()
	bandaging.read(roster, active, done)
	_check(active.is_empty() and done.get("Bandager") == false, "the bandager downed, the patient still bound: a cut")
	player.downed_until = 0
	player.tending = "Patient"
	bandaging.read(roster, active, done)
	player.tending = ""
	var alone: Array[GridEntity] = [player]
	active.clear()
	done.clear()
	bandaging.read(alone, active, done)
	_check(active.is_empty() and done.get("Bandager") == false, "the patient gone: a cut")
	patient.free()
	player.free()
	bandaging.free()


func _test_options_panel() -> void:
	print("\n== O: the options panel, a slider per volume, moved: the bus follows, written when let go ==")
	var panel: OptionsPanel = _main.options_panel
	_check(panel != null and not panel.visible and panel.credits_button == null,
			"there, hidden, its credits not built till shown (the server builds it too)")
	_main.toggle_options()
	_check(panel.visible and panel.sliders.size() == OptionsPanel.VOLUMES.size(), "O shows it: %d sliders" % panel.sliders.size())
	var was := Net.ambience_volume
	panel.sliders["ambience_volume"].value = 0.25
	_check(is_equal_approx(Net.ambience_volume, 0.25)
			and is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Ambience")), linear_to_db(0.25)),
			"the ambience slider at 25%%: Net and the Ambience bus follow (%.2f)" % Net.ambience_volume)
	panel.sliders["ambience_volume"].value = 0.0
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Ambience")), "at 0: muted")
	var music_was := Net.music_volume
	panel.sliders["music_volume"].value = 0.5
	_check(is_equal_approx(Net.music_volume, 0.5)
			and is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), linear_to_db(0.5)),
			"the music slider at half: Net and the Music bus follow (Jeff: \"no way to adjust music volume\")")
	panel.sliders["music_volume"].value = music_was
	var settings: Array = [Net._settings_override, Net.player_id, Net.player_name]
	Net._settings_override = preload("res://tests/test_ports.gd").scratch_path("view_test_body.cfg")
	Net.save_settings("127.0.0.1", 17789, "", Net.player_name)  # A file to rewrite, as a client has.
	var bodies: Dictionary = panel.choices["body"]["buttons"]
	_check(bodies[String(Net.player_body)].button_pressed, "Character: the body shown as set")
	var look_was := Net.player_look
	(bodies["female"] as Button).pressed.emit()
	_check(Net.player_body == &"female"
			and "body=female" in FileAccess.get_file_as_string(Net._settings_override),
			"Woman picked: Net's body and settings.cfg follow (decision 388)")
	_check(panel.preview != null and panel.preview._body == &"female" and not panel.beard_row.visible,
			"the preview shows her; no beard row for a woman (decision 439)")
	(bodies["male"] as Button).pressed.emit()
	(panel.choices["look_build"]["buttons"]["heavy"] as Button).pressed.emit()
	(panel.swatches["skin"]["7"] as Button).pressed.emit()
	var written := Net._read_settings(Net._settings_override).get("look", "") as String
	_check("build=heavy" in written and "skin=7" in written and written.begins_with("seed=")
			and panel.preview._model.find_children("*", "MeshInstance3D", true, false).any(func(m: MeshInstance3D) -> bool:
				return m.name == "Body" and m.get_blend_shape_value(m.find_blend_shape_by_name(&"heavy")) > 0.3),
			"Heavy and the seventh skin picked: written with the seed it was shown with (%s), the preview heavy" % written)
	var seed_was := Net.player_look.get_slice(" ", 0)
	for button: Button in panel.find_children("*", "Button", true, false):
		if button.text == "Surprise me":
			button.pressed.emit()
	_check(Net.player_look.begins_with("seed=") and not " " in Net.player_look and Net.player_look != seed_was,
			"Surprise me: a new seed, the rest left to it (%s)" % Net.player_look)
	Net.player_look = look_was
	DirAccess.remove_absolute(Net._settings_override)
	Net._settings_override = settings[0]
	Net.player_id = settings[1]
	Net.player_name = settings[2]
	var aa_was := Net.antialias
	var saved_override: String = Net._settings_override
	var path: String = preload("res://tests/test_ports.gd").scratch_path("view_test_aa.cfg")
	FileAccess.open(path, FileAccess.WRITE).store_string("name=Tester\n")
	Net._settings_override = path
	_check(panel.antialias_buttons.size() == Net.ANTIALIAS.size() and panel.antialias_buttons[Net.antialias].button_pressed,
			"Video: a button per anti-aliasing, %s's down" % Net.antialias)
	panel.antialias_buttons["msaa4"].pressed.emit()
	_check(Net.antialias == "msaa4" and get_viewport().msaa_3d == Viewport.MSAA_4X
			and get_viewport().screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED
			and "antialias=msaa4" in FileAccess.get_file_as_string(path),
			"MSAA 4x clicked: on the viewport, written to the file")
	panel.antialias_buttons["smaa"].pressed.emit()
	_check(get_viewport().msaa_3d == Viewport.MSAA_DISABLED and get_viewport().screen_space_aa == Viewport.SCREEN_SPACE_AA_SMAA,
			"SMAA clicked: MSAA off, SMAA on")
	Net._settings_override = saved_override
	DirAccess.remove_absolute(path)
	Net.set_antialias(aa_was, false)
	var credited := 0
	for provider: Callable in OptionsPanel.credit_providers():
		credited += (provider.call()["entries"] as Array).filter(func(entry: Dictionary) -> bool: return str(entry["url"]) != "").size()
	_check(panel.credits_box != null and not panel.credits_box.visible
			and panel.credits_list.get_children().filter(func(node: Node) -> bool: return node is LinkButton).size() == credited,
			"Credits: the list hidden, a page link per credited sound and art piece (%d; decision 406)" % credited)
	panel.credits_button.pressed.emit()
	_check(panel.credits_box.visible and panel.credits_button.text == "Hide credits", "its button shows the list")
	panel.credits_button.pressed.emit()
	_check(not panel.credits_box.visible, "and hides it")
	_main.toggle_options()
	_check(not panel.visible, "O again hides it")
	Net.set_volume("ambience_volume", was, false)
	_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Ambience")), "back as it was")


func _test_piles() -> void:
	print("\n== what lies on the ground is drawn: each thing's art slot in a ring; gone when taken ==")
	var cell := Vector2i(-1, -1)
	for each: Vector2i in _main._terrain["floor"]:
		# Not a link's cell: nothing is put down on one (571).
		if World.is_walkable(each) and not World.is_water(each) and not World.is_link_cell(each):
			cell = each
			break
	var kit := World.items.mint("bandaging_kit", "built")
	var ore := World.items.mint("ore_sack", "built")
	World.put_on_ground(kit, cell)
	World.put_on_ground(ore, cell)
	var pile: GroundPile = World.zone.piles.get(cell)
	var heap: Node3D = _rig._pile_nodes.get(pile)
	_check(heap != null and heap.get_child_count() == 3, "a heap at %s: a ring and two things (%d)" % [cell, heap.get_child_count() if heap else -1])
	_check(heap != null and heap.position.is_equal_approx(_rig._tile_position(cell)), "standing on its cell")
	World.items.end(World.take_from_ground(cell, 1), "gone")
	_check(_rig._pile_nodes.has(pile) and _rig._pile_nodes[pile].get_child_count() == 2, "one taken: the heap has the other")
	World.items.end(World.take_from_ground(cell, 0), "gone")
	_check(not _rig._pile_nodes.has(pile) and World.ground_at(cell).is_empty(), "both taken: the heap is gone")


func _test_every_sound_has_its_files() -> void:
	print("
== every sound slot the view plays has takes of its own or a fill (not the placeholder) ==")
	for slot: String in ["sfx.swing", "sfx.hit_flesh", "sfx.knockback_stone", "sfx.knockback_wood", "sfx.knockback_body",
			"sfx.knockback_body_soft", "sfx.break_wood", "sfx.goblin_death", "sfx.death_player", "sfx.death_companion",
			"sfx.door_wood_open", "sfx.door_wood_close", "sfx.footstep", "sfx.chest_open", "sfx.pack_open"]:
		var streams := _rig.sfx._streams(slot)
		_check(not streams.is_empty() and (streams[0] as AudioStream).resource_path != "",
				"%s: %d takes (%s)" % [slot, streams.size(), (streams[0] as AudioStream).resource_path.get_file() if not streams.is_empty() else "none"])


func _test_hp_bars() -> void:
	print("\n== HP bars: hurt or fighting, Alt for all, by hp, sized by max hp ==")
	var player := _player()
	var imp := _spawn_imp(Vector2i(9, 4))
	_rig._process(0.0)
	var bar := _bar(player)
	var imp_bar := _bar(imp)
	_check(bar != null and imp_bar != null, "a player and an imp each have one")
	var width := (bar.mesh as QuadMesh).size.x
	var imp_width := (imp_bar.mesh as QuadMesh).size.x
	_check(is_equal_approx(width / imp_width, float(player.max_hp) / imp.max_hp),
			"widths in proportion to max hp (%.2f for %d, %.2f for %d)" % [width, player.max_hp, imp_width, imp.max_hp])
	await _fade()
	_check(not bar.visible, "at full hp, out of a fight: no bar")
	_rig.show_all_bars = true
	await _fade()
	_check(bar.visible and _alpha(bar) > 0.99, "Alt held: shown (%.2f)" % _alpha(bar))
	_rig.show_all_bars = false
	await _fade()
	_check(not bar.visible, "let go: gone again")
	World.damage(imp, 4, player, &"attack")
	_rig._process(0.0)
	await _fade()
	_check(imp_bar.visible and is_equal_approx(_fill(imp_bar), 8.0 / 12.0), "hurt: shown, two-thirds full (%.2f)" % _fill(imp_bar))
	_check(_colour(imp_bar).is_equal_approx(Client3D.HP_GREEN_COLOR), "green above half")
	World.damage(imp, 3, player, &"attack")
	await _frames(2)
	_check(_colour(imp_bar).is_equal_approx(Client3D.HP_AMBER_COLOR), "amber at 5 of 12")
	World.damage(imp, 3, player, &"attack")
	await _frames(2)
	_check(_colour(imp_bar).is_equal_approx(Client3D.HP_RED_COLOR), "red at 2 of 12")
	var id := player.get_instance_id()
	_rig._combat_at[id] = Time.get_ticks_msec()
	await _fade()
	_check(bar.visible, "full hp, but in a fight a moment ago: shown")
	_rig._combat_at[id] = Time.get_ticks_msec() - int(Client3D.COMBAT_SECONDS * 1000.0) - 100
	await _fade()
	_check(not bar.visible, "more than %d s after the fight: faded out" % roundi(Client3D.COMBAT_SECONDS))
	Net.hp_bars = false
	_rig.show_all_bars = true
	await _fade()
	_check(not imp_bar.visible and not bar.visible, "hp_bars=0: none, even with Alt")
	Net.hp_bars = true
	_rig.show_all_bars = false
	World.despawn(imp)
	_rig._process(0.0)


## The arrows shot that are still about (_on_shot's ShotArrow*).
func _shot_arrows() -> Array:
	var parent := (_rig._puppets.values()[0] as Node3D).get_parent()
	return parent.get_children().filter(func(node: Node) -> bool:
		return String(node.name).begins_with("ShotArrow") and not node.is_queued_for_deletion())


func _test_bow_sounds() -> void:
	print("
== the bow: a creak as it's drawn, a twang as it's loosed, the arrow heard where it ends as it gets there ==")
	var player := _player()
	var imp := _spawn_imp(Vector2i(9, 4))
	_rig._process(0.0)
	player.raised = "draw"
	_check(_heard(func() -> void: _rig._process(0.0)).has("sfx.bow_draw"), "drawn: the creak")
	_check(not _heard(func() -> void: _rig._process(0.0)).has("sfx.bow_draw"), "held drawn: once")
	var creaks := _rig.sfx.get_children().filter(func(child: Node) -> bool:
		return str(child.get_meta("slot", "")) == "sfx.bow_creak" and not child.is_queued_for_deletion())
	# Its takes are external (synced from the sound library): a checkout
	# without them holds none (Sfx.hold's null).
	var takes := not SoundKit.files("sfx.bow_creak").is_empty()
	_check(creaks.size() == (1 if takes else 0) and (not takes or (creaks[0] as AudioStreamPlayer3D).playing),
			"held drawn: the bow's creak held, one (%d; takes here: %s)" % [creaks.size(), takes])
	var low := Client3D.creak_tune(0.0)
	var full := Client3D.creak_tune(1.0)
	_check(is_equal_approx(low.x, 0.85) and is_equal_approx(full.x, 1.25) and full.y > low.y + 12.0,
			"the creak rises with the draw (%s to %s)" % [low, full])
	if takes:
		_check(is_equal_approx(float(creaks[0].get_meta("pitch")), Client3D.creak_tune(World.draw_of(player)).x),
				"the creak tuned to the draw")
	player.raised = ""
	_rig._process(0.0)
	_check(not takes or creaks[0].is_queued_for_deletion(), "the draw let down: the creak stops")
	var before := _rig.sfx.played.size()
	var loosed := _heard(func() -> void:
		player._world_shot(Vector2(imp.tile), &"body")
		World.damage(imp, 1, player, &"shot"))
	_check(loosed.slice(0, 1) == ["sfx.bow_loose"] and not loosed.has("sfx.arrow_hit_flesh"),
			"loosed at the imp: the twang, its hit not yet (%s)" % [loosed])
	await get_tree().create_timer(0.5).timeout
	var after: Array[String] = []
	for entry: Array in _rig.sfx.played.slice(before):
		after.append(entry[0])
	_check(after.count("sfx.arrow_hit_flesh") == 1 and not after.any(func(slot: String) -> bool: return slot in ["sfx.arrow_land", "sfx.arrow_hit_stone", "sfx.arrow_hit_wood"]),
			"as the arrow arrives: its hit on flesh, once, and no miss (%s)" % [after])
	_check(not after.has("sfx.hit_blunt_flesh"), "a shot that leaves it standing: no heavier blow")
	# A shot that knocks it down (a lob's hit, 677) lands heavier: the blunt blow
	# with the arrow's and the fall, once, whichever news comes first.
	var imp_id := imp.get_instance_id()
	imp.down_until = World.tick + 15
	var knocked := _heard(func() -> void:
		_rig._on_struck(1, &"shot", imp_id)
		_rig._process(0.0)
		_rig._process(0.0))
	_check(knocked.has("sfx.arrow_hit_flesh") and knocked.has("sfx.knockdown") and knocked.count("sfx.hit_blunt_flesh") == 1,
			"a shot knocks it down: the arrow's hit, the fall and one heavier blow (%s)" % [knocked])
	imp.down_until = 0
	_rig._process(0.0)
	_check(not _heard(func() -> void: _rig._on_struck(1, &"shot", imp_id)).has("sfx.hit_blunt_flesh"), "its next shot, standing: none")
	imp.down_until = World.tick + 15
	(_rig._puppets[imp_id] as Node3D).set_meta("shot_ms", Time.get_ticks_msec() - 2 * Client3D.KNOCKDOWN_BLOW_MS)
	var shoved := _heard(func() -> void: _rig._process(0.0))
	_check(shoved.has("sfx.knockdown") and not shoved.has("sfx.hit_blunt_flesh"), "knocked down long after a shot: only the fall (%s)" % [shoved])
	imp.down_until = 0
	_rig._process(0.0)
	# A miss, heard by what stopped it.
	var open := Vector2i(-1, -1)
	var wall := Vector2i(-1, -1)
	for cell: Vector2i in _main._terrain["floor"]:
		if World.is_water(cell) or not World.is_walkable(cell):
			continue
		var kind := World.edge_kind(cell, Vector2i(1, 0))
		var past := cell + Vector2i(1, 0)
		if open.x < 0 and kind == Terrain.Edge.OPEN and World.is_walkable(past) and World.height_at(past) <= World.height_at(cell):
			open = cell
		if wall.x < 0 and kind == Terrain.Edge.WALL:
			wall = cell
	_check(Client3D._arrow_landed(open - Vector2i(3, 0), open) == "sfx.arrow_land", "nothing past it: it falls (%s)" % open)
	_check(wall.x < 0 or Client3D._arrow_landed(wall - Vector2i(3, 0), wall) == "sfx.arrow_hit_stone", "a wall past it: stone (%s)" % wall)
	var door: Door = World.get_doors()[0]
	var cell := Vector2i(door.key.x, door.key.y)
	var across := Vector2i(1, 0) if door.key.z == Terrain.EAST else Vector2i(0, 1)
	if door.is_open():
		World._set_door(door, false, player)
	_check(Client3D._arrow_landed(cell - across * 3, cell) == "sfx.arrow_hit_wood", "a closed door past it: wood")
	var edge := Vector2i(-1, -1)
	var pool := Vector2i(-1, -1)
	for at: Vector2i in _main._terrain["floor"]:
		var beyond := at + Vector2i(1, 0)
		if edge.x < 0 and World.edge_kind(at, Vector2i(1, 0)) == Terrain.Edge.OPEN and not World.is_walkable(beyond) \
				and not World.is_water(beyond) and not World.is_water(at):
			edge = at
		if pool.x < 0 and World.is_water(at):
			pool = at
	_check(edge.x < 0 or Client3D._arrow_landed(edge - Vector2i(3, 0), edge, {edge + Vector2i(1, 0): true}) == "sfx.arrow_hit_wood"
			and Client3D._arrow_landed(edge - Vector2i(3, 0), edge) == "sfx.arrow_hit_stone",
			"a tree past it: wood; the same edge with no tree: stone (%s)" % edge)
	_check(pool.x < 0 or Client3D._arrow_landed(pool - Vector2i(3, 0), pool) == "sfx.arrow_water", "down in water: its plip (%s)" % pool)
	var archer: Variant = _rig.sfx.listener
	_rig.sfx.listener = player.tile
	var whistled := _rig.sfx.played.size()
	var whistle_unheard := _rig.sfx.unheard.size()
	var far := _rig._tile_position(player.tile + Vector2i(-4, 1))
	_rig._whistle(far, _rig._tile_position(player.tile + Vector2i(4, 1)), 0.2)
	_rig._whistle(_rig._tile_position(player.tile), far, 0.2)
	await get_tree().create_timer(0.4).timeout
	var whistles := (_rig.sfx.played.slice(whistled).map(func(entry: Array) -> String: return entry[0]) \
			+ _rig.sfx.unheard.slice(whistle_unheard)).count("sfx.arrow_flight")
	_check(whistles == 1, "an arrow passing a cell off whistles by, once; the archer's own does not (%d)" % whistles)
	_rig.sfx.listener = archer
	var miss := _rig.sfx.played.size()
	var unheard := _rig.sfx.unheard.size()
	var expected := Client3D._shot_sound(&"ground", open)  # As the sim says what stopped it (583).
	var arrows_before := _shot_arrows()
	player._world_shot(Vector2(open), &"ground")
	await get_tree().create_timer(0.5).timeout
	_check((_rig.sfx.played.slice(miss).map(func(entry: Array) -> String: return entry[0]) + _rig.sfx.unheard.slice(unheard)).has(expected),
			"loosed at nobody: as it gets there, what stopped it (%s)" % expected)
	# Its flight (Jeff: "after the full range it sags down and lands in ground, not hitting ground
	# at its target like it does now"): past the cell it was shot at, in the ground, nose down.
	# From where the player stands: a cell its shot falls short at, and one it meets stone at.
	var spent := Vector2i(-1, -1)
	var stone := Vector2i(-1, -1)
	for target: Vector2i in _main._terrain["floor"]:
		var d: Vector2i = target - player.tile
		if maxi(absi(d.x), absi(d.y)) < 3 or maxi(absi(d.x), absi(d.y)) > 8 or World.get_entity_at(target) != null:
			continue
		var heard := Client3D._arrow_landed(player.tile, target)
		if spent.x < 0 and heard == "sfx.arrow_land":
			spent = target
		if stone.x < 0 and heard == "sfx.arrow_hit_stone":
			stone = target
	open = spent
	wall = stone
	expected = "sfx.arrow_land"
	arrows_before = _shot_arrows()
	player._world_shot(Vector2(open), &"ground")
	await get_tree().create_timer(0.05).timeout
	# Seen in flight (the coordinator: a hairline in the game's camera): thicker, a pale trail behind.
	var flying := _shot_arrows().filter(func(arrow: Node3D) -> bool: return not arrow in arrows_before)
	_check(flying.size() == 1 and (flying[0] as Node3D).get_node_or_null("Trail") != null
			and is_equal_approx((flying[0] as Node3D).transform.basis.x.length(), Client3D.ARROW_FLIGHT_GIRTH),
			"an arrow in flight is drawn %.1f times its girth, a pale trail behind it" % Client3D.ARROW_FLIGHT_GIRTH)
	await get_tree().create_timer(0.55).timeout
	var landed := _shot_arrows().filter(func(arrow: Node3D) -> bool: return not arrow in arrows_before)
	_check(landed.size() == 1 and (landed[0] as Node3D).get_node_or_null("Trail") == null
			and is_equal_approx((landed[0] as Node3D).transform.basis.x.length(), 1.0),
			"come to rest: its true girth, the trail gone")
	if open.x >= 0 and landed.size() == 1:
		var arrow: Node3D = landed[0]
		var aimed := _rig._tile_position(open)
		var from := (_rig._puppets[player.get_instance_id()] as Node3D).position
		var along := Vector3(aimed.x - from.x, 0.0, aimed.z - from.z).normalized()
		var past := (arrow.position - aimed).dot(along)
		var ground := _rig._ground_height(Vector2(arrow.position.x, arrow.position.z))
		_check(past > 1.0 and absf(arrow.position.y - ground) < 0.3 and arrow.transform.basis.y.normalized().y < -0.3,
				"a spent arrow falls past where it was aimed (%.2f m on) and stands in the ground nose down (%.2f m off it, heading %s)" % [past, arrow.position.y - ground, arrow.transform.basis.y.normalized()])
	else:
		_check(false, "a spent arrow landed (%s, %d new)" % [expected, landed.size()])
	# Its arc (583 amended (3); Jeff: "the abrupt arrow drop at the range thats a little obvious"):
	# level, then dipping ever steeper, no sudden turn.
	var a := Vector3(0, 1.4, 0)
	var b := Vector3(12, 1.4, 0)
	var dips := []
	var turns := 0.0
	for i in 21:
		var t := i / 20.0
		dips.append(snappedf(a.y - Client3D.arc_at(a, b, 1.4, t).y, 0.01))
		if i > 0:
			turns = maxf(turns, Client3D.arc_heading(a, b, 1.4, t).angle_to(Client3D.arc_heading(a, b, 1.4, t - 0.05)))
	_check(dips[10] == 0.0 and dips[16] > 0.0 and dips[16] < 0.5 and is_equal_approx(dips[20], 1.4) and turns < deg_to_rad(8.0)
			and Client3D.arc_heading(a, b, 1.4, 1.0).normalized().y < -0.3,
			"a spent arrow's arc: level halfway, dipping over its last part, into the ground nose down, never turning more than 8 degrees a step (%s)" % [dips])
	# The lob (decision 677): its aim, a brass arc and the ring, then the arrow up and down onto the cell.
	if open.x >= 0:
		var tip: Vector3 = _rig._bow_tip(_rig._puppets[player.get_instance_id()])
		_rig.lob_aim(tip, open, 1.0, true, 0.25, true)
		_check(_rig._lob_arc.visible and _rig._lob_ring.visible and _rig._lob_arc.mesh.get_surface_count() == 1, "lobbing: the brass arc and the ring shown")
		_rig.lob_aim(Vector3.ZERO, Vector2i.ZERO, 0.0, false, 0.0, false)
		_check(not _rig._lob_arc.visible and not _rig._lob_ring.visible, "and hidden after")
		var lob_played := _rig.sfx.played.size()
		var lob_unheard := _rig.sfx.unheard.size()
		var lob_sounds := func() -> Array:
			return _rig.sfx.played.slice(lob_played).map(func(entry: Array) -> String: return entry[0]) + _rig.sfx.unheard.slice(lob_unheard)
		# 677 amended (2), ui's side: a volley of three. The loose goes up fast at
		# LOB_PITCH and fades; the circle shows till the last is down; each falls
		# steeply onto its point at its tick, with its thud.
		var falls := PackedVector2Array([Vector2(open) + Vector2(0.3, -0.2), Vector2(open) + Vector2(-0.3, 0.3), Vector2(open)])
		var ticks := 6
		var volley_before := _rig.find_children("VolleyArrow*", "", false, false)
		player._world_lobbed(open, ticks, 1.0, falls)
		var start := Time.get_ticks_msec()
		_check(lob_sounds.call().has("sfx.bow_loose") and lob_sounds.call().has("sfx.arrow_lob_rise") and not lob_sounds.call().has("sfx.arrow_lob_fall"),
				"a lob loosed: the twang and its whoosh up, its whistle not yet (%s)" % [lob_sounds.call()])
		var lofted := _rig.get_tree().root.find_child("LobArrow", true, false) as Node3D
		var ring := _rig.find_child("VolleyRing", false, false) as MeshInstance3D
		var volley := _rig.find_children("VolleyArrow*", "", false, false).filter(func(arrow: Node) -> bool: return not arrow in volley_before)
		_check(ring != null and ring.material_override.albedo_color.is_equal_approx(Color(UiTheme.color("alarm"), 0.85)),
				"the volley's circle on the ground round the aimed cell, in the alarm colour")
		_check(volley.size() == 3 and volley.all(func(arrow: Node3D) -> bool: return not arrow.visible), "three arrows to fall, none shown yet (%d)" % volley.size())
		var high := tip.y
		var faded := 0.0
		var lands: Array[float] = []
		var whistles_at_first := -1
		var ring_at_last := false
		var landed_at: Array[Vector3] = []
		# Game time, as the falls' tweens run (process delta), not the wall clock: under a
		# suite's load a long frame put the thuds 0.3 s late by the clock (terrain's landing,
		# 2026-11-04 22:54). A fall is heard at most a frame after its tick.
		var game := 0.0
		var longest := 0.0
		while game < 1.4 and Time.get_ticks_msec() - start < 10000:
			await get_tree().process_frame
			var step := get_process_delta_time()
			game += step
			longest = maxf(longest, step)
			var now := game
			if is_instance_valid(lofted):
				high = maxf(high, lofted.position.y)
				var meshes := ([lofted] if lofted is GeometryInstance3D else []) + lofted.find_children("*", "GeometryInstance3D", true, false)
				faded = maxf(faded, (meshes[0] as GeometryInstance3D).transparency if not meshes.is_empty() else 0.0)
			while lands.size() < lob_sounds.call().count("sfx.arrow_land"):
				lands.append(now)
				if lands.size() == 1:
					whistles_at_first = lob_sounds.call().count("sfx.arrow_lob_fall")
					_check(not is_instance_valid(lofted), "the loosed arrow gone before the first falls")
				var fallen: Node3D = volley[lands.size() - 1] if lands.size() <= volley.size() else null
				landed_at.append(fallen.position if fallen != null and is_instance_valid(fallen) else Vector3.INF)
				_check(fallen != null and is_instance_valid(fallen) and fallen.visible and fallen.transform.basis.y.normalized().y < -0.8,
						"fall %d down steeply, nose first" % lands.size())
				if lands.size() == falls.size():
					ring_at_last = is_instance_valid(ring)
		_check(high > tip.y + 4.0 and faded > 0.8, "the loosed arrow went up fast (%.1f m over the bow) and faded out (%.2f)" % [high - tip.y, faded])
		_check(whistles_at_first == 1, "the falling whistle once, before the first lands (%d)" % whistles_at_first)
		var flight := float(ticks) / World.TICK_RATE
		var on_time := lands.size() == 3
		for i in lands.size():
			on_time = on_time and absf(lands[i] - (flight + float(i) / World.TICK_RATE)) < 0.1 + longest
		_check(on_time, "each fall thuds in at its tick, %.1f s apart, by game time within a frame (%s; longest frame %.3f s)" % [1.0 / World.TICK_RATE, lands, longest])
		var on_point := landed_at.size() == 3
		for i in landed_at.size():
			on_point = on_point and Vector2(landed_at[i].x, landed_at[i].z).distance_to(falls[i]) < 0.2
		_check(on_point, "each on its own point (%s, %s)" % [landed_at, falls])
		_check(ring_at_last and not is_instance_valid(ring), "the circle shown till the last is down, then gone")
	if wall.x >= 0:
		arrows_before = _shot_arrows()
		player._world_shot(Vector2(wall) + Vector2(wall - player.tile).normalized() * 0.5, &"stone")
		await get_tree().create_timer(1.0).timeout
		var glanced := _shot_arrows().filter(func(arrow: Node3D) -> bool: return not arrow in arrows_before)
		var at_wall := _rig._tile_position(wall)
		_check(glanced.size() == 1 and absf((glanced[0] as Node3D).position.y - _rig._ground_height(Vector2((glanced[0] as Node3D).position.x, (glanced[0] as Node3D).position.z))) < 0.1
				and Vector2((glanced[0] as Node3D).position.x - at_wall.x, (glanced[0] as Node3D).position.z - at_wall.z).length() < 1.2,
				"an arrow off a stone wall lies on the ground at its foot (%s, the wall cell at %s)" % [glanced.map(func(arrow: Node3D) -> Vector3: return arrow.position), at_wall])
	var friend := _companion()
	if friend != null and World.spares(player, friend):
		var heard := _rig.sfx.played.size()
		var unheard_before := _rig.sfx.unheard.size()
		player._world_shot(Vector2(friend.tile), &"body")
		await get_tree().create_timer(0.5).timeout
		_check((_rig.sfx.played.slice(heard).map(func(entry: Array) -> String: return entry[0]) + _rig.sfx.unheard.slice(unheard_before)).has("sfx.arrow_spared"),
				"loosed at a companion, who is spared (456): it sticks in, softly")
	World.despawn(imp)
	_rig._process(0.0)


func _test_sounds_follow_events() -> void:
	print("\n== sounds play on the server's events ==")
	var player := _player()
	var imp := _spawn_imp(Vector2i(9, 4))
	_rig._process(0.0)
	var swung := _heard(func() -> void: player._world_swung(Vector2i(1, 0)))
	_check(swung.slice(0, 1) == [SoundKit.swing(World.wielded(player))] and swung.slice(1) in [[], ["voice.effort_swing_male"]],
			"a swing: a whoosh, a grunt now and then (%s)" % [swung])
	_check(_heard(func() -> void: imp.cried.emit(&"call")) == ["sfx.goblin_alert"], "a goblin calls its pack: its alert")
	_check(_heard(func() -> void: imp.cried.emit(&"rout")) == ["sfx.goblin_rout"], "a goblin breaks and runs: its rout")
	_check(_heard(func() -> void: imp.cried.emit(&"howl_unknown")).is_empty(), "a cry with no slot: nothing")
	# Its hit heard as the drawn blow lands (its strike's contact), not with the whoosh.
	var swung_at := int(_rig._swings[player.get_instance_id()][0])
	var lands := int(_rig._swings[player.get_instance_id()][2])
	var before := _rig.sfx.played.size()
	var at_once := _heard(func() -> void: World.damage(imp, 1, player, &"attack"))
	await get_tree().create_timer(maxf((lands - Time.get_ticks_msec()) / 1000.0, 0.0) + 0.1).timeout
	var blow: Array = _rig.sfx.played.slice(before).map(func(entry: Array) -> String: return entry[0])
	_check(lands > swung_at and (at_once.is_empty() or Time.get_ticks_msec() >= lands), "the swing's blow lands %d ms after it sets off; nothing heard before (%s)" % [lands - swung_at, at_once])
	_check(blow.slice(0, 1) == [SoundKit.hit(World.wielded(player))] and blow.slice(1) in [[], ["sfx.goblin_pain"]],
			"a blow just after the player's swing: its weapon's hit on flesh, the imp crying out now and then (%s)" % [blow])
	# On worn metal: the imp's blow (its hands unknown) on the player in plate knocks on it.
	var worn_before: String = player.worn
	player.worn = "plate_armour"
	_check(_heard(func() -> void: World.damage(player, 1, imp, &"attack")).slice(0, 1) == ["sfx.hit_blunt_armor"], "a blow on a player in plate: on metal")
	player.worn = worn_before
	player.hp = player.max_hp
	_check(_heard(func() -> void: World._impact(imp, 1, player, &"stone")) == ["sfx.knockback_stone"], "into a wall: stone")
	_check(_heard(func() -> void: World._impact(imp, 1, player, &"wood")) == ["sfx.knockback_wood"], "into a door or crate: wood")
	_check(_heard(func() -> void: World._impact(imp, 1, player, &"body")) == ["sfx.knockback_body", "sfx.knockback_body_soft"],
			"into another body: a thud, and a softer one")
	_check(_heard(func() -> void: World.damage(imp, 1, null, &"fire")).is_empty(), "fire: nothing yet (no fire sounds in the packs)")
	var door: Door = World.get_doors()[0]
	_rig._process(0.0)
	_check(_heard(func() -> void: World._set_door(door, not door.open, player); _rig._process(0.0)) == [
			"sfx.door_wood_open" if door.open else "sfx.door_wood_close"], "a door: open or close, as it went")
	_check(_heard(func() -> void: World._relocate(imp, imp.tile + Vector2i(0, 1)); _rig._process(0.0)).any(func(slot: String) -> bool: return slot.begins_with("sfx.footstep_stone_")),
			"a creature's tile moves on: a footstep")
	# Tall grass (decision 508): a step into it rustles over the footstep;
	# none once trampled flat, but the trampling step itself does.
	var grass_at := imp.tile + Vector2i(0, 1)
	var had_grass: Array = _rig._terrain.get("tall_grass", [])
	World._load_cover({"tall_grass": [grass_at]})
	var into := _heard(func() -> void: World._relocate(imp, grass_at); _rig._process(0.0))
	_check(into.size() == 2 and into[1] == "sfx.grass_rustle", "into tall grass: a rustle over the step (%s)" % [into])
	_check(Client3D.rustles(grass_at, -Client3D.FLATTENED_MS, 0) == (World.cover_at(grass_at) > 0.0)
			and Client3D.rustles(grass_at, 500, 600) and not Client3D.rustles(imp.tile + Vector2i(5, 5), 500, 600),
			"trampled: only the step that flattened it rustles; none off the grass")
	World._trampled_of(World.fields.level).erase(grass_at)
	World._load_cover({"tall_grass": had_grass})
	# 676 1b amended: a step off from standing is its own footfall, the footstep and the clank
	# together; once in its gait the feet give both (_test_armour_footfalls).
	var worn_was: String = player.worn
	var from_tile := player.tile
	player.worn = "plate_armour"
	var off := _heard(func() -> void: World._relocate(player, player.tile + Vector2i(0, 1)); _rig._process(0.0)).filter(
			func(slot: String) -> bool: return slot.begins_with("sfx.armour_") or slot.begins_with("sfx.footstep"))
	World._relocate(player, from_tile)
	_rig._process(0.0)
	player.worn = worn_was
	_check(off.size() == 2 and off[0].begins_with("sfx.footstep") and off[1] == "sfx.armour_plate",
			"a step off from standing in plate: its footstep and its clank together (%s)" % [off])
	var pitch_light := _swing_pitch(imp)
	var pitch_heavy := _swing_pitch(player)
	_check(pitch_light > pitch_heavy, "an imp's swing is higher than a player's (%.2f, %.2f)" % [pitch_light, pitch_heavy])
	World.despawn(imp)
	_rig._process(0.0)


## 780: a cry from out of sight (the server's "far_cry"): the great bear's
## roar played at its cell, not at any drawn body; a kind with no slot for
## the cry plays nothing.
func _test_far_cry() -> void:
	print("\n== a cry from out of sight, played where the creature is (780) ==")
	var hear_was: bool = _rig.sfx.hear_everything
	_rig.sfx.hear_everything = true
	var before: int = _rig.sfx.played.size()
	var played: bool = _rig.far_cry("great_bear", "roar", Vector2i(30, 30))
	var heard: Array = _rig.sfx.played.slice(before).map(func(entry: Array) -> String: return str(entry[0]))
	_check(played and heard == ["sfx.great_bear_roar"], "the great bear's roar from (30, 30) (%s)" % [heard])
	before = _rig.sfx.played.size()
	_check(not _rig.far_cry("great_bear", "hum", Vector2i(30, 30)) and not _rig.far_cry("", "roar", Vector2i(30, 30))
			and _rig.sfx.played.size() == before, "a cry with no slot: nothing")
	before = _rig.sfx.played.size()
	_rig.play_cell("sfx.wave_wolves", Vector2i(40, 12))
	heard = _rig.sfx.played.slice(before).map(func(entry: Array) -> String: return str(entry[0]))
	_check(heard == ["sfx.wave_wolves"], "a night watch's wave heard from its cell (771) (%s)" % [heard])
	_rig.sfx.hear_everything = hear_was


## 769 amended (4): a mine's sounds. A blow on a seam is the pick on rock,
## with no cry and no fight's music; a sack given (its hp back up, or spent)
## the ore tumbling; a cart's roll held while it moves, its stop after; a
## wall lamp's soft flame from the nearest lamp.
func _test_mine_sounds() -> void:
	print("\n== a mine's sounds (769 amended (4)) ==")
	var hear_was: bool = _rig.sfx.hear_everything
	_rig.sfx.hear_everything = true
	var tile := Vector2i(9, 9)
	var occupant := World.get_entity_at(tile)
	if occupant != null:
		World.despawn(occupant)
	var spec := Level.SEAM_SPEC.duplicate()
	spec["tile"] = tile
	spec["name"] = "ViewSeam"
	var seam := _main._spawn(spec) as Seam
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets.get(seam.get_instance_id())
	if puppet == null:
		_check(false, "a seam drawn")
		World.despawn(seam)
		_rig.sfx.hear_everything = hear_was
		return
	var fight_was: bool = _rig.music._fight_heard
	_rig.music._fight_heard = false
	var struck := _heard(func() -> void: _rig._on_struck(1, &"attack", seam.get_instance_id()))
	_check(struck == ["sfx.pick_strike"] and not _rig.music._fight_heard, "a seam struck: the pick on rock, no cry, no fight's music (%s)" % [struck])
	_rig.music._fight_heard = fight_was
	seam.hp = seam.max_hp - 1
	_rig._sync_seam(puppet, seam)
	var sack := _heard(func() -> void:
		seam.hp = seam.max_hp
		_rig._sync_seam(puppet, seam))
	_check(sack == ["sfx.ore_sack"], "a sack given: the ore tumbling (%s)" % [sack])
	var blow := _heard(func() -> void:
		seam.hp = seam.max_hp - 1
		_rig._sync_seam(puppet, seam))
	_check(blow.is_empty(), "a blow's hp lost: no sack (%s)" % [blow])
	var last := _heard(func() -> void:
		seam.spent = true
		_rig._sync_seam(puppet, seam))
	var after := _heard(func() -> void: _rig._sync_seam(puppet, seam))
	_check(last == ["sfx.ore_sack"] and after.is_empty(), "the last sack, the seam spent: once (%s, then %s)" % [last, after])
	World.despawn(seam)
	# The cart: any entity drawn as prop.mine_cart.
	var cart := _spawn_imp(Vector2i(9, 11))
	cart.spawn_spec["art"] = Client3D.CART_ART
	cart.move_ticks = 2.0  # A quick roll's step: its stop at CART_STOP_MS (794, sound's side).
	_rig._process(0.0)
	var body: Node3D = _rig._puppets.get(cart.get_instance_id())
	if body == null:
		_check(false, "a cart drawn")
	else:
		var now := Time.get_ticks_msec()
		body.set_meta("cart_tile", cart.tile + Vector2i(-1, 0))
		_rig._sync_cart(body, cart, now)
		var rolling: Variant = body.get_meta("cart_roll") if body.has_meta("cart_roll") else null
		_check(SoundKit.files("sfx.minecart_roll").is_empty() or rolling is AudioStreamPlayer3D, "a cart moving: its roll held")
		var stop := _heard(func() -> void: _rig._sync_cart(body, cart, now + Client3D.CART_STOP_MS + 1))
		_check(rolling == null or (stop == ["sfx.minecart_stop"] and not body.has_meta("cart_roll") and (rolling as Node).is_queued_for_deletion()),
				"a cart still CART_STOP_MS: its roll let go, its stop heard (%s)" % [stop])
		# A slow roll (794, sound's side): low, and its stop waits out the step.
		cart.move_ticks = World.TICK_RATE / World.cart_stop_speed
		var then := now + 5000
		body.set_meta("cart_tile", cart.tile + Vector2i(-1, 0))
		_rig._sync_cart(body, cart, then)
		var slow: Variant = body.get_meta("cart_roll") if body.has_meta("cart_roll") else null
		var early := _heard(func() -> void: _rig._sync_cart(body, cart, then + Client3D.CART_STOP_MS + 1))
		_check(slow == null or (early.is_empty() and is_equal_approx((slow as AudioStreamPlayer3D).pitch_scale, Client3D.CART_PITCH.x)),
				"a cart rolling at cart_stop_speed: pitched low (%s), no stop CART_STOP_MS into a %d ms step (%s)"
				% [str((slow as AudioStreamPlayer3D).pitch_scale) if slow != null else "-", Client3D.cart_stop_ms(cart.move_ticks), early])
		var late := _heard(func() -> void: _rig._sync_cart(body, cart, then + Client3D.cart_stop_ms(cart.move_ticks) + 1))
		_check(slow == null or late == ["sfx.minecart_stop"], "its step out and the slack past: its stop heard (%s)" % [late])
		_check(is_equal_approx(Client3D.cart_roll_pitch(World.TICK_RATE / World.cart_top_speed), Client3D.CART_PITCH.y)
				and Client3D.cart_stop_ms(2.0) == Client3D.CART_STOP_MS,
				"a cart at cart_top_speed pitched high; a quick step's stop at CART_STOP_MS")
	World.despawn(cart)
	_rig._process(0.0)
	# A wall lamp: its flame from the nearest in reach.
	var listener: Vector2i = _rig.sfx.listener
	var had_decor: Variant = _rig._terrain.get("decor")
	_rig._terrain["decor"] = [{"cell": listener + Vector2i(1, 0), "out": Vector2i(0, -1), "kind": "mine_lamp", "variant": 1, "edge": Vector3i.ZERO}]
	_rig.ambience._mine_terrain = {}
	_rig.ambience._weigh()
	var hiss: AudioStreamPlayer3D = _rig.ambience.points.get("amb.lamp_hiss")
	_check(SoundKit.files("amb.lamp_hiss").is_empty() or hiss != null and hiss.playing, "by a mine's lamp: its flame")
	if had_decor == null:
		_rig._terrain.erase("decor")
	else:
		_rig._terrain["decor"] = had_decor
	_rig.ambience._mine_terrain = {}
	_rig.ambience._weigh()
	_check(hiss == null or not hiss.playing, "no mine: no lamp")
	# A skylight (797; 795 amended): the outside's faint air from the gap.
	var had_skylights: Variant = _rig._terrain.get("skylights")
	_rig._terrain["skylights"] = [{"at": listener + Vector2i(2, 0), "radius": 2.0}]
	_rig.ambience._mine_terrain = {}
	_rig.ambience._weigh()
	var air: AudioStreamPlayer3D = _rig.ambience.points.get("amb.skylight_air")
	_check(SoundKit.files("amb.skylight_air").is_empty() or air != null and air.playing, "under a skylight: the outside's air")
	_rig._terrain["skylights"] = [{"at": listener + Vector2i(SoundKit.reach("amb.skylight_air") + 3, 0), "radius": 2.0}]
	_rig.ambience._mine_terrain = {}
	_rig.ambience._weigh()
	_check(air == null or not air.playing, "a skylight out of reach: no air")
	if had_skylights == null:
		_rig._terrain.erase("skylights")
	else:
		_rig._terrain["skylights"] = had_skylights
	_rig.ambience._mine_terrain = {}
	_rig.sfx.hear_everything = hear_was


## 795: a boar at peace grunts or roots now and then: two at most at once
## (a sounder murmurs, not chatters), none from one that just fought, none
## when the roll misses.
func _test_idle_voices() -> void:
	print("\n== a boar at peace grunts and roots (795) ==")
	var hear_was: bool = _rig.sfx.hear_everything
	_rig.sfx.hear_everything = true
	var listener_was: Variant = _rig.sfx.listener
	var boars: Array[Monster] = [_spawn_imp(Vector2i(9, 9), "boar"), _spawn_imp(Vector2i(10, 9), "boar"), _spawn_imp(Vector2i(11, 9), "boar")]
	_rig._process(0.0)
	_rig.sfx.listener = Vector2i(10, 11)
	var now := Time.get_ticks_msec() + 100000
	_rig._idle_next = 0
	_rig._idle_heard.clear()
	var heard := _heard(func() -> void: _rig._idle_voices(now, 0.0))
	var idle := ["sfx.boar_grunt", "sfx.boar_root"]
	_check(heard.size() == Client3D.IDLE_AT_ONCE and heard.all(func(slot: String) -> bool: return slot in idle),
			"three boars at peace, every roll a hit: two sound (%s)" % [heard])
	var again := _heard(func() -> void: _rig._idle_voices(now + Client3D.IDLE_EVERY_MS, 0.0))
	_check(again.is_empty(), "a second on: still two in the span, none more (%s)" % [again])
	var later := now + Client3D.IDLE_SPAN_MS + Client3D.IDLE_EVERY_MS * 2
	for boar: Monster in boars:
		_rig._combat_at[boar.get_instance_id()] = later
	var fighting := _heard(func() -> void: _rig._idle_voices(later, 0.0))
	_check(fighting.is_empty(), "boars that just fought: silent (%s)" % [fighting])
	for boar: Monster in boars:
		_rig._combat_at.erase(boar.get_instance_id())
	var missed := _heard(func() -> void: _rig._idle_voices(later + Client3D.IDLE_EVERY_MS, 0.99))
	_check(missed.is_empty(), "the rolls missing: silent (%s)" % [missed])
	for boar: Monster in boars:
		World.despawn(boar)
	# 795 amended (3): a pack growls in turn, never two within IDLE_APART_MS;
	# a wolf sitting is quiet.
	var wolves: Array[Monster] = [_spawn_imp(Vector2i(9, 9), "wolf"), _spawn_imp(Vector2i(10, 9), "wolf"),
		_spawn_imp(Vector2i(11, 9), "wolf"), _spawn_imp(Vector2i(12, 9), "wolf")]
	_rig._process(0.0)
	var apart := int(SoundKit.IDLE_APART_MS["sfx.wolf_growl"])
	var t := later + Client3D.IDLE_SPAN_MS * 2
	_rig._idle_heard.clear()
	_rig._idle_slot_at.clear()
	var pack := _heard(func() -> void: _rig._idle_voices(t, 0.0))
	var soon := _heard(func() -> void: _rig._idle_voices(t + Client3D.IDLE_SPAN_MS + Client3D.IDLE_EVERY_MS, 0.0))
	var after := _heard(func() -> void: _rig._idle_voices(t + apart, 0.0))
	_check(pack == ["sfx.wolf_growl"] and soon.is_empty() and after == ["sfx.wolf_growl"],
			"four wolves at peace, every roll a hit: one growl, none more within %d ms, the next after (%s, %s, %s)" % [apart, pack, soon, after])
	for wolf: Monster in wolves:
		wolf.pose = Monster.Pose.SIT
	_rig._idle_heard.clear()
	_rig._idle_slot_at.clear()
	var sitting := _heard(func() -> void: _rig._idle_voices(t + apart * 3, 0.0))
	_check(sitting.is_empty(), "the pack sitting: no growl (%s)" % [sitting])
	for wolf: Monster in wolves:
		World.despawn(wolf)
	_rig.sfx.listener = listener_was
	_rig._process(0.0)
	_rig.sfx.hear_everything = hear_was


## 505 amended (4): a two-wide bridge's ends post only its outer sides (the
## hills' bridge read as a fenced box: four posts across each end). Facing
## an end the piece's -x is the walker's right (art-kit).
func _test_bridge_ends() -> void:
	print("
== a two-wide bridge's end posts at its sides (505 amended (4)) ==")
	var rect := Rect2i(88, 110, 2, 2)  # the hills': along x, rows 110 and 111
	var east := Vector2i(1, 0)
	var west := Vector2i(-1, 0)
	var picks := [Client3D.bridge_end_variant(rect, Vector2i(89, 110), east, 3), Client3D.bridge_end_variant(rect, Vector2i(89, 111), east, 3),
		Client3D.bridge_end_variant(rect, Vector2i(88, 110), west, 3), Client3D.bridge_end_variant(rect, Vector2i(88, 111), west, 3)]
	# Walking east the north row (110) is on the left (+x: 3), the south on the right (-x: 2); west, the other way round.
	_check(picks == [3, 2, 2, 3], "each end cell posts its outer side only, none mid-walkway (%s)" % [picks])
	var one := Rect2i(10, 10, 3, 1)
	_check(Client3D.bridge_end_variant(one, Vector2i(12, 10), east, 3) == 1 and Client3D.bridge_end_variant(rect, Vector2i(89, 110), east, 1) == 1,
		"a one-wide bridge's end posts both sides, and so does a kit without the one-post ends")


## 505 amended (3): a body stepping out of a ford onto dry ground drips (a
## drop now, another WADE_DRIP_SECONDS on); dry ground to dry ground no
## drip. A ford set on the player's next cell (the splash: sound_kit_test).
func _test_wade_drip() -> void:
	print("\n== out of a ford a body drips (505 amended (3)) ==")
	var player := _player()
	var puppet: Node3D = _rig._puppets.get(player.get_instance_id()) if player != null else null
	if puppet == null:
		_check(true, "no drawn player: skipped")
		return
	var id := player.get_instance_id()
	var dry := player.tile
	var ford := dry + Vector2i(1, 0)
	var other := dry - Vector2i(1, 0)
	var had_ford := World._fords.has(ford)
	var hear_was: bool = _rig.sfx.hear_everything
	_rig.sfx.hear_everything = true
	World._fords[ford] = true
	var heard := func(from: Vector2i) -> Array:
		_rig._last_tile[id] = from
		var before := _rig.sfx.played.size()
		_rig._step_sound(player, puppet)
		return _rig.sfx.played.slice(before).map(func(entry: Array) -> String: return str(entry[0]))
	var drips_was: int = _rig.drips
	var out_of: Array = heard.call(ford)
	_check(out_of.has("sfx.wade_drip") and _rig.drips == drips_was + 1, "out of the ford: a drip (%s)" % [out_of])
	var dry_step: Array = heard.call(other)
	_check(not dry_step.has("sfx.wade_drip") and _rig.drips == drips_was + 1, "dry ground to dry ground: no drip (%s)" % [dry_step])
	_rig._last_tile[id] = dry
	if not had_ford:
		World._fords.erase(ford)
	_rig.sfx.hear_everything = hear_was


## 804 amended (18): a work's strokes heard at its blows. Each work clip run
## through three cycles a frame (1/60 s) at a time on a drawn body set to its
## work: its stroke sound exactly at each blow of Client3D.WORK_STROKES, at the
## hands' height, none between; the work's clip without the work, none.
func _test_work_strokes() -> void:
	print("
== a work's strokes at its blows: the axe biting, the saw's push and pull, the hammer's face (804 amended (18)) ==")
	_check(Client3D.stroke_slot(null, "chop") == "sfx.chop_wood" and Client3D.stroke_slot(null, "saw") == "sfx.saw_stroke"
			and Client3D.stroke_slot(null, "hammer") == "sfx.hammer_wood" and Client3D.stroke_slot(null, "hoe") == ""
			and Client3D.STROKE_SLOTS.values().all(func(slot: String) -> bool: return SoundKit.has(slot)),
			"each work's stroke its slot; a work with none (the hoe) silent")
	var player := _player()
	var puppet: Node3D = _rig._puppets.get(player.get_instance_id()) if player != null else null
	if puppet == null or not puppet.has_meta("rig"):
		_check(true, "no drawn player: skipped")
		return
	var rig := puppet.get_meta("rig") as AnimRig
	var work_was: String = str(puppet.get_meta("work", ""))
	for word: String in Client3D.STROKE_SLOTS:
		var slot: String = Client3D.STROKE_SLOTS[word]
		var clip := str(Client3D.ACTIVITIES[word]["clip"])
		var length := rig.length(clip)
		if SoundKit.files(slot).is_empty() or length <= 0.0:
			_check(true, "%s: its takes are not synced here, or no %s clip: skipped" % [word, clip])
			continue
		puppet.set_meta("work", word)
		if puppet.has_meta("stroke_at"):
			puppet.remove_meta("stroke_at")
		var heard_at: Array[float] = []
		var right := true
		for frame in int(length * 3.0 * 60.0):
			rig.base_at(clip, frame / 60.0)
			rig.tree.advance(0.0)
			var before := _rig.sfx.played.size()
			_rig._stroke_sounds(player, puppet, rig)
			for entry: Array in _rig.sfx.played.slice(before):
				heard_at.append(fposmod(frame / 60.0, length) / length)
				right = right and entry[0] == slot
		var blows: Array = Client3D.WORK_STROKES[clip]
		var on_blows := heard_at.all(func(share: float) -> bool: return blows.any(func(blow: float) -> bool:
				return fposmod(share - blow, 1.0) < 1.5 / 60.0 / length))
		print("  %s (%s, %.2f s): %d strokes in 3 cycles, at %s of the clip" % [word, clip, length, heard_at.size(), heard_at.map(func(share: float) -> String: return "%.3f" % share)])
		# The first cycle's blow at its very start (the saw's push at 0) passes
		# before any frame was seen, so one fewer then.
		var want := blows.size() * 3 - (1 if blows.has(0.0) else 0)
		_check(right and on_blows and heard_at.size() == want, "%s: %s at each of its %d blows a cycle, none between (%d of %d)" % [word, slot, blows.size(), heard_at.size(), want])
	# The clip playing without its work (another body's clip, a test pose): none.
	puppet.set_meta("work", "")
	var quiet_before := _rig.sfx.played.size()
	for frame in 120:
		rig.base_at("Chop", frame / 60.0)
		rig.tree.advance(0.0)
		_rig._stroke_sounds(player, puppet, rig)
	_check(_rig.sfx.played.size() == quiet_before and not puppet.has_meta("stroke_at"), "the Chop clip with no work: silent")
	puppet.set_meta("work", work_was)


## 676 1b (Jeff on the first mixes: "the walking ones are approximately
## running speed"): worn armour clanks on the body's own footfalls, from its
## gait clip (Client3D.GAIT_FOOTFALLS), at a walk, a jog and a sprint, not
## once a cell. A headless walk of 3 s at each, the clanks counted against
## the clip's footfalls and the cells stepped.
func _test_armour_footfalls() -> void:
	print("
== worn armour clanks on the body's footfalls, at its gait, not once a cell (676 1b) ==")
	_check(Client3D.footfall_between(0.0, 0.1, [0.081]) and not Client3D.footfall_between(0.1, 0.5, [0.081, 0.581])
			and Client3D.footfall_between(0.9, 0.05, [0.027]) and not Client3D.footfall_between(0.3, 0.3, [0.3]),
			"a footfall passed between two frames' places, round the clip's end too; standing still none")
	var player := _player()
	var puppet: Node3D = _rig._puppets.get(player.get_instance_id()) if player != null else null
	if puppet == null or not puppet.has_meta("rig") or SoundKit.files("sfx.armour_plate").is_empty() or SoundKit.files("sfx.armour_mail").is_empty():
		_check(true, "no drawn player or the armour takes are not synced here: skipped")
		return
	var rig := puppet.get_meta("rig") as AnimRig
	var worn_was: String = player.worn
	var from := player.tile
	# The cadence a player's steps give (cells a second: loaded, its walk at
	# World.CLANK_WALK_TICKS, twice that), as _animate plays the gait.
	for cells: float in [1.5, World.TICK_RATE / World.CLANK_WALK_TICKS, 2.0 * World.TICK_RATE / World.CLANK_WALK_TICKS]:
		var table: Array = Client3D.paced(puppet.get_meta("gaits", Client3D.GAITS))
		var gait: Array = table[Client3D.gait_for("", cells / float(puppet.get_meta("pace", 1.0)), table)]
		var rate := clampf(cells / (float(gait[1]) * float(puppet.get_meta("pace", 1.0))) * ArtKit.feel("client3d.gait_rate", Client3D.GAIT_RATE), 0.3, 3.0)
		print("  %.1f cells a second: %s at x%.2f, a footfall every %.2f s (a cell every %.2f s)" % [cells, gait[0], rate, rig.length(str(gait[0])) / 2.0 / rate, 1.0 / cells])
	# Each gait clip run through three cycles a frame (1/60 s) at a time:
	# a clank exactly at each footfall, two a cycle, and the game's cadence
	# at a player's own paces (walk, jog, sprint), from the gait table.
	player.worn = "plate_armour"
	_rig._step_slot[player.get_instance_id()] = "sfx.footstep_stone_medium"
	var pace: float = puppet.get_meta("pace", 1.0)
	var gaits: Array = Client3D.paced(puppet.get_meta("gaits", Client3D.GAITS))
	for gait: Array in gaits:
		var clip := str(gait[0])
		var length := rig.length(clip)
		var heard_at: Array[float] = []
		if puppet.has_meta("footfall_at"):
			puppet.remove_meta("footfall_at")
		var together := true
		for frame in int(length * 3.0 * 60.0):
			rig.base_at(clip, frame / 60.0)
			rig.tree.advance(0.0)
			_rig._last_step_ms[player.get_instance_id()] = Time.get_ticks_msec()  # Still moving.
			var before := _rig.sfx.played.size()
			_rig._footfall_sounds(player, puppet, rig)
			var now_heard := _rig.sfx.played.slice(before).map(func(entry: Array) -> String: return str(entry[0]))
			if not now_heard.is_empty():
				heard_at.append(fposmod(frame / 60.0, length) / length)
				together = together and now_heard == ["sfx.footstep_stone_medium", "sfx.armour_plate"]
		var falls: Array = Client3D.GAIT_FOOTFALLS[clip]
		var on_falls := heard_at.all(func(share: float) -> bool: return falls.any(func(fall: float) -> bool: return share >= fall and share - fall < 1.5 / 60.0 / length))
		print("  %s: %d clanks in 3 cycles, at %s of the clip" % [clip, heard_at.size(), heard_at.map(func(share: float) -> String: return "%.3f" % share)])
		_check(heard_at.size() == 6 and on_falls and together, "%s: the footstep and the clank together at each of its two footfalls a cycle, none between (%d)" % [clip, heard_at.size()])
	# Stopped (no cell for FOOTFALL_MOVING_MS): its gait's last frames step no more.
	_rig._last_step_ms[player.get_instance_id()] = Time.get_ticks_msec() - Client3D.FOOTFALL_MOVING_MS - 1
	var stopped_before := _rig.sfx.played.size()
	for frame in 60:
		rig.base_at("Jog_Short", frame / 60.0)
		rig.tree.advance(0.0)
		_rig._footfall_sounds(player, puppet, rig)
	_check(_rig.sfx.played.size() == stopped_before, "stopped: the gait's last footfalls are silent")
	var hear_was: bool = _rig.sfx.hear_everything
	_rig.sfx.hear_everything = true
	# Each: the worn piece, seconds a cell, and its slot. The drawn body's own
	# footfalls are counted beside it, frame by frame, from its gait clip.
	for each: Array in [["plate_armour", 0.8, "sfx.armour_plate"], ["plate_armour", 0.25, "sfx.armour_plate"],
			["plate_armour", 0.15, "sfx.armour_plate"], ["mail_armour", 0.25, "sfx.armour_mail"], ["leather_armour", 0.25, ""]]:
		player.worn = each[0]
		var before := _rig.sfx.played.size()
		var start := Time.get_ticks_msec()
		var cells := 0
		var falls := 0
		var clank_ms: Array[int] = []
		var clips: Dictionary[String, int] = {}
		var was := ["", 0.0]
		var frames := 0
		while Time.get_ticks_msec() - start < 3000:
			frames += 1
			var seconds := (Time.get_ticks_msec() - start) / 1000.0
			if seconds >= cells * float(each[1]):
				cells += 1
				World._relocate(player, from + Vector2i(cells % 24 if cells % 24 <= 12 else 24 - cells % 24, 0))
			var heard_before := _rig.sfx.played.size()
			await get_tree().process_frame
			for entry: Array in _rig.sfx.played.slice(heard_before):
				if str(entry[0]).begins_with("sfx.armour_"):
					clank_ms.append(Time.get_ticks_msec() - start)
			var clip := rig.base_clip()
			clips[clip] = int(clips.get(clip, 0)) + 1
			var length := rig.length(clip)
			var at := fposmod(rig.base_position(), length) / length if length > 0.0 else 0.0
			if was[0] == clip and Client3D.footfall_between(float(was[1]), at, Client3D.GAIT_FOOTFALLS.get(clip, [])):
				falls += 1
			was = [clip, at]
		var clanks := _rig.sfx.played.slice(before).filter(func(entry: Array) -> bool: return str(entry[0]).begins_with("sfx.armour_"))
		var footsteps := _rig.sfx.played.slice(before).filter(func(entry: Array) -> bool: return str(entry[0]).begins_with("sfx.footstep"))
		var right_slot := clanks.all(func(entry: Array) -> bool: return entry[0] == each[2])
		# The drawn footfalls are sampled here a frame after the game's own, on the
		# wall clock: a loaded machine (a suite beside it) draws so few frames that
		# this sampling can miss every one the game heard (release: 1 footstep and
		# 0 footfalls counted, 2026-10-28). So the walk shows by either, and is asked
		# for only at 30 frames a second or more. The clank going with the footstep
		# holds at any rate; each clip's footfalls are checked above, a frame at a time.
		var smooth := frames >= 90
		var drawn := falls > 0 or footsteps.size() > 0 or not smooth
		if not smooth:
			print("  %s, a cell every %.2f s: the walk's drawn footfalls skipped: %.0f fps" % [each[0], each[1], frames / 3.0])
		print("  %s, a cell every %.2f s: %d cells, %d frames, %d footfalls drawn, %d footsteps, %d clanks at %s ms; clips by frames %s" % [
				each[0], each[1], cells, frames, falls, footsteps.size(), clanks.size(), clank_ms, clips])
		if each[2] == "":
			_check(clanks.is_empty() and drawn and footsteps.size() <= cells, "%s: no clank, footsteps no more than a cell's (%d, %d footfalls)" % [each[0], footsteps.size(), falls])
		else:
			# Live, the body moved by teleports (World._relocate): its drawn gait wavers, so
			# the count against its footfalls is printed; the clips' own are checked above.
			_check(right_slot and drawn and clanks.size() == footsteps.size() and clanks.size() <= cells,
					"%s, a cell every %.2f s: the footstep and the clank together, no more than a cell's (%d footsteps, %d clanks, %d footfalls, %d cells)" % [
					each[0], each[1], footsteps.size(), clanks.size(), falls, cells])
		World._relocate(player, from)
		await _frames(30)
	player.worn = worn_was
	_rig.sfx.hear_everything = hear_was

func _test_monster_death() -> void:
	print("\n== a monster's death: it falls, lies, sinks; its tile is free at once ==")
	var player := _player()
	var imp := _spawn_imp(Vector2i(9, 4))
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets[imp.get_instance_id()]
	var heard := _heard(func() -> void: World.damage(imp, 999, player, &"attack"); _rig._process(0.0))
	_check("sfx.goblin_death" in heard, "a death sound (%s)" % [heard])
	_check(World.is_free(Vector2i(9, 4)), "its tile is free at once: a corpse never blocks")
	_check(is_instance_valid(puppet) and puppet.has_meta("corpse") and puppet.get_node_or_null("Pick") == null,
			"its puppet is a corpse, with nothing to pick")
	await get_tree().create_timer(Client3D.FALL_SECONDS + 0.15).timeout
	_check(is_equal_approx(puppet.rotation.z, PI * 0.5), "on its side after %d ms (%.2f rad)" % [
			roundi(Client3D.FALL_SECONDS * 1000.0), puppet.rotation.z])
	var lying := puppet.position.y
	await get_tree().create_timer(1.0).timeout
	_check(is_instance_valid(puppet) and is_equal_approx(puppet.position.y, lying), "and lies still")
	await _death_after_despawn()


## The death message can come after the despawn: the puppet waits for it.
func _death_after_despawn() -> void:
	var imp := _spawn_imp(Vector2i(10, 4))
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets[imp.get_instance_id()]
	var entity_name := String(imp.name)
	World.despawn(imp)
	_rig._process(0.0)
	await _frames(3)
	_check(is_instance_valid(puppet) and not puppet.has_meta("corpse"), "despawned before its death came: kept a moment, still")
	_rig.on_death({"entity": entity_name, "tile": [10, 4], "kind": "monster", "say": ""})
	_check(puppet.has_meta("corpse"), "and falls when the death comes")
	var other := _spawn_imp(Vector2i(10, 5))
	_rig._process(0.0)
	var gone: Node3D = _rig._puppets[other.get_instance_id()]
	World.despawn(other)
	_rig._process(0.0)
	await get_tree().create_timer(Client3D.DEPARTED_SECONDS + 0.2).timeout
	_check(not is_instance_valid(gone), "gone without a death: freed after %d ms" % roundi(Client3D.DEPARTED_SECONDS * 1000.0))


## A charm's aura (789): a cool, steady light over its wearer after
## sunset, the followed player's own always among the real lights; none
## with no aura.
func _test_aura() -> void:
	print("\n== a charm's aura: a cool light round the wearer at night, always the player's own ==")
	var player := _player()
	_rig._process(0.0)
	var id := player.get_instance_id()
	var puppet: Node3D = _rig._puppets[id]
	var night := _rig._night
	_rig._night = true
	player.aura = 0.67
	_rig._sync_aura(player, puppet, id)
	var glow := puppet.get_node_or_null("AuraGlow") as Node3D
	_check(glow != null and glow.visible and _rig._carriers.get(id) == glow, "a worn aura at night: its marker, kept with the carried lanterns")
	_rig._carried_clock = Client3D.CARRIED_PICK
	_rig._light_carriers(0.0)
	var want := Client3D.aura_glow(0.67)
	var lit := _rig._carried_lights.filter(func(light: OmniLight3D) -> bool:
		return light.visible and light.light_color == Client3D.AURA_COLOUR)
	_check(lit.size() == 1 and is_equal_approx((lit[0] as OmniLight3D).omni_range, want.x) and is_equal_approx((lit[0] as OmniLight3D).light_energy, want.y)
			and not (glow.get_node("Disc") as Node3D).visible,
			"lit by a real light, cool, %.1f m at aura 0.67, no ground glow" % want.x)
	var motes := puppet.get_node_or_null("AuraMotes") as GPUParticles3D
	_check(motes != null and motes.visible and motes.emitting and motes.amount == Client3D.aura_motes(0.67),
			"and its motes round the body, %d at aura 0.67 (789 amended)" % Client3D.aura_motes(0.67))
	_rig._night = false
	var outdoor := _rig._outdoor
	_rig._outdoor = true
	_rig._sync_aura(player, puppet, id)
	_check(motes.visible and not glow.visible, "by day in the open: no light, the motes still")
	_rig._outdoor = outdoor
	_rig._night = true
	player.aura = 0.0
	_rig._sync_aura(player, puppet, id)
	_check(not glow.visible and not _rig._carriers.has(id), "no aura, no light")
	_check(not motes.visible and not motes.emitting, "nor motes")
	_rig._night = night
	_rig._carried_clock = Client3D.CARRIED_PICK
	_rig._light_carriers(0.0)


## The cold forge woken (813 amended (7)): dungeon's hook on a bare holder
## (its piece is art-kit's to come), caught in view, then as found lit.
func _test_forge() -> void:
	print("\n== the cold forge woken: a flare and sparks as it catches, then a steady fire ==")
	var forge := Node3D.new()
	forge.name = "TestForge"
	_rig.add_child(forge)
	_rig._show_forge(forge, true, true)
	var fire := forge.get_node_or_null("ForgeFire") as Node3D
	var light := fire.get_node_or_null("Light") as OmniLight3D if fire != null else null
	_check(light != null and light.light_color == Client3D.FORGE_COLOUR and light in _rig._forge_lights
			and fire.position == Client3D.FORGE_HEARTH and fire.get_node_or_null("Burst") != null and fire.get_node_or_null("Sparks") != null,
			"caught: a forge-orange light at the hearth, a burst of sparks and their trickle")
	if light == null:
		forge.free()
		return
	await get_tree().create_timer(Client3D.FORGE_CATCH + 0.1).timeout
	var peak := float(light.get_meta(&"base"))
	_check(peak > Client3D.FORGE_ENERGY * 1.5 and light.omni_range > Client3D.FORGE_RANGE,
			"the flare: brighter than it burns (%.1f), reaching further (%.1f m)" % [peak, light.omni_range])
	await get_tree().create_timer(Client3D.FORGE_SETTLE + 0.1).timeout
	_check(is_equal_approx(float(light.get_meta(&"base")), Client3D.FORGE_ENERGY) and is_equal_approx(light.omni_range, Client3D.FORGE_RANGE),
			"then it settles to its fire: %.1f, %.0f m" % [Client3D.FORGE_ENERGY, Client3D.FORGE_RANGE])
	_rig._show_forge(forge, true, false)
	_check(forge.get_children().filter(func(child: Node) -> bool: return child.name.begins_with("ForgeFire")).size() == 1, "lit twice is lit once")
	_rig._show_forge(forge, false, false)
	_check(forge.get_node_or_null("ForgeFire") == null and not light in _rig._forge_lights and not light in _rig._shadow_lights,
			"cold again (a regen): no fire left, nor its shadow")
	var hearth := Marker3D.new()
	hearth.name = "hearth"
	forge.add_child(hearth)
	_rig._show_forge(forge, true, false)
	fire = hearth.get_node_or_null("ForgeFire") as Node3D
	light = fire.get_node_or_null("Light") as OmniLight3D if fire != null else null
	_check(light != null and is_equal_approx(float(light.get_meta(&"base")), Client3D.FORGE_ENERGY) and fire.get_node_or_null("Burst") == null,
			"found already lit: at the piece's hearth, burning steady, no flare or burst")
	forge.free()
	_rig._flicker_fires(0.016)
	_check(_rig._forge_lights.is_empty(), "the forge freed with its room: its light dropped")


func _test_companion_death() -> void:
	print("\n== a companion's death: the fall, a last line, her lantern dropped ==")
	var pet := _companion()
	_check(pet != null, "the host has a companion")
	if pet == null:
		return
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets[pet.get_instance_id()]
	var lantern := puppet.get_node_or_null("Lantern") as OmniLight3D
	var heard := _heard(func() -> void: World.damage(pet, 999, null, &"attack"); _rig._process(0.0))
	_check("sfx.death_companion" in heard and not heard.any(func(slot: String) -> bool: return slot.begins_with("voice.last_breath")),
			"her death sound, a sudden death's, no last breath (%s)" % [heard])
	var words: String = _main.bubbles.text_of(puppet.get_instance_id())
	_check(words in Main.COMPANION_DEATH_LINES, "a last line, in a bubble over her body: %s" % words)
	_check(lantern != null and lantern.get_parent() == _rig, "her lantern is dropped, off the body")
	await get_tree().create_timer(Client3D.LANTERN_OUT_SECONDS + 0.2).timeout
	_check(not is_instance_valid(lantern), "and goes out")


## Mortally Wounded (587): the colour drains while the local player lies
## downed, the camera where it was; back when they are up again.
func _test_down_grey() -> void:
	print("\n== the local player downed: the colour drains under the Mortally Wounded screen, the camera stays ==")
	var player := _player()
	_rig._process(0.0)
	var size := _rig._camera.size
	World.damage(player, 999, null, &"attack")
	_rig._process(0.0)
	_check(World.is_downed(player) and not _rig._mourning, "downed first (587), not dead: no mourning")
	await get_tree().create_timer(1.0).timeout
	_check(_rig._down > 0.0 and _rig._environment.adjustment_saturation < 1.0 and is_equal_approx(_rig._camera.size, size),
			"after a second: paler (saturation %.2f), the camera not pulled back (%.1f)" % [_rig._environment.adjustment_saturation, _rig._camera.size])
	World.raise_downed(player, player.max_hp)  # Up again, by a revival (544 amended: a window set over by hand left it on World._downed).
	await get_tree().create_timer(Client3D.MOURN_RETURN_SECONDS + 0.3).timeout
	_check(not World.is_downed(player) and is_equal_approx(_rig._environment.adjustment_saturation, 1.0) and is_zero_approx(_rig._down),
			"up again: the colour back (%.2f)" % _rig._environment.adjustment_saturation)


func _test_player_death() -> void:
	print("\n== the local player's death: the camera pulls back and the colour drains ==")
	var player := _player()
	_rig._process(0.0)
	var size := _rig._camera.size
	World.damage(player, 999, null, &"attack")
	# Downed first (decision 587, Mortally Wounded); Bleed Out is the death.
	_rig._process(0.0)
	var body := str(_rig._puppets[player.get_instance_id()].get_meta("body", "male"))
	var heard := _heard(func() -> void: _main._on_command(player, "bleed_out", {}); _rig._process(0.0))
	_check(("voice.last_breath_%s" % body) in heard and not ("voice.death_%s" % body) in heard and not "sfx.death_player" in heard,
			"bled out: a last breath, not the cry or the blow (628; %s)" % [heard])
	_check(_rig._mourning, "mourning")
	await get_tree().create_timer(1.0).timeout
	_check(_rig._camera.size > size and _rig._environment.adjustment_saturation < 1.0,
			"after a second: pulled back (%.1f from %.1f) and paler (saturation %.2f)" % [
				_rig._camera.size, size, _rig._environment.adjustment_saturation])
	for i in Main.RESPAWN_TICKS + 2:
		World.step()
	await _frames(2)
	_check(_player() != null and not _rig._mourning, "back on respawn")
	await get_tree().create_timer(Client3D.MOURN_RETURN_SECONDS + 0.2).timeout
	_check(is_equal_approx(_rig._environment.adjustment_saturation, 1.0) and is_equal_approx(_rig._camera.size, size),
			"colour and size as they were (%.2f, %.1f)" % [_rig._environment.adjustment_saturation, _rig._camera.size])


## Every way's glimpse meets our ground (327 amended; Jeff, after 745: "the
## castle zone after foothills looks crazy since it falls down a steep cliff
## to the castle between zones"): on every outdoor level of the world plane,
## each link's glimpse, at the lane's first cell and at its own land's
## arrival past the lane's far end, stands within GLIMPSE_MEET of our drawn
## ground at our last land cell along the way, and so does the ground the
## room keeps for those cells (the forest round it stands there).
const GLIMPSE_MEET := 0.3


func _test_world_map_kept() -> void:
	print("\n== the far landmarks' and glimpses' WorldMap kept until a level changes ==")
	var first := Client3D._world_map()
	_check(Client3D._world_map() == first, "asked again with nothing changed: the same build")
	_check(first.areas.has("castle"), "it holds the castle")
	# The castle made in code in its place (as a regenerated or sent level is): built again.
	var made := Level.source("castle")
	Level.register("castle", (made["layout"] as Image).duplicate(), made["height"], made["config"], made.get("relief"))
	var registered := Client3D._world_map()
	Level.unregister("castle")
	_check(registered != first and registered.areas.has("castle"), "the castle registered: built again")
	var back := Client3D._world_map()
	_check(back != registered and back.areas.has("castle"), "the castle's registration gone: built again")
	_check(Client3D._world_map() == back, "and kept again")


func _test_glimpses_meet() -> void:
	print("\n== every glimpse meets our ground at its way, within %.1f m (327 amended) ==" % GLIMPSE_MEET)
	var zones: Array = (Level.world_plane().get("zones", {}) as Dictionary).keys()
	zones.sort()
	for zone: String in zones:
		if not Level.exists(zone):
			continue
		var level := Level.load_level(zone)
		_rig.rebuild(level["terrain"], level["centre"])
		var misses: Array[String] = []
		var measured := 0
		for i in _rig._glimpse_plans.size():
			var plan: Dictionary = _rig._glimpse_plans[i]
			var raised: Dictionary = plan.get("raised", {})
			if raised.is_empty() or i >= _rig._glimpses.size():
				continue
			var view: Client3D = _rig._glimpses[i]
			var meet: Vector2i = raised["meet"]
			var lane_end: Vector2i = raised["lane_end"]
			var first := meet + (lane_end - meet) / Client3D.GLIMPSE_GAP
			var ours: float = _rig._height_in(meet, Vector2(meet))
			var spots := {"the way": first}
			if (plan["cells"] as Dictionary).has(raised["arrive"]):
				spots["their arrival"] = raised["arrive"]
			for what: String in spots:
				var cell: Vector2i = spots[what]
				measured += 1
				var drawn: float = view.position.y + view._height_in(cell, Vector2(cell))
				if absf(drawn - ours) > GLIMPSE_MEET:
					misses.append("%s's %s at %s: %.2f, ours %.2f" % [plan["to"], what, cell, drawn, ours])
				if absf(_rig._elevation(cell) - drawn) > GLIMPSE_MEET:
					misses.append("%s's %s at %s kept at %.2f for the forest, drawn %.2f" % [plan["to"], what, cell, _rig._elevation(cell), drawn])
		# Every link's glimpse measured (a plan with no "raised" would pass unmeasured).
		_check(misses.is_empty() and measured >= 2 * _rig._glimpses.size(),
				"%s: its %d glimpses meet our ground (%d spots; %s)" % [zone, _rig._glimpses.size(), measured, "; ".join(misses) if not misses.is_empty() else "all within"])
		# No wall of theirs on the lane (the seam tour, 2026-11-01: the
		# castle's outer wall, the lane past it, stood as a lone wall by the
		# foothills' north road, the wilds' likewise by its south road).
		var on_lane: Array[String] = []
		var lanes := 0
		for plan: Dictionary in _rig._glimpse_plans:
			var lane := {}
			for cell: Vector2i in plan.get("lane", []):
				lane[cell] = true
			lanes += lane.size()
			for key: Vector3i in plan["terrain"]["edges"]:
				var sides := Terrain.edge_cells(key)
				if lane.has(sides[0]) or lane.has(sides[1]):
					on_lane.append("%s's %s" % [plan["to"], key])
		_check(on_lane.is_empty() and (lanes > 0 or _rig._glimpses.is_empty()),
				"%s: no glimpse's wall stands on its lane (%d lane cells; %s)" % [zone, lanes, ", ".join(on_lane) if not on_lane.is_empty() else "none"])
	_rig.rebuild(_main._terrain, Vector2i.ZERO)

## The ground's fields apart from the members (660 step 2 A): _ground_fields
## writes none (what it makes it returns, put in place by
## _apply_ground_fields), and makes the same bytes on one thread as on the
## pool's (Client3D.field_threads), so perf's arrival can run it on a
## worker. (That it makes what the build made before is the refactor's
## digest, on every level: decision 660.)
func _test_ground_fields() -> void:
	print("\n== the ground's fields (660 step 2 A): no member written, the same on one thread or many ==")
	var held := Level.load_level("held")
	var kinds: Dictionary = held["terrain"]["kinds"]
	_rig.rebuild(held["terrain"], held["centre"])
	var threads_was := Client3D.field_threads
	var made: Array[Dictionary] = []
	var untouched := true
	for threads: int in [1, 0]:
		Client3D.field_threads = threads
		var input: Dictionary = _rig._ground_input(kinds)
		var before := [_rig._corners.duplicate(), _rig._grounds.duplicate(), _rig._ground_kinds.duplicate(), _rig._floor_bytes,
			_rig._curve_kept.size(), _rig._road_kept.size(), _rig._edge_kept.size(), _rig._shore_heights.duplicate(), _rig._shore_image]
		made.append(_rig._ground_fields(input))
		var after := [_rig._corners, _rig._grounds, _rig._ground_kinds, _rig._floor_bytes,
			_rig._curve_kept.size(), _rig._road_kept.size(), _rig._edge_kept.size(), _rig._shore_heights, _rig._shore_image]
		for k in before.size():
			untouched = untouched and var_to_bytes(before[k]) == var_to_bytes(after[k]) if not before[k] is Image else before[k] == after[k]
	Client3D.field_threads = threads_was
	_rig._apply_ground_fields(made[-1])
	var differ: Array[String] = []
	for key: String in made[0]:
		var a: Variant = made[0][key]
		var b: Variant = made[1][key]
		if a is Image:
			a = (a as Image).get_data()
			b = (b as Image).get_data() if b != null else null
		if var_to_bytes(a) != var_to_bytes(b):
			differ.append(key)
	_check(untouched, "_ground_fields leaves the members as they were (corners, grounds, kinds, floor bytes, memos, shore)")
	_check(differ.is_empty() and made[0]["shore_heights"].size() > 0 and made[0]["road_image"] != null and made[0]["edge_image"] != null,
			"one thread and the pool make the same bytes, Held's shore, roads and forest edge among them (differ: %s)" % [differ])
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


func _test_scatter() -> void:
	print("\n== scatter off the grid by the ground, never on water; trees varied; the land runs into the forest floor ==")
	var castle := Level.load_level("castle")
	var terrain: Dictionary = castle["terrain"]
	# Every kind's mesh made with the room's art, before the view grows any
	# (the first tuft's art, made in _grow_scatter on arrival, was a 218 ms frame).
	Client3D._scatter_meshes.clear()
	Client3D._warmed = false
	_rig.rebuild(terrain, castle["centre"])
	var unmade: Array[String] = []
	for kind: String in Client3D.SCATTER_SIZES:
		if not Client3D._scatter_meshes.has(kind):
			unmade.append(kind)
	_check(unmade.is_empty(), "the room's build makes every scatter kind's mesh (not made: %s)" % [unmade])
	_rig._scatter_all()
	var water: Dictionary = {}
	for cell: Vector2i in terrain["water"]:
		water[cell] = true
	var counts: Dictionary[String, int] = {}
	var wet := 0
	var off_grid := 0
	# (Headless, a MultiMesh keeps no transforms: where the plan put them.)
	for chunk: Vector2i in _rig._scatter_chunks:
		var plan := _rig._scatter_plan(chunk)
		for kind: String in plan:
			counts[kind] = counts.get(kind, 0) + plan[kind].size()
			for item: Array in plan[kind]:
				var at: Vector2 = item[1]
				var cell := Vector2i(roundi(at.x), roundi(at.y))
				wet += 1 if water.has(cell) else 0
				off_grid += 1 if absf(at.x - cell.x) > 0.05 or absf(at.y - cell.y) > 0.05 else 0
	_check(not _rig._room.find_children("Scatter_*", "MultiMeshInstance3D", false, false).is_empty(), "drawn by MultiMesh, a chunk and kind")
	var total: int = counts.values().reduce(func(a: int, b: int) -> int: return a + b, 0)
	_check(counts.get("tuft", 0) > 0 and counts.get("flower", 0) > 0 and counts.get("stone", 0) > 0 and counts.get("root", 0) > 0
			and counts.get("reeds", 0) > 0, "tufts, flowers, stones, roots, and reeds by the water (%s)" % counts)
	_check(wet == 0 and off_grid > total * 0.9, "none on water, and off the cells' middles (%d of %d)" % [off_grid, total])
	# Art's scatter is coloured by the palette through UVs; the scatter draws
	# vertex colours, so they are baked in (white tufts on 2026-10-18).
	var pale: Array[String] = []
	for kind: String in ["tuft", "flower", "stone", "root", "reeds"]:
		var mesh := Client3D._scatter_mesh(kind)
		var colours: Variant = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		if colours == null or (colours as PackedColorArray).is_empty() or Array(colours).all(func(c: Color) -> bool: return c.r > 0.95 and c.g > 0.95 and c.b > 0.95):
			pale.append(kind)
	_check(pale.is_empty(), "every scatter kind's mesh carries its colours, art or not (white: %s)" % [pale])
	var forest_cells := _rig._ground_cells.size() - _rig._ground_water_end
	_check(forest_cells > 0, "the ground runs into the forest, its floor blended in (%d cells)" % forest_cells)
	var sizes: Dictionary[float, bool] = {}
	var leaning := 0
	for tree: Node3D in _rig._trees.values():
		sizes[snappedf(tree.scale.y, 0.05)] = true
		leaning += 1 if absf(tree.rotation.x) + absf(tree.rotation.z) > 0.02 else 0
	_check(sizes.size() > 5 and leaning > _rig._trees.size() / 2, "trees of many sizes (%d), most leaning a little" % sizes.size())
	var inside := 0
	for cell: Vector2i in _rig._saplings:
		var sapling: Node3D = _rig._saplings[cell]
		var off := Vector2(sapling.position.x - cell.x, sapling.position.z - cell.y)
		if not _rig._land.has(cell) and absf(off.x) <= 0.451 and absf(off.y) <= 0.451 and off.length() > 0.1 \
				and sapling.scale.y < _rig._trees[cell].scale.y:
			inside += 1
	_check(_rig._saplings.size() > 0 and inside == _rig._saplings.size(),
			"saplings at the edge, smaller than its trees, off their void cell's middle and in it (%d of %d)" % [inside, _rig._saplings.size()])
	# Dead wood (277 amended): stumps, never on the land; logs and dead trees
	# only once their slots have art.
	var wood := _rig._room.find_children("Deadwood_*", "", false, false)
	var on_land := wood.filter(func(each: Node3D) -> bool: return _rig._land.has(Vector2i(roundi(each.position.x), roundi(each.position.z))))
	_check(not wood.is_empty() and on_land.is_empty() and Client3D._deadwood_drawn("tree.stump"),
			"stumps in the forest and at its edge, none on the land (%d)" % wood.size())
	for slot in ["tree.log", "tree.dead"]:
		_check(Client3D._deadwood_drawn(slot) == (ArtKit.filled_by(slot) != "placeholder"), "%s drawn only with art (%s)" % [slot, ArtKit.filled_by(slot)])
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


func _test_wall_runs() -> void:
	print("\n== walls: a run of wall is one mesh, swept, varied; a breach is rubble, never a way through ==")
	var castle := Level.load_level("castle")
	var terrain: Dictionary = castle["terrain"]
	_rig.rebuild(terrain, castle["centre"])
	var runs: Dictionary[Node3D, int] = {}
	for key: Vector3i in _rig._walls:
		runs[_rig._walls[key]] = runs.get(_rig._walls[key], 0) + 1
	var stood := 0
	for key: Vector3i in terrain["edges"]:
		if terrain["edges"][key] == Terrain.Edge.WALL and not _rig._is_outline(key):
			stood += 1 if _rig._walls.has(key) else 0
	_check(stood > 0 and stood == _rig._walls.size() and runs.size() < stood / 2,
			"every wall edge stands, in runs: %d edges, %d meshes" % [stood, runs.size()])
	var heights: Dictionary[float, bool] = {}
	for run: Node3D in runs:
		var top := -INF
		var body := run.get_node("Body") as MeshInstance3D
		for point: Vector3 in (body.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			top = maxf(top, (body.global_transform * point).y)
		heights[snappedf(top, 0.05)] = true
	_check(heights.size() > 3, "the runs' tops are not all one height (%d heights)" % heights.size())
	# A breach: the sim's wall stays, and its rubble stands at least waist high.
	print("  (breaches: %s)" % [_rig._wall_breaches])
	for key: Vector3i in _rig._wall_breaches:
		var middle := Client3D._edge_midpoint(key)
		var top := _drawn_top(key, 0.5)
		_check(terrain["edges"].get(key) == Terrain.Edge.WALL and top >= _rubble_low(key),
				"the breach at %s is rubble %.2f m high where the sim keeps its wall" % [key, top])
	# The castle's walls are its set's: half a metre thick (_edge_bounds).
	var some: Vector3i = _rig._walls.keys()[0]
	var castle_width := _rig._edge_bounds(some).size.x if some.z == Terrain.EAST else _rig._edge_bounds(some).size.z
	_check(_rig._set_of(some) == "castle" and is_equal_approx(castle_width, 0.5), "a map's walls are in its set, castle by default, %.2f m thick" % castle_width)
	# In the wood set (a home's): no breach, no broken top, the cap at the
	# profile's top less its sag, 0.3 m thick at the foot, leaning a little.
	for key: Vector3i in terrain["edges"]:
		if terrain["edges"][key] == Terrain.Edge.WALL:
			_rig._wall_sets[key] = "wood"
	_rig.rebuild(terrain, castle["centre"])
	var level := true
	var thin := true
	var leant := 0
	var sag: float = Client3D._wall_set("wood")["variation"]["sag"]
	var wood_runs: Dictionary[Node3D, bool] = {}
	for key: Vector3i in _rig._walls:
		wood_runs[_rig._walls[key]] = true
	for run: Node3D in wood_runs:
		var body := run.get_node("Body") as MeshInstance3D
		var top := -INF
		var low_top := INF
		var top_x := 0.0
		for point: Vector3 in (body.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			top = maxf(top, point.y)
			if point.y > Client3D.WALL_HEIGHT - 0.1:
				low_top = minf(low_top, point.y)
				top_x = maxf(top_x, absf(point.x))
			if point.y < 0.001:
				thin = thin and absf(point.x) <= 0.15 + 0.0001
		level = level and top <= Client3D.WALL_HEIGHT + 0.0001 and low_top >= Client3D.WALL_HEIGHT - sag - 0.0001
		leant += 1 if absf(top_x - 0.15) > 0.005 else 0
	var bounds := _rig._edge_bounds(some)
	_check(_rig._wall_breaches.is_empty() and level, "wood walls: no breach, no broken top, every cap within %.2f m of %s m" % [sag, Client3D.WALL_HEIGHT])
	_check(thin and is_equal_approx(bounds.size.x if some.z == Terrain.EAST else bounds.size.z, 0.3),
			"0.3 m thick, as the set's profile, in what hides the player too")
	_check(leant > wood_runs.size() / 3, "most runs lean a little (%d of %d)" % [leant, wood_runs.size()])
	_rig._wall_sets.clear()
	_rig.rebuild(terrain, castle["centre"])
	# A town's walls broken or in rubble (buildings: _wall_states and
	# rebuild_walls): that line's runs drawn again, the rest kept.
	var by_run: Dictionary[Node3D, Array] = {}
	for key: Vector3i in _rig._walls:
		if not by_run.has(_rig._walls[key]):
			by_run[_rig._walls[key]] = []
		by_run[_rig._walls[key]].append(key)
	var long_run: Array[Vector3i] = []
	for run: Node3D in by_run:
		if by_run[run].size() >= 5:
			long_run.assign(by_run[run])
			break
	long_run.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return Client3D._along(a) < Client3D._along(b))
	_check(long_run.size() >= 5, "a run of five walls or more (%d)" % long_run.size())
	if long_run.size() >= 5:
		var rubble_at := long_run[2]
		var broken_at := long_run[4]
		var kept: Dictionary[Node3D, bool] = {}
		for key: Vector3i in _rig._walls:
			if Client3D._line_of(key) != Client3D._line_of(rubble_at):
				kept[_rig._walls[key]] = true
		var before: Node3D = _rig._walls[rubble_at]
		_rig._wall_states[rubble_at] = "rubble"
		_rig._wall_states[broken_at] = "broken"
		_rig.rebuild_walls([rubble_at, broken_at])
		_check(not before.visible and _rig._walls[rubble_at] != before and not _rig._occluders_built or _rig._occluders.all(func(entry: Array) -> bool: return entry[0] != before),
				"the old run hidden, a new one in its place, and what can fade indexed again")
		var tops := {}
		for key: Vector3i in [rubble_at, broken_at]:
			var middle := Client3D._edge_midpoint(key)
			tops[key] = _drawn_top(key, 0.45)
		var cap: float = Client3D._wall_set("castle")["cap"]
		_check(rubble_at in _rig._wall_breaches and tops[rubble_at] >= _rubble_low(rubble_at) and tops[rubble_at] <= Client3D.WALL_RUBBLE_HIGH + 0.01
				and terrain["edges"].get(rubble_at) == Terrain.Edge.WALL, "rubble: a bank %.2f m high, never a way through, the sim's wall kept" % tops[rubble_at])
		_check(tops[broken_at] >= cap / 3.0 and tops[broken_at] < cap, "broken: a stub %.2f m high, never under a third of the wall" % tops[broken_at])
		var still := 0
		for key: Vector3i in _rig._walls:
			if Client3D._line_of(key) != Client3D._line_of(rubble_at) and kept.has(_rig._walls[key]):
				still += 1
		var others := _rig._walls.keys().filter(func(key: Vector3i) -> bool: return Client3D._line_of(key) != Client3D._line_of(rubble_at)).size()
		_check(still == others, "every run on another line kept as it was (%d of %d edges)" % [still, others])
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		_check(not is_instance_valid(before), "and the old run freed, frames later")
		# The room rebuilt before then: the old runs went with the room.
		_rig.rebuild_walls([rubble_at])
		_rig.rebuild(terrain, castle["centre"])
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		_rig._wall_states.clear()
	_rig.rebuild(terrain, castle["centre"])
	runs.clear()
	for key: Vector3i in _rig._walls:
		runs[_rig._walls[key]] = 1
	# A run fades as one, by its see-through copy (188).
	var run: Node3D = runs.keys()[0]
	var body := run.get_node("Body") as MeshInstance3D
	_rig._set_near(run, true)
	var faded := body.material_override as BaseMaterial3D
	_check(faded != null and faded.albedo_color.a < 1.0 and faded.next_pass != null, "a near run is see-through, its depth drawn first")
	_rig._set_near(run, false)
	_check((body.material_override as BaseMaterial3D).albedo_color.a == 1.0, "and solid again after")
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## The rock mass (769, terrain's side): a small indoor level with "mass":
## "rock", a tunnel bending into a chamber: rock over every void cell and
## MASS_APRON past the map, none over the open, its edge under the cave
## walls' ridge, darker away from the open but never black; without the
## key, or outdoors, none.
## A gap in a cave's roof (797): a light straight down per skylight, its
## cone the gap's, a dusty shaft by day; none outdoors or without the key.
func _test_skylights() -> void:
	print("
== skylights: a light down through a gap in a cave's roof ==")
	var map := LevelMap.new(Vector2i(14, 12))
	for x in range(2, 12):
		for y in range(2, 10):
			map.set_cell(Vector2i(x, y), "stone")
	var config := {"outdoor": false, "walls": "cave", "floors": "cave", "skylights": [{"at": [7, 6], "radius": 3}]}
	var terrain: Dictionary = Level.parse(map.to_image(), null, config)["terrain"]
	_rig.rebuild(terrain, Vector2i(7, 6))
	var light := _rig._shafts.get_node_or_null("Skylight_7_6") as SpotLight3D if _rig._shafts != null else null
	_check(light != null and is_equal_approx(light.spot_angle, Client3D.skylight_angle(3.0))
			and light.position.y > _rig._tile_position(Vector2i(7, 6)).y + 5.0 and is_equal_approx(light.position.x, 7.0),
			"one light straight down over the gap, its cone the gap's (%s)" % [light])
	var was := DayNight.light
	DayNight.light = DayNight.NIGHT
	_rig._light_skylights(Client3D.SKYLIGHT_PICK)
	var night := light.light_energy if light != null else 0.0
	# 797 amended (2): the dust in the beam, glowing by day, gone at night.
	var motes := _rig._shafts.get_node_or_null("Motes_7_6") as GPUParticles3D if _rig._shafts != null else null
	var motes_night := motes != null and motes.visible
	DayNight.light = 1.0
	_rig._light_skylights(Client3D.SKYLIGHT_PICK)
	var day := light.light_energy if light != null else 0.0
	var glow: Color = _rig._mote_material.albedo_color if _rig._mote_material != null else Color.BLACK
	DayNight.light = was
	_check(night > 0.0 and day > night * 2.0, "faint at night, never out; bright by day (%.2f, %.2f)" % [night, day])
	var foot := _rig._tile_position(Vector2i(7, 6))
	_check(motes != null and motes.amount == Client3D.MOTE_COUNT and not motes_night and motes.visible
			and is_equal_approx(motes.position.x, foot.x) and motes.position.y > foot.y
			and glow.r > 0.3 and motes.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"dust drifting in the beam: none at night, glowing by day (%s, %s)" % [motes, glow])
	config.erase("skylights")
	_rig.rebuild(Level.parse(map.to_image(), null, config)["terrain"], Vector2i(7, 6))
	_check(_rig._skylights.is_empty(), "none without the key")
	# 797 amended: a mouth on the west edge, x 2, row 6.
	config["mouths"] = [{"at": [2, 6], "reach": 5}]
	_rig.rebuild(Level.parse(map.to_image(), null, config)["terrain"], Vector2i(7, 6))
	var mouth := _rig._room.get_node_or_null("Mouth_2_6") as SpotLight3D
	var ahead := -mouth.transform.basis.z if mouth != null else Vector3.ZERO
	_check(mouth != null and mouth.position.x < 2.0 and mouth.position.y > _rig._tile_position(Vector2i(2, 6)).y + 1.0
			and ahead.x > 0.5 and ahead.y < 0.0 and not mouth.shadow_enabled,
			"one light outside the mouth, shining in and down (%s, %s)" % [mouth, ahead])
	DayNight.light = 1.0
	_rig._light_skylights(Client3D.SKYLIGHT_PICK)
	DayNight.light = was
	_check(mouth != null and is_equal_approx(mouth.light_energy, Client3D.SKYLIGHT_ENERGY * Client3D.MOUTH_SHARE),
			"lit by the sky as a skylight, at its share (%.2f)" % [mouth.light_energy if mouth != null else 0.0])


func _test_mass() -> void:
	print("\n== the rock mass: rock past the walls, lit near, dark far, never black, no edge ==")
	var map := LevelMap.new(Vector2i(20, 14))
	var open: Dictionary[Vector2i, bool] = {}
	for x in range(2, 14):
		for y in range(5, 8):
			open[Vector2i(x, y)] = true
	for x in range(11, 17):
		for y in range(2, 11):
			open[Vector2i(x, y)] = true
	for cell: Vector2i in open:
		map.set_cell(cell, "stone")
	var config := {"outdoor": false, "walls": "cave", "floors": "cave", "mass": "rock"}
	var terrain: Dictionary = Level.parse(map.to_image(), null, config)["terrain"]
	_check(str(terrain.get("mass", "")) == "rock", "level.json's \"mass\" read into the terrain")
	_rig.rebuild(terrain, Vector2i(12, 6))
	var chunks: Array[MeshInstance3D] = []
	for child in _rig._room.get_children():
		if str(child.name).begins_with("Mass_"):
			chunks.append(child as MeshInstance3D)
	var box: Rect2i = _rig._mass_box
	_check(not chunks.is_empty() and box.position.x <= -Client3D.MASS_APRON and box.end.x >= 20 + Client3D.MASS_APRON
			and box.end.y >= 14 + Client3D.MASS_APRON, "drawn in chunks over the map and MASS_APRON past it (%d chunks, %s)" % [chunks.size(), box])
	var over_open := 0
	var edge_high := -INF
	var inside_low := INF
	var darkest := INF
	var lightest := 0.0
	var facets := 0
	for chunk in chunks:
		var arrays := (chunk.mesh as ArrayMesh).surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for i in range(0, points.size(), 3):
			facets += 1
			var middle := (points[i] + points[i + 1] + points[i + 2]) / 3.0
			if open.has(Vector2i(roundi(middle.x), roundi(middle.z))):
				over_open += 1
			darkest = minf(darkest, colours[i].get_luminance())
			lightest = maxf(lightest, colours[i].get_luminance())
			for k in 3:
				var p := points[i + k]
				# On a wall line: on the edge of an open cell's square.
				var on_edge := false
				for dx in [-0.5, 0.5]:
					for dz in [-0.5, 0.5]:
						on_edge = on_edge or open.has(Vector2i(roundi(p.x + dx * 0.98), roundi(p.z + dz * 0.98)))
				if on_edge:
					edge_high = maxf(edge_high, p.y)
				elif p.x > 0.0 and p.z > 0.0 and p.x < 19.0 and p.z < 13.0:
					inside_low = minf(inside_low, p.y)
	_check(facets > 0 and over_open == 0, "none over the open cells (%d facets, %d over)" % [facets, over_open])
	_check(edge_high <= Client3D.MASS_EDGE + 0.001 and edge_high < Client3D.CAVE_TOP_LOW,
			"at the walls under the cave ridge, so the wall is the lip (%.2f m, ridge from %.2f)" % [edge_high, Client3D.CAVE_TOP_LOW])
	_check(inside_low > Client3D.MASS_EDGE - Client3D.MASS_LUMP.w - 0.01, "a mass, not a floor: no trench behind a wall, no hollow (lowest %.2f m)" % inside_low)
	_check(darkest > 0.01 and lightest > darkest * 3.0, "darker away from the open, never black (%.3f to %.3f)" % [darkest, lightest])
	# Unlit: the lamps hang under its tops, so no facet beside a lit one
	# goes black (769 amended (7)).
	var unlit := chunks.all(func(c: MeshInstance3D) -> bool:
		var m := c.material_override as BaseMaterial3D
		return m != null and m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and m.vertex_color_use_as_albedo)
	_check(unlit, "drawn unlit, in its own shades")
	# The walls' lines wander into the rock, never into the walkable: no
	# point of a wall further into an open cell than CAVE_REACH, some
	# further into the rock than it.
	var into_open := 0.0
	var into_rock := 0.0
	for child in _rig._room.get_children():
		if not str(child.name).begins_with("Wall_"):
			continue
		var holder := child as Node3D
		var body := holder.get_node("Body") as MeshInstance3D
		var points: PackedVector3Array = (body.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for p in points:
			var q := holder.transform * p
			var cell := Vector2i(roundi(q.x), roundi(q.z))
			var inside := open.has(cell)
			# How far the point is from the nearest square of the other kind.
			var nearest := INF
			for dx in range(-2, 3):
				for dz in range(-2, 3):
					var other := cell + Vector2i(dx, dz)
					if open.has(other) == inside:
						continue
					var gap := Vector2(maxf(absf(q.x - other.x) - 0.5, 0.0), maxf(absf(q.z - other.y) - 0.5, 0.0))
					nearest = minf(nearest, gap.length())
			if nearest == INF:
				continue
			if inside:
				into_open = maxf(into_open, nearest)
			else:
				into_rock = maxf(into_rock, nearest)
	_check(into_open <= Client3D.CAVE_REACH + 0.001 and into_rock > Client3D.CAVE_REACH + 0.1,
			"the walls wander into the rock, never the walkable (%.2f m into the open, %.2f into the rock)" % [into_open, into_rock])
	# The walls' light runs nearly smooth: wherever facets share a point their
	# normals are close (the mean, each keeping CAVE_FACET_KEEP of its own), so
	# a lamp grazing a wall never lights one triangle of a quad and not the
	# other, yet the facets still show (769 amended (7)).
	var seen := {}
	var split := 0
	var shared := 0
	var turned := 0
	for child in _rig._room.get_children():
		if not str(child.name).begins_with("Wall_"):
			continue
		var arrays := ((child as Node3D).get_node("Body") as MeshInstance3D).mesh.surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		seen.clear()
		for k in points.size():
			var key := Vector3i((points[k] * 1000.0).round())
			if seen.has(key):
				shared += 1
				var apart := (seen[key] as Vector3).angle_to(normals[k])
				if apart > deg_to_rad(45.0):
					split += 1
				elif apart > deg_to_rad(2.0):
					turned += 1
			else:
				seen[key] = normals[k]
	_check(shared > 0 and split == 0 and turned > 0, "the walls lit nearly smooth, their facets still showing (%d shared points, %d each its own turn, %d split)" % [shared, turned, split])
	terrain["mass"] = ""
	_rig.rebuild(terrain, Vector2i(12, 6))
	var none := _rig._room.get_children().filter(func(n: Node) -> bool: return str(n.name).begins_with("Mass_")).is_empty()
	terrain["mass"] = "rock"
	terrain["outdoor"] = true
	_rig.rebuild(terrain, Vector2i(12, 6))
	var none_out := _rig._room.get_children().filter(func(n: Node) -> bool: return str(n.name).begins_with("Mass_")).is_empty()
	_check(none and none_out, "none without the key, none outdoors")
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


func _test_cave_walls() -> void:
	print("
== cave walls: rock, not a profile; 0.6 to 0.9 m thick, a ragged top, never far into a walkable cell, no seam ==")
	var castle := Level.load_level("castle")
	var terrain: Dictionary = castle["terrain"].duplicate()
	terrain["walls"] = "cave"
	_rig.rebuild(terrain, castle["centre"])
	var by_run: Dictionary[Node3D, Array] = {}
	for key: Vector3i in _rig._walls:
		if not by_run.has(_rig._walls[key]):
			by_run[_rig._walls[key]] = []
		by_run[_rig._walls[key]].append(key)
	var reach := true
	var feet := true
	var tops := true
	var heights: Dictionary[float, bool] = {}
	for run: Node3D in by_run:
		var body := run.get_node("Body") as MeshInstance3D
		var foot := 0.0
		var top := 0.0
		for point: Vector3 in (body.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			reach = reach and absf(point.x) <= Client3D.CAVE_REACH + 0.0001
			if point.y < 0.001:
				foot = maxf(foot, absf(point.x))
			top = maxf(top, point.y)
		feet = feet and foot >= 0.3 - 0.0001 and foot <= Client3D.CAVE_REACH + 0.0001
		tops = tops and top >= Client3D.CAVE_TOP_LOW * 0.55 and top <= Client3D.CAVE_TOP_HIGH + Client3D.CAVE_RIDGE + Client3D.CAVE_BUMP
		heights[snappedf(top, 0.05)] = true
	_check(by_run.size() > 0 and _rig._set_of(by_run[by_run.keys()[0]][0]) == "cave" and (by_run.keys()[0].get_node("Body") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] != null,
			"a map whose walls are \"cave\": its runs are rock, coloured facets (%d runs)" % by_run.size())
	_check(reach, "nothing more than %.2f m from the edge's line, into a walkable cell" % Client3D.CAVE_REACH)
	_check(feet, "between 0.6 and 0.9 m thick at the foot")
	_check(tops and heights.size() > 3, "tops ragged, %.1f to %.1f m and a ridge (%d heights)" % [Client3D.CAVE_TOP_LOW, Client3D.CAVE_TOP_HIGH, heights.size()])
	# Runs that meet on a line share their points: no seam.
	var pairs := 0
	var seams := 0
	var runs := by_run.keys()
	for a: Node3D in runs:
		for b: Node3D in runs:
			var a_keys: Array = by_run[a]
			var b_keys: Array = by_run[b]
			a_keys.sort_custom(func(x: Vector3i, y: Vector3i) -> bool: return Client3D._along(x) < Client3D._along(y))
			b_keys.sort_custom(func(x: Vector3i, y: Vector3i) -> bool: return Client3D._along(x) < Client3D._along(y))
			if Client3D._line_of(a_keys[0]) != Client3D._line_of(b_keys[0]) or Client3D._along(a_keys[-1]) + 1 != Client3D._along(b_keys[0]):
				continue
			pairs += 1
			var ends: Array[Dictionary] = [{}, {}]
			for side in 2:
				var body := ([a, b][side] as Node3D).get_node("Body") as MeshInstance3D
				var at := float(a_keys.size()) if side == 0 else 0.0
				for point: Vector3 in (body.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
					if absf(point.z - at) < 0.0001:
						ends[side][(body.global_transform * point).snappedf(0.001)] = true
			seams += 0 if ends[0].keys().all(func(point: Vector3) -> bool: return ends[1].has(point)) and ends[0].size() == ends[1].size() else 1
	_check(seams == 0, "runs meeting on a line share every point where they meet (%d pairs, %d with a seam)" % [pairs, seams])
	var lumps := _rig._posts.values().filter(func(post: Node3D) -> bool:
		var body := post.get_node_or_null("Body") as MeshInstance3D
		return body != null and body.mesh is ArrayMesh)
	if ArtKit.filled_by("wall.cave.end") == "own":
		_check(_rig._posts.size() > 0 and lumps.is_empty(), "its posts drawn from wall.cave.end's art, no lumps (%d of %d)" % [lumps.size(), _rig._posts.size()])
	else:
		_check(_rig._posts.size() > 0 and lumps.size() == _rig._posts.size(), "its posts lumps of the same rock while wall.cave.end has no art (%d of %d)" % [lumps.size(), _rig._posts.size()])
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## A grass field with a house (front south) at (2, 2) and a hut turned a
## quarter (front west) at (9, 2), stamped from the kit prefabs: its terrain.
func _building_terrain() -> Dictionary:
	var map := LevelMap.new(Vector2i(16, 14))
	for y in 14:
		for x in 16:
			map.set_cell(Vector2i(x, y), "grass")
	var config := {"outdoor": true}
	for stamp: Array in [["building_house", Vector2i(2, 2), 0], ["building_hut", Vector2i(9, 2), 1], ["well", Vector2i(9, 8), 0]]:
		var changes := Prefab.stamp_changes(Prefab.rotated(Prefab.load_prefab(stamp[0]), stamp[2]), map, stamp[1], config)
		for cell: Vector2i in changes["cells"]:
			map.set_cell(cell, changes["cells"][cell])
		for key: Vector3i in changes["edges"]:
			map.set_edge(key, changes["edges"][key])
		config.merge(changes.get("config", {}), true)
	return Level.parse(map.to_image(), null, config)["terrain"]


func _roof_shadow_only(building: Dictionary) -> bool:
	return _rig._descendants(building["roof"]).all(func(node: Node) -> bool:
		return not node is GeometryInstance3D or node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)


func _test_buildings() -> void:
	print("
== buildings: the slot's roof over the footprint; the roof off, its shadow kept, while the player is inside ==")
	_rig.rebuild(_building_terrain(), Vector2i(7, 7))
	var by_rect := {}
	for building: Dictionary in _rig._buildings:
		by_rect[building["rect"]] = building
	var house: Dictionary = by_rect.get(Rect2i(3, 3, 4, 6), {})
	var hut: Dictionary = by_rect.get(Rect2i(10, 3, 3, 3), {})
	var well: Dictionary = by_rect.get(Rect2i(11, 10, 1, 1), {})
	_check(_rig._buildings.size() == 3 and not house.is_empty() and not hut.is_empty() and not well.is_empty(), "three buildings drawn (%s)" % [by_rect.keys()])
	if house.is_empty() or hut.is_empty():
		_rig.rebuild(_main._terrain, Vector2i.ZERO)
		return
	var node: Node3D = house["node"]
	_check(house["roof"] != null and node.get_node_or_null("floor") == null, "each has its roof, and no floor of its own: its inside is terrain's ground in its floor set")
	_check(not (node.get_node("roof_damaged") as Node3D).visible and not (node.get_node("state_damaged") as Node3D).visible,
			"whole: its damaged roof and its rubble hidden")
	_check(Level.BUILDINGS.keys().all(func(slot: String) -> bool:
		var footprint: Array = ArtKit.spec(slot).get("footprint", [])
		return footprint.size() == 2 and Vector2i(int(footprint[0]), int(footprint[1])) == Level.BUILDINGS[slot]),
			"the sim's footprints are art-kit's slots' (Level.BUILDINGS)")
	_check(not well.is_empty() and not _rig._building_at.has(Vector2i(11, 10)) and _rig._dry_water.has(Vector2i(11, 10))
			and not _rig._wall_sets.has(Vector3i(11, 10, Terrain.EAST)), "the well: no inside, no walls, its water drawn dry under its rim")
	_check(Level.outline(house["rect"]).all(func(key: Vector3i) -> bool: return _rig._set_of(key) == "wood"),
			"its outline is drawn in its slot's wall set, wood (decision 285)")
	var planks := 0
	var footprint := Level.rect_cells(house["rect"])
	for cell: Vector2i in footprint:
		var place := (cell.y - _rig._mask_origin.y) * _rig._mask_size.x + cell.x - _rig._mask_origin.x
		planks += 1 if _rig._floor_bytes[place] == Client3D.FLOOR_SETS["wood"] else 0
	var lawn := Vector2i(1, 1)
	var lawn_place := (lawn.y - _rig._mask_origin.y) * _rig._mask_size.x + lawn.x - _rig._mask_origin.x
	_check(planks == footprint.size() and _rig._floor_bytes[lawn_place] == 0,
			"and its inside floored in its floor set, wood, cell by cell to its walls (%d of %d), the grass outside as it was" % [planks, footprint.size()])
	_check(node.position.is_equal_approx(Vector3(4.5, 0.0, 5.5)) and is_equal_approx(node.rotation.y, 0.0),
			"the house stands over the middle of its footprint, its front south (%s, %s)" % [node.position, node.rotation.y])
	_check(is_equal_approx((hut["node"] as Node3D).rotation.y, -PI / 2.0), "the hut turned with its front west")
	_check(is_equal_approx((house["roof"] as Node3D).global_position.y - node.global_position.y, Client3D.WALL_HEIGHT), "its roof on the walls' tops")
	_check(_rig._occluders.any(func(entry: Array) -> bool: return entry[0] == house["roof"]), "a roof can fade as a wall does when it hides a player outside")
	# The player inside, the companion far off: the house's roof is off.
	_rig.set_process(false)
	var player := _player()
	var companion := _companion()
	var puppet: Node3D = _rig._puppets[player.get_instance_id()]
	var other: Node3D = _rig._puppets.get(companion.get_instance_id()) if companion != null else null
	var was := puppet.global_position
	var other_was := other.global_position if other != null else Vector3.ZERO
	var outside := _rig.to_global(_rig._tile_position(Vector2i(14, 12)))
	if other != null:
		other.global_position = outside
	puppet.global_position = outside
	_rig._update_fade(true)
	_check(not house["off"] and not hut["off"] and not _roof_shadow_only(house), "both outside: every roof on")
	puppet.global_position = _rig.to_global(_rig._tile_position(Vector2i(4, 6)))
	_rig._update_fade()
	# Its roof eases off over ROOF_FADE.
	_rig._fade_clock += Client3D.ROOF_FADE
	_rig._update_fade()
	_check(house["off"] and _roof_shadow_only(house), "the player inside the house: its roof draws only its shadow")
	_check(not hut["off"] and not _roof_shadow_only(hut), "the hut's roof stays on")
	# Its sides toward the camera fade, the others stay solid, at two yaws.
	for turn in 2:
		var toward := _rig._camera.global_transform.basis.z
		var flat := Vector2(toward.x, toward.z).normalized()
		var near := 0
		var wrong := 0
		for key in Level.outline(house["rect"]):
			if not _rig._walls.has(key) and not _rig._doorways.has(key):
				continue
			var piece: Node3D = _rig._walls[key] if _rig._walls.has(key) else _rig._doorways[key].get_node(Client3D.DOOR_FRAME)
			var outward := Vector2(1, 0) if key.z == Terrain.EAST else Vector2(0, 1)
			if key.x < 4 and key.z == Terrain.EAST or key.y < 3 and key.z == Terrain.SOUTH:
				outward = -outward
			var faces := outward.dot(flat) > Client3D.NEAR_SIDE
			near += 1 if faces else 0
			if faces != _rig._faded.has(piece):
				wrong += 1
		_check(near > 0 and wrong == 0, "yaw %d: the house's %d outline edges toward the camera fade, the rest stay solid (%d wrong)" % [roundi(_rig.yaw), near, wrong])
		# Turned: the sides that were near stay faded FADE_HOLD, as any wall.
		_rig._set_yaw(_rig.yaw + 90.0)
		_rig._fade_clock += Client3D.FADE_HOLD + 0.1
		_rig._update_fade()
	_rig._set_yaw(_rig.yaw - 180.0)
	puppet.global_position = outside
	_rig._fade_clock += Client3D.FADE_HOLD * 0.5
	_rig._update_fade()
	_check(house["off"], "stepped out: it stays off a moment")
	_rig._fade_clock += Client3D.FADE_HOLD
	_rig._update_fade()
	_check(not house["off"] and not _roof_shadow_only(house), "and after %s s, it is back" % Client3D.FADE_HOLD)
	if other != null:
		other.global_position = _rig.to_global(_rig._tile_position(Vector2i(11, 4)))
		_rig._update_fade()
		_check(hut["off"] and not house["off"], "the companion inside the hut: its roof is off")
		other.global_position = other_was
	puppet.global_position = was
	_rig.set_process(true)
	_rig.rebuild(_main._terrain, Vector2i.ZERO)



func _test_roofs() -> void:
	print("
== roofs (decision 364): a tiling set's gable over a walled room; off while the player is under it ==")
	var map := LevelMap.new(Vector2i(16, 14))
	for y in 14:
		for x in 16:
			map.set_cell(Vector2i(x, y), "grass")
	var rect := Rect2i(3, 3, 5, 3)
	for key in Level.outline(rect):
		map.set_edge(key, "door" if key == Vector3i(5, 5, Terrain.SOUTH) else "wall")
	var terrain: Dictionary = Level.parse(map.to_image(), null, {"outdoor": true, "walls": "wood",
		"roofs": [{"rect": [3, 3, 5, 3], "use": "", "town": ""}]})["terrain"]
	(terrain["roofs"][0] as Dictionary)["use"] = "forge"
	(terrain["roofs"][0] as Dictionary)["town_id"] = "fixture/roofs"
	_rig.rebuild(terrain, Vector2i(7, 7))
	_check(_rig._buildings.size() == 1, "one roof drawn, kept with the buildings (%d)" % _rig._buildings.size())
	if _rig._buildings.size() != 1:
		_rig.rebuild(_main._terrain, Vector2i.ZERO)
		return
	var roofed: Dictionary = _rig._buildings[0]
	var holder: Node3D = roofed["node"]
	var roof: Node3D = roofed["roof"]
	_check(holder.name == "Roof_3_3" and holder.position.is_equal_approx(Vector3(5, 0, 4)) and is_equal_approx(holder.rotation.y, PI * 0.5)
			and is_equal_approx(roof.position.y, Client3D.WALL_HEIGHT), "over the room's middle at the walls' top, its ridge along x, the long side")
	_check(roof.get_node_or_null("Slopes") != null and roof.get_node_or_null("Gables") != null,
			"its slopes from roof.shingle.profile, its gables in the wall set")
	var top := _rig._bounds(roof.get_node("Slopes"))
	_check(absf(top.end.y - (Client3D.WALL_HEIGHT + 0.75 * 1.5 + 0.15)) < 0.01 and is_equal_approx(top.size.x, 5.6) and is_equal_approx(top.size.z, 3.6),
			"rising 0.75 a cell to its ridge, past the walls at the eaves and gables (%s)" % [top])
	_check(_rig._building_at.get(Vector2i(4, 4), -1) == 0 and _rig._building_at.get(Vector2i(7, 5), -1) == 0 and not _rig._building_at.has(Vector2i(8, 4)),
			"its cells are its inside")
	_check(_rig._occluders.any(func(entry: Array) -> bool: return entry[0] == roof), "it fades as a wall does when it hides a player outside")
	_rig.set_process(false)
	var puppet: Node3D = _rig._puppets[_player().get_instance_id()]
	var other: Node3D = _rig._puppets.get(_companion().get_instance_id()) if _companion() != null else null
	var was := puppet.global_position
	var other_was := other.global_position if other != null else Vector3.ZERO
	var outside := _rig.to_global(_rig._tile_position(Vector2i(12, 11)))
	if other != null:
		other.global_position = outside
	puppet.global_position = _rig.to_global(_rig._tile_position(Vector2i(6, 4)))
	_rig._update_fade()
	# Its roof eases off over ROOF_FADE.
	_rig._fade_clock += Client3D.ROOF_FADE
	_rig._update_fade()
	_check(roofed["off"] and _roof_shadow_only(roofed), "the player under it: it draws only its shadow")
	puppet.global_position = outside
	_rig._fade_clock += Client3D.FADE_HOLD + 0.1
	_rig._update_fade()
	_check(not roofed["off"] and not _roof_shadow_only(roofed), "out from under it: it is back")
	_rig.set_town("fixture/roofs", {"forge": {"state": Towns.DAMAGED, "level": 1}})
	_check(roofed["damaged"] and not roof.transform.is_equal_approx(roofed["roof_at"]), "its town's forge damaged: it sags, as a slot's roof with no roof_damaged")
	_rig.set_town("fixture/roofs", {"forge": {"state": Towns.STANDING, "level": 1}})
	_check(not roofed["damaged"] and roof.transform.is_equal_approx(roofed["roof_at"]), "and standing again")
	puppet.global_position = was
	if other != null:
		other.global_position = other_was
	_rig.set_process(true)
	_rig.town_states.erase("fixture/roofs")
	# An open shelter: no walls, a post at each corner.
	var open: Dictionary = Level.parse(map.to_image(), null, {"outdoor": true,
		"roofs": [{"rect": [10, 8, 3, 2]}]})["terrain"]
	_rig.rebuild(open, Vector2i(7, 7))
	_check([Vector2i(10, 8), Vector2i(13, 8), Vector2i(10, 10), Vector2i(13, 10)].all(func(vertex: Vector2i) -> bool: return _rig._posts.has(vertex)),
			"an open shelter stands on a post at each corner")
	_rig.rebuild(_main._terrain, Vector2i.ZERO)




func _test_roof_damage() -> void:
	print("
== a damaged roof (decision 383): a third of it open to the sky, in the sim and the view; mended, whole ==")
	var broken := Level.broken_cells(Rect2i(0, 0, 9, 9))
	_check(broken.size() > 15 and broken.size() < 39 and Level.broken_cells(Rect2i(5, 5, 1, 1)) == [Vector2i(5, 5)],
			"a third or so of a big roof's cells broken (%d of 81), and a one-cell roof's one" % broken.size())
	var map := LevelMap.new(Vector2i(16, 14))
	for y in 14:
		for x in 16:
			map.set_cell(Vector2i(x, y), "grass")
	var rect := Rect2i(3, 3, 5, 3)
	for key in Level.outline(rect):
		map.set_edge(key, "door" if key == Vector3i(5, 5, Terrain.SOUTH) else "wall")
	var terrain: Dictionary = Level.parse(map.to_image(), null, {"outdoor": true,
		"roofs": [{"rect": [3, 3, 5, 3]}, {"rect": [10, 3, 3, 3]}]})["terrain"]
	terrain["level"] = "roof_fixture"
	# The sim: a zone of its own, so the test's own zone is left as it is.
	var zone := Zone.new("roof_fixture")
	zone.fields.load(terrain)
	zone.fields.outdoor = true
	World.zones["roof_fixture"] = zone
	var told: Array[String] = []
	var heard := func(level: String) -> void: told.append(level)
	World.roof_changed.connect(heard)
	var open := Level.broken_cells(rect)
	_check(World.damage_roof("roof_fixture", 0) and not World.damage_roof("roof_fixture", 0) and not World.damage_roof("roof_fixture", 7),
			"damaged once (again, or a roof there is not, is nothing)")
	_check(World.damaged_roofs("roof_fixture") == [0] and World.roof_damaged("roof_fixture", 0) and told == ["roof_fixture"],
			"its index is among the level's damaged roofs, and Main is told (%s)" % [told])
	_check(open.all(func(cell: Vector2i) -> bool: return zone.fields.under_sky(cell))
			and Level.rect_cells(rect).filter(func(cell: Vector2i) -> bool: return zone.fields.under_sky(cell)).size() == open.size()
			and not zone.fields.under_sky(Vector2i(11, 4)),
			"its broken cells are under the sky, the rest of it and the other roof still roofed")
	_check(World.repair_roof("roof_fixture", 0) and World.damaged_roofs("roof_fixture").is_empty()
			and Level.rect_cells(rect).all(func(cell: Vector2i) -> bool: return not zone.fields.under_sky(cell)),
			"mended: roofed again")
	# A client, told by the server ("roofs"), opens the same cells.
	World.roofs_told("roof_fixture", [1.0])
	_check(Level.broken_cells(Rect2i(10, 3, 3, 3)).all(func(cell: Vector2i) -> bool: return zone.fields.under_sky(cell))
			and Level.rect_cells(rect).all(func(cell: Vector2i) -> bool: return not zone.fields.under_sky(cell)),
			"a client told roof 1 is damaged opens its cells, as the server does")
	World.roofs_told("roof_fixture", [])
	# A town's damaged building opens a third of it too (a client's, told the town).
	var house := {"slot": "building.house", "rect": Rect2i(3, 8, 4, 4), "use": "forge", "town_id": "roof_fixture/square"}
	var with_house := terrain.duplicate()
	with_house["buildings"] = [house]
	zone.fields.load(with_house)
	zone.fields.outdoor = true
	var towns := World.towns
	World.towns = null
	World.towns_seen["roof_fixture/square"] = {"forge": {"state": Towns.DAMAGED, "level": 1}}
	World.open_roofs("roof_fixture")
	var house_open := Level.rect_cells(house["rect"]).filter(func(cell: Vector2i) -> bool: return zone.fields.under_sky(cell))
	_check(house_open.size() == Level.broken_cells(house["rect"]).size(), "a damaged town building: a third of its cells under the sky (%d)" % house_open.size())
	# Its walls not up (566): its outline open both ways, and the path cache
	# dropped; up, its walls stand again.
	var outline := Level.blocks_outline(Level.rect_cells(house["rect"]))
	for key in outline:
		zone.edges[key] = Terrain.Edge.WALL
	zone.grid_rect = Rect2i(0, 0, 4, 4)
	World.towns_seen["roof_fixture/square"] = {"forge": {"state": Towns.BUILDING, "level": 0, "walls": false}}
	World.open_roofs("roof_fixture")
	_check(outline.all(func(key: Vector3i) -> bool: return not zone.edges.has(key)) and zone.grid_rect == Rect2i(),
		"walls not up (566): its %d outline edges open, the path cache dropped" % outline.size())
	World.towns_seen["roof_fixture/square"] = {"forge": {"state": Towns.BUILDING, "level": 0, "walls": true}}
	World.open_roofs("roof_fixture")
	_check(outline.all(func(key: Vector3i) -> bool: return zone.edges.get(key) == Terrain.Edge.WALL), "walls up: they stand again")
	# 383 amended: the heat and light worked out again only on a change. A
	# house's lamp (Towns.set_awake) sent the town again every time a
	# resident went in or out, and the whole map's floor was shaded again.
	var was := World.enter(zone)
	var changes := {"n": 0}
	var counted := func() -> void: changes["n"] += 1
	World.fields_changed_signal.connect(counted)
	World.open_roofs("roof_fixture")
	World.open_roofs("roof_fixture")
	var unchanged: int = changes["n"]
	World.towns_seen["roof_fixture/square"] = {"forge": {"state": Towns.DAMAGED, "level": 1, "walls": true}}
	World.open_roofs("roof_fixture")
	var damaged: int = changes["n"]
	World.towns_seen["roof_fixture/square"] = {"forge": {"state": Towns.BUILDING, "level": 0, "walls": true}}
	World.open_roofs("roof_fixture")
	World.fields_changed_signal.disconnect(counted)
	World.enter(was)
	_check(unchanged == 0 and damaged == 1 and changes["n"] == 2,
		"383 amended: the town told again with nothing open or down changed leaves the fields be (%d); damaged, then mended, each works them out again (%d, %d)" % [unchanged, damaged, changes["n"]])
	World._walls_down.erase("roof_fixture")
	World.towns = towns
	World.towns_seen.erase("roof_fixture/square")
	World.roof_changed.disconnect(heard)
	World.zones.erase("roof_fixture")
	World.roofs_damaged.clear()
	# The snapshot: an old one has none.
	var path: String = preload("res://tests/test_ports.gd").scratch("view_test_old.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": Snapshot.VERSION, "zones": {}, "players": [], "steps": 7}))
	file.close()
	var old := Snapshot.load(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check(old["ok"] and old["roofs"] == [], "a snapshot from before roofs broke loads with none broken (%s)" % [old.get("roofs")])
	# The view: told, the roof is made again with holes, each dressed.
	_rig.rebuild(terrain, Vector2i(7, 7))
	var roofed: Dictionary = _rig._buildings[0]
	var whole: Node3D = roofed["roof"]
	var tris := func(roof: Node3D) -> int: return ((roof.get_node("Slopes") as MeshInstance3D).mesh as ArrayMesh).surface_get_array_len(0) / 3
	var before: int = tris.call(whole)
	_rig.set_roofs("roof_fixture", [0])
	var holed: Node3D = roofed["roof"]
	var pieces := holed.get_children().filter(func(child: Node) -> bool: return child.name.begins_with("Broken_"))
	_check(roofed["holed"] and holed != whole and tris.call(holed) < before and pieces.size() == open.size()
			and not (_rig._buildings[1]["holed"] as bool),
			"told roof 0 is damaged: made again with %d holes, each dressed (%d), %d triangles of %d; the other whole" % [open.size(), pieces.size(), tris.call(holed), before])
	_rig.set_roofs("roof_fixture", [])
	_check(not roofed["holed"] and tris.call(roofed["roof"]) == before, "mended: whole again")
	_rig.roof_states.erase("roof_fixture")
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


func _test_wall_heights() -> void:
	print("
== the temple and the healer's hut: kit prefabs; a building's walls as tall as its slot says ==")
	var level := _kit_level()
	var rects := (level["buildings"] as Array).map(func(b: Dictionary) -> Array: return [b["slot"], b["rect"]])
	_check(rects == [["building.temple", Rect2i(2, 2, 4, 6)], ["building.healers_hut", Rect2i(10, 2, 3, 3)], ["building.field", Rect2i(10, 7, 4, 4)]]
			and (level["warnings"] as Array).filter(func(text: String) -> bool: return text.contains("building")).is_empty(),
			"each prefab stamps its building on its footprint, walled, nothing said (%s)" % [rects])
	var counters := (level["entities"] as Array).filter(func(spec: Dictionary) -> bool: return spec.get("props", {}).get("temple") == true)
	_check(counters.size() == 1 and counters[0]["tile"] == Vector2i(3, 2) and counters[0]["script"] == Level.CHEST,
			"the temple's counter (decision 424): a chest at its back, props temple (%s)" % [counters.map(func(spec: Dictionary) -> Vector2i: return spec["tile"])])
	_rig.rebuild(level["terrain"], Vector2i(7, 6))
	var tall := float(ArtKit.spec("building.temple").get("wall_height", Client3D.WALL_HEIGHT))
	var temple := Level.outline(Rect2i(2, 2, 4, 6))
	_check(temple.all(func(key: Vector3i) -> bool: return is_equal_approx(_rig._wall_heights.get(key, Client3D.WALL_HEIGHT), tall))
			and Level.outline(Rect2i(10, 2, 3, 3)).all(func(key: Vector3i) -> bool: return not _rig._wall_heights.has(key)),
			"the temple's outline %s m tall, as its slot says; the hut's the sets' own" % tall)
	# Its runs reach its roof's eaves; the hut's stand at the sets' 3 m.
	var tops := func(outline: Array[Vector3i]) -> Array[float]:
		var out: Array[float] = []
		var seen: Dictionary[Node3D, bool] = {}
		for key in outline:
			var run: Node3D = _rig._walls.get(key)
			if run == null or seen.has(run) or run.get_node_or_null("Body") == null:
				continue
			seen[run] = true
			var top := -INF
			for point: Vector3 in ((run.get_node("Body") as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				top = maxf(top, point.y)
			out.append(top)
		return out
	var temple_tops: Array[float] = tops.call(temple)
	var hut_tops: Array[float] = tops.call(Level.outline(Rect2i(10, 2, 3, 3)))
	var eaves := -1.0
	for building: Dictionary in _rig._buildings:
		if building["rect"] == Rect2i(2, 2, 4, 6) and building["roof"] != null:
			eaves = (building["roof"] as Node3D).global_position.y - (building["node"] as Node3D).global_position.y
	_check(not temple_tops.is_empty() and temple_tops.all(func(top: float) -> bool: return absf(top - eaves) < 0.6)
			and not hut_tops.is_empty() and hut_tops.all(func(top: float) -> bool: return absf(top - Client3D.WALL_HEIGHT) < 0.6),
			"the temple's wall tops meet its eaves at %.1f m (%s), the hut's stand at %.1f m (%s)" % [eaves, temple_tops, Client3D.WALL_HEIGHT, hut_tops])
	var doors := temple.filter(func(key: Vector3i) -> bool: return _rig._doorways.has(key))
	_check(not doors.is_empty() and doors.all(func(key: Vector3i) -> bool: return _rig._doorways[key].find_child("Lintel", true, false) != null)
			and not Level.outline(Rect2i(10, 2, 3, 3)).any(func(key: Vector3i) -> bool: return _rig._doorways.has(key) and _rig._doorways[key].find_child("Lintel", true, false) != null),
			"over the temple's doors the wall goes on (a lintel), over the hut's none")
	var corner: Node3D = _rig._posts.get(Vector2i(2, 2))
	_check(corner != null and _rig._bounds(corner).end.y > tall - 0.2, "its corner posts as tall")
	_rig.rebuild(_main._terrain, Vector2i.ZERO)
	_check(_rig._wall_heights.is_empty(), "and none left on another map")


## The temple (at 2, 2), the healer's hut (at 10, 2) and a field (at 10, 7)
## stamped from their prefabs on grass, parsed.
func _kit_level() -> Dictionary:
	var map := LevelMap.new(Vector2i(16, 12))
	for y in 12:
		for x in 16:
			map.set_cell(Vector2i(x, y), "grass")
	var config := {"outdoor": true}
	for stamp: Array in [["building_temple", Vector2i(1, 1)], ["building_healers_hut", Vector2i(9, 1)],
			["building_field", Vector2i(9, 6)]]:
		var changes := Prefab.stamp_changes(Prefab.load_prefab(stamp[0]), map, stamp[1], config)
		for cell: Vector2i in changes["cells"]:
			map.set_cell(cell, changes["cells"][cell])
		for key: Vector3i in changes["edges"]:
			map.set_edge(key, changes["edges"][key])
		config.merge(changes.get("config", {}), true)
		config["entities"] = config.get("entities", []) + changes["entries"]
	return Level.parse(map.to_image(), null, config)


## A field (Level.OPEN_AIR, decision 452): its slot drawn, its fence the
## slot's mesh, so no wall drawn on its outline, and no inside (no roof to
## cut away, nothing kept dry); the temple beside it walled as ever.
func _test_field() -> void:
	print("\n== a field: its slot drawn, no walls on its outline, no inside (decision 452) ==")
	_rig.rebuild(_kit_level()["terrain"], Vector2i(7, 6))
	var rect := Rect2i(10, 7, 4, 4)
	var field := _rig._buildings.filter(func(each: Dictionary) -> bool: return each["rect"] == rect)
	_check(field.size() == 1 and field[0]["roof"] == null, "the field's slot stands over its footprint, no roof (%d)" % field.size())
	var walled := Level.outline(rect).filter(func(key: Vector3i) -> bool: return _rig._runs.has(key) or _rig._walls.has(key))
	_check(walled.is_empty() and Level.outline(Rect2i(2, 2, 4, 6)).any(func(key: Vector3i) -> bool: return _rig._runs.has(key) or _rig._walls.has(key)),
			"no wall drawn round the field, the temple's drawn (%s)" % [walled])
	_check(Level.rect_cells(rect).all(func(cell: Vector2i) -> bool: return not _rig._building_at.has(cell)) and _rig._building_at.has(Vector2i(3, 3)),
			"the field has no inside; the temple has")
	if field.size() != 1:
		return
	# Its crop (decision 452 amended): the town record's "crop" picks the
	# slot's state_<crop>, one at a time; none, "" or an unknown name bare.
	var building: Dictionary = field[0]
	building["use"] = "field"
	building["town_id"] = "crop_town"
	var states := (building["node"] as Node3D).find_children("state_*", "Node3D", true, false)
	var shown := func() -> Array: return states.filter(func(part: Node3D) -> bool: return part.visible).map(func(part: Node3D) -> String: return str(part.name))
	_check(states.size() >= 4 and shown.call().is_empty(), "bare to begin with: none of its %d states shown" % states.size())
	_rig.set_town("crop_town", {"field": {"state": Towns.STANDING, "crop": "ripe"}})
	_check(shown.call() == ["state_ripe"], "ripe: state_ripe alone (%s)" % [shown.call()])
	_rig.set_town("crop_town", {"field": {"state": Towns.STANDING, "crop": "sown"}})
	_check(shown.call() == ["state_sown"], "sown: state_sown alone (%s)" % [shown.call()])
	_rig.set_town("crop_town", {"field": {"state": Towns.DAMAGED, "crop": "flattened"}})
	_check(shown.call() == ["state_flattened"] and Level.outline(rect).all(func(key: Vector3i) -> bool: return not _rig._wall_states.has(key)),
			"flattened, damaged: state_flattened alone, no broken wall drawn on its fence (%s)" % [shown.call()])
	_rig.set_town("crop_town", {"field": {"state": Towns.STANDING}})
	_check(shown.call().is_empty(), "a record with no crop: bare")
	_rig.set_town("crop_town", {"field": {"state": Towns.STANDING, "crop": "weeds"}})
	_check(shown.call().is_empty(), "a crop the slot has no state for: bare")
	_rig.town_states.erase("crop_town")


## A herder's fold (640, maps' side): min(count, 6) sheep drawn standing
## inside its fence, off the trough's strip at its back; a count dropping
## shows fewer at once; none for none.
func _test_folds() -> void:
	print("\n== a fold: its holding's sheep drawn in it, min(count, 6), fewer at once when a drove leaves (640) ==")
	var rect := Rect2i(2, 2, 6, 6)
	var drawn := func() -> int:
		return _rig._fold_sheep.get_child_count() if is_instance_valid(_rig._fold_sheep) else 0
	for facing: Vector2i in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]:
		var spots := Client3D.fold_spots(rect, facing, 9)
		var back := Vector2(rect.position) + Vector2(rect.size - Vector2i.ONE) * 0.5 - Vector2(facing) * 3.0
		var inside := true
		var off_trough := true
		for at: Vector2 in spots:
			# Cell centres: the fence 0.5 out from the outer cells' middles.
			inside = inside and at.x > rect.position.x - 0.2 and at.y > rect.position.y - 0.2 and at.x < rect.end.x - 0.8 and at.y < rect.end.y - 0.8
			off_trough = off_trough and absf((at - back).dot(Vector2(facing))) > 0.7
		_check(spots.size() == 6 and inside and off_trough, "gate %s: six spots of nine, all inside the fence, off the trough (%s)" % [facing, spots])
	_check(Client3D.fold_spots(rect, Vector2i(0, 1), 0).is_empty(), "none for none")
	if not ArtKit.has(Client3D.FOLD_SHEEP):
		print("  (no creature.sheep art here: the drawing checks skipped)")
		return
	_rig.set_folds([{"rect": rect, "facing": Vector2i(0, 1), "count": 9}])
	_check(drawn.call() == 6, "nine sheep: six drawn (%d)" % drawn.call())
	_rig.set_folds([{"rect": rect, "facing": Vector2i(0, 1), "count": 2}])
	_check(drawn.call() == 2, "a drove of seven walked off: two drawn at once (%d)" % drawn.call())
	_rig.set_folds([])
	_check(drawn.call() == 0, "no fold told: none drawn")


## A building of a kind (decision 488): an L-house's roof a gable over
## each block, off as one while inside either; inside its wing, not the
## corner its box leaves empty; its outline's walls in its kind's set.
func _test_kinds() -> void:
	print("\n== an L-house: a roof over each block, inside by its blocks (decision 488) ==")
	var map := LevelMap.new(Vector2i(14, 12))
	for y in 12:
		for x in 14:
			map.set_cell(Vector2i(x, y), "grass")
	var changes := Prefab.stamp_changes(Prefab.load_prefab("building_l_house_small"), map, Vector2i(1, 1), {"outdoor": true})
	for cell: Vector2i in changes["cells"]:
		map.set_cell(cell, changes["cells"][cell])
	for key: Vector3i in changes["edges"]:
		map.set_edge(key, changes["edges"][key])
	var config := {"outdoor": true}
	config.merge(changes.get("config", {}), true)
	_rig.rebuild(Level.parse(map.to_image(), null, config)["terrain"], Vector2i(4, 11))
	var house := _rig._buildings.filter(func(each: Dictionary) -> bool: return each["rect"] == Rect2i(2, 2, 10, 8))
	_check(house.size() == 1 and house[0]["roof"] != null and (house[0]["roof"] as Node3D).get_child_count() == 2,
			"one building, its roof a piece over each of its two blocks")
	_check(_rig._building_at.get(Vector2i(9, 7), -1) == _rig._buildings.find(house[0] if not house.is_empty() else {}) and not _rig._building_at.has(Vector2i(9, 3)),
			"inside it in its wing, not in the corner its box leaves")
	var outline := Level.blocks_outline(Level._union([Rect2i(2, 2, 6, 8), Rect2i(8, 6, 4, 4)]))
	var walls := outline.filter(func(key: Vector3i) -> bool: return not _rig._doorways.has(key) and (_rig._runs.has(key) or _rig._walls.has(key)))
	var doors := outline.filter(func(key: Vector3i) -> bool: return _rig._doorways.has(key))
	_check(walls.size() == outline.size() - 1 and doors == [Vector3i(4, 9, Terrain.SOUTH)]
			and outline.all(func(key: Vector3i) -> bool: return _rig._wall_sets.get(key, "wood") == "wood"),
			"its outline walled round both blocks, its door a doorway (%d of %d; %s)" % [walls.size(), outline.size(), doors])
	_test_composer()
	_test_stages()
	_test_window_slot()
	_test_plinth()
	_test_open_kinds()
	_test_plots()
	_test_camp()
	_test_decline()
	_test_inside()
	_test_chimney_smoke()
	_test_turf_house()
	_test_beds_drawn()
	_test_chapel()
	_test_home_label()
	_test_inside_is_his()
	_test_tavern_inside()
	_test_smithy_inside()


## Umbrage's tavern, re-laid (774; the coordinator: "a player who walks into
## the moved inn" must see its inside): on the real wilds, walked in through
## its east door a cell at a time, the view tells it inside, the bounds
## ui's camera frames within the inn's footprint and round the player, and
## the inn's own roof eased off; out again, not inside.
## Umbrage's smithy inside (811 amended (2), off): its forge burning, its
## "fire" part shown and the forge's light at its hearth, as the cold forge's
## once woken; its pieces drawn; the smith's tools gone from the west wall.
func _test_smithy_inside() -> void:
	print("
== Umbrage's smithy inside (811 amended (2)): the forge burning, its pieces drawn ==")
	var level := Level.load_level("umbrage_smithy")
	_rig.rebuild(level["terrain"], level["spawn_points"]["from_wilds"])
	var forges: Array = _rig._buildings.filter(func(building: Dictionary) -> bool: return building.get("rect") == Rect2i(1, 0, 2, 1))
	var forge: Node3D = forges[0]["node"] if forges.size() == 1 else null
	var fire: Node = forge.find_child("ForgeFire", true, false) if forge != null else null
	var light := fire.get_node_or_null("Light") as OmniLight3D if fire != null else null
	var part := forge.find_child("fire", true, false) as Node3D if forge != null else null
	_check(light != null and light in _rig._forge_lights and light.light_color == Client3D.FORGE_COLOUR and part != null and part.visible,
		"the smithy's forge burning: its fire shown, the forge's light at its hearth (%s)" % [fire])
	var drawn: Array = _rig._buildings.map(func(building: Dictionary) -> Rect2i: return building["rect"])
	_check([Rect2i(2, 2, 1, 1), Rect2i(4, 0, 1, 1), Rect2i(0, 4, 1, 1), Rect2i(4, 4, 2, 1)].all(func(rect: Rect2i) -> bool: return rect in drawn),
		"its anvil, trough, grindstone and bench drawn (%s)" % [drawn])
	var tools := _rig._room.get_node_or_null("Decor_0_1_tool_wall_-1_0") as Node3D
	_check(tools != null and is_equal_approx(tools.position.x, -0.5) and is_equal_approx(tools.rotation.y, PI * 0.5),
		"the smith's tool wall hung on the west wall (%s)" % [tools.position if tools != null else null])


func _test_tavern_inside() -> void:
	print("\n== the wilds' tavern, walked into through its door: inside, its own bounds and roof (774) ==")
	var wilds := Level.load_level("wilds")
	_rig.rebuild(wilds["terrain"], wilds["centre"])
	# The inn's shell (the tavern zone: its inside is umbrage_tavern, its way
	# in two cells inside the door; the roof still eases off a player there).
	var inns: Array = (wilds["buildings"] as Array).filter(func(building: Dictionary) -> bool: return str(building.get("use", "")) == "inn")
	var rect: Rect2i = inns[0]["rect"] if inns.size() == 1 else Rect2i()
	var drawn: Array = _rig._buildings.filter(func(building: Dictionary) -> bool: return building.get("rect") == rect)
	_check(rect.size == Vector2i(10, 8) and drawn.size() == 1, "the inn drawn where it stands (%s, %d drawn)" % [rect, drawn.size()])
	if drawn.size() != 1:
		return
	var told: Array = []
	var listen := func(inside: bool, bounds: Rect2i) -> void: told.append([inside, bounds])
	_rig.inside_changed.connect(listen)
	var at := func(cell: Vector2i) -> void:
		_rig._update_roofs([_rig.to_global(Vector3(cell.x, 0.5, cell.y))])
	var path: Array[Vector2i] = [Vector2i(182, 208), Vector2i(181, 208), Vector2i(180, 208), Vector2i(179, 208), Vector2i(178, 208), Vector2i(177, 208), Vector2i(176, 208)]
	var outside := not _rig._indoors(path[0]) and _rig.inside_building() == Rect2i()
	for cell: Vector2i in path:
		at.call(cell)
	var bounds := _rig.inside_building()
	_check(outside and bounds != Rect2i() and rect.encloses(bounds) and bounds.has_point(path.back()) and not told.is_empty() and told.back()[0],
			"walked in through its east door: inside, the camera's bounds %s within the inn %s and round the player at %s" % [bounds, rect, path.back()])
	var roof: Node3D = drawn[0]["roof"]
	for i in 3:
		_rig._fade_clock += Client3D.ROOF_FADE
		at.call(path.back())
	var meshes: Array = _rig._descendants(roof).filter(func(node: Node) -> bool: return node is GeometryInstance3D)
	_check(not meshes.is_empty() and (meshes[0] as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,
			"the inn's own roof eased off over the player")
	at.call(path[0])
	_check(not told.back()[0] and _rig.inside_building() == Rect2i(), "out of its door again: not inside")
	_rig._fade_clock += Client3D.FADE_HOLD + Client3D.ROOF_FADE * 4.0
	at.call(path[0])
	_rig.inside_changed.disconnect(listen)
	# The Mughouse's front (811 amended, art-kit's pieces): its sign out of
	# the street front's wall beside the door; its two-storey walls' windows
	# art-kit's tall wood ones (489 amended (2)), and the lamp on the sill of
	# the one nearest its door, at the ground storey's sill.
	var inn_windows := BuildingComposer.windows(inns[0], wilds["terrain"]["edges"])
	var inn_sill := BuildingComposer.sill_lamp_edge(inns[0], inn_windows)
	var tall_drawn := inn_windows.all(func(key: Vector3i) -> bool: return _rig._wall_states.get(key) == "window") 			and Client3D.window_slot("wood", _rig._height_of(inn_sill)) == "wall.wood.window_tall"
	var inn_lamps: Array = _rig._descendants(_rig._room).filter(func(node: Node) -> bool: return node.name == "SillLamp")
	var inn_sides := Terrain.edge_cells(inn_sill) if inn_sill != BuildingComposer.NO_SILL else [Vector2i.ZERO, Vector2i.ZERO]
	var inn_middle := Vector2(inn_sides[0] + inn_sides[1]) * 0.5
	var inside_cell: Vector2i = inn_sides[0] if rect.has_point(inn_sides[0]) else inn_sides[1]
	var inn_spot := _rig._room.to_local((inn_lamps[0] as Node3D).global_position) if inn_lamps.size() == 1 else Vector3(-9.0, -9.0, -9.0)
	var lift := inn_spot.y - _rig._elevation(inside_cell)
	_check(not inn_windows.is_empty() and tall_drawn and inn_lamps.size() == 1 and Vector2(inn_spot.x, inn_spot.z).distance_to(inn_middle) < 0.05
			and absf(lift - Client3D.SILL_LAMP_LIFT) < 0.05,
			"the Mughouse's %d windows drawn two storeys tall, its lamp on the sill of the one %s nearest its door, %.2f m up" % [inn_windows.size(), inn_sill, lift])
	var sign := _rig._room.get_node_or_null("Decor_180_207_inn_sign_-1_0") as Node3D
	_check(sign != null and is_equal_approx(sign.position.x, 179.5) and is_equal_approx(sign.position.z, 207.0),
			"the inn's sign out of its street front by the door (%s)" % [sign.position if sign != null else null])
	# The slot houses and huts windowed as kinds are (489 amended (3), Jeff:
	# "no windows, no light inside"): a window drawn on every side of each
	# with a straight wall, its door side too, or a wall beside its door
	# (the coordinator: a lit pane from the street), the same every build;
	# each windowed building its
	# light inside, out by day, over its floor's middle.
	var slotted: Array = (wilds["buildings"] as Array).filter(func(building: Dictionary) -> bool:
		return str(building["slot"]) in BuildingComposer.WINDOWED_SLOTS)
	var bare: Array = []
	var undrawn: Array = []
	var unlit: Array = []
	for building: Dictionary in slotted:
		var shown := BuildingComposer.windows(building, wilds["terrain"]["edges"])
		if shown != BuildingComposer.windows(building, wilds["terrain"]["edges"]):
			bare.append(["unsteady", building["rect"]])
		for key: Vector3i in shown:
			if _rig._wall_states.get(key) != "window":
				undrawn.append(key)
		var lines: Dictionary = {}
		var outline := Level.building_outline(building)
		for key: Vector3i in outline:
			var line := Vector2i(key.z, key.x if key.z == Terrain.EAST else key.y)
			if not lines.has(line):
				lines[line] = [false, false]
			var step := Vector3i(0, 1, 0) if key.z == Terrain.EAST else Vector3i(1, 0, 0)
			var kind := func(edge: Vector3i) -> int: return wilds["terrain"]["edges"].get(edge, -1) if edge in outline else -1
			var beyond := [kind.call(key - step), kind.call(key + step)]
			if (kind.call(key) == Terrain.Edge.WALL and Terrain.Edge.WALL in beyond
					and (beyond.count(Terrain.Edge.WALL) == 2 or Terrain.Edge.DOOR in beyond)):
				lines[line][0] = true
			if key in shown:
				lines[line][1] = true
		for line: Vector2i in lines:
			if lines[line][0] and not lines[line][1]:
				bare.append([building["rect"], line])
		var corner: Vector2i = (building["rect"] as Rect2i).position
		var light: OmniLight3D = _rig._house_lights[corner][0] if _rig._house_lights.has(corner) else null
		var box: Rect2i = building["rect"]
		var mid := Vector2(box.position) + Vector2(box.size - Vector2i.ONE) * 0.5
		if (light == null or light.shadow_enabled or Vector2(light.position.x, light.position.z).distance_to(mid) > 0.6
				or not is_equal_approx(light.omni_range, Client3D.house_light_range(box))):
			unlit.append([building["rect"], light.position if light != null else null])
	_check(slotted.size() >= 3 and bare.is_empty() and undrawn.is_empty(),
			"the wilds' %d slot houses and huts windowed on every side with a straight wall, the door's too, drawn as art-kit's (bare %s, undrawn %s)" % [slotted.size(), bare, undrawn])
	_check(unlit.is_empty() and is_equal_approx(Client3D.house_light_range(Rect2i(0, 0, 3, 3)), 2.5)
			and is_equal_approx(Client3D.house_light_range(Rect2i(0, 0, 4, 6)), 4.0) and is_equal_approx(Client3D.house_light_range(Rect2i(0, 0, 10, 8)), 4.5),
			"each its warm light inside, shadowless, over its floor's middle, reaching as far as its room (%s)" % [unlit])
	# Lit only with its windows, and only the nearest HOUSE_LIGHT_NEAR, the
	# one the view's aim stands in first.
	var entries: Array = _rig._house_lights.values()
	var inn_entry: Array = _rig._house_lights.get(rect.position, [])
	var far := Vector2(rect.get_center()) + Vector2(200.0, 0.0)
	var near := Client3D.house_lights_near(entries, Vector2(rect.get_center()), 2)
	var from_far := Client3D.house_lights_near(entries, far, Client3D.HOUSE_LIGHT_NEAR)
	_check(entries.size() > Client3D.HOUSE_LIGHT_NEAR and not inn_entry.is_empty() and near.size() == 2 and near[0] == inn_entry
			and from_far.size() == Client3D.HOUSE_LIGHT_NEAR,
			"the nearest lights picked, the house the aim stands in first (%d lights)" % entries.size())
	var shares := not inn_entry.is_empty() and _rig._window_code.values().any(func(row: Array) -> bool: return is_same(row, inn_entry[1]))
	_check(shares, "the inn's light reads its own windows' row, lit and put out as they are")
	# Each lived-in house's doorway (489 amended (4)): art-kit's doorstep at
	# each front door's foot, its set's variant, and its door lantern beside
	# them, kept on its light's row, its light off the flame as 782
	# amended's, a house's numbers; its flame shown while the house is lit,
	# its light only while picked too.
	var socket: Vector3 = Flames.socket_of(Client3D.DOOR_LAMP_SLOT)
	var doorway_bad: Array = []
	var lamped := 0
	for building: Dictionary in slotted:
		var corner: Vector2i = (building["rect"] as Rect2i).position
		var entry: Array = _rig._house_lights.get(corner, [])
		var own_cells := {}
		for cell in Level.building_cells(building):
			own_cells[cell] = true
		var doors := Client3D.front_doors(building, wilds["terrain"]["edges"], own_cells)
		var steps := 0
		for door: Array in doors:
			var step := _rig._room.get_node_or_null("Doorstep_%d_%d" % [door[0].x, door[0].y]) as Node3D
			if step != null and step.position.distance_to(_rig._tile_position(door[0]) + Vector3(door[1].x, 0.0, door[1].y) * 0.5) < 0.01:
				steps += 1
		if entry.is_empty() or doors.is_empty():
			doorway_bad.append(["no light or door", corner])
			continue
		if steps != doors.size():
			doorway_bad.append(["steps %d of %d" % [steps, doors.size()], corner])
		# Its light on the ground as built, not the ground before it (the
		# room's houses come with its sets, _seat_houses after its ground).
		var ground := 0.0
		for cell in own_cells:
			ground += _rig._tile_position(cell).y
		ground /= maxf(own_cells.size(), 1.0)
		if not is_equal_approx((entry[0] as Node3D).position.y, ground + Client3D.HOUSE_LIGHT_UP):
			doorway_bad.append(["light at %.2f over ground %.2f" % [(entry[0] as Node3D).position.y, ground], corner])
		if entry.size() < 8:
			continue  # A trade building's: its door lamp is 782's (_hang_door_lamps).
		lamped += 1
		var lamp_light := entry[4] as OmniLight3D
		var piece := entry[7] as Node3D
		if (piece == null or lamp_light.get_parent() != piece or not lamp_light.position.is_equal_approx(socket + Client3D.DOOR_LAMP_ART_LIGHT)
				or not is_equal_approx(lamp_light.omni_range, Client3D.HOUSE_DOOR_LAMP_RANGE) or lamp_light.shadow_enabled or entry[5] == null):
			doorway_bad.append(["lamp", corner])
			continue
		var shown: Array = []
		for state: Array in [[false, false], [true, false], [true, true]]:
			Client3D._show_house_lamp(entry, state[0], state[1])
			shown.append([(entry[5] as Node3D).visible, lamp_light.visible])
		if shown != [[false, false], [true, false], [true, true]]:
			doorway_bad.append(["shown %s" % [shown], corner])
	_check(lamped >= 3 and doorway_bad.is_empty() and Client3D.DOORSTEP_VARIANTS == {"wood": 1, "stone": 2},
			"each lived-in house its doorstep at each front door and its lantern beside them, its light %.2f m off the wall, %.1f m up, lit with its house, picked with it (%d lamps; bad %s)"
			% [(socket + Client3D.DOOR_LAMP_ART_LIGHT).x, (socket + Client3D.DOOR_LAMP_ART_LIGHT).y, lamped, doorway_bad])
	var lamp_spot := Client3D.house_lamp_at([[Vector2i(3, 8), Vector2i(0, 1)], [Vector2i(4, 8), Vector2i(0, 1)]],
		[Vector3(3.0, 0.0, 8.5), Vector3(4.0, 0.0, 8.5)], true)
	_check(lamp_spot.is_equal_approx(Vector3(3.0 - Client3D.DOOR_LAMP_ASIDE, 0.0, 8.5 + Client3D.DOOR_LAMP_STONE)),
			"a two-door front's lantern beside its last door, on a stone wall %.1f m further out (%s)" % [Client3D.DOOR_LAMP_STONE, lamp_spot])
	_check(Client3D.window_slot("stone", Client3D.WALL_HEIGHT) == ("wall.stone.window_house" if ArtKit.has("wall.stone.window_house") else "")
			and Client3D.window_slot("wood", Client3D.WALL_HEIGHT) == "wall.wood.window",
			"a stone house's one-storey wall its shuttered window_house (never the castle's grate), a wood one's wall.wood.window (%s)" % Client3D.window_slot("stone", Client3D.WALL_HEIGHT))
	# Inside, its common room's fireplace over the hearth's two fire cells,
	# its back to the west wall, at their middle.
	var ground := Level.load_level("umbrage_tavern")
	_rig.rebuild(ground["terrain"], ground["spawn_points"]["from_wilds"])
	# Its way out the inside of its front door (Jeff: "no door to exit"):
	# a door.double in the south wall over the doorstep's two cells, as the
	# inn's outline has it outside.
	var front_door := Vector3i(5, 13, Terrain.SOUTH)
	_check(bool(ground["terrain"].get("interior", false)) and _rig._doorways.has(front_door)
		and _rig._double_doors().get(front_door) == Vector3i(6, 13, Terrain.SOUTH),
		"the Mughouse's way out a double door in its south wall (%s)" % [_rig._double_doors().get(front_door)])
	var hearth := _rig._room.get_node_or_null("Decor_0_6_wall_hearth_-1_0") as Node3D
	_check(hearth != null and is_equal_approx(hearth.position.x, -0.5) and is_equal_approx(hearth.position.z, 6.5)
			and is_equal_approx(hearth.rotation.y, PI * 0.5),
			"the Mughouse's fireplace against its west wall, over its two fire cells (%s)" % [hearth.position if hearth != null else null])
	# Its common room's candles (811 amended (4), environment's numbers):
	# five, on its four tables and its bar, each lit over its top, warm,
	# shadowless, at its reach, flickering with the fires.
	var candle_lights: Array[OmniLight3D] = []
	var candles_bad: Array = []
	for entry: Dictionary in ground["terrain"].get("lit_candles", []):
		var candle_at: Vector2 = entry["at"]
		var candle_tag := "%d_%d" % [roundi(candle_at.x * 2.0), roundi(candle_at.y * 2.0)]
		var candle_top := _rig._height_in(Vector2i(roundi(candle_at.x), roundi(candle_at.y)), candle_at) + float(entry["top"])
		var candle_light := _rig._room.get_node_or_null("CandleLight_" + candle_tag) as OmniLight3D
		var candle_piece := _rig._room.get_node_or_null("Candles_" + candle_tag) as Node3D
		if (candle_light == null or candle_piece == null or candle_light.shadow_enabled
				or not candle_light.position.is_equal_approx(Vector3(candle_at.x, candle_top + float(entry["up"]), candle_at.y))
				or not candle_piece.position.is_equal_approx(Vector3(candle_at.x, candle_top, candle_at.y))
				or not is_equal_approx(candle_light.omni_range, float(entry.get("reach", Client3D.CANDLE_RANGE)))
				or not is_equal_approx(candle_light.omni_attenuation, float(entry.get("falloff", Client3D.CANDLE_FALLOFF)))
				or candle_light.light_color != Client3D.HOUSE_LIGHT
				or not _rig._fire_lights.any(func(fire: Array) -> bool: return fire[0] == candle_light)):
			candles_bad.append(candle_tag)
		if candle_light != null:
			candle_lights.append(candle_light)
	_check(candle_lights.size() == 5 and candles_bad.is_empty() and is_equal_approx(float(ground["terrain"]["ambient"]), 0.35),
			"the Mughouse's candles lit on its four tables and its bar, warm and shadowless, over their tops (%d, wrong %s)" % [candle_lights.size(), candles_bad])
	# A shell's lamp (811 amended, art-kit's prop.sill_lamp): one, on the
	# sill of its window nearest its door, at the sill's height; none on a
	# building that is no shell.
	var level := _kinds_level([["building_l_house_small", Vector2i(1, 1), false]])
	var house: Dictionary = level["buildings"][0]
	house["inside"] = "a_shell"
	var windows := BuildingComposer.windows(house, level["terrain"]["edges"])
	var sill := BuildingComposer.sill_lamp_edge(house, windows)
	_rig.rebuild(level["terrain"], Vector2i(12, 12))
	var lamps: Array = _rig._descendants(_rig._room).filter(func(node: Node) -> bool: return node.name == "SillLamp")
	var spot := _rig._room.to_local((lamps[0] as Node3D).global_position) if lamps.size() == 1 else Vector3(-9.0, -9.0, -9.0)
	var sides := Terrain.edge_cells(sill) if sill != BuildingComposer.NO_SILL else [Vector2i.ZERO, Vector2i.ZERO]
	var middle := Vector2(sides[0] + sides[1]) * 0.5
	_check(sill in windows and lamps.size() == 1 and Vector2(spot.x, spot.z).distance_to(middle) < 0.05
			and spot.y - _rig._height_in(sides[0], middle) > Client3D.SILL_LAMP_LIFT - 0.05,
			"a shell's lamp on the sill of its window %s nearest its door (%s)" % [sill, spot])
	_check(BuildingComposer.sill_lamp_edge(house.merged({"inside": ""}, true), windows) == BuildingComposer.NO_SILL
			and BuildingComposer.sill_lamp_edge(house, [] as Array[Vector3i]) == BuildingComposer.NO_SILL,
			"no lamp on a building that is no shell, nor on a shell with no window")
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## Which window a wall takes by its height (489 amended (2)): a wood wall
## of a storey its plain window; two storeys a tall one only once the set
## has one (art-kit's wall.wood.window_tall, here a stand-in), never on a
## one-storey wall; between, none; a set with no plain window (the
## chapel's lancets) its tall one on any wall, drawn at a storey; a wood
## tall window drawn two storeys high.
func _test_window_slot() -> void:
	print("
== a wall's window by its height: one storey or two (489 amended (2)) ==")
	var slots := ArtKit.slots()
	var had := slots.has("wall.wood.window_tall")
	var saved: Variant = slots.get("wall.wood.window_tall")
	slots.erase("wall.wood.window_tall")
	var c := Client3D
	var h := Client3D.WALL_HEIGHT
	var bare := [c.window_slot("wood", h), c.window_slot("wood", 2.0 * h)]
	_check(bare == ["wall.wood.window", ""], "without a tall wood window: the plain one at a storey, none at two (%s)" % [bare])
	slots["wall.wood.window_tall"] = {"category": "walls", "kind": "edge", "size": [0.3, 2.0 * h, 1.0]}
	var tall := [c.window_slot("wood", h), c.window_slot("wood", h + 0.4), c.window_slot("wood", 1.5 * h), c.window_slot("wood", 2.0 * h)]
	_check(tall == ["wall.wood.window", "wall.wood.window", "", "wall.wood.window_tall"],
			"with one: the plain window on a storey's wall, the tall one on two storeys', none between (%s)" % [tall])
	_check(is_equal_approx(c.window_drawn_height("wall.wood.window_tall"), 2.0 * h) and is_equal_approx(c.window_drawn_height("wall.wood.window"), h),
			"the tall wood window drawn two storeys high, the plain one one")
	slots.erase("wall.wood.window_tall")
	if had:
		slots["wall.wood.window_tall"] = saved
	var lancet := c.window_slot("chapel", 4.5)
	_check((lancet == "wall.chapel.window_tall") == ArtKit.has("wall.chapel.window_tall") and is_equal_approx(c.window_drawn_height("wall.chapel.window_tall"), h),
			"the chapel's lancet on its wall whatever its height, drawn as before (%s)" % [lancet])


## A building being built (decision 566): its stages by its town record's
## progress (its plot staked, no wall nor post; its frame's corner posts
## and sills; its walls cut to a part of their height, its door not yet
## hung; standing again as built), a raise's scaffold, where its carpenter
## works, and when a window is lit.
func _test_stages() -> void:
	print("\n== a building being built: its stages, its site, its lamps (decision 566) ==")
	var c := BuildingComposer
	var stages := [c.stage({"state": Towns.PLANNED}), c.stage({"state": Towns.PLANNED, "progress": 0.2}),
		c.stage({"state": Towns.PLANNED, "progress": 0.5}), c.stage({"state": Towns.BUILDING, "level": 0, "progress": 0.8}),
		c.stage({"state": Towns.PLANNED, "progress": 0.95}), c.stage({"state": Towns.STANDING}),
		c.stage({"state": Towns.BUILDING, "level": 1, "progress": 0.3})]
	_check(stages == [c.PLOT, c.FRAME, c.WALLS + 1, c.RAFTERS, c.COVERING, c.STANDING, c.STANDING],
			"its stages by progress, a planned one staked (%s)" % [stages])
	_check(c.scaffolded({"state": Towns.BUILDING, "level": 1, "progress": 0.3}) and c.scaffolded({"state": Towns.DAMAGED, "progress": 0.1})
			and not c.scaffolded({"state": Towns.DAMAGED}) and not c.scaffolded({"state": Towns.PLANNED, "progress": 0.2}),
			"scaffold on a raise or a repair under way, not on a first build's record alone")
	var level := _kinds_level([["building_l_house_small", Vector2i(1, 1), false]])
	var parsed: Dictionary = level["buildings"][0]
	var site := Level.site_cells(parsed)
	var cells := Level.building_cells(parsed)
	var front: Vector2i = parsed["front"]
	_check(cells.has(site["work"]) and not cells.has(site["woodpile"]) and (site["woodpile"] - front).length_squared() == 1
			and Terrain.edge_key(site["work"], front - (site["work"] as Vector2i)) == parsed["doors"][0],
			"its carpenter works inside its door (%s), its woodpile beside its front (%s)" % [site["work"], site["woodpile"]])
	var buck: Vector2i = site["sawbuck"]
	var saw: Vector2i = site["saw"]
	_check(not cells.has(buck) and not cells.has(saw) and buck != site["woodpile"] and saw != site["woodpile"]
			and (saw - buck).length_squared() == 1 and saw - buck == front - (site["work"] as Vector2i),
			"its sawbuck off it and its woodpile (%s), its sawyer a step further from its door, facing it (%s)" % [buck, saw])
	_rig.rebuild(level["terrain"], Vector2i(4, 11))
	var house: Dictionary = _rig._buildings[0]
	house["use"] = "house"
	house["town_id"] = "stage_town"
	var outline: Array = house["outline"]
	var full: Dictionary = (house["heights"] as Dictionary).duplicate()
	var windows: Array = (house["windows"] as Array).duplicate()
	var node: Node3D = house["node"]
	var roof: Node3D = node.get_node("roof")
	var walls_at := func() -> Array: return outline.filter(func(key: Vector3i) -> bool: return _rig._walls.has(key))
	var posts_at := func() -> Array:
		var out := []
		for key: Vector3i in outline:
			for end in 2:
				var vertex := WallEdge.vertex_at(key, end)
				if _rig._posts.has(vertex) and not out.has(vertex):
					out.append(vertex)
		return out
	var door: Vector3i = parsed["doors"][0]
	_rig.set_town("stage_town", {"house": {"state": Towns.PLANNED, "level": 0, "progress": 0.0}})
	_check(node.has_node("Site/Woodpile") and node.has_node("Site/Sawhorse") and node.find_child("Stake", true, false) != null and not roof.visible and house["roof"] == null
			and walls_at.call().is_empty() and posts_at.call().is_empty() and not (_rig._doorways[door] as Node3D).visible,
			"planned: its plot staked, a woodpile, no wall, post, door or roof (%d walls, %d posts)" % [walls_at.call().size(), posts_at.call().size()])
	_rig.set_town("stage_town", {"house": {"state": Towns.PLANNED, "level": 0, "progress": 0.2}})
	_check(node.find_child("Sill", true, false) != null and node.find_child("Stake", true, false) == null
			and walls_at.call().is_empty() and posts_at.call().size() >= 6,
			"its frame: sills and its corner posts (%d), no wall yet" % posts_at.call().size())
	_rig.set_town("stage_town", {"house": {"state": Towns.PLANNED, "level": 0, "progress": 0.5}})
	var half := outline.all(func(key: Vector3i) -> bool:
		return _rig._terrain["edges"].get(key) != Terrain.Edge.WALL or is_equal_approx(_rig._height_of(key), float(full[key]) * 0.5))
	_check(walls_at.call().size() > 10 and half and not (_rig._doorways[door] as Node3D).visible
			and not _rig._wall_states.values().has("window") and node.find_child("Bay", true, false) != null,
			"its walls half their height, scaffold up, no window or door yet")
	var lamps := func() -> Array:
		var out := []
		for each: Array in _rig._glows:
			if is_instance_valid(each[0]):
				out.append(_rig._window_lit(each[1], 20.0, -5.0))
		return out
	_rig.set_town("stage_town", {"house": {"state": Towns.PLANNED, "level": 0, "progress": 0.95}})
	var covering: Array = lamps.call()
	_check(not covering.is_empty() and not covering.has(true),
			"its roof going on: its windows in, their lamps out, nobody living there yet (%s)" % [covering])
	_rig.set_town("stage_town", {"house": {"state": Towns.STANDING, "level": 1}})
	var standing: Array = lamps.call()
	_check(not standing.is_empty() and not standing.has(false), "standing: its lamps lit at 20 o'clock (%s)" % [standing])
	var restored := outline.all(func(key: Vector3i) -> bool: return is_equal_approx(_rig._height_of(key), float(full[key])))
	var back := outline.filter(func(key: Vector3i) -> bool: return _rig._wall_states.get(key) == "window")
	_check(not node.has_node("Site") and roof.visible and house["roof"] == roof and restored and back.size() == windows.size()
			and (_rig._doorways[door] as Node3D).visible,
			"standing: its roof on, its walls whole, its %d windows and its door back" % windows.size())
	_rig.set_town("stage_town", {"house": {"state": Towns.BUILDING, "level": 1, "progress": 0.4}})
	_check(node.find_child("Bay", true, false) != null and roof.visible and restored,
			"a level raised: the building standing, in scaffold")
	_rig.set_town("stage_town", {})
	var lit := [Client3D.lamp_lit({}, "H1", 20.0, -5.0), Client3D.lamp_lit({}, "H1", 23.0, -5.0), Client3D.lamp_lit({"H1": true}, "H1", 23.0, -5.0),
		Client3D.lamp_lit({"H1": false}, "H1", 20.0, -5.0), Client3D.lamp_lit({"H1": true}, "H1", 13.0, 40.0)]
	_check(lit == [true, false, true, false, false],
			"a window lit with the sun down: as its building's awake says, else till 22 (%s)" % [lit])


## The plinth (decision 489 amended): a kind's wood walls on a stone band
## PLINTH_HEIGHT over its pad, down to the lowest ground beside them on a
## slope; its walls, posts and roof on its pad, not the ground outside; a
## stone kind none.
func _test_plinth() -> void:
	print("\n== a kind's wood walls on a stone plinth, on its pad (decision 489 amended) ==")
	var level := _kinds_level([["building_l_house_small", Vector2i(1, 1), false], ["building_cottage_small", Vector2i(13, 1), false]], 0.3)
	var warned := (level["warnings"] as Array).filter(func(each: String) -> bool: return not each.begins_with("no player start"))
	_check(warned.is_empty(), "the sloped plot parses, its pads level (%s)" % [warned])
	_rig.rebuild(level["terrain"], Vector2i(4, 20))
	var house: Dictionary = level["buildings"][0]
	var cottage: Dictionary = level["buildings"][1]
	var pad := _rig._elevation(Level.building_cells(house)[0])
	var walls := Level.building_outline(house).filter(func(key: Vector3i) -> bool:
		return _rig._terrain["edges"].get(key) == Terrain.Edge.WALL)
	var on_pad := walls.all(func(key: Vector3i) -> bool:
		return _rig._walls.has(key) and is_equal_approx((_rig._walls[key] as Node3D).position.y, pad))
	var plinths := walls.all(func(key: Vector3i) -> bool: return _rig._walls.has(key) and (_rig._walls[key] as Node3D).has_node("Plinth"))
	var deepest := 0.0
	var reached := true
	for key: Vector3i in walls:
		if not _rig._walls.has(key):
			continue
		var plinth := (_rig._walls[key] as Node3D).get_node_or_null("Plinth") as MeshInstance3D
		if plinth == null:
			continue
		var box := plinth.mesh.get_aabb()
		reached = reached and is_equal_approx(box.end.y, Client3D.PLINTH_HEIGHT)
		for cell in Terrain.edge_cells(key):
			var below := _rig._elevation(cell) - pad
			deepest = minf(deepest, below)
			reached = reached and box.position.y <= below
	_check(on_pad and plinths and reached and deepest < -0.2,
			"the L-house's walls on its pad, each on a plinth %.1f m up, down to the ground %.2f m below it" % [Client3D.PLINTH_HEIGHT, -deepest])
	var posts := true
	for key: Vector3i in walls:
		for end in 2:
			var vertex := WallEdge.vertex_at(key, end)
			if _rig._posts.has(vertex):
				posts = posts and is_equal_approx((_rig._posts[vertex] as Node3D).position.y, pad)
	var roofed := _rig._buildings.filter(func(each: Dictionary) -> bool: return each.get("kind") == house)
	_check(posts and not roofed.is_empty() and is_equal_approx((roofed[0]["node"] as Node3D).position.y, pad),
			"its posts and its roof on its pad too")
	var stone := Level.building_outline(cottage).filter(func(key: Vector3i) -> bool:
		return _rig._walls.has(key) and (_rig._walls[key] as Node3D).has_node("Plinth"))
	_check(stone.is_empty() and str(cottage["wall_set"]) == "stone", "the stone cottage has none")


## Open edges (591): a market hall on posts all round, a forge's front on
## posts under its lean-to's low eave; no wall on either.
func _test_open_kinds() -> void:
	print("
== kinds with open edges on posts: a market hall, a forge's front (decision 591) ==")
	var level := _kinds_level([["building_market_large", Vector2i(1, 1), false], ["building_forge_small", Vector2i(12, 1), false]])
	var market: Dictionary = level["buildings"][0]
	var forge: Dictionary = level["buildings"][1]
	var hall := BuildingComposer.compose(market, Client3D.KIND_ROOF)
	var smithy := BuildingComposer.compose(forge, Client3D.KIND_ROOF)
	var posts := func(node: Node3D) -> Array:
		return node.get_node("parts").get_children().filter(func(each: Node) -> bool: return each.name.begins_with("OpenPost"))
	var hall_posts: Array = posts.call(hall)
	var front_posts: Array = posts.call(smithy)
	var low := true
	for post: Node3D in front_posts:
		var height := post.scale.y * Client3D.WALL_HEIGHT if post.get_child_count() > 0 else ((post as MeshInstance3D).mesh as BoxMesh).size.y
		low = low and height < float(forge["eaves"]) - 0.1
	var no_walls := Level.building_outline(market).all(func(key: Vector3i) -> bool: return not level["terrain"]["edges"].has(key))
	_check(no_walls and hall_posts.size() >= 12 and hall.get_node("roof").get_child_count() > 0,
			"the market hall: no wall, its roof on %d posts round it" % hall_posts.size())
	_check(front_posts.size() >= 2 and low and (forge["open"] as Array).size() == 6,
			"the forge's open front on %d posts, under its lean-to's low eave" % front_posts.size())
	hall.free()
	smithy.free()


## A town's laid plots (591 amended, maps' Level.plot_building) drawn as
## their kinds, raised by their records' stages (566): staked with no
## record, never standing for being laid; one laid live drawn at once;
## one dropped (649) gone.
func _test_plots() -> void:
	print("
== a town's laid plots: staked till its record raises it, one laid live drawn (591 amended) ==")
	var level := _kinds_level([])
	var terrain: Dictionary = level["terrain"]
	var town := "plot_zone/plot_town"
	var house_rect := Rect2i(Vector2i(1, 1), Level.plot_of("house") + Vector2i(2, 2))
	Clearing.lay_plots(terrain, [{"town": town, "kind": "house", "use": "house", "rect": house_rect, "facing": Vector2i(0, 1), "size": "small"}])
	_check((terrain["plot_buildings"] as Array).size() == 1, "the house's plot is laid as its kind (%s)" % [terrain.get("plot_buildings")])
	_rig.rebuild(terrain, Vector2i(5, 18))
	var plots := _rig._buildings.filter(func(each: Dictionary) -> bool: return each.get("plot", false))
	var house: Dictionary = plots[0] if plots.size() == 1 else {}
	var walls_at := func(entry: Dictionary) -> Array:
		return (entry["outline"] as Array).filter(func(key: Vector3i) -> bool: return _rig._walls.has(key))
	_check(not house.is_empty() and house["stage"] == BuildingComposer.PLOT and walls_at.call(house).is_empty()
			and (house["node"] as Node3D).find_child("Stake", true, false) != null,
			"no record yet: its plot staked, no wall (%s)" % [house.get("stage")])
	_rig.set_town(town, {"house": {"state": Towns.PLANNED, "level": 0, "progress": 0.0}})
	_check(house["stage"] == BuildingComposer.PLOT, "planned: still staked")
	_rig.set_town(town, {"house": {"state": Towns.BUILDING, "level": 0, "progress": 0.5}})
	_check(house["stage"] > BuildingComposer.FRAME and house["stage"] < BuildingComposer.STANDING and walls_at.call(house).size() > 6,
			"half built: its walls going up (%d)" % walls_at.call(house).size())
	_rig.set_town(town, {"house": {"state": Towns.STANDING, "level": 1}})
	_check(house["stage"] == BuildingComposer.STANDING and house["roof"] != null, "standing: whole, roofed")
	# One laid while the view is up (Main: Clearing.lay_plots, then clearing_changed).
	var shed_rect := Rect2i(Vector2i(13, 1), Level.plot_of("shed") + Vector2i(2, 2))
	Clearing.lay_plots(_rig._terrain, [{"town": town, "kind": "shed", "use": "shed", "rect": shed_rect, "facing": Vector2i(0, 1), "size": "small"}])
	var before := _rig._buildings.size()
	_rig.clearing_changed(_rig._terrain, [])
	var shed: Dictionary = _rig._buildings.back() if _rig._buildings.size() == before + 1 else {}
	_check(not shed.is_empty() and shed.get("plot", false) and shed["stage"] == BuildingComposer.PLOT
			and shed_rect.encloses(shed["rect"]) and walls_at.call(shed).is_empty(),
			"a plot laid live: drawn at once, staked (%d buildings, was %d)" % [_rig._buildings.size(), before])
	_rig.clearing_changed(_rig._terrain, [])
	_check(_rig._buildings.size() == before + 1, "and drawn once")
	_rig.set_town(town, {"house": {"state": Towns.STANDING, "level": 1}, "shed": {"state": Towns.STANDING, "level": 1}})
	_check(shed["stage"] == BuildingComposer.STANDING and walls_at.call(shed).size() > 6, "its record standing: its walls up (%d)" % walls_at.call(shed).size())
	# Dropped (649; Main: Clearing.unlay_plot takes its building and edges out, then clearing_changed).
	var shed_built: Dictionary = (_rig._terrain["plot_buildings"] as Array).back()
	(_rig._terrain["plot_buildings"] as Array).erase(shed_built)
	for key: Vector3i in Level.building_outline(shed_built):
		(_rig._terrain["edges"] as Dictionary).erase(key)
	_rig.clearing_changed(_rig._terrain, [])
	var inside_left := (shed["inside"] as Dictionary).keys().any(func(cell: Vector2i) -> bool: return _rig._building_at.has(cell))
	_check(shed.get("dropped", false) and not (shed["node"] as Node3D).visible and walls_at.call(shed).is_empty() and not inside_left,
			"a plot dropped: its building gone, no wall, no inside (%d walls)" % walls_at.call(shed).size())
	_rig.set_town(town, {"house": {"state": Towns.STANDING, "level": 1}, "shed": {"state": Towns.BUILDING, "level": 0, "progress": 0.5}})
	_check(not (shed["node"] as Node3D).visible and walls_at.call(shed).is_empty() and house["stage"] == BuildingComposer.STANDING,
			"and its town's record raises nothing of it; the house stands")
	Clearing.lay_plots(_rig._terrain, [{"town": town, "kind": "shed", "use": "shed", "rect": shed_rect, "facing": Vector2i(0, 1), "size": "small"}])
	_rig.clearing_changed(_rig._terrain, [])
	var again: Dictionary = _rig._buildings.back()
	_check(again != shed and again.get("plot", false) and not again.get("dropped", false) and (again["node"] as Node3D).visible,
			"laid again there: drawn anew")
	_rig.town_states.erase(town)


## A settlement's camp (649): tents and a fire ring, no roof, no posts.
func _test_camp() -> void:
	print("\n== a camp: its tents and fire ring, open to the sky (649) ==")
	var level := _kinds_level([["building_camp_small", Vector2i(1, 1), false], ["building_camp_large", Vector2i(10, 1), false]])
	var small := BuildingComposer.compose(level["buildings"][0], Client3D.KIND_ROOF)
	var large := BuildingComposer.compose(level["buildings"][1], Client3D.KIND_ROOF)
	var named := func(node: Node3D, prefix: String) -> int:
		return node.get_node("parts").get_children().filter(func(each: Node) -> bool: return each.name.begins_with(prefix)).size()
	var art := ArtKit.has("prop.tent") and ArtKit.has("prop.campfire")
	_check(not small.has_node("roof") and not large.has_node("roof") and named.call(small, "OpenPost") == 0,
			"no roof over a camp, nor posts round it")
	_check(not art or named.call(small, "Tent") == 1 and named.call(large, "Tent") == 2 and named.call(small, "Campfire") == 1,
			"a small camp's one tent, a large one's two, each a fire ring (%d, %d)" % [named.call(small, "Tent"), named.call(large, "Tent")])
	if art:
		var apart := ((large.get_node("parts/Tent_0") as Node3D).position - (large.get_node("parts/Tent_1") as Node3D).position).length()
		_check(apart >= 3.0, "the large camp's two tents well apart, not into each other (%.1f)" % apart)
	small.free()
	large.free()


## A building in decline (649): disrepair worn, a ruin's rubble, gone hidden,
## and built again whole.
func _test_decline() -> void:
	print("\n== a building in decline: worn, a ruin, gone, built again (649) ==")
	var level := _kinds_level([["building_house_small", Vector2i(2, 2), false]])
	_rig.rebuild(level["terrain"], Vector2i(4, 14))
	var house: Dictionary = _rig._buildings[0]
	house["use"] = "house"
	house["town_id"] = "decline_town"
	var outline: Array = house["outline"]
	var node: Node3D = house["node"]
	var walls := outline.filter(func(key: Vector3i) -> bool: return _rig._terrain["edges"].get(key) == Terrain.Edge.WALL)
	var states := func(state: String) -> int:
		return walls.filter(func(key: Vector3i) -> bool: return _rig._wall_states.get(key, "") == state).size()
	var lit := func() -> bool:
		return walls.any(func(key: Vector3i) -> bool: return _rig._window_code.has(key) and bool(_rig._window_code[key][2]))
	_rig.set_town("decline_town", {"house": {"state": Towns.DISREPAIR, "level": 1}})
	_check(house["damaged"] and house["decline"] == Towns.DISREPAIR and node.visible and not lit.call()
			and (not ArtKit.has("scatter.tuft") or is_instance_valid(house.get("weeds"))),
			"in disrepair: worn as damaged, its lamps out, weeds at its foot")
	_rig.set_town("decline_town", {"house": {"state": Towns.RUIN, "level": 0, "walls": false}})
	var posts := func() -> Array:
		var out := []
		for key: Vector3i in outline:
			for end in 2:
				var vertex := WallEdge.vertex_at(key, end)
				if _rig._posts.has(vertex) and not out.has(vertex):
					out.append(vertex)
		return out
	# The plinth along the house's walls, from its top faces: [lowest top,
	# highest top, metres of run it covers]. Broken off and open in a ruin.
	var plinth_tops := func() -> Array:
		var seen := []
		var low := INF
		var high := 0.0
		var covered := 0.0
		for key: Vector3i in walls:
			var run: Node3D = _rig._walls.get(key)
			var band := run.get_node_or_null("Plinth") as MeshInstance3D if is_instance_valid(run) else null
			if band == null or seen.has(band):
				continue
			seen.append(band)
			var arrays := band.mesh.surface_get_arrays(0)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in range(0, points.size(), 4):
				if normals[i].y < 0.9:
					continue
				low = minf(low, points[i].y)
				high = maxf(high, points[i].y)
				var zs := [points[i].z, points[i + 1].z, points[i + 2].z, points[i + 3].z]
				covered += zs.max() - zs.min()
		return [snappedf(low, 0.01), snappedf(high, 0.01), snappedf(covered, 0.1)]
	var plinths: Array = walls.filter(func(key: Vector3i) -> bool: return _rig._plinths.has(key))
	var ruined: Array = plinth_tops.call()
	_check(plinths.is_empty() or ruined[0] < Client3D.PLINTH_HEIGHT * 0.2 and ruined[1] <= Client3D.PLINTH_HEIGHT + 0.01
			and ruined[2] < plinths.size() * 0.8,
			"a ruin's plinth broken off and open: tops %.2f to %.2f m (whole %.2f), %.1f m of its %d edges" % [ruined[0], ruined[1], Client3D.PLINTH_HEIGHT, ruined[2], plinths.size()])
	var floored := func() -> int:
		return Level.rect_cells(house["rect"]).filter(func(cell: Vector2i) -> bool: return _rig._floor_sets.has(cell)).size()
	var cells: int = Level.rect_cells(house["rect"]).size()
	var dirt := func() -> int:
		return Level.rect_cells(house["rect"]).filter(func(cell: Vector2i) -> bool: return _rig._ground_kinds.get(cell, "dirt") == "dirt").size()
	var mix := [states.call("rubble"), states.call("broken"), states.call("plot")]
	var litter: int = (house["weeds"] as Node3D).get_child_count() if is_instance_valid(house.get("weeds")) else 0
	_check(node.visible and house["roof"] == null and mix[0] > 0 and mix[1] > 0 and mix[2] > 0 and mix[0] + mix[1] + mix[2] == walls.size()
			and not (node.get_node("parts") as Node3D).visible and posts.call().is_empty(),
			"a ruin: its walls rubble, stubs and gaps (%s of %d), no roof, no post standing over it (%s)" % [mix, walls.size(), posts.call()])
	_check(floored.call() > 0 and floored.call() < cells and dirt.call() >= cells - floored.call()
			and (not ArtKit.has("scatter.tuft") or litter > walls.size() / Client3D.WEED_EVERY / 2),
			"a ruin's floor: boards on %d of %d cells, the rest bare ground; %d weeds and litter in it" % [floored.call(), cells, litter])
	var worn_byte: int = Client3D.FLOOR_SETS["wood"] + Client3D.FLOOR_WORN
	var bytes_of := func(byte: int) -> int:
		return Level.rect_cells(house["rect"]).filter(func(cell: Vector2i) -> bool: return _rig._floor_bytes_at(cell) == byte).size()
	_check(bytes_of.call(worn_byte) == floored.call(), "a ruin's boards weathered: %d of its %d kept cells drawn worn" % [bytes_of.call(worn_byte), floored.call()])
	# The wall pieces over its plinth's gone halves fallen with it.
	var fallen := 0
	for key: Vector3i in walls:
		var run: Node3D = _rig._walls.get(key)
		for piece: Node in run.get_children() if is_instance_valid(run) else []:
			fallen += 1 if piece.name.begins_with("Piece_") and (piece as Node3D).position.y < -0.01 else 0
	_check(plinths.is_empty() or fallen > 0, "a ruin's wall pieces over its gone plinth fallen with it (%d)" % fallen)
	_rig.set_town("decline_town", {"house": {"state": "gone", "level": 0, "walls": false}})
	_check(not node.visible and states.call("plot") == walls.size() and not is_instance_valid(house.get("weeds")) and floored.call() == 0
			and dirt.call() == cells,
			"gone: nothing of it drawn, its plot bare ground (%d of %d walls none, %d floor cells, %d of %d dirt)" % [states.call("plot"), walls.size(), floored.call(), dirt.call(), cells])
	_rig.set_town("decline_town", {"house": {"state": Towns.STANDING, "level": 1}})
	_check(node.visible and house["roof"] != null and house["decline"] == "" and not house["damaged"]
			and states.call("plot") == 0 and states.call("rubble") == 0 and states.call("broken") == 0 and not is_instance_valid(house.get("weeds"))
			and floored.call() == cells and dirt.call() < cells and not posts.call().is_empty(),
			"built again: whole, roofed, its walls, posts, floor and ground back (%d floor, %d dirt of %d)" % [floored.call(), dirt.call(), cells])
	var whole: Array = plinth_tops.call()
	_check(plinths.is_empty() or whole[0] == snappedf(Client3D.PLINTH_HEIGHT, 0.01) and whole[1] == whole[0] and whole[2] >= plinths.size(),
			"built again: its plinth whole (%d edges, tops %.2f to %.2f m, %.1f m)" % [plinths.size(), whole[0], whole[1], whole[2]])
	_check(bytes_of.call(worn_byte) == 0 and bytes_of.call(Client3D.FLOOR_SETS["wood"]) == cells,
			"built again: its boards new (%d worn, %d of %d plain)" % [bytes_of.call(worn_byte), bytes_of.call(Client3D.FLOOR_SETS["wood"]), cells])
	_rig.town_states.erase("decline_town")


## Chimney smoke (the coordinator, from ui's trailer takes: Umbrage's forge
## showed none): a slot forge or kitchen given a chimney (slot_chimney), a
## composed kind's chimney its own; each smokes while its building is
## said awake (someone awake inside, the "town" message's "awake") and
## stands, never in ruin, never with nobody known inside.
func _test_chimney_smoke() -> void:
	print("
== chimney smoke: a forge's fire in use, a lived-in house's hearth ==")
	var terrain := _building_terrain()
	for building: Dictionary in terrain["buildings"]:
		if building["slot"] == "building.house":
			building["use"] = "forge"
			building["town_id"] = "smoke_town/square"
			building["code"] = "H1"
	_rig.rebuild(terrain, Vector2i(7, 7))
	var forge: Dictionary = _rig._buildings.filter(func(b: Dictionary) -> bool: return b["use"] == "forge")[0]
	var hut: Dictionary = _rig._buildings.filter(func(b: Dictionary) -> bool: return b["rect"] == Rect2i(10, 3, 3, 3))[0]
	var smoke: Node3D = forge.get("smoke")
	# A lived-in house slot's chimney at its art's socket (489 amended (4)):
	# the house's stack at "chimney_seat", the hut's vent at "chimney".
	var seat_of := func(slot: String, name: String) -> Variant:
		var at: Variant = (ArtKit.spec(slot).get("sockets", {}) as Dictionary).get(name)
		return Vector3(float(at[0]), float(at[1]), float(at[2])) if at is Array else null
	var forge_chimney := (forge["node"] as Node3D).find_child("Chimney", true, false) as Node3D
	var hut_chimney := (hut["node"] as Node3D).find_child("Chimney", true, false) as Node3D
	_check(smoke != null and forge_chimney != null and hut.get("smoke") != null and hut_chimney != null,
			"a slot house given a chimney and its smoke, a hut its vent and its smoke")
	if forge_chimney != null and hut_chimney != null:
		# Its foot at the seat's x and z but at the eaves, its lower part in
		# the roof (art-kit: the seat is where the stack meets the roof).
		var seat: Vector3 = seat_of.call("building.house", "chimney_seat")
		seat.y = float(ArtKit.spec("building.house").get("wall_height", Client3D.WALL_HEIGHT))
		_check(forge_chimney.position.is_equal_approx(seat) and forge_chimney.get_child_count() == 2
				and hut_chimney.position.is_equal_approx(seat_of.call("building.hut", "chimney")) and hut_chimney.get_child_count() == 1,
				"the house's stack through its chimney_seat, its foot at the eaves (%s), under its smoke, the hut's vent at its chimney socket (%s), its smoke alone (%d, %d)"
				% [forge_chimney.position, hut_chimney.position, forge_chimney.get_child_count(), hut_chimney.get_child_count()])
	if smoke == null:
		return
	var top := smoke.global_position.y - Flames.CHIMNEY_SMOKE.y * 0.45
	_check(top > _rig.global_position.y + Client3D.WALL_HEIGHT + 0.5, "the smoke rises from over the roof (%.2f m)" % (top - _rig.global_position.y))
	_rig.set_awake("smoke_town/square", {"H1": false})
	_check(not smoke.visible, "all asleep inside: no smoke")
	_rig.set_awake("smoke_town/square", {"H1": true})
	_check(smoke.visible, "the smith at work (awake inside): it smokes")
	_rig.set_town("smoke_town/square", {"forge": {"state": Towns.RUIN, "level": 0, "walls": false}})
	_check(not smoke.is_visible_in_tree(), "a ruin: no smoke, its chimney down with its roof")
	_rig.set_town("smoke_town/square", {"forge": {"state": Towns.STANDING, "level": 1}})
	_check(smoke.visible, "standing again, still worked: it smokes")
	_rig.set_awake("smoke_town/square", {"H1": false})
	_check(not smoke.visible, "the forge emptied or asleep: no smoke")
	_rig.set_awake("smoke_town/square", {})
	_rig.town_states.erase("smoke_town/square")
	var said := [Client3D.smoking({"H1": true}, "H1", Towns.DAMAGED, true, 12.0), Client3D.smoking({"H1": true}, "H1", Towns.STANDING, false, 12.0),
		Client3D.smoking({"H1": true}, "H1", Towns.PLANNED, true, 12.0), Client3D.smoking({"H1": true}, "H1", Towns.STANDING, true, 3.0),
		Client3D.smoking({"H1": false}, "H1", Towns.STANDING, true, 12.0)]
	_check(said == [true, false, false, true, false], "damaged still smokes, awake at any hour; being built, planned or asleep: not (%s)" % [said])
	# Nobody known inside (no body has been in): by the hour, as its windows
	# (489 amended (4)): from SMOKE_FROM to LAMP_OUT, so a lit house smokes.
	var by_hour: Array = [5.9, 6.0, 12.0, 21.5, 22.0, 23.0].map(func(hour: float) -> bool: return Client3D.smoking({}, "H1", Towns.STANDING, true, hour))
	var lit_unsmoked: Array = [12.0, 18.0, 21.9].filter(func(hour: float) -> bool:
		return Client3D.lamp_lit({}, "H1", hour, -1.0) and not Client3D.smoking({}, "H1", Towns.STANDING, true, hour))
	_check(by_hour == [false, true, true, true, false, false] and lit_unsmoked.is_empty(),
			"nobody known inside: smoke from 6:00 to LAMP_OUT, never a lit window unsmoked (%s; %s)" % [by_hour, lit_unsmoked])
	# A composed kind's chimney (its composer's) has its smoke too.
	var stamps: Array = []
	for i in 6:
		stamps.append(["building_house_small", Vector2i(2 + (i % 3) * 7, 2 + floori(i / 3.0) * 9), false])
	_rig.rebuild(_kinds_level(stamps)["terrain"], Vector2i(4, 20))
	var chimneys := _rig._buildings.filter(func(b: Dictionary) -> bool: return (b["node"] as Node3D).find_child("Chimney", true, false) != null)
	_check(not chimneys.is_empty() and chimneys.all(func(b: Dictionary) -> bool: return b.get("smoke") != null),
			"every composed chimney has its smoke (%d of %d houses)" % [chimneys.size(), _rig._buildings.size()])


## The healer's turf house (718): a 7 x 5 plot (Level.BANKED), its inside
## the middle 5 x 3 walled square in the sim, its bank's ring and its bed
## and hearth solid, the approach before its door its place; drawn by its
## slot's own walls (Level.ART_WALLED: none of the map's), its quarters on
## the camera's side faded while you are inside, its pot, bed and shelf at
## their sockets, its pot's fire and chimney smoke while someone is awake
## inside, its disrepair and ruin its slot's own looks.
func _test_beds_drawn() -> void:
	print("
== the dwellings' beds drawn (751, buildings' side) ==")
	var cells: Array[Vector2i] = []
	for y in 30:
		for x in 30:
			cells.append(Vector2i(x, y))
	var warnings: Array[String] = []
	var built := Level.buildings_from({"buildings": [{"kind": "house", "at": [5, 5], "facing": [0, 1]}]}, {"floor": cells, "edges": {}, "heights": {}, "water": []}, warnings)
	var house: Dictionary = built[0]
	var node := BuildingComposer.compose(house, BuildingComposer.covered_in(house))
	node.position = Vector3(5, 0.5, 5)
	Client3D.add_beds(node, house, 0.5)
	var beds: Array = house["beds"]
	var wrong: Array[String] = []
	for index in beds.size():
		var piece := node.get_node_or_null("parts/Bed_%d" % index) as Node3D
		var bed: Dictionary = beds[index]
		var middle := (Vector2(bed["cells"][0]) + Vector2(bed["cells"][1])) * 0.5
		if piece == null:
			wrong.append("no Bed_%d" % index)
			continue
		var at := node.transform * piece.transform
		var way: Vector2i = bed["head"]
		var head := -at.basis.z
		if not at.origin.is_equal_approx(Vector3(middle.x, 0.5, middle.y)) or not head.is_equal_approx(Vector3(way.x, 0, way.y)):
			wrong.append("Bed_%d at %s head %s, wanted %s head %s" % [index, at.origin, head, middle, way])
	_check(beds.size() == 3 and wrong.is_empty() and str(beds[0]["prop"]) == "prop.bed",
		"a house's three beds in its parts, each on the middle of its cells at its floor, its head (-z) the bed's way (%s)" % [wrong])
	node.free()
	var hut := {"slot": "building.hut", "rect": Rect2i(2, 2, 3, 3), "facing": Vector2i(0, -1),
		"beds": [{"cells": [Vector2i(2, 4), Vector2i(2, 3)], "head": Vector2i(0, 1), "prop": "prop.bed_straw"}]}
	var slot := Node3D.new()
	slot.position = Vector3(3, 0, 3)
	slot.rotation.y = atan2(0.0, -1.0)
	Client3D.add_beds(slot, hut, 0.0)
	var straw := slot.get_node_or_null("parts/Bed_0") as Node3D
	var placed := slot.transform * straw.transform if straw != null else Transform3D()
	_check(straw != null and placed.origin.is_equal_approx(Vector3(2, 0, 3.5)) and (-placed.basis.z).is_equal_approx(Vector3(0, 0, 1)),
		"a turned slot hut's straw bed: its parts made, the bed where the map has it (%s)" % [placed])
	slot.free()
	_test_bedroll_drawn()


## 751, npc's side (3): a townsman asleep out of doors lies on prop.bedroll; on a bed's head cell, the bed's height.
func _test_bedroll_drawn() -> void:
	print("\n== a townsman asleep out of doors on a bedroll, its head the facing's way; on a bed, its height (751, npc's side (3)) ==")
	var resident := Resident.new()
	resident.name = "BedrollTestResident"
	var puppet := Node3D.new()
	resident.tile = Vector2i(-500, -500)
	resident.facing = Vector2i(1, 0)
	resident.activity = "sleep"
	_rig._sync_bedroll(resident, puppet)
	var roll := puppet.get_node_or_null("Bedroll") as Node3D
	_check(roll != null and roll.position.is_equal_approx(Vector3(-0.5, 0, 0)) and (-roll.basis.z).is_equal_approx(Vector3(1, 0, 0))
		and is_equal_approx(float(puppet.get_meta("bed_height", 0.0)), 0.09),
		"out of doors: the bedroll from its cell one back, its head the facing's way, the body 0.09 up (%s)" % [roll.transform if roll != null else null])
	resident.activity = ""
	_rig._sync_bedroll(resident, puppet)
	_check(puppet.get_node_or_null("Bedroll") == null and float(puppet.get_meta("bed_height", 1.0)) == 0.0, "up: the bedroll gone, the height 0")
	var plots: Array = _rig._terrain.get("plot_buildings", [])
	var had := _rig._terrain.has("plot_buildings")
	var house := {"rect": Rect2i(-600, -600, 3, 3), "beds": [{"cells": [Vector2i(-600, -600), Vector2i(-600, -599)], "head": Vector2i(0, -1), "prop": "prop.bed"}]}
	_rig._terrain["plot_buildings"] = plots + [house]
	resident.tile = Vector2i(-600, -600)
	resident.facing = Vector2i(0, -1)
	resident.activity = "sleep"
	_rig._sync_bedroll(resident, puppet)
	_check(puppet.get_node_or_null("Bedroll") == null and is_equal_approx(float(puppet.get_meta("bed_height", 0.0)), 0.37),
		"on a bed's head cell: no bedroll, the bed's height (%s)" % [puppet.get_meta("bed_height", 0.0)])
	_check(not puppet.has_meta("lie_at"), "(a plain bed: no lie_at)")
	# A furnished (solid) bed (751 amended (4)): the sleeper beside its head, drawn on it, its head on the pillow end.
	var turf_rect := Rect2i(-700, -700, 7, 5)
	var solid_head := Vector2i(-697, -698)
	var turf := {"rect": turf_rect, "slot": "building.turf_house",
		"beds": [{"cells": [solid_head, solid_head + Vector2i(1, 0)], "head": Vector2i(-1, 0), "prop": "prop.bed_straw", "solid": true}]}
	var turf_node := Node3D.new()
	turf_node.position = Vector3(-697.0, 0.25, -698.0)
	var turf_parts := Node3D.new()
	turf_parts.name = "parts"
	turf_node.add_child(turf_parts)
	var straw := Node3D.new()
	straw.name = "Bed"
	straw.position = Vector3(0.5, 0.0, 0.0)
	straw.rotation.y = PI / 2.0  # Its head (-z) to -x, as art_dress turns it.
	turf_parts.add_child(straw)
	_rig._terrain["plot_buildings"] = plots + [turf]
	_rig._buildings.append({"rect": turf_rect, "node": turf_node})
	resident.tile = solid_head + Vector2i(0, 1)
	resident.facing = Vector2i(-1, 0)
	resident.activity = ""
	_rig._sync_bedroll(resident, puppet)
	resident.activity = "sleep"
	_rig._sync_bedroll(resident, puppet)
	var ground := _rig._ground_height(Vector2(resident.tile))
	var pillow: Variant = puppet.get_meta("lie_at", null)
	_check(puppet.get_node_or_null("Bedroll") == null and pillow is Vector2 and (pillow as Vector2).distance_to(Vector2(0.5 - 0.9, -1.0)) < 0.001
		and absf(float(puppet.get_meta("bed_height", 0.0)) - (0.25 + 0.37 - ground)) < 0.001,
		"beside a furnished bed: no bedroll; its pillow end from his cell, its top's height (%s, %s)" % [pillow, puppet.get_meta("bed_height", 0.0)])
	var lay_body := Node3D.new()
	puppet.add_child(lay_body)
	var lay_model := Node3D.new()
	lay_model.name = "Model"
	lay_body.add_child(lay_model)
	puppet.set_meta("work", "sleep")
	puppet.set_meta("faces", 0.0)
	_rig._lay(puppet, lay_body, PI)  # Facing -x.
	_check(lay_body.position.distance_to(Vector3(0.5 - 0.9 + Client3D.SLEEP_HEAD_BACK, float(puppet.get_meta("bed_height")), -1.0 + Client3D.SLEEP_ASIDE)) < 0.001,
		"laid on it: the root SLEEP_HEAD_BACK behind the pillow end, SLEEP_ASIDE aside, at its top (%s)" % [lay_body.position])
	puppet.remove_meta("work")
	resident.activity = ""
	_rig._sync_bedroll(resident, puppet)
	_check(not puppet.has_meta("lie_at"), "up: lie_at gone")
	_rig._buildings.pop_back()
	turf_node.free()
	if had:
		_rig._terrain["plot_buildings"] = plots
	else:
		_rig._terrain.erase("plot_buildings")
	puppet.free()
	resident.free()


func _test_turf_house() -> void:
	print("\n== the healer's turf house: banked plot, art walls, furnishings, its fire and its ruin (718) ==")
	var map := LevelMap.new(Vector2i(16, 12))
	for y in 12:
		for x in 16:
			map.set_cell(Vector2i(x, y), "grass")
	var config := {"outdoor": true}
	var changes := Prefab.stamp_changes(Prefab.load_prefab("building_turf_house"), map, Vector2i(2, 2), config)
	for cell: Vector2i in changes["cells"]:
		map.set_cell(cell, changes["cells"][cell])
	for key: Vector3i in changes["edges"]:
		map.set_edge(key, changes["edges"][key])
	config.merge(changes.get("config", {}), true)
	var level := Level.parse(map.to_image(), null, config)
	var said := (level["warnings"] as Array).filter(func(text: String) -> bool: return text.contains("building"))
	_check(level["buildings"].size() == 1 and said.is_empty(), "the prefab stamps the turf house, nothing said (%s)" % [said])
	if level["buildings"].size() != 1:
		return
	var parsed: Dictionary = level["buildings"][0]
	var inner := Rect2i(4, 4, 5, 3)
	_check(parsed["rect"] == Rect2i(3, 3, 7, 5) and parsed["blocks"] == [inner] and parsed["front"] == Vector2i(6, 7),
			"its footprint the 7 x 5 plot, its inside the middle 5 x 3, its front the approach (%s %s %s)" % [parsed["rect"], parsed["blocks"], parsed["front"]])
	var terrain: Dictionary = level["terrain"]
	var solid: Array = terrain.get("solid", [])
	var furnished: Array[Vector2i] = [Vector2i(8, 5), Vector2i(4, 4), Vector2i(5, 4)]
	var ring := Level.rect_cells(parsed["rect"]).filter(func(cell: Vector2i) -> bool: return not inner.has_point(cell) and cell != Vector2i(6, 7))
	_check(solid.size() == ring.size() + 3 and ring.all(func(cell: Vector2i) -> bool: return cell in solid and not cell in terrain["floor"])
			and furnished.all(func(cell: Vector2i) -> bool: return cell in solid and not cell in terrain["floor"])
			and Vector2i(6, 7) in terrain["floor"] and Vector2i(6, 5) in terrain["floor"],
			"its bank's ring (but the approach) and its hearth and bed solid, out of the floor (%d)" % solid.size())
	var outline := Level.building_outline(parsed)
	var kinds := outline.map(func(key: Vector3i) -> int: return terrain["edges"].get(key, Terrain.Edge.OPEN))
	_check(outline.size() == 16 and kinds.count(Terrain.Edge.DOOR) == 1 and kinds.count(Terrain.Edge.WALL) == 15,
			"the sim walls its inside square, one door (%s)" % [kinds])
	_check(level["places"].has("healers_hut@6,7") and Level.building_cells(parsed).has(Vector2i(6, 5)) and not Level.building_cells(parsed).has(Vector2i(3, 3))
			and not Level.building_cells(parsed).has(Vector2i(6, 7)), "the healer's place on the approach; its inside the block, not the bank")
	_check([Level.land_variant("building.turf_house", "wilds"), Level.land_variant("building.turf_house", "forest"),
			Level.land_variant("building.turf_house", "hills"), Level.land_variant("building.hut", "forest")] == [1, 2, 1, 1],
			"its look by land: the wilds' turf, the forest's logs, else 1")
	parsed["use"] = "hut"
	parsed["town_id"] = "turf_town"
	parsed["code"] = "T1"
	_rig.rebuild(terrain, Vector2i(6, 9))
	var found := _rig._buildings.filter(func(b: Dictionary) -> bool: return b["rect"] == parsed["rect"])
	_check(found.size() == 1, "drawn")
	if found.size() != 1:
		return
	var house: Dictionary = found[0]
	var node: Node3D = house["node"]
	var drawn := outline.filter(func(key: Vector3i) -> bool: return _rig._runs.has(key) or _rig._walls.has(key) or _rig._doorways.has(key))
	_check(drawn.is_empty(), "none of the map's walls or doorway drawn round it: its slot's own walls (%s)" % [drawn])
	_check(_rig._building_at.has(Vector2i(6, 5)) and not _rig._building_at.has(Vector2i(3, 3)) and not _rig._building_at.has(Vector2i(6, 7)),
			"its inside the block (its roof off there), not its bank or approach")
	# The coordinator's find (Hob's hut): a slot building's floor takes only
	# the indoor scatter, as a kind's does (734 amended (2)); grass outside.
	var inside_tufts := 0
	var outside_tufts := 0
	for chunk: Vector2i in _rig._scatter_chunks:
		var plan := _rig._scatter_plan(chunk)
		for kind: String in plan:
			for item: Array in plan[kind]:
				if Client3D.SCATTER_INDOORS.has(kind):
					continue
				if (house["rect"] as Rect2i).has_point(item[0]):
					inside_tufts += 1  # Its block and its bank's ring, inside its walls' art (734 amended (6)).
				else:
					outside_tufts += 1
	_check(inside_tufts == 0 and outside_tufts > 0, "no tufts or flowers on its plot (its floor, its walls' ring), its grass round it (%d on it, %d round it)" % [inside_tufts, outside_tufts])
	var parts := node.get_node_or_null("parts") as Node3D
	var names := ["Hearth", "Bed", "Shelf"].filter(func(name: String) -> bool: return parts != null and parts.get_node_or_null(name) != null)
	_check(names.size() == 3 and is_equal_approx((parts.get_node("Bed") as Node3D).rotation.y, PI / 2.0),
			"its pot, bed (turned head west) and shelf at their sockets (%s)" % [names])
	if names.size() != 3:
		return
	var quarters: Array = house.get("quarters", [])
	_check(quarters.size() == 4 and node.get_node_or_null("roof_damaged") != null and not (node.get_node("roof_damaged") as Node3D).visible
			and not (node.get_node(BuildingComposer.WALLS_RUIN) as Node3D).visible and not (node.get_node(BuildingComposer.RUIN_POT) as Node3D).visible,
			"four quarters; its disrepair roof, ruin walls and tipped pot hidden while it stands")
	var near: Dictionary = _rig._inside_walls([_rig.to_global(Vector3(6, 0.5, 5))], Vector3(0, 0.7, 0.7))
	var faded := quarters.filter(func(q: Array) -> bool: return near.has(q[0])).map(func(q: Array) -> String: return str((q[0] as Node3D).name))
	faded.sort()
	_check(faded == ["wall_se", "wall_sw"], "inside, the camera south: its south quarters faded, the north ones not (%s)" % [faded])
	var far: Dictionary = _rig._inside_walls([_rig.to_global(Vector3(12, 0.5, 9))], Vector3(0, 0.7, 0.7))
	_check(quarters.all(func(q: Array) -> bool: return not far.has(q[0])), "outside it: none faded for being inside")
	var smoke: Node3D = house.get("smoke")
	var hearth: Node3D = house.get("hearth")
	_rig.set_awake("turf_town", {"T1": false})  # Nobody known smokes by the hour (489 amended (4)).
	_check(smoke != null and hearth != null and not smoke.visible and not hearth.visible, "all asleep inside: no smoke, the pot's fire out")
	if smoke == null or hearth == null:
		return
	_rig.set_awake("turf_town", {"T1": true})
	_check(smoke.visible and hearth.visible, "the healer awake inside: the pot's fire lit, the chimney smoking")
	var top := smoke.global_position.y - Flames.CHIMNEY_SMOKE.y * 0.45
	_check(absf(top - _rig.global_position.y - 2.95) < 0.05, "the smoke rises from the chimney socket (%.2f m)" % (top - _rig.global_position.y))
	_rig.set_town("turf_town", {"hut": {"state": Towns.DISREPAIR, "level": 1}})
	_check((node.get_node("roof_damaged") as Node3D).visible and not (node.get_node("roof") as Node3D).visible,
			"in disrepair: its sagged, holed dome in its roof's place")
	_rig.set_town("turf_town", {"hut": {"state": Towns.RUIN, "level": 0, "walls": false}})
	_check(quarters.all(func(q: Array) -> bool: return not (q[0] as Node3D).visible) and (node.get_node(BuildingComposer.WALLS_RUIN) as Node3D).visible
			and (node.get_node(BuildingComposer.RUIN_POT) as Node3D).visible and not parts.visible and not smoke.is_visible_in_tree()
			and not (node.get_node("roof_damaged") as Node3D).visible and not (node.get_node("roof") as Node3D).visible,
			"a ruin: its broken walls for its quarters, its pot tipped over, no roof, bed, shelf or smoke")
	drawn = outline.filter(func(key: Vector3i) -> bool: return _rig._runs.has(key) or _rig._walls.has(key) or _rig._doorways.has(key))
	_check(drawn.is_empty(), "nor any of the map's rubble or stubs drawn round it in ruin (%s)" % [drawn])
	_rig.set_town("turf_town", {"hut": {"state": Towns.STANDING, "level": 1}})
	_check(quarters.all(func(q: Array) -> bool: return (q[0] as Node3D).visible) and not (node.get_node(BuildingComposer.WALLS_RUIN) as Node3D).visible
			and not (node.get_node(BuildingComposer.RUIN_POT) as Node3D).visible and parts.visible and smoke.visible and hearth.visible
			and (node.get_node("roof") as Node3D).visible, "built again: standing, furnished, its fire lit")
	# 733: the hut's own state, told by its place id ("huts"), over its town's.
	var hut := "%s/healers_hut@6,7" % str(terrain.get("level", ""))
	_check(house.get("hut") == hut, "its hut id is its place's, on its front cell (%s)" % [house.get("hut")])
	_rig.set_huts({hut: {"state": Towns.DISREPAIR, "level": 1}})
	_check((node.get_node("roof_damaged") as Node3D).visible and not (node.get_node("roof") as Node3D).visible and smoke.visible,
			"told in disrepair by its place id: its holed roof, its keeper's fire still lit")
	_rig.set_huts({hut: {"state": Towns.RUIN, "level": 0}})
	_check(quarters.all(func(q: Array) -> bool: return not (q[0] as Node3D).visible) and (node.get_node(BuildingComposer.WALLS_RUIN) as Node3D).visible
			and (node.get_node(BuildingComposer.RUIN_POT) as Node3D).visible and not smoke.is_visible_in_tree() and not hearth.visible,
			"told a ruin: its broken walls, its pot tipped and cold, no smoke")
	_rig.set_huts({hut: {"state": Towns.STANDING, "level": 1}})
	_check(quarters.all(func(q: Array) -> bool: return (q[0] as Node3D).visible) and smoke.visible and hearth.visible
			and (node.get_node("roof") as Node3D).visible, "told mended: standing, its fire lit again")
	# 759: its keeper gone in old age, the hut told empty: cold and dark, standing.
	_rig.set_huts({hut: {"state": Towns.STANDING, "level": 1, "empty": true}})
	var window := ["turf_town", "T1", true, hut]
	_check(not smoke.visible and not hearth.visible and quarters.all(func(q: Array) -> bool: return (q[0] as Node3D).visible)
			and not _rig._window_lit(window, 21.0, -0.5), "told empty, the healer still said awake: no smoke, the pot cold, a window dark; it stands")
	_rig.set_huts({hut: {"state": Towns.STANDING, "level": 1}})
	_check(smoke.visible and hearth.visible and _rig._window_lit(window, 21.0, -0.5), "no longer empty: its fire lit and smoking, a window lit")
	_rig.hut_states.clear()
	_rig.set_awake("turf_town", {})
	_rig.town_states.erase("turf_town")
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## Inside (Jeff: "going inside buildings should go into top down view and
## make roofs invisible"; "any space with enclosed walls would count as
## inside, ruins, castle, etc."): a space closed in by walls is inside, told
## by inside_changed and inside_building for ui's camera; the roof over the
## player eases off over ROOF_FADE, then is shadow only; a ruin's stubs still
## enclose, a gone building's plot does not.
func _test_inside() -> void:
	print("\n== inside: a space closed in by walls, its roof eased off (Jeff's top-down view) ==")
	var level := _kinds_level([["building_house_small", Vector2i(2, 2), false]])
	_rig.rebuild(level["terrain"], Vector2i(4, 14))
	var house: Dictionary = _rig._buildings[0]
	house["use"] = "house"
	house["town_id"] = "inside_town"
	var rect: Rect2i = house["rect"]
	var told: Array = []
	var listen := func(inside: bool, bounds: Rect2i) -> void: told.append([inside, bounds])
	_rig.inside_changed.connect(listen)
	var at := func(cell: Vector2i) -> void:
		_rig._update_roofs([_rig.to_global(Vector3(cell.x, 0.5, cell.y))])
	var middle := rect.get_center()
	at.call(Vector2i(20, 20))
	_check(told.is_empty() and _rig.inside_building() == Rect2i(), "out on the grass: not inside (%s)" % [told])
	at.call(middle)
	_check(told.size() == 1 and told[0][0] and (told[0][1] as Rect2i).encloses(Rect2i(middle, Vector2i.ONE))
			and rect.encloses(told[0][1]) and _rig.inside_building() == told[0][1],
			"in the house: inside, the room's bounds %s within its rect %s" % [told.back(), rect])
	var roof: Node3D = house["roof"]
	var meshes: Array = _rig._descendants(roof).filter(func(node: Node) -> bool: return node is GeometryInstance3D)
	_rig._fade_clock += Client3D.ROOF_FADE * 0.5
	at.call(middle)
	var half: float = (meshes[0] as GeometryInstance3D).transparency
	_rig._fade_clock += Client3D.ROOF_FADE
	at.call(middle)
	_check(half > 0.2 and half < 0.9 and (meshes[0] as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,
			"its roof eased off (%.2f half way), then shadow only" % half)
	_rig.set_town("inside_town", {"house": {"state": Towns.RUIN, "level": 0, "walls": false}})
	at.call(middle)
	_check(_rig.inside_building() != Rect2i(), "a ruin: its stubs still enclose, inside (%s)" % [_rig.inside_building()])
	_rig.set_town("inside_town", {"house": {"state": "gone", "level": 0, "walls": false}})
	at.call(middle)
	_check(_rig.inside_building() == Rect2i() and not told.back()[0], "gone: its plot open ground, not inside (%s)" % [told.back()])
	_rig.set_town("inside_town", {"house": {"state": Towns.STANDING, "level": 1}})
	at.call(middle)
	_check(_rig.inside_building() != Rect2i(), "built again: inside")
	# A wall change works out only the spaces beside it: the same as afresh.
	var partly: Dictionary = _rig._enclosed.duplicate()
	var partly_rect: Rect2i = _rig._enclosed_rects[partly[middle]]
	_rig._find_enclosed()
	_check(partly.size() == _rig._enclosed.size() and partly_rect == _rig._enclosed_rects[_rig._enclosed[middle]],
			"the spaces after the wall changes, worked out beside them: as afresh (%d cells, %s)" % [partly.size(), partly_rect])
	at.call(Vector2i(20, 20))
	var gone_from: int = told.size()
	_check(not told.back()[0] and _rig.inside_building() == Rect2i(), "out again: told so (%d tellings)" % gone_from)
	_rig._fade_clock += Client3D.FADE_HOLD + Client3D.ROOF_FADE * 2.0
	at.call(Vector2i(20, 20))
	_rig._fade_clock += Client3D.ROOF_FADE * 2.0
	at.call(Vector2i(20, 20))
	var back: GeometryInstance3D = _rig._descendants(house["roof"]).filter(func(node: Node) -> bool: return node is GeometryInstance3D)[0]
	_check(back.transparency == 0.0 and back.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,
			"its roof back, whole, after FADE_HOLD")
	_rig.inside_changed.disconnect(listen)
	_rig.town_states.erase("inside_town")


## The temple's chapel kit (734), with stand-in slots in art-kit's names:
## its slate laid and cut by the bay, its rose on the front gable and its
## oculus on the back, its belfry on the ridge by the front, buttresses
## and lancets along its long sides, steps at its door; without the art,
## one sheet and stone walls as before.
func _test_chapel() -> void:
	print("\n== the temple's chapel kit: bays, gables, belfry, buttresses (734) ==")
	var slots := ArtKit.slots()
	var edge := {"category": "roofs", "kind": "edge", "size": [0.3, 0.2, 1]}
	var stand_ins := {
		"roof.slate.profile": {"category": "roofs", "type": "profile", "kind": "cell", "size": [1, 0.9, 1],
			"rise": 1.2, "bellcast": 0.15, "bellcast_reach": 0.6, "bay": 1.0},
		"material.wall.chapel": {"category": "materials", "kind": "material", "size": [1, 1, 1]},
		"roof.slate.ridge": edge, "roof.slate.eave": edge, "roof.slate.verge": edge, "roof.slate.end": edge, "roof.slate.hole": edge,
		"wall.chapel.profile": {"category": "walls", "type": "profile", "kind": "edge", "size": [0.5, 4.5, 1], "windows": "between_buttresses"},
		"wall.chapel.buttress_tall": {"category": "walls", "kind": "edge", "size": [0.8, 4.5, 0.6]},
		"gable.chapel.rose": {"category": "walls", "kind": "edge", "size": [0.3, 1.4, 1.4]},
		"gable.chapel.oculus": {"category": "walls", "kind": "edge", "size": [0.3, 0.8, 0.8]},
		"belfry.chapel": {"category": "roofs", "kind": "cell", "size": [1.6, 3.5, 1.6], "sockets": {"bell": [0, 2.96, 0]}},
		"prop.bell": {"category": "props", "kind": "cell", "size": [0.8, 0.8, 0.8]},
		"roof.rafters_broken": {"category": "roofs", "kind": "edge", "size": [4.5, 2.3, 0.2], "variants": 3},
		"roof.ridge_beam": {"category": "roofs", "kind": "edge", "size": [0.16, 0.22, 1.0]},
		"steps.chapel": {"category": "props", "kind": "edge", "size": [1.2, 0.4, 2.4]},
	}
	var level := _kinds_level([["building_temple_small", Vector2i(2, 2), false]])
	var temple: Dictionary = level["buildings"][0]
	# Without the art: art-kit's own chapel and slate slots set aside.
	var kit := {}
	for slot: String in slots.keys():
		if ".chapel" in slot or ".slate" in slot:
			kit[slot] = slots[slot]
			slots.erase(slot)
	BuildingComposer.forget()
	var plain := BuildingComposer.compose(temple, BuildingComposer.covered_in(temple))
	_check(plain.find_child("Slopes", true, false) != null and plain.find_child("Belfry", true, false) == null
			and not BuildingComposer.bayed(plain) and Client3D._known_set("chapel") == "stone",
			"without the chapel's art: one sheet, no belfry, stone walls")
	plain.free()
	slots.merge(kit)
	for slot: String in stand_ins:
		slots[slot] = stand_ins[slot]
	BuildingComposer.forget()
	var node := BuildingComposer.compose(temple, BuildingComposer.covered_in(temple))
	var frame := func(piece: Node) -> Transform3D:
		var out := Transform3D.IDENTITY
		while piece != node:
			out = (piece as Node3D).transform * out
			piece = piece.get_parent()
		return out
	var sheets := node.find_children("Slopes_*", "MeshInstance3D", true, false)
	var holes := node.find_children("Hole_*", "", true, false)
	var ridges := node.find_children("Ridge_*", "", true, false)
	_check(BuildingComposer.bayed(node) and sheets.size() >= 10 and ridges.size() == sheets.size() and holes.size() == sheets.size() * 2
			and holes.all(func(hole: Node3D) -> bool: return not hole.visible),
			"its slate a sheet a bay, a ridge piece each, their holes hidden (%d, %d, %d)" % [sheets.size(), ridges.size(), holes.size()])
	var rose := node.find_child("Rose", true, false)
	var oculus := node.find_child("Oculus", true, false)
	var belfry := node.find_child("Belfry", true, false)
	var middle := (Vector2((temple["rect"] as Rect2i).size) - Vector2.ONE) * 0.5
	_check(rose != null and oculus != null and frame.call(rose).origin.z > middle.y + 4.0 and frame.call(oculus).origin.z < middle.y - 4.0
			and (frame.call(rose).basis.x as Vector3).z > 0.9 and (frame.call(oculus).basis.x as Vector3).z < -0.9,
			"its rose on its front gable, its oculus on its back, each facing out")
	_check(belfry != null and frame.call(belfry).origin.z > middle.y + 2.0 and frame.call(belfry).origin.y > float(temple["eaves"]) + 2.0,
			"its belfry on its ridge, toward its front (%s)" % [frame.call(belfry).origin if belfry != null else null])
	var buttresses := node.get_node("parts").get_children().filter(func(each: Node) -> bool: return each.name.begins_with("Buttress"))
	var lancets := BuildingComposer.windows(temple, {})
	var door_at := Vector2.ZERO
	for key: Vector3i in temple["doors"]:
		door_at += (BuildingComposer._edge_out(temple, key)[0] as Vector2) / (temple["doors"] as Array).size()
	var by_door := buttresses.filter(func(each: Node3D) -> bool: return Vector2(each.position.x, each.position.z).distance_to(door_at) < 2.0)
	_check(buttresses.size() == 6 and lancets.size() == 6 and by_door.is_empty() and node.find_child("Steps", true, false) != null,
			"734 amended (3): three buttresses and three lancets along each long side, a bay of three between, none by the door; steps at its door (%d, %d, %d)"
			% [buttresses.size(), lancets.size(), by_door.size()])
	# Each slope's hole leans off its own slope (734 amended (3)).
	var leaning := holes.filter(func(hole: Node3D) -> bool:
		var side := 1.0 if str(hole.name).ends_with("_1") else -1.0
		return hole.transform.basis.y.x * side > 0.0 and hole.transform.basis.y.y > 0.0)  # In its slopes' frame, x across.
	var bell := node.find_child("Bell", true, false) as Node3D
	var broken := node.find_children("Rafters_broken_*", "", true, false)
	var shown := func() -> Array: return sheets.filter(func(sheet: Node3D) -> bool: return sheet.visible)
	BuildingComposer.show_bays(temple, node, "half")
	var front: Array = shown.call()
	var nearest_bare := INF
	for sheet: Node3D in sheets:
		if not sheet.visible:
			nearest_bare = minf(nearest_bare, frame.call(sheet).origin.z + float(sheet.get_aabb().get_center().z))
	_check(front.size() == ceili(sheets.size() * 0.5) and front.all(func(sheet: Node3D) -> bool:
			return frame.call(sheet).origin.z + sheet.get_aabb().get_center().z > nearest_bare),
			"covering: its front half's slate on, the back bare (%d of %d)" % [front.size(), sheets.size()])
	var cut_of := func() -> Array:
		return sheets.filter(func(sheet: Node3D) -> bool: return not sheet.visible).map(func(sheet: Node3D) -> int: return sheet.get_meta(BuildingComposer.BAY))
	BuildingComposer.show_bays(temple, node, "damaged")
	var damaged: Array = cut_of.call()
	var open_holes := holes.filter(func(hole: Node3D) -> bool: return hole.visible).size()
	var broken_damaged := broken.filter(func(pair: Node3D) -> bool: return pair.visible).size()
	BuildingComposer.show_bays(temple, node, "disrepair")
	var worn: Array = cut_of.call()
	var broken_worn := broken.filter(func(pair: Node3D) -> bool: return pair.visible).size()
	var bell_worn := bell != null and bell.visible
	_check(damaged.size() in [2, 3] and open_holes == damaged.size() * 2 and worn.size() in [5, 6]
			and damaged.all(func(bay: int) -> bool: return bay in worn),
			"damaged: 2-3 bays holed; in disrepair 5-6, the damaged among them (%s, %s)" % [damaged, worn])
	_check(broken.size() == sheets.size() and broken_damaged == 0 and broken_worn == worn.size() and bell != null and not bell_worn,
			"734 amended (3): broken rafters under each bay cut in disrepair only, its bell gone (%d, %d, %d)" % [broken.size(), broken_damaged, broken_worn])
	BuildingComposer.show_bays(temple, node, "whole")
	_check(shown.call().size() == sheets.size() and holes.all(func(hole: Node3D) -> bool: return not hole.visible) and bell.visible, "whole again, its bell hung")
	_check(leaning.size() == holes.size(), "734 amended (3): each hole leans off its own slope (%d of %d)" % [leaning.size(), holes.size()])
	var site := BuildingComposer.site(temple, BuildingComposer.RAFTERS, false)
	var beams := site.find_children("Ridge_beam_*", "", true, false)
	_check(beams.size() == maxi((temple["rect"] as Rect2i).size.y, (temple["rect"] as Rect2i).size.x), "734 amended (3): a ridge beam a metre at its rafters (%d)" % beams.size())
	site.free()
	node.free()
	for slot: String in stand_ins:
		slots.erase(slot)
	BuildingComposer.forget()
	ArtKit.forget()


## The player's house (737): one label, "Your house", over it to every
## viewer, seen only near it.
func _test_home_label() -> void:
	print("\n== the player's house: labelled theirs, seen near (737) ==")
	var level := _kinds_level([["building_house_small", Vector2i(2, 2), false]])
	(level["terrain"]["buildings"][0] as Dictionary)["home"] = true
	_rig.rebuild(level["terrain"], Vector2i(4, 12))
	var labels := _rig._home_labels
	_check(labels.size() == 1 and labels[0].text == Client3D.HOME_WORDS and labels[0].text == "Your house",
			"one label over the house, \"Your house\" (%d)" % labels.size())
	if labels.size() != 1:
		return
	var at := labels[0].global_position
	var near: Array[Vector3] = [Vector3(at.x + 3.0, 0.0, at.z + 4.0)]
	var far: Array[Vector3] = [Vector3(at.x + Client3D.HOME_NEAR + 2.0, 0.0, at.z)]
	_rig._show_home_labels(far)
	var hidden_far := not labels[0].visible
	_rig._show_home_labels(near)
	_check(hidden_far and labels[0].visible and at.y > 4.0, "hidden from afar, shown near, over the roof (%.1f)" % at.y)
	(level["terrain"]["buildings"][0] as Dictionary).erase("home")
	_rig.rebuild(level["terrain"], Vector2i(4, 12))
	_check(_rig._home_labels.is_empty(), "a house not marked the player's: no label")


## Inside is the player's own place, not his companion's (671 amended (3);
## Jeff on v0.1.186: walking into a house did not tip the view): the focus
## points start with his, even when she came into the zone before him.
func _test_inside_is_his() -> void:
	print("
== the first focus point is the player's, whoever spawned first ==")
	var player := _player()
	var pet := EntityFactory.build({"script": "res://sim/companion.gd", "shape": "capsule", "name": "Inside", "props": {"max_hp": 10}}) as Companion
	pet.keeper_peer = Net.local_id
	var free := player.tile + Vector2i(3, 0)
	for cell: Vector2i in [player.tile + Vector2i(3, 0), player.tile + Vector2i(0, 3), player.tile + Vector2i(-3, 0), player.tile + Vector2i(0, -3)]:
		if World.is_walkable(cell) and World.get_entity_at(cell) == null:
			free = cell
			break
	World.spawn(pet, free)
	World._entities.erase(pet)
	World._entities.push_front(pet)  # Hers first, as a client can hear them.
	var points := _rig._focus_points()
	var his := _rig.to_local(points[0])
	_check(Vector2i(roundi(his.x), roundi(his.z)) == player.tile and points.size() == 2 * Client3D.FADE_HEIGHTS.size(),
			"his first (%s at %s, she at %s)" % [Vector2i(roundi(his.x), roundi(his.z)), player.tile, free])
	World.despawn(pet)


## BuildingComposer (decision 489): a wing's walls drawn to its own lower
## eaves; one look made once, its copies sharing their meshes; a round
## hut's one cone; a ruin with no roof, its walls broken here and there.
func _test_composer() -> void:
	print("\n== the composer: a wing's lower walls, one build a look, a round roof, a ruin (decision 489) ==")
	var main_wall: float = _rig._wall_heights.get(Vector3i(1, 4, Terrain.EAST), Client3D.WALL_HEIGHT)
	var wing_wall: float = _rig._wall_heights.get(Vector3i(11, 7, Terrain.EAST), Client3D.WALL_HEIGHT)
	_check(is_equal_approx(main_wall, Client3D.WALL_HEIGHT) and wing_wall < main_wall - 0.2 and wing_wall > main_wall - 0.6,
			"the main block's walls at its eaves (%.2f), the wing's a little lower (%.2f), not whole metres" % [main_wall, wing_wall])
	# A post stands no higher than the walls at it (a wing's corner posts
	# lower, not a storey's poking through its roof).
	var tall_posts: Array[Vector2i] = []
	for vertex: Vector2i in _rig._posts:
		var top := 0.0
		for entry: Array in WallEdge.edges_at_vertex(vertex):
			if _rig._terrain["edges"].get(entry[0], Terrain.Edge.OPEN) != Terrain.Edge.OPEN:
				top = maxf(top, _rig._height_of(entry[0]))
		if _rig._bounds(_rig._posts[vertex]).end.y > top + 0.35:
			tall_posts.append(vertex)
	_check(not _rig._posts.is_empty() and tall_posts.is_empty(), "every post no taller than the walls at it (%s)" % [tall_posts])
	var level := _kinds_level([["building_l_house_small", Vector2i(1, 1), false], ["building_round_hut_small", Vector2i(13, 1), false],
		["building_house_small", Vector2i(1, 12), true]])
	var buildings: Array = level["buildings"]
	BuildingComposer.forget()
	var one := BuildingComposer.compose(buildings[0], "shingle")
	var two := BuildingComposer.compose(buildings[0], "shingle")
	var slopes := func(node: Node3D) -> Mesh: return (node.find_child("Slopes", true, false) as MeshInstance3D).mesh
	_check(one != two and slopes.call(one) == slopes.call(two) and BuildingComposer._made.size() == 1,
			"one look built once: two copies, one mesh between them")
	# Thatch's trims: art-kit's ridge roll and eave fringe, a metre apiece,
	# each eave's fringe out past its slope's low edge; shingle has none.
	var thatch := BuildingComposer.compose(buildings[0], "thatch")
	var trims := thatch.find_children("Trim", "", true, false)
	var fringe_out := true
	for trim: Node3D in trims:
		for piece: Node3D in trim.get_children():
			var local := piece.position
			if absf(local.x) > 0.5:
				fringe_out = fringe_out and piece.transform.basis.x.x * signf(local.x) > 0.5
	var pieces := 0
	for trim: Node in trims:
		pieces += trim.get_child_count()
	_check(one.find_child("Trim", true, false) == null and (not ArtKit.has("roof.thatch.eave") or (pieces > 10 and fringe_out)),
			"thatch roofs trimmed in art-kit's ridge and eave rolls, the eaves' side out (%d); shingle none" % pieces)
	thatch.free()
	one.free()
	two.free()
	_rig.rebuild(level["terrain"], Vector2i(4, 11))
	var round_hut := _rig._buildings.filter(func(each: Dictionary) -> bool: return each["rect"] == Rect2i(14, 2, 7, 5))
	_check(round_hut.size() == 1 and (round_hut[0]["node"] as Node3D).find_child("Cone", true, false) != null,
			"the round hut: one cone over its blocks")
	var house := _rig._buildings.filter(func(each: Dictionary) -> bool: return each["rect"] == Rect2i(2, 2, 10, 8))
	var thatched: MeshInstance3D = (house[0]["roof"] as Node3D).find_child("Slopes", true, false) if house.size() == 1 else null
	_check(thatched != null and thatched.material_override == Client3D._roof_material(Client3D.KIND_ROOF) and Client3D.KIND_ROOF == "shingle",
			"its roofs Jeff's shingle, a kind naming no other set (decision 489 amended)")
	# A porch over the L-house's door (4, 9 south: out is +z), its front out;
	# a cruck on the round hut's... none: a longhouse's far gable instead.
	var porch := BuildingComposer.porch_of(buildings[0])
	_check(porch != null and porch.position.is_equal_approx(Vector3(2.0, 0.0, 7.5)) and is_equal_approx(porch.rotation.y, -PI * 0.5),
			"a porch on its door's edge, its front out of the house (%s, %.2f)" % [porch.position if porch else null, porch.rotation.y if porch else 0.0])
	if porch != null:
		porch.free()
	# Windows: wood walls in a straight stretch, art-kit's window drawn there,
	# its shutters opening outward.
	var windows := BuildingComposer.windows(buildings[0], level["terrain"]["edges"])
	var drawn := windows.filter(func(key: Vector3i) -> bool: return _rig._wall_states.get(key) == "window")
	var outward := true
	for key in drawn:
		var mid := Vector2(key.x + 0.5, key.y) if key.z == Terrain.EAST else Vector2(key.x, key.y + 0.5)
		var piece: Node3D = null
		for child in (_rig._walls[key] as Node3D).get_children() if _rig._walls.has(key) else []:
			if str(child.name).begins_with("Piece_") and Vector2(child.global_position.x, child.global_position.z).distance_to(mid) < 0.1:
				piece = child
		var sides := Terrain.edge_cells(key)
		var out := Vector2(sides[1] - sides[0]) * (1.0 if Level.building_cells(buildings[0]).has(sides[0]) else -1.0)
		var plus_x := (piece.global_transform.basis.x if piece != null else Vector3.ZERO)
		outward = outward and piece != null and Vector2(plus_x.x, plus_x.z).dot(out) > 0.9
	_check(not windows.is_empty() and drawn.size() == windows.size() and outward,
			"the L-house's windows (%d) drawn as art-kit's, their shutters' side out" % windows.size())
	var longhouse: Dictionary = _kinds_level([["building_longhouse_small", Vector2i(1, 1), false]])["buildings"][0]
	var cruck := BuildingComposer.cruck_of(longhouse, false)
	_check(cruck != null and is_equal_approx(absf(cruck.position.x - 5.5), 6.0) and is_equal_approx(cruck.position.z, 2.0),
			"a cruck frame on the longhouse's gable end, outside its 12 cells (%s)" % [cruck.position if cruck else null])
	if cruck != null:
		cruck.free()
	var ruin := _rig._buildings.filter(func(each: Dictionary) -> bool: return each["rect"] == Rect2i(2, 13, 6, 8))
	# Every wall of it down (489 amended, the wilds' farmstead): art-kit's low
	# ruin where the set has it, else a ragged stub or a low bank of rubble,
	# none whole, none a gap (the sim keeps them).
	var ruin_walls := Level.blocks_outline(Level._union([Rect2i(2, 13, 6, 8)])).filter(func(key: Vector3i) -> bool:
			return _rig._terrain["edges"].get(key) == Terrain.Edge.WALL)
	var down := {}
	for key: Vector3i in ruin_walls:
		var state := str(_rig._wall_states.get(key, ""))
		down[state] = int(down.get(state, 0)) + 1
	var low_wood := Client3D._has_art(Client3D.RUIN_LOW % "wood")
	var as_drawn := (down.keys().all(func(state: String) -> bool: return state == "low_ruin") and int(down.get("low_ruin", 0)) == ruin_walls.size()) if low_wood \
			else (down.keys().all(func(state: String) -> bool: return state == "broken" or state == "rubble") and int(down.get("broken", 0)) > 3 and int(down.get("rubble", 0)) > 3)
	_check(ruin.size() == 1 and ruin[0]["roof"] == null and not _rig._building_at.has(Vector2i(4, 16)) and as_drawn,
			"the ruined house: no roof, no inside, every wall %s (%s of %d)" % ["art-kit's low ruin" if low_wood else "a stub or rubble", down, ruin_walls.size()])
	# A stone ruin (827, the wilds' farmhouse) in art-kit's low ruin, its
	# piers at its corners, where the kit has them.
	if not Client3D._has_art(Client3D.RUIN_LOW % "stone"):
		print("  (art-kit's wall.stone.low_ruin is not made here: the stone ruin is not checked)")
		return
	var stone := _kinds_level([["building_cottage_small", Vector2i(2, 2), true]])
	_rig.rebuild(stone["terrain"], Vector2i(4, 12))
	var cottage: Dictionary = _rig._buildings[0] if not _rig._buildings.is_empty() else {}
	var stone_walls: Array = (cottage.get("outline", []) as Array).filter(func(key: Vector3i) -> bool:
			return _rig._terrain["edges"].get(key) == Terrain.Edge.WALL)
	var low := stone_walls.filter(func(key: Vector3i) -> bool: return _rig._wall_states.get(key) == "low_ruin")
	var low_pieces := 0
	var holders := {}
	for key: Vector3i in stone_walls:
		if _rig._walls.has(key):
			holders[_rig._walls[key]] = true
	for holder: Node3D in holders:
		low_pieces += holder.get_children().filter(func(node: Node) -> bool: return str(node.name).begins_with("Piece_")).size()
	var corners := (cottage.get("outline", []) as Array).size() > 0 and _rig._posts.values().any(func(post: Node3D) -> bool:
			return is_instance_valid(post) and post.scale.is_equal_approx(Vector3.ONE))
	_check(not stone_walls.is_empty() and low.size() == stone_walls.size() and low_pieces == stone_walls.size() and corners,
			"a stone ruin in art-kit's low ruin: %d of its %d walls, %d pieces, its piers as made" % [low.size(), stone_walls.size(), low_pieces])


## [param stamps] ([prefab, top-left, ruined]) stamped on grass, parsed.
func _kinds_level(stamps: Array, slope := 0.0) -> Dictionary:
	var map := LevelMap.new(Vector2i(24, 24))
	for y in 24:
		for x in 24:
			map.set_cell(Vector2i(x, y), "grass")
	var config := {"outdoor": true}
	for stamp: Array in stamps:
		var changes := Prefab.stamp_changes(Prefab.load_prefab(stamp[0]), map, stamp[1], config)
		for cell: Vector2i in changes["cells"]:
			map.set_cell(cell, changes["cells"][cell])
		for key: Vector3i in changes["edges"]:
			map.set_edge(key, changes["edges"][key])
		config.merge(changes.get("config", {}), true)
		if stamp[2]:
			(config["buildings"] as Array)[-1]["ruined"] = true
	if slope <= 0.0:
		return Level.parse(map.to_image(), null, config)
	# Ground falling [param slope] metres a row southward, each building on a
	# pad level at its middle row (relief.png, decision 525).
	var size := Vector2i(24, 24)
	var field := PackedFloat32Array()
	field.resize(size.x * size.y)
	for y in size.y:
		for x in size.x:
			field[y * size.x + x] = slope * (size.y - y)
	for building: Dictionary in Level.parse(map.to_image(), null, config)["buildings"]:
		var cells := Level.building_cells(building)
		var middle := 0.0
		for cell in cells:
			middle += cell.y
		var pad := slope * (size.y - roundf(middle / cells.size()))
		for cell in cells:
			field[cell.y * size.x + cell.x] = pad
	return Level.parse(map.to_image(), null, config, Relief.image(field, size))


func _test_double_doors() -> void:
	print("
== a building's doorway two edges wide is one door.double, each leaf its own edge's Door (decision 403) ==")
	_rig.rebuild(_kit_level()["terrain"], Vector2i(7, 6))
	var entrance := Level.outline(Rect2i(2, 2, 4, 6)).filter(func(key: Vector3i) -> bool: return _rig._doorways.has(key))
	_check(entrance.size() == 2 and _rig._doorways[entrance[0]] == _rig._doorways[entrance[1]]
			and _rig._doorways[entrance[0]].get_node("Door").has_node("leaf_b"),
			"the temple's two door edges %s: one doorway, a door.double" % [entrance])
	var hut := Level.outline(Rect2i(10, 2, 3, 3)).filter(func(key: Vector3i) -> bool: return _rig._doorways.has(key))
	_check(hut.size() == 1 and _rig._doorways[hut[0]].has_node(Client3D.DOOR_LEAF), "the hut's one door edge: a door.single")
	if entrance.size() != 2:
		return
	var doorway: Node3D = _rig._doorways[entrance[0]]
	var leaves := entrance.map(func(key: Vector3i) -> Node3D: return _rig._door_hinges[key][0])
	var picks := doorway.get_children().filter(func(node: Node) -> bool: return node is Area3D)
	var centre := doorway.global_position
	_check(leaves[0] != leaves[1] and picks.size() == 2
			and entrance.all(func(key: Vector3i) -> bool:
				var leaf: Node3D = _rig._door_hinges[key][0]
				var middle := Client3D._edge_midpoint(key)
				# Each edge's leaf hinged at that edge's end of the doorway.
				return (leaf.global_position - centre).dot(middle - Vector3(centre.x, 0.0, centre.z)) > 0.0),
			"a leaf for each edge, on that edge's half, and a pick each (%d)" % picks.size())
	# Each leaf follows its own Door: one open, the other locked, then broken.
	var doors: Array[Door] = []
	for key in entrance:
		var door := Door.new()
		door.key = key
		World._doors[key] = door
		doors.append(door)
	var locked := Node3D.new()
	locked.name = "state_locked"
	(leaves[1] as Node3D).add_child(locked)
	var settle := func() -> void:
		for key in entrance:
			_rig._doors_due[key] = true
			_rig._door_states.erase(key)
		await _settle_doors()
	doors[0].open = true
	doors[1].lock = "test key"
	await settle.call()
	_check(is_equal_approx(leaves[0].rotation.y, _rig._door_hinges[entrance[0]][1]) and is_zero_approx(leaves[1].rotation.y)
			and locked.visible and leaves[0].visible and leaves[1].visible,
			"one open, swung (%.2f); the other locked, shut, its lock showing (%.2f)" % [leaves[0].rotation.y, leaves[1].rotation.y])
	doors[1].lock = ""
	doors[1].hp = 0
	await settle.call()
	_check(leaves[0].visible and not leaves[1].visible and not locked.visible and is_equal_approx(leaves[0].rotation.y, _rig._door_hinges[entrance[0]][1]),
			"the other broken: its leaf gone, the open one still open")
	doors[0].open = false
	doors[1].hp = doors[1].max_hp
	await settle.call()
	_check(is_zero_approx(leaves[0].rotation.y) and is_zero_approx(leaves[1].rotation.y) and leaves[1].visible,
			"both shut and whole: both leaves home")
	for door in doors:
		World._doors.erase(door.key)
		door.free()
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


func _test_building_states() -> void:
	print("
== a building drawn as its town has it: damaged, its roof caved in; standing again, as built ==")
	var terrain := _building_terrain()
	var record: Dictionary = (terrain["buildings"] as Array).filter(func(b: Dictionary) -> bool: return b["slot"] == "building.house")[0]
	record["use"] = "forge"
	record["town_id"] = "fixture/square"
	_rig.rebuild(terrain, Vector2i(7, 7))
	_main._client3d = _rig
	var house: Dictionary = _rig._buildings.filter(func(b: Dictionary) -> bool: return b["use"] == "forge")[0]
	var roof: Node3D = house["roof"]
	_check(not house["damaged"] and roof.transform.is_equal_approx(house["roof_at"]), "no word from the town: standing, as built")
	# A client told by the server ("town"), through Main as the message comes.
	_main._on_message("town", {"town": "fixture/square", "buildings": {"forge": {"state": Towns.DAMAGED, "level": 1}}})
	_check(_main.town_states.has("fixture/square") and house["damaged"], "told the forge is damaged: it is drawn so")
	var caved: bool = house["roof"] != roof or not roof.transform.is_equal_approx(house["roof_at"])
	var heaps := (house["node"] as Node3D).find_child("state_damaged", true, false) as Node3D
	var broken := Level.outline(house["rect"]).filter(func(key: Vector3i) -> bool: return _rig._wall_states.get(key) == "broken")
	_check(broken.size() > 0 and broken.size() < Level.outline(house["rect"]).size() / 2, "a third or so of its walls broken (%d of %d)" % [broken.size(), Level.outline(house["rect"]).size()])
	_check(caved and house["roof"] != roof and (house["roof"] as Node3D).name == "roof_damaged" and (house["roof"] as Node3D).visible
			and not roof.visible and heaps != null and heaps.visible, "its roof_damaged in its roof's place, its rubble shown (art-kit's slot)")
	# Inside, the damaged roof goes as the whole one did.
	_rig.set_process(false)
	var puppet: Node3D = _rig._puppets[_player().get_instance_id()]
	var was := puppet.global_position
	puppet.global_position = _rig.to_global(_rig._tile_position(Vector2i(4, 6)))
	_rig._update_fade()
	# Its roof eases off over ROOF_FADE.
	_rig._fade_clock += Client3D.ROOF_FADE
	_rig._update_fade()
	_check(house["off"] and _roof_shadow_only(house), "inside a damaged building: its roof draws only its shadow")
	puppet.global_position = was
	_rig._fade_clock += Client3D.FADE_HOLD + 0.1
	_rig._update_fade()
	_rig.set_process(true)
	_main._on_message("town", {"town": "fixture/square", "buildings": {"forge": {"state": Towns.STANDING, "level": 1}}})
	_check(not house["damaged"] and house["roof"] == roof and roof.visible and roof.transform.is_equal_approx(house["roof_at"]) and not heaps.visible,
			"repaired: standing again, its roof whole, its rubble gone")
	_check(Level.outline(house["rect"]).all(func(key: Vector3i) -> bool: return _rig._wall_states.get(key, "") == ("window" if _rig._window_code.has(key) else "")),
			"and its walls whole, its windows windows again (489 amended (3))")
	_rig.rebuild(terrain, Vector2i(7, 7))
	_check(_rig._buildings.any(func(b: Dictionary) -> bool: return b["use"] == "forge" and not b["damaged"]), "kept across a rebuild (as the town has it)")
	_main._on_message("town", {"town": "fixture/square", "buildings": {"forge": {"state": Towns.DAMAGED, "level": 1}}})
	_rig.rebuild(terrain, Vector2i(7, 7))
	_check(_rig._buildings.any(func(b: Dictionary) -> bool: return b["use"] == "forge" and b["damaged"]), "a damaged building is still damaged after a rebuild")
	# On the server, a change in the town's records reaches its own view too.
	World.towns.building_changed.emit("fixture/other", "inn")
	_check(_main.town_states.has("fixture/other") and _rig.town_states.has("fixture/other"), "the server's Towns.building_changed is told to every peer and its own view")
	_main.town_states.clear()
	_rig.town_states.clear()
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


func _test_town_walls() -> void:
	print("
== a town wall drawn as its town's walls level: rubble, palisade, stone, towers; damaged, broken in places ==")
	var map := LevelMap.new(Vector2i(20, 16))
	for y in 16:
		for x in 20:
			map.set_cell(Vector2i(x, y), "grass")
	var rect := Rect2i(4, 3, 10, 8)
	var gate := Vector3i(8, 10, Terrain.SOUTH)
	for key in Level.outline(rect):
		map.set_edge(key, "door" if key == gate else "wall")
	var config := {"outdoor": true, "places": {"square": {"at": [8, 6], "kind": "stockpile"}}, "town_walls": [{"town": "square", "rect": [4, 3, 10, 8]}]}
	var terrain: Dictionary = Level.parse(map.to_image(), null, config)["terrain"]
	(terrain["town_walls"] as Array)[0]["town_id"] = "fixture/square"
	_rig.rebuild(terrain, Vector2i(8, 6))
	var ring: Dictionary = _rig._town_walls[0] if not _rig._town_walls.is_empty() else {}
	_check(not ring.is_empty() and ring["walls"].size() == Level.outline(rect).size() - 1 and ring["gates"] == [gate], "the ring drawn, its gate a door")
	if ring.is_empty():
		_rig.rebuild(_main._terrain, Vector2i.ZERO)
		return
	var walls: Array = ring["walls"]
	var all_are := func(state: String) -> bool: return walls.all(func(key: Vector3i) -> bool: return _rig._wall_states.get(key, "") == state)
	var all_set := func(set_name: String) -> bool: return walls.all(func(key: Vector3i) -> bool: return _rig._wall_sets.get(key, "") == set_name)
	_check(all_are.call("rubble") and _rig._walls.has(walls[0]), "no walls record (level 0): a bank of rubble all round, the walls still standing in the sim and drawn")
	_rig.set_town("fixture/square", {"walls": {"state": Towns.STANDING, "level": 1}})
	_check(all_are.call("") and all_set.call("wood"), "level 1: a palisade")
	_rig.set_town("fixture/square", {"walls": {"state": Towns.STANDING, "level": 2}})
	_check(all_are.call("") and all_set.call("stone") and ring["towers"].is_empty(), "level 2: stone, no towers")
	_rig.set_town("fixture/square", {"walls": {"state": Towns.STANDING, "level": 3}})
	var towers: Dictionary = ring["towers"]
	_check(towers.size() == 6 and towers.has(rect.position) and towers.has(rect.end) and towers.has(WallEdge.vertex_at(gate, 0))
			and towers.values().all(func(t: Node3D) -> bool: return t.visible), "level 3: towers at its four corners and either side of its gate (%d)" % towers.size())
	_rig.set_town("fixture/square", {"walls": {"state": Towns.DAMAGED, "level": 3}})
	var broken := walls.filter(func(key: Vector3i) -> bool: return _rig._wall_states.get(key, "") == "broken")
	_check(broken.size() > 0 and broken.size() < walls.size() / 2 and all_set.call("stone"), "damaged: a third or so of it broken, still stone (%d of %d)" % [broken.size(), walls.size()])
	_rig.set_town("fixture/square", {"walls": {"state": Towns.PLANNED, "level": 0}})
	_check(all_are.call("rubble") and all_set.call("") and towers.values().all(func(t: Node3D) -> bool: return not t.visible), "planned only: rubble again, no towers")
	_rig.rebuild(_main._terrain, Vector2i.ZERO)
	_check(_rig._town_walls.is_empty() and walls.all(func(key: Vector3i) -> bool: return not _rig._wall_states.has(key) and not _rig._wall_sets.has(key)),
			"another map: its ring's looks taken out")
	_rig.town_states.clear()


func _test_water() -> void:
	print("\n== water: a surface a body over a bed the ground sinks into, drawn under the marks ==")
	# The sample's pool and stream, cell water (the castle's ponds are curves
	# since 568 amended: CELL_WATER_FIXTURES in level_test).
	var castle := Level.load_level("sample")
	var terrain: Dictionary = castle["terrain"]
	_rig.rebuild(terrain, castle["centre"])
	var water: Array = terrain["water"]
	# Bodies by hand: cells joined side to side, a stream's cells left to its
	# ribbon (557).
	var left: Dictionary = {}
	for cell: Vector2i in water:
		if not _rig._stream_cells.has(cell):
			left[cell] = true
	var bodies := 0
	while not left.is_empty():
		bodies += 1
		var open: Array = [left.keys()[0]]
		while not open.is_empty():
			var cell: Vector2i = open.pop_back()
			if left.erase(cell):
				for side: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					open.append(cell + side)
	_check(bodies > 0 and _rig._water_bodies.size() == bodies
			and _rig._room.find_children("WaterBed_*", "", false, false).is_empty(),
			"one water surface a body (%d), no quads a cell" % bodies)
	var material := _rig._water_bodies[0].material_override as ShaderMaterial
	_check(material.shader == Client3D.WATER_SHADER and material.render_priority < 0,
			"drawn by the water shader, before the hover outline, ripples and builder's ghost")
	var all_in := water.all(func(cell: Vector2i) -> bool: return _rig._grounds.has(cell))
	var sunk := 0
	for point: Vector3 in _rig._ground_meshes.map(func(mesh: ArrayMesh) -> Array: return Array(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])).reduce(func(a: Array, b: Array) -> Array: return a + b, []):
		if point.y < -0.1:
			sunk += 1
	_check(all_in and sunk > 0, "the ground runs on under the water as its bed, sunk where water is all round (%d corners)" % sunk)
	# Dry water (a well's): drawn as the land beside it, no surface, no bed.
	for cell: Vector2i in water:
		_rig._dry_water[cell] = true
	_rig.rebuild(terrain, castle["centre"])
	var dry_sunk := 0
	for mesh: ArrayMesh in _rig._ground_meshes:
		for point: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			dry_sunk += 1 if point.y < -0.1 else 0
	var as_land := water.all(func(cell: Vector2i) -> bool:
		return _rig._grounds.has(cell) and _rig._grounds[cell] < _rig._ground_floor_end)
	_check(_rig._water_bodies.is_empty() and dry_sunk == 0 and as_land and terrain["water"].size() == water.size(),
			"dry water: no surface, no sunk bed, drawn as the land; the map still has it as water")
	_rig._dry_water.clear()
	_rig.rebuild(terrain, castle["centre"])
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## Fire drawn (decision 523): the castle's torches and fire cells with their
## flames (a torch's on its post or its slot's socket, two or three on a fire
## cell, each with its smoke), flames sized by slot, the drawn lights
## flickering within their swing and the same for the same time, faded by
## day outdoors only, and World's light untouched by it.
func _test_fire() -> void:
	print("
== fire: flames on torches and fire cells, the drawn light flickering, World's light steady ==")
	var castle := Level.load_level("castle")
	var terrain: Dictionary = castle["terrain"]
	var torches: Array = terrain.get("torches", [])
	var fire: Array = terrain.get("fire", [])
	_check(not torches.is_empty() and not fire.is_empty(), "the castle has torches and fire (%d, %d)" % [torches.size(), fire.size()])
	if torches.is_empty() or fire.is_empty():
		return
	_rig.rebuild(terrain, castle["centre"])
	var lit := torches.all(func(cell: Vector2i) -> bool:
		var post := _rig._room.get_node_or_null("Torch_%d_%d" % [cell.x, cell.y]) as Node3D
		var flame := post.get_node_or_null("Flame") as Node3D if post != null else null
		return flame != null and flame.get_node_or_null("Body") != null and flame.get_node_or_null("Smoke") != null 				and flame.position.y > 1.0)
	var burning := fire.filter(func(cell: Vector2i) -> bool: return _rig._grounds.has(cell)).all(func(cell: Vector2i) -> bool:
		var patch := _rig._room.get_node_or_null("Fire_%d_%d" % [cell.x, cell.y]) as Node3D
		var flames := patch.find_children("Flame*", "Node3D", false, false).size() if patch != null else 0
		return flames >= Client3D.FIRE_FLAMES.x and flames <= Client3D.FIRE_FLAMES.y)
	_check(lit and burning, "a flame on each torch's top, two or three on each fire cell, each with its smoke")
	_check(Flames.size_of("prop.campfire") > Flames.size_of("prop.forge") and Flames.size_of("prop.forge") > Flames.size_of("prop.torch")
			and Flames.socket_of("prop.campfire") == Vector3(0.0, 0.2, 0.0) and Flames.socket_of("prop.barrel") == null,
			"flames sized by slot, at its flame socket; none for a slot without one")
	var swung := 0.0
	var steady := true
	for i in 300:
		var share := Flames.flicker(i * 0.0333, 1.3, Flames.TORCH_FLICKER)
		swung = maxf(swung, absf(share - 1.0))
		steady = steady and Flames.flicker(i * 0.0333, 1.3, Flames.TORCH_FLICKER) == share
	_check(swung > Flames.TORCH_FLICKER * 0.5 and swung <= Flames.TORCH_FLICKER + 0.0001 and steady,
			"the drawn light flickers within its swing, the same for the same time (%.3f of %.2f)" % [swung, Flames.TORCH_FLICKER])
	_check(is_equal_approx(Flames.day_share(1.0, true, 0.0), Flames.DAY_SHARE) and Flames.day_share(0.0, true, 0.0) == 1.0
			and Flames.day_share(1.0, false, 0.0) == 1.0 and Flames.day_share(1.0, true, 1.0) == 1.0,
			"by day outdoors faded to %.1f, full at night, indoors and under a full canopy" % Flames.DAY_SHARE)
	var cell: Vector2i = torches[0]
	var before := World.light_at(cell)
	var energies: Array[float] = []
	for i in 5:
		_rig._flicker_fires(0.05)
		energies.append((_rig._fire_lights[0][0] as OmniLight3D).light_energy)
	# Outdoors, one pool more for each cluster of fire cells (782).
	var drawn: Array[Vector2i] = []
	for each: Vector2i in fire:
		if _rig._grounds.has(each):
			drawn.append(each)
	var pools := Client3D.fire_clusters(drawn).size() if bool(terrain.get("outdoor", false)) else 0
	_check(_rig._fire_lights.size() == torches.size() + drawn.size() + pools
			and _rig._room.find_children("FirePool*", "OmniLight3D", false, false).size() == pools
			and energies.max() != energies.min() and World.light_at(cell) == before,
			"each fire's drawn light flickers, a pool over each cluster outdoors (%d); World's light stays as it was (%s)" % [pools, energies])
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## The dark tower's cold lamps (659 amended): the sample tower's top floor
## drawn, each lamp_cold marker art-kit's prop.dark_lamp (or its stand-in
## post) with no fire on it, its light the cold colour at the slot's flame
## socket, no shadows, breathing slowly between LAMP_PULSE_LOW and full
## (never a fire's flicker); and the sim counting it as light, no heat.
func _test_cold_lamp() -> void:
	print("
== the cold lamps: the dark tower's lights, drawn and in the sim ==")
	var made := preload("res://tools/plan_sheet.gd").sample_tower(4, 4, "vt_tower")
	var level := Level.parse(made["layout"], null, made["config"])
	var terrain: Dictionary = level["terrain"]
	var lamps: Array = terrain.get("lamps", [])
	_check(lamps.size() == 2 and terrain["torches"].is_empty(), "the top chamber's two lamps parsed, no torch (%s)" % [lamps])
	if lamps.is_empty():
		return
	_rig.rebuild(terrain, Vector2i(11, 11))
	var drawn := true
	for cell: Vector2i in lamps:
		var post := _rig._room.get_node_or_null("Lamp_%d_%d" % [cell.x, cell.y]) as Node3D
		var light := _rig._room.get_node_or_null("LampLight_%d_%d" % [cell.x, cell.y]) as OmniLight3D
		drawn = drawn and post != null and post.find_children("Flame*", "", true, false).is_empty() and light != null
		drawn = drawn and light.light_color == Client3D.LAMP_COLD and not light.shadow_enabled and light.omni_range == Client3D.LAMP_RANGE and light.position.y > 1.0
	_check(drawn and _rig._lamp_lights.size() == 2, "each lamp stands with no flame, its light cold, unshadowed, at its heart")
	var low := INF
	var high := -INF
	for i in 160:
		_rig._flicker_fires(0.05)
		var energy := (_rig._lamp_lights[0][0] as OmniLight3D).light_energy
		low = minf(low, energy)
		high = maxf(high, energy)
	_check(low >= Client3D.LAMP_ENERGY * Client3D.LAMP_PULSE_LOW - 0.001 and high <= Client3D.LAMP_ENERGY + 0.001 and high - low > 0.05,
		"the lamp breathes slowly, between %.2f and %.2f over its %d s (%.3f .. %.3f)" % [Client3D.LAMP_PULSE_LOW, 1.0, int(Client3D.LAMP_PERIOD), low, high])
	var fields := Fields.new()
	fields.load(terrain)
	var sources: Array = fields._sources().filter(func(source: Array) -> bool: return source[1] == Fields.LAMP)
	_check(sources.size() == 2 and float(Fields.LAMP["heat"]) == 0.0 and float(Fields.LAMP["light"]) > 0.0,
		"the sim counts each lamp as light, no heat (%d sources)" % sources.size())
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## Seeing the player through ground that hides them (decision 549): on
## levels/hills, at the foot of the plateau's face with the camera on the
## plateau's side the player is hidden (any pitch the camera has), on the
## valley floor not; the cut-out eases in over SIGHT_EASE and back out, its
## globals set; the castle (no relief) never hides.
func _test_sight() -> void:
	print("
== sight: the ground thinned where it hides the player, as a wall fades ==")
	var hills := Level.load_level("hills")
	_rig.rebuild(hills["terrain"], hills["centre"])
	var had_yaw := _rig.yaw
	_rig.yaw = 45.0  # The camera east of its aim: the plateau's side.
	# 756: the plateau's face at column 168; open ground by the west link.
	var foot := Vector2i(167, 44)
	var at := Vector3(foot.x, _rig._ground_height(Vector2(foot)), foot.y)
	var valley := Vector3(24.0, _rig._ground_height(Vector2(24.0, 112.0)), 112.0)
	var under := _rig.hidden_by_ground(at, Client3D.CAMERA_PITCH)
	var lifted := _rig.hidden_by_ground(at, Client3D.RIDGE_PITCH_MAX)
	var open := _rig.hidden_by_ground(valley, Client3D.CAMERA_PITCH)
	_check(under and not open,
			"under the plateau's face, its top between the player and the camera: hidden; on the valley floor, not (%s, lifted %s, %s)" % [under, lifted, open])
	_rig._sight_cut = 0.0
	for i in 3:
		_rig._update_sight(at, Client3D.SIGHT_EASE / 2.0)
	var cut := _rig._sight_cut
	var toward := _rig._camera_offset().normalized()
	for i in 3:
		_rig._update_sight(valley, Client3D.SIGHT_EASE / 2.0)
	# (Headless, global shader uniforms read back nil: the eased strength.)
	_check(is_equal_approx(cut, 1.0) and toward.y > 0.5 and toward.x > 0.3 and is_equal_approx(_rig._sight_cut, 0.0),
			"the cut-out eases in while hidden and out again, toward the camera (%.2f, %s)" % [cut, toward])
	# Its shaders only while it is in (549 amended): the everyday ground and
	# scatter carry no discard.
	_rig._sight_cut = 0.0
	_rig._update_sight(at, Client3D.SIGHT_EASE / 2.0)
	var in_shader := _rig._ground_look.shader
	for i in 3:
		_rig._update_sight(valley, Client3D.SIGHT_EASE / 2.0)
	var everyday := FileAccess.get_file_as_string("res://client3d/ground.gdshader") + FileAccess.get_file_as_string("res://client3d/scatter.gdshader")
	_check(in_shader == Client3D.GROUND_SIGHT_SHADER and _rig._ground_look.shader == Client3D.GROUND_SHADER
			and _rig._ground_look.get_shader_parameter("slope_shade") == Client3D.SLOPE_SHADE and not everyday.contains("SIGHT"),
			"the cut-out's shaders swapped in only while it is in, the ground's parameters kept")
	var castle := Level.load_level("castle")
	_rig.rebuild(castle["terrain"], castle["centre"])
	_check(not _rig.hidden_by_ground(Vector3(10.0, 0.0, 10.0), Client3D.CAMERA_PITCH), "the castle (no relief) never hides the player behind ground")
	_rig.yaw = had_yaw
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## The ground drawn from the relief (decision 525, terrain's side): levels/
## sample's corners are Relief.corner_heights' (the sim's own derivation),
## a point's height the triangle drawn there, each water body flat, the
## camera lifted over a ridge and not on the flat; the castle (no relief.png)
## drawn exactly as its whole levels.
func _test_relief() -> void:
	print("\n== relief: the ground drawn from the field, water level, the camera over a ridge ==")
	var sample := Level.load_level("sample")
	var terrain: Dictionary = sample["terrain"]
	_check(terrain.get("relief_given", false), "the sample gives its ground in relief.png")
	_rig.rebuild(terrain, sample["centre"])
	var field: PackedFloat32Array = terrain["relief"]
	var size: Vector2i = terrain["relief_size"]
	var differ := []
	for cell: Vector2i in _rig._corners:
		if _rig._bed_levels.has(cell) or _rig._ramp_heights.has(cell) or _rig._wet.has(cell) or not Relief.on_map(size, cell):
			continue
		var bank := false
		for corner: Vector2i in Client3D.GROUND_CORNERS:
			bank = bank or _rig._water_corner(cell + corner) < INF
		if bank:
			continue  # A bank comes down to the water's edge (decision 525).
		if _rig._corners[cell] != Relief.corner_heights(field, size, cell):
			differ.append(cell)
	_check(not _rig._corners.is_empty() and differ.is_empty(),
			"each cell's corners are the sim's (Relief.corner_heights), off a ramp, a bank or the water (%d differ: %s)" % [differ.size(), differ.slice(0, 4)])
	# A point's height: the triangle drawn there, its corners exactly at
	# the corners; a sloped cell's middle between its lowest and highest.
	var sloped := Vector2i(13, 14)
	var h := _rig._corner_heights(sloped)
	var corners_met := true
	for c in 4:
		var corner := sloped + Client3D.GROUND_CORNERS[c]
		var drawn := Vector3(corner.x - 0.5, h[c], corner.y - 0.5)
		corners_met = corners_met and absf(_rig._height_in(sloped, Vector2(drawn.x, drawn.z)) - drawn.y) < 0.0001
	var middle := _rig._tile_position(sloped).y
	_check(corners_met and Array(h).max() - Array(h).min() > 0.1 and middle > Array(h).min() and middle < Array(h).max(),
			"on a slope a thing stands on the ground drawn there (%s, middle %.2f)" % [h, middle])
	var level := true
	for body: MeshInstance3D in _rig._water_bodies:
		var ys: Dictionary = {}
		for point: Vector3 in (body.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			ys[snappedf(point.y, 0.001)] = true
		level = level and ys.size() == 1
	_check(not _rig._water_bodies.is_empty() and level, "the sample's water (one surface) lies level (%d bodies)" % _rig._water_bodies.size())
	# On hills the stream steps down its valley: its surface slopes with it,
	# each corner its water cells' mean, and its bed lies under it where the
	# shore field has it in the water (decision 553: a winding stream leaves
	# a water cell's corner dry bank).
	var hills := Level.load_level("hills")
	_rig.rebuild(hills["terrain"], hills["centre"])
	# Its water a ribbon along its curve (557; 559, terrain's side): each
	# middle point on the river's surface there (_curve_surface), never
	# rising down the stream, over its bed all along.
	var off_surface := 0
	var heights_seen: Dictionary = {}
	var rising := 0
	var under_bed := 0
	var stream_path: Array = hills["terrain"]["streams"][0]["path"]
	var middles: PackedVector3Array = (_rig._stream_ribbons[0].mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] \
			if not _rig._stream_ribbons.is_empty() else PackedVector3Array()
	for k in range(1, middles.size(), 3):
		var point := middles[k]
		heights_seen[snappedf(point.y, 0.01)] = true
		if k >= 4 and point.y > middles[k - 3].y + 0.001:
			rising += 1
		var spot := Vector2(point.x, point.z)
		# Over the bed's mesh (_height_in): _ground_height is where a body
		# stands, a bridge's deck over the stream (505 amended (5)).
		if point.y < _rig._height_in(Vector2i(spot.round()), spot) - 0.001:
			under_bed += 1
	for k in range(1, middles.size(), 3):
		var spot := Vector2(middles[k].x, middles[k].z)
		off_surface += 0 if absf(middles[k].y - _rig._curve_surface(spot) - Client3D.WATER_LIFT) < 0.002 else 1
	var covered := _ribbon_report(_rig, Vector2.ZERO)
	off_surface += rising + under_bed + covered["uncovered"].size()
	var dry_bed := []
	for cell: Vector2i in _rig._wet:
		var bed := _rig._corner_heights(cell)
		for c in 4:
			var corner := cell + Client3D.GROUND_CORNERS[c]
			var at := Vector2(corner) - Vector2(0.5, 0.5)
			var surface := _rig._curve_surface(at) if _rig._curve_cells.has(cell) else _rig._water_corner(corner)
			# A lip's corner on a tall fall's line stands over the foot's
			# water: the face between them, not a dry bed (570).
			if _rig.shore_at(at) > 0.6 and bed[c] >= surface and bed[c] - surface < Client3D.FALL_TALL:
				dry_bed.append(cell)
				break
	_check(off_surface == 0 and heights_seen.size() > 3 and dry_bed.is_empty(),
			"a stream's ribbon slopes down its valley, on its curve's surface, never rising, over its bed, over all its cells (%d heights; off: %d, rising %d, under its bed %d, uncovered %s; beds above: %s)" % [heights_seen.size(), off_surface, rising, under_bed, covered["uncovered"].slice(0, 3), dry_bed.slice(0, 4)])
	# No fall past its bridge (557 amended (2)): the level writes the deck's
	# height into the relief under a bridge, and the water there is read at
	# its bed, so the deck is no step.
	var by_bridge := _rig.stream_falls.filter(func(fall: Dictionary) -> bool:
		return (hills["terrain"].get("bridged", []) as Array).any(func(cell: Vector2i) -> bool: return (cell - (fall["cell"] as Vector2i)).length() < 2.0))
	_check(by_bridge.is_empty(), "no fall past the hills' bridge, its deck no step (%s)" % [by_bridge])
	# Its falls (decision 557, for sound's ambience): each a step down its
	# path of more than FALL_LEAST, the cell below it; a new array a build.
	# The hills have no real step, so one is made: the land past the
	# stream's middle (away from its bridge) lowered FALL_STEP.
	const FALL_STEP := 0.6
	var stepped: Dictionary = hills["terrain"].duplicate(true)
	var step_index := stream_path.size() / 2
	# Where it heads down its valley (756: a loop running across it would
	# cross the lowered land's edge again and again).
	var down := Vector2((stream_path[-1] as Vector2i) - (stream_path[0] as Vector2i)).normalized()
	while step_index > 1 and ((stepped.get("bridged", []) as Array).any(func(cell: Vector2i) -> bool: return (cell - (stream_path[step_index] as Vector2i)).length() < 4.0)
			or Vector2((stream_path[step_index] as Vector2i) - (stream_path[step_index - 1] as Vector2i)).dot(down) < 0.9):
		step_index -= 1
	var step_at: Vector2i = stream_path[step_index]
	var way: Vector2i = step_at - (stream_path[step_index - 1] as Vector2i)
	var relief: PackedFloat32Array = stepped["relief"]
	var relief_size: Vector2i = stepped["relief_size"]
	for y in relief_size.y:
		for x in relief_size.x:
			if Vector2(Vector2i(x, y) - step_at).dot(Vector2(way)) >= 0.0:
				relief[y * relief_size.x + x] -= FALL_STEP
	stepped["relief"] = relief
	_rig.rebuild(stepped, hills["centre"])
	var falls := _rig.stream_falls
	var bed := func(cell: Vector2i) -> float: return _rig._bed_levels.get(cell, _rig._elevation(cell))
	# Down any of its streams' paths (a tall fall's stream, 570, too).
	var true_falls := falls.all(func(fall: Dictionary) -> bool:
		return (stepped["streams"] as Array).any(func(stream: Dictionary) -> bool:
			var path: Array = stream["path"]
			var i := path.find(fall["cell"])
			return i > 0 and absf(bed.call(path[i - 1]) - bed.call(path[i]) - float(fall["drop"])) < 0.001 and float(fall["drop"]) > Client3D.FALL_LEAST))
	var at_step := falls.any(func(fall: Dictionary) -> bool: return fall["cell"] == step_at)
	# Each fall white on the water drawn there (559, terrain's side: from
	# the curve's ground, not its smoothed surface).
	var dry_falls := []
	for fall: Dictionary in falls:
		var white := false
		for ribbon: MeshInstance3D in _rig._stream_ribbons:
			var arrays := (ribbon.mesh as ArrayMesh).surface_get_arrays(0)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			for k in points.size():
				if colours[k].a > 0.5 and Vector2(points[k].x, points[k].z).distance_to(Vector2(fall["cell"])) < 1.5:
					white = true
		if not white:
			dry_falls.append(fall["cell"])
	_rig.rebuild(stepped, hills["centre"])
	_check(at_step and true_falls and not is_same(falls, _rig.stream_falls) and falls == _rig.stream_falls,
			"a step %.1f m down the stream at %s a fall there, each a step down its path over %.2f m (%s), a new array each build" % [FALL_STEP, step_at, Client3D.FALL_LEAST, falls])
	_check(dry_falls.is_empty(), "each fall white on the water there (none: %s)" % [dry_falls])
	# A tall fall (570, terrain's side): the land past the step lowered
	# FALL_TALL and more, the stream's surface keeps the step (never under
	# its bed either side) and hangs a curtain from the lip to the water
	# below, white, facing down the stream.
	var tall: Dictionary = hills["terrain"].duplicate(true)
	var tall_relief: PackedFloat32Array = tall["relief"]
	for y in relief_size.y:
		for x in relief_size.x:
			if Vector2(Vector2i(x, y) - step_at).dot(Vector2(way)) >= 0.0:
				tall_relief[y * relief_size.x + x] -= 3.0
	tall["relief"] = tall_relief
	_rig.rebuild(tall, hills["centre"])
	var curtain_rows := 0
	var curtain_top := -INF
	var curtain_foot := INF
	var curtain_wrong := 0
	for ribbon: MeshInstance3D in _rig._stream_ribbons:
		var arrays := (ribbon.mesh as ArrayMesh).surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for k in points.size():
			if uvs[k].y < 0.5:
				continue
			curtain_rows += 1
			curtain_top = maxf(curtain_top, points[k].y)
			curtain_foot = minf(curtain_foot, points[k].y)
			if colours[k].a < 0.99 or normals[k].y > 0.5:
				curtain_wrong += 1
	var dry_under := 0
	for curve_water: Dictionary in _rig._curve_waters:
		if curve_water["closed"]:
			continue
		var profile: PackedFloat32Array = curve_water["profile"]
		var ground := _rig._curve_ground(curve_water["curve"])
		for k in profile.size():
			# Over its own cells (past the map's edge the relief is none).
			var sample_cell := Vector2i(((curve_water["curve"]["points"] as PackedVector2Array)[k]).round())
			if _rig._curve_cells.has(sample_cell) and profile[k] < ground[k] - 0.5:
				dry_under += 1
	_check(curtain_rows >= (Client3D.CURTAIN_ROWS + 1) * 3 and curtain_top - curtain_foot > 2.5 and curtain_wrong == 0 and dry_under == 0,
			"a 3 m step down the stream hangs a curtain from its lip to the water below (%d points, %.2f m tall; wrong: %d), its surface never far under its bed (%d)" % [curtain_rows, curtain_top - curtain_foot, curtain_wrong, dry_under])
	_rig.rebuild(hills["terrain"], hills["centre"])
	# Mist at each tall fall's foot (570 amended, terrain's side): one
	# emitter a curtain, its puffs capped, on the water at the foot; none
	# where there is no tall fall (the sample).
	var curtains := 0
	for ribbon: MeshInstance3D in _rig._stream_ribbons:
		var uvs: PackedVector2Array = (ribbon.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		var rows := 0
		for uv in uvs:
			rows += 1 if uv.y >= 0.5 else 0
		curtains += rows / ((Client3D.CURTAIN_ROWS + 1) * 3)
	var misty := _rig._mists.size() == curtains and curtains > 0
	for mist: GPUParticles3D in _rig._mists:
		var near_foot := _rig._fall_feet.any(func(foot: Dictionary) -> bool: return (foot["at"] as Vector3).distance_to(mist.position) < 0.5)
		misty = misty and mist.amount <= Client3D.MIST_PUFFS and near_foot and mist.is_inside_tree()
	var mists := _rig._mists.size()
	# Its banks: within a walk of the water a grassy slope into it, no face;
	# a face only where the land stands a cliff over it.
	var faces: Dictionary = {}
	for edge: Array in _rig._cliff_edges:
		faces[edge] = true
	var low_faced := []
	var low_banks := 0
	for cell: Vector2i in _rig._corners:
		if _rig._wet.has(cell) or _rig._bed_levels.has(cell):
			continue
		for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := cell + direction
			if _rig._wet.has(next) and not _rig._fords.has(next) and _rig._elevation(cell) - _rig._elevation(next) <= Relief.WALK_RISE:
				low_banks += 1
				if faces.has([cell, direction]):
					low_faced.append([cell, direction])
	# The hills read: slopes lit against the sun, the valley floor darkened,
	# the crests lit (decision 525 amended, terrain's side).
	var lowest := Vector2i(-1, -1)
	var highest := Vector2i(-1, -1)
	for cell: Vector2i in _rig._corners:
		if _rig._wet.has(cell) or not Relief.on_map(_rig._relief_size, cell):
			continue
		if lowest.x < 0 or _rig._elevation(cell) < _rig._elevation(lowest):
			lowest = cell
		if highest.x < 0 or _rig._elevation(cell) > _rig._elevation(highest):
			highest = cell
	var shaded: float = _rig._ground_look.get_shader_parameter("slope_shade") if _rig._ground_look != null else 0.0
	_check(is_equal_approx(shaded, Client3D.SLOPE_SHADE) and _rig._concavity(lowest + Vector2i.ONE, _rig._elevation(lowest)) > 0.0
			and _rig._crest(highest, _rig._elevation(highest)) > 0.0,
			"hills read: slopes lit by the relief light (%.1f), the valley floor darkened, the crest lit" % shaded)
	# The relief light: from the screen's upper left whatever the hour,
	# turning with the camera (a north-south ridge's flanks part at noon).
	_rig._place_camera()
	var light := Client3D.hillshade_light(_rig.yaw)
	var screen_up := Vector3(_rig._camera_target - _rig._camera.global_position) * Vector3(1, 0, 1)
	var screen_left := -_rig._camera.global_transform.basis.x
	var turned := Client3D.hillshade_light(_rig.yaw + 90.0)
	_check(light.y > 0.5 and light.dot(screen_up.normalized()) > 0.3 and light.dot(screen_left) > 0.3
			and is_equal_approx(turned.y, light.y) and turned.dot(light) < 0.7
			and _rig._ground_look.get_shader_parameter("relief_light").is_equal_approx(light),
			"the relief light from the screen's upper left, turning with the camera (%s; up %s, left %s)" % [light, screen_up.normalized(), screen_left])
	_check(low_banks > 10 and low_faced.is_empty(),
			"a low bank slopes into the water as grass, no rock face (%d banks; faced: %s)" % [low_banks, low_faced.slice(0, 4)])
	# The camera over a ridge: ground standing 6 m between the player and the
	# camera lifts its pitch past the usual; none on the flat.
	var at := Vector3(sloped.x, _rig._ground_height(Vector2(sloped)), sloped.y)
	var flat := _rig.ridge_pitch(Vector3(4.0, _rig._ground_height(Vector2(4.0, 4.0)), 4.0))
	var back := Vector2(1.0, 1.0).normalized().rotated(-deg_to_rad(_rig.yaw))
	var had := _rig._corners.duplicate()
	for d in range(3, 7):
		var cell := Vector2i((Vector2(at.x, at.z) + back * d).round())
		_rig._corners[cell] = PackedFloat32Array([at.y + 6.0, at.y + 6.0, at.y + 6.0, at.y + 6.0])
	var lifted := _rig.ridge_pitch(at)
	_rig._corners = had
	_check(lifted > Client3D.CAMERA_PITCH and flat < Client3D.CAMERA_PITCH,
			"the camera lifts over a ridge between it and the player (%.0f degrees), not on the flat (%.0f)" % [lifted, flat])
	# The castle: no relief.png, its ground exactly its whole levels.
	var castle := Level.load_level("castle")
	_rig.rebuild(castle["terrain"], castle["centre"])
	# The hills' mists gone with them: the castle has no fall.
	var none_without := _rig._mists.is_empty()
	_check(misty and none_without, "mist at each tall fall's foot, %d puffs at most (%d curtains, %d mists), none without a fall (%s)" % [Client3D.MIST_PUFFS, curtains, mists, none_without])
	var off := []
	for cell: Vector2i in _rig._corners:
		if _rig._ramp_heights.has(cell) or _rig._bed_levels.has(cell):
			continue
		var whole := _rig._height(cell) * Client3D.LEVEL_RISE
		if _rig._corners[cell] != PackedFloat32Array([whole, whole, whole, whole]):
			off.append(cell)
	var castle_shade: float = _rig._ground_look.get_shader_parameter("slope_shade")
	_check(not castle["terrain"].get("relief_given", false) and off.is_empty() and castle_shade == 0.0,
			"the castle (no relief.png) drawn exactly as its whole levels (%d cells off: %s)" % [off.size(), off.slice(0, 4)])
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## levels/sample's outcrop (decision 513, terrain's side): its rocks drawn
## as rocks (a large one over a 2x2 clump, small ones on the rest), never a
## tree, on ground of their footing and no scatter; its slopes ramps in the
## ground, nothing stair-like on them.
## The barrow's burial niches (542 amended, terrain's side): a generated
## barrow's "niches" read into terrain["niches"] (a bad one said and left
## out), and art-kit's prop.burial_niche drawn on each, a MultiMesh a
## variant and mesh, every niche once, the lid with it.
func _test_niches() -> void:
	print("
== niches: the barrow's burial niches drawn ==")
	var warnings: Array[String] = []
	var wall := Terrain.edge_key(Vector2i(1, 1), Vector2i(0, 1))
	var parsed := Level.niches_from({"niches": [[1, 1, 0, 1, "a", 2], [1, 1, 1, 1, "a", 2], [1, 1, 0, 1, "a", 4], [99, 99, 0, 1, "a", 1], [1, 1, 0, 1, "x", 1],
			[1, 1, 0, -1, "hidden", 1], [1, 1, 1, 0, "b", 1]]},
			{"floor": [Vector2i(1, 1), Vector2i(2, 1)], "edges": {wall: Terrain.Edge.WALL, Terrain.edge_key(Vector2i(1, 1), Vector2i(0, -1)): Terrain.Edge.DOOR}}, warnings)
	_check(parsed.size() == 1 and parsed[0]["out"] == Vector2i(0, -1) and parsed[0]["edge"] == wall and parsed[0]["kind"] == "a" and parsed[0]["variant"] == 2 and warnings.size() == 6,
			"niches read as {cell, out, edge, kind, variant} (608); a diagonal step, a bad variant, no floor, a kind there is not, a hidden one with rock behind its door and a wall with floor behind said and left out (%d)" % warnings.size())
	var made := Regen.generate("barrow_deep", 1)  # The deep holds the tombs (580); the first layer lists no niches.
	if made.is_empty():
		_check(false, "the barrow's deep generates")
		return
	var level := Level.parse(made["layout"], made["height"], made["config"], made.get("relief"))
	var niches: Array = level["terrain"].get("niches", [])
	_check(not niches.is_empty() and niches.all(func(n: Dictionary) -> bool: return level["terrain"]["floor"].has(n["cell"])),
			"a generated barrow's niches reach the terrain, each on floor (%d)" % niches.size())
	# Drawn as wall edges (608, terrain's side): each niche's edge, behind
	# its cell, art-kit's wall.crypt.niche_<kind> in its wall run, +x toward
	# the room; no niche prop left in the cells.
	var terrain: Dictionary = level["terrain"].duplicate()
	# A hidden niche on one of its doors: the cracked wall, no doorway.
	var door_key := Vector3i.MAX
	var door_cell := Vector2i.ZERO
	var door_out := Vector2i.ZERO
	for key: Vector3i in terrain["edges"]:
		if terrain["edges"][key] != Terrain.Edge.DOOR:
			continue
		var sides := Terrain.edge_cells(key)
		if (terrain["floor"] as Array).has(sides[0]):
			door_key = key
			door_cell = sides[0]
			door_out = Vector2i(-1, 0) if key.z == Terrain.EAST else Vector2i(0, -1)
			break
	if door_key != Vector3i.MAX:
		terrain["niches"] = niches + [{"cell": door_cell, "out": door_out, "edge": door_key, "kind": "hidden", "variant": 1}]
	_rig.rebuild(terrain, level["centre"])
	var placed := 0
	var turned := 0
	for niche: Dictionary in niches:
		var edge := Terrain.edge_key(niche["cell"], -(niche["out"] as Vector2i))
		var holder: Node3D = _rig._walls.get(edge)
		if holder == null:
			continue
		var k := (edge.y if edge.z == Terrain.EAST else edge.x) - (holder.name.get_slice("_", 2).to_int() if edge.z == Terrain.EAST else holder.name.get_slice("_", 1).to_int())
		var piece := holder.get_node_or_null("Piece_%d" % k) as Node3D
		if piece == null:
			continue
		placed += 1
		# Its +x in the world toward the niche's cell.
		var x_axis := piece.global_transform.basis.x
		if Vector2(x_axis.x, x_axis.z).dot(Vector2(niche["out"])) > 0.9:
			turned += 1
	_check(not niches.is_empty() and placed == niches.size() and turned == placed and _rig._room.get_node_or_null("Niches") == null,
			"each niche a wall piece on its edge, +x toward its room (%d of %d placed, %d turned); no niche props" % [placed, niches.size(), turned])
	if door_key != Vector3i.MAX:
		var hidden := _rig._room.get_node_or_null("HiddenNiche_%d_%d_%s" % [door_key.x, door_key.y, "e" if door_key.z == Terrain.EAST else "s"]) as Node3D
		var doorway := _rig._doorways.has(door_key)
		_check(hidden != null and not doorway and (hidden.get_node("Cracked") as Node3D).visible and not (hidden.get_node("Open") as Node3D).visible,
				"the hidden niche's door edge: the cracked wall, no doorway, the open niche hidden till found")
		# Its footprints (608 amended), once art-kit's prop.footprints is in:
		# on its cell, +x toward the wall.
		if ArtKit.has(Client3D.NICHE_FOOTPRINTS):
			var prints := _rig._room.get_node_or_null("Footprints_%d_%d" % [door_cell.x, door_cell.y]) as Node3D
			var toward := Vector2.ZERO
			if prints != null:
				toward = Vector2(prints.global_transform.basis.x.x, prints.global_transform.basis.x.z)
			_check(prints != null and toward.dot(-Vector2(door_out)) > 0.9 and absf(prints.position.x - door_cell.x) < 0.01,
					"the hidden niche's footprints on its cell, toward the wall (%s)" % toward)
		# Its draft (608 amended, environment's side): low, drifting into the
		# room, lit, while shut; off once open, back if it shuts.
		var draft := hidden.get_node_or_null("Draft") as GPUParticles3D if hidden != null else null
		var process := draft.process_material as ParticleProcessMaterial if draft != null else null
		var into := draft.global_transform.basis * process.direction if process != null else Vector3.ZERO
		var lit := draft != null and (draft.draw_pass_1.surface_get_material(0) as StandardMaterial3D).shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED
		_check(draft != null and draft.emitting and lit and draft.position.y + process.emission_box_extents.y <= Client3D.DRAFT_LOW
				and Vector2(into.x, into.z).normalized().dot(Vector2(door_out)) > 0.9,
				"the hidden niche's draft: lit, low, drifting out into its room while shut")
		if draft != null:
			_rig._show_hidden_niche(door_key, true)
			var off := not draft.emitting and (hidden.get_node("Open") as Node3D).visible
			_rig._show_hidden_niche(door_key, false)
			_check(off and draft.emitting and (hidden.get_node("Cracked") as Node3D).visible,
					"the draft stops when the niche's door opens and comes back when it shuts")
			# 608 amended (2): opened from shut as drawn, it gives way: the dust,
			# and the slab (art-kit's, else a stand-in here) shudders, grinds
			# back, slides into the wall and is hidden; opened again with no
			# shut between, nothing replays.
			var parts: Array = _rig._hidden_niches[door_key]
			var stand_in: Node3D = null
			if parts[3] == null:
				stand_in = Node3D.new()
				stand_in.name = "Slab"
				stand_in.visible = false
				hidden.add_child(stand_in)
				parts[3] = stand_in
			var slab := parts[3] as Node3D
			var dust := parts[4] as GPUParticles3D
			_rig._show_hidden_niche(door_key, true)
			var tween := slab.get_meta(&"tween") as Tween if slab.has_meta(&"tween") else null
			_check(dust.emitting and dust.one_shot and slab.visible and tween != null and tween.is_valid()
					and is_equal_approx(slab.position.x, Client3D.SLAB_FACE_X),
					"found as it is drawn: the dust bursts and the slab stands flush in the doorway, moving")
			tween.custom_step(Client3D.SLAB_SHUDDER + Client3D.SLAB_BACK_SECONDS + 0.01)
			var back := slab.position
			tween.custom_step(Client3D.SLAB_SLIDE_SECONDS)
			_check(is_equal_approx(back.x, Client3D.SLAB_FACE_X - Client3D.SLAB_BACK) and absf(back.z) < 0.02
					and is_equal_approx(slab.position.z, Client3D.SLAB_SLIDE) and not slab.visible,
					"it grinds back %.2f m, then slides %.2f m along the wall into it and is hidden (%s, %s)" % [Client3D.SLAB_BACK, Client3D.SLAB_SLIDE, back, slab.position])
			dust.emitting = false
			_rig._show_hidden_niche(door_key, true)
			_check(not dust.emitting and not slab.visible, "shown open again, it does not give way twice")
			_rig._show_hidden_niche(door_key, false)
			_check(not slab.visible and is_equal_approx(slab.position.x, Client3D.SLAB_FACE_X), "shut again, the slab is back in place, hidden behind the cracked wall")
			if stand_in != null:
				parts[3] = null
				stand_in.free()
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


func _test_rocks() -> void:
	print("\n== rocks and slopes: rocks for trees, ramps for slopes ==")
	var sample := Level.load_level("sample")
	var terrain: Dictionary = sample["terrain"]
	var rocks: Array = terrain.get("rocks", [])
	var slopes: Array = (terrain.get("slopes", {}) as Dictionary).keys()
	_check(not rocks.is_empty() and not slopes.is_empty(), "the sample has rocks and slopes (%d, %d)" % [rocks.size(), slopes.size()])
	if rocks.is_empty() or slopes.is_empty():
		return
	var plan := Client3D.rock_plan({Vector2i(0, 0): true, Vector2i(1, 0): true, Vector2i(0, 1): true, Vector2i(1, 1): true,
			Vector2i(2, 0): true, Vector2i(2, 1): true, Vector2i(5, 5): true})
	_check(plan["large"] == [Vector2i(0, 0)] and plan["small"] == [Vector2i(2, 0), Vector2i(2, 1), Vector2i(5, 5)],
			"a large rock over a 2x2 clump, small ones on the rest, no cell twice (%s)" % [plan])
	_rig.rebuild(terrain, sample["centre"])
	_rig._scatter_all()
	var kinds: Dictionary = terrain["kinds"]
	var heights: Dictionary = terrain.get("heights", {})
	var no_tree := rocks.all(func(cell: Vector2i) -> bool: return not _rig._trees.has(cell) and _rig._forest_distance.get(cell, 0) == 0)
	var grounded := rocks.all(func(cell: Vector2i) -> bool:
		var index: int = _rig._grounds.get(cell, -1)
		return index >= 0 and index < _rig._ground_floor_end and _rig._ground_kinds[cell] == str(kinds.get(cell, "")) \
				and absf(Array(_rig._corner_heights(cell)).reduce(func(a: float, b: float) -> float: return a + b, 0.0) / 4.0 - _rig._elevation(cell)) < 0.3)
	_check(no_tree and grounded, "no tree on a rock; its ground its footing, at its height (trees %s, ground %s)" % [no_tree, grounded])
	var on_rock := false
	for chunk: Vector2i in _rig._scatter_chunks:
		var placed := _rig._scatter_plan(chunk)
		for kind: String in placed:
			for item: Array in placed[kind]:
				on_rock = on_rock or rocks.has(item[0])
	_check(not on_rock, "no scatter on a rock")
	var walled := 0
	for key: Vector3i in _rig._walls:
		walled += 1 if Terrain.edge_cells(key).any(func(cell: Vector2i) -> bool: return rocks.has(cell)) else 0
	var rock_edges := 0
	for key: Vector3i in terrain["edges"]:
		rock_edges += 1 if terrain["edges"][key] == Terrain.Edge.WALL and Terrain.edge_cells(key).any(func(cell: Vector2i) -> bool: return rocks.has(cell)) else 0
	_check(rock_edges > 0 and walled == 0, "no wall drawn round a rock, though the sim walls it (%d edges, %d drawn)" % [rock_edges, walled])
	var drawn := _rig._room.get_node_or_null("Rocks") as Node3D
	var counts := {"small": 0, "large": 0}
	var shadowed := true
	if drawn != null:
		for many: MultiMeshInstance3D in drawn.find_children("*", "MultiMeshInstance3D", false, false):
			# Named size_variant_mesh: a piece of several meshes counted once.
			if String(many.name).get_slice("_", 2) == "0":
				counts[String(many.name).get_slice("_", 0)] += many.multimesh.instance_count
			shadowed = shadowed and many.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var wanted := Client3D.rock_plan(_rig._rocks)
	_check(drawn != null and counts["small"] == wanted["small"].size() and counts["large"] == wanted["large"].size()
			and counts["small"] + 4 * counts["large"] == rocks.size() and shadowed,
			"each rock drawn, casting shadows (%s of %d cells)" % [counts, rocks.size()])
	var stairs: Dictionary = terrain.get("stairs", {})
	var ramps := slopes.all(func(cell: Vector2i) -> bool:
		var corners := Array(_rig._corner_heights(cell))
		var top := maxf(_rig._elevation(cell + stairs.get(cell, Vector2i.ZERO)), _rig._elevation(cell) + 0.3)
		return stairs.has(cell) and absf(corners.max() - top) < 0.25 and corners.max() - corners.min() >= 0.3)
	_check(ramps and _rig._room.find_children("*tair*", "", true, false).is_empty(),
			"a slope is a ramp in the ground, a level up its high side; nothing stair-like drawn")
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## levels/sample's tall grass (decision 508, terrain's side): its clumps,
## tall, in place of the tufts, bending in the wind; each drawn clump known
## by its cell; a cell trampled laid flat and stood again, and a full set
## (both lists empty) read again whole.
func _test_tall_grass() -> void:
	print("\n== tall grass: clumps for tufts, laid flat when trampled ==")
	var sample := Level.load_level("sample")
	var terrain: Dictionary = sample["terrain"]
	var grass: Array = terrain.get("tall_grass", [])
	_check(not grass.is_empty(), "the sample has tall grass (%d cells)" % grass.size())
	if grass.is_empty():
		return
	# The game's first build is setup's, not rebuild's: the ground's build
	# reads the cells (e0d25913 read them in rebuild alone, and the game drew
	# the lawn).
	_rig.rebuild(terrain, sample["centre"])
	_rig._tall.clear()
	_rig._build_ground(terrain["kinds"])
	_check(_rig._tall.size() == grass.size(), "the ground's build reads its cells, setup's first build too (%d)" % _rig._tall.size())
	_rig.rebuild(terrain, sample["centre"])
	_rig._scatter_all()
	var clumps := 0
	var tufts := 0
	for chunk: Vector2i in _rig._scatter_chunks:
		var plan := _rig._scatter_plan(chunk)
		for item: Array in plan.get("tall", []):
			clumps += 1 if grass.has(item[0]) else 0
		for item: Array in plan.get("tuft", []):
			tufts += 1 if grass.has(item[0]) else 0
	_check(clumps >= grass.size() * 7 and tufts == 0, "clumps on its cells, about nine a cell, no tufts (%d on %d cells, %d tufts)" % [clumps, grass.size(), tufts])
	var high := Client3D._scatter_mesh("tall").get_aabb().end.y
	_check(high > 0.75 and high < 1.12 and "tall" in Client3D.SWAYING, "its blades about a metre and bending in the wind (%.2f m)" % high)
	_check(grass.all(func(cell: Vector2i) -> bool: return _rig._tall_where.has(cell)), "each cell's clumps known, to redraw it alone")
	var had_tall := _rig._tall.duplicate()
	for x in 3:
		for y in 3:
			_rig._tall[Vector2i(100 + x, 100 + y)] = true
	_check(_rig._tall_edge(Vector2i(100, 101)) and not _rig._tall_edge(Vector2i(101, 101)), "the patch's edge known (its clumps taller there)")
	_rig._tall = had_tall
	_check(Client3D.tall_look(Color(0.5, 0.6, 0.3), true).a == 0.0 and Client3D.tall_look(Color(0.5, 0.6, 0.3), false).a == 1.0
			and is_equal_approx(Client3D.tall_look(Color(0.5, 0.6, 0.3), true).g, 0.6), "trampled is its colour's alpha 0, standing 1, its colour kept")
	var cell: Vector2i = grass[0]
	# (Headless, a MultiMesh keeps no colours: the cells it drew flat.)
	var alpha := func() -> float: return 0.0 if _rig._tall_flat.has(cell) else 1.0
	var was: Dictionary = World._trampled_here.duplicate()
	World._trampled_here[cell] = 1
	_rig._on_grass_changed(World.fields.level, PackedInt32Array([cell.x, cell.y]), PackedInt32Array())
	var flat: float = alpha.call()
	World._trampled_here.erase(cell)
	_rig._on_grass_changed(World.fields.level, PackedInt32Array(), PackedInt32Array([cell.x, cell.y]))
	var stood: float = alpha.call()
	World._trampled_here[cell] = 1
	_rig._on_grass_changed(World.fields.level, PackedInt32Array(), PackedInt32Array())
	var full: float = alpha.call()
	World._trampled_here.clear()
	World._trampled_here.merge(was)
	_check(flat == 0.0 and stood == 1.0 and full == 0.0, "trampled laid flat, stood again, and a full set read again (%.0f, %.0f, %.0f)" % [flat, stood, full])
	_rig._flattened.clear()
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## A wounded animal's blood (764, terrain's side): a few dark specks to a
## marked cell, on its ground, none on water, fading out over their last
## BLOOD_FADE_MS, gone when told, only the zone's own level drawn.
func _test_blood() -> void:
	print("
== blood: specks on the ground, fading, none on water ==")
	var sample := Level.load_level("sample")
	var terrain: Dictionary = sample["terrain"].duplicate()
	terrain["outdoor"] = true
	_rig.rebuild(terrain, sample["centre"])
	var level: String = World.zone.name
	var land := Vector2i(-1, -1)
	var wet := Vector2i(-1, -1)
	for cell: Vector2i in terrain["floor"]:
		if _rig._terrain_water_has(cell):
			wet = cell if wet.x < 0 else wet
		elif land.x < 0 and not _rig._terrain_water_has(cell + Vector2i(1, 0)):
			land = cell
	for cell: Vector2i in terrain.get("water", []):
		wet = cell if wet.x < 0 else wet
	_check(_rig._outdoor and land.x >= 0 and wet.x >= 0, "the sample, outdoors, has land and water (%s, %s)" % [land, wet])
	_rig._on_blood_changed(level, PackedInt32Array([land.x, land.y, 200, wet.x, wet.y, 200]), PackedInt32Array(), true)
	var drawn: MultiMeshInstance3D = _rig._blood_drawn
	var count := drawn.multimesh.instance_count if drawn != null else 0
	count = count if count == _rig._blood_specks.size() else -1
	var far := 0.0
	var off := 0.0
	for i in count:
		var at: Vector3 = _rig._blood_specks[i].origin
		far = maxf(far, Vector2(at.x - land.x, at.z - land.y).length())
		off = maxf(off, absf(at.y - 0.015 - _rig._height_in(land, Vector2(at.x, at.z))))
	_check(count >= Client3D.BLOOD_SPECKS.x and count <= Client3D.BLOOD_SPECKS.y and far < 0.6 and off < 0.001,
			"a few specks on the land cell, on its ground, none on the water (%d, %.2f m out, %.3f m off)" % [count, far, off])
	_check(not _rig._blood_shades.is_empty() and _rig._blood_shades.all(func(c: Color) -> bool: return c.a >= 0.74), "fresh, not faded (%s)" % [_rig._blood_shades.map(func(c: Color) -> float: return snappedf(c.a, 0.01))])
	var had_kind: String = _rig._ground_kinds.get(land, "")
	_rig._ground_kinds[land] = "grass"
	_rig._draw_blood()
	var on_grass: Color = _rig._blood_shades[0] if not _rig._blood_shades.is_empty() else Color.BLACK
	_rig._ground_kinds[land] = "dirt"
	_rig._draw_blood()
	var on_dirt: Color = _rig._blood_shades[0] if not _rig._blood_shades.is_empty() else Color.BLACK
	var wide := _rig._blood_specks[0].basis.get_scale().z if not _rig._blood_specks.is_empty() else 0.0
	_rig._ground_kinds[land] = "grass"
	_rig._draw_blood()
	var narrow := _rig._blood_specks[0].basis.get_scale().z if not _rig._blood_specks.is_empty() else 0.0
	_rig._ground_kinds[land] = had_kind
	_check(on_dirt.r > on_grass.r * 1.5 and wide > narrow * 1.2, "redder and bigger on dirt, to be seen there (%.2f vs %.2f red, %.3f vs %.3f m)" % [on_dirt.r, on_grass.r, wide, narrow])
	_rig._on_blood_changed(level, PackedInt32Array([land.x, land.y, Client3D.BLOOD_FADE_MS / 2000]), PackedInt32Array())
	_check(not _rig._blood_shades.is_empty() and _rig._blood_shades.all(func(c: Color) -> bool: return c.a > 0.3 and c.a < 0.55) and _rig._blood_due > 0,
			"half way through its fade, half seen, and a redraw due (%s)" % [_rig._blood_shades.map(func(c: Color) -> float: return snappedf(c.a, 0.01))])
	_rig._on_blood_changed(level, PackedInt32Array(), PackedInt32Array([land.x, land.y, wet.x, wet.y]))
	_check(_rig._blood_drawn == null and _rig._blood_shades.is_empty() and not _rig._blood.has(level), "gone when told")
	_rig._on_blood_changed("elsewhere", PackedInt32Array([land.x, land.y, 200]), PackedInt32Array(), true)
	_check(_rig._blood_drawn == null and _rig._blood.has("elsewhere"), "another level's kept, not drawn")
	_rig._on_blood_changed(level, PackedInt32Array([land.x, land.y, 0]), PackedInt32Array(), true)
	_check(_rig._blood_drawn == null and not _rig._blood.has(level), "one past its time dropped")
	_rig._blood.clear()
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## An apex creature's prints (780 amended (3), terrain's side): a pair of
## paws a print, pointing the way walked, on the ground, none on water or
## hard ground, more seen on grass, fading, gone when told, none indoors.
func _test_tracks() -> void:
	print("\n== tracks: a pair of paws a print, the way walked, none on water or stone ==")
	var sample := Level.load_level("sample")
	var terrain: Dictionary = sample["terrain"].duplicate()
	terrain["outdoor"] = true
	_rig.rebuild(terrain, sample["centre"])
	var level: String = World.zone.name
	var land := Vector2i(-1, -1)
	var wet := Vector2i(-1, -1)
	var floor_cells: Array = terrain["floor"]
	for cell: Vector2i in floor_cells:
		if _rig._terrain_water_has(cell):
			wet = cell if wet.x < 0 else wet
			continue
		if land.x >= 0:
			continue
		var dry := true
		for y in range(-1, 2):
			for x in range(-1, 2):
				var near := cell + Vector2i(x, y)
				dry = dry and floor_cells.has(near) and not _rig._terrain_water_has(near)
		if dry:
			land = cell
	for cell: Vector2i in terrain.get("water", []):
		wet = cell if wet.x < 0 else wet
	_check(_rig._outdoor and land.x >= 0 and wet.x >= 0, "the sample, outdoors, has dry land and water (%s, %s)" % [land, wet])
	var kinds_were := {}
	var set_kind := func(kind: String) -> void:
		for y in range(-1, 2):
			for x in range(-1, 2):
				_rig._ground_kinds[land + Vector2i(x, y)] = kind
	for y in range(-1, 2):
		for x in range(-1, 2):
			var near := land + Vector2i(x, y)
			kinds_were[near] = _rig._ground_kinds.get(near, null)
	set_kind.call("dirt")
	# Facing east (2): the toes east of each pad, the right (south) paw ahead.
	_rig._on_tracks_changed(level, PackedInt32Array([land.x, land.y, 200, 2, wet.x, wet.y, 200, 2]), PackedInt32Array(), true)
	var parts: Array[Transform3D] = _rig._track_parts
	var drawn: MultiMeshInstance3D = _rig._tracks_drawn
	var count := drawn.multimesh.instance_count if drawn != null else 0
	_check(count == 12 and parts.size() == 12, "two paws of a pad and five toes on the land, none on the water (%d parts)" % count)
	var far := 0.0
	var off := 0.0
	for part in parts:
		var at := Vector2(part.origin.x, part.origin.z)
		far = maxf(far, at.distance_to(Vector2(land)))
		var cell := Vector2i(roundi(at.x), roundi(at.y))
		off = maxf(off, absf(part.origin.y - 0.012 - _rig._height_in(cell, at)))
	_check(count == 12 and far < 1.0 and off < 0.001, "round the cell, on its ground (%.2f m out, %.3f m off)" % [far, off])
	var pointing := func(of: Array[Transform3D], index: int) -> Vector2:
		var pad := Vector2(of[index].origin.x, of[index].origin.z)
		var toes := Vector2.ZERO
		for t in range(1, 6):
			toes += Vector2(of[index + t].origin.x, of[index + t].origin.z) / 5.0
		return (toes - pad).normalized()
	if count == 12:
		var way: Vector2 = pointing.call(parts, 0)
		var other: Vector2 = pointing.call(parts, 6)
		var pads := Vector2(parts[6].origin.x, parts[6].origin.z) - Vector2(parts[0].origin.x, parts[0].origin.z)
		var big := parts[0].basis.get_scale().x
		_check(way.dot(Vector2(1, 0)) > 0.95 and other.dot(Vector2(1, 0)) > 0.95 and pads.y > 0.2 and pads.x > 0.05 and big > 0.3,
				"pointing east the way walked, side by side, the right one ahead, a big bear's pad (%s, %s, apart %s, %.2f m)" % [way, other, pads, big])
	_rig._on_tracks_changed(level, PackedInt32Array([land.x, land.y, 200, 0]), PackedInt32Array(), true)
	parts = _rig._track_parts
	var north: Vector2 = pointing.call(parts, 0) if parts.size() == 12 else Vector2.ZERO
	_check(north.dot(Vector2(0, -1)) > 0.95, "facing 0 points north, up the map (%s)" % north)
	var on_dirt := _rig._track_shades[0].a if not _rig._track_shades.is_empty() else 0.0
	set_kind.call("grass")
	_rig._draw_tracks()
	var on_grass := _rig._track_shades[0].a if not _rig._track_shades.is_empty() else 0.0
	_check(on_dirt > 0.35 and on_grass > on_dirt * 1.2, "fresh, and more of it on grass, to be seen there (%.2f on dirt, %.2f on grass)" % [on_dirt, on_grass])
	set_kind.call("stone")
	_rig._draw_tracks()
	_check(_rig._tracks_drawn == null and _rig._track_parts.is_empty(), "none on stone ground")
	set_kind.call("dirt")
	_rig._outdoor = false
	_rig._draw_tracks()
	_rig._outdoor = true
	_check(_rig._tracks_drawn == null, "none indoors")
	_rig._on_tracks_changed(level, PackedInt32Array([land.x, land.y, Client3D.TRACK_FADE_MS / 2000, 2]), PackedInt32Array())
	_check(not _rig._track_shades.is_empty() and _rig._track_shades.all(func(c: Color) -> bool: return c.a > 0.2 and c.a < 0.4) and _rig._tracks_due > 0,
			"half way through its fade, half seen, and a redraw due (%s)" % [_rig._track_shades.slice(0, 1).map(func(c: Color) -> float: return snappedf(c.a, 0.01))])
	_rig._on_tracks_changed(level, PackedInt32Array(), PackedInt32Array([land.x, land.y, wet.x, wet.y]))
	_check(_rig._tracks_drawn == null and _rig._track_parts.is_empty() and not _rig._tracks.has(level), "gone when told")
	_rig._on_tracks_changed("elsewhere", PackedInt32Array([land.x, land.y, 200, 2]), PackedInt32Array(), true)
	_check(_rig._tracks_drawn == null and _rig._tracks.has("elsewhere"), "another level's kept, not drawn")
	_rig._on_tracks_changed(level, PackedInt32Array([land.x, land.y, 0, 2]), PackedInt32Array(), true)
	_check(_rig._tracks_drawn == null and not _rig._tracks.has(level), "one past its time dropped")
	World.tracks_changed.emit(level, PackedInt32Array([land.x, land.y, 200, 4]), PackedInt32Array(), true)
	_check(_rig._tracks_drawn != null and _rig._track_parts.size() == 12, "drawn from World.tracks_changed")
	for near: Vector2i in kinds_were:
		if kinds_were[near] == null:
			_rig._ground_kinds.erase(near)
		else:
			_rig._ground_kinds[near] = kinds_were[near]
	_rig._tracks.clear()
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## A cave mouth (a link's cue "cave", the forest plan's lairs): a hill of
## rock behind the link cell, the way it faces; an open arch at the cell's
## far edge, its throat going black; no art rock under the hill.
func _test_cave_mouth() -> void:
	print("\n== cave mouth: a hill of rock, an open arch, a throat going black ==")
	var sample := Level.load_level("sample")
	var terrain: Dictionary = sample["terrain"].duplicate()
	terrain["outdoor"] = true
	var floor_cells: Array = terrain["floor"]
	var at := Vector2i(-1, -1)
	for cell: Vector2i in floor_cells:
		if floor_cells.has(cell + Vector2i(0, -5)) and floor_cells.has(cell + Vector2i(3, -5)) and floor_cells.has(cell + Vector2i(-3, -5)):
			at = cell
			break
	_check(at.x >= 0, "the sample has room for a hill (%s)" % at)
	if at.x < 0:
		return
	var ahead := Vector2i(0, -1)
	terrain["link_cues"] = [{"tile": at, "cue": "cave", "facing": ahead, "variant": 1}]
	_rig.rebuild(terrain, sample["centre"])
	var holder: Node3D = _rig._room.get_node_or_null("Mouth_%d_%d" % [at.x, at.y])
	var body: MeshInstance3D = holder.get_node_or_null("Body") if holder != null else null
	_check(body != null and body.mesh != null, "drawn on the link's cell, in one mesh")
	if body == null or body.mesh == null:
		_rig.rebuild(_main._terrain, Vector2i.ZERO)
		return
	var arrays := body.mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var shades: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	# In the mouth's frame: +z into the hill.
	var top := -INF
	var out := 0.0
	for p in points:
		top = maxf(top, p.y)
		out = maxf(out, maxf(absf(p.x) - Client3D.MOUTH_HILL.x * 0.5, maxf(0.2 - p.z, p.z - Client3D.MOUTH_HILL.z)))
	var into := holder.transform.basis * Vector3(0, 0, 1)
	_check(top > Client3D.MOUTH_ARCH.y + 0.6 and out < 0.05 and Vector2(into.x, into.z).dot(Vector2(ahead)) > 0.99,
			"a hill of rock behind the cell, the way it faces (%.1f m high, %.2f m out, into %s)" % [top, out, into])
	# Looking in at the arch's middle, waist high: the first thing met is
	# the black end of the throat, not rock across the arch.
	var near := INF
	var met := Color.WHITE
	var from := Vector3(0.0, 1.0, -2.0)
	for i in range(0, points.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(from, Vector3(0, 0, 1), points[i], points[i + 1], points[i + 2])
		if hit != null and (hit as Vector3).z < near:
			near = (hit as Vector3).z
			met = shades[i]
	_check(near > 0.5 + Client3D.MOUTH_THROAT - 0.1 and met.get_luminance() < 0.01,
			"the arch open, its throat going black (met at %.2f m, %.3f)" % [near, met.get_luminance()])
	# Along the throat's floor, just over it, to either side: its wall met
	# at the arch's edge, no slit under the vault (the light line the
	# coordinator saw from above).
	var slit := 0.0
	for side: float in [-1.0, 1.0]:
		for z: float in [0.9, 1.8, 2.7]:
			var at_floor := Vector3(0.0, 0.05, z)
			var reach := INF
			for i in range(0, points.size(), 3):
				var hit: Variant = Geometry3D.ray_intersects_triangle(at_floor, Vector3(side, 0, 0), points[i], points[i + 1], points[i + 2])
				if hit != null:
					reach = minf(reach, absf((hit as Vector3).x))
			slit = maxf(slit, reach)
	_check(slit < Client3D.MOUTH_ARCH.x * 0.5 + 0.1,
			"the throat's walls down to its floor, no slit along its sides (met at %.2f m)" % slit)
	var face_hit := INF
	from = Vector3(Client3D.MOUTH_ARCH.x * 0.5 + 0.6, 1.0, -2.0)
	for i in range(0, points.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(from, Vector3(0, 0, 1), points[i], points[i + 1], points[i + 2])
		if hit != null:
			face_hit = minf(face_hit, (hit as Vector3).z)
	_check(face_hit < 0.8, "beside the arch, the hill's face (met at %.2f m)" % face_hit)
	var under := _rig._mouth_cells()
	_check(under.size() == Client3D.MOUTH_CELLS.x * Client3D.MOUTH_CELLS.y and under.has(at + ahead) and under.has(at + ahead * Client3D.MOUTH_CELLS.y) and not under.has(at),
			"its hill's cells behind the link, none on it (%d)" % under.size())
	# No ground in its throat (in a bank it would wall the arch up).
	var throat := _rig._throat_cells()
	var walled := 0
	for cell: Vector2i in _rig._ground_cells:
		if throat.has(cell):
			walled += 1
	_check(throat.has(at + ahead) and throat.has(at + ahead * 3) and not throat.has(at) and walled == 0,
			"no ground in its throat (%d cells, %d drawn)" % [throat.size(), walled])
	# An outcrop grown out of the hills (the coordinator): grass and moss on
	# some of its gentle top facets, rock darkest just over the arch, scree
	# at its foot.
	var green := 0
	var lip := INF
	var face_rest := 0.0
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in range(0, points.size(), 3):
		var shade := shades[i]
		if normals[i].y > 0.8 and shade.g > shade.r * 1.15 and shade.g > shade.b * 1.15:
			green += 1
		var middle := (points[i] + points[i + 1] + points[i + 2]) / 3.0
		if absf(normals[i].z) > 0.9 and middle.z < 0.8:
			if absf(middle.x) < Client3D.MOUTH_ARCH.x * 0.5 and middle.y > Client3D.MOUTH_ARCH.y and middle.y < Client3D.MOUTH_ARCH.y + 0.25:
				lip = minf(lip, shade.get_luminance())
			elif absf(middle.x) > Client3D.MOUTH_ARCH.x * 0.5 + Client3D.MOUTH_LIP_REACH and middle.y > 0.3:
				face_rest = maxf(face_rest, shade.get_luminance())
	_check(green > 4 and lip < face_rest * 0.6, "grass on its top, its lip in shadow (%d green facets, lip %.3f, face %.3f)" % [green, lip, face_rest])
	var scree: Node3D = holder.get_node_or_null("Scree")
	_check(scree != null and scree.get_child_count() == Client3D.MOUTH_SCREE.size(), "scree at its foot (%d)" % (scree.get_child_count() if scree != null else 0))
	var open_heap := holder.get_node_or_null("Rockfall")
	# Closed (the link closed or sealed): a rockfall heaped in the arch.
	terrain["link_cues"] = [{"tile": at, "cue": "cave", "facing": ahead, "variant": 1, "closed": true}]
	_rig.rebuild(terrain, sample["centre"])
	holder = _rig._room.get_node_or_null("Mouth_%d_%d" % [at.x, at.y])
	var heap: Node3D = holder.get_node_or_null("Rockfall") if holder != null else null
	var stones := heap.get_child_count() if heap != null else 0
	var stray := 0.0
	for stone: Node3D in (heap.get_children() if heap != null else []):
		stray = maxf(stray, maxf(absf(stone.position.x) - Client3D.MOUTH_ARCH.x * 0.5, maxf(-0.5 - stone.position.z, stone.position.z - 1.6)))
	_check(open_heap == null and stones == Client3D.MOUTH_ROCKFALL.size() and stray <= 0.0,
			"closed, a rockfall heaped in the arch; none when open (%d stones, %.2f m stray)" % [stones, stray])
	# Kept low, so the black throat shows over it across the arch (the
	# coordinator: a cave, blocked, in daylight).
	var heap_top := -INF
	for mesh: MeshInstance3D in (heap.find_children("*", "MeshInstance3D", true, false) if heap != null else []):
		var box := holder.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		heap_top = maxf(heap_top, box.end.y)
	_check(heap_top < Client3D.MOUTH_ROCKFALL_TOP + 0.1 and heap_top < Client3D.MOUTH_ARCH.y - 1.0,
			"the rockfall low in the arch, the throat black over it (top at %.2f m)" % heap_top)
	# In a bank (the hills' bear cave): its top drawn over every throat cell,
	# which draws no ground (the mouth audit: from behind the hill, the
	# throat's black showed through a hole in its top).
	var hills := Level.load_level("hills")
	_rig.rebuild(hills["terrain"], hills["centre"])
	var open_over: Array[Vector2i] = []
	var throat_count := 0
	for cue: Dictionary in hills["terrain"].get("link_cues", []):
		if cue["cue"] == "cave":
			var found := _throat_open_over(cue, Client3D.MOUTH_ARCH)
			throat_count += int(found[0])
			open_over.append_array(found[1])
	_check(throat_count > 0 and open_over.is_empty(),
			"in a bank (the hills' bear cave), its top over every throat cell (%d cells, open: %s)" % [throat_count, open_over])
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## The throat cells of the hills' cave mouth at `cue` (its own, by its tile
## and facing, `arch` wide) and those its body's top leaves open over its
## vault, `arch`.y high: [count, open cells]. A cell without a body is open.
func _throat_open_over(cue: Dictionary, arch: Vector2) -> Array:
	var at: Vector2i = cue["tile"]
	var open: Array[Vector2i] = []
	var holder: Node3D = _rig._room.get_node_or_null("Mouth_%d_%d" % [at.x, at.y])
	var body: MeshInstance3D = holder.get_node_or_null("Body") if holder != null else null
	if body == null:
		open.append(at)
		return [0, open]
	var points: PackedVector3Array = body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var to_frame := holder.transform.affine_inverse()
	# Its own throat's cells only: the hills' bear cave and mine mouth each
	# have one, under their own bodies.
	var ahead: Vector2i = cue["facing"]
	var across := Vector2i(-ahead.y, ahead.x)
	var count := 0
	for cell: Vector2i in _rig._throat_cells():
		var deep := (cell - at).x * ahead.x + (cell - at).y * ahead.y
		var side := (cell - at).x * across.x + (cell - at).y * across.y
		if deep < 1 or deep > ceili(Client3D.MOUTH_THROAT) or absi(side) > ceili(arch.x * 0.5 - 0.5):
			continue
		count += 1
		var over := to_frame * Vector3(cell.x, 0.0, cell.y)
		var covered := false
		for i in range(0, points.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(over.x, 60.0, over.z), Vector3.DOWN, points[i], points[i + 1], points[i + 2])
			if hit != null and (hit as Vector3).y > arch.y + 0.1:  # Over the throat's own vault.
				covered = true
				break
		if not covered:
			open.append(cell)
	return [count, open]


## A thicket mouth (798 amended, maps' boar lair): a mound of art-kit's
## bramble bushes behind and beside the link, the link its gap, lower at
## the front and thinner at the sides; a low tangle in the gap when closed.
func _test_thicket_mouth() -> void:
	print("
== thicket mouth: a bramble mound, the link its gap ==")
	if not ArtKit.has("wall.thicket.end"):
		_check(false, "art-kit's wall.thicket.end")
		return
	var sample := Level.load_level("sample")
	var terrain: Dictionary = sample["terrain"].duplicate()
	terrain["outdoor"] = true
	var floor_cells: Array = terrain["floor"]
	var at := Vector2i(-1, -1)
	for cell: Vector2i in floor_cells:
		if floor_cells.has(cell + Vector2i(-2, -2)) and floor_cells.has(cell + Vector2i(2, -2)) and floor_cells.has(cell + Vector2i(0, 2)):
			at = cell
			break
	if at.x < 0:
		_check(false, "the sample has room for a mound")
		return
	var ahead := Vector2i(0, -1)
	for closed in [false, true]:
		terrain["link_cues"] = [{"tile": at, "cue": "thicket", "facing": ahead, "variant": 1, "closed": closed}]
		_rig.rebuild(terrain, sample["centre"])
		var holder: Node3D = _rig._room.get_node_or_null("Thicket_%d_%d" % [at.x, at.y])
		var mound := _rig._thicket_cells()
		var bushes := 0
		var stray := 0
		var front := 0.0
		var back := 0.0
		var per_cell: Dictionary[Vector2i, int] = {}
		for bush: Node3D in (holder.get_children() if holder != null else []):
			if bush.name == "Tangle" or bush.name == "Den":
				continue
			bushes += 1
			var cell := Vector2i(roundi(bush.position.x), roundi(bush.position.z))
			if not mound.has(cell):
				stray += 1
				continue
			per_cell[cell] = int(per_cell.get(cell, 0)) + 1
			var top := -INF
			for mesh: MeshInstance3D in bush.find_children("*", "MeshInstance3D", true, false):
				var box := holder.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
				top = maxf(top, box.end.y - bush.position.y)
			if mound[cell] == 0:
				front = maxf(front, top)
			else:
				back = maxf(back, top)
		var tangle := holder.get_node_or_null("Tangle") if holder != null else null
		if not closed:
			var sides: int = per_cell.get(at + Vector2i(2, -1), 0) + per_cell.get(at + Vector2i(-2, -1), 0)
			var inner: int = per_cell.get(at + Vector2i(0, -1), 0) + per_cell.get(at + Vector2i(0, -2), 0)
			var bare := 0
			for cell: Vector2i in mound:
				var near := false
				for bush: Node3D in holder.get_children() if holder != null else []:
					near = near or bush.name != "Den" and Vector2(bush.position.x, bush.position.z).distance_to(Vector2(cell)) < 1.0
				if not near:
					bare += 1
			_check(holder != null and mound.size() == 14 and not mound.has(at) and bushes > 14 and stray == 0 and bare == 0,
					"a mound of bushes over its 14 cells, none on the link or the pad (%d bushes, %d stray, %d cells bare)" % [bushes, stray, bare])
			_check(front > 0.9 and front < back and back > 1.5 and back < 2.3 and sides < inner,
					"low at the front, 1.5-2 m behind, thinner at its sides (front %.2f m, back %.2f m, %d at the sides, %d in the middle)" % [front, back, sides, inner])
			_check(tangle == null, "open: its gap clear")
			var wood := 0
			for cell: Vector2i in mound:
				if _rig._stood.has(cell) and (_rig._room.has_node("Tree_%d_%d" % [cell.x, cell.y]) or _rig._room.has_node("Sapling_%d_%d" % [cell.x, cell.y])):
					wood += 1
			_check(mound.keys().all(func(cell: Vector2i) -> bool: return _rig._stood.has(cell)) and wood == 0,
					"none of the wood's trees on its mound (%d)" % wood)
			var den: MeshInstance3D = holder.get_node_or_null("Den") if holder != null else null
			var dark := den != null and den.mesh != null and (den.material_override as StandardMaterial3D).albedo_color.get_luminance() < 0.05
			var den_cell := Vector2i(-1, -1)
			if dark:
				var box := den.mesh.get_aabb()
				den_cell = Vector2i(roundi(box.get_center().x), roundi(box.get_center().z))
			_check(dark and den_cell == at + ahead, "behind its gap the way in, dark (%s)" % den_cell)
		else:
			_check(tangle != null and Vector2i(roundi(tangle.position.x), roundi(tangle.position.z)) == at,
					"closed: a low tangle in its gap")
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## 798 amended (2): a den mouth ("den", maps' old grey's den): a low earth
## bank over the boar's footprint, a hole into it at the link cell's far
## edge going black, a tilted shelf of rock over it, art-kit's root lip as
## its top and the signs before it; the wood's trees kept off the bank.
## A mine's mouth (cue "mine": Hollowfell's door in the hills, the
## coordinator from Jeff's play): the cave mouth's hill, its arch squared and
## taller, open to the black; art-kit's timber frame in its face, rails out to
## a buffer, the stair down inside the dark, a brazier lit at the door.
func _test_mine_mouth() -> void:
	print("
== mine mouth: a timbered adit in a hill of rock, the dark beyond ==")
	_check("mine" in Level.CUES and WorldMapPanel.end_mark({"cue": "mine"}) == "mouth" and "mine" in Minimap.GLYPH_CUES,
			"a link cue, marked on the maps as a way down")
	var sample := Level.load_level("sample")
	var terrain: Dictionary = sample["terrain"].duplicate()
	terrain["outdoor"] = true
	var floor_cells: Array = terrain["floor"]
	var at := Vector2i(-1, -1)
	for cell: Vector2i in floor_cells:
		if floor_cells.has(cell + Vector2i(0, -5)) and floor_cells.has(cell + Vector2i(3, -5)) and floor_cells.has(cell + Vector2i(-3, -5)) 				and floor_cells.has(cell + Vector2i(0, 3)):
			at = cell
			break
	_check(at.x >= 0, "the sample has room for a hill (%s)" % at)
	if at.x < 0:
		return
	terrain["link_cues"] = [{"tile": at, "cue": "mine", "facing": Vector2i(0, -1), "variant": 1}]
	_rig.rebuild(terrain, sample["centre"])
	var holder: Node3D = _rig._room.get_node_or_null("Mouth_%d_%d" % [at.x, at.y])
	var body: MeshInstance3D = holder.get_node_or_null("Body") if holder != null else null
	var dress: Node3D = holder.get_node_or_null("Mine") if holder != null else null
	_check(body != null and body.mesh != null and dress != null, "drawn on the link's cell, dressed")
	if body == null or body.mesh == null or dress == null:
		_rig.rebuild(_main._terrain, Vector2i.ZERO)
		return
	var points: PackedVector3Array = body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var shades: PackedColorArray = body.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var first_hit := func(from: Vector3) -> Array:
		var near := INF
		var met := Color.WHITE
		for i in range(0, points.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(from, Vector3(0, 0, 1), points[i], points[i + 1], points[i + 2])
			if hit != null and (hit as Vector3).z < near:
				near = (hit as Vector3).z
				met = shades[i]
		return [near, met]
	# Square: open at its shoulders, where a cave's round arch is rock.
	var deep := 0.5 + Client3D.MOUTH_THROAT - 0.1
	var middle: Array = first_hit.call(Vector3(0.0, 1.5, -2.0))
	var shoulder: Array = first_hit.call(Vector3(Client3D.MINE_ARCH.x * 0.4, Client3D.MINE_ARCH.y * 0.8, -2.0))
	_check(middle[0] > deep and (middle[1] as Color).get_luminance() < 0.01 and shoulder[0] > 1.0,
			"its arch open and squared, the throat going black (met at %.2f m; at its shoulder %.2f m)" % [middle[0], shoulder[0]])
	var slots := {}
	var stair_z := -INF
	for piece: Node in dress.get_children():
		var slot := str(piece.get_meta("slot", ""))
		slots[slot] = int(slots.get(slot, 0)) + 1
		if slot == "building.stair_down":
			stair_z = (piece as Node3D).position.z
	var lit := dress.find_children("*", "OmniLight3D", true, false).size()
	_check(int(slots.get(Client3D.MINE_FRAME, 0)) == 2 and int(slots.get("mine.track", 0)) >= 4 and int(slots.get("mine.track_end", 0)) == 1
			and int(slots.get("prop.mine_cart", 0)) == 1 and int(slots.get("mine.spoil", 0)) == 1 and stair_z > 0.5 and lit >= 1,
			"timbered, railed out to a buffer and a cart, the spoil heap beside it (798 amended (5)), the stair down in the dark, a fire at the door (%s; the stair %.1f m in, %d light)" % [slots, stair_z, lit])
	# In the hills (Hollowfell's door, in maps' bank): its own top over every
	# throat cell, which draws no ground (as the bear cave's: else its black
	# would show through from behind the hill).
	var hills := Level.load_level("hills")
	_rig.rebuild(hills["terrain"], hills["centre"])
	var mines := 0
	var throat_count := 0
	var open_over: Array[Vector2i] = []
	for cue: Dictionary in hills["terrain"].get("link_cues", []):
		if cue["cue"] == "mine":
			mines += 1
			var found := _throat_open_over(cue, Client3D.MINE_ARCH)
			throat_count += int(found[0])
			open_over.append_array(found[1])
	_check(mines == 1 and throat_count > 0 and open_over.is_empty(),
			"in the hills, its top over every throat cell (%d cells, open: %s)" % [throat_count, open_over])
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## A rock shelter (798 amended (4): a place's "opens", the hills' hill cave):
## an overhang you walk under, its rock shaded to a rock back, never black,
## its roof falling toward the back, a lip jutting past its face; dressed as
## a refuge.
func _test_shelter() -> void:
	print("
== rock shelter: an overhang you walk under, a refuge's things inside ==")
	var warnings: Array[String] = []
	var places := Level.places_from({"places": {"cave": {"at": [4, 4], "kind": "refuge", "where": "hills", "name": "a cave", "opens": [1, 0]},
			"odd": {"at": [8, 8], "opens": [1, 1]}}}, warnings)
	var shelters := Level.shelters_of(places)
	_check(shelters.size() == 1 and shelters[0]["at"] == Vector2i(4, 4) and shelters[0]["opens"] == Vector2i(1, 0)
			and warnings.any(func(w: String) -> bool: return "odd opens" in w),
			"a place's \"opens\" a shelter; a slant one warned and left out (%s)" % [shelters])
	var sample := Level.load_level("sample")
	var terrain: Dictionary = sample["terrain"].duplicate()
	terrain["outdoor"] = true
	var floor_cells: Array = terrain["floor"]
	var at := Vector2i(-1, -1)
	for cell: Vector2i in floor_cells:
		if floor_cells.has(cell + Vector2i(0, -5)) and floor_cells.has(cell + Vector2i(3, -5)) and floor_cells.has(cell + Vector2i(-3, -5)):
			at = cell
			break
	_check(at.x >= 0, "the sample has room for a hill (%s)" % at)
	if at.x < 0:
		return
	terrain["link_cues"] = []
	terrain["shelters"] = [{"at": at, "opens": Vector2i(0, 1)}]
	_rig.rebuild(terrain, sample["centre"])
	var holder: Node3D = _rig._room.get_node_or_null("Shelter_%d_%d" % [at.x, at.y])
	var body: MeshInstance3D = holder.get_node_or_null("Body") if holder != null else null
	var dress: Node3D = holder.get_node_or_null("Refuge") if holder != null else null
	_check(body != null and body.mesh != null and dress != null and _rig._mouth_cells().has(at + Vector2i(0, -1)),
			"drawn behind the place's cell, its hill's cells kept, dressed")
	if body == null or body.mesh == null or dress == null:
		_rig.rebuild(_main._terrain, Vector2i.ZERO)
		return
	var points: PackedVector3Array = body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var shades: PackedColorArray = body.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var cast := func(from: Vector3, way: Vector3) -> Array:
		var near := INF
		var met := Color.WHITE
		for i in range(0, points.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(from, way, points[i], points[i + 1], points[i + 2])
			if hit != null and from.distance_to(hit) < near:
				near = from.distance_to(hit)
				met = shades[i]
		return [near, met]
	var face := 0.5
	var back: Array = cast.call(Vector3(0.0, 0.5, -2.0), Vector3(0, 0, 1))
	var lip_high: float = cast.call(Vector3(0.0, 0.05, face + 0.3), Vector3.UP)[0]
	var back_high: float = cast.call(Vector3(0.0, 0.05, face + Client3D.SHELTER_DEEP - 0.3), Vector3.UP)[0]
	var jut := INF
	for p in points:
		if p.y > Client3D.SHELTER_ARCH.y * 0.8:
			jut = minf(jut, p.z)
	_check(back[0] > 2.0 + face + Client3D.SHELTER_DEEP - 0.2 and (back[1] as Color).get_luminance() > 0.02,
			"open to a rock back, not black (met at %.2f m, %.3f)" % [back[0], (back[1] as Color).get_luminance()])
	_check(lip_high > 1.6 and back_high < lip_high * 0.8 and Client3D.SHELTER_ARCH.x > Client3D.SHELTER_ARCH.y * 2.0 and jut < face - 0.5,
			"wider than tall, its roof %.2f m at the lip and %.2f m at the back, its lip %.2f m past the face" % [lip_high, back_high, face - jut])
	var slots := {}
	for piece: Node in dress.get_children():
		var slot := str(piece.get_meta("slot", ""))
		slots[slot] = int(slots.get(slot, 0)) + 1
	_check(int(slots.get("prop.campfire_cold", 0)) == 1 and int(slots.get("prop.bedroll", 0)) == 2,
			"a cold fire ring and two old bedrolls under it (%s)" % [slots])
	# 825 ("hill cave rest"): its ring drawn lit while a player's fire burns
	# on its cell, cold again when it goes out; its crackle with the camps'.
	var ring := at + Vector2i(0, -1)
	var cold: Node3D = _rig._hearth_rings.get(ring)
	var zone_name: String = World.zone.name
	var was: Variant = World.hearths_lit.get(zone_name)
	World.hearths_lit[zone_name] = {ring: World.tick + 600}
	World.hearths_changed.emit(zone_name)
	var lit: Node3D = dress.get_node_or_null("Lit_%d_%d" % [ring.x, ring.y])
	var lights: Array = lit.find_children("*", "OmniLight3D", true, false) if lit != null else []
	var flickers := not lights.is_empty() and _rig._fire_lights.any(func(each: Array) -> bool: return each[0] == lights[0])
	# Low over the fire and soft, so the lip is lit underneath, not banded.
	var low := not lights.is_empty() and (lights[0] as OmniLight3D).position.y <= 0.8 and (lights[0] as OmniLight3D).omni_range <= 5.0
	var lit_slot := ""
	for piece: Node in (lit.get_children() if lit != null else []):
		lit_slot = str(piece.get_meta("slot", lit_slot))
	_check(_rig._hearth_rings.size() == 1 and cold != null and lit != null and not cold.visible and lit_slot == Client3D.HEARTH_LIT
			and flickers and low and _rig.campfire_cells().has(ring),
			"lit: a burning ring for the cold one, its light flickering, its crackle heard (%s on %s, %d light)" % [lit_slot, ring, lights.size()])
	World.hearths_lit.erase(zone_name)
	World.hearths_changed.emit(zone_name)
	var still_flickers := not lights.is_empty() and _rig._fire_lights.any(func(each: Array) -> bool: return each[0] == lights[0])
	_check(cold != null and cold.visible and dress.get_node_or_null("Lit_%d_%d" % [ring.x, ring.y]) == null
			and not still_flickers and not _rig.campfire_cells().has(ring),
			"gone out: the cold ring again, no light, no crackle")
	if was != null:
		World.hearths_lit[zone_name] = was
	# The hills: every hearth (a place's "fire_ring") on the ring its shelter draws.
	var hills := Level.load_level("hills")
	_rig.rebuild(hills["terrain"], hills["centre"])
	var rings: Array = hills["terrain"].get("fire_rings", [])
	var undrawn := rings.filter(func(cell: Vector2i) -> bool: return not _rig._hearth_rings.has(cell))
	_check(undrawn.is_empty(), "the hills' hearths each on a shelter's drawn ring (%s; drawn %s)" % [rings, _rig._hearth_rings.keys()])
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


func _test_den_mouth() -> void:
	print("
== den mouth: a low hole under a shelf, roots over its lip ==")
	var sample := Level.load_level("sample")
	var terrain: Dictionary = sample["terrain"].duplicate()
	terrain["outdoor"] = true
	var floor_cells: Array = terrain["floor"]
	var at := Vector2i(-1, -1)
	for cell: Vector2i in floor_cells:
		if floor_cells.has(cell + Vector2i(-2, -2)) and floor_cells.has(cell + Vector2i(2, -2)) and floor_cells.has(cell + Vector2i(0, 2)):
			at = cell
			break
	if at.x < 0:
		_check(false, "the sample has room for a den")
		return
	var ahead := Vector2i(0, -1)
	for closed in [false, true]:
		terrain["link_cues"] = [{"tile": at, "cue": "den", "facing": ahead, "variant": 1, "closed": closed}]
		_rig.rebuild(terrain, sample["centre"])
		var holder: Node3D = _rig._room.get_node_or_null("DenMouth_%d_%d" % [at.x, at.y])
		var bank: MeshInstance3D = holder.get_node_or_null("Bank") if holder != null else null
		var throat: MeshInstance3D = holder.get_node_or_null("Throat") if holder != null else null
		if bank == null or bank.mesh == null or throat == null:
			_check(false, "drawn on the link's cell: its bank and throat")
			_rig.rebuild(_main._terrain, Vector2i.ZERO)
			return
		if closed:
			_check(holder.get_node_or_null("Stopped") != null and holder.get_node("Stopped").get_child_count() > 0,
					"closed: stones in its hole")
			continue
		var points: PackedVector3Array = bank.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		# In its frame: +z into the bank.
		var top := -INF
		var out := 0.0
		for p in points:
			top = maxf(top, p.y)
			out = maxf(out, maxf(absf(p.x) - Client3D.DEN_MOUND.x * 0.5, maxf(-0.5 - p.z, p.z - 2.5)))
		var into := holder.transform.basis * Vector3(0, 0, 1)
		_check(top > Client3D.DEN_HOLE.y + 0.4 and top < 2.9 and out < 0.15 and Vector2(into.x, into.z).dot(Vector2(ahead)) > 0.99,
				"low, a bank over its cells, the way it faces (%.2f m high, %.2f m out, into %s)" % [top, out, into])
		# Looking in at the hole's middle, knee high: past the face, the
		# throat's black end, nothing of the bank across the hole.
		var dark: PackedVector3Array = throat.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var from := Vector3(0.0, 0.4, -2.0)
		var near_bank := INF
		for i in range(0, points.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(from, Vector3(0, 0, 1), points[i], points[i + 1], points[i + 2])
			if hit != null:
				near_bank = minf(near_bank, (hit as Vector3).z)
		var near_dark := INF
		for i in range(0, dark.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(from, Vector3(0, 0, 1), dark[i], dark[i + 1], dark[i + 2])
			if hit != null:
				near_dark = minf(near_dark, (hit as Vector3).z)
		_check(near_dark > 0.5 and near_dark < 0.5 + Client3D.DEN_VEIL + 0.05 and near_dark < near_bank,
				"its hole open, black just past the roots (the dark at %.2f m, the bank at %.2f m)" % [near_dark, near_bank])
		# Over the hole, the shelf: rock above its top, jutting past the face.
		var over := INF
		var jut := INF
		for p in points:
			if absf(p.x) < Client3D.DEN_HOLE.x * 0.5 and p.y > Client3D.DEN_HOLE.y:
				jut = minf(jut, p.z)
		var up_from := Vector3(0.0, 0.5, 0.9)
		for i in range(0, points.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(up_from, Vector3.UP, points[i], points[i + 1], points[i + 2])
			if hit != null:
				over = minf(over, (hit as Vector3).y)
		_check(jut < 0.5 - 0.1 and over > Client3D.DEN_HOLE.y - 0.3 and over < 2.7,
				"a shelf over it, jutting past its face (its front at %.2f m, %.2f m over the throat)" % [jut, over])
		var lip: Node3D = holder.get_node_or_null("RootLip")
		var signs := 0
		for child: Node in holder.get_children():
			if str(child.name).begins_with("Sign_"):
				signs += 1
		_check(lip != null and absf(lip.rotation.y) > 3.0 and signs == Client3D.DEN_SIGNS.size(),
				"art-kit's root lip turned out over it, its fur and rakes before it (%d signs)" % signs)
		var cells := _rig._den_cells()
		var grown := 0
		for child: Node in _rig._room.get_children():
			if child is Node3D and (str(child.name).begins_with("Tree_") or str(child.name).begins_with("Sapling_")):
				var spot := Vector2i(roundi((child as Node3D).position.x), roundi((child as Node3D).position.z))
				if cells.has(spot):
					grown += 1
		var all_stood := true
		for cell: Vector2i in cells:
			all_stood = all_stood and _rig._stood.has(cell)
		_check(cells.size() == 14 and not cells.has(at) and all_stood and grown == 0,
				"its 14 cells kept from the wood's trees (%d cells, %d trees)" % [cells.size(), grown])
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## levels/sample's stream (decision 505, terrain's side): the ford and the
## water under the bridge in the water mask with the stream's (a ford's
## shallow), the flow down the path and none on still water, the bed under
## the bridge at the stream's level, no scatter on the ford, and the bridge's
## deck, rails and ends.
func _test_streams() -> void:
	print("\n== streams: fords and bridged water in the mask, the flow down the path, the bridge's pieces ==")
	var sample := Level.load_level("sample")
	var terrain: Dictionary = sample["terrain"]
	var fords: Array = terrain.get("fords", [])
	var bridged: Array = terrain.get("bridged", [])
	var streams: Array = terrain.get("streams", [])
	_check(not fords.is_empty() and not bridged.is_empty() and not streams.is_empty(),
			"the sample has a stream, a ford and a bridge (%d, %d, %d)" % [streams.size(), fords.size(), bridged.size()])
	if fords.is_empty() or bridged.is_empty() or streams.is_empty():
		return
	_rig.rebuild(terrain, sample["centre"])
	var mask := _rig._water_mask.get_image()
	var texel := func(cell: Vector2i) -> Color: return mask.get_pixelv(cell - _rig._mask_origin)
	var ford: Vector2i = fords[0]
	var under: Vector2i = bridged[0]
	var plain: Vector2i = terrain["water"].filter(func(cell: Vector2i) -> bool: return not fords.has(cell))[0]
	_check(texel.call(ford).r > 0.9 and texel.call(ford).b > 0.9 and texel.call(under).r > 0.9 and texel.call(under).b < 0.1
			and texel.call(plain).r > 0.9 and texel.call(plain).b < 0.1,
			"the mask: the ford water and shallow, the bridge's cell water, the stream's water not shallow")
	# Its water a ribbon along its path (decision 557): over every one of
	# its own cells' middles, running down the path, the cells marked its
	# own in the mask's a and left out of the bodies.
	var path: Array = streams[0]["path"]
	var down := Vector2(path[-1] - path[0]).normalized()
	_check(_rig._stream_ribbons.size() == streams.size(), "a ribbon a stream (%d for %d)" % [_rig._stream_ribbons.size(), streams.size()])
	var report := _ribbon_report(_rig, down)
	_check(report["uncovered"].is_empty() and report["against"] == 0,
			"the ribbon over each of its cells' middles (uncovered: %s), running down the path (%d points against it)" % [report["uncovered"].slice(0, 3), report["against"]])
	var in_bodies := []
	for body: MeshInstance3D in _rig._water_bodies:
		for point: Vector3 in (body.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var corner := Vector2i(roundi(point.x + 0.5), roundi(point.z + 0.5))
			var round_it := [corner - Vector2i.ONE, corner - Vector2i(0, 1), corner - Vector2i(1, 0), corner]
			if round_it.all(func(c: Vector2i) -> bool: return _rig._stream_cells.has(c)):
				in_bodies.append(corner)
	var running: Vector2i = path.filter(func(cell: Vector2i) -> bool: return not fords.has(cell) and not bridged.has(cell))[0]
	_check(texel.call(ford).a > 0.9 and texel.call(running).a > 0.9 and texel.call(plain).a < 0.1 and in_bodies.is_empty(),
			"the stream's cells its own in the mask's a (a pond's not), none drawn by a body (%s)" % [in_bodies.slice(0, 3)])
	var bed := _rig._grounds.get(under, -1) as int
	_check(bed >= _rig._ground_floor_end and bed < _rig._ground_water_end and _rig._bed_levels.get(under, -1) == int(terrain["heights"].get(plain, 0)),
			"under the bridge the ground is the stream's bed, at its level")
	var on_ford := false
	for chunk: Vector2i in _rig._scatter_chunks:
		for kind: String in _rig._scatter_plan(chunk):
			for item: Array in _rig._scatter_plan(chunk)[kind]:
				on_ford = on_ford or item[0] == ford
	_check(not on_ford, "no scatter on the ford")
	var bridge_entry: Dictionary = terrain["buildings"].filter(func(b: Dictionary) -> bool: return str(b["slot"]) in Level.SPANS_WATER)[0]
	var rect: Rect2i = bridge_entry["rect"]
	var bridge := _rig._room.get_node_or_null("Bridge_%d_%d" % [rect.position.x, rect.position.y]) as Node3D
	var counts := {"deck": 0, "rail": 0, "end": 0}
	if bridge != null:
		for many: MultiMeshInstance3D in bridge.find_children("*", "MultiMeshInstance3D", false, false):
			# Named piece_variant_mesh: a piece of several meshes counted once.
			var kind := String(many.name).get_slice("_", 0)
			if String(many.name).get_slice("_", 2) == "0" and counts.has(kind):
				counts[kind] += many.multimesh.instance_count
	var facing: Vector2i = bridge_entry["facing"]
	var length := rect.size.x if facing.x != 0 else rect.size.y
	var width := rect.size.y if facing.x != 0 else rect.size.x
	_check(bridge != null and counts["deck"] == length * width and counts["rail"] == 2 * length and counts["end"] == 2 * width,
			"the bridge: a deck a cell, a rail along each long side, an end at each end (%s)" % [counts])
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## A curve that passes a cell twice (maps' 745: the wilds' outline round
## the hills' glimpse and back along its lane), each pass's nearest sample
## searched: a long thin closed outline, its two long sides about 80
## samples apart along it, the cell midway between them nearest the top
## side, yet a point in it (0.15 off the bottom side, inside the cell)
## reads the bottom's distance, not the top's; and the same by the lane's
## end, where the curve round the end stays within reach of the cell, so
## both sides are one unbroken run, their nearest about 30 samples apart.
func _test_curve_passes() -> void:
	print("\n== a curve by a cell twice: each pass searched ==")
	for case: Array in [[0.5, Vector2i(20, 0), "two runs"], [0.1, Vector2i(39, 0), "one run round the lane's end"]]:
		var points := PackedVector2Array()
		var corners: Array[Vector2] = [Vector2(0, -0.6), Vector2(40, -0.6), Vector2(40, 0.5), Vector2(0, 0.5)]
		for side in 4:
			var from := corners[side]
			var to := corners[(side + 1) % 4]
			var steps := maxi(1, ceili(from.distance_to(to) / float(case[0])))
			for i in steps:
				points.append(from.lerp(to, i / float(steps)))
		var widths := PackedFloat32Array()
		widths.resize(points.size())
		var curve := {"points": points, "widths": widths}
		var kept := [_rig._edge_curves.duplicate(), _rig._edge_near_sample.duplicate(), _rig._edge_near_also.duplicate(), _rig._edge_kept.duplicate()]
		_rig._edge_curves.assign([{"curve": curve}])
		_rig._edge_near_sample.clear()
		_rig._edge_near_also.clear()
		_rig._edge_kept.clear()
		_rig._stamp_near(curve, true, 0, _rig._edge_near_sample, _rig._edge_near_also)
		var cell: Vector2i = case[1]
		var nearest: Vector2i = _rig._edge_near_sample.get(cell, Vector2i(-1, -1))
		var reads := absf(_rig._edge_signed(Vector2(cell.x, -0.45)))
		_check(nearest.y >= 0 and points[nearest.y].y > 0.0 and is_equal_approx(snappedf(reads, 0.001), 0.15),
				"%s: the cell's nearest sample on the far side (%s), yet a point of it beside the near side reads 0.15 (%.3f)" % [case[2], points[nearest.y] if nearest.y >= 0 else Vector2.INF, reads])
		_rig._edge_curves.assign(kept[0])
		_rig._edge_near_sample.assign(kept[1])
		_rig._edge_near_also.assign(kept[2])
		_rig._edge_kept.assign(kept[3])


## The water's edge unsquared (decision 553): the shore field rounds a
## pond's corners (a lone cell a disc) yet keeps to its cells, the hills'
## shore cells drawn finer and meeting the ground round them, a level
## without relief drawn whole.
## The forest's edge drawn from curves (decision 575): traced round the
## cells the forest grows round, never past EDGE_BOUND of their edge; the
## land's side and the forest's by the curve agreeing with the cells away
## from it; the ground's field a half on the curve; the edge's trees on the
## forest's cells and its side; the scatter by it on its own side.
func _test_forest_edge() -> void:
	print("\n== the forest's edge: a curve traced round the land, its trees and scatter by it ==")
	for name: String in ["hills", "wilds"]:
		var level := Level.load_level(name)
		_rig.rebuild(level["terrain"], level["centre"])
		var wooded: Dictionary = _rig._wooded
		# How far a point is from the cells' edge (wooded beside not).
		var off_edge := func(at: Vector2) -> float:
			var nearest := INF
			var cell := Vector2i(roundi(at.x), roundi(at.y))
			for y in range(-1, 2):
				for x in range(-1, 2):
					var here := cell + Vector2i(x, y)
					for side: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
						if wooded.has(here) == wooded.has(here + side):
							continue
						var middle := Vector2(here) + Vector2(side) * 0.5
						var along := Vector2(side.y, side.x) * 0.5
						nearest = minf(nearest, at.distance_to(Geometry2D.get_closest_point_to_segment(at, middle - along, middle + along)))
			return nearest
		var astray := []
		var samples := 0
		for edge: Dictionary in _rig._edge_curves:
			for point: Vector2 in edge["curve"]["points"]:
				samples += 1
				if off_edge.call(point) > Client3D.EDGE_BOUND:
					astray.append(point)
		_check(not _rig._edge_curves.is_empty() and astray.is_empty(),
				"%s: %d edge curves, every point within %.2f of the cells' edge (%d points; astray: %s)" % [name, _rig._edge_curves.size(), Client3D.EDGE_BOUND, samples, astray.slice(0, 4)])
		var wrong := []
		var field_off := []
		for cell: Vector2i in _rig._edge_near_sample:
			var into := _rig._edge_signed(Vector2(cell))
			if is_nan(into) or absf(into) < Client3D.EDGE_BOUND + 0.05:
				continue
			if (into > 0.0) == wooded.has(cell):
				wrong.append(cell)
		for edge: Dictionary in _rig._edge_curves:
			var points: PackedVector2Array = edge["curve"]["points"]
			for k in range(0, points.size(), 16):
				var into := _rig._edge_signed(points[k])
				if is_nan(into) or absf(into) > 0.05:
					field_off.append(points[k])
		_check(wrong.is_empty() and field_off.is_empty(),
				"%s: the land's side and the forest's by the curve as the cells have them away from it (wrong: %s), nought on the curve (off: %s)" % [name, wrong.slice(0, 4), field_off.slice(0, 4)])
		var on_land := []
		for cell: Vector2i in _rig._trees:
			var tree: Node3D = _rig._trees[cell]
			var at := Vector2(tree.position.x, tree.position.z)
			var into := _rig._edge_signed(at)
			if _rig._land.has(Vector2i(roundi(at.x), roundi(at.y))) or not is_nan(into) and into < 0.0:
				on_land.append(at)
		_check(on_land.is_empty(), "%s: every tree on the forest's cells and its side of the edge (%d trees; on the land: %s)" % [name, _rig._trees.size(), on_land.slice(0, 4)])
		var astray_scatter := 0
		var by_edge := 0
		for chunk: Vector2i in _rig._scatter_chunks:
			var plan := _rig._scatter_plan(chunk)
			for kind: String in plan:
				for item: Array in plan[kind]:
					var into := _rig._edge_signed(item[1])
					if is_nan(into) or not _rig._edge_near_sample.has(item[0]):
						continue
					by_edge += 1
					if (into > 0.0) != bool(item[3]) or kind == "root" and not item[3] and into < -Client3D.EDGE_ROOTS:
						astray_scatter += 1
		_check(by_edge > 0 and astray_scatter == 0,
				"%s: the scatter by the edge on its own side of the curve, the roots within %.1f of it (%d by it; astray: %d)" % [name, Client3D.EDGE_ROOTS, by_edge, astray_scatter])
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## No hole in the ground (decision 753; Jeff on v0.1.194: "in between the
## trees a hole in the map"): on every outdoor level with a relief, every
## land cell and every forest cell out to FOREST_REACH has the ground or
## the forest band under it; where the band meets the ground their shared
## corners stand within BAND_SEAM; and every stand stands on the band, not
## at 0 under it.
func _test_forest_floor_whole() -> void:
	print("\n== no hole in the ground: the land and its forest floored whole, the band on the relief ==")
	const BAND_SEAM := 0.05
	var tried := 0
	for name: String in Level.names():
		var level := Level.load_level(name)
		var terrain: Dictionary = level["terrain"]
		if not bool(terrain.get("outdoor", false)) or not terrain.has("relief"):
			continue
		tried += 1
		_rig.rebuild(terrain, level["centre"])
		var covered: Dictionary = {}
		for cell: Vector2i in _rig._ground_cells:
			covered[cell] = true
		# A cave mouth's throat (798) is floored by its hill and throat.
		covered.merge(_rig._throat_cells())
		var bare: Array[Vector2i] = []
		for cell: Vector2i in _rig._land:
			if not covered.has(cell):
				bare.append(cell)
		for cell: Vector2i in _rig._forest_distance:
			if _rig._forest_distance[cell] >= 1 and not _rig._wooded.has(cell) and not covered.has(cell) and not _rig._band_cells.has(cell):
				bare.append(cell)
		_check(not _rig._band_cells.is_empty() and bare.is_empty(),
				"%s: every land cell and forest cell out to %d floored (%d ground, %d band; bare: %s)" % [name, Client3D.FOREST_REACH, covered.size(), _rig._band_cells.size(), bare.slice(0, 4)])
		# Where the band meets the ground: at each shared corner, the band on
		# the ground's lowest corner there (a higher one is the ground's own
		# cliff); each band corner one vertex, so no slit between its quads.
		# Drawn: the band's meshes hold its cells' two triangles each.
		var vertices := 0
		for band: MeshInstance3D in _rig._room.find_children("ForestBand_*", "MeshInstance3D", false, false):
			if band.mesh != null and (band.mesh as ArrayMesh).get_surface_count() > 0:
				vertices += ((band.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		_check(vertices == _rig._band_cells.size() * 6, "%s: the band drawn, two triangles a cell (%d vertices for %d cells)" % [name, vertices, _rig._band_cells.size()])
		var steps: Array = []
		var met := 0
		var rise := 0.0
		var rise_at := Vector2i.ZERO
		for cell: Vector2i in _rig._band_cells:
			for c in 4:
				var vertex: Vector2i = cell + Client3D.GROUND_CORNERS[c]
				var band: float = _rig._band_vertices.get(vertex, NAN)
				var low := INF
				var high := -INF
				for k in 4:
					var other: Vector2i = vertex - Client3D.GROUND_CORNERS[k]
					if covered.has(other):
						var drawn: float = _rig._corner_heights(other)[k]
						low = minf(low, drawn)
						high = maxf(high, drawn)
				if is_nan(band) or low < INF and absf(band - low) > BAND_SEAM:
					steps.append([vertex, band, low])
				elif low < INF:
					met += 1
					if high - band > rise:
						rise = high - band
						rise_at = vertex
		_check(met > 0 and steps.is_empty(), "%s: the band on the ground's corner wherever they meet (%d corners, the ground's own steps above it up to %.2f m at %s; off: %s)" % [name, met, rise, rise_at, steps.slice(0, 3)])
		# A glimpse's sides (327 amended draws it flat at its arrival's level,
		# raised to us): our ground's corners touching it on its height.
		var off_glimpse: Array = []
		var glimpse_corners := 0
		for plan: Dictionary in _rig._glimpse_plans:
			for g: Vector2i in plan["cells"]:
				for c in 4:
					var vertex: Vector2i = g + Client3D.GROUND_CORNERS[c]
					var low := INF
					for k in 4:
						var beside: Vector2i = vertex - Client3D.GROUND_CORNERS[k]
						if _rig._glimpse_ground.has(beside):
							low = minf(low, _rig._glimpse_ground[beside])
					for k in 4:
						var ours: Vector2i = vertex - Client3D.GROUND_CORNERS[k]
						if not covered.has(ours) or _rig._glimpse_ground.has(ours):
							continue
						glimpse_corners += 1
						var drawn: float = _rig._corner_heights(ours)[k]
						if absf(drawn - low) > BAND_SEAM:
							off_glimpse.append([ours, snappedf(drawn, 0.01), snappedf(low, 0.01)])
		_check(off_glimpse.is_empty(), "%s: our ground meets each glimpse's sides within %.2f m (%d corners; off: %s)" % [name, BAND_SEAM, glimpse_corners, off_glimpse.slice(0, 3)])
		var sunk: Array = []
		var stands := 0
		for stand: Node3D in _rig._room.find_children("Stand_*", "", false, false):
			stands += 1
			var corner := Vector2i(str(stand.name).get_slice("_", 1).to_int(), str(stand.name).get_slice("_", 2).to_int())
			var foot := INF
			for at in PineStands.FOOTPRINT:
				foot = minf(foot, _rig._band_height(corner + at))
			if absf(stand.position.y - foot) > 0.01:
				sunk.append([corner, snappedf(stand.position.y, 0.01), snappedf(foot, 0.01)])
		_check(sunk.is_empty(), "%s: every stand on the forest floor's relief, its footprint's lowest (%d stands; off: %s)" % [name, stands, sunk.slice(0, 3)])
	_check(tried >= 2, "%d outdoor levels with a relief tried" % tried)
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## A dais indoors (580 step 3, terrain's side): a 12 x 4 dais a level up
## in a stone hall, its front row stairs: art-kit's dais.steps on the
## front, dais.edge round the rest, each turned with +x off the dais, no
## cliff face; the stairs flat under the steps, walked up them. The same
## map outdoors keeps its cliffs, and the sample (its relief's rock) has
## no dais.
func _test_dais() -> void:
	print("\n== a dais indoors: art-kit's edge and steps for the cliff, the stairs flat under them ==")
	var map := LevelMap.new(Vector2i(16, 12))
	for y in 12:
		for x in 16:
			map.set_cell(Vector2i(x, y), "stone")
	var dais := Rect2i(2, 2, 12, 4)
	for y in range(dais.position.y, dais.end.y):
		for x in range(dais.position.x, dais.end.x):
			map.heights[Vector2i(x, y)] = 1
	for x in range(dais.position.x, dais.end.x):
		map.set_cell(Vector2i(x, dais.end.y), "stair")
	var config := {"walls": "stone", "floors": "stone"}
	var terrain: Dictionary = Level.parse(map.to_image(), map.to_height_image(), config)["terrain"]
	_rig.rebuild(terrain, Vector2i(8, 8))
	var pieces: Array[Node] = _rig._room.find_children("Dais_*", "", false, false)
	var steps := 0
	var turned := true
	for piece: Node3D in pieces:
		var parts := String(piece.name).split("_")
		var direction := Vector2i(int(parts[3]), int(parts[4]))
		var is_steps: bool = piece.get_meta(&"slot", "") == Client3D.DAIS_STEPS
		if direction == Vector2i(0, 1):
			steps += 1
		turned = turned and piece.transform.basis.x.is_equal_approx(Vector3(direction.x, 0.0, direction.y)) \
				and piece.position.is_equal_approx(Vector3(int(parts[1]) + direction.x * 0.5, 0.0, int(parts[2]) + direction.y * 0.5))
		if is_steps != (direction == Vector2i(0, 1)):
			turned = false
	var cliffs := _rig._room.find_children("Cliffs_*", "", false, false)
	_check(pieces.size() == 32 and steps == 12 and turned and cliffs.is_empty(),
			"%d dais pieces round it (32), dais.steps on its 12 front edges, each +x off the dais on the low floor (%s), no cliff face (%d)" % [pieces.size(), turned, cliffs.size()])
	var stair := Vector2i(7, dais.end.y)
	var corners := _rig._corner_heights(stair)
	_check(Array(corners).all(func(h: float) -> bool: return absf(h) < 0.01) and not _rig._ramp_heights.has(stair) and _rig._dais_stairs.get(stair) == Vector2i(0, -1),
			"the stairs drawn flat under the steps (%s)" % [corners])
	var foot := _rig._ground_height(Vector2(stair) + Vector2(0.0, 0.45))
	var top := _rig._ground_height(Vector2(stair) - Vector2(0.0, 0.5))
	var dais_top := _rig._ground_height(Vector2(7, 4))
	_check(foot < 0.01 and absf(top - Client3D.LEVEL_RISE) < 0.01 and absf(dais_top - Client3D.LEVEL_RISE) < 0.01,
			"walked up the steps: the floor at their foot, the dais at the edge (%.2f, %.2f, %.2f)" % [foot, top, dais_top])
	config["outdoor"] = true
	terrain = Level.parse(map.to_image(), map.to_height_image(), config)["terrain"]
	_rig.rebuild(terrain, Vector2i(8, 8))
	_check(_rig._room.find_children("Dais_*", "", false, false).is_empty() and not _rig._room.find_children("Cliffs_*", "", false, false).is_empty(),
			"outdoors the same dais is a cliff")
	var sample := Level.load_level("sample")
	_rig.rebuild(sample["terrain"], sample["centre"])
	_check(_rig._room.find_children("Dais_*", "", false, false).is_empty() and _rig._dais_stairs.is_empty(),
			"the sample's ledges stay rock (a relief's)")
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## The dark tower's set (659, art-kit's side): a level naming "dark" walls
## and floors has them (art-kit's wall.dark.profile makes the set known);
## its floor cells write byte 4, drawn in the ground shader from stone's
## look (no floor.dark texture: FLOOR_UNTEXTURED), its colour the swatch.
func _test_dark_set() -> void:
	print("\n== the dark tower's set: dark walls, a dark floor a cell, byte 4 ==")
	var map := LevelMap.new(Vector2i(8, 8))
	for y in 8:
		for x in 8:
			map.set_cell(Vector2i(x, y), "stone")
	var terrain: Dictionary = Level.parse(map.to_image(), map.to_height_image(), {"walls": "dark", "floors": "dark"})["terrain"]
	_rig.rebuild(terrain, Vector2i(4, 4))
	var cell := Vector2i(3, 3)
	var place := (cell.y - _rig._mask_origin.y) * _rig._mask_size.x + cell.x - _rig._mask_origin.x
	var material := _rig._ground_shader_material
	_check(_rig._walls_set == "dark" and _rig._floor_set(cell, "stone") == "dark" and Client3D.FLOOR_SETS["dark"] == 4
			and _rig._floor_bytes[place] == 4,
			"the walls and the floor are the dark set, its cell's floor byte 4 (%s, %s, %d)" % [_rig._walls_set, _rig._floor_set(cell, "stone"), _rig._floor_bytes[place]])
	var at: Vector2i = Client3D.FLOOR_SWATCHES["dark"]
	_check(material != null and (material.get_shader_parameter("floor_dark") as Color).is_equal_approx(Client3D.swatch(at.x, at.y))
			and not _swatch_shared(at),
			"the shader's floor_dark is its own swatch %s, no other set's" % [at])
	# Its doors in its own variant (659 amended), any other set's variant 1.
	var door := Vector3i(3, 3, Terrain.SOUTH)
	for key in Level.outline(Rect2i(2, 2, 3, 2)):
		map.set_edge(key, "door" if key == door else "wall")
	for walls: String in ["dark", "stone"]:
		_rig.rebuild(Level.parse(map.to_image(), map.to_height_image(), {"walls": walls, "floors": "dark"})["terrain"], Vector2i(4, 4))
		var piece: Node3D = (_rig._doorways[door] as Node3D).get_node_or_null("Door") if _rig._doorways.has(door) else null
		var want := 2 if walls == "dark" else 1
		_check(piece != null and int(piece.get_meta("variant", 0)) == want and ArtKit.variant_count("door.single") >= 2,
				"a %s wall's door is door.single variant %d (%s)" % [walls, want, piece.get_meta("variant", 0) if piece != null else "none"])
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


static func _swatch_shared(at: Vector2i) -> bool:
	for floor_set: String in Client3D.FLOOR_SWATCHES:
		if floor_set != "dark" and Client3D.FLOOR_SWATCHES[floor_set] == at:
			return true
	return false


## The Hall of Fallen Souls (dungeon's 580 step 3 and 647, terrain's sides):
## its dais drawn with art-kit's pieces (the sides and front, the back on
## the wall), and each decor entry as its prop in its frame: a moss patch
## on its cell, a strip and a niche web on their edge facing the room, a
## corner web turned to its corner.
func _test_lair() -> void:
	print("
== the Hall of Fallen Souls in the Ossuary (666): its dais, its moss and webs ==")
	var lair := Level.load_level("barrow_deep")  # The Hall lies in the Ossuary since 666.
	var terrain: Dictionary = lair["terrain"]
	_rig.rebuild(terrain, lair["centre"])
	var pieces: Array[Node] = _rig._room.find_children("Dais_*", "", false, false)
	var steps := pieces.filter(func(piece: Node) -> bool: return piece.get_meta(&"slot", "") == Client3D.DAIS_STEPS)
	_check(pieces.size() == 20 and steps.size() == 12, "the dais: %d pieces (its two sides' 8 and the front's 12 steps), %d steps" % [pieces.size(), steps.size()])
	var decor: Array = terrain.get("decor", [])
	var drawn := 0
	var wrong := []
	for entry: Dictionary in decor:
		var kind := str(entry["kind"])
		if not Client3D._deadwood_drawn(Client3D.DECOR_SLOT % kind):
			continue
		var cell: Vector2i = entry["cell"]
		var out: Vector2i = entry["out"]
		var piece := _rig._room.get_node_or_null("Decor_%d_%d_%s_%d_%d" % [cell.x, cell.y, kind, out.x, out.y]) as Node3D
		if piece == null:
			wrong.append([cell, kind, "missing"])
			continue
		drawn += 1
		var flat := Vector2(piece.position.x, piece.position.z)
		var ok := true
		match kind:
			"moss_patch":
				ok = flat.is_equal_approx(Vector2(cell))
			"web_corner":
				var corner: Vector3 = piece.transform.basis * Vector3(-1.0, 0.0, -1.0)
				ok = flat.is_equal_approx(Vector2(cell)) and Vector2(corner.x, corner.z).normalized().is_equal_approx(Vector2(out).normalized())
			_:
				var x := piece.transform.basis.x
				ok = flat.is_equal_approx(Vector2(cell) + Vector2(out) * 0.5) and Vector2(x.x, x.z).is_equal_approx(-Vector2(out))
		if not ok:
			wrong.append([cell, kind, out])
	_check(not decor.is_empty() and drawn > 0 and wrong.is_empty(),
			"%d of %d decor entries drawn as art-kit's props, each in its frame (wrong: %s)" % [drawn, decor.size(), wrong.slice(0, 3)])
	# Each web's two variants their own meshes (art-kit's ea3b1b52).
	var mesh_of := func(node: Node3D) -> Mesh:
		var found := node.find_children("*", "MeshInstance3D", true, false)
		var mesh: Mesh = (found[0] as MeshInstance3D).mesh if not found.is_empty() else null
		node.free()
		return mesh
	var both := true
	for kind: String in ["web_corner", "web_niche"]:
		var slot := Client3D.DECOR_SLOT % kind
		var first: Mesh = mesh_of.call(ArtKit.instance(slot, 1))
		var second: Mesh = mesh_of.call(ArtKit.instance(slot, 2))
		both = both and ArtKit.variant_count(slot) >= 2 and first != null and second != null and first != second
	_check(both, "each web's variant 2 is a mesh of its own")
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## Decor with a facing and on an open edge (658): a fallen guard turned the
## way his step names, a fence section at an open edge's midpoint facing
## its cell, as a strip faces the room.
func _test_faced_decor() -> void:
	print("
== decor kinds (658): a faced guard, a fence on an open edge ==")
	var rows: Array[String] = []
	for py in 4 * 2 - 1:
		var row := ""
		for px in 5 * 2 - 1:
			row += "." if px % 2 == 0 and py % 2 == 0 else " "
		rows.append(row)
	Level.register("vt_decor_faced", Level.image_from_rows(rows, {Vector2i(0, 0): "start"}), null,
		{"decor": [[2, 1, 1, 0, "fallen_guard", 1], [1, 2, 0, -1, "grave_fence", 1]]})
	var level := Level.load_level("vt_decor_faced")
	var decor: Array = level["terrain"]["decor"]
	_check(level["warnings"].is_empty() and decor.size() == 2, "the guard and the fence section are read (%s)" % [level["warnings"]])
	var slots_drawn := Client3D._deadwood_drawn(Client3D.DECOR_SLOT % "fallen_guard") and Client3D._deadwood_drawn(Client3D.DECOR_SLOT % "grave_fence")
	if not slots_drawn:
		print("  (art-kit's prop.fallen_guard or prop.grave_fence is not drawn here: the frames are not checked)")
		return
	_rig.rebuild(level["terrain"], level["centre"])
	var guard := _rig._room.get_node_or_null("Decor_2_1_fallen_guard_1_0") as Node3D
	var fence := _rig._room.get_node_or_null("Decor_1_2_grave_fence_0_-1") as Node3D
	var guard_front := guard.transform.basis.z if guard != null else Vector3.ZERO
	_check(guard != null and Vector2(guard.position.x, guard.position.z).is_equal_approx(Vector2(2, 1)) and Vector2(guard_front.x, guard_front.z).is_equal_approx(Vector2(1, 0)),
		"the guard lies on his cell, his front turned east as his step names (%s)" % [guard_front])
	var fence_x := fence.transform.basis.x if fence != null else Vector3.ZERO
	_check(fence != null and Vector2(fence.position.x, fence.position.z).is_equal_approx(Vector2(1, 1.5)) and Vector2(fence_x.x, fence_x.z).is_equal_approx(Vector2(0, 1)),
		"the fence section stands at its open edge's midpoint, +x toward its cell, z along the edge (%s, %s)" % [fence.position if fence else null, fence_x])
	# A farm's fence ("wilds basics"): a run of three on the north edges and
	# one round the corner, a post at each end, one at a corner shared.
	Level.register("vt_decor_farm_fence", Level.image_from_rows(rows, {Vector2i(0, 0): "start"}), null,
		{"decor": [[1, 2, 0, -1, "fence", 1], [2, 2, 0, -1, "fence", 1], [3, 2, 0, -1, "fence", 1], [3, 2, 1, 0, "fence", 1]]})
	var farm := Level.load_level("vt_decor_farm_fence")
	if not ArtKit.has("prop.fence") or not ArtKit.has("prop.fence_post"):
		_check(false, "art-kit's prop.fence and prop.fence_post")
		return
	_rig.rebuild(farm["terrain"], farm["centre"])
	var rails := _rig._room.get_children().filter(func(node: Node) -> bool: return str(node.name).contains("_fence_"))
	var posts := _rig._room.get_children().filter(func(node: Node) -> bool: return str(node.name).begins_with("FencePost_"))
	var spots: Array[Vector2] = []
	for post: Node3D in posts:
		spots.append(Vector2(post.position.x, post.position.z))
	var wanted: Array[Vector2] = [Vector2(0.5, 1.5), Vector2(1.5, 1.5), Vector2(2.5, 1.5), Vector2(3.5, 1.5), Vector2(3.5, 2.5)]
	_check(farm["warnings"].is_empty() and rails.size() == 4 and posts.size() == 5
			and wanted.all(func(spot: Vector2) -> bool: return spots.any(func(each: Vector2) -> bool: return each.is_equal_approx(spot))),
			"a fence: four rails, a post at each end, the corner's shared (%d rails, posts at %s) %s" % [rails.size(), spots, farm["warnings"]])
	# A fallow field (827, the farm's): ridges of earth along its rows inside
	# its rect, low, and green weeds on them and in the hollows; a bad entry
	# warned and left out.
	var field_rows: Array[String] = []
	for py in 8 * 2 - 1:
		var line := ""
		for px in 10 * 2 - 1:
			line += "." if px % 2 == 0 and py % 2 == 0 else " "
		field_rows.append(line)
	Level.register("vt_furrows", Level.image_from_rows(field_rows, {Vector2i(0, 0): "start"}), null,
		{"outdoor": true, "furrows": [{"rect": [2, 2, 6, 4], "along": "x"}, {"rect": [1, 1], "along": "z"}]})
	var fallow := Level.load_level("vt_furrows")
	var listed: Array = fallow["terrain"]["furrows"]
	_check(listed.size() == 1 and listed[0]["rect"] == Rect2i(2, 2, 6, 4) and listed[0]["along"] == Vector2i(1, 0)
			and fallow["warnings"].any(func(w: String) -> bool: return "furrows entry" in w),
			"a field's furrows read; a bad entry warned and left out (%s)" % [listed])
	_rig.rebuild(fallow["terrain"], fallow["centre"])
	var furrows := _rig._room.get_node_or_null("Furrows_2_2") as Node3D
	var ridges := furrows.get_node_or_null("Ridges") as MeshInstance3D if furrows != null else null
	var box := ridges.mesh.get_aabb() if ridges != null and ridges.mesh != null else AABB()
	var floor_y := _rig._height_in(Vector2i(4, 3), Vector2(4, 3))
	var weeds := furrows.get_children().filter(func(node: Node) -> bool: return str(node.name).begins_with("Weed_")) if furrows != null else []
	var strays := weeds.filter(func(weed: Node3D) -> bool: return not Rect2(1.5, 1.5, 6, 4).has_point(Vector2(weed.position.x, weed.position.z)))
	_check(ridges != null and Rect2(1.5, 1.5, 6.01, 4.01).encloses(Rect2(box.position.x, box.position.z, box.size.x, box.size.z))
			and box.end.y - floor_y < Client3D.FURROW_HIGH * (1.0 + Client3D.FURROW_WOBBLE) + 0.05 and box.end.y - floor_y > Client3D.FURROW_HIGH * 0.5,
			"its ridges of earth inside its rect, low (to %.2f m over the ground, %s)" % [box.end.y - floor_y, box])
	var earth := ridges.material_override as StandardMaterial3D if ridges != null else null
	var dirt := Client3D.ground_texture("dirt")
	_check(earth != null and earth.albedo_texture != null and (dirt == null or earth.albedo_texture == dirt)
			and earth.uv1_triplanar and not earth.uv1_world_triplanar,
			"its earth the ground's dirt texture, in the room's frame (%s)" % [earth.albedo_texture if earth != null else null])
	_check(not ArtKit.has("scatter.tuft") or weeds.size() >= 24 and strays.is_empty(),
			"weeds on it, none outside it (%d, %d stray)" % [weeds.size(), strays.size()])
	# A wide ford's middle (505 amended (7)): a ford three rows deep across
	# grass; its middle row, no ground beside it, a bed of sand with a few
	# round stones, not the stone floor's paving; its edge rows the bank's
	# grass, bare.
	var wading: Dictionary = {Vector2i(0, 0): "start"}
	for y in 8:
		for x in 10:
			if Vector2i(x, y) != Vector2i.ZERO:
				wading[Vector2i(x, y)] = "ford" if y >= 3 and y <= 5 else "grass"
	Level.register("vt_ford_bed", Level.image_from_rows(field_rows, wading), null, {"outdoor": true})
	var stream := Level.load_level("vt_ford_bed")
	_rig.rebuild(stream["terrain"], stream["centre"])
	var middles: Array[Vector2i] = []
	var edges: Array[Vector2i] = []
	for x in 10:
		middles.append(Vector2i(x, 4))
		edges.append_array([Vector2i(x, 3), Vector2i(x, 5)])
	_check(str(stream["terrain"]["kinds"].get(Vector2i(4, 4), "")) == "stone"
			and middles.all(func(cell: Vector2i) -> bool: return _rig._ford_beds.has(cell) and _rig._ground_kinds.get(cell, "") == Client3D.FORD_BED_KIND)
			and edges.all(func(cell: Vector2i) -> bool: return not _rig._ford_beds.has(cell) and _rig._ground_kinds.get(cell, "") == "grass"),
			"a wide ford's middle drawn as sand, the sim's kind still stone; its edges the bank's grass (%s, %s)" % [_rig._ground_kinds.get(Vector2i(4, 4), ""), _rig._ground_kinds.get(Vector2i(4, 3), "")])
	var on_bed := {}
	var on_edge := 0
	for chunk: Vector2i in _rig._scatter_chunks:
		var plan := _rig._scatter_plan(chunk)
		for kind: String in plan:
			for item: Array in plan[kind]:
				if middles.has(item[0]):
					on_bed[kind] = int(on_bed.get(kind, 0)) + 1
				elif edges.has(item[0]):
					on_edge += 1
	_check(on_bed.keys() == ["stone"] and int(on_bed["stone"]) >= 1 and int(on_bed["stone"]) < middles.size() and on_edge == 0,
			"on its bed a few round stones, nothing else, under one a cell; nothing on its edges (%s, %d)" % [on_bed, on_edge])
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## The felled forest drawn (591, terrain's side; maps' Clearing): a stage
## each on four edge trunks of the hills (else the wilds'), no tree on any, the edge's curve
## round them, each stage's props and scrub's thick grass; live, a stage
## changed on the land swaps its props and ground with no rebuild, a fell
## takes its tree at once (its outline the next build's), a regrowth puts
## the tree back.
func _test_clearing() -> void:
	print("\n== the forest felled: a clearing's stages drawn, live changes ==")
	# Edge trunks: a void cell beside the land, apart from each other, in
	# from the land's bounds (where Clearing fells none, and the next map's
	# glimpse lies): the hills', else the wilds'.
	var level: Dictionary
	var terrain: Dictionary
	var trunks: Array[Vector2i] = []
	for name: String in ["hills", "wilds"]:
		level = Level.load_level(name)
		terrain = level["terrain"]
		var land: Dictionary[Vector2i, bool] = {}
		for cell: Vector2i in terrain["floor"] + terrain.get("water", []) + terrain.get("solid", []) + terrain.get("rocks", []):
			land[cell] = true
		var low := Vector2i(1 << 20, 1 << 20)
		var high := -low
		for cell: Vector2i in land:
			low = low.min(cell)
			high = high.max(cell)
		trunks.clear()
		for cell: Vector2i in terrain["floor"]:
			if trunks.size() >= 4:
				break
			for side: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var trunk := cell + side
				if trunk.x < low.x + 8 or trunk.y < low.y + 8 or trunk.x > high.x - 8 or trunk.y > high.y - 8 or land.has(trunk) \
						or trunks.any(func(t: Vector2i) -> bool: return Vector2(t).distance_to(Vector2(trunk)) < 12.0):
					continue
				trunks.append(trunk)
				break
		if trunks.size() >= 4:
			break
	_check(trunks.size() >= 4, "%s: four edge trunks to fell (%s)" % [level["name"], trunks])
	if trunks.size() < 4:
		return
	var stages := ["stump", "grass", "scrub", "saplings"]
	var cells := []
	for k in 4:
		cells.append([trunks[k].x, trunks[k].y, stages[k]])
	Clearing.apply_cells(terrain, cells)
	_rig.rebuild(terrain, level["centre"])
	var treed := []
	for k in 4:
		for cell: Vector2i in _rig._trees:
			var at: Vector3 = _rig._trees[cell].position
			if cell == trunks[k] or Vector2i(roundi(at.x), roundi(at.z)) == trunks[k]:
				treed.append(trunks[k])
	var forested := trunks.slice(0, 4).filter(func(cell: Vector2i) -> bool:
		var into := _rig._edge_signed(Vector2(cell))
		return not _rig._wooded.has(cell) or not is_nan(into) and into > 0.0)
	_check(treed.is_empty() and forested.is_empty(), "%s: no tree on a felled cell (treed: %s), each on the land's side of the edge (forest's: %s)" % [level["name"], treed, forested])
	# Walls or posts drawn round a cell (591 amended: a felled cell's are none,
	# open to the land, the forest's edge beyond it trees).
	var walled := func(cell: Vector2i) -> Array:
		var found := []
		for way: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var key := Terrain.edge_key(cell, way)
			if _rig._walls.has(key):
				found.append(key)
			for end in 2:
				if _rig._posts.has(WallEdge.vertex_at(key, end)):
					found.append(WallEdge.vertex_at(key, end))
		return found
	var round_four := trunks.slice(0, 4).map(func(cell: Vector2i) -> Array: return walled.call(cell)).filter(func(found: Array) -> bool: return not found.is_empty())
	_check(round_four.is_empty(), "%s: no wall or post round a felled cell (%s)" % [level["name"], round_four])
	var props := func(cell: Vector2i) -> Array: return _rig._clearing_props.get(cell, [])
	var stump_ok: bool = (props.call(trunks[0]) as Array).size() == (1 if Client3D._deadwood_drawn("tree.stump") else 0)
	var saplings: Array = props.call(trunks[3])
	var saplings_ok := saplings.size() >= 2 and saplings.size() <= 3 and saplings.all(func(prop: Node3D) -> bool: return prop.has_meta(&"fades"))
	_check(stump_ok and (props.call(trunks[1]) as Array).is_empty() and (props.call(trunks[2]) as Array).size() <= 1 and saplings_ok,
			"%s: a stump on the stump, nothing on the grass, at most a bush in the scrub, %d saplings that fade as trees do" % [level["name"], saplings.size()])
	var chunk := Vector2i(floori(trunks[2].x / float(Client3D.FLOOR_CHUNK)), floori(trunks[2].y / float(Client3D.FLOOR_CHUNK)))
	var tall := 0
	for item: Array in _rig._scatter_plan(chunk).get("tall", []):
		if item[0] == trunks[2]:
			tall += 1
	_check(tall > 0 and _rig._ground_kinds.get(trunks[0], "") == "dirt", "%s: scrub's tall grass (%d clumps), the stump's ground dirt" % [level["name"], tall])
	# Live: a stage changed on the land, then a fell, then a regrowth.
	_rig._scatter_all()
	var room := _rig._room.get_instance_id()
	var change := [[trunks[0].x, trunks[0].y, "grass"]]
	Clearing.apply_cells(terrain, change)
	_rig.clearing_changed(terrain, change)
	_check(_rig._room.get_instance_id() == room and not _rig._clearing_props.has(trunks[0]) and _rig._ground_kinds.get(trunks[0], "") == "grass" \
			and _rig._kinds_image.get_pixelv(trunks[0] - _rig._mask_origin).r > 0.9,
			"live: the stump grown to grass, its stump gone, its ground grass, no rebuild")
	# An edge tree of its own cell, away from the clearing's four.
	var felled := Vector2i(-1, -1)
	for cell: Vector2i in _rig._trees:
		if _rig._forest_distance.get(cell, 0) == 1 and str(_rig._trees[cell].name).begins_with("Tree_") \
				and trunks.all(func(t: Vector2i) -> bool: return Vector2(t).distance_to(Vector2(cell)) >= 12.0):
			felled = cell
			break
	var had_tree := _rig._trees.has(felled)
	change = [[felled.x, felled.y, "stump"]]
	var walls_changed: Dictionary = Clearing.apply_cells(terrain, change)
	_rig.clearing_changed(terrain, change)
	_rig.clearing_walls(walls_changed)
	_check(had_tree and _rig._room.get_instance_id() == room and not _rig._trees.has(felled) and _rig._clearing.get(felled, "") == "stump",
			"live: a fell takes its tree at once (had one: %s), no rebuild" % had_tree)
	_check(not walls_changed.is_empty() and (walled.call(felled) as Array).is_empty(),
			"live: the felled cell's walls drawn again (%d edges changed), none round it" % walls_changed.size())
	_rig.rebuild(terrain, level["centre"])
	_check(_rig._wooded.has(felled) and not _rig._trees.has(felled) and _rig._clearing.get(felled, "") == "stump",
			"next build: the felled cell the land's, the outline round it")
	change = [[felled.x, felled.y, Clearing.TRUNK]]
	walls_changed = Clearing.apply_cells(terrain, change)
	room = _rig._room.get_instance_id()
	_rig.clearing_changed(terrain, change)
	_rig.clearing_walls(walls_changed)
	_check(_rig._room.get_instance_id() == room and _rig._trees.has(felled) and not _rig._clearing.has(felled),
			"live: grown back, a tree at once, no rebuild")
	# The build's land still holds the cell: grown back, it is the void again,
	# its edges the outline (trees), no wall.
	_check(not walls_changed.is_empty() and _rig._grown_back.has(felled) and (walled.call(felled) as Array).is_empty(),
			"live: the regrown trunk's edges the outline again, no wall round it")
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## The ledges drawn from their curves (585, terrain's side): each cell a
## ledge's curve crosses split along it, its two parts filling its square,
## each part on its own side; each part at the ground of its side, so the
## high ground meets the face's top on the curve and the low its foot; a
## face down every stretch of a ledge that drops; the cell edges a ledge
## covers left to it.
func _test_ledge_curves() -> void:
	print("\n== ledges drawn from their curves: split cells, faces along the curve ==")
	for name: String in ["hills", "wilds"]:
		var level := Level.load_level(name)
		_rig.rebuild(level["terrain"], level["centre"])
		if _rig._ledge_curves.is_empty():
			_check(not (level["terrain"] as Dictionary).has("ledges") or (level["terrain"]["ledges"] as Array).is_empty(),
					"%s: no ledges laid, none drawn" % name)
			continue
		var short := []
		var astray := []
		for cell: Vector2i in _rig._ledge_split:
			var split: Dictionary = _rig._ledge_split[cell]
			var area := 0.0
			for part: Array in split["parts"]:
				var polygon: PackedVector2Array = part[0]
				var twice := 0.0
				for k in polygon.size():
					twice += polygon[k].cross(polygon[(k + 1) % polygon.size()])
				area += absf(twice) / 2.0
				var middle := Client3D._inside_point(polygon)
				# A part's middle on its own side of its ledge's curve (well inside
				# it; where two ledges meet, or past an open end, no side to say).
				var at := _rig._ledge_near(middle)
				if at.y == float(split["ledge"]) and absf(at.x) > 0.05 and (at.x > 0.0) != bool(part[1]) 						and at.z > 0.5 and at.z < (_rig._ledge_curves[int(at.y)]["curve"]["points"] as PackedVector2Array).size() - 1.5:
					astray.append(cell)
			if absf(area - 1.0) > 0.01:
				short.append([cell, snappedf(area, 0.001)])
		_check(not _rig._ledge_split.is_empty() and short.is_empty() and astray.is_empty(),
				"%s: %d cells split along %d ledges, their parts filling them (short: %s), each on its side (astray: %s)" % [name, _rig._ledge_split.size(), _rig._ledge_curves.size(), short.slice(0, 3), astray.slice(0, 3)])
		# Each face's top is the high ground there, its foot the low, and a
		# stretch that drops has one.
		var stretches := 0
		var faced := 0
		var unmet := []
		for index in _rig._ledge_curves.size():
			var ledge: Dictionary = _rig._ledge_curves[index]
			var points: PackedVector2Array = ledge["curve"]["points"]
			for k in range(0, points.size(), 4):
				# An open curve's end can stop on another ledge (756's terraced
				# taper), where the ground either side is the two ledges' both.
				if not bool(ledge["closed"]) and (k == 0 or k == points.size() - 1):
					continue
				var high := _rig._ledge_ground(points[k], true, index)
				var low := _rig._ledge_ground(points[k], false, index)
				if high - low <= Relief.EPSILON:
					continue
				stretches += 1
				# The drawn ground just past the curve either side meets it.
				var t: Vector2 = (ledge["curve"]["tangents"] as PackedVector2Array)[k]
				var up := Vector2(-t.y, t.x) * float(ledge["up"])
				var above := _rig._ledge_ground(points[k] + up * 0.02, true, index)
				var below := _rig._ledge_ground(points[k] - up * 0.02, false, index)
				if absf(above - high) > 0.05 or absf(below - low) > 0.05:
					unmet.append(points[k])
				faced += 1
		_check(stretches > 0 and unmet.is_empty(),
				"%s: the faces along the curves, top on the high ground, foot on the low (%d stretches; unmet: %s)" % [name, stretches, unmet.slice(0, 3)])
		var covered := 0
		for edge: Array in _rig._cliff_edges:
			covered += 1 if _rig._ledge_covers(edge[0], edge[0] + edge[1]) else 0
		_check(covered > 0, "%s: %d cell-edge faces left to the ledges' curves" % [name, covered])
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## A body walks on a bridge's deck (505 amended (5); Jeff, 2026-11-06: "the
## bridge still doesn't work you glitch through it"): the ground's mesh under
## a deck is the stream's bed and its banks dip to the water, so a puppet
## stood on them (_ground_height) sank through the deck. Walked along each
## deck row of the wilds' and the hills' bridges, bank to bank: on the deck
## its top, at the deck's ends its top, no step between two points a tenth
## of a cell apart (the bank cell past an end eases into the ground).
func _test_bridge_walked() -> void:
	print("\n== a body walks on a bridge's deck, not the bed under it (505 amended (5)) ==")
	for name: String in ["wilds", "hills"]:
		var level := Level.load_level(name)
		var bridges: Array = level["buildings"].filter(func(b: Dictionary) -> bool: return b["slot"] == Level.BRIDGE)
		if bridges.is_empty():
			_check(false, "%s has a bridge" % name)
			continue
		var bridge: Dictionary = bridges[0]
		var rect: Rect2i = bridge["rect"]
		_rig.rebuild(level["terrain"], rect.position)
		var facing: Vector2i = bridge["facing"]
		var along := Vector2i(absi(facing.x), absi(facing.y))
		var across := Vector2i(along.y, along.x)
		var top := _rig._elevation(rect.position) + Client3D.BRIDGE_LIFT
		var length := rect.size.x if along.x != 0 else rect.size.y
		var width := rect.size.y if along.x != 0 else rect.size.x
		var off_deck := []
		var under_at_ends := []
		var jumps := []
		var lowest_bed := INF
		for row in width:
			var start := Vector2(rect.position + across * row) - Vector2(along) * 1.5
			var before := NAN
			for k in int((length + 2) * 10) + 1:
				var point := start + Vector2(along) * (0.1 * k)
				var cell := Vector2i(roundi(point.x), roundi(point.y))
				var height: float = _rig._ground_height(point)
				if rect.has_point(cell):
					lowest_bed = minf(lowest_bed, _rig._height_in(cell, point))
					if absf(height - top) > 0.01:
						off_deck.append([point, snappedf(height, 0.01)])
				elif rect.has_point(cell - along) or rect.has_point(cell + along):
					# The bank cell past an end: at the deck's edge, the deck's top.
					var edge := Vector2(cell) + Vector2(along) * (0.5 if rect.has_point(cell + along) else -0.5)
					if point.distance_to(edge) < 0.05 and absf(height - top) > 0.01:
						under_at_ends.append([point, snappedf(height, 0.01)])
				if not is_nan(before) and absf(height - before) > 0.1:
					jumps.append([point, snappedf(before, 0.01), snappedf(height, 0.01)])
				before = height
		_check(off_deck.is_empty() and under_at_ends.is_empty() and jumps.is_empty(),
			"%s: on the deck at its top %.2f (the bed's mesh under it as low as %.2f), off its ends at the same, no step (off %s, at the ends %s, steps %s)"
			% [name, top, lowest_bed, off_deck.slice(0, 3), under_at_ends.slice(0, 3), jumps.slice(0, 3)])


## Built water (decision 595): water no curve lays (the wilds' wells) drawn
## square and still: each body over its own cells alone, its edge theirs, no
## shore field round it; natural water (a curve's) as before.
func _test_built_water() -> void:
	print("
== built water: the wilds' wells square and still, natural water from its curves ==")
	var wilds := Level.load_level("wilds")
	# The farmstead's well, the wilds' only one, is dry since 827: water put
	# back in it here, in memory, stands for a well that has water.
	var well := Vector2i(127, 147)
	_check(not well in wilds["terrain"]["water"], "the old farmstead's well dry (827)")
	wilds["terrain"]["water"].append(well)
	_rig.rebuild(wilds["terrain"], wilds["centre"])
	var built_bodies := 0
	var astray := []
	var fielded := []
	for body: MeshInstance3D in _rig._water_bodies:
		var material := body.material_override as ShaderMaterial
		if not bool(material.get_shader_parameter("built")):
			continue
		built_bodies += 1
		for point: Vector3 in (body.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			# Each corner a corner of a built cell.
			var touches := false
			for dy in [-0.5, 0.5]:
				for dx in [-0.5, 0.5]:
					touches = touches or _rig._built_water.has(Vector2i(roundi(point.x + dx), roundi(point.z + dy)))
			if not touches:
				astray.append(Vector2(point.x, point.z))
	for cell: Vector2i in _rig._built_water:
		if _rig.shore_at(Vector2(cell)) > 0.01:
			fielded.append(cell)
	_check(not _rig._built_water.is_empty() and built_bodies >= 1 and astray.is_empty() and fielded.is_empty(),
			"wilds: its wells built water (%d cells, %d bodies), each over its own cells alone (astray: %s), no shore field round them (%s)" % [_rig._built_water.size(), built_bodies, astray.slice(0, 3), fielded.slice(0, 3)])
	var hills := Level.load_level("hills")
	_rig.rebuild(hills["terrain"], hills["centre"])
	_check(_rig._built_water.is_empty(), "hills: all its water natural, from its curves (built: %s)" % [_rig._built_water.keys().slice(0, 3)])
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## Umbrage at night (858), its switch forced on here (night_look_2) and put
## back: indoors, on a damp level and in a cave the ambient and the floor's
## light are the same switched on as off, and no body fill; outdoors at
## midnight the ambient lower and less blue, the ground's floor light up from
## FLOOR_DARKEST to NIGHT_FLOOR_DARKEST, the fill on, the floor's colour
## keeping its light off (sky_floor_base) under the lift; at noon all as off;
## a body's drawn parts on BODY_LAYER, its own layer kept.
func _test_night_look_2() -> void:
	print("\n== Umbrage at night (858): outdoors only, the ground lit once, a fill on bodies ==")
	var was := Client3D.night_look_2
	var hour_was := DayNight.hour(DayNight.now())
	var weather_was: Dictionary = World.fields.weather.duplicate()
	var read := func() -> Array:
		return [_rig._environment.ambient_light_color, _rig._environment.ambient_light_energy,
				float(_rig._ground_shader_material.get_shader_parameter("sky_floor")), _rig._body_fill.visible,
				_param_or(_rig._ground_shader_material, "sky_floor_base", -1.0)]
	var barrow := Level.load_level("barrow")
	var plain: Dictionary = barrow["terrain"]
	var damp: Dictionary = plain.duplicate()
	damp["damp"] = true
	var cave: Dictionary = plain.duplicate()
	cave["zone"] = "cave"
	cave.erase("ambient")
	var differ := []
	for name: String in ["barrow", "damp", "cave"]:
		var terrain: Dictionary = {"barrow": plain, "damp": damp, "cave": cave}[name]
		var seen := []
		for on: bool in [false, true]:
			Client3D.night_look_2 = on
			_rig.rebuild(terrain, barrow["centre"])
			_rig._update_sky(0.0)
			seen.append(read.call())
		if seen[0] != seen[1] or bool(seen[1][3]):
			differ.append("%s %s / %s" % [name, seen[0], seen[1]])
	_check(differ.is_empty(), "indoors, damp and in a cave the ambient and floor light are the same switched on as off, no fill (%s)" % [differ])
	var hills := Level.load_level("hills")
	var at := func(hour: float, on: bool) -> Array:
		Client3D.night_look_2 = on
		DayNight.set_hour(hour)
		World.fields.weather = Weather.KINDS["clear"].duplicate()
		World.fields.weather["wind_dir"] = Vector2.RIGHT
		World.fields.weather["snow"] = 0.0
		_rig._weather_view.weather = World.fields.weather.duplicate()
		_rig.rebuild(hills["terrain"], hills["centre"])
		_rig._sky_step = -1
		_rig._update_sky(0.0)
		_rig._update_sky(0.0)  # The fill follows the look the first call set.
		return read.call() + [_rig._body_fill.light_energy]
	var off_night: Array = at.call(0.0, false)
	var on_night: Array = at.call(0.0, true)
	var bluer := func(c: Color) -> float: return c.b - c.r
	_check(float(on_night[1]) < float(off_night[1]) and bluer.call(on_night[0]) < bluer.call(off_night[0])
			and float(on_night[2]) > float(off_night[2]) and bool(on_night[3]) and not bool(off_night[3])
			and float(on_night[5]) > 0.0 and float(on_night[5]) <= Client3D.BODY_FILL_ENERGY + 0.0001,
			"midnight outdoors switched on: the ambient %.3f (off %.3f), less blue, the floor's light %.2f (off %.2f), the body fill %.2f"
			% [on_night[1], off_night[1], on_night[2], off_night[2], on_night[5]])
	# The lift is the sky's alone (858): the floor's colour keeps the light it had off, so a lantern or a
	# lamp lights it as before, and the sky's light on it is set for the shader to add the rest.
	var sky_light: Vector3 = _param_or(_rig._ground_shader_material, "night_sky_light", Vector3.ZERO)
	_check(is_equal_approx(float(on_night[4]), float(off_night[2])) and is_equal_approx(float(off_night[4]), float(off_night[2])),
			"midnight: the floor's colour keeps its light off (%.2f, off %.2f) under the lift to %.2f"
			% [on_night[4], off_night[2], on_night[2]])
	# The sky's light pinned to its sum, so a wrong scale fails here, not in a still (start 7: a PI too
	# many lit the street 2.75 times over): NIGHT_KEY_2's ambient plus its moon at its fall on the flat.
	# At midnight on the hills the moon stands lifted to 60 degrees (a fall of 0.866): the row's own numbers.
	var key: Dictionary = Client3D.NIGHT_KEY_2
	var want_ambient: Color = key["ambient"] * float(key["ambient_energy"])
	var want_moon: Color = key["light"] * float(key["energy"])
	var midnight := Vector3(want_ambient.r + want_moon.r * 0.866, want_ambient.g + want_moon.g * 0.866, want_ambient.b + want_moon.b * 0.866)
	_check(sky_light.distance_to(midnight) < 0.01, "midnight: the sky's light on the floor %s, the ambient and the moon's fall summed %s" % [sky_light, midnight])
	at.call(2.0, true)
	var later: Vector3 = _param_or(_rig._ground_shader_material, "night_sky_light", Vector3.ZERO)
	var env := _rig._environment
	var falls := maxf(_rig._sun.global_transform.basis.z.y, 0.0)
	var summed := Vector3(env.ambient_light_color.r * env.ambient_light_energy + _rig._sun.light_color.r * _rig._sun.light_energy * falls,
			env.ambient_light_color.g * env.ambient_light_energy + _rig._sun.light_color.g * _rig._sun.light_energy * falls,
			env.ambient_light_color.b * env.ambient_light_energy + _rig._sun.light_color.b * _rig._sun.light_energy * falls)
	_check(later.distance_to(summed) < 0.005 and falls > 0.0, "02:00: the sky's light %s, the view's ambient and moon (fall %.3f) summed %s" % [later, falls, summed])
	var off_noon: Array = at.call(12.0, false)
	var on_noon: Array = at.call(12.0, true)
	_check(off_noon.slice(0, 5) == on_noon.slice(0, 5) and not bool(on_noon[3]) and is_equal_approx(float(on_noon[4]), float(on_noon[2])),
			"noon outdoors: the same switched on as off, no fill, no lift")
	var parts := 0
	var layered := 0
	for puppet: Node3D in _rig._puppets.values():
		for node: Node in puppet.find_children("*", "GeometryInstance3D", true, false):
			parts += 1
			if (node as VisualInstance3D).layers & Client3D.BODY_LAYER and (node as VisualInstance3D).layers & 1:
				layered += 1
	_check(parts > 0 and layered == parts, "every body's drawn part on BODY_LAYER, its own layer kept (%d of %d)" % [layered, parts])
	Client3D.night_look_2 = was
	DayNight.set_hour(hour_was)
	World.fields.weather = weather_was
	_rig._weather_view.weather = weather_was.duplicate()
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## [param material]'s [param name], or the shader's own [param fallback] when never set (a shader
## material gives null for a uniform nobody set).
func _param_or(material: ShaderMaterial, name: String, fallback: Variant) -> Variant:
	var value: Variant = material.get_shader_parameter(name)
	return fallback if value == null else value


## A damp level's look (580, terrain's side): the barrow with "damp": its
## ambient a share of the zone's, colder, a faint haze; each carried
## lantern at the sim's reach (Fields.carried_reach: half); back as it was
## on a level not damp.
func _test_damp_look() -> void:
	print("
== a damp level: darker, colder, a haze, the lanterns at half reach ==")
	var barrow := Level.load_level("barrow")
	var plain: Dictionary = barrow["terrain"]
	var damp: Dictionary = plain.duplicate()
	damp["damp"] = true
	_rig.rebuild(plain, barrow["centre"])
	var dry_energy := _rig._environment.ambient_light_energy
	_rig.rebuild(damp, barrow["centre"])
	var lanterns := _rig._puppets.values().map(func(puppet: Node3D) -> OmniLight3D: return puppet.get_node_or_null("Lantern") as OmniLight3D).filter(func(light: OmniLight3D) -> bool: return light != null)
	var reach := Client3D.PLAYER_LIGHT_RANGE * Fields.carried_reach(true) / float(Fields.CARRIED_REACH)
	var short := lanterns.all(func(light: OmniLight3D) -> bool: return is_equal_approx(light.omni_range, reach))
	_check(not lanterns.is_empty() and short and _rig._environment.fog_enabled
			and is_equal_approx(_rig._environment.ambient_light_energy, dry_energy * Client3D.DAMP_AMBIENT),
			"damp: ambient %.2f of %.2f, a haze, %d lanterns at %.1f m" % [_rig._environment.ambient_light_energy, dry_energy, lanterns.size(), reach])
	_rig.rebuild(plain, barrow["centre"])
	var back := lanterns.all(func(light: OmniLight3D) -> bool: return is_equal_approx(light.omni_range, Client3D.PLAYER_LIGHT_RANGE))
	_check(back and not _rig._environment.fog_enabled and is_equal_approx(_rig._environment.ambient_light_energy, dry_energy),
			"not damp: the lanterns at %.1f m again, no haze" % Client3D.PLAYER_LIGHT_RANGE)
	# A cave (304 amended): its look's ambient, and the floor drawn no darker
	# than CAVE_FLOOR of its colour; other zones the sim's cell light alone.
	var cave: Dictionary = plain.duplicate()
	cave["zone"] = "cave"
	cave.erase("ambient")
	_rig.rebuild(cave, barrow["centre"])
	var cave_floor: float = _rig._ground_shader_material.get_shader_parameter("sky_floor")
	var cave_energy := _rig._environment.ambient_light_energy
	_rig.rebuild(plain, barrow["centre"])
	var plain_floor: float = _rig._ground_shader_material.get_shader_parameter("sky_floor")
	_check(is_equal_approx(cave_floor, Client3D.CAVE_FLOOR) and is_equal_approx(cave_energy, float(Client3D.ZONE_LOOK["cave"][1]))
			and is_zero_approx(plain_floor),
			"a cave: ambient %.2f, its floor drawn at least %.2f; the barrow's floor %.2f (the sim's light alone)" % [cave_energy, cave_floor, plain_floor])
	# The soft scatter darkens with the floor indoors (the global floor_shade,
	# each cell's brightness as the floor draws it); outdoors none.
	_rig._shade_floor()
	var indoors := _rig._shade_texture != null and _rig._shade_image != null
	var matched := 0
	var differ := []
	for cell: Vector2i in _rig._ground_shades:
		var at := cell - _rig._mask_origin
		if at.x < 0 or at.y < 0 or at.x >= _rig._mask_size.x or at.y >= _rig._mask_size.y:
			continue
		var drawn := _rig._shade_image.get_pixel(at.x, at.y).r if indoors else -1.0
		if absf(drawn - minf((_rig._ground_shades[cell] as Vector2).x, 1.0)) < 0.01:
			matched += 1
		else:
			differ.append(cell)
	# No live plants indoors (Jeff: "moss and spiderwebs for decor, no live
	# plants"): of the scatter, stones alone.
	var grown := {}
	for chunk: Vector2i in _rig._scatter_chunks:
		for kind: String in _rig._scatter_plan(chunk):
			if not Client3D.SCATTER_INDOORS.has(kind):
				grown[kind] = true
	_check(not _rig._scatter_chunks.is_empty() and grown.is_empty(), "indoors no plant in the scatter (grown: %s)" % [grown.keys()])
	var hills := Level.load_level("hills")
	_rig.rebuild(hills["terrain"], hills["centre"])
	var tufts := 0
	for chunk: Vector2i in _rig._scatter_chunks:
		tufts += (_rig._scatter_plan(chunk).get("tuft", []) as Array).size()
		if tufts > 0:
			break
	_check(tufts > 0, "outdoors the grass's tufts as before")
	var outdoors := _rig._shade_texture == null
	_check(indoors and matched > 0 and differ.is_empty() and outdoors,
			"indoors the scatter's floor shade is each cell's as drawn (%d cells; differ: %s); outdoors none" % [matched, differ.slice(0, 3)])
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## Where two waters' curves meet (570, terrain's side: a stream into a
## river): the field their union, so a point inside the river nearer the
## stream's end than any of the river's samples is still in the water.
func _test_curves_meet() -> void:
	print("
== curves meet: a stream's end in a river, the water their union ==")
	var river := Curves.sample(PackedVector2Array([Vector2(-6, 0), Vector2(0, 0), Vector2(6, 0)]), PackedFloat32Array([4.0, 4.0, 4.0]))
	var stream := Curves.sample(PackedVector2Array([Vector2(0, 8), Vector2(0, 5), Vector2(0, 3)]), PackedFloat32Array([0.5, 0.5, 0.5]))
	var curves: Array = [{"curve": river, "closed": false}, {"curve": stream, "closed": false}]
	var near_map: Dictionary = {}
	var also: Dictionary = {}
	_rig._stamp_near(river, false, 0, near_map, also)
	_rig._stamp_near(stream, false, 1, near_map, also)
	# (0.2, 1.6): 0.4 inside the river's edge, 1.4 from the stream's end.
	var point := Vector2(0.2, 1.6)
	var at := _rig._near_on(curves, near_map, point, also)
	var one := _rig._near_on(curves, {Vector2i(0, 2): Vector2i(1, (stream["points"] as PackedVector2Array).size() - 1)}, point, {})
	_check(also.has(Vector2i(0, 2)) and int(at.z) == 0 and absf(at.x - 0.4) < 0.05 and one.x < 0.0,
			"a point in the river by the stream's end is in the river (%s; the stream's end alone: %s)" % [at, one])


func _test_shore() -> void:
	print("\n== shore: the water's edge rounded, within SHORE_BOUND of its cells; the bank drawn finer on relief ==")
	# A lone cell is a disc: wet in its middle, dry at its corners; a 3 x 3
	# pond's straight sides keep their edge, its corners rounded.
	var lone: Dictionary[Vector2i, bool] = {Vector2i(3, 3): true}
	var field := Client3D.shore_image([], lone, Vector2i.ZERO, Vector2i(7, 7))
	var at := func(image: Image, point: Vector2) -> float:
		var texel := ((point + Vector2(0.5, 0.5)) * Client3D.SHORE_RES - Vector2(0.5, 0.5)).round()
		return image.get_pixelv(Vector2i(texel)).r
	var corners_dry := true
	for corner: Vector2 in [Vector2(-0.45, -0.45), Vector2(0.45, -0.45), Vector2(-0.45, 0.45), Vector2(0.45, 0.45)]:
		corners_dry = corners_dry and at.call(field, Vector2(3, 3) + corner) < 0.5
	_check(at.call(field, Vector2(3, 3)) > 0.5 and corners_dry, "a lone water cell is a disc: wet in its middle, dry at its corners")
	var pond: Dictionary[Vector2i, bool] = {}
	for y in range(2, 5):
		for x in range(2, 5):
			pond[Vector2i(x, y)] = true
	field = Client3D.shore_image([], pond, Vector2i.ZERO, Vector2i(7, 7))
	_check(at.call(field, Vector2(3, 1.75)) > 0.5 and at.call(field, Vector2(3, 1.25)) < 0.5 and at.call(field, Vector2(1.6, 1.6)) < 0.5,
			"a pond's side keeps its edge, its corner rounded (side %.2f, out %.2f, corner %.2f)"
			% [at.call(field, Vector2(3, 1.75)), at.call(field, Vector2(3, 1.25)), at.call(field, Vector2(1.6, 1.6))])
	for name: String in ["wilds", "hills"]:
		var level := Level.load_level(name)
		_rig.rebuild(level["terrain"], level["centre"])
		var wet: Dictionary = {}
		for cell: Vector2i in _rig._wet:
			wet[cell] = true
		wet.merge(_rig._fords)
		for cell: Vector2i in _rig._bed_levels:
			wet[cell] = true  # A bridge's: the water runs on under it.
		# Each texel within the wet cells round it and the land: further
		# than SHORE_BOUND (box distance) from the other, it is the cell's.
		var astray := []
		var checked := 0
		var seen: Dictionary[Vector2i, bool] = {}
		for cell: Vector2i in wet:
			for y in range(-1, 2):
				for x in range(-1, 2):
					var here := cell + Vector2i(x, y)
					if not _rig._grounds.has(here) or seen.has(here):
						continue
					seen[here] = true
					# A water laid as a curve (559, terrain's side): its edge is
					# the curve's, checked below, not its cells'.
					if _rig._curve_near_sample.has(here):
						continue
					# Built water (decision 595) has no shore field: its edge is
					# its cells', drawn square (_test_built_water).
					if _rig._built_water.has(here) or [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)].any(func(d: Vector2i) -> bool: return _rig._built_water.has(here + d)):
						continue
					var water := wet.has(here)
					for v in Client3D.SHORE_RES:
						for u in Client3D.SHORE_RES:
							var point := Vector2(here) + (Vector2(u, v) + Vector2(0.5, 0.5)) / Client3D.SHORE_RES - Vector2(0.5, 0.5)
							var far := INF
							for dy in range(-1, 2):
								for dx in range(-1, 2):
									var near := here + Vector2i(dx, dy)
									if wet.has(near) != water and _rig._grounds.has(near):
										var gap := (point - Vector2(near)).abs() - Vector2(0.5, 0.5)
										far = minf(far, maxf(maxf(gap.x, gap.y), 0.0))
							if far <= Client3D.SHORE_BOUND:
								continue
							checked += 1
							if (_rig.shore_at(point) > 0.5) != water:
								astray.append([name, here, point])
		_check((checked > 0 or not _rig._curve_waters.is_empty()) and astray.is_empty(),
				"%s: the water's edge within %.2f of its cells' (%d points; astray: %s)" % [name, Client3D.SHORE_BOUND, checked, astray.slice(0, 4)])
		# A water laid as a curve (559, terrain's side): the field is the
		# curve's signed distance; in or out by it wherever it is past 0.15
		# of a cell, and its edge (the curve's half width) at a half within
		# an eighth, never from the cells.
		var curve_points := 0
		var crossed := []
		var off_edge := []
		for water: Dictionary in _rig._curve_waters:
			if water["closed"]:
				continue
			var samples: PackedVector2Array = water["curve"]["points"]
			var widths: PackedFloat32Array = water["curve"]["widths"]
			var tangents: PackedVector2Array = water["curve"]["tangents"]
			for k in range(0, samples.size(), 3):
				var normal := Vector2(-tangents[k].y, tangents[k].x)
				for side: float in [-1.0, 1.0]:
					var edge := samples[k] + normal * side * widths[k] * 0.5
					# Off the drawn ground (past the map's edge, where the curve
					# runs in) is no water's.
					if not _rig._grounds.has(Vector2i(edge.round())):
						continue
					var signed := _rig._curve_near(edge).x
					if absf(signed) < 0.02 and absf(_rig.shore_at(edge) - 0.5) > 0.125:
						off_edge.append(edge)
					for out: float in [-0.6, -0.3, 0.3, 0.6]:
						var p := edge + normal * side * out
						var sd := _rig._curve_near(p).x
						if absf(sd) < 0.15 or not _rig._grounds.has(Vector2i(p.round())):
							continue
						curve_points += 1
						if (_rig.shore_at(p) > 0.5) != (sd > 0.0):
							crossed.append(p)
		if not _rig._curve_waters.is_empty():
			_check(curve_points > 100 and crossed.is_empty() and off_edge.is_empty(),
					"%s: a curve's water drawn from the curve, in or out by its distance (%d points; wrong: %s; edge off a half: %s)"
					% [name, curve_points, crossed.slice(0, 3), off_edge.slice(0, 3)])
		if not bool(level["terrain"].get("relief_given", false)):
			_check(not wet.is_empty() and _rig._shore_heights.is_empty() and _rig._stream_ribbons.is_empty() and _rig.stream_falls.is_empty(),
					"%s (no relief): its ground drawn whole, its water's edge the shaders', no ribbon" % name)
			continue
		# Drawn finer only in the band: water and land in its 3 x 3.
		var outside := []
		for cell: Vector2i in _rig._shore_heights:
			var water := false
			var land := false
			for y in range(-1, 2):
				for x in range(-1, 2):
					var near := cell + Vector2i(x, y)
					if _rig._grounds.has(near):
						water = water or wet.has(near) or _rig._bed_levels.has(near)
						land = land or not (wet.has(near) or _rig._bed_levels.has(near))
			if not (water and land) and not _rig._curve_cells.has(cell):
				outside.append(cell)
		_check(not _rig._shore_heights.is_empty() and outside.is_empty(),
				"%s: %d shore cells drawn finer, each by water and land (outside: %s)" % [name, _rig._shore_heights.size(), outside.slice(0, 4)])
		# Each finer point in the mesh, _height_in its height; on its edge the
		# cell beside it meets it there (no gap).
		var drawn: Dictionary = {}
		for mesh: ArrayMesh in _rig._ground_meshes:
			for point: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				drawn[Vector3i(roundi(point.x * Client3D.SHORE_RES), roundi(point.z * Client3D.SHORE_RES), roundi(point.y * 1000.0))] = true
		var row := Client3D.SHORE_RES + 1
		var unmet := []
		var gaps := []
		for cell: Vector2i in _rig._shore_heights:
			var fine: PackedFloat32Array = _rig._shore_heights[cell]
			for y in row:
				for x in row:
					var point := Vector2(cell) - Vector2(0.5, 0.5) + Vector2(x, y) / Client3D.SHORE_RES
					var height := fine[y * row + x]
					var key := Vector3i(roundi(point.x * Client3D.SHORE_RES), roundi(point.y * Client3D.SHORE_RES), roundi(height * 1000.0))
					if not drawn.has(key) or absf(_rig._height_in(cell, point) - height) > 0.0001:
						unmet.append([cell, x, y])
					if x != 0 and y != 0 and x != Client3D.SHORE_RES and y != Client3D.SHORE_RES:
						continue
					var side := Vector2i(-1 if x == 0 else 1 if x == Client3D.SHORE_RES else 0, -1 if y == 0 else 1 if y == Client3D.SHORE_RES else 0)
					for next: Vector2i in [cell + Vector2i(side.x, 0), cell + Vector2i(0, side.y)]:
						if next == cell or not _rig._corners.has(next):
							continue
						# As the cell beside draws it: a whole cell's corners with
						# water all round sunk WATER_BED_DEPTH (a finer cell's
						# heights have it already). A cliff splits them on
						# purpose: a face drawn there.
						var sink := PackedFloat32Array()
						for c in 4:
							var sunk := true
							for a in 4:
								var round_it: Vector2i = next + Client3D.GROUND_CORNERS[c] + Client3D.SHORE_AROUND[a]
								var index: int = _rig._grounds.get(round_it, -1)
								sunk = sunk and index >= _rig._ground_floor_end and index < _rig._ground_water_end
							sink.append(Client3D.WATER_BED_DEPTH if sunk and not _rig._shore_heights.has(next) else 0.0)
						var f := (point - Vector2(next) + Vector2(0.5, 0.5)).clamp(Vector2.ZERO, Vector2.ONE)
						var theirs := _rig._height_in(next, point) - lerpf(lerpf(sink[0], sink[1], f.x), lerpf(sink[2], sink[3], f.x), f.y)
						if absf(theirs - height) > 0.0001 and not Relief.cliff_between(theirs, height):
							gaps.append([cell, next, x, y])
		_check(unmet.is_empty() and gaps.is_empty(),
				"%s: each finer point drawn at its _height_in, the ground beside meeting it (unmet: %s; gaps: %s)" % [name, unmet.slice(0, 3), gaps.slice(0, 3)])
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## The ribbons of [param rig] (decision 557): its stream cells whose middle
## no ribbon triangle covers ("uncovered"), and how many ribbon points run
## against [param down] ("against"; none counted for a zero one).
static func _ribbon_report(rig: Client3D, down: Vector2) -> Dictionary:
	var triangles: Array[PackedVector2Array] = []
	var against := 0
	for ribbon: MeshInstance3D in rig._stream_ribbons:
		var arrays := (ribbon.mesh as ArrayMesh).surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for t in range(0, indices.size(), 3):
			var flat := PackedVector2Array()
			for k in 3:
				flat.append(Vector2(points[indices[t + k]].x, points[indices[t + k]].z))
			triangles.append(flat)
		for colour: Color in colours:
			if down != Vector2.ZERO and Vector2(colour.r * 2.0 - 1.0, colour.g * 2.0 - 1.0).dot(down) < 0.0:
				against += 1
	# Each triangle filed under the cells its box spans, so a cell's middle
	# is tried against the few near it (756: the 224 hills' rivers made every
	# cell against every triangle seconds of the suite's limit).
	var near: Dictionary[Vector2i, Array] = {}
	for flat: PackedVector2Array in triangles:
		var low := Vector2i(floori(minf(flat[0].x, minf(flat[1].x, flat[2].x))), floori(minf(flat[0].y, minf(flat[1].y, flat[2].y))))
		var high := Vector2i(ceili(maxf(flat[0].x, maxf(flat[1].x, flat[2].x))), ceili(maxf(flat[0].y, maxf(flat[1].y, flat[2].y))))
		for y in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1):
				if not near.has(Vector2i(x, y)):
					near[Vector2i(x, y)] = []
				near[Vector2i(x, y)].append(flat)
	var uncovered := []
	for cell: Vector2i in rig._stream_cells:
		var middle := Vector2(cell)
		var inside := false
		for flat: PackedVector2Array in near.get(cell, []):
			if Geometry2D.point_is_inside_triangle(middle, flat[0], flat[1], flat[2]):
				inside = true
				break
		if not inside:
			uncovered.append(cell)
	return {"uncovered": uncovered, "against": against}


## A solid building's cells (decision 550: the barrow's mound on the wilds)
## drawn as land of the level's own kind, so the round mound sits on its
## grass, not on the forest's floor in a square round it.
func _test_solid_ground() -> void:
	print("
== solid ground: a solid building's cells drawn as the level's own ground ==")
	var wilds := Level.load_level("wilds")
	var terrain: Dictionary = wilds["terrain"]
	_rig.rebuild(terrain, wilds["centre"])
	var solid: Array = terrain.get("solid", [])
	var kinds: Dictionary = terrain["kinds"]
	var wrong := []
	for cell: Vector2i in solid:
		var index: int = _rig._grounds.get(cell, -1)
		if index < 0 or index >= _rig._ground_floor_end or _rig._ground_kinds.get(cell, "") != str(kinds.get(cell, "stone")):
			wrong.append([cell, index, _rig._ground_kinds.get(cell, ""), kinds.get(cell, "")])
	_check(not solid.is_empty() and wrong.is_empty(),
			"the mound's %d solid cells drawn as land of the level's kind (%s; wrong: %s)" % [solid.size(), kinds.get(solid[0] if not solid.is_empty() else Vector2i.ZERO, ""), wrong.slice(0, 3)])
	_rig.rebuild(_main._terrain, Vector2i.ZERO)

## Roads drawn from their curves (563, terrain's side): the road's field
## over a half on its curve and under it past its edge, its edge at a half;
## its cells drawn as the ground round them (never the road's kind by
## cell); no scatter on the road; a level without roads none.
func _test_roads() -> void:
	print("\n== roads: drawn from their curves, not their cells ==")
	for name: String in ["hills", "wilds"]:
		var level := Level.load_level(name)
		var terrain: Dictionary = level["terrain"]
		_rig.rebuild(terrain, level["centre"])
		if (terrain.get("roads", []) as Array).is_empty():
			_check(_rig._road_curves.is_empty() and _rig.road_at(Vector2(level["centre"])) == 0.0, "%s: no roads, no road drawn" % name)
			continue
		var on := 0
		var wrong := []
		var off_edge := []
		for road: Dictionary in _rig._road_curves:
			var points: PackedVector2Array = road["curve"]["points"]
			var widths: PackedFloat32Array = road["curve"]["widths"]
			var tangents: PackedVector2Array = road["curve"]["tangents"]
			for k in range(0, points.size(), 3):
				if not _rig._grounds.has(Vector2i(points[k].round())):
					continue
				var normal := Vector2(-tangents[k].y, tangents[k].x)
				on += 1
				if _rig.road_at(points[k]) < 0.5:
					wrong.append(points[k])
				for side: float in [-1.0, 1.0]:
					var edge := points[k] + normal * side * widths[k] * 0.5
					# On ground (a bridge's deck is no ground cell, as its middle's skipped above).
					if _rig._grounds.has(Vector2i(edge.round())) and absf(_rig._road_near(edge).x) < 0.02 and absf(_rig.road_at(edge) - 0.5) > 0.13:
						off_edge.append(edge)
					var past := points[k] + normal * side * (widths[k] * 0.5 + 0.6)
					if _rig._road_near(past).x < -0.5 and _rig.road_at(past) > 0.5:
						wrong.append(past)
		_check(on > 20 and wrong.is_empty() and off_edge.is_empty(),
				"%s: a road's field from its curve (%d points; wrong: %s; edge off a half: %s)" % [name, on, wrong.slice(0, 3), off_edge.slice(0, 3)])
		var kinds: Dictionary = terrain["kinds"]
		var by_cell := []
		for cell: Vector2i in _rig._road_cells:
			if _rig._grounds.get(cell, -1) >= 0 and _rig._grounds[cell] < _rig._ground_floor_end and _rig._ground_kinds.get(cell, "") != _rig._road_kind_round(cell, kinds):
				by_cell.append(cell)
		_check(not _rig._road_cells.is_empty() and by_cell.is_empty(), "%s: a road's cells drawn as the ground round them (%d cells; not: %s)" % [name, _rig._road_cells.size(), by_cell.slice(0, 3)])
		if name == "wilds":
			# 563 amended (1): Umbrage's roads start inside its cobbled square;
			# their cells there are drawn as cobble, and the shader lays a dirt
			# road only off stone, so the road stops at the cobble's edge.
			var cobbled := []
			for cell: Vector2i in _rig._road_cells:
				if _rig._ground_kinds.get(cell, "") == "stone" and _rig.road_at(Vector2(cell)) > 0.5:
					cobbled.append(cell)
			# The cells with only road round them (where Umbrage's roads meet its
			# square) are cobble too, not grass.
			for cell: Vector2i in [Vector2i(189, 192), Vector2i(200, 192), Vector2i(189, 211), Vector2i(200, 211)]:
				if not _rig._road_cells.has(cell) or _rig._ground_kinds.get(cell, "") != "stone":
					cobbled.clear()
			var code := (load("res://client3d/ground.gdshaderinc") as ShaderInclude).code
			_check(not cobbled.is_empty() and code.contains("float off_stone = 1.0 - smoothstep(0.3, 0.7, weights.b);")
					and code.contains("smoothstep(0.42, 0.58, road.r + worn) * off_stone"),
					"wilds: a dirt road's cells in the square drawn as cobble, those with only road round them too (%d, e.g. %s), its dirt never laid over stone" % [cobbled.size(), cobbled.slice(0, 3)])
		var on_road := []
		for chunk: Vector2i in _rig._scatter_chunks:
			for kind: String in _rig._scatter_plan(chunk):
				for item: Array in _rig._scatter_plan(chunk)[kind]:
					if _rig._road_near(item[1]).x > 0.0:
						on_road.append(item[1])
		_check(on_road.is_empty(), "%s: no scatter on a road (%s)" % [name, on_road.slice(0, 3)])
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## levels/hills (decision 358; relief since 525, drawn from its whole
## levels until terrain's side reads metres): every ledge between two of
## its cells is a rock face, at many levels.
func _test_hills() -> void:
	print("
== hills: a rock face down every cliff, smooth slopes everywhere else ==")
	var hills := Level.load_level("hills")
	var terrain: Dictionary = hills["terrain"]
	_rig.rebuild(terrain, hills["centre"])
	var faces: Dictionary = {}
	for edge: Array in _rig._cliff_edges:
		faces[edge] = true
	var stairs: Dictionary = terrain["stairs"]
	var floor_cells: Dictionary = {}
	for cell: Vector2i in terrain["floor"]:
		floor_cells[cell] = true
	# A ledge is where the sim's rule says a step is a cliff (decision 525):
	# each has its face; a walkable step down (a slope) has none.
	var missing := []
	# A cliff step whose drawn corners agree on the edge (no drawn step):
	# counted apart, under a metre, until terrain's 585 side draws every face
	# from the ledge's curve (its tops and feet, not the corners).
	var flattened := []
	var corner_sides := {
		Vector2i(1, 0): [[1, 3], [0, 2]], Vector2i(-1, 0): [[2, 0], [3, 1]],
		Vector2i(0, 1): [[3, 2], [1, 0]], Vector2i(0, -1): [[0, 1], [2, 3]],
	}
	var on_slopes := []
	var ledges := 0
	var slopes := 0
	# A ford's or the water's bank is a lip down to its bed: not a slope's.
	var wet: Array = terrain.get("water", []) + terrain.get("fords", []) + terrain.get("bridged", [])
	for cell: Vector2i in floor_cells:
		var here := _rig._elevation(cell)
		for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := cell + direction
			if not floor_cells.has(next) or _rig._elevation(next) >= here - Relief.EPSILON or stairs.get(next) == -direction 					or wet.has(cell) or wet.has(next):
				continue
			if Relief.cliff_between(here, _rig._elevation(next)):
				ledges += 1
				if not faces.has([cell, direction]):
					var own := _rig._corner_heights(cell)
					var theirs := _rig._corner_heights(next)
					var pair: Array = corner_sides[direction]
					if absf(own[pair[0][0]] - theirs[pair[1][0]]) <= Relief.EPSILON and absf(own[pair[0][1]] - theirs[pair[1][1]]) <= Relief.EPSILON:
						flattened.append([cell, direction, snappedf(here - _rig._elevation(next), 0.01)])
					else:
						missing.append([cell, direction])
			else:
				slopes += 1
				if faces.has([cell, direction]):
					on_slopes.append([cell, direction])
	_check(ledges > 0 and missing.is_empty(), "a face down each of the %d cliff steps (missing: %s; flattened by the corners: %s)" % [ledges, missing.slice(0, 5), flattened])
	# What reads as a slope must be climbable (585): the lay softens a
	# cliff step under a metre, so no step is left for the corners to flatten.
	_check(flattened.is_empty(), "no cliff step the corners draw as a slope (%s)" % [flattened])
	_check(slopes > ledges * 4 and on_slopes.is_empty(),
			"and none on the %d steps down a walkable slope: hills, not terraces (faces there: %s)" % [slopes, on_slopes.slice(0, 5)])
	# On relief the ground casts its shadow; a level without relief's doesn't.
	var casting := func() -> Array:
		var settings := []
		for drawn: Node in _rig._room.get_children():
			if drawn is MeshInstance3D and String(drawn.name).begins_with("Ground_"):
				settings.append((drawn as MeshInstance3D).cast_shadow)
		return settings
	var on_hills: Array = casting.call()
	# The castle has no relief (the wilds have, since 565).
	var wilds := Level.load_level("castle")
	_rig.rebuild(wilds["terrain"], wilds["centre"])
	var on_wilds: Array = casting.call()
	_check(not on_hills.is_empty() and on_hills.all(func(s: int) -> bool: return s == GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
			and not on_wilds.is_empty() and on_wilds.all(func(s: int) -> bool: return s == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF),
			"the hills' ground casts its shadow (%d chunks), the castle's (no relief) doesn't (%d)" % [on_hills.size(), on_wilds.size()])


func _test_heights() -> void:
	print("\n== heights: a stair is a ramp the ground runs up, a ledge a rock face, marks lie on the slope ==")
	var sample := Level.load_level("sample")
	var terrain: Dictionary = sample["terrain"]
	var stairs: Dictionary = terrain["stairs"]
	_check(not stairs.is_empty(), "the sample has stairs (%d)" % stairs.size())
	if stairs.is_empty():
		return
	_rig.rebuild(terrain, sample["centre"])
	var stair: Vector2i = stairs.keys()[0]
	var up: Vector2i = stairs[stair]
	# In metres (decision 525): the stair's ground and the cell it climbs to.
	var low := _rig._elevation(stair)
	var high := _rig._elevation(stair + up)
	if high <= low + Relief.EPSILON:
		high = low + Client3D.LEVEL_RISE
	var middle := _rig._ground_height(Vector2(stair))
	_check(middle > low + 0.1 and middle < high - 0.1
			and absf(_rig._ground_height(Vector2(stair) - Vector2(up) * 0.49) - low) < 0.15
			and absf(_rig._ground_height(Vector2(stair) + Vector2(up) * 0.49) - high) < 0.06,
			"a puppet on a stair stands on its ramp: part way up at its middle, at the cell above at its top edge (%.2f between %.2f and %.2f)" % [middle, low, high])
	# The ramp's high corners are the upper cell's: one vertex shared.
	var shared := false
	var stair_index: int = _rig._grounds[stair]
	var upper_index: int = _rig._grounds.get(stair + up, -1)
	for vertex in _rig._vertex_chunk.size():
		var around := Array(_rig._vertex_cells.slice(vertex * 4, vertex * 4 + 4))
		if around.has(stair_index) and around.has(upper_index):
			shared = true
	_check(upper_index >= 0 and shared, "the ramp's top meets the cell above it, no step between")
	# No rock face where the sim walks: between cells at one height with no
	# wall, or a stair and the cell it climbs to.
	var heights: Dictionary = terrain["heights"]
	var walked := []
	for edge: Array in _rig._cliff_edges:
		var from: Vector2i = edge[0]
		var direction: Vector2i = edge[1]
		var to := from + direction
		if not _rig._grounds.has(to) or terrain["edges"].get(Terrain.edge_key(from, direction), Terrain.Edge.OPEN) == Terrain.Edge.WALL:
			continue
		# A shore's lip over the water is a face (decision 525: shores stand
		# over the surface); the water is not walked.
		var wet: Array = terrain.get("water", []) + terrain.get("fords", []) + terrain.get("bridged", [])
		if wet.has(from) or wet.has(to):
			continue
		# Walked: no cliff between them by the sim's own rule (decision 525).
		if not Relief.cliff_between(_rig._elevation(from), _rig._elevation(to)) or stairs.get(from) == direction or stairs.get(to) == -direction:
			walked.append(edge)
	_check(not _rig._cliff_edges.is_empty() and walked.is_empty(),
			"a rock face only on a ledge, none where the sim walks (%d faces; on walked edges: %s)" % [_rig._cliff_edges.size(), walked])
	# A ramp's side: the cell beside it at the stair's height shares the
	# ramp's raised corner (one vertex for the stair, the cell above, and it).
	var welded := 0
	var sides := 0
	for side: Vector2i in [Vector2i(up.y, up.x), -Vector2i(up.y, up.x)]:
		var beside := stair + side
		if not _rig._grounds.has(beside) or absf(_rig._elevation(beside) - low) > Relief.EPSILON:
			continue
		sides += 1
		var wanted := [stair_index, upper_index, _rig._grounds[beside]]
		for vertex in _rig._vertex_chunk.size():
			var around := Array(_rig._vertex_cells.slice(vertex * 4, vertex * 4 + 4))
			if wanted.all(func(index: int) -> bool: return around.has(index)):
				welded += 1
				break
	_check(sides > 0 and welded == sides, "beside the ramp the ground slopes up with it, welded at its corner (%d of %d sides)" % [welded, sides])
	_check(not _rig._room.find_children("Cliffs_*", "MeshInstance3D", false, false).is_empty()
			and _rig._room.find_children("Stair_*", "", false, false).is_empty()
			and _rig._room.find_children("Cliff_*", "", false, false).is_empty(),
			"ledges are rock faces, a mesh a chunk; no stone boxes, no steps")
	# The faces under the sky's light as the ground (513 amended): dark at
	# night, as before indoors.
	var sky_was := _rig._sky_floor
	_rig._set_sky_floor(Client3D.FLOOR_DARKEST)
	var night: Variant = _rig._cliff_material.get_shader_parameter("sky_floor")
	_rig._set_sky_floor(0.0)
	var indoors: Variant = _rig._cliff_material.get_shader_parameter("sky_floor")
	_rig._set_sky_floor(sky_was)
	_check(is_equal_approx(night, Client3D.FLOOR_DARKEST) and is_equal_approx(indoors, 1.0)
			and FileAccess.get_file_as_string("res://client3d/cliff.gdshader").contains("pow(sky_floor, 2.2)"),
			"a cliff face takes the ground's sky light (%s at night, %s indoors)" % [night, indoors])
	_rig.hover(stair, true)
	_check(absf(_rig._hover.position.y - _rig._ground_height(Vector2(stair))) < 0.05 and _rig._hover.basis.y.y < 0.995
			and _rig._hover.basis.y.dot(Vector3(up.x, 0.0, up.y)) < 0.0,
			"the hover outline lies on the ramp, tilted with it (leaning back from its top)")
	_rig.hover(stair, false)
	_rig.stand_ring(stair, true)
	_check(_rig._stand_ring.visible and absf(_rig._stand_ring.position.y - _rig._ground_height(Vector2(stair))) < 0.1
			and absf(_rig._stand_ring.position.x - stair.x) < 0.05 and absf(_rig._stand_ring.position.z - stair.y) < 0.05,
			"the stand ring (combat's (c)) lies at the body's feet, tilted with the ramp (%s for %s)" % [_rig._stand_ring.position, stair])
	_rig.stand_ring(stair, false)
	_check(not _rig._stand_ring.visible, "and goes when nobody would be struck")
	_rig.show_builder(Rect2i(stair - Vector2i.ONE, Vector2i(3, 3)), [[stair.x, stair.y, "grass"]])
	var lowest := INF
	var highest := -INF
	for node in _rig._builder_marks.get_children():
		var mesh := (node as MeshInstance3D).mesh
		if mesh is ArrayMesh and node.position == Vector3.ZERO:
			for point: Vector3 in (mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				lowest = minf(lowest, point.y)
				highest = maxf(highest, point.y)
	_check(highest - lowest > (high - low) * 0.9, "a builder ghost on the stair runs up its ramp (%.2f to %.2f)" % [lowest, highest])
	# A height the proposal changes: flat at the new height, lighter the higher (decision 356).
	var beside := stair
	_rig.show_builder(Rect2i(stair - Vector2i.ONE, Vector2i(3, 3)), [], [], Rect2i(), [[beside.x, beside.y, 5]])
	var tops: Array[float] = []
	var colours: Array[Color] = []
	for node in _rig._builder_marks.get_children():
		var mesh := (node as MeshInstance3D).mesh
		if mesh is ArrayMesh and node.position == Vector3.ZERO:
			for point: Vector3 in (mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				tops.append(point.y)
			colours.append(((node as MeshInstance3D).material_override as StandardMaterial3D).albedo_color)
	_check(not tops.is_empty() and tops.all(func(y: float) -> bool: return absf(y - 5 * Client3D.LEVEL_RISE - Client3D.ON_FLOOR * 2.0) < 0.01)
			and colours.size() == 1 and colours[0].v > Client3D.BUILDER_LOW.v,
			"a cell raised to 5 in the ghost: flat at 5, lighter than the ground's tint (%s)" % [colours])
	_rig.clear_builder()
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


func _test_outdoor() -> void:
	print("\n== outdoors: a day sky, and a forest for the outline ==")
	_check(not _rig._outdoor and _rig._environment.background_mode == Environment.BG_COLOR and _rig._trees.is_empty(),
			"the test room is under stone: dark, no sky, no trees")
	var castle := Level.load_level("castle")
	var terrain: Dictionary = castle["terrain"]
	_rig.rebuild(terrain, castle["centre"])
	_check(_rig._outdoor and _rig._environment.background_mode == Environment.BG_SKY
			and _rig._sun.light_energy > 0.5, "the castle is outdoors: under a sky, lit by a day's sun")
	var ambient := _rig._environment.ambient_light_color
	_check(_rig._environment.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR
			and is_equal_approx(ambient.r, ambient.g) and is_equal_approx(ambient.g, ambient.b),
			"its ambient light is neutral, not the sky's green-bottomed colour (%s)" % ambient)
	var water: Array = terrain.get("water", [])
	if not water.is_empty():
		# The bed is the ground's lowest corners; the surface a flat mesh.
		var bed := INF
		for mesh: ArrayMesh in _rig._ground_meshes:
			for point: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				bed = minf(bed, point.y)
		# A body drawn by its cells, or (568 amended: the castle's ponds are
		# curves) a curve's surface.
		# The castle's way out (589): a waystone either side of its link.
		_check(_rig._room.get_node_or_null("Cue_17_23") != null and _rig._room.get_node_or_null("Cue_15_23") != null
				and _rig._room.get_node_or_null("Cue_16_23") == null, "a waystone either side of the castle's way out, its cell clear")
		var drawn: MeshInstance3D = _rig._water_bodies[0] if not _rig._water_bodies.is_empty() else _rig._room.get_node("Water_curve_0")
		var surface: float = (drawn.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX][0].y
		var forest_floor := _rig._room.get_node("ForestFloor") as Node3D
		_check(forest_floor.position.y < bed and bed < surface,
				"its water is drawn above its bed, and both above the forest floor, not hidden under it")
	var land: Dictionary = _rig._land
	# The edge reads closed (decision 575: its trees from its curve, not a
	# tree a cell): along every edge curve, every cell's stretch of it has a
	# tree (or a felled one's stump) within EDGE_CLOSED of it, but by a
	# way's lane.
	const EDGE_CLOSED := 2.2
	var standing: Array[Vector2] = []
	for tree: Node3D in _rig._trees.values():
		standing.append(Vector2(tree.position.x, tree.position.z))
	for wood: Node3D in _rig._room.find_children("Deadwood_*", "", false, false):
		standing.append(Vector2(wood.position.x, wood.position.z))
	var bare: Array[Vector2] = []
	for edge: Dictionary in _rig._edge_curves:
		var points: PackedVector2Array = edge["curve"]["points"]
		for k in range(0, points.size(), 4):
			var by_lane := _rig._glimpse_plans.any(func(plan: Dictionary) -> bool:
				return (plan["cells"] as Dictionary).has(Vector2i(roundi(points[k].x), roundi(points[k].y))) \
						or (plan["cells"] as Dictionary).keys().any(func(cell: Vector2i) -> bool: return Vector2(cell).distance_to(points[k]) < 2.0))
			if not by_lane and not standing.any(func(at: Vector2) -> bool: return at.distance_to(points[k]) < EDGE_CLOSED):
				bare.append(points[k])
	_check(not _rig._trees.is_empty() and not _rig._edge_curves.is_empty() and bare.is_empty(),
			"a tree (or a felled one's stump) within %.1f of every stretch of the forest's edge but a way's lane (%d trees; bare: %s)" % [EDGE_CLOSED, _rig._trees.size(), bare.slice(0, 5)])
	var outline_walls := 0
	var inner_walls := 0
	var edges: Dictionary = terrain["edges"]
	for key: Vector3i in edges:
		if edges[key] != Terrain.Edge.WALL:
			continue
		if _rig._is_outline(key):
			outline_walls += 1 if _rig._walls.has(key) else 0
		else:
			inner_walls += 1 if _rig._walls.has(key) else 0
	_check(outline_walls == 0 and inner_walls > 0, "no wall along the outline; the walls painted inside stand (%d)" % inner_walls)
	_check(_rig._room.get_node_or_null("ForestFloor") != null, "over a forest floor")
	var tree: Node3D = _rig._trees.values()[0]
	_check(tree.scale.x * ArtKit.size(str(tree.get_meta("slot"))).y > 2.5,
			"trees stand taller than a player")
	# Past the forest (326): a canopy to the view's reach and more, never
	# over the land or its first trees, over a far floor.
	var border := _rig._border
	_check(border != null and border.get_parent() == _rig._room, "a border past the forest")
	if border != null:
		border.finish()
		var forest_floor := _rig._room.get_node("ForestFloor") as Node3D
		_check(border.far_floor != null and border.far_floor.position.y < forest_floor.position.y
				and (border.far_floor.mesh as PlaneMesh).size.x > TerrainBorder.FAR * 2.0, "over a far floor, under the forest's, %d m past the map" % TerrainBorder.FAR)
		var canopy: Dictionary[Vector2i, bool] = {}
		var near_land := 0
		var tried := 0
		for chunk: Vector2i in border.chunks:
			var positions: PackedVector3Array = border.chunks[chunk][0]
			for t in range(0, positions.size(), 3):
				var middle := (positions[t] + positions[t + 1] + positions[t + 2]) / 3.0
				var cell := Vector2i(roundi(middle.x), roundi(middle.z))
				canopy[cell] = true
				if (t / 3) % 7 != 0:
					continue
				tried += 1
				var reach := TerrainBorder.START - 2
				for dy in range(-reach, reach + 1):
					for dx in range(-reach, reach + 1):
						if land.has(cell + Vector2i(dx, dy)):
							near_land += 1
		_check(not border.chunks.is_empty() and near_land == 0,
				"its canopy %d cells and more off the land, never over it (%d facets tried)" % [TerrainBorder.START - 1, tried])
		var low := Vector2i(1 << 20, 1 << 20)
		var high := -low
		for cell: Vector2i in land:
			low = low.min(cell)
			high = high.max(cell)
		var middle := (low + high) / 2
		var out := TerrainBorder.REACH - 4
		var ends: Array[Vector2i] = [Vector2i(middle.x, low.y - out), Vector2i(middle.x, high.y + out), Vector2i(low.x - out, middle.y), Vector2i(high.x + out, middle.y)]
		_check(ends.all(func(cell: Vector2i) -> bool: return canopy.has(cell)),
				"reaching %d cells out every way, past what the view and its pan see" % out)
		# The castle's way south (327; to the wilds till 745, the foothills since):
		# past its south edge, three rows of trees with a lane through them, then
		# the foothills' road.
		_check(_rig._glimpses.size() == 1 and _rig._glimpse_plans[0]["to"] == "foothills",
				"a glimpse of the foothills past the castle's way there, none of the test room's dungeon (%s)" % [_rig._glimpse_plans.map(func(plan: Dictionary) -> String: return plan["to"])])
		if _rig._glimpses.size() == 1:
			var plan: Dictionary = _rig._glimpse_plans[0]
			var cells: Dictionary = plan["cells"]
			var on_land := cells.keys().filter(func(cell: Vector2i) -> bool: return land.has(cell)).size()
			var lane := [Vector2i(16, 24), Vector2i(16, 25), Vector2i(16, 26), Vector2i(15, 25), Vector2i(17, 25)]
			_check(on_land == 0 and lane.all(func(cell: Vector2i) -> bool: return cells.has(cell)) and cells.has(Vector2i(16, 29)),
					"none of it on our land; a lane from the link through the trees; the foothills' from_castle (128, 2) across from our link, at (16, 29)")
			var wooded := cells.keys().filter(func(cell: Vector2i) -> bool: return _rig._trees.has(cell)).size()
			var near_tree := func(at: Vector2) -> bool:
				return _rig._trees.values().any(func(tree: Node3D) -> bool: return Vector2(tree.position.x, tree.position.z).distance_to(at) < 1.6)
			_check(wooded == 0 and near_tree.call(Vector2(14, 24)) and near_tree.call(Vector2(18, 24)),
					"no tree on it, the trees either side of the lane")
			var view: Client3D = _rig._glimpses[0]
			_check(view.find_children("*", "Area3D", true, false).is_empty() and not view.is_processing()
					and view._ground_bytes.size() > 0 and Array(view._ground_bytes).all(func(byte: int) -> bool: return true)
					and range(0, view._ground_bytes.size(), view._ground_stride).all(func(at: int) -> bool: return view._ground_bytes[at + view._ground_custom] == 0),
					"nothing in it picked or thought about; its ground lit by our sky alone")
		# Its buildings: those wholly in it, roofed and drawn only.
		var far: Array[Vector2i] = []
		for y in 10:
			for x in 10:
				far.append(Vector2i(x, y))
		var huts: Array[Dictionary] = [{"slot": "building.hut", "rect": Rect2i(2, 2, 3, 3), "facing": Vector2i(0, 1), "use": "forge", "town_id": "x/store"},
			{"slot": "building.hut", "rect": Rect2i(8, 8, 3, 3), "facing": Vector2i(0, 1)}]
		var seen := _rig._glimpse_plan({"kind": "edge", "out": Vector2i(0, 1), "to_ours": Transform2D(0.0, Vector2(500, 500)), "from_cell": Vector2i.ZERO, "to_map": "x"},
				{"floor": far, "buildings": huts}, Vector2i(10, 10), Vector2i(64, 64))
		var shown: Array = seen["terrain"]["buildings"]
		_check(shown.size() == 1 and shown[0]["rect"] == Rect2i(502, 502, 3, 3) and not shown[0].has("use"),
				"a glimpse keeps the buildings wholly in it, moved, with no town (%s)" % [shown])
		var glimpsed := Client3D.new()
		glimpsed._glimpse = true
		_rig._room.add_child(glimpsed)
		glimpsed.set_process(false)
		glimpsed._draw_glimpse(seen["terrain"])
		_check(glimpsed._buildings.size() == 1 and glimpsed._buildings[0]["roof"] != null and (glimpsed._buildings[0]["roof"] as Node3D).visible
				and glimpsed._building_at.is_empty() and glimpsed.find_children("*", "GPUParticlesCollisionBox3D", true, false).is_empty(),
				"drawn roofed, with no inside")
		glimpsed.free()
		var bare_terrain := terrain.duplicate()
		bare_terrain["border"] = "none"
		_rig.rebuild(bare_terrain, castle["centre"])
		_check(_rig._border == null, "and none where level.json says \"border\": \"none\"")
	_rig.rebuild(_main._terrain, Vector2i.ZERO)
	_check(not _rig._outdoor and _rig._trees.is_empty() and _rig._environment.background_mode == Environment.BG_COLOR,
			"and back in the test room, it is under stone again")


## The horizon under the low camera (623, terrain's side): the hills with
## the camera low have a skirt round the forest's bounds, under the crowns
## at its inner edge and up to the treetops and a ridge beyond, shown only
## while the camera is low; the ground's far meadow on with it; off, both
## gone; under stone, no skirt.
## The sky (decision 744): the sun's disc where DayNight has the sun (not
## the shadows' lifted light), the moon opposite with its phase, the stars
## by night only and none in fog, and the cloud layer under the weather's
## cloud, drifting as the shadows do.
func _test_sky() -> void:
	print("\n== the sky: sun, moon, stars, clouds ==")
	var hour_was := DayNight.hour(DayNight.now())
	var weather_was: Dictionary = World.fields.weather.duplicate()
	var hills := Level.load_level("hills")
	_rig.rebuild(hills["terrain"], hills["centre"])
	var sky: ShaderMaterial = _rig._sky_material
	_check(sky != null, "outdoors the sky is the sky shader")
	if sky == null:
		return
	var show := func(hour: float, kind: String) -> void:
		DayNight.set_hour(hour)
		World.fields.weather = Weather.KINDS[kind].duplicate()
		World.fields.weather["wind_dir"] = Vector2.RIGHT
		World.fields.weather["snow"] = 0.0
		_rig._weather_view.weather = World.fields.weather.duplicate()
		_rig._sky_step = -1
		_rig._update_sky(0.0)
	show.call(12.0, "clear")
	var toward: Vector3 = sky.get_shader_parameter("sun_direction")
	var fraction := float(_rig._sky_step) / Client3D.SKY_STEPS
	_check(sky.shader == Client3D.SKY_SHADER and toward.is_equal_approx(_rig._level_direction(DayNight.sun_at(fraction)).normalized())
			and toward.y > 0.5 and (sky.get_shader_parameter("sun_color") as Color).a > 0.99,
			"noon: the sun's disc high, where DayNight has it, shown (%.2f up)" % toward.y)
	_check(float(sky.get_shader_parameter("stars")) == 0.0 and (sky.get_shader_parameter("moon_direction") as Vector3).is_equal_approx(-toward)
			and float(sky.get_shader_parameter("cloud_cover")) == 0.0,
			"no stars by day; the moon opposite the sun; a clear sky has no clouds")
	show.call(0.0, "clear")
	_check(float(sky.get_shader_parameter("stars")) > 0.99 and (sky.get_shader_parameter("sun_color") as Color).a == 0.0
			and (sky.get_shader_parameter("moon_color") as Color).a > 0.9,
			"midnight: the stars out, the sun down, the moon up")
	show.call(0.0, "fog")
	_check(float(sky.get_shader_parameter("stars")) < 0.2 and (sky.get_shader_parameter("moon_color") as Color).a < 0.2,
			"in fog the stars and the moon are hidden")
	show.call(12.0, "fog")
	var foggy := float(sky.get_shader_parameter("cloud_cover"))
	_check(foggy < float(Weather.KINDS["fog"]["cloud"]) * 0.5 or is_zero_approx(float(Weather.KINDS["fog"]["cloud"])),
			"in fog the sky's clouds thin (%.2f of the weather's %.2f)" % [foggy, float(Weather.KINDS["fog"]["cloud"])])
	show.call(12.0, "storm")
	var dark: Color = sky.get_shader_parameter("cloud_color")
	show.call(12.0, "overcast")
	var grey: Color = sky.get_shader_parameter("cloud_color")
	_check(is_equal_approx(float(sky.get_shader_parameter("cloud_cover")), Weather.KINDS["overcast"]["cloud"]) and dark.v < grey.v
			and (sky.get_shader_parameter("cloud_drift") as Vector2) == _rig._weather_view.drift()
			and sky.get_shader_parameter("cloud_noise") == _rig._weather_view.sky_noise(),
			"the clouds as the weather's cloud, darker in a storm, drifting with the shadows, from the shadows' noise")
	var day := float(DayNight.day_steps)
	_check(is_equal_approx(Client3D.moon_phase(0.0), Client3D.MOON_START) and is_zero_approx(Client3D.moon_phase(day * Client3D.MOON_DAYS * 0.5))
			and is_equal_approx(Client3D.moon_phase(day * Client3D.MOON_DAYS), Client3D.MOON_START),
			"a new world's moon full, new half of MOON_DAYS on, full again after MOON_DAYS")
	DayNight.set_hour(hour_was)
	World.fields.weather = weather_was
	_rig._weather_view.weather = weather_was.duplicate()
	_rig._sky_step = -1
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## The low camera's eye kept out of buildings (decision 864): a segment's
## entry into a box; in Umbrage at (178, 229), yaw 135, the eye that stood in
## the inn brought in along its line to stand outside every building, no
## nearer than BOX_PULL_LEAST; on open ground it does not move at
## all; and a walk past the inn at a player's pace (5 cells a second), the
## eye's distance printed each half second, coming in and going out once.
func _test_eye_kept_out() -> void:
	print("\n== the low camera's eye kept out of buildings (864) ==")
	var box := AABB(Vector3.ZERO, Vector3(2.0, 2.0, 2.0))
	_check(is_equal_approx(Client3D.segment_enters(Vector3(-1.0, 1.0, 1.0), Vector3(4.0, 0.0, 0.0), box), 0.25)
			and Client3D.segment_enters(Vector3(-1.0, 3.0, 1.0), Vector3(4.0, 0.0, 0.0), box) == -1.0
			and Client3D.segment_enters(Vector3(-2.0, 1.0, 1.0), Vector3(1.0, 0.0, 0.0), box) == -1.0,
			"a segment enters a box a quarter along; over it, or short of it, it does not")
	var low_was := Net.camera_low
	var yaw_was := _rig.yaw
	Net.set_camera_low(true, false)
	var wilds := Level.load_level("wilds")
	_rig.rebuild(wilds["terrain"], Vector2i(178, 229))
	_rig.zoom = 1.0
	_rig._zoom_to = 1.0
	_rig.pan = Vector3.ZERO
	_rig._ridge_pitch = 0.0
	var ground := func(cell: Vector2) -> Vector3: return Vector3(cell.x, _rig._ground_height(cell), cell.y)
	var in_building := func(eye: Vector3) -> String:
		for building: Dictionary in _rig._buildings:
			var each: AABB = _rig._eye_box(building)
			if each.size != Vector3.ZERO and each.has_point(eye):
				return str(building.get("kind", building.get("slot", "?")))
		return ""
	# Stood at (178, 229), turned to 135: the eye at its full distance is in the inn.
	_rig._set_yaw(135.0)
	_rig.pitch = _rig.normal_pitch()
	_rig._camera_target = ground.call(Vector2(178, 229))
	_rig._box_pull = 1.0
	_rig._box_hold = 0.0
	_rig._place_camera()
	var was_in: String = in_building.call(_rig._camera.position)
	var want := _rig.eye_clear_share()
	for i in 180:
		_rig._ease_box_pull(_rig.eye_clear_share(), 1.0 / 60.0)
	_rig._place_camera()
	var now_in: String = in_building.call(_rig._camera.position)
	var full := Client3D.CAMERA_DISTANCE * Client3D.LOW_DISTANCE_SHARE * _rig._size_factor()
	var distance := _rig._camera.position.distance_to(_rig._camera_target)
	# The figure in frame: feet and head projected inside the screen, 5 % in from each edge.
	var framed := func(feet: Vector3) -> bool:
		var screen := _rig._camera.get_viewport().get_visible_rect().size
		var inner := Rect2(screen * 0.05, screen * 0.9)
		for body_at: Vector3 in [feet, feet + Vector3.UP * Client3D.BOX_PULL_HEAD]:
			if _rig._camera.is_position_behind(_rig.to_global(body_at)) or not inner.has_point(_rig._camera.unproject_position(_rig.to_global(body_at))):
				return false
		return true
	var pull_was: float = _rig._box_pull
	var zoom_was: float = _rig.zoom
	var unframed: Array[String] = []
	for each_zoom: float in [Client3D.LOW_ZOOM_MIN, 1.0]:
		_rig.zoom = each_zoom
		_rig.pitch = _rig.normal_pitch()
		var whole := Client3D.CAMERA_DISTANCE * Client3D.LOW_DISTANCE_SHARE * _rig._size_factor()
		for step in 21:
			_rig._box_pull = lerpf(Client3D.BOX_PULL_LEAST / whole, 1.0, step / 20.0)
			_rig._place_camera()
			if not framed.call(_rig._camera_target):
				unframed.append("%.1f m at zoom %.1f" % [_rig._camera_distance(), each_zoom])
	_rig.zoom = zoom_was
	_rig.pitch = _rig.normal_pitch()
	_rig._box_pull = pull_was
	_rig._place_camera()
	_check(unframed.is_empty(), "at every pull from the full distance down to %.0f m, nearest zoom and full, the player's feet and head stand inside the screen with a margin, the aim risen %.1f m at the nearest (864; cut at %s)" % [Client3D.BOX_PULL_LEAST, Client3D.BOX_PULL_AIM_LIFT, unframed])
	_check(was_in != "" and want < 1.0 and now_in == "" and distance >= Client3D.BOX_PULL_LEAST - 0.01 and distance < full,
			"at (178, 229) yaw 135 the eye stood in the %s; brought in to %.1f m of %.1f (share %.2f), outside every building" % [was_in, distance, full, want])
	# Terrain's walk at the nearest zoom (the coordinator, 11-11): at (207, 200)
	# yaw 45 the eye stood inside a house's eave, the box being the house's
	# meshes and its roof's, overhang and all; at (203, 216) yaw 135 a stall's
	# awning filled the frame, a stall having no roof and so no box. Each
	# piece within 2 m of the eye printed.
	var near_eye := func(eye: Vector3) -> String:
		var names: Array[String] = []
		for building: Dictionary in _rig._buildings:
			var node: Node3D = building.get("node")
			if node == null:
				continue
			var box_all: AABB = _rig.global_transform.affine_inverse() * _rig._bounds(node)
			var roof: Node3D = building.get("roof")
			if roof != null and not node.is_ancestor_of(roof):
				box_all = box_all.merge(_rig.global_transform.affine_inverse() * _rig._bounds(roof))
			if eye.clamp(box_all.position, box_all.end).distance_to(eye) <= 2.0:
				names.append("%s %s (box %s, roof %s, fades %s, stands %s, %.1f m off)" % [building.get("use", ""), building["rect"],
						_rig._eye_box(building).size != Vector3.ZERO, roof != null, building.get("fades", false), building.get("stands", false), eye.clamp(box_all.position, box_all.end).distance_to(eye)])
		return ", ".join(names) if not names.is_empty() else "none"
	var spot_out: Dictionary = {}
	for spot: Array in [[Vector2(207, 200), 45.0, "eave"], [Vector2(203, 216), 135.0, "stall"]]:
		_rig.zoom = Client3D.LOW_ZOOM_MIN
		_rig._zoom_to = Client3D.LOW_ZOOM_MIN
		_rig._set_yaw(spot[1])
		_rig.pitch = _rig.normal_pitch()
		_rig._camera_target = ground.call(spot[0])
		_rig._box_pull = 1.0
		_rig._box_hold = 0.0
		_rig._place_camera()
		var was_box: String = in_building.call(_rig._camera.position)
		var near_before: String = near_eye.call(_rig._camera.position)
		for i in 180:
			_rig._ease_box_pull(_rig.eye_clear_share(), 1.0 / 60.0)
		_rig._place_camera()
		var now_box: String = in_building.call(_rig._camera.position)
		var off_box := INF
		for building: Dictionary in _rig._buildings:
			var each_box: AABB = _rig._eye_box(building)
			if each_box.size != Vector3.ZERO:
				off_box = minf(off_box, _rig._camera.position.clamp(each_box.position, each_box.end).distance_to(_rig._camera.position))
		spot_out[spot[2]] = now_box if now_box != "" or off_box >= Client3D.BOX_PULL_MARGIN - 0.05 else "%.2f m off a box" % off_box
		print("  %s at %s yaw %.0f, nearest zoom: eye %.1f m (share %.2f), in a box before: %s, after: %s; within 2 m before: %s; after: %s" % [spot[2], spot[0],
				spot[1], _rig._camera.position.distance_to(_rig._camera_target), _rig._box_pull, was_box if was_box != "" else "no", now_box if now_box != "" else "no",
				near_before, near_eye.call(_rig._camera.position)])
	_rig.zoom = zoom_was
	_rig._zoom_to = zoom_was
	_rig.pitch = _rig.normal_pitch()
	_check(spot_out["eave"] == "", "at (207, 200) yaw 45, nearest zoom, the eye stands outside the forge's box, its roof's overhang in it, and at least the margin off it (864; %s)" % spot_out["eave"])
	# Open ground: the cell nearest (214, 244) with no building within 26 cells; at any yaw the eye never moves.
	var open := Vector2i(-1, -1)
	var best := INF
	for y in range(224, 265):
		for x in range(194, 235):
			var cell := Vector2i(x, y)
			var clear := true
			for building: Dictionary in _rig._buildings:
				if Vector2((building["rect"] as Rect2i).get_center()).distance_to(Vector2(cell)) < 26.0:
					clear = false
					break
			if clear and Vector2(cell).distance_to(Vector2(214, 244)) < best:
				best = Vector2(cell).distance_to(Vector2(214, 244))
				open = cell
	var moved := 0
	for turn: float in [0.0, 90.0, 180.0, 270.0]:
		_rig._set_yaw(turn)
		_rig._camera_target = ground.call(Vector2(open))
		_rig._box_pull = 1.0
		_rig._place_camera()
		var before := _rig._camera.position
		for i in 60:
			_rig._ease_box_pull(_rig.eye_clear_share(), 1.0 / 60.0)
		_rig._place_camera()
		if _rig._box_pull != 1.0 or _rig._camera.position != before:
			moved += 1
	_check(open != Vector2i(-1, -1) and moved == 0, "on open ground at %s the eye does not move at all, four yaws (%d moved)" % [open, moved])
	# A walk past the inn along the south-west road, yaw 135, at 5 cells a second: the eye's distance each half second.
	_rig._set_yaw(135.0)
	_rig._box_pull = 1.0
	_rig._box_hold = 0.0
	var floor := {}
	for cell: Vector2i in wilds["terrain"]["floor"]:
		floor[cell] = true
	var nearest := func(to: Vector2i) -> Vector2i:
		for r in 6:
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if floor.has(to + Vector2i(dx, dy)):
						return to + Vector2i(dx, dy)
		return to
	var start: Vector2i = nearest.call(Vector2i(178, 236))
	# To the inn's far corner, not on to the temple: a second building's own
	# pull in is not the eye pumping past this one (864's BOX_PULL_LEAST).
	var goal: Vector2i = nearest.call(Vector2i(178, 202))
	var came := {start: start}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size() and not came.has(goal):
		var c: Vector2i = queue[head]
		head += 1
		for d: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)]:
			if floor.has(c + d) and not came.has(c + d):
				came[c + d] = c
				queue.append(c + d)
	var walk: Array[Vector2] = []
	if came.has(goal):
		var back := goal
		while back != start:
			walk.push_front(Vector2(back))
			back = came[back]
		walk.push_front(Vector2(start))
	print("  walk from %s to %s, %d cells" % [start, goal, walk.size()])
	var step := 1.0 / 60.0
	var seconds := 0.0
	var along := 0.0
	var last_row := -1.0
	var rows: Array[float] = []
	var inside_frames := 0
	var cut_frames := 0
	while walk.size() > 1 and along < walk.size() - 1:
		var k := floori(along)
		var at: Vector2 = walk[k].lerp(walk[mini(k + 1, walk.size() - 1)], along - k)
		_rig._camera_target = ground.call(at)
		_rig._ease_box_pull(_rig.eye_clear_share(), step)
		_rig._place_camera()
		if not framed.call(_rig._camera_target):
			cut_frames += 1
		var where: String = in_building.call(_rig._camera.position)
		if where != "":
			inside_frames += 1
		if seconds - last_row >= 0.5 - 0.0001:
			last_row = seconds
			var gap := _rig._camera.position.distance_to(_rig._camera_target)
			rows.append(gap)
			print("  walk %.1f s at (%.1f, %.1f): eye %.1f m (share %.2f)%s" % [seconds, at.x, at.y, gap, _rig._box_pull, (" in " + where) if where != "" else ""])
		seconds += step
		along += 5.0 * step
	# Pumping: the distance turning from falling to rising, or back, by over half a metre a row.
	var turns := 0
	var going := 0
	for i in range(1, rows.size()):
		var change := rows[i] - rows[i - 1]
		if absf(change) < 0.5:
			continue
		var sign_now := 1 if change > 0.0 else -1
		if going != 0 and sign_now != going:
			turns += 1
		going = sign_now
	_check(cut_frames == 0, "on the walk the player's feet and head (%.1f m) stay inside the screen with a margin at every pull (%d frames cut) (864)" % [Client3D.BOX_PULL_HEAD, cut_frames])
	_check(rows.size() >= 10 and turns <= 1,
			"a walk past the inn: the eye comes in and goes back out once at most (%d turns in %d rows, %d frames still inside a box)" % [turns, rows.size(), inside_frames])
	_rig._box_pull = 1.0
	_rig._set_yaw(yaw_was)
	Net.set_camera_low(low_was, false)
	_rig._apply_camera_mode()


## A doorway's leaves fade with the near wall (864, maps' still inside the
## temple, x_inside_temple_shows_doors.png): inside Umbrage's temple at
## (194, 201), the camera to the west, the near side faded takes the west
## doors' frame and both leaves; from outside, before the doors, neither.
func _test_doors_fade_inside() -> void:
	print("\n== a doorway's leaves fade with the near wall (864) ==")
	var wilds := Level.load_level("wilds")
	_rig.rebuild(wilds["terrain"], Vector2i(194, 201))
	var west := Vector3(-1.0, 0.6, 0.0).normalized()
	var inside := _rig.to_global(Vector3(194.0, _rig._ground_height(Vector2(194, 201)) + 1.0, 201.0))
	var outside := _rig.to_global(Vector3(186.0, _rig._ground_height(Vector2(186, 201)) + 1.0, 201.0))
	var leaves: Array[Node3D] = []
	var frames: Array[Node3D] = []
	for key: Vector3i in _rig._doorways:
		if key.z != Terrain.EAST or key.x != 189 or key.y < 199 or key.y > 204:
			continue
		var door: Node3D = _rig._doorways[key].get_node(^"Door")
		if not frames.has(door.get_node(^"Body")):
			frames.append(door.get_node(^"Body"))
		for leaf in door.get_children():
			if str(leaf.name).begins_with("leaf") and not leaves.has(leaf):
				leaves.append(leaf)
	var faded_in := _rig._inside_walls([inside] as Array[Vector3], west)
	_check(leaves.size() == 2 and frames.size() == 1 and leaves.all(func(leaf: Node3D) -> bool: return faded_in.has(leaf)) and faded_in.has(frames[0]),
			"inside the temple, the camera west: the west doors' frame and both leaves fade with the near side (%d leaves, %d frames)" % [leaves.size(), frames.size()])
	# From the street, nobody inside: at every yaw the closed doors stay as built.
	var ghosted := 0
	for turn in 8:
		var toward := Vector3(1.0, 0.0, 1.0).normalized().rotated(Vector3.UP, deg_to_rad(turn * 45.0))
		toward = (toward + Vector3(0.0, 0.6, 0.0)).normalized()
		var faded_out := _rig._inside_walls([outside] as Array[Vector3], toward)
		if leaves.any(func(leaf: Node3D) -> bool: return faded_out.has(leaf)):
			ghosted += 1
	_check(leaves.size() == 2 and ghosted == 0, "from the street, nobody inside, the closed doors stay solid at all eight yaws (%d ghosted)" % ghosted)
	# An open leaf fades and comes back with its run as a shut one does.
	if leaves.size() == 2:
		var leaf: Node3D = leaves[0]
		leaf.rotation.y = PI * 0.5
		var open_in := _rig._inside_walls([inside] as Array[Vector3], west).has(leaf)
		# The leaf itself may be the mesh (art-kit's leaves are), as _set_near reads it.
		var meshes: Array = _rig._descendants(leaf).filter(func(node: Node) -> bool: return node is MeshInstance3D and (node as MeshInstance3D).mesh != null)
		var before: Array = meshes.map(func(mesh: MeshInstance3D) -> Array: return [mesh.material_override, mesh.get_surface_override_material(0)])
		_rig._set_near(leaf, true)
		var faded := false
		for k in meshes.size():
			var mesh: MeshInstance3D = meshes[k]
			if mesh.material_override != before[k][0] or mesh.get_surface_override_material(0) != before[k][1]:
				faded = true
		_rig._set_near(leaf, false)
		var back := true
		for k in meshes.size():
			var mesh: MeshInstance3D = meshes[k]
			if mesh.material_override != before[k][0] or mesh.get_surface_override_material(0) != before[k][1]:
				back = false
		leaf.rotation.y = 0.0
		_check(open_in and meshes.size() > 0 and faded and back, "an open leaf is in the near side too, fades and comes back as built (%d meshes)" % meshes.size())


func _test_horizon() -> void:
	print("\n== the horizon under the low camera: the forest's skirt, the far meadow ==")
	var low_was := Net.camera_low
	Net.set_camera_low(true, false)
	var hills := Level.load_level("hills")
	_rig.rebuild(hills["terrain"], hills["centre"])
	var skirt: MeshInstance3D = _rig._skirt
	var bounds := AABB()
	var inner := INF
	var outer := -INF
	if skirt != null:
		bounds = skirt.mesh.get_aabb()
		var points: PackedVector3Array = skirt.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var rows := Client3D.SKIRT_ROWS.size()
		for i in range(0, points.size(), rows):
			inner = minf(inner, points[i].y)
			outer = maxf(outer, points[i + rows - 1].y)
	var forest := Rect2()
	var first := true
	for cell: Vector2i in _rig._forest_distance:
		if first:
			forest = Rect2(Vector2(cell), Vector2.ZERO)
			first = false
		forest = forest.expand(Vector2(cell))
	_check(skirt != null and skirt.visible and skirt.get_parent() == _rig._room and skirt.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			and bounds.position.x < forest.position.x - Client3D.SKIRT_WIDE + 1.0 and bounds.end.x > forest.end.x + Client3D.SKIRT_WIDE - 1.0
			and inner < _rig._ground_bottom and outer > Client3D.SKIRT_TOP - Client3D.SKIRT_BUMPS,
			"a skirt round the forest out SKIRT_WIDE, from under the crowns (%.1f) up past the treetops (%.1f), no shadows" % [inner, outer])
	# Its top faces up (Godot's front winds clockwise: (c - a) x (b - a)), its
	# underside the same faces wound back: wound down, the top was culled and
	# the ridge's undersides floated over the horizon as grey slabs.
	var up := 0
	var down := 0
	var wrong := 0
	if skirt != null:
		var arrays := skirt.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var faces: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var half := faces.size() / 2
		for f in range(0, faces.size(), 3):
			var a := vertices[faces[f]]
			var facing := (vertices[faces[f + 2]] - a).cross(vertices[faces[f + 1]] - a)
			if absf(facing.y) < 1e-6:
				continue
			# Past the bounds only: inside a corner the fan's rows under the
			# crowns (SKIRT_IN) fold over themselves, unseen.
			var inside := false
			for g in 3:
				var at := vertices[faces[f + g]]
				inside = inside or forest.grow(0.6).has_point(Vector2(at.x, at.z))
			if inside:
				continue
			if (facing.y > 0.0) == (f < half):
				if f < half:
					up += 1
				else:
					down += 1
			else:
				wrong += 1
	_check(up > 0 and up == down and wrong == 0,
			"the skirt's top faces up, its underside drawn too (%d up, %d down, %d wrong)" % [up, down, wrong])
	_check(is_equal_approx(float(_rig._ground_look.get_shader_parameter("far_meadow")), 1.0)
			and is_equal_approx(float(_rig._ground_look.get_shader_parameter("far_from")), _rig.scatter_reach_low - Client3D.FAR_MEADOW_FADE * 0.5),
			"the far meadow on, from the scatter's reach")
	var sky: ShaderMaterial = _rig._sky_material
	_check(sky != null and sky.get_shader_parameter("ground_horizon_color") == sky.get_shader_parameter("sky_horizon_color")
			and sky.get_shader_parameter("sky_horizon_color") == _rig._sky_horizon and sky.get_shader_parameter("ground_bottom_color") == Client3D.FOREST_FLOOR
			and is_equal_approx(float(sky.get_shader_parameter("ground_curve")), Client3D.LOW_SKY_GROUND_CURVE),
			"the sky just below the horizon the haze's colour (no forest floor band under the skyline), the rest the forest floor")
	# The border canopy kept from between the low camera and the player (326
	# amended): its own material cuts it within CANOPY_EYE_CUT of the camera,
	# and nothing else in the room draws with that cut.
	var canopy_cut := func() -> Array:
		var border: TerrainBorder = _rig._border
		if border == null:
			return [-1.0, [], 0]
		border.finish()
		var sheet := border.get_children().filter(func(node: Node) -> bool: return node.name.begins_with("Canopy_"))
		var cut := -1.0
		var off_shader: Array[String] = []
		for piece: Node in sheet:
			var look := (piece as MeshInstance3D).material_override as ShaderMaterial
			if look == null or look.shader != TerrainBorder.EYE_CUT_SHADER:
				off_shader.append(str(piece.name))
			else:
				cut = float(look.get_shader_parameter("eye_cut"))
		# Nothing else but the forest's trees, saplings and near stands
		# (326 amended (2)): each of theirs cut, its see-through copy too, at the
		# canopy's cut; one of each kind at least on the wilds.
		var others := 0
		var kinds := {}
		var tree_cuts := {}
		for node: Node in _rig._room.find_children("*", "MeshInstance3D", true, false):
			if str(node.name).begins_with("Canopy_"):
				continue
			var owner_name := ""
			var climb: Node = node
			while climb != null and climb != _rig._room:
				for kind: String in ["Tree_", "Sapling_", "Stand_"]:
					if str(climb.name).begins_with(kind):
						owner_name = kind
				climb = climb.get_parent()
			var mesh := node as MeshInstance3D
			var looks: Array[Material] = [mesh.material_override]
			if mesh.mesh != null:
				for surface in mesh.mesh.get_surface_count():
					looks.append(mesh.get_surface_override_material(surface))
			for look: Material in looks:
				var shader_look := look as ShaderMaterial
				if shader_look == null or shader_look.shader != TerrainBorder.EYE_CUT_SHADER:
					continue
				if owner_name == "":
					others += 1
					continue
				kinds[owner_name] = true
				var near: ShaderMaterial = shader_look.get_meta(Client3D.SEASON_NEAR_META) as ShaderMaterial if shader_look.has_meta(Client3D.SEASON_NEAR_META) else null
				tree_cuts[float(shader_look.get_shader_parameter("eye_cut"))] = true
				if near == null or near.shader != Client3D.EYE_CUT_NEAR_SHADER:
					tree_cuts[-2.0] = true
				else:
					tree_cuts[float(near.get_shader_parameter("eye_cut"))] = true
		return [cut, off_shader, others, sheet.size(), kinds.keys(), tree_cuts.keys()]
	var cut_low: Array = canopy_cut.call()
	_check(cut_low.size() == 6 and int(cut_low[3]) > 0 and (cut_low[1] as Array).is_empty() and is_equal_approx(float(cut_low[0]), Client3D.CANOPY_EYE_CUT) and int(cut_low[2]) == 0,
			"the canopy past the wood's edge not drawn within %.0f m of the low camera, on its own material and no other's but the forest's (%s)" % [Client3D.CANOPY_EYE_CUT, cut_low])
	_check(cut_low.size() == 6 and (cut_low[5] as Array).all(func(metres: float) -> bool: return is_equal_approx(metres, Client3D.CANOPY_EYE_CUT)),
			"and the forest's pieces in their cut copies cut as the canopy, their see-through copies too (326 amended (2); %s)" % [cut_low.slice(4) if cut_low.size() == 6 else cut_low])
	# Near only (326 amended (2)): a piece in its cut copy only while its
	# foot is within CANOPY_EYE_CUT + EYE_CUT_REACH of the camera; the near
	# fade's kept materials swapped with it, so a fade puts back the right one.
	var drawn_shader := func(piece: Node3D) -> Shader:
		for node: Node in piece.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if mesh.mesh != null:
				var look := mesh.get_active_material(0) as ShaderMaterial
				return look.shader if look != null else null
		return null
	var eye_cut_wrong := func() -> Array:
		var reach := Client3D.CANOPY_EYE_CUT + Client3D.EYE_CUT_REACH
		var eye := _rig._camera.global_position - _rig._room.global_position
		var on := 0
		var miscut: Array[String] = []
		for bucket: Array in _rig._eye_cut_buckets.values():
			for piece: Node3D in bucket:
				var near_eye := Vector2(piece.position.x - eye.x, piece.position.z - eye.z).length() <= reach and _rig._low
				var cut_now := false
				for node: Node in piece.find_children("*", "MeshInstance3D", true, false):
					var mesh := node as MeshInstance3D
					for surface in (mesh.mesh.get_surface_count() if mesh.mesh != null else 0):
						var look := mesh.get_active_material(surface) as ShaderMaterial
						cut_now = cut_now or (look != null and look.shader in [Client3D.EYE_CUT_SHADER, Client3D.EYE_CUT_NEAR_SHADER])
				if near_eye:
					on += 1
				if near_eye != cut_now or near_eye != _rig._eye_cut_on.has(piece):
					miscut.append(str(piece.name))
		return [on, miscut]
	var probe: Node3D = null
	for piece: Node3D in _rig._trees.values():
		if str(piece.name).begins_with("Tree_") and drawn_shader.call(piece) in [Client3D.SEASON_SHADER, Client3D.EYE_CUT_SHADER]:
			probe = piece
			break
	var steps: Array = []
	if probe != null:
		var put_eye := func(offset: Vector3) -> void:
			_rig._camera.global_position = probe.global_position + offset
			_rig._update_eye_cut()
		put_eye.call(Vector3(0.0, 7.5, 0.0))
		steps.append(eye_cut_wrong.call())
		steps.append(drawn_shader.call(probe) == Client3D.EYE_CUT_SHADER)
		_rig._set_near(probe, true)
		steps.append(drawn_shader.call(probe) == Client3D.EYE_CUT_NEAR_SHADER)
		put_eye.call(Vector3(Client3D.CANOPY_EYE_CUT + Client3D.EYE_CUT_REACH + 3.0, 7.5, 0.0))
		steps.append(drawn_shader.call(probe) == Client3D.SEASON_NEAR_SHADER)
		_rig._set_near(probe, false)
		steps.append(drawn_shader.call(probe) == Client3D.SEASON_SHADER)
		steps.append(eye_cut_wrong.call())
		put_eye.call(Vector3(0.5, 7.5, 0.0))
		steps.append(drawn_shader.call(probe) == Client3D.EYE_CUT_SHADER)
		_rig._set_near(probe, true)
		_rig._set_near(probe, false)
		steps.append(drawn_shader.call(probe) == Client3D.EYE_CUT_SHADER)
		_rig._place_camera()
	_check(probe != null and steps.size() == 8 and int(steps[0][0]) > 0 and (steps[0][1] as Array).is_empty() and steps[1] and steps[2]
			and steps[3] and steps[4] and (steps[5][1] as Array).is_empty() and steps[6] and steps[7],
			"near only: a tree in its cut copy by the camera and in season away from it, the rest as their distance says; faded, its see-through copy follows, and the fade puts back the right one (%s)" % [steps])
	Net.set_camera_low(false, false)
	_rig._apply_camera_mode()
	_check(skirt != null and not skirt.visible and is_equal_approx(float(_rig._ground_look.get_shader_parameter("far_meadow")), 0.0)
			and sky.get_shader_parameter("ground_horizon_color") == Client3D.FOREST_FLOOR.lightened(0.2)
			and is_equal_approx(float(sky.get_shader_parameter("ground_curve")), Client3D.SKY_GROUND_CURVE),
			"the camera high: the skirt hidden, the far meadow off, the sky's ground the forest floor's again")
	var cut_high: Array = canopy_cut.call()
	_check(cut_high.size() == 6 and is_equal_approx(float(cut_high[0]), 0.0) and (cut_high[4] as Array).is_empty() and _rig._eye_cut_on.is_empty(),
			"and drawn whole under the high camera, the forest's in their season materials (%s)" % [cut_high])
	Net.set_camera_low(true, false)
	var barrow := Level.load_level("barrow")
	_rig.rebuild(barrow["terrain"], barrow["centre"])
	_check(_rig._skirt == null and _rig._room.get_node_or_null("Skirt") == null, "under stone no skirt")
	Net.set_camera_low(low_was, false)
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## Far landmarks under the low camera (650, terrain's side): from the hills
## the castle and the tower over the mine, each at its true place on maps'
## world plane or pulled in along its line to FAR_DRAW and scaled by as
## much (the same on screen), shifting as the camera moves, hazed toward
## the sky's horizon by their true distance; none with the camera high,
## none under stone, none on a cell the view draws itself (the castle from
## inside the castle).
func _test_far_landmarks() -> void:
	print("\n== far landmarks under the low camera (650, terrain's side) ==")
	var plane := Level.world_plane()
	var castle_mark: Dictionary = {}
	for mark: Dictionary in Client3D.far_landmarks(plane, "wilds", {}):
		if mark["id"] == "castle":
			castle_mark = mark
	var wilds_zone: Dictionary = plane["zones"]["wilds"]
	var castle_at := Vector2i(128, -12)
	var castle_base := 0.0
	for mark: Dictionary in plane["landmarks"]:
		if mark["id"] == "castle":
			castle_at = mark["at"]
			castle_base = mark["base"]
	_check(not castle_mark.is_empty() and (castle_mark["at"] as Vector3).is_equal_approx(Vector3(castle_at.x - wilds_zone["origin"].x,
			castle_base - float(wilds_zone["height"]), castle_at.y - wilds_zone["origin"].y)),
			"from the wilds the castle at its world cell less the wilds' origin, its base less the wilds' height")
	_check(Client3D.far_landmarks(plane, "barrow", {}).is_empty(), "a level with no place on the plane has none")
	var drawn := {Vector2i(castle_at - (wilds_zone["origin"] as Vector2i)): true}
	_check(Client3D.far_landmarks(plane, "wilds", drawn).all(func(mark: Dictionary) -> bool: return mark["id"] != "castle"),
			"a landmark on a cell the view draws itself is left to it")
	var castle_size: Vector2i = WorldMap.build().areas["castle"]["size"]
	_check(Client3D.far_landmarks(plane, "wilds", {}, {"castle": castle_size}).all(func(mark: Dictionary) -> bool: return mark["id"] != "castle"),
			"nor one in a level this one links to (the castle from the wilds)")
	_check(is_equal_approx(Client3D.far_shrink(Vector3(0, 10, 0), Vector3(100, 0, 0), 20.0, 45.0), 1.0)
			and is_equal_approx(Client3D.far_shrink(Vector3(0, 10, 0), Vector3(100, 0, 0), 20.0, 0.0), 0.5),
			"far_shrink: whole when it fits under the top, else down to the room there is")
	var low_was := Net.camera_low
	Net.set_camera_low(true, false)
	var hills := Level.load_level("hills")
	_rig.rebuild(hills["terrain"], hills["centre"])
	_rig._place_camera()
	var root: Node3D = _rig._far_root
	var ids: Array = _rig._far_marks.map(func(mark: Dictionary) -> String: return String((mark["node"] as Node).name))
	_check(root != null and root.visible and root.get_parent() == _rig._room and ids.has("Far_castle") and ids.has("Far_tower_over_the_mine"),
			"from the hills, low: the castle and the tower over the mine (%s)" % [ids])
	var eye: Vector3 = _rig._camera.position
	var forward: Vector3 = -_rig._camera.global_transform.basis.z
	var top_edge: float = rad_to_deg(asin(forward.y)) + _rig._camera.fov * 0.5
	var placed := true
	var shares := {}
	for mark: Dictionary in _rig._far_marks:
		var node: Node3D = mark["node"]
		var at: Vector3 = mark["at"]
		var distance := eye.distance_to(at)
		var drawn_at := eye.distance_to(node.position)
		placed = placed and (node.position - eye).normalized().is_equal_approx((at - eye).normalized())
		var shrink := Client3D.far_shrink(eye, at, mark["height"], top_edge - Client3D.FAR_TOP_MARGIN)
		placed = placed and is_equal_approx(drawn_at, minf(distance, Client3D.FAR_DRAW)) and is_equal_approx(node.scale.x, drawn_at / distance * shrink)
		# Its top no higher than the frame's top edge, less the margin.
		var top := at + Vector3.UP * float(mark["height"]) * shrink
		var rise := rad_to_deg(atan2(top.y - eye.y, Vector2(top.x - eye.x, top.z - eye.z).length()))
		placed = placed and (rise <= top_edge - Client3D.FAR_TOP_MARGIN + 0.01 or is_equal_approx(shrink, Client3D.FAR_SHRINK_MOST))
		var geometry: GeometryInstance3D = mark["meshes"][0]
		shares[String(node.name)] = Client3D.far_haze(float(geometry.get_instance_shader_parameter("true_distance")),
				_rig._environment.fog_depth_begin, _rig._environment.fog_depth_end)
		placed = placed and is_equal_approx(float(geometry.get_instance_shader_parameter("true_distance")), distance)
		placed = placed and geometry.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and geometry.material_override == _rig._far_material
	_check(placed, "each on its true line from the camera, no further than FAR_DRAW and scaled by as much, shrunk to keep its top in frame (top edge %.1f degrees); no shadows" % top_edge)
	# 650 amended (3): each stands on its hill, FAR_FOOT_SINK deep under its
	# foot and wider than the piece, hazed by the piece's own distance.
	var feet: Array[String] = []
	for mark: Dictionary in _rig._far_marks:
		var node: Node3D = mark["node"]
		var foot := node.get_node_or_null("FarFoot") as MeshInstance3D
		var body: GeometryInstance3D = mark["meshes"][0]
		var piece_box: AABB = body.get_aabb()
		var foot_box: AABB = foot.get_aabb() if foot != null else AABB()
		if (foot != null and (mark["meshes"] as Array).has(foot) and foot.material_override == _rig._far_material
				and foot.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				and Color(foot.get_instance_shader_parameter("body")).is_equal_approx(Client3D.FAR_FOOT_BODY)
				and is_equal_approx(float(foot.get_instance_shader_parameter("true_distance")), float(body.get_instance_shader_parameter("true_distance")))
				and is_equal_approx(foot_box.position.y, -Client3D.FAR_FOOT_SINK) and absf(foot_box.end.y) < 0.01
				and foot_box.size.x > piece_box.size.x and foot_box.size.z > piece_box.size.z
				and float(mark["height"]) > 0.0 and is_equal_approx(float(mark["height"]), piece_box.end.y)):
			feet.append(String(node.name))
	_check(feet.size() == _rig._far_marks.size() and feet.size() > 0,
			"each far landmark on its hill, %.0f m deep under its foot, wider than it, in the far material, hazed by its own distance, its height still the piece's (%s)" % [Client3D.FAR_FOOT_SINK, feet])
	# More sky on screen: nearer true size, with no code change.
	var fov_was: float = _rig._camera.fov
	var tower: Dictionary = {}
	for mark: Dictionary in _rig._far_marks:
		if String((mark["node"] as Node).name) == "Far_tower_over_the_mine":
			tower = mark
	var small: float = (tower["node"] as Node3D).scale.x if not tower.is_empty() else 0.0
	_rig._camera.fov = 100.0
	_rig._place_far_landmarks()
	var grown: float = (tower["node"] as Node3D).scale.x if not tower.is_empty() else 0.0
	_rig._camera.fov = fov_was
	_rig._place_far_landmarks()
	_check(not tower.is_empty() and grown > small * 1.5, "with more sky on screen the tower is drawn nearer its true size (%.3f to %.3f)" % [small, grown])
	_check(shares.get("Far_tower_over_the_mine", 0.0) > shares.get("Far_castle", 1.0) and shares.get("Far_tower_over_the_mine", 1.0) < 1.0
			and shares.get("Far_castle", 1.0) < 0.5,
			"the far tower more hazed than the castle, both seen; the castle reads (%s)" % [shares])
	_check(_rig._far_material.get_shader_parameter("haze") == _rig._environment.fog_light_color
			and is_equal_approx(float(_rig._far_material.get_shader_parameter("depth_end")), _rig._environment.fog_depth_end),
			"their haze the scene fog's colour, on its curve")
	# 623 amended (3): one curve with the land's own haze to the hand-over,
	# lighter past it; full at the fog's end only for what is no landmark.
	var b := _rig._environment.fog_depth_begin
	var e := _rig._environment.fog_depth_end
	var at_hand := Client3D.far_haze(Client3D.FAR_HAND_OVER, b, e)
	_check(is_equal_approx(Client3D.far_haze(60.0, b, e), clampf((60.0 - b) / (e - b), 0.0, 1.0))
			and absf(Client3D.far_haze(Client3D.FAR_HAND_OVER + 0.01, b, e) - at_hand) < 0.001
			and Client3D.far_haze(e + 50.0, b, e) < 0.6,
			"a far piece's haze the land's own to the hand-over, no step there, lighter past the land's edge (%.3f at %.0f m)" % [Client3D.far_haze(e + 50.0, b, e), e + 50.0])
	# The camera moved sideways: the castle seen along another line.
	var castle_node: Node3D = root.get_node_or_null("Far_castle")
	var before := (castle_node.position - eye).normalized() if castle_node != null else Vector3.ZERO
	var target_was: Vector3 = _rig._camera_target
	_rig._camera_target += Vector3(40, 0, 0)
	_rig._place_camera()
	var after := (castle_node.position - _rig._camera.position).normalized() if castle_node != null else Vector3.ZERO
	_check(castle_node != null and before.angle_to(after) > deg_to_rad(1.0), "walked 40 m the castle shifts against the sky (%.1f degrees)" % rad_to_deg(before.angle_to(after)))
	_rig._camera_target = target_was
	Net.set_camera_low(false, false)
	_rig._apply_camera_mode()
	_check(not root.visible, "the camera high: none drawn")
	Net.set_camera_low(true, false)
	# By the live plane and links, not by name (maps' layout steps move both:
	# 745 has the castle reached through the foothills): the far castle drawn
	# exactly where the castle isn't this level or one it links to, and then
	# at its plane spot; the tower far off from each.
	var world := WorldMap.build()
	var plane_castle: Dictionary = {}
	for mark: Dictionary in plane["landmarks"]:
		if mark["id"] == "castle":
			plane_castle = mark
	for level_name: String in ["wilds", "castle", "foothills"]:
		if not Level.names().has(level_name) or not plane["zones"].has(level_name):
			continue
		var level := Level.load_level(level_name)
		_rig.rebuild(level["terrain"], level["centre"])
		var by := level_name == "castle" or world.ways_from(level_name).any(func(way: Dictionary) -> bool: return way["to"] == "castle")
		var far_castle: Node3D = _rig._far_root.get_node_or_null("Far_castle") if _rig._far_root != null else null
		var spot_ok := true
		if far_castle != null:
			var zone: Dictionary = plane["zones"][level_name]
			var expected := Vector3((plane_castle["at"] as Vector2i).x - (zone["origin"] as Vector2i).x, float(plane_castle["base"]) - float(zone["height"]),
					(plane_castle["at"] as Vector2i).y - (zone["origin"] as Vector2i).y)
			spot_ok = _rig._far_marks.any(func(mark: Dictionary) -> bool: return mark["node"] == far_castle and (mark["at"] as Vector3).is_equal_approx(expected))
		_check(_rig._far_root != null and (far_castle == null) == by and spot_ok and _rig._far_root.get_node_or_null("Far_tower_over_the_mine") != null,
				"from the %s: the far castle %s; the tower far off" % [level_name,
				"left to the real one (it is the castle or links to it)" if by else "drawn at its plane spot"])
	var barrow := Level.load_level("barrow")
	_rig.rebuild(barrow["terrain"], barrow["centre"])
	_check(_rig._far_root == null, "under stone none")
	Net.set_camera_low(low_was, false)
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## The low-horizon camera trial (decision 623): Net.camera_low makes the
## outdoor view a perspective one, 22 degrees up and half the distance off,
## seeing the sky through haze; under stone the ortho view stays; off
## restores it exactly; what is clicked or drawn stays within NEAR_TILES.
func _test_low_camera() -> void:
	print("\n== the low-horizon camera (623): outdoors on the toggle, under stone never ==")
	var low_was := Net.camera_low
	var pitch_was: float = _rig.pitch
	var far_was: float = _rig._camera.far
	Net.set_camera_low(true, false)
	_check(not _rig.low_camera() and _rig._camera.projection == Camera3D.PROJECTION_ORTHOGONAL and is_equal_approx(_rig.pitch, pitch_was),
			"the test room is under stone: the toggle leaves it ortho at the usual pitch")
	var castle := Level.load_level("castle")
	var terrain: Dictionary = castle["terrain"]
	_rig.rebuild(terrain, castle["centre"])
	_check(_rig.low_camera() and _rig._camera.projection == Camera3D.PROJECTION_PERSPECTIVE
			and is_equal_approx(_rig._camera.fov, Client3D.LOW_FOV) and is_equal_approx(_rig._camera.far, Client3D.LOW_FAR)
			and is_equal_approx(_rig.pitch, Client3D.low_pitch_at(_rig.zoom)),
			"the castle outdoors: perspective, LOW_FOV, LOW_FAR, the wheel's low pitch (%s %.0f %.0f %.0f)" % [_rig._camera.projection, _rig._camera.fov, _rig._camera.far, _rig.pitch])
	_rig._ridge_pitch = 0.0  # The castle's ridge rule (525) lifts it otherwise; the flat's numbers here.
	var offset: Vector3 = _rig._camera_offset()
	_check(is_equal_approx(offset.length(), Client3D.CAMERA_DISTANCE * Client3D.LOW_DISTANCE_SHARE)
			and is_equal_approx(rad_to_deg(asin(offset.normalized().y)), Client3D.low_pitch_at(1.0)),
			"half the distance off, the wheel's low pitch above the ground (%.1f, %.1f)" % [offset.length(), rad_to_deg(asin(offset.normalized().y))])
	var look_fog: float = _rig.canopied_look(_rig.weathered_look(_rig.seasoned_look(_rig._look, Season.at(World.fields.region, DayNight.now())), _rig._weather_view.weather),
			_rig._canopy_cover * World.fields.canopy_shade / DayNight.CANOPY_SHADE)["fog_density"]
	_check(_rig._environment.fog_mode == Environment.FOG_MODE_DEPTH and _rig._environment.fog_depth_end <= Client3D.LOW_EDGE
			and _rig._environment.fog_depth_begin <= Client3D.LOW_CLEAR and _rig._environment.fog_depth_begin < _rig._environment.fog_depth_end
			and is_equal_approx(_rig._environment.fog_aerial_perspective, Client3D.LOW_AERIAL)
			and _rig._environment.background_mode == Environment.BG_SKY,
			"depth haze, clear out to at most LOW_CLEAR and full by LOW_EDGE, LOW_AERIAL of the sky in it, the day's sky behind (%.0f to %.0f m; look %.4f)" % [_rig._environment.fog_depth_begin, _rig._environment.fog_depth_end, look_fog])
	_check(_rig._sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			and is_equal_approx(_rig._sun.directional_shadow_max_distance, Client3D.LOW_SHADOW_DISTANCE),
			"the sun's shadows out to LOW_SHADOW_DISTANCE in two splits")
	_check(is_equal_approx(_rig._view_reach(), World.NEAR_TILES), "the view's reach for shadows and puppets is NEAR_TILES")
	var aim := Vector2(_rig._camera_target.x, _rig._camera_target.z)
	var near := aim + Vector2(3.0, 4.0)
	var far_off := aim + Vector2(60.0, 80.0)
	var held: Vector2 = _rig.within_near(far_off)
	_check(_rig.within_near(near) == near and is_equal_approx(held.distance_to(aim), World.NEAR_TILES)
			and is_equal_approx((held - aim).angle(), (far_off - aim).angle()),
			"a far click lands NEAR_TILES out along its line; a near one where it is")
	# 623 amended (2): a tall piece with no walls (Level.FADES_ON_LINE, indoors and below ground: a throne) fades on the line as a tree does.
	var stall := MeshInstance3D.new()
	stall.mesh = BoxMesh.new()
	_rig._room.add_child(stall)
	_rig._buildings.append({"rect": Rect2i(0, 0, 1, 1), "node": stall, "roof": null, "off": false, "fades": "building.throne" in Level.FADES_ON_LINE})
	_rig._index_occluders()
	_check(_rig._occluders.any(func(entry: Array) -> bool: return entry[0] == stall) and "building.woodpile" not in Level.FADES_ON_LINE,
			"a throne is one of the pieces that fade on the line to the player; a woodpile is not")
	# Jeff: "basic landmarks such as the barrows and signs shouldnt go transparent": outdoors they hide, never fade.
	var landmark := MeshInstance3D.new()
	landmark.mesh = SphereMesh.new()  # Radius 0.5, at the room's origin.
	_rig._room.add_child(landmark)
	_rig._buildings.append({"rect": Rect2i(0, 0, 1, 1), "node": landmark, "roof": null, "off": false,
		"fades": "building.waystone" in Level.FADES_ON_LINE, "stands": "building.waystone" in Client3D.STANDS_IN_VIEW})
	_rig._index_occluders()
	var standing: Array = _rig._occluders.filter(func(entry: Array) -> bool: return entry[0] == landmark)
	_check(standing.size() == 1 and (standing[0][3] as Array).is_empty()
			and Level.FADES_ON_LINE.all(func(kind: String) -> bool: return kind not in Client3D.STANDS_IN_VIEW)
			and ["building.mound", "building.waystone", "building.well", "tree.great_oak"].all(func(kind: String) -> bool: return kind not in Level.FADES_ON_LINE),
			"an outdoor landmark (a waystone, a barrow's mound) hides the player but has nothing to fade")
	var at := landmark.global_position
	var shapes: Array = standing[0][4] if standing.size() == 1 and standing[0].size() > 4 else []
	var corner_from := at + Vector3(-1.0, 0.45, 0.45)
	var corner_to := at + Vector3(1.0, 0.45, 0.45)
	_check(Client3D.shapes_meet(shapes, at + Vector3(-1, 0, 0), at + Vector3(1, 0, 0))
			and not Client3D.shapes_meet(shapes, corner_from, corner_to)
			and (standing[0][1] as AABB).intersects_segment(corner_from, corner_to) != null,
			"a landmark hides along a line through its own shape, not over its box's empty corner")
	_rig._buildings.pop_back()
	landmark.queue_free()
	_rig._index_occluders()
	var faded_stall: Dictionary[Node3D, bool] = {stall: true}
	var far_off_camera: bool = _rig._close_pieces(faded_stall).is_empty()
	stall.global_position = _rig._camera.global_position + Vector3(2.0, -1.0, 0.0)
	_rig._index_occluders()
	var close: Dictionary = _rig._close_pieces(faded_stall)
	_rig._set_close(stall, true)
	var hidden := not stall.visible
	_rig._set_close(stall, false)
	_check(far_off_camera and close.has(stall) and hidden and stall.visible,
			"faded within NEAR_CLOSE of the low camera, it is hidden (a season tree's see-through shader takes no transparency: the pale peaks), and back (623 amended (2))")
	_rig._buildings.pop_back()
	_rig._index_occluders()
	_rig._hid_at.erase(stall)
	_rig._faded.erase(stall)
	_rig._faded_close.erase(stall)
	_rig._fade_key = ""
	stall.queue_free()
	var sky: Vector2 = _rig.sky_grid(Vector3(0.6, 0.3, 0.8))
	_check(is_equal_approx(sky.distance_to(aim), World.NEAR_TILES) and is_equal_approx((sky - aim).angle(), Vector2(0.6, 0.8).angle())
			and is_nan(_rig.sky_grid(Vector3.UP).x),
			"a click on the sky lands at the NEAR_TILES edge the cursor's way (623 amended (2))")
	# The bodies' slides under the low camera, and a body back from far off
	# (623's hotfix, v0.1.169: the far block's restart lines had slipped
	# under the low camera's, so a near body was caught up to its tile
	# every frame with the camera on, and a body back from far off never
	# ran again with it off).
	# (World still holds the test room: a room tile within NEAR_TILES of the castle's centre.)
	var near_tile := Vector2i(9, 4)
	var slider := _spawn_imp(near_tile)
	var mid_slide := Iso.grid_to_local(Vector2(near_tile) + Vector2(0.4, 0.0))
	slider.position = mid_slide
	_rig._sync_puppets()
	_check(slider.position == mid_slide and slider.is_processing() and _rig._puppets[slider.get_instance_id()].visible,
			"a near body mid-slide keeps its slide under the low camera (not caught up to its tile each frame)")
	var far_tile := Vector2i(roundi(aim.x) + 60, roundi(aim.y) + 80)
	slider.tile = far_tile
	slider.position = Iso.grid_to_local(Vector2(far_tile))
	_rig._sync_puppets()
	_check(_rig._far.has(slider.get_instance_id()) and not slider.is_processing(), "gone far off, it is not drawn or run")
	slider.tile = near_tile
	slider.position = Iso.grid_to_local(Vector2(near_tile))
	for i in Client3D.FAR_EVERY:
		_rig._sync_puppets()
		await get_tree().process_frame
	_check(not _rig._far.has(slider.get_instance_id()) and slider.is_processing() and slider.position == Iso.grid_to_local(Vector2(near_tile)),
			"back near, it runs again, shown where it is")
	World.despawn(slider)
	_rig._sync_puppets()
	_rig.zoom = 0.9
	_rig._apply_size()
	var zoomed: Vector3 = _rig._camera_offset()
	_check(is_equal_approx(zoomed.length(), Client3D.CAMERA_DISTANCE * Client3D.LOW_DISTANCE_SHARE * 0.9), "the wheel moves the camera nearer, not the (unused) ortho size")
	# 623 amended (2): nearer is flatter, LOW_PITCH_NEAR at the nearest, LOW_PITCH at the farthest.
	_rig.zoom = Client3D.LOW_ZOOM_MIN
	_rig._apply_size()
	var near_pitch: float = _rig.pitch
	var near_off: float = _rig._camera_offset().length()
	_rig.zoom = Client3D.ZOOM_MAX
	_rig._apply_size()
	_check(is_equal_approx(near_pitch, Client3D.LOW_PITCH_NEAR) and is_equal_approx(_rig.pitch, Client3D.LOW_PITCH)
			and is_equal_approx(near_off, Client3D.CAMERA_DISTANCE * Client3D.LOW_DISTANCE_SHARE * Client3D.LOW_ZOOM_MIN)
			and Client3D.low_pitch_at(0.6) > Client3D.LOW_PITCH_NEAR and Client3D.low_pitch_at(0.6) < Client3D.LOW_PITCH,
			"the wheel tilts the low camera: %.0f° at %.1f units, %.0f° at the farthest (623 amended (2))" % [near_pitch, near_off, _rig.pitch])
	_rig.zoom = 1.0
	_rig._apply_size()
	var height := _rig.get_viewport().get_visible_rect().size.y
	_rig.begin_pan()
	_rig.pan_by(Vector2(height, 0.0))
	_check(is_equal_approx(_rig.pan.length(), minf(_rig._view_height(), Client3D.PAN_MAX))
			and _rig._view_height() < Client3D.CAMERA_DISTANCE,
			"a drag of the screen's height pans the frustum's height at the aim (%.1f)" % _rig._view_height())
	_rig.end_pan()
	_rig.pan = Vector3.ZERO
	var overhead_was: bool = Net.camera_overhead
	_rig.set_overhead(true)
	_rig._ease_tilt(10.0)
	_check(is_equal_approx(_rig.pitch, Client3D.OVERHEAD_PITCH), "W under the low camera: overhead too (671; %.0f)" % _rig.pitch)
	_rig.set_overhead(false)
	_rig._ease_tilt(10.0)
	_check(is_equal_approx(_rig.pitch, Client3D.low_pitch_at(_rig.zoom)), "and S, back to the wheel's low pitch (%.0f)" % _rig.pitch)
	_rig.zoom = Client3D.LOW_ZOOM_MIN
	_rig._apply_size()
	_check(is_equal_approx(_rig.pitch, Client3D.LOW_PITCH_NEAR), "and the wheel tilts it again from there (%.0f)" % _rig.pitch)
	_rig.set_overhead(true)
	_rig._ease_tilt(10.0)
	_rig.zoom = 1.0
	_rig._apply_size()
	_check(is_equal_approx(_rig.pitch, Client3D.OVERHEAD_PITCH), "overhead, the wheel leaves the pitch be (%.0f)" % _rig.pitch)
	_rig.set_overhead(false)
	_rig._ease_tilt(10.0)
	_rig.indoor_view = true
	_rig.inside_changed.emit(true, Rect2i(0, 0, 4, 4))
	_rig._ease_tilt(1.0)
	_check(_rig.indoors and is_equal_approx(_rig.pitch, Client3D.INSIDE_PITCH), "indoors under the low camera: top-down too (671 amended (4); %.0f)" % _rig.pitch)
	_rig.inside_changed.emit(false, Rect2i())
	_rig._fade_clock += Client3D.INSIDE_LEAVE_HOLD * 2.0
	_rig._update_indoors()
	_rig.indoor_view = false
	Net.camera_overhead = overhead_was
	Net.set_camera_low(false, false)
	_check(not _rig.low_camera() and _rig._camera.projection == Camera3D.PROJECTION_ORTHOGONAL and is_equal_approx(_rig._camera.far, far_was)
			and is_equal_approx(_rig.pitch, Client3D.CAMERA_PITCH) and is_equal_approx(_rig._environment.fog_aerial_perspective, 0.0)
			and is_equal_approx(_rig._environment.fog_density, look_fog)
			and _rig._sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL
			and is_equal_approx(_rig._sun.directional_shadow_max_distance, Client3D.SHADOW_DISTANCE)
			and is_equal_approx(_rig._camera_offset().length(), Client3D.CAMERA_DISTANCE),
			"Off: the ortho view exactly as before (far, pitch, haze, shadows, distance)")
	Net.set_camera_low(low_was, false)
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## Outdoors the camera turns to keep the player in view (801): behind a
## house from the camera, nothing fades for the line to them; hidden past
## HIDE_SECONDS, it turns to the nearest yaw within TURN_MOST of the one
## they set that shows them whole (a sine out), the walk keys going by the
## yaw it set off from meanwhile, and stays (saved); the player's own turn
## stops one at once and holds it; with the turning off (or no yaw within
## reach clearing them) nothing fades either (623 amended (5)): their rim
## shows through.
func _test_camera_turn() -> void:
	print("
== outdoors the camera turns to keep you in view (801) ==")
	const CameraTurn := preload("res://client3d/camera_turn.gd")
	var symmetric := func(degrees: float) -> bool: return absf(degrees - 30.0) < 20.0
	var pick := CameraTurn.choose(30.0, symmetric, CameraTurn.looking(15.0), 30.0)
	var none := CameraTurn.choose(30.0, func(_degrees: float) -> bool: return false, Vector2.ZERO, 30.0)
	var only_far := func(degrees: float) -> bool: return degrees == -60.0
	_check(pick == 15.0 and CameraTurn.choose(30.0, symmetric, Vector2.ZERO, 30.0) == 45.0 and is_nan(none)
			and CameraTurn.choose(0.0, func(degrees: float) -> bool: return degrees == -45.0, Vector2.ZERO, 0.0) == -45.0
			and is_nan(CameraTurn.choose(0.0, only_far, Vector2.ZERO, 0.0)) and CameraTurn.choose(-30.0, only_far, Vector2.ZERO, -30.0) == -60.0,
			"the nearest clearing yaw, 15 degrees a step, within 45 of the one they set; of two as near, the one looking the way they walk (%s); none: NAN" % pick)
	var player := _player()
	var companion := _companion()
	var spawned_her: Companion = null
	if companion == null:
		# Wren for the hidden-companion check (623 amended (5)), as _test_inside_is_his has one.
		spawned_her = EntityFactory.build({"script": "res://sim/companion.gd", "shape": "capsule", "name": "TurnWren", "props": {"max_hp": 10}}) as Companion
		spawned_her.keeper_peer = Net.local_id
		for cell: Vector2i in [player.tile + Vector2i(3, 0), player.tile + Vector2i(0, 3), player.tile + Vector2i(-3, 0), player.tile + Vector2i(0, -3)]:
			if World.is_walkable(cell) and World.get_entity_at(cell) == null and World.spawn(spawned_her, cell):
				companion = spawned_her
				break
	_rig.rebuild(_building_terrain(), Vector2i(7, 7))
	_rig._process(0.0)  # Her puppet drawn.
	_rig.set_process(false)
	_rig._hid_at.clear()  # What that frame faded round where she stood held no FADE_HOLD here (the clock stands).
	_rig._close_at.clear()
	var puppet: Node3D = _rig._puppets[player.get_instance_id()]
	var other: Node3D = _rig._puppets.get(companion.get_instance_id()) if companion != null else null
	_check(other != null, "a companion drawn for the check (%s)" % ("spawned" if spawned_her != null else "the scene's"))
	var was := puppet.global_position
	var other_was := other.global_position if other != null else Vector3.ZERO
	var yaw_was: float = _rig.yaw
	if other != null:
		other.global_position = _rig.to_global(_rig._tile_position(Vector2i(14, 12)))
	# The house is x 3..6, y 3..8; the camera at yaw 0 is off +x +y: behind it.
	puppet.global_position = _rig.to_global(_rig._tile_position(Vector2i(2, 5)))
	_rig._set_yaw(0.0)
	_rig._yaw_step = 0.0
	_rig._hand_yaw = 0.0
	_rig._ease_t = 1.0
	_rig._turn_view = CameraTurn.new()
	_rig._camera_target = puppet.position
	_rig._place_camera()
	_rig._update_fade(true)
	var faded_walls := _rig._faded.keys().filter(func(piece: Node3D) -> bool: return _rig._walls.values().has(piece)).size()
	_check(_rig._outdoor and _rig._player_hidden and not _rig._lined.is_empty() and faded_walls == 0,
			"behind the house: hidden, and nothing fades for it (%d on the line, %d walls faded)" % [_rig._lined.size(), faded_walls])
	_rig._update_seen_through()
	var worn: Variant = puppet.get_meta("outline", null)
	var fill: ShaderMaterial = _rig._player_through
	var rim_pass := fill.next_pass as ShaderMaterial
	_check(puppet.has_meta("seen_through") and worn == fill and rim_pass != null
			and "write" in fill.shader.code and "depth_test_disabled" in fill.shader.code
			and Color(fill.get_shader_parameter("colour")).b > Color(fill.get_shader_parameter("colour")).r
			and Color(rim_pass.get_shader_parameter("colour")).get_luminance() > Color(fill.get_shader_parameter("colour")).get_luminance(),
			"hidden outdoors: the player shows through what hides them, a cool fill marking its pixels and a brighter rim round it (623 amended (5))")
	if other != null:
		# Wren behind the house too (623 amended (5)): hers shows; marked, her rim is the target's, drawn through.
		other.global_position = _rig.to_global(_rig._tile_position(Vector2i(2, 6)))
		_rig._update_fade(true)
		_rig._update_seen_through()
		var hidden_her: bool = _rig._companion_hidden
		var hers: bool = hidden_her and other.has_meta("seen_through")
		_rig.target(companion)
		_rig._update_seen_through()
		var through: bool = other.get_meta("outline", null) == _rig._target_through and not other.has_meta("seen_through")
		_rig.target(null)
		other.global_position = _rig.to_global(_rig._tile_position(Vector2i(12, 11)))  # In the open, as the player's check below.
		_rig._update_fade(true)
		_rig._update_seen_through()
		_check(hers and through and not _rig._companion_hidden and not other.has_meta("seen_through"),
				"Wren hidden behind it: her rim shows; marked, the target's rim drawn through; in the open, off (hidden %s, rim %s; through %s; after %s %s)"
				% [hidden_her, hers, through, _rig._companion_hidden, other.has_meta("seen_through")])
	var target := CameraTurn.choose(0.0, _rig._clears, Vector2.ZERO, 0.0)
	_check(not is_nan(target) and absf(target) <= CameraTurn.TURN_MOST and _rig._clears(target) and not _rig._clears(0.0),
			"a yaw within 45 degrees shows them whole (%s)" % target)
	# Not before HIDE_SECONDS.
	_rig._drive_turn(CameraTurn.HIDE_SECONDS * 0.5)
	var early: bool = _rig._turn_view.turning or _rig._line_fade
	_rig._drive_turn(CameraTurn.HIDE_SECONDS * 0.6)
	var started: bool = _rig._turn_view.turning
	_rig._drive_turn(0.05)
	var mid: float = _rig.yaw
	var frame_kept: bool = _rig.move_yaw() == 0.0 and mid != 0.0
	for i in 40:
		_rig._drive_turn(0.05)
	_rig._update_fade(true)
	_check(not early and started and frame_kept and is_equal_approx(_rig.yaw, target) and not _rig._turn_view.turning
			and is_equal_approx(Net.camera_yaw, Client3D.wrapped_yaw(target)) and not _rig._player_hidden,
			"after HIDE_SECONDS it turns there and stays, the walk keys going by where it set off meanwhile (%s, mid-turn %.1f); seen now" % [_rig.yaw, mid])
	_rig._update_seen_through()
	_check(not puppet.has_meta("seen_through"), "seen again: their rim off")
	# Back behind the house, the player's own turn stops a turn under way.
	_rig._set_yaw(0.0)
	_rig._update_fade(true)
	_rig._turn_view = CameraTurn.new()
	_rig._drive_turn(CameraTurn.HIDE_SECONDS + 0.1)
	var turning_before: bool = _rig._turn_view.turning
	_rig.turn(1.0, 0.0)
	_rig.end_turn()
	_rig._ease_t = 1.0
	var stopped: bool = not _rig._turn_view.turning
	_rig._set_yaw(0.0)
	_rig._update_fade(true)
	_rig._drive_turn(CameraTurn.HIDE_SECONDS + 0.1)
	_rig._drive_turn(0.25)
	var walls_faded := _rig._faded.keys().filter(func(piece: Node3D) -> bool: return _rig._walls.values().has(piece)).size()
	_rig._update_seen_through()
	_check(turning_before and stopped and not _rig._turn_view.turning and _rig._line_fade and walls_faded == 0 and puppet.has_meta("seen_through"),
			"A/D stops it at once, none for MANUAL_HOLD; nothing fades meanwhile, their rim shows (623 amended (5); %d walls)" % walls_faded)
	# Turned off past TURN_MOST by hand's yaw: nothing within reach clears, so it fades.
	_rig._turn_view = CameraTurn.new()
	_rig._line_fade = false
	_rig._hand_yaw = 0.0
	var clear_at := func(_degrees: float) -> bool: return false
	_check(is_nan(CameraTurn.choose(0.0, clear_at, Vector2.ZERO, 0.0)), "nothing clears: no turn")
	# The Options' turning off: never turns; what hides them fades, as ever.
	_rig._turn_view = CameraTurn.new()
	_rig._line_fade = false
	_rig._update_fade(true)
	Net.camera_turn = false
	for i in 20:
		_rig._drive_turn(0.1)
	var off_faded := _rig._faded.keys().filter(func(piece: Node3D) -> bool: return _rig._walls.values().has(piece)).size()
	_rig._update_seen_through()
	_check(_rig.yaw == 0.0 and _rig._line_fade and off_faded == 0 and _rig._player_hidden and puppet.has_meta("seen_through"),
			"turning off in Options: it never turns, nothing fades, their rim shows (%d walls; still counted hidden, so it turns again when on)" % off_faded)
	Net.camera_turn = true
	# Out in the open: not hidden, nothing shown through.
	puppet.global_position = _rig.to_global(_rig._tile_position(Vector2i(13, 11)))
	_rig._camera_target = puppet.position
	_rig._place_camera()
	_rig._update_fade(true)
	for i in 5:
		_rig._drive_turn(0.1)
	_check(not _rig._player_hidden and not _rig._line_fade and is_equal_approx(_rig.yaw, 0.0), "in the open: seen, nothing faded for them, and no turn back")
	puppet.global_position = was
	if other != null:
		other.global_position = other_was
	if spawned_her != null and spawned_her.spawned:
		World.despawn(spawned_her)
	_rig._turn_view = CameraTurn.new()
	_rig._line_fade = false
	_rig._set_yaw(yaw_was)
	_rig._yaw_step = yaw_was
	Net.camera_yaw = Client3D.wrapped_yaw(yaw_was)
	_rig.rebuild(_main._terrain, Vector2i.ZERO)
	_rig.set_process(true)


## Indoors (671): top-down in a walled space, eased; out after a hold, so a
## doorway never bobs it; the low camera keeps its own.
## The camera's feel from art/kit/feel.json (673 step 2): the repo's file
## names only the view's vars, one of each, each a number; a file's key
## sets its var (a whole number for an int one), its words and any other
## key left alone; the tuning panel's camera source sets one live.
func _test_camera_feel() -> void:
	print("
== the camera's feel from art/kit/feel.json (673 step 2) ==")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://art/kit/feel.json"))
	var section: Dictionary = data.get("camera", {}) if data is Dictionary else {}
	var numbers := section.keys().filter(func(key: String) -> bool: return key != "about")
	_check(numbers.size() == Client3D.CAMERA_FEEL.size() and Client3D.CAMERA_FEEL.all(func(key: String) -> bool: return section.get(key) is float or section.get(key) is int),
			"the file's camera section: each of the view's %d vars, a number (%d)" % [Client3D.CAMERA_FEEL.size(), numbers.size()])
	var kept := {}
	for key in Client3D.CAMERA_FEEL:
		kept[key] = _rig.get(key)
	_check(_rig.load_camera_feel("res://art/kit/feel.json") == Client3D.CAMERA_FEEL.size(), "all of them read")
	var scratch := preload("res://tests/test_ports.gd").scratch("camera_feel.json")
	var file := FileAccess.open(scratch, FileAccess.WRITE)
	file.store_string(JSON.stringify({"about": "x", "feel": {"client3d.clip_blend": 9}, "camera": {"about": "y", "overhead_pitch": 70, "telegraph_flash_msec": 120.6, "nothing": 3, "zoom_rate": "fast"}}))
	file.close()
	_check(_rig.load_camera_feel(scratch) == 2 and is_equal_approx(_rig.overhead_pitch, 70.0) and _rig.overhead_pitch is float
			and _rig.telegraph_flash_msec == 121 and _rig.get("nothing") == null,
			"a file's camera keys set their vars (%s, %s); words and other keys left alone" % [_rig.overhead_pitch, _rig.telegraph_flash_msec])
	_rig.overhead = true
	_check(is_equal_approx(_rig.rest_pitch(), 70.0) or _rig.indoors, "the overhead view rests at the file's pitch (%s)" % _rig.rest_pitch())
	_rig.overhead = false
	for key: String in kept:
		_rig.set(key, kept[key])
	DirAccess.remove_absolute(scratch)


func _test_indoor_camera() -> void:
	print("
== indoors (671): top-down in a walled space, out after a hold, never a bob ==")
	var room := Rect2i(2, 2, 6, 5)
	var overhead_was: bool = _rig.overhead
	var outdoor_was: bool = _rig._outdoor
	_rig._outdoor = true  # A building's walls, out on a map (671 amended (2)).
	_rig.indoor_view = true
	_rig.overhead = false
	_rig.indoors = false
	_rig._left_inside_at = -1.0
	_rig._ease_pitch()
	_rig._ease_tilt(10.0)
	var outside := _rig.pitch
	_rig.inside_changed.emit(true, room)
	_rig._ease_tilt(Client3D.INSIDE_EASE_SECONDS * 0.5)
	var going := _rig.pitch
	_rig._ease_tilt(Client3D.INSIDE_EASE_SECONDS * 0.5)
	_check(_rig.indoors and going > outside and going < Client3D.INSIDE_PITCH and is_equal_approx(_rig.pitch, Client3D.INSIDE_PITCH),
			"in: eased to top-down (%.0f, %.1f half way)" % [_rig.pitch, going])
	_rig.inside_changed.emit(true, Rect2i(8, 2, 4, 4))
	_rig._ease_tilt(0.1)
	_check(is_equal_approx(_rig.pitch, Client3D.INSIDE_PITCH), "room to room: still")
	_rig.inside_changed.emit(false, Rect2i())
	_rig._fade_clock += Client3D.INSIDE_LEAVE_HOLD * 0.5
	_rig._update_indoors()
	_rig.inside_changed.emit(true, room)
	_rig._fade_clock += Client3D.INSIDE_LEAVE_HOLD
	_rig._update_indoors()
	_rig._ease_tilt(0.1)
	_check(_rig.indoors and is_equal_approx(_rig.pitch, Client3D.INSIDE_PITCH), "a doorway out and back within the hold: no bob")
	_rig.inside_changed.emit(false, Rect2i())
	_rig._fade_clock += Client3D.INSIDE_LEAVE_HOLD * 0.9
	_rig._update_indoors()
	_check(_rig.indoors, "out, under the hold: still in")
	_rig._fade_clock += Client3D.INSIDE_LEAVE_HOLD * 0.2
	_rig._update_indoors()
	_rig._ease_tilt(Client3D.INSIDE_EASE_SECONDS)
	_check(not _rig.indoors and is_equal_approx(_rig.pitch, outside), "out past the hold: back to the view it had (%.0f)" % _rig.pitch)
	_rig.set_overhead(true)
	_rig._ease_tilt(1.0)
	_rig.inside_changed.emit(true, room)
	_rig._ease_tilt(1.0)
	_check(is_equal_approx(_rig.pitch, Client3D.INSIDE_PITCH), "in again: top-down (%.0f)" % _rig.pitch)
	_rig.set_overhead(false)
	_rig._ease_tilt(1.0)
	_check(is_equal_approx(_rig.pitch, Client3D.CAMERA_PITCH) and not _rig.overhead,
			"S indoors: the player's view wins, the normal pitch (671 amended (2); %.0f)" % _rig.pitch)
	_rig.inside_changed.emit(true, Rect2i(8, 2, 4, 4))
	_rig._ease_tilt(1.0)
	_check(is_equal_approx(_rig.pitch, Client3D.CAMERA_PITCH), "room to room: their choice kept (%.0f)" % _rig.pitch)
	_rig.set_overhead(true)
	_rig._ease_tilt(1.0)
	_check(is_equal_approx(_rig.pitch, Client3D.OVERHEAD_PITCH), "and W: overhead (%.0f)" % _rig.pitch)
	_rig.set_overhead(false)
	_rig.inside_changed.emit(false, Rect2i())
	_rig._fade_clock += Client3D.INSIDE_LEAVE_HOLD * 2.0
	_rig._update_indoors()
	_rig._ease_tilt(1.0)
	_check(is_equal_approx(_rig.pitch, Client3D.CAMERA_PITCH), "and out: the normal pitch, as S left it (%.0f)" % _rig.pitch)
	_rig.inside_changed.emit(true, room)
	_rig._ease_tilt(Client3D.INSIDE_EASE_SECONDS)
	_check(is_equal_approx(_rig.pitch, Client3D.INSIDE_PITCH), "left and in again: top-down, the choice gone with the space")
	_rig.inside_changed.emit(false, Rect2i())
	_rig._fade_clock += Client3D.INSIDE_LEAVE_HOLD * 2.0
	_rig._update_indoors()
	_rig._outdoor = false
	_rig.inside_changed.emit(true, room)
	_rig._ease_tilt(Client3D.INSIDE_EASE_SECONDS)
	_check(not _rig.indoors and is_equal_approx(_rig.pitch, Client3D.CAMERA_PITCH),
			"underground (the barrow's rooms, all walled): no tip, the normal pitch (%.0f)" % _rig.pitch)
	_rig.inside_changed.emit(false, Rect2i())
	_rig._outdoor = outdoor_was
	_rig.set_overhead(overhead_was)
	_rig._ease_tilt(1.0)
	_rig.indoor_view = false


## The draw's pull-back (decision 669; Jeff: "the camera should start to
## zoom out as the bow range goes up"): a reach that would leave the screen
## widens the view till its point is DRAW_PULL_MARGIN inside, from the high
## camera and the low; a short one leaves the player's zoom; never nearer;
## let go, back to it.
func _test_draw_pull() -> void:
	print("
== the bow's reach kept on screen: the view widens as it grows, from the high camera and the low (decision 669) ==")
	var low_was := Net.camera_low
	var zoom_was: float = _rig.zoom
	for low: bool in [false, true]:
		Net.set_camera_low(low, false)
		if low:
			var castle := Level.load_level("castle")
			_rig.rebuild(castle["terrain"], castle["centre"])
			_rig._ridge_pitch = 0.0
		var label := "the low camera" if low else "the high camera"
		var kept := true
		var widened := 0
		for way: Vector2 in [Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2(1, 1).normalized(), Vector2(-1, -1).normalized()]:
			_rig._reach_pull = 1.0
			_rig._reach_pull_to = 1.0
			_rig._apply_size()
			_rig._place_camera()
			_rig.aim_lead(way, true)
			_rig._aim_lead = _rig._aim_lead_to
			_rig.aim_reach(15.0, way)
			_rig._ease_reach_pull(10.0)
			_rig._apply_size()
			_rig._place_camera()
			if _rig._reach_pull > 1.0:
				widened += 1
			var target: Vector3 = _rig._camera_target
			var far := target + Vector3(way.x * 15.0, 0.0, way.y * 15.0) - _rig._aim_lead
			var at: Vector2 = _rig._camera.unproject_position(far)
			var screen: Vector2 = _rig.get_viewport().get_visible_rect().size
			kept = kept and at.x >= 0.0 and at.y >= 0.0 and at.x <= screen.x and at.y <= screen.y
		_check(kept and widened > 0, "%s: 15 cells out kept on screen every way, the view widened for %d of 5 ways" % [label, widened])
		_rig.aim_lead(Vector2.RIGHT, true)
		_rig.aim_reach(5.0, Vector2.RIGHT)
		_check(is_equal_approx(_rig._reach_pull_to, 1.0), "%s: a reach of 5 leaves the player's own zoom" % label)
		_rig.aim_reach(0.0, Vector2.ZERO)
		_rig.aim_lead(Vector2.ZERO, false)
		_rig._ease_reach_pull(10.0)
		_rig._apply_size()
		_check(is_equal_approx(_rig._reach_pull, 1.0) and is_equal_approx(_rig.zoom, zoom_was), "%s: let go, back to the player's zoom" % label)
	_rig._aim_lead = Vector3.ZERO
	Net.set_camera_low(low_was, false)
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## The low camera's scatter reach (decision 653): built out to
## LOW_SCATTER_REACH of the aim, not NEAR_TILES (which still bounds the
## rest), shrinking into the ground over its last SCATTER_FADE, the kinds
## that don't sway fading by their draw distance; chunks left SCATTER_KEEP
## past the reach freed; the ortho view as before.
func _test_low_scatter() -> void:
	print("\n== the low camera's scatter reach (653): out to LOW_SCATTER_REACH, faded, freed past it ==")
	var low_was := Net.camera_low
	Net.set_camera_low(true, false)
	var wilds := Level.load_level("wilds")
	_rig.rebuild(wilds["terrain"], wilds["centre"])
	var aim := Vector2(_rig._camera_target.x, _rig._camera_target.z)
	var reach: float = _rig._scatter_reach()
	_check(is_equal_approx(reach, Client3D.LOW_SCATTER_REACH) and is_equal_approx(_rig._view_reach(), World.NEAR_TILES),
			"the scatter's reach is LOW_SCATTER_REACH, the view's NEAR_TILES (%.0f, %.0f)" % [reach, _rig._view_reach()])
	_rig._grow_scatter()
	while _rig._scatter_step():
		pass
	_rig._grow_scatter()
	var middle := func(chunk: Vector2i) -> float:
		return (Vector2(chunk * Client3D.FLOOR_CHUNK) + Vector2.ONE * Client3D.FLOOR_CHUNK * 0.5).distance_to(aim)
	var furthest := 0.0
	var inside := true
	for chunk: Vector2i in _rig._scattered:
		furthest = maxf(furthest, middle.call(chunk))
		inside = inside and middle.call(chunk) <= reach + Client3D.FLOOR_CHUNK
	_check(inside and furthest > World.NEAR_TILES + Client3D.FLOOR_CHUNK,
			"built out past NEAR_TILES, no further than the reach and a chunk (furthest middle %.0f)" % furthest)
	var fade: Vector4 = Client3D._scatter_material("tuft").get_shader_parameter("reach_fade")
	_check(fade.is_equal_approx(Vector4(aim.x, aim.y, reach - Client3D.SCATTER_FADE, reach)),
			"the swaying kinds shrink away over the reach's last SCATTER_FADE (%s)" % fade)
	var ranged := 0
	var unranged := 0
	for chunk: Vector2i in _rig._scatter_nodes:
		for drawn: MultiMeshInstance3D in _rig._scatter_nodes[chunk]:
			if not drawn.material_override is ShaderMaterial:
				if is_equal_approx(drawn.visibility_range_end, reach) and is_equal_approx(drawn.visibility_range_end_margin, Client3D.SCATTER_FADE):
					ranged += 1
				else:
					unranged += 1
	_check(ranged > 0 and unranged == 0, "the stones and roots fade by their draw distance at the reach (%d, %d not)" % [ranged, unranged])
	var built: int = _rig._scattered.size()
	_rig.scatter_reach_low = 20.0
	_rig._grow_scatter()
	var kept := true
	for chunk: Vector2i in _rig._scattered:
		kept = kept and middle.call(chunk) <= 20.0 + Client3D.FLOOR_CHUNK + Client3D.SCATTER_KEEP
	for chunk: Vector2i in _rig._scatter_nodes:
		kept = kept and _rig._scattered.has(chunk)
	_check(kept and _rig._scattered.size() < built,
			"a shorter reach frees the chunks SCATTER_KEEP past it (%d of %d kept)" % [_rig._scattered.size(), built])
	_rig.scatter_reach_low = Client3D.LOW_SCATTER_REACH
	Net.set_camera_low(false, false)
	_rig._grow_scatter()
	fade = Client3D._scatter_material("tuft").get_shader_parameter("reach_fade")
	var unfaded := true
	for chunk: Vector2i in _rig._scatter_nodes:
		for drawn: MultiMeshInstance3D in _rig._scatter_nodes[chunk]:
			unfaded = unfaded and is_zero_approx(drawn.visibility_range_end)
	_check(fade.z > 1e8 and unfaded and is_equal_approx(_rig._scatter_reach(), _rig._view_reach()),
			"Off: the screen's reach, no fade, drawn as far as seen")
	Net.set_camera_low(low_was, false)
	_rig.rebuild(_main._terrain, Vector2i.ZERO)

## 623's hotfix, the half Jeff saw most (the draugr at his spawn, the
## castle's goblins dead on their feet with stale bars): under stone the
## low camera is off, and a body back from beyond the view's reach must
## run again there too; one that died out there falls when its body goes.
func _test_far_restart() -> void:
	print("\n== under stone, the low camera off: a body back from beyond the view's reach runs again; one that died out there falls ==")
	_check(not _rig._low and _rig._camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "the test room is under stone: the ortho camera, the low one off")
	var aim := Vector2(_rig._camera_target.x, _rig._camera_target.z)
	var imp := _spawn_imp(Vector2i(9, 4))
	await _frames(2)
	_rig._sync_puppets()
	var id := imp.get_instance_id()
	var near_tile := imp.tile
	var far_tile := Vector2i(roundi(aim.x) + 200, roundi(aim.y) + 200)
	imp.tile = far_tile
	imp.position = Iso.grid_to_local(Vector2(far_tile))
	_rig._sync_puppets()
	_check(_rig._far.has(id) and not imp.is_processing(), "gone beyond the view's reach: its drawing stops")
	imp.tile = near_tile
	imp.position = Iso.grid_to_local(Vector2(near_tile))
	for i in Client3D.FAR_EVERY:
		_rig._sync_puppets()
		await get_tree().process_frame
	_check(not _rig._far.has(id) and imp.is_processing() and _rig._puppets[id].process_mode == Node.PROCESS_MODE_INHERIT,
			"back near with the low camera off: it runs again, where it is")
	# Died beyond the reach: the death's news fells its puppet when its body goes.
	imp.tile = far_tile
	imp.position = Iso.grid_to_local(Vector2(far_tile))
	_rig._sync_puppets()
	_check(_rig._far.has(id), "far off again")
	var puppet: Node3D = _rig._puppets[id]
	_rig.on_death({"entity": imp.name, "kind": "monster"})
	imp.tile = near_tile  # (The sim's own tile, so its despawn frees the right cell.)
	World.despawn(imp)
	_rig._sync_puppets()
	_check(is_instance_valid(puppet) and puppet.has_meta("corpse") and not _rig._puppets.has(id), "died out there: its puppet falls as its body goes, not left standing")
	await _frames(2)


## The low-angle fight, 2: under the low camera a click's slack beside a
## monster is a thumb's width of screen, so a far body is as easy to hit
## as a near one.
func _test_low_pick() -> void:
	print("\n== picking under the low camera: the slack beside a body is screen, not ground ==")
	var low_was := Net.camera_low
	_check(_rig.pick_slack_at(_rig._camera.global_position - _rig._camera.global_transform.basis.z * 30.0) == Client3D.PICK_SLACK,
			"under the ortho camera: PICK_SLACK of ground, wherever the body is")
	Net.set_camera_low(true, false)
	var castle := Level.load_level("castle")
	_rig.rebuild(castle["terrain"], castle["centre"])
	var ahead: Vector3 = -_rig._camera.global_transform.basis.z
	var origin: Vector3 = _rig._camera.global_position
	var at_10 := _rig.pick_slack_at(origin + ahead * 10.0)
	var at_30 := _rig.pick_slack_at(origin + ahead * 30.0)
	var wanted_30 := Client3D.PICK_SLACK_SHARE * 2.0 * 30.0 * tan(deg_to_rad(Client3D.LOW_FOV * 0.5))
	_check(is_equal_approx(at_30, maxf(Client3D.PICK_SLACK, wanted_30)) and at_30 > at_10 and at_10 >= Client3D.PICK_SLACK and wanted_30 > Client3D.PICK_SLACK,
			"under the low camera: PICK_SLACK_SHARE of the screen's height at the body's depth, in ground units, more the farther, never under PICK_SLACK (%.2f at 10, %.2f at 30)" % [at_10, at_30])
	# The room's free floor cell deepest in the view (World still holds the test room).
	var deep := Vector2i(9, 4)
	var deepest := -INF
	for cell: Vector2i in _main._terrain["floor"]:
		var depth: float = (_rig.to_global(_rig._tile_position(cell)) - origin).dot(ahead)
		if depth > deepest and World.get_entity_at(cell) == null:
			deepest = depth
			deep = cell
	var imp := _spawn_imp(deep, "imp")
	await _frames(2)
	_rig._process(0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var puppet: Node3D = _rig._puppets[imp.get_instance_id()]
	var chest := puppet.global_position + Vector3.UP * 0.6
	var slack := _rig.pick_slack_at(chest)
	if slack > Client3D.PICK_SLACK + 0.05:
		var side := ahead.cross(Vector3.UP).normalized()
		var off := chest + side * (Client3D.MODEL_RADIUS + (Client3D.PICK_SLACK + slack) * 0.5)
		var picked: GridEntity = _rig.monster_near_ray(origin, (off - origin).normalized())
		_check(picked == imp, "a ray past the ground slack but within the screen's picks the imp %.0f units off (slack %.2f)" % [chest.distance_to(origin), slack])
		var wide := chest + side * (Client3D.MODEL_RADIUS + slack + 0.3)
		_check(_rig.monster_near_ray(origin, (wide - origin).normalized()) == null, "and one past the screen's slack picks nothing")
	else:
		print("  (the imp is too near the camera for the screen's slack to exceed the ground's: %.2f; the ray checks skipped)" % slack)
	World.despawn(imp)
	await _frames(2)
	Net.set_camera_low(low_was, false)
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## The border's pine stands (PineStands): drawn with the stand-in while the
## slot has no art, on the castle, whose way to the wilds has a lane.
func _test_pine_stands() -> void:
	print("
== the border's pine stands: packed past the first ring, never on a lane ==")
	_check(ArtKit.filled_by(PineStands.SLOT) != "placeholder" or not PineStands.drawn(),
			"while their slot has no art, no stands (never grey boxes)")
	PineStands.stand_in = true
	PineStands.forget()
	var castle := Level.load_level("castle")
	_rig.rebuild(castle["terrain"], castle["centre"])
	var distance := _rig._forest_distance
	var stands := PineStands.plan(distance, PineStands.variants())
	_check(not stands.is_empty() and str(stands) == str(PineStands.plan(distance, PineStands.variants())),
			"the same cells make the same stands (%d)" % stands.size())
	var taken: Dictionary[Vector2i, int] = {}
	for i in stands.size():
		for at in PineStands.FOOTPRINT:
			taken[stands[i]["cell"] + at] = i
	var bare: Array[Vector2i] = []
	var too_near: Array[Vector2i] = []
	for cell: Vector2i in distance:
		if distance[cell] >= PineStands.FROM and not taken.has(cell) and not _rig._trees.has(cell):
			bare.append(cell)
		if taken.has(cell) and distance[cell] < PineStands.FROM:
			too_near.append(cell)
	_check(bare.is_empty() and too_near.is_empty(),
			"every cell from ring %d out a stand's or a tree's, none of the first ring a stand's (bare %s, near %s)" % [PineStands.FROM, bare.slice(0, 4), too_near.slice(0, 4)])
	var holes := 0
	for cell: Vector2i in distance:
		if distance[cell] >= PineStands.FROM and not taken.has(cell):
			holes += 1
	_check(holes * 5 < taken.size(), "stands fill most of the band (%d cells in stands, %d trees between)" % [taken.size(), holes])
	if Client3D._deadwood_drawn("tree.pine"):
		var solo := 0
		for cell: Vector2i in distance:
			if distance[cell] >= PineStands.FROM and not taken.has(cell) and _rig._trees.has(cell) 					and str(_rig._trees[cell].get_meta("slot", "")) == "tree.pine":
				solo += 1
		_check(solo == holes, "the trees between them solo pines (%d of %d)" % [solo, holes])
	var on_lane := 0
	for cell: Vector2i in taken:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if _rig._wooded.has(cell + Vector2i(dx, dy)):
					on_lane += 1
	_check(_rig._glimpses.size() == 1 and on_lane == 0, "none on or beside the land, the glimpse or its lane through the trees")
	var same := 0
	for i in stands.size():
		var corner: Vector2i = stands[i]["cell"]
		for at: Vector2i in [Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(2, 0), Vector2i(2, 1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(0, 2), Vector2i(1, 2)]:
			var other: int = taken.get(corner + at, i)
			if other != i and stands[other]["variant"] == stands[i]["variant"]:
				same += 1
	_check(same == 0, "no two stands side by side the same variant")
	var near: Array[Node3D] = []
	var far := 0
	for stand: Dictionary in stands:
		var corner: Vector2i = stand["cell"]
		if int(stand["near"]) <= PineStands.NEAR:
			var node := _rig._room.get_node_or_null("Stand_%d_%d" % [corner.x, corner.y]) as Node3D
			if node != null and _rig._trees.get(corner) == node:
				near.append(node)
		else:
			far += 1
	var instances := 0
	for drawn: MultiMeshInstance3D in _rig._room.find_children("Stands_*", "MultiMeshInstance3D", false, false):
		instances += drawn.multimesh.instance_count
	_check(near.size() == stands.filter(func(stand: Dictionary) -> bool: return int(stand["near"]) <= PineStands.NEAR).size() and instances == far and far > 0,
			"near the land each a node of its own (%d), the rest a MultiMesh a chunk (%d)" % [near.size(), far])
	if not near.is_empty():
		_rig._set_near(near[0], true)
		var drawn := near[0].get_child(0) as MeshInstance3D
		var faded := drawn.get_surface_override_material(0) as ShaderMaterial
		# Its eye-cut copy's see-through copy since 326 amended (2).
		_check(faded != null and faded.shader in [Client3D.SEASON_NEAR_SHADER, Client3D.EYE_CUT_NEAR_SHADER] and faded.render_priority == Client3D.NEAR_PRIORITY,
				"a near stand fades as a tree does (its season's see-through copy)")
		_rig._set_near(near[0], false)
		var again := drawn.get_active_material(0) as ShaderMaterial
		_check(again != null and again.shader in [Client3D.SEASON_SHADER, Client3D.EYE_CUT_SHADER] and not again.get_shader_parameter("leaf"),
				"and solid again after, evergreen: snow on it, never dried or turned")
	var ringed := 0
	for index in range(_rig._ground_water_end, _rig._ground_cells.size()):
		if distance.get(_rig._ground_cells[index], 0) >= PineStands.FROM:
			ringed += 1
	var forest_floor := _rig._room.get_node("ForestFloor") as MeshInstance3D
	var flat := PineStands.needles_texture() == null
	_check(ringed == 0 and (not flat or (forest_floor.material_override as ShaderMaterial).get_shader_parameter("albedo_color") == PineStands.NEEDLES),
			"under them the needles' floor; the land's ground runs only into the first ring")
	# The needles' own texture (decision 423), tested with one made here
	# while ground.needles has none.
	var needles := PineStands.needles_texture()
	if needles == null:
		var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
		image.fill(PineStands.NEEDLES)
		needles = ImageTexture.create_from_image(image)
		PineStands.needles_stand_in = needles
		PineStands.forget()
		_rig.rebuild(castle["terrain"], castle["centre"])
	var floors: Array[ShaderMaterial] = [(_rig._room.get_node("ForestFloor") as MeshInstance3D).material_override]
	if _rig._border != null:
		floors.append((_rig._border.get_node("FarFloor") as MeshInstance3D).material_override)
	var tiled := 0
	for material in floors:
		var see_through := material.get_meta(Client3D.SEASON_NEAR_META) as ShaderMaterial
		if material.shader == Client3D.SEASON_SHADER and not material.get_shader_parameter("leaf") \
				and material.get_shader_parameter("tile_texture") == needles and float(material.get_shader_parameter("world_tile")) > 0.0 \
				and see_through.get_shader_parameter("tile_texture") == needles:
			tiled += 1
	_check(floors.size() == 2 and tiled == 2,
			"the needles' texture on the forest floor and the far floor, tiled in world metres, snow only, its see-through copy too (%d of %d)" % [tiled, floors.size()])
	PineStands.needles_stand_in = null
	PineStands.stand_in = false
	PineStands.forget()
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## The season on terrain's side (environment's 362): the ground, trees and
## the forest's floors drawn in the season's shaders, by kind.
func _test_seasons() -> void:
	print("
== in season: broadleaf dries and turns, pines and dead wood only take snow ==")
	_check(FileAccess.get_file_as_string("res://client3d/ground.gdshaderinc").contains("global uniform vec4 season")
			and (Client3D.SEASON_SHADER as Shader).code.contains("season.gdshaderinc"),
			"the ground's shader and the trees' read the season")
	var castle := Level.load_level("castle")
	_rig.rebuild(castle["terrain"], castle["centre"])
	var season_of := func(node: Node) -> Array:
		var out := []
		for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false) + ([node] if node is MeshInstance3D else []):
			for surface in mesh.mesh.get_surface_count():
				var drawn := mesh.get_active_material(surface) as ShaderMaterial
				# The canopy's own eye cut is the season's shader too (326 amended (1)).
				out.append(null if drawn == null or not drawn.shader in [Client3D.SEASON_SHADER, TerrainBorder.EYE_CUT_SHADER] else drawn.get_shader_parameter("leaf"))
		return out
	var leaves: Array = []
	var dead: Array = []
	for tree: Node3D in _rig._trees.values():
		var kind := str(tree.get_meta("slot", ""))
		# Pines and their stands, as dead wood: snow only.
		(dead if kind in ["tree.dead", "tree.pine", PineStands.SLOT] else leaves).append_array(season_of.call(tree))
	_check(not leaves.is_empty() and leaves.all(func(leaf: Variant) -> bool: return leaf == true),
			"every broadleaf's surfaces in the season's shader, its foliage turning (%d)" % leaves.size())
	var wood: Array = []
	for node in _rig._room.find_children("Deadwood_*", "", false, false):
		wood.append_array(season_of.call(node))
	_check(wood.all(func(leaf: Variant) -> bool: return leaf == false) and dead.all(func(leaf: Variant) -> bool: return leaf == false),
			"stumps, logs and dead trees: snow only (%d surfaces)" % (wood.size() + dead.size()))
	var forest_floor := _rig._room.get_node("ForestFloor") as MeshInstance3D
	var canopy_leaf: Variant = null
	if _rig._border != null:
		_rig._border.finish()
		var sheet := _rig._border.get_children().filter(func(node: Node) -> bool: return node.name.begins_with("Canopy_"))
		if not sheet.is_empty():
			canopy_leaf = season_of.call(sheet[0])[0]
	# The canopy sheet past pine stands is pines' (snow only), else broadleaf's.
	_check(season_of.call(forest_floor) == [false] and canopy_leaf == (not PineStands.drawn()),
			"the forest floor snow only; the canopy past broadleaf turns with it, past pine stands snow only")
	var tree: Node3D = _rig._trees.values()[0]
	var before: Array = season_of.call(tree)
	_rig._set_near(tree, true)
	var faded := tree.find_children("*", "MeshInstance3D", true, false)[0].get_active_material(0) as ShaderMaterial
	_rig._set_near(tree, false)
	_check(faded != null and faded.shader in [Client3D.SEASON_NEAR_SHADER, Client3D.EYE_CUT_NEAR_SHADER] and season_of.call(tree) == before,
			"a near tree fades in its season's see-through copy, and is in season again after")
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## The ground's kinds drawn with their own textures once ground.<kind> has
## art (decision 437; stand-ins made here while it has none), and the
## forest's edge into the stands' needles (423).
func _test_canopy_mask() -> void:
	print("
== the canopy's texture: a texel a cell, on the ground mask's grid ==")
	var cover: Dictionary[Vector2i, float] = {Vector2i(5, 4): 1.0, Vector2i(6, 4): 0.5, Vector2i(40, 40): 1.0}
	var texture := Client3D.canopy_mask(cover, Vector2i(4, 3), Vector2i(8, 6))
	var image := texture.get_image() if texture != null else null
	_check(image != null and image.get_size() == Vector2i(8, 6) and is_equal_approx(image.get_pixel(1, 1).r, 1.0)
			and absf(image.get_pixel(2, 1).r - 0.5) < 0.01 and image.get_pixel(0, 0).r == 0.0,
			"each cell's cover at its texel from the origin, none elsewhere, a cell off the grid left out")
	_check(Client3D.canopy_mask({}, Vector2i.ZERO, Vector2i(8, 6)) == null, "no canopy: no texture")


static var _warm_calls := 0


## A warm-up for the test: a box, counted.
static func _warm_probe() -> Node3D:
	_warm_calls += 1
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	return box


func _test_warm_ups() -> void:
	print("
== shader warm-ups: drawn once a process under the ground after a room is built, then freed ==")
	var probe := Callable(get_script(), "_warm_probe")
	Client3D.warm_ups.append(probe)
	_warm_calls = 0
	var castle := Level.load_level("castle")
	_rig.rebuild(castle["terrain"], castle["centre"])
	var warming := _rig._room.find_children("WarmUp_*", "Node3D", false, false)
	var under := warming.filter(func(node: Node3D) -> bool: return node.position.y < _rig._camera_target.y - 5.0)
	_check(_warm_calls == 1 and not warming.is_empty() and under.size() == warming.size(),
			"each drawn after the build, under the ground at the view's middle (%d)" % warming.size())
	_check(Client3D.warm_ups.has(Callable(GrownTrees, "warm")), "the forest's see-through among them")
	for i in Client3D.WARM_FRAMES + 2:
		await get_tree().process_frame
	_check(_rig._room.find_children("WarmUp_*", "Node3D", false, false).is_empty(), "freed after WARM_FRAMES frames")
	_rig.rebuild(castle["terrain"], castle["centre"])
	_check(_warm_calls == 1 and _rig._room.find_children("WarmUp_*", "Node3D", false, false).is_empty(), "never again in the same process")
	Client3D.warm_ups.erase(probe)


func _test_grown_trees() -> void:
	print("\n== a grown forest's trees: on their trunks' void, the ring left out, near pads by the view, seen through round the player ==")
	var map := LevelMap.new(Vector2i(64, 24))
	for y in 24:
		for x in 64:
			map.set_cell(Vector2i(x, y), "grass")
	map.set_cell(Vector2i(2, 2), "start")
	var whorls := [{"y": 1.2, "branches": [[0.3, 1.4]]}, {"y": 5.0, "branches": [[0.0, 1.6], [2.1, 1.5], [4.2, 1.3]]}, {"y": 8.0, "branches": [[1.0, 1.0]]}]
	var tree := func(at: Vector2, height: float) -> Dictionary:
		return {"at": [at.x, at.y], "height": height, "radius": 0.2, "lean": [0.0, 0.0], "state": "live", "whorls": whorls if height >= 3.0 else [], "dead": [[2.0, 1.0, 0.8]]}
	var trees: Array = [tree.call(Vector2(5.5, 5.5), 10.0), tree.call(Vector2(8.4, 6.7), 9.0), tree.call(Vector2(60.5, 20.5), 11.0),
		tree.call(Vector2(10.5, 10.5), 1.5), tree.call(Vector2(12.5, 12.5), 8.0)]
	for cell: Vector2i in [Vector2i(5, 5), Vector2i(8, 6), Vector2i(60, 20)]:
		map.set_cell(cell, "void")
	var level := Level.parse(map.to_image(), null, {"canopy": {"kind": "evergreen"}})
	var terrain: Dictionary = level["terrain"]
	terrain["level"] = "view_test_grown"
	terrain["outdoor"] = true
	GrownTrees.registered["view_test_grown"] = {"trees": trees}
	_rig.rebuild(terrain, Vector2i(4, 4))
	var grown := _rig._grown
	var chunk_of := func(cell: Vector2i) -> Vector2i: return Vector2i(floori(cell.x / float(GrownTrees.CHUNK)), floori(cell.y / float(GrownTrees.CHUNK)))
	var expected := {}
	for cell: Vector2i in [Vector2i(5, 5), Vector2i(8, 6), Vector2i(10, 10), Vector2i(60, 20)]:
		expected[chunk_of.call(cell)] = true
	_check(grown != null and grown.tree_count == 4 and grown.chunks.size() == expected.size(),
			"the three on void and the undergrowth on grass drawn; the tall one on grass not (%s trees, %s chunks)" % [grown.tree_count if grown else -1, grown.chunks.size() if grown else -1])
	_check(not _rig._trees.has(Vector2i(5, 5)) and not _rig._trees.has(Vector2i(8, 6)) and _rig._grounds.has(Vector2i(5, 5)),
			"no ring tree on a grown trunk's cell, and the ground runs under it")
	var roofed := Vector2i(6, 5)
	var open_cell := Vector2i(30, 15)
	var as_forest := {}
	for scatter_chunk: Vector2i in _rig._scatter_chunks:
		var plan := _rig._scatter_plan(scatter_chunk)
		for kind: String in plan:
			for item: Array in plan[kind]:
				if item[0] == roofed or item[0] == open_cell:
					as_forest[item[0]] = as_forest.get(item[0], true) and bool(item[3])
	_check(float(terrain["canopy"].get(roofed, 0.0)) > Client3D.SCATTER_ROOF and as_forest.get(roofed, false) and not as_forest.get(open_cell, true),
			"grass under the roof takes the forest's scatter, as its floor turns to needles; open grass its own")
	# The renderer keeps the custom data (headless it reads back as 0): its
	# makings, and that the tufts carry it.
	var forest_custom := Client3D.scatter_custom(true, 2.0)
	var open_custom := Client3D.scatter_custom(false, 2.0)
	var carried := false
	for chunk_key: Vector2i in _rig._scatter_chunks:
		_rig._scatter_build(chunk_key, "tuft", _rig._scatter_plan(chunk_key).get("tuft", []))
	for node in _rig._room.get_children():
		if node is MultiMeshInstance3D and String(node.name).ends_with("_tuft"):
			carried = (node as MultiMeshInstance3D).multimesh.use_custom_data
			break
	_check(carried and open_custom == Color(1.0, 2.0, 1.0, 1.0)
			and forest_custom == Color(Client3D.SCATTER_ROOF_SNOW, 2.0, Client3D.SCATTER_ROOF_STRAW, 1.0)
			and Client3D.scatter_custom(false, 2.0, false).a == 0.0
			and Client3D.SCATTER_ROOF_SNOW < 1.0 and Client3D.SCATTER_ROOF_STRAW < 1.0,
			"a tuft's snow: full in the open, less under the roof with its straw shaded, its tips by its own height, sunk in it (not reeds) (%s, %s)" % [open_custom, forest_custom])
	grown.set_focus(Vector3(5.0, 0.0, 5.0), Vector3(5.0, 0.0, 5.0))
	grown.finish()
	var near_one: Node3D = grown.chunks[chunk_of.call(Vector2i(5, 5))]["near"]
	var far_one: Node3D = grown.chunks[chunk_of.call(Vector2i(60, 20))]["near"]
	_check(near_one != null and not (grown.chunks[chunk_of.call(Vector2i(5, 5))]["far"] as Node3D).visible and far_one == null
			and (grown.chunks[chunk_of.call(Vector2i(60, 20))]["far"] as Node3D).visible,
			"the chunk by the focus drawn near, its far hidden; one past NEAR_REACH stays far")
	var drawn := near_one.get_node("Drawn") as MeshInstance3D
	var twin := near_one.get_node("Shadow") as MeshInstance3D
	var far_drawn := (grown.chunks[chunk_of.call(Vector2i(5, 5))]["far"] as Node3D).get_node("Drawn") as MeshInstance3D
	var crown_look := far_drawn.material_override as ShaderMaterial
	_check(crown_look != null and is_equal_approx(float(crown_look.get_shader_parameter("snow_cover")), GrownTrees.SNOW_COVER)
			and float(crown_look.get_shader_parameter("snow_patch")) > 0.0, "the crowns hold half a pine's snow, in patches")
	_check(drawn.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and twin.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			and twin.mesh == drawn.mesh, "drawn with no shadow of its own; a twin casts it, uncut")
	var near_tris: int = drawn.mesh.surface_get_array_len(0) / 3
	var far_tris: int = far_drawn.mesh.surface_get_array_len(0) / 3
	_check(far_tris * 2 < near_tris, "the far a fraction of the near (%d to %d triangles)" % [far_tris, near_tris])
	var material := drawn.material_override as ShaderMaterial
	var see_colour := material.next_pass as ShaderMaterial
	var depth := see_colour.next_pass as ShaderMaterial if see_colour != null else null
	_check((material.get_shader_parameter("focus") as Vector3).is_equal_approx(Vector3(5.0, 0.9, 5.0)) and see_colour != null and depth != null
			and see_colour.render_priority == Client3D.NEAR_PRIORITY and depth.render_priority == Client3D.NEAR_DEPTH_PRIORITY
			and is_equal_approx(float(see_colour.get_shader_parameter("alpha")), Client3D.NEAR_ALPHA)
			and (see_colour.get_shader_parameter("focus") as Vector3).is_equal_approx(Vector3(5.0, 0.9, 5.0)),
			"by the player, seen through: opaque but for it, its depth, then its colour at NEAR_ALPHA after (decision 188's order), on the player")
	var far_drawn_off := (grown.chunks[chunk_of.call(Vector2i(60, 20))]["far"] as Node3D).get_node("Drawn") as MeshInstance3D
	_check((far_drawn_off.material_override as ShaderMaterial).next_pass == null, "a chunk far from the player the opaque pass alone")
	grown.set_see(6.0)
	_check(is_equal_approx(float(material.get_shader_parameter("see_radius")), 6.0 + GrownTrees.SEE_SOFT * 0.5)
			and is_equal_approx(float(see_colour.get_shader_parameter("see_radius")), 6.0 + GrownTrees.SEE_SOFT * 0.5),
			"its width set from the view (Net's see_through x the half-height), to its soft edge's middle")
	var arrays := drawn.mesh.surface_get_arrays(0)
	var low := 0
	for i in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
		var colour: Color = arrays[Mesh.ARRAY_COLOR][i]
		if arrays[Mesh.ARRAY_VERTEX][i].y < GrownTrees.PAD_CLEAR - 0.3 and colour.g > colour.r + 0.05:
			low += 1
	_check(low == 0, "a tall tree's low branch a stick, no pad of needles at head height (%d points)" % low)
	grown.set_focus(Vector3(5.0, 0.0, 5.0), Vector3(60.0, 0.0, 20.0))
	grown.finish()
	_check(grown.chunks[chunk_of.call(Vector2i(5, 5))]["near"] == null and (grown.chunks[chunk_of.call(Vector2i(5, 5))]["far"] as Node3D).visible,
			"the view moved off past DROP_REACH, the player not: the near dropped there and the far back")
	GrownTrees.registered.erase("view_test_grown")
	terrain.erase("canopy_kind")
	_rig.rebuild(terrain, Vector2i(4, 4))
	_check(_rig._grown == null and [Vector2i(5, 5), Vector2i(8, 6), Vector2i(60, 20)].any(func(cell: Vector2i) -> bool: return _rig._trees.has(cell)),
			"no canopy: no grown trees, the ring's trees on the void as before")


func _test_ground_textures() -> void:
	print("\n== the ground's kinds: their own textures once they have art, the forest's edge into the needles ==")
	var ground_of := func() -> ShaderMaterial:
		var chunks := _rig._room.find_children("Ground_*", "MeshInstance3D", false, false)
		return (chunks[0] as MeshInstance3D).material_override as ShaderMaterial
	var castle := Level.load_level("castle")
	_rig.rebuild(castle["terrain"], castle["centre"])
	var plain: ShaderMaterial = ground_of.call()
	var off := Array(Client3D.GROUND_KINDS).filter(func(kind: String) -> bool:
		return Client3D.ground_texture(kind) == null and not plain.get_shader_parameter(kind + "_own"))
	var bare := Array(Client3D.GROUND_KINDS).filter(func(kind: String) -> bool: return Client3D.ground_texture(kind) == null)
	_check(off.size() == bare.size(), "a kind with no art its procedural look (%s)" % [off])
	var stand_ins: Dictionary[String, Texture2D] = {}
	for kind in Client3D.GROUND_KINDS:
		var image := Image.create(4, 4, false, Image.FORMAT_RGB8)
		image.fill(Client3D.ground_colour(kind))
		stand_ins[kind] = ImageTexture.create_from_image(image)
	Client3D.ground_stand_ins = stand_ins
	var needles := Image.create(4, 4, false, Image.FORMAT_RGB8)
	needles.fill(PineStands.NEEDLES)
	PineStands.needles_stand_in = ImageTexture.create_from_image(needles)
	PineStands.stand_in = true
	PineStands.forget()
	_rig.rebuild(castle["terrain"], castle["centre"])
	var drawn: ShaderMaterial = ground_of.call()
	var own := Array(Client3D.GROUND_KINDS).filter(func(kind: String) -> bool:
		return drawn.get_shader_parameter(kind + "_own") and drawn.get_shader_parameter(kind + "_tex") == Client3D.ground_texture(kind))
	var tiles: Vector4 = drawn.get_shader_parameter("kind_tiles")
	_check(own.size() == 4 and tiles.x > 0.0 and tiles.w > 0.0, "with art each kind its own texture, tiled in metres (%s, %s)" % [own, tiles])
	_check(drawn.get_shader_parameter("needles_own") and drawn.get_shader_parameter("needles_tex") == PineStands.needles_texture()
			and drawn.get_shader_parameter("forest_floor") == PineStands.NEEDLES.darkened(Client3D.EDGE_NEEDLES_DARK),
			"past pine stands the land's edge runs into their needles")
	Client3D.ground_stand_ins = {}
	PineStands.needles_stand_in = null
	PineStands.stand_in = false
	PineStands.forget()
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


func _test_ground_colours() -> void:
	print("\n== the ground: a mesh a chunk, stone grey, grass green, dirt brown, light and heat on each corner ==")
	var stone: Color = Client3D.ground_colour("stone")
	var grass: Color = Client3D.ground_colour("grass")
	var dirt: Color = Client3D.ground_colour("dirt")
	_check(is_equal_approx(stone.r, stone.g) and absf(stone.g - stone.b) < 0.05, "stone: grey (%s)" % stone)
	_check(grass.g > grass.r and grass.g > grass.b and dirt.r > dirt.g and dirt.g > dirt.b, "grass green, dirt brown")
	_check(grass.s < 0.6 and dirt.s < 0.6 and Client3D.swatch(4, 3) == grass,
			"from art-kit's palette, muted and earthy (grass %s, saturation %.2f)" % [grass.to_html(false), grass.s])
	var chunks := _rig._room.find_children("Ground_*", "MeshInstance3D", false, false)
	_check(chunks.size() == _rig._ground_meshes.size() and chunks.size() > 0
			and _rig._room.find_children("Floor_*", "", false, false).is_empty(),
			"the ground is a mesh a chunk (%d), no tile of its own a cell" % chunks.size())
	var material := (chunks[0] as MeshInstance3D).material_override as ShaderMaterial
	_check(material != null and material.shader == Client3D.GROUND_SHADER and material.get_shader_parameter("kinds") is Texture2D,
			"drawn by the ground shader with the kinds texture")
	for cell: Vector2i in _rig._grounds:
		if _rig._ground_kinds[cell] == "stone":
			var shade: Vector2 = _rig._ground_shades[cell]
			var colour: Color = _rig._ground_colour("stone", shade.x, shade.y)
			_check(colour.r > 0.1 and is_equal_approx(colour.r, colour.g) and absf(colour.g - colour.b) < 0.05,
					"a stone floor cell in the room is drawn grey (%s: %s)" % [cell, colour])
			break
	# (Headless, a mesh keeps no attributes: the bytes sent, kept by the view.)
	var averaged := 0
	for vertex in _rig._vertex_chunk.size():
		var bright := 0
		var count := 0
		for k in range(vertex * 4, vertex * 4 + 4):
			var cell := _rig._vertex_cells[k]
			if cell >= 0:
				bright += _rig._cell_shades[cell * 2]
				count += 1
		if count > 0 and _rig._ground_bytes[_rig._vertex_byte[vertex]] == roundi(bright / float(count)):
			averaged += 1
	_check(averaged == _rig._vertex_chunk.size(),
			"every corner is lit as the cells around it, averaged (%d of %d)" % [averaged, _rig._vertex_chunk.size()])
	var lit := 0
	for cell: Vector2i in _rig._grounds:
		var shade: Vector2 = _rig._ground_shades.get(cell, Vector2(-1.0, -1.0))
		var light := World.light_at(cell, false, false)
		if is_equal_approx(shade.x, snappedf(Client3D.floor_brightness(light), 0.1)):
			lit += 1
	_check(lit == _rig._grounds.size(), "every floor cell is shaded by the light on it (%d of %d)" % [lit, _rig._grounds.size()])


## A wall of the test room with floor on both sides, free on its far side
## from the camera: [key, the cell behind it, the cell before it], or
## [Vector3i(-1, -1, -1), ZERO, ZERO] when none.
func _wall_to_hide_behind() -> Array:
	var floor_cells: Array = _main._terrain["floor"]
	var toward := _rig._camera.global_transform.basis.z
	for key: Vector3i in _rig._walls:
		var cell := Vector2i(key.x, key.y)
		var normal := Vector2i(1, 0) if key.z == Terrain.EAST else Vector2i(0, 1)
		var other := cell + normal
		var far := cell if Vector2(normal).dot(Vector2(toward.x, toward.z)) > 0.0 else other
		if cell in floor_cells and other in floor_cells and World.get_entity_at(far) == null and _rig._height(cell) == _rig._height(other):
			return [key, far, other if far == cell else cell]
	return [Vector3i(-1, -1, -1), Vector2i.ZERO, Vector2i.ZERO]


func _test_fade() -> void:
	print("\n== walls fade, a whole run at once, only where they hide the player from the camera, a moment longer ==")
	var player := _player()
	var start := player.tile
	var floor_cells: Array = _main._terrain["floor"]
	# A wall with floor on both sides: stand on its far side from the camera.
	var toward := _rig._camera.global_transform.basis.z
	var hiding_wall := _wall_to_hide_behind()
	var wall_key: Vector3i = hiding_wall[0]
	var behind: Vector2i = hiding_wall[1]
	_check(wall_key.z != -1, "the test room has a wall with floor on both sides (%s)" % wall_key)
	if wall_key.z == -1:
		return
	_place(player, behind)
	await get_tree().create_timer(1.5).timeout
	var wall := _rig._walls[wall_key]
	_check(_rig._faded.has(wall), "standing just behind a wall: it fades (%s, at %s)" % [wall_key, behind])
	var faded_mesh: MeshInstance3D = _rig._descendants(wall).filter(func(node: Node) -> bool: return node is MeshInstance3D)[0]
	var near_material := faded_mesh.get_active_material(0) as BaseMaterial3D
	_check(near_material != null and near_material.render_priority == Client3D.NEAR_PRIORITY
			and near_material.next_pass is ShaderMaterial and near_material.next_pass.render_priority == Client3D.NEAR_DEPTH_PRIORITY,
			"drawn as its nearest surface only: its depth first, then its colour (no seam where two pieces meet)")
	var run: Array = _rig._wall_runs()[wall_key]
	_check(run.size() > 1 and run.all(func(piece: Node3D) -> bool: return _rig._faded.has(piece)),
			"and its whole run with it (%d pieces)" % run.size())
	# Everything faded is in the run of a piece near the player or the
	# companion, or is such a piece itself.
	var companion := _companion()
	var near_runs: Dictionary[Node3D, bool] = {}
	for entry: Array in _rig._occluders:
		# Where the occluder is: its bounds (a run of wall is one node).
		var centre := (entry[1] as AABB).get_center()
		var at := Vector2(centre.x, centre.z)
		if at.distance_to(Vector2(player.tile)) < 3.0 or companion != null and at.distance_to(Vector2(companion.tile)) < 3.0:
			for piece: Node3D in entry[3]:
				near_runs[piece] = true
	var far_faded := _rig._faded.keys().filter(func(piece: Node3D) -> bool: return not near_runs.has(piece)).size()
	_check(far_faded == 0, "and nothing else far from the player or the companion fades (%d of %d)" % [far_faded, _rig._faded.size()])
	# Beside a wall at their back, anywhere in the cell (as they walk): the
	# line to the camera never meets it, so it stays solid (its bounds, grown,
	# were grazed, and its run faded).
	var flat := Vector2(toward.x, toward.z).normalized()
	var grazed := 0
	var beside := 0
	for cell: Vector2i in floor_cells:
		for edge: Array in [[Vector3i(cell.x, cell.y, Terrain.EAST), Vector2(1, 0)], [Vector3i(cell.x - 1, cell.y, Terrain.EAST), Vector2(-1, 0)],
				[Vector3i(cell.x, cell.y, Terrain.SOUTH), Vector2(0, 1)], [Vector3i(cell.x, cell.y - 1, Terrain.SOUTH), Vector2(0, -1)]]:
			if not _rig._walls.has(edge[0]) or (edge[1] as Vector2).dot(flat) > -0.2:
				continue
			for nudge: Vector2 in [Vector2.ZERO, Vector2(0.3, 0.0), Vector2(-0.3, 0.0), Vector2(0.0, 0.3), Vector2(0.0, -0.3)]:
				var at := _rig.to_global(_rig._tile_position(cell)) + Vector3(nudge.x, 0.0, nudge.y)
				var points: Array[Vector3] = []
				for height in Client3D.FADE_HEIGHTS:
					points.append(at + Vector3(0.0, height, 0.0))
				beside += 1
				if _rig._hiding_pieces(points, toward).has(_rig._walls[edge[0]]):
					grazed += 1
	_check(beside > 0 and grazed == 0, "beside a wall at their back, it never fades (%d of %d spots)" % [grazed, beside])
	# The chunk index (310) finds what testing every piece finds: from
	# every floor cell, the camera turned to each of the eight views (671:
	# the square-on ones too) and tilted, overhead among them.
	var differ := 0
	var asked := 0
	var found := 0
	for cell: Vector2i in floor_cells:
		for turn in 8:
			for tilt: float in [Client3D.PITCH_MIN, Client3D.CAMERA_PITCH, Client3D.OVERHEAD_PITCH, Client3D.PITCH_MAX]:
				var flat_way := flat.rotated(turn * PI * 0.25)
				var way := Vector3(flat_way.x * cos(deg_to_rad(tilt)), sin(deg_to_rad(tilt)), flat_way.y * cos(deg_to_rad(tilt)))
				var at := _rig.to_global(_rig._tile_position(cell))
				var points: Array[Vector3] = []
				for height in Client3D.FADE_HEIGHTS:
					points.append(at + Vector3(0.0, height, 0.0))
				var every: Dictionary[Node3D, bool] = {}
				for entry: Array in _rig._occluders:
					var bounds: AABB = entry[1]
					for point in points:
						var ahead := bounds.get_center() - point
						var reach := maxf((_rig._camera.global_position - point).dot(way), 0.0)
						if ahead.x * way.x + ahead.z * way.z > 0.0 and bounds.intersects_segment(point, point + way * reach) != null:
							for piece: Node3D in entry[3]:
								every[piece] = true
							break
				var indexed := _rig._hiding_pieces(points, way)
				asked += 1
				found += every.size()
				if indexed.size() != every.size() or not every.keys().all(func(piece: Node3D) -> bool: return indexed.has(piece)):
					differ += 1
	_check(asked > 0 and found > 0 and differ == 0, "the pieces hiding them, found by the chunk index, are those testing every piece finds (%d of %d views differ, %d pieces in all)" % [differ, asked, found])
	# Out of the way: still faded for FADE_HOLD, so walking along a wall does
	# not flicker it, then solid (the rig held still, its clock stepped).
	var puppet: Node3D = _rig._puppets[player.get_instance_id()]
	var was := puppet.global_position
	_rig.set_process(false)
	puppet.global_position = was + Vector3(-toward.x, 0.0, -toward.z).normalized() * 3.0
	_rig._fade_clock += Client3D.FADE_HOLD * 0.5
	_rig._update_fade()
	_check(not _rig._hiding.has(wall) and _rig._faded.has(wall), "stepped out from behind it: it no longer hides them, but stays faded a moment")
	_rig._fade_clock += Client3D.FADE_HOLD
	_rig._update_fade()
	_check(not _rig._faded.has(wall), "and after %s s, solid again" % Client3D.FADE_HOLD)
	puppet.global_position = was
	_rig.set_process(true)
	# A corner whose two walls are at the player's back, away from the
	# camera: neither fades.
	var corner := Vector2i(-1, -1)
	for cell: Vector2i in floor_cells:
		var side_x := Vector3i(cell.x, cell.y, Terrain.EAST) if toward.x < 0.0 else Vector3i(cell.x - 1, cell.y, Terrain.EAST)
		var side_z := Vector3i(cell.x, cell.y, Terrain.SOUTH) if toward.z < 0.0 else Vector3i(cell.x, cell.y - 1, Terrain.SOUTH)
		var link := (_main.level.get("links", []) as Array).any(func(l: Dictionary) -> bool: return l["tile"] == cell)
		if _rig._walls.has(side_x) and _rig._walls.has(side_z) and World.get_entity_at(cell) == null and not link:
			corner = cell
			_place(player, cell)
			await get_tree().create_timer(1.5).timeout
			_check(not _rig._faded.has(_rig._walls[side_x]) and not _rig._faded.has(_rig._walls[side_z]),
					"in a corner, its walls at the player's back stay solid (at %s)" % cell)
			break
	_check(corner.x != -1, "the test room has a corner away from the camera")
	var away := behind
	for cell: Vector2i in floor_cells:
		if Vector2(cell - behind).length() >= 6.0 and World.get_entity_at(cell) == null and (companion == null or Vector2(cell - companion.tile).length() >= 6.0):
			away = cell
			break
	_place(player, away)
	await get_tree().create_timer(1.5).timeout
	_check(not _rig._faded.has(wall), "walk away, the camera with them: that wall is solid again")
	_place(player, start)
	await get_tree().create_timer(1.0).timeout


## A monster kind drawn as a person (Jeff: "have the grave robbers use the character body type"):
## its row's "person" words put it in the human body with a build and a look, the words worn, its
## hands and head sockets a person's; without them it is drawn as before.
## The low-angle fight, 1: what hides a foe fades as what hides the player
## does, while the foe is near enough to be fought.
func _test_fight_fade() -> void:
	print("\n== a fight's other side: what hides a live monster near the player fades too ==")
	var player := _player()
	var start := player.tile
	var found := _wall_to_hide_behind()
	var wall_key: Vector3i = found[0]
	var behind: Vector2i = found[1]
	var before: Vector2i = found[2]
	if wall_key.z == -1:
		_check(false, "the test room has a wall with floor on both sides")
		return
	var wall: Node3D = _rig._walls[wall_key]
	# The player before the wall (at their back: it never hides them), an imp behind it.
	_place(player, before)
	await get_tree().create_timer(1.5).timeout
	_rig._update_fade(true)
	_check(not _rig._hiding.has(wall), "the player before the wall, it at their back: it does not hide them")
	var imp := _spawn_imp(behind)
	await get_tree().create_timer(1.5).timeout  # Its body drawn where it stands.
	_rig._sync_puppets()
	_rig._update_fade(true)
	_check(_rig._fight_points(_rig._focus_points()).is_empty() and not _rig._hiding.has(wall), "an idle imp behind the wall is no fight: its cover stays")
	imp.alert = Monster.Alert.HUNTING
	_rig._update_fade(true)
	var fight_points: Array[Vector3] = _rig._fight_points(_rig._focus_points())
	var imp_at: Vector3 = _rig.to_global(_rig._tile_position(behind))
	_check(fight_points.size() == Client3D.FADE_HEIGHTS.size() and Vector2(fight_points[0].x, fight_points[0].z).distance_to(Vector2(imp_at.x, imp_at.z)) < 0.6,
			"hunting, an imp a cell away is the fight's other side, at FADE_HEIGHTS (%d points, %s for %s)" % [fight_points.size(), fight_points[0] if not fight_points.is_empty() else Vector3.ZERO, imp_at])
	_check(_rig._hiding.has(wall) and _rig._faded.has(wall), "the wall between the camera and the imp fades, as it would for the player")
	imp.alert = Monster.Alert.FLEEING
	_rig._update_fade(true)
	_check(_rig._fight_points(_rig._focus_points()).is_empty() and not _rig._hiding.has(wall), "fleeing, its cover is its own again")
	imp.alert = Monster.Alert.FIGHTING
	_rig._update_fade(true)
	_check(_rig._hiding.has(wall), "fighting, the wall fades again")
	imp.hp = 0
	_rig._update_fade(true)
	_check(_rig._fight_points(_rig._focus_points()).is_empty() and not _rig._hiding.has(wall), "felled, it is no fight: the wall no longer hides anyone")
	World.despawn(imp)
	_rig._sync_puppets()
	# Beyond FIGHT_TILES, a monster's cover is its own.
	var floor_cells: Array = _main._terrain["floor"]
	var far_cell := Vector2i(-1, -1)
	for cell: Vector2i in floor_cells:
		if Vector2(cell).distance_to(Vector2(behind)) > Client3D.FIGHT_TILES + 1.0 and World.get_entity_at(cell) == null:
			far_cell = cell
			break
	if far_cell.x != -1:
		_place(player, far_cell)
		await get_tree().create_timer(1.5).timeout
		var far_imp := _spawn_imp(behind)
		await get_tree().create_timer(1.5).timeout
		_rig._sync_puppets()
		far_imp.alert = Monster.Alert.FIGHTING
		_rig._update_fade(true)
		_check(_rig._fight_points(_rig._focus_points()).is_empty() and not _rig._hiding.has(wall),
				"the player %.0f tiles off: an imp behind the wall is no fight of theirs, and the wall stays" % Vector2(far_cell).distance_to(Vector2(behind)))
		World.despawn(far_imp)
		_rig._sync_puppets()
	else:
		print("  (no floor cell beyond FIGHT_TILES of the wall in the test room: the far check skipped)")
	_place(player, start)
	await get_tree().create_timer(1.5).timeout
	_rig._update_fade(true)


func _test_person_monster() -> void:
	print("
== a monster kind drawn as a person: the grave robber ==")
	var row: Dictionary = Monster.kinds().get("robber", {})
	_check(not row.is_empty(), "the robber's row is there")
	if row.is_empty():
		return
	# The row as read (Monster.read_kinds), not the words set here: a kinds() that dropped "person"
	# drew the box's robbers as capsules (v0.1.165) while a test that set it passed.
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(Monster.KINDS_PATH))
	var written := str((raw as Dictionary).get("robber", {}).get("person", "")) if raw is Dictionary else ""
	var had: Variant = row.get("person")
	_check(written != "" and str(had) == written, "the robber's person words read from its row (%s)" % had)
	var robber := _spawn_imp(Vector2i(9, 6), "robber")
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets[robber.get_instance_id()]
	var scene := puppet.get_node("Body/Model") as Node3D
	var look := puppet.get_meta("look") as PersonLook if puppet.has_meta("look") else null
	var sockets: Dictionary = puppet.get_meta("sockets", {})
	var hood := scene.find_child("Hood", true, false) as MeshInstance3D
	_check(scene.scene_file_path in [Client3D.HUMAN["scene"], Client3D.HUMAN_F["scene"]] and look != null and hood != null and hood.visible
			and sockets.has("hand_r") and sockets.has("hand_l"),
			"a grave robber in the human body (%s), its look's words worn (its hood up: %s), a person's hands" % [scene.scene_file_path.get_file(), hood != null and hood.visible])
	# Its voice a person's, its look's body's (Jeff: "grave robbers are using monster death sounds").
	var body := look.body if look != null else &""
	var hurt := _heard(func() -> void: World.damage(robber, 1, null, &"attack"))
	_check(body in [&"male", &"female"] and ("voice.effort_hurt_%s" % body) in hurt and not "sfx.goblin_pain" in hurt,
			"a grave robber struck cries out as a %s person (%s)" % [body, hurt])
	var died := _heard(func() -> void: World.damage(robber, 999, null, &"attack"); _rig._process(0.0))
	_check(("voice.foe_death_%s" % body) in died and not ("voice.death_%s" % body) in died and "sfx.death_player" in died
			and not "sfx.goblin_death" in died,
			"and dies as one: a person's fall and a short grunt, not a player's scream nor a monster's (%s)" % [died])
	_rig._process(0.0)
	row.erase("person")
	var plain := _spawn_imp(Vector2i(9, 6), "robber")
	_rig._process(0.0)
	var plain_scene := (_rig._puppets[plain.get_instance_id()] as Node3D).get_node_or_null("Body/Model") as Node3D
	if had != null:
		row["person"] = had
	_check(plain_scene == null or not plain_scene.scene_file_path in [Client3D.HUMAN["scene"], Client3D.HUMAN_F["scene"]],
			"without the words, drawn as before")
	World.despawn(plain)
	_rig._process(0.0)


## A robber's told lunge read on his body (790 amended (7), animation's side): the telegraph's
## "lunge" draws his dagger back to its gather, holds it there through the tell and thrusts as it
## lands, his body out along his facing on the thrust; his plain blow kept off meanwhile; called
## off, it stops and his body is back at rest.
func _test_told_lunge() -> void:
	print("\n== a robber's told lunge: drawn back, held, thrust as it lands (790 amended (7)) ==")
	var robber := _spawn_imp(Vector2i(9, 6), "robber")
	robber.hands = PackedStringArray([str(Monster.kinds()["robber"]["wields"]["right"]), ""])  # His kind's, as a level arms him (Level._arm).
	World.face(robber, Vector2i(1, 0))
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets[robber.get_instance_id()]
	var rig := puppet.get_meta("rig") as AnimRig if puppet.has_meta("rig") else null
	var told: Array = Client3D.HUMANOID_MOVES["told"].get(World.wielded(robber), [])
	_check(rig != null and told.size() == 3 and rig.has(str(told[0])),
			"his told strike for what he holds (%s): %s" % [World.wielded(robber), told])
	if rig == null or told.size() < 3:
		World.despawn(robber)
		return
	var lands_ticks := 7
	var lands_in := lands_ticks * World.TICK_DT + Client3D.STRIKE_LANDS_IN
	var start := AnimRig.now_msec()
	_rig.creature_tell(21, {"id": 21, "source": str(robber.get_path()), "kind": "lunge", "lands_tick": World.tick + lands_ticks})
	_check(rig.striking() and rig.playing() == str(told[0]) and _rig._tells.get(21) == puppet
			and absi(rig.contact_msec - (start + int(lands_in * 1000.0))) <= 20,
			"the telegraph's lunge: %s, its contact as the drawn tell lands (%d ms, want %d)" % [rig.playing(), rig.contact_msec - start, int(lands_in * 1000.0)])
	_check(Time.get_ticks_msec() < int(puppet.get_meta("wound_until", 0)), "his plain blow kept off till then (wound_until)")
	await _until_msec(start + int((Client3D.TOLD_DRAW + 0.12) * 1000.0))
	var body := puppet.get_node("Body") as Node3D
	_check(is_zero_approx(rig.speed()) and absf(body.position.x) < 0.01,
			"drawn back and held at the gather (speed %.2f), not yet out (%.2f m)" % [rig.speed(), body.position.x])
	var furthest := 0.0
	var out_at := -1
	while AnimRig.now_msec() < start + int(lands_in * 1000.0) + 20:
		await get_tree().process_frame
		if body.position.x > furthest + 0.001:
			furthest = body.position.x
			out_at = AnimRig.now_msec() - start
	_check(furthest > Client3D.TOLD_REACH * 0.8 and rig.speed() > 0.0,
			"thrust as it lands: out %.2f m along his facing (furthest at %d ms), the recovery playing (speed %.2f)" % [furthest, out_at, rig.speed()])
	_rig.creature_tell_over(21, true)
	await _until_msec(AnimRig.now_msec() + int((Client3D.TOLD_RECOVER + 0.1) * 1000.0))
	_check(absf(body.position.x) < 0.02 and not _rig._tells.has(21), "and back at rest after (%.2f m)" % body.position.x)
	# Called off (stunned mid-tell): the thrust never comes, and he eases out of the gather (no snap).
	var skeleton := puppet.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var hand := func() -> Vector3:
		return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")).origin
	_rig.creature_tell(22, {"id": 22, "source": str(robber.get_path()), "kind": "lunge", "lands_tick": World.tick + lands_ticks})
	await _until_msec(AnimRig.now_msec() + int((Client3D.TOLD_DRAW + 0.05) * 1000.0))
	var held: Vector3 = hand.call()
	_rig.creature_tell_over(22, false)
	var was := held
	var jump := 0.0
	var off_at := AnimRig.now_msec()
	while AnimRig.now_msec() < off_at + int(lands_in * 1000.0):
		await get_tree().process_frame
		var now_at: Vector3 = hand.call()
		jump = maxf(jump, now_at.distance_to(was))
		was = now_at
	_check(not rig.striking() and absf(body.position.x) < 0.01 and int(puppet.get_meta("wound_until", 0)) == 0,
			"called off: stopped where it was, his body at rest (%.2f m), his blows his own again" % body.position.x)
	_check(was.distance_to(held) > 0.05 and jump < 0.6 * was.distance_to(held),
			"and eased out of the gather, not snapped: the hand %.2f m back to rest, at most %.2f m a frame" % [was.distance_to(held), jump])
	# Two robbers told at once: each his own timing (two rigs), one held while the other thrusts.
	var other := _spawn_imp(Vector2i(9, 9), "robber")
	other.hands = PackedStringArray([str(Monster.kinds()["robber"]["wields"]["right"]), ""])
	World.face(other, Vector2i(1, 0))
	_rig._process(0.0)
	var other_rig := (_rig._puppets[other.get_instance_id()] as Node3D).get_meta("rig") as AnimRig
	var both_from := AnimRig.now_msec()
	_rig.creature_tell(23, {"id": 23, "source": str(robber.get_path()), "kind": "lunge", "lands_tick": World.tick + 5})
	_rig.creature_tell(24, {"id": 24, "source": str(other.get_path()), "kind": "lunge", "lands_tick": World.tick + 12})
	var first_in := 5 * World.TICK_DT + Client3D.STRIKE_LANDS_IN
	var second_in := 12 * World.TICK_DT + Client3D.STRIKE_LANDS_IN
	_check(absi(rig.contact_msec - (both_from + int(first_in * 1000.0))) <= 20 and absi(other_rig.contact_msec - (both_from + int(second_in * 1000.0))) <= 20,
			"two robbers told at once: each lands on his own telegraph (%d and %d ms)" % [rig.contact_msec - both_from, other_rig.contact_msec - both_from])
	await _until_msec(both_from + int(first_in * 1000.0) + 20)
	_check(rig.speed() > 0.0 and is_zero_approx(other_rig.speed()),
			"the first thrust while the second still holds (speeds %.2f, %.2f)" % [rig.speed(), other_rig.speed()])
	_rig.creature_tell_over(23, true)
	_rig.creature_tell_over(24, false)
	World.despawn(other)
	World.despawn(robber)
	_rig._process(0.0)


## Steadied heard (843): a boss's "steady" plays his kind's set
## (SoundKit.steady_slot) and never a cry slot of its own; a blow on him the
## dull thud (SoundKit.HIT_STEADIED) in place of the hit, till "steady_over";
## an ordinary foe crying it (no server sends one) changes nothing.
func _test_steadied_heard() -> void:
	print("\n== steadied: his set heard by his kind, a blow on him dull till it's over (843) ==")
	var chief := _spawn_imp(Vector2i(9, 6), "robber_brute")
	_rig._process(0.0)
	var id := chief.get_instance_id()
	var plain := _heard(func() -> void: _rig._on_cried(&"steady", id))
	_check(not _rig._heard_steadied(chief) and plain.is_empty(), "an ordinary foe's \"steady\": nothing (%s)" % [plain])
	chief.boss = true
	var set_heard := _heard(func() -> void: _rig._on_cried(&"steady", id))
	_check(_rig._heard_steadied(chief) and set_heard == [SoundKit.steady_slot("robber_brute")],
			"a boss's: steadied, his kind's set (%s)" % [set_heard])
	var dull := _heard(func() -> void: World.damage(chief, 1, null, &"attack"); _rig._process(0.0))
	_check(SoundKit.HIT_STEADIED in dull and not "sfx.hit_flesh" in dull and not "sfx.hit_blunt_armor" in dull,
			"a blow on him steadied: the dull thud, not the hit (%s)" % [dull])
	var over := _heard(func() -> void: _rig._on_cried(&"steady_over", id))
	_check(not _rig._heard_steadied(chief) and over.is_empty(), "\"steady_over\": heard steadied no more, quietly (%s)" % [over])
	var again := _heard(func() -> void: World.damage(chief, 1, null, &"attack"); _rig._process(0.0))
	_check(not SoundKit.HIT_STEADIED in again and not again.is_empty(), "then the hit as ever (%s)" % [again])
	_rig._on_cried(&"steady", id)
	_rig._steadied[id] = AnimRig.now_msec() - 1
	_check(not _rig._heard_steadied(chief), "a lost \"steady_over\": it lapses (STEADY_HEARD_MS %d)" % Client3D.STEADY_HEARD_MS)
	World.despawn(chief)
	_rig._process(0.0)


## A blow's pain waits for the drawn blade to land (a timer); the body it
## struck dies and is freed inside that wait (836). Its callback holds ids,
## not nodes: before 836 it printed "Lambda capture at index 0 was freed"
## every time, which land.sh fails as an engine error, so that is the check.
func _test_blow_wait_outlives_body() -> void:
	print("
== a blow's wait outlives the body it struck: nothing freed is called (836) ==")
	var swinger := _spawn_imp(Vector2i(9, 6))
	var struck := _spawn_imp(Vector2i(10, 6))
	_rig._process(0.0)
	var now := AnimRig.now_msec()
	_rig._swings[swinger.get_instance_id()] = [now, "", now + 300]
	var lands := int(_rig._struck_with(struck)[1])
	_check(lands > now, "a swing beside it lands later (%d ms on)" % (lands - now))
	var puppet: Node3D = _rig._puppets.get(struck.get_instance_id())
	World.damage(struck, 1, null, &"attack")
	World.despawn(struck)
	_rig._process(0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not is_instance_valid(struck), "the struck body is freed inside the wait (its puppet may still be falling: %s)" % is_instance_valid(puppet))
	await get_tree().create_timer(0.5).timeout
	_check(true, "the wait has passed (an engine error above would fail the landing)")
	_rig._swings.erase(swinger.get_instance_id())
	World.despawn(swinger)
	_rig._process(0.0)


## The bandits dressed for the forest (793, pc-character's side): their rows' clothes=forest draws
## the tunic and trousers from PersonLook's FOREST_TUNICS and FOREST_TROUSERS, by the same draws as a
## town's colours, so every other word of a seed is as it was; a vest over it, the hood up. A grave
## robber's clothes=grave its greys and dirt browns (enemy-ai's rows), no vest; neither in a town's colours.
func _test_fishing_pose() -> void:
	print("\n== fishing seen: the cast, the wait, the bite, landed and missed (805 amended (6)) ==")
	var player := _player()
	if player == null:
		_check(false, "a player to fish")
		return
	var slots := player.slots
	while slots.size() < Items.CARRIED:
		slots.append("")
	var was := slots.duplicate()
	slots[Items.RIGHT_HAND] = "fishing_rod"
	slots[Items.LEFT_HAND] = ""
	player.slots = slots
	player.raised = ""
	var id := player.get_instance_id()
	var puppet: Node3D = _rig._puppets[id]
	for key: String in ["shuffle_until", "busy_until"]:
		puppet.set_meta(key, 0)
	puppet.set_meta("turning", false)
	puppet.set_meta("turned_ms", -1)
	puppet.set_meta("speed", 0.0)
	puppet.set_meta("last_at", puppet.position)
	puppet.set_meta("last_ms", Time.get_ticks_msec())
	_rig._process(0.0)
	var rig := puppet.get_meta("rig") as AnimRig
	var sockets: Dictionary = puppet.get_meta("sockets")
	_check((sockets["hand_r"] as Node3D).has_node("Held") and Client3D.rod_tip(puppet) != null and rig.has("Fish_Cast")
			and rig.has(Client3D.FISH_HOLD), "the rod in the right hand, its tip found; the clips in the library")
	var played := {}
	for state: String in ["cast", "wait", "bite", "landed", "missed"]:
		puppet.set_meta("busy_until", 0)
		player.fishing = {"state": state, "at": player.tile + Vector2i(0, 2)}
		_rig._process(0.0)
		played[state] = rig.base_clip()
	var want := {}
	for state: String in Client3D.FISH_CLIPS:
		want[state] = Client3D.FISH_CLIPS[state]
	_check(played == want, "each state its clip: %s" % played)
	# Waiting: the rod held out ahead and up, its tip where the line leaves it.
	player.fishing = {"state": "wait", "at": player.tile + Vector2i(0, 2)}
	puppet.set_meta("busy_until", 0)
	for i in 30:
		await get_tree().process_frame
	var tip: Variant = Client3D.rod_tip(puppet)
	var model := puppet.get_node("Body/Model") as Node3D
	var ahead := -model.global_basis.z.normalized() if model != null else Vector3.FORWARD
	var reach := Vector3(tip.x - puppet.global_position.x, 0.0, tip.z - puppet.global_position.z) if tip is Vector3 else Vector3.ZERO
	var up := float(tip.y - puppet.global_position.y) if tip is Vector3 else 0.0
	_check(tip is Vector3 and up > 1.5 and up < 2.5 and reach.length() > 0.9 and reach.length() < 2.2,
			"waiting: the tip out and up, %.2f m up, %.2f m out (%s; the model's front %s)" % [up, reach.length(), rig.base_clip(), ahead])
	# The line in water heard while it waits, and only then (805 amended (9)).
	var key := String(player.name)
	var cast: Dictionary = _rig.fishing_view.casts.get(key, {})
	var lap: Variant = cast.get("lap")
	var held := lap != null and is_instance_valid(lap) and str(lap.get_meta("slot", "")) == "sfx.fish_wait"
	# Its takes are external (synced from the sound library), as the bow's creak: a
	# checkout without them holds none (Sfx.hold's null).
	var lapping := not SoundKit.files("sfx.fish_wait").is_empty()
	_check(held == lapping, "waiting: the float's lap held at it (%s; takes here: %s)" % [held, lapping])
	# The bite read without sound (animation's take 2): a big red-capped float,
	# a slack line that goes taut at the bite, two tugs at the splashes.
	var fv: Node = _rig.fishing_view
	var bobber: Node3D = cast.get("float")
	var cap: MeshInstance3D = bobber.get_child(0) as MeshInstance3D if bobber != null and bobber.get_child_count() == 1 else null
	_check(cap != null and (cap.material_override as StandardMaterial3D).albedo_color.is_equal_approx(fv.FLOAT_RED)
			and (cap.mesh as SphereMesh).is_hemisphere and is_equal_approx(((bobber as MeshInstance3D).mesh as SphereMesh).radius, fv.FLOAT_RADIUS),
		"the float: %.2f m, its upper half red (%s)" % [fv.FLOAT_RADIUS, bobber.get_children() if bobber != null else "none"])
	var line_points := func() -> PackedVector3Array:
		var mesh := (cast["line"] as MeshInstance3D).mesh as ImmediateMesh
		return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] if mesh.get_surface_count() > 0 else PackedVector3Array()
	var slack: PackedVector3Array = line_points.call()
	var middle := slack[slack.size() / 2] if slack.size() > 2 else Vector3.ZERO
	var straight := slack[0].lerp(slack[-1], 0.5) if slack.size() > 2 else Vector3.ZERO
	_check(slack.size() > 2 and middle.y < straight.y - 0.2, "waiting: the line hangs slack (%d points, %.2f m low at its middle)" % [slack.size(), straight.y - middle.y])
	player.fishing = {"state": "bite", "at": player.tile + Vector2i(0, 2)}
	for i in 2:
		await get_tree().process_frame
	_check((line_points.call() as PackedVector3Array).size() == 2, "the bite: the line drawn straight and taut")
	_check(is_equal_approx(fv.tug(0.0), 0.0) and is_equal_approx(fv.tug(fv.TUG_DOWN), 1.0) and is_equal_approx(fv.tug(0.9), 0.0)
			and is_equal_approx(fv.tug(1.2 + fv.TUG_DOWN), 1.0) and fv.BITE_TUGS.size() == 2 and fv.BITE_TUGS[0] == 0.0 and fv.BITE_TUGS[1] == fv.BITE_SPLASH_AGAIN,
		"the bite: tugged right under twice, at its start and at the second splash")
	player.fishing = {"state": "missed", "at": player.tile + Vector2i(0, 2)}
	for i in 2:
		await get_tree().process_frame
	cast = _rig.fishing_view.casts.get(key, {})
	_check(cast.get("lap") == null and (lap == null or not is_instance_valid(lap) or lap.is_queued_for_deletion()),
			"missed: the lap stopped as the float lifts out")
	player.fishing = {"state": "wait", "at": player.tile + Vector2i(0, 2)}  # Back as it was: the miss's clip not left playing.
	puppet.set_meta("busy_until", 0)
	_rig._process(0.0)
	puppet.set_meta("busy_until", 0)
	player.fishing = {}
	_rig._process(0.0)
	_check(not puppet.has_meta("fish_state") and not rig.base_clip().begins_with("Fish"), "reeled in: the next cast casts again, and it stands (%s)" % rig.base_clip())
	player.slots = was
	_rig._process(0.0)


## Fish rising (805 amended (10), "fish rise"): rings only on water that
## fishes, more often the keener the fish feed, none by a float.
func _test_fish_rise() -> void:
	print("
== fish rising: rings on fishing water, oftener as they feed (805 amended (10)) ==")
	var fv: Node = _rig.fishing_view
	var player := _player()
	var base: Vector2i = player.tile + Vector2i(3, 3) if player != null else Vector2i(10, 10)
	var water: Array[Vector2i] = []
	for y in 4:
		for x in 4:
			water.append(base + Vector2i(x, y))
	var puddle: Array[Vector2i] = [base + Vector2i(8, 0), base + Vector2i(9, 0)]  # Small water fishes too (805 amended (11)).
	var terrain := {"water": water + puddle}
	fv.rose.clear()
	# The most rings showing at once over a run: its last step may fall
	# between two rises (a ring's RISE_SECONDS under the gap), so the end alone
	# says nothing.
	var seen := {"most": 0}
	var count_at := func(keen: float, seconds: float) -> int:
		fv.feeding_override = keen
		fv.rose.clear()
		fv._next_rise.clear()
		seen["most"] = 0
		var t := 0.0
		while t < seconds:
			fv._clock += 0.1
			t += 0.1
			fv.step_rises(terrain)
			var showing := 0
			for rise: Dictionary in fv.rises:
				showing += 1 if (rise["ring"] as MeshInstance3D).visible else 0
			seen["most"] = maxi(seen["most"], showing)
		return fv.rose.size()
	var slow: int = count_at.call(0.0, 120.0)
	var on_water := true
	for entry: Array in fv.rose:
		on_water = on_water and (terrain["water"] as Array).has(entry[1])
	var fast: int = count_at.call(1.0, 120.0)
	for entry: Array in fv.rose:
		on_water = on_water and (terrain["water"] as Array).has(entry[1])
	_check(fv.bodies.size() == 2, "both bodies fish, the 16-cell pool and the 2-cell puddle (%s)" % [fv.bodies.keys()])
	_check(on_water and slow > 0 and fast > slow * 3, "rings only on water, %d in two minutes hardly feeding, %d at their keenest" % [slow, fast])
	_check(fv.rises.size() <= 4 and seen["most"] >= 1, "the rings reused, %d made for %d rises (%d showing at most)" % [fv.rises.size(), fast, seen["most"]])
	# A float on the pool: no rise within RISE_CLEAR of it.
	if player != null:
		player.fishing = {"state": "wait", "at": base + Vector2i(1, 1)}
		fv._process(0.0)
		count_at.call(1.0, 60.0)
		var clear := true
		for entry: Array in fv.rose:
			clear = clear and Vector2(entry[1]).distance_to(Vector2(base + Vector2i(1, 1))) >= fv.RISE_CLEAR
		_check(clear and fv.rose.size() > 0, "none within %.0f m of a float (%d elsewhere)" % [fv.RISE_CLEAR, fv.rose.size()])
		player.fishing = {}
		fv._process(0.0)
	fv.feeding_override = -1.0
	fv.read_waters(_rig._terrain)
	for rise: Dictionary in fv.rises:
		(rise["ring"] as MeshInstance3D).visible = false
		(rise["splash"] as MeshInstance3D).visible = false


func _test_bandit_look() -> void:
	print("\n== the bandits dressed for the forest (793, pc-character's side) ==")
	var plain := PersonLook.make("seed=4242 headwear=hood garb=vest apron=no")
	var forest := PersonLook.make("seed=4242 headwear=hood garb=vest apron=no clothes=forest")
	_check(forest.clothes == "forest" and plain.clothes == "" and forest.build == plain.build and forest.hair == plain.hair
			and forest.skin == plain.skin and forest.keys == plain.keys and forest.parts == plain.parts and forest.scale == plain.scale,
			"clothes=forest changes only the clothes' colours: the seed's body, face and parts the same")
	var forest_tunics := PersonLook.FOREST_TUNICS.map(func(h: String) -> Color: return Color(h))
	var forest_trousers := PersonLook.FOREST_TROUSERS.map(func(h: String) -> Color: return Color(h))
	var town_tunics := PersonLook.TUNICS.map(func(h: String) -> Color: return Color(h))
	var grave_tunics := PersonLook.GRAVE_TUNICS.map(func(h: String) -> Color: return Color(h))
	var grave_trousers := PersonLook.GRAVE_TROUSERS.map(func(h: String) -> Color: return Color(h))
	var seen := {}
	var off := []
	for seed in 40:
		var each := PersonLook.make("seed=%d clothes=forest" % seed)
		var tunic: Color = each.colours["tunic"]
		if not tunic in forest_tunics or not each.colours["trousers"] in forest_trousers or tunic in town_tunics:
			off.append(seed)
		seen[tunic.to_html(false)] = true
		var grave := PersonLook.make("seed=%d clothes=grave" % seed)
		var grey: Color = grave.colours["tunic"]
		if grave.clothes != "grave" or not grey in grave_tunics or not grave.colours["trousers"] in grave_trousers or grey in town_tunics or grey in forest_tunics:
			off.append(-seed - 1)
	_check(off.is_empty() and seen.size() >= 3, "40 seeds: each in a forest (or with clothes=grave, a grave) tunic and trousers, %d forest tunics of %d among them (off: %s)" % [
			seen.size(), PersonLook.FOREST_TUNICS.size(), off])
	var shown := []
	for kind: String in ["bandit", "bandit_brute", "robber"]:
		var entity := _spawn_imp(Vector2i(9 + shown.size(), 6), kind)
		_rig._process(0.0)
		var puppet: Node3D = _rig._puppets[entity.get_instance_id()]
		var scene := puppet.get_node_or_null("Body/Model") as Node3D
		var body := scene.find_child("Body", true, false) as MeshInstance3D if scene != null else null
		var tunic: Variant = body.get_instance_shader_parameter("tunic") if body != null else null
		var vest := scene.find_child("Vest", true, false) as MeshInstance3D if scene != null else null
		var hood := scene.find_child("Hood", true, false) as MeshInstance3D if scene != null else null
		var dressed: bool = tunic is Color and (tunic in (grave_tunics if kind == "robber" else forest_tunics))
		_check(dressed and hood != null and hood.visible and vest != null and vest.visible == (kind != "robber"),
				"%s: %s, the hood up, %s" % [kind, ("in the forest's %s" if kind != "robber" else "in the grave's %s") % (tunic.to_html(false) if tunic is Color else "nothing"),
				"a vest over it" if vest != null and vest.visible else "no vest"])
		shown.append(entity)
	for entity: Monster in shown:
		World.despawn(entity)
	_rig._process(0.0)


func _test_allies() -> void:
	print("
== the Blood Rot's allies (decision 478): the brute an orc, the sneak a kobold, each its own ==")
	var orcs: Array[Monster] = [_spawn_imp(Vector2i(9, 6), "brute"), _spawn_imp(Vector2i(10, 6), "brute")]
	var kobold := _spawn_imp(Vector2i(11, 6), "sneak")
	_rig._process(0.0)
	for entity: Monster in orcs + [kobold]:
		var puppet: Node3D = _rig._puppets[entity.get_instance_id()]
		var people := str(Client3D.MODELS[str(entity.spawn_spec["kind"])]["people"])
		var look := puppet.get_meta("look") as PersonLook
		var scene := puppet.get_node("Body/Model") as Node3D
		var shown := []
		for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			if mesh.visible and mesh.get_parent() is Skeleton3D and mesh.name != "Body":
				shown.append(String(mesh.name))
		var allowed: Array = ["Hair_Cropped", "Hair_Bound"] if people == "orc" else []
		_check(look.people == people and (PersonLook.PEOPLE_SKINS[people] as Array).has(look.colours["skin"].to_html(false))
				and shown.all(func(part: String) -> bool: return part in allowed)
				and look.posture == PersonLook.PEOPLE_POSTURES[people],
				"a %s: %s's skin (%s), only its own parts (%s), %s" % [entity.spawn_spec["kind"], people, look.colours["skin"].to_html(false), shown, look.posture])
		var rig := puppet.get_meta("rig") as AnimRig
		var sockets: Dictionary = puppet.get_meta("sockets", {})
		var model_fidgets: Dictionary = Client3D.MODELS[str(entity.spawn_spec["kind"])]["fidgets"]
		_check((rig.playing() == Client3D.CLIP_IDLE or model_fidgets.has(rig.playing())) and sockets.has("hand_r") and sockets.has("hand_l"),
				"its clips play on it (%s) and it has hands to hold things" % rig.playing())
	var heights := []
	for puppet: Node3D in [_rig._puppets[orcs[0].get_instance_id()], _rig._puppets[kobold.get_instance_id()]]:
		var top := 0.0
		for mesh: MeshInstance3D in (puppet.get_node("Body/Model") as Node3D).find_children("Body", "MeshInstance3D", true, false):
			top = maxf(top, mesh.get_aabb().end.y * float(puppet.get_meta("model_scale")))
		heights.append(snappedf(top, 0.01))
	_check(absf(heights[0] - 1.95) < 0.15 and absf(heights[1] - 1.0) < 0.1,
			"an orc stands about 1.95 m, a kobold about 1 m (%s)" % [heights])
	# The orc and the kobold in their own paint (decision 529): their skins in
	# <people>_body.tres (a hand-made body's parts on art-kit's palette keep it), each its own by
	# its name (painted_look), with no second hunch over its mesh's.
	var painted := []
	for orc: Monster in orcs + [kobold]:
		var puppet: Node3D = _rig._puppets[orc.get_instance_id()]
		var body := (puppet.get_node("Body/Model") as Node3D).find_child("Body", true, false) as MeshInstance3D
		var look: Dictionary = puppet.get_meta("painted_look", {})
		painted.append(look)
		var paint := load(str(Client3D.MODELS[str(orc.spawn_spec["kind"])]["paint"]))
		var skinned := body != null and range(body.mesh.get_surface_count()).all(func(i: int) -> bool:
			var own := body.mesh.surface_get_material(i)
			var palette := own != null and own.resource_name == ArtKit.PALETTE_NAME
			return (body.get_surface_override_material(i) == paint) != palette)
		_check(skinned
				and look == Client3D.painted_look(String(orc.name))
				and body.get_instance_shader_parameter("skin") == look["skin"] and body.get_instance_shader_parameter("mark") == look["mark"]
				and (puppet.get_meta("rig") as AnimRig)._posture == null,
				"a %s in its own paint, its look its name's (%s), no posture over its stance" % [orc.spawn_spec["kind"], str(look.get("words", ""))])
	_check(painted[0] != painted[1], "two orcs differ")
	# Outlined (hovered, targeted) and let go, as a body is when it dies, it keeps its paint
	# (Jeff: "killed a brute and sneak and the corpses had no palette").
	for orc: Monster in [orcs[0], kobold]:
		var puppet: Node3D = _rig._puppets[orc.get_instance_id()]
		var meshes := (puppet.get_node("Body") as Node3D).find_children("*", "MeshInstance3D", true, false)
		var before := meshes.map(func(mesh: MeshInstance3D) -> Array:
			return range(mesh.get_surface_override_material_count()).map(func(i: int) -> Material: return mesh.get_surface_override_material(i)))
		_rig._show_outline(puppet, true)
		var marked := meshes.map(func(mesh: MeshInstance3D) -> Array:
			return range(mesh.get_surface_override_material_count()).map(func(i: int) -> Material: return mesh.get_surface_override_material(i)))
		_rig._show_outline(puppet, false)
		var after := meshes.map(func(mesh: MeshInstance3D) -> Array:
			return range(mesh.get_surface_override_material_count()).map(func(i: int) -> Material: return mesh.get_surface_override_material(i)))
		_check(marked != before and after == before,
				"a %s outlined and let go keeps its paint, as a corpse does" % orc.spawn_spec["kind"])
	# Their fidgets (Jeff: "the idle need variability"): their own, never the same twice
	# running, timed by a generator of this run's (the name and _session_seed).
	var orc_puppet: Node3D = _rig._puppets[orcs[0].get_instance_id()]
	var orc_rig := orc_puppet.get_meta("rig") as AnimRig
	_rig._combat_at.erase(orcs[0].get_instance_id())
	var picked: Array[String] = []
	for i in 30:
		orc_puppet.set_meta("fidget_at", 0)
		orc_puppet.set_meta("busy_until", 0)
		orc_puppet.set_meta("fidgeting", false)
		_rig._animate(orc_puppet)
		picked.append(orc_rig.playing())
	var kinds := {}
	for clip in picked:
		kinds[clip] = true
	_check(picked.all(func(clip: String) -> bool: return Client3D.ORC_FIDGETS.has(clip)) and kinds.size() >= 3
			and range(1, picked.size()).all(func(i: int) -> bool: return picked[i] != picked[i - 1]),
			"an orc fidgets its own ways, never the same twice running (%s)" % [kinds.keys()])
	var fidget_rng := orc_puppet.get_meta("fidget_rng") as RandomNumberGenerator
	_check(fidget_rng != null and fidget_rng.seed == hash(String(orcs[0].name)) ^ Client3D._session_seed
			and (orc_puppet.get_meta("rng") as RandomNumberGenerator).seed == hash(String(orcs[0].name)),
			"when it fidgets is this run's (its name and the session's seed); its size and blows its name's alone")
	_check(Client3D.HUMAN_FIDGETS.size() >= 5 and Client3D.HUMAN_FIDGETS.values().min() == Client3D.HUMAN_FIDGETS["Idle_LookAround"]
			and Client3D.HUMAN_FIDGETS.keys().all(func(clip: String) -> bool: return orc_rig.has(clip)),
			"a person has %d fidgets in the library, the head scratch the rarest" % Client3D.HUMAN_FIDGETS.size())
	for entity: Monster in orcs + [kobold]:
		World.despawn(entity)
	_rig._process(0.0)


## The barrow's dead (art-kit's by hand, rigged on the human skeleton): the skeleton and the barrow
## guard each their creature.skeleton variant, on the shared palette, a man's height, their clips
## and their hands the human ones.
func _test_barrow_dead() -> void:
	print("
== the barrow's dead: the skeleton, its guard, the draugr, the ghost ==")
	var dead: Array[Monster] = [_spawn_imp(Vector2i(9, 6), "skeleton"), _spawn_imp(Vector2i(10, 6), "skeleton_guard"),
		_spawn_imp(Vector2i(11, 6), "draugr"), _spawn_imp(Vector2i(12, 6), "ghost")]
	_rig._process(0.0)
	var palette := load(ArtKit.PALETTE)
	for entity: Monster in dead:
		var kind := str(entity.spawn_spec["kind"])
		var puppet: Node3D = _rig._puppets[entity.get_instance_id()]
		var scene := puppet.get_node("Body/Model") as Node3D
		var body := scene.find_child("Body", true, false) as MeshInstance3D
		var painted := body != null and range(body.mesh.get_surface_count()).all(func(i: int) -> bool:
			return body.get_surface_override_material(i) == palette)
		var top := body.get_aabb().end.y * float(puppet.get_meta("model_scale")) if body != null else 0.0
		var rig := puppet.get_meta("rig") as AnimRig
		var sockets: Dictionary = puppet.get_meta("sockets", {})
		_check(scene.scene_file_path == Client3D.MODELS[kind]["scene"] and painted and absf(top - float(Client3D.MODELS[kind]["height"])) < 0.15
				and (rig.playing() == Client3D.CLIP_IDLE or Client3D.DEAD_FIDGETS.has(rig.playing()))
				and sockets.has("hand_r") and sockets.has("hand_l"),
				"a %s: its own body on the palette, %.2f m, its clips playing (%s), hands to hold things" % [kind, top, rig.playing()])
	var guard := (_rig._puppets[dead[1].get_instance_id()] as Node3D).get_node("Body/Model").find_child("Body", true, false) as MeshInstance3D
	var plain := (_rig._puppets[dead[0].get_instance_id()] as Node3D).get_node("Body/Model").find_child("Body", true, false) as MeshInstance3D
	_check(guard.get_aabb().size.x > plain.get_aabb().size.x or guard.mesh.surface_get_array_len(0) > plain.mesh.surface_get_array_len(0),
			"the guard wears more than the plain skeleton (its helm, mail and shield)")
	var ghost := (_rig._puppets[dead[3].get_instance_id()] as Node3D).get_node("Body/Model") as Node3D
	var shadows := {}
	for mesh: MeshInstance3D in ghost.find_children("*", "MeshInstance3D", true, false):
		var own := mesh.mesh.surface_get_material(0)
		shadows[own.resource_name if own != null else ""] = mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_check(shadows.get(Client3D.GHOST_MATERIAL) == false and shadows.get(ArtKit.PALETTE_NAME) == true,
			"the ghost's shroud casts no shadow, its bones do (%s)" % shadows)
	# Gone (573 amended (4); Jeff: the draugr "should not lie down, he is otherworldly"): one holding
	# no cell is not drawn, at once; back, it eases in (REACH_EASE) where it stands again.
	var draugr_puppet: Node3D = _rig._puppets[dead[2].get_instance_id()]
	dead[2].holds_cell = false
	_rig._process(0.0)
	var hidden := not draugr_puppet.visible
	dead[2].holds_cell = true
	_rig._process(0.0)
	_check(hidden and draugr_puppet.visible and draugr_puppet.has_meta("reach_at"),
			"gone, the draugr's body is not drawn; back, it eases in (hidden %s, shown %s)" % [hidden, draugr_puppet.visible])
	# His remains (art-kit's prop.draugr_remains): while he is gone they lie on the cell he fell on,
	# turned his pile_facing; back, they are taken away.
	World.despawn(dead[2])  # His cell, for a draugr of his own script.
	var draugr := _main._spawn({"script": "res://sim/draugr.gd", "shape": "capsule", "kind": "draugr", "name": "ViewDraugr", "tile": Vector2i(11, 6)}) as Draugr
	draugr.pile_at = Vector2i(11, 7)
	draugr.pile_facing = Vector2i(1, 0)
	draugr.gone = true
	_rig._process(0.0)
	var remains: Node3D = _rig._remains.get(draugr.get_instance_id())
	var at := Vector3(11, _rig._ground_height(Vector2(11, 7)), 7)
	_check(remains != null and remains.position.is_equal_approx(at) and is_equal_approx(remains.rotation.y, atan2(1.0, 0.0))
			and remains.find_children("*", "MeshInstance3D", true, false).size() > 0,
			"gone, his remains lie on pile_at turned pile_facing (%s, %s)" % [remains.position if remains != null else null, remains.rotation.y if remains != null else null])
	draugr.gone = false
	_rig._process(0.0)
	_check(remains != null and not _rig._remains.has(draugr.get_instance_id()) and remains.is_queued_for_deletion(), "back, his remains are taken away")
	World.despawn(draugr)
	# At rest (631 amended; Jeff: "lying down on ground, clipping through walls"): the skeleton and its
	# guard stand on their cell at their idle, not tipped over, and every joint of the posed body (with a
	# hand's breadth of flesh) stays inside the cell at all eight facings, so none crosses a wall edge.
	for entity: Monster in [dead[0], dead[1]]:
		entity.lay_down()
		var puppet: Node3D = _rig._puppets[entity.get_instance_id()]
		var worst := 0.0
		var tipped := false
		for way: Vector2i in Monster.AROUND:
			World.face(entity, way)
			for i in 10:
				_rig._process(0.05)
			var rig := puppet.get_meta("rig") as AnimRig
			if rig.tree != null:
				rig.tree.advance(0.5)
			tipped = tipped or bool(puppet.get_meta("lying", false)) or not is_zero_approx((puppet.get_node("Body") as Node3D).rotation.x)
			var skeleton: Skeleton3D = null
			for each: Skeleton3D in puppet.find_children("*", "Skeleton3D", true, false):
				skeleton = each
			if skeleton == null:
				worst = INF
				continue
			var middle := puppet.global_position
			for bone in skeleton.get_bone_count():
				var joint := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
				worst = maxf(worst, maxf(absf(joint.x - middle.x), absf(joint.z - middle.z)) + REST_FLESH)
		_check(entity.laid and not World.is_down(entity) and not tipped and worst <= 0.5,
				"a %s at rest stands on its cell at every facing: not lying, its farthest joint %.2f of a cell's half 0.5" % [World.kind_of(entity), worst])
	for entity: Monster in dead:
		World.despawn(entity)
	_rig._process(0.0)


## A hand's breadth of flesh round a joint (the rest check of the barrow's dead).
const REST_FLESH := 0.08



## The surfaces [param puppet]'s model drew on both sides (its own material double-sided, as a .glb's
## doubleSided gives) but its drawn material culls (a ShaderMaterial without cull_disabled, a BaseMaterial3D
## not CULL_DISABLED): "mesh/surface" each. A surface drawn in the kit's palette is left out: palette.tres
## culls back faces everywhere by rule, and the kit keeps those meshes closed (the orc's gear, surface 0).
static func _sides_dropped(puppet: Node3D) -> Array[String]:
	var out: Array[String] = []
	for m: MeshInstance3D in puppet.find_children("*", "MeshInstance3D", true, false):
		if not m.get_parent() is Skeleton3D or m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var own := m.mesh.surface_get_material(s)
			var drawn: Material = m.material_override if m.material_override != null else m.get_surface_override_material(s)
			if drawn == null:
				drawn = own
			if drawn != null and drawn.resource_path == ArtKit.PALETTE:
				continue
			var both := func(mat: Material) -> bool:
				if mat is BaseMaterial3D:
					return (mat as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED
				if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null:
					return "cull_disabled" in (mat as ShaderMaterial).shader.code
				return false
			if both.call(own) and not both.call(drawn):
				out.append("%s/%d" % [m.name, s])
	return out

func _test_goblins_differ() -> void:
	print("\n== no two goblins alike: size by mass, their own pace and tempo, out of step; they look about, and stand tired ==")
	var imps: Array[Monster] = [_spawn_imp(Vector2i(9, 2), "imp"), _spawn_imp(Vector2i(10, 2), "imp")]
	var brute := _spawn_imp(Vector2i(11, 2), "brute")
	brute.mass = 70.0  # Before its puppet is made.
	_rig._process(0.0)
	var a: Node3D = _rig._puppets[imps[0].get_instance_id()]
	var b: Node3D = _rig._puppets[imps[1].get_instance_id()]
	var big: Node3D = _rig._puppets[brute.get_instance_id()]
	_check(big.has_meta("rig"), "a brute is modelled too")
	var looks := func(puppet: Node3D) -> Array:
		return [snappedf(puppet.get_meta("model_scale"), 0.001), snappedf(puppet.get_meta("pace"), 0.001), snappedf(puppet.get_meta("tempo"), 0.001)]
	_check(looks.call(a) != looks.call(b), "two imps differ in size, pace or tempo (%s, %s)" % [looks.call(a), looks.call(b)])
	_check(absf(float(a.get_meta("model_scale")) - 1.0) <= Client3D.MODEL_SCALE_SPREAD + 0.001,
			"an imp is about the goblin's size (x%.2f)" % a.get_meta("model_scale"))
	var tall := func(puppet: Node3D, model: Dictionary) -> float:
		return float(model["height"]) * float(puppet.get_meta("model_scale"))
	_check(tall.call(big, Client3D.MODELS["brute"]) > tall.call(a, Client3D.MODELS["imp"]) * 1.4,
			"and the brute, an orc, much bigger (%.2f m, an imp %.2f m)" % [tall.call(big, Client3D.MODELS["brute"]), tall.call(a, Client3D.MODELS["imp"])])
	# Their looks (decision 494): by name, alike on every peer; one material for them all.
	var la: Dictionary = a.get_meta("goblin_look")
	var lb: Dictionary = b.get_meta("goblin_look")
	_check(la == Client3D.goblin_look(String(imps[0].name)) and la != lb,
			"each goblin its own look by its name (%s | %s)" % [la["words"], lb["words"]])
	var shared := [a, b].all(func(p: Node3D) -> bool:
		return p.find_children("*", "MeshInstance3D", true, false).filter(func(m: MeshInstance3D) -> bool: return m.get_parent() is Skeleton3D).all(
			func(m: MeshInstance3D) -> bool: return m.material_override == Client3D.GOBLIN_MATERIAL))
	var body_mesh := a.find_children("*", "MeshInstance3D", true, false).filter(func(m: MeshInstance3D) -> bool: return m.get_parent() is Skeleton3D)[0] as MeshInstance3D
	var skin: Vector3 = body_mesh.get_instance_shader_parameter("skin")
	_check(shared and skin == la["skin"], "drawn in the one shared material, its look as instance parameters (skin %s)" % skin)
	# Both sides drawn where its own model drew both (494 amended (3), Jeff 11-11: "snagfin has some see through
	# body parts"): the goblin's .glb material is double-sided over faces wound inward, so a material drawing
	# it in their place that culls back faces puts holes in it.
	var dropped: Array[String] = []
	for puppet: Node3D in [a, big]:
		dropped.append_array(_sides_dropped(puppet))
	_check(dropped.is_empty(), "a goblin and an orc drawn on both sides where their own models were (%s)" % ("none dropped" if dropped.is_empty() else ", ".join(dropped)))
	# And every triangle its .blend has (494 amended (3), perf's word for bodies of 1.5k to 3.3k tris): no
	# character scene imported with Godot's generated LODs, which merge a faceted figure's planes when small.
	var decimated: Array[String] = []
	var scenes: Array[String] = [str(Client3D.HUMAN["scene"]), str(Client3D.HUMAN_F["scene"])]
	for kind: String in Client3D.MODELS:
		var path := str(Client3D.MODELS[kind].get("scene", ""))
		if path.begins_with("res://art/models/characters/") and path not in scenes:
			scenes.append(path)
	for path in scenes:
		var config := ConfigFile.new()
		if config.load(path + ".import") != OK or bool(config.get_value("params", "meshes/generate_lods", true)):
			decimated.append(path.get_file())
	_check(decimated.is_empty(), "%d character models imported whole, no generated LODs (%s)" % [scenes.size(), "none" if decimated.is_empty() else ", ".join(decimated)])
	var marked := 0
	var stocky_or_lean := 0
	for i in 40:
		var look := Client3D.goblin_look("Raider%d" % i)
		if (look["mark"] as Vector3) != Vector3.ZERO:
			marked += 1
		if "build=" in str(look["words"]):
			stocky_or_lean += 1
	_check(marked > 5 and marked < 30 and stocky_or_lean > 5, "a raid of 40: %d marked, %d lean or stocky" % [marked, stocky_or_lean])
	# Its hood and ears (494 amended): the hood its own mesh, shown or not; its ears' shape keys.
	var hood_mesh := a.find_children("Hood", "MeshInstance3D", true, false)
	var goblin_body: MeshInstance3D = a.find_children("*", "MeshInstance3D", true, false).filter(func(m: MeshInstance3D) -> bool:
		return m.name != "Hood" and m.get_parent() is Skeleton3D)[0]
	var big_key := goblin_body.find_blend_shape_by_name("Ears_Big")
	var small_key := goblin_body.find_blend_shape_by_name("Ears_Small")
	_check(hood_mesh.size() == 1 and (hood_mesh[0] as MeshInstance3D).visible == bool(la["hood"]) and big_key >= 0 and small_key >= 0
			and is_equal_approx(goblin_body.get_blend_shape_value(big_key), maxf(float(la["ears"]), 0.0))
			and is_equal_approx(goblin_body.get_blend_shape_value(small_key), maxf(-float(la["ears"]), 0.0)),
			"its hood %s, its ears %.2f" % ["up" if la["hood"] else "down", la["ears"]])
	var bare := 0
	for i in 40:
		if not Client3D.goblin_look("Raider%d" % i)["hood"]:
			bare += 1
	_check(bare == 0, "a raid of 40: %d bare-headed (every goblin hooded for now, 494 amended (3))" % bare)
	# A goblin among the townsfolk (decision 471, Snagfin): its kind's body, never a person's; hooded, as
	# every goblin is for now (494 amended (3): the script's bare head is not Jeff's work).
	var occupant := World.get_entity_at(Vector2i(12, 2))
	if occupant != null:
		World.despawn(occupant)
	var merchant: GridEntity = _main._spawn({"script": "res://sim/resident.gd", "shape": "capsule", "name": "Resident_snagfin_view",
		"tile": Vector2i(12, 2), "kind": "imp", "label": "Snagfin [merchant]", "look": "seed=1 body=male"})
	_rig._process(0.0)
	var his: Node3D = _rig._puppets.get(merchant.get_instance_id())
	var his_model := his.get_node_or_null("Body/Model") if his != null else null
	var hoods: Array = his_model.find_children("Hood", "MeshInstance3D", true, false) if his_model != null else []
	_check(his_model != null and his_model.scene_file_path == str(Client3D.MODELS["imp"]["scene"]) and hoods.size() == 1
			and (hoods[0] as MeshInstance3D).visible and not "hood=down" in str(his.get_meta("goblin_look")["words"]),
			"a goblin resident is the goblin, its hood up (%s)" % [his_model.scene_file_path if his_model != null else "no model"])
	World.despawn(merchant)
	_rig._process(0.0)
	var animators: Array[AnimRig] = [a.get_meta("rig"), b.get_meta("rig")]
	_check(absf(animators[0].position() - animators[1].position()) > 0.01,
			"standing side by side, out of step (%.2f s, %.2f s into Idle)" % [animators[0].position(), animators[1].position()])
	var again := RandomNumberGenerator.new()
	again.seed = hash(String(imps[0].name))
	_check(is_equal_approx(float(a.get_meta("model_scale")), clampf(1.0, Client3D.MODEL_SCALE_MIN, Client3D.MODEL_SCALE_MAX)
			* (1.0 + again.randf_range(-Client3D.MODEL_SCALE_SPREAD, Client3D.MODEL_SCALE_SPREAD))),
			"each the same on every view: seeded by its name")
	_check([a, b, big].all(func(p: Node3D) -> bool: return absf(float(p.get_meta("tempo")) - 1.0) <= Client3D.TEMPO_SPREAD + 0.001),
			"each its own tempo, within %d%%" % roundi(Client3D.TEMPO_SPREAD * 100.0))
	_rig._combat_at.erase(imps[0].get_instance_id())
	var fidgets: Array[String] = []
	# A fixed draw: its own rng is seeded by the session too, and 40 draws by weight
	# sometimes put another clip ahead of looking about (art-kit's landing, 2026-10-19).
	var steady := RandomNumberGenerator.new()
	steady.seed = 1
	a.set_meta("fidget_rng", steady)
	for i in 40:
		a.set_meta("fidget_at", 0)
		a.set_meta("busy_until", 0)
		a.set_meta("fidgeting", false)
		_rig._animate(a)
		fidgets.append(animators[0].playing())
	var kinds := {}
	for clip in fidgets:
		kinds[clip] = int(kinds.get(clip, 0)) + 1
	_check(fidgets.all(func(clip: String) -> bool: return Client3D.FIDGETS.has(clip)), "calm a while, it fidgets (%s)" % fidgets[0])
	_check(kinds.size() >= 4, "now one way, now another (%s)" % [kinds])
	_check(range(1, fidgets.size()).all(func(i: int) -> bool: return fidgets[i] != fidgets[i - 1]), "never the same twice running")
	_check(int(kinds.get(Client3D.CLIP_LOOK_ABOUT, 0)) >= kinds.values().max() - 2, "looking about the most of them, by weight (%d)" % kinds.get(Client3D.CLIP_LOOK_ABOUT, 0))
	a.set_meta("busy_until", 0)
	a.set_meta("fidgeting", false)
	a.set_meta("fidget_at", Time.get_ticks_msec() + 100000)
	imps[0].pose = Monster.Pose.SIT
	_rig._animate(a)
	_check(animators[0].playing() == Client3D.CLIP_SIT_DOWN, "set to sit, it sits down (%s)" % animators[0].playing())
	a.set_meta("busy_until", 0)
	_rig._animate(a)
	_check(animators[0].playing() == Client3D.CLIP_SITTING, "and stays sat (%s)" % animators[0].playing())
	imps[0].pose = Monster.Pose.STAND
	_rig._animate(a)
	_check(animators[0].playing() == Client3D.CLIP_SIT_UP, "and gets up when it stands (%s)" % animators[0].playing())
	a.set_meta("busy_until", 0)
	a.set_meta("fidgeting", false)
	a.set_meta("speed", 2.0)
	a.set_meta("last_at", a.position - Vector3(0.2, 0.0, 0.0))
	a.set_meta("last_ms", Time.get_ticks_msec() - 100)
	_rig._animate(a)
	_check(Client3D.is_gait(animators[0].playing()), "and goes when it moves, not looking about as it slides (%s)" % animators[0].playing())
	imps[1].hp = 2
	_rig._animate(b)
	_check(animators[1].playing() == Client3D.CLIP_TIRED, "hurt, it stands tired (%s)" % animators[1].playing())
	var heavy := big.get_meta("rig") as AnimRig
	brute.winding.emit(Vector2i(-1, 0), Monster.WINDUP_TICKS)
	# Its own strike ("blows you can see" 2ii: a monster's own, not the sword's heavy swing for every
	# wind-up), its contact as the drawn body's blow lands: the lead, and the drawn body's delay after.
	# A jab slowed only so far: it waits the rest of the wind-up before it starts (_strike's hold).
	var lands := (int(big.get_meta("contact_msec", 0)) - Time.get_ticks_msec()) / 1000.0
	var meant := Monster.WINDUP_TICKS * World.TICK_DT + Client3D.STRIKE_LANDS_IN
	await get_tree().create_timer(meant - 0.17 / AnimRig.STRIKE_SPEED_MIN + 0.05).timeout
	var wound := heavy.playing()
	var bare_strikes: Array = ((big.get_meta("moves", {}) as Dictionary).get("strikes", {}) as Dictionary).get("", [])
	_check(heavy.striking() and bare_strikes.any(func(s: Array) -> bool: return str(s[0]) == wound) and absf(lands - meant) < 0.05,
			"a brute winding up swings its own blow, timed to connect as its drawn blow lands (%s in %.2f s, %.2f meant)" % [wound, lands, meant])
	brute.swung.emit(Vector2i(-1, 0))
	_check(heavy.playing() == wound, "and the blow itself plays no other clip over it (%s)" % heavy.playing())
	brute.winding.emit(Vector2i(-1, 0), Monster.WINDUP_TICKS)
	brute.winding.emit(Vector2i(-1, 0), 0)
	_check(not heavy.striking() and int(big.get_meta("busy_until", 0)) == 0,
			"a wind-up given up (ticks 0): the swing let go (%s)" % heavy.playing())
	for each: GridEntity in [imps[0], imps[1], brute]:
		World.despawn(each)
	_rig._process(0.0)


func _test_near_miss_picks() -> void:
	print("\n== a click just off a goblin is a click on it, not on the ground behind it ==")
	var imp := _spawn_imp(Vector2i(9, 4), "imp")
	await _frames(2)
	_rig._process(0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var puppet: Node3D = _rig._puppets[imp.get_instance_id()]
	var basis := _rig._camera.global_transform.basis
	var ahead := -basis.z
	var chest := puppet.global_position + Vector3.UP * 0.6
	var off := chest - basis.x * 0.6
	var query := PhysicsRayQueryParameters3D.create(off - ahead * 30.0, off + ahead * 30.0)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := _rig.get_world_3d().direct_space_state.intersect_ray(query)
	_check(hit.is_empty() or hit["collider"].get_meta("entity", 0) != imp.get_instance_id(),
			"its own pick shape misses a ray 0.6 off its chest (it is slim)")
	_check(_rig.monster_near_ray(off - ahead * 30.0, ahead) == imp, "but that ray picks it")
	var above := puppet.global_position + Vector3.UP * (float(puppet.get_meta("pick_height")) + 0.4)
	_check(_rig.monster_near_ray(above - ahead * 30.0, ahead) == imp, "and one just over its head")
	var wide := chest - basis.x * 1.2
	_check(_rig.monster_near_ray(wide - ahead * 30.0, ahead) == null, "a ray 1.2 off it picks nothing")
	var near := _spawn_imp(Vector2i(10, 3), "imp")
	await _frames(2)
	_rig._process(0.0)
	var other: Node3D = _rig._puppets[near.get_instance_id()]
	var by_other := other.global_position + Vector3.UP * 0.6 + basis.x * 0.1
	var picked: GridEntity = _rig.monster_near_ray(by_other - ahead * 30.0, ahead)
	_check(picked == near, "two near: the nearer to the ray wins (%s)" % picked)
	World.despawn(imp)
	World.despawn(near)
	await _frames(2)


## The low-angle fight, combat's (b): a foe a nearer body hides, or one
## inside an active telegraph, wears a rim drawn through the body before
## it; never through a wall (bodies alone are asked).
func _test_seen_through() -> void:
	print("\n== a foe hidden by a nearer body, or inside a telegraph, is outlined through it ==")
	var far_imp := _spawn_imp(Vector2i(9, 4), "imp")
	var near_imp := _spawn_imp(Vector2i(10, 3), "imp")
	await _frames(2)
	_rig._process(0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var far_id := far_imp.get_instance_id()
	var far_puppet: Node3D = _rig._puppets[far_id]
	var near_puppet: Node3D = _rig._puppets[near_imp.get_instance_id()]
	var meshes := (far_puppet.get_node("Body") as Node3D).find_children("*", "MeshInstance3D", true, false)
	var rimmed := func() -> bool: return not meshes.is_empty() and meshes.all(func(mesh: MeshInstance3D) -> bool: return mesh.material_overlay == _rig._seen_through)
	_check(_rig._seen_through != null and _rig._seen_through != _rig._outline and (_rig._seen_through.shader as Shader).code.contains("depth_test_disabled")
			and not (_rig._outline.shader as Shader).code.contains("depth_test_disabled"),
			"the seen-through rim is the target's, drawn with no depth test; the target's own keeps its")
	far_imp.alert = Monster.Alert.HUNTING
	_rig._update_seen_through()
	_check(not rimmed.call() and not _rig.hidden_by_body(far_puppet, far_id), "hunting with nothing before it: no rim")
	# The nearer imp's body put on the line from the camera to the far one's chest.
	var chest := far_puppet.global_position + Vector3.UP * (float(far_puppet.get_meta("pick_height", 1.0)) * 0.6)
	var ahead: Vector3 = -_rig._camera.global_transform.basis.z
	var on_line := chest - ahead * 1.2
	var near_was := near_puppet.global_position
	_rig.set_process(false)  # (Else each frame's sync puts the puppet back on its tile.)
	near_puppet.global_position = on_line - Vector3.UP * (float(near_puppet.get_meta("pick_height", 1.0)) * 0.5)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_rig.hidden_by_body(far_puppet, far_id), "a body on the line from the camera to its chest hides it")
	_rig._update_seen_through()
	_check(rimmed.call() and far_puppet.has_meta("seen_through"), "hidden by a nearer body: outlined through it")
	_check(near_puppet.get_node("Body").find_children("*", "MeshInstance3D", true, false).all(func(mesh: MeshInstance3D) -> bool: return mesh.material_overlay == null), "the body before it: no rim")
	far_imp.alert = Monster.Alert.IDLE
	_rig._combat_at.erase(far_id)
	_rig._update_seen_through()
	_check(not rimmed.call(), "idle behind the body: no rim (its cover is the sim's to give)")
	near_puppet.global_position = near_was
	_rig.set_process(true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not _rig.hidden_by_body(far_puppet, far_id), "the body moved off the line: not hidden")
	# Inside an active telegraph: outlined whatever it is doing; gone with the telegraph.
	_rig.telegraph_show("seen", [far_imp.tile], World.tick, World.tick + 10)
	_rig._update_seen_through()
	_check(_rig.in_telegraph(far_imp.tile) and rimmed.call(), "inside an active telegraph: outlined")
	_rig.telegraph_drop("seen")
	_rig._update_seen_through()
	_check(not rimmed.call() and not far_puppet.has_meta("seen_through"), "the telegraph gone: the rim too")
	# Combat's checks: the rim follows the cells the blow will land on (the
	# sent cells, walls and their shadows already clipped out), not the
	# shape; a blow already landed, or a foe already dead, warns of nothing.
	_rig.telegraph_show("clipped", [far_imp.tile + Vector2i(1, 0), far_imp.tile + Vector2i(0, 1)], World.tick, World.tick + 10)
	_rig._update_seen_through()
	_check(not rimmed.call(), "a telegraph whose sent cells leave its cell out (clipped by a wall): no rim")
	_rig.telegraph_drop("clipped")
	_rig.telegraph_show("landing", [far_imp.tile], World.tick, World.tick + 10)
	_rig.telegraph_land("landing", true)
	_rig._update_seen_through()
	_check(not rimmed.call(), "a telegraph landed (its flash still showing): no rim")
	_rig.telegraph_drop("landing")
	var hp_was := far_imp.hp
	far_imp.hp = 0
	_rig.telegraph_show("dead", [far_imp.tile], World.tick, World.tick + 10)
	_rig._update_seen_through()
	_check(not rimmed.call(), "dead in a telegraph: no rim")
	_rig.telegraph_drop("dead")
	far_imp.hp = hp_was
	_rig._update_seen_through()
	# The marked target wears its own rim, not this one.
	_rig.telegraph_show("seen", [far_imp.tile], World.tick, World.tick + 10)
	_rig._update_seen_through()
	_rig.target(far_imp)
	_rig._update_seen_through()
	_check(meshes.all(func(mesh: MeshInstance3D) -> bool: return mesh.material_overlay == _rig._outline) and not far_puppet.has_meta("seen_through"), "marked as the target: its own rim, this one forgotten")
	_rig.target(null)
	_rig.telegraph_drop("seen")
	_rig._update_seen_through()
	World.despawn(far_imp)
	World.despawn(near_imp)
	await _frames(2)
## The closing (602 amended (4), the coordinator's rule): a telegraph's
## cells closed half a cell out and back in, so a stair reads as one shape;
## every struck cell whole, no unstruck cell's centre covered at any
## strength; a block keeps its square corners; a one-cell hole stays open;
## a wall or non-floor never bridged; two marks overlapping each closed on
## its own.
func _test_telegraph_closing() -> void:
	print("\n== a telegraph's cells closed: a stair one shape, no unstruck centre covered (602 amended (4)) ==")
	var floor_all := func(_cell: Vector2i) -> bool: return true
	var open := func(_cell: Vector2i, _way: Vector2i) -> bool: return true
	var feather := Client3D.TELEGRAPH_FEATHER
	# Every unstruck cell beside [param struck]: its centre never on a piece, its alpha 0.
	var centres_clear := func(struck: Array[Vector2i], floor_ok: Callable, passable: Callable) -> Array[String]:
		var fillets := Client3D.telegraph_fillets(struck, floor_ok, passable)
		var pieces: Array[Dictionary] = fillets.duplicate()
		pieces.append_array(Client3D.telegraph_band_polygons(struck, feather, floor_ok, passable, fillets))
		var wrong: Array[String] = []
		var seen := {}
		for each in struck:
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var near := each + Vector2i(dx, dy)
					if struck.has(near) or seen.has(near):
						continue
					seen[near] = true
					var at := Vector2(near)
					if Client3D.telegraph_band_alpha(at, struck, feather, fillets) > 0.0:
						wrong.append("%s lit" % near)
					for piece: Dictionary in pieces:
						if Geometry2D.is_point_in_polygon(at, piece["polygon"]):
							wrong.append("%s under a piece" % near)
		return wrong

	var stair: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2)]
	var fillets := Client3D.telegraph_fillets(stair, floor_all, open)
	var notches := {}
	for fillet: Dictionary in fillets:
		notches[Vector2i(fillet["cell"])] = true
	_check(notches.has(Vector2i(0, 1)) and notches.has(Vector2i(1, 2)) and notches.has(Vector2i(2, 0)) and fillets.size() == 3,
			"a stair: each notch between its steps filled in its corner (%s)" % [notches.keys()])
	var in_notch := Vector2(0.45, 0.55)  # In (0, 1), beside the inner corner the steps meet at.
	_check(is_equal_approx(Client3D.telegraph_band_alpha(in_notch, stair, feather, fillets), 1.0)
			and Client3D.telegraph_band_alpha(in_notch, stair, feather) < 1.0,
			"the notch's corner at full strength, where unclosed it faded (%.2f before)" % Client3D.telegraph_band_alpha(in_notch, stair, feather))
	var whole := true
	for cell in stair:
		for offset: Vector2 in [Vector2.ZERO, Vector2(0.49, 0.49), Vector2(-0.49, 0.49), Vector2(0.49, -0.49), Vector2(-0.49, -0.49)]:
			whole = whole and is_equal_approx(Client3D.telegraph_band_alpha(Vector2(cell) + offset, stair, feather, fillets), 1.0)
	_check(whole, "every struck cell whole at full strength")
	var clear: Array[String] = centres_clear.call(stair, floor_all, open)
	_check(clear.is_empty(), "no unstruck cell's centre covered or lit (%s)" % [clear])
	var nearest := INF
	for fillet: Dictionary in fillets:
		for point: Vector2 in fillet["polygon"]:
			nearest = minf(nearest, (point - Vector2(Vector2i(fillet["cell"]))).length())
	_check(nearest > 0.45, "a fillet's nearest point to its cell's centre %.3f of a cell (the arc's chords)" % nearest)

	var block: Array[Vector2i] = []
	for y in 2:
		for x in 3:
			block.append(Vector2i(x, y))
	var corner := Vector2(2.49, 1.49)
	var past := Client3D.telegraph_band_alpha(Vector2(2.6, 1.6), block, feather)
	_check(Client3D.telegraph_fillets(block, floor_all, open).is_empty() and is_equal_approx(Client3D.telegraph_band_alpha(corner, block, feather), 1.0)
			and past < 0.5,
			"a block of cells (a swipe's): no fill, its corners square, only the band past them (%.2f off the corner)" % past)

	var ring: Array[Vector2i] = []
	for y in [-1, 0, 1]:
		for x in [-1, 0, 1]:
			if x != 0 or y != 0:
				ring.append(Vector2i(x, y))
	var ring_fillets := Client3D.telegraph_fillets(ring, floor_all, open)
	var in_hole := 0
	for fillet: Dictionary in ring_fillets:
		if Vector2i(fillet["cell"]) == Vector2i.ZERO:
			in_hole += 1
	clear = centres_clear.call(ring, floor_all, open)
	_check(in_hole == 0 and clear.is_empty() and is_equal_approx(Client3D.telegraph_band_alpha(Vector2.ZERO, ring, feather, ring_fillets), 0.0),
			"a ring round one cell: the hole kept open, its centre bare (%d fillets in it; %s)" % [in_hole, clear])

	var walled := func(cell: Vector2i, way: Vector2i) -> bool: return not (cell == Vector2i(0, 1) and way == Vector2i(1, 0))
	var by_wall := Client3D.telegraph_fillets(stair, floor_all, walled)
	var pit := func(cell: Vector2i) -> bool: return cell != Vector2i(0, 1)
	var by_pit := Client3D.telegraph_fillets(stair, pit, open)
	var bridged := 0
	for fillet: Dictionary in by_wall + by_pit:
		if Vector2i(fillet["cell"]) == Vector2i(0, 1):
			bridged += 1
	var pit_band := 0
	for piece: Dictionary in Client3D.telegraph_band_polygons(stair, feather, pit, open, by_pit):
		if Vector2i(piece["cell"]) == Vector2i(0, 1):
			pit_band += 1
	clear = centres_clear.call(stair, floor_all, walled)
	_check(bridged == 0 and pit_band == 0 and by_wall.size() == 2 and by_pit.size() == 2 and clear.is_empty(),
			"a wall on the notch's edge, or the notch not floor: no fill there, no band on non-floor, the other notches as before (%d, %d)" % [bridged, pit_band])

	# Two marks overlapping, each its own mesh: each covers its own cells whole, and none of
	# its triangles covers an unstruck cell's centre of its own (the other's cells aside).
	var shape := {"kind": "cone", "origin": [9, 4], "facing": [1, 0], "length": 2, "half_angle": 60}
	if Client3D.telegraph_outline(shape).is_empty():
		print("  (no Telegraph.outline here: the overlap checks skipped)")
		return
	var marks := {"close_a": [Vector2i(8, 3), Vector2i(9, 3), Vector2i(9, 4)], "close_b": [Vector2i(9, 4), Vector2i(10, 4), Vector2i(10, 5)]}
	for id: String in marks:
		_rig.telegraph_show(id, marks[id], World.tick, World.tick + 10, shape)
	var faults: Array[String] = []
	for id: String in marks:
		var own: Array[Vector2i] = []
		own.assign(marks[id])
		var entry: Dictionary = _rig._telegraphs[id]
		var arrays := ((entry["quads"][0] as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var covers := func(at: Vector2) -> float:
			var most := 0.0
			for i in range(0, points.size(), 3):
				var triangle := PackedVector2Array([Vector2(points[i].x, points[i].z), Vector2(points[i + 1].x, points[i + 1].z), Vector2(points[i + 2].x, points[i + 2].z)])
				if Geometry2D.is_point_in_polygon(at, triangle):
					most = maxf(most, maxf(colours[i].a, maxf(colours[i + 1].a, colours[i + 2].a)))
			return most
		for cell in own:
			if covers.call(Vector2(cell) + Vector2(0.01, 0.02)) < 0.999:  # Off the squares' diagonals.
				faults.append("%s: its cell %s not whole" % [id, cell])
		for cell in own:
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var near := cell + Vector2i(dx, dy)
					if not own.has(near) and covers.call(Vector2(near)) > 0.0:
						faults.append("%s: covers %s" % [id, near])
	_check(_rig._telegraphs.has("close_a") and _rig._telegraphs.has("close_b") and faults.is_empty(),
			"two marks overlapping: each closed on its own, its cells whole, no centre of its own unstruck cells covered (%s)" % [faults])
	for id: String in marks:
		_rig.telegraph_drop(id)


## The low-angle fight, combat's (a): a telegraph with a shape is drawn as
## combat's outline cut to the sent cells, with a curtain along its edge
## drawn through bodies; one without a shape as the cells, as before.
func _test_telegraph_smooth() -> void:
	print("\n== a telegraph drawn smooth: the outline's fill cut to the sent cells, flat on the ground ==")
	var shape := {"kind": "cone", "origin": [9, 4], "facing": [1, 0], "length": 2, "half_angle": 60}
	var outline := Client3D.telegraph_outline(shape)
	var all_cells: Array = Main.telegraph_cells(shape)
	if outline.is_empty() or all_cells.size() < 2:
		print("  (no Telegraph.outline here: the smooth telegraph checks skipped)")
		return
	_check(outline.size() > 10 and outline[outline.size() - 1] == Vector2.ZERO, "combat's outline for a cone: an arc then the origin (%d points)" % outline.size())
	var left_out: Variant = all_cells[all_cells.size() - 1]  # (As a wall's clip would leave one out.)
	var cells: Array = all_cells.slice(0, all_cells.size() - 1)
	_rig.telegraph_show("smooth", cells, World.tick, World.tick + 10, shape)
	var entry: Dictionary = _rig._telegraphs["smooth"]
	var fill: MeshInstance3D = entry["quads"][0]
	_check(entry["quads"].size() == 1 and entry["curtain"] == null, "one fill mesh on the ground, no curtain standing on its edge (602 amended (2): Jeff's \"3d block\")")
	var struck: Array[Vector2i] = []
	for cell in cells:
		struck.append(Vector2i(cell))
	# 602 amended (3) (the coordinator's: a warning never understates): every point of the sent
	# cells at the fill's full alpha, a band fading outside them to none at TELEGRAPH_FEATHER.
	var arrays := (fill.mesh as ArrayMesh).surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var feather := Client3D.TELEGRAPH_FEATHER
	# 602 amended (4): the closed mark, its fillets as the mesh has them.
	var fillets := Client3D.telegraph_fillets(struck,
			func(cell: Vector2i) -> bool: return World.is_walkable(cell),
			func(cell: Vector2i, way: Vector2i) -> bool: return not World.edge_blocks(cell, way))
	var inner_dim := 0
	var too_far := 0
	var band := 0
	var rim_lit := 0
	for i in points.size():
		var at := Vector2(points[i].x, points[i].z)
		var nearest := Client3D.telegraph_closed_distance(at, struck, fillets)
		if nearest <= 0.001 and colours[i].a < 0.999:
			inner_dim += 1
		if nearest > feather + 0.01:
			too_far += 1
		if nearest > 0.001:
			band += 1
		if nearest >= feather - 0.01 and colours[i].a > 0.01:
			rim_lit += 1
	_check(points.size() >= 3 and colours.size() == points.size() and inner_dim == 0,
			"every point of the sent cells drawn at the fill's full alpha: none understated (%d vertices, %d dim)" % [points.size(), inner_dim])
	_check(band > 0 and too_far == 0 and rim_lit == 0,
			"a soft band outside them, %.1f of a cell, fading to none at its edge (%d band vertices, %d too far, %d lit at the rim)" % [feather, band, too_far, rim_lit])
	var walled := Vector2i(struck[0]) + Vector2i(0, -1)
	while struck.has(walled):
		walled += Vector2i(0, -1)
	var floor_ok := func(cell: Vector2i) -> bool: return cell != walled
	var open := func(_cell: Vector2i, _way: Vector2i) -> bool: return true
	var over_wall := 0
	for piece: Dictionary in Client3D.telegraph_band_polygons(struck, feather, floor_ok, open):
		if Vector2i(piece["cell"]) == walled:
			over_wall += 1
	# Just past the struck cell's edge, mid-side: only the band straight across that edge reaches
	# it (a side neighbour's or a corner's is 0.5 away), so a wall on that edge leaves it bare.
	var probe := Vector2(walled) + Vector2(0.0, 0.5 - feather * 0.5)
	var floor_all := func(_cell: Vector2i) -> bool: return true
	var covered := func(passable: Callable) -> bool:
		for piece: Dictionary in Client3D.telegraph_band_polygons(struck, feather, floor_all, passable):
			if Vector2i(piece["cell"]) == walled and Geometry2D.is_point_in_polygon(probe, piece["polygon"]):
				return true
		return false
	var shut := func(cell: Vector2i, way: Vector2i) -> bool: return not (cell == walled and way == Vector2i(0, 1))
	var open_covers: bool = covered.call(open)
	var shut_covers: bool = covered.call(shut)
	_check(over_wall == 0 and open_covers and not shut_covers,
			"nothing drawn beyond a wall: none on a wall's cell (%d); past an open edge the band (%s), past a walled one none (%s)" % [over_wall, open_covers, shut_covers])
	var fill_material := fill.material_override as StandardMaterial3D
	_rig.telegraph_tick(World.tick)
	var faint := fill_material.albedo_color.a
	_rig.telegraph_tick(World.tick + 8)
	var later := fill_material.albedo_color.a
	_check(fill.visible and fill_material.albedo_color.r > 0.5 and later > faint,
			"the red fill stays and brightens as the blow comes: the tell kept (%.2f to %.2f)" % [faint, later])
	# 602 amended (3), ui-design's: the theme's danger_ground, strong out of doors (read over
	# grass), lower indoors (no slab over the floor).
	var ground := UiTheme.color("danger_ground")
	_check(ground != Color.MAGENTA and Color(fill_material.albedo_color, 1.0).is_equal_approx(Color(ground, 1.0)),
			"the fill in the theme's danger_ground (%s)" % fill_material.albedo_color.to_html(false))
	var was_outdoor: bool = _rig._outdoor
	var was_light := DayNight.light
	for setting: Array in [[true, 1.0, Client3D.TELEGRAPH_DAY, "out of doors by day"],
			[true, DayNight.NIGHT, Client3D.TELEGRAPH_NIGHT, "out of doors at night"],
			[false, 1.0, Client3D.TELEGRAPH_INDOORS, "indoors"]]:
		_rig._outdoor = setting[0]
		DayNight.light = setting[1]
		var pair: Vector2 = setting[2]
		_rig.telegraph_tick(World.tick)
		var at_start := fill_material.albedo_color.a
		_rig.telegraph_tick(World.tick + 10)
		var at_lands := fill_material.albedo_color.a
		_check(is_equal_approx(at_start, pair.x) and is_equal_approx(at_lands, pair.y),
				"%s: faint %.2f as it begins, full %.2f as it lands (%.2f, %.2f)" % [setting[3], pair.x, pair.y, at_start, at_lands])
	_rig._outdoor = was_outdoor
	DayNight.light = was_light
	var dusk := Client3D.telegraph_strengths(true, lerpf(DayNight.NIGHT, 1.0, 0.5))
	var day := Client3D.telegraph_strengths(true, 1.0)
	var night := Client3D.telegraph_strengths(true, DayNight.NIGHT)
	var indoors := Client3D.telegraph_strengths(false, DayNight.NIGHT)
	_check(dusk.is_equal_approx((day + night) * 0.5) and day.y < 1.0 and night.x > 0.0,
			"at dusk halfway from night's to day's, never opaque (%s)" % dusk)
	_check(night.y < indoors.y,
			"at night out of doors the full mark under a hall's, so a night fight never blares more than a hall (%.2f < %.2f)" % [night.y, indoors.y])
	_rig.telegraph_drop("smooth")
	_check(not _rig._telegraphs.has("smooth"), "dropped: gone")
	_rig.telegraph_show("plain", cells, World.tick, World.tick + 10)
	_check(_rig._telegraphs["plain"]["quads"].size() == cells.size() and _rig._telegraphs["plain"]["curtain"] == null, "a message without a shape: a quad a cell, no curtain, as before")
	_rig.telegraph_drop("plain")

## The spin's whole disc (603 amended (7): half_angle 180): its rim stands
## whole on open ground, every outer segment kept (two broke where the rim,
## at length + REACH_SLACK, ran past the squares between struck cells); with
## a cell left out as a wall leaves it, no rim segment stands over that cell.
func _test_telegraph_disc_rim() -> void:
	var shape := {"kind": "cone", "origin": [0, 0], "facing": [1, 0], "length": 3, "half_angle": 180}
	var outline := Client3D.telegraph_outline(shape)
	var struck := Telegraph.cells(shape)
	struck.append(Vector2i.ZERO)
	var rim := 0.0
	for point in outline:
		rim = maxf(rim, point.length())
	var on_rim := 0
	for i in outline.size():
		if absf(outline[i].length() - rim) < 0.01 and absf(outline[(i + 1) % outline.size()].length() - rim) < 0.01:
			on_rim += 1
	var kept := Client3D.telegraph_curtain_segments(outline, Vector2.ZERO, struck)
	var kept_rim := 0
	for segment in kept:
		if absf(segment[0].length() - rim) < 0.01 and absf(segment[1].length() - rim) < 0.01:
			kept_rim += 1
	_check(on_rim > 8 and kept_rim == on_rim, "a disc's rim stands whole on open ground (%d of %d rim segments)" % [kept_rim, on_rim])
	var walled := Vector2i(3, 0)
	struck.erase(walled)
	var over_wall := 0
	for segment in Client3D.telegraph_curtain_segments(outline, Vector2.ZERO, struck):
		var middle: Vector2 = (segment[0] + segment[1]) * 0.5
		if absf(middle.x - walled.x) < 0.5 and absf(middle.y - walled.y) < 0.5:
			over_wall += 1
	_check(over_wall == 0, "a cell a wall leaves out cuts the rim there (%d pieces over it)" % over_wall)


## Combat's check on the smooth telegraph's fill (602 amended's rule): a
## body is struck exactly when its cell's centre is inside what is drawn.
## Over the draugr's spin, throw and charge at several aims, with cells clipped
## out as a wall would leave them, every sent cell's centre is under the fill
## and no other centre is (one within a hundredth of a cell of an edge let be).
func _test_telegraph_fill_honest() -> void:
	print("
== the smooth telegraph's fill: under it exactly the cells the blow lands on ==")
	var shapes: Array[Dictionary] = []
	for turn in 16:
		var facing := Vector2.from_angle(turn * TAU / 16.0 + 0.07)
		shapes.append(Telegraph.cone(Vector2i(20, 20), facing, 2.0, 150.0))
		shapes.append(Telegraph.line(Vector2i(20, 20), facing, 8.0))
		shapes.append(Telegraph.line(Vector2i(20, 20), facing, 12.0))
	var wrong := []
	var pieces := 0
	for shape in shapes:
		var origin := Vector2(Telegraph.origin_of(shape))
		var outline := Client3D.telegraph_outline(shape)
		for clip in [false, true]:
			var struck: Array[Vector2i] = []
			for cell in Telegraph.cells(shape):
				if not clip or cell.x < 22:  # As a wall at x = 22 would cut it.
					struck.append(cell)
			var fill := Client3D.telegraph_fill_polygons(outline, origin, struck)
			pieces += fill.size()
			var reach := ceili(float(shape["length"])) + 2
			for y in range(20 - reach, 21 + reach):
				for x in range(20 - reach, 21 + reach):
					var centre := Vector2(x, y)
					var near := false
					var under := false
					for piece in fill:
						near = near or _near_edge(piece, centre, 0.01)
						under = under or _crossed(piece, centre)
					if not near and under != struck.has(Vector2i(x, y)) and wrong.size() < 4:
						wrong.append([shape["kind"], shape["facing"], clip, Vector2i(x, y), under])
	_check(wrong.is_empty() and pieces > 0,
			"%d shapes, whole and clipped: under the fill exactly the sent cells' centres (%d pieces) %s" % [shapes.size(), pieces, wrong])


## Whether [param point] is inside [param polygon] by the even-odd rule.
func _crossed(polygon: PackedVector2Array, point: Vector2) -> bool:
	var inside := false
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		if (a.y > point.y) != (b.y > point.y) and point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x:
			inside = not inside
	return inside


## Whether [param point] lies within [param slack] of [param polygon]'s edge.
func _near_edge(polygon: PackedVector2Array, point: Vector2, slack: float) -> bool:
	for i in polygon.size():
		if Geometry2D.get_closest_point_to_segment(point, polygon[i], polygon[(i + 1) % polygon.size()]).distance_to(point) < slack:
			return true
	return false



func _test_target_marked() -> void:
	print("\n== the monster a click would attack is outlined, its own look untouched; not after it dies ==")
	var player := _player()
	var imp := _spawn_imp(Vector2i(9, 4), "imp")
	var other := _spawn_imp(Vector2i(10, 3), "imp")
	await _frames(2)
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets[imp.get_instance_id()]
	var beside: Node3D = _rig._puppets[other.get_instance_id()]
	var meshes := _body_meshes(puppet)
	var own: Array[Material] = []
	for mesh in meshes:
		own.append(mesh.get_active_material(0))
	_check(not meshes.is_empty() and _outlined(puppet) == 0, "none outlined at first")
	_rig.target(imp)
	_check(_outlined(puppet) == meshes.size(), "every mesh of its body is outlined (%d of %d)" % [_outlined(puppet), meshes.size()])
	var passes := 0
	var pass_: Material = meshes[0].material_overlay
	while pass_ != null:
		passes += 1
		pass_ = pass_.next_pass
	_check(passes == 8, "by its silhouette nudged each of the eight ways (%d passes)" % passes)
	var same := true
	for n in meshes.size():
		if own[n] is ShaderMaterial:
			# A goblin's (decision 494): its shader's twin that marks the stencil, its paint the same.
			var shaded := meshes[n].get_active_material(0) as ShaderMaterial
			same = same and shaded != null and shaded.shader == Client3D.GOBLIN_MARKING_SHADER \
					and shaded.get_shader_parameter("paint") == (own[n] as ShaderMaterial).get_shader_parameter("paint")
			continue
		var drawn := meshes[n].get_active_material(0) as BaseMaterial3D
		var was := own[n] as BaseMaterial3D
		same = same and drawn != null and was != null and drawn.stencil_mode == BaseMaterial3D.STENCIL_MODE_CUSTOM \
				and drawn.stencil_reference == Client3D.OUTLINE_STENCIL and drawn.albedo_texture == was.albedo_texture \
				and drawn.albedo_color == was.albedo_color and drawn.roughness_texture == was.roughness_texture
	_check(same, "its body marks the stencil, with its own colours and textures")
	# A human's body (a robber's): its shader's twin marks the stencil too,
	# or the rim's passes drew over the whole body (Jeff on v0.1.187: "their
	# whole model to go white translucent").
	var human := _rig._marking_copy(Client3D.HUMAN_MATERIAL) as ShaderMaterial
	_check(human != null and human.shader != Client3D.HUMAN_MATERIAL.shader and "stencil_mode write" in human.shader.code
			and human.get_shader_parameter("palette") == Client3D.HUMAN_MATERIAL.get_shader_parameter("palette"),
			"a human body's copy marks the stencil, its palette the same")
	_check(_outlined(beside) == 0, "the one beside it is not outlined")
	_rig.target(other)
	_check(_outlined(puppet) == 0 and meshes[0].get_active_material(0) == own[0] and _outlined(beside) > 0,
			"another outlined: the first is as it was")
	_rig.target(null)
	_check(_outlined(beside) == 0, "none: nothing outlined")
	_rig.target(imp)
	World.damage(imp, 999, player, &"attack")
	_rig._process(0.0)
	_check(_outlined(puppet) == 0 and meshes[0].get_active_material(0) == own[0], "killed while outlined: gone at once")
	_rig.target(null)
	World.despawn(other)
	await _frames(2)


## The meshes of [param puppet]'s body.
func _body_meshes(puppet: Node3D) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for mesh in puppet.get_node("Body").find_children("*", "MeshInstance3D", true, false):
		meshes.append(mesh)
	return meshes


## How many of [param puppet]'s body meshes have the outline over them.
func _outlined(puppet: Node3D) -> int:
	return _body_meshes(puppet).filter(func(mesh: MeshInstance3D) -> bool: return mesh.material_overlay != null).size()


func _place(entity: GridEntity, tile: Vector2i) -> void:
	World._relocate(entity, tile)
	if entity is Player:
		# A free body (703): its view starts again where it is put, no route left.
		entity.free_view = null
		_main._free["path"] = []


func _test_humans() -> void:
	print("
== players and companions are the human bodies (decisions 243, 388): upright, toes forward, on the ground ==")
	var player := _player()
	_rig._process(0.0)
	for body: StringName in [&"male", &"female"]:
		player.body = body
		_rig._process(0.0)
		var puppet: Node3D = _rig._puppets[player.get_instance_id()]
		var model := puppet.get_node_or_null("Body/Model")
		var scene := str(Client3D.HUMAN_F["scene"] if body == &"female" else Client3D.HUMAN["scene"])
		_check(model != null and model.scene_file_path == scene and puppet.has_meta("rig"),
				"%s: its puppet is %s, animated" % [body, scene.get_file()])
		if model == null or not puppet.has_meta("rig"):
			continue
		var animator := puppet.get_meta("rig") as AnimRig
		# Standing, now and then fidgeting (decision 171: the first fidget comes at a moment of
		# this run's, as early as 2 s in).
		_check(animator.playing() == Client3D.CLIP_IDLE or Client3D.HUMAN_FIDGETS.has(animator.playing()),
				"standing: Idle, or a fidget (%s)" % animator.playing())
		var skeleton := puppet.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var y := func(bone: String) -> float:
			return (skeleton.global_transform * skeleton.get_bone_global_rest(skeleton.find_bone(bone)).origin).y
		_check(y.call("Head") > y.call("Hips") and y.call("Hips") > y.call("LeftFoot"), "upright: head over hips over feet")
		var low := INF
		var high := -INF
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			if not mesh.visible:
				continue
			var box := mesh.global_transform * mesh.get_aabb()
			low = minf(low, box.position.y)
			high = maxf(high, box.end.y)
		var tall := float(Client3D.HUMAN_F["height"] if body == &"female" else Client3D.HUMAN["height"]) * float(puppet.get_meta("model_scale"))
		_check(absf(low - puppet.global_position.y) < 0.05 and absf(high - low - tall) < 0.12,
				"its feet on the ground (%.3f), %.2f m tall" % [low - puppet.global_position.y, high - low])
		var wanted := Vector2(player.facing).normalized()
		_check(_toes_ahead(puppet).dot(wanted) > 0.9, "its toes point where it faces (%s)" % _toes_ahead(puppet))
		# The body and its parts: the skinned meshes (not what its sockets hold).
		var meshes := model.find_children("*", "MeshInstance3D", true, false).filter(func(m: MeshInstance3D) -> bool:
			return m.get_parent() is Skeleton3D)
		var mesh := model.find_child("Body", true, false) as MeshInstance3D
		var look := puppet.get_meta("look") as PersonLook
		var shown: Array = meshes.filter(func(m: MeshInstance3D) -> bool: return m.visible and m != mesh).map(func(m: MeshInstance3D) -> String: return String(m.name))
		_check(mesh != null and mesh.mesh.get_surface_count() == 1
				and meshes.all(func(m: MeshInstance3D) -> bool: return m.get_active_material(0) == Client3D.HUMAN_MATERIAL),
				"a body of one surface and its parts, all in the bodies' one shared material")
		if mesh == null:
			continue
		shown.sort()
		var worn := look.parts.duplicate()
		worn.sort()
		_check(shown == worn and not ("Hood" in worn or "Hat_Brimmed" in worn or "Apron" in worn),
				"wearing its look's parts (%s), no headwear or apron for a player" % [shown])
		_check(mesh.get_instance_shader_parameter("skin") == look.colours["skin"] and absf(float(puppet.get_meta("model_scale")) - look.scale) < 1e-4,
				"its look's skin and stature (%.3f)" % look.scale)
		var tint: Color = puppet.get_meta("tint")
		_check(tint == Color.WHITE or mesh.get_instance_shader_parameter("tunic") == tint, "the tunic in the player's colour")
	player.body = &"male"
	_rig._process(0.0)
	var library := load(str(Client3D.HUMAN["clips"])) as AnimationLibrary
	var moves: Dictionary = Client3D.HUMAN["moves"]
	var missing: Array[String] = []
	for item: String in moves["strikes"]:
		for strike: Array in moves["strikes"][item]:
			var clip := library.get_animation(strike[0]) if library.has_animation(strike[0]) else null
			if clip == null or float(strike[1]) <= 0.0 or float(strike[1]) >= clip.length:
				missing.append("%s (%s)" % [strike[0], item])
	for key: String in ["block", "knockdown", "lying", "get_up", "bow_aim", "bow_shoot", "bow_idle", "stance"]:
		if not library.has_animation(moves[key]):
			missing.append(moves[key])
	var listed: Array = moves["dodges"] + moves["deaths"]
	for gait: Array in Client3D.HUMAN_GAITS + Client3D.HUMAN_F_GAITS:
		listed.append(gait[0])
	for side: String in ["front", "left", "right", "back"]:
		listed += moves["hits"][side]
	for clip: String in listed:
		if not library.has_animation(clip):
			missing.append(clip)
	_check(missing.is_empty(), "every move's clip is in the library, each strike's contact within it (%s)" % [missing])
	_check(library.get_animation(moves["block"]).loop_mode != Animation.LOOP_NONE
			and library.get_animation(moves["lying"]).loop_mode != Animation.LOOP_NONE, "the guard and lying loop")
	var pet := _companion()
	if pet != null:
		var wanted := CompanionCard.body_of(pet.traits, pet.keeper_id)
		var model: Node = _rig._puppets[pet.get_instance_id()].get_node_or_null("Body/Model")
		_check(pet.body == wanted and model != null
				and model.scene_file_path == str((Client3D.HUMAN if wanted == &"male" else Client3D.HUMAN_F)["scene"]),
				"%s wears her card's body, %s" % [pet.name, wanted])


func _test_person_garb() -> void:
	print("
== a person's face and garb (decision 480): faces seeded, a trade dresses them, said words win; a player's own ==")
	var guard := PersonLook.make("seed=11 body=male headwear=none trade=guard")
	var merchant := PersonLook.make("seed=11 body=male headwear=none trade=merchant")
	var hauler := PersonLook.make("seed=12 body=male trade=hauler")
	_check("Vest" in guard.parts and "Coat" in merchant.parts and "Sleeves_Rolled" in hauler.parts and "Cap_Soft" in hauler.parts,
			"a guard in a vest, a merchant in a coat, a hauler's sleeves rolled and a cap (%s, %s, %s)" % [guard.parts, merchant.parts, hauler.parts])
	_check(not "Cap_Soft" in PersonLook.make("seed=12 body=male trade=hauler headwear=hat").parts
			and "Hat_Brimmed" in PersonLook.make("seed=12 body=male trade=hauler headwear=hat").parts
			and "Coat" in PersonLook.make("seed=11 trade=guard garb=coat").parts,
			"the look's own words win over the trade's (headwear, garb)")
	var unknown := PersonLook.make("seed=11 body=male headwear=none trade=juggler")
	_check(PersonLook.GARB_PARTS.values().all(func(part: String) -> bool: return part == "" or not part in unknown.parts),
			"an unknown trade: plain clothes (%s)" % [unknown.parts])
	var faces := []
	for seed in 20:
		var look := PersonLook.make("seed=%d" % seed)
		faces.append(look)
	_check(faces.all(func(look: PersonLook) -> bool: return PersonLook.FACE_KEYS.all(func(key: String) -> bool:
			return look.keys.has(key) and float(look.keys[key]) >= 0.0 and float(look.keys[key]) <= 1.0)),
			"every face its own planes, each 0..1")
	_check(faces.filter(func(look: PersonLook) -> bool: return look.body == &"female").all(func(look: PersonLook) -> bool:
			return float(look.keys["jaw"]) <= 0.35 and float(look.keys["brow"]) <= 0.4),
			"a woman's jaw and brow kept lighter")
	var garbed := faces.filter(func(look: PersonLook) -> bool: return look.garb != "none").size()
	_check(garbed > 0 and garbed < 20, "with no trade, some wear garb by their seed, most not (%d of 20)" % garbed)
	var before := PersonLook.make("seed=48213 body=female build=heavy hair=long")
	_check(before.parts.has("Hair_Long") and before.skin == PersonLook.make("seed=48213 body=female build=heavy hair=long trade=guard").skin,
			"a trade changes the clothes, not the person (the same skin, the same hair)")
	var orc := PersonLook.make("seed=5 people=orc trade=guard")
	_check(PersonLook.FACE_KEYS.all(func(key: String) -> bool: return not orc.keys.has(key)) and not "Vest" in orc.parts,
			"an orc keeps its own look: no human face planes, no garb (%s)" % [orc.parts])
	var player := Player.new()
	player.name = "GarbPlayer"
	player.spawn_spec = {"look": "seed=3 trade=merchant"}
	var mine := Client3D.look_for(player)
	_check(mine.garb == "none" and not "Coat" in mine.parts, "a player wears no garb: theirs is what they chose (%s)" % [mine.parts])
	player.free()


func _test_person_looks() -> void:
	print("
== a person's look (decision 419): the same words the same person; words over the seed; parts, keys, posture ==")
	var full := "seed=48213 body=female build=heavy stature=tall age=old posture=stooped hair=long hair_colour=grey beard=none headwear=hood apron=yes skin=8 shoulders=broad"
	var a := PersonLook.make(full)
	var b := PersonLook.make(full)
	_check(a.keys == b.keys and a.parts == b.parts and a.scale == b.scale and a.colours == b.colours,
			"the same look twice is the same person")
	_check(a.body == &"female" and a.keys.get("heavy", 0.0) > 0.4 and a.keys.get("old", 0.0) > 0.5 and a.keys.get("broad", 0.0) >= 0.3
			and a.scale > 1.03 and a.posture == "stooped" and a.colours["hair"] == Color(PersonLook.HAIR_COLOURS["grey"])
			and a.colours["skin"] == Color(PersonLook.SKINS[7]),
			"its words: heavy, old, broad, tall, stooped, grey, the darkest skin (%s, %.3f)" % [a.keys, a.scale])
	_check(a.parts == ["Hood", "Apron"], "a hood over the hair (not drawn under it), an apron (%s)" % [a.parts])
	var seeded := PersonLook.make("seed=7")
	var odd := PersonLook.make("seed=7 build=enormous colour_of_eyes=blue")
	_check(seeded.keys == odd.keys and seeded.parts == odd.parts and seeded.scale == odd.scale,
			"a word it does not know, or a value, is passed over: the seed decides")
	var men := 0
	for i in 40:
		if PersonLook.make("seed=%d" % i).body == &"male":
			men += 1
	_check(men > 10 and men < 30, "no body named and none given: the seed picks (%d men of 40)" % men)
	_check(PersonLook.make("seed=7", &"female").body == &"female", "else the body given (the pronoun's)")
	# A resident is a person, drawn as its spec's look.
	var resident := Resident.new()
	resident.name = "LookTestResident"
	resident.spawn_spec = {"look": full}
	_check(Client3D.model_for(resident) == Client3D.HUMAN_F and Client3D.look_for(resident).parts == ["Hood", "Apron"],
			"a resident is the human body its look says")
	resident.free()
	# Every part body_gen makes is in both bodies, keyed as the body is.
	for scene_path: String in [Client3D.HUMAN["scene"], Client3D.HUMAN_F["scene"]]:
		var scene := (load(scene_path) as PackedScene).instantiate() as Node3D
		var names: Array = scene.find_children("*", "MeshInstance3D", true, false).map(func(m: MeshInstance3D) -> String: return String(m.name))
		var wanted: Array = ["Body"] + PersonLook.HAIR_PARTS.values() + PersonLook.BEARD_PARTS.values() + PersonLook.HEADWEAR_PARTS.values() + ["Apron"]
		var missing := wanted.filter(func(n: String) -> bool: return n != "" and not n in names)
		var unkeyed := scene.find_children("*", "MeshInstance3D", true, false).filter(func(m: MeshInstance3D) -> bool:
			return (m.mesh as ArrayMesh).get_blend_shape_count() < 7)
		_check(missing.is_empty() and unkeyed.is_empty(), "%s: every part (%s missing), each with the seven keys" % [scene_path.get_file(), missing])
		scene.free()
	var library := load(str(Client3D.HUMAN["clips"])) as AnimationLibrary
	_check(Client3D.POSTURES.values().all(func(clip: String) -> bool: return library.has_animation(clip)), "the postures are in the clips")


## 560, pc-character's side: a person standing turns slowly, shuffling; a resident addressing
## someone looks at them and talks.
func _test_standing_turn() -> void:
	print("
== a standing turn and a resident's look (560): turned over a moment, the head toward whom it addresses ==")
	var player := _player()
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets[player.get_instance_id()]
	var rig := puppet.get_meta("rig") as AnimRig
	puppet.remove_meta("turned_ms")
	puppet.set_meta("speed", 0.0)
	_check(is_equal_approx(_rig._standing_turn(puppet, 0.0, PI * 0.9), PI * 0.9), "first drawn: facing as it is")
	puppet.set_meta("turned_ms", Time.get_ticks_msec() - 50)
	var turned := _rig._standing_turn(puppet, 0.0, PI * 0.9)
	_check(turned > 0.1 and turned < 0.6 and int(puppet.get_meta("shuffle_until", 0)) > Time.get_ticks_msec(),
			"standing, a half turn not at once: %.2f of %.2f rad after 50 ms, its feet shuffling" % [turned, PI * 0.9])
	_rig._animate(puppet)
	_check(rig.base_clip() == Client3D.CLIP_WALK, "the shuffle: the walk while it turns (%s)" % rig.base_clip())
	puppet.set_meta("shuffle_until", 0)
	puppet.set_meta("turning", false)
	puppet.set_meta("speed", 2.0)
	_check(is_equal_approx(_rig._standing_turn(puppet, 0.0, PI * 0.9), PI * 0.9), "moving: it follows its facing")
	puppet.set_meta("speed", 0.0)
	var resident := Resident.new()
	resident.name = "AddressTestResident"
	add_child(resident)
	resident.addressing = String(player.get_path())
	_rig._sync_addressing(resident, puppet)
	var look := puppet.get_node_or_null("Look") as Node3D
	var turn := look.get_meta("turn") as LookAtModifier3D if look != null else null
	if look != null:
		look.set_meta("eased_ms", Time.get_ticks_msec() - 1000)
	_rig._sync_addressing(resident, puppet)
	_rig._animate(puppet)
	_check(turn != null and turn.bone_name == "Head" and is_equal_approx(turn.influence, 1.0) and turn.get_node_or_null(turn.target_node) == look,
			"addressing: the head turned toward them (a LookAtModifier3D on Head, influence %.2f)" % [turn.influence if turn != null else -1.0])
	_check(rig.base_clip() == Client3D.CLIP_TALKING or not rig.has(Client3D.CLIP_TALKING), "and talking (%s)" % rig.base_clip())
	resident.addressing = ""
	if look != null:
		look.set_meta("eased_ms", Time.get_ticks_msec() - 1000)
	_rig._sync_addressing(resident, puppet)
	_check(turn != null and is_zero_approx(turn.influence) and str(puppet.get_meta("addressing", "")) == "",
			"addressing no one: the head its own again")
	resident.free()
	if turn != null:
		turn.free()
	if look != null:
		look.free()
	_rig._animate(puppet)


## The head socket (the bard's hat): on a person's Head bone at the top of the skull, level, +x
## its front; a hat word with no piece in this build (or none known) wears nothing new and leaves
## the look's own headwear as it was.
func _test_head_socket() -> void:
	print("
== the head socket: at the crown; a hat by its look word ==")
	var player := _player()
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets[player.get_instance_id()]
	var sockets: Dictionary = puppet.get_meta("sockets")
	var head := sockets.get("head") as Node3D
	var on := head.get_parent() as BoneAttachment3D if head != null else null
	var model := puppet.get_node("Body/Model") as Node3D
	var above := (head.global_position.y - on.global_position.y) / float(puppet.get_meta("model_scale", 1.0)) if head != null else 0.0
	_check(head != null and on.bone_name == "Head" and absf(above - 0.228) < 0.03,
			"a person has a head socket on the Head bone at the top of the skull (%.3f m above the bone)" % above)
	var plain := Node3D.new()
	var look := PersonLook.make("hat=no_such_hat")
	var shown := {}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		shown[mesh.name] = mesh.visible
	puppet.set_meta("look", look)
	Client3D._wear_hat(model, puppet)
	var after := {}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		after[mesh.name] = mesh.visible
	_check(head.get_node_or_null("Hat") == null and after == shown, "a hat word it doesn't know: nothing new worn, the look's own headwear as it was")
	_check(Client3D.HATS.has("bard"), "the bard's hat by its word")
	plain.free()


## 566, pc-character's side: a resident's activity word as its body shows it.
func _test_visible_work() -> void:
	print("\n== visible work (566): the work's clip, its tool in hand, a log on the shoulder, lying to sleep ==")
	var player := _player()
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets[player.get_instance_id()]
	var rig := puppet.get_meta("rig") as AnimRig
	var sockets: Dictionary = puppet.get_meta("sockets")
	_check(sockets.has("shoulder") and (sockets["shoulder"].get_parent() as BoneAttachment3D).bone_name == "UpperChest",
			"a person has a shoulder socket on the upper chest")
	var resident := Resident.new()
	resident.name = "WorkTestResident"
	add_child(resident)
	puppet.set_meta("speed", 0.0)
	puppet.set_meta("shuffle_until", 0)
	var held: Array = puppet.get_meta("held")
	var show := func(word: String) -> void:
		resident.activity = word
		_rig._sync_held(resident, puppet)
		_rig._sync_work(resident, puppet)
		_rig._animate(puppet)
	var tools := {}
	for word: String in ["chop", "saw", "hammer"]:
		show.call(word)
		var thing := (sockets["hand_r"] as Node3D).get_node_or_null("Held")
		tools[word] = [rig.base_clip(), held[0], thing != null]
	_check(tools["chop"] == ["Chop", "art:tool.axe", true] and tools["saw"] == ["Saw", "art:tool.saw", true]
			and tools["hammer"] == ["Hammer", "art:tool.hammer", true],
			"at work: chopping, sawing, hammering, each its tool in the right hand (%s)" % tools)
	show.call("carry_log")
	var log_piece := (sockets["shoulder"] as Node3D).get_node_or_null("Load")
	_check(log_piece != null and rig.upper_clip() == "Carry_Shoulder" and held[0] == "",
			"carrying a log: on the shoulder, the hand up to it (%s), the axe put away" % rig.upper_clip())
	# Townsfolk at work (566 amended, pc-character's side): each word its clip (or upper-layer clip
	# over the stand and walk) and its pieces, the right hand's, the left's (a hunter's bow), the
	# shoulder's.
	var works := {}
	for word: String in ["stalk", "carry_game", "carry_sack", "hoe", "herd", "shear"]:
		show.call(word)
		works[word] = [rig.base_clip() if not Client3D.ACTIVITIES[word].has("upper") else rig.upper_clip(), held[0], held[1]]
	_check(works == {"stalk": ["Crouch_Idle", "", "art:item.bow"], "carry_game": ["Carry_Game", "", ""],
			"carry_sack": ["Carry_Shoulder", "", ""], "hoe": ["Hoe", "art:tool.hoe", ""], "herd": ["Herd", "art:tool.crook", ""],
			"shear": ["Fixing_Kneeling", "art:tool.shears", ""]},
			"stalking with a bow, carrying game and a sack, hoeing, herding, shearing: each its clip and pieces (%s)" % works)
	show.call("sleep")
	var lain_down := rig.base_clip()
	puppet.set_meta("busy_until", 0)  # The lie-down (751) done.
	show.call("sleep")
	_rig._lay(puppet, puppet.get_node("Body"), 0.0)
	var body := puppet.get_node("Body") as Node3D
	var model := body.get_node("Model") as Node3D
	_check(lain_down == "Sleep_Down" and rig.base_clip() == "Sleep_Side"
			and body.position.distance_to(Vector3(-Client3D.SLEEP_MIDDLE, 0, -Client3D.SLEEP_ASIDE) * float(puppet.get_meta("model_scale", 1.0))) < 0.001
			and is_equal_approx(wrapf(model.rotation.y - float(puppet.get_meta("faces")), 0.0, TAU), PI),
			"asleep: lain down to (%s), curled (%s), turned to put the head the way it faces, along its bed (%s)" % [lain_down, rig.base_clip(), body.position])
	show.call("dig_for_treasure")
	puppet.set_meta("busy_until", 0)  # Got up (751).
	puppet.set_meta("rising_until", 0)
	show.call("dig_for_treasure")
	_rig._lay(puppet, puppet.get_node("Body"), 0.0)
	_check(rig.upper_clip() == "" and (sockets["shoulder"] as Node3D).get_node_or_null("Load") == null and body.position == Vector3.ZERO
			and is_equal_approx(model.rotation.y, float(puppet.get_meta("faces"))) and rig.base_clip() != "Lie",
			"a word it doesn't know: standing as before, nothing carried (%s)" % rig.base_clip())
	# On the throne (580 step 3): a body on a cell whose piece has a stand
	# point stands there, turned by the piece's facing (north here: its
	# front 0.4 toward -z, 0.1 up); elsewhere at the cell's middle.
	var throne_cell := Vector2i(5, 5)
	var north := atan2(0.0, -1.0)
	var at := Client3D.stand_offset("building.throne", Rect2i(throne_cell, Vector2i.ONE), north, throne_cell)
	_check(at.distance_to(Vector3(0.0, 0.1, -0.4)) < 0.001 and Client3D.stand_offset("building.link_arch", Rect2i(throne_cell, Vector2i.ONE), north, throne_cell) == Vector3.ZERO,
		"the throne's stand point, faced north: 0.4 toward its front, 0.1 up (%s); a piece without one, the middle" % at)
	_rig._stand_at[throne_cell] = at
	_rig._lay(puppet, body, 0.0, throne_cell)
	var on_throne := body.position
	_rig._lay(puppet, body, 0.0, throne_cell + Vector2i.RIGHT)
	_check(on_throne == at and body.position == Vector3.ZERO, "standing on its cell he is drawn at it (%s); off it, the cell's middle again" % on_throne)
	_rig._stand_at.erase(throne_cell)
	resident.free()
	# The bandage kneel: a player tending a body beside it kneels, turned to it,
	# leant in; walking, it walks; done, it stands.
	var patient: GridEntity = null
	for other in World.get_entities():
		if other != player and other.spawned and other.tile != player.tile and patient == null:
			patient = other
	_check(patient != null, "a body to tend")
	if patient != null:
		player.tending = String(patient.name)
		_rig._sync_work(player, puppet)
		_rig._animate(puppet)
		var toward := -Vector2(patient.tile - player.tile).angle()
		var yaw := Client3D._tending_yaw(player, 0.0)
		_rig._lay(puppet, body, yaw)
		var leant := body.position.length()
		_check(rig.base_clip() == "Fixing_Kneeling" and patient.tile != player.tile and is_equal_approx(yaw, toward)
				and absf(leant - 0.3 * float(puppet.get_meta("model_scale", 1.0))) < 0.001,
				"tending a body: kneeling (%s), turned to it, leant in %.2f m" % [rig.base_clip(), leant])
		puppet.set_meta("speed", 3.0)
		_rig._animate(puppet)
		_rig._lay(puppet, body, yaw)
		_check(rig.base_clip() != "Fixing_Kneeling" and body.position == Vector3.ZERO, "moving (shoved): it walks, not leant (%s)" % rig.base_clip())
		puppet.set_meta("speed", 0.0)
		player.tending = ""
		_rig._sync_work(player, puppet)
		_rig._animate(puppet)
		_rig._lay(puppet, body, yaw)
		_check(rig.base_clip() != "Fixing_Kneeling" and body.position == Vector3.ZERO and Client3D._tending_yaw(player, 1.0) == 1.0,
				"done or broken off: standing again, its own facing (%s)" % rig.base_clip())
		# A fidget already playing when the tending starts gives way to the kneel at once (items'
		# (3): the fidget held it off up to 3.4 s, and a short bandage showed no kneel at all).
		_rig._combat_at.erase(int(puppet.get_meta("entity_id", 0)))  # Calm: a fight drops a fidget anyway.
		Client3D._play_fidget(puppet, rig, "Fidget_Shift", Time.get_ticks_msec(), 1.0)
		var fidget := rig.base_clip()
		player.tending = String(patient.name)
		_rig._sync_work(player, puppet)
		_rig._animate(puppet)
		_check(fidget == "Fidget_Shift" and rig.base_clip() == "Fixing_Kneeling",
				"a fidget playing (%s) when the tending starts: kneeling at once (%s)" % [fidget, rig.base_clip()])
		player.tending = ""
		_rig._sync_work(player, puppet)
		_rig._animate(puppet)
	_rig._sync_held(player, puppet)
	puppet.set_meta("work", "")
	_rig._animate(puppet)


func _test_attach_points() -> void:
	print("
== attach points (decision 451): what a hand holds is drawn in it, the lantern at the belt ==")
	var player := _player()
	var hold := func(entity: GridEntity, right: String, left: String) -> void:
		var slots := entity.slots
		while slots.size() < Items.CARRIED:
			slots.append("")
		slots[Items.RIGHT_HAND] = right
		slots[Items.LEFT_HAND] = left
		entity.slots = slots
		_rig._process(0.0)
	hold.call(player, "sword", "shield")
	var puppet: Node3D = _rig._puppets[player.get_instance_id()]
	var sockets: Dictionary = puppet.get_meta("sockets", {})
	_check(sockets.has_all(["hand_r", "hand_l", "back", "belt_r", "hip_l"]) and (sockets["hand_r"].get_parent() as BoneAttachment3D).bone_name == "RightHand",
			"a person has hand, back, belt and sheath sockets on their bones")
	var sword := (sockets["hand_r"] as Node3D).get_node_or_null("Held") as Node3D
	var shield := (sockets["arm_l"] as Node3D).get_node_or_null("Held") as Node3D if sockets.has("arm_l") else null
	_check(sword != null and shield != null, "a sword drawn in the right hand, a shield on the left arm")
	if sword != null:
		var skeleton := puppet.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		# Where the socket puts it in the hand's pose now (the attachment follows
		# the pose a frame later): beside the fist's knuckles, along its axis.
		var bone := func(name: String) -> Transform3D:
			return skeleton.get_bone_global_pose(skeleton.find_bone(name))
		var grip: Transform3D = bone.call("RightHand") * (sockets["hand_r"] as Node3D).transform
		var fist: Vector3 = (bone.call("RightIndexProximal").origin - bone.call("RightLittleProximal").origin).normalized()
		var knuckles: Vector3 = (bone.call("RightIndexProximal").origin + bone.call("RightLittleProximal").origin) * 0.5
		var scale: float = skeleton.global_transform.basis.get_scale().y
		# In the palm (the mitten's middle), not out at the knuckle line (Jeff: "sword hilt is at the end of hand").
		var wrist: Transform3D = bone.call("RightHand")
		var out: float = (grip.origin - wrist.origin).dot(wrist.basis.y.normalized()) * scale
		_check(grip.basis.y.normalized().dot(fist) > 0.9 and out > 0.055 and out < 0.085 and grip.origin.distance_to(knuckles) * scale > 0.02,
				"its grip in the palm, %.3f m out from the wrist (%.3f m short of the knuckles), its length along the fist's axis (%.2f)" % [
				out, grip.origin.distance_to(knuckles) * scale, grip.basis.y.normalized().dot(fist)])
		_check(absf((skeleton.global_transform.basis * grip.basis).get_scale().y - 1.0) < 0.02,
				"at its own size, whatever the person's stature")
		# Its edge (+x) along the fingers toward the knuckles, not out of the palm (Jeff: "held sideways").
		var edge: Vector3 = (grip.basis * sword.transform.basis).x.normalized()
		var fingers: Vector3 = (bone.call("RightHand") as Transform3D).basis.y.normalized()
		_check(edge.dot(fingers) > 0.9, "its edge along the fingers, toward the knuckles (%.2f)" % edge.dot(fingers))
	_check(shield != null and shield.get_parent() == sockets.get("arm_l"), "the shield strapped on the left forearm, not in the hand")
	if shield != null:
		# On the outside of the forearm (Jeff: "not inside"): its face out of the forearm's back (the bone's -X),
		# its centre beyond it, the forearm between it and the body.
		var forearm := (sockets["arm_l"] as Node3D).get_parent() as Node3D
		var back := -forearm.global_basis.x.normalized()
		var beyond := (shield.global_position - (sockets["arm_l"] as Node3D).global_position).dot(back)
		_check(shield.global_basis.z.normalized().dot(back) > 0.99 and beyond > 0.04,
				"the shield's face (+z) out of the back of the forearm, its centre %.3f m beyond it" % beyond)
	hold.call(player, "", "shield")
	_check((sockets["hand_r"] as Node3D).get_children().all(func(n: Node) -> bool: return n.is_queued_for_deletion()),
			"the hand emptied: nothing drawn in it")
	hold.call(player, "", "")
	_check((sockets["belt_r"] as Node3D).get_node_or_null("LanternBody") != null, "the lantern hangs at the right of the belt (the left is the sheath's, 662 (c))")
	var imp := _spawn_imp(Vector2i(9, 6), "imp")
	_rig._process(0.0)
	hold.call(imp, "dagger", "")
	var goblin: Node3D = _rig._puppets[imp.get_instance_id()]
	var held: Node3D = (goblin.get_meta("sockets", {}) as Dictionary).get("hand_r")
	_check(held != null and held.get_node_or_null("Held") != null, "a goblin's dagger is in its hand")
	World.despawn(imp)
	_rig._process(0.0)


## A sleeper (751, pc-character's side; Jeff: sleeping townsfolk "look like they are dead"): a
## resident's "sleep" is the side curl (Sleep_Side), laid with its head toward the facing and its
## middle SLEEP_MIDDLE back, up on its bed's height (npc's bed_height); lain down to once, already
## down when first seen, and got up from when it ends, still turned as it lay till it stands.
func _test_sleeper() -> void:
	print("
== a sleeper: curled on its side, on its bed, lain down to and got up from ==")
	var work: Dictionary = Client3D.ACTIVITIES["sleep"]
	_check(str(work["clip"]) == "Sleep_Side" and str(work["down"]) == "Sleep_Down" and bool(work["lying"])
		and Client3D.ACTIVITIES["sleep_side"].get("down") == "Sleep_Down", "asleep: the side curl, lain down to (%s)" % [work])
	var puppet := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	puppet.add_child(body)
	var model := (load(Client3D.HUMAN["scene"]) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	body.add_child(model)
	add_child(puppet)
	puppet.set_meta("faces", 0.0)
	puppet.set_meta("work", "sleep")
	puppet.set_meta("bed_height", 0.09)
	_rig._lay(puppet, body, 0.0)
	_check(body.position.distance_to(Vector3(-Client3D.SLEEP_MIDDLE, 0.09, -Client3D.SLEEP_ASIDE)) < 0.001 and is_equal_approx(model.rotation.y, PI),
		"laid on its bedroll, its middle %.2f back, %.2f aside, %.2f up, turned round (%s, %.2f)" % [Client3D.SLEEP_MIDDLE, Client3D.SLEEP_ASIDE, 0.09, body.position, model.rotation.y])
	var rig := AnimRig.make(model, load("res://art/models/animations/goblin.res") as AnimationLibrary, 0.0, true, null)
	rig.loop("Idle", 0.0)
	var now := Time.get_ticks_msec()
	var first := _rig._lying_down(puppet, rig, work, 0.0, now, 1.0)
	_check(not first and bool(puppet.get_meta("laid")), "first seen asleep: already down, no lying down")
	puppet.set_meta("laid", false)
	var down := _rig._lying_down(puppet, rig, work, 0.0, now, 1.0)
	_check(down and rig.base_clip() == "Sleep_Down", "falling asleep: lies down (%s)" % rig.base_clip())
	var up := _rig._lying_down(puppet, rig, {}, 0.0, now, 1.0)
	_check(up and rig.base_clip() == "Sleep_Up" and int(puppet.get_meta("rising_until")) > now, "woken: gets up (%s)" % rig.base_clip())
	puppet.set_meta("work", "")
	_rig._lay(puppet, body, 0.0)
	_check(is_equal_approx(model.rotation.y, PI), "and is still turned as it lay while it gets up")
	puppet.set_meta("rising_until", 0)
	_rig._lay(puppet, body, 0.0)
	_check(is_zero_approx(model.rotation.y) and body.position == Vector3.ZERO, "stood: as it stands (%s)" % body.position)
	puppet.free()
	_test_sleeper_posture()


## Umbrage's townsfolk at their spots (npc's spots contract; the coordinator's Umbrage focus, Jeff:
## "townspeople frozen"): each spot's word has its clips; "sit" sits down onto the seat once
## (SEAT_DOWN), each body one of the sit's idles, already sat when first seen, the talk and listen
## turns kept sat, and gets up (SEAT_UP) when the word ends, cut short if it walks off; the body
## eased SEAT_TOWARD ahead of its cell and back; the sit's hips at a seat's height that far
## behind its feet, and the lean's forearms on the well's coping before it.
func _test_townsfolk_spots() -> void:
	print("
== townsfolk at their spots: sat on a seat, leant on the well, talking and listening ==")
	var lib := load("res://art/models/animations/goblin.res") as AnimationLibrary
	var missing: Array[String] = []
	for word: String in ["sit", "sit_talk", "sit_listen", "lean", "talk", "listen", "tend"]:
		var spot: Dictionary = Client3D.ACTIVITIES.get(word, {})
		var clips: Array = spot.get("clips", [spot.get("clip", "")]) + spot.get("asides", [])
		for key: String in ["enter", "exit"]:
			if spot.has(key):
				clips.append(spot[key])
		for clip: String in clips:
			if not lib.has_animation(clip):
				missing.append("%s: %s" % [word, clip])
	for clip: String in [Client3D.SEAT_DOWN, Client3D.SEAT_UP]:
		if not lib.has_animation(clip):
			missing.append(clip)
	_check(missing.is_empty(), "each spot's word has its clips (missing: %s)" % [missing])
	_check(["sit", "sit_talk", "sit_listen"].all(func(w: String) -> bool: return bool(Client3D.ACTIVITIES[w].get("seat", false)))
			and ["lean", "talk", "listen"].all(func(w: String) -> bool: return not Client3D.ACTIVITIES[w].has("seat")),
			"sat words on a seat, the lean and the stood talk not")
	var puppet := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	puppet.add_child(body)
	var model := (load(Client3D.HUMAN["scene"]) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	body.add_child(model)
	add_child(puppet)
	puppet.set_meta("faces", 0.0)
	puppet.set_meta("entity_id", 7)
	var rig := AnimRig.make(model, lib, 0.0, true, null)
	rig.loop("Idle", 0.0)
	var sit: Dictionary = Client3D.ACTIVITIES["sit"]
	var now := Time.get_ticks_msec()
	var first := _rig._seat(puppet, rig, sit, 0.0, now, 1.0)
	_check(not first and bool(puppet.get_meta("sat")) and is_equal_approx(Client3D._seated_share(puppet, now), 1.0),
			"first seen sat: already down, its hips over the seat")
	puppet.set_meta("sat", false)
	var down := _rig._seat(puppet, rig, sit, 0.0, now, 1.0)
	var ease_ms := int(Client3D.SEAT_EASE * 1000.0)
	_check(down and rig.base_clip() == Client3D.SEAT_DOWN and is_zero_approx(Client3D._seated_share(puppet, now))
			and is_equal_approx(Client3D._seated_share(puppet, now + ease_ms), 1.0),
			"come to its seat: sits down onto it, drawn toward it over the ease (%s)" % rig.base_clip())
	puppet.set_meta("work", "sit")
	puppet.set_meta("seat_at", Time.get_ticks_msec() - ease_ms - 50)
	_rig._lay(puppet, body, 0.0)
	_check(body.position.distance_to(Vector3(Client3D.SEAT_TOWARD, 0.0, 0.0)) < 0.001,
			"sat: drawn %.3f ahead of its cell, its hips over the seat (%s)" % [Client3D.SEAT_TOWARD, body.position])
	var idles := {}
	for id in 3:
		puppet.set_meta("entity_id", id)
		idles[Client3D._work_clip(puppet, sit)] = true
	puppet.set_meta("entity_id", 7)
	_check(idles.size() == 3 and idles.keys().all(func(c: String) -> bool: return c in sit["clips"]),
			"each body one of the sit's idles, neighbours apart (%s)" % [idles.keys()])
	var turned := not _rig._seat(puppet, rig, Client3D.ACTIVITIES["sit_talk"], 0.0, now, 1.0) \
			and not _rig._seat(puppet, rig, Client3D.ACTIVITIES["sit_listen"], 0.0, now, 1.0) and bool(puppet.get_meta("sat"))
	_check(turned, "talking and listening in turn on the seat: still sat, not sat down again")
	var up := _rig._seat(puppet, rig, {}, 0.0, now, 1.0)
	var until := int(puppet.get_meta("unseat_until", 0))
	_check(up and rig.base_clip() == Client3D.SEAT_UP and until > now and is_equal_approx(Client3D._seated_share(puppet, now), 1.0)
			and is_zero_approx(Client3D._seated_share(puppet, until + ease_ms)),
			"its word ended: gets up, held over the seat till it stands, then eased back (%s)" % rig.base_clip())
	puppet.set_meta("sat", true)
	_rig._seat(puppet, rig, {}, 0.0, now, 1.0)
	_rig._seat(puppet, rig, {}, 2.0, now + 100, 1.0)
	_check(int(puppet.get_meta("unseat_until")) == now + 100 and int(puppet.get_meta("busy_until")) == 0,
			"walked off while getting up: the getting up goes")
	# Where the clips put it: the sit's hips at a seat's height behind its feet; the lean's wrists on
	# the coping (the town well's 0.82 m) before it. Measured against the idle's hips (the UAL's
	# 0.88 m), as the body is scaled.
	var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var at := func(clip: String, seconds: float, bone: String) -> Vector3:
		rig.base_at(clip, seconds)
		rig.tree.advance(0.0)
		return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin
	var front := skeleton.global_basis.z.normalized()
	var hips: Vector3 = at.call("Idle", 0.0, "Hips")
	var feet: Vector3 = (at.call("Idle", 0.0, "LeftFoot") + at.call("Idle", 0.0, "RightFoot")) / 2.0
	var sized := hips.y / 0.877
	var sat_hips: Vector3 = at.call("Sitting_Idle", 0.5, "Hips")
	var back := (feet - sat_hips).dot(front) / sized
	_check(absf(sat_hips.y / sized - 0.54) < 0.04 and absf(back - Client3D.SEAT_TOWARD) < 0.06,
			"sat: its hips %.2f up (a 0.45 m seat's), %.2f behind its feet (SEAT_TOWARD %.3f)" % [sat_hips.y / sized, back, Client3D.SEAT_TOWARD])
	var lean_low := 9.0
	var lean_high := -9.0
	var reach_least := 9.0
	var reach_most := -9.0
	for k in 12:
		for hand: String in ["LeftHand", "RightHand"]:
			var wrist: Vector3 = at.call("Lean_Rail", k * lib.get_animation("Lean_Rail").length / 12.0, hand)
			lean_low = minf(lean_low, wrist.y / sized)
			lean_high = maxf(lean_high, wrist.y / sized)
			var ahead := (wrist - feet).dot(front) / sized
			reach_least = minf(reach_least, ahead)
			reach_most = maxf(reach_most, ahead)
	_check(lean_low > 0.82 and lean_high < 0.95 and reach_least > 0.3 and reach_most < 0.6,
			"leant on the well: its wrists %.2f to %.2f up (the coping 0.82), %.2f to %.2f before its feet (the ring's edge 0.3)"
			% [lean_low, lean_high, reach_least, reach_most])
	# The keeper at its counter (tend): stepped up to as the work begins (first seen there, already
	# there), now and then an aside, never the same twice running, stepped back from as it ends.
	var tend: Dictionary = Client3D.ACTIVITIES["tend"]
	now = Time.get_ticks_msec()
	puppet.set_meta("sat", false)
	puppet.set_meta("work", "tend")
	puppet.remove_meta("entered")
	var seen := not _rig._work_enter(puppet, rig, tend, 0.0, now, 1.0) and str(puppet.get_meta("entered")) == "tend"
	puppet.set_meta("entered", "")
	var stepped: bool = _rig._work_enter(puppet, rig, tend, 0.0, now, 1.0) and rig.base_clip() == str(tend["enter"])
	var held := not _rig._work_enter(puppet, rig, tend, 0.0, now, 1.0)
	_check(seen and stepped and held, "the keeper: first seen at its counter already there, else steps up to it once (%s)" % rig.base_clip())
	puppet.set_meta("rng", RandomNumberGenerator.new())
	puppet.set_meta("aside_at", now - 1)
	var first_aside := _rig._work_aside(puppet, rig, tend, now, 1.0)
	var shown := rig.base_clip()
	puppet.set_meta("aside_at", now - 1)
	var second_aside := _rig._work_aside(puppet, rig, tend, now, 1.0)
	_check(first_aside and second_aside and shown in tend["asides"] and rig.base_clip() in tend["asides"] and rig.base_clip() != shown
			and str(puppet.get_meta("aside_of")) == "tend" and int(puppet.get_meta("aside_at")) > now,
			"now and then shows or hands over a ware, never the same twice running (%s, %s)" % [shown, rig.base_clip()])
	# A long sit (npc's 2 to 4 minutes) or stand: now and then a sitter takes another of the sitting
	# idles once through, never its own; the sat talker and listener pause in one; the stood shift or
	# look about, never a sitting clip.
	puppet.set_meta("work", "sit")
	puppet.remove_meta("aside_clip")
	var own := Client3D._work_clip(puppet, Client3D.ACTIVITIES["sit"])
	var taken := {}
	for k in 8:
		puppet.set_meta("aside_at", now - 1)
		if _rig._work_aside(puppet, rig, Client3D.ACTIVITIES["sit"], now, 1.0):
			taken[rig.base_clip()] = true
	var seated_ok := ["sit", "sit_talk", "sit_listen"].all(func(w: String) -> bool:
		return (Client3D.ACTIVITIES[w].get("asides", []) as Array).all(func(c: String) -> bool: return c.begins_with("Sitting_")))
	var stood_ok := ["talk", "listen"].all(func(w: String) -> bool:
		var asides: Array = Client3D.ACTIVITIES[w].get("asides", [])
		return not asides.is_empty() and asides.all(func(c: String) -> bool: return not c.begins_with("Sitting_")))
	_check(taken.size() == 2 and not taken.has(own) and seated_ok and stood_ok,
			"a long sit: the other sitting idles now and then, never its own (%s; took %s); sat asides seated, stood ones standing"
			% [own, taken.keys()])
	puppet.set_meta("work", "")
	var stepped_back := _rig._work_enter(puppet, rig, {}, 0.0, now, 1.0)
	_check(stepped_back and rig.base_clip() == tend["exit"] and int(puppet.get_meta("unseat_until")) > now,
			"its word ended: steps back from the counter (%s)" % rig.base_clip())
	# Where its hands rest: the market stall's top 0.88 m, its keeper's edge behind the counter.
	var low := 9.0
	var high := -9.0
	var near := 9.0
	var far := -9.0
	var idle_length := lib.get_animation(str(tend["clip"])).length
	for k in 12:
		for hand: String in ["LeftHand", "RightHand"]:
			var wrist: Vector3 = at.call(str(tend["clip"]), k * idle_length / 12.0, hand)
			low = minf(low, wrist.y / sized)
			high = maxf(high, wrist.y / sized)
			var ahead := (wrist - feet).dot(front) / sized
			near = minf(near, ahead)
			far = maxf(far, ahead)
	_check(low > 0.89 and high < 0.95 and near > 0.4 and far < 1.5,
			"the keeper's hands on the stall's top: its wrists %.2f to %.2f up (the top 0.88), %.2f to %.2f before its feet (the top from 0.4 to 1.5)"
			% [low, high, near, far])
	puppet.free()


## 751 amended (5): a stooped person's posture is off while it lies (it lifted the curl's
## trunk 7 cm off the bed) and fades back on over POSTURE_FADE when it stands.
func _test_sleeper_posture() -> void:
	var lib := load("res://art/models/animations/goblin.res") as AnimationLibrary
	var puppet := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	puppet.add_child(body)
	var model := (load(Client3D.HUMAN["scene"]) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	body.add_child(model)
	add_child(puppet)
	var rig := AnimRig.make(model, lib, 0.0, true, null)
	rig.loop("Idle", 0.0)
	var stoop := lib.get_animation(str(Client3D.POSTURES["stooped"]))
	rig.posture(stoop, 1.0)
	puppet.set_meta("rig", rig)
	puppet.set_meta("posture", stoop)
	puppet.set_meta("faces", 0.0)
	puppet.set_meta("work", "sleep")
	var amount := func() -> float: return float(rig.tree.get("parameters/posture/add_amount"))
	_rig._lay(puppet, body, 0.0)
	_check(is_zero_approx(amount.call()), "a stooped sleeper, first seen asleep: its stoop off at once (%.2f)" % amount.call())
	puppet.set_meta("work", "")
	puppet.set_meta("posture_ms", Time.get_ticks_msec() - int(Client3D.POSTURE_FADE * 500.0))
	_rig._lay(puppet, body, 0.0)
	_check(absf(amount.call() - 0.5) < 0.1, "stood up: the stoop half back after half of POSTURE_FADE (%.2f)" % amount.call())
	puppet.set_meta("posture_ms", Time.get_ticks_msec() - int(Client3D.POSTURE_FADE * 1000.0))
	_rig._lay(puppet, body, 0.0)
	_check(is_equal_approx(amount.call(), 1.0), "and all back after it (%.2f)" % amount.call())
	puppet.set_meta("work", "sleep")
	puppet.set_meta("posture_ms", Time.get_ticks_msec() - int(Client3D.POSTURE_FADE * 1000.0))
	_rig._lay(puppet, body, 0.0)
	_check(is_zero_approx(amount.call()), "lain down again: off (%.2f)" % amount.call())
	puppet.free()


## A two-handed piece (451 amended (2), step 4; Jeff: the great axe "held sideways by player and
## draugr"): the left hand on its second grip (art-kit's grip_2), turned along the haft as the right
## one is (HandReach), standing ready (Axe_Ready) and through the overhead swing; off with a shield
## in the left. Real frames: the sockets follow the pose the modifiers leave.
func _test_two_hands() -> void:
	print("
== two hands on a two-handed piece: the left on its grip_2 ==")
	var player := _player()
	var slots := player.slots
	while slots.size() < Items.CARRIED:
		slots.append("")
	var was := slots.duplicate()
	slots[Items.RIGHT_HAND] = "giant_axe"
	slots[Items.LEFT_HAND] = ""
	player.slots = slots
	player.raised = ""
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets[player.get_instance_id()]
	var sockets: Dictionary = puppet.get_meta("sockets")
	var rig := puppet.get_meta("rig") as AnimRig
	var reach := puppet.get_meta("reach") as HandReach if puppet.has_meta("reach") else null
	_check(reach != null and reach.active, "a two-handed axe: the left hand reaches for it")
	_check(rig.upper_clip() == "Axe_Ready", "standing with it: the ready stance (%s)" % rig.upper_clip())
	if reach != null:
		var axe := (sockets["hand_r"] as Node3D).get_node("Held") as Node3D
		for at: float in [-1.0, 0.0, 0.55]:
			if at >= 0.0:
				rig.upper_at("Axe_Overhead", at)
			for i in 3:
				await get_tree().process_frame
			var left := sockets["hand_l"] as Node3D
			var off := left.global_position.distance_to(axe.global_transform * reach.grip)
			var along := left.global_basis.y.normalized().dot(axe.global_basis.y.normalized())
			_check(off < 0.04 and along > 0.95, "%s: the left hand on its grip_2, %.3f m off, its fist along the haft (%.2f)" % [
					"standing ready" if at < 0.0 else "Axe_Overhead at %.2f s" % at, off, along])
			if at < 0.0:
				# Ready, the haft laid forward: the left hand at the chest, not across the face (the coordinator,
				# on art-kit's stills: "a fist across the face in the ready pose").
				var skeleton := puppet.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
				var neck := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Neck")).origin
				_check(left.global_position.y < neck.y - 0.05, "standing ready: the left hand %.2f m below the neck" % (neck.y - left.global_position.y))
	# The Tomb Sledge (750, pc-character's side; Jeff: "it shouldn't be held at the very end of the
	# shaft"): the right hand at its grip (0.35 m up from the butt since 451 amended (5)), the left on
	# grip_2; struck, the left hand slides down the haft toward the right as it falls (REACH_SLIDES),
	# and is on it there; at the contact and held down after it, the head on the ground before him.
	slots[Items.RIGHT_HAND] = "tomb_sledge"
	player.slots = slots
	_rig._process(0.0)
	var sledge_sockets: Dictionary = ArtKit.spec("item.tomb_sledge").get("sockets", {})
	var grip_up := float(sledge_sockets["grip"][1])
	var grip_2 := float(sledge_sockets["grip_2"][1])
	var sledge := (sockets["hand_r"] as Node3D).get_node("Held") as Node3D
	var hand := (sockets["hand_r"] as Node3D).global_position
	var up := (hand - sledge.global_position).dot(sledge.global_basis.y.normalized())
	_check(absf(up - grip_up) < 0.005 and reach != null and reach.active and is_equal_approx(reach.grip.y, grip_2),
		"the sledge in hand %.2f m up from its butt (its grip %.2f), the left hand on its grip_2 at %.2f" % [up, grip_up, reach.grip.y if reach != null else -1.0])
	if reach != null:
		rig.strike("Sledge_Attack", 0.9, 0.9, 0.8)
		var slid := 0.0
		var worst := 0.0
		var ground_gap := -INF  # The head's lowest above the ground, its highest from 0.9 to 1.3 s.
		var ground_dip := INF
		var heights := {}
		var worst_at := 0.0
		# Scrubbed, not waited on (750 amended (3)): the strike held at each time in turn, its slide
		# and its pose at the same moment. On the wall clock a slow frame under a loaded suite let the
		# pose run on past the grip read before it (0.139 m off once).
		rig._contact_msec = -1
		rig._strike_msec = Time.get_ticks_msec() + 600000
		rig._set_action_speed(0.0)
		# Its fade in run out first (as the axes' edge test): that is on the wall clock, so under load the
		# first steps scrubbed stood half blended with the ready stance (0.103 to 0.110 m off).
		rig.tree.set("parameters/action_seek/seek_request", 0.0)
		rig._apply()
		await get_tree().create_timer(0.5).timeout
		var length := rig.length("Sledge_Attack")
		for step in int(length / 0.05) + 1:
			rig.tree.set("parameters/action_seek/seek_request", minf(step * 0.05, length))
			rig._apply()
			_rig._process(0.0)
			var grip := reach.grip
			await get_tree().process_frame
			slid = maxf(slid, grip_2 - grip.y)
			var off := (sockets["hand_l"] as Node3D).global_position.distance_to(sledge.global_transform * grip)
			if off > worst:
				worst = off
				worst_at = step * 0.05
			if step * 0.05 >= 0.9 - 0.001 and step * 0.05 <= 1.3 + 0.001:
				var low := INF
				for mesh: MeshInstance3D in sledge.find_children("*", "MeshInstance3D", true, false):
					var box := mesh.get_aabb()
					for corner in 8:
						low = minf(low, (mesh.global_transform * box.get_endpoint(corner)).y)
				ground_gap = maxf(ground_gap, low - puppet.global_position.y)
				ground_dip = minf(ground_dip, low - puppet.global_position.y)
				heights["%.2f" % (step * 0.05)] = snappedf(low - puppet.global_position.y, 0.001)
		# 0.09 m off on a quiet run, on its fade in run out: 0.12 leaves a loaded frame room (release).
		_check(slid > 0.3 and worst < 0.12, "struck: the left hand slid %.2f m down the haft toward the right, never more than %.3f m off it (at %.2f s)" % [slid, worst, worst_at])
		print("  the sledge's head off the ground: %s" % [heights])
		_check(ground_gap < 0.1 and ground_dip > -0.06, "struck: the head on the ground from the contact to 1.3 s (its lowest %.3f to %.3f m off the ground)" % [ground_dip, ground_gap])
		# Ended as a strike ends: its clip run out at speed again (a cancel left at speed 0 never
		# fades, and the rests after it stood on it).
		rig._set_action_speed(1.0)
		rig.tree.set("parameters/action_seek/seek_request", length)
		rig._apply()
		rig._strike_msec = 0
		for i in 4:
			await get_tree().process_frame
		_rig._process(0.0)
		_check(not rig.striking() and is_equal_approx(reach.grip.y, grip_2), "the blow done: back at grip_2 (%.2f)" % reach.grip.y)
	slots[Items.RIGHT_HAND] = "giant_axe"
	player.slots = slots
	_rig._process(0.0)
	# A one-handed weapon never swings a two-handed clip (the war hammer did: its left hand came up
	# beside the haft holding nothing).
	var two_handed_clips := ["Axe_Overhead", "Sledge_Attack", "Axe_Sweep"]
	var one_handed := (Client3D.HUMANOID_MOVES["strikes"] as Dictionary).keys().filter(func(id: String) -> bool:
		return Items.exists(id) and int(Items.def(id).get("hands", 1)) < 2 and (Client3D.HUMANOID_MOVES["strikes"][id] as Array).any(
				func(strike: Array) -> bool: return strike[0] in two_handed_clips))
	_check(one_handed.is_empty(), "no one-handed weapon strikes with both hands (%s)" % [one_handed])
	slots[Items.LEFT_HAND] = "shield"
	player.slots = slots
	_rig._process(0.0)
	_check(reach == null or not reach.active, "a shield in the left: no reach")
	_check(rig.upper_clip() == "", "nor the ready stance (%s)" % rig.upper_clip())
	player.slots = was
	_rig._process(0.0)


## A body wet (775; Jeff: wading "makes character get wet"): standing in water it is wet up to the
## water's depth and a splash, kept out of it and drying over DRY_SECONDS (FIRE_DRY times faster by a
## fire); rain outdoors wets it all over, and nothing dries in it; walled in, the rain wets nothing.
## Drawn as the overlay on its meshes, off when dry; with the target's outline, the wet overlay
## passes on to it.
func _test_wet() -> void:
	print("\n== a body wet from wading and rain, drying (775) ==")
	var WetLook := Client3D.WetLook
	var player := _player()
	var puppet: Node3D = _rig._puppets[player.get_instance_id()]
	var cell := Vector2i(roundi(puppet.position.x), roundi(puppet.position.z))
	var had_bed: bool = _rig._bed_levels.has(cell)
	var bed: float = _rig._bed_levels.get(cell, 0.0)
	var fires: Array[Vector2i] = _rig._terrain.get("fire", [] as Array[Vector2i])
	var fires_were := fires.duplicate()
	var weather = _rig._weather_view
	var dry := func() -> void:
		for key: String in ["wet", "wet_line", "wet_all"]:
			puppet.set_meta(key, 0.0)
	dry.call()
	var water := puppet.position.y + 0.4
	_rig._bed_levels[cell] = water
	_check(absf(WetLook.depth_at(_rig, puppet) - 0.4) < 0.001, "the water 0.4 m deep at its feet (%.2f)" % WetLook.depth_at(_rig, puppet))
	WetLook.soak(_rig, puppet, WetLook.STEP)
	var line := float(puppet.get_meta("wet_line"))
	_check(is_equal_approx(float(puppet.get_meta("wet")), 1.0) and absf(line - (0.4 + WetLook.SPLASH)) < 0.001,
		"wading: wet up to the water and a splash (%.2f m)" % line)
	WetLook.show(_rig, puppet)
	var meshes := WetLook.meshes_of(puppet)
	_check(not meshes.is_empty() and meshes.all(func(m: MeshInstance3D) -> bool: return m.material_overlay == WetLook.material_of(puppet)),
		"its %d meshes under its own wet overlay" % meshes.size())
	var drawn_line := float(WetLook.material_of(puppet).get_shader_parameter("wet_line"))
	_check(absf(drawn_line - (puppet.global_position.y + line)) < 0.001, "the line drawn at the water's height on it (%.2f)" % drawn_line)
	# Wading: a ford's water (FORD_DEPTH, every hills stream since 776) plays the wade; a skim doesn't.
	var rig: AnimRig = puppet.get_meta("rig")
	_rig._bed_levels[cell] = puppet.position.y + Client3D.FORD_DEPTH
	_check(_rig.wading(puppet, rig), "in a ford's %.2f m of water: it wades" % Client3D.FORD_DEPTH)
	_rig._bed_levels[cell] = puppet.position.y + 0.02
	_check(not _rig.wading(puppet, rig), "in 0.02 m: it walks")
	_rig._bed_levels.erase(cell)
	if had_bed:
		_rig._bed_levels[cell] = bed
	var rained: bool = weather != null and weather.outdoor and float(weather.weather.get("rain", 0.0)) >= WetLook.RAIN_WETS and not _rig._enclosed.has(cell)
	_check(not rained, "no rain on it here (the test's weather)")
	WetLook.soak(_rig, puppet, WetLook.DRY_SECONDS * 0.5)
	_check(absf(float(puppet.get_meta("wet")) - 0.5) < 0.01 and is_equal_approx(float(puppet.get_meta("wet_line")), line),
		"out of the water: half dry after half of DRY_SECONDS, the line kept (%.2f)" % float(puppet.get_meta("wet")))
	WetLook.soak(_rig, puppet, WetLook.DRY_SECONDS * 0.5 + 0.1)
	WetLook.show(_rig, puppet)
	_check(is_zero_approx(float(puppet.get_meta("wet"))) and is_zero_approx(float(puppet.get_meta("wet_line")))
			and meshes.all(func(m: MeshInstance3D) -> bool: return m.material_overlay == null),
		"dry after DRY_SECONDS: the line gone, the overlay off")
	# By a fire: FIRE_DRY times faster.
	puppet.set_meta("wet", 1.0)
	puppet.set_meta("wet_line", 0.5)
	fires.append(cell + Vector2i(2, 1))
	_rig._terrain["fire"] = fires
	WetLook.soak(_rig, puppet, WetLook.DRY_SECONDS / WetLook.FIRE_DRY * 0.5)
	_check(absf(float(puppet.get_meta("wet")) - 0.5) < 0.01, "by a fire two cells off: half dry in a quarter of the time (%.2f)" % float(puppet.get_meta("wet")))
	_rig._terrain["fire"] = fires_were
	# A camp's fire ring (777, Level.camp_fire) dries as a fire does, within FIRE_REACH.
	var buildings: Array = _rig._terrain.get("buildings", [])
	var had_buildings := _rig._terrain.has("buildings")
	_check(not WetLook.near_fire(_rig, cell), "no fire near it to begin with")
	var camp := {"kind": "camp", "rect": Rect2i(cell + Vector2i(1, -2), Vector2i(3, 3)), "facing": Vector2i(0, 1)}
	_rig._terrain["buildings"] = buildings + [camp]
	_check(Level.camp_fire(camp) == cell + Vector2i(2, 0) and WetLook.near_fire(_rig, cell),
		"a camp whose fire ring is two cells off: by a fire")
	camp["rect"] = Rect2i(cell + Vector2i(2, -2), Vector2i(3, 3))
	_rig._terrain["buildings"] = buildings + [camp, {"kind": "hut"}]  # A building more: read again.
	_check(not WetLook.near_fire(_rig, cell), "its fire three cells off: not")
	if had_buildings:
		_rig._terrain["buildings"] = buildings
	else:
		_rig._terrain.erase("buildings")
	# A lit hearth (825, package "hill cave rest": World.lit_hearths, as the "hearths" message keeps
	# them) dries as a fire does, within FIRE_REACH; gone out, not.
	var zone_name: String = World.zone.name
	var hearths_had = World.hearths_lit.get(zone_name)
	World.hearths_lit[zone_name] = {cell + Vector2i(2, 2): World.tick + 100}
	var by_hearth := WetLook.near_fire(_rig, cell)
	World.hearths_lit[zone_name] = {cell + Vector2i(3, 0): World.tick + 100}
	var beyond := WetLook.near_fire(_rig, cell)
	World.hearths_lit[zone_name] = {cell + Vector2i(2, 2): World.tick}
	var gone_out := WetLook.near_fire(_rig, cell)
	if hearths_had == null:
		World.hearths_lit.erase(zone_name)
	else:
		World.hearths_lit[zone_name] = hearths_had
	_check(by_hearth and not beyond and not gone_out,
		"a hearth lit two cells off: by a fire; three off, or gone out: not (%s, %s, %s)" % [by_hearth, beyond, gone_out])
	# Rain: outdoors it wets all over and nothing dries; walled in, it wets nothing.
	if weather != null:
		var outdoor_was: bool = weather.outdoor
		var rain_was: float = weather.weather.get("rain", 0.0)
		weather.outdoor = true
		weather.weather["rain"] = 1.0
		var enclosed_had: bool = _rig._enclosed.has(cell)
		var enclosed_was = _rig._enclosed.get(cell)
		_rig._enclosed.erase(cell)
		puppet.set_meta("wet", 1.0)
		WetLook.soak(_rig, puppet, WetLook.RAIN_SOAK_SECONDS * 0.5)
		_check(absf(float(puppet.get_meta("wet_all")) - 0.5) < 0.01 and is_equal_approx(float(puppet.get_meta("wet")), 1.0),
			"in full rain: half soaked all over in half of RAIN_SOAK_SECONDS, the legs not drying (%.2f)" % float(puppet.get_meta("wet_all")))
		_rig._enclosed[cell] = 1
		_check(is_zero_approx(WetLook.rain_on(_rig, cell)), "walled in: no rain on it")
		_rig._enclosed.erase(cell)
		if enclosed_had:
			_rig._enclosed[cell] = enclosed_was
		weather.outdoor = outdoor_was
		weather.weather["rain"] = rain_was
	# The target's outline over a wet body: the wet overlay passes on to it, and back.
	puppet.set_meta("wet", 1.0)
	WetLook.show(_rig, puppet)
	_rig._show_outline(puppet, true)
	var over := (meshes[0] as MeshInstance3D).material_overlay
	_check(over is ShaderMaterial and (over as ShaderMaterial).shader == WetLook.SHADER and over.next_pass == _rig._outline,
		"outlined while wet: the wet overlay, then the outline")
	_rig._show_outline(puppet, false)
	_check((meshes[0] as MeshInstance3D).material_overlay == WetLook.material_of(puppet), "the outline off: the wet overlay alone again")
	dry.call()
	WetLook.show(_rig, puppet)
	var drips := puppet.get_node_or_null("WetDrips") as CPUParticles3D
	_check((meshes[0] as MeshInstance3D).material_overlay == null and not puppet.has_meta("wet_material")
			and (drips == null or not drips.emitting), "dried: no overlay, its material dropped, no drips")


## A sword swung at nothing (338 amended (3); Jeff on v0.1.198: "punching with a sword in my
## hand"): World.try_swing winds nothing up, and the slash's lead ran at the 3x cap; now it takes
## the sword's lead (windup_ticks, 2), as a blow wound up at someone does: its contact 0.2 s on.
func _test_sword_whiff() -> void:
	print("\n== a sword swung at nothing still takes its lead ==")
	var player := _player()
	var slots := player.slots
	while slots.size() < Items.CARRIED:
		slots.append("")
	var was := slots.duplicate()
	slots[Items.RIGHT_HAND] = "sword"
	slots[Items.LEFT_HAND] = ""
	player.slots = slots
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets[player.get_instance_id()]
	var rig := puppet.get_meta("rig") as AnimRig
	puppet.set_meta("wound_until", 0)
	var lead := World.windup_ticks(player) * World.TICK_DT
	_check(is_equal_approx(lead, 0.2), "the sword's lead 2 ticks (%.2f s)" % lead)
	var now := Time.get_ticks_msec()
	player.swung.emit(Vector2i(1, 0))
	var contact_in := (rig.contact_msec - now) / 1000.0
	_check(rig.striking() and rig.playing().begins_with("Sword_Slash") and absf(contact_in - lead) < 0.03,
		"swung at nothing: the slash lands its contact over the lead, not hurried to the cap (%s in %.2f s)" % [rig.playing(), contact_in])
	_check(rig.speed() < 1.2, "its lead near its natural pace (x%.2f)" % rig.speed())
	rig.cancel_strike()
	puppet.set_meta("busy_until", 0)
	player.slots = was
	_rig._process(0.0)


## Held weapons rest out of a fight (662 (b)): a two-hander calm a while (the times put back,
## not waited for) stands with its head down on the ground ahead, the left hand let go of grip_2;
## a blow seen near it, or a monster hunting within REST_ROUSED_CELLS, takes it up again (the
## ready stance, the left hand back); a spear grounded, a hammer hung; a sword sheathed
## (step (c), _test_sheathed).
func _test_rest() -> void:
	print("
== held weapons at rest (662 (b)) ==")
	var player := _player()
	var slots := player.slots
	while slots.size() < Items.CARRIED:
		slots.append("")
	var was := slots.duplicate()
	player.raised = ""
	var id := player.get_instance_id()
	for kind: String in ["giant_axe", "spear", "hammer", "sword"]:
		slots[Items.RIGHT_HAND] = kind
		slots[Items.LEFT_HAND] = ""
		player.slots = slots
		_rig._process(0.0)
		var puppet: Node3D = _rig._puppets[id]
		var rig := puppet.get_meta("rig") as AnimRig
		var sockets: Dictionary = puppet.get_meta("sockets")
		_check(rig.upper_clip() != str(Client3D.RESTS.get(kind, {}).get("upper", "-")), "%s just taken up: not at rest (%s)" % [kind, rig.upper_clip()])
		var now := Time.get_ticks_msec()
		puppet.set_meta("roused_at", now - 60000)
		puppet.set_meta("stood_at", now - 60000)
		_rig._combat_at.erase(id)
		# No fidget meanwhile: at rest the left hand is off the haft, so one may start (the
		# wall clock past its fidget_at under a loaded suite), and the rouse below sees its base
		# clip, not Idle, so no ready stance till the next frame (the flake, 750 amended (2)).
		puppet.set_meta("fidget_at", now + 600000)
		puppet.set_meta("fidgeting", false)  # Nor one still playing: Idle from the next frame.
		puppet.set_meta("busy_until", 0)
		for i in 4:
			_rig._process(0.0)
			await get_tree().process_frame
		if Client3D.SHEATHS.has(kind):
			_check(str(puppet.get_meta("bow_state")) in ["sheathing", "sheathed"] and rig.upper_clip() in ["Sheathe", ""],
				"%s calm a while: sheathing, not at rest in hand (_test_sheathed) (%s)" % [kind, puppet.get_meta("bow_state")])
			continue
		var held := (sockets["hand_r"] as Node3D).get_node("Held") as Node3D
		if not Client3D.RESTS.has(kind):
			_check(rig.upper_clip() == "" and held.position == Vector3.ZERO, "%s: no rest of its own yet, in hand as held (%s)" % [kind, rig.upper_clip()])
			continue
		var low := INF
		for mesh: MeshInstance3D in held.find_children("*", "MeshInstance3D", true, false):
			for s in mesh.mesh.get_surface_count():
				for v: Vector3 in mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
					low = minf(low, (mesh.global_transform * v).y)
		low -= puppet.global_position.y
		_check(rig.upper_clip() == str(Client3D.RESTS[kind]["upper"]), "%s calm a while: at rest (%s)" % [kind, rig.upper_clip()])
		if kind != "hammer":
			_check(absf(low) < 0.15, "%s at rest: its end on the ground (%.2f m)" % [kind, low])
		else:
			_check(low > 0.05, "%s hung: its head off the ground (%.2f m)" % [kind, low])
		if kind == "giant_axe":
			var reach := puppet.get_meta("reach") as HandReach
			_check(not reach.active and rig.base_clip() == Client3D.CLIP_IDLE, "the axe at rest: the left hand let go of grip_2, standing idle (%s)" % rig.base_clip())
			_rig._combat_at[id] = Time.get_ticks_msec()
			_rig._process(0.0)
			_check(rig.upper_clip() == "Axe_Ready" and reach.active and held.position.is_equal_approx(held.basis * -(held.get_meta("grip") as Vector3)),
				"a blow seen near it: taken up, ready, both hands on it, at its grip (%s)" % rig.upper_clip())
			_rig._combat_at.erase(id)
			puppet.set_meta("roused_at", Time.get_ticks_msec() - 60000)
			_rig._process(0.0)
			_check(rig.upper_clip() == "Haft_Rest", "calm again: at rest (%s)" % rig.upper_clip())
			var free := Vector2i(-1, -1)
			for dx in range(-5, 6):
				for dy in range(-5, 6):
					var t := player.tile + Vector2i(dx, dy)
					if free == Vector2i(-1, -1) and absi(dx) + absi(dy) >= 2 and World.is_free(t) 							and Vector2(t).distance_to(Vector2(player.tile)) <= Client3D.REST_ROUSED_CELLS - 1.0:
						free = t
			var imp := _spawn_imp(free)
			imp.alert = Monster.Alert.HUNTING
			_rig._process(0.0)  # Its puppet made.
			puppet.set_meta("roused_look_at", 0)
			_rig._process(0.0)
			_check(rig.upper_clip() == "Axe_Ready", "a monster hunting %.1f cells off: taken up (%s)" % [Vector2(free).distance_to(Vector2(player.tile)), rig.upper_clip()])
			imp.alert = Monster.Alert.IDLE  # (Its puppet outlives it a frame.)
			World.despawn(imp)
			puppet.set_meta("roused_look_at", 0)  # Looked for again at once: nothing hunting now.
	(_rig._puppets[id] as Node3D).set_meta("fidget_at", Time.get_ticks_msec())  # Fidgets as before.
	player.slots = was
	_rig._process(0.0)


func _test_bow_back() -> void:
	print("
== the bow on the back out of a fight (662 amended (d)) ==")
	var player := _player()
	var slots := player.slots
	while slots.size() < Items.CARRIED:
		slots.append("")
	var was := slots.duplicate()
	slots[Items.RIGHT_HAND] = "bow"
	slots[Items.LEFT_HAND] = "arrows"
	player.slots = slots
	player.raised = ""
	var id := player.get_instance_id()
	# Standing, whatever the tests before left: _sync_bow reads the base clip the frame before chose, and a
	# gait still on it read "carry" under load (environment's runs): a walk's speed easing off, or the
	# shuffle of a turn where it stands (the pick's test turns the player to its seam and back; "base Walk,
	# 0.00 m/s"), both on the wall clock.
	var standing: Node3D = _rig._puppets[id]
	standing.set_meta("shuffle_until", 0)
	standing.set_meta("turning", false)
	standing.set_meta("turned_ms", -1)  # The turn's next frame snaps to the facing (_standing_turn).
	standing.set_meta("busy_until", 0)
	standing.set_meta("speed", 0.0)
	standing.set_meta("last_at", standing.position)
	standing.set_meta("last_ms", Time.get_ticks_msec())
	_rig._process(0.0)
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets[id]
	var sockets: Dictionary = puppet.get_meta("sockets")
	var rig := puppet.get_meta("rig") as AnimRig
	var hand := sockets["hand_l"] as Node3D
	var back := sockets["sling"] as Node3D
	var fit := Client3D.sling_fit(sockets)
	_check(not fit.is_empty() and Client3D._quiver_of(sockets).get_parent() == back, "a human's quiver on the sling, the bow in hand or not")
	_check(hand.has_node("Held") and puppet.get_meta("bow_state") == "idle", "just taken up: the bow in hand (%s; base %s, %.2f m/s)" % [puppet.get_meta("bow_state"), rig.base_clip(), float(puppet.get_meta("speed", 0.0))])
	puppet.set_meta("roused_at", Time.get_ticks_msec() - 60000)
	_rig._combat_at.erase(id)
	_rig._process(0.0)
	var quiver := back.get_node("Quiver") as Node3D
	_check(not hand.has_node("Held") and back.has_node("StowedBow") and rig.upper_clip() == "",
		"calm a while: the bow slung, the hands free (%s)" % rig.upper_clip())
	var own_shown := func() -> int:
		var shown := 0
		var bow_now := (back.get_node_or_null("StowedBow") if back.has_node("StowedBow") else hand.get_node_or_null("Held")) as Node3D
		for string: MeshInstance3D in bow_now.find_children("*string*", "MeshInstance3D", true, false):
			shown += 1 if string.visible else 0
		return shown
	_check(back.has_node("SlingString") and own_shown.call() == 0 and quiver.position.distance_to((fit["quiver"] as Transform3D).origin) < 0.1,
		"slung: its string drawn over the chest, its own hidden, the quiver on the back as fitted (within 10 cm, riding the body: a draw pulls the right shoulder back under its mouth)")
	_check(Client3D.in_hand(puppet) == ["", ""] and Client3D.fidget_with("Fidget_Shoulders", Client3D.in_hand(puppet)),
		"both hands empty to the fidgets (the arrows in the quiver): every fidget again")
	rig.loop(str((puppet.get_meta("gaits") as Array)[1][0]))
	_rig._sync_bow(player, puppet)
	_check(back.has_node("StowedBow") and rig.upper_clip() == "", "running calm: still on the back")
	rig.loop(Client3D.CLIP_IDLE)
	player.raised = "draw"
	player.raised_tick = World.tick
	_rig._process(0.0)
	_check(hand.has_node("Held") and not back.has_node("StowedBow") and rig.upper_clip() == "Bow_Draw",
		"a draw: in hand at once, drawing (%s)" % rig.upper_clip())
	_check(not back.has_node("SlingString") and own_shown.call() > 0 and quiver.get_parent() == back and quiver.position.distance_to((fit["quiver"] as Transform3D).origin) < 0.1,
		"in hand: the drawn string gone, its own shown, the quiver kept on the sling as fitted (%s, %d shown, %.3f off)" % [back.has_node("SlingString"), own_shown.call(), quiver.position.distance_to((fit["quiver"] as Transform3D).origin)])
	player.raised = ""
	_rig._process(0.0)
	_check(hand.has_node("Held"), "let go: still in hand, roused")
	puppet.set_meta("roused_at", Time.get_ticks_msec() - 60000)
	_rig._combat_at.erase(id)
	_rig._process(0.0)
	_check(back.has_node("StowedBow"), "calm again: on the back")
	_rig._combat_at[id] = Time.get_ticks_msec()
	_rig._process(0.0)
	_check(hand.has_node("Held") and rig.upper_clip() == "Bow_Idle", "a blow seen near: in hand (%s)" % rig.upper_clip())
	puppet.set_meta("roused_at", Time.get_ticks_msec() - 60000)
	_rig._combat_at.erase(id)
	_rig._process(0.0)
	slots[Items.RIGHT_HAND] = ""
	player.slots = slots
	_rig._process(0.0)
	_check(not back.has_node("StowedBow") and not back.has_node("SlingString") and Client3D._quiver_of(sockets) == null,
		"put away while slung: gone from the back, its string and the quiver with it")
	player.slots = was
	_rig._process(0.0)


## The blades sheathed and the shield on the back out of a fight (662 (c)): a sword and a
## shield taken up, in hand, the sheath empty at the hip; calm a while (the times put back), the
## Sheathe clip, the blade still in hand till the hand meets the sheath (SHEATHE_CONTACT), then the
## sword in its sheath and the shield on the back, and once the clip ends the upper layer off and
## both hands free to the fidgets; a blow seen near, the Draw clip, back in hand at DRAW_GRIP; a
## raised guard during either clip cuts it at once with both in hand (the coordinator's guard);
## the sword let go while sheathed, the sheath gone with it and the shield's back socket emptied.
func _test_sheathed() -> void:
	print("== the blade at the hip, the shield on the back (662 (c)) ==")
	var player := _player()
	var slots := player.slots
	while slots.size() < Items.CARRIED:
		slots.append("")
	var was := slots.duplicate()
	slots[Items.RIGHT_HAND] = "sword"
	slots[Items.LEFT_HAND] = "shield"
	player.slots = slots
	player.raised = ""
	var id := player.get_instance_id()
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets[id]
	var sockets: Dictionary = puppet.get_meta("sockets")
	var rig := puppet.get_meta("rig") as AnimRig
	var hand := sockets["hand_r"] as Node3D
	var arm := sockets["arm_l"] as Node3D
	var back := sockets["back"] as Node3D
	var sheath := (sockets["hip_l"] as Node3D).get_node_or_null("Sheath") as Node3D
	_check(sheath != null and hand.has_node("Held") and arm.has_node("Held") and not sheath.has_node("Sheathed"),
		"just taken up: the sword in hand, its scabbard empty at the hip, the shield on the arm")
	var calm := func() -> void:
		player.raised = ""
		puppet.set_meta("roused_at", Time.get_ticks_msec() - 60000)
		_rig._combat_at.erase(id)
	var since := func(ms: int) -> void:
		puppet.set_meta("sheathe_at", Time.get_ticks_msec() - ms)
		_rig._process(0.0)
	calm.call()
	_rig._process(0.0)
	_check(puppet.get_meta("bow_state") == "sheathing" and rig.upper_clip() == "Sheathe" and hand.has_node("Held") and not sheath.has_node("Sheathed"),
		"calm a while: the Sheathe clip, the sword still in hand (%s, %s)" % [puppet.get_meta("bow_state"), rig.upper_clip()])
	since.call(300)
	player.raised = "block"
	_rig._process(0.0)
	_check(hand.has_node("Held") and arm.has_node("Held") and not sheath.has_node("Sheathed") and rig.upper_clip() == "Block_Idle",
		"the guard raised mid-sheathe: cut at once, both in hand, guarding (%s)" % rig.upper_clip())
	calm.call()
	_rig._process(0.0)
	since.call(int(Client3D.SHEATHE_CONTACT * 1000.0) + 50)
	_check(sheath.has_node("Sheathed") and not hand.has_node("Held") and back.has_node("StowedShield") and not arm.has_node("Held")
		and rig.upper_clip() == "Sheathe", "the hand at the sheath: the sword in it, the shield on the back, the clip playing on")
	since.call(3000)
	_check(sheath.has_node("Sheathed") and back.has_node("StowedShield") and rig.upper_clip() == "" and puppet.get_meta("bow_state") == "sheathed",
		"the clip done: sheathed, the upper layer off (%s)" % puppet.get_meta("bow_state"))
	_check(Client3D.in_hand(puppet) == ["", ""] and Client3D.fidget_with("Fidget_Shoulders", Client3D.in_hand(puppet)),
		"both hands free to the fidgets: every fidget again")
	_rig._combat_at[id] = Time.get_ticks_msec()
	_rig._process(0.0)
	_check(puppet.get_meta("bow_state") == "drawing" and rig.upper_clip() == "Draw" and sheath.has_node("Sheathed"),
		"a blow seen near: the Draw clip, the sword still sheathed (%s, %s)" % [puppet.get_meta("bow_state"), rig.upper_clip()])
	since.call(int(Client3D.DRAW_GRIP * 1000.0) + 50)
	_check(hand.has_node("Held") and arm.has_node("Held") and not sheath.has_node("Sheathed") and rig.upper_clip() == "Draw",
		"at the grip: the sword in hand, the shield on the arm, the clip playing on")
	since.call(3000)
	_check(rig.upper_clip() != "Draw" and str(puppet.get_meta("bow_state")) not in ["drawing", "sheathed"], "the clip done: as held (%s)" % puppet.get_meta("bow_state"))
	calm.call()
	_rig._process(0.0)
	since.call(3000)
	_rig._combat_at[id] = Time.get_ticks_msec()
	_rig._process(0.0)
	player.raised = "block"
	_rig._process(0.0)
	_check(hand.has_node("Held") and arm.has_node("Held") and not sheath.has_node("Sheathed") and not back.has_node("StowedShield")
		and rig.upper_clip() == "Block_Idle", "the guard raised mid-draw: cut at once, both in hand, guarding (%s)" % rig.upper_clip())
	calm.call()
	_rig._process(0.0)
	since.call(3000)
	_check(sheath.has_node("Sheathed") and back.has_node("StowedShield"), "calm again: put away")
	slots[Items.RIGHT_HAND] = "dagger"
	slots[Items.LEFT_HAND] = ""
	player.slots = slots
	_rig._process(0.0)
	var dagger_sheath := (sockets["hip_l"] as Node3D).get_node_or_null("Sheath") as Node3D
	_check(not back.has_node("StowedShield") and hand.has_node("Held") and dagger_sheath != null and dagger_sheath != sheath
		and not dagger_sheath.has_node("Sheathed"), "the sword and shield let go while put away: gone; a dagger in hand, its own sheath empty")
	slots[Items.RIGHT_HAND] = "spear"
	player.slots = slots
	_rig._process(0.0)
	_check((sockets["hip_l"] as Node3D).get_children().all(func(n: Node) -> bool: return n.is_queued_for_deletion()), "a spear: no sheath at the hip")
	player.slots = was
	_rig._process(0.0)


func _test_bow() -> void:
	print("
== the bow (decision 462): held left, drawn, held at full draw, loosed; the shield's guard ==")
	var player := _player()
	var slots := player.slots
	while slots.size() < Items.CARRIED:
		slots.append("")
	var was := slots.duplicate()
	slots[Items.RIGHT_HAND] = "bow"
	slots[Items.LEFT_HAND] = "arrows"
	player.slots = slots
	player.raised = ""
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets[player.get_instance_id()]
	var sockets: Dictionary = puppet.get_meta("sockets")
	var rig := puppet.get_meta("rig") as AnimRig
	var bow := (sockets["hand_l"] as Node3D).get_node_or_null("Held")
	var bundle := (sockets["hand_r"] as Node3D).get_node_or_null("Held")
	var quiver := Client3D._quiver_of(sockets)
	_check(bow != null and Client3D.held_ids(player) == ["arrows", "bow"],
			"a bow in the right hand's slot is drawn in the left")
	_check(bundle == null and quiver != null, "its arrows not in the right hand but in a quiver on the back (462 amended (3))")
	_check(rig.upper_clip() == "Bow_Idle", "a bow in hand: Bow_Idle (%s)" % rig.upper_clip())
	# Walking or running: no upper layer, both arms swinging with the gait.
	rig.loop(str((puppet.get_meta("gaits") as Array)[1][0]))
	_rig._sync_bow(player, puppet)
	_check(rig.upper_clip() == "" and puppet.get_meta("bow_state") == "carry", "running with the bow down: the arms swing with the gait (%s over %s)" % [rig.upper_clip(), rig.base_clip()])
	rig.loop(Client3D.CLIP_IDLE)
	_rig._sync_bow(player, puppet)
	_check(rig.upper_clip() == "Bow_Idle", "standing again: Bow_Idle (%s)" % rig.upper_clip())
	var string := bow.find_child("string", true, false) as Node3D
	var segments: Array = string.get_meta("segments", []) if string != null else []
	_check(segments.size() == 2 and string.get_children().all(func(n: Node) -> bool: return not (n is MeshInstance3D and (n as MeshInstance3D).visible)),
			"the string drawn as two segments, the art's straight box hidden")
	# The pose is scrubbed by the draw (bow_pull), carried on between ticks by
	# World.tick_alpha: held at a tick's start here, so the check doesn't hang
	# on where in a tick the test happens to run.
	var alpha_was := World.tick_alpha
	World.tick_alpha = 0.0
	player.raised = "draw"
	player.raised_tick = World.tick
	_rig._process(0.0)
	_check(rig.upper_clip() == "Bow_Draw" and rig.upper_position() < 0.01,
			"drawing: Bow_Draw from the nock (%s, %.2f)" % [rig.upper_clip(), rig.upper_position()])
	World.tick_alpha = alpha_was
	var on_string := bow.find_child("Nocked", true, false) as Node3D
	_check((on_string != null and on_string.is_visible_in_tree()) or not ArtKit.has("fx.arrow"),
			"an arrow on the string, shown (Jeff: \"the arrow doesn't load into the bow with drawing\")")
	# Scrubbed by the sim's draw (bow_pull): the nock by the ticks to draw_min,
	# then the pull by draw_of (from draw_min's 3 ticks to the bow's draw_full,
	# decision 669).
	var alpha := World.tick_alpha
	World.tick_alpha = 0.0
	var length := rig.length("Bow_Draw")
	var poses := []
	for drawn: int in [2, 6, 9]:
		player.raised_tick = World.tick - drawn
		_rig._process(0.0)
		poses.append(rig.upper_position() / length)
	World.tick_alpha = alpha
	var full := float(Items.verb_of("bow")["draw_full"])  # 10 ticks since 669 amended (2).
	var expected := [Client3D.BOW_NOCK_END * 2.0 / 3.0, Client3D.BOW_NOCK_END + (1.0 - Client3D.BOW_NOCK_END) * 3.0 / (full - 3.0),
			Client3D.BOW_NOCK_END + (1.0 - Client3D.BOW_NOCK_END) * 6.0 / (full - 3.0)]
	_check(range(3).all(func(i: int) -> bool: return absf(poses[i] - expected[i]) < 0.02) and rig.upper_speed() == 0.0,
			"the pose scrubbed by the draw: nocking before draw_min, then drawn back as draw_of grows (%s of the clip, expected %s)" % [poses, expected])
	player.raised_tick = World.tick - 20
	_rig._process(0.0)
	_check(rig.upper_clip() == "Bow_Hold", "at full draw: Bow_Hold (%s)" % rig.upper_clip())
	if segments.size() == 2:
		# Bent: both segments meet at the nock, drawn back of the brace.
		var rest: Vector3 = string.get_meta("rest")
		var tips: Array = string.get_meta("tips")
		var bend := float(string.get_meta("bent", 0.0))
		var reach := maxf(absf((tips[0] as Vector3).y), absf((tips[1] as Vector3).y))
		var ends := range(2).map(func(i: int) -> float:
			var seg := segments[i] as MeshInstance3D
			return (seg.position - seg.basis.y * 0.5).distance_to(string.position) + (seg.position + seg.basis.y * 0.5).distance_to(Client3D.bent(tips[i], bend, reach)))
		_check(float(string.get_meta("pulled", 0.0)) > 0.0 and string.position.z < rest.z and ends.all(func(d: float) -> bool: return d < 0.001),
				"drawn: the string bent at the nock, back toward the hand (%.3f m), its two segments from the bent tips to the nock (%s)" % [string.get_meta("pulled", 0.0), ends])
		# The limbs (462 amended (4)): bent toward the string, the tips furthest, the grip not at all
		# (each limb's moving vertices, as bent places them: the headless renderer keeps no buffer).
		var limbs: Array = string.get_meta("limbs", [])
		var moved := []
		for limb: Array in limbs:
			var moving: PackedInt32Array = limb[5]
			var points: PackedVector3Array = limb[6]
			var squares: PackedFloat32Array = limb[7]
			var most := 0.0
			for k in moving.size():
				most = maxf(most, bend * squares[k])
			moved.append([moving.size(), points.size(), most])
		_check(bend > 0.04 and not limbs.is_empty() and moved.all(func(m: Array) -> bool: return m[0] > 0 and m[0] < m[1] and m[2] > 0.9 * bend)
				and Client3D.bent(Vector3(0.0, 0.05, 0.0), bend, reach) == Vector3(0.0, 0.05, 0.0)
				and is_equal_approx(Client3D.bent(Vector3(0.0, reach, 0.0), bend, reach).z, -bend),
				"drawn: the limbs bent %.3f m at the tips, the grip still ([moving, of, at most] %s)" % [bend, moved])
	player.shot.emit(Vector2(player.tile + Vector2i(4, 0)), &"ground")
	player.raised = ""
	_rig._process(0.0)
	_check(rig.upper_clip() == "Bow_Loose", "loosed: Bow_Loose (%s)" % rig.upper_clip())
	# Drawn, the body turns to ui's aim (583), any angle; not drawn, its facing.
	var had_aim: Variant = _main.get("aim_drawn")
	if had_aim != null:
		player.raised = "draw"
		_main.set("aim_drawn", true)
		_main.set("aim_angle", 1.0)
		var aimed := _rig._aimed_yaw(player, 0.25)
		player.raised = ""
		var loose_yaw := _rig._aimed_yaw(player, 0.25)
		_main.set("aim_drawn", had_aim)
		_check(is_equal_approx(aimed, -1.0) and is_equal_approx(loose_yaw, 0.25),
				"drawn, the archer turns to the aim at any angle (%.2f), else its facing (%.2f)" % [aimed, loose_yaw])
	var nocked := bow.find_child("Nocked", true, false)
	_check((nocked == null or nocked.is_queued_for_deletion()) and (string == null or string.has_meta("loosed")),
			"loosed: the arrow gone from the string, the string springing back")
	# The spring: the brace in STRING_SNAP, a ring past it never more than
	# STRING_OVERSHOOT_MAX nor back of the draw, still by STRING_SETTLE (a function of
	# the time, so a long frame can't throw it further).
	var swing := []
	for ms in range(0, 600, 5):
		swing.append(Client3D.bow_string(0.5, ms / 1000.0))
	_check(absf(Client3D.bow_string(0.5, Client3D.STRING_SNAP)) < 0.001 and swing.max() > 0.01
			and swing.max() <= Client3D.STRING_OVERSHOOT_MAX + 0.0001 and swing.min() >= -0.5 and swing.slice(swing.size() - 30).all(func(z: float) -> bool: return z == 0.0),
			"the string's spring: at the brace by %.2f s, rings past it at most %.2f m (%.3f), still after %.1f s" % [
				Client3D.STRING_SNAP, Client3D.STRING_OVERSHOOT_MAX, swing.max(), Client3D.STRING_SETTLE])
	puppet.set_meta("bow_until", 0)
	_rig._process(0.0)
	_check(rig.upper_clip() == "Bow_Idle", "then Bow_Idle again")
	player.raised = "draw"
	player.raised_tick = World.tick
	_rig._process(0.0)
	player.raised = ""
	_rig._process(0.0)
	_check(rig.upper_clip() == "Bow_Idle", "a draw let go with no shot: back to Bow_Idle")
	slots[Items.RIGHT_HAND] = "sword"
	slots[Items.LEFT_HAND] = "shield"
	player.slots = slots
	player.raised = "block"
	_rig._process(0.0)
	_check(rig.upper_clip() == "Block_Idle", "a shield raised: the guard (%s)" % rig.upper_clip())
	# Raised in front of the body (451 amended (2), step 3; Jeff: "raising shield in front of body, not
	# sideways out"): its face to the front, its centre ahead of the chest, about its height.
	var guard_sockets: Dictionary = puppet.get_meta("sockets")
	var raised_shield := (guard_sockets["arm_l"] as Node3D).get_node_or_null("Held") as Node3D if guard_sockets.has("arm_l") else null
	_check(raised_shield != null, "the raised shield on the forearm")
	if raised_shield != null:
		rig.tree.advance(0.6)
		var skeleton := puppet.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var pose := func(bone: String) -> Transform3D:
			return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone))
		var arm_l := guard_sockets["arm_l"] as Node3D
		var placed: Transform3D = pose.call("LeftLowerArm") * arm_l.transform * raised_shield.transform
		var chest: Transform3D = pose.call("UpperChest")
		var front := skeleton.global_basis.z.normalized()  # the body's front (the glTF's +Z)
		var ahead := (placed.origin - chest.origin).dot(front) / skeleton.global_transform.basis.get_scale().y * float(puppet.get_meta("model_scale", 1.0))
		var up := placed.origin.y - chest.origin.y
		_check(placed.basis.z.normalized().dot(front) > 0.9 and ahead > 0.2 and absf(up) < 0.3,
				"the guard raises it in front: its face to the front (%.2f), %.2f m ahead of the chest, %.2f m above it" % [
				placed.basis.z.normalized().dot(front), ahead, up])
	player.raised = ""
	_rig._process(0.0)
	_check(rig.upper_clip() == "", "lowered, nothing on the upper layer (%s)" % rig.upper_clip())
	player.slots = was
	_rig._process(0.0)


func _test_goblin() -> void:
	print("\n== an imp is the goblin: a model that faces, walks, punches, flinches, is knocked about and dies ==")
	var player := _player()
	var imp := _spawn_imp(Vector2i(9, 4), "imp")
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets[imp.get_instance_id()]
	_check(puppet.get_node_or_null("Body/Model") != null and puppet.has_meta("rig"), "its puppet is the goblin model, animated")
	if not puppet.has_meta("rig"):
		return
	var animator := puppet.get_meta("rig") as AnimRig
	var clips := Array(animator.clips())
	_check([Client3D.CLIP_IDLE, Client3D.CLIP_WALK, Client3D.CLIP_ATTACK, Client3D.CLIP_HIT, Client3D.CLIP_DEATH,
			Client3D.CLIP_BACKPEDAL, Client3D.CLIP_IMPACT, Client3D.CLIP_ROLL, Client3D.CLIP_LAND,
			Client3D.CLIP_JOG, Client3D.CLIP_SPRINT, Client3D.CLIP_LOOK_ABOUT, Client3D.CLIP_TIRED].all(
			func(clip: String) -> bool: return clip in clips)
			and (Client3D.ATTACK_CLIPS + Client3D.HIT_CLIPS + Client3D.DEATH_CLIPS + Client3D.FIDGETS.keys()
				+ [Client3D.CLIP_SIT_DOWN, Client3D.CLIP_SITTING, Client3D.CLIP_SIT_UP]).all(
			func(clip: String) -> bool: return clip in clips), "with all its clips (%s)" % [clips])
	_check(animator.playing() == "Idle" or Client3D.FIDGETS.has(animator.playing()),
			"standing: Idle, or a fidget (%s)" % animator.playing())
	var bone_count := 0
	for skeleton in puppet.find_children("*", "Skeleton3D", true, false):
		bone_count = (skeleton as Skeleton3D).get_bone_count()
	_check(bone_count == 22, "on its 22-bone rig")
	for direction: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, -1)]:
		World.face(imp, direction)
		for i in 30:
			imp._process(0.05)
		_rig._process(0.0)
		# Its front, from the rig: the toes are ahead of the feet.
		var forward := _toes_ahead(puppet)
		var wanted := Vector2(direction).normalized()
		_check(forward.dot(wanted) > 0.9, "it faces %s: its toes point %s" % [direction, forward])
	var own_pace: float = puppet.get_meta("pace")
	puppet.set_meta("pace", 1.0)  # The gaits at GAITS' own paces; its own pace below.
	# Each speed held past GAIT_DWELL (869: a change between gaits waits till it has been wanted that
	# long), on the rigs' clock set by hand: read once, the clock on past the dwell, read again.
	AnimRig._clock_movie = 1
	AnimRig._clock_frame = Engine.get_process_frames()
	AnimRig._clock_msec = Time.get_ticks_msec()
	var held := func(speed: float, metres: float, ms: int) -> void:
		for read in 2:
			puppet.set_meta("speed", speed)
			puppet.set_meta("gait_speed", speed)
			puppet.set_meta("last_at", puppet.position - Vector3(metres, 0.0, 0.0))
			puppet.set_meta("last_ms", AnimRig._clock_msec - ms)
			_rig._animate(puppet)
			AnimRig._clock_msec += int(Client3D.GAIT_DWELL * 1000.0) + 50
	for pace: Array in [[0.7, Client3D.CLIP_WALK], [1.4, Client3D.CLIP_WALK], [2.5, Client3D.CLIP_JOG], [1.2, Client3D.CLIP_JOG],
			[0.9, Client3D.CLIP_WALK], [5.5, Client3D.CLIP_SPRINT], [4.0, Client3D.CLIP_SPRINT], [3.5, Client3D.CLIP_JOG]]:
		held.call(float(pace[0]), float(pace[0]), 1000)  # A second's walk.
		var own := 0.0
		for gait: Array in Client3D.GAITS:
			if gait[0] == animator.playing():
				own = gait[1]
		_check(animator.playing() == pace[1] and absf(animator.speed() * own - float(pace[0])) < 0.05,
				"moving %.1f tiles a second: %s, its feet at that pace (x%.2f)" % [pace[0], animator.playing(), animator.speed()])
	puppet.set_meta("pace", own_pace)
	held.call(0.7, 0.07, 100)
	_check(animator.playing() == Client3D.CLIP_WALK and absf(animator.speed() * Client3D.GAITS[0][1] * own_pace - 0.7) < 0.05,
			"at its own pace (x%.2f of the clip's, its legs longer or shorter): x%.2f" % [own_pace, animator.speed()])
	AnimRig._clock_movie = -1
	AnimRig._clock_frame = -1
	var blows := {}
	for i in 4:
		imp.swung.emit(Vector2i(1, 0))
		blows[animator.playing()] = true
		_check(animator.playing() in Client3D.ATTACK_CLIPS, "an attack: %s" % animator.playing())
	_check(blows.size() >= 2, "and not the same blow every time (%s)" % [blows.keys()])
	var blow := animator.playing()
	_rig._animate(puppet)
	_check(animator.playing() == blow, "played out, not cut off by walking")
	imp.struck.emit(1, &"attack")
	_check(animator.playing() in Client3D.HIT_CLIPS, "struck: %s" % animator.playing())
	await get_tree().create_timer(0.6).timeout
	var aimed := imp.tile + Vector2i(6, 0)
	imp.shot.emit(Vector2(aimed), &"body")
	var flying: Array = _rig._arrows.filter(func(arrow: Dictionary) -> bool: return arrow["end"] == aimed)
	var due := int(flying[0]["arrive"]) - Time.get_ticks_msec() if not flying.is_empty() else 0
	_check(due > 100 and due < 250, "an arrow shot six cells off gets there in its flight's time (%d ms)" % due)
	_rig._animate(puppet)
	var standing := animator.playing()
	_rig._arrows.append({"end": imp.tile, "arrive": Time.get_ticks_msec() + 300, "heard": false})
	imp.struck.emit(1, &"shot")
	_check(animator.playing() == standing, "shot: no flinch before the arrow arrives (%s)" % animator.playing())
	await get_tree().create_timer(0.45).timeout
	_check(animator.playing() in Client3D.HIT_CLIPS, "and it flinches as it does (%s)" % animator.playing())
	await get_tree().create_timer(0.6).timeout
	var was := (puppet.get_node("Body") as Node3D).rotation.y
	_push_imp(imp, Vector2i(1, 0))
	# The first frame that turns it, against the ease for that frame's own
	# length: a wall-clock wait let one slow frame bring it all the way round.
	var turn := await _first_turn(puppet)
	var yaw: float = turn[0]
	var eased := absf(angle_difference(was, PI)) * exp(-GridEntity.TURN_RATE * float(turn[1]))
	_check(animator.playing() == Client3D.CLIP_BACKPEDAL and absf(angle_difference(yaw, PI)) > 0.0
			and absf(absf(angle_difference(yaw, PI)) - eased) <= 0.1 * eased + 0.001,
			"pushed back (+x): it backpedals, turning (not snapping) toward whence it came (-x), yaw %.2f from %.2f (%.2f expected after a %.0f ms frame)"
			% [yaw, was, PI - eased, float(turn[1]) * 1000.0])
	await _run_clock(0.3)
	yaw = await _yaw_settles((puppet.get_node("Body") as Node3D), PI, 0.05)
	_check(absf(angle_difference(yaw, PI)) < 0.05, "and comes round to face it, yaw %.2f" % yaw)
	_check(animator.playing() == Client3D.CLIP_IMPACT,
			"there, hit nothing, it doubles over all the same, still facing it (%s)" % animator.playing())
	await _run_clock(Client3D.KNOCK_MIN_SECONDS + 0.8)
	_check(not puppet.has_meta("knock") and animator.playing() == Client3D.CLIP_IDLE, "come to rest: Idle again (%s)" % animator.playing())
	yaw = await _yaw_settles((puppet.get_node("Body") as Node3D), was, 0.05)
	_check(absf(angle_difference(yaw, was)) < 0.05, "and turned back to its own facing, yaw %.2f" % yaw)
	_push_imp(imp, Vector2i(1, 0))
	await _run_clock(0.05)
	_check(animator.playing() == Client3D.CLIP_BACKPEDAL, "pushed back again: it backpedals")
	await _run_clock(0.15)
	_step_imp(imp, Vector2i(-1, 0))
	# A host draws its bodies GridEntity.HOST_DRAW_DELAY_TICKS behind (350 amended (1)): the step back,
	# queued behind the push's slide, is drawn from 0.3 s after the push, the moment this check once
	# read at (0.1 s after the step); whether that frame had begun it was the machine's (npc's landing,
	# 11-12). Waited on, not timed: the step drawn, the knock over within a tick of it, then read
	# mid-step.
	var drawn := await _run_until(func() -> bool: return imp.stepping, 0.2 + 2.0 * GridEntity.HOST_DRAW_DELAY_TICKS / World.TICK_RATE)
	var over := await _run_until(func() -> bool: return not puppet.has_meta("knock"), 1.0)
	_check(drawn >= 0.0 and over >= 0.0 and over <= 1.0 / World.TICK_RATE,
			"stepping back: drawn %.2f s after its step (a host draws %.1f tick behind), the knock over %.2f s after that (a tick at most)"
			% [drawn, GridEntity.HOST_DRAW_DELAY_TICKS, over])
	await _run_clock(0.05)
	yaw = await _yaw_settles((puppet.get_node("Body") as Node3D), PI, 0.3)
	_check(not puppet.has_meta("knock") and Client3D.is_gait(animator.playing()) and absf(angle_difference(yaw, PI)) < 0.3,
			"walking straight back: the knock is over and it walks back facing the way it goes, not backpedals (%s, yaw %.2f)" % [animator.playing(), yaw])
	await _run_clock(1.0)
	# As a client that never drew the slide: the body is just there.
	var from := imp.tile
	World._relocate(imp, from + Vector2i(1, 0))
	imp._world_slide_from(from, World.tick - 5, 1)
	imp._world_pushed(1, false, false, from, World.tick - 5, 1, 0)
	await _run_clock(0.1)
	_check(animator.playing() == Client3D.CLIP_BACKPEDAL, "a push whose slide never showed: it still backpedals where it stands (%s)" % animator.playing())
	await _run_clock(0.3)
	yaw = await _yaw_settles((puppet.get_node("Body") as Node3D), PI, 0.05)
	_check(absf(angle_difference(yaw, PI)) < 0.05, "facing whence it came, from what the sim says, yaw %.2f" % yaw)
	await _run_clock(1.0)
	_push_imp(imp, Vector2i(0, 1))
	imp.impacted.emit(2, &"stone")
	await _run_clock(0.05)
	_check(animator.playing() == Client3D.CLIP_BACKPEDAL, "pushed into a wall: it backpedals there first (%s)" % animator.playing())
	await _run_clock(0.25)
	_check(animator.playing() == Client3D.CLIP_IMPACT, "and doubles over when it gets there (%s)" % animator.playing())
	await _run_clock(1.0)
	imp.impacted.emit(1, &"wood")
	_check(animator.playing() == Client3D.CLIP_IMPACT, "shoved against a door where it stands: doubles over at once")
	await _run_clock(1.0)
	_push_imp(imp, Vector2i(0, -2), true)
	await _run_clock(0.3)
	var rolled := animator.playing() == Client3D.CLIP_ROLL and animator.speed() < 0.0
	var roll_speed := animator.speed()
	yaw = await _yaw_settles((puppet.get_node("Body") as Node3D), -Vector2(0, 1).angle(), 0.05)
	_check(rolled and absf(angle_difference(yaw, -Vector2(0, 1).angle())) < 0.05,
			"tossed (-z): it rolls over backwards, facing whence it came (+z), yaw %.2f, speed %.2f" % [yaw, roll_speed])
	var roll := animator.length(Client3D.CLIP_ROLL) / ArtKit.feel("client3d.roll_speed", Client3D.ROLL_SPEED)
	await _run_clock(roll)
	_check(animator.playing() == Client3D.CLIP_LAND, "then lands (%s)" % animator.playing())
	await _run_clock(1.4)
	World.damage(imp, 999, player, &"attack")
	_rig._process(0.0)
	_check(puppet.has_meta("corpse") and animator.playing() in Client3D.DEATH_CLIPS, "killed: %s" % animator.playing())
	await get_tree().create_timer(Client3D.FALL_SECONDS + 0.15).timeout
	_check(is_instance_valid(puppet) and is_zero_approx(puppet.rotation.z), "it plays its death rather than tipping over")
	_check(Client3D.model_for(_spawn_imp(Vector2i(10, 4))).is_empty(), "a monster of no kind with a model is still a capsule")
	# The hit and death sounds finish before the test does.
	await get_tree().create_timer(1.5).timeout


## Pushes [param imp] [param by] tiles as the sim does: there at once, its
## slide from where it was, and the push's message.
func _push_imp(imp: GridEntity, by: Vector2i, toss := false) -> void:
	var from := imp.tile
	World._relocate(imp, from + by)
	var tiles := maxi(absi(by.x), absi(by.y))
	imp._world_slide_from(from, World.tick + World.tick_alpha, World.push_slide_ticks(tiles))
	imp._world_pushed(tiles, false, toss, from, World.tick + World.tick_alpha, World.push_slide_ticks(tiles), 0)


## [param imp] takes a step of its own, [param by].
func _step_imp(imp: GridEntity, by: Vector2i) -> void:
	var from := imp.tile
	World._relocate(imp, from + by)
	imp._world_slide_from(from, World.tick + World.tick_alpha, 3.0)


## Runs the drawing clock (the sim is stopped in this test) for
## [param seconds] of real frames.
func _run_clock(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		World.tick_alpha += get_process_delta_time() * World.TICK_RATE
		while World.tick_alpha >= 1.0:
			World.tick += 1
			World.tick_alpha -= 1.0


## Runs the drawing clock as _run_clock does, a frame at a time, until [param done] says so or
## [param cap] seconds have passed: the seconds it took (from the first frame), or -1.0 if it never did.
func _run_until(done: Callable, cap: float) -> float:
	var from := Time.get_ticks_msec()
	var until := from + int(cap * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		World.tick_alpha += get_process_delta_time() * World.TICK_RATE
		while World.tick_alpha >= 1.0:
			World.tick += 1
			World.tick_alpha -= 1.0
		if done.call():
			return (Time.get_ticks_msec() - from) / 1000.0
	return -1.0


## Waits on a turn's state, not the wall clock (a loaded machine eases a turn late: the tossed roll
## and the teeter read mid-turn and failed, passing on a rerun): a frame at a time, the drawing
## clock run as _run_clock does when [param clock], until [param body]'s yaw is within
## [param tolerance] of [param want] or [param cap] seconds have passed; its yaw then.
func _yaw_settles(body: Node3D, want: float, tolerance: float, cap := 3.0, clock := true) -> float:
	var until := Time.get_ticks_msec() + int(cap * 1000.0)
	while absf(angle_difference(body.rotation.y, want)) >= tolerance and Time.get_ticks_msec() < until:
		await get_tree().process_frame
		if clock:
			World.tick_alpha += get_process_delta_time() * World.TICK_RATE
			while World.tick_alpha >= 1.0:
				World.tick += 1
				World.tick_alpha -= 1.0
	return body.rotation.y


## Runs the drawing clock as _run_clock does, a frame at a time, until
## [param puppet]'s body turns (a second at most): [yaw, the delta of the
## frame that turned it]. process_frame comes before the frame's _process,
## so a turn is seen a frame after the one that made it.
func _first_turn(puppet: Node3D) -> Array:
	var body := puppet.get_node("Body") as Node3D
	var until := Time.get_ticks_msec() + 1000
	var before := body.rotation.y
	var delta := 0.0
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		var turned := [body.rotation.y, delta]
		delta = get_process_delta_time()
		World.tick_alpha += delta * World.TICK_RATE
		while World.tick_alpha >= 1.0:
			World.tick += 1
			World.tick_alpha -= 1.0
		if turned[0] != before:
			return turned
	return [body.rotation.y, 0.0]


func _test_settings() -> void:
	print("\n== hp_bars, master_volume and sfx_volume in settings.cfg, other lines kept ==")
	Net.apply_view_options({"hp_bars": "0", "master_volume": "0.5", "sfx_volume": "3", "colour_blind": "yes"})
	_check(not Net.hp_bars and is_equal_approx(Net.master_volume, 0.5) and is_equal_approx(Net.sfx_volume, 1.0),
			"read, volumes held to 0..1")
	var aa_was := Net.antialias
	Net.apply_view_options({"antialias": "FXAA"})
	_check(Net.antialias == "fxaa" and get_viewport().screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA, "antialias=FXAA read and applied")
	Net.apply_view_options({"antialias": "8x"})
	_check(Net.antialias == "fxaa", "an unknown antialias= keeps what it was")
	Net.set_antialias(aa_was, false)
	Net.apply_view_options({"hp_bars": "0", "master_volume": "0.5", "sfx_volume": "3", "colour_blind": "yes"})
	Sfx.apply_volumes()
	_check(is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.5)) and AudioServer.get_bus_index(Sfx.BUS) != -1,
			"the Master bus at half, an SFX bus made")
	var path: String = preload("res://tests/test_ports.gd").scratch_path("view_test.cfg")
	var saved := [Net._settings_override, Net.player_id]
	Net._settings_override = path
	Net.player_body = &"female"
	Net.save_settings("127.0.0.1", 17789, "", "Tester")
	var text := FileAccess.get_file_as_string(path)
	_check("hp_bars=0" in text and "master_volume=0.5" in text and "colour_blind=yes" in text,
			"a rewrite keeps the lines the game does not write itself")
	_check("body=female" in text and Net.tidy_body(Net._read_settings(path).get("body", "")) == &"female",
			"the body is written and read back (decision 388)")
	Net.player_body = &"male"
	DirAccess.remove_absolute(path)
	Net._settings_override = saved[0]
	Net.player_id = saved[1]
	Net.apply_view_options({})
	Sfx.apply_volumes()
	_check(Net.hp_bars and is_equal_approx(Net.master_volume, 0.5), "no line: bars on; a volume keeps what it had")
	Net.master_volume = 1.0
	Sfx.apply_volumes()


func _test_shadows_in_view() -> void:
	print("
== a light casts shadows only while its reach overlaps the ground in view ==")
	var near := OmniLight3D.new()
	near.omni_range = 4.5
	_rig._room.add_child(near)
	near.global_position = _rig._camera_target + Vector3(1.0, 1.3, 1.0)
	var edge := OmniLight3D.new()
	edge.omni_range = 4.5
	_rig._room.add_child(edge)
	var reach: float = _rig._view_reach()
	edge.global_position = _rig._camera_target + Vector3(reach + 4.0, 1.3, 0.0)
	var far := OmniLight3D.new()
	far.omni_range = 4.5
	_rig._room.add_child(far)
	far.global_position = _rig._camera_target + Vector3(reach + 40.0, 1.3, 0.0)
	for light in [near, edge, far]:
		_rig._cast_shadows(light)
	_check(near.shadow_enabled and edge.shadow_enabled and far.shadow_enabled, "each is on as it comes, until it is placed")
	_rig._update_shadows()
	_check(near.shadow_enabled, "one by the player casts shadows")
	_check(edge.shadow_enabled, "one off screen whose light reaches onto it does too (%.1f out)" % (reach + 4.0))
	_check(not far.shadow_enabled, "one far off does not")
	far.global_position = near.global_position
	_rig._shadow_checked = -INF
	_rig._update_shadows()
	_check(far.shadow_enabled, "and comes on once it is near (a carried lantern walking up)")
	for light in [near, edge, far]:
		light.free()
	_rig._shadow_checked = -INF
	_rig._update_shadows()
	_check(_rig._shadow_lights.all(func(light: Variant) -> bool: return is_instance_valid(light)),
			"lights gone are forgotten")


func _test_no_2d_under_3d() -> void:
	print("
== under the 3D view the 2D view is not drawn ==")
	_main._paint_level()
	_check(_main._walls.is_empty() and _main.ground.get_used_cells().is_empty(),
			"no 2D walls or floor tiles (%d, %d)" % [_main._walls.size(), _main.ground.get_used_cells().size()])


func _test_doors_swing() -> void:
	print("
== a door's leaf swings when it opens or shuts, and then nothing is done for it ==")
	var doors := World.get_doors()
	_check(not doors.is_empty(), "the test room has a door")
	if doors.is_empty():
		return
	var door: Door = doors[0]
	var hinge := _rig._doorways[door.key].get_node(Client3D.DOOR_LEAF) as Node3D
	for i in 30:
		_rig._process(0.05)
		await get_tree().process_frame
	_check(_rig._doors_due.is_empty() and not door.is_processing(), "at rest, no door is looked at, and the door sleeps (due %s, processing %s, doorways %s, doors %s)" % [_rig._doors_due.keys(), door.is_processing(), _rig._doorways.keys(), doors.map(func(d: Door) -> Vector3i: return d.key)])
	var was := door.open
	# No door sound (one plays only when its last state is known): quitting
	# while a sound plays holds its stream at exit.
	_rig._door_open.erase(door.key)
	door.open = not was
	_check(_rig._doors_due.has(door.key) and door.is_processing(), "it changes: it is looked at again, and swings")
	for i in 40:
		await get_tree().process_frame
		_rig._process(0.05)
	var target := PI * 0.5 if door.is_open() else 0.0
	_check(is_equal_approx(hinge.rotation.y, target), "its leaf has swung %s (%.2f)" % ["open" if door.is_open() else "shut", hinge.rotation.y])
	_check(_rig._doors_due.is_empty() and not door.is_processing(), "and once still, both rest again")
	_rig._door_open.erase(door.key)
	door.open = was
	for i in 40:
		await get_tree().process_frame
		_rig._process(0.05)


func _test_door_states() -> void:
	print("
== a door's art shows its state_<name> nodes in that state alone; with state_broken a broken door keeps its leaf, open ==")
	var doors := World.get_doors()
	if doors.is_empty():
		return
	var door: Door = doors[0]
	var doorway: Node3D = _rig._doorways[door.key]
	var hinge := doorway.get_node(Client3D.DOOR_LEAF) as Node3D
	var kept := {"open": door.open, "lock": door.lock, "hp": door.hp}
	_rig._door_open.erase(door.key)
	door.open = false
	door.hp = 0
	await _settle_doors()
	_check(not hinge.visible, "art with no state_broken (a fill, a grey box): a broken door's leaf is gone, as before")
	# Art of its own with states, as a dropped .glb's: a lock plate on the
	# frame, splintered boards on the leaf.
	var locked := Node3D.new()
	locked.name = "state_locked"
	doorway.get_node(^"Door/Body").add_child(locked)
	var broken := Node3D.new()
	broken.name = "state_broken"
	hinge.add_child(broken)
	_rig._door_states.erase(door.key)
	door.hp = door.max_hp
	door.lock = "test key"
	await _settle_doors()
	_check(door.state() == "locked" and locked.visible and not broken.visible, "locked: its lock plate shows, not the boards (%s)" % door.state())
	door.lock = ""
	await _settle_doors()
	_check(door.state() == "closed" and not locked.visible and not broken.visible, "closed: neither")
	door.hp = 0
	await _settle_doors()
	_check(door.state() == "broken" and hinge.visible and broken.visible and not locked.visible
			and is_equal_approx(hinge.rotation.y, PI * 0.5),
			"broken: the leaf stays, swung open, its boards splintered (leaf %s, %.2f)" % [hinge.visible, hinge.rotation.y])
	locked.free()
	broken.free()
	_rig._door_states.erase(door.key)
	_rig._door_open.erase(door.key)
	door.hp = kept["hp"]
	door.lock = kept["lock"]
	door.open = kept["open"]
	await _settle_doors()
	_check(hinge.visible, "mended: its leaf is back")


## A thing drawn as nothing (734 amended (7), "no chests in town": a town's
## depot, shop counter and locker, reached through their keepers): no body,
## no pick, and neither a click nor E opens it.
func _test_undrawn_puppet() -> void:
	print("
== a thing drawn as nothing: no body, no pick, never opened by hand (734 amended (7)) ==")
	var crate: GridEntity = null
	for entity in World.get_entities():
		if str(entity.spawn_spec.get("art", "")) == "prop.crate":
			crate = entity
			break
	_check(crate != null, "the test room has a crate to stand in")
	if crate == null:
		return
	var kept: Array[Callable] = []
	for connection: Dictionary in crate.get_signal_connection_list(&"impacted"):
		if (connection["callable"] as Callable).get_object() == _rig:
			kept.append(connection["callable"])
			crate.disconnect(&"impacted", connection["callable"])
	var art: Variant = crate.spawn_spec.get("art")
	crate.spawn_spec["art"] = Level.UNDRAWN_ART
	var puppet := _rig._make_puppet(crate)
	_check(Level.undrawn(crate) and Client3D.art_slot_for(crate) == "" and puppet.get_node_or_null("Body") == null
		and puppet.get_node_or_null("Pick") == null, "drawn as nothing: no body and nothing to pick")
	_check(not _main.opens_on_click(crate), "a click never opens it: its keeper is the way to it")
	puppet.free()
	_disconnect_rig(crate)
	crate.spawn_spec["art"] = art
	for callable in kept:
		crate.impacted.connect(callable)
	_check(not Level.undrawn(crate), "its own art back")


func _test_art_puppets() -> void:
	print("
== a crate is drawn as prop.crate's own art once it has some, else its tinted cube ==")
	var crate: GridEntity = null
	for entity in World.get_entities():
		if str(entity.spawn_spec.get("art", "")) == "prop.crate":
			crate = entity
			break
	_check(crate != null, "the test room has a crate, its spec naming its slot")
	if crate == null:
		return
	# Its own puppet's connections, set aside while test puppets are made for
	# it (each connects the crate's signals again), and put back after.
	var kept: Array[Callable] = []
	for signal_name: StringName in [&"impacted"]:
		for connection: Dictionary in crate.get_signal_connection_list(signal_name):
			if (connection["callable"] as Callable).get_object() == _rig:
				kept.append(connection["callable"])
				crate.disconnect(signal_name, connection["callable"])
	# The crate's own art hidden (its variant count cached at none), whatever the kit has by now.
	ArtKit._variants["prop.crate"] = 0
	var before := _rig._make_puppet(crate)
	_check(before.get_node("Body") is MeshInstance3D and Client3D.art_slot_for(crate) == "",
			"no art of its own yet: its cube, as before")
	before.free()
	_disconnect_rig(crate)
	# Art of its own, as a dropped .glb would be: the grey box, packed.
	ArtKit.show_placeholders = true
	var grey := ArtKit.instance("prop.crate")
	ArtKit.show_placeholders = false
	ArtKit.forget()
	for node in ArtKit._descendants(grey):
		if node != grey:
			node.owner = grey
	var scene := PackedScene.new()
	scene.pack(grey)
	grey.free()
	ArtKit._scenes[ArtKit.own_path("prop.crate")] = scene
	ArtKit._variants["prop.crate"] = 1
	var after := _rig._make_puppet(crate)
	var body := after.get_node("Body") as Node3D
	var drawn := body.get_child(0) as Node3D if body.get_child_count() > 0 else null
	var pick := (after.get_node("Pick").find_children("*", "CollisionShape3D", false, false)[0] as CollisionShape3D).shape as BoxShape3D
	_check(not body is MeshInstance3D and drawn != null and str(drawn.get_meta("slot", "")) == "prop.crate"
			and pick != null and pick.size.is_equal_approx(ArtKit.size("prop.crate")),
			"with art of its own: drawn as prop.crate, standing on its tile, picked by its size")
	after.free()
	_disconnect_rig(crate)
	for callable in kept:
		crate.impacted.connect(callable)
	ArtKit.forget("prop.crate")
	ArtKit._variants["prop.crate"] = 0
	_check(Client3D.art_slot_for(crate) == "", "and back to its cube when the art is gone")
	ArtKit.forget("prop.crate")


## Decision 660: a crossing's room built a builder a frame ends as the room
## built at once; a rebuild started mid-build stops the first, nothing of it
## left over.
func _test_phased_build() -> void:
	print("
== a room built over frames is the room built at once; a second rebuild mid-build ends the first cleanly ==")
	var castle := Level.load_level("castle")
	var terrain: Dictionary = castle["terrain"]
	# The scatter grows after, a step a frame, as the view comes near: not counted.
	var drawn := func() -> int:
		return _rig._room.find_children("*", "", true, false).filter(
				func(node: Node) -> bool: return not String(node.name).begins_with("Scatter_")).size()
	# The counted nodes by their parent's name and their own, each up to its
	# first "_" or "@", and class: a count that differs names what.
	var kinds := func() -> Dictionary:
		var out := {}
		for node: Node in _rig._room.find_children("*", "", true, false):
			if String(node.name).begins_with("Scatter_"):
				continue
			var kind := "%s/%s %s" % [String(node.get_parent().name).get_slice("_", 0).get_slice("@", 0),
				String(node.name).get_slice("_", 0).get_slice("@", 0), node.get_class()]
			out[kind] = int(out.get(kind, 0)) + 1
		return out
	# Each ground and cliff chunk's mesh by name (built in another order over
	# frames): its arrays, the ground's shade bytes from the CPU copy the
	# floor's shade writes (_ground_bytes), and how many vertices in all.
	var meshes := func() -> Dictionary:
		var out := {}
		var vertices := 0
		var starts: PackedInt32Array = _rig._chunk_byte_start
		for node: Node in _rig._room.find_children("*", "MeshInstance3D", true, false):
			var name := String(node.name)
			if not (name.begins_with("Ground_") or name.begins_with("Cliffs_")):
				continue
			var mesh: Mesh = (node as MeshInstance3D).mesh
			var arrays: Array = mesh.surface_get_arrays(0)
			vertices += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var i := _rig._ground_meshes.find(mesh)
			if i >= 0:
				arrays[Mesh.ARRAY_CUSTOM0] = null
				arrays.append(_rig._ground_bytes.slice(starts[i], starts[i + 1] if i + 1 < starts.size() else _rig._ground_bytes.size()))
			# By its path: a glimpse's own ground chunks share the room's names.
			out[str(_rig._room.get_path_to(node))] = arrays.hash()
		out["vertices"] = vertices
		return out
	var built := [0]
	var lifted := [{}]
	var count_built := func() -> void:
		built[0] += 1
		if _rig.ground_filling:  # Over frames: the chunks drawn when the card lifts.
			lifted[0] = meshes.call()
	_rig.room_built.connect(count_built)
	# Twice at once: the second without the first's warm-ups.
	_rig.rebuild(terrain, castle["centre"])
	_rig.rebuild(terrain, castle["centre"])
	await _frames(Client3D.WARM_FRAMES + 2)
	await _settled_room()
	var at_once: int = drawn.call()
	var at_once_kinds: Dictionary = kinds.call()
	var once: Dictionary = meshes.call()
	var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	built[0] = 0
	_rig.rebuild(terrain, castle["centre"], true)
	var phasing := _rig.building_room
	var frames: int = await _settled_room()
	_check(phasing and not _rig.building_room and not _rig.ground_filling and _rig._fill_jobs.is_empty()
			and frames >= 2 and built[0] == 1 and _rig._old_rooms.is_empty(),  # Over more than one frame: phases share a frame while the budget allows (660 amended (7)).
			"building over %d frames, then whole, told once (%d), the last room freed (phasing %s, building %s, filling %s, fill jobs %d, phases %d, old rooms %d)" % [
			frames, built[0], phasing, _rig.building_room, _rig.ground_filling, _rig._fill_jobs.size(), _rig._room_phases().size(), _rig._old_rooms.size()])
	await _frames(Client3D.WARM_FRAMES + 2)
	await _settled_room()
	_check(drawn.call() == at_once, "the same room as built at once (%d nodes, %d)" % [drawn.call(), at_once])
	if drawn.call() != at_once:
		# Under a suite's load once (2308, 2250, ui's landing 2026-10-27): which kinds differ.
		var now: Dictionary = kinds.call()
		for kind: String in now.merged(at_once_kinds):
			if now.get(kind, 0) != at_once_kinds.get(kind, 0):
				print("    %s: %d, at once %d" % [kind, now.get(kind, 0), at_once_kinds.get(kind, 0)])
	var phased: Dictionary = meshes.call()
	_check(once["vertices"] > 0 and phased == once, "each ground and cliff chunk the same mesh and shade as built at once (%d chunks, %d vertices)" % [
		once.size() - 1, once["vertices"]])
	# Terrain's review: a chunk drawn by the lift is drawn shaded, not at
	# full light till the last chunk is in (a pop in the dark).
	var seen := 0
	var same := true
	for name: String in lifted[0]:
		if name != "vertices":
			seen += 1
			same = same and lifted[0][name] == phased[name]
	_check(seen > 0 and same, "the %d chunks drawn when the card lifts already as shaded as at the end" % seen)
	built[0] = 0
	_rig.rebuild(terrain, castle["centre"], true)
	await _frames(2)
	var first_room: Node3D = _rig._room
	_rig.rebuild(terrain, castle["centre"], true)
	await _settled_room()
	await _frames(Client3D.WARM_FRAMES + 2)
	await _settled_room()
	_check(not is_instance_valid(first_room) and built[0] == 1 and drawn.call() == at_once,
			"a rebuild mid-build: the first's room gone, told once, the same room (%d nodes)" % drawn.call())
	_check(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) == orphans,
			"no orphan nodes left by the stopped build (%d, %d)" % [Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), orphans])
	# 650's far landmarks after a build over frames under the low camera
	# (pc-character's find, 11-11): under the new room, none freed, one set.
	var low_was := Net.camera_low
	Net.set_camera_low(true, false)
	_rig._apply_camera_mode()
	var wilds := Level.load_level("wilds")
	_rig.rebuild(wilds["terrain"], wilds["centre"], true)
	await _settled_room()
	await _frames(2)
	# Placed as the camera is, here and each frame since: a freed node in
	# the list errors (land.sh fails a scene on an ERROR line), so the next
	# such loop fails a landing, not 2,000 times in play.
	_rig._place_camera()
	var far_dead := _rig._far_marks.filter(func(mark: Dictionary) -> bool:
		return (not is_instance_valid(mark["node"]) or not _rig._room.is_ancestor_of(mark["node"]) or not (mark["node"] as Node3D).is_inside_tree()
			or (mark["node"] as Node3D).scale.x <= 0.0))
	var far_sets := _rig._room.find_children("FarLandmarks", "", true, false).size()
	_check(not _rig._far_marks.is_empty() and far_dead.is_empty() and far_sets == 1 and is_instance_valid(_rig._far_root)
			and _rig._room.is_ancestor_of(_rig._far_root) and is_instance_valid(_rig._skirt) and _rig._room.is_ancestor_of(_rig._skirt),
			"a build over frames under the low camera (a crossing): the far landmarks placed and the skirt made under the new room, none freed, one set, no error placing them (%d marks, %d dead, %d sets)" % [
			_rig._far_marks.size(), far_dead.size(), far_sets])
	Net.set_camera_low(low_was, false)
	_rig._apply_camera_mode()
	_rig.room_built.disconnect(count_built)
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## The room's build, its ground's fill, the last room's free and the
## border's canopy done (perf, release's ask: a frame cap and a fixed
## WARM_FRAMES wait both lost to a loaded machine, the fill and the canopy
## run on workers; terrain found the canopy): frames waited, up to
## SETTLE_MSEC of wall time.
const SETTLE_MSEC := 20000
func _settled_room() -> int:
	var started := Time.get_ticks_msec()
	var frames := 0
	while (_rig.building_room or _rig.ground_filling or not _rig._fill_jobs.is_empty() or not _rig._old_rooms.is_empty()) \
			and Time.get_ticks_msec() - started < SETTLE_MSEC:
		await get_tree().process_frame
		frames += 1
	if is_instance_valid(_rig._border):
		_rig._border.finish()  # Its canopy, worked out on a worker (terrain's finding).
	return frames


## The most frames a small indoor room's card may take to lift (660 amended (7)).
const INDOOR_LIFT_FRAMES := 16


## 660 amended (4): an indoor zone built over frames (no wooded land, no
## edge) is the room built at once. The curves' start once took the indoor
## case's empty set as a script error and the barrow never drew (black but
## the HUD, pc-character, 2026-10-30).
func _test_indoor_phased_build() -> void:
	print("
== an indoor zone built over frames is the room built at once ==")
	var barrow := Level.load_level("barrow")
	var terrain: Dictionary = barrow["terrain"]
	var drawn := func() -> int:
		return _rig._room.find_children("*", "", true, false).filter(
				func(node: Node) -> bool: return not String(node.name).begins_with("Scatter_")).size()
	_rig.rebuild(terrain, barrow["centre"])
	await _frames(Client3D.WARM_FRAMES + 2)
	var at_once: int = drawn.call()
	_rig.rebuild(terrain, barrow["centre"], true)
	var frames := 0
	var lifted := -1
	while (_rig.building_room or _rig.ground_filling) and frames < 400:
		await get_tree().process_frame
		frames += 1
		if lifted < 0 and not _rig.building_room:
			lifted = frames
	await _frames(Client3D.WARM_FRAMES + 2)
	_check(not _rig._outdoor and not _rig.building_room and not _rig.ground_filling and _rig._curves_task == -1,
			"the barrow built over %d frames, then whole" % frames)
	# 660 amended (7): a small room's phases share frames while the card's
	# budget allows (a frame each was 27 frames to the lift, 450 ms at 60 fps).
	_check(lifted > 0 and lifted <= INDOOR_LIFT_FRAMES, "the barrow's card lifts within %d frames (%d)" % [INDOOR_LIFT_FRAMES, lifted])
	_check(at_once > 0 and drawn.call() == at_once, "the same room as built at once (%d nodes, %d)" % [drawn.call(), at_once])
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## Decision 822 (P1, step 1): a held neighbour's view and the swap. Every
## Client3D var is sorted once into room_fields.gd's VIEW or ROOM; a
## neighbour builds its room and nothing else (no camera, sky or warm-up),
## at once or over frames; swap_room trades the rooms (each node left under
## the view that built it), the live view kept at its place and the rooms
## and camera kept where they were to one another
## (shifted together, the shaders' plane_origin with them); swapped back, all
## as before.
func _test_neighbour_swap() -> void:
	print("\n== a held neighbour's view: the fields sorted, its room alone, the swap and back (822) ==")
	var fields := preload("res://client3d/room_fields.gd")
	var unsorted: Array[String] = []
	var twice: Array[String] = []
	var names := {}
	for property: Dictionary in (Client3D as Script).get_script_property_list():
		if not property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			continue
		var field := StringName(property["name"])
		names[field] = true
		var view := fields.VIEW.has(field)
		var room := fields.ROOM.has(field)
		if view and room:
			twice.append(field)
		elif not view and not room:
			unsorted.append(field)
	var stale: Array[String] = []
	for field: StringName in fields.VIEW + fields.ROOM:
		if not names.has(field):
			stale.append(field)
	_check(names.size() > 300 and unsorted.is_empty() and twice.is_empty() and stale.is_empty(),
			"every one of Client3D's %d vars in VIEW or ROOM, once (unsorted: %s; in both: %s; no such var: %s)" % [names.size(), unsorted, twice, stale])

	var castle := Level.load_level("castle")
	var drawn := func(room: Node3D) -> int:
		return room.find_children("*", "", true, false).filter(
				func(node: Node) -> bool: return not String(node.name).begins_with("Scatter_") and not _under_pile(node)).size()
	_rig.rebuild(_main._terrain, Vector2i.ZERO)
	await _frames(Client3D.WARM_FRAMES + 2)
	var neighbour := Client3D.new()
	neighbour.name = "Neighbour"
	_main.add_child(neighbour)
	neighbour.set_process(false)
	neighbour.position = Vector3(40.0, 1.5, -24.0)
	neighbour.build_neighbour(castle["terrain"], castle["centre"], _rig._sky_floor)
	# Its room alone, and nothing of the live zone's World (its doors, piles, grass, marks) hooked.
	_check(neighbour.room_whole() and neighbour.get_children() == [neighbour._room] and neighbour._camera == null
			and neighbour._environment == null and neighbour._warming.is_empty() and neighbour._doors_due.is_empty()
			and not World.grass_changed.is_connected(neighbour._on_grass_changed) and not World.door_shown.is_connected(neighbour._on_door_shown),
			"a neighbour built at once holds its room alone (%s)" % neighbour.get_children().map(func(node: Node) -> String: return node.name))
	var ours_terrain: Dictionary = _rig._terrain
	var ours_room: Node3D = _rig._room
	var theirs_room: Node3D = neighbour._room
	var ours_count: int = drawn.call(ours_room)
	var theirs_count: int = drawn.call(theirs_room)
	var ours_at := ours_room.global_position
	var theirs_at := theirs_room.global_position
	var camera_at: Vector3 = _rig._camera.global_position
	var rig_at := _rig.position
	var neighbour_at := neighbour.position
	_rig.swap_room(neighbour)
	_check(_rig._room == theirs_room and theirs_room.get_parent() == neighbour and neighbour._room == ours_room
			and ours_room.get_parent() == _rig and _rig._terrain == castle["terrain"] and neighbour._terrain == ours_terrain,
			"swapped: the castle's room and terrain the live view's, ours the neighbour's, each room node still under the view that built it")
	var shift := rig_at - neighbour_at
	_check(_rig.position.is_equal_approx(rig_at) and ours_room.global_position.is_equal_approx(ours_at + shift)
			and theirs_room.global_position.is_equal_approx(theirs_at + shift) and _rig._camera.global_position.is_equal_approx(camera_at + shift)
			and Client3D.plane_given.is_equal_approx(_rig._plane_at),
			"the live view kept its place, both rooms and the camera shifted together by %s (%s, %s, %s), plane_origin the castle's" % [shift, ours_room.global_position, theirs_room.global_position, _rig._camera.global_position])
	var piles := World.zone.piles.values().filter(func(pile: GroundPile) -> bool: return pile.is_inside_tree() and (pile.get_parent() as Node2D).visible).size()
	_check(drawn.call(_rig._room) == theirs_count and drawn.call(neighbour._room) == ours_count and _rig._outdoor == bool(castle["terrain"].get("outdoor", false))
			and _rig._pile_nodes.size() == piles and neighbour._pile_nodes.is_empty() and neighbour._room.find_children("Pile_*", "", false, false).is_empty(),
			"each room whole as built (%d and %d nodes, %d and %d), the live zone's %d heaps on the live room alone (%d, %d)"
			% [drawn.call(_rig._room), drawn.call(neighbour._room), theirs_count, ours_count, piles, _rig._pile_nodes.size(), neighbour._pile_nodes.size()])
	_rig.swap_room(neighbour)
	_check(_rig._room == ours_room and _rig._terrain == ours_terrain and _rig.position.is_equal_approx(rig_at) and neighbour.position.is_equal_approx(neighbour_at)
			and _rig._camera.global_position.is_equal_approx(camera_at) and drawn.call(ours_room) == ours_count
			and drawn.call(theirs_room) == theirs_count and neighbour.get_children() == [theirs_room] and neighbour._pile_nodes.is_empty(),
			"swapped back: all as before (%d and %d nodes)" % [drawn.call(ours_room), drawn.call(theirs_room)])
	neighbour.free()

	var later := Client3D.new()
	later.name = "Neighbour"
	_main.add_child(later)
	later.set_process(false)
	later.build_neighbour(castle["terrain"], castle["centre"], _rig._sky_floor, true)
	var frames := 0
	while not later.room_whole() and frames < 600:
		await get_tree().process_frame
		frames += 1
	_check(later.room_whole() and later.get_children() == [later._room] and drawn.call(later._room) == theirs_count,
			"a neighbour built over frames: whole in %d frames, the same room (%d nodes, %d)" % [frames, drawn.call(later._room), theirs_count])
	later.free()
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## Whether [param node] is a heap (a "Pile_" node) or sits under one: the
## live zone's piles, drawn on whichever room is live.
func _under_pile(node: Node) -> bool:
	var up := node
	while up != null:
		if String(up.name).begins_with("Pile_"):
			return true
		up = up.get_parent()
	return false


## Decision 660 (a): a zone's ground fields kept for its next arrival, the
## same ground as worked out afresh; its terrain changed behind them (here a
## cell's kind), the next arrival works them out again, as a build at once
## of the changed terrain draws it.
func _test_kept_fields() -> void:
	print("
== a zone's ground fields kept for its next arrival; its terrain changed, worked out again ==")
	var terrain: Dictionary = Level.load_level("castle")["terrain"].duplicate(true)
	var centre: Vector2i = Level.load_level("castle")["centre"]
	var digest := func() -> int:
		# The fields' own (the chunks' bytes follow the order they were built in).
		return [_rig._corners, _rig._shore_heights, _rig._shore_image.get_data(),
			_rig._depth_image.get_data(), _rig._road_image.get_data(), _rig._kinds_image.get_data()].hash()
	var arrive := func() -> void:
		_rig.rebuild(terrain, centre, true)
		var frames := 0
		while (_rig.building_room or _rig.ground_filling) and frames < 400:
			await get_tree().process_frame
			frames += 1
	_rig._fields_kept.clear()
	var hits: int = _rig.fields_hits
	await arrive.call()
	var first: int = digest.call()
	await arrive.call()
	_check(_rig.fields_hits == hits + 1 and digest.call() == first,
			"the second arrival finds them kept, the same ground (%d hits)" % (_rig.fields_hits - hits))
	var cell: Vector2i = terrain["floor"][terrain["floor"].size() / 2]
	terrain["kinds"][cell] = "sand" if str(terrain["kinds"].get(cell, "")) != "sand" else "grass"
	await arrive.call()
	var changed: int = digest.call()
	_rig.rebuild(terrain, centre)
	_check(_rig.fields_hits == hits + 1 and changed == digest.call() and changed != first,
			"its terrain changed: worked out again, as built at once from the change (%d hits, %s, %s)" % [
			_rig.fields_hits - hits, changed == digest.call(), changed != first])
	for i in Client3D.FIELDS_KEPT + 1:
		terrain["kinds"][cell] = Client3D.GROUND_CHANNELS.keys()[i % Client3D.GROUND_CHANNELS.size()]
		await arrive.call()
	_check(_rig._fields_kept.size() == Client3D.FIELDS_KEPT, "no more than %d zones kept (%d)" % [Client3D.FIELDS_KEPT, _rig._fields_kept.size()])
	_rig._fields_kept.clear()
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## A zone entered again builds its puppets again (Main._repaint): a
## breakable's impacted stays hooked once, never "already connected".
func _test_breakable_hooked_once() -> void:
	print("
== a breakable's puppet made again (a zone entered again) hooks its impacted once ==")
	var crate: GridEntity = null
	for entity in World.get_entities():
		if entity.is_breakable() and not entity.is_creature():
			crate = entity
			break
	_check(crate != null, "the test room has a breakable")
	if crate == null:
		return
	var hooked := func() -> int:
		var count := 0
		for connection: Dictionary in crate.get_signal_connection_list(&"impacted"):
			if (connection["callable"] as Callable).get_object() == _rig:
				count += 1
		return count
	var was: int = hooked.call()
	for again in 2:
		_rig._make_puppet(crate).free()
	_check(was == 1 and hooked.call() == 1, "hooked once before and after two more puppets (%d, %d)" % [was, hooked.call()])


## The highest point drawn at a wall edge's middle (within [param reach] of
## it), over its run's swept body and any art piece in its place
## (wall.<set>.straight_ruined, wall.<set>.rubble: Client3D's WALL_PIECE).
func _drawn_top(key: Vector3i, reach: float) -> float:
	var middle := Client3D._edge_midpoint(key)
	var top := 0.0
	for drawn: MeshInstance3D in _rig._walls[key].find_children("*", "MeshInstance3D", true, false):
		for surface in drawn.mesh.get_surface_count():
			for local: Vector3 in drawn.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var point := drawn.global_transform * local
				if Vector2(point.x - middle.x, point.z - middle.z).length() < reach:
					top = maxf(top, point.y - _rig._edge_base(key))
	return top


## How low a breach's rubble may stand: the swept bank's WALL_RUBBLE_LOW,
## or, where the set's wall.<set>.rubble has art, that piece's own height
## (its slot: at least 0.6 m, never a way through).
func _rubble_low(key: Vector3i) -> float:
	var slot := "wall.%s.rubble" % _rig._set_of(key)
	return 0.6 if ArtKit.filled_by(slot) == "own" else Client3D.WALL_RUBBLE_LOW

func _test_creature_puppets() -> void:
	print("
== a boar is drawn from creature.boar's art, played by its CreatureView (decision 359) ==")
	var boar := _spawn_imp(Vector2i(9, 4), "boar")
	await _frames(2)
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets.get(boar.get_instance_id())
	_check(puppet != null and Client3D.creature_slot_for(boar) == "creature.boar", "a boar's puppet, its slot creature.boar (it has art)")
	if puppet == null:
		return
	var view := puppet.get_meta("creature_view", null) as CreatureView
	var art := puppet.get_node_or_null("Body/Pose").get_child(0) as Node3D if puppet.has_node("Body/Pose") else null
	_check(view != null and art != null and str(art.get_meta("slot", "")) == "creature.boar"
			and (puppet.get_node("Facing") as Node3D).get_child_count() == 0,
			"drawn as creature.boar's art under Body/Pose, no nose")
	if view == null:
		World.despawn(boar)
		return
	_check(["idle", "walk", "run", "graze", "attack", "death"].all(func(clip: String) -> bool: return view.clips.has(clip)),
			"the Pig's clips found by the slot's names: %s" % [view.clips])
	_check(view.resolve("charge") == view.clips["run"] and view.resolve("alert") == view.clips["idle"] and not view.clips.has("hit"),
			"no charge, alert or hit of its own: run and idle stand in (a flinch for a hit)")
	var rig := view.rig
	_check(rig != null and art.is_ancestor_of(rig) and rig.tree.tree_root.has_node("action") and not rig.tree.tree_root.has_node("upper")
			and art.find_children("*", "AnimationPlayer", true, false).size() == 1,
			"played by an AnimRig of its own in the art (decision 390): no upper layer, one AnimationPlayer (the rig's)")
	var player := rig.player if rig != null else null
	_check(player != null and player.get_animation(view.clips["walk"]).loop_mode == Animation.LOOP_LINEAR
			and player.get_animation(view.clips["death"]).loop_mode == Animation.LOOP_NONE, "its walk loops, its death plays once")
	if rig == null:
		World.despawn(boar)
		return
	view.frame(puppet, boar)
	_check(rig.playing() == view.clips["idle"], "standing still: idle")
	_rig._process(0.0)
	_check(rig.every >= 1, "posed as often as Client3D says (_pose_every)")
	view._loop("walk", 1.3)
	view._loop("walk", 0.8)
	_check(rig.base_clip() == view.clips["walk"] and is_equal_approx(rig.speed(), 0.8), "a gait's pace changes its speed, not its clip")
	# A slot clip's "speed" (the old grey's idle at 0.7): its loop at that, and a stand-in's for it.
	view._pace = {"idle": 0.7}
	view._loop("idle", 1.0)
	var slow_idle := is_equal_approx(rig.speed(), 0.7)
	view._loop("alert", 1.0)
	var slow_alert: bool = rig.base_clip() == view.clips["idle"] and is_equal_approx(rig.speed(), 0.7)
	view._loop("walk", 0.8)
	var walk_kept := is_equal_approx(rig.speed(), 0.8)
	view._pace = {}
	# A led blow's coil (338 amended (6)): drawn back with the head dipped over
	# the lead, sprung past rest as it lands, settled after; a heavy wind-up doesn't coil.
	var pose := view._pose
	view.wind(0.3, true)
	await get_tree().create_timer(0.2).timeout
	var coiled := pose.position.x < -0.04 and pose.position.y < -0.01 and pose.rotation.x > 0.06
	await get_tree().create_timer(0.7).timeout
	var settled := is_zero_approx(snappedf(pose.position.x, 0.001)) and is_zero_approx(snappedf(pose.position.y, 0.001)) 			and is_zero_approx(snappedf(pose.rotation.x, 0.001))
	view.unwind()
	view.wind(0.3)
	await get_tree().create_timer(0.2).timeout
	var still := is_zero_approx(snappedf(pose.position.x, 0.001))
	view.unwind()
	_check(coiled and settled and still, "a led blow coils it (%s), settled after (%s); a wind-up without a lead doesn't (%s)" % [coiled, settled, still])
	var old_idle: Array = (ArtKit.spec("creature.old_wolf").get("clips", []) as Array).filter(func(clip: Dictionary) -> bool: return clip["name"] == "idle")
	_check(slow_idle and slow_alert and walk_kept and not old_idle.is_empty() and is_equal_approx(float(old_idle[0].get("speed", 1.0)), 0.7),
			"a slot clip's speed: the idle at 0.7, the alert standing in with it too, the walk its own; the old grey's idle 0.7")
	view.wind(0.6)
	var length := rig.length(view.clips["attack"])
	_check(rig.striking() and rig.playing() == view.clips["attack"]
			and is_equal_approx(rig.speed(), clampf(length * ArtKit.feel("art_kit.clip_contact", CreatureView.CONTACT) / 0.6,
				ArtKit.feel("anim_rig.strike_speed_min", AnimRig.STRIKE_SPEED_MIN), ArtKit.feel("anim_rig.strike_speed_max", AnimRig.STRIKE_SPEED_MAX))),
			"a wound-up blow strikes its headbutt, its middle landing in 0.6 s")
	var wound := rig.speed()
	view.swing()
	_check(rig.playing() == view.clips["attack"] and is_equal_approx(rig.speed(), wound), "a swing while it plays is let be")
	view.unwind()
	_check(not rig.striking(), "a wind-up given up stops it")
	_check(view.die() > 0.0 and rig.playing() == view.clips["death"], "dying plays its death")
	World.despawn(boar)
	await _frames(2)


## The boar king's own clips (package "the boar king", animation's piece): creature.boar_king's
## art holds charge_tell, charge, skid, dazed and hook; the charge's telegraph plays charge_tell, a
## skid its skid, a crash's stun dazed looping till it's over, a heavy wind-up the hook and a lead
## the plain attack. On a view of its own (his row is enemy-ai's, shelved till its switch-on).
## Jeff on v0.1.208: "barrows enemies when dying no longer fall to ground they just freeze in place".
## A robber and a skeleton killed at rest and mid-wind-up each play a death and lie down.
func _test_barrow_deaths() -> void:
	print("
== the barrow's dead fall (Jeff: they froze in place) ==")
	var player := _player()
	if player == null:
		_check(false, "a player to kill them")
		return
	# A cell beside the player it can stand on (wherever earlier sections left them), and the way to it.
	var way := Vector2i.ZERO
	for each: Vector2i in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var cell := player.tile + each
		if World.is_walkable(cell) and not World.is_water(cell) and World.get_entity_at(cell) == null:
			way = each
			break
	if way == Vector2i.ZERO:
		_check(false, "an open cell beside the player (%s)" % player.tile)
		return
	var ahead := Vector2i(signi(way.x), signi(way.y))
	for kind: String in ["robber", "skeleton"]:
		for winding in [false, true]:
			var foe := _spawn_imp(player.tile + way, kind)
			if foe == null:
				_check(false, "a %s placed beside the player (%s)" % [kind, player.tile + way])
				continue
			var puppet: Node3D = null
			for i in 30:
				_rig._process(0.0)
				puppet = _rig._puppets.get(foe.get_instance_id())
				if puppet != null and puppet.has_meta("rig"):
					break
				await get_tree().process_frame
			if puppet == null or not puppet.has_meta("rig"):
				_check(false, "%s drawn with a model (%s)" % [kind, puppet != null])
				World.despawn(foe)
				continue
			var rig := puppet.get_meta("rig") as AnimRig
			await _frames(3)
			_rig._process(0.0)
			if winding:
				_rig._on_winding(-ahead, 3, foe.get_instance_id())
				await _frames(2)
				_rig._process(0.0)
			var before := rig.playing()
			# Killed by a drawn blow (the player swung): its flinch waits for the blade to land, after the death.
			player._world_swung(ahead)
			World.damage(foe, foe.hp + 100, player, &"attack")
			var seen := []
			for i in 12:
				await get_tree().create_timer(0.1).timeout
				_rig._process(0.0)
				if is_instance_valid(puppet):
					seen.append(rig.playing() if is_instance_valid(rig) else "")
			var died := not seen.is_empty() and str(seen[-1]).begins_with("Death")
			_check(is_instance_valid(puppet) and puppet.has_meta("corpse") and died,
					"a %s killed %s plays its death and lies down (%s, then %s)" % [kind, "mid-wind-up" if winding else "at rest", before, seen])
			await _frames(1)


func _test_reel_clock() -> void:
	print("
== a reel times clips by its frames (AnimRig.now_msec) ==")
	var wall_from := AnimRig.now_msec()
	OS.delay_msec(30)
	_check(AnimRig.now_msec() - wall_from >= 30, "in play, the wall clock (%d ms over a 30 ms wait)" % (AnimRig.now_msec() - wall_from))
	AnimRig._clock_movie = 1  # As under --write-movie.
	AnimRig._clock_frame = -1
	var from := AnimRig.now_msec()
	OS.delay_msec(30)
	_check(AnimRig.now_msec() == from, "under movie maker, still through a frame however long it draws")
	await get_tree().process_frame
	var step := AnimRig.now_msec() - from
	var delta := roundi(get_tree().root.get_process_delta_time() * 1000.0)
	_check(absi(step - delta) <= 1, "and on by the frame's own delta (%d ms, delta %d)" % [step, delta])
	# A swing's drawn landing on it too (Client3D._swings, contact_msec): the reel's own moment.
	OS.delay_msec(250)  # The wall now runs ahead of the frames, as in a reel.
	var player := _player()
	var id := player.get_instance_id()
	var puppet: Node3D = _rig._puppets.get(id)
	puppet.set_meta("wound_until", 0)
	player._world_swung(Vector2i(1, 0))
	var swing: Array = _rig._swings.get(id, [])
	var at := AnimRig.now_msec()
	_check(not swing.is_empty() and int(swing[0]) == at and int(swing[2]) >= at and int(swing[2]) - at < 1000
			and int(swing[2]) == int(puppet.get_meta("contact_msec", -1)) and Time.get_ticks_msec() - at >= 200,
			"a swing's landing timed on the reel's frames, its contact with it (%s at %d, wall %d ahead)"
			% [swing, at, Time.get_ticks_msec() - at])
	# Calm again for the tests after (a swing is combat; its strike done).
	_rig._swings.erase(id)
	_rig._combat_at.erase(id)
	if puppet.has_meta("rig"):
		(puppet.get_meta("rig") as AnimRig).cancel_strike()
	puppet.set_meta("busy_until", 0)
	AnimRig._clock_movie = -1
	AnimRig._clock_frame = -1


## Each apex beast (the great bear, the old grey, the boar king) spawned and drawn by Client3D, put
## through every state CreatureView draws and every tell and cry its sim sends: each draws a clip its
## slot has (or, for a tell with none, the body's gather), never nothing.
func _test_apex_sweep() -> void:
	print("
== the apex beasts through every state (the coordinator's check) ==")
	# kind: its tells (move -> slot clip, "" for the gather), its cries (cry -> slot clip, "" for none
	# drawn), what it draws sitting, and its heavy wind-up's clip.
	var apexes := {
		"great_bear": {"tells": {"swipe": "swipe", "slam": "slam", "charge": "charge_tell"}, "cries": {"roar": "roar"},
			"sit": "sleep", "heavy": "attack", "lead": "attack"},
		"old_wolf": {"tells": {"lunge": "lunge_tell"}, "cries": {"howl": "howl"}, "sit": "lie", "heavy": "attack",
			"lead": "bite_lead"},
		"boar_king": {"tells": {"charge": "charge_tell"}, "cries": {"skid": "skid"}, "sit": "graze", "heavy": "hook",
			"lead": "attack"},
	}
	var player := _player()
	for kind: String in apexes:
		var want: Dictionary = apexes[kind]
		var spec := Level._spec_for("monster_" + kind, Level.MONSTER_TYPES)
		spec["name"] = "Sweep" + kind.capitalize().replace(" ", "")
		var at := player.tile + Vector2i(3, 0) if player != null else Vector2i(9, 4)
		if World.get_entity_at(at) != null:
			World.despawn(World.get_entity_at(at))
		spec["tile"] = at
		var beast := _main._spawn(spec) as Monster
		var puppet: Node3D = null
		for i in 30:
			_rig._process(0.0)
			puppet = _rig._puppets.get(beast.get_instance_id()) if beast != null else null
			if puppet != null and puppet.has_meta("creature_view"):
				break
			await get_tree().process_frame
		if puppet == null or not puppet.has_meta("creature_view"):
			_check(false, "%s drawn (%s, %s)" % [kind, beast != null, puppet != null])
			if beast != null:
				World.despawn(beast)
			continue
		var view := puppet.get_meta("creature_view") as CreatureView
		var rig := view.rig
		var fresh := func() -> void:
			rig.cancel_strike()
			view.unwind()
			view._busy_until = 0
			view._charge_until = 0
			view._bolt_until = 0
			view._pant_until = 0
			view._dazed_until = 0
			view._then = ""
			view._tell_then_at = 0
			beast.alert = Monster.Alert.IDLE
			beast.pose = Monster.Pose.STAND
			beast.winded = false
			beast.teeter = Vector2i.ZERO
			beast.stun_cause = &""
			beast._reel_until = 0.0
		var drawn := func(speed: float) -> String:
			view._speed = speed
			view._last_at = puppet.position
			view._last_ms = AnimRig.now_msec()
			view.frame(puppet, beast)
			return rig.base_clip()
		var states := []
		var wrong := []
		var expect := func(label: String, got: String, slot_clip: String) -> void:
			var ok := got != "" and got == view.resolve(slot_clip)
			states.append(label)
			if not ok:
				wrong.append("%s: %s, not %s" % [label, got, view.resolve(slot_clip)])
		fresh.call()
		expect.call("idle", drawn.call(0.0), "idle")
		expect.call("walk", drawn.call(1.0), "walk")
		expect.call("run", drawn.call(3.0), "run")
		beast.alert = Monster.Alert.FLEEING
		expect.call("fleeing", drawn.call(1.0), "run")
		fresh.call()
		beast.alert = Monster.Alert.SUSPICIOUS
		expect.call("suspicious", drawn.call(0.0), "alert")
		fresh.call()
		beast.pose = Monster.Pose.SIT
		expect.call("sitting", drawn.call(0.0), str(want["sit"]))
		fresh.call()
		beast.winded = true
		expect.call("winded", drawn.call(0.0), "winded" if view.clips.has("winded") else "idle")
		fresh.call()
		beast.teeter = Vector2i(1, 0)
		expect.call("teetering", drawn.call(0.0), "teeter" if view.clips.has("teeter") else "walk")
		fresh.call()
		beast.stun_cause = &"crash"
		beast._reel_until = World.tick + 20.0
		expect.call("crash stun", drawn.call(0.0), "dazed" if view.clips.has("dazed") else "idle")
		fresh.call()
		view.swing()
		expect.call("swing", rig.playing(), "attack")
		fresh.call()
		view.wind(0.6)
		expect.call("heavy wind-up", rig.playing(), str(want["heavy"]))
		fresh.call()
		view.wind(0.3, true)
		expect.call("lead", rig.playing(), str(want["lead"]))
		for move: String in want["tells"]:
			fresh.call()
			var clip := str(want["tells"][move])
			_rig.creature_tell(90 + states.size(), {"source": str(beast.get_path()), "kind": move, "lands_tick": World.tick + 10})
			if clip == "":
				states.append("tell " + move)
				if not (view._coil != null and view._coil.is_valid() and _rig._tells.has(90 + states.size() - 1)):
					wrong.append("tell %s: no gather" % move)
			else:
				expect.call("tell " + move, rig.playing(), clip)
		for cry: String in want["cries"]:
			fresh.call()
			_rig._on_cried(StringName(cry), beast.get_instance_id())
			expect.call("cry " + cry, rig.playing(), str(want["cries"][cry]))
		fresh.call()
		view.hit()
		if view.clips.has("hit"):
			expect.call("hit", rig.playing(), "hit")
		fresh.call()
		_check(wrong.is_empty(), "%s: every state drawn (%s)%s" % [kind, ", ".join(states), "" if wrong.is_empty() else "; WRONG " + "; ".join(wrong)])
		if kind == "old_wolf":
			fresh.call()
			_rig._on_cried(&"pant", beast.get_instance_id())
			var panting: String = drawn.call(0.0)
			_check(panting == view.clips["idle"] and view._pant_until > AnimRig.now_msec() + 1500,
					"the old grey's pant: his idle slowed, head low, for its 20 ticks (%s, %.2f s left)"
					% [panting, (view._pant_until - AnimRig.now_msec()) / 1000.0])
			fresh.call()
		World.despawn(beast)
		_rig._process(0.0)
		await _frames(1)


## The old grey's lunge drawn as a made leap (780 amended (24), animation's side; the coordinator,
## after v0.1.210's "a squash and spring, not a made leap"): his lunge's telegraph plays his
## lunge_tell, its contact on the landing (his SPRING windup, 0.8 s), its crouch held on after; at
## the landing (drawn here without a body, so not waiting on its slide) his leap plays once out of
## the crouch; called off, no leap; a landing seen late (drawn otherwise then) no stale leap.
func _test_old_wolf_leap() -> void:
	print("\n== the old grey's lunge: the crouch told, the leap at its landing ==")
	var body := Node3D.new()
	var pose := Node3D.new()
	body.add_child(pose)
	_rig.add_child(body)
	var art := ArtKit.instance("creature.old_wolf")
	pose.add_child(art)
	var view := CreatureView.new("creature.old_wolf", art, pose)
	body.add_child(view)
	var rig := view.rig
	var has_all := rig != null and ["lunge_tell", "leap"].all(func(clip: String) -> bool: return view.clips.has(clip))
	_check(has_all, "his art holds lunge_tell and leap (%s)" % [view.clips.keys()])
	if not has_all:
		body.queue_free()
		return
	var crouch_to := rig.length(view.clips["lunge_tell"]) * float(view._contact.get("lunge_tell", 0.0))
	_check(absf(crouch_to - 0.8) < 0.05 and rig.length(view.clips["lunge_tell"]) > 1.1 and rig.length(view.clips["leap"]) > 0.4
			and rig.length(view.clips["leap"]) < 0.8,
			"the crouch 0.8 s to the spring (OldWolf's SPRING windup, 8 ticks), held on after, the leap under 0.8 s (%.2f of %.2f, %.2f)"
			% [crouch_to, rig.length(view.clips["lunge_tell"]), rig.length(view.clips["leap"])])
	view.frame(body, null)
	var told := view.tell("lunge", 0.8, 21)
	var landing := view._tell_until
	_check(told and rig.playing() == view.clips["lunge_tell"] and view._tell_then == "leap" and view._tell_then_at == landing
			and absf(rig._contact_msec - landing) <= 40 and rig._strike_msec > landing + 200,
			"his lunge's telegraph plays lunge_tell, its spring on the landing, the crouch held on after, the leap to follow (%s)" % rig.playing())
	view.frame(body, null)
	_check(rig.playing() == view.clips["lunge_tell"], "before its landing, still crouched (%s)" % rig.playing())
	view._tell_then_at = AnimRig.now_msec()  # Its landing come (the clock's, not waited for).
	# Landed, but his rush's slide not begun (a tick or more after): the crouch held; the leap
	# starts with the slide (GridEntity.stepping), so he never stands up before he goes.
	var near := _player()
	var grey := _spawn_imp(near.tile + Vector2i(0, 2) if near != null else Vector2i(9, 6))  # His body.
	grey.stepping = false
	view.frame(body, grey)
	var held: bool = rig.playing() == view.clips["lunge_tell"] and view._tell_then_at > 0
	grey.stepping = true
	view.frame(body, grey)
	grey.stepping = false
	_check(held and rig.base_clip() == view.clips["leap"] and not rig.striking() and view._busy_until > AnimRig.now_msec()
			and view._tell_then_at == 0,
			"landed, his crouch held till his rush slides, then he leaps, once, the crouch over (%s, %s)"
			% [held, rig.base_clip()])
	World.despawn(grey)
	view.tell_over(21, true)
	view._busy_until = 0
	view.frame(body, null)
	view.tell("lunge", 0.8, 22)
	view.tell_over(22, false)
	_check(view._tell_then_at == 0 and not rig.striking(), "called off (stunned in his crouch): no leap to follow")
	view.frame(body, null)
	view.tell("lunge", 0.8, 23)
	view._tell_then_at = AnimRig.now_msec() - CreatureView.TELL_THEN_LATE_MS - 100
	view.frame(body, null)
	_check(rig.base_clip() != view.clips["leap"] and view._tell_then_at == 0,
			"a landing seen late (he was drawn otherwise as it came): no stale leap (%s)" % rig.base_clip())
	# His bite told ahead (enemy-ai's 780 amended (23), a lead of 6 ticks): his own bite_lead, head
	# down and back, held, its snap (the contact) landing with the blow; not the generic coil.
	view._busy_until = 0
	rig.cancel_strike()
	view.wind(0.6, true)
	var length := rig.length(view.clips["bite_lead"])
	var contact := length * float(view._contact.get("bite_lead", 0.0))
	_check(view.clips.has("bite_lead") and rig.playing() == view.clips["bite_lead"] and absf(rig.speed() - contact / 0.6) < 0.02
			and absf(contact - 0.65) < 0.05 and not (view._coil != null and view._coil.is_running()),
			"his bite told ahead: his bite_lead, its snap at 0.6 s with the blow, no generic coil (%s x%.2f, snap %.2f s of %.2f)"
			% [rig.playing(), rig.speed(), contact, length])
	body.queue_free()
	await _frames(1)


func _test_hill_cat_clips() -> void:
	print("
== the hill cat's clips: crouch, leap and recover, lie, snarl, swipe and bite ==")
	var body := Node3D.new()
	var pose := Node3D.new()
	body.add_child(pose)
	_rig.add_child(body)
	var art := ArtKit.instance("creature.hill_cat")
	pose.add_child(art)
	var view := CreatureView.new("creature.hill_cat", art, pose)
	body.add_child(view)
	var rig := view.rig
	var wanted := ["crouch_tell", "pounce", "recover", "lie", "snarl", "bite", "attack"]
	var has_all := rig != null and wanted.all(func(clip: String) -> bool: return view.clips.has(clip))
	_check(has_all, "its art holds its clips (%s)" % [view.clips.keys()])
	if not has_all:
		body.queue_free()
		return
	view.frame(body, null)
	_check(view.tell("pounce", 1.1, 9) and rig.playing() == view.clips["crouch_tell"],
			"the pounce's telegraph plays crouch_tell, not the leap (%s)" % rig.playing())
	view.tell_over(9, true)
	view.pounce()
	var leapt := rig.playing()
	await get_tree().create_timer(rig.length(view.clips["pounce"]) + 0.1).timeout
	view.frame(body, null)
	_check(leapt == view.clips["pounce"] and rig.playing() == view.clips["recover"],
			"its landing cry: the leap, then recover (%s, then %s)" % [leapt, rig.playing()])
	await get_tree().create_timer(rig.length(view.clips["recover"]) + 0.1).timeout
	view.frame(body, null)
	rig.cancel_strike()
	view.snarl()
	_check(rig.playing() == view.clips["snarl"], "spotted (cried call): it snarls (%s)" % rig.playing())
	rig.cancel_strike()
	view._busy_until = 0
	view.swing()
	var first := rig.playing()
	rig.cancel_strike()
	view.swing()
	var second := rig.playing()
	rig.cancel_strike()
	_check(first == view.clips["attack"] and second == view.clips["bite"], "its blows swipe, then bite (%s, %s)" % [first, second])
	view.wind(0.6, true)
	var led := rig.playing()
	view.unwind()
	view.wind(0.6, true)
	var led_again := rig.playing()
	view.unwind()
	_check(led == view.clips["attack"] and led_again == view.clips["bite"],
			"its wound-up blows too, as it fights (the reel's: every blow a lead): swipe, then bite (%s, %s)" % [led, led_again])
	body.queue_free()
	await _frames(1)
	# Spawned and drawn: lying up (Pose.SIT) it lies.
	var spec := Level._spec_for("monster_hill_cat", Level.MONSTER_TYPES)
	spec["name"] = "ViewHillCat"
	var player := _player()
	var at := player.tile + Vector2i(3, 0) if player != null else Vector2i(9, 4)
	if World.get_entity_at(at) != null:
		World.despawn(World.get_entity_at(at))
	spec["tile"] = at
	var cat := _main._spawn(spec) as Monster
	var puppet: Node3D = null
	for i in 30:
		_rig._process(0.0)
		puppet = _rig._puppets.get(cat.get_instance_id()) if cat != null else null
		if puppet != null and puppet.has_meta("creature_view"):
			break
		await get_tree().process_frame
	if puppet == null or not puppet.has_meta("creature_view"):
		_check(false, "the hill cat drawn (%s, %s)" % [cat != null, puppet != null])
		if cat != null:
			World.despawn(cat)
		return
	var drawn := puppet.get_meta("creature_view") as CreatureView
	cat.pose = Monster.Pose.SIT
	drawn._speed = 0.0  # Standing where it was drawn (a step's speed would draw its gait).
	drawn._last_at = puppet.position
	drawn._busy_until = 0
	drawn.frame(puppet, cat)
	_check(drawn.rig.base_clip() == drawn.clips["lie"], "lying up (Pose.SIT), drawn lying, not standing idle (%s)" % drawn.rig.base_clip())
	World.despawn(cat)
	_rig._process(0.0)


func _test_boar_king_clips() -> void:
	print("\n== the boar king's clips: tell, charge, skid, dazed, hook ==")
	var body := Node3D.new()
	var pose := Node3D.new()
	body.add_child(pose)
	_rig.add_child(body)
	var art := ArtKit.instance("creature.boar_king")
	pose.add_child(art)
	var view := CreatureView.new("creature.boar_king", art, pose)
	body.add_child(view)
	var five := ["charge_tell", "charge", "skid", "dazed", "hook"]
	_check(five.all(func(clip: String) -> bool: return view.clips.has(clip)) and view.clips.has("idle"),
			"his art holds his five beside the Pig's (%s)" % [view.clips.keys()])
	var rig := view.rig
	if rig == null or not five.all(func(clip: String) -> bool: return view.clips.has(clip)):
		body.queue_free()
		return
	_check(absf(rig.length(view.clips["charge_tell"]) - 1.2) < 0.06 and absf(rig.length(view.clips["skid"]) - 1.5) < 0.06
			and rig.player.get_animation(view.clips["dazed"]).loop_mode == Animation.LOOP_LINEAR,
			"the tell 1.2 s and the skid 1.5 s (BoarKing's 12 and 15 ticks), dazed looping")
	view.frame(body, null)
	_check(view.tell("charge", 1.2, 7) and rig.playing() == view.clips["charge_tell"], "the charge's telegraph plays charge_tell (%s)" % rig.playing())
	view.tell_over(7, true)
	view.charge()
	rig.cancel_strike()
	view._busy_until = 0
	view.skid()
	_check(rig.playing() == view.clips["skid"] and view._charge_until == 0, "a skid plays skid, the charge over (%s)" % rig.playing())
	view._busy_until = 0
	view.daze(0.4)
	view.frame(body, null)
	var dazed := rig.base_clip()
	await get_tree().create_timer(0.5).timeout
	view.frame(body, null)
	_check(dazed == view.clips["dazed"] and rig.base_clip() == view.clips["idle"],
			"a crash's stun loops dazed through it, then idle (%s, then %s)" % [dazed, rig.base_clip()])
	view.wind(0.6)
	var hooked := rig.playing()
	view.unwind()
	view.wind(0.3, true)
	var led := rig.playing()
	view.unwind()
	_check(hooked == view.clips["hook"] and led == view.clips["attack"], "a heavy wind-up hooks, a lead the plain attack (%s, %s)" % [hooked, led])
	body.queue_free()
	await _frames(1)
	# Spawned and drawn by Client3D: his crash's stun (stunned, cause &"crash") holds him dazed through it.
	var spec := Level._spec_for("monster_boar_king", Level.MONSTER_TYPES)
	spec["name"] = "ViewBoarKing"
	var player := _player()
	var at := player.tile + Vector2i(3, 0) if player != null else Vector2i(9, 4)
	if World.get_entity_at(at) != null:
		World.despawn(World.get_entity_at(at))
	spec["tile"] = at
	var king := _main._spawn(spec) as Monster
	var puppet: Node3D = null
	for i in 30:
		_rig._process(0.0)
		puppet = _rig._puppets.get(king.get_instance_id()) if king != null else null
		if puppet != null and puppet.has_meta("creature_view"):
			break
		await get_tree().process_frame
	if puppet == null or not puppet.has_meta("creature_view"):
		_check(false, "the boar king drawn (%s, %s)" % [king != null, puppet != null])
		if king != null:
			World.despawn(king)
		return
	var drawn := puppet.get_meta("creature_view") as CreatureView
	World._stun_for(king, 25, &"crash")
	World._stun_for(king, 3)  # The same tick's slide: its cause kept, its end not the daze's.
	var seen := []
	for i in 6:
		await get_tree().create_timer(0.35).timeout
		_rig._process(0.0)
		seen.append(drawn.rig.base_clip() if drawn.rig != null else "")
	_check(king.stun_cause == &"crash" and seen.all(func(clip: String) -> bool: return clip == drawn.clips.get("dazed", "-")),
			"his crash's stun, drawn: dazed through it (%s)" % [seen])
	# Backing off to charge (enemy-ai's back-off): walking away from where he faces, drawn backing
	# (back_off), not walking off; walking where he faces, his walk. Cried snort: the paw, 0.6 s.
	king.stun_cause = &""
	king._reel_until = 0.0
	king._shown_angle = 0.0  # Facing +x.
	var backed := _drawn_walk(drawn, puppet, king, Vector3(0.1, 0.0, 0.0))
	var walked := _drawn_walk(drawn, puppet, king, Vector3(-0.1, 0.0, 0.0))
	_check(drawn.clips.has("back_off") and backed == drawn.clips["back_off"] and walked == drawn.clips["walk"],
			"backing away facing his foe, drawn backing off; walking on, his walk (%s, %s)" % [backed, walked])
	drawn._busy_until = 0
	drawn.rig.cancel_strike()
	_rig._on_cried(&"snort", king.get_instance_id())
	_check(drawn.clips.has("paw") and drawn.rig.playing() == drawn.clips["paw"]
			and absf(drawn.rig.length(drawn.clips["paw"]) - 0.6) < 0.06,
			"cried snort: he paws in place, 0.6 s (his 6 ticks) (%s)" % drawn.rig.playing())
	# A real back step (the boarback reel showed the slide turning him to walk off): his face set
	# on his foe across the step (BoarKing._tend_back_off's _world_set_facing after World.try_move);
	# through the slide his shown facing stays on them and he is drawn backing, never walking. The
	# edges (the coordinator's): a step at a slant to his facing turns him to it as before; his
	# back-off ended mid-slide (his facing put on his step) turns him to it then, eased, no snap.
	# Back_off alone while the slide runs, from its first frame (the view draws it by the slide's own
	# way, whatever the pace reads): from rest, then from a pace read past RUN_ABOVE and taken late in
	# a tick (dungeon's take drew Run on the opening frame: the slide stamped on the whole tick, a
	# loaded first frame read the jump along it as a run), then mid-tick from rest.
	var only_back := func(clips: Dictionary) -> bool:
		return clips.keys() == [drawn.clips.get("back_off", "-")]
	var back := await _back_step(king, drawn, true, false)
	var hurried := await _back_step(king, drawn, true, false, CreatureView.RUN_ABOVE * 2.0, 0.95)
	var late := await _back_step(king, drawn, true, false, 0.0, 0.6)
	_check(back["stepped"] and hurried["stepped"] and late["stepped"] and king.faces_back_steps and back["kept"] > 0.9
			and hurried["kept"] > 0.9 and late["kept"] > 0.9 and only_back.call(back["clips"]) and only_back.call(hurried["clips"])
			and only_back.call(late["clips"]),
			"a real back step: his face kept on his foe through the slide (the least %.2f), drawn only backing off %s; at a pace read past the run's, the step taken late in a tick %s; mid-tick %s"
			% [minf(back["kept"], minf(hurried["kept"], late["kept"])), back["clips"].keys(), hurried["clips"].keys(), late["clips"].keys()])
	var slant := await _back_step(king, drawn, false, false)
	_check(slant["stepped"] and slant["to_step"] > 0.7,
			"a step at a slant to his facing: turned to his step within the slide, as before (%.2f toward it, the most %.2f rad a frame)"
			% [slant["to_step"], slant["jump"]])
	var ended := await _back_step(king, drawn, true, true)
	_check(ended["stepped"] and ended["kept"] > 0.9 and ended["to_step"] > 0.5,
			"his back-off ended mid-slide: turned to his step then, within the slide, not at its end (%.2f toward it, the most %.2f rad a frame)"
			% [ended["to_step"], ended["jump"]])
	World.despawn(king)
	await _frames(1)


## The boar king [param king] stepped a cell by World.try_move, drawn by [param view] through its
## slide (780 amended (16), his back-off, animation's side): [param backing], his facing put
## against the step after it (as BoarKing._tend_back_off does), else at a slant (a right angle) to
## it; [param end_mid], his facing put on his step halfway through the slide (his back-off over).
## Gives "stepped", "kept" (the least shown facing along the facing he held, while held),
## "to_step" (the most his shown facing came round along the step while the slide ran,
## GridEntity.stepping),
## "jump" (the most the shown facing turned in one frame, rad: TURN_RATE's ease, for the print) and
## "clips" (the base clips drawn while the slide ran). [param pace]: the pace the view last read
## as the step starts (one past RUN_ABOVE: a hitch's); [param alpha] (0..1), the tick's fraction
## it is taken at (the slide stamped on the whole tick, its opening frame a jump along it).
func _back_step(king: Monster, view: CreatureView, backing: bool, end_mid: bool, pace := 0.0, alpha := -1.0) -> Dictionary:
	var out := {"stepped": false, "kept": 1.0, "to_step": -1.0, "jump": 0.0, "clips": {}}
	king.stunned_until_tick = 0
	king.next_move_tick = 0
	king.move_ticks = 5.0
	view._busy_until = 0
	view._charge_until = 0
	view.rig.cancel_strike()
	# One clock and one order, as in play (World's clock, then the body, then Client3D's draw, a frame
	# at a time): the view's clock is its frames' own (AnimRig's reel clock, read once a frame), the
	# slide's clock runs on it, and the test alone moves him and draws him (his and Client3D's own
	# frames stopped through the step). Before, the view timed the slide by the wall between its draws
	# while the test moved it by the frame's delta, his place was a frame behind the draw, and Client3D
	# drew him again between: on a loaded machine the 2 cells a second he backs at read past RUN_ABOVE
	# (2.2), so "Run" was drawn (builder's take; a trace beside a suite read 2.16, its draws 3-20 ms
	# apart, each delta 8 ms, and with the clocks alone made one, up to 2.46 off the frame-late place).
	var processing := _rig.is_processing()
	var moving := king.is_processing()
	_rig.set_process(false)
	king.set_process(false)
	AnimRig._clock_movie = 1
	AnimRig._clock_frame = -1
	var stepped := Vector2i.ZERO
	var held := Vector2i.ZERO
	for way: Vector2i in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0)]:
		held = -way if backing else Vector2i(way.y, -way.x)
		king._world_set_facing(held)
		king.turn_shown_from(Vector2(held).angle())
		view._last_at = Vector3.INF  # No step left over from before: the slide's own.
		view._speed = pace
		_rig._process(0.0)  # Its view drawn once, so it knows it backs (faces_back_steps).
		view._speed = pace
		if alpha >= 0.0:
			World.tick_alpha = alpha
		if World.try_move(king, way):
			stepped = way
			break
	if stepped == Vector2i.ZERO:
		AnimRig._clock_movie = -1
		_rig.set_process(processing)
		king.set_process(moving)
		return out
	out["stepped"] = true
	king._world_set_facing(held)
	var last := king.shown_facing().angle()
	var began := AnimRig.now_msec()
	var clock := began
	var walled := Time.get_ticks_msec()
	var ended := false
	# The slide's 5 ticks on the view's clock, through to its end (World doesn't tick here, so his mind
	# doesn't move him again), 3 s of the wall at most.
	while (clock - began < 450 or king.stepping) and Time.get_ticks_msec() - walled < 3000:
		await get_tree().process_frame
		# The drawing clock run as _run_clock does, by the time the view sees pass: the slide moves.
		var now := AnimRig.now_msec()
		var seconds := (now - clock) / 1000.0
		World.tick_alpha += seconds * World.TICK_RATE
		clock = now
		while World.tick_alpha >= 1.0:
			World.tick += 1
			World.tick_alpha -= 1.0
		if end_mid and not ended and clock - began >= 200:
			ended = true
			king._world_set_facing(stepped)
		king._process(seconds)  # His place and shown facing at this clock, before he is drawn.
		_rig._process(0.0)
		var shown := king.shown_facing()
		if not ended:
			out["kept"] = minf(out["kept"], shown.dot(Vector2(held).normalized()))
		out["jump"] = maxf(out["jump"], absf(angle_difference(last, shown.angle())))
		last = shown.angle()
		if king.stepping:  # Within the slide only: after it he turns to his facing as every body does.
			out["to_step"] = maxf(out["to_step"], shown.dot(Vector2(stepped).normalized()))
			out["clips"][view.rig.base_clip()] = true
	AnimRig._clock_movie = -1  # The wall's again, as the rest of the test is timed.
	_rig.set_process(processing)
	king.set_process(moving)
	return out


## What [param view] draws for [param monster] moved a step from [param puppet]'s place plus
## [param from] to it, at a walk (about 2 cells a second).
func _drawn_walk(view: CreatureView, puppet: Node3D, monster: Monster, from: Vector3) -> String:
	view._busy_until = 0
	view._charge_until = 0
	view._speed = 2.0
	view._last_at = puppet.position + from
	view._last_ms = AnimRig.now_msec() - 50
	view.frame(puppet, monster)
	return view.rig.base_clip()


## An apex beast's tells (780 amended (6)): a telegraph's move plays the slot clip of its name
## (charge: charge_tell), its contact on the lands tick; called off, it stops; a roar plays its
## roar; asleep (Pose SIT) its sleep, winded and standing its winded; a slot without those clips
## does as before. On a boar's view, its art given the great bear's clip names (the bear's slot is
## art-kit's to land): stand-ins copied from its own clips.
## A miner's swing meets the seam (769 amended (9)): a player with a pick, facing an ore seam in
## the next cell (its front turned to them), swings; at the swing's contact the pick's point is at
## the seam's face (no farther in than PICK_BITE, no short of it more than PICK_SHORT), at a height
## on the rock, not the floor, and the blow puffs dust at the face as it lands.
func _test_pick_meets_seam() -> void:
	print("\n== a miner's swing: the pick's point meets the seam's face at the contact (769 amended (9)) ==")
	var player := _player()
	var slots := player.slots
	while slots.size() < Items.CARRIED:
		slots.append("")
	var was := slots.duplicate()
	var was_facing := player.facing
	slots[Items.RIGHT_HAND] = "pick"
	slots[Items.LEFT_HAND] = ""
	player.slots = slots
	player.facing = Vector2i(1, 0)
	var at := player.tile + Vector2i(1, 0)
	var occupant := World.get_entity_at(at)
	if occupant != null:
		World.despawn(occupant)
	var spec: Dictionary = Level._spec_for("seam", {})
	spec["name"] = "ViewSeam"
	spec["tile"] = at
	spec["art_facing"] = Vector2i(-1, 0)
	var seam := _main._spawn(spec) as Seam
	await _frames(3)
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets[player.get_instance_id()]
	var rock: Node3D = _rig._puppets.get(seam.get_instance_id())
	var rig := puppet.get_meta("rig") as AnimRig
	puppet.set_meta("busy_until", 0)
	puppet.set_meta("wound_until", 0)
	# The seam's face: its rock's nearest point toward the miner (+x is away from them).
	var face := INF
	var top := -INF
	for mesh: MeshInstance3D in rock.find_children("*", "MeshInstance3D", true, false):
		for v in mesh.mesh.get_faces():
			var p := mesh.global_transform * v
			face = minf(face, p.x)
			top = maxf(top, p.y)
	print("    the miner at x %.3f, the face %.3f ahead, the rock %.2f m tall; contact in %.2f s"
			% [puppet.global_position.x, face - puppet.global_position.x, top - puppet.global_position.y, World.windup_ticks(player) * World.TICK_DT])
	player.swung.emit(Vector2i(1, 0))
	_rig._on_struck(1, &"attack", seam.get_instance_id())  # The blow as the server's damage reports it.
	var contact := rig.contact_msec
	while Time.get_ticks_msec() < contact:
		await get_tree().process_frame
	# The pose read at the contact in the clip's own time, held there: under a loaded suite one long frame
	# ran the wall clock past it (maps' landing, -0.14 m; +0.03 alone).
	rig._contact_msec = -1  # Its own switch to the recovery's speed would run it on past the seek.
	rig._set_action_speed(0.0)
	rig.tree.set("parameters/action_seek/seek_request", rig.contact_at)
	rig._apply()
	_rig._process(0.0)
	# Held there while the blends settle (on the wall clock, as the sledge's slide test waits its fade in
	# out): read at once the same pose stood 0.03 m nearer the body on one run in four (-0.064, then -0.033),
	# its rest's and its strike's fades caught at a different share. Then seeked again and read.
	await get_tree().create_timer(0.3).timeout
	rig.tree.set("parameters/action_seek/seek_request", rig.contact_at)
	rig._apply()
	_rig._process(0.0)
	await get_tree().process_frame
	var held := ((puppet.get_meta("sockets") as Dictionary)["hand_r"] as Node3D).get_node_or_null("Held") as Node3D
	# The pick's point and chisel, in its art's own frame (art-kit's item.pick: the point 0.27 m off the
	# haft toward +x, 0.767 m up it); the rock's front at the point's height.
	var tip := Vector3(-INF, 0.0, 0.0)
	var chisel := Vector3.ZERO
	if held != null:
		for mesh: MeshInstance3D in held.find_children("*", "MeshInstance3D", true, false):
			tip = mesh.global_transform * Client3D.PICK_POINT
			chisel = mesh.global_transform * Vector3(-0.211, 0.791, 0.0)
	var face_there := INF
	for mesh: MeshInstance3D in rock.find_children("*", "MeshInstance3D", true, false):
		for v in mesh.mesh.get_faces():
			var p := mesh.global_transform * v
			if absf(p.y - tip.y) < 0.08:
				face_there = minf(face_there, p.x)
	face = face_there
	var ground := puppet.global_position.y
	print("    clip %s; the point at x %.3f (the face there %.3f: %+.3f), %.2f m up; the chisel %.2f ahead, %.2f up"
			% [rig.playing(), tip.x, face, tip.x - face, tip.y - ground, chisel.x - puppet.global_position.x, chisel.y - ground])
	_check(rig.playing() == Client3D.CLIP_PICK_SWING, "a pick swings Pick_Swing (%s)" % rig.playing())
	_check(tip.x - face < Client3D.PICK_BITE and face - tip.x < Client3D.PICK_SHORT,
			"at its contact the point meets the face (%+.2f m)" % (tip.x - face))
	_check(tip.y - ground > 0.4 and tip.y - ground < 1.4, "on the rock, not the floor (%.2f m up)" % (tip.y - ground))
	rig._set_action_speed(rig._recover_speed)
	await _frames(3)
	var dust := rock.get_node_or_null("SeamDust") as GPUParticles3D
	# Made by this blow (the seam is this test's own), so not read by its emitting: that runs out on the
	# wall clock, and a 200 ms stall before the contact's seek had it out.
	_check(dust != null and dust.global_position.x < face + 0.1 and absf(dust.global_position.y - ground - Client3D.SEAM_DUST_UP) < 0.05,
			"the blow puffs dust off the face as it lands (%s)" % (str(dust.global_position) if dust != null else "none"))
	rig.cancel_strike()
	puppet.set_meta("busy_until", 0)
	World.despawn(seam)
	player.slots = was
	player.facing = was_facing
	_rig._process(0.0)


## The heavy axes' sweep leads with the edge: through the blow (Axe_Sweep's fast stretch about its
## contact) each axe's striking side (its art's +x, laid along the fingers by HELD_EDGE_TURN) faces
## the way its head travels, not the flat (the great-axe check: the blade hung edge down across the
## level swing, 0.0-0.2 of the way along its travel). Scrubbed, as the sledge's slide is.
func _test_axe_edge_leads() -> void:
	print("
== the heavy axes' sweep: the edge leads the blow ==")
	var player := _player()
	var slots := player.slots
	while slots.size() < Items.CARRIED:
		slots.append("")
	var was := slots.duplicate()
	for id: String in ["battle_axe", "giant_axe"]:
		slots[Items.RIGHT_HAND] = id
		slots[Items.LEFT_HAND] = ""
		player.slots = slots
		_rig._process(0.0)
		var puppet: Node3D = _rig._puppets[player.get_instance_id()]
		var rig := puppet.get_meta("rig") as AnimRig
		var held := ((puppet.get_meta("sockets") as Dictionary)["hand_r"] as Node3D).get_node_or_null("Held") as Node3D
		if held == null:
			_check(false, "%s in hand" % id)
			continue
		rig.strike("Axe_Sweep", 0.8, 0.8, 0.5)
		rig._contact_msec = -1
		rig._strike_msec = Time.get_ticks_msec() + 600000
		rig._set_action_speed(0.0)
		# Its fade in run out first: on the wall clock, so the first steps scrubbed stood half blended with the rest.
		rig.tree.set("parameters/action_seek/seek_request", 0.55)
		rig._apply()
		await get_tree().create_timer(0.5).timeout
		var heads: Array[Vector3] = []
		var edges: Array[Vector3] = []
		for step in 11:
			rig.tree.set("parameters/action_seek/seek_request", 0.55 + step * 0.05)
			rig._apply()
			_rig._process(0.0)
			await get_tree().process_frame
			# In the piece's own frame (art_style: its length +y, its striking side +x), the head 1.1 m up it.
			heads.append(held.global_transform * Vector3(0.0, 1.1, 0.0))
			edges.append(held.global_basis.x.normalized())
		var worst := INF
		for k in range(1, heads.size() - 1):
			worst = minf(worst, edges[k].dot((heads[k + 1] - heads[k - 1]).normalized()))
		_check(worst > 0.8, "%s: through the blow its edge leads the head's travel (at worst %.2f of the way)" % [id, worst])
		# Ended as a strike ends (as the sledge's): run out at speed, so the tests after it stand on the rest.
		rig._set_action_speed(1.0)
		rig.tree.set("parameters/action_seek/seek_request", rig.length("Axe_Sweep"))
		rig._apply()
		rig._strike_msec = 0
		# Its fade out run in time (the next axe's blow, or the bow's pose after, stood on it half faded).
		await get_tree().create_timer(0.6).timeout
		_rig._process(0.0)
		puppet.set_meta("busy_until", 0)
	player.slots = was
	_rig._process(0.0)
	await get_tree().create_timer(0.6).timeout  # The axes' ready stance faded off the upper body before the bow's tests read it.
	_rig._process(0.0)


## A guard as a client draws it (791, npc's side; pc-character's): its replicated hands are its
## slots (Client3D._mirror_hands), so the spear is in its right hand and is what it strikes with;
## its mail (worn) worn, and its lie (down_until: knocked down, or downed for as long) drawn, as a
## player's. A resident with no hands sent keeps what it has.
func _test_guard_arms() -> void:
	print("
== a guard as a client draws it: the spear in hand, the mail, the lie (791) ==")
	var player := _player()
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets[player.get_instance_id()]
	var sockets: Dictionary = puppet.get_meta("sockets")
	var guard := Resident.new()
	guard.name = "GuardArmsResident"
	add_child(guard)
	Client3D._mirror_hands(guard)
	_check(guard.slots.is_empty(), "no hands sent: its slots as they were")
	guard.hands = PackedStringArray(["spear", ""])
	guard.worn = "mail_armour"
	Client3D._mirror_hands(guard)
	_check(guard.slots.size() >= Items.HANDED and guard.slots[Items.RIGHT_HAND] == "spear" and guard.slots[Items.LEFT_HAND] == "",
			"its hands are its slots: the spear in the right (%s)" % [guard.slots])
	_check(Client3D.held_ids(guard) == ["spear", ""] and World.wielded(guard) == "spear",
			"held and struck with: the spear (%s, %s)" % [Client3D.held_ids(guard), World.wielded(guard)])
	_rig._sync_held(guard, puppet)
	var held := (sockets["hand_r"] as Node3D).get_node_or_null("Held") as Node3D
	_check(held != null, "drawn: the spear in its right hand")
	_rig._sync_worn(guard, puppet)
	var model := puppet.get_node("Body/Model") as Node3D
	_check(str(model.get_meta("worn", "")) == "mail_armour", "the mail worn (%s)" % model.get_meta("worn", ""))
	guard.down_until = World.tick + 100
	guard.downed_until = World.tick + 100
	_rig._sync_down(guard, puppet)
	_check(bool(puppet.get_meta("lying", false)), "downed: lying, as a downed player lies")
	guard.down_until = 0
	guard.downed_until = 0
	_rig._sync_down(guard, puppet)
	_check(not bool(puppet.get_meta("lying", false)), "helped up: rising")
	guard.free()
	_rig._sync_worn(player, puppet)
	_rig._process(0.0)


## Crouched (784 amended (3)): a player crouching stands in Crouch_Idle and, moving, creeps
## (Crouch_Fwd) at its own stride, the walk's pace times CREEP_STRIDE; stood up, neither.
func _test_crouch() -> void:
	print("
== a crouched player crouches, and creeps at its stride (784 amended (3)) ==")
	var player := _player()
	var puppet: Node3D = _rig._puppets.get(player.get_instance_id())
	var rig := puppet.get_meta("rig") as AnimRig
	_check(rig.has(Client3D.CLIP_CROUCH) and rig.has(Client3D.CLIP_CREEP), "the humanoid library has Crouch_Idle and Crouch_Fwd")
	puppet.set_meta("busy_until", 0)
	player.crouched = true
	_rig._process(0.0)
	_check(rig.base_clip() == Client3D.CLIP_CROUCH, "crouched and still: crouching (%s)" % rig.base_clip())
	# Moving one tile a second (World.crouch_pace's creep, 10 ticks a cell): the speed _animate reads.
	var pace := 1.0
	var now := Time.get_ticks_msec()
	puppet.set_meta("speed", pace)
	puppet.set_meta("last_at", puppet.position - Vector3(pace * 0.1, 0.0, 0.0))
	puppet.set_meta("last_ms", now - 100)
	_rig._animate(puppet)
	var walk := float(Client3D.paced(puppet.get_meta("gaits", Client3D.GAITS))[0][1])
	var want := pace / (walk * Client3D.CREEP_STRIDE * float(puppet.get_meta("pace", 1.0)))
	_check(rig.base_clip() == Client3D.CLIP_CREEP and absf(rig.speed() - want) < 0.05,
			"creeping a tile a second: Crouch_Fwd at its stride (x%.2f, want x%.2f)" % [rig.speed(), want])
	player.crouched = false
	puppet.set_meta("speed", 0.0)
	puppet.set_meta("last_at", puppet.position)
	_rig._process(0.0)
	_check(rig.base_clip() != Client3D.CLIP_CROUCH and rig.base_clip() != Client3D.CLIP_CREEP, "stood up: neither (%s)" % rig.base_clip())


## Teetering on a rim (783 amended): a body whose teeter is set turns to face the drop and rocks
## toward it, a person wheeling its arms (Teeter), a beast with no teeter clip scrabbling (its walk,
## quick); set back to ZERO it stands upright again with its own facing. The local player walking
## keeps their own facing.
func _test_teeter() -> void:
	print("
== a body on a rim faces the drop and rocks toward it (783 amended) ==")
	var player := _player()
	var puppet: Node3D = _rig._puppets.get(player.get_instance_id())
	var rig := puppet.get_meta("rig") as AnimRig
	var body := puppet.get_node("Body") as Node3D
	var facing := puppet.get_node_or_null("Facing") as Node3D
	_check(rig.has(Client3D.CLIP_TEETER), "the humanoid library has Teeter")
	var way := Vector2i(1, 0) if absf(angle_difference(body.rotation.y, 0.0)) > 1.0 else Vector2i(-1, 0)
	var drop_yaw := -Vector2(way).angle()
	player.teeter = way
	var toward := -1.0
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 400 or (toward <= sin(deg_to_rad(6.0)) and Time.get_ticks_msec() - start < 3000):
		await _frames(1)
		toward = maxf(toward, body.global_transform.basis.y.dot(Vector3(way.x, 0.0, way.y)))
	await _yaw_settles(body, drop_yaw, 0.1, 3.0, false)
	_check(absf(angle_difference(body.rotation.y, drop_yaw)) < 0.1, "teetering: the model faces the drop (%.2f, the drop %.2f)" % [body.rotation.y, drop_yaw])
	_check(toward > sin(deg_to_rad(6.0)), "it rocks out over the drop (%.1f degrees at most)" % rad_to_deg(asin(clampf(toward, -1.0, 1.0))))
	_check(rig.base_clip() == Client3D.CLIP_TEETER, "a person wheels its arms (%s)" % rig.base_clip())
	if _rig._local_player() == player:
		# A walk key held, through main's own (--test-walk's) keys; World doesn't tick here, so
		# nobody walks (checked).
		var tile := player.tile
		Net.test_walk = [{"keys": "w", "seconds": 5.0}]
		_main.set("_walk_index", -1)
		await _frames(10)
		_check(str(_main.call("_held_key_names")) == "w" and (facing == null or absf(angle_difference(body.rotation.y, facing.rotation.y)) < 0.05),
				"the local player pressing a way keeps their own facing, teetering or not (%.2f, its facing %.2f)"
				% [body.rotation.y, facing.rotation.y if facing != null else 0.0])
		Net.test_walk = []
		_main.set("_walk_index", -1)
		await _frames(1)
		_check(player.tile == tile, "(and nobody walked: World doesn't tick here)")
	else:
		_check(false, "the test's player is the local one")
	player.teeter = Vector2i.ZERO
	start = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 600:
		await _frames(1)
	_check(is_zero_approx(body.rotation.x) and is_zero_approx(body.rotation.z), "off the rim: upright again")
	if facing != null:
		await _yaw_settles(body, facing.rotation.y, 0.05, 3.0, false)
	_check(facing == null or absf(angle_difference(body.rotation.y, facing.rotation.y)) < 0.05,
			"and turned back to its own facing (%.2f, its facing %.2f)" % [body.rotation.y, facing.rotation.y if facing != null else 0.0])
	_check(rig.base_clip() != Client3D.CLIP_TEETER, "no longer wheeling (%s)" % rig.base_clip())

	var boar := _spawn_imp(Vector2i(9, 4), "boar")
	await _frames(2)
	_rig._process(0.0)
	var beast: Node3D = _rig._puppets.get(boar.get_instance_id())
	var view := beast.get_meta("creature_view", null) as CreatureView if beast != null else null
	if view == null or view.rig == null:
		_check(false, "a boar drawn by its CreatureView")
		World.despawn(boar)
		return
	var beast_body := beast.get_node("Body") as Node3D
	boar.teeter = Vector2i(0, 1)
	toward = -1.0
	start = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 400 or (toward <= sin(deg_to_rad(6.0)) and Time.get_ticks_msec() - start < 3000):
		await _frames(1)
		toward = maxf(toward, beast_body.global_transform.basis.y.dot(Vector3(0.0, 0.0, 1.0)))
	await _yaw_settles(beast_body, -Vector2(0, 1).angle(), 0.1, 3.0, false)
	_check(not view.clips.has("teeter") and view.rig.base_clip() == view.clips["walk"]
			and is_equal_approx(view.rig.speed(), CreatureView.TEETER_PACE),
			"a beast with no teeter clip scrabbles: its walk, quick (%s x%.2f)" % [view.rig.base_clip(), view.rig.speed()])
	_check(toward > sin(deg_to_rad(6.0)) and absf(angle_difference(beast_body.rotation.y, -Vector2(0, 1).angle())) < 0.1,
			"and faces and rocks toward the drop too")
	boar.teeter = Vector2i.ZERO
	World.despawn(boar)
	await _frames(2)


func _test_creature_tells() -> void:
	print("
== a beast's tells play timed to its telegraph; asleep it sleeps, winded it heaves (780 amended (6)) ==")
	var boar := _spawn_imp(Vector2i(9, 4), "boar")
	await _frames(2)
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets.get(boar.get_instance_id())
	var view := puppet.get_meta("creature_view", null) as CreatureView if puppet != null else null
	if view == null or view.rig == null:
		_check(false, "a boar drawn by its CreatureView")
		World.despawn(boar)
		return
	var rig := view.rig
	# No swipe clip: the body coils over the tell, no clip slid into (780 amended (17), the old grey's lunge).
	var told := view.tell("swipe", 0.6, 1)
	_check(told and not rig.striking() and view._coil != null and view._coil.is_running(),
			"a slot with no swipe: it coils, no clip struck (%s)" % told)
	view.tell_over(1, false)
	boar.pose = Monster.Pose.SIT
	view.frame(puppet, boar)
	_check(rig.base_clip() == view.clips["graze"], "no sleep in the slot: sitting grazes, as before")
	boar.pose = Monster.Pose.STAND
	var library := rig.player.get_animation_library("")
	for clip: String in ["swipe", "slam", "charge_tell", "roar", "sleep", "winded"]:
		var copy := rig.player.get_animation(view.clips["attack" if clip in ["swipe", "slam", "charge_tell", "roar"] else "idle"]).duplicate() as Animation
		copy.length = 1.1 if clip == "swipe" else 0.8
		copy.loop_mode = Animation.LOOP_LINEAR if clip in CreatureView.LOOPED else Animation.LOOP_NONE
		library.add_animation("Tell_" + clip, copy)
		view.clips[clip] = "Tell_" + clip
	view._contact["swipe"] = 0.545
	boar.pose = Monster.Pose.SIT
	view.frame(puppet, boar)
	_check(rig.base_clip() == view.clips["sleep"], "asleep (Pose SIT) with a sleep: sleeping, not grazing")
	boar.pose = Monster.Pose.STAND
	boar.winded = true
	view.frame(puppet, boar)
	_check(rig.base_clip() == view.clips["winded"], "winded and standing: heaving")
	boar.winded = false
	view.frame(puppet, boar)
	_check(rig.base_clip() == view.clips["idle"], "not winded: idle again")
	var speed_for := func(contact: float, lands_in: float) -> float:
		return clampf(contact / lands_in, ArtKit.feel("anim_rig.strike_speed_min", AnimRig.STRIKE_SPEED_MIN),
				ArtKit.feel("anim_rig.strike_speed_max", AnimRig.STRIKE_SPEED_MAX))
	_check(view.tell("swipe", 0.6, 7) and rig.striking() and rig.playing() == view.clips["swipe"]
			and is_equal_approx(rig.speed(), speed_for.call(1.1 * 0.545, 0.6)),
			"a swipe telegraphed to land in 0.6 s: its swipe, its contact (0.545 of 1.1 s) landing then (speed %.2f)" % rig.speed())
	view.tell_over(8, false)
	_check(rig.striking(), "another telegraph's end leaves it be")
	view.tell_over(7, false)
	_check(not rig.striking(), "its telegraph called off (stunned mid-tell): the tell stops")
	_check(view.tell("charge", 0.8, 9) and rig.playing() == view.clips["charge_tell"]
			and is_equal_approx(rig.speed(), speed_for.call(0.8, 0.8)),
			"a charge's telegraph: its charge_tell, all wind-up, ending as the rush begins (speed %.2f)" % rig.speed())
	var pose_x := (puppet.get_node("Body/Pose") as Node3D).position.x
	view.charge()
	_check(rig.playing() == view.clips["charge_tell"] and view._charge_until >= view._tell_until + int(CreatureView.CHARGE_SECONDS * 1000.0) - 5,
			"the charge cry while telling: the tell plays on, the run after it")
	await _frames(3)
	_check(is_equal_approx((puppet.get_node("Body/Pose") as Node3D).position.x, pose_x), "no lunge for a beast with a tell")
	view.tell_over(9, true)
	_check(rig.playing() == view.clips["charge_tell"], "landed: its tell plays out")
	view.unwind()
	view.roar()
	_check(rig.striking() and rig.playing() == view.clips["roar"], "a roar cried: its roar")
	view.unwind()
	# Through the client: the telegraph message's source and lands tick.
	var data := {"id": 11, "source": str(boar.get_path()), "kind": "slam", "lands_tick": World.tick + 12}
	_rig.creature_tell(11, data)
	_check(rig.playing() == view.clips["slam"] and _rig._tells.get(11) == puppet, "Client3D.creature_tell: the slam on the puppet the message names")
	_rig.creature_tell_over(11, false)
	_check(not rig.striking() and not _rig._tells.has(11), "creature_tell_over: called off, stopped and forgotten")
	World.despawn(boar)
	await _frames(2)

## A deer down (764, pc-character's side; enemy-ai's Monster.Pose.DOWN): lain on its belly over
## its idle (creature_life.gd: the legs folded under, the body lowered to the ground, the neck
## up), eased down and up; no flinch lying; killed lying it unfolds as its death plays; first seen
## down it lies at once. The stag, boar and rabbit fold by the same table.
func _test_creature_down() -> void:
	print("
== a deer down lies on its belly, alive (764, pc-character's side) ==")
	_check(Monster.Pose.DOWN == 2, "Monster.Pose.DOWN is 2, as enemy-ai's 764 amended sends it (%d)" % Monster.Pose.DOWN)
	for kind: String in ["stag", "boar", "rabbit", "deer"]:
		var animal := _spawn_imp(Vector2i(9, 4), kind)
		await _frames(2)
		_rig._process(0.0)
		var puppet: Node3D = _rig._puppets.get(animal.get_instance_id())
		var view := puppet.get_meta("creature_view", null) as CreatureView if puppet != null else null
		if view == null or view.rig == null or view._life == null:
			_check(false, "a %s drawn by its CreatureView with a life on its skeleton" % kind)
			World.despawn(animal)
			continue
		var life := view._life
		var skeleton := life.get_skeleton()
		var fronts := life.legs.filter(func(leg: Dictionary) -> bool: return leg["front"]).size()
		var height := ArtKit.size("creature." + kind).y
		_check(life.legs.size() == 4 and fronts == 2 and not life.necks.is_empty() and life.drop.length() > 0.0,
				"%s: four legs (two front), a neck, lowered lying (%d legs, %d front, %d necks, root %s)" % [
					kind, life.legs.size(), fronts, life.necks.size(), skeleton.get_bone_name(life.root)])
		# The folded pose, measured: the trunk's underside on the ground, each lower leg along it,
		# the neck up.
		var meshes := skeleton.find_children("*", "MeshInstance3D", false, false)
		var to_art := life.to_art
		skeleton.reset_bone_poses()
		var standing := life._lowest(skeleton, meshes[0], to_art)
		life.lie(skeleton, 1.0, -1000.0)
		var lying := life._lowest(skeleton, meshes[0], to_art, life.trunk_skip(skeleton)) - life.TRUNK_CLEAR
		var flat := true
		for leg: Dictionary in life.legs:
			flat = flat and absf(skeleton.get_bone_global_pose(leg["bones"][-1]).basis.y.normalized().dot(life.up)) < 0.45
		var neck_up := skeleton.get_bone_global_pose(life.necks[0]).basis.y.normalized().dot(life.up)
		skeleton.reset_bone_poses()
		_check(absf(lying - standing) < 0.03 * height + 0.01 and flat and neck_up > 0.6,
				"%s lying: its trunk's underside on the ground (standing's lowest %.3f, the trunk's lying %.3f), each lower leg along the ground, the neck up (%.2f)" % [
					kind, standing, lying, neck_up])
		if kind != "deer":
			World.despawn(animal)
			await _frames(2)
			continue
		var rig := view.rig
		view.frame(puppet, animal)
		_check(rig.playing() == view.clips["idle"] and life.weight == 0.0, "standing: idle, not lying")
		animal.pose = Monster.Pose.DOWN
		view.frame(puppet, animal)
		_check(rig.base_clip() == view.clips["idle"] and life.weight < 0.05, "down: lying down begun over its idle (%.2f)" % life.weight)
		var tipped := (puppet.get_node("Body/Pose") as Node3D).transform
		view.hit()
		_check((puppet.get_node("Body/Pose") as Node3D).transform.is_equal_approx(tipped) and not rig.busy(), "a blow lying: no flinch, no hit clip")
		view._down_ms -= int(CreatureView.DOWN_SECONDS * 1000.0) + 50
		view.frame(puppet, animal)
		_check(is_equal_approx(life.weight, 1.0), "lain after %.1f s" % CreatureView.DOWN_SECONDS)
		animal.pose = Monster.Pose.STAND
		view.frame(puppet, animal)
		_check(life.weight > 0.95, "up again: getting up from lying (%.2f)" % life.weight)
		view._down_ms -= int(CreatureView.UP_SECONDS * 1000.0) + 50
		view.frame(puppet, animal)
		_check(life.weight == 0.0 and rig.playing() == view.clips["idle"], "stood after %.1f s: idle" % CreatureView.UP_SECONDS)
		animal.pose = Monster.Pose.DOWN
		view.frame(puppet, animal)
		view._down_ms -= 5000
		view.frame(puppet, animal)
		_check(view.die() > 0.0 and rig.playing() == view.clips["death"] and life.weight > 0.9, "killed lying: its death plays as it unfolds")
		await get_tree().create_timer(CreatureView.DIE_UNFOLD_SECONDS + 0.1).timeout
		_check(life.weight == 0.0, "dead: unfolded, still")
		World.despawn(animal)
		await _frames(2)
	var seen_down := _spawn_imp(Vector2i(9, 4), "deer")
	seen_down.pose = Monster.Pose.DOWN
	await _frames(2)
	_rig._process(0.0)
	var seen: Node3D = _rig._puppets.get(seen_down.get_instance_id())
	var seen_view := seen.get_meta("creature_view", null) as CreatureView if seen != null else null
	_check(seen_view != null and is_equal_approx(seen_view._life.weight, 1.0), "first seen down: lying at once")
	World.despawn(seen_down)
	await _frames(2)


# --- helpers ------------------------------------------------------------------

## The doors' leaves swung and shown, as some frames would, without their
## sounds (one playing at quit holds its stream).
func _settle_doors() -> void:
	_rig._door_open.clear()
	for i in 20:
		await get_tree().process_frame
		_rig._process(0.05)


## [param entity]'s signals' connections to the rig, undone (a test puppet's).
func _disconnect_rig(entity: GridEntity) -> void:
	for signal_info: Dictionary in entity.get_signal_list():
		for connection: Dictionary in entity.get_signal_connection_list(signal_info["name"]):
			if (connection["callable"] as Callable).get_object() == _rig:
				entity.disconnect(signal_info["name"], connection["callable"])


## The sound sets [param action] made the view play.
func _heard(action: Callable) -> Array[String]:
	var before := _rig.sfx.played.size()
	action.call()
	var sets: Array[String] = []
	for entry: Array in _rig.sfx.played.slice(before):
		sets.append(entry[0])
	return sets


func _swing_pitch(entity: GridEntity) -> float:
	var before := _rig.sfx.get_child_count()
	entity._world_swung(Vector2i(1, 0))
	# The pitch before the jitter, which could swap two close ones; a voice
	# beside the swing is skipped.
	for i: int in range(before, _rig.sfx.get_child_count()):
		var player := _rig.sfx.get_child(i)
		if str(player.get_meta("slot", "")).begins_with("sfx.swing"):
			return float(player.get_meta("pitch"))
	return 0.0


func _bar(entity: GridEntity) -> MeshInstance3D:
	var puppet: Node3D = _rig._puppets.get(entity.get_instance_id())
	return puppet.get_node_or_null("HpBar") as MeshInstance3D if puppet != null else null


func _alpha(bar: MeshInstance3D) -> float:
	return float((bar.material_override as ShaderMaterial).get_shader_parameter("alpha"))


func _fill(bar: MeshInstance3D) -> float:
	return float((bar.material_override as ShaderMaterial).get_shader_parameter("fill"))


func _colour(bar: MeshInstance3D) -> Color:
	return (bar.material_override as ShaderMaterial).get_shader_parameter("fill_color")


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


## Frames till the rigs' clock (AnimRig.now_msec) reaches [param msec]: a timer here runs on the
## engine's scaled time, not the clock a rig's strike is timed by.
func _until_msec(msec: int) -> void:
	while AnimRig.now_msec() < msec:
		await get_tree().process_frame


## Long enough for a bar to fade all the way in or out.
func _fade() -> void:
	await get_tree().create_timer(1.0 / Client3D.HP_BAR_FADE + 0.1).timeout


func _test_worn_gear() -> void:
	print("\n== worn gear on the body (788's worn slots): hood, cloak and boots as parts, the hat, amulet and charm on sockets ==")
	var player := _player()
	if player == null:
		_check(false, "a player to dress")
		return
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets[player.get_instance_id()]
	var look := puppet.get_meta("look") as PersonLook
	var model := puppet.get_node_or_null("Body/Model") as Node3D
	var sockets: Dictionary = puppet.get_meta("sockets", {})
	_check(model != null and sockets.has("neck") and sockets.has("belt_c") and sockets.has("head")
			and model.find_child("Worn_Hood", true, false) != null and model.find_child("Worn_Cloak", true, false) != null
			and model.find_child("Worn_Boots", true, false) != null, "a person's body has the worn parts and the neck and belt_c sockets")
	if model == null or not sockets.has("neck"):
		return
	# Where the sockets sit on the body: the neck's at the throat, the belt's at the waist, both on its front.
	var feet := puppet.global_position
	var neck := (sockets["neck"] as Node3D).global_position - feet
	var belt := (sockets["belt_c"] as Node3D).global_position - feet
	var front := (model.global_basis * Vector3(0, 0, 1)).normalized()
	var body_y := model.global_basis.y.length()
	_check(neck.y > 1.2 * body_y and neck.y < 1.6 * body_y and belt.y > 0.85 * body_y and belt.y < 1.15 * body_y
			and Vector3(neck.x, 0, neck.z).dot(front) > 0.03 and Vector3(belt.x, 0, belt.z).dot(front) > 0.05,
			"the neck socket at the throat (%.2f m up), belt_c on the belt (%.2f m up), both on the front" % [neck.y, belt.y])
	var slots := player.slots
	while slots.size() < Items.CARRIED:
		slots.append("")
	var was := slots.duplicate()
	var visible := func(name: String) -> bool:
		var mesh := model.find_child(name, true, false) as MeshInstance3D
		return mesh != null and mesh.visible
	var hair := func() -> bool:
		return PersonLook.HAIR_PARTS.values().any(func(n: String) -> bool: return n != "" and visible.call(n))
	look.parts.append("Hair_Cropped")  # Hair, to be hooded.
	look.apply(model, puppet.get_meta("tint", Color.WHITE))
	model.set_meta("worn_gear", "")
	slots[Items.HEAD] = "hood"
	slots[Items.FEET] = "soft_boots"
	slots[Items.NECK] = "encolpion_amulet"
	slots[Items.CHARM] = "bear_claw_charm"
	player.slots = slots
	_rig._process(0.0)
	var hood := model.find_child("Worn_Hood", true, false) as MeshInstance3D
	var boots := model.find_child("Worn_Boots", true, false) as MeshInstance3D
	_check(hood.visible and hood.get_instance_shader_parameter("tunic") == Items.color_of("hood") and not hair.call()
			and boots.visible and boots.get_instance_shader_parameter("tunic") == Items.color_of("soft_boots") and not visible.call("Worn_Cloak"),
			"the hood up in its colour, the hair under it hidden; the soft boots on; no cloak")
	var amulet := (sockets["neck"] as Node3D).get_node_or_null("Worn") as Node3D
	var charm := (sockets["belt_c"] as Node3D).get_node_or_null("Worn") as Node3D
	_check((amulet != null) == (ArtKit.has("worn.encolpion_amulet") or ArtKit.has("item.encolpion_amulet"))
			and (charm != null) == ArtKit.has("item.bear_claw_charm"),
			"the amulet at the neck (%s), the charm at the belt (%s), each as its art is made" % [amulet != null, charm != null])
	slots[Items.HEAD] = "felt_hat"
	player.slots = slots
	_rig._process(0.0)
	var hat := (sockets["head"] as Node3D).get_node_or_null("Worn") as Node3D
	_check(not hood.visible and hair.call() and (hat != null) == ArtKit.has("worn.felt_hat"), "the hood off for the felt hat: the hair again, the hat on the head")
	# Items' cloak row (788 amended): its look draws the long cloak in its colour, over the garb's cape.
	look.parts.append("Cape")
	look.apply(model, puppet.get_meta("tint", Color.WHITE))
	model.set_meta("worn_gear", "")
	slots[Items.BACK] = "cloak"
	player.slots = slots
	_rig._process(0.0)
	var cloak := model.find_child("Worn_Cloak", true, false) as MeshInstance3D
	var cape := model.find_child("Cape", true, false) as MeshInstance3D
	_check(str(Items.worn_of("cloak").get("look", "")) == "cloak" and cloak.visible
			and cloak.get_instance_shader_parameter("tunic") == Items.color_of("cloak") and cape != null and not cape.visible,
			"the cloak row on the back: the long cloak in its colour, the garb's cape hidden")
	look.parts.erase("Cape")
	# Items' string of amber beads at the neck (9603f43af), drawn as art-kit's worn.amber_beads on the
	# neck socket: that piece (its size the slot's), not the pack item.
	slots[Items.NECK] = "amber_beads"
	player.slots = slots
	_rig._process(0.0)
	var beads := (sockets["neck"] as Node3D).get_node_or_null("Worn") as Node3D
	var beads_size := Vector3.ZERO
	if beads != null:
		for mesh: MeshInstance3D in beads.find_children("*", "MeshInstance3D", true, false):
			beads_size = mesh.get_aabb().size
	var beads_meant := Vector3(0.109, 0.104, 0.128)  # art/kit/slots.json's worn.amber_beads size
	_check(not ArtKit.has("worn.amber_beads") or (beads != null and (beads_size - beads_meant).abs().length() < 0.03),
			"the amber beads at the neck, as worn.amber_beads (%s, %s)" % [beads != null, beads_size])
	player.slots = was
	_rig._process(0.0)
	_check(not hood.visible and not boots.visible and not cloak.visible and (sockets["head"] as Node3D).get_node_or_null("Worn") == null
			and (sockets["neck"] as Node3D).get_node_or_null("Worn") == null and hair.call(), "all off: the look's own again")
	look.parts.erase("Hair_Cropped")
	look.apply(model, puppet.get_meta("tint", Color.WHITE))
	model.set_meta("worn_gear", "")
	_rig._process(0.0)


func _test_satchel_worn() -> void:
	print("
== the satchel worn (819 amended): its strap over what is worn, the bag on its socket at the strap's ends ==")
	var player := _player()
	if player == null:
		_check(false, "a player to dress")
		return
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets[player.get_instance_id()]
	var look := puppet.get_meta("look") as PersonLook
	var model := puppet.get_node_or_null("Body/Model") as Node3D
	var sockets: Dictionary = puppet.get_meta("sockets", {})
	var straps := ["Worn_Strap", "Worn_Strap_Over", "Worn_Strap_Sleeved", "Worn_Strap_Cape", "Worn_Strap_Plate"]
	_check(model != null and straps.all(func(n: String) -> bool: return model.find_child(n, true, false) != null)
			and model.find_child("Worn_Cloak_Strapped", true, false) != null, "a person's body has the five straps and the strapped cloak")
	if model == null:
		return
	var slots := player.slots
	while slots.size() < Items.CARRIED:
		slots.append("")
	var was := slots.duplicate()
	var keys_were := look.keys.duplicate()
	var shown := func() -> Array:
		var out := []
		for n: String in straps + ["Worn_Cloak", "Worn_Cloak_Strapped"]:
			var mesh := model.find_child(n, true, false) as MeshInstance3D
			if mesh != null and mesh.visible:
				out.append(n)
		return out
	var feet := puppet.global_position
	var front := (model.global_basis * Vector3(0, 0, 1)).normalized()
	var right := (model.global_basis * Vector3(-1, 0, 0)).normalized()
	var body_y := model.global_basis.y.length()
	# The lantern (451) where it has always hung, the package being off: not a millimetre moved.
	var lamp := (sockets["belt_r"] as Node3D).get_node_or_null("LanternBody") as Node3D if sockets.get("belt_r") is Node3D else null
	_check(lamp != null and lamp.position == Vector3.ZERO, "no satchel: the lantern where 451 hung it (%s)" % [lamp.position if lamp != null else "none"])
	var lamp_at := lamp.global_position if lamp != null else Vector3.ZERO
	slots[Items.BAG] = "satchel"
	player.slots = slots
	_rig._process(0.0)
	if lamp != null:
		var moved := lamp.global_position - lamp_at
		_check(lamp.position == Client3D.LANTERN_BY_BAG and moved.dot(front) > 0.04 * body_y and absf(moved.dot(right)) < 0.02 * body_y,
				"a satchel worn: the lantern forward of the bag (%.3f m forward, %.3f out)" % [moved.dot(front), moved.dot(right)])
	var strap := model.find_child("Worn_Strap", true, false) as MeshInstance3D
	var socket := sockets.get("bag") as Node3D
	_check(shown.call() == ["Worn_Strap"] and strap.get_instance_shader_parameter("tunic") == Items.color_of("satchel"),
			"the satchel on: its strap over the tunic, in its colour (%s)" % [shown.call()])
	_check(socket != null, "the bag socket made")
	if socket == null:
		player.slots = was
		_rig._process(0.0)
		return
	var bag := socket.global_position - feet
	var level := Vector3(bag.x, 0, bag.z)
	_check(bag.y > 0.85 * body_y and bag.y < 1.1 * body_y and level.dot(right) > 0.03 and level.dot(front) < -0.10,
			"the bag socket at the right hip's back quarter, the strap's ends (%.2f m up, %.2f right, %.2f behind)" % [bag.y, level.dot(right), -level.dot(front)])
	var bag_art := socket.get_node_or_null("Worn") as Node3D
	_check((bag_art != null) == (ArtKit.has("worn.satchel") or ArtKit.has("item.satchel")), "the bag's art on its socket as it is made (%s)" % [bag_art != null])
	_check(socket.global_basis.y.normalized().dot(model.global_basis.y.normalized()) > 0.99
			and socket.global_basis.z.normalized().dot(level.normalized()) > 0.5, "the bag's frame level, +y up and +z out from the body")
	# A heavy body: the strap's ends further out, the socket with them (its shape keys as they stand).
	look.keys["heavy"] = 1.0
	look.apply(model, puppet.get_meta("tint", Color.WHITE))
	model.set_meta("worn_gear", "")
	_rig._process(0.0)
	var heavy := socket.global_position - feet
	var out_by := Vector3(heavy.x, 0, heavy.z).length() - level.length()
	_check(out_by > 0.005 and out_by < 0.06, "a heavy body's bag further out with its strap's ends (%.3f m)" % out_by)
	look.keys = keys_were.duplicate()
	look.apply(model, puppet.get_meta("tint", Color.WHITE))
	model.set_meta("worn_gear", "")
	var worn_was: String = player.worn
	for row: Array in [["leather_armour", "Worn_Strap_Over"], ["mail_armour", "Worn_Strap_Sleeved"], ["plate_armour", "Worn_Strap_Plate"]]:
		player.worn = row[0]
		_rig._process(0.0)
		_check(shown.call() == [row[1]], "in %s, the strap over it: %s (%s)" % [row[0], row[1], shown.call()])
	player.worn = worn_was
	slots[Items.BACK] = "cloak"
	player.slots = slots
	_rig._process(0.0)
	var strapped := model.find_child("Worn_Cloak_Strapped", true, false) as MeshInstance3D
	_check(shown.call() == ["Worn_Strap", "Worn_Cloak_Strapped"] and strapped.get_instance_shader_parameter("tunic") == Items.color_of("cloak"),
			"under a cloak: the strapped cloak in its colour over the strap, not the plain one (%s)" % [shown.call()])
	slots[Items.BAG] = ""
	player.slots = slots
	_rig._process(0.0)
	_check(shown.call() == ["Worn_Cloak"] and socket.get_node_or_null("Worn") == null, "the satchel off: the plain cloak again, no strap, the socket empty (%s)" % [shown.call()])
	_check(lamp == null or (lamp.position == Vector3.ZERO and lamp.global_position.is_equal_approx(lamp_at)), "the satchel off: the lantern back where 451 hung it")
	player.slots = was
	_rig._process(0.0)
	_check(shown.call().is_empty(), "all off")


func _test_worn() -> void:
	print("
== armour worn (items' 622): its look's covering on the body, in the item's colour, the garb under it hidden ==")
	var player := _player()
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets[player.get_instance_id()]
	var look := puppet.get_meta("look") as PersonLook
	var model := puppet.get_node_or_null("Body/Model") as Node3D
	var shown := func() -> Array:
		return model.find_children("Armour_*", "MeshInstance3D", true, false).filter(func(m: MeshInstance3D) -> bool: return m.visible).map(
				func(m: MeshInstance3D) -> String: return String(m.name))
	_check(model != null and shown.call().is_empty() and player.worn == "", "nothing worn: no covering")
	if model == null:
		return
	look.parts.append_array(["Vest", "Cape"])  # A vest and a cape, to be covered.
	look.apply(model, puppet.get_meta("tint", Color.WHITE))
	var vest := model.find_child("Vest", true, false) as MeshInstance3D
	var cape := model.find_child("Cape", true, false) as MeshInstance3D
	var each := []
	for id: String in ["leather_armour", "mail_armour", "plate_armour", "robes"]:
		player.worn = id
		_rig._process(0.0)
		var part := str(PersonLook.ARMOUR_PARTS[Items.armour_of(id)["look"]])
		var mesh := model.find_child(part, true, false) as MeshInstance3D
		each.append([id, shown.call(), mesh != null and mesh.get_instance_shader_parameter("tunic") == Items.color_of(id), vest.visible or cape.visible])
	_check(each.all(func(e: Array) -> bool: return e[1].size() == 1 and e[2] and not e[3]),
			"each armour its own covering, in its colour, over the vest and the cape (%s)" % [each])
	player.worn = ""
	_rig._process(0.0)
	_check(shown.call().is_empty() and vest.visible and cape.visible, "taken off: no covering, the vest and the cape again")
	var said := PersonLook.make("seed=7 worn=robes")
	_check(said.worn == "robes" and PersonLook.make("seed=7 worn=gown").worn == "", "a look's worn= word (a resident's), a known look only")
	said.wear(model, "")
	_check(shown.call() == ["Armour_Robes"] and (model.find_child("Armour_Robes", true, false) as MeshInstance3D).get_instance_shader_parameter("tunic")
			== Items.color_of(PersonLook.armour_kind("robes")), "a worn= word: that look, in its kind's colour")
	look.parts.erase("Vest")
	look.parts.erase("Cape")
	look.apply(model, puppet.get_meta("tint", Color.WHITE))
	model.set_meta("worn", "")



func _test_asleep() -> void:
	print("
== a companion asleep on the watch (621 amended): on her side, her front to the fire, a slow breath; awake, standing ==")
	# A companion's sleep drawn on the player's puppet (as _test_visible_work draws a resident's work).
	var player := _player()
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets[player.get_instance_id()]
	var rig := puppet.get_meta("rig") as AnimRig
	var body := puppet.get_node("Body") as Node3D
	var model := body.get_node("Model") as Node3D
	var her := Companion.new()
	her.name = "SleepTestCompanion"
	her.tile = player.tile
	puppet.set_meta("speed", 0.0)
	puppet.set_meta("shuffle_until", 0)
	var fire := her.tile + Vector2i(1, 1)
	var had := World.is_fire(fire)
	World._fire[fire] = true
	var draw := func() -> float:
		_rig._sync_work(her, puppet)
		_rig._animate(puppet)
		var yaw := Client3D._sleeping_yaw(her, 0.0)
		_rig._lay(puppet, body, yaw)
		body.rotation.y = yaw
		return yaw
	her.asleep = true
	var yaw: float = draw.call()
	_check(rig.base_clip() == "Sleep_Down", "falling asleep: she lies down first (751) (%s)" % rig.base_clip())
	puppet.set_meta("busy_until", 0)  # The lie-down done.
	yaw = draw.call()
	# Her front: the model's +X (Sleep_Side lies on her left side, her front where her left hand was), flat.
	var front := model.global_transform.basis.x
	front = Vector3(front.x, 0.0, front.z).normalized()
	var to_fire := Vector3(fire.x - her.tile.x, 0.0, fire.y - her.tile.y).normalized()
	_check(rig.base_clip() == "Sleep_Side" and str(puppet.get_meta("work", "")) == "sleep_side",
			"asleep: Sleep_Side, as her work (%s, %s)" % [rig.base_clip(), puppet.get_meta("work", "")])
	_check(front.dot(to_fire) > 0.99, "her front to the fire a cell off diagonally (%s, %s; yaw %.2f)" % [front, to_fire, yaw])
	var clip := rig.player.get_animation(rig._name("Sleep_Side")) if rig.has("Sleep_Side") else null
	_check(clip != null and absf(clip.length - 5.0) < 0.05 and clip.loop_mode != Animation.LOOP_NONE, "the breath slow: a 5 s loop")
	World._fire.erase(fire)
	_check(is_equal_approx(Client3D._sleeping_yaw(her, 0.5), 0.5), "no fire near: her own facing")
	her.asleep = false
	draw.call()
	_check(rig.base_clip() == Client3D.CLIP_SLEEP_UP, "woken: she gets up (751) (%s)" % rig.base_clip())
	puppet.set_meta("busy_until", 0)  # The get-up done.
	puppet.set_meta("rising_until", 0)
	draw.call()
	_check(rig.base_clip() != "Sleep_Side" and str(puppet.get_meta("work", "")) == "" and body.position == Vector3.ZERO
			and is_equal_approx(model.rotation.y, float(puppet.get_meta("faces"))), "awake: standing again (%s)" % rig.base_clip())
	if had:
		World._fire[fire] = true
	her.free()
	_rig._sync_work(player, puppet)
	_rig._process(0.0)


func _player() -> Player:
	for entity in World.get_entities():
		if entity is Player and entity.spawned:
			return entity
	return null


func _companion() -> Companion:
	for entity in World.get_entities():
		if entity is Companion and entity.spawned:
			return entity
	return null


## Which way a model's toes point from its feet, on the ground, unit: its
## front, whatever axis it was modelled facing.
func _toes_ahead(puppet: Node3D) -> Vector2:
	var skeleton := puppet.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var ahead := Vector3.ZERO
	for side in ["Left", "Right"]:
		var foot := skeleton.global_transform * skeleton.get_bone_global_rest(skeleton.find_bone(side + "Foot")).origin
		var toes := skeleton.global_transform * skeleton.get_bone_global_rest(skeleton.find_bone(side + "Toes")).origin
		ahead += toes - foot
	return Vector2(ahead.x, ahead.z).normalized()


## "Blows you can see" (combat's package; enemy-ai's slide diagnosis, Jeff: "enemies tend to look
## like they are sliding into you and then no visible swing"): a body struck while it moves walks
## its gait under the blow; a struck body flinches as the drawn blow lands, not at its news.
## 869 (Jeff, 11-11: "walking around looks like skipping"; Wren's clip changed 72 times a minute as
## she stopped and went on): the gait pick holds through a gap. Driven frame by frame (60 a second) on
## the rigs' clock, the player's body moved at set speeds: a start from standing walks at once and is
## jogging within 0.5 s; a 0.25 s pause mid-jog keeps the jog, no clip change through it; speeds
## alternating across the walk's and the sprint's changes every 0.25 s change gait at most once each;
## a real stop stands, not before STOP_HOLD and by 0.4 s; a burst from a walk jogs within 0.1 s.
func _test_gait_holds() -> void:
	print("\n== 869: the gait holds through a pause, never flaps, stops and bursts at once ==")
	var player := _player()
	if player == null:
		_check(false, "a player to walk")
		return
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets[player.get_instance_id()]
	var rig := puppet.get_meta("rig") as AnimRig
	var kept := {}
	for key: String in ["busy_until", "speed", "gait_speed", "last_at", "last_ms", "still_since", "gait_want", "gait_want_at"]:
		kept[key] = puppet.get_meta(key) if puppet.has_meta(key) else null
	var was_at := puppet.position
	var pace: float = puppet.get_meta("pace", 1.0)
	var gaits := (Client3D.paced(puppet.get_meta("gaits", Client3D.GAITS)) as Array).map(func(gait: Array) -> String: return str(gait[0]))
	AnimRig._clock_movie = 1
	AnimRig._clock_frame = Engine.get_process_frames()
	AnimRig._clock_msec = Time.get_ticks_msec()
	puppet.set_meta("busy_until", 0)
	for key: String in ["speed", "gait_speed", "still_since", "gait_want"]:
		puppet.remove_meta(key)
	puppet.set_meta("last_at", puppet.position)
	puppet.set_meta("last_ms", AnimRig._clock_msec)
	rig.loop(Client3D.CLIP_IDLE, 1.0)
	# [speed m/s at pace 1, seconds] in order; each frame's clip.
	var drive := func(legs: Array) -> Array:
		var seen := []
		for leg: Array in legs:
			for i in int(roundf(float(leg[1]) * 60.0)):
				AnimRig._clock_frame = Engine.get_process_frames()
				AnimRig._clock_msec += 16
				puppet.position += Vector3(float(leg[0]) * pace * 0.016, 0.0, 0.0)
				_rig._animate(puppet)
				seen.append(rig.base_clip())
		return seen
	var changes := func(seen: Array) -> int:
		var n := 0
		for i in range(1, seen.size()):
			n += 1 if seen[i] != seen[i - 1] else 0
		return n
	var started: Array = drive.call([[4.0, 0.6]])
	var first: String = started[0]
	_check(first in gaits and started[30] == gaits[1], "a start from standing goes at once (%s on its first frame) and jogs within 0.5 s (%s)" % [first, started[30]])
	drive.call([[4.0, 1.0]])
	var paused: Array = drive.call([[0.0, 0.25], [4.0, 1.0]])
	_check(changes.call(paused) == 0 and paused[0] == gaits[1], "a 0.25 s pause mid-jog keeps the jog (%d changes, %s)" % [changes.call(paused), paused[0]])
	var low := []
	var high := []
	for i in 6:
		low.append_array([[1.2, 0.25], [2.6, 0.25]])
		high.append_array([[4.0, 0.25], [6.2, 0.25]])
	var flap_low: Array = drive.call(low)
	drive.call([[4.5, 1.0]])
	var flap_high: Array = drive.call(high)
	_check(changes.call(flap_low) <= 1 and changes.call(flap_high) <= 1,
			"speeds alternating across a change every 0.25 s: at most one change each (walk and jog %d, jog and sprint %d)" % [changes.call(flap_low), changes.call(flap_high)])
	# A host's own body at a fractional pace (companions' heel, 2.5 ticks a cell): its drawn place stands a
	# frame or two at a cell's centre, then makes up the ground in one frame (12 m/s for it).
	drive.call([[4.0, 1.0]])
	var hitched := []
	for i in 6:
		hitched.append_array(drive.call([[4.0, 0.4], [0.0, 2.0 / 60.0], [12.0, 1.0 / 60.0]]))
	_check(hitched.all(func(clip: String) -> bool: return clip == gaits[1]),
			"a jog that stalls two frames and makes the ground up in one keeps the jog, six times over (%s)" % [hitched.filter(func(clip: String) -> bool: return clip != gaits[1])])
	drive.call([[4.0, 1.0]])
	var stop: Array = drive.call([[0.0, 0.6]])
	var stood := stop.find(Client3D.CLIP_IDLE)
	_check(stood >= int(Client3D.STOP_HOLD * 60.0) - 1 and stood <= 24, "a real stop stands after STOP_HOLD, by 0.4 s (frame %d)" % stood)
	drive.call([[1.0, 1.5]])
	var walked := rig.base_clip()
	var burst: Array = drive.call([[4.0, 0.1]])
	_check(walked == gaits[0] and burst[-1] == gaits[1], "a burst from a walk (%s) jogs within 0.1 s (%s)" % [walked, burst[-1]])
	AnimRig._clock_movie = -1
	AnimRig._clock_frame = -1
	puppet.position = was_at
	for key: String in kept:
		if kept[key] == null:
			puppet.remove_meta(key)
		else:
			puppet.set_meta(key, kept[key])
	rig.loop(Client3D.CLIP_IDLE, 1.0)


func _test_blows_seen() -> void:
	print("\n== blows you can see: the legs walk under a strike, the flinch at the contact ==")
	var player := _player()
	if player == null:
		_check(false, "a player to strike with")
		return
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets[player.get_instance_id()]
	var rig := puppet.get_meta("rig") as AnimRig
	# Put back after: the bow, guard and pick checks read this same puppet.
	var kept := {}
	for key: String in ["busy_until", "speed", "last_at", "last_ms"]:
		kept[key] = puppet.get_meta(key) if puppet.has_meta(key) else null
	rig.strike("Punch_Jab", 0.17, 0.34, 0.6)
	puppet.set_meta("busy_until", Time.get_ticks_msec() + 900)
	puppet.set_meta("speed", 2.0)
	puppet.set_meta("last_at", puppet.position - Vector3(0.2, 0.0, 0.0))
	puppet.set_meta("last_ms", Time.get_ticks_msec() - 100)
	_rig._animate(puppet)
	var gaits: Array = (puppet.get_meta("gaits", Client3D.GAITS) as Array).map(func(gait: Array) -> String: return str(gait[0]))
	_check(rig.striking() and rig.legs_amount() > 0.5 and rig.base_clip() in gaits,
			"striking as it moves: the blow on, its legs walking (%.2f of them, %s under it)" % [rig.legs_amount(), rig.base_clip()])
	rig.cancel_strike()
	puppet.set_meta("busy_until", 0)
	puppet.set_meta("speed", 0.0)
	puppet.set_meta("last_at", puppet.position)
	puppet.set_meta("last_ms", Time.get_ticks_msec() - 100)
	_rig._animate(puppet)
	_check(rig.legs_amount() < 0.5, "and stood, its legs its own again (%.2f)" % rig.legs_amount())
	rig.legs_walk(0.0)
	for key: String in kept:
		if kept[key] == null:
			puppet.remove_meta(key)
		else:
			puppet.set_meta(key, kept[key])
	# An orc struck by a swing whose drawn blow lands 0.3 s on: no flinch till then.
	# Beside the player: _struck_with takes the nearest swing within BLOW_REACH.
	var imp := _spawn_imp(player.tile + Vector2i(1, 0), "brute")
	var target: Node3D = null
	for i in 30:  # Its model may come a frame or more after its puppet.
		_rig._process(0.0)
		target = _rig._puppets.get(imp.get_instance_id())
		if target != null and target.has_meta("rig"):
			break
		await get_tree().process_frame
	if target == null or not target.has_meta("rig"):
		_check(false, "a goblin to strike (%s, %s)" % [imp != null and is_instance_valid(imp), target != null])
		World.despawn(imp)
		return
	var hurt := target.get_meta("rig") as AnimRig
	var now := Time.get_ticks_msec()
	_rig._swings[player.get_instance_id()] = [now, "", now + 300]
	_rig._on_struck(1, &"attack", imp.get_instance_id())
	var early := hurt.playing()
	await get_tree().create_timer(0.45).timeout
	_check(not early in Client3D.HIT_CLIPS and hurt.playing() in Client3D.HIT_CLIPS,
			"the struck orc flinches as the blow lands, not at its news (%s, then %s)" % [early, hurt.playing()])
	# Its own led blow (338 amended (6)): the bare hands' drawn strike, gathered
	# over the lead, its contact on the drawn blow's landing; a player's lead keeps the plain ones.
	var drawn_names: Array = (Client3D.HUMANOID_MOVES["drawn"][""] as Array).map(func(choice: Array) -> String: return str(choice[0]))
	_check(Client3D.drawn_strikes(target, imp, "", false).is_empty() and Client3D.drawn_strikes(puppet, player, "", true).is_empty()
			and Client3D.drawn_strikes(target, imp, "", true).size() == drawn_names.size()
			and Client3D.is_lead(imp, Monster.LEAD_TICKS) and not Client3D.is_lead(imp, Monster.WINDUP_TICKS) and not Client3D.is_lead(player, 3),
			"drawn strikes only for a monster's lead (its lead_ticks, not a HEAVY wind-up; none for a player)")
	hurt.cancel_strike()
	target.set_meta("busy_until", 0)
	var wound_at := Time.get_ticks_msec()
	_rig._on_winding(Vector2i(-1, 0), 3, imp.get_instance_id())
	var lands_at := wound_at + int((3 * World.TICK_DT + Client3D.STRIKE_LANDS_IN) * 1000.0)
	var contact_at := int(target.get_meta("contact_msec", -1))
	_check(hurt.striking() and hurt.playing() in drawn_names and absi(contact_at - lands_at) <= 20,
			"the orc's led blow gathers first: %s, its contact on the landing (%d ms off)" % [hurt.playing(), contact_at - lands_at])
	_rig._on_swung(Vector2i(-1, 0), imp.get_instance_id())
	_check(hurt.playing() in drawn_names, "its swing's news starts no second strike (%s)" % hurt.playing())
	hurt.cancel_strike()
	target.set_meta("busy_until", 0)
	World.despawn(imp)
	_rig._swings.erase(player.get_instance_id())
	_rig._process(0.0)


## The shield package, animation's side (340 and 379 amended): a bash's Shield_Bash on the basher and
## the bashed body's hit from its side as the shield meets it; the attacker thrown back off a raised
## shield recoils as its drawn blow lands; sparks off the shield, gone after.
func _test_shield_seen() -> void:
	print("\n== the shield seen: the bash, the recoil off a raised shield, sparks ==")
	_check(Client3D.hit_side(Vector2(1, 0), Vector2(1, 0)) == "front" and Client3D.hit_side(Vector2(1, 0), Vector2(-1, 0)) == "back"
			and Client3D.hit_side(Vector2(0, 1), Vector2(-1, 0)) == "right" and Client3D.hit_side(Vector2(0, 1), Vector2(1, 0)) == "left"
			and Client3D.hit_side(Vector2(0, 1), Vector2.ZERO) == "front",
			"a blow's side: ahead front, behind back, a quarter clockwise (y down) the right")
	var player := _player()
	if player == null:
		_check(false, "a player to bash with")
		return
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets[player.get_instance_id()]
	var rig := puppet.get_meta("rig") as AnimRig
	var imp := _spawn_imp(player.tile + Vector2i(1, 0), "brute")
	var target: Node3D = null
	for i in 30:
		_rig._process(0.0)
		target = _rig._puppets.get(imp.get_instance_id())
		if target != null and target.has_meta("rig"):
			break
		await get_tree().process_frame
	if target == null or not target.has_meta("rig"):
		_check(false, "an orc to bash (%s)" % [target != null])
		World.despawn(imp)
		return
	var hurt := target.get_meta("rig") as AnimRig
	_check(rig.has(Client3D.CLIP_RECOIL) and rig.has(Client3D.CLIP_SHIELD_BASH), "the people's clips hold Recoil and Shield_Bash")
	# The bash: the player swung as it bashed, its drawn blow landing 0.25 s on.
	hurt.cancel_strike()
	target.set_meta("busy_until", 0)
	imp.facing = Vector2i(0, 1)
	var now := Time.get_ticks_msec()
	_rig._swings[player.get_instance_id()] = [now, "", now + 250]
	_rig._on_bashed(Vector2i.ZERO, player.get_path(), imp.get_instance_id())
	var early := hurt.playing()
	_check(rig.striking() and rig.playing() == Client3D.CLIP_SHIELD_BASH, "the basher drives its shield in (%s)" % rig.playing())
	await get_tree().create_timer(0.3).timeout
	var right: Array = Client3D.HUMANOID_MOVES["hits"]["right"]
	_check(not early in right and hurt.playing() in right,
			"the bashed orc, facing south with the basher west, takes it on its right as it lands (%s, then %s)" % [early, hurt.playing()])
	await get_tree().create_timer(0.25).timeout
	var body := target.get_node("Body") as Node3D
	_check(body.position.is_equal_approx(Vector3(0.0, body.position.y, 0.0)) or body.position.distance_to(Vector3(0.0, body.position.y, 0.0)) < 0.01,
			"not moved, it jolted and came home (%s)" % body.position)
	rig.cancel_strike()
	puppet.set_meta("busy_until", 0)
	# Thrown back off a raised shield: its drawn blow lands 0.2 s on, the recoil then; a bash's stun no recoil.
	hurt.cancel_strike()
	target.set_meta("busy_until", 0)
	now = Time.get_ticks_msec()
	_rig._swings[imp.get_instance_id()] = [now, "", now + 200]
	_rig._on_stunned(4, &"guarded", imp.get_instance_id())
	early = hurt.playing()
	await get_tree().create_timer(0.3).timeout
	_check(early != Client3D.CLIP_RECOIL and hurt.playing() == Client3D.CLIP_RECOIL,
			"thrown back off a shield, it recoils as its blow lands (%s, then %s)" % [early, hurt.playing()])
	hurt.cancel_strike()
	target.set_meta("busy_until", 0)
	_rig._swings.erase(imp.get_instance_id())
	await get_tree().create_timer(0.7).timeout  # (The recoil played out.)
	var was := hurt.playing()
	_rig._on_stunned(4, &"bash", imp.get_instance_id())
	_check(was != Client3D.CLIP_RECOIL and hurt.playing() == was, "a bash's stun plays no recoil (%s, then %s)" % [was, hurt.playing()])
	# Sparks off the player's shield, gone after.
	var mesh := Client3D.spark_mesh()
	_check(mesh.get_surface_count() == 1 and mesh.surface_get_array_len(0) == Client3D.SPARK_COUNT * 3, "the sparks' one mesh: %d streaks" % Client3D.SPARK_COUNT)
	var before := _rig.find_children("Spark", "MeshInstance3D", false, false).size()
	_rig._spark(puppet, player)
	var sparks := _rig.find_children("Spark", "MeshInstance3D", false, false).size()
	await get_tree().create_timer(Client3D.SPARK_SECONDS + 0.15).timeout
	var after := _rig.find_children("Spark", "MeshInstance3D", false, false).size()
	_check(sparks == before + 1 and after == before, "a blow on the shield throws sparks, gone after (%d, %d, %d)" % [before, sparks, after])
	_rig._swings.erase(player.get_instance_id())
	World.despawn(imp)
	_rig._process(0.0)


## Steadied (843, animation's side): a boss out of a stagger, cried "steady", plants and shakes it
## off, then stands braced; a blow on it rocks it with no hit clip; "steady_over" (or its cap) lets
## it up. A creature (the boar king, CreatureView) and a person (a robber for the chiefs, Client3D).
func _test_steadied() -> void:
	print("
== steadied (843): out of a stagger it plants and shakes it off, a blow rocks it without a hit, braced till steady_over ==")
	var king := _spawn_imp(Vector2i(9, 4), "boar_king")
	var robber := _spawn_imp(Vector2i(9, 6), "robber")
	await _frames(2)
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets.get(king.get_instance_id()) if king != null else null
	var view := puppet.get_meta("creature_view", null) as CreatureView if puppet != null else null
	var person: Node3D = _rig._puppets.get(robber.get_instance_id()) if robber != null else null
	if view == null or view.rig == null or person == null or not person.has_meta("rig") or not person.has_node("Body/Model"):
		_check(false, "a boar king by its CreatureView and a robber by its rig (%s, %s)" % [view, person])
		for each: GridEntity in [king, robber]:
			if each != null:
				World.despawn(each)
		return
	var pose := view._pose
	_rig._on_cried(&"steady", king.get_instance_id())
	var lowest := 0.0
	var rolled := 0.0
	var twisted := 0.0
	# Waits on the state, not the wall clock (a loaded suite reads a tween late): the beat's 0.4 s
	# watched, then on till braced, 3 s at most.
	var braced := func() -> bool:
		return pose.position.y < -0.005 and absf(pose.rotation.z) < 0.01 and absf(pose.rotation.y - view._rest_yaw) < 0.01
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 600 or (not braced.call() and Time.get_ticks_msec() - started < 3000):
		await get_tree().process_frame
		lowest = minf(lowest, pose.position.y)
		rolled = maxf(rolled, absf(pose.rotation.z))
		twisted = maxf(twisted, absf(pose.rotation.y - view._rest_yaw))
	_check(view.steadied() and lowest < -0.02 and rolled > 0.05 and twisted > 0.05 and pose.position.y < -0.005
			and absf(pose.rotation.z) < 0.01 and absf(pose.rotation.y - view._rest_yaw) < 0.01,
			"the boar king steadied: planted (sunk %.3f m), shaken (rolled %.2f, twisted %.2f rad), then braced (%.3f m)"
			% [lowest, rolled, twisted, pose.position.y])
	var hit_clip := str(view.clips.get("hit", "-"))
	_rig._flinch(puppet)
	var rocked := 0.0
	started = Time.get_ticks_msec()
	while rocked >= -0.01 and Time.get_ticks_msec() - started < 1000:
		await get_tree().process_frame
		rocked = minf(rocked, pose.position.x)
	_check(rocked < -0.01 and view.rig.playing() != hit_clip and view.steadied(),
			"a blow on him steadied: rocked back %.3f m, no hit clip (%s), still steadied" % [rocked, view.rig.playing()])
	_rig._on_cried(&"steady_over", king.get_instance_id())
	started = Time.get_ticks_msec()
	var risen := func() -> bool:
		return absf(pose.position.y) < 0.005 and absf(pose.rotation.x) < 0.01
	while (not risen.call() or Time.get_ticks_msec() - started < 400) and Time.get_ticks_msec() - started < 3000:
		await get_tree().process_frame
	_check(not view.steadied() and absf(pose.position.y) < 0.005 and absf(pose.rotation.x) < 0.01,
			"steady_over: up from the brace (%.3f m, %.3f rad)" % [pose.position.y, pose.rotation.x])
	view.steady()
	view._steady_until = AnimRig.now_msec() - 1
	view.frame(puppet, king)
	_check(view._steady_until == 0, "a lost steady_over: let up at its cap")
	# A person (the chiefs' way): its Model dipped, its Body rolled, its clips playing on.
	var body := person.get_node("Body") as Node3D
	var model := body.get_node("Model") as Node3D
	var rig := person.get_meta("rig") as AnimRig
	var rest_y := model.position.y
	_rig._on_cried(&"steady", robber.get_instance_id())
	var faces := model.rotation.y
	var dipped := rest_y
	var rolled_by := 0.0
	var twisted_by := 0.0
	var lifted := 0.0
	var held := func() -> bool:
		var turned_back := absf(angle_difference(faces, model.rotation.y)) < 0.01
		return model.position.y < rest_y - 0.02 and absf(body.rotation.x) < 0.01 and absf(body.rotation.z) < 0.01 and turned_back
	started = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 600 or (not held.call() and Time.get_ticks_msec() - started < 3000):
		await get_tree().process_frame
		dipped = minf(dipped, model.position.y)
		rolled_by = maxf(rolled_by, absf(body.rotation.x))
		twisted_by = maxf(twisted_by, absf(angle_difference(faces, model.rotation.y)))
		lifted = maxf(lifted, body.rotation.z)
	_check(_rig._held_steady(person) and dipped < rest_y - 0.1 and rolled_by > 0.2 and twisted_by > 0.15 and lifted > 0.05
			and model.position.y < rest_y - 0.02 and absf(body.rotation.x) < 0.01 and absf(body.rotation.z) < 0.01
			and absf(angle_difference(faces, model.rotation.y)) < 0.01,
			"a person steadied: dipped %.3f m, shoulders rolled %.2f, twisted %.2f, head up %.2f rad, then braced (%.3f m below its rest)"
			% [rest_y - dipped, rolled_by, twisted_by, lifted, rest_y - model.position.y])
	var stood := body.position
	_rig._flinch(person)
	var pushed := 0.0
	started = Time.get_ticks_msec()
	while pushed <= 0.02 and Time.get_ticks_msec() - started < 1000:
		await get_tree().process_frame
		pushed = maxf(pushed, Vector2(body.position.x - stood.x, body.position.z - stood.z).length())
	_check(pushed > 0.02 and not rig.playing() in _rig.HIT_CLIPS,
			"a blow on a person steadied: rocked %.3f m, no hit clip (%s)" % [pushed, rig.playing()])
	_rig._on_cried(&"steady_over", robber.get_instance_id())
	started = Time.get_ticks_msec()
	var stood_up := func() -> bool:
		return absf(model.position.y - rest_y) < 0.005 and absf(body.rotation.x) < 0.01
	while (not stood_up.call() or Time.get_ticks_msec() - started < 400) and Time.get_ticks_msec() - started < 3000:
		await get_tree().process_frame
	_check(not _rig._held_steady(person) and absf(model.position.y - rest_y) < 0.005 and absf(body.rotation.x) < 0.01,
			"steady_over: the person up from the brace (%.3f m off its rest)" % (model.position.y - rest_y))
	person.set_meta("busy_until", 0)
	_rig._flinch(person)
	_check(rig.playing() in _rig.HIT_CLIPS, "steadied no more, a blow plays its hit again (%s)" % rig.playing())
	World.despawn(king)
	World.despawn(robber)
	await _frames(2)


func _spawn_imp(tile: Vector2i, kind := "") -> Monster:
	var occupant := World.get_entity_at(tile)
	if occupant != null:
		World.despawn(occupant)
	var spec := {"script": "res://sim/monster.gd", "shape": "capsule",
		"name": "ViewImp%d_%d" % [tile.x, tile.y], "tile": tile}
	if not kind.is_empty():
		spec["kind"] = kind
	var imp := _main._spawn(spec) as Monster
	if imp != null:
		imp.sight_range = 0
	return imp


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


## The low-angle fight, 4: under the low camera a body crossing
## World.NEAR_TILES eases in and out instead of popping.
func _test_reach_ease() -> void:
	print("\n== the reach's edge under the low camera: a body crossing it eases in and out, never pops ==")
	var low_was := Net.camera_low
	Net.set_camera_low(true, false)
	var castle := Level.load_level("castle")
	_rig.rebuild(castle["terrain"], castle["centre"])
	var imp := _spawn_imp(Vector2i(9, 4))  # (A room tile within NEAR_TILES of the camera's aim, on the player.)
	await _frames(4)  # (Its body's puppet, made and made again once its body is known.)
	_rig._sync_puppets()
	var id := imp.get_instance_id()
	var puppet: Node3D = _rig._puppets[id]
	var meshes: Array = _rig._descendants(puppet).filter(func(node: Node) -> bool: return node is GeometryInstance3D)
	var solid := func() -> bool: return meshes.all(func(node: GeometryInstance3D) -> bool: return is_zero_approx(node.transparency))
	var gone := func() -> bool: return meshes.all(func(node: GeometryInstance3D) -> bool: return is_equal_approx(node.transparency, 1.0))
	_check(meshes.size() > 0 and puppet.visible and solid.call() and not puppet.has_meta("reach_at"), "within the reach: drawn, solid (%d parts)" % meshes.size())
	var near_tile := imp.tile
	# Past NEAR_TILES of the camera's aim (as it stands now: it follows the player), within the puppets' reach.
	var aim := Vector2(_rig._camera_target.x, _rig._camera_target.z)
	var edge_tile := Vector2i(roundi(aim.x) + World.NEAR_TILES + 2, roundi(aim.y))
	imp.tile = edge_tile
	imp.position = Iso.grid_to_local(Vector2(edge_tile))
	_rig._sync_puppets()
	_check(puppet.visible and puppet.has_meta("reach_at") and not _rig._far.has(id) and _rig._puppets[id] == puppet,
			"stepped past NEAR_TILES: still drawn, its easing out begun (same puppet %s, far %s, in %s)" % [_rig._puppets[id] == puppet, _rig._far.has(id), puppet.get_meta("reach_in", "-")])
	puppet.set_meta("reach_at", Time.get_ticks_msec() - int(Client3D.REACH_EASE * 500.0))
	_rig._sync_puppets()
	var half: float = (meshes[0] as GeometryInstance3D).transparency
	_check(puppet.visible and half > 0.3 and half < 0.7, "half way: half gone (%.2f)" % half)
	puppet.set_meta("reach_at", Time.get_ticks_msec() - int(Client3D.REACH_EASE * 1000.0) - 50)
	_rig._sync_puppets()
	_check(not puppet.visible and gone.call() and not puppet.has_meta("reach_at"), "and after REACH_EASE: hidden")
	imp.tile = near_tile
	imp.position = Iso.grid_to_local(Vector2(near_tile))
	_rig._sync_puppets()
	_check(puppet.visible and gone.call() and puppet.has_meta("reach_at"), "back within: drawn at once, from gone, its easing in begun")
	puppet.set_meta("reach_at", Time.get_ticks_msec() - int(Client3D.REACH_EASE * 1000.0) - 50)
	_rig._sync_puppets()
	_check(puppet.visible and solid.call() and not puppet.has_meta("reach_at"), "and after REACH_EASE: solid")
	# The camera off: every puppet drawn and solid again, the easing forgotten.
	imp.tile = edge_tile
	imp.position = Iso.grid_to_local(Vector2(edge_tile))
	_rig._sync_puppets()
	Net.set_camera_low(false, false)
	_check(puppet.visible and solid.call() and not puppet.has_meta("reach_in") and not puppet.has_meta("reach_at"), "the low camera off: drawn, solid, nothing remembered")
	imp.tile = near_tile
	imp.position = Iso.grid_to_local(Vector2(near_tile))
	World.despawn(imp)
	_rig._sync_puppets()
	Net.set_camera_low(low_was, false)
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## The low-angle fight, 5: names under the low camera read at every
## depth, the nearest on top, and past NAME_TILES only the party's and a
## foe's.
func _test_low_names() -> void:
	print("\n== names under the low camera: sized to their depth, the nearest on top, far ones only for the party and a foe ==")
	var low_was := Net.camera_low
	var player := _player()
	var start := player.tile
	Net.set_camera_low(true, false)
	var castle := Level.load_level("castle")
	_rig.rebuild(castle["terrain"], castle["centre"])
	var ahead: Vector3 = -_rig._camera.global_transform.basis.z
	# Two imps on the room's floor: the nearest and the deepest free cells in the view (World still holds the room).
	var near_cell := Vector2i(-1, -1)
	var deep_cell := Vector2i(-1, -1)
	var nearest := INF
	var deepest := -INF
	for cell: Vector2i in _main._terrain["floor"]:
		if World.get_entity_at(cell) != null:
			continue
		var depth: float = (_rig.to_global(_rig._tile_position(cell)) - _rig._camera.global_position).dot(ahead)
		if depth < nearest:
			nearest = depth
			near_cell = cell
		if depth > deepest:
			deepest = depth
			deep_cell = cell
	var near := _spawn_imp(near_cell)
	var deep := _spawn_imp(deep_cell)
	await _frames(4)
	_rig._sync_puppets()
	var near_label: Label3D = _rig._puppets[near.get_instance_id()].get_node("Name")
	var deep_label: Label3D = _rig._puppets[deep.get_instance_id()].get_node("Name")
	_check(deep_label.scale.x >= near_label.scale.x and near_label.scale.x >= 1.0 and deep_label.render_priority < near_label.render_priority,
			"the deeper name is grown to read and drawn under the nearer (scales %.2f, %.2f; priorities %d, %d)" % [near_label.scale.x, deep_label.scale.x, near_label.render_priority, deep_label.render_priority])
	var far_tiles := Vector2(deep_cell).distance_to(Vector2(player.tile))
	# The deep imp near or far from the player by NAME_TILES: its name shown near; past it, only once it is a foe.
	var now := Time.get_ticks_msec()
	if far_tiles > Client3D.NAME_TILES:
		_check(not deep_label.visible and near_label.visible == (Vector2(near_cell).distance_to(Vector2(player.tile)) <= Client3D.NAME_TILES or near.alert != Monster.Alert.IDLE),
				"an idle imp %.0f tiles off: its name waits (%s)" % [far_tiles, deep_label.visible])
	else:
		print("  (the room's deepest cell is within NAME_TILES of the player: the far name check is on the alert alone)")
	deep.alert = Monster.Alert.HUNTING
	_rig._sync_puppets()
	_check(deep_label.visible, "hunting, its name shows wherever it is")
	deep.alert = Monster.Alert.IDLE
	_rig._combat_at[deep.get_instance_id()] = Time.get_ticks_msec()
	_rig._sync_puppets()
	_check(deep_label.visible, "lately struck, too")
	_rig._combat_at.erase(deep.get_instance_id())
	_check(_rig.name_shown(player, _rig._puppets[player.get_instance_id()], now), "the party's always")
	Net.set_camera_low(false, false)
	_check(deep_label.visible and is_equal_approx(deep_label.scale.x, 1.0) and deep_label.render_priority == 0, "the camera off: every name as it was")
	World.despawn(near)
	World.despawn(deep)
	_rig._sync_puppets()
	Net.set_camera_low(low_was, false)
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## The low-angle fight, combat's (d): under a camera pitched below
## AIM_LOW_PITCH the cone of flight's edges stand off the ground and its
## fill is fuller; at the ortho pitch, as before.
## Jeff: "for the archery circle (arc) -- on a slanted ground it disappears
## into the terrain": the ring, the cone's fill and its sides lie on the
## ground in quarter-cell strips, every vertex on the ground mesh's own
## height, nothing under it, on the hills' slopes.
func _test_arc_on_ground() -> void:
	print("\n== the aim's ring and cone of flight lie on sloped ground, strip by strip ==")
	var hills := Level.load_level("hills")
	if hills.is_empty():
		print("  (no hills level here: skipped)")
		return
	_rig.rebuild(hills["terrain"], hills["centre"])
	# The cell with the steepest slope (not a cliff) over five cells eastward, near the middle.
	var centre: Vector2i = hills["centre"]
	var origin := Vector2(centre)
	var steepest := 0.0
	for y in range(centre.y - 40, centre.y + 40, 2):
		for x in range(centre.x - 40, centre.x + 40, 2):
			var cell := Vector2i(x, y)
			var rise := absf(_rig._ground_height(Vector2(cell) + Vector2(5.0, 0.0)) - _rig._ground_height(Vector2(cell)))
			var sloped := true  # A slope, not a cliff: no single cell's step over 0.6.
			for k in 5:
				if absf(_rig._ground_height(Vector2(cell) + Vector2(k + 1.0, 0.0)) - _rig._ground_height(Vector2(cell) + Vector2(float(k), 0.0))) > 0.6:
					sloped = false
			if sloped and rise > steepest:
				steepest = rise
				origin = Vector2(cell)
	_check(steepest >= 0.5, "a slope on the hills to aim across: %.2f up or down over five cells from %s" % [steepest, origin])
	_rig.aim_arc(origin, 0.0, 5.0, 1.0, 0, true, 0.4)
	var base: float = _rig._height_in(Vector2i(origin.round()), origin)
	var worst := 0.0
	var mid_worst := 0.0
	var faces := 0
	var creases := 0
	for pair: Array in [[_rig._aim_arc, 0.0], [_rig._aim_cone, Client3D.ON_FLOOR], [_rig._aim_cone_rim, Client3D.ON_FLOOR * 1.5]]:
		var mesh: MeshInstance3D = pair[0]
		var bias: float = pair[1]
		var vertices := (mesh.mesh as ArrayMesh).get_faces()
		faces += vertices.size() / 3
		for i in range(0, vertices.size(), 3):
			var tri: Array[Vector3] = [vertices[i], vertices[i + 1], vertices[i + 2]]
			for j in 3:
				var a := tri[j]
				var b := tri[(j + 1) % 3]
				var at_a := origin + Vector2(a.x, a.z)
				var at_b := origin + Vector2(b.x, b.z)
				worst = maxf(worst, absf(a.y - (_rig._height_in(Vector2i(at_a.round()), at_a) - base + bias)))
				# The edge's middle: on the ground where the edge lies on one of a cell's two
				# triangles; across a crease (a cell's fold, a cliff's foot) the strip bridges it.
				var cell := Vector2i(at_a.round())
				var in_a := at_a - Vector2(cell) + Vector2(0.5, 0.5)
				var in_b := at_b - Vector2(cell) + Vector2(0.5, 0.5)
				if cell != Vector2i(at_b.round()) or (in_a.x + in_a.y <= 1.0) != (in_b.x + in_b.y <= 1.0) or _rig._shore_heights.has(cell):
					creases += 1
					continue
				var mid := (at_a + at_b) * 0.5
				mid_worst = maxf(mid_worst, absf((a.y + b.y) * 0.5 - (_rig._height_in(cell, mid) - base + bias)))
	_check(faces > 3 * Client3D.AIM_SEGMENTS, "built strip by strip: %d triangles for a five-cell cone (a fan was %d)" % [faces, Client3D.AIM_SEGMENTS])
	_check(worst < 0.01, "every corner of the ring, the fill and the sides on the ground under it (worst %.3f off)" % worst)
	_check(mid_worst < 0.01 and creases > 0, "every strip's middle on the ground where it lies on one ground triangle (worst %.3f off); %d strip edges bridge a crease" % [mid_worst, creases])
	var ring_y: Array[float] = []
	for vertex in (_rig._aim_arc.mesh as ArrayMesh).get_faces():
		ring_y.append(vertex.y)
	_check(ring_y.max() - ring_y.min() > 0.2, "the ring itself climbs the slope (%.2f from its lowest to its highest point)" % (ring_y.max() - ring_y.min()))
	# Moving the archer a cell rebuilds the ring on the new ground.
	var ring_was: ArrayMesh = _rig._aim_arc.mesh
	_rig.aim_arc(origin + Vector2(1.0, 0.0), 0.0, 5.0, 1.0, 0, true, 0.4)
	_check(_rig._aim_arc.mesh != ring_was, "the archer a cell on: the ring built again for the ground there")
	_rig.aim_arc(origin, 0.0, 0.0, 0.0, 0, false)
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


func _test_cone_lift() -> void:
	print("\n== the cone of flight under a low pitch: its edges lifted, its fill fuller ==")
	var pitch_was: float = _rig.pitch
	var origin := Vector2(9.0, 4.0)
	_rig.aim_arc(origin, 0.0, 5.0, 1.0, 0, true, 0.4)
	var flat_y: float = _rig._aim_arc.position.y
	var flat_rim: float = (_rig._aim_cone_rim.mesh as ArrayMesh).get_faces()[0].y
	var flat_fill: float = (_rig._aim_cone.material_override as StandardMaterial3D).albedo_color.a
	_check(_rig.pitch >= Client3D.AIM_LOW_PITCH and is_zero_approx(_rig.edge_lift()) and is_equal_approx(flat_fill, Client3D.AIM_CONE_FILL),
			"at the ortho pitch (%.0f): no lift, the fill AIM_CONE_FILL (%.2f)" % [_rig.pitch, flat_fill])
	_rig.pitch = Client3D.LOW_PITCH
	_rig.aim_arc(origin, 0.0, 5.0, 1.0, 0, true, 0.4)
	var low_rim: float = (_rig._aim_cone_rim.mesh as ArrayMesh).get_faces()[0].y
	var low_fill: float = (_rig._aim_cone.material_override as StandardMaterial3D).albedo_color.a
	_check(is_equal_approx(_rig.edge_lift(), Client3D.AIM_EDGE_LIFT) and is_equal_approx(_rig._aim_arc.position.y, flat_y + Client3D.AIM_EDGE_LIFT)
			and is_equal_approx(low_rim, flat_rim + Client3D.AIM_EDGE_LIFT) and is_equal_approx(low_fill, Client3D.AIM_CONE_FILL_LOW),
			"at LOW_PITCH: the far arc and the sides AIM_EDGE_LIFT up (%.2f, %.2f), the fill AIM_CONE_FILL_LOW (%.2f)" % [_rig._aim_arc.position.y - flat_y, low_rim - flat_rim, low_fill])
	# Combat's check (623's fight reads): lifted, the cone is the same cone,
	# every point of its sides over the same ground, only higher, so its
	# drawn spread is still the sim's (World.spread_of).
	var low_faces := (_rig._aim_cone_rim.mesh as ArrayMesh).get_faces()
	_rig.pitch = pitch_was
	_rig.aim_arc(origin, 0.0, 5.0, 1.0, 0, true, 0.4)
	var flat_faces := (_rig._aim_cone_rim.mesh as ArrayMesh).get_faces()
	var same_ground := low_faces.size() == flat_faces.size() and not flat_faces.is_empty()
	for i in mini(low_faces.size(), flat_faces.size()):
		same_ground = same_ground and is_equal_approx(low_faces[i].x, flat_faces[i].x) and is_equal_approx(low_faces[i].z, flat_faces[i].z) 				and is_equal_approx(low_faces[i].y, flat_faces[i].y + Client3D.AIM_EDGE_LIFT)
	_check(same_ground, "lifted, the cone's sides stand over the same ground (%d vertices): its spread is the sim's at either pitch" % flat_faces.size())
	_check(is_equal_approx(_rig._aim_arc.position.y, flat_y), "and back at the ortho pitch, on the ground again")
	_rig.aim_arc(origin, 0.0, 5.0, 1.0, 0, false)


## The shown walk bends through the cell centre (decision 655).
func _test_bent_walk() -> void:
	print("\n== the shown walk bends through the cell centre (655) ==")
	var none := GridEntity.UNKNOWN_TILE
	var r := GridEntity.BEND_REACH
	var a := Vector2i(0, 0)
	var b := Vector2i(1, 0)
	var c := Vector2i(1, 1)
	var straight := true
	for i in 5:
		var t := i / 4.0
		straight = straight and GridEntity.bent_position(a, b, Vector2i(2, 0), Vector2i(3, 0), t, r, r).is_equal_approx(Vector2(1.0 + t, 0.0)) \
				and GridEntity.bent_tangent(a, b, Vector2i(2, 0), Vector2i(3, 0), t, r, r).is_equal_approx(Vector2.RIGHT)
	_check(straight, "a straight run is the straight line at the straight pace, pointing along it")
	# A right-angle corner at b: east, then south.
	var into := GridEntity.bent_position(none, a, b, c, 1.0 - r, 0.0, r)
	var out := GridEntity.bent_position(a, b, c, none, r, r, 0.0)
	_check(into.is_equal_approx(Vector2(0.5, 0.0)) and out.is_equal_approx(Vector2(1.0, 0.5)),
			"the bend starts and ends on the straight line's midpoints, at the straight line's moments (%s, %s)" % [into, out])
	var corner_in := GridEntity.bent_position(none, a, b, c, 1.0, 0.0, r)
	var corner_out := GridEntity.bent_position(a, b, c, none, 0.0, r, 0.0)
	_check(corner_in.is_equal_approx(corner_out) and corner_in.is_equal_approx(Vector2(0.875, 0.125)),
			"at the corner's moment the two steps meet on the bend, the corner cut by under a quarter cell (%s)" % corner_in)
	var inside := true
	var onward := true
	var last := -1.0
	for k in 21:
		var at := GridEntity.bent_position(none, a, b, c, 1.0 - r + r * k / 20.0, 0.0, r)
		inside = inside and at.x >= -0.5 and at.x <= 1.5 and at.y >= -0.5 and at.y <= 0.5
		onward = onward and at.x + at.y > last
		last = at.x + at.y
	for k in range(1, 21):
		var at := GridEntity.bent_position(a, b, c, none, r * k / 20.0, r, 0.0)
		inside = inside and at.x >= 0.5 and at.x <= 1.5 and at.y >= -0.5 and at.y <= 1.5
		onward = onward and at.x + at.y > last
		last = at.x + at.y
	_check(inside and onward, "the bend stays within the two cells of each step and always moves on")
	var tangent := GridEntity.bent_tangent(a, b, c, none, 0.0, r, 0.0)
	_check(tangent.is_equal_approx(Vector2(1, 1).normalized()), "at the corner's moment the body points between the two ways (%s)" % tangent)
	# 655 amended: the cut capped at a quarter cell.
	var back := GridEntity.bent_position(a, b, a, none, 0.0, r, 0.0).distance_to(Vector2(b))
	var diagonal_back := GridEntity.bent_position(a, c, a, none, 0.0, r, 0.0).distance_to(Vector2(c))
	var uncapped := GridEntity._bend_point(Vector2(a), Vector2(c), Vector2(a), r, 0.5).distance_to(Vector2(c))
	_check(is_equal_approx(back, 0.25) and is_equal_approx(diagonal_back, 0.25) and uncapped > 0.3,
			"a reversal cuts its corner by a quarter cell exactly, and a diagonal reversal (%.3f unchecked) is capped to the same (%.3f, %.3f)" % [uncapped, back, diagonal_back])
	var capped := GridEntity.capped_reach(Vector2(a), Vector2(c), Vector2(a), r)
	var capped_in := GridEntity.bent_position(none, a, c, a, 1.0 - capped + 0.001, 0.0, r)
	_check(capped_in.distance_to(Vector2(c).lerp(Vector2(a), capped)) < 0.002,
			"the capped bend still starts on the straight line at the straight line's moment (%s)" % capped_in)
	var narrow := GridEntity.BEND_REACH_NARROW
	var narrow_in := GridEntity.bent_position(none, a, b, c, 1.0 - narrow, 0.0, narrow)
	var narrow_corner := GridEntity.bent_position(none, a, b, c, 1.0, 0.0, narrow)
	_check(narrow_in.is_equal_approx(Vector2(0.75, 0.0)) and narrow_corner.distance_to(Vector2(b)) < corner_in.distance_to(Vector2(b)),
			"a narrow way's bend reaches a quarter step and cuts the corner less (%s)" % narrow_corner)
	# The reach read off the map: a cell walled on a side is narrow, one open all round is not.
	var open := none
	var walled := none
	for cell: Vector2i in World.floor_cells():
		var walls := 0
		for side: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if not World.is_walkable(cell + side):
				walls += 1
		if walls == 0 and open == none:
			open = cell
		elif walls > 0 and walled == none:
			walled = cell
		if open != none and walled != none:
			break
	_check(open != none and walled != none and GridEntity.bend_reach(open) == r and GridEntity.bend_reach(walled) == narrow,
			"the reach read off the map: a cell with a wall beside it bends the short way (%s), one open all round the full (%s)" % [walled, open])
	# A mirror's slide: the bend at its end settled from the queue as its tail begins.
	var body := GridEntity.new()
	body._from_tile = open
	body._from_pos = Vector2(open)
	body._to_tile = open + Vector2i.RIGHT
	body._move_tick = 100.0
	body._move_duration = 2.0
	body._slides.assign([{"from": open + Vector2i.RIGHT, "to": open + Vector2i.RIGHT + Vector2i.DOWN, "tick": 102.0, "duration": 2.0}])
	var early := body._bent_step(body._to_tile, 0.3)
	var late := body._bent_step(body._to_tile, 0.9)
	var reach := GridEntity.bend_reach(body._to_tile)
	var expected := GridEntity.bent_position(none, open, body._to_tile, body._slides[0]["to"], 0.9, 0.0, reach)
	_check(early.is_empty() and not late.is_empty() and body._bend_decided and body._bend_next == body._slides[0]["to"] and late[0].is_equal_approx(expected),
			"a mirror's slide runs straight till its tail, then bends toward the slide queued to follow it (%s)" % [late])
	body._bend_decided = false
	body._bend_next = none
	body._slides[0]["tick"] = 103.0
	_check(body._bent_step(body._to_tile, 0.9).is_empty() and body._bend_decided and body._bend_next == none,
			"a slide queued to start a tick late is no corner to bend toward: straight to the centre")
	body._present = true
	_check(body._bent_step(body._to_tile, 0.9).is_empty(), "a push is drawn straight")
	body.free()
