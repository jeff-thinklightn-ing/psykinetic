extends SkeletonModifier3D
## A person's head drawn HEAD_SCALE of its built size (the coordinator's pick, from
## C:/dev/review/pc-character/head_size_sheet.png: the heads sat pinched on the shoulders, under hood
## and hat). The Head bone's pose scaled after the animation, every frame: every clip keys every bone's
## scale, so a scale set once on the pose, or on the rest, is overwritten by the next frame's clip
## (the sheet's first render came out the same at all three sizes for that reason). The skeleton puts
## its poses back after each frame's modifiers, so the scale is never compounded.
##
## What rides the bone grows with it: the hair, beards, hood and brimmed hat (weighted to Head) and the
## "head" socket's pieces (the bard's hat). Its origin, the neck's top, does not move: the look-at's aim
## (Client3D._eyes_of) and anything placed by the bone's origin stay where they were. The name plates,
## bubbles and bars stand by the model's "height", not the bone.
## Client3D._size_head puts one on a person's skeleton (people "human" only, not an orc or kobold).

const HEAD_SCALE := 1.10

var _head := -1


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if _head < 0:
		_head = skeleton.find_bone("Head")
		if _head < 0:
			return
	skeleton.set_bone_pose_scale(_head, skeleton.get_bone_pose_scale(_head) * HEAD_SCALE)
