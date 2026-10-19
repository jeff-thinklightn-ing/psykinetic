extends Node
## Tall grass (decision 508) on a little level with a patch of it in a
## grass meadow: the "tall_grass" kind read as grass ground, floor, listed
## in the terrain; one under a building left out, said; World.cover_at
## TALL_GRASS_COVER on it and 0 elsewhere and off the map; a step into it
## takes TALL_GRASS_TICK_SCALE; a body of TRAMPLE_MASS or more stepping in
## flattens it (no cover, no slowing, grass_changed), a lighter one not; it
## stands again on the world tick after TRAMPLE_DAYS; the trampled set
## round-trips through the snapshot's form and a client's "grass" messages;
## TallGrass.lay grows meadow patches and a wood's edge on grass only, clear
## of markers, the same for the same seed; the sample level's patch. Run it
## with tests/run.ps1 or tests/run.sh.

const WIDTH := 12
const HEIGHT := 8
const PATCH := Rect2i(4, 2, 4, 4)

var _failures := 0
var _main: Node


func _ready() -> void:
	World.set_process(false)
	Net.port = preload("res://tests/test_ports.gd").of(17863)
	Monster.idling = false
	_main = preload("res://main.tscn").instantiate()
	_main.returns = false
	add_child(_main)
	Level.register("tg_meadow", _layout(), null, {"name": "The Meadow", "outdoor": true})
	_test_parse()
	_test_world()
	_test_trample()
	_test_saved_and_told()
	_test_lay()
	_test_sample()
	_main.load_map(Level.DEFAULT_MAP)
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## Grass from x 2 to 9, y 1 to 6, the tall grass in PATCH, the start at
## (1, 4) on stone.
static func _layout() -> Image:
	var rows: Array[String] = []
	for y in 2 * HEIGHT - 1:
		rows.append(".".repeat(2 * WIDTH - 1))
	var markers := {Vector2i(1, 4): "start"}
	for y in range(1, 7):
		for x in range(2, 10):
			markers[Vector2i(x, y)] = "tall_grass" if PATCH.has_point(Vector2i(x, y)) else "grass"
	return Level.image_from_rows(rows, markers)


func _test_parse() -> void:
	print("== the level ==")
	var level := Level.load_level("tg_meadow")
	var terrain: Dictionary = level["terrain"]
	var grass: Array = terrain["tall_grass"]
	_check(grass.size() == 16 and grass.all(func(cell: Vector2i) -> bool: return PATCH.has_point(cell)), "the patch is tall grass, 16 cells (%d)" % grass.size())
	_check(Vector2i(5, 3) in terrain["floor"] and terrain["kinds"][Vector2i(5, 3)] == "grass", "floor, on grass ground")
	_check(level["warnings"].is_empty(), "no warnings (%s)" % [level["warnings"]])
	var built := Level.parse(_layout(), null, {"name": "Built", "outdoor": true, "buildings": [{"slot": "building.hut", "at": [5, 3]}]})
	_check(not Vector2i(5, 3) in built["terrain"]["tall_grass"]
		and built["warnings"].any(func(w: String) -> bool: return "tall grass at (5, 3) is under a building" in w),
		"under a building it is left out, said (%s)" % [built["warnings"]])


func _test_world() -> void:
	print("== in the world ==")
	_check(_main.load_map("tg_meadow"), "the level loads")
	_check(is_equal_approx(World.cover_at(Vector2i(5, 3)), World.TALL_GRASS_COVER) and World.cover_at(Vector2i(3, 3)) == 0.0
		and World.cover_at(Vector2i(1, 4)) == 0.0 and World.cover_at(Vector2i(-5, 40)) == 0.0,
		"cover %.1f in the grass, none beside it, on stone or off the map" % World.TALL_GRASS_COVER)
	_check(World.is_tall_grass(Vector2i(4, 2)) and not World.is_tall_grass(Vector2i(3, 2)), "is_tall_grass")
	var player := _player()
	World._relocate(player, Vector2i(3, 3))
	_check(is_equal_approx(World.step_ticks(player, Vector2i(1, 0)), player.move_ticks * World.TALL_GRASS_TICK_SCALE)
		and is_equal_approx(World.step_ticks(player, Vector2i(0, 1)), player.move_ticks), "a step into it takes %.2f times as long, beside it as ever" % World.TALL_GRASS_TICK_SCALE)
	_check(World.has_line_of_sight(Vector2i(3, 3), Vector2i(8, 3)), "it does not stop a line of sight through it")


func _test_trample() -> void:
	print("== trampled, standing again ==")
	_main.load_map("tg_meadow")
	var player := _player()
	var told: Array = []
	var listen := func(level: String, flat: PackedInt32Array, stood: PackedInt32Array) -> void: told.append([level, flat, stood])
	World.grass_changed.connect(listen)
	World._relocate(player, Vector2i(3, 3))
	player.next_move_tick = 0
	_check(player.mass >= World.TRAMPLE_MASS and World.try_move(player, Vector2i(1, 0)) and player.tile == Vector2i(4, 3), "the player (%.0f) steps in" % player.mass)
	_check(World.is_trampled(Vector2i(4, 3)) and World.cover_at(Vector2i(4, 3)) == 0.0 and World.is_tall_grass(Vector2i(4, 3)),
		"it is trampled flat: no cover, still tall grass")
	_check(told.size() == 1 and told[0][0] == "tg_meadow" and Array(told[0][1]) == [4, 3], "and grass_changed said so (%s)" % [told])
	World._relocate(player, Vector2i(3, 3))
	_check(is_equal_approx(World.step_ticks(player, Vector2i(1, 0)), player.move_ticks), "a step onto the flattened cell is not slowed")
	var mass := player.mass
	player.mass = World.TRAMPLE_MASS - 1.0
	World._relocate(player, Vector2i(3, 4))
	player.next_move_tick = 0
	World.try_move(player, Vector2i(1, 0))
	_check(player.tile == Vector2i(4, 4) and not World.is_trampled(Vector2i(4, 4)) and World.cover_at(Vector2i(4, 4)) > 0.0, "a lighter body goes through, the grass standing")
	player.mass = mass
	World.steps += int(World.TRAMPLE_DAYS * DayNight.day_steps) - 10
	World.world_tick()
	_check(World.is_trampled(Vector2i(4, 3)), "short of %d days it is still flat" % World.TRAMPLE_DAYS)
	World.steps += 11
	World.world_tick()
	_check(not World.is_trampled(Vector2i(4, 3)) and is_equal_approx(World.cover_at(Vector2i(4, 3)), World.TALL_GRASS_COVER),
		"then it stands again on the world tick")
	_check(told.size() == 2 and Array(told[1][2]) == [4, 3], "said (%s)" % [told])
	World.grass_changed.disconnect(listen)


func _test_saved_and_told() -> void:
	print("== saved, and told to a client ==")
	_main.load_map("tg_meadow")
	World.trampled_from_dict({})
	World._trampled_here[Vector2i(5, 5)] = World.steps + 100
	var saved := World.trampled_to_dict()
	_check(saved.get("tg_meadow") == [5, 5, World.steps + 100], "the snapshot's form: [x, y, when it stands] (%s)" % [saved])
	World.trampled_from_dict({})
	_check(not World.is_trampled(Vector2i(5, 5)), "cleared")
	World.trampled_from_dict(JSON.parse_string(JSON.stringify(saved)))
	_check(World.is_trampled(Vector2i(5, 5)) and World.cover_at(Vector2i(5, 5)) == 0.0, "read back through JSON, trampled again")
	World.grass_told("tg_other", {"full": true, "flat": PackedInt32Array([1, 2, 3, 4])})
	World.grass_told("tg_other", {"flat": PackedInt32Array([5, 6]), "stood": PackedInt32Array([1, 2])})
	_check(Array(World.trampled_cells("tg_other")) == [3, 4, 5, 6], "a client's: the full set, then a cell flattened and one standing again (%s)" % [World.trampled_cells("tg_other")])
	World.grass_told("tg_other", {"full": true, "flat": PackedInt32Array()})
	_check(World.trampled_cells("tg_other").is_empty(), "a full message with none clears it")
	World.trampled_from_dict({})


func _test_lay() -> void:
	print("== TallGrass.lay ==")
	var map := LevelMap.new(Vector2i(20, 12))
	for y in 12:
		for x in 20:
			map.set_cell(Vector2i(x, y), "grass")
	for y in range(0, 12):
		map.set_cell(Vector2i(0, y), "void")  # A wood along the west.
	map.set_cell(Vector2i(10, 6), "link")
	for x in range(12, 20):
		map.set_cell(Vector2i(x, 2), "dirt")  # A path.
	var rect := Rect2i(Vector2i.ZERO, map.size)
	var laid: Dictionary = TallGrass.lay(map, rect, 7)["cells"]
	_check(not laid.is_empty() and laid.keys().all(func(cell: Vector2i) -> bool: return map.cell(cell) == "grass"), "grows on grass only (%d cells)" % laid.size())
	_check(not laid.keys().any(func(cell: Vector2i) -> bool: return maxi(absi(cell.x - 10), absi(cell.y - 6)) <= 1), "and clear of the link")
	var edge := 0
	for y in 12:
		for x in range(1, 3):
			edge += 1 if laid.has(Vector2i(x, y)) else 0
	_check(edge >= 12, "a band along the trees (%d of 24 cells)" % edge)
	_check(TallGrass.lay(map, rect, 7)["cells"] == laid, "the same seed, the same grass")
	_check(TallGrass.lay(map, rect, 7, {"meadow": 0.0, "edge": 0})["cells"].is_empty(), "no meadow and no edge: none")
	_check(TallGrass.lay(map, rect, 7, {"keep_clear": {Vector2i(1, 5): true}})["cells"].keys().all(func(cell: Vector2i) -> bool:
		return maxi(absi(cell.x - 1), absi(cell.y - 5)) > 1), "clear of a kept cell")


func _test_sample() -> void:
	print("== the sample level ==")
	var level := Level.load_level("sample")
	var grass: Array = level["terrain"]["tall_grass"]
	_check(grass.size() == 12 and not Vector2i(6, 2) in grass and not Vector2i(6, 3) in grass, "a patch of 12, a trodden line down x 6 (%s)" % [grass])
	_check(not level["warnings"].any(func(w: String) -> bool: return "tall grass" in w), "nothing said of it")


func _player() -> Player:
	for entity in World.get_entities():
		if entity is Player and entity.spawned:
			return entity
	return null


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
