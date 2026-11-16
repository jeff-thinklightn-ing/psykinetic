extends Node
## level_test and level_dungeons_test's shared part (the coordinator, 11-16: level_test
## ran 219-269 s on saturn, over land.sh's 220 s slow-scene line, so it is two scenes).
## The checks, the maps made in code, and every helper and test both halves reach; each
## half sets its own port, then calls _setup(), its tests, and _finish(). Not a scene.

const LEGACY := preload("res://tests/legacy_test_room.gd")
const Sheet := preload("res://tools/plan_sheet.gd")
## The floor kinds a pond would lie in (Level.GROUNDS but stone, the paving).
const NATURAL_GROUND: Array[String] = ["grass", "dirt"]
## Levels whose cell water is a test's fixture: the sample's pool and stream
## are what view_test draws cell water from (terrain's side, 553/557).
const CELL_WATER_FIXTURES: Array[String] = ["sample"]
## How far a ledge's curve may lie from the cliff edges it traces (585;
## terrain's bound, as the forest edge's EDGE_BOUND).
const LEDGE_BOUND := 0.45
## The furthest any of a level's starts lies from its first (World.distance; 774 amended (4)): the other levels'
## starts lie 3 or less from their first, the wilds' 7 (its second, by the dirt square).
const START_SPREAD := 10

var _failures := 0
var _main: Node
var _pushes: Array[Dictionary] = []
## Every "party" line this peer's screen was sent (133 amended (1): a line
## said to a player must reach it, not the party log alone).
var _heard: Array[String] = []

## Filling the hills, phase 1 (777): a track from the road to each refuge
## (its place's cell on a safe path), two rest camps (649's camp kind, a
## "rest" place at Level.camp_fire), seven forage patches on grass; the do
## rhythm: every safe path cell within FILL_DO_REACH of something to do (a
## rest, a refuge, a patch), about 15 s of walking either way; a player by
## a camp's fire, unhurt a while, is warmed (physics' heal), and not once hit.
const FILL_DO_REACH := 60
## Shipped levels with a known trap, until their owner fixes it: level -> owner
## (783, physics' side (2)). Their traps print as EXPECTED FAIL, not a failure.
const PIT_TRAPS_EXPECTED := {
}
## 832 (the coordinator's ruling): the quick way down kept. The First Hall's
## sealed link at (30,8) to barrow_deep / from_temple, sealed "draugr",
## replaces the wilds temple's stair as the reward for beating him. It reads
## as a shut way (the slab cue the temple stair had, no words), and a player
## whose saved record already holds the mark finds it open from the first
## build it is in. 896 switched on (the full circle; Jeff: "drop the short
## cut in") took it out of the barrow; the sealed way stays a level.json
## link of any level, tried here on a copy of the barrow (HALL_SHORTCUT).
const HALL_SHORTCUT := {"at": [30, 8], "to_map": "barrow_deep", "to_spawn": "from_temple", "sealed": "draugr"}
## 832 (the crypt's ways in): the deep laid by the crypt generator, its
## "deep" block (the switch-on's keys, DEEP_SWITCH, until barrow_deep
## carries them): generations 1-6 each with an ossuary and tomb chambers
## only, the wing old_graves of two rooms or more (or none), the
## block's guard packs whole (one shared "pack" each, three of three), the
## draugr in the lair, both links kept, no torches out of the anchors, and
## no fault of any layout rule, where the old caverns have a dozen.
## The Charnel Vault's torches in barrow_deep's template (608 amended (4)),
## at the ends of its way out, which every generation opens at (48..52, 7)
## (47 too on most): its south row, one cell in from the corners where 608
## amended (4) had them, behind the south wall (608 amended (5)); then
## (48,6) and (52,6), the east one behind the corner of the wall east of the
## mouth; now (49,6) and (51,6), even about the mouth's middle (608 amended (6)).
const VAULT_TORCHES: Array[Vector2i] = [Vector2i(49, 6), Vector2i(51, 6)]
## (5)'s pair, left free by (6).
const VAULT_TORCHES_BEFORE: Array[Vector2i] = [Vector2i(48, 6), Vector2i(52, 6)]
## The default camera and the walls, as Client3D draws them (608 amended
## (6)'s line walk): the resting camera on the +x +z diagonal (_camera_offset,
## yaw 0) CAMERA_PITCH above the ground; a torch's flame over its cell's
## middle (prop.torch_post's flame socket, 1.45 m, and the flame); walls
## WALL_HEIGHT tall and WALL_THICKNESS thick, posts as thick at their ends;
## the post's half width across the view.
const VIEW_PITCH := 50.0
const VIEW_FLAME := 1.6
const VIEW_WALL := 3.0
const VIEW_WALL_HALF := 0.25
const VIEW_POST_HALF := 0.15
## The crypt generator, whose torch rule a row turns off to compare (608 amended (5)).
const CRYPT_GEN := preload("res://sim/level_gen/crypt.gd")
## The barrow's Offering stone, in the First Hall east of the bier since the
## Low Hall went (747 amended (13)), and the First Hall's rect (its anchor).
const OFFERING_AT := Vector2i(44, 8)
const FIRST_HALL := Rect2i(27, 1, 26, 16)
## The knight's marker, beside the bier (747 amended (8)).
const KNIGHT_AT := Vector2i(39, 10)
## Where the Low Hall stood, rock every generation leaves whole (the block's "rock").
const LOW_HALL := Rect2i(30, 24, 18, 14)
const DEEP_SWITCH := {"generator": "crypt", "heart": "lair", "deep": {"wing": "old_graves"}, "chests": 3,
	"held": ["door", "purpose", "wrap", "dead_end", "spine", "loop", "chest", "coop", "arrival"]}
const LABYRINTH := preload("res://sim/level_gen/labyrinth.gd")
const LAYOUT_SENSE := preload("res://sim/layout_sense.gd")
## Layout sense in every generated map (the roadmap's step 4, dungeon
## leads): every level marked to regenerate holds all of layout_sense's
## rules (its block's "held", so Regen retries a try that faults), and
## its generations 1-4 lay with no fault of any rule. SENSE_NOT_YET names
## the ones still to come and what they wait on; a level there is checked
## all the same once its block holds every rule. SENSE_RULES_NOT_YET names
## a rule a level holds later, and on what; the level is checked on the rest.
const SENSE_NOT_YET := {"hollowfell": "the mine's spine and purpose faults, next in step 4"}
const SENSE_RULES_NOT_YET := {}
## A made-up level for the checker: [param rects] floor, [param edges]
## [[cell, way, Terrain.Edge], ...], a start at each of [param starts], a
## thing with a purpose (a bier) at each of [param things].
## 806 amended (playtest's tour: mouth to both chambers, not one fight):
## each chamber but the entrance has a monster within GUARD_STEPS walked
## steps of it, and most monsters stand within ROUTE_NEAR of the walk from
## the entrance to the chambers.
const GUARD_STEPS := 10
const ROUTE_NEAR := 5


## The setup both halves share, once Net.port is set: the game, the signals, the maps made in code.
func _setup() -> void:
	World.set_process(false)
	Net.companions = false
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	World.entity_pushed.connect(func(entity: GridEntity, _by: GridEntity, _direction: Vector2i, tiles: int, impact: int, stopped_by: String) -> void:
		_pushes.append({"entity": entity, "tiles": tiles, "impact": impact, "stopped_by": stopped_by}))
	Net.message_received.connect(func(kind: String, data: Dictionary) -> void:
		if kind == "party":
			_heard.append(str(data.get("text", ""))))
	_register_maps()
	_check(_player() == null or World.free_body(_player()), "a player is a free body: every player's walk below is one (6b, 703)")


## The end both halves share: the default map back, the result, the exit code.
func _finish() -> void:
	_main.load_map(Level.DEFAULT_MAP)
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


# --- Maps made in code -------------------------------------------------------------


## ASCII rows in Terrain's double resolution for cells x in [x0, x1], y in
## [y0, y1], all floor, with [param walls] and [param doors] (edge keys).
static func _rows(x0: int, x1: int, y0: int, y1: int, walls: Array[Vector3i] = [], doors: Array[Vector3i] = []) -> Array[String]:
	var width := 2 * x1 + 3
	var height := 2 * y1 + 3
	var grid: Array[PackedStringArray] = []
	for y in height:
		var row := PackedStringArray()
		row.resize(width)
		row.fill(" ")
		grid.append(row)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			grid[2 * y][2 * x] = "."
	for key in walls:
		var at := Vector2i(key.x, key.y) * 2 + (Vector2i(1, 0) if key.z == Terrain.EAST else Vector2i(0, 1))
		grid[at.y][at.x] = "#"
	for key in doors:
		var at := Vector2i(key.x, key.y) * 2 + (Vector2i(1, 0) if key.z == Terrain.EAST else Vector2i(0, 1))
		grid[at.y][at.x] = "+"
	var rows: Array[String] = []
	for row in grid:
		rows.append("".join(row))
	return rows


func _register_maps() -> void:
	# Edges: a wall pixel between (1,1) and (2,1), a door between (2,1) and
	# (3,1); a wall pixel on cell (4,2) is void; the wall colour overridden.
	var config := {"legend": {"wall": "#123456"}}
	var rows := _rows(1, 4, 1, 2, [Vector3i(1, 1, Terrain.EAST)], [Vector3i(2, 1, Terrain.EAST)])
	var image := Level.image_from_rows(rows, {Vector2i(1, 1): "start", Vector2i(1, 2): "crate", Vector2i(3, 2): "monster_brute"}, config)
	image.set_pixel(8, 4, Color("#123456"))
	Level.register("test_edges", image, null, config)
	# Heights: x 1-2 at 0, x 3 at 1, x 4-5 at 2; row 3's x 3 at 0; a stair
	# on (2,2) climbing east; a wall between (1,3) and (2,3).
	var heights := {}
	var levels := [[0, 0, 1, 2, 2], [0, 0, 1, 2, 2], [0, 0, 0, 2, 2]]
	for y in 3:
		for x in 5:
			heights[Vector2i(x + 1, y + 1)] = levels[y][x]
	var height_rows := _rows(1, 5, 1, 3, [Vector3i(1, 3, Terrain.EAST)])
	var layout := Level.image_from_rows(height_rows, {Vector2i(1, 1): "start", Vector2i(2, 2): "stair"})
	Level.register("test_heights", layout, Level.height_image(layout, heights), {})
	# Links: a to b, arriving at b's spawn point "gate".
	Level.register("test_link_a", Level.image_from_rows(_rows(1, 4, 1, 1), {Vector2i(1, 1): "start", Vector2i(4, 1): "link"}), null,
		{"links": [{"at": [4, 1], "to_map": "test_link_b", "to_spawn": "gate"}]})
	Level.register("test_link_b", Level.image_from_rows(_rows(1, 3, 1, 2), {Vector2i(1, 1): "start"}), null,
		{"spawn_points": {"gate": [2, 2]}})
	# A sealed link (decision 540): the same way, open to the marked alone.
	Level.register("test_link_s", Level.image_from_rows(_rows(1, 4, 1, 1), {Vector2i(1, 1): "start", Vector2i(4, 1): "link"}), null,
		{"links": [{"at": [4, 1], "to_map": "test_link_b", "to_spawn": "gate", "sealed": "draugr"}]})
	# Edge links: test_edge_w (4 x 3 cells, all floor) has test_edge_e
	# (3 x 5) east of it, and the other way round.
	var w_rows: Array[String] = []
	for y in 5:
		w_rows.append(".".repeat(7))
	Level.register("test_edge_w", Level.image_from_rows(w_rows, {Vector2i(0, 1): "start"}), null, {"neighbours": {"east": "test_edge_e"}})
	var e_rows: Array[String] = []
	for y in 9:
		e_rows.append(".".repeat(5))
	Level.register("test_edge_e", Level.image_from_rows(e_rows, {Vector2i(2, 0): "start"}), null, {"neighbours": {"west": "test_edge_w"}})


# --- Tests ----------------------------------------------------------------------


## An 8 x 6 level [param level_name]: a room x 1..6, y 1..4 in the rock,
## three niches in its north wall at (2, 1), (4, 1) and (6, 1), the last the
## hidden one with its alcove at (6, 0) behind a door edge and the stair
## link in it.
func _register_niche(level_name: String) -> void:
	var rows: Array[String] = []
	for py in 6 * 2 - 1:
		var row := ""
		for px in 8 * 2 - 1:
			var cell := Vector2i(px / 2, py / 2)
			var floor_here := px % 2 == 0 and py % 2 == 0 and (cell.x >= 1 and cell.x <= 6 and cell.y >= 1 and cell.y <= 4 or cell == Vector2i(6, 0))
			row += "+" if px == 12 and py == 1 else ("." if floor_here else " ")
		rows.append(row)
	Level.register(level_name, Level.image_from_rows(rows, {Vector2i(3, 3): "start", Vector2i(6, 0): "link"}), null,
		{"niches": [[2, 1, 0, -1, "a", 1], [4, 1, 0, -1, "c", 2], [6, 1, 0, -1, "hidden", 1]],
			"links": [{"at": [6, 0], "to_map": "test_room", "to_spawn": "", "hidden": true}],
			"spawn_points": {"from_below": [6, 1]},
			"regenerate": {"generator": "labyrinth", "anchors": [{"name": "hall", "rect": [0, 0, 8, 6]}], "entrance": "hall"}})


## [param player]'s free body held on [param intent] for [param ticks] ticks.
func _hold_free(player: Player, intent: Vector2, ticks: int) -> void:
	for i in ticks:
		World.free_input(player, intent, World.TICK_DT)
		World.step()


func _player() -> Player:
	for entity in World.get_entities():
		if entity is Player and entity.spawned:
			return entity
	return null


func _put(entity: GridEntity, tile: Vector2i) -> void:
	if entity.tile == tile:
		return
	var occupant := World.get_entity_at(tile)
	if occupant != null:
		World.despawn(occupant)
	World._relocate(entity, tile)


static func _cells_apart(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
