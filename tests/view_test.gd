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
	Net.port = preload("res://tests/test_ports.gd").of(17791)  # Not 7777 (the editor may be hosting there), nor any other test's or eval's.
	_main = preload("res://main.tscn").instantiate()
	_main.returns = false  # The old respawn (decision 396 is return_test's).
	add_child(_main)
	_rig = preload("res://client3d/client3d.tscn").instantiate()
	_main.add_child(_rig)
	_rig.setup(_main._terrain)
	_main._client3d = _rig
	_rig.bubbles = _main.bubbles
	_rig._process(0.0)
	_rig.sfx.hear_everything = true  # Which sounds events make; who hears them is _test_heard_as_monsters_hear.

	_test_every_sound_has_its_files()
	await _test_hp_bars()
	_test_sounds_follow_events()
	await _test_bow_sounds()
	await _test_monster_death()
	await _test_companion_death()
	await _test_player_death()
	_test_settings()
	_test_ground_colours()
	await _test_fade()
	_test_outdoor()
	_test_pine_stands()
	_test_ground_textures()
	_test_canopy_mask()
	_test_grown_trees()
	await _test_warm_ups()
	_test_seasons()
	_test_heights()
	_test_hills()
	_test_shore()
	_test_ledges()
	_test_relax()
	_test_solid_ground()
	_test_water()
	_test_streams()
	_test_tall_grass()
	_test_rocks()
	_test_niches()
	_test_relief()
	_test_sight()
	_test_fire()
	await _test_wall_runs()
	_test_cave_walls()
	_test_scatter()
	_test_buildings()
	_test_roofs()
	_test_wall_heights()
	await _test_double_doors()
	_test_field()
	_test_kinds()
	_test_roof_damage()
	_test_building_states()
	_test_town_walls()
	await _test_near_miss_picks()
	await _test_target_marked()
	await _test_goblin()
	_test_humans()
	_test_person_looks()
	_test_person_garb()
	_test_attach_points()
	_test_bow()
	_test_standing_turn()
	_test_visible_work()
	_test_goblins_differ()
	_test_allies()
	_test_shadows_in_view()
	_test_no_2d_under_3d()
	await _test_doors_swing()
	await _test_door_states()
	_test_art_puppets()
	await _test_creature_puppets()
	_test_piles()
	_test_heard_as_monsters_hear()
	_test_ambience_runs()
	_test_options_panel()

	# Every sound stopped and let go before quitting: the audio server lets
	# a stopped sound's stream go a mix or two later, and one still held at
	# exit is reported as a leak.
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
		if World.is_walkable(each) and not World.is_water(each):
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
		player._world_shot(imp.tile)
		World.damage(imp, 1, player, &"shot"))
	_check(loosed.slice(0, 1) == ["sfx.bow_loose"] and not loosed.has("sfx.arrow_hit_flesh"),
			"loosed at the imp: the twang, its hit not yet (%s)" % [loosed])
	await get_tree().create_timer(0.5).timeout
	var after: Array[String] = []
	for entry: Array in _rig.sfx.played.slice(before):
		after.append(entry[0])
	_check(after.count("sfx.arrow_hit_flesh") == 1 and not after.any(func(slot: String) -> bool: return slot in ["sfx.arrow_land", "sfx.arrow_hit_stone", "sfx.arrow_hit_wood"]),
			"as the arrow arrives: its hit on flesh, once, and no miss (%s)" % [after])
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
	var miss := _rig.sfx.played.size()
	var unheard := _rig.sfx.unheard.size()
	var expected := Client3D._arrow_landed(player.tile, open)
	player._world_shot(open)
	await get_tree().create_timer(0.5).timeout
	_check((_rig.sfx.played.slice(miss).map(func(entry: Array) -> String: return entry[0]) + _rig.sfx.unheard.slice(unheard)).has(expected),
			"loosed at nobody: as it gets there, what stopped it (%s)" % expected)
	var friend := _companion()
	if friend != null and World.spares(player, friend):
		var heard := _rig.sfx.played.size()
		var unheard_before := _rig.sfx.unheard.size()
		player._world_shot(friend.tile)
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
	var blow := _heard(func() -> void: World.damage(imp, 1, player, &"attack"))
	_check(blow.slice(0, 1) == [SoundKit.hit(World.wielded(player))] and blow.slice(1) in [[], ["sfx.goblin_pain"]],
			"a blow just after the player's swing: its weapon's hit on flesh, the imp crying out now and then (%s)" % [blow])
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
	var pitch_light := _swing_pitch(imp)
	var pitch_heavy := _swing_pitch(player)
	_check(pitch_light > pitch_heavy, "an imp's swing is higher than a player's (%.2f, %.2f)" % [pitch_light, pitch_heavy])
	World.despawn(imp)
	_rig._process(0.0)


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
	_check("sfx.death_companion" in heard, "her death sound (%s)" % [heard])
	var words: String = _main.bubbles.text_of(puppet.get_instance_id())
	_check(words in Main.COMPANION_DEATH_LINES, "a last line, in a bubble over her body: %s" % words)
	_check(lantern != null and lantern.get_parent() == _rig, "her lantern is dropped, off the body")
	await get_tree().create_timer(Client3D.LANTERN_OUT_SECONDS + 0.2).timeout
	_check(not is_instance_valid(lantern), "and goes out")


func _test_player_death() -> void:
	print("\n== the local player's death: the camera pulls back and the colour drains ==")
	var player := _player()
	_rig._process(0.0)
	var size := _rig._camera.size
	World.damage(player, 999, null, &"attack")
	_rig._process(0.0)
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


func _test_scatter() -> void:
	print("\n== scatter off the grid by the ground, never on water; trees varied; the land runs into the forest floor ==")
	var castle := Level.load_level("castle")
	var terrain: Dictionary = castle["terrain"]
	_rig.rebuild(terrain, castle["centre"])
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


## BuildingComposer (decision 489): a wing's walls drawn to its own lower
## eaves; one look made once, its copies sharing their meshes; a round
## hut's one cone; a ruin with no roof, its walls broken here and there.
func _test_composer() -> void:
	print("\n== the composer: a wing's lower walls, one build a look, a round roof, a ruin (decision 489) ==")
	var main_wall: float = _rig._wall_heights.get(Vector3i(1, 4, Terrain.EAST), Client3D.WALL_HEIGHT)
	var wing_wall: float = _rig._wall_heights.get(Vector3i(11, 7, Terrain.EAST), Client3D.WALL_HEIGHT)
	_check(is_equal_approx(main_wall, Client3D.WALL_HEIGHT) and wing_wall < main_wall - 0.2 and wing_wall > main_wall - 0.6,
			"the main block's walls at its eaves (%.2f), the wing's a little lower (%.2f), not whole metres" % [main_wall, wing_wall])
	var level := _kinds_level([["building_l_house_small", Vector2i(1, 1), false], ["building_round_hut_small", Vector2i(13, 1), false],
		["building_house_small", Vector2i(1, 12), true]])
	var buildings: Array = level["buildings"]
	BuildingComposer.forget()
	var one := BuildingComposer.compose(buildings[0], "shingle")
	var two := BuildingComposer.compose(buildings[0], "shingle")
	var slopes := func(node: Node3D) -> Mesh: return (node.find_child("Slopes", true, false) as MeshInstance3D).mesh
	_check(one != two and slopes.call(one) == slopes.call(two) and BuildingComposer._made.size() == 1,
			"one look built once: two copies, one mesh between them")
	one.free()
	two.free()
	_rig.rebuild(level["terrain"], Vector2i(4, 11))
	var round_hut := _rig._buildings.filter(func(each: Dictionary) -> bool: return each["rect"] == Rect2i(14, 2, 5, 5))
	_check(round_hut.size() == 1 and (round_hut[0]["node"] as Node3D).find_child("Cone", true, false) != null,
			"the round hut: one cone over its blocks")
	var house := _rig._buildings.filter(func(each: Dictionary) -> bool: return each["rect"] == Rect2i(2, 2, 10, 8))
	var thatched: MeshInstance3D = (house[0]["roof"] as Node3D).find_child("Slopes", true, false) if house.size() == 1 else null
	_check(thatched != null and thatched.material_override == Client3D._roof_material("thatch") and ArtKit.has("material.roof.thatch"),
			"its roofs thatched, art-kit's thatch set there (decision 489 amended)")
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
func _kinds_level(stamps: Array) -> Dictionary:
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
	return Level.parse(map.to_image(), null, config)


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
	var castle := Level.load_level("castle")
	var terrain: Dictionary = castle["terrain"]
	_rig.rebuild(terrain, castle["centre"])
	var water: Array = terrain["water"]
	# Bodies by hand: cells joined side to side.
	var left: Dictionary = {}
	for cell: Vector2i in water:
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
		# Where the corner is drawn (decision 558 may move it).
		var drawn := _rig._drawn_corner(sloped, c)
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
			if _rig.shore_at(at) > 0.6 and bed[c] >= surface:
				dry_bed.append(cell)
				break
	_check(off_surface == 0 and heights_seen.size() > 3 and dry_bed.is_empty(),
			"a stream's ribbon slopes down its valley, on its curve's surface, never rising, over its bed, over all its cells (%d heights; off: %d, rising %d, under its bed %d, uncovered %s; beds above: %s)" % [heights_seen.size(), off_surface, rising, under_bed, covered["uncovered"].slice(0, 3), dry_bed.slice(0, 4)])
	# Its falls (decision 557, for sound's ambience): each a step down its
	# path of more than FALL_LEAST, the cell below it; a new array a build.
	var falls := _rig.stream_falls
	var true_falls := falls.all(func(fall: Dictionary) -> bool:
		var i := stream_path.find(fall["cell"])
		return i > 0 and absf(_rig._elevation(stream_path[i - 1]) - _rig._elevation(stream_path[i]) - float(fall["drop"])) < 0.001 				and float(fall["drop"]) > Client3D.FALL_LEAST)
	_rig.rebuild(hills["terrain"], hills["centre"])
	_check(not falls.is_empty() and true_falls and not is_same(falls, _rig.stream_falls) and falls == _rig.stream_falls,
			"the stream's falls listed, each a step down its path over %.2f m (%s), a new array each build" % [Client3D.FALL_LEAST, falls])
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
	_check(dry_falls.is_empty(), "each fall white on the water there (none: %s)" % [dry_falls])
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
	# The ridge laid on the cells' corners as drawn: the relax (decision 558)
	# set aside meanwhile.
	var had_quads := _rig._relax_quads.duplicate()
	_rig._relax_quads.clear()
	for d in range(3, 7):
		var cell := Vector2i((Vector2(at.x, at.z) + back * d).round())
		_rig._corners[cell] = PackedFloat32Array([at.y + 6.0, at.y + 6.0, at.y + 6.0, at.y + 6.0])
	var lifted := _rig.ridge_pitch(at)
	_rig._corners = had
	_rig._relax_quads = had_quads
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
	var parsed := Level.niches_from({"niches": [[1, 1, 0, 1, 2], [1, 1, 1, 1, 2], [1, 1, 0, 1, 4], [99, 99, 0, 1, 1]]},
			{"floor": [Vector2i(1, 1)]}, warnings)
	_check(parsed.size() == 1 and parsed[0]["out"] == Vector2i(0, 1) and parsed[0]["variant"] == 2 and warnings.size() == 3,
			"niches read as {cell, out, variant}; a diagonal way out, a bad variant and no floor said and left out (%d)" % warnings.size())
	var made := Regen.generate("barrow", 1)
	if made.is_empty():
		_check(false, "the barrow generates")
		return
	var level := Level.parse(made["layout"], made["height"], made["config"], made.get("relief"))
	var niches: Array = level["terrain"].get("niches", [])
	_check(not niches.is_empty() and niches.all(func(n: Dictionary) -> bool: return level["terrain"]["floor"].has(n["cell"])),
			"a generated barrow's niches reach the terrain, each on floor (%d)" % niches.size())
	_rig.rebuild(level["terrain"], level["centre"])
	var holder := _rig._room.get_node_or_null("Niches") as Node3D
	var by_variant: Dictionary = {}
	for n: Dictionary in niches:
		by_variant[n["variant"]] = by_variant.get(n["variant"], 0) + 1
	var drawn: Dictionary = {}
	var meshes_a_variant: Dictionary = {}
	if holder != null:
		for many: MultiMeshInstance3D in holder.find_children("*", "MultiMeshInstance3D", false, false):
			var variant := int(String(many.name).get_slice("_", 1))
			meshes_a_variant[variant] = meshes_a_variant.get(variant, 0) + 1
			if String(many.name).get_slice("_", 2) == "0":
				drawn[variant] = many.multimesh.instance_count
	_check(holder != null and drawn == by_variant and meshes_a_variant.values().all(func(c: int) -> bool: return c >= 2),
			"prop.burial_niche on each niche, a MultiMesh a variant and mesh, the lid with it (%s; meshes %s)" % [drawn, meshes_a_variant])
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


## The ledges' rims along a curve (decision 556): on relief a cap carries
## the higher ground out over the cell under it to a curve within
## SHORE_BOUND, never over a cell's middle, the faces down from it; the
## caps of two cells meet on their edge; a level without relief keeps its
## straight faces.
func _test_ledges() -> void:
	print("\n== ledges: rims along a curve on relief, within SHORE_BOUND, never over a cell's middle ==")
	var row := Client3D.RIM_RES + 1
	for name: String in ["hills", "sample", "castle", "wilds"]:
		var level := Level.load_level(name)
		_rig.rebuild(level["terrain"], level["centre"])
		if not bool(level["terrain"].get("relief_given", false)):
			_check(_rig._rim_caps.is_empty(),
					"%s (no relief): no caps, its faces on the cells' edges (%d faces)" % [name, _rig._cliff_edges.size()])
			continue
		var middles := []
		var astray := []
		var faces := 0
		var stray_faces := []
		var samples := 0
		for cell: Vector2i in _rig._rim_caps:
			var cap: Dictionary = _rig._rim_caps[cell]
			var tops: PackedFloat32Array = cap["tops"]
			var over: Array[Vector2i] = cap["over"]
			if tops[(row / 2) * row + row / 2] > -INF:
				middles.append(cell)
			for k in row * row:
				if tops[k] == -INF:
					continue
				samples += 1
				var point := Vector2(cell) + Vector2(k % row, k / row) / Client3D.RIM_RES - Vector2(0.5, 0.5)
				if float(Client3D._rim_nearest(point, over)[1]) > Client3D.SHORE_BOUND:
					astray.append([cell, point])
			for segment: Array in cap["segments"]:
				faces += 1
				for end: Vector2 in [segment[0], segment[1]]:
					var off := (end - Vector2(cell)).abs()
					if off.x > 0.5001 or off.y > 0.5001:
						stray_faces.append([cell, end])
		_check(not _rig._rim_caps.is_empty() and samples > 0 and middles.is_empty() and astray.is_empty(),
				"%s: %d cells capped (%d samples), none over a cell's middle (%s), all within %.2f of the cells over them (astray: %s)"
				% [name, _rig._rim_caps.size(), samples, middles.slice(0, 3), Client3D.SHORE_BOUND, astray.slice(0, 3)])
		_check(faces > 0 and stray_faces.is_empty(), "%s: %d faces down the rims' curves, each within its cell (stray: %s)" % [name, faces, stray_faces.slice(0, 3)])
		# Two capped cells side by side meet on their edge: the same cap there.
		var unmet := []
		for cell: Vector2i in _rig._rim_caps:
			for side: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var next := cell + side
				if not _rig._rim_caps.has(next):
					continue
				var mine: PackedFloat32Array = _rig._rim_caps[cell]["tops"]
				var theirs: PackedFloat32Array = _rig._rim_caps[next]["tops"]
				for t in row:
					var a := (t * row + Client3D.RIM_RES) if side.x == 1 else (Client3D.RIM_RES * row + t)
					var b := (t * row) if side.x == 1 else t
					if (mine[a] == -INF) != (theirs[b] == -INF) or (mine[a] > -INF and absf(mine[a] - theirs[b]) > 0.001):
						unmet.append([cell, next, t])
						break
		_check(unmet.is_empty(), "%s: capped cells side by side meet on their edge (unmet: %s)" % [name, unmet.slice(0, 4)])
		# What the camera sees takes the caps in; where a puppet stands doesn't.
		var shown := false
		for cell: Vector2i in _rig._rim_caps:
			var tops: PackedFloat32Array = _rig._rim_caps[cell]["tops"]
			for k in row * row:
				if tops[k] > -INF and not shown:
					var point := Vector2(cell) + Vector2(k % row, k / row) / Client3D.RIM_RES - Vector2(0.5, 0.5)
					shown = absf(_rig._drawn_height(point) - tops[k]) < 0.001 and _rig._ground_height(point) < tops[k] - 0.1
		_check(shown, "%s: the drawn height takes a cap in, a puppet's doesn't" % name)
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

## The ground relaxed (decision 558): on relief the free corners moved up
## to RELAX_MOST, none on a cliff's edge, each on the ground's surface;
## the cells beside a relaxed one meeting it on the same drawn edge (no gap,
## no sliver); _height_in the mesh's triangle; a level without relief as
## it was.
func _test_relax() -> void:
	print("\n== relax: natural ground's facets off the grid, the shape kept, no seam ==")
	for name: String in ["hills", "sample", "castle", "wilds"]:
		var level := Level.load_level(name)
		_rig.rebuild(level["terrain"], level["centre"])
		if not bool(level["terrain"].get("relief_given", false)):
			_check(_rig._relax_moves.is_empty() and _rig._relax_flips.is_empty(), "%s (no relief): its ground on the grid as it was" % name)
			continue
		var far := []
		for corner: Vector2i in _rig._relax_moves:
			if _rig._relax_moves[corner].length() > Client3D.RELAX_MOST + 0.0001:
				far.append(corner)
		var on_cliffs := []
		for edge: Array in _rig._cliff_edges:
			var cell: Vector2i = edge[0]
			var direction: Vector2i = edge[1]
			for corner in Client3D.GROUND_CORNERS:
				var at: Vector2i = cell + corner
				if Client3D.GROUND_CORNERS.has(at - cell - direction) and _rig._relax_moves.has(at):
					on_cliffs.append(at)
		_check(_rig._relax_moves.size() > 20 and far.is_empty() and on_cliffs.is_empty(),
				"%s: %d corners moved (%d cells split the other way), none past %.1f (%s), none on a cliff's edge (%s)"
				% [name, _rig._relax_moves.size(), _rig._relax_flips.size(), Client3D.RELAX_MOST, far.slice(0, 3), on_cliffs.slice(0, 3)])
		# Each moved corner a vertex of the mesh, at the ground's height there.
		var drawn: Dictionary = {}
		var triangles: Dictionary = {}
		for mesh: ArrayMesh in _rig._ground_meshes:
			var arrays := mesh.surface_get_arrays(0)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for point in points:
				drawn[Vector2i(roundi(point.x * 1000.0), roundi(point.z * 1000.0))] = point.y
			for t in range(0, indices.size(), 3):
				var tri := [points[indices[t]], points[indices[t + 1]], points[indices[t + 2]]]
				var middle: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
				var key := Vector2i(roundi(middle.x), roundi(middle.z))
				if not triangles.has(key):
					triangles[key] = []
				triangles[key].append(tri)
		var off_surface := []
		for corner: Vector2i in _rig._relax_moves:
			var at := Vector2(corner) - Vector2(0.5, 0.5) + _rig._relax_moves[corner]
			var under := Vector2i(roundi(at.x), roundi(at.y))
			var h := _rig._corner_heights(under)
			var f := at - Vector2(under) + Vector2(0.5, 0.5)
			var surface := lerpf(lerpf(h[0], h[1], f.x), lerpf(h[2], h[3], f.x), f.y)
			var key := Vector2i(roundi(at.x * 1000.0), roundi(at.y * 1000.0))
			if not drawn.has(key) or absf(float(drawn[key]) - surface) > 0.0001:
				off_surface.append(corner)
		_check(off_surface.is_empty(), "%s: each moved corner drawn there, on the ground's surface (off: %s)" % [name, off_surface.slice(0, 3)])
		# The seam: a relaxed cell and each cell beside it draw their shared
		# edge from the same two points, at the same heights along it.
		var seams := []
		var unmatched := []
		var checked := 0
		for corner: Vector2i in _rig._relax_moves:
			for a in 4:
				var cell: Vector2i = corner + Client3D.SHORE_AROUND[a]
				for side: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var next := cell + side
					if not _rig._grounds.has(next):
						continue
					var ends := []
					for c in 4:
						var k := Client3D.GROUND_CORNERS.find(cell + Client3D.GROUND_CORNERS[c] - next)
						if k >= 0:
							ends.append([_rig._drawn_corner(cell, c), _rig._drawn_corner(next, k)])
					if ends.size() != 2:
						continue
					var mine_a: Vector3 = ends[0][0]
					var mine_b: Vector3 = ends[1][0]
					if not mine_a.is_equal_approx(ends[0][1]) or not mine_b.is_equal_approx(ends[1][1]):
						if absf(mine_a.y - ends[0][1].y) <= Relief.EPSILON and absf(mine_b.y - ends[1][1].y) <= Relief.EPSILON:
							seams.append([cell, next])
						continue
					for t: float in [0.25, 0.5, 0.75]:
						checked += 1
						var p := Vector2(mine_a.x, mine_a.z).lerp(Vector2(mine_b.x, mine_b.z), t)
						if absf(_rig._height_in(cell, p) - _rig._height_in(next, p)) > 0.0001:
							unmatched.append([cell, next, t])
		_check(checked > 0 and seams.is_empty() and unmatched.is_empty(),
				"%s: relaxed cells meet the cells beside them on one drawn edge (%d points; apart: %s; heights differ: %s)"
				% [name, checked, seams.slice(0, 3), unmatched.slice(0, 3)])
		# _height_in the drawn triangle's, inside each relaxed cell.
		var wrong := []
		var sampled := 0
		for cell: Vector2i in _rig._grounds:
			if not _rig._relaxed(cell) or sampled > 1500:
				continue
			for p: Vector2 in [Vector2(-0.4, -0.4), Vector2(0.4, -0.4), Vector2(-0.4, 0.4), Vector2(0.4, 0.4), Vector2(0.1, -0.2)]:
				var point := Vector2(cell) + p
				var mesh_height := NAN
				for y in range(-1, 2):
					for x in range(-1, 2):
						for tri: Array in triangles.get(cell + Vector2i(x, y), []):
							var a: Vector3 = tri[0]
							var b: Vector3 = tri[1]
							var c: Vector3 = tri[2]
							if Geometry2D.point_is_inside_triangle(point, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)):
								var bary := Geometry3D.get_triangle_barycentric_coords(Vector3(point.x, 0.0, point.y), Vector3(a.x, 0.0, a.z), Vector3(b.x, 0.0, b.z), Vector3(c.x, 0.0, c.z))
								mesh_height = a.y * bary.x + b.y * bary.y + c.y * bary.z
				if is_nan(mesh_height):
					continue
				sampled += 1
				if absf(_rig._height_in(cell, point) - mesh_height) > 0.001:
					wrong.append([cell, p])
		_check(sampled > 100 and wrong.is_empty(), "%s: what stands on a relaxed cell stands on its drawn triangle (%d points; off: %s)" % [name, sampled, wrong.slice(0, 3)])
	_rig.rebuild(_main._terrain, Vector2i.ZERO)



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
					missing.append([cell, direction])
			else:
				slopes += 1
				if faces.has([cell, direction]):
					on_slopes.append([cell, direction])
	_check(ledges > 0 and missing.is_empty(), "a face down each of the %d cliff steps (missing: %s)" % [ledges, missing.slice(0, 5)])
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
	var wilds := Level.load_level("wilds")
	_rig.rebuild(wilds["terrain"], wilds["centre"])
	var on_wilds: Array = casting.call()
	_check(not on_hills.is_empty() and on_hills.all(func(s: int) -> bool: return s == GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
			and not on_wilds.is_empty() and on_wilds.all(func(s: int) -> bool: return s == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF),
			"the hills' ground casts its shadow (%d chunks), the wilds' (no relief) doesn't (%d)" % [on_hills.size(), on_wilds.size()])


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
		var surface: float = (_rig._water_bodies[0].mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX][0].y
		var forest_floor := _rig._room.get_node("ForestFloor") as Node3D
		_check(forest_floor.position.y < bed and bed < surface,
				"its water is drawn above its bed, and both above the forest floor, not hidden under it")
	var land: Dictionary = _rig._land
	var bare: Array[Vector2i] = []
	for cell: Vector2i in land:
		for direction: Vector2i in World.DIRECTIONS:
			var next := cell + direction
			if not land.has(next) and not _rig._trees.has(next) and next not in bare and not _rig._wooded.has(next) 					and not _rig._room.has_node("Deadwood_%d_%d" % [next.x, next.y]):
				bare.append(next)
	_check(not _rig._trees.is_empty() and bare.is_empty(),
			"a tree (or a felled one's stump) on every cell beside the land but a way's lane (%d trees; bare: %s)" % [_rig._trees.size(), bare.slice(0, 5)])
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
			_check(wooded == 0 and _rig._trees.has(Vector2i(14, 24)) and _rig._trees.has(Vector2i(18, 24)),
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


func _test_fade() -> void:
	print("\n== walls fade, a whole run at once, only where they hide the player from the camera, a moment longer ==")
	var player := _player()
	var start := player.tile
	var floor_cells: Array = _main._terrain["floor"]
	# A wall with floor on both sides: stand on its far side from the camera.
	var toward := _rig._camera.global_transform.basis.z
	var wall_key := Vector3i(-1, -1, -1)
	var behind := Vector2i.ZERO
	for key: Vector3i in _rig._walls:
		var cell := Vector2i(key.x, key.y)
		var normal := Vector2i(1, 0) if key.z == Terrain.EAST else Vector2i(0, 1)
		var other := cell + normal
		var far := cell if Vector2(normal).dot(Vector2(toward.x, toward.z)) > 0.0 else other
		if cell in floor_cells and other in floor_cells and World.get_entity_at(far) == null and _rig._height(cell) == _rig._height(other):
			wall_key = key
			behind = far
			break
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
	# every floor cell, the camera turned to each diamond and tilted.
	var differ := 0
	var asked := 0
	var found := 0
	for cell: Vector2i in floor_cells:
		for turn in 4:
			for tilt: float in [Client3D.PITCH_MIN, Client3D.CAMERA_PITCH, Client3D.PITCH_MAX]:
				var flat_way := flat.rotated(turn * PI * 0.5)
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
			and is_equal_approx(heavy.speed(), Client3D.CLIP_HEAVY_CONTACT / (Monster.WINDUP_TICKS * World.TICK_DT)),
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
	resident.free()
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
	_check(sockets.has_all(["hand_r", "hand_l", "back", "belt_l"]) and (sockets["hand_r"].get_parent() as BoneAttachment3D).bone_name == "RightHand",
			"a person has hand, back and belt sockets on their bones")
	var sword := (sockets["hand_r"] as Node3D).get_node_or_null("Held") as Node3D
	var shield := (sockets["hand_l"] as Node3D).get_node_or_null("Held") as Node3D
	_check(sword != null and shield != null, "a sword drawn in the right hand, a shield in the left")
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
		_check(grip.basis.y.normalized().dot(fist) > 0.9 and grip.origin.distance_to(knuckles) * scale < 0.06,
				"its grip in the fist (%.3f m from the knuckles), its length along the fist's axis (%.2f)" % [
				grip.origin.distance_to(knuckles) * scale, grip.basis.y.normalized().dot(fist)])
		_check(absf((skeleton.global_transform.basis * grip.basis).get_scale().y - 1.0) < 0.02,
				"at its own size, whatever the person's stature")
	if shield != null:
		_check((sockets["hand_l"] as Node3D).global_basis.x.normalized().dot(shield.global_basis.z.normalized()) > 0.99,
				"the shield's face (+z) out of the back of the hand")
	hold.call(player, "", "shield")
	_check((sockets["hand_r"] as Node3D).get_children().all(func(n: Node) -> bool: return n.is_queued_for_deletion()),
			"the hand emptied: nothing drawn in it")
	hold.call(player, "", "")
	_check((sockets["belt_l"] as Node3D).get_node_or_null("LanternBody") != null, "the lantern hangs at the belt")
	var imp := _spawn_imp(Vector2i(9, 6), "imp")
	_rig._process(0.0)
	hold.call(imp, "dagger", "")
	var goblin: Node3D = _rig._puppets[imp.get_instance_id()]
	var held: Node3D = (goblin.get_meta("sockets", {}) as Dictionary).get("hand_r")
	_check(held != null and held.get_node_or_null("Held") != null, "a goblin's dagger is in its hand")
	World.despawn(imp)
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
	_check(bow.find_child("Nocked", true, false) != null or not ArtKit.has("fx.arrow"), "an arrow on the string")
	# Scrubbed by the sim's draw (bow_pull): the nock by the ticks to draw_min,
	# then the pull by draw_of (0.5 at 10 of the bow's 20 ticks: a third of the
	# way from draw_min's 0.25 to 1).
	var alpha := World.tick_alpha
	World.tick_alpha = 0.0
	var length := rig.length("Bow_Draw")
	var poses := []
	for drawn: int in [3, 10, 15]:
		player.raised_tick = World.tick - drawn
		_rig._process(0.0)
		poses.append(rig.upper_position() / length)
	World.tick_alpha = alpha
	var expected := [Client3D.BOW_NOCK_END * 3.0 / 5.0, Client3D.BOW_NOCK_END + (1.0 - Client3D.BOW_NOCK_END) / 3.0,
			Client3D.BOW_NOCK_END + (1.0 - Client3D.BOW_NOCK_END) * 2.0 / 3.0]
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
	player.shot.emit(player.tile + Vector2i(4, 0))
	player.raised = ""
	_rig._process(0.0)
	_check(rig.upper_clip() == "Bow_Loose", "loosed: Bow_Loose (%s)" % rig.upper_clip())
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
	imp.shot.emit(aimed)
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
	var roll := animator.length(Client3D.CLIP_ROLL) / Client3D.ROLL_SPEED
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
			and is_equal_approx(rig.speed(), clampf(length * CreatureView.CONTACT / 0.6, AnimRig.STRIKE_SPEED_MIN, AnimRig.STRIKE_SPEED_MAX)),
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
