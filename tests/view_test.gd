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


func _ready() -> void:
	World.set_process(false)
	# The grid's steps: free walk is the default (decision 693).
	Net.free_walk = false
	World.free_walk = false
	Net.port = preload("res://tests/test_ports.gd").of(17791)  # Not 7777 (the editor may be hosting there), nor any other test's or eval's.
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

	_test_every_sound_has_its_files()
	await _test_hp_bars()
	await _test_sounds_follow_events()
	await _test_bow_sounds()
	await _test_armour_footfalls()
	await _test_monster_death()
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
	_test_draw_pull()
	_test_low_scatter()
	await _test_far_restart()
	await _test_low_pick()
	await _test_reach_ease()
	await _test_low_names()
	_test_cone_lift()
	_test_arc_on_ground()
	_test_bent_walk()
	_test_pine_stands()
	_test_ground_textures()
	_test_canopy_mask()
	_test_grown_trees()
	await _test_warm_ups()
	_test_seasons()
	_test_heights()
	_test_hills()
	_test_shore()
	_test_curves_meet()
	_test_built_water()
	_test_ledge_curves()
	_test_damp_look()
	_test_forest_edge()
	_test_clearing()
	_test_dais()
	_test_dark_set()
	_test_lair()
	_test_faced_decor()
	_test_solid_ground()
	_test_roads()
	_test_water()
	_test_streams()
	_test_tall_grass()
	_test_rocks()
	_test_niches()
	_test_relief()
	_test_sight()
	_test_fire()
	_test_cold_lamp()
	await _test_wall_runs()
	_test_cave_walls()
	_test_scatter()
	_test_ground_fields()
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
	_test_telegraph_fill_honest()
	await _test_target_marked()
	await _test_goblin()
	_test_humans()
	_test_worn()
	_test_asleep()
	_test_person_looks()
	_test_person_garb()
	_test_attach_points()
	_test_bow()
	_test_standing_turn()
	_test_visible_work()
	_test_head_socket()
	await _test_two_hands()  # It lets frames run (the pose the modifiers leave): after the tests that read a pose unrun.
	await _test_rest()
	_test_bow_back()
	_test_sheathed()
	_test_goblins_differ()
	_test_allies()
	_test_barrow_dead()
	_test_person_monster()
	_test_shadows_in_view()
	_test_no_2d_under_3d()
	await _test_doors_swing()
	await _test_door_states()
	_test_art_puppets()
	_test_breakable_hooked_once()
	await _test_phased_build()
	await _test_kept_fields()
	await _test_creature_puppets()
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
	music._process(Music.LEVEL_FADE)
	var player: AudioStreamPlayer = music.players.get("music.umbrage")
	_check(float(music.levels.get("music.umbrage", 0.0)) > 0.9 * wanted and player != null and player.playing,
		"eased in within %.1f s, playing (%.2f of %.2f)" % [Music.LEVEL_FADE, float(music.levels.get("music.umbrage", 0.0)), wanted])
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
	_check(player != null and (player.stream as AudioStreamOggVorbis).loop and is_equal_approx(player.volume_db, title.SILENT_DB),
		"looped, and it starts silent")
	title._tween.custom_step(title.FADE_IN)
	_check(player != null and is_equal_approx(player.volume_db, SoundKit.volume_db("music.title")), "faded in over %.1f s to the slot's level" % title.FADE_IN)
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
		player._world_lobbed(open, 6)
		_check(lob_sounds.call().has("sfx.bow_loose") and lob_sounds.call().has("sfx.arrow_lob_rise") and not lob_sounds.call().has("sfx.arrow_lob_fall"),
				"a lob loosed: the twang and its whoosh up, its whistle not yet (%s)" % [lob_sounds.call()])
		await get_tree().create_timer(0.3).timeout
		_check(lob_sounds.call().count("sfx.arrow_lob_fall") == 1 and not lob_sounds.call().has("sfx.arrow_land"),
				"its last %.1f s: the falling whistle, once, before it lands (%s)" % [Client3D.LOB_WARN_SECONDS, lob_sounds.call()])
		var lofted := _rig.get_tree().root.find_child("LobArrow", true, false) as Node3D
		var ground := _rig._tile_position(open)
		_check(lofted != null and lofted.position.y > maxf(tip.y, ground.y), "a lob's arrow climbs above the bow and the ground it falls to (%s)" % [lofted.position if lofted != null else null])
		await get_tree().create_timer(0.5).timeout
		_check(lofted != null and is_instance_valid(lofted) and lofted.position.distance_to(ground) < 0.3 and lofted.transform.basis.y.normalized().y < -0.3,
				"and comes down into the cell aimed at, nose down")
		_check(lob_sounds.call().count("sfx.arrow_lob_fall") == 1 and lob_sounds.call().has("sfx.arrow_land"), "and thuds in (%s)" % [lob_sounds.call()])
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
		while Time.get_ticks_msec() - start < 3000:
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
		print("  %s, a cell every %.2f s: %d cells, %d footfalls drawn, %d footsteps, %d clanks at %s ms; clips by frames %s" % [
				each[0], each[1], cells, falls, footsteps.size(), clanks.size(), clank_ms, clips])
		if each[2] == "":
			_check(clanks.is_empty() and falls > 0 and footsteps.size() <= cells, "%s: no clank, footsteps no more than a cell's (%d, %d footfalls)" % [each[0], footsteps.size(), falls])
		else:
			# Live, the body moved by teleports (World._relocate): its drawn gait wavers, so
			# the count against its footfalls is printed; the clips' own are checked above.
			_check(right_slot and falls > 0 and clanks.size() == footsteps.size() and clanks.size() <= cells,
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
	player.downed_until = World.tick  # Up again (a revival's end state).
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
	_test_plinth()
	_test_open_kinds()
	_test_plots()
	_test_camp()
	_test_decline()
	_test_inside()
	_test_inside_is_his()


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
	var broken := Level.blocks_outline(Level._union([Rect2i(2, 13, 6, 8)])).filter(func(key: Vector3i) -> bool: return _rig._wall_states.get(key) == "broken")
	_check(ruin.size() == 1 and ruin[0]["roof"] == null and broken.size() > 3 and not _rig._building_at.has(Vector2i(4, 16)),
			"the ruined house: no roof, no inside, %d of its walls broken" % broken.size())


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
	_check(Level.outline(house["rect"]).all(func(key: Vector3i) -> bool: return not _rig._wall_states.has(key)), "and its walls whole")
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
	_check(_rig._fire_lights.size() == torches.size() + fire.filter(func(c: Vector2i) -> bool: return _rig._grounds.has(c)).size()
			and energies.max() != energies.min() and World.light_at(cell) == before,
			"each fire's drawn light flickers; World's light stays as it was (%s)" % [energies])
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
	var foot := Vector2i(59, 20)
	var at := Vector3(foot.x, _rig._ground_height(Vector2(foot)), foot.y)
	var valley := Vector3(48.0, _rig._ground_height(Vector2(48.0, 72.0)), 72.0)
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
		if point.y < _rig._ground_height(spot) - 0.001:
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
	while step_index > 1 and (stepped.get("bridged", []) as Array).any(func(cell: Vector2i) -> bool: return (cell - (stream_path[step_index] as Vector2i)).length() < 4.0):
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
	var sample_level := Level.load_level("sample")
	_rig.rebuild(sample_level["terrain"], sample_level["centre"])
	var none_without := _rig._mists.is_empty()
	_rig.rebuild(hills["terrain"], hills["centre"])
	_check(misty and none_without, "mist at each tall fall's foot, %d puffs at most (%d curtains, %d mists), none without a fall (%s)" % [Client3D.MIST_PUFFS, curtains, _rig._mists.size(), none_without])
	_rig.rebuild(hills["terrain"], hills["centre"])
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
		for ledge: Dictionary in _rig._ledge_curves:
			var points: PackedVector2Array = ledge["curve"]["points"]
			for k in range(0, points.size(), 4):
				var high := _rig._ledge_ground(points[k], true)
				var low := _rig._ledge_ground(points[k], false)
				if high - low <= Relief.EPSILON:
					continue
				stretches += 1
				# The drawn ground just past the curve either side meets it.
				var t: Vector2 = (ledge["curve"]["tangents"] as PackedVector2Array)[k]
				var up := Vector2(-t.y, t.x) * float(ledge["up"])
				var above := _rig._ledge_ground(points[k] + up * 0.02, true)
				var below := _rig._ledge_ground(points[k] - up * 0.02, false)
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


## Built water (decision 595): water no curve lays (the wilds' wells) drawn
## square and still: each body over its own cells alone, its edge theirs, no
## shore field round it; natural water (a curve's) as before.
func _test_built_water() -> void:
	print("
== built water: the wilds' wells square and still, natural water from its curves ==")
	var wilds := Level.load_level("wilds")
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
	var uncovered := []
	for cell: Vector2i in rig._stream_cells:
		var middle := Vector2(cell)
		if not triangles.any(func(flat: PackedVector2Array) -> bool:
				return Geometry2D.point_is_inside_triangle(middle, flat[0], flat[1], flat[2])):
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
					if absf(_rig._road_near(edge).x) < 0.02 and absf(_rig.road_at(edge) - 0.5) > 0.13:
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
		# The castle's way to the wilds (327): past its south edge, three
		# rows of trees with a lane through them, then the wilds' road.
		_check(_rig._glimpses.size() == 1 and _rig._glimpse_plans[0]["to"] == "wilds",
				"a glimpse of the wilds past the castle's way there, none of the test room's dungeon (%s)" % [_rig._glimpse_plans.map(func(plan: Dictionary) -> String: return plan["to"])])
		if _rig._glimpses.size() == 1:
			var plan: Dictionary = _rig._glimpse_plans[0]
			var cells: Dictionary = plan["cells"]
			var on_land := cells.keys().filter(func(cell: Vector2i) -> bool: return land.has(cell)).size()
			var lane := [Vector2i(16, 24), Vector2i(16, 25), Vector2i(16, 26), Vector2i(15, 25), Vector2i(17, 25)]
			_check(on_land == 0 and lane.all(func(cell: Vector2i) -> bool: return cells.has(cell)) and cells.has(Vector2i(16, 33)),
					"none of it on our land; a lane from the link through the trees; the wilds' from_castle (128, 22) across from our link, at (16, 33)")
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
			and is_equal_approx(_rig.pitch, Client3D.LOW_PITCH),
			"the castle outdoors: perspective, LOW_FOV, LOW_FAR, LOW_PITCH (%s %.0f %.0f %.0f)" % [_rig._camera.projection, _rig._camera.fov, _rig._camera.far, _rig.pitch])
	_rig._ridge_pitch = 0.0  # The castle's ridge rule (525) lifts it otherwise; the flat's numbers here.
	var offset: Vector3 = _rig._camera_offset()
	_check(is_equal_approx(offset.length(), Client3D.CAMERA_DISTANCE * Client3D.LOW_DISTANCE_SHARE)
			and is_equal_approx(rad_to_deg(asin(offset.normalized().y)), Client3D.LOW_PITCH),
			"half the distance off, LOW_PITCH above the ground (%.1f, %.1f)" % [offset.length(), rad_to_deg(asin(offset.normalized().y))])
	var look_fog: float = _rig.canopied_look(_rig.weathered_look(_rig.seasoned_look(_rig._look, Season.at(World.fields.region, DayNight.now())), _rig._weather_view.weather),
			_rig._canopy_cover * World.fields.canopy_shade / DayNight.CANOPY_SHADE)["fog_density"]
	_check(is_equal_approx(_rig._environment.fog_density, look_fog + Client3D.LOW_FOG)
			and is_equal_approx(_rig._environment.fog_aerial_perspective, Client3D.LOW_AERIAL)
			and _rig._environment.background_mode == Environment.BG_SKY,
			"LOW_FOG of haze over the look's own, LOW_AERIAL of the sky in it, the day's sky behind (%.4f vs %.4f)" % [_rig._environment.fog_density, look_fog])
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
	_check(is_equal_approx(_rig.pitch, Client3D.LOW_PITCH), "and S, back to LOW_PITCH (%.0f)" % _rig.pitch)
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
		_check(faded != null and faded.shader == Client3D.SEASON_NEAR_SHADER and faded.render_priority == Client3D.NEAR_PRIORITY,
				"a near stand fades as a tree does (its season's see-through copy)")
		_rig._set_near(near[0], false)
		var again := drawn.get_active_material(0) as ShaderMaterial
		_check(again != null and again.shader == Client3D.SEASON_SHADER and not again.get_shader_parameter("leaf"),
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
				out.append(null if drawn == null or drawn.shader != Client3D.SEASON_SHADER else drawn.get_shader_parameter("leaf"))
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
	_check(faded != null and faded.shader == Client3D.SEASON_NEAR_SHADER and season_of.call(tree) == before,
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
	_check(("voice.death_%s" % body) in died and "sfx.death_player" in died and not "sfx.goblin_death" in died,
			"and dies as one: a person's fall and cry, no monster's (%s)" % [died])
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
	_check(bare > 4 and bare < 25, "a raid of 40: %d bare-headed" % bare)
	# A goblin among the townsfolk (decision 471, Snagfin): its kind's body, hood down, never a person's.
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
			and not (hoods[0] as MeshInstance3D).visible and "hood=down" in str(his.get_meta("goblin_look")["words"]),
			"a goblin resident is the goblin, its hood down (%s)" % [his_model.scene_file_path if his_model != null else "no model"])
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
	_check(heavy.playing() == Client3D.CLIP_HEAVY
			and is_equal_approx(heavy.speed(), ArtKit.feel("client3d.clip_heavy_contact", Client3D.CLIP_HEAVY_CONTACT) / (Monster.WINDUP_TICKS * World.TICK_DT)),
			"a brute winding up swings, timed to connect as its blow lands (%s x%.2f)" % [heavy.playing(), heavy.speed()])
	brute.swung.emit(Vector2i(-1, 0))
	_check(heavy.playing() == Client3D.CLIP_HEAVY, "and the blow itself plays no other clip over it (%s)" % heavy.playing())
	brute.winding.emit(Vector2i(-1, 0), Monster.WINDUP_TICKS)
	brute.winding.emit(Vector2i(-1, 0), 0)
	_check(not heavy.striking() and heavy.playing() != Client3D.CLIP_HEAVY and int(big.get_meta("busy_until", 0)) == 0,
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
## The low-angle fight, combat's (a): a telegraph with a shape is drawn as
## combat's outline cut to the sent cells, with a curtain along its edge
## drawn through bodies; one without a shape as the cells, as before.
func _test_telegraph_smooth() -> void:
	print("\n== a telegraph drawn smooth: the outline's fill cut to the sent cells, a curtain on its edge ==")
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
	var curtain: MeshInstance3D = entry["curtain"]
	_check(entry["quads"].size() == 1 and curtain != null, "one fill mesh and a curtain, not a quad a cell")
	var struck: Array[Vector2i] = []
	for cell in cells:
		struck.append(Vector2i(cell))
	var inside := func(point: Vector3) -> bool:
		for cell in struck:
			if absf(point.x - cell.x) <= 0.51 and absf(point.z - cell.y) <= 0.51:
				return true
		return false
	var fill_faces := (fill.mesh as ArrayMesh).get_faces()
	var out_cell := Vector2i(left_out)
	var stray := 0
	var in_left_out := 0
	for vertex in fill_faces:
		if not inside.call(vertex):
			stray += 1
		if absf(vertex.x - out_cell.x) < 0.49 and absf(vertex.z - out_cell.y) < 0.49:
			in_left_out += 1
	_check(fill_faces.size() >= 3 and stray == 0 and in_left_out == 0, "the fill lies within the sent cells only, none in the cell left out (%d vertices, %d stray)" % [fill_faces.size(), stray])
	var curtain_faces := (curtain.mesh as ArrayMesh).get_faces()
	var lowest := INF
	var highest := -INF
	for vertex in curtain_faces:
		lowest = minf(lowest, vertex.y)
		highest = maxf(highest, vertex.y)
	var material := curtain.material_override as StandardMaterial3D
	_check(curtain_faces.size() >= 6 and absf((highest - lowest) - Client3D.TELEGRAPH_CURTAIN) < 0.2 and material != null and material.no_depth_test
			and material.cull_mode == BaseMaterial3D.CULL_DISABLED,
			"the curtain stands TELEGRAPH_CURTAIN tall on the edge, drawn with no depth test, both faces (%d vertices, %.2f tall)" % [curtain_faces.size(), highest - lowest])
	var segments := Client3D.telegraph_curtain_segments(outline, Vector2(9, 4), struck)
	var outside := 0
	for segment in segments:
		var middle: Vector2 = (segment[0] + segment[1]) * 0.5
		if not inside.call(Vector3(middle.x, 0.0, middle.y)):
			outside += 1
	_check(segments.size() > 0 and outside == 0, "every curtain piece stands over a sent cell (%d pieces)" % segments.size())
	_rig.telegraph_tick(World.tick)
	var fill_alpha := (fill.material_override as StandardMaterial3D).albedo_color.a
	_check(is_equal_approx(material.albedo_color.a, _rig.curtain_alpha(fill_alpha)) and material.albedo_color.a > fill_alpha,
			"the tick tints the curtain brighter than the fill (%.2f over %.2f)" % [material.albedo_color.a, fill_alpha])
	_rig.telegraph_drop("smooth")
	_check(not _rig._telegraphs.has("smooth"), "dropped: gone, curtain and all")
	_rig.telegraph_show("plain", cells, World.tick, World.tick + 10)
	_check(_rig._telegraphs["plain"]["quads"].size() == cells.size() and _rig._telegraphs["plain"]["curtain"] == null, "a message without a shape: a quad a cell, no curtain, as before")
	_rig.telegraph_drop("plain")

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
		entity.queued_steps.clear()
		entity.has_move_order = false


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
	_rig._lay(puppet, puppet.get_node("Body"), 0.0)
	var body := puppet.get_node("Body") as Node3D
	var model := body.get_node("Model") as Node3D
	_check(rig.base_clip() == "Lie" and body.position.distance_to(Vector3(-Client3D.LIE_MIDDLE * float(puppet.get_meta("model_scale", 1.0)), 0, 0)) < 0.001
			and is_equal_approx(wrapf(model.rotation.y - float(puppet.get_meta("faces")), 0.0, TAU), PI),
			"asleep: lying (%s), turned to put the head the way it faces, on its cell (%s)" % [rig.base_clip(), body.position])
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
	# A one-handed weapon never swings a two-handed clip (the war hammer did: its left hand came up
	# beside the haft holding nothing).
	var two_handed_clips := ["Axe_Overhead"]
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
			_check(not reach.active, "the axe at rest: the left hand let go of grip_2")
			_rig._combat_at[id] = Time.get_ticks_msec()
			_rig._process(0.0)
			_check(rig.upper_clip() == "Axe_Ready" and reach.active and held.position == Vector3.ZERO, "a blow seen near it: taken up, ready, both hands on it (%s)" % rig.upper_clip())
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
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets[id]
	var sockets: Dictionary = puppet.get_meta("sockets")
	var rig := puppet.get_meta("rig") as AnimRig
	var hand := sockets["hand_l"] as Node3D
	var back := sockets["back"] as Node3D
	_check(hand.has_node("Held") and puppet.get_meta("bow_state") == "idle", "just taken up: the bow in hand (%s)" % puppet.get_meta("bow_state"))
	puppet.set_meta("roused_at", Time.get_ticks_msec() - 60000)
	_rig._combat_at.erase(id)
	_rig._process(0.0)
	var quiver := back.get_node("Quiver") as Node3D
	_check(not hand.has_node("Held") and back.has_node("StowedBow") and rig.upper_clip() == "",
		"calm a while: the bow on the back, the hands free (%s)" % rig.upper_clip())
	_check(quiver.position.is_equal_approx(Client3D.BOW_BACK[Client3D.bow_back_face][1]), "the quiver laid over it")
	_check(Client3D.in_hand(puppet) == ["", ""] and Client3D.fidget_with("Fidget_Shoulders", Client3D.in_hand(puppet)),
		"both hands empty to the fidgets (the arrows in the quiver): every fidget again")
	rig.loop(str((puppet.get_meta("gaits") as Array)[1][0]))
	_rig._sync_bow(player, puppet)
	_check(back.has_node("StowedBow") and rig.upper_clip() == "", "running calm: still on the back")
	rig.loop(Client3D.CLIP_IDLE)
	player.raised = "draw"
	player.raised_tick = World.tick
	_rig._process(0.0)
	_check(hand.has_node("Held") and not back.has_node("StowedBow") and rig.upper_clip() == "Bow_Draw" and quiver.position == Vector3.ZERO,
		"a draw: in hand at once, drawing (%s)" % rig.upper_clip())
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
	_check(not back.has_node("StowedBow") and back.get_node_or_null("Quiver") == null, "put away while on the back: gone from the back, and the quiver with it")
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
	var quiver := (sockets["back"] as Node3D).get_node_or_null("Quiver")
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
	for pace: Array in [[0.7, Client3D.CLIP_WALK], [1.4, Client3D.CLIP_WALK], [2.5, Client3D.CLIP_JOG], [1.2, Client3D.CLIP_JOG],
			[0.9, Client3D.CLIP_WALK], [5.5, Client3D.CLIP_SPRINT], [4.0, Client3D.CLIP_SPRINT], [3.5, Client3D.CLIP_JOG]]:
		puppet.set_meta("speed", float(pace[0]))
		# A second's walk, so the moment between this and _animate's own
		# clock (a few ms on a busy machine) is a tenth of a percent of it.
		puppet.set_meta("last_at", puppet.position - Vector3(float(pace[0]), 0.0, 0.0))
		puppet.set_meta("last_ms", Time.get_ticks_msec() - 1000)
		_rig._animate(puppet)
		var own := 0.0
		for gait: Array in Client3D.GAITS:
			if gait[0] == animator.playing():
				own = gait[1]
		_check(animator.playing() == pace[1] and absf(animator.speed() * own - float(pace[0])) < 0.05,
				"moving %.1f tiles a second: %s, its feet at that pace (x%.2f)" % [pace[0], animator.playing(), animator.speed()])
	puppet.set_meta("pace", own_pace)
	puppet.set_meta("speed", 0.7)
	puppet.set_meta("last_at", puppet.position - Vector3(0.07, 0.0, 0.0))
	puppet.set_meta("last_ms", Time.get_ticks_msec() - 100)
	_rig._animate(puppet)
	_check(animator.playing() == Client3D.CLIP_WALK and absf(animator.speed() * Client3D.GAITS[0][1] * own_pace - 0.7) < 0.05,
			"at its own pace (x%.2f of the clip's, its legs longer or shorter): x%.2f" % [own_pace, animator.speed()])
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
	yaw = (puppet.get_node("Body") as Node3D).rotation.y
	_check(absf(angle_difference(yaw, PI)) < 0.05, "and comes round to face it, yaw %.2f" % yaw)
	_check(animator.playing() == Client3D.CLIP_IMPACT,
			"there, hit nothing, it doubles over all the same, still facing it (%s)" % animator.playing())
	await _run_clock(Client3D.KNOCK_MIN_SECONDS + 0.8)
	_check(not puppet.has_meta("knock") and animator.playing() == Client3D.CLIP_IDLE, "come to rest: Idle again (%s)" % animator.playing())
	yaw = (puppet.get_node("Body") as Node3D).rotation.y
	_check(absf(angle_difference(yaw, was)) < 0.05, "and turned back to its own facing, yaw %.2f" % yaw)
	_push_imp(imp, Vector2i(1, 0))
	await _run_clock(0.05)
	_check(animator.playing() == Client3D.CLIP_BACKPEDAL, "pushed back again: it backpedals")
	await _run_clock(0.15)
	_step_imp(imp, Vector2i(-1, 0))
	await _run_clock(0.1)
	yaw = (puppet.get_node("Body") as Node3D).rotation.y
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
	yaw = (puppet.get_node("Body") as Node3D).rotation.y
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
	yaw = (puppet.get_node("Body") as Node3D).rotation.y
	_check(animator.playing() == Client3D.CLIP_ROLL and animator.speed() < 0.0
			and absf(angle_difference(yaw, -Vector2(0, 1).angle())) < 0.05,
			"tossed (-z): it rolls over backwards, facing whence it came (+z), yaw %.2f, speed %.2f" % [yaw, animator.speed()])
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
	var at_once: int = drawn.call()
	var once: Dictionary = meshes.call()
	var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	built[0] = 0
	_rig.rebuild(terrain, castle["centre"], true)
	var phasing := _rig.building_room
	var frames := 0
	while (_rig.building_room or _rig.ground_filling) and frames < 400:
		await get_tree().process_frame
		frames += 1
	_check(phasing and not _rig.building_room and not _rig.ground_filling and _rig._fill_jobs.is_empty()
			and frames >= _rig._room_phases().size() - 1 and built[0] == 1 and _rig._old_rooms.is_empty(),
			"building over %d frames, then whole, told once (%d), the last room freed" % [frames, built[0]])
	await _frames(Client3D.WARM_FRAMES + 2)
	_check(drawn.call() == at_once, "the same room as built at once (%d nodes, %d)" % [drawn.call(), at_once])
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
	frames = 0
	while (_rig.building_room or _rig.ground_filling) and frames < 400:
		await get_tree().process_frame
		frames += 1
	await _frames(Client3D.WARM_FRAMES + 2)
	_check(not is_instance_valid(first_room) and built[0] == 1 and drawn.call() == at_once,
			"a rebuild mid-build: the first's room gone, told once, the same room (%d nodes)" % drawn.call())
	_check(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) == orphans,
			"no orphan nodes left by the stopped build (%d, %d)" % [Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), orphans])
	_rig.room_built.disconnect(count_built)
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


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


## Long enough for a bar to fade all the way in or out.
func _fade() -> void:
	await get_tree().create_timer(1.0 / Client3D.HP_BAR_FADE + 0.1).timeout


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
	# Her front: the model's +X (Sleep_Side lies on her left side, her front where her left hand was), flat.
	var front := model.global_transform.basis.x
	front = Vector3(front.x, 0.0, front.z).normalized()
	var to_fire := Vector3(fire.x - her.tile.x, 0.0, fire.y - her.tile.y).normalized()
	_check(rig.base_clip() == "Sleep_Side" and str(puppet.get_meta("work", "")) == "sleep_side",
			"asleep: Sleep_Side, as her work (%s, %s)" % [rig.base_clip(), puppet.get_meta("work", "")])
	_check(front.dot(to_fire) > 0.99, "her front to the fire a cell off diagonally (%s, %s; yaw %.2f)" % [front, to_fire, yaw])
	var clip := rig.player.get_animation(rig._name("Sleep_Side")) if rig.has("Sleep_Side") else null
	_check(clip != null and absf(clip.length - 4.0) < 0.05 and clip.loop_mode != Animation.LOOP_NONE, "the breath slow: a 4 s loop")
	World._fire.erase(fire)
	_check(is_equal_approx(Client3D._sleeping_yaw(her, 0.5), 0.5), "no fire near: her own facing")
	her.asleep = false
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


func _spawn_imp(tile: Vector2i, kind := "") -> Monster:
	var occupant := World.get_entity_at(tile)
	if occupant != null:
		World.despawn(occupant)
	var spec := {"script": "res://sim/monster.gd", "shape": "capsule",
		"name": "ViewImp%d_%d" % [tile.x, tile.y], "tile": tile}
	if not kind.is_empty():
		spec["kind"] = kind
	var imp := _main._spawn(spec) as Monster
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
