extends SceneTree
## Writes the hand-made prefabs in levels/prefabs/ from the drawings below:
##   Godot --headless --path . --script tools/seed_prefabs.gd
## (A script run has no autoloads, so Godot prints that World is not
## found while compiling what Level depends on; the prefabs are written all
## the same, one "[prefabs] <name>: ..., OK" line each.)
##
## Each drawing is double resolution, as Terrain's ASCII maps: the
## character at (2x, 2y) is cell (x, y), at (2x + 1, 2y) the edge east of
## it, at (2x, 2y + 1) the edge south of it. Cells: CELLS below, space for
## void. Edges: "#" wall, "+" door, anything else open.

const CELLS := {
	".": "grass", ",": "dirt", "_": "stone", "~": "water", "f": "fire",
	"h": "chest", "k": "crate", "o": "boulder", "a": "cart", "t": "torch", "l": "lantern",
	"i": "monster_imp", "b": "monster_brute", "s": "monster_sneak",
}

const PREFABS := {
	# A one-room house: stone floor, walls, a door on the south side, a
	# chest and a lantern; a ring of dirt round it so its walls are its own.
	"small_house": {
		"rows": [
			", , , , , ,",
			"  # # # #  ",
			",#_ _ _ h#,",
			"           ",
			",#_ l _ _#,",
			"           ",
			",#_ _ _ _#,",
			"           ",
			",#_ _ _ _#,",
			"  # + # #  ",
			", , , , , ,",
		],
		"config": {"entities": [{"at": [4, 1], "props": {"slots": ["bandaging_kit", "", "", ""]}}]},
	},
	# A camp round a fire: a clearing of dirt, three imps sitting round the
	# fire (their gather point is the camp's anchor: a slow world tick can
	# move the group by it), a chest and crates of their stores.
	"campfire_camp": {
		"rows": [
			"    , , ,    ",
			"             ",
			"  , , i , ,  ",
			"             ",
			", , , , , , ,",
			"             ",
			", i , f , i ,",
			"             ",
			", , , , , , ,",
			"             ",
			"  k , , , h  ",
			"             ",
			"    , k ,    ",
		],
		"config": {"entities": [
			{"at": [3, 1], "idle": {"mode": "gather", "point": [3, 3]}},
			{"at": [1, 3], "idle": {"mode": "gather", "point": [3, 3]}},
			{"at": [5, 3], "idle": {"mode": "gather", "point": [3, 3]}},
			{"at": [5, 5], "props": {"slots": ["bandaging_kit", "", "", ""]}},
		]},
	},
	# A field of dirt behind a fence, a gate in its south side, a ring of
	# grass round it.
	"fenced_field": {
		"rows": [
			". . . . . . . . . .",
			"  # # # # # # # #  ",
			".#, , , , , , , ,#.",
			"                   ",
			".#, , , , , , , ,#.",
			"                   ",
			".#, , , , , , , ,#.",
			"                   ",
			".#, , , , , , , ,#.",
			"  # # # + # # # #  ",
			". . . . . . . . . .",
		],
		"config": {},
	},
	# A well: water ringed with stone; art-kit's building.well stands on the
	# water (decision 265), which is what stops walkers.
	"well": {
		"rows": [
			"  _ _ _  ",
			"         ",
			"_ _ _ _ _",
			"         ",
			"_ _ ~ _ _",
			"         ",
			"_ _ _ _ _",
			"         ",
			"  _ _ _  ",
		],
		"config": {"buildings": [{"slot": "building.well", "at": [2, 2]}]},
	},
	# The town's store (decision 301): an open yard of dirt, its depot
	# (what is put in is banked) and its shop counter (players buy and sell)
	# on its back row, facing the yard, no wall near them; the store itself
	# a stockpile place the town holds, covering the yard.
	"town_store": {
		"rows": [
			", , , , , , ,",
			"             ",
			", , h , h , ,",
			"             ",
			", , , , , , ,",
			"             ",
			", , , , , , ,",
			"             ",
			", , , , , , ,",
		],
		"config": {
			"entities": [
				{"at": [2, 1], "facing": [0, 1], "props": {"depot": true}},
				{"at": [4, 1], "facing": [0, 1], "props": {"shop": true}},
			],
			"places": {"store": {"at": [3, 2], "kind": "stockpile", "radius": 4, "holder": "town", "name": "the town's store"}},
		},
	},
	# The buildings (Level.BUILDINGS, decision 265): the footprint in stone,
	# its walls on the outline, a door in its front (south), a ring of dirt
	# round it so the walls are its own; the record says where it stands.
	# Art-kit's building.<kind> draws its roof, floor and trim over it.
	"building_hut": {
		"rows": [
			", , , , ,",
			"  # # #  ",
			",#_ _ _#,",
			"         ",
			",#_ _ _#,",
			"         ",
			",#_ _ _#,",
			"  # + #  ",
			", , , , ,",
		],
		"config": {"buildings": [{"slot": "building.hut", "at": [1, 1], "facing": [0, 1]}]},
	},
	"building_house": {
		"rows": [
			", , , , , ,",
			"  # # # #  ",
			",#_ _ _ _#,",
			"           ",
			",#_ _ _ _#,",
			"           ",
			",#_ _ _ _#,",
			"           ",
			",#_ _ _ _#,",
			"           ",
			",#_ _ _ _#,",
			"           ",
			",#_ _ _ _#,",
			"  # + # #  ",
			", , , , , ,",
		],
		"config": {"buildings": [{"slot": "building.house", "at": [1, 1], "facing": [0, 1]}]},
	},
	"building_shed": {
		"rows": [
			", , , ,",
			"  # #  ",
			",#_ _#,",
			"       ",
			",#_ _#,",
			"       ",
			",#_ _#,",
			"  + #  ",
			", , , ,",
		],
		"config": {"buildings": [{"slot": "building.shed", "at": [1, 1], "facing": [0, 1]}]},
	},
}


func _initialize() -> void:
	for prefab_name: String in PREFABS:
		var spec: Dictionary = PREFABS[prefab_name]
		var map := from_rows(spec["rows"])
		var error := Prefab.save(prefab_name, {"map": map, "config": spec["config"]})
		print("[prefabs] %s: %d x %d cells, %s" % [prefab_name, map.size.x, map.size.y, error_string(error)])
	quit()


## A map from a double-resolution drawing (see the top).
static func from_rows(rows: Array) -> LevelMap:
	var width := 0
	for row: String in rows:
		width = maxi(width, row.length())
	var map := LevelMap.new(Vector2i((width + 1) / 2, (rows.size() + 1) / 2))
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var c := row[x]
			if x % 2 == 0 and y % 2 == 0:
				if CELLS.has(c):
					map.set_cell(Vector2i(x / 2, y / 2), CELLS[c])
			elif x % 2 != y % 2 and c in ["#", "+"]:
				var key := Vector3i(x / 2, y / 2, Terrain.EAST if x % 2 == 1 else Terrain.SOUTH)
				map.set_edge(key, "wall" if c == "#" else "door")
	return map
