extends SceneTree
## The pace of a model's gait clips: how fast (metres, so tiles, a second) the
## ground goes by under a planted foot when the clip plays at speed 1. A body
## moved at that pace while the clip plays keeps its planted foot still on the
## ground; Client3D's GAITS and the models' "stride" come from this.
##
## godot --headless --path . -s res://tools/gait_pace.gd -- \
##     <scene.glb> <clips.res> [<clip> ...]
## (clips default to Walk Jog_Fwd Sprint Jog_Bwd)
##
## The model stands at the origin, unmoved, its front as modelled (the toes
## ahead of the feet, measured from its rest). Each frame (1/240 s) the lower
## of its two toes is the planted one; its speed backwards along the front,
## over the frames it is within PLANTED_M of its lowest, is the ground's
## speed under it. The median of those is the pace, and the spread (the
## middle half) says how much the foot slips in any case.

const STEP := 1.0 / 240.0
const PLANTED_M := 0.02


var _done := false


# On the first frame, once the tree has taken the model in (an
# AnimationPlayer outside it poses nothing).
func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		_measure()
	return false


func _measure() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: -s res://tools/gait_pace.gd -- <scene.glb> <clips.res> [<clip> ...]")
		quit(1)
		return
	var clips: Array = args.slice(2) if args.size() > 2 else ["Walk", "Jog_Fwd", "Sprint", "Jog_Bwd"]
	var scene := (load(args[0]) as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	var skeleton := scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var animator := AnimationPlayer.new()
	scene.add_child(animator)
	animator.root_node = NodePath("..")
	animator.add_animation_library("", load(args[1]) as AnimationLibrary)
	var toes := [skeleton.find_bone("LeftToes"), skeleton.find_bone("RightToes")]
	var feet := [skeleton.find_bone("LeftFoot"), skeleton.find_bone("RightFoot")]
	var front := Vector3.ZERO
	for i in 2:
		front += _rest(skeleton, toes[i]) - _rest(skeleton, feet[i])
	front.y = 0.0
	front = front.normalized()
	var hips := _rest(skeleton, skeleton.find_bone("Hips")).y
	print("%s: front %s, hips %.3f m" % [args[0], front, hips])
	for clip: String in clips:
		if not animator.has_animation(clip):
			print("  %-10s (none)" % clip)
			continue
		var length := animator.get_animation(clip).length
		animator.play(clip)
		animator.seek(0.0, true)
		var samples: Array[float] = []
		var last := [_at(skeleton, toes[0]), _at(skeleton, toes[1])]
		var lows: Array[float] = [INF, INF]
		var heights: Array = []
		var speeds: Array = []
		var t := 0.0
		while t < length:
			animator.advance(STEP)
			t += STEP
			var now := [_at(skeleton, toes[0]), _at(skeleton, toes[1])]
			var planted := 0 if now[0].y <= now[1].y else 1
			lows[planted] = minf(lows[planted], now[planted].y)
			heights.append([planted, now[planted].y])
			speeds.append(-(now[planted] - last[planted]).dot(front) / STEP)
			last = now
		for i in heights.size():
			var foot: int = heights[i][0]
			if float(heights[i][1]) <= lows[foot] + PLANTED_M:
				samples.append(absf(float(speeds[i])))
		samples.sort()
		if samples.is_empty():
			print("  %-10s no planted frames" % clip)
			continue
		var n := samples.size()
		print("  %-10s pace %.2f m/s (middle half %.2f .. %.2f), %d frames planted of %d, clip %.2f s" % [
			clip, samples[n / 2], samples[n / 4], samples[n * 3 / 4], n, heights.size(), length])
	quit()


func _rest(skeleton: Skeleton3D, bone: int) -> Vector3:
	return _placed(skeleton) * skeleton.get_bone_global_rest(bone).origin


func _at(skeleton: Skeleton3D, bone: int) -> Vector3:
	return _placed(skeleton) * skeleton.get_bone_global_pose(bone).origin


## The skeleton's transform in the model's own.
func _placed(node: Node3D) -> Transform3D:
	var placed := Transform3D.IDENTITY
	while node != null and node.get_parent() is Node3D:
		placed = node.transform * placed
		node = node.get_parent() as Node3D
	return placed
