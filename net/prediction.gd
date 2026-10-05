class_name MovePrediction
extends RefCounted
## Client-side prediction of the local player's own walking. Presentation
## only: it decides where the sprite is drawn, never where the entity is.
##
## When the client orders a move it works out the path the server will most
## likely take and starts showing it at once. Each replicated tile that then
## arrives from the server is checked against the steps already shown:
##   - it is the next shown step: confirmed, nothing visible happens;
##   - it is anything else, or no confirmation arrives in time (the server
##     refused the step): a misprediction. The caller snaps the sprite to the
##     server's tile and the predicted path is dropped.
## Only walking is predicted. Being pushed is never predicted.

## How long past its expected confirmation (start + round trip) a shown step
## may stay unconfirmed before it counts as a misprediction.
const RECONCILE_GRACE_TICKS := 4.0


class Step:
	var from := Vector2i.ZERO
	var to := Vector2i.ZERO
	## On the prediction clock, in ticks.
	var start := 0.0
	var duration := 1.0
	var deadline := 0.0
	var confirmed := false


var _steps: Array[Step] = []
## Local time in ticks, advanced by frame time, so shown motion does not
## depend on when server packets happen to arrive.
var _clock := 0.0


func is_active() -> bool:
	return not _steps.is_empty()


## Predicts the walk the server will do for a move order to [param target].
## Steps already being shown stay; steps not yet started are replaced.
func order(entity: GridEntity, target: Vector2i) -> void:
	cancel_unstarted()
	var at: Vector2i = entity.tile
	var start := _clock
	if is_active():
		var last: Step = _steps.back()
		at = last.to
		start = maxf(_clock, last.start + last.duration)
	var latency := Net.rtt_ticks()
	for next in World.find_path(at, target, true):
		# The goal may be occupied. The server only steps into it if the
		# occupant can be walked into and shoved along.
		var occupant := World.get_entity_at(next)
		if occupant != null and occupant != entity \
				and not (occupant.pushable and occupant.mass <= entity.mass):
			break
		var step := Step.new()
		step.from = at
		step.to = next
		step.start = start
		step.duration = World.step_ticks(entity, next - at)
		step.deadline = start + latency + RECONCILE_GRACE_TICKS
		_steps.append(step)
		start += step.duration
		at = next


## Drops predicted steps that have not started showing (the order changed).
func cancel_unstarted() -> void:
	while is_active() and _steps.back().start > _clock:
		_steps.pop_back()


func clear() -> void:
	_steps.clear()


## Advances the clock. Returns true if a shown step has gone unconfirmed past
## its deadline, which the caller must treat as a misprediction.
func advance(delta: float) -> bool:
	_clock += delta / World.TICK_DT
	if not is_active():
		return false
	var all_confirmed := true
	for step in _steps:
		if step.confirmed:
			continue
		all_confirmed = false
		if step.start <= _clock and _clock > step.deadline:
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
	return false


## Tile the shown sprite is on or heading into.
func predicted_tile() -> Vector2i:
	return _current().to


func facing() -> Vector2i:
	var step := _current()
	return step.to - step.from


func position() -> Vector2:
	var step := _current()
	var t := clampf((_clock - step.start) / step.duration, 0.0, 1.0)
	return Iso.tile_to_local(step.from).lerp(Iso.tile_to_local(step.to), t)


## The latest step that has started; the first one if none has yet.
func _current() -> Step:
	var current: Step = _steps[0]
	for step in _steps:
		if step.start <= _clock:
			current = step
	return current
