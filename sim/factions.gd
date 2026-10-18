class_name Factions
extends RefCounted
## The sides that hold places (levels/factions.json): the Blood Rot (key
## "goblins"), the orcs and kobolds allied to it, and the town. Each has a
## name for words, a colour for the world map, the monster kinds that act
## for it (the one place a kind's faction is said), the factions it is
## hostile to, the lore entry it is (lore_id), and the faction it is allied
## to, if any (decision 416): an ally is on its lead's side, one level deep,
## and takes on the lead's enemies.
## "nobody" is no faction: it holds what nobody holds, and blocks no one;
## "contested" is ground two factions claim (Holdings.ground).

const PATH := "res://levels/factions.json"
const NOBODY := "nobody"
const CONTESTED := "contested"
const NOBODY_COLOUR := Color(0.5, 0.5, 0.52)
const CONTESTED_COLOUR := Color(0.85, 0.3, 0.3)

## Faction id -> {name, colour (Color), monsters (Array[String]),
## hostile_to (Array[String]), allied_to ("" for none), lore_id}.
var all: Dictionary[String, Dictionary] = {}


## The factions in [param path]; none, with a warning, if it cannot be read.
static func read(path := PATH) -> Factions:
	var out := Factions.new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not parsed is Dictionary:
		push_warning("[factions] %s is missing or not a JSON object: no factions" % path)
		return out
	for id: String in parsed:
		var entry: Variant = parsed[id]
		if not entry is Dictionary or id in [NOBODY, CONTESTED]:
			push_warning("[factions] %s: %s is not a faction" % [path, id])
			continue
		var monsters: Array[String] = []
		for kind: Variant in entry.get("monsters", []):
			monsters.append(str(kind))
		var hostile: Array[String] = []
		for other: Variant in entry.get("hostile_to", []):
			hostile.append(str(other))
		out.all[id] = {"name": str(entry.get("name", id)), "colour": Color.from_string(str(entry.get("colour", "")), NOBODY_COLOUR),
			"monsters": monsters, "hostile_to": hostile, "allied_to": str(entry.get("allied_to", "")),
			"lore_id": str(entry.get("lore_id", id))}
	for id: String in out.all:
		var lead: String = out.all[id]["allied_to"]
		if lead != "" and (not out.all.has(lead) or lead == id or out.all[lead]["allied_to"] != ""):
			push_warning("[factions] %s: %s's allied_to %s is not a faction leading a side: none" % [path, id, lead])
			out.all[id]["allied_to"] = ""
	return out


## The faction ids, sorted ("nobody" not among them).
func names() -> Array[String]:
	var out: Array[String] = []
	out.assign(all.keys())
	out.sort()
	return out


## Whether [param id] can hold a place: a faction, or "nobody".
func has(id: String) -> bool:
	return id == NOBODY or all.has(id)


## [param id]'s name for words ("the goblins"; "nobody"; "contested").
func display_name(id: String) -> String:
	return str(all[id]["name"]) if all.has(id) else id


func colour(id: String) -> Color:
	if all.has(id):
		return all[id]["colour"]
	return CONTESTED_COLOUR if id == CONTESTED else NOBODY_COLOUR


## The faction monsters of [param kind] act for ("nobody" if none).
func of_kind(kind: String) -> String:
	for id: String in all:
		if kind in all[id]["monsters"]:
			return id
	return NOBODY


## Whether [param a] or [param b] counts the other as an enemy: either
## faction or the side it is on (an ally takes on its lead's enemies). Never
## two of one side.
func hostile(a: String, b: String) -> bool:
	if same_side(a, b):
		return false
	for pair: Array in [[a, b], [side(a), b], [a, side(b)], [side(a), side(b)]]:
		if _counts_hostile(pair[0], pair[1]):
			return true
	return false


func _counts_hostile(a: String, b: String) -> bool:
	return all.has(a) and b in all[a]["hostile_to"] or all.has(b) and a in all[b]["hostile_to"]


## The side [param id] is on: the faction it is allied to, else itself.
func side(id: String) -> String:
	var lead: String = all[id]["allied_to"] if all.has(id) else ""
	return lead if lead != "" else id


## Whether [param a] and [param b] are one side: the same faction, or one
## allied to the other, or both to one lead. "nobody" is no one's side.
func same_side(a: String, b: String) -> bool:
	if a == NOBODY or b == NOBODY or a == CONTESTED or b == CONTESTED:
		return a == b and a != CONTESTED
	return side(a) == side(b)


## The factions allied to [param id], sorted (none for an ally itself).
func allies_of(id: String) -> Array[String]:
	return names().filter(func(other: String) -> bool: return other != id and all[other]["allied_to"] == id)


## The lore entry [param id] is (levels/lore; the id itself when
## factions.json gives none).
func lore_id(id: String) -> String:
	return str(all[id]["lore_id"]) if all.has(id) else id
