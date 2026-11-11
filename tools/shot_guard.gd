extends RefCounted
## A shot scene's check that it draws one game view (the coordinator, 2026-11-11): a still that
## hosts main.tscn uses main's own Client3D (windowed, main builds it in _ready, _show_3d) and never
## adds a second, which doubled the sun, the lamps and the environment in trees' scratch stills.
## No class_name: preload("res://tools/shot_guard.gd").count(rig), then .ok(counts) before any still.
##
## A rig is a Client3D that runs: the neighbour zone's view and the zone glimpses are Client3Ds with
## processing off and no light of their own. A sun or an environment counts when it draws in the
## town's world (the root's): the item icons' and the character preview's sit in worlds of their own.
## The rig's body fill (858), a second DirectionalLight3D culled to bodies, is not a sun.


## {"rigs", "suns", "environments", "apart", "lines"}: the counts in the town's world, how many
## lights and environments sit apart, and one line per node counted or set aside, with its path.
## [param rig] is the scene's view (main's _client3d); its body fill is left out.
static func count(rig: Node) -> Dictionary:
	var tree := rig.get_tree()
	var town := tree.root.world_3d
	var fill: Variant = rig.get("_body_fill") if "_body_fill" in rig else null
	var rigs := 0
	var suns := 0
	var environments := 0
	var apart := 0
	var lines := PackedStringArray()
	for node in tree.root.find_children("*", "", true, false):
		var line := ""
		if node is Client3D:
			var view := node as Client3D
			var runs := view.is_processing() and not view._glimpse
			rigs += int(runs)
			line = "rig" if runs else "still view (processing off, glimpse %s)" % view._glimpse
		elif node is DirectionalLight3D and fill != null and node == fill:
			line = "the rig's body fill (858), culled to bodies: not a sun"
		elif node is DirectionalLight3D or node is WorldEnvironment:
			var lit := node.get_viewport().world_3d == town and (node is WorldEnvironment or (node as Node3D).is_visible_in_tree())
			if node is DirectionalLight3D:
				suns += int(lit)
			else:
				environments += int(lit)
			apart += int(not lit)
			line = "in the town's world" if lit else "apart (own world or hidden)"
		if line != "":
			lines.append("%s %s: %s" % [node.get_class(), node.get_path(), line])
	return {"rigs": rigs, "suns": suns, "environments": environments, "apart": apart, "lines": lines}


## Whether [param counts] (from count) is one rig, one sun and one environment.
static func ok(counts: Dictionary) -> bool:
	return int(counts["rigs"]) == 1 and int(counts["suns"]) == 1 and int(counts["environments"]) == 1


## The counts as one line, for a scene's log.
static func summary(counts: Dictionary) -> String:
	return "rigs %d, suns %d, environments %d in the town's world (%d apart), display %s" % [counts["rigs"],
		counts["suns"], counts["environments"], counts["apart"], DisplayServer.get_name()]
