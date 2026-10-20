extends Node
## The fallen brought back (decision 396): a "return" job at a temple or a
## healer's hut, worked by its priest or medicine man for the rules'
## return.steps, then Main's returned hook; nobody there for give_up and it
## gives up (the old respawn); saved mid-job and finished after; a town's
## standing temple gets its priest, an official paid like the guard; a
## medicine man lives outside any town's purse (no rent, no needs). Then in
## Main, on the test room with a healer's hut put in its holdings: a player
## who dies comes back at the hut with full hp, told who brought them; with
## the medicine man away, at a start tile as before. Reads the repo's levels,
## never the shared overlay.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const TOWN := "rt/store"

var _failures := 0
var _now := 0
var _rules := {}
var _done: Array[Dictionary] = []
var _main: Node


func _ready() -> void:
	World.set_process(false)
	Level.overlay_dir = preload("res://tests/test_ports.gd").scratch("return_test/no_overlay/")
	_rules = Production.read_rules()
	_test_job()
	_test_officials()
	_test_main()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _work() -> Production:
	_now = 0
	_done.clear()
	var stock := Stockpile.new({}, func() -> int: return _now)
	var work := Production.new({}, stock, null, func() -> int: return _now, _rules, func() -> Dictionary: return {})
	work.returned = func(job: Dictionary) -> void: _done.append(job)
	work.add_worker("priest:" + TOWN, "Osric", ["priest"], TOWN, "appointed")
	work.add_workshop(TOWN + ":temple", "priest", TOWN)
	work.assign(TOWN + ":temple", "priest:" + TOWN)
	return work


func _run(work: Production, steps: int) -> void:
	var until := _now + steps
	while _now < until:
		_now += World.WORLD_TICK_STEPS
		work.tick()


func _test_job() -> void:
	print("\n== the return job: worked, given up on, saved ==")
	var steps := int(_rules["return"]["steps"])
	var work := _work()
	_check(work.manned(TOWN + ":temple"), "the temple is manned by its priest")
	_check(work.open_return("nowhere", "p1", "player") == 0, "no return at a workshop that is not there")
	var id := work.open_return(TOWN + ":temple", "p1", "player", "rt/temple@3,3")
	_check(id != 0 and work.job(id)["kind"] == "return", "a return job is opened for a player (#%d)" % id)
	_run(work, steps - World.WORLD_TICK_STEPS)
	_check(_done.is_empty(), "not done before return.steps (%d)" % steps)
	_run(work, World.WORLD_TICK_STEPS)
	_check(_done.size() == 1 and _done[0]["who"] == "p1" and _done[0]["by"] == "Osric" and _done[0]["place"] == "rt/temple@3,3"
		and not _done[0].get("fallback", false), "after return.steps, brought back by Osric at the temple's place")
	_check(work.job(id).is_empty(), "the job is gone once done")

	work = _work()
	work.set_away("priest:" + TOWN, true)
	_check(not work.manned(TOWN + ":temple"), "with the priest away the temple is not manned")
	id = work.open_return(TOWN + ":temple", "c1", "companion")
	_run(work, int(_rules["return"]["give_up"]) - World.WORLD_TICK_STEPS)
	_check(_done.is_empty(), "the job waits for him")
	_run(work, World.WORLD_TICK_STEPS)
	_check(_done.size() == 1 and _done[0]["who"] == "c1" and _done[0].get("fallback", false),
		"nobody there for give_up: given up on, brought back as before")

	work = _work()
	id = work.open_return(TOWN + ":temple", "r1", "resident", "rt/temple@3,3")
	_run(work, World.WORLD_TICK_STEPS)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(work.to_dict()))
	var loaded := Production.new(saved, work.stockpile, null, func() -> int: return _now, _rules, func() -> Dictionary: return {})
	loaded.returned = func(job: Dictionary) -> void: _done.append(job)
	_check(loaded.job(id).get("who") == "r1" and loaded.job(id).get("who_kind") == "resident" and loaded.job(id).get("place") == "rt/temple@3,3",
		"saved mid-job: who, what they are and where, kept")
	_check(int(loaded.workshop(TOWN + ":temple")["job"]) == 0, "a return does not take the temple's own job slot")
	_run(loaded, steps)
	_check(_done.size() == 1 and _done[0]["who"] == "r1", "and finished after loading")
	saved["workshops"].erase(TOWN + ":temple")
	saved["jobs"][str(id)] = loaded.to_dict()["jobs"].get(str(id), JSON.parse_string(JSON.stringify(work.to_dict()))["jobs"][str(id)])
	var gone := Production.new(saved, work.stockpile, null, func() -> int: return _now, _rules, func() -> Dictionary: return {})
	_check(not gone.job(id).is_empty(), "a return whose temple is gone is kept, to give up in time (never lost)")


func _test_officials() -> void:
	print("\n== the priest, the medicine man ==")
	_check(int(_rules["official"]["priest"]["wage"]) == 4 and int(_rules["official"]["priest"]["every"]) == 54000,
		"the priest is an official: 4 a day (528 amended)")
	_check(_rules["buildings"]["temple"]["trade"] == "priest", "the temple is the priest's building")
	var stock := Stockpile.new({}, func() -> int: return _now)
	var work := Production.new({}, stock, null, func() -> int: return _now, _rules, func() -> Dictionary: return {})
	var towns := Towns.new({}, work, _rules, func() -> int: return _now)
	towns.tick()
	_check(work.worker_ids(TOWN).is_empty(), "no temple, no priest")
	var record: Dictionary = towns._town(TOWN)
	record["buildings"]["temple"] = {"kind": "temple", "level": 1, "state": Towns.STANDING, "since": 0, "job": 0}
	towns.tick()
	var priests := work.worker_ids(TOWN).filter(func(id: String) -> bool: return "priest" in work.worker(id)["trades"])
	_check(priests.size() == 1 and work.workshop_of(priests[0]) == TOWN + ":temple" and work.manned(TOWN + ":temple"),
		"the temple stands: a priest comes, seated at it (%s)" % [priests.map(func(id: String) -> String: return work.worker(id)["name"])])
	towns.tick()
	_check(work.worker_ids(TOWN).size() == 1, "and only one")
	work.add_worker("medicine_man:hut", "Ned", ["medicine_man"], "rt/hut", "wilds")
	work.pay("medicine_man:hut", 5)
	_check(work.outside("medicine_man:hut") and not work.outside(priests[0]), "the medicine man lives outside any town's purse; the priest not")
	_now = 3 * 54000
	work.tick()
	_check(int(work.worker("medicine_man:hut")["purse"]) == 5, "he pays no rent")


func _test_main() -> void:
	print("\n== in Main: a player brought back at the healer's hut ==")
	Net.port = preload("res://tests/test_ports.gd").of(17833)
	Net.companions = false
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	_kill_monsters()
	var hut := Vector2i(4, 4)
	var id := "%s/healers_hut@4,4" % World.zone.name
	World.holdings._places[id] = {"id": id, "area": World.zone.name, "key": "healers_hut@4,4", "cell": hut, "name": "the healer's hut",
		"kind": "healers_hut", "radius": 2, "worth": 0, "start": Factions.NOBODY}
	World.holdings._holder[id] = Factions.NOBODY
	_main._seat_healers()
	var keeper := "medicine_man:" + id
	_check(World.production.manned(id) and World.production.worker(keeper)["trades"] == ["medicine_man"],
		"the hut has its medicine man (%s)" % World.production.worker(keeper).get("name", "?"))
	_main._seat_healers()
	_check(World.production.worker_ids(id).size() == 1, "only one")
	var player := _player()
	World.order_move(player, Vector2i(12, 6))
	for i in 60:
		World.step()
	_kill_monsters()
	World.damage(_player(), 999)
	_check(_player() == null, "the player died")
	for i in _main.RESPAWN_TICKS + 1:
		World.step()
	_check(_player() == null, "not back by the old respawn timer")
	for i in int(_rules["return"]["steps"]) + World.WORLD_TICK_STEPS:
		if i % 100 == 0:
			_kill_monsters()  # The test room's imps come back; spawn safety would move the player.
		World.step()
	player = _player()
	_check(player != null and World.distance(player.tile, hut) <= 2 and player.hp == player.max_hp,
		"brought back at the hut, at full hp (at %s)" % (player.tile if player else World.NO_CELL))
	# Nobody to bring them back anywhere (the wilds' temple is a walk away too).
	for each in World.production.worker_ids():
		if World.production.worker(each)["trades"].any(func(t: String) -> bool: return t in ["priest", "medicine_man"]):
			World.production.set_away(each, true)
	World.damage(player, 999)
	for i in _main.RESPAWN_TICKS + 1:
		World.step()
	player = _player()
	_check(player != null and World.distance(player.tile, hut) > 2, "with the medicine man away: the old respawn, at a start tile (at %s)"
		% (player.tile if player else World.NO_CELL))


func _kill_monsters() -> void:
	for entity in World.get_entities():
		if entity is Monster:
			World.damage(entity, 999)


func _player() -> Player:
	for entity in World.get_entities():
		if entity is Player and entity.spawned:
			return entity
	return null


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
