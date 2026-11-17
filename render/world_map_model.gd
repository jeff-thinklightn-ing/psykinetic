class_name WorldMapModel
extends RefCounted
## What the world map window draws, worked out from the plane and what the player knows, with no
## drawing in it (decision 968, ui's side; ui-design's mock4, variant B): each known outdoor
## area a box at its place on the world plane (WorldMap.plane_layout, decision 755), north up;
## a ring at the mouth of a plainly visible way down or out, and a chip with the level's name once
## that level is known, or a "?" on a short stub when it is not; a short bar where two known areas
## share an edge, and a "?" stub out of a side whose neighbour is not known; the labels on the
## player's picture, folded into one where they would overlap. Positions are world cells; the
## window turns them into pixels. Pure functions (the tests call them).

## The cues of a way that is not plainly visible: the map draws no ring, chip or stub for it.
const HIDDEN_CUES: Array[String] = ["none", "sealed"]
## The gap two boxes may have and still share an edge, in cells.
const EDGE_GAP := 3.0
## The compass sides a way's "side" names, as a unit step.
const SIDES := {"north": Vector2(0, -1), "south": Vector2(0, 1), "west": Vector2(-1, 0), "east": Vector2(1, 0)}


## Whether [param name] is known: every area is when none are told (the client before any world
## message), else the ones told and the one the player stands in.
static func is_known(name: String, known_areas: Dictionary, own: String) -> bool:
	return known_areas.is_empty() or known_areas.has(name) or name == own


## The names of the areas a box is drawn for, sorted: the plane's zones that are known, but a test
## level (Level.DEV_LEVELS, [param test_levels]) only where [param own] stands (the mend of 445
## amended (3), kept).
static func shown(layout: Dictionary, known_areas: Dictionary, own: String, test_levels: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for name: String in (layout.get("zones", {}) as Dictionary):
		if not is_known(name, known_areas, own):
			continue
		if name != own and (name in Level.DEV_LEVELS or name in test_levels):
			continue
		out.append(name)
	out.sort()
	return out


## [param name]'s box in world cells.
static func box_of(layout: Dictionary, name: String) -> Rect2:
	var zone: Dictionary = (layout.get("zones", {}) as Dictionary).get(name, {})
	return Rect2(zone["rect"]) if zone.has("rect") else Rect2()


## Where in world cells [param way]'s mouth is, on [param from]'s box ("at" is a cell of the
## zone); the middle of the cell.
static func mouth_cell(layout: Dictionary, from: String, way: Dictionary) -> Vector2:
	return box_of(layout, from).position + Vector2(way.get("at", Vector2i.ZERO)) + Vector2(0.5, 0.5)


## A way is drawn at all: not hidden and not closed (a closed link, hidden ones with it, gives
## nothing away: 608), and of a cue a player sees.
static func way_visible(way: Dictionary) -> bool:
	return not bool(way.get("hidden", false)) and not bool(way.get("closed", false)) \
			and str(way.get("cue", "none")) not in HIDDEN_CUES


## The rings at the mouths of ways down or out of a shown area, as [{area, at (world cell), level,
## known}], one for each mouth (a cell): a plainly visible link to a level that is no box of the
## map (a level below, or an area not on the plane).
static func mouths(layout: Dictionary, ways: Array[Dictionary], known_areas: Dictionary, own: String, areas: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for way: Dictionary in ways:
		if str(way.get("kind", "")) != "link" or not way_visible(way):
			continue
		var from := str(way["from"])
		var to := str(way["to"])
		if from not in areas or to in areas:
			continue
		var at := mouth_cell(layout, from, way)
		if seen.has(at):
			continue
		seen[at] = true
		out.append({"area": from, "at": at, "level": to, "known": is_known(to, known_areas, own)})
	return out


## The chips of known levels below, as [{level, at (the mouth, world cell), depth (0 for the
## level the mouth opens on, 1 for the one under it ...)}]: the level of each mouth in [param
## mouths] that is known, then the known levels the plane reaches through it (layout "doors",
## [param known_areas] told), each one under the last.
static func chips(layout: Dictionary, mouths_drawn: Array[Dictionary], known_areas: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var doors: Dictionary = layout.get("doors", {})
	for mouth: Dictionary in mouths_drawn:
		if not bool(mouth["known"]):
			continue
		out.append({"level": mouth["level"], "at": mouth["at"], "depth": 0, "area": mouth["area"]})
		var deeper: Array[String] = []
		for level: String in doors:
			if level == mouth["level"] or not is_known(level, known_areas, ""):
				continue
			for door: Dictionary in doors[level]:
				var via: Array = door["via"]
				if not via.is_empty() and str(via[0]) == str(mouth["level"]) and Vector2(door["at"]) == (mouth["at"] as Vector2) - Vector2(0.5, 0.5) \
						and level not in deeper:
					deeper.append(level)
		deeper.sort_custom(func(a: String, b: String) -> bool: return _depth_of(doors, a) < _depth_of(doors, b))
		for i in deeper.size():
			out.append({"level": deeper[i], "at": mouth["at"], "depth": i + 1, "area": mouth["area"]})
	return out


static func _depth_of(doors: Dictionary, level: String) -> int:
	var best := 99
	for door: Dictionary in doors.get(level, []):
		best = mini(best, (door["via"] as Array).size())
	return best


## The "?" stubs, as [{at (world cell where the stub leaves), dir (the unit step out of the box; the
## window gives the stub its length in canvas units), kind: "edge"|"link"}]: one out of the middle
## of a shown area's side whose neighbour is no known area, and one out of the ring of a mouth
## whose level is not known.
static func stubs(layout: Dictionary, ways: Array[Dictionary], mouths_drawn: Array[Dictionary], known_areas: Dictionary, own: String, areas: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for way: Dictionary in ways:
		if str(way.get("kind", "")) != "edge":
			continue
		var from := str(way["from"])
		var to := str(way["to"])
		var side := str(way.get("side", ""))
		if from not in areas or to in areas or is_known(to, known_areas, own) or not SIDES.has(side):
			continue
		var box := box_of(layout, from)
		var step: Vector2 = SIDES[side]
		var at := box.get_center() + step * box.size * 0.5
		if seen.has([from, side]):
			continue
		seen[[from, side]] = true
		out.append({"at": at, "dir": step, "kind": "edge"})
	for mouth: Dictionary in mouths_drawn:
		if bool(mouth["known"]):
			continue
		var box := box_of(layout, str(mouth["area"]))
		var at: Vector2 = mouth["at"]
		out.append({"at": at, "dir": outward(box, at), "kind": "link"})
	return out


## The unit step out of [param box] at [param at]: the side of the box [param at] is nearest.
static func outward(box: Rect2, at: Vector2) -> Vector2:
	var left := at.x - box.position.x
	var right := box.end.x - at.x
	var top := at.y - box.position.y
	var bottom := box.end.y - at.y
	var nearest := minf(minf(left, right), minf(top, bottom))
	if nearest == top:
		return Vector2(0, -1)
	if nearest == bottom:
		return Vector2(0, 1)
	return Vector2(-1, 0) if nearest == left else Vector2(1, 0)


## The short brass bars where two shown areas share an edge, as [{a, b, at (world cell, the
## middle of the shared part), vertical (the bar runs up and down)}].
static func bars(layout: Dictionary, areas: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in areas.size():
		for j in range(i + 1, areas.size()):
			var a := box_of(layout, areas[i])
			var b := box_of(layout, areas[j])
			var across := minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y)
			var along := minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
			if across > 0.0 and (absf(a.end.x - b.position.x) <= EDGE_GAP or absf(b.end.x - a.position.x) <= EDGE_GAP):
				var x := (a.end.x + b.position.x) * 0.5 if absf(a.end.x - b.position.x) <= EDGE_GAP else (b.end.x + a.position.x) * 0.5
				out.append({"a": areas[i], "b": areas[j], "at": Vector2(x, maxf(a.position.y, b.position.y) + across * 0.5), "vertical": true})
			elif along > 0.0 and (absf(a.end.y - b.position.y) <= EDGE_GAP or absf(b.end.y - a.position.y) <= EDGE_GAP):
				var y := (a.end.y + b.position.y) * 0.5 if absf(a.end.y - b.position.y) <= EDGE_GAP else (b.end.y + a.position.y) * 0.5
				out.append({"a": areas[i], "b": areas[j], "at": Vector2(maxf(a.position.x, b.position.x) + along * 0.5, y), "vertical": false})
	return out


## The rect in world cells that holds every box.
static func bounds(boxes: Array[Rect2]) -> Rect2:
	var out := Rect2()
	var first := true
	for box: Rect2 in boxes:
		out = box if first else out.merge(box)
		first = false
	return out


## The scale (pixels to a cell) at which [param world] fits inside [param room] with [param margin]
## pixels to spare on each side (room for the "?" stubs); 1.0 for an empty world. No upper cap: one
## known area fills the room.
static func fit_scale(world: Rect2, room: Vector2, margin: float) -> float:
	if world.size.x <= 0.0 or world.size.y <= 0.0:
		return 1.0
	return maxf(minf((room.x - margin * 2.0) / world.size.x, (room.y - margin * 2.0) / world.size.y), 0.01)


## The place labels on a picture, with those that would overlap folded into one. [param labels]
## are [{id, at (screen, where the ring is), size (the label's rect size)}]; [param keep_off]
## rects (chips, the "you" mark) no label may cover; [param name_of] is called with a group's
## ids and its middle ring (a screen point) for its words; [param measure] gives the size of
## words. Each label stands beside its ring (right, left, above or below, the first clear of
## keep_off; none clear: it is left out, the ring staying). Returns [{ids, rect, at, name, folded}]:
## a lone label as it was, a folded group's rect under the words name_of gave, and the groups
## whose rects meet joined until none do.
static func fold(labels: Array[Dictionary], keep_off: Array[Rect2], gap: float, name_of: Callable, measure: Callable, inside := Rect2()) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	for label: Dictionary in labels:
		var rect := _placed(label["at"], label["size"], keep_off, gap, inside)
		if rect.size == Vector2.ZERO:
			continue
		groups.append({"ids": [label["id"]], "rect": rect, "at": label["at"], "name": str(label.get("name", "")), "folded": false,
			"ring_size": label["size"]})
	var merged := true
	while merged:
		merged = false
		for i in groups.size():
			for j in range(i + 1, groups.size()):
				if (groups[i]["rect"] as Rect2).intersects(groups[j]["rect"]):
					groups[i] = _join(groups[i], groups[j], keep_off, gap, name_of, measure, inside)
					groups.remove_at(j)
					merged = true
					break
			if merged:
				break
	return groups


## One group of two, its words from [param name_of] and its rect beside the middle of their rings.
static func _join(a: Dictionary, b: Dictionary, keep_off: Array[Rect2], gap: float, name_of: Callable, measure: Callable, inside: Rect2) -> Dictionary:
	var ids: Array = (a["ids"] as Array) + (b["ids"] as Array)
	var weight_a := float((a["ids"] as Array).size())
	var weight_b := float((b["ids"] as Array).size())
	var at: Vector2 = ((a["at"] as Vector2) * weight_a + (b["at"] as Vector2) * weight_b) / (weight_a + weight_b)
	var words := str(name_of.call(ids, at))
	var size: Vector2 = measure.call(words)
	var rect := _placed(at, size, keep_off, gap, inside)
	if rect.size == Vector2.ZERO:
		rect = Rect2(at + Vector2(gap, -size.y * 0.5), size)
	return {"ids": ids, "rect": rect, "at": at, "name": words, "folded": true, "ring_size": size}


## The rect a label of [param size] takes beside a ring at [param at]: right, left, above, below,
## the first that covers none of [param keep_off] and, where [param inside] is given, lies inside it
## (a label stays inside its own box), at [param gap] from the ring and, none clear there, stepped out
## to twice and then three times the gap (a newcomer's two places keep their names); an empty rect
## for none.
static func _placed(at: Vector2, size: Vector2, keep_off: Array[Rect2], gap: float, inside := Rect2()) -> Rect2:
	for step in [1.0, 2.0, 3.0]:
		var away: float = gap * step
		for rect: Rect2 in [Rect2(at + Vector2(away, -size.y * 0.5), size), Rect2(at + Vector2(-away - size.x, -size.y * 0.5), size),
				Rect2(at + Vector2(-size.x * 0.5, -away - size.y), size), Rect2(at + Vector2(-size.x * 0.5, away), size)]:
			if inside.size != Vector2.ZERO and not inside.encloses(rect):
				continue
			if not keep_off.any(func(off: Rect2) -> bool: return off.intersects(rect)):
				return rect
	return Rect2()
