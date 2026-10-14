extends SceneTree
## Checks the art slots' own art (ArtCheck) and prints what is wrong, slot
## by slot, or "ok" and what it is drawn from now. Exit code 1 if anything
## is an error.
##   godot --headless --path . --script tools/art_check.gd                  every slot with art of its own, and the folders
##   godot --headless --path . --script tools/art_check.gd -- door.single   those slots, whether they have art or not
## Run --import first after dropping a file in, so Godot has read it
## (tools/art_drop.ps1 does both).


func _initialize() -> void:
	var asked := Array(OS.get_cmdline_user_args()).filter(func(arg: String) -> bool: return not arg.begins_with("--"))
	var errors := 0
	var lines: Array[String] = []
	if asked.is_empty():
		lines.append_array(ArtCheck.check_folders())
	var slots: Array = asked if not asked.is_empty() else ArtKit.slots().keys()
	for slot: String in slots:
		if asked.is_empty() and ArtKit.variant_count(slot) == 0:
			continue
		var problems := ArtCheck.check(slot)
		if problems.is_empty():
			print("ok     %s: %s" % [slot, _drawn_from(slot)])
			continue
		for problem in problems:
			lines.append("%s: %s" % [slot, problem] if not problem.begins_with("error: res://") else problem)
	for line in lines:
		print(line)
		if line.contains("error:"):
			errors += 1
	print("%d error%s" % [errors, "" if errors == 1 else "s"])
	quit(1 if errors > 0 else 0)


func _drawn_from(slot: String) -> String:
	match ArtKit.filled_by(slot):
		"own":
			var count := ArtKit.variant_count(slot)
			return "its own art" + ("" if count == 1 else " (%d variants)" % count)
		"fill":
			return "its fill (%s)" % ArtKit.spec(slot)["fill"].get("from", "?")
	return "a grey box"
