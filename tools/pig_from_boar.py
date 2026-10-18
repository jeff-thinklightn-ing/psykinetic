# The farm pig from the boar (creature.boar's own mesh and rig, the Quaternius Pig's clips): its
# bristle ridge laid down to the line of its back, its tusks drawn in to its snout, its barrel a
# little rounder, its coat pink-grey from the palette (the hooves kept dark). The coordinator's
# quick route (2026-10-18); a veto in game sends the pig to art-gen as a concept of its own.
#
#   blender -b art/kit/creatures/creature.boar/creature.boar.blend -P tools/pig_from_boar.py -- <out .blend>
#       [--coat ROW,COL] [--belly ROW,COL] [--height M]
#
# Then scaled whole (its rig and clips' moves with it) to --height (HEIGHT: a farm pig
# smaller than the wild boar).
#
# The boar stands with its front toward -Y, Z up. The ridge: along the back, any vertex within
# RIDGE_X of the middle line is held to the back's height there (the highest vertex a little off
# the middle, RIDGE_X..SIDE_X out, plus RIDGE_LIFT). The tusks: in front of SNOUT_Y, above
# SNOUT_Z, no vertex further out to the side than the snout's own half-width there.
import os
import sys

import bpy

RIDGE_X = 0.07
SIDE_X = 0.14
RIDGE_LIFT = 0.015
SNOUT_Y = -0.45
SNOUT_Z = 0.22
SNOUT_HALF = 0.075
## The barrel (between the legs, above them) widened by this.
BARREL = 1.08
HEIGHT = 0.75
## The palette rows' swatch for the coat and the belly patches (row 0: skin, pink-grey).
COAT = (0, 2)
BELLY = (0, 1)


def args() -> list:
	return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def main() -> None:
	a = args()
	if not a:
		raise SystemExit("usage: -- <out .blend> [--coat ROW,COL] [--belly ROW,COL]")
	out = os.path.abspath(a[0])
	coat = tuple(int(v) for v in a[a.index("--coat") + 1].split(",")) if "--coat" in a else COAT
	belly = tuple(int(v) for v in a[a.index("--belly") + 1].split(",")) if "--belly" in a else BELLY
	height = float(a[a.index("--height") + 1]) if "--height" in a else HEIGHT
	body = bpy.data.objects["Body"]
	mesh = body.data
	world = body.matrix_world
	inverse = world.inverted()
	points = [world @ v.co for v in mesh.vertices]
	# The back's line: per slab of Y, the highest point just off the middle.
	slab = 0.04
	back = {}
	for p in points:
		if RIDGE_X <= abs(p.x) <= SIDE_X:
			k = round(p.y / slab)
			back[k] = max(back.get(k, 0.0), p.z)
	ridge = tusks = 0
	for v, p in zip(mesh.vertices, points):
		q = p.copy()
		if abs(p.x) < RIDGE_X:
			k = round(p.y / slab)
			top = max(back.get(k + d, 0.0) for d in (-1, 0, 1)) + RIDGE_LIFT
			if top > RIDGE_LIFT and q.z > top:
				q.z = top
				ridge += 1
		if p.y < SNOUT_Y and p.z > SNOUT_Z and abs(p.x) > SNOUT_HALF:
			q.x = SNOUT_HALF if p.x > 0 else -SNOUT_HALF
			tusks += 1
		if -0.3 < p.y < 0.35 and p.z > 0.3:
			q.x *= BARREL
		v.co = inverse @ q
	# The coat: each face's swatch by its colour now (the boar's row 5 browns), the hooves
	# (the darkest, column 7) kept.
	image = bpy.data.images.load(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "kit", "palette.png"))
	rows = round(image.size[1] / (image.size[0] // 8))
	bpy.data.images.remove(image)
	uv = mesh.uv_layers.active.data
	at = lambda rc: ((rc[1] + 0.5) / 8.0, 1.0 - (rc[0] + 0.5) / rows)
	recoloured = 0
	for poly in mesh.polygons:
		u = sum(uv[li].uv[0] for li in poly.loop_indices) / len(poly.loop_indices)
		col = int(u * 8.0)
		if col == 7:
			continue
		to = at(coat if col == 5 else belly)
		for li in poly.loop_indices:
			uv[li].uv = to
		recoloured += 1
	# Scaled whole to the height, as tools/animal_palette.py scales an animal.
	sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
	from creature_rig import scale_reference  # noqa: E402
	arm = body.parent
	low = min((world @ v.co).z for v in mesh.vertices)
	top = max((world @ v.co).z for v in mesh.vertices)
	s = height / (top - low)
	body.parent = None
	scale_reference(arm, body, s)
	body.parent = arm
	body.matrix_parent_inverse = arm.matrix_world.inverted()
	for mod in body.modifiers:
		if mod.type == "ARMATURE":
			mod.object = arm
	bpy.context.scene["source"] = ("creature.boar's mesh (art-gen, fitted to the Quaternius Pig rig) made a farm pig by "
		+ "tools/pig_from_boar.py: its ridge laid down, its tusks drawn in, recoloured")
	bpy.context.preferences.filepaths.save_version = 0
	bpy.ops.wm.save_as_mainfile(filepath=out)
	print("pig: ridge %d vertices laid down, tusks %d drawn in, %d faces recoloured, scaled %.3f to %.2f m; wrote %s"
		% (ridge, tusks, recoloured, s, height, out))


if __name__ == "__main__":
	main()
