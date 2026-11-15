extends Node
## The square's fire at night (853 amended (18), the coordinator's ruling 11-15: it stands on its own while 875's
## evening is off). Umbrage as town_day_test sets it up, a player in the square, 21:00 to 05:00, every body read
## each game minute. No lodger (a visitor, the stall's keeper) and no inn-goer turned away holds a fire seat: every
## night sitter's doing is the square (its stint, or its night pick); never more than Resident.FIRE_SITTERS of the
## town at once; none faces away. The fire is put out at 03:00: from 04:05 (a seat's longest sit and a stroll
## after it) nobody holds a seat. (The keepers' work spells are town_day_test's.)

const TOWN := "wilds/store"
const PIT := Vector2i(194, 211)
const HOUR := 2250
const MINUTE := 37
const FROM_HOUR := 21
const HOURS := 8
## When the fire is put out, and from when nobody may still hold a seat of it (game hours past midnight).
const OUT_AT := 3.0
const NONE_FROM := 4.08
const FOLK := [["smith_1", "Odo", "smith"], ["cook_1", "Mags", "cook"], ["carp_1", "Pell", "carpenter"],
	["hunt_1", "Hob", "hunter"], ["tan_1", "Hew", "tanner"], ["farm_1", "Tam", "farmer"],
	["hand_1", "Ash", "hauler"], ["hand_2", "Bea", "hauler"], ["guard_1", "Gar", "guard"], ["hand_3", "Nix", "hauler"]]

var _main: Node
var _failed := 0
var _told := {}
var _seen := {"sitters": {}, "most": 0, "most_at": "", "after_out": 0}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	World.set_process(false)
	var ports := preload("res://tests/test_ports.gd")
	Net.port = ports.of(17962)
	Net.companions = false
	Net.map_name = "wilds"
	Net.lawspeaker = "off"
	Net.state_path = ports.scratch_path("fire_night_world.json")
	if FileAccess.file_exists(Net.state_path):
		DirAccess.remove_absolute(Net.state_path)
	_main = preload("res://main.tscn").instantiate()
	_seat_the_fire(_main)
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
	print("== the square's fire at night (853 amended (18)): %d hours from %d:00, 875's evening off, the fire out at %.0f:00 ==" % [HOURS, FROM_HOUR, OUT_AT])
	_check(World.is_fire(PIT), "the square's fire burns at %s" % PIT)
	while int(DayNight.hour(DayNight.now())) != FROM_HOUR:
		World.step()
	var out := false
	for s in HOURS * HOUR:
		World.step()
		var hour := DayNight.hour(DayNight.now())
		if not out and hour >= OUT_AT and hour < FROM_HOUR:
			out = true
			World._fire.erase(PIT)
			_check(not World.is_fire(PIT), "put out at %.2f" % hour)
		if s % MINUTE == 0:
			_sample(hour, out)
		if s % HOUR == 0:
			await get_tree().process_frame
	var sitters: Array = (_seen["sitters"] as Dictionary).keys()
	print("  night sitters: %s" % ", ".join(sitters))
	_check(not sitters.is_empty(), "the night's square-goers sit at the burning fire (%d)" % sitters.size())
	_check(int(_seen["most"]) <= Resident.FIRE_SITTERS, "never more than %d of the town hold its seats at once (most %d at %s)" % [
		Resident.FIRE_SITTERS, int(_seen["most"]), _seen["most_at"]])
	_check(int(_seen["after_out"]) == 0, "the fire out from %.0f:00, nobody holds a seat of it from %.2f (%d samples held)" % [OUT_AT, NONE_FROM, int(_seen["after_out"])])
	print("RESULT: %s (%d failed)" % ["PASS" if _failed == 0 else "FAIL", _failed])
	Net.state_path = ""
	get_tree().quit(0 if _failed == 0 else 1)


func _sample(hour: float, out: bool) -> void:
	var holding := 0
	var keeper := Offers.VENDOR + TOWN
	for entity in World.townsfolk():
		var body := entity as Resident
		if body == null:
			continue
		var on_fire := str(body._spot.get("use", "")) == "fire"
		if not on_fire or body.town != TOWN or not body.spawned:
			continue
		holding += 1
		if body.worker_id.begins_with(Offers.VISITOR) or body.worker_id == keeper:
			_say(body, "lodger", "%s, a lodger, holds a fire seat %s at %.2f (%s)" % [body.person, body._spot.get("cell"), hour, Resident.Doing.keys()[body.doing]])
		if body.doing != Resident.Doing.SQUARE:
			_say(body, "doing", "%s holds a fire seat %s at %.2f doing %s, not the square" % [body.person, body._spot.get("cell"), hour, Resident.Doing.keys()[body.doing]])
		if body.tile == body._spot.get("cell") and body.activity == "sit":
			(_seen["sitters"] as Dictionary)["%s (%s)" % [body.person, body.trade]] = true
			if body.facing != body._toward(body._spot["face"]):
				_say(body, "askew", "%s sits at %s facing %s, away from the fire, at %.2f" % [body.person, body.tile, body.facing, hour])
		if out and hour >= NONE_FROM and hour < FROM_HOUR:
			_seen["after_out"] += 1
			_say(body, "out", "%s still holds a seat %s of the fire out since %.0f:00, at %.2f" % [body.person, body._spot.get("cell"), OUT_AT, hour])
	if holding > int(_seen["most"]):
		_seen["most"] = holding
		_seen["most_at"] = "%.2f" % hour


func _say(body: Resident, what: String, label: String) -> void:
	if _told.has(body.worker_id + "|" + what):
		return
	_told[body.worker_id + "|" + what] = true
	_check(false, label)


## The square's fire's seats (853 amended (18): Main sits nobody where no seat decor is, Main.seat_cells_of): the
## level's own, maps' four log seats on the pit's diagonals (774 amended (5)), nothing added for the run. Set before
## Main boots: a body's spots are read as it is made.
static func _seat_the_fire(main: Node) -> void:
	var loaded := Level.load_level("wilds")
	main._seat_decor["wilds"] = Main.seat_cells_of(loaded.get("terrain", {}).get("decor", []), Level.DECOR_KINDS)


func _check(ok: bool, label: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + label)
	if not ok:
		_failed += 1
