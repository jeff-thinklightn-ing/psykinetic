class_name Hearsay
extends RefCounted
## What a resident has heard said of the world, and whether they believe
## it (decision 378, Jeff's of 2026-10-17: townsfolk don't fabricate; they
## keep what they hear and decide, and an intellect sets how easily a
## falsehood takes). Kept on the resident's worker record (Production's
## "heard", saved with it; "intellect", 1..10, rolled at founding: economy's):
## [{id, text, from, step, fits, believed}], at most "max" of them. A claim
## comes from a claims ask (claims_ask: one cheap call on the resident mind,
## Main's) on a line said to them or near them: it agrees with what lore
## says they know (kept nowhere: it is lore already), goes against it, or
## is beyond it; the last two are believed by a seeded roll under the
## intellect's curve (residents.json "hearsay"). A believed claim reaches a
## townsfolk's or a free role's voice as hearsay, naming who said it, never
## as fact; an official's (Lore.binding) never. A claim of an omen, a curse
## or the like is believed the more readily by a superstitious role (Jeff's
## role profiles, Lore.profile: the higher of the two chances, "omen"'s
## curve on superstition). A later claims ask may show
## a held one false: it is then no longer believed. Nothing here is ever
## written to lore.

const FILE := "res://levels/residents.json"
const DEFAULTS := {"max": 8, "shown": 3, "claims_ticks": 150, "against": [7, 6], "beyond": [11, 10], "omen": [3, 6], "min_words": 4}
## Words that make a line worth a claims ask: a statement about something,
## not a greeting or a bare question.
## Words that make a claim an omen when the claims ask did not say.
const OMEN_WORDS := "(?i)\\b(curse\\w*|haunt\\w*|ghost\\w*|spirit\\w*|omen\\w*|witch\\w*|magic\\w*|hex\\w*|demon\\w*|spell\\w*|sign from|the gods?)\\b"
const CLAIM_WORDS := "(?i)\\b(is|are|was|were|has|have|had|will|did|lives?|died|dead|cursed|haunted|hidden|buried|says?|said|told|knows?|there's|there is|there are)\\b"

## The claims ask's system prompt: the hearer, what they know, what they
## already hold, and the line.
const CLAIMS_SYSTEM := """You keep track of what %s, who lives in a town, has heard said about the world. You are given what %s knows to be true, what %s has heard before (each with an id), and a line someone just said near them.
List each claim the line makes about the world: places, people, peoples, events, the town, the land. Leave out greetings, questions, feelings, plans, and what the speaker says of themselves. Write each claim as one short plain sentence. For each, say whether it agrees with what %s knows to be true ("agrees"), goes against it ("against"), or says something beyond it ("beyond"), and whether it is of omens, curses, spirits or the like ("omen": true). Then list the ids of anything heard before that this line plainly shows to be false. Usually there is no claim. Reply with one JSON object and nothing else:
{"facts": [{"text": "...", "fits": "agrees|against|beyond", "omen": false}], "overturns": ["..."]}"""


static var _settings := {}


## A setting of residents.json's "hearsay" (DEFAULTS' when not given).
static func setting(key: String) -> Variant:
	if _settings.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE)) if FileAccess.file_exists(FILE) else null
		_settings = DEFAULTS.duplicate()
		if data is Dictionary and data.get("hearsay") is Dictionary:
			_settings.merge(data["hearsay"], true)
	return _settings.get(key, DEFAULTS.get(key))


## How likely a claim that [param fits] ("against" or "beyond") is believed
## by one of [param intellect]: max(0, (a - intellect) / b), clamped to 1,
## from the setting [a, b] of that name; 0 for anything else. An [param omen]
## beyond what they know: the higher of that and max(0, (superstition - a)
## / b), "omen"'s [a, b].
static func p_believe(fits: String, intellect: int, omen := false, superstition := 5) -> float:
	if fits not in ["against", "beyond"]:
		return 0.0
	var curve: Array = setting(fits)
	var chance := clampf((float(curve[0]) - intellect) / maxf(float(curve[1]), 1.0), 0.0, 1.0)
	if omen and fits == "beyond":
		var omens: Array = setting("omen")
		chance = maxf(chance, clampf((superstition - float(omens[0])) / maxf(float(omens[1]), 1.0), 0.0, 1.0))
	return chance


## Whether [param claim] is of omens and the like: as the claims ask said
## ([param said]: its "omen", null when it gave none), else by OMEN_WORDS.
static func is_omen(claim: String, said: Variant = null) -> bool:
	if said is bool:
		return said
	return RegEx.create_from_string(OMEN_WORDS).search(claim) != null


## A roll in [0, 1), the same for [param who] and [param text] every time.
static func roll(who: String, text: String) -> float:
	return float(absi(hash("%s|%s" % [who, _key(text)])) % 100000) / 100000.0


## Whether [param line] may hold a claim, worth a claims ask.
static func worth_asking(line: String) -> bool:
	var words := line.strip_edges().split(" ", false)
	if words.size() < int(setting("min_words")):
		return false
	var trimmed := line.strip_edges()
	if trimmed.ends_with("?") and trimmed.count(".") == 0 and trimmed.count("!") == 0:
		return false
	return RegEx.create_from_string(CLAIM_WORDS).search(line) != null


## [param claim] said by [param from] heard: kept in [param heard] (a
## worker's "heard", changed in place) with whether it is believed, unless
## it agrees with what they know or is held already from them; the entry
## kept, or {}. [param who] seeds the roll (the worker id); [param intellect]
## sets the curve; [param step] is when.
static func hear(heard: Array, who: String, intellect: int, claim: String, fits: String, from: String, step: int,
		omen := false, superstition := 5) -> Dictionary:
	var text := claim.strip_edges().trim_suffix(".")
	if text.is_empty() or fits not in ["against", "beyond"]:
		return {}
	for entry: Dictionary in heard:
		if _key(str(entry.get("text", ""))) == _key(text) and str(entry.get("from", "")) == from:
			return {}
	var chance := p_believe(fits, intellect, omen, superstition)
	var rolled := roll(who, text)
	var entry := {"id": _next_id(heard), "text": text, "from": from, "step": step, "fits": fits, "omen": omen,
		"believed": rolled < chance, "roll": snappedf(rolled, 0.001), "chance": snappedf(chance, 0.001)}
	heard.append(entry)
	_cap(heard)
	return entry


## The entries of [param heard] whose id is in [param ids], no longer
## believed; those changed.
static func overturn(heard: Array, ids: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var wanted := ids.map(func(each: Variant) -> String: return str(each))
	for entry: Dictionary in heard:
		if str(entry.get("id", "")) in wanted and bool(entry.get("believed", false)):
			entry["believed"] = false
			entry["overturned"] = true
			out.append(entry)
	return out


## The newest "shown" believed entries of [param heard], oldest first.
static func believed(heard: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in heard:
		if bool(entry.get("believed", false)):
			out.append(entry)
	return out.slice(maxi(out.size() - int(setting("shown")), 0))


## What a voice is told of [param heard]: "" for none, else a sentence
## naming who said each, as hearsay.
static func prompt_words(heard: Array) -> String:
	var said: Array[String] = []
	for entry in believed(heard):
		var from := str(entry.get("from", ""))
		said.append("%s told you that %s." % [from if not from.is_empty() else "Someone", _lower_first(str(entry["text"]))])
	if said.is_empty():
		return ""
	return "You have heard, and believe it though you are not sure: %s" % " ".join(said)


## The claims ask for [param line] said by [param from] near [param person]
## (who knows [param known], sentences, and holds [param heard]): the facts
## channel's shape (CompanionMind.facts).
static func claims_ask(person: String, known: Array[String], heard: Array, from: String, line: String, serial: int) -> Dictionary:
	var system := CLAIMS_SYSTEM % [person, person, person, person]
	var held: Array[String] = []
	for entry: Dictionary in heard:
		held.append("- [%s] %s (from %s)" % [entry.get("id", ""), entry.get("text", ""), entry.get("from", "someone")])
	var user := "What %s knows to be true:\n%s\n\nWhat %s has heard before:\n%s\n\n%s just said: \"%s\"" % [
		person, "\n".join(known.map(func(each: String) -> String: return "- " + each)) if not known.is_empty() else "- nothing of the world beyond the town",
		person, "\n".join(held) if not held.is_empty() else "- nothing yet", from, line]
	return {"kind": "facts", "serial": serial, "trigger": "%s heard %s" % [person, from], "speaker": person, "system": system, "user": user,
		"messages": [{"role": "system", "content": system}, {"role": "user", "content": user}], "heard": line}


## Over the cap: the oldest not believed goes, else the oldest.
static func _cap(heard: Array) -> void:
	while heard.size() > int(setting("max")):
		var gone := 0
		for i in heard.size():
			if not bool(heard[i].get("believed", false)):
				gone = i
				break
		heard.remove_at(gone)


static func _next_id(heard: Array) -> String:
	var most := 0
	for entry: Dictionary in heard:
		most = maxi(most, str(entry.get("id", "h0")).trim_prefix("h").to_int())
	return "h%d" % (most + 1)


static func _key(text: String) -> String:
	return RegEx.create_from_string("[^a-z0-9 ]").sub(text.to_lower(), "", true).strip_edges()


static func _lower_first(text: String) -> String:
	return text.left(1).to_lower() + text.substr(1) if text.length() > 1 and text.substr(1, 1) == text.substr(1, 1).to_lower() else text
