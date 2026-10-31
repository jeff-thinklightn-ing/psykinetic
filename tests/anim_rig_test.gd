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
	_test_feel_moved()
	_test_feel_source()
	await _test_strike()
	await _test_one_strike_clip()
	await _test_spear_jab()
	await _test_sword_slash()
	await _test_bow_clear()
	await _test_sky_bow()
	await _test_bow_back()
	await _test_sheathed()
	await _test_sheathe_clips()
	await _test_work_clear()
	await _test_armed_fidgets()
	await _test_beckon()
	_test_knight_vigil()
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


## The animation feel moved to art/kit/feel.json (673 step 2, pc-character's side): every key names
## a constant ("<script>.<constant>") whose value it holds, so the move changes nothing seen.
func _test_feel_moved() -> void:
	print("== the animation feel in art/kit/feel.json ==")
	var scripts := {"client3d": Client3D, "anim_rig": AnimRig, "art_kit": ArtKit, "creature_view": CreatureView}
	var file: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(ArtKit.FEEL)) as Dictionary).get("feel", {})
	var off: Array[String] = []
	# The people's gait paces (674 step 3): a row of HUMAN_GAITS or HUMAN_F_GAITS by its clip.
	var tables := {"client3d.gait": Client3D.HUMAN_GAITS, "client3d.gait_f": Client3D.HUMAN_F_GAITS}
	for key: String in file:
		var parts := key.split(".")
		if parts.size() == 3 and tables.has(parts[0] + "." + parts[1]):
			var rows: Array = (tables[parts[0] + "." + parts[1]] as Array).filter(func(gait: Array) -> bool: return gait[0] == parts[2])
			if rows.is_empty() or not is_equal_approx(float(rows[0][1]), float(file[key])):
				off.append("%s %s (table %s)" % [key, file[key], rows])
			continue
		var script: Script = scripts.get(parts[0])
		var constants := script.get_script_constant_map() if script != null else {}
		var name := parts[1].to_upper() if parts.size() == 2 else ""
		if not constants.has(name) or not is_equal_approx(float(constants[name]), float(file[key])):
			off.append("%s %s (code %s)" % [key, file[key], constants.get(name, "none")])
	_check(file.size() >= 14 and off.is_empty(), "each of feel.json's %d values the constant it names, as the code had it (%s)" % [file.size(), ", ".join(off)])


## The feel on combat's tuning panel (673 step 2): ArtKit's source as Main
## registers it, every key of feel.json a row in Animation, the rig blends
## taking on bodies made after; a change read where it is used; reset to the
## file's value; an unknown key nobody's.
func _test_feel_source() -> void:
	print("== the feel on the tuning panel ==")
	var mode := Net.mode
	Net.mode = Net.Mode.HOST
	Tuning.register_source("feel", ArtKit.feel_value, ArtKit.set_feel_value, ArtKit.feel_fields)
	var rows := {}
	for row: Dictionary in Tuning.fields():
		if str(row["path"]).begins_with("feel."):
			rows[row["path"]] = row
	var file: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ArtKit.FEEL))["feel"]
	var all_in := rows.size() == file.size()
	for key: String in file:
		var row: Dictionary = rows.get("feel." + key, {})
		all_in = all_in and row.get("group") == "Animation" and row.get("kind") == "float" and row.get("owner") == "pc-character" 			and float(row.get("min", INF)) <= float(file[key]) and float(file[key]) <= float(row.get("max", -INF)) 			and row.get("takes") == ("spawn" if key in ["client3d.clip_blend", "creature_view.blend"] else "now")
	_check(all_in, "each of feel.json's %d keys a row in Animation, its value in its range, the blends on spawn" % file.size())
	_check(Tuning.apply("feel.client3d.gait_rate", 1.3) and is_equal_approx(ArtKit.feel("client3d.gait_rate", Client3D.GAIT_RATE), 1.3),
		"gait_rate set to 1.3 from the panel: read where it's used")
	_check(Tuning.reset("feel.client3d.gait_rate") and is_equal_approx(ArtKit.feel("client3d.gait_rate", 0.0), float(file["client3d.gait_rate"])),
		"reset: the file's again")
	_check(Tuning.value("feel.client3d.nothing") == null and not Tuning.apply("feel.client3d.nothing", 1.0), "a key the file lacks: no field")
	Tuning._sources.erase("feel")
	Net.mode = mode


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
	var recover := clampf((length - 0.17) / 0.6, ArtKit.feel("anim_rig.strike_speed_min", AnimRig.STRIKE_SPEED_MIN),
		ArtKit.feel("anim_rig.strike_speed_max", AnimRig.STRIKE_SPEED_MAX))
	await _seconds(0.45)
	_check(is_equal_approx(rig.speed(), recover), "past its contact, the rest fitted to the recovery (x%.2f, wanted x%.2f)" % [rig.speed(), recover])
	_check(rig.busy(), "busy till it is done (%.2f s in all)" % seconds)
	await _seconds(seconds)
	_check(not rig.striking() and rig.playing() == "Idle", "then the idle under it again (%s)" % rig.playing())
	rig.strike("Punch_Jab", 0.17, 0.001, 10.0)
	await _frames(2)
	var most := ArtKit.feel("anim_rig.strike_speed_max", AnimRig.STRIKE_SPEED_MAX)
	_check(is_equal_approx(rig.speed(), most), "hurried past what reads as a blow: kept to x%.1f (x%.2f)" % [most, rig.speed()])
	rig.cancel_strike()
	# The feel tuning (combat's panel): a value set for the run, taken by the next blow; put back.
	ArtKit.set_feel("anim_rig.strike_speed_max", 1.5)
	rig.strike("Punch_Jab", 0.17, 0.001, 10.0)
	await _frames(2)
	_check(is_equal_approx(rig.speed(), 1.5), "the most a blow is hurried set to x1.5 for the run: the next blow kept to it (x%.2f)" % rig.speed())
	ArtKit.set_feel("anim_rig.strike_speed_max", null)
	_check(is_equal_approx(ArtKit.feel("anim_rig.strike_speed_max", -1.0), AnimRig.STRIKE_SPEED_MAX), "and put back: feel.json's (x%.1f)" % ArtKit.feel("anim_rig.strike_speed_max", -1.0))
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


## The spear's strike is a jab (Jeff on v0.1.187: "spear needs a jabbing animation instead of
## slash"), on every body that fights with one (man, woman, goblin, orc, draugr): through
## Spear_Thrust, every 0.05 s, the shaft within SPEAR_LEVEL of level and of the facing, its point
## running out ahead at least SPEAR_DRIVE of the body's height and swinging no more than
## SPEAR_SWAY of it across or up and down (the old clip swung the point 0.5 m up and across).
const SPEAR_LEVEL := 10.0
const SPEAR_DRIVE := 0.3
const SPEAR_SWAY := 0.12
func _test_spear_jab() -> void:
	print("== the spear's jab ==")
	var lib := load(CLIPS) as AnimationLibrary
	var clip := str(Client3D.HUMANOID_MOVES["strikes"]["spear"][0][0])
	var bodies := [["man", Client3D.HUMAN, 1.75], ["woman", Client3D.HUMAN_F, 1.65], ["goblin", Client3D.MODELS["imp"], 1.2],
		["orc", Client3D.MODELS["brute"], 1.95], ["draugr", Client3D.MODELS["draugr"], 1.75]]
	for body: Array in bodies:
		var model: Dictionary = body[1]
		var puppet := Node3D.new()
		add_child(puppet)
		var scene := (load(model["scene"]) as PackedScene).instantiate() as Node3D
		scene.rotation.y = float(model["faces"])
		puppet.add_child(scene)
		var holder := Node3D.new()
		puppet.add_child(holder)
		Client3D._attach_sockets(scene, model["sockets"], 1.0, holder)
		var sockets: Dictionary = holder.get_meta("sockets")
		Client3D._hold(sockets, 0, "spear")
		var spear := (sockets["hand_r"] as Node3D).get_node("Held") as Node3D
		var ends := _held_ends(spear)
		var rig := AnimRig.make(scene, lib, 0.0, true, null)
		var worst := 0.0
		var ahead := Vector2(INF, -INF)
		var across := Vector2(INF, -INF)
		var up := Vector2(INF, -INF)
		var t := 0.0
		while t <= rig.length(clip) + 0.001:
			rig.base_at(clip, t)
			await _frames(2)
			var tip := puppet.global_transform.affine_inverse() * (spear.global_transform * ends[1])
			var butt := puppet.global_transform.affine_inverse() * (spear.global_transform * ends[0])
			var d := (tip - butt).normalized()  # The puppet's front is +x.
			worst = maxf(worst, maxf(absf(rad_to_deg(asin(d.y))), absf(rad_to_deg(atan2(d.z, d.x)))))
			ahead = Vector2(minf(ahead.x, tip.x), maxf(ahead.y, tip.x))
			across = Vector2(minf(across.x, tip.z), maxf(across.y, tip.z))
			up = Vector2(minf(up.x, tip.y), maxf(up.y, tip.y))
			t += 0.05
		var height: float = body[2]
		_check(worst <= SPEAR_LEVEL, "%s: the shaft within %.0f deg of level and the facing (%.1f)" % [body[0], SPEAR_LEVEL, worst])
		_check(ahead.y - ahead.x >= SPEAR_DRIVE * height, "%s: the point driven %.2f m ahead (at least %.2f), out to %.2f m" % [
			body[0], ahead.y - ahead.x, SPEAR_DRIVE * height, ahead.y])
		_check(maxf(across.y - across.x, up.y - up.x) <= SPEAR_SWAY * height, "%s: the point swung %.2f m across, %.2f m up and down (at most %.2f)" % [
			body[0], across.y - across.x, up.y - up.x, SPEAR_SWAY * height])
		puppet.queue_free()


## The sword's slashes (338 amended, pc-character's side; Jeff: "sword swings a little too fast", "a
## small reset to guard between slashes"): the recovery is what's left of the blow's time after the
## lead it took (AnimRig.lead_of), so at a blow every 7 ticks (sword speed 1.4) one's own slash plays
## near its natural speed (SLASH_PACE); each slash starts and ends at the guard (the right hand within
## SLASH_GUARD of it, both ways alike), the forehand cutting right to left and the backhand left to
## right; Client3D picks them by turns.
const SLASH_PACE := [0.6, 1.6]
const SLASH_GUARD := 0.02
func _test_sword_slash() -> void:
	print("== the sword's slashes ==")
	var strikes: Array = Client3D.HUMANOID_MOVES["strikes"]["sword"]
	var between := 7 * World.TICK_DT
	# One's own blow, another's, and either wound up 2 ticks (Client3D.WOUND_STRIKES: its lead
	# played over the wind-up, a slash seen, not only its reset).
	_check("sword" in Client3D.WOUND_STRIKES, "a wound-up sword blow plays its own slash")
	for case: Array in [["one's own", 0.0], ["another's", Client3D.STRIKE_LANDS_IN], ["a wound-up", 2 * World.TICK_DT]]:
		var lands_in := float(case[1])
		var contact := float(strikes[0][1])
		var lead := AnimRig.lead_of(contact, lands_in)
		var length := (load(CLIPS) as AnimationLibrary).get_animation(str(strikes[0][0])).length
		var recover := (length - contact) / maxf(between - lead, 0.2)
		_check(recover >= SLASH_PACE[0] and recover <= SLASH_PACE[1] and lead <= maxf(lands_in, contact / AnimRig.STRIKE_SPEED_MAX) + 0.001
				and lead >= minf(lands_in, contact / AnimRig.STRIKE_SPEED_MIN) - 0.001,
			"%s blow every 7 ticks: the lead %.2f s, the follow-through and the guard at x%.2f" % [case[0], lead, recover])
	var lib := load(CLIPS) as AnimationLibrary
	var at := {}
	for strike: Array in strikes:
		var clip := str(strike[0])
		var length := lib.get_animation(clip).length
		for t: float in [0.0, 0.18, 0.36, length]:
			var body := (load("res://art/models/characters/human_m.glb") as PackedScene).instantiate() as Node3D
			add_child(body)
			var rig := AnimRig.make(body, lib, 0.0, true, null)
			for i in 3:
				rig.base_at(clip, t)
				await get_tree().process_frame
			var sk := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
			at["%s %.2f" % [clip, t]] = sk.get_bone_global_pose(sk.find_bone("RightHand")).origin
			at["%s end" % clip] = at["%s %.2f" % [clip, t]] if t == length else at.get("%s end" % clip, Vector3.ZERO)
			body.free()
		var start: Vector3 = at["%s 0.00" % clip]
		_check(start.distance_to(at["%s end" % clip]) <= SLASH_GUARD and start.distance_to(at["Sword_Slash_F 0.00"]) <= SLASH_GUARD,
			"%s: from the guard and back to it (%.3f m)" % [clip, start.distance_to(at["%s end" % clip])])
		# Skeleton space: the body's left is +x.
		var across: float = (at["%s 0.36" % clip] as Vector3).x - (at["%s 0.18" % clip] as Vector3).x
		var forehand := clip.ends_with("_F")
		_check(across > 0.2 if forehand else across < -0.2, "%s: the cut %s, %.2f m across" % [clip, "right to left" if forehand else "left to right", absf(across)])
	var puppet := Node3D.new()
	puppet.set_meta("rng", RandomNumberGenerator.new())
	var names: Array[String] = []
	for strike: Array in strikes:
		names.append(str(strike[0]))
	var picked: Array[String] = []
	for i in 4:
		picked.append(Client3D._pick_clip(puppet, names))
	puppet.free()
	_check(picked[0] != picked[1] and picked[1] != picked[2] and picked[2] != picked[3], "a string of blows alternates forehand and backhand (%s)" % [picked])


## The form of a full draw: "bow_t" (degrees the bow arm turns off the shoulder line carried on),
## "elbow_off" (the draw elbow's distance from the arrow's line), "elbow_behind" (how far behind the
## nock along it), "nock_eye" (the nock's height over the eyes, Head + 0.07 m).
static func _bow_form(model: Node3D, sockets: Dictionary) -> Dictionary:
	var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var at := func(bone: String) -> Vector3:
		return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin
	var ls: Vector3 = at.call("LeftUpperArm")
	var nock := (sockets["hand_r"] as Node3D).global_position
	var line := ((sockets["hand_l"] as Node3D).global_position - nock).normalized()
	var elbow: Vector3 = at.call("RightLowerArm")
	var head: Vector3 = at.call("Head")
	return {"bow_t": rad_to_deg((at.call("LeftHand") - ls).normalized().angle_to((ls - at.call("RightUpperArm")).normalized())),
		"elbow_off": ((elbow - nock) - line * (elbow - nock).dot(line)).length(), "elbow_behind": -(elbow - nock).dot(line),
		"nock_eye": nock.y - (head.y + 0.07)}


## The two ends of a held piece along its length (its +y), in its own frame: [butt, point].
static func _held_ends(piece: Node3D) -> Array[Vector3]:
	var low := INF
	var high := -INF
	for mesh: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
		var box := piece.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		low = minf(low, box.position.y)
		high = maxf(high, box.end.y)
	return [Vector3(0.0, low, 0.0), Vector3(0.0, high, 0.0)]


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
		["down", "Idle", "Bow_Loose", 0.8],
		# The lob's (677, pc-character's side): the same aimed at the sky.
		["sky raise", "Idle", "Bow_Draw_Sky", 0.42], ["sky raised", "Idle", "Bow_Draw_Sky", 0.55],
		["sky pull", "Idle", "Bow_Draw_Sky", 0.68], ["sky full", "Idle", "Bow_Draw_Sky", 1.0],
		["sky release", "Idle", "Bow_Loose_Sky", 0.09], ["sky down", "Idle", "Bow_Loose_Sky", 0.8]]
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
			if pose[0] in ["full", "sky full"]:
				var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
				var bone := skeleton.find_bone("Head")
				var head := skeleton.get_bone_global_pose(bone).origin
				var wrist := skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")).origin
				# Skeleton space: the body faces +z at rest; the face turns with the head (leaned back
				# at the sky, its forward tips up), so behind the head is against its posed forward.
				var turned := skeleton.get_bone_global_pose(bone).basis * skeleton.get_bone_global_rest(bone).basis.inverse()
				var ahead := (wrist - head).dot((turned * Vector3.BACK).normalized())
				if wrist.distance_to(head) > 0.2 or ahead < -0.04:
					anchors.append("%s %s: wrist %.2f from the head, %.2f ahead of it" % [build[0], pose[0], wrist.distance_to(head), ahead])
			model.queue_free()
			holder.free()
	_check(found.is_empty(), "no bow nor arm inside the body, five builds, carried, nocked, drawn, released, flat and at the sky (%s)" % ", ".join(found))
	_check(anchors.is_empty(), "at full draw, flat and at the sky, the string hand at the jaw, not behind the head (%s)" % ", ".join(anchors))


## The lob's draw (677, pc-character's side): at full draw and held (Bow_Draw_Sky, Bow_Hold_Sky)
## the arrow's line (the string hand's socket to the bow hand's) within SKY_AIM of the lob's
## launch (Client3D.LOB_PITCH, 70 degrees, every lob alike: 677 amended (2)), man and woman, while the
## flat draw's stays within SKY_AIM of level; the bow standing to that line within SKY_AIM of how
## it stands drawn flat (turned with the arm and the lean, it lay back too far); and AnimRig.sky: half mixed, the line halfway
## between; let go, the flat clip's again; played (Bow_Hold), the sky clip in step with it.
## And in form at full draw, flat and at the sky (Jeff on the lob still: "a continous T from arm
## across back ... the back elbow angle dropped to be a line with the arrow, the arrow notch fairly
## close to eye level"): the bow arm within FORM_T of the shoulder line carried on, the draw elbow
## within FORM_ELBOW of the arrow's line (the nock to the bow hand) and FORM_BEHIND behind the nock;
## at the sky the nock within FORM_EYE below the eyes (Head + 0.07 m).
const SKY_AIM := 5.0
const FORM_T := 12.0
const FORM_ELBOW := 0.07
const FORM_BEHIND := 0.2
const FORM_EYE := 0.06
func _test_sky_bow() -> void:
	print("== the lob's draw at the sky ==")
	var lib := load(CLIPS) as AnimationLibrary
	var launch := Client3D.LOB_PITCH
	for build: Array in [["man", "res://art/models/characters/human_m.glb"], ["woman", "res://art/models/characters/human_f.glb"]]:
		var model := (load(build[1]) as PackedScene).instantiate() as Node3D
		add_child(model)
		var holder := Node3D.new()
		model.add_child(holder)
		Client3D._attach_sockets(model, Client3D.HUMAN_SOCKETS, 1.0, holder)
		var sockets: Dictionary = holder.get_meta("sockets")
		var bow := ArtKit.instance("item.bow")
		(sockets["hand_l"] as Node3D).add_child(bow)
		var rig := AnimRig.make(model, lib, 0.0, true, null)
		rig.loop("Idle", 0.0)
		var square := func() -> float:  # The bow's length to the arrow's line, degrees.
			var d := ((sockets["hand_l"] as Node3D).global_position - (sockets["hand_r"] as Node3D).global_position).normalized()
			return rad_to_deg(acos(clampf(d.dot(bow.global_basis.y.normalized()), -1.0, 1.0)))
		var squares := {}
		var pitch := func() -> float:
			var d := ((sockets["hand_l"] as Node3D).global_position - (sockets["hand_r"] as Node3D).global_position).normalized()
			return rad_to_deg(asin(d.y))
		var at := {}
		for moment: Array in [["flat", "Bow_Draw", "", 0.0], ["sky", "Bow_Draw", "Bow_Draw_Sky", 1.0], ["half", "Bow_Draw", "Bow_Draw_Sky", 0.5],
				["held", "Bow_Hold", "Bow_Hold_Sky", 1.0], ["let go", "Bow_Draw", "", 0.0]]:
			rig.upper_at(moment[1], 1.0 if moment[1] == "Bow_Draw" else 0.4)
			rig.sky(moment[2], moment[3])
			await _frames(3)
			at[moment[0]] = pitch.call()
			squares[moment[0]] = square.call()
		_check(absf(at["sky"] - launch) <= SKY_AIM and absf(at["held"] - launch) <= SKY_AIM,
			"%s: drawn and held at the sky, the arrow %.1f and %.1f deg up (the lob leaves at %.0f)" % [build[0], at["sky"], at["held"], launch])
		_check(absf(at["flat"]) <= SKY_AIM, "%s: the flat draw level (%.1f deg)" % [build[0], at["flat"]])
		for drawn: Array in [["flat", "Bow_Draw", false], ["sky", "Bow_Draw_Sky", true]]:
			rig.sky("", 0.0)
			rig.upper_at(drawn[1], 1.0)
			await _frames(3)
			var form := _bow_form(model, sockets)
			_check(form["bow_t"] <= FORM_T and form["elbow_off"] <= FORM_ELBOW and form["elbow_behind"] >= FORM_BEHIND,
				"%s %s: one T, the bow arm %.0f deg off the shoulder line; the draw elbow %.3f m off the arrow's line, %.2f m behind the nock" % [
				build[0], drawn[0], form["bow_t"], form["elbow_off"], form["elbow_behind"]])
			if drawn[2]:
				_check(form["nock_eye"] >= -FORM_EYE and form["nock_eye"] <= 0.02, "%s sky: the nock at eye level (%.3f m)" % [build[0], form["nock_eye"]])
		_check(absf(squares["sky"] - squares["flat"]) <= SKY_AIM, "%s: the bow stands to the arrow at the sky as drawn flat (%.0f, %.0f deg)" % [
			build[0], squares["sky"], squares["flat"]])
		_check(at["half"] > at["flat"] + 10.0 and at["half"] < at["sky"] - 10.0,
			"%s: half mixed, between (%.1f of %.1f..%.1f)" % [build[0], at["half"], at["flat"], at["sky"]])
		_check(absf(at["let go"] - at["flat"]) < 1.0 and rig.sky_amount() == 0.0, "%s: let go, the flat draw again (%.1f)" % [build[0], at["let go"]])
		rig.sky("", 0.0)
		model.queue_free()
	var rig := _goblin()
	rig.loop("Idle")
	rig.upper("Bow_Hold", 1.0, true)
	rig.sky("Bow_Hold_Sky", 0.5)
	rig.tree.advance(0.4)
	var sky_at := float(rig.tree.get("parameters/sky_clip/current_position"))
	_check(absf(sky_at - rig.upper_position()) < 0.02, "played, the sky clip in step with the upper clip (%.3f, %.3f)" % [sky_at, rig.upper_position()])
	rig.sky("", 0.0)
	rig.tree.advance(0.3)
	rig.sky("Bow_Hold_Sky", 0.3)
	rig.tree.advance(0.0)
	sky_at = float(rig.tree.get("parameters/sky_clip/current_position"))
	_check(absf(sky_at - rig.upper_position()) < 0.02, "let go and taken up again, it starts where the upper clip is (%.3f, %.3f)" % [sky_at, rig.upper_position()])
	rig.get_parent().queue_free()


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


## The blades sheathed at the hip and the shields on the back (662 (c)), as Client3D._hold and
## _sheathe put them: on the five builds, standing and through the gaits, no vertex of the sheath
## or its blade inside the trunk or the left leg, none of the shield inside the trunk or the head;
## each blade's tip inside its sheath's sleeve; drawn again, each back in the hand as it was.
func _test_sheathed() -> void:
	print("== the blades sheathed at the hip, the shield on the back ==")
	var lib := load(CLIPS) as AnimationLibrary
	var builds := [["man", "res://art/models/characters/human_m.glb", {}],
		["man heavy", "res://art/models/characters/human_m.glb", {"heavy": 1.0}],
		["man broad", "res://art/models/characters/human_m.glb", {"heavy": 0.6, "broad": 1.0}],
		["man lean", "res://art/models/characters/human_m.glb", {"lean": 1.0, "narrow": 1.0}],
		["woman", "res://art/models/characters/human_f.glb", {}]]
	var poses := [["stand", "Idle", 1], ["walk", Client3D.HUMAN_GAITS[0][0], 1], ["walk", Client3D.HUMAN_GAITS[0][0], 2],
		["jog", JOG, 1], ["jog", JOG, 2], ["sprint", SPRINT, 1], ["sprint", SPRINT, 2]]
	var found: Array[String] = []
	var tips: Array[String] = []
	var back_again := true
	for kit: Array in [["sword", "shield"], ["dagger", "buckler"], ["knife", ""]]:
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
				Client3D._hold(sockets, 0, kit[0])
				Client3D._hold(sockets, 1, kit[1])
				var hand := (sockets["hand_r"] as Node3D).get_node("Held") as Node3D
				var held_at := hand.transform
				var shield := (sockets["arm_l"] as Node3D).get_node_or_null("Held") as Node3D
				var shield_at := shield.transform if shield != null else Transform3D()
				Client3D._sheathe(sockets, true)
				var sheath := (sockets["hip_l"] as Node3D).get_node("Sheath") as Node3D
				var rng := RandomNumberGenerator.new()
				rng.seed = int(pose[2])
				var rig := AnimRig.make(model, lib, 0.0, true, rng)
				rig.loop(pose[1], 0.0)
				for i in 3:
					await get_tree().process_frame
				var parts := _skinned_parts(model)
				var trunk: Array = parts["trunk"]
				var at_hip := _inside(_points(sheath), trunk[0] + parts["leg"][0], trunk[1] + parts["leg"][1])
				var on_back := _inside(_points(shield), trunk[0] + parts["head"][0], trunk[1] + parts["head"][1]) if shield != null else 0
				if at_hip > 0 or on_back > 0 or hand.get_parent() != sheath or (shield != null and shield.get_parent() != sockets["back"]):
					found.append("%s %s %s: hip %d, back %d" % [kit[0], build[0], pose[0], at_hip, on_back])
				if build[0] == "man" and pose[0] == "stand":
					# In the sheath's frame: the blade's lowest point above the sleeve's end.
					var own := sheath.global_transform.affine_inverse()
					var blade := _box(own * _points(hand))
					var blade_points := _points(hand)
					var sleeve_points := PackedVector3Array()
					for p in _points(sheath):
						if not blade_points.has(p):
							sleeve_points.append(p)
					var sleeve := _box(own * sleeve_points)
					if blade.position.y < sleeve.position.y:
						tips.append("%s %.3f below" % [kit[0], sleeve.position.y - blade.position.y])
					Client3D._sheathe(sockets, false)
					back_again = back_again and hand.get_parent() == sockets["hand_r"] and hand.transform.is_equal_approx(held_at) \
						and (shield == null or (shield.get_parent() == sockets["arm_l"] and shield.transform.is_equal_approx(shield_at)))
				model.queue_free()
				holder.queue_free()
	_check(found.is_empty(), "the sheathed blades and the shields on the back clear of the body, five builds, the gaits (%s)" % ", ".join(found))
	_check(tips.is_empty(), "each blade's tip inside its sheath (%s)" % ", ".join(tips))
	_check(back_again, "drawn again, the blade in the hand and the shield on the arm as they were")


## The Sheathe and Draw clips (662 (c)), the sword's and the short sheath's, on the five builds:
## at the moment Client3D moves the blade (SHEATHE_CONTACT, DRAW_GRIP) the hand's grip within
## SHEATHE_REACH of the sheath's mouth and the blade along its sleeve, so it doesn't jump; and
## through the clip while the blade is in hand (the Sheathe to its contact, the Draw from its
## grip), every 0.05 s, no more of it inside the trunk or the left leg than in the hand's own
## held pose at rest (Idle), none of it within SHEATHE_HEAD of the head (the coordinator: the first
## draw brought the hilt up across the face), none through the shield's box (the shield's forearm
## swung out of the way) or within SHEATHE_ARM of that forearm.
const SHEATHE_REACH := 0.04
const SHEATHE_HEAD := 0.08
const SHEATHE_ARM := 0.02
func _test_sheathe_clips() -> void:
	print("== the Sheathe and Draw clips ==")
	var lib := load(CLIPS) as AnimationLibrary
	var builds := [["man", "res://art/models/characters/human_m.glb", {}],
		["man heavy", "res://art/models/characters/human_m.glb", {"heavy": 1.0}],
		["man broad", "res://art/models/characters/human_m.glb", {"heavy": 0.6, "broad": 1.0}],
		["man lean", "res://art/models/characters/human_m.glb", {"lean": 1.0, "narrow": 1.0}],
		["woman", "res://art/models/characters/human_f.glb", {}]]
	var off: Array[String] = []
	var inside: Array[String] = []
	var near: Array[String] = []
	for kit: Array in [["sword", "shield"], ["dagger", "buckler"], ["knife", ""]]:
		var kind: String = kit[0]
		var clips: Array = Client3D.SHEATHE_CLIPS[Client3D.SHEATHS[kind][0]]
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
			Client3D._hold(sockets, 0, kind)
			Client3D._hold(sockets, 1, kit[1])
			var rig := AnimRig.make(model, lib, 0.0, true, null)
			rig.base_at("Idle", 0.0)
			var sheath := (sockets["hip_l"] as Node3D).get_node("Sheath") as Node3D
			var blade := (sockets["hand_r"] as Node3D).get_node("Held") as Node3D
			var shield := (sockets["arm_l"] as Node3D).get_node_or_null("Held") as Node3D
			rig.upper_off()
			for i in 3:
				await get_tree().process_frame
			var parts := _skinned_parts(model)
			var at_rest := _inside(_points(blade), parts["trunk"][0] + parts["leg"][0], parts["trunk"][1] + parts["leg"][1])
			for moment: Array in [[clips[0], Client3D.SHEATHE_CONTACT], [clips[1], Client3D.DRAW_GRIP]]:
				rig.upper_at(moment[0], moment[1])
				for i in 3:
					await get_tree().process_frame
				var mouth := sheath.global_transform * (sheath.get_meta("mouth") as Vector3)
				var gap := blade.global_position.distance_to(mouth)
				var along := blade.global_basis.y.normalized().dot(-sheath.global_basis.y.normalized())
				if gap > SHEATHE_REACH or along < 0.98:
					off.append("%s %s %s %.3f m, %.2f" % [kind, build[0], moment[0], gap, along])
			for span: Array in [[clips[0], 0.0, Client3D.SHEATHE_CONTACT], [clips[1], Client3D.DRAW_GRIP, rig.length(clips[1])]]:
				var t: float = span[1]
				while t <= float(span[2]) + 0.001:
					rig.upper_at(span[0], t)
					for i in 2:
						await get_tree().process_frame
					parts = _skinned_parts(model)
					var points := _points(blade)
					var n := _inside(points, parts["trunk"][0] + parts["leg"][0], parts["trunk"][1] + parts["leg"][1])
					if n > at_rest:
						inside.append("%s %s %s %.2f: %d (at rest %d)" % [kind, build[0], span[0], t, n, at_rest])
					var head := _near(points, parts["head"][0], SHEATHE_HEAD)
					var through := _through_shield(points, shield) if shield != null else 0
					var arm := _near(points, parts["forearm"][0], SHEATHE_ARM)
					if head + through + arm > 0:
						near.append("%s %s %s %.2f: head %d, shield %d, forearm %d" % [kind, build[0], span[0], t, head, through, arm])
					t += 0.05
			model.queue_free()
			holder.queue_free()
	_check(off.is_empty(), "the grip at the sheath's mouth and the blade along its sleeve when it moves, five builds (%s)" % ", ".join(off))
	_check(inside.is_empty(), "the blade in hand through both clips no deeper in the body than held at rest (%s)" % ", ".join(inside))
	_check(near.is_empty(), "the blade in hand through both clips clear of the head, the shield and its forearm (%s)" % ", ".join(near))


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
		_inside(parts["right"][0], trunk[0], trunk[1]) + _inside(parts["right"][0], parts["head"][0], parts["head"][1], true))


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


## [param boxed]: a point outside the surface's box (grown 1 cm) is never counted (a lone part:
## the head's nearest vertex to a string hand held out beside it was the neck's open rim, its normal
## up, and counted the hand inside the head 28 cm off the body's middle; 677, pc-character's side).
static func _inside(points: PackedVector3Array, surface: PackedVector3Array, normals: PackedVector3Array, boxed := false) -> int:
	var n := 0
	if surface.is_empty():
		return 0
	var box := AABB(surface[0], Vector3.ZERO)
	for q in surface:
		box = box.expand(q)
	box = box.grow(0.01)
	for p in points:
		if boxed and not box.has_point(p):
			continue
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


## How many of [points] lie within the shield's own box (its meshes' bounds, in its frame).
static func _through_shield(points: PackedVector3Array, shield: Node3D) -> int:
	var n := 0
	for mesh: MeshInstance3D in shield.find_children("*", "MeshInstance3D", true, false):
		var box := mesh.get_aabb()
		var into := mesh.global_transform.affine_inverse()
		for p in points:
			if box.has_point(into * p):
				n += 1
	return n


## How many of [points] lie within [reach] of any of [surface] (an open mesh, the forearm's,
## where inside can't be told).
static func _near(points: PackedVector3Array, surface: PackedVector3Array, reach: float) -> int:
	var n := 0
	for p in points:
		for q in surface:
			if p.distance_squared_to(q) < reach * reach:
				n += 1
				break
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

## The guide's beckon (companions' guide_wait 2): Client3D.beckon_clip picks the right arm, the
## left when the right hand holds something, neither with both full or not waiting; each clip, man
## and woman, about 0.9 s, the hand above the head at the scoops in (0.36, 0.64) and BECKON_SCOOP
## nearer her than out at 0.2 and 0.5, and the arm never inside the trunk or the head; out (0.2)
## the hand open, palm to him (the coordinator: a fist reads as a cheer): the palm within
## BECKON_PALM of straight ahead (its way: the fingers crossed with the thumb's side, signed so the
## rest pose's palms read down), the middle finger bent at most BECKON_OPEN.
const BECKON_SCOOP := 0.1
const BECKON_PALM := 25.0
const BECKON_OPEN := 20.0
## The fallen knight (747, pc-character's side): his model stands his vigil, looping, never
## fidgeting, on a body that casts no shadow.
func _test_knight_vigil() -> void:
	print("== the fallen knight's vigil ==")
	var lib := load(CLIPS) as AnimationLibrary
	_check(lib.has_animation(Client3D.KNIGHT_VIGIL) and lib.get_animation(Client3D.KNIGHT_VIGIL).loop_mode != Animation.LOOP_NONE,
		"his vigil is in the clips, looping")
	var model: Dictionary = Client3D.MODELS["astral_knight"]
	var puppet := Node3D.new()
	add_child(puppet)
	puppet.add_child(Client3D._make_model(model, puppet))
	var rig := puppet.get_meta("rig") as AnimRig
	var shadows := puppet.find_children("*", "MeshInstance3D", true, false).filter(
		func(mesh: MeshInstance3D) -> bool: return mesh.visible and mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_check(rig.base_clip() == Client3D.KNIGHT_VIGIL and Client3D._idle_clip(puppet) == Client3D.KNIGHT_VIGIL
		and (puppet.get_meta("fidgets") as Dictionary).is_empty() and shadows.is_empty(),
		"his model stands it (%s), never fidgets, and casts no shadow (%d casting)" % [rig.base_clip(), shadows.size()])
	puppet.free()


func _test_beckon() -> void:
	print("== the guide's beckon ==")
	var lib := load(CLIPS) as AnimationLibrary
	var model := (load("res://art/models/characters/human_f.glb") as PackedScene).instantiate() as Node3D
	add_child(model)
	var rig := AnimRig.make(model, lib, 0.0, true, null)
	var picks := []
	for case: Array in [[0, ["", ""]], [1, ["", ""]], [2, ["", ""]], [2, ["sword", ""]], [2, ["", "bow"]], [2, ["sword", "shield"]]]:
		model.set_meta("guide_wait", case[0])
		model.set_meta("held", case[1])
		picks.append(Client3D.beckon_clip(model, rig))
	_check(picks == ["", "", "Beckon_R", "Beckon_L", "Beckon_R", ""],
		"beckoning only at guide_wait 2, with a free hand, the right first (%s)" % [picks])
	model.free()
	for path: String in ["res://art/models/characters/human_m.glb", "res://art/models/characters/human_f.glb"]:
		for clip: String in ["Beckon_R", "Beckon_L"]:
			var ahead := {}
			var notes: Array[String] = []
			var length := 0.0
			for t: float in [0.2, 0.36, 0.5, 0.64]:
				var body := (load(path) as PackedScene).instantiate() as Node3D
				add_child(body)
				var r := AnimRig.make(body, lib, 0.0, true, null)
				r.loop("Idle", 0.0)
				length = r.length(clip)
				for i in 3:
					r.base_at(clip, t)  # As Client3D plays it: the whole body (_play_fidget), the fingers too.
					await get_tree().process_frame
				var sk := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
				var hand := sk.get_bone_global_pose(sk.find_bone("RightHand" if clip == "Beckon_R" else "LeftHand")).origin
				var head := sk.get_bone_global_pose(sk.find_bone("Head")).origin
				ahead[t] = hand.z - head.z  # Skeleton space: the body faces +z.
				if t == 0.2:
					var side := "Right" if clip == "Beckon_R" else "Left"
					var pose := func(bone: String) -> Vector3: return sk.get_bone_global_pose(sk.find_bone(side + bone)).origin
					var rest := func(bone: String) -> Vector3: return sk.get_bone_global_rest(sk.find_bone(side + bone)).origin
					var down: float = ((rest.call("MiddleProximal") - rest.call("Hand")) as Vector3).cross(rest.call("ThumbProximal") - rest.call("Hand")).y
					var along: Vector3 = (pose.call("MiddleProximal") - hand).normalized()
					var palm := along.cross((pose.call("ThumbProximal") - hand).normalized()).normalized() * (-1.0 if down > 0.0 else 1.0)
					var off := rad_to_deg(palm.angle_to(Vector3.BACK))
					var bend := rad_to_deg(along.angle_to(pose.call("MiddleDistal") - pose.call("MiddleProximal")))
					if off > BECKON_PALM or bend > BECKON_OPEN:
						notes.append("out: the palm %.0f deg off ahead, the middle finger bent %.0f" % [off, bend])
				if t in [0.36, 0.64] and hand.y <= head.y:
					notes.append("%.2f: the hand %.2f under the head" % [t, head.y - hand.y])
				var parts: Dictionary = _skinned_parts(body)
				var arm: PackedVector3Array = parts["right" if clip == "Beckon_R" else "forearm"][0]
				var inside := _inside(arm, parts["trunk"][0], parts["trunk"][1]) + _inside(arm, parts["head"][0], parts["head"][1], true)
				if inside > 0:
					notes.append("%.2f: %d inside" % [t, inside])
				body.free()
			var scoop := minf(ahead[0.2] - ahead[0.36], ahead[0.5] - ahead[0.64])
			if scoop < BECKON_SCOOP:
				notes.append("scooped in only %.2f" % scoop)
			if length < 0.7 or length > 1.0:
				notes.append("%.2f s long" % length)
			_check(notes.is_empty(), "%s %s: about 0.9 s, the hand open to him, scooping in twice (%.2f), the hand up, clear of the body (%s)" % [
				path.get_file(), clip, scoop, ", ".join(notes)])


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
