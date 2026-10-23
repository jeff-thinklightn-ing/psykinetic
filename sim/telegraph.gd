class_name Telegraph
extends RefCounted
## A danger area on the ground before a blow lands (decision 602; every
## boss's): a shape, and the cells it covers. The one function cells() says
## both what the views draw and who the blow strikes, so what is seen is what
## hits. Pure geometry here; World.telegraph_cells clips it to the terrain
## (walls, closed doors, ground that is not walkable).
##
## A shape is a Dictionary: {kind: "cone" | "line" | "ring", origin: [x, y]
## (a cell), facing: [x, y] (any angle; normalised here), length: cells,
## half_angle: degrees (a cone), width: cells (a line), inner: cells (a
## ring)}.

const KINDS := ["cone", "line", "ring"]
## A cell is in a cone or a ring when its centre is within length plus this
## of the origin's (a cone of 2 takes the knight's-move cells, not the far
## corners).
const REACH_SLACK := 0.25
## A line takes the centres strictly inside its band, this much in from
## half its width, so a centre on the band's edge is never in doubt.
const LINE_EDGE := 0.001
## The most an outline's chord falls short of its arc, in cells: under the
## nearest a centre comes to a reach (0.0625 / (2 x reach)).
const ARC_SAG := 0.001


## [param shape]'s cells, the origin's own never among them, each once, in
## no promised order but the same every call; [] for a shape that does not
## read.
static func cells(shape: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not valid(shape):
		return out
	var origin := origin_of(shape)
	var facing := facing_of(shape)
	var length := float(shape["length"])
	var reach := ceili(length + REACH_SLACK)
	match str(shape["kind"]):
		"cone", "ring":
			var half := deg_to_rad(float(shape.get("half_angle", 180.0)))
			var inner := float(shape.get("inner", 0.0))
			for y in range(-reach, reach + 1):
				for x in range(-reach, reach + 1):
					var offset := Vector2(x, y)
					var far := offset.length()
					if far == 0.0 or far > length + REACH_SLACK or far <= inner:
						continue
					if str(shape["kind"]) == "cone" and absf(facing.angle_to(offset)) > half + 0.001:
						continue
					out.append(origin + Vector2i(x, y))
		"line":
			# Every centre within half its width of the line, ahead and no
			# further than length plus the slack: the band outline draws
			# (602 amended; it had rounded half-cell steps).
			var half := maxi(1, int(shape.get("width", 1))) * 0.5 - LINE_EDGE
			var side := Vector2(-facing.y, facing.x)
			var along := {}
			for y in range(-reach, reach + 1):
				for x in range(-reach, reach + 1):
					var offset := Vector2(x, y)
					var ahead := facing.dot(offset)
					if ahead > 0.0 and ahead <= length + REACH_SLACK and absf(side.dot(offset)) < half:
						out.append(origin + Vector2i(x, y))
						along[out[-1]] = ahead
			# In order along it, nearest first: World.telegraph_cells stops a
			# line at the first cell it cannot cross.
			out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return along[a] < along[b])
	return out


## [param shape] as drawn (decision 602 amended, smooth telegraphs): a polygon in cells about the
## origin cell's centre, so a body is struck exactly when its cell's centre
## is inside it (before World.telegraph_cells clips walls away). A cone's
## sector, a ring's annulus (its gap behind, if any) or a line's band; []
## for a shape that does not read. Its arcs are cut fine enough
## (ARC_SAG) that no centre falls between a chord and its arc.
static func outline(shape: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not valid(shape):
		return out
	var facing := facing_of(shape)
	var length := float(shape["length"]) + REACH_SLACK
	if str(shape["kind"]) == "line":
		var half := maxi(1, int(shape.get("width", 1))) * 0.5 - LINE_EDGE
		var side := Vector2(-facing.y, facing.x)
		for corner: Vector2 in [Vector2(0.0, -half), Vector2(length, -half), Vector2(length, half), Vector2(0.0, half)]:
			out.append(facing * corner.x + side * corner.y)
		return out
	var half_angle := PI if str(shape["kind"]) == "ring" else minf(deg_to_rad(float(shape.get("half_angle", 180.0))) + 0.001, PI)
	var inner := float(shape.get("inner", 0.0))
	var whole := half_angle >= PI
	var pieces := maxi(8, ceili(2.0 * half_angle / sqrt(8.0 * ARC_SAG / length)))
	for i in pieces + (0 if whole else 1):
		out.append(facing.rotated(-half_angle + 2.0 * half_angle * i / pieces) * length)
	if inner > 0.0:
		# The hole's edge just outside the inner radius, its chords outside
		# it too (a centre at inner is not struck).
		var hole := (inner + 0.001) / cos(PI / pieces)
		if whole:
			out.append(out[0])
		for i in range(pieces, -1, -1):
			out.append(facing.rotated(-half_angle + 2.0 * half_angle * i / pieces) * hole)
	elif not whole:
		out.append(Vector2.ZERO)
	return out


## Whether [param shape] reads: a known kind, an origin, a facing that is
## not zero, a length over 0.
static func valid(shape: Dictionary) -> bool:
	if str(shape.get("kind", "")) not in KINDS:
		return false
	var origin: Variant = shape.get("origin")
	var facing: Variant = shape.get("facing")
	if origin is not Array or origin.size() != 2 or facing is not Array or facing.size() != 2:
		return false
	if Vector2(float(facing[0]), float(facing[1])).length() < 0.001:
		return false
	return float(shape.get("length", 0.0)) > 0.0


static func origin_of(shape: Dictionary) -> Vector2i:
	return Vector2i(int(shape["origin"][0]), int(shape["origin"][1]))


static func facing_of(shape: Dictionary) -> Vector2:
	return Vector2(float(shape["facing"][0]), float(shape["facing"][1])).normalized()


## A cone: from [param origin] toward [param facing], [param length] cells,
## [param half_angle] degrees either side.
static func cone(origin: Vector2i, facing: Vector2, length: float, half_angle: float) -> Dictionary:
	return {"kind": "cone", "origin": [origin.x, origin.y], "facing": [facing.x, facing.y], "length": length,
		"half_angle": half_angle}


## A line: from [param origin] toward [param facing], [param length] cells
## long and [param width] wide.
static func line(origin: Vector2i, facing: Vector2, length: float, width := 1) -> Dictionary:
	return {"kind": "line", "origin": [origin.x, origin.y], "facing": [facing.x, facing.y], "length": length,
		"width": width}
