extends RefCounted
## A held piece against the head as the game's low camera sees it (451 amended (13), TASK 16's measure; anim_rig_test's
## _test_carry_view). The head is the Body mesh's triangles whose three vertices go mostly with Head or a bone under it,
## skinned at BoneAttachment3Ds (the pose as drawn, the reach's modifier in); the piece is its whole mesh. Each is drawn
## through a view's camera into CELL squares in the head's plane: the overlap of their outlines (cm2), split where the
## piece is the nearer (before the head) and the further (behind it). In 3D, in the body's frame: the piece's top
## against the chin (the lowest front head vertex at the midline) and its head's top (the part from where it spreads
## past HEAD_SPREAD of the haft's line, in its upper half) against the shoulder line (the upper arms' roots).

const CELL := 0.01
const HEAD_SPREAD := 0.04


## The views: name: [the camera's horizontal direction from the body (x left, z ahead), distance m, pitch deg]: the low
## camera at the nearest zoom (LOW_ZOOM_MIN) from the body's left and right side and its four quarters, front and back.
static func views() -> Dictionary:
	var d := Client3D.CAMERA_DISTANCE * Client3D.LOW_DISTANCE_SHARE * Client3D.LOW_ZOOM_MIN
	var p := Client3D.low_pitch_at(Client3D.LOW_ZOOM_MIN)
	var q := sqrt(0.5)
	return {"L": [Vector3(1, 0, 0), d, p], "R": [Vector3(-1, 0, 0), d, p],
		"FL": [Vector3(q, 0, q), d, p], "FR": [Vector3(-q, 0, q), d, p],
		"BL": [Vector3(q, 0, -q), d, p], "BR": [Vector3(-q, 0, -q), d, p],
		"F": [Vector3(0, 0, 1), d, p], "B": [Vector3(0, 0, -1), d, p]}


## BoneAttachment3Ds on every bone of [param sk], by bone index.
static func attach(sk: Skeleton3D) -> Dictionary:
	var at := {}
	for b in sk.get_bone_count():
		var on := BoneAttachment3D.new()
		on.bone_name = sk.get_bone_name(b)
		sk.add_child(on)
		at[b] = on
	return at


## The head's skin: {"set": [[vertex, [[bone, bind, weight, fix]...]]...], "tris": indices into set}.
static func head_skin(model: Node3D, sk: Skeleton3D) -> Dictionary:
	var head := sk.find_bone("Head")
	var head_set: Array = []
	var tris := PackedInt32Array()
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null or mi.mesh == null or mi.name != "Body":
			continue
		var binds := []
		for i in mi.skin.get_bind_count():
			var bb := mi.skin.get_bind_bone(i)
			if bb < 0:
				bb = sk.find_bone(mi.skin.get_bind_name(i))
			binds.append([bb, mi.skin.get_bind_pose(i)])
		var fix := mi.global_transform * sk.global_transform.affine_inverse()
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var index: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if bones.is_empty():
				continue
			var per := bones.size() / verts.size()
			var map := {}
			for v in verts.size():
				var infl := []
				var best := -1
				var bw := 0.0
				for k in per:
					var w := weights[v * per + k]
					if w <= 0.0:
						continue
					var bind: Array = binds[bones[v * per + k]]
					infl.append([bind[0], bind[1], w, fix])
					if w > bw:
						bw = w
						best = bind[0]
				if _under(sk, best, head):
					map[v] = head_set.size()
					head_set.append([verts[v], infl])
			if index.is_empty():
				index.resize(verts.size())
				for v in verts.size():
					index[v] = v
			for t in range(0, index.size() - 2, 3):
				if map.has(index[t]) and map.has(index[t + 1]) and map.has(index[t + 2]):
					tris.append(map[index[t]])
					tris.append(map[index[t + 1]])
					tris.append(map[index[t + 2]])
	return {"set": head_set, "tris": tris}


## The piece's mesh in its own space: {"verts", "tris", "head_from": the height its head part starts}.
static func piece_mesh(piece: Node3D) -> Dictionary:
	var verts := PackedVector3Array()
	var tris := PackedInt32Array()
	for mesh: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
		var into := piece.global_transform.affine_inverse() * mesh.global_transform
		for s in mesh.mesh.get_surface_count():
			var arr := mesh.mesh.surface_get_arrays(s)
			var base := verts.size()
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in vs:
				verts.append(into * v)
			var index: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if index.is_empty():
				for v in vs.size():
					index.append(v)
			for k in index:
				tris.append(base + k)
	var top := -INF
	for q in verts:
		top = maxf(top, q.y)
	var head_from := top
	for q in verts:
		if q.y > top * 0.5 and Vector2(q.x, q.z).length() > HEAD_SPREAD:
			head_from = minf(head_from, q.y)
	return {"verts": verts, "tris": tris, "head_from": head_from}


## One pose read: {"top_chin": the piece's top over the chin (m), "head_top_shoulders": its head part's top over the
## shoulder line (m), view: Vector3(overlap, before, behind) cm2 for each of [param views]}.
static func read(model: Node3D, sk: Skeleton3D, at: Dictionary, piece: Node3D, head: Dictionary, pm: Dictionary, view_list: Dictionary) -> Dictionary:
	var o := model.global_transform
	var inv := o.affine_inverse()
	var hp := PackedVector3Array()
	for e: Array in head["set"]:
		hp.append(_skinned(e, at))
	var pw := PackedVector3Array()
	var pv: PackedVector3Array = pm["verts"]
	for q in pv:
		pw.append(piece.global_transform * q)
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for w in hp:
		var b := inv * w
		lo = lo.min(b)
		hi = hi.max(b)
	var mid := (lo + hi) * 0.5
	var chin := INF
	for w in hp:
		var b := inv * w
		if b.z > mid.z and absf(b.x - mid.x) < 0.03:
			chin = minf(chin, b.y)
	var shoulder := ((inv * (at[sk.find_bone("LeftUpperArm")] as Node3D).global_position).y
		+ (inv * (at[sk.find_bone("RightUpperArm")] as Node3D).global_position).y) * 0.5
	var top := -INF
	var head_top := -INF
	for k in pw.size():
		var y := (inv * pw[k]).y
		top = maxf(top, y)
		if pv[k].y >= float(pm["head_from"]):
			head_top = maxf(head_top, y)
	var out := {"top_chin": top - chin, "head_top_shoulders": head_top - shoulder}
	for v: String in view_list:
		var spec: Array = view_list[v]
		var dir: Vector3 = o.basis * (spec[0] as Vector3)
		var dist: float = spec[1]
		var pitch := deg_to_rad(float(spec[2]))
		var cam := Transform3D(Basis.IDENTITY, o.origin + dir * dist * cos(pitch) + Vector3.UP * dist * sin(pitch)).looking_at(o.origin, Vector3.UP)
		out[v] = _overlap(cam, hp, head["tris"], pw, pm["tris"])
	return out


## The head and the piece drawn through [param cam] (perspective, scaled to the head's plane) into CELL squares:
## (overlap, the piece before the head, behind it) in cm2.
static func _overlap(cam: Transform3D, hp: PackedVector3Array, ht: PackedInt32Array, pw: PackedVector3Array, pt: PackedInt32Array) -> Vector3:
	var into := cam.affine_inverse()
	var hc := Vector3.ZERO
	for w in hp:
		hc += w
	hc /= maxf(hp.size(), 1)
	var plane := -(into * hc).z
	var h2 := PackedVector3Array()
	for w in hp:
		var c := into * w
		h2.append(Vector3(c.x / -c.z * plane, c.y / -c.z * plane, -c.z))
	var p2 := PackedVector3Array()
	for w in pw:
		var c := into * w
		p2.append(Vector3(c.x / -c.z * plane, c.y / -c.z * plane, -c.z))
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in h2:
		lo = lo.min(Vector2(q.x, q.y))
		hi = hi.max(Vector2(q.x, q.y))
	var ox := floori(lo.x / CELL) - 1
	var oy := floori(lo.y / CELL) - 1
	var nx := floori(hi.x / CELL) - ox + 2
	var ny := floori(hi.y / CELL) - oy + 2
	var hd := PackedFloat32Array()
	hd.resize(nx * ny)
	hd.fill(INF)
	_raster(h2, ht, hd, ox, oy, nx, ny)
	var pd := PackedFloat32Array()
	pd.resize(nx * ny)
	pd.fill(INF)
	_raster(p2, pt, pd, ox, oy, nx, ny)
	var both := 0
	var before := 0
	for k in nx * ny:
		if hd[k] < INF and pd[k] < INF:
			both += 1
			if pd[k] < hd[k]:
				before += 1
	var a := CELL * CELL * 10000.0
	return Vector3(both * a, before * a, (both - before) * a)


## Each triangle's cells inside the grid, keeping the nearest depth (the triangle's mean).
static func _raster(v: PackedVector3Array, tris: PackedInt32Array, depth: PackedFloat32Array, ox: int, oy: int, nx: int, ny: int) -> void:
	for t in range(0, tris.size() - 2, 3):
		var a := v[tris[t]]
		var b := v[tris[t + 1]]
		var c := v[tris[t + 2]]
		var x0 := maxi(floori(minf(a.x, minf(b.x, c.x)) / CELL) - ox, 0)
		var x1 := mini(floori(maxf(a.x, maxf(b.x, c.x)) / CELL) - ox, nx - 1)
		if x0 > x1:
			continue
		var y0 := maxi(floori(minf(a.y, minf(b.y, c.y)) / CELL) - oy, 0)
		var y1 := mini(floori(maxf(a.y, maxf(b.y, c.y)) / CELL) - oy, ny - 1)
		if y0 > y1:
			continue
		var z := (a.z + b.z + c.z) / 3.0
		var den := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
		if absf(den) < 1e-12:
			continue
		for y in range(y0, y1 + 1):
			var py := (y + oy + 0.5) * CELL
			for x in range(x0, x1 + 1):
				var px := (x + ox + 0.5) * CELL
				var l1 := ((b.y - c.y) * (px - c.x) + (c.x - b.x) * (py - c.y)) / den
				var l2 := ((c.y - a.y) * (px - c.x) + (a.x - c.x) * (py - c.y)) / den
				if l1 >= 0.0 and l2 >= 0.0 and l1 + l2 <= 1.0:
					var k := y * nx + x
					if z < depth[k]:
						depth[k] = z


static func _under(sk: Skeleton3D, b: int, top: int) -> bool:
	while b >= 0:
		if b == top:
			return true
		b = sk.get_bone_parent(b)
	return false


static func _skinned(e: Array, at: Dictionary) -> Vector3:
	var sum := Vector3.ZERO
	var tw := 0.0
	for inf: Array in e[1]:
		sum += ((inf[3] as Transform3D) * (at[inf[0]] as Node3D).global_transform * (inf[1] as Transform3D) * (e[0] as Vector3)) * float(inf[2])
		tw += float(inf[2])
	return sum / maxf(tw, 0.0001)
