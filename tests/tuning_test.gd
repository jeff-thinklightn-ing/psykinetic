extends Node
## Feel tuning in a local host (decision 673): each kind of field applied
## at once and reset; refused anywhere but a host (a joined client, a
## server: the box never runs it or reads a save); a save holding only what
## changed, beside the repo's values, in a scratch folder; read back in;
## the time scales, the pause and the frame step of exactly one tick; the
## practice dummy that never dies and is full again when let be; a passive
## kind standing; a thing given to the right place. Scripted like
## combat_test: a small room, World stepped by hand.

const PLAYER := {"script": "res://sim/player.gd", "shape": "capsule"}

var _failures := 0
var _room: Node2D


func _ready() -> void:
	World.set_process(false)
	Tuning.save_dir = preload("res://tests/test_ports.gd").scratch("saves")
	Tuning.review_dir = preload("res://tests/test_ports.gd").scratch_path("review")
	var mode := Net.mode
	Net.mode = Net.Mode.HOST

	_test_fields()
	_test_apply_and_reset()
	_test_source()
	_test_refused()
	_test_save_and_load()
	_test_time()
	_test_dummy()
	_test_give()
	_test_hall_unreached()

	Tuning.reset_all()
	Tuning.plain_time()
	Net.mode = mode
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_fields() -> void:
	print("\n== the fields: what is already data, each with its kind and range ==")
	var by_path := {}
	for row in Tuning.fields():
		by_path[row["path"]] = row
	var want := {"combat.swing_base": "float", "combat.recover_at": "int", "combat.moves.spin.windup": "float",
		"physics.knockback_min_speed": "float", "items.bow.drain": "int", "items.bow.steps": "ints",
		"items.bow.damage_at": "floats", "items.spear.cells": "int", "items.spear.brace": "bool"}
	for path: String in want:
		_check(by_path.has(path) and by_path[path]["kind"] == want[path] and by_path[path]["takes"] == "now",
				"%s: a %s field (%s)" % [path, want[path], by_path.get(path)])
	_check(not by_path.has("items.bow.draw_full") and not by_path.has("items.bow.cells") and not by_path.has("items.bow.says"),
			"a bow's worked-out ticks to full draw and longest step, and its words, are not fields")


func _test_apply_and_reset() -> void:
	print("\n== a change takes at once; reset puts the repo's value back ==")
	_check(Tuning.apply("combat.swing_base", 5) and is_equal_approx(World.swing_base, 5.0), "swing_base 5 (%s)" % World.swing_base)
	_check(Tuning.apply("combat.recover_at", 40.6) and World.recover_at == 41, "an int field takes a whole number (%s)" % World.recover_at)
	var windup: Variant = World.moves["spin"]["windup"]
	_check(Tuning.apply("combat.moves.spin.windup", 9) and is_equal_approx(float(World.moves["spin"]["windup"]), 9.0),
			"the spin's windup 9 (%s)" % World.moves["spin"]["windup"])
	_check(Tuning.apply("physics.knockback_min_speed", 2.5) and is_equal_approx(World.knockback_min_force, 2.5),
			"physics.json's name, World's var (%s)" % World.knockback_min_force)
	var full_before := float(Items.verb_of("bow")["draw_full"])
	_check(Tuning.apply("items.bow.drain", 4) and int(Items.verb_of("bow")["drain"]) == 4, "the bow's drain 4")
	_check(Tuning.apply("items.bow.full", 3) and float(Items.verb_of("bow")["draw_full"]) > full_before,
			"full draw a step later: its ticks worked out anew (%s -> %s)" % [full_before, Items.verb_of("bow")["draw_full"]])
	_check(Tuning.apply("items.bow.draw_steps", [3, 3, 3, 3, 3]) and Items.verb_of("bow")["draw_steps"] == [3, 3, 3, 3, 3],
			"a list field takes a list (%s)" % [Items.verb_of("bow")["draw_steps"]])
	_check(not Tuning.apply("combat.swing_base", "soon") and not Tuning.apply("combat.swing_base", -1)
			and not Tuning.apply("items.bow.steps", 4) and not Tuning.apply("combat.nothing", 1) and not Tuning.apply("items.bow.nothing", 1),
			"refused: a word, under 0, a number for a list, an unknown field")
	_check(Tuning.changes().size() == 7, "seven changed (%s)" % [Tuning.changes().keys()])
	_check(Tuning.reset("combat.swing_base") and is_equal_approx(World.swing_base, 3.0) and Tuning.changes().size() == 6, "swing_base reset to 3")
	Tuning.apply("combat.whiff_scale", 1.25)
	_check(not Tuning.changes().has("combat.whiff_scale"), "set to the repo's own value: no change kept")
	Tuning.reset_all()
	_check(World.recover_at == 25 and World.moves["spin"]["windup"] == windup and int(Items.verb_of("bow")["drain"]) == 1
			and int(Items.verb_of("bow")["full"]) == 2 and is_equal_approx(float(Items.verb_of("bow")["draw_full"]), full_before)
			and Tuning.changes().is_empty(), "reset all: every one back, nothing changed")


var _fake := {"blend": 0.15}


func _test_source() -> void:
	print("
== a tree's own fields, registered (pc-character's feel, the camera's) ==")
	Tuning.register_source("fake", func(path: String) -> Variant: return _fake.get(path.get_slice(".", 1)),
		func(path: String, v: Variant) -> bool:
			_fake[path.get_slice(".", 1)] = v
			return true,
		func() -> Array: return [{"path": "fake.blend", "group": "Fake", "min": 0.0, "max": 0.5, "owner": "test", "takes": "spawn"}])
	var row: Array = Tuning.fields().filter(func(r: Dictionary) -> bool: return r["path"] == "fake.blend")
	_check(row.size() == 1 and row[0]["kind"] == "float" and row[0]["takes"] == "spawn", "listed with its kind and when it takes (%s)" % [row])
	_check(Tuning.apply("fake.blend", 0.3) and is_equal_approx(_fake["blend"], 0.3), "set through its setter")
	_check(Tuning.reset("fake.blend") and is_equal_approx(_fake["blend"], 0.15), "and reset")
	Tuning._sources.erase("fake")
	_test_gait_paces()


## The people's gait paces in feel.json (674 step 3): untouched, the same as
## Client3D's tables (the move changes no walk in game); a row each on the
## panel; set from it, the gait's pace read where it's used; reset, the
## table's again; another table (the orc's) as it is.
func _test_gait_paces() -> void:
	print("\n== the gait paces in feel.json, untouched the tables' ==")
	var same := true
	for table: Array in [Client3D.HUMAN_GAITS, Client3D.HUMAN_F_GAITS]:
		var paced := Client3D.paced(table)
		same = same and paced.size() == table.size()
		for i in table.size():
			same = same and paced[i][0] == table[i][0] and float(paced[i][1]) == float(table[i][1])
	_check(same, "the man's and the woman's paces as HUMAN_GAITS and HUMAN_F_GAITS, exactly")
	Tuning.register_source("feel", ArtKit.feel_value, ArtKit.set_feel_value, ArtKit.feel_fields)
	var paths: Array = Tuning.fields().map(func(r: Dictionary) -> String: return str(r["path"]))
	var listed := true
	for clip: String in ["Walk", "Jog_Short", "Sprint_Short"]:
		listed = listed and ("feel.client3d.gait." + clip) in paths and ("feel.client3d.gait_f." + clip) in paths
	_check(listed, "a row each on the panel, his and hers")
	_check(Tuning.apply("feel.client3d.gait.Jog_Short", 3.9) and is_equal_approx(float(Client3D.paced(Client3D.HUMAN_GAITS)[1][1]), 3.9)
		and is_equal_approx(float(Client3D.paced(Client3D.HUMAN_F_GAITS)[1][1]), 3.44), "his jog set to 3.9: his read so, hers not")
	_check(Tuning.reset("feel.client3d.gait.Jog_Short") and is_equal_approx(float(Client3D.paced(Client3D.HUMAN_GAITS)[1][1]), 3.63),
		"reset: the table's again")
	_check(Client3D.paced(Client3D.ORC_GAITS) == Client3D.ORC_GAITS, "the orc's table as it is")
	Tuning._sources.erase("feel")


func _test_refused() -> void:
	print("\n== only a local host: a joined client's keys and a server do nothing ==")
	for mode: int in [Net.Mode.CLIENT, Net.Mode.SERVER]:
		Net.mode = mode
		var words := "a client" if mode == Net.Mode.CLIENT else "a server (the box)"
		var scale := Engine.time_scale
		_check(not Tuning.allowed() and not Tuning.apply("combat.swing_base", 9) and is_equal_approx(World.swing_base, 3.0),
				"%s: no change taken" % words)
		Tuning.cycle_scale()
		Tuning.toggle_pause()
		_check(is_equal_approx(Engine.time_scale, scale) and not Tuning.paused, "%s: F8 and F9 leave time alone" % words)
		_check(Tuning.save() == "" and Tuning.load_file(_a_save()) == -1 and is_equal_approx(World.swing_base, 3.0),
				"%s: nothing saved, a save never read" % words)
		var main: Node = load("res://main.gd").new()
		var keys_ok := true
		for code: int in [KEY_F7, KEY_F8, KEY_F9, KEY_PERIOD]:
			var key := InputEventKey.new()
			key.keycode = code as Key
			key.pressed = true
			keys_ok = keys_ok and not main.tuning_key(key)
		main.free()
		_check(keys_ok and is_equal_approx(Engine.time_scale, scale), "%s: Main takes none of F7, F8, F9, \".\"" % words)
	Net.mode = Net.Mode.HOST
	_check(Tuning.allowed(), "a host: allowed")
	_check(_no_save_read_elsewhere(), "nothing but the panel reads a save: no script calls Tuning.load_file")


## A save written as a host would, for the refused modes to be handed.
func _a_save() -> String:
	DirAccess.make_dir_recursive_absolute(Tuning.save_dir)
	var path := Tuning.save_dir.path_join("handed.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"changes": {"combat.swing_base": {"value": 9, "repo": 3}}}))
	file.close()
	return path


## No script but Tuning's own names load_file: no start-up, server or box
## path reads a tuning save (the panel, ui's, will call it on a click).
func _no_save_read_elsewhere() -> bool:
	for path in _scripts("res://"):
		if path in ["res://sim/tuning.gd"]:
			continue
		if FileAccess.get_file_as_string(path).contains("Tuning.load_file") and not path.begins_with("res://render/") and not path.begins_with("res://ui/"):
			print("    %s reads a tuning save" % path)
			return false
	return true


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for sub in DirAccess.get_directories_at(dir):
		if sub not in [".godot", "build", "tests", "tools", "addons"]:
			out.append_array(_scripts(dir.path_join(sub)))
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			out.append(dir.path_join(file))
	return out


func _test_save_and_load() -> void:
	print("\n== save: only what changed, beside the repo's value; read back in ==")
	_check(Tuning.save() == "", "nothing changed: nothing saved")
	Tuning.apply("items.bow.drain", 3)
	Tuning.apply("combat.moves.charge.roar", 8)
	var path := Tuning.save()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if not path.is_empty() else null
	_check(path.begins_with(Tuning.save_dir) and data is Dictionary and (data["changes"] as Dictionary).size() == 2
			and int(data["changes"]["items.bow.drain"]["value"]) == 3 and int(data["changes"]["items.bow.drain"]["repo"]) == 1
			and data["version"] == Net.version, "the two changes, each with its repo value, and the build (%s)" % path)
	var copy := Tuning.copy_to_review(path)
	_check(not copy.is_empty() and FileAccess.file_exists(copy) and copy.begins_with(Tuning.review_dir), "copied for review (%s)" % copy)
	Tuning.reset_all()
	_check(Tuning.load_file(path) == 2 and int(Items.verb_of("bow")["drain"]) == 3 and World.moves["charge"]["roar"] == 8,
			"read back in: both applied")
	Tuning.reset_all()


func _test_time() -> void:
	print("\n== slow motion, the pause and the frame step ==")
	_build(["######", "#....#", "######"])
	Tuning.plain_time()
	_check(is_equal_approx(Tuning.cycle_scale(), 0.5) and is_equal_approx(Engine.time_scale, 0.5), "F8: half speed")
	_check(is_equal_approx(Tuning.cycle_scale(), 0.25) and is_equal_approx(Engine.time_scale, 0.25), "F8 again: a quarter")
	_check(Tuning.toggle_pause() and is_equal_approx(Engine.time_scale, 0.0), "F9: paused, time held")
	var at := World.tick
	World._process(0.0)
	_check(World.tick == at, "paused: no tick")
	Tuning.step_once()
	_check(is_equal_approx(Engine.time_scale, 0.25), "\".\": time runs at the scale for the step")
	World._process(0.35)  # More than three ticks' worth arriving at once.
	_check(World.tick == at + 1 and is_equal_approx(Engine.time_scale, 0.0) and World.pause_at_tick == -1,
			"exactly one tick played, then held again (%d -> %d)" % [at, World.tick])
	World._process(0.0)
	_check(World.tick == at + 1, "and nothing more while held")
	_check(not Tuning.toggle_pause() and is_equal_approx(Engine.time_scale, 0.25), "F9 again: running, at its quarter")
	Tuning.cycle_scale()
	_check(is_equal_approx(Engine.time_scale, 1.0), "F8 round to plain time")
	Tuning.plain_time()


func _test_dummy() -> void:
	print("\n== the practice dummy: stands, never dies, full again when let be ==")
	_build(["#########", "#.......#", "#.......#", "#########"])
	var dummy := Tuning.spawn_dummy(Vector2i(4, 1))
	_check(dummy is Monster and (dummy as Monster).never_dies and (dummy as Monster).practice_still and dummy.spawned,
			"a dummy made where asked (%s)" % [dummy])
	if dummy == null:
		return
	var tile := dummy.tile
	World.damage(dummy, dummy.hp + 50)
	_check(dummy.hp == 1 and dummy.spawned, "a killing blow leaves it at 1 (%d)" % dummy.hp)
	World.tick += Tuning.DUMMY_REFILL_TICKS - 1
	(dummy as Monster)._world_tick(World.TICK_DT)
	_check(dummy.hp == 1, "struck lately: not yet full")
	World.tick += 1
	(dummy as Monster)._world_tick(World.TICK_DT)
	_check(dummy.hp == dummy.max_hp and dummy.tile == tile, "3 s let be: full again, and never moved (%d/%d)" % [dummy.hp, dummy.max_hp])
	var standing := Tuning.spawn_kind("skeleton", Vector2i(6, 2), false)
	_check(standing is Monster and (standing as Monster).practice_still and not (standing as Monster).never_dies,
			"a passive skeleton stands, and can die (%s)" % [standing])
	var fighting := Tuning.spawn_kind("imp", Vector2i(2, 2))
	_check(fighting is Monster and not (fighting as Monster).practice_still, "one that fights is a plain monster")
	_check(Tuning.spawn_kind("no_such_kind", Vector2i(3, 2)) == null, "an unknown kind: none")
	var robber := Tuning.spawn_kind("robber", Vector2i(6, 1))
	_check(robber is Monster and World.wielded(robber) == "dagger", "armed with its kind's wields, as a level's (%s)" % [World.wielded(robber) if robber != null else ""])
	Tuning.clear()
	_check(not dummy.spawned and not standing.spawned and not fighting.spawned and not robber.spawned, "clear: every one the arena made gone")


func _test_give() -> void:
	print("\n== a thing given goes where it is held or worn ==")
	_build(["######", "#....#", "######"])
	var player := EntityFactory.build(PLAYER.merged({"name": "Practiser", "tile": Vector2i(1, 1)}))
	_room.add_child(player)
	World.spawn(player, Vector2i(1, 1))
	_check(Tuning.give(player, "bow") and player.slots[Items.RIGHT_HAND] == "bow" and player.slots[Items.LEFT_HAND] == "arrows",
			"a bow in the right hand, its arrows in the left (%s)" % [player.slots])
	_check(Tuning.give(player, "sword") and player.slots[Items.RIGHT_HAND] == "sword", "a sword in place of it")
	_check(Tuning.give(player, "shield") and player.slots[Items.LEFT_HAND] == "shield", "a shield in the left")
	_check(Tuning.give(player, "mail_armour") and player.slots[Items.ARMOUR] == "mail_armour", "mail worn")
	_check(not Tuning.give(player, "no_such_thing"), "no such thing: nothing")
	player.hp = 3
	player.stamina = 0
	Tuning.full(player)
	_check(player.hp == player.max_hp and player.stamina == player.max_stamina, "full: hp and stamina")


func _test_hall_unreached() -> void:
	print("
== the practice hall: a dev level no way in the world reaches ==")
	var reached: Array[String] = []
	for name in Level.names():
		var config: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://levels/%s/level.json" % name))
		if config is Dictionary and str(config.get("links", [])).contains('"%s"' % Net.PRACTICE_MAP):
			reached.append(name)
		if config is Dictionary and str(config.get("neighbours", {})).contains('"%s"' % Net.PRACTICE_MAP):
			reached.append(name)
	_check(Net.PRACTICE_MAP in Level.names() and reached.is_empty(), "no level links to it or borders it (%s)" % [reached])
	_check(not FileAccess.get_file_as_string("res://levels/world_map.json").contains('"%s"' % Net.PRACTICE_MAP)
			and not FileAccess.get_file_as_string("res://levels/world_plane.json").contains('"%s"' % Net.PRACTICE_MAP),
			"nor the world map or plane")
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://levels/%s/level.json" % Net.PRACTICE_MAP))
	_check(config is Dictionary and (config["links"] as Array).is_empty() and (config["entities"] as Array).is_empty(),
			"and it leads nowhere, holding nothing but what the arena makes")


func _build(rows: Array[String]) -> void:
	World.reset()
	if _room != null:
		_room.free()
	_room = Node2D.new()
	add_child(_room)
	World.load_terrain(Terrain.parse(Terrain.expand(rows)))
	World.spawn_spec = func(spec: Dictionary) -> GridEntity:
		var entity := EntityFactory.build(spec)
		_room.add_child(entity)
		World.spawn(entity, spec["tile"])
		return entity


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
