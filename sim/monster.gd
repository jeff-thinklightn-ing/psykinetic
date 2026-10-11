class_name Monster
extends GridEntity
## Picks the nearest player it can see (within sight range, in line of sight).
## Attacks if that player is in melee reach, otherwise walks toward them.
##
## A monster of a kind (its level marker's, spawn_spec "kind") fights as
## that kind does (TACTICS), in a manner of its own (_temper, from its name):
## it makes for a tile beside its target that no other monster is making
## for, so a pack surrounds rather than queues (_pick_slot).

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
## A nearer target is taken over the one it has only when this much nearer.
const RETARGET_TILES := 2
const NO_TILE := Vector2i(-9999, -9999)
## How far (tiles looked at) it searches for a way to a tile beside its
## target before going straight at it instead.
const SLOT_SEARCH_TILES := 120

## A blow is coming (HEAVY): which way, over how many ticks. Views wind up.
signal winding(direction: Vector2i, ticks: int)

@export var sight_range := 7
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


func _init() -> void:
	super()
	mass = 40.0
	move_ticks = 4
	max_hp = 12
	attack_damage = 1
	strength = 6
	max_stamina = 60
	attack_ticks = 10
	# Its pace changes as it charges; a client slides its steps by it.
	replicate("move_ticks")


func _ready() -> void:
	super()
	# An explicit tint wins; otherwise colour by mass.
	if _sprite != null and tint.a <= 0.0:
		var heaviness := clampf(inverse_lerp(SHADE_LIGHT_MASS, SHADE_DARK_MASS, mass), 0.0, 1.0)
		_sprite.modulate = SHADE_LIGHT.lerp(SHADE_DARK, heaviness)
	if Net.is_authority():
		_temper()


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
	if seen != target:
		_noticed_tick = World.tick
		slot = NO_TILE
		_front_ticks = 0
	target = seen
	if target == null:
		_windup = {}
		return
	if tactic == Tactic.PLAIN:
		if World.can_melee(tile, target.tile):
			World.try_attack(self, target)
		elif World.tick >= next_move_tick:
			var path := World.find_path(tile, target.tile, true)
			if not path.is_empty():
				World.try_move(self, path[0] - tile)
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
		var path := World.find_path(tile, target.tile, true)
		if not path.is_empty():
			World.try_move(self, path[0] - tile)


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
	var aimed: GridEntity = _windup["target"]
	var direction: Vector2i = _windup["direction"]
	_windup = {}
	if is_instance_valid(aimed) and aimed.spawned and World.can_melee(tile, aimed.tile):
		World.try_attack(self, aimed)
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
	for entity in World.get_entities():
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
	for entity in World.get_entities():
		if entity != self and entity is Monster and World.are_adjacent(entity.tile, target.tile):
			return true
	return false


## The nearest player, or companion whose owner is online, in sight; the
## one it has kept unless another is RETARGET_TILES nearer.
## Entities still in their spawn grace are passed over.
func _nearest_visible_target() -> GridEntity:
	var nearest: GridEntity = null
	var nearest_distance := sight_range + 1
	var kept := -1
	for entity in World.get_entities():
		if entity.protected:
			continue  # Spawn grace.
		if entity is Player or (entity is Companion and entity.keeper != null):
			var d := World.distance(tile, entity.tile)
			if d <= sight_range and World.has_line_of_sight(tile, entity.tile):
				if entity == target:
					kept = d
				if d < nearest_distance:
					nearest = entity
					nearest_distance = d
	if tactic != Tactic.PLAIN and kept >= 0 and kept - nearest_distance < RETARGET_TILES:
		return target
	return nearest


func _world_winding(direction: Vector2i, ticks: int) -> void:
	winding.emit(direction, ticks)
	for peer in Net.sendable_peers():
		_net_winding.rpc_id(peer, direction, ticks)


@rpc("authority", "call_remote", "reliable")
func _net_winding(direction: Vector2i, ticks: int) -> void:
	winding.emit(direction, ticks)
