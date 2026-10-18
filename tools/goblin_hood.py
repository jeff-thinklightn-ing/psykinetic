# The goblin's hood and ears made separable (decision 494 amended): from art/models/characters/
# goblin.blend (one painted, skinned mesh), its hood's faces above the neck split off into their
# own skinned mesh, "Hood", so a goblin can go bare-headed; the hole they leave in its head filled
# with a scalp in its skin's green; and two shape keys on its body, "Ears_Big" and "Ears_Small",
# its ears scaled about their roots, so each goblin's ears are its own (Client3D.goblin_look).
#
#   blender -b art/models/characters/goblin.blend -P tools/goblin_hood.py -- <out .blend> <out .glb>
#
# The hood's faces: those the paint colours as cloth (not the skin's green, not the face's dark
# details) whose middles are above HOOD_ABOVE (the neck, as it stands). The ears: the green
# vertices above EAR_ABOVE further out to the side than EAR_OUT; each ear's root its vertices'
# nearest to the middle.
import os
import sys

import bmesh
import bpy
from mathutils import Vector

HOOD_ABOVE = 0.87
EAR_ABOVE = 0.9
EAR_OUT = 0.13
EAR_BIG = 1.3
EAR_SMALL = 0.75
## The scalp's dome (metres, as the goblin stands: its face toward -Y), on the head's bone.
SCALP_CENTRE = (0.0, 0.0, 1.0)
SCALP_RADII = (0.105, 0.118, 0.12)
HEAD_BONE = "Head"
## Dark faces this far behind the head's middle (+Y, the face being toward -Y) go with the hood.
DARK_BEHIND = 0.02


def args() -> list:
	return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def main() -> None:
	a = args()
	if len(a) < 2:
		raise SystemExit("usage: -- <out .blend> <out .glb>")
	out_blend, out_glb = (os.path.abspath(p) for p in a[:2])
	body = bpy.data.objects["goblin"]
	rig = bpy.data.objects["goblin_rig"]
	world = body.matrix_world
	image = bpy.data.images["goblin_paint"]
	w, h = image.size
	px = list(image.pixels)
	me = body.data
	uv = me.uv_layers.active.data

	def colour(poly):
		u = sum(uv[l].uv[0] for l in poly.loop_indices) / len(poly.loop_indices)
		v = sum(uv[l].uv[1] for l in poly.loop_indices) / len(poly.loop_indices)
		x, y = min(w - 1, max(0, int(u * w))), min(h - 1, max(0, int(v * h)))
		i = (y * w + x) * 4
		return Vector(px[i:i + 3]), (u, v)

	green_uv = None
	hood = []
	green_verts = set()
	for poly in me.polygons:
		c, at = colour(poly)
		green = c.y > c.x * 1.1 and c.y > c.z * 1.1
		dark = max(c) < 0.12
		z = (world @ poly.center).z
		if green:
			green_verts.update(poly.vertices)
			if green_uv is None and z > 0.95:
				green_uv = at
		elif z > HOOD_ABOVE and (not dark or (world @ poly.center).y > DARK_BEHIND):
			# Cloth, and the dark faces at the back of the head (the hood's lining, its shadow:
			# bare, they read as a second face).
			hood.append(poly.index)
	# The ears' shape keys, before the split (the body keeps them).
	body.shape_key_add(name="Basis", from_mix=False)
	ears = {}
	for i in green_verts:
		p = world @ me.vertices[i].co
		if p.z > EAR_ABOVE and abs(p.x) > EAR_OUT:
			ears[i] = p
	roots = {}
	for side in (1.0, -1.0):
		mine = [p for i, p in ears.items() if p.x * side > 0]
		if mine:
			near = sorted(mine, key=lambda p: abs(p.x))[:max(3, len(mine) // 6)]
			roots[side] = sum(near, Vector()) / len(near)
	inverse = world.inverted()
	for name, s in (("Ears_Big", EAR_BIG), ("Ears_Small", EAR_SMALL)):
		key = body.shape_key_add(name=name, from_mix=False)
		for i, p in ears.items():
			root = roots[1.0 if p.x > 0 else -1.0]
			# Full at the tip, nothing at the root: a smooth step out along the ear.
			reach = max(0.001, max(abs(q.x) for q in ears.values()) - abs(root.x))
			t = min(1.0, max(0.0, (abs(p.x) - abs(root.x)) / reach))
			k = 1.0 + (s - 1.0) * (t * t * (3.0 - 2.0 * t))
			key.data[i].co = inverse @ (root + (p - root) * k)
	print("ears: %d vertices, roots %s" % (len(ears), {k: tuple(round(c, 3) for c in v) for k, v in roots.items()}))
	# The hood: its faces into their own object.
	bpy.ops.object.select_all(action="DESELECT")
	body.select_set(True)
	bpy.context.view_layer.objects.active = body
	bpy.ops.object.mode_set(mode="EDIT")
	bpy.ops.mesh.select_mode(type="FACE")
	bpy.ops.mesh.select_all(action="DESELECT")
	bpy.ops.object.mode_set(mode="OBJECT")
	for i in hood:
		me.polygons[i].select = True
	bpy.ops.object.mode_set(mode="EDIT")
	bpy.ops.mesh.separate(type="SELECTED")
	bpy.ops.object.mode_set(mode="OBJECT")
	hood_obj = [o for o in bpy.context.selected_objects if o is not body][0]
	hood_obj.name = "Hood"
	hood_obj.data.name = "Hood"
	if hood_obj.data.shape_keys:
		hood_obj.shape_key_clear()
	# The scalp: the body's holes above the neck filled, in the skin's green.
	bm = bmesh.new()
	bm.from_mesh(body.data)
	edges = [e for e in bm.edges if e.is_boundary and min((world @ v.co).z for v in e.verts) > HOOD_ABOVE - 0.03]
	before = len(bm.faces)
	filled = bmesh.ops.holes_fill(bm, edges=edges, sides=0)["faces"]
	bmesh.ops.triangulate(bm, faces=filled)
	layer = bm.loops.layers.uv.active
	bm.faces.ensure_lookup_table()
	for f in bm.faces[before:]:
		for loop in f.loops:
			loop[layer].uv = Vector(green_uv)
	bm.to_mesh(body.data)
	scalp = len(bm.faces) - before
	bm.free()
	# The hood covered the back of the head too: a skin-green dome on the Head bone closes it
	# (under the hood when it is up), behind the face's own surface.
	dome = bpy.data.meshes.new("Scalp")
	dm = bmesh.new()
	bmesh.ops.create_icosphere(dm, subdivisions=2, radius=1.0)
	for v in dm.verts:
		v.co = inverse @ Vector((SCALP_CENTRE[0] + v.co.x * SCALP_RADII[0], SCALP_CENTRE[1] + v.co.y * SCALP_RADII[1],
			SCALP_CENTRE[2] + v.co.z * SCALP_RADII[2]))
	# Outward again once placed (the goblin's own transform may turn its winding inside out).
	bmesh.ops.recalc_face_normals(dm, faces=dm.faces[:])
	dlayer = dm.loops.layers.uv.new(me.uv_layers.active.name)  # The body's own layer ("paint"), so the join keeps one.
	for f in dm.faces:
		for loop in f.loops:
			loop[dlayer].uv = Vector(green_uv)
	dm.to_mesh(dome)
	dm.free()
	dome_obj = bpy.data.objects.new("Scalp", dome)
	bpy.context.scene.collection.objects.link(dome_obj)
	dome_obj.matrix_world = world
	dome.materials.append(me.materials[0])
	dome_obj.vertex_groups.new(name=HEAD_BONE).add(list(range(len(dome.vertices))), 1.0, "REPLACE")
	bpy.ops.object.select_all(action="DESELECT")
	dome_obj.select_set(True)
	body.select_set(True)
	bpy.context.view_layer.objects.active = body
	bpy.ops.object.join()
	print("hood: %d faces split off; scalp: %d faces filled and a dome of %d" % (len(hood), scalp, 320))
	bpy.context.scene["source"] = (str(bpy.context.scene.get("source", "")) + "; its hood split off and its ears given shape keys by "
		+ "tools/goblin_hood.py (decision 494 amended)")
	bpy.context.preferences.filepaths.save_version = 0
	bpy.ops.wm.save_as_mainfile(filepath=out_blend)
	bpy.ops.object.select_all(action="DESELECT")
	for o in (rig, body, hood_obj):
		o.select_set(True)
	bpy.ops.export_scene.gltf(filepath=out_glb, export_format="GLB", use_selection=True, export_yup=True, export_skins=True,
		export_morph=True, export_morph_normal=False, export_animations=False)
	print("wrote %s and %s" % (out_blend, out_glb))


if __name__ == "__main__":
	main()
