extends Node
## The lawspeaker's rulings by batch (decision 448, phase 2 of Jeff's
## proposal): the request built from the town's memory, lore and the
## candidates (a player's words left out unless allowed); each ruling kind
## applied (accept, reconcile keeping the candidate's history, leave with a
## rest, move_in marked ready, propose as memory and listed); a memory that
## names the world refused by code; a round through StubClaude (never the
## API: no key, no network) that saves the log and the lawspeaker's record
## and tells the town; a failed answer leaving the candidates; the session's
## Claude budget stopping a round; what the town remembers reaching the
## voice's lore lines. Pure sim: no Main, no port, no scratch folder. Reads
## the repo's levels, never the shared overlay. Run it with tests/run.ps1
## or tests/run.sh. Prints PASS/FAIL per assertion and quits with exit
## code 1 if any assertion failed, 0 otherwise.

const TOWN := "l/store"

var _failures := 0
var _now := 0
var _stock: Stockpile
var _work: Production
var _logs := {}
var _records := {}
var _notes: Array = []
var _ctx := {}
var _players_words := false


## StubClaude answers a request with a fixed text: the JSON rulings.
class Answer:
	extends RefCounted
	var text := ""
	var sent: Array = []
	var error := ""
	func _init(words: String, fail := "") -> void:
		text = words
		error = fail
	func send(body: Dictionary) -> Dictionary:
		sent.append(body.duplicate(true))
		await Engine.get_main_loop().process_frame
		if not error.is_empty():
			return {"error": error}
		return {"model": body.get("model", ""), "stop_reason": "end_turn", "usage": {"input_tokens": 900, "output_tokens": 120},
			"content": [{"type": "text", "text": text}], "request_id": "req_test"}


func _ready() -> void:
	World.set_process(false)
	_test_request()
	_test_apply()
	await _test_round()
	await _test_failures()
	_test_remembered_in_voice()
	Production.profile_of = Callable()
	Production.type_of = Callable()
	TownMemory.use_settings({})
	TownMemory.use_names(PackedStringArray())
	Lawspeaker.use_settings({})
	Offers.ctx = {}
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


static func _profile(_trade: String, _type := "") -> Dictionary:
	return {"intellect": 5, "superstition": 5, "creativity": 5, "integrity": 5}


static func _type(_id: String) -> String:
	return ""


func _setup() -> void:
	_now = 10 * DayNight.day_steps
	_logs = {}
	_records = {}
	_notes.clear()
	_players_words = false
	Production.profile_of = _profile
	Production.type_of = _type
	TownMemory.use_settings({"spread": 3, "held": 2, "hold_days": 3, "max": 200})
	TownMemory.use_names(PackedStringArray(["goblins", "blood rot"]))
	Lawspeaker.use_settings({"every": 100, "rest_days": 7, "max_candidates": 12, "max_tokens": 500, "lore_facts": 4})
	var clock := func() -> int: return _now
	var cat := func() -> Dictionary: return {}
	_stock = Stockpile.new({}, clock, ItemBook.new(clock))
	_work = Production.new({}, _stock, null, clock, Production.read_rules(), cat)
	for each: Array in [["l-mara", "Mara", "cook"], ["l-tam", "Tam", "hauler"], ["l-bram", "Bram", "smith"]]:
		_work.add_worker(each[0], each[1], [each[2]], TOWN)
	_ctx = {
		"production": _work,
		"memory": func(town: String) -> Array: return _logs.get(town, []).duplicate(true),
		"set_memory": func(town: String, log: Array) -> void: _logs[town] = log.duplicate(true),
		"lawspeaker": func(town: String) -> Dictionary: return _records.get(town, {}).duplicate(true),
		"set_lawspeaker": func(town: String, record: Dictionary) -> void: _records[town] = record.duplicate(true),
		"note": func(town: String, line: String) -> void: _notes.append([town, line]),
		"lore": func(_town: String) -> Array: return ["Those who live near the mine call it the rot-source.", "Deer graze in the wilds."],
		"town_name": func(_town: String) -> String: return "Ashford",
		"players_words": func() -> bool: return _players_words,
		"model": func() -> String: return "claude-haiku-5-5",
	}
	Offers.ctx = _ctx


## A log with three candidates and one memory, as phase 1 leaves it.
func _log_with_candidates() -> Array:
	var log: Array = []
	var day := DayNight.day_steps
	TownMemory.note(log, "Old Marta lives by the east field", "l-mara", "player:p1", 0)
	TownMemory.hold(log, "Old Marta lives by the east field", "l-tam", "l-mara", day)
	TownMemory.hold(log, "Old Marta lives by the east field", "l-bram", "l-tam", 2 * day)
	TownMemory.note(log, "Marta's boy Timmy is sick again", "l-mara", "l-tam", 0)
	TownMemory.hold(log, "Marta's boy Timmy is sick again", "l-tam", "l-mara", day)
	TownMemory.hold(log, "Marta's boy Timmy is sick again", "l-bram", "l-tam", day)
	TownMemory.note(log, "The miller's dog bit the smith", "player:p1", "l-tam", 0)
	TownMemory.hold(log, "The miller's dog bit the smith", "l-tam", "player:p1", day)
	TownMemory.hold(log, "The miller's dog bit the smith", "l-bram", "l-tam", day)
	TownMemory.hold(log, "The miller's dog bit the smith", "l-mara", "l-bram", day)
	TownMemory.note(log, "The well was dug by Bram's grandfather", "l-bram", "l-tam", 0)
	log[3]["tier"] = TownMemory.MEMORY
	TownMemory.candidates(log, 5 * day)
	return log


func _test_request() -> void:
	print("\n== the request: memory, lore, the candidates, a traveller's words left out ==")
	_setup()
	var log := _log_with_candidates()
	_check(TownMemory.of_tier(log, TownMemory.CANDIDATE).size() == 3, "(three candidates, one memory)")
	var body := Lawspeaker.request(TOWN, log, _ctx)
	var user := str(body["messages"][0]["content"])
	_check(body["model"] == "claude-haiku-5-5" and body["max_tokens"] == 500 and str(body["system"]).begins_with("You are the lawspeaker of Ashford"), "the model, the budget, the system prompt for the town")
	_check(user.contains("[tm.4] The well was dug by Bram's grandfather") and user.contains("Those who live near the mine call it the rot-source."), "what the town remembers and what lore knows are in it")
	_check(user.contains("[tm.1] \"Old Marta lives by the east field\", first said by Mara the cook to a traveller, held by Mara the cook, Tam the hauler, Bram the smith (3 of 3 who heard it), 10 days old."),
		"a candidate with its source, holders, spread and age")
	_check(not user.contains("tm.3") and body["candidates"] == ["tm.1", "tm.2"], "a traveller's own words stay out of the request by default")
	_players_words = true
	body = Lawspeaker.request(TOWN, log, _ctx)
	_check(body["candidates"] == ["tm.1", "tm.2", "tm.3"], "and go in when allowed")
	_check(Lawspeaker.request(TOWN, [], _ctx).is_empty(), "nothing to rule on, no request")
	_check(Lawspeaker.parse({"content": [{"type": "text", "text": "```json\n{\"rulings\": [{\"candidate\": \"tm.1\", \"ruling\": \"accept\"}]}\n```"}]}).size() == 1
		and Lawspeaker.parse({"content": [{"type": "text", "text": "I cannot say."}]}).is_empty() and Lawspeaker.parse({"error": "x"}).is_empty()
		and Lawspeaker.parse({"content": [{"type": "text", "text": "{\"rulings\": [{\"candidate\": \"tm.1\", \"ruling\": \"burn\"}]}"}]}).is_empty(),
		"the answer parsed: fenced JSON, words, an error, an unknown ruling")


func _test_apply() -> void:
	print("\n== each ruling applied by code; the world refused ==")
	_setup()
	var log := _log_with_candidates()
	var day := DayNight.day_steps
	var lines := Lawspeaker.apply(log, [
		{"candidate": "tm.1", "ruling": "accept", "memory": "Old Marta lives by the east field.", "because": "three hold it"},
		{"candidate": "tm.2", "ruling": "reconcile", "memory": "Timmy was sick through the winter and is mending", "because": "the priest says he is up"},
		{"candidate": "tm.3", "ruling": "leave", "because": "one dog, one bite"},
	], 12 * day)
	_check(log[0]["tier"] == TownMemory.MEMORY and log[0]["ruling"]["ruling"] == "accept", "accepted: town memory")
	var made := TownMemory.find(log, "Timmy was sick through the winter and is mending")
	_check(log[1]["tier"] == TownMemory.RECONCILED and not made.is_empty() and made["tier"] == TownMemory.MEMORY and made["said_by"] == "lawspeaker"
		and made["ruling"]["from"] == "tm.2" and log[1]["ruling"]["memory"] == made["id"], "reconciled: a new memory with his explanation, the candidate kept and pointing at it")
	_check(log[2]["tier"] == TownMemory.BELIEF and log[2]["rest_until"] == 12 * day + 7 * day, "left: a belief again, rested seven days")
	_check(TownMemory.candidates(log, 13 * day).is_empty(), "and not a candidate again while it rests")
	_check(lines.size() == 3 and lines[0] == "the lawspeaker ruled: the town remembers that old Marta lives by the east field", "the town's log lines: %s" % [lines])
	log = _log_with_candidates()
	Lawspeaker.apply(log, [
		{"candidate": "tm.1", "ruling": "move_in", "because": "she would live by the field"},
		{"candidate": "tm.2", "ruling": "propose", "memory": "Marta's boy Timmy is sickly", "because": "it is the town's own"},
		{"candidate": "tm.3", "ruling": "accept", "memory": "The miller's dog bit the smith at the goblins' camp", "because": ""},
	], 12 * day)
	_check(log[0]["tier"] == TownMemory.CANDIDATE and log[0]["ready"] == true, "move_in: marked ready, nothing more yet")
	_check(log[1]["tier"] == TownMemory.MEMORY and log[1]["proposed"] == true and log[1]["text"] == "Marta's boy Timmy is sickly", "propose: memory, and listed for lore")
	_check(log[2]["tier"] == TownMemory.BELIEF and log[2]["ruling"]["ruling"] == "leave" and str(log[2]["ruling"]["because"]).contains("named the world"), "a memory that names the world is refused by code and the candidate left")
	_check(Lawspeaker.apply(log, [{"candidate": "tm.9", "ruling": "accept"}, {"candidate": "tm.3", "ruling": "accept"}], 13 * day).size() == 0, "an unknown id, or one no longer a candidate, does nothing")


func _test_round() -> void:
	print("\n== a round through the stub: asked, applied, saved, told ==")
	_setup()
	_logs[TOWN] = _log_with_candidates()
	var stub := Answer.new('{"rulings": [{"candidate": "tm.1", "ruling": "accept", "memory": "", "because": "three hold it"}, {"candidate": "tm.2", "ruling": "leave", "because": "wait"}]}')
	var calls_before: int = ClaudeMind.calls
	await Lawspeaker.tick(_now, stub, _ctx)
	_check(stub.sent.size() == 1 and not stub.sent[0].has("town") and str(stub.sent[0]["system"]).contains("Ashford"), "one request sent, the body clean")
	var log: Array = _logs[TOWN]
	_check(TownMemory.find(log, "Old Marta lives by the east field")["tier"] == TownMemory.MEMORY and TownMemory.find(log, "Marta's boy Timmy is sick again")["tier"] == TownMemory.BELIEF,
		"the rulings are applied to the saved log")
	_check(_records[TOWN]["last_round"] == _now and _records[TOWN]["rulings"] == 2, "the lawspeaker's record: the round and the count")
	_check(_notes.size() == 2 and _notes[0][0] == TOWN and str(_notes[0][1]).begins_with("the lawspeaker ruled"), "the town's log told: %s" % [_notes])
	_check(ClaudeMind.calls == calls_before + 1, "the session's Claude budget counts it")
	await Lawspeaker.tick(_now + 50, stub, _ctx)
	_check(stub.sent.size() == 1, "not again before the day is out")
	await Lawspeaker.tick(_now + 100, stub, _ctx)
	_check(stub.sent.size() == 1, "a day on, with the left one resting and nothing new: no request")
	var more: Array = _logs[TOWN]
	TownMemory.note(more, "The smith sings at night", "l-bram", "l-tam", 0)
	TownMemory.hold(more, "The smith sings at night", "l-tam", "l-bram", 0)
	TownMemory.hold(more, "The smith sings at night", "l-mara", "l-tam", 0)
	TownMemory.candidates(more, _now)
	_logs[TOWN] = more
	await Lawspeaker.tick(_now + 200, stub, _ctx)
	_check(stub.sent.size() == 2, "a new candidate the next day: asked again")
	_notes.clear()
	await Lawspeaker.tick(_now + 200, null, _ctx)
	_check(_notes.is_empty(), "no client (off): nothing happens")


func _test_failures() -> void:
	print("\n== a failed answer leaves the candidates; the budget spent stops a round ==")
	_setup()
	_logs[TOWN] = _log_with_candidates()
	var broken := Answer.new("", "HTTP 529: overloaded")
	await Lawspeaker.tick(_now, broken, _ctx)
	_check(TownMemory.of_tier(_logs[TOWN], TownMemory.CANDIDATE).size() == 3 and _records[TOWN]["failed"] == "HTTP 529: overloaded" and _notes.is_empty(),
		"an error: the candidates stay, the record says why")
	var words := Answer.new("I would rather not.")
	await Lawspeaker.tick(_now + 100, words, _ctx)
	_check(TownMemory.of_tier(_logs[TOWN], TownMemory.CANDIDATE).size() == 3 and _records[TOWN]["failed"] == "no rulings in the answer", "words, not rulings: the same")
	var spent_before: int = ClaudeMind.calls
	ClaudeMind.calls = ClaudeMind.CALL_BUDGET
	var fine := Answer.new('{"rulings": [{"candidate": "tm.1", "ruling": "accept"}]}')
	await Lawspeaker.tick(_now + 200, fine, _ctx)
	_check(fine.sent.is_empty() and TownMemory.of_tier(_logs[TOWN], TownMemory.CANDIDATE).size() == 3, "the session's budget spent: not asked")
	ClaudeMind.calls = spent_before


func _test_remembered_in_voice() -> void:
	print("\n== what the town remembers reaches the voice after lore's facts ==")
	var log: Array = []
	TownMemory.note(log, "Old Marta lives by the east field", "l-mara", "", 0)
	log[0]["tier"] = TownMemory.MEMORY
	_check(TownMemory.remembered(log) == ["The town remembers that old Marta lives by the east field."], "as memory, not fact: %s" % [TownMemory.remembered(log)])


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
