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


# --- helpers ------------------------------------------------------------------

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
