extends Node
## Authoritative grid simulation (autoload "World").
##
## Owns terrain and tile occupancy, runs the fixed 10 Hz tick, and is the only
## code allowed to move entities. Every mutation is gated behind
## multiplayer.is_server(). See docs/design.md.

signal ticked(tick: int)
signal entity_moved(entity: GridEntity, from: Vector2i, to: Vector2i)
signal entity_damaged(entity: GridEntity, amount: int, source: GridEntity)
signal entity_despawned(entity: GridEntity)

const TICK_RATE := 10
const TICK_DT := 1.0 / TICK_RATE
## Ticks run per frame at most; beyond this the sim slows down instead of spiralling.
const MAX_CATCHUP_TICKS := 5
const DIRECTIONS: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP,
]

var tick := 0
## Fraction of the way from the last tick to the next one, in [0, 1). Read by rendering.
var tick_alpha := 0.0

var _floor: Dictionary[Vector2i, bool] = {}
var _walls: Dictionary[Vector2i, bool] = {}
var _occupancy: Dictionary[Vector2i, GridEntity] = {}
var _entities: Array[GridEntity] = []
var _accumulator := 0.0


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_accumulator += delta
	var steps := 0
	while _accumulator >= TICK_DT:
		_accumulator -= TICK_DT
		if steps < MAX_CATCHUP_TICKS:
			_step()
			steps += 1
	tick_alpha = _accumulator / TICK_DT


func _step() -> void:
	tick += 1
	# Spawn order. Iterate a copy: entities may despawn each other mid-tick.
	for entity in _entities.duplicate():
		if is_instance_valid(entity) and entity.spawned:
			entity._sim_tick()
	ticked.emit(tick)


# --- Mutations (server only) --------------------------------------------------

func reset() -> void:
	if not multiplayer.is_server():
		return
	for entity in _entities:
		if is_instance_valid(entity):
			entity._world_remove()
	_entities.clear()
	_occupancy.clear()
	_floor.clear()
	_walls.clear()
	tick = 0
	tick_alpha = 0.0
	_accumulator = 0.0


func load_terrain(floor_tiles: Array[Vector2i], wall_tiles: Array[Vector2i]) -> void:
	if not multiplayer.is_server():
		return
	_floor.clear()
	_walls.clear()
	for t in floor_tiles:
		_floor[t] = true
	for t in wall_tiles:
		_walls[t] = true


func spawn(entity: GridEntity, at: Vector2i) -> bool:
	if not multiplayer.is_server():
		return false
	if entity.spawned or not is_free(at):
		push_warning("World.spawn: cannot place %s at %s" % [entity.name, at])
		return false
	_occupancy[at] = entity
	_entities.append(entity)
	entity._world_place(at, tick)
	return true


func despawn(entity: GridEntity) -> void:
	if not multiplayer.is_server():
		return
	if not entity.spawned:
		return
	_occupancy.erase(entity.tile)
	_entities.erase(entity)
	entity._world_remove()
	entity_despawned.emit(entity)
	entity.queue_free()


## Moves [param entity] one tile in [param direction] (one of [constant DIRECTIONS]),
## pushing any chain of pushable entities whose total mass does not exceed the
## mover's. The only way an entity's tile ever changes.
func try_move(entity: GridEntity, direction: Vector2i) -> bool:
	if not multiplayer.is_server():
		return false
	if not entity.spawned or direction not in DIRECTIONS:
		return false
	if tick < entity.next_move_tick:
		return false
	if not _shift(entity, direction, entity.mass, entity.move_ticks):
		return false
	entity.next_move_tick = tick + entity.move_ticks
	return true


func try_attack(attacker: GridEntity, target: GridEntity) -> bool:
	if not multiplayer.is_server():
		return false
	if not attacker.spawned or not is_instance_valid(target) or not target.spawned:
		return false
	if tick < attacker.next_attack_tick or not are_adjacent(attacker.tile, target.tile):
		return false
	attacker.next_attack_tick = tick + attacker.attack_ticks
	damage(target, attacker.attack_damage, attacker)
	return true


func damage(target: GridEntity, amount: int, source: GridEntity = null) -> void:
	if not multiplayer.is_server():
		return
	if not target.spawned or target.max_hp <= 0 or amount <= 0:
		return
	target.hp = maxi(target.hp - amount, 0)
	target.damaged.emit(amount)
	entity_damaged.emit(target, amount, source)
	if target.hp == 0:
		despawn(target)


## Player intent. Clients will send this to the host by RPC once there is one.
func order_move(entity: GridEntity, target: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	if not entity.spawned:
		return
	entity.move_order = target
	entity.has_move_order = true


func _shift(entity: GridEntity, direction: Vector2i, push_budget: float, duration: int) -> bool:
	var from: Vector2i = entity.tile
	var to: Vector2i = from + direction
	if not is_walkable(to):
		return false
	var blocker: GridEntity = _occupancy.get(to)
	if blocker != null:
		if not blocker.pushable or blocker.mass > push_budget:
			return false
		if not _shift(blocker, direction, push_budget - blocker.mass, duration):
			return false
	_occupancy.erase(from)
	_occupancy[to] = entity
	entity._world_set_tile(to, tick, duration)
	entity_moved.emit(entity, from, to)
	return true


# --- Queries (safe anywhere) --------------------------------------------------

func is_walkable(at: Vector2i) -> bool:
	return _floor.has(at) and not _walls.has(at)


func is_free(at: Vector2i) -> bool:
	return is_walkable(at) and not _occupancy.has(at)


func get_entity_at(at: Vector2i) -> GridEntity:
	return _occupancy.get(at)


func get_entities() -> Array[GridEntity]:
	return _entities.duplicate()


func are_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return _manhattan(a, b) == 1


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


## A* over the occupancy grid, 4-connected. Returns the tiles to step through,
## excluding [param from] and including [param to]; empty if unreachable.
## With [param ignore_goal_occupant] the goal may be occupied (walk up to a
## monster, push a crate), but occupied tiles along the way still block.
func find_path(from: Vector2i, to: Vector2i, ignore_goal_occupant := false) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if from == to or not is_walkable(to):
		return path
	if _occupancy.has(to) and not ignore_goal_occupant:
		return path

	var open: Array[Vector2i] = [from]
	var closed: Dictionary[Vector2i, bool] = {}
	var came_from: Dictionary[Vector2i, Vector2i] = {}
	var cost: Dictionary[Vector2i, int] = {}
	cost[from] = 0

	while not open.is_empty():
		var best := 0
		var best_f: int = cost[open[0]] + _manhattan(open[0], to)
		for i in range(1, open.size()):
			var f: int = cost[open[i]] + _manhattan(open[i], to)
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
			if closed.has(next) or not is_walkable(next):
				continue
			if _occupancy.has(next) and next != to:
				continue
			var next_cost: int = cost[current] + 1
			if not cost.has(next) or next_cost < cost[next]:
				cost[next] = next_cost
				came_from[next] = current
				if next not in open:
					open.append(next)
	return path


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
