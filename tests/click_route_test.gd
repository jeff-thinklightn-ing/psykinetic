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
		_test_hut_sight()
		_test_go_in()
		_test_footprint_click()
		_test_door_talk()
		_test_stand_cell_routes()
		_test_no_route()
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
	# 935 amended (ui's side): no way past the body, so the click walks to the cell that comes nearest it (find_path's nearest: the
	# same one search, the same cells closed), never through the body, and stops there.
	var nearest := _closed(func() -> Array[Vector2i]: return World.walk_path(free, PAST, player, World.PATH_FIRE_EXTRA, World.CLICK_SEARCH_TILES, true))
	_check(not clicked["path"].is_empty() and clicked["path"].back() != PAST and not clicked["path"].has(HUT_DOOR) and clicked["path"] == nearest["path"]
			and clicked["closed"] <= World.CLICK_SEARCH_TILES and nearest["closed"] == capped["closed"],
		"Main's click route (_free_route) there: to the cell nearest it, %s, not through the body, on the one search (%d closed, as capped %d; %.1f ms)" % [
			clicked["path"].back() if not clicked["path"].is_empty() else "none", clicked["closed"], capped["closed"], clicked["ms"]])
	# The same click held past the hold (ui-design's first click: a long frame between its press and release), the body still in the door:
	# the steering must keep the walk to the door's step. Printed first, then checked.
	var own = _main._free_own(player)
	if own != null:
		var controls_was: String = Net.controls
		Net.controls = "mouse"
		_main._free_route(player, PAST)
		var planned: Array = (_main._free.get("path", []) as Array).duplicate()
		_main._free["held"] = true
		_main._free["at"] = Time.get_ticks_msec() - 1000
		_main._free.erase("goal")
		_main._free.erase("no_route")
		_main._test_holding = true
		_main._pick_grid = Vector2(PAST)
		var line_clear := World._line_clear(World.free_cell(player, own.shown(player)), PAST, PAST, player)
		var way: Vector2 = _main._free_intent(player, own)
		var kept: Array = _main._free.get("path", [])
		print("  (door: line clear %s, click planned %d cells, after the held steering %d cells, way %s)" % [line_clear, planned.size(), kept.size(), way])
		_check(not planned.is_empty() and not kept.is_empty(),
			"the click past a body in the door, held past the hold: the walk to the door's step is kept (%d cells planned, %d after)" % [planned.size(), kept.size()])
		_main._test_holding = false
		_main._free["held"] = false
		Net.controls = controls_was
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
	# 935 amended (5): anywhere on the footprint (170..179, 205..212) goes in by the nearest link; a cell just outside it does not.
	for cell: Vector2i in [Vector2i(170, 205), Vector2i(174, 208), Vector2i(179, 212), Vector2i(176, 211), Vector2i(171, 206)]:
		var goal_in: Vector2i = Main.go_in_goal(wilds, cell)
		_check(links.has(goal_in), "a click on %s, inside the inn's footprint, goes in: the goal is %s" % [cell, goal_in])
	for cell: Vector2i in [Vector2i(169, 205), Vector2i(175, 204), Vector2i(174, 204), Vector2i(175, 213), Vector2i(180, 206)]:
		_check(Main.go_in_goal(wilds, cell) == cell, "a click on %s, outside the footprint and not a door cell, is as clicked" % cell)
	# A building whose way in is shut: the click stays as it is (a closed link is no way in).
	var shut_level: Dictionary = wilds.duplicate(true)
	for link: Dictionary in shut_level["links"]:
		if str(link.get("to_map", "")) == "umbrage_tavern":
			link["closed"] = true
	_check(Main.go_in_goal(shut_level, Vector2i(174, 208)) == Vector2i(174, 208) and Main.go_in_goal(shut_level, Vector2i(180, 208)) == Vector2i(180, 208),
		"the inn's way in shut (a closed link): a click on its footprint or its front cell stays as clicked")
	if player != null:
		World._relocate(player, Vector2i(185, 208))
		_main._free_taken_over(player)
		_main._plain_left(player, null, Vector2i(180, 208), false)
		var path: Array = _main._free.get("path", [])
		_check(not path.is_empty() and path.back() == Vector2i(178, 208) and path.has(Vector2i(179, 208)),
			"a click on the front cell (180,208) from the lane: the route goes through the door cell to the link %s (%d cells)" % [path.back() if not path.is_empty() else "none", path.size()])
		_main._free["path"] = []


## 935 amended (6): ui-design's gate run on main 87b2f6017 (the Mughouse's shell solid, 811 amended (8)): 0 of 22 clicks on the footprint off
## the door went in. The click was taken to the ground beside the building (_snap_to_floor: (174,206) to (174,204)) or to nothing (no floor
## within SNAP_RANGE of (173,210)) before go_in_goal read it. These are main's own cells, the five targets of the run, on the shell as the
## level lays it (solid here, asserted): the click's cell is the way in, from the snap's own failure to the route's end at a link.
func _test_footprint_click() -> void:
	print("\n== a click on the Mughouse's solid footprint goes in (935 amended (6)) ==")
	var player := _player()
	var wilds: Dictionary = _main.level
	var links: Array[Vector2i] = []
	for link: Dictionary in wilds.get("links", []):
		if str(link.get("to_map", "")) == "umbrage_tavern":
			links.append(link["tile"])
	# Roof, wall and the shell's inside: the five targets of the run (the roof's picture and wall faces are footprint cells too).
	var targets: Array[Vector2i] = [Vector2i(174, 206), Vector2i(175, 205), Vector2i(179, 206), Vector2i(179, 211), Vector2i(173, 210),
			Vector2i(172, 207), Vector2i(173, 208), Vector2i(174, 208)]
	var solid := 0
	var snapped_off := 0
	for cell: Vector2i in targets:
		if not World.is_walkable(cell):
			solid += 1
		var old_way: Vector2i = _main._snap_to_floor(Vector2(cell))
		if old_way == Main.NONE or not Level.building_rect(_building_at(wilds, cell)).has_point(old_way):
			snapped_off += 1
	_check(solid == targets.size(), "the shell is solid at the targets as the level lays it (%d of %d not walkable): the row stands on what the run did" % [solid, targets.size()])
	_check(snapped_off >= 1, "the snap alone takes %d of the %d targets off the footprint or to nothing: the fault the run found" % [snapped_off, targets.size()])
	for cell: Vector2i in targets:
		var goal: Vector2i = _main._click_ground_cell(Vector2(cell))
		_check(links.has(goal), "a click on %s, solid footprint, means the way in: %s (a link of %s)" % [cell, goal, links])
		if player != null:
			World._relocate(player, Vector2i(185, 208))
			_main._free_taken_over(player)
			_main._plain_left(player, null, goal, false)
			var path: Array = _main._free.get("path", [])
			_check(not path.is_empty() and links.has(path.back()), "and the walk from the lane to it ends on a link: %s (%d cells)" % [path.back() if not path.is_empty() else "none", path.size()])
			_main._free["path"] = []
	# The same click with a bow in hand (never an attack: a move click, as without the bow): _click_with_bow takes the cell as the plain click does.
	if player != null:
		var controls_was: String = Net.controls
		Net.controls = "click"
		for cell: Vector2i in [Vector2i(174, 206), Vector2i(173, 210), Vector2i(179, 206)]:
			World._relocate(player, Vector2i(185, 208))
			_main._free_taken_over(player)
			_main._pick_grid = Vector2(cell)
			_main._click_with_bow(player)
			var bow_path: Array = _main._free.get("path", [])
			_check(not bow_path.is_empty() and links.has(bow_path.back()), "a left click on %s with a bow in hand walks to a link as without it: %s" % [cell, bow_path.back() if not bow_path.is_empty() else "none"])
			_main._free["path"] = []
		Net.controls = controls_was
	# Ground outside the footprint is the snap as before; the way in shut is the snap too.
	_check(_main._click_ground_cell(Vector2(185.2, 208.1)) == Vector2i(185, 208), "a click on the open lane is the cell clicked, as before")
	var shut_level: Dictionary = wilds.duplicate(true)
	for link: Dictionary in shut_level["links"]:
		if str(link.get("to_map", "")) == "umbrage_tavern":
			link["closed"] = true
	var kept: Dictionary = _main.level
	_main.level = shut_level
	var shut_goal: Vector2i = _main._click_ground_cell(Vector2(174, 206))
	_main.level = kept
	_check(shut_goal != Vector2i(174, 206) and not links.has(shut_goal), "the inn's way in shut: a click on its roof is the snap's cell %s, as before" % shut_goal)


## The building of [param from_level] whose footprint holds [param cell] (an empty one: none).
func _building_at(from_level: Dictionary, cell: Vector2i) -> Dictionary:
	for building: Dictionary in from_level.get("buildings", []):
		if Level.building_rect(building).has_point(cell):
			return building
	return {}


## 935 amended (3): a click on one at work in the one cell inside his shut door (the healer by day, the wilds' (152, 233)): the cells
## beside him are walled in by his own body, so the stand cell has no route and the click did nothing; now the walk is at his own cell
## (a route to an occupied goal exists, a free body opens a door by walking at it). With a stand cell that has a route: unchanged.
func _test_door_talk() -> void:
	print("
== a click on one behind a shut door walks at him; with a way to the stand cell, as before (935 amended (3)) ==")
	var player := _player()
	var body: GridEntity = null
	for entity: GridEntity in World.get_entities():
		if entity != player and entity.spawned and not entity is Player:
			body = entity
			break
	if player == null or body == null:
		_check(false, "a player and a body")
		return
	var street := Vector2i(152, 230)
	var inside := Vector2i(152, 233)
	World._relocate(body, inside)
	World._relocate(player, street)
	_main._free_taken_over(player)
	var stand: Vector2i = _main._stand_to_talk(body, street)
	var routed := not World.walk_path(World.free_cell(player, Vector2(player.tile)), stand, player, World.PATH_FIRE_EXTRA, World.CLICK_SEARCH_TILES).is_empty()
	_check(stand != Main.NONE and not routed, "the stand cell beside him inside the hut, %s, has no route (his body shuts the entry)" % stand)
	var closed0 := World.path_closed
	_main._talk_to(player, body)
	var closed_by := World.path_closed - closed0
	var path: Array = _main._free.get("path", [])
	_check(_main._talk_wanted == body and not path.is_empty() and path.back() == inside,
		"the click walks at his own cell %s (%d cells), and the talk is wanted on arrival" % [inside, path.size()])
	_check(closed_by <= Main.TALK_STAND_SEARCH_TILES + 300,
		"the stand cell's search ended at its own bound %d, not the zone's %d (the click closed %d cells in all)" % [Main.TALK_STAND_SEARCH_TILES, World.CLICK_SEARCH_TILES, closed_by])
	# The walk does not open a shut door; the step does (E's "door" command). Every walked talk: two cells off it waits, at the door's step
	# the door is opened, then the talk is let through; with him at the entry (the walk at his cell) and off it (a stand cell inside).
	for him: Vector2i in [inside, Vector2i(150, 233)]:
		World._relocate(body, him)
		var shut: Door = _main._shut_door_in_the_way(street + Vector2i(0, 1), him)
		_check(shut != null and not shut.is_open(), "him at %s: a shut door is in the way from the cell two off %s" % [him, street + Vector2i(0, 1)])
		_main._talk_wanted = body
		_main._talk_until = Time.get_ticks_msec() + 20000
		_main._talk_door_sent = 0
		_main._talk_door_tries = 0
		World._relocate(player, street + Vector2i(0, 1))
		_main._update_talk()
		_check(_main._talk_wanted == body and shut != null and not shut.is_open(), "two cells off, the door shut, the talk waits (not opened, the door not yet touched)")
		World._relocate(player, street + Vector2i(0, 2))
		player.next_move_tick = 0
		_main._talk_door_since = 0
		_main._update_talk()
		_check(shut != null and not shut.is_open(), "at the door's step the walk is given its moment to open the door itself: not yet touched")
		_main._talk_door_since = Time.get_ticks_msec() - Main.TALK_DOOR_WAIT_MSEC - 50
		_main._update_talk()
		_check(shut != null and shut.is_open(), "still shut after its moment (the route ended there): E's own command opens it")
		_main._update_talk()
		_check(_main._talk_wanted == null, "and the talk is let through once it is open")
		if shut != null:
			shut.open = false  # Shut again, as it was laid.
	# A door that will not open (locked, no key): tried three times, the want dropped, the door still shut, nothing more sent.
	World._relocate(body, inside)
	var locked: Door = _main._shut_door_in_the_way(street + Vector2i(0, 2), inside)
	if locked != null:
		locked.lock = "test_key"
		_main._talk_wanted = body
		_main._talk_until = Time.get_ticks_msec() + 20000
		_main._talk_door_tries = 0
		_main._talk_door_since = 0
		World._relocate(player, street + Vector2i(0, 2))
		_main._update_talk()
		_check(_main._talk_wanted == null and not locked.open and _main._talk_door_tries == 0,
			"a locked door he has no key for: the want dropped at once, the door still shut, nothing sent")
		locked.lock = ""
	# A walk of his own (a click elsewhere) drops the want.
	_main._talk_wanted = body
	_main._move_click(player, street)
	_check(_main._talk_wanted == null, "a click elsewhere drops the wanted talk")
	_main._talk_wanted = null
	_main._free["path"] = []
	# In the open, with a way to the stand cell: as before.
	var open_cell := Vector2i(-1, -1)
	for dx in range(-8, -3):
		for dy in range(-2, 3):
			var cell := street + Vector2i(dx, dy)
			if open_cell == Vector2i(-1, -1) and World.is_walkable(cell) and World.get_entity_at(cell) == null:
				open_cell = cell
	if open_cell == Vector2i(-1, -1):
		print("  (no open cell near the street: the unchanged row skipped)")
	else:
		World._relocate(body, open_cell)
		var stand_open: Vector2i = _main._stand_to_talk(body, street)
		_main._talk_to(player, body)
		var way: Array = _main._free.get("path", [])
		_check(stand_open != Main.NONE and not way.is_empty() and way.back() == stand_open and way.back() != open_cell,
			"in the open: the walk is to the stand cell %s beside him, as before (%s)" % [stand_open, way.back() if not way.is_empty() else "none"])
	# A stand cell whose real route needs more than its bound (a small one here): the search is cut, and the click still walks at him and
	# arrives: the bound only bounds the cost, never a click that does nothing.
	if open_cell != Vector2i(-1, -1):
		World._relocate(body, open_cell)
		World._relocate(player, street)
		_main._free_taken_over(player)
		var stand_far: Vector2i = _main._stand_to_talk(body, street)
		var whole := World.walk_path(World.free_cell(player, Vector2(player.tile)), stand_far, player, World.PATH_FIRE_EXTRA, World.CLICK_SEARCH_TILES)
		var cut_closed0 := World.path_closed
		var cut := World.walk_path(World.free_cell(player, Vector2(player.tile)), stand_far, player, World.PATH_FIRE_EXTRA, 3)
		var needs := World.path_closed - cut_closed0
		_main.talk_stand_search_tiles = 3
		_main._talk_to(player, body)
		_main.talk_stand_search_tiles = Main.TALK_STAND_SEARCH_TILES
		var walk_at: Array = _main._free.get("path", [])
		_check(not whole.is_empty() and cut.is_empty() and not walk_at.is_empty() and walk_at.back() == open_cell,
			"a stand cell %s whose real route (%d cells) needs more than its bound (3): cut, and the click walks at him and arrives at %s" % [
				stand_far, whole.size(), walk_at.back() if not walk_at.is_empty() else "none"])
	_main._talk_wanted = null
	_main._free["path"] = []


## 935 amended (3): how many cells a real stand-cell route ever closes, for a cap on the stand cell's own search (perf's and ui's design).
## A talker at every fifth cell of Umbrage's room, a player starting from the eight ways at 4 and at 10 cells off: the stand cell
## Main._stand_to_talk gives, the route the click plans to it (World.walk_path as _free_route plans it), the cells closed; the worst is
## printed with its talker's cell and the start, and any stand cell with no route is counted (the healer in his entry is one).
func _test_stand_cell_routes() -> void:
	print("
== the cells a stand cell's route closes, Umbrage's lattice (935 amended (3)) ==")
	var player := _player()
	var body: GridEntity = null
	for entity: GridEntity in World.get_entities():
		if entity != player and entity.spawned and not entity is Player:
			body = entity
			break
	var room := Rect2i(140, 185, 96, 56)  # Umbrage's room (165, 185, 71, 56) and the west of it to Hob's hut (152, 233).
	if player == null or body == null:
		_check(false, "a player and a body")
		return
	var routes := 0
	var none := 0
	var worst := {"closed": -1, "talker": Vector2i.ZERO, "start": Vector2i.ZERO, "stand": Vector2i.ZERO, "length": 0}
	var over_cap := 0
	for y in range(room.position.y, room.end.y, 5):
		for x in range(room.position.x, room.end.x, 5):
			var talker := Vector2i(x, y)
			if not World.is_walkable(talker) or World.get_entity_at(talker) != null:
				continue
			World._relocate(body, talker)
			for way: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
				for reach in [4, 10, 20, 32]:
					var start: Vector2i = talker + way * reach
					if not World.is_walkable(start) or World.get_entity_at(start) != null or World.distance(start, talker) <= Main.TALK_REACH:
						continue
					var stand: Vector2i = _main._stand_to_talk(body, start)
					if stand == Main.NONE or stand == start:
						continue
					var c0 := World.path_closed
					var path := World.walk_path(start, stand, player, World.PATH_FIRE_EXTRA, World.CLICK_SEARCH_TILES)
					var closed := World.path_closed - c0
					if path.is_empty():
						none += 1
						continue
					routes += 1
					if closed > Main.TALK_STAND_SEARCH_TILES:
						over_cap += 1
					if closed > int(worst["closed"]):
						worst = {"closed": closed, "talker": talker, "start": start, "stand": stand, "length": path.size()}
	print("  %d stand-cell routes read, %d with no route; the worst closes %d cells (talker %s, from %s, stand cell %s, %d cells long); bound %d" % [
		routes, none, worst["closed"], worst["talker"], worst["start"], worst["stand"], worst["length"], World.CLICK_SEARCH_TILES])
	_check(routes > 100 and int(worst["closed"]) <= World.CLICK_SEARCH_TILES,
		"every stand-cell route that exists closes at most the zone's bound (%d of %d); over the stand bound %d: %d (each falls back to the walk at him)" % [
			worst["closed"], World.CLICK_SEARCH_TILES, Main.TALK_STAND_SEARCH_TILES, over_cap])
	World._relocate(body, Vector2i(152, 233))
	World._relocate(player, Vector2i(149, 231))


## 935 amended (ui's side): a click with no route walks to the cell that comes nearest it and stops, a chase of a target that cannot
## be reached likewise, and replans as it moves. A walkable cell with the eight round it blocked by chests is a pocket no route enters.
func _test_no_route() -> void:
	print("\n== a click with no route walks to the nearest cell and stops (935 amended, ui's side) ==")
	var player := _player()
	if player == null:
		_check(false, "a player")
		return
	var held: GridEntity = World.get_entity_at(OUTSIDE)
	if held != null and held != player:
		World.despawn(held)
	World._relocate(player, OUTSIDE)
	var rings: Array[Dictionary] = []
	var blocks: Array[Chest] = []
	for dx in range(-12, -5):
		for dy in range(-3, 4):
			var centre := OUTSIDE + Vector2i(dx, dy)
			var clear := true
			for ax in range(-1, 2):
				for ay in range(-1, 2):
					var cell := centre + Vector2i(ax, ay)
					if not World.is_walkable(cell) or World.get_entity_at(cell) != null:
						clear = false
			if clear and rings.size() < 2 and (rings.is_empty() or World.distance(rings[0]["centre"], centre) > 4):
				var made: Array[Chest] = []
				for ax in range(-1, 2):
					for ay in range(-1, 2):
						if ax != 0 or ay != 0:
							var chest := _main._spawn({"script": "res://sim/chest.gd", "name": "Ring%d_%d_%d" % [rings.size(), ax, ay], "tile": centre + Vector2i(ax, ay)}) as Chest
							if chest != null:
								made.append(chest)
				blocks.append_array(made)
				rings.append({"centre": centre})
	if rings.size() < 2:
		print("  (no two free pockets near the doorway: skipped)")
		for chest: Chest in blocks:
			World.despawn(chest)
		return
	var pocket: Vector2i = rings[0]["centre"]
	var free := World.free_cell(player, Vector2(player.tile))
	_check(World.walk_path(free, pocket, player, World.PATH_FIRE_EXTRA, World.CLICK_SEARCH_TILES).is_empty(), "the pocket %s has no route in" % pocket)
	_main._free_taken_over(player)
	_main._free_route(player, pocket)
	var path: Array = _main._free.get("path", [])
	_check(not path.is_empty() and not path.has(pocket) and World.distance(path.back(), pocket) <= 2 and World.distance(path.back(), pocket) < World.distance(free, pocket),
		"a click on it walks nearer and stops at %s, two cells off, never in (%d cells)" % [path.back() if not path.is_empty() else "none", path.size()])
	# A click held past FREE_HOLD_SECONDS (ui-design's first click: a 930 ms frame between its press and its release) steers to the cursor
	# by the same plan: the walk the click planned to the cell nearest the pocket is kept, never emptied by a plan with no nearest.
	var own = _main._free_own(player)
	if own != null:
		var controls_was: String = Net.controls
		Net.controls = "mouse"
		_main._free_route(player, pocket)
		_main._free["held"] = true
		_main._free["at"] = Time.get_ticks_msec() - 1000
		_main._free.erase("goal")
		_main._free["click"] = Vector2i(-99999, -99999)  # The cursor has left the clicked cell: a steer.
		_main._test_holding = true
		_main._pick_grid = Vector2(pocket)
		_main._free_intent(player, own)
		var steered: Array = _main._free.get("path", [])
		_check(not steered.is_empty() and not steered.has(pocket) and World.distance(steered.back(), pocket) <= 2,
			"a click held past the hold (a long first frame): the steering plans to the cell nearest the cursor, the walk kept (%d cells, ends %s)" % [
				steered.size(), steered.back() if not steered.is_empty() else "none"])
		# The held replan from the cell that comes nearest finds no way on: it searches once, then not again within the memory.
		World._relocate(player, steered.back())
		_main._free.erase("goal")
		_main._free.erase("no_route")
		_main._free["planned"] = 0
		_main._free["click"] = Vector2i(-99999, -99999)
		var c0 := World.path_closed
		_main._free_intent(player, own)
		var first_closed := World.path_closed - c0
		_main._free["planned"] = 0
		var c1 := World.path_closed
		_main._free_intent(player, own)
		var again_closed := World.path_closed - c1
		_check(first_closed > 0 and again_closed == 0,
			"held over a pocket from the nearest cell: the first replan searches (%d closed), the next within the memory does not (%d closed)" % [first_closed, again_closed])
		# A button still down over the very cell clicked is still the click (a long frame or search between press and release): in the
		# open the click's route is kept, never cleared into a straight steer; a cursor moved off the cell is a steer, as ever.
		World._relocate(player, free)
		var open_to := Vector2i(-1, -1)
		for reach in [7, 6, 5, 8]:
			for way: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var cell: Vector2i = free + way * reach
				if open_to == Vector2i(-1, -1) and World.is_walkable(cell) and World.get_entity_at(cell) == null and World._line_clear(free, cell, cell, player):
					open_to = cell
		if open_to != Vector2i(-1, -1):
			_main._free_route(player, open_to)
			var planned_open: int = (_main._free.get("path", []) as Array).size()
			_main._free["held"] = true
			_main._free["at"] = Time.get_ticks_msec() - 1000
			_main._test_holding = true
			_main._pick_grid = Vector2(open_to)
			_main._free_intent(player, own)
			var kept_open: int = (_main._free.get("path", []) as Array).size()
			_check(planned_open > 0 and kept_open > 0, "held over the cell clicked: the click's route is kept (%d cells planned, %d after)" % [planned_open, kept_open])
			_main._free["at"] = Time.get_ticks_msec() - 1000
			_main._pick_grid = Vector2(open_to) + Vector2(3, 0)
			_main._free_intent(player, own)
			_check((_main._free.get("path", []) as Array).is_empty(), "the cursor moved off the clicked cell: the hold steers, the route cleared (straight at the cursor)")
		else:
			print("  (no open cell to try the held click on: skipped)")
		# A click whose search is slow (the pocket's: the zone's bound searched dry): its time is taken when its route is ready, so the
		# search is no hold; released 100 ms on it walks; held on over the same cell it still walks and does not steer.
		World._relocate(player, free)
		_main._test_holding = false
		_main._free["held"] = false
		var t_before := Time.get_ticks_msec()
		_main._free_route(player, pocket)
		var t_after := Time.get_ticks_msec()
		var stamped := int(_main._free["at"])
		_check(t_after - t_before >= 5 and t_after - stamped <= 15 and stamped - t_before >= (t_after - t_before) - 15,
			"the click's time is taken when its route is ready (a %d ms search: stamped %d ms after the press, %d ms before the end)" % [t_after - t_before, stamped - t_before, t_after - stamped])
		_main._free["held"] = true
		_main._test_holding = true
		_main._pick_grid = Vector2(pocket)
		OS.delay_msec(100)
		_main._test_holding = false
		var released_way: Vector2 = _main._free_intent(player, own)
		_check(not (_main._free.get("path", []) as Array).is_empty() and released_way != Vector2.ZERO, "released 100 ms on, the click walks (%d cells, way %s)" % [(_main._free.get("path", []) as Array).size(), released_way])
		_main._free_route(player, pocket)
		_main._free["held"] = true
		_main._free["at"] = Time.get_ticks_msec() - 600
		_main._test_holding = true
		_main._pick_grid = Vector2(pocket)
		var held_way: Vector2 = _main._free_intent(player, own)
		_check(not (_main._free.get("path", []) as Array).is_empty() and held_way != Vector2.ZERO, "held past the hold over the same cell, it still walks and does not steer (%d cells)" % (_main._free.get("path", []) as Array).size())
		_main._test_holding = false
		_main._free["held"] = false
		Net.controls = controls_was
	else:
		print("  (no own free body here: the held-click steering row skipped)")
	# A target that cannot be reached, then moves: its chase walks to the cell nearest it, and plans again as it moves.
	var foe := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "name": "RouteImp", "tile": pocket}) as Monster
	if foe != null:
		foe.sight_range = 0
		_main._free["chase"] = foe
		_main._free["chase_tile"] = Vector2i(-99999, -99999)
		_main._free["chase_shove"] = false
		_main._free["chase_sent"] = Time.get_ticks_msec()  # (A chase as _free_chase_begin makes it: its order not resent here.)
		_main._free_chase(player, Vector2(free))
		var first: Array = (_main._free.get("path", []) as Array).duplicate()
		_check(not first.is_empty() and World.distance(first.back(), pocket) <= 2, "a chase of one in the pocket walks to the cell nearest it (%s)" % [first.back() if not first.is_empty() else "none"])
		var second_at: Vector2i = rings[1]["centre"]
		World._relocate(foe, second_at)
		_main._free_chase(player, Vector2(free))
		var second: Array = _main._free.get("path", [])
		_check(not second.is_empty() and World.distance(second.back(), second_at) <= 2 and second.back() != first.back(),
			"it moves to the other pocket: the route is planned again to the cell nearest that (%s)" % [second.back() if not second.is_empty() else "none"])
		_main._free["chase"] = null
		World.despawn(foe)
	# The cap ends the search early: "nearest" is then the nearest cell the search reached, so the walk goes toward the goal and stops
	# short of it, never away: a far goal under a tiny bound ends no farther from it than the start, and short of it.
	var far := Vector2i.ZERO
	for reach in [60, 50, 45, 40]:
		for way: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if far == Vector2i.ZERO and World.is_walkable(free + way * reach) and World.get_entity_at(free + way * reach) == null:
				far = free + way * reach
	if far == Vector2i.ZERO:
		print("  (no free far cell to try a short bound on: skipped)")
	else:
		var stopped := World.walk_path(free, far, player, World.PATH_FIRE_EXTRA, 150, true)
		_check(not stopped.is_empty() and stopped.back() != far and World.distance(stopped.back(), far) <= World.distance(free, far),
			"a bound that ends the search early: toward %s and stopped short at %s, no farther from it than the start (%d to %d)" % [
				far, stopped.back() if not stopped.is_empty() else "none", World.distance(free, far), World.distance(stopped.back(), far) if not stopped.is_empty() else -1])
	# Rolf's stand as Umbrage lays it (the wilds' M2, counter row 196): a click from the street on his own cell has a route (round the
	# counter to his side), so this is a walk-round, not a nearest: it ends at his cell, once, and never farther from it than it began.
	var rolf_cell := Vector2i(203, 196)
	var street := Vector2i(203, 201)
	if World.is_walkable(rolf_cell) and World.is_walkable(street) and World.get_entity_at(street) == null:
		World._relocate(player, street)
		var from_street := World.free_cell(player, Vector2(player.tile))
		_main._free_taken_over(player)
		_main._free_route(player, rolf_cell)
		var to_rolf: Array = _main._free.get("path", [])
		var routed := not World.walk_path(from_street, rolf_cell, player, World.PATH_FIRE_EXTRA, World.CLICK_SEARCH_TILES).is_empty()
		_check(routed and not to_rolf.is_empty() and to_rolf.back() == rolf_cell,
			"a click from the street (%s) on the cell behind Rolf's counter %s is a walk-round: a route exists and the walk ends at it (%d cells, from %d off)" % [
				street, rolf_cell, to_rolf.size(), World.distance(from_street, rolf_cell)])
	else:
		print("  (the wilds' M2 cells are not floor here: Rolf's counter row skipped)")
	_main._free["path"] = []
	for chest: Chest in blocks:
		World.despawn(chest)


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


## ui-design's joined run of the healer's window (11-16, ui-route's rows): "too far away" under Buy with the player one cell from Hob (150,233) inside
## his hut, 15 s on. The server's barter look is answered by World.in_person (PERSON_REACH 3 and line of sight from the player's cell as the SERVER holds
## it), and the client opens the window on its own cell, a step or two ahead. These are the sight lines into his bench cell from the cells the walk
## in passes: the door cell (152,232) and the street cell before it are out of sight of him, so a look sent as the window opens there is refused.
func _test_hut_sight() -> void:
	print("
== Hob's hut: from which cells of the walk in he is in person (the barter look's answer) ==")
	var hob := Vector2i(150, 233)
	var rows: Array[String] = []
	var seen_from: Dictionary = {}
	for cell: Vector2i in [Vector2i(152, 229), Vector2i(152, 230), Vector2i(152, 231), Vector2i(152, 232), Vector2i(152, 233), Vector2i(151, 233)]:
		var in_reach := World.distance(cell, hob) <= World.PERSON_REACH
		var sight := World.has_line_of_sight(cell, hob)
		seen_from[cell] = in_reach and sight
		rows.append("%s %s%s" % [cell, "reach" if in_reach else "far", " sight" if sight else " no sight"])
	print("  %s" % [rows])
	_check(bool(seen_from[Vector2i(151, 233)]) and bool(seen_from[Vector2i(152, 233)]), "inside the hut, beside him, he is in person (%s)" % [rows])
	var first_out := ""
	for cell: Vector2i in [Vector2i(152, 231), Vector2i(152, 232)]:
		if World.distance(cell, hob) <= World.PERSON_REACH and not bool(seen_from[cell]):
			first_out += "%s " % cell
	print("  in reach and out of his sight: %s" % ("none" if first_out.is_empty() else first_out))
