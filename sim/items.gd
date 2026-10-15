class_name Items
extends RefCounted
## The item catalog: what each kind of thing is, by id, read once from
## levels/items.json (CATALOG). A slot holds an id ("" empty); the thing in
## it is an instance of that id with its own history (ItemBook, server
## only). A player has Player.SLOTS slots, a chest Chest.SLOTS;
## World.try_transfer, take_item and put_item move them.
##
## A definition: id, name ("bandaging kit"), short (what a slot shows),
## color (the slot text and grey box), art (its ArtKit slot, item.<id>),
## kind (held or cell), size (metres), weight (kg), hands (0 pack only, 1
## or 2), tags, effects ([{kind, amount, ticks}]: buffs, used up), use
## (the verb it is used with), yield (a resource's counts when banked),
## made (how the town makes it, read by economy's production: {by: a trade
## (TRADES), from: {resource or item id: count}, steps} to make it, or
## {by, rework: the id it is reworked from, steps}; {} for none).
## Levels, prefabs and the builder name ids; an unknown id is dropped.

const CATALOG := "res://levels/items.json"
## Loot tables (loot_tables, decision 330).
const LOOT := "res://levels/loot.json"
## The ArtKit manifest of items' slots, generated from the catalog.
const ART_SLOTS := "res://art/kit/slots_items.json"
const ART_BUDGET := 500
## A carrier's slots (a player's, a companion's): the pack first, then two
## hands, right and left. A thing in a hand is held (hands 1 or 2; a
## two-handed one in the right hand with the left empty); World keeps to it.
## A save from before hands had the pack alone: tidy pads the hands.
const PACK := 4
const RIGHT_HAND := 4
const LEFT_HAND := 5
const CARRIED := 6
const FIELDS := ["id", "name", "short", "color", "art", "kind", "size", "weight", "hands", "tags", "effects", "use", "yield", "verb", "made",
	"opens", "value"]
## Who makes things (made's "by"), as economy's production has them.
const TRADES: Array[String] = ["smith", "cook", "carpenter"]

static var _catalog: Dictionary = {}
static var _loot: Dictionary = {}


## Every definition by id, read on first use.
static func all() -> Dictionary:
	if _catalog.is_empty():
		_catalog = read(FileAccess.get_file_as_string(CATALOG))
	return _catalog


## [param text] (the catalog file) as definitions by id, each with every
## field filled in. An entry with no id, a repeated id or a field that is
## not known is warned about; one with no usable id is left out.
static func read(text: String) -> Dictionary:
	var definitions := {}
	var data: Variant = JSON.parse_string(text)
	if data is not Dictionary or data.get("items") is not Array:
		push_warning("Items: %s has no items list" % CATALOG)
		return definitions
	for entry: Variant in data["items"]:
		if entry is not Dictionary or entry.get("id") is not String or str(entry["id"]).is_empty():
			push_warning("Items: an entry with no id: %s" % [entry])
			continue
		var id := str(entry["id"])
		if definitions.has(id):
			push_warning("Items: %s is defined twice; the first is kept" % id)
			continue
		for key: String in entry:
			if key not in FIELDS:
				push_warning("Items: %s has an unknown field %s" % [id, key])
		definitions[id] = _definition(id, entry)
		if entry.has("value") and (entry["value"] is not float and entry["value"] is not int or float(entry["value"]) < 0.0):
			push_warning("Items: %s's value %s is not a count of gold; none" % [id, entry["value"]])
	for id: String in definitions:
		var made: Dictionary = definitions[id]["made"]
		var problem := made_problem(made, definitions)
		if not problem.is_empty():
			push_warning("Items: %s's made %s; left out" % [id, problem])
			definitions[id]["made"] = {}
	return definitions


## What is wrong with a definition's [param made] given [param definitions]
## (every id), or "" if nothing: "by" a trade (TRADES), "steps" over 0, and
## either "from" (stockpile resources or item ids, each a count over 0) or
## "rework" (an item id).
static func made_problem(made: Dictionary, definitions: Dictionary) -> String:
	if made.is_empty():
		return ""
	if str(made.get("by", "")) not in TRADES:
		return "is by %s, no trade (%s)" % [made.get("by"), ", ".join(TRADES)]
	if int(made.get("steps", 0)) <= 0:
		return "takes no steps"
	if made.has("rework"):
		return "" if definitions.has(str(made["rework"])) else "reworks %s, no item" % made["rework"]
	var from: Variant = made.get("from")
	if from is not Dictionary or from.is_empty():
		return "is from nothing"
	for what: Variant in from:
		if str(what) not in Stockpile.RESOURCES and not definitions.has(str(what)):
			return "is from %s, no resource or item" % what
		if int(from[what]) <= 0:
			return "takes %s of %s" % [from[what], what]
	return ""


static func _definition(id: String, entry: Dictionary) -> Dictionary:
	var color_text := str(entry.get("color", ""))
	var size: Variant = entry.get("size")
	var tags: Array[String] = []
	for tag: Variant in entry.get("tags", []):
		tags.append(str(tag))
	var yields := {}
	var given: Variant = entry.get("yield", {})
	if given is Dictionary:
		for resource: Variant in given:
			yields[str(resource)] = int(given[resource])
	return {
		"id": id,
		"name": str(entry.get("name", id)),
		"short": str(entry.get("short", entry.get("name", id))),
		"color": Color.html(color_text) if Color.html_is_valid(color_text) else Color(0.7, 0.7, 0.7),
		"art": str(entry.get("art", "item." + id)),
		"kind": "cell" if entry.get("kind") == "cell" else "held",
		"size": Vector3(size[0], size[1], size[2]) if size is Array and size.size() == 3 else Vector3(0.3, 0.3, 0.3),
		"weight": maxf(float(entry.get("weight", 1.0)), 0.0),
		"hands": clampi(int(entry.get("hands", 1)), 0, 2),
		"tags": tags,
		"effects": effects_of(id, entry["effects"]) if entry.get("effects") is Array else [],
		"use": str(entry.get("use", "")),
		"opens": str(entry.get("opens", "")),
		"value": maxi(int(entry.get("value", 0)), 0) if entry.get("value") is float or entry.get("value") is int else 0,
		"verb": verb_from(id, entry["verb"]) if entry.get("verb") is Dictionary else {},
		"yield": yields,
		"made": _made(entry.get("made")),
	}


## A made field as read: counts as ints, steps an int; {} for none.
static func _made(value: Variant) -> Dictionary:
	if value is not Dictionary:
		return {}
	var made := {"by": str(value.get("by", "")), "steps": int(value.get("steps", 0))}
	if value.has("rework"):
		made["rework"] = str(value["rework"])
	elif value.get("from") is Dictionary:
		var from := {}
		for what: Variant in value["from"]:
			from[str(what)] = int(value["from"][what])
		made["from"] = from
	return made


## For tests: [param entry] (as a catalog entry, with an id) added to the
## catalog as if it were in the file, until reset. Its definition.
static func add_for_test(entry: Dictionary) -> Dictionary:
	var id := str(entry.get("id", ""))
	all()[id] = _definition(id, entry)
	return _catalog[id]


## For tests: the catalog and the loot tables read again from their files
## on next use, anything added for a test gone.
static func reset() -> void:
	_catalog = {}
	_loot = {}


static func exists(id: String) -> bool:
	return all().has(id)


## Every id in the catalog.
static func ids() -> Array:
	return all().keys()


## The definition of [param id] (see the class notes); {} for an unknown one.
static func def(id: String) -> Dictionary:
	return all().get(id, {})


## Its name in a sentence ("bandaging kit"); the id for an unknown one.
static func name_of(id: String) -> String:
	return str(def(id).get("name", id))


## What a slot shows ("Bandages").
static func short_of(id: String) -> String:
	return str(def(id).get("short", id))


static func color_of(id: String) -> Color:
	return def(id).get("color", Color(0.7, 0.7, 0.7))


static func weight_of(id: String) -> float:
	return float(def(id).get("weight", 0.0))


## Weapons are verbs, not damage tiers (the roadmap's rules): what a held
## weapon makes an attack do. Each kind with its own numbers and their
## defaults; every verb also has COMMON's. Combat reads them (roadmap's
## "weapons as verbs"); nothing here acts on them.
##   knockback (hammer): force, a multiple of the blow's push force.
##   block (sword, shield): the guard's arc (cells either side of facing:
##     0 straight ahead, 1 the three in front), absorb (the share of a
##     blow's damage taken off), stamina per blow taken, breaks_at (a blow
##     with this force or more breaks the guard).
##   knockdown (giant axe): arc, down_ticks (prone, can't act or resist).
##   reach (spear): cells (how far it hits), brace (stops a charge).
##   backstab (dagger): behind (damage multiple from behind, by facing).
##   ranged (bow): cells, draw_min and draw_full (ticks: the shortest draw
##     that shoots, and the one that shoots at full strength).
const VERBS := {
	"knockback": {"force": 3.0},
	"block": {"arc": 1, "absorb": 1.0, "stamina": 8, "breaks_at": 2.0},
	"knockdown": {"arc": 1, "down_ticks": 15},
	"reach": {"cells": 2, "brace": true},
	"backstab": {"behind": 2.0},
	"ranged": {"cells": 8, "draw_min": 5, "draw_full": 20},
}
## Every verb's: speed (a multiple of the wielder's attack time: under 1
## quicker), damage and force (multiples of the wielder's blow).
const COMMON := {"speed": 1.0, "damage": 1.0, "force": 1.0}


## [param verb] as the catalog gives it, every number filled in from its
## kind's defaults; {} (and a warning) for no known kind. A number that is
## not one, or under 0, takes the default; an unknown key is warned about
## and left out. [param id] for warnings.
static func verb_from(id: String, verb: Dictionary) -> Dictionary:
	var kind := str(verb.get("kind", ""))
	if not VERBS.has(kind):
		push_warning("Items: %s's verb %s is not one of %s; none" % [id, kind, ", ".join(VERBS.keys())])
		return {}
	var defaults: Dictionary = COMMON.merged(VERBS[kind])
	var out := {"kind": kind}
	for key: String in defaults:
		var given: Variant = verb.get(key, defaults[key])
		if defaults[key] is bool:
			out[key] = bool(given) if given is bool else defaults[key]
		elif (given is int or given is float) and float(given) >= 0.0:
			out[key] = int(given) if defaults[key] is int else float(given)
		else:
			push_warning("Items: %s's verb %s is %s; %s" % [id, key, given, defaults[key]])
			out[key] = defaults[key]
	for key: String in verb:
		if key != "kind" and not defaults.has(key):
			push_warning("Items: %s's verb has an unknown %s; left out" % [id, key])
	return out


## [param id]'s verb, every number filled in ({} for anything not a weapon).
static func verb_of(id: String) -> Dictionary:
	return def(id).get("verb", {})


static func has_tag(id: String, tag: String) -> bool:
	return tag in def(id).get("tags", [])


## What banking a resource gives ({"ore": 5}); {} for anything else.
## The lock [param id] opens (a key: Door.lock), "" for none.
## What a consumed thing's effects may raise, each with its name on the HUD:
## mass (food: kg, heavier and harder to shove), aura (magic) and wits
## (social time), the last two read by whatever comes to use them
## (World.buff).
const BUFF_KINDS := {"mass": "Fed", "aura": "Aura", "wits": "Wits"}


## [param effects] as the catalog gives them, each {kind, amount, ticks},
## the ones that make sense: a kind in BUFF_KINDS, an amount and ticks over
## 0 (a buff never takes anyone below baseline). [param id] for warnings.
static func effects_of(id: String, effects: Array) -> Array:
	var out := []
	for effect: Variant in effects:
		if effect is Dictionary and str(effect.get("kind", "")) in BUFF_KINDS \
				and float(effect.get("amount", 0)) > 0.0 and int(effect.get("ticks", 0)) > 0:
			out.append({"kind": str(effect["kind"]), "amount": float(effect["amount"]), "ticks": int(effect["ticks"])})
		else:
			push_warning("Items: %s's effect %s is not a buff (%s, an amount and ticks over 0); left out" % [
				id, effect, ", ".join(BUFF_KINDS.keys())])
	return out


static func opens_of(id: String) -> String:
	return str(def(id).get("opens", ""))


## What [param id] is worth in gold (the catalog's value; 0 if it gives none).
static func value_of(id: String) -> int:
	return int(def(id).get("value", 0))


## Loot tables (decision 330), read on first use: name -> its rows, each
## {item, count: [least, most], chance: 0 to 1}, as levels/loot.json has
## them. A level or the builder names one for a chest or a monster
## ("loot"), and Level rolls it as the level is built (roll_loot).
static func loot_tables() -> Dictionary:
	if _loot.is_empty():
		_loot = read_loot(FileAccess.get_file_as_string(LOOT))
	return _loot


## [param text] (loot.json) as tables. A row naming no thing in the catalog
## is warned about and left out; a count not [least, most] is [1, 1]; a
## chance is kept to 0 to 1 (1 if not given).
static func read_loot(text: String) -> Dictionary:
	var out := {}
	var parsed: Variant = JSON.parse_string(text)
	var tables: Variant = parsed.get("tables") if parsed is Dictionary else null
	if not tables is Dictionary:
		push_warning("Items: no loot tables in %s" % LOOT)
		return out
	for table: String in tables:
		var rows: Array[Dictionary] = []
		var given: Variant = tables[table]
		for row: Variant in (given if given is Array else []):
			var id := str(row.get("item", "")) if row is Dictionary else ""
			if not exists(id):
				push_warning("Items: loot table %s names \"%s\", no thing in the catalog; left out" % [table, id])
				continue
			var count: Variant = row.get("count", [1, 1])
			var pair: bool = count is Array and count.size() == 2
			var least := maxi(0, int(count[0])) if pair else 1
			var most := maxi(least, int(count[1])) if pair else 1
			rows.append({"item": id, "count": [least, most], "chance": clampf(float(row.get("chance", 1.0)), 0.0, 1.0)})
		out[table] = rows
	return out


## Whether [param table] is a loot table.
static func has_loot(table: String) -> bool:
	return loot_tables().has(table)


## [param table] rolled: the ids it gives, row by row (each with its
## chance, then a count from least to most), at most [param room]. Drawn by
## [param seed_text]: one seed gives the same every time, so a level built
## twice is stocked the same. An unknown table gives nothing.
static func roll_loot(table: String, seed_text: String, room: int) -> PackedStringArray:
	var out := PackedStringArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text.sha256_text())  # Mixed: near names, near seeds, alike rolls.
	for row: Dictionary in loot_tables().get(table, []):
		if rng.randf() >= float(row["chance"]):
			continue
		for i in rng.randi_range(int(row["count"][0]), int(row["count"][1])):
			if out.size() >= room:
				return out
			out.append(str(row["item"]))
	return out


## For tests: [param rows] as table [param table], as if in the file,
## until reset.
static func add_loot_for_test(table: String, rows: Array) -> void:
	loot_tables()[table] = read_loot(JSON.stringify({"tables": {table: rows}}))[table]


static func yield_of(id: String) -> Dictionary:
	return def(id).get("yield", {}).duplicate() if has_tag(id, "resource") else {}


## Every item's ArtKit slot, as art/kit/slots_items.json holds them
## (ART_SLOTS, written by tools/items_art_slots.gd): a held piece has its
## grip at the origin and, two-handed, grip_2 up its length; budget a
## prop's (docs/art_style.md).
static func art_slots() -> Dictionary:
	var slots := {}
	for id: String in ids():
		var item := def(id)
		var size: Vector3 = item["size"]
		var entry := {
			"category": "items",
			"type": "mesh",
			"kind": item["kind"],
			"size": [snappedf(size.x, 0.001), snappedf(size.y, 0.001), snappedf(size.z, 0.001)],
			"budget": ART_BUDGET,
			"uses": "%s (Items: levels/items.json): in a pack or chest as its icon, in a hand, on the ground" % item["name"],
		}
		if item["kind"] == "held":
			entry["sockets"] = {"grip": [0, 0, 0]}
			if item["hands"] == 2:
				entry["sockets"]["grip_2"] = [0, snappedf(size.y * 0.6, 0.01), 0]
		slots[item["art"]] = entry
	return {"about": "Generated from the item catalog (levels/items.json) by tools/items_art_slots.gd; do not edit by hand.", "slots": slots}


## [param contents] as [param count] slots: known item ids or "", cut or
## padded to size.
static func tidy(contents: Variant, count: int) -> PackedStringArray:
	var slots := PackedStringArray()
	slots.resize(count)
	if contents is Array or contents is PackedStringArray:
		for i in mini(count, contents.size()):
			var id := str(contents[i])
			slots[i] = id if exists(id) else ""
	return slots
