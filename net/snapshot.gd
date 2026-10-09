class_name Snapshot
extends RefCounted
## JSON snapshot of entity state for the dedicated server (--state=<path>).
##
## Holds every entity the level owns (the spawn spec it was built from, its
## tile, hp, stamina and facing) and a PlayerRecord per player who has ever
## joined, so a player comes back where they left off. The room itself
## always comes from the ASCII map in main.gd.
##
## Written to <path>.tmp then renamed, so a crash mid-write cannot leave a
## half snapshot behind. Loading anything it cannot make sense of logs the
## problem and reports nothing to restore, never crashes.

const VERSION := 1


## Writes [param entities] to [param path]. Returns false and logs on failure.
## [param respawns] lists dead level entities as {spawn, ticks_left}.
static func save(path: String, tick: int, entities: Array[GridEntity],
		players: Array[PlayerRecord] = [], respawns: Array[Dictionary] = [], map := "") -> bool:
	var list: Array[Dictionary] = []
	for entity in entities:
		if not is_instance_valid(entity) or not entity.spawned or entity.owner_peer != 0:
			continue
		if entity is Companion:
			continue  # Kept in its owner's player record instead.
		var spec := entity.spawn_spec
		list.append({
			"script": str(spec.get("script", "")),
			"shape": str(spec.get("shape", EntityFactory.DEFAULT_SHAPE)),
			"tint": spec["tint"].to_html(true) if spec.get("tint") is Color else "",
			"scale": float(spec.get("scale", 1.0)),
			"label": str(spec.get("label", "")),
			"name": String(entity.name),
			"tile": [entity.tile.x, entity.tile.y],
			"hp": entity.hp,
			"stamina": entity.stamina,
			"facing": [entity.facing.x, entity.facing.y],
			"props": JSON.from_native(entity.spawn_spec.get("props", {})),
			"spawn": int(entity.spawn_spec.get("spawn", -1)),
		})
	var records: Array[Dictionary] = []
	for record in players:
		records.append(record.to_dict())
	var text := JSON.stringify(
			{"version": VERSION, "tick": tick, "map": map, "entities": list, "players": records,
				"respawns": respawns}, "\t")

	var directory := path.get_base_dir()
	if directory != "" and not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		push_warning("[state] cannot write %s (%s)" % [temp, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(text)
	file.close()
	var error := DirAccess.rename_absolute(temp, path)
	if error != OK:
		push_warning("[state] cannot replace %s (%s)" % [path, error_string(error)])
		return false
	return true


## Reads [param path]. The result's "ok" is false if there was nothing usable
## (missing, unreadable, or malformed); otherwise "entities" holds one entry
## per restorable entity: {spec, hp, stamina, facing}. Entries that make no
## sense are skipped with a warning rather than failing the whole load.
static func load(path: String) -> Dictionary:
	var nothing := {"ok": false, "tick": 0, "entities": [], "players": [], "respawns": []}
	if not FileAccess.file_exists(path):
		print("[state] no snapshot at %s; starting fresh" % path)
		return nothing
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		print("[state] %s is empty or unreadable; starting fresh" % path)
		return nothing
	var json := JSON.new()
	if json.parse(text) != OK:
		print("[state] %s does not parse (line %d: %s); starting fresh" % [
			path, json.get_error_line(), json.get_error_message()])
		return nothing
	var data: Variant = json.data
	if data is not Dictionary or data.get("version") != VERSION or data.get("entities") is not Array:
		print("[state] %s is not a version %d snapshot; starting fresh" % [path, VERSION])
		return nothing

	var entities: Array[Dictionary] = []
	for entry in data["entities"]:
		var parsed := _parse_entry(entry)
		if parsed.is_empty():
			push_warning("[state] skipping an entry that makes no sense: %s" % [entry])
			continue
		entities.append(parsed)
	var players: Array[PlayerRecord] = []
	var player_entries: Variant = data.get("players", [])
	if player_entries is Array:
		for entry in player_entries:
			var record := PlayerRecord.from_dict(entry)
			if record == null:
				push_warning("[state] skipping a player record that makes no sense: %s" % [entry])
				continue
			players.append(record)
	var respawns: Array[Dictionary] = []
	var respawn_entries: Variant = data.get("respawns", [])
	if respawn_entries is Array:
		for entry in respawn_entries:
			if entry is Dictionary and entry.get("spawn") is float:
				respawns.append({"spawn": int(entry["spawn"]), "ticks_left": int(entry.get("ticks_left", 0))})
	return {"ok": true, "tick": int(data.get("tick", 0)), "entities": entities,
		"players": players, "respawns": respawns, "map": _map_in(data)}


## The map [param path]'s snapshot was saved on ("" for no snapshot; the
## test room for one from before maps).
static func map_of(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	# Quietly: a file that does not parse is load()'s to report.
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return ""
	return _map_in(json.data) if json.data is Dictionary else ""


static func _map_in(data: Dictionary) -> String:
	var map := str(data.get("map", ""))
	return map if not map.is_empty() else "test_room"


## Snapshots from before the generic entity scene named a scene type instead
## of a script and shape.
const LEGACY_TYPES := {
	"monster": {"script": "res://sim/monster.gd", "shape": "capsule"},
	"pushable": {"script": "res://sim/pushable.gd", "shape": "cube"},
}


static func _parse_entry(entry: Variant) -> Dictionary:
	if entry is not Dictionary:
		return {}
	var tile: Variant = vector(entry.get("tile"))
	if tile == null or entry.get("name") is not String:
		return {}
	var facing: Variant = vector(entry.get("facing"))
	# Props were written with JSON.from_native; a bare {} (no props) is not.
	var raw_props: Variant = entry.get("props", {})
	var props: Variant = JSON.to_native(raw_props) 			if raw_props is Dictionary and raw_props.has("type") else {}
	var spec := {
		"name": entry["name"],
		"tile": tile,
		"props": props if props is Dictionary else {},
	}
	if entry.get("script") is String:
		spec["script"] = entry["script"]
		spec["shape"] = str(entry.get("shape", EntityFactory.DEFAULT_SHAPE))
	elif entry.get("type") is String and LEGACY_TYPES.has(entry["type"]):
		spec.merge(LEGACY_TYPES[entry["type"]])
	else:
		return {}
	var tint := str(entry.get("tint", ""))
	if Color.html_is_valid(tint):
		spec["tint"] = Color.html(tint)
	if entry.get("scale") is float and float(entry["scale"]) > 0.0:
		spec["scale"] = float(entry["scale"])
	if entry.get("label") is String and not entry["label"].is_empty():
		spec["label"] = entry["label"]
	if entry.get("spawn") is float and int(entry["spawn"]) >= 0:
		spec["spawn"] = int(entry["spawn"])
	return {
		"spec": spec,
		"hp": int(entry.get("hp", 0)),
		"stamina": int(entry.get("stamina", 0)),
		"facing": facing if facing != null else Vector2i(0, 1),
	}


## A JSON [x, y] pair as a Vector2i, or null.
static func vector(value: Variant) -> Variant:
	if value is Array and value.size() == 2 \
			and (value[0] is float or value[0] is int) and (value[1] is float or value[1] is int):
		return Vector2i(int(value[0]), int(value[1]))
	return null
