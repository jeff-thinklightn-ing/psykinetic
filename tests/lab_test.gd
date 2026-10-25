extends Node
## The Character Lab (decision 674): each of its builds made as the game
## makes a person, holding and wearing what its pickers say; its clips
## listed gaits first; paused, scrubbed and stepped; the treadmill's floor
## running at the clip's gait pace. Headless: the lab opens no window of its
## own. Prints PASS/FAIL per assertion and quits with exit code 1 if any
## assertion failed, 0 otherwise.

var _failures := 0
var _lab: CharacterLab
## The drop folder and the import folder of its own (674 step 2): never Jeff's,
## never the lab's build/lab.
var DROP: String = preload("res://tests/test_ports.gd").scratch("lab_drop")
const OUT := "res://build/lab_test"


func _ready() -> void:
	_clear(DROP)
	_clear(OUT)
	_lab = (load("res://client3d/character_lab.tscn") as PackedScene).instantiate() as CharacterLab
	_lab.drop.drop = DROP
	_lab.drop.out = OUT
	add_child(_lab)
	await get_tree().process_frame
	await _test_builds()
	await _test_held_and_worn()
	_test_clips()
	await _test_pause()
	await _test_treadmill()
	await _test_compare()
	_test_feet()
	_test_drop()
	_clear(DROP)
	_clear(OUT)
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


## Compared (674 step 3): B made beside A, its own build, tagged; the clip,
## pause and scrub both's; Compare off, B gone.
func _test_compare() -> void:
	print("== two bodies compared ==")
	_lab.compare = true
	_lab.body_b = 4
	_lab.make_body()
	await get_tree().process_frame
	var two := _lab.get_children().filter(func(n: Node) -> bool: return n.name in ["Person", "PersonB"] and not n.is_queued_for_deletion())
	_check(two.size() == 2 and _lab.rig_b != null and _lab.look_b.body == &"female" and _lab.look.body == &"male",
		"B beside A: A the man, B the woman (%d bodies)" % two.size())
	_check(is_equal_approx(_lab.puppet.position.z, -CharacterLab.SPACING * 0.5) and is_equal_approx(_lab.puppet_b.position.z, CharacterLab.SPACING * 0.5),
		"side by side, %.1f m apart across their way" % CharacterLab.SPACING)
	var tag := _lab.puppet_b.get_node_or_null("Tag") as Label3D
	_check(tag != null and tag.text == "B: game, woman", "B tagged over its head (%s)" % (tag.text if tag != null else "none"))
	_lab.clip = "Jog_Short"
	_lab.paused = false
	_lab.play()
	_check(_lab.rig.base_clip() == "Jog_Short" and _lab.rig_b.base_clip() == "Jog_Short", "both play the clip")
	_lab.scrub(0.4)
	_lab.rig.tree.advance(0.1)
	_lab.rig_b.tree.advance(0.1)
	_check(absf(_lab.rig.position() - 0.4) < 0.01 and absf(_lab.rig_b.position() - 0.4) < 0.01,
		"scrubbed together (%.3f, %.3f)" % [_lab.rig.position(), _lab.rig_b.position()])
	_lab.set_paused(false)
	_check(_lab.readout(1)[0] != "", "B has a readout line")
	_lab.compare = false
	_lab.make_body()
	await get_tree().process_frame
	_check(_lab.puppet_b == null and _lab.feet[1] == null and is_zero_approx(_lab.puppet.position.z), "Compare off: B gone, A back in the middle")


## The feet measured (674 step 3), stepped by hand a 1/120 s at a time over
## two loops: the man's jog at its table's pace slides under LabFeet's red
## line, its measured pace within 5% of the table's; the planted toe marked;
## "Use measured" sets his jog's pace for this run, read by the treadmill.
func _test_feet() -> void:
	print("== the feet measured ==")
	_lab.body = 0
	_lab.clip = "Jog_Short"
	_lab.set_speed(1.0)
	_lab.paused = false
	_lab.play()
	var step := 1.0 / 120.0
	var marks := _lab._marks.size()
	for i in int(2.0 * _lab.rig.length("Jog_Short") / step):
		_lab.rig.tree.advance(step)
		_lab.sample_feet(step)
	var measured: Dictionary = _lab.feet[0].measure(_lab.pace())
	var table := _lab.pace()
	_check(not measured.is_empty() and absf(float(measured["pace"]) - table) < 0.05 * table,
		"measured pace %.2f m/s, the table's %.2f" % [float(measured.get("pace", 0.0)), table])
	_check(not measured.is_empty() and not _lab.LabFeet.red(measured, table),
		"slide %.3f m/s at the table's pace (under %d%%)" % [float(measured.get("slide", 0.0)), roundi(100 * _lab.LabFeet.SLIDE_RED)])
	_check(str(_lab.readout(0)[0]).begins_with("A: measured pace"), "the readout line (%s)" % _lab.readout(0)[0])
	_check(_lab._marks.size() > marks, "the planted toe marked on the floor (%d marks)" % (_lab._marks.size() - marks))
	var set_to := _lab.use_measured(0)
	_check(set_to > 0.0 and is_equal_approx(ArtKit.feel("client3d.gait.Jog_Short", 0.0), set_to)
		and absf(_lab.pace() - set_to * _lab.look.scale) < 0.01, "Use measured: his jog's pace %.2f for this run, the treadmill at it" % set_to)
	ArtKit.set_feel("client3d.gait.Jog_Short", null)
	_check(is_equal_approx(ArtKit.feel("client3d.gait.Jog_Short", 0.0), 3.63), "put back: the file's")
	_lab.clip = "Idle"
	_check(_lab.use_measured(0) == 0.0, "an idle: nothing to set")
	_lab._age_marks(CharacterLab.MARK_LIFE + 0.1, 0.0)
	_check(_lab._marks.is_empty(), "the marks gone after their life")


## Jeff's exports (674 step 2), through the lab's own LabDrop with a stand-in
## import and load: a file taken once settled; a body shown in the game's
## place; a bad one (no Body, the wrong bones, the scale, not a glTF) keeping
## the last good and saying why; an .fbx named; a gate stop tried again; clips
## laid over the game's and marked "(yours)"; nothing written outside its folder.
func _test_drop() -> void:
	print("== the drop folder: Jeff's exports ==")
	var drop = _lab.drop
	var imports := [0]
	var stop := [false]
	drop.importer = func(done: Callable) -> void:
		imports[0] += 1
		done.call(not stop[0], "heavy_job: stopped after 10 min" if stop[0] else "")
	var stand_in := {}
	drop.loader = func(path: String, _keep: bool) -> Resource: return stand_in.get(path.get_file())
	var body_at := DROP.path_join("human_m.glb")
	stand_in["human_m.glb"] = load(Client3D.HUMAN["scene"])
	_write(body_at, "one")
	var t := 100000
	drop.poll(t)
	drop.poll(t + 1000)
	_check(imports[0] == 0, "a file still being written (still under 2 s) not taken")
	drop.poll(t + 2100)
	var copy: String = OUT.path_join("human_m.glb")
	var settings := FileAccess.get_file_as_string(copy + ".import")
	_check(imports[0] == 1 and FileAccess.file_exists(copy) and "animation/import=false" in settings and "ual.tres" in settings,
		"settled: copied with the body's import (the UAL bone map), imported once")
	_check(drop.bodies.get("male") == Client3D.HUMAN["scene"] and not drop.bad and str(drop.status).begins_with("loaded"),
		"loaded (%s)" % drop.status)
	_lab.body = 0
	_lab._drop_at = 0
	_lab._process(0.0)
	_check(_lab.drop_line.text == drop.status and _lab.puppet != null, "the status line under the panel, the body made again")
	drop.poll(t + 6000)
	_check(imports[0] == 1, "unchanged: not imported again")
	var bad_cases := [[_scene(BONES_OK, false, 0.0), "no mesh named Body", "no Body"],
		[_scene(["pelvis", "spine_01"], true, 1.75), "Hips", "the UAL names lost"],
		[_scene(BONES_OK, true, 17.5), "17.50 m", "the scale not applied"],
		[null, "import failed", "not a glTF"]]
	for each: Array in bad_cases:
		stand_in["human_m.glb"] = each[0]
		_write(body_at, each[2])
		t += 10000
		drop.poll(t)
		drop.poll(t + 2100)
		_check(drop.bad and str(each[1]) in drop.status and drop.bodies.get("male") == Client3D.HUMAN["scene"] and not FileAccess.file_exists(copy),
			"%s: said, the last good kept, the copy gone (%s)" % [each[2], drop.status])
	_write(DROP.path_join("clips/walk.fbx"), "x")
	drop.poll(t + 5000)
	_check(drop.bad and "clips/walk.fbx" in drop.status and ".glb" in drop.status, "an .fbx named: export as .glb (%s)" % drop.status)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DROP.path_join("clips/walk.fbx")))
	stand_in["run.glb"] = _scene(BONES_OK, false, 0.0, "My_Run")
	_write(DROP.path_join("clips/run.glb"), "run")
	stop[0] = true
	t += 10000
	drop.poll(t)
	drop.poll(t + 2100)
	_check(drop.bad and "busy" in drop.status, "the gate stopped the import: said (%s)" % drop.status)
	stop[0] = false
	drop.poll(t + 3000)
	drop.poll(t + 5200)
	var library := ResourceLoader.load(drop.clips_path(), "", ResourceLoader.CACHE_MODE_IGNORE) as AnimationLibrary if ResourceLoader.exists(drop.clips_path()) else null
	_check(imports[0] == 7 and "My_Run" in drop.clip_names and library != null and library.has_animation("My_Run") and library.has_animation("Idle"),
		"tried again: the clip laid over the game's (%d imports, %s)" % [imports[0], drop.status])
	_lab._drop_at = 0
	_lab._process(0.0)
	var shown: Array[String] = []
	var picker := _lab._ui["clip"] as OptionButton
	for i in picker.item_count:
		shown.append(picker.get_item_text(i))
	_check("My_Run (yours)" in shown and _lab.rig.has("My_Run"), "the lab's body has it, marked (yours) in the picker")
	_check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://build/lab")) or OUT != "res://build/lab",
		"written only to its own folder, never build/lab")


const BONES_OK := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftUpperArm", "LeftLowerArm",
	"LeftHand", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"RightUpperLeg", "RightLowerLeg", "RightFoot"]


## A stand-in import: a skeleton with [param bones], a Body [param tall] high
## if [param body], an animation named [param clip] on the skeleton.
static func _scene(bones: Array, body: bool, tall: float, clip := "") -> PackedScene:
	var root := Node3D.new()
	var skeleton := Skeleton3D.new()
	skeleton.name = "GeneralSkeleton"
	root.add_child(skeleton)
	skeleton.owner = root
	for bone: String in bones:
		skeleton.add_bone(bone)
	if body:
		var mesh := MeshInstance3D.new()
		mesh.name = "Body"
		var box := BoxMesh.new()
		box.size = Vector3(0.5, tall, 0.3)
		mesh.mesh = box
		skeleton.add_child(mesh)
		mesh.owner = root
	if clip != "":
		var player := AnimationPlayer.new()
		root.add_child(player)
		player.owner = root
		var animation := Animation.new()
		var track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, "%GeneralSkeleton:Hips")
		animation.rotation_track_insert_key(track, 0.0, Quaternion.IDENTITY)
		var library := AnimationLibrary.new()
		library.add_animation(clip, animation)
		player.add_animation_library("", library)
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed


static func _write(path: String, words: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(words)
	file.close()


static func _clear(folder: String) -> void:
	var at := ProjectSettings.globalize_path(folder)
	if not DirAccess.dir_exists_absolute(at):
		return
	for sub in DirAccess.get_directories_at(at):
		_clear(folder.path_join(sub))
	for file in DirAccess.get_files_at(at):
		DirAccess.remove_absolute(at.path_join(file))
	DirAccess.remove_absolute(at)
