extends Node
## The Character Lab (decision 674): each of its builds made as the game
## makes a person, holding and wearing what its pickers say; its clips
## listed gaits first; paused, scrubbed and stepped; the treadmill's floor
## running at the clip's gait pace. Headless: the lab opens no window of its
## own. Prints PASS/FAIL per assertion and quits with exit code 1 if any
## assertion failed, 0 otherwise.

var _failures := 0
var _lab: CharacterLab


func _ready() -> void:
	_lab = (load("res://client3d/character_lab.tscn") as PackedScene).instantiate() as CharacterLab
	add_child(_lab)
	await get_tree().process_frame
	await _test_builds()
	await _test_held_and_worn()
	_test_clips()
	await _test_pause()
	await _test_treadmill()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


static func _body_mesh(puppet: Node3D) -> MeshInstance3D:
	for mesh: MeshInstance3D in puppet.find_children("Body", "MeshInstance3D", true, false):
		return mesh
	return null


func _test_builds() -> void:
	print("== each build made as the game makes a person ==")
	for i in CharacterLab.BUILDS.size():
		var build: Array = CharacterLab.BUILDS[i]
		_lab.body = i
		_lab.make_body()
		await get_tree().process_frame
		var puppet := _lab.puppet
		_check(_lab.rig != null and puppet.has_meta("sockets"), "%s: a rig and sockets" % build[0])
		_check(_lab.look.body == StringName(build[1]), "%s: the %s body" % [build[0], build[1]])
		var mesh := _body_mesh(puppet)
		var keyed := mesh != null
		for key: String in build[2]:
			var index := mesh.find_blend_shape_by_name(key) if mesh != null else -1
			keyed = keyed and index >= 0 and is_equal_approx(mesh.get_blend_shape_value(index), float(build[2][key]))
		_check(keyed, "%s: its shape keys set (%s)" % [build[0], build[2]])
		_check(get_children().size() == 1 and _lab.get_children().filter(func(n: Node) -> bool: return n.name == "Person").size() == 1,
			"%s: one body in the lab" % build[0])
	_lab.body = 0


func _test_held_and_worn() -> void:
	print("== held and worn as the game draws them ==")
	var weapons := CharacterLab.items_tagged(["weapon"] as Array[String])
	var shields := CharacterLab.items_tagged(["shield"] as Array[String])
	var worn := CharacterLab.items_worn()
	_check(not weapons.is_empty() and not shields.is_empty() and not worn.is_empty(), "the pickers list weapons, shields and armour")
	if weapons.is_empty() or shields.is_empty() or worn.is_empty():
		return
	_lab.held = [weapons[0], shields[0]] as Array[String]
	_lab.worn = worn[0]
	_lab.make_body()
	await get_tree().process_frame
	var sockets: Dictionary = _lab.puppet.get_meta("sockets")
	_check((sockets["hand_r"] as Node3D).get_node_or_null("Held") != null, "%s in the right hand" % weapons[0])
	_check((sockets["arm_l"] as Node3D).get_node_or_null("Held") != null, "%s strapped on the left forearm" % shields[0])
	var armour := str(PersonLook.ARMOUR_PARTS.get(str(Items.armour_of(worn[0]).get("look", "")), ""))
	var part := _lab.puppet.find_child(armour, true, false) as Node3D if armour != "" else null
	_check(part != null and part.visible, "%s worn (%s shown)" % [worn[0], armour])
	_lab.held = ["", ""] as Array[String]
	_lab.worn = ""
	_lab.make_body()
	await get_tree().process_frame
	sockets = _lab.puppet.get_meta("sockets")
	_check((sockets["hand_r"] as Node3D).get_node_or_null("Held") == null, "emptied: nothing in the hand")


func _test_clips() -> void:
	print("== the clips, gaits first ==")
	var listed := _lab.clips()
	_check(listed.size() > 20 and listed[0] == Client3D.CLIP_WALK and listed[1] == "Jog_Short", "gaits first, then the rest (%d)" % listed.size())
	_check("Haft_Rest" in listed and "Bow_Idle" in listed, "the rests and the bow listed")
	_check((_lab._ui["clip"] as OptionButton).item_count == listed.size(), "the clip picker filled")


func _test_pause() -> void:
	print("== paused, scrubbed, stepped ==")
	_lab.clip = "Jog_Short"
	_lab.paused = false
	_lab.play()
	_lab.scrub(0.3)
	_lab.rig.tree.advance(0.2)
	_check(_lab.paused and absf(_lab.rig.position() - 0.3) < 0.01, "scrubbed to 0.3 s and held (%.3f)" % _lab.rig.position())
	_lab.step()
	_lab.rig.tree.advance(0.1)
	_check(absf(_lab.rig.position() - (0.3 + CharacterLab.FRAME)) < 0.01, "a step on is a frame on (%.3f)" % _lab.rig.position())
	_lab.set_paused(false)
	_lab.rig.tree.advance(0.2)
	_check(absf(_lab.rig.position() - (0.3 + CharacterLab.FRAME + 0.2)) < 0.02, "resumed from there (%.3f)" % _lab.rig.position())


func _test_treadmill() -> void:
	print("== the treadmill at the gait's pace ==")
	_lab.clip = "Jog_Short"
	_lab.set_speed(1.0)
	var jog := 0.0
	for gait: Array in Client3D.HUMAN_GAITS:
		if gait[0] == "Jog_Short":
			jog = float(gait[1])
	var rate := ArtKit.feel("client3d.gait_rate", Client3D.GAIT_RATE)
	_check(is_equal_approx(_lab.pace(), jog * _lab.look.scale / rate), "the jog's pace, %.2f m/s" % _lab.pace())
	_lab.clip = "Idle"
	_check(is_zero_approx(_lab.pace()), "an idle stands still")
	_lab.clip = "Jog_Short"
	_lab.treadmill = true
	_lab.run = 0.0
	_lab._process(0.5)
	_check(absf(_lab.run - _lab.pace() * 0.5) < 0.001, "half a second runs the floor %.2f m" % _lab.run)
	_check(not is_zero_approx(_lab.floor_material.uv1_offset.x), "the floor's grid moved")
	_lab.treadmill = false
	_lab._process(0.1)
	_check(_lab.floor_material.uv1_offset == Vector3.ZERO, "off: the floor stands")
	await get_tree().process_frame
