extends Node
## Visitors come and go by a road (711 amended (3); maps' Mughouse landing, 11-15: Edda, a traveller going on,
## stood half an hour north of the temple's pews). Main._town_edge took the nearest way out of the area of any
## kind, and from Umbrage's store that was the crypt's stair in the temple: every visitor going on walked into
## the temple, and every one come was made there. Now only an open way to an outdoor level (Main.road_way).
## Umbrage, a player in the square: the way picked, a traveller come (made at it), and two going on from the
## square, one with a player walking beside her and one with the player left in the square; how and where each
## leaves the world, never standing.

const TOWN := "wilds/store"
const STAIR := Vector2i(199, 199)
const MINUTE := 37
## The most game minutes a body going on may stand on one cell.
const STAND_MOST := 3
## Ticks a going-on walk is read for at most (its time is VISITOR_WALK_OUT_SECONDS).
const WATCH_TICKS := 3000

var _main: Node
var _failed := 0
var _player: Player = null


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	World.set_process(false)
	var ports := preload("res://tests/test_ports.gd")
	Net.port = ports.of(17992)
	Net.companions = false
	Net.map_name = "wilds"
	Net.lawspeaker = "off"
	Net.state_path = ports.scratch_path("visitor_road_world.json")
	if FileAccess.file_exists(Net.state_path):
		DirAccess.remove_absolute(Net.state_path)
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	for entity in World.get_entities():
		if entity is Player and entity.spawned:
			_player = entity
	var place: Dictionary = World.holdings.place(TOWN)
	var store: Vector2i = place.get("cell", Vector2i.ZERO)
	var square_at := _main._nearest_free(store + Vector2i(0, 3)) as Vector2i
	World._relocate(_player, square_at)
	DayNight.set_hour(10.0)
	for s in Main.RESIDENT_SYNC_TICKS * 3:
		World.step()
	print("== visitors come and go by a road (711 amended (3)) ==")
	var edge: Vector2i = _main._town_edge(place)
	var ways: Array[Dictionary] = _main._world_map.ways_from("wilds")
	var picked: Array = ways.filter(func(way: Dictionary) -> bool: return str(way["kind"]) == "link" and way["at"] == edge)
	var stair: Array = ways.filter(func(way: Dictionary) -> bool: return way["at"] == STAIR)
	_check(not stair.is_empty() and not Main.road_way(stair[0]), "the crypt's stair %s is a way out of the wilds (to %s) and no road" % [
		STAIR, str(stair[0]["to"]) if not stair.is_empty() else "none"])
	_check(edge != STAIR and not picked.is_empty() and Main.road_way(picked[0]),
		"Umbrage's road out: the way at %s to %s, %d cells from the store %s, %d from the town's nearest building" % [
			edge, str(picked[0]["to"]) if not picked.is_empty() else "?", World.distance(edge, store), store, _from_buildings(edge)])
	var ground: Array = []
	for dy in range(-2, 3):
		var row := ""
		for dx in range(-2, 3):
			var c := edge + Vector2i(dx, dy)
			row += "L" if World.is_link_cell(c) else ("." if World.is_free(c) else ("w" if World.is_walkable(c) else "#"))
		ground.append(row)
	print("  the ground about the way (L link, . free, w walkable not free, # shut): %s" % " / ".join(ground))
	# One come: walks in from the road (Main's enter_at, the body made there).
	var draw := RandomNumberGenerator.new()
	draw.seed = 711
	World.towns._visitor_comes(TOWN, "traveller", draw)
	var come: Dictionary = (World.towns.visitors(TOWN) as Array).back()
	var come_key := Offers.VISITOR + str(come["id"])
	var wanted: Array = _main._visitors_wanted(_main._world_map.areas.get("wilds", {}), TOWN, place).filter(
		func(each: Dictionary) -> bool: return each["key"] == come_key)
	_check(not wanted.is_empty() and wanted[0].get("enter_at") == edge,
		"a visitor come walks in from the road: enter_at %s (the way %s)" % [wanted[0].get("enter_at") if not wanted.is_empty() else "none", edge])
	var made: Resident = null
	var made_at := Vector2i(-1, -1)
	for s in Main.RESIDENT_SYNC_TICKS * 3:
		World.step()
		if made == null:
			made = _main._resident_body(come_key)
			if made != null:
				made_at = made.tile
	_check(made != null and World.distance(made_at, edge) <= 2 and not _in_temple(made_at),
		"%s is made at the road (%s, the way %s), not in the temple" % [str(come["name"]), made_at, edge])
	# Two going on from the square: a player beside one, the player in the square for the other.
	await _going(come, true, square_at, edge)
	World.towns._visitor_comes(TOWN, "traveller", draw)
	var second: Dictionary = (World.towns.visitors(TOWN) as Array).back()
	for s in Main.RESIDENT_SYNC_TICKS * 3:
		World.step()
	World._relocate(_player, square_at)
	await _going(second, false, square_at, edge)
	print("RESULT: %s (%d failed)" % ["PASS" if _failed == 0 else "FAIL", _failed])
	Net.state_path = ""
	get_tree().quit(0 if _failed == 0 else 1)


## [param entry] goes on from the square: walked till its body is gone, the player beside it each game
## minute when [param beside], else left at [param square_at]. Where it was last, how long it stood at most.
func _going(entry: Dictionary, beside: bool, square_at: Vector2i, edge: Vector2i) -> void:
	var key := Offers.VISITOR + str(entry["id"])
	var body := _main._resident_body(key) as Resident
	if body == null:
		_check(false, "%s has a body in the square before going on" % entry["name"])
		return
	World._relocate(body, _main._nearest_free(square_at + Vector2i(2, 0)))
	(World.towns._town(TOWN)["visitors"] as Array).erase(entry)
	_main._on_visitor_left(TOWN, str(entry["id"]))
	var from := World.tick
	var last := body.tile
	var stood_since := World.tick
	var stood_most := 0
	var moved_at := World.tick
	var behind := body.tile
	while World.tick - from < WATCH_TICKS:
		World.step()
		if body == null or not is_instance_valid(body) or not body.spawned or _main._resident_body(key) == null:
			break
		if body.tile != last:
			stood_most = maxi(stood_most, (World.tick - stood_since) / MINUTE)
			behind = last
			last = body.tile
			stood_since = World.tick
			moved_at = World.tick
		if beside and (World.tick - from) % MINUTE == 0 and World.distance(_player.tile, body.tile) > 2:
			World._relocate(_player, _main._nearest_free(behind))
		if (World.tick - from) % 2250 == 0:
			await get_tree().process_frame
	stood_most = maxi(stood_most, (World.tick - stood_since) / MINUTE)
	var ticks := World.tick - from
	var at_way := World.distance(last, edge) <= 1
	var walking := World.tick - moved_at <= 2 * MINUTE
	print("  %s going on (%s): gone after %d ticks (%.1f game minutes; her time %d ticks) at %s, %d cells from the way %s, %d from the town's nearest building, %d from the player; %s; stood at most %d game minutes" % [
		entry["name"], "a player beside her" if beside else "the player in the square", ticks, float(ticks) / MINUTE,
		Main.VISITOR_WALK_OUT_SECONDS * World.TICK_RATE, last, World.distance(last, edge), edge, _from_buildings(last),
		World.distance(last, _player.tile), "at the way" if at_way else ("walking" if walking else "standing"), stood_most])
	_check(ticks < WATCH_TICKS, "%s is gone within %d ticks (%d)" % [entry["name"], WATCH_TICKS, ticks])
	_check(at_way or (walking and not _in_temple(last) and _from_buildings(last) > 0),
		"%s leaves the world at the way, or walking on the road out of town, never standing or in the temple (%s)" % [entry["name"], last])
	_check(stood_most <= STAND_MOST, "%s never stands over %d game minutes going on (%d)" % [entry["name"], STAND_MOST, stood_most])
	if beside:
		_check(at_way, "with a player beside her %s walks out at the way %s (last %s)" % [entry["name"], edge, last])


## Cells from [param cell] to the nearest building of the town (its rect), 0 inside one.
func _from_buildings(cell: Vector2i) -> int:
	var best := 1 << 20
	for building: Dictionary in _main._world_map.areas.get("wilds", {}).get("buildings", []):
		if str(building.get("town", "")) != "store":
			continue
		var rect: Rect2i = building["rect"]
		var near := Vector2i(clampi(cell.x, rect.position.x, rect.end.x - 1), clampi(cell.y, rect.position.y, rect.end.y - 1))
		best = mini(best, World.distance(cell, near))
	return best


func _in_temple(cell: Vector2i) -> bool:
	for building: Dictionary in _main._world_map.areas.get("wilds", {}).get("buildings", []):
		if str(building.get("use", "")) == "temple" and (building["rect"] as Rect2i).has_point(cell):
			return true
	return false


func _check(ok: bool, label: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + label)
	if not ok:
		_failed += 1
