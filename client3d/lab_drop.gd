extends RefCounted
## The Character Lab's drop folder (674 step 2; Jeff: "i also need to work on
## the player model and run animations separately"): Jeff's Blender exports
## brought into the running lab. The lab calls poll() about once a second.
##
## Watched: DROP's human_m.glb and human_f.glb (bodies) and clips/*.glb (one or
## more actions each; "_Loop" at a name's end loops it, as the game's import
## does). A file is taken once its size and time have held still SETTLE_MSEC
## (Blender's write done); anything else of a model's kind (.gltf, .fbx,
## .blend) is named in the status and left alone. A taken file is copied into
## OUT (build/lab, gitignored) with a .glb.import from TEMPLATE (the bodies'
## import, the UAL bone map onto SkeletonProfileHumanoid; clips with their
## animations), and imported as a process of its own through the resource
## gate (`heavy_job.py run <checkout's folder> godot_import --expect
## IMPORT_MINUTES`), never a bare import and never one this process holds a
## take for. Done, each is loaded fresh (CACHE_MODE_REPLACE, so a second
## export at the same path is the new one), once checked: a body's skeleton has
## the humanoid bones (the retarget found the UAL names), a mesh named Body
## and a height in HEIGHT; a clip file has an animation with tracks on the
## skeleton. A good body becomes the lab's for its sex; good clips go into
## the lab's library (OUT's lab_clips.res, the game's clips with Jeff's over
## them). Each is checked as loaded fresh, and only a good one is kept in the
## cache, so a bad export keeps the last good, says why, and its copy goes. A
## gate that stops the import (the machine short) is tried once more. Nothing is written
## outside OUT: never art/, levels/, user:// or the drop folder.

const DROP := "C:/dev/review/character_lab/drop"
const OUT := "res://build/lab"
const TEMPLATE := "res://tools/lab/glb.import.template"
const BODIES := {"human_m.glb": "male", "human_f.glb": "female"}
const NOT_GLB: Array[String] = ["gltf", "fbx", "blend", "obj"]
const SETTLE_MSEC := 2000
const IMPORT_MINUTES := 10
## A body's height (metres) outside this is a scale not applied.
const HEIGHT := Vector2(1.3, 2.2)
## The humanoid bones a body or clip's skeleton must have after the retarget.
const BONES: Array[String] = ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftUpperArm", "LeftLowerArm",
	"LeftHand", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"RightUpperLeg", "RightLowerLeg", "RightFoot"]

var drop := DROP
var out := OUT
## Starts the import of what was copied; calls back done(ok: bool, log: String).
## The real one is a gated process (_import); lab_test's stands in.
var importer: Callable
## A path in OUT loaded (null when it won't load): (path, keep) fresh to be
## checked, or kept in the cache as the one the lab loads; lab_test's stands in.
var loader: Callable
## The status line, and whether it says something is wrong.
var status := "watching " + DROP
var bad := false
## What loaded: bodies {sex: scene path}, and the clips' names Jeff's ones replace or add.
var bodies := {}
var clip_names: Array[String] = []
## Bumped each time something new loads, for the lab to make its body again.
var loaded := 0

var _seen := {}  # relative path -> [size, time, since msec]
var _done := {}  # relative path -> [size, time] taken already
var _taking: Array[String] = []
var _pid := -1
var _started := 0
var _log := ""
var _retried := false


func _init() -> void:
	importer = _import
	loader = func(path: String, keep: bool) -> Resource:
		if not ResourceLoader.exists(path):
			return null
		return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE if keep else ResourceLoader.CACHE_MODE_IGNORE_DEEP)


## The lab's library of clips, once Jeff's have loaded.
func clips_path() -> String:
	return out.path_join("lab_clips.res")


## One look at the drop folder at [param now] (msec): settled files taken,
## an import under way followed.
func poll(now: int) -> void:
	if _pid >= 0:
		_follow(now)
		return
	if not _taking.is_empty():
		return
	var ready: Array[String] = []
	for rel in _files():
		var path := drop.path_join(rel)
		var stamp := [_size(path), FileAccess.get_modified_time(path)]
		if _done.get(rel) == stamp:
			continue
		var seen: Array = _seen.get(rel, [])
		if seen.is_empty() or seen[0] != stamp[0] or seen[1] != stamp[1]:
			_seen[rel] = [stamp[0], stamp[1], now]
		elif now - int(seen[2]) >= SETTLE_MSEC:
			ready.append(rel)
	if ready.is_empty():
		return
	for rel in ready:
		var to := out.path_join(rel)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(to.get_base_dir()))
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(drop.path_join(rel)), ProjectSettings.globalize_path(to)) != OK:
			_say("could not copy %s" % rel, true)
			continue
		var template := FileAccess.get_file_as_string(TEMPLATE)
		var file := FileAccess.open(to + ".import", FileAccess.WRITE)
		file.store_string(template.replace("{animation}", "false" if BODIES.has(rel) else "true"))
		file.close()
		_done[rel] = [_seen[rel][0], _seen[rel][1]]
		_taking.append(rel)
	if _taking.is_empty():
		return
	_say("%s changed: waiting for the machine (gate), then importing" % ", ".join(_taking), false)
	_started = now
	importer.call(_imported)


## R: everything in the drop folder taken again.
func force() -> void:
	_done.clear()
	_seen.clear()


func _files() -> Array[String]:
	var found: Array[String] = []
	var others: Array[String] = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(drop)):
		return found
	for name in DirAccess.get_files_at(drop):
		if BODIES.has(name):
			found.append(name)
		elif name.get_extension().to_lower() in NOT_GLB:
			others.append(name)
	var clips_dir := drop.path_join("clips")
	for name in (DirAccess.get_files_at(clips_dir) if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(clips_dir)) else PackedStringArray()):
		if name.get_extension().to_lower() == "glb":
			found.append("clips/" + name)
		elif name.get_extension().to_lower() in NOT_GLB:
			others.append("clips/" + name)
	if not others.is_empty() and _pid < 0 and _taking.is_empty():
		_say("%s: export as .glb (File > Export > glTF Binary)" % ", ".join(others), true)
	return found


static func _size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_length() if file != null else -1


## The real import: the checkout's own import, through the gate as this
## checkout's folder name, its output in OUT/import.log.
func _import(done: Callable) -> void:
	var checkout := ProjectSettings.globalize_path("res://").trim_suffix("/")
	_log = ProjectSettings.globalize_path(out.path_join("import.log"))
	var line := "python -B \"%s\" run %s godot_import --expect %d -- \"%s\" --headless --path \"%s\" --import > \"%s\" 2>&1" % [
		checkout.path_join("tools/heavy_job.py"), checkout.get_file(), IMPORT_MINUTES, OS.get_executable_path(), checkout, _log]
	_pid = OS.create_process("cmd.exe", ["/c", line])
	set_meta("done", done)
	if _pid < 0:
		_pid = -1
		done.call(false, "could not start the import")


func _follow(now: int) -> void:
	if OS.is_process_running(_pid):
		var words := FileAccess.get_file_as_string(_log)
		var waiting := "waiting" in words and not "taken" in words and not "starts" in words
		_say("%s: %s %d s" % [", ".join(_taking), "waiting for the machine (gate)" if waiting else "importing", (now - _started) / 1000], false)
		return
	_pid = -1
	var words := FileAccess.get_file_as_string(_log)
	var stopped := "stopped after" in words or "overrun" in words or "hung" in words
	(get_meta("done") as Callable).call(not stopped, words)


## The import over: each file taken loaded and checked.
func _imported(ok: bool, log: String) -> void:
	var taken := _taking.duplicate()
	_taking.clear()
	if not ok:
		if not _retried:
			_retried = true
			for rel in taken:
				_done.erase(rel)  # Taken again at the next look.
			_say("the machine is busy: trying again (%s)" % _tail(log), true)
		else:
			_say("import stopped: %s" % _tail(log), true)
		return
	_retried = false
	var problems: Array[String] = []
	var clips: AnimationLibrary = null
	var any := false
	for rel in taken:
		var path := out.path_join(rel)
		var resource: Resource = loader.call(path, false)
		var why := _check(rel, resource)
		if why == "" and not BODIES.has(rel):
			clips = _add_clips(clips, resource as PackedScene)
		if why != "":
			problems.append("%s: %s" % [rel, why])
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".import"))
			continue
		if BODIES.has(rel):
			var kept: Resource = loader.call(path, true)
			bodies[BODIES[rel]] = kept.resource_path if kept != null and kept.resource_path != "" else path
		any = true
	if clips != null:
		ResourceSaver.save(clips, clips_path())
		ResourceLoader.load(clips_path(), "", ResourceLoader.CACHE_MODE_REPLACE)
	if any:
		loaded += 1
	if not problems.is_empty():
		_say("; ".join(problems) + " (the last good kept)", true)
	else:
		_say("loaded %s %s" % [", ".join(taken), Time.get_time_string_from_system().left(5)], false)


## Why [param resource], from [param rel], is not a body or clips the lab can
## use; "" when it is.
static func _check(rel: String, resource: Resource) -> String:
	if not resource is PackedScene:
		return "the import failed (not a glTF binary?)"
	var scene := (resource as PackedScene).instantiate()
	var why := ""
	var skeletons := scene.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		why = "no armature in it"
	else:
		var skeleton := skeletons[0] as Skeleton3D
		var missing := BONES.filter(func(bone: String) -> bool: return skeleton.find_bone(bone) < 0)
		if not missing.is_empty():
			why = "bones %s not found: keep the UAL bone names and the armature named Armature (README)" % ", ".join(missing.slice(0, 3))
	if why == "" and BODIES.has(rel):
		var body := scene.find_child("Body", true, false) as MeshInstance3D
		if body == null:
			why = "no mesh named Body"
		else:
			# Scaled by its own and its parents' transforms (not in a tree: no global_transform).
			var scale := Vector3.ONE
			var at: Node = body
			while at is Node3D:
				scale *= (at as Node3D).transform.basis.get_scale()
				at = at.get_parent()
			var height := body.get_aabb().size.y * scale.y
			if height < HEIGHT.x or height > HEIGHT.y:
				why = "%.2f m tall: apply the scale (1 unit = 1 m)" % height
	elif why == "":
		var players := scene.find_children("*", "AnimationPlayer", true, false)
		var tracked := false
		for player: AnimationPlayer in players:
			for name in player.get_animation_list():
				var animation := player.get_animation(name)
				for t in animation.get_track_count():
					tracked = tracked or str(animation.track_get_path(t)).contains("Skeleton")
		if not tracked:
			why = "no animation on the skeleton in it (Animation mode: Actions)"
	scene.free()
	return why


## The lab's library so far (or the game's, the first time) with [param scene]'s
## animations laid over it, each kept by its name.
func _add_clips(library: AnimationLibrary, scene: PackedScene) -> AnimationLibrary:
	if library == null:
		var base := ResourceLoader.load(clips_path(), "", ResourceLoader.CACHE_MODE_IGNORE) as AnimationLibrary if ResourceLoader.exists(clips_path()) else null
		library = (base if base != null else load(Client3D.HUMAN["clips"]) as AnimationLibrary).duplicate()
	var node := scene.instantiate()
	for player: AnimationPlayer in node.find_children("*", "AnimationPlayer", true, false):
		for name in player.get_animation_list():
			if name == "RESET":
				continue
			var clip := String(name).get_file()
			if library.has_animation(clip):
				library.remove_animation(clip)
			library.add_animation(clip, player.get_animation(name).duplicate())
			if not clip in clip_names:
				clip_names.append(clip)
	node.free()
	return library


static func _tail(log: String) -> String:
	var lines := log.strip_edges().split("\n")
	return lines[lines.size() - 1] if lines.size() > 0 else "no output"


func _say(words: String, wrong: bool) -> void:
	status = words
	bad = wrong
