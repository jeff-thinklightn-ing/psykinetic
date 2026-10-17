class_name PineStands
extends RefCounted
## The border's pine stands (decision 369, Jeff's design of 2026-10-17): past the forest's
## first ring, the band round an outdoor map is stands of pines on 2 x 2
## cells (art slot tree.pine_stand, its variants), crowded so their canopies
## bleed into one, over an open floor of needles. Drawing only, as the
## forest is.
##
## plan() packs the band: its cells in a hashed order, a stand wherever all
## four of its cells are free and FROM or more off the land, its variant one
## no stand beside it has where it can be, each turned a quarter at random
## and a little more, sized and nudged a little; the cells left between them
## have a tree of their own (Client3D._add_forest). The same cells make the
## same stands on every peer.
##
## Drawn only once the slot has art of its own or a fill, never as grey
## boxes; until then the forest is as it was. stand_in draws a stand made
## here instead (shots only, to tune the packing before the art).

const SLOT := "tree.pine_stand"
## The band's first ring off the land; ring 1 is the region's own edge.
const FROM := 2
## A stand with a cell this near the land is a node of its own, so it fades
## as a tree does between the camera and the player; the rest are drawn a
## MultiMesh a CHUNK, with no shadows.
const NEAR := 4
const CHUNK := 16
## Up to this much more than its quarter turn (radians), its height and
## width sized within these, nudged up to this far (cells).
const YAW := 0.21
const HEIGHT_SIZE := Vector2(0.9, 1.12)
const WIDTH_SIZE := Vector2(0.96, 1.04)
const NUDGE := 0.15
## How far the packing's sweep is jittered (cells): more leaves more
## cells between stands (1: about a tenth of the band; 3: a fifth).
const SWEEP_JITTER := 1.0
## The needles' floor, under the stands from FROM out (sppine.jpg).
const NEEDLES := Color("7a4e2c")
const FOOTPRINT: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]

## Shots only: stands drawn with a stand-in made here while the slot has no
## art (map_bench --stand-in).
static var stand_in := false
static var _meshes: Dictionary[int, Mesh] = {}


## Whether stands are drawn: the slot has art or a fill, or the stand-in is on.
static func drawn() -> bool:
	return stand_in or ArtKit.has(SLOT) and ArtKit.filled_by(SLOT) != "placeholder"


## How many variants to pick from.
static func variants() -> int:
	return 4 if stand_in and ArtKit.filled_by(SLOT) == "placeholder" else maxi(1, ArtKit.variant_count(SLOT))


## The stands on the band [param distance] says (each void cell's rings off
## the land), each {cell: its footprint's first (least) cell, variant (1..),
## turn (quarters), yaw, size (x across, y up), nudge (cells), near (its
## nearest cell's ring)}.
static func plan(distance: Dictionary[Vector2i, int], variant_count: int) -> Array[Dictionary]:
	# A sweep corner to corner, jittered: each stand packs against those
	# before it, as a row would, but the rows wander, so no grid shows.
	# (Sorted as Vector3s, key first: Array.sort's own compare, no lambda.)
	var order: Array[Vector3] = []
	for cell: Vector2i in distance:
		if distance[cell] >= FROM:
			order.append(Vector3(cell.x + cell.y + Client3D._roll(cell, 70) * SWEEP_JITTER, cell.x, cell.y))
	order.sort()
	var taken: Dictionary[Vector2i, int] = {}
	var out: Array[Dictionary] = []
	var offsets: Array[Vector2i] = [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]
	for entry in order:
		var cell := Vector2i(int(entry.y), int(entry.z))
		if taken.has(cell):
			continue
		var first := int(Client3D._roll(cell, 71) * 4.0)
		for k in 4:
			var corner := cell + offsets[(first + k) % 4]
			var fits := true
			for at in FOOTPRINT:
				if distance.get(corner + at, 0) < FROM or taken.has(corner + at):
					fits = false
					break
			if not fits:
				continue
			var stand := _stand(corner, distance, taken, out, variant_count)
			for at in FOOTPRINT:
				taken[corner + at] = out.size()
			out.append(stand)
			break
	return out


## The stand on [param corner]'s 2 x 2: a variant and turn unlike the stands
## beside it ([param taken], [param placed]) where it can be.
static func _stand(corner: Vector2i, distance: Dictionary[Vector2i, int], taken: Dictionary[Vector2i, int], placed: Array[Dictionary], variant_count: int) -> Dictionary:
	var side: Dictionary[int, bool] = {}
	var round_it: Dictionary[int, bool] = {}
	for y in range(-1, 3):
		for x in range(-1, 3):
			var at := corner + Vector2i(x, y)
			if not taken.has(at):
				continue
			var inside := x >= 0 and x <= 1 or y >= 0 and y <= 1
			if inside:
				side[taken[at]] = true
			round_it[taken[at]] = true
	var used_side: Dictionary[int, bool] = {}
	var used_round: Dictionary[int, bool] = {}
	for index in side:
		used_side[placed[index]["variant"]] = true
	for index in round_it:
		used_round[placed[index]["variant"]] = true
	var picks: Array[int] = []
	for variant in range(1, variant_count + 1):
		if not used_round.has(variant):
			picks.append(variant)
	if picks.is_empty():
		for variant in range(1, variant_count + 1):
			if not used_side.has(variant):
				picks.append(variant)
	if picks.is_empty():
		picks.assign(range(1, variant_count + 1))
	var variant := picks[int(Client3D._roll(corner, 72) * picks.size()) % picks.size()]
	# Its turn: one no stand beside it of the same variant has.
	var turns: Array[int] = [0, 1, 2, 3]
	for index in side:
		if placed[index]["variant"] == variant:
			turns.erase(placed[index]["turn"])
	if turns.is_empty():
		turns = [0, 1, 2, 3]
	var near := 1 << 20
	for at in FOOTPRINT:
		near = mini(near, distance[corner + at])
	return {"cell": corner, "variant": variant,
		"turn": turns[int(Client3D._roll(corner, 73) * turns.size()) % turns.size()],
		"yaw": (Client3D._roll(corner, 74) - 0.5) * 2.0 * YAW,
		"size": Vector2(lerpf(WIDTH_SIZE.x, WIDTH_SIZE.y, Client3D._roll(corner, 75)), lerpf(HEIGHT_SIZE.x, HEIGHT_SIZE.y, Client3D._roll(corner, 76))),
		"nudge": Vector2(Client3D._roll(corner, 77) - 0.5, Client3D._roll(corner, 78) - 0.5) * NUDGE * 2.0,
		"near": near}


## [param stand]'s place, turn and size, standing on y 0 (as the forest's
## trees do): its footprint's middle, nudged.
static func transform_of(stand: Dictionary) -> Transform3D:
	var corner: Vector2i = stand["cell"]
	var nudge: Vector2 = stand["nudge"]
	var size: Vector2 = stand["size"]
	var basis := Basis(Vector3.UP, int(stand["turn"]) * PI * 0.5 + float(stand["yaw"])).scaled(Vector3(size.x, size.y, size.x))
	return Transform3D(basis, Vector3(corner.x + 0.5 + nudge.x, 0.0, corner.y + 0.5 + nudge.y))


## Variant [param variant]'s mesh, its surfaces' materials its own: the
## slot's art (or fill) baked into one mesh, or the stand-in.
static func mesh(variant: int) -> Mesh:
	if not _meshes.has(variant):
		_meshes[variant] = _stand_in(variant) if ArtKit.filled_by(SLOT) == "placeholder" else _bake(ArtKit.instance(SLOT, variant))
	return _meshes[variant]


## Forgets the meshes made (the slot's art changed, or the stand-in).
static func forget() -> void:
	_meshes.clear()


## Every mesh under [param root] as one mesh, in root's space.
static func _bake(root: Node3D) -> Mesh:
	var out := ArrayMesh.new()
	var walk: Array = [[root, Transform3D.IDENTITY]]
	while not walk.is_empty():
		var next: Array = walk.pop_back()
		var node: Node = next[0]
		var at: Transform3D = next[1]
		var drawn := node as MeshInstance3D
		if drawn != null and drawn.mesh != null:
			for surface in drawn.mesh.get_surface_count():
				var arrays := drawn.mesh.surface_get_arrays(surface)
				var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for i in points.size():
					points[i] = at * points[i]
				arrays[Mesh.ARRAY_VERTEX] = points
				if arrays[Mesh.ARRAY_NORMAL] != null:
					var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
					for i in normals.size():
						normals[i] = (at.basis * normals[i]).normalized()
					arrays[Mesh.ARRAY_NORMAL] = normals
				arrays[Mesh.ARRAY_TANGENT] = null
				var material := drawn.material_override
				if material == null:
					material = drawn.get_surface_override_material(surface)
				if material == null:
					material = drawn.mesh.surface_get_material(surface)
				out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				# Evergreen: snow on it in winter, never dried or turned.
				out.surface_set_material(out.get_surface_count() - 1, Client3D.season_material(material, false) if material != null else null)
		for child in node.get_children():
			if child is Node3D:
				walk.append([child, at * (child as Node3D).transform])
	root.free()
	return out


## A stand made here (shots only): 4 to 6 bare trunks on the 2 x 2 under a
## canopy of crowns from 2.4 to 4 m, overhanging it by up to 0.4 m, in the palette's foliage; every variant its own trunks and crowns.
static func _stand_in(variant: int) -> Mesh:
	var seed_cell := Vector2i(variant * 31, 7)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark := Color("5a3d2b")
	var trunks := 4 + int(Client3D._roll(seed_cell, 1) * 3.0)
	var tops: Array[Vector3] = []
	for i in trunks:
		var angle := TAU * (i + Client3D._roll(seed_cell, 10 + i) * 0.6) / trunks
		var reach := lerpf(0.3, 0.8, Client3D._roll(seed_cell, 20 + i))
		var foot := Vector3(cos(angle) * reach, 0.0, sin(angle) * reach)
		var tall := lerpf(2.7, 3.4, Client3D._roll(seed_cell, 30 + i))
		var lean := Vector3(Client3D._roll(seed_cell, 40 + i) - 0.5, 0.0, Client3D._roll(seed_cell, 50 + i) - 0.5) * 0.3
		var top := foot + lean + Vector3.UP * tall
		_prism(tool, foot, top, 0.11, 0.06, bark.darkened(Client3D._roll(seed_cell, 60 + i) * 0.2))
		tops.append(top)
	var greens: Array[Color] = []
	for at in TerrainBorder.FOLIAGE:
		greens.append(Client3D.swatch(at.x, at.y))
	var crowns := 7 + int(Client3D._roll(seed_cell, 2) * 4.0)
	for i in crowns:
		var over := tops[i % tops.size()]
		var spread := Vector3(Client3D._roll(seed_cell, 70 + i) - 0.5, 0.0, Client3D._roll(seed_cell, 80 + i) - 0.5) * 1.4
		var middle := Vector3(clampf(over.x + spread.x, -0.85, 0.85), over.y - 0.2 + Client3D._roll(seed_cell, 90 + i) * 0.3,
				clampf(over.z + spread.z, -0.85, 0.85))
		var radius := lerpf(0.45, 0.55, Client3D._roll(seed_cell, 100 + i))
		_crown(tool, middle, Vector3(radius, radius * 0.7, radius), greens[i % greens.size()])
	tool.generate_normals()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	tool.set_material(Client3D.season_material(material, false))
	return tool.commit()


## A six-sided trunk from [param foot] to [param top].
static func _prism(tool: SurfaceTool, foot: Vector3, top: Vector3, low_radius: float, high_radius: float, colour: Color) -> void:
	for side in 6:
		var a := TAU * side / 6.0
		var b := TAU * (side + 1) / 6.0
		var da := Vector3(cos(a), 0.0, sin(a))
		var db := Vector3(cos(b), 0.0, sin(b))
		var quad: Array[Vector3] = [foot + da * low_radius, foot + db * low_radius, top + db * high_radius, top + da * high_radius]
		tool.set_color(colour)
		for index: int in [0, 2, 1, 0, 3, 2]:
			tool.add_vertex(quad[index])


## A faceted crown: an octahedron split once, squashed to [param size].
static func _crown(tool: SurfaceTool, middle: Vector3, size: Vector3, colour: Color) -> void:
	var points: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	var faces: Array[Vector3i] = [Vector3i(0, 2, 4), Vector3i(4, 2, 1), Vector3i(1, 2, 5), Vector3i(5, 2, 0),
			Vector3i(4, 3, 0), Vector3i(1, 3, 4), Vector3i(5, 3, 1), Vector3i(0, 3, 5)]
	tool.set_color(colour)
	for face in faces:
		var a := points[face.x]
		var b := points[face.y]
		var c := points[face.z]
		var ab := (a + b).normalized()
		var bc := (b + c).normalized()
		var ca := (c + a).normalized()
		for tri: Array in [[a, ab, ca], [ab, b, bc], [ca, bc, c], [ab, bc, ca]]:
			for point: Vector3 in tri:
				tool.add_vertex(middle + point * size)
