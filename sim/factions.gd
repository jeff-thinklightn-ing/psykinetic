class_name Factions
extends RefCounted
## The sides that hold places (levels/factions.json): goblins and the town
## for now. Each has a name for words, a colour for the world map, the
## monster kinds that act for it, and the factions it is hostile to.
## "nobody" is no faction: it holds what nobody holds, and blocks no one;
## "contested" is ground two factions claim (Holdings.ground).

const PATH := "res://levels/factions.json"
const NOBODY := "nobody"
const CONTESTED := "contested"
const NOBODY_COLOUR := Color(0.5, 0.5, 0.52)
const CONTESTED_COLOUR := Color(0.85, 0.3, 0.3)

## Faction id -> {name, colour (Color), monsters (Array[String]),
## hostile_to (Array[String])}.
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
			"monsters": monsters, "hostile_to": hostile}
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


## Whether [param a] or [param b] counts the other as an enemy.
func hostile(a: String, b: String) -> bool:
	return all.has(a) and b in all[a]["hostile_to"] or all.has(b) and a in all[b]["hostile_to"]
