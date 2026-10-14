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
## every other it can walk to, at the real length of the walk, worked out
## once when the routes are made (steps_from: walls, doors (a group opens
## them), corners, ledges and stairs as World's steps have them, a diagonal
## costing DIAGONAL). Costs are in steps, so a group's speed turns them
## into time.
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
## Area name -> how long making its in-area lengths took, in milliseconds.
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


func _init(world_map: WorldMap) -> void:
	_areas = world_map.areas
	_ways = world_map.ways
	_graph.routes = weakref(self)
	for index in _ways.size():
		_add_way(index)
	for area_name: String in _in_area:
		var started := Time.get_ticks_usec()
		var ids: Array = _in_area[area_name]
		for from_id: int in ids:
			var targets: Array[Vector2i] = []
			for to_id: int in ids:
				if to_id != from_id:
					targets.append(_portals[to_id]["cell"])
			var lengths := steps_from(area_name, _portals[from_id]["cell"], targets)
			for to_id: int in ids:
				var cell: Vector2i = _portals[to_id]["cell"]
				if to_id != from_id and lengths.has(cell):
					_join(from_id, to_id, lengths[cell])
		build_ms[area_name] = (Time.get_ticks_usec() - started) / 1000.0


## The cheapest way from [param from_cell] in [param from_area] to
## [param to_cell] in [param to_area], as legs, one per area passed through:
## {area, from (cell), to (cell), steps, way (the way it leaves by,
## WorldMap.ways' entry; {} on the last leg)}. [] when there is none (no
## such area, a cell no floor reaches, or every way there blocked).
func route(from_area: String, from_cell: Vector2i, to_area: String, to_cell: Vector2i) -> Array[Dictionary]:
	var none: Array[Dictionary] = []
	if not _areas.has(from_area) or not _areas.has(to_area):
		return none
	var start := _graph.get_available_point_id()
	_graph.add_point(start, Vector2.ZERO)
	var finish := _graph.get_available_point_id()
	_graph.add_point(finish, Vector2.ZERO)
	_portals[start] = {"area": from_area, "cell": from_cell}
	_portals[finish] = {"area": to_area, "cell": to_cell}
	var targets: Array[Vector2i] = []
	for id: int in _in_area.get(from_area, []):
		targets.append(_portals[id]["cell"])
	if from_area == to_area:
		targets.append(to_cell)
	var lengths := steps_from(from_area, from_cell, targets)
	for id: int in _in_area.get(from_area, []):
		if lengths.has(_portals[id]["cell"]):
			_join(start, id, lengths[_portals[id]["cell"]])
	if from_area == to_area and lengths.has(to_cell):
		_join(start, finish, lengths[to_cell])
	# Walking is the same length either way, so the walk from each portal
	# to the end is the walk from the end to each portal.
	targets.clear()
	for id: int in _in_area.get(to_area, []):
		targets.append(_portals[id]["cell"])
	lengths = steps_from(to_area, to_cell, targets)
	for id: int in _in_area.get(to_area, []):
		if lengths.has(_portals[id]["cell"]):
			_join(id, finish, lengths[_portals[id]["cell"]])
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


## The length in steps of the shortest walk from [param from] to each of
## [param targets] in [param area_name] (the ones it can reach), walking as
## World does: floor only, no wall edge (doors open), no corner cut past a
## wall or void, no ledge (stairs climb one level), a diagonal costing
## DIAGONAL. Stops once every target is found.
func steps_from(area_name: String, from: Vector2i, targets: Array[Vector2i]) -> Dictionary[Vector2i, float]:
	var found: Dictionary[Vector2i, float] = {}
	var area: Dictionary = _areas[area_name]
	var floor_cells: Dictionary = area["floor"]
	if not floor_cells.has(from):
		return found
	var wanted := {}
	for cell in targets:
		wanted[cell] = true
	# Dijkstra by buckets: costs in half steps (2 straight, 3 diagonal).
	var best: Dictionary[Vector2i, int] = {from: 0}
	var buckets: Array[Array] = [[from]]
	var cost := 0
	var left := wanted.size()
	while cost < buckets.size() and left > 0:
		for cell: Vector2i in buckets[cost]:
			if best[cell] != cost:
				continue
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


func _relax(area: Dictionary, cell: Vector2i, direction: Vector2i, cost: int, best: Dictionary[Vector2i, int], buckets: Array[Array]) -> void:
	var to := cell + direction
	if best.get(to, 1 << 30) <= cost or not can_step(area, cell, direction):
		return
	best[to] = cost
	while buckets.size() <= cost:
		buckets.append([])
	buckets[cost].append(to)


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
## [param along] (the row, for east and west; the column, for north and
## south; -1 for the middle of the edge), or null if that edge has no floor.
func _edge_cell(area: Dictionary, side: String, along: int) -> Variant:
	var size: Vector2i = area["size"]
	var across := side in ["east", "west"]
	var length := size.y if across else size.x
	var fixed := 0
	match side:
		"east":
			fixed = size.x - 1
		"south":
			fixed = size.y - 1
	var aim := along if along >= 0 else (length - 1) / 2
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
