extends Node
## AnimRig (decision 390): the goblin on its clips, each layer seen moving
## its bones; loops, a clip held at its end handing over to a loop without
## a frame of standing, a strike timed to its contact and fitted after it,
## the upper layer leaving the legs to the base. Run it with tests/run.ps1
## or tests/run.sh. Prints PASS/FAIL per assertion and quits with exit code
## 1 if any assertion failed, 0 otherwise.

const SCENE := "res://art/models/characters/goblin.glb"
const CLIPS := "res://art/models/animations/goblin.res"

var _failures := 0


func _ready() -> void:
	await _test_make()
	await _test_loop()
	await _test_held_hands_over()
	await _test_strike()
	await _test_one_strike_clip()
	await _test_bow_clear()
	await _test_upper()
	await _test_upper_timed()
	await _test_no_upper()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _goblin(upper := true, seed := 1) -> AnimRig:
	var scene := (load(SCENE) as PackedScene).instantiate() as Node3D
	add_child(scene)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return AnimRig.make(scene, load(CLIPS) as AnimationLibrary, 0.15, upper, rng)


static func _skeleton(rig: AnimRig) -> Skeleton3D:
	return rig.get_parent().find_children("*", "Skeleton3D", true, false)[0]


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _test_make() -> void:
	print("== make ==")
	var rig := _goblin()
	_check(rig.player != null and rig.tree != null and rig.tree.active, "a player and an active tree of its own")
	_check(rig.has("Idle") and rig.has("goblin/Idle") and not rig.has("Nonesuch"), "has() takes a clip with or without its library")
	_check(rig.length("Idle") > 0.0 and rig.clips().has("Walk"), "its clips and their lengths")
	rig.get_parent().queue_free()


func _test_loop() -> void:
	print("== loops ==")
	var one := _goblin(true, 1)
	var two := _goblin(true, 2)
	one.loop("Idle")
	two.loop("Idle")
	await _frames(3)
	_check(one.playing() == "Idle" and two.playing() == "Idle", "both stand idle")
	_check(absf(one.position() - two.position()) > 0.01, "out of step, each started where it will (%.2f, %.2f)" % [one.position(), two.position()])
	var skeleton := _skeleton(one)
	var hips := skeleton.find_bone("Hips")
	var idle_at := skeleton.get_bone_pose_position(hips)
	one.loop("Walk", 1.2)
	await _frames(30)
	_check(one.playing() == "Walk" and is_equal_approx(one.speed(), 1.2), "walking, at its speed (%s x%.2f)" % [one.playing(), one.speed()])
	_check(not skeleton.get_bone_pose_position(hips).is_equal_approx(idle_at), "the hips move to the walk")
	var at := one.position()
	await _frames(2)
	one.loop("Walk", 1.5)
	await _frames(2)
	_check(is_equal_approx(one.speed(), 1.5) and one.position() > at, "the walk again, faster: only its speed changes, it goes on (%.2f s, then %.2f s)" % [at, one.position()])
	one.get_parent().queue_free()
	two.get_parent().queue_free()


func _test_held_hands_over() -> void:
	print("== held at its end ==")
	var rig := _goblin()
	var skeleton := _skeleton(rig)
	var hips := skeleton.find_bone("Hips")
	rig.loop("Idle")
	await _frames(10)
	var standing := skeleton.get_bone_pose_position(hips).y
	var seconds := rig.once("Knockdown")
	_check(seconds > 0.0 and rig.busy() and rig.playing() == "Knockdown", "knocked down: once, busy, %.2f s" % seconds)
	await _seconds(seconds + 0.3)
	var down := skeleton.get_bone_pose_position(hips).y
	_check(not rig.busy() and down < standing * 0.6, "done, and held down at its end, not stood up again (hips %.2f, standing %.2f)" % [down, standing])
	rig.loop("Lie")
	var highest := 0.0
	for i in 20:
		await get_tree().process_frame
		highest = maxf(highest, skeleton.get_bone_pose_position(hips).y)
	_check(rig.playing() == "Lie" and highest < standing * 0.6, "lying after: never a frame of standing between (hips at most %.2f)" % highest)
	var up := rig.once("Get_Up")
	await _seconds(up + 0.3)
	_check(skeleton.get_bone_pose_position(hips).y > standing * 0.8, "and up again (hips %.2f)" % skeleton.get_bone_pose_position(hips).y)
	rig.get_parent().queue_free()


func _test_strike() -> void:
	print("== a strike ==")
	var rig := _goblin()
	rig.loop("Idle")
	await _frames(3)
	var length := rig.length("Punch_Jab")
	var seconds := rig.strike("Punch_Jab", 0.17, 0.34, 0.6)
	await _frames(2)
	_check(rig.striking() and rig.playing() == "Punch_Jab" and is_equal_approx(rig.speed(), 0.5),
		"struck so its contact (0.17 s in) lands in 0.34 s: half speed (x%.2f)" % rig.speed())
	var recover := clampf((length - 0.17) / 0.6, AnimRig.STRIKE_SPEED_MIN, AnimRig.STRIKE_SPEED_MAX)
	await _seconds(0.45)
	_check(is_equal_approx(rig.speed(), recover), "past its contact, the rest fitted to the recovery (x%.2f, wanted x%.2f)" % [rig.speed(), recover])
	_check(rig.busy(), "busy till it is done (%.2f s in all)" % seconds)
	await _seconds(seconds)
	_check(not rig.striking() and rig.playing() == "Idle", "then the idle under it again (%s)" % rig.playing())
	rig.strike("Punch_Jab", 0.17, 0.001, 10.0)
	await _frames(2)
	_check(is_equal_approx(rig.speed(), AnimRig.STRIKE_SPEED_MAX), "hurried past what reads as a blow: kept to x%.1f (x%.2f)" % [AnimRig.STRIKE_SPEED_MAX, rig.speed()])
	rig.cancel_strike()
	rig.strike("Punch_Jab", -1.0, length * AnimRig.CONTACT_DEFAULT, 1.0)
	await _frames(2)
	_check(is_equal_approx(rig.speed(), 1.0), "no contact named: halfway through the clip (x%.2f)" % rig.speed())
	rig.get_parent().queue_free()


## A body whose strikes for its weapon hold one clip (the kobold's dagger, a
## player's spear or pick): every swing that clip, no error. Client3D._pick_clip
## once left out the last clip and took a modulo of the none left (terrain,
## on the sample level: "Modulo by zero" from the second swing on).
func _test_one_strike_clip() -> void:
	print("== one strike clip ==")
	var rig := _goblin()
	rig.loop("Idle")
	var puppet := rig.get_parent() as Node3D
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	puppet.set_meta("rig", rig)
	puppet.set_meta("rng", rng)
	puppet.set_meta("moves", Client3D.HUMANOID_MOVES)
	var client := Client3D.new()  # Never in the tree: _strike reads only the puppet.
	var played: Array[String] = []
	for i in 3:
		rig.cancel_strike()
		client._strike(puppet, null, "dagger")
		await _frames(2)
		played.append(rig.playing())
	_check(played == ["Dagger_Stab", "Dagger_Stab", "Dagger_Stab"], "a dagger's one stab, swing after swing (%s)" % [played])
	var bare: Array[String] = []
	for i in 4:
		rig.cancel_strike()
		client._strike(puppet, null, "")
		await _frames(2)
		bare.append(rig.playing())
	_check(range(1, bare.size()).all(func(i: int) -> bool: return bare[i] != bare[i - 1]),
		"two clips: never the same twice running (%s)" % [bare])
	client.free()
	puppet.queue_free()


## The bow clear of the body (Jeff: "arm and bow clipping body"): on five builds (the man as
## built, heavy, broad, lean; the woman), the bow in the left hand and the bundle in the right as
## Client3D sockets them, in the held pose walking and standing, at the nock, at full draw and at
## the release, no vertex of the bow nor of the left forearm inside the trunk (each against the
## nearest trunk vertex's normal, the body baked as posed).
func _test_bow_clear() -> void:
	print("== the bow clear of the body ==")
	var lib := load(CLIPS) as AnimationLibrary
	var builds := [["man", "res://art/models/characters/human_m.glb", {}],
		["man heavy", "res://art/models/characters/human_m.glb", {"heavy": 1.0}],
		["man broad", "res://art/models/characters/human_m.glb", {"heavy": 0.6, "broad": 1.0}],
		["man lean", "res://art/models/characters/human_m.glb", {"lean": 1.0, "narrow": 1.0}],
		["woman", "res://art/models/characters/human_f.glb", {}]]
	var poses := [["walk", "Walk", "Bow_Idle", 0.3], ["stand", "Idle", "Bow_Idle", 0.3], ["nock", "Idle", "Bow_Draw", 0.3],
		["full", "Idle", "Bow_Draw", 1.0], ["release", "Idle", "Bow_Loose", 0.09]]
	var found: Array[String] = []
	for build: Array in builds:
		for pose: Array in poses:
			var model := (load(build[1]) as PackedScene).instantiate() as Node3D
			add_child(model)
			for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
				for key: String in build[2]:
					var i := mesh.find_blend_shape_by_name(key)
					if i >= 0:
						mesh.set_blend_shape_value(i, build[2][key])
			var holder := Node3D.new()
			Client3D._attach_sockets(model, Client3D.HUMAN_SOCKETS, 1.0, holder)
			var bow := ArtKit.instance("item.bow")
			(holder.get_meta("sockets")["hand_l"] as Node3D).add_child(bow)
			var rng := RandomNumberGenerator.new()
			rng.seed = 1
			var rig := AnimRig.make(model, lib, 0.0, true, rng)
			rig.loop(pose[1])
			for i in 3:
				rig.upper_at(pose[2], float(pose[3]) * rig.length(pose[2]))
				await get_tree().process_frame
			var counts := _bow_inside(model, bow)
			if counts.x > 0 or counts.y > 0:
				found.append("%s %s: bow %d, forearm %d" % [build[0], pose[0], counts.x, counts.y])
			model.queue_free()
			holder.free()
	_check(found.is_empty(), "no bow or forearm inside the trunk, five builds, held, nock, full draw, release (%s)" % ", ".join(found))


const TRUNK_BONES := ["Hips", "Spine", "Chest", "UpperChest", "Neck"]


## Bow and left-forearm vertices inside [param model]'s trunk, as (bow, forearm).
static func _bow_inside(model: Node3D, bow: Node3D) -> Vector2i:
	# Skinned here, not baked (a headless run registers no skin): each vertex, its shape keys
	# added, by its bones' poses over their binds.
	var body := model.find_child("Body", true, false) as MeshInstance3D
	var skeleton := body.get_parent() as Skeleton3D
	var shaped := body.mesh as ArrayMesh
	var src := shaped.surface_get_arrays(0)
	var verts: PackedVector3Array = (src[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	var normals: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
	var shapes := shaped.surface_get_blend_shape_arrays(0)
	for k in shapes.size():
		var weight := body.get_blend_shape_value(k)
		if weight == 0.0:
			continue
		var shape: PackedVector3Array = shapes[k][Mesh.ARRAY_VERTEX]
		for i in verts.size():
			var delta := shape[i] - (src[Mesh.ARRAY_VERTEX] as PackedVector3Array)[i] if shaped.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED else shape[i]
			verts[i] += delta * weight
	var bones: PackedInt32Array = src[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = src[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / verts.size()
	var skin := body.skin
	var poses: Array[Transform3D] = []
	for b in skin.get_bind_count():
		var bone_index := skin.get_bind_bone(b) if skin.get_bind_name(b) == &"" else skeleton.find_bone(skin.get_bind_name(b))
		poses.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone_index) * skin.get_bind_pose(b))
	var trunk := PackedVector3Array()
	var trunk_n := PackedVector3Array()
	var forearm := PackedVector3Array()
	for i in verts.size():
		var p := Vector3.ZERO
		var n := Vector3.ZERO
		var best := 0
		for k in per:
			var w := weights[i * per + k]
			if w <= 0.0:
				continue
			var pose := poses[bones[i * per + k]]
			p += pose * verts[i] * w
			n += pose.basis * normals[i] * w
			if w > weights[i * per + best]:
				best = k
		var b := bones[i * per + best]
		var bone := String(skin.get_bind_name(b)) if skin.get_bind_name(b) != &"" else skeleton.get_bone_name(skin.get_bind_bone(b))
		if bone in TRUNK_BONES:
			trunk.append(p)
			trunk_n.append(n.normalized())
		elif bone == "LeftLowerArm":
			forearm.append(p)
	var points := PackedVector3Array()
	for mesh: MeshInstance3D in bow.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			for v: Vector3 in mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				points.append(mesh.global_transform * v)
	return Vector2i(_inside(points, trunk, trunk_n), _inside(forearm, trunk, trunk_n))


static func _inside(points: PackedVector3Array, surface: PackedVector3Array, normals: PackedVector3Array) -> int:
	var n := 0
	for p in points:
		var best := INF
		var at := -1
		for j in surface.size():
			var d := p.distance_squared_to(surface[j])
			if d < best:
				best = d
				at = j
		if at >= 0 and best < 0.0225 and (p - surface[at]).dot(normals[at]) < -0.004:
			n += 1
	return n

func _test_upper() -> void:
	print("== the upper layer ==")
	var rig := _goblin()
	var skeleton := _skeleton(rig)
	var leg := skeleton.find_bone("LeftUpperLeg")
	var arm := skeleton.find_bone("RightUpperArm")
	rig.loop("Walk", 1.0, -1.0, true)
	var bare := _goblin()
	bare.loop("Walk", 1.0, -1.0, true)
	rig.upper("Block_Idle")
	await _frames(20)
	var bare_skeleton := _skeleton(bare)
	_check(skeleton.get_bone_pose_rotation(leg).is_equal_approx(bare_skeleton.get_bone_pose_rotation(leg)),
		"guarding as it walks: the legs walk as a body's that does not")
	_check(not skeleton.get_bone_pose_rotation(arm).is_equal_approx(bare_skeleton.get_bone_pose_rotation(arm)), "and the arms guard")
	rig.upper_off()
	await _frames(5)
	_check(skeleton.get_bone_pose_rotation(arm).is_equal_approx(bare_skeleton.get_bone_pose_rotation(arm)), "let go: the arms walk again")
	rig.posture(null, 1.0)
	_check(is_zero_approx(float(rig.tree.get("parameters/posture/add_amount"))), "no posture: nothing added")
	rig.get_parent().queue_free()
	bare.get_parent().queue_free()


func _test_upper_timed() -> void:
	print("== the upper layer timed (decision 462: a bow's draw kept to the sim's) ==")
	var rig := _goblin()
	rig.loop("Idle")
	rig.upper("Bow_Draw", 2.0, true)
	rig.tree.advance(0.25)
	_check(absf(rig.upper_position() - 0.5) < 0.02 and is_equal_approx(rig.upper_speed(), 2.0),
		"Bow_Draw at speed 2: half a second in after a quarter (%.3f)" % rig.upper_position())
	rig.upper("Bow_Draw", 2.0)
	rig.tree.advance(0.1)
	_check(absf(rig.upper_position() - 0.7) < 0.02, "asked again without from_start: it goes on (%.3f)" % rig.upper_position())
	rig.upper("Bow_Draw", 2.0, true)
	_check(rig.upper_position() < 0.02, "from_start: back at the nock (%.3f)" % rig.upper_position())
	rig.upper("Bow_Draw", 0.5)
	rig.tree.advance(0.2)
	_check(absf(rig.upper_position() - 0.1) < 0.02, "a new speed, the same clip: slower, not restarted (%.3f)" % rig.upper_position())
	rig.upper_at("Bow_Draw", 0.6)
	_check(absf(rig.upper_position() - 0.6) < 0.02 and rig.upper_speed() == 0.0, "upper_at: held at 0.6 s (%.3f)" % rig.upper_position())
	rig.tree.advance(0.3)
	_check(absf(rig.upper_position() - 0.6) < 0.02, "and stays there as time goes on (%.3f)" % rig.upper_position())
	rig.upper_at("Bow_Draw", 0.2)
	_check(absf(rig.upper_position() - 0.2) < 0.02, "scrubbed back too (%.3f)" % rig.upper_position())
	rig.get_parent().queue_free()


func _test_no_upper() -> void:
	print("== no upper layer (a quadruped) ==")
	var rig := _goblin(false)
	rig.loop("Idle")
	rig.upper("Block_Idle")
	await _frames(3)
	_check(not (rig.tree.tree_root as AnimationNodeBlendTree).has_node("upper") and rig.playing() == "Idle",
		"made without it: no such node, and upper() does nothing")
	rig.get_parent().queue_free()
