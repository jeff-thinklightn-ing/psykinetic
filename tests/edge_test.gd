extends Node
## Walls and doors as edges between cells, in rooms written in the
## double-resolution map format (see Terrain).
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

## A 5 x 4 room. Cell (1, 1) has a wall on its east and south edges, which
## meet at a corner; the edge east of (1, 2) is a door.
const ROOM: Array[String] = [
	". . . . .",
	"         ",
	". .#. . .",
	"  #      ",
	". .+. . .",
	"         ",
	". . . . .",
]
const DOOR_KEY := Vector3i(1, 2, Terrain.EAST)

var _failures := 0
var _room: Node2D
var _pushes: Array[Dictionary] = []
var _damage: Array[Dictionary] = []


func _ready() -> void:
	World.set_process(false)
	World.entity_pushed.connect(func(entity: GridEntity, _by: GridEntity, _direction: Vector2i, tiles: int, impact: int, stopped_by: String) -> void:
		_pushes.append({"entity": entity, "tiles": tiles, "impact": impact, "stopped_by": stopped_by}))
	World.entity_damaged.connect(func(entity: GridEntity, amount: int, _source: GridEntity, cause: StringName) -> void:
		_damage.append({"entity": entity, "amount": amount, "cause": cause}))

	_test_map_format()
	_test_moving_across_edges()
	_test_push_against_a_wall_edge()
	_test_sight_through_edges()
	_test_doors()
	_test_door_breaks()
	_test_projection()
	_test_near_walls()

	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_map_format() -> void:
	print("\n== the map format ==")
	var terrain := Terrain.parse(ROOM)
	var edges: Dictionary = terrain["edges"]
	_check(terrain["floor"].size() == 20, "every cell is floor (%d)" % terrain["floor"].size())
	_check(edges.get(Vector3i(1, 1, Terrain.EAST)) == Terrain.Edge.WALL and edges.get(Vector3i(1, 1, Terrain.SOUTH)) == Terrain.Edge.WALL,
			"# on an edge position is a wall")
	_check(edges.get(DOOR_KEY) == Terrain.Edge.DOOR, "+ on an edge position is a door")
	_check(edges.get(Vector3i(0, -1, Terrain.SOUTH)) == Terrain.Edge.WALL and edges.get(Vector3i(-1, 0, Terrain.EAST)) == Terrain.Edge.WALL
			and edges.get(Vector3i(4, 0, Terrain.EAST)) == Terrain.Edge.WALL and edges.get(Vector3i(2, 3, Terrain.SOUTH)) == Terrain.Edge.WALL,
			"the outline, where floor meets nothing, is walled without being spelled out")
	var inside := 0
	for key: Vector3i in edges:
		var cells := Terrain.edge_cells(key)
		if cells[0] in terrain["floor"] and cells[1] in terrain["floor"]:
			inside += 1
	_check(inside == 3, "and only the three edges written are walls between floor cells (%d)" % inside)
	var old := Terrain.expand(["#..", ".#."])
	var converted := Terrain.parse(old)
	_check(converted["floor"].size() == 4 and converted["edges"].get(Vector3i(0, 1, Terrain.EAST)) == Terrain.Edge.WALL,
			"an old cell map expands: a wall cell is nothing with walls on its sides")


func _test_moving_across_edges() -> void:
	print("\n== moving across edges ==")
	_build()
	var player := _spawn("res://sim/player.gd", "Player", Vector2i(1, 1))
	_check(not World.try_move(player, Vector2i(1, 0)) and player.tile == Vector2i(1, 1), "a move across a wall edge fails")
	_check(not World.try_move(player, Vector2i(0, 1)), "across the other wall edge too")
	_check(not World.try_move(player, Vector2i(1, 1)), "a diagonal past the wall corner fails")
	_check(not World.try_move(player, Vector2i(-1, 1)), "a diagonal past the end of a wall fails as well")
	_check(World.try_move(player, Vector2i(0, -1)) and player.tile == Vector2i(1, 0), "a move across an open edge succeeds")
	_wait(player)
	_check(not World.try_move(player, Vector2i(1, 1)), "a diagonal past the top end of that wall fails too")
	World.try_move(player, Vector2i(1, 0))
	_wait(player)
	_check(player.tile == Vector2i(2, 0) and World.try_move(player, Vector2i(1, 1)) and player.tile == Vector2i(3, 1),
			"and a diagonal with nothing at its corner succeeds")
	_check(World.find_path(Vector2i(1, 1), Vector2i(2, 1)).size() > 1, "a path around a wall edge goes around it (%d steps)" % World.find_path(Vector2i(1, 1), Vector2i(2, 1)).size())
	_check(not World.can_melee(Vector2i(1, 1), Vector2i(2, 1)) and World.can_melee(Vector2i(1, 0), Vector2i(2, 0)),
			"nothing hits across a wall edge")


func _test_push_against_a_wall_edge() -> void:
	print("\n== a push against a wall edge ==")
	_build()
	var player := _spawn("res://sim/player.gd", "Player", Vector2i(0, 1))
	var imp := _spawn("res://sim/monster.gd", "Imp", Vector2i(1, 1))
	_pushes.clear()
	_damage.clear()
	World.order_shove(player, imp)
	World.step()
	var push: Dictionary = _pushes.back() if not _pushes.is_empty() else {}
	_check(imp.tile == Vector2i(1, 1) and push.get("tiles") == 0, "the imp stops where it is, against the edge")
	_check(push.get("stopped_by") == "wall" and push.get("impact", 0) > 0 and _impact_on(imp) == push.get("impact"),
			"and takes impact as against a wall (%d), stopped by: %s" % [push.get("impact", 0), push.get("stopped_by")])
	_check(World.is_stunned(imp), "and is stunned by the collision")


func _test_sight_through_edges() -> void:
	print("\n== line of sight ==")
	_build()
	_check(not World.has_line_of_sight(Vector2i(1, 1), Vector2i(3, 1)), "a wall edge blocks sight along a row")
	_check(World.has_line_of_sight(Vector2i(1, 0), Vector2i(3, 0)), "an open row does not")
	_check(not World.has_line_of_sight(Vector2i(1, 1), Vector2i(2, 2)), "nor does sight pass the wall corner diagonally")
	_check(World.has_line_of_sight(Vector2i(2, 0), Vector2i(4, 2)), "a diagonal across open cells is clear")
	var imp := _spawn("res://sim/monster.gd", "Imp", Vector2i(3, 1))
	var player := _spawn("res://sim/player.gd", "Player", Vector2i(1, 1))
	imp.sight_range = 7
	World.step()
	_check(imp.tile == Vector2i(3, 1), "an imp with a wall edge between it and the player does not see it (stays at %s)" % imp.tile)
	World.despawn(player)


func _test_doors() -> void:
	print("\n== doors ==")
	_build()
	var door := _door(DOOR_KEY, 20)
	var player := _spawn("res://sim/player.gd", "Player", Vector2i(1, 2))
	var crate := _spawn("res://sim/pushable.gd", "Crate", Vector2i(3, 2))
	_check(not door.open and World.edge_blocks(Vector2i(1, 2), Vector2i(1, 0)), "the door starts closed, and a closed door blocks")
	_check(not World.has_line_of_sight(Vector2i(1, 2), Vector2i(3, 2)), "and blocks sight")
	_check(not World.try_toggle_door(player, Vector3i(1, 1, Terrain.EAST)), "a wall is not a door to toggle")
	_check(World.try_toggle_door(player, DOOR_KEY) and door.open, "a player beside it opens it (command)")
	_check(World.has_line_of_sight(Vector2i(1, 2), Vector2i(3, 2)), "an open door lets sight through")
	_wait(player)
	_check(World.try_toggle_door(player, DOOR_KEY) and not door.open, "and closes it again")
	_wait(player)
	_check(World.try_move(player, Vector2i(1, 0)) and player.tile == Vector2i(2, 2) and door.open,
			"walking into a closed door opens it and steps through")
	_wait(player)
	World.try_toggle_door(player, DOOR_KEY)
	_check(not door.open and player.tile == Vector2i(2, 2), "closed again from the other side")
	_check(not World.try_toggle_door(crate, DOOR_KEY), "a crate cannot work a door")
	var far := _spawn("res://sim/player.gd", "Far", Vector2i(3, 3))
	_check(not World.try_toggle_door(far, DOOR_KEY), "nor can a player that is not beside it")
	# A crate cannot go through a closed door: walking it into the door fails.
	_wait(player)
	World.despawn(crate)
	var box := _spawn("res://sim/pushable.gd", "Box", Vector2i(1, 2))
	var pusher := _spawn("res://sim/player.gd", "Pusher", Vector2i(0, 2))
	_check(not World.try_move(pusher, Vector2i(1, 0)) and box.tile == Vector2i(1, 2), "a crate walked into a closed door stays put")
	_check(World.find_path(Vector2i(0, 2), Vector2i(4, 2), false, pusher).size() <= 5, "a creature's path goes through the door (%d steps)" % World.find_path(Vector2i(0, 2), Vector2i(4, 2), false, pusher).size())
	# A monster opens a door by walking into it, unless the doorway cell on
	# the other side is held: that is just occupancy.
	World.despawn(far)
	World.despawn(pusher)
	World.despawn(box)
	var imp := _spawn("res://sim/monster.gd", "Imp", Vector2i(1, 2))
	imp.sight_range = 7
	World.step()
	_check(not door.open and not World.can_melee(imp.tile, player.tile) and player.hp == player.max_hp,
			"a closed door keeps the imp beside it from seeing or hitting the player")
	_check(not World.try_move(imp, Vector2i(1, 0)) and not door.open, "held: with the player in the doorway cell the imp cannot come through, and the door stays shut")
	World.try_move(player, Vector2i(1, 0))
	_wait(imp)
	_check(World.try_move(imp, Vector2i(1, 0)) and door.open and imp.tile == Vector2i(2, 2), "with the doorway free a monster opens the door and comes through")


func _test_door_breaks() -> void:
	print("\n== a door takes impact and breaks ==")
	_build()
	var door := _door(DOOR_KEY, 3)
	var player := _spawn("res://sim/player.gd", "Player", Vector2i(0, 2))
	var imp := _spawn("res://sim/monster.gd", "Imp", Vector2i(1, 2))
	_pushes.clear()
	World.order_shove(player, imp)
	World.step()
	var push: Dictionary = _pushes.back() if not _pushes.is_empty() else {}
	_check(imp.tile == Vector2i(1, 2) and push.get("stopped_by") == door.name and push.get("impact", 0) > 0,
			"an imp shoved into a closed door stops and takes impact (%d)" % push.get("impact", 0))
	_check(door.is_broken() and door.is_open(), "impact of at least the door's hp breaks it (hp %d)" % door.hp)
	_check(not World.edge_blocks(Vector2i(1, 2), Vector2i(1, 0)) and World.has_line_of_sight(Vector2i(0, 2), Vector2i(4, 2)),
			"a broken door is open for good")
	_check(not World.try_toggle_door(player, DOOR_KEY), "and cannot be closed")

	_build()
	var stone := _door(DOOR_KEY, 3, GridEntity.BodyMaterial.STONE)
	player = _spawn("res://sim/player.gd", "Player", Vector2i(0, 2))
	imp = _spawn("res://sim/monster.gd", "Imp", Vector2i(1, 2))
	World.order_shove(player, imp)
	World.step()
	_check(stone.hp == 3 and not stone.is_broken(), "a stone door takes nothing (hp %d)" % stone.hp)


func _test_projection() -> void:
	print("\n== drawing: the projection turns with the azimuth; 0 is the 2:1 diamond, 45 the axis-aligned view ==")
	Iso.set_azimuth(0.0)
	var tile := Vector2i(3, 5)
	_check(Iso.tile_to_local(tile).is_equal_approx(Vector2((3 - 5) * 16 + 16, (3 + 5) * 8 + 8)), "at 0 a tile centre is where the diamond TileSet puts it")
	_check(Iso.axis_x().is_equal_approx(Vector2(16, 8)) and Iso.axis_y().is_equal_approx(Vector2(-16, 8)), "at 0 the axes run down-right and down-left")
	Iso.set_azimuth(45.0)
	_check(Iso.axis_x().is_equal_approx(Vector2(Iso.UNIT, 0)) and Iso.axis_y().is_equal_approx(Vector2(0, Iso.UNIT * 0.5)),
			"at +45 x runs right and y down: an upright 2:1 cell")
	Iso.set_azimuth(-45.0)
	_check(Iso.axis_x().is_equal_approx(Vector2(0, Iso.UNIT * 0.5)) and Iso.axis_y().is_equal_approx(Vector2(-Iso.UNIT, 0)),
			"at -45 x runs down and y left")
	Iso.set_azimuth(22.0)
	var grid := Vector2(2.3, -1.7)
	_check(Iso.local_to_grid(Iso.grid_to_local(grid)).is_equal_approx(grid), "grid -> local -> grid round-trips at 22")
	_check(Iso.local_to_tile(Iso.tile_to_local(tile)) == tile, "and a tile centre comes back as that tile")
	_check(Iso.faces_camera(Terrain.EAST) and Iso.faces_camera(Terrain.SOUTH), "east and south faces point at the camera at 22")
	Iso.set_azimuth(60.0)
	_check(Iso.azimuth == 45.0, "the azimuth is clamped to the range")
	var floor_at := func(cell: Vector2i) -> bool: return cell == Vector2i(1, 1)
	for degrees in [-45.0, 0.0, 45.0]:
		Iso.set_azimuth(degrees)
		_check(WallEdge.is_near(Vector3i(1, 1, Terrain.SOUTH), floor_at) and not WallEdge.is_near(Vector3i(1, 0, Terrain.SOUTH), floor_at),
				"at %d the walkable cell's south edge is near and its north edge far" % int(degrees))
	Iso.set_azimuth(0.0)


func _test_near_walls() -> void:
	print("\n== drawing: a wall on the south or east edge of a walkable cell is near (translucent), the others far ==")
	# Floor at (1, 1) and (2, 1) in a void.
	var floor_at := func(cell: Vector2i) -> bool: return cell in [Vector2i(1, 1), Vector2i(2, 1)]
	_check(WallEdge.is_near(Vector3i(1, 1, Terrain.SOUTH), floor_at), "a walkable cell's south edge: near")
	_check(WallEdge.is_near(Vector3i(2, 1, Terrain.EAST), floor_at), "a walkable cell's east edge: near")
	_check(not WallEdge.is_near(Vector3i(1, 0, Terrain.SOUTH), floor_at), "its north edge (the south edge of nothing): far")
	_check(not WallEdge.is_near(Vector3i(0, 1, Terrain.EAST), floor_at), "its west edge (the east edge of nothing): far")
	_check(WallEdge.is_near(Vector3i(1, 1, Terrain.EAST), floor_at), "a partition between two walkable cells: near, by the cell it is the east edge of")
	_check(WallEdge.full_height() == Iso.height_px("wall"), "every wall is the scale table's full height")
	_check(Main.NEAR_WALL_ALPHA > 0.0 and Main.NEAR_WALL_ALPHA < 1.0, "near walls are translucent (%.2f)" % Main.NEAR_WALL_ALPHA)


# --- helpers ------------------------------------------------------------------

func _build() -> void:
	World.reset()
	if _room != null:
		_room.free()
	_room = Node2D.new()
	add_child(_room)
	World.load_terrain(Terrain.parse(ROOM))


func _spawn(script: String, entity_name: String, tile: Vector2i) -> GridEntity:
	var entity := EntityFactory.build({"script": script, "shape": "capsule", "name": entity_name, "tile": tile})
	if entity is Monster:
		entity.sight_range = 0
	_room.add_child(entity)
	assert(World.spawn(entity, tile), "could not spawn %s at %s" % [entity_name, tile])
	return entity


func _door(key: Vector3i, hp: int, material := GridEntity.BodyMaterial.WOOD) -> Door:
	var door := Door.build({"script": "res://sim/door.gd", "name": "Door", "edge": [key.x, key.y, key.z],
		"props": {"max_hp": hp, "body_material": material}})
	_room.add_child(door)
	return door


## Lets a cooldown pass.
func _wait(entity: GridEntity) -> void:
	while World.tick < maxf(entity.next_move_tick, entity.next_attack_tick):
		World.step()


func _impact_on(entity: GridEntity) -> int:
	var total := 0
	for hit in _damage:
		if hit["entity"] == entity and hit["cause"] == &"impact":
			total += hit["amount"]
	return total


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
