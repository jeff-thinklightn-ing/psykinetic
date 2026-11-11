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
## Markers taken out of a level, their saved entities with them, once
## (decision 807: chests only in dungeons). Each {level, decision, removed:
## marker cell "x,y" -> {to}}: the saved level entity keyed to that cell is
## dropped, and what it held (its slots, and every thing the item book has
## at it) goes where "to" says: "ground", a pile on its cell (or the nearest
## floor). Each entry is done under its own key (done_key_of), so it never
## blocks a level's RELAID or another decision's removals.
const REMOVED: Array[Dictionary] = [
	{"level": "wilds", "decision": 807, "removed": {
		"122,138": {"to": "ground"},  # The old farmstead's hut chests, empty since 599.
		"120,152": {"to": "ground"},
		"201,83": {"to": "ground"},  # The old monster camp's (807 amended: a pack in its place).
	}},
	{"level": "held", "decision": 807, "removed": {
		"19,90": {"to": "ground"},  # The Old Tower's shop counter, from when held was the town.
	}},
	{"level": "castle", "decision": 807, "removed": {
		"5,5": {"to": "ground"},
		"27,5": {"to": "ground"},
		"5,7": {"to": "ground"},
	}},
	# No chests in town (734 amended (7); Jeff, 11-05: "remove chests from
	# town"): the retired kit's three by Umbrage's market stall (807 amended
	# (5)). What they held goes to the temple of "town" (to_temple): nothing
	# is laid on the ground, nothing destroyed.
	{"level": "wilds", "decision": 734, "town": "wilds/store", "removed": {
		"205,208": {"to": "temple"},
		"206,208": {"to": "temple"},
		"206,207": {"to": "temple"},
	}},
]


## A building become a shell (decision 811: Umbrage's inn, its inside now
## the Last Light Mughouse's own levels), level -> {decision, rect: [x, y,
## w, h] its footprint}: what was saved inside it carried out once (shell).
const SHELLS: Dictionary = {
	"wilds": {"decision": 811, "rect": [170, 205, 10, 8]},
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
	for plan: Dictionary in REMOVED:
		var line := _remove(snapshot, done, level_of, plan)
		if not line.is_empty():
			lines.append(line)
	return lines


## One REMOVED entry carried out on [param snapshot] (move's arguments):
## its count-only line, or "" when it was done already.
static func _remove(snapshot: Dictionary, done: Dictionary, level_of: Callable, plan: Dictionary) -> String:
	var level := str(plan["level"])
	var key := done_key_of(level, int(plan["decision"]))
	if int(done.get(key, 0)) == int(plan["decision"]):
		return ""
	var loaded: Dictionary = level_of.call(level)
	for spec: Dictionary in loaded.get("entities", []):
		var tile: Variant = spec.get("tile")
		if tile is Vector2i and plan["removed"].has("%d,%d" % [tile.x, tile.y]):
			return "[level] %s's removals (%d) wait: it still has a marker at %s (an overlay copy?); nothing removed" % [level, plan["decision"], tile]
	done[key] = int(plan["decision"])
	if not snapshot.get("ok", false):
		return ""
	var counts := {"removed": 0, "holding": 0, "laid": 0, "kept": 0, "unknown": 0, "kit": 0, "held": 0, "nobody": 0, "owners": {}}
	var zones: Dictionary = snapshot.get("zones", {}) if snapshot.get("zones") is Dictionary else {}
	if zones.get(level) is Dictionary:
		var floor := {}
		for cell: Vector2i in loaded.get("terrain", {}).get("floor", []):
			floor[cell] = true
		var section: Dictionary = zones[level]
		var book: Dictionary = snapshot.get("items", {}).get("book", {}) if snapshot.get("items") is Dictionary and snapshot["items"].get("book") is Dictionary else {}
		var renames := {}
		var kept: Array = []
		for entry: Dictionary in section.get("entities", []):
			var spec: Dictionary = entry.get("spec", {})
			if not plan["removed"].has(str(spec.get("spawn_key", ""))):
				kept.append(entry)
				continue
			counts["removed"] += 1
			var cell: Variant = _cell(spec.get("tile"))
			if cell == null:
				cell = _cell_of_key(str(spec["spawn_key"]))
			var to := nearest_floor(cell, floor)
			if to == cell and not floor.has(cell):
				counts["kept"] += 1
			var holder := "%s/%s" % [level, spec.get("name", "")]
			var ids: Array = []
			var uids: Array = []
			var slots: Array = entry["slots"] if entry.get("slots") is Array else []
			var items: Array = entry.get("items", [])
			for i in slots.size():
				if str(slots[i]).is_empty():
					continue
				ids.append(str(slots[i]))
				uids.append(int(items[i]) if i < items.size() and (items[i] is float or items[i] is int) else 0)
			# Stacked units (619) and anything else the book has at it.
			for uid: Variant in book:
				var thing: Variant = book[uid]
				if thing is Dictionary and str(thing.get("at", "")) == holder and not int(str(uid)) in uids:
					ids.append(str(thing.get("id", "")))
					uids.append(int(str(uid)))
			if ids.is_empty():
				continue
			counts["holding"] += 1
			match str((plan["removed"][str(spec["spawn_key"])] as Dictionary).get("to", "ground")):
				"ground":
					pass
				"temple":
					if to_temple(snapshot, str(plan.get("town", "")), level, cell, ids, uids, counts):
						continue
					counts["unknown"] += 1  # No such town saved: on the ground, never dropped.
				_:
					counts["unknown"] += 1  # A "to" this build does not know: on the ground, never dropped.
			counts["laid"] += ids.size()
			renames[holder] = "%s@%d,%d" % [level, to.x, to.y]
			_lay(section, to, ids, uids)
		section["entities"] = kept
		section["respawns"] = (section.get("respawns", []) as Array).filter(func(respawn: Dictionary) -> bool:
				return not plan["removed"].has(str(respawn.get("spawn_key", ""))))
		_rename_places(snapshot, renames, {"places": 0})
	var line := "[level] removed in %s (%d): %d saved entities removed, %d holding things, %d things laid on the ground, %d left where they were (no floor near)" % [
		level, plan["decision"], counts["removed"], counts["holding"], counts["laid"], counts["kept"]]
	if plan.has("town"):
		# Counts only (the coordinator: no names, no ids, no uids).
		line = "[level] removed in %s (%d): %d saved entities removed, %d holding things, %d kit things to the shop, %d players' things held for %d owners at the temple, %d of no known owner to the shop, %d laid on the ground" % [
			level, plan["decision"], counts["removed"], counts["holding"], counts["kit"], counts["held"], (counts["owners"] as Dictionary).size(),
			counts["nobody"], counts["laid"]]
	if counts["unknown"] > 0:
		line += ", %d with an unknown destination laid on the ground" % counts["unknown"]
	return line


## Things [param ids] (their [param uids] beside them, 0 for one the item
## book has no instance of) out of a removed chest on [param cell] of
## [param zone], carried to [param town]'s temple (734 amended (7), the
## coordinator's rulings: nothing out of every player's reach): one only
## one player ever carried, held there for them (Towns held_for, decision
## 434), handed back free by the priest at his counter, marked RETURNED for
## his words; any other goes on the town's shop at the town's price (its
## stockpile "shop", Stockpile.shop_holder): a piece of the chest's own lay
## (minted "stocked" in it, never carried by anyone: _kit_own), and one of
## no known owner (carried by two or more players, whose book keeps no order
## of who held it last; by no player; or never in the book, given an
## instance). False, nothing moved, when [param snapshot] has no such town
## saved, or no store for it.
static func to_temple(snapshot: Dictionary, town: String, zone: String, cell: Vector2i, ids: Array, uids: Array, counts: Dictionary) -> bool:
	var towns: Variant = snapshot.get("towns")
	if town.is_empty() or not towns is Dictionary or not (towns as Dictionary).get(town) is Dictionary:
		return false
	var record: Dictionary = towns[town]
	if not record.get("held_for") is Dictionary:
		record["held_for"] = {}
	var held_for: Dictionary = record["held_for"]
	if not snapshot.get("items") is Dictionary:
		snapshot["items"] = {}
	var items: Dictionary = snapshot["items"]
	if not items.get("book") is Dictionary:
		items["book"] = {}
	var book: Dictionary = items["book"]
	var stores: Variant = snapshot.get("stockpile")
	var store: Variant = (stores as Dictionary).get(town) if stores is Dictionary else null
	if not store is Dictionary:
		return false
	if not (store as Dictionary).get("shop") is Array:
		store["shop"] = []
	var shelf: Array = store["shop"]
	for i in ids.size():
		var uid := int(uids[i]) if i < uids.size() else 0
		var thing: Variant = book.get(str(uid)) if uid > 0 else null
		var owner := ""
		var kit := false
		if thing is Dictionary:
			kit = _kit_own(thing, zone, cell)
			owner = "" if kit else _sole_player(thing)
		else:
			# No instance in the book: one made for it, so it can be sold.
			uid = maxi(int(items.get("next", 1)), 1)
			while book.has(str(uid)):
				uid += 1
			items["next"] = uid + 1
			thing = {"id": str(ids[i]), "made": 0, "at": "", "holder": "", "carriers": [],
				"events": [{"kind": "migrated", "step": 0, "zone": zone, "tile": [cell.x, cell.y], "what": "a chest's, unrecorded"}]}
			book[str(uid)] = thing
		if owner.is_empty():
			if not uid in shelf:
				shelf.append(uid)
			thing["at"] = Stockpile.shop_holder(town)
			counts["kit" if kit else "nobody"] += 1
			continue
		thing["at"] = "temple:" + town
		thing[ItemBook.RETURNED] = ItemBook.FROM_OLD_CHESTS
		if not held_for.get(owner) is Array:
			held_for[owner] = []
		held_for[owner].append(uid)
		counts["held"] += 1
		counts["owners"][owner] = true
	return true


## Whether book entry [param thing] is provably a piece of the chest's own
## lay on [param cell] of [param zone] (the coordinator: "its uid in the
## kit's own lay, never carried by a player"): minted "stocked" there, and
## carried by nobody since.
static func _kit_own(thing: Dictionary, zone: String, cell: Vector2i) -> bool:
	var events: Array = thing.get("events", []) if thing.get("events") is Array else []
	if not (thing.get("carriers", []) as Array).is_empty() or events.is_empty() or not events[0] is Dictionary:
		return false
	var first: Dictionary = events[0]
	var tile: Variant = first.get("tile")
	return str(first.get("kind", "")) == "stocked" and str(first.get("zone", "")) == zone and tile is Array \
		and (tile as Array).size() == 2 and int(tile[0]) == cell.x and int(tile[1]) == cell.y


## The one player who ever carried book entry [param thing] (a carrier key,
## "player:<id>"); "" for none, or more than one (to the shop: the book's
## carrier rows keep first-carry order and time held, and a take from a
## chest after the first carry leaves no event, so who held it last is
## never known).
static func _sole_player(thing: Dictionary) -> String:
	var players: Array[String] = []
	for row: Variant in thing.get("carriers", []):
		var who := str((row as Dictionary).get("who", "")) if row is Dictionary else ""
		if who.begins_with("player:") and not who in players:
			players.append(who)
	return players[0] if players.size() == 1 else ""


## Things [param ids] (their [param uids] beside them) laid on [param
## section]'s ground at [param cell], on a pile there if there is one.
static func _lay(section: Dictionary, cell: Vector2i, ids: Array, uids: Array) -> void:
	if not section.get("ground") is Array:
		section["ground"] = []
	for pile: Dictionary in section["ground"]:
		if _cell(pile.get("cell")) == cell:
			var pile_items: Array = pile.get("items", [])
			# Pad the pile's uids to its ids, so each new id has its uid beside it.
			while pile_items.size() < (pile["ids"] as Array).size():
				pile_items.append(0)
			pile["ids"].append_array(ids)
			pile_items.append_array(uids)
			pile["items"] = pile_items
			return
	section["ground"].append({"cell": cell, "ids": ids, "items": uids, "gold": 0})


## Carries [param snapshot] out of each SHELLS building not yet in
## [param done] (under done_key_of(level, decision)), and marks it done: a
## shell's inside is walked into by no one now (its way in is a link, and
## no body but a player stands on a link's cell), so the zone's saved
## entities and ground piles in its footprint go to the nearest floor
## outside it (a pile's item-book place following), and a player saved in
## it stands there too, their companion beside them. A level that loads
## with no shell there (an overlay copy) waits, said once a boot. Returns
## one count-only line per level, for release to grep:
## "[level] shelled <level> (<decision>): ...".
static func shell(snapshot: Dictionary, done: Dictionary, level_of: Callable) -> Array[String]:
	var lines: Array[String] = []
	for level: String in SHELLS:
		var plan: Dictionary = SHELLS[level]
		var key := done_key_of(level, int(plan["decision"]))
		if done.has(key):
			continue
		var rect := Rect2i(plan["rect"][0], plan["rect"][1], plan["rect"][2], plan["rect"][3])
		var loaded: Dictionary = level_of.call(level)
		var shelled := (loaded.get("buildings", []) as Array).any(func(building: Dictionary) -> bool:
			return building.get("rect") == rect and not str(building.get("inside", "")).is_empty())
		if not shelled:
			lines.append("[level] %s not shelled (%d): it loads with no shell at %s (an overlay copy?); nothing moved, it waits" % [level, plan["decision"], rect.position])
			continue
		done[key] = int(plan["decision"])
		if not snapshot.get("ok", false):
			continue
		var outside := {}
		for cell: Vector2i in loaded.get("terrain", {}).get("floor", []):
			if not rect.has_point(cell):
				outside[cell] = true
		var counts := {"entities": 0, "piles": 0, "players": 0, "kept": 0}
		var zones: Dictionary = snapshot.get("zones", {}) if snapshot.get("zones") is Dictionary else {}
		var section: Dictionary = zones.get(level, {}) if zones.get(level) is Dictionary else {}
		var out_of := func(cell: Vector2i, what: String) -> Vector2i:
			var to := nearest_floor(cell, outside)
			counts[what if to != cell else "kept"] += 1
			return to
		for entry: Dictionary in section.get("entities", []):
			var tile: Variant = _cell(entry["spec"].get("tile"))
			if tile is Vector2i and rect.has_point(tile):
				entry["spec"]["tile"] = out_of.call(tile, "entities")
		var piles := {}
		for pile: Dictionary in section.get("ground", []):
			var cell: Variant = _cell(pile.get("cell"))
			if cell is Vector2i and rect.has_point(cell):
				var to: Vector2i = out_of.call(cell, "piles")
				if to != cell:
					piles["%s@%d,%d" % [level, cell.x, cell.y]] = "%s@%d,%d" % [level, to.x, to.y]
					pile["cell"] = to
		_rename_places(snapshot, piles, {"places": 0})
		for record: PlayerRecord in snapshot.get("players", []):
			if record.zone == level and rect.has_point(record.tile):
				record.tile = out_of.call(record.tile, "players")
				if not record.companion.is_empty():
					record.companion["tile"] = null  # She comes back beside them.
		lines.append("[level] shelled %s (%d): %d saved entities, %d ground piles and %d players moved out of the shell at %s, %d left where they were (no floor near)" % [
			level, plan["decision"], counts["entities"], counts["piles"], counts["players"], rect.position, counts["kept"]])
	return lines


## The key a REMOVED entry or a SHELLS building is marked done under, in
## Main's saved "remade": its level and decision, so each is done apart
## from the others: "relaid/<level>/<decision>".
static func done_key_of(level: String, decision: int) -> String:
	return "relaid/%s/%d" % [level, decision]


static func _cell_of_key(key: String) -> Vector2i:
	return Vector2i(int(key.get_slice(",", 0)), int(key.get_slice(",", 1)))


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
## moves to: each place renamed to and each marker moved to is there, but
## for a marker a later REMOVED entry takes out of that level (734 amended
## (7): Snagfin's three, moved by its stall, then gone from town).
static func is_laid(level: Dictionary, plan: Dictionary) -> bool:
	var places: Dictionary = level.get("places", {})
	for to: String in plan["places"].values():
		if not places.has(to.get_slice("/", 1)):
			return false
	var marked := {}
	for spec: Dictionary in level.get("entities", []):
		marked[spec.get("tile")] = true
	var gone := {}
	for removal: Dictionary in REMOVED:
		if removal["level"] == str(level.get("name", "")):
			for key: String in removal["removed"]:
				gone[Vector2i(int(key.get_slice(",", 0)), int(key.get_slice(",", 1)))] = true
	for to: Array in plan["markers"].values():
		var at := Vector2i(to[0], to[1])
		if not marked.has(at) and not gone.has(at):
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
