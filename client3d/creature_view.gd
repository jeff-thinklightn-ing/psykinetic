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
## Teetering on a rim (783 amended) with no teeter clip: its walk at this speed, in place.
const TEETER_PACE := 1.6
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
## A led blow's coil (338 amended (6)): over the lead the body draws back this
## share of its length, sinks this share of its height and dips its head and shoulders (radians),
## a crouch; then springs a third of it past rest as the blow lands, settling back over
## COIL_SETTLE seconds (the coordinator on the reel: "a crouch-and-spring at play distance").
const COIL_BACK := 0.08
const COIL_SINK := 0.06
const COIL_DIP := 0.18
const COIL_SETTLE := 0.25
## A pant (cried "pant": the old grey's opening after a lunge, with no clip of its own): its idle
## this slow, the head this far down (radians), eased in and out over PANT_EASE seconds.
const PANT_PACE := 0.55
const PANT_DIP := 0.16
const PANT_EASE := 0.3
## Steadied (843, animation's side: a boss out of a stagger, cried "steady" till "steady_over"): the
## set beat, planted and shaken off over STEADY_SECONDS, sunk STEADY_SINK of its height and rolled
## STEADY_SHAKE (radians) side to side about its length and twisted STEADY_TWIST about the upright
## (what reads from the game's camera, above); then braced, a share STEADY_HOLD of the
## sink kept and the head STEADY_DIP low, till "steady_over" or STEADY_CAP seconds (a lost cry). A
## blow on it meanwhile rocks it back ROCK (radians, ROCK_BACK of its length) and it holds.
const STEADY_SECONDS := 0.4
const STEADY_SINK := 0.1
const STEADY_SHAKE := 0.2
const STEADY_TWIST := 0.22
const STEADY_HOLD := 0.4
const STEADY_DIP := 0.08
const STEADY_CAP := 6.0
const STEADY_SETTLE := 0.25
const ROCK := 0.12
const ROCK_BACK := 0.06
const ROCK_SECONDS := 0.24
const BLEND := 0.2
## How squarely against its facing a walk runs to be drawn backing off (a cosine).
const BACKING_DOT := 0.5
## Where a blow lands in its clip when the slot's clip names no "contact":
## this far through it.
const CONTACT := ArtKit.CLIP_CONTACT

## The clip a slot clip falls back to when the art has none of its own.
const FALLBACKS := {"graze": "idle", "feed": "graze", "trot": "walk", "charge": "run", "alert": "idle",
	"howl": "idle", "sit": "idle", "lie": "idle"}
## The slot clips that loop; the rest (attack, hit, death) play once.
const LOOPED: Array[String] = ["idle", "walk", "trot", "run", "charge", "graze", "feed", "alert", "howl", "sit", "lie",
	"sleep", "winded", "dazed", "back_off"]
## A move's tell (780 amended (6): an apex beast's World.telegraph, its "kind" the move): the
## slot clip it plays, its contact landing on the telegraph's lands tick; a move not named here
## plays the clip of its own name (swipe, slam). Only a slot listing the clip has one.
const TELL_CLIPS := {"charge": "charge_tell", "pounce": "crouch_tell"}
## Tells whose clip is all wind-up (the slot gives no contact): their end is the move's start.
const TELL_ENDS_AT_LANDING: Array[String] = ["charge_tell", "crouch_tell"]
## Monster.Pose.DOWN (enemy-ai's 764: a deer hurt past its sprint, lying a while, to be
## finished): drawn lying on its belly, alive (creature_life.gd, over its idle), lain down over
## DOWN_SECONDS, got up over UP_SECONDS; first seen down it lies at once; dying it unfolds over
## DIE_UNFOLD_SECONDS as its death plays, to lie on its side as the dead do.
const DOWN_SECONDS := 0.8
const UP_SECONDS := 0.7
const DIE_UNFOLD_SECONDS := 0.35
const Life := preload("res://client3d/creature_life.gd")
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
## Slot clip name to the speed its loop plays at, 1 where the slot names none (its clip's
## "speed": the old grey's idle slower than his pack's, so he reads as the old one).
var _pace := {}
var _busy_until := 0
## The telegraph whose tell is playing (0 for none), and when the tell's clip ends (msec).
var _tell_id := 0
var _tell_until := 0
var _charge_until := 0
## Panting till (msec, the rigs' clock): the old grey's opening after a lunge.
var _pant_until := 0
## Steadied till (msec, the rigs' clock; 0: not), and its tween (843).
var _steady_until := 0
var _steady: Tween
## The pose's own yaw (Client3D turns the art's front to +X): a twist is about it.
var _rest_yaw := 0.0
## A slot clip played once when the one playing ends (the hill cat's recover after its leap).
var _then := ""
## Plain blows struck: a slot with a bite alternates its swipe (attack) and bite.
var _blows := 0
var _bolt_until := 0
## Dazed till (msec), for a view drawn without its monster: a crash's stun (the boar king's charge
## into the terrain), its slot's dazed looping. With its monster, its stun in ticks says (_dazed).
var _dazed_until := 0
## Dazed this frame: its monster's stun, cause &"crash", not yet worn off (in game ticks, so a reel
## run slower than real time holds it as long), else _dazed_until.
var _dazed := false
var _dead := false
var _head_up := false
var _last_at := Vector3.INF
var _last_ms := 0
var _speed := 0.0
## Its last drawn step's way on the ground (x, z), for a back-off (_backing).
var _way := Vector2.ZERO
var _down := false
var _down_ms := 0  # When it went down (or got up): the fall's, the rise's start.
var _framed := false  # Drawn once: a body first seen down lies at once.
var _life: Life
var _coil: Tween


## For [param art] (an instance of [param creature_slot]) under
## [param pose], the node the stand-ins tip.
func _init(creature_slot: String, art: Node3D, pose: Node3D) -> void:
	name = "CreatureView"
	slot = creature_slot
	_pose = pose
	_rest_yaw = pose.rotation.y if pose != null else 0.0
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
		if clip.has("speed"):
			_pace[str(clip["name"])] = float(clip["speed"])
	clips = clip_map(wanted, library.get_animation_list())
	# A glTF's clips come in playing once; these loop (set on the shared
	# clips, the same for every instance of the art, before the rig is made).
	for clip: String in clips:
		library.get_animation(clips[clip]).loop_mode = Animation.LOOP_LINEAR if clip in LOOPED else Animation.LOOP_NONE
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(slot) ^ art.get_instance_id()
	rig = AnimRig.make(root if root != null else art, library, ArtKit.feel("creature_view.blend", BLEND), false, rng)
	var idle := resolve("idle")
	if idle != "":
		rig.loop(idle, pace("idle"))
	var skeletons := art.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		_life = Life.new()
		_life.name = "Life"
		(skeletons[0] as Skeleton3D).add_child(_life)
		_life.setup(skeletons[0] as Skeleton3D, art, rng.seed)


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


## The speed [param clip]'s loop plays at: the slot's "speed" on the clip that plays for it
## (its own, else its fallback's: an alert standing in with the idle takes the idle's).
func pace(clip: String) -> float:
	var at := clip
	for i in 4:
		if clips.has(at):
			return float(_pace.get(at, 1.0))
		at = str(FALLBACKS.get(at, ""))
		if at == "":
			break
	return 1.0


## Every drawn frame: what it does now from [param puppet]'s movement and
## [param monster]'s alert and pose, unless a one-shot has it.
func frame(puppet: Node3D, monster: Monster) -> void:
	if rig == null or _dead:
		return
	var now := AnimRig.now_msec()
	var seconds := (now - _last_ms) / 1000.0
	if _last_at != Vector3.INF and seconds > 0.0:
		var step := Vector2(puppet.position.x - _last_at.x, puppet.position.z - _last_at.z)
		_speed = lerpf(_speed, step.length() / seconds, clampf(seconds * 12.0, 0.0, 1.0))
		if step.length() > 0.0001:
			_way = step.normalized()
	_last_at = puppet.position
	_last_ms = now
	if _steady_until > 0 and (now >= _steady_until or _down):
		steady_over()  # Its "steady_over" lost (STEADY_CAP), or knocked down after all.
	if _lying(monster, now):
		return
	if monster != null and monster.teeter != Vector2i.ZERO:
		# On a rim (783 amended): its slot's teeter, else its paws scrabbling (the walk, quick, in
		# place); Client3D turns it to the drop and rocks it. A flinch from the push gives way.
		_busy_until = 0
		_set_head_up(false)
		if clips.has("teeter"):
			_loop("teeter", 1.0)
		else:
			_loop("walk", ArtKit.feel("creature_view.teeter_pace", TEETER_PACE))
		return
	_dazed = clips.has("dazed") and (now < _dazed_until if monster == null
			else monster.stun_cause == &"crash" and World.tick + World.tick_alpha < monster._reel_until)
	if now < _busy_until:
		return
	if _then != "":
		var then := _then
		_then = ""
		if _once(then):
			return
	if _dazed:
		_set_head_up(false)
		_loop("dazed", 1.0)
		return
	if now < _pant_until:
		# Standing heaving, head low (pant): its winded where its slot has one, else its idle slowed.
		_loop("winded" if clips.has("winded") else "idle", 1.0 if clips.has("winded") else PANT_PACE)
		return
	var alert := monster.alert if monster != null else Monster.Alert.IDLE
	var clip := "idle"
	var scale := 1.0
	# Backing off facing its foe (the boar king's, before a charge): its back_off from the step's
	# first frame to its last, whatever its pace reads (a step's opening frame, or one after a hitch,
	# can read past RUN_ABOVE or under WALKING; the coordinator); the pace chooses walk or run only
	# going forward.
	var fled := alert == Monster.Alert.FLEEING or now < _bolt_until
	var backing := now >= _charge_until and not fled and _backing(monster)
	if backing and (_speed > WALKING or monster.stepping):
		clip = "back_off"
		scale = clampf(_speed / WALK_PACE, ArtKit.feel("creature_view.speed_min", SPEED_MIN),
				ArtKit.feel("creature_view.speed_max", SPEED_MAX))
	elif _speed > WALKING:
		var running := _speed > RUN_ABOVE or fled or now < _charge_until
		clip = "run" if running else "walk"
		scale = clampf(_speed / (RUN_PACE if running else WALK_PACE), ArtKit.feel("creature_view.speed_min", SPEED_MIN),
				ArtKit.feel("creature_view.speed_max", SPEED_MAX))
		if now < _charge_until:
			clip = "charge" if clips.has("charge") else "run"
			scale = maxf(scale, ArtKit.feel("creature_view.charge_speed", CHARGE_SPEED))
	elif monster != null and monster.pose == Monster.Pose.SIT:
		# Asleep, for a beast whose slot has a sleep (the great bear at its den); else grazing.
		# Lying up, for one whose slot has a lie (the hill cat on its perch).
		clip = "sleep" if clips.has("sleep") else "lie" if clips.has("lie") else "graze" if resolve("graze") != "" else "feed"
	elif monster != null and monster.winded and clips.has("winded"):
		clip = "winded"  # Standing heaving (597), after a charge that met nobody.
	elif alert == Monster.Alert.SUSPICIOUS:
		clip = "alert"
	_set_head_up(clip in HEAD_UP_FOR and not clips.has(clip))
	_loop(clip, scale)


## Whether [param monster] walks away from where it faces (enemy-ai's boar king backing off to
## charge, World.face on his foe each step), for a slot with a back_off: by its slide's own way
## while the sim slides it (GridEntity.stepping, so from the step's first frame, before a drawn
## move has shown it), else by its last drawn step's.
func _backing(monster: Monster) -> bool:
	if monster == null or not clips.has("back_off"):
		return false
	monster.faces_back_steps = true  # Its slide keeps the face on its foe (GridEntity).
	var facing := Vector2(monster.shown_facing())
	var way := _way
	if monster.stepping and monster._to_tile != monster._from_tile:
		way = Vector2(monster._to_tile - monster._from_tile).normalized()
	return facing != Vector2.ZERO and way.dot(facing.normalized()) < -BACKING_DOT


## Whether [param monster] is drawn down (Pose DOWN) or still getting up this frame: on its
## pose's change it lies down or gets up (the life's weight eased), its idle under it.
func _lying(monster: Monster, now: int) -> bool:
	if _life == null or _life.root < 0:
		return false
	var down := monster != null and monster.pose == Monster.Pose.DOWN
	var first := not _framed
	_framed = true
	if down != _down:
		_down = down
		_down_ms = now - (int(DOWN_SECONDS * 1000.0) if down and first else 0)
		rig.cancel_strike()
		_busy_until = 0
		_set_head_up(false)
		_loop("idle", 1.0)
	var t := float(now - _down_ms) / 1000.0
	var amount := clampf(t / DOWN_SECONDS, 0.0, 1.0) if _down else 1.0 - clampf(t / UP_SECONDS, 0.0, 1.0)
	_life.weight = smoothstep(0.0, 1.0, amount)
	return amount > 0.0


## Plays [param clip] (a slot clip, through its fallbacks) looping at
## [param scale]: a clip already playing only takes the new speed.
func _loop(clip: String, scale: float) -> void:
	var animation := resolve(clip)
	if animation != "":
		rig.loop(animation, scale * pace(clip))


## [param clip] once through, at [param scale], busy till it ends.
func _once(clip: String, scale := 1.0) -> bool:
	var animation := resolve(clip)
	if rig == null or animation == "" or _dead:
		return false
	_busy_until = AnimRig.now_msec() + int(rig.once(animation, scale) * 1000.0)
	return true


## A blow (GridEntity.swung): its attack at its own pace, unless a wound-up
## one or a hit is playing.
func swing() -> void:
	if rig != null and not rig.striking() and AnimRig.now_msec() >= _busy_until:
		_strike(-1.0, _blow())


## The next plain blow's clip: the attack, or for a slot with a bite (the hill cat's) swipe and
## bite in turn.
func _blow() -> String:
	_blows += 1
	return "bite" if clips.has("bite") and _blows % 2 == 0 else "attack"


## A wound-up blow given up (GridEntity.winding with 0 ticks; decision 392):
## free for the gait or rest at once.
func unwind() -> void:
	_busy_until = 0
	_then = ""
	if _coil != null and _coil.is_valid() and _pose != null:
		_coil.kill()
		_coil = create_tween().set_parallel(true)
		_coil.tween_property(_pose, "position:x", 0.0, COIL_SETTLE)
		_coil.tween_property(_pose, "rotation:x", -HEAD_UP if _head_up else 0.0, COIL_SETTLE)
		_coil.tween_property(_pose, "position:y", 0.0, COIL_SETTLE)
	if rig != null:
		rig.cancel_strike()


## A blow wound up over [param seconds] (GridEntity.winding: a brute's HEAVY
## tactic, a heavy weapon's wind-up, a plain blow's lead): the attack struck so that its
## contact, the blow, lands as the sim's does. A [param lead] (a plain blow told ahead, 338
## amended (4)) also coils the body over it (coil).
func wind(seconds: float, lead := false) -> void:
	# A heavy wind-up (not a lead) plays the slot's hook where it has one: the boar king's tusks.
	# A plain one swipes and bites in turn for a slot with a bite (the hill cat's), as swing does.
	_strike(maxf(seconds, 0.05), "hook" if not lead and clips.has("hook") else _blow())
	if lead:
		coil(maxf(seconds, 0.05))


## The body gathered for a blow landing in [param seconds]: drawn back COIL_BACK of its length
## with its head dipped, eased in over the lead, then sprung a third past rest as it lands and
## settled; a wolf's bite seen coming, not slid into.
func coil(seconds: float) -> void:
	if _pose == null or _dead or _down:
		return
	if _coil != null and _coil.is_valid():
		_coil.kill()
	var back := ArtKit.size(slot).z * ArtKit.feel("creature_view.coil_back", COIL_BACK)
	var sink := ArtKit.size(slot).y * ArtKit.feel("creature_view.coil_sink", COIL_SINK)
	var rest := -HEAD_UP if _head_up else 0.0
	var dip := ArtKit.feel("creature_view.coil_dip", COIL_DIP)
	_coil = create_tween().set_parallel(true)
	_coil.tween_property(_pose, "position:x", -back, seconds * 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_coil.tween_property(_pose, "rotation:x", rest + dip, seconds * 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_coil.tween_property(_pose, "position:y", -sink, seconds * 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_coil.chain().tween_property(_pose, "position:x", back / 3.0, seconds * 0.3).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_coil.parallel().tween_property(_pose, "rotation:x", rest - dip * 0.3, seconds * 0.3).set_ease(Tween.EASE_IN)
	_coil.parallel().tween_property(_pose, "position:y", 0.0, seconds * 0.3).set_ease(Tween.EASE_IN)
	_coil.chain().tween_property(_pose, "position:x", 0.0, COIL_SETTLE).set_ease(Tween.EASE_IN_OUT)
	_coil.parallel().tween_property(_pose, "rotation:x", rest, COIL_SETTLE).set_ease(Tween.EASE_IN_OUT)


## The attack struck over the gait or rest, its contact landing in
## [param lands_in] seconds (at its own pace if negative), the rest of it at
## the same speed.
func _strike(lands_in: float, clip := "attack") -> void:
	var animation := resolve(clip)
	if rig == null or animation == "" or _dead:
		return
	var length := rig.length(animation)
	var share := 1.0 if clip in TELL_ENDS_AT_LANDING else ArtKit.feel("art_kit.clip_contact", CONTACT)
	var contact := length * clampf(float(_contact.get(clip, share)), 0.0, 1.0)
	if lands_in < 0.0:
		lands_in = contact
	var speed := contact / lands_in if lands_in > 0.0 else 1.0
	rig.strike(animation, contact, lands_in, (length - contact) / maxf(speed, 0.001))


## The tell of a move telegraphed as [param move] (780 amended (6); Main's telegraph_started),
## landing in [param lands_in] seconds: its slot clip (TELL_CLIPS, else the move's own name)
## struck over the gait or rest so that its contact lands with the move. Whether there was one.
func tell(move: String, lands_in: float, id: int) -> bool:
	var clip := str(TELL_CLIPS.get(move, move))
	if rig == null or _dead:
		return false
	if not clips.has(clip):
		# No clip of its own (the old grey's lunge): the body gathers over the tell and springs as it
		# lands (coil, a lead's draw-back), never slid into untold (the coordinator).
		if _pose == null or _down:
			return false
		coil(maxf(lands_in, 0.05))
		_tell_id = id
		_tell_until = AnimRig.now_msec() + int(maxf(lands_in, 0.0) * 1000.0)
		return true
	_strike(maxf(lands_in, 0.05), clip)
	_tell_id = id
	_tell_until = AnimRig.now_msec() + int(maxf(lands_in, 0.0) * 1000.0)
	return true


## Telegraph [param id] over: called off (stunned, knocked down: not [param landed]), its tell
## stops at once, as a blow given up does (unwind).
func tell_over(id: int, landed: bool) -> void:
	if id != _tell_id or id == 0:
		return
	_tell_id = 0
	if not landed:
		_tell_until = 0
		unwind()


## A roar (cried "roar"; or [param clip], the old grey's "howl" as he calls his pack in): its slot
## clip once at its own pace, over the gait or rest; none without one.
func roar(clip := "roar") -> void:
	if clips.has(clip) and rig != null and not _dead and not rig.striking():
		_strike(-1.0, clip)


## A pant for [param seconds] (cried "pant": the old grey stands heaving after a lunge, open to a
## blow, as Jeff's checklist has it): its idle slowed (a winded where its slot has one), the head
## let down and back up at its end.
func pant(seconds: float) -> void:
	if rig == null or _dead or _pose == null:
		return
	_charge_until = 0
	_pant_until = AnimRig.now_msec() + int(maxf(seconds, 0.0) * 1000.0)
	var dip := ArtKit.feel("creature_view.pant_dip", PANT_DIP)
	var tween := create_tween()
	tween.tween_property(_pose, "rotation:x", dip, PANT_EASE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(maxf(seconds - PANT_EASE * 2.0, 0.0))
	tween.tween_property(_pose, "rotation:x", 0.0, PANT_EASE).set_ease(Tween.EASE_IN_OUT)


## The paw before a back-off (cried "snort"; the boar king's, enemy-ai's "paw" ticks): its
## slot's paw once, in place; none without one.
func paw() -> void:
	if rig == null or _dead or not clips.has("paw"):
		return
	_once("paw")


## A charge (cried "charge"): a faster run for a while, lunging as it goes
## when the art has no charge of its own. A charge whose tell plays (the great bear's roar
## before its rush) runs on from the tell's end: the sim rushes once it lands, the client
## holds nothing back.
func charge() -> void:
	var now := AnimRig.now_msec()
	var from := maxi(now, _tell_until)
	_charge_until = from + int(CHARGE_SECONDS * 1000.0)
	if from > now:
		return  # Telling: the tell has it, and the run follows when the body moves.
	_busy_until = 0
	# No lunge for a beast with a tell: it stands telling (whichever of the cry and the
	# telegraph comes first), then runs.
	if clips.has("charge") or clips.has("charge_tell") or _pose == null:
		return
	var tween := create_tween()
	tween.tween_property(_pose, "position:x", LUNGE, CHARGE_SECONDS * 0.3).set_ease(Tween.EASE_OUT)
	tween.tween_property(_pose, "position:x", 0.0, CHARGE_SECONDS * 0.7).set_ease(Tween.EASE_IN_OUT)


## Its leap landing (cried "pounce": the hill cat's, enemy-ai's HillCat): its slot's pounce once,
## landing as the slide does, then its recover once (the opening it gives); the tell over.
func pounce() -> void:
	if rig == null or _dead or not clips.has("pounce"):
		return
	_tell_until = 0
	_charge_until = 0
	rig.cancel_strike()
	if _once("pounce") and clips.has("recover"):
		_then = "recover"


## Its quarry's notice (cried "call": the hill cat spotted): its slot's snarl once over the
## gait or rest; none without one (a goblin's call has none).
func snarl() -> void:
	if rig != null and not _dead and clips.has("snarl") and not rig.striking():
		_strike(-1.0, "snarl")


## A charge run out past its target (cried "skid"; the boar king's, enemy-ai's BoarKing): its slot's
## skid once, the charge over; none without one (it stands, as before).
func skid() -> void:
	if rig == null or _dead or not clips.has("skid"):
		return
	_charge_until = 0
	rig.cancel_strike()
	_once("skid")


## Stunned by a crash for [param seconds] (stunned, cause &"crash": the boar king's charge into the
## terrain): its slot's dazed looping through it, over any blow's hit; none without one.
func daze(seconds: float) -> void:
	if rig == null or _dead or not clips.has("dazed"):
		return
	_charge_until = 0
	_busy_until = 0
	rig.cancel_strike()
	# Only ever lengthened: a shorter stun the same tick keeps the crash's cause (a slide's), not its end.
	_dazed_until = maxi(_dazed_until, AnimRig.now_msec() + int(maxf(seconds, 0.0) * 1000.0))


## The herd bolting (cried "rout"): run.
func bolt() -> void:
	_bolt_until = AnimRig.now_msec() + int(BOLT_SECONDS * 1000.0)


## A blow taken: its hit clip, else a flinch (tipped and pushed back); none lying down (it
## would half stand). Steadied (843), no hit: it rocks back and holds.
func hit() -> void:
	if _dead or _down or (_life != null and _life.weight > 0.0):
		return
	if _dazed or AnimRig.now_msec() < _dazed_until:
		return  # Dazed wins over a blow for its whole stun (the coordinator): its opening stays shown.
	if steadied():
		_rock()
		return
	if clips.has("hit"):
		# Not under a blow (it would play unseen, then show held as the blow
		# fades), nor over one played once.
		if AnimRig.now_msec() >= _busy_until and not rig.striking():
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


## Steadied (cried "steady", 843): out of a stagger a boss plants and shakes it off (the set beat,
## STEADY_SECONDS), then stands braced, a blow rocking it without a hit, till steady_over.
func steady() -> void:
	if rig == null or _dead or _down or _pose == null:
		return
	_steady_until = AnimRig.now_msec() + int(ArtKit.feel("creature_view.steady_cap", STEADY_CAP) * 1000.0)
	var sink := ArtKit.size(slot).y * ArtKit.feel("creature_view.steady_sink", STEADY_SINK)
	var shake := ArtKit.feel("creature_view.steady_shake", STEADY_SHAKE)
	var twist := ArtKit.feel("creature_view.steady_twist", STEADY_TWIST)
	var dip := (-HEAD_UP if _head_up else 0.0) + ArtKit.feel("creature_view.steady_dip", STEADY_DIP)
	var beat := ArtKit.feel("creature_view.steady_seconds", STEADY_SECONDS)
	if _steady != null and _steady.is_valid():
		_steady.kill()
	_steady = create_tween().set_parallel(true)
	# Planted: down into its legs, the head low, the first roll of the shake with it.
	_steady.tween_property(_pose, "position:y", -sink, beat * 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_steady.tween_property(_pose, "rotation:x", dip, beat * 0.25).set_ease(Tween.EASE_OUT)
	_steady.tween_property(_pose, "rotation:z", shake, beat * 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_steady.tween_property(_pose, "rotation:y", _rest_yaw + twist, beat * 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_steady.chain().tween_property(_pose, "rotation:z", -shake, beat * 0.25).set_trans(Tween.TRANS_SINE)
	_steady.parallel().tween_property(_pose, "rotation:y", _rest_yaw - twist, beat * 0.25).set_trans(Tween.TRANS_SINE)
	_steady.chain().tween_property(_pose, "rotation:z", shake * 0.4, beat * 0.2).set_trans(Tween.TRANS_SINE)
	_steady.parallel().tween_property(_pose, "rotation:y", _rest_yaw + twist * 0.4, beat * 0.2).set_trans(Tween.TRANS_SINE)
	_steady.chain().tween_property(_pose, "rotation:z", 0.0, beat * 0.3).set_ease(Tween.EASE_OUT)
	_steady.parallel().tween_property(_pose, "rotation:y", _rest_yaw, beat * 0.3).set_ease(Tween.EASE_OUT)
	# Braced: part way up again, held so.
	_steady.parallel().tween_property(_pose, "position:y", -sink * STEADY_HOLD, beat * 0.3).set_ease(Tween.EASE_IN_OUT)


## Whether it stands steadied now (843).
func steadied() -> bool:
	return _steady_until > AnimRig.now_msec()


## Steadied no more (cried "steady_over", or STEADY_CAP, a knockdown, its death): up from the
## brace.
func steady_over() -> void:
	if _steady_until == 0:
		return
	_steady_until = 0
	if _steady != null and _steady.is_valid():
		_steady.kill()
	if _pose == null or _dead:
		return
	_steady = create_tween().set_parallel(true)
	_steady.tween_property(_pose, "position:y", 0.0, STEADY_SETTLE).set_ease(Tween.EASE_IN_OUT)
	_steady.tween_property(_pose, "rotation:x", -HEAD_UP if _head_up else 0.0, STEADY_SETTLE).set_ease(Tween.EASE_IN_OUT)
	_steady.tween_property(_pose, "rotation:z", 0.0, STEADY_SETTLE).set_ease(Tween.EASE_IN_OUT)
	_steady.tween_property(_pose, "rotation:y", _rest_yaw, STEADY_SETTLE).set_ease(Tween.EASE_IN_OUT)


## A blow on it steadied: rocked back, the head tossed up, and back into its brace at once.
func _rock() -> void:
	if _pose == null:
		return
	var braced := (-HEAD_UP if _head_up else 0.0) + ArtKit.feel("creature_view.steady_dip", STEADY_DIP)
	var back := ArtKit.size(slot).z * ArtKit.feel("creature_view.rock_back", ROCK_BACK)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_pose, "rotation:x", braced - ArtKit.feel("creature_view.rock", ROCK), ROCK_SECONDS * 0.25).set_ease(Tween.EASE_OUT)
	tween.tween_property(_pose, "position:x", -back, ROCK_SECONDS * 0.25).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(_pose, "rotation:x", braced, ROCK_SECONDS * 0.75).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(_pose, "position:x", 0.0, ROCK_SECONDS * 0.75).set_ease(Tween.EASE_IN_OUT)


## Dead: its death clip once, held on its last frame; the seconds it takes
## (0 with none, and the puppet falls over as a body without art does).
func die() -> float:
	_then = ""
	steady_over()
	if rig == null or resolve("death") == "":
		return 0.0
	if _life != null and _life.weight > 0.0:
		# Killed lying: it unfolds as its death plays, to lie on its side, still.
		create_tween().tween_property(_life, "weight", 0.0, DIE_UNFOLD_SECONDS)
	_down = false
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
