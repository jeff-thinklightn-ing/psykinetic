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
		"effects": entry.get("effects", []) if entry.get("effects") is Array else [],
		"use": str(entry.get("use", "")),
		"opens": str(entry.get("opens", "")),
		"value": maxi(int(entry.get("value", 0)), 0) if entry.get("value") is float or entry.get("value") is int else 0,
		"verb": entry.get("verb", {}) if entry.get("verb") is Dictionary else {},
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


## For tests: the catalog read again from the file on next use, anything
## added_for_test gone.
static func reset() -> void:
	_catalog = {}


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


static func has_tag(id: String, tag: String) -> bool:
	return tag in def(id).get("tags", [])


## What banking a resource gives ({"ore": 5}); {} for anything else.
## The lock [param id] opens (a key: Door.lock), "" for none.
static func opens_of(id: String) -> String:
	return str(def(id).get("opens", ""))


## What [param id] is worth in gold (the catalog's value; 0 if it gives none).
static func value_of(id: String) -> int:
	return int(def(id).get("value", 0))


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
