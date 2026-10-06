extends Node
## Authoritative grid simulation (autoload "World").
##
## Owns terrain and tile occupancy, runs the fixed 10 Hz tick, and is the only
## code allowed to move entities. Every mutation is gated behind
## Net.is_authority(), which is multiplayer.is_server() for anything that was
## not launched as a client. See docs/design.md.
##
## On a client nothing here simulates. World is then a read-only mirror: the
## tick arrives by RPC, entities arrive through MultiplayerSpawner /
## MultiplayerSynchronizer, and occupancy is rebuilt from their tiles. The
## mirror_* functions are the only writers and refuse to run on the server.

signal ticked(tick: int)
signal entity_moved(entity: GridEntity, from: Vector2i, to: Vector2i)
## [param cause] is &"attack", &"impact" or &"fire".
signal entity_damaged(entity: GridEntity, amount: int, source: GridEntity, cause: StringName)
signal entity_pushed(entity: GridEntity, by: GridEntity, direction: Vector2i, tiles: int, impact: int, stopped_by: String)
signal entity_despawned(entity: GridEntity)
## A player's command that is not a move, attack or shove: (name, args), for
## Main to act on. "order" {slot} is a companion order.
signal command_received(entity: GridEntity, command: String, args: Dictionary)

const TICK_RATE := 10
const TICK_DT := 1.0 / TICK_RATE
## Ticks run per frame at most; beyond this the sim slows down instead of spiralling.
const MAX_CATCHUP_TICKS := 5
## Orthogonals first so ties in pathfinding prefer straight steps.
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(1, -1),
]
const FIRE_DAMAGE := 2
## Clamp on mover_mass / target_mass when scaling push travel and impact.
const MASS_RATIO_MIN := 0.5
const MASS_RATIO_MAX := 1.5
const MAX_PUSH_SLIDE_TICKS := 3
## net_display_delay_ticks: how far in the past a client draws everything it
## does not predict. One tick means a replicated tile change is always in hand
## before its slide has to begin.
const NET_DISPLAY_DELAY_TICKS := 2
## The live value: settings.cfg's display_delay overrides the default.
var display_delay_ticks := NET_DISPLAY_DELAY_TICKS
## A diagonal step takes this many times the ticks of an orthogonal one (rounded
## up), so world speed is roughly constant in every direction. On screen a
## sideways diagonal covers 32 px against 18 px for an orthogonal step; at 1.0
## it would move nearly twice as fast as everything else.
const DIAGONAL_TICK_SCALE := 1.5
# Path costs are integers proportional to ticks. The +1 only breaks ties in
# favour of straight lines; fire is a detour worth five steps.
const PATH_STEP_COST := 1000
const PATH_DIAGONAL_COST := int(PATH_STEP_COST * DIAGONAL_TICK_SCALE)
const PATH_DIAGONAL_EXTRA := 1
const PATH_FIRE_EXTRA := 5000

## Share of the shove force that a melee attack carries.
const ATTACK_FORCE_FACTOR := 0.5
## Mass multiplier for being pushed while at 0 stamina.
const EXHAUSTED_MASS_FACTOR := 0.5

# Exported vars, not consts: GDScript cannot export constants.
## Impact damage per unit of force left over when a pushed entity is stopped.
@export var impact_per_force := 2
## FORCE_SCALE: force = strength x mover_mass / target_mass x this.
@export var force_scale := 0.1
## MAX_FORCE: upper clamp on that force.
@export var max_force := 4.0
## SHOVE_COST_BASE and SHOVE_COST_SCALE: a shove costs
## base + force x target_mass x scale stamina.
@export var shove_cost_base := 5.0
@export var shove_cost_scale := 0.15
## STAMINA_REGEN: stamina regained on a tick spent resting or walking.
@export var stamina_regen := 2
## A creature that is thrown into a wall or another entity, or is the one run
## into, is stunned for base + round(remaining force x per_force) ticks.
@export var stun_ticks_base := 4
@export var stun_ticks_per_force := 3.0
## Ticks after attacking, shoving or being thrown before regen resumes.
## 0 means only the tick of the exertion itself is lost.
@export var stamina_regen_delay := 10

var tick := 0
## Fraction of the way from the last tick to the next one, in [0, 1). Read by rendering.
var tick_alpha := 0.0

var _floor: Dictionary[Vector2i, bool] = {}
var _walls: Dictionary[Vector2i, bool] = {}
var _fire: Dictionary[Vector2i, bool] = {}
var _occupancy: Dictionary[Vector2i, GridEntity] = {}
## Always in ascending id order: ids are handed out in spawn order.
var _entities: Array[GridEntity] = []
var _hits: Array[Hit] = []
var _next_id := 1
var _accumulator := 0.0


## An attack or shove accepted this tick, waiting for the resolve phase.
class Hit:
	var source: GridEntity
	var target: GridEntity
	var source_id := 0
	var source_name := ""
	var target_name := ""
	## Where the target stood relative to the source when the hit was accepted.
	var direction := Vector2i.ZERO
	## Which way the target is pushed. The same as direction unless tossed.
	var push_direction := Vector2i.ZERO
	var damage := 0
	var force := 0.0


func _process(delta: float) -> void:
	if not Net.is_authority():
		# Mirror: no sim, only render time since the last replicated tick.
		_accumulator += delta
		tick_alpha = minf(_accumulator / TICK_DT, 1.0)
		return
	_accumulator += delta
	var steps := 0
	while _accumulator >= TICK_DT:
		_accumulator -= TICK_DT
		if steps < MAX_CATCHUP_TICKS:
			step()
			steps += 1
	tick_alpha = _accumulator / TICK_DT


## Advances the sim one tick. Driven by _process; tests call it directly.
func step() -> void:
	if not Net.is_authority():
		return
	tick += 1
	for entity in _entities:
		if entity.protected and tick >= entity.protected_until_tick:
			entity.protected = false
	# 1. Act, in ascending id. Iterate a copy: entities may despawn mid-tick.
	for entity in _entities.duplicate():
		# A stunned entity skips its turn; its orders wait for it.
		if _alive(entity) and not is_stunned(entity):
			entity._sim_tick()
	# 2. Hits (attacks and shoves) queued during the act phase.
	_resolve_hits()
	# 3. Hazard tiles.
	_apply_hazards()
	# 4. Stamina comes back for whoever did not exert themselves this tick.
	_regen_stamina()
	ticked.emit(tick)
	# 5. The tick counter goes to clients once per tick.
	if not multiplayer.get_peers().is_empty():
		_net_tick.rpc(tick)


# --- Mutations (server only) --------------------------------------------------

func reset() -> void:
	if not Net.is_authority():
		return
	for entity in _entities:
		if is_instance_valid(entity):
			entity._world_remove()
	_entities.clear()
	_occupancy.clear()
	_hits.clear()
	_floor.clear()
	_walls.clear()
	_fire.clear()
	_next_id = 1
	tick = 0
	tick_alpha = 0.0
	_accumulator = 0.0


func load_terrain(floor_tiles: Array[Vector2i], wall_tiles: Array[Vector2i],
		fire_tiles: Array[Vector2i] = []) -> void:
	if not Net.is_authority():
		return
	_floor.clear()
	_walls.clear()
	_fire.clear()
	for t in floor_tiles:
		_floor[t] = true
	for t in wall_tiles:
		_walls[t] = true
	for t in fire_tiles:
		_fire[t] = true


func spawn(entity: GridEntity, at: Vector2i) -> bool:
	if not Net.is_authority():
		return false
	if entity.spawned or not is_free(at):
		push_warning("World.spawn: cannot place %s at %s" % [entity.name, at])
		return false
	_occupancy[at] = entity
	_entities.append(entity)
	entity._world_place(_next_id, at)
	_next_id += 1
	return true


func despawn(entity: GridEntity) -> void:
	if not Net.is_authority():
		return
	if not entity.spawned:
		return
	_occupancy.erase(entity.tile)
	_entities.erase(entity)
	entity._world_remove()
	entity_despawned.emit(entity)
	entity.queue_free()


## Spawn grace: for [param ticks], or until it moves or attacks, monsters do
## not target [param entity].
func protect(entity: GridEntity, ticks: int) -> void:
	if not Net.is_authority():
		return
	if not entity.spawned:
		return
	entity.protected = true
	entity.protected_until_tick = tick + ticks


## Puts back state read from a snapshot, right after spawn. Values are clamped
## to what the entity allows; a facing that is not a direction is ignored.
func restore(entity: GridEntity, hp: int, stamina: int, facing: Vector2i) -> void:
	if not Net.is_authority():
		return
	if not entity.spawned:
		return
	if entity.max_hp > 0:
		entity.hp = clampi(hp, 1, entity.max_hp)
	if entity.max_stamina > 0:
		entity.stamina = clampi(stamina, 0, entity.max_stamina)
	if facing in DIRECTIONS:
		entity._world_set_facing(facing)


## Moves [param entity] one tile in [param direction] (one of [constant DIRECTIONS]),
## pushing any chain of pushable entities whose total mass does not exceed the
## mover's. Resolves immediately. Diagonals may not cut a wall corner.
func try_move(entity: GridEntity, direction: Vector2i) -> bool:
	if not Net.is_authority():
		return false
	if not entity.spawned or direction not in DIRECTIONS:
		return false
	if tick < entity.next_move_tick or is_stunned(entity):
		return false
	var duration := step_ticks(entity, direction)
	if not _shift(entity, entity, direction, entity.mass, duration):
		return false
	entity.next_move_tick = tick + duration
	entity._world_set_facing(direction)
	entity.protected = false  # Moving ends spawn grace.
	return true


## Melee: attack_damage plus a push of half the shove force, at no stamina
## cost. Queued; resolved after every entity has acted this tick.
func try_attack(attacker: GridEntity, target: GridEntity) -> bool:
	if not Net.is_authority():
		return false
	return _try_hit(attacker, target, attacker.attack_damage, false)


## Shove: no direct damage, only a push at full force, paid for in stamina
## whether or not anything moves. Queued like an attack.
##
## [param direction] aims it: Vector2i.ZERO pushes the target straight away
## from the attacker; one of [constant DIRECTIONS] tosses it that way instead.
## Tossed straight back at the attacker it goes over the attacker's head and
## lands on the tile behind, which must be free.
func try_shove(attacker: GridEntity, target: GridEntity,
		direction := Vector2i.ZERO) -> bool:
	if not Net.is_authority():
		return false
	if attacker.strength <= 0:
		return false
	return _try_hit(attacker, target, 0, true, direction)


## [param cause] is &"attack", &"impact" or &"fire". Only FLESH and WOOD with
## max_hp > 0 can be hurt; at 0 hp the entity is removed and its tile is empty.
func damage(target: GridEntity, amount: int, source: GridEntity = null,
		cause: StringName = &"attack") -> void:
	if not Net.is_authority():
		return
	if not target.spawned or amount <= 0 or not target.is_breakable():
		return
	target.hp = maxi(target.hp - amount, 0)
	target.damaged.emit(amount)
	entity_damaged.emit(target, amount, source, cause)
	if target.hp == 0:
		despawn(target)


## Player intent: walk to [param target]. Server only; input code on any peer
## goes through command_move().
func order_move(entity: GridEntity, target: Vector2i) -> void:
	if not Net.is_authority():
		return
	if not entity.spawned:
		return
	entity.move_order = target
	entity.has_move_order = true
	entity.action_order = GridEntity.Order.NONE
	entity.action_target = null


## Player intent: attack [param target] on the entity's next free tick.
func order_attack(entity: GridEntity, target: GridEntity) -> void:
	if not Net.is_authority():
		return
	_order_action(entity, GridEntity.Order.ATTACK, target, Vector2i.ZERO)


## Player intent: shove [param target] on the entity's next free tick.
## With a [param direction] it is a toss: the target goes that way instead of
## straight away from the entity.
func order_shove(entity: GridEntity, target: GridEntity, direction := Vector2i.ZERO) -> void:
	if not Net.is_authority():
		return
	if direction != Vector2i.ZERO and direction not in DIRECTIONS:
		return
	_order_action(entity, GridEntity.Order.SHOVE, target, direction)


func _order_action(entity: GridEntity, order: GridEntity.Order, target: GridEntity,
		direction: Vector2i) -> void:
	if not Net.is_authority():
		return
	if not entity.spawned or not target.spawned or entity == target:
		return
	if not can_target(entity, target):
		return
	entity.action_order = order
	entity.action_target = target
	entity.action_direction = direction
	entity.has_move_order = false


# --- Input from any peer ------------------------------------------------------
# Input code calls command_*. On the server that is the gated order_* directly;
# on a client it is an RPC to the server, which checks that the sender owns the
# entity before calling the same order_*. Clients never call try_*.

func command_move(entity: GridEntity, target: Vector2i) -> void:
	if Net.is_authority():
		order_move(entity, target)
	else:
		# Shown at once on this client; the server still decides what happens.
		entity.predict_move(target)
		request_move.rpc_id(1, entity.get_path(), target)


func command_attack(entity: GridEntity, target: GridEntity) -> void:
	if Net.is_authority():
		order_attack(entity, target)
	else:
		entity.predict_approach(target.tile)
		request_attack.rpc_id(1, entity.get_path(), target.get_path())


func command_shove(entity: GridEntity, target: GridEntity, direction := Vector2i.ZERO) -> void:
	if Net.is_authority():
		order_shove(entity, target, direction)
	else:
		entity.predict_approach(target.tile)
		request_shove.rpc_id(1, entity.get_path(), target.get_path(), direction)


@rpc("any_peer", "call_remote", "reliable")
func request_move(entity_path: NodePath, target: Vector2i) -> void:
	if not Net.is_authority():
		return
	var entity := _entity_owned_by_sender(entity_path)
	if entity != null:
		order_move(entity, target)


@rpc("any_peer", "call_remote", "reliable")
func request_attack(entity_path: NodePath, target_path: NodePath) -> void:
	if not Net.is_authority():
		return
	var entity := _entity_owned_by_sender(entity_path)
	var target := _entity_at_path(target_path)
	if entity != null and target != null:
		order_attack(entity, target)


@rpc("any_peer", "call_remote", "reliable")
func request_shove(entity_path: NodePath, target_path: NodePath, direction: Vector2i) -> void:
	if not Net.is_authority():
		return
	var entity := _entity_owned_by_sender(entity_path)
	var target := _entity_at_path(target_path)
	if entity != null and target != null:
		order_shove(entity, target, direction)


## Server: a player's step into [param tile] was refused this tick (someone
## else got there first). Its client re-plans at once instead of waiting
## for a position that is not going to change.
func report_move_refused(entity: GridEntity, tile: Vector2i) -> void:
	if not Net.is_authority():
		return
	if entity.owner_peer != 0 and entity.owner_peer != Net.local_id \
			and entity.owner_peer in multiplayer.get_peers():
		move_refused.rpc_id(entity.owner_peer, entity.get_path(), tile)


@rpc("authority", "call_remote", "reliable")
func move_refused(entity_path: NodePath, tile: Vector2i) -> void:
	var entity := get_node_or_null(entity_path) as GridEntity
	if entity != null:
		entity._on_move_refused(tile)


## Any other player command, from input code on any peer. On the server it
## is handed straight to command_received; on a client it goes by RPC.
func command(entity: GridEntity, command_name: String, args: Dictionary) -> void:
	if Net.is_authority():
		command_received.emit(entity, command_name, args)
	else:
		request_command.rpc_id(1, entity.get_path(), command_name, args)


@rpc("any_peer", "call_remote", "reliable")
func request_command(entity_path: NodePath, command_name: String, args: Dictionary) -> void:
	if not Net.is_authority():
		return
	var entity := _entity_owned_by_sender(entity_path)
	if entity != null:
		command_received.emit(entity, command_name, args)


func _entity_at_path(path: NodePath) -> GridEntity:
	var entity := get_node_or_null(path) as GridEntity
	if entity == null or not entity.spawned:
		return null
	return entity


## The entity at [param path], but only if the peer that sent the current RPC
## owns it. Anything else is rejected and logged.
func _entity_owned_by_sender(path: NodePath) -> GridEntity:
	var sender := multiplayer.get_remote_sender_id()
	if not Net.is_peer_authenticated(sender):
		_log("ignored order from unauthenticated peer %d" % sender)
		return null
	var entity := _entity_at_path(path)
	if entity == null or entity.owner_peer != sender:
		_log("rejected order from peer %d for %s" % [sender, path])
		return null
	return entity


# --- Client mirror (non-server only) -------------------------------------------
# Nothing derived is replicated. A client gets entity tiles and rebuilds the
# occupancy map from them; terrain comes from the same level data the server
# loaded.

@rpc("authority", "call_remote", "unreliable_ordered")
func _net_tick(server_tick: int) -> void:
	if Net.is_authority():
		return
	tick = server_tick
	_accumulator = 0.0
	tick_alpha = 0.0
	ticked.emit(tick)


func mirror_reset() -> void:
	if Net.is_authority():
		return
	_entities.clear()
	_occupancy.clear()
	_floor.clear()
	_walls.clear()
	_fire.clear()
	tick = 0
	tick_alpha = 0.0
	_accumulator = 0.0


func mirror_terrain(floor_tiles: Array[Vector2i], wall_tiles: Array[Vector2i],
		fire_tiles: Array[Vector2i] = []) -> void:
	if Net.is_authority():
		return
	_floor.clear()
	_walls.clear()
	_fire.clear()
	for t in floor_tiles:
		_floor[t] = true
	for t in wall_tiles:
		_walls[t] = true
	for t in fire_tiles:
		_fire[t] = true


func mirror_add(entity: GridEntity) -> void:
	if Net.is_authority():
		return
	if entity not in _entities:
		_entities.append(entity)
	entity._mirror_attach()
	mirror_changed()


func mirror_remove(entity: GridEntity) -> void:
	if Net.is_authority():
		return
	_entities.erase(entity)
	mirror_changed()


## Rebuilds occupancy from the entities' replicated tiles.
func mirror_changed() -> void:
	if Net.is_authority():
		return
	_occupancy.clear()
	for entity in _entities:
		_occupancy[entity.tile] = entity


func _try_hit(attacker: GridEntity, target: GridEntity, hit_damage: int, is_shove: bool,
		push_direction := Vector2i.ZERO) -> bool:
	if not Net.is_authority():
		return false
	if not attacker.spawned or not target.spawned or attacker == target:
		return false
	if not can_target(attacker, target) or is_stunned(attacker):
		return false
	if tick < attacker.next_attack_tick or not can_melee(attacker.tile, target.tile):
		return false
	# No hitting mid-step: the attacker's tile changes when a step starts, but
	# on screen it is still crossing over, so the blow would land from afar.
	if tick < attacker.next_move_tick:
		return false
	var aim: Vector2i = target.tile - attacker.tile
	if push_direction == Vector2i.ZERO:
		push_direction = aim
	elif push_direction not in DIRECTIONS:
		return false
	elif push_direction == -aim and not _can_land_behind(attacker, push_direction):
		# Overhead toss with nowhere to come down: refused, costs nothing.
		return false
	attacker.next_attack_tick = tick + attacker.attack_ticks
	attacker._world_set_facing(target.tile - attacker.tile)
	attacker._world_note_exertion(tick)
	attacker.protected = false  # So does attacking or shoving.
	var force := push_force(attacker, target)
	if is_shove:
		# Paid now, whatever the shove goes on to do. Short on stamina: the
		# force shrinks in proportion and everything left is spent.
		var cost := shove_cost(force, target)
		if attacker.max_stamina > 0 and cost > 0:
			if attacker.stamina < cost:
				force *= float(attacker.stamina) / cost
				attacker.stamina = 0
			else:
				attacker.stamina -= cost
	else:
		force *= ATTACK_FORCE_FACTOR
	var hit := Hit.new()
	hit.source = attacker
	hit.target = target
	hit.source_id = attacker.id
	hit.source_name = attacker.name
	hit.target_name = target.name
	hit.direction = aim
	hit.push_direction = push_direction
	hit.damage = hit_damage
	hit.force = force
	_hits.append(hit)
	return true


## Ascending source id. A hit whose target is no longer where it was aimed
## (an earlier hit or a move displaced something) is dropped, never re-aimed.
func _resolve_hits() -> void:
	if _hits.is_empty():
		return
	var hits := _hits
	_hits = []
	hits.sort_custom(func(a: Hit, b: Hit) -> bool: return a.source_id < b.source_id)
	for hit in hits:
		if not _alive(hit.source) or not _alive(hit.target) \
				or hit.target.tile != hit.source.tile + hit.direction:
			_log("hit dropped: %s -> %s (no longer lined up)" % [hit.source_name, hit.target_name])
			continue
		if hit.damage > 0:
			damage(hit.target, hit.damage, hit.source, &"attack")
		if hit.force > 0.0 and _alive(hit.target):
			_push(hit.source, hit.target, hit.push_direction, hit.force)


## Force push. The mover's mass is a budget: each body set in motion spends its
## own mass from it, and a body heavier than what is left does not move. A body
## travels up to floor(force * ratio) tiles; whatever force is left when
## something stops it becomes impact. Nothing here knows what kind of entity
## it is pushing.
func _push(mover: GridEntity, first: GridEntity, direction: Vector2i, force: float) -> void:
	var mover_mass: float = mover.mass
	var budget: float = mover_mass
	var body: GridEntity = first
	var f: float = force
	while body != null and f > 0.0:
		# An exhausted body counts as half its mass for everything below.
		var body_mass := pushed_mass(body)
		if body_mass > budget:
			_log("push: %s -> %s blocked: too heavy (mass %s, %s left)" % [
				mover.name, body.name, body_mass, budget])
			return
		budget -= body_mass

		var ratio := mass_ratio(mover_mass, body_mass)
		# Less than a tile's worth of force moves nothing and hurts nothing.
		var max_tiles: int = floori(f * ratio + 0.001)
		var start: Vector2i = body.tile
		var tiles := 0
		var stopped := false
		var collided := false
		var stopped_by := "nothing (force spent)"
		var blocker: GridEntity = null
		# An overhead toss: the first body is lifted over the mover's own tile
		# and comes down behind it. That is two tiles of travel in one go.
		var lofted := body == first and body.tile + direction == mover.tile
		if lofted:
			if max_tiles < 2:
				stopped_by = "nothing (too heavy to lift overhead)"
				max_tiles = 0
			elif not _can_land_behind(mover, direction):
				stopped_by = "nothing (no room to land)"
				max_tiles = 0
			else:
				var landing: Vector2i = mover.tile + direction
				body._world_note_moved(tick)
				_relocate(body, landing)
				tiles = 2
				if _fire.has(landing) and body.is_creature():
					stopped = true
					stopped_by = "fire"
					max_tiles = 0
		while tiles < max_tiles:
			var next: Vector2i = body.tile + direction
			if _terrain_blocks_step(body.tile, direction):
				stopped = true
				collided = true
				stopped_by = "wall"
				break
			blocker = _occupancy.get(next)
			if blocker != null:
				stopped = true
				collided = true
				stopped_by = blocker.name
				break
			_relocate(body, next)
			tiles += 1
			if _fire.has(next) and body.is_creature():
				stopped = true
				stopped_by = "fire"
				break

		# Force spent on travel, rounded up; the rest is what hits.
		var remaining := 0.0
		if stopped:
			remaining = maxf(f - ceili(tiles / ratio - 0.001), 0.0)
		var impact := impact_damage(remaining, ratio)

		if tiles > 0:
			body._world_slide_from(start, tick, clampi(tiles, 1, MAX_PUSH_SLIDE_TICKS))
		body._world_pushed(tiles, lofted and tiles > 0)
		var note := ""
		var next_body: GridEntity = null
		if impact > 0:
			_impact(body, impact, mover)
		# Running into something stuns, even with no force left to hurt.
		if collided:
			_stun(body, remaining)
		if blocker != null:
			_stun(blocker, remaining)
			var blocker_impact := impact_damage(
					remaining, mass_ratio(mover_mass, pushed_mass(blocker)))
			note = " (%s takes %d)" % [blocker.name, blocker_impact]
			if blocker_impact > 0:
				_impact(blocker, blocker_impact, mover)
			if _alive(blocker):
				next_body = blocker
		_log("push: %s -> %s dir=%s force=%.2f tiles=%d impact=%d stopped_by=%s%s" % [
			mover.name, body.name, direction, f, tiles, impact, stopped_by, note])
		entity_pushed.emit(body, mover, direction, tiles, impact, stopped_by)

		body = next_body
		f = remaining - 1.0


## True if a body tossed over [param mover] in [param direction] has a free
## tile to come down on directly behind it, with no wall in the way.
func _can_land_behind(mover: GridEntity, direction: Vector2i) -> bool:
	var from: Vector2i = mover.tile - direction
	return not _terrain_blocks_step(from, direction) \
			and not _terrain_blocks_step(mover.tile, direction) \
			and not _occupancy.has(mover.tile + direction)


## Creatures only. A longer stun replaces a shorter one; they do not add up.
func _stun(entity: GridEntity, remaining_force: float) -> void:
	if not _alive(entity) or not entity.is_creature():
		return
	var ticks := stun_ticks_base + roundi(remaining_force * stun_ticks_per_force)
	if tick + ticks > entity.stunned_until_tick:
		entity._world_stunned(tick + ticks, ticks)


func _impact(entity: GridEntity, amount: int, source: GridEntity) -> void:
	entity._world_impacted(amount)
	damage(entity, amount, source, &"impact")


## Resting and walking regain stamina. Attacking, shoving, or being moved more
## than one tile in a tick stops it for that tick and stamina_regen_delay more.
func _regen_stamina() -> void:
	for entity in _entities:
		if entity.max_stamina > 0 and entity.stamina < entity.max_stamina \
				and tick - entity.last_exertion_tick() > stamina_regen_delay:
			entity.stamina = mini(entity.stamina + stamina_regen, entity.max_stamina)


func _apply_hazards() -> void:
	if _fire.is_empty():
		return
	for entity in _entities.duplicate():
		if _alive(entity) and entity.is_creature() and _fire.has(entity.tile):
			damage(entity, FIRE_DAMAGE, null, &"fire")


## One walking step for [param entity], shoving the pushable chain ahead of it.
func _shift(mover: GridEntity, entity: GridEntity, direction: Vector2i, push_budget: float,
		duration: int) -> bool:
	var from: Vector2i = entity.tile
	var to: Vector2i = from + direction
	if _terrain_blocks_step(from, direction):
		return false
	var blocker: GridEntity = _occupancy.get(to)
	if blocker != null:
		if not blocker.pushable or blocker.mass > push_budget:
			return false
		if not _shift(mover, blocker, direction, push_budget - blocker.mass, duration):
			return false
	_relocate(entity, to)
	entity._world_slide_from(from, tick, duration)
	if entity != mover:
		entity._world_pushed(1)
		_log("push: %s -> %s dir=%s tiles=1 impact=0 stopped_by=nothing (walked into)" % [
			mover.name, entity.name, direction])
		entity_pushed.emit(entity, mover, direction, 1, 0, "nothing (walked into)")
	return true


func _relocate(entity: GridEntity, to: Vector2i) -> void:
	var from: Vector2i = entity.tile
	_occupancy.erase(from)
	_occupancy[to] = entity
	entity._world_set_tile(to)
	entity._world_note_moved(tick)
	entity_moved.emit(entity, from, to)


# --- Queries (safe anywhere) --------------------------------------------------

func is_walkable(at: Vector2i) -> bool:
	return _floor.has(at) and not _walls.has(at)


func is_free(at: Vector2i) -> bool:
	return is_walkable(at) and not _occupancy.has(at)


func is_fire(at: Vector2i) -> bool:
	return _fire.has(at)


func get_entity_at(at: Vector2i) -> GridEntity:
	return _occupancy.get(at)


func get_entities() -> Array[GridEntity]:
	return _entities.duplicate()


## True if occupancy and the entity list describe the same thing: every entity
## is the occupant of its own walkable tile, and nothing else is occupied.
func is_occupancy_consistent() -> bool:
	if _occupancy.size() != _entities.size():
		return false
	for entity in _entities:
		if not is_instance_valid(entity) or not is_walkable(entity.tile) \
				or _occupancy.get(entity.tile) != entity:
			return false
	return true


## Distance in steps (a diagonal is one step). Used for reach and sight range.
func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Ticks one walking step in [param direction] takes for [param entity].
func step_ticks(entity: GridEntity, direction: Vector2i) -> int:
	if direction.x != 0 and direction.y != 0:
		return ceili(entity.move_ticks * DIAGONAL_TICK_SCALE)
	return entity.move_ticks


func are_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return distance(a, b) == 1


## No friendly fire: an entity controlled by a peer may not attack or shove
## another peer-controlled entity. This is decided when a hit is accepted; the
## push code itself still treats every body alike, so a player can be caught
## by a crate or monster that someone else sent flying.
func can_target(attacker: GridEntity, target: GridEntity) -> bool:
	return attacker.owner_peer == 0 or target.owner_peer == 0


## Adjacent, and not diagonally across a wall corner.
func can_melee(from: Vector2i, to: Vector2i) -> bool:
	return are_adjacent(from, to) and not _cuts_corner(from, to - from)


func mass_ratio(mover_mass: float, target_mass: float) -> float:
	return clampf(mover_mass / maxf(target_mass, 0.001), MASS_RATIO_MIN, MASS_RATIO_MAX)


## Stunned entities cannot move, attack or shove, and skip their turn.
func is_stunned(entity: GridEntity) -> bool:
	return tick < entity.stunned_until_tick


## Mass used when [param entity] is on the receiving end of a push: halved
## while it is exhausted.
func pushed_mass(entity: GridEntity) -> float:
	return entity.mass * EXHAUSTED_MASS_FACTOR if entity.is_exhausted() else entity.mass


## Force of a shove by [param attacker] on [param target]:
## strength x mover_mass / target_mass x force_scale, clamped to max_force,
## then scaled by how much stamina the attacker has left. So pushes fade as
## the attacker tires, down to nothing at 0. A melee attack carries half.
func push_force(attacker: GridEntity, target: GridEntity) -> float:
	if attacker.strength <= 0:
		return 0.0
	var raw := attacker.strength * attacker.mass / maxf(pushed_mass(target), 0.001) * force_scale
	return clampf(raw, 0.0, max_force) * attacker.stamina_fraction()


func shove_cost(force: float, target: GridEntity) -> int:
	return roundi(shove_cost_base + force * pushed_mass(target) * shove_cost_scale)


func impact_damage(remaining_force: float, ratio: float) -> int:
	return roundi(remaining_force * impact_per_force * ratio)


func blocks_sight(at: Vector2i) -> bool:
	if _walls.has(at):
		return true
	var occupant: GridEntity = _occupancy.get(at)
	return occupant != null and occupant.blocks_sight


## Bresenham walk between two tiles; the endpoints themselves never block.
func has_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	var d: Vector2i = (to - from).abs()
	var s := Vector2i(1 if from.x < to.x else -1, 1 if from.y < to.y else -1)
	var err: int = d.x - d.y
	var at: Vector2i = from
	while at != to:
		var e2: int = 2 * err
		if e2 > -d.y:
			err -= d.y
			at.x += s.x
		if e2 < d.x:
			err += d.x
			at.y += s.y
		if at != to and blocks_sight(at):
			return false
	return true


## A* over the occupancy grid, 8-connected, costed in ticks (see
## [constant DIAGONAL_TICK_SCALE]).
## Returns the tiles to step through, excluding [param from] and including
## [param to]; empty if unreachable. Diagonals never cut a wall corner. Fire is
## walkable but avoided when a short detour exists.
## With [param ignore_goal_occupant] the goal may be occupied (walk up to a
## monster, push a crate), but occupied tiles along the way still block.
## [param ignore] is an entity whose own tile does not count as occupied
## (a client predicting for itself, whose replicated tile lags behind).
func find_path(from: Vector2i, to: Vector2i, ignore_goal_occupant := false,
		ignore: GridEntity = null) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if from == to or not is_walkable(to):
		return path
	if _occupancy.has(to) and not ignore_goal_occupant and _occupancy[to] != ignore:
		return path

	var open: Array[Vector2i] = [from]
	var closed: Dictionary[Vector2i, bool] = {}
	var came_from: Dictionary[Vector2i, Vector2i] = {}
	var cost: Dictionary[Vector2i, int] = {}
	cost[from] = 0

	while not open.is_empty():
		var best := 0
		var best_f: int = cost[open[0]] + _path_heuristic(open[0], to)
		for i in range(1, open.size()):
			var f: int = cost[open[i]] + _path_heuristic(open[i], to)
			if f < best_f:
				best = i
				best_f = f
		var current: Vector2i = open[best]
		open.remove_at(best)

		if current == to:
			while current != from:
				path.append(current)
				current = came_from[current]
			path.reverse()
			return path

		closed[current] = true
		for direction in DIRECTIONS:
			var next: Vector2i = current + direction
			if closed.has(next) or _terrain_blocks_step(current, direction):
				continue
			if _occupancy.has(next) and next != to and _occupancy[next] != ignore:
				continue
			var next_cost: int = cost[current]
			if direction.x != 0 and direction.y != 0:
				next_cost += PATH_DIAGONAL_COST + PATH_DIAGONAL_EXTRA
			else:
				next_cost += PATH_STEP_COST
			if _fire.has(next):
				next_cost += PATH_FIRE_EXTRA
			if not cost.has(next) or next_cost < cost[next]:
				cost[next] = next_cost
				came_from[next] = current
				if next not in open:
					open.append(next)
	return path


## Cheapest possible cost between two tiles on an empty grid.
func _path_heuristic(a: Vector2i, b: Vector2i) -> int:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	var diagonals := mini(dx, dy)
	return diagonals * PATH_DIAGONAL_COST + (maxi(dx, dy) - diagonals) * PATH_STEP_COST


## True if terrain alone forbids stepping from [param from] in [param direction]:
## the destination is not floor, or a diagonal would cut a wall corner.
func _terrain_blocks_step(from: Vector2i, direction: Vector2i) -> bool:
	return not is_walkable(from + direction) or _cuts_corner(from, direction)


## A diagonal cuts a corner if either orthogonal neighbour it passes between is
## not open floor. Entities standing there do not count.
func _cuts_corner(from: Vector2i, direction: Vector2i) -> bool:
	if direction.x == 0 or direction.y == 0:
		return false
	return not is_walkable(from + Vector2i(direction.x, 0)) \
			or not is_walkable(from + Vector2i(0, direction.y))


func _alive(entity: Variant) -> bool:
	return is_instance_valid(entity) and entity.spawned


func _log(message: String) -> void:
	print("[tick %d] %s" % [tick, message])
