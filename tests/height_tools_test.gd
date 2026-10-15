extends Node
## HeightTools (decision 356): raise, level, hill, stair and flight give
## heights and stairs Level.parse reads as made (each stair climbing the
## one way, no warning), void untouched, heights kept within 0..MAX_HEIGHT,
## a reason and no changes when a tool cannot; ledge_warnings finds a thing
## cut off by ledges, and not one a stair reaches.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

var _failures := 0


func _ready() -> void:
	_test_raise_and_level()
	_test_stair()
	_test_flight()
	_test_hill()
	_test_ledges()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


static func _field(size := Vector2i(24, 24)) -> LevelMap:
	var map := LevelMap.new(size)
	for y in size.y:
		for x in size.x:
			map.set_cell(Vector2i(x, y), "grass")
	return map


## [param map] with [param changes] laid on it, as MapDoc.apply_changes would.
static func _laid(map: LevelMap, changes: Dictionary) -> LevelMap:
	var out := map.copy()
	for at: Vector2i in changes.get("cells", {}):
		out.set_cell(at, changes["cells"][at])
	for key: Vector3i in changes.get("edges", {}):
		out.set_edge(key, changes["edges"][key])
	for at: Vector2i in changes.get("heights", {}):
		if int(changes["heights"][at]) == 0:
			out.heights.erase(at)
		else:
			out.heights[at] = int(changes["heights"][at])
	return out


static func _parsed(map: LevelMap) -> Dictionary:
	return Level.parse(map.to_image(), map.to_height_image(), {})


static func _stair_warnings(level: Dictionary) -> Array:
	return (level["warnings"] as Array).filter(func(line: String) -> bool: return "stair" in line)


func _test_raise_and_level() -> void:
	print("\n== raise and level: each cell once, clamped, void left ==")
	var map := _field()
	map.set_cell(Vector2i(3, 3), "void")
	var cells: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 3)]
	var up := HeightTools.raise(map, cells, 2)
	_check(up["heights"] == {Vector2i(1, 1): 2, Vector2i(2, 1): 2}, "raise by 2: a cell listed twice raised once, void left (%s)" % up["heights"])
	map = _laid(map, up)
	_check(HeightTools.raise(map, [Vector2i(1, 1)] as Array[Vector2i], 9)["heights"][Vector2i(1, 1)] == Level.MAX_HEIGHT, "raised past the top: the top")
	_check(HeightTools.raise(map, [Vector2i(1, 1)] as Array[Vector2i], -5)["heights"][Vector2i(1, 1)] == 0, "lowered past the ground: 0")
	_check(HeightTools.level(map, [Vector2i(1, 1), Vector2i(5, 5)] as Array[Vector2i], 2)["heights"] == {Vector2i(5, 5): 2}, "level to 2: only what was not 2")
	_check(_parsed(map)["terrain"]["heights"] == {Vector2i(1, 1): 2, Vector2i(2, 1): 2}, "Level.parse reads them")


func _test_stair() -> void:
	print("\n== stair: onto a ledge, up from flat, the top, sides walled ==")
	var map := _field()
	# A cliff: rows 0-9 at height 2, a stair cut into it at (5, 10) climbing north.
	for y in 10:
		for x in 24:
			map.heights[Vector2i(x, y)] = 2
	var cut := HeightTools.stair(map, Vector2i(5, 10), Vector2i(0, -1))
	_check(cut.get("reason", "") == "" and cut["cells"].keys() == [Vector2i(5, 11), Vector2i(5, 10)] and cut["heights"] == {Vector2i(5, 10): 1},
			"beside a ledge 2 up: a flight of two, (5, 11) at 0 and (5, 10) at 1 (%s, %s)" % [cut["cells"].keys(), cut["heights"]])
	var laid := _laid(map, cut)
	var level := _parsed(laid)
	_check(level["terrain"]["stairs"].get(Vector2i(5, 10)) == Vector2i(0, -1) and level["terrain"]["stairs"].get(Vector2i(5, 11)) == Vector2i(0, -1)
			and _stair_warnings(level).is_empty(), "both climb north, no warning (%s)" % str(_stair_warnings(level)))
	_check(HeightTools.ledge_warnings(laid, [Vector2i(5, 5)] as Array[Vector2i]).is_empty(), "the cliff top is reached")
	# Cut into the face: the cliff's cells either side are a level above it too.
	var face := _field()
	for y in 10:
		for x in 24:
			face.heights[Vector2i(x, y)] = 2
	for x in 24:
		face.heights[Vector2i(x, 10)] = 1
	var side := HeightTools.stair(face, Vector2i(5, 11), Vector2i(0, -1))
	level = _parsed(_laid(face, side))
	_check(level["terrain"]["stairs"].get(Vector2i(5, 11)) == Vector2i(0, -1) and _stair_warnings(level).is_empty(), "on flat ground before a step: climbs one way")
	var flat := _field()
	var up := HeightTools.stair(flat, Vector2i(8, 8), Vector2i(1, 0))
	_check(up["heights"] == {Vector2i(9, 8): 1}, "on flat ground: the cell beyond is raised a level")
	flat.heights[Vector2i(8, 8)] = Level.MAX_HEIGHT
	_check(HeightTools.stair(flat, Vector2i(8, 8), Vector2i(1, 0)).get("reason", "") != "", "at the top: a reason")
	flat.set_cell(Vector2i(9, 8), "water")
	var none := HeightTools.stair(flat, Vector2i(8, 8), Vector2i(1, 0))
	_check(none.get("reason", "") != "" and none["cells"].is_empty() and none["heights"].is_empty(), "toward water: a reason and no changes")


func _test_flight() -> void:
	print("\n== flight: a stair a level, the landing on top; into a cliff, sides walled ==")
	var map := _field()
	for y in 6:
		for x in 24:
			map.heights[Vector2i(x, y)] = 3
	# From the foot at (10, 9) north to the landing at (10, 6), cut into the face's side cells.
	for x in [9, 11]:
		for y in [6, 7, 8]:
			map.heights[Vector2i(x, y)] = 3
	var run := HeightTools.flight(map, Vector2i(10, 9), Vector2i(10, 6))
	_check(run.get("reason", "") == "", "made (%s)" % run.get("reason", ""))
	var laid := _laid(map, run)
	var level := _parsed(laid)
	var stairs: Dictionary = level["terrain"]["stairs"]
	_check(stairs.get(Vector2i(10, 9)) == Vector2i(0, -1) and stairs.get(Vector2i(10, 8)) == Vector2i(0, -1) and stairs.get(Vector2i(10, 7)) == Vector2i(0, -1),
			"three stairs climbing north (%s)" % stairs)
	_check(laid.heights.get(Vector2i(10, 6)) == 3 and laid.heights.get(Vector2i(10, 7)) == 2, "the landing at 3")
	_check(_stair_warnings(level).is_empty(), "no stair warning though its sides are a level up (%s)" % str(_stair_warnings(level)))
	_check(HeightTools.ledge_warnings(laid, [Vector2i(3, 2)] as Array[Vector2i]).is_empty(), "the top is reached from below")
	_check(HeightTools.flight(map, Vector2i(1, 1), Vector2i(3, 3)).get("reason", "") != "", "not along a row or column: a reason")
	_check(HeightTools.flight(map, Vector2i(1, 20), Vector2i(1, 13)).get("reason", "") != "", "seven levels up: a reason")


func _test_hill() -> void:
	print("\n== hill: terraces up to its top, stairs up the sides asked ==")
	var map := _field(Vector2i(30, 30))
	map.set_cell(Vector2i(15, 13), "void")
	var made := HeightTools.hill(map, Vector2i(15, 15), 8, 4, [Vector2i(0, 1), Vector2i(1, 0)] as Array[Vector2i])
	var laid := _laid(map, made)
	_check(laid.heights.get(Vector2i(15, 15)) == 4 and not laid.heights.has(Vector2i(15, 13)), "the top at 4, the void cell given none")
	var bounded := laid.heights.values().all(func(h: int) -> bool: return h >= 1 and h <= 4)
	_check(bounded and not laid.heights.has(Vector2i(2, 2)), "everything raised 1..4, the corner untouched")
	var jumps := 0
	for at: Vector2i in laid.heights:
		for side in HeightTools.FOUR:
			if absi(int(laid.heights.get(at + side, 0)) - int(laid.heights[at])) > 1 and laid.walkable(at + side):
				jumps += 1
	_check(jumps == 0, "a level a ring: no step of two")
	var level := _parsed(laid)
	var south := 0
	var east := 0
	for at: Vector2i in level["terrain"]["stairs"]:
		if level["terrain"]["stairs"][at] == Vector2i(0, -1):
			south += 1
		elif level["terrain"]["stairs"][at] == Vector2i(-1, 0):
			east += 1
	_check(south == 4 and east == 4 and _stair_warnings(level).is_empty(), "four stairs up the south side, four up the east, no warning (%d, %d, %s)" % [south, east, str(_stair_warnings(level))])
	_check(HeightTools.ledge_warnings(laid, [Vector2i(15, 15)] as Array[Vector2i]).is_empty(), "the top is reached")
	var bare := _laid(_field(Vector2i(30, 30)), HeightTools.hill(map, Vector2i(15, 15), 8, 4))
	_check(HeightTools.ledge_warnings(bare, [Vector2i(15, 15), Vector2i(15, 14)] as Array[Vector2i]).size() == 1,
			"no stairs: the top is cut off, said once for its patch")
	_check(HeightTools.hill(map, Vector2i(15, 15), 2, 6)["heights"].values().max() == 2, "a top higher than the radius: the radius")
	var already := _field(Vector2i(30, 30))
	already.heights[Vector2i(10, 15)] = 6
	_check(not HeightTools.hill(already, Vector2i(15, 15), 8, 4)["heights"].has(Vector2i(10, 15)), "higher ground is never lowered")


func _test_ledges() -> void:
	print("\n== ledge_warnings: a pillar, a walled yard, open ground ==")
	var map := _field()
	map.heights[Vector2i(4, 4)] = 1
	_check(HeightTools.ledge_warnings(map, [Vector2i(4, 4), Vector2i(10, 10)] as Array[Vector2i]).size() == 1, "a raised cell is cut off; open ground is not")
	var yard := _field()
	for key: Vector3i in Level.outline(Rect2i(2, 2, 4, 4)):
		yard.set_edge(key, "wall")
	_check(HeightTools.ledge_warnings(yard, [Vector2i(3, 3)] as Array[Vector2i]).is_empty(), "walled in on flat ground: not a ledge, not said")


func _check(ok: bool, what: String) -> void:
	print("%s: %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
