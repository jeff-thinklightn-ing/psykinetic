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
## A thing a neighbour saw herself, passed on as gossip (decision 422):
## believed always.
const WITNESSED := "witnessed"
## One's own tale (the town memory log, the lawspeaker's phase 1): believed for sure.
const OWN := "own"
## Where gossip is heard (Townsfolk.PLACES' meeting places), in words.
const PLACE_WORDS := {"well": "at the well", "inn": "at the inn", "square": "in the square", "temple": "at the temple"}
## Words that make a line worth a claims ask: a statement about something,
## not a greeting or a bare question.
## Words that make a claim an omen when the claims ask did not say.
const OMEN_WORDS := "(?i)\\b(curse\\w*|haunt\\w*|ghost\\w*|spirit\\w*|omen\\w*|witch\\w*|magic\\w*|hex\\w*|demon\\w*|spell\\w*|sign from|the gods?)\\b"
const CLAIM_WORDS := "(?i)\\b(is|are|was|were|has|have|had|will|did|lives?|died|dead|cursed|haunted|hidden|buried|says?|said|told|knows?|there's|there is|there are)\\b"

## The claims ask's system prompt: the hearer, what they know, what they
## already hold, and the line.
const CLAIMS_SYSTEM := """You keep track of what %s, %s, has heard said about the world. You are given what %s knows to be true, what %s has heard before (each with an id), and a line someone just said near them.
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
	if fits == WITNESSED or fits == OWN:
		return 1.0  # A neighbour saying what she saw herself is no rumour (decision 422); one's own tale neither.
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
## sets the curve; [param step] is when. [param where] is the place it was
## heard (gossip, decision 422: "well", "inn", "square", "temple"), "" for
## a line said to them.
static func hear(heard: Array, who: String, intellect: int, claim: String, fits: String, from: String, step: int,
		omen := false, superstition := 5, where := "") -> Dictionary:
	var text := claim.strip_edges().trim_suffix(".")
	if text.is_empty() or fits not in ["against", "beyond", WITNESSED, OWN]:
		return {}
	for entry: Dictionary in heard:
		if _key(str(entry.get("text", ""))) == _key(text) and str(entry.get("from", "")) == from:
			return {}
	var chance := p_believe(fits, intellect, omen, superstition)
	var rolled := roll(who, text)
	var entry := {"id": _next_id(heard), "text": text, "from": from, "step": step, "fits": fits, "omen": omen,
		"believed": rolled < chance, "roll": snappedf(rolled, 0.001), "chance": snappedf(chance, 0.001)}
	if not where.is_empty():
		entry["where"] = where
	heard.append(entry)
	_cap(heard)
	return entry


## Whether [param heard] holds [param text] already, from anyone.
static func holds(heard: Array, text: String) -> bool:
	var key := _key(text.strip_edges().trim_suffix("."))
	for entry: Dictionary in heard:
		if _key(str(entry.get("text", ""))) == key:
			return true
	return false


## Where a thing was heard, in words: "at the well"; "" for no place.
static func place_words(place: String) -> String:
	return str(PLACE_WORDS.get(place, ""))


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
		var where := place_words(str(entry.get("where", "")))
		said.append("%s told you%s that %s." % [from if not from.is_empty() else "Someone",
			" " + where if not where.is_empty() else "", _lower_first(str(entry["text"]))])
	if said.is_empty():
		return ""
	return "You have heard, and believe it though you are not sure: %s" % " ".join(said)


## The claims ask for [param line] said by [param from] near [param person]
## (who knows [param known], sentences, and holds [param heard]): the facts
## channel's shape (CompanionMind.facts). [param who_is] says who they are
## ("who travels with Jeff": a companion's, decision 442).
static func claims_ask(person: String, known: Array[String], heard: Array, from: String, line: String, serial: int,
		who_is := "who lives in a town") -> Dictionary:
	var system := CLAIMS_SYSTEM % [person, who_is, person, person, person]
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


## [param text] with its first letter lowered to follow "It is said that" and the like, unless its
## first word is a name (lore's finding, 2026-11-10: "It is said that umbrage is cursed"; Hollowfell,
## Brand, Aldous and Snagfin the same): is_name. "I" ("I'll", "I'm", "I've", "I'd") keeps its capital, and
## so does a place's name of several words that opens it ("Hall of Fallen Souls", "First Hall": _phrases;
## the coordinator's rule, 2026-11-11).
static func _lower_first(text: String) -> String:
	if text.length() <= 1 or text.substr(1, 1) != text.substr(1, 1).to_lower():
		return text
	var first := RegEx.create_from_string("^[A-Za-z]+(?:-[a-z]+)*").search(text)  # "Mound-breakers" whole.
	if first != null and (first.get_string() == "I" or is_name(first.get_string())):
		return text
	for phrase: String in _phrases:
		if text.begins_with(phrase) and (text.length() == phrase.length() or not _is_letter(text.unicode_at(phrase.length()))):
			return text
	return text.left(1).to_lower() + text.substr(1)


static func _is_letter(code: int) -> bool:
	return (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 39


## The names the game's own texts use (NAME_FILES), read once. Always a name: a value that is one
## capitalized word (a names list's, "Rook", "Wren"), a person's name in lore (an entry of type
## "person": "Wren", "Pip"), and the name of a title ("Brand the Ox"), whatever else the texts write
## in small letters (the coordinator's rule, 2026-11-11, after voice's keep-list). A word they write
## capitalized mid-sentence (after a small letter or a comma; "Mound-breakers" with its hyphen) is a
## name unless they also write it in small letters in prose ("Old Marta" is old Marta: "old" is a
## word; an id like "hollowfell" is not prose).
const NAME_FILES: Array[String] = ["res://levels/lore/", "res://levels/residents.json", "res://levels/economy.json",
	"res://levels/townsfolk.json", "res://levels/companion_traits.json", "res://levels/named_enemies.json"]
static var _names: Dictionary = {}
## The names of several words (_lower_first): those NAME_FILES write mid-sentence ("the Hall of Fallen
## Souls", "the Old Tower") and the levels' own names without their "The" (level.json "name"); filled by is_name.
static var _phrases: Array[String] = []
static var _names_read := false


## Whether [param word] is a name (_names): "Umbrage" yes, "Raiders" no.
static func is_name(word: String) -> bool:
	if not _names_read:
		_names_read = true
		var mid := RegEx.create_from_string("[a-z,] ([A-Z][a-z']+(?:-[a-z]+)*)")
		var capital := RegEx.create_from_string("[A-Z][a-z']+")
		var lone := RegEx.create_from_string("^[A-Z][a-z']+$")
		var titled := RegEx.create_from_string("^([A-Z][a-z']+) the [A-Z]")
		var small := RegEx.create_from_string("(?:^|(?<=[ (\"]))([a-z][a-z']+)(?=[ ,.;:!?)\"]|$)")
		var phrase := RegEx.create_from_string("(?<=[a-z,] )([A-Z][a-z']+(?: (?:of the |of |the )?[A-Z][a-z']+)+)")
		var phrases := {}
		var whole := RegEx.create_from_string("^[A-Z][a-z']+(?: (?:of the |of |the )?[A-Z][a-z']+)+$")
		var words := {}
		var titles := {}  # Always names: titles', names lists' and lore's people's.
		var files: Array[String] = []
		for path: String in NAME_FILES:
			if path.ends_with("/"):
				for file: String in DirAccess.get_files_at(path):
					if file.ends_with(".json"):
						files.append(path + file)
			else:
				files.append(path)
		for path: String in files:
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
			var pending: Array = [parsed]
			while not pending.is_empty():
				var value: Variant = pending.pop_back()
				if value is Dictionary:
					pending.append_array((value as Dictionary).values())
					if value.get("type") == "person" and value.get("name") is String:
						for found: RegExMatch in capital.search_all(str(value["name"])):
							titles[found.get_string()] = true
						if whole.search(str(value["name"])) != null:
							phrases[str(value["name"])] = true
				elif value is Array:
					pending.append_array(value)
				elif value is String:
					if lone.search(value) != null:
						titles[value] = true
					elif whole.search(value) != null:
						phrases[value] = true  # A names list's of several words: "Old Tam", "Brother Cuth".
					var title := titled.search(value)
					if title != null:
						titles[title.get_string(1)] = true
					for found: RegExMatch in mid.search_all(value):
						_names[found.get_string(1)] = true
					for found: RegExMatch in phrase.search_all(value):
						phrases[found.get_string(1)] = true
					if value.contains(" "):  # Prose, not an id ("hollowfell", "snagfin").
						for found: RegExMatch in small.search_all(value):
							words[found.get_string(1)] = true
		for name: String in _names.keys():
			if words.has(name.to_lower()):
				_names.erase(name)
		_names.merge(titles)
		var dirs: Array[String] = []
		for dir: String in DirAccess.get_directories_at("res://levels/"):
			dirs.append("res://levels/" + dir)
			for inner: String in DirAccess.get_directories_at("res://levels/" + dir):
				dirs.append("res://levels/%s/%s" % [dir, inner])
		for dir: String in dirs:
			var path := dir + "/level.json"
			var level: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
			var pending: Array = [level]
			while not pending.is_empty():  # Its own name and its rooms' and buildings' ("The First Hall").
				var value: Variant = pending.pop_back()
				if value is Array:
					pending.append_array(value)
				elif value is Dictionary:
					pending.append_array((value as Dictionary).values())
					var title := str(value.get("name", "")) if value.get("name") is String else ""
					if title.begins_with("The "):
						title = title.substr(4)
					if whole.search(title) != null:  # Every word a capital's but "of" and "the" ("Common room" is none).
						phrases[title] = true
		_phrases.assign(phrases.keys())
	return _names.has(word)
