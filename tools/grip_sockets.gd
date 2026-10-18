extends SceneTree
## Measures a humanoid model's hand grip (decision 451) in its hand bones'
## own frames, for Client3D's sockets: where the closed fist holds a thing
## (between the fingers' first knuckles and the palm) and the fist's axis
## (from the little finger's knuckle toward the index's: a held piece's +Y,
## out of the thumb's side), and each hand's length to its fingers' middle
## knuckles, to scale a model without finger bones by. Prints them; it
## changes nothing.
##   godot --headless --path . -s res://tools/grip_sockets.gd -- <model.glb> [...]


func _initialize() -> void:
	for path: String in OS.get_cmdline_user_args():
		var scene := (load(path) as PackedScene).instantiate()
		var skeleton := scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		for side: String in ["Right", "Left"]:
			var hand := skeleton.find_bone(side + "Hand")
			var frame := skeleton.get_bone_global_rest(hand).affine_inverse()
			var at := func(bone: String) -> Variant:
				var index := skeleton.find_bone(side + bone)
				return frame * skeleton.get_bone_global_rest(index).origin if index >= 0 else null
			var index_knuckle: Variant = at.call("IndexProximal")
			var little_knuckle: Variant = at.call("LittleProximal")
			var middle: Variant = at.call("MiddleIntermediate")
			if index_knuckle == null or little_knuckle == null or middle == null:
				print("%s %s: no finger bones (scale a measured hand's sockets by its hand's length)" % [path.get_file(), side])
				continue
			var knuckles: Vector3 = (index_knuckle + little_knuckle) * 0.5
			var axis: Vector3 = (index_knuckle - little_knuckle).normalized()
			print("%s %s: knuckles %s, fist axis %s, hand length %.3f" % [path.get_file(), side,
					knuckles.snapped(Vector3.ONE * 0.001), axis.snapped(Vector3.ONE * 0.01), (middle as Vector3).length()])
		scene.free()
	quit()
