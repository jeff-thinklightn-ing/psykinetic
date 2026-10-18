class_name CreatureView
extends Node
## A wild creature's puppet drawn from its creature.<kind> art slot (decision
## 319) and played from what the sim replicates: its AnimationPlayer's clips
## found by the slot's names for them (any of a clip's "names", after any
## library or armature prefix, as ArtCheck finds them), and where the art
## has none, the slot's fallback (a graze is an idle, a charge a run, an
## alert or a howl an idle with the head up, a hit a flinch). Its clips play
## through an AnimRig of its own (decision 390; no upper layer, a quadruped
## has no such bones): the gaits and rests as the base, a blow as a strike
## over it, landing at the clip's "contact".
## Client3D makes one under each such puppet, beside its Body, sets its
## rig's level of detail (rig.every) and calls frame() every drawn frame and
## the one-shots (swing, wind, charge, hit, die) from the entity's signals.

## Moving faster than this (tiles a second) walks; faster than RUN_ABOVE runs.
const WALKING := 0.4
const RUN_ABOVE := 2.2
## The tiles a second each moving clip is played at speed 1 for, and how far
## its speed may stretch either way.
const WALK_PACE := 1.2
const RUN_PACE := 3.5
const SPEED_MIN := 0.6
const SPEED_MAX := 1.8
## A charge (cried "charge"): run this much faster for CHARGE_SECONDS, a
## lunge forward of LUNGE metres as it goes.
const CHARGE_SPEED := 1.4
const CHARGE_SECONDS := 1.5
const LUNGE := 0.25
## A rout (cried "rout"): the herd bolting, a run for this long.
const BOLT_SECONDS := 2.0
## The head-up stand-in for an alert or a howl: the body tipped back this
## much (radians, its front up), eased in and out.
const HEAD_UP := 0.12
const HEAD_UP_SECONDS := 0.3
## The flinch stand-in for a hit: tipped back and pushed back a little, then
## back where it was.
const FLINCH := 0.15
const FLINCH_BACK := 0.06
const FLINCH_SECONDS := 0.25
const BLEND := 0.2
## Where a blow lands in its clip when the slot's clip names no "contact":
## this far through it.
const CONTACT := 0.5

## The clip a slot clip falls back to when the art has none of its own.
const FALLBACKS := {"graze": "idle", "feed": "graze", "trot": "walk", "charge": "run", "alert": "idle",
	"howl": "idle", "sit": "idle", "lie": "idle"}
## The slot clips that loop; the rest (attack, hit, death) play once.
const LOOPED: Array[String] = ["idle", "walk", "trot", "run", "charge", "graze", "feed", "alert", "howl", "sit", "lie"]
## Played with the head up when it stands in for these.
const HEAD_UP_FOR: Array[String] = ["alert", "howl"]

var slot := ""
## Slot clip name to the rig's name for it.
var clips := {}
## Plays the clips (null when the art has none).
var rig: AnimRig
## Turned and tipped by the stand-in tweens; its child is the art.
var _pose: Node3D
## Slot clip name to how far through it its blow lands (the slot's "contact").
var _contact := {}
var _busy_until := 0
var _charge_until := 0
var _bolt_until := 0
var _dead := false
var _head_up := false
var _last_at := Vector3.INF
var _last_ms := 0
var _speed := 0.0


## For [param art] (an instance of [param creature_slot]) under
## [param pose], the node the stand-ins tip.
func _init(creature_slot: String, art: Node3D, pose: Node3D) -> void:
	name = "CreatureView"
	slot = creature_slot
	_pose = pose
	var players := art.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	# The art's own player gives up its clips to the rig's (one library: a
	# second's names after the first's).
	var own := players[0] as AnimationPlayer
	var root := own.get_node(own.root_node) as Node3D
	var library := AnimationLibrary.new()
	for name in own.get_animation_list():
		var bare := str(name).substr(str(name).find("/") + 1)
		if not library.has_animation(bare):
			library.add_animation(bare, own.get_animation(name))
	own.get_parent().remove_child(own)
	own.free()
	var wanted: Array = ArtKit.spec(slot).get("clips", [])
	for clip: Dictionary in wanted:
		if clip.has("contact"):
			_contact[str(clip["name"])] = float(clip["contact"])
	clips = clip_map(wanted, library.get_animation_list())
	# A glTF's clips come in playing once; these loop (set on the shared
	# clips, the same for every instance of the art, before the rig is made).
	for clip: String in clips:
		library.get_animation(clips[clip]).loop_mode = Animation.LOOP_LINEAR if clip in LOOPED else Animation.LOOP_NONE
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(slot) ^ art.get_instance_id()
	rig = AnimRig.make(root if root != null else art, library, BLEND, false, rng)
	var idle := resolve("idle")
	if idle != "":
		rig.loop(idle)


## Each slot clip (the manifest's "clips": {name, names}) to the first of
## [param animations] answering to one of its names, ignoring case and any
## "library/" or "Armature|" before it; a clip with none is left out.
static func clip_map(wanted: Array, animations: PackedStringArray) -> Dictionary:
	var bare := {}
	for animation in animations:
		var plain := animation.substr(animation.rfind("/") + 1)
		plain = plain.substr(plain.rfind("|") + 1).to_lower()
		if not bare.has(plain):
			bare[plain] = animation
	var out := {}
	for clip: Dictionary in wanted:
		for name: String in clip.get("names", []):
			if bare.has(name.to_lower()):
				out[str(clip["name"])] = bare[name.to_lower()]
				break
	return out


## The animation [param clip] plays as: its own, else its fallback's, else
## "" (and whether that is a stand-in, so the head comes up for an alert).
func resolve(clip: String) -> String:
	var at := clip
	for i in 4:
		if clips.has(at):
			return clips[at]
		at = str(FALLBACKS.get(at, ""))
		if at == "":
			break
	return ""


## Every drawn frame: what it does now from [param puppet]'s movement and
## [param monster]'s alert and pose, unless a one-shot has it.
func frame(puppet: Node3D, monster: Monster) -> void:
	if rig == null or _dead:
		return
	var now := Time.get_ticks_msec()
	var seconds := (now - _last_ms) / 1000.0
	if _last_at != Vector3.INF and seconds > 0.0:
		var step := Vector2(puppet.position.x - _last_at.x, puppet.position.z - _last_at.z)
		_speed = lerpf(_speed, step.length() / seconds, clampf(seconds * 12.0, 0.0, 1.0))
	_last_at = puppet.position
	_last_ms = now
	if now < _busy_until:
		return
	var alert := monster.alert if monster != null else Monster.Alert.IDLE
	var clip := "idle"
	var scale := 1.0
	if _speed > WALKING:
		var running := _speed > RUN_ABOVE or alert == Monster.Alert.FLEEING or now < _charge_until or now < _bolt_until
		clip = "run" if running else "walk"
		scale = clampf(_speed / (RUN_PACE if running else WALK_PACE), SPEED_MIN, SPEED_MAX)
		if now < _charge_until:
			clip = "charge" if clips.has("charge") else "run"
			scale = maxf(scale, CHARGE_SPEED)
	elif monster != null and monster.pose == Monster.Pose.SIT:
		clip = "graze" if resolve("graze") != "" else "feed"
	elif alert == Monster.Alert.SUSPICIOUS:
		clip = "alert"
	_set_head_up(clip in HEAD_UP_FOR and not clips.has(clip))
	_loop(clip, scale)


## Plays [param clip] (a slot clip, through its fallbacks) looping at
## [param scale]: a clip already playing only takes the new speed.
func _loop(clip: String, scale: float) -> void:
	var animation := resolve(clip)
	if animation != "":
		rig.loop(animation, scale)


## [param clip] once through, at [param scale], busy till it ends.
func _once(clip: String, scale := 1.0) -> bool:
	var animation := resolve(clip)
	if rig == null or animation == "" or _dead:
		return false
	_busy_until = Time.get_ticks_msec() + int(rig.once(animation, scale) * 1000.0)
	return true


## A blow (GridEntity.swung): its attack at its own pace, unless a wound-up
## one or a hit is playing.
func swing() -> void:
	if rig != null and not rig.striking() and Time.get_ticks_msec() >= _busy_until:
		_strike(-1.0)


## A wound-up blow given up (GridEntity.winding with 0 ticks; decision 392):
## free for the gait or rest at once.
func unwind() -> void:
	_busy_until = 0
	if rig != null:
		rig.cancel_strike()


## A blow wound up over [param seconds] (GridEntity.winding: a brute's HEAVY
## tactic, a heavy weapon's wind-up): the attack struck so that its contact,
## the blow, lands as the sim's does.
func wind(seconds: float) -> void:
	_strike(maxf(seconds, 0.05))


## The attack struck over the gait or rest, its contact landing in
## [param lands_in] seconds (at its own pace if negative), the rest of it at
## the same speed.
func _strike(lands_in: float) -> void:
	var animation := resolve("attack")
	if rig == null or animation == "" or _dead:
		return
	var length := rig.length(animation)
	var contact := length * clampf(float(_contact.get("attack", CONTACT)), 0.0, 1.0)
	if lands_in < 0.0:
		lands_in = contact
	var speed := contact / lands_in if lands_in > 0.0 else 1.0
	rig.strike(animation, contact, lands_in, (length - contact) / maxf(speed, 0.001))


## A charge (cried "charge"): a faster run for a while, lunging as it goes
## when the art has no charge of its own.
func charge() -> void:
	_charge_until = Time.get_ticks_msec() + int(CHARGE_SECONDS * 1000.0)
	_busy_until = 0
	if clips.has("charge") or _pose == null:
		return
	var tween := create_tween()
	tween.tween_property(_pose, "position:x", LUNGE, CHARGE_SECONDS * 0.3).set_ease(Tween.EASE_OUT)
	tween.tween_property(_pose, "position:x", 0.0, CHARGE_SECONDS * 0.7).set_ease(Tween.EASE_IN_OUT)


## The herd bolting (cried "rout"): run.
func bolt() -> void:
	_bolt_until = Time.get_ticks_msec() + int(BOLT_SECONDS * 1000.0)


## A blow taken: its hit clip, else a flinch (tipped and pushed back).
func hit() -> void:
	if _dead:
		return
	if clips.has("hit"):
		# Not under a blow (it would play unseen, then show held as the blow
		# fades), nor over one played once.
		if Time.get_ticks_msec() >= _busy_until and not rig.striking():
			_once("hit")
		return
	if _pose == null:
		return
	var tween := create_tween().set_parallel(true)
	var rest := -HEAD_UP if _head_up else 0.0
	tween.tween_property(_pose, "rotation:x", rest - FLINCH, FLINCH_SECONDS * 0.3)
	tween.tween_property(_pose, "position:x", -FLINCH_BACK, FLINCH_SECONDS * 0.3)
	tween.chain().tween_property(_pose, "rotation:x", rest, FLINCH_SECONDS * 0.7)
	tween.parallel().tween_property(_pose, "position:x", 0.0, FLINCH_SECONDS * 0.7)


## Dead: its death clip once, held on its last frame; the seconds it takes
## (0 with none, and the puppet falls over as a body without art does).
func die() -> float:
	if rig == null or resolve("death") == "":
		return 0.0
	rig.cancel_strike()
	var seconds := rig.once(resolve("death"))
	_dead = true
	_busy_until = 1 << 62
	return seconds


## The head up (the stand-in for an alert or a howl), eased.
func _set_head_up(up: bool) -> void:
	if up == _head_up or _pose == null:
		return
	_head_up = up
	create_tween().tween_property(_pose, "rotation:x", -HEAD_UP if up else 0.0, HEAD_UP_SECONDS).set_ease(Tween.EASE_IN_OUT)
