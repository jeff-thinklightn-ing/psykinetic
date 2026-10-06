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
static func save(path: String, tick: int, entities: Array[GridEntity],
		players: Array[PlayerRecord] = []) -> bool:
	var list: Array[Dictionary] = []
	for entity in entities:
		if not is_instance_valid(entity) or not entity.spawned or entity.owner_peer != 0:
			continue
		list.append({
			"type": entity.spawn_spec.get("scene", ""),
			"name": String(entity.name),
			"tile": [entity.tile.x, entity.tile.y],
			"hp": entity.hp,
			"stamina": entity.stamina,
			"facing": [entity.facing.x, entity.facing.y],
			"props": JSON.from_native(entity.spawn_spec.get("props", {})),
		})
	var records: Array[Dictionary] = []
	for record in players:
		records.append(record.to_dict())
	var text := JSON.stringify(
			{"version": VERSION, "tick": tick, "entities": list, "players": records}, "\t")

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
	var nothing := {"ok": false, "tick": 0, "entities": [], "players": []}
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
	return {"ok": true, "tick": int(data.get("tick", 0)), "entities": entities, "players": players}


static func _parse_entry(entry: Variant) -> Dictionary:
	if entry is not Dictionary:
		return {}
	var tile: Variant = vector(entry.get("tile"))
	if tile == null or entry.get("type") is not String or entry.get("name") is not String:
		return {}
	var facing: Variant = vector(entry.get("facing"))
	var props: Variant = JSON.to_native(entry.get("props", {}))
	return {
		"spec": {
			"scene": entry["type"],
			"name": entry["name"],
			"tile": tile,
			"props": props if props is Dictionary else {},
		},
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
