extends Node
## Lore: every file under levels/lore/ follows docs/lore/README.md (decisions
## 257, 258): entries and facts have unique ids, a known type, status and
## knowledge level; an asked one names its question; relations, where and
## knowers name ids that exist; a rumour says whether it is true; ids shared
## with other files (factions, resources, place kinds, items, levels) are
## theirs.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const DIR := "res://levels/lore/"
const FILES := ["world", "factions", "regions", "materials", "people", "history"]
const TYPES := ["world", "faction", "people", "region", "place", "material", "person", "weapon", "event"]
const STATUSES := ["agreed", "draft", "asked"]
const KNOWN := ["common", "rumour", "secret", "lived"]
const RELATIONS := ["in", "holds", "enemy", "feud", "ally", "from", "member", "carries", "took", "held_at"]

var _failures := 0
var _entries := {}
var _knowers := {}


func _ready() -> void:
	_test_read()
	_test_entries()
	_test_facts()
	_test_shared_ids()
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _read(file: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(DIR + file + ".json"))


func _test_read() -> void:
	print("\n== every lore file reads, ids unique across them ==")
	var dupes: Array = []
	for file in FILES:
		var data: Variant = _read(file)
		_check(data is Dictionary and data.get("entries") is Array, "%s.json is {entries: [...]}" % file)
		if not data is Dictionary:
			continue
		for entry in data.get("entries", []):
			if _entries.has(entry.get("id")):
				dupes.append(entry.get("id"))
			_entries[entry.get("id")] = entry
	_check(dupes.is_empty(), "entry ids are unique across the files %s" % [dupes])
	var known: Variant = _read("knowers")
	_check(known is Dictionary and known.get("knowers") is Array, "knowers.json is {knowers: [...]}")
	for knower in known.get("knowers", []) if known is Dictionary else []:
		_knowers[knower.get("id")] = knower


func _test_entries() -> void:
	print("\n== an entry has an id, a known type and status, a source and a summary ==")
	var bad: Array = []
	for id in _entries:
		var entry: Dictionary = _entries[id]
		var ok: bool = id is String and _is_id(id) and entry.get("type") in TYPES and _status_ok(entry) \
				and entry.get("name") is String and entry.get("source") is String \
				and entry.get("summary") is String and entry.get("facts") is Array
		for relation in entry.get("relations", []):
			ok = ok and relation.get("kind") in RELATIONS and _entries.has(relation.get("to"))
		if not ok:
			bad.append(id)
	_check(bad.is_empty(), "every entry is well formed, its relations to known entries %s" % [bad])
	bad = []
	for id in _knowers:
		var knower: Dictionary = _knowers[id]
		if not (_is_id(id) and _status_ok(knower) and _regions_ok(knower.get("where")) and knower.get("tags") is Array):
			bad.append(id)
	_check(bad.is_empty(), "every knower is well formed, its where regions %s" % [bad])


func _test_facts() -> void:
	print("\n== a fact belongs to its entry, says who knows it, and states no line ==")
	var bad: Array = []
	var ids := {}
	for id in _entries:
		for fact in _entries[id]["facts"]:
			var fid: Variant = fact.get("id")
			var ok: bool = fid is String and fid.begins_with(id + ".") and not ids.has(fid) \
					and fact.get("text") is String and fact.get("known") in KNOWN \
					and _regions_ok(fact.get("where")) and _status_ok(fact, false)
			ids[fid] = true
			var known: Variant = fact.get("known")
			if known == "rumour":
				ok = ok and fact.get("true") is bool
			if known == "secret" or known == "lived":
				ok = ok and fact.get("knowers") is Array and not fact["knowers"].is_empty()
			for knower in fact.get("knowers", []):
				ok = ok and _knowers.has(knower)
			# A line to say would be quoted speech.
			ok = ok and not String(fact.get("text", "")).contains("\"")
			if not ok:
				bad.append(fid)
	_check(bad.is_empty(), "every fact is well formed %s" % [bad])
	_check(not ids.is_empty(), "there are facts (%d)" % ids.size())


func _test_shared_ids() -> void:
	print("\n== ids shared with other files are theirs ==")
	var factions: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://levels/factions.json"))
	var bad: Array = []
	for id in _entries:
		var entry: Dictionary = _entries[id]
		match entry["type"]:
			"faction":
				# A new faction waits for maps to add its key before it can be agreed.
				if entry["status"] == "agreed" and not factions.has(id):
					bad.append(id)
			"material":
				if entry.has("resource") and not entry["resource"] in Stockpile.RESOURCES:
					bad.append(id)
			"place":
				if entry.has("place_kind") and not entry["place_kind"] in Level.PLACE_KINDS:
					bad.append(id)
				if entry.has("level") and not Level.exists(entry["level"]):
					bad.append(id)
			"weapon":
				if entry.has("item") and not Items.exists(entry["item"]):
					bad.append(id)
	_check(bad.is_empty(), "factions, resources, place kinds, levels and items named exist %s" % [bad])


func _is_id(id: Variant) -> bool:
	if not id is String or id.is_empty():
		return false
	for c in id:
		if not (c == "_" or (c >= "a" and c <= "z") or (c >= "0" and c <= "9")):
			return false
	return true


## An entry's status is required; a fact's defaults to its entry's. An asked
## one names its question.
func _status_ok(thing: Dictionary, required := true) -> bool:
	if not thing.has("status"):
		return not required
	return thing["status"] in STATUSES and (thing["status"] != "asked" or thing.get("ask") is String)


func _regions_ok(where: Variant) -> bool:
	if not where is Array:
		return false
	for region in where:
		if not _entries.has(region) or _entries[region]["type"] != "region":
			return false
	return true


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
