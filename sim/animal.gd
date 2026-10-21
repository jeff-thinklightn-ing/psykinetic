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
##   the herd after it; it never fights.
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
## within PACK_TILES.
const NIGHT_LIGHT := 0.35
const NIGHT_SIGHT := 2
const PACK_BOLD := 3
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
		super()
		return
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
	_idle_tick()
	var standing := World.tick < _idle_until or _idle_goal == NO_TILE
	pose = Pose.SIT if standing and idle != Idle.NONE else Pose.STAND


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
		if noise["kind"] == &"step" and not predator:
			var way := Senses.way_toward(tile, noise["at"])
			if way != Vector2i.ZERO:
				World.face(self, way)
			_heads_up_until = World.tick + ALERT_TICKS
			continue
		_flee(noise["at"])
		return


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
	_bold = night or pack >= PACK_BOLD
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
	return super()


## Fleeing: one of a herd's group first tries the steps away from its
## threat that leave the floor (World.walked_off): at a map edge with a
## neighbour, Main sends it there (crossing_off); else nothing comes of it
## and it runs on as any monster.
func _flee_tick() -> void:
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
