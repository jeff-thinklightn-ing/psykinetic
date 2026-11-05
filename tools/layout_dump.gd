extends Node
## Dumps generations of regenerating levels for tools/layout_audit.py
## (decision 806): each as <out>/<level>_g<n>_layout.png, _height.png and
## _config.json, laid as Regen lays them. Headless:
##   godot --headless --path <repo> --scene res://tools/layout_dump.tscn -- --out=<dir> [--levels=barrow,castle_halls] [--generations=1,2,3]
## Without --levels, every level marked "regenerate". Writes nothing but --out.


func _ready() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			args[arg.substr(2, arg.find("=") - 2)] = arg.substr(arg.find("=") + 1)
	var out := str(args.get("out", ""))
	if out.is_empty():
		push_error("layout_dump: --out=<dir> is needed")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var levels: Array = Regen.marked_levels() if not args.has("levels") else str(args["levels"]).split(",")
	var generations: Array = [1, 2, 3]
	if args.has("generations"):
		generations = Array(str(args["generations"]).split(",")).map(func(g: String) -> int: return int(g))
	for level_name: String in levels:
		for generation: int in generations:
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
			print("layout_dump: ", stem)
	get_tree().quit(0)
