extends RefCounted
## The test room as it was before levels/ (main.gd's constants, unchanged),
## for level_test.gd to check levels/test_room against: nothing changed.

const MONSTER := "res://sim/monster.gd"
const PUSHABLE := "res://sim/pushable.gd"
const CHAMBER_CENTRE := Vector2i(6, 6)
## Double resolution (see Terrain): '#' wall, '+' door, '.' floor, '~' fire.
## The west corridor is rows 8-9, x 3..5, two wide, narrowing to the one
## cell (1..2, 8) at its dead end: the one chokepoint. Rows 11-12 are a
## two-wide passage; the corridors south and east of it are two wide too,
## and the door above (4, 13) is the only way into the south one.
const LEVEL: Array[String] = [
	"",
	" #########################",
	" #. . . . .#. . . . . . .#",
	" #                       #",
	" #. . . . . . . . . . . .#",
	" #                       #",
	" #. . . . . . . . . . . .#",
	" #                       #",
	" #. . . . . . . . . . . .#",
	" #                       #",
	" #. . . . . . ~ ~ ~ . . .#",
	" #                       #",
	" #. . . . . . . . . . . .#",
	" ###########             #",
	"           #. . . . . . .#",
	" ###########             #",
	" #. . . . . . . . . . . .#",
	" ##### # # #             #",
	"      . . . . . . . . . .#",
	" ########### # ####### # #",
	" #          . .       . .#",
	" #           # ####### # ###################",
	" #. . . . . . . . . . . . . . . . . . . . .#",
	" #                                         #",
	" #. . . . . . . . . . . . . . . . . . . . .#",
	" #######+###############################   #",
	"      . .#                             #. .#",
	"     # # #                             #   #",
	"     #. .#                             #. .#",
	"     #   #                             #   #",
	"     #. .#                             #. .#",
	"     #   #                             #   #",
	"     #. .#                             #. .#",
	"     #   #                             #   #",
	"     #. .#                             #. .#",
	"     #   ###############################   ###################",
	"     #. . . . . . . . . . . . . . . . . . . . . . . . . . . .#",
	"     #                                                       #",
	"     #. . . . . . . . . . . . . . . . . . . . . . . . . . . .#",
	"     ###################################   ###############   #",
	"                                       #. .#             #. .#",
	"                                       #   #             #   #",
	"                                       #. .#             #. .#",
	"                                       #   #             #   #",
	"                                       #. .#             #. .#",
	"                                       #   #             #   #",
	"                                       #. .#             #. .#",
	"                                       #   #             #   #",
	"                                       #. .#             #. .#",
	"                                       #   #             #   #",
	"                                       #. .#             #. .#",
	"                                       #   #             #   #",
	"                                       #. .#             #. .#",
	"                                       #   #             #   #",
	"                                       #. .#             #. .#",
	"                                       #   #             #   #",
	"                                       #. .#             #. .#",
	"                                       #   #             #   #",
	"                                       #. .#             #. .#",
	"                                       #   #             #   #",
	"                                       #. .#             #. .#",
	"                                       #####             #   #",
	"                                                         #. .#",
	"                                                         #   #",
	"                                                         #. .#",
	"                                                         #   #",
	"                                                         #. .#",
	"                                                         #   #",
	"                                                         #. .#",
	"                                                         #####",
]
## Spawned by the server in this order, which is also entity id order. Each
## spec is built by EntityFactory on every peer: script, shape, tint, scale,
## label, and "props" set on the instance before it enters the tree.
const LEVEL_ENTITIES: Array[Dictionary] = [
	# Imps come in different masses; Monster shades them darker as they get heavier.
	{"script": MONSTER, "shape": "capsule", "name": "CorridorImp1", "tile": Vector2i(1, 8), "props": {"mass": 25.0}},
	{"script": MONSTER, "shape": "capsule", "name": "CorridorImp2", "tile": Vector2i(2, 8), "props": {"mass": 40.0}},
	{"script": MONSTER, "shape": "capsule", "name": "CorridorImp3", "tile": Vector2i(3, 8), "props": {"mass": 60.0}},
	# These two doze in the open: they only notice what comes within 3 tiles.
	{"script": MONSTER, "shape": "capsule", "name": "Imp1", "tile": Vector2i(1, 6), "props": {"mass": 30.0, "sight_range": 3}},
	{"script": MONSTER, "shape": "capsule", "name": "Imp2", "tile": Vector2i(2, 6), "props": {"mass": 70.0, "sight_range": 3}},
	{"script": PUSHABLE, "shape": "cube", "name": "Crate1", "tile": Vector2i(8, 2), "tint": Color(0.8, 0.6, 0.35)},
	{"script": PUSHABLE, "shape": "cube", "name": "Crate2", "tile": Vector2i(8, 3), "tint": Color(0.8, 0.6, 0.35)},
	{"script": PUSHABLE, "shape": "cube", "name": "Crate3", "tile": Vector2i(4, 2), "tint": Color(0.8, 0.6, 0.35)},
	{"script": PUSHABLE, "shape": "sphere", "name": "Boulder", "tile": Vector2i(6, 3), "tint": Color(0.55, 0.55, 0.6),
		"props": {"mass": 200.0, "body_material": GridEntity.BodyMaterial.STONE}},
]
## A joining peer's player takes the first of these that is free.
const PLAYER_STARTS: Array[Vector2i] = [
	Vector2i(11, 2), Vector2i(12, 1), Vector2i(11, 1), Vector2i(12, 2),
	Vector2i(10, 1), Vector2i(10, 2), Vector2i(12, 3), Vector2i(11, 3),
]
