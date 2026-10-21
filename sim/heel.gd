class_name Heel
extends RefCounted
## Walking at someone's heel (decision 485): a companion's following (381,
## 391) cut out of Companion, so a body with no mind of hers (npc's escorted
## resident) walks with a player the same way. One per follower: follow()
## once a tick. The leader may go a few cells before she moves; she then
## makes for their heel (cell), the path found afresh every step, and once
## they stand stops there, or within STOP of them and not ahead. In a
## doorway, or across a building's walls from them, she moves however near.

## How far the leader gets before she sets off, and how close she comes
## when no heel cell is free.
const START := 3
const CLOSE := 1
## Where a follow stops (381): within this of the leader, behind their
## facing. While they walk (moved within WALKING_TICKS) she keeps on for
## the cell just behind them instead of stopping.
const STOP := 2
const WALKING_TICKS := 12
const NONE := Vector2i(-1, -1)

## How far the leader gets before she sets off (START; a companion's bond
## moves it, decision 555).
var start := START
## She has set off after the leader and not yet closed in.
var catching_up := false
var _leader_at := NONE
var _leader_moved := -1000


## One tick of [param body] following [param leader]: still, or one step
## for their heel. A leader gone stops it.
func follow(body: GridEntity, leader: GridEntity) -> void:
	if leader == null or not is_instance_valid(leader) or not leader.spawned:
		catching_up = false
		return
	var distance := World.distance(body.tile, leader.tile)
	if distance >= start and not catching_up:
		catching_up = true
	if leader.tile != _leader_at:
		_leader_at = leader.tile
		_leader_moved = World.tick
	# In a doorway, or on the other side of a building's walls from the
	# leader (they went in, or out): she moves, however near (391).
	var astray := Companion.door_cells().has(body.tile) or Companion._inside_of(body.tile) != Companion._inside_of(leader.tile)
	if astray:
		catching_up = true
	if not catching_up:
		return
	var walking := World.tick - _leader_moved <= WALKING_TICKS
	var heel := cell(body, leader)
	var ahead := ahead_of(body.tile - leader.tile, leader.facing) > 0
	if body.tile == heel:
		if not walking:
			catching_up = false
		return
	if not walking and not astray and (distance <= STOP and not ahead or heel == NONE and distance <= STOP):
		catching_up = false
		return
	if heel != NONE:
		step(body, heel, false)
	elif distance > CLOSE:
		# None free: as close as she can get; one that cannot get closer waits.
		step(body, leader.tile, true)


## The cell at [param leader]'s heel for [param body]: of the free walkable
## cells within STOP of them (hers among them), never a door's
## (Companion.door_cells), one on their side of a building's walls (inside
## with them, or outside), then one behind their facing (not ahead, nor
## beside if any behind is free), the nearest to them, then to her; NONE if
## none.
static func cell(body: GridEntity, leader: GridEntity) -> Vector2i:
	var best := NONE
	var best_key := Vector2i(1 << 20, 1 << 20)
	var doors := Companion.door_cells()
	var theirs := Companion._inside_of(leader.tile)
	for dy in range(-STOP, STOP + 1):
		for dx in range(-STOP, STOP + 1):
			var at := leader.tile + Vector2i(dx, dy)
			if at == leader.tile or World.distance(at, leader.tile) > STOP or doors.has(at):
				continue
			if at != body.tile and not (World.is_walkable(at) and World.is_free(at)):
				continue
			var along := ahead_of(Vector2i(dx, dy), leader.facing)
			var apart := 0 if Companion._inside_of(at) == theirs else 10
			var key := Vector2i(apart + (0 if along < 0 else 1 + along), World.distance(at, leader.tile) * 100 + World.distance(body.tile, at))
			if key.x < best_key.x or key.x == best_key.x and key.y < best_key.y:
				best_key = key
				best = at
	return best


## One A* step of [param body] toward [param goal], when its next move is
## due. False if there is no way there.
static func step(body: GridEntity, goal: Vector2i, occupied_goal_ok: bool) -> bool:
	if World.tick < body.next_move_tick:
		return true
	var path := World.find_path(body.tile, goal, occupied_goal_ok)
	if path.is_empty():
		return false
	World.try_move(body, path[0] - body.tile)
	return true


## How far [param offset] lies along [param facing] (a dot product).
static func ahead_of(offset: Vector2i, facing: Vector2i) -> int:
	return offset.x * facing.x + offset.y * facing.y
