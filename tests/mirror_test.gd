extends Node
## How a client draws an entity it does not predict: replicated tile changes
## fed to a mirror by hand, its drawn position sampled five times a tick.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const SAMPLES_PER_TICK := 10

var _failures := 0
var _tick := 100


func _ready() -> void:
	World.set_process(false)
	Net.mode = Net.Mode.CLIENT  # Never started: this process is only a mirror.
	World.mirror_reset()

	_test_a_walk_is_drawn_without_jumps_or_pauses()
	_test_a_fast_walker_slides_too()
	_test_a_rush_is_drawn_as_a_slide()
	_test_turning_a_corner()
	_test_a_step_starts_after_the_display_delay()
	_test_the_display_clock_rides_out_late_ticks()
	_test_a_push_is_drawn_as_the_server_timed_it()
	_test_a_push_you_made_is_drawn_at_once()
	_test_a_guessed_shove()
	_test_prediction_does_not_walk_into_a_pinned_crate()
	_test_prediction_gives_up_when_the_server_has()
	_test_the_camera_eases_over_a_jump_not_a_slide()
	_test_a_large_correction_slides_not_snaps()
	_test_a_slow_step_overtaken_is_not_cut_short()
	_test_the_display_clock_waits_out_a_stall()
	_test_the_smooth_meter_names_who_went_back()
	_test_a_standing_body_starts_without_leaps()

	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_a_walk_is_drawn_without_jumps_or_pauses() -> void:
	print("\n== an imp walking six tiles east is drawn in one even slide ==")
	var imp := _mirror("Imp", Vector2i(2, 5), 4)
	var moves := _walk(imp, [Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0)])
	var per_sample := _tile_pixels(Vector2i(1, 0)) / (4.0 * SAMPLES_PER_TICK)
	var walking := _trim(moves)
	_check(walking.size() == 6 * 4 * SAMPLES_PER_TICK, "it is on the move for 6 steps of 4 ticks (%d samples)" % walking.size())
	_check(walking.max() <= per_sample * 1.05, "never jumps: at most %.2f px a sample (largest %.2f)" % [per_sample, walking.max()])
	_check(walking.min() >= per_sample * 0.95, "never stops between steps (smallest %.2f)" % walking.min())
	_check(imp.position.is_equal_approx(Iso.tile_to_local(Vector2i(8, 5))), "and ends on its tile")


func _test_a_fast_walker_slides_too() -> void:
	print("\n== so is a fast one, two ticks a step ==")
	# Two ticks a step, drawn 1.5 ticks behind: the next step arrives just
	# before this one's slide ends.
	var runner := _mirror("Runner", Vector2i(2, 7), 2)
	var moves := _walk(runner, [Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0)])
	var per_sample := _tile_pixels(Vector2i(1, 0)) / (2.0 * SAMPLES_PER_TICK)
	var walking := _trim(moves)
	_check(walking.max() <= per_sample * 1.05 and walking.min() >= per_sample * 0.95,
			"an even slide, not tile-to-tile hops (%.2f to %.2f px a sample, want %.2f)" % [walking.min(), walking.max(), per_sample])
	_check(runner.position.is_equal_approx(Iso.tile_to_local(Vector2i(6, 7))), "ending on its tile")


## A rush or an axe charge (World.rush, _lunge_cell): the server sets the
## tile a cell a tick, far faster than the body's own step (a draugr's
## move_ticks is 4.5). A joined client sees only the tile changes, and
## paces the slides by their arrival (decision 646): before it, each cell
## waited for the step-long slide before it, and the run was drawn at
## half the body's step at best, a draugr's eight cells arriving 12 ticks
## after the server's.
func _test_a_rush_is_drawn_as_a_slide() -> void:
	print("
== a rush, a cell a tick, is drawn as a slide that keeps up ==")
	var draugr := _mirror("Draugr", Vector2i(2, 9), 4)
	var moves: Array[float] = []
	var cells := 8
	for i in cells:
		_run_tick(draugr, moves, Vector2i(1, 0))
	var arrived_tick := _tick
	var settled := -1
	for i in 40:
		_run_tick(draugr, moves)
		if settled < 0 and draugr.position.is_equal_approx(Iso.tile_to_local(Vector2i(2 + cells, 9))):
			settled = _tick
	var sliding := _trim(moves)
	var per_sample := _tile_pixels(Vector2i(1, 0)) / float(SAMPLES_PER_TICK)
	print("  rush of %d cells: server done at tick %d, drawn there at tick %d (%.1f ticks behind, display delay %.1f); samples %d, largest %.2f px (a cell a tick is %.2f a sample)"
			% [cells, arrived_tick, settled, settled - arrived_tick, World.display_delay_ticks, sliding.size(), sliding.max(), per_sample])
	_check(sliding.max() <= per_sample * 1.05, "never jumps: at most a cell a tick's worth a sample (largest %.2f, want <= %.2f)" % [sliding.max(), per_sample])
	_check(sliding.min() > 0.0, "never stops between cells (smallest %.2f)" % sliding.min())
	_check(settled >= 0 and settled - arrived_tick <= ceili(World.display_delay_ticks) + 2,
			"and keeps up: there within the display delay of the server (%.1f ticks behind)" % (settled - arrived_tick))
	_check(sliding.size() >= cells * SAMPLES_PER_TICK * 0.9, "drawn a cell a tick, as the server stepped it (%d samples for %d cells)" % [sliding.size(), cells])
	# A walker whose next step comes mid-slide, slower than a cell a tick: paced the same, never a jump.
	var walker := _mirror("Hurried", Vector2i(2, 11), 6)
	var hurried: Array[float] = []
	_run_tick(walker, hurried, Vector2i(1, 0))
	for i in 2:
		_run_tick(walker, hurried)
	_run_tick(walker, hurried, Vector2i(1, 0))  # 3 ticks on, mid-slide.
	for i in 2:
		_run_tick(walker, hurried)
	_run_tick(walker, hurried, Vector2i(1, 0))
	for i in 12:
		_run_tick(walker, hurried)
	var three := _tile_pixels(Vector2i(1, 0)) / (3.0 * SAMPLES_PER_TICK)
	# The step on screen has the display delay's share of its cell still to draw by the next's tick: at most twice the pace, as _catch_up allows.
	_check(hurried.max() <= three * 2.0 * 1.05, "a step hurried by the next, a cell in three ticks: never a jump, at most twice that pace (largest %.2f px a sample, want <= %.2f)" % [hurried.max(), three * 2.0])
	_check(walker.position.is_equal_approx(Iso.tile_to_local(Vector2i(5, 11))), "and it ends on its tile (%s)" % Iso.local_to_grid(walker.position))


func _test_turning_a_corner() -> void:
	print("\n== a diagonal step between two straight ones joins up ==")
	var imp := _mirror("Turner", Vector2i(2, 9), 4)
	var moves := _walk(imp, [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)])
	var walking := _trim(moves)
	# On screen the straight steps are the faster ones.
	var fastest := _tile_pixels(Vector2i(1, 0)) / (4.0 * SAMPLES_PER_TICK)
	_check(walking.size() == (4 + 6 + 4) * SAMPLES_PER_TICK, "moving for 4 + 6 + 4 ticks (%d samples)" % walking.size())
	_check(walking.min() > 0.0 and walking.max() <= fastest * 1.05, "with no pause and no jump at either join (%.2f to %.2f px)" % [walking.min(), walking.max()])


func _test_a_step_starts_after_the_display_delay() -> void:
	print("\n== a step from rest starts display_delay ticks after it arrives ==")
	var imp := _mirror("Late", Vector2i(2, 11), 4)
	var moves := _walk(imp, [Vector2i(1, 0)])
	var still := 0
	while still < moves.size() and moves[still] == 0.0:
		still += 1
	# The slide begins on the first sample of the tick it is due in, so the
	# first movement shows on the sample after that.
	_check(still == floori(World.display_delay_ticks * SAMPLES_PER_TICK) + 1, "still for %.1f ticks first (%d samples)" % [World.display_delay_ticks, still])


func _test_the_display_clock_rides_out_late_ticks() -> void:
	print("\n== the display clock runs on smoothly through late and bunched ticks ==")
	World.set_process(true)
	var frame := 1.0 / 60.0
	var server := float(_tick)
	World._net_tick(_tick)
	World._clock = _tick
	World._clock_drift = 0.0
	var shown: Array[float] = []
	var arrivals := 0
	# Six seconds of 60 fps; the ticks come every 100 ms, but every fifth is
	# 80 ms late and arrives with the next.
	var late := -1
	for f in 360:
		server += frame * World.TICK_RATE
		World._process(frame)
		while floori(server) > _tick:
			_tick += 1
			if _tick % 5 == 0:
				late = _tick
				continue
			if late != -1:
				World._net_tick(late)
				arrivals += 1
				late = -1
			World._net_tick(_tick)
			arrivals += 1
		shown.append(World.tick + World.tick_alpha)
	World.set_process(false)
	var steps: Array[float] = []
	for i in range(1, shown.size()):
		steps.append(shown[i] - shown[i - 1])
	var even := frame * World.TICK_RATE
	_check(steps.min() > even * 0.7 and steps.max() < even * 1.3,
			"each frame moves it %.3f to %.3f ticks, never stopping or jumping (even: %.3f)" % [steps.min(), steps.max(), even])
	_check(absf(shown.back() - server) < 1.0, "and it keeps up with the server (%.2f behind)" % (server - shown.back()))


func _test_a_push_is_drawn_as_the_server_timed_it() -> void:
	print("\n== a push is drawn as the server timed it, whichever comes first ==")
	for order in ["the push's word first", "the tile first"]:
		var imp := _mirror("Pushed", Vector2i(2, 13) if order == "the tile first" else Vector2i(2, 15), 4)
		var from := imp.tile
		var to := from + Vector2i(2, 0)
		_run_tick(imp, [])
		if order == "the tile first":
			imp.tile = to
			imp._net_pushed(2, false, false, from, to, float(_tick), 4.0, 0)
		else:
			imp._net_pushed(2, false, false, from, to, float(_tick), 4.0, 0)
			imp.tile = to
		var moves: Array[float] = []
		for i in 10:
			_run_tick(imp, moves)
		var sliding := _trim(moves)
		_check(sliding.size() == 4 * SAMPLES_PER_TICK,
				"%s: it slides the two tiles in the server's 4 ticks, not the jump's guess (%d samples)" % [order, sliding.size()])
		_check(imp.position.is_equal_approx(Iso.tile_to_local(to)), "%s: and ends there" % order)


func _test_a_push_you_made_is_drawn_at_once() -> void:
	print("\n== a push the local player made is drawn at once, not 1.5 ticks later ==")
	var imp := _mirror("Shoved", Vector2i(2, 17), 4)
	var from := imp.tile
	var to := from + Vector2i(2, 0)
	_run_tick(imp, [])
	imp._net_pushed(2, false, false, from, to, float(_tick), 4.0, multiplayer.get_unique_id())
	imp.tile = to
	var moves: Array[float] = []
	_tick += 1
	World._net_tick(_tick)
	World.tick_alpha = 0.1
	imp._process(0.0)
	_check(imp.position != Iso.tile_to_local(from), "moving on the very next frame (at %s)" % Iso.local_to_grid(imp.position))
	for i in 6:
		_run_tick(imp, moves)
	_check(imp.position.is_equal_approx(Iso.tile_to_local(to)), "and there after the server's 4 ticks")
	# Shoved again, and walking back two steps before the slide is over: the
	# steps come due on the display clock while the push still shows.
	imp._net_pushed(2, false, false, to, to + Vector2i(2, 0), float(_tick), 6.0, multiplayer.get_unique_id())
	imp.tile = to + Vector2i(2, 0)
	moves.clear()
	_run_tick(imp, moves)
	for back in 2:
		_run_tick(imp, moves, Vector2i(-1, 0))
		for i in 3:
			_run_tick(imp, moves)
	for i in 10:
		_run_tick(imp, moves)
	var push_sample := _tile_pixels(Vector2i(2, 0)) / (6.0 * SAMPLES_PER_TICK)
	var step_sample := _tile_pixels(Vector2i(1, 0)) / (4.0 * SAMPLES_PER_TICK)
	_check(moves.max() <= maxf(push_sample, step_sample) * 1.05,
			"the walk that came due meanwhile follows on, no jump to its end (largest %.2f px a sample)" % moves.max())
	_check(imp.position.is_equal_approx(Iso.tile_to_local(to)), "and it ends back where it walked to (%s)" % Iso.local_to_grid(imp.position))


func _test_a_guessed_shove() -> void:
	print("\n== your shove, guessed: shown at once, kept, corrected or taken back ==")
	for case in ["right", "wrong", "unanswered"]:
		var imp := _mirror("Guessed_" + case, Vector2i(2, 23 + ["right", "wrong", "unanswered"].find(case) * 2), 4)
		var from := imp.tile
		var guess := from + Vector2i(2, 0)
		_run_tick(imp, [])
		imp.guess_knock(guess, 4.0)
		var moves: Array[float] = []
		_run_tick(imp, moves)
		_check(moves.max() > 0.0, "%s: it starts sliding at once" % case)
		if case != "unanswered":
			var to := guess if case == "right" else from + Vector2i(1, 0)
			imp._net_pushed(2, false, false, from, to, float(_tick), 4.0, multiplayer.get_unique_id())
			imp.tile = to
			for i in 8:
				_run_tick(imp, moves)
			var steady := _trim(moves)
			if case == "right":
				_check(steady.size() == 4 * SAMPLES_PER_TICK and steady.max() - steady.min() < 0.01,
						"right: the server's word changes nothing, one even slide (%d samples, %.2f to %.2f px)" % [steady.size(), steady.min(), steady.max()])
			_check(imp.position.is_equal_approx(Iso.tile_to_local(to)), "%s: it ends where the server put it (%s)" % [case, Iso.local_to_grid(imp.position)])
		else:
			for i in 12:
				_run_tick(imp, moves)
			_check(imp.position.is_equal_approx(Iso.tile_to_local(from)), "unanswered: it slides back to its tile (%s)" % Iso.local_to_grid(imp.position))


func _test_prediction_does_not_walk_into_a_pinned_crate() -> void:
	print("\n== the local player's prediction treats a crate against a wall as a wall ==")
	# A 10 x 3 strip of floor, y 19..21, x 0..9; everything else is off the map.
	var floor_tiles: Array[Vector2i] = []
	for x in 10:
		for y in range(19, 22):
			floor_tiles.append(Vector2i(x, y))
	World.mirror_terrain({"floor": floor_tiles, "fire": [], "edges": {}})
	_crate("Pinned", Vector2i(9, 20))   # Against the east edge.
	_crate("Loose", Vector2i(3, 19))    # Two in a row with floor behind them:
	_crate("Second", Vector2i(2, 19))   # 60 of the player's 80 mass budget.
	_crate("Stacked", Vector2i(1, 20))  # Two in a row...
	_crate("Blocked", Vector2i(0, 20))  # ...ending at the west edge.

	var me := _me(Vector2i(6, 20))
	me.predict_move(Vector2i(9, 20))
	_check(me._prediction.is_active() and _last_step(me) == Vector2i(8, 20),
			"ordered onto the pinned crate: the walk shown stops beside it (last step to %s)" % _last_step(me))
	me._prediction.clear()
	me.predict_move(Vector2i(1, 20))
	_check(_last_step(me) == Vector2i(2, 20), "nor into a crate whose chain ends at the edge (last step to %s)" % _last_step(me))
	me._prediction.clear()
	var other := _me(Vector2i(6, 19))
	other.predict_move(Vector2i(3, 19))
	_check(_last_step(other) == Vector2i(3, 19), "but two crates with room behind them, within the mass budget, are walked into (last step to %s)" % _last_step(other))
	other._prediction.clear()


func _test_prediction_gives_up_when_the_server_has() -> void:
	print("\n== the prediction gives an order up when the server does ==")
	var me := _me(Vector2i(6, 21))
	me.predict_move(Vector2i(8, 21))
	me._process(0.05)
	_check(me._prediction.is_active() and me._prediction.has_target(), "a walk is being shown")
	# The server refused the step into the destination: Player gives the order up.
	me._on_move_refused(Vector2i(8, 21), 0)
	_check(not me._prediction.has_target(), "a refused step into the destination itself: the order is given up")
	for i in 10:
		me._process(0.1)
	_check(not me._prediction.is_active() and me.position.is_equal_approx(Iso.tile_to_local(Vector2i(6, 21))),
			"the sprite blends back to the server's tile and stays (at %s)" % Iso.local_to_tile(me.position))

	me.predict_move(Vector2i(8, 21))
	var mispredicts := Net.mispredicts_total
	for i in 30:  # Well past the deadline; no tile ever arrives from the server.
		me._process(0.1)
	_check(Net.mispredicts_total == mispredicts + 1 and not me._prediction.has_target(),
			"a shown step nobody confirms counts once and the order is given up, not re-planned for ever (%d mispredicts)" % (Net.mispredicts_total - mispredicts))
	_check(not me._prediction.is_active() and me.position.is_equal_approx(Iso.tile_to_local(Vector2i(6, 21))),
			"and the sprite is back on the server's tile")


## A misprediction of more than SNAP_TILES (decision 339): the walk ends
## and the sprite slides from where it is drawn to the server's tile over
## 2-4 ticks, never a jump; TELEPORT_TILES or more is still snapped.
func _test_a_large_correction_slides_not_snaps() -> void:
	print("
== a large correction slides there, a teleport snaps ==")
	var me := _me(Vector2i(6, 21))
	me.predict_move(Vector2i(8, 21))
	me._process(0.05)
	var snaps := Net.snaps_total
	var mispredicts := Net.mispredicts_total
	var drawn := Iso.local_to_grid(me.position)
	World.tick_alpha = 0.0
	me.tile = Vector2i(6, 25)  # The server has it four rows away.
	var worst := 0.0
	var last := drawn
	var frames := 0
	while frames < 80 and not Iso.local_to_grid(me.position).is_equal_approx(Vector2(6, 25)):
		World.tick_alpha += 0.1
		me._process(0.01)
		var at := Iso.local_to_grid(me.position)
		worst = maxf(worst, (at - last).length())
		last = at
		frames += 1
	_check(Net.mispredicts_total == mispredicts + 1 and Net.snaps_total == snaps and not me._prediction.is_active(),
			"a misprediction, no snap, and the walk ended")
	_check(frames >= 25 and frames <= 35 and worst < 0.2,
			"it slides there from %s in %d tenths of a tick, at most %.2f tiles a tenth" % [drawn, frames, worst])
	World.tick_alpha = 0.0
	var far := _me(Vector2i(6, 21))
	far.predict_move(Vector2i(8, 21))
	far._process(0.05)
	far.tile = Vector2i(6, 40)
	far._process(0.0)
	_check(Net.snaps_total == snaps + 1 and Iso.local_to_grid(far.position).is_equal_approx(Vector2(6, 40)),
			"nineteen tiles off is snapped (at %s)" % Iso.local_to_grid(far.position))


## A mirror's slow step (an idle pace) is overtaken by its next, sooner
## than the slow step would end, as a monster that starts to run does
## (decision 350): the next waits for it to end, then catches up at no more
## than twice its pace; never a jump to the slow step's end.
func _test_a_slow_step_overtaken_is_not_cut_short() -> void:
	print("
== a slow step overtaken by the next is not cut short ==")
	var imp := _mirror("Overtaken", Vector2i(2, 13), 10)
	var moves: Array[float] = []
	_run_tick(imp, moves, Vector2i(1, 0))  # A 10-tick step...
	for i in 3:
		_run_tick(imp, moves)
	imp.move_ticks = 2
	_run_tick(imp, moves, Vector2i(1, 0))  # ...and 4 ticks on, a 2-tick one.
	for i in 3:
		_run_tick(imp, moves, Vector2i(1, 0) if i == 1 else Vector2i.ZERO)
	for i in 20:
		_run_tick(imp, moves)
	var slow := _tile_pixels(Vector2i(1, 0)) / (10.0 * SAMPLES_PER_TICK)
	var fast := _tile_pixels(Vector2i(1, 0)) / (World.step_ticks(imp, Vector2i(1, 0)) * SAMPLES_PER_TICK)
	_check(moves.max() <= fast * 2.0 * 1.05, "no jump: at most %.2f px a sample (the fast step's pace %.2f, twice it %.2f, the slow %.2f)" % [
			moves.max(), fast, fast * 2.0, slow])
	_check(imp.position.is_equal_approx(Iso.tile_to_local(Vector2i(5, 13))), "and it ends on its tile (%s)" % Iso.local_to_grid(imp.position))


## No ticks for a second (the server stalled): the display clock waits
## within CLOCK_LEAD_MAX of the last tick instead of running on, and when
## the ticks come again it is never set back (decision 350).
func _test_the_display_clock_waits_out_a_stall() -> void:
	print("
== the display clock waits out a stall, and is never set back ==")
	World.set_process(true)
	var frame := 1.0 / 60.0
	World._net_tick(_tick)
	World._clock = _tick
	World._clock_drift = 0.0
	var shown: Array[float] = []
	for f in 60:  # A second of frames, no ticks.
		World._process(frame)
		shown.append(World.tick + World.tick_alpha)
	var lead: float = shown.back() - float(_tick)
	_tick += 10
	World._net_tick(_tick)  # They come again, ten ticks on.
	for f in 60:
		World._process(frame)
		shown.append(World.tick + World.tick_alpha)
		if f % 6 == 5:
			_tick += 1
			World._net_tick(_tick)
	World.set_process(false)
	var back := 0.0
	for i in range(1, shown.size()):
		back = minf(back, shown[i] - shown[i - 1])
	_check(lead <= World.CLOCK_LEAD_MAX + 0.001, "stalled, it waits %.2f ticks past the last tick" % lead)
	_check(back >= 0.0, "and never goes back (%.2f)" % back)


## Decision 678 (Jeff: "walking still wants to be on a diagonal and it
## doesn't fit with the new camera"): an open floor, 60 x 60 (the tests
## walk its far quarter, clear of the bodies the tests before left).
func _open_floor() -> void:
	var floor_tiles: Array[Vector2i] = []
	for x in 60:
		for y in 60:
			floor_tiles.append(Vector2i(x, y))
	World.mirror_terrain({"floor": floor_tiles, "fire": [], "edges": {}})


## 678's companion question (net_smooth.sh, --test-smooth): the meter says
## which bodies went back, whether their tile did (A, B, A), and swaps.
func _test_the_smooth_meter_names_who_went_back() -> void:
	print("\n== the smooth meter names the bodies that went back, and whether their tile did ==")
	_open_floor()
	var me: Player = _me(Vector2i(50, 50))
	var other := _mirror("Wobbler", Vector2i(52, 50), 3)
	var meter: RefCounted = preload("res://net/smooth_meter.gd").new()
	var path: Array[Vector2i] = [Vector2i(52, 50), Vector2i(53, 50), Vector2i(52, 50)]
	for cell in path:
		other.tile = cell
		for i in 12:
			other.position = Iso.grid_to_local(Vector2(cell) + Vector2(0.1 * i if cell.x == 53 else -0.1 * i, 0.0))
			meter.sample(me, Vector2.ZERO, 1.0 / 60.0)
	var said: String = meter.bodies_report()
	_check(said.begins_with("[smooth] by body: Wobbler (Monster)") and said.contains("1 tile back") and said.ends_with("swaps 0"),
			"it names the monster, its tile back, no swap (%s)" % said)
	other.queue_free()
	me.queue_free()


## Perf's trace on v0.1.177 (the coordinator's ask): a companion standing
## since the join set off a cell a tick just after the client's worst
## hitches; her first slides were due ticks before the display clock got to
## them, and _catch_up drew them at twice the pace on a clock itself
## catching up: six leaps of 0.47 tiles. A body that sets off from standing
## is drawn from the display clock's now (re-anchored), never hurried.
func _test_a_standing_body_starts_without_leaps() -> void:
	print("\n== a body that sets off from standing, late, is drawn without leaps ==")
	var hollis := _mirror("Hollis", Vector2i(40, 40), 1)
	for i in 10:
		_tick += 1
		World._net_tick(_tick)
		hollis._process(0.0)
	# A hitch: three ticks pass, a step a tick arriving, no frame drawn.
	for i in 3:
		_tick += 1
		World._net_tick(_tick)
		hollis.tile += Vector2i(-1, 0)
	var worst := 0.0
	var last := Iso.local_to_grid(hollis.position)
	for i in 14:
		_tick += 1
		World._net_tick(_tick)
		if i < 3:
			hollis.tile += Vector2i(-1, 0)
		for sample in 6:  # 60 frames a second.
			World.tick_alpha = float(sample) / 6.0
			hollis._process(0.0)
			var at := Iso.local_to_grid(hollis.position)
			worst = maxf(worst, at.distance_to(last))
			last = at
	_check(worst <= 0.25, "no frame draws more than a quarter tile (largest %.3f; a cell a tick is 0.167)" % worst)
	_check(Iso.local_to_grid(hollis.position).is_equal_approx(Vector2(34, 40)), "and it arrives (%s)" % Iso.local_to_grid(hollis.position))
	hollis.queue_free()

# --- helpers ------------------------------------------------------------------

func _crate(crate_name: String, tile: Vector2i) -> GridEntity:
	var crate := EntityFactory.build({"script": "res://sim/pushable.gd", "shape": "cube", "name": crate_name, "tile": tile})
	add_child(crate)
	return crate


## The local player as a client sees it: a mirror that predicts its own walking.
func _me(tile: Vector2i) -> GridEntity:
	var me := EntityFactory.build({"script": "res://sim/player.gd", "shape": "capsule", "name": "Me", "tile": tile, "peer": 2})
	add_child(me)
	me._process(0.0)
	me.enable_prediction()
	return me


func _last_step(me: GridEntity) -> Vector2i:
	return me._prediction._steps.back().to if me._prediction.is_active() else Vector2i(-1, -1)


func _mirror(entity_name: String, tile: Vector2i, move_ticks: int) -> GridEntity:
	var entity := EntityFactory.build({"script": "res://sim/monster.gd", "shape": "capsule", "name": entity_name,
		"tile": tile, "props": {"move_ticks": move_ticks}})
	add_child(entity)
	entity._process(0.0)
	return entity


## Feeds [param entity] one replicated step per entry of [param steps], each
## arriving as the one before it ends on the server, then lets the display
## catch up. Returns how far the drawn position moved, sample by sample.
func _walk(entity: GridEntity, steps: Array[Vector2i]) -> Array[float]:
	var moves: Array[float] = []
	for step in steps:
		_run_tick(entity, moves, step)
		for i in int(World.step_ticks(entity, step)) - 1:
			_run_tick(entity, moves)
	for i in ceili(World.display_delay_ticks) + 2:
		_run_tick(entity, moves)
	return moves


## One server tick as a client sees it: the tick, then any tile change made
## in it, then frames.
func _run_tick(entity: GridEntity, moves: Array[float], step := Vector2i.ZERO) -> void:
	_tick += 1
	World._net_tick(_tick)
	if step != Vector2i.ZERO:
		entity.tile += step
	for sample in SAMPLES_PER_TICK:
		World.tick_alpha = float(sample) / SAMPLES_PER_TICK
		var before := entity.position
		entity._process(0.0)
		moves.append(before.distance_to(entity.position))


## [param moves] without the standing still before and after.
func _trim(moves: Array[float]) -> Array[float]:
	var first := 0
	while first < moves.size() and moves[first] == 0.0:
		first += 1
	var last := moves.size() - 1
	while last >= first and moves[last] == 0.0:
		last -= 1
	return moves.slice(first, last + 1)


func _tile_pixels(step: Vector2i) -> float:
	return Iso.tile_to_local(Vector2i.ZERO).distance_to(Iso.tile_to_local(step))


## The 3D camera's follow (client3d/camera_ease.gd, decision 337): a slide
## at a push's speed is followed with no lag, a jump is eased over a few
## frames at no more than a sixth of a tile a frame, and a teleport is
## taken at once.
func _test_the_camera_eases_over_a_jump_not_a_slide() -> void:
	print("
== the camera eases over a jump, not a slide ==")
	var ease: RefCounted = preload("res://client3d/camera_ease.gd").new()
	var dt := 1.0 / 60.0
	ease.follow(Vector3.ZERO, dt)
	var worst_lag := 0.0
	for frame in 30:  # A 5 tiles a second slide (a push's), half a second.
		var at := Vector3((frame + 1) * 5.0 * dt, 0.0, 0.0)
		worst_lag = maxf(worst_lag, (ease.follow(at, dt) - at).length())
	_check(worst_lag < 0.001, "a slide is followed as it is (lag %.3f tiles)" % worst_lag)
	var held: Vector3 = ease.follow(Vector3(5.5, 0.0, 0.0), dt)
	var last := held
	var worst_frame := 0.0
	var frames := 0
	while frames < 60 and (last - Vector3(5.5, 0.0, 0.0)).length() > 0.01:
		var now: Vector3 = ease.follow(Vector3(5.5, 0.0, 0.0), dt)
		worst_frame = maxf(worst_frame, (now - last).length())
		last = now
		frames += 1
	_check(held.x < 2.6 + 0.2 and worst_frame <= 10.0 * dt + 0.001 and frames < 36,
			"a 3-tile jump: the camera holds (%.2f) and closes in %d frames, at most %.3f a frame" % [held.x, frames, worst_frame])
	var cut: Vector3 = ease.follow(Vector3(20.0, 0.0, 0.0), dt)
	_check(cut.is_equal_approx(Vector3(20.0, 0.0, 0.0)), "a respawn's teleport is taken at once (%s)" % cut)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
