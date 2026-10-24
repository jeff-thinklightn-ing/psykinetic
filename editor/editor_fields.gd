class_name EditorFields
extends RefCounted
## The level editor's properties panel's table (decision 506): for each
## kind of thing a level.json holds, where it is found and its fields, each
## of a type from a short closed set that says how it is shown, checked and
## written. A new level.json key is a row here; the panel builds itself
## from the rows and knows no kind by name. Every edit is one undo step
## through MapDoc ("config <key>": the key's whole value as it was), checked
## before it is written; after, the level goes through Level.parse and
## WorldMap's problems, whose warnings are said, not refused.
##
## A thing is {kind, id}: id the cell for a thing found by its "at" (a link,
## an entity, a building), the key for a keyed one (a place, a market, a
## spawn point), the index for a listed one (a start, a stream, an anchor),
## "" for the level itself.

## The types, each with its widget (LevelEditor) and its check (check).
const TYPES: Array[String] = ["string", "int", "float", "bool", "enum", "level", "spawn", "faction", "item", "items", "region",
	"rect", "cell", "cells", "order", "action"]

## kind -> {where, list (the level.json key, "a/b" inside an object), label,
## fields: [{key ("a/b" inside an object), label, type, min, max, choices,
## required, of (a spawn's level field)}]}. where: "config" (the level's
## own keys), "at" (a list matched by its entries' "at"), "keyed" (an
## object by key, its entries' "at" their cell), "spawn" (spawn_points:
## name -> cell), "indexed" (a list by index).
const KINDS := {
	"level": {"where": "config", "label": "The level", "fields": [
		{"key": "name", "label": "name", "type": "string", "required": true},
		{"key": "outdoor", "label": "outdoor", "type": "bool"},
		{"key": "zone", "label": "zone", "type": "enum", "choices": "zones"},
		{"key": "region", "label": "region (its weather)", "type": "region"},
		{"key": "border", "label": "past its edge", "type": "enum", "choices": ["forest", "none"]},
		{"key": "north", "label": "north is", "type": "enum", "choices": "norths"},
		{"key": "ambient", "label": "light (no sky)", "type": "float", "min": 0.0, "max": 1.0},
		{"key": "damp", "label": "too damp to light", "type": "bool"},
		{"key": "walls", "label": "wall set", "type": "string"},
		{"key": "floors", "label": "floor set", "type": "string"},
		{"key": "depth", "label": "depth (stairs down to deeper)", "type": "int", "min": 0, "max": 9},
		{"key": "canopy/kind", "label": "canopy", "type": "enum", "choices": ["", "evergreen", "broadleaf"]},
		{"key": "neighbours/north", "label": "north neighbour", "type": "level"},
		{"key": "neighbours/east", "label": "east neighbour", "type": "level"},
		{"key": "neighbours/south", "label": "south neighbour", "type": "level"},
		{"key": "neighbours/west", "label": "west neighbour", "type": "level"},
		{"key": "regenerate/generator", "label": "regenerates by", "type": "string"},
		{"key": "regenerate/every_days", "label": "every (days)", "type": "int", "min": 1, "max": 365},
	]},
	"link": {"where": "at", "list": "links", "label": "Link", "fields": [
		{"key": "to_map", "label": "to level", "type": "level", "required": true},
		{"key": "to_spawn", "label": "arriving at", "type": "spawn", "of": "to_map"},
		{"key": "one_way", "label": "one way", "type": "bool"},
		{"key": "closed", "label": "closed", "type": "bool"},
	]},
	"entity": {"where": "at", "list": "entities", "label": "Thing", "fields": [
		{"key": "name", "label": "name", "type": "string"},
		{"key": "props/slots", "label": "in it", "type": "items"},
	]},
	"building": {"where": "at", "list": "buildings", "label": "Building", "fields": [
		{"key": "slot", "label": "slot", "type": "cells"},
		{"key": "facing", "label": "facing", "type": "enum", "choices": "facings"},
		{"key": "use", "label": "use", "type": "string"},
		{"key": "town", "label": "town (its store's key)", "type": "string"},
		{"key": "length", "label": "length (a bridge)", "type": "int", "min": 1, "max": 64, "only": "bridge"},
		{"key": "width", "label": "width (a bridge)", "type": "int", "min": 1, "max": 2, "only": "bridge"},
	]},
	"place": {"where": "keyed", "list": "places", "label": "Place", "fields": [
		{"key": "name", "label": "name", "type": "string"},
		{"key": "kind", "label": "kind", "type": "enum", "choices": "place_kinds"},
		{"key": "holder", "label": "held by", "type": "faction"},
		{"key": "radius", "label": "radius", "type": "int", "min": 1, "max": 64},
		{"key": "worth", "label": "worth", "type": "int", "min": 0, "max": 100},
		# The stockpile place whose town works it (decision 517).
		{"key": "town", "label": "works for (a stockpile)", "type": "string"},
	]},
	"market": {"where": "keyed", "list": "markets", "label": "Market", "fields": [
		{"key": "name", "label": "name", "type": "string", "required": true},
		# A market is not painted: its cell is picked here (decision 506's
		# one "at" a field edits; nothing else draws it).
		{"key": "at", "label": "at", "type": "cell"},
	]},
	"spawn": {"where": "spawn", "list": "spawn_points", "label": "Spawn point", "fields": [
		{"key": "name", "label": "name", "type": "string", "required": true},
	]},
	"start": {"where": "indexed", "list": "starts", "label": "Start", "fields": [
		{"key": "order", "label": "order", "type": "order"},
	]},
	"stream": {"where": "indexed", "list": "streams", "label": "Stream", "fields": [
		{"key": "path", "label": "course", "type": "cells"},
		{"key": "reverse", "label": "reverse its flow", "type": "action"},
		{"key": "delete", "label": "take it out (the water stays)", "type": "action"},
	]},
	"anchor": {"where": "indexed", "list": "regenerate/anchors", "label": "Anchor", "fields": [
		{"key": "name", "label": "name", "type": "string"},
		{"key": "rect", "label": "kept", "type": "rect"},
	]},
}
## level.json keys Level reads that the panel does not offer (painted, laid
## by other tools, or not hand-edited): the every-key check's other half.
const NOT_OFFERED: Array[String] = ["legend", "became", "loot", "clearings", "roofs", "town_walls", "item_style", "grave_goods", "monsters", "centre",
	"herds", "dead_ground", "building_codes", "niches", "plots", "decor", "rooms"]
const FACINGS := {"north": [0, -1], "east": [1, 0], "south": [0, 1], "west": [-1, 0]}


## The things on cell [param at] of [param doc]'s level, topmost first: what
## a click on it selects, a second click the next.
static func things_at(doc: MapDoc, at: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var meaning := doc.map.cell(at)
	if meaning.begins_with("monster_"):
		out.append({"kind": "monster", "id": at})
	elif meaning in ["crate", "cart", "chest"]:
		out.append({"kind": "entity", "id": at})
	if not doc.link_of(at).is_empty():
		out.append({"kind": "link", "id": at})
	var starts: Variant = doc.config.get("starts", [])
	for i in (starts as Array).size() if starts is Array else 0:
		if Level._tile(starts[i]) == at:
			out.append({"kind": "start", "id": i})
	var points: Variant = doc.config.get("spawn_points", {})
	for name: Variant in (points as Dictionary).keys() if points is Dictionary else []:
		if Level._tile(points[name]) == at:
			out.append({"kind": "spawn", "id": str(name)})
	for kind: String in ["place", "market"]:
		var listed: Variant = doc.config.get(KINDS[kind]["list"], {})
		for key: Variant in (listed as Dictionary).keys() if listed is Dictionary else []:
			if listed[key] is Dictionary and Level._tile(listed[key].get("at")) == at:
				out.append({"kind": kind, "id": str(key)})
	var buildings: Variant = doc.config.get("buildings", [])
	for entry: Variant in buildings if buildings is Array else []:
		var rect: Variant = Level.building_rect(entry)
		if rect != null and (rect as Rect2i).has_point(at):
			out.append({"kind": "building", "id": Level._tile(entry.get("at"))})
	var streams: Variant = doc.config.get("streams", [])
	for i in (streams as Array).size() if streams is Array else 0:
		var path: Variant = streams[i].get("path", []) if streams[i] is Dictionary else []
		if path is Array and (path as Array).any(func(each: Variant) -> bool: return Level._tile(each) == at):
			out.append({"kind": "stream", "id": i})
	var anchors: Array = _value(doc.config, "regenerate/anchors", []) if _value(doc.config, "regenerate/anchors", []) is Array else []
	for i in anchors.size():
		var rect := _rect(anchors[i].get("rect") if anchors[i] is Dictionary else null)
		if rect.size != Vector2i.ZERO and rect.has_point(at):
			out.append({"kind": "anchor", "id": i})
	return out


## The fields of [param thing] that it has (a bridge's length only on a
## bridge).
static func fields_of(doc: MapDoc, thing: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var entry := read(doc, thing)
	for field: Dictionary in KINDS.get(thing["kind"], {}).get("fields", []):
		if field.has("only") and str(entry.get("slot", "")) != field["only"]:
			continue
		out.append(field)
	return out


## [param thing]'s entry as level.json has it now ({} for none; a spawn
## point's {name, at}; a start's {at, order}; the level's whole config).
static func read(doc: MapDoc, thing: Dictionary) -> Dictionary:
	var spec: Dictionary = KINDS.get(thing["kind"], {})
	match spec.get("where", ""):
		"config":
			return doc.config
		"at":
			for each: Variant in _value(doc.config, spec["list"], []) if _value(doc.config, spec["list"], []) is Array else []:
				if each is Dictionary and Level._tile(each.get("at")) == thing["id"]:
					return each
			return {}
		"keyed":
			var listed: Variant = _value(doc.config, spec["list"], {})
			return listed.get(thing["id"], {}) if listed is Dictionary else {}
		"spawn":
			var points: Variant = doc.config.get("spawn_points", {})
			return {"name": thing["id"], "at": points.get(thing["id"])} if points is Dictionary and points.has(thing["id"]) else {}
		"indexed":
			var listed: Variant = _value(doc.config, spec["list"], [])
			if listed is Array and int(thing["id"]) < (listed as Array).size():
				var each: Variant = listed[int(thing["id"])]
				return each if each is Dictionary else {"at": each, "order": int(thing["id"])}
	return {}


## The value of [param key] ("a/b" inside an object) in [param entry], or
## [param default].
static func _value(entry: Variant, key: String, default: Variant = null) -> Variant:
	var at: Variant = entry
	for part in key.split("/"):
		if not at is Dictionary or not (at as Dictionary).has(part):
			return default
		at = at[part]
	return at


static func value_of(doc: MapDoc, thing: Dictionary, key: String) -> Variant:
	if KINDS[thing["kind"]]["where"] == "indexed" and key == "order":
		return int(thing["id"])
	return _value(read(doc, thing), key)


## What is wrong with [param value] for [param field] of [param thing]: ""
## if nothing (it may be written), else why not.
static func check(doc: MapDoc, thing: Dictionary, field: Dictionary, value: Variant) -> String:
	var label := str(field.get("label", field["key"]))
	match field["type"]:
		"string":
			if not value is String:
				return "%s is words" % label
			if field.get("required", false) and (value as String).strip_edges().is_empty():
				return "%s cannot be empty" % label
		"int", "float":
			if not (value is int or value is float):
				return "%s is a number" % label
			if field.has("min") and value < field["min"] or field.has("max") and value > field["max"]:
				return "%s is %s to %s" % [label, field.get("min", "-"), field.get("max", "-")]
		"bool":
			if not value is bool:
				return "%s is yes or no" % label
		"enum":
			if not value in choices(field):
				return "%s is one of %s" % [label, ", ".join(choices(field).map(func(each: Variant) -> String: return str(each)))]
		"level":
			if not value is String or (not (value as String).is_empty() and not value in Level.names()):
				return "%s: %s is no level" % [label, value]
			if field.get("required", false) and (value as String).is_empty():
				return "%s cannot be empty" % label
		"spawn":
			var level_name := str(value_of(doc, thing, str(field.get("of", ""))))
			if not value is String:
				return "%s is a spawn point's name" % label
			if not (value as String).is_empty() and not value in spawns_of(level_name):
				return "%s: %s has no spawn point %s (it has %s)" % [label, level_name, value, ", ".join(spawns_of(level_name))]
		"faction":
			if not value is String or not (value == Factions.NOBODY or Factions.read().has(value)):
				return "%s: %s is no faction (%s, or nobody)" % [label, value, ", ".join(Factions.read().names())]
		"item":
			if not value in Items.ids():
				return "%s: %s is no item" % [label, value]
		"items":
			if not value is Array:
				return "%s is a list of items" % label
			for each: Variant in value:
				if not each in Items.ids():
					return "%s: %s is no item" % [label, each]
		"region":
			var entry: Variant = Lore.entries().get(str(value))
			if not (entry is Dictionary and entry.get("type") == "region"):
				return "%s: %s is no lore region" % [label, value]
		"rect":
			var rect := _rect(value)
			if rect.size.x < 1 or rect.size.y < 1:
				return "%s is x, y, width, height, each side 1 or more" % label
			if not Rect2i(Vector2i.ZERO, doc.map.size).encloses(rect):
				return "%s goes off the map" % label
		"cell":
			var at: Variant = value if value is Vector2i else Level._tile(value)
			if at == null or not doc.map.in_bounds(at):
				return "%s is a cell on the map" % label
		"cells", "order", "action":
			return "%s is not written so" % label
	return ""


## The choices an enum field offers.
static func choices(field: Dictionary) -> Array:
	var given: Variant = field.get("choices", [])
	if given is Array:
		return given
	match str(given):
		"zones":
			return DayNight.ZONES.duplicate()
		"norths":
			return Level.NORTHS.keys()
		"place_kinds":
			return Level.PLACE_KINDS.duplicate()
		"facings":
			return FACINGS.keys()
	return []


## The spawn points level [param level_name] has.
static func spawns_of(level_name: String) -> Array[String]:
	var out: Array[String] = []
	if level_name.is_empty() or not level_name in Level.names():
		return out
	out.assign(Level.load_level(level_name).get("spawn_points", {}).keys())
	out.sort()
	return out


## Writes [param value] to [param field] of [param thing] as one undo step,
## if check says it may be: "" when written (or nothing changed), else why
## not (nothing is changed then).
static func write(doc: MapDoc, thing: Dictionary, field: Dictionary, value: Variant) -> String:
	var why := check(doc, thing, field, value)
	if not why.is_empty():
		return why
	var spec: Dictionary = KINDS[thing["kind"]]
	var key: String = field["key"]
	if field["type"] == "enum" and str(field.get("choices", "")) == "facings":
		value = FACINGS[value]
	if field["type"] == "rect":
		var rect := _rect(value)
		value = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	if field["type"] == "cell":
		var at: Vector2i = value if value is Vector2i else Level._tile(value)
		value = [at.x, at.y]
	match spec["where"]:
		"config":
			var top := key.split("/")[0]
			var whole: Variant = doc.config.get(top)
			var changed: Variant = _with(whole, key.split("/").slice(1), value) if key.contains("/") else value
			if changed is String and (changed as String).is_empty() and not field.get("required", false):
				changed = null
			return _put(doc, top, changed)
		"at", "indexed":
			var list_key: String = spec["list"]
			var listed: Array = (_value(doc.config, list_key, []) as Array).duplicate(true) if _value(doc.config, list_key, []) is Array else []
			var index := -1
			for i in listed.size():
				if spec["where"] == "indexed" and i == int(thing["id"]) or spec["where"] == "at" and listed[i] is Dictionary \
						and Level._tile(listed[i].get("at")) == thing["id"]:
					index = i
			var entry: Dictionary = listed[index].duplicate(true) if index >= 0 and listed[index] is Dictionary else {}
			if index < 0:
				if spec["where"] != "at":
					return "there is no such %s" % thing["kind"]
				entry = {"at": [thing["id"].x, thing["id"].y]}
			entry = _with(entry, key.split("/"), value)
			if index >= 0:
				listed[index] = entry
			else:
				listed.append(entry)
			return _put_path(doc, list_key, listed)
		"keyed":
			var listed: Dictionary = (_value(doc.config, spec["list"], {}) as Dictionary).duplicate(true) if _value(doc.config, spec["list"], {}) is Dictionary else {}
			if not listed.has(thing["id"]):
				return "there is no such %s" % thing["kind"]
			listed[thing["id"]] = _with(listed[thing["id"]], key.split("/"), value)
			return _put_path(doc, spec["list"], listed)
		"spawn":
			return "a spawn point is renamed by rename_spawn (it may change other levels)"
	return "%s cannot be written" % thing["kind"]


## [param whole] (an object, or null) with [param path] set to [param value].
static func _with(whole: Variant, path: PackedStringArray, value: Variant) -> Dictionary:
	var out: Dictionary = (whole as Dictionary).duplicate(true) if whole is Dictionary else {}
	if path.size() == 1:
		if value == null:
			out.erase(path[0])
		else:
			out[path[0]] = value
		return out
	out[path[0]] = _with(out.get(path[0]), path.slice(1), value)
	return out


## level.json's [param list_key] ("a/b" inside an object) set to [param value], one undo step.
static func _put_path(doc: MapDoc, list_key: String, value: Variant) -> String:
	if not list_key.contains("/"):
		return _put(doc, list_key, value)
	var parts := list_key.split("/")
	return _put(doc, parts[0], _with(doc.config.get(parts[0]), parts.slice(1), value))


static func _put(doc: MapDoc, top: String, value: Variant) -> String:
	if doc.config.get(top) == value:
		return ""
	doc.apply_changes({"config": {top: value}})
	return ""


## Runs [param action] ("reverse", "delete") on [param thing], one undo
## step; "" when done, else why not.
static func act(doc: MapDoc, thing: Dictionary, action: String) -> String:
	var spec: Dictionary = KINDS[thing["kind"]]
	if spec["where"] != "indexed":
		return "%s has no %s" % [thing["kind"], action]
	var listed: Array = (_value(doc.config, spec["list"], []) as Array).duplicate(true)
	var index := int(thing["id"])
	if index >= listed.size():
		return "there is no such %s" % thing["kind"]
	match action:
		"reverse":
			var entry: Dictionary = listed[index]
			var path: Array = entry.get("path", []).duplicate()
			path.reverse()
			entry["path"] = path
		"delete":
			listed.remove_at(index)
		"up", "down":
			var to := index + (-1 if action == "up" else 1)
			if to < 0 or to >= listed.size():
				return "it is already %s" % ("first" if action == "up" else "last")
			var moved: Variant = listed[index]
			listed[index] = listed[to]
			listed[to] = moved
		_:
			return "no such action %s" % action
	return _put_path(doc, spec["list"], listed if not listed.is_empty() else null)


## The links in other levels that arrive at spawn point [param old_name] of
## level [param level_name]: [{level, at}]. Renaming it changes them too.
static func links_arriving(level_name: String, old_name: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var all: Array[String] = Level.names()
	for each in Level.registered_names():
		if not each in all:
			all.append(each)
	for other in all:
		if other == level_name:
			continue
		for link: Dictionary in Level.load_level(other).get("links", []):
			if link.get("to_map") == level_name and link.get("to_spawn") == old_name:
				out.append({"level": other, "at": link["tile"]})
	return out


## Spawn point [param old_name] of [param doc]'s level renamed
## [param new_name], one undo step there, and the links arriving at it in
## [param others] (MapDocs of the levels links_arriving names, which the
## user agreed to change) changed and saved through MapDoc, so Level's
## warnings fire there too; "" when done, else why not (nothing changed).
static func rename_spawn(doc: MapDoc, level_name: String, old_name: String, new_name: String, others: Array) -> String:
	var points: Dictionary = (doc.config.get("spawn_points", {}) as Dictionary).duplicate(true)
	if not points.has(old_name):
		return "there is no spawn point %s" % old_name
	if new_name.strip_edges().is_empty() or points.has(new_name):
		return "a spawn point needs a name of its own"
	var renamed := {}
	for key: String in points:
		renamed[new_name if key == old_name else key] = points[key]
	for other: MapDoc in others:
		var links: Array = (other.config.get("links", []) as Array).duplicate(true)
		for link: Variant in links:
			if link is Dictionary and link.get("to_map") == level_name and link.get("to_spawn") == old_name:
				link["to_spawn"] = new_name
		other.apply_changes({"config": {"links": links}})
		other.save()
	return _put(doc, "spawn_points", renamed)


## What Level.parse and WorldMap say of [param doc]'s level now, as
## [param level_name]: its warnings and its problems.
static func issues(doc: MapDoc, level_name: String) -> Array[String]:
	var layout := doc.map.to_image()
	var height: Image = doc.map.to_height_image() if not doc.map.heights.is_empty() else null
	var out: Array[String] = []
	var relief := doc.map.to_relief_image()
	out.assign(Level.parse(layout, height, doc.config, relief)["warnings"])
	if level_name in Level.names():
		var names: Array[String] = Level.names()
		var sources := {level_name: {"layout": layout, "height": height, "config": doc.config, "relief": relief}}
		for problem: String in WorldMap.build(names, sources).problems():
			if problem.begins_with(level_name + ":") and not problem.trim_prefix(level_name + ": ") in out:
				out.append(problem.trim_prefix(level_name + ": "))
	return out


## The issues that are [param thing]'s: those naming its cell, its key or
## its index.
static func issues_of(doc: MapDoc, thing: Dictionary, all: Array[String]) -> Array[String]:
	var out: Array[String] = []
	var entry := read(doc, thing)
	var at: Variant = Level._tile(entry.get("at")) if thing["kind"] != "level" else null
	if thing["id"] is Vector2i:
		at = thing["id"]
	for issue in all:
		if at != null and str(at) in issue or thing["id"] is String and not thing["id"].is_empty() and thing["id"] in issue:
			out.append(issue)
	return out


## A market put on cell [param at] (one undo step), keyed market, market_2...
## and named "the market" to be renamed; its key.
static func add_market(doc: MapDoc, at: Vector2i) -> String:
	var markets: Dictionary = (doc.config.get("markets", {}) as Dictionary).duplicate(true) if doc.config.get("markets") is Dictionary else {}
	var key := "market"
	var n := 2
	while markets.has(key):
		key = "market_%d" % n
		n += 1
	markets[key] = {"at": [at.x, at.y], "name": "the market"}
	_put(doc, "markets", markets)
	return key


static func _rect(value: Variant) -> Rect2i:
	if value is Rect2i:
		return value
	if value is Array and (value as Array).size() == 4:
		return Rect2i(int(value[0]), int(value[1]), int(value[2]), int(value[3]))
	return Rect2i()
