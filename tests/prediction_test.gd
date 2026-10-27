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
## 300 ms round trip) the walk is neither corrected nor slowed. 655
## amended: a held key's hint bends the walk shown toward the step to
## come, the key let go settles the body to the centre, a hint into a wall
## bends nothing, and a step the server refuses slides back from the bend.
## 543 amended, ui's side: a held walk pauses while the server holds three
## of its steps unseen, so a slowed or stalled server never drops a step
## unheard and the server's path never parts from the shown one; a server
## keeping up never pauses it. Run it with tests/run.ps1 or tests/run.sh.

const SIZE := 40
const FRAME := 1.0 / 60.0

var _failures := 0
var _main: Node


func _ready() -> void:
	World.set_process(false)
	# The grid's steps: free walk is the default (decision 693).
	Net.free_walk = false
	World.free_walk = false
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
	_test_hinted_walk()
	_test_through_her()
	Net.test_lag = 0.0
	Level.unregister("pt_field")
	_main.load_map(Level.DEFAULT_MAP)
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## An open stone field, the start at (2, 20), one wall cell at (2, 18).
static func _layout() -> Image:
	var rows: Array[String] = []
	for y in 2 * SIZE - 1:
		rows.append(".".repeat(2 * SIZE - 1))
	rows[36] = rows[36].substr(0, 4) + "#" + rows[36].substr(5)
	return Level.image_from_rows(rows, {Vector2i(2, 20): "start"})


## 655 amended: the own walk's bends from the held key.
func _test_hinted_walk() -> void:
	print("\n== the own walk bends toward the held key's next step (655 amended) ==")
	Net.test_lag = 0.4 * World.TICK_DT  # The server keeping up (40 ms), as the first walk is.
	var zigzag := _drive([Vector2i(1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0)], true)
	_check(zigzag["corrections"] == 0 and zigzag["paused"] == 0, "a held zigzag, the server keeping up: no corrections, never paused (%d, %d)" % [zigzag["corrections"], zigzag["paused"]])
	_check(zigzag["bends"] == 4, "each step's end bent toward the step the held key then brought, which starts on that bend (%d of 4)" % zigzag["bends"])
	_check(zigzag["cut"] >= 0.12 and zigzag["cut"] <= 0.26, "at the first corner the body is off the centre, on the bend, by under a quarter cell (%.3f)" % zigzag["cut"])
	_check(zigzag["jump"] <= zigzag["frame"] * 1.5, "no frame jumps: at most a frame and a half's walk between frames (%.3f cells, a frame's walk %.3f)" % [zigzag["jump"], zigzag["frame"]])
	_check(zigzag["settled"] and zigzag["rest"].distance_to(Vector2(zigzag["end"])) < 0.02 and not zigzag["active"],
			"the key held past the last step's tail then let go: the body settles to the last cell's centre and the walk ends (%s, %s)" % [zigzag["rest"], zigzag["end"]])
	var wall := _drive([Vector2i(0, -1), Vector2i(0, -1)], true)
	_check(wall["bends"] == 0 and not wall["settled"] and not wall["active"] and wall["rest"].distance_to(Vector2(wall["end"])) < 0.1 and wall["end"] == Vector2i(2, 19),
			"a key held into a wall: no bend toward it, the body stops on the cell's centre (%s, %s)" % [wall["rest"], wall["end"]])
	_test_paused_walk()
	_test_let_go()
	var refused := _drive([Vector2i(1, 0), Vector2i(1, 0), Vector2i(0, 1)], true, 2)
	_check(refused["corrections"] == 1 and refused["bends"] == 2, "a third step the server refuses: one correction, the two before it bent (%d, %d)" % [refused["corrections"], refused["bends"]])
	_check(refused["jump"] <= refused["frame"] * 1.5 and not refused["active"] and refused["rest"].distance_to(Vector2(refused["end"])) < 0.02 and refused["end"] == Vector2i(4, 20),
			"the body slides back from the bend to the server's cell, no jump (%.3f cells a frame at most; rest %s, server %s)" % [refused["jump"], refused["rest"], refused["end"]])


## 683 (the coordinator's latency table: a stop was the step's rest and a
## 150 ms slide back after it): a key let go in the step's tail, bent toward
## the step it hinted, stands on the centre as the step ends, with no settle;
## let go after the step ended (the body coasting on the bend), the settle
## is at the walking pace, under the old SETTLE_TICKS.
func _test_let_go() -> void:
	print("\n== 683: let go, the body stands as its step ends ==")
	var east := [Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0)]
	var tail := _drive(east, true, -1, 1.0, 0.0, 0.8)
	_check(not tail["settled"] and tail["corrections"] == 0 and tail["rest"].distance_to(Vector2(5, 20)) < 0.1 and tail["end"] == Vector2i(5, 20),
			"let go at 80%% of the last step, bent toward the next: no settle, on the centre of %s (%s)" % [tail["end"], tail["rest"]])
	_check(tail["last_move"] - tail["last_end"] <= 0.05, "and standing as the step ends (%.2f ticks after)" % (tail["last_move"] - tail["last_end"]))
	_check(tail["jump"] <= tail["frame"] * 1.5, "no frame jumps as the bend lets go (%.3f cells, a frame's walk %.3f)" % [tail["jump"], tail["frame"]])
	var late := _drive(east, true, -1, 1.0, 0.0, 1.1)
	_check(late["settled"] and late["rest"].distance_to(Vector2(5, 20)) < 0.02 and not late["active"],
			"let go just after the step ended, coasting on the bend: the settle brings it to the centre (%s)" % late["rest"])
	_check(late["last_move"] - late["last_end"] <= 0.25 + MovePrediction.SETTLE_MIN_TICKS * 2.0,
			"at the walking pace: standing %.2f ticks after the step's end (the old settle alone was %.1f)" % [late["last_move"] - late["last_end"], MovePrediction.SETTLE_TICKS])


## 543 amended, ui's side: the held walk against a server that cannot keep
## up, which keeps three queued steps and drops a fourth unheard
## (World.order_step).
func _test_paused_walk() -> void:
	print("\n== the held walk pauses while the server holds three steps (543 amended, ui's side) ==")
	var east: Array = []
	for i in 12:
		east.append(Vector2i(1, 0))
	var slow := _drive(east, false, -1, 0.6)
	_check(slow["dropped"] == 0 and slow["paused"] > 0 and slow["end"] == Vector2i(14, 20),
			"a server walking at 60%% of the pace: the walk pauses (%d frames) rather than send a step it would drop (%d dropped); every step walked, to %s" % [slow["paused"], slow["dropped"], slow["end"]])
	_check(slow["elsewhere"] == 0, "and the server's path never parts from the shown one (%d corrections, none 'elsewhere')" % slow["corrections"])
	var stalled := _drive(east.slice(0, 8), false, -1, 1.0, 15.0)
	_check(stalled["dropped"] == 0 and stalled["paused"] > 0 and stalled["end"] == Vector2i(10, 20) and stalled["elsewhere"] == 0,
			"a server stalled 15 ticks: the walk pauses (%d frames), nothing dropped, the server walks every step to %s (%d corrections)" % [stalled["paused"], stalled["end"], stalled["corrections"]])
	var steady := _drive(east, false)
	_check(steady["paused"] == 0 and steady["dropped"] == 0 and steady["corrections"] == 0, "the server keeping up: never paused, nothing dropped, no corrections")
	Net.test_lag = 8.0 * World.TICK_DT  # A long way to the server: three steps in flight at once.
	var far := _drive(east, false)
	_check(far["paused"] == 0 and far["dropped"] == 0 and far["corrections"] == 0, "an 800 ms round trip, the server keeping up: never paused either (%d, %d, %d)" % [far["paused"], far["dropped"], far["corrections"]])
	Net.test_lag = 0.4 * World.TICK_DT


## [param dirs] WASD steps held from (2, 20), one after another as each shown
## step ends, the key read each frame (the hint): the next direction, the
## last one again after them while [param hold_on], else none. The scripted
## server as _walk's, keeping up, refusing the step at [param refuse_at]
## (and emptying its queue, as the real one does); walking at [param slow]
## of the pace (its step takes pace / slow), taking nothing before tick
## [param hold_until]; holding World.MAX_QUEUED_STEPS steps and dropping a
## further one unheard, as World.order_step does. {corrections, elsewhere
## (corrections where the server's tile was off the shown path), bends
## (steps that started on the bend the step before settled toward them),
## cut (how far off the centre the body is as the first turn's corner
## moment passes), jump (the most the body moved between frames, cells),
## frame (a straight step's walk in a frame), settled (a settle was shown),
## active (the prediction still active at the end), rest (where the body
## was last drawn), end (the server's tile at the end), paused (frames the
## walk waited on the server), dropped (steps the server dropped),
## last_move (the clock of the last frame the body moved on), last_end (the
## last step's end, a settle aside)}. 683: held on, the key is let go at
## [param release_t] of the last step's time (never if negative).
func _drive(dirs: Array, hold_on: bool, refuse_at := -1, slow := 1.0, hold_until := 0.0, release_t := -1.0) -> Dictionary:
	var player := _player()
	World._relocate(player, Vector2i(2, 20))
	for other in World.get_entities():
		if other != player and other.spawned:
			World._relocate(other, Vector2i(2, 35))
	player.position = Iso.grid_to_local(Vector2(player.tile))
	var shown := MovePrediction.new(player)
	var pace := World.step_ticks(player, Vector2i(1, 0))
	var one_way := Net.test_lag / World.TICK_DT / 2.0
	var clock := 0.0
	var sent: Array = []  # [arrives at the server, direction]
	var told: Array = []  # [reaches the client, tile, refused]
	var server_tile := player.tile
	var server_due := 0.0
	var server_tick := 0
	var server_took := 0
	var queue: Array[Vector2i] = []  # Arrived at the server, not taken: its queued_steps.
	var dropped := 0
	var paused := 0
	var elsewhere := 0
	var sent_count := 0
	var corrections := 0
	var bends := 0
	var cut := -1.0
	var jump := 0.0
	var settled := false
	var last_pos := Vector2(player.tile)
	var last_move := 0.0
	var last_end := 0.0
	var total := 0.0
	for direction: Vector2i in dirs:
		total += World.step_ticks(player, direction)
	while clock < total / slow + hold_until + 30.0:
		clock += FRAME * World.TICK_RATE
		if shown.advance(FRAME):
			corrections += 1
			shown.rebase(player.tile, 2.0)
		# The frame's draw, as GridEntity._process: the body where the prediction has it.
		if shown.is_active():
			var pos := Iso.local_to_grid(shown.position())
			if pos.distance_to(last_pos) > FRAME * World.TICK_RATE / pace * 1.5 and not shown._current().ease:
				var current: MovePrediction.Step = shown._current()  # (A correction's blend is a known fast slide.)
				print("    jump at %.2f: %s -> %s on %s->%s t %.2f (ease %s, settle %s, %d steps, bend %s/%s)" % [clock, last_pos, pos,
						current.from, current.to, (clock - current.start) / current.duration, current.ease, current.settle, shown._steps.size(), current.bend_prev, current.bend_next])
			jump = maxf(jump, pos.distance_to(last_pos))
			if pos.distance_to(last_pos) > 0.0005:
				last_move = clock
			last_pos = pos
			for i in range(shown._steps.size() - 1, -1, -1):
				if not shown._steps[i].settle:
					last_end = shown._steps[i].start + shown._steps[i].duration
					break
			player.position = shown.position()
			if shown._steps.back().settle:
				settled = true
		# Main._drive_wasd: the key held told each frame; the step as the one shown ends.
		var held: Vector2i = Vector2i.ZERO
		var t_last := 0.0
		if shown.is_active():
			var under: MovePrediction.Step = shown._steps.back()
			t_last = (clock - under.start) / under.duration
		if sent_count < dirs.size():
			held = dirs[sent_count]
		elif hold_on and (release_t < 0.0 or t_last < release_t):
			held = dirs.back()
		shown.hint(held)
		if sent_count < dirs.size() and shown.waiting_on_server():
			paused += 1
		if sent_count < dirs.size() and shown.ready_for_step():
			var before: MovePrediction.Step = shown._steps.back() if shown.is_active() else null
			if shown.step(held):
				var step: MovePrediction.Step = shown._steps.back()
				if before != null and before.bend_next == step.to and step.bend_prev == before.from:
					bends += 1
					if cut < 0.0 and step.to - step.from != before.to - before.from:
						cut = Iso.local_to_grid(shown.position()).distance_to(Vector2(step.from))
				sent.append([clock + one_way, held])
			sent_count += 1
		while server_tick <= floori(clock):
			while not sent.is_empty() and sent[0][0] <= server_tick:
				var arrived: Array = sent.pop_front()
				if queue.size() >= World.MAX_QUEUED_STEPS:
					dropped += 1  # As World.order_step: a fourth queued step is dropped unheard.
				else:
					queue.append(arrived[1])
			if not queue.is_empty() and server_tick >= server_due and server_tick >= hold_until:
				var direction: Vector2i = queue.pop_front()
				var start := float(server_tick)
				if server_tick - server_due < 1.0:
					start = server_due  # Its clock kept within a tick, as World.try_move keeps it.
				server_due = start + pace / slow
				var refuse := server_took == refuse_at
				if refuse:
					sent.clear()
					queue.clear()
				else:
					server_tile += direction
				server_took += 1
				told.append([server_tick + one_way, server_tile, refuse])
			server_tick += 1
		while not told.is_empty() and told[0][0] <= clock:
			var reply: Array = told.pop_front()
			World._relocate(player, reply[1])
			if reply[2]:
				# As GridEntity._step_refused: the queue gone, the walk rebased.
				corrections += 1
				shown.server_dropped_queue()
				shown.rebase(reply[1], 2.0)
			elif shown.is_active() and not shown.reconcile(reply[1]):
				corrections += 1
				var on_path := false
				for step in shown._steps:
					if step.to == reply[1] or step.from == reply[1]:
						on_path = true
				if not on_path:
					elsewhere += 1
				shown.rebase(reply[1], 2.0)
	return {"corrections": corrections, "elsewhere": elsewhere, "bends": bends, "cut": cut, "jump": jump, "frame": FRAME * World.TICK_RATE / pace,
			"settled": settled, "active": shown.is_active(), "rest": last_pos, "end": server_tile, "paused": paused, "dropped": dropped,
			"last_move": last_move, "last_end": last_end}


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


## The swap rule: a held walk east through the player's own companion, the
## real World.try_move the server: the client shows the step into her cell
## (her cell open to her own player), the server takes it on its tick and
## they change places, so nothing is corrected, refused or late. Not
## another's companion, not one downed, never across a wall's corner.
func _test_through_her() -> void:
	print("
== a held walk through her own companion: swapped on the step's tick, nothing corrected or late (the swap rule) ==")
	Net.test_lag = 0.4 * World.TICK_DT
	var player := _player()
	var pet: Companion = null
	for other in World.get_entities():
		if other is Companion and other.spawned and (other as Companion).keeper == player:
			pet = other
	_check(pet != null, "the host's companion is there")
	if pet == null:
		return
	World._relocate(player, Vector2i(10, 24))
	World._relocate(pet, Vector2i(12, 24))
	var shown := MovePrediction.new(player)
	var pace := World.step_ticks(player, Vector2i(1, 0))
	var one_way := 0.2
	var base := World.tick
	var clock := 0.0
	var sent: Array = []
	var told: Array = []
	var shown_at: Array[float] = []
	var took_at: Array[float] = []
	var corrections := 0
	var refused := 0
	var steps := 6
	while clock < steps * pace * 2.0 + 20.0:
		clock += FRAME * World.TICK_RATE
		if shown.advance(FRAME):
			corrections += 1
			shown.rebase(player.tile, 2.0)
		if shown_at.size() < steps and shown.ready_for_step() and shown.step(Vector2i(1, 0)):
			shown_at.append((shown._steps.back() as MovePrediction.Step).start)
			sent.append([clock + one_way, Vector2i(1, 0)])
		while World.tick <= base + floori(clock):
			if not sent.is_empty() and sent[0][0] <= World.tick - base and World.tick >= player.next_move_tick:
				var due := player.next_move_tick
				if World.try_move(player, sent[0][1]):
					sent.pop_front()
					took_at.append((due if World.tick - due < 1.0 else float(World.tick)) - base)  # Its clock kept within a tick, as try_move keeps it.
					told.append([World.tick - base + one_way, player.tile])
				else:
					refused += 1
			World.tick += 1
		while not told.is_empty() and told[0][0] <= clock:
			if shown.is_active() and not shown.reconcile(told.pop_front()[1]):
				corrections += 1
				shown.rebase(player.tile, 2.0)
	var late := 0
	for i in mini(shown_at.size(), took_at.size()):
		if took_at[i] > shown_at[i] + one_way + 1.0:
			late += 1
	_check(took_at.size() == steps and player.tile == Vector2i(16, 24) and pet.tile == Vector2i(11, 24),
			"6 steps east from (10, 24) through her at (12, 24): at %s, she at %s, where he stood" % [player.tile, pet.tile])
	_check(corrections == 0 and refused == 0 and late == 0,
			"none corrected, refused or late (%d, %d, %d)" % [corrections, refused, late])
	# The server's rule alone: not another's, not downed, not round a wall's corner.
	World._relocate(player, Vector2i(10, 24))
	World._relocate(pet, Vector2i(11, 24))
	player.next_move_tick = 0
	pet.keeper = null
	_check(not World.try_move(player, Vector2i(1, 0)) and pet.tile == Vector2i(11, 24), "another's companion (no keeper his): no swap")
	pet.keeper = player
	pet.downed_until = World.tick + 100
	_check(not World.try_move(player, Vector2i(1, 0)) and pet.tile == Vector2i(11, 24), "she lies downed: no swap")
	pet.downed_until = 0
	# Dodging or fighting she swaps all the same (679 amended): the client
	# cannot see her intent, so a refusal there would snap his body back.
	for intent: int in [Companion.Intent.ATTACK, Companion.Intent.DODGE]:
		World._relocate(player, Vector2i(10, 24))
		World._relocate(pet, Vector2i(11, 24))
		player.next_move_tick = 0
		pet.current_intent = intent
		_check(World.try_move(player, Vector2i(1, 0)) and player.tile == Vector2i(11, 24) and pet.tile == Vector2i(10, 24),
				"she %s: swapped all the same, he at %s, she at %s" % ["fights (ATTACK)" if intent == Companion.Intent.ATTACK else "dodges (DODGE)", player.tile, pet.tile])
	pet.current_intent = Companion.Intent.FOLLOW
	World._relocate(player, Vector2i(10, 24))
	World._relocate(pet, Vector2i(11, 24))
	player.next_move_tick = 0
	# Stunned (679 amended): the server refuses and the prediction knows it
	# (_reel_until, set on a client by _net_stunned), so nothing is corrected.
	var predicted := MovePrediction.new(player)
	pet._world_stunned(World.tick + 30, 30)
	_check(not predicted._swaps_with(pet) and predicted._blocked(player.tile, Vector2i(1, 0))
			and not World.try_move(player, Vector2i(1, 0)) and pet.tile == Vector2i(11, 24),
			"she reels from a stun: no swap, and the prediction shows him stopped")
	pet._world_stunned(0, 0)
	pet._reel_until = 0.0
	_check(predicted._swaps_with(pet) and not predicted._blocked(player.tile, Vector2i(1, 0)), "the stun over: her cell open to him again")
	# The wall cell (2, 18): a diagonal from (2, 19) to (3, 18) cuts its corner.
	World._relocate(player, Vector2i(2, 19))
	World._relocate(pet, Vector2i(3, 18))
	player.next_move_tick = 0
	var cut := World._terrain_blocks_step(Vector2i(2, 19), Vector2i(1, -1), true)
	_check(cut and not World.try_move(player, Vector2i(1, -1)) and pet.tile == Vector2i(3, 18) and player.tile == Vector2i(2, 19),
			"round the wall's corner, where a step is blocked: no swap (%s)" % cut)
	World._relocate(pet, Vector2i(2, 35))


func _player() -> Player:
	for entity in World.get_entities():
		if entity is Player and entity.spawned:
			return entity
	return null


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
