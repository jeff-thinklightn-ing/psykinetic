class_name WorldRoutes
extends RefCounted
## Routing between areas over the world map, for the world tick to move
## groups from one area to another without walking them cell by cell.
##
## The graph's points are portals, not areas: each way (WorldMap.ways) has
## an exit in its area (a link's marker cell; for an edge link, the floor
## cell on that edge nearest its middle) and an arrival in the next (the
## link's spawn point, or its first start; across an edge, the matching
## cell, WorldMap.arrival, or the nearest floor along that edge). An exit
## leads to its arrival only, at a cost of one step (a link is one way; the
## way back is a way of its own). Inside an area every portal is joined to
## every other it can walk to, at the real length of the walk (walls, doors
## (a group opens them), corners, ledges and stairs as World's steps have
## them, a diagonal costing DIAGONAL). Costs are in steps, so a group's
## speed turns them into time.
##
## Those lengths come from a distance field per portal (the steps from it to
## every cell of its area, a PackedFloat32Array by cell, -1 where it cannot
## walk), made on a WorkerThreadPool task when the routes are made, from
## copies of the areas taken then, so the task touches nothing else. Until
## an area's fields are in, a route through it walks the area there and then
## (slow on a big map: a quarter of a second for the wilds), so the world
## tick may rather wait for is_ready(). With the fields, a route's first and
## last legs are lookups too; only a route that stays inside one area still
## walks from its start to its end.
##
## [member blocked] and [member extra_cost] are asked of every way a route
## would take, each time one is found, so who holds a way can close or slow
## it later without the routes being made again.

## What a diagonal step costs (World.DIAGONAL_TICK_SCALE).
const DIAGONAL := 1.5
## What crossing a way costs, in steps.
const CROSSING := 1.0
## A blocked way's cost: a route over one is no route.
const BLOCKED := 1.0e9
const STRAIGHTS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const DIAGONALS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(1, -1)]

## (way: Dictionary) -> bool: true closes that way to every route. Unset:
## every way is open.
var blocked := Callable()
## (way: Dictionary) -> float: steps added to crossing that way. Unset: none.
var extra_cost := Callable()
## Area name -> how long making its distance fields took, in milliseconds
## (filled in as the task finishes each area; read it after is_ready).
var build_ms: Dictionary[String, float] = {}
## Ways the routes leave out, one line each: an edge with no floor along it,
## a link into an area or spawn point that is not there.
var gaps: Array[String] = []

## WorldMap's areas and ways (not the WorldMap, which holds these routes).
var _areas: Dictionary[String, Dictionary]
var _ways: Array[Dictionary]
var _graph := PortalGraph.new()
## Portal id -> {area, cell}.
var _portals: Dictionary[int, Dictionary] = {}
## "area x y" -> portal id.
var _portal_at: Dictionary[String, int] = {}
## Area name -> its portals' ids.
var _in_area: Dictionary[String, Array] = {}
## Vector2i(from id, to id) -> steps, inside an area.
var _costs: Dictionary[Vector2i, float] = {}
## Vector2i(exit id, arrival id) -> the index of its way in WorldMap.ways.
var _crossings: Dictionary[Vector2i, int] = {}
## Areas whose portals are joined to each other in the graph.
var _joined: Dictionary[String, bool] = {}
## Written by the task, under _mutex: portal id -> its distance field, and
## the areas whose fields are all in.
var _fields: Dictionary[int, PackedFloat32Array] = {}
var _ready: Dictionary[String, bool] = {}
var _mutex := Mutex.new()
var _task := -1
## Set when the routes are freed: the task stops at its next portal.
var _stopping := false


## The A* graph, its cost taken from the routes: per edge, not by distance
## (portals in different areas have no distance between them), and no
## estimate, so it finds the cheapest route.
class PortalGraph extends AStar2D:
	## The WorldRoutes it belongs to, weakly: it holds this graph.
	var routes: WeakRef

	func _compute_cost(from_id: int, to_id: int) -> float:
		return routes.get_ref()._cost(from_id, to_id)

	func _estimate_cost(_from_id: int, _to_id: int) -> float:
		return 0.0


## The routes over [param world_map]; its distance fields made on a
## WorkerThreadPool task, or, with [param threaded] false, here and now, or,
## with [param make_fields] false, never (every route walks: tests).
func _init(world_map: WorldMap, threaded := true, make_fields := true) -> void:
	_areas = world_map.areas
	_ways = world_map.ways
	_graph.routes = weakref(self)
	for index in _ways.size():
		_add_way(index)
	var job: Array[Dictionary] = []
	for area_name: String in _in_area:
		var area: Dictionary = _areas[area_name]
		var portals: Array[Array] = []
		for id: int in _in_area[area_name]:
			portals.append([id, _portals[id]["cell"]])
		job.append({"name": area_name, "portals": portals, "area": {"size": area["size"],
			"floor": area["floor"].duplicate(), "edges": area["edges"].duplicate(),
			"heights": area["heights"].duplicate(), "stairs": area["stairs"].duplicate()}})
	if job.is_empty() or not make_fields:
		return
	if threaded:
		_task = WorkerThreadPool.add_task(_make_fields.bind(job), false, "world routes: distance fields")
	else:
		_make_fields(job)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _task >= 0:
		_stopping = true
		WorkerThreadPool.wait_for_task_completion(_task)


## Whether every area's distance fields are in: from then on no route walks
## an area to find a way through it.
func is_ready() -> bool:
	_mutex.lock()
	var count := _ready.size()
	_mutex.unlock()
	return count == _in_area.size()


## Waits for the distance fields (tests and tools; the world tick asks
## is_ready instead).
func wait() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## The task: a distance field per portal, area by area, from the copies in
## [param job] only.
func _make_fields(job: Array[Dictionary]) -> void:
	for entry in job:
		var started := Time.get_ticks_usec()
		var area: Dictionary = entry["area"]
		var size: Vector2i = area["size"]
		var made: Dictionary[int, PackedFloat32Array] = {}
		for portal: Array in entry["portals"]:
			if _stopping:
				return
			var field := PackedFloat32Array()
			field.resize(size.x * size.y)
			field.fill(-1.0)
			_flood(area, portal[1], {}, field)
			made[portal[0]] = field
		_mutex.lock()
		_fields.merge(made)
		_ready[entry["name"]] = true
		build_ms[entry["name"]] = (Time.get_ticks_usec() - started) / 1000.0
		_mutex.unlock()


## The cheapest way from [param from_cell] in [param from_area] to
## [param to_cell] in [param to_area], as legs, one per area passed through:
## {area, from (cell), to (cell), steps, way (the way it leaves by,
## WorldMap.ways' entry; {} on the last leg)}. [] when there is none (no
## such area, a cell no floor reaches, or every way there blocked).
func route(from_area: String, from_cell: Vector2i, to_area: String, to_cell: Vector2i) -> Array[Dictionary]:
	var none: Array[Dictionary] = []
	if not _areas.has(from_area) or not _areas.has(to_area):
		return none
	for area_name in _areas_from(from_area):
		_join_area(area_name)
	var start := _graph.get_available_point_id()
	_graph.add_point(start, Vector2.ZERO)
	var finish := _graph.get_available_point_id()
	_graph.add_point(finish, Vector2.ZERO)
	_portals[start] = {"area": from_area, "cell": from_cell}
	_portals[finish] = {"area": to_area, "cell": to_cell}
	# Walking is the same length either way, so the walk from each portal
	# to the end is the walk from the end to each portal.
	var lengths := _to_portals(from_area, from_cell)
	for id: int in lengths:
		_join(start, id, lengths[id])
	lengths = _to_portals(to_area, to_cell)
	for id: int in lengths:
		_join(id, finish, lengths[id])
	if from_area == to_area:
		var direct := steps_from(from_area, from_cell, [to_cell] as Array[Vector2i])
		if direct.has(to_cell):
			_join(start, finish, direct[to_cell])
	var path := _graph.get_id_path(start, finish)
	var legs: Array[Dictionary] = []
	var total := 0.0
	if not path.is_empty():
		var leg := {"area": from_area, "from": from_cell, "steps": 0.0}
		for i in range(1, path.size()):
			var step := _cost(path[i - 1], path[i])
			total += step
			var key := Vector2i(path[i - 1], path[i])
			if _crossings.has(key):
				leg["to"] = _portals[path[i - 1]]["cell"]
				leg["way"] = _ways[_crossings[key]]
				legs.append(leg)
				leg = {"area": _portals[path[i]]["area"], "from": _portals[path[i]]["cell"], "steps": 0.0}
			else:
				leg["steps"] += step
		leg["to"] = to_cell
		leg["way"] = {}
		legs.append(leg)
	for id in [start, finish]:
		_graph.remove_point(id)
		_portals.erase(id)
	for key: Vector2i in _costs.keys():
		if key.x == start or key.y == start or key.x == finish or key.y == finish:
			_costs.erase(key)
	return legs if total < BLOCKED else none


## Where a group is after covering [param cells] steps of [param legs] (a
## route): {area, cell, leg (its index), done (at the end)}; {} for no
## route. Crossing a way takes CROSSING steps; a group partway through one
## is where it arrives. The cell is on a shortest walk where the distance
## fields have it (a leg from or to a portal whose fields are in); otherwise
## it is the floor cell nearest the straight line's point, which is coarse.
func along(legs: Array[Dictionary], cells: float) -> Dictionary:
	if legs.is_empty():
		return {}
	var left := cells
	for index in legs.size():
		var leg: Dictionary = legs[index]
		var steps: float = leg["steps"]
		if left < steps:
			return {"area": leg["area"], "cell": _cell_along(leg, maxf(left, 0.0)), "leg": index, "done": false}
		left -= steps
		if index + 1 < legs.size():
			left -= CROSSING
			if left < 0.0:
				var next: Dictionary = legs[index + 1]
				return {"area": next["area"], "cell": next["from"], "leg": index + 1, "done": false}
	var last: Dictionary = legs[-1]
	return {"area": last["area"], "cell": last["to"], "leg": legs.size() - 1, "done": true}


## The length in steps of the shortest walk from [param from] to each of
## [param targets] in [param area_name] (the ones it can reach), walking as
## World does: floor only, no wall edge (doors open), no corner cut past a
## wall or void, no ledge (stairs climb one level), a diagonal costing
## DIAGONAL. Stops once every target is found.
func steps_from(area_name: String, from: Vector2i, targets: Array[Vector2i]) -> Dictionary[Vector2i, float]:
	var wanted := {}
	for cell in targets:
		wanted[cell] = true
	return _flood(_areas[area_name], from, wanted, PackedFloat32Array())


## Dijkstra by buckets over [param area] from [param from], costs in half
## steps (2 straight, 3 diagonal). Returns the steps to each cell of
## [param wanted] it reaches, stopping once it has them all, unless
## [param field] (one float per cell, by y * width + x) is to be filled, in
## which case it walks the whole area and writes every cell's steps there.
static func _flood(area: Dictionary, from: Vector2i, wanted: Dictionary, field: PackedFloat32Array) -> Dictionary[Vector2i, float]:
	var found: Dictionary[Vector2i, float] = {}
	var floor_cells: Dictionary = area["floor"]
	if not floor_cells.has(from):
		return found
	var width: int = area["size"].x
	var filling := not field.is_empty()
	var best: Dictionary[Vector2i, int] = {from: 0}
	var buckets: Array[Array] = [[from]]
	var cost := 0
	var left := wanted.size()
	while cost < buckets.size() and (left > 0 or filling):
		for cell: Vector2i in buckets[cost]:
			if best[cell] != cost:
				continue
			if filling:
				field[cell.y * width + cell.x] = cost / 2.0
			if wanted.has(cell) and not found.has(cell):
				found[cell] = cost / 2.0
				left -= 1
			for direction in STRAIGHTS:
				_relax(area, cell, direction, cost + 2, best, buckets)
			for direction in DIAGONALS:
				_relax(area, cell, direction, cost + 3, best, buckets)
		buckets[cost] = []
		cost += 1
	return found


static func _relax(area: Dictionary, cell: Vector2i, direction: Vector2i, cost: int, best: Dictionary[Vector2i, int], buckets: Array[Array]) -> void:
	var to := cell + direction
	if best.get(to, 1 << 30) <= cost or not can_step(area, cell, direction):
		return
	best[to] = cost
	while buckets.size() <= cost:
		buckets.append([])
	buckets[cost].append(to)


# --- Using the fields ----------------------------------------------------------------

## [param id]'s distance field, or an empty one if it is not in yet.
func _field(id: int) -> PackedFloat32Array:
	_mutex.lock()
	var field: PackedFloat32Array = _fields.get(id, PackedFloat32Array())
	_mutex.unlock()
	return field


func _area_ready(area_name: String) -> bool:
	_mutex.lock()
	var ready: bool = _ready.has(area_name)
	_mutex.unlock()
	return ready


## [param field]'s steps at [param cell] of [param area_name]; -1 if it
## cannot walk there.
func _at(field: PackedFloat32Array, area_name: String, cell: Vector2i) -> float:
	var size: Vector2i = _areas[area_name]["size"]
	if field.is_empty() or not Rect2i(Vector2i.ZERO, size).has_point(cell):
		return -1.0
	return field[cell.y * size.x + cell.x]


## The steps from [param cell] to each portal of [param area_name] it can
## walk to (portal id -> steps): from the fields, or by walking the area.
func _to_portals(area_name: String, cell: Vector2i) -> Dictionary[int, float]:
	var out: Dictionary[int, float] = {}
	var ids: Array = _in_area.get(area_name, [])
	if _area_ready(area_name):
		for id: int in ids:
			var steps := _at(_field(id), area_name, cell)
			if steps >= 0.0:
				out[id] = steps
		return out
	var targets: Array[Vector2i] = []
	for id: int in ids:
		targets.append(_portals[id]["cell"])
	var lengths := steps_from(area_name, cell, targets)
	for id: int in ids:
		if lengths.has(_portals[id]["cell"]):
			out[id] = lengths[_portals[id]["cell"]]
	return out


## Joins [param area_name]'s portals to each other in the graph, once.
func _join_area(area_name: String) -> void:
	if _joined.has(area_name) or not _in_area.has(area_name):
		return
	var started := Time.get_ticks_usec()
	for from_id: int in _in_area[area_name]:
		var lengths := _to_portals(area_name, _portals[from_id]["cell"])
		for to_id: int in lengths:
			if to_id != from_id:
				_join(from_id, to_id, lengths[to_id])
	_joined[area_name] = true
	var ms := (Time.get_ticks_usec() - started) / 1000.0
	if ms > 50.0:
		print("[routes] %s walked for its routes in %.0f ms (its distance fields were not in yet)" % [area_name, ms])


## The areas [param from] leads to, itself included.
func _areas_from(from: String) -> Array[String]:
	var seen: Array[String] = [from]
	var next := 0
	while next < seen.size():
		var here := seen[next]
		next += 1
		for way: Dictionary in _ways:
			if way["from"] == here and _areas.has(way["to"]) and way["to"] not in seen:
				seen.append(way["to"])
	return seen


## The cell [param covered] steps along [param leg]: down the field of the
## portal it leaves by (towards it), or down the field of the portal it
## started at (back from its end), whichever is in; else the floor cell
## nearest the straight line's point.
func _cell_along(leg: Dictionary, covered: float) -> Vector2i:
	var area_name: String = leg["area"]
	var area: Dictionary = _areas[area_name]
	var from: Vector2i = leg["from"]
	var to: Vector2i = leg["to"]
	var exit := _field(_portal_at.get("%s %d %d" % [area_name, to.x, to.y], -1))
	if _at(exit, area_name, from) >= 0.0:
		# Towards the exit: down its field until covered steps are spent.
		return _descend(area, exit, from, _at(exit, area_name, from) - covered)
	var entry := _field(_portal_at.get("%s %d %d" % [area_name, from.x, from.y], -1))
	if _at(entry, area_name, to) >= 0.0:
		# Back from the end, down the entry's field to covered steps from it.
		return _descend(area, entry, to, covered)
	var point := Vector2(from).lerp(Vector2(to), covered / maxf(leg["steps"], 0.001)).round()
	return _nearest_floor(area, Vector2i(point), from)


## From [param cell], step down [param field] (each step to a cell one
## real step nearer its portal) until the field is at most [param down_to].
func _descend(area: Dictionary, field: PackedFloat32Array, cell: Vector2i, down_to: float) -> Vector2i:
	var size: Vector2i = area["size"]
	var here := cell
	while field[here.y * size.x + here.x] > down_to + 0.001:
		var value := field[here.y * size.x + here.x]
		var moved := false
		for direction in STRAIGHTS + DIAGONALS:
			var next := here + direction
			if not Rect2i(Vector2i.ZERO, size).has_point(next):
				continue
			var step := DIAGONAL if direction.x != 0 and direction.y != 0 else 1.0
			var there := field[next.y * size.x + next.x]
			if there >= 0.0 and absf(there + step - value) < 0.001 and can_step(area, here, direction):
				here = next
				moved = true
				break
		if not moved:
			break
	return here


## The floor cell nearest [param cell] (within 8), or [param fallback].
static func _nearest_floor(area: Dictionary, cell: Vector2i, fallback: Vector2i) -> Vector2i:
	var floor_cells: Dictionary = area["floor"]
	for radius in 9:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) == radius and floor_cells.has(cell + Vector2i(dx, dy)):
					return cell + Vector2i(dx, dy)
	return fallback


## Whether a group can step from [param from] by [param direction] in an
## area of WorldMap.areas: World._terrain_blocks_step's rules, doors open.
static func can_step(area: Dictionary, from: Vector2i, direction: Vector2i) -> bool:
	var floor_cells: Dictionary = area["floor"]
	if not floor_cells.has(from + direction) or _height_step(area, from, direction) != 0:
		return false
	if direction.x == 0 or direction.y == 0:
		return not _wall(area, from, direction)
	var via_x := Vector2i(direction.x, 0)
	var via_y := Vector2i(0, direction.y)
	if not floor_cells.has(from + via_x) or not floor_cells.has(from + via_y):
		return false
	return not (_wall(area, from, via_x) or _wall(area, from + via_x, via_y)
			or _wall(area, from, via_y) or _wall(area, from + via_y, via_x))


static func _wall(area: Dictionary, from: Vector2i, direction: Vector2i) -> bool:
	return area["edges"].get(Terrain.edge_key(from, direction), Terrain.Edge.OPEN) == Terrain.Edge.WALL


## World.height_step on an area: 0 for a step that is level (or a stair).
static func _height_step(area: Dictionary, from: Vector2i, direction: Vector2i) -> int:
	var heights: Dictionary = area["heights"]
	var stairs: Dictionary = area["stairs"]
	var here: int = heights.get(from, 0)
	var to := from + direction
	var rise: int = heights.get(to, 0) - here
	if direction.x != 0 and direction.y != 0:
		if rise == 0 and heights.get(from + Vector2i(direction.x, 0), 0) == here \
				and heights.get(from + Vector2i(0, direction.y), 0) == here:
			return 0
		return -rise if rise != 0 else -1
	if rise == 0:
		return 0
	if rise == 1 and stairs.get(from, Vector2i.ZERO) == direction:
		return 0
	if rise == -1 and stairs.get(to, Vector2i.ZERO) == -direction:
		return 0
	return -rise


# --- Building ------------------------------------------------------------------------

func _add_way(index: int) -> void:
	var way: Dictionary = _ways[index]
	var from: String = way["from"]
	var to: String = way["to"]
	var what := "%s's %s" % [from, "link at %s" % way["at"] if way["kind"] == "link" else "%s neighbour" % way["side"]]
	if not _areas.has(to):
		gaps.append("%s: %s is no level" % [what, to])
		return
	var target: Dictionary = _areas[to]
	var exit: Variant = null
	var arrival: Variant = null
	if way["kind"] == "link":
		exit = way["at"]
		var to_spawn: String = way["to_spawn"]
		if to_spawn.is_empty():
			arrival = target["starts"][0] if not target["starts"].is_empty() else null
		else:
			arrival = target["spawn_points"].get(to_spawn)
	else:
		var side: String = way["side"]
		exit = _edge_cell(_areas[from], side, -1)
		if exit != null:
			var landing := WorldMap.arrival(side, exit + Level.SIDES[side], target["size"])
			arrival = _edge_cell(target, Level.OPPOSITE[side], landing.y if side in ["east", "west"] else landing.x)
	if exit == null or arrival == null:
		gaps.append("%s: no floor to %s by it" % [what, "leave" if exit == null else "arrive"])
		return
	var exit_id := _portal(from, exit)
	var arrival_id := _portal(to, arrival)
	_graph.connect_points(exit_id, arrival_id, false)
	_crossings[Vector2i(exit_id, arrival_id)] = index


## The floor cell on [param side]'s edge of [param area] nearest
## [param near] (the row, for east and west; the column, for north and
## south; -1 for the middle of the edge), or null if that edge has no floor.
func _edge_cell(area: Dictionary, side: String, near: int) -> Variant:
	var size: Vector2i = area["size"]
	var across := side in ["east", "west"]
	var length := size.y if across else size.x
	var fixed := 0
	match side:
		"east":
			fixed = size.x - 1
		"south":
			fixed = size.y - 1
	var aim := near if near >= 0 else (length - 1) / 2
	var floor_cells: Dictionary = area["floor"]
	for offset in length:
		for at in [aim - offset, aim + offset]:
			if at < 0 or at >= length:
				continue
			var cell := Vector2i(fixed, at) if across else Vector2i(at, fixed)
			if floor_cells.has(cell):
				return cell
	return null


func _portal(area_name: String, cell: Vector2i) -> int:
	var key := "%s %d %d" % [area_name, cell.x, cell.y]
	if _portal_at.has(key):
		return _portal_at[key]
	var id := _graph.get_available_point_id()
	_graph.add_point(id, Vector2.ZERO)
	_portals[id] = {"area": area_name, "cell": cell}
	_portal_at[key] = id
	if not _in_area.has(area_name):
		_in_area[area_name] = []
	_in_area[area_name].append(id)
	return id


func _join(from_id: int, to_id: int, steps: float) -> void:
	_costs[Vector2i(from_id, to_id)] = steps
	_graph.connect_points(from_id, to_id, false)


func _cost(from_id: int, to_id: int) -> float:
	var key := Vector2i(from_id, to_id)
	if _crossings.has(key):
		var way: Dictionary = _ways[_crossings[key]]
		if blocked.is_valid() and blocked.call(way):
			return BLOCKED
		return CROSSING + (float(extra_cost.call(way)) if extra_cost.is_valid() else 0.0)
	return _costs.get(key, BLOCKED)
