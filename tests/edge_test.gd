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
	_test_paths_remember_the_terrain()
	_test_steps_filled_by_cell()
	_test_fields_by_door()
	_test_lines_owe_doors()

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


func _test_paths_remember_the_terrain() -> void:
	print("
== find_path remembers what the terrain allows, but not a door's state, nor an old map ==")
	_build()
	var door := _door(DOOR_KEY, 20)
	door.open = false
	# (1, 3) to (2, 2) is a diagonal past the door's edge (east of (1, 2)).
	var closed := World.find_path(Vector2i(1, 3), Vector2i(2, 2))
	door.open = true
	var opened := World.find_path(Vector2i(1, 3), Vector2i(2, 2))
	door.open = false
	var shut_again := World.find_path(Vector2i(1, 3), Vector2i(2, 2))
	_check(closed.size() == 2 and opened == [Vector2i(2, 2)] and shut_again == closed,
			"a diagonal past a door: round while it is shut %s, straight across once open %s, round again shut %s" % [closed, opened, shut_again])
	var across := World.find_path(Vector2i(0, 0), Vector2i(2, 0))
	World.load_terrain(Terrain.parse([
		". .#.",
		"  #  ",
		". .#.",
	]))
	var walled := World.find_path(Vector2i(0, 0), Vector2i(2, 0))
	_check(across.size() == 2 and walled.is_empty(), "a new map: its own walls, not the old map's open floor (%s, then %s)" % [across, walled])


## find_path's memo of steps is filled a cell's eight at a time
## (World._fill_path_steps): each answer as the step alone says it, by the
## edges and _terrain_blocks_step, on every cell of the levels and of a maze
## with ledges, stairs, walls and doors.
func _test_steps_filled_by_cell() -> void:
	print("
== find_path's steps, a cell's eight worked out at once, as each step alone says ==")
	for level_name in ["castle", "sample", "wilds", "test_room"]:
		var terrain: Dictionary = Level.load_level(level_name)["terrain"]
		var seen := _compare_steps(terrain)
		_check(seen["wrong"] == 0 and seen["checked"] > 0, "%s: %d of %d steps differ (%d ask, %d door, %d ledge or stair)" % [
				level_name, seen["wrong"], seen["checked"], seen["ask"], seen["door"], seen["height"]])
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var size := 14
	var rows: Array[String] = []
	for y in size * 2 - 1:
		var row := ""
		for x in size * 2 - 1:
			if x % 2 == 0 and y % 2 == 0:
				row += "." if rng.randf() < 0.9 else " "
			elif x % 2 == 1 and y % 2 == 1:
				row += " "
			else:
				row += [" ", " ", " ", "#", "+"][rng.randi_range(0, 4)]
		rows.append(row)
	var maze := Terrain.parse(rows)
	var heights := {}
	var stairs := {}
	for cell: Vector2i in maze["floor"]:
		heights[cell] = [0, 0, 0, 1, 2][rng.randi_range(0, 4)]
		if rng.randf() < 0.3:
			stairs[cell] = World.DIRECTIONS[rng.randi_range(0, 3)]
	maze["heights"] = heights
	maze["stairs"] = stairs
	var seen := _compare_steps(maze)
	_check(seen["wrong"] == 0 and seen["ask"] > 0 and seen["door"] > 0 and seen["height"] > 0,
			"a maze with ledges and stairs: %d of %d steps differ (%d ask, %d door, %d ledge or stair)" % [
			seen["wrong"], seen["checked"], seen["ask"], seen["door"], seen["height"]])


## Every step of every cell of [param terrain]'s grid: the memo's answer
## (World._path_step) against the step alone, as the memo was once filled.
func _compare_steps(terrain: Dictionary) -> Dictionary:
	World.load_terrain(terrain)
	World._ensure_grid()
	var rect: Rect2i = World._grid_rect
	var out := {"checked": 0, "wrong": 0, "ask": 0, "door": 0, "height": 0}
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var from := Vector2i(x, y)
			for way in 8:
				var direction: Vector2i = World.DIRECTIONS[way]
				if not rect.has_point(from + direction):
					continue  # find_path never asks off the grid.
				var via_x := Vector2i(direction.x, 0)
				var via_y := Vector2i(0, direction.y)
				var expected: int
				if direction.x != 0 and direction.y != 0 and Terrain.Edge.DOOR in [World.edge_kind(from, via_x),
						World.edge_kind(from + via_x, via_y), World.edge_kind(from, via_y), World.edge_kind(from + via_y, via_x)]:
					expected = World.PATH_STEP_ASK
				elif World._terrain_blocks_step(from, direction, true):
					expected = World.PATH_STEP_BLOCKED
				elif World.edge_kind(from, direction) == Terrain.Edge.DOOR:
					expected = World.PATH_STEP_DOOR
				else:
					expected = World.PATH_STEP_OPEN
				out["checked"] += 1
				if expected == World.PATH_STEP_ASK:
					out["ask"] += 1
				elif expected == World.PATH_STEP_DOOR:
					out["door"] += 1
				if World.is_walkable(from) and World.is_walkable(from + direction) 						and World.height_at(from) != World.height_at(from + direction):
					out["height"] += 1
				if World._path_step(from, way) != expected:
					out["wrong"] += 1
					if out["wrong"] <= 3:
						print("  %s way %s: %d, the step alone %d" % [from, direction, World._path_step(from, way), expected])
	return out


func _test_fields_by_door() -> void:
	print("
== a door opening or shutting works out again only the light and heat that reach it, the same as all of it ==")
	_build()
	var terrain := Terrain.parse(ROOM)
	terrain["torches"] = [Vector2i(0, 2), Vector2i(4, 3)]
	terrain["fire"] = [Vector2i(3, 0)]
	terrain["lanterns"] = [Vector2i(0, 0)]
	World.load_terrain(terrain)
	var door := _door(DOOR_KEY, 20)
	var same := true
	var changed := false
	var before: Dictionary = {}
	for i in 6:
		door.open = i % 2 == 0
		World.heat_at(Vector2i(2, 2))
		var whole := Fields.new()
		whole.load(terrain)
		whole._refresh(World)
		same = same and World.fields._heat == whole._heat and World.fields._light == whole._light
		if i == 1:
			before = World.fields._light.duplicate()
		if i == 2:
			changed = World.fields._light != before
	_check(same, "after each of six, every cell's heat and light are exactly as worked out afresh")
	_check(changed, "and the door does change them")
	# A maze of doors and torches: doors opened and shut one or two at a
	# time, at random; a source done again for a door redoes only the
	# cells whose line goes through it (decision 351), and every cell must
	# still come out as a whole recompute has it, the hot cells too.
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var size := 14
	var rows: Array[String] = []
	for y in size * 2 - 1:
		var row := ""
		for x in size * 2 - 1:
			if x % 2 == 0 and y % 2 == 0:
				row += "."
			elif x % 2 == 1 and y % 2 == 1:
				row += " "
			else:
				row += [" ", " ", " ", "#", "+"][rng.randi_range(0, 4)]
		rows.append(row)
	var maze := Terrain.parse(rows)
	maze["torches"] = [Vector2i(2, 2), Vector2i(9, 3), Vector2i(5, 6), Vector2i(1, 10), Vector2i(10, 10), Vector2i(12, 5)]
	maze["fire"] = [Vector2i(7, 8), Vector2i(3, 12)]
	_build()
	World.load_terrain(maze)
	var doors: Array[Door] = []
	for key: Vector3i in maze["edges"]:
		if maze["edges"][key] == Terrain.Edge.DOOR:
			doors.append(_door(key, 20))
	World.heat_at(Vector2i(0, 0))
	var wrong := 0
	for round in 40:
		for flip in rng.randi_range(1, 2):
			var door_now: Door = doors[rng.randi_range(0, doors.size() - 1)]
			door_now.open = not door_now.open
		World.heat_at(Vector2i(0, 0))
		World.fields.hot_set(World, World.HEAT_BURN)
		var afresh := Fields.new()
		afresh.load(maze)
		afresh._refresh(World)
		if World.fields._heat != afresh._heat or World.fields._light != afresh._light 				or World.fields.hot_set(World, World.HEAT_BURN) != afresh.hot_set(World, World.HEAT_BURN):
			wrong += 1
	_check(doors.size() > 30 and wrong == 0, "a maze of %d doors, 40 rounds of one or two flipped: %d rounds differ from a whole recompute" % [doors.size(), wrong])


func _test_lines_owe_doors() -> void:
	print("
== what a light's line owes to doors, worked out once, sees as walking the line does ==")
	var castle: Dictionary = Level.load_level("castle")["terrain"]
	var seen := _compare_lines(castle)
	_check(seen["doors"] > 0 and seen["through"] > 0, "the castle: %d doors, %d lines through them" % [seen["doors"], seen["through"]])
	_check(seen["wrong"] == 0, "every cell in reach of every light, doors shut, open and mixed: %d of %d differ" % [seen["wrong"], seen["checked"]])
	# A maze: every edge open, a wall or a door, at random, and torches.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var size := 12
	var rows: Array[String] = []
	for y in size * 2 - 1:
		var row := ""
		for x in size * 2 - 1:
			if x % 2 == 0 and y % 2 == 0:
				row += "."
			elif x % 2 == 1 and y % 2 == 1:
				row += " "
			else:
				row += [" ", " ", "#", "+"][rng.randi_range(0, 3)]
		rows.append(row)
	var maze := Terrain.parse(rows)
	maze["torches"] = [Vector2i(2, 2), Vector2i(9, 3), Vector2i(5, 6), Vector2i(1, 10), Vector2i(10, 10)]
	seen = _compare_lines(maze)
	_check(seen["through"] > 20 and seen["ask"] > 0, "a maze: %d doors, %d lines through them, %d past one on a diagonal" % [
			seen["doors"], seen["through"], seen["ask"]])
	_check(seen["wrong"] == 0, "the same there: %d of %d differ" % [seen["wrong"], seen["checked"]])


## [param terrain] loaded with a node on each door, its doors all shut, all
## open, then half at random: for every fixed light and every cell in its
## reach, whether the cached lines (Fields._lines_of) see it against
## whether walking the line does.
func _compare_lines(terrain: Dictionary) -> Dictionary:
	_build()
	World.load_terrain(terrain)
	var doors: Array[Door] = []
	for key: Vector3i in terrain["edges"]:
		if terrain["edges"][key] == Terrain.Edge.DOOR:
			doors.append(_door(key, 20))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var fields := World.fields
	var sources := fields._sources()
	var out := {"doors": doors.size(), "checked": 0, "wrong": 0, "through": 0, "ask": 0}
	for round in 3:
		for door in doors:
			door.open = round == 1 or (round == 2 and rng.randf() < 0.5)
		for i in sources.size():
			var source: Vector2i = sources[i][0]
			var reach: int = sources[i][1]["reach"]
			var lines: Dictionary = fields._lines_of(World, i, source, reach)
			var cached := {}
			for k in lines["cells"].size():
				var owed: Variant = lines["doors"][k]
				if round == 0 and owed is int:
					out["ask"] += 1
				elif round == 0 and not owed.is_empty():
					out["through"] += 1
				if owed is int and World.has_clear_line(source, lines["cells"][k]) \
						or owed is Array and Fields._all_open(World, owed):
					cached[lines["cells"][k]] = true
			for cell in Fields._reachable(source, reach):
				var walked := cell == source or World.has_clear_line(source, cell)
				out["checked"] += 1
				if walked != cached.has(cell):
					out["wrong"] += 1
	return out


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
