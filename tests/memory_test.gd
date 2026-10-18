extends Node
## The town memory log (the lawspeaker, phase 1): a resident's own tale,
## found by the claims ask on their own line, goes into their heard as
## believed and into the town's log with its source; gossip adds holders
## and spread; an overturned belief is dropped and a belief nobody holds is
## left, never erased; beliefs that spread and hold become candidates by the
## thresholds, and one that names the world never does; the names and
## tags; what the town remembers, as the voice is told it. Pure sim: no
## Main, no port, no scratch folder. Reads the repo's levels, never the
## shared overlay. Run it with tests/run.ps1 or tests/run.sh. Prints
## PASS/FAIL per assertion and quits with exit code 1 if any assertion
## failed, 0 otherwise.

const TOWN := "m/store"
const CATALOG := {}
const EVERY := 100

var _failures := 0
var _now := 0
var _stock: Stockpile
var _work: Production
var _logs := {}
var _ctx := {}


func _ready() -> void:
	World.set_process(false)
	_test_tags_and_world()
	_test_told()
	_test_hold_drop_left()
	_test_candidates()
	_test_gossip_spreads_it()
	_test_remembered()
	_test_moving_in()
	Production.profile_of = Callable()
	Production.type_of = Callable()
	Townsfolk.use_days({})
	TownMemory.use_settings({})
	TownMemory.use_names(PackedStringArray())
	Offers.ctx = {}
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


static func _profile(_trade: String, _type := "") -> Dictionary:
	return {"intellect": 1, "superstition": 5, "creativity": 5, "integrity": 5}


static func _type(_id: String) -> String:
	return ""


func _setup(folk: Array = [["m-tam", "Tam", "hauler"], ["m-mara", "Mara", "hauler"], ["m-bram", "Bram", "hauler"]]) -> void:
	_now = 0
	_logs = {}
	Production.profile_of = _profile
	Production.type_of = _type
	TownMemory.use_settings({"spread": 3, "held": 2, "hold_days": 3, "max": 200})
	TownMemory.use_names(PackedStringArray(["goblins", "blood rot", "the rot-source", "wren"]))
	Townsfolk.use_days({"default": {"stints": [{"from": 0, "to": 12, "at": "well"}, {"from": 12, "to": 24, "at": "well"}]}, "offset_hours": 0,
		"gossip": {"every": EVERY, "places": ["well", "inn", "square", "temple"]}})
	Townsfolk._gossip_due.clear()
	var clock := func() -> int: return _now
	var cat := func() -> Dictionary: return CATALOG
	_stock = Stockpile.new({}, clock, ItemBook.new(clock))
	_work = Production.new({}, _stock, null, clock, Production.read_rules(), cat)
	for each: Array in folk:
		_work.add_worker(each[0], each[1], [each[2]], TOWN)
	for each: Array in folk:
		Townsfolk.card_of(_work, each[0])
	for each: Array in folk:
		var card := Townsfolk.card_of(_work, each[0])
		card["kin"] = {}
		card["grudge"] = []
		_work.set_card(each[0], card)
	_ctx = {
		"production": _work,
		"memory": func(town: String) -> Array: return _logs.get(town, []).duplicate(true),
		"set_memory": func(town: String, log: Array) -> void: _logs[town] = log.duplicate(true),
		"name_of": func(player_id: String) -> String: return player_id,
	}
	Offers.ctx = _ctx


func _log() -> Array:
	return _logs.get(TOWN, [])


func _test_tags_and_world() -> void:
	print("\n== the names a tale carries, and the world's ==")
	TownMemory.use_names(PackedStringArray(["goblins", "blood rot", "wren"]))
	_check(TownMemory.tags("Old Marta lives by the east field.") == PackedStringArray(["marta"]), "the capitalised words past the first, lower-cased: %s" % [TownMemory.tags("Old Marta lives by the east field.")])
	_check(TownMemory.tags("Timmy, Marta's boy, is sick again") == PackedStringArray(["marta"]) or TownMemory.tags("Timmy, Marta's boy, is sick again") == PackedStringArray(["marta", "timmy"]),
		"a possessive is trimmed; the first word is not a tag: %s" % [TownMemory.tags("Timmy, Marta's boy, is sick again")])
	_check(not TownMemory.is_world("Old Marta lives by the east field"), "small life is not the world")
	_check(TownMemory.is_world("Old Marta once cooked for the Goblins") and TownMemory.is_world("Wren was born in the town"), "a lore name makes it the world's")
	_check(TownMemory.is_world("The king rode through last spring") and TownMemory.is_world("Marta's son went to the war"), "the world's words too (king, war)")
	_check(not TownMemory.is_world("The miller's dog bit the smith"), "a dog and a smith are small life")


func _test_told() -> void:
	print("\n== a resident's own tale: into their heard and the town's log ==")
	_setup()
	var log: Array = []
	var heard: Array = []
	var claims := [{"text": "Old Marta lives by the east field", "fits": "beyond"}, {"text": "The town is short of cloth", "fits": "agrees"},
		{"text": "Marta's boy Timmy is sick again", "fits": "beyond"}, {"text": "The goblins fear the river", "fits": "beyond"}]
	var noted := TownMemory.told(log, heard, "m-mara", "player:p1", claims, 1000)
	_check(noted.size() == 3 and log.size() == 3, "each claim beyond what she knows is logged (%d), what agrees is not" % log.size())
	_check(heard.size() == 3 and heard.all(func(e: Dictionary) -> bool: return bool(e.get("believed", false)) and str(e.get("fits", "")) == Hearsay.OWN),
		"and believed as her own in her heard: %s" % [heard.map(func(e: Dictionary) -> String: return str(e["text"]))])
	var marta: Dictionary = log[0]
	_check(marta["id"] == "tm.1" and marta["tier"] == TownMemory.BELIEF and marta["said_by"] == "m-mara" and marta["to"] == "player:p1"
		and marta["holders"] == ["m-mara"] and marta["spread"] == 1 and marta["first_said"] == 1000 and marta["tags"] == ["marta"] and not marta["world"],
		"the entry: id, belief, said by her to the player, held by her, its tags: %s" % [marta])
	_check(log[2]["world"] == true, "the goblins' tale is marked the world's: %s" % log[2]["text"])
	TownMemory.told(log, heard, "m-mara", "player:p2", [{"text": "Old Marta lives by the east field.", "fits": "beyond"}], 1500)
	_check(log.size() == 3 and log[0]["last_said"] == 1500 and log[0]["spread"] == 1, "told again: the same entry, last_said moved, spread unchanged")


func _test_hold_drop_left() -> void:
	print("\n== held by others, dropped, left ==")
	var log: Array = []
	TownMemory.note(log, "Old Marta lives by the east field", "m-mara", "player:p1", 10)
	var held := TownMemory.hold(log, "old marta lives by the east field.", "m-tam", "m-mara", 20)
	_check(held["holders"] == ["m-mara", "m-tam"] and held["spread"] == 2, "Tam holds it too, matched by the words alone: %s" % [held["holders"]])
	TownMemory.hold(log, "Old Marta lives by the east field", "m-tam", "m-mara", 30)
	_check(log[0]["spread"] == 2, "held again by the same: no more spread")
	var fresh := TownMemory.hold(log, "The miller waters the flour", "m-tam", "player:p1", 40)
	_check(log.size() == 2 and fresh["said_by"] == "player:p1" and fresh["holders"] == ["m-tam"], "a thing not yet logged is logged with its source when someone holds it")
	TownMemory.drop(log, "Old Marta lives by the east field", "m-tam")
	_check(log[0]["holders"] == ["m-mara"] and log[0]["tier"] == TownMemory.BELIEF, "dropped by one, still held by another")
	TownMemory.drop(log, "Old Marta lives by the east field", "m-mara")
	_check(log[0]["holders"].is_empty() and log[0]["tier"] == TownMemory.LEFT and log.size() == 2, "held by nobody: left, never erased")
	TownMemory.hold(log, "Old Marta lives by the east field", "m-bram", "m-mara", 50)
	_check(log[0]["tier"] == TownMemory.BELIEF and log[0]["spread"] == 3, "taken up again: a belief once more, its history kept")
	TownMemory.use_settings({"spread": 3, "held": 2, "hold_days": 3, "max": 2})
	TownMemory.note(log, "The smith sings at night", "m-bram", "m-tam", 60)
	_check(log.size() == 2 and TownMemory.find(log, "The smith sings at night").size() > 0, "over max, the oldest left goes first, else the oldest")


func _test_candidates() -> void:
	print("\n== candidates: spread, held, old, and not of the world ==")
	TownMemory.use_settings({"spread": 3, "held": 2, "hold_days": 3, "max": 200})
	var day := DayNight.day_steps
	var log: Array = []
	TownMemory.note(log, "Old Marta lives by the east field", "m-mara", "player:p1", 0)
	TownMemory.hold(log, "Old Marta lives by the east field", "m-tam", "m-mara", day)
	_check(TownMemory.candidates(log, 4 * day).is_empty(), "two holders: not yet")
	TownMemory.hold(log, "Old Marta lives by the east field", "m-bram", "m-tam", 2 * day)
	_check(TownMemory.candidates(log, 2 * day).is_empty(), "three, but only two days old: not yet")
	var up := TownMemory.candidates(log, 3 * day)
	_check(up.size() == 1 and log[0]["tier"] == TownMemory.CANDIDATE, "three holders, three days: a candidate")
	_check(TownMemory.candidates(log, 4 * day).is_empty(), "and not promoted twice")
	TownMemory.note(log, "The town talks of Timmy's cough", "m-mara", "m-tam", 0)
	TownMemory.hold(log, "The town talks of Timmy's cough", "m-tam", "m-mara", 0)
	TownMemory.hold(log, "The town talks of Timmy's cough", "m-bram", "m-tam", 0)
	TownMemory.drop(log, "The town talks of Timmy's cough", "m-bram")
	TownMemory.drop(log, "The town talks of Timmy's cough", "m-tam")
	_check(TownMemory.candidates(log, 9 * day).is_empty(), "spread to three but held by one now: not a candidate")
	TownMemory.note(log, "Marta's son went to the war", "m-mara", "player:p1", 0)
	for id: String in ["m-tam", "m-bram", "m-x"]:
		TownMemory.hold(log, "Marta's son went to the war", id, "m-mara", 0)
	_check(TownMemory.candidates(log, 9 * day).is_empty() and TownMemory.find(log, "Marta's son went to the war")["world"], "a tale of the world, however held, never is")


func _test_gossip_spreads_it() -> void:
	print("\n== gossip holds a passed belief in the town's log ==")
	_setup()
	var log: Array = []
	var heard: Array = _work.worker("m-tam").get("heard", [])
	TownMemory.told(log, heard, "m-tam", "player:p1", [{"text": "Old Marta lives by the east field", "fits": "beyond"}], 0)
	_work.set_heard("m-tam", heard)
	_logs[TOWN] = log
	Townsfolk.gossip(_work)  # Arms.
	var held := false
	for i in 12:
		_now += EVERY
		Townsfolk.gossip(_work)
		var entry := TownMemory.find(_log(), "Old Marta lives by the east field")
		if not entry.is_empty() and entry["holders"].size() >= 2:
			held = true
			break
	var entry := TownMemory.find(_log(), "Old Marta lives by the east field")
	_check(held and entry["said_by"] == "m-tam" and entry["spread"] >= 2, "Tam's tale passes at the well and the hearer is a holder: %s" % [entry.get("holders", [])])
	_now = 3 * DayNight.day_steps + 100
	for i in 12:
		_now += EVERY
		Townsfolk.gossip(_work)
		if TownMemory.find(_log(), "Old Marta lives by the east field").get("tier", "") == TownMemory.CANDIDATE:
			break
	entry = TownMemory.find(_log(), "Old Marta lives by the east field")
	_check(entry["holders"].size() >= 3 and entry["tier"] == TownMemory.CANDIDATE, "three days and three holders on: the town's tick makes it a candidate (%s, %d held)" % [entry["tier"], entry["holders"].size()])


func _test_remembered() -> void:
	print("\n== what the town remembers, as the voice is told it ==")
	var log: Array = []
	TownMemory.note(log, "Old Marta lives by the east field", "m-mara", "", 0)
	TownMemory.note(log, "Timmy was sick through the winter and is mending", "m-ora", "", 0)
	log[1]["tier"] = TownMemory.MEMORY
	_check(TownMemory.remembered(log) == ["The town remembers that timmy was sick through the winter and is mending."] or TownMemory.remembered(log) == ["The town remembers that Timmy was sick through the winter and is mending."],
		"memories only, in the town's words: %s" % [TownMemory.remembered(log)])
	_check(TownMemory.of_tier(log, TownMemory.BELIEF).size() == 1 and TownMemory.of_tier(log, "").size() == 2, "by tier, or all")


var _moved: Array = []
var _room := true


func _test_moving_in() -> void:
	print("\n== remembered people move in, with room and the lawspeaker's word (decision 460) ==")
	_setup()
	_moved.clear()
	_room = true
	_ctx["move_in"] = func(town: String, who: String, name: String, trade: String) -> bool:
		if not _room:
			return false
		_moved.append([town, who, name, trade])
		return _work.add_worker(who, name, [trade], town, "remembered")
	var log: Array = []
	TownMemory.note(log, "Old Marta lives by the east field", "m-tam", "player:p1", 0)
	TownMemory.note(log, "Marta's boy Timmy is sick again", "m-tam", "m-mara", 0)
	TownMemory.note(log, "The miller Hob waters the flour", "m-bram", "m-tam", 0)
	TownMemory.note(log, "The goblins' king Gorm lives in the hills", "m-bram", "m-tam", 0)
	for entry: Dictionary in log:
		entry["tier"] = TownMemory.MEMORY
	log[0]["ready"] = true
	log[0]["ruling"] = {"ruling": "move_in", "step": 100}
	log[2]["ready"] = true
	log[2]["ruling"] = {"ruling": "move_in", "step": 50}
	log[3]["ready"] = true
	log[3]["ruling"] = {"ruling": "move_in", "step": 10}
	var who := TownMemory.arrivals(log).map(func(e: Dictionary) -> String: return str(e["id"]))
	_check(who == ["tm.3", "tm.1"], "ready, named and not of the world, oldest ruling first (the goblins' king never): %s" % [who])
	_check(TownMemory.person_of(log[0], ["cook", "hauler"]) == {"name": "Marta", "old": true, "trade": "hauler"}, "Old Marta: Marta, old, the stand-in trade: %s" % [TownMemory.person_of(log[0], ["cook", "hauler"])])
	_check(TownMemory.person_of(log[2], ["miller", "hauler"])["trade"] == "miller" and TownMemory.person_of(log[2], ["cook"])["trade"] == "hauler",
		"a trade the talk names when the town has it, else the stand-in")
	_logs[TOWN] = log
	Townsfolk.gossip(_work)  # Arms.
	_now += EVERY
	Townsfolk.gossip(_work)
	_check(_moved.size() == 2 and _moved[0][2] == "Hob" and _moved[1][2] == "Marta" and _moved[1][1] == "remembered:%s:marta" % TOWN,
		"both arrive through economy, oldest ruling first: %s" % [_moved])
	var marta := _work.worker("remembered:%s:marta" % TOWN)
	_check(not marta.is_empty() and marta["origin"] == "remembered" and marta["trades"] == ["hauler"], "Marta is a resident now, a hauler, origin remembered")
	var card: Dictionary = marta.get("card", {})
	_check(card.get("came", "") == "has lived here all along, as the town tells it" and card.get("look", {}).get("age", "") == "old"
		and card.get("facts", []).any(func(f: Dictionary) -> bool: return str(f["text"]) == "Marta's boy Timmy is sick again"),
		"her card: how she came, old, and the town's talk of her as facts (%s)" % [card.get("facts", []).map(func(f: Dictionary) -> String: return str(f["text"]))])
	_check(TownMemory.find(_log(), "Old Marta lives by the east field")["arrived"] == "remembered:%s:marta" % TOWN and TownMemory.find(_log(), "Old Marta lives by the east field")["tier"] == TownMemory.MEMORY,
		"the entry keeps who arrived and stays memory")
	_now += EVERY
	Townsfolk.gossip(_work)
	_check(_moved.size() == 2, "nobody arrives twice")
	_room = false
	var more: Array = _log()
	TownMemory.note(more, "Young Wat the hunter sleeps in the barn", "m-tam", "m-mara", 0)
	TownMemory.find(more, "Young Wat the hunter sleeps in the barn")["tier"] = TownMemory.MEMORY
	TownMemory.find(more, "Young Wat the hunter sleeps in the barn")["ready"] = true
	TownMemory.find(more, "Young Wat the hunter sleeps in the barn")["ruling"] = {"ruling": "move_in", "step": 200}
	_logs[TOWN] = more
	_now += EVERY
	Townsfolk.gossip(_work)
	_check(_moved.size() == 2 and str(TownMemory.find(_log(), "Young Wat the hunter sleeps in the barn").get("arrived", "")).is_empty(), "no room: Wat waits")
	_room = true
	_now += EVERY
	Townsfolk.gossip(_work)
	_check(_moved.size() == 3 and _moved[2][2] == "Wat" and _moved[2][3] == "hauler", "room again: Wat arrives, a hauler since the town has no hunter's trade (%s)" % [_moved.back() if not _moved.is_empty() else []])


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
