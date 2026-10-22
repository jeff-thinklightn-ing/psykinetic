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
			var width := maxi(1, int(shape.get("width", 1)))
			var side := Vector2(-facing.y, facing.x)
			var seen := {}
			for step in range(1, int(length) * 2 + 1):
				var along := facing * (step * 0.5)
				for lane in width:
					var offset := along + side * (lane - (width - 1) * 0.5)
					var cell := origin + Vector2i(roundi(offset.x), roundi(offset.y))
					if cell != origin and not seen.has(cell) and Vector2(cell - origin).length() <= length + REACH_SLACK:
						seen[cell] = true
						out.append(cell)
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
