class_name AnimRig
extends Node
## The one way a model's clips are played (decision 390, roadmap step 3):
## an AnimationTree of its own beside the model's AnimationPlayer, in layers.
##
##   base    the clip a body is in: a loop (idle, a gait, sitting) or a clip
##           played once and held at its end (a fidget, a death, lying),
##           each change crossfaded over the rig's blend;
##   upper   a clip over the body above the hips (a guard, a bow drawn),
##           the legs left to the base (left out of the tree with
##           upper = false: a quadruped has no such bones);
##   posture an additive pose on top (stooped, slouching), made outside the
##           rig and only added by it;
##   action  a blow over everything (strike): timed so its contact lands
##           when the sim's blow does, faded in and out by the blend.
##
## Which clip is played stays with the caller (Client3D's HUMANOID_MOVES,
## CreatureView's clip map): the rig is handed clip names. Every body has a
## tree of its own: its clips and speeds are its own.

## The bones the upper layer moves, by the humanoid profile's names
## (Godot's retargeted %GeneralSkeleton): the spine up, the clavicles,
## arms and hands.
const UPPER_BONES: Array[String] = ["Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand"]
## A strike's speed is kept within these (a blow can be hurried or held back
## only so far before it no longer reads as that blow).
const STRIKE_SPEED_MIN := 0.4
const STRIKE_SPEED_MAX := 3.0
## Where in a strike its blow lands when its table names no contact: this
## far through the clip.
const CONTACT_DEFAULT := 0.5

var player: AnimationPlayer
var tree: AnimationTree
## Seconds a change of clip crossfades over (and a strike fades in and out).
var blend := 0.15
## The tree is posed every this many frames (its level of detail: the caller
## sets it by how near and how seen the body is), with the time since.
var every := 1
var _since := 0.0
var _frames := 0
var _root: AnimationNodeBlendTree
var _slot := 0  # The base slot playing: 0 is "a", 1 is "b".
var _base_clip := ["", ""]
var _base_speed := [1.0, 1.0]
var _base_seek := [0.0, 0.0]  # Where each slot's clip was started.
var _has_upper := false
var _upper_clip := ""
var _posture: Animation
var _action_clip := ""
var _action_speed := 1.0
## A strike's speed after its contact, and the msec it changes to it.
var _recover_speed := 1.0
var _contact_msec := -1
var _busy_msec := 0  # A clip played once runs till then.
var _strike_msec := 0  # A strike runs till then.
var _rng: RandomNumberGenerator


## A rig for [param scene] (its root node holds the skeleton) playing
## [param clips] (their loop modes as their library has them), crossfading
## over [param blend_seconds]; [param upper]: whether it has the upper
## layer. Seeded by [param rng], loops start where they will.
static func make(scene: Node3D, clips: AnimationLibrary, blend_seconds := 0.15, upper := true,
		rng: RandomNumberGenerator = null) -> AnimRig:
	var rig := AnimRig.new()
	rig.name = "Rig"
	rig.blend = blend_seconds
	rig._rng = rng
	rig.player = AnimationPlayer.new()
	rig.player.name = "Animator"
	scene.add_child(rig.player)
	rig.player.root_node = NodePath("..")
	rig.player.add_animation_library("", clips)
	scene.add_child(rig)
	rig._build(upper)
	return rig


func _build(upper: bool) -> void:
	_has_upper = upper
	_root = AnimationNodeBlendTree.new()
	var base := AnimationNodeTransition.new()
	base.xfade_time = blend
	for slot: String in ["a", "b"]:
		base.add_input(slot)
		_root.add_node(slot, AnimationNodeAnimation.new())
		_root.add_node(slot + "_seek", AnimationNodeTimeSeek.new())
		_root.add_node(slot + "_speed", AnimationNodeTimeScale.new())
		_root.connect_node(slot + "_seek", 0, slot)
		_root.connect_node(slot + "_speed", 0, slot + "_seek")
	_root.add_node("base", base)
	_root.connect_node("base", 0, "a_speed")
	_root.connect_node("base", 1, "b_speed")
	var under := "base"
	if upper:
		var layer := AnimationNodeBlend2.new()
		layer.filter_enabled = true
		for bone in UPPER_BONES:
			layer.set_filter_path(NodePath("%GeneralSkeleton:" + bone), true)
		_root.add_node("upper_clip", AnimationNodeAnimation.new())
		_root.add_node("upper", layer)
		_root.connect_node("upper", 0, under)
		_root.connect_node("upper", 1, "upper_clip")
		under = "upper"
	_root.add_node("pose", AnimationNodeAnimation.new())
	_root.add_node("posture", AnimationNodeAdd2.new())
	_root.connect_node("posture", 0, under)
	_root.connect_node("posture", 1, "pose")
	var action := AnimationNodeOneShot.new()
	action.fadein_time = blend
	action.fadeout_time = blend
	_root.add_node("action_clip", AnimationNodeAnimation.new())
	_root.add_node("action_seek", AnimationNodeTimeSeek.new())
	_root.add_node("action_speed", AnimationNodeTimeScale.new())
	_root.connect_node("action_seek", 0, "action_clip")
	_root.connect_node("action_speed", 0, "action_seek")
	_root.add_node("action", action)
	_root.connect_node("action", 0, "posture")
	_root.connect_node("action", 1, "action_speed")
	_root.connect_node("output", 0, "action")
	tree = AnimationTree.new()
	tree.name = "Tree"
	add_child(tree)
	tree.root_node = tree.get_path_to(player.get_node(player.root_node))
	tree.anim_player = tree.get_path_to(player)
	tree.tree_root = _root
	# Advanced by the rig itself, every so many frames (every).
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	# Bodies posed every other frame or less are spread over the frames.
	_frames = get_instance_id() % 8
	if upper:
		tree.set("parameters/upper/blend_amount", 0.0)
	tree.set("parameters/posture/add_amount", 0.0)
	tree.active = true


## Whether the library has [param clip] (with its "library/" prefix or not).
func has(clip: String) -> bool:
	return player.has_animation(_name(clip))


## [param clip] as the player knows it.
func _name(clip: String) -> String:
	if player.has_animation(clip) or not clip.contains("/"):
		return clip
	return clip.get_slice("/", 1)


## The base layer plays [param clip] at [param speed] (of the clip's own):
## crossfaded in over [param fade] (the rig's blend if negative), started
## somewhere along it (seeded) unless [param from_start]. The clip already
## playing only takes the new speed: no restart, no fade (a gait's pace
## changes every frame).
func loop(clip: String, speed := 1.0, fade := -1.0, from_start := false) -> void:
	clip = _name(clip)
	if clip == _base_clip[_slot] and not from_start:
		set_speed(speed)
		return
	_to_base(clip, speed, fade, -1.0 if from_start else -2.0)


## The base layer's speed (the clip playing goes on, faster or slower).
func set_speed(speed: float) -> void:
	_base_speed[_slot] = speed
	tree.set("parameters/%s_speed/scale" % _slot_name(_slot), speed)


## [param clip] once from its start (from its end, backwards, at a speed
## below 0), crossfaded in over [param fade] (the rig's blend if negative)
## and held at its end until the next loop or once (a death, lying; a
## fidget, which the caller drops when it is done with it). The seconds it
## takes.
func once(clip: String, speed := 1.0, fade := -1.0) -> float:
	clip = _name(clip)
	if not player.has_animation(clip) or is_zero_approx(speed):
		return 0.0
	var length := player.get_animation(clip).length
	_to_base(clip, speed, fade, length if speed < 0.0 else 0.0, true)
	var seconds := length / absf(speed)
	_busy_msec = Time.get_ticks_msec() + int(seconds * 1000.0)
	return seconds


func _to_base(clip: String, speed: float, fade: float, seek: float, restart := false) -> void:
	if not player.has_animation(clip):
		return
	var next := 1 - _slot if clip != _base_clip[_slot] or restart else _slot
	if next == _slot and restart and not is_zero_approx(fade):
		# The same clip again from its start: through the other slot, so it
		# crossfades into itself rather than jumping.
		next = 1 - _slot
	var slot := _slot_name(next)
	(_root.get_node(slot) as AnimationNodeAnimation).animation = clip
	_base_clip[next] = clip
	_base_speed[next] = speed
	tree.set("parameters/%s_speed/scale" % slot, speed)
	if seek == -2.0:
		seek = _rng.randf() * player.get_animation(clip).length if _rng != null else 0.0
	_base_seek[next] = maxf(seek, 0.0)
	tree.set("parameters/%s_seek/seek_request" % slot, _base_seek[next])
	(_root.get_node("base") as AnimationNodeTransition).xfade_time = blend if fade < 0.0 else fade
	tree.set("parameters/base/transition_request", slot)
	_slot = next
	_apply()


## [param clip] struck once over everything: played so the blow lands
## (its [param contact], seconds into the clip at speed 1; CONTACT_DEFAULT
## of it if negative) [param lands_in] seconds from now, then what follows
## the contact fitted to [param recover] seconds; each speed kept within
## STRIKE_SPEED_MIN to MAX. Faded in and out over the rig's blend. The
## seconds it takes.
func strike(clip: String, contact: float, lands_in: float, recover: float) -> float:
	clip = _name(clip)
	if not player.has_animation(clip):
		return 0.0
	var length := player.get_animation(clip).length
	if contact < 0.0:
		contact = length * CONTACT_DEFAULT
	contact = clampf(contact, 0.0, length)
	var before := clampf(contact / maxf(lands_in, 0.001), STRIKE_SPEED_MIN, STRIKE_SPEED_MAX)
	_recover_speed = clampf((length - contact) / maxf(recover, 0.001), STRIKE_SPEED_MIN, STRIKE_SPEED_MAX)
	(_root.get_node("action_clip") as AnimationNodeAnimation).animation = clip
	_action_clip = clip
	_set_action_speed(before)
	tree.set("parameters/action_seek/seek_request", 0.0)
	tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_apply()
	var now := Time.get_ticks_msec()
	_contact_msec = now + int(contact / before * 1000.0)
	var seconds := contact / before + (length - contact) / _recover_speed
	_strike_msec = now + int(seconds * 1000.0)
	return seconds


func _set_action_speed(speed: float) -> void:
	_action_speed = speed
	tree.set("parameters/action_speed/scale", speed)


## A strike under way stopped, faded out.
func cancel_strike() -> void:
	if striking():
		tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
		_apply()
	_strike_msec = 0
	_contact_msec = -1


## The upper layer plays [param clip] over the body above the hips; "" lets
## it go. (Nothing on a rig made without the layer.)
func upper(clip: String) -> void:
	if not _has_upper:
		return
	clip = _name(clip)
	if clip == "" or not player.has_animation(clip):
		_upper_clip = ""
		tree.set("parameters/upper/blend_amount", 0.0)
		return
	if clip != _upper_clip:
		(_root.get_node("upper_clip") as AnimationNodeAnimation).animation = clip
		_upper_clip = clip
	tree.set("parameters/upper/blend_amount", 1.0)


func upper_off() -> void:
	upper("")


## [param pose] (a clip of one frame, a body's rest bent) added at
## [param weight]; a null pose clears it.
func posture(pose: Animation, weight: float) -> void:
	if pose == null or weight <= 0.0:
		_posture = null
		tree.set("parameters/posture/add_amount", 0.0)
		return
	if pose != _posture:
		var library := player.get_animation_library("")
		var key := "_posture_" + str(pose.get_instance_id())
		if not library.has_animation(key):
			library.add_animation(key, pose)
		(_root.get_node("pose") as AnimationNodeAnimation).animation = key
		_posture = pose
	tree.set("parameters/posture/add_amount", weight)


## Whether a clip played once or a strike is still going.
func busy() -> bool:
	return Time.get_ticks_msec() < _busy_msec or striking()


func striking() -> bool:
	return Time.get_ticks_msec() < _strike_msec


## The clip on top: a strike's while it plays, else the base layer's.
func playing() -> String:
	return _action_clip if striking() else _base_clip[_slot]


## The base layer's clip, whatever plays over it.
func base_clip() -> String:
	return _base_clip[_slot]


## The speed of the clip on top (below 0 backwards).
func speed() -> float:
	return _action_speed if striking() else _base_speed[_slot]


## Seconds into the clip on top.
func position() -> float:
	if striking():
		return _action_time()
	var at: Variant = tree.get("parameters/%s/current_position" % _slot_name(_slot))
	# Before the tree has played a frame of it: where it was started.
	return float(at) if at != null and float(at) > 0.0 else float(_base_seek[_slot])


func _action_time() -> float:
	var at: Variant = tree.get("parameters/action_clip/current_position")
	return float(at) if at != null else 0.0


## [param clip]'s seconds at speed 1 (0 if there is none).
func length(clip: String) -> float:
	clip = _name(clip)
	return player.get_animation(clip).length if player.has_animation(clip) else 0.0


func clips() -> PackedStringArray:
	return player.get_animation_list()


func _ready() -> void:
	# Made before it was in the scene: what it was asked to play takes now.
	if tree != null:
		_apply()


func _process(delta: float) -> void:
	if _contact_msec >= 0 and Time.get_ticks_msec() >= _contact_msec:
		_contact_msec = -1
		_set_action_speed(_recover_speed)
	_since += delta
	_frames += 1
	if every <= 1 or _frames % every == 0:
		tree.advance(_since)
		_since = 0.0


## A change takes now, not at the tree's next frame: what plays (and where)
## is what was asked for straight away.
func _apply() -> void:
	tree.advance(0.0)


static func _slot_name(slot: int) -> String:
	return "a" if slot == 0 else "b"
