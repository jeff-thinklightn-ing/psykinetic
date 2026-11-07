class_name NamedEnemy
extends RefCounted
## A named enemy (decision 716): a monster of an ordinary kind with a name
## and a record the world keeps (World.named), like a companion's. A level
## entity's "named": <id> makes its spawn that one; levels/named_enemies.json
## "named" says who each is: {name, kind, rise_days, strength}. Its strength
## is fixed when its record is made (written there, else rolled by its id)
## and never grows: no XP, no level-ups. It dies like any monster and rises
## again at its post rise_days of the world clock later, by magic, the same
## record. Its weapon goes back to it (Jeff: "their weapon might be a
## special weapon the longer they used it"): kept through each death, it
## names itself by decision 365 with the named one as its holder. npc keeps
## its card, memories and track record on the record (World.named_event).

const PATH := "res://levels/named_enemies.json"
## What a named one's strength multiplies on its kind's: hp and a blow's
## damage, and speed (its steps' ticks divided by it). Rolled within these.
const STRENGTH_SPANS := {"hp": [0.8, 1.6], "damage": [0.8, 1.6], "speed": [0.85, 1.15]}
## A strength its row gives (authored, not rolled: a chief's) is clamped to
## these instead (716 amended, combat's: Hollowfell's chiefs' 2.2 and 2.0
## were clamped to 1.6). Still fixed, never grown by play.
const GIVEN_SPANS := {"hp": [0.5, 3.0], "damage": [0.5, 2.0], "speed": [0.7, 1.3]}
## Its days dead before it rises (the world clock's days), and the panel's span.
const RISE_DAYS := 3.0
const RISE_DAYS_SPAN := [0.5, 10.0]
## A row's "rise_s" in place of rise_days: real seconds dead (714 amended (2);
## Jeff, no scarcity in the barrow: its band back in 5 minutes), and its span.
const RISE_S_SPAN := [30.0, 3600.0]
## Seconds after its trophy is won before it is due again (714 amended (2):
## the Tomb Sledge back in 5 minutes; F7's named.trophy_s).
static var trophy_s := 300.0
## Where its weapon is kept while it is dead or away (ItemBook's place).
const KEPT := "named:%s/kept"

static var _defs := {}


## The file's "named" block, read once: {id: {name, kind, rise_days, strength}}.
static func defs() -> Dictionary:
	if _defs.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		var given: Variant = parsed.get("named", {}) if parsed is Dictionary else {}
		_defs = {"_read": true}
		if given is Dictionary:
			for id: String in given:
				if given[id] is Dictionary and not id.begins_with("_"):
					_defs[id] = (given[id] as Dictionary).duplicate(true)
	return _defs


## For tests: [param id] defined as [param row] until reset_for_test.
static func define_for_test(id: String, row: Dictionary) -> void:
	defs()[id] = row.duplicate(true)


static func reset_for_test() -> void:
	_defs = {}


## [param id]'s row; {} for none.
static func def(id: String) -> Dictionary:
	return defs().get(id, {}) if not id.begins_with("_") else {}


## How many world steps [param id] lies dead before it rises.
static func rise_steps(id: String) -> int:
	if def(id).has("rise_s"):
		return roundi(clampf(float(def(id)["rise_s"]), RISE_S_SPAN[0], RISE_S_SPAN[1]) * World.TICK_RATE)
	var days := clampf(float(def(id).get("rise_days", RISE_DAYS)), RISE_DAYS_SPAN[0], RISE_DAYS_SPAN[1])
	return roundi(days * DayNight.day_steps)


## A new record for [param id] (its first spawn) of [param kind]: its name,
## its strength (the row's, each clamped to GIVEN_SPANS, else rolled by its id),
## alive. npc's card, memories and track start empty.
static func new_record(id: String, kind: String) -> Dictionary:
	var row := def(id)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("named/" + id)
	var strength := {}
	for key: String in STRENGTH_SPANS:
		var span: Array = STRENGTH_SPANS[key]
		var rolled := rng.randf_range(span[0], span[1])
		strength[key] = snappedf(rolled, 0.01)
	strength.merge(given_strength(id), true)
	return {"name": str(row.get("name", id.capitalize())), "kind": str(row.get("kind", kind)), "strength": strength,
		"alive": true, "returns_at": 0, "weapon_uid": 0, "lives": 1, "card": {}, "memories": [], "track": {}}


## [param monster]'s numbers times its record's strength: max hp (full if it
## was full), a blow's damage, its pace. Once, as it spawns.
static func strengthen(monster: Monster, record: Dictionary) -> void:
	# The row's given strength wins over the record's (716 amended): a
	# tune reaches a record made before it. Only the strength; a rolled one
	# stays as it rolled, and the rest of the record is the world's.
	var given := given_strength(monster.named_id)
	if not given.is_empty():
		var kept: Dictionary = record.get("strength", {})
		kept.merge(given, true)
		record["strength"] = kept
	var strength: Dictionary = record.get("strength", {})
	var full := monster.hp >= monster.max_hp
	monster.max_hp = maxi(1, roundi(monster.max_hp * float(strength.get("hp", 1.0))))
	if full:
		monster.hp = monster.max_hp
	monster.attack_damage = maxi(1, roundi(monster.attack_damage * float(strength.get("damage", 1.0))))
	monster.move_ticks = monster.move_ticks / maxf(float(strength.get("speed", 1.0)), 0.01)


## The strength [param id]'s row gives, each field clamped to GIVEN_SPANS:
## only those it gives ({} for a row that gives none; 716 amended).
static func given_strength(id: String) -> Dictionary:
	var given: Variant = def(id).get("strength", {}) if not id.is_empty() else {}
	var out := {}
	if not given is Dictionary:
		return out
	for key: String in GIVEN_SPANS:
		var value: Variant = (given as Dictionary).get(key)
		if value is float or value is int:
			out[key] = clampf(float(value), GIVEN_SPANS[key][0], GIVEN_SPANS[key][1])
	return out


## The tuning panel's source "named" (decision 716): named.<id>.rise_days,
## or named.<id>.rise_s for a row timed in seconds (714 amended (2)); and
## named.trophy_s.
static func tuning_value(path: String) -> Variant:
	if path == "named.trophy_s":
		return trophy_s
	var parts := path.split(".")
	if parts.size() != 3 or parts[0] != "named" or def(parts[1]).is_empty():
		return null
	if parts[2] == "rise_s" and def(parts[1]).has("rise_s"):
		return float(def(parts[1])["rise_s"])
	if parts[2] == "rise_days" and not def(parts[1]).has("rise_s"):
		return float(def(parts[1]).get("rise_days", RISE_DAYS))
	return null


static func set_tuning_value(path: String, value: Variant) -> bool:
	if tuning_value(path) == null or not (value is int or value is float):
		return false
	if path == "named.trophy_s":
		trophy_s = clampf(float(value), RISE_S_SPAN[0], RISE_S_SPAN[1])
	elif path.ends_with(".rise_s"):
		defs()[path.get_slice(".", 1)]["rise_s"] = clampf(float(value), RISE_S_SPAN[0], RISE_S_SPAN[1])
	else:
		defs()[path.get_slice(".", 1)]["rise_days"] = clampf(float(value), RISE_DAYS_SPAN[0], RISE_DAYS_SPAN[1])
	return true


## The panel's rows: each named one's time dead, enemy-ai's, taken at its
## next death; and the trophy's wait, taken at its next win.
static func tuning_fields() -> Array:
	var out := [{"path": "named.trophy_s", "group": "Named enemies", "min": RISE_S_SPAN[0], "max": RISE_S_SPAN[1],
		"owner": "enemy-ai", "takes": "win"}]
	for id: String in defs():
		if id.begins_with("_"):
			continue
		if def(id).has("rise_s"):
			out.append({"path": "named.%s.rise_s" % id, "group": "Named enemies", "min": RISE_S_SPAN[0],
				"max": RISE_S_SPAN[1], "owner": "enemy-ai", "takes": "death"})
		else:
			out.append({"path": "named.%s.rise_days" % id, "group": "Named enemies", "min": RISE_DAYS_SPAN[0],
				"max": RISE_DAYS_SPAN[1], "owner": "enemy-ai", "takes": "death"})
	return out