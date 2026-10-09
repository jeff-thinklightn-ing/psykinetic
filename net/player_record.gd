class_name PlayerRecord
extends RefCounted
## What the server remembers about a player between sessions, keyed by the
## player_id the client keeps in its settings.cfg. Saved in the snapshot.

var player_id := ""
## Join order on this server, from 1. Gives the entity its node name
## ("Player3") and its colour, and never changes.
var index := 0
var name := "Player"
var tile := Vector2i.ZERO
var hp := 0
var stamina := 0
var facing := Vector2i(0, 1)
var color := Color.WHITE
## The zone (map) the player is in: where they come back to.
var zone := ""
## Unix time of the last join or leave.
var last_seen := 0
## The player's companion: {name, card, hp, stamina, tile: [x, y], alive,
## said: her last lines, newest last}.
## Empty until one has been given. A tile of null means beside its owner.
var companion: Dictionary = {}
## What is in the player's slots (Items ids, "" empty), kept through
## death, travel and leaving.
var slots := Items.tidy([], Player.SLOTS)


## Copies the live state off the player's entity.
func remember(entity: GridEntity) -> void:
	tile = entity.tile
	if not entity.zone.is_empty():
		zone = entity.zone
	hp = entity.hp
	stamina = entity.stamina
	facing = entity.facing
	slots = entity.slots.duplicate()
	last_seen = int(Time.get_unix_time_from_system())


func to_dict() -> Dictionary:
	return {
		"player_id": player_id,
		"index": index,
		"name": name,
		"tile": [tile.x, tile.y],
		"hp": hp,
		"stamina": stamina,
		"facing": [facing.x, facing.y],
		"color": color.to_html(false),
		"zone": zone,
		"last_seen": last_seen,
		"companion": companion.duplicate(true),
		"slots": Array(slots),
	}


## Null if the entry is not a usable record.
static func from_dict(entry: Variant) -> PlayerRecord:
	if entry is not Dictionary or entry.get("player_id") is not String or entry["player_id"].is_empty():
		return null
	var tile_value: Variant = Snapshot.vector(entry.get("tile"))
	if tile_value == null:
		return null
	var record := PlayerRecord.new()
	record.player_id = entry["player_id"]
	record.index = int(entry.get("index", 0))
	record.name = str(entry.get("name", "Player"))
	record.tile = tile_value
	record.hp = int(entry.get("hp", 0))
	record.stamina = int(entry.get("stamina", 0))
	var facing_value: Variant = Snapshot.vector(entry.get("facing"))
	record.facing = facing_value if facing_value != null else Vector2i(0, 1)
	var html: String = str(entry.get("color", ""))
	record.color = Color.html(html) if Color.html_is_valid(html) else Color.WHITE
	record.last_seen = int(entry.get("last_seen", 0))
	record.zone = str(entry.get("zone", ""))
	record.slots = Items.tidy(entry.get("slots", []), Player.SLOTS)
	var pet: Variant = entry.get("companion", {})
	if pet is Dictionary and pet.get("name") is String:
		record.companion = {
			"name": str(pet["name"]),
			"card": str(pet.get("card", "")),
			"hp": int(pet.get("hp", 0)),
			"stamina": int(pet.get("stamina", 0)),
			"tile": pet.get("tile"),
			"alive": bool(pet.get("alive", true)),
			"said": _lines(pet.get("said", [])),
		}
	return record


## [param value] as lines of text, or none.
static func _lines(value: Variant) -> Array[String]:
	var lines: Array[String] = []
	if value is Array:
		for line: Variant in value:
			lines.append(str(line))
	return lines
