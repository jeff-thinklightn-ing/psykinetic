# Gives a rigidly skinned quadruped's Neck bone a real share (the coordinator's option A for the
# Quaternius Pig's boar and boar king: every vertex was on one bone and Neck on none, so a head
# move tore the Body-Head seam 30-56 cm). Across the seam where Head-weighted vertices meet
# Body-weighted ones, a vertex's signed distance x from it (minus on Body's side, plus on Head's)
# sets its weights: Neck all at the seam, fading over WIDTH to its own bone either way
# (Body = -x/W and Neck = 1 + x/W on Body's side; Neck = 1 - x/W and Head = x/W on Head's).
# Only vertices on Body or Head move; legs keep their own; anything beyond WIDTH (the tusks, the
# snout, the haunches) stays as it was. Saves the .blend in place; export it after with
# tools/blender/export_slot.py.
#
#   blender -b <slot>.blend -P tools/blender/neck_blend.py -- [--width M]
#
# The width defaults to WIDTH_SHARE of the body's height (the armature's mesh, as it stands).
import bpy
import sys
from mathutils import kdtree

WIDTH_SHARE = 0.35  # 0.3 m on the stock boar: the least tear (0.13, 0.2 and 0.4 tore more)
FROM, NECK, TO = "Body", "Neck", "Head"
# The seam is ragged (Body throat vertices run under the jaw), so the blend would reach the snout.
# Between these shares of the head's length in front of its pivot (Head's head toward Head_end) a
# blended vertex fades to Head alone (smoothstep): past HEAD_RIGID the snout and the tusks ride
# rigid, and the throat under the jaw goes with the jaw. A hard cut there tore 7x; the fade doesn't.
HEAD_FADE, HEAD_RIGID = 0.3, 0.6

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
width = float(args[args.index("--width") + 1]) if "--width" in args else -1.0

body = next(o for o in bpy.data.objects if o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers))
groups = {g.name: g for g in body.vertex_groups}
for name in (FROM, NECK, TO):
	if name not in groups:
		raise SystemExit("neck_blend: %s has no %s group" % (body.name, name))
co = [body.matrix_world @ v.co for v in body.data.vertices]
arm = next(m.object for m in body.modifiers if m.type == "ARMATURE")
pivot = arm.matrix_world @ arm.data.bones[TO].head_local
tip = arm.matrix_world @ arm.data.bones[TO].children[0].head_local if arm.data.bones[TO].children else arm.matrix_world @ arm.data.bones[TO].tail_local
ahead = (tip - pivot)
head_length = max(ahead.length, 1e-6)
ahead.normalize()
if width <= 0.0:
	width = WIDTH_SHARE * (max(c.z for c in co) - min(c.z for c in co))


def owner(v) -> str:
	best = max(v.groups, key=lambda g: g.weight, default=None)
	return body.vertex_groups[best.group].name if best is not None else ""


own = [owner(v) for v in body.data.vertices]
seam: dict[str, list[int]] = {FROM: [], TO: []}
for e in body.data.edges:
	a, b = e.vertices
	if {own[a], own[b]} == {FROM, TO}:
		seam[own[a]].append(a)
		seam[own[b]].append(b)
trees = {}
for side, ids in seam.items():
	tree = kdtree.KDTree(len(ids))
	for i in ids:
		tree.insert(co[i], i)
	tree.balance()
	trees[side] = tree
if not seam[FROM]:
	raise SystemExit("neck_blend: no %s-%s seam on %s" % (FROM, TO, body.name))

moved = 0
for v in body.data.vertices:
	side = own[v.index]
	if side not in (FROM, TO):
		continue
	# Its distance to the seam: to the nearest seam vertex of the other side, halved across it.
	other = TO if side == FROM else FROM
	d = trees[other].find(co[v.index])[2]
	x = d if side == TO else -d
	if abs(x) >= width:
		continue
	if side == FROM:
		weights = {FROM: -x / width, NECK: 1.0 + x / width, TO: 0.0}
	else:
		weights = {FROM: 0.0, NECK: 1.0 - x / width, TO: x / width}
	f = ((co[v.index] - pivot).dot(ahead) / head_length - HEAD_FADE) / (HEAD_RIGID - HEAD_FADE)
	g = 0.0 if f <= 0.0 else 1.0 if f >= 1.0 else f * f * (3.0 - 2.0 * f)
	weights = {k: w * (1.0 - g) + (g if k == TO else 0.0) for k, w in weights.items()}
	for name, w in weights.items():
		if w > 0.0:
			groups[name].add([v.index], w, "REPLACE")
		else:
			groups[name].remove([v.index])
	moved += 1
print("neck_blend: %s, %d seam verts, %d verts blended over %.3f m" % (body.name, len(seam[FROM]) + len(seam[TO]), moved, width))
bpy.ops.wm.save_mainfile()
