extends Node
## The free body (decision 688; Jeff's pick 3 of free-movement.md): with
## World.free_walk on, a player's body has a centre of its own
## (GridEntity.free_pos) and moves any way at once, a circle of
## World.FREE_RADIUS against cell edges and others' cells, holding the cell
## its centre is in. Small rooms in the double-resolution map format, World
## stepped by hand. A bare player walks 2.5 ticks a cell: 0.4 cells a tick.

const Walk := preload("res://tests/walk.gd")

## Open ground, 9 x 5.
const OPEN: Array[String] = [
	". . . . . . . . .",
	"                 ",
	". . . . . . . . .",
	"                 ",
	". . . . . . . . .",
	"                 ",
	". . . . . . . . .",
	"                 ",
	". . . . . . . . .",
]
## A wall along the south edges of (1, 1) to (3, 1); a door on the east
## edge of (2, 3).
const WALLED: Array[String] = [
	". . . . .",
	"         ",
	". . . . .",
	"  # # #  ",
	". . . . .",
	"         ",
	". . .+. .",
]
const DOOR_KEY := Vector3i(2, 3, Terrain.EAST)
## Two walls meeting at the corner between (1, 1), (2, 1), (1, 2) and
## (2, 2): the south edge of (2, 1) and the east edge of (1, 2). A
## diagonal from (1, 1) to (2, 2) would cut it.
const CORNER: Array[String] = [
	". . . .",
	"       ",
	". . . .",
	"    #  ",
	". .#. .",
	"       ",
	". . . .",
]

var _failures := 0
var _room: Node2D
var _bumps := 0


func _ready() -> void:
	World.set_process(false)
	World.entity_bumped.connect(func(_mover: GridEntity, _occupant: GridEntity, _direction: Vector2i) -> void: _bumps += 1)

	_test_flag_off()
	_test_speed()
	_test_claim()
	_test_bank()
	_test_others()
	_test_own_companion()
	_test_crate()
	_test_wall_slide()
	_test_corner()
	_test_door()
	_test_held()
	_test_snap()
	_test_walk_helper()
	World.free_walk = false

	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_flag_off() -> void:
	print("\n== the flag off: a player walks the grid's steps, free_input does nothing ==")
	var player := _build(OPEN, Vector2i(1, 2))
	World.free_walk = false
	_check(not World.free_body(player), "a player is no free body with free_walk off")
	World.free_input(player, Vector2(1, 0), 1.0)
	_check(player.free_inputs.is_empty(), "free_input queues nothing")
	_check(World.try_move(player, Vector2i(1, 0)) and player.tile == Vector2i(2, 2) and player.free_pos == Vector2(2, 2),
			"a step east: at (2, 2), its centre with it (%s)" % player.free_pos)


func _test_speed() -> void:
	print("\n== the walk's speed: 0.4 cells a tick any way, a diagonal no slower than a straight ==")
	var player := _build(OPEN, Vector2i(1, 2))
	_hold(player, Vector2(1, 0), 10)
	_check(player.free_pos.is_equal_approx(Vector2(5, 2)) and player.tile == Vector2i(5, 2),
			"10 ticks east from (1, 2): 4 cells, at (5, 2) (%s, %s)" % [player.free_pos, player.tile])
	_check(player.facing == Vector2i(1, 0) and player.free_way.is_equal_approx(Vector2(0.4, 0)) and player.last_step_tick == World.tick,
			"facing east, 0.4 cells a tick, stepped this tick (%s, %s)" % [player.facing, player.free_way])
	player = _build(OPEN, Vector2i(1, 0))
	_hold(player, Vector2(1, 1).normalized(), 10)
	var gone := player.free_pos.distance_to(Vector2(1, 0))
	_check(is_equal_approx(gone, 4.0) and player.facing == Vector2i(1, 1),
			"10 ticks south-east: 4 cells too (%.3f; the grid's diagonal 3.75 ticks a step went 2.67 x 1.41 = 3.77)" % gone)
	player = _build(OPEN, Vector2i(1, 2))
	_hold(player, Vector2(0.5, 0), 10)
	_check(player.free_pos.is_equal_approx(Vector2(3, 2)), "a half intent walks at half speed: 2 cells (%s)" % player.free_pos)


func _test_claim() -> void:
	print("\n== the cell it holds: its centre's, once 0.1 past the edge ==")
	var player := _build(OPEN, Vector2i(1, 2))
	var moves: Array[Vector2i] = []
	var heard := func(entity: GridEntity, _from: Vector2i, to: Vector2i) -> void:
		if entity == player:
			moves.append(to)
	World.entity_moved.connect(heard)
	player.free_pos = Vector2(1.55, 2)
	World._free_claim(player, 2.5)
	_check(player.tile == Vector2i(1, 2) and moves.is_empty(), "0.55 east of its centre: still (1, 2)")
	player.free_pos = Vector2(1.65, 2)
	World._free_claim(player, 2.5)
	_check(player.tile == Vector2i(2, 2) and moves == [Vector2i(2, 2)] and player.free_pos == Vector2(1.65, 2),
			"0.65 east: (2, 2) held, entity_moved told, its centre kept (%s)" % player.free_pos)
	player.free_pos = Vector2(1.45, 2)
	World._free_claim(player, 2.5)
	_check(player.tile == Vector2i(2, 2), "back 0.55 west of (2, 2)'s centre: still (2, 2), no flicker on the border")
	World.entity_moved.disconnect(heard)
	_check(World._occupancy.get(Vector2i(2, 2)) == player and not World._occupancy.has(Vector2i(1, 2)), "one cell held, the one it left free")


func _test_bank() -> void:
	print("\n== more commands than time: no faster than the bank, 3 ticks at most ==")
	var player := _build(OPEN, Vector2i(1, 2))
	for i in 10:
		World.step()
	for i in 30:
		World.free_input(player, Vector2(1, 0), 1.0)
	World.step()
	_check(is_equal_approx(player.free_pos.x, 2.2), "after 10 idle ticks, 30 commands of a second: 3 ticks' walk, 1.2 cells (%.3f)" % player.free_pos.x)
	World.step()
	_check(is_equal_approx(player.free_pos.x, 2.6), "the next tick: one tick's, 0.4 (%.3f)" % player.free_pos.x)


func _test_others() -> void:
	print("\n== a monster's cell is solid: the body stops a radius off it ==")
	var player := _build(OPEN, Vector2i(1, 2))
	var dummy := _spawn("res://sim/monster.gd", "Dummy", Vector2i(4, 2))
	_hold(player, Vector2(1, 0), 10)
	_check(is_equal_approx(player.free_pos.x, 3.2) and player.tile == Vector2i(3, 2) and dummy.tile == Vector2i(4, 2),
			"east into the dummy at (4, 2): stopped at 3.2, holding (3, 2) (%s)" % player.free_pos)
	_hold(player, Vector2(1, 1).normalized(), 5)
	_check(player.free_pos.y > 3.0 and player.free_pos.x > 3.2,
			"south-east along it: it slides past the dummy's corner (%s)" % player.free_pos)


func _test_own_companion() -> void:
	print("\n== its own companion it passes through; it waits on her cell, bumping her ==")
	var player := _build(OPEN, Vector2i(1, 2))
	var pet := EntityFactory.build({"script": "res://sim/companion.gd", "shape": "capsule", "name": "Garrow", "props": {"max_hp": 10}}) as Companion
	pet.acts = false
	_room.add_child(pet)
	World.spawn(pet, Vector2i(3, 2))
	pet.keeper = player
	_bumps = 0
	var held: Array[Vector2i] = []
	for i in 10:
		World.free_input(player, Vector2(1, 0), World.TICK_DT)
		World.step()
		held.append(player.tile)
	_check(player.free_pos.is_equal_approx(Vector2(5, 2)) and player.tile == Vector2i(5, 2) and pet.tile == Vector2i(3, 2),
			"10 ticks east through her at (3, 2): at (5, 2), she where she was (%s)" % player.free_pos)
	_check(Vector2i(3, 2) not in held and _bumps >= 1, "her cell never his; she was bumped %d times (%s)" % [_bumps, held])
	_check(not World.swap_places(player, pet, 2.5), "no swap for a free body (679 retired for it)")


func _test_crate() -> void:
	print("\n== a crate pressed into shifts a cell at the walk's pace ==")
	var player := _build(OPEN, Vector2i(1, 2))
	var crate := EntityFactory.build({"script": "res://sim/pushable.gd", "shape": "sphere", "name": "Crate", "props": {"mass": 20.0}})
	_room.add_child(crate)
	World.spawn(crate, Vector2i(3, 2))
	_hold(player, Vector2(1, 0), 10)
	_check(crate.tile.x >= 5 and player.tile.x == crate.tile.x - 1, "10 ticks east into a 20 kg crate: it went to %s, he behind it at %s" % [crate.tile, player.tile])


func _test_wall_slide() -> void:
	print("\n== a wall along its way: it slides along it ==")
	var player := _build(WALLED, Vector2i(1, 1))
	_hold(player, Vector2(1, 1).normalized(), 6)
	_check(is_equal_approx(player.free_pos.y, 1.2) and player.free_pos.x > 2.3 and player.tile.y == 1,
			"south-east into the wall south of (1..3, 1): held 0.3 off it at y 1.2, sliding east to x %.2f" % player.free_pos.x)


func _test_corner() -> void:
	print("\n== two walls meeting at a corner: no diagonal through it ==")
	var player := _build(CORNER, Vector2i(1, 1))
	_hold(player, Vector2(1, 1).normalized(), 20)
	_check(player.tile == Vector2i(1, 1) and player.free_pos.distance_to(Vector2(1.5, 1.5)) >= World.FREE_RADIUS - 0.001,
			"20 ticks south-east at the corner: still (1, 1), a radius off it (%s)" % player.free_pos)


func _test_door() -> void:
	print("\n== a closed door pressed into opens, and it walks through ==")
	var player := _build(WALLED, Vector2i(2, 3))
	var door := Door.build({"script": "res://sim/door.gd", "name": "Door", "edge": [DOOR_KEY.x, DOOR_KEY.y, DOOR_KEY.z], "props": {"max_hp": 20}})
	_room.add_child(door)
	_check(not door.open, "the door starts closed")
	_hold(player, Vector2(1, 0), 6)
	_check(door.open and player.tile == Vector2i(4, 3), "6 ticks east: open, and he at %s" % player.tile)


func _test_held() -> void:
	print("\n== halted, or a bow drawn: the intent is not taken ==")
	var player := _build(OPEN, Vector2i(1, 2))
	World.halt(player, World.tick + 5)
	_hold(player, Vector2(1, 0), 4)
	_check(player.free_pos == Vector2(1, 2) and player.free_way == Vector2.ZERO, "halted till 5 ticks on: the 4 before, not moved")
	_hold(player, Vector2(1, 0), 1)
	_check(is_equal_approx(player.free_pos.x, 1.4), "on the fifth, it walks (%.2f)" % player.free_pos.x)
	_hold(player, Vector2(1, 0), 4)
	_check(is_equal_approx(player.free_pos.x, 3.0), "then 4 ticks more: at 3 (%.2f)" % player.free_pos.x)
	player.raised = "draw"
	_hold(player, Vector2(1, 0), 5)
	_check(is_equal_approx(player.free_pos.x, 3.0), "a bow drawn: stands firm")
	player.raised = ""
	World.free_input(player, Vector2(1, 0), 1.0)
	World.stand_firm(player)
	World.step()
	_check(is_equal_approx(player.free_pos.x, 3.0) and player.free_inputs.is_empty(), "stand_firm: its waiting commands dropped")
	World.free_input(player, Vector2(0.03, 0), World.TICK_DT)
	World.step()
	_check(player.last_step_tick == World.tick and player.tile == Vector2i(3, 2),
			"inching 0.012 of a cell, no edge crossed: it has stepped (a spear braced only standing still)")


func _test_snap() -> void:
	print("\n== moved some other way (a push, a lunge, a relocate): its centre goes to the cell's ==")
	var player := _build(OPEN, Vector2i(1, 2))
	_hold(player, Vector2(0.3, 0.2), 1)
	_check(player.free_pos != Vector2(1, 2), "off its centre (%s)" % player.free_pos)
	World._relocate(player, Vector2i(4, 3))
	_check(player.free_pos == Vector2(4, 3), "relocated to (4, 3): its centre there (%s)" % player.free_pos)
	_hold(player, Vector2(-0.2, 0.3), 1)
	var dummy := _spawn("res://sim/monster.gd", "Dummy", Vector2i(3, 3))
	var slid := World._push(dummy, player, Vector2(1, 0), 2.0)
	_check(not slid.is_empty() and player.tile.x > 4 and player.free_pos == Vector2(player.tile),
			"knocked east a speed of 2 from off its centre: to %s, snapped onto it (%s; impulses later, 688 amended)" % [player.tile, player.free_pos])


func _test_walk_helper() -> void:
	print("\n== the walk-to test helper, either way ==")
	for free: bool in [false, true]:
		var player := _build(WALLED, Vector2i(0, 0))
		World.free_walk = free
		var started := World.tick
		_check(Walk.to(player, Vector2i(2, 2)) and Walk.arrived(player, Vector2i(2, 2)),
				"%s: from (0, 0) round the wall to (2, 2) in %d ticks" % ["free" if free else "grid", World.tick - started])


## A room from [param rows] with a player at [param at], free_walk on.
func _build(rows: Array[String], at: Vector2i) -> Player:
	World.reset()
	World.free_walk = true
	if _room != null:
		_room.free()
	_room = Node2D.new()
	add_child(_room)
	World.load_terrain(Terrain.parse(rows))
	return _spawn("res://sim/player.gd", "Player1", at) as Player


func _spawn(script: String, entity_name: String, at: Vector2i) -> GridEntity:
	var entity := EntityFactory.build({"script": script, "shape": "capsule", "name": entity_name, "tile": at})
	if entity is Monster:
		entity.sight_range = 0
		entity.acts = false
	_room.add_child(entity)
	World.spawn(entity, at)
	return entity


## [param player] holds [param intent] for [param ticks] ticks, a command a tick.
func _hold(player: Player, intent: Vector2, ticks: int) -> void:
	for i in ticks:
		World.free_input(player, intent, World.TICK_DT)
		World.step()


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
