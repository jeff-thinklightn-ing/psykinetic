extends Node
## A player's click route is bounded (decision 935): World.walk_path's
## max_tiles, World.CLICK_SEARCH_TILES from Main's click-born callers. A cell
## walkable but walled off (a body in a doorway: the healer standing on his
## hut's door cell, perf_folk4) gives up after the bound, not after the whole
## zone; and no route a click can ask for, in any zone the game loads, needs
## as much as half the bound, so the bound never cuts one that exists.
## Run it with tests/run.sh. Prints PASS/FAIL per assertion and quits with
## exit code 1 if any assertion failed, 0 otherwise.
##
## Two scenes (the row runs long): this one, the doorway and every zone but
## the three largest open lands; click_route_far_test (this script's
## subclass, a port of its own) the hills, foothills and forest (FAR_ZONES).

## A click's cell is at most this far off the player (Chebyshev): the view's
## widest reach from the camera's aim (World.NEAR_TILES, ZOOM_MAX's rule,
## decision 238) and the middle drag's slide of the aim (Client3D.PAN_MAX).
var CLICK_REACH := World.NEAR_TILES + int(Client3D.PAN_MAX)
## The healer's hut in the wilds: his door's cell, a cell outside it a click
## came from (perf_folk4's stall), and the cell past the door.
const HUT_DOOR := Vector2i(152, 232)
const OUTSIDE := Vector2i(149, 231)
const PAST := Vector2i(152, 233)
## The lattice the agree row reads: starts every START_STRIDE cells (with
## each level's starts and link cells), targets every TARGET_STRIDE within
## CLICK_REACH in a zone of WIDE_FLOOR floor cells or more (where every worst
## route lives: the hills, foothills, wilds, held, castle_halls' generations),
## every SMALL_STRIDE in a smaller one (its whole floor under the bound, so no
## route of it can be cut at all).
const START_STRIDE := 24
const TARGET_STRIDE := 3
const SMALL_STRIDE := 6
const WIDE_FLOOR := 2000
## The far scene's zones (click_route_far_test).
const FAR_ZONES: Array[String] = ["hills", "foothills", "forest"]

var _failures := 0
var _main: Node


func _ready() -> void:
	World.set_process(false)
	Net.port = _port()
	Net.companions = false
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	if not _far():
		_test_doorway()
		_test_go_in()
	await _test_click_routes_agree()
	print("\nRESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _port() -> int:
	return preload("res://tests/test_ports.gd").of(17867)


## Whether this is the far scene (FAR_ZONES alone).
func _far() -> bool:
	return false


## The healer in his doorway (perf_folk4: Hob on (152, 232) at night, every
## cell a hand reaches him from past his body): a click route to the cell
## past him from outside. Uncapped it closes the zone's reach (the wilds'
## 49,777 cells, about 230 ms here, 450 on a laptop); capped, at most the
## bound; through Main's click (_free_route) too. The body gone, the route
## is found, the same capped as not. The cells closed decide; the ms is
## printed, never checked.
func _test_doorway() -> void:
	print("\n== a body in a doorway: a click past it gives up at the bound, not the zone (935) ==")
	_check(_main.load_map("wilds"), "the wilds load")
	_check(World.is_walkable(HUT_DOOR) and World.is_walkable(PAST) and World.is_walkable(OUTSIDE),
		"the healer's door %s, the cell past it %s and outside %s are floor" % [HUT_DOOR, PAST, OUTSIDE])
	var player := _player()
	_check(player != null, "a player")
	if player == null:
		return
	var held: GridEntity = World.get_entity_at(OUTSIDE)
	if held != null and held != player:
		World.despawn(held)
	World._relocate(player, OUTSIDE)
	var was: GridEntity = World._occupancy.get(HUT_DOOR)
	var body: GridEntity = was
	if body == null:
		for entity: GridEntity in World.get_entities():
			if entity != player and entity.spawned and not entity is Player:
				body = entity
				break
	_check(body != null, "a body to stand in the doorway")
	if body == null:
		return
	World._occupancy[HUT_DOOR] = body
	var free := World.free_cell(player, Vector2(player.tile))
	var whole := _closed(func() -> Array[Vector2i]: return World.walk_path(free, PAST, player))
	var capped := _closed(func() -> Array[Vector2i]: return World.walk_path(free, PAST, player, World.PATH_FIRE_EXTRA, World.CLICK_SEARCH_TILES))
	print("  uncapped: %d cells, %d closed, %.1f ms; capped: %d cells, %d closed, %.1f ms" % [
		whole["path"].size(), whole["closed"], whole["ms"], capped["path"].size(), capped["closed"], capped["ms"]])
	_check(whole["path"].is_empty() and whole["closed"] > World.CLICK_SEARCH_TILES,
		"uncapped, no way past the body, after the zone's reach (%d cells closed)" % whole["closed"])
	_check(capped["path"].is_empty() and capped["closed"] <= World.CLICK_SEARCH_TILES,
		"capped, no way, after at most %d cells closed (%d)" % [World.CLICK_SEARCH_TILES, capped["closed"]])
	_main._free_taken_over(player)
	var clicked := _closed(func() -> Array[Vector2i]:
		_main._free_route(player, PAST)
		var out: Array[Vector2i] = []
		out.assign(_main._free.get("path", []))
		return out)
	_check(clicked["path"].is_empty() and clicked["closed"] <= World.CLICK_SEARCH_TILES,
		"Main's click route (_free_route) there: none, after at most %d cells closed (%d, %.1f ms)" % [World.CLICK_SEARCH_TILES, clicked["closed"], clicked["ms"]])
	if was == null:
		World._occupancy.erase(HUT_DOOR)
	else:
		World._occupancy[HUT_DOOR] = was
	var open := _closed(func() -> Array[Vector2i]: return World.walk_path(free, PAST, player, World.PATH_FIRE_EXTRA, World.CLICK_SEARCH_TILES))
	var open_whole := World.walk_path(free, PAST, player)
	_check(not open["path"].is_empty() and open["path"] == open_whole,
		"the doorway clear: the way through found capped, the same as uncapped (%s, %d closed)" % [open["path"], open["closed"]])
	_main._free["path"] = []


## 935 amended (4): a click on a way into a building with an inside (its front cells and its inside door cells) is a click to go in: the
## goal is the building's link behind the door. The wilds' Mughouse (I1): doors on the east side at y208 and y209, links (178,208) and
## (178,209). A hut with no inside and plain ground are the cell clicked.
func _test_go_in() -> void:
	print("
== a click on the way into a building with an inside goes in (935 amended (4)) ==")
	var player := _player()
	var wilds: Dictionary = _main.level
	var links: Array = []
	for link: Dictionary in wilds.get("links", []):
		if str(link.get("to_map", "")) == "umbrage_tavern":
			links.append(link["tile"])
	_check(links.has(Vector2i(178, 208)) and links.has(Vector2i(178, 209)), "the Mughouse's links to its inside: %s" % [links])
	for cell: Vector2i in [Vector2i(180, 208), Vector2i(180, 209), Vector2i(179, 208), Vector2i(179, 209)]:
		var goal: Vector2i = Main.go_in_goal(wilds, cell)
		_check(links.has(goal) and goal.y == cell.y, "a click on %s goes in: the goal is its link %s" % [cell, goal])
	_check(Main.go_in_goal(wilds, Vector2i(183, 208)) == Vector2i(183, 208) and Main.go_in_goal(wilds, Vector2i(152, 231)) == Vector2i(152, 231)
			and Main.go_in_goal(wilds, Vector2i(150, 233)) == Vector2i(150, 233), "the lane, the healer's hut's front cell and a cell inside it: as clicked (no inside, no link)")
	_check(Main.go_in_goal(wilds, Vector2i(152, 232)) == Vector2i(152, 232), "a walk-in hut's door cell stays plain ground")
	if player != null:
		World._relocate(player, Vector2i(185, 208))
		_main._free_taken_over(player)
		_main._plain_left(player, null, Vector2i(180, 208), false)
		var path: Array = _main._free.get("path", [])
		_check(not path.is_empty() and path.back() == Vector2i(178, 208) and path.has(Vector2i(179, 208)),
			"a click on the front cell (180,208) from the lane: the route goes through the door cell to the link %s (%d cells)" % [path.back() if not path.is_empty() else "none", path.size()])
		_main._free["path"] = []


## Every zone the game loads (Level.names(), and each regenerating level's
## generations 1-8), every route a click can ask for: from the level's
## starts, its link cells and a lattice of walkable cells, to every free
## walkable cell on a lattice within CLICK_REACH. Each route that exists
## closes at most half of CLICK_SEARCH_TILES (so the bound, which stops only
## at itself, never cuts one, with room for maps to change); past half, the
## row fails and names the route, and the bound is raised before a click is
## ever cut. The worst of each zone printed.
func _test_click_routes_agree() -> void:
	print("\n== every route a click can ask for, in every zone, closes under half the bound (935) ==")
	var half := World.CLICK_SEARCH_TILES / 2
	var zones: Array[Dictionary] = []
	for level_name: String in Level.names():
		if not Level.playable(level_name) or level_name in Level.DEV_LEVELS or (level_name in FAR_ZONES) != _far():
			continue
		if Regen.marked(level_name):
			for generation in range(1, 9):
				zones.append({"level": level_name, "generation": generation})
		else:
			zones.append({"level": level_name, "generation": 0})
	var routes := 0
	var over: Array[String] = []
	var worst := {"closed": -1}
	var started := Time.get_ticks_msec()
	for zone: Dictionary in zones:
		var level_name: String = zone["level"]
		if int(zone["generation"]) > 0:
			# A generation as the game lays it, registered in memory under a name
			# of its own (never the shared overlay).
			var made := Regen.generate(level_name, int(zone["generation"]))
			level_name = "click_%s_%d" % [zone["level"], int(zone["generation"])]
			Level.register(level_name, made["layout"], made["height"], made["config"])
		if not _main.load_map(level_name):
			over.append("%s did not load" % level_name)
			continue
		await get_tree().process_frame
		var floor := World.floor_cells()
		var row := _zone_worst(level_name, floor)
		routes += int(row["routes"])
		var named := "%s%s" % [zone["level"], (" generation %d" % int(zone["generation"])) if int(zone["generation"]) > 0 else ""]
		print("  %s: %d floor cells, %d routes from %d starts; worst %d closed (%s -> %s, %d cells, %.1f ms)%s" % [
			named, floor.size(), row["routes"], row["starts"], row["closed"], row["from"], row["to"], row["length"], row["ms"],
			"; its whole floor is under the bound" if floor.size() < World.CLICK_SEARCH_TILES else ""])
		if int(row["closed"]) > half:
			over.append("%s: %s -> %s closed %d" % [named, row["from"], row["to"], row["closed"]])
		if int(row["closed"]) > int(worst["closed"]):
			worst = row.duplicate()
			worst["zone"] = named
	_check(zones.size() >= (FAR_ZONES.size() if _far() else 5) and routes > 10000, "%d zones read, %d routes, in %.1f s" % [zones.size(), routes, (Time.get_ticks_msec() - started) / 1000.0])
	_check(over.is_empty(), "every route that exists closes at most %d (half the bound %d); the worst %d, %s %s -> %s (%s)" % [
		half, World.CLICK_SEARCH_TILES, worst.get("closed", -1), worst.get("zone", "-"), worst.get("from", "-"), worst.get("to", "-"), over])
	_main.load_map("test_room")


## One zone's worst route: the cells closed by the costliest route that
## exists from its starts to the lattice within CLICK_REACH (find_path
## uncapped: a capped search is the same search, stopped at the bound).
func _zone_worst(level_name: String, floor: Array[Vector2i]) -> Dictionary:
	var starts: Array[Vector2i] = []
	var level := Level.load_level(level_name)
	for start: Variant in level.get("starts", []):
		if start is Vector2i and World.is_walkable(start):
			starts.append(start)
	for link: Variant in level.get("terrain", {}).get("links_at", []):
		if link is Vector2i:
			for direction: Vector2i in World.DIRECTIONS:
				if World.is_walkable(link + direction) and World.is_free(link + direction):
					starts.append(link + direction)
					break
	for cell: Vector2i in floor:
		if posmod(cell.x, START_STRIDE) == 0 and posmod(cell.y, START_STRIDE) == 0 and World.is_free(cell):
			starts.append(cell)
	var out := {"routes": 0, "starts": starts.size(), "closed": 0, "from": "-", "to": "-", "length": 0, "ms": 0.0}
	var stride := TARGET_STRIDE if floor.size() >= WIDE_FLOOR else SMALL_STRIDE
	for start: Vector2i in starts:
		for dy in range(-CLICK_REACH, CLICK_REACH + 1, stride):
			for dx in range(-CLICK_REACH, CLICK_REACH + 1, stride):
				var goal := start + Vector2i(dx, dy)
				if goal == start or not World.is_walkable(goal) or not World.is_free(goal):
					continue
				var c0 := World.path_closed
				var t := Time.get_ticks_usec()
				var path := World.find_path(start, goal, true)
				if path.is_empty():
					continue
				out["routes"] += 1
				var closed := World.path_closed - c0
				if closed > int(out["closed"]):
					out["closed"] = closed
					out["from"] = start
					out["to"] = goal
					out["length"] = path.size()
					out["ms"] = (Time.get_ticks_usec() - t) / 1000.0
	return out


## What [param search] returns, the cells World's searches closed doing it
## (World.path_closed), and its ms.
func _closed(search: Callable) -> Dictionary:
	var c0 := World.path_closed
	var t := Time.get_ticks_usec()
	var path: Array[Vector2i] = search.call()
	return {"path": path, "closed": World.path_closed - c0, "ms": (Time.get_ticks_usec() - t) / 1000.0}


func _player() -> Player:
	for entity in World.get_entities():
		if entity is Player and entity.spawned:
			return entity
	return null


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  " + label)
	else:
		_failures += 1
		print("  FAIL  " + label)
