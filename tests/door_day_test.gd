extends Node
## Residents keep off their own building's way in (853 amended (17); perf's folk tour, 11-15: Hob, the
## wilds' healer, stood in his hut's doorway at night, where no click reached him and nobody got in).
## Main._keep_off_doors gives any resident whose work, home or bed is a building's rect that
## building's door cells (Main.door_cells) as places["keep_off"]; a stroll or a stand never picks one.
## Umbrage with a player at the healer's hut, a day and a night (12:00 to 12:00), every body near read
## each game minute: no goal on a keep_off cell (a spot's own cell aside), none on one longer than a
## pass through it, and the healer in his bed inside his own sleep spell (Townsfolk.sleep_spell).

const HUT := "wilds/healers_hut@152,232"
const HUT_RECT := Rect2i(149, 232, 7, 5)
const HOUR := 2250
const MINUTE := 37
const FROM_HOUR := 12
const HOURS := 24
## The most game minutes a body may be read on a keep_off cell in a row: a walk out passes through.
const PASS_MINUTES := 2

var _main: Node
var _failed := 0
var _on_door := {}  # worker id -> samples in a row on a keep_off cell
var _told := {}  # "who|what" -> true: each fault said once
var _healer := {"abed": 0, "spell": 0, "awake": 0, "samples": 0}
var _doors := {}  # rect -> its door cells (Main.door_cells), the area's buildings


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	World.set_process(false)
	var ports := preload("res://tests/test_ports.gd")
	Net.port = ports.of(17986)
	Net.companions = false
	Net.map_name = "wilds"
	Net.lawspeaker = "off"
	Net.state_path = ports.scratch_path("door_day_world.json")
	if FileAccess.file_exists(Net.state_path):
		DirAccess.remove_absolute(Net.state_path)
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Player = null
	for entity in World.get_entities():
		if entity is Player and entity.spawned:
			player = entity
	World._relocate(player, _main._nearest_free(Vector2i(152, 228)))
	print("== residents keep off their own building's way in (853 amended (17)): %d hours from %d:00, a player at the healer's hut ==" % [HOURS, FROM_HOUR])
	while int(DayNight.hour(DayNight.now())) != FROM_HOUR:
		World.step()
	for s in Main.RESIDENT_SYNC_TICKS * 3:  # Main's sync gives the bodies near the player theirs.
		World.step()
	_test_marks()
	var t0 := Time.get_ticks_msec()
	for s in HOURS * HOUR:
		World.step()
		if s % MINUTE == 0:
			_sample()
		if s % HOUR == 0:
			await get_tree().process_frame
	_check(_healer["samples"] > 0, "the healer was read (%d game minutes)" % _healer["samples"])
	_check(_healer["abed"] > 0, "the healer lies in his own bed inside his sleep spell (%d of %d minutes in the spell)" % [_healer["abed"], _healer["spell"]])
	_check(_healer["awake"] > 0, "the healer is up outside his spell (%d minutes)" % _healer["awake"])
	print("  %d game hours in %.0f s" % [HOURS, (Time.get_ticks_msec() - t0) / 1000.0])
	print("RESULT: %s (%d failed)" % ["PASS" if _failed == 0 else "FAIL", _failed])
	Net.state_path = ""
	get_tree().quit(0 if _failed == 0 else 1)


## The marks as Main's sync sets them: the healer's hut's door and front, every resident whose work, home
## or bed is a building's rect carrying that building's door cells, and no spot on a building's way in.
func _test_marks() -> void:
	var area: Dictionary = _main._world_map.areas.get(World.zone.name, {})
	for building: Variant in area.get("buildings", []):
		if building is Dictionary and (building as Dictionary).get("rect") is Rect2i:
			_doors[building["rect"]] = Main.door_cells(building)
	var doors := _doors
	_check(doors.get(HUT_RECT, []) == [Vector2i(152, 232), Vector2i(152, 231)],
		"the turf house's way in: its door and the cell before it (%s)" % [doors.get(HUT_RECT, "no such building")])
	var healer := _healer_body()
	_check(healer != null and (healer.places.get("keep_off", []) as Array).has(Vector2i(152, 232)) and (healer.places.get("keep_off", []) as Array).has(Vector2i(152, 231)),
		"the healer keeps off his hut's door and front (%s)" % [healer.places.get("keep_off") if healer != null else "no body"])
	var marked := 0
	for entity in World.townsfolk():
		var body := entity as Resident
		if body == null:
			continue
		var want := _ways_in(body)
		var have: Array = body.places.get("keep_off", [])
		var ok := want.all(func(c: Vector2i) -> bool: return have.has(c)) and have.size() == want.size()
		marked += 1 if not want.is_empty() else 0
		if not ok:
			_check(false, "%s keeps off its own buildings' ways in %s (has %s)" % [body.person, want, have])
	_check(marked > 0, "residents with a building of their own are marked (%d)" % marked)
	var on_door: Array = []
	for spot: Variant in area.get("spots", []):
		if not spot is Dictionary:
			continue
		for rect: Variant in doors:
			if (doors[rect] as Array).has((spot as Dictionary).get("cell")):
				on_door.append("%s %s at %s" % [spot.get("use", ""), spot.get("town", ""), spot["cell"]])
	_check(on_door.is_empty(), "no spot stands on a building's way in (%s)" % [on_door])


## The door cells of [param body]'s own buildings (its work, home or bed rect), read here, not from its marks.
func _ways_in(body: Resident) -> Array[Vector2i]:
	var want: Array[Vector2i] = []
	for use: String in ["work", "home", "bed"]:
		var rect: Variant = body.places.get(use)
		if rect is Rect2i and _doors.has(rect):
			for cell: Vector2i in _doors[rect]:
				if not want.has(cell):
					want.append(cell)
	return want


func _healer_body() -> Resident:
	for entity in World.townsfolk():
		var body := entity as Resident
		if body != null and body.town == HUT:
			return body
	return null


func _sample() -> void:
	var hour := DayNight.hour(DayNight.now())
	for entity in World.townsfolk():
		var body := entity as Resident
		if body == null or not body.spawned or body._far():
			continue
		var keep := _ways_in(body)
		if keep.is_empty():
			continue
		if keep.has(body._goal) and body._goal != body._spot.get("cell", Level.NO_DOOR):
			_say(body, "goal", "%s set out for its own way in, %s, at %.2f (%s, spot %s)" % [body.person, body._goal, hour, Resident.Doing.keys()[body.doing], body._spot])
		var run := int(_on_door.get(body.worker_id, 0)) + 1 if keep.has(body.tile) else 0
		_on_door[body.worker_id] = run
		if run > PASS_MINUTES:
			_say(body, "stand", "%s stood on its own way in, %s, %d game minutes to %.2f (%s, goal %s, route %d)" % [
				body.person, body.tile, run, hour, Resident.Doing.keys()[body.doing], body._goal, body._route.size()])
		if body.town == HUT:
			_healer["samples"] += 1
			if Resident.asleep_now(body.worker_id):
				_healer["spell"] += 1
				_healer["abed"] += 1 if body.activity == "sleep" and body.tile == body._bed() else 0
			elif body.activity != "sleep":
				_healer["awake"] += 1


func _say(body: Resident, what: String, label: String) -> void:
	if _told.has(body.worker_id + "|" + what):
		return
	_told[body.worker_id + "|" + what] = true
	_check(false, label)


func _check(ok: bool, label: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + label)
	if not ok:
		_failed += 1
