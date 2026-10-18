class_name PlayerRecord
extends RefCounted
## What the server remembers about a player between sessions, keyed by the
## player_id the client keeps in its settings.cfg. Saved in the snapshot.

var player_id := ""
## Join order on this server, from 1. Gives the entity its node name
## ("Player3") and its colour, and never changes.
var index := 0
var name := "Player"
## The body the player wears (Net.BODIES; decision 388): what they asked for
## at their last join.
var body: StringName = &"male"
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
## said: her last lines, newest last, slots: her pack, traits (rolled:
## CompanionCard), how_we_met, card_by ("plain" or "model"), facts and
## beliefs (CompanionFacts), talk (not yet read for them), and resident while
## she stays in a town working: {place, zone, trade} (decision 284), and
## taken while raiders hold her: {by: the group's id, zone, at: the world
## step} (decision 314)}.
## Empty until one has been given. A tile of null means beside its owner.
var companion: Dictionary = {}
## The commissions and errands they took on from the town's people (decision
## 435): the asks as the residents' cards hold them, by id.
var commissions: Array = []
## What is in the player's slots (Items ids, "" empty), kept through
## death, travel and leaving.
var slots := Items.tidy([], Player.SLOTS)
## The instance in each slot (ItemBook uids, 0 none), beside slots.
var slot_items := PackedInt32Array()


## Copies the live state off the player's entity.
func remember(entity: GridEntity) -> void:
	tile = entity.tile
	if not entity.zone.is_empty():
		zone = entity.zone
	hp = entity.hp
	stamina = entity.stamina
	facing = entity.facing
	slots = entity.slots.duplicate()
	slot_items = World.slot_uids(entity)
	last_seen = int(Time.get_unix_time_from_system())


func to_dict() -> Dictionary:
	return {
		"player_id": player_id,
		"index": index,
		"name": name,
		"body": String(body),
		"tile": [tile.x, tile.y],
		"hp": hp,
		"stamina": stamina,
		"facing": [facing.x, facing.y],
		"color": color.to_html(false),
		"zone": zone,
		"last_seen": last_seen,
		"companion": companion.duplicate(true),
		"commissions": commissions.duplicate(true),
		"slots": Array(slots),
		"items": Array(slot_items),
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
	record.body = Net.tidy_body(entry.get("body", ""))  # Older snapshots have none: male.
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
	record.slot_items = _uids(entry.get("items", []))
	var asks: Variant = entry.get("commissions", [])
	record.commissions = asks.duplicate(true) if asks is Array else []
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
			"slots": Array(Items.tidy(pet.get("slots", []), Companion.SLOTS)),
			"items": Array(_uids(pet.get("items", []))),
		}
		var traits: Variant = pet.get("traits")
		if traits is Dictionary and not traits.is_empty():
			var kept := {}
			for key: Variant in traits:
				kept[str(key)] = str(traits[key])
			record.companion["traits"] = kept
			record.companion["how_we_met"] = str(pet.get("how_we_met", ""))
			record.companion["card_by"] = str(pet.get("card_by", "plain"))
		# What has become true of her (decision 294), and talk not yet read for it.
		var grown := CompanionFacts.from_record(pet.get("facts", []), pet.get("beliefs", []))
		if not grown.facts.is_empty() or not grown.beliefs.is_empty():
			record.companion["facts"] = grown.facts
			record.companion["beliefs"] = grown.beliefs
		var talk: Variant = pet.get("talk", [])
		if talk is Array and not talk.is_empty():
			record.companion["talk"] = Array(talk.map(func(line: Variant) -> String: return str(line)))
		var resident: Variant = pet.get("resident")
		if resident is Dictionary and str(resident.get("place", "")) != "" and str(resident.get("zone", "")) != "":
			record.companion["resident"] = {"place": str(resident["place"]), "zone": str(resident["zone"]),
				"trade": str(resident.get("trade", ""))}
		var taken: Variant = pet.get("taken")
		if taken is Dictionary and str(taken.get("by", "")) != "":
			record.companion["taken"] = {"by": str(taken["by"]), "zone": str(taken.get("zone", "")), "at": int(taken.get("at", 0))}
	return record


## [param value] as ItemBook uids (0 for none), or none.
static func _uids(value: Variant) -> PackedInt32Array:
	var uids := PackedInt32Array()
	if value is Array:
		for uid: Variant in value:
			uids.append(int(uid) if uid is float or uid is int else 0)
	return uids


## [param value] as lines of text, or none.
static func _lines(value: Variant) -> Array[String]:
	var lines: Array[String] = []
	if value is Array:
		for line: Variant in value:
			lines.append(str(line))
	return lines
