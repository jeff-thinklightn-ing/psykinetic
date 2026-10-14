extends Node
## Checks how the levels connect (WorldMap.problems(): links with no way
## back, missing spawn points, unreachable areas, cells off the map) and
## prints each problem; exit code 1 if there are any, 0 otherwise.
##   godot --headless --path . --scene res://tools/check_world.tscn


func _ready() -> void:
	World.set_process(false)
	var world_map := WorldMap.build()
	print("[world] %d areas, %d ways: %s" % [world_map.areas.size(), world_map.ways.size(), ", ".join(world_map.areas.keys())])
	var problems := world_map.problems()
	for problem in problems:
		print("  " + problem)
	print("[world] %s" % ("no problems" if problems.is_empty() else "%d problems" % problems.size()))
	get_tree().quit(1 if not problems.is_empty() else 0)
