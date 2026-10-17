class_name Lore
extends RefCounted
## The world's facts, read once from levels/lore/ (DIR: the entries of
## FILES, and knowers.json), as docs/lore/README.md describes them
## (decisions 257, 258). known_by says what one knower knows: the facts a
## prompt may state for that character, never lines to say.
##
## A fact counts only when its status and its entry's are both agreed (or,
## asked for with least "draft", agreed or draft; asked is an open question
## and never counts). A knower must pass the same gate. A knower knows the
## common facts and rumours whose where meets its own (or is empty), those
## sharing a tag with its tags wherever they are, and the secret and lived
## facts that name it. A rumour comes back as hearsay and a lived fact as
## memory; whether a rumour is true stays here.
##
## names.json (decision 366) says how things are named: forms by how a name
## came (holder, deed, maker) and lore's word for a thing, under the same
## gate. Items stores a name as {form, holder, ...} and render_name fills it
## at display time, so a reforged thing keeps its name with its new word.

const DIR := "res://levels/lore/"
const FILES := ["world", "factions", "regions", "materials", "people", "history"]
const KNOWN := ["common", "rumour", "secret", "lived"]
## A fact's weight when it gives none: how much it matters beside others,
## for a prompt that has room for only some. Left at this until Jeff weighs
## them.
const DEFAULT_WEIGHT := 1.0
## How a name came, and what a form may be filled from.
const NAME_HOWS := ["holder", "deed", "maker"]
const NAME_SLOTS := ["holder", "thing", "deed", "maker"]

static var _entries: Dictionary = {}
static var _knowers: Dictionary = {}
static var _forms: Array = []
static var _things: Array = []
static var _names_read := false


## Every entry by id, read on first use.
static func entries() -> Dictionary:
	_load()
	return _entries


## Every knower by id, read on first use.
static func knowers() -> Dictionary:
	_load()
	return _knowers


## Forgets what was read, so the next ask reads the files again (a data
## file live-reloaded).
static func reload() -> void:
	_entries = {}
	_knowers = {}
	_forms = []
	_things = []
	_names_read = false


## Uses [param entry_list] and [param knower_list] (and, given, the name
## forms and thing words) in place of the files (tests, tools).
static func use(entry_list: Array, knower_list: Array, form_list := [], thing_list := []) -> void:
	_entries = {}
	_knowers = {}
	_forms = form_list.filter(func(form: Variant) -> bool: return form is Dictionary)
	_things = thing_list.filter(func(thing: Variant) -> bool: return thing is Dictionary)
	_names_read = true
	for entry: Variant in entry_list:
		if entry is Dictionary and entry.get("id") is String:
			_entries[entry["id"]] = entry
	for knower: Variant in knower_list:
		if knower is Dictionary and knower.get("id") is String:
			_knowers[knower["id"]] = knower


## What [param knower] knows, in file order: [{id, text, hearsay, memory,
## where, weight}] (where: the fact's region ids; weight: its own, else
## DEFAULT_WEIGHT). [param about], when given, keeps the facts on any of
## those topics (_about). [param least] is "agreed" (what code uses) or
## "draft" (to preview drafts).
static func known_by(knower: String, about := PackedStringArray(), least := "agreed") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var who: Dictionary = knowers().get(knower, {})
	if who.is_empty() or not _counts(str(who.get("status", "")), least):
		return out
	var where: Array = who.get("where", [])
	var tags: Array = who.get("tags", [])
	for id: String in entries():
		var entry: Dictionary = _entries[id]
		var entry_status := str(entry.get("status", ""))
		if not _counts(entry_status, least):
			continue
		for fact: Variant in entry.get("facts", []):
			if fact is not Dictionary or not _counts(str(fact.get("status", entry_status)), least):
				continue
			var known := str(fact.get("known", ""))
			var knows := false
			match known:
				"common", "rumour":
					var at: Array = fact.get("where", [])
					knows = at.is_empty() or _meets(at, where) or _meets(fact.get("tags", []), tags)
				"secret", "lived":
					knows = knower in fact.get("knowers", [])
			if knows and (about.is_empty() or _about(fact, entry, about)):
				out.append({"id": fact.get("id", ""), "text": fact.get("text", ""),
						"hearsay": known == "rumour", "memory": known == "lived",
						"where": fact.get("where", []).duplicate(), "weight": float(fact.get("weight", DEFAULT_WEIGHT))})
	return out


## The name forms that count ([param least] as for known_by), in file
## order: [{id, how, form}], those of [param how] when given.
static func name_forms(how := "", least := "agreed") -> Array[Dictionary]:
	_load_names()
	var out: Array[Dictionary] = []
	for form: Dictionary in _forms:
		if _counts(str(form.get("status", "")), least) and (how.is_empty() or form.get("how") == how):
			out.append({"id": str(form.get("id", "")), "how": str(form.get("how", "")), "form": str(form.get("form", ""))})
	return out


## Lore's word for a thing ([param item_id] first, then any of [param tags]),
## or "" when it has none and the item's own word stands.
static func thing_word(item_id: String, tags := PackedStringArray(), least := "agreed") -> String:
	_load_names()
	for pass_tags: bool in [false, true]:
		for thing: Dictionary in _things:
			var match_for: Variant = thing.get("for")
			if _counts(str(thing.get("status", "")), least) and (match_for in tags if pass_tags else match_for == item_id):
				return str(thing.get("words", ""))
	return ""


## A stored name ([param name]: {form, holder, deed, maker}) as text, its
## {thing} lore's word for the item or else [param noun] (the item's own).
## The form is used whatever its status now, so a name given stays given (the
## thing's word goes by [param least]); "" when the form is unknown or a slot
## it needs is empty.
static func render_name(name: Dictionary, item_id: String, tags := PackedStringArray(), noun := "", least := "agreed") -> String:
	_load_names()
	var text := ""
	for form: Dictionary in _forms:
		if form.get("id") == name.get("form"):
			text = str(form.get("form", ""))
	if text.is_empty():
		return ""
	var word := thing_word(item_id, tags, least)
	var slots := {"holder": str(name.get("holder", "")), "thing": word if not word.is_empty() else noun,
			"deed": str(name.get("deed", "")), "maker": str(name.get("maker", ""))}
	for slot: String in NAME_SLOTS:
		var key := "{%s}" % slot
		if text.contains(key):
			if slots[slot].is_empty():
				return ""
			text = text.replace(key, slots[slot])
	return text


## Whether [param fact] (in [param entry]) is on one of the topics in
## [param about]: a topic that is one of the fact's or the entry's tags or
## the entry's id, or a word or phrase of its text or the entry's name
## (whole words, any case, a plural "s" allowed: "ore" finds "ores").
static func _about(fact: Dictionary, entry: Dictionary, about: PackedStringArray) -> bool:
	var tags: Array = fact.get("tags", []) + entry.get("tags", []) + [entry.get("id", "")]
	var words := " %s %s " % [_words(str(fact.get("text", ""))), _words(str(entry.get("name", "")))]
	for topic: String in about:
		var each := _words(topic)
		if each.is_empty():
			continue
		if each in tags or each.replace(" ", "_") in tags or words.contains(" %s " % each) or words.contains(" %ss " % each):
			return true
	return false


## [param text] lower case, with everything but letters, digits and
## hyphens turned to single spaces.
static func _words(text: String) -> String:
	var out := ""
	for c in text.to_lower():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "-" else " "
	return " ".join(out.split(" ", false))


static func _counts(status: String, least: String) -> bool:
	return status == "agreed" or (least == "draft" and status == "draft")


static func _meets(a: Array, b: Array) -> bool:
	for each: Variant in a:
		if each in b:
			return true
	return false


static func _load() -> void:
	if not _entries.is_empty():
		return
	for file: String in FILES:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + file + ".json"))
		if data is not Dictionary or data.get("entries") is not Array:
			push_warning("Lore: %s%s.json has no entries list" % [DIR, file])
			continue
		for entry: Variant in data["entries"]:
			if entry is Dictionary and entry.get("id") is String:
				_entries[entry["id"]] = entry
	var known: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "knowers.json"))
	if known is Dictionary and known.get("knowers") is Array:
		for knower: Variant in known["knowers"]:
			if knower is Dictionary and knower.get("id") is String:
				_knowers[knower["id"]] = knower


static func _load_names() -> void:
	if _names_read:
		return
	_names_read = true
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "names.json"))
	if data is not Dictionary or data.get("forms") is not Array or data.get("things") is not Array:
		push_warning("Lore: %snames.json has no forms and things lists" % DIR)
		return
	_forms = data["forms"].filter(func(form: Variant) -> bool: return form is Dictionary)
	_things = data["things"].filter(func(thing: Variant) -> bool: return thing is Dictionary)
