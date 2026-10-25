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
	await _test_bow_back()
	await _test_work_clear()
	await _test_armed_fidgets()
	await _test_rests()
	_test_warm_painted()
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


## The bow clear of the body (Jeff: "arm and bow clipping body"; on v0.1.160: "the bow draw back
## arm is all wrong, it clips through the body then is held as if the arm is behind wrapping
## behind the head"): on five builds (the man as built, heavy, broad, lean; the woman), the bow in
## the left hand as Client3D sockets it, carried walking, jogging and sprinting with no upper layer
## (462 amended (3): the arm swinging with the gait, at four places along each, the bow turned
## as Client3D.BOW_CARRY turns it; the bow alone checked there, the arms being the gait's), standing, lifted, at the nock, raised,
## pulled, at full draw, at the release and coming down, no vertex of the bow inside the trunk or
## the left leg, of the left forearm inside the trunk, nor of the right forearm or hand inside the
## trunk or the head (each against the nearest such vertex's normal, the body skinned as posed);
## and at full draw the string hand at the jaw: the wrist beside the head, not behind it.
func _test_bow_clear() -> void:
	print("== the bow clear of the body ==")
	var lib := load(CLIPS) as AnimationLibrary
	var builds := [["man", "res://art/models/characters/human_m.glb", {}],
		["man heavy", "res://art/models/characters/human_m.glb", {"heavy": 1.0}],
		["man broad", "res://art/models/characters/human_m.glb", {"heavy": 0.6, "broad": 1.0}],
		["man lean", "res://art/models/characters/human_m.glb", {"lean": 1.0, "narrow": 1.0}],
		["woman", "res://art/models/characters/human_f.glb", {}]]
	# A carry's last field is the seed of where along its gait the loop starts.
	var poses := [["walk", Client3D.HUMAN_GAITS[0][0], "", 1], ["walk", Client3D.HUMAN_GAITS[0][0], "", 2], ["walk", Client3D.HUMAN_GAITS[0][0], "", 3],
		["walk", Client3D.HUMAN_GAITS[0][0], "", 4], ["jog", JOG, "", 1], ["jog", JOG, "", 2],
		["jog", JOG, "", 3], ["jog", JOG, "", 4], ["sprint", SPRINT, "", 1],
		["sprint", SPRINT, "", 2], ["sprint", SPRINT, "", 3], ["sprint", SPRINT, "", 4],
		["stand", "Idle", "Bow_Idle", 0.0], ["lift", "Idle", "Bow_Draw", 0.15],
		["nock", "Idle", "Bow_Draw", 0.3], ["raise", "Idle", "Bow_Draw", 0.42], ["raised", "Idle", "Bow_Draw", 0.5],
		["pull", "Idle", "Bow_Draw", 0.68], ["full", "Idle", "Bow_Draw", 1.0], ["release", "Idle", "Bow_Loose", 0.09],
		["down", "Idle", "Bow_Loose", 0.8]]
	var found: Array[String] = []
	var anchors: Array[String] = []
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
			if pose[2] == "":
				bow.transform = Client3D.BOW_CARRY
			var rng := RandomNumberGenerator.new()
			rng.seed = int(pose[3]) if pose[2] == "" else 1
			var rig := AnimRig.make(model, lib, 0.0, true, rng)
			rig.loop(pose[1], 0.0)
			for i in 3:
				if pose[2] != "":
					rig.upper_at(pose[2], float(pose[3]) * rig.length(pose[2]))
				await get_tree().process_frame
			var counts := _bow_inside(model, bow)
			if pose[2] == "":
				# Carried, the arms are the gait's own (the clip's, not the bow's): the bow alone.
				counts = Vector3i(counts.x, 0, 0)
			if counts != Vector3i.ZERO:
				found.append("%s %s%s: bow %d, left forearm %d, right arm %d" % [build[0], pose[0],
					" %.2f" % rig.position() if pose[2] == "" else "", counts.x, counts.y, counts.z])
			if pose[0] == "full":
				var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
				var head := skeleton.get_bone_global_pose(skeleton.find_bone("Head")).origin
				var wrist := skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")).origin
				# Skeleton space: the body faces +z; behind the head is -z.
				if wrist.distance_to(head) > 0.2 or wrist.z - head.z < -0.04:
					anchors.append("%s: wrist %.2f from the head, %.2f ahead of it" % [build[0], wrist.distance_to(head), wrist.z - head.z])
			model.queue_free()
			holder.free()
	_check(found.is_empty(), "no bow nor arm inside the body, five builds, carried, nocked, drawn, released (%s)" % ", ".join(found))
	_check(anchors.is_empty(), "at full draw the string hand at the jaw, not behind the head (%s)" % ", ".join(anchors))


## The bow on the back (662 amended (d)), each face: clear of the body through
## the gaits and standing, five builds, and through none of the quiver's box
## laid over it.
func _test_bow_back() -> void:
	print("== the bow on the back: clear of the body and the quiver ==")
	var lib := load(CLIPS) as AnimationLibrary
	var builds := [["man", "res://art/models/characters/human_m.glb", {}],
		["man heavy", "res://art/models/characters/human_m.glb", {"heavy": 1.0}],
		["man broad", "res://art/models/characters/human_m.glb", {"heavy": 0.6, "broad": 1.0}],
		["man lean", "res://art/models/characters/human_m.glb", {"lean": 1.0, "narrow": 1.0}],
		["woman", "res://art/models/characters/human_f.glb", {}]]
	var poses := [["stand", "Idle", 1], ["walk", Client3D.HUMAN_GAITS[0][0], 1], ["walk", Client3D.HUMAN_GAITS[0][0], 2],
		["jog", JOG, 1], ["jog", JOG, 2], ["sprint", SPRINT, 1], ["sprint", SPRINT, 2]]
	var found: Array[String] = []
	var crossed: Array[String] = []
	var face_was := Client3D.bow_back_face
	for face: String in Client3D.BOW_BACK:
		Client3D.bow_back_face = face
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
				var sockets: Dictionary = holder.get_meta("sockets")
				var bow := ArtKit.instance("item.bow")
				bow.name = "Held"
				(sockets["hand_l"] as Node3D).add_child(bow)
				var quiver := ArtKit.instance(Client3D.QUIVER, 1)
				quiver.name = "Quiver"
				(sockets["back"] as Node3D).add_child(quiver)
				Client3D._stow_bow(sockets, true)
				var rng := RandomNumberGenerator.new()
				rng.seed = int(pose[2])
				var rig := AnimRig.make(model, lib, 0.0, true, rng)
				rig.loop(pose[1], 0.0)
				for i in 3:
					await get_tree().process_frame
				var parts := _skinned_parts(model)
				var trunk: Array = parts["trunk"]
				var points := _points(bow) + _points(quiver)
				var inside := _inside(points, trunk[0] + parts["head"][0], trunk[1] + parts["head"][1])
				if inside > 0 or bow.get_parent() != sockets["back"]:
					var of_bow := _inside(_points(bow), trunk[0] + parts["head"][0], trunk[1] + parts["head"][1])
					found.append("%s %s %s: bow %d, quiver %d" % [face, build[0], pose[0], of_bow, inside - of_bow])
				if build[0] == "man" and pose[0] == "stand":
					# In the back socket's frame: no point of the bow in the quiver's box.
					var back := (sockets["back"] as Node3D).global_transform.affine_inverse()
					var box := _box(back * _points(quiver)).grow(-0.005)
					var through := 0
					for p in back * _points(bow):
						if box.has_point(p):
							through += 1
					if through > 0:
						crossed.append("%s %d" % [face, through])
				model.queue_free()
				holder.queue_free()
	Client3D.bow_back_face = face_was
	_check(found.is_empty(), "the bow and quiver on the back clear of the body, both faces, five builds, the gaits (%s)" % ", ".join(found))
	_check(crossed.is_empty(), "the bow through none of the quiver laid over it (%s)" % ", ".join(crossed))


static func _points(piece: Node3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	for mesh: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			for v: Vector3 in mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				points.append(mesh.global_transform * v)
	return points


## The work's clips (566) with the tool in the right hand as Client3D sockets it: at moments along
## each loop, on the five builds, no vertex of the tool inside the trunk or the left leg, of the
## left forearm inside the trunk, nor of the right forearm or hand inside the trunk or the head.
func _test_work_clear() -> void:
	print("== the work's tools clear of the body ==")
	var lib := load(CLIPS) as AnimationLibrary
	var builds := [["man", "res://art/models/characters/human_m.glb", {}],
		["man heavy", "res://art/models/characters/human_m.glb", {"heavy": 1.0}],
		["man broad", "res://art/models/characters/human_m.glb", {"heavy": 0.6, "broad": 1.0}],
		["man lean", "res://art/models/characters/human_m.glb", {"lean": 1.0, "narrow": 1.0}],
		["woman", "res://art/models/characters/human_f.glb", {}]]
	var moments := [["Chop", "chop", [0.0, 0.3, 0.45, 0.55, 0.62, 0.8, 1.3]], ["Saw", "saw", [0.0, 0.2, 0.4, 0.6]],
		["Hammer", "hammer", [0.0, 0.22, 0.5]]]
	if ArtKit.has("tool.hoe"):  # Art-kit's (566 amended), once its slot is in.
		moments.append(["Hoe", "hoe", [0.0, 0.25, 0.45, 0.7, 1.0]])
	var lowest := 9.0  # The hoe's blade, its lowest through the stroke (metres above the feet).
	var found: Array[String] = []
	var off_haft: Array[String] = []
	for build: Array in builds:
		for moment: Array in moments:
			for at: float in moment[2]:
				var model := (load(build[1]) as PackedScene).instantiate() as Node3D
				add_child(model)
				for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
					for key: String in build[2]:
						var i := mesh.find_blend_shape_by_name(key)
						if i >= 0:
							mesh.set_blend_shape_value(i, build[2][key])
				var holder := Node3D.new()
				Client3D._attach_sockets(model, Client3D.HUMAN_SOCKETS, 1.0, holder)
				var work: Dictionary = Client3D.ACTIVITIES[moment[1]]
				var tool := ArtKit.instance(work["right"])
				Client3D._grip(tool, work)
				(holder.get_meta("sockets")["hand_r"] as Node3D).add_child(tool)
				var rig := AnimRig.make(model, lib, 0.0, true, null)
				rig.loop(moment[0], 0.0, 0.0, true)
				for i in 3:
					rig.upper_at(moment[0], at)
					await get_tree().process_frame
				if moment[1] == "hoe":
					lowest = minf(lowest, (tool.global_transform * Vector3(0.0, ArtKit.size("tool.hoe").y, 0.0)).y)
				var counts := _bow_inside(model, tool)
				if counts != Vector3i.ZERO:
					found.append("%s %s %.2f: tool %d, left forearm %d, right arm %d" % [build[0], moment[0], at, counts.x, counts.y, counts.z])
				if work.has("grip"):
					# Two hands on the haft: the left hand's grip (its socket, where it holds a thing) near
					# the line of the haft, between its butt and the right hand.
					var wrist := (holder.get_meta("sockets")["hand_l"] as Node3D).global_position
					var butt := tool.global_position
					var up := tool.global_basis.y.normalized()
					var along := (wrist - butt).dot(up)
					var off := (wrist - butt - up * along).length()
					if off > 0.09 or along < -0.05 or along > float(work["grip"]):
						off_haft.append("%s %.2f: %.2f off, %.2f along" % [build[0], at, off, along])
				model.queue_free()
				holder.free()
	_check(found.is_empty(), "no tool nor arm inside the body, five builds, chopping, sawing, hammering (%s)" % ", ".join(found))
	_check(off_haft.is_empty(), "chopping and hoeing, the left hand on the haft by its butt, five builds (%s)" % ", ".join(off_haft))
	# Hoeing a row (566 amended): the blade's low point clear of the ground, so a field's edge
	# running higher (653) doesn't take it under.
	_check(not ArtKit.has("tool.hoe") or lowest > 0.15, "hoeing: the blade's lowest %s" % (
			"%.2f m above the feet" % lowest if ArtKit.has("tool.hoe") else "unmeasured (no tool.hoe yet)"))
	# The blow lands on art-kit's chopping block (building.chopping_block): its log's top 0.79 m up,
	# about 1 m ahead of the body on the next cell, in line with it.
	var chopper := (load("res://art/models/characters/human_m.glb") as PackedScene).instantiate() as Node3D
	add_child(chopper)
	var chopper_holder := Node3D.new()
	Client3D._attach_sockets(chopper, Client3D.HUMAN_SOCKETS, 1.0, chopper_holder)
	var axe := ArtKit.instance("tool.axe")
	Client3D._grip(axe, Client3D.ACTIVITIES["chop"])
	(chopper_holder.get_meta("sockets")["hand_r"] as Node3D).add_child(axe)
	var chopper_rig := AnimRig.make(chopper, lib, 0.0, true, null)
	chopper_rig.loop("Chop", 0.0, 0.0, true)
	for i in 3:
		chopper_rig.upper_at("Chop", 0.7)
		await get_tree().process_frame
	var blade := axe.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var blade_box := blade.get_aabb()
	var head := chopper.global_transform.affine_inverse() * blade.global_transform * Vector3(blade_box.get_center().x, blade_box.end.y - 0.08, blade_box.get_center().z)
	_check(head.distance_to(CHOP_BLOCK) < 0.1, "the chop's blow lands on the block's top (%s, the top at %s)" % [head, CHOP_BLOCK])
	chopper.queue_free()
	chopper_holder.free()
	# The log on the shoulder (Carry_Shoulder over the walk, held level by _level_load): none of
	# the head or the trunk inside it (art-kit's 0.27 m log went through the crown, in from the
	# shoulder and tipped with the walk's lean).
	var through: Array[String] = []
	for build: Array in builds:
		for at: float in [0.0, 0.25, 0.5, 0.75]:
			var model := (load(build[1]) as PackedScene).instantiate() as Node3D
			add_child(model)
			for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
				for key: String in build[2]:
					var i := mesh.find_blend_shape_by_name(key)
					if i >= 0:
						mesh.set_blend_shape_value(i, build[2][key])
			var holder := Node3D.new()
			Client3D._attach_sockets(model, Client3D.HUMAN_SOCKETS, 1.0, holder)
			var sockets: Dictionary = holder.get_meta("sockets")
			var piece := ArtKit.instance("carry.log")
			piece.name = "Load"
			(sockets["shoulder"] as Node3D).add_child(piece)
			var rig := AnimRig.make(model, lib, 0.0, true, null)
			rig.loop("Walk", 0.0, 0.0, true)
			for i in 3:
				rig.upper_at("Carry_Shoulder", at * rig.length("Carry_Shoulder"))
				await get_tree().process_frame
			Client3D._level_load(sockets)
			var parts := _skinned_parts(model)
			var count := 0
			for mesh: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
				var box := mesh.get_aabb()
				var middle := box.get_center()
				var radius := minf(box.size.y, box.size.z) * 0.5
				var into := mesh.global_transform.affine_inverse()
				for p: Vector3 in parts["head"][0] + parts["trunk"][0]:
					var q := into * p
					if q.x > box.position.x and q.x < box.end.x and Vector2(q.y - middle.y, q.z - middle.z).length() < radius:
						count += 1
			if count > 0:
				through.append("%s %.2f: %d" % [build[0], at, count])
			model.queue_free()
			holder.free()
	_check(through.is_empty(), "a log on the shoulder clear of the head and the trunk, five builds, along the walk (%s)" % ", ".join(through))


## The chopping block's top in a chopper's frame (x its left, y up, z its front): art-kit's
## building.chopping_block on the next cell, its log's top 0.79 m up.
const CHOP_BLOCK := Vector3(0.0, 0.79, 1.0)


## The people's own run and sprint (Client3D.HUMAN_GAITS).
const JOG := "Jog_Short"
const SPRINT := "Sprint_Short"
const TRUNK_BONES := ["Hips", "Spine", "Chest", "UpperChest", "Neck"]


## Vertices inside [param model]'s body, as (the bow in the trunk or the left leg, the left
## forearm in the trunk, the right forearm and hand in the trunk or the head).
static func _bow_inside(model: Node3D, bow: Node3D) -> Vector3i:
	var parts := _skinned_parts(model)
	var points := PackedVector3Array()
	for mesh: MeshInstance3D in bow.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			for v: Vector3 in mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				points.append(mesh.global_transform * v)
	var trunk: Array = parts["trunk"]
	return Vector3i(_inside(points, trunk[0] + parts["leg"][0], trunk[1] + parts["leg"][1]),
		_inside(parts["forearm"][0], trunk[0], trunk[1]),
		_inside(parts["right"][0], trunk[0] + parts["head"][0], trunk[1] + parts["head"][1]))


## [param model]'s Body skinned as it stands, by part: {part: [points, normals]} for "trunk",
## "head", "leg" (the left), "forearm" (the left) and "right" (the right forearm and hand).
static func _skinned_parts(model: Node3D) -> Dictionary:
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
	# {part: [points, normals]}
	var parts := {}
	for part: String in ["trunk", "head", "leg", "forearm", "right"]:
		parts[part] = [PackedVector3Array(), PackedVector3Array()]
	var part_of := {"Head": "head", "LeftUpperLeg": "leg", "LeftLowerLeg": "leg", "LeftLowerArm": "forearm",
		"RightLowerArm": "right", "RightHand": "right"}
	for name: String in TRUNK_BONES:
		part_of[name] = "trunk"
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
		if part_of.has(bone):
			parts[part_of[bone]][0].append(p)
			parts[part_of[bone]][1].append(n.normalized())
	return parts


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


## The painted allies' warm-up (decision 529): each MODELS "paint" warmed in its material and its
## outline twin; a model whose paint this build lacks (a pck without the art) passed over, with
## no error (terrain's bench: a null duplicated).
func _test_warm_painted() -> void:
	print("== the painted allies warmed, a missing paint passed over ==")
	var painted := Client3D.MODELS.keys().filter(func(kind: String) -> bool: return Client3D.MODELS[kind].has("paint"))
	var piece := Client3D.warm_painted()
	_check(piece.get_child_count() == 2 * painted.size(), "each painted model twice, its paint and its twin (%d of %d)" % [piece.get_child_count(), 2 * painted.size()])
	piece.free()
	var models := {"brute": Client3D.MODELS["brute"],
		"lost": {"scene": Client3D.MODELS["brute"]["scene"], "paint": "res://art/models/characters/no_such_body.tres"}}
	piece = Client3D.warm_painted(models)
	_check(piece.get_child_count() == 2, "a model without its paint passed over (%d warmed)" % piece.get_child_count())
	piece.free()

## Fidgets with a thing in hand (662; Jeff: "definitely not scratching head or anything that sword
## goes near body"): each one-handed held kind as Client3D holds it (a blade edge first, the
## shield strapped on the forearm, the bow low in the left with Bow_Idle over the arms), standing
## (Idle, Idle_Tired) and through every fidget Client3D.fidget_with lets it play, five builds, every
## quarter second: no vertex of it inside the trunk, the head or the left leg, none within
## ARMED_HEAD_CLEAR of the head. And none of the scratch, the drink, the sleeve, the crossed arms,
## the shrug, the talking with anything in hand.
func _test_armed_fidgets() -> void:
	print("== fidgets with a thing in hand: clear of the body and the head ==")
	var lib := load(CLIPS) as AnimationLibrary
	var builds := [["man", "res://art/models/characters/human_m.glb", {}],
		["man heavy", "res://art/models/characters/human_m.glb", {"heavy": 1.0}],
		["man broad", "res://art/models/characters/human_m.glb", {"heavy": 0.6, "broad": 1.0}],
		["man lean", "res://art/models/characters/human_m.glb", {"lean": 1.0, "narrow": 1.0}],
		["woman", "res://art/models/characters/human_f.glb", {}]]
	var refused: Array[String] = []
	for clip: String in ["Idle_LookAround", "Drink", "Fidget_Sleeve", "Fidget_ArmsCrossed", "Fidget_Shoulders", "Idle_Talking"]:
		if Client3D.fidget_with(clip, ["sword", ""]) or not Client3D.fidget_with(clip, ["", ""]):
			refused.append(clip)
	_check(refused.is_empty(), "with a sword in hand none of the scratch, drink, sleeve, crossed arms, shrug, talking; empty-handed all (%s)" % [refused])
	var found: Array[String] = []
	var measured := 0
	for kind: String in ["knife", "dagger", "sword", "hammer", "spear", "bow", "shield"]:
		var left: bool = kind == "bow" or "shield" in Items.def(kind).get("tags", [])
		var held := ["", kind] if left else [kind, ""]
		var clips: Array[String] = ["Idle", "Idle_Tired"]
		for clip: String in Client3D.ARMED_FIDGETS:
			if Client3D.fidget_with(clip, held):
				clips.append(clip)
		for build: Array in builds:
			for clip: String in clips:
				var model := (load(build[1]) as PackedScene).instantiate() as Node3D
				add_child(model)
				for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
					for key: String in build[2]:
						var i := mesh.find_blend_shape_by_name(key)
						if i >= 0:
							mesh.set_blend_shape_value(i, build[2][key])
				var holder := Node3D.new()
				Client3D._attach_sockets(model, Client3D.HUMAN_SOCKETS, 1.0, holder)
				var sockets: Dictionary = holder.get_meta("sockets")
				var art := str(Items.def(kind).get("art", "item." + kind))
				var piece := ArtKit.instance(art)
				if "shield" in Items.def(kind).get("tags", []):
					piece.position = -Client3D._strap_of(art)
					(sockets["arm_l"] as Node3D).add_child(piece)
				else:
					if Client3D._edge_first(kind):
						piece.basis = Client3D.HELD_EDGE_TURN
					(sockets["hand_l" if left else "hand_r"] as Node3D).add_child(piece)
				var rig := AnimRig.make(model, lib, 0.0, true, null)
				var length := rig.length(clip)
				var steps := maxi(1, ceili(length / 0.25))
				var worst := ""
				for k in steps + 1:
					var at := minf(k * 0.25, length)
					for i in 3:
						rig.base_at(clip, at)
						if kind == "bow":
							rig.upper(str(Client3D.HUMANOID_MOVES["bow_idle"]))
						await get_tree().process_frame
					var parts := _skinned_parts(model)
					var points := PackedVector3Array()
					for mesh: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
						for s in mesh.mesh.get_surface_count():
							for v: Vector3 in mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
								points.append(mesh.global_transform * v)
					# Only the piece's points within the body's box (and the head's, grown by the
					# clearance) are measured against it: a point by point search of every pair
					# takes minutes.
					var trunk: Array = parts["trunk"]
					var surface: PackedVector3Array = trunk[0] + parts["head"][0] + parts["leg"][0]
					var body_box := _box(surface).grow(0.01)
					var head_box := _box(parts["head"][0]).grow(Client3D.ARMED_HEAD_CLEAR)
					var in_body := PackedVector3Array()
					var by_head := PackedVector3Array()
					for p in points:
						if body_box.has_point(p):
							in_body.append(p)
						if head_box.has_point(p):
							by_head.append(p)
					var inside := _inside(in_body, surface, trunk[1] + parts["head"][1] + parts["leg"][1]) if not in_body.is_empty() else 0
					var near := INF
					for p in by_head:
						for h: Vector3 in parts["head"][0]:
							near = minf(near, p.distance_squared_to(h))
					near = sqrt(near)
					measured += 1
					if (inside > 0 or near < Client3D.ARMED_HEAD_CLEAR) and worst == "":
						worst = "%s %s %s %.2f: %d inside, %.2f m from the head" % [build[0], kind, clip, at, inside, near]
				if worst != "":
					found.append(worst)
				model.queue_free()
				holder.queue_free()
	_check(found.is_empty() and measured > 0, "each held kind clear of the body and %.2f m from the head, standing and through its fidgets, five builds, %d poses (%s)" % [Client3D.ARMED_HEAD_CLEAR, measured, "; ".join(found)])


## Held weapons at rest (662 (b)): each of Client3D.RESTS as Client3D lays it (its upper clip over
## Idle, the piece slid "grip" in the hand), five builds, through the loop: no vertex inside the
## trunk, the head or the left leg, none within ARMED_HEAD_CLEAR of the head; a grounded piece's end
## within REST_GROUND of the ground (a shorter build's axe bites into it a little), a hung one's off it.
const REST_GROUND := 0.2
func _test_rests() -> void:
	print("== held weapons at rest: clear of the body, grounded ==")
	var lib := load(CLIPS) as AnimationLibrary
	var builds := [["man", "res://art/models/characters/human_m.glb", {}],
		["man heavy", "res://art/models/characters/human_m.glb", {"heavy": 1.0}],
		["man broad", "res://art/models/characters/human_m.glb", {"heavy": 0.6, "broad": 1.0}],
		["man lean", "res://art/models/characters/human_m.glb", {"lean": 1.0, "narrow": 1.0}],
		["woman", "res://art/models/characters/human_f.glb", {}]]
	var found: Array[String] = []
	var lows: Array[String] = []
	for kind: String in Client3D.RESTS:
		var rest: Dictionary = Client3D.RESTS[kind]
		var hung := str(rest["upper"]) == "Hang_Rest"
		for build: Array in builds:
			var model := (load(build[1]) as PackedScene).instantiate() as Node3D
			add_child(model)
			for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
				for key: String in build[2]:
					var i := mesh.find_blend_shape_by_name(key)
					if i >= 0:
						mesh.set_blend_shape_value(i, build[2][key])
			var holder := Node3D.new()
			Client3D._attach_sockets(model, Client3D.HUMAN_SOCKETS, 1.0, holder)
			var sockets: Dictionary = holder.get_meta("sockets")
			var piece := ArtKit.instance(str(Items.def(kind).get("art", "item." + kind)))
			piece.name = "Held"
			if Client3D._edge_first(kind):
				piece.basis = Client3D.HELD_EDGE_TURN
			(sockets["hand_r"] as Node3D).add_child(piece)
			Client3D._slide_held(sockets, float(rest.get("grip", 0.0)))
			var rig := AnimRig.make(model, lib, 0.0, true, null)
			rig.loop("Idle", 0.0, 0.0, true)
			var worst := ""
			var low := INF
			for at: float in [0.0, 1.25, 2.5, 3.75]:
				for i in 3:
					rig.upper_at(str(rest["upper"]), at)
					await get_tree().process_frame
				var parts := _skinned_parts(model)
				var points := PackedVector3Array()
				for mesh: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
					for s in mesh.mesh.get_surface_count():
						for v: Vector3 in mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
							points.append(mesh.global_transform * v)
				for p in points:
					low = minf(low, p.y)
				var trunk: Array = parts["trunk"]
				var inside := _inside(points, trunk[0] + parts["head"][0] + parts["leg"][0], trunk[1] + parts["head"][1] + parts["leg"][1])
				var near := INF
				for p in points:
					for h: Vector3 in parts["head"][0]:
						near = minf(near, p.distance_squared_to(h))
				near = sqrt(near)
				if (inside > 0 or near < Client3D.ARMED_HEAD_CLEAR) and worst == "":
					worst = "%s %s %.2f: %d inside, %.2f m from the head" % [build[0], kind, at, inside, near]
			if worst != "":
				found.append(worst)
			if (hung and low < 0.03) or (not hung and absf(low) > REST_GROUND):
				lows.append("%s %s %.2f" % [build[0], kind, low])
			model.queue_free()
			holder.queue_free()
	_check(found.is_empty(), "each rest clear of the body and %.2f m from the head, five builds (%s)" % [Client3D.ARMED_HEAD_CLEAR, "; ".join(found)])
	_check(lows.is_empty(), "each grounded piece's end within %.2f m of the ground, a hung one's off it, five builds (%s)" % [REST_GROUND, ", ".join(lows)])


static func _box(points: PackedVector3Array) -> AABB:
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	return box


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
