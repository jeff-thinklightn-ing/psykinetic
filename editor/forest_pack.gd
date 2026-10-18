class_name ForestPack
extends RefCounted
## A forest's trunks in a level's layout (decision 466): each a void cell,
## which stops walkers and sight as any void does, and which Level reads as
## a trunk under a canopy (Level.canopy_from). The trunks are the trees
## tools/forest_grow.py grew (decision 467), written to the level's
## trees.json; a level tool (maps' make_forest) lays its ground first and
## calls from_trees last.

## A tree this tall or taller, live or a snag, stands on its cell as a
## trunk; a smaller one is undergrowth, walked through (forest_grow.py's
## TRUNK_HEIGHT).
const TRUNK_HEIGHT := 3.0
## The ground a trunk may take: never the path's dirt, a marker or water.
const TAKES: Array[String] = ["grass"]


## Makes a void cell of [param map] under every tree of TRUNK_HEIGHT or
## more in the trees.json at [param trees_path], where the cell is TAKES
## ground. Returns how many it made; 0 if the file is missing or unread.
static func from_trees(map: LevelMap, trees_path: String) -> int:
	if not FileAccess.file_exists(trees_path):
		return 0
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(trees_path))
	if not data is Dictionary:
		push_warning("ForestPack: %s is not a trees file" % trees_path)
		return 0
	var made := 0
	for tree: Dictionary in data.get("trees", []):
		if float(tree.get("height", 0.0)) < TRUNK_HEIGHT:
			continue
		var at := Vector2i(int(tree["at"][0]), int(tree["at"][1]))
		if map.cell(at) in TAKES:
			map.set_cell(at, "void")
			made += 1
	return made
