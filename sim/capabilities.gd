class_name Capabilities
extends RefCounted
## What each area teaches (decision 576): levels/capabilities.json. A
## capability is a mark (a player's record.marks, a companion's
## record.companion["marks"]) with an entry there; Main gives them
## (grant_capability) and asks after them (party_has). All static.

const PATH := "res://levels/capabilities.json"

static var _catalog: Dictionary = {}


## The catalog, id -> entry (its "_about" left out); read once.
static func catalog() -> Dictionary:
	if _catalog.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		var out := {}
		if parsed is Dictionary:
			for id: String in parsed:
				if not id.begins_with("_") and parsed[id] is Dictionary:
					out[id] = parsed[id]
		_catalog = out if not out.is_empty() else {"_none": {}}
	return _catalog


## [param id]'s entry, {} for none.
static func entry(id: String) -> Dictionary:
	var found: Variant = catalog().get(id, {})
	return found if found is Dictionary and not id.begins_with("_") else {}


## Whether [param id] is given and checked now (status "live").
static func live(id: String) -> bool:
	return str(entry(id).get("status", "")) == "live"


## The live capabilities among [param marks], each {id, words, teacher},
## in the catalog's order: what her card shows.
static func held(marks: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in catalog():
		if id in marks and live(id):
			var known := entry(id)
			out.append({"id": id, "words": str(known.get("words", id)), "teacher": str(known.get("teacher", ""))})
	return out


## [param key] of [param id]'s entry with {her} and {player} filled in.
static func said(id: String, key: String, her: String, player := "") -> String:
	return str(entry(id).get(key, "")).replace("{her}", her).replace("{player}", player)
