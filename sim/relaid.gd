class_name Relaid
## A level laid out again in place (decision 774: Umbrage round its chapel),
## its saved state carried onto the new layout once, nothing dropped. Unlike
## a remade level (Level.REMADE, 756), whose whole section is dropped, a
## re-laid one keeps it: its places that moved with their building keep what
## they hold under their new ids, its moved markers keep their saved things
## (by key, so the game neither duplicates nor drops them), and whatever lay
## or stood on a cell that is no floor now goes to the nearest floor.
## Main._boot calls move on the snapshot as read, before anything reads it.

## Level -> {decision, places: old place id -> new (with the area's prefix,
## as Holdings keys them; "stockpile:" keys follow), markers: old marker
## cell "x,y" -> new [x, y]}.
const RELAID: Dictionary = {
	"wilds": {
		"decision": 774,
		"places": {"wilds/temple@217,201": "wilds/temple@189,201"},
		"markers": {
			"209,199": [190, 196],  # The depot's counter, to the store.
			"211,199": [193, 196],  # The shop's.
			"217,195": [198, 201],  # The temple's, in the chapel's east end.
			"221,225": [205, 208],  # Snagfin's three chests, by his stall.
			"219,226": [206, 208],
			"219,225": [206, 207],
			"195,220": [172, 193],  # The locker, its back to the home house's north wall.
		},
	},
}
## How far the nearest floor is looked for (cells).
const FLOOR_REACH := 12


## Carries [param snapshot] (Snapshot.load's, its players PlayerRecords)
## onto each level in RELAID not yet in [param done] (level -> the decision
## it was moved for, under done_key; Main's saved "remade"), and marks it
## done. A new world has nothing to move. [param level_of] (level name ->
## Level.load_level's dict) gives the level as it loads here. A level that
## loads laid out the old way (an overlay copy edited before the re-lay
## shadows the new one) is left alone and not marked done: one line says
## so, and it moves at the first boot that loads the new layout. Returns one
## count-only line per level, for release to grep.
static func move(snapshot: Dictionary, done: Dictionary, level_of: Callable) -> Array[String]:
	var lines: Array[String] = []
	for level: String in RELAID:
		var plan: Dictionary = RELAID[level]
		var key := done_key(level)
		if int(done.get(key, 0)) == int(plan["decision"]):
			continue
		var loaded: Dictionary = level_of.call(level)
		if not is_laid(loaded, plan):
			lines.append("[level] %s not re-laid (%d): it loads laid out the old way (an overlay copy?); nothing moved, it waits" % [level, plan["decision"]])
			continue
		done[key] = int(plan["decision"])
		if not snapshot.get("ok", false):
			continue
		var floor := {}
		for cell: Vector2i in loaded.get("terrain", {}).get("floor", []):
			floor[cell] = true
		var counts := {"places": 0, "markers": 0, "off": 0, "kept": 0}
		_rename_places(snapshot, plan["places"], counts)
		var zones: Dictionary = snapshot.get("zones", {}) if snapshot.get("zones") is Dictionary else {}
		if zones.get(level) is Dictionary:
			_move_markers(zones[level], plan["markers"], counts)
			# A pile's things are at "level@x,y" in the item book: they follow it.
			_rename_places(snapshot, _onto_floor(level, zones[level], floor, counts), {"places": 0})
		for record: PlayerRecord in snapshot.get("players", []):
			if record.zone != level:
				continue
			if not floor.has(record.tile):
				_count_onto(record.tile, nearest_floor(record.tile, floor), counts)
				record.tile = nearest_floor(record.tile, floor)
			var with: Variant = _cell(record.companion.get("tile"))
			if with is Vector2i and not floor.has(with):
				record.companion["tile"] = null  # She comes back beside them.
				counts["off"] += 1
		lines.append("[level] re-laid %s (%d): %d place keys renamed, %d saved markers carried, %d things moved onto floor, %d left where they were (no floor near)" % [
			level, plan["decision"], counts["places"], counts["markers"], counts["off"], counts["kept"]])
	return lines


## Every key and string under [param snapshot] naming a place in
## [param places] (or its stockpile, "stockpile:" + id) renamed, and each
## player record's (through its dict) likewise.
static func _rename_places(snapshot: Dictionary, places: Dictionary, counts: Dictionary) -> void:
	for key: Variant in snapshot.keys():
		if key in ["zones", "players", "ok"]:
			continue
		snapshot[key] = _renamed(snapshot[key], places, counts)
	var players: Array = snapshot.get("players", [])
	for index in players.size():
		var record: PlayerRecord = players[index]
		var before: int = counts["places"]
		var dict: Variant = _renamed(record.to_dict(), places, counts)
		if counts["places"] > before:
			var again := PlayerRecord.from_dict(dict)
			if again != null:
				players[index] = again


static func _renamed(value: Variant, places: Dictionary, counts: Dictionary) -> Variant:
	if value is String:
		return _rename(value, places, counts)
	if value is Array:
		for index in (value as Array).size():
			value[index] = _renamed(value[index], places, counts)
		return value
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[_rename(key, places, counts) if key is String else key] = _renamed(value[key], places, counts)
		return out
	return value


static func _rename(text: String, places: Dictionary, counts: Dictionary) -> String:
	if places.has(text):
		counts["places"] += 1
		return places[text]
	if text.begins_with("stockpile:") and places.has(text.trim_prefix("stockpile:")):
		counts["places"] += 1
		return "stockpile:" + str(places[text.trim_prefix("stockpile:")])
	return text


## The zone's saved level entities, monster records and dead timers whose
## marker moved: keyed and stood at the new marker.
static func _move_markers(section: Dictionary, markers: Dictionary, counts: Dictionary) -> void:
	var specs: Array = []
	for entry: Dictionary in section.get("entities", []):
		specs.append(entry["spec"])
	for record: Dictionary in section.get("records", []):
		if record.get("entry") is Dictionary:
			specs.append(record["entry"])
	for spec: Dictionary in specs:
		var key := str(spec.get("spawn_key", ""))
		if markers.has(key):
			var to: Array = markers[key]
			spec["spawn_key"] = "%d,%d" % [to[0], to[1]]
			spec["tile"] = Vector2i(to[0], to[1])
			counts["markers"] += 1
	for respawn: Dictionary in section.get("respawns", []):
		var key := str(respawn.get("spawn_key", ""))
		if markers.has(key):
			var to: Array = markers[key]
			respawn["spawn_key"] = "%d,%d" % [to[0], to[1]]
			counts["markers"] += 1


## The zone's saved entities and ground piles on a cell that is no floor
## now: on the nearest floor. Returns the piles' item-book places renamed,
## "level@x,y" old -> new.
static func _onto_floor(level: String, section: Dictionary, floor: Dictionary, counts: Dictionary) -> Dictionary:
	var piles := {}
	for entry: Dictionary in section.get("entities", []):
		var tile: Variant = _cell(entry["spec"].get("tile"))
		if tile is Vector2i and not floor.has(tile):
			entry["spec"]["tile"] = nearest_floor(tile, floor)
			_count_onto(tile, entry["spec"]["tile"], counts)
	for pile: Dictionary in section.get("ground", []):
		var cell: Variant = _cell(pile.get("cell"))
		if cell is Vector2i and not floor.has(cell):
			var to := nearest_floor(cell, floor)
			_count_onto(cell, to, counts)
			if to == cell:
				continue
			piles["%s@%d,%d" % [level, cell.x, cell.y]] = "%s@%d,%d" % [level, to.x, to.y]
			pile["cell"] = to
	return piles


## Whether [param level] (Level.load_level's) is laid out as [param plan]
## moves to: each place renamed to and each marker moved to is there.
static func is_laid(level: Dictionary, plan: Dictionary) -> bool:
	var places: Dictionary = level.get("places", {})
	for to: String in plan["places"].values():
		if not places.has(to.get_slice("/", 1)):
			return false
	var marked := {}
	for spec: Dictionary in level.get("entities", []):
		marked[spec.get("tile")] = true
	for to: Array in plan["markers"].values():
		if not marked.has(Vector2i(to[0], to[1])):
			return false
	return true


## The key [param level]'s move is marked done under in Main's saved
## "remade" (its own, so a later remake of the level, Level.REMADE, is not
## taken for done).
static func done_key(level: String) -> String:
	return "relaid/" + level


## Counts a thing off the floor at [param from]: moved onto [param to], or
## kept where it was when no floor is near (never dropped).
static func _count_onto(from: Vector2i, to: Vector2i, counts: Dictionary) -> void:
	counts["off" if to != from else "kept"] += 1


## A saved cell, a Vector2i or a JSON pair, as a Vector2i; else null.
static func _cell(value: Variant) -> Variant:
	return value if value is Vector2i else Snapshot.vector(value)


## [param cell] if it is in [param floor], else the nearest floor cell
## within FLOOR_REACH (rings outward, the first found in reading order), else
## [param cell] as it is.
static func nearest_floor(cell: Vector2i, floor: Dictionary) -> Vector2i:
	if floor.has(cell) or floor.is_empty():
		return cell
	for reach in range(1, FLOOR_REACH + 1):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dy in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				if maxi(absi(dx), absi(dy)) != reach:
					continue
				var at := cell + Vector2i(dx, dy)
				var d := Vector2(dx, dy).length()
				if floor.has(at) and d < best_d:
					best = at
					best_d = d
		if best_d < INF:
			return best
	return cell
