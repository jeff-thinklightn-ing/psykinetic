extends Node
## Streams, fords and bridges (decision 505) on a little level with a
## stream down its middle: the stream's cells water, its "streams" path
## read in order (one off the water, or with a gap, warns); a ford in it is
## floor, not water, walked into at half pace and costing routes twice a
## step; a bridge over it is floor at its banks' height, the water under it
## kept for drawing, railings along its sides that stop walkers but not
## sight; bridges not over water or between banks of two heights are left
## out, said; a player walks across both, and their companion follows over
## the bridge rather than stalling at the bank; Streams.lay lays a stream
## across a map with a ford and a bridge where paths cross it; WorldMap
## says what is wrong with a ford or bridge. Run it with tests/run.ps1 or
## tests/run.sh.

const WIDTH := 14
const HEIGHT := 9
const FORD := Vector2i(7, 2)
const BRIDGE := Vector2i(7, 6)

var _failures := 0
var _main: Node


const Walk := preload("res://tests/walk.gd")


func _ready() -> void:
	World.set_process(false)
	Net.port = preload("res://tests/test_ports.gd").of(17862)
	Monster.idling = false
	_main = preload("res://main.tscn").instantiate()
	_main.returns = false
	add_child(_main)
	_register()
	_test_parse()
	_test_bad()
	_test_world()
	_test_routes()
	_test_walk_and_follow()
	_test_lay()
	_test_problems()
	_main.load_map(Level.DEFAULT_MAP)
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## The stream down x 7, a ford at FORD, a bridge over it at BRIDGE (facing
## east, one long), the start on the west bank.
static func _layout(extra: Dictionary = {}) -> Image:
	var rows: Array[String] = []
	for y in 2 * HEIGHT - 1:
		rows.append(".".repeat(2 * WIDTH - 1))
	var markers := {Vector2i(2, 4): "start", FORD: "ford"}
	for y in HEIGHT:
		if Vector2i(7, y) != FORD:
			markers[Vector2i(7, y)] = "water"
	markers.merge(extra, true)
	return Level.image_from_rows(rows, markers)


static func _config(more: Dictionary = {}) -> Dictionary:
	var path := []
	for y in HEIGHT:
		path.append([7, y])
	var out := {"name": "The Stream", "outdoor": true, "streams": [{"path": path}],
		"buildings": [{"slot": "bridge", "at": [BRIDGE.x, BRIDGE.y], "facing": [1, 0], "length": 1}]}
	out.merge(more, true)
	return out


func _register() -> void:
	Level.register("st_stream", _layout(), null, _config())


func _test_parse() -> void:
	print("== the level ==")
	var level := Level.load_level("st_stream")
	var terrain: Dictionary = level["terrain"]
	_check(Array(terrain["fords"]) == [FORD] and FORD in terrain["floor"] and not FORD in terrain["water"],
		"the ford is floor, not water (%s)" % [terrain["fords"]])
	_check(BRIDGE in terrain["floor"] and not BRIDGE in terrain["water"] and Array(terrain["bridged"]) == [BRIDGE],
		"the bridge's cell is floor, the water under it kept as bridged (%s)" % [terrain["bridged"]])
	var railings: Array = terrain["railings"]
	_check(railings.size() == 2 and Terrain.edge_key(BRIDGE, Vector2i(0, 1)) in railings and Terrain.edge_key(BRIDGE, Vector2i(0, -1)) in railings
		and terrain["edges"].get(railings[0]) == Terrain.Edge.WALL, "railings on its two long sides, wall edges (%s)" % [railings])
	var bridges: Array = level["buildings"].filter(func(b: Dictionary) -> bool: return b["slot"] == Level.BRIDGE)
	_check(bridges.size() == 1 and bridges[0]["banks"] == [Vector2i(6, 6), Vector2i(8, 6)] and not Level.has_inside(bridges[0]),
		"one bridge, from the west bank to the east, nothing inside it (%s)" % [bridges])
	var streams: Array = terrain["streams"]
	_check(streams.size() == 1 and streams[0]["path"].size() == HEIGHT and streams[0]["path"][0] == Vector2i(7, 0),
		"its stream's path, source to mouth, over the ford and under the bridge (%s)" % [streams])
	_check(level["warnings"].is_empty(), "and no warnings (%s)" % [level["warnings"]])


func _test_bad() -> void:
	print("== what is said ==")
	var warnings: Array[String] = Level.parse(_layout(), null, _config({"streams": [{"path": [[7, 0], [7, 2], [7, 3]]}, {"path": [[3, 3], [3, 4]]}]}))["warnings"]
	_check(warnings.size() == 2 and warnings.any(func(w: String) -> bool: return "not beside" in w) and warnings.any(func(w: String) -> bool: return "no water" in w),
		"a stream with a gap, and one off the water, are said and left out (%s)" % [warnings])
	warnings = Level.parse(_layout(), null, _config({"buildings": [{"slot": "bridge", "at": [3, 3], "facing": [1, 0], "length": 2}]}))["warnings"]
	_check(warnings.size() == 1 and "not all over water" in warnings[0], "a bridge on dry ground is left out (%s)" % [warnings])
	var high := Level.height_image(_layout(), {Vector2i(8, 6): 1})
	warnings = Level.parse(_layout(), high, _config())["warnings"]
	_check(warnings.any(func(w: String) -> bool: return "two heights" in w), "banks of two heights: left out, level banks only (%s)" % [warnings])


func _test_world() -> void:
	print("== in the world ==")
	_check(_main.load_map("st_stream"), "the level loads")
	_check(World.is_water(Vector2i(7, 4)) and not World.is_walkable(Vector2i(7, 4)), "the stream is water, not walked")
	_check(World.is_ford(FORD) and not World.is_water(FORD) and World.is_walkable(FORD), "the ford: walked, not water")
	_check(World.is_walkable(BRIDGE) and not World.is_water(BRIDGE), "the bridge: walked")
	var player := _player()
	World._relocate(player, FORD + Vector2i(-1, 0))
	_check(is_equal_approx(World.step_ticks(player, Vector2i(1, 0)), player.move_ticks * World.FORD_TICK_SCALE)
		and is_equal_approx(World.step_ticks(player, Vector2i(0, 1)), player.move_ticks), "a step into the ford takes twice as long, beside it as ever")
	_check(World.edge_blocks(BRIDGE, Vector2i(0, 1)) and not World.edge_blocks_sight(BRIDGE, Vector2i(0, 1)),
		"the railing stops a step off the bridge but not sight")
	_check(not World.edge_blocks(BRIDGE, Vector2i(1, 0)) and not World.edge_blocks(BRIDGE, Vector2i(-1, 0)), "its ends are open to the banks")


func _test_routes() -> void:
	print("== routes ==")
	var names: Array[String] = ["st_stream"]
	var routes := WorldMap.build(names).routes()
	routes.wait()
	var through_ford := routes.steps_from("st_stream", Vector2i(5, 2), [Vector2i(9, 2)] as Array[Vector2i])
	_check(through_ford.get(Vector2i(9, 2), -1.0) == 5.0, "across the ford: 4 steps, the one into it costing 2 (%s)" % [through_ford])
	var over_bridge := routes.steps_from("st_stream", Vector2i(5, 6), [Vector2i(9, 6)] as Array[Vector2i])
	_check(over_bridge.get(Vector2i(9, 6), -1.0) == 4.0, "over the bridge: 4 steps (%s)" % [over_bridge])
	var area: Dictionary = WorldMap.build(names).areas["st_stream"]
	_check(WorldRoutes._steps_between(area, Vector2i(5, 2), Vector2i(9, 2)) == 5.0, "A* agrees")


func _test_walk_and_follow() -> void:
	print("== walking over, followed ==")
	_main.load_map("st_stream")
	var player := _player()
	World._relocate(player, Vector2i(5, 2))
	Walk.to(player, Vector2i(10, 2), 80)  # A free body (703).
	_check(player.tile == Vector2i(10, 2), "a player walks through the ford (%s)" % player.tile)
	World._relocate(player, Vector2i(4, 6))
	var pet := _companion()
	if pet == null:
		_check(false, "a companion to follow")
		return
	World._relocate(pet, _main._nearest_free(Vector2i(3, 6)))
	for i in 10:
		World.step()
	Walk.to(player, Vector2i(12, 6), 160)
	_check(player.tile == Vector2i(12, 6), "they walk over the bridge (%s)" % player.tile)
	_check(pet.tile.x > 7, "their companion follows across, not stalled at the bank (%s)" % pet.tile)


func _test_lay() -> void:
	print("== Streams.lay ==")
	var map := LevelMap.new(Vector2i(40, 30))
	for y in 30:
		for x in 40:
			map.set_cell(Vector2i(x, y), "grass")
	var path: Array[Vector2i] = []
	for x in 40:
		path.append(Vector2i(x, 15))
	var laid := Streams.lay(map, Vector2i(20, 0), Vector2i(20, 29), {"seed": 7, "width": 2, "fords": [path], "bridges": []})
	var stream_path: Array = laid.get("path", [])
	_check(stream_path.size() >= 30 and stream_path[0].y == 0 and stream_path[-1].y == 29, "a course from the top edge to the bottom (%d cells)" % stream_path.size())
	var wet := 0
	for cell: Vector2i in stream_path:
		if map.cell(cell) in ["water", "ford"]:
			wet += 1
	_check(wet == stream_path.size(), "every cell on it water or a ford")
	var crossing := path.filter(func(cell: Vector2i) -> bool: return map.cell(cell) == "ford")
	_check(not crossing.is_empty() and path.all(func(cell: Vector2i) -> bool: return map.cell(cell) != "water"),
		"where the path crosses it, a ford: the path stays dry or shallow (%d ford cells)" % crossing.size())
	var again := LevelMap.new(Vector2i(40, 30))
	for y in 30:
		for x in 40:
			again.set_cell(Vector2i(x, y), "grass")
	var bridged := Streams.lay(again, Vector2i(20, 0), Vector2i(20, 29), {"seed": 7, "width": 2, "fords": [], "bridges": [path]})
	_check(bridged.get("bridges", []).size() == 1 and bridged["bridges"][0]["slot"] == Level.BRIDGE, "or a bridge, as a building entry (%s)" % [bridged.get("bridges")])
	var same := LevelMap.new(Vector2i(40, 30))
	for y in 30:
		for x in 40:
			same.set_cell(Vector2i(x, y), "grass")
	_check(Streams.lay(same, Vector2i(20, 0), Vector2i(20, 29), {"seed": 7, "width": 2, "fords": [path], "bridges": []})["path"] == stream_path,
		"the same seed lays the same stream")


func _test_problems() -> void:
	print("== the world map's problems ==")
	var lone := _layout({Vector2i(3, 0): "ford"})
	Level.register("st_bad", lone, null, _config())
	var names: Array[String] = ["st_bad"]
	var problems := WorldMap.build(names).problems()
	_check(problems.any(func(p: String) -> bool: return "ford" in p and "(3, 0)" in p), "a ford with no water beside it is said (%s)" % [problems])


func _player() -> Player:
	for entity in World.get_entities():
		if entity is Player and entity.spawned:
			return entity
	return null


func _companion() -> Companion:
	for entity in World.get_entities():
		if entity is Companion and entity.spawned:
			return entity
	return null


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
