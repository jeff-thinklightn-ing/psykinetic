class_name Snapshot
extends RefCounted
## JSON snapshot of entity state for the dedicated server (--state=<path>).
##
## Holds every loaded zone (World.zones): its tick, every entity the level
## owns (the spawn spec it was built from, its tile, hp, stamina and
## facing) and its respawn timers; and a PlayerRecord per player who has
## ever joined, with the zone they are in, so a player comes back where they
## left off. The rooms themselves always come from the levels. A version 1
## file (one map, before zones) loads as that one zone.
##
## Written to <path>.tmp then renamed, so a crash mid-write cannot leave a
## half snapshot behind. Loading anything it cannot make sense of logs the
## problem and reports nothing to restore, never crashes.

const VERSION := 2


## Writes [param zones] (name -> {tick, entities: Array[GridEntity],
## respawns: dead level entities as {spawn, ticks_left}}) and
## [param players] to [param path]. Returns false and logs on failure.
static func save(path: String, zones: Dictionary, players: Array[PlayerRecord] = []) -> bool:
	var saved := {}
	for zone_name: String in zones:
		var section: Dictionary = zones[zone_name]
		var entities: Array[GridEntity] = []
		entities.assign(section.get("entities", []))
		saved[zone_name] = {"tick": int(section.get("tick", 0)), "entities": _entries(entities),
			"respawns": section.get("respawns", [])}
	var records: Array[Dictionary] = []
	for record in players:
		records.append(record.to_dict())
	var text := JSON.stringify({"version": VERSION, "zones": saved, "players": records}, "\t")
	return _write(path, text)


static func _entries(entities: Array[GridEntity]) -> Array[Dictionary]:
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
	return list


static func _write(path: String, text: String) -> bool:
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
## (missing, unreadable, or malformed); otherwise "zones" holds each zone's
## {tick, entities, respawns}, "entities" one entry per restorable entity:
## {spec, hp, stamina, facing}, and "players" the records. Entries that make
## no sense are skipped with a warning rather than failing the whole load.
static func load(path: String) -> Dictionary:
	var nothing := {"ok": false, "zones": {}, "players": []}
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
	if data is not Dictionary or not (data.get("version") == VERSION and data.get("zones") is Dictionary
			or data.get("version") == 1.0 and data.get("entities") is Array):
		print("[state] %s is not a version %d snapshot; starting fresh" % [path, VERSION])
		return nothing

	# Version 1: one map, its entities and respawns at the top.
	var raw_zones: Dictionary = data["zones"] if data.get("version") == VERSION \
			else {_map_in(data): {"tick": data.get("tick", 0), "entities": data["entities"],
				"respawns": data.get("respawns", [])}}
	var zones := {}
	for zone_name: String in raw_zones:
		var raw: Variant = raw_zones[zone_name]
		if raw is Dictionary:
			zones[zone_name] = _parse_zone(raw)
	var players: Array[PlayerRecord] = []
	var player_entries: Variant = data.get("players", [])
	if player_entries is Array:
		for entry in player_entries:
			var record := PlayerRecord.from_dict(entry)
			if record == null:
				push_warning("[state] skipping a player record that makes no sense: %s" % [entry])
				continue
			players.append(record)
	if data.get("version") != VERSION:
		# Version 1: everyone was on its one map.
		for record in players:
			if record.zone.is_empty():
				record.zone = _map_in(data)
	return {"ok": true, "zones": zones, "players": players}


## One zone's {tick, entities, respawns} as read.
static func _parse_zone(raw: Dictionary) -> Dictionary:
	var entities: Array[Dictionary] = []
	var entries: Variant = raw.get("entities", [])
	if entries is Array:
		for entry in entries:
			var parsed := _parse_entry(entry)
			if parsed.is_empty():
				push_warning("[state] skipping an entry that makes no sense: %s" % [entry])
				continue
			entities.append(parsed)
	var respawns: Array[Dictionary] = []
	var respawn_entries: Variant = raw.get("respawns", [])
	if respawn_entries is Array:
		for entry in respawn_entries:
			if entry is Dictionary and entry.get("spawn") is float:
				respawns.append({"spawn": int(entry["spawn"]), "ticks_left": int(entry.get("ticks_left", 0))})
	return {"tick": int(raw.get("tick", 0)), "entities": entities, "respawns": respawns}


## A version 1 snapshot's map (the test room for one from before maps).
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
