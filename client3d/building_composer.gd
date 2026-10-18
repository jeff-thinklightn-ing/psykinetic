class_name BuildingComposer
extends RefCounted
## Draws a building of a kind (Level.kinds, decision 488) from its blocks,
## seeded (decision 489): the grid is the rules and the look need not show
## it, so nothing here keeps to whole metres. Each block's roof by its role:
## the main block's a gable along its longer side at the kind's eaves; a
## wing's a gable a little lower; a lean-to's, an outshot's or a bay's a
## single slope rising to the block it leans on, its high side under that
## one's eaves. Every roof reaches past its walls (overhang), sags a little
## in the middle of its ridge, and is set a few centimetres off true; a
## round kind's one faceted cone over all its blocks. A chimney stands at a
## gable end of a house's main block when its seed says so (art-kit's
## chimney.stone if it is there, else a stack of the stone set). A ruin has
## no roof, perhaps its chimney.
## The walls and floors are not drawn here: they are the map's edges, the
## terrain's runs in the kind's sets (Client3D).
## What it makes is kept by kind, size, seed, facing and ruin (compose), so
## a street of one kind costs one build of each look; the copies share
## their meshes. Each block draws from its own seeded stream (_stream), its
## eaves first, so the walls under it are drawn to them (wall_heights)
## without building the roof.

## A roof's rise over its half-span, its overhang and its sag over its
## length, each seeded between these.
const RISE := Vector2(0.75, 1.1)
const REACH := Vector2(0.3, 0.5)
const SAG := Vector2(0.01, 0.025)
## How far below the main block's eaves a wing's are, and a lean-to's low
## eave; a lean-to's high side keeps LEAN_TUCK under them.
const WING_DROP := Vector2(0.25, 0.5)
const LEAN_DROP := Vector2(0.7, 1.0)
const LEAN_TUCK := 0.15
## A whole roof's tilt off true (radians) and each block's shift (m).
const TILT := 0.012
const SHIFT := 0.05
const THICK := 0.15
## Lengthwise steps of a slope, so its sag shows.
const STEPS := 8
## A round roof's facets and how far each point strays (of the radius).
const FACETS := 11
const FACET_STRAY := 0.05
## The kinds that may have a chimney, and how likely.
const CHIMNEYS := {"house": 0.7, "l_house": 0.7, "house_leanto": 0.6, "house_wing": 0.7, "two_storey": 0.8,
	"cottage": 0.8, "inn": 0.9, "hall": 0.6, "longhouse": 0.5, "hut": 0.3, "healers_hut": 0.5}
const CHIMNEY := Vector3(0.75, 0.9, 0.65)
## The roles of blocks roofed with a single slope.
const LEANING: Array[String] = ["leanto", "outshot", "bay"]
## The stream salt for what is the building's own, not a block's.
const WHOLE := 1000

## Each look made, packed: a resource, so the cache holds no nodes (freed
## with the script, nothing left at exit), its meshes shared by every copy.
static var _made: Dictionary[String, PackedScene] = {}


## [param building] (Level's, with its kind) drawn: a Node3D whose origin is
## its box's top-left cell's middle at its ground, holding "roof" (every
## roof, what hides while the player is inside; none on a ruin) and
## "parts" (a chimney). [param roof_set] names the roof's material set.
static func compose(building: Dictionary, roof_set: String) -> Node3D:
	var key := "%s|%s|%d|%s|%s|%s|%s" % [building["kind"], building["size"], building["seed"], building["facing"],
		building.get("ruined", false), building["eaves"], roof_set]
	if not _made.has(key):
		var built := _build(building, roof_set)
		for node in built.find_children("*", "", true, false):
			node.owner = built
		var packed := PackedScene.new()
		packed.pack(built)
		built.free()
		_made[key] = packed
	return _made[key].instantiate()


## Forgets what was made (a test, or new art).
static func forget() -> void:
	_made.clear()


## Each outline edge of [param building] -> the height its wall is drawn
## to: the eaves of the block whose cell it bounds (a wing's lower, a
## lean-to's its low eave), so no roof sits under its walls' tops.
static func wall_heights(building: Dictionary) -> Dictionary[Vector3i, float]:
	var out: Dictionary[Vector3i, float] = {}
	var blocks: Array = building["blocks"]
	var heights: Array[float] = []
	for index in blocks.size():
		heights.append(block_eaves(building, index))
	for key in Level.building_outline(building):
		for cell in Terrain.edge_cells(key):
			var index := blocks.find_custom(func(block: Rect2i) -> bool: return block.has_point(cell))
			if index >= 0:
				out[key] = heights[index]
				break
	return out


## Block [param index]'s eaves: the kind's for its main block (the largest)
## and for a round kind's every block; a lean-to's low eave, a wing's a
## little lower, as its stream draws first.
static func block_eaves(building: Dictionary, index: int) -> float:
	var eaves := float(building["eaves"])
	var blocks: Array = building["blocks"]
	if index == _main_of(blocks) or str(building.get("roof", "gable")) == "round":
		return eaves
	var rng := _stream(building, index)
	if _leaning(building, index):
		return eaves - rng.randf_range(LEAN_DROP.x, LEAN_DROP.y)
	return eaves - rng.randf_range(WING_DROP.x, WING_DROP.y)


## Whether block [param index] is a single slope leaning on another: its
## role a lean-to's, an outshot's or a bay's, and another block beside it.
static func _leaning(building: Dictionary, index: int) -> bool:
	var roles: Array = building.get("roles", [])
	return index < roles.size() and str(roles[index]) in LEANING 			and _leans_on(building["blocks"][index], building["blocks"]) != Vector2i.ZERO


## [param building]'s seeded stream for [param salt]: a block's index, or
## WHOLE for what is the building's own (its tilt, its chimney).
static func _stream(building: Dictionary, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(building["seed"]), salt])
	return rng


## The index of [param blocks]' largest (the first of the largest).
static func _main_of(blocks: Array) -> int:
	var best := 0
	for index in blocks.size():
		if (blocks[index] as Rect2i).get_area() > (blocks[best] as Rect2i).get_area():
			best = index
	return best


static func _build(building: Dictionary, roof_set: String) -> Node3D:
	var rng := _stream(building, WHOLE)
	var rect: Rect2i = building["rect"]
	var blocks: Array = building["blocks"]
	var eaves := float(building["eaves"])
	var out := Node3D.new()
	out.name = "Composed"
	var parts := Node3D.new()
	parts.name = "parts"
	out.add_child(parts)
	var main: Rect2i = blocks[_main_of(blocks)]
	var ruined: bool = building.get("ruined", false)
	if not ruined:
		var roof := Node3D.new()
		roof.name = "roof"
		roof.rotation = Vector3(rng.randf_range(-TILT, TILT), 0.0, rng.randf_range(-TILT, TILT))
		out.add_child(roof)
		var material := Client3D._roof_material(roof_set)
		var gable := Client3D._wall_material(str(building.get("wall_set", Client3D.DEFAULT_SET))).duplicate() as StandardMaterial3D
		gable.cull_mode = BaseMaterial3D.CULL_DISABLED
		if str(building.get("roof", "gable")) == "round":
			roof.add_child(_cone(Vector2(rect.size), eaves, rng, material))
		else:
			for index in blocks.size():
				var piece := _block_roof(building, index, material, gable)
				piece.name = "Roof_%d" % index
				roof.add_child(piece)
	var odds := float(CHIMNEYS.get(str(building["kind"]), 0.0)) * (0.6 if ruined else 1.0)
	if rng.randf() < odds and str(building.get("roof", "gable")) != "round":
		parts.add_child(_chimney(main, rect, eaves, rng))
	return out


## Block [param index]'s roof by its role, placed in the building's frame
## (its box's top-left cell's middle at the origin), from its own stream.
static func _block_roof(building: Dictionary, index: int, material: Material, gable: Material) -> Node3D:
	var blocks: Array = building["blocks"]
	var block: Rect2i = blocks[index]
	var rect: Rect2i = building["rect"]
	var eaves := float(building["eaves"])
	var is_main := index == _main_of(blocks)
	var rng := _stream(building, index)
	var at := eaves if is_main else block_eaves(building, index)
	if not is_main:
		rng.randf()  # Its eaves' draw, made by block_eaves.
	var middle := Vector2(block.position - rect.position) + Vector2(block.size - Vector2i.ONE) * 0.5
	var reach := rng.randf_range(REACH.x, REACH.y)
	var holder := Node3D.new()
	var leans := _leans_on(block, blocks)
	if not is_main and _leaning(building, index):
		# A single slope, its high side toward the block it leans on.
		var across := float(block.size.x if leans.x != 0 else block.size.y)
		var along := float(block.size.y if leans.x != 0 else block.size.x)
		var low := at
		var rise := maxf(eaves - LEAN_TUCK - low, 0.3)
		holder.add_child(_slopes(across, along, rise, reach, rng.randf_range(SAG.x, SAG.y) * along, true, material, gable))
		holder.position = Vector3(middle.x, low, middle.y)
		holder.rotation.y = {Vector2i(1, 0): 0.0, Vector2i(-1, 0): PI, Vector2i(0, 1): -PI * 0.5, Vector2i(0, -1): PI * 0.5}[leans]
	else:
		var along_x := block.size.x > block.size.y
		var span := Vector2(block.size.y, block.size.x) if along_x else Vector2(block.size)
		var rise := span.x * 0.5 * rng.randf_range(RISE.x, RISE.y)
		holder.add_child(_slopes(span.x, span.y, rise, reach, rng.randf_range(SAG.x, SAG.y) * span.y, false, material, gable))
		holder.position = Vector3(middle.x, at, middle.y)
		holder.rotation.y = PI * 0.5 if along_x else 0.0
	holder.position += Vector3(rng.randf_range(-SHIFT, SHIFT), 0.0, rng.randf_range(-SHIFT, SHIFT))
	return holder


## The side of [param block] (a unit step) most of whose outside cells are
## another block's: what a lean-to leans on; ZERO for none.
static func _leans_on(block: Rect2i, blocks: Array) -> Vector2i:
	var best := Vector2i.ZERO
	var most := 0
	for side: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var touching := 0
		for cell in Level.rect_cells(block):
			var next := cell + side
			if block.has_point(next):
				continue
			for other: Rect2i in blocks:
				if other != block and other.has_point(next):
					touching += 1
					break
		if touching > most:
			most = touching
			best = side
	return best


## A roof's slopes across x and along z, its eaves at y 0: a gable from
## both eaves to the ridge over x = 0, or a lean-to ([param mono]) from its
## low eave at -x to its high side at +x; reaching [param reach] past the
## walls each way, the ridge sagging [param sag] in the middle of its
## length (the eaves do not), a top THICK above its underside; and its
## ends closed down to the eaves in [param gable].
static func _slopes(across: float, along: float, rise: float, reach: float, sag: float, mono: bool,
		material: Material, gable: Material) -> Node3D:
	var half := across * 0.5
	var length := along + reach * 2.0
	var height := func(x: float, z: float) -> float:
		var h := rise * (x + half) / across if mono else rise * (1.0 - absf(x) / half)
		var t := clampf(h / rise, 0.0, 1.0)
		var u := 2.0 * z / length
		return h - sag * (1.0 - u * u) * t
	var xs: Array[float] = [-half - reach, half + reach]
	if not mono:
		xs.insert(1, 0.0)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in xs.size() - 1:
		for j in STEPS:
			var z0 := -length * 0.5 + length * j / STEPS
			var z1 := -length * 0.5 + length * (j + 1) / STEPS
			for lift in [THICK, 0.0]:
				var corners := [Vector3(xs[i], height.call(xs[i], z0) + lift, z0), Vector3(xs[i], height.call(xs[i], z1) + lift, z1),
					Vector3(xs[i + 1], height.call(xs[i + 1], z1) + lift, z1), Vector3(xs[i + 1], height.call(xs[i + 1], z0) + lift, z0)]
				for k in [0, 1, 2, 0, 2, 3]:
					var corner: Vector3 = corners[k]
					tool.set_uv(Vector2(corner.z + length * 0.5, absf(corner.x)) / 2.0)
					tool.add_vertex(corner)
	tool.generate_normals()
	var out := Node3D.new()
	var slopes := MeshInstance3D.new()
	slopes.name = "Slopes"
	slopes.mesh = tool.commit()
	slopes.material_override = material
	out.add_child(slopes)
	var ends := SurfaceTool.new()
	ends.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in [-along * 0.5, along * 0.5]:
		var points: Array[Vector3] = [Vector3(-half, 0.0, z), Vector3(half, 0.0, z)]
		points.append(Vector3(half, height.call(half, z), z) if mono else Vector3(0.0, height.call(0.0, z), z))
		for point in points:
			ends.set_uv(Vector2(point.x, -point.y) / Client3D.WALL_TILE)
			ends.add_vertex(point)
	ends.generate_normals()
	var gables := MeshInstance3D.new()
	gables.name = "Gables"
	gables.mesh = ends.commit()
	gables.material_override = gable
	out.add_child(gables)
	return out


## A round kind's roof: a cone of FACETS faces over its box (its blocks'
## cells inside it), its points straying a little, reaching past the walls.
static func _cone(size: Vector2, eaves: float, rng: RandomNumberGenerator, material: Material) -> Node3D:
	var radius := maxf(size.x, size.y) * 0.5 + rng.randf_range(REACH.x, REACH.y)
	var apex := Vector3(rng.randf_range(-SHIFT, SHIFT), radius * rng.randf_range(1.0, 1.3), rng.randf_range(-SHIFT, SHIFT))
	var drop := radius - maxf(size.x, size.y) * 0.5
	var rim: Array[Vector3] = []
	for k in FACETS:
		var angle := TAU * k / FACETS
		var r := radius * (1.0 + rng.randf_range(-FACET_STRAY, FACET_STRAY))
		rim.append(Vector3(cos(angle) * r, -drop * 0.6, sin(angle) * r))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in FACETS:
		for point: Vector3 in [rim[k], rim[(k + 1) % FACETS], apex]:
			tool.set_uv(Vector2(point.x, point.z) / 2.0)
			tool.add_vertex(point)
	tool.generate_normals()
	var cone := MeshInstance3D.new()
	cone.name = "Cone"
	cone.mesh = tool.commit()
	cone.material_override = material
	var holder := Node3D.new()
	holder.name = "Roof_0"
	holder.position = Vector3((size.x - 1.0) * 0.5, eaves, (size.y - 1.0) * 0.5)
	holder.add_child(cone)
	return holder


## A chimney at one gable end of [param main], a little off its middle,
## standing from the ground to over its ridge: art-kit's chimney.stone on
## the roof line if it is there, else a stack and cap of the stone set.
static func _chimney(main: Rect2i, rect: Rect2i, eaves: float, rng: RandomNumberGenerator) -> Node3D:
	var middle := Vector2(main.position - rect.position) + Vector2(main.size - Vector2i.ONE) * 0.5
	var along_x := main.size.x > main.size.y
	var end := (float(main.size.x if along_x else main.size.y) * 0.5 - 0.35) * (1.0 if rng.randf() < 0.5 else -1.0)
	var off := rng.randf_range(-0.3, 0.3)
	var at := middle + (Vector2(end, off) if along_x else Vector2(off, end))
	var ridge := eaves + float(mini(main.size.x, main.size.y)) * 0.5 * RISE.y
	var out := Node3D.new()
	out.name = "Chimney"
	out.position = Vector3(at.x, 0.0, at.y)
	out.rotation.y = rng.randf_range(-0.05, 0.05)
	if ArtKit.has("chimney.stone"):
		var piece := ArtKit.instance("chimney.stone")
		piece.position.y = eaves
		out.add_child(piece)
		return out
	var stone := Client3D._wall_material("stone")
	var tall := ridge + rng.randf_range(0.4, 0.8)
	for part: Array in [[Vector3(CHIMNEY.x, tall, CHIMNEY.z), tall * 0.5], [Vector3(CHIMNEY.x + 0.12, 0.14, CHIMNEY.z + 0.12), tall + 0.07]]:
		var box := MeshInstance3D.new()
		var shape := BoxMesh.new()
		shape.size = part[0]
		box.mesh = shape
		box.material_override = stone
		box.position.y = part[1]
		out.add_child(box)
	return out
