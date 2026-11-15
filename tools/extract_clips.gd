extends SceneTree
## Saves some clips of an imported, retargeted animation scene as an
## AnimationLibrary resource, so the game ships a few clips rather than a
## whole animation pack (art/models/animations/goblin.res came from the
## Quaternius Universal Animation Library this way).
##
## 1. Copy the pack's .glb into build/ (never committed), e.g.
##    build/ual_extract/UAL1.glb (use the in-place file, not the _RM one: the
##    game moves bodies itself).
## 2. Give it a .glb.import whose _subresources -> nodes -> PATH:<armature>/
##    Skeleton3D sets "retarget/bone_map" (art/models/bonemaps/ual.tres for
##    UAL), and import: godot --headless --path . --import
## 3. godot --headless --path . -s res://tools/extract_clips.gd -- \
##        res://build/ual_extract/UAL1.glb res://art/models/animations/goblin.res \
##        Idle Walk Punch_Jab Hit_Chest Death01 Jog_Bwd Hit_Stomach Roll Jump_Land
## 4. Delete build/ual_extract.
##
## A library already at <out.res> keeps its clips; those named are added
## (or replaced), so more can be taken later without the first ones. A clip
## given as <pack name>=<name> is saved under the second. (Godot's import
## already drops a pack clip's "_Loop" and loops it: Pistol_Idle_Loop is
## Pistol_Idle here.)
##
## Track paths stay as retargeted (%GeneralSkeleton:<Bone>), so the library
## plays on any model imported with a SkeletonProfileHumanoid bone map.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		print("usage: -s res://tools/extract_clips.gd -- <scene.glb> <out.res> <clip> [<clip> ...]")
		quit(1)
		return
	var scene := (load(args[0]) as PackedScene).instantiate()
	var players := scene.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		print("%s has no AnimationPlayer" % args[0])
		scene.free()
		quit(1)
		return
	var source := (players[0] as AnimationPlayer).get_animation_library("")
	var library := AnimationLibrary.new()
	if ResourceLoader.exists(args[1]):
		library = (load(args[1]) as AnimationLibrary).duplicate(true)
		print("adding to %s's %d clips" % [args[1], library.get_animation_list().size()])
	var missing := 0
	for given in args.slice(2):
		var names := str(given).split("=")
		var clip := names[0]
		if not source.has_animation(clip):
			print("no clip %s" % clip)
			missing += 1
			continue
		var animation := source.get_animation(clip).duplicate(true) as Animation
		# A glb imported without step 2's bone map keeps its own bone paths (Armature/Skeleton3D:...), and
		# its clips play broken on every model (a fresh glb name imports with _subresources={}: 338
		# amended (9)'s first re-extract, its forehand 1.2 m off). Nothing is saved from such a glb.
		for t in animation.get_track_count():
			if not str(animation.track_get_path(t)).begins_with("%GeneralSkeleton:"):
				print("REFUSED %s: no bone map on its .import (%s's track %s is not retargeted); give %s.import step 2's retarget/bone_map, import, extract again" % [
					args[0], clip, animation.track_get_path(t), args[0]])
				scene.free()
				quit(1)
				return
		clip = names[1] if names.size() > 1 else clip
		if library.has_animation(clip):
			library.remove_animation(clip)
		library.add_animation(clip, animation)
		print("%s: %.2f s, %s, %d tracks" % [clip, animation.length, "loops" if animation.loop_mode != Animation.LOOP_NONE else "once",
			animation.get_track_count()])
	var error := ResourceSaver.save(library, args[1], ResourceSaver.FLAG_COMPRESS)
	print("saved %s: %s" % [args[1], error_string(error)])
	scene.free()
	quit(1 if missing > 0 or error != OK else 0)
