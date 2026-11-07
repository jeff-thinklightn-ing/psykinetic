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
## Run it with tests/run.ps1 or tests/run.sh.

const FROM_CELLS := 250

var _failures := 0
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
