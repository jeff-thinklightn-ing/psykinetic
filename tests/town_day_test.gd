extends Node
## Townsfolk keep moving (853; Jeff 2026-11-10: "townspeople frozen staring at the wall all day"):
## the wilds town as town_soak sets it up (its folk), a player in the square, run through the
## waking day (06:00 to 22:00), every resident body within sight of a player read each game minute.
## No awake body stands on one cell and facing longer than STAY_MINUTES with no clip but the stand,
## and none stands idle facing shut ground longer than SHUT_MINUTES. A body at a task's work, or at its
## work spot showing a trade the client draws, in a pose of a spot, asleep, sick, hiding, led or
## addressing a player is not standing idle. At every tenth sample, no body stands beside its goal while
## another that chose that cell too stands on it, two samples running (853 amended (16)). Between 12:00 and 14:00
## someone sits at the square's fire facing it, and before 17:00 never more than Resident.FIRE_SITTERS hold its seats
## (853 amended (18)).

const TOWN := "wilds/store"
const HOUR := 2250
const MINUTE := 37
## The longest an awake body may stand idle on one cell (game minutes): a stroll comes every 12 to 32.
const STAY_MINUTES := 35
## The longest an idle body may face shut ground (game minutes).
const SHUT_MINUTES := 3
const FROM_HOUR := 6
const HOURS := 16
const FOLK := [["smith_1", "Odo", "smith"], ["cook_1", "Mags", "cook"], ["carp_1", "Pell", "carpenter"],
	["hunt_1", "Hob", "hunter"], ["tan_1", "Hew", "tanner"], ["farm_1", "Tam", "farmer"],
	["hand_1", "Ash", "hauler"], ["hand_2", "Bea", "hauler"], ["guard_1", "Gar", "guard"], ["hand_3", "Nix", "hauler"]]

var _main: Node
var _failed := 0
var _runs := {}  # worker id -> {tile, facing, since, shut_since}
var _worst := {}  # person -> the longest idle stay seen (minutes)
## 853 amended (16): every TAKEN_EVERY samples (ten game minutes), each body beside its goal while another
## that chose that cell too stands on it; two such samples running is a fail (Pell beside Nix's well spot).
const TAKEN_EVERY := 10
var _samples := 0
var _taken := {}  # worker id -> the ten-minute samples running it was found so
var _taken_seen := 0
var _keeper := {"missing": [], "astray": [], "cells": {}, "doings": {}}  # 333 amended (4): Rolf, sample by sample
## 853 amended (18): the square's fire by day, sample by sample: who sat at it at noon, the most holding its seats
## at once before the evening, and any sitter not facing it.
const FIRE_NOON := Vector2(12.0, 14.0)
const FIRE_DAY_END := 17.0
var _fire := {"noon": [], "most": 0, "most_at": "", "askew": []}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	World.set_process(false)
	var ports := preload("res://tests/test_ports.gd")
	Net.port = preload("res://tests/test_ports.gd").of(17944)
	Net.companions = false
	Net.map_name = "wilds"
	Net.lawspeaker = "off"
	Net.state_path = ports.scratch_path("town_day_world.json")
	if FileAccess.file_exists(Net.state_path):
		DirAccess.remove_absolute(Net.state_path)
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	for each: Array in FOLK:
		World.towns.note_rescue(TOWN, each[0], each[1], each[2])
	await get_tree().process_frame
	var player: Player = null
	for entity in World.get_entities():
		if entity is Player and entity.spawned:
			player = entity
	var store: Dictionary = World.holdings.place(TOWN)
	World._relocate(player, _main._nearest_free(store.get("cell", Vector2i.ZERO) + Vector2i(0, 3)))
	print("== townsfolk keep moving (853): %d hours from %d:00 in Umbrage, a player in the square ==" % [HOURS, FROM_HOUR])
	while int(DayNight.hour(DayNight.now())) != FROM_HOUR:
		World.step()
	var t0 := Time.get_ticks_msec()
	for s in HOURS * HOUR:
		World.step()
		if s % MINUTE == 0:
			_sample()
		if s % HOUR == 0:
			await get_tree().process_frame
	_check(not _worst.is_empty(), "bodies were read (%d)" % _worst.size())
	# 853 amended (15): a run whose body is gone at a sample ends there, so one despawned and spawned again
	# on its own tile and facing starts a new run, never counting the time it had no body.
	_runs["absent:probe"] = {"tile": Vector2i(1, 1), "facing": Vector2i(0, 1), "since": 0, "told": false, "shut_told": false}
	_sample()
	_check(not _runs.has("absent:probe"), "a body with none at a sample ends its idle run (despawned and back on its tile is not idle)")
	_check(_samples >= HOURS * 60,
		"(%d samples; at the ten-minute ones, %d found beside a spot another chose too and stands on, none two running unless told above)" % [_samples, _taken_seen])
	_check(int(_keeper.get("due", 0)) >= 60 and (_keeper["missing"] as Array).is_empty() and (_keeper["astray"] as Array).is_empty(),
		"Rolf under the cap: from his first work spell to his sleep, a body at his stand at work in every one of %d samples (cells %s, doings %s; %d samples before work or asleep; missing %s; astray %s)" % [
			int(_keeper.get("due", 0)), (_keeper["cells"] as Dictionary).keys(), (_keeper["doings"] as Dictionary).keys(), int(_keeper.get("off", 0)),
			(_keeper["missing"] as Array).slice(0, 5), (_keeper["astray"] as Array).slice(0, 5)])
	_check(not (_fire["noon"] as Array).is_empty(), "853am18: someone sits at the square's fire at midday, %d:00 to %d:00 (first %s; %d samples)" % [
		int(FIRE_NOON.x), int(FIRE_NOON.y), (_fire["noon"] as Array).slice(0, 1), (_fire["noon"] as Array).size()])
	_check(int(_fire["most"]) <= Resident.FIRE_SITTERS, "853am18: by day never more than %d of the square's people hold the fire's seats at once (most %d%s)" % [
		Resident.FIRE_SITTERS, int(_fire["most"]), (" at " + str(_fire["most_at"])) if not str(_fire["most_at"]).is_empty() else ""])
	_check((_fire["askew"] as Array).is_empty(), "853am18: a sitter at the fire faces it (%s)" % [(_fire["askew"] as Array).slice(0, 3)])
	var names: Array = _worst.keys()
	names.sort()
	print("  longest idle stay each, game minutes: %s" % ", ".join(names.map(func(n: String) -> String: return "%s %d" % [n, _worst[n]])))
	print("  %d game hours in %.0f s" % [HOURS, (Time.get_ticks_msec() - t0) / 1000.0])
	print("RESULT: %s (%d failed)" % ["PASS" if _failed == 0 else "FAIL", _failed])
	Net.state_path = ""
	get_tree().quit(0 if _failed == 0 else 1)


func _idle(body: Resident) -> bool:
	if body.activity == "sleep" or not body.task.is_empty() or not body.addressing.is_empty():
		return false
	if body.doing in [Resident.Doing.BED, Resident.Doing.HIDE, Resident.Doing.ESCORT, Resident.Doing.STRAYED, Resident.Doing.VISIT]:
		return false
	# At its work spot (853 amended (8), maps' people work) showing a trade the client draws: the
	# show in bouts, the rests between facing the same work (the hunter's at the woodpile). A trade
	# with no word, or one the client doesn't draw, stands there idle as far as a player sees (npc).
	if body.doing == Resident.Doing.WORK and str(body._spot.get("use", "")) == "work" and body.tile == body._spot.get("cell") \
			and Client3D.ACTIVITIES.has(Resident.show_word(str(body._spot.get("trade", "")))):
		return false
	return not (body.activity in Resident.POSES and Client3D.ACTIVITIES.has(body.activity))


func _sample() -> void:
	var now := World.steps
	var seen := {}
	_samples += 1
	if _samples % TAKEN_EVERY == 0:
		_sample_taken()
	for entity in World.townsfolk():
		var body := entity as Resident
		if body == null or not body.spawned or body._far():
			_runs.erase(body.worker_id if body != null else "")
			continue
		seen[body.worker_id] = true
		var run: Dictionary = _runs.get(body.worker_id, {})
		var idle := _idle(body)
		if run.is_empty() or run["tile"] != body.tile or run["facing"] != body.facing or not idle:
			_runs[body.worker_id] = {"tile": body.tile, "facing": body.facing, "since": now, "told": false, "shut_told": false}
			continue
		var minutes := (now - int(run["since"])) / MINUTE
		_worst[body.person] = maxi(int(_worst.get(body.person, 0)), minutes)
		if minutes > STAY_MINUTES and not run["told"]:
			run["told"] = true
			_check(false, "%s stood idle on %s facing %s for %d game minutes from %.2f (%s; goal %s, next stroll in %d ticks, route %d, retry %d, strolls %s, spot %s)" % [
				body.person, body.tile, body.facing, minutes, DayNight.hour(DayNight.now()) - minutes / 60.0, Resident.Doing.keys()[body.doing],
				body._goal, body._wander_at - World.tick, body._route.size(), body._retry_at - World.tick, body._strolls(), body._spot])
		if minutes > SHUT_MINUTES and not run["shut_told"] and not World.is_walkable(body.tile + body.facing):
			run["shut_told"] = true
			_check(false, "%s stood idle facing shut ground at %s for %d game minutes" % [body.person, body.tile + body.facing, minutes])
	# A body not here at this sample (despawned under Main's RESIDENTS_MAX, gone indoors, away) ends its run
	# (853 amended (15)): the stall's keeper, given no body from 13.83 to 17.33 and spawned again on his own
	# tile and facing, read as 236 minutes stood idle.
	for who: String in _runs.keys():
		if not seen.has(who):
			_runs.erase(who)
	_sample_keeper()
	_sample_fire()


## The square's fire (853 amended (18)): who sits at a seat of it, facing in, and how many hold its seats before evening.
func _sample_fire() -> void:
	var hour := DayNight.hour(DayNight.now())
	var holding := 0
	for entity in World.townsfolk():
		var body := entity as Resident
		if body == null or not body.spawned or body.town != TOWN or str(body._spot.get("use", "")) != "fire":
			continue
		holding += 1
		if body.tile != body._spot.get("cell") or body.activity != "sit":
			continue
		if body.facing != body._toward(body._spot["face"]):
			(_fire["askew"] as Array).append("%s at %s facing %s, %.2f" % [body.person, body.tile, body.facing, hour])
		if hour >= FIRE_NOON.x and hour < FIRE_NOON.y:
			(_fire["noon"] as Array).append("%s %s at %.2f (%s)" % [body.person, body.tile, hour, Resident.Doing.keys()[body.doing]])
	if hour < FIRE_DAY_END and holding > int(_fire["most"]):
		_fire["most"] = holding
		_fire["most_at"] = "%.2f" % hour


## The stall's keeper under the cap (333 amended (4): keepers are never cut): from his clock's first work spell to his
## sleep spell, a body at every sample, on his stand, at work (his inn spell there read as work, 875 amended (4)).
func _sample_keeper() -> void:
	var id := Offers.VENDOR + TOWN
	var now := DayNight.now()
	var hour := DayNight.hour(now)
	var clock := Resident.doing_at("", hour, Season.name_at(int(now)), "", id, Townsfolk.day_of(now), Townsfolk.mood_of(World.production, id))
	if clock == Resident.Doing.WORK:
		_keeper["worked"] = true
	if not bool(_keeper.get("worked", false)) or clock == Resident.Doing.HOME:
		_keeper["off"] = int(_keeper.get("off", 0)) + 1
		return
	_keeper["due"] = int(_keeper.get("due", 0)) + 1
	var body: Resident = null
	for entity in World.townsfolk():
		if (entity as Resident).worker_id == id and entity.spawned:
			body = entity
	var line := "%.2f clock %s" % [hour, Resident.Doing.keys()[clock]]
	if body == null:
		(_keeper["missing"] as Array).append(line)
		return
	var stand: Rect2i = _main._vendor_spot(TOWN, World.holdings.place(TOWN).get("cell", Vector2i.ZERO))
	(_keeper["cells"] as Dictionary)[body.tile] = true
	(_keeper["doings"] as Dictionary)[Resident.Doing.keys()[body.doing]] = true
	if not stand.has_point(body.tile) or body.doing != Resident.Doing.WORK:
		(_keeper["astray"] as Array).append("%s: %s %s" % [line, body.tile, Resident.Doing.keys()[body.doing]])


## Each body beside its goal while the body on it chose that cell too and stays there (853 amended (16)).
func _sample_taken() -> void:
	var found := {}
	for entity in World.townsfolk():
		var body := entity as Resident
		if body == null or not body.spawned or body._far() or body.tile == body._goal or World.distance(body.tile, body._goal) > 1:
			continue
		var holder := World.get_entity_at(body._goal) as Resident
		if holder == null or holder == body or holder._goal != body._goal:
			continue
		found[body.worker_id] = int(_taken.get(body.worker_id, 0)) + 1
		_taken_seen += 1
		if int(found[body.worker_id]) == 2:
			_check(false, "%s stood beside %s, taken by %s who chose it too, for two ten-minute samples running (at %.2f, %s)" % [
				body.person, body._goal, holder.person, DayNight.hour(DayNight.now()), Resident.Doing.keys()[body.doing]])
	_taken = found


func _check(ok: bool, label: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + label)
	if not ok:
		_failed += 1
