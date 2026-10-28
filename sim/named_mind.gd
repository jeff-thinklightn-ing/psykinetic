class_name NamedMind
extends RefCounted
## What a named enemy (decision 716) keeps of the players it has met, npc's
## side: its card (ResidentCard's roll: how it speaks, never how it fights),
## a short list of memories and a track record per player, all on its
## record (World.named_record). Built from enemy-ai's World.named_event
## only: no read of the player, no fear or courage, nothing that grows its
## strength. A memory is {kind, player, step, where}: the player's id is a
## key, never words (692). The track is counts per player: {met, fought,
## killed, killed_by, fled_from, last}. Its words come from the counts by
## the ENEMY ladder; its lines from levels/named_enemies.json "lines".

const PATH := "res://levels/named_enemies.json"
## The kinds of named_event kept as memories (rose is the world's, not a player's).
const KINDS: Array[String] = ["met", "fought", "killed", "killed_by", "fled_from"]
const MEMORIES_KEPT := 8
## A player who put it down this often is its bane; one it put down this often, its prey.
const GRUDGE_AT := 2
## Its words for a player, by the track: stranger (none), known (met), foe
## (fought), bane, prey.
const ENEMY := {"none": "stranger", "met": "known", "fought": "foe", "bane": "bane", "prey": "prey"}
const DEFAULT_LINES := {
	"stranger": ["Fresh meat."], "known": ["You again."], "foe": ["Back for more?"],
	"bane": ["You put me in the ground once. Not again."], "prey": ["Come to lie down again?"],
	"fled_from": ["Last time you ran."], "rose": ["%s walks again."],
	"emote": ["snarls"], "speaks": []}

static var _lines := {}


## The file's "lines" block over DEFAULT_LINES, read once.
static func lines() -> Dictionary:
	if _lines.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_lines = DEFAULT_LINES.duplicate(true)
		if parsed is Dictionary and parsed.get("lines") is Dictionary:
			for key: String in parsed["lines"]:
				if parsed["lines"][key] is Array and not key.begins_with("_"):
					_lines[key] = parsed["lines"][key]
	return _lines


## For tests: [param given] over DEFAULT_LINES ({} to read the file again).
static func use_lines(given: Dictionary) -> void:
	_lines = {}
	if not given.is_empty():
		_lines = DEFAULT_LINES.duplicate(true)
		_lines.merge(given, true)


## [param record]'s card, rolled once by [param id] (ResidentCard: traits,
## temper, pronoun) if it has none yet. Whether it was rolled now.
static func ensure_card(record: Dictionary, id: String) -> bool:
	if record.get("card") is Dictionary and not (record["card"] as Dictionary).is_empty():
		return false
	record["card"] = ResidentCard.roll("named:" + id, str(record.get("name", id)), str(record.get("kind", "")), "named")
	return true


## [param kind] with [param player_id] at [param step] in [param where]
## kept on [param record]: a memory (the last MEMORIES_KEPT) and the
## track's count. Whether it was one to keep.
static func remember(record: Dictionary, kind: String, player_id: String, step: int, where: String) -> bool:
	if player_id.is_empty() or not KINDS.has(kind):
		return false
	var memories: Array = record.get("memories", []) if record.get("memories") is Array else []
	memories.append({"kind": kind, "player": player_id, "step": step, "where": where})
	while memories.size() > MEMORIES_KEPT:
		memories.pop_front()
	record["memories"] = memories
	var track: Dictionary = record.get("track", {}) if record.get("track") is Dictionary else {}
	var counts: Dictionary = track.get(player_id, {})
	counts[kind] = int(counts.get(kind, 0)) + 1
	counts["last"] = step
	track[player_id] = counts
	record["track"] = track
	return true


## Its word for [param player_id] (ENEMY's): bane before prey before foe
## before known; stranger for one it has no count of.
static func word(record: Dictionary, player_id: String) -> String:
	var counts: Dictionary = record.get("track", {}).get(player_id, {}) if record.get("track") is Dictionary else {}
	if int(counts.get("killed_by", 0)) >= GRUDGE_AT:
		return ENEMY["bane"]
	if int(counts.get("killed", 0)) >= GRUDGE_AT:
		return ENEMY["prey"]
	if int(counts.get("fought", 0)) > 0 or int(counts.get("killed_by", 0)) > 0 or int(counts.get("killed", 0)) > 0:
		return ENEMY["fought"]
	if int(counts.get("met", 0)) > 0:
		return ENEMY["met"]
	return ENEMY["none"]


## Its newest memory with [param player_id], {} for none.
static func last_with(record: Dictionary, player_id: String) -> Dictionary:
	var memories: Array = record.get("memories", []) if record.get("memories") is Array else []
	for i in range(memories.size() - 1, -1, -1):
		if str(memories[i].get("player", "")) == player_id:
			return memories[i]
	return {}


## Whether [param record]'s kind speaks (the lines' "speaks" list); one
## that doesn't is shown by an emote.
static func speaks(record: Dictionary) -> bool:
	return (lines().get("speaks", []) as Array).has(str(record.get("kind", "")))


## Its line on meeting [param player_id] (asked before this met is
## kept): by their newest memory when that was their running, else by its
## word for them. Picked by its id, the player and its life, so it holds in one
## life. "" when the table has none.
static func meeting_line(record: Dictionary, id: String, player_id: String) -> String:
	var key := word(record, player_id)
	if str(last_with(record, player_id).get("kind", "")) == "fled_from":
		key = "fled_from"
	return _pick(key, "%s|%s|%d" % [id, player_id, int(record.get("lives", 1))])


## The town's news of its rising: "Brand the Ox walks again."
static func rose_news(record: Dictionary, id: String) -> String:
	var line := _pick("rose", "%s|rose|%d" % [id, int(record.get("lives", 1))])
	return line % str(record.get("name", id)) if line.contains("%s") else line


## Its emote for one that doesn't speak: "snarls".
static func emote(record: Dictionary, id: String, player_id: String) -> String:
	return _pick("emote", "%s|%s|%d" % [id, player_id, int(record.get("lives", 1))])


static func _pick(key: String, seed_text: String) -> String:
	var options: Array = lines().get(key, [])
	if options.is_empty():
		return ""
	return str(options[absi(hash(seed_text)) % options.size()])
