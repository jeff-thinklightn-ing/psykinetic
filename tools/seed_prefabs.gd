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
	# The town's temple (its walls stone, 4.5 m, the slot's) and the
	# healer's hut out in the wilds (Jeff, 2026-10-17): the house's and
	# the hut's footprints, the temple's door in the middle of its front.
	# The temple's counter (decision 424): a chest at its back, facing the
	# door, props {"temple": true}, where a player hands the priest a thing
	# and an offering and collects what waits.
	"building_temple": {
		"rows": [
			", , , , , ,",
			"  # # # #  ",
			",#_ h _ _#,",
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
			"  # + + #  ",
			", , , , , ,",
		],
		"config": {
			"buildings": [{"slot": "building.temple", "at": [1, 1], "facing": [0, 1]}],
			"entities": [{"at": [2, 1], "facing": [0, 1], "props": {"temple": true}}],
		},
	},
	"building_healers_hut": {
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
		"config": {"buildings": [{"slot": "building.healers_hut", "at": [1, 1], "facing": [0, 1]}]},
	},
	# A town's field (decision 452, economy's farms): a 4 x 4 plot of dirt,
	# fenced on its outline (walls Level.OPEN_AIR keeps from blocking sight
	# or being drawn; the slot's mesh is the fence), its gate a gap in the
	# front just right of the middle; no inside, no roof. Its "use" and
	# "town" a level gives it.
	"building_field": {
		"rows": [
			", , , , , ,",
			"  # # # #  ",
			",#, , , ,#,",
			"           ",
			",#, , , ,#,",
			"           ",
			",#, , , ,#,",
			"           ",
			",#, , , ,#,",
			"  # #   #  ",
			", , , , , ,",
		],
		"config": {"buildings": [{"slot": "building.field", "at": [1, 1], "facing": [0, 1]}]},
	},
	# The Old Tower (decision 600; Jeff: the ancients' broken-down castle,
	# Snagfin's in Held): a yard walled round but at its east gate (the
	# bridge road, y 8) and a breach in the north-east (the ford path); the
	# broken tower solid on the north-west corner (art-kit's tower_ruin);
	# the one room still roofed, a stone kind, its door south onto a dirt
	# path to the gate, Snagfin's counter at its back facing the door;
	# fallen stone (rubble heaps, a column) solid in the yard, off the path,
	# each heap against the wall (no way one cell wide: Jeff, 2026-10-22).
	# A ring of dirt round it so its walls are its own. Its place is a
	# "fort" working for the town whose store is "store" (economy's 594: a
	# counter in it is that town's shop); Snagfin's home is behind the
	# counter, (5, 3) here.
	"old_tower": {
		"rows": [
			"_ _ _ , , , , , , , , , , , , , ,",
			"      # # # # # # # # #     # #  ",
			"_ _ _ . . . . . . . . . . . . .#,",
			"                                 ",
			"_ _ _ . . . . . . . . . . . . .#,",
			"      # # # # # #                ",
			",#. .#_ _ _ _ _ _#. . . . . . .#,",
			"                                 ",
			",#. .#_ _ h _ _ _#. . . . . . .#,",
			"                                 ",
			",#. .#_ _ _ _ _ _#. . . . . . .#,",
			"                                 ",
			",#. .#_ _ _ _ _ _#. . . . . . .#,",
			"                                 ",
			",#. .#_ _ _ _ _ _#. . . . . . . ,",
			"                                 ",
			",#. .#_ _ _ _ _ _#. , , , , , , ,",
			"      # # + # # #                ",
			",#. . . . , , , , , , . . . . . ,",
			"                                 ",
			",#. . . . . . . . . . . . . . .#,",
			"                                 ",
			",#. . . . . . . . . . . . . . .#,",
			"                                 ",
			",#. . . . . . . . . . . . . . .#,",
			"                                 ",
			",#. . . . . . . . . . . . . . .#,",
			"                                 ",
			",#. . . . . . . . . . . . . . .#,",
			"                                 ",
			",#. . . . . . . . . . . . . . .#,",
			"  # # # # # # # # # # # # # # #  ",
			", , , , , , , , , , , , , , , , ,",
		],
		"config": {
			"buildings": [
				{"slot": "building.tower_ruin", "at": [0, 0], "facing": [0, 1]},
				{"kind": "tower_room", "size": "small", "at": [3, 3], "facing": [0, 1]},
				{"slot": "building.rubble_heap", "at": [11, 1], "facing": [0, 1]},
				{"slot": "building.rubble_heap", "at": [15, 6], "facing": [0, 1], "variant": 2},
				{"slot": "building.rubble_heap", "at": [15, 10], "facing": [0, 1], "variant": 3},
				{"slot": "building.rubble_heap", "at": [1, 11], "facing": [0, 1], "variant": 2},
				{"slot": "building.rubble_heap", "at": [15, 13], "facing": [0, 1], "variant": 3},
				{"slot": "building.rubble_heap", "at": [7, 15], "facing": [0, 1]},
				{"slot": "building.fallen_column", "at": [9, 11], "facing": [0, 1]},
			],
			"entities": [{"at": [5, 4], "facing": [0, 1], "props": {"shop": true}}],
			"places": {"old_tower": {"at": [8, 8], "kind": "fort", "radius": 7, "holder": "town", "town": "store", "name": "the Old Tower"}},
		},
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
