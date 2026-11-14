extends Node
## The short searches' bounds (decision 685): a companion's yield
## (Companion.YIELD_SEARCH_TILES), her step aside from her player's way
## (Heel.ASIDE_SEARCH_TILES) and her dodge (Companion.DODGE_SEARCH_TILES)
## look for their ways closing at most that many cells, where unbounded a
## cell behind a wall walked the search round the zone. On real maps (the
## wilds, the castle), from cells beside walls and doors, the bounded search
## finds every short way the unbounded one does, the same way, and no other.
## A resident's way (Resident.RESIDENT_SEARCH_TILES, decision 818's bound on the
## town soak's 1.3 s tick) finds every walk of a town's size the unbounded
## search does, on the wilds, the hills and Umbrage (held); and bodies past
## Resident.RESIDENT_BODIES_WITHIN of it are planned through.
## A companion's way (Heel.STEP_SEARCH_TILES, 818 amended) finds every walk
## across the whole map the unbounded search does, on the wilds, the hills and
## Umbrage, and a walled-off goal is given up at that bound.
## Run it with tests/run.ps1 or tests/run.sh.

const FROM_CELLS := 250

var _failures := 0
var _stuck := 0  # Walks of the scan's that never ended (a route planned again for ever).
const SCAN_LEGS := 400
var _main: Node


func _ready() -> void:
	World.set_process(false)
	var ports := preload("res://tests/test_ports.gd")
	Net.port = ports.of(17912)
	Net.companions = false
	Net.map_name = "wilds"
	Net.state_path = ""
	Level.overlay_dir = ports.scratch("path_bound_overlay/")
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	for map in ["wilds", "castle"]:
		_main.load_map(map)
		World.enter_named(map)
		_test_map(map)
	for map in ["wilds", "hills", "held"]:
		_main.load_map(map)
		World.enter_named(map)
		_test_resident_walks(map)
	_test_far_crowd()
	for map in ["wilds", "hills", "held"]:
		_main.load_map(map)
		World.enter_named(map)
		_test_companion_walks(map)
	_test_walled_off()
	_test_link_cells()
	for map in ["wilds", "held", "umbrage_tavern"]:
		_test_link_scan(map)
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


## Cells beside a wall, a cliff or a door (a door's own cells among them),
## FROM_CELLS of them spread over the map.
func _walled_cells() -> Array[Vector2i]:
	var doors := Companion.door_cells()
	var near: Array[Vector2i] = []
	for cell in World.floor_cells():
		if not World.is_walkable(cell):
			continue
		for way: Vector2i in World.DIRECTIONS:
			if doors.has(cell + way) or doors.has(cell) or World._terrain_blocks_step(cell, way, true):
				near.append(cell)
				break
	near.sort()
	var picked: Array[Vector2i] = []
	var every := maxi(1, near.size() / FROM_CELLS)
	for i in range(0, near.size(), every):
		picked.append(near[i])
	return picked


## Within [param reach] of [param from], every walkable cell's way, bounded
## at [param bound] and not: a way of [param short] steps or fewer the
## unbounded search finds, the bounded one finds the same; any the bounded
## one finds is the unbounded one's. The count of ways asked and differing.
func _agree(from: Vector2i, reach: int, bound: int, short: int) -> Vector2i:
	var asked := 0
	var differ := 0
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var cell := from + Vector2i(dx, dy)
			if cell == from or not World.is_walkable(cell):
				continue
			asked += 1
			var open := World.find_path(from, cell)
			var bounded := World.find_path(from, cell, false, null, bound)
			var open_short := not open.is_empty() and open.size() <= short
			if (open_short or not bounded.is_empty()) and bounded != open:
				differ += 1
				if differ <= 3:
					print("    %s to %s: unbounded %s, bounded %s" % [from, cell, open, bounded])
	return Vector2i(asked, differ)


func _test_map(map: String) -> void:
	print("== %s: bounded short searches agree with unbounded ones ==" % map)
	var froms := _walled_cells()
	var doors := Companion.door_cells().size()
	_check(froms.size() >= 100, "%d cells beside walls and doors to search from (%d door cells)" % [froms.size(), doors])
	var cases := [
		["a yield", Companion.YIELD_REACH, Companion.YIELD_SEARCH_TILES, Companion.YIELD_REACH],
		["a step aside", 1, Heel.ASIDE_SEARCH_TILES, 1],
		["a dodge", Companion.DODGE_REACH, Companion.DODGE_SEARCH_TILES, 2 * Companion.DODGE_REACH],
	]
	for each: Array in cases:
		var asked := 0
		var differ := 0
		for from in froms:
			var counts := _agree(from, each[1], each[2], each[3])
			asked += counts.x
			differ += counts.y
		_check(asked > 0 and differ == 0, "%s (within %d, bounded at %d cells): %d of %d ways of %d steps or fewer differ" % [
			each[0], each[1], each[2], differ, asked, each[3]])


## A resident's bounded way against the unbounded one (perf): from cells
## beside walls and doors to cells up to RESIDENT_WALK cells off, every way
## the unbounded search finds, the bounded one finds too (the wilds' winding
## ways of ~200 steps closed up to 12000 tiles).
const RESIDENT_WALK := 60
func _test_resident_walks(map: String) -> void:
	print("== %s: a resident's bounded way finds every town-sized walk ==" % map)
	var froms := _walled_cells()
	var asked := 0
	var missed := 0
	var longest := 0
	for n in froms.size() * 2:
		var i := n / 2
		var from := froms[i]
		var to := froms[(i + (3 if n % 2 == 0 else 12)) % froms.size()]
		if to == from or maxi(absi(to.x - from.x), absi(to.y - from.y)) > RESIDENT_WALK:
			continue
		var open := World.find_path(from, to, false, null, 0, false, {}, true, World.PATH_FIRE_EXTRA, Resident.RESIDENT_BODIES_WITHIN)
		if open.is_empty():
			continue
		asked += 1
		longest = maxi(longest, open.size())
		var bounded := World.find_path(from, to, false, null, Resident.RESIDENT_SEARCH_TILES, false, {}, true,
				World.PATH_FIRE_EXTRA, Resident.RESIDENT_BODIES_WITHIN)
		if bounded.is_empty():
			missed += 1
			if missed <= 3:
				print("    %s to %s: %d steps unbounded, none bounded" % [from, to, open.size()])
	_check(asked >= 20 and missed == 0, "%d walks found (the longest %d steps), %d missed at %d tiles" % [
		asked, longest, missed, Resident.RESIDENT_SEARCH_TILES])


## A goal ringed by bodies far from the start: planned through with
## bodies_within, no way with every body blocking; a ring beside the start
## still blocks.
func _test_far_crowd() -> void:
	print("
== bodies far off are planned through (find_path's bodies_within) ==")
	_main.load_map("wilds")
	World.enter_named("wilds")
	var froms := _walled_cells()
	var from := Vector2i.ZERO
	var goal := Vector2i.ZERO
	var found := false
	for cell in World.floor_cells():
		if not World.is_walkable(cell) or World._occupancy.has(cell):
			continue
		var clear := true
		for dy in range(-12, 13):
			for dx in range(-2, 15):
				var at := cell + Vector2i(dx, dy)
				if not World.is_walkable(at) or World._occupancy.has(at):
					clear = false
		if clear:
			from = cell
			goal = cell + Vector2i(12, 0)
			found = true
			break
	_check(found and froms.size() > 0, "open ground for it at %s" % from)
	var body := GridEntity.new()
	var ring: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx != 0 or dy != 0:
				ring.append(goal + Vector2i(dx, dy))
	for cell in ring:
		World._occupancy[cell] = body
	var blocked := World.find_path(from, goal, false, null, Resident.RESIDENT_SEARCH_TILES)
	var through := World.find_path(from, goal, false, null, Resident.RESIDENT_SEARCH_TILES, false, {}, true,
			World.PATH_FIRE_EXTRA, Resident.RESIDENT_BODIES_WITHIN)
	_check(blocked.is_empty(), "every body blocking: no way into the ring 12 cells off")
	_check(not through.is_empty() and through[-1] == goal, "within %d only: planned through the far ring (%d steps)" % [
		Resident.RESIDENT_BODIES_WITHIN, through.size()])
	for cell in ring:
		World._occupancy.erase(cell)
	# The same ring round the start: bodies beside it still block.
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx != 0 or dy != 0:
				World._occupancy[from + Vector2i(dx, dy)] = body
	var hemmed := World.find_path(from, goal, false, null, Resident.RESIDENT_SEARCH_TILES, false, {}, true,
			World.PATH_FIRE_EXTRA, Resident.RESIDENT_BODIES_WITHIN)
	_check(hemmed.is_empty(), "a ring beside it still blocks")
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			World._occupancy.erase(from + Vector2i(dx, dy))
	body.free()


## A companion's bounded way against the unbounded one (818 amended): from
## cells beside walls and doors to cells anywhere on the map (her player can
## call her from across it), every way the unbounded search finds, the bounded
## one finds too, with heel's own arguments (a goal she may stand on, off fire).
func _test_companion_walks(map: String) -> void:
	print("== %s: her bounded way finds every walk across the map ==" % map)
	var cells: Array[Vector2i] = []
	for cell in World.floor_cells():
		if World.is_walkable(cell):
			cells.append(cell)
	cells.sort()
	var froms := _walled_cells()
	var asked := 0
	var missed := 0
	var longest := 0
	var farthest := 0
	# Every other cell beside a wall (about 150 walks a map: the suite's
	# scenes run at once, the longest setting its time; release).
	for i in range(0, froms.size(), 2):
		var from: Vector2i = froms[i]
		var to: Vector2i = cells[(i * 97 + 113 * 1009) % cells.size()]
		if to == from:
			continue
		var open := World.find_path(from, to, true, null, 0, false, {}, true, World.PATH_FIRE_AVOID)
		if open.is_empty():
			continue
		asked += 1
		longest = maxi(longest, open.size())
		farthest = maxi(farthest, World.distance(from, to))
		if World.find_path(from, to, true, null, Heel.STEP_SEARCH_TILES, false, {}, true, World.PATH_FIRE_AVOID).is_empty():
			missed += 1
			if missed <= 3:
				print("    %s to %s: %d steps unbounded, none bounded" % [from, to, open.size()])
	_check(asked >= 100 and farthest >= 150 and missed == 0, "%d walks found (the farthest %d cells off, the longest %d steps), %d missed at %d tiles" % [
		asked, farthest, longest, missed, Heel.STEP_SEARCH_TILES])


## A goal walled off on the wilds: her bounded search gives up having closed
## its bound, where the unbounded one searched the zone (the time is printed,
## not checked: the machine is shared).
func _test_walled_off() -> void:
	print("== a walled-off goal: given up at her bound ==")
	_main.load_map("wilds")
	World.enter_named("wilds")
	var from := Vector2i.ZERO
	var goal := Vector2i.ZERO
	for cell in World.floor_cells():
		if World.is_walkable(cell) and World.distance(cell, Vector2i(128, 128)) < 40 and not World._occupancy.has(cell):
			from = cell
			break
	for cell in World.floor_cells():
		if World.is_walkable(cell) and World.distance(cell, from) > 60 and not World._occupancy.has(cell):
			goal = cell
			break
	var body := GridEntity.new()
	var ring: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var at := goal + Vector2i(dx, dy)
			if (dx != 0 or dy != 0) and not World._occupancy.has(at):
				ring.append(at)
	for cell in ring:
		World._occupancy[cell] = body
	var t0 := Time.get_ticks_usec()
	var open := World.find_path(from, goal, true, null, 0, false, {}, true, World.PATH_FIRE_AVOID)
	var t1 := Time.get_ticks_usec()
	var bounded := World.find_path(from, goal, true, null, Heel.STEP_SEARCH_TILES, false, {}, true, World.PATH_FIRE_AVOID)
	var t2 := Time.get_ticks_usec()
	for cell in ring:
		World._occupancy.erase(cell)
	body.free()
	_check(open.is_empty() and bounded.is_empty(), "%s to %s ringed by bodies: no way either way (unbounded %d ms, bounded %d ms)" % [
		from, goal, (t1 - t0) / 1000, (t2 - t1) / 1000])


## A level link's cell is a step only as the goal (the link fix, after 875): try_move refuses any body
## but a player onto one (571), so a route across one stalled at it for ever (Rolf asleep on his feet a
## night at the Mughouse's door). Open ground with a link cell on the straight way: the way goes round it,
## a resident's legs too, and a way whose goal is the link still ends on it.
func _test_link_cells() -> void:
	print("== a link's cell: round it, unless it is the goal ==")
	_main.load_map("wilds")
	World.enter_named("wilds")
	var from := Vector2i.ZERO
	var found := false
	for cell in World.floor_cells():
		var clear := true
		for dy in range(-3, 4):
			for dx in range(-1, 14):
				var at := cell + Vector2i(dx, dy)
				if not World.is_walkable(at) or World._occupancy.has(at) or World.is_link_cell(at):
					clear = false
		if clear:
			from = cell
			found = true
			break
	_check(found, "open ground for it at %s" % from)
	var goal := from + Vector2i(12, 0)
	var straight := World.find_path(from, goal, false, null, Resident.RESIDENT_SEARCH_TILES, false, {}, true,
			World.PATH_FIRE_EXTRA, Resident.RESIDENT_BODIES_WITHIN)
	var link := from + Vector2i(6, 0)
	_check(link in straight, "with no link, the straight way crosses %s (%d steps)" % [link, straight.size()])
	World.fields.link_cells[link] = true
	World.fields.link_cells[link + Vector2i(0, 1)] = true
	var way := World.find_path(from, goal, false, null, Resident.RESIDENT_SEARCH_TILES, false, {}, true,
			World.PATH_FIRE_EXTRA, Resident.RESIDENT_BODIES_WITHIN)
	var on_links := way.filter(func(cell: Vector2i) -> bool: return World.is_link_cell(cell))
	_check(not way.is_empty() and way[-1] == goal and on_links.is_empty(),
		"a link's cell on its way: round it to the goal (%d steps, on links %s)" % [way.size(), on_links])
	var legs := World.legs_path(from, way, goal)
	var legs_on := legs.filter(func(cell: Vector2i) -> bool: return World.is_link_cell(cell))
	_check(not legs.is_empty() and legs[-1] == goal and legs_on.is_empty(),
		"a resident's legs keep off it too (%d steps, on links %s)" % [legs.size(), legs_on])
	_check(not World._line_clear(from, goal, goal, null) and World._line_clear(from, link, link, null),
		"a straight line across it is not clear; one ending on it is")
	var to_link := World.find_path(from, link, false, null, Resident.RESIDENT_SEARCH_TILES)
	var before := to_link.slice(0, maxi(to_link.size() - 1, 0)).filter(func(cell: Vector2i) -> bool: return World.is_link_cell(cell))
	_check(not to_link.is_empty() and to_link[-1] == link and before.is_empty(),
		"its goal the link: the way ends on it (%d steps, other links on it %s)" % [to_link.size(), before])
	World.fields.link_cells.erase(link)
	World.fields.link_cells.erase(link + Vector2i(0, 1))


## Every level link of [param map] (689 amended (12)): every click walk a player makes from a cell
## within 3 of it to one within 4 (both walkable, not the link, 2 or more apart), walked as his free
## body walks it (Main._free_pull from where he is, straight at the head, on from there), from the
## start cell's centre and four points 0.3 off it, never puts his centre in the link's cell before
## the walk's end (looked at every 0.05 of a cell, apart from the code it judges), nor steps on it
## by its route; and the link's corner rule closes no way and lengthens few (a doorway beside a
## link stays open: the tavern's (16, 10), Umbrage's house doors).
func _test_link_scan(map: String) -> void:
	print("== %s: walks past each way out keep off it ==" % map)
	_main.load_map(map)
	World.enter_named(map)
	var player: Player = null
	for entity in World.sought():
		if entity is Player:
			player = entity
	_check(player != null, "(a player to walk: %s)" % player)
	if player == null:
		return
	var offs: Array[Vector2] = [Vector2.ZERO, Vector2(0.3, 0.3), Vector2(-0.3, 0.3), Vector2(0.3, -0.3), Vector2(-0.3, -0.3)]
	var links: Array = World.fields.link_cells.keys()
	_check(not links.is_empty(), "(%s has %d links)" % [map, links.size()])
	for link: Vector2i in links:
		# Its open sides (a step from it the terrain lets a walker take): a way out with one side open
		# (a stair in a corner, a breach in a wall) has no walk passing beside it to judge.
		var open: Array[Vector2i] = []
		for way: Vector2i in World.DIRECTIONS:
			if World.is_walkable(link + way) and not World._terrain_blocks_step(link, way, true):
				open.append(way)
		print("    %s link %s: open sides %s" % [map, link, open])
		var walks := 0
		_stuck = 0
		var by_stale := 0
		var by_route := 0
		var by_walk := 0
		var longer := 0
		var most := 0
		var extra_walked := 0.0
		var worst_walked := 0.0
		var walked_longer := 0
		var closed := 0
		var shown := 0
		for ay in range(-3, 4):
			for ax in range(-3, 4):
				var a := link + Vector2i(ax, ay)
				if a == link or not World.is_walkable(a) or World.is_link_cell(a):
					continue
				for by in range(-4, 5):
					for bx in range(-4, 5):
						var b := link + Vector2i(bx, by)
						if b == link or World.is_link_cell(b) or not World.is_walkable(b) or maxi(absi(b.x - a.x), absi(b.y - a.y)) < 2:
							continue
						var route := World.walk_path(a, b, player)
						var anyone := World.find_path(a, b, true, null)
						if route.is_empty():
							if not anyone.is_empty():
								closed += 1
							continue
						walks += 1
						var extra := World.find_path(a, b, true, player).size() - anyone.size()
						if extra > 0:
							longer += 1
							most = maxi(most, extra)
						# What the body walks (the pulled legs from the start's centre), the rule on and off.
						World.link_corner_rule = false
						var without := _walked(player, World.walk_path(a, b, player), Vector2(a))
						World.link_corner_rule = true
						var more := _walked(player, route, Vector2(a)) - without
						if more > 0.001:
							walked_longer += 1
							extra_walked += more
							worst_walked = maxf(worst_walked, more)
						var on_route := route.slice(0, route.size() - 1).has(link)
						var on_walk := false
						for off: Vector2 in offs:
							on_walk = on_walk or _walk_crosses(player, route, Vector2(a) + off, link)
						# A route planned two cells off (before a knock, a shove or a throw's landing set the
						# body down at a), walked from a: its head is not beside the body.
						for away: Vector2i in [Vector2i(2, 0), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(0, -2)]:
							var a2 := a + away
							if a2 == b or not World.is_walkable(a2) or World.is_link_cell(a2):
								continue
							var stale := World.walk_path(a2, b, player)
							if not stale.is_empty() and _walk_crosses(player, stale, Vector2(a), link):
								by_stale += 1
								if shown < 3:
									shown += 1
									print("    %s (its route from %s) -> %s: walked over it (route %s)" % [a, a2, b, stale])
						by_route += 1 if on_route else 0
						by_walk += 1 if on_walk else 0
						if (on_route or on_walk) and shown < 3:
							shown += 1
							print("    %s -> %s: route %s, walked over it %s (route %s)" % [a, b, on_route, on_walk, route])
		print("    %s link %s: walked farther by the corner rule on %d walks, %.2f cells more on average, %.2f at worst" 				% [map, link, walked_longer, extra_walked / maxi(walked_longer, 1), worst_walked])
		_check(_stuck == 0, "%s link %s: every walk ends (%d went on past %d legs)" % [map, link, _stuck, SCAN_LEGS])
		_check(by_stale == 0, "%s link %s: routes planned 2 cells off, walked from the start: %d walked over it" % [map, link, by_stale])
		_check(by_route == 0 and by_walk == 0 and closed == 0,
				"%s link %s: %d walks, %d step on it by route, %d walked over it, %d closed by its corner, %d made longer (by %d steps at most)" 				% [map, link, walks, by_route, by_walk, closed, longer, most])


## How far [param player]'s free body walks [param route] from [param at]: each pulled leg
## (Main._free_pull from where it is, straight at the head), summed.
func _walked(player: Player, route: Array[Vector2i], at: Vector2) -> float:
	var path: Array = []
	path.assign(route)
	var length := 0.0
	var legs := 0
	while not path.is_empty():
		legs += 1
		if legs > SCAN_LEGS:
			_stuck += 1
			break
		_main._free_pull(player, path, at)
		if path.is_empty():
			break
		var head := Vector2(path[0])
		length += at.distance_to(head)
		at = head
		path.pop_front()
	return length


## Whether [param player]'s free body, walking [param route] from [param at] as it does (Main._free_pull
## from where it is, straight at the head, on from there), puts its centre in [param link]'s cell
## before the walk's end; looked at every 0.05 of a cell.
func _walk_crosses(player: Player, route: Array[Vector2i], at: Vector2, link: Vector2i) -> bool:
	var path: Array = []
	path.assign(route)
	var legs := 0
	while not path.is_empty():
		legs += 1
		if legs > SCAN_LEGS:
			_stuck += 1
			return false
		_main._free_pull(player, path, at)
		if path.is_empty():
			break
		var head := Vector2(path[0])
		var steps := maxi(ceili(at.distance_to(head) / 0.05), 1)
		for t in steps + 1:
			if Vector2i(at.lerp(head, float(t) / steps).round()) == link and path[0] != link:
				return true
		at = head
		path.pop_front()
	return false
