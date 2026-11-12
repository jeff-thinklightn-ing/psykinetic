extends Node
## npc's look at Umbrage's folk as a player standing in the plaza meets them (the coordinator's
## three-worst rule, 2026-11-11). A fresh local world (economy seats its own folk), the player
## in the plaza, a warm-up and one game day; every body read each tick. Local scratch world only.
##   godot --headless --path . --scene tools/look_day.tscn -- --out=<folder> [--mug-spots] [--temple-spots] [--seed=N]
## --temple-spots lays maps' four temple pews (875's ruling, in memory only). --seed=N steps N whole
## days before the warm-up (the night picks and visitors are drawn by the day) and seeds the global draw.
## A body under the temple's roof is counted on its own line, apart from the plaza.
## --mug-spots lays maps' ten Mughouse spots (875's, in memory only) before the day; after the
## day the player walks into the Mughouse from 20:00 to 03:00 and its floor is read each minute.

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
var _stood := {}  # worker id -> the stand it is in now: {since, tile, goal, wander, stand_for, retry, doing, addressing, activity}
var _minutes_read := 0  # minutes read so far: a run seen at the first is one begun before the watch
var _seen_off := {}  # worker id -> true once seen off a stand: a stand begun before the watch is not one counted
var _stand_ends := {}  # why a stand under SHORT_TICKS ended -> count
var _stand_end_lines: Array[String] = []
const SHORT_TICKS := 450  # 12 game minutes (Resident.STROLL_TICKS)
var _stroll_stands: Array = []  # stands ended by its own next pick in the same doing (853 amended (10)), minutes
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
var _packed_by := {}  # "kind doing hour" -> body-minutes packed (kind: resident, visitor, vendor; no names)
var _temple_by_hour := {}  # hour -> {person initial key: true} under the temple's roof
var _temple_minutes := {}  # hour -> {"sat or a word": n, "standing": n, "walking": n}
var _open_most := {}  # hour -> the most standing still at once in the open plaza (no word, not walking)
var _inn_by_hour := {}  # hour -> the most the town sends into its shell inn (875's Main._inn_goers)
var _watch := {}  # worker id -> 100 ticks of an off-bed sleeper watched from its dump (what holds its next step)
const WATCH_TICKS := 100
var _mug := {}  # hour -> {bodies (most at once), shared, packed, on_spot, minutes}
## Maps' ten Mughouse spots (875), laid by --mug-spots: [cell, face, pose, use].
## Maps' four temple pews (875's ruling): [cell, face].
const TEMPLE_SPOTS := [[Vector2i(193, 200), Vector2i(194, 200)], [Vector2i(195, 200), Vector2i(196, 200)],
	[Vector2i(193, 203), Vector2i(194, 203)], [Vector2i(195, 203), Vector2i(196, 203)]]
const MUG_SPOTS := [[Vector2i(8, 4), Vector2i(8, 3), "stand", "inn"], [Vector2i(10, 4), Vector2i(10, 3), "stand", "inn"],
	[Vector2i(1, 6), Vector2i(0, 6), "sit", "inn"], [Vector2i(1, 7), Vector2i(0, 7), "sit", "inn"], [Vector2i(1, 5), Vector2i(0, 6), "sit", "inn"],
	[Vector2i(1, 8), Vector2i(0, 7), "sit", "inn"], [Vector2i(2, 5), Vector2i(1, 6), "sit", "inn"], [Vector2i(2, 8), Vector2i(1, 7), "sit", "inn"],
	[Vector2i(7, 10), Vector2i(8, 10), "sit", "talk"], [Vector2i(10, 11), Vector2i(9, 11), "sit", "talk"]]


func _ready() -> void:
	_go.call_deferred()


func _go() -> void:
	var out := ""
	var mug_spots := false
	var temple_spots := false
	var days_first := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		mug_spots = mug_spots or arg == "--mug-spots"
		temple_spots = temple_spots or arg == "--temple-spots"
		if arg.begins_with("--seed="):
			days_first = maxi(int(arg.trim_prefix("--seed=")), 0)
	seed(days_first)
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
	if mug_spots:
		var laid: Array = []
		for each: Array in MUG_SPOTS:
			laid.append({"use": each[3], "cell": each[0], "face": each[1], "pose": each[2], "town": TOWN.get_slice("/", 1), "trade": "",
				"pair": "mug_east" if each[3] == "talk" else ""})
		(_main._zone_level("umbrage_tavern") as Dictionary)["spots"] = laid
		print("LOOK mug spots laid: %d" % laid.size())
	if temple_spots:
		var wilds: Dictionary = _main._world_map.areas.get("wilds", {})
		var spots: Array = wilds.get("spots", [])
		for each: Array in TEMPLE_SPOTS:
			spots.append({"use": "temple", "cell": each[0], "face": each[1], "pose": "sit", "town": TOWN.get_slice("/", 1), "trade": "", "pair": ""})
		wilds["spots"] = spots
		print("LOOK temple spots laid: %d (the wilds' spots now %d)" % [TEMPLE_SPOTS.size(), spots.size()])
	for d in days_first:
		for s in DAY:
			World.step()
			if s % HOUR == 0:
				await get_tree().process_frame
	print("LOOK seed %d: %d days stepped first" % [days_first, days_first])
	print("LOOK start hour %.2f store %s player %s" % [DayNight.hour(DayNight.now()), store, _player.tile])
	for s in HOUR * 2:
		World.step()
	for s in DAY:
		World.step()
		_tick_read()
		if not _watch.is_empty():
			_watch_read()
		if s % MINUTE == 0:
			_minute_read(store)
		if s % HOUR == 0:
			if _hour() in [3, 10, 15, 22]:
				_dump()
			await get_tree().process_frame
	for id: String in _run.keys():
		_close(id)
	_report()
	await _mug_night()
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
		_stand_read(body)
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
	_minutes_read += 1
	var h := _hour()
	if _main.has_method("_inn_goers"):
		_inn_by_hour[h] = maxi(int(_inn_by_hour.get(h, 0)), (_main._inn_goers(TOWN, DayNight.now()) as Array).size())
	var bodies: Array = []
	for entity in World.townsfolk():
		var body := entity as Resident
		if body != null and body.spawned:
			bodies.append(body)
	var standing_now := 0
	for body: Resident in bodies:
		_people[body.person] = true
		var near := World.distance(body.tile, store) <= NEAR and not Resident.asleep_now(body.worker_id)
		if not near:
			_close_if(body)
			continue
		var walking := not body._route.is_empty() or body.tile != body._goal
		var word := str(body.activity)
		var roof: Dictionary = Companion.building_at(body.tile)
		if not roof.is_empty() and _main._is_temple(roof):
			# Under the temple's roof (875's ruling): its own line, not the plaza's.
			(_temple_by_hour.get_or_add(h, {}) as Dictionary)[body.person] = true
			var kind := "walking" if walking else "standing" if word.is_empty() else "sat or a word"
			var row: Dictionary = _temple_minutes.get_or_add(h, {"sat or a word": 0, "standing": 0, "walking": 0})
			row[kind] = int(row[kind]) + 1
			_close_if(body)
			continue
		_near_by_hour[h] = (_near_by_hour.get(h, {}) as Dictionary)
		_near_by_hour[h][body.person] = true
		if not walking and word.is_empty():
			standing_now += 1
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
				_run[body.worker_id] = {"tile": body.tile, "minutes": 1, "idle": word.is_empty(), "doing": body.doing,
					"seen_start": _minutes_read > 1}
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
			_close(body.worker_id, body.doing)  # Walking off: its own next pick when the doing is the stand's.
	_open_most[h] = maxi(int(_open_most.get(h, 0)), standing_now)


## Each tick, [param body]'s stand: begun when it stands on its goal with no route; ended when its goal
## changes or it is off it. A stand under SHORT_TICKS is listed with why it ended.
func _stand_read(body: Resident) -> void:
	var id := body.worker_id
	if str(body.activity).begins_with("carry"):
		_stood.erase(id)  # A carrier on its way (the coordinator: carry_log paced two cells), not a stand.
		return
	var on := body._route.is_empty() and body.tile == body._goal
	var was: Dictionary = _stood.get(id, {})
	if not was.is_empty():
		var moved: bool = body.tile != was["tile"]
		var regoaled: bool = body._goal != was["goal"]
		if moved or regoaled:
			_stood.erase(id)
			var stood := World.tick - int(was["since"])
			if stood < SHORT_TICKS:
				var why := "other"
				var wander := int(was["wander"])
				if moved and not regoaled:
					why = "moved off its goal (pushed, swapped or shifted)"
				elif not body.task.is_empty() and body._goal == body.task.get("cell"):
					why = "its task's cell"
				elif body.doing != was["doing"]:
					why = "a new stint (%s to %s)" % [Resident.Doing.keys()[was["doing"]], Resident.Doing.keys()[body.doing]]
				elif int(was["retry"]) >= 0 and World.tick >= int(was["retry"]):
					why = "a retry (its way had been shut)"
				elif not str(was["addressing"]).is_empty() or not body.addressing.is_empty():
					why = "spoken to or hailing"
				elif wander >= (1 << 59):
					why = "re-picked before its stand began"
				elif World.tick >= wander:
					why = "its stroll due"
				elif body._goal == body.tile:
					why = "its goal set to where it stands (a way shut)"
				else:
					why = "re-picked early (%s)" % ("a seat or spot" if not body._spot.is_empty() else "the room rule or stuck")
				_stand_ends[why] = int(_stand_ends.get(why, 0)) + 1
				if _stand_end_lines.size() < 30:
					var drawn := wander - int(was["since"]) if wander < (1 << 59) else int(was["stand_for"])
					_stand_end_lines.append("LOOK short stand at %02d: %s %s stood %d ticks (drawn %d) at %s, %s; then goal %s, activity \"%s\" -> \"%s\"" % [
						_hour(), body.person.left(1), Resident.Doing.keys()[was["doing"]], stood, drawn, was["tile"], why, body._goal,
						was["activity"], body.activity])
	if not on:
		_seen_off[id] = true
	if on and not _stood.has(id) and _seen_off.has(id):
		var stand_for: Variant = body.get("_stand_for")
		_stood[id] = {"since": World.tick, "tile": body.tile, "goal": body._goal, "wander": body._wander_at,
			"stand_for": int(stand_for) if stand_for != null else 0, "retry": body._retry_at, "doing": body.doing,
			"addressing": body.addressing, "activity": body.activity}
	elif on and _stood.has(id):  # (A stand begun before the watch has no entry.)
		# Its clocks as they stand now (853 amended (10) starts _wander_at the tick after it arrives).
		(_stood[id] as Dictionary)["wander"] = body._wander_at
		(_stood[id] as Dictionary)["retry"] = body._retry_at


func _dump() -> void:
	for entity in World.townsfolk():
		var body := entity as Resident
		if body == null or not body.spawned:
			continue
		if body.sleeps_now() and body.activity != "sleep" and body.places.get("bed") is Rect2i:
			# Asleep off its bed (Rolf on his feet at (180, 207), 875): why. No names.
			var bed: Vector2i = body._bed()
			var way := World.find_path(body.tile, bed, false, null, Resident.RESIDENT_SEARCH_TILES, false, {}, true, World.PATH_FIRE_EXTRA,
				Resident.RESIDENT_BODIES_WITHIN)
			var open := World.find_path(body.tile, bed, false, null, Resident.RESIDENT_SEARCH_TILES)
			var lines: Array[String] = []
			lines.append("LOOK off its bed at %02d: %s at %s, doing %s, goal %s, bed %s (walkable %s, free %s), route %d, retry in %d, its path %d, with every body blocking %d, sheltering %s, far %s" % [
				_hour(), body.person.left(1), body.tile, Resident.Doing.keys()[body.doing], body._goal, bed, World.is_walkable(bed), World.is_free(bed), body._route.size(),
				body._retry_at - World.tick, way.size(), open.size(), body.sheltering, body._far()])
			# The cause seen, not only read (the coordinator, 875): the route's first cell and the links on its way.
			var first: Vector2i = body._route[0] if not body._route.is_empty() else Vector2i(-1, -1)
			lines.append("LOOK off its bed at %02d: %s's next cell %s, a link's %s; link cells on its path %s, on its route %s" % [
				_hour(), body.person.left(1), first, World.is_link_cell(first),
				way.filter(func(cell: Vector2i) -> bool: return World.is_link_cell(cell)),
				body._route.filter(func(cell: Vector2i) -> bool: return World.is_link_cell(cell))])
			_holds(body, first, lines)
		var inside: Dictionary = Companion.building_at(body.tile)
		var near := ""
		for other in World.townsfolk():
			if other != body and other.spawned and World.distance(other.tile, body.tile) <= 1:
				near += (other as Resident).person.left(4) + " "
		print("LOOK at %02d: %s (%s) doing=%s act=%s tile=%s in=%s asleep=%s sleeps=%s bed=%s spots=%s beside=%s" % [_hour(), body.person.left(1), body.trade,
			Resident.Doing.keys()[body.doing], body.activity, body.tile, str(inside.get("slot", inside.get("use", "-"))) if not inside.is_empty() else "-",
			Resident.asleep_now(body.worker_id), body.sleeps_now(), body.places.get("bed", "-"), (body.places.get("spots", {}) as Dictionary).keys(), near])


## What holds [param body]'s step onto [param next] (Rolf asleep on his feet with a free 17-cell route,
## the coordinator's list): who or what holds the cell, the terrain and a door across the step, a brace,
## its clocks against the tick, its tries, a stun, a drawn bow; then WATCH_TICKS of watching it.
func _holds(body: Resident, next: Vector2i, lines: Array[String]) -> void:
	var way := next - body.tile
	var who: Variant = World._occupancy.get(next)
	var held := "nobody"
	if who is Resident:
		held = "a resident (%s, %s)" % [(who as Resident).person.left(1), Resident.Doing.keys()[(who as Resident).doing]]
	elif who is Player:
		held = "a player"
	elif who is GridEntity:
		held = "a %s" % (who as GridEntity).get_class() if (who as GridEntity).get_script() == null else "a %s" % str((who as GridEntity).get_script().resource_path.get_file())
	if next == Vector2i(-1, -1):
		held = "no route"
	lines.append("LOOK holds at %02d: %s's step %s by %s: adjacent %s, walkable %s, free %s, held by %s, terrain blocks %s, a shut door %s, a brace %s; next_move in %s, rise in %s, stuck %d, stunned %s, raised \"%s\", spawned %s" % [
		_hour(), body.person.left(1), next, way, way in World.DIRECTIONS, World.is_walkable(next), World.is_free(next), held,
		World._terrain_blocks_step(body.tile, way, true) if way in World.DIRECTIONS else "-",
		World._closed_door_across(body.tile, way) != null if way in World.DIRECTIONS else "-",
		World._meets_brace(body, next, way) if way in World.DIRECTIONS else "-",
		"%.1f" % (body.next_move_tick - World.tick), body._rise_until - World.tick, body._stuck, World.is_stunned(body), body.raised, body.spawned])
	_watch[body.worker_id] = {"body": body, "from": body.tile, "start": World.tick, "tiles": {body.tile: true}, "stuck_most": body._stuck,
		"route_least": body._route.size(), "route_most": body._route.size(), "repaths": 0, "route_was": body._route.size(), "goals": {body._goal: true}, "hour": _hour(),
		"lines": lines, "abed": -1}


## Each tick of a watched sleeper: where it stood, its tries (_stuck), its route (popped on a step,
## cleared and found again after STUCK_TRIES), its goals; after WATCH_TICKS one line, and it is let go.
func _watch_read() -> void:
	for id: String in _watch.keys():
		var w: Dictionary = _watch[id]
		var body: Resident = w["body"]
		if not is_instance_valid(body) or not body.spawned:
			print("LOOK watched at %02d: %s gone after %d ticks" % [int(w["hour"]), id.left(0) + "a body", World.tick - int(w["start"])])
			_watch.erase(id)
			continue
		(w["tiles"] as Dictionary)[body.tile] = true
		(w["goals"] as Dictionary)[body._goal] = true
		w["stuck_most"] = maxi(int(w["stuck_most"]), body._stuck)
		var size := body._route.size()
		if size > int(w["route_was"]) + 1:
			w["repaths"] = int(w["repaths"]) + 1
		w["route_was"] = size
		w["route_least"] = mini(int(w["route_least"]), size)
		w["route_most"] = maxi(int(w["route_most"]), size)
		if int(w["abed"]) < 0 and body.activity == "sleep":
			w["abed"] = World.tick - int(w["start"])
		if World.tick - int(w["start"]) >= WATCH_TICKS and body.activity == "sleep":
			# On its way, not stuck (the coordinator: the 03:00 dump caught Rolf mid-walk): one line, no alarm.
			print("LOOK on its way at %02d: %s from %s abed in %d ticks (%d cells)" % [int(w["hour"]), body.person.left(1), w["from"],
				int(w["abed"]), (w["tiles"] as Dictionary).size()])
			_watch.erase(id)
			continue
		if World.tick - int(w["start"]) >= WATCH_TICKS:
			for line: String in w["lines"]:
				print(line + " (still off its bed after %d ticks)" % WATCH_TICKS)
			print("LOOK watched at %02d: %s from %s over %d ticks: now at %s, %d cells stood on, tries most %d, route %d..%d, found again %d times, goals %s, activity \"%s\", next_move in %.1f" % [
				int(w["hour"]), body.person.left(1), w["from"], WATCH_TICKS, body.tile, (w["tiles"] as Dictionary).size(), int(w["stuck_most"]),
				int(w["route_least"]), int(w["route_most"]), int(w["repaths"]), (w["goals"] as Dictionary).keys(), body.activity,
				body.next_move_tick - World.tick])
			_watch.erase(id)


func _mark(what: String, body: Resident, extra := "") -> void:
	_bad[what] = int(_bad[what]) + 1
	if what == "packed":
		var kind := "visitor" if body.worker_id.begins_with(Offers.VISITOR) else "vendor" if body.worker_id.begins_with(Offers.VENDOR) else "resident"
		var key_by := "%s %s %02d" % [kind, Resident.Doing.keys()[body.doing], _hour()]
		_packed_by[key_by] = int(_packed_by.get(key_by, 0)) + 1
	(_bad_who.get_or_add(what, {}) as Dictionary)[body.worker_id] = true  # How many residents, not who.
	var key := "%s %s %s" % [what, body.tile, extra]
	_bad_where[key] = int(_bad_where.get(key, 0)) + 1


func _close_if(body: Resident) -> void:
	_close(body.worker_id)


func _close(id: String, walked_off_doing := -1) -> void:
	var run: Dictionary = _run.get(id, {})
	_run.erase(id)
	if not run.is_empty() and bool(run["idle"]):
		_stand_runs.append(int(run["minutes"]))
		if walked_off_doing >= 0 and int(run.get("doing", -1)) == walked_off_doing and bool(run.get("seen_start", true)):
			_stroll_stands.append(int(run["minutes"]))


func _median(values: Array) -> float:
	if values.is_empty():
		return -1.0
	var s := values.duplicate()
	s.sort()
	return float(s[s.size() / 2])


## The Mughouse at night (875): the player walks in at 20:00 and stays to 03:00; its floor read each
## minute: the most bodies at once (the taverner too), body-minutes two share a cell, stand beside
## another standing still, and stand on one of its spots.
func _mug_night() -> void:
	for s in DAY:
		if _hour() == 20:
			break
		World.step()
		if s % HOUR == 0:
			await get_tree().process_frame
	if not _main.travel(Net.local_id, "umbrage_tavern", "from_wilds"):
		print("LOOK mug: could not walk in")
		return
	var spots := {}
	for spot: Variant in (_main._zone_level("umbrage_tavern") as Dictionary).get("spots", []):
		if spot is Dictionary:
			spots[spot.get("cell")] = true
	for s in HOUR * 7:
		World.step()
		if s % MINUTE == 0:
			var h := _hour()
			var row: Dictionary = _mug.get_or_add(h, {"bodies": 0, "shared": 0, "packed": 0, "on_spot": 0, "minutes": 0})
			var bodies: Array = World.townsfolk().filter(func(body: GridEntity) -> bool: return body.spawned)
			row["bodies"] = maxi(int(row["bodies"]), bodies.size())
			row["minutes"] = int(row["minutes"]) + 1
			for body: Resident in bodies:
				var still := body._route.is_empty() and body.tile == body._goal
				if spots.has(body.tile) and still:
					row["on_spot"] = int(row["on_spot"]) + 1
				for other: Resident in bodies:
					if other == body:
						continue
					if other.tile == body.tile:
						row["shared"] = int(row["shared"]) + 1
						break
					if still and other._route.is_empty() and World.distance(other.tile, body.tile) <= 1 and not spots.has(body.tile):
						row["packed"] = int(row["packed"]) + 1
						break
		if s % HOUR == 0:
			await get_tree().process_frame
	for h: int in [20, 21, 22, 23, 0, 1, 2]:
		var row: Dictionary = _mug.get(h, {})
		print("LOOK mug %02d: bodies %d at most, body-minutes sharing a cell %d, beside another off a spot %d, on a spot %d (of %d minutes)" % [h,
			int(row.get("bodies", 0)), int(row.get("shared", 0)), int(row.get("packed", 0)), int(row.get("on_spot", 0)), int(row.get("minutes", 0))])


func _report() -> void:
	print("LOOK people: %s" % [_people.keys().size()])
	if _main.has_method("_inn_goers"):
		print("LOOK inn by hour (the most going into the Mughouse): %s" % [_inn_by_hour])
	for h in range(24):
		var near: Dictionary = _near_by_hour.get(h, {})
		print("LOOK hour %02d: in the plaza %d (%s), minutes walking %d, standing %d, a word %d; most standing at once %d" % [h, near.size(),
			"/".join(near.keys().map(func(p: String) -> String: return p.left(1))), int(_walk_by_hour.get(h, 0)), int(_idle_by_hour.get(h, 0)), int(_word_by_hour.get(h, 0)),
			int(_open_most.get(h, 0))])
		var temple: Dictionary = _temple_by_hour.get(h, {})
		if not temple.is_empty():
			print("LOOK temple %02d: under its roof %d (%s), minutes %s" % [h, temple.size(), "/".join(temple.keys().map(func(p: String) -> String: return p.left(1))),
				_temple_minutes.get(h, {})])
	_stand_runs.sort()
	var n := _stand_runs.size()
	print("LOOK idle stands in the plaza: %d, median %.0f min, longest %s" % [n, _median(_stand_runs), _stand_runs.slice(maxi(n - 5, 0))])
	# 853 amended (10)'s measure: the stands a body ends itself by walking off in the same doing (a stroll's
	# next pick), not those an hour's stint cut; under 12 game minutes (STROLL_TICKS, playtest's 45 s) is short.
	_stroll_stands.sort()
	var short := _stroll_stands.filter(func(m: int) -> bool: return m < 12)
	print("LOOK short stands (under %d ticks) by what ended them: %s" % [SHORT_TICKS, _stand_ends])
	for line: String in _stand_end_lines:
		print(line)
	print("LOOK stroll stands (ended by its own next pick): %d, under 12 min %d, under 6 min %d, median %.0f min, shortest %s" % [
		_stroll_stands.size(), short.size(), _stroll_stands.filter(func(m: int) -> bool: return m < 6).size(), _median(_stroll_stands),
		_stroll_stands.slice(0, mini(8, _stroll_stands.size()))])
	print("LOOK steps %d: straight gap median %.0f ticks (%d), diagonal %.0f (%d); turns %d (%.0f%% of steps); hitches mid-walk (8..59 ticks) %d" % [_steps,
		_median(_gaps["straight"]), (_gaps["straight"] as Array).size(), _median(_gaps["diagonal"]), (_gaps["diagonal"] as Array).size(), _turns,
		100.0 * _turns / maxi(_steps, 1), _pauses])
	print("LOOK still on: %s (body-minutes)" % [_bad])
	var night_packed := 0
	for k: String in _packed_by:
		var hour := int(k.get_slice(" ", 2))
		if hour >= 20 or hour < 5:
			night_packed += int(_packed_by[k])
	print("LOOK packed totals: night 20-05 %d, the day %d (body-minutes; the day's WORK is noise until work spots are laid)" % [night_packed, int(_bad["packed"])])
	var by := _packed_by.keys()
	by.sort_custom(func(a: String, b: String) -> bool: return int(_packed_by[a]) > int(_packed_by[b]))
	print("LOOK packed by kind, doing, hour: %s" % [", ".join(by.slice(0, 20).map(func(k: String) -> String: return "%s: %d" % [k, _packed_by[k]]))])
	var who := {}
	for what: String in _bad.keys():
		who[what] = (_bad_who.get(what, {}) as Dictionary).size()
	print("LOOK residents: %s (residents marked at least once)" % [who])
	var keys := _bad_where.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(_bad_where[a]) > int(_bad_where[b]))
	for k: String in keys.slice(0, 15):
		print("LOOK  %s: %d" % [k, _bad_where[k]])
