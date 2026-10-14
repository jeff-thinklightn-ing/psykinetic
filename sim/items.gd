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
## (the verb it is used with), yield (a resource's counts when banked).
## Levels, prefabs and the builder name ids; an unknown id is dropped.

const CATALOG := "res://levels/items.json"
## The ArtKit manifest of items' slots, generated from the catalog.
const ART_SLOTS := "res://art/kit/slots_items.json"
const ART_BUDGET := 500
const FIELDS := ["id", "name", "short", "color", "art", "kind", "size", "weight", "hands", "tags", "effects", "use", "yield", "verb"]

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
	return definitions


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
		"verb": entry.get("verb", {}) if entry.get("verb") is Dictionary else {},
		"yield": yields,
	}


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
