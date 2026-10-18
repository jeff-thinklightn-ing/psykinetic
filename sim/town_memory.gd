class_name TownMemory
## The town's memory log (the lawspeaker, phase 1): what the town's people
## have said of the town's small life, kept with its source, spread by
## gossip, and in time ruled on (phase 2). One log per town (economy's
## Towns.memory, saved with the town record; Main keeps it in hand until
## that hook is there), an Array of entries: {"id": "tm.<n>", "tier":
## belief | candidate | memory | left | reconciled, "text": one sentence
## as first said, "said_by": the worker id ("companion:<name>" for a resting
## companion, "player:<id>" for a player's words), "to": who heard it,
## "first_said", "last_said": steps, "holders": the worker ids who believe
## it now, "spread": how many have held it, "tags": the names in it,
## "world": whether it touches the world (lore's names, or the world's
## words), "ruling": {} until the lawspeaker rules}. Nothing is erased: a
## belief nobody holds is "left", with its history. Numbers in
## levels/residents.json "memory".
##
## A belief is born from a resident's own words (Main: the speaker's claims
## ask, 378, on their own line; each claim beyond what they know is a tale
## of their own: told(), under today's speech rule only for one whose voice
## may embellish), held and spread by gossip (hold(), 422), dropped when a
## holder's belief is overturned (drop()). A belief held by "spread" people,
## still by "held", and "hold_days" old becomes a candidate (candidates());
## one that touches the world never does: small life is free, the world is
## not. No model call here.

const FILE := "res://levels/residents.json"
const DEFAULTS := {"spread": 3, "held": 2, "hold_days": 3, "max": 200}
const BELIEF := "belief"
const CANDIDATE := "candidate"
const MEMORY := "memory"
const LEFT := "left"
const RECONCILED := "reconciled"
## Words of the world no tale may bear (the proposal's guardrail): rulers,
## gods, peoples, war and the land's names are lore's.
const WORLD_WORDS := "(?i)\\b(king|queen|prince|princess|lord|lady|duke|baron|knight\\w*|emperor|empire|kingdom|realm|crown|throne|god|gods|goddess|temple of|priest of|prophe\\w+|war|army|armies|legion\\w*|dwarf|dwarves|elf|elves|orc\\w*|goblin\\w*|kobold\\w*|dragon\\w*|demon\\w*|the land|mountain\\w*|river\\w*|forest\\w*|sea|ocean|capital|city|cities)\\b"
const PLAYER := "player:"

static var _settings := {}
static var _names: PackedStringArray = PackedStringArray()
static var _names_read := false


static func settings() -> Dictionary:
	if _settings.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE)) if FileAccess.file_exists(FILE) else null
		_settings = DEFAULTS.duplicate()
		if data is Dictionary and data.get("memory") is Dictionary:
			_settings.merge(data["memory"], true)
	return _settings


## Uses [param given] in place of the file's "memory" ({} to read it again): tests.
static func use_settings(given: Dictionary) -> void:
	_settings = {}
	if not given.is_empty():
		_settings = DEFAULTS.duplicate()
		_settings.merge(given, true)


static func setting(key: String) -> int:
	return int(settings().get(key, DEFAULTS.get(key, 0)))


## The world's names, lower-cased: lore's name forms and entries, drafts
## included (a draft name is still the world's). Cached; use_names() for tests.
static func names() -> PackedStringArray:
	if _names_read:
		return _names
	_names_read = true
	var found := {}
	# Lore's name forms and entries (lore may give one call for this later).
	for form: Dictionary in Lore.name_forms("", "draft"):
		found[str(form.get("form", "")).to_lower()] = true
	for id: String in Lore.entries():
		var entry: Dictionary = Lore.entries()[id]
		found[str(entry.get("name", id)).to_lower()] = true
		found[id.to_lower().replace("_", " ")] = true
	found.erase("")
	_names = PackedStringArray(found.keys())
	return _names


## Uses [param given] as the world's names ([] to read lore's again): tests.
static func use_names(given: PackedStringArray) -> void:
	_names = given
	_names_read = not given.is_empty()


## The capitalised words of [param text] past its first, lower-cased: the
## names a tale carries ("Old Marta lives by the east field" -> ["marta"]).
static func tags(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var words := text.strip_edges().split(" ", false)
	for i in range(1, words.size()):
		var word := words[i].strip_edges().trim_suffix(".").trim_suffix(",").trim_suffix(";").trim_suffix("'s").trim_suffix("’s")
		if word.length() > 1 and word[0] == word[0].to_upper() and word[0] != word[0].to_lower() and not out.has(word.to_lower()):
			out.append(word.to_lower())
	return out


## Whether [param text] touches the world: it names one of lore's names or
## bears one of the world's words. Such a tale stays one person's.
static func is_world(text: String) -> bool:
	var lowered := text.to_lower()
	for name: String in names():
		if not name.is_empty() and RegEx.create_from_string("\\b" + _escape(name) + "\\b").search(lowered) != null:
			return true
	return RegEx.create_from_string(WORLD_WORDS).search(text) != null


static func _escape(text: String) -> String:
	var out := ""
	for ch in text:
		out += ("\\" + ch) if ch in ".^$*+?()[]{}|\\" else ch
	return out


static func key(text: String) -> String:
	return Hearsay._key(text.strip_edges().trim_suffix("."))


## The entry of [param log] saying [param text], or {}.
static func find(log: Array, text: String) -> Dictionary:
	var wanted := key(text)
	for entry: Dictionary in log:
		if key(str(entry.get("text", ""))) == wanted:
			return entry
	return {}


## [param text] said by [param said_by] to [param to] at [param step] goes
## into [param log] as a belief (said again: its last_said), its sayer
## among the holders when they are one of the town's people. The entry.
static func note(log: Array, text: String, said_by: String, to: String, step: int) -> Dictionary:
	var clean := text.strip_edges().trim_suffix(".")
	if clean.is_empty():
		return {}
	var entry := find(log, clean)
	if entry.is_empty():
		entry = {"id": "tm.%d" % (_most(log) + 1), "tier": BELIEF, "text": clean, "said_by": said_by, "to": to, "first_said": step,
			"last_said": step, "holders": [], "spread": 0, "tags": Array(tags(clean)), "world": is_world(clean), "ruling": {}}
		log.append(entry)
		while log.size() > setting("max"):
			var oldest := -1
			for i in log.size():
				if str(log[i].get("tier", "")) == LEFT:
					oldest = i
					break
			log.remove_at(oldest if oldest >= 0 else 0)
	entry["last_said"] = step
	if not said_by.is_empty() and not said_by.begins_with(PLAYER):
		_hold(entry, said_by)
	return entry


## [param holder_id] now believes [param text] (gossip, or a claims ask on
## a player's words): among the holders, the spread up; logged first when
## it was not, said_by [param said_by]. The entry.
static func hold(log: Array, text: String, holder_id: String, said_by: String, step: int) -> Dictionary:
	var entry := find(log, text)
	if entry.is_empty():
		entry = note(log, text, said_by, holder_id, step)
	if entry.is_empty():
		return {}
	entry["last_said"] = step
	_hold(entry, holder_id)
	if str(entry.get("tier", "")) == LEFT:
		entry["tier"] = BELIEF
	return entry


static func _hold(entry: Dictionary, holder_id: String) -> void:
	if holder_id.is_empty() or holder_id.begins_with(PLAYER):
		return
	var holders: Array = entry.get("holders", [])
	if holder_id not in holders:
		holders.append(holder_id)
		entry["holders"] = holders
		entry["spread"] = int(entry.get("spread", 0)) + 1


## [param holder_id] no longer believes [param text] (overturned): off the
## holders; a belief nobody holds is left, kept with its history.
static func drop(log: Array, text: String, holder_id: String) -> Dictionary:
	var entry := find(log, text)
	if entry.is_empty():
		return {}
	var holders: Array = entry.get("holders", [])
	holders.erase(holder_id)
	entry["holders"] = holders
	if holders.is_empty() and str(entry.get("tier", "")) in [BELIEF, CANDIDATE]:
		entry["tier"] = LEFT
	return entry


## A resident's own tale (the speaker's claims ask on their own line,
## 378): each of [param claims] beyond what they know goes into their
## [param heard] as believed ("own": one believes one's own tale) and into
## [param log] as a belief said by [param worker_id] to [param to]. What
## was noted.
static func told(log: Array, heard: Array, worker_id: String, to: String, claims: Array, step: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for claim: Variant in claims:
		if not claim is Dictionary or str(claim.get("fits", "")) != "beyond":
			continue
		var text := str(claim.get("text", "")).strip_edges()
		if text.is_empty():
			continue
		Hearsay.hear(heard, worker_id, 5, text, Hearsay.OWN, "", step)
		var entry := note(log, text, worker_id, to, step)
		if not entry.is_empty():
			out.append(entry)
	return out


## The beliefs of [param log] that are now candidates for town memory at
## [param step]: held by "spread" people in all, still by "held", and
## "hold_days" old, and not of the world; their tier set. Those promoted.
static func candidates(log: Array, step: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var age := setting("hold_days") * maxi(DayNight.day_steps, 1)
	for entry: Dictionary in log:
		if str(entry.get("tier", "")) != BELIEF or bool(entry.get("world", false)):
			continue
		if int(entry.get("spread", 0)) >= setting("spread") and entry.get("holders", []).size() >= setting("held") \
				and step - int(entry.get("first_said", step)) >= age and int(entry.get("rest_until", 0)) <= step:
			entry["tier"] = CANDIDATE
			out.append(entry)
	return out


## The entries of [param log] of [param tier] (every tier for "").
static func of_tier(log: Array, tier: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in log:
		if tier.is_empty() or str(entry.get("tier", "")) == tier:
			out.append(entry)
	return out


## What the town remembers, as the voice is told it: "The town remembers
## that <sentence>." for each memory, oldest first.
static func remembered(log: Array) -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in of_tier(log, MEMORY):
		out.append("The town remembers that %s." % Hearsay._lower_first(str(entry.get("text", ""))))
	return out


static func _most(log: Array) -> int:
	var most := 0
	for entry: Dictionary in log:
		most = maxi(most, str(entry.get("id", "tm.0")).trim_prefix("tm.").to_int())
	return most


# --- Moving in (the lawspeaker, phase 4, decision 460) -----------------------------------

## Trades the talk may name, and the word the town's trades know them by.
const TRADE_WORDS := {"miller": "miller", "smith": "smith", "cook": "cook", "carpenter": "carpenter", "farmer": "farmer",
	"hunter": "hunter", "priest": "priest", "guard": "guard", "healer": "medicine_man", "tanner": "tanner"}
const STAND_IN_TRADE := "hauler"


## The entries of [param log] the lawspeaker ruled move_in ("ready") that
## have not arrived, name someone, and do not touch the world: who may come,
## oldest ruling first.
static func arrivals(log: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in log:
		if bool(entry.get("ready", false)) and str(entry.get("arrived", "")).is_empty() and not bool(entry.get("world", false)) \
				and not entry.get("tags", []).is_empty():
			out.append(entry)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("ruling", {}).get("step", 0)) < int(b.get("ruling", {}).get("step", 0)))
	return out


## The person [param entry] speaks of: {"name": the first name word,
## capitalised ("Old Marta" gives "Marta"), "old": whether the talk calls
## them old, "trade": a trade word in the talk among [param trades] (the
## town's), else the stand-in}.
static func person_of(entry: Dictionary, trades: Array = []) -> Dictionary:
	var tags: Array = entry.get("tags", [])
	if tags.is_empty():
		return {}
	var name := str(tags[0])
	name = name.left(1).to_upper() + name.substr(1)
	var text := str(entry.get("text", "")).to_lower()
	var trade := STAND_IN_TRADE
	for word: String in TRADE_WORDS:
		if RegEx.create_from_string("\\b" + word + "\\b").search(text) != null and (trades.is_empty() or TRADE_WORDS[word] in trades):
			trade = TRADE_WORDS[word]
			break
	return {"name": name, "old": RegEx.create_from_string("(?i)\\bold\\b").search(str(entry.get("text", ""))) != null, "trade": trade}


## Every memory of [param log] that names [param name] (as a word of its
## text, "Marta's" included): the talk that is their card's facts.
static func talk_of(log: Array, name: String) -> Array[String]:
	var out: Array[String] = []
	var named := RegEx.create_from_string("(?i)\\b" + _escape(name.to_lower()) + "\\b")
	for entry: Dictionary in of_tier(log, MEMORY):
		if named.search(str(entry.get("text", ""))) != null:
			out.append(str(entry.get("text", "")))
	return out


# --- The proposals list for Jeff (the lawspeaker, phase 5, decision 458) ---------------

const PAGE_HEAD := """# Proposed to lore

Written by code from the towns' memory logs (decision 458): what each town's lawspeaker (448)
ruled good enough to be the world's. Nothing here is lore until Jeff says so; lore owns this
page. Edit an entry's status line by hand ("open", "agreed", "declined", or words), and the
next rebuild keeps it.
"""


## The chronicle (decision 491): what [param town_name]'s people set down,
## kept by [param keeper], as lines a scholar reads at the desk: the
## heading; oldest first, each MEMORY entry ("On day N the town set down
## that ...", with the lawspeaker's "because"), the newest [param most] of
## them and "The rest is in the book." when cut; then the proposals to
## lore ("proposed", 458) with their status from [param statuses] (458's
## page, keyed "<town id> <entry id>", "open" when none); then the open
## disputes before the lawspeaker ("Before the lawspeaker: ..., says X";
## [param who] names an id). With nothing set down: "The town has set down
## nothing yet." and the first [param lore_most] of [param lore] ("Of
## <town> it is known that ..."). A name at the front of a sentence keeps
## its capital ([param names]).
static func chronicle(log: Array, town_name: String, keeper: String, who: Callable, lore: Array, statuses: Dictionary, town_id := "",
		most := 12, lore_most := 6, names: Array = []) -> Array[String]:
	var day := maxi(DayNight.day_steps, 1)
	var out: Array[String] = ["The chronicle of %s, kept by %s." % [town_name, keeper]]
	var memories := of_tier(log, MEMORY)
	var cut := memories.size() > most
	if cut:
		memories = memories.slice(memories.size() - most)
	for entry: Dictionary in memories:
		var ruling: Dictionary = entry.get("ruling", {})
		var step := int(ruling.get("step", entry.get("first_said", 0)))
		var line := "On day %d the town set down that %s." % [int(step / day), clause(str(entry.get("text", "")), names)]
		var because := str(ruling.get("because", "")).strip_edges()
		if not because.is_empty():
			line += " The lawspeaker's word: %s." % because.trim_suffix(".")
		out.append(line)
	if cut:
		out.append("The rest is in the book.")
	for entry: Variant in log:
		if entry is Dictionary and bool(entry.get("proposed", false)):
			var status := str(statuses.get("%s %s" % [town_id, entry.get("id", "")], "open"))
			out.append("Proposed to the lore-keepers on day %d: %s (%s)." % [int(int(entry.get("ruling", {}).get("step", 0)) / day),
				clause(str(entry.get("text", "")), names), status])
	for entry: Variant in log:
		if entry is Dictionary and bool(entry.get("dispute", false)) and str(entry.get("tier", "")) in [BELIEF, CANDIDATE] and entry.get("ruling", {}).is_empty():
			out.append("Before the lawspeaker: %s, says %s." % [clause(str(entry.get("text", "")), names), _name(who, str(entry.get("said_by", "")))])
	if out.size() == 1:
		out.append("The town has set down nothing yet.")
		for i in mini(lore.size(), lore_most):
			out.append("Of %s it is known that %s." % [town_name, clause(str(lore[i]), names)])
	return out


## [param text] as a clause after "that": no full stop, its first letter
## lowered unless its first word is one of [param names] (a deed starts
## with its doer).
static func clause(text: String, names: Array = []) -> String:
	var clean := text.strip_edges().trim_suffix(".")
	var first := clean.get_slice(" ", 0).trim_suffix(",").trim_suffix("'s")
	return clean if first in names else Hearsay._lower_first(clean)


## The page: one section per town of [param logs] (town id -> log), named
## by [param names] (town id -> display name), people named by [param who]
## (worker id -> words), each "proposed" entry a block with its source,
## holders, the ruling's day and why, and a status line: the one in
## [param statuses] (entry key -> status), else "open". Oldest first.
static func proposed_page(logs: Dictionary, names: Dictionary, who: Callable, statuses: Dictionary = {}) -> String:
	var out := PAGE_HEAD
	var towns: Array = logs.keys()
	towns.sort()
	var day := maxi(DayNight.day_steps, 1)
	var any := false
	for town: String in towns:
		var entries: Array[Dictionary] = []
		for entry: Variant in logs[town]:
			if entry is Dictionary and bool(entry.get("proposed", false)):
				entries.append(entry)
		if entries.is_empty():
			continue
		any = true
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("ruling", {}).get("step", 0)) < int(b.get("ruling", {}).get("step", 0)))
		out += "\n## %s (%s)\n" % [names.get(town, town), town]
		for entry: Dictionary in entries:
			var key := "%s %s" % [town, entry.get("id", "")]
			var ruling: Dictionary = entry.get("ruling", {})
			var holders: Array[String] = []
			for id: Variant in entry.get("holders", []):
				holders.append(_name(who, str(id)))
			var ruled := int(ruling.get("step", 0))
			out += "\n### %s: %s\n" % [entry.get("id", ""), entry.get("text", "")]
			out += "- first said by %s to %s, on day %d; held by %s (%d of %d who heard it)\n" % [_name(who, str(entry.get("said_by", ""))),
				_name(who, str(entry.get("to", ""))), int(int(entry.get("first_said", 0)) / day), ", ".join(holders) if not holders.is_empty() else "nobody now",
				entry.get("holders", []).size(), int(entry.get("spread", 0))]
			out += "- proposed on day %d%s\n" % [int(ruled / day), ": " + str(ruling.get("because", "")) if not str(ruling.get("because", "")).is_empty() else ""]
			out += "- status: %s\n" % str(statuses.get(key, "open"))
	if not any:
		out += "\nNothing proposed yet.\n"
	return out


static func _name(who: Callable, id: String) -> String:
	if id.is_empty():
		return "someone"
	if id.begins_with(PLAYER):
		return "a traveller"
	if who.is_valid():
		var words: Variant = who.call(id)
		if words is String and not words.is_empty():
			return words
	return id


## The statuses written by hand into [param page] (a page proposed_page
## made): entry key ("<town> <id>") -> status, from each "- status:" line
## under its "### <id>" heading in its "## <name> (<town>)" section.
static func proposed_statuses(page: String) -> Dictionary:
	var out := {}
	var town := ""
	var id := ""
	for line: String in page.split("\n"):
		if line.begins_with("## ") and line.ends_with(")") and line.contains("("):
			town = line.substr(line.rfind("(") + 1).trim_suffix(")")
		elif line.begins_with("### "):
			id = line.substr(4).get_slice(":", 0).strip_edges()
		elif line.begins_with("- status:") and not town.is_empty() and not id.is_empty():
			out["%s %s" % [town, id]] = line.substr(9).strip_edges()
	return out
