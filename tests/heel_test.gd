extends Node
## Her fall-in behind her player while he walks on (485 amended (7); the
## coordinator's TASK 13, K1 of the stands counted on 6f1060b55): on the wilds,
## her player a free body jogging through her and on, straight and at 2:1,
## she facing him and facing away; the look's shuttle, turned at once and after
## 0.3 s; a turn straight back in the middle of her fall-in; a jog and a stop,
## and from still 555's start band; and the fence: a body on a Heel made as an
## escort makes it follows as before. Prints PASS/FAIL per assertion and quits
## with exit code 1 if any assertion failed, 0 otherwise.

var _failures := 0
var _main: Node
## Two open starts on the wilds (14 open cells every way round them, and beside).
const STARTS: Array[Vector2i] = [Vector2i(155, 199), Vector2i(200, 182)]
## The escort's follow through the "front" straight pass on 6f1060b55 (main
## before the fall-in): its cell each tick its step started, {tick from the jog: cell}.
const ESCORT_ON_MAIN := "1:155,200 7:155,199 12:154,199 17:153,199 21:152,199 25:151,199 29:150,199"


func _ready() -> void:
	World.set_process(false)
	var ports := preload("res://tests/test_ports.gd")
	Net.port = ports.of(18012)
	Net.companions = true
	Net.map_name = "wilds"
	Net.state_path = ports.scratch("heel_test_world.json")
	if FileAccess.file_exists(Net.state_path):
		DirAccess.remove_absolute(Net.state_path)
	Level.overlay_dir = ports.scratch("heel_test_overlay/")
	Companion.tends_unasked = false
	FirstSteps.forced = 0
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	for i in 5:
		await get_tree().process_frame
	for i in 3:
		World.step()
	for body: GridEntity in World.townsfolk().duplicate():
		World.despawn(body)
	for body: GridEntity in World.get_entities().duplicate():
		if (body is Monster or body is Animal) and body.spawned:
			World.despawn(body)
	DayNight.set_hour(12.0)
	_check(_player() != null and _companion() != null, "(her player and her on the wilds)")
	if _player() == null or _companion() == null:
		_finish()
		return
	_test_escort()
	_test_through()
	_test_shuttle()
	_test_turn_back()
	_test_stop()
	_finish()


func _finish() -> void:
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _player() -> Player:
	for e in World.get_entities():
		if e is Player and e.spawned:
			return e
	return null


func _companion() -> Companion:
	for e in World.get_entities():
		if e is Companion and e.spawned:
			return e
	return null


## [param him] and [param body] put on [param p] and [param q], his free body still.
func _place(him: Player, body: GridEntity, p: Vector2i, q: Vector2i) -> void:
	him.free_inputs.clear()
	him.free_way = Vector2.ZERO
	if him.tile != p:
		var there: Variant = World._occupancy.get(p)
		if there != null and there != him:
			World._relocate(there, q + Vector2i(5, 5))
		World._relocate(him, p)
	him.free_pos = Vector2(p)
	if body.tile != q:
		World._relocate(body, q)


## Whether [param him] moves now (Heel.moving, kept here so the fence's row reads main too).
static func _moving(him: GridEntity) -> bool:
	return World.tick <= him.step_until + 1.0 and him.step_velocity != Vector2.ZERO


## His cell past [param body]'s along his way.
static func _past(him: GridEntity, body: GridEntity) -> bool:
	return Heel.ahead_of(body.tile - him.tile, Heel.travel(him)) < 0


## [param ticks] ticks of [param him] jogging [param way], each logged for [param body]
## ([param heel] followed after each step: a body Main does not drive).
func _jog(him: Player, body: GridEntity, way: Vector2, ticks: int, log: Array, heel: Heel = null) -> void:
	for i in ticks:
		World.free_input(him, way.normalized(), World.TICK_DT)
		World.step()
		if heel != null:
			heel.follow(body, him)
		_log(him, body, log)


func _idle(him: Player, body: GridEntity, ticks: int, log: Array = [], heel: Heel = null) -> void:
	for i in ticks:
		World.step()
		if heel != null:
			heel.follow(body, him)
		_log(him, body, log)


func _log(him: Player, body: GridEntity, log: Array) -> void:
	var heel: Variant = body.get("heel")
	log.append({"t": World.tick, "her": body.tile, "him": him.tile, "centre": him.free_pos, "last": body.last_step_tick,
		"until": body.step_until, "moving": him.last_step_tick == World.tick, "past": _past(him, body), "heading": him.step_velocity.normalized(),
		"stunned": World.is_stunned(him) or World.is_stunned(body),
		"settled": heel != null and not heel.catching_up, "goal": heel.get("_goal") if heel != null else null,
		"fall": heel.get("_fall_goal") if heel != null else null, "ticks": body.move_ticks,
		"guarded": heel != null and heel.get("falls_in") == true and not (heel.get("_trail") as Array).is_empty()
			and heel.get("_her_left") == (heel.get("_trail") as Array)[0],
		"trail": (heel.get("_trail") as Array).slice(0, 2) if heel != null else [],
		"with": (heel.get("_trail") as Array).slice(0, 2).map(func(at: Vector2i) -> bool: return Heel._with(body, him, at) and not Heel._yet_to_cross(him, at)) if heel != null else []})


## [param log] a row a tick, when a row fails (DEBUG_HEEL).
func _dump(log: Array) -> void:
	for r: Dictionary in log:
		print("    t%d her %s last %d until %.2f ticks %.2f | him %s (%.2f,%.2f) moving %s past %s settled %s goal %s fall %s trail %s with %s" % [r["t"], r["her"], r["last"], r["until"], r["ticks"],
			r["him"], r["centre"].x, r["centre"].y, r["moving"], r["past"], r["settled"], r["goal"], r["fall"], r["trail"], r["with"]])


## Her stands of more than a tick while he moves past her, in [param log]: each
## "+start ms" (the time from his passing her if he passed during it), her steps'
## true starts (World.try_move: the tick due, if under a tick late; else the tick taken).
func _stands(log: Array) -> Array[String]:
	var out: Array[String] = []
	if log.is_empty():
		return out
	var t0: int = log[0]["t"]
	var prev_end := maxf(float(t0) - 1.0, float(log[0]["until"]))  # A step under way as the log begins.
	var prev_last: int = log[0]["last"]
	var past_since := -1.0
	var moved_all := true
	for r: Dictionary in log:
		# 555's start wait (K3, kept: a settled companion who lets him get START off is standing) is not a stand here.
		if not r["past"] or not r["moving"] or (r["settled"] and World.distance(r["her"], r["him"]) < Heel.START):
			past_since = -1.0
			moved_all = false
		elif past_since < 0.0:
			past_since = float(r["t"]) - 0.5
			moved_all = true
		var started := int(r["last"]) != prev_last
		if started or r == log.back():
			var at := float(r["t"])
			var start := (prev_end if started and at - prev_end < 1.0 else at)
			var from := maxf(prev_end, past_since)
			if past_since >= 0.0 and moved_all and start - from > 1.001:
				var guarded := false
				for g: Dictionary in log:
					if float(g["t"]) >= from:
						guarded = g["guarded"]
						break
				out.append("+%d %d ms (her %s, his %s)%s" % [int(from) - t0, roundi((start - from) * 100.0), r["her"], r["him"], " guarded" if guarded else ""])
		if started:
			prev_last = int(r["last"])
			prev_end = float(r["until"])
			if r["past"] and r["moving"]:
				past_since = float(r["t"])
	return out


## Each step of hers after he is past her, while he moves: none back toward
## where he set off, none onto a cell he has yet to cross, never on his cell
## nor nearer than CLOSE. The faults, listed.
func _faults(log: Array) -> Array[String]:
	var out: Array[String] = []
	for i in range(1, log.size()):
		var r: Dictionary = log[i]
		var was: Dictionary = log[i - 1]
		if World.distance(r["her"], r["him"]) < Heel.CLOSE:
			out.append("t+%d within CLOSE (%s, %s)" % [i, r["her"], r["him"]])
		if r["her"] == was["her"] or not (was["past"] and was["moving"]):
			continue
		var heading: Vector2 = was["heading"]
		if Vector2(r["her"] - was["her"]).dot(heading) < -0.001:
			out.append("t+%d back %s to %s" % [i, was["her"], r["her"]])
		if (Vector2(r["her"]) - Vector2(r["centre"])).dot(heading) > 0.001:
			out.append("t+%d onto %s, ahead of his centre %s" % [i, r["her"], r["centre"]])
	return out


## Her first step once he is past her, in [param log]: onto the cell he left that tick.
static func _onto_left(log: Array) -> bool:
	for i in range(1, log.size()):
		var r: Dictionary = log[i]
		var was: Dictionary = log[i - 1]
		if r["her"] != was["her"] and was["past"]:
			return r["her"] == was["him"] and r["him"] != was["him"]
	return false


## Through her and on (the probe's front and behind passes): straight, at 2:1
## and on the diagonal, she facing him and facing away, he two cells off and
## jogging through her. After he is past her, while he walks on: no stand over a
## tick (on the diagonal, K2's one), no step back, none onto a cell he has yet
## to cross, never within CLOSE.
func _test_through() -> void:
	print("\n== through her and on: she falls in at once behind him ==")
	var him := _player()
	var pet := _companion()
	for c: Vector2i in STARTS:
		for w: Vector2 in [Vector2(1, 0), Vector2(2, 1), Vector2(1, 1)]:
			for kind: String in ["front", "behind"]:
				var u := Vector2i(w.normalized().round())
				_place(him, pet, c + 2 * u, c)
				pet.facing = u if kind == "front" else -u
				_idle(him, pet, 15)
				var log: Array = []
				_jog(him, pet, -w, 30, log)
				var stands := _stands(log)
				var faults := _faults(log)
				var waited := log.filter(func(r: Dictionary) -> bool: return r["past"] and r["moving"] and r["settled"] and World.distance(r["her"], r["him"]) < Heel.START).size()
				print("  %s %s at %s: 555's start wait with him past her, %d ms" % [kind, w, c, waited * 100])
				var ok := stands.is_empty()
				if w == Vector2(1, 1):
					# K2 on the diagonal (kept): past her, his only footstep ahead of her is
					# the cell level with her he still holds (the one before it is back toward
					# where he set off). One stand, ended by her step onto that cell on the
					# tick he leaves it.
					var onto := _onto_left(log)
					ok = stands.size() <= 1 and onto
					print("  %s %s at %s: K2, beside his line till he leaves the cell level with her: %s, onto it the tick he leaves it %s" % [kind, w, c, stands, onto])
				_check(ok and faults.is_empty(), "%s %s at %s: no stand over a tick once he is past (%s), no step back nor ahead of him (%s)"
					% [kind, w, c, stands, faults])
				if not (ok and faults.is_empty()):
					_dump(log)
				_idle(him, pet, 25)


## The look's D2 shuttle (ui-design's): he from (185,177) to (191,177) and back,
## ten legs, she at (186,177) to start, turned at once and after 0.3 s. Per leg
## her one stand is the stay-put while he comes by (678); once he is past, only
## one while his nearest footstep is the cell she stepped aside from (678's
## bounce, "guarded"), shorter than main's (550 ms a leg on 6f1060b55).
func _test_shuttle() -> void:
	print("\n== the look's shuttle: only the stay-put while he comes by ==")
	var him := _player()
	var pet := _companion()
	for pause: int in [0, 3]:
		var a := Vector2i(185, 177)
		var b := Vector2i(191, 177)
		_place(him, pet, a, Vector2i(186, 177))
		_idle(him, pet, 20)
		var to := b
		var bad: Array[String] = []
		var guarded: Array[String] = []
		for leg in 10:
			var log: Array = []
			var guard := 0
			while him.free_pos.distance_to(Vector2(to)) > 0.35 and guard < 60:
				_jog(him, pet, (Vector2(to) - him.free_pos).normalized(), 1, log)
				guard += 1
			_idle(him, pet, pause, log)
			var found := _stands(log)
			for s: String in found:
				var ms := int(s.split(" ")[1])
				if s.ends_with(" guarded") and ms < 550:
					guarded.append("leg %d: %s" % [leg, s])
				else:
					bad.append("leg %d: %s" % [leg, s])
			if not bad.is_empty() and found.size() > 0:
				_dump(log)
			for f: String in _faults(log):
				bad.append("leg %d: %s" % [leg, f])
			to = a if to == b else b
		print("  (turned after %d ms: %d stands held by 678's bounce guard, each under main's 550 ms: %s)" % [pause * 100, guarded.size(), guarded])
		_check(bad.is_empty(), "turned after %d ms: no stand over a tick once he is past but the bounce guard's, no step back nor ahead of him (%s)" % [pause * 100, bad])
		_idle(him, pet, 25)


## In her fall-in he turns straight back: she lets him by, no swap of cells,
## no bump, and he goes back unhindered.
func _test_turn_back() -> void:
	print("\n== a turn straight back in her fall-in: she lets him by ==")
	var him := _player()
	var pet := _companion()
	for c: Vector2i in STARTS:
		for w: Vector2 in [Vector2(1, 0), Vector2(2, 1)]:
			var u := Vector2i(w.normalized().round())
			_place(him, pet, c + 2 * u, c)
			pet.facing = u
			_idle(him, pet, 15)
			var log: Array = []
			var turned := -1
			for i in 30:
				_jog(him, pet, -w, 1, log)
				if pet.heel.get("_fall_goal") != Heel.NONE and World.tick < pet.step_until:
					turned = i
					break
			_check(turned >= 0, "%s at %s: she falls in behind him (tick %d)" % [w, c, turned])
			var from := him.free_pos
			var back: Array = []
			_jog(him, pet, w, 15, back)
			var swaps := 0
			var stunned := false
			var prev: Dictionary = log.back()
			for r: Dictionary in back:
				if r["her"] == prev["him"] and r["him"] == prev["her"]:
					swaps += 1
				stunned = stunned or r["stunned"]
				prev = r
			var gone := (him.free_pos - from).dot(w.normalized())
			var passed := Heel.ahead_of(pet.tile - him.tile, u) < 0
			if not passed:
				_dump(log.slice(-4) + back)
			_check(swaps == 0 and not stunned and gone >= 4.0 and passed, "%s at %s: turned back, no swap (%d), no bump (%s), he goes %.1f cells on past her (%s)"
				% [w, c, swaps, stunned, gone, passed])
			_idle(him, pet, 25)


## A jog and a stop: she stands within STOP behind him, a true stand. From
## still, 555's start band: she sets off only once he is heel.start off.
func _test_stop() -> void:
	print("\n== a jog and a stop: a true stand; from still she waits for the start band ==")
	var him := _player()
	var pet := _companion()
	var c := STARTS[0]
	for w: Vector2 in [Vector2(1, 0), Vector2(2, 1)]:
		var u := Vector2i(w.normalized().round())
		_place(him, pet, c, c - u)
		_idle(him, pet, 20)
		var log: Array = []
		_jog(him, pet, w, 20, log)
		var still: Array = []
		_idle(him, pet, 8, still)
		var at := pet.tile
		var stood: Array = []
		_idle(him, pet, 20, stood)
		var behind := Heel.ahead_of(pet.tile - him.tile, u) <= 0
		_check(World.distance(pet.tile, him.tile) <= Heel.STOP and behind and stood.all(func(r: Dictionary) -> bool: return r["her"] == at),
			"%s: he stops, she stands within STOP behind him (%s, he at %s) and stays" % [w, pet.tile, him.tile])
		# From still: settled behind him, he walks off; her first step not before he is start off.
		var first := -1
		var log2: Array = []
		for i in 30:
			_jog(him, pet, w, 1, log2)
			if pet.tile != at:
				first = World.distance(at, him.tile)
				break
		_check(first >= pet.heel.start, "%s from still: she sets off with him %d off (start %d)" % [w, first, pet.heel.start])
		_idle(him, pet, 25)


## The fence (the coordinator's term 2): a body on a Heel made as an escort
## makes its own (Resident.HEEL_SCRIPT, no flag of Companion's) follows the
## straight front pass as on main, cell for cell, and never falls in.
func _test_escort() -> void:
	print("\n== the fence: an escort's Heel follows as before ==")
	var him := _player()
	var pet := _companion()
	var c := STARTS[0]
	var u := Vector2i(1, 0)
	pet.stance = Companion.Stance.HOLD
	pet.hold_tile = c + Vector2i(0, 8)
	World._relocate(pet, pet.hold_tile)
	var walker := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "name": "HeelTestWalker", "tile": c + Vector2i(0, 4)}) as Monster
	walker.sight_range = 0
	var heel: Heel = load(Resident.HEEL_SCRIPT).new()
	_place(him, walker, c + 2 * u, c)
	walker.facing = u
	_idle(him, walker, 15, [], heel)
	var log: Array = []
	var fell := false
	var t0 := World.tick
	var steps: Array[String] = []
	var last := walker.last_step_tick
	for i in 30:
		_jog(him, walker, -Vector2(u), 1, log, heel)
		fell = fell or heel.get("_fall_goal") not in [null, Heel.NONE] or heel.get("falls_in") == true
		if walker.last_step_tick != last:
			last = walker.last_step_tick
			steps.append("%d:%d,%d" % [World.tick - t0, walker.tile.x, walker.tile.y])
	var trace := " ".join(steps)
	print("  ESCORT trace: %s" % trace)
	_check(not fell, "its Heel never falls in (no flag of Companion's)")
	_check(trace == ESCORT_ON_MAIN, "its steps as on main, cell for cell (%s; main: %s)" % [trace, ESCORT_ON_MAIN])
	World.despawn(walker)
	pet.stance = Companion.DEFAULT_STANCE
	_place(him, pet, c, c + Vector2i(0, 1))
	_idle(him, pet, 20)
