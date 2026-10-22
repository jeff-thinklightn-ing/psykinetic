extends Node
## Rocks and cliffs (decision 513) on a little level with a plateau two
## levels up in its middle, a slope run up its west side and a rock on its
## lip: the slope a stair (terrain stairs and slopes, its footing the
## ground round it), the rock no floor, walled round (no step, no sight,
## routes round it) with its own footing; the cliff stops a step; a body
## pushed off falls (the fall's impact, as before) and walks back up by the
## slope; sight from under the cliff sees its lip and nothing behind it,
## from on top all below; light still reaches past the lip; an archer's
## shot line from the top reaches a player below; a monster below that saw
## its quarry on the lip can walk there by the slope; Outcrops.lay raises a
## blob with a slope whose sides stay at its foot, rocks on its lip, the
## same for the same seed; the sample level's outcrop. Run it with
## tests/run.ps1 or tests/run.sh.

const WIDTH := 14
const HEIGHT := 10
const PLATEAU := Rect2i(6, 2, 5, 5)
const ROCK := Vector2i(8, 2)

var _failures := 0
var _main: Node


func _ready() -> void:
	World.set_process(false)
	Net.port = preload("res://tests/test_ports.gd").of(17864)
	Monster.idling = false
	_main = preload("res://main.tscn").instantiate()
	_main.returns = false
	add_child(_main)
	Level.register("cl_cliff", _layout(), _heights(), {"name": "The Cliff", "outdoor": true})
	_test_parse()
	_test_walk_and_fall()
	_test_sight()
	_test_lay()
	_test_sample()
	_main.load_map(Level.DEFAULT_MAP)
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## Grass all over, the slope at (4, 4) and (5, 4) climbing east onto the
## plateau, the rock at ROCK, the start at (1, 4).
static func _layout() -> Image:
	var rows: Array[String] = []
	for y in 2 * HEIGHT - 1:
		rows.append(".".repeat(2 * WIDTH - 1))
	var markers := {Vector2i(1, 4): "start", Vector2i(4, 4): "slope", Vector2i(5, 4): "slope", ROCK: "rock"}
	for y in HEIGHT:
		for x in WIDTH:
			if not markers.has(Vector2i(x, y)):
				markers[Vector2i(x, y)] = "grass"
	return Level.image_from_rows(rows, markers)


static func _heights() -> Image:
	var heights := {Vector2i(5, 4): 1}
	for y in range(PLATEAU.position.y, PLATEAU.end.y):
		for x in range(PLATEAU.position.x, PLATEAU.end.x):
			heights[Vector2i(x, y)] = 2
	return Level.height_image(_layout(), heights)


func _test_parse() -> void:
	print("== the level ==")
	var level := Level.load_level("cl_cliff")
	var terrain: Dictionary = level["terrain"]
	_check(terrain["stairs"].get(Vector2i(4, 4)) == Vector2i(1, 0) and terrain["stairs"].get(Vector2i(5, 4)) == Vector2i(1, 0)
		and terrain["slopes"].size() == 2 and terrain["slopes"].has(Vector2i(4, 4)), "the slope is a stair climbing east, and listed as a slope (%s)" % [terrain["slopes"]])
	_check(terrain["kinds"][Vector2i(5, 4)] == "grass", "on the ground round it")
	_check(Array(terrain["rocks"]) == [ROCK] and not ROCK in terrain["floor"] and terrain["kinds"][ROCK] == "grass" and terrain["heights"].get(ROCK) == 2,
		"the rock: no floor, its footing grass, on the plateau's height")
	_check(terrain["edges"].get(Terrain.edge_key(ROCK, Vector2i(0, 1))) == Terrain.Edge.WALL, "walled round")
	_check(level["warnings"].is_empty(), "no warnings (%s)" % [level["warnings"]])
	var lonely := Level.parse(_layout(), null, {"name": "Flat"})
	_check(lonely["warnings"].any(func(w: String) -> bool: return w.begins_with("the slope at (4, 4) has no cell one level up")),
		"a slope with nothing above it is floor, said as a slope (%s)" % [lonely["warnings"]])


func _test_walk_and_fall() -> void:
	print("== walked, fallen from ==")
	_check(_main.load_map("cl_cliff"), "the level loads")
	var player := _player()
	_check(not World.is_walkable(ROCK) and World.is_walkable(Vector2i(7, 2)), "the rock is not walked on")
	_check(World._terrain_blocks_step(Vector2i(5, 3), Vector2i(1, 0)), "the cliff stops a step up")
	_check(World._terrain_blocks_step(Vector2i(6, 3), Vector2i(-1, 0)), "and a step off")
	var path := World.find_path(Vector2i(1, 4), Vector2i(9, 5), true)
	_check(not path.is_empty() and Vector2i(4, 4) in path and Vector2i(5, 4) in path, "the way up is the slope (%s)" % [path])
	_check(World.find_path(Vector2i(7, 2), Vector2i(9, 2), true).all(func(cell: Vector2i) -> bool: return cell != ROCK), "a path goes round the rock")
	var imp: Monster = _main._spawn({"script": Level.MONSTER, "shape": "capsule", "name": "Faller", "tile": Vector2i(6, 5), "props": {"sight_range": 0}})
	World._relocate(player, Vector2i(7, 5))
	var hp := imp.hp
	World._push(player, imp, Vector2i(-1, 0), 3.0)
	_check(imp.tile == Vector2i(5, 5) and hp - imp.hp == World.FALL_IMPACT_PER_LEVEL * 2,
		"pushed off the cliff it falls two levels, hurt as ever (%s, %d)" % [imp.tile, hp - imp.hp])
	_check(not World.find_path(imp.tile, Vector2i(6, 5), true).is_empty(), "and has a way back up, by the slope")
	World.despawn(imp)


func _test_sight() -> void:
	print("== sight over the lip ==")
	_main.load_map("cl_cliff")
	_check(World.has_line_of_sight(Vector2i(2, 3), Vector2i(6, 3)), "from under the cliff, the lip is seen")
	_check(not World.has_line_of_sight(Vector2i(2, 3), Vector2i(8, 3)), "and nothing behind it")
	_check(World.has_line_of_sight(Vector2i(8, 3), Vector2i(2, 3)) and World.has_line_of_sight(Vector2i(9, 5), Vector2i(2, 6)), "from on top, everything below")
	_check(World.has_clear_line(Vector2i(2, 3), Vector2i(8, 3)), "light still reaches past the lip (has_clear_line)")
	_check(not World.has_line_of_sight(Vector2i(7, 2), Vector2i(9, 2)), "the rock stops sight across it")
	var line: Array = World.shot_ray(Vector2i(8, 4), PI, 8)["cells"]
	_check(Vector2i(3, 4) in line, "an archer on top: the shot line reaches a player below (%s)" % [line])
	_check(not Vector2i(8, 4) in World.shot_ray(Vector2i(3, 4), 0.0, 8)["cells"], "and none from below to the top")
	var path := World.find_path(Vector2i(2, 3), Vector2i(6, 3), true)
	_check(not path.is_empty(), "a monster below that saw its quarry on the lip walks there, by the slope (%d steps)" % path.size())


func _test_lay() -> void:
	print("== Outcrops.lay ==")
	var map := LevelMap.new(Vector2i(16, 14))
	for y in 14:
		for x in 16:
			map.set_cell(Vector2i(x, y), "grass")
	map.set_cell(Vector2i(1, 1), "link")
	var rect := Rect2i(0, 0, 16, 14)
	var laid := Outcrops.lay(map, rect, 5)
	var heights: Dictionary = laid["heights"]
	var slopes: Array = laid["cells"].keys().filter(func(cell: Vector2i) -> bool: return laid["cells"][cell] == "slope")
	var raised: Array = heights.keys().filter(func(cell: Vector2i) -> bool: return heights[cell] == 2)
	_check(raised.size() >= 8 and slopes.size() == 2, "a blob two levels up (%d cells), a slope of two (%s)" % [raised.size(), slopes])
	var low: Vector2i = slopes[0] if heights[slopes[0]] == 0 else slopes[1]
	var high: Vector2i = slopes[1] if low == slopes[0] else slopes[0]
	var out := low - high
	_check(heights[high] == 1 and heights.get(high - out) == 2, "the slope climbs one a cell, onto the top")
	var across := Vector2i(absi(out.y), absi(out.x))
	_check(slopes.all(func(cell: Vector2i) -> bool: return heights.get(cell + across, 0) == 0 and heights.get(cell - across, 0) == 0),
		"its sides at its foot's height, no drop beside it")
	var rocks: Array = laid["cells"].keys().filter(func(cell: Vector2i) -> bool: return laid["cells"][cell] == "rock")
	_check(not rocks.is_empty() and rocks.all(_on_lip.bind(heights)), "rocks on its lip (%s)" % [rocks])
	_check(rocks.all(func(cell: Vector2i) -> bool: return maxi(absi(cell.x - (high - out).x), absi(cell.y - (high - out).y)) > 1), "none at the slope's mouth")
	_check(not heights.has(Vector2i(1, 1)) and not heights.has(Vector2i(2, 2)), "clear of the link")
	_check(str(Outcrops.lay(map, rect, 5)) == str(laid), "the same seed, the same outcrop")
	_check(Outcrops.lay(map, Rect2i(0, 0, 3, 3), 5)["heights"].is_empty(), "too small an area: none")


func _test_sample() -> void:
	print("== the sample level ==")
	var level := Level.load_level("sample")
	var terrain: Dictionary = level["terrain"]
	_check(terrain["slopes"].size() == 2 and terrain["rocks"].size() >= 1 and terrain["heights"].values().has(2),
		"an outcrop: a slope of two, rocks on its lip (%s, %s)" % [terrain["slopes"], terrain["rocks"]])
	_check(level["warnings"].is_empty(), "no warnings (%s)" % [level["warnings"]])


## Two levels up with a neighbour that is not.
static func _on_lip(cell: Vector2i, heights: Dictionary) -> bool:
	if heights.get(cell) != 2:
		return false
	for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if heights.get(cell + step, 0) != 2:
			return true
	return false


func _player() -> Player:
	for entity in World.get_entities():
		if entity is Player and entity.spawned:
			return entity
	return null


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
