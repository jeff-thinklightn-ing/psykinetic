class_name Animal
extends Monster
## A wild animal (decision 315): a monster of side "wild" (a row of
## levels/monsters.json with "side": "wild"), of no faction. Monsters do not
## hunt it and it never answers their calls; its side is its herd (a row's
## "herd": a stag runs with the deer). It notices by the shared senses
## (sight, a glimpse, what it hears) and by scent: downwind of you it smells
## you before it sees you (Senses.smells, decision 316).
##
## Its "role" says what it does about it:
## - prey (rabbit, deer, stag): anyone it notices, or a noise not its
##   herd's, and it bolts (FLEEING), and its bolting (a rout, a cry) sends
##   the herd after it; it never fights. Hunted (decision 764): it bolts in
##   a burst (BURST_PACE for BURST_TICKS; struck, STRUCK_BURST_TICKS), then
##   trots at its pace, so one left behind is shaken off; wounded under
##   half it bleeds (BLEED_TICKS, never to death) and trots WOUNDED_TROT
##   slower; under DOWN_BELOW of its hp, after a burst it goes down
##   (DOWN_TICKS: still, not running) and can be finished. A kill seen or
##   heard, or one struck crying out (within WARY_REACH), leaves its herd wary WARY_TICKS: it sees
##   WARY_SIGHT farther, heeds every step, bolts twice as long, and moves
##   its home MOVE_OFF away. A player's step it heeds only hurried (its step_gap within
##   STALK_STEP_TICKS: a slow stalk behind it goes unheard), and one it finds at its side
##   unawares startles it STARTLE_TICKS before it bolts: a blow's time.
## - game (boar): bolts as prey does, but struck (running or not), or cornered with the
##   threat near, it charges (its kind's HEAVY blow) for a while, then
##   runs again.
## - predator (wolf): hunts its "diet" kinds in sight, and players only when
##   bold: at night (the sky's light under NIGHT_LIGHT: bold, sight
##   NIGHT_SIGHT farther) or with PACK_BOLD of its pack about. Its call is
##   the pack's howl (a "call" its herd hears).
##
## Idling it wanders about its home, the herd's ground; standing between
## strolls it grazes (Pose.SIT, which a view of an animal plays as its
## graze), seeing GRAZE_SIGHT less far with its head down.
##
## Keeping the balance (decision 761, enemy-ai's side), in an area whose
## level's herds say "balance" (World.balance governs it; test levels only),
## a predator with nobody to fight has errands (_errand_step), before its
## prey: meat lying within SMELL_TILES (Balance.meat_near) it goes to and
## eats (Balance.eat; head down EAT_TICKS, a howl when it finds it); hungry
## (its group's Herds.fed under HUNGRY_FED) it is bold, keeps out of no din,
## and at night goes to a fold within FOLD_TILES and takes one sheep
## (Balance.take_sheep), once a night, then back to its den. A town's
## wolves of a night (town_wolf: Main._town_wolves makes them while the
## town has the threat) go to its store, take one thing (Balance.night_take:
## food and livestock, never gold), and go back; they never hunt people or
## game, and one killed is one fewer to come (Balance.town_wolf_killed).

enum Role { PREY, GAME, PREDATOR }
const ROLES := {"prey": Role.PREY, "game": Role.GAME, "predator": Role.PREDATOR}
## Grazing it sees this many cells less far.
const GRAZE_SIGHT := 3
## A boar struck, or cornered with the threat this near, charges for so
## long (ticks), then runs.
const CHARGE_TICKS := 90
const CORNERED_TILES := 2
## A predator is bold under this much of the sky's light (DayNight), and
## sees this much farther; or with this many of its pack (itself too)
## within PACK_TILES (decision 397 amended, enemy-ai's side: 4 and 1, Jeff approved; were 3
## and 2, so a pack of economy's 2 or 3 lets a player be by day).
const NIGHT_LIGHT := 0.35
const NIGHT_SIGHT := 1
const PACK_BOLD := 4
const PACK_TILES := 8
## A predator looks over its diet in sight every so many ticks, and
## settles whether it is bold as often.
const PREY_LOOK_TICKS := 10
## A boar's charge is heard so far (a "charge" cry).
const NOISE_CHARGE := 6
## A predator by day keeps to its den: it wanders this far from home; by
## night twice its own wander radius (decision 317, W4).
const DEN_RADIUS := 1
## A herd's body is made (Herds' free_near, Main) more than this far from
## every player where it can be: it walks into view, not appears in it.
const UNSEEN_TILES := 8
## A step heard (not its herd's, nor a predator's): it stops, head up,
## turned to it, for so long (ticks), and sees as far as it can.
const ALERT_TICKS := 40
## Decision 764 (hunting; drafts): prey bolts at BURST_PACE x its pace for
## BURST_TICKS (struck, STRUCK_BURST_TICKS), then trots at its pace.
## Wounded under half its hp, it trots at WOUNDED_TROT x its pace and bleeds
## 1 hp every BLEED_TICKS (never under 1); under DOWN_BELOW of its hp, after
## a burst it goes down for DOWN_TICKS. A kill of its herd within
## WARY_REACH: wary WARY_TICKS (WARY_SIGHT farther, every step heeded,
## bursts twice as long), its home moved MOVE_OFF away from the kill. A player's step within STALK_STEP_TICKS of its
## last (GridEntity.step_gap) is hurried (heeded); slower, a stalk (not). Found
## at its side unawares, it stands startled STARTLE_TICKS, then bolts.
const BURST_PACE := 0.75
const BURST_TICKS := 30
const STRUCK_BURST_TICKS := 60
const WOUNDED_TROT := 1.25
const WARY_TICKS := 3000
const WARY_SIGHT := 3
const WARY_REACH := 40
const MOVE_OFF := 30
const BLEED_TICKS := 100
const DOWN_BELOW := 0.25
const DOWN_TICKS := 600
const STALK_STEP_TICKS := 6
const STARTLE_TICKS := 12
## A blow from this near (cells) on game unawares fells a "felled_by_surprise"
## kind (764): a melee blow, a spear's reach.
const SURPRISE_REACH := 2
## A companion's step is judged by her keeper's within this many cells
## (764): she stalks with a stalking player.
const STALK_WITH_TILES := 8
## Decision 761 (enemy-ai's side): a predator smells meat lying so far
## (cells), and eats it head down for so long (ticks) once beside it.
const SMELL_TILES := 12
const EAT_TICKS := 30
## Fed under this much (Herds.fed, 0..1) it is hungry: bold, heedless of a
## din, and at night after the fold.
const HUNGRY_FED := 0.5
## A hungry predator goes to a fold this near (cells) at night.
const FOLD_TILES := 40
## A town's wolf takes from the store this near its cell.
const STORE_REACH := 2

var role := Role.PREY
## The kinds a predator hunts.
var diet: Array[String] = []
## Its herd (a row's "herd", else its kind).
var herd := ""
var _foe: GridEntity = null
var _charge_until := -1
var _look_tick := -1
var _prey: GridEntity = null
var _bold := false
var _bold_tick := -1
## The sight it has from the night now (NIGHT_SIGHT or 0).
var _night_bonus := 0
## Head up after a step heard, till then (ticks).
var _heads_up_until := -1
## Its wander radius as its spawn spec or kind gave it (a predator's by
## night is twice it; by day DEN_RADIUS).
var _roam := WANDER_RADIUS
## Decision 761: the town whose nights it comes to (Main._town_wolves; a
## spawn prop, so kept in a save), "" for a wild one.
var town_wolf := ""
## Its town's store cell, [x, y] (a spawn prop too).
var town_store: Array = []
## Its errand (761): {kind: meat, fold or town, cell, reach, and uid or
## fold}; {} for none.
var _errand := {}
var _errand_tick := -1
var _eat_until := -1
## Hungry (761): its group fed under HUNGRY_FED. Settled with its boldness.
var _hungry := false
var _night := false
## When it last took a sheep or a town's thing (World's steps), -1 never.
var _took_at := -1
## Decision 764: its flight's burst ends (ticks); down till;
## startled till; its last bleed.
var _burst_until := -1
## Wary after a kill of its herd till then (764), -1 not.
var _wary_until := -1
var _down_until := -1
var _startle_until := -1
var _bled_tick := -1


func _ready() -> void:
	super()
	if not Net.is_authority():
		return
	var row: Dictionary = kinds().get(str(spawn_spec.get("kind", "")), {})
	role = ROLES.get(str(row.get("role", "prey")), Role.PREY)
	diet.assign(row.get("diet", []))
	herd = str(row.get("herd", spawn_spec.get("kind", "")))
	_roam = wander_radius


## Whether [param kind] is a wild animal's (its row's "side").
static func is_wild(kind: String) -> bool:
	return str(kinds().get(kind, {}).get("side", "")) == "wild"


func _sim_tick() -> void:
	if not noticing:
		_unnoticing()
		return
	if role == Role.PREDATOR:
		_settle_bold()
		if _errand_step():
			return
		super()
		return
	_bleed()
	if _wary_until >= 0 and World.tick >= _wary_until:
		_wary_until = -1
		sight_range -= WARY_SIGHT
	if World.tick < _down_until:
		_lie_down_tick()
		return
	if World.tick < _startle_until:
		if _struck_by() == null:
			pose = Pose.STAND
			return  # Startled: a moment before it bolts (764).
		_startle_until = -1
	# Struck, a boar turns and charges though it was running (an arrow from
	# afar); prey runs on.
	if alert == Alert.FLEEING and not (role == Role.GAME and _struck_by() != null):
		pose = Pose.STAND
		_flee_tick()
		return
	if senses.last_tick > _rout_tick and _heard_rout():
		return
	if role == Role.GAME and World.tick < _charge_until and is_instance_valid(_foe) and _foe.spawned:
		super()  # The charge: its kind's fight, at _foe (_nearest_visible_target).
		return
	_foe = null
	var threat := _threat()
	if threat == null and _struck_by() == null:
		_noise_threat()
		if alert != Alert.FLEEING:
			_graze_tick()
		return
	var from := _struck_by()
	if role == Role.GAME and (from != null or World.distance(tile, threat.tile) <= CORNERED_TILES and _cornered(threat.tile)):
		_foe = from if from != null else threat
		_charge_until = World.tick + CHARGE_TICKS
		_cry(&"charge", NOISE_CHARGE)
		pose = Pose.STAND
		alert = Alert.IDLE  # Running no more: Monster's fight takes it from here.
		super()
		return
	if role == Role.PREY and from == null and alert != Alert.FLEEING and alert != Alert.SUSPICIOUS \
			and World.distance(tile, threat.tile) <= Senses.NOTICE_ALWAYS:
		# Found at its side unawares (764): a start, then it bolts.
		_startle_until = World.tick + STARTLE_TICKS
		alert = Alert.SUSPICIOUS
		pose = Pose.STAND
		var way := Senses.way_toward(tile, threat.tile)
		if way != Vector2i.ZERO:
			World.face(self, way)
		return
	_flee((from if from != null else threat).tile)


## Grazing about home: Monster's idling (WANDER), its head down between
## strolls.
func _graze_tick() -> void:
	target = null
	if World.tick < _heads_up_until:
		alert = Alert.SUSPICIOUS  # Head up, listening: a view plays its alert.
		pose = Pose.STAND
		return
	alert = Alert.IDLE
	_leave_din()
	_idle_tick()
	var standing := World.tick < _idle_until or _idle_goal == NO_TILE
	pose = Pose.SIT if standing and idle != Idle.NONE else Pose.STAND


## Decision 740: grazing in a din (World.din_at: a town's, a fire's, a
## fight's; a predator heeds towns and fires only; a player it flees by
## sight), it makes a spot out of it its home and walks there, not running.
func _leave_din() -> void:
	if _returning:
		return
	var din := World.din_at(tile, role == Role.PREDATOR, false)
	if din.is_empty():
		return
	var out := World.out_of_din(tile, din, role == Role.PREDATOR)
	if out != NO_TILE:
		home = out
		_returning = true


## It keeps its wandering out of the din (740); a hungry predator, or a
## town's wolf, does not (761).
func _shuns(at: Vector2i) -> bool:
	if role == Role.PREDATOR and (_hungry or not town_wolf.is_empty()):
		return false
	return not World.din_at(at, role == Role.PREDATOR).is_empty()


## Its looking: the nearest player or companion it sees, glimpses or
## smells (grazing, GRAZE_SIGHT less far); null for none.
func _threat() -> GridEntity:
	var reach := senses.sight_range
	if pose == Pose.SIT:
		senses.sight_range = maxi(1, reach - GRAZE_SIGHT)
	var nearest: GridEntity = null
	var nearest_d := 1 << 30
	for entity in World.sought():
		var d := World.distance(tile, entity.tile)
		if d >= nearest_d or d > maxi(reach, Senses.SCENT_TILES):
			continue
		if senses.sees(entity, d) or senses.glimpses(entity, d) or senses.smells(entity, d):
			nearest = entity
			nearest_d = d
	senses.sight_range = reach
	return nearest


## What it heard since it last looked, not of its herd's making: a
## predator's step, a fight, a call, a door, anything loud, and it bolts
## away from it; another's step, and it stops, head up and turned to it
## (ALERT_TICKS), to look.
func _noise_threat() -> void:
	if senses.heard.is_empty() or int(senses.heard.back()["tick"]) <= _listened_tick:
		return
	var since := _listened_tick
	_listened_tick = int(senses.heard.back()["tick"])
	for noise: Dictionary in senses.heard:
		if int(noise["tick"]) <= since or noise["kind"] == &"rout":
			continue
		var source: Variant = noise["source"]
		if is_instance_valid(source) and (source == self or source is Animal and (source as Animal).herd == herd):
			continue  # Its own, or its herd's.
		var predator: bool = is_instance_valid(source) and source is Animal and (source as Animal).role == Role.PREDATOR
		if noise["kind"] == &"step" and not predator and is_instance_valid(source) and not source is Animal \
				and _walker_of(source as GridEntity).step_gap > STALK_STEP_TICKS and not wary():
			continue  # A stalk (764): a slow step, not close on the last, goes unheeded.
		if noise["kind"] == &"step" and not predator:
			var way := Senses.way_toward(tile, noise["at"])
			if way != Vector2i.ZERO:
				World.face(self, way)
			_heads_up_until = World.tick + ALERT_TICKS
			continue
		_flee(noise["at"])
		return


## Where prey runs (764; playtest: a doe stood 4 minutes in a corner a cell
## from a hunter): Monster's goal straight away; with none there, along the
## wall, the free cell of a few every way round that keeps it farthest
## from the threat, never nearer it than it stands. A boar's is Monster's
## (cornered, it charges).
func _flee_goal() -> Vector2i:
	var goal := super()
	if role != Role.PREY or (goal != NO_TILE and goal != tile):
		return goal
	var best := NO_TILE
	var best_d := World.distance(tile, _flee_from)
	for way: Vector2i in AROUND:
		for n in range(flee_tiles, 0, -1):
			var at := tile + way * n
			var d := World.distance(at, _flee_from)
			if d >= best_d and World.is_walkable(at) and World.is_free(at):
				if d > best_d or best == NO_TILE:
					best = at
					best_d = d
				break
	return best


## Whether it has nowhere to run from [param threat] (Monster's flee goal
## finds no tile away).
func _cornered(threat: Vector2i) -> bool:
	_flee_from = threat
	var goal := _flee_goal()
	return goal == NO_TILE or goal == tile


## A predator's quarry: its diet in sight (looked over every
## PREY_LOOK_TICKS), and players when bold; a boar's, the one it charges.
func _nearest_visible_target() -> GridEntity:
	match role:
		Role.GAME:
			return _foe if World.tick < _charge_until and is_instance_valid(_foe) and _foe.spawned else null
		Role.PREY:
			return null
	var player: GridEntity = super() if _bold or World.tick - hurt_tick < CHARGE_TICKS else null
	if not town_wolf.is_empty():
		return player  # A town's wolf hunts nothing: it fights back only when hurt (761).
	if _look_tick < 0 or World.tick - _look_tick >= PREY_LOOK_TICKS or (_prey != null and not is_instance_valid(_prey)):
		_look_tick = World.tick
		_prey = _sees_prey()
	if _prey != null and (not is_instance_valid(_prey) or not _prey.spawned):
		_prey = null
	if player == null:
		return _prey
	if _prey == null:
		return player
	return player if World.distance(tile, player.tile) <= World.distance(tile, _prey.tile) else _prey


## The nearest animal of its diet it sees, null for none.
func _sees_prey() -> GridEntity:
	if diet.is_empty():
		return null
	var nearest: GridEntity = null
	var nearest_d := sight_range + 1
	for entity in World.monsters():
		if not entity is Animal or str(entity.spawn_spec.get("kind", "")) not in diet:
			continue
		var d := World.distance(tile, entity.tile)
		if d < nearest_d and senses.sees(entity, d, entity != target):
			nearest = entity
			nearest_d = d
	return nearest


## A predator: bold at night or with its pack about; then CAUTIOUS's
## holding back is gone and it sees farther. Looked at every
## PREY_LOOK_TICKS.
func _settle_bold() -> void:
	if _bold_tick >= 0 and World.tick - _bold_tick < PREY_LOOK_TICKS:
		return
	_bold_tick = World.tick
	var night := DayNight.daylight(DayNight.now()) < NIGHT_LIGHT if World.fields.outdoor else false
	var pack := 1
	if not night:
		for entity in World.monsters():
			if entity != self and entity is Animal and (entity as Animal).herd == herd \
					and World.distance(tile, entity.tile) <= PACK_TILES:
				pack += 1
	_night = night
	_hungry = town_wolf.is_empty() and _governed() and World.herds != null \
			and World.herds.fed(str(spawn_spec.get("group", ""))) < HUNGRY_FED
	_bold = (night or pack >= PACK_BOLD or _hungry) and town_wolf.is_empty()  # A town's wolf never goes at people (761).
	wander_radius = _roam * 2 if night else DEN_RADIUS  # Out by night, at its den by day.
	temper = Temper.BOLD if _bold else Temper.CAUTIOUS
	var bonus := NIGHT_SIGHT if night else 0
	sight_range += bonus - _night_bonus
	_night_bonus = bonus


## Its drops; and one of a herd's group (spec "group", decision 367) is
## gone from it for good (Herds.killed): hunting thins a herd.
func remains() -> Array[int]:
	var group := str(spawn_spec.get("group", ""))
	if not group.is_empty() and World.herds != null:
		World.herds.killed(group, str(spawn_spec.get("kind", "")))
	if not town_wolf.is_empty() and World.balance != null:
		World.balance.town_wolf_killed(town_wolf)  # One fewer to come (761).
	if role == Role.PREY:
		_alarm_herd()  # Its herd saw it fall (764).
	return super()


## Its herd within WARY_REACH, but itself, alarmed at where it is (764):
## a kill, or its cry struck, heard; a hunted ground goes quiet.
func _alarm_herd() -> void:
	for entity in World.monsters():
		if entity != self and entity is Animal and (entity as Animal).herd == herd \
				and World.distance(tile, entity.tile) <= WARY_REACH:
			(entity as Animal).alarm(tile)


# --- Keeping the balance (decision 761, enemy-ai's side) --------------------------

## Whether World.balance governs the zone it is in.
func _governed() -> bool:
	return World.balance != null and World.zone != null and World.balance.governs(World.zone.name)


## A predator's errand this tick (meat, a fold, a town's store), when it has
## nobody to fight, isn't running and isn't struck: true while it is on one
## (it walks or eats; Monster's tick is not run), false to go on as ever. A
## bold one's quarry in sight ends it, looked for as often as the errand is
## chosen (PREY_LOOK_TICKS).
func _errand_step() -> bool:
	if World.balance == null or (town_wolf.is_empty() and not _governed()) or target != null \
			or alert == Alert.FLEEING or alert == Alert.FIGHTING or _struck_by() != null or World.is_stunned(self):
		_errand = {}
		return false
	if World.tick < _eat_until:
		pose = Pose.SIT  # Head down at the meat (a view plays it as the graze).
		return true
	if _errand_tick < 0 or World.tick - _errand_tick >= PREY_LOOK_TICKS:
		_errand_tick = World.tick
		if (_bold or World.tick - hurt_tick < CHARGE_TICKS) and super._nearest_visible_target() != null:
			_errand = {}
			return false  # A quarry in sight: Monster's fight.
		var was := str(_errand.get("kind", ""))
		_errand = _pick_errand()
		if str(_errand.get("kind", "")) == "meat" and was != "meat":
			_cry(&"call", call_reach)  # The howl over meat found: its pack hears it.
	if _errand.is_empty():
		return false
	var at: Vector2i = _errand["cell"]
	if World.distance(tile, at) <= int(_errand["reach"]):
		_do_errand()
		return true
	pose = Pose.STAND
	alert = Alert.IDLE
	if World.tick < next_move_tick:
		return true
	move_ticks = _pace
	if not _idle_step(at):
		_errand = {}  # No way there now: looked at again in a moment.
		return false
	return true


## What it goes to now: a town's wolf its town's store (until it took);
## else meat lying it smells, nearest; else, hungry at night and not yet
## this night, the nearest fold with sheep within FOLD_TILES. {} for none.
func _pick_errand() -> Dictionary:
	if not town_wolf.is_empty():
		var store: Variant = Snapshot.vector(town_store)
		if _took_at >= 0 or store == null or World.balance.threat(town_wolf).is_empty():
			return {}
		return {"kind": "town", "cell": store, "reach": STORE_REACH}
	var area := World.zone.name
	var meat := World.balance.meat_near(area, tile, SMELL_TILES)
	if not meat.is_empty():
		return {"kind": "meat", "cell": meat[0]["cell"], "uid": int(meat[0]["uid"]), "reach": 1}
	if not (_night and _hungry) or (_took_at >= 0 and World.steps_now() - _took_at < maxi(DayNight.day_steps, 1) / 2):
		return {}
	var best := {}
	for fold in World.balance.folds_in(area):
		var d := World.distance(tile, fold["cell"])
		if int(fold["sheep"]) > 0 and d <= FOLD_TILES and (best.is_empty() or d < World.distance(tile, best["cell"])):
			best = {"kind": "fold", "cell": fold["cell"], "fold": str(fold["id"]), "reach": int(fold["reach"])}
	return best


## There: eats the meat, takes a sheep or the town's thing (then home).
func _do_errand() -> void:
	match str(_errand["kind"]):
		"meat":
			if World.balance.eat(int(_errand["uid"])):
				var way := Senses.way_toward(tile, _errand["cell"])
				if way != Vector2i.ZERO:
					World.face(self, way)
				_eat_until = World.tick + EAT_TICKS
				pose = Pose.SIT
		"fold":
			if World.balance.take_sheep(str(_errand["fold"])):
				print("[balance] a wolf took a sheep from a fold")
			_took_at = World.steps_now()
			_returning = true
		"town":
			var took := World.balance.night_take(town_wolf)
			print("[balance] a wolf in a town's night took %s" % (took if not took.is_empty() else "nothing"))
			_took_at = World.steps_now()
			_returning = true
	_errand = {}
	_errand_tick = -1


## Prey bolting (764): a burst first.
func _flee(threat: Vector2i, routs := true) -> void:
	var was := alert
	super(threat, routs)
	if role == Role.PREY and was != Alert.FLEEING:
		_burst_until = maxi(_burst_until, World.tick + BURST_TICKS * (2 if wary() else 1))


## Struck, prey bolts long (764): a missed or wounding shot costs a chase;
## its cry alarms its herd within WARY_REACH.
## Struck unawares (grazing, or startled) from within SURPRISE_REACH, a kind
## whose row says "felled_by_surprise" (deer, stag, rabbit; not the boar,
## who turns and fights) goes down at once, to be finished.
func note_struck(by: GridEntity) -> void:
	var startled := World.tick < _startle_until
	var unaware := (alert == Alert.IDLE or startled) and World.tick >= _down_until
	super(by)
	if role != Role.PREY:
		return
	_alarm_herd()  # Its cry, struck: its herd within hearing is wary (764).
	var fells := bool(kinds().get(str(spawn_spec.get("kind", "")), {}).get("felled_by_surprise", false))
	var d := World.distance(tile, by.tile) if is_instance_valid(by) else -1
	if fells:
		print("[hunt] %s struck from %d: %s, %s" % [name, d, "startled" if startled else ("grazing" if alert == Alert.IDLE else
				("down" if World.tick < _down_until else Alert.keys()[alert].to_lower())),
				"felled" if unaware and d >= 0 and d <= SURPRISE_REACH else "not felled"])
	if unaware and fells and d >= 0 and d <= SURPRISE_REACH:
		_startle_until = -1
		_burst_until = -1
		_down_until = World.tick + DOWN_TICKS
		alert = Alert.IDLE
		pose = Pose.SIT
		return
	if World.tick >= _down_until:
		_burst_until = World.tick + STRUCK_BURST_TICKS * (2 if wary() else 1)


## Whose pace a step of [param stepper] is judged by (764): a companion
## near her keeper stalks with him (his), else its own.
func _walker_of(stepper: GridEntity) -> GridEntity:
	if stepper is Companion:
		var keeper := (stepper as Companion).keeper
		if is_instance_valid(keeper) and World.distance(stepper.tile, keeper.tile) <= STALK_WITH_TILES:
			return keeper
	return stepper


## Whether a kill of its herd still has it wary (764): till its time,
## ticking or not (its sight's bonus goes at its next tick).
func wary() -> bool:
	return World.tick < _wary_until


## A kill of its herd seen or heard at [param at] (764): wary WARY_TICKS,
## its home moved MOVE_OFF away from it, and off it runs.
func alarm(at: Vector2i) -> void:
	if _wary_until < 0:
		sight_range += WARY_SIGHT
	_wary_until = World.tick + WARY_TICKS
	var away := Vector2i(signi(home.x - at.x), signi(home.y - at.y)) if home != NO_TILE else Vector2i.ZERO
	if away == Vector2i.ZERO:
		away = Vector2i(signi(tile.x - at.x), signi(tile.y - at.y))
	if away != Vector2i.ZERO:
		var from := home if home != NO_TILE else tile
		for n in range(MOVE_OFF, 7, -1):
			var to := from + away * n
			if World.is_walkable(to):
				home = to
				break
	if World.tick >= _down_until and alert != Alert.FLEEING:
		_flee(at)


## Whether it is wounded under half its hp (764).
func wounded() -> bool:
	return max_hp > 0 and hp * 2 < max_hp


## Wounded under half, prey bleeds a little now and then, never to death
## (764): left to run, it tires on.
func _bleed() -> void:
	if role != Role.PREY or not wounded() or hp <= 1:
		_bled_tick = World.tick
		return
	if World.tick - _bled_tick >= BLEED_TICKS:
		_bled_tick = World.tick
		hp -= 1


## Down (764): still, head low, not running from anyone; struck, it stays
## down; its time out, it gets up, wary.
func _lie_down_tick() -> void:
	target = null
	pose = Pose.SIT
	if World.tick + 1 >= _down_until:
		_down_until = -1
		alert = Alert.SUSPICIOUS
		pose = Pose.STAND


## Its pace in flight (764): a burst, then a trot at its pace (wounded,
## WOUNDED_TROT slower); low, down after its burst.
## Whether it moves this tick.
func _flight_paced() -> bool:
	var pace := _pace
	if World.tick < _burst_until:
		move_ticks = pace * BURST_PACE
		return true
	if _burst_until >= 0 and float(hp) < float(max_hp) * DOWN_BELOW:
		_burst_until = -1
		_down_until = World.tick + DOWN_TICKS
		alert = Alert.IDLE
		pose = Pose.SIT
		return false
	move_ticks = pace * (WOUNDED_TROT if wounded() else 1.0)
	return true


## Fleeing: one of a herd's group first tries the steps away from its
## threat that leave the floor (World.walked_off): at a map edge with a
## neighbour, Main sends it there (crossing_off); else nothing comes of it
## and it runs on as any monster.
func _flee_tick() -> void:
	if role == Role.PREY and not _flight_paced():
		return
	if not str(spawn_spec.get("group", "")).is_empty() and World.herds != null \
			and not World.is_stunned(self) and World.tick >= next_move_tick:
		var away := Vector2i(signi(tile.x - _flee_from.x), signi(tile.y - _flee_from.y))
		# Straight steps only: off the map a cell across, at its row or column.
		for way: Vector2i in [Vector2i(away.x, 0), Vector2i(0, away.y)]:
			if way != Vector2i.ZERO and not World.is_walkable(tile + way):
				World.try_move(self, way)
	super()


## Where [param animal], stepping by [param direction] off the floor of
## [param area] on [param world_map], goes (WorldMap.crossing: {to, side,
## at}): {} unless it is one of a herd's group, fleeing, and that edge has
## a neighbour. A level's own animals and ungrouped ones never leave.
static func crossing_off(animal: Animal, direction: Vector2i, world_map: WorldMap, area: String) -> Dictionary:
	if world_map == null or World.herds == null or animal.alert != Alert.FLEEING \
			or str(animal.spawn_spec.get("group", "")).is_empty():
		return {}
	return world_map.crossing(area, animal.tile, direction)


## A free cell under the sky within [param reach] of [param near] (itself
## first) more than UNSEEN_TILES from every one of [param away_from], drawn
## by [param draw]; World.NO_CELL if a few draws find none.
static func unseen_cell(near: Vector2i, reach: int, away_from: Array[Vector2i], draw: RandomNumberGenerator) -> Vector2i:
	for attempt in 16:
		var at := near if attempt == 0 else near + Vector2i(draw.randi_range(-reach, reach), draw.randi_range(-reach, reach))
		if not World.is_free(at) or not World.fields.under_sky(at):
			continue
		if away_from.all(func(other: Vector2i) -> bool: return World.distance(at, other) > UNSEEN_TILES):
			return at
	return World.NO_CELL


## A boar in its charge, or charging as Monster's HEAVY do.
func charging() -> bool:
	return super() or role == Role.GAME and World.tick < _charge_until and is_instance_valid(_foe) and _foe.spawned


## Whether it would fight [param entity] (decision 551, enemy-ai's side):
## prey never; a boar the one it charges; a predator its diet, and a player
## or kept companion while bold or just hurt.
func threatens(entity: GridEntity) -> bool:
	if not _may_threaten(entity):
		return false
	match role:
		Role.PREY:
			return false
		Role.GAME:
			return charging() and _foe == entity
	if entity is Animal:
		return str(entity.spawn_spec.get("kind", "")) in diet
	if entity is Player or (entity is Companion and (entity as Companion).keeper != null):
		return _bold or World.tick - hurt_tick < CHARGE_TICKS
	return false


## Its side is its herd.
func _same_side(other: GridEntity) -> bool:
	return other is Animal and (other as Animal).herd == herd
