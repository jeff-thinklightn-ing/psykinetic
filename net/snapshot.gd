class_name Snapshot
extends RefCounted
## JSON snapshot of entity state for the dedicated server (--state=<path>).
##
## Holds every loaded zone (World.zones): its tick, every entity the level
## owns (the spawn spec it was built from, its tile, hp, stamina and
## facing, and a chest's slots) and its respawn timers; and a PlayerRecord per player who has
## ever joined, with the zone they are in, so a player comes back where they
## left off; and the world's clock (World.steps), so the world tick goes on
## from where it stopped (the world waits while the server is down); who
## holds which place (Holdings) and the town's stores (Stockpile). The
## rooms themselves always come from the levels. A version 1
## file (one map, before zones) loads as that one zone.
##
## Written to <path>.tmp then renamed, so a crash mid-write cannot leave a
## half snapshot behind. Loading anything it cannot make sense of logs the
## problem and reports nothing to restore, never crashes.

const VERSION := 2


## Writes [param zones] (name -> {tick, entities: Array[GridEntity],
## respawns: dead level entities as {spawn, ticks_left}}) and
## [param players] to [param path], with [param world]'s keys at the top
## level beside them ("steps": World.steps). Returns false and logs on
## failure.
static func save(path: String, zones: Dictionary, players: Array[PlayerRecord] = [], world := {}) -> bool:
	return write(path, data_of(zones, players, world))


## What save writes, gathered now: it reads the entities, so on the main
## thread; then it can be written anywhere (write, on a thread: decision 360).
static func data_of(zones: Dictionary, players: Array[PlayerRecord] = [], world := {}) -> Dictionary:
	var saved := {}
	for zone_name: String in zones:
		var section: Dictionary = zones[zone_name]
		var entities: Array[GridEntity] = []
		entities.assign(section.get("entities", []))
		saved[zone_name] = {"tick": int(section.get("tick", 0)), "entities": _entries(entities),
			"respawns": section.get("respawns", []), "ground": section.get("ground", []),
			"records": section.get("records", [])}
	var records: Array[Dictionary] = []
	for record in players:
		records.append(record.to_dict())
	var data := {"version": VERSION, "zones": saved, "players": records}
	data.merge(world)
	return data


## [param data] (data_of) as JSON to [param path], whole or not at all (a
## temp file, then renamed over it). Safe on a thread if nothing else
## touches [param data] meanwhile.
static func write(path: String, data: Dictionary) -> bool:
	return _write(path, JSON.stringify(data, "\t"))


## [param entity] as a saved entry (_entries), for a record of it kept
## instead of the node (Main._retire, decision 352); {} if it is not saved.
static func entry(entity: GridEntity) -> Dictionary:
	var list := _entries([entity])
	return list[0] if not list.is_empty() else {}


## A saved entry read back (_parse_entry): {} if it makes no sense.
static func parse_entry(raw: Variant) -> Dictionary:
	return _parse_entry(raw)


## A zone's section as written (data_of) read back as load gives it
## (_parse_zone): a live zone's section put through the save and back, for
## Main to rebuild the zone from part of it (Regen.keep_section).
static func parse_zone(raw: Dictionary) -> Dictionary:
	return _parse_zone(raw)


static func _entries(entities: Array[GridEntity]) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for entity in entities:
		if not is_instance_valid(entity) or not entity.spawned or entity.owner_peer != 0:
			continue
		if entity is Companion:
			continue  # Kept in its owner's player record instead.
		if entity is Resident:
			continue  # Its town's records are its truth (decision 333).
		var spec := entity.spawn_spec
		var entry := {
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
		}
		# Which level entity it is, by its marker cell (decision 433): the
		# slot's index moves when a level gains one before it, its key not.
		if str(spec.get("spawn_key", "")) != "":
			entry["spawn_key"] = str(spec["spawn_key"])
		if spec.has("kind"):
			entry["kind"] = str(spec["kind"])
		if spec.has("art"):
			entry["art"] = str(spec["art"])
		# A herd's body (decision 367): its group and the group's home.
		if spec.has("group"):
			entry["group"] = str(spec["group"])
		if spec.get("home") is Vector2i:
			entry["home"] = [spec["home"].x, spec["home"].y]
		if not entity.slots.is_empty():
			entry["slots"] = Array(entity.slots)
			entry["items"] = Array(World.slot_uids(entity))
		list.append(entry)
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
## {spec, hp, stamina, facing, slots (null if none saved), items (their
## ItemBook uids; [] in a file from before instances)}, "players"
## the records, "steps" the world's clock (0 in a file from before it
## was kept), and "holdings" who holds which place (Holdings.to_dict; {} in
## a file from before them: the levels' own holders), and "stockpile" the
## town's stores (Stockpile.to_dict; {} in a file from before it), and
## "items" the ItemBook (ItemBook.to_dict; {} before instances), and
## "production" the town's work (Production.to_dict; {} before it), and
## "towns" how each grows (Towns.to_dict; {} before it), "roofs" the
## damaged roofs (World.roofs_damaged's keys; [] before them), "economy"
## the players' gold (Economy.to_dict; {} before it), and "herds" the
## wildlife (Herds.to_dict; {} before it). Entries that make
## no sense are skipped with a warning rather than failing the whole load.
static func load(path: String) -> Dictionary:
	var nothing := {"ok": false, "zones": {}, "players": [], "steps": 0}
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
	var steps: Variant = data.get("steps", 0)
	var holdings: Variant = data.get("holdings", {})
	var stockpile: Variant = data.get("stockpile", {})
	var items: Variant = data.get("items", {})
	var production: Variant = data.get("production", {})
	var towns: Variant = data.get("towns", {})
	var roofs: Variant = data.get("roofs", [])
	var economy: Variant = data.get("economy", {})
	var herds: Variant = data.get("herds", {})
	var sky: Variant = data.get("sky", {})
	var regen: Variant = data.get("regen", {})
	return {"ok": true, "zones": zones, "players": players,
		"regen": regen if regen is Dictionary else {},
		"steps": maxi(int(steps), 0) if steps is float or steps is int else 0,
		"holdings": holdings if holdings is Dictionary else {},
		"stockpile": stockpile if stockpile is Dictionary else {},
		"items": items if items is Dictionary else {},
		"production": production if production is Dictionary else {},
		"towns": towns if towns is Dictionary else {},
		"roofs": roofs if roofs is Array else [],
		"economy": economy if economy is Dictionary else {},
		"herds": herds if herds is Dictionary else {},
		"sky": sky if sky is Dictionary else {}}


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
				respawns.append({"spawn": int(entry["spawn"]), "spawn_key": str(entry.get("spawn_key", "")),
					"ticks_left": int(entry.get("ticks_left", 0))})
	var ground: Array = []
	for pile: Variant in raw.get("ground", []) if raw.get("ground") is Array else []:
		var cell: Variant = vector(pile.get("cell")) if pile is Dictionary else null
		if cell != null and pile.get("ids") is Array:
			ground.append({"cell": cell, "ids": pile["ids"], "items": pile["items"] if pile.get("items") is Array else []})
	# Monsters kept as records (decision 352): kept as they are (Main reads
	# each when it recalls it); none in a snapshot from before them.
	var records: Array[Dictionary] = []
	for record: Variant in raw.get("records", []) if raw.get("records") is Array else []:
		if record is Dictionary and not _parse_entry(record.get("entry")).is_empty():
			records.append(record)
		else:
			push_warning("[state] skipping a record that makes no sense: %s" % [record])
	return {"tick": int(raw.get("tick", 0)), "entities": entities, "respawns": respawns, "ground": ground, "records": records}


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
	var props: Variant = JSON.to_native(raw_props) \
			if raw_props is Dictionary and raw_props.has("type") else {}
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
	if entry.get("spawn_key") is String and not entry["spawn_key"].is_empty():
		spec["spawn_key"] = entry["spawn_key"]
	if entry.get("art") is String and not entry["art"].is_empty():
		spec["art"] = entry["art"]
	if entry.get("kind") is String and not entry["kind"].is_empty():
		# A monster that is no level entity (a level's own takes its kind,
		# as all it is, from the level).
		spec["kind"] = entry["kind"]
	if entry.get("group") is String and not entry["group"].is_empty():
		spec["group"] = entry["group"]
	if vector(entry.get("home")) != null:
		spec["home"] = vector(entry.get("home"))
	return {
		"spec": spec,
		"hp": int(entry.get("hp", 0)),
		"stamina": int(entry.get("stamina", 0)),
		"facing": facing if facing != null else Vector2i(0, 1),
		"slots": entry["slots"] if entry.get("slots") is Array else null,
		"items": entry["items"] if entry.get("items") is Array else [],
	}


## A JSON [x, y] pair as a Vector2i, or null.
static func vector(value: Variant) -> Variant:
	if value is Array and value.size() == 2 \
			and (value[0] is float or value[0] is int) and (value[1] is float or value[1] is int):
		return Vector2i(int(value[0]), int(value[1]))
	return null
