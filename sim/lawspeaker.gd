class_name Lawspeaker
## The lawspeaker's rulings, offline, by batch (decision 448, phase 2 of
## Jeff's proposal docs/lore/lawspeaker.md): the one careful mind over the
## town's many cheap voices. Every "lawspeaker.every" steps (a day), a town
## whose memory log (447) holds candidates gets one structured request: the
## town's memories, the candidates with their text, source, holders, spread
## and age, the lore facts that bear on them, and the rules; he answers JSON
## rulings only, and code applies them (apply): accept (town memory),
## reconcile (a new memory with his in-world explanation, the candidate
## marked reconciled and pointing at it), leave (a belief again, rested
## "rest_days"), move_in (marked ready; phase 4 acts), propose (memory, and
## marked proposed for the list lore keeps for Jeff; phase 5). He never
## writes lore and never invents the world: a memory text that trips the
## world guard (TownMemory.is_world) is refused by code and the candidate
## left. Everything to mind.log (kind "ruling") and the town's log.
##
## The model is the builder's ClaudeClient (363's ClaudeMind is a voice
## wrapper; this is a request): off by default (Net.lawspeaker "off";
## --lawspeaker=<haiku|sonnet|opus>), one request per town per day, its
## cost capped a request (Net.lawspeaker_max_cost) and counted into
## ClaudeMind's session budget (note_spend, spent), the key only from
## ANTHROPIC_API_KEY read by ClaudeClient and never logged; StubClaude in
## tests and on a keyless server. A player's words ("player:<id>" sources)
## are left out of the request unless Net.lawspeaker_players is on (the
## proposal's outside-API note). Any failure leaves the candidates for the
## next round: the town runs without him.

const FILE := "res://levels/residents.json"
const DEFAULTS := {"every": 54000, "rest_days": 7, "max_candidates": 12, "max_tokens": 1500, "lore_facts": 24}
const MODELS := {"haiku": "claude-haiku-5-5", "sonnet": "claude-sonnet-5-5", "opus": "claude-opus-5-5"}
const RULINGS: Array[String] = ["accept", "reconcile", "leave", "move_in", "propose"]
const SAID_BY := "lawspeaker"
const SYSTEM := """You are the lawspeaker of %s, a small town in a game: the one who holds in memory what the town remembers and keeps it straight. On your rounds you have heard what the people say. You are given what the town already remembers, what lore (the world's facts, which outrank everything) says that bears on it, and the candidates: things several people now believe. Rule on each candidate:
- accept: it becomes town memory as said (or tidied into one plain sentence in "memory").
- reconcile: it clashes with lore or with what the town remembers; give the in-world explanation in "memory" (she moved away; it was only Marta's talk; the boy got better), which becomes the memory instead.
- leave: not taken up; it stays one person's talk.
- move_in: it speaks of a person who would live in or near the town and is still talked of; they may arrive (code decides when).
- propose: good enough to be the world's; it becomes memory and is listed for the author of the world, never written as lore by you.
You never write lore and never invent the world: no factions, history, places, gods, rulers, wars or the land's names; small life is free (neighbours, kin, ailments, chores, quarrels, animals, weather). Reconcile, never erase. Reply with one JSON object and nothing else:
{"rulings": [{"candidate": "tm.3", "ruling": "accept|reconcile|leave|move_in|propose", "memory": "one sentence, for accept, reconcile and propose", "because": "one clause"}]}"""

static var _settings := {}
static var _due: Dictionary = {}
## Test hook: the last request built and the last rulings applied.
static var last_request: Dictionary = {}
static var last_applied: Array = []


static func settings() -> Dictionary:
	if _settings.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE)) if FileAccess.file_exists(FILE) else null
		_settings = DEFAULTS.duplicate()
		if data is Dictionary and data.get("rulings") is Dictionary:
			_settings.merge(data["rulings"], true)  # "lawspeaker" is his day (459).
	return _settings


## Uses [param given] in place of the file's "rulings" ({} to read it again): tests.
static func use_settings(given: Dictionary) -> void:
	_settings = {}
	_due = {}
	if not given.is_empty():
		_settings = DEFAULTS.duplicate()
		_settings.merge(given, true)


static func setting(key: String) -> int:
	return int(settings().get(key, DEFAULTS.get(key, 0)))


## The request for [param town] over [param log]'s candidates (a Messages
## API body): {} when there is nothing to rule on. [param given] (Offers.ctx
## shaped) gives "production", "lore" (town) -> [sentences], "town_name"
## (town) -> String, "players_words" () -> bool, "model" () -> String.
static func request(town: String, log: Array, given: Dictionary) -> Dictionary:
	var production: Production = given.get("production")
	var players_words := bool(Offers._call(given, "players_words"))
	# With a lawspeaker in the town (decision 459), the batch is built from the
	# people he stood with on his rounds today: candidates they hold or said,
	# and every dispute, which comes first.
	var visited: Variant = Offers._call(given, "visits", [town])
	var near: Array = visited if visited is Array else []
	var candidates: Array[Dictionary] = []
	var all: Array[Dictionary] = TownMemory.of_tier(log, TownMemory.CANDIDATE)
	all.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return bool(a.get("dispute", false)) and not bool(b.get("dispute", false)))
	for entry: Dictionary in all:
		if bool(entry.get("world", false)) or bool(entry.get("ready", false)) or bool(entry.get("proposed", false)):
			continue
		if not players_words and str(entry.get("said_by", "")).begins_with(TownMemory.PLAYER):
			continue
		if not near.is_empty() and not bool(entry.get("dispute", false)) and str(entry.get("said_by", "")) not in near \
				and not entry.get("holders", []).any(func(id: Variant) -> bool: return str(id) in near):
			continue
		candidates.append(entry)
		if candidates.size() >= setting("max_candidates"):
			break
	if candidates.is_empty():
		return {}
	var name := str(Offers._call(given, "town_name", [town]))
	if name.is_empty() or name == "<null>":
		name = town
	var lines: Array[String] = ["The town: %s." % name, "", "What the town remembers:"]
	var memories := TownMemory.of_tier(log, TownMemory.MEMORY)
	if memories.is_empty():
		lines.append("- nothing yet")
	for entry: Dictionary in memories:
		lines.append("- [%s] %s" % [entry.get("id", ""), entry.get("text", "")])
	lines.append("")
	lines.append("What lore knows that bears on them:")
	var lore: Variant = Offers._call(given, "lore", [town])
	var known: Array = lore if lore is Array else []
	if known.is_empty():
		lines.append("- nothing that touches these")
	for i in mini(known.size(), setting("lore_facts")):
		lines.append("- " + str(known[i]))
	lines.append("")
	lines.append("The candidates:")
	var day := maxi(DayNight.day_steps, 1)
	var now := production.now() if production != null else 0
	for entry: Dictionary in candidates:
		var holders: Array[String] = []
		for id: Variant in entry.get("holders", []):
			holders.append(_who(production, str(id)))
		lines.append("- [%s] \"%s\", first said by %s to %s, held by %s (%d of %d who heard it), %d days old." % [entry.get("id", ""), entry.get("text", ""),
			_who(production, str(entry.get("said_by", ""))), _who(production, str(entry.get("to", ""))), ", ".join(holders) if not holders.is_empty() else "nobody now",
			entry.get("holders", []).size(), int(entry.get("spread", 0)), int((now - int(entry.get("first_said", now))) / day)])
	lines.append("")
	lines.append("Rule on each candidate.")
	var model := str(Offers._call(given, "model"))
	if model.is_empty() or model == "<null>":
		model = MODELS["haiku"]
	var law := str(Offers._call(given, "lawspeaker_of", [town]))
	var system := SYSTEM % name
	if not law.is_empty() and law != "<null>" and production != null and not production.worker(law).is_empty():
		system = "You are %s. " % production.worker(law).get("name", law) + system  # Named (Jeff's Q2 hook).
	return {"model": model, "max_tokens": setting("max_tokens"), "system": system,
		"messages": [{"role": "user", "content": "\n".join(lines)}], "town": town, "candidates": candidates.map(func(e: Dictionary) -> String: return str(e["id"]))}


static func _who(production: Production, id: String) -> String:
	if id.is_empty():
		return "someone"
	if id.begins_with(TownMemory.PLAYER):
		return "a traveller"
	if id == SAID_BY:
		return "the lawspeaker"
	if production == null:
		return id
	var who := production.worker(id)
	if who.is_empty():
		return id
	var trades: Array = who.get("trades", [])
	return "%s the %s" % [who.get("name", id), str(trades[0]).replace("_", " ")] if not trades.is_empty() else str(who.get("name", id))


## The rulings in [param response] (ClaudeClient.send's): [] for none, or
## an error, or words that are not the JSON asked for (fences stripped).
static func parse(response: Dictionary) -> Array:
	if response.has("error") or not response.get("content") is Array:
		return []
	var text := ""
	for part: Variant in response["content"]:
		if part is Dictionary and str(part.get("type", "")) == "text":
			text += str(part.get("text", ""))
	text = text.strip_edges()
	if text.begins_with("```"):
		text = text.trim_prefix("```json").trim_prefix("```").strip_edges().trim_suffix("```").strip_edges()
	var start := text.find("{")
	var end := text.rfind("}")
	if start < 0 or end <= start:
		return []
	var data: Variant = JSON.parse_string(text.substr(start, end - start + 1))
	if not data is Dictionary or not data.get("rulings") is Array:
		return []
	var out := []
	for ruling: Variant in data["rulings"]:
		if ruling is Dictionary and str(ruling.get("ruling", "")) in RULINGS and not str(ruling.get("candidate", "")).is_empty():
			out.append(ruling)
	return out


## [param rulings] applied to [param log] at [param step]: what each did,
## a line each, for the town's log. A memory text that touches the world is
## refused and the candidate left.
static func apply(log: Array, rulings: Array, step: int) -> Array[String]:
	var lines: Array[String] = []
	var rest := setting("rest_days") * maxi(DayNight.day_steps, 1)
	for ruling: Dictionary in rulings:
		var id := str(ruling.get("candidate", ""))
		var entry := {}
		for each: Dictionary in log:
			if str(each.get("id", "")) == id:
				entry = each
		if entry.is_empty() or str(entry.get("tier", "")) != TownMemory.CANDIDATE:
			continue
		var kind := str(ruling.get("ruling", ""))
		var memory := str(ruling.get("memory", "")).strip_edges().trim_suffix(".")
		var because := str(ruling.get("because", "")).strip_edges()
		if kind in ["accept", "reconcile", "propose"] and not memory.is_empty() and TownMemory.is_world(memory):
			kind = "leave"
			because = "the ruling named the world, which is not the town's to remember"
		entry["ruling"] = {"ruling": kind, "because": because, "step": step}
		match kind:
			"accept", "propose":
				entry["tier"] = TownMemory.MEMORY
				if not memory.is_empty():
					entry["text"] = memory
				if kind == "propose":
					entry["proposed"] = true
				lines.append("the lawspeaker ruled: the town remembers that %s%s" % [Hearsay._lower_first(str(entry["text"])), " (proposed to lore)" if kind == "propose" else ""])
			"reconcile":
				if memory.is_empty():
					entry["tier"] = TownMemory.BELIEF
					entry["rest_until"] = step + rest
					lines.append("the lawspeaker left %s as %s's talk" % [id, entry.get("said_by", "someone")])
					continue
				var made := TownMemory.note(log, memory, SAID_BY, "", step)
				made["tier"] = TownMemory.MEMORY
				made["ruling"] = {"ruling": "reconcile", "because": because, "from": id, "step": step}
				entry["tier"] = TownMemory.RECONCILED
				entry["ruling"]["memory"] = made.get("id", "")
				lines.append("the lawspeaker reconciled %s: the town remembers that %s" % [id, Hearsay._lower_first(memory)])
			"leave":
				entry["tier"] = TownMemory.BELIEF
				entry["rest_until"] = step + rest
				lines.append("the lawspeaker left \"%s\" as talk%s" % [entry.get("text", ""), ": " + because if not because.is_empty() else ""])
			"move_in":
				entry["ready"] = true
				lines.append("the lawspeaker ruled that %s may be real: the town has room for them in time" % entry.get("text", ""))
	last_applied = lines.duplicate()
	return lines


## The round's spend into ClaudeMind's session counters (one budget for
## one key): through companions' note_spend when it is there, else the
## counters themselves. That call's cost.
static func _note_spend(model: String, input: int, output: int) -> float:
	var shared := Callable(ClaudeMind, "note_spend")
	if shared.is_valid():
		return float(shared.call(model, input, output))
	var cost := ClaudeMind.cost_of(model, input, output)
	ClaudeMind.calls += 1
	ClaudeMind.tokens_in += input
	ClaudeMind.tokens_out += output
	ClaudeMind.cost += cost
	return cost


## A round for every town due at [param step]: the request sent through
## [param client] (ClaudeClient or StubClaude: send(body) awaited), the
## rulings applied, the log and the lawspeaker's record saved (Offers.ctx's
## "memory", "set_memory", "lawspeaker", "set_lawspeaker"), the town's log
## told ("note"). Nothing when the client is null (off), the session's
## Claude budget is spent (ClaudeMind.spent), or nothing is due.
static func tick(step: int, client: Variant, given: Dictionary = Offers.ctx) -> void:
	var production: Production = given.get("production")
	if production == null or client == null or not client.has_method("send"):
		return
	var every := setting("every")
	var towns := {}
	for id: String in production.worker_ids():
		var town := str(production.worker(id).get("town", ""))
		if not town.is_empty():
			towns[town] = true
	for town: String in towns:
		if int(_due.get(town, 0)) > step:
			continue
		_due[town] = step + every
		var log: Variant = Offers._call(given, "memory", [town])
		if not log is Array:
			continue
		var body := request(town, log, given)
		if body.is_empty():
			continue
		if ClaudeMind.spent():
			MindLog.record({"kind": "ruling", "mind": "lawspeaker", "town": town, "outcome": "not asked", "error": "the session's Claude budget is spent"})
			continue
		last_request = body
		var sent := body.duplicate()
		sent.erase("town")
		sent.erase("candidates")
		var response: Dictionary = await client.send(sent)
		var used: Dictionary = response.get("usage", {}) if response.get("usage") is Dictionary else {}
		var model := str(response.get("model", body.get("model", "")))
		var cost := _note_spend(model, int(used.get("input_tokens", 0)), int(used.get("output_tokens", 0))) if not used.is_empty() else 0.0
		var rulings := parse(response)
		var record: Variant = Offers._call(given, "lawspeaker", [town])
		var mine: Dictionary = record if record is Dictionary else {}
		mine["last_round"] = step
		if response.has("error") or rulings.is_empty():
			mine["failed"] = str(response.get("error", "no rulings in the answer"))
			mine["requests"] = int(mine.get("requests", 0)) + (0 if response.has("error") else 1)
			print("[lawspeaker] %s: %s gave no rulings (%s)" % [town, model, mine["failed"]])
			Offers._call(given, "set_lawspeaker", [town, mine])
			MindLog.record({"kind": "ruling", "mind": "lawspeaker", "town": town, "model": model, "candidates": body.get("candidates", []),
				"outcome": "no rulings", "error": str(response.get("error", "")), "cost": cost})
			continue
		var fresh: Array = Offers._call(given, "memory", [town])  # Read again: talk went on while we waited.
		var lines := apply(fresh, rulings, step)
		Offers._call(given, "set_memory", [town, fresh])
		mine["rulings"] = int(mine.get("rulings", 0)) + rulings.size()
		mine["requests"] = int(mine.get("requests", 0)) + 1
		mine.erase("failed")
		print("[lawspeaker] %s: %s ruled on %d (request %d of this town's, $%.4f; %d rulings in all)" % [town, model, rulings.size(), int(mine["requests"]), cost, int(mine["rulings"])])
		Offers._call(given, "set_lawspeaker", [town, mine])
		for line: String in lines:
			Offers._call(given, "note", [town, line])
		if rulings.any(func(each: Dictionary) -> bool: return str(each.get("ruling", "")) == "propose"):
			Offers._call(given, "proposed")  # The list for Jeff (decision 458).
		MindLog.record({"kind": "ruling", "mind": "lawspeaker", "town": town, "model": model, "candidates": body.get("candidates", []),
			"rulings": rulings, "applied": lines, "outcome": "ruled", "cost": cost, "request_id": str(response.get("request_id", ""))})
