class_name Items
extends RefCounted
## The things that go in slots, by id. An empty slot is "". A player has
## Player.SLOTS of them, a chest Chest.SLOTS; World.try_transfer is the
## only way anything moves between them.
##
## An item is only an id for now: it does nothing yet, it exists to be
## moved (the bandaging kit is the first).

const ALL := {
	"bandaging_kit": {"name": "bandaging kit", "short": "Bandages", "color": Color(0.92, 0.9, 0.84)},
}


static func exists(id: String) -> bool:
	return ALL.has(id)


## Its name in a sentence ("bandaging kit"); the id for an unknown one.
static func name_of(id: String) -> String:
	return str(ALL[id]["name"]) if ALL.has(id) else id


## What a slot shows ("Bandages").
static func short_of(id: String) -> String:
	return str(ALL[id]["short"]) if ALL.has(id) else id


static func color_of(id: String) -> Color:
	return ALL[id]["color"] if ALL.has(id) else Color(0.7, 0.7, 0.7)


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
