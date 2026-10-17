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
	await _test_monster_death()
	await _test_companion_death()
	await _test_player_death()
	_test_settings()
	_test_ground_colours()
	await _test_fade()
	_test_outdoor()
	_test_pine_stands()
	_test_seasons()
	_test_heights()
	_test_hills()
	_test_water()
	await _test_wall_runs()
	_test_cave_walls()
	_test_scatter()
	_test_buildings()
	_test_roofs()
	_test_wall_heights()
	_test_roof_damage()
	_test_building_states()
	_test_town_walls()
	await _test_near_miss_picks()
	await _test_target_marked()
	await _test_goblin()
	_test_humans()
	_test_goblins_differ()
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


func _test_options_panel() -> void:
	print("\n== O: the options panel, a slider per volume, moved: the bus follows, written when let go ==")
	var panel: OptionsPanel = _main.options_panel
	_check(panel != null and not panel.visible, "there, hidden")
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
	_check(panel.body_choice.selected == Net.BODIES.find(Net.player_body), "Character: the body shown as set")
	panel.body_choice.item_selected.emit(1)
	_check(Net.player_body == &"female"
			and "body=female" in FileAccess.get_file_as_string(Net._settings_override),
			"Female picked: Net's body and settings.cfg follow (decision 388)")
	panel.body_choice.item_selected.emit(0)
	DirAccess.remove_absolute(Net._settings_override)
	Net._settings_override = settings[0]
	Net.player_id = settings[1]
	Net.player_name = settings[2]
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
		var top := 0.0
		var body := _rig._walls[key].get_node("Body") as MeshInstance3D
		for local: Vector3 in (body.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var point := body.global_transform * local
			if Vector2(point.x - middle.x, point.z - middle.z).length() < 0.5:
				top = maxf(top, point.y - _rig._edge_base(key))
		_check(terrain["edges"].get(key) == Terrain.Edge.WALL and top >= Client3D.WALL_RUBBLE_LOW,
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
			var top := 0.0
			var body := _rig._walls[key].get_node("Body") as MeshInstance3D
			for local: Vector3 in (body.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				var point := body.global_transform * local
				if Vector2(point.x - middle.x, point.z - middle.z).length() < 0.45:
					top = maxf(top, point.y - _rig._edge_base(key))
			tops[key] = top
		var cap: float = Client3D._wall_set("castle")["cap"]
		_check(rubble_at in _rig._wall_breaches and tops[rubble_at] >= Client3D.WALL_RUBBLE_LOW and tops[rubble_at] <= Client3D.WALL_RUBBLE_HIGH + 0.01
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
	var map := LevelMap.new(Vector2i(16, 12))
	for y in 12:
		for x in 16:
			map.set_cell(Vector2i(x, y), "grass")
	var config := {"outdoor": true}
	for stamp: Array in [["building_temple", Vector2i(1, 1)], ["building_healers_hut", Vector2i(9, 1)]]:
		var changes := Prefab.stamp_changes(Prefab.load_prefab(stamp[0]), map, stamp[1], config)
		for cell: Vector2i in changes["cells"]:
			map.set_cell(cell, changes["cells"][cell])
		for key: Vector3i in changes["edges"]:
			map.set_edge(key, changes["edges"][key])
		config.merge(changes.get("config", {}), true)
	var level := Level.parse(map.to_image(), null, config)
	var rects := (level["buildings"] as Array).map(func(b: Dictionary) -> Array: return [b["slot"], b["rect"]])
	_check(rects == [["building.temple", Rect2i(2, 2, 4, 6)], ["building.healers_hut", Rect2i(10, 2, 3, 3)]]
			and (level["warnings"] as Array).filter(func(text: String) -> bool: return text.contains("building")).is_empty(),
			"each prefab stamps its building on its footprint, walled, nothing said (%s)" % [rects])
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


## levels/hills (decision 358): every ledge between two of its cells is a
## rock face, at every level from 1 to 4 (the plateau's cliff the tallest).
func _test_hills() -> void:
	print("
== hills: a rock face down every ledge, at every level ==")
	var hills := Level.load_level("hills")
	var terrain: Dictionary = hills["terrain"]
	_rig.rebuild(terrain, hills["centre"])
	var faces: Dictionary = {}
	for edge: Array in _rig._cliff_edges:
		faces[edge] = true
	var heights: Dictionary = terrain["heights"]
	var stairs: Dictionary = terrain["stairs"]
	var floor_cells: Dictionary = {}
	for cell: Vector2i in terrain["floor"]:
		floor_cells[cell] = true
	var missing := []
	var tops: Dictionary = {}
	var drops: Dictionary = {}
	for cell: Vector2i in floor_cells:
		var level: int = heights.get(cell, 0)
		for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := cell + direction
			if not floor_cells.has(next) or heights.get(next, 0) >= level or stairs.get(next) == -direction:
				continue
			tops[level] = true
			drops[level - int(heights.get(next, 0))] = true
			if not faces.has([cell, direction]):
				missing.append([cell, direction])
	_check(missing.is_empty() and tops.size() == 4 and drops.has(4),
			"a face on each of %d ledges, from tops at levels %s, drops of %s (missing: %s)" % [faces.size(), tops.keys(), drops.keys(), missing.slice(0, 5)])


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
	var low: int = terrain["heights"].get(stair, 0)
	var rise := Client3D.LEVEL_RISE
	_check(is_equal_approx(_rig._ground_height(Vector2(stair)), (low + 0.5) * rise)
			and is_equal_approx(_rig._ground_height(Vector2(stair) - Vector2(up) * 0.49), (low + 0.01) * rise)
			and is_equal_approx(_rig._ground_height(Vector2(stair) + Vector2(up) * 0.49), (low + 0.99) * rise),
			"a puppet on a stair stands on its ramp: half up at its middle, nearly a level up at its top edge")
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
		var level: int = heights.get(from, 0)
		var other: int = heights.get(to, 0)
		if level == other or stairs.get(from) == direction or stairs.get(to) == -direction:
			walked.append(edge)
	_check(not _rig._cliff_edges.is_empty() and walked.is_empty(),
			"a rock face only on a ledge, none where the sim walks (%d faces; on walked edges: %s)" % [_rig._cliff_edges.size(), walked])
	# A ramp's side: the cell beside it at the stair's height shares the
	# ramp's raised corner (one vertex for the stair, the cell above, and it).
	var welded := 0
	var sides := 0
	for side: Vector2i in [Vector2i(up.y, up.x), -Vector2i(up.y, up.x)]:
		var beside := stair + side
		if not _rig._grounds.has(beside) or heights.get(beside, 0) != low:
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
	_rig.hover(stair, true)
	var slope := Vector3(-up.x * rise, 1.0, -up.y * rise).normalized()
	_check(absf(_rig._hover.position.y - (low + 0.5) * rise) < 0.05 and _rig._hover.basis.y.dot(slope) > 0.999,
			"the hover outline lies on the ramp, tilted with it")
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
	_check(highest - lowest > rise * 0.9, "a builder ghost on the stair runs up its ramp (%.2f to %.2f)" % [lowest, highest])
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
	_check(not tops.is_empty() and tops.all(func(y: float) -> bool: return absf(y - 5 * rise - Client3D.ON_FLOOR * 2.0) < 0.01)
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
	_check(ringed == 0 and (forest_floor.material_override as ShaderMaterial).get_shader_parameter("albedo_color") == PineStands.NEEDLES,
			"under them the needles' floor; the land's ground runs only into the first ring")
	PineStands.stand_in = false
	PineStands.forget()
	_rig.rebuild(_main._terrain, Vector2i.ZERO)


## The season on terrain's side (environment's 362): the ground, trees and
## the forest's floors drawn in the season's shaders, by kind.
func _test_seasons() -> void:
	print("
== in season: broadleaf dries and turns, pines and dead wood only take snow ==")
	_check((Client3D.GROUND_SHADER as Shader).code.contains("global uniform vec4 season")
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
		(dead if kind == "tree.dead" else leaves).append_array(season_of.call(tree))
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
	_check(season_of.call(forest_floor) == [false] and canopy_leaf == true,
			"the forest floor snow only; the canopy past broadleaf turns with it")
	var tree: Node3D = _rig._trees.values()[0]
	var before: Array = season_of.call(tree)
	_rig._set_near(tree, true)
	var faded := tree.find_children("*", "MeshInstance3D", true, false)[0].get_active_material(0) as ShaderMaterial
	_rig._set_near(tree, false)
	_check(faded != null and faded.shader == Client3D.SEASON_NEAR_SHADER and season_of.call(tree) == before,
			"a near tree fades in its season's see-through copy, and is in season again after")
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


func _test_goblins_differ() -> void:
	print("\n== no two goblins alike: size by mass, their own pace and tempo, out of step; they look about, and stand tired ==")
	var imps: Array[Monster] = [_spawn_imp(Vector2i(9, 2), "imp"), _spawn_imp(Vector2i(10, 2), "imp")]
	var brute := _spawn_imp(Vector2i(11, 2), "brute")
	brute.mass = 70.0  # Before its puppet is made.
	_rig._process(0.0)
	var a: Node3D = _rig._puppets[imps[0].get_instance_id()]
	var b: Node3D = _rig._puppets[imps[1].get_instance_id()]
	var big: Node3D = _rig._puppets[brute.get_instance_id()]
	_check(big.has_meta("animator"), "a brute is the goblin too")
	var looks := func(puppet: Node3D) -> Array:
		return [snappedf(puppet.get_meta("model_scale"), 0.001), snappedf(puppet.get_meta("pace"), 0.001), snappedf(puppet.get_meta("tempo"), 0.001)]
	_check(looks.call(a) != looks.call(b), "two imps differ in size, pace or tempo (%s, %s)" % [looks.call(a), looks.call(b)])
	_check(absf(float(a.get_meta("model_scale")) - 1.0) <= Client3D.MODEL_SCALE_SPREAD + 0.001,
			"an imp is about the goblin's size (x%.2f)" % a.get_meta("model_scale"))
	_check(float(big.get_meta("model_scale")) > 1.12, "and the brute, heavier, bigger (x%.2f)" % big.get_meta("model_scale"))
	var animators: Array[AnimationPlayer] = [a.get_meta("animator"), b.get_meta("animator")]
	_check(absf(animators[0].current_animation_position - animators[1].current_animation_position) > 0.01,
			"standing side by side, out of step (%.2f s, %.2f s into Idle)" % [animators[0].current_animation_position, animators[1].current_animation_position])
	var again := RandomNumberGenerator.new()
	again.seed = hash(String(imps[0].name))
	_check(is_equal_approx(float(a.get_meta("model_scale")), clampf(1.0, Client3D.MODEL_SCALE_MIN, Client3D.MODEL_SCALE_MAX)
			* (1.0 + again.randf_range(-Client3D.MODEL_SCALE_SPREAD, Client3D.MODEL_SCALE_SPREAD))),
			"each the same on every view: seeded by its name")
	_check([a, b, big].all(func(p: Node3D) -> bool: return absf(float(p.get_meta("tempo")) - 1.0) <= Client3D.TEMPO_SPREAD + 0.001),
			"each its own tempo, within %d%%" % roundi(Client3D.TEMPO_SPREAD * 100.0))
	_rig._combat_at.erase(imps[0].get_instance_id())
	var fidgets: Array[String] = []
	for i in 40:
		a.set_meta("fidget_at", 0)
		a.set_meta("busy_until", 0)
		a.set_meta("fidgeting", false)
		_rig._animate(a)
		fidgets.append(animators[0].current_animation)
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
	_check(animators[0].current_animation == Client3D.CLIP_SIT_DOWN, "set to sit, it sits down (%s)" % animators[0].current_animation)
	a.set_meta("busy_until", 0)
	_rig._animate(a)
	_check(animators[0].current_animation == Client3D.CLIP_SITTING, "and stays sat (%s)" % animators[0].current_animation)
	imps[0].pose = Monster.Pose.STAND
	_rig._animate(a)
	_check(animators[0].current_animation == Client3D.CLIP_SIT_UP, "and gets up when it stands (%s)" % animators[0].current_animation)
	a.set_meta("busy_until", 0)
	a.set_meta("fidgeting", false)
	a.set_meta("speed", 2.0)
	a.set_meta("last_at", a.position - Vector3(0.2, 0.0, 0.0))
	a.set_meta("last_ms", Time.get_ticks_msec() - 100)
	_rig._animate(a)
	_check(Client3D.is_gait(animators[0].current_animation), "and goes when it moves, not looking about as it slides (%s)" % animators[0].current_animation)
	imps[1].hp = 2
	_rig._animate(b)
	_check(animators[1].current_animation == Client3D.CLIP_TIRED, "hurt, it stands tired (%s)" % animators[1].current_animation)
	var heavy := big.get_meta("animator") as AnimationPlayer
	brute.winding.emit(Vector2i(-1, 0), Monster.WINDUP_TICKS)
	_check(heavy.current_animation == Client3D.CLIP_HEAVY
			and is_equal_approx(heavy.speed_scale, Client3D.CLIP_HEAVY_CONTACT / (Monster.WINDUP_TICKS * World.TICK_DT)),
			"a brute winding up swings, timed to connect as its blow lands (%s x%.2f)" % [heavy.current_animation, heavy.speed_scale])
	brute.swung.emit(Vector2i(-1, 0))
	_check(heavy.current_animation == Client3D.CLIP_HEAVY, "and the blow itself plays no other clip over it (%s)" % heavy.current_animation)
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
		_check(model != null and model.scene_file_path == scene and puppet.has_meta("animator"),
				"%s: its puppet is %s, animated" % [body, scene.get_file()])
		if model == null or not puppet.has_meta("animator"):
			continue
		var animator := puppet.get_meta("animator") as AnimationPlayer
		_check(animator.current_animation == Client3D.CLIP_IDLE, "standing: Idle")
		var skeleton := puppet.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var y := func(bone: String) -> float:
			return (skeleton.global_transform * skeleton.get_bone_global_rest(skeleton.find_bone(bone)).origin).y
		_check(y.call("Head") > y.call("Hips") and y.call("Hips") > y.call("LeftFoot"), "upright: head over hips over feet")
		var low := INF
		var high := -INF
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			var box := mesh.global_transform * mesh.get_aabb()
			low = minf(low, box.position.y)
			high = maxf(high, box.end.y)
		var tall := float(Client3D.HUMAN_F["height"] if body == &"female" else Client3D.HUMAN["height"]) * float(puppet.get_meta("model_scale"))
		_check(absf(low - puppet.global_position.y) < 0.05 and absf(high - low - tall) < 0.12,
				"its feet on the ground (%.3f), %.2f m tall" % [low - puppet.global_position.y, high - low])
		var wanted := Vector2(player.facing).normalized()
		_check(_toes_ahead(puppet).dot(wanted) > 0.9, "its toes point where it faces (%s)" % _toes_ahead(puppet))
		var looks := {}
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			for surface in mesh.mesh.get_surface_count():
				var own := mesh.mesh.surface_get_material(surface)
				var drawn := mesh.get_active_material(surface)
				if own != null:
					looks[own.resource_name] = drawn
		_check(looks.has("palette") and looks["palette"] == load(ArtKit.PALETTE), "belt and boots on art-kit's palette")
		_check(looks.has("Tunic") and (looks["Tunic"] as BaseMaterial3D).albedo_color == puppet.get_meta("tint"),
				"the tunic in the player's colour")
	player.body = &"male"
	_rig._process(0.0)
	var pet := _companion()
	if pet != null:
		var wanted := &"male" if str(pet.traits.get("pronoun", "")) == "he" else &"female"
		var model: Node = _rig._puppets[pet.get_instance_id()].get_node_or_null("Body/Model")
		_check(pet.body == wanted and model != null
				and model.scene_file_path == str((Client3D.HUMAN if wanted == &"male" else Client3D.HUMAN_F)["scene"]),
				"%s, \"%s\" on her card, wears the %s body" % [pet.name, pet.traits.get("pronoun", ""), wanted])


func _test_goblin() -> void:
	print("\n== an imp is the goblin: a model that faces, walks, punches, flinches, is knocked about and dies ==")
	var player := _player()
	var imp := _spawn_imp(Vector2i(9, 4), "imp")
	_rig._process(0.0)
	var puppet: Node3D = _rig._puppets[imp.get_instance_id()]
	_check(puppet.get_node_or_null("Body/Model") != null and puppet.has_meta("animator"), "its puppet is the goblin model, animated")
	if not puppet.has_meta("animator"):
		return
	var animator := puppet.get_meta("animator") as AnimationPlayer
	var clips := Array(animator.get_animation_list())
	_check([Client3D.CLIP_IDLE, Client3D.CLIP_WALK, Client3D.CLIP_ATTACK, Client3D.CLIP_HIT, Client3D.CLIP_DEATH,
			Client3D.CLIP_BACKPEDAL, Client3D.CLIP_IMPACT, Client3D.CLIP_ROLL, Client3D.CLIP_LAND,
			Client3D.CLIP_JOG, Client3D.CLIP_SPRINT, Client3D.CLIP_LOOK_ABOUT, Client3D.CLIP_TIRED].all(
			func(clip: String) -> bool: return clip in clips)
			and (Client3D.ATTACK_CLIPS + Client3D.HIT_CLIPS + Client3D.DEATH_CLIPS + Client3D.FIDGETS.keys()
				+ [Client3D.CLIP_SIT_DOWN, Client3D.CLIP_SITTING, Client3D.CLIP_SIT_UP]).all(
			func(clip: String) -> bool: return clip in clips), "with all its clips (%s)" % [clips])
	_check(animator.current_animation == "Idle", "standing: Idle")
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
			if gait[0] == animator.current_animation:
				own = gait[1]
		_check(animator.current_animation == pace[1] and absf(animator.speed_scale * own - float(pace[0])) < 0.05,
				"moving %.1f tiles a second: %s, its feet at that pace (x%.2f)" % [pace[0], animator.current_animation, animator.speed_scale])
	puppet.set_meta("pace", own_pace)
	puppet.set_meta("speed", 0.7)
	puppet.set_meta("last_at", puppet.position - Vector3(0.07, 0.0, 0.0))
	puppet.set_meta("last_ms", Time.get_ticks_msec() - 100)
	_rig._animate(puppet)
	_check(animator.current_animation == Client3D.CLIP_WALK and absf(animator.speed_scale * Client3D.GAITS[0][1] * own_pace - 0.7) < 0.05,
			"at its own pace (x%.2f of the clip's, its legs longer or shorter): x%.2f" % [own_pace, animator.speed_scale])
	var blows := {}
	for i in 4:
		imp.swung.emit(Vector2i(1, 0))
		blows[animator.current_animation] = true
		_check(animator.current_animation in Client3D.ATTACK_CLIPS, "an attack: %s" % animator.current_animation)
	_check(blows.size() >= 2, "and not the same blow every time (%s)" % [blows.keys()])
	var blow := animator.current_animation
	_rig._animate(puppet)
	_check(animator.current_animation == blow, "played out, not cut off by walking")
	imp.struck.emit(1, &"attack")
	_check(animator.current_animation in Client3D.HIT_CLIPS, "struck: %s" % animator.current_animation)
	await get_tree().create_timer(0.6).timeout
	var was := (puppet.get_node("Body") as Node3D).rotation.y
	_push_imp(imp, Vector2i(1, 0))
	# The first frame that turns it, against the ease for that frame's own
	# length: a wall-clock wait let one slow frame bring it all the way round.
	var turn := await _first_turn(puppet)
	var yaw: float = turn[0]
	var eased := absf(angle_difference(was, PI)) * exp(-GridEntity.TURN_RATE * float(turn[1]))
	_check(animator.current_animation == Client3D.CLIP_BACKPEDAL and absf(angle_difference(yaw, PI)) > 0.0
			and absf(absf(angle_difference(yaw, PI)) - eased) <= 0.1 * eased + 0.001,
			"pushed back (+x): it backpedals, turning (not snapping) toward whence it came (-x), yaw %.2f from %.2f (%.2f expected after a %.0f ms frame)"
			% [yaw, was, PI - eased, float(turn[1]) * 1000.0])
	await _run_clock(0.3)
	yaw = (puppet.get_node("Body") as Node3D).rotation.y
	_check(absf(angle_difference(yaw, PI)) < 0.05, "and comes round to face it, yaw %.2f" % yaw)
	_check(animator.current_animation == Client3D.CLIP_IMPACT,
			"there, hit nothing, it doubles over all the same, still facing it (%s)" % animator.current_animation)
	await _run_clock(Client3D.KNOCK_MIN_SECONDS + 0.8)
	_check(not puppet.has_meta("knock") and animator.current_animation == Client3D.CLIP_IDLE, "come to rest: Idle again (%s)" % animator.current_animation)
	yaw = (puppet.get_node("Body") as Node3D).rotation.y
	_check(absf(angle_difference(yaw, was)) < 0.05, "and turned back to its own facing, yaw %.2f" % yaw)
	_push_imp(imp, Vector2i(1, 0))
	await _run_clock(0.05)
	_check(animator.current_animation == Client3D.CLIP_BACKPEDAL, "pushed back again: it backpedals")
	await _run_clock(0.15)
	_step_imp(imp, Vector2i(-1, 0))
	await _run_clock(0.1)
	yaw = (puppet.get_node("Body") as Node3D).rotation.y
	_check(not puppet.has_meta("knock") and Client3D.is_gait(animator.current_animation) and absf(angle_difference(yaw, PI)) < 0.3,
			"walking straight back: the knock is over and it walks back facing the way it goes, not backpedals (%s, yaw %.2f)" % [animator.current_animation, yaw])
	await _run_clock(1.0)
	# As a client that never drew the slide: the body is just there.
	var from := imp.tile
	World._relocate(imp, from + Vector2i(1, 0))
	imp._world_slide_from(from, World.tick - 5, 1)
	imp._world_pushed(1, false, false, from, World.tick - 5, 1, 0)
	await _run_clock(0.1)
	_check(animator.current_animation == Client3D.CLIP_BACKPEDAL, "a push whose slide never showed: it still backpedals where it stands (%s)" % animator.current_animation)
	await _run_clock(0.3)
	yaw = (puppet.get_node("Body") as Node3D).rotation.y
	_check(absf(angle_difference(yaw, PI)) < 0.05, "facing whence it came, from what the sim says, yaw %.2f" % yaw)
	await _run_clock(1.0)
	_push_imp(imp, Vector2i(0, 1))
	imp.impacted.emit(2, &"stone")
	await _run_clock(0.05)
	_check(animator.current_animation == Client3D.CLIP_BACKPEDAL, "pushed into a wall: it backpedals there first (%s)" % animator.current_animation)
	await _run_clock(0.25)
	_check(animator.current_animation == Client3D.CLIP_IMPACT, "and doubles over when it gets there (%s)" % animator.current_animation)
	await _run_clock(1.0)
	imp.impacted.emit(1, &"wood")
	_check(animator.current_animation == Client3D.CLIP_IMPACT, "shoved against a door where it stands: doubles over at once")
	await _run_clock(1.0)
	_push_imp(imp, Vector2i(0, -2), true)
	await _run_clock(0.3)
	yaw = (puppet.get_node("Body") as Node3D).rotation.y
	_check(animator.current_animation == Client3D.CLIP_ROLL and animator.get_playing_speed() < 0.0
			and absf(angle_difference(yaw, -Vector2(0, 1).angle())) < 0.05,
			"tossed (-z): it rolls over backwards, facing whence it came (+z), yaw %.2f, speed %.2f" % [yaw, animator.get_playing_speed()])
	var roll := animator.get_animation(Client3D.CLIP_ROLL).length / Client3D.ROLL_SPEED
	await _run_clock(roll)
	_check(animator.current_animation == Client3D.CLIP_LAND, "then lands (%s)" % animator.current_animation)
	await _run_clock(1.4)
	World.damage(imp, 999, player, &"attack")
	_rig._process(0.0)
	_check(puppet.has_meta("corpse") and animator.current_animation in Client3D.DEATH_CLIPS, "killed: %s" % animator.current_animation)
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
	doorway.remove_meta(&"states")
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
	doorway.remove_meta(&"states")
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
	_check(Client3D.art_slot_for(crate) == "", "and back to its cube when the art is gone")


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
	var player := art.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	_check(player.get_animation(view.clips["walk"]).loop_mode == Animation.LOOP_LINEAR
			and player.get_animation(view.clips["death"]).loop_mode == Animation.LOOP_NONE, "its walk loops, its death plays once")
	view.frame(puppet, boar)
	_check(player.current_animation == view.clips["idle"], "standing still: idle")
	view.wind(0.6)
	_check(player.current_animation == view.clips["attack"] and player.speed_scale > 0.0, "a wound-up blow plays its headbutt")
	_check(view.die() > 0.0 and player.current_animation == view.clips["death"], "dying plays its death")
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
	var player := _rig.sfx.get_child(_rig.sfx.get_child_count() - 1) as AudioStreamPlayer3D
	return player.pitch_scale if _rig.sfx.get_child_count() > before else 0.0


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
