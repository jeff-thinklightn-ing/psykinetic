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
	_test_heights()
	_test_water()
	_test_wall_runs()
	_test_scatter()
	_test_buildings()
	await _test_near_miss_picks()
	await _test_target_marked()
	await _test_goblin()
	_test_goblins_differ()
	_test_shadows_in_view()
	_test_no_2d_under_3d()
	await _test_doors_swing()
	_test_art_puppets()
	_test_piles()

	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


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
	_check(_heard(func() -> void: player._world_swung(Vector2i(1, 0))) == ["sfx.swing"], "a swing: a whoosh")
	_check(_heard(func() -> void: World.damage(imp, 1, player, &"attack")) == ["sfx.hit_flesh"], "a blow: a thud on flesh")
	_check(_heard(func() -> void: World._impact(imp, 1, player, &"stone")) == ["sfx.knockback_stone"], "into a wall: stone")
	_check(_heard(func() -> void: World._impact(imp, 1, player, &"wood")) == ["sfx.knockback_wood"], "into a door or crate: wood")
	_check(_heard(func() -> void: World._impact(imp, 1, player, &"body")) == ["sfx.knockback_body", "sfx.knockback_body_soft"],
			"into another body: a thud, and a softer one")
	_check(_heard(func() -> void: World.damage(imp, 1, null, &"fire")).is_empty(), "fire: nothing yet (no fire sounds in the packs)")
	var door: Door = World.get_doors()[0]
	_rig._process(0.0)
	_check(_heard(func() -> void: World._set_door(door, not door.open, player); _rig._process(0.0)) == [
			"sfx.door_wood_open" if door.open else "sfx.door_wood_close"], "a door: open or close, as it went")
	_check(_heard(func() -> void: World._relocate(imp, imp.tile + Vector2i(0, 1)); _rig._process(0.0)) == ["sfx.footstep"],
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
		if not _rig._land.has(cell) and absf(off.x) <= 0.45 and absf(off.y) <= 0.45 and off.length() > 0.1 \
				and sapling.scale.y < _rig._trees[cell].scale.y:
			inside += 1
	_check(_rig._saplings.size() > 0 and inside == _rig._saplings.size(),
			"saplings at the edge, smaller than its trees, off their void cell's middle and in it (%d of %d)" % [inside, _rig._saplings.size()])
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
	# Plain walls (a building's): whole and level, the cap at WALL_HEIGHT.
	for key: Vector3i in terrain["edges"]:
		if terrain["edges"][key] == Terrain.Edge.WALL:
			_rig._plain_walls[key] = true
	_rig.rebuild(terrain, castle["centre"])
	var level := true
	for key: Vector3i in _rig._walls:
		var body := _rig._walls[key].get_node("Body") as MeshInstance3D
		var top := -INF
		for point: Vector3 in (body.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			top = maxf(top, point.y)
		level = level and is_equal_approx(top, Client3D.WALL_HEIGHT)
	_check(_rig._wall_breaches.is_empty() and level, "plain walls: no breach, no broken top, every cap at %s m" % Client3D.WALL_HEIGHT)
	_rig._plain_walls.clear()
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
== buildings: the slot's roof and floor over the footprint; the roof off, its shadow kept, while the player is inside ==")
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
	_check(house["roof"] != null and node.get_node_or_null("floor") != null, "each has its roof and its inside floor")
	_check(Level.BUILDINGS.keys().all(func(slot: String) -> bool:
		var footprint: Array = ArtKit.spec(slot).get("footprint", [])
		return footprint.size() == 2 and Vector2i(int(footprint[0]), int(footprint[1])) == Level.BUILDINGS[slot]),
			"the sim's footprints are art-kit's slots' (Level.BUILDINGS)")
	_check(not well.is_empty() and not _rig._building_at.has(Vector2i(11, 10)) and _rig._dry_water.has(Vector2i(11, 10))
			and not _rig._plain_walls.has(Vector3i(11, 10, Terrain.EAST)), "the well: no inside, no walls, its water drawn dry under its rim")
	_check(Level.outline(house["rect"]).all(func(key: Vector3i) -> bool: return _rig._plain_walls.has(key)),
			"its outline is drawn plain, level under its roof (decision 252)")
	_check(node.position.is_equal_approx(Vector3(4.5, Client3D.BUILDING_LIFT, 5.5)) and is_equal_approx(node.rotation.y, 0.0),
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
			if not land.has(next) and not _rig._trees.has(next) and next not in bare:
				bare.append(next)
	_check(not _rig._trees.is_empty() and bare.is_empty(), "a tree on every cell beside the land (%d trees; bare: %s)" % [_rig._trees.size(), bare.slice(0, 5)])
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
	_rig.rebuild(_main._terrain, Vector2i.ZERO)
	_check(not _rig._outdoor and _rig._trees.is_empty() and _rig._environment.background_mode == Environment.BG_COLOR,
			"and back in the test room, it is under stone again")


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
		var light := World.light_at(cell, false)
		if is_equal_approx(shade.x, snappedf(lerpf(Client3D.FLOOR_DARKEST, 1.0, light), 0.1)):
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
	Net.save_settings("127.0.0.1", 17789, "", "Tester")
	var text := FileAccess.get_file_as_string(path)
	_check("hp_bars=0" in text and "master_volume=0.5" in text and "colour_blind=yes" in text,
			"a rewrite keeps the lines the game does not write itself")
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


# --- helpers ------------------------------------------------------------------

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
