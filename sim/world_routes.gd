class_name WorldRoutes
extends RefCounted
## Routing between areas over the world map, for the world tick to move
## groups from one area to another along real walks.
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
## Held ground is physical (Holdings, decision 206): a group may not walk
## through cells another faction holds. So the routes are kept in layers,
## one per faction that moves (its obstacles: the cells it may not walk,
## each naming the place that holds it) and one with none (""). Each layer
## has its own graph (the crossings are the same; a crossing whose exit or
## arrival is in held ground is closed to it) and its own distance fields.
##
## A distance field is a portal's steps to every cell of its area, a
## PackedFloat32Array by cell (-1 where it cannot walk), made on a
## WorkerThreadPool task from copies of the areas and of that layer's
## obstacles, so the task touches nothing else. When a layer's obstacles in
## an area change (a place taken), that area's fields are made again on the
## pool; until they are in, a route through it walks the area there and
## then (correct, slow on a big map), so the world tick may rather wait for
## is_ready(). With the fields, a route's first and last legs are lookups;
## a route inside one area still walks from its start to its end.
##
## [member blocked] is asked of every way a route would take, each time one
## is found, so a closed gate can shut a way without the routes being made
## again.

## What a diagonal step costs (World.DIAGONAL_TICK_SCALE).
const DIAGONAL := 1.5
## What crossing a way costs, in steps.
const CROSSING := 1.0
## A step into a ford costs this many times a dry one (decision 505;
## World.FORD_TICK_SCALE).
const FORD_COST := 2
## A blocked way's cost: a route over one is no route.
const BLOCKED := 1.0e9
const STRAIGHTS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const DIAGONALS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(1, -1)]
## The layer with no obstacles.
const OPEN := ""

## (way: Dictionary, faction: String) -> bool: true closes that way to that
## faction's routes (faction "" for a route with no faction). Unset: every
## way is open.
var blocked := Callable()
## "<faction> <area>" -> how long making that layer's distance fields there
## took, in milliseconds (faction "" for the open layer), as tasks finish.
var build_ms: Dictionary[String, float] = {}
## Ways the routes leave out, one line each: an edge with no floor along it,
## a link into an area or spawn point that is not there.
var gaps: Array[String] = []

## WorldMap's areas and ways (not the WorldMap, which holds these routes).
var _areas: Dictionary[String, Dictionary]
var _ways: Array[Dictionary]
## Area name -> a copy of what walking it needs, for the tasks (never changed).
var _copies: Dictionary[String, Dictionary] = {}
## Faction ("" for none) -> its Layer.
var _layers: Dictionary[String, Layer] = {}
## Portal id -> {area, cell}.
var _portals: Dictionary[int, Dictionary] = {}
## "area x y" -> portal id.
var _portal_at: Dictionary[String, int] = {}
## Area name -> its portals' ids.
var _in_area: Dictionary[String, Array] = {}
## Vector2i(exit id, arrival id) -> the index of its way in WorldMap.ways.
var _crossings: Dictionary[Vector2i, int] = {}
var _mutex := Mutex.new()
var _tasks: Array[int] = []
var _threaded := true
var _make_fields := true
## Set when the routes are freed: the tasks stop at their next portal.
var _stopping := false


## One faction's routes: its graph, its obstacles, its fields.
class Layer:
	var faction := ""
	var graph := PortalGraph.new()
	## Vector2i(from id, to id) -> steps, inside an area.
	var costs: Dictionary[Vector2i, float] = {}
	## Areas whose portals are joined to each other in the graph.
	var joined: Dictionary[String, bool] = {}
	## Area name -> {cell: the place holding it}: what this faction may not walk.
	var obstacles: Dictionary[String, Dictionary] = {}
	## Under the routes' mutex: area -> its obstacles' version, and the
	## version its fields are in for (missing: none in yet); portal id -> field.
	var version: Dictionary[String, int] = {}
	var ready: Dictionary[String, int] = {}
	var fields: Dictionary[int, PackedFloat32Array] = {}


## The A* graph, its cost taken from the routes: per edge, not by distance
## (portals in different areas have no distance between them), and no
## estimate, so it finds the cheapest route.
class PortalGraph extends AStar2D:
	## The WorldRoutes it belongs to, weakly: it holds this graph.
	var routes: WeakRef
	var faction := ""

	func _compute_cost(from_id: int, to_id: int) -> float:
		return routes.get_ref()._cost(faction, from_id, to_id)

	func _estimate_cost(_from_id: int, _to_id: int) -> float:
		return 0.0


## The routes over [param world_map], with a layer for each faction in
## [param obstacles] (faction -> area -> {cell: place id}, Holdings.obstacles)
## besides the open one. Their distance fields are made on WorkerThreadPool
## tasks, or, with [param threaded] false, here and now, or, with
## [param make_fields] false, never (every route walks: tests).
func _init(world_map: WorldMap, threaded := true, make_fields := true, obstacles := {}) -> void:
	_areas = world_map.areas
	_ways = world_map.ways
	_threaded = threaded
	_make_fields = make_fields
	for faction: String in [OPEN] + obstacles.keys():
		var layer := Layer.new()
		layer.faction = faction
		layer.graph.routes = weakref(self)
		layer.graph.faction = faction
		_layers[faction] = layer
	for index in _ways.size():
		if not _ways[index].get("closed", false):  # No way through a closed link (decision 463).
			_add_way(index)
	for area_name: String in _in_area:
		var area: Dictionary = _areas[area_name]
		_copies[area_name] = {"size": area["size"], "floor": area["floor"].duplicate(), "edges": area["edges"].duplicate(),
			"heights": area["heights"].duplicate(), "stairs": area["stairs"].duplicate()}
	var job: Array[Dictionary] = []
	for faction: String in _layers:
		var layer := _layers[faction]
		var given: Dictionary = obstacles.get(faction, {})
		for area_name: String in _in_area:
			layer.obstacles[area_name] = (given.get(area_name, {}) as Dictionary).duplicate()
			layer.version[area_name] = 0
			job.append(_job(layer, area_name))
	_start(job)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_stopping = true
		for task in _tasks:
			WorkerThreadPool.wait_for_task_completion(task)


## The factions with a layer of their own.
func factions() -> Array[String]:
	var out: Array[String] = []
	for faction: String in _layers:
		if faction != OPEN:
			out.append(faction)
	return out


## Sets what [param faction] may not walk in [param area_name]
## ({cell: place id}). If that changes it, the area's fields for that layer
## are made again on the pool, and its routes there walk until they are in.
func set_obstacles(faction: String, area_name: String, cells: Dictionary) -> void:
	var layer: Layer = _layers.get(faction)
	if layer == null or not _in_area.has(area_name) or layer.obstacles.get(area_name, {}) == cells:
		return
	layer.obstacles[area_name] = cells.duplicate()
	_mutex.lock()
	layer.version[area_name] = layer.version.get(area_name, 0) + 1
	_mutex.unlock()
	_unjoin(layer, area_name)
	_start([_job(layer, area_name)])


## Whether every layer's distance fields are in for every area (only
## [param faction]'s layer, if given): from then on no route walks an area
## to find a way through it.
func is_ready(faction: Variant = null) -> bool:
	_reap()
	for each: String in _layers:
		if faction != null and each != faction:
			continue
		for area_name: String in _in_area:
			if not _area_ready(_layers[each], area_name):
				return false
	return true


## Waits for every distance field being made (tests and tools; the world
## tick asks is_ready instead).
func wait() -> void:
	for task in _tasks:
		WorkerThreadPool.wait_for_task_completion(task)
	_tasks.clear()


func _job(layer: Layer, area_name: String) -> Dictionary:
	var portals: Array[Array] = []
	for id: int in _in_area[area_name]:
		portals.append([id, _portals[id]["cell"]])
	return {"layer": layer, "name": area_name, "version": layer.version[area_name], "portals": portals,
		"area": _copies[area_name], "obstacles": layer.obstacles[area_name].duplicate()}


func _start(job: Array[Dictionary]) -> void:
	if job.is_empty() or not _make_fields:
		return
	_reap()
	if _threaded:
		_tasks.append(WorkerThreadPool.add_task(_make.bind(job), false, "world routes: distance fields"))
	else:
		_make(job)


## Lets go of the tasks that are done.
func _reap() -> void:
	for task in _tasks.duplicate():
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
			_tasks.erase(task)


## A task: a distance field per portal, area by area, from the copies in
## [param job] only. An area whose obstacles changed meanwhile is dropped
## (a newer task makes it).
func _make(job: Array[Dictionary]) -> void:
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
			_flood(area, portal[1], {}, field, entry["obstacles"])
			made[portal[0]] = field
		var layer: Layer = entry["layer"]
		_mutex.lock()
		if layer.version.get(entry["name"], 0) == entry["version"]:
			layer.fields.merge(made, true)
			layer.ready[entry["name"]] = entry["version"]
			build_ms["%s %s" % [layer.faction, entry["name"]]] = (Time.get_ticks_usec() - started) / 1000.0
		_mutex.unlock()


# --- Routes --------------------------------------------------------------------------

## The cheapest way from [param from_cell] in [param from_area] to
## [param to_cell] in [param to_area] for a group of [param faction] ("" for
## none: held ground stops nothing), as legs, one per area passed through:
## {area, from (cell), to (cell), steps, way (the way it leaves by,
## WorldMap.ways' entry; {} on the last leg)}.
##
## Held ground another faction holds is not walked: the route goes round it.
## If there is no way round, it is the cheapest route ignoring held ground,
## cut off at its first held cell: its last leg ends on the open cell before
## it and carries "meets", the id of the place holding that ground, for the
## world tick to make the encounter. A goal in held ground is reached the
## same way (to its edge, with "meets"); a group standing in held ground
## gets one leg going nowhere, with "meets". No last leg with "meets" means
## it gets there. [] when there is no route at all (no such area, a cell no
## floor reaches, a one-way dead end, every way blocked).
func route(from_area: String, from_cell: Vector2i, to_area: String, to_cell: Vector2i, faction := OPEN) -> Array[Dictionary]:
	var none: Array[Dictionary] = []
	if not _areas.has(from_area) or not _areas.has(to_area):
		return none
	var layer: Layer = _layers.get(faction)
	if layer == null:
		push_warning("[routes] no layer for %s: its route ignores held ground" % faction)
		layer = _layers[OPEN]
	var held: Variant = _held(layer, from_area, from_cell)
	if held != null:
		var stay: Array[Dictionary] = [{"area": from_area, "from": from_cell, "to": from_cell, "steps": 0.0, "way": {}, "meets": held}]
		return stay
	var legs := _route_in(layer, from_area, from_cell, to_area, to_cell)
	if not legs.is_empty() or layer.faction == OPEN:
		return legs
	return _cut_at_held(layer, from_area, from_cell, _route_in(_layers[OPEN], from_area, from_cell, to_area, to_cell))


## Where a group is after covering [param cells] steps of [param legs] (a
## route for [param faction]): {area, cell, leg (its index), done (at the
## end; at the edge of held ground, if the route meets it)}; {} for no
## route. Crossing a way takes CROSSING steps; a group partway through one
## is where it arrives. The cell is on a shortest walk where that layer's
## distance fields have it (a leg from or to a portal whose fields are in);
## otherwise it is the floor cell nearest the straight line's point.
func along(legs: Array[Dictionary], cells: float, faction := OPEN) -> Dictionary:
	if legs.is_empty():
		return {}
	var layer: Layer = _layers.get(faction, _layers[OPEN])
	var left := cells
	for index in legs.size():
		var leg: Dictionary = legs[index]
		var steps: float = leg["steps"]
		if left < steps:
			return {"area": leg["area"], "cell": _cell_along(layer, leg, maxf(left, 0.0)), "leg": index, "done": false}
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
## DIAGONAL; for [param faction], not through ground another faction holds.
## Stops once every target is found.
func steps_from(area_name: String, from: Vector2i, targets: Array[Vector2i], faction := OPEN) -> Dictionary[Vector2i, float]:
	var wanted := {}
	for cell in targets:
		wanted[cell] = true
	var layer: Layer = _layers.get(faction, _layers[OPEN])
	return _flood(_areas[area_name], from, wanted, PackedFloat32Array(), layer.obstacles.get(area_name, {}))


## Walking steps from the nearest of [param starts] ({area, cell}) to every
## cell of every area it reaches, across the ways (each CROSSING steps),
## held ground walked and no way blocked: area name -> PackedFloat32Array
## by cell (-1 where none reaches). For thinning by distance from a place
## (WorldRichness, decision 368). Reads only what never changes after the
## routes are made, so a WorkerThreadPool task may call it.
func distances_from(starts: Array[Dictionary]) -> Dictionary[String, PackedFloat32Array]:
	# Area -> exit cell -> [[area, arrival cell], ...].
	var leads: Dictionary[String, Dictionary] = {}
	for key: Vector2i in _crossings:
		var exit: Dictionary = _portals[key.x]
		var arrival: Dictionary = _portals[key.y]
		var from_area: Dictionary = leads.get_or_add(exit["area"], {})
		(from_area.get_or_add(exit["cell"], []) as Array).append([arrival["area"], arrival["cell"]])
	# Costs in half steps: a straight step 2, a diagonal 3, a crossing 2.
	# Area -> half steps by cell (an Array, not a packed one: written in
	# place, never copied).
	var best: Dictionary[String, Array] = {}
	var buckets: Array[Array] = [[]]
	for start: Dictionary in starts:
		_reach(str(start["area"]), start["cell"], 0, best, buckets)
	var cost := 0
	while cost < buckets.size():
		for entry: Array in buckets[cost]:
			var area_name: String = entry[0]
			var cell: Vector2i = entry[1]
			var area: Dictionary = _areas[area_name]
			if best[area_name][cell.y * area["size"].x + cell.x] != cost:
				continue
			for direction in STRAIGHTS:
				if can_step(area, cell, direction):
					_reach(area_name, cell + direction, cost + step_cost(area, cell + direction, 2), best, buckets)
			for direction in DIAGONALS:
				if can_step(area, cell, direction):
					_reach(area_name, cell + direction, cost + step_cost(area, cell + direction, 3), best, buckets)
			for lead: Array in leads.get(area_name, {}).get(cell, []):
				_reach(lead[0], lead[1], cost + roundi(CROSSING * 2.0), best, buckets)
		buckets[cost] = []
		cost += 1
	var out: Dictionary[String, PackedFloat32Array] = {}
	for area_name: String in best:
		var halves: Array = best[area_name]
		var steps := PackedFloat32Array()
		steps.resize(halves.size())
		for i in halves.size():
			steps[i] = halves[i] / 2.0 if halves[i] < 1 << 30 else -1.0
		out[area_name] = steps
	return out


func _reach(area_name: String, cell: Vector2i, cost: int, best: Dictionary[String, Array], buckets: Array[Array]) -> void:
	var area: Dictionary = _areas.get(area_name, {})
	if area.is_empty() or not area["floor"].has(cell):
		return
	var size: Vector2i = area["size"]
	if not best.has(area_name):
		var fresh := []
		fresh.resize(size.x * size.y)
		fresh.fill(1 << 30)
		best[area_name] = fresh
	var halves: Array = best[area_name]
	var index := cell.y * size.x + cell.x
	if halves[index] <= cost:
		return
	halves[index] = cost
	while buckets.size() <= cost:
		buckets.append([])
	buckets[cost].append([area_name, cell])


## The cheapest route in [param layer], ignoring nothing; [] if none.
func _route_in(layer: Layer, from_area: String, from_cell: Vector2i, to_area: String, to_cell: Vector2i) -> Array[Dictionary]:
	var none: Array[Dictionary] = []
	var reached := _areas_from(from_area)
	if to_area not in reached:
		return none  # No way there at all: nothing walked (decision 503).
	if from_area == to_area and not _area_ready(layer, from_area):
		# Until its fields are in, a walk inside one area is its walk there
		# alone, not every portal's walked to as well (seconds on the wilds).
		var steps := _steps_between(_areas[from_area], from_cell, to_cell, layer.obstacles.get(from_area, {}))
		if steps < 0.0:
			return none
		var alone: Array[Dictionary] = [{"area": from_area, "from": from_cell, "to": to_cell, "steps": steps, "way": {}}]
		return alone
	for area_name in reached:
		_join_area(layer, area_name)
	var graph := layer.graph
	var start := graph.get_available_point_id()
	graph.add_point(start, Vector2.ZERO)
	var finish := graph.get_available_point_id()
	graph.add_point(finish, Vector2.ZERO)
	_portals[start] = {"area": from_area, "cell": from_cell}
	_portals[finish] = {"area": to_area, "cell": to_cell}
	# Walking is the same length either way, so the walk from each portal
	# to the end is the walk from the end to each portal.
	var lengths := _to_portals(layer, from_area, from_cell)
	for id: int in lengths:
		_join(layer, start, id, lengths[id])
	lengths = _to_portals(layer, to_area, to_cell)
	for id: int in lengths:
		_join(layer, id, finish, lengths[id])
	if from_area == to_area:
		var direct := _steps_between(_areas[from_area], from_cell, to_cell, layer.obstacles.get(from_area, {}))
		if direct >= 0.0:
			_join(layer, start, finish, direct)
	var path := graph.get_id_path(start, finish)
	var legs: Array[Dictionary] = []
	var total := 0.0
	if not path.is_empty():
		var leg := {"area": from_area, "from": from_cell, "steps": 0.0}
		for i in range(1, path.size()):
			var step := _cost(layer.faction, path[i - 1], path[i])
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
		graph.remove_point(id)
		_portals.erase(id)
	for key: Vector2i in layer.costs.keys():
		if key.x == start or key.y == start or key.x == finish or key.y == finish:
			layer.costs.erase(key)
	return legs if total < BLOCKED else none


## Where [param layer]'s faction meets held ground it cannot get round, on
## its way along [param legs] (the open route from [param from_area]'s
## [param from_cell]): held ground on that route it can get round (it can
## still reach the open cell past it) is passed; at the first it cannot, the
## faction's own route to the open cell before it, its last leg ending there
## with "meets" (the place holding it). [] if none stops it (what closed
## its way was not held ground: a blocked way).
func _cut_at_held(layer: Layer, from_area: String, from_cell: Vector2i, legs: Array[Dictionary]) -> Array[Dictionary]:
	var none: Array[Dictionary] = []
	# The open route cell by cell, [area, cell], crossings included.
	var walk: Array[Array] = []
	for leg in legs:
		for cell in _walk_cells(_layers[OPEN], leg):
			walk.append([leg["area"], cell])
	var i := 1
	while i < walk.size():
		var held: Variant = _held(layer, walk[i][0], walk[i][1])
		if held == null:
			i += 1
			continue
		var past := i
		while past < walk.size() and _held(layer, walk[past][0], walk[past][1]) != null:
			past += 1
		var before: Array = walk[i - 1]
		if past < walk.size() and not _route_in(layer, from_area, from_cell, walk[past][0], walk[past][1]).is_empty():
			i = past
			continue
		var out := _route_in(layer, from_area, from_cell, before[0], before[1])
		if out.is_empty():
			return none
		out[-1]["meets"] = held
		return out
	return none


## The cells of [param leg], from its start to its end, along a shortest
## walk in [param layer]: down the field of the portal it leaves by, or
## back from its end down the field of the portal it started at, or down a
## field walked for it now.
func _walk_cells(layer: Layer, leg: Dictionary) -> Array[Vector2i]:
	var area_name: String = leg["area"]
	var area: Dictionary = _areas[area_name]
	var from: Vector2i = leg["from"]
	var to: Vector2i = leg["to"]
	var exit := _field(layer, _portal_id(area_name, to))
	if _at(exit, area_name, from) >= 0.0:
		return _down(area, exit, from)
	var entry := _field(layer, _portal_id(area_name, from))
	var backwards := true
	var field := entry
	if _at(entry, area_name, to) < 0.0:
		var size: Vector2i = area["size"]
		field = PackedFloat32Array()
		field.resize(size.x * size.y)
		field.fill(-1.0)
		_flood(area, to, {}, field, layer.obstacles.get(area_name, {}))
		backwards = false
	if backwards:
		var cells := _down(area, field, to)
		cells.reverse()
		return cells
	return _down(area, field, from)


## The cells from [param cell] down [param field] to its 0 (its portal or
## start), each one real step nearer.
func _down(area: Dictionary, field: PackedFloat32Array, cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [cell]
	var here := cell
	while true:
		var next: Variant = _step_down(area, field, here)
		if next == null:
			break
		here = next
		cells.append(here)
	return cells


# --- Using the fields ----------------------------------------------------------------

## The place holding [param cell] of [param area_name] against
## [param layer]'s faction, or null if it may walk there.
func _held(layer: Layer, area_name: String, cell: Vector2i) -> Variant:
	var cells: Dictionary = layer.obstacles.get(area_name, {})
	return cells.get(cell)


func _portal_id(area_name: String, cell: Vector2i) -> int:
	return _portal_at.get("%s %d %d" % [area_name, cell.x, cell.y], -1)


## [param id]'s distance field in [param layer], or an empty one if it is
## not in yet (or is out of date).
func _field(layer: Layer, id: int) -> PackedFloat32Array:
	if id < 0 or not _area_ready(layer, _portals[id]["area"]):
		return PackedFloat32Array()
	_mutex.lock()
	var field: PackedFloat32Array = layer.fields.get(id, PackedFloat32Array())
	_mutex.unlock()
	return field


func _area_ready(layer: Layer, area_name: String) -> bool:
	_mutex.lock()
	var ready: bool = layer.ready.has(area_name) and layer.ready[area_name] == layer.version.get(area_name, 0)
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
## walk to in [param layer] (portal id -> steps): from the fields, or by
## walking the area.
func _to_portals(layer: Layer, area_name: String, cell: Vector2i) -> Dictionary[int, float]:
	var out: Dictionary[int, float] = {}
	var ids: Array = _in_area.get(area_name, [])
	if _area_ready(layer, area_name):
		for id: int in ids:
			var steps := _at(_field(layer, id), area_name, cell)
			if steps >= 0.0:
				out[id] = steps
		return out
	# Not in yet: each portal walked to (A*), not the area flooded till it
	# has them all (all of it, when one cannot be reached: decision 503).
	var obstacles: Dictionary = layer.obstacles.get(area_name, {})
	for id: int in ids:
		var steps := _steps_between(_areas[area_name], cell, _portals[id]["cell"], obstacles)
		if steps >= 0.0:
			out[id] = steps
	return out


## Joins [param area_name]'s portals to each other in [param layer]'s
## graph, once (until its obstacles change).
func _join_area(layer: Layer, area_name: String) -> void:
	if layer.joined.has(area_name) or not _in_area.has(area_name):
		return
	var started := Time.get_ticks_usec()
	var ids: Array = _in_area[area_name]
	if _area_ready(layer, area_name):
		for from_id: int in ids:
			var lengths := _to_portals(layer, area_name, _portals[from_id]["cell"])
			for to_id: int in lengths:
				if to_id != from_id:
					_join(layer, from_id, to_id, lengths[to_id])
	else:
		# Its fields not in yet: each pair walked towards each other (A*),
		# not the area flooded from every portal (decision 503).
		var obstacles: Dictionary = layer.obstacles.get(area_name, {})
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				var steps := _steps_between(_areas[area_name], _portals[ids[i]]["cell"], _portals[ids[j]]["cell"], obstacles)
				if steps >= 0.0:
					_join(layer, ids[i], ids[j], steps)
					_join(layer, ids[j], ids[i], steps)
	layer.joined[area_name] = true
	var ms := (Time.get_ticks_usec() - started) / 1000.0
	if ms > 50.0:
		print("[routes] %s walked for %s's routes in %.0f ms (its distance fields were not in yet)" % [area_name, layer.faction, ms])


## Takes [param area_name]'s portals' joins out of [param layer]'s graph.
func _unjoin(layer: Layer, area_name: String) -> void:
	layer.joined.erase(area_name)
	for from_id: int in _in_area.get(area_name, []):
		for to_id: int in _in_area[area_name]:
			var key := Vector2i(from_id, to_id)
			if layer.costs.has(key):
				layer.costs.erase(key)
				if not _crossings.has(key):
					layer.graph.disconnect_points(from_id, to_id, false)


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
func _cell_along(layer: Layer, leg: Dictionary, covered: float) -> Vector2i:
	var area_name: String = leg["area"]
	var area: Dictionary = _areas[area_name]
	var from: Vector2i = leg["from"]
	var to: Vector2i = leg["to"]
	var exit := _field(layer, _portal_id(area_name, to))
	if _at(exit, area_name, from) >= 0.0:
		# Towards the exit: down its field until covered steps are spent.
		return _descend(area, exit, from, _at(exit, area_name, from) - covered)
	var entry := _field(layer, _portal_id(area_name, from))
	if _at(entry, area_name, to) >= 0.0:
		# Back from the end, down the entry's field to covered steps from it.
		return _descend(area, entry, to, covered)
	var point := Vector2(from).lerp(Vector2(to), covered / maxf(leg["steps"], 0.001)).round()
	return _nearest_floor(area, Vector2i(point), from)


## From [param cell], step down [param field] until the field is at most
## [param down_to].
func _descend(area: Dictionary, field: PackedFloat32Array, cell: Vector2i, down_to: float) -> Vector2i:
	var size: Vector2i = area["size"]
	var here := cell
	while field[here.y * size.x + here.x] > down_to + 0.001:
		var next: Variant = _step_down(area, field, here)
		if next == null:
			break
		here = next
	return here


## The cell one real step from [param cell] down [param field] (one step
## nearer its 0), or null at the bottom.
func _step_down(area: Dictionary, field: PackedFloat32Array, cell: Vector2i) -> Variant:
	var size: Vector2i = area["size"]
	var value := field[cell.y * size.x + cell.x]
	if value <= 0.0:
		return null
	for direction in STRAIGHTS + DIAGONALS:
		var next := cell + direction
		if not Rect2i(Vector2i.ZERO, size).has_point(next):
			continue
		var step := DIAGONAL if direction.x != 0 and direction.y != 0 else 1.0
		var there := field[next.y * size.x + next.x]
		if there >= 0.0 and absf(there + step - value) < 0.001 and can_step(area, cell, direction):
			return next
	return null


## The floor cell nearest [param cell] (within 8), or [param fallback].
static func _nearest_floor(area: Dictionary, cell: Vector2i, fallback: Vector2i) -> Vector2i:
	var floor_cells: Dictionary = area["floor"]
	for radius in 9:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) == radius and floor_cells.has(cell + Vector2i(dx, dy)):
					return cell + Vector2i(dx, dy)
	return fallback


# --- Walking -------------------------------------------------------------------------

## Dijkstra by buckets over [param area] from [param from], costs in half
## steps (2 straight, 3 diagonal), never into [param obstacles] (nor out of
## one: a start in them reaches nothing). Returns the steps to each cell of
## [param wanted] it reaches, stopping once it has them all, unless
## [param field] (one float per cell, by y * width + x) is to be filled, in
## which case it walks the whole area and writes every cell's steps there.
static func _flood(area: Dictionary, from: Vector2i, wanted: Dictionary, field: PackedFloat32Array, obstacles: Dictionary = {}) -> Dictionary[Vector2i, float]:
	var found: Dictionary[Vector2i, float] = {}
	var floor_cells: Dictionary = area["floor"]
	if not floor_cells.has(from) or obstacles.has(from):
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
				_relax(area, cell, direction, cost + 2, best, buckets, obstacles)
			for direction in DIAGONALS:
				_relax(area, cell, direction, cost + 3, best, buckets, obstacles)
		buckets[cost] = []
		cost += 1
	return found


## The steps of the shortest walk from [param from] to [param to] in
## [param area] (as _flood walks), or -1 if it cannot get there: A* by
## buckets, costs in half steps, aimed by the octile distance (never more
## than the walk, so the walk found is a shortest), so it looks at the cells
## towards [param to] and not the whole area round [param from] (a death's
## way to the nearest temple: decision 503).
static func _steps_between(area: Dictionary, from: Vector2i, to: Vector2i, obstacles: Dictionary = {}) -> float:
	var floor_cells: Dictionary = area["floor"]
	if not floor_cells.has(from) or obstacles.has(from) or not floor_cells.has(to) or obstacles.has(to):
		return -1.0
	var best: Dictionary[Vector2i, int] = {from: 0}
	var buckets: Array[Array] = []
	var guess := _octile(from, to)
	while buckets.size() <= guess:
		buckets.append([])
	buckets[guess].append(from)
	while guess < buckets.size():
		var here: Array = buckets[guess]
		var i := 0
		while i < here.size():
			var cell: Vector2i = here[i]
			i += 1
			var cost := best[cell]
			if cost + _octile(cell, to) != guess:
				continue  # Reached again more cheaply since it was put here.
			if cell == to:
				return cost / 2.0
			for pair: Array in [[STRAIGHTS, 2], [DIAGONALS, 3]]:
				for direction: Vector2i in pair[0]:
					var next := cell + direction
					var next_cost: int = cost + step_cost(area, next, pair[1])
					if best.get(next, 1 << 30) <= next_cost or obstacles.has(next) or not can_step(area, cell, direction):
						continue
					best[next] = next_cost
					var f: int = next_cost + _octile(next, to)
					while buckets.size() <= f:
						buckets.append([])
					buckets[f].append(next)
		buckets[guess] = []
		guess += 1
	return -1.0


## The octile distance in half steps (2 straight, 3 diagonal).
static func _octile(a: Vector2i, b: Vector2i) -> int:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return 3 * mini(dx, dy) + 2 * absi(dx - dy)


## A step into [param to] of [param area] costing [param half_steps]
## (2 straight, 3 diagonal) on dry ground: FORD_COST times as much into a
## ford (decision 505), as World.step_ticks paces it.
static func step_cost(area: Dictionary, to: Vector2i, half_steps: int) -> int:
	return half_steps * FORD_COST if area.get("fords", {}).has(to) else half_steps


static func _relax(area: Dictionary, cell: Vector2i, direction: Vector2i, cost: int, best: Dictionary[Vector2i, int], buckets: Array[Array], obstacles: Dictionary) -> void:
	var to := cell + direction
	if area.get("fords", {}).has(to):
		cost += (cost - best[cell]) * (FORD_COST - 1)
	if best.get(to, 1 << 30) <= cost or obstacles.has(to) or not can_step(area, cell, direction):
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
	for faction: String in _layers:
		_layers[faction].graph.connect_points(exit_id, arrival_id, false)
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


## The portal at [param cell] of [param area_name], made (in every layer's
## graph) if it is new.
func _portal(area_name: String, cell: Vector2i) -> int:
	var key := "%s %d %d" % [area_name, cell.x, cell.y]
	if _portal_at.has(key):
		return _portal_at[key]
	var id := _layers[OPEN].graph.get_available_point_id()
	for faction: String in _layers:
		_layers[faction].graph.add_point(id, Vector2.ZERO)
	_portals[id] = {"area": area_name, "cell": cell}
	_portal_at[key] = id
	if not _in_area.has(area_name):
		_in_area[area_name] = []
	_in_area[area_name].append(id)
	return id


func _join(layer: Layer, from_id: int, to_id: int, steps: float) -> void:
	layer.costs[Vector2i(from_id, to_id)] = steps
	layer.graph.connect_points(from_id, to_id, false)


func _cost(faction: String, from_id: int, to_id: int) -> float:
	var layer: Layer = _layers[faction]
	var key := Vector2i(from_id, to_id)
	if _crossings.has(key):
		var way: Dictionary = _ways[_crossings[key]]
		if blocked.is_valid() and blocked.call(way, faction):
			return BLOCKED
		if _held(layer, _portals[from_id]["area"], _portals[from_id]["cell"]) != null \
				or _held(layer, _portals[to_id]["area"], _portals[to_id]["cell"]) != null:
			return BLOCKED
		return CROSSING
	return layer.costs.get(key, BLOCKED)
