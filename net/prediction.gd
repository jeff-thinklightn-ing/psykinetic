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
##     a couple of ticks and the path is re-planned from there. An error of
##     more than SNAP_TILES ends the walk and slides there instead, and only
##     TELEPORT_TILES or more is snapped (see GridEntity._mispredicted).
## Only walking is predicted. Being pushed is never predicted.
##
## A new move order keeps the steps already showing, and the order sent
## to the server lists every step shown or planned that it has not
## confirmed (order's result), so the server walks the way shown, re-pathing
## only when a step is refused: otherwise an order that arrives before the
## server has taken a shown step sets off from the tile before it, and a
## server re-pathing round monsters it sees a moment later goes another
## way than the client planned (hold-to-move steering, worst in 3D where
## the camera moves the ground under a still cursor). After a correction
## the owner sends the re-planned walk again (GridEntity._resend_walk).
##
## WASD walks are predicted step by step (step()): each one starts where
## the last ends, so the walk is one steady motion, and is sent to the
## server as it starts; the server takes them in order on its own timer.
## The key held is told each frame (hint, 655 amended), so the step shown
## bends toward the one to come before that one is shown.
##
## The prediction gives its target up when the server evidently has: a step
## into the target tile itself refused, or a shown step that no reply
## confirms at all. From then on the server's moves are drawn as for any
## other entity; predicting again would only bounce the sprite between the
## same guess and the same correction.

## How long past its expected confirmation (start + round trip) a shown step
## may stay unconfirmed before it counts as a misprediction.
const RECONCILE_GRACE_TICKS := 4.0
## A WASD step shown while the server is behind (decision 543) is drawn this
## much longer at most, of its own length, so a backlog drains a little each
## step instead of lasting the whole held walk.
const CATCH_UP_STRETCH := 0.5
## How long past its deadline a WASD step the server has not taken yet (it
## still has the walker on the step's own start) is waited for, in steps of
## its length, before it counts as a misprediction after all (decision 543).
const CATCH_UP_WAIT_STEPS := 2.0
## Ticks a step toward a target that came within reach is eased back over.
const REACH_SETTLE_TICKS := 1.5
## 655 amended: a walk ended on a bend toward the held key's next step, and
## that step never came (the key let go): the body slides from where it is
## to the cell's centre over this long.
const SETTLE_TICKS := 1.5
## How far along the step hinted at the body may be drawn on (position) past
## the end of the step before it, waiting the frame for that step to come.
const COAST_MAX := 0.5
## A held key's hint older than this (no frame has read the keys since) is
## not bent toward.
const HINT_FRESH_TICKS := 1.0
## 678: the own body drawn on its walk's straight line, not cell to cell:
## pulled onto it by at most this much (cells; the DDA keeps within half),
## and a change of line (a new way, a corner of the route) eased out at
## this rate a second rather than jumped.
const GLIDE_MAX := 0.5
const GLIDE_EASE := 12.0
## 678 amended (Jeff on v0.1.177: "i can move cursor behind me and character
## keeps going"): a new order whose target lies more than this off the way of
## the step the one under way bends into drops that step too; under it, the
## step is kept (the held-click jitter's fix).
const TURN_KEEP := deg_to_rad(45.0)


class Step:
	var from := Vector2i.ZERO
	var to := Vector2i.ZERO
	## A correction (see rebase): eased out, so the body slows to a stop
	## on the server's tile instead of halting dead.
	var ease := false
	## Where the sprite goes between, in grid units so the view can turn
	## under it; usually the two tiles' centres.
	var from_grid := Vector2.ZERO
	var to_grid := Vector2.ZERO
	## On the prediction clock, in ticks.
	var start := 0.0
	var duration := 1.0
	var deadline := 0.0
	var started := false
	var confirmed := false
	## 655: the corners rounded (GridEntity.bent_position): the tile the step
	## before came from when this one starts on its bend; the tile this one
	## bends toward at its end, settled as its tail begins.
	var bend_prev := GridEntity.UNKNOWN_TILE
	var bend_next := GridEntity.UNKNOWN_TILE
	var bend_decided := false
	## 655 amended: the slide from a bend's apex back to the cell's centre
	## after a walk that ended bent toward a step that never came.
	var settle := false
	## 678 amended: the order that planned it (MovePrediction._plan), so a
	## walk planned again as it goes draws on the newest plan's line, not a
	## line through an earlier plan's cells it has left.
	var plan := 0


var _entity: GridEntity
var _steps: Array[Step] = []
## Local time in ticks, advanced by frame time, so shown motion does not
## depend on when server packets happen to arrive.
var _clock := 0.0
## The order being carried out, for re-planning.
var _has_target := false
var _target := Vector2i.ZERO
var _into_goal := true
## Refusals of WASD steps heard from the server (see World.order_step).
var epoch := 0
## When the last shown walk ended, on the clock, kept after its steps are
## dropped: a WASD step held on from it starts there, not a frame late.
var _ended_at := -INF
## Where it ended (655 amended): a step held on from there starts from the
## cell's centre, on the line, not from the body's last drawn point.
var _ended_tile := GridEntity.UNKNOWN_TILE
## 655 amended: the direction the WASD keys hold now, as last told (hint),
## and when on the clock.
var _hint := Vector2i.ZERO
var _hint_clock := -INF
## 678: the held walk's line (hint_line), when told on the clock; the
## line the glide last drew on and the part of a change of it still easing out.
var _line_origin := Vector2.INF
var _line_along := Vector2.ZERO
var _line_clock := -INF
var _glide_line: Array = []
var _glide_carry := Vector2.ZERO
## 678 amended: the orders given, counted (Step.plan).
var _plan := 0
## The shown walk has ended bent toward the held key's step and been given
## the frame for that step to come, drawn on along the bend meanwhile
## (advance, position); the frame over, the settle starts.
var _coasting := false
## Closing in to strike: the one struck at, whose replicated tile the walk
## is planned to again as it moves, as the server re-paths each step.
var _following: WeakRef = null
## The walk was planned again (a step taken, a shorter way open) and is to
## be sent to the server (take_route_changed).
var _route_changed := false
## When the server will have done the last step it confirmed, on the clock,
## as the client shows walks (a round trip ahead of the server's own time):
## where a WASD step may start with the server keeping up (decision 543).
var _server_done := -INF
## WASD steps sent that the server has not been seen to take, in order: its
## queue as this client has it (decision 543). A correction shows them again
## from the server's tile, for the server walks them still.
var _sent: Array[Vector2i] = []
## When each of _sent's steps was sent, on the clock (543 amended, ui's
## side): a step unseen past the round trip and the grace is one the
## server has not taken yet.
var _sent_at: Array[float] = []
## The server's tile as last heard, where _sent's steps go on from.
var _server_at := Vector2i.ZERO


func _init(entity: GridEntity) -> void:
	_entity = entity


func is_active() -> bool:
	return not _steps.is_empty()


## Predicts the walk the server will do for a move order to [param target].
## Steps already being shown stay; steps not yet started are replaced.
## With [param into_goal] false the walk stops next to the target tile, which
## is what the server does when closing in to attack or shove.
## Returns the tiles of every step it shows that the server has not
## confirmed, in order, those under way and those planned: the server walks
## them while it can (Player._walk_via), so it goes the way shown rather
## than a way of its own round the same monsters, which it sees a moment
## later and elsewhere (most of the corrections on the castle were that).
func order(target: Vector2i, into_goal := true) -> Array[Vector2i]:
	_following = null
	_sent.clear()  # The server's queue goes with a move order (World.order_move).
	_sent_at.clear()
	_has_target = true
	_target = target
	_into_goal = into_goal
	# 678 amended: whatever the new plan changes on screen is eased out
	# (_glide_carry), never jumped: a bend toward a dropped step undone.
	var was := Iso.local_to_grid(position()) if is_active() else Vector2.INF
	_plan += 1
	_cancel_unbent(target)
	var at: Vector2i = _entity.tile
	var start := _clock
	var drawn := Vector2.INF
	_coasting = false
	if is_active() and _steps.back().settle:
		# 655 amended: sliding back from a bend: from where the body is, now.
		drawn = Iso.local_to_grid(position())
		_steps.pop_back()
	if is_active():
		var last: Step = _steps.back()
		at = last.to
		start = maxf(_clock, last.start + last.duration)
		if drawn == Vector2.INF and start == _clock and last.bend_next != GridEntity.UNKNOWN_TILE:
			drawn = Iso.local_to_grid(position())  # 655 amended: ended on a bend: from its point, now.
	elif drawn == Vector2.INF:
		drawn = _drawn()
	_append_path(at, start, drawn)
	if was != Vector2.INF and is_active():
		_glide_carry += (was - Iso.local_to_grid(position())).limit_length(GLIDE_MAX)
	return unconfirmed()


## The tiles of the steps shown or planned that the server has not
## confirmed, in order.
func unconfirmed() -> Array[Vector2i]:
	var via: Array[Vector2i] = []
	for step in _steps:
		if not step.confirmed:
			via.append(step.to)
	return via


## The tiles of the steps under way on screen that the server has not
## confirmed, in order (sent with a strike order, which the server plans
## itself from where they end).
func in_flight() -> Array[Vector2i]:
	var via: Array[Vector2i] = []
	for step in _steps:
		if step.started and not step.confirmed:
			via.append(step.to)
	return via


## Closing in on [param target] (after order(its tile, false)): as it moves
## the approach is planned again to where it is (advance).
func follow(target: GridEntity) -> void:
	_following = weakref(target) if target != null else null


## A walk to a tile (not a closing in to strike, which the server plans
## itself), with a target still to reach.
func is_walking_to_target() -> bool:
	return _has_target and _into_goal


## WASD: one step in [param direction] from where the shown walk ends,
## starting as the step before it ends. Any move order is dropped (the
## server drops it too). False, and nothing shown, if the replicated world
## refuses the step.
func step(direction: Vector2i) -> bool:
	_has_target = false
	cancel_unstarted()
	_coasting = false
	var at: Vector2i = _entity.tile
	var last: Step = null
	var drawn_now := Vector2.INF
	var settling := false
	if is_active():
		drawn_now = Iso.local_to_grid(position())
		last = _steps.back()
		if last.settle:
			# 655 amended: sliding back from a bend (the settle, confirmed
			# and done with): the step goes from where the body is, now.
			settling = true
			last = _steps[_steps.size() - 2]
		at = last.to
	if _blocked(at, direction):
		return false
	if settling:
		_steps.pop_back()
	# Straight on from the last step if it has only just ended, so a held
	# key makes one steady walk; after a pause, from now.
	var start := _ended_at
	var from_grid := Vector2.INF
	var bend_prev := GridEntity.UNKNOWN_TILE
	if last != null:
		start = last.start + last.duration
		from_grid = Vector2(at)
		if settling or (last.bend_decided and last.bend_next != GridEntity.UNKNOWN_TILE and last.bend_next != at + direction):
			# 655 amended: sliding back, or bent toward another step (the
			# key changed in the last half step): straight from where the
			# body is drawn, now, to the next centre, as a mirror's catch-up
			# is; the step after bends again.
			from_grid = drawn_now
			start = _clock
		elif last.bend_decided and last.bend_next == at + direction:
			bend_prev = last.from  # 655: on from the bend the last ends on.
	elif start >= _clock - 1.0 and at == _ended_tile:
		# 655 amended: a walk ended here within the tick: on from the cell's
		# centre, on the line (the body drawn a frame short of it at most),
		# so the step bends as any other.
		from_grid = Vector2(at)
	else:
		from_grid = _drawn()
	if start < _clock - 1.0:
		start = _clock
	var next := Step.new()
	next.from = at
	next.to = at + direction
	next.from_grid = from_grid
	next.bend_prev = bend_prev
	next.to_grid = Vector2(next.to)
	next.start = start
	next.duration = World.step_ticks(_entity, direction, at)
	# The server walks the queue of steps sent on its own clock: if it fell
	# behind (a step it took late, a hauler in the way) a held walk would stay
	# that far ahead of it, past every step's deadline, corrected over and over
	# (decision 543; the wilds town's chests). Where the server should be by
	# now: done with its last confirmed step and the shown ones after it.
	# More than one step behind that, this step waits on it: confirmed later
	# (the deadline from when the server will take it) and drawn a little
	# longer (CATCH_UP_STRETCH), so the gap closes. Keeping up, this is a step
	# or more in the past and nothing changes.
	var server_takes := _server_done
	for shown in _steps:
		if not shown.confirmed:
			server_takes += shown.duration
	var behind := server_takes - start - next.duration
	next.duration += clampf(behind, 0.0, next.duration * CATCH_UP_STRETCH)
	next.deadline = maxf(start, server_takes) + Net.rtt_ticks() + RECONCILE_GRACE_TICKS
	# Sent as it starts: never re-planned (see advance).
	next.started = true
	_steps.append(next)
	if _sent.is_empty():
		_server_at = _entity.tile
	_sent.append(direction)
	_sent_at.append(_clock)
	return true


## WASD: the shown walk has (nearly) run out, so the next held step should
## go now. True with nothing showing. False while the server holds as many
## steps as it will queue (543 amended, ui's side): World.MAX_QUEUED_STEPS
## sent and not seen taken, the oldest unseen past the round trip and the
## grace, so the server has it and has not walked it; a step sent now would
## be dropped unheard (World.order_step) and the walk shown would part from
## the server's, a correction of several tiles later. The held walk pauses
## at its shown end instead and goes on as the server takes them. A server
## keeping up never has three unseen that long, whatever the round trip:
## each is seen a round trip after it is sent.
func ready_for_step() -> bool:
	if _sent.size() >= World.MAX_QUEUED_STEPS and _clock - _sent_at[0] > Net.rtt_ticks() + RECONCILE_GRACE_TICKS:
		return false
	if not is_active():
		return true
	var last: Step = _steps.back()
	return last.settle or _clock >= last.start + last.duration


## 543 amended, ui's side: whether the held walk is paused on the server
## (ready_for_step's first rule), for the owner's say.
func waiting_on_server() -> bool:
	return _sent.size() >= World.MAX_QUEUED_STEPS and _clock - _sent_at[0] > Net.rtt_ticks() + RECONCILE_GRACE_TICKS


## Drops predicted steps that have not started showing (the order changed),
## but not one the server has already taken (confirmed while the server was
## ahead): dropped and planned again, it would wait for a confirmation that
## had come and gone, and be pulled back at its deadline onto the very tile
## the server has ("predicted X, server has X: no confirmation").
## A new order's cancel: the unstarted steps go, but not the one the step
## on screen is already bending into (its bend settled as its tail began,
## 655): dropping it left the body at the bend's end, half a step on toward
## a cell no longer planned, and the new route set off from the centre, a
## jump every re-order in a tail (the held-click jitter). The route goes on
## from that step's end; the server walks it as one of the via tiles.
## Unless [param target] turns the walk (TURN_KEEP; 678 amended): then that
## step goes too, the one under way is bent again toward the new plan
## (order eases the change), and the turn comes a step sooner.
func _cancel_unbent(target := GridEntity.UNKNOWN_TILE) -> void:
	while is_active() and not _steps.back().started and not _steps.back().confirmed:
		var i := _steps.size() - 1
		if i > 0 and _steps[i - 1].bend_decided and _steps[i - 1].bend_next == _steps[i].to:
			if target == GridEntity.UNKNOWN_TILE or _keeps_way(_steps[i], target):
				return
			_steps[i - 1].bend_decided = false
			_steps[i - 1].bend_next = GridEntity.UNKNOWN_TILE
		_steps.pop_back()


## 678 amended: whether [param target] lies within TURN_KEEP of [param step]'s way.
static func _keeps_way(step: Step, target: Vector2i) -> bool:
	var to := Vector2(target - step.from)
	return to.length() > 0.01 and Vector2(step.to - step.from).normalized().dot(to.normalized()) >= cos(TURN_KEEP) - 0.0001


## 678 amended: the steps planned and not begun.
func steps_planned() -> int:
	var count := 0
	for step in _steps:
		if not step.started:
			count += 1
	return count


func cancel_unstarted() -> void:
	while is_active() and not _steps.back().started and not _steps.back().confirmed:
		_steps.pop_back()


func clear() -> void:
	_steps.clear()
	_has_target = false
	_coasting = false


func target() -> Vector2i:
	return _target


func has_target() -> bool:
	return _has_target


## Stop pursuing the target; steps already shown finish or blend away.
func give_up() -> void:
	_has_target = false


## The server put the entity on [param server_tile], not where this
## prediction had it. Blend the sprite there over [param blend_ticks] from
## wherever it is now, then carry on toward the target from that tile.
func rebase(server_tile: Vector2i, blend_ticks: float) -> void:
	var from_grid := Iso.local_to_grid(position() if is_active() else _entity.position)
	_taken(server_tile)
	_steps.clear()
	_coasting = false
	var blend := Step.new()
	blend.from = server_tile
	blend.to = server_tile
	blend.from_grid = from_grid
	blend.to_grid = Vector2(server_tile)
	blend.start = _clock
	blend.duration = maxf(blend_ticks, 0.01)
	blend.started = true
	blend.confirmed = true  # Not a guess: the server said so.
	blend.ease = true
	_steps.append(blend)
	if _has_target:
		_append_path(server_tile, _clock + blend.duration)
		return
	# WASD steps the server still has queued: shown again, from its tile on,
	# as it will walk them (decision 543), not dropped to come back as more
	# surprises one by one.
	var at := server_tile
	var start := _clock + blend.duration
	for direction in _sent:
		var again := Step.new()
		again.from = at
		again.to = at + direction
		again.from_grid = Vector2(at)
		again.to_grid = Vector2(again.to)
		again.start = start
		again.duration = World.step_ticks(_entity, direction, at)
		again.deadline = start + Net.rtt_ticks() + RECONCILE_GRACE_TICKS
		again.started = true
		_steps.append(again)
		at = again.to
		start += again.duration


## Advances the clock. Returns true if a shown step has gone unconfirmed past
## its deadline, which the caller must treat as a misprediction.
func advance(delta: float) -> bool:
	_clock += delta / World.TICK_DT
	_glide_carry *= exp(-GLIDE_EASE * delta)  # 678: a jump in the pull eases out.
	if not is_active():
		return false
	if _following != null and _has_target and not _into_goal:
		var followed := _following.get_ref() as GridEntity
		if followed == null or not followed.spawned:
			_following = null
		elif followed.tile != _target:
			if World.can_melee(_entity.tile, followed.tile) and not in_flight().is_empty():
				# It came within reach of where the server has the striker: the
				# server strikes from there and takes no step, so neither is a
				# step shown toward it.
				_target = followed.tile
				rebase(_entity.tile, REACH_SETTLE_TICKS)
			else:
				# It moved: the way to it again, as the server re-paths each step.
				order(followed.tile, false)
				_following = weakref(followed)
	# Start steps whose time has come, re-planning if the world moved into one.
	for i in _steps.size():
		var step := _steps[i]
		if step.started:
			continue
		if step.start > _clock:
			break
		# (Not one the server has taken already: its world is the one that counts.)
		if not step.confirmed and (_blocked(step.from, step.to - step.from) or _shorter_way_from(i)):
			# Taken, or a shorter way opened (one who stood in a passage moved
			# on): planned again from here, as the server once did each step;
			# the server walks the plan, so it is sent again (take_route_changed).
			_replan_from(i)
			if is_walking_to_target():
				_route_changed = true
			break
		step.started = true
	var all_confirmed := true
	for step in _steps:
		if step.confirmed:
			continue
		all_confirmed = false
		if step.started and _clock > step.deadline:
			if _server_behind(step):
				break  # The ones after it wait on it too.
			return true
	var last: Step = _steps.back()
	if _clock >= last.start + last.duration and last.bend_next != GridEntity.UNKNOWN_TILE and not last.settle:
		# 655 amended: ended bent toward the held key's step, which has not
		# come. The key held a frame ago, its step comes this frame (Main
		# reads the keys after the bodies are drawn): the body is drawn on
		# along the bend meanwhile (position) and the step joins it. No
		# step by the next frame, or the key let go: the body slides from
		# where it is to the centre; it never snaps there.
		if not _coasting and _hint != Vector2i.ZERO and _clock - _hint_clock <= HINT_FRESH_TICKS:
			_coasting = true
		else:
			var settle := Step.new()
			settle.from = last.to
			settle.to = last.to
			settle.from_grid = Iso.local_to_grid(position())
			settle.to_grid = Vector2(last.to)
			settle.start = _clock
			settle.duration = SETTLE_TICKS
			settle.ease = true
			settle.started = true
			settle.confirmed = true
			settle.settle = true
			_steps.append(settle)
			_coasting = false
			last = settle
	if all_confirmed and _clock >= last.start + last.duration and not _coasting:
		_ended_at = last.start + last.duration
		_ended_tile = last.to
		_steps.clear()
	return false


## A WASD step past its deadline that the server has simply not taken yet:
## the oldest unconfirmed, the server still has the walker on its start
## (behind on the queue of steps sent, not somewhere else), and not
## CATCH_UP_WAIT_STEPS of its length overdue (decision 543). Correcting it
## would drop steps the server is still to walk, each then a surprise.
func _server_behind(step: Step) -> bool:
	if _has_target or _entity.tile != step.from:
		return false
	for shown in _steps:
		if not shown.confirmed:
			return shown == step and _clock - step.deadline < step.duration * CATCH_UP_WAIT_STEPS
	return false


## The server refused a WASD step and emptied its queue (Player's
## _take_queued_step): none of the steps sent is coming.
func server_dropped_queue() -> void:
	_sent.clear()
	_sent_at.clear()


## 655 amended: WASD, each frame (Main._drive_wasd): the direction the keys
## hold now, ZERO for none, which the step after the one shown will take
## as that one ends. A step's bend at its end is settled toward it when no
## planned step follows (_bent); nothing is shown or sent for it.
func hint(direction: Vector2i) -> void:
	_hint = direction
	_hint_clock = _clock


## 678: the held walk's line, each frame it is held (INF: none).
func hint_line(origin: Vector2, along: Vector2) -> void:
	_line_origin = origin
	_line_along = along.normalized()
	_line_clock = _clock if origin != Vector2.INF else -INF


## 678: the straight line [param step] is on, [origin, unit way] in grid
## units, or [] for none: the held walk's (fresh, no order), else the run
## of the planned route round it that keeps to two neighbouring ways of
## the eight, both taken (a line string-pulled by World.walk_path; a run
## of one way is a line already).
func _line_of(step: Step, loose := false) -> Array:
	if not _has_target:
		if _line_origin != Vector2.INF and _clock - _line_clock <= HINT_FRESH_TICKS:
			return [_line_origin, _line_along]
		return []
	var i := _steps.find(step)
	if i < 0:
		return []
	var first := i
	var last := i
	var main := step.to - step.from
	var other := Vector2i.ZERO
	for way: int in [-1, 1]:
		var j: int = i + way
		while j >= 0 and j < _steps.size():
			var s: Step = _steps[j]
			var joined: bool = s.to == _steps[j + 1].from if way == -1 else s.from == _steps[j - 1].to
			if not joined or s.settle or not (_bends(s) or loose and _one_cell(s)):
				break
			if way == -1 and s.plan != _steps[j + 1].plan:
				break  # 678 amended: an earlier plan's line is not this one's.
			var d := s.to - s.from
			if d != main:
				if other == Vector2i.ZERO and Vector2(d).normalized().dot(Vector2(main).normalized()) > 0.7:
					other = d
				elif d != other:
					break
			if way == -1:
				first = j
			else:
				last = j
			j += way
	if other == Vector2i.ZERO:
		return []
	var origin := Vector2(_steps[first].from)
	return [origin, (Vector2(_steps[last].to) - origin).normalized()]


## 678: [param p], [param step]'s drawn point (grid units), pulled onto
## the line it is on (_line_of), at most GLIDE_MAX; a change of line (a new
## way, a route's next run, none) eased out over a few frames rather than
## jumped. A step drawn from where the body was (a correction, a walk from
## rest, a settle) is not pulled: it set off from the pulled point already.
func _glide(p: Vector2, step: Step) -> Vector2:
	if step.settle or not _bends(step):
		_glide_line = []
		_glide_carry = Vector2.ZERO
		return p
	var line := _line_of(step)
	var pull := _pull(p, line)
	if line != _glide_line:
		_glide_carry += _pull(p, _glide_line) - pull
		_glide_line = line
	return p + pull + _glide_carry


## 678: how far [param p] is moved onto [param line] ([origin, way]; []
## none), GLIDE_MAX at most.
static func _pull(p: Vector2, line: Array) -> Vector2:
	if line.is_empty():
		return Vector2.ZERO
	var origin: Vector2 = line[0]
	var along: Vector2 = line[1]
	return (origin + along * along.dot(p - origin) - p).limit_length(GLIDE_MAX)


## The server is on [param server_tile]: the sent steps that took it there,
## followed from where it was, are taken; the rest it has still to walk. On
## a tile they do not lead to (a push, a step refused), none are known.
func _taken(server_tile: Vector2i) -> void:
	if server_tile == _server_at:
		return
	var at := _server_at
	for i in _sent.size():
		at += _sent[i]
		if at == server_tile:
			_sent = _sent.slice(i + 1)
			_sent_at = _sent_at.slice(i + 1)
			_server_at = server_tile
			return
	_sent.clear()
	_sent_at.clear()
	_server_at = server_tile


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
				# The server started it a one-way trip ago; shown a round trip
				# ahead, it is done a step's length after that (543).
				_server_done = maxf(_server_done, _clock - Net.rtt_ticks() + _steps[k].duration)
				_taken(server_tile)
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


## Where the sprite is shown now, projected at the current azimuth.
func position() -> Vector2:
	var step := _current()
	var t := (_clock - step.start) / step.duration
	if _coasts(step, t):
		return Iso.grid_to_local(_glide(GridEntity.bent_position(step.from, step.to, step.bend_next, GridEntity.UNKNOWN_TILE,
				_coast_t(step, t), GridEntity.bend_reach(step.to), 0.0), step))
	t = clampf(t, 0.0, 1.0)
	if step.ease:
		t = 1.0 - (1.0 - t) * (1.0 - t)
	return Iso.grid_to_local(_glide(_bent(step, t), step))


## 655: the way the body points as drawn, a unit vector in grid units:
## along its bend, else along the step.
func shown_direction() -> Vector2:
	var step := _current()
	var t := (_clock - step.start) / step.duration
	if _coasts(step, t):
		return GridEntity.bent_tangent(step.from, step.to, step.bend_next, GridEntity.UNKNOWN_TILE,
				_coast_t(step, t), GridEntity.bend_reach(step.to), 0.0)
	t = clampf(t, 0.0, 1.0)
	if not _bends(step):
		# 678 amended (Jeff: "the body doesn't face the direction of
		# travel"): a step drawn from where the body was (each new order
		# held far, a key's turn) is on the line too; facing its own way of
		# the eight turned the body off it at every re-order.
		var on := _line_of(step, true) if _one_cell(step) and not step.ease and not step.settle else []
		return on[1] if not on.is_empty() else Vector2(step.to - step.from)
	var line := _line_of(step)
	if not line.is_empty():
		return line[1]  # 678: facing along the line walked, not each step's way.
	var reach_in := GridEntity.bend_reach(step.from) if step.bend_prev != GridEntity.UNKNOWN_TILE else 0.0
	return GridEntity.bent_tangent(step.bend_prev, step.from, step.to, step.bend_next, t, reach_in, GridEntity.bend_reach(step.to))


## 655 amended: [param step], the last shown, has ended ([param t] past 1)
## bent toward the held key's step, which has not come yet: the body is
## drawn on along that bend as that step would draw it (_coast_t), so the
## step joins it without a jump when it comes within the frame.
func _coasts(step: Step, t: float) -> bool:
	return t > 1.0 and step == _steps.back() and not step.settle and step.bend_next != GridEntity.UNKNOWN_TILE


## Where on the step hinted at (0..COAST_MAX of its own time) the body is,
## [param t] of [param step]'s time past its end.
func _coast_t(step: Step, t: float) -> float:
	var on := step.bend_next - step.to
	return minf((t - 1.0) * step.duration / World.step_ticks(_entity, on, step.to), COAST_MAX)


## 655: [param step]'s drawn point at [param t], its corners rounded as the
## mirrors' are (GridEntity._bent_step): the bend at its end settled as its
## tail begins, from the step after when that one is planned by then and
## joins straight on, and handed to that step as the bend it starts on.
func _bent(step: Step, t: float) -> Vector2:
	if not _bends(step):
		return step.from_grid.lerp(step.to_grid, t)
	var reach_out := GridEntity.bend_reach(step.to)
	if t > 1.0 - reach_out and not step.bend_decided:
		step.bend_decided = true
		var i := _steps.find(step)
		if i >= 0 and i + 1 < _steps.size():
			var after: Step = _steps[i + 1]
			if _bends(after) and after.from == step.to and is_equal_approx(after.start, step.start + step.duration):
				step.bend_next = after.to
				after.bend_prev = step.from
		elif i == _steps.size() - 1 and not _has_target and _hint != Vector2i.ZERO \
				and _clock - _hint_clock <= HINT_FRESH_TICKS and not _blocked(step.to, _hint):
			# 655 amended: no step planned after it, but a key held: the
			# step to come goes that way as this one ends (Main._drive_wasd),
			# so the bend is toward it; step() joins it, or the settle
			# (advance) brings the body back when the key is let go first.
			step.bend_next = step.to + _hint
	var reach_in := GridEntity.bend_reach(step.from) if step.bend_prev != GridEntity.UNKNOWN_TILE else 0.0
	return GridEntity.bent_position(step.bend_prev, step.from, step.to, step.bend_next, t, reach_in, reach_out)


## 678 amended: [param step] is one cell, a king's move.
static func _one_cell(step: Step) -> bool:
	var delta := step.to - step.from
	return maxi(absi(delta.x), absi(delta.y)) == 1


## 655: whether [param step] may be drawn on a bend: a step of one cell
## between two centres, not a correction's ease or a walk from rest.
static func _bends(step: Step) -> bool:
	var delta := step.to - step.from
	return not step.ease and maxi(absi(delta.x), absi(delta.y)) == 1 \
			and step.from_grid == Vector2(step.from) and step.to_grid == Vector2(step.to)


## The latest step that has started; the first one if none has yet.
func _current() -> Step:
	var current: Step = _steps[0]
	for step in _steps:
		if step.start <= _clock:
			current = step
	return current


## Where the entity is drawn now (grid units): a walk that starts from rest
## starts there, not from its tile, which a slide still under way (a push,
## a correction's, decision 339) has not reached; from the tile it would
## jump back to it first.
func _drawn() -> Vector2:
	var drawn := Iso.local_to_grid(_entity.position)
	# At rest on a centre (within the projection's rounding): the centre
	# itself, so the step from it is between centres and bends (655).
	return drawn.round() if drawn.distance_squared_to(drawn.round()) < 0.000001 else drawn


## Appends the predicted steps from [param at] toward the target, the first
## beginning at [param start], and from [param drawn] if given (a walk from
## rest: _drawn).
func _append_path(at: Vector2i, start: float, drawn := Vector2.INF) -> void:
	if not _has_target:
		return
	var latency := Net.rtt_ticks()
	for next in World.walk_path(at, _target, _entity):  # 678: the string pulled.
		if next == _target and not _into_goal:
			break
		if _blocked(at, next - at):
			break
		var step := Step.new()
		step.from = at
		step.to = next
		step.from_grid = Vector2(at) if drawn == Vector2.INF else drawn
		drawn = Vector2.INF
		step.to_grid = Vector2(next)
		step.start = start
		step.duration = World.step_ticks(_entity, next - at, at)
		step.deadline = start + latency + RECONCILE_GRACE_TICKS
		step.plan = _plan
		_steps.append(step)
		start += step.duration
		at = next


## A walk to a tile whose planned steps from index [param i] on are at
## least World.DETOUR_STEPS more than a way found now from the same tile.
func _shorter_way_from(i: int) -> bool:
	if not is_walking_to_target() or _steps[_steps.size() - 1].to != _target:
		return false
	var way := World.walk_path(_steps[i].from, _target, _entity)
	return not way.is_empty() and way.size() + World.DETOUR_STEPS <= _steps.size() - i


## Whether the walk was planned again since the last take: the owner sends
## it to the server then (GridEntity._resend_walk). Clears it.
func take_route_changed() -> bool:
	var changed := _route_changed
	_route_changed = false
	return changed


## Drops steps from index [param i] on and plans again from the tile before.
func _replan_from(i: int) -> void:
	var at: Vector2i = _steps[i - 1].to if i > 0 else _entity.tile
	var start: float = _steps[i - 1].start + _steps[i - 1].duration if i > 0 else _clock
	_steps.resize(i)
	_append_path(at, maxf(start, _clock))


## Whether a step into [param occupant]'s cell swaps the walker with it, as
## World._swap_with_own does: the walker's own companion (keeper_peer, which
## replicates), not downed or lying (decision 679). Her dodge and her fight
## are the server's alone; a swap it refuses then is corrected as any
## refused step.
func _swaps_with(occupant: GridEntity) -> bool:
	return _entity is Player and occupant is Companion and occupant.keeper_peer == _entity.owner_peer 			and _entity.owner_peer != 0 and not World.is_downed(occupant) and not World.is_down(occupant)


## Would the server refuse this step? The same rule as World._shift, read
## off the replicated world: terrain in the way, or an occupant that cannot
## be walked into. Every other entity's current tile, where it is or is
## heading, counts; a pushable one does not if it is within the mover's mass
## budget and has somewhere to go, chain and all. A crate against a wall is
## as solid as the wall. A closed door is walked through (the server opens
## it on the way) unless a crate would have to go through it first.
func _blocked(from: Vector2i, direction: Vector2i, budget := _entity.mass) -> bool:
	if World._terrain_blocks_step(from, direction, _entity.is_creature()):
		return true
	var to := from + direction
	var occupant := World.get_entity_at(to)
	if occupant == null or occupant == _entity:
		return false
	if budget == _entity.mass and _swaps_with(occupant):
		return false  # Her own player's step swaps them (World._swap_with_own).
	if not occupant.pushable or occupant.mass > budget:
		return true
	return _blocked(to, direction, budget - occupant.mass)
