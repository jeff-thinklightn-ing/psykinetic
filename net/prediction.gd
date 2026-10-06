class_name MovePrediction
extends RefCounted
## Client-side prediction of the local player's own walking. Presentation
## only: it decides where the sprite is drawn, never where the entity is.
##
## When the client orders a move it works out the path the server will most
## likely take, against the replicated world (every other entity's current
## tile counts as taken), and starts showing it at once. Just before each
## step begins it looks again: if that tile has since been taken, the rest
## of the path is re-planned, the way the server re-paths every step.
##
## Each replicated tile that arrives from the server is checked against the
## steps already shown:
##   - it is the next shown step: confirmed, nothing visible happens;
##   - it is anything else, or no confirmation arrives in time, or the server
##     says a step was refused: a misprediction. The owner then calls
##     rebase(): the sprite blends from where it is to the server's tile over
##     a couple of ticks and the path is re-planned from there. Only an error
##     of more than SNAP_TILES is snapped (see GridEntity).
## Only walking is predicted. Being pushed is never predicted.

## How long past its expected confirmation (start + round trip) a shown step
## may stay unconfirmed before it counts as a misprediction.
const RECONCILE_GRACE_TICKS := 4.0


class Step:
	var from := Vector2i.ZERO
	var to := Vector2i.ZERO
	## Where the sprite goes between; usually the two tiles' centres.
	var from_pos := Vector2.ZERO
	var to_pos := Vector2.ZERO
	## On the prediction clock, in ticks.
	var start := 0.0
	var duration := 1.0
	var deadline := 0.0
	var started := false
	var confirmed := false


var _entity: GridEntity
var _steps: Array[Step] = []
## Local time in ticks, advanced by frame time, so shown motion does not
## depend on when server packets happen to arrive.
var _clock := 0.0
## The order being carried out, for re-planning.
var _has_target := false
var _target := Vector2i.ZERO
var _into_goal := true


func _init(entity: GridEntity) -> void:
	_entity = entity


func is_active() -> bool:
	return not _steps.is_empty()


## Predicts the walk the server will do for a move order to [param target].
## Steps already being shown stay; steps not yet started are replaced.
## With [param into_goal] false the walk stops next to the target tile, which
## is what the server does when closing in to attack or shove.
func order(target: Vector2i, into_goal := true) -> void:
	_has_target = true
	_target = target
	_into_goal = into_goal
	cancel_unstarted()
	var at: Vector2i = _entity.tile
	var start := _clock
	if is_active():
		var last: Step = _steps.back()
		at = last.to
		start = maxf(_clock, last.start + last.duration)
	_append_path(at, start)


## Drops predicted steps that have not started showing (the order changed).
func cancel_unstarted() -> void:
	while is_active() and not _steps.back().started:
		_steps.pop_back()


func clear() -> void:
	_steps.clear()
	_has_target = false


## The server put the entity on [param server_tile], not where this
## prediction had it. Blend the sprite there over [param blend_ticks] from
## wherever it is now, then carry on toward the target from that tile.
func rebase(server_tile: Vector2i, blend_ticks: float) -> void:
	var from_pos := position() if is_active() else _entity.position
	_steps.clear()
	var blend := Step.new()
	blend.from = server_tile
	blend.to = server_tile
	blend.from_pos = from_pos
	blend.to_pos = Iso.tile_to_local(server_tile)
	blend.start = _clock
	blend.duration = maxf(blend_ticks, 0.01)
	blend.started = true
	blend.confirmed = true  # Not a guess: the server said so.
	_steps.append(blend)
	if _has_target:
		_append_path(server_tile, _clock + blend.duration)


## Advances the clock. Returns true if a shown step has gone unconfirmed past
## its deadline, which the caller must treat as a misprediction.
func advance(delta: float) -> bool:
	_clock += delta / World.TICK_DT
	if not is_active():
		return false
	# Start steps whose time has come, re-planning if the world moved into one.
	for i in _steps.size():
		var step := _steps[i]
		if step.started:
			continue
		if step.start > _clock:
			break
		if _taken(step.to):
			_replan_from(i)
			break
		step.started = true
	var all_confirmed := true
	for step in _steps:
		if step.confirmed:
			continue
		all_confirmed = false
		if step.started and _clock > step.deadline:
			return true
	var last: Step = _steps.back()
	if all_confirmed and _clock >= last.start + last.duration:
		_steps.clear()
	return false


## The server's tile for the entity just changed to [param server_tile].
## Returns true if that is a step this prediction is showing or about to.
func reconcile(server_tile: Vector2i) -> bool:
	for i in _steps.size():
		if _steps[i].confirmed:
			continue
		for k in range(i, _steps.size()):
			if _steps[k].to == server_tile:
				for confirmed in range(i, k + 1):
					_steps[confirmed].confirmed = true
				return true
		return false
	# Everything is confirmed already; the same tile again is no surprise.
	return _steps.back().to == server_tile


## Tile the shown sprite is on or heading into.
func predicted_tile() -> Vector2i:
	return _current().to


func facing() -> Vector2i:
	var step := _current()
	return step.to - step.from


func position() -> Vector2:
	var step := _current()
	var t := clampf((_clock - step.start) / step.duration, 0.0, 1.0)
	return step.from_pos.lerp(step.to_pos, t)


## The latest step that has started; the first one if none has yet.
func _current() -> Step:
	var current: Step = _steps[0]
	for step in _steps:
		if step.start <= _clock:
			current = step
	return current


## Appends the predicted steps from [param at] toward the target, the first
## beginning at [param start].
func _append_path(at: Vector2i, start: float) -> void:
	if not _has_target:
		return
	var latency := Net.rtt_ticks()
	for next in World.find_path(at, _target, true, _entity):
		if next == _target and not _into_goal:
			break
		if _taken(next):
			break
		var step := Step.new()
		step.from = at
		step.to = next
		step.from_pos = Iso.tile_to_local(at)
		step.to_pos = Iso.tile_to_local(next)
		step.start = start
		step.duration = World.step_ticks(_entity, next - at)
		step.deadline = start + latency + RECONCILE_GRACE_TICKS
		_steps.append(step)
		start += step.duration
		at = next


## Drops steps from index [param i] on and plans again from the tile before.
func _replan_from(i: int) -> void:
	var at: Vector2i = _steps[i - 1].to if i > 0 else _entity.tile
	var start: float = _steps[i - 1].start + _steps[i - 1].duration if i > 0 else _clock
	_steps.resize(i)
	_append_path(at, maxf(start, _clock))


## Occupied in the replicated world by something the server would not let
## this entity walk into. Every other entity's current tile, where it is or
## is heading, counts; only a crate light enough to shove does not.
func _taken(tile: Vector2i) -> bool:
	var occupant := World.get_entity_at(tile)
	if occupant == null or occupant == _entity:
		return false
	return not (occupant.pushable and occupant.mass <= _entity.mass)
