class_name Clearing
extends RefCounted
## The forest felled and growing back (decision 591; Jeff: "forests to chop
## down, town and city growing and becoming something is one of the major
## gameplay components", "forests can regenerate too if not built over").
## Server only; World keeps one (World.clearing), made by Main at boot and
## moved on by the world tick's first slice, whether or not anyone is in a
## zone. Kept in the world snapshot ("clearing"), never in a level: the
## levels stay as made, and a cell grown back is the level's trunk again,
## leaving no trace.
##
## A tree is a trunk: a level's void cell inside its land (one beside the
## land's floor, more than EDGE cells in from the map's edge). fell takes
## trunks for a woodcut: the edge trunks within REACH of the site nearest
## the town first, each cell then a stump. A felled cell is floor of its
## stage's kind: a stump (dirt), then grass, scrub, saplings (grass); a
## stage lasts a season (Season.season_days), twice that for a cell with no
## standing trunk beside it, so a clearing closes from its edges in. Past
## saplings it is a trunk again, unless something stands or lies on it (it
## waits), or it is built over (a building's cell, a road's: never).
##
## The cells a zone has felled reach the views as terrain["clearing"]
## (cell -> stage), applied to a level's terrain as it loads (apply), and as
## the "clearing" message ({zone, cells: [[x, y, stage]]}, "trunk" for one
## grown back) when they change (changed).
##
## A town grows on plots (591 step 2, the coordinator's approval): plot_for
## finds a plot class's footprint (Level.PLOT_CLASSES) with a ring of a cell
## round it for its path and footing, on cleared level ground nearest the
## town's store, and lay_plot keeps it (plots, in the snapshot's "plots").
## A plot is staked ground, not a building: its cells never grow back, and
## buildings' 566 raises the kind on it through its stages by economy's
## record (its "use"). The sim lays its kind's walls (Level.plot_building)
## as for a town's own buildings, open until the record says they are up.
##
## A town falls back too (649, economy's rise and fall; Jeff: "buildings at
## the edge fall into disrepair and the forest overtakes"): unbuild gives a
## ruin's footprint back to the forest, its cells felled at a stump from the
## day given, growing on as any felled cell. A cell of the level's own floor
## so given back grows past saplings to a trunk that stays (kept: [4, day,
## 1], "trunk" to the views, out of the floor), the level floor no more;
## build takes cells back for a building planned on them (a kept trunk to
## grass, held while built). Both are kept in the snapshot (the level's own
## buildings and roads are read from it each boot): "built" the cells build
## took, "unbuilt" the level's built cells a ruin gave back.

## What each stage is, in order, and the floor kind it is.
const STAGES: Array[String] = ["stump", "grass", "scrub", "saplings"]
const STAGE_KINDS := {"stump": "dirt", "grass": "grass", "scrub": "grass", "saplings": "grass"}
## A cell grown back: the level's own trunk again.
const TRUNK := "trunk"
## How far round a woodcut's site trunks are taken (cells).
const REACH := 6
## How far a site steps out to the nearest standing edge when bare (cells).
const STEP_REACH := 40
## Trunks this near the map's edge are its border, never felled.
const EDGE := 4
## The cells kept clear between a plot's footprint and any other footprint,
## standing building or wall (612: never a one-cell walkway between).
const PLOT_GAP := 2
## How far from the store a plot is looked for (cells).
const PLOT_REACH := 64

## zone -> cell -> [stage index, the day the stage began], and a third 1 for
## a cell of the level's own floor (a ruin's, unbuild): STAGES.size() its
## stage once grown back, a trunk kept.
var felled: Dictionary = {}
## zone -> cell -> true: built over by build (a building planned on them).
var built_over: Dictionary = {}
## zone -> cell -> true: the level's own built cells a ruin gave back (unbuild).
var given_back: Dictionary = {}
## zone -> {size, floor (cell -> true), built (cell -> true)}: the level as
## made, read once a zone.
var _base: Dictionary = {}
## zone -> the cells of its plots (_plotted).
var _plot_cells: Dictionary = {}
var _day := -1
## zone -> [{town, kind, use, rect (Rect2i, the ring's), facing (Vector2i,
## the kind's +y), day}], each as laid.
var plots: Dictionary = {}
## (town, kind) -> "small" or "large": the size a plot's kind stands at
## (Main: economy's record's level); unset, Level.KIND_SIZE.
var size_of := Callable()
## The day, for tests (an int); else World's steps' day.
var clock := Callable()
## Told when a zone's cells change: (zone, cells: [[x, y, stage]]).
signal changed(zone: String, cells: Array)
## Told when a plot is laid: (zone, plot), plots_of's shape.
signal plotted(zone: String, plot: Dictionary)
## Told when a plot is dropped (unplot): (zone, plot), plots_of's shape.
signal unplotted(zone: String, plot: Dictionary)


func _init(saved := {}, saved_plots := {}) -> void:
	for zone: String in saved_plots:
		var listed: Variant = saved_plots[zone]
		plots[zone] = []
		for each: Variant in listed if listed is Array else []:
			var plot := plot_from(each)
			if not plot.is_empty():
				plot["day"] = int(each.get("day", 0))
				plots[zone].append(plot)
	for zone: String in saved:
		var cells := {}
		var listed: Variant = saved[zone]
		if listed is Dictionary:
			for key: String in listed:
				var entry: Variant = listed[key]
				if key == "built" or key == "unbuilt":
					var into: Dictionary = {}
					for each: Variant in entry if entry is Array else []:
						into[_cell_of(str(each))] = true
					(built_over if key == "built" else given_back)[zone] = into
				elif entry is Array and ((entry as Array).size() == 2 or (entry as Array).size() == 3):
					cells[_cell_of(key)] = (entry as Array).map(func(n: Variant) -> int: return int(n))
		felled[zone] = cells


func to_dict() -> Dictionary:
	var out := {}
	for zone: String in _zones():
		var cells := {}
		for cell: Vector2i in felled.get(zone, {}):
			cells["%d,%d" % [cell.x, cell.y]] = (felled[zone][cell] as Array).duplicate()
		for key: String in ["built", "unbuilt"]:
			var listed: Dictionary = (built_over if key == "built" else given_back).get(zone, {})
			if not listed.is_empty():
				cells[key] = listed.keys().map(func(cell: Vector2i) -> String: return "%d,%d" % [cell.x, cell.y])
		if not cells.is_empty():
			out[zone] = cells
	return out


## Every zone with felled, built or given back cells.
func _zones() -> Array:
	var zones := {}
	for each: Dictionary in [felled, built_over, given_back]:
		for zone: String in each:
			zones[zone] = true
	return zones.keys()


static func _cell_of(key: String) -> Vector2i:
	return Vector2i(int(key.get_slice(",", 0)), int(key.get_slice(",", 1)))


## The plots, for the snapshot's "plots": zone -> [wire plots with "day"].
func plots_to_dict() -> Dictionary:
	var out := {}
	for zone: String in plots:
		var listed := []
		for plot: Dictionary in plots[zone]:
			var wire := plot_wire(plot)
			wire["day"] = int(plot.get("day", 0))
			listed.append(wire)
		if not listed.is_empty():
			out[zone] = listed
	return out


func today() -> int:
	if clock.is_valid():
		return int(clock.call())
	return World.steps / maxi(DayNight.day_steps, 1)


## [param terrain] (a level's as parsed, zone [param zone]'s) with its
## felled cells floor of their stage's kind, their edges open to the floor
## round them (Level.relay_outline, 591 amended) and terrain["clearing"]
## (cell -> stage) for the views. Main applies it before World loads the
## terrain.
func apply(zone: String, terrain: Dictionary) -> void:
	var stages: Dictionary[Vector2i, String] = {}
	var cells: Array[Vector2i] = []
	for cell: Vector2i in felled.get(zone, {}):
		cells.append(cell)
		if _kept(zone, cell):
			terrain["floor"].erase(cell)  # A ruin's ground grown back (649): a trunk.
			terrain["kinds"].erase(cell)
			continue
		var stage: String = STAGES[int(felled[zone][cell][0])]
		stages[cell] = stage
		if not cell in terrain["floor"]:
			terrain["floor"].append(cell)
		terrain["kinds"][cell] = STAGE_KINDS[stage]
	terrain["clearing"] = stages
	Level.relay_outline(terrain, cells)
	lay_plots(terrain, plots_of(zone), size_of)


## [param cells] ([[x, y, stage]], a "clearing" message's or the server's
## own change) laid on [param terrain]: felled cells floor, grown ones void
## again, the outline's walls round them made again (Level.relay_outline:
## a felled cell open to the floor beside it, a regrown trunk walled).
## Returns the edges changed (key -> kind) for World.set_edges and the
## views' walls.
static func apply_cells(terrain: Dictionary, cells: Array) -> Dictionary[Vector3i, int]:
	var stages: Dictionary = terrain.get("clearing", {})
	var changed: Array[Vector2i] = []
	for each: Array in cells:
		var cell := Vector2i(int(each[0]), int(each[1]))
		var stage := str(each[2])
		if stage == TRUNK:
			stages.erase(cell)
			terrain["floor"].erase(cell)
			terrain["kinds"].erase(cell)
		else:
			stages[cell] = stage
			if not cell in terrain["floor"]:
				terrain["floor"].append(cell)
			terrain["kinds"][cell] = STAGE_KINDS.get(stage, "grass")
		changed.append(cell)
	terrain["clearing"] = stages
	return Level.relay_outline(terrain, changed)


## [param listed] (plots_of's shape) laid on [param terrain]: kept in
## terrain["plots"] for the views, and each its kind's building at the size
## the plot's own "size" says (a client's, as told), else [param sizes]
## ((town, kind) -> "small" | "large"; unset, Level.KIND_SIZE), in
## terrain["plot_buildings"], its walls and doors in the
## edges where none stand (Fields keeps them open until its walls are up,
## 566). Main's apply on the server, and a client's from the message.
static func lay_plots(terrain: Dictionary, listed: Array, sizes := Callable()) -> void:
	var kept: Array = terrain.get("plots", [])
	var built: Array = terrain.get("plot_buildings", [])
	for plot: Dictionary in listed:
		kept.append(plot)
		var size := Level.KIND_SIZE
		if plot.has("size"):
			size = str(plot["size"])  # As told a client (the server's size then).
		elif sizes.is_valid():
			size = str(sizes.call(plot["town"], plot["kind"]))
		var building := Level.plot_building(plot, size, terrain)
		if building.is_empty():
			continue
		built.append(building)
		var edges := Level.plot_edges(building)
		var laid: Array[Vector3i] = []
		for key: Vector3i in edges:
			if not terrain["edges"].has(key):
				terrain["edges"][key] = edges[key]
				laid.append(key)
		building["laid"] = laid  # The edges it added, for unlay_plot.
	terrain["plots"] = kept
	terrain["plot_buildings"] = built


## The plot on [param rect] taken off [param terrain] (649, maps'
## side; lay_plots' reverse): out of terrain["plots"], its building out of
## terrain["plot_buildings"] and the edges it laid out of the edges (any
## changed since kept). Returns its building, {} if none.
static func unlay_plot(terrain: Dictionary, rect: Rect2i) -> Dictionary:
	var kept: Array = terrain.get("plots", [])
	for i in range(kept.size() - 1, -1, -1):
		if (kept[i] as Dictionary)["rect"] == rect:
			kept.remove_at(i)
	var built: Array = terrain.get("plot_buildings", [])
	for i in range(built.size() - 1, -1, -1):
		var building: Dictionary = built[i]
		if not building.get("plot", false) or not rect.encloses(building["rect"]):
			continue
		built.remove_at(i)
		var edges := Level.plot_edges(building)
		for key: Vector3i in building.get("laid", []):
			if terrain["edges"].get(key) == edges.get(key):
				terrain["edges"].erase(key)
		return building
	return {}


## A plot as a message and the snapshot carry it: {town, kind, use, rect:
## [x, y, w, h], facing: [dx, dy]}.
static func plot_wire(plot: Dictionary) -> Dictionary:
	var rect: Rect2i = plot["rect"]
	var facing: Vector2i = plot["facing"]
	return {"town": plot["town"], "kind": plot["kind"], "use": plot["use"],
		"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "facing": [facing.x, facing.y]}


## A wire plot read back (plot_wire's), {} for a bad one.
static func plot_from(wire: Variant) -> Dictionary:
	if not wire is Dictionary or not wire.get("rect") is Array or (wire["rect"] as Array).size() != 4:
		return {}
	var facing: Variant = Level.facing_from(wire.get("facing"))
	if facing == null or (facing.x != 0 and facing.y != 0):
		return {}
	var at: Array = wire["rect"]
	return {"town": str(wire.get("town", "")), "kind": str(wire.get("kind", "")), "use": str(wire.get("use", wire.get("kind", ""))),
		"rect": Rect2i(int(at[0]), int(at[1]), int(at[2]), int(at[3])), "facing": facing}


## Zone [param zone]'s laid plots: [{town, kind, use, rect, facing}], as
## terrain["plots"] holds them.
func plots_of(zone: String) -> Array:
	var out := []
	for plot: Dictionary in plots.get(zone, []):
		out.append({"town": plot["town"], "kind": plot["kind"], "use": plot["use"], "rect": plot["rect"], "facing": plot["facing"]})
	return out


## Where a plot of class [param plot_class] (Level.PLOT_CLASSES) goes in
## [param zone]: its footprint with a ring of a cell round it, the ring's
## rect, nearest [param toward] (the town's store) within PLOT_REACH, on
## cleared level ground: every cell floor (the level's, or felled), not
## water, a building, a link or another plot's footprint, more than EDGE in
## from the map's edge, all of one height; the footprint off roads (they
## may touch the ring) and PLOT_GAP cells clear of any other footprint,
## standing building or wall. Turned either way. An empty Rect2i when
## nothing fits: the town fells more first (the woodcut the only clearer).
func plot_for(zone: String, plot_class: String, toward: Vector2i) -> Rect2i:
	var footprint: Vector2i = Level.PLOT_CLASSES.get(plot_class, Vector2i.ZERO)
	if footprint == Vector2i.ZERO or not Level.exists(zone):
		return Rect2i()
	var base := _base_of(zone)
	var size: Vector2i = base["size"]
	var map := Rect2i(Vector2i.ZERO, size)
	var footed: Dictionary = (base["buildings"] as Dictionary).merged(base["solid"])
	for plot: Dictionary in plots.get(zone, []):
		for cell in Level.rect_cells((plot["rect"] as Rect2i).grow(-1)):
			footed[cell] = true
	# The cells no ring may take; those a footprint keeps PLOT_GAP from (a
	# footprint, a wall); a road's, kept off the footprint: summed tables.
	var ring_bad := PackedInt32Array()
	var stop := PackedInt32Array()
	var road := PackedInt32Array()
	for list: PackedInt32Array in [ring_bad, stop, road]:
		list.resize(size.x * size.y)
	for y in size.y:
		for x in size.x:
			var cell := Vector2i(x, y)
			var i := y * size.x + x
			stop[i] = 1 if footed.has(cell) or base["walls"].has(cell) else 0
			road[i] = 1 if base["roads"].has(cell) else 0
			var usable: bool = x >= EDGE and y >= EDGE and x < size.x - EDGE and y < size.y - EDGE and not footed.has(cell) \
				and _is_floor(zone, base, cell) and not base["water"].has(cell) and not base["links"].has(cell)
			ring_bad[i] = 0 if usable else 1
	var ring_sum := _summed(ring_bad, size)
	var stop_sum := _summed(stop, size)
	var road_sum := _summed(road, size)
	# Candidates by their middle's distance to the store, nearest first.
	var buckets: Array[Array] = []
	buckets.resize(PLOT_REACH + 1)
	for i in buckets.size():
		buckets[i] = []
	for turned: Vector2i in ([footprint] if footprint.x == footprint.y else [footprint, Vector2i(footprint.y, footprint.x)]):
		var whole := turned + Vector2i(2, 2)
		for y in range(maxi(0, toward.y - PLOT_REACH - whole.y), mini(size.y - whole.y, toward.y + PLOT_REACH) + 1):
			for x in range(maxi(0, toward.x - PLOT_REACH - whole.x), mini(size.x - whole.x, toward.x + PLOT_REACH) + 1):
				var rect := Rect2i(x, y, whole.x, whole.y)
				var far := int((Vector2(rect.position) + Vector2(rect.size) / 2.0 - Vector2(toward)).length())
				if far <= PLOT_REACH:
					buckets[far].append(rect)
	var heights: Dictionary = base["heights"]
	for bucket: Array in buckets:
		for rect: Rect2i in bucket:
			var inner := rect.grow(-1)
			if _sum_in(ring_sum, size, rect) != 0 or _sum_in(road_sum, size, inner) != 0 \
					or _sum_in(stop_sum, size, inner.grow(PLOT_GAP).intersection(map)) != 0:
				continue
			var height := int(heights.get(rect.position, 0))
			if Level.rect_cells(rect).all(func(cell: Vector2i) -> bool: return int(heights.get(cell, 0)) == height):
				return rect
	return Rect2i()


## The way a plot's kind faces on [param rect] (a ring's, of class
## [param plot_class]): its +y toward [param toward] along the axis its
## turn allows (either for a square class: the nearer way).
static func facing_for(rect: Rect2i, plot_class: String, toward: Vector2i) -> Vector2i:
	var footprint: Vector2i = Level.PLOT_CLASSES.get(plot_class, Vector2i.ZERO)
	var inner := rect.grow(-1).size
	var to: Vector2 = Vector2(toward) - (Vector2(rect.position) + Vector2(rect.size) / 2.0)
	var along_y := inner == footprint and (footprint.x != footprint.y or absf(to.y) >= absf(to.x))
	if along_y:
		return Vector2i(0, 1 if to.y >= 0.0 else -1)
	return Vector2i(1 if to.x >= 0.0 else -1, 0)


## Lays a plot for [param town]'s [param kind] on [param rect] (plot_for's),
## its kind's +y turned to [param facing]: kept (the snapshot's), its cells
## never growing back; plotted told. [param use] is economy's record key,
## the kind unless given. The plot, plots_of's shape.
func lay_plot(zone: String, town: String, kind: String, rect: Rect2i, facing: Vector2i, use := "") -> Dictionary:
	if not plots.has(zone):
		plots[zone] = []
	plots[zone].append({"town": town, "kind": kind, "use": use if not use.is_empty() else kind, "rect": rect, "facing": facing, "day": today()})
	_plot_cells.erase(zone)
	var told: Dictionary = plots_of(zone).back()
	plotted.emit(zone, told)
	return told


## Drops zone [param zone]'s plot on [param rect] (649, maps'
## side: economy's, when a ruin's record is dropped after its season, and
## terrain's unbuild over a plot's cells): its cells no longer kept from
## growing back, so a felled one grows back as any does and a level floor
## one once unbuild hands it to the regrowth; unplotted told. The plot
## dropped, plots_of's shape; {} if none is laid on [param rect].
func unplot(zone: String, rect: Rect2i) -> Dictionary:
	var listed: Array = plots.get(zone, [])
	for i in listed.size():
		var plot: Dictionary = listed[i]
		if plot["rect"] != rect:
			continue
		listed.remove_at(i)
		_plot_cells.erase(zone)
		var told := {"town": plot["town"], "kind": plot["kind"], "use": plot["use"], "rect": plot["rect"], "facing": plot["facing"]}
		unplotted.emit(zone, told)
		return told
	return {}


## Zone [param zone]'s plot whose rect (its ring's) holds [param cell],
## plots_of's shape; {} if none.
func plot_at(zone: String, cell: Vector2i) -> Dictionary:
	for plot: Dictionary in plots.get(zone, []):
		if (plot["rect"] as Rect2i).has_point(cell):
			return {"town": plot["town"], "kind": plot["kind"], "use": plot["use"], "rect": plot["rect"], "facing": plot["facing"]}
	return {}


## A summed table of [param values] (size.x by size.y), a row and a column
## of 0 before.
static func _summed(values: PackedInt32Array, size: Vector2i) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize((size.x + 1) * (size.y + 1))
	for y in size.y:
		var row := 0
		for x in size.x:
			row += values[y * size.x + x]
			out[(y + 1) * (size.x + 1) + x + 1] = out[y * (size.x + 1) + x + 1] + row
	return out


## The sum of a summed table's values over [param rect] (inside the map).
static func _sum_in(summed: PackedInt32Array, size: Vector2i, rect: Rect2i) -> int:
	var w := size.x + 1
	return summed[rect.end.y * w + rect.end.x] - summed[rect.position.y * w + rect.end.x] \
		- summed[rect.end.y * w + rect.position.x] + summed[rect.position.y * w + rect.position.x]


## A zone's felled cells as a message's list ([[x, y, stage]]).
func cells_of(zone: String) -> Array:
	var out := []
	for cell: Vector2i in felled.get(zone, {}):
		out.append([cell.x, cell.y, TRUNK if _kept(zone, cell) else STAGES[int(felled[zone][cell][0])]])
	return out


## A woodcut (economy's, through Towns.fell): up to [param wanted] trunks of
## zone [param zone] felled within REACH of [param site] (its woodlot's
## cell), the edge trunks nearest [param toward] (the town's store) first;
## how many. None within reach: 0 (step_site moves the lot).
func fell(zone: String, site: Vector2i, toward: Vector2i, wanted: int) -> int:
	if wanted <= 0 or not Level.exists(zone):
		return 0
	var taken := []
	for i in wanted:
		var trunk := _nearest_edge(zone, site, REACH, toward)
		if trunk == World.NO_CELL:
			break
		if not felled.has(zone):
			felled[zone] = {}
		felled[zone][trunk] = [0, today(), 1] if _base_of(zone)["floor"].has(trunk) else [0, today()]
		taken.append([trunk.x, trunk.y, STAGES[0]])
	if not taken.is_empty():
		changed.emit(zone, taken)
	return taken.size()


## A ruin's footprint given back to the forest (649; Main, at economy's
## ruin dropped): [param cells] of [param zone] felled at a stump from
## [param day], built over no more, growing on as any felled cell (a cell of
## the level's own floor to a trunk kept). A laid plot under any of them is
## dropped first, the whole of it (unplot, maps' 649 side: its building and
## edges off with it). Told changed; how many were given back.
func unbuild(zone: String, cells: Array[Vector2i], day: int) -> int:
	if not Level.exists(zone):
		return 0
	var base := _base_of(zone)
	var size: Vector2i = base["size"]
	for cell in cells:
		var plot := plot_at(zone, cell)
		if not plot.is_empty():
			unplot(zone, plot["rect"])
	var given := []
	for cell in cells:
		if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y or base["water"].has(cell):
			continue
		if not _is_floor(zone, base, cell) and not _is_built(zone, base, cell):
			continue  # A trunk already: nothing built there to fall.
		(built_over.get(zone, {}) as Dictionary).erase(cell)
		if base["built"].has(cell):
			if not given_back.has(zone):
				given_back[zone] = {}
			given_back[zone][cell] = true
		if not felled.has(zone):
			felled[zone] = {}
		# The level's own ground (its floor, or a building's cell): kept once
		# grown back, never the level's cell again.
		felled[zone][cell] = [0, day, 1] if base["floor"].has(cell) or base["built"].has(cell) else [0, day]
		given.append([cell.x, cell.y, STAGES[0]])
	if not given.is_empty():
		changed.emit(zone, given)
	return given.size()


## [param cells] of [param zone] taken for a building planned on them (649;
## Main, as economy plans one on ground the forest took back): built over
## (kept so, never growing), each floor: a kept trunk grass again, a felled
## cell held at its stage, a standing trunk of the level grass. Told changed
## for the cells that changed.
func build(zone: String, cells: Array[Vector2i]) -> void:
	if not Level.exists(zone):
		return
	var base := _base_of(zone)
	var size: Vector2i = base["size"]
	if not built_over.has(zone):
		built_over[zone] = {}
	if not felled.has(zone):
		felled[zone] = {}
	var taken := []
	for cell in cells:
		if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y or base["water"].has(cell):
			continue
		built_over[zone][cell] = true
		if _kept(zone, cell) or not _is_floor(zone, base, cell):
			felled[zone][cell] = [1, today(), 1] if base["floor"].has(cell) else [1, today()]
			taken.append([cell.x, cell.y, STAGES[1]])
	if not taken.is_empty():
		changed.emit(zone, taken)


## Where a woodlot bare of trunks within REACH of [param site] steps out to:
## the floor cell beside the standing edge trunk nearest it (within
## STEP_REACH), nearest the site; World.NO_CELL if there is none.
func step_site(zone: String, site: Vector2i) -> Vector2i:
	var trunk := _nearest_edge(zone, site, STEP_REACH, site)
	if trunk == World.NO_CELL:
		return World.NO_CELL
	var base := _base_of(zone)
	var best := World.NO_CELL
	for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var beside := trunk + step
		if _is_floor(zone, base, beside) and (best == World.NO_CELL or Vector2(beside - site).length() < Vector2(best - site).length()):
			best = beside
	return best


## The world tick: on a new day, every zone's felled cells grow on.
func tick() -> void:
	var day := today()
	if day == _day:
		return
	_day = day
	daily(day)


## [param day]'s growing: each felled cell's stage on when it has lasted its
## season (twice that with no standing trunk beside it); past saplings, a
## trunk again if nothing stands or lies on it and it is not built over.
func daily(day: int) -> void:
	var stage_days := maxi(1, Season.season_days)
	for zone: String in felled.keys():
		var base := _base_of(zone)
		var grown := []
		for cell: Vector2i in (felled[zone] as Dictionary).keys():
			if _is_built(zone, base, cell) or _plotted(zone).has(cell) or _kept(zone, cell):
				continue
			var entry: Array = felled[zone][cell]
			var needed := stage_days if _beside_trunk(zone, base, cell) else stage_days * 2
			if day - int(entry[1]) < needed:
				continue
			var floor_cell := entry.size() > 2
			if int(entry[0]) + 1 < STAGES.size():
				felled[zone][cell] = [int(entry[0]) + 1, day, 1] if floor_cell else [int(entry[0]) + 1, day]
				grown.append([cell.x, cell.y, STAGES[int(entry[0]) + 1]])
			elif not _occupied(zone, cell):
				# The level's own trunk again; a ruin's floor cell a trunk kept.
				if floor_cell:
					felled[zone][cell] = [STAGES.size(), day, 1]
				else:
					(felled[zone] as Dictionary).erase(cell)
				grown.append([cell.x, cell.y, TRUNK])
		if not grown.is_empty():
			changed.emit(zone, grown)


## The standing edge trunk of [param zone] within [param reach] of [param
## site] nearest [param toward]: a trunk not felled with floor (the level's,
## or felled) beside it; World.NO_CELL if none.
func _nearest_edge(zone: String, site: Vector2i, reach: int, toward: Vector2i) -> Vector2i:
	var base := _base_of(zone)
	var size: Vector2i = base["size"]
	var best := World.NO_CELL
	for y in range(site.y - reach, site.y + reach + 1):
		for x in range(site.x - reach, site.x + reach + 1):
			var cell := Vector2i(x, y)
			if x < EDGE or y < EDGE or x >= size.x - EDGE or y >= size.y - EDGE or Vector2(cell - site).length() > reach:
				continue
			if _is_floor(zone, base, cell) or _is_built(zone, base, cell) or base["water"].has(cell):
				continue
			var edge := false
			for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				edge = edge or _is_floor(zone, base, cell + step)
			if edge and (best == World.NO_CELL or Vector2(cell - toward).length() < Vector2(best - toward).length()):
				best = cell
	return best


func _is_floor(zone: String, base: Dictionary, cell: Vector2i) -> bool:
	if felled.get(zone, {}).has(cell):
		return not _kept(zone, cell)
	return base["floor"].has(cell)


## Whether [param cell] of [param zone] is a ruin's floor cell grown back to
## a trunk (649).
func _kept(zone: String, cell: Vector2i) -> bool:
	var entry: Variant = felled.get(zone, {}).get(cell)
	return entry != null and int(entry[0]) >= STAGES.size()


## Whether [param cell] is built over: the level's building or road (unless a
## ruin gave it back), or build's.
func _is_built(zone: String, base: Dictionary, cell: Vector2i) -> bool:
	if built_over.get(zone, {}).has(cell):
		return true
	return base["built"].has(cell) and not given_back.get(zone, {}).has(cell)


## Zone [param zone]'s plots' cells, rings and all (never growing back).
func _plotted(zone: String) -> Dictionary:
	if not _plot_cells.has(zone):
		var cells := {}
		for plot: Dictionary in plots.get(zone, []):
			for cell in Level.rect_cells(plot["rect"]):
				cells[cell] = true
		_plot_cells[zone] = cells
	return _plot_cells[zone]


## Whether a standing trunk (the level's void, not felled) is beside [param cell].
func _beside_trunk(zone: String, base: Dictionary, cell: Vector2i) -> bool:
	var size: Vector2i = base["size"]
	for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var near := cell + step
		if near.x >= 0 and near.y >= 0 and near.x < size.x and near.y < size.y and not _is_floor(zone, base, near) and not base["water"].has(near):
			return true
	return false


## Whether something stands or lies on [param cell] of loaded zone [param
## zone] (a cell grown back must not shut anyone in); an unloaded zone has
## nothing on it.
func _occupied(zone: String, cell: Vector2i) -> bool:
	if not World.zones.has(zone):
		return false
	var was := World.zone
	World.enter(World.zones[zone])
	var taken := not World.is_free(cell) or not World.ground_at(cell).is_empty()
	World.enter(was)
	return taken


## The level as made, read once a zone: its size, floor, water, and what is
## built over (buildings' cells, roads' cells), and for plots each of those
## apart, its links' cells, solid cells, the cells either side of its walls
## and its heights.
func _base_of(zone: String) -> Dictionary:
	if _base.has(zone):
		return _base[zone]
	var level := Level.load_level(zone)
	var base := {"size": Vector2i.ZERO, "floor": {}, "water": {}, "built": {}, "buildings": {}, "roads": {}, "links": {},
		"solid": {}, "walls": {}, "heights": {}}
	if not level.is_empty():
		var terrain: Dictionary = level["terrain"]
		base["size"] = level["size"]
		for cell: Vector2i in terrain["floor"]:
			base["floor"][cell] = true
		for key in ["water", "fords", "bridged"]:
			for cell: Vector2i in terrain.get(key, []):
				base["water"][cell] = true
		for building: Dictionary in level["buildings"]:
			for cell in Level.building_cells(building):
				base["built"][cell] = true
				base["buildings"][cell] = true
		for road: Dictionary in terrain.get("roads", []):
			for cell: Vector2i in Curves.cells(road["curve"], false):
				base["built"][cell] = true
				base["roads"][cell] = true
		for link: Dictionary in level.get("links", []):
			base["links"][link["tile"]] = true
		for cell: Vector2i in terrain.get("solid", []):
			base["solid"][cell] = true
		# A wall between two floor cells (not the floor's edge against the
		# void, which the ring's own floor rule keeps off): both its cells.
		for key: Vector3i in terrain["edges"]:
			var sides := Terrain.edge_cells(key)
			if base["floor"].has(sides[0]) and base["floor"].has(sides[1]):
				base["walls"][sides[0]] = true
				base["walls"][sides[1]] = true
		base["heights"] = terrain.get("heights", {})
	_base[zone] = base
	return base
