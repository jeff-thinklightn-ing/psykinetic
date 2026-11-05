extends Node
## Dumps generations of regenerating levels for tools/layout_audit.py
## (decision 806): each as <out>/<level>_g<n>_layout.png, _height.png,
## _config.json and _faults.json (layout_sense's check, for the plan sheet),
## laid as Regen lays them. Headless:
##   godot --headless --path <repo> --scene res://tools/layout_dump.tscn -- --out=<dir> [--levels=barrow,castle_halls] [--generations=1,2,3]
##   godot ... --scene res://tools/layout_dump.tscn -- --out=<an earlier dump> --check   (its faults checked again)
## Without --levels, every level marked "regenerate". Writes nothing but --out.


func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			args[arg.substr(2, arg.find("=") - 2)] = arg.substr(arg.find("=") + 1)
		elif arg.begins_with("--"):
			args[arg.substr(2)] = true
	var out := str(args.get("out", ""))
	if out.is_empty():
		push_error("layout_dump: --out=<dir> is needed")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	if args.has("check"):
		# --check: an earlier dump in --out checked again (its _faults.json
		# written anew), as a "before" sheet beside a new generator's "after".
		for name: String in DirAccess.get_files_at(out):
			if not name.ends_with("_layout.png"):
				continue
			var stem := out + "/" + name.trim_suffix("_layout.png")
			var level_name := name.trim_suffix("_layout.png").left(name.rfind("_g"))
			var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(stem + "_config.json"))
			var height: Image = Image.load_from_file(stem + "_height.png") if FileAccess.file_exists(stem + "_height.png") else null
			var made := {"layout": Image.load_from_file(stem + "_layout.png"), "height": height, "config": config}
			_write_faults(stem, Regen.layout_faults(made, Regen.config_of(level_name)))
			print("layout_dump: checked ", stem)
		get_tree().quit(0)
		return
	var levels: Array = Regen.marked_levels() if not args.has("levels") else str(args["levels"]).split(",")
	var generations: Array = [1, 2, 3]
	if args.has("generations"):
		generations = Array(str(args["generations"]).split(",")).map(func(g: String) -> int: return int(g))
	for level_name: String in levels:
		for generation: int in generations:
			var began := Time.get_ticks_msec()
			var made := Regen.generate(level_name, generation)
			if made.is_empty():
				print("layout_dump: %s generation %d not made" % [level_name, generation])
				continue
			var stem := "%s/%s_g%d" % [out, level_name, generation]
			(made["layout"] as Image).save_png(stem + "_layout.png")
			if made.get("height") is Image:
				(made["height"] as Image).save_png(stem + "_height.png")
			var file := FileAccess.open(stem + "_config.json", FileAccess.WRITE)
			file.store_string(JSON.stringify(made["config"], "\t"))
			file.close()
			# The game's own check of it (806), for the plan sheet to draw.
			_write_faults(stem, Regen.layout_faults(made, Regen.config_of(level_name)))
			print("layout_dump: %s (%d tries, %d ms)" % [stem, made["tries"], Time.get_ticks_msec() - began])
	get_tree().quit(0)


func _write_faults(stem: String, found: Array) -> void:
	var faults := []
	for fault: Dictionary in found:
		faults.append({"rule": fault["rule"], "cell": [fault["cell"].x, fault["cell"].y], "what": fault["what"]})
	var file := FileAccess.open(stem + "_faults.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(faults, "\t"))
	file.close()
