extends SkeletonModifier3D
## A downed animal lying on its belly, alive (764, pc-character's side; the coordinator: a hurt
## deer down lies on its belly, legs folded under, chest up, head up on its neck, now and then
## lowering it; only the dead lie flat on their side). No animal art has a lying clip, so the
## pose is made on the rig over whatever clip plays (CreatureView keeps idle under it): each leg
## folded under the body, the body lowered till its trunk's underside is on the ground, the neck
## raised; alive over it a breath swelling the flank, the head lowered a while now and then, an
## ear flicked. Every bone is aimed in the body's own directions (its forward, its up, its
## side), found from the rig's rest, so one table serves the deer and stag, the boar and the
## rabbit. CreatureView makes one on its art's skeleton and eases [member weight] (lying down,
## getting up, and off as it dies).

## A breath: its period, and how much the flank swells along the up.
const BREATH_SECONDS := 1.4
const BREATH_SWELL := 0.06
## The head lowered: every so many seconds (a range), for so long.
const LOWER_EVERY := Vector2(3.0, 7.0)
const LOWER_SECONDS := 2.4
## An ear flicked.
const TWITCH_EVERY := Vector2(1.2, 3.5)
const TWITCH_SECONDS := 0.25
const TWITCH_ANGLE := 0.6
## A leg's segments aimed, from its foot back up (last first), in (forward, up) of the body,
## the side's outward added: a front leg's cannon back under the chest, its forearm forward and
## down from the elbow, above that down; a hind leg's cannon forward under the belly, its shank
## back along the ground, its thigh forward and down.
const FRONT_FOLD := [Vector2(-1.0, -0.05), Vector2(0.9, -0.3), Vector2(-0.3, -1.0)]
const HIND_FOLD := [Vector2(1.0, -0.05), Vector2(-1.0, -0.2), Vector2(0.7, -0.6)]
const SPLAY := 0.25
## The trunk's underside left this far off the ground lying (metres, the art's).
const TRUNK_CLEAR := 0.02
## The neck raised, and lowered (forward, up).
const NECK_UP := Vector2(0.55, 0.85)
const NECK_LOW := Vector2(0.9, -0.3)
const LIMB_WORDS: Array[String] = ["leg", "arm", "thigh", "shin", "foot", "paw"]

## 0 standing as its clip has it, 1 lying.
var weight := 0.0
## Seconds added to the clock it moves by (a still's own moment; 0 in play).
var shift := 0.0
var root := -1
var chest := -1
var necks: Array[int] = []
var ears: Array[int] = []
## Each leg: {"bones": its chain top down, "front": bool, "side": its outward (skeleton space),
## and where a hoof hangs off the rig's root (the deer's FF/FFB under its IK bones) "foot", the
## top of the branch it hangs in, and "foot_at", where that sits from the chain's last bone at
## rest: carried with it.}
var legs: Array[Dictionary] = []
## The root lowered by this when lying (skeleton space).
var drop := Vector3.ZERO
var forward := Vector3.FORWARD
## The skeleton's frame in the art's (the art upright, its feet at 0).
var to_art := Transform3D.IDENTITY
var up := Vector3.UP
var _rng := RandomNumberGenerator.new()
var _lower_at := 0.0
var _twitch_at := 0.0
var _ear := 0
## The drop per mesh (the same art, the same fold): measured once.
static var _drops := {}


## Its bones, found by name on [param skeleton] (under [param art], the art's root, upright),
## and how far lying lowers it.
func setup(skeleton: Skeleton3D, art: Node3D, seed: int) -> void:
	_rng.seed = seed
	to_art = Transform3D.IDENTITY
	var node: Node = skeleton
	while node != null and node != art:
		to_art = (node as Node3D).transform * to_art if node is Node3D else to_art
		node = node.get_parent()
	up = (to_art.basis.inverse() * Vector3.UP).normalized()
	var size := 0
	var chests: Array[int] = []
	var head := -1
	for bone in skeleton.get_bone_count():
		var name := skeleton.get_bone_name(bone).to_lower()
		if name.begins_with("ik") or name.begins_with("pole") or name.begins_with("ff") or name.ends_with("_end"):
			continue
		if skeleton.get_bone_parent(bone) < 0 and _descendants(skeleton, bone) > size:
			size = _descendants(skeleton, bone)
			root = bone
		if "torso" in name or "spine" in name:
			chests.append(bone)
		elif "neck" in name:
			necks.append(bone)
		elif "head" in name and head < 0:
			head = bone
		elif "ear" in name and not _limb(name) and "ear" not in skeleton.get_bone_name(skeleton.get_bone_parent(bone)).to_lower():
			ears.append(bone)
		elif _limb(name) and not _limb(skeleton.get_bone_name(skeleton.get_bone_parent(bone)).to_lower()):
			legs.append({"bones": _chain(skeleton, bone)})
	if chests.is_empty() and skeleton.find_bone("Body") >= 0:
		chests.append(skeleton.find_bone("Body"))
	chest = chests[chests.size() / 2] if not chests.is_empty() else -1
	if root < 0 or legs.is_empty():
		return
	var at := skeleton.get_bone_global_rest(root).origin
	var ahead := skeleton.get_bone_global_rest(head if head >= 0 else necks[0]).origin - at if head >= 0 or not necks.is_empty() else Vector3.FORWARD
	forward = (ahead - up * ahead.dot(up)).normalized()
	var across := up.cross(forward)
	var middle := 0.0
	for leg: Dictionary in legs:
		middle += skeleton.get_bone_global_rest(leg["bones"][0]).origin.dot(forward) / legs.size()
	for leg: Dictionary in legs:
		var start := skeleton.get_bone_global_rest(leg["bones"][0]).origin
		leg["front"] = start.dot(forward) > middle
		leg["side"] = across * signf((start - at).dot(across))
		var last: int = leg["bones"][-1]
		var tip := skeleton.get_bone_global_rest(last)
		var nearest := INF
		for bone in skeleton.get_bone_count():
			var name := skeleton.get_bone_name(bone).to_lower()
			if _under(skeleton, bone, root) or name.begins_with("ik") or name.begins_with("pole") or skeleton.get_bone_children(bone).size() > 0:
				continue
			var gap := skeleton.get_bone_global_rest(bone).origin.distance_to(tip.origin)
			if gap < nearest and (skeleton.get_bone_global_rest(bone).origin - tip.origin).dot(up) < 0.0:
				nearest = gap
				var top := bone  # The branch it hangs in (the deer's IKFrontLeg.L over FF.L): carried whole.
				while skeleton.get_bone_parent(top) >= 0:
					top = skeleton.get_bone_parent(top)
				leg["foot"] = top
				leg["foot_at"] = tip.affine_inverse() * skeleton.get_bone_global_rest(top)
	# Measured once in the tree, a call later: a skeleton just entering it doesn't pose yet.
	if skeleton.is_inside_tree():
		_measure.call_deferred(skeleton)
	else:
		skeleton.tree_entered.connect(_measure.call_deferred.bind(skeleton), CONNECT_ONE_SHOT)
	var now := _seconds()
	_lower_at = now + _rng.randf_range(1.0, LOWER_EVERY.x)
	_twitch_at = now + _rng.randf_range(0.3, TWITCH_EVERY.x)


func _measure(skeleton: Skeleton3D) -> void:
	if is_instance_valid(skeleton):
		drop = _measure_drop(skeleton, to_art)


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton != null and weight > 0.0:
		lie(skeleton, weight, _seconds())


## [param skeleton]'s pose (as its clip has it) folded down by [param amount], alive at
## [param now] (seconds).
func lie(skeleton: Skeleton3D, amount: float, now: float) -> void:
	if root < 0:
		return
	skeleton.set_bone_pose_position(root, skeleton.get_bone_pose_position(root) + drop * amount)
	for leg: Dictionary in legs:
		var bones: Array = leg["bones"]
		var fold: Array = FRONT_FOLD if leg["front"] else HIND_FOLD
		for i in bones.size():
			var aim: Vector2 = fold[mini(bones.size() - 1 - i, fold.size() - 1)]
			_aim(skeleton, bones[i], forward * aim.x + up * aim.y + (leg["side"] as Vector3) * SPLAY, amount)
		if leg.has("foot"):
			var foot: int = leg["foot"]
			var parent := skeleton.get_bone_parent(foot)
			var want := skeleton.get_bone_global_pose(bones[-1]) * (leg["foot_at"] as Transform3D)
			var local := (skeleton.get_bone_global_pose(parent).affine_inverse() if parent >= 0 else Transform3D.IDENTITY) * want
			var now_local := skeleton.get_bone_pose(foot)
			skeleton.set_bone_pose_position(foot, now_local.origin.lerp(local.origin, amount))
			skeleton.set_bone_pose_rotation(foot, now_local.basis.get_rotation_quaternion().slerp(local.basis.get_rotation_quaternion(), amount))
	if now >= _lower_at + LOWER_SECONDS:
		_lower_at = now + _rng.randf_range(LOWER_EVERY.x, LOWER_EVERY.y)
	var low := clampf((now - _lower_at) / LOWER_SECONDS, 0.0, 1.0)
	low = smoothstep(0.0, 0.3, low) * (1.0 - smoothstep(0.7, 1.0, low))
	var neck := NECK_UP.lerp(NECK_LOW, low)
	for bone in necks:
		_aim(skeleton, bone, forward * neck.x + up * neck.y, amount)
	if chest >= 0:
		var swell := BREATH_SWELL * amount * (0.5 - 0.5 * cos(TAU * now / BREATH_SECONDS))
		var along := (skeleton.get_bone_global_pose(chest).basis.inverse() * up).normalized().abs()
		skeleton.set_bone_pose_scale(chest, skeleton.get_bone_pose_scale(chest) * (Vector3.ONE + along * swell))
	if now >= _twitch_at + TWITCH_SECONDS:
		_twitch_at = now + _rng.randf_range(TWITCH_EVERY.x, TWITCH_EVERY.y)
		_ear = _rng.randi() % maxi(ears.size(), 1)
	var twitch := (now - _twitch_at) / TWITCH_SECONDS
	if twitch > 0.0 and twitch < 1.0 and not ears.is_empty():
		var length := skeleton.get_bone_global_pose(ears[_ear]).basis.y.normalized()
		_aim(skeleton, ears[_ear], length.rotated(length.cross(up).normalized(), TWITCH_ANGLE) if length.cross(up).length() > 0.05 else length,
				amount * sin(PI * twitch))


## [param bone] turned, by [param amount], so its length (its +Y) points along [param toward]
## (skeleton space).
static func _aim(skeleton: Skeleton3D, bone: int, toward: Vector3, amount: float) -> void:
	if bone < 0 or amount <= 0.0:
		return
	var global := skeleton.get_bone_global_pose(bone).basis.orthonormalized()
	var swing := Quaternion(global.y.normalized(), toward.normalized())
	var local := Quaternion(global.inverse() * Basis(swing) * global).normalized()
	skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * Quaternion.IDENTITY.slerp(local, clampf(amount, 0.0, 1.0)))


## How far lying lowers the root: from the trunk's underside folded (the skinned points whose
## main bone is not a leg's, a hoof's, the neck's or below it, nor the tail's) to the ground (the
## lowest point standing), less TRUNK_CLEAR, as a skeleton-space step down.
func _measure_drop(skeleton: Skeleton3D, to_art: Transform3D) -> Vector3:
	var meshes := skeleton.find_children("*", "MeshInstance3D", false, false)
	if meshes.is_empty() or (meshes[0] as MeshInstance3D).skin == null:
		return Vector3.ZERO
	var key := (meshes[0] as MeshInstance3D).mesh.get_instance_id()
	if not _drops.has(key):
		var skip := trunk_skip(skeleton)
		skeleton.reset_bone_poses()
		var ground := _lowest(skeleton, meshes[0] as MeshInstance3D, to_art)
		lie(skeleton, 1.0, -1000.0)  # Folded (drop still 0): the legs' fold moves skin blended into the trunk.
		var trunk := _lowest(skeleton, meshes[0] as MeshInstance3D, to_art, skip)
		skeleton.reset_bone_poses()
		_drops[key] = maxf(trunk - ground - TRUNK_CLEAR, 0.0)
	return -(to_art.basis.inverse() * Vector3(0.0, float(_drops[key]), 0.0))


## The bones not the trunk's: the legs', the hooves', the neck's and below, the tail's, and
## any off the root (the deer's IK bones).
func trunk_skip(skeleton: Skeleton3D) -> Dictionary:
	var skip := {}
	for leg: Dictionary in legs:
		for bone: int in leg["bones"]:
			skip[bone] = true
		if leg.has("foot"):
			skip[leg["foot"]] = true
	for bone in skeleton.get_bone_count():
		if (not necks.is_empty() and _under(skeleton, bone, necks[0])) or "tail" in skeleton.get_bone_name(bone).to_lower() 				or not _under(skeleton, bone, root):
			skip[bone] = true
	return skip


## [param mesh]'s lowest point skinned on [param skeleton]'s pose, in the art's up; the points
## whose main bone is in [param skip] left out.
static func _lowest(skeleton: Skeleton3D, mesh: MeshInstance3D, to_art: Transform3D, skip := {}) -> float:
	var skin := mesh.skin
	var poses: Array[Transform3D] = []
	var bound: Array[int] = []
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b) if skin.get_bind_name(b) == &"" else skeleton.find_bone(skin.get_bind_name(b))
		bound.append(bone)
		poses.append(skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(b))
	var low := INF
	for s in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / maxi(verts.size(), 1)
		for i in verts.size():
			var p := Vector3.ZERO
			var main := -1
			var most := -1.0
			for k in per:
				var w := weights[i * per + k]
				if w > 0.0:
					p += (poses[bones[i * per + k]] * verts[i]) * w
					if w > most:
						most = w
						main = bound[bones[i * per + k]]
			if not skip.has(main):
				low = minf(low, (to_art * p).y)
	return low


static func _limb(name: String) -> bool:
	if name.begins_with("ik") or name.begins_with("pole") or name.ends_with("_end"):
		return false
	return LIMB_WORDS.any(func(word: String) -> bool: return word in name)


## [param bone] and its limb children down to the foot (the first such child each time).
static func _chain(skeleton: Skeleton3D, bone: int) -> Array[int]:
	var chain: Array[int] = [bone]
	while true:
		var next := -1
		for child in skeleton.get_bone_children(chain[-1]):
			if _limb(skeleton.get_bone_name(child).to_lower()):
				next = child
				break
		if next < 0:
			return chain
		chain.append(next)
	return chain


## Whether [param bone] is [param top] or under it.
static func _under(skeleton: Skeleton3D, bone: int, top: int) -> bool:
	while bone >= 0:
		if bone == top:
			return true
		bone = skeleton.get_bone_parent(bone)
	return false


static func _descendants(skeleton: Skeleton3D, bone: int) -> int:
	var count := 0
	for child in skeleton.get_bone_children(bone):
		count += 1 + _descendants(skeleton, child)
	return count


func _seconds() -> float:
	return Time.get_ticks_msec() / 1000.0 + shift
