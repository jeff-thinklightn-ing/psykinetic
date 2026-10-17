# The humanoid body, from a mesh rigged to the UAL skeleton (tools/body_rig.py's output)
# to the game's look: decimated to a triangle budget, flat-shaded (faceted), with two
# shape keys, "lean" and "heavy", that the game blends by one value (-1 lean .. 0 ..
# +1 heavy). Skin weights and the skeleton are kept as rigged, so every UAL clip fits.
#
# Run with Blender, headless (BLENDER_PATH, or Steam's):
#   blender -b -P tools/body_build.py -- --list <in.glb>
#       prints the objects, their triangles, materials and the armature's bones.
#   blender -b -P tools/body_build.py -- <in.glb> <out stem> [--tris 4000] [--mesh NAME ...]
#           [--source TEXT] [--colours FRONT.png] [--smooth] [--vertex-colours]
#       builds <out stem>.blend and <out stem>.glb (e.g. art/models/characters/human_m).
#       --mesh keeps only the named meshes; default every mesh skinned to the armature.
#       --source is where the mesh came from, kept in the .blend's scene["source"].
#       --colours colours a shape-only mesh from its front concept (a figure on white):
#       flat regions Skin, Hair, Tunic (the one the game tints), Trousers, Belt, Boots.
#       One surface, one material ("human"): Skin, Hair, Tunic and Trousers are marked
#       one-hot in the vertex colour (red, green, blue, alpha) and take their colours
#       per body in the game (art/models/characters/human_body.gdshader; the concept's
#       are the mesh's extras: skin, hair, tunic, trousers); Belt and Boots are on the
#       palette, each on the swatch of PALETTE_ROWS nearest the concept's colour (u =
#       (col + 0.5) / 8, v = 1 - (row + 0.5) / rows, as art/kit's pieces are).
#       --smooth keeps the surface smooth-shaded (the mesh's own normals) instead of faceted.
#       --vertex-colours keeps the mesh's own vertex colours (art-gen's projected concept)
#       on one material, "VertexColour", instead of colouring by region.
#
# The shape keys move each vertex along its normal by its bones' weights times the
# amounts below (metres), so a body fills out where people do (belly, hips, thighs,
# upper arms, neck) and hands, feet and the head keep their place: the attach points
# and the feet on the ground hold at any blend. The belly's push is mostly forward.
import os
import sys

import bpy
from mathutils import Vector

HEAVY = {
	"pelvis": 0.035, "spine_01": 0.055, "spine_02": 0.04, "spine_03": 0.025,
	"neck_01": 0.018, "clavicle_l": 0.01, "clavicle_r": 0.01,
	"upperarm_l": 0.02, "upperarm_r": 0.02, "lowerarm_l": 0.01, "lowerarm_r": 0.01,
	"thigh_l": 0.03, "thigh_r": 0.03, "calf_l": 0.012, "calf_r": 0.012,
}
LEAN = {
	"pelvis": -0.012, "spine_01": -0.02, "spine_02": -0.015, "spine_03": -0.008,
	"neck_01": -0.006, "upperarm_l": -0.008, "upperarm_r": -0.008,
	"lowerarm_l": -0.004, "lowerarm_r": -0.004,
	"thigh_l": -0.012, "thigh_r": -0.012, "calf_l": -0.006, "calf_r": -0.006,
}
## Flat colour regions, each its own material (the game tints "Tunic"), and which of
## them a face may be, by the bone that moves it most: the concept's colour picks
## among these, so a dark boot is never read as hair.
REGIONS = ["Skin", "Hair", "Tunic", "Trousers", "Belt", "Boots"]
ALLOWED = [
	(("Head", "neck_01"), ("Skin", "Hair")),
	(("hand_", "thumb_", "index_", "middle_", "ring_", "pinky_"), ("Skin",)),  # Sleeves end at the wrist.
	(("lowerarm_", "upperarm_", "clavicle_"), ("Tunic",)),  # Long sleeves.
	(("spine_03", "spine_02"), ("Tunic", "Skin")),  # Skin only at the neck: see NECK.
	(("spine_01", "pelvis", "root"), ("Tunic", "Belt", "Trousers")),
	(("thigh_",), ("Trousers", "Belt", "Tunic")),
	(("calf_",), ("Trousers", "Boots")),
	(("foot_", "ball_"), ("Boots",)),
]
## The one material of a built body, and its tinted parts in the order of the
## vertex colour's channels (red, green, blue, alpha).
MATERIAL = "human"
TINTED = ["Skin", "Hair", "Tunic", "Trousers"]
## The regions that go on the palette, and the palette rows each picks its swatch from
## (5 cloth and leather, 6 metal).
PALETTE_ROWS = {"Belt": (5,), "Boots": (5, 6)}
PALETTE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "kit", "palette.png")
## The neck opening, where the chest may show skin: within this far of the centre line
## (metres) and above this far below the neck bone's head.
NECK = (0.12, 0.16)
## Bones whose push goes mostly forward (a belly, not a barrel).
FRONT = {"pelvis", "spine_01", "spine_02"}
FRONT_FLOOR = 0.25
SOURCE = ("Qwen-Image-2512 concept, TRELLIS.2 mesh (C:/dev/art-gen); rigged to Quaternius UAL "
	+ "(CC0) by tools/body_rig.py; decimated, flat-shaded, lean/heavy shape keys by tools/body_build.py")


def args() -> list:
	return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def load(path: str) -> None:
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=path)


def tris(obj) -> int:
	return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def armature():
	arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
	if len(arms) != 1:
		raise SystemExit("expected one armature, found %d" % len(arms))
	return arms[0]


def skinned(arm) -> list:
	return [o for o in bpy.data.objects if o.type == "MESH"
		and any(m.type == "ARMATURE" and m.object == arm for m in o.modifiers)]


def list_scene() -> None:
	for obj in bpy.data.objects:
		line = "%-10s %-32s" % (obj.type, obj.name)
		if obj.type == "MESH":
			mats = [m.name for m in obj.data.materials if m]
			keys = [k.name for k in obj.data.shape_keys.key_blocks] if obj.data.shape_keys else []
			line += " tris %6d  groups %3d  materials %s  keys %s" % (
				tris(obj), len(obj.vertex_groups), mats, keys)
		print(line)
	arm = armature()
	print("bones (%d): %s" % (len(arm.data.bones), [b.name for b in arm.data.bones]))
	lo, hi = bounds(skinned(arm))
	print("height %.3f m (z %.3f .. %.3f)" % (hi.z - lo.z, lo.z, hi.z))
	print("forward %s, right %s" % tuple(axes(arm)))


def bounds(objs) -> tuple:
	pts = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
	lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
	hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
	return lo, hi


## The body's forward (heel to toe, flat) and right (left foot to right foot), in world space.
def axes(arm) -> list:
	bones = arm.data.bones
	m = arm.matrix_world
	forward = (m @ bones["ball_l"].head_local) - (m @ bones["foot_l"].head_local)
	forward.z = 0.0
	right = (m @ bones["foot_r"].head_local) - (m @ bones["foot_l"].head_local)
	right.z = 0.0
	return [forward.normalized(), right.normalized()]


def decimate(obj, target: int, right: Vector) -> None:
	ratio = min(1.0, target / max(1, tris(obj)))
	if ratio >= 1.0:
		return
	if obj.data.shape_keys:
		obj.shape_key_clear()
	mod = obj.modifiers.new("Decimate", "DECIMATE")
	mod.ratio = ratio
	mod.use_collapse_triangulate = True
	mod.use_symmetry = True
	mod.symmetry_axis = "XYZ"[max(range(3), key=lambda i: abs(right[i]))]
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
	bpy.ops.object.modifier_apply(modifier=mod.name)
	# Collapsing blends weights: back to four bones a vertex, summing to one.
	bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
	bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)


## The front concept (a figure on white), as a function from a world point to its
## colour there (sRGB, 0..1), the figure's bounds fitted to the body's.
class Concept:
	def __init__(self, path: str, lo: Vector, hi: Vector, right: Vector):
		import numpy
		image = bpy.data.images.load(path)
		w, h = image.size
		pixels = numpy.empty(w * h * 4, dtype=numpy.float32)
		image.pixels.foreach_get(pixels)
		self.rgb = pixels.reshape(h, w, 4)[::-1, :, :3]  # Rows top to bottom.
		figure = self.rgb.min(axis=2) < 0.92
		rows = numpy.nonzero(figure.any(axis=1))[0]
		columns = numpy.nonzero(figure.any(axis=0))[0]
		self.top, self.bottom = rows[0], rows[-1]
		self.left, self.right_px = columns[0], columns[-1]
		self.figure = figure
		bpy.data.images.remove(image)  # Not kept in the .blend.
		# The viewer's right is the body's left.
		self.across = -right
		corners = [lo, hi]
		spans = [c.dot(self.across) for c in corners]
		self.u0, self.u1 = min(spans), max(spans)
		self.z0, self.z1 = lo.z, hi.z

	def pixel(self, p: Vector) -> tuple:
		u = (p.dot(self.across) - self.u0) / (self.u1 - self.u0)
		v = (self.z1 - p.z) / (self.z1 - self.z0)
		x = round(self.left + u * (self.right_px - self.left))
		y = round(self.top + v * (self.bottom - self.top))
		return min(max(x, 0), self.rgb.shape[1] - 1), min(max(y, 0), self.rgb.shape[0] - 1)

	def z_of(self, row: int) -> float:
		return self.z1 - (row - self.top) / (self.bottom - self.top) * (self.z1 - self.z0)

	## The longest run of rows, going down column x from row a to row b, whose colour
	## is nearer refs[region] than any other of refs: (first row, last row), or None.
	def run(self, x: int, a: int, b: int, refs: dict, region: str):
		best, start = None, None
		for y in range(a, b + 2):
			hit = False
			if y <= b and self.figure[y, x]:
				c = Vector(self.rgb[y, max(x - 2, 0):x + 3].mean(axis=0).tolist())
				hit = min(refs, key=lambda r: (refs[r] - c).length) == region
			if hit and start is None:
				start = y
			elif not hit and start is not None:
				if best is None or y - 1 - start > best[1] - best[0]:
					best = (start, y - 1)
				start = None
		return best

	## The median colour of the figure's pixels around p (None off the figure).
	def colour(self, p: Vector, r: int = 3):
		import numpy
		x, y = self.pixel(p)
		patch = self.rgb[max(y - r, 0):y + r + 1, max(x - r, 0):x + r + 1]
		mask = self.figure[max(y - r, 0):y + r + 1, max(x - r, 0):x + r + 1]
		if not mask.any():
			return None
		return Vector(numpy.median(patch[mask], axis=0).tolist())


def allowed(bone: str) -> tuple:
	for prefixes, regions in ALLOWED:
		if any(bone.startswith(p) for p in prefixes):
			return regions
	return tuple(REGIONS)


## Each region's colour, sampled from the concept where the rig says that region is.
def reference_colours(concept: Concept, arm) -> dict:
	m = arm.matrix_world
	b = arm.data.bones
	at = lambda name, t=0.0: m @ b[name].head_local.lerp(b[name].tail_local, t)
	head = at("Head", 0.5)
	hair_top = Vector((head.x, head.y, concept.z1 - 0.012))
	pelvis, spine = at("pelvis"), at("spine_01")
	# The belt: the dark band on the centre line between the hips and the waist; the middle
	# of the three darkest points there, since the darkest may be a shadow line at its edge.
	belt = sorted((pelvis.lerp(spine, k / 40.0) for k in range(41)),
		key=lambda p: (concept.colour(p, 1) or Vector((1, 1, 1))).length)[1]
	ankle = at("foot_l").lerp(at("calf_l"), 0.15)
	refs = {
		"Skin": [concept.colour(at("hand_l", 0.5)), concept.colour(at("hand_r", 0.5)), concept.colour(head + Vector((0, 0, -0.03)))],
		"Hair": [concept.colour(hair_top, 2)],
		"Tunic": [concept.colour(at("spine_02", 0.5)), concept.colour(at("upperarm_l", 0.5))],
		"Trousers": [concept.colour(at("thigh_l", 0.5)), concept.colour(at("thigh_r", 0.5))],
		"Belt": [concept.colour(belt, 1)],
		"Boots": [concept.colour(ankle), concept.colour(at("foot_r").lerp(at("calf_r"), 0.15))],
	}
	out = {}
	for region, samples in refs.items():
		samples = [s for s in samples if s is not None]
		if not samples:
			raise SystemExit("no %s colour in the concept: is it the front view of this body?" % region)
		out[region] = sum(samples, Vector((0, 0, 0))) / len(samples)
		print("  %-8s %s" % (region, tuple(round(c, 3) for c in out[region])))
	return out


## Cuts the mesh across at each height (world z) below [param head_below] (not the
## arms, held out at the shoulders), so a border between regions runs along the cut,
## not zigzagging along whole facets. The new vertices' weights are interpolated.
def cut(obj, heights: list, head_below: float) -> None:
	import bmesh
	mw = obj.matrix_world
	inv = mw.inverted()
	bm = bmesh.new()
	bm.from_mesh(obj.data)
	before = len(bm.faces)
	for z in heights:
		if z >= head_below:
			continue
		geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
		bmesh.ops.bisect_plane(bm, geom=geom, dist=0.002, plane_co=inv @ Vector((0, 0, z)),
			plane_no=(inv.to_3x3().transposed() @ Vector((0, 0, 1))).normalized())
	bmesh.ops.triangulate(bm, faces=bm.faces[:])
	print("  cut at %s m: %d faces to %d" % ([round(z, 3) for z in heights], before, len(bm.faces)))
	bm.to_mesh(obj.data)
	bm.free()
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
	bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)


## Splits the mesh into the flat colour regions, each face by the concept's colour
## where it is (among the regions its bone allows), the back of the head hair, then
## lone faces given their neighbours' region.
def colour(obj, arm, concept_path: str, forward_world: Vector, right_world: Vector) -> None:
	mw = obj.matrix_world
	lo, hi = bounds([obj])
	concept = Concept(concept_path, lo, hi, right_world)
	print("colours from %s:" % concept_path)
	refs = reference_colours(concept, arm)
	# The clothes are cut by height, as they are made: the belt's band down the centre
	# line, the boots' tops down each shin. Colour picks only skin from cloth and hair
	# from face, where the facets can't follow a line.
	m, b = arm.matrix_world, arm.data.bones
	at = lambda name, t=0.0: m @ b[name].head_local.lerp(b[name].tail_local, t)
	cx, waist = concept.pixel(at("spine_02"))
	crotch = concept.pixel(at("thigh_l"))[1]
	# A few columns across the waist, the longest run: a buckle on the centre line is
	# neither belt nor cloth, and leaves a sliver there.
	runs = []
	for dx in (-0.08, -0.05, -0.02, 0.0, 0.02, 0.05, 0.08):
		x = concept.pixel(at("spine_02") + right_world * dx)[0]
		run = concept.run(x, waist, crotch, {r: refs[r] for r in ("Tunic", "Belt", "Trousers")}, "Belt")
		if run is not None:
			runs.append(run)
	belt = max(runs, key=lambda r: r[1] - r[0]) if runs else None
	if belt is None:
		raise SystemExit("no belt down the centre line of the concept")
	belt_top, belt_bottom = concept.z_of(belt[0]), concept.z_of(belt[1] + 1)
	boot_tops = []
	for side in ("l", "r"):
		x, knee = concept.pixel(at("calf_" + side))
		foot = concept.pixel(at("foot_" + side))[1]
		boot = concept.run(x, knee, foot, {r: refs[r] for r in ("Trousers", "Boots")}, "Boots")
		if boot is not None:
			boot_tops.append(concept.z_of(boot[0]))
	if not boot_tops:
		raise SystemExit("no boots down the shins of the concept")
	boot_top = sum(boot_tops) / len(boot_tops)
	# The tunic's skirt: tunic straight on below the belt, down to its hem (none if the
	# trousers start at the belt).
	hem = belt_bottom
	for dx in (-0.06, 0.0, 0.06):
		x = concept.pixel(at("spine_02") + right_world * dx)[0]
		skirt = concept.run(x, belt[1] + 1, concept.pixel(at("thigh_l", 0.5))[1], {r: refs[r] for r in ("Tunic", "Trousers")}, "Tunic")
		if skirt is not None and skirt[0] <= belt[1] + 4:
			hem = min(hem, concept.z_of(skirt[1] + 1))
	print("  belt %.3f..%.3f m, hem %.3f m, boot tops %.3f m" % (belt_bottom, belt_top, hem, boot_top))
	cut(obj, [belt_top, belt_bottom, boot_top] + ([hem] if hem < belt_bottom - 0.01 else []), head_below=at("spine_03").z)
	names = {g.index: g.name for g in obj.vertex_groups}
	mesh = obj.data
	head_at = arm.matrix_world @ arm.data.bones["Head"].head_local
	head_z = head_at.z
	neck_z = (arm.matrix_world @ arm.data.bones["neck_01"].head_local).z
	hairline = hi.z - 0.06  # Below it a face that looks forward is the face.
	nrm = mw.to_3x3().inverted().transposed()
	region = []
	for poly in mesh.polygons:
		weights = {}
		for vi in poly.vertices:
			for g in mesh.vertices[vi].groups:
				weights[names.get(g.group, "")] = weights.get(names.get(g.group, ""), 0.0) + g.weight
		bone = max(weights, key=weights.get) if weights else ""
		choices = allowed(bone)
		centre = mw @ poly.center
		normal = (nrm @ poly.normal).normalized()
		looks = normal.dot(forward_world)
		if "Hair" in choices:
			behind = (centre - head_at).dot(forward_world) < -0.04
			crown = centre.z > hi.z - 0.08 and normal.z > 0.4  # The top, which the front view sees edge on.
			if crown or (centre.z > head_z + 0.03 and looks < -0.25) or (behind and centre.z > head_z - 0.02):
				# The back of the head, which the front view never saw (a bun too).
				region.append("Hair")
				continue
			if centre.z < hairline:
				region.append("Skin")  # Eyes, brows and shadows are not hair.
				continue
		if bone.startswith("spine") and belt_bottom <= centre.z <= belt_top:
			region.append("Belt")  # Round the back, where the spine moves the belt.
			continue
		if "Belt" in choices or "Boots" in choices:
			if centre.z > belt_top:
				region.append("Tunic")
			elif centre.z >= belt_bottom:
				region.append("Belt")
			elif centre.z >= hem:
				region.append("Tunic")
			elif centre.z > boot_top:
				region.append("Trousers")
			else:
				region.append("Boots")
			continue
		if "Skin" in choices and "Hair" not in choices and bone.startswith("spine"):
			if abs(centre.dot(right_world)) > NECK[0] or centre.z < neck_z - NECK[1]:
				choices = tuple(c for c in choices if c != "Skin")
		seen = concept.colour(centre)
		if seen is None:
			region.append(choices[0])
			continue
		region.append(min(choices, key=lambda r: (refs[r] - seen).length))
	# Lone faces take their neighbours' region (two passes).
	neighbours = [[] for _ in mesh.polygons]
	by_edge = {}
	for poly in mesh.polygons:
		for key in poly.edge_keys:
			by_edge.setdefault(key, []).append(poly.index)
	for faces in by_edge.values():
		for a in faces:
			for b in faces:
				if a != b:
					neighbours[a].append(b)
	for _ in range(2):
		changed = list(region)
		for i, near in enumerate(neighbours):
			counts = {}
			for j in near:
				counts[region[j]] = counts.get(region[j], 0) + 1
			if counts and region[i] not in counts:
				best = max(counts, key=counts.get)
				if counts[best] >= 2:
					changed[i] = best
		region = changed
	mesh.materials.clear()
	swatches = palette_swatches(refs)
	if not mesh.uv_layers:
		mesh.uv_layers.new(name="UVMap")
	uv = mesh.uv_layers.active.data
	# One material for the whole body (art/models/characters/human_body.tres
	# in the game): the part each face is, one-hot in its vertex colour, and
	# the palette's swatch in its UVs for the parts that are not tinted.
	mesh.materials.append(bpy.data.materials.get(MATERIAL) or bpy.data.materials.new(MATERIAL))
	while mesh.color_attributes:
		mesh.color_attributes.remove(mesh.color_attributes[0])
	parts = mesh.color_attributes.new(name="parts", type="FLOAT_COLOR", domain="CORNER")
	mesh.color_attributes.active_color = parts
	for poly, name in zip(mesh.polygons, region):
		at = swatches[name][1] if name in swatches else swatches[next(iter(swatches))][1]
		mask = [1.0 if TINTED.index(name) == i else 0.0 for i in range(4)] if name in TINTED else [0.0] * 4
		poly.material_index = 0
		for li in poly.loop_indices:
			uv[li].uv = at
			parts.data[li].color = mask
	# The body's own colours, as the concept has them: the game's defaults
	# for each tinted part (the node's extras, its metadata in Godot).
	for name in TINTED:
		c = refs[name]
		obj[name.lower()] = "#%02x%02x%02x" % tuple(round(max(0.0, min(1.0, v)) * 255) for v in (c.x, c.y, c.z))
	print("  faces: %s" % {n: region.count(n) for n in REGIONS})
	print("  palette: %s" % {n: swatches[n][0] for n in swatches})


## How far apart two colours look: their hue (each one's offset from its own grey) counts
## twice their lightness, so slate boots pick a grey swatch, not a brown one as dark.
def colour_distance(a: Vector, b: Vector) -> float:
	ga, gb = sum(a) / 3.0, sum(b) / 3.0
	hue = (a - Vector((ga, ga, ga))) - (b - Vector((gb, gb, gb)))
	return 2.0 * hue.length + abs(ga - gb)


## Each palette region's swatch: the one in its rows nearest the concept's colour, as
## {region: ((row, col), (u, v))}.
def palette_swatches(refs: dict) -> dict:
	image = bpy.data.images.load(PALETTE)
	w, h = image.size
	pixels = list(image.pixels)  # Rows bottom up; an 8-bit PNG's values as stored (sRGB).
	size = w // 8
	rows = round(h / size)
	out = {}
	for region, allowed in PALETTE_ROWS.items():
		best = None
		for row in allowed:
			for col in range(8):
				x, y = col * size + size // 2, h - 1 - (row * size + size // 2)
				i = (y * w + x) * 4
				d = colour_distance(Vector(pixels[i:i + 3]), refs[region])
				if best is None or d < best[0]:
					best = (d, (row, col))
		row, col = best[1]
		out[region] = ((row, col), ((col + 0.5) / 8.0, 1.0 - (row + 0.5) / rows))
	bpy.data.images.remove(image)
	return out


## Welds the vertices a glTF export split along hard edges (one island a face, else),
## so decimating sees one surface. Split points share their bone weights.
def weld(obj) -> None:
	import bmesh
	if obj.data.shape_keys:
		obj.shape_key_clear()
	bm = bmesh.new()
	bm.from_mesh(obj.data)
	before = len(bm.verts)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
	# TRELLIS's facing is not always consistent: every face outward.
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
	bm.to_mesh(obj.data)
	bm.free()
	if obj.data.has_custom_normals:
		bpy.context.view_layer.objects.active = obj
		bpy.ops.mesh.customdata_custom_splitnormals_clear()
	print("  welded %s: %d vertices to %d" % (obj.name, before, len(obj.data.vertices)))


## One material, "VertexColour", drawn by the mesh's own colours (the game and
## body_sheet.gd give it a material that takes them as albedo).
def keep_vertex_colours(obj) -> None:
	mesh = obj.data
	if not mesh.color_attributes:
		raise SystemExit("--vertex-colours: %s has no vertex colours" % obj.name)
	mesh.color_attributes.active_color = mesh.color_attributes[0]
	mesh.materials.clear()
	material = bpy.data.materials.get("VertexColour") or bpy.data.materials.new("VertexColour")
	material.use_nodes = True
	nodes = material.node_tree.nodes
	bsdf = nodes.get("Principled BSDF")
	attribute = nodes.new("ShaderNodeVertexColor")
	attribute.layer_name = mesh.color_attributes[0].name
	material.node_tree.links.new(attribute.outputs["Color"], bsdf.inputs["Base Color"])
	bsdf.inputs["Roughness"].default_value = 1.0
	bsdf.inputs["Metallic"].default_value = 0.0
	mesh.materials.append(material)
	print("  vertex colours: %s" % mesh.color_attributes[0].name)


def shape_keys(obj, forward_world: Vector) -> None:
	mesh = obj.data
	basis = obj.shape_key_add(name="Basis", from_mix=False)
	inv = obj.matrix_world.to_3x3().inverted()
	forward = (inv @ forward_world).normalized()
	names = {g.index: g.name for g in obj.vertex_groups}
	for key_name, amounts in (("lean", LEAN), ("heavy", HEAVY)):
		key = obj.shape_key_add(name=key_name, from_mix=False)
		for v in mesh.vertices:
			normal = v.normal.normalized()
			push = 0.0
			for g in v.groups:
				bone = names.get(g.group, "")
				amount = amounts.get(bone, 0.0)
				if amount == 0.0:
					continue
				if bone in FRONT:
					amount *= FRONT_FLOOR + (1.0 - FRONT_FLOOR) * max(0.0, normal.dot(forward))
				push += amount * g.weight
			key.data[v.index].co = basis.data[v.index].co + normal * push


def build(path: str, stem: str, target: int, keep: list, source: str, concept: str, smooth: bool = False,
		vertex_colours: bool = False) -> None:
	load(path)
	arm = armature()
	meshes = skinned(arm)
	if keep:
		meshes = [o for o in meshes if o.name in keep]
		missing = set(keep) - {o.name for o in meshes}
		if missing:
			raise SystemExit("no skinned mesh named %s" % sorted(missing))
	for obj in list(bpy.data.objects):
		if obj.type == "MESH" and obj not in meshes:
			bpy.data.objects.remove(obj)
	# The body has no clips of its own (an animation pack's would bloat the .blend).
	if arm.animation_data:
		arm.animation_data_clear()
	for action in list(bpy.data.actions):
		bpy.data.actions.remove(action)
	bpy.data.orphans_purge(do_recursive=True)
	forward, right = axes(arm)
	total = sum(tris(o) for o in meshes)
	for obj in meshes:
		weld(obj)
		# Each mesh keeps its share of the budget.
		decimate(obj, max(8, round(target * tris(obj) / total)), right)
		for poly in obj.data.polygons:
			poly.use_smooth = smooth
		if vertex_colours:
			keep_vertex_colours(obj)
		elif concept:
			colour(obj, arm, concept, forward, right)
		shape_keys(obj, forward)
		obj.data.update()
	bpy.context.scene["source"] = source
	lo, hi = bounds(meshes)
	print("built %s: tris %d, height %.3f m, keys lean/heavy" % (
		stem, sum(tris(o) for o in meshes), hi.z - lo.z))
	bpy.context.preferences.filepaths.save_version = 0  # no .blend1 beside it
	bpy.ops.wm.save_as_mainfile(filepath=bpy.path.abspath(stem + ".blend"))
	bpy.ops.object.select_all(action="DESELECT")
	arm.select_set(True)
	for obj in meshes:
		obj.select_set(True)
	bpy.ops.export_scene.gltf(filepath=stem + ".glb", export_format="GLB", use_selection=True,
		export_yup=True, export_skins=True, export_morph=True, export_morph_normal=True,
		export_animations=False, export_extras=True, export_vertex_color="ACTIVE")


def main() -> None:
	a = args()
	if len(a) == 2 and a[0] == "--list":
		load(a[1])
		list_scene()
		return
	if len(a) < 2:
		raise SystemExit("usage: -- --list <in.glb> | -- <in.glb> <out stem> [--tris N] [--mesh NAME ...] [--source TEXT] [--colours FRONT.png]")
	target = 4000
	keep = []
	source = SOURCE
	concept = ""
	smooth, vertex_colours = False, False
	rest = a[2:]
	i = 0
	while i < len(rest):
		if rest[i] == "--tris":
			target = int(rest[i + 1])
			i += 2
		elif rest[i] == "--colours":
			concept = os.path.abspath(rest[i + 1])
			i += 2
		elif rest[i] in ("--smooth", "--vertex-colours"):
			smooth = smooth or rest[i] == "--smooth"
			vertex_colours = vertex_colours or rest[i] == "--vertex-colours"
			i += 1
		elif rest[i] == "--source":
			source = rest[i + 1]
			i += 2
		elif rest[i] == "--mesh":
			i += 1
			while i < len(rest) and not rest[i].startswith("--"):
				keep.append(rest[i])
				i += 1
		else:
			raise SystemExit("unknown argument %s" % rest[i])
	build(a[0], a[1], target, keep, source, concept, smooth, vertex_colours)


main()
