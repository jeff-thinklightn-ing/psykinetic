extends Node
## The slung bow and its quiver fitted to the people's backs (662 amended (d), Jeff's pick "bow back
## 1"; build/bowpick's sheet): writes client3d/sling.json, which Client3D reads when a bow is slung
## or a quiver worn. For the man's and the woman's body, standing (Idle's first frame), at scale 1:
## the bow slung across the back, its belly to the body, from the left hip up past the right shoulder,
## rolled and pitched about its own line until the gap along it is least, then pushed in until its
## nearest point is SLING_CLEAR off the skin (Client3D's); the quiver the same, beside the wood toward
## the neck, its mouth at the right shoulder, slid along its line to where most of it lies over the
## body. Then, for each slice of each piece (BIN of its length), its gap to the skin along the
## piece's inward axis, at the body's base shape and again with each shape key at 1 (the change):
## shape keys move the skin linearly, so a build's gaps are base + the sum of key x change. The
## string's path over the chest (round the shoulder, the shoulder top, the left hip's front, the
## front of the chest at STRING_SAMPLES points between, round the hip to its side and down the
## thigh's; each with its changes too) and the contacts the bow is aimed by
## (its top on UpperChest, its foot on Hips). The skin is the trunk's, shoulders' and thighs'.
## Run it after the bow, the quiver or the bodies change:
##   godot --headless --path . --scene res://tools/sling_fit.tscn
## (anim_rig_test _test_bow_back measures the result on the five builds and the gaits).
const OUT := "res://client3d/sling.json"
const MODELS := ["res://art/models/characters/human_m.glb", "res://art/models/characters/human_f.glb"]
const SURFACE_BONES := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "LeftShoulder", "RightShoulder", "LeftUpperLeg", "RightUpperLeg"]
const BIN := 0.05
const STRING_SAMPLES := 21
const BOW_IN := Vector3(0, 0, -1)
const QUIVER_IN := Vector3(0, 0, 1)
## The quiver's axis from the bow's line, across the back (its 0.06 half-width, the wood's 0.03, the
## bow's limbs curving in toward it, clear).
const QUIVER_BESIDE := 0.095
## The skin triangles kept for each slice (Client3D._sling_lie), by their middles: this far
## across its inward line, this far behind it and ahead.
const PROXY_REACH := 0.12
const PROXY_BEHIND := 0.08
const PROXY_AHEAD := 0.3
const STRING_LIFT := 0.006
## Round the hip the string stands this far off (taut from the hip's side to the bow's foot nock,
## off the thigh, it would cross the bulge where hip meets thigh).
const ROUND_LIFT := 0.025


func _ready() -> void:
	var lib := load("res://art/models/animations/goblin.res") as AnimationLibrary
	var table := {}
	for path: String in MODELS:
		var holder := Node3D.new()
		add_child(holder)
		var scene := (load(path) as PackedScene).instantiate() as Node3D
		scene.rotation.y = PI * 0.5
		holder.add_child(scene)
		var skeleton := scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var on := {}
		for bone: String in ["UpperChest", "Hips"]:
			var at := BoneAttachment3D.new()
			at.bone_name = bone
			skeleton.add_child(at)
			on[bone] = at
		var rig := AnimRig.make(scene, lib, 0.0, true, null)
		rig.base_at("Idle", 0.0)
		for i in 4:
			await get_tree().process_frame
		table[path] = await _fit(scene, on)
		holder.queue_free()
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(table) + "\n")
	file.close()
	print("wrote ", OUT)
	get_tree().quit()


func _fit(scene: Node3D, on: Dictionary) -> Dictionary:
	var skeleton := scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var body := scene.find_child("Body", true, false) as MeshInstance3D
	var at := func(bone: String) -> Vector3:
		return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin
	var up := Vector3.UP
	var left: Vector3 = at.call("LeftUpperArm") - at.call("RightUpperArm")
	left.y = 0.0
	left = left.normalized()
	var front := left.cross(up).normalized()
	var surf := surface(scene)
	var bow := ArtKit.instance("item.bow")
	add_child(bow)
	var quiver := ArtKit.instance(Client3D.QUIVER, 1)
	add_child(quiver)
	# The bow: its back (+z) out, its belly and tips to the body.
	var top: Vector3 = at.call("RightUpperArm") + up * 0.12
	var foot: Vector3 = at.call("LeftUpperLeg") + left * 0.06
	var along := (top - foot).normalized()
	var out := (-front - along * (-front).dot(along)).normalized()
	var bow_points := facing(bow, BOW_IN, "string")
	var laid := lay(surf, bow_points, BOW_IN, Basis(along.cross(out), along, out), (top + foot) * 0.5 - front * 0.35)
	var bow_xf := Transform3D(laid[0], laid[1])
	# The quiver: its +z (the strap) to the body, beside the wood toward the neck.
	var side := out.cross(along).normalized()
	if side.dot(up) < 0.0:
		side = -side
	var q_points := facing(quiver, QUIVER_IN, "")
	var q_laid := lay(surf, q_points, QUIVER_IN, Basis(along.cross(-out), along, -out), (laid[1] as Vector3) + side * QUIVER_BESIDE - front * 0.3, true)
	var q_xf := Transform3D(q_laid[0], q_laid[1])
	# The string's bottom end, as Client3D._string_rods finds it.
	var nock := Vector3.ZERO
	for string: MeshInstance3D in bow.find_children("*string*", "MeshInstance3D", true, false):
		var box := (bow.global_transform.affine_inverse() * string.global_transform) * string.get_aabb()
		nock = bow_xf * Vector3(box.get_center().x, box.position.y, box.get_center().z)
	bow.queue_free()
	quiver.queue_free()
	var bow_gaps := gaps(surf, bow_points, BOW_IN, bow_xf.basis, bow_xf.origin)
	var chest := (on["UpperChest"] as Node3D).global_transform
	var hips := (on["Hips"] as Node3D).global_transform
	var string_line := func(s: Array) -> Dictionary:
		# The shoulder's top, the left hip's front, and the chest's front between, along the line.
		var shoulder: Vector3 = (at.call("Neck") as Vector3).lerp(at.call("RightUpperArm"), 0.55)
		var down := gap(s, shoulder + up * 0.4, -up)
		shoulder += up * (0.4 - down) if down < INF else Vector3.ZERO
		var hip: Vector3 = at.call("LeftUpperLeg") + up * 0.06 + left * 0.06
		var to_front := gap(s, hip + front * 0.5, -front)
		hip += front * (0.5 - to_front) if to_front < INF else front * 0.15
		var offsets := PackedFloat32Array()
		for i in STRING_SAMPLES:
			var g := gap(s, shoulder.lerp(hip, i / float(STRING_SAMPLES - 1)) + front * 0.5, -front)
			offsets.append(maxf(0.0, 0.5 - g) if g < INF else 0.0)
		# Round the shoulder (behind its top, before it) and round the hip (from its front to
		# its side, and down the thigh on the bottom nock's side): the skin met from [d] toward
		# the joint, STRING_LIFT off it.
		var round_on := func(centre: Vector3, d: Vector3, lift: float) -> Vector3:
			var g := gap(s, centre + d * 0.5, -d)
			return chest.affine_inverse() * (centre + d * ((0.5 - g if g < INF else 0.12) + lift))
		var joint: Vector3 = (at.call("Neck") as Vector3).lerp(at.call("RightUpperArm"), 0.55)
		var hip_joint: Vector3 = at.call("LeftUpperLeg") + up * 0.06 + left * 0.06
		var over: Array[Vector3] = [round_on.call(joint, (up - front).normalized(), STRING_LIFT), round_on.call(joint, (up + front).normalized(), STRING_LIFT)]
		var round: Array[Vector3] = []
		for angle: float in [45.0, 90.0]:
			round.append(round_on.call(hip_joint, front * cos(deg_to_rad(angle)) + left * sin(deg_to_rad(angle)), ROUND_LIFT))
		var low: Vector3 = hip_joint - up * 0.12
		for f: float in [0.0, 0.5]:
			var on_thigh := low + up * (nock - low).dot(up) * f
			var toward := nock - on_thigh
			toward -= up * toward.dot(up)
			round.append(round_on.call(on_thigh, toward.normalized() if toward.length() > 0.001 else left, ROUND_LIFT))
		return {"shoulder": chest.affine_inverse() * shoulder, "hip": chest.affine_inverse() * hip, "front": offsets, "over": over, "round": round}
	var base_line: Dictionary = string_line.call(surf)
	# The skin each slice could meet as the body moves: the trunk's, shoulders' and thighs'
	# triangles ahead of it (along its inward) and within PROXY_REACH across, their vertices kept
	# with their weights, rest places and shape-key changes, so Client3D skins them each frame.
	var raw: Dictionary = surf[2]
	var tri_v: PackedInt32Array = raw["tri_v"]
	var all_tris: PackedVector3Array = surf[0]
	var proxy: Array = []
	var proxy_of := {}
	var proxy_tris := PackedInt32Array()
	var tri_of := {}
	var nears := func(points: PackedVector3Array, inward: Vector3, xf: Transform3D) -> Array:
		var each: Array = []
		var into := (xf.basis * inward).normalized()
		for v in points:
			var at_slice := xf.basis * v + xf.origin
			var found: Array = []
			for t in tri_v.size() / 3:
				var d := (all_tris[t * 3] + all_tris[t * 3 + 1] + all_tris[t * 3 + 2]) / 3.0 - at_slice
				var ahead := d.dot(into)
				if ahead < -PROXY_BEHIND or ahead > PROXY_AHEAD or (d - into * ahead).length() > PROXY_REACH:
					continue
				if not tri_of.has(t):
					tri_of[t] = proxy_tris.size() / 3
					for corner in 3:
						var i := tri_v[t * 3 + corner]
						if not proxy_of.has(i):
							proxy_of[i] = proxy.size()
							proxy.append(i)
						proxy_tris.append(proxy_of[i])
				found.append(tri_of[t])
			each.append(found)
		return each
	var bow_near: Array = nears.call(bow_points, BOW_IN, bow_xf)
	var quiver_near: Array = nears.call(q_points, QUIVER_IN, q_xf)
	var entry := {
		"bow": _xf(chest.affine_inverse() * bow_xf), "quiver": _xf(chest.affine_inverse() * q_xf),
		"bow_y": _ys(bow_points), "quiver_y": _ys(q_points),
		"bow_gap": {"": _gaps_out(bow_gaps)}, "quiver_gap": {"": _gaps_out(gaps(surf, q_points, QUIVER_IN, q_xf.basis, q_xf.origin))},
		"hips_from_chest": _xf(hips.affine_inverse() * chest),
		"front": _v((chest.basis.inverse() * front).normalized()), "up": _v((chest.basis.inverse() * up).normalized()),
		"shoulder": {"": _v(base_line["shoulder"])}, "hip": {"": _v(base_line["hip"])}, "string": {"": _floats(base_line["front"])},
		"over": {"": _vs(base_line["over"])}, "round": {"": _vs(base_line["round"])},
		"bow_pts": _vs(bow_points), "quiver_pts": _vs(q_points), "bow_near": bow_near, "quiver_near": quiver_near,
		"proxy": _proxy_out(raw, proxy), "proxy_tris": Array(proxy_tris),
	}
	var shapes := body.mesh as ArrayMesh
	for k in shapes.get_blend_shape_count():
		var key := String(shapes.get_blend_shape_name(k))
		body.set_blend_shape_value(k, 1.0)
		var shaped := surface(scene)
		body.set_blend_shape_value(k, 0.0)
		var line: Dictionary = string_line.call(shaped)
		entry["bow_gap"][key] = _change(gaps(shaped, bow_points, BOW_IN, bow_xf.basis, bow_xf.origin), bow_gaps)
		entry["quiver_gap"][key] = _change(gaps(shaped, q_points, QUIVER_IN, q_xf.basis, q_xf.origin), gaps(surf, q_points, QUIVER_IN, q_xf.basis, q_xf.origin))
		entry["shoulder"][key] = _v((line["shoulder"] as Vector3) - (base_line["shoulder"] as Vector3))
		entry["hip"][key] = _v((line["hip"] as Vector3) - (base_line["hip"] as Vector3))
		var front_change := PackedFloat32Array()
		for i in STRING_SAMPLES:
			front_change.append((line["front"] as PackedFloat32Array)[i] - (base_line["front"] as PackedFloat32Array)[i])
		entry["string"][key] = _floats(front_change)
		for name: String in ["over", "round"]:
			var change: Array[Vector3] = []
			for i in (base_line[name] as Array).size():
				change.append((line[name][i] as Vector3) - (base_line[name][i] as Vector3))
			entry[name][key] = _vs(change)
	await get_tree().process_frame
	return entry


## The proxy vertices for the table: {"binds": {bone: its bind pose}, "points": [{"v": rest place,
## "skin": [[bone, weight], ...], "keys": {key: change at 1}}, ...]}.
static func _proxy_out(raw: Dictionary, proxy: Array) -> Dictionary:
	var base: PackedVector3Array = raw["base"]
	var bones: PackedInt32Array = raw["bones"]
	var weights: PackedFloat32Array = raw["weights"]
	var per: int = raw["per"]
	var binds := {}
	var points: Array = []
	for i: int in proxy:
		var skin: Array = []
		for k in per:
			var w := weights[i * per + k]
			if w <= 0.0:
				continue
			var bone: String = raw["bind_bone"][bones[i * per + k]]
			binds[bone] = _xf(raw["binds"][bones[i * per + k]])
			skin.append([bone, _r(w)])
		var keys := {}
		for key: String in raw["deltas"]:
			var d: Vector3 = raw["deltas"][key][i]
			if d.length() > 0.0002:
				keys[key] = _v(d)
		points.append({"v": _v(base[i]), "skin": skin, "keys": keys})
	return {"binds": binds, "points": points}


static func _r(x: float) -> float:
	return snappedf(x, 0.0001)


static func _v(v: Vector3) -> Array:
	return [_r(v.x), _r(v.y), _r(v.z)]


static func _vs(points: Array) -> Array:
	var out := []
	for p: Vector3 in points:
		out.append(_v(p))
	return out


static func _xf(t: Transform3D) -> Array:
	return _v(t.basis.x) + _v(t.basis.y) + _v(t.basis.z) + _v(t.origin)


static func _floats(values: PackedFloat32Array) -> Array:
	var out := []
	for v in values:
		out.append(_r(v))
	return out


static func _ys(points: PackedVector3Array) -> Array:
	var out := []
	for p in points:
		out.append(_r(p.y))
	return out


## Off the body as null.
static func _gaps_out(values: PackedFloat32Array) -> Array:
	var out := []
	for v in values:
		out.append(null if v == INF else _r(v))
	return out


## A key's change to each slice's gap (0 where either is off the body).
static func _change(shaped: PackedFloat32Array, base: PackedFloat32Array) -> Array:
	var out := []
	for i in base.size():
		out.append(0.0 if shaped[i] == INF or base[i] == INF else _r(shaped[i] - base[i]))
	return out


## The body's skin as posed, the trunk, shoulders and thighs: [triangles (3 points each), their normals].
static func surface(model: Node3D) -> Array:
	var body := model.find_child("Body", true, false) as MeshInstance3D
	var skeleton := body.get_parent() as Skeleton3D
	var shaped := body.mesh as ArrayMesh
	var src := shaped.surface_get_arrays(0)
	var base: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var verts := base.duplicate()
	var normals: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
	var shapes := shaped.surface_get_blend_shape_arrays(0)
	for k in shapes.size():
		var weight := body.get_blend_shape_value(k)
		if weight == 0.0:
			continue
		var shape: PackedVector3Array = shapes[k][Mesh.ARRAY_VERTEX]
		for i in verts.size():
			verts[i] += (shape[i] - base[i] if shaped.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED else shape[i]) * weight
	var bones: PackedInt32Array = src[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = src[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / verts.size()
	var skin := body.skin
	var poses: Array[Transform3D] = []
	for b in skin.get_bind_count():
		var bone_index := skin.get_bind_bone(b) if skin.get_bind_name(b) == &"" else skeleton.find_bone(skin.get_bind_name(b))
		poses.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone_index) * skin.get_bind_pose(b))
	var posed := PackedVector3Array()
	var posed_n := PackedVector3Array()
	var keep := PackedByteArray()
	for i in verts.size():
		var p := Vector3.ZERO
		var n := Vector3.ZERO
		var best := 0
		for k in per:
			var w := weights[i * per + k]
			if w <= 0.0:
				continue
			var pose := poses[bones[i * per + k]]
			p += pose * verts[i] * w
			n += pose.basis * normals[i] * w
			if w > weights[i * per + best]:
				best = k
		var b := bones[i * per + best]
		var bone := String(skin.get_bind_name(b)) if skin.get_bind_name(b) != &"" else skeleton.get_bone_name(skin.get_bind_bone(b))
		posed.append(p)
		posed_n.append(n.normalized())
		keep.append(1 if bone in SURFACE_BONES else 0)
	var index: PackedInt32Array = src[Mesh.ARRAY_INDEX]
	var tris := PackedVector3Array()
	var tri_n := PackedVector3Array()
	var tri_v := PackedInt32Array()
	for t in index.size() / 3:
		var a := index[t * 3]
		var b := index[t * 3 + 1]
		var c := index[t * 3 + 2]
		if keep[a] + keep[b] + keep[c] < 2:
			continue
		tris.append_array([posed[a], posed[b], posed[c]])
		tri_n.append((posed_n[a] + posed_n[b] + posed_n[c]).normalized())
		tri_v.append_array([a, b, c])
	var bind_bone := PackedStringArray()
	var binds: Array[Transform3D] = []
	for b in skin.get_bind_count():
		bind_bone.append(String(skin.get_bind_name(b)) if skin.get_bind_name(b) != &"" else skeleton.get_bone_name(skin.get_bind_bone(b)))
		binds.append(skin.get_bind_pose(b))
	var deltas := {}
	for k in shapes.size():
		var shape: PackedVector3Array = shapes[k][Mesh.ARRAY_VERTEX]
		var delta := PackedVector3Array()
		delta.resize(base.size())
		for i in base.size():
			delta[i] = shape[i] - base[i] if shaped.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED else shape[i]
		deltas[String(shaped.get_blend_shape_name(k))] = delta
	return [tris, tri_n, {"base": base, "bones": bones, "weights": weights, "per": per, "posed": posed, "keep": keep, "tri_v": tri_v,
		"bind_bone": bind_bone, "binds": binds, "deltas": deltas}]


## The gap from [p] to the skin along [inward]: positive clear of it, negative inside it (the
## depth), INF when nothing is met within half a metre.
static func gap(surf: Array, p: Vector3, inward: Vector3) -> float:
	var tris: PackedVector3Array = surf[0]
	var ns: PackedVector3Array = surf[1]
	var best_in := INF
	var best_out := INF
	var exiting := false
	for t in ns.size():
		var a := tris[t * 3]
		var b := tris[t * 3 + 1]
		var c := tris[t * 3 + 2]
		var hit: Variant = Geometry3D.ray_intersects_triangle(p, inward, a, b, c)
		if hit != null:
			best_in = minf(best_in, p.distance_to(hit))
		hit = Geometry3D.ray_intersects_triangle(p, -inward, a, b, c)
		if hit != null and p.distance_to(hit) < best_out:
			best_out = p.distance_to(hit)
			exiting = ns[t].dot(-inward) > 0.0
	if best_out < 0.5 and exiting:
		return -best_out
	return best_in if best_in < 0.5 else INF


## The triangles near [at] (within [reach]), so the fits test fewer.
static func near(surf: Array, at: Vector3, reach: float) -> Array:
	var tris: PackedVector3Array = surf[0]
	var ns: PackedVector3Array = surf[1]
	var out_t := PackedVector3Array()
	var out_n := PackedVector3Array()
	for t in ns.size():
		if (tris[t * 3] + tris[t * 3 + 1] + tris[t * 3 + 2]).distance_to(at * 3.0) < reach * 3.0:
			out_t.append_array([tris[t * 3], tris[t * 3 + 1], tris[t * 3 + 2]])
			out_n.append(ns[t])
	return [out_t, out_n]


## A piece's points facing the body, one per BIN of its length (local y): the farthest along
## [inward] (local) of that slice. [skip] names a part left out (the bow's string).
static func facing(piece: Node3D, inward: Vector3, skip: String) -> PackedVector3Array:
	var bins := {}
	for mesh: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
		if skip != "" and mesh.name.contains(skip):
			continue
		var to_piece := piece.global_transform.affine_inverse() * mesh.global_transform
		for s in mesh.mesh.get_surface_count():
			for v: Vector3 in mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var p := to_piece * v
				var k := int(floor(p.y / BIN))
				if not bins.has(k) or p.dot(inward) > (bins[k] as Vector3).dot(inward):
					bins[k] = p
	var out := PackedVector3Array()
	var keys := bins.keys()
	keys.sort()
	for k: int in keys:
		out.append(bins[k])
	return out


## Gaps of [points] placed by [basis] at [centre], along the basis's [inward].
static func gaps(surf: Array, points: PackedVector3Array, inward: Vector3, basis: Basis, centre: Vector3) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var into := (basis * inward).normalized()
	for v in points:
		out.append(gap(surf, basis * v + centre, into))
	return out


## [least, most, count] of the finite gaps.
static func span(values: PackedFloat32Array) -> Array:
	var least := INF
	var most := -INF
	var n := 0
	for g in values:
		if g < INF:
			least = minf(least, g)
			most = maxf(most, g)
			n += 1
	return [least, most, n]


## Rolls and pitches [basis] about its own y and x to lay [points] flattest on the skin (slid
## along its line first when [slide], to where most of it lies over the body), then pushes it in
## along [inward] (as it started) until the nearest is SLING_CLEAR off it: [basis, centre].
static func lay(surf: Array, points: PackedVector3Array, inward: Vector3, basis: Basis, centre: Vector3, slide := false) -> Array:
	var close := near(surf, centre, 0.9)
	if slide:
		var most := -1
		var at := centre
		for step: int in [0, -1, 1, -2, 2, -3, 3, -4, 4, -5, 5, -6, 6]:
			var c: Vector3 = centre + basis.y.normalized() * 0.05 * step
			var n: int = span(gaps(close, points, inward, basis, c))[2]
			if n > most:
				most = n
				at = c
		centre = at
	var best := basis
	var need: int = maxi(int(span(gaps(close, points, inward, basis, centre))[2]) - 1, 2)
	var best_score := INF
	for round in 2:
		for axis: Vector3 in [Vector3.UP, Vector3.RIGHT]:
			var around := best
			for step in range(-4, 5):
				var b := around * Basis(axis, deg_to_rad(5.0 * step))
				var s: Array = span(gaps(close, points, inward, b, centre))
				if int(s[2]) < need:
					continue
				var score := float(s[1]) - float(s[0])
				if score < best_score - 0.0005:
					best_score = score
					best = b
	# In along the way it started (along its own rolled axis it would slide across the back),
	# measured along its own, until the nearest is SLING_CLEAR off.
	var into := (basis * inward).normalized()
	for i in 4:
		var s: Array = span(gaps(close, points, inward, best, centre))
		centre += into * (float(s[0]) - Client3D.SLING_CLEAR) / maxf(into.dot((best * inward).normalized()), 0.5)
	return [best, centre]
