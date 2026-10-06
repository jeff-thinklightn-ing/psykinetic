extends Node
## How a client draws an entity it does not predict: replicated tile changes
## fed to a mirror by hand, its drawn position sampled five times a tick.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const SAMPLES_PER_TICK := 5

var _failures := 0
var _tick := 100


func _ready() -> void:
	World.set_process(false)
	Net.mode = Net.Mode.CLIENT  # Never started: this process is only a mirror.
	World.mirror_reset()

	_test_a_walk_is_drawn_without_jumps_or_pauses()
	_test_a_fast_walker_slides_too()
	_test_turning_a_corner()
	_test_a_step_starts_after_the_display_delay()
	_test_prediction_does_not_walk_into_a_pinned_crate()
	_test_prediction_gives_up_when_the_server_has()

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
	print("\n== so is one whose step is as short as the display delay ==")
	# Two ticks a step, drawn two ticks behind: the next step arrives just as
	# this one's slide is due to begin.
	var runner := _mirror("Runner", Vector2i(2, 7), World.display_delay_ticks)
	var moves := _walk(runner, [Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0)])
	var per_sample := _tile_pixels(Vector2i(1, 0)) / float(World.display_delay_ticks * SAMPLES_PER_TICK)
	var walking := _trim(moves)
	_check(walking.max() <= per_sample * 1.05 and walking.min() >= per_sample * 0.95,
			"an even slide, not tile-to-tile hops (%.2f to %.2f px a sample, want %.2f)" % [walking.min(), walking.max(), per_sample])
	_check(runner.position.is_equal_approx(Iso.tile_to_local(Vector2i(6, 7))), "ending on its tile")


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
	_check(still == World.display_delay_ticks * SAMPLES_PER_TICK + 1, "still for %d ticks first (%d samples)" % [World.display_delay_ticks, still])


func _test_prediction_does_not_walk_into_a_pinned_crate() -> void:
	print("
== the local player's prediction treats a crate against a wall as a wall ==")
	# A 10 x 3 strip of floor, y 19..21, x 0..9; everything else is off the map.
	var floor_tiles: Array[Vector2i] = []
	for x in 10:
		for y in range(19, 22):
			floor_tiles.append(Vector2i(x, y))
	World.mirror_terrain(floor_tiles, [])
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
	print("
== the prediction gives an order up when the server does ==")
	var me := _me(Vector2i(6, 21))
	me.predict_move(Vector2i(8, 21))
	me._process(0.05)
	_check(me._prediction.is_active() and me._prediction.has_target(), "a walk is being shown")
	# The server refused the step into the destination: Player gives the order up.
	me._on_move_refused(Vector2i(8, 21))
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
		for i in World.step_ticks(entity, step) - 1:
			_run_tick(entity, moves)
	for i in World.display_delay_ticks + 2:
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


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
