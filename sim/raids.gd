class_name Raids
extends RefCounted
## Raid groups in played zones as real monsters (decision 313). maps moves a
## raid group on the world tick (WorldRaids); when its route crosses into an
## area whose zone is awake, maps hands it over (enter) and leaves it alone
## till one of three signals hands it back:
##
## - raid_left(group_id, strength, area, cell, carries): the zone fell
##   asleep (or was reset) with raiders alive, or they walked to their goal
##   when it was not the town (an exit on the way), or home after the raid.
##   maps goes on from that cell with that strength and what it carries.
## - raid_done(group_id, report): the first raider reached the town's
##   stockpile ground; Towns.raid_arrives was called with the strength left
##   and this is its report (what it took is what the group now carries).
##   The raiders turn back the way they came; raid_left or raid_beaten
##   follows.
## - raid_beaten(group_id, area, cell): every raider dead or running; what
##   the group carried lies on the ground there (ItemBook, "raid:<id>").
##
## A group's strength is spread over raiders of its faction's kinds
## (Factions' "monsters", each with a "strength" in levels/monsters.json),
## drawn by the group's id, so its strength now is what its living raiders
## hold. Raiders fight whoever they notice like any monster, and go back to
## their march after; they kill players, but a companion (a resident is one
## too) they beat down is taken, not killed (World.spared, decision 314):
## World.entity_taken says so, and the group carries the captive off.

signal raid_done(group_id: String, report: Dictionary)
signal raid_left(group_id: String, strength: float, area: String, cell: Vector2i, carries: Dictionary)
signal raid_beaten(group_id: String, area: String, cell: Vector2i)

const NO_CELL := Vector2i(-99999, -99999)
## Waypoints of a march: one every so many steps of its way.
const WAYPOINT_EVERY := 6
## The one search for a group's way across the area, when it enters (tiles
## looked at); none found, it marches straight at its goal.
const ROUTE_SEARCH_TILES := 8000
## A raider this near its goal is there (with no town ground to say).
const ARRIVE_TILES := 2
## Raiders spawn on free cells this near where the group comes in.
const SPREAD_TILES := 4

## What a group reaching the town does (town, group) -> report: the town's
## raid_arrives; tests set their own.
var arrive: Callable = func(town: String, group: Dictionary) -> Dictionary:
	return World.towns.raid_arrives(town, group) if World.towns != null else {}
## Where town [param town]'s stockpile ground is in [param area] (town,
## area) -> cell, NO_CELL if not there; and whether a cell is on it (town,
## cell) -> bool: from Holdings; tests set their own.
var town_cell: Callable = func(town: String, area: String) -> Vector2i:
	var place: Dictionary = World.holdings.place(town) if World.holdings != null else {}
	return place["cell"] if str(place.get("area", "")) == area else NO_CELL
var on_town: Callable = func(town: String, cell: Vector2i) -> bool:
	return World.holdings != null and not World.holdings.place(town).is_empty() and World.holdings.covers(town, cell)

## group id -> {group, area, raiders: Array[Monster], goal, route, town_here,
## done, cell (where it stands), arrival, carries}.
var _groups: Dictionary[String, Dictionary] = {}
var _hooked := false


## The group ids in play, sorted.
func ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(_groups.keys())
	out.sort()
	return out


## Group [param id]'s raiders still on their feet.
func raiders(id: String) -> Array[Monster]:
	var out: Array[Monster] = []
	if not _groups.has(id):
		return out
	for each: Variant in _groups[id]["raiders"]:
		if is_instance_valid(each) and (each as Monster).spawned:
			out.append(each)
	return out


## Group [param id]'s strength now: what its living raiders hold.
func strength(id: String) -> float:
	var total := 0.0
	for each in raiders(id):
		total += each.raid_strength
	return total


## What group [param id] carries ({items: [uids], captives: [ids]}).
func carries(id: String) -> Dictionary:
	return _groups[id]["carries"] if _groups.has(id) else {}


## maps: [param group] ({id, faction, strength, from, town, carries}) comes
## into [param area] at [param arrival], making for [param goal] (a cell of
## that area: the exit it leaves by on its way, or by default the town's
## stockpile ground if the town is there). Its raiders spawn about the
## arrival and march; the number spawned.
func enter(group: Dictionary, area: String, arrival: Vector2i, goal := NO_CELL) -> int:
	if not Net.is_authority():
		return 0
	_hook()
	var id := str(group.get("id", ""))
	if id == "" or _groups.has(id):
		push_warning("[raids] %s: no id, or in play already" % id)
		return 0
	var town := str(group.get("town", ""))
	var town_here := false
	if goal == NO_CELL:
		goal = town_cell.call(town, area)
		town_here = goal != NO_CELL
	else:
		town_here = on_town.call(town, goal)
	if goal == NO_CELL:
		push_warning("[raids] %s: no goal in %s (town %s): it walks on" % [id, area, town])
		goal = arrival
	var was := World.zone
	World.enter_named(area)
	var route := _route(arrival, goal)
	var carried: Variant = group.get("carries", {})
	var record := {"group": group.duplicate(true), "area": area, "raiders": [], "goal": goal,
		"route": route, "town_here": town_here, "done": false, "cell": arrival, "arrival": arrival,
		"carries": _carries(carried if carried is Dictionary else {})}
	_groups[id] = record
	_spawn(record, arrival)
	World.enter(was)
	print("[raids] %s (%s, %.1f) comes into %s at %s, %d raiders, for %s" % [id, group.get("faction", ""),
		float(group.get("strength", 0.0)), area, arrival, record["raiders"].size(), "the town" if town_here else str(goal)])
	if record["raiders"].is_empty():
		_left(id)
	return record["raiders"].size()


## World.step, after the zones: each group's arrival, its way home, or its
## end.
func step() -> void:
	if _groups.is_empty():
		return
	for id in ids():
		if not _groups.has(id):
			continue
		var record: Dictionary = _groups[id]
		var standing := raiders(id).filter(func(each: Monster) -> bool: return each.alert != Monster.Alert.FLEEING)
		if standing.is_empty():
			_beaten(id)
			continue
		record["cell"] = standing[0].tile
		var there: Monster = null
		for each: Monster in standing:
			if _arrived(record, each):
				there = each
				break
		if there == null:
			continue
		if record["town_here"] and not record["done"]:
			_raid(id, there)
		else:
			record["cell"] = there.tile
			_left(id)


## Zone [param area] went to sleep or was reset: its groups go back to maps
## where they stand, with what they carry.
func hand_back(area: String) -> void:
	for id in ids():
		if _groups[id]["area"] == area:
			var standing := raiders(id)
			if not standing.is_empty():
				_groups[id]["cell"] = standing[0].tile
			_left(id)


## Every group dropped, no signals (a test's fresh start).
func clear() -> void:
	_groups.clear()


# --- Inside -------------------------------------------------------------------------

func _hook() -> void:
	if _hooked:
		return
	_hooked = true
	World.zone_slept.connect(func(each: Zone) -> void: hand_back(each.name))
	World.spared = _spared
	World.entity_taken.connect(_on_taken)


## World.spared: a raider's blow that would kill a companion takes it
## instead (decision 314): the group's id, else "".
func _spared(target: GridEntity, source: GridEntity, _cause: StringName) -> String:
	if target is Companion and source is Monster and (source as Monster).raid != "" \
			and _groups.has((source as Monster).raid):
		return (source as Monster).raid
	return ""


## A companion taken by group [param by]: it carries her off (her keeper's
## id, "companion:<id>", as Towns' captives name her origin).
func _on_taken(entity: GridEntity, by: String) -> void:
	if not _groups.has(by) or not entity is Companion:
		return
	var who := "companion:%s" % (entity as Companion).keeper_id
	if who not in _groups[by]["carries"]["captives"]:
		_groups[by]["carries"]["captives"].append(who)
	print("[raids] %s takes %s" % [by, entity.name])


static func _carries(given: Dictionary) -> Dictionary:
	var items: Array = given.get("items", [])
	var captives: Array = given.get("captives", [])
	return {"items": items.duplicate(), "captives": captives.duplicate()}


## The march's waypoints from [param from] to [param to]: one search, capped,
## every WAYPOINT_EVERY steps and the goal; just the goal if none is found.
func _route(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var path := World.find_path(from, to, true, null, ROUTE_SEARCH_TILES, true)
	for i in range(WAYPOINT_EVERY - 1, path.size() - 1, WAYPOINT_EVERY):
		out.append(path[i])
	out.append(to)
	return out


## Group [param record]'s raiders, its strength spread over its faction's
## kinds as drawn by its id, on free cells about [param at].
func _spawn(record: Dictionary, at: Vector2i) -> void:
	var group: Dictionary = record["group"]
	var id := str(group["id"])
	var kinds := _kinds_of(str(group.get("faction", "")))
	var total := maxf(float(group.get("strength", 0.0)), 0.0)
	if kinds.is_empty() or total <= 0.0 or not World.spawn_spec.is_valid():
		return
	var draw := RandomNumberGenerator.new()
	draw.seed = hash(id + "/raiders")
	var picked: Array[String] = []
	var left := total
	var cheapest := INF
	for kind in kinds:
		cheapest = minf(cheapest, _strength_of(kind))
	while left >= cheapest * 0.5 and picked.size() < 64:
		var can := kinds.filter(func(kind: String) -> bool: return _strength_of(kind) <= maxf(left, cheapest))
		var kind: String = can[draw.randi_range(0, can.size() - 1)]
		picked.append(kind)
		left -= _strength_of(kind)
	var spent := 0.0
	for kind in picked:
		spent += _strength_of(kind)
	var cells := _free_cells(at, picked.size())
	for i in mini(picked.size(), cells.size()):
		var kind := picked[i]
		var spec := Level._spec_for("monster_" + kind, Level.MONSTER_TYPES)
		spec["name"] = "Raider_%s_%d" % [id.validate_node_name(), i + 1]
		spec["tile"] = cells[i]
		spec["home"] = record["goal"]
		spec["idle"] = {"mode": "march", "route": record["route"].duplicate(), "loop": false}
		var made: Variant = World.spawn_spec.call(spec)
		if not made is Monster:
			continue
		var raider := made as Monster
		raider.raid = id
		raider.raid_strength = total * _strength_of(kind) / spent  # Shares that sum to the group's.
		record["raiders"].append(raider)


## The kinds faction [param faction] raids with: its monsters with a
## strength, sorted.
static func _kinds_of(faction: String) -> Array[String]:
	var factions: Factions = World.holdings.factions if World.holdings != null else Factions.read()
	var out: Array[String] = []
	if factions == null or not factions.all.has(faction):
		return out
	for kind: String in factions.all[faction].get("monsters", []):
		if Monster.kinds().has(kind) and _strength_of(kind) > 0.0:
			out.append(kind)
	out.sort()
	return out


static func _strength_of(kind: String) -> float:
	return float(Monster.kinds().get(kind, {}).get("strength", 0.0))


## Up to [param count] free walkable cells nearest [param at], within
## SPREAD_TILES.
static func _free_cells(at: Vector2i, count: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for ring in SPREAD_TILES + 1:
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var cell := at + Vector2i(dx, dy)
				if out.size() < count and World.is_walkable(cell) and World.is_free(cell) and not World.is_burning(cell):
					out.append(cell)
	return out


## Whether [param raider] has reached its group's goal: the town's ground,
## or near its goal.
func _arrived(record: Dictionary, raider: Monster) -> bool:
	if record["town_here"] and not record["done"] and on_town.call(str(record["group"].get("town", "")), raider.tile):
		return true
	return raider.marched(ARRIVE_TILES)


## The town is reached: Towns.raid_arrives with the strength left; what it
## took the group carries; they turn back the way they came.
func _raid(id: String, there: Monster) -> void:
	var record: Dictionary = _groups[id]
	var group: Dictionary = record["group"].duplicate()
	group["strength"] = strength(id)
	var report: Dictionary = arrive.call(str(group.get("town", "")), group)
	record["done"] = true
	var took: Dictionary = report.get("took", {})
	record["carries"]["items"].append_array(took.get("items", []))
	for each: Variant in report.get("captives", []):
		record["carries"]["captives"].append(str(each.get("id", "")) if each is Dictionary else str(each))
	print("[raids] %s reaches %s at %s (%.1f): %s" % [id, group.get("town", ""), there.tile, group["strength"],
		"fought off" if report.get("repelled", false) else "took %s" % [took]])
	raid_done.emit(id, report)
	# Home the way they came: the route back to where they came in.
	var back: Array[Vector2i] = []
	back.assign(record["route"].duplicate())
	back.reverse()
	back.pop_front()
	back.append(record["arrival"])
	record["route"] = back
	record["town_here"] = false
	for each in raiders(id):
		each.route = back.duplicate()
		each._route_index = 0
		each.home = back.back()


## Group [param id] goes back to maps: its raiders off the map, raid_left.
func _left(id: String) -> void:
	var record: Dictionary = _groups[id]
	var total := strength(id)
	_despawn(record)
	_groups.erase(id)
	print("[raids] %s leaves %s at %s (%.1f)" % [id, record["area"], record["cell"], total])
	raid_left.emit(id, total, record["area"], record["cell"], record["carries"])


## Group [param id] is beaten: those still running scatter (off the map),
## what it carried lies where it fell, the companions it took are free
## (World.companion_freed), raid_beaten.
func _beaten(id: String) -> void:
	var record: Dictionary = _groups[id]
	var at: Vector2i = record["cell"]
	var was := World.zone
	World.enter_named(record["area"])
	_despawn(record)
	for uid: Variant in record["carries"]["items"]:
		World.put_on_ground(int(uid), at)
	# The companions it carried are free, back beside their players.
	for who: Variant in record["carries"]["captives"]:
		if str(who).begins_with("companion:") and World.companion_freed.is_valid():
			World.companion_freed.call(str(who).trim_prefix("companion:"), "")
	World.enter(was)
	_groups.erase(id)
	print("[raids] %s is beaten in %s at %s" % [id, record["area"], at])
	raid_beaten.emit(id, record["area"], at)


func _despawn(record: Dictionary) -> void:
	var was := World.zone
	World.enter_named(record["area"])
	for each: Variant in record["raiders"]:
		if is_instance_valid(each) and (each as Monster).spawned:
			World.despawn(each)
	World.enter(was)
