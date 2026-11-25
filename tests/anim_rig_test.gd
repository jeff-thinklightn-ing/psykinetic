extends Node
## AnimRig (decision 390): the goblin on its clips, each layer seen moving
## its bones; loops, a clip held at its end handing over to a loop without
## a frame of standing, a strike timed to its contact and fitted after it,
## the upper layer leaving the legs to the base. Run it with tests/run.ps1
## or tests/run.sh. Prints PASS/FAIL per assertion and quits with exit code
## 1 if any assertion failed, 0 otherwise.

const HeadSize := preload("res://client3d/head_size.gd")
const SCENE := "res://art/models/characters/goblin.glb"
const CLIPS := "res://art/models/animations/goblin.res"

var _failures := 0


## Which half of the list this scene runs (930's split; the coordinator, 11-16: anim_rig_test ran 249 to
## 297 s in saturn's landings, over land.sh's 220 s slow-scene line): 0 the first, anim_rig_test (the rig's
## make and loops, the strikes, the shield and the bow, sheathing and work, about 125 s); 1 the second,
## anim_rig_poses_test, the same script (fidgets and gestures, the props' clips, rests, hafts and wrists,
## the upper layer, the people's feet, about 130 s). Neither takes a port or a scratch folder. A new
## section's call line goes in the half its subject belongs to.
func _half() -> int:
	return 0


func _ready() -> void:
	if _half() == 0:
		await _first_half()
		_result()
		return
	await _test_armed_fidgets()
	await _test_beckon()
	_test_knight_vigil()
	_test_sledge()
	_test_sleep_clips()
	_test_axe_sweep()
	await _test_sledge_sweep()
	await _test_rests()
	await _test_haft_turned()
	await _test_held_wrists()
	_test_warm_painted()
	await _test_upper()
	await _test_upper_timed()
	await _test_no_upper()
	await _test_people_feet()
	_test_people_jog()
	_test_run_body()
	_test_run_vary()
	_test_walk_vary()
	_test_idle_vary()
	_test_vary_cost()
	await _test_gait_phases()
	await _test_gait_switch_feet()
	await _test_run_arms()
	await _test_carry_two()
	await _test_carry_view()
	await _test_posture_arms()
	_test_work_clips_loop()
	await _test_kneel_stays()
	await _test_hand_relax()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## anim_rig_test's half of the list (_half 0).
func _first_half() -> void:
	await _test_make()
	await _test_loop()
	await _test_held_hands_over()
	_test_feel_moved()
	_test_feel_source()
	await _test_strike()
	await _test_strike_held_long_frame()
	await _test_legs_walk()
	await _test_one_strike_clip()
	await _test_spear_jab()
	await _test_dagger_stab()
	await _test_sword_slash()
	await _test_strike_fade()
	await _test_sword_clear()
	await _test_shield_works()
	await _test_bow_clear()
	await _test_sky_bow()
	await _test_bow_renock()
	await _test_bow_back()
	await _test_sheathed()
	await _test_sheathe_clips()
	await _test_work_clear()


func _result() -> void:
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


## A held strike through a long frame (790 amended (9)): a frame longer than the draw carried the
## clip on past its gather into the blow, so the told robber held his crouch with the dagger already
## out and "thrust" back into his recovery. Each phase now puts the clip where it should be: one
## long frame over the draw leaves it held at the gather.
func _test_strike_held_long_frame() -> void:
	print("== a held strike through a long frame ==")
	var rig := _goblin()
	rig.loop("Idle")
	await _frames(3)
	rig.strike_held("Punch_Jab", 0.1, 0.17, 0.8, 0.1, 0.15, 0.6)
	OS.delay_msec(350)  # One frame far past the 0.1 s draw, as on a starved machine.
	await _frames(2)
	_check(rig.striking() and is_zero_approx(rig.speed()) and absf(rig.position() - 0.1) < 0.01,
			"held at its gather (0.10 s in) after a frame past the draw, not carried on (%.3f s in, x%.2f)" % [rig.position(), rig.speed()])
	rig.cancel_strike()
	rig.get_parent().queue_free()


## The legs under a strike ("blows you can see" 2): two bodies walking, the same blow struck on
## each; one's legs given to its walk (legs_walk 1). Its legs differ from the other's (the walk's,
## not the blow's footwork) and go on moving; above them both are the blow's alike.
func _test_legs_walk() -> void:
	print("== the legs walk under a strike ==")
	var still := _goblin(true, 1)
	var walking := _goblin(true, 1)
	for rig: AnimRig in [still, walking]:
		rig.loop("Walk", 1.0, 0.0, true)
	await _frames(3)
	for rig: AnimRig in [still, walking]:
		rig.strike("Punch_Jab", 0.17, 0.34, 0.6)
	walking.legs_walk(1.0)
	await _frames(6)
	var bone := func(rig: AnimRig, name: String) -> Quaternion:
		var skeleton := _skeleton(rig)
		return skeleton.get_bone_pose_rotation(skeleton.find_bone(name))
	var leg_apart: float = (bone.call(still, "LeftUpperLeg") as Quaternion).angle_to(bone.call(walking, "LeftUpperLeg"))
	var chest_apart: float = (bone.call(still, "UpperChest") as Quaternion).angle_to(bone.call(walking, "UpperChest"))
	var leg_then: Quaternion = bone.call(walking, "LeftUpperLeg")
	await _seconds(0.15)  # Time, not frames: headless frames come unthrottled.
	var leg_moved: float = leg_then.angle_to(bone.call(walking, "LeftUpperLeg"))
	_check(walking.striking() and walking.legs_amount() == 1.0 and leg_apart > 0.02 and leg_moved > 0.02 and chest_apart < 0.01,
			"the legs the walk's, still moving (%.3f rad from the blow's, %.3f rad on); the chest the blow's (%.4f rad apart)"
			% [leg_apart, leg_moved, chest_apart])
	walking.legs_walk(0.0)
	still.get_parent().queue_free()
	walking.get_parent().queue_free()


## A strike fades in over a share of its own lead (338 amended (3); Jeff on v0.1.198: "punching
## with a sword in my hand"): the sword's slash, its 0.2 s lead wound up, over 0.05 s, not the whole
## blend that hid its wind-up; a long lead (the sledge's) keeps the blend; and the share is feel's.
func _test_strike_fade() -> void:
	print("== a strike fades in over a share of its lead ==")
	var rig := _goblin()
	rig.loop("Idle")
	await _frames(3)
	var action := rig._root.get_node("action") as AnimationNodeOneShot
	var share := ArtKit.feel("anim_rig.strike_fade_share", AnimRig.STRIKE_FADE_SHARE)
	_check(is_equal_approx(share, 0.25), "feel.json's share 0.25 (%.2f)" % share)
	rig.strike("Sword_Slash_F", 0.21, 0.2, 0.5)
	_check(is_equal_approx(action.fadein_time, 0.05), "the sword's slash, 0.2 s to its contact: faded in over 0.05 s (%.3f)" % action.fadein_time)
	rig.cancel_strike()
	rig.strike("Sledge_Attack", 0.9, 0.9, 0.8)
	_check(is_equal_approx(action.fadein_time, rig.blend), "the sledge's, 0.9 s: over the rig's blend (%.3f)" % action.fadein_time)
	rig.cancel_strike()
	rig.strike("Punch_Jab", 0.17, 0.0, 0.6)
	_check(is_equal_approx(action.fadein_time, 0.17 / AnimRig.STRIKE_SPEED_MAX * 0.25),
		"a jab at the cap: a quarter of its 0.057 s lead (%.3f)" % action.fadein_time)
	rig.cancel_strike()
	ArtKit.set_feel("anim_rig.strike_fade_share", 1.0)
	rig.strike("Sword_Slash_F", 0.21, 0.2, 0.5)
	_check(is_equal_approx(action.fadein_time, rig.blend), "the share set to 1 for the run: the blend again (%.3f)" % action.fadein_time)
	ArtKit.set_feel("anim_rig.strike_fade_share", null)
	rig.cancel_strike()
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


## The dagger's stab (930; the coordinator's line from ui-design's dagger4/5 reads: the free left hand,
## never keyed, swung out ahead on the trunk's counter-turn and read as the stab at 8 m, the blade landing
## low at the belly). On the man and the woman, Dagger_Stab and the robbers' Dagger_Stab_Drawn, each hand
## from the UpperChest bone in the model's frame (ahead is its +z): the free hand never more than
## DAGGER_FREE_AHEAD ahead (main's 0.47 and 0.54 m; redrawn 0.10); at the blade's largest reach its hand
## DAGGER_BLADE_LEADS or more ahead of the free one (main's 0.09; redrawn 0.37); at the clip's contact
## (Client3D's strike and drawn tables) the blade's hand at most DAGGER_CONTACT_UNDER under the chest bone
## (main's 0.21 and 0.20, the belly; redrawn 0.12 and 0.06).
const DAGGER_FREE_AHEAD := 0.15
const DAGGER_BLADE_LEADS := 0.25
const DAGGER_CONTACT_UNDER := 0.17
func _test_dagger_stab() -> void:
	print("== the dagger's stab ==")
	var strike: Array = Client3D.HUMANOID_MOVES["strikes"]["dagger"][0]
	var drawn: Array = Client3D.HUMANOID_MOVES["drawn"]["dagger"][0]
	var contacts := {str(strike[0]): float(strike[1]), str(drawn[0]): float(drawn[1])}
	for build: Array in [SWORD_BUILDS[0], SWORD_BUILDS[4]]:
		var made := _sword_body(self, build)
		var model: Node3D = made[0]
		var rig: AnimRig = made[2]
		var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var place := func(bone: String) -> Vector3:
			return model.global_transform.affine_inverse() * (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin)
		for clip: String in contacts:
			var free_far := -INF
			var blade_far := -INF
			var lead := 0.0
			var t := 0.0
			while t <= rig.length(clip) + 0.001:
				rig.base_at(clip, t)
				await _frames(2)
				var chest: Vector3 = place.call("UpperChest")
				var right: Vector3 = place.call("RightHand") - chest
				var left: Vector3 = place.call("LeftHand") - chest
				free_far = maxf(free_far, left.z)
				if right.z > blade_far:
					blade_far = right.z
					lead = right.z - left.z
				t += 1.0 / 30.0
			rig.base_at(clip, float(contacts[clip]))
			await _frames(2)
			var under: float = (place.call("UpperChest") as Vector3).y - (place.call("RightHand") as Vector3).y
			_check(free_far <= DAGGER_FREE_AHEAD, "%s, %s: the free hand kept in its guard, at most %.3f m ahead of the chest (within %.2f)" % [
				build[0], clip, free_far, DAGGER_FREE_AHEAD])
			_check(lead >= DAGGER_BLADE_LEADS, "%s, %s: the blade's hand %.3f m ahead of the free one at its farthest reach (%.3f m; at least %.2f)" % [
				build[0], clip, lead, blade_far, DAGGER_BLADE_LEADS])
			_check(under <= DAGGER_CONTACT_UNDER, "%s, %s: at contact (%.2f s) the blade's hand %.3f m under the chest bone (at most %.2f), at chest height" % [
				build[0], clip, float(contacts[clip]), under, DAGGER_CONTACT_UNDER])
		model.queue_free()
		(made[3] as Node3D).free()


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


## The sword clear of its wielder (338 amended (3); Jeff on the slash strip: "check for collisions
## with the body. Those body collisions really break the suspension of disbelief"): on the five
## builds of _test_bow_clear, bare and in each worn piece (SWORD_WORN, plate's bulk among them),
## through both slashes and the heavy blow (Client3D.CLIP_HEAVY) at every 1/SWORD_FPS s, the blade
## (the sword's length past the hand, pommel and blade, every 2 cm: _sword_samples) at least
## SWORD_CLEAR from the wielder's trunk, head, legs, off arm and sword's upper arm and from the
## worn piece, never through it, each skinned as posed (_sword_frame); and neither forearm's flesh
## (its bone's line less SWORD_ARM_RADIUS) more than SWORD_ARM_IN into the rest of the body, the
## coil and the arm across the face and the flank among them. Near-misses under SWORD_NEAR are
## printed, not failed. (The first slashes of 338 amended (3) failed it: the pommel into the face
## in both wind-ups, the backhand's forearm through the chin and its elbow into the flank.)
const SWORD_CLEAR := 0.03
## The hood's own (419 amended (2), the coordinator's ruling, its floor): it rides the Head bone and
## grows with the 1.10 head, and the slash's blade passes it at 0.019 m (the woman, Slash_F and
## Sword_Shield_Slash_F at 0.13 s; 0.032 before the head grew) and the men's 0.021 (Slash_F) and 0.025
## (Slash_B at 0.07 s), shield or not, never touching. The smallest pass is printed each run; under
## this the answer is animation's re-pose of the slash, not the bar.
const SWORD_HOOD_CLEAR := 0.015
const SWORD_NEAR := 0.06
const SWORD_FPS := 30.0
const SWORD_ARM_IN := 0.01  # An arm resting on the trunk, its skin pressed in so far, is no clip.
const SWORD_WORN: Array[String] = ["Armour_Leather", "Armour_Mail", "Armour_Plate", "Armour_Robes", "Cape", "Coat", "Hood"]
const SWORD_BUILDS := [["man", "res://art/models/characters/human_m.glb", {}],
	["man heavy", "res://art/models/characters/human_m.glb", {"heavy": 1.0}],
	["man broad", "res://art/models/characters/human_m.glb", {"heavy": 0.6, "broad": 1.0}],
	["man lean", "res://art/models/characters/human_m.glb", {"lean": 1.0, "narrow": 1.0}],
	["woman", "res://art/models/characters/human_f.glb", {}]]
func _test_sword_clear() -> void:
	print("== the sword clear of its wielder ==")
	var lib := load(CLIPS) as AnimationLibrary
	var clips: Array[String] = []
	for key: String in ["sword", "sword_shield"]:
		for strike: Array in Client3D.HUMANOID_MOVES["strikes"][key]:
			clips.append(str(strike[0]))
	clips.append(Client3D.CLIP_HEAVY)
	var fails: Array[String] = []
	var near: Array[String] = []
	var coiled: Array[String] = []
	var least := {}  # {clip: [clearance, where]}
	var hood_least := [INF, "none"]
	var whole_least := [INF, "none"]  # The whole sword, guard included, by the hood.
	var whole_through: Array[String] = []
	for build: Array in SWORD_BUILDS:
		var made := _sword_body(self, build)
		var model: Node3D = made[0]
		var rig: AnimRig = made[2]
		for clip in clips:
			var t := 0.0
			var length := lib.get_animation(clip).length
			while t <= length + 0.001:
				rig.base_at(clip, t)
				await _frames(2)
				var frame := _sword_frame(model, made[1])
				for target: String in frame["clear"]:
					var c: Array = frame["clear"][target]
					var at := "%s%s %s %.2f s: %s %.3f m" % [build[0], "" if target in SWORD_BODY_PARTS else " in " + target.trim_prefix("Armour_").to_lower(),
						clip, t, target.trim_prefix("Armour_").to_lower(), c[0]]
					if float(c[0]) < (SWORD_HOOD_CLEAR if target == "Hood" else SWORD_CLEAR):
						fails.append(at)
					elif float(c[0]) < SWORD_NEAR:
						near.append(at)
					if float(c[0]) < float(least.get(clip, [INF])[0]):
						least[clip] = [c[0], at]
					if target == "Hood" and float(c[0]) < float(hood_least[0]):
						hood_least = [c[0], at]
				var whole: Array = frame["hood_whole"]
				if float(whole[0]) < float(whole_least[0]):
					whole_least = [float(whole[0]), "%s %s %.2f s" % [build[0], clip, t]]
				if bool(whole[1]):
					whole_through.append("%s %s %.2f s" % [build[0], clip, t])
				var coil: Array = frame["coil"]
				if float(coil[0]) < -SWORD_ARM_IN or float(coil[1]) < -SWORD_ARM_IN:
					coiled.append("%s %s %.2f s: off arm %.3f, sword forearm %.3f m" % [build[0], clip, t, coil[0], coil[1]])
				t += 1.0 / SWORD_FPS
		model.queue_free()
		(made[3] as Node3D).free()
	for clip: String in least:
		print("  closest in %s: %s" % [clip, least[clip][1]])
	print("  the hood's smallest pass: %.3f m, floor %.3f (%s)" % [float(hood_least[0]), SWORD_HOOD_CLEAR, hood_least[1]])
	print("  the whole sword (guard and grip too) by the hood: %.3f m at least (%s)" % [float(whole_least[0]), whole_least[1]])
	if not near.is_empty():
		print("  near-misses (under %.2f m): %d, %s" % [SWORD_NEAR, near.size(), ", ".join(near.slice(0, 12))])
	_check(fails.is_empty(), "the blade %.2f m or more clear of the body and what it wears (the hood %.2f m), five builds, %d worn pieces, %s (%d: %s)" % [
		SWORD_CLEAR, SWORD_HOOD_CLEAR, SWORD_WORN.size(), ", ".join(clips), fails.size(), ", ".join(fails.slice(0, 16))])
	# 419 amended (2) held twenty frames where the cross-guard went through the hood's cloth (the forward
	# slashes at 4/30 and 5/30 s); the forehand's wind-up re-posed (338 amended (9)) clears them: none now.
	print("  the sword through the hood: %d frames (%s)" % [whole_through.size(), ", ".join(whole_through.slice(0, 4))])
	_check(whole_through.is_empty(), "the whole sword, guard included, through the hood nowhere (%d: %s)" % [
		whole_through.size(), ", ".join(whole_through.slice(0, 12))])
	_check(coiled.is_empty(), "neither forearm %.2f m or more into the rest of the body through them (%d: %s)" % [SWORD_ARM_IN, coiled.size(), ", ".join(coiled.slice(0, 16))])


## Jeff, 2026-11-07: "sword attacks with a shield in one hand seem like the shield is just along for
## the ride". The sword-and-shield slashes (Client3D's SHIELDED_STRIKES): the blade never into the
## shield; the shield's face (the way its front looks) within the lowered guard's arc
## all through (combat's World.lowered_guard: 45 to 135 degrees round to the left of ahead), out at
## its front edge at guard and on the forehand's wind-up and back at the flank through the cut, its
## middle never behind the hips; the sword hand's path the plain slash's; a sword with a shield on the
## left arm takes these, without one the plain ones.
const SHIELD_SWORD_CLEAR := 0.03
func _test_shield_works() -> void:
	print("== the shield works through the sword's cut ==")
	var lib := load(CLIPS) as AnimationLibrary
	var made := _sword_body(self, SWORD_BUILDS[0])
	var model: Node3D = made[0]
	var rig: AnimRig = made[2]
	var sockets: Dictionary = (made[3] as Node3D).get_meta("sockets")
	Client3D._hold(sockets, 1, "shield")
	await _frames(2)
	var shield := (sockets["arm_l"] as Node3D).get_node("Held") as Node3D
	var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var bone := func(name: String) -> Vector3:
		return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(name)).origin
	var front := model.global_basis.z.normalized()
	var left := model.global_basis.x.normalized()
	var fails: Array[String] = []
	var faces := {}
	var least := INF
	var drift := 0.0
	for pair: Array in [["Sword_Shield_Slash_F", "Sword_Slash_F"], ["Sword_Shield_Slash_B", "Sword_Slash_B"]]:
		var length := lib.get_animation(pair[0]).length
		var t := 0.0
		while t <= length + 0.001:
			rig.base_at(pair[1], t)
			await _frames(2)
			var plain_hand: Vector3 = bone.call("RightHand")
			rig.base_at(pair[0], t)
			await _frames(2)
			drift = maxf(drift, plain_hand.distance_to(bone.call("RightHand")))
			var points := _points(shield)
			var middle := Vector3.ZERO
			for p in points:
				middle += p
			middle /= maxf(points.size(), 1)
			# Its face: the shield art's +z (art_style), the arm_l socket's +z (the forearm's back).
			var face := (sockets["arm_l"] as Node3D).global_basis.z
			var angle := rad_to_deg(atan2(face.dot(left), face.dot(front)))
			faces["%s %.2f" % [str(pair[0]).trim_prefix("Sword_Shield_Slash_"), t]] = snappedf(angle, 1.0)
			if angle < 40.0 or angle > 140.0:
				fails.append("%s %.2f s: faces %.0f deg" % [pair[0], t, angle])
			if (middle - bone.call("Hips")).dot(front) < -0.1:
				fails.append("%s %.2f s: behind the hips" % [pair[0], t])
			var into := false
			for b in _sword_samples(made[1]):
				for p in points:
					least = minf(least, b.distance_to(p))
					into = into or b.distance_to(p) < SHIELD_SWORD_CLEAR
			if into:
				fails.append("%s %.2f s: the blade in the shield" % [pair[0], t])
			t += 1.0 / SWORD_FPS
	print("  shield faces (deg left of ahead): %s" % [faces])
	var at := func(key: String) -> float: return float(faces.get(key, 999.0))
	var front_edge := absf(at.call("F 0.00") - 45.0) < 20.0 and absf(at.call("F 0.13") - 45.0) < 20.0
	var flank := [at.call("F 0.33"), at.call("F 0.40"), at.call("B 0.33"), at.call("B 0.40")].all(func(a: float) -> bool: return absf(a - 90.0) < 25.0)
	_check(fails.is_empty(), "the shield in the lowered guard's arc, never behind the hips, the blade %.2f m clear of it (least %.3f m; %d: %s)"
			% [SHIELD_SWORD_CLEAR, least, fails.size(), ", ".join(fails.slice(0, 12))])
	_check(front_edge and flank, "out at the arc's front edge at guard and on the forehand's wind-up, back at the flank through the cut")
	_check(drift < 0.01, "the sword hand's path the plain slash's (%.4f m apart at most)" % drift)
	var swinger := GridEntity.new()
	var plain := Client3D.strike_key(swinger, "sword")
	var held := PackedStringArray()
	held.resize(Items.LEFT_HAND + 1)
	held[Items.LEFT_HAND] = "shield"
	swinger.slots = held
	_check(plain == "sword" and Client3D.strike_key(swinger, "sword") == "sword_shield" and Client3D.strike_key(swinger, "dagger") == "dagger",
			"a sword with a shield on the left arm takes the shield's slashes, without one the plain ones")
	swinger.free()
	model.queue_free()
	(made[3] as Node3D).free()


## A body of [param build] ([name, scene, shape keys]) under [param parent] holding a sword in its
## right hand as Client3D sockets it: [model, the sword, its AnimRig, the sockets' holder].
static func _sword_body(parent: Node, build: Array) -> Array:
	var model := (load(build[1]) as PackedScene).instantiate() as Node3D
	parent.add_child(model)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for key: String in build[2]:
			var i := mesh.find_blend_shape_by_name(key)
			if i >= 0:
				mesh.set_blend_shape_value(i, build[2][key])
	var holder := Node3D.new()
	Client3D._attach_sockets(model, Client3D.HUMAN_SOCKETS, 1.0, holder)
	var sockets: Dictionary = holder.get_meta("sockets")
	Client3D._hold(sockets, 0, "sword")
	var sword := (sockets["hand_r"] as Node3D).get_node("Held") as Node3D
	return [model, sword, AnimRig.make(model, load(CLIPS) as AnimationLibrary, 0.0, true, null), holder]


## The parts the blade is kept clear of, by the bone a Body vertex hangs on most; the sword's own
## forearm, hand and fingers (and what isn't listed) aren't: the grip is in that hand.
const SWORD_BODY_PARTS := ["trunk", "head", "legs", "off arm", "sword upper arm"]
static func _sword_part(bone: String) -> String:
	if bone in TRUNK_BONES or bone == "LeftShoulder" or bone == "RightShoulder":
		return "trunk"
	if bone == "Head":
		return "head"
	if bone.begins_with("Left") and (bone.contains("Leg") or bone.contains("Foot") or bone.contains("Toes")) \
			or bone.begins_with("Right") and (bone.contains("Leg") or bone.contains("Foot") or bone.contains("Toes")) or bone.begins_with("ball_leaf"):
		return "legs"
	if bone.begins_with("Left") or bone.ends_with("_l"):
		return "off arm"
	if bone == "RightUpperArm":
		return "sword upper arm"
	return ""


## The sword's blade as points: along its length (its +y, _held_ends) every 2 cm, but those within
## SWORD_GRIP of the hand holding it (the grip and the guard in the fist).
const SWORD_GRIP := 0.11
static func _sword_samples(sword: Node3D) -> PackedVector3Array:
	var ends := _held_ends(sword)
	var hand := (sword.get_parent() as Node3D).global_position
	var out := PackedVector3Array()
	var y: float = ends[0].y
	while y <= ends[1].y + 0.0001:
		var p := sword.global_transform * Vector3(0.0, y, 0.0)
		if p.distance_to(hand) > SWORD_GRIP:
			out.append(p)
		y += 0.02
	return out


## One posed frame of [param model] holding [param sword]: {"clear": {target: [the blade's least
## clearance to it, the sample's index]} for each SWORD_BODY_PARTS part the blade comes within
## SWORD_REACH of and each SWORD_WORN piece the model has, "coil": [the off forearm's least
## clearance to the rest of the body, the sword forearm's], "blade": the samples, "body": the
## Body's points, "fore": the sword forearm's line, "trunk": the trunk's points, "fore_at": the
## sword forearm's point nearest the body}.
## The body: the Body's triangles but the sword's forearm, hand and fingers (_sword_part ""). A
## sample's clearance is its distance to the nearest of them (named by its first corner's part),
## less than nothing when the sample is inside the body (a ray down from it crosses the body an odd
## number of times: legs to the soles, the body is closed but where the arm left out joined it).
## A worn piece is a shell: a sample's clearance its distance to it, less than nothing where the
## blade between two samples passes through it. An arm is its bone's line (the forearm's to the
## hand's) every 2 cm, against the body but that whole arm: its clearance the line's least, less
## SWORD_ARM_RADIUS for the arm's own flesh.
const SWORD_REACH := 0.2
const SWORD_ARM_RADIUS := 0.035
static func _sword_frame(model: Node3D, sword: Node3D) -> Dictionary:
	var blade := _sword_samples(sword)
	var hood_whole := [SWORD_REACH, false]
	var body := model.find_child("Body", true, false) as MeshInstance3D
	var skinned := _skin(body)
	var points: PackedVector3Array = skinned[0]
	var bones: PackedStringArray = skinned[2]
	var tris: PackedInt32Array = skinned[3]
	var parts := PackedStringArray()
	for bone in bones:
		parts.append(_sword_part(bone))
	var kept := PackedInt32Array()  # The body but the sword's forearm and hand.
	var but_right := PackedInt32Array()  # The body but the sword arm.
	var but_left := PackedInt32Array()  # The body but the off arm.
	for t in range(0, tris.size(), 3):
		var corner := [tris[t], tris[t + 1], tris[t + 2]]
		var named := [parts[corner[0]], parts[corner[1]], parts[corner[2]]]
		if not "" in named:
			kept.append_array(corner)
			if not "sword upper arm" in named:
				but_right.append_array(corner)
		var left := false
		for i: int in corner:
			left = left or _off_arm_bone(bones[i])
		if not left:
			but_left.append_array(corner)
	var clear := {}
	for k in blade.size():
		var near := _nearest_triangle(blade[k], points, kept)
		if near[1] < 0:
			continue
		var c: float = float(near[0]) * (-1.0 if _inside_mesh(blade[k], points, kept) else 1.0)
		var part := parts[kept[near[1]]]
		if c < float(clear.get(part, [INF])[0]):
			clear[part] = [c, k]
	for name in SWORD_WORN:
		var worn := model.find_child(name, true, false) as MeshInstance3D
		if worn == null:
			continue
		var on := _skin(worn)
		var shell := PackedInt32Array()
		var corners: PackedInt32Array = on[3]
		for t in range(0, corners.size(), 3):
			if _sword_part(on[2][corners[t]]) != "" and _sword_part(on[2][corners[t + 1]]) != "" and _sword_part(on[2][corners[t + 2]]) != "":
				shell.append_array([corners[t], corners[t + 1], corners[t + 2]])
		var best := [SWORD_REACH, -1]
		for k in blade.size():
			var near := _nearest_triangle(blade[k], on[0], shell)
			if near[1] >= 0 and float(near[0]) < float(best[0]):
				best = [near[0], k]
			if k > 0 and blade[k].distance_to(blade[k - 1]) < 0.03 and _crosses(blade[k - 1], blade[k], on[0], shell):
				best = [-0.001, k]
				break
		clear[name] = best
		if name == "Hood":
			hood_whole = _whole_sword_by(sword, on[0], shell)
	var skeleton := body.get_parent() as Skeleton3D
	var lines := []
	for ends: Array in [["LeftLowerArm", "LeftHand"], ["RightLowerArm", "RightHand"]]:
		var a := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(ends[0])).origin
		var b := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(ends[1])).origin
		var out := PackedVector3Array()
		var n := maxi(int(a.distance_to(b) / 0.02), 1)
		for i in n + 1:
			out.append(a.lerp(b, float(i) / n))
		lines.append(out)
	var coil := []
	var fore_at := Vector3.INF
	var fore_part := ""
	for side in 2:
		var against: PackedInt32Array = but_left if side == 0 else but_right
		var least := SWORD_REACH
		for p: Vector3 in lines[side]:
			var near := _nearest_triangle(p, points, against)
			if near[1] < 0:
				continue
			var c: float = float(near[0]) * (-1.0 if _inside_mesh(p, points, against) else 1.0) - SWORD_ARM_RADIUS
			if c < least:
				least = c
				if side == 1:
					fore_at = p
					fore_part = parts[against[near[1]]]
		coil.append(least)
	var trunk_points := PackedVector3Array()
	for i in points.size():
		if bones[i] in TRUNK_BONES:
			trunk_points.append(points[i])
	return {"clear": clear, "blade": blade, "body": points, "coil": coil, "fore": lines[1], "trunk": trunk_points, "fore_at": fore_at,
		"fore_part": fore_part, "hood_whole": hood_whole}


## The whole sword, guard and grip too, against a worn piece's [param verts] / [param corners] (the
## blade's samples are its centreline past SWORD_GRIP, and the guard stands out sideways of it):
## [its vertices' least distance to the piece (SWORD_REACH if none near), whether any of its own
## triangles' edges goes through the piece]. Only what is within SWORD_REACH of the piece's box is
## measured. 419 amended (2): the guard's end grazes the hood at the slash's 4/30 s.
static func _whole_sword_by(sword: Node3D, verts: PackedVector3Array, corners: PackedInt32Array) -> Array:
	if verts.is_empty() or corners.is_empty():
		return [SWORD_REACH, false]
	var box := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		box = box.expand(v)
	box = box.grow(SWORD_REACH)
	var least := SWORD_REACH
	var through := false
	var meshes: Array = sword.find_children("*", "MeshInstance3D", true, false)
	if sword is MeshInstance3D:
		meshes.append(sword)
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var own: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var world := PackedVector3Array()
			world.resize(own.size())
			var near := PackedByteArray()
			near.resize(own.size())
			for i in own.size():
				world[i] = mesh.global_transform * own[i]
				near[i] = 1 if box.has_point(world[i]) else 0
				if near[i] == 1:
					least = minf(least, float(_nearest_triangle(world[i], verts, corners)[0]))
			var tris: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(own.size()))
			for t in range(0, tris.size() - 2, 3):
				if through:
					break
				for e in 3:
					var a := tris[t + e]
					var b := tris[t + (e + 1) % 3]
					if (near[a] == 1 or near[b] == 1) and _crosses(world[a], world[b], verts, corners):
						through = true
						break
	return [least, through]


## Whether [param bone] is the off (left) arm's, from the upper arm to the fingertips.
static func _off_arm_bone(bone: String) -> bool:
	if bone in ["LeftUpperArm", "LeftLowerArm", "LeftHand"]:
		return true
	if bone.begins_with("Left"):
		for finger in ["Thumb", "Index", "Middle", "Ring", "Little"]:
			if bone.contains(finger):
				return true
	return bone.ends_with("_l") and not bone.begins_with("ball")


## The nearest of the triangles [param corners] (of [param verts]) to [param p] within SWORD_REACH:
## [its distance, its first corner's index in corners] ([SWORD_REACH, -1] if none).
static func _nearest_triangle(p: Vector3, verts: PackedVector3Array, corners: PackedInt32Array) -> Array:
	var best := [SWORD_REACH, -1]
	var reach2 := SWORD_REACH * SWORD_REACH
	for t in range(0, corners.size(), 3):
		var a := verts[corners[t]]
		var b := verts[corners[t + 1]]
		var c := verts[corners[t + 2]]
		# A triangle past reach on any axis can't be nearer.
		if minf(a.x, minf(b.x, c.x)) > p.x + SWORD_REACH or maxf(a.x, maxf(b.x, c.x)) < p.x - SWORD_REACH \
				or minf(a.y, minf(b.y, c.y)) > p.y + SWORD_REACH or maxf(a.y, maxf(b.y, c.y)) < p.y - SWORD_REACH \
				or minf(a.z, minf(b.z, c.z)) > p.z + SWORD_REACH or maxf(a.z, maxf(b.z, c.z)) < p.z - SWORD_REACH:
			continue
		var d := p.distance_squared_to(_closest_on_triangle(p, a, b, c))
		if d < reach2:
			reach2 = d
			best = [sqrt(d), t]
	return best


## Whether a ray straight down from [param p] crosses the triangles [param corners] an odd number of times.
static func _inside_mesh(p: Vector3, verts: PackedVector3Array, corners: PackedInt32Array) -> bool:
	var n := 0
	for t in range(0, corners.size(), 3):
		var a := verts[corners[t]]
		var b := verts[corners[t + 1]]
		var c := verts[corners[t + 2]]
		if minf(a.x, minf(b.x, c.x)) > p.x or maxf(a.x, maxf(b.x, c.x)) < p.x or minf(a.z, minf(b.z, c.z)) > p.z \
				or maxf(a.z, maxf(b.z, c.z)) < p.z or minf(a.y, minf(b.y, c.y)) > p.y:
			continue
		if Geometry3D.ray_intersects_triangle(p, Vector3.DOWN, a, b, c) != null:
			n += 1
	return n % 2 == 1


## Whether the segment [param a] to [param b] passes through any of the triangles [param corners].
static func _crosses(a: Vector3, b: Vector3, verts: PackedVector3Array, corners: PackedInt32Array) -> bool:
	for t in range(0, corners.size(), 3):
		if Geometry3D.segment_intersects_triangle(a, b, verts[corners[t]], verts[corners[t + 1]], verts[corners[t + 2]]) != null:
			return true
	return false


## The point of the triangle [param a], [param b], [param c] nearest [param p] (Ericson, Real-Time
## Collision Detection, 5.1.5).
static func _closest_on_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and d4 - d3 >= 0.0 and d5 - d6 >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denom := 1.0 / (va + vb + vc)
	return a + ab * (vb * denom) + ac * (vc * denom)


## Each of [param skin]'s binds posed as the game draws it: HeadSize scales the Head bone's pose by
## HEAD_SCALE after the animation (419 amended (2)), here a uniform scale about the Head's origin of it
## and every bone under it, the same thing.
static func _bone_poses(skeleton: Skeleton3D, skin: Skin) -> Array[Transform3D]:
	var head := skeleton.find_bone("Head")
	var grown := Transform3D.IDENTITY
	if head >= 0:
		var origin := skeleton.global_transform * skeleton.get_bone_global_pose(head).origin
		grown = Transform3D(Basis.from_scale(Vector3.ONE * HeadSize.HEAD_SCALE), origin - origin * HeadSize.HEAD_SCALE)
	var poses: Array[Transform3D] = []
	for b in skin.get_bind_count():
		var bone_index := skin.get_bind_bone(b) if skin.get_bind_name(b) == &"" else skeleton.find_bone(skin.get_bind_name(b))
		var under_head := false
		var up := bone_index
		while up >= 0 and not under_head:
			under_head = up == head
			up = skeleton.get_bone_parent(up)
		poses.append((grown if under_head else Transform3D.IDENTITY) * skeleton.global_transform * skeleton.get_bone_global_pose(bone_index) * skin.get_bind_pose(b))
	return poses


## [param mesh] skinned as it stands (as _skinned_parts: by hand, a headless run registers no skin),
## its shape keys added: [points, normals, the bone each vertex hangs on most, its triangles' corners]. The shaped rest is
## worked out once a mesh ("shaped" meta: a build's keys are set before the first call).
static func _skin(mesh: MeshInstance3D) -> Array:
	var skeleton := mesh.get_parent() as Skeleton3D
	var arrays := mesh.mesh as ArrayMesh
	var src := arrays.surface_get_arrays(0)
	if not mesh.has_meta("shaped"):
		var verts: PackedVector3Array = (src[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
		var shapes := arrays.surface_get_blend_shape_arrays(0)
		for k in shapes.size():
			var weight := mesh.get_blend_shape_value(k)
			if weight == 0.0:
				continue
			var shape: PackedVector3Array = shapes[k][Mesh.ARRAY_VERTEX]
			for i in verts.size():
				var delta := shape[i] - (src[Mesh.ARRAY_VERTEX] as PackedVector3Array)[i] if arrays.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED else shape[i]
				verts[i] += delta * weight
		var bones: PackedInt32Array = src[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = src[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / verts.size()
		var named := PackedStringArray()
		for i in verts.size():
			var best := 0
			for k in per:
				if weights[i * per + k] > weights[i * per + best]:
					best = k
			var b := bones[i * per + best]
			named.append(String(mesh.skin.get_bind_name(b)) if mesh.skin.get_bind_name(b) != &"" else skeleton.get_bone_name(mesh.skin.get_bind_bone(b)))
		mesh.set_meta("shaped", [verts, named])
	var shaped: Array = mesh.get_meta("shaped")
	var verts: PackedVector3Array = shaped[0]
	var normals: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = src[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = src[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / verts.size()
	var skin := mesh.skin
	var poses := _bone_poses(skeleton, skin)
	var points := PackedVector3Array()
	var turned := PackedVector3Array()
	points.resize(verts.size())
	turned.resize(verts.size())
	for i in verts.size():
		var p := Vector3.ZERO
		var n := Vector3.ZERO
		for k in per:
			var w := weights[i * per + k]
			if w <= 0.0:
				continue
			var pose := poses[bones[i * per + k]]
			p += pose * verts[i] * w
			n += pose.basis * normals[i] * w
		points[i] = p
		turned[i] = n.normalized()
	return [points, turned, shaped[1], src[Mesh.ARRAY_INDEX] as PackedInt32Array]


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
## Drawn again inside a loose (928 amended (1); the coordinator on ui-design's cycle strip: through
## Bow_Loose's NOCK the bow dropped to the chest and came back up between two quick shots): the path
## Client3D.bow_nock_at gives from a loose RENOCK_FROM in (Bow_Loose on to BOW_LOOSE_UP, Bow_Renock),
## sampled RENOCK_SAMPLES times, flat and at the sky: the bow hand never more than RENOCK_DROP below
## where the first draw's pull starts (Bow_Draw at BOW_SET_END, the bow up on the line; ui-design's
## snap strip); Bow_Renock's ends on Bow_Loose's BOW_LOOSE_UP and Bow_Draw's BOW_SET_END within
## RENOCK_SEAM (each hand), so the clip changes show nothing. The old path (no renock) is measured
## beside it and printed.
const RENOCK_FROM := 0.2
const RENOCK_SAMPLES := 20
const RENOCK_DROP := 0.04
const RENOCK_SEAM := 0.03
func _test_bow_renock() -> void:
	print("== drawn again inside a loose, the bow kept on the line ==")
	var lib := load(CLIPS) as AnimationLibrary
	_check(lib.has_animation("Bow_Renock") and lib.has_animation("Bow_Renock_Sky")
			and absf(lib.get_animation("Bow_Renock").length - Client3D.BOW_RENOCK_SECONDS) < 0.001
			and absf(lib.get_animation("Bow_Renock_Sky").length - Client3D.BOW_RENOCK_SECONDS) < 0.001,
			"Bow_Renock and its sky clip, %.2f s (BOW_RENOCK_SECONDS)" % Client3D.BOW_RENOCK_SECONDS)
	if not lib.has_animation("Bow_Renock"):
		return
	var clip_of := {"loose": "Bow_Loose", "renock": "Bow_Renock", "draw": "Bow_Draw"}
	var sky_of := {"Bow_Loose": "Bow_Loose_Sky", "Bow_Renock": "Bow_Renock_Sky", "Bow_Draw": "Bow_Draw_Sky"}
	for build: Array in [["man", "res://art/models/characters/human_m.glb"], ["woman", "res://art/models/characters/human_f.glb"]]:
		var model := (load(build[1]) as PackedScene).instantiate() as Node3D
		add_child(model)
		var holder := Node3D.new()
		model.add_child(holder)
		Client3D._attach_sockets(model, Client3D.HUMAN_SOCKETS, 1.0, holder)
		var sockets: Dictionary = holder.get_meta("sockets")
		var rig := AnimRig.make(model, lib, 0.0, true, null)
		rig.loop("Idle", 0.0)
		var hands := func() -> Array:
			var inv := model.global_transform.affine_inverse()
			return [inv * (sockets["hand_l"] as Node3D).global_position, inv * (sockets["hand_r"] as Node3D).global_position]
		var pose := func(clip: String, share: float, sky: bool) -> Array:
			rig.sky(sky_of[clip] if sky else "", 1.0 if sky else 0.0)
			rig.upper_at(clip, share * lib.get_animation(clip).length)  # After the sky's: it seeks both.
			await _frames(3)
			return hands.call()
		for sky: bool in [false, true]:
			var held: Array = await pose.call("Bow_Draw", Client3D.BOW_SET_END, sky)
			var lows := []
			for renock: bool in [true, false]:
				var low := INF
				for i in RENOCK_SAMPLES + 1:
					var at: Array = Client3D.bow_nock_at(float(i) / RENOCK_SAMPLES, RENOCK_FROM, renock)
					var got: Array = await pose.call(clip_of[at[0]], float(at[1]), sky)
					low = minf(low, (got[0] as Vector3).y)
				lows.append((held[0] as Vector3).y - low)
			var name := "%s %s" % [build[0], "sky" if sky else "flat"]
			_check(lows[0] <= RENOCK_DROP, "%s: drawn again inside a loose the bow hand at most %.3f m below where the first draw's pull starts (%.3f; through Bow_Loose's NOCK, the old path: %.3f)" % [
				name, RENOCK_DROP, lows[0], lows[1]])
			var loose_up: Array = await pose.call("Bow_Loose", Client3D.BOW_LOOSE_UP, sky)
			var start: Array = await pose.call("Bow_Renock", 0.0, sky)
			var finish: Array = await pose.call("Bow_Renock", 1.0, sky)
			var set_at: Array = await pose.call("Bow_Draw", Client3D.BOW_SET_END, sky)
			var seams := [(loose_up[0] as Vector3).distance_to(start[0]), (loose_up[1] as Vector3).distance_to(start[1]),
				(finish[0] as Vector3).distance_to(set_at[0]), (finish[1] as Vector3).distance_to(set_at[1])]
			_check(seams.all(func(d: float) -> bool: return d <= RENOCK_SEAM), "%s: Bow_Renock begins on Bow_Loose at %.1f and ends on Bow_Draw at %.2f, each hand within %.2f m (%s)" % [
				name, Client3D.BOW_LOOSE_UP, Client3D.BOW_SET_END, RENOCK_SEAM, seams.map(func(d: float) -> String: return "%.3f" % d)])
		rig.sky("", 0.0)
		model.queue_free()


const SETTLE_DEGREES := Vector2(2.5, 6.0)
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
				["held", "Bow_Hold", "Bow_Hold_Sky", 1.0], ["held flat", "Bow_Hold", "", 0.0], ["settle", "Bow_Hold", "Bow_Hold_Sky", Client3D.BOW_SETTLE_SKY],
				["let go", "Bow_Draw", "", 0.0]]:
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
		# 928 amended (1): the snap's settle, BOW_SETTLE_SKY of the sky clip over the hold, lifts the arrow's
		# line SETTLE_DEGREES (a few degrees: not yet settled, never aimed elsewhere), the bow still square to it.
		var lift: float = at["settle"] - at["held flat"]
		_check(lift >= SETTLE_DEGREES.x and lift <= SETTLE_DEGREES.y and absf(squares["settle"] - squares["held flat"]) <= 1.0,
			"%s: the settle's start lifts the held arrow %.1f deg (%.0f..%.0f), the bow square to it as held (%.1f, %.1f deg)" % [
			build[0], lift, SETTLE_DEGREES.x, SETTLE_DEGREES.y, squares["settle"], squares["held flat"]])
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


## The bow slung and the quiver (662 amended (d), Jeff's "bow back 1"), as Client3D wears them
## by tools/sling_fit's table, on the five builds: standing, every slice of the wood and the quiver
## over the body (but the farthest, the bow's arrow shelf) from SLING_IN inside the skin to
## SLING_OFF off it; walking, none deeper than SLING_WALK_DEEP nor farther off than
## SLING_WALK_LIFT; jogging and sprinting (the bow aimed by _aim_sling) none deeper than
## SLING_RUN_DEEP, the bow no farther off than SLING_RUN_LIFT; the string's path out of the body
## standing, the bow's own hidden; the bow through none of the quiver.
const SlingFit := preload("res://tools/sling_fit.gd")
const SLING_IN := 0.01
const SLING_OFF := 0.02
const SLING_WALK_DEEP := 0.02
## Walking, the bow's foot lifts off the hip with the stride: up to about 5 cm, as Jeff's pick
## sheet for option 1 said (C:/dev/review/rest662/bow_pick.png).
const SLING_WALK_LIFT := 0.05
## How far past the last bent slice's y a measured slice still counts (_lying): half a slice.
const SLING_END_SLACK := 0.02
const SLING_RUN_DEEP := 0.05
const SLING_RUN_LIFT := 0.1
func _test_bow_back() -> void:
	print("== the bow slung and the quiver on the back ==")
	var lib := load(CLIPS) as AnimationLibrary
	var builds := [["man", "res://art/models/characters/human_m.glb", {}],
		["man heavy", "res://art/models/characters/human_m.glb", {"heavy": 1.0}],
		["man broad", "res://art/models/characters/human_m.glb", {"heavy": 0.6, "broad": 1.0}],
		["man lean", "res://art/models/characters/human_m.glb", {"lean": 1.0, "narrow": 1.0}],
		["woman", "res://art/models/characters/human_f.glb", {}]]
	var poses := [["stand", "Idle", 1], ["walk", Client3D.HUMAN_GAITS[0][0], 1], ["walk", Client3D.HUMAN_GAITS[0][0], 2],
		["jog", JOG, 1], ["jog", JOG, 2], ["sprint", SPRINT, 1], ["sprint", SPRINT, 2]]
	var off: Array[String] = []
	var moving: Array[String] = []
	var strung: Array[String] = []
	var crossed: Array[String] = []
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
			Client3D._wear_quiver(sockets, quiver)
			Client3D._stow_bow(sockets, true)
			var rng := RandomNumberGenerator.new()
			rng.seed = int(pose[2])
			var rig := AnimRig.make(model, lib, 0.0, true, rng)
			rig.base_at(pose[1], 0.0 if int(pose[2]) == 1 else 0.3 * rig.length(pose[1]))
			for i in 3:
				await get_tree().process_frame
			Client3D._aim_sling(sockets)
			var surf := SlingFit.surface(model)
			var spans := []
			var fit: Dictionary = (sockets["sling"] as Node3D).get_meta("fit", {})
			for piece: Array in [[bow, Client3D.BOW_IN, "string", "bow"], [quiver, Client3D.QUIVER_IN, "", "quiver"]]:
				var node := piece[0] as Node3D
				var points := SlingFit.facing(node, piece[1], piece[2])
				spans.append(_lying(SlingFit.gaps(surf, points, piece[1], node.global_basis.orthonormalized(), node.global_position), points, fit.get(piece[3] + "_bend", [])))
			var said := "%s %s: bow %.1f to %.1f cm (%d), quiver %.1f to %.1f cm (%d)" % [build[0], pose[0],
				spans[0][0] * 100.0, spans[0][1] * 100.0, spans[0][2], spans[1][0] * 100.0, spans[1][1] * 100.0, spans[1][2]]
			if bow.get_parent() != sockets["sling"] or quiver.get_parent() != sockets["sling"] or int(spans[0][2]) < 4 or int(spans[1][2]) < 4:
				off.append(said + " (not slung)")
			elif pose[0] == "stand":
				if float(spans[0][0]) < -SLING_IN or float(spans[1][0]) < -SLING_IN or float(spans[0][1]) > SLING_OFF or float(spans[1][1]) > SLING_OFF:
					off.append(said)
				var rods := (sockets["sling"] as Node3D).get_node("SlingString") as Node3D
				var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
				var across := sk.global_basis * (sk.get_bone_global_pose(sk.find_bone("LeftUpperArm")).origin - sk.get_bone_global_pose(sk.find_bone("RightUpperArm")).origin)
				across.y = 0.0
				var front := across.normalized().cross(Vector3.UP).normalized()
				var inside: Array[String] = []
				for r in rods.get_child_count():
					for t: float in [-0.5, -0.25, 0.0, 0.25, 0.5]:
						var g := SlingFit.gap(surf, (rods.get_child(r) as Node3D).global_transform * Vector3(0.0, t, 0.0), -front)
						if g < -0.003:
							inside.append("rod %d at %.2f %.1f cm" % [r, t, g * 100.0])
				var shown := 0
				for own: MeshInstance3D in bow.find_children("*string*", "MeshInstance3D", true, false):
					shown += 1 if own.visible else 0
				if not inside.is_empty() or shown > 0 or rods.get_child_count() < 3:
					strung.append("%s: inside %s of %d rods, its own shown %d" % [build[0], inside, rods.get_child_count(), shown])
				# The quiver's round body, its box's ellipse along its length, 1 cm in (2 cm short
				# of each end, rounded narrower than the box).
				var box := _box(quiver.global_transform.affine_inverse() * _points(quiver))
				var mid := box.get_center()
				var half := Vector2(box.size.x * 0.5 - 0.01, box.size.z * 0.5 - 0.01)
				var through := PackedVector3Array()
				for p in quiver.global_transform.affine_inverse() * _points(bow):
					if p.y > box.position.y + 0.02 and p.y < box.end.y - 0.02 and Vector2((p.x - mid.x) / half.x, (p.z - mid.z) / half.y).length() < 1.0:
						through.append(p)
				if not through.is_empty():
					crossed.append("%s %d, %s in the quiver's frame %s" % [build[0], through.size(), through[0], box])
			else:
				var deep := SLING_WALK_DEEP if pose[0] == "walk" else SLING_RUN_DEEP
				var lift := SLING_WALK_LIFT if pose[0] == "walk" else SLING_RUN_LIFT
				# Running, the quiver's foot swings off the back (the woman's, past her flank,
				# 18 cm): only its depth is held.
				if float(spans[0][0]) < -deep or float(spans[1][0]) < -deep or float(spans[0][1]) > lift or (pose[0] == "walk" and float(spans[1][1]) > lift):
					moving.append(said)
			if OS.get_environment("SLING_PRINT") != "":
				print("  ", said)
			model.queue_free()
			holder.queue_free()
	_check(off.is_empty(), "standing, the slung bow's wood and the quiver on the back within %.1f cm of the skin, five builds (%s)" % [SLING_OFF * 100.0, ", ".join(off)])
	_check(moving.is_empty(), "walking, none deeper than %.1f cm nor off by more than %.1f; jogging and sprinting, %.1f and the bow %.1f (%s)" % [SLING_WALK_DEEP * 100.0, SLING_WALK_LIFT * 100.0, SLING_RUN_DEEP * 100.0, SLING_RUN_LIFT * 100.0, ", ".join(moving)])
	_check(strung.is_empty(), "the string drawn over the chest, out of the body, the bow's own hidden (%s)" % ", ".join(strung))
	_check(crossed.is_empty(), "the bow through none of the quiver beside it (%s)" % ", ".join(crossed))


## [least, most, count] of a piece's finite slice gaps, the most leaving out the one farthest:
## the bow's arrow shelf, cut into the grip, stands off the back by its own depth.
## The slices past either end of those Client3D.sling_fit bent onto the skin (bend: its
## [ys, moves]) are past the body's edge, hanging straight (the man's quiver foot past his
## waist, only the thigh 20 cm behind it), and are left out; none between them ever is.
static func _lying(gaps: PackedFloat32Array, points: PackedVector3Array = PackedVector3Array(), bend: Array = []) -> Array:
	var lo := -INF
	var hi := INF
	if bend.size() == 2 and (bend[0] as PackedFloat32Array).size() > 0:
		var ys := bend[0] as PackedFloat32Array
		lo = ys[0]
		hi = ys[0]
		for y in ys:
			lo = minf(lo, y)
			hi = maxf(hi, y)
		lo -= SLING_END_SLACK
		hi += SLING_END_SLACK
	var seen: Array[float] = []
	for i in gaps.size():
		var g := gaps[i]
		if g < INF and (points.is_empty() or (points[i].y >= lo and points[i].y <= hi)):
			seen.append(g)
	seen.sort()
	if seen.is_empty():
		return [INF, -INF, 0]
	return [seen[0], seen[maxi(seen.size() - 2, 0)], seen.size()]


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
	# The edge leads the blow (the coordinator's CHOP_* edges check; 769 amended (9) found the pick's
	# head drawn across its swing): tool.axe's edge toward its own +x, so through the downswing the
	# edge points the way the head moves, and at the block it bites down into the log.
	var to_body := chopper.global_transform.affine_inverse()
	var heads: Array[Vector3] = []
	var edges: Array[Vector3] = []
	for at: float in [0.54, 0.62, 0.7]:
		for i in 3:
			chopper_rig.upper_at("Chop", at)
			await get_tree().process_frame
		heads.append(to_body * blade.global_transform * Vector3(blade_box.get_center().x, blade_box.end.y - 0.08, blade_box.get_center().z))
		edges.append((to_body.basis * axe.global_basis.x).normalized())
	var leads := [edges[0].dot((heads[1] - heads[0]).normalized()), edges[1].dot((heads[2] - heads[1]).normalized())]
	print("    chop: the head %s -> %s -> %s; the edge %s, %s, %s; leading %.2f, %.2f" % [heads[0], heads[1], heads[2],
			edges[0], edges[1], edges[2], leads[0], leads[1]])
	_check(leads[0] > 0.5 and leads[1] > 0.5 and edges[2].y < -0.5,
			"chopping, the axe's edge leads its swing (%.2f, %.2f) and bites down into the block (%.2f)" % [leads[0], leads[1], edges[2].y])
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
	var poses := _bone_poses(skeleton, skin)
	# {part: [points, normals]}
	var parts := {}
	for part: String in ["trunk", "head", "leg", "forearm", "right"]:
		parts[part] = [PackedVector3Array(), []]
	var part_of := {"Head": "head", "LeftUpperLeg": "leg", "LeftLowerLeg": "leg", "LeftLowerArm": "forearm",
		"RightLowerArm": "right", "RightHand": "right"}
	for name: String in TRUNK_BONES:
		part_of[name] = "trunk"
	var placed := PackedVector3Array()
	var turned := PackedVector3Array()
	var part_at := PackedStringArray()
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
		placed.append(p)
		turned.append(n.normalized())
		part_at.append(part_of.get(bone, ""))
	# Each place once (a vertex shared or split, as the build left it), with the normals of every face
	# that meets there, from the posed corners (turned to the side the corners' own normals face).
	# What a body's normals were stored as no longer counts: a smooth body (419 amended (2)) shares its
	# vertices with their normals averaged across a crease, and the nearest vertex's averaged normal
	# called arms and blades by the heavy man's flank inside with no vertex moved.
	var place_of := PackedInt32Array()
	var places := {}
	var where := PackedVector3Array()
	var faces: Array[PackedVector3Array] = []
	var place_part := PackedStringArray()
	for i in placed.size():
		var key := Vector3i((verts[i] * 100000.0).round())
		if not places.has(key):
			places[key] = where.size()
			where.append(placed[i])
			faces.append(PackedVector3Array())
			place_part.append(part_at[i])
		place_of.append(places[key])
	var corners: PackedInt32Array = src[Mesh.ARRAY_INDEX] if src[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if corners.is_empty():
		corners = PackedInt32Array(range(placed.size()))
	for t in range(0, corners.size() - 2, 3):
		var a := placed[corners[t]]
		var face := (placed[corners[t + 1]] - a).cross(placed[corners[t + 2]] - a)
		if face.length_squared() < 1e-14:
			continue
		face = face.normalized()
		if face.dot(turned[corners[t]] + turned[corners[t + 1]] + turned[corners[t + 2]]) < 0.0:
			face = -face
		for c in 3:
			faces[place_of[corners[t + c]]].append(face)
	for k in where.size():
		if place_part[k] != "" and not faces[k].is_empty():
			parts[place_part[k]][0].append(where[k])
			parts[place_part[k]][1].append(faces[k])
	return parts


## [param boxed]: a point outside the surface's box (grown 1 cm) is never counted (a lone part:
## the head's nearest vertex to a string hand held out beside it was the neck's open rim, its normal
## up, and counted the hand inside the head 28 cm off the body's middle; 677, pc-character's side).
static func _inside(points: PackedVector3Array, surface: PackedVector3Array, faces: Array, boxed := false) -> int:
	# [faces]: each of [surface]'s places, the normals of the faces that meet there (_skinned_parts).
	# Inside: within 15 cm of its nearest place and 4 mm or more behind every one of its faces. A flat
	# body's split corners each carried one of those faces and the first one decided, so nothing is
	# counted here that that count let by (on main, and on a smooth body of the same corners).
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
		if at < 0 or best >= 0.0225:
			continue
		var behind := true
		for normal: Vector3 in faces[at] as PackedVector3Array:
			if (p - surface[at]).dot(normal) >= -0.004:
				behind = false
				break
		if behind:
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
	# One shell: each ghost surface's colour after its own depth, so his far side never shows through his near.
	var shells := 0
	var plain := 0
	for mesh: MeshInstance3D in puppet.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var own := mesh.mesh.surface_get_material(surface)
			if own == null or own.resource_name != Client3D.GHOST_MATERIAL:
				continue
			var drawn := mesh.get_surface_override_material(surface)
			var depth: Material = drawn.next_pass if drawn != null else null
			if (drawn != null and drawn.render_priority == Client3D.GHOST_PRIORITY and depth != null
					and depth.render_priority == Client3D.GHOST_DEPTH_PRIORITY and depth.render_priority < drawn.render_priority):
				shells += 1
			else:
				plain += 1
	# He stands as the people stand (877): his vigil, talk and tiredness their People_ copies,
	# the feet under the hips within _test_people_feet's bounds (the UAL's pace apart read as a kneel).
	var skeleton := puppet.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var scene := puppet.get_node("Body/Model") as Node3D
	var gaps: Array[String] = []
	var stands := true
	for t: float in [0.0, 1.0, 2.0, 3.0]:
		rig.base_at(Client3D.KNIGHT_VIGIL, t)
		rig.tree.advance(0.0)
		var at: Array = ["LeftFoot", "RightFoot"].map(func(bone: String) -> Vector3:
			return scene.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin)
		var gap: Vector3 = at[0] - at[1]
		gaps.append("%.2f across, %.2f ahead" % [absf(gap.x), absf(gap.z)])
		stands = stands and absf(gap.x) <= 0.30 and absf(gap.z) <= 0.20
	var played := [rig.as_played(Client3D.KNIGHT_VIGIL), rig.as_played(Client3D.CLIP_TALKING), rig.as_played(Client3D.CLIP_TIRED)]
	_check(rig.stood_as == Client3D.PEOPLE_PREFIX and played == ["People_Knight_Vigil", "People_Idle_Talking", "People_Idle_Tired"] and stands,
		"he stands as the people stand: %s, his feet under his hips (%s)" % [played, ", ".join(gaps)])
	puppet.free()
	var ghost := Node3D.new()
	add_child(ghost)
	ghost.add_child(Client3D._make_model(Client3D.MODELS["ghost"], ghost))
	var overridden := ghost.find_children("*", "MeshInstance3D", true, false).filter(func(mesh: MeshInstance3D) -> bool:
		return range(mesh.mesh.get_surface_count()).any(func(i: int) -> bool:
			var drawn := mesh.get_surface_override_material(i)
			return drawn != null and drawn.next_pass != null and drawn.next_pass == Client3D._ghost_depth))
	_check(shells > 0 and plain == 0 and overridden.is_empty(),
		"he is drawn as one shell, his depth before his colour (%d surfaces, %d plain); the shrouded ghost as before (%d overridden)" % [shells, plain, overridden.size()])
	ghost.free()


## The Tomb Sledge's blow (750, pc-character's side): authored at combat's times, so it plays at
## speed 1 against the sim's wind-up (0.9 s) and recovery (0.8 s), a wound-up blow.
func _test_sledge() -> void:
	print("== the Tomb Sledge's blow ==")
	var lib := load(CLIPS) as AnimationLibrary
	var strikes: Array = Client3D.HUMANOID_MOVES["strikes"].get("tomb_sledge", [])
	_check(lib.has_animation("Sledge_Attack") and absf(lib.get_animation("Sledge_Attack").length - 1.7) < 0.02
		and strikes == [["Sledge_Attack", 0.9]] and "tomb_sledge" in Client3D.WOUND_STRIKES,
		"Sledge_Attack is 1.7 s, its contact at 0.9, the sledge's wound-up blow (%s)" % [strikes])


## The heavy axes' sweep: Axe_Sweep at combat's times (1.3 s, contact 0.8), each axe's wound-up blow.
func _test_axe_sweep() -> void:
	print("== the heavy axes' sweep ==")
	var lib := load(CLIPS) as AnimationLibrary
	var axes := ["giant_axe", "battle_axe"].filter(func(id: String) -> bool:
		return Client3D.HUMANOID_MOVES["strikes"].get(id, []) == [["Axe_Sweep", 0.8]] and id in Client3D.WOUND_STRIKES)
	_check(lib.has_animation("Axe_Sweep") and absf(lib.get_animation("Axe_Sweep").length - 1.3) < 0.02
		and lib.get_animation("Axe_Sweep").loop_mode == Animation.LOOP_NONE and axes.size() == 2,
		"Axe_Sweep is 1.3 s, its contact at 0.8, both heavy axes' wound-up blow (%s)" % [axes])


## Brand's told sweep (the coordinator's yes to animation's design, 11-15): Sledge_Sweep, the Tomb Sledge
## in the right hand as Client3D holds it, on the man and the woman. Each head place in the model's frame
## from its feet: its way round from ahead (+ to his right) and its reach. Coiled and held behind his right
## (SSWEEP_ANGLES[0] or more round at the gather), carried across his front through the three told cells
## (right of SSWEEP_ANGLES[1] at 0.75, within SSWEEP_AT_CONTACT of ahead at the contact, the middle cell,
## left past -SSWEEP_ANGLES[1] by 1.2), at the contact SSWEEP_REACH or more out and between SSWEEP_LOW
## and SSWEEP_HIGH up (knee to waist); the head SSWEEP_CLEAR or more off his hips' upright throughout; the
## left hand's grip (its socket, as the chopping row) within SSWEEP_ON_HAFT of the haft's line throughout, where
## HandReach holds it as in play (grip_2 slid down by REACH_SLIDES, as _slide_reach does: the arm reaches it at
## every frame), the head's centre SSWEEP_FLOOR or more up (its face off the ground); the head's long axis along its travel (SSWEEP_FACE) across the
## carry (its face leads). The coil read apart from Sledge_Attack's wind-up from its first frames (the
## coordinator's condition): the head never over its ready height (at 0) before the gather and SSWEEP_DROP_BY
## or more under it at 0.3 s, where Sledge_Attack lifts it SSWEEP_ATTACK_RISE or more over its own by 0.45 s,
## and SSWEEP_APART or more from where Sledge_Attack has it at 0.3 s.
const SSWEEP_ANGLES := [100.0, 45.0]
const SSWEEP_AT_CONTACT := 15.0
const SSWEEP_REACH := 0.9
const SSWEEP_LOW := 0.25
const SSWEEP_HIGH := 1.0
const SSWEEP_CLEAR := 0.4
const SSWEEP_ON_HAFT := 0.09
const SSWEEP_FLOOR := 0.2
const SSWEEP_FACE := 0.8
const SSWEEP_DROP_BY := 0.4
const SSWEEP_ATTACK_RISE := 0.2
const SSWEEP_APART := 0.6
func _test_sledge_sweep() -> void:
	print("== Brand's told sweep: Sledge_Sweep ==")
	var lib := load(CLIPS) as AnimationLibrary
	var told: Array = Client3D.HUMANOID_MOVES["told"]["sweep"].get("tomb_sledge", [])
	_check(lib.has_animation("Sledge_Sweep") and absf(lib.get_animation("Sledge_Sweep").length - 1.75) < 0.02
		and lib.get_animation("Sledge_Sweep").loop_mode == Animation.LOOP_NONE and told == ["Sledge_Sweep", 0.6, 0.9]
		and Client3D.REACH_SLIDES.has("Sledge_Sweep"),
		"Sledge_Sweep is 1.75 s, the sledge's told sweep gathered at 0.6, its contact at 0.9 (%s), its left hand's slides" % [told])
	if not lib.has_animation("Sledge_Sweep"):
		return
	var off_reach: Array[String] = []
	for build: Array in [SWORD_BUILDS[0], SWORD_BUILDS[4]]:
		var model := (load(build[1]) as PackedScene).instantiate() as Node3D
		add_child(model)
		var holder := Node3D.new()
		Client3D._attach_sockets(model, Client3D.HUMAN_SOCKETS, 1.0, holder)
		var sockets: Dictionary = holder.get_meta("sockets")
		Client3D._hold(sockets, 0, "tomb_sledge")
		var piece := (sockets["hand_r"] as Node3D).get_node("Held") as Node3D
		var tip := _head_of(piece)
		var long := _head_long(piece, tip.y)
		var reach := holder.get_meta("reach") as HandReach
		Client3D._sync_reach(reach, sockets, ["tomb_sledge", ""])
		var second: Vector3 = reach.get_meta("second", Vector3.ZERO)
		if not reach.active:
			off_reach.append(str(build[0]))
		var rig := AnimRig.make(model, lib, 0.0, true, null)
		var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var inv := func() -> Transform3D: return model.global_transform.affine_inverse()
		var bone := func(bone_name: String) -> Vector3:
			return (inv.call() as Transform3D) * (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone_name)).origin)
		rig.base_at("Idle", 0.0)
		await _frames(2)
		var right_way := 1.0 if (bone.call("RightShoulder") as Vector3).x > (bone.call("LeftShoulder") as Vector3).x else -1.0
		var head_at := func() -> Vector3: return (inv.call() as Transform3D) * (piece.global_transform * tip)
		var round_of := func(at: Vector3) -> float: return rad_to_deg(atan2(at.x * right_way, at.z))
		var angles := {}
		var off: Array[String] = []
		var coil_top := -INF
		var ready_up := 0.0
		var dropped := 0.0
		var clear := INF
		var on_haft := 0.0
		var lowest := INF
		var t := 0.0
		while t <= 1.75 + 0.001:
			reach.grip = second + Vector3.DOWN * Client3D._keyed(Client3D.REACH_SLIDES["Sledge_Sweep"], t)
			rig.base_at("Sledge_Sweep", t)
			await _frames(2)
			var head: Vector3 = head_at.call()
			var hips: Vector3 = bone.call("Hips")
			clear = minf(clear, Vector2(head.x - hips.x, head.z - hips.z).length())
			if t < 0.001:
				ready_up = head.y
			elif t <= 0.6 + 0.001:
				coil_top = maxf(coil_top, head.y)
			if absf(t - 0.3) < 0.01:
				dropped = ready_up - head.y
			var butt := (inv.call() as Transform3D) * piece.global_position
			var line := ((inv.call() as Transform3D).basis * piece.global_basis.y).normalized()
			var hand := (inv.call() as Transform3D) * (sockets["hand_l"] as Node3D).global_position
			lowest = minf(lowest, head.y)
			on_haft = maxf(on_haft, ((hand - butt) - line * (hand - butt).dot(line)).length())
			for key: float in [0.6, 0.75, 0.9, 1.2]:
				if absf(t - key) < 0.01:
					angles[key] = [round_of.call(head), Vector2(head.x, head.z).length(), head.y]
			t = snappedf(t + 0.05, 0.05)
		var faces: Array[String] = []
		for at: float in [0.75, 0.8, 0.85, 0.9, 0.95, 1.0]:
			rig.base_at("Sledge_Sweep", at)
			await _frames(2)
			var a: Vector3 = head_at.call()
			var axis := ((inv.call() as Transform3D).basis * (piece.global_basis * long)).normalized()
			rig.base_at("Sledge_Sweep", at + 0.03)
			await _frames(2)
			var travel := (head_at.call() as Vector3) - a
			travel.y = 0.0
			var along := absf(Vector3(axis.x, 0.0, axis.z).normalized().dot(travel.normalized())) if travel.length() > 0.005 else 1.0
			faces.append("%.2f" % along)
			if along < SSWEEP_FACE:
				off.append("its face off its travel at %.2f s (%.2f)" % [at, along])
		reach.reach(false)
		rig.base_at("Sledge_Sweep", 0.3)
		await _frames(2)
		var sweep_at: Vector3 = head_at.call()
		rig.base_at("Sledge_Attack", 0.0)
		await _frames(2)
		var attack_ready: float = (head_at.call() as Vector3).y
		rig.base_at("Sledge_Attack", 0.3)
		await _frames(2)
		var attack_at: Vector3 = head_at.call()
		rig.base_at("Sledge_Attack", 0.45)
		await _frames(2)
		var attack_rise: float = (head_at.call() as Vector3).y - attack_ready
		var g: Array = angles.get(0.6, [0.0, 0.0, 0.0])
		var o: Array = angles.get(0.75, [0.0, 0.0, 0.0])
		var c: Array = angles.get(0.9, [0.0, 0.0, 0.0])
		var p: Array = angles.get(1.2, [0.0, 0.0, 0.0])
		print("  %s: round %.0f / %.0f / %.0f / %.0f deg (gather, 0.75, contact, 1.2); at the contact %.2f m out, %.2f m up; clear %.2f m; left hand %.3f m off the haft; lowest %.2f m; faces %s; coil at most %+.2f m on its ready, %.2f under it at 0.3 (Sledge_Attack %+.2f at 0.45), %.2f m apart at 0.3" % [
			build[0], g[0], o[0], c[0], p[0], c[1], c[2], clear, on_haft, lowest, ", ".join(faces), coil_top - ready_up, dropped, attack_rise, sweep_at.distance_to(attack_at)])
		if float(g[0]) < SSWEEP_ANGLES[0] or float(o[0]) < SSWEEP_ANGLES[1] or absf(float(c[0])) > SSWEEP_AT_CONTACT or float(p[0]) > -SSWEEP_ANGLES[1]:
			off.append("its way round %.0f / %.0f / %.0f / %.0f" % [g[0], o[0], c[0], p[0]])
		if float(c[1]) < SSWEEP_REACH or float(c[2]) < SSWEEP_LOW or float(c[2]) > SSWEEP_HIGH:
			off.append("at the contact %.2f m out, %.2f m up" % [c[1], c[2]])
		if clear < SSWEEP_CLEAR:
			off.append("the head %.2f m off his hips" % clear)
		if on_haft > SSWEEP_ON_HAFT:
			off.append("the left hand %.3f m off the haft" % on_haft)
		if lowest < SSWEEP_FLOOR:
			off.append("the head's centre %.2f m up" % lowest)
		if coil_top > ready_up + 0.001 or dropped < SSWEEP_DROP_BY or attack_rise < SSWEEP_ATTACK_RISE or sweep_at.distance_to(attack_at) < SSWEEP_APART:
			off.append("the coil %+.2f m on its ready, %.2f under it at 0.3 (Sledge_Attack %+.2f), %.2f m from Sledge_Attack's at 0.3" % [
				coil_top - ready_up, dropped, attack_rise, sweep_at.distance_to(attack_at)])
		_check(off.is_empty(), "%s: coiled behind his right, carried across his front through the three cells to the middle at the contact, knee to waist, clear of him, both hands on the haft, off the ground, its face leading, the coil apart from Sledge_Attack's (%s)" % [
			build[0], "; ".join(off)])
		model.queue_free()
		holder.free()

	_check(off_reach.is_empty(), "the sledge in the right hand: the left on its grip_2 (HandReach on; %s)" % ", ".join(off_reach))

## _test_sledge_sweep's: the long axis of [param piece]'s head (its points within 0.2 m of [param centre]
## along the haft, _head_of's height), across the haft: its own x or z, whichever the head spans further.
static func _head_long(piece: Node3D, centre: float) -> Vector3:
	var span := {0: Vector2(INF, -INF), 2: Vector2(INF, -INF)}
	for mesh: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
		var into := piece.global_transform.affine_inverse() * mesh.global_transform
		for s in mesh.mesh.get_surface_count():
			for v: Vector3 in mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var q := into * v
				if absf(q.y - centre) < 0.2:
					for axis: int in [0, 2]:
						span[axis] = Vector2(minf(span[axis].x, q[axis]), maxf(span[axis].y, q[axis]))
	return Vector3.RIGHT if span[0].y - span[0].x >= span[2].y - span[2].x else Vector3.BACK


## The sleeper's clips (751): the curl loops, its breath plainly seen; the lie-down and the get-up
## each end where the other starts (the curl, standing).
func _test_sleep_clips() -> void:
	print("== asleep: the curl, lying down and getting up ==")
	var lib := load(CLIPS) as AnimationLibrary
	var ok := ["Sleep_Side", "Sleep_Down", "Sleep_Up"].all(func(c: String) -> bool: return lib.has_animation(c))
	_check(ok and lib.get_animation("Sleep_Side").loop_mode != Animation.LOOP_NONE and lib.get_animation("Sleep_Down").loop_mode == Animation.LOOP_NONE
		and absf(lib.get_animation("Sleep_Side").length - 5.0) < 0.05, "the curl loops over 5 s; lying down and getting up play once")


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
			Client3D._slide_held(sockets, float(rest.get("grip", 0.0)), true)
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


## [param piece]'s one blade side in its own frame (art_style: across +x or -x of its haft, +y): of its
## points past half its farthest reach off the haft, the side whose span along the haft is at least
## twice the other's (art-kit, 11-12: the giant axe's back spike reaches as far as its blade, 0.30 m,
## but is 0.14 tall to the blade's 0.58); zero for a piece with no one side (a spear, a sledge).
static func _blade_side(piece: Node3D) -> Vector3:
	var points: Array[Vector3] = []
	var reach := 0.0
	for mesh: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
		var into := piece.global_transform.affine_inverse() * mesh.global_transform
		for s in mesh.mesh.get_surface_count():
			for v: Vector3 in mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var p := into * v
				points.append(p)
				reach = maxf(reach, Vector2(p.x, p.z).length())
	var spans := {1: Vector2(INF, -INF), -1: Vector2(INF, -INF)}
	for p in points:
		if Vector2(p.x, p.z).length() > reach * 0.5:
			var side := 1 if p.x > 0.0 else -1
			spans[side] = Vector2(minf(spans[side].x, p.y), maxf(spans[side].y, p.y))
	var tall := {}
	for side: int in spans:
		tall[side] = maxf(0.0, spans[side].y - spans[side].x)
	if tall[1] >= 2.0 * tall[-1] and tall[1] > 0.0:
		return Vector3.RIGHT
	if tall[-1] >= 2.0 * tall[1] and tall[-1] > 0.0:
		return Vector3.LEFT
	return Vector3.ZERO


## How far [param direction] (world) points the way [param model]'s feet do (heels to toes, level),
## -1 to 1, level only.
static func _ahead_of_feet(model: Node3D, direction: Vector3) -> float:
	var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var way := Vector3.ZERO
	for side: String in ["Left", "Right"]:
		way += sk.global_transform * sk.get_bone_global_pose(sk.find_bone(side + "Toes")).origin 			- sk.global_transform * sk.get_bone_global_pose(sk.find_bone(side + "Foot")).origin
	var level := Vector3(direction.x, 0.0, direction.z)
	way.y = 0.0
	return level.normalized().dot(way.normalized()) if level.length() > 0.01 else 0.0


## A one-sided axe in its ready stance (Client3D.HAFT_TURNED; Jeff, v0.1.213: "its the direction in the roused
## stance, with axe blade up toward face, it should be down to ground"; his pick A, the stance turned, 451 amended
## (6)): held as every piece is (HELD_EDGE_TURN), Axe_Ready's right hand turned a quarter round the haft puts its
## edge out ahead (at least READY_EDGE_AHEAD along her feet's way) and down (at most READY_EDGE_UP); and through
## Axe_Sweep from its coil's end to its follow-through the edge leads the head's motion (at least
## SWEEP_EDGE_LEADS), so the turn that rights the stance never turns the blow. The turn moves neither the grip
## (the hand_r socket, the man's body standing, within READY_GRIP_OFF of READY_GRIP) nor the haft's line (within
## READY_HAFT_OFF degrees of READY_HAFT_LINE): both as Jeff approved them (fdc9f91c5's Axe_Ready, measured in game;
## the coordinator, 11-13: "keep the grip point, the haft's line and the head's place as approved").
const READY_GRIP := Vector3(-0.1771, 0.9724, 0.1231)
const READY_HAFT_LINE := Vector3(0.4169, 0.6879, 0.5941)
const READY_GRIP_OFF := 0.01
const READY_HAFT_OFF := 1.0
const READY_EDGE_AHEAD := 0.5
const READY_EDGE_UP := -0.2
const SWEEP_EDGE_LEADS := 0.85
func _test_haft_turned() -> void:
	print("== a one-sided axe: ready, its edge out and down; swung, its edge leading ==")
	var lib := load(CLIPS) as AnimationLibrary
	var off: Array[String] = []
	var read: Array[String] = []
	for kind: String in Client3D.HAFT_TURNED:
		var model := (load("res://art/models/characters/human_m.glb") as PackedScene).instantiate() as Node3D
		add_child(model)
		var holder := Node3D.new()
		Client3D._attach_sockets(model, Client3D.HUMAN_SOCKETS, 1.0, holder)
		var sockets: Dictionary = holder.get_meta("sockets")
		var art := str(Items.def(kind).get("art", "item." + kind))
		var piece := ArtKit.instance(art)
		piece.name = "Held"
		piece.basis = Client3D.HELD_EDGE_TURN
		Client3D._grip_at(piece, art)
		(sockets["hand_r"] as Node3D).add_child(piece)
		var rig := AnimRig.make(model, lib, 0.0, true, null)
		var blade := _blade_side(piece)
		rig.loop("Idle", 0.0, 0.0, true)
		rig.upper_at("Axe_Ready", 0.0)
		await _frames(3)
		var edge := piece.global_basis * blade
		var ahead := _ahead_of_feet(model, edge)
		var grip := (sockets["hand_r"] as Node3D).global_position
		var line := rad_to_deg(piece.global_basis.y.normalized().angle_to(READY_HAFT_LINE.normalized()))
		read.append("%s ready ahead %.2f up %.2f, the grip %.3f m from the approved, the haft %.2f deg" % [kind, ahead, edge.normalized().y,
			grip.distance_to(READY_GRIP), line])
		if grip.distance_to(READY_GRIP) > READY_GRIP_OFF or line > READY_HAFT_OFF:
			off.append("%s ready: the grip %.3f m off the approved, the haft %.2f deg" % [kind, grip.distance_to(READY_GRIP), line])
		if blade == Vector3.ZERO or ahead < READY_EDGE_AHEAD or edge.normalized().y > READY_EDGE_UP:
			off.append("%s ready: ahead %.2f, up %.2f" % [kind, ahead, edge.normalized().y])
		rig.upper_off()
		var tip := _head_of(piece)
		for t: float in [0.55, 0.68, 0.75, 0.8, 0.9]:
			rig.base_at("Axe_Sweep", t)
			await _frames(3)
			var a := piece.global_transform * tip
			rig.base_at("Axe_Sweep", t + 0.03)
			await _frames(3)
			var lead := (piece.global_basis * blade).normalized().dot((piece.global_transform * tip - a).normalized())
			if lead < SWEEP_EDGE_LEADS:
				off.append("%s sweep %.2f: leads %.2f" % [kind, t, lead])
		model.queue_free()
		holder.queue_free()
	print("  ", "; ".join(read))
	_check(off.is_empty() and read.size() == Client3D.HAFT_TURNED.size(), "each one-sided axe ready with its edge out ahead and down, its grip and haft as approved, and swung with it leading (%s)" % "; ".join(off))


## Every pose held with a tool or weapon in hand keeps the wrists that hold it within HELD_WRIST_BEND of their rest
## and HELD_WRIST_TWIST of twist (the coordinator, 11-13, after Axe_Ready bent the right wrist 148 degrees back on the
## forearm, C:/dev/review/animation/wrists_blender.png: "so the next one fails at the gate instead of on a sheet"):
## the ready of each two-hander the left hand reaches for, each rest of Client3D.RESTS, each work of
## Client3D.ACTIVITIES with a tool in the right hand, the man's body, HELD_STEPS samples a loop; the right wrist,
## and the left where HandReach holds it to the haft. A pose in HELD_WRIST_ROWS is printed, not failed: its own row
## is open, named there.
const HELD_STEPS := 12
const HELD_WRIST_BEND := 60.0
const HELD_WRIST_TWIST := 45.0
## Every two-hander the left hand reaches for (a grip_2 within Client3D.REACH_SPAN of its grip).
const REACHED_TWO := ["battle_axe", "giant_axe", "tomb_sledge", "rot_hammer", "pick"]
## In the coordinator's order (11-13), each its own row with its own sheet, a close still beside the measure first:
## the player's rests (on Jeff's body whenever he stands with a weapon out), then the woodcutter's chop, then the
## work poses as people work comes on, the knelt work last.
const HELD_WRIST_ROWS := {
	"Haft_Rest": "1st, the heavy axes' rests (Haft_Rest, Haft_Rest_High)",
	"Hang_Rest": "2nd, the hammer's and the pick's rest",
	"Spear_Rest": "3rd, the spear's rest",
	"Chop": "4th, the woodcutter's chop (its ready 116 degrees)",
	"Hammer": "5th, the smith's hammer",
	"Saw": "6th, the sawyer's saw",
	"Hoe": "7th, the farmer's hoe",
	"Herd": "8th, the herder's crook",
	"Kneel_Work": "last, the knelt work's right hand with the shears (877 amended (1)'s Kneel_Work, twisted 53)"}
func _test_held_wrists() -> void:
	print("== every pose held with a tool in hand: the wrists that hold it in range ==")
	var lib := load(CLIPS) as AnimationLibrary
	var poses: Array = []  # [label, base clip, upper clip, held kind (an item id) or art id]
	for kind: String in REACHED_TWO:
		poses.append(["%s ready" % kind, "Idle", str(Client3D.HUMANOID_MOVES["ready"]), kind])
	for kind: String in Client3D.RESTS:
		if Items.def(kind).is_empty():
			continue
		poses.append(["%s at rest" % kind, "Idle", str(Client3D.RESTS[kind]["upper"]), kind])
	for word: String in Client3D.ACTIVITIES:
		var work: Dictionary = Client3D.ACTIVITIES[word]
		if not work.has("right"):
			continue
		if work.has("upper"):
			poses.append(["%s (%s)" % [word, work["upper"]], "Idle", str(work["upper"]), str(work["right"])])
		else:
			poses.append(["%s (%s)" % [word, work["clip"]], str(work["clip"]), "", str(work["right"])])
	var off: Array[String] = []
	var known: Array[String] = []
	var read: Array[String] = []
	for pose: Array in poses:
		var model := (load("res://art/models/characters/human_m.glb") as PackedScene).instantiate() as Node3D
		add_child(model)
		var holder := Node3D.new()
		add_child(holder)
		Client3D._attach_sockets(model, Client3D.HUMAN_SOCKETS, 1.0, holder)
		var sockets: Dictionary = holder.get_meta("sockets")
		var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var id := str(pose[3])
		var art := id if id.contains(".") else str(Items.def(id).get("art", "item." + id))
		var piece := ArtKit.instance(art)
		piece.name = "Held"
		if not id.contains(".") and Client3D._edge_first(id):
			piece.basis = Client3D.HELD_EDGE_TURN
		Client3D._grip_at(piece, art)
		(sockets["hand_r"] as Node3D).add_child(piece)
		var reach := HandReach.make(sk, (sockets["hand_r"] as Node3D).transform, (sockets["hand_l"] as Node3D).transform)
		if not id.contains("."):
			Client3D._sync_reach(reach, sockets, [id, ""])
		var at := {}
		for bone: String in ["LeftLowerArm", "LeftHand", "RightLowerArm", "RightHand"]:
			var on := BoneAttachment3D.new()
			on.bone_name = bone
			sk.add_child(on)
			at[bone] = on
		var rig := AnimRig.make(model, lib, 0.0, true, null)
		var base := str(pose[1])
		var upper := str(pose[2])
		var clip := upper if upper != "" else base
		var length := rig.length(clip)
		var most := Vector4.ZERO  # right bend, right twist, left bend, left twist (the left only on the haft)
		for i in HELD_STEPS:
			var t := length * float(i) / HELD_STEPS
			if upper != "":
				rig.loop(base, 0.0, 0.0, true)
				rig.upper_at(upper, t)
			else:
				rig.base_at(base, t)
			await _frames(3)
			var wr := _wrist_turn(sk, at, "Right")
			most = Vector4(maxf(most.x, wr.x), maxf(most.y, absf(wr.y)), most.z, most.w)
			if reach.active:
				var wl := _wrist_turn(sk, at, "Left")
				most = Vector4(most.x, most.y, maxf(most.z, wl.x), maxf(most.w, absf(wl.y)))
		read.append("%s: right %.0f/%.0f, left %s" % [pose[0], most.x, most.y, "%.0f/%.0f" % [most.z, most.w] if reach.active else "free"])
		if most.x > HELD_WRIST_BEND or most.y > HELD_WRIST_TWIST or most.z > HELD_WRIST_BEND or most.w > HELD_WRIST_TWIST:
			var row := ""
			for name: String in HELD_WRIST_ROWS:
				if clip.begins_with(name):
					row = str(HELD_WRIST_ROWS[name])
			(known if row != "" else off).append(read[-1] + (" (%s)" % row if row != "" else ""))
		model.queue_free()
		holder.queue_free()
		await _frames(1)
	for line in read:
		print("  ", line)
	for line in known:
		print("  open row: ", line)
	_check(off.is_empty() and read.size() == poses.size(), "every pose held with a tool in hand, its holding wrists within %.0f deg (twist %.0f) (%s)" % [
		HELD_WRIST_BEND, HELD_WRIST_TWIST, "; ".join(off)])


## The wrist's turn from its rest: x the swing off the forearm's line, y the twist about it (-180..180), degrees.
static func _wrist_turn(sk: Skeleton3D, at: Dictionary, side: String) -> Vector2:
	var hand := sk.find_bone(side + "Hand")
	if hand < 0 or not at.has(side + "LowerArm") or not at.has(side + "Hand"):
		return Vector2.ZERO
	var rel := (at[side + "LowerArm"] as Node3D).global_basis.orthonormalized().inverse() * (at[side + "Hand"] as Node3D).global_basis.orthonormalized()
	var d := Quaternion(sk.get_bone_rest(hand).basis.orthonormalized().inverse() * rel)
	var twist := Quaternion(0.0, d.y, 0.0, d.w).normalized()
	var y := (d * twist.inverse()) * Vector3.UP
	return Vector2(rad_to_deg(acos(clampf(y.y, -1.0, 1.0))), wrapf(rad_to_deg(2.0 * atan2(twist.y, twist.w)), -180.0, 180.0))


static func _head_of(piece: Node3D) -> Vector3:
	var points: Array[Vector3] = []
	var top := -INF
	for mesh: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
		var into := piece.global_transform.affine_inverse() * mesh.global_transform
		for s in mesh.mesh.get_surface_count():
			for v: Vector3 in mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				points.append(into * v)
				top = maxf(top, (into * v).y)
	var sum := Vector3.ZERO
	var n := 0
	for p in points:
		if p.y > top - 0.35:
			sum += p
			n += 1
	return sum / maxf(n, 1)


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


## 877: the people's stance. People_Idle stands the feet under the hips (within 0.30 m across and
## 0.20 m fore and aft; the UAL's 0.36 and 0.39). Every "People_" clip that begins or ends where a
## person stands at rest has both feet within PEOPLE_FEET_NEAR of People_Idle's there (none slides a
## foot as it blends in or out); through each, a foot on the ground (within 1 cm of its height at rest)
## moves no more than PEOPLE_SLIDE in a 1/30 s, five builds. The ground sit's own slides (the UAL's,
## its feet drawn in while sat) are not ours to judge.
## The people's gaits (People_Jog_Short, People_Sprint_Short): their feet run on the ground at the gait's pace, never
## stood, so the stance's ends and slide are not theirs (_test_people_jog has the jog's, _test_run_arms the sprint's
## legs as Sprint_Short's).
const PEOPLE_GAITS: Array[String] = ["Jog_Short", "Sprint_Short"]
const PEOPLE_FEET_NEAR := 0.03
const PEOPLE_SLIDE := 0.02
const PEOPLE_START_ELSEWHERE: Array[String] = ["Counter_Low_Idle", "Counter_Low_Show", "Counter_Low_Give", "Counter_Low_Exit",
	"Counter_Bar_Idle", "Counter_Bar_Show", "Counter_Bar_Give", "Counter_Bar_Exit", "Sitting_Exit", "GroundSit_Exit",
	"Kneel_Work", "Kneel_Up"]
const PEOPLE_END_ELSEWHERE: Array[String] = ["Counter_Low_Idle", "Counter_Low_Show", "Counter_Low_Give", "Counter_Low_Enter",
	"Counter_Bar_Idle", "Counter_Bar_Show", "Counter_Bar_Give", "Counter_Bar_Enter", "Sitting_Enter", "GroundSit_Enter",
	"Kneel_Work", "Kneel_Down"]
## Every work word's clip loops (877 amended (1); maps' stills, 11-12: Fixing_Kneeling, down, at work
## and up in one, plays once, so a work's loop of it held its last frame: the hunter stood on straight
## legs), plain and as the people's copy; what it steps in and out with and its asides are there.
func _test_work_clips_loop() -> void:
	print("== every work's clip loops ==")
	var lib := load(CLIPS) as AnimationLibrary
	var off: Array[String] = []
	for word: String in Client3D.ACTIVITIES:
		var work: Dictionary = Client3D.ACTIVITIES[word]
		var looped: Array = (work.get("clips", []) as Array).duplicate()
		if work.has("clip"):
			looped.append(work["clip"])
		for clip: Variant in looped:
			for name: String in [str(clip), Client3D.PEOPLE_PREFIX + str(clip)]:
				if lib.has_animation(name) and lib.get_animation(name).loop_mode == Animation.LOOP_NONE:
					off.append("%s: %s plays once" % [word, name])
		for key: String in ["enter", "exit"]:
			if work.has(key) and not lib.has_animation(str(work[key])):
				off.append("%s: its %s %s is not in the library" % [word, key, work[key]])
	_check(off.is_empty(), "every work's clip loops, its enter and exit there (%d: %s)" % [off.size(), ", ".join(off.slice(0, 8))])


## A person knelt at work stays knelt (877 amended (1)): People_Kneel_Work looped past its length
## keeps the hips low, and People_Kneel_Down ends there.
func _test_kneel_stays() -> void:
	print("== a person knelt at work stays knelt ==")
	var made := _sword_body(self, SWORD_BUILDS[0])
	var model: Node3D = made[0]
	var rig: AnimRig = made[2]
	var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var hips := func() -> float:
		return (model.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Hips")).origin).y
	rig.base_at(Client3D.PEOPLE_PREFIX + Client3D.CLIP_IDLE, 0.0)
	await _frames(2)
	var stood: float = hips.call()
	var length := rig.length(Client3D.PEOPLE_PREFIX + "Kneel_Work")
	rig.loop(Client3D.PEOPLE_PREFIX + "Kneel_Work")
	await _seconds(0.3)
	var early: float = hips.call()
	await _seconds(length + 0.4)
	var late: float = hips.call()
	_check(length > 1.0 and early < stood * 0.6 and late < stood * 0.6 and rig.playing() == Client3D.PEOPLE_PREFIX + "Kneel_Work",
			"knelt at work: the hips %.2f m, and %.2f m past the loop's %.2f s (stood: %.2f m)" % [early, late, length, stood])
	model.queue_free()
	(made[3] as Node3D).free()


func _test_people_feet() -> void:
	print("== the people's stance: feet under the hips, met and kept by every people's clip ==")
	var lib := load(CLIPS) as AnimationLibrary
	var off: Array[String] = []
	var spans: Array[String] = []
	var clips: Array[String] = []
	for clip: String in lib.get_animation_list():
		if clip.begins_with(Client3D.PEOPLE_PREFIX) and not clip.trim_prefix(Client3D.PEOPLE_PREFIX) in PEOPLE_GAITS:
			clips.append(clip)
	# Every build's feet at People_Idle and at each clip's ends; the slide, frame by frame, on the
	# first build only (the clips are one rig's, and a sweep of every clip at 30 frames a second on
	# five builds ran anim_rig_test past its time limit on a loaded landing, 11-12).
	for build: Array in SWORD_BUILDS:
		var sweep := build == SWORD_BUILDS[0]
		var made := _sword_body(self, build)
		var model: Node3D = made[0]
		var rig: AnimRig = made[2]
		var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		if skeleton.find_bone("LeftFoot") < 0 or skeleton.find_bone("RightFoot") < 0:
			off.append("%s has no LeftFoot or RightFoot bone" % build[0])
			model.queue_free()
			(made[3] as Node3D).free()
			continue
		var feet := func() -> Array:
			return ["LeftFoot", "RightFoot"].map(func(bone: String) -> Vector3:
				return model.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin)
		rig.base_at(Client3D.PEOPLE_PREFIX + Client3D.CLIP_IDLE, 0.0)
		await _frames(2)
		var stance: Array = feet.call()
		var gap: Vector3 = stance[0] - stance[1]
		spans.append("%s %.2f across, %.2f ahead" % [build[0], absf(gap.x), absf(gap.z)])
		if absf(gap.x) > 0.30 or absf(gap.z) > 0.20:
			off.append("%s People_Idle's feet %.2f m across, %.2f fore and aft" % [build[0], absf(gap.x), absf(gap.z)])
		for clip in clips:
			var plain := clip.trim_prefix(Client3D.PEOPLE_PREFIX)
			var length := lib.get_animation(clip).length
			var was: Array = []
			var last := floori((length + 0.001) * 30.0)
			for k in range(last + 1):
				if not sweep and k != 0 and k != last:
					continue
				var t := k / 30.0
				rig.base_at(clip, minf(t, length))
				await _frames(2)
				var now: Array = feet.call()
				var end := t == 0.0 and not plain in PEOPLE_START_ELSEWHERE or t + 1.0 / 30.0 > length + 0.001 and not plain in PEOPLE_END_ELSEWHERE
				for side in 2:
					var flat := Vector2(now[side].x - stance[side].x, now[side].z - stance[side].z).length()
					if end and (flat > PEOPLE_FEET_NEAR or absf(float(now[side].y) - float(stance[side].y)) > PEOPLE_FEET_NEAR):
						off.append("%s %s %.2f s: the %s foot %.3f m from People_Idle's" % [build[0], clip, t, ["left", "right"][side], flat])
					if sweep and not was.is_empty() and not plain.begins_with("GroundSit") and float(now[side].y) < float(stance[side].y) + 0.01 							and float(was[side].y) < float(stance[side].y) + 0.01:
						var slid := Vector2(now[side].x - was[side].x, now[side].z - was[side].z).length()
						if slid > PEOPLE_SLIDE:
							off.append("%s %s %.2f s: the %s foot slid %.3f m on the ground" % [build[0], clip, t, ["left", "right"][side], slid])
				was = now
		model.queue_free()
		(made[3] as Node3D).free()
	print("  People_Idle's feet: %s; %d people's clips" % [", ".join(spans), clips.size()])
	_check(lib.has_animation(Client3D.PEOPLE_PREFIX + Client3D.CLIP_IDLE) and off.is_empty(),
			"the people's clips meet People_Idle's feet where they begin or end at rest (within %.2f m) and slide none on the ground (%.2f m a 1/30 s), feet under the hips, five builds (the slide on one) (%d: %s)" % [
			PEOPLE_FEET_NEAR, PEOPLE_SLIDE, off.size(), ", ".join(off.slice(0, 12))])


## An empty hand at rest (decision 938): on the man and the woman, in Idle and mid-Walk, each hand's
## fingertips (each finger's distal joint carried on as far again as its last segment) read from the
## wrist along the hand (its +Y) at the skeleton's update, after its modifiers. The pack's one finger
## pose curls them back under the palm, 0.06 m out (the hook): the check fails that, with the relax off.
## An empty hand at rest has every tip RELAX_TIP_ALONG out or more (0.13 to 0.16 at HAND_RELAX 0.5). A
## hand holding keeps the clip's fist to the millimetre, and so does an empty hand working the other's
## piece: a bow's string hand, a two-handed piece's or a work tool's other hand. The share's ease
## (hand_relax_step). The thumb (the coordinator, 11-15: the pincer's V of air): its tip, carried on as
## its fingers' are, lies within RELAX_THUMB_NEAR of the index finger's line, knuckle to tip, in an empty
## hand at rest (0.040 m the man, 0.038 the woman); the clip's thumb stands 0.075 and 0.071 off it.
const RELAX_TIP_ALONG := 0.11
const RELAX_THUMB_NEAR := 0.055
func _test_hand_relax() -> void:
	print("== an empty hand at rest ==")
	var lib := load(CLIPS) as AnimationLibrary
	var hooked: Array[String] = []
	var tight: Array[String] = []
	var moved: Array[String] = []
	var least := INF
	var thumb_far := 0.0
	var thumb_hook := INF
	var cases := [["empty", ["", ""], [true, true]], ["a sword in the right", ["sword", ""], [false, true]],
		["a bow in the left (the string hand)", ["", "bow"], [false, false]],
		["a two-handed axe", ["battle_axe", ""], [false, false]],
		["a work's tool", [Client3D.ART_ID + "tool.axe", ""], [false, false]]]
	for build: Array in [SWORD_BUILDS[0], SWORD_BUILDS[4]]:
		var model := (load(build[1]) as PackedScene).instantiate() as Node3D
		add_child(model)
		var holder := Node3D.new()
		add_child(holder)
		Client3D._attach_sockets(model, Client3D.HUMAN_SOCKETS, 1.0, holder)
		Client3D._relax_hands(model, holder)
		var relax := holder.get_meta("hand_relax") as SkeletonModifier3D
		var rig := AnimRig.make(model, lib, 0.0, true, null)
		var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var caught := {}
		skeleton.skeleton_updated.connect(func() -> void:
			caught["tips"] = [_relax_tips(skeleton, "Right"), _relax_tips(skeleton, "Left")]
			caught["thumbs"] = [_relax_thumb(skeleton, "Right"), _relax_thumb(skeleton, "Left")])
		for at: Array in [["Idle", 0.0], ["Walk", 0.4]]:
			rig.base_at(at[0], at[1])
			relax.active = false
			await _frames(3)
			var fist: Array = caught["tips"]
			for hand in 2:
				thumb_hook = minf(thumb_hook, float(caught["thumbs"][hand]))
				if _relax_least(fist[hand]) >= RELAX_TIP_ALONG:
					hooked.append("%s %s %s with the relax off: %.3f" % [build[0], at[0], ["right", "left"][hand], _relax_least(fist[hand])])
			relax.active = true
			for case: Array in cases:
				holder.set_meta("held", case[1])
				relax.share = Vector2(-1.0, -1.0)
				await _frames(3)
				var tips: Array = caught["tips"]
				for hand in 2:
					var where := "%s %s, %s: the %s hand" % [build[0], at[0], case[0], ["right", "left"][hand]]
					if bool(case[2][hand]):
						least = minf(least, _relax_least(tips[hand]))
						thumb_far = maxf(thumb_far, float(caught["thumbs"][hand]))
						if _relax_least(tips[hand]) < RELAX_TIP_ALONG:
							tight.append("%s %.3f" % [where, _relax_least(tips[hand])])
					else:
						for k in 4:
							if absf(float(tips[hand][k]) - float(fist[hand][k])) > 0.001:
								moved.append("%s %.3f against %.3f" % [where, tips[hand][k], fist[hand][k]])
								break
		model.queue_free()
		holder.queue_free()
	print("  the empty hand's nearest tip at rest: %.3f m (floor %.2f)" % [least, RELAX_TIP_ALONG])
	_check(hooked.is_empty(), "with the relax off the check fails the hook: every hand's tips under %.2f m (%s)" % [RELAX_TIP_ALONG, ", ".join(hooked)])
	_check(tight.is_empty(), "an empty hand at rest eased open: every tip %.2f m or more out from the wrist, Idle and Walk, man and woman (%d: %s)" % [
		RELAX_TIP_ALONG, tight.size(), ", ".join(tight.slice(0, 6))])
	_check(thumb_far <= RELAX_THUMB_NEAR and thumb_hook > RELAX_THUMB_NEAR,
		"an empty hand's thumb lies in along the index, no pincer: its tip at most %.3f m off the index's line (within %.3f), the clip's thumb %.3f off with the relax off" % [
		thumb_far, RELAX_THUMB_NEAR, thumb_hook])
	_check(moved.is_empty(), "a hand holding, or working the other's bow, two-handed piece or tool, keeps the clip's fist within 1 mm (%d: %s)" % [
		moved.size(), ", ".join(moved.slice(0, 6))])
	var half := Client3D.hand_relax_step(Vector2.ZERO, Vector2(Client3D.HAND_RELAX, 0.0), Client3D.HAND_RELAX_EASE * 0.5)
	var whole := Client3D.hand_relax_step(Vector2.ZERO, Vector2(Client3D.HAND_RELAX, 0.0), Client3D.HAND_RELAX_EASE)
	var hitch := Client3D.hand_relax_step(Vector2(Client3D.HAND_RELAX, Client3D.HAND_RELAX), Vector2.ZERO, 2.0)
	_check(is_equal_approx(half.x, Client3D.HAND_RELAX * 0.5) and is_equal_approx(whole.x, Client3D.HAND_RELAX) and is_equal_approx(hitch.x, 0.0),
		"the share eases over %.2f s: half way at half the time (%.3f), whole at it (%.3f), a 2 s hitch shut (%.3f, %.3f)" % [
		Client3D.HAND_RELAX_EASE, half.x, whole.x, hitch.x, hitch.y])


## _test_hand_relax's: each finger's tip of [param side]'s hand from its wrist along the hand.
static func _relax_tips(skeleton: Skeleton3D, side: String) -> Array:
	var hand := skeleton.get_bone_global_pose(skeleton.find_bone(side + "Hand"))
	var out := []
	for finger in ["Index", "Middle", "Ring", "Little"]:
		var mid := skeleton.get_bone_global_pose(skeleton.find_bone(side + finger + "Intermediate")).origin
		var tip := skeleton.get_bone_global_pose(skeleton.find_bone(side + finger + "Distal")).origin
		out.append((hand.affine_inverse() * (tip + (tip - mid))).y)
	return out


## _test_hand_relax's: the thumb's tip of [param side]'s hand (its last joint carried on as far again as
## its last segment) from the index finger's line, its first knuckle to its tip.
static func _relax_thumb(skeleton: Skeleton3D, side: String) -> float:
	var at := func(bone: String) -> Vector3: return skeleton.get_bone_global_pose(skeleton.find_bone(side + bone)).origin
	var near: Vector3 = at.call("ThumbProximal")
	var last: Vector3 = at.call("ThumbDistal")
	var tip := last + (last - near)
	var knuckle: Vector3 = at.call("IndexProximal")
	var mid: Vector3 = at.call("IndexIntermediate")
	var end: Vector3 = at.call("IndexDistal")
	var line := end + (end - mid) - knuckle
	var u := clampf((tip - knuckle).dot(line) / line.length_squared(), 0.0, 1.0)
	return tip.distance_to(knuckle + line * u)


static func _relax_least(tips: Array) -> float:
	var least := INF
	for along: float in tips:
		least = minf(least, along)
	return least


## The people's jog held up (Jeff, 11-11: "the walk looks like skipping"; every player in motion plays
## the jog): People_Jog_Short's hips-to-head line pitched forward PEOPLE_JOG_LEAN_LEAST to _MOST degrees
## on the cycle's mean (Jog_Short's 24 to 29 at JOG_LEAN_STOCK or more; 977 moved the band up from 12 to 18 with
## the run's lean from the feet, the trunk's own band in _test_run_body), at no sample past
## PEOPLE_JOG_LEAN_PEAK, the head tipped within PEOPLE_JOG_HEAD of Idle's; its length Jog_Short's, its feet
## where Jog_Short's fall but no toe under Walk's floor, its hips' rise at most PEOPLE_JOG_BOB_MOST (Jog_Short's
## 0.23 m), its hands as high over the hips as Jog_Short's and under the shoulder; a person's rig plays
## it for "Jog_Short" and reads it so, a body with no people's stance plays Jog_Short. Read off the
## tracks on the bone chain (8 samples a cycle), man and woman.
const PEOPLE_JOG_LEAN_LEAST := 18.0
const PEOPLE_JOG_LEAN_MOST := 23.0
const PEOPLE_JOG_LEAN_PEAK := 26.0
const JOG_LEAN_STOCK := 22.0
const PEOPLE_JOG_HEAD := 5.0
const PEOPLE_JOG_FEET := 0.04
const PEOPLE_JOG_UNDER := 0.005
const PEOPLE_JOG_ACROSS := 0.03
const PEOPLE_JOG_BOB_MOST := 0.15
## The stride row (Jeff, 11-11: "the walk looks like skipping"; the coordinator's (b), 11-16: the skip was the
## hang): every key of Jog_Short's kept (its length), the planted toe's pace within PEOPLE_JOG_PACE m/s of the gait
## table's (Client3D.HUMAN_GAITS: no slide at the pace it is played at), a step of PEOPLE_JOG_STEP_LEAST m or more
## at a player's 4 m/s, in the air at most PEOPLE_JOG_HANG_MOST s a step there (953: 0.263), each foot down
## PEOPLE_JOG_STANCE_LEAST of a step or more and the two within PEOPLE_JOG_EVEN of a step of each other (no limp),
## the hips' top at most PEOPLE_JOG_TOP of standing (Idle's). A foot is down while the lower of its toe and its
## ankle, from rest, is within 2 cm of the clip's lowest (_jog_stride).
const PEOPLE_JOG_PACE := 0.1
const PEOPLE_JOG_STEP_LEAST := 1.48
const PEOPLE_JOG_HANG_MOST := 0.175
const PEOPLE_JOG_STANCE_LEAST := 0.5
const PEOPLE_JOG_EVEN := 0.12
const PEOPLE_JOG_TOP := 1.05


## The gaits' starts and stances (Client3D.GAIT_STARTS, GAIT_STANCES; the coordinator's ruling on ui-design's
## hops, 11-16), on the man and the woman: inside each foot's stance span (STANCE_SAMPLES across it, its ends
## too) that foot's sole (the lower of its toe's and its ankle's height over their rest) within STANCE_SOLE of the
## ground; at a start's share the right foot down and the left off the ground (it leads), both feet together
## within START_NEAR m of where Idle has them over the ground and nearer than half a cycle on (the right leading).
const STANCE_SAMPLES := 8
const STANCE_SOLE := 0.03
const START_NEAR := 0.25
func _test_gait_phases() -> void:
	print("== the gaits' starts and stances ==")
	var lib := load(CLIPS) as AnimationLibrary
	var bad: Array[String] = []
	var starts: Array[String] = []
	for build: Array in [["man", "res://art/models/characters/human_m.glb"], ["woman", "res://art/models/characters/human_f.glb"]]:
		var model := (load(build[1]) as PackedScene).instantiate() as Node3D
		add_child(model)
		var rig := AnimRig.make(model, lib, 0.0, true, null)
		var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var toes := [skeleton.find_bone("LeftToes"), skeleton.find_bone("RightToes")]
		var feet := [skeleton.find_bone("LeftFoot"), skeleton.find_bone("RightFoot")]
		var read := func(clip: String, share: float) -> Array:
			rig.base_at(clip, share * lib.get_animation(clip).length)
			await _frames(2)
			var out := []
			for s in 2:
				var toe := skeleton.get_bone_global_pose(toes[s]).origin
				var foot := skeleton.get_bone_global_pose(feet[s]).origin
				out.append([minf(toe.y - skeleton.get_bone_global_rest(toes[s]).origin.y, foot.y - skeleton.get_bone_global_rest(feet[s]).origin.y), Vector2(foot.x, foot.z)])
			return out
		var idle: Array = await read.call("Idle", 0.0)
		for clip: String in Client3D.GAIT_STANCES:
			if not lib.has_animation(clip):
				bad.append("%s: no clip" % clip)
				continue
			var spans: Array = Client3D.GAIT_STANCES[clip]
			for s in 2:
				var from := float(spans[s][0])
				var span := fposmod(float(spans[s][1]) - from, 1.0)
				for k in STANCE_SAMPLES + 1:
					var share := fposmod(from + span * k / STANCE_SAMPLES, 1.0)
					var got: Array = await read.call(clip, share)
					if float(got[s][0]) > STANCE_SOLE:
						bad.append("%s %s: the %s sole %.3f m up at %.3f" % [build[0], clip, ["left", "right"][s], got[s][0], share])
		for clip: String in Client3D.GAIT_STARTS:
			var share := float(Client3D.GAIT_STARTS[clip])
			var got: Array = await read.call(clip, share)
			var mirror: Array = await read.call(clip, fposmod(share + 0.5, 1.0))
			var near := (got[0][1] as Vector2).distance_to(idle[0][1]) + (got[1][1] as Vector2).distance_to(idle[1][1])
			var other := (mirror[0][1] as Vector2).distance_to(idle[0][1]) + (mirror[1][1] as Vector2).distance_to(idle[1][1])
			starts.append("%s %s %.3f m (half a cycle on %.3f)" % [build[0], clip, near, other])
			if float(got[1][0]) > STANCE_SOLE or float(got[0][0]) <= 0.02 or near > START_NEAR or near >= other:
				bad.append("%s %s's start at %.3f: right sole %.3f, left %.3f, feet %.3f m from Idle's (half a cycle on %.3f)" % [
					build[0], clip, share, got[1][0], got[0][0], near, other])
		model.queue_free()
	print("  starts, both feet from Idle's: %s" % ", ".join(starts))
	_check(bad.is_empty(), "every stance span's foot down within %.2f m on both bodies, every start the right foot down and the left leading, its feet within %.2f m of Idle's (%s)" % [
		STANCE_SOLE, START_NEAR, "; ".join(bad.slice(0, 6))])


## 869 amended (4): a change of gait keeps the foot (ui-design's run977, L R L R R L after a burst: the new clip began
## at a random point of its cycle). Each body's gaits as it plays them, every foot's touchdowns read from its sole
## (SWITCH_SAMPLES a cycle; down when the sole falls under a quarter of its range): each foot lands once a cycle (the
## read's own check). From SWITCH_SHARES points of each gait, switched up and down to its neighbour (Client3D.switch_at),
## the foot that lands next is the one that would have: L R L R across the switch. A point within SWITCH_NEAR of a
## landing is left out (there the foot is landing, either clip's next is a matter of a sample). A crowd's spread phases
## stay spread (no two of SWITCH_CROWD within SWITCH_CROWD_GAP of a cycle). A random seek's share of wrong feet printed.
const SWITCH_SAMPLES := 48
const SWITCH_SHARES := 32
const SWITCH_NEAR := 0.07
const SWITCH_CROWD := 8
const SWITCH_CROWD_GAP := 0.04
func _test_gait_switch_feet() -> void:
	print("== a change of gait keeps the foot ==")
	var lib := load(CLIPS) as AnimationLibrary
	var bad: Array[String] = []
	var read: Array[String] = []
	var crowd_gap := 1.0
	for build: Array in [["man", "res://art/models/characters/human_m.glb", Client3D.HUMAN_GAITS, true],
			["woman", "res://art/models/characters/human_f.glb", Client3D.HUMAN_F_GAITS, true],
			["goblin", SCENE, Client3D.GAITS, false],
			["skeleton", "res://art/kit/creatures/creature.skeleton/creature.skeleton.glb", Client3D.DEAD_GAITS, false]]:
		var model := (load(build[1]) as PackedScene).instantiate() as Node3D
		add_child(model)
		var rig := AnimRig.make(model, lib, 0.0, true, null)
		if build[3]:
			rig.stood_as = Client3D.PEOPLE_PREFIX
		var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var toes := [sk.find_bone("LeftToes"), sk.find_bone("RightToes")]
		var feet := [sk.find_bone("LeftFoot"), sk.find_bone("RightFoot")]
		var gaits: Array = (Client3D.paced(build[2]) as Array).map(func(gait: Array) -> String: return str(gait[0]))
		# Each gait's touchdowns, [left shares, right shares].
		var lands := {}
		for clip: String in gaits:
			var length := rig.length(clip)
			if length <= 0.0:
				bad.append("%s: no %s" % [build[0], clip])
				continue
			var soles := [[], []]
			for k in SWITCH_SAMPLES:
				rig.base_at(clip, float(k) / SWITCH_SAMPLES * length)
				await _frames(2)
				for s in 2:
					var toe := sk.get_bone_global_pose(toes[s]).origin.y - sk.get_bone_global_rest(toes[s]).origin.y
					var foot := sk.get_bone_global_pose(feet[s]).origin.y - sk.get_bone_global_rest(feet[s]).origin.y
					soles[s].append(minf(toe, foot))
			var both := [[], []]
			for s in 2:
				var low: float = soles[s].min()
				var line: float = low + (float(soles[s].max()) - low) * 0.25
				for k in SWITCH_SAMPLES:
					if float(soles[s][k]) <= line and float(soles[s][k - 1]) > line:
						both[s].append(float(k) / SWITCH_SAMPLES)
				if both[s].size() != 1:
					bad.append("%s %s: the %s foot lands %d times a cycle %s" % [build[0], clip, ["left", "right"][s], both[s].size(), both[s]])
			lands[clip] = both
			read.append("%s %s %s" % [build[0], rig.as_played(clip), both])
		# The foot landing next after [param share] of [param clip] (0 left, 1 right), and how near a landing it is.
		var next_foot := func(clip: String, share: float) -> Array:
			var best := [-1, 2.0, 2.0]
			for s in 2:
				for at: float in lands[clip][s]:
					var ahead := fposmod(at - share, 1.0)
					var near := minf(ahead, 1.0 - ahead)
					if ahead < best[1]:
						best = [s, ahead, best[2]]
					best[2] = minf(best[2], near)
			return best
		var kept := 0
		var tried := 0
		var random_wrong := 0.0
		for i in range(gaits.size() - 1):
			for pair: Array in [[gaits[i], gaits[i + 1]], [gaits[i + 1], gaits[i]]]:
				if not lands.has(pair[0]) or not lands.has(pair[1]):
					continue
				var to_length := rig.length(pair[1])
				var wrong: Array[String] = []
				for k in SWITCH_SHARES:
					var share := (k + 0.5) / SWITCH_SHARES
					var was: Array = next_foot.call(pair[0], share)
					if float(was[2]) < SWITCH_NEAR:
						continue
					rig.base_at(pair[0], share * rig.length(pair[0]))
					var t := Client3D.switch_at(rig, pair[0], pair[1])
					var now: Array = next_foot.call(pair[1], fposmod(t / to_length, 1.0))
					tried += 1
					if t >= 0.0 and int(now[0]) == int(was[0]):
						kept += 1
					else:
						wrong.append("%.2f->%.2f" % [share, t / to_length])
					var other := 0
					for r in SWITCH_SHARES:
						other += 1 if int(next_foot.call(pair[1], (r + 0.5) / SWITCH_SHARES)[0]) != int(was[0]) else 0
					random_wrong += float(other) / SWITCH_SHARES
				if not wrong.is_empty():
					bad.append("%s %s to %s: the other foot next at %s" % [build[0], pair[0], pair[1], ", ".join(wrong.slice(0, 4))])
		read.append("%s: %d of %d switches keep the foot (a random seek: %.0f%% the wrong foot)" % [build[0], kept, tried, 100.0 * random_wrong / maxf(tried, 1)])
		# A crowd jogging out of step, all switched up together: still out of step.
		if gaits.size() >= 3:
			var shares: Array[float] = []
			for k in SWITCH_CROWD:
				rig.base_at(gaits[1], float(k) / SWITCH_CROWD * rig.length(gaits[1]))
				shares.append(fposmod(Client3D.switch_at(rig, gaits[1], gaits[2]) / rig.length(gaits[2]), 1.0))
			shares.sort()
			for k in SWITCH_CROWD:
				crowd_gap = minf(crowd_gap, fposmod(shares[(k + 1) % SWITCH_CROWD] - shares[k], 1.0))
		model.queue_free()
	print("  %s" % "\n  ".join(read))
	_check(bad.is_empty() and crowd_gap >= SWITCH_CROWD_GAP,
			"walk to jog, jog to sprint and back keep L R L R on the man, the woman, the goblin and the skeleton; a crowd's spread phases stay %.3f apart at least (%s)" % [
			crowd_gap, "; ".join(bad.slice(0, 6))])


## The people's run arms (Jeff on v0.1.226: "the running animation, the arms swinging left to right together is
## incorrect. it needs a rework stat"; the coordinator's terms, 11-16). The pack's jog twisted the shoulders on the hips
## 88 degrees a cycle (People_Jog_Short), carrying both hands 0.24 m across the body together, held high and ahead (up
## to 0.30 m over the hips' head, 0.52 m before it); its sprint never took a hand behind the hip. Read in the root's
## heading frame on the man and the woman, RUN_ARM_SAMPLES across each clip, each hand from the hips' head: it travels
## RUN_HAND_TRAVEL fore and aft or more, moves RUN_HAND_SIDE across at most and keeps RUN_HAND_MIDLINE off the middle,
## and pumps astride the hip, not ahead of it (the coordinator, 11-16: "it is done when the hands pump"): its path's
## back behind the hips' head (by its band, below), its front RUN_HAND_AHEAD at most before it, at the back no
## higher than RUN_HAND_BACK_UP over it, and never over the bottom of the ribs (the Chest bone's rest height over the
## Hips', read straight up). The jog's path is read so in the heading frame and in its trunk's (fore-aft square to the
## hips-to-shoulders line, its mean over the cycle, and up along it), the sprint's in its trunk's alone (its shoulders
## lead its hips 0.28 m: a sprinter's hand behind the hip is behind the leaning back, at that back's hip). The hands opposite each other (r at most RUN_HANDS_R) and each opposite its own
## foot (RUN_FOOT_R); the shoulders' line on the hips' and on the heading, RUN_TWIST degrees of range at most; the head's
## yaw on the heading RUN_HEAD at most. People_Sprint_Short's legs are Sprint_Short's (the foes keep that), within 1 mm.
## 977 (Jeff on v0.1.230: "the arms swing backwards too far ... its not just arms and legs moving"; the coordinator's
## terms, 11-17): the back of the path a band, not a floor, RUN_JOG_BEHIND in the jog's heading frame and
## RUN_SPRINT_BEHIND in the sprint's trunk frame (the coaching rule's "just behind the top of the hip"; the pack's own
## jog 0.16); the elbow never opened past RUN_JOG_ELBOW / RUN_SPRINT_ELBOW of bend (the straight arm flung back was
## the "too far"); the jog's pelvis turning with its legs, its yaw's range RUN_PELVIS_YAW (not rigid: 1 degree was the
## post; capped short of a twist); the shoulders' roll on the heading RUN_JOG_ROLL / RUN_SPRINT_ROLL at most (the
## sprint's 47 was a see-saw); the shoulders on the heading RUN_ON_HEADING at most.
const RUN_ARM_SAMPLES := 48
const RUN_HAND_TRAVEL := 0.32
const RUN_JOG_BEHIND := Vector2(0.06, 0.14)
const RUN_SPRINT_BEHIND := Vector2(0.10, 0.18)
const RUN_JOG_ELBOW := 70.0
const RUN_SPRINT_ELBOW := 50.0
const RUN_PELVIS_YAW := Vector2(5.0, 16.0)
const RUN_JOG_ROLL := 12.0
const RUN_SPRINT_ROLL := 20.0
const RUN_ON_HEADING := 18.0
const RUN_HAND_AHEAD := 0.30
const RUN_HAND_BACK_UP := 0.20
const RUN_HAND_SIDE := 0.10
const RUN_HAND_MIDLINE := 0.12
const RUN_HANDS_R := -0.9
const RUN_FOOT_R := -0.8
const RUN_TWIST := 30.0
const RUN_HEAD := 3.0
## A reached two-hander carried at the run (451 amended (13), TASK 16; Jeff's v0.1.213 report, "running with axe, chars
## left arm clips into head, and wrist bends at non anatomic angle"): the man's and the woman's rig in the people's stance,
## each of REACHED_TWO in hand and its left hand reaching grip_2, Jog_Short and Sprint_Short each at HELD_STEPS times a
## loop, read with Axe_Carry on the carry layer and with it off (main's arms). Carried: both wrists within
## HELD_WRIST_BEND (twist HELD_WRIST_TWIST) on every sample, the left hand's root and the left elbow at least
## CARRY_HEAD_CLEAR from the Head bone's root, and every bone but the arms' (POSTURE_ARM_BONES) where it is without the
## carry (CARRY_BODY_SAME): the legs, the trunk's lean and twist and the head are the run's. The bounds are
## C:/dev/review/animation/axe_run/carry_table.md's (measured on the skinned mesh, 11-25): the carried left wrist 44 to
## 50 degrees, twist 39 to 44 (main 99 to 113, over 60 on 35 to 48 frames of 48), the right 33, twist 31; every part
## of the left arm 0.24 m or more off the head's mesh (main 1 to 7 mm); the lean the gait's to a tenth of a degree.
## CARRY_HEAD_CLEAR is that clearance read at the bones as drawn (_carry_head_gap: the head's centre to the forearm's and
## the hand's segments), set from this row's own first reading, 11-25: carried 0.391 to 0.466 m, main 0.054 to 0.148 (the
## hand at the face); the row's second check holds main's under it, so the bound tells the two apart.
const CARRY_HEAD_CLEAR := 0.30
const CARRY_BODY_SAME := 0.001
func _test_carry_two() -> void:
	print("== a two-hander carried at the run: the wrists in range, the left arm off the head, the body the run's ==")
	var lib := load(CLIPS) as AnimationLibrary
	var vary_was := AnimRig.vary_on
	AnimRig.vary_on = false
	var off: Array[String] = []
	var read: Array[String] = []
	var main_reads: Array[String] = []
	var least_main := INF
	for build: Array in [["man", "res://art/models/characters/human_m.glb"], ["woman", "res://art/models/characters/human_f.glb"]]:
		for kind: String in REACHED_TWO:
			var model := (load(build[1]) as PackedScene).instantiate() as Node3D
			add_child(model)
			var holder := Node3D.new()
			add_child(holder)
			Client3D._attach_sockets(model, Client3D.HUMAN_SOCKETS, 1.0, holder)
			var sockets: Dictionary = holder.get_meta("sockets")
			var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
			var art := str(Items.def(kind).get("art", "item." + kind))
			var piece := ArtKit.instance(art)
			piece.name = "Held"
			if Client3D._edge_first(kind):
				piece.basis = Client3D.HELD_EDGE_TURN
			Client3D._grip_at(piece, art)
			(sockets["hand_r"] as Node3D).add_child(piece)
			var reach := HandReach.make(sk, (sockets["hand_r"] as Node3D).transform, (sockets["hand_l"] as Node3D).transform)
			Client3D._sync_reach(reach, sockets, [kind, ""])
			var at := {}
			for bone: String in ["LeftLowerArm", "LeftHand", "RightLowerArm", "RightHand", "LeftMiddleProximal", "Head"]:
				var on := BoneAttachment3D.new()
				on.bone_name = bone
				sk.add_child(on)
				at[bone] = on
			var rig := AnimRig.make(model, lib, 0.0, true, null)
			rig.stood_as = Client3D.PEOPLE_PREFIX
			rig.set_process(false)
			var still: Array[int] = []
			for b in sk.get_bone_count():
				if sk.get_bone_name(b) not in AnimRig.POSTURE_ARM_BONES and not _carry_under(sk, b, "LeftHand") and not _carry_under(sk, b, "RightHand"):
					still.append(b)
			for gait: String in ["Jog_Short", "Sprint_Short"]:
				var length := rig.length(gait)
				# [carried, main]: right bend, right twist, left bend, left twist, least clearance, and the body's most moved
				var most := [[0.0, 0.0, 0.0, 0.0, INF, 0.0], [0.0, 0.0, 0.0, 0.0, INF, 0.0]]
				for i in HELD_STEPS:
					var t := length * float(i) / HELD_STEPS
					var bodies := []
					for k in 2:
						rig.carry(str(Client3D.HUMANOID_MOVES["carry_two"]) if k == 0 else "", 0.0)
						rig.base_at(gait, t)
						await _frames(3)
						var m: Array = most[k]
						var wr := _wrist_turn(sk, at, "Right")
						var wl := _wrist_turn(sk, at, "Left")
						m[0] = maxf(m[0], wr.x)
						m[1] = maxf(m[1], absf(wr.y))
						m[2] = maxf(m[2], wl.x)
						m[3] = maxf(m[3], absf(wl.y))
						m[4] = minf(m[4], _carry_head_gap(at))
						var places := []
						for b in still:
							places.append(sk.get_bone_global_pose(b).origin)
						bodies.append(places)
					for j in still.size():
						most[0][5] = maxf(most[0][5], (bodies[0][j] as Vector3).distance_to(bodies[1][j]))
				var c: Array = most[0]
				var o: Array = most[1]
				read.append("%s %s %s: right %.0f/%.0f, left %.0f/%.0f, left forearm and hand %.3f m off the head's centre, body moved %.4f m" % [
					build[0], kind, gait, c[0], c[1], c[2], c[3], c[4], c[5]])
				main_reads.append("%s %s %s: right %.0f/%.0f, left %.0f/%.0f, left forearm and hand %.3f m" % [build[0], kind, gait, o[0], o[1], o[2], o[3], o[4]])
				least_main = minf(least_main, o[4])
				if not reach.active or c[0] > HELD_WRIST_BEND or c[1] > HELD_WRIST_TWIST or c[2] > HELD_WRIST_BEND or c[3] > HELD_WRIST_TWIST \
						or c[4] < CARRY_HEAD_CLEAR or c[5] > CARRY_BODY_SAME:
					off.append(read[-1] + ("" if reach.active else " (the left hand not reaching)"))
			model.queue_free()
			holder.queue_free()
			await _frames(1)
	AnimRig.vary_on = vary_was
	for line in read:
		print("  carried ", line)
	for line in main_reads:
		print("  main's  ", line)
	_check(off.is_empty() and read.size() == 2 * REACHED_TWO.size() * 2,
		"each two-hander carried at the jog and the sprint, both bodies: wrists within %.0f deg (twist %.0f), the left forearm and hand %.2f m or more off the head's centre, the body as without it (%s)" % [
		HELD_WRIST_BEND, HELD_WRIST_TWIST, CARRY_HEAD_CLEAR, "; ".join(off)])
	# The clearance is a watch only if main's arm, which went into the face, reads inside it.
	_check(least_main < CARRY_HEAD_CLEAR, "main's run (no carry) reads the left arm inside the bound: %.3f m against %.2f" % [least_main, CARRY_HEAD_CLEAR])


## The carried two-hander as the low camera sees it (451 amended (13), TASK 16; the coordinator's Lenovo strip of
## 1d3acca3f: side on, the weapon's head level with the face): the man's and the woman's rig in the people's stance,
## each of REACHED_TWO in hand and its left hand reaching grip_2, each of CARRY_VIEW_RUNS (a clip, the carry's share,
## the stand's ready's share on the upper layer) at CARRY_VIEW_STEPS times a loop, read by tests/carry_view.gd: the
## piece's whole mesh against the head's skinned mesh drawn through the low camera at the nearest zoom from each side,
## each quarter, the front and the back, their outlines' overlap (cm2). Carried in full (the walk, the jog, the
## sprint): none in any view, the piece's top CARRY_VIEW_CHIN or more under the chin and its head part's top
## CARRY_VIEW_SHOULDER or more under the shoulder line. Part way, the stop as Client3D plays it (the carry held while
## the legs settle, eased out over the stand's bare arms, then the ready eased in over them): none from either side or
## quarter (CARRY_VIEW_PART), the coordinator's (3), the ready's in-between no more than the ready's own in full (read
## too, the stand as shipped). The bounds are the reworked pose's own readings
## (C:/dev/review/animation/axe_run/carry_view_table.md); main's jog (no carry) is read as a full carry and must break
## them, so the row tells the two apart.
const CARRY_VIEW_STEPS := 8
const CARRY_VIEW_RUNS := [["Jog_Short", 1.0, 0.0], ["Sprint_Short", 1.0, 0.0], ["Walk", 1.0, 0.0],
	["Idle", 0.75, 0.0], ["Idle", 0.5, 0.0], ["Idle", 0.25, 0.0], ["Idle", 0.0, 0.25], ["Idle", 0.0, 0.5], ["Idle", 0.0, 0.75]]
const CARRY_VIEW_CHIN := 0.08
const CARRY_VIEW_SHOULDER := 0.0
const CARRY_VIEW_PART := ["L", "R", "FL", "FR", "BL", "BR"]
const CarryView := preload("res://tests/carry_view.gd")
func _test_carry_view() -> void:
	print("== a two-hander carried: clear of the head from every side at the low camera, under the chin and the shoulders ==")
	var lib := load(CLIPS) as AnimationLibrary
	var vary_was := AnimRig.vary_on
	AnimRig.vary_on = false
	var views := CarryView.views()
	var off: Array[String] = []
	var read: Array[String] = []
	var main_reads: Array[String] = []
	var main_breaks := 0
	var main_count := 0
	var count := 0
	for build: Array in [["man", "res://art/models/characters/human_m.glb"], ["woman", "res://art/models/characters/human_f.glb"]]:
		for kind: String in REACHED_TWO:
			var model := (load(build[1]) as PackedScene).instantiate() as Node3D
			add_child(model)
			var holder := Node3D.new()
			add_child(holder)
			Client3D._attach_sockets(model, Client3D.HUMAN_SOCKETS, 1.0, holder)
			var sockets: Dictionary = holder.get_meta("sockets")
			var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
			var art := str(Items.def(kind).get("art", "item." + kind))
			var piece := ArtKit.instance(art)
			piece.name = "Held"
			if Client3D._edge_first(kind):
				piece.basis = Client3D.HELD_EDGE_TURN
			Client3D._grip_at(piece, art)
			(sockets["hand_r"] as Node3D).add_child(piece)
			var reach := HandReach.make(sk, (sockets["hand_r"] as Node3D).transform, (sockets["hand_l"] as Node3D).transform)
			Client3D._sync_reach(reach, sockets, [kind, ""])
			var at := CarryView.attach(sk)
			var rig := AnimRig.make(model, lib, 0.0, true, null)
			rig.stood_as = Client3D.PEOPLE_PREFIX
			rig.set_process(false)
			await _frames(2)
			var head := CarryView.head_skin(model, sk)
			var pm := CarryView.piece_mesh(piece)
			# The stand as shipped first (the ready's own, the bound of its in-between), main's jog last.
			var runs: Array = [["Idle", 0.0, 1.0]]
			runs.append_array(CARRY_VIEW_RUNS)
			runs.append(["Jog_Short", 0.0, 0.0])
			var ready_own := {}
			for r: Array in runs:
				var clip := str(r[0])
				var share := float(r[1])
				var ready := float(r[2])
				if ready > 0.0:
					rig.upper(str(Client3D.HUMANOID_MOVES["ready"]))
				else:
					rig.upper_off()  # Client3D's _sync_bow plays the stand's ready only once the carry is out.
				rig.carry(str(Client3D.HUMANOID_MOVES["carry_two"]) if share > 0.0 else "", 0.0)
				rig._carry = share
				var length := rig.length(clip)
				var most := {"top_chin": -INF, "head_top_shoulders": -INF}
				var seen := {}
				for v: String in views:
					seen[v] = Vector3.ZERO
				for i in CARRY_VIEW_STEPS:
					rig.base_at(clip, length * float(i) / CARRY_VIEW_STEPS)
					rig.tree.set("parameters/carry/blend_amount", share)
					if ready > 0.0:
						rig.tree.set("parameters/upper/blend_amount", ready)
					rig.tree.advance(0.0)
					await _frames(3)
					var got := CarryView.read(model, sk, at, piece, head, pm, views)
					most["top_chin"] = maxf(most["top_chin"], got["top_chin"])
					most["head_top_shoulders"] = maxf(most["head_top_shoulders"], got["head_top_shoulders"])
					for v: String in views:
						seen[v] = (seen[v] as Vector3).max(got[v])
				var full := (share >= 1.0 or share == 0.0) and ready == 0.0
				var over: Array[String] = []
				var all: Array[String] = []
				for v: String in views:
					all.append("%s %.0f" % [v, seen[v].x])
					var allowed := float(ready_own.get(v, 0.0)) if ready > 0.0 else 0.0
					if (seen[v] as Vector3).x > allowed and (full or v in CARRY_VIEW_PART):
						over.append("%s %.0f (%.0f before, %.0f behind)" % [v, seen[v].x, seen[v].y, seen[v].z])
				var line := "%s %s %s carry %.2f ready %.2f: top %+.3f m on the chin, its head %+.3f m on the shoulders, overlapping the head %s [%s]" % [
					build[0], kind, clip, share, ready, most["top_chin"], most["head_top_shoulders"],
					", ".join(over) if not over.is_empty() else "in no view checked", " ".join(all)]
				var clear: bool = reach.active and over.is_empty() and (not full or most["top_chin"] <= -CARRY_VIEW_CHIN and most["head_top_shoulders"] <= -CARRY_VIEW_SHOULDER)
				if ready >= 1.0:
					for v: String in views:
						ready_own[v] = (seen[v] as Vector3).x
					main_reads.append("(the stand's ready) " + line)
				elif share > 0.0 or ready > 0.0:
					read.append(line)
					count += 1
					if not clear:
						off.append(line + ("" if reach.active else " (the left hand not reaching)"))
				else:
					main_reads.append(line)
					main_count += 1
					if not clear:
						main_breaks += 1
			model.queue_free()
			holder.queue_free()
			await _frames(1)
	AnimRig.vary_on = vary_was
	for line in read:
		print("  carried ", line)
	for line in main_reads:
		print("  main's  ", line)
	_check(off.is_empty() and count == 2 * REACHED_TWO.size() * CARRY_VIEW_RUNS.size(),
		"each two-hander carried, both bodies, %s: no overlap with the head at the low camera (in full from any side, quarter, the front or the back, the top %.2f m or more under the chin, its head %.2f m or more under the shoulders; part way from either side or quarter, the ready's in-between no more than its own) (%s)" % [
		", ".join(CARRY_VIEW_RUNS.map(func(r: Array) -> String: return "%s %.2f/%.2f" % [r[0], r[1], r[2]])), CARRY_VIEW_CHIN, CARRY_VIEW_SHOULDER, "; ".join(off)])
	# A watch only if main's jog, the carried weapon's head before the face, breaks it.
	_check(main_breaks == main_count and main_breaks > 0, "main's jog (no carry) breaks the bounds on every body and two-hander: %d of %d" % [main_breaks, main_count])


## The least distance from the head's centre (CARRY_HEAD_UP along the Head bone from its root) to the left forearm
## (elbow to wrist) and the hand (wrist to the middle finger's root), read at [param at]'s BoneAttachment3Ds: the pose
## as drawn, the reach's modifier in (get_bone_global_pose is the pose before it, the hand never at grip_2).
const CARRY_HEAD_UP := 0.09
static func _carry_head_gap(at: Dictionary) -> float:
	var head := at["Head"] as Node3D
	var centre := head.global_position + head.global_basis.y.normalized() * CARRY_HEAD_UP
	var least := INF
	for pair: Array in [["LeftLowerArm", "LeftHand"], ["LeftHand", "LeftMiddleProximal"]]:
		var a := (at[pair[0]] as Node3D).global_position
		var b := (at[pair[1]] as Node3D).global_position
		least = minf(least, Geometry3D.get_closest_point_to_segment(centre, a, b).distance_to(centre))
	return least


static func _carry_under(sk: Skeleton3D, b: int, top: String) -> bool:
	var t := sk.find_bone(top)
	b = sk.get_bone_parent(b)
	while b >= 0:
		if b == t:
			return true
		b = sk.get_bone_parent(b)
	return false


func _test_run_arms() -> void:
	print("== the people's run arms ==")
	var lib := load(CLIPS) as AnimationLibrary
	var bad: Array[String] = []
	var read: Array[String] = []
	# Read with the variation off (--no-vary's flag): a band is the clip's, never a random draw's (977 amended (1);
	# the variation's own row, _test_run_vary, reads the layer by its spread).
	var vary_was := AnimRig.vary_on
	AnimRig.vary_on = false
	for build: Array in [["man", "res://art/models/characters/human_m.glb"], ["woman", "res://art/models/characters/human_f.glb"]]:
		var model := (load(build[1]) as PackedScene).instantiate() as Node3D
		add_child(model)
		var rig := AnimRig.make(model, lib, 0.0, true, null)
		rig.stood_as = "People_"
		if rig.as_played("Sprint_Short") != "People_Sprint_Short" or rig.as_played("Jog_Short") != "People_Jog_Short":
			bad.append("%s plays %s and %s" % [build[0], rig.as_played("Jog_Short"), rig.as_played("Sprint_Short")])
		var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var at := func(n: String) -> Vector3: return sk.get_bone_global_pose(sk.find_bone(n)).origin
		var rest := func(n: String) -> Vector3: return sk.get_bone_global_rest(sk.find_bone(n)).origin
		var left: Vector3 = rest.call("LeftUpperLeg") - rest.call("RightUpperLeg")
		left = Vector3(left.x, 0.0, left.z).normalized()
		var fwd := Vector3.UP.cross(left).normalized()
		if (rest.call("LeftToes") - rest.call("LeftFoot")).dot(fwd) < 0.0:
			fwd = -fwd
		var head_bone := sk.find_bone("Head")
		var head_rest := sk.get_bone_global_rest(head_bone).basis
		var head_axis := 0
		for c in 3:
			if absf(head_rest[c].dot(fwd)) > absf(head_rest[head_axis].dot(fwd)):
				head_axis = c
		var head_sign := signf(head_rest[head_axis].dot(fwd))
		var yaw := func(v: Vector3) -> float: return atan2(v.dot(left), v.dot(fwd))
		var legs := {}
		for clip: String in ["People_Jog_Short", "People_Sprint_Short", "Sprint_Short"]:
			var length := lib.get_animation(clip).length
			var s := {}
			for k in ["Lf", "Ls", "Lu", "Rf", "Rs", "Ru", "Lb", "Rb", "Lfoot", "Rfoot", "twist", "on_heading", "head", "trunk", "pelvis", "roll"]:
				s[k] = []
			legs[clip] = []
			for i in RUN_ARM_SAMPLES:
				rig.base_at(clip, length * i / RUN_ARM_SAMPLES)
				await _frames(2)
				var hips: Vector3 = at.call("Hips")
				var shoulders: Vector3 = at.call("LeftUpperArm") - at.call("RightUpperArm")
				var thighs: Vector3 = at.call("LeftUpperLeg") - at.call("RightUpperLeg")
				s["twist"].append(rad_to_deg(angle_difference(yaw.call(thighs), yaw.call(shoulders))))
				s["on_heading"].append(rad_to_deg(angle_difference(yaw.call(left), yaw.call(shoulders))))
				s["head"].append(rad_to_deg(yaw.call(sk.get_bone_global_pose(head_bone).basis[head_axis] * head_sign)))
				s["pelvis"].append(rad_to_deg(yaw.call(thighs)))
				s["roll"].append(rad_to_deg(atan2(shoulders.y, shoulders.dot(left))))
				var trunk: Vector3 = (at.call("LeftUpperArm") + at.call("RightUpperArm")) * 0.5 - hips
				s["trunk"].append(Vector2(trunk.dot(fwd), trunk.y))
				for side in ["L", "R"]:
					var hand: Vector3 = at.call(("Left" if side == "L" else "Right") + "Hand") - hips
					s[side + "f"].append(hand.dot(fwd))
					s[side + "s"].append(hand.dot(left))
					s[side + "u"].append(hand.y)
					s[side + "foot"].append((at.call(("Left" if side == "L" else "Right") + "Foot") - hips).dot(fwd))
					var arm := "Left" if side == "L" else "Right"
					var upper: Vector3 = at.call(arm + "LowerArm") - at.call(arm + "UpperArm")
					s[side + "b"].append(rad_to_deg(upper.angle_to(at.call(arm + "Hand") - at.call(arm + "LowerArm"))))
				for bone in ["Hips", "LeftFoot", "RightFoot", "LeftToes", "RightToes"]:
					legs[clip].append(at.call(bone))
			if clip == "Sprint_Short":
				continue
			var span := func(a: Array) -> float: return a.max() - a.min()
			var lean := Vector2.ZERO
			for v: Vector2 in s["trunk"]:
				lean += v
			lean = lean.normalized()  # (fore, up) of the trunk's mean line; its fore-aft is square to it.
			var ribs: float = rest.call("Chest").y - rest.call("Hips").y
			for side in ["L", "R"]:
				var fore: Array = s[side + "f"]
				var across: Array = s[side + "s"]
				var up: Array = s[side + "u"]
				var in_trunk := []
				var trunk_up := []
				for i in fore.size():
					in_trunk.append(float(fore[i]) * lean.y - float(up[i]) * lean.x)
					trunk_up.append(float(fore[i]) * lean.x + float(up[i]) * lean.y)
				var back_up: float = up[fore.find(fore.min())]
				var trunk_back_up: float = trunk_up[in_trunk.find(in_trunk.min())]
				var off_middle: float = across.min() if side == "L" else -across.max()
				var jog := clip == "People_Jog_Short"
				var elbow: float = (s[side + "b"] as Array).min()
				read.append("%s %s %s: fore-aft %+.3f to %+.3f, up %+.3f to %+.3f (%+.3f at the back); in the trunk's frame %+.3f to %+.3f, up to %+.3f (%+.3f at the back); the ribs' bottom %+.3f; across %.3f, %.3f off the middle; elbow %.0f to %.0f" % [
					build[0], clip, side, fore.min(), fore.max(), up.min(), up.max(), back_up, in_trunk.min(), in_trunk.max(), trunk_up.max(), trunk_back_up, ribs, span.call(across), off_middle, elbow, (s[side + "b"] as Array).max()])
				# The back of the path: the jog's in the heading frame, the sprint's in its trunk's (977).
				var behind: float = -fore.min() if jog else -in_trunk.min()
				var band := RUN_JOG_BEHIND if jog else RUN_SPRINT_BEHIND
				var astride: bool = behind >= band.x and behind <= band.y and in_trunk.max() <= RUN_HAND_AHEAD and trunk_back_up <= RUN_HAND_BACK_UP and up.max() <= ribs
				if jog:
					astride = astride and fore.max() <= RUN_HAND_AHEAD and back_up <= RUN_HAND_BACK_UP
				if span.call(fore) < RUN_HAND_TRAVEL or not astride or span.call(across) > RUN_HAND_SIDE or off_middle < RUN_HAND_MIDLINE or elbow < (RUN_JOG_ELBOW if jog else RUN_SPRINT_ELBOW):
					bad.append("%s %s %s hand: fore-aft %+.3f to %+.3f m (trunk's %+.3f to %+.3f), %.3f behind, up to %+.3f (%+.3f at the back), across %.3f m, %.3f m off the middle, the elbow bent %.0f at least" % [
						build[0], clip, side, fore.min(), fore.max(), in_trunk.min(), in_trunk.max(), behind, up.max(), back_up, span.call(across), off_middle, elbow])
				var to_foot := _pearson(fore, s[side + "foot"])
				if to_foot > RUN_FOOT_R:
					bad.append("%s %s %s hand against its foot r %+.2f" % [build[0], clip, side, to_foot])
			var hands := _pearson(s["Lf"], s["Rf"])
			var jogging := clip == "People_Jog_Short"
			var pelvis: float = span.call(s["pelvis"])
			var roll: float = span.call(s["roll"])
			# The pelvis's band is the jog's: the sprint keeps Sprint_Short's legs (the 1 mm row), and its pelvis with them.
			var turning := not jogging or (pelvis >= RUN_PELVIS_YAW.x and pelvis <= RUN_PELVIS_YAW.y)
			if hands > RUN_HANDS_R or span.call(s["twist"]) > RUN_TWIST or span.call(s["on_heading"]) > RUN_ON_HEADING or span.call(s["head"]) > RUN_HEAD \
					or not turning or roll > (RUN_JOG_ROLL if jogging else RUN_SPRINT_ROLL):
				bad.append("%s %s: hands r %+.2f, twist %.0f, shoulders on the heading %.0f, head %.1f, pelvis yaw %.1f, shoulders' roll %.1f deg" % [
					build[0], clip, hands, span.call(s["twist"]), span.call(s["on_heading"]), span.call(s["head"]), pelvis, roll])
			read.append("%s %s: hands r %+.2f, twist %.1f, on the heading %.1f, head %.1f, pelvis yaw %.1f, shoulders' roll %.1f" % [
				build[0], clip, hands, span.call(s["twist"]), span.call(s["on_heading"]), span.call(s["head"]), pelvis, roll])
		var drift := 0.0
		for k in (legs["Sprint_Short"] as Array).size():
			drift = maxf(drift, ((legs["Sprint_Short"] as Array)[k] - (legs["People_Sprint_Short"] as Array)[k]).length())
		if drift > 0.001:
			bad.append("%s People_Sprint_Short's legs %.4f m off Sprint_Short's" % [build[0], drift])
		read.append("%s People_Sprint_Short's legs on Sprint_Short's within %.4f m" % [build[0], drift])
		model.queue_free()
	print("  " + "
  ".join(read))
	AnimRig.vary_on = vary_was
	_check(bad.is_empty(), "the people's jog and sprint: the hands pump fore and aft, past the hip, not across; the trunk and head steady (%s)" % ["; ".join(bad.slice(0, 6))])


## A posture's arms through a gait (953 amended (3); the residue of Jeff's v0.1.226 report: Rhea, slouched, ran with
## both hands drifting 0.11 m across together). Posture_Slouch and Posture_Stooped turn the clavicles in; AnimRig eases
## them (POSTURE_ARM_BONES) out through a gait and back in at rest. On the man and the woman, each posture: on Walk,
## Jog_Short and Sprint_Short each hand's across POSTURE_RUN_SIDE at most and the hands opposite fore and aft (r at
## most POSTURE_HANDS_R); the share 0 in a gait, eased there over the base's crossfade (no step over a frame's
## share of it, at 1/60 s); stood again after the run, every arm bone within POSTURE_STAND of a body that never ran.
## 977: the rest of the posture at AnimRig.POSTURE_GAIT_BODY in a gait and whole again at rest, so the run's lean is
## part of the bend, not on top of it: the man's jog's trunk (the hips to the shoulders' middle, its mean) within
## POSTURE_JOG_TRUNK degrees of v0.1.231's (POSTURE_JOG_TODAY: the posture whole, the run upright).
const POSTURE_JOG_TRUNK := 2.0
const POSTURE_JOG_TODAY := {"Posture_Stooped": 22.7, "Posture_Slouch": 16.2}
const POSTURE_RUN_SIDE := 0.06
const POSTURE_HANDS_R := -0.9
const POSTURE_STAND := 0.001
func _test_posture_arms() -> void:
	print("== a posture's arms through a gait ==")
	var lib := load(CLIPS) as AnimationLibrary
	var bad: Array[String] = []
	var read: Array[String] = []
	var arm_bones := ["LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand"]
	for build: Array in [["man", "res://art/models/characters/human_m.glb"], ["woman", "res://art/models/characters/human_f.glb"]]:
		for posture: String in ["Posture_Stooped", "Posture_Slouch"]:
			var bodies := []
			for k in 2:
				var model := (load(build[1]) as PackedScene).instantiate() as Node3D
				add_child(model)
				var rig := AnimRig.make(model, lib, 0.15, true, null)
				rig.stood_as = "People_"
				rig.gaits = PackedStringArray(["Walk", "Jog_Short", "Sprint_Short"])
				rig.posture(lib.get_animation(posture), 1.0)
				rig.loop("Idle", 1.0, 0.0, true)
				rig._process(0.0)
				bodies.append([model, rig, model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D])
			var rig: AnimRig = bodies[0][1]
			var sk: Skeleton3D = bodies[0][2]
			var rest := func(n: String) -> Vector3: return sk.get_bone_global_rest(sk.find_bone(n)).origin
			var left: Vector3 = rest.call("LeftUpperLeg") - rest.call("RightUpperLeg")
			left = Vector3(left.x, 0.0, left.z).normalized()
			var fwd := Vector3.UP.cross(left).normalized()
			if (rest.call("LeftToes") - rest.call("LeftFoot")).dot(fwd) < 0.0:
				fwd = -fwd
			# The ease: from Idle into the jog at 1/60 s, the share's steps.
			rig.loop("Jog_Short", 1.0)
			var step := 0.0
			var was := rig.posture_arms()
			var frames := 0
			while rig.posture_arms() > 0.0 and frames < 60:
				rig._process(1.0 / 60.0)
				step = maxf(step, was - rig.posture_arms())
				was = rig.posture_arms()
				frames += 1
			if rig.posture_arms() > 0.0 or step > 1.0 / (rig.blend * 60.0) + 0.001 or not is_equal_approx(rig.posture_body(), AnimRig.POSTURE_GAIT_BODY):
				bad.append("%s %s: the share %.2f after %d frames, its largest step %.3f, the body's share %.2f" % [build[0], posture, rig.posture_arms(), frames, step, rig.posture_body()])
			for clip: String in ["Walk", "Jog_Short", "Sprint_Short"]:
				rig.loop(clip, 1.0, 0.0)
				for k in 20:
					rig._process(1.0 / 60.0)
				var length := lib.get_animation(rig.as_played(clip)).length
				var s := {"Lf": [], "Ls": [], "Rf": [], "Rs": [], "trunk": []}
				for i in 48:
					rig.base_at(clip, length * i / 48.0)
					await _frames(2)
					var hips := sk.get_bone_global_pose(sk.find_bone("Hips")).origin
					var trunk := (sk.get_bone_global_pose(sk.find_bone("LeftUpperArm")).origin + sk.get_bone_global_pose(sk.find_bone("RightUpperArm")).origin) * 0.5 - hips
					s["trunk"].append(rad_to_deg(atan2(trunk.dot(fwd), trunk.y)))
					for side in ["L", "R"]:
						var h := sk.get_bone_global_pose(sk.find_bone(("Left" if side == "L" else "Right") + "Hand")).origin - hips
						s[side + "f"].append(h.dot(fwd))
						s[side + "s"].append(h.dot(left))
				var across: float = maxf(s["Ls"].max() - s["Ls"].min(), s["Rs"].max() - s["Rs"].min())
				var hands := _pearson(s["Lf"], s["Rf"])
				var trunk_mean: float = (s["trunk"] as Array).reduce(func(a: float, b: float) -> float: return a + b, 0.0) / (s["trunk"] as Array).size()
				read.append("%s %s %s: across %.3f, hands r %+.2f, sides r %+.2f, trunk %.1f" % [build[0], posture, clip, across, hands, _pearson(s["Ls"], s["Rs"]), trunk_mean])
				if across > POSTURE_RUN_SIDE or hands > POSTURE_HANDS_R:
					bad.append("%s %s %s: across %.3f m, hands r %+.2f" % [build[0], posture, clip, across, hands])
				if clip == "Jog_Short" and build[0] == "man" and absf(trunk_mean - float(POSTURE_JOG_TODAY[posture])) > POSTURE_JOG_TRUNK:
					bad.append("%s %s jog's trunk %.1f against v0.1.231's %.1f" % [build[0], posture, trunk_mean, POSTURE_JOG_TODAY[posture]])
			# Stood again: the share back to 1, the arms where a body that never ran holds them.
			rig.loop("Idle", 1.0, -1.0, true)
			for k in 30:
				rig._process(1.0 / 60.0)
			rig.base_at("Idle", 0.0)
			(bodies[1][1] as AnimRig).base_at("Idle", 0.0)
			await _frames(2)
			var off := 0.0
			for bone: String in arm_bones:
				off = maxf(off, sk.get_bone_global_pose(sk.find_bone(bone)).origin.distance_to((bodies[1][2] as Skeleton3D).get_bone_global_pose((bodies[1][2] as Skeleton3D).find_bone(bone)).origin))
			if not is_equal_approx(rig.posture_arms(), 1.0) or not is_equal_approx(rig.posture_body(), 1.0) or off > POSTURE_STAND:
				bad.append("%s %s stood again: the share %.2f, an arm bone %.4f m off a body that never ran" % [build[0], posture, rig.posture_arms(), off])
			read.append("%s %s stood again: arms %.5f m off" % [build[0], posture, off])
			for body: Array in bodies:
				(body[0] as Node3D).queue_free()
	print("  " + "
  ".join(read))
	_check(bad.is_empty(), "slouched and stooped, walking, jogging and sprinting: the hands opposite and beside the body; the shoulders' posture eased out and back, standing as it was (%s)" % ["; ".join(bad.slice(0, 6))])


static func _pearson(a: Array, b: Array) -> float:
	var n := a.size()
	var ma := 0.0
	var mb := 0.0
	for i in n:
		ma += float(a[i])
		mb += float(b[i])
	ma /= n
	mb /= n
	var va := 0.0
	var vb := 0.0
	var c := 0.0
	for i in n:
		va += (float(a[i]) - ma) ** 2
		vb += (float(b[i]) - mb) ** 2
		c += (float(a[i]) - ma) * (float(b[i]) - mb)
	return c / sqrt(va * vb) if va > 0.0 and vb > 0.0 else 0.0


func _test_people_jog() -> void:
	print("== the people's jog held up ==")
	var lib := load(CLIPS) as AnimationLibrary
	var people := Client3D.PEOPLE_PREFIX + JOG
	_check(lib.has_animation(people), "the library has %s" % people)
	if not lib.has_animation(people):
		return
	var stock := lib.get_animation(JOG)
	var held := lib.get_animation(people)
	_check(absf(held.length - stock.length) <= 0.5 / 24.0 and held.loop_mode == stock.loop_mode,
			"its length Jog_Short's, every key kept, a loop as Jog_Short is (%.3f / %.3f s)" % [held.length, stock.length])
	for build: Array in [SWORD_BUILDS[0], SWORD_BUILDS[4]]:
		var model := (load(build[1]) as PackedScene).instantiate() as Node3D
		var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var read := func(anim: Animation, t: float) -> Array:
			_jog_pose(skeleton, anim, t)
			var hips := _jog_global(skeleton, skeleton.find_bone("Hips"))
			var head := _jog_global(skeleton, skeleton.find_bone("Head"))
			var up := head.origin - hips.origin
			var face := head.basis.z
			return [rad_to_deg(atan2(up.z, up.y)), rad_to_deg(atan2(-face.y, Vector2(face.x, face.z).length()))]
		var lean := {}
		var tip := {}
		var peak := 0.0
		for clip: String in ["Idle", JOG, people]:
			var anim := lib.get_animation(clip)
			var leans := 0.0
			var tips := 0.0
			for i in 8:
				var got: Array = read.call(anim, anim.length * i / 8.0)
				leans += float(got[0]) / 8.0
				tips += float(got[1]) / 8.0
				if clip == people:
					peak = maxf(peak, float(got[0]))
			lean[clip] = leans
			tip[clip] = tips
		_check(lean[JOG] >= JOG_LEAN_STOCK and lean[people] >= PEOPLE_JOG_LEAN_LEAST and lean[people] <= PEOPLE_JOG_LEAN_MOST and peak <= PEOPLE_JOG_LEAN_PEAK,
				"%s: the jog pitched %.1f degrees forward on the mean, at most %.1f (Jog_Short %.1f, Idle %.1f)" % [build[0], lean[people], peak, lean[JOG], lean["Idle"]])
		_check(absf(float(tip[people]) - float(tip["Idle"])) <= PEOPLE_JOG_HEAD,
				"%s: the head tipped %.1f against Idle's %.1f (Jog_Short's %.1f)" % [build[0], tip[people], tip["Idle"], tip[JOG]])
		model.free()
	# The feet where Jog_Short puts them across the ground (side to side, at the same share of the cycle) but never under
	# Walk's floor (Jog_Short's toe sinks 5.6 cm for 0.15 s of each step, ui-design's jogA_3f76ef27e); the
	# hips' path near the same, their rise at most PEOPLE_JOG_BOB_MOST; each hand never over the shoulder (a back
	# held up takes the arms up with it: the coordinator, on jog_strip_ABC). Each hand's height had been held within
	# PEOPLE_JOG_HANDS of Jog_Short's (kept_hands); the run's arms (_test_run_arms) bring them down astride the hip.
	var model := (load(SWORD_BUILDS[0][1]) as PackedScene).instantiate() as Node3D
	var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var at := func(anim: Animation, t: float, bone: String) -> Vector3:
		_jog_pose(skeleton, anim, t)
		return _jog_global(skeleton, skeleton.find_bone(bone)).origin
	var walk := lib.get_animation("Walk")
	var walk_floor := INF
	for i in 32:
		for toe: String in ["LeftToes", "RightToes"]:
			walk_floor = minf(walk_floor, (at.call(walk, walk.length * i / 32.0, toe) as Vector3).y)
	var off: Array[String] = []
	var rise := [Vector2(INF, -INF), Vector2(INF, -INF)]
	var most := {"across": 0.0, "feet": 0.0, "under": -INF, "hands": 0.0, "over": -INF}
	for i in 32:
		var got := []
		for anim: Animation in [stock, held]:
			var t := anim.length * i / 32.0
			var bones := {}
			for bone: String in ["Hips", "LeftFoot", "RightFoot", "LeftToes", "RightToes", "LeftHand", "RightHand", "LeftUpperArm", "RightUpperArm"]:
				bones[bone] = at.call(anim, t, bone)
			got.append(bones)
		for side in 2:
			var h: Vector3 = got[side]["Hips"]
			rise[side] = Vector2(minf(rise[side].x, h.y), maxf(rise[side].y, h.y))
		var hips_a: Vector3 = got[0]["Hips"]
		var hips_b: Vector3 = got[1]["Hips"]
		most["across"] = maxf(most["across"], Vector2(hips_a.x, hips_a.z).distance_to(Vector2(hips_b.x, hips_b.z)))
		for foot: String in ["LeftFoot", "RightFoot"]:
			var fa: Vector3 = got[0][foot]
			var fb: Vector3 = got[1][foot]
			most["feet"] = maxf(most["feet"], absf(fa.x - fb.x))
		for toe: String in ["LeftToes", "RightToes"]:
			most["under"] = maxf(most["under"], walk_floor - (got[1][toe] as Vector3).y)
		var shoulder := minf((got[1]["LeftUpperArm"] as Vector3).y, (got[1]["RightUpperArm"] as Vector3).y)
		for hand: String in ["LeftHand", "RightHand"]:
			var over_a: float = (got[0][hand] as Vector3).y - hips_a.y
			var over_b: float = (got[1][hand] as Vector3).y - hips_b.y
			most["hands"] = maxf(most["hands"], absf(over_b - over_a))
			most["over"] = maxf(most["over"], (got[1][hand] as Vector3).y - shoulder)
	# The stride (_jog_stride): pace, no foot down, the planted knee's deepest fold; the hips' top over Idle's.
	var walked := {}
	for anim: Animation in [stock, held]:
		walked[anim] = _jog_stride(skeleton, anim)
	var standing: float = (at.call(lib.get_animation("Idle"), 0.0, "Hips") as Vector3).y
	model.free()
	var ours: Dictionary = walked[held]
	var theirs: Dictionary = walked[stock]
	var table := float(Client3D.HUMAN_GAITS[1][1])
	var played := 4.0 / table
	var step_s := held.length / 2.0 / played
	var hang := float(ours["flight"]) * held.length / played / 2.0
	var feet: Array = ours["stance"]
	var stance := [float(feet[0]) * 2.0, float(feet[1]) * 2.0]  # Each foot's share of the cycle, as a share of a step.
	_check(absf(float(ours["pace"]) - table) <= PEOPLE_JOG_PACE and 4.0 * step_s >= PEOPLE_JOG_STEP_LEAST and hang <= PEOPLE_JOG_HANG_MOST
			and minf(stance[0], stance[1]) >= PEOPLE_JOG_STANCE_LEAST and absf(stance[0] - stance[1]) <= PEOPLE_JOG_EVEN and rise[1].y <= standing * PEOPLE_JOG_TOP,
			"the stride: pace %.2f m/s (the table's %.2f; Jog_Short's own %.2f), at 4 m/s %.2f steps a second of %.2f m; in the air %.0f ms a step (Jog_Short at its 3.63: %.0f); each foot down %.0f%% and %.0f%% of a step; the planted knee at most %.0f degrees (%.0f); the hips' top %.0f%% of standing" % [
			ours["pace"], table, theirs["pace"], 1.0 / step_s, 4.0 * step_s, hang * 1000.0,
			float(theirs["flight"]) * stock.length / (4.0 / 3.63) / 2.0 * 1000.0, stance[0] * 100.0, stance[1] * 100.0, ours["knee"], theirs["knee"],
			rise[1].y / standing * 100.0])
	var bob: float = rise[1].y - rise[1].x
	if most["across"] > PEOPLE_JOG_ACROSS:
		off.append("the hips %.3f m off Jog_Short's path" % most["across"])
	if most["feet"] > PEOPLE_JOG_FEET:
		off.append("a foot %.3f m off Jog_Short's across the ground" % most["feet"])
	if most["under"] > PEOPLE_JOG_UNDER:
		off.append("a toe %.3f m under Walk's floor" % most["under"])
	if bob > PEOPLE_JOG_BOB_MOST:
		off.append("the hips rise %.3f m" % bob)
	_check(off.is_empty(), "its feet within %.3f m of Jog_Short's across the ground (%.3f), no toe under Walk's floor by more than %.3f (%.3f), the hips' path within %.3f (%.3f), their rise %.3f m against %.3f (%s)" % [
			PEOPLE_JOG_FEET, most["feet"], PEOPLE_JOG_UNDER, most["under"], PEOPLE_JOG_ACROSS, most["across"], bob, rise[0].y - rise[0].x, off])
	_check(most["over"] < 0.0, "each hand under the shoulder, the highest %.3f m under it (%.3f m off Jog_Short's height over the hips)" % [-float(most["over"]), most["hands"]])
	# Who plays it: a person's rig for "Jog_Short", read back as Jog_Short; a body without the stance, Jog_Short.
	var made := _sword_body(self, SWORD_BUILDS[0])
	var rig: AnimRig = made[2]
	rig.stood_as = Client3D.PEOPLE_PREFIX
	rig.loop(JOG)
	var person := [rig.as_played(JOG), rig.base_clip()]
	rig.stood_as = ""
	var plain := rig.as_played(JOG)
	(made[0] as Node3D).queue_free()
	(made[3] as Node3D).free()
	_check(person == [people, JOG] and plain == JOG, "a person plays %s for the jog and reads it as %s; no stance, %s" % [person[0], person[1], plain])


## The people's jog leans from its feet and runs with its whole body (977; Jeff on v0.1.230: "the body sits starkly
## spine straight upright, running adjust the center of gravity forward a little bit, its not just arms and legs
## moving"; the coordinator's terms, 11-17). People_Jog_Short on the man and the woman, RUN_BODY_SAMPLES across the
## cycle off its tracks: the trunk (the hips to the shoulders' middle) RUN_TRUNK degrees from upright on the mean
## (Teng & Powers at 3.4 m/s: 7.3 self-selected, 14.1 asked to lean; Jeff's "a little bit"; the pack's was 7.7); the
## centre of mass (Winter's segment shares) over each planted foot: at mid-stance its line from the ankle
## RUN_MID_STANCE degrees forward or more (7 was the post), at touchdown no more than RUN_TOUCHDOWN m behind the ankle
## (today's, v0.1.231: the foot no further ahead of the body than it was); the shoulders settling after the hips, their
## rise and fall RUN_SETTLE_MORE m over the hips' or more, and their height on the hips at its lowest RUN_SETTLE_LAG s
## or more after the hips' lowest (the trunk still settling once the hips have landed: the overlap a post lacks, the
## pack's moved as one); the head's pitch within RUN_HEAD_PITCH degrees over the cycle (the gaze
## steady while the trunk works). A foot is planted while its sole (the lower of its toe's and its ankle's height from
## rest) is within 2 cm of its own lowest; its stance the longest such run.
const RUN_BODY_SAMPLES := 96
const RUN_TRUNK := Vector2(11.0, 14.0)
const RUN_MID_STANCE := 9.0
const RUN_TOUCHDOWN := 0.27
const RUN_SETTLE_MORE := 0.005
const RUN_SETTLE_LAG := 0.5 / 24.0  # Half a key: the clip settles a key (42 ms) after; 96 samples read it 38. The fault is none.
const RUN_HEAD_PITCH := 3.0
const RUN_BODY_SEGMENTS := [[0.081, "Head", ""], [0.497, "Hips", "Neck"],
	[0.028, "LeftUpperArm", "LeftLowerArm"], [0.028, "RightUpperArm", "RightLowerArm"],
	[0.016, "LeftLowerArm", "LeftHand"], [0.016, "RightLowerArm", "RightHand"], [0.006, "LeftHand", ""], [0.006, "RightHand", ""],
	[0.100, "LeftUpperLeg", "LeftLowerLeg"], [0.100, "RightUpperLeg", "RightLowerLeg"],
	[0.0465, "LeftLowerLeg", "LeftFoot"], [0.0465, "RightLowerLeg", "RightFoot"],
	[0.0145, "LeftFoot", "LeftToes"], [0.0145, "RightFoot", "RightToes"]]
func _test_run_body() -> void:
	print("== the people's jog runs with its whole body ==")
	var lib := load(CLIPS) as AnimationLibrary
	var anim := lib.get_animation(Client3D.PEOPLE_PREFIX + JOG)
	var n := RUN_BODY_SAMPLES
	var alike: Array[String] = []
	for build: Array in [SWORD_BUILDS[0], SWORD_BUILDS[4]]:
		var model := (load(build[1]) as PackedScene).instantiate() as Node3D
		var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var rest := func(b: String) -> float: return sk.get_bone_global_rest(sk.find_bone(b)).origin.y
		var s := {}
		for k in ["trunk", "pitch", "hips", "shoulders", "com_f", "com_u", "Lsole", "Rsole", "Lankle", "Rankle", "Lground", "Rground"]:
			s[k] = []
		for i in n:
			_jog_pose(sk, anim, anim.length * i / n)
			var at := func(b: String) -> Vector3: return _jog_global(sk, sk.find_bone(b)).origin
			var hips: Vector3 = at.call("Hips")
			var shoulders: Vector3 = (at.call("LeftUpperArm") + at.call("RightUpperArm")) * 0.5
			var trunk := shoulders - hips
			s["trunk"].append(rad_to_deg(atan2(trunk.z, trunk.y)))
			var face := _jog_global(sk, sk.find_bone("Head")).basis.z
			s["pitch"].append(rad_to_deg(atan2(-face.y, Vector2(face.x, face.z).length())))
			s["hips"].append(hips.y)
			s["shoulders"].append(shoulders.y)
			var com := Vector3.ZERO
			var mass := 0.0
			for seg: Array in RUN_BODY_SEGMENTS:
				com += (at.call(seg[1]) if seg[2] == "" else (at.call(seg[1]) + at.call(seg[2])) * 0.5) * float(seg[0])
				mass += float(seg[0])
			com /= mass
			s["com_f"].append(com.z)
			s["com_u"].append(com.y)
			for side in ["L", "R"]:
				var foot: Vector3 = at.call(("Left" if side == "L" else "Right") + "Foot")
				var toe: Vector3 = at.call(("Left" if side == "L" else "Right") + "Toes")
				s[side + "sole"].append(minf(toe.y - rest.call("LeftToes"), foot.y - rest.call("LeftFoot")))
				s[side + "ankle"].append(foot.z)
				s[side + "ground"].append(minf(toe.y, foot.y))
		var mean := func(a: Array) -> float: return a.reduce(func(x: float, y: float) -> float: return x + y, 0.0) / a.size()
		var span := func(a: Array) -> float: return a.max() - a.min()
		var bad: Array[String] = []
		var trunk: float = mean.call(s["trunk"])
		if trunk < RUN_TRUNK.x or trunk > RUN_TRUNK.y:
			bad.append("the trunk %.1f" % trunk)
		var stances: Array[String] = []
		var feet := {}
		for side in ["L", "R"]:
			var soles: Array = s[side + "sole"]
			var down := []
			for i in n:
				down.append(float(soles[i]) <= soles.min() + 0.02)
			var best := [-1, 0]
			for i in n:
				if down[i] and not down[(i - 1 + n) % n]:
					var k := 0
					while down[(i + k) % n] and k < n:
						k += 1
					if k > best[1]:
						best = [i, k]
			if best[0] < 0:
				bad.append("%s foot never planted" % side)
				continue
			var ground: float = (s[side + "ground"] as Array).min()
			var line := func(i: int) -> Array:
				var ahead: float = float(s["com_f"][i]) - float(s[side + "ankle"][i])
				return [ahead, rad_to_deg(atan2(ahead, float(s["com_u"][i]) - ground))]
			var touch: Array = line.call(best[0])
			var mid: Array = line.call((best[0] + best[1] / 2) % n)
			stances.append("%s down %d of %d: touchdown %+.3f m (%.1f), mid %+.3f m (%.1f deg)" % [side, best[1], n, touch[0], touch[1], mid[0], mid[1]])
			if float(mid[1]) < RUN_MID_STANCE or float(touch[0]) < -RUN_TOUCHDOWN:
				bad.append("%s stance: touchdown %+.3f m, mid-stance %.1f deg" % [side, touch[0], mid[1]])
			feet[side] = {"from": best[0], "touch": touch, "mid": mid,
				"touch_on": line.call((best[0] + 1) % n), "mid_on": line.call((best[0] + best[1] / 2 + 1) % n)}
		# The two feet alike (977 amended: the left landed across the clip's seam, 2 cm up for a key, and read a
		# limp: touchdown 0.09 m nearer, mid-stance 4 degrees more than the right's): the left's landing half a cycle
		# from the right's within a sample, its touchdown's and mid-stance's place and angle each within what one
		# sample moves the right's (the measure's own spread).
		if feet.size() == 2:
			var apart: int = posmod(int(feet["L"]["from"]) - int(feet["R"]["from"]), n) - n / 2
			if absi(apart) > 1:
				alike.append("%s: the left lands %+d samples off half a cycle from the right" % [build[0], apart])
			for at: String in ["touch", "mid"]:
				for k in 2:
					var off: float = absf(float(feet["L"][at][k]) - float(feet["R"][at][k]))
					var spread: float = absf(float(feet["R"][at + "_on"][k]) - float(feet["R"][at][k]))
					if off > spread:
						alike.append("%s %s %s: left %.3f, right %.3f (a sample moves the right's %.3f)" % [
							build[0], at, ["place", "angle"][k], feet["L"][at][k], feet["R"][at][k], spread])
		# The settle: the shoulders' rise and fall over the hips', and at each step's landing the trunk still settling
		# after the hips have bottomed: the shoulders' height over the hips at its lowest after the hips' lowest (within a
		# quarter cycle of it, each step's; the mean of the two). The shoulders' own lowest can't show it: a centimetre's
		# settle on the hips' 8.5 cm moves the sum's lowest under 10 ms at any lag.
		var hips_up: float = span.call(s["hips"])
		var shoulders_up: float = span.call(s["shoulders"])
		var hips: Array = s["hips"]
		var shoulders := []
		for i in n:
			shoulders.append(float(s["shoulders"][i]) - float(hips[i]))
		var lags := []
		var first: int = hips.find(hips.min())
		for step in 2:
			var low := first
			if step == 1:
				for k in range(-n / 4, n / 4 + 1):
					if float(hips[(first + n / 2 + k + n) % n]) < float(hips[low]) or low == first:
						low = (first + n / 2 + k + n) % n
			var at := 0
			for k in range(-n / 4, n / 4 + 1):
				if float(shoulders[(low + k + n) % n]) < float(shoulders[(low + at + n) % n]):
					at = k
			lags.append(at * anim.length / n)
		var lag_s := (float(lags[0]) + float(lags[1])) * 0.5
		if shoulders_up < hips_up + RUN_SETTLE_MORE or lag_s < RUN_SETTLE_LAG - 0.0001:
			bad.append("the shoulders rise %.3f m against the hips' %.3f, settled lowest on them %.0f and %.0f ms after the hips' lowest" % [shoulders_up, hips_up, lags[0] * 1000.0, lags[1] * 1000.0])
		var pitch: float = span.call(s["pitch"])
		if pitch > RUN_HEAD_PITCH:
			bad.append("the head's pitch %.1f" % pitch)
		print("  %s: trunk %.1f to %.1f, mean %.1f deg; %s; up travel hips %.3f, shoulders %.3f m, settled lowest on the hips %.0f and %.0f ms after the hips' lowest; head pitch %.1f deg" % [
			build[0], (s["trunk"] as Array).min(), (s["trunk"] as Array).max(), trunk, "; ".join(stances), hips_up, shoulders_up, lags[0] * 1000.0, lags[1] * 1000.0, pitch])
		_check(bad.is_empty(), "%s: the jog leans from its feet, the body over the planted foot, the shoulders settling after the hips, the gaze steady (%s)" % [build[0], "; ".join(bad)])
		model.free()
	_check(alike.is_empty(), "the jog's two feet alike: the left lands half a cycle from the right, its touchdown and mid-stance where the right's are within a sample (%s)" % "; ".join(alike))


## The run varies stride to stride (977; Jeff, 11-17: "throwing in a some slight variation into movement so it's not
## just a strict loop"; the coordinator's terms: drawn only, the head's look yielding, a switch to turn it off). The man
## and the woman jog VARY_SECONDS at 1/60 s on two people's rigs started together, one with the layer (AnimRig.make's
## vary) and one without: every frame the legs (LEG_BONES and the hips) within VARY_LEGS of the plain body's, the trunk
## (the hips to the shoulders' middle) within VARY_LEAN degrees of its lean and the head's yaw within VARY_HEAD_YAW; each
## weight's step a frame no more than the ease's steepest (smoothstep's 1.5 times the even share of AnimRig.VARY_EASE of a
## step); "carry" spread at least VARY_SPREAD each way and "look" drawn VARY_LOOKS times or more, and both seen in the
## body (the lean's and the yaw's largest at least VARY_SEEN of their caps). Then: a look held (look_held 1) gives the
## look none; vary_on false eases both to 0 within the blend; stood at Idle, both 0.
const VARY_SECONDS := 30.0
const VARY_LEGS := 0.001
const VARY_LEAN := 1.5
const VARY_HEAD_YAW := 4.0
const VARY_SPREAD := 0.5
const VARY_LOOKS := 4
const VARY_SEEN := 0.5
func _test_run_vary() -> void:
	print("== the run varies stride to stride, drawn only ==")
	var lib := load(CLIPS) as AnimationLibrary
	var legs: Array[String] = ["Hips"]
	legs.append_array(AnimRig.LEG_BONES)
	for build: Array in [["man", "res://art/models/characters/human_m.glb"], ["woman", "res://art/models/characters/human_f.glb"]]:
		var bodies := []
		for vary in [true, false]:
			var model := (load(build[1]) as PackedScene).instantiate() as Node3D
			add_child(model)
			var rig := AnimRig.make(model, lib, 0.15, true, null, vary)
			rig.stood_as = "People_"
			rig.gaits = PackedStringArray(["Walk", "Jog_Short", "Sprint_Short"])
			rig.loop("Idle", 1.0, 0.0, true)
			rig._process(0.0)
			bodies.append([model, rig, model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D])
		var rig: AnimRig = bodies[0][1]
		var sk: Skeleton3D = bodies[0][2]
		var plain_sk: Skeleton3D = bodies[1][2]
		var bad: Array[String] = []
		if not rig.varies() or (bodies[1][1] as AnimRig).varies():
			bad.append("the layer on the vary rig %s, on the plain %s" % [rig.varies(), (bodies[1][1] as AnimRig).varies()])
		for body: Array in bodies:
			(body[1] as AnimRig).loop("Jog_Short", 1.0, 0.0, true)
		var step_s := lib.get_animation(rig.as_played("Jog_Short")).length / 2.0
		var steepest := 1.5 * 2.0 / (step_s * AnimRig.VARY_EASE * 60.0) + 0.0001
		var g := func(k: Skeleton3D, b: String) -> Transform3D: return k.get_bone_global_pose(k.find_bone(b))
		var trunk := func(k: Skeleton3D) -> float:
			var t: Vector3 = (g.call(k, "LeftUpperArm").origin + g.call(k, "RightUpperArm").origin) * 0.5 - g.call(k, "Hips").origin
			return rad_to_deg(atan2(t.z, t.y))
		var yaw := func(k: Skeleton3D) -> float:
			var z: Vector3 = g.call(k, "Head").basis.z
			return rad_to_deg(atan2(z.x, z.z))
		var most := {"legs": 0.0, "lean": 0.0, "yaw": 0.0, "step": 0.0, "carry_lo": 0.0, "carry_hi": 0.0}
		var looks := {}
		var frames := int(VARY_SECONDS * 60.0)
		for i in frames:
			var was := [rig.vary_weight("carry"), rig.vary_weight("look")]
			for body: Array in bodies:
				(body[1] as AnimRig)._process(1.0 / 60.0)
			most["step"] = maxf(most["step"], maxf(absf(rig.vary_weight("carry") - float(was[0])), absf(rig.vary_weight("look") - float(was[1]))))
			most["carry_lo"] = minf(most["carry_lo"], rig.vary_weight("carry"))
			most["carry_hi"] = maxf(most["carry_hi"], rig.vary_weight("carry"))
			looks[snappedf(float(rig._vary_w["look"]["to"]), 0.0001)] = true
			for b: String in legs:
				most["legs"] = maxf(most["legs"], (g.call(sk, b) as Transform3D).origin.distance_to((g.call(plain_sk, b) as Transform3D).origin))
			most["lean"] = maxf(most["lean"], absf(float(trunk.call(sk)) - float(trunk.call(plain_sk))))
			most["yaw"] = maxf(most["yaw"], absf(wrapf(float(yaw.call(sk)) - float(yaw.call(plain_sk)), -180.0, 180.0)))
		if most["legs"] > VARY_LEGS:
			bad.append("a leg %.4f m off the plain jog's" % most["legs"])
		if most["lean"] > VARY_LEAN or most["lean"] < VARY_LEAN * VARY_SEEN:
			bad.append("the lean %.2f deg off the plain jog's" % most["lean"])
		if most["yaw"] > VARY_HEAD_YAW or most["yaw"] < VARY_HEAD_YAW * VARY_SEEN:
			bad.append("the head's yaw %.2f deg off the plain jog's" % most["yaw"])
		if most["step"] > steepest:
			bad.append("a weight's step %.4f a frame (the ease's steepest %.4f)" % [most["step"], steepest])
		if most["carry_lo"] > -VARY_SPREAD or most["carry_hi"] < VARY_SPREAD or looks.size() < VARY_LOOKS:
			bad.append("carry %+.2f to %+.2f, look drawn %d times" % [most["carry_lo"], most["carry_hi"], looks.size()])
		# A look held: the head is the turn's.
		rig.look_held = 1.0
		rig._process(1.0 / 60.0)
		var held := float(rig.tree.get("parameters/vary_look/add_amount"))
		rig.look_held = 0.0
		# Switched off: both to 0 within the blend.
		AnimRig.vary_on = false
		for k in int(ceil(rig.blend * 60.0)) + 1:
			rig._process(1.0 / 60.0)
		var off := [rig.vary_weight("carry"), rig.vary_weight("look"), rig.varies()]
		AnimRig.vary_on = true
		for k in 60:
			rig._process(1.0 / 60.0)
		var back := absf(rig.vary_weight("carry")) + absf(rig.vary_weight("look"))
		rig.loop("Idle", 1.0)
		for k in int(ceil(rig.blend * 60.0)) + 30:
			rig._process(1.0 / 60.0)
		var stood := [rig.vary_weight("carry"), rig.vary_weight("look")]
		if held != 0.0 or float(off[0]) != 0.0 or float(off[1]) != 0.0 or bool(off[2]) or back <= 0.0 or float(stood[0]) != 0.0 or float(stood[1]) != 0.0:
			bad.append("the look held %.3f; switched off %s; on again %.2f; stood %s" % [held, off, back, stood])
		print("  %s: %.0f s: legs %.5f m off, lean %.2f, head yaw %.2f deg at most; carry %+.2f to %+.2f, look drawn %d times; largest step %.4f a frame (cap %.4f)" % [
			build[0], VARY_SECONDS, most["legs"], most["lean"], most["yaw"], most["carry_lo"], most["carry_hi"], looks.size(), most["step"], steepest])
		_check(bad.is_empty(), "%s: the jog varies stride to stride within its caps, the legs untouched, the look yielding, off at rest and by the switch (%s)" % [build[0], "; ".join(bad)])
		for body: Array in bodies:
			(body[0] as Node3D).free()


## The walk and the stand vary (977 amended (2); TASK 10, the coordinator's terms, 11-19), on rigs with a fixed draw
## (term 2: a row's rigs seeded, VARY_SEED, the game's drawn locally). Two people's rigs for the man and the woman,
## one with the layer and one without, started together; the layer's legs (LEG_BONES and the hips) within VARY_LEGS of
## the plain body's every frame, and each weight's step a frame within its ease's steepest (smoothstep's 1.5 times the
## even share of its ease over twice its size).
const VARY_SEED := 977
const WALK_HEAD_YAW := 8.0
const STAND_SECONDS := 60.0
const STAND_LOOKS := 8
const STAND_CARRIES := 5
func _vary_bodies(lib: AnimationLibrary, path: String, clip: String) -> Array:
	var bodies := []
	for vary in [true, false]:
		var model := (load(path) as PackedScene).instantiate() as Node3D
		add_child(model)
		var rig := AnimRig.make(model, lib, 0.15, true, null, vary)
		rig._vary_rng.seed = VARY_SEED
		rig.stood_as = "People_"
		rig.gaits = PackedStringArray(["Walk", "Jog_Short", "Sprint_Short"])
		rig.loop(clip, 1.0, 0.0, true)
		rig._process(0.0)
		bodies.append([model, rig, model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D])
	return bodies


static func _vary_reads(k: Skeleton3D) -> Dictionary:
	var g := func(b: String) -> Transform3D: return k.get_bone_global_pose(k.find_bone(b))
	var t: Vector3 = ((g.call("LeftUpperArm") as Transform3D).origin + (g.call("RightUpperArm") as Transform3D).origin) * 0.5 - (g.call("Hips") as Transform3D).origin
	var z: Vector3 = (g.call("Head") as Transform3D).basis.z
	return {"trunk": rad_to_deg(atan2(t.z, t.y)), "yaw": rad_to_deg(atan2(z.x, z.z))}


static func _legs_off(sk: Skeleton3D, plain: Skeleton3D) -> float:
	var most := 0.0
	var legs: Array[String] = ["Hips"]
	legs.append_array(AnimRig.LEG_BONES)
	for b: String in legs:
		most = maxf(most, sk.get_bone_global_pose(sk.find_bone(b)).origin.distance_to(plain.get_bone_global_pose(plain.find_bone(b)).origin))
	return most


## The walk (VARY_SECONDS at 1/60): the head's yaw off the plain walk's at least VARY_SEEN of the walk's cap
## (AnimRig.VARY_WALK_LOOK times the run's 3.7) and never over WALK_HEAD_YAW; the lean within VARY_LEAN; "look" drawn
## every VARY_WALK_LOOK_STEPS footfalls (each "carry" draw a footfall), VARY_LOOKS times or more. Then busy (vary_calm
## false) the walk's weights at 0 within the blend, and the jog busy still the run's (977's, untouched).
func _test_walk_vary() -> void:
	print("== the walk varies, its look larger and more often than the run's, at 0 while busy ==")
	var lib := load(CLIPS) as AnimationLibrary
	for build: Array in [["man", "res://art/models/characters/human_m.glb"], ["woman", "res://art/models/characters/human_f.glb"]]:
		var bodies := _vary_bodies(lib, build[1], "Idle")
		for body: Array in bodies:
			(body[1] as AnimRig).loop("Walk", 1.0, 0.0, true)
		var rig: AnimRig = bodies[0][1]
		var sk: Skeleton3D = bodies[0][2]
		var plain_sk: Skeleton3D = bodies[1][2]
		var step_s := lib.get_animation(rig.as_played("Walk")).length / 2.0
		var steepest := 1.5 * 2.0 * AnimRig.VARY_WALK_LOOK / (step_s * AnimRig.VARY_WALK_EASE * 60.0) + 0.0001
		var most := {"legs": 0.0, "lean": 0.0, "yaw": 0.0, "step": 0.0}
		var gaps: Array[int] = []
		var falls_at := -1
		for i in int(VARY_SECONDS * 60.0):
			var was := [rig.vary_weight("carry"), rig.vary_weight("look"), int(rig._vary_draws["look"])]
			for body: Array in bodies:
				(body[1] as AnimRig)._process(1.0 / 60.0)
			most["step"] = maxf(most["step"], maxf(absf(rig.vary_weight("carry") - float(was[0])), absf(rig.vary_weight("look") - float(was[1]))))
			# A footfall draws "carry" (AnimRig._vary_draws); "look" drawn on a footfall, its gap counted in footfalls.
			if int(rig._vary_draws["look"]) != int(was[2]):
				if falls_at >= 0:
					gaps.append(int(rig._vary_draws["carry"]) - falls_at)
				falls_at = int(rig._vary_draws["carry"])
			most["legs"] = maxf(most["legs"], _legs_off(sk, plain_sk))
			var a := _vary_reads(sk)
			var b := _vary_reads(plain_sk)
			most["lean"] = maxf(most["lean"], absf(float(a["trunk"]) - float(b["trunk"])))
			most["yaw"] = maxf(most["yaw"], absf(wrapf(float(a["yaw"]) - float(b["yaw"]), -180.0, 180.0)))
		var bad: Array[String] = []
		var cap := 3.7 * AnimRig.VARY_WALK_LOOK
		if most["legs"] > VARY_LEGS:
			bad.append("a leg %.4f m off the plain walk's" % most["legs"])
		if most["lean"] > VARY_LEAN:
			bad.append("the lean %.2f deg off" % most["lean"])
		if most["yaw"] > WALK_HEAD_YAW or most["yaw"] < cap * VARY_SEEN:
			bad.append("the head's yaw %.2f deg off (at least %.2f, at most %.1f)" % [most["yaw"], cap * VARY_SEEN, WALK_HEAD_YAW])
		if most["step"] > steepest:
			bad.append("a weight's step %.4f a frame (cap %.4f)" % [most["step"], steepest])
		if gaps.size() + 1 < VARY_LOOKS or gaps.any(func(n: int) -> bool: return n < AnimRig.VARY_WALK_LOOK_STEPS.x or n > AnimRig.VARY_WALK_LOOK_STEPS.y):
			bad.append("look drawn %d times, footfalls between %s" % [gaps.size() + 1, gaps])
		# Busy (a piece readied, a fight, a load): the walk's layer at 0 within the blend.
		rig.vary_calm = false
		for k in int(ceil(rig.blend * 60.0)) + 1:
			rig._process(1.0 / 60.0)
		var busy := [rig.vary_weight("carry"), rig.vary_weight("look")]
		# The jog busy: 977's run, varying as landed.
		rig.loop("Jog_Short", 1.0, 0.0, true)
		for k in 90:
			rig._process(1.0 / 60.0)
		var jog := absf(rig.vary_weight("carry")) + absf(rig.vary_weight("look"))
		rig.vary_calm = true
		if float(busy[0]) != 0.0 or float(busy[1]) != 0.0 or jog <= 0.0:
			bad.append("busy at the walk %s; the jog busy %.3f" % [busy, jog])
		print("  %s: %.0f s walking: legs %.5f m off, lean %.2f, head yaw %.2f deg at most (cap %.1f); %d footfalls, look drawn %d times, footfalls between %s; largest step %.4f (cap %.4f)" % [
			build[0], VARY_SECONDS, most["legs"], most["lean"], most["yaw"], cap, int(rig._vary_draws["carry"]), gaps.size() + 1, gaps, most["step"], steepest])
		_check(bad.is_empty(), "%s: the walk varies within its caps, its look the run's twice over and every 3 to 6 footfalls, the legs untouched, at 0 while busy and the jog as landed (%s)" % [build[0], "; ".join(bad)])
		for body: Array in bodies:
			(body[0] as Node3D).free()


## The stand (STAND_SECONDS at 1/60, at Idle, vary_stand Idle): the plain body's rate kept to the layer's (its stand
## rate drawn each cycle), so the legs and the hips within VARY_LEGS of it every frame (the feet planted); the trunk off
## the plain's at least VARY_SEEN of VARY_LEAN and never over it, the head's yaw at least half the walk's cap and never
## over WALK_HEAD_YAW; "look" drawn STAND_LOOKS times or more at intervals within VARY_STAND_LOOK, at least STAND_LOOKS
## of them different at the frame's 1/60 (two draws may land on one frame count), and
## "carry" STAND_CARRIES or more within VARY_STAND_CARRY; the rate within VARY_STAND_RATE and not one value. Then each
## of the stand's stops at 0 within the blend, its rate back to the clip's: busy (vary_calm), unseen (seen), not its
## stand (vary_stand ""), Idle_Tired; a look held gives the look none. And from a jog's stop the stand's draws wait for
## the settle to be done.
func _test_idle_vary() -> void:
	print("== the stand varies on the rig's clock, the feet planted, at 0 while busy or unseen ==")
	var lib := load(CLIPS) as AnimationLibrary
	for build: Array in [["man", "res://art/models/characters/human_m.glb"], ["woman", "res://art/models/characters/human_f.glb"]]:
		var bodies := _vary_bodies(lib, build[1], "Idle")
		var rig: AnimRig = bodies[0][1]
		var plain: AnimRig = bodies[1][1]
		var sk: Skeleton3D = bodies[0][2]
		var plain_sk: Skeleton3D = bodies[1][2]
		rig.vary_stand = "Idle"
		var look_cap := 1.5 * 2.0 * AnimRig.VARY_WALK_LOOK / (AnimRig.VARY_STAND_LOOK_EASE * 60.0) + 0.0001
		var carry_cap := 1.5 * 2.0 / (AnimRig.VARY_STAND_CARRY_EASE * 60.0) + 0.0001
		var most := {"legs": 0.0, "lean": 0.0, "yaw": 0.0, "look_step": 0.0, "carry_step": 0.0}
		var draws := {"look": [], "carry": []}
		var rates := {}
		for i in int(STAND_SECONDS * 60.0):
			var was := [rig.vary_weight("carry"), rig.vary_weight("look"), rig._vary_draws.duplicate()]
			rig._process(1.0 / 60.0)
			plain.set_speed(rig._stand_rate)
			plain._process(1.0 / 60.0)
			most["carry_step"] = maxf(most["carry_step"], absf(rig.vary_weight("carry") - float(was[0])))
			most["look_step"] = maxf(most["look_step"], absf(rig.vary_weight("look") - float(was[1])))
			for layer: String in draws:
				if int(rig._vary_draws[layer]) != int((was[2] as Dictionary)[layer]):
					(draws[layer] as Array).append(i / 60.0)
			rates[snappedf(rig._stand_rate, 0.0001)] = true
			most["legs"] = maxf(most["legs"], _legs_off(sk, plain_sk))
			var a := _vary_reads(sk)
			var b := _vary_reads(plain_sk)
			most["lean"] = maxf(most["lean"], absf(float(a["trunk"]) - float(b["trunk"])))
			most["yaw"] = maxf(most["yaw"], absf(wrapf(float(a["yaw"]) - float(b["yaw"]), -180.0, 180.0)))
		var gaps := {}
		for layer: String in draws:
			var at: Array = draws[layer]
			gaps[layer] = []
			for k in range(1, at.size()):
				(gaps[layer] as Array).append(snappedf(float(at[k]) - float(at[k - 1]), 0.001))
		var bad: Array[String] = []
		var yaw_cap := 3.7 * AnimRig.VARY_WALK_LOOK
		if most["legs"] > VARY_LEGS:
			bad.append("a leg or the hips %.4f m off the plain stand's" % most["legs"])
		if most["lean"] > VARY_LEAN or most["lean"] < VARY_LEAN * VARY_SEEN:
			bad.append("the lean %.2f deg off" % most["lean"])
		if most["yaw"] > WALK_HEAD_YAW or most["yaw"] < yaw_cap * VARY_SEEN:
			bad.append("the head's yaw %.2f deg off" % most["yaw"])
		if most["look_step"] > look_cap or most["carry_step"] > carry_cap:
			bad.append("a step a frame: look %.4f (cap %.4f), carry %.4f (cap %.4f)" % [most["look_step"], look_cap, most["carry_step"], carry_cap])
		var look_gaps: Array = gaps["look"]
		var carry_gaps: Array = gaps["carry"]
		var unique := {}
		for gap: float in look_gaps:
			unique[gap] = true
		if (draws["look"] as Array).size() < STAND_LOOKS or unique.size() < STAND_LOOKS or look_gaps.any(func(s: float) -> bool: return s < AnimRig.VARY_STAND_LOOK.x - 0.02 or s > AnimRig.VARY_STAND_LOOK.y + 0.02):
			bad.append("look drawn %d times, seconds between %s" % [(draws["look"] as Array).size(), look_gaps])
		if (draws["carry"] as Array).size() < STAND_CARRIES or carry_gaps.any(func(s: float) -> bool: return s < AnimRig.VARY_STAND_CARRY.x - 0.02 or s > AnimRig.VARY_STAND_CARRY.y + 0.02):
			bad.append("carry drawn %d times, seconds between %s" % [(draws["carry"] as Array).size(), carry_gaps])
		if rates.size() < 2 or rates.keys().any(func(r: float) -> bool: return r < AnimRig.VARY_STAND_RATE.x or r > AnimRig.VARY_STAND_RATE.y):
			bad.append("the stand's rate %s" % [rates.keys()])
		print("  %s: %.0f s standing: legs and hips %.5f m off, lean %.2f, head yaw %.2f deg at most; look drawn %d times, s between %s; carry %d, s between %s; rates %s; largest steps look %.4f, carry %.4f" % [
			build[0], STAND_SECONDS, most["legs"], most["lean"], most["yaw"], (draws["look"] as Array).size(), look_gaps,
			(draws["carry"] as Array).size(), carry_gaps, rates.keys(), most["look_step"], most["carry_step"]])
		# Each of the stand's stops, and the stand again between them.
		var stops: Array[String] = []
		for stop: String in ["busy", "unseen", "not its stand", "tired", "held"]:
			for k in 120:
				rig._process(1.0 / 60.0)
			match stop:
				"busy": rig.vary_calm = false
				"unseen": rig.seen = false
				"not its stand": rig.vary_stand = ""
				"tired": rig.loop("Idle_Tired", 1.0, 0.0, true)
				"held": rig.look_held = 1.0
			for k in int(ceil(rig.blend * 60.0)) + 1:
				rig._process(1.0 / 60.0)
			var scale := float(rig.tree.get("parameters/%s_speed/scale" % AnimRig._slot_name(rig._slot)))
			var look := float(rig.tree.get("parameters/vary_look/add_amount"))
			var ok := look == 0.0 if stop == "held" else (rig.vary_weight("carry") == 0.0 and rig.vary_weight("look") == 0.0 and is_equal_approx(scale, float(rig._base_speed[rig._slot])))
			if not ok:
				stops.append("%s: carry %.3f, look %.3f, its rate %.3f" % [stop, rig.vary_weight("carry"), look, scale])
			rig.vary_calm = true
			rig.seen = true
			rig.vary_stand = "Idle"
			rig.look_held = 0.0
			if stop == "tired":
				rig.loop("Idle", 1.0, 0.0, true)
		# A jog's stop: the stand's draws wait for the settle.
		rig.loop("Jog_Short", 1.0, 0.0, true)
		for k in 60:
			rig._process(1.0 / 60.0)
		var early := false
		for k in 18:
			rig.settle("Idle", 0.3)
			rig._process(1.0 / 60.0)
		rig.loop("Idle", 1.0)
		for k in 120:
			rig._process(1.0 / 60.0)
			if rig._vary_mode == "stand" and (rig.settled() > 0.0 or rig._settle_rising):
				early = true
		if early or rig._vary_mode != "stand":
			stops.append("after a jog's stop: the stand drew inside the settle %s, standing %s" % [early, rig._vary_mode])
		bad.append_array(stops)
		_check(bad.is_empty(), "%s: the stand varies over a minute within its caps, never a loop (intervals drawn, the rate drawn each cycle), the feet planted, at 0 busy, unseen, tired, off its stand or in a settle (%s)" % [build[0], "; ".join(bad)])
		for body: Array in bodies:
			(body[0] as Node3D).free()


## The stand's cost (term 3: a count from a row): VARY_COST_RIGS people's rigs standing at Idle, the man's and the
## woman's in turn, stepped VARY_COST_FRAMES at 1/60 (each _process: the layer's step and the tree's), timed with the
## stand's layer on and then with it off (vary_on false: as main's tip stands, its weights at 0), each twice, the
## least kept. The layer's work a rig a frame is the difference over the rigs; printed, and failed only past
## VARY_COST_MOST (a loaded machine's noise kept out of it: the coordinator's twentieth of a millisecond is read from
## the print).
const VARY_COST_RIGS := 30
const VARY_COST_FRAMES := 300
const VARY_COST_MOST := 0.5
func _test_vary_cost() -> void:
	print("== the stand's cost: %d people standing ==" % VARY_COST_RIGS)
	var lib := load(CLIPS) as AnimationLibrary
	var rigs: Array[AnimRig] = []
	var models: Array[Node3D] = []
	for i in VARY_COST_RIGS:
		var model := (load("res://art/models/characters/human_m.glb" if i % 2 == 0 else "res://art/models/characters/human_f.glb") as PackedScene).instantiate() as Node3D
		add_child(model)
		var rig := AnimRig.make(model, lib, 0.15, true, null, true)
		rig._vary_rng.seed = VARY_SEED + i
		rig.stood_as = "People_"
		rig.gaits = PackedStringArray(["Walk", "Jog_Short", "Sprint_Short"])
		rig.vary_stand = "Idle"
		rig.loop("Idle", 1.0, 0.0, true)
		rig._process(0.0)
		rigs.append(rig)
		models.append(model)
	var was := AnimRig.vary_on
	var timed := {}
	var standing := 0
	for on: bool in [true, false, true, false]:
		AnimRig.vary_on = on
		for k in 30:
			for rig in rigs:
				rig._process(1.0 / 60.0)
		if on:
			standing = rigs.filter(func(rig: AnimRig) -> bool: return rig._vary_mode == "stand").size()
		var start := Time.get_ticks_usec()
		for k in VARY_COST_FRAMES:
			for rig in rigs:
				rig._process(1.0 / 60.0)
		var ms := (Time.get_ticks_usec() - start) / 1000.0 / VARY_COST_FRAMES
		timed[on] = minf(float(timed.get(on, INF)), ms)
	AnimRig.vary_on = was
	var layer := (float(timed[true]) - float(timed[false])) / VARY_COST_RIGS
	print("  a frame, %d rigs standing: %.3f ms with the stand's layer, %.3f ms without (as main's tip); the layer %.4f ms a rig a frame (%d of %d varying)" % [
		VARY_COST_RIGS, timed[true], timed[false], layer, standing, VARY_COST_RIGS])
	_check(standing == VARY_COST_RIGS and layer < VARY_COST_MOST, "the stand's layer costs %.4f ms a rig a frame (under %.1f), every rig varying (%d)" % [layer, VARY_COST_MOST, standing])
	for model in models:
		model.free()

## [param anim]'s stride on [param skeleton] over 240 samples: "pace", the planted toe's median backward
## speed (as tools/gait_pace.gd: a toe within 2 cm of the lowest on both samples); "flight", the share of
## samples with neither foot down (a foot down when its toe or heel, from rest, is within 2 cm of the lowest);
## "stance", each foot's share of the samples down;
## "knee", the deepest fold (180 less the thigh-shin angle) of a planted leg.
static func _jog_stride(skeleton: Skeleton3D, anim: Animation) -> Dictionary:
	const N := 240
	var bone := func(name: String) -> int: return skeleton.find_bone(name)
	var toe_rest := skeleton.get_bone_global_rest(bone.call("LeftToes")).origin.y
	var heel_rest := skeleton.get_bone_global_rest(bone.call("LeftFoot")).origin.y
	var fwd := skeleton.get_bone_global_rest(bone.call("LeftToes")).origin - skeleton.get_bone_global_rest(bone.call("LeftFoot")).origin
	fwd = Vector3(fwd.x, 0.0, fwd.z).normalized()
	var toes := []
	var soles := []
	var knees := []
	for i in N + 1:
		_jog_pose(skeleton, anim, anim.length * i / N)
		var t_toes := []
		var t_soles := []
		var t_knees := []
		for side: String in ["Left", "Right"]:
			var toe := _jog_global(skeleton, bone.call(side + "Toes")).origin
			var foot := _jog_global(skeleton, bone.call(side + "Foot")).origin
			var hip := _jog_global(skeleton, bone.call(side + "UpperLeg")).origin
			var knee := _jog_global(skeleton, bone.call(side + "LowerLeg")).origin
			t_toes.append(toe)
			t_soles.append(minf(toe.y - toe_rest, foot.y - heel_rest))
			t_knees.append(180.0 - rad_to_deg((hip - knee).angle_to(foot - knee)))
		toes.append(t_toes)
		soles.append(t_soles)
		knees.append(t_knees)
	var low := INF
	var sole_low := INF
	for i in N + 1:
		for side in 2:
			low = minf(low, (toes[i][side] as Vector3).y)
			sole_low = minf(sole_low, float(soles[i][side]))
	var speeds: Array[float] = []
	var flight := 0
	var deepest := 0.0
	var stance := [0, 0]
	for i in N:
		var down := false
		for side in 2:
			var p: Vector3 = toes[i][side]
			var q: Vector3 = toes[i + 1][side]
			if p.y <= low + 0.02 and q.y <= low + 0.02:
				speeds.append(-(q - p).dot(fwd) / (anim.length / N))
			if float(soles[i][side]) <= sole_low + 0.02:
				down = true
				stance[side] += 1
				deepest = maxf(deepest, float(knees[i][side]))
		if not down:
			flight += 1
	speeds.sort()
	return {"pace": speeds[speeds.size() / 2] if not speeds.is_empty() else 0.0, "flight": float(flight) / N, "knee": deepest,
		"stance": [float(stance[0]) / N, float(stance[1]) / N]}


## [param anim]'s rotation and position tracks at [param t] on [param skeleton]'s poses (reset first).
static func _jog_pose(skeleton: Skeleton3D, anim: Animation, t: float) -> void:
	skeleton.reset_bone_poses()
	for k in anim.get_track_count():
		var bone := skeleton.find_bone(str(anim.track_get_path(k)).get_slice(":", 1))
		if bone < 0:
			continue
		match anim.track_get_type(k):
			Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(bone, anim.rotation_track_interpolate(k, t))
			Animation.TYPE_POSITION_3D:
				skeleton.set_bone_pose_position(bone, anim.position_track_interpolate(k, t))


## A bone's pose in the skeleton's space, chained by hand from its poses (no skeleton update needed).
static func _jog_global(skeleton: Skeleton3D, bone: int) -> Transform3D:
	var own := Transform3D(Basis(skeleton.get_bone_pose_rotation(bone)).scaled(skeleton.get_bone_pose_scale(bone)), skeleton.get_bone_pose_position(bone))
	var parent := skeleton.get_bone_parent(bone)
	return own if parent < 0 else _jog_global(skeleton, parent) * own
