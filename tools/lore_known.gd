extends SceneTree
## Prints what a knower knows (Lore.known_by), to check the lore reads as
## that character would know it: rumours marked as hearsay, lived facts as
## memory. With --draft, drafts count as well as agreed facts. With no
## knower, lists the knowers.
##   godot --headless --path . --script tools/lore_known.gd -- townsfolk --draft


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var least := "draft" if "--draft" in args else "agreed"
	var names := Array(args).filter(func(arg: String) -> bool: return not arg.begins_with("--"))
	if names.is_empty():
		for id: String in Lore.knowers():
			print("%s (%s)" % [id, Lore.knowers()[id].get("status", "")])
		quit(0)
		return
	for knower: String in names:
		if not Lore.knowers().has(knower):
			push_error("lore_known: no knower %s" % knower)
			quit(1)
			return
		var facts := Lore.known_by(knower, least)
		print("== %s knows %d (%s) ==" % [knower, facts.size(), "agreed and draft" if least == "draft" else "agreed"])
		for fact: Dictionary in facts:
			var how := " (hearsay)" if fact["hearsay"] else (" (memory)" if fact["memory"] else "")
			print("- %s%s" % [fact["text"], how])
	quit(0)
