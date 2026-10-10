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
##        Idle Walk Punch_Jab Hit_Chest Death01
## 4. Delete build/ual_extract.
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
	var missing := 0
	for clip in args.slice(2):
		if not source.has_animation(clip):
			print("no clip %s" % clip)
			missing += 1
			continue
		var animation := source.get_animation(clip).duplicate(true) as Animation
		library.add_animation(clip, animation)
		print("%s: %.2f s, %s, %d tracks" % [clip, animation.length, "loops" if animation.loop_mode != Animation.LOOP_NONE else "once",
			animation.get_track_count()])
	var error := ResourceSaver.save(library, args[1], ResourceSaver.FLAG_COMPRESS)
	print("saved %s: %s" % [args[1], error_string(error)])
	scene.free()
	quit(1 if missing > 0 or error != OK else 0)
