extends SceneTree
## Writes a slot's grey box as a .glb, the start of its Blender template
## (tools/art_template.ps1 opens it in Blender and saves the .blend): the
## same boxes, moving parts at their pivots and sockets the game makes for
## the slot, so the template is sized, placed and named as the slot is.
##   godot --headless --path . --script tools/art_template.gd -- <slot> <out.glb>


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or not ArtKit.has(args[0]):
		push_error("art_template: give a slot and a .glb to write (%s)" % [args])
		quit(1)
		return
	var slot := args[0]
	ArtKit.show_placeholders = true
	var node := ArtKit.instance(slot)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	document.append_from_scene(node, state)
	var error := document.write_to_filesystem(state, args[1])
	node.free()
	print("art_template: %s's grey box to %s: %s" % [slot, args[1], error_string(error)])
	quit(0 if error == OK else 1)
