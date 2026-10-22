class_name Curves
## Water and roads as smooth curves, the cells rasterised from them
## (decision 559; Jeff: "Rivers, streams, roads and shorelines are drawn as
## smooth curves, then rasterized to cells. Never cell regions with rounded
## edges."). level.json "waters" and "roads" carry control points in cell
## units, a width per point; the sim's cells, the "streams" paths and the
## views' drawing all come from the same sampled curve here, so they agree.

## How far apart a sampled curve's points lie, in cells.
const SPACING := 0.25
## The narrowest a curve's width is sampled.
const LEAST_WIDTH := 0.5


## The curve through [param points] (cells), a point every SPACING of its
## length: a centripetal Catmull-Rom (no cusps or loops at uneven spacing),
## round to the first point again if [param closed]; [param widths] (one a
## point) interpolated along it the same way, at least LEAST_WIDTH (all 0
## for a closed curve); each point's way along it (a unit vector). As
## {points, widths, tangents, length}.
static func sample(points: PackedVector2Array, widths: PackedFloat32Array, closed := false) -> Dictionary:
	var out := {"points": PackedVector2Array(), "widths": PackedFloat32Array(), "tangents": PackedVector2Array(), "length": 0.0}
	var count := points.size()
	if count < 2:
		return out
	# Densely along each span, then evenly by length.
	var dense := PackedVector2Array()
	var dense_widths := PackedFloat32Array()
	var spans := count if closed else count - 1
	for i in spans:
		var p := [_at(points, i - 1, closed), points[i], _at(points, i + 1, closed), _at(points, i + 2, closed)]
		var w := [_width_at(widths, i - 1, closed), _width_at(widths, i, closed), _width_at(widths, i + 1, closed), _width_at(widths, i + 2, closed)]
		var pieces := maxi(8, ceili(points[i].distance_to(_at(points, i + 1, closed)) * 8.0))
		for j in pieces:
			var t := float(j) / pieces
			dense.append(_centripetal(p[0], p[1], p[2], p[3], t))
			dense_widths.append(_hermite(w[0], w[1], w[2], w[3], t))
	dense.append(points[0] if closed else points[count - 1])
	dense_widths.append(_width_at(widths, 0 if closed else count - 1, closed))
	var length := 0.0
	for i in range(1, dense.size()):
		length += dense[i].distance_to(dense[i - 1])
	out["length"] = length
	var walked := 0.0
	var segment := 0
	var s := 0.0
	while s <= length + 0.0001:
		while segment < dense.size() - 2 and walked + dense[segment].distance_to(dense[segment + 1]) < s:
			walked += dense[segment].distance_to(dense[segment + 1])
			segment += 1
		var span := maxf(dense[segment].distance_to(dense[segment + 1]), 0.0001)
		var t := clampf((s - walked) / span, 0.0, 1.0)
		out["points"].append(dense[segment].lerp(dense[segment + 1], t))
		out["widths"].append(0.0 if closed else maxf(LEAST_WIDTH, lerpf(dense_widths[segment], dense_widths[segment + 1], t)))
		s += SPACING
	var sampled: PackedVector2Array = out["points"]
	var tangents := PackedVector2Array()
	for i in sampled.size():
		var before := sampled[i - 1] if i > 0 else (sampled[-2] if closed and sampled.size() > 2 else sampled[i])
		var after := sampled[i + 1] if i + 1 < sampled.size() else (sampled[1] if closed and sampled.size() > 2 else sampled[i])
		tangents.append((after - before).normalized())
	out["tangents"] = tangents
	return out


## The nearest point of [param curve] (sample's) to [param at]: as
## {distance, along (cells from its start), width there, index (of the
## sampled point before it)}.
static func nearest(curve: Dictionary, at: Vector2) -> Dictionary:
	var points: PackedVector2Array = curve["points"]
	var widths: PackedFloat32Array = curve["widths"]
	var best := {"distance": INF, "along": 0.0, "width": 0.0, "index": -1}
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var on := Geometry2D.get_closest_point_to_segment(at, a, b)
		var near := at.distance_to(on)
		if near < best["distance"]:
			var t := a.distance_to(on) / maxf(a.distance_to(b), 0.0001)
			best = {"distance": near, "along": (i - 1 + t) * SPACING, "width": lerpf(widths[i - 1], widths[i], t), "index": i - 1}
	return best


## Whether [param at] lies inside the closed [param curve].
static func inside(curve: Dictionary, at: Vector2) -> bool:
	var points: PackedVector2Array = curve["points"]
	return points.size() >= 3 and Geometry2D.is_point_in_polygon(at, points)


## The cells of [param curve] (sample's): open, each cell whose middle lies
## within the width / 2 there of the curve, and its middle's (middle()),
## each -> the index in middle() of the cell it was laid from (the nearest
## point of the curve's; a middle cell its own); closed, each cell whose
## middle lies inside it, -> -1.
static func cells(curve: Dictionary, closed: bool) -> Dictionary[Vector2i, int]:
	var out: Dictionary[Vector2i, int] = {}
	var points: PackedVector2Array = curve["points"]
	if points.size() < 2:
		return out
	if closed:
		var low := Vector2i(floori(points[0].x), floori(points[0].y))
		var high := low
		for point in points:
			low = low.min(Vector2i(floori(point.x), floori(point.y)))
			high = high.max(Vector2i(ceili(point.x), ceili(point.y)))
		for y in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1):
				if Geometry2D.is_point_in_polygon(Vector2(x, y), points):
					out[Vector2i(x, y)] = -1
		return out
	var widths: PackedFloat32Array = curve["widths"]
	var standing := _standing(curve)
	var path: Array[Vector2i] = standing["middle"]
	var at_index: PackedInt32Array = standing["at"]
	var nearest_gap := {}
	for k in points.size():
		if at_index[k] < 0:
			continue
		var point := points[k]
		var reach := widths[k] / 2.0
		for y in range(floori(point.y - reach), ceili(point.y + reach) + 1):
			for x in range(floori(point.x - reach), ceili(point.x + reach) + 1):
				var cell := Vector2i(x, y)
				var gap := Vector2(cell).distance_to(point)
				if gap < reach and gap < float(nearest_gap.get(cell, INF)):
					nearest_gap[cell] = gap
					out[cell] = at_index[k]
	for i in path.size():
		out[path[i]] = i
	return out


## cells() of [param curve] on [param ground] (cell -> anything): open, the
## longest run of its middle on the ground ("path", first to last) and the
## cells of the ground laid from it; closed, its cells on the ground. As
## {cells: cell -> middle index, path, first (path's index in middle())}. Level lays a water's cells on load
## this way and Relief.lay its rivers, so both lay the same.
static func laid(curve: Dictionary, closed: bool, ground: Dictionary) -> Dictionary:
	var raster := cells(curve, closed)
	var out: Dictionary[Vector2i, int] = {}
	var run: Array[Vector2i] = []
	if closed:
		for cell: Vector2i in raster:
			if ground.has(cell):
				out[cell] = -1
		return {"cells": out, "path": run, "first": 0}
	var path := middle(curve)
	var first := 0
	var last := -1
	var start := 0
	for i in path.size() + 1:
		if i < path.size() and ground.has(path[i]):
			continue
		if i - 1 - start > last - first:
			first = start
			last = i - 1
		start = i + 1
	if last < first:
		return {"cells": out, "path": run, "first": 0}
	run = path.slice(first, last + 1)
	for cell: Vector2i in raster:
		if ground.has(cell) and raster[cell] >= first and raster[cell] <= last:
			out[cell] = raster[cell]
	return {"cells": out, "path": run, "first": first}


## The cells [param curve] (sample's, open) runs through, first to last,
## each a side step from the one before (a corner turned through the side
## cell nearer the curve, so nothing steps diagonally between two of them),
## a loop that comes back on itself cut out: a stream's "streams" path.
static func middle(curve: Dictionary) -> Array[Vector2i]:
	return _standing(curve)["middle"]


## middle(), and for each sampled point the index in it of the cell it
## stands at (-1 where cut out with a loop): {middle, at}.
static func _standing(curve: Dictionary) -> Dictionary:
	var path: Array[Vector2i] = []
	var index_of := {}
	var at_index := PackedInt32Array()
	for point: Vector2 in curve["points"]:
		var cell := Vector2i(roundi(point.x), roundi(point.y))
		while path.is_empty() or cell != path[-1]:
			var next := cell
			if not path.is_empty():
				var step := (cell - path[-1]).clamp(-Vector2i.ONE, Vector2i.ONE)
				if step.x != 0 and step.y != 0:
					var across := path[-1] + Vector2i(step.x, 0)
					var down := path[-1] + Vector2i(0, step.y)
					step = across - path[-1] if Vector2(across).distance_to(point) <= Vector2(down).distance_to(point) else down - path[-1]
				next = path[-1] + step
			if index_of.has(next):
				var back: int = index_of[next]
				for gone in path.slice(back + 1):
					index_of.erase(gone)
				path.resize(back + 1)
				for i in at_index.size():
					if at_index[i] > back:
						at_index[i] = -1
			else:
				index_of[next] = path.size()
				path.append(next)
		at_index.append(path.size() - 1)
	return {"middle": path, "at": at_index}


## level.json's [param key] ("waters" or "roads", decision 559) from
## [param config]: [{points: [[x, y, width], ...], closed, kind}], each
## sampled; as [{points, widths, closed, kind, curve}]. A water's kind is
## "water"; a road's "dirt" or "stone" (dirt if not said). An entry of
## fewer than two points (three, closed), or a point that is not three
## numbers, is said in [param warnings] and left out.
static func parse(config: Dictionary, key: String, warnings: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var listed: Variant = config.get(key, [])
	if not listed is Array:
		warnings.append("\"%s\" in level.json is not a list" % key)
		return out
	for index in (listed as Array).size():
		var entry: Variant = listed[index]
		var raw: Variant = entry.get("points", []) if entry is Dictionary else null
		var closed := entry is Dictionary and key == "waters" and bool(entry.get("closed", false))
		if not raw is Array or (raw as Array).size() < (3 if closed else 2):
			warnings.append("%s %d has too few points: left out" % [key, index])
			continue
		var points := PackedVector2Array()
		var widths := PackedFloat32Array()
		for point: Variant in raw:
			if not point is Array or (point as Array).size() != 3 or (point as Array).any(func(n: Variant) -> bool: return not (n is float or n is int)):
				points.clear()
				break
			points.append(Vector2(float(point[0]), float(point[1])))
			widths.append(float(point[2]))
		if points.is_empty():
			warnings.append("%s %d has a point that is not [x, y, width]: left out" % [key, index])
			continue
		var kind := "water"
		if key == "roads":
			kind = str(entry.get("kind", "dirt"))
			if kind not in ["dirt", "stone"]:
				warnings.append("road %d is %s, not dirt or stone: dirt" % [index, kind])
				kind = "dirt"
		out.append({"points": points, "widths": widths, "closed": closed, "kind": kind, "curve": sample(points, widths, closed)})
	return out


## [param points] and [param widths] as level.json writes them:
## [[x, y, width], ...], to two places.
static func to_json(points: PackedVector2Array, widths: PackedFloat32Array) -> Array:
	var out := []
	for i in points.size():
		out.append([snappedf(points[i].x, 0.01), snappedf(points[i].y, 0.01), snappedf(widths[i] if i < widths.size() else 0.0, 0.01)])
	return out


static func _at(points: PackedVector2Array, i: int, closed: bool) -> Vector2:
	var count := points.size()
	if closed:
		return points[posmod(i, count)]
	if i < 0:
		return 2.0 * points[0] - points[1]
	if i >= count:
		return 2.0 * points[count - 1] - points[count - 2]
	return points[i]


static func _width_at(widths: PackedFloat32Array, i: int, closed: bool) -> float:
	if widths.is_empty():
		return 0.0
	return widths[posmod(i, widths.size())] if closed else widths[clampi(i, 0, widths.size() - 1)]


## A centripetal Catmull-Rom (alpha 0.5) from [param p1] to [param p2] at
## [param t] (Barry and Goldman's pyramid).
static func _centripetal(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t0 := 0.0
	var t1 := t0 + maxf(sqrt(p0.distance_to(p1)), 0.0001)
	var t2 := t1 + maxf(sqrt(p1.distance_to(p2)), 0.0001)
	var t3 := t2 + maxf(sqrt(p2.distance_to(p3)), 0.0001)
	var u := lerpf(t1, t2, t)
	var a1 := p0 * ((t1 - u) / (t1 - t0)) + p1 * ((u - t0) / (t1 - t0))
	var a2 := p1 * ((t2 - u) / (t2 - t1)) + p2 * ((u - t1) / (t2 - t1))
	var a3 := p2 * ((t3 - u) / (t3 - t2)) + p3 * ((u - t2) / (t3 - t2))
	var b1 := a1 * ((t2 - u) / (t2 - t0)) + a2 * ((u - t0) / (t2 - t0))
	var b2 := a2 * ((t3 - u) / (t3 - t1)) + a3 * ((u - t1) / (t3 - t1))
	return b1 * ((t2 - u) / (t2 - t1)) + b2 * ((u - t1) / (t2 - t1))


## A width between [param w1] and [param w2] at [param t], eased by its
## neighbours (a Catmull-Rom in one dimension, kept within the two).
static func _hermite(w0: float, w1: float, w2: float, w3: float, t: float) -> float:
	var value := 0.5 * (2.0 * w1 + (w2 - w0) * t + (2.0 * w0 - 5.0 * w1 + 4.0 * w2 - w3) * t * t + (3.0 * w1 - w0 - 3.0 * w2 + w3) * t * t * t)
	return clampf(value, minf(w1, w2), maxf(w1, w2))


## The shore of [param cells] (a region of cells, four-way joined) as a
## closed curve's control points (for "waters" closed): its outline (the
## cells' squares' outer edges, the longest loop of them) cut at each
## edge's middle, so no corner of the grid is left, then the fewest points
## within [param tolerance] cells of that (Douglas-Peucker, round the loop),
## at least four. A closed curve through them (sample, cells) holds about
## the region's cells. [] for an empty region.
static func trace(cells: Dictionary, tolerance := 0.6) -> PackedVector2Array:
	var none := PackedVector2Array()
	if cells.is_empty():
		return none
	# Each outer edge, clockwise round its cell, from corner to corner.
	var next_of := {}
	for cell: Vector2i in cells:
		var x := float(cell.x)
		var y := float(cell.y)
		var corners := [Vector2(x - 0.5, y - 0.5), Vector2(x + 0.5, y - 0.5), Vector2(x + 0.5, y + 0.5), Vector2(x - 0.5, y + 0.5)]
		var sides: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
		for k in 4:
			if not cells.has(cell + sides[k]):
				next_of[corners[k]] = corners[(k + 1) % 4]
	# Chained into loops; the longest is the outline.
	var best: Array = []
	var left := next_of.duplicate()
	while not left.is_empty():
		var start: Vector2 = left.keys()[0]
		var loop: Array = [start]
		var at: Vector2 = left[start]
		left.erase(start)
		while at != start and left.has(at):
			loop.append(at)
			var after: Vector2 = left[at]
			left.erase(at)
			at = after
		if loop.size() > best.size():
			best = loop
	var middles := PackedVector2Array()
	for i in best.size():
		middles.append((best[i] + best[(i + 1) % best.size()]) / 2.0)
	if middles.size() <= 4:
		return middles
	# Douglas-Peucker round the loop: split at the two points farthest apart.
	var far := 0
	for i in middles.size():
		if middles[i].distance_to(middles[0]) > middles[far].distance_to(middles[0]):
			far = i
	var first := _simplify(middles.slice(0, far + 1), tolerance)
	var back := middles.slice(far)
	back.append(middles[0])
	var second := _simplify(back, tolerance)
	first.remove_at(first.size() - 1)
	second.remove_at(second.size() - 1)
	first.append_array(second)
	if first.size() < 4:
		var even := PackedVector2Array()
		for k in 4:
			even.append(middles[k * middles.size() / 4])
		return even
	return first


## [param line]'s fewest points within [param tolerance] of it
## (Douglas-Peucker), its ends kept.
static func _simplify(line: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	if line.size() < 3:
		return line
	var far := 0.0
	var at := 0
	for i in range(1, line.size() - 1):
		var gap := line[i].distance_to(Geometry2D.get_closest_point_to_segment(line[i], line[0], line[-1]))
		if gap > far:
			far = gap
			at = i
	if far <= tolerance:
		return PackedVector2Array([line[0], line[-1]])
	var head := _simplify(line.slice(0, at + 1), tolerance)
	var tail := _simplify(line.slice(at), tolerance)
	head.remove_at(head.size() - 1)
	head.append_array(tail)
	return head
