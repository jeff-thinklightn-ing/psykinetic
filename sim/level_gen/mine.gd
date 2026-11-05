extends RefCounted
## The mine's generator (decision 790, 769's phases 2-3; Hollowfell): the
## template's anchors kept, the rest laid as mine_look's vocabulary
## (tools/make_mine_look.py) over the whole level. Bays (small chambers) set
## in the rock and the anchors joined by twisting tunnels 3 to 5 wide, a
## spanning tree with loops so the routes close into rings; 2-wide side
## galleries off the tunnels (the sneaks flank there, enemy-ai); pits beside
## a tunnel, never across it, each with a stair run two wide back up and a
## lamp at its foot (783: a pit with no way out is a trap); ore seams in
## recesses; track on a straight with a cart, arches where a tunnel runs
## straight, beams over the bays, lamps on the walls (each a "lantern"
## marker, environment's light); then the monsters, none near the mouth.
## Every cell dug stands at FLOOR_LEVEL but the pits'. Regen reads the
## decor, the cart's entity and the relief's ledges from decor_of,
## entities_of and ledges_of. Loaded by name (Regen.GENERATORS), so no
## class_name.

const Tools := preload("res://sim/level_gen/gen_tools.gd")
const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const FLOOR := "stone"
## The level every dug cell stands at, and a pit's floor (three levels down:
## a body knocked in falls, and climbs out by the stair run).
const FLOOR_LEVEL := 3
const PIT_LEVEL := 0
## Rock kept round the map's rim, so the mass draws past the last tunnel.
const RIM := 2
const DEFAULT_BAYS: Array[int] = [4, 6]
const BAY_SIZE: Array[int] = [6, 8]
const DEFAULT_LOOPS := 0.25
const DEFAULT_GALLERIES: Array[int] = [3, 5]
const GALLERY_LENGTH: Array[int] = [5, 10]
const DEFAULT_PITS: Array[int] = [2, 3]
const DEFAULT_SEAMS: Array[int] = [7, 10]
const SEAM_APART := 6
const LAMP_APART := 11
const ARCH_APART := 6
const TRACK_LENGTH: Array[int] = [8, 14]
const TRACK_WIDE := 4
const TRACK_SPAN := 6
const TRACK_CLEAR := 2
## No monster within this many cells (Chebyshev) of the entrance anchor.
const MOUTH_CLEAR := 6
const GUARD_OUT := 4
const ROUTE_APART := 9


static func generate(template: LevelMap, config: Dictionary, seed: int) -> LevelMap:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var anchors: Array = config.get("anchors", [])
	var map := template.copy()
	Tools.clear_outside(map, anchors)
	var carved: Dictionary[Vector2i, bool] = {}
	var plan := {"carved": carved, "levels": {}, "bays": [], "galleries": {}, "track": {}, "decor": [], "entities": []}
	var nodes: Array[Dictionary] = []
	for anchor: Dictionary in anchors:
		var exits := _exits(map, anchors, anchor["rect"])
		if exits.is_empty():
			continue
		nodes.append({"at": exits[exits.size() / 2], "exits": exits})
	for bay in _bays(map, anchors, config, rng):
		plan["bays"].append(bay)
		for cell: Vector2i in bay["cells"]:
			Tools.carve(map, cell, carved)
		nodes.append({"at": bay["centre"], "exits": []})
	var ways := _ways(nodes, float(config.get("loops", DEFAULT_LOOPS)), rng)
	var narrow := rng.randi_range(0, ways.size() - 1) if not ways.is_empty() else -1
	var wide := (narrow + 1 + rng.randi_range(0, maxi(ways.size() - 2, 0))) % maxi(ways.size(), 1)
	for index in ways.size():
		var middle := 3 if index == narrow else (5 if index == wide else 4)
		_tunnel(map, anchors, nodes[ways[index][0]], nodes[ways[index][1]], middle, rng, carved)
	Tools.join_up(map, anchors, carved)
	Tools.widen(map, anchors, carved)
	_galleries(map, anchors, config, rng, plan)
	_pits(map, anchors, config, rng, plan)
	_seams(map, anchors, config, rng, plan)
	_track(map, anchors, rng, plan)
	_arches(map, anchors, plan)
	_beams(map, plan)
	_lamps(map, anchors, plan)
	_monsters(map, anchors, config, rng, plan)
	_fill_bays(map, anchors, rng, plan)
	var levels: Dictionary = plan["levels"]
	for cell: Vector2i in map.cells:
		if not Level.in_anchors(anchors, cell):
			var level := int(levels.get(cell, FLOOR_LEVEL))
			if level > 0:
				map.heights[cell] = level
			else:
				map.heights.erase(cell)
	map.extras["decor"] = plan["decor"]
	map.extras["entities"] = plan["entities"]
	return map


## The decor rows the generation laid (Level.decor_from's [x, y, dx, dy,
## kind, variant]): arches, beams, lamps, track; Regen adds them to the
## generated level.json's "decor".
static func decor_of(map: LevelMap) -> Array:
	return (map.extras.get("decor", []) as Array).duplicate(true)


## The level entities the generation adds ({at, art, facing}): the cart on
## its track drawn as the mine's (prop.mine_cart), faced along the run.
static func entities_of(map: LevelMap) -> Array:
	return (map.extras.get("entities", []) as Array).duplicate(true)


## The generated relief's ledges (decision 585), as Level.ledges_of finds
## them on the level loaded from this map: its whole levels over the
## walkable cells, those cells in row order.
static func ledges_of(map: LevelMap) -> Array:
	var heights := {}
	var ground := {}
	for y in map.size.y:
		for x in map.size.x:
			var cell := Vector2i(x, y)
			if not map.walkable(cell):
				continue
			ground[cell] = true
			if int(map.heights.get(cell, 0)) > 0:
				heights[cell] = map.heights[cell]
	if heights.is_empty():
		return []
	return Curves.trace_ledges(Relief.derived(heights, map.size), map.size, ground, {})


## The cells just outside [param rect]'s plain floor border cells on [param map]
## (in no anchor, in bounds): where a tunnel meets the anchor, in cell order.
static func _exits(map: LevelMap, anchors: Array, rect: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in Level.rect_cells(rect):
		if map.cell(cell) != FLOOR:
			continue  # A seam's recess or a lamp's cell is no way in.
		for direction in DIRECTIONS:
			var next := cell + direction
			if rect.has_point(next) or not _diggable(map, anchors, next) or next in out:
				continue
			out.append(next)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or a.y == b.y and a.x < b.x)
	return out


## Whether [param at] may be dug: rock outside every anchor, RIM cells in
## from the map's edge.
static func _diggable(map: LevelMap, anchors: Array, at: Vector2i) -> bool:
	return at.x >= RIM and at.y >= RIM and at.x < map.size.x - RIM and at.y < map.size.y - RIM \
			and Tools.rock(map, anchors, at)


## The bays: [{rect, cells, centre}], "bays" [least, most] of them (else
## DEFAULT_BAYS), each BAY_SIZE across, a rounded rectangle set in the rock
## three cells clear of every anchor and two of every other bay.
static func _bays(map: LevelMap, anchors: Array, config: Dictionary, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var span: Array = config.get("bays", DEFAULT_BAYS)
	var count := rng.randi_range(int(span[0]), int(span[1]))
	var out: Array[Dictionary] = []
	for attempt in 300:
		if out.size() >= count:
			break
		var size := Vector2i(rng.randi_range(BAY_SIZE[0], BAY_SIZE[1]), rng.randi_range(BAY_SIZE[0], BAY_SIZE[1]))
		var room := RIM + 2
		if map.size.x - 2 * room - size.x <= 0 or map.size.y - 2 * room - size.y <= 0:
			break
		var rect := Rect2i(Vector2i(rng.randi_range(room, map.size.x - room - size.x), rng.randi_range(room, map.size.y - room - size.y)), size)
		var clear := true
		for anchor: Dictionary in anchors:
			if (anchor["rect"] as Rect2i).grow(3).intersects(rect):
				clear = false
		for other in out:
			if (other["rect"] as Rect2i).grow(2).intersects(rect):
				clear = false
		if not clear:
			continue
		var cells: Array[Vector2i] = []
		var half := Vector2(size) / 2.0
		var centre := Vector2(rect.position) + half
		for cell in Level.rect_cells(rect):
			var d := (Vector2(cell) + Vector2(0.5, 0.5) - centre) / half
			if pow(absf(d.x), 4.0) + pow(absf(d.y), 4.0) <= 1.0 and _diggable(map, anchors, cell):
				cells.append(cell)
		out.append({"rect": rect, "cells": cells, "centre": rect.position + size / 2})
	return out


## Which nodes the tunnels join, as [[a, b], ...]: a minimum spanning tree
## over the nodes' cells, then the shortest pairs left, [param loops] a node
## of them (at least one, so the map has a ring).
static func _ways(nodes: Array[Dictionary], loops: float, rng: RandomNumberGenerator) -> Array[Array]:
	var out: Array[Array] = []
	if nodes.size() < 2:
		return out
	var joined: Array[int] = [0]
	var used := {}
	while joined.size() < nodes.size():
		var best: Array = []
		var best_d := INF
		for a in joined:
			for b in nodes.size():
				if b in joined:
					continue
				var d := Vector2(nodes[a]["at"]).distance_to(Vector2(nodes[b]["at"]))
				if d < best_d:
					best_d = d
					best = [a, b]
		joined.append(best[1])
		out.append(best)
		used[Vector2i(mini(best[0], best[1]), maxi(best[0], best[1]))] = true
	var rest: Array = []
	for a in nodes.size():
		for b in range(a + 1, nodes.size()):
			if not used.has(Vector2i(a, b)):
				rest.append([Vector2(nodes[a]["at"]).distance_to(Vector2(nodes[b]["at"])) + rng.randf() * 4.0, a, b])
	rest.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	var extra := maxi(roundi(loops * nodes.size()), 1)
	for pair: Array in rest.slice(0, extra):
		out.append([pair[1], pair[2]])
	return out


## A tunnel from node [param a] to node [param b]: a polyline through one to
## three waypoints thrown aside of the straight way, carved with
## mine_look's brush, its width eased from 4 at the ends to
## [param middle] at the middle, its sides roughened, never under 3 across.
static func _tunnel(map: LevelMap, anchors: Array, a: Dictionary, b: Dictionary, middle: int, rng: RandomNumberGenerator,
		carved: Dictionary[Vector2i, bool]) -> void:
	var from := Vector2(a["at"]) + Vector2(0.5, 0.5)
	var to := Vector2(b["at"]) + Vector2(0.5, 0.5)
	var length := from.distance_to(to)
	var across := (to - from).orthogonal().normalized() if length > 0.0 else Vector2.ZERO
	var points: Array[Vector2] = [from]
	var turns := rng.randi_range(1, 3)
	var low := Vector2(RIM + 2, RIM + 2)
	var high := Vector2(map.size - Vector2i(RIM + 2, RIM + 2))
	for k in turns:
		var t := float(k + 1) / float(turns + 1)
		var point := from.lerp(to, t) + across * rng.randf_range(-0.22, 0.22) * length
		points.append(point.clamp(low, high))
	points.append(to)
	var widths: Array[float] = []
	for k in points.size():
		var t := float(k) / float(points.size() - 1)
		widths.append(lerpf(4.0, float(middle), 1.0 - absf(t * 2.0 - 1.0)))
	for k in points.size() - 1:
		var p := points[k]
		var q := points[k + 1]
		var steps := maxi(1, int(p.distance_to(q) * 4.0))
		for s in steps + 1:
			var t := float(s) / float(steps)
			var centre := p.lerp(q, t)
			var radius := maxf(lerpf(widths[k], widths[k + 1], t) / 2.0 + rng.randf_range(-0.15, 0.35), 1.5)
			for y in range(int(centre.y - radius) - 1, int(centre.y + radius) + 2):
				for x in range(int(centre.x - radius) - 1, int(centre.x + radius) + 2):
					var cell := Vector2i(x, y)
					if (Vector2(cell) + Vector2(0.5, 0.5)).distance_to(centre) <= radius and _diggable(map, anchors, cell):
						Tools.carve(map, cell, carved)


## The side galleries ("galleries" [least, most], else DEFAULT_GALLERIES):
## each a blind spur two wide and GALLERY_LENGTH long, dug straight into the
## rock off a tunnel's side, a cell of rock either side of it and past its
## end, eight cells from any other. Its cells go in plan["galleries"].
static func _galleries(map: LevelMap, anchors: Array, config: Dictionary, rng: RandomNumberGenerator, plan: Dictionary) -> void:
	var span: Array = config.get("galleries", DEFAULT_GALLERIES)
	var count := rng.randi_range(int(span[0]), int(span[1]))
	var starts := _floor_cells(map, anchors)
	Tools.shuffle(starts, rng)
	var mouths: Array[Vector2i] = []
	var galleries: Dictionary = plan["galleries"]
	for cell in starts:
		if mouths.size() >= count:
			break
		if _in_bay(plan, cell) or mouths.any(func(other: Vector2i) -> bool: return Tools.distance(other, cell) < 8):
			continue
		for d in DIRECTIONS:
			var p := Vector2i(d.y, d.x)
			if map.cell(cell + p) != FLOOR or Level.in_anchors(anchors, cell + p):
				continue
			var length := rng.randi_range(GALLERY_LENGTH[0], GALLERY_LENGTH[1])
			var cells: Array[Vector2i] = []
			var fits := true
			for k in range(1, length + 2):
				for u in range(-1, 3):
					var at := cell + d * k + p * u
					var inside := u in [0, 1] and k <= length
					if not _diggable(map, anchors, at) or map.cell(at) != "void":
						fits = false
						break
					if inside:
						cells.append(at)
				if not fits:
					break
			if not fits:
				continue
			for at in cells:
				Tools.carve(map, at, plan["carved"])
				galleries[at] = true
			# 806: a dead end holds something. A seam in the gallery's end wall,
			# what the miners dug it for.
			var end := cell + d * (length + 1) + p * rng.randi_range(0, 1)
			map.set_cell(end, "seam")
			plan["carved"][end] = true
			mouths.append(cell)
			break


## The pits ("pits" [least, most], else DEFAULT_PITS), each dug into the
## rock beside a tunnel, never across it. Seen from the tunnel (u along its
## side, v into the rock): the pit two wide and four deep at u 0-1, its first
## row open on the tunnel (the drop); a stair run two wide (v 3-4) climbing
## from its far end a level a cell (u 2-4, levels 0-2) to floor at the
## tunnel's level (u 5-6, v 1-4) that opens onto the tunnel. Laid where no
## stair has a second cell a level up beside it (the mine_look lesson), with
## a lamp on the wall past the stair's foot, so whoever falls in sees the
## way out and whoever looks down sees how deep it goes (the coordinator).
static func _pits(map: LevelMap, anchors: Array, config: Dictionary, rng: RandomNumberGenerator, plan: Dictionary) -> void:
	var span: Array = config.get("pits", DEFAULT_PITS)
	var count := rng.randi_range(int(span[0]), int(span[1]))
	var starts := _floor_cells(map, anchors)
	Tools.shuffle(starts, rng)
	var laid: Array[Vector2i] = []
	var levels: Dictionary = plan["levels"]
	for cell in starts:
		if laid.size() >= count:
			break
		if laid.any(func(other: Vector2i) -> bool: return Tools.distance(other, cell) < 12):
			continue
		for d in DIRECTIONS:
			for p: Vector2i in [Vector2i(d.y, d.x), Vector2i(-d.y, -d.x)]:
				if not _pit_fits(map, anchors, plan, cell, d, p):
					continue
				var at := func(u: int, v: int) -> Vector2i: return cell + p * u + d * v
				for u in range(0, 7):
					Tools.carve(map, at.call(u, 0), plan["carved"])  # The tunnel's side squared off along the pit.
				for v in range(1, 5):
					for u in range(0, 2):
						Tools.carve(map, at.call(u, v), plan["carved"])
						levels[at.call(u, v)] = PIT_LEVEL
					for u in range(5, 7):
						Tools.carve(map, at.call(u, v), plan["carved"])
						levels[at.call(u, v)] = FLOOR_LEVEL
				for v in range(3, 5):
					for k in 3:
						var stair: Vector2i = at.call(2 + k, v)
						map.set_cell(stair, "stair")
						plan["carved"][stair] = true
						levels[stair] = PIT_LEVEL + k
				var lamp: Vector2i = at.call(1, 4)
				map.set_cell(lamp, "lantern")
				plan["decor"].append([lamp.x, lamp.y, d.x, d.y, "mine_lamp", 1])
				laid.append(cell)
				break
			if laid.has(cell):
				break


## Whether a pit fits at tunnel cell [param cell], dug along [param d] with
## the tunnel's side along [param p]: on v 0, u 0-6, tunnel floor (four of
## them at least, [param cell] one) or rock with tunnel floor behind it, dug
## to square the tunnel's side off; rock for u -1..7 on v 1..5; none of it
## in an anchor or a gallery.
static func _pit_fits(map: LevelMap, anchors: Array, plan: Dictionary, cell: Vector2i, d: Vector2i, p: Vector2i) -> bool:
	var floor := 0
	for u in range(0, 7):
		var edge := cell + p * u
		if Level.in_anchors(anchors, edge) or plan["galleries"].has(edge) or plan["levels"].has(edge):
			return false
		if map.cell(edge) == FLOOR:
			floor += 1
		elif map.cell(edge) != "void" or not _diggable(map, anchors, edge) or map.cell(edge - d) != FLOOR:
			return false
	if floor < 4 or map.cell(cell) != FLOOR:
		return false
	for v in range(1, 6):
		for u in range(-1, 8):
			var at := cell + p * u + d * v
			if not _diggable(map, anchors, at) or map.cell(at) != "void":
				return false
	return true


## The ore seams ("seams" [least, most], else DEFAULT_SEAMS): each a cell of
## rock beside a tunnel floor at its level, walled on its three other sides
## (mine_look's recess), the floor before it open on both sides across its
## way in, SEAM_APART from another, three cells clear of every anchor, dug
## and marked "seam".
static func _seams(map: LevelMap, anchors: Array, config: Dictionary, rng: RandomNumberGenerator, plan: Dictionary) -> void:
	var span: Array = config.get("seams", DEFAULT_SEAMS)
	var count := rng.randi_range(int(span[0]), int(span[1]))
	var spots: Array[Vector2i] = []
	for y in map.size.y:
		for x in map.size.x:
			var cell := Vector2i(x, y)
			if not _diggable(map, anchors, cell) or map.cell(cell) != "void" or _near_anchor(anchors, cell, 3):
				continue
			var opens: Array[Vector2i] = []
			for d in DIRECTIONS:
				if map.walkable(cell + d):
					opens.append(cell + d)
			if opens.size() != 1 or map.cell(opens[0]) != FLOOR or plan["levels"].has(opens[0]) or Level.in_anchors(anchors, opens[0]):
				continue
			# The floor before it open either side across its way in, so the
			# recess never caps a nub one cell wide (612).
			var across := Vector2i((opens[0] - cell).y, (opens[0] - cell).x)
			if map.walkable(opens[0] + across) and map.walkable(opens[0] - across):
				spots.append(cell)
	Tools.shuffle(spots, rng)
	var laid: Array[Vector2i] = []
	for cell in spots:
		if laid.size() >= count:
			break
		if laid.any(func(other: Vector2i) -> bool: return Tools.distance(other, cell) < SEAM_APART):
			continue
		map.set_cell(cell, "seam")
		plan["carved"][cell] = true
		laid.append(cell)


## Track (physics' 794 rules): one or two straight runs TRACK_LENGTH long
## down a tunnel's middle (floor at the tunnel's level either side of every
## cell, no stair, no drop, in no anchor or gallery), a buffer (variant 3)
## on each end, so no cell has three track neighbours and every end stops;
## a cart (the "cart" marker, drawn as prop.mine_cart along the run) on
## one cell of each.
static func _track(map: LevelMap, anchors: Array, rng: RandomNumberGenerator, plan: Dictionary) -> void:
	var runs: Array = []
	for cell in _floor_cells(map, anchors):
		for a: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			if _track_cell(map, anchors, plan, cell - a, a):
				continue  # Not a run's first cell.
			var length := 0
			while length < TRACK_LENGTH[1] and _track_cell(map, anchors, plan, cell + a * length, a):
				length += 1
			if length >= TRACK_LENGTH[0]:
				runs.append([length + rng.randf(), cell, a, length])
	runs.sort_custom(func(p: Array, q: Array) -> bool: return p[0] > q[0])
	var wanted := rng.randi_range(1, 2)
	var laid: Array[Array] = []
	for run: Array in runs:
		if laid.size() >= wanted:
			break
		var start: Vector2i = run[1]
		var a: Vector2i = run[2]
		var length: int = run[3]
		var cells: Array[Vector2i] = []
		for k in length:
			cells.append(start + a * k)
		var clear := true
		for other: Array in laid:
			for here in cells:
				for there: Vector2i in other:
					if Tools.distance(here, there) < 6:
						clear = false
		if not clear:
			continue
		laid.append(cells)
		for k in length:
			var at := cells[k]
			plan["track"][at] = true
			if k == 0:
				plan["decor"].append([at.x, at.y, -a.x, -a.y, "mine_track", 3])
			elif k == length - 1:
				plan["decor"].append([at.x, at.y, a.x, a.y, "mine_track", 3])
			else:
				plan["decor"].append([at.x, at.y, a.x, a.y, "mine_track", 1])
		var cart := cells[length / 2]
		map.set_cell(cart, "cart")
		plan["entities"].append({"at": [cart.x, cart.y], "art": "prop.mine_cart", "facing": [a.x, a.y]})


## A cell track may run along [param a] through (806 amended; the tour
## stalled 25 s at a cart in a two-cell way): floor at the tunnel's level
## either side, the tunnel TRACK_WIDE across at least (a cart on it leaves
## a way past) and at most TRACK_SPAN (no crossing of ways), no anchor or
## gallery within TRACK_CLEAR (a buffer never stands in a doorway).
static func _track_cell(map: LevelMap, anchors: Array, plan: Dictionary, cell: Vector2i, a: Vector2i) -> bool:
	var q := Vector2i(a.y, a.x)
	for at: Vector2i in [cell, cell + q, cell - q]:
		if map.cell(at) != FLOOR or Level.in_anchors(anchors, at) or plan["levels"].has(at) or plan["galleries"].has(at):
			return false
	var across := 1
	for side: Vector2i in [q, -q]:
		var k := 1
		while k <= TRACK_SPAN and map.walkable(cell + side * k):
			k += 1
		across += k - 1
	if across < TRACK_WIDE or across > TRACK_SPAN or _near_anchor(anchors, cell, TRACK_CLEAR):
		return false
	for dy in range(-TRACK_CLEAR, TRACK_CLEAR + 1):
		for dx in range(-TRACK_CLEAR, TRACK_CLEAR + 1):
			if plan["galleries"].has(cell + Vector2i(dx, dy)):
				return false
	return true


## Arches across the tunnels where they run straight (mine_look's rule): a
## span wall to wall 3 to 5 across at the tunnel's level, the same span at
## the cells either side along the way, ARCH_APART from another; none in a
## bay, an anchor or a gallery.
static func _arches(map: LevelMap, anchors: Array, plan: Dictionary) -> void:
	var arches: Array[Vector2i] = []
	var cells := _floor_cells(map, anchors)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or a.x == b.x and a.y < b.y)
	for cell in cells:
		if _in_bay(plan, cell) or plan["galleries"].has(cell):
			continue
		for pair: Array in [[Vector2i(0, 1), Vector2i(1, 0)], [Vector2i(1, 0), Vector2i(0, 1)]]:
			var way: Vector2i = pair[0]
			var along: Vector2i = pair[1]
			var width := _span(map, anchors, plan, cell, way, 6)
			if width < 3 or width > 5:
				continue
			var straight := true
			for side in [-1, 1]:
				if _span(map, anchors, plan, cell + along * side, way, 6) != width:
					straight = false
			if not straight or arches.any(func(other: Vector2i) -> bool: return Tools.distance(other, cell) < ARCH_APART):
				continue
			arches.append(cell)
			plan["decor"].append([cell.x, cell.y, way.x, way.y, "mine_arch", 1])
			break


## The span from [param cell] along [param way], wall to wall (walled
## behind it, every cell walkable plain floor at the tunnel's level, in no
## anchor, then walled), in cells; 0 when it is none or over [param most].
static func _span(map: LevelMap, anchors: Array, plan: Dictionary, cell: Vector2i, way: Vector2i, most: int) -> int:
	if map.walkable(cell - way):
		return 0
	var width := 0
	var at := cell
	while map.walkable(at):
		if map.cell(at) != FLOOR or Level.in_anchors(anchors, at) or plan["levels"].has(at):
			return 0
		width += 1
		if width > most:
			return 0
		at += way
	return width


## Beams over each bay, wall to wall, every other line, all one way: west
## to east, else north to south where that gives more.
static func _beams(map: LevelMap, plan: Dictionary) -> void:
	for bay: Dictionary in plan["bays"]:
		var rect: Rect2i = bay["rect"]
		var best: Array = []
		for pair: Array in [[Vector2i(1, 0), true], [Vector2i(0, 1), false]]:
			var way: Vector2i = pair[0]
			var rows: bool = pair[1]
			var found: Array = []
			var last := -10
			var lines := range(rect.position.y, rect.end.y) if rows else range(rect.position.x, rect.end.x)
			for k: int in lines:
				if k - last < 2:
					continue
				var first := Vector2i(-1, -1)
				var steps := range(rect.position.x, rect.end.x) if rows else range(rect.position.y, rect.end.y)
				for j: int in steps:
					var cell := Vector2i(j, k) if rows else Vector2i(k, j)
					if map.walkable(cell):
						first = cell
						break
				if first.x < 0 or map.walkable(first - way):
					continue
				var width := 0
				var at := first
				while map.walkable(at) and width <= 10:
					width += 1
					at += way
				if width < 3 or width > 10:
					continue
				found.append([first.x, first.y, way.x, way.y, "mine_beam", 1])
				last = k
			if found.size() > best.size():
				best = found
		plan["decor"].append_array(best)


## Lamps on the walls, LAMP_APART from another (and from the anchors'
## own): a floor cell at the tunnel's level with a wall on a side, its first
## walled side the lamp's; the cell marked "lantern" (environment's light).
static func _lamps(map: LevelMap, anchors: Array, plan: Dictionary) -> void:
	var lamps: Array[Vector2i] = []
	for cell: Vector2i in map.cells:
		if map.cells[cell] == "lantern":
			lamps.append(cell)
	for cell in _floor_cells(map, anchors):
		if plan["track"].has(cell) or plan["levels"].has(cell):
			continue
		if lamps.any(func(other: Vector2i) -> bool: return Tools.distance(other, cell) < LAMP_APART):
			continue
		for way in DIRECTIONS:
			if not map.walkable(cell + way):
				map.set_cell(cell, "lantern")
				plan["decor"].append([cell.x, cell.y, way.x, way.y, "mine_lamp", 1])
				lamps.append(cell)
				break


## The Blood Rot ("monsters" {kind: count}), laid where a walker meets
## them (806 amended; playtest's tour: mouth to both chambers and not one
## fight). The route is the shortest walks from the entrance to each other
## anchor. First a guard on the route a few cells outside each chamber (an
## imp, else any kind), so every chamber has its fight; the brute in the bay
## nearest the route with an imp beside it if one is left; each sneak two
## cells into a gallery whose mouth is on the route, waiting in the dark
## off the way; the imps left along the route, ROUTE_APART apart. What finds
## no such spot goes anywhere, as before. Never within MOUTH_CLEAR of the
## entrance, on track, a stair or a pit.
static func _monsters(map: LevelMap, anchors: Array, config: Dictionary, rng: RandomNumberGenerator, plan: Dictionary) -> void:
	var counts: Variant = config.get("monsters", {})
	if not counts is Dictionary:
		return
	var mouth := Regen.entrance_of(config)
	var fit := func(cell: Vector2i) -> bool:
		if map.cell(cell) != FLOOR or plan["track"].has(cell) or plan["levels"].has(cell) or _near_anchor(anchors, cell, 1):
			return false
		return mouth.is_empty() or not (mouth["rect"] as Rect2i).grow(MOUTH_CLEAR).has_point(cell)
	var left := {}
	for kind: Variant in counts:
		if map.colours.has("monster_" + str(kind)):
			left[str(kind)] = int(counts[kind])
	var lay := func(kind: String, cell: Vector2i) -> bool:
		if int(left.get(kind, 0)) <= 0 or not fit.call(cell):
			return false
		map.set_cell(cell, "monster_" + kind)
		left[kind] = int(left[kind]) - 1
		return true
	var first_of := func(kinds: Array) -> String:
		for kind: String in kinds:
			if int(left.get(kind, 0)) > 0:
				return kind
		for kind: String in left:
			if int(left[kind]) > 0:
				return kind
		return ""
	var routes := _routes(map, anchors, mouth)
	var on_route := {}
	for path: Array in routes:
		for cell: Vector2i in path:
			on_route[cell] = true
	# A guard before each chamber: on its route, GUARD_OUT cells out from it.
	for path: Array in routes:
		var kind: String = first_of.call(["imp"])
		for back in range(GUARD_OUT, path.size()):
			if kind.is_empty() or lay.call(kind, path[path.size() - 1 - back]):
				break
	# The brute in the bay nearest the route, an imp at its side.
	var bays: Array = (plan["bays"] as Array).duplicate()
	bays.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _gap(on_route, a["cells"]) < _gap(on_route, b["cells"]))
	if not bays.is_empty() and int(left.get("brute", 0)) > 0:
		var cells: Array[Vector2i] = []
		cells.assign(bays[0]["cells"])
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _gap(on_route, [a]) < _gap(on_route, [b]))
		for cell in cells:
			if lay.call("brute", cell):
				for d in DIRECTIONS:
					if lay.call("imp", cell + d):
						break
				break
	# Each sneak at the end of a gallery opening on the route.
	var ends: Array = []
	for pair: Array in _gallery_ends(plan["galleries"]):
		var near := _gap(on_route, [pair[0]]) <= _gap(on_route, [pair[1]])
		ends.append([pair[0] if near else pair[1], pair[1] if near else pair[0], mini(_gap(on_route, [pair[0]]), _gap(on_route, [pair[1]]))])
	ends.sort_custom(func(a: Array, b: Array) -> bool: return a[2] < b[2])
	for gallery: Array in ends:
		if int(left.get("sneak", 0)) <= 0 or gallery[2] > 3:
			break
		# Two cells in from its mouth: in the dark off the way, a lunge from it.
		var inward := Vector2(gallery[1] - gallery[0]).normalized()
		lay.call("sneak", gallery[0] + Vector2i(roundi(inward.x * 2.0), roundi(inward.y * 2.0)))
	# The rest along the route, apart.
	var route_cells: Array[Vector2i] = []
	for path: Array in routes:
		for cell: Vector2i in path:
			if not cell in route_cells:
				route_cells.append(cell)
	Tools.shuffle(route_cells, rng)
	var laid: Array[Vector2i] = []
	for y in map.size.y:
		for x in map.size.x:
			if map.cell(Vector2i(x, y)).begins_with("monster_"):
				laid.append(Vector2i(x, y))
	for cell in route_cells:
		var kind: String = first_of.call(["imp", "sneak", "brute"])
		if kind.is_empty():
			break
		if laid.any(func(other: Vector2i) -> bool: return Tools.distance(other, cell) < ROUTE_APART):
			continue
		if lay.call(kind, cell):
			laid.append(cell)
	var everywhere: Array[Vector2i] = []
	everywhere.assign(_floor_cells(map, anchors).filter(fit))
	Tools.shuffle(everywhere, rng)
	for cell in everywhere:
		var kind: String = first_of.call([])
		if kind.is_empty():
			break
		lay.call(kind, cell)


## The shortest walks (LevelMap.walkable, four ways) from the entrance's
## exits to each other anchor's, one [cell, ...] each, entrance first; an
## anchor that can't be reached has none.
static func _routes(map: LevelMap, anchors: Array, mouth: Dictionary) -> Array:
	if mouth.is_empty():
		return []
	var dist := {}
	var prev := {}
	var queue: Array[Vector2i] = []
	for cell in Level.rect_cells(mouth["rect"]):
		if map.walkable(cell):
			dist[cell] = 0
			prev[cell] = cell
			queue.append(cell)
	var at := 0
	while at < queue.size():
		var cell := queue[at]
		at += 1
		for d in DIRECTIONS:
			var next := cell + d
			if not dist.has(next) and map.walkable(next):
				dist[next] = int(dist[cell]) + 1
				prev[next] = cell
				queue.append(next)
	var out: Array = []
	for anchor: Dictionary in anchors:
		if anchor == mouth:
			continue
		var best := Vector2i(-1, -1)
		for cell in Level.rect_cells(anchor["rect"]):
			if dist.has(cell) and (best.x < 0 or int(dist[cell]) < int(dist[best])):
				best = cell
		if best.x < 0:
			continue
		var path: Array[Vector2i] = []
		var cell := best
		while prev[cell] != cell:
			cell = prev[cell]
			if not Level.in_anchors(anchors, cell):
				path.append(cell)
		path.reverse()
		out.append(path)
	return out


## Fewest steps (as the crow flies, Tools.distance) from any of [param cells]
## to the route.
static func _gap(route: Dictionary, cells: Array) -> int:
	var best := 1 << 20
	for cell: Vector2i in cells:
		if route.has(cell):
			return 0
		for other: Vector2i in route:
			best = mini(best, Tools.distance(cell, other))
	return best


## The galleries' two ends, [first, last] in cell order, each gallery's
## cells (plan's) a piece of its own.
static func _gallery_ends(galleries: Dictionary) -> Array:
	var out: Array = []
	var seen := {}
	for start: Vector2i in Tools.sorted_cells(galleries):
		if seen.has(start):
			continue
		var piece: Array[Vector2i] = [start]
		seen[start] = true
		var at := 0
		while at < piece.size():
			for d in DIRECTIONS:
				var next := piece[at] + d
				if galleries.has(next) and not seen.has(next):
					seen[next] = true
					piece.append(next)
			at += 1
		piece.sort()
		var a := piece[0]
		var b := piece[-1]
		out.append([a, b])
	return out


## 806 (Jeff: "no room should be empty"): a bay holding no monster, seam,
## cart or crate gets a seam cut into its wall, a working face.
static func _fill_bays(map: LevelMap, anchors: Array, rng: RandomNumberGenerator, plan: Dictionary) -> void:
	for bay: Dictionary in plan["bays"]:
		var held := false
		var walls: Array[Vector2i] = []
		for cell: Vector2i in bay["cells"]:
			var here := map.cell(cell)
			if here.begins_with("monster_") or here in ["cart", "crate", "boulder"]:
				held = true
				break
			for d in DIRECTIONS:
				var at := cell + d
				if map.cell(at) == "seam":
					held = true
				elif map.cell(at) == "void" and _diggable(map, anchors, at) and not _near_anchor(anchors, at, 3) 						and not plan["levels"].has(cell) and not plan["track"].has(cell) and not walls.has(at):
					walls.append(at)
			if held:
				break
		if held or walls.is_empty():
			continue
		var at := walls[rng.randi_range(0, walls.size() - 1)]
		map.set_cell(at, "seam")
		plan["carved"][at] = true


## Plain floor cells outside the anchors, in row order.
static func _floor_cells(map: LevelMap, anchors: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in map.size.y:
		for x in map.size.x:
			var cell := Vector2i(x, y)
			if map.cell(cell) == FLOOR and not Level.in_anchors(anchors, cell):
				out.append(cell)
	return out


static func _in_bay(plan: Dictionary, cell: Vector2i) -> bool:
	for bay: Dictionary in plan["bays"]:
		if (bay["rect"] as Rect2i).has_point(cell):
			return true
	return false


## Whether [param cell] lies within [param cells] (Chebyshev) of an anchor.
static func _near_anchor(anchors: Array, cell: Vector2i, cells: int) -> bool:
	for anchor: Dictionary in anchors:
		if (anchor["rect"] as Rect2i).grow(cells).has_point(cell):
			return true
	return false
