# A rigged body's marks (decision 529; the goblin's by hand, tools/goblin_marks.py), drawn
# into a mask over its paint texture's UVs from where they lie on the body, so a TRELLIS mesh's
# scattered UV islands take them: a mark a channel, which a shader draws one of or none by
# seed (goblin.gdshaderinc's mark). Placed by the skeleton at rest (the UAL's T-pose, its
# front -Y), sized by the body's height over the orc's 1.95 m:
#   red    "scarred":     a slash across the chest, from the right collarbone down to the left ribs;
#   green  "striped":     three bands round each upper arm;
#   blue   "red-handed":  a hand on the chest's left, the palm over the heart, fingers up.
#
#   blender -b -P tools/body_marks.py -- <rigged .glb> <out.png> [--size PX]
import math
import os
import sys

import bpy
from mathutils import Vector

SIZE = 512
ORC_HEIGHT = 1.95
## How far into a front-facing surface the chest's marks reach: faces whose normal's -Y is
## at least this much of it.
FRONT = 0.25


def args() -> list:
	return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def seg_dist(p, a, b) -> tuple:
	ab = b - a
	t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-12)))
	return (p - (a + ab * t)).length, t


def main() -> None:
	a = args()
	if len(a) < 2:
		raise SystemExit("usage: -- <rigged .glb> <out.png> [--size PX]")
	src, out = os.path.abspath(a[0]), os.path.abspath(a[1])
	size = int(a[a.index("--size") + 1]) if "--size" in a else SIZE
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=src)
	arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
	body = max((o for o in bpy.data.objects if o.type == "MESH" and o.data.uv_layers), key=lambda o: len(o.data.polygons))
	bone = lambda n: arm.matrix_world @ arm.data.bones[n].head_local
	tail = lambda n: arm.matrix_world @ arm.data.bones[n].tail_local
	# The skin's own faces only (a hand-made body's parts on art-kit's palette take no marks).
	skin = {i for i, m in enumerate(body.data.materials) if m is None or m.name.split(".")[0] != "palette"}
	on_skin = {v for poly in body.data.polygons if poly.material_index in skin for v in poly.vertices}
	pts = [body.matrix_world @ body.data.vertices[i].co for i in sorted(on_skin)]
	height = max(p.z for p in pts) - min(p.z for p in pts)
	k = height / ORC_HEIGHT
	# The chest's middle: a little over spine_02 (spine_03 sits up under a hunched body's jaw).
	chest = bone("spine_02") + Vector((0.0, 0.0, 0.06 * k))
	# The chest's front, where a front ray along the middle meets the body (its points nearest x 0).
	front_y = min(p.y for p in pts if abs(p.x - chest.x) < 0.08 * k and abs(p.z - chest.z) < 0.1 * k)
	scar = (Vector((-0.20 * k, 0, chest.z + 0.14 * k)), Vector((0.04 * k, 0, chest.z - 0.20 * k)))
	palm = Vector((0.13 * k, 0, chest.z - 0.02 * k))
	fingers = [(palm + Vector((dx * k, 0, 0.03 * k)), palm + Vector((ex * k, 0, 0.17 * k))) for dx, ex in
		((-0.05, -0.085), (-0.017, -0.025), (0.017, 0.025), (0.05, 0.08))]
	thumb = (palm + Vector((0.045 * k, 0, -0.015 * k)), palm + Vector((0.13 * k, 0, 0.045 * k)))
	arms = [(bone("upperarm_" + s), tail("upperarm_" + s)) for s in ("l", "r")]

	def chest_front(p, n) -> bool:
		return -n.y >= FRONT and p.y < front_y + 0.12 * k and abs(p.z - chest.z) < 0.3 * k

	def flat(p) -> Vector:
		return Vector((p.x, 0.0, p.z))

	def marks(p, n) -> tuple:
		r = g = b = 0.0
		if chest_front(p, n):
			if seg_dist(flat(p), *scar)[0] < 0.018 * k:
				r = 1.0
			q = flat(p) - palm
			if (q.x / (0.07 * k)) ** 2 + (q.z / (0.078 * k)) ** 2 < 1.0:
				b = 1.0
			elif any(seg_dist(flat(p), f0, f1)[0] < 0.017 * k for f0, f1 in fingers + [thumb]):
				b = 1.0
		for a0, a1 in arms:
			d, t = seg_dist(p, a0, a1)
			if d < 0.3 * k and any(lo < t < lo + 0.07 for lo in (0.38, 0.53, 0.68)):
				g = 1.0
		return r, g, b

	# The mask's texels, rows top first (as the paint's UVs read it in the game).
	px = [[0.0, 0.0, 0.0] for _ in range(size * size)]
	mesh = body.data
	mesh.calc_loop_triangles()
	uv = mesh.uv_layers.active.data
	world = body.matrix_world
	normal_m = world.to_3x3().inverted().transposed()
	drawn = [0, 0, 0]
	for tri in mesh.loop_triangles:
		if tri.material_index not in skin:
			continue
		p3 = [world @ mesh.vertices[v].co for v in tri.vertices]
		centre = (p3[0] + p3[1] + p3[2]) / 3.0
		# Only near the chest and the upper arms.
		if abs(centre.z - chest.z) > 0.45 * k:
			continue
		n = (normal_m @ tri.normal).normalized()
		t2 = [Vector((uv[li].uv.x * size, (1.0 - uv[li].uv.y) * size)) for li in tri.loops]
		x0, x1 = int(min(q.x for q in t2)), int(math.ceil(max(q.x for q in t2)))
		y0, y1 = int(min(q.y for q in t2)), int(math.ceil(max(q.y for q in t2)))
		den = (t2[1].y - t2[2].y) * (t2[0].x - t2[2].x) + (t2[2].x - t2[1].x) * (t2[0].y - t2[2].y)
		if abs(den) < 1e-9:
			continue
		for y in range(max(0, y0), min(size, y1 + 1)):
			for x in range(max(0, x0), min(size, x1 + 1)):
				c = Vector((x + 0.5, y + 0.5))
				w0 = ((t2[1].y - t2[2].y) * (c.x - t2[2].x) + (t2[2].x - t2[1].x) * (c.y - t2[2].y)) / den
				w1 = ((t2[2].y - t2[0].y) * (c.x - t2[2].x) + (t2[0].x - t2[2].x) * (c.y - t2[2].y)) / den
				w2 = 1.0 - w0 - w1
				# A texel's worth past the edges, so the islands' borders don't bleed the paint.
				if min(w0, w1, w2) < -0.15:
					continue
				m = marks(p3[0] * w0 + p3[1] * w1 + p3[2] * w2, n)
				if any(m):
					at = px[y * size + x]
					for i in range(3):
						drawn[i] += m[i] > at[i]
						at[i] = max(at[i], m[i])
	image = bpy.data.images.new("marks", size, size, alpha=False)
	flat_px = []
	for y in range(size):
		# Blender's image rows run bottom first.
		for x in range(size):
			flat_px.extend(px[(size - 1 - y) * size + x] + [1.0])
	image.pixels = flat_px
	image.filepath_raw = out
	image.file_format = "PNG"
	image.save()
	print("marks: %s, %d px at %d (scar, stripes, hand: %s), height %.2f m" % (out, sum(drawn), size, drawn, height))


if __name__ == "__main__":
	main()
