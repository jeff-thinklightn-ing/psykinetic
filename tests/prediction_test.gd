extends Node
## MovePrediction's WASD walk against a scripted server (decision 543): the
## server walks the steps sent on its own tick clock, a one-way trip after
## each is sent, and its tile reaches the client a one-way trip later, where
## reconcile confirms it or a correction rebases the walk (as
## GridEntity._mispredicted does). A held walk with the server keeping up is
## shown as before, uncorrected and unstretched; one whose first step the
## server takes 5 ticks late (a backlog of over a step) is corrected at most
## once and catches up, and so does one 12 ticks late, past the wait, its
## queued steps shown again from the server's tile; over a slow link (a
## 300 ms round trip) the walk is neither corrected nor slowed. Run it with
## tests/run.ps1 or tests/run.sh.

const SIZE := 40
const FRAME := 1.0 / 60.0

var _failures := 0
var _main: Node


func _ready() -> void:
	World.set_process(false)
	Net.port = preload("res://tests/test_ports.gd").of(17911)
	Monster.idling = false
	_main = preload("res://main.tscn").instantiate()
	_main.returns = false
	add_child(_main)
	Level.register("pt_field", _layout(), null, {"name": "The Field", "outdoor": true})
	_check(_main.load_map("pt_field"), "the level loads")
	var keeping := _walk(0.4, 0.0, 20)
	_check(keeping["corrections"] == 0, "the server keeping up (40 ms): no corrections (%d)" % keeping["corrections"])
	_check(keeping["stretched"] == 0, "and no step drawn longer: the walk as it was (%d stretched)" % keeping["stretched"])
	var held := _walk(0.4, 5.0, 20)
	_check(held["corrections"] <= 1, "the server's first step 5 ticks late: at most 1 correction (%d)" % held["corrections"])
	_check(held["behind"] <= held["step"] * 1.01, "and it caught up to within a step (%.2f ticks behind at the end)" % held["behind"])
	var long := _walk(0.4, 12.0, 20)
	_check(long["corrections"] <= 1, "12 ticks late, past the wait: corrected once, the queued steps shown again, no more after (%d)" % long["corrections"])
	_check(long["behind"] <= long["step"] * 1.01, "and caught up (%.2f ticks behind at the end)" % long["behind"])
	var slow := _walk(3.0, 0.0, 20)
	_check(slow["corrections"] == 0 and slow["stretched"] == 0, "a 300 ms round trip: none corrected (%d), none slower (%d)" % [slow["corrections"], slow["stretched"]])
	Net.test_lag = 0.0
	Level.unregister("pt_field")
	_main.load_map(Level.DEFAULT_MAP)
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## An open stone field, the start at (2, 20).
static func _layout() -> Image:
	var rows: Array[String] = []
	for y in 2 * SIZE - 1:
		rows.append(".".repeat(2 * SIZE - 1))
	return Level.image_from_rows(rows, {Vector2i(2, 20): "start"})


## [param steps] WASD steps east held from (2, 20), a round trip of
## [param rtt] ticks, the server's first step no sooner than tick
## [param held_back]. {corrections, stretched (steps drawn longer than
## their pace), behind (ticks the last shown step starts ahead of the
## server taking it), step (a step's ticks)}.
func _walk(rtt: float, held_back: float, steps: int) -> Dictionary:
	Net.test_lag = rtt * World.TICK_DT
	var player := _player()
	World._relocate(player, Vector2i(2, 20))
	for other in World.get_entities():
		if other != player and other.spawned:
			World._relocate(other, Vector2i(2, 35))  # Her companion, out of the way.
	var shown := MovePrediction.new(player)
	var pace := World.step_ticks(player, Vector2i(1, 0))
	var one_way := rtt / 2.0
	var clock := 0.0
	var sent: Array = []  # [arrives at the server, direction]
	var told: Array = []  # [reaches the client, tile]
	var server_tile := player.tile
	var server_due := held_back
	var server_tick := 0
	var corrections := 0
	var stretched := 0
	var sent_count := 0
	var last_start := 0.0
	var server_took: Array[float] = []
	while clock < steps * pace * 2.0 + 20.0:
		clock += FRAME * World.TICK_RATE
		if shown.advance(FRAME):
			corrections += 1
			shown.rebase(player.tile, 2.0)
		if sent_count < steps and shown.ready_for_step() and shown.step(Vector2i(1, 0)):
			sent_count += 1
			var last: MovePrediction.Step = shown._steps.back()
			if last.duration > pace + 0.001:
				stretched += 1
			last_start = last.start
			sent.append([clock + one_way, Vector2i(1, 0)])
		# The server's ticks up to now: a queued step that has arrived, taken
		# when due, its clock kept within a tick as World.try_move keeps it.
		while server_tick <= floori(clock):
			if not sent.is_empty() and sent[0][0] <= server_tick and server_tick >= server_due:
				var start := float(server_tick)
				if server_tick - server_due < 1.0:
					start = server_due
				server_due = start + pace
				server_tile += sent.pop_front()[1]
				server_took.append(start)
				told.append([server_tick + one_way, server_tile])
			server_tick += 1
		while not told.is_empty() and told[0][0] <= clock:
			var tile: Vector2i = told.pop_front()[1]
			World._relocate(player, tile)
			if shown.is_active() and not shown.reconcile(tile):
				corrections += 1
				shown.rebase(tile, 2.0)
	# The prediction's clock and the server's ticks run together here.
	var behind: float = server_took.back() - last_start if server_took.size() == steps else INF
	return {"corrections": corrections, "stretched": stretched, "behind": behind, "step": pace}


func _player() -> Player:
	for entity in World.get_entities():
		if entity is Player and entity.spawned:
			return entity
	return null


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
