extends Node
## npc's look at Umbrage's folk as a player standing in the plaza meets them (the coordinator's
## three-worst rule, 2026-11-11). A fresh local world (economy seats its own folk), the player
## in the plaza, a warm-up and one game day; every body read each tick. Local scratch world only.
##   godot --headless --path . --scene tools/look_day.tscn -- --out=<folder>

const TOWN := "wilds/store"
const DAY := 54000
const HOUR := DAY / 24
const MINUTE := 37
const NEAR := 12  # A plaza's screen at the nearest zoom, about.

var _player: Player
var _main: Node
var _last := {}  # id -> {tile, tick, way}
var _gaps := {"straight": [], "diagonal": []}
var _turns := 0
var _steps := 0
var _pauses := 0  # A stop mid-route longer than three steps' time.
var _stand_runs: Array = []  # idle stand lengths in minutes
var _run := {}  # id -> {tile, minutes, idle}
var _near_by_hour := {}
var _idle_by_hour := {}
var _walk_by_hour := {}
var _word_by_hour := {}
var _bad := {"link": 0, "in_building": 0, "doorway": 0, "packed": 0, "wall_face": 0}
var _bad_where := {}
var _bad_who := {}  # what -> {worker_id: true}: counted, never printed
var _people := {}
var _cells := {}  # "x,y" -> steps onto it in the day (terrain's ask; no names or ids)


func _ready() -> void:
	_go.call_deferred()


func _go() -> void:
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	if out.is_empty() or out.begins_with("/var/lib") or out.begins_with("user://"):
		push_error("look_day: --out=<a local folder>")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	World.set_process(false)
	var ports := preload("res://tests/test_ports.gd")
	Net.port = 19733
	Net.companions = false
	Net.map_name = "wilds"
	Net.state_path = ports.scratch_path("look_day_world.json")
	if FileAccess.file_exists(Net.state_path):
		DirAccess.remove_absolute(Net.state_path)
	Net.transcripts_dir = out.path_join("transcripts")
	Net.mind_log_path = out.path_join("mind.log")
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	for entity in World.get_entities():
		if entity is Player and entity.spawned:
			_player = entity
	var store: Vector2i = World.holdings.place(TOWN).get("cell", Vector2i.ZERO)
	World._relocate(_player, _main._nearest_free(store + Vector2i(0, 4)))
	print("LOOK start hour %.2f store %s player %s" % [DayNight.hour(DayNight.now()), store, _player.tile])
	for s in HOUR * 2:
		World.step()
	for s in DAY:
		World.step()
		_tick_read()
		if s % MINUTE == 0:
			_minute_read(store)
		if s % HOUR == 0:
			if _hour() in [3, 10, 15, 22]:
				_dump()
			await get_tree().process_frame
	for id: String in _run.keys():
		_close(id)
	_report()
	var steps_file := FileAccess.open(out.path_join("umbrage_steps.json"), FileAccess.WRITE)
	if steps_file != null:
		steps_file.store_string(JSON.stringify(_cells, "", true))
		steps_file.close()
		print("LOOK cells %d written" % _cells.size())
	Net.state_path = ""
	get_tree().quit(0)


func _hour() -> int:
	return int(DayNight.hour(DayNight.now()))


func _tick_read() -> void:
	for entity in World.townsfolk():
		var body := entity as Resident
		if body == null or not body.spawned:
			continue
		var id := body.worker_id
		var was: Dictionary = _last.get(id, {})
		if was.is_empty():
			_last[id] = {"tile": body.tile, "tick": World.tick, "way": Vector2i.ZERO, "moved": World.tick}
			continue
		if body.tile != was["tile"]:
			var way: Vector2i = body.tile - Vector2i(was["tile"])
			if absi(way.x) <= 1 and absi(way.y) <= 1:
				var gap := World.tick - int(was["moved"])
				var kind := "diagonal" if way.x != 0 and way.y != 0 else "straight"
				if gap < 60:
					(_gaps[kind] as Array).append(gap)
					if gap >= 8:
						_pauses += 1  # A hitch mid-walk: twice a step's time or more, under 6 s.
				_steps += 1
				var cell := "%d,%d" % [body.tile.x, body.tile.y]
				_cells[cell] = int(_cells.get(cell, 0)) + 1  # Terrain's worn paths: steps onto each cell, no names.
				if was["way"] != Vector2i.ZERO and way != was["way"]:
					_turns += 1
			_last[id] = {"tile": body.tile, "tick": World.tick, "way": way, "moved": World.tick}


func _minute_read(store: Vector2i) -> void:
	var h := _hour()
	var bodies: Array = []
	for entity in World.townsfolk():
		var body := entity as Resident
		if body != null and body.spawned:
			bodies.append(body)
	for body: Resident in bodies:
		_people[body.person] = true
		var near := World.distance(body.tile, store) <= NEAR and not Resident.asleep_now(body.worker_id)
		if not near:
			_close_if(body)
			continue
		_near_by_hour[h] = (_near_by_hour.get(h, {}) as Dictionary)
		_near_by_hour[h][body.person] = true
		var walking := not body._route.is_empty() or body.tile != body._goal
		var word := str(body.activity)
		if walking:
			_walk_by_hour[h] = int(_walk_by_hour.get(h, 0)) + 1
		elif word.is_empty():
			_idle_by_hour[h] = int(_idle_by_hour.get(h, 0)) + 1
		else:
			_word_by_hour[h] = int(_word_by_hour.get(h, 0)) + 1
		# Where it stands still.
		if not walking:
			var run: Dictionary = _run.get(body.worker_id, {})
			if not run.is_empty() and run["tile"] == body.tile:
				run["minutes"] += 1
			else:
				_close(body.worker_id)
				_run[body.worker_id] = {"tile": body.tile, "minutes": 1, "idle": word.is_empty()}
			if World.is_link_cell(body.tile):
				_mark("link", body)
			var inside: Dictionary = Companion.building_at(body.tile)
			if not inside.is_empty():
				_mark("in_building", body, str(inside.get("slot", inside.get("use", ""))))
			if body.facing != Vector2i.ZERO and not World.is_walkable(body.tile + body.facing) and word.is_empty():
				_mark("wall_face", body)
			for other: Resident in bodies:
				if other != body and not other.tile == body.tile and World.distance(other.tile, body.tile) <= 1 \
						and other._route.is_empty() and str(body.activity) not in ["talk", "sit_talk", "sit_listen", "listen"]:
					_mark("packed", body)
					break
		else:
			_close(body.worker_id)


func _dump() -> void:
	for entity in World.townsfolk():
		var body := entity as Resident
		if body == null or not body.spawned:
			continue
		var inside: Dictionary = Companion.building_at(body.tile)
		var near := ""
		for other in World.townsfolk():
			if other != body and other.spawned and World.distance(other.tile, body.tile) <= 1:
				near += (other as Resident).person.left(4) + " "
		print("LOOK at %02d: %s (%s) doing=%s act=%s tile=%s in=%s asleep=%s sleeps=%s bed=%s spots=%s beside=%s" % [_hour(), body.person.left(1), body.trade,
			Resident.Doing.keys()[body.doing], body.activity, body.tile, str(inside.get("slot", inside.get("use", "-"))) if not inside.is_empty() else "-",
			Resident.asleep_now(body.worker_id), body.sleeps_now(), body.places.get("bed", "-"), (body.places.get("spots", {}) as Dictionary).keys(), near])


func _mark(what: String, body: Resident, extra := "") -> void:
	_bad[what] = int(_bad[what]) + 1
	(_bad_who.get_or_add(what, {}) as Dictionary)[body.worker_id] = true  # How many residents, not who.
	var key := "%s %s %s" % [what, body.tile, extra]
	_bad_where[key] = int(_bad_where.get(key, 0)) + 1


func _close_if(body: Resident) -> void:
	_close(body.worker_id)


func _close(id: String) -> void:
	var run: Dictionary = _run.get(id, {})
	_run.erase(id)
	if not run.is_empty() and bool(run["idle"]):
		_stand_runs.append(int(run["minutes"]))


func _median(values: Array) -> float:
	if values.is_empty():
		return -1.0
	var s := values.duplicate()
	s.sort()
	return float(s[s.size() / 2])


func _report() -> void:
	print("LOOK people: %s" % [_people.keys().size()])
	for h in range(24):
		var near: Dictionary = _near_by_hour.get(h, {})
		print("LOOK hour %02d: in the plaza %d (%s), minutes walking %d, standing %d, a word %d" % [h, near.size(),
			"/".join(near.keys().map(func(p: String) -> String: return p.left(1))), int(_walk_by_hour.get(h, 0)), int(_idle_by_hour.get(h, 0)), int(_word_by_hour.get(h, 0))])
	_stand_runs.sort()
	var n := _stand_runs.size()
	print("LOOK idle stands in the plaza: %d, median %.0f min, longest %s" % [n, _median(_stand_runs), _stand_runs.slice(maxi(n - 5, 0))])
	print("LOOK steps %d: straight gap median %.0f ticks (%d), diagonal %.0f (%d); turns %d (%.0f%% of steps); hitches mid-walk (8..59 ticks) %d" % [_steps,
		_median(_gaps["straight"]), (_gaps["straight"] as Array).size(), _median(_gaps["diagonal"]), (_gaps["diagonal"] as Array).size(), _turns,
		100.0 * _turns / maxi(_steps, 1), _pauses])
	print("LOOK still on: %s (body-minutes)" % [_bad])
	var who := {}
	for what: String in _bad.keys():
		who[what] = (_bad_who.get(what, {}) as Dictionary).size()
	print("LOOK residents: %s (residents marked at least once)" % [who])
	var keys := _bad_where.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(_bad_where[a]) > int(_bad_where[b]))
	for k: String in keys.slice(0, 15):
		print("LOOK  %s: %d" % [k, _bad_where[k]])
