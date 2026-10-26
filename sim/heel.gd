class_name Heel
extends RefCounted
## Walking at someone's heel (decision 485): a companion's following (381,
## 391) cut out of Companion, so a body with no mind of hers (npc's escorted
## resident) walks with a player the same way. One per follower: follow()
## once a tick. The leader may go a few cells before she moves; she then
## makes for their heel (cell), the path found afresh every step, and once
## they stand stops there, or within STOP of them and not ahead. In a
## doorway, or across a building's walls from them, she moves however near.
## She keeps out of the cells the leader is walking into (keep_clear), keeps
## her heel cell while it serves rather than picking it again each tick,
## and walks the pulled line (678, companions' side).

## How far the leader gets before she sets off, and how close she comes
## when no heel cell is free.
const START := 3
const CLOSE := 1
## Where a follow stops (381): within this of the leader, behind their
## facing. While they walk (moved within WALKING_TICKS) she keeps on for
## the cell just behind them instead of stopping.
const STOP := 2
const WALKING_TICKS := 12
## How long after a step's end the leader still counts as walking on
## (travel, keep_clear): a held key's next step is due by then.
const WALK_ON_TICKS := 3
## How far ahead along a free leader's velocity his next cells are read
## (free_cells, 688): two cells, about what he walks in the ticks she needs
## to step aside.
const FREE_AHEAD := 2.0
## How long after the leader's last step ends she waits on their
## footsteps before closing in to their heel (a stop, then a turn straight
## back, walked into her as she came up).
const SETTLE_TICKS := 6
## How many of the leader's footsteps are kept (_trail).
const TRAIL_KEPT := 4
## A heel goal found with no way (the leader across water, behind a locked
## door, on a roof): she asks for a way again only after NO_WAY_TICKS, and
## passes that cell over for NO_WAY_KEPT (685 amended): each unanswered
## search walked the whole zone, every tick.
const NO_WAY_TICKS := 20
const NO_WAY_KEPT := 100
const NONE := Vector2i(-1, -1)
## The cells _aside's one-step search closes at most (685): a one-step way
## lies within the 7 by 7 round her.
const ASIDE_SEARCH_TILES := 49

## How far the leader gets before she sets off (START; a companion's bond
## moves it, decision 555).
var start := START
## She has set off after the leader and not yet closed in.
var catching_up := false
var _leader_at := NONE
var _leader_moved := -1000
## The heel cell she makes for, kept while it serves (678, companions' side).
var _goal := NONE
## The leader's last cells, newest first, a step apart (their footsteps).
var _trail: Array[Vector2i] = []
## Her goal is one of their footsteps (_footstep), dropped when they stop.
var _on_trail := false
## Goals found with no way, each to the tick it may be tried again, and the
## tick before which she asks for no way at all (685 amended).
var _no_way: Dictionary[Vector2i, int] = {}
var _no_way_until := -1
## Ways asked for (step's searches), for tests and benches.
static var searches := 0


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
		if _leader_at != NONE and World.distance(_leader_at, leader.tile) == 1:
			_trail.push_front(_leader_at)
			_trail.resize(mini(_trail.size(), TRAIL_KEPT))
		else:
			_trail.clear()  # A jump (a link, a respawn): no footsteps to follow.
		_leader_at = leader.tile
		_leader_moved = World.tick
	# In a doorway, or on the other side of a building's walls from the
	# leader (they went in, or out): she moves, however near (391).
	var astray := Companion.door_cells().has(body.tile) or Companion._inside_of(body.tile) != Companion._inside_of(leader.tile)
	if astray:
		catching_up = true
	if not catching_up:
		_goal = NONE
		# Settled, and his held line or order runs through her cell: she steps
		# aside at once, else stays and his step swaps them (678, companions'
		# side, amended; ui's bench: his straight line fell to a route round her).
		var clear := keep_clear(leader)
		if clear.has(body.tile):
			var aside := _aside(body, leader, clear)
			if aside != NONE:
				step(body, aside, false, leader)
		return
	var walking := World.tick - _leader_moved <= WALKING_TICKS
	var way := travel(leader)
	var clear := keep_clear(leader)
	# Cells found with no way lately are passed over as goals (685 amended).
	var avoid := clear
	if not _no_way.is_empty():
		avoid = clear.duplicate()
		for at: Vector2i in _no_way.keys():
			if World.tick >= _no_way[at]:
				_no_way.erase(at)
			else:
				avoid[at] = true
	# Beside her walking leader and out of their way she stays put while
	# they go by (a turn back toward her): no step round to their new back
	# and straight back again (678, companions' side).
	if walking and not astray and distance <= CLOSE and not clear.has(body.tile):
		return
	# Walking on, she makes for their footsteps, so she goes along the line
	# they walk (Jeff on v0.1.179: "Pip now does zig zag run behind me");
	# else a heel cell, kept while it serves.
	var footstep := _footstep(body, leader, avoid) if walking_on(leader) else NONE
	if footstep != NONE:
		_goal = footstep
		_on_trail = true
	elif clear.has(body.tile):
		_goal = _aside(body, leader, clear)  # In their way: a step aside, not round them.
		_on_trail = false
	elif _on_trail and World.tick <= leader.step_until + SETTLE_TICKS and _serves(_goal, body, leader, way, avoid):
		pass  # Stopped a moment ago: a turn straight back may come; she waits a cell back.
	elif _on_trail and World.free_body(leader) and _serves(_goal, body, leader, way, avoid):
		# A free body sets off any way at any tick (688): a footstep that
		# serves is kept, not left for a cell nearer he may walk into.
		_on_trail = false
	elif _on_trail or not _serves(_goal, body, leader, way, avoid):
		# They stopped (or a footstep went): their heel, a cell nearer.
		_goal = cell(body, leader, avoid, way)
		_on_trail = false
	var heel := _goal
	var ahead := ahead_of(body.tile - leader.tile, way) > 0
	if body.tile == heel:
		if not walking:
			catching_up = false
		return
	if not walking and not astray and (distance <= STOP and not ahead or heel == NONE and distance <= STOP):
		catching_up = false
		return
	if World.tick < _no_way_until:
		return  # No way a moment ago: she waits before asking again (685 amended).
	var went := true
	if heel != NONE:
		went = step(body, heel, false, leader)
	elif distance > CLOSE:
		# None free: as close as she can get; one that cannot get closer waits.
		went = step(body, leader.tile, true, leader)
	if not went:
		_no_way_until = World.tick + NO_WAY_TICKS
		if heel != NONE:
			_no_way[heel] = World.tick + NO_WAY_KEPT  # Next time the next-best heel cell.
		_goal = NONE


## The nearest of [param leader]'s last cells (their footsteps) a cell back
## from them and within STOP that she may make for: out of their way
## ([param clear]), not a door's, on their side of a building's walls, and
## free or hers, nearer them than she is; NONE if none. A cell back, so a
## turn straight back does not walk into her. Their step due this tick and
## not yet taken counts as taken: she sets off with it, not a tick behind.
func _footstep(body: GridEntity, leader: GridEntity, clear: Dictionary) -> Vector2i:
	var lead := leader.tile
	var steps: Array[Vector2i] = _trail.duplicate()
	var next := next_cells(leader)
	var due := World.tick >= leader.next_move_tick and leader.last_step_tick != World.tick
	if due and not next.is_empty() and World.distance(next[0], leader.tile) == 1 and World.is_free(next[0]):
		lead = next[0]
		steps.push_front(leader.tile)
	for at: Vector2i in steps.slice(1):
		if World.distance(at, lead) > STOP:
			break
		if clear.has(at) or Companion.door_cells().has(at) or Companion._inside_of(at) != Companion._inside_of(leader.tile):
			continue
		if at == body.tile:
			return at
		# Only one that brings her nearer them: none back onto their line
		# after a step aside, a cell no nearer.
		if World.is_walkable(at) and World.is_free(at) and World.distance(at, lead) < World.distance(body.tile, lead):
			return at
	return NONE


## A step out of [param leader]'s way for [param body] standing in it: the
## free walkable cell next to her, within STOP of them and out of their way
## ([param clear]), never a door's, nearest them; NONE if none.
static func _aside(body: GridEntity, leader: GridEntity, clear: Dictionary) -> Vector2i:
	var best := NONE
	for way: Vector2i in World.DIRECTIONS:
		var at := body.tile + way
		if clear.has(at) or World.distance(at, leader.tile) > STOP or Companion.door_cells().has(at):
			continue
		if not (World.is_walkable(at) and World.is_free(at)) or World.find_path(body.tile, at, false, null, ASIDE_SEARCH_TILES).size() != 1:
			continue
		if best == NONE or World.distance(at, leader.tile) < World.distance(best, leader.tile):
			best = at
	return best


## Whether her kept heel cell [param goal] still serves: within STOP of
## [param leader], walkable and free (or hers), out of their way
## ([param clear]) and not ahead of where they go ([param way]).
static func _serves(goal: Vector2i, body: GridEntity, leader: GridEntity, way: Vector2i, clear: Dictionary) -> bool:
	if goal == NONE or clear.has(goal) or World.distance(goal, leader.tile) > STOP or Companion.door_cells().has(goal):
		return false
	if goal != body.tile and not (World.is_walkable(goal) and World.is_free(goal)):
		return false
	return Companion._inside_of(goal) == Companion._inside_of(leader.tile) and ahead_of(goal - leader.tile, way) <= 0


## The next two cells of [param leader]'s way, a player's (WASD steps
## queued, the via cells, else the line to their move order); none known,
## or not a player's, empty.
static func next_cells(leader: GridEntity) -> Array[Vector2i]:
	var next: Array[Vector2i] = []
	var player := leader as Player
	if player == null:
		return next
	if World.free_body(player):
		return free_cells(player)
	var at := player.tile
	for queued: Dictionary in player.queued_steps.slice(0, 2):
		at += queued["direction"] as Vector2i
		next.append(at)
	if next.is_empty():
		next.assign(player.move_via.slice(0, 2))
	if next.is_empty() and player.has_move_order and player.move_order != player.tile:
		next.assign(World.line_cells(player.tile, player.move_order).slice(0, 2))
	return next


## A free-walking leader's next cells (688; 689 sends no route, only the
## way he is pressed): the cells his centre crosses within FREE_AHEAD cells
## along his velocity, as World.free_cell would hold them, read every
## FREE_HYSTERESIS so the corner of a cell his slant grazes counts (his
## claim bumps her there), three at most so a graze keeps the cell after.
static func free_cells(leader: GridEntity) -> Array[Vector2i]:
	var next: Array[Vector2i] = []
	if leader.free_way.length() < 0.001:
		return next
	var way := leader.free_way.normalized()
	var d := World.FREE_HYSTERESIS
	while d <= FREE_AHEAD and next.size() < 3:
		var at := World.free_cell(leader, leader.free_pos + way * d)
		if at != leader.tile and not next.has(at):
			next.append(at)
		d += World.FREE_HYSTERESIS
	return next


## Whether [param leader] is still walking on: within WALK_ON_TICKS of
## their last step's end (a held key's next step is due by then).
static func walking_on(leader: GridEntity) -> bool:
	return World.tick <= leader.step_until + WALK_ON_TICKS and leader.step_velocity != Vector2.ZERO


## Where [param leader] is going: the way of their last step while they
## walk on, else their facing.
static func travel(leader: GridEntity) -> Vector2i:
	if walking_on(leader):
		# A free body's slant counts as a diagonal only past half way to one
		# (688): a shallow slant is the straight it mostly goes.
		var v := leader.step_velocity.normalized()
		var lean := 0.38 if World.free_body(leader) else 0.001
		return Vector2i(signi(v.x) if absf(v.x) > lean else 0, signi(v.y) if absf(v.y) > lean else 0)
	return leader.facing


## The cells a follower keeps out of (678, companions' side; Jeff: "she
## catches up into the same tile and bounces off"): [param leader]'s own,
## the next two of a player's way (WASD steps queued, the via cells, else
## the line to their move order), and while they walk on two along their
## last step. Her step into the cell he stepped into on the same tick was a
## swap (679) drawn as her sliding in and straight back out.
static func keep_clear(leader: GridEntity) -> Dictionary:
	var clear := {leader.tile: true}
	for each in next_cells(leader):
		clear[each] = true
	if walking_on(leader):
		var way := travel(leader)
		clear[leader.tile + way] = true
		clear[leader.tile + way * 2] = true
	return clear


## The cell at [param leader]'s heel for [param body]: of the free walkable
## cells within STOP of them (hers among them), never a door's
## (Companion.door_cells) nor one of [param clear] (keep_clear), one on
## their side of a building's walls (inside with them, or outside), then one
## behind [param way] (their facing by default; not ahead, nor beside if any
## behind is free), the nearest to them, then to her; NONE if none.
static func cell(body: GridEntity, leader: GridEntity, clear := {}, way := NONE) -> Vector2i:
	if way == NONE:
		way = leader.facing
	var best := NONE
	var best_key := Vector2i(1 << 20, 1 << 20)
	var doors := Companion.door_cells()
	var theirs := Companion._inside_of(leader.tile)
	for dy in range(-STOP, STOP + 1):
		for dx in range(-STOP, STOP + 1):
			var at := leader.tile + Vector2i(dx, dy)
			if at == leader.tile or World.distance(at, leader.tile) > STOP or doors.has(at) or clear.has(at):
				continue
			if at != body.tile and not (World.is_walkable(at) and World.is_free(at)):
				continue
			var along := ahead_of(Vector2i(dx, dy), way)
			var apart := 0 if Companion._inside_of(at) == theirs else 10
			var key := Vector2i(apart + (0 if along < 0 else 1 + along), World.distance(at, leader.tile) * 100 + World.distance(body.tile, at))
			if key.x < best_key.x or key.x == best_key.x and key.y < best_key.y:
				best_key = key
				best = at
	return best


## One step of [param body] toward [param goal], when its next move is
## due: on the pulled line (World.walk_path, 678) where the way is 3 cells
## or more and its goal may be stood on, else find_path's. A step into a
## cell [param leader] is walking into (keep_clear) waits instead: she
## stops short rather than bump (678, companions' side). False if there is
## no way there.
static func step(body: GridEntity, goal: Vector2i, occupied_goal_ok: bool, leader: GridEntity = null) -> bool:
	if World.tick < body.next_move_tick:
		return true
	searches += 1
	var path := World.find_path(body.tile, goal, occupied_goal_ok)
	if path.is_empty():
		return false
	if path.size() >= 3 and (occupied_goal_ok or World.is_free(goal)):
		var pulled := World.walk_path(body.tile, goal, body)
		if not pulled.is_empty():
			path = pulled
	if leader != null and is_instance_valid(leader) and leader.spawned and path[0] != goal and keep_clear(leader).has(path[0]):
		return true
	World.try_move(body, path[0] - body.tile)
	return true


## How far [param offset] lies along [param facing] (a dot product).
static func ahead_of(offset: Vector2i, facing: Vector2i) -> int:
	return offset.x * facing.x + offset.y * facing.y
