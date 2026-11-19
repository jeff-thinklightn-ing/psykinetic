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
##           upper = false: a quadruped has no such bones); its sky clip
##           (sky) mixed over it in step, the bow's flat and sky draws;
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
## The clock clips are timed by (now_msec): unset till its first read; -1 off a movie.
static var _clock_msec := 0
static var _clock_frame := -1
static var _clock_movie := -1

const UPPER_BONES: Array[String] = ["Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand"]
## The bones the legs layer takes from the base under a strike (legs_walk):
## the hips stay the strike's, so its turn and lean read.
const LEG_BONES: Array[String] = ["LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes",
	"RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes"]
## The arm's bones a posture leaves to a gait (posture_arms; 953 amended (3)). Posture_Slouch and Posture_Stooped
## turn the shoulders (the clavicles) in, about 13 degrees about the upright for the slouch: on a body standing it
## reads as rounded shoulders; on an arm swinging fore and aft it turns the swing across, the two hands drifting to
## the same side together (a slouched runner 0.11 m a hand, stooped 0.04, the run's own path 0.005; Rhea in
## ui-design's arms5). Filtered one group at a time on the slouched jog, the shoulders alone carry it (0.118 m;
## the spine 0.015, the neck and head, hips, legs none). The arm below them is here too, for a posture that turns it.
const POSTURE_ARM_BONES: Array[String] = ["LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand"]
## A posture's body share through a gait (977): the people's run leans from the feet (5 degrees on the pelvis), and
## a stooped or slouched body added whole on top of it would run bent further than it stands (stooped 22.7 to 27.7
## degrees, hips to shoulders). In a gait the rest of the posture plays at this share, eased with its arms
## (posture_arms: 1 at rest gives the whole posture, 0 in a gait gives this), so the lean is part of the bend.
const POSTURE_GAIT_BODY := 0.65
## The run's variation (977; Jeff, 11-17: "throwing in a some slight variation into movement so it's not just a strict
## loop"): a people's rig (make's vary) adds two delta poses after its posture, each weighed -1 to +1 by an Add3 (its
## "-" input the _Minus pose): "carry" (VARY_CARRY: the trunk's lean +-1.5 degrees, the elbows +-6, the shoulders' carry
## +-2) and "look" (VARY_LOOK: the head's yaw +-4 and pitch +-2), tools/humanoid_clips.py's. Drawn only: each weight is
## drawn from the rig's own generator (a local draw, nothing of whose body it is) at a footfall (each half of the base
## clip's cycle) and eased to over VARY_EASE of a step (smoothstep: its steepest frame 1.5 times the even share), "carry"
## at every footfall, "look" every VARY_LOOK_STEPS footfalls; in a gait only (gaits), eased to 0 over the blend
## otherwise; "look" scaled by 1 - look_held (a head turned on purpose, Client3D's addressing look, has the head). The
## legs, the timing and the pace never touched. vary_on false (the command line's --no-vary) turns the layer off.
## The trunk's bones a stop settles (settle; 869 amended (4)): above the hips, so the feet are the held gait's.
const SETTLE_BONES: Array[String] = ["Spine", "Chest", "UpperChest", "Neck", "Head"]
const VARY_CARRY: Array[String] = ["Vary_Carry_Minus", "Vary_Carry_Plus"]
const VARY_LOOK: Array[String] = ["Vary_Look_Minus", "Vary_Look_Plus"]
const VARY_EASE := 0.5
const VARY_LOOK_STEPS := Vector2i(4, 10)
static var vary_on := not "--no-vary" in OS.get_cmdline_user_args()
## The walk and the stand vary too (977 amended (2); TASK 10, the coordinator's terms, 11-19). At the walk (gaits' first)
## "look" is drawn to VARY_WALK_LOOK times the run's (the head's yaw to +-7.4, its pitch +-4) every VARY_WALK_LOOK_STEPS
## footfalls, eased over VARY_WALK_EASE of a step; "carry" as the run's. Standing at its own stand clip (vary_stand,
## Client3D's: a body's idle, never Idle_Tired) the two are drawn on the rig's clock, not footfalls: "look" to the walk's
## size every VARY_STAND_LOOK seconds, eased over VARY_STAND_LOOK_EASE; "carry" to the run's every VARY_STAND_CARRY,
## eased over VARY_STAND_CARRY_EASE, each on its own timer; and the stand clip's rate drawn in VARY_STAND_RATE at each
## of its cycles (its feet are planted). The stand's draws wait for a stop's settle to be done, and run only while the
## rig is seen (seen: Client3D's, its body in the camera's frustum). The walk and the stand vary only while vary_calm
## (Client3D's: nothing readied, drawn or aimed, not hurt or in a fight, neither carrying nor working nor in a one-off),
## eased to 0 over the blend otherwise; the jog and the sprint are 977's, untouched. vary_log (--vary-log, a debug
## build only) prints each draw: the rig's kind (its model's file), its clip, the layer, the weights and the time.
const VARY_WALK_LOOK := 2.0
const VARY_WALK_LOOK_STEPS := Vector2i(3, 6)
const VARY_WALK_EASE := 1.0
const VARY_STAND_LOOK := Vector2(2.5, 7.0)
const VARY_STAND_LOOK_EASE := 1.0
const VARY_STAND_CARRY := Vector2(4.0, 9.0)
const VARY_STAND_CARRY_EASE := 1.5
const VARY_STAND_RATE := Vector2(0.92, 1.08)
static var vary_log := OS.is_debug_build() and "--vary-log" in OS.get_cmdline_user_args()
## A debug build's --hold-log (869 amended (5)): Client3D prints a line for each of a gait's holds (never a released one).
static var hold_log := OS.is_debug_build() and "--hold-log" in OS.get_cmdline_user_args()
## The free leg's sole at a hold (settle_leg), metres over its rest's: the gait's own stances stand 0.004 to 0.025.
const LEG_SOLE := 0.01
## The free leg comes down over this (settle_leg; it goes back over the blend): down by the hold's end from any stop.
const LEG_EASE := 0.1
## The free leg's swing over before it comes down: its turn is done at this share of LEG_EASE, its height lags.
const LEG_TURN := 0.6
## The free foot's lift, metres at its height, as it steps from its held stance into the stand's blend (a step, not a drag).
const LEG_STEP := 0.06
## A strike's speed is kept within these (a blow can be hurried or held back
## only so far before it no longer reads as that blow).
const STRIKE_SPEED_MIN := 0.4
const STRIKE_SPEED_MAX := 3.0
## A strike fades in over at most this share of its lead (the seconds to its
## contact), never longer than the rig's blend: faded over the whole blend, a
## lead as short as the sword's (0.2 s) was mostly hidden under the fade, and
## the slash read as the arm thrust out (Jeff on v0.1.198: "punching with a
## sword in my hand"; 338 amended (3)).
const STRIKE_FADE_SHARE := 0.25
## Where in a strike its blow lands when its table names no contact: this
## far through the clip.
const CONTACT_DEFAULT := 0.5

var player: AnimationPlayer
var tree: AnimationTree
## Seconds a change of clip crossfades over (and a strike fades in and out).
var blend := 0.15
## A prefix (decision 877: Client3D.PEOPLE_PREFIX on a people's body): a clip asked for is played
## as its copy so named where the library has one (People_Idle for Idle), and named plain by
## playing(), base_clip() and upper_clip(), so callers and their tables keep the plain names.
var stood_as := ""
## The base clips (named plain) a posture's arms ease out of (Client3D: the body's gaits). Playing one, the
## posture's arm share goes to 0 over the base's crossfade; playing anything else, back to 1. The spine, neck and
## head keep the posture throughout.
var gaits := PackedStringArray()
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
## The upper layer's speed (upper()): its clip played this many times as fast.
var _upper_speed := 1.0
var _sky_clip := ""
var _sky_amount := 0.0
var _posture: Animation
var _posture_weight := 0.0
var _posture_arms := 1.0  # The posture's arm share now (posture_arms).
var _action_clip := ""
var _action_speed := 1.0
## A strike's speed after its contact, and the msec it changes to it.
var _recover_speed := 1.0
var _contact_msec := -1
## Where a held strike's clip is put at its contact (its contact, seconds into the clip), or -1: a
## held strike's phases each put the clip where it should be, so a long frame never carries it
## past its gather (790 amended (9): one long frame in the draw held him with the dagger out).
var _contact_seek := -1.0
## A held strike's (strike_held) speeds before its contact, each [msec, speed] from that msec on.
var _phases: Array = []
## The msec the last strike's blow lands (its contact), kept after: its hit is heard then.
var contact_msec := -1
## The last strike's contact in its clip's own seconds (a test reads the pose there, not by the clock).
var contact_at := 0.0
var _busy_msec := 0  # A clip played once runs till then.
var _legs := 0.0  # The legs layer's weight (legs_walk).
var _strike_msec := 0  # A strike runs till then.
var _rng: RandomNumberGenerator
## The variation (VARY_CARRY): whether this rig has it, each weight's {"now", "from", "to", "eased"} ("eased" 0 to 1 over
## VARY_EASE of a step), the footfall last drawn at ([clip, half]) and the footfalls till "look" draws again.
var _vary := false
var _vary_rng := RandomNumberGenerator.new()
var _vary_w := {"carry": {"now": 0.0, "from": 0.0, "to": 0.0, "eased": 1.0}, "look": {"now": 0.0, "from": 0.0, "to": 0.0, "eased": 1.0}}
var _vary_step: Array = ["", -1]
var _vary_look_in := 0
## The walk's and the stand's (977 amended (2)): the stand clip a body varies at ("" none), whether it may vary (calm),
## whether it is seen, the model's kind for vary_log; the mode last stepped ("", "gait", "stand"), the stand's seconds
## till each layer draws, its rate and the cycle it was drawn at.
var vary_stand := ""
var vary_calm := true
var seen := true
var kind := ""
var _vary_mode := ""
var _stand_in := {"look": 0.0, "carry": 0.0}
var _stand_rate := 1.0
var _stand_cycle := -1
var _stand_last := 0.0
var _vary_zeroed := false
var _vary_draws := {"look": 0, "carry": 0, "rate": 0}  # Draws so far, by layer (a row counts them).
## A stop's settle (settle): the stand clip the trunk eases to, its share now (0 to 1), the seconds it rises over, the
## gait it rises from, whether it rises, and the seconds the base has played the stand clip.
var _settle_clip := ""
var _settle := 0.0
var _settle_seconds := 0.45
var _settle_from := ""
var _settle_rising := false
var _settle_stood := 0.0
var _settle_skeleton: Skeleton3D
## A hold's free leg (settle_leg): its share now (0 to 1), whether it rises, its side ("Left" or "Right"), the gait
## clip (as played) it was held in and the seconds into it where that leg's own stance stands (half a cycle on);
## per side, its bones [upper leg, lower leg, foot, toes] and their rests' heights.
var _leg := 0.0
var _leg_rising := false
var _leg_side := ""
var _leg_clip := ""
var _leg_at := 0.0
var _leg_bones := {}
## How much of the head a purposeful turn holds (0 to 1; Client3D's addressing look): "look" yields so much.
var look_held := 0.0


## A rig for [param scene] (its root node holds the skeleton) playing
## [param clips] (their loop modes as their library has them), crossfading
## over [param blend_seconds]; [param upper]: whether it has the upper
## layer. Seeded by [param rng], loops start where they will.
static func make(scene: Node3D, clips: AnimationLibrary, blend_seconds := 0.15, upper := true,
		rng: RandomNumberGenerator = null, vary := false) -> AnimRig:
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
	rig._vary = vary and upper and VARY_CARRY.all(clips.has_animation) and VARY_LOOK.all(clips.has_animation)
	rig._vary_rng.randomize()
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
	if _vary:
		# A people's stop (settle): the trunk (SETTLE_BONES) eased to the stand's over the held gait.
		var settle := AnimationNodeBlend2.new()
		settle.filter_enabled = true
		for bone in SETTLE_BONES:
			settle.set_filter_path(NodePath("%GeneralSkeleton:" + bone), true)
		_root.add_node("settle_clip", AnimationNodeAnimation.new())
		_root.add_node("settle", settle)
		_root.connect_node("settle", 0, under)
		_root.connect_node("settle", 1, "settle_clip")
		under = "settle"
	if upper:
		var layer := AnimationNodeBlend2.new()
		layer.filter_enabled = true
		for bone in UPPER_BONES:
			layer.set_filter_path(NodePath("%GeneralSkeleton:" + bone), true)
		_root.add_node("upper_clip", AnimationNodeAnimation.new())
		_root.add_node("upper_seek", AnimationNodeTimeSeek.new())
		_root.add_node("upper_speed", AnimationNodeTimeScale.new())
		_root.connect_node("upper_seek", 0, "upper_clip")
		_root.connect_node("upper_speed", 0, "upper_seek")
		# The sky clip (sky), mixed over the upper clip in step with it.
		_root.add_node("sky_clip", AnimationNodeAnimation.new())
		_root.add_node("sky_seek", AnimationNodeTimeSeek.new())
		_root.add_node("sky_speed", AnimationNodeTimeScale.new())
		_root.connect_node("sky_seek", 0, "sky_clip")
		_root.connect_node("sky_speed", 0, "sky_seek")
		_root.add_node("sky", AnimationNodeBlend2.new())
		_root.connect_node("sky", 0, "upper_speed")
		_root.connect_node("sky", 1, "sky_speed")
		_root.add_node("upper", layer)
		_root.connect_node("upper", 0, under)
		_root.connect_node("upper", 1, "sky")
		under = "upper"
	# The posture in two: its arms (POSTURE_ARM_BONES, at the gait's share) and the rest of it, each a filter of the
	# other's bones (set by posture()); a node's output feeds one input, so each has its own copy of the pose.
	_root.add_node("pose", AnimationNodeAnimation.new())
	_root.add_node("pose_arms", AnimationNodeAnimation.new())
	var body_add := AnimationNodeAdd2.new()
	body_add.filter_enabled = true
	_root.add_node("posture", body_add)
	_root.connect_node("posture", 0, under)
	_root.connect_node("posture", 1, "pose")
	var arms_add := AnimationNodeAdd2.new()
	arms_add.filter_enabled = true
	for bone in POSTURE_ARM_BONES:
		arms_add.set_filter_path(NodePath("%GeneralSkeleton:" + bone), true)
	_root.add_node("posture_arms", arms_add)
	_root.connect_node("posture_arms", 0, "posture")
	_root.connect_node("posture_arms", 1, "pose_arms")
	var posed := "posture_arms"
	if _vary:
		for layer: String in ["carry", "look"]:
			var poses: Array[String] = VARY_CARRY if layer == "carry" else VARY_LOOK
			var add := AnimationNodeAdd3.new()
			_root.add_node("vary_" + layer, add)
			_root.connect_node("vary_" + layer, 1, posed)
			for k in 2:
				var pose := AnimationNodeAnimation.new()
				pose.animation = poses[k]
				_root.add_node("vary_%s_%d" % [layer, k], pose)
				_root.connect_node("vary_" + layer, 2 * k, "vary_%s_%d" % [layer, k])
			posed = "vary_" + layer
	var action := AnimationNodeOneShot.new()
	action.fadein_time = blend
	action.fadeout_time = blend
	_root.add_node("action_clip", AnimationNodeAnimation.new())
	_root.add_node("action_seek", AnimationNodeTimeSeek.new())
	_root.add_node("action_speed", AnimationNodeTimeScale.new())
	_root.connect_node("action_seek", 0, "action_clip")
	_root.connect_node("action_speed", 0, "action_seek")
	_root.add_node("action", action)
	_root.connect_node("action", 0, posed)
	var struck := "action_speed"
	if upper:
		# The legs under a strike (legs_walk): the base's gait (a copy of it, legs_clip: a node's
		# output feeds one input only) in place of the strike's footwork.
		_root.add_node("legs_clip", AnimationNodeAnimation.new())
		_root.add_node("legs_seek", AnimationNodeTimeSeek.new())
		_root.add_node("legs_speed", AnimationNodeTimeScale.new())
		_root.connect_node("legs_seek", 0, "legs_clip")
		_root.connect_node("legs_speed", 0, "legs_seek")
		var legs := AnimationNodeBlend2.new()
		legs.filter_enabled = true
		for bone in LEG_BONES:
			legs.set_filter_path(NodePath("%GeneralSkeleton:" + bone), true)
		_root.add_node("legs", legs)
		_root.connect_node("legs", 0, "action_speed")
		_root.connect_node("legs", 1, "legs_speed")
		struck = "legs"
	_root.connect_node("action", 1, struck)
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
		tree.set("parameters/sky/blend_amount", 0.0)
	tree.set("parameters/posture/add_amount", 0.0)
	tree.set("parameters/posture_arms/add_amount", 0.0)
	if _vary:
		tree.set("parameters/vary_carry/add_amount", 0.0)
		tree.set("parameters/vary_look/add_amount", 0.0)
		tree.set("parameters/settle/blend_amount", 0.0)
	if upper:
		tree.set("parameters/legs/blend_amount", 0.0)
	tree.active = true


## Whether the library has [param clip] (with its "library/" prefix or not).
func has(clip: String) -> bool:
	return player.has_animation(_name(clip))


## [param clip] as the player knows it: its [member stood_as] copy where the library has one.
func _name(clip: String) -> String:
	if not player.has_animation(clip) and clip.contains("/"):
		clip = clip.get_slice("/", 1)
	if stood_as != "" and player.has_animation(stood_as + clip):
		return stood_as + clip
	return clip


## The clip played for [param clip]: itself, or its [member stood_as] copy.
func as_played(clip: String) -> String:
	return _name(clip)


## The base layer plays [param clip] at [param speed] (of the clip's own):
## crossfaded in over [param fade] (the rig's blend if negative), started
## somewhere along it (seeded) unless [param from_start], or at [param at]
## seconds into it when that is 0 or more (a gait's start, its feet as Idle's).
## The clip already playing only takes the new speed: no restart, no fade (a
## gait's pace changes every frame).
func loop(clip: String, speed := 1.0, fade := -1.0, from_start := false, at := -1.0) -> void:
	clip = _name(clip)
	if clip == _base_clip[_slot] and not from_start:
		set_speed(speed)
		return
	_to_base(clip, speed, fade, at if at >= 0.0 else (-1.0 if from_start else -2.0))


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
	_busy_msec = now_msec() + int(seconds * 1000.0)
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


## The seconds a strike's lead (its [param contact] seconds in, at speed 1)
## takes, played to land in [param lands_in]: its speed kept within the
## strike speeds, as strike() plays it.
static func lead_of(contact: float, lands_in: float) -> float:
	var least := ArtKit.feel("anim_rig.strike_speed_min", STRIKE_SPEED_MIN)
	var most := ArtKit.feel("anim_rig.strike_speed_max", STRIKE_SPEED_MAX)
	return contact / clampf(contact / maxf(lands_in, 0.001), least, most)


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
	var least := ArtKit.feel("anim_rig.strike_speed_min", STRIKE_SPEED_MIN)
	var most := ArtKit.feel("anim_rig.strike_speed_max", STRIKE_SPEED_MAX)
	var before := clampf(contact / maxf(lands_in, 0.001), least, most)
	_recover_speed = clampf((length - contact) / maxf(recover, 0.001), least, most)
	var share := ArtKit.feel("anim_rig.strike_fade_share", STRIKE_FADE_SHARE)
	(_root.get_node("action") as AnimationNodeOneShot).fadein_time = minf(blend, contact / before * share)
	(_root.get_node("action_clip") as AnimationNodeAnimation).animation = clip
	_action_clip = clip
	_set_action_speed(before)
	tree.set("parameters/action_seek/seek_request", 0.0)
	tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_apply()
	var now := now_msec()
	_contact_msec = now + int(contact / before * 1000.0)
	contact_msec = _contact_msec
	contact_at = contact
	var seconds := contact / before + (length - contact) / _recover_speed
	_strike_msec = now + int(seconds * 1000.0)
	_phases = []
	_contact_seek = -1.0
	return seconds


## [param clip] struck with its gather held (a told lunge, 790 amended (7), animation's side): played
## to [param peak] (its gathered pose, seconds into the clip at speed 1) over [param draw] seconds,
## held there, then on to its [param contact] over [param thrust] seconds so the blow lands
## [param lands_in] seconds from now, and what follows fitted to [param recover] seconds as strike()
## fits it. Too short a wind-up for the hold: the draw and the thrust shortened alike, no hold. The
## seconds it takes.
func strike_held(clip: String, peak: float, contact: float, lands_in: float, draw: float, thrust: float,
		recover: float) -> float:
	if strike(clip, contact, lands_in, recover) <= 0.0:
		return 0.0
	var length := player.get_animation(_name(clip)).length
	contact = clampf(contact, 0.0, length)
	peak = clampf(peak, 0.0, contact)
	if draw + thrust > lands_in:
		var cut := maxf(lands_in, 0.001) / maxf(draw + thrust, 0.001)
		draw *= cut
		thrust *= cut
	var now := now_msec()
	_set_action_speed(peak / maxf(draw, 0.001))
	var thrust_from := lands_in - thrust
	_phases = [[now + int(draw * 1000.0), 0.0, peak], [now + int(thrust_from * 1000.0), (contact - peak) / maxf(thrust, 0.001), peak]]
	_contact_seek = contact
	_contact_msec = now + int(lands_in * 1000.0)
	contact_msec = _contact_msec
	_strike_msec = _contact_msec + int((length - contact) / _recover_speed * 1000.0)
	return lands_in + (length - contact) / _recover_speed


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
	_contact_seek = -1.0
	_phases = []


## The upper layer plays [param clip] over the body above the hips at
## [param speed]; "" lets it go. A new clip, or [param from_start], starts it
## from its beginning now; the same clip again only changes its speed (a
## bow's draw timed to the sim's, decision 462). (Nothing on a rig made
## without the layer.)
func upper(clip: String, speed := 1.0, from_start := false) -> void:
	if not _has_upper:
		return
	clip = _name(clip)
	if clip == "" or not player.has_animation(clip):
		_upper_clip = ""
		tree.set("parameters/upper/blend_amount", 0.0)
		return
	_upper_speed = speed
	tree.set("parameters/upper_speed/scale", speed)
	tree.set("parameters/sky_speed/scale", speed)
	if clip != _upper_clip or from_start:
		(_root.get_node("upper_clip") as AnimationNodeAnimation).animation = clip
		_upper_clip = clip
		tree.set("parameters/upper_seek/seek_request", 0.0)
		tree.set("parameters/sky_seek/seek_request", 0.0)
		tree.set("parameters/upper/blend_amount", 1.0)
		_apply()
		return
	tree.set("parameters/upper/blend_amount", 1.0)


## The upper layer held still on [param clip] at [param seconds] into it:
## a pose scrubbed by something other than time (a bow's draw by how far
## the sim has it drawn, decision 462). (Nothing on a rig made without the
## layer.)
func upper_at(clip: String, seconds: float) -> void:
	if not _has_upper:
		return
	upper(clip, 0.0)
	if _upper_clip == "":
		return
	tree.set("parameters/upper_seek/seek_request", seconds)
	tree.set("parameters/sky_seek/seek_request", seconds)
	_apply()


## The upper clip's sky clip (677, pc-character's side): [param clip] played
## in step with the upper clip (its time and speed; upper and upper_at move
## both), mixed over it at [param amount], 0 the upper clip alone, 1 the
## sky's. The bow's flat and sky clips, key for key alike, so a draw turned
## up mid-pull crossfades rather than snaps. "" or 0 lets it go (an input
## at no weight isn't posed); taken up again, it starts where the upper
## clip is.
func sky(clip: String, amount: float) -> void:
	if not _has_upper:
		return
	clip = _name(clip) if clip != "" else ""
	if clip == "" or amount <= 0.0 or not player.has_animation(clip):
		if _sky_amount > 0.0:
			tree.set("parameters/sky/blend_amount", 0.0)
		_sky_amount = 0.0
		return
	if clip != _sky_clip or _sky_amount <= 0.0:
		(_root.get_node("sky_clip") as AnimationNodeAnimation).animation = clip
		_sky_clip = clip
		tree.set("parameters/sky_seek/seek_request", upper_position())
		tree.set("parameters/sky/blend_amount", amount)
		_sky_amount = amount
		_apply()
		return
	_sky_amount = amount
	tree.set("parameters/sky/blend_amount", amount)


## How much of the sky clip is mixed over the upper clip (sky).
func sky_amount() -> float:
	return _sky_amount


## The base layer held still on [param clip] at [param seconds] into it: a
## pose to measure (anim_rig_test's held pieces through the fidgets, 662).
func base_at(clip: String, seconds: float) -> void:
	clip = _name(clip)
	_to_base(clip, 0.0, 0.0, seconds, true)


## The upper layer's clip ("" for none) and its speed.
func upper_clip() -> String:
	return _upper_clip.trim_prefix(stood_as) if stood_as != "" else _upper_clip


func upper_speed() -> float:
	return _upper_speed


## Seconds into the upper layer's clip.
func upper_position() -> float:
	var at: Variant = tree.get("parameters/upper_clip/current_position")
	return float(at) if at != null else 0.0


func upper_off() -> void:
	upper("")


## [param pose] (a clip of one frame, a body's rest bent) added at
## [param weight]; a null pose clears it.
func posture(pose: Animation, weight: float) -> void:
	if pose == null or weight <= 0.0:
		_posture = null
		_posture_weight = 0.0
		tree.set("parameters/posture/add_amount", 0.0)
		tree.set("parameters/posture_arms/add_amount", 0.0)
		return
	if pose != _posture:
		var library := player.get_animation_library("")
		var key := "_posture_" + str(pose.get_instance_id())
		if not library.has_animation(key):
			library.add_animation(key, pose)
		(_root.get_node("pose") as AnimationNodeAnimation).animation = key
		(_root.get_node("pose_arms") as AnimationNodeAnimation).animation = key
		# The body's share: every bone the pose turns but the arms'.
		var body_add := _root.get_node("posture") as AnimationNodeAdd2
		for track in pose.get_track_count():
			var path := pose.track_get_path(track)
			var bone := path.get_concatenated_subnames()
			body_add.set_filter_path(NodePath(str(path.get_concatenated_names()) + ":" + bone), not bone in POSTURE_ARM_BONES)
		_posture = pose
	_posture_weight = weight
	tree.set("parameters/posture/add_amount", weight * posture_body())
	tree.set("parameters/posture_arms/add_amount", weight * _posture_arms)


## The posture's arm share now: 1 at rest, 0 through a gait (gaits), eased between over the base's crossfade.
func posture_arms() -> float:
	return _posture_arms


## The posture's body share now (POSTURE_GAIT_BODY): 1 at rest, POSTURE_GAIT_BODY through a gait, eased with the arms.
func posture_body() -> float:
	return lerpf(POSTURE_GAIT_BODY, 1.0, _posture_arms)


## Eases the posture's arm share toward its mark by [param delta] seconds (_process; a test steps it).
func _ease_posture_arms(delta: float) -> void:
	var mark := 0.0 if base_clip() in gaits else 1.0
	if is_equal_approx(_posture_arms, mark):
		return
	_posture_arms = move_toward(_posture_arms, mark, delta / maxf(blend, 0.01))
	if _posture != null:
		tree.set("parameters/posture_arms/add_amount", _posture_weight * _posture_arms)
		tree.set("parameters/posture/add_amount", _posture_weight * posture_body())


## Whether this rig draws the variation (VARY_CARRY; make's vary, and vary_on).
func varies() -> bool:
	return _vary and vary_on


## The variation's weight [param layer] ("carry" or "look") now, -1 to +1 (look before look_held).
func vary_weight(layer: String) -> float:
	return float(_vary_w[layer]["now"]) if _vary else 0.0


## Steps the variation by [param delta] seconds (_process; a test steps it): a footfall of a gait draws, a stand's
## timers draw (977 amended (2)), else it eases to 0.
## A people's stop (869 amended (4); the coordinator on ui-design's look of 977, 11-18: the body stood leaning 19
## degrees through STOP_HOLD, held with the gait, then dropped to 8 inside the stand's 0.15 s blend, the trunk's
## largest 40 ms change 5.3 to 8.1 times a mid-stride's): from the hold's first frame the trunk (SETTLE_BONES, above
## the hips: the feet stay the held gait's) eases to [param clip]'s, evenly over [param seconds] (the hold and the
## blend), so the runner comes upright. Called each held frame; the rest is the rig's own: rising while the base
## plays the gait it began over or the stand, then, the stand's blend done, given back to the stand over the blend
## (the stand under it by then); moving again (unsettle) or anything else on the base, given back over the blend. A
## rig without the layer (not a people's) ignores it.
func settle(clip: String, seconds: float) -> void:
	if not _vary:
		return
	clip = _name(clip)
	if not player.has_animation(clip):
		return
	if _settle_rising and clip == _settle_clip:
		return
	if clip != _settle_clip:
		_settle_clip = clip
		(_root.get_node("settle_clip") as AnimationNodeAnimation).animation = clip
	_settle_seconds = maxf(seconds, 0.01)
	_settle_from = str(_base_clip[_slot])
	_settle_rising = true
	_settle_stood = 0.0


## Moving again: the settle given back over the blend, the free leg's too.
func unsettle() -> void:
	_settle_rising = false
	_leg_rising = false


## 869 amended (5) (TASK 11, the companion's jog on the spot at her step aside): a gait held with a foot down, the
## other leg ([param side], "Left" or "Right"), caught in the air, eases over LEG_EASE to its own stance's pose, the
## base clip's rotations for it half a cycle on (so both feet stand as the gait plants them), and its ankle is put
## down to LEG_SOLE over the ground by a two-bone reach in the knee's own plane, the foot's turn kept. The planted
## leg and the hips stay the gait's. Called each held frame; given back over the blend when the body moves on
## (unsettle) or the base plays anything else (the stand's blend: the stand's legs take over). A different leg
## while one eases out waits for it to be out. A rig without the layer (not a people's) ignores it.
func settle_leg(side: String) -> void:
	if not _vary or not side in ["Left", "Right"]:
		return
	var clip := str(_base_clip[_slot])
	if not player.has_animation(clip):
		return
	if _leg > 0.0 and (side != _leg_side or clip != _leg_clip):
		_leg_rising = false
		return
	var length := player.get_animation(clip).length
	_leg_side = side
	_leg_clip = clip
	_leg_at = fposmod(base_position() + length / 2.0, length)
	_leg_rising = true


## The free leg's share now (settle_leg).
func leg_settled() -> float:
	return _leg


func _leg_ease(delta: float) -> void:
	if not _vary or (_leg <= 0.0 and not _leg_rising):
		return
	if _leg_rising and str(_base_clip[_slot]) == _leg_clip:
		_leg = minf(1.0, _leg + delta / LEG_EASE)
	else:
		_leg_rising = false
		_leg = maxf(0.0, _leg - delta / maxf(blend, 0.01))


## A side's leg bones and their rests' heights (settle_leg), found once; empty where the skeleton lacks one.
func _leg_of(sk: Skeleton3D, side: String) -> Array:
	if not _leg_bones.has(side):
		var bones := []
		for part: String in ["UpperLeg", "LowerLeg", "Foot", "Toes"]:
			bones.append(sk.find_bone(side + part))
		var found: Array = [] if bones.has(-1) else [bones, sk.get_bone_global_rest(bones[2]).origin.y,
				sk.get_bone_global_rest(bones[3]).origin.y]
		_leg_bones[side] = found
	return _leg_bones[side]


## The lower of foot and toes over their rests' (the ground), skeleton space: anim_rig_test _test_gait_phases' sole.
static func _sole_of(sk: Skeleton3D, leg: Array) -> float:
	return minf(sk.get_bone_global_pose(leg[0][2]).origin.y - float(leg[1]), sk.get_bone_global_pose(leg[0][3]).origin.y - float(leg[2]))


func _settle_free_leg() -> void:
	if _leg <= 0.0 or _leg_side == "" or not player.has_animation(_leg_clip):
		return
	var sk := _trunk_skeleton()
	if sk == null:
		return
	var leg := _leg_of(sk, _leg_side)
	if leg.is_empty():
		return
	var bones: Array = leg[0]
	var held := player.get_animation(_leg_clip)
	var before := _sole_of(sk, leg)
	var parts := ["UpperLeg", "LowerLeg", "Foot", "Toes"]
	# Coming down it swings over first, then down; stood out of the hold (the base the stand's) it steps, lifted.
	var turn := minf(1.0, _leg / LEG_TURN) if _leg_rising else _leg
	var lift := LEG_STEP * sin(PI * _leg) if not _leg_rising and str(_base_clip[_slot]) != _leg_clip else 0.0
	for i in 4:
		var track := held.find_track(NodePath("%GeneralSkeleton:" + _leg_side + parts[i]), Animation.TYPE_ROTATION_3D)
		if track >= 0:
			var own := held.rotation_track_interpolate(track, _leg_at)
			sk.set_bone_pose_rotation(bones[i], sk.get_bone_pose_rotation(bones[i]).slerp(own, turn).normalized())
	var rise := lerpf(before, LEG_SOLE, _leg) + lift - _sole_of(sk, leg)
	if absf(rise) > 0.0002:
		_reach_ankle(sk, bones[0], bones[1], bones[2], rise)


## The ankle (foot) moved [param rise] metres up (down when under 0) by the thigh and the shin, the knee kept on its
## side of the plane through the hip, the knee and the new ankle; the foot's turn kept. Short of reach it goes as far
## as the leg does.
static func _reach_ankle(sk: Skeleton3D, upper: int, lower: int, foot: int, rise: float) -> void:
	var hip_pose := sk.get_bone_global_pose(upper)
	var hip := hip_pose.origin
	var knee := sk.get_bone_global_pose(lower).origin
	var ankle_pose := sk.get_bone_global_pose(foot)
	var thigh := (knee - hip).length()
	var shin := (ankle_pose.origin - knee).length()
	var to := ankle_pose.origin + Vector3(0.0, rise, 0.0) - hip
	var plane := (knee - hip).cross(to)
	if thigh < 0.0001 or shin < 0.0001 or to.length_squared() < 0.000001 or plane.length_squared() < 0.0000000001:
		return
	plane = plane.normalized()
	var reach := clampf(to.length(), absf(thigh - shin) + 0.0001, thigh + shin - 0.0001)
	var along := to.normalized()
	var bend := acos(clampf((thigh * thigh + reach * reach - shin * shin) / (2.0 * thigh * reach), -1.0, 1.0))
	var new_knee := hip + along.rotated(plane, -bend) * thigh
	sk.set_bone_global_pose(upper, Transform3D(Basis(Quaternion((knee - hip).normalized(), (new_knee - hip).normalized())) * hip_pose.basis, hip))
	var shin_pose := sk.get_bone_global_pose(lower)
	var ankle_now := sk.get_bone_global_pose(foot).origin
	var new_ankle := hip + along * reach
	sk.set_bone_global_pose(lower, Transform3D(Basis(Quaternion((ankle_now - shin_pose.origin).normalized(),
			(new_ankle - shin_pose.origin).normalized())) * shin_pose.basis, shin_pose.origin))
	sk.set_bone_global_pose(foot, Transform3D(ankle_pose.basis, sk.get_bone_global_pose(foot).origin))


## The stop's settle share now (settle).
func settled() -> float:
	return _settle


func _settle_ease(delta: float) -> void:
	if not _vary or (_settle <= 0.0 and not _settle_rising):
		return
	var base := str(_base_clip[_slot])
	if base == _settle_clip:
		_settle_stood += delta
	if _settle_rising and (base == _settle_from or base == _settle_clip):
		_settle = minf(1.0, _settle + delta / _settle_seconds)
		if base == _settle_clip and _settle >= 1.0 and _settle_stood >= blend:
			_settle_rising = false
	else:
		_settle_rising = false
		_settle = maxf(0.0, _settle - delta / maxf(blend, 0.01))
	tree.set("parameters/settle/blend_amount", _settle)


## The settle's trunk as the stand's from the hips up, the feet the held gait's: the people's jog leans most at the
## pelvis (pitched forward and the spine bent back over it), so the stand's spine on the held pelvis leaned further
## (19.4 degrees to 23.0 in view_world_test). After each pose the Spine is turned by the held hips' turn back to the
## stand's (its clip's hips where it plays), at the settle's share: so much of the trunk faces as the stand's does,
## on hips and legs untouched. Through the stand's blend the hips come round themselves and the turn goes to none.
func _settle_trunk() -> void:
	if _settle <= 0.0 or _settle_clip == "" or not player.has_animation(_settle_clip):
		return
	var sk := _trunk_skeleton()
	if sk == null:
		return
	var hips := sk.find_bone("Hips")
	var spine := sk.find_bone("Spine")
	var stand := player.get_animation(_settle_clip)
	var track := stand.find_track(NodePath("%GeneralSkeleton:Hips"), Animation.TYPE_ROTATION_3D)
	if hips < 0 or spine < 0 or track < 0:
		return
	var at: Variant = tree.get("parameters/settle_clip/current_position")
	var stood := stand.rotation_track_interpolate(track, float(at) if at != null else 0.0)
	var turn := (sk.get_bone_pose_rotation(hips).inverse() * stood).normalized()
	sk.set_bone_pose_rotation(spine, (Quaternion.IDENTITY.slerp(turn, _settle) * sk.get_bone_pose_rotation(spine)).normalized())


## The body's skeleton (its GeneralSkeleton), found once; null where it has none.
func _trunk_skeleton() -> Skeleton3D:
	if _settle_skeleton == null:
		var root := player.get_node_or_null(player.root_node)
		_settle_skeleton = root.find_child("GeneralSkeleton", true, false) as Skeleton3D if root != null else null
	return _settle_skeleton


func _vary_ease(delta: float) -> void:
	if not _vary:
		return
	var clip: String = _base_clip[_slot]
	var length := player.get_animation(clip).length if clip != "" and player.has_animation(clip) else 0.0
	var walk := not gaits.is_empty() and base_clip() == gaits[0]
	var gait := vary_on and base_clip() in gaits and length > 0.0 and (vary_calm or not walk)
	var stand := not gait and vary_on and vary_calm and seen and vary_stand != "" and base_clip() == vary_stand \
			and length > 0.0 and not striking() and _settle <= 0.0 and not _settle_rising
	var mode := "gait" if gait else ("stand" if stand else "")
	if mode != _vary_mode:
		_vary_mode = mode
		_vary_step = ["", -1]
		_vary_look_in = 0
		_stand_in = {"look": 0.0, "carry": 0.0}
		_stand_cycle = -1
		for layer: String in _vary_w:
			(_vary_w[layer] as Dictionary)["from"] = (_vary_w[layer] as Dictionary)["now"]  # Out from here (or a draw).
		if _stand_rate != 1.0:
			_stand_rate = 1.0
			tree.set("parameters/%s_speed/scale" % _slot_name(_slot), _base_speed[_slot])
	elif mode == "" and _vary_zeroed:
		return
	var step_s := length / 2.0 / maxf(absf(_base_speed[_slot]), 0.01)
	if gait:
		var half := int(floor(base_position() / (length / 2.0)))
		if clip != _vary_step[0] or half != _vary_step[1]:
			_vary_step = [clip, half]
			_vary_draw("carry")
			_vary_look_in -= 1
			if _vary_look_in <= 0:
				var steps := VARY_WALK_LOOK_STEPS if walk else VARY_LOOK_STEPS
				_vary_look_in = _vary_rng.randi_range(steps.x, steps.y)
				_vary_draw("look", VARY_WALK_LOOK if walk else 1.0)
	elif stand:
		for layer: String in ["look", "carry"]:
			_stand_in[layer] = float(_stand_in[layer]) - delta
			if float(_stand_in[layer]) <= 0.0:
				var every_s := VARY_STAND_LOOK if layer == "look" else VARY_STAND_CARRY
				_stand_in[layer] = _vary_rng.randf_range(every_s.x, every_s.y)
				_vary_draw(layer, VARY_WALK_LOOK if layer == "look" else 1.0)
		# A new cycle of the stand clip (its position wraps): its rate drawn again.
		var at := base_position()
		if _stand_cycle < 0 or at < _stand_last:
			_stand_cycle += 1
			_stand_rate = _vary_rng.randf_range(VARY_STAND_RATE.x, VARY_STAND_RATE.y)
			_vary_draws["rate"] = int(_vary_draws["rate"]) + 1
			if vary_log:
				_vary_print("rate", 1.0, _stand_rate)
		_stand_last = at
		tree.set("parameters/%s_speed/scale" % _slot_name(_slot), _base_speed[_slot] * _stand_rate)
	for layer: String in _vary_w:
		var w: Dictionary = _vary_w[layer]
		if mode != "":
			var over := (VARY_STAND_LOOK_EASE if layer == "look" else VARY_STAND_CARRY_EASE) if stand \
					else step_s * (VARY_WALK_EASE if walk and layer == "look" else VARY_EASE)
			w["eased"] = minf(1.0, float(w["eased"]) + delta / maxf(over, 0.01))
			w["now"] = lerpf(float(w["from"]), float(w["to"]), smoothstep(0.0, 1.0, float(w["eased"])))
		else:
			# Out within the blend from whatever size it was drawn to (the walk's and the stand's look twice the run's).
			w["now"] = move_toward(float(w["now"]), 0.0, delta / maxf(blend, 0.01) * maxf(1.0, absf(float(w["from"]))))
			w["to"] = 0.0
			w["eased"] = 1.0
	_vary_zeroed = mode == "" and float(_vary_w["carry"]["now"]) == 0.0 and float(_vary_w["look"]["now"]) == 0.0
	tree.set("parameters/vary_carry/add_amount", float(_vary_w["carry"]["now"]))
	tree.set("parameters/vary_look/add_amount", float(_vary_w["look"]["now"]) * (1.0 - clampf(look_held, 0.0, 1.0)))


## A new weight for [param layer], drawn to within [param size] each way (the walk's and the stand's look larger).
func _vary_draw(layer: String, size := 1.0) -> void:
	var w: Dictionary = _vary_w[layer]
	w["from"] = w["now"]
	w["to"] = _vary_rng.randf_range(-1.0, 1.0) * size
	w["eased"] = 0.0
	_vary_draws[layer] = int(_vary_draws[layer]) + 1
	if vary_log:
		_vary_print(layer, float(w["from"]), float(w["to"]))


## vary_log's line: nothing of whose body it is (the rig's own node number, its model's file, its clip).
func _vary_print(layer: String, from: float, to: float) -> void:
	print("VARY_LOG t=%d body=%d kind=%s clip=%s mode=%s layer=%s from=%+.3f to=%+.3f" % [
		now_msec(), get_instance_id(), kind, base_clip(), _vary_mode, layer, from, to])


## How much of a strike's legs give way to the base's (0 its own footwork,
## 1 the base's gait under it): a body striking while it steps walks. Only
## on a rig with the upper layer (a humanoid).
func legs_walk(amount: float) -> void:
	if not _has_upper:
		return
	var was := _legs
	_legs = clampf(amount, 0.0, 1.0)
	var clip: String = _base_clip[_slot]
	if _legs > 0.0 and clip != "":
		var node := _root.get_node("legs_clip") as AnimationNodeAnimation
		if node.animation != clip or was <= 0.0:
			# The base's gait, in step with it from here.
			node.animation = clip
			tree.set("parameters/legs_seek/seek_request", base_position())
		tree.set("parameters/legs_speed/scale", _base_speed[_slot])
	tree.set("parameters/legs/blend_amount", _legs)


func legs_amount() -> float:
	return _legs


## Milliseconds clips are timed by: the wall clock in play; under movie maker (a reel, tools/clip.sh)
## the frames' own time, each frame its fixed 1/fps, since a reel draws slower than real time and a
## clip timed by the wall would end early (the boar king's hook drawn 2 ticks of its 9). Read once a
## frame it holds through the frame, so every rig and view the same frame sees the same time.
static func now_msec() -> int:
	if _clock_movie < 0:
		_clock_movie = 1 if Engine.get_write_movie_path() != "" else 0
	if _clock_movie == 0:
		return Time.get_ticks_msec()
	var frame := Engine.get_process_frames()
	if _clock_frame < 0:
		_clock_msec = Time.get_ticks_msec()
	elif frame != _clock_frame:
		var tree := Engine.get_main_loop() as SceneTree
		var delta := tree.root.get_process_delta_time() if tree != null else 0.0
		_clock_msec += int(roundf(delta * 1000.0 * (frame - _clock_frame)))
	_clock_frame = frame
	return _clock_msec


## Whether a clip played once or a strike is still going.
func busy() -> bool:
	return now_msec() < _busy_msec or striking()


func striking() -> bool:
	return now_msec() < _strike_msec


## The clip on top: a strike's while it plays, else the base layer's.
func playing() -> String:
	return (_action_clip if striking() else _base_clip[_slot]).trim_prefix(stood_as) if stood_as != "" else (_action_clip if striking() else _base_clip[_slot])


## The base layer's clip, whatever plays over it.
func base_clip() -> String:
	return _base_clip[_slot].trim_prefix(stood_as) if stood_as != "" else _base_clip[_slot]


## The speed of the clip on top (below 0 backwards).
func speed() -> float:
	return _action_speed if striking() else _base_speed[_slot]


## The base layer's own speed (below 0 backwards), a strike on top or not: a gait's rate.
func base_speed() -> float:
	return _base_speed[_slot]


## Seconds into the clip on top.
func position() -> float:
	return _action_time() if striking() else base_position()


## Seconds into the base layer's clip, whatever plays over it (a gait's
## footfalls go on under a strike).
func base_position() -> float:
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
	while not _phases.is_empty() and now_msec() >= int(_phases[0][0]):
		var phase: Array = _phases.pop_front()
		_set_action_speed(float(phase[1]))
		if phase.size() > 2:
			tree.set("parameters/action_seek/seek_request", float(phase[2]))
	if _contact_msec >= 0 and now_msec() >= _contact_msec:
		_phases = []
		_contact_msec = -1
		_set_action_speed(_recover_speed)
		if _contact_seek >= 0.0:
			tree.set("parameters/action_seek/seek_request", _contact_seek)
		_contact_seek = -1.0
	_since += delta
	_frames += 1
	_ease_posture_arms(delta)
	_vary_ease(delta)
	_settle_ease(delta)
	_leg_ease(delta)
	if every <= 1 or _frames % every == 0:
		tree.advance(_since)
		_since = 0.0
		_settle_trunk()
		_settle_free_leg()


## A change takes now, not at the tree's next frame: what plays (and where)
## is what was asked for straight away.
func _apply() -> void:
	tree.advance(0.0)
	_settle_trunk()
	_settle_free_leg()


static func _slot_name(slot: int) -> String:
	return "a" if slot == 0 else "b"
