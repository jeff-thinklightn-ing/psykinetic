class_name Monster
extends GridEntity
## Picks the nearest player it can see (within sight range, in line of sight).
## Attacks if that player is in melee reach, otherwise walks toward them.
##
## A monster of a kind (its level marker's, spawn_spec "kind") fights as
## that kind does (TACTICS), in a manner of its own (_temper, from its name):
## it makes for a tile beside its target that no other monster is making
## for, so a pack surrounds rather than queues (_pick_slot).
##
## With nobody in sight it idles (Idle, level.json "idle", else by kind,
## IDLE_BY_KIND), at IDLE_PACE of its step time: GUARD stands at its home
## facing its set way and now and then glances aside; WANDER strolls about
## its home; PATROL walks a route of waypoints; GATHER stands or sits round
## a point, facing it. After a fight it walks back (home, its route, its
## place at the point) and goes on. Its facing is its level entry's, or one
## of its own from its name.
##
## It sees and hears by its Senses: a monster of a kind only what is lit
## (or carries a light) in a cone before it, a monster of no kind all
## round, as monsters did. Hearing something with nobody in sight it turns
## that way (LISTEN_TICKS) and may see who made it.
##
## A monster of a kind is more or less alert (Alert): a noise or a glimpse
## sends it to look (SUSPICIOUS), a target lost from sight or a fight heard
## after it (HUNTING), to where it last saw it and on the way it was going;
## there it looks round, and in time it gives up and goes back. Too far
## from where it took up the chase (LEASH) it gives up at once, and lets
## that one be a while (GIVE_UP_TICKS): escape is possible.
##
## Far from every player and companion it thinks less often, or not at all
## (World.Tier); the world tick moves it on then (_world_tick).

## Mass reads off the body: the sprite runs from SHADE_LIGHT at
## SHADE_LIGHT_MASS to SHADE_DARK at SHADE_DARK_MASS. Darker is heavier.
const SHADE_LIGHT_MASS := 20.0
const SHADE_DARK_MASS := 80.0
const SHADE_LIGHT := Color(1.0, 0.62, 0.55)
const SHADE_DARK := Color(0.33, 0.04, 0.08)

## PLAIN: straight at it, and hit it (a monster of no kind).
## DART: in, a blow, and (DART_AFTER_TICKS on, its blow played out) out of
##   reach again while it cools down.
## HEAVY: plods, charges the last CHARGE_RANGE tiles at CHARGE_PACE, and
##   winds up (WINDUP_TICKS) a blow that lands on its target only if it is
##   still in reach; a whiff otherwise, and a knock or a stun spoils it.
## FLANK: works round to its target's back or side before it strikes
##   (FLANK_PATIENCE_TICKS from the front at most); from behind, its blow
##   does BACKSTAB_DAMAGE more.
enum Tactic { PLAIN, DART, HEAVY, FLANK }
const TACTICS := {"imp": Tactic.DART, "brute": Tactic.HEAVY, "sneak": Tactic.FLANK}
const DART_AFTER_TICKS := 3
const CHARGE_RANGE := 4
const CHARGE_PACE := 0.5
const WINDUP_TICKS := 6
const FLANK_PATIENCE_TICKS := 20
const BACKSTAB_DAMAGE := 1
## Its manner, from its name: a step this much quicker or slower, a cooldown
## this many ticks either way, up to REACTION_TICKS_MAX to act on a new
## target, a chance a tick of PAUSE_CHANCE_MAX at most to stop a moment
## (PAUSE_TICKS) on the way in; bolder than HOLD_BACK_BELOW, or it waits
## HOLD_BACK_RANGE off until another monster is at its target or its target
## is under half its hp.
const PACE_SPREAD := 0.15
const COOLDOWN_SPREAD := 2
const REACTION_TICKS_MAX := 6
const PAUSE_CHANCE_MAX := 0.12
const PAUSE_TICKS := Vector2i(2, 6)
const HOLD_BACK_BELOW := 0.3
const HOLD_BACK_RANGE := 3
## Looking out is skipped while the nearest player or companion was, at the
## tier's last measure, this much beyond its sight: more than anyone walks,
## or is shoved, in World.TIER_EVERY_TICKS.
const LOOK_MARGIN_TILES := 8
## A nearer target is taken over the one it has only when this much nearer.
const RETARGET_TILES := 2
const NO_TILE := Vector2i(-9999, -9999)
## How far (tiles looked at) it searches for a way to a tile beside its
## target before going straight at it instead.
const SLOT_SEARCH_TILES := 120
## How far (tiles looked at) it searches for a way to its target itself
## (nowhere free beside it, or a monster of no kind): its target is in
## sight, so a way that needs more is round a crowd it cannot get through,
## not worth a search of the whole map every tick.
const CHASE_SEARCH_TILES := 400
## Hearing something with nobody in sight: it turns that way and holds
## still so long (ticks); a noise heard more than LISTEN_STALE_TICKS ago
## (it was not thinking then) is let go.
const LISTEN_TICKS := 20
const LISTEN_STALE_TICKS := 20
## How alert it is (shown over its head): IDLE, as it idles; SUSPICIOUS, a
## noise or a glimpse to look into, at its idle pace; HUNTING, a target
## lost from sight or a fight heard, at its chase pace; FIGHTING, a target
## in sight. A monster of no kind only idles and fights.
enum Alert { IDLE, SUSPICIOUS, HUNTING, FIGHTING }
## So long (ticks) since the last thing that roused it before it gives up.
const SUSPICIOUS_TICKS := 100
const HUNT_TICKS := 150
## At its lead it looks round: these turns (eighths of a turn from the way
## it faces), LOOK_TICKS each.
const LOOK_ROUND: Array[int] = [2, -4, 2]
const LOOK_TICKS := 10
## Hunting, it goes on past where it last saw its quarry so far (tiles) the
## way it was going: round the corner it went round.
const HUNT_ON_TILES := 2
## Fighting or hunting more than LEASH tiles from where it took up the
## chase, it gives up, and lets that one be for GIVE_UP_TICKS unless it
## comes within LEASH / 2 of there or strikes it.
const LEASH := 20
const GIVE_UP_TICKS := 100
## With no way to its target at all (a crowd round it), it looks for one
## again only after this many ticks: a crowd does not open in a tick.
const CHASE_RETRY_TICKS := 5

## What it does with nobody in sight. NONE: stands where it is (a monster of
## no kind, as monsters were).
enum Idle { NONE, GUARD, WANDER, PATROL, GATHER }
const IDLE_MODES := {"none": Idle.NONE, "guard": Idle.GUARD, "wander": Idle.WANDER, "patrol": Idle.PATROL,
	"gather": Idle.GATHER}
const IDLE_BY_KIND := {"imp": Idle.WANDER, "brute": Idle.GUARD, "sneak": Idle.PATROL}
## Idling it walks this much slower than it chases (its step time times this).
const IDLE_PACE := 1.6
## GUARD: a glance aside every so often (ticks), up to GLANCE_STEPS_MAX
## eighths of a turn (2: 90 degrees) either way, held a moment.
const GLANCE_EVERY_TICKS := Vector2i(30, 70)
const GLANCE_HOLD_TICKS := Vector2i(8, 20)
const GLANCE_STEPS_MAX := 2
## WANDER: to a free tile at most this far from home, then a pause.
const WANDER_RADIUS := 3
const WANDER_PAUSE_TICKS := Vector2i(15, 60)
## PATROL: a pause at each waypoint. With no route set, a loop of its own of
## PATROL_LOOP_POINTS about its home, PATROL_LOOP_RADIUS out.
const PATROL_PAUSE_TICKS := Vector2i(8, 25)
const PATROL_LOOP_POINTS := 4
const PATROL_LOOP_RADIUS := 3
## GATHER: its place is a free tile this near the point (not in fire); some
## sit there, by name, the rest stand.
const GATHER_RADIUS := 2
const SIT_CHANCE := 0.5
## How far (tiles looked at) it searches for its way home or about.
const IDLE_SEARCH_TILES := 400
## Choosing a tile to stroll to or a patrol waypoint within so many tiles of
## home, it looks at no more than this many tiles for each tile of the
## square round home that reaches: a spot only a long way round from home
## is not about home (and looking for it was most of a monster's first
## turn near a player).
const ABOUT_SEARCH_PER_TILE := 2
## How it is standing, for the views: SIT at a gathering.
enum Pose { STAND, SIT }
## The eight ways round, clockwise from north (for glances).
const AROUND: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]

## A blow is coming (HEAVY): which way, over how many ticks. Views wind up.
signal winding(direction: Vector2i, ticks: int)

## Off: no monster idles (they stand where they are, as before idling). For
## tests staged in a real level whose monsters must stay put.
static var idling := true

@export var sight_range := 7:
	set(value):
		sight_range = value
		if senses != null:
			senses.sight_range = value
## What it sees, hears and remembers (the server's; null on a client).
var senses: Senses
## How alert it is (Alert); the views show it.
var alert := Alert.IDLE
## Who it went for this tick (null for nobody), for the companions' minds.
var target: GridEntity
var tactic := Tactic.PLAIN
var reaction_ticks := 0
var boldness := 1.0
var pause_chance := 0.0
## The tile beside its target it is making for (NO_TILE: none).
var slot := NO_TILE
var _pace := 0.0
var _rng := RandomNumberGenerator.new()
var _noticed_tick := 0
## {target, lands, direction, from}: a blow wound up (HEAVY).
var _windup := {}
## DART: out of reach from _dart_from till _dart_until, cooling down.
var _dart_from := -1
var _dart_until := -1
## FLANK: ticks spent beside its target's front, ready to strike.
var _front_ticks := 0
## Idling: how, where home is (its level tile) and which way it faces there,
## its route (PATROL; loop, or back and forth), the point it gathers at.
var idle := Idle.NONE
var home := NO_TILE
var home_facing := Vector2i(0, 1)
var route: Array[Vector2i] = []
var route_loop := true
var gather_point := NO_TILE
var wander_radius := WANDER_RADIUS
var pose := Pose.STAND
var _idle_rng := RandomNumberGenerator.new()
## Going back after a fight.
var _returning := false
## WANDER's tile, GATHER's place.
var _idle_goal := NO_TILE
## Pausing, or holding a glance, till then.
var _idle_until := 0
## The tick of the last noise it turned to, and till when it listens.
var _listened_tick := -1
var _listening_until := -1
## Alertness (a monster of a kind: _wary): SUSPICIOUS or HUNTING till
## _alert_until; where it is making for (_lead), the turns it has looked
## there and till when it holds the last; whom it hunts, where it last saw
## them and where before that; where it took up the chase (_post, for the
## leash); whom it has given up on, till when (instance id -> tick); a
## glimpse this tick.
var _wary := false
var _alert_until := 0
var _lead := NO_TILE
var _looks := 0
var _look_until := -1
var _quarry: GridEntity
var _quarry_at := NO_TILE
var _quarry_from := NO_TILE
var _post := NO_TILE
var _given_up: Dictionary[int, int] = {}
var _glimpsed := NO_TILE
var _glancing := false
var _route_index := 0
var _route_step := 1
var _sits := false
## Woken, it idles from this tick on (_woke_up).
var _idle_from := 0
## The way it is walking as it idles, and where to (_idle_step).
var _idle_path: Array[Vector2i] = []
var _idle_path_to := NO_TILE
## How often it thinks (World.Tier), and the tick that was worked out (-1:
## not yet). World's.
var tier := 0
var tier_tick := -1
## Beyond World.VIEW_TILES of everyone when its tier was worked out: on
## nobody's screen. World's.
var beyond_view := false
## The tiles to the nearest player or companion when its tier was worked
## out (-1: not measured), and the zone's comings then. World's.
var nearest_sought := -1
var tier_comings := -1
## The World.steps of its last world tick (-1: none yet), and whether one
## is queued for it. World's.
var world_step := -1
var world_queued := false


func _init() -> void:
	super()
	mass = 40.0
	move_ticks = 4
	max_hp = 12
	attack_damage = 1
	strength = 6
	max_stamina = 60
	attack_ticks = 10
	tiered = true
	# Its pace changes as it charges and as it idles; a client slides its
	# steps by it.
	replicate("move_ticks")
	replicate("pose")
	replicate("alert")


func _ready() -> void:
	super()
	# An explicit tint wins; otherwise colour by mass.
	if _sprite != null and tint.a <= 0.0:
		var heaviness := clampf(inverse_lerp(SHADE_LIGHT_MASS, SHADE_DARK_MASS, mass), 0.0, 1.0)
		_sprite.modulate = SHADE_LIGHT.lerp(SHADE_DARK, heaviness)
	if Net.is_authority():
		_temper()
		_settle_idle()
		var kind := str(spawn_spec.get("kind", ""))
		_wary = TACTICS.has(kind)
		senses = Senses.new(self, sight_range, Senses.CONE_COS if _wary else -1.0)


## How it idles, where its home is and which way it faces, from its spawn
## spec ("home", "facing", "idle": as Level gives them), else by its kind and
## its name.
func _settle_idle() -> void:
	_idle_rng.seed = hash(String(name) + "/idle")
	var tile_given: Variant = spawn_spec.get("tile")
	home = spawn_spec.get("home", tile_given if tile_given is Vector2i else NO_TILE)
	var set_facing: Variant = spawn_spec.get("facing")
	home_facing = set_facing if set_facing is Vector2i and set_facing in AROUND else own_facing(String(name))
	facing = home_facing
	var given: Dictionary = spawn_spec.get("idle", {})
	var mode := str(given.get("mode", ""))
	idle = IDLE_MODES[mode] if IDLE_MODES.has(mode) else IDLE_BY_KIND.get(str(spawn_spec.get("kind", "")), Idle.NONE)
	route.assign(given.get("route", []))
	route_loop = bool(given.get("loop", true))
	var point: Variant = given.get("point")
	gather_point = point if point is Vector2i else home
	wander_radius = int(given.get("radius", WANDER_RADIUS))
	_sits = _idle_rng.randf() < SIT_CHANCE
	_idle_until = World.tick + _idle_rng.randi_range(0, GLANCE_EVERY_TICKS.y)


## Its kind's tactic and its own manner, the same every time for the same
## name (a respawn, a restart). A monster of no kind is PLAIN, as it was.
func _temper() -> void:
	var kind := str(spawn_spec.get("kind", ""))
	_pace = move_ticks
	if not TACTICS.has(kind):
		return
	tactic = TACTICS[kind]
	_rng.seed = hash(String(name))
	_pace = move_ticks * (1.0 + _rng.randf_range(-PACE_SPREAD, PACE_SPREAD))
	move_ticks = _pace
	attack_ticks = maxi(4, attack_ticks + _rng.randi_range(-COOLDOWN_SPREAD, COOLDOWN_SPREAD))
	reaction_ticks = _rng.randi_range(0, REACTION_TICKS_MAX)
	boldness = _rng.randf()
	pause_chance = _rng.randf_range(0.0, PAUSE_CHANCE_MAX)


func _sim_tick() -> void:
	var seen := _nearest_visible_target()
	if seen != null and _wary and _beyond_leash():
		_give_up(seen)
		seen = null
	if seen != target:
		_noticed_tick = World.tick
		slot = NO_TILE
		_front_ticks = 0
		if seen == null:
			if not _hunt(target):
				# The fight is over: back to where it idles, then on as before.
				_returning = idle != Idle.NONE
				if alert == Alert.FIGHTING:
					alert = Alert.IDLE
			_idle_goal = NO_TILE
			_glancing = false
		else:
			_quarry_at = seen.tile
			_quarry_from = NO_TILE
			if target == null:
				move_ticks = _pace
				pose = Pose.STAND
	target = seen
	if target == null:
		_windup = {}
		_alert_tick()
		return
	if alert == Alert.IDLE:
		_post = tile
	alert = Alert.FIGHTING
	_quarry = target
	if target.tile != _quarry_at:
		_quarry_from = _quarry_at
		_quarry_at = target.tile
	if tactic == Tactic.PLAIN:
		if World.can_melee(tile, target.tile):
			World.try_attack(self, target)
		elif World.tick >= next_move_tick:
			var path := World.find_path(tile, target.tile, true, null, CHASE_SEARCH_TILES)
			if not path.is_empty():
				World.try_move(self, path[0] - tile)
			else:
				next_move_tick = World.tick + CHASE_RETRY_TICKS  # No way in: look again in a moment.
		return
	if not _windup.is_empty():
		_wind_on()
		return
	if World.tick - _noticed_tick < reaction_ticks:
		return  # Sizing it up.
	var can_strike := World.tick >= next_attack_tick and World.tick >= next_move_tick
	if World.can_melee(tile, target.tile):
		if tactic == Tactic.DART and World.tick < _dart_until:
			if World.tick >= _dart_from:
				_step_out()
			return
		if not can_strike:
			return
		if tactic == Tactic.FLANK and _in_front() and _front_ticks < FLANK_PATIENCE_TICKS:
			_front_ticks += 1
			var round_to := _pick_slot()
			if round_to != NO_TILE and round_to != tile and _go_to(round_to):
				return
			if _front_ticks < FLANK_PATIENCE_TICKS:
				return
		_strike()
		return
	if tactic == Tactic.DART and World.tick < _dart_until:
		return  # Out of reach, cooling down.
	if World.tick < next_move_tick:
		return
	if boldness < HOLD_BACK_BELOW and World.distance(tile, target.tile) <= HOLD_BACK_RANGE and not _target_beset():
		return  # Waits for the others.
	if _rng.randf() < pause_chance:
		next_move_tick = World.tick + _rng.randi_range(PAUSE_TICKS.x, PAUSE_TICKS.y)
		return
	if tactic == Tactic.HEAVY:
		var charging := World.distance(tile, target.tile) <= CHARGE_RANGE \
				and World.has_clear_line(tile, target.tile)
		move_ticks = _pace * (CHARGE_PACE if charging else 1.0)
	slot = _pick_slot()
	if slot == NO_TILE or not _go_to(slot):
		# Nowhere free beside it: as near as it can get.
		var path := World.find_path(tile, target.tile, true, null, CHASE_SEARCH_TILES)
		if not path.is_empty():
			World.try_move(self, path[0] - tile)
		else:
			next_move_tick = World.tick + CHASE_RETRY_TICKS  # No way in: look again in a moment.


## A blow at its target, as its kind strikes.
func _strike() -> void:
	match tactic:
		Tactic.HEAVY:
			move_ticks = _pace
			var direction := target.tile - tile
			_windup = {"target": target, "lands": World.tick + WINDUP_TICKS, "direction": direction, "from": tile}
			World.face(self, direction)
			_world_winding(direction, WINDUP_TICKS)
		Tactic.FLANK:
			var behind := Vector2(tile - target.tile).dot(Vector2(target.facing)) < 0.0
			World.try_attack(self, target, attack_damage + (BACKSTAB_DAMAGE if behind else 0))
		_:
			if World.try_attack(self, target) and tactic == Tactic.DART:
				_dart_from = World.tick + DART_AFTER_TICKS
				_dart_until = next_attack_tick - ceili(_pace)


## A wound-up blow (HEAVY): lands when due if its target is still in reach,
## else a whiff; a knock off its tile or a stun spoils it.
func _wind_on() -> void:
	if tile != _windup["from"] or World.is_stunned(self):
		_windup = {}
		return
	if World.tick < int(_windup["lands"]):
		return
	# Untyped till checked: a target freed since (a player who died or left)
	# cannot be put in a GridEntity.
	var aimed: Variant = _windup["target"]
	var direction: Vector2i = _windup["direction"]
	_windup = {}
	if is_instance_valid(aimed) and (aimed as GridEntity).spawned and World.can_melee(tile, (aimed as GridEntity).tile):
		World.try_attack(self, aimed as GridEntity)
	else:
		World.try_swing(self, direction)


## DART: a step out of its target's reach, as far from it as it can.
func _step_out() -> void:
	if World.tick < next_move_tick:
		return
	var best := Vector2i.ZERO
	var best_score := -INF
	var away := Vector2(tile - target.tile).normalized()
	for direction in World.DIRECTIONS:
		var to := tile + direction
		if World.distance(to, target.tile) < 2 or not World.is_free(to) or not World.is_walkable(to) \
				or not World.can_melee(tile, to):
			continue
		var score := Vector2(direction).normalized().dot(away)
		if score > best_score:
			best = direction
			best_score = score
	if best != Vector2i.ZERO:
		World.try_move(self, best)


## A step toward [param to]; false if there is no way there.
func _go_to(to: Vector2i) -> bool:
	var path := World.find_path(tile, to, false, null, SLOT_SEARCH_TILES)
	if path.is_empty():
		return false
	World.try_move(self, path[0] - tile)
	return true


## The free tile beside its target that it can strike from and that no
## other monster is making for, nearest first; FLANK sooner behind or
## beside it. Its own (where it stands, or the one it was making for) a
## little sooner, so it does not dither. NO_TILE when there is none.
func _pick_slot() -> Vector2i:
	var claimed := {}
	for entity in World.monsters():
		if entity != self and entity is Monster and (entity as Monster).target == target:
			claimed[(entity as Monster).slot] = true
	var best := NO_TILE
	var best_score := INF
	var facing := Vector2(target.facing).normalized()
	for direction in World.DIRECTIONS:
		var at := target.tile + direction
		if claimed.has(at) or not World.is_walkable(at) or not World.can_melee(at, target.tile):
			continue
		var occupant := World.get_entity_at(at)
		if occupant != null and occupant != self:
			continue
		var score := float(World.distance(tile, at))
		if tactic == Tactic.FLANK:
			score += 3.0 * Vector2(direction).normalized().dot(facing)
		if at == tile or at == slot:
			score -= 0.5
		if score < best_score:
			best = at
			best_score = score
	return best


## FLANK: beside its target's front (where it faces, or either side of it).
func _in_front() -> bool:
	return Vector2(tile - target.tile).normalized().dot(Vector2(target.facing).normalized()) > 0.5


## Someone is already at its target, or its target is under half its hp.
func _target_beset() -> bool:
	if target.max_hp > 0 and target.hp * 2 < target.max_hp:
		return true
	for entity in World.monsters():
		if entity != self and entity is Monster and World.are_adjacent(entity.tile, target.tile):
			return true
	return false


## The nearest player, or companion whose owner is online, it sees
## (Senses.sees); the one it has kept unless another is RETARGET_TILES
## nearer.
## Entities still in their spawn grace are passed over.
func _nearest_visible_target() -> GridEntity:
	# Nobody near enough to be seen: its tier's measure (a few ticks old,
	# nobody come or gone since) is beyond its sight by more than anyone
	# could close meanwhile. Most looks end here.
	if target == null and nearest_sought > sight_range + LOOK_MARGIN_TILES \
			and tier_comings == World.zone.comings and World.tick - tier_tick < World.TIER_EVERY_TICKS:
		return null
	var nearest: GridEntity = null
	var nearest_distance := sight_range + 1
	var kept := -1
	_glimpsed = NO_TILE
	for entity in World.sought():
		# Out of sight range first: a few sums, where most looks end.
		var at := entity.tile
		var d := maxi(absi(at.x - tile.x), absi(at.y - tile.y))
		if d > sight_range or entity.protected:
			continue  # Too far, or in its spawn grace.
		if entity is Player or (entity is Companion and entity.keeper != null):
			if not _given_up.is_empty() and _letting_be(entity):
				continue
			# Its target it follows, cone or not (it turns as it goes).
			if senses.sees(entity, d, entity != target):
				if entity == target:
					kept = d
				if d < nearest_distance:
					nearest = entity
					nearest_distance = d
			elif _wary and alert == Alert.IDLE and _glimpsed == NO_TILE and senses.glimpses(entity, d):
				_glimpsed = at
	if tactic != Tactic.PLAIN and kept >= 0 and kept - nearest_distance < RETARGET_TILES:
		return target
	return nearest


## Nobody in sight: the newest noise it has not turned to yet, if fresh,
## turns it that way, and it holds still a moment (LISTEN_TICKS) to look.
## That noise ({} for none).
func _listen() -> Dictionary:
	if senses.heard.is_empty() or World.tick < next_move_tick or World.is_stunned(self):
		return {}
	var noise: Dictionary = senses.heard.back()
	var heard_at := int(noise["tick"])
	if heard_at <= _listened_tick:
		return {}
	_listened_tick = heard_at
	if World.tick - heard_at > LISTEN_STALE_TICKS:
		return {}
	var way := Senses.way_toward(tile, noise["at"])
	if way != Vector2i.ZERO:
		World.face(self, way)
	pose = Pose.STAND
	_glancing = true  # A guard turns back to its way after (_guard).
	_listening_until = World.tick + LISTEN_TICKS
	return noise


# --- Alertness ------------------------------------------------------------------

## Nobody in sight: a monster of no kind listens and idles; one of a kind is
## roused by what it hears or glimpses, and goes to look (_search) till it
## gives up.
func _alert_tick() -> void:
	var noise := _listen()
	if not _wary:
		_idle_tick()
		return
	if not noise.is_empty():
		_heard(noise)
	elif _glimpsed != NO_TILE and alert == Alert.IDLE:
		_follow(_glimpsed, Alert.SUSPICIOUS, SUSPICIOUS_TICKS)
	if alert == Alert.IDLE:
		_idle_tick()
		return
	if _beyond_leash():
		_give_up(_quarry)
		return
	if World.tick >= _alert_until:
		if alert == Alert.HUNTING:
			alert = Alert.SUSPICIOUS  # A last look about, then back.
			_follow(tile, Alert.SUSPICIOUS, SUSPICIOUS_TICKS / 2)
		else:
			_give_up(null)
			return
	_search()


## What a noise rouses it to: a fight (not through a wall), a door struck,
## a shout, to hunt; the rest to look. A blow on itself from someone it
## does not see, to hunt the one who struck it.
func _heard(noise: Dictionary) -> void:
	var at: Vector2i = noise["at"]
	var kind: StringName = noise["kind"]
	var urgent: bool = (kind == &"fight" and not noise.get("muffled", false)) or kind in [&"door_struck", &"door_broken"] \
			or int(noise["radius"]) >= Senses.NOISE_SHOUT
	var source: Variant = noise["source"]
	if at == tile and kind == &"fight" and is_instance_valid(source) and source != self:
		var striker := source as GridEntity
		_given_up.erase(striker.get_instance_id())
		_quarry = striker
		at = striker.tile
	if urgent:
		_listening_until = -1
	_follow(at, Alert.HUNTING if urgent else Alert.SUSPICIOUS, HUNT_TICKS if urgent else SUSPICIOUS_TICKS)


## [param lost] went out of its sight: after it, to where it last saw it and
## on HUNT_ON_TILES the way it was going. False (no hunt) for a monster of
## no kind, one gone, or one it has given up on.
func _hunt(lost: GridEntity) -> bool:
	if not _wary or lost == null or not is_instance_valid(lost) or not lost.spawned \
			or _given_up.has(lost.get_instance_id()):
		return false
	_quarry = lost
	var lead := _quarry_at if _quarry_at != NO_TILE else tile
	if _quarry_from != NO_TILE and _quarry_at != NO_TILE:
		var way := Vector2i(signi(_quarry_at.x - _quarry_from.x), signi(_quarry_at.y - _quarry_from.y))
		for n in range(HUNT_ON_TILES, 0, -1):
			var on := _quarry_at + way * n
			if World.is_walkable(on) and World.has_clear_line(_quarry_at, on):
				lead = on
				break
	_follow(lead, Alert.HUNTING, HUNT_TICKS)
	return true


## Off to [param lead] at [param level] (a hunt stays a hunt for a lesser
## lead), for [param ticks] from now; it looks round when there.
func _follow(lead: Vector2i, level: Alert, ticks: int) -> void:
	if alert == Alert.IDLE:
		_post = tile
	if not (alert == Alert.HUNTING and level == Alert.SUSPICIOUS):
		alert = level
	_alert_until = World.tick + ticks
	_lead = lead
	_looks = 0
	_look_until = -1
	_returning = false
	pose = Pose.STAND


## SUSPICIOUS or HUNTING: a step toward its lead (at its idle pace or its
## chase pace), else, there or with no way there, a look round.
func _search() -> void:
	if World.is_stunned(self) or World.tick < next_move_tick or World.tick < _listening_until \
			or World.tick < _look_until:
		return
	move_ticks = _pace if alert == Alert.HUNTING else _pace * IDLE_PACE
	if _lead != NO_TILE and tile != _lead:
		if _idle_step(_lead):
			return
		# No way there (a closed door, a crowd): it looks from here.
		_lead = NO_TILE
		next_move_tick = World.tick + CHASE_RETRY_TICKS
		return
	if _looks < LOOK_ROUND.size():
		World.face(self, turned(facing, LOOK_ROUND[_looks]))
		_looks += 1
		_look_until = World.tick + LOOK_TICKS


## More than LEASH from where it took up the chase.
func _beyond_leash() -> bool:
	return _post != NO_TILE and World.distance(tile, _post) > LEASH


## Lets [param who] be for GIVE_UP_TICKS (null: nobody in particular), and
## goes back to where it idles.
func _give_up(who: GridEntity) -> void:
	if who != null and is_instance_valid(who):
		_given_up[who.get_instance_id()] = World.tick + GIVE_UP_TICKS
	_calm()
	_returning = idle != Idle.NONE


## Whether it lets [param entity] be (given up on it, a while yet, and it is
## not back near where it took up the chase).
func _letting_be(entity: GridEntity) -> bool:
	var id := entity.get_instance_id()
	var until: int = _given_up.get(id, -1)
	if until < World.tick:
		_given_up.erase(id)
		return false
	return _post == NO_TILE or World.distance(entity.tile, _post) > LEASH / 2


## Back to IDLE: a monster that was looking or hunting goes back to where it
## idles (the world tick's walk, when far).
func _calm() -> void:
	if alert == Alert.SUSPICIOUS or alert == Alert.HUNTING:
		_returning = idle != Idle.NONE
		_idle_goal = NO_TILE
	alert = Alert.IDLE
	_lead = NO_TILE
	_quarry = null


# --- Idling ---------------------------------------------------------------------

## Nobody in sight: back from a fight first, then as it idles; slower than
## it chases.
func _idle_tick() -> void:
	if not idling or idle == Idle.NONE or World.is_stunned(self) or World.tick < next_move_tick \
			or World.tick < _listening_until:
		return
	if World.tick < _idle_from and not _returning:
		return  # Just woken: in a moment of its own.
	move_ticks = _pace * IDLE_PACE
	if _returning:
		var back := _back_to()
		if back == NO_TILE or tile == back or not _idle_step(back):
			_returning = false
			_idle_until = World.tick + _idle_rng.randi_range(PATROL_PAUSE_TICKS.x, PATROL_PAUSE_TICKS.y)
		return
	match idle:
		Idle.GUARD:
			_guard()
		Idle.WANDER:
			_wander()
		Idle.PATROL:
			_patrol()
		Idle.GATHER:
			_gather()


## Where it goes back to after a fight: home, or (PATROL) the nearest
## waypoint of its route, or (GATHER) its place at the point.
func _back_to() -> Vector2i:
	match idle:
		Idle.PATROL:
			_ensure_route()
			if route.is_empty():
				return home
			var nearest := 0
			for i in route.size():
				if World.distance(tile, route[i]) < World.distance(tile, route[nearest]):
					nearest = i
			_route_index = nearest
			return route[nearest]
		Idle.GATHER:
			return _gather_place()
	return home


## GUARD: at home, facing its way, and every so often a glance aside, held
## a moment, then back.
func _guard() -> void:
	if tile != home:
		if not _idle_step(home, IDLE_SEARCH_TILES, beyond_view):
			_idle_until = World.tick + PATROL_PAUSE_TICKS.y  # Someone is on it: wait.
		return
	if World.tick < _idle_until:
		return
	if _glancing or facing != home_facing:
		World.face(self, home_facing)
		_glancing = false
		_idle_until = World.tick + _idle_rng.randi_range(GLANCE_EVERY_TICKS.x, GLANCE_EVERY_TICKS.y)
		return
	var steps := _idle_rng.randi_range(1, GLANCE_STEPS_MAX) * (1 if _idle_rng.randf() < 0.5 else -1)
	World.face(self, turned(home_facing, steps))
	_glancing = true
	_idle_until = World.tick + _idle_rng.randi_range(GLANCE_HOLD_TICKS.x, GLANCE_HOLD_TICKS.y)


## WANDER: to a free tile near home, a pause, another.
func _wander() -> void:
	if World.tick < _idle_until:
		return
	if _idle_goal == tile:
		_idle_goal = NO_TILE
		_idle_until = World.tick + _idle_rng.randi_range(WANDER_PAUSE_TICKS.x, WANDER_PAUSE_TICKS.y)
		return
	if _idle_goal == NO_TILE:
		_idle_goal = _wander_goal()
		if _idle_goal == NO_TILE:
			_idle_until = World.tick + WANDER_PAUSE_TICKS.x
			return
	if not _idle_step(_idle_goal, _about_search(wander_radius), beyond_view):
		_idle_goal = NO_TILE
		_idle_until = World.tick + WANDER_PAUSE_TICKS.x


## A free tile it can walk to, at most wander_radius from home, not where it
## stands; NO_TILE if a few tries find none.
func _wander_goal() -> Vector2i:
	for i in 12:
		var at := home + Vector2i(_idle_rng.randi_range(-wander_radius, wander_radius),
				_idle_rng.randi_range(-wander_radius, wander_radius))
		if at == tile or not World.is_walkable(at) or not World.is_free(at) or World.is_fire(at):
			continue
		if _straight(tile, at, wander_radius * 2 + 2):
			_idle_path.clear()  # It walks there straight (_idle_step).
			return at
		if beyond_view:
			continue  # On nobody's screen: a spot it can walk to straight, or none.
		var path := World.find_path(tile, at, false, null, _about_search(wander_radius))
		if not path.is_empty():
			# The way there is the walk's first plan (_idle_step).
			_idle_path = path
			_idle_path_to = at
			return at
	return NO_TILE


## The step from [param from] toward [param to] that goes straight at it, or
## if that is shut one of its two halves (each nearer, never farther): ZERO
## if none. With [param now], only onto a free tile (the step it takes);
## without, by the terrain alone (whether it could walk there).
static func _direct_step(from: Vector2i, to: Vector2i, now: bool) -> Vector2i:
	var toward := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	for direction: Vector2i in [toward, Vector2i(toward.x, 0), Vector2i(0, toward.y)]:
		if direction != Vector2i.ZERO and World.terrain_step_open(from, direction) \
				and (not now or World.is_free(from + direction)):
			return direction
	return Vector2i.ZERO


## Whether one could walk from [param from] to [param to] by straight steps
## (_direct_step, the terrain alone) in [param steps] at most.
static func _straight(from: Vector2i, to: Vector2i, steps: int) -> bool:
	var at := from
	for i in steps:
		if at == to:
			return true
		var direction := _direct_step(at, to, false)
		if direction == Vector2i.ZERO:
			return false
		at += direction
	return at == to


## How many tiles a search for a spot within [param radius] of home looks
## at (ABOUT_SEARCH_PER_TILE).
static func _about_search(radius: int) -> int:
	return (radius * 2 + 1) * (radius * 2 + 1) * ABOUT_SEARCH_PER_TILE


## PATROL: waypoint to waypoint, a pause at each; round again (a loop) or
## back the way it came.
func _patrol() -> void:
	_ensure_route()
	if route.size() < 2 or World.tick < _idle_until:
		return
	var to := route[_route_index]
	if tile == to or not _idle_step(to, IDLE_SEARCH_TILES, beyond_view):
		# There (or no way there now: on to the next).
		if route_loop:
			_route_index = (_route_index + 1) % route.size()
		else:
			if _route_index + _route_step < 0 or _route_index + _route_step >= route.size():
				_route_step = -_route_step
			_route_index += _route_step
		_idle_until = World.tick + _idle_rng.randi_range(PATROL_PAUSE_TICKS.x, PATROL_PAUSE_TICKS.y)


## A route of its own when none is set (if World.take_plan allows it this
## step; till then it has none): home, then PATROL_LOOP_POINTS - 1
## tiles round it it can walk to, in turn round the compass from a way of
## its own, as a loop.
func _ensure_route() -> void:
	if not route.is_empty() or home == NO_TILE:
		return
	if not World.take_plan():
		return  # Enough worked out this step: it waits a step or two.
	route.append(home)
	var start := _idle_rng.randi_range(0, AROUND.size() - 1)
	var per := AROUND.size() / (PATROL_LOOP_POINTS - 1)
	for i in PATROL_LOOP_POINTS - 1:
		var way := AROUND[(start + i * per) % AROUND.size()]
		for reach in range(PATROL_LOOP_RADIUS, 0, -1):
			var at := home + way * reach
			# Straight from home if it can be walked so; a search only if not.
			if World.is_walkable(at) and not World.is_fire(at) and at not in route \
					and (_straight(home, at, PATROL_LOOP_RADIUS * 2) \
						or not World.find_path(home, at, true, null, _about_search(PATROL_LOOP_RADIUS)).is_empty()):
				route.append(at)
				break
	route_loop = true


## GATHER: to its place by the point, then facing the point, sitting or
## standing.
func _gather() -> void:
	var place := _gather_place()
	if place == NO_TILE:
		return
	if tile != place:
		pose = Pose.STAND
		if not _idle_step(place, IDLE_SEARCH_TILES, beyond_view):
			_idle_goal = NO_TILE  # Taken or cut off: another place.
			_idle_until = World.tick + PATROL_PAUSE_TICKS.y
		return
	var toward := gather_point - tile
	toward = Vector2i(signi(toward.x), signi(toward.y))
	if toward != Vector2i.ZERO and facing != toward:
		World.face(self, toward)
	pose = Pose.SIT if _sits else Pose.STAND


## Its place round the gather point: a free tile within GATHER_RADIUS (not
## the point, not fire, nearest the point first), one of its own by name
## among those; kept while it is free.
func _gather_place() -> Vector2i:
	if _idle_goal != NO_TILE and (_idle_goal == tile or World.is_free(_idle_goal)):
		return _idle_goal
	var places: Array[Vector2i] = []
	for reach in range(1, GATHER_RADIUS + 1):
		for dx in range(-reach, reach + 1):
			for dy in range(-reach, reach + 1):
				var at := gather_point + Vector2i(dx, dy)
				if World.distance(at, gather_point) != reach or not World.is_walkable(at) or World.is_fire(at):
					continue
				if at != tile and not World.is_free(at):
					continue
				places.append(at)
		if not places.is_empty():
			break
	if places.is_empty():
		return NO_TILE
	_idle_goal = places[absi(hash(String(name))) % places.size()]
	return _idle_goal


## A step toward [param to] as it idles, looking at [param max_tiles] at
## most for the way (a stroll's spot, near, less); false if there is no way.
## With [param straight_only] (idling on nobody's screen) only a straight
## step, never a search: false if that is shut, and it waits or goes
## elsewhere, as idling does when there is no way.
## Straight toward it when it can (_direct_step); else by a planned way,
## kept from step to step (_idle_path) and planned again only when the next
## step on it is taken, it is somewhere else (pushed, moved on by the world
## tick) or the goal has changed: planning at every step was most of what
## idling cost.
func _idle_step(to: Vector2i, max_tiles := IDLE_SEARCH_TILES, straight_only := false) -> bool:
	if _idle_path.is_empty() or _idle_path_to != to or World.distance(tile, _idle_path[0]) != 1 \
			or not World.is_free(_idle_path[0]):
		# Straight there if it can (most idle walks are a few tiles over open
		# floor): a few looks, where planning the way is a search.
		var direct := _direct_step(tile, to, true)
		if direct != Vector2i.ZERO:
			_idle_path.clear()
			return World.try_move(self, direct)
		if straight_only:
			return false  # Out of everyone's view: it waits, or goes elsewhere.
		_idle_path = World.find_path(tile, to, false, null, max_tiles)
		_idle_path_to = to
		if _idle_path.is_empty():
			return false
	if World.try_move(self, _idle_path[0] - tile):
		_idle_path.pop_front()
		return true
	_idle_path.clear()
	return false


## It thinks again after not thinking at all (World._tier: out of FAR, or
## its zone woken): its idling (a stroll, a glance, its loop) starts after
## a moment of its own, up to World.WAKE_SPREAD_TICKS, so a crowd woken
## together does not all choose and plan on one tick. Its looking out and
## fighting start at once.
func _woke_up() -> void:
	_idle_from = World.tick + id % World.WAKE_SPREAD_TICKS


## The world tick (far from everyone, or its zone asleep): [param seconds]
## gone by at once. A fight is over; one on its way back after a fight
## walks back (home, its route, its place at the point) as far as it would
## have in that time at its idle pace, by a real way (World.walk), and is
## back if it gets there. No hits.
func _world_tick(seconds: float) -> void:
	target = null
	slot = NO_TILE
	_windup = {}
	_glancing = false
	_calm()
	if not _returning:
		return
	move_ticks = _pace * IDLE_PACE
	# A patrol with no route yet goes home, its first waypoint, rather than
	# work its route out now: it does that when it is near and thinking.
	var back := home if idle == Idle.PATROL and route.is_empty() else _back_to()
	if back != NO_TILE and World.walk(self, back, seconds * World.TICK_RATE):
		_returning = false
		_idle_goal = NO_TILE


## The way a monster called [param monster_name] faces when its level entry
## sets none: one of AROUND, the same every time (the editor draws it).
static func own_facing(monster_name: String) -> Vector2i:
	return AROUND[absi(hash(monster_name + "/facing")) % AROUND.size()]


## [param direction] turned [param steps] eighths of a turn (clockwise for
## positive), one of AROUND.
static func turned(direction: Vector2i, steps: int) -> Vector2i:
	var at := AROUND.find(direction)
	if at < 0:
		return direction
	return AROUND[posmod(at + steps, AROUND.size())]


func _world_winding(direction: Vector2i, ticks: int) -> void:
	winding.emit(direction, ticks)
	for peer in viewers():
		_net_winding.rpc_id(peer, direction, ticks)


@rpc("authority", "call_remote", "reliable")
func _net_winding(direction: Vector2i, ticks: int) -> void:
	winding.emit(direction, ticks)
