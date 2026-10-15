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

const DIR := "res://levels/lore/"
const FILES := ["world", "factions", "regions", "materials", "people", "history"]
const KNOWN := ["common", "rumour", "secret", "lived"]

static var _entries: Dictionary = {}
static var _knowers: Dictionary = {}


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


## Uses [param entry_list] and [param knower_list] in place of the files
## (tests, tools).
static func use(entry_list: Array, knower_list: Array) -> void:
	_entries = {}
	_knowers = {}
	for entry: Variant in entry_list:
		if entry is Dictionary and entry.get("id") is String:
			_entries[entry["id"]] = entry
	for knower: Variant in knower_list:
		if knower is Dictionary and knower.get("id") is String:
			_knowers[knower["id"]] = knower


## What [param knower] knows, in file order: [{id, text, hearsay, memory}].
## [param least] is "agreed" (what code uses) or "draft" (to preview drafts).
static func known_by(knower: String, least := "agreed") -> Array[Dictionary]:
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
			if knows:
				out.append({"id": fact.get("id", ""), "text": fact.get("text", ""),
						"hearsay": known == "rumour", "memory": known == "lived"})
	return out


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
