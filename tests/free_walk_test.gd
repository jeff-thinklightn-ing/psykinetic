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
## Walls on the east and south edges of (1, 1), meeting at its corner: a
## pocket heading south-east.
const POCKET: Array[String] = [
	". . . .",
	"       ",
	". .#. .",
	"  #    ",
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
	_test_kick()
	_test_kick_wall()
	_test_kick_glance()
	_test_kick_body()
	_test_kick_fall()
	_test_press_niche()
	_test_press_edge()
	_test_held_door()
	_test_link_cells()
	_test_glide()
	_test_replay_matches()
	_test_acks()
	_test_walk_helper()
	_test_free_dodge()
	_test_free_chase()
	_test_free_kite()
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
	World._relocate(player, Vector2i(1, 2))
	var paces: Array[float] = []
	for i in 10:
		var was := player.free_pos.x
		World.free_input(player, Vector2(1, 0), World.TICK_DT)
		World.step()
		paces.append(snappedf(player.free_pos.x - was, 0.001))
	_check(paces.all(func(pace: float) -> bool: return is_equal_approx(pace, 0.4)),
			"through her again: 0.4 a tick every tick, no slowing on her, only the claim waits (%s)" % [paces])
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
	print("\n== two walls meeting at a corner: no diagonal through it, and no stall on it ==")
	var player := _build(CORNER, Vector2i(1, 1))
	var held: Array[Vector2i] = []
	var nearest := INF
	for i in 20:
		World.free_input(player, Vector2(1, 1).normalized(), World.TICK_DT)
		World.step()
		held.append(player.tile)
		nearest = minf(nearest, player.free_pos.distance_to(Vector2(1.5, 1.5)))
	_check(Vector2i(2, 2) not in held and nearest >= World.FREE_RADIUS - 0.001,
			"20 ticks south-east at it: never (2, 2) through it, never nearer than a radius (%.3f)" % nearest)
	_check(player.tile.x >= 3,
			"head on at the corner it slides off east (x first on a tie, 688 amended), not stalled: at %s (%s)" % [player.tile, player.free_pos])
	player = _build(POCKET, Vector2i(1, 1))
	_hold(player, Vector2(1, 1).normalized(), 10)
	_check(player.tile == Vector2i(1, 1) and player.free_pos.is_equal_approx(Vector2(1.2, 1.2)),
			"into a pocket, walls east and south of (1, 1): stopped a radius off both (%s)" % player.free_pos)


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

## A push on a free body (688 amended (2)): decided at once, its centre
## traced from where it is; the cell taken then, the slide shown over the
## ticks after, what it sends meanwhile dropped and acknowledged.
func _test_kick() -> void:
	print("\n== a push on a free body: decided at once, slid from its centre, shown over the ticks after ==")
	var player := _build(OPEN, Vector2i(3, 3))
	_hold(player, Vector2(1, 0.3), 2)
	var from := player.free_pos
	var dummy := _spawn("res://sim/monster.gd", "Dummy", Vector2i(1, 1))
	var slid := World._push(dummy, player, Vector2(1, 0), 2.0)
	var reach := 2.0 * World.slide_per_speed
	var end := Vector2(from.x + reach, from.y)
	_check(slid.size() == 1 and player.tile == Vector2i(roundi(end.x), roundi(end.y)) and slid[0]["cells"] == player.tile.x - 4,
			"a speed of 2 east from %s: its cell %s at once (%d cells), the centre %.2f on" % [from, player.tile, slid[0]["cells"], reach])
	_check(player.free_pos == from and World.free_held(player), "the centre not yet moved, the body held while it is shown")
	World.free_input(player, Vector2(-1, 0), World.TICK_DT, 7)
	var ticks := World.push_slide_ticks(slid[0]["cells"])
	var last := from.x
	var slowing := true
	var step_was := INF
	for i in ticks:
		World.step()
		var step := player.free_pos.x - last
		slowing = slowing and step <= step_was + 0.0001 and step >= 0.0
		step_was = step
		last = player.free_pos.x
	_check(player.free_pos.distance_to(end) < 0.001 and slowing,
			"after %d ticks: at %s (%s), each tick's slide shorter" % [ticks, player.free_pos, end])
	_check(player.free_acked == 7 and player.free_inputs.is_empty(), "the command sent while it slid: dropped, acknowledged (7)")
	_check(not World.free_held(player) or World.is_stunned(player), "the slide shown: held only by its stagger")
	while World.is_stunned(player):
		World.step()
	_hold(player, Vector2(-1, 0), 3)
	_check(player.free_pos.x < end.x - 1.0, "steered again after (%s)" % player.free_pos)
	# The grid's cells, from a cell's centre: the same as a free body's.
	var cells := []
	for free in [false, true]:
		var body := _build(OPEN, Vector2i(1, 2))
		World.free_walk = free
		var pusher := _spawn("res://sim/monster.gd", "Dummy", Vector2i(0, 0))
		World._push(pusher, body, Vector2(1, 0), 2.0)
		cells.append(body.tile)
	World.free_walk = true
	_check(cells[0] == cells[1], "from a cell's centre, east at 2: the grid's %s, the free body's %s" % cells)


func _test_kick_wall() -> void:
	print("\n== a free body pushed head on into a wall: stopped a radius off it, hurt by the speed it had left ==")
	var player := _build(WALLED, Vector2i(2, 0))
	player.hp = 100
	var dummy := _spawn("res://sim/monster.gd", "Dummy", Vector2i(4, 0))
	var slid := World._push(dummy, player, Vector2(0, 1), 2.0)
	var travelled := 1.5 - World.FREE_RADIUS
	var left := 2.0 - travelled / World.slide_per_speed
	var hurt := roundi(World.impact_per_energy * 0.5 * World.pushed_mass(player) * left * left)
	_check(player.tile == Vector2i(2, 1) and slid[0]["stopped_by"] == "wall" and slid[0]["impact"] == hurt,
			"south at 2 from (2, 0): stopped in (2, 1) by the wall, %d hurt (%d: %.2f left)" % [slid[0]["impact"], hurt, left])
	while not player.free_kick_path.is_empty():
		World.step()
	_check(absf(player.free_pos.y - travelled) < 0.001 and is_equal_approx(player.free_pos.x, 2.0),
			"shown to %s, a radius short of the wall" % player.free_pos)


func _test_kick_glance() -> void:
	print("\n== a free body pushed at a slant into a wall slides along it ==")
	var player := _build(WALLED, Vector2i(0, 1))
	player.hp = 100
	var dummy := _spawn("res://sim/monster.gd", "Dummy", Vector2i(4, 3))
	var slid := World._push(dummy, player, Vector2(1, 0.4), 2.0)
	var path := player.free_kick_path
	var lowest := 0.0
	for at in path:
		lowest = maxf(lowest, at.y)
	_check(player.tile.y == 1 and player.tile.x >= 2 and lowest <= 1.5 - World.FREE_RADIUS + 0.001,
			"east-south-east at 2 from (0, 1): slid along the wall to %s, never past it (lowest %.3f)" % [player.tile, lowest])
	_check(slid[0]["impact"] > 0, "the speed it lost into the wall hurts (%d)" % slid[0]["impact"])
	var head_on := _build(WALLED, Vector2i(2, 0))
	dummy = _spawn("res://sim/monster.gd", "Dummy", Vector2i(4, 3))
	World._push(dummy, head_on, Vector2(0.2, 1), 2.0)
	_check(head_on.tile == Vector2i(2, 1), "nearly head on (11 degrees): stopped, not slid (%s)" % head_on.tile)


func _test_kick_body() -> void:
	print("\n== a free body pushed into another hands its speed on ==")
	var player := _build(OPEN, Vector2i(2, 2))
	var dummy := _spawn("res://sim/monster.gd", "Dummy", Vector2i(5, 2))
	dummy.hp = 100
	var pusher := _spawn("res://sim/monster.gd", "Pusher", Vector2i(0, 0))
	var slid := World._push(pusher, player, Vector2(1, 0), 3.0)
	var travelled := 2.5 - World.FREE_RADIUS
	var left := 3.0 - travelled / World.slide_per_speed
	var m1 := World.pushed_mass(player)
	var given := (1.0 + World.restitution) * m1 * left / (m1 + World.pushed_mass(dummy))
	_check(slid.size() == 2 and slid[0]["stopped_by"] == dummy.name and player.tile == Vector2i(4, 2),
			"east at 3 from (2, 2): stopped in (4, 2) by the dummy (%s)" % [slid[0]["stopped_by"]])
	_check(slid[1]["body"] == dummy and dummy.tile.x == 5 + floori(given * World.slide_per_speed + 0.001),
			"the dummy goes on at %.2f: to %s" % [given, dummy.tile])
	var pip := _build(OPEN, Vector2i(2, 2))
	var her := _spawn("res://sim/companion.gd", "Pip", Vector2i(4, 2)) as Companion
	her.keeper = pip
	pusher = _spawn("res://sim/monster.gd", "Pusher", Vector2i(0, 0))
	World._push(pusher, pip, Vector2(1, 0), 2.0)
	_check(pip.tile == Vector2i(3, 2), "its own companion it walks through, but a push meets her (%s)" % pip.tile)


func _test_kick_fall() -> void:
	print("\n== a free body pushed off a ledge falls ==")
	World.reset()
	World.free_walk = true
	if _room != null:
		_room.free()
	_room = Node2D.new()
	add_child(_room)
	var terrain := Terrain.parse(OPEN)
	var heights := {}
	for x in 4:
		for y in 5:
			heights[Vector2i(x, y)] = 1
	terrain["heights"] = heights
	World.load_terrain(terrain)
	var player := _spawn("res://sim/player.gd", "Player1", Vector2i(2, 2)) as Player
	player.hp = 100
	var dummy := _spawn("res://sim/monster.gd", "Dummy", Vector2i(0, 0))
	var slid := World._push(dummy, player, Vector2(1, 0), 2.0)
	_check(player.tile == Vector2i(4, 2) and str(slid[0]["stopped_by"]).begins_with("a fall"),
			"east at 2 from (2, 2) on a ledge: off it into (4, 2), %s" % slid[0]["stopped_by"])


## A free body pressing an edge it cannot cross (688 amended (4); Jeff:
## the barrow's hidden niche no longer opened): FREE_PRESS_TICKS against it
## and it is a step refused there, as a grid walk's.
func _test_press_niche() -> void:
	print("
== pressing a burial niche's edge: the niche pressed, as a refused step presses it ==")
	var player := _build(WALLED, Vector2i(2, 1))
	var key := Terrain.edge_key(Vector2i(2, 1), Vector2i(0, 1))
	World.niche_edges[key] = "hidden"
	var pressed: Array = []
	var on_press := func(entity: GridEntity, edge: Vector3i) -> void: pressed.append([entity, edge])
	World.niche_pressed.connect(on_press)
	_hold(player, Vector2(0, 1), World.FREE_PRESS_TICKS - 1)
	_check(pressed.is_empty(), "%d tick into the wall: not yet pressed (at %s)" % [World.FREE_PRESS_TICKS - 1, player.free_pos])
	_hold(player, Vector2(0, 1), 1)
	_check(pressed.size() == 1 and pressed[0][0] == player and pressed[0][1] == key,
			"%d ticks against it: the niche's edge pressed once (%s)" % [World.FREE_PRESS_TICKS, pressed])
	_hold(player, Vector2(0, 1), World.FREE_PRESS_TICKS)
	_check(pressed.size() == 2, "held on: pressed again, as a held key's refused steps come again (%d)" % pressed.size())
	pressed.clear()
	_hold(player, Vector2(0.3, 1).normalized(), World.FREE_PRESS_TICKS)
	_check(pressed.size() == 1, "leaning in a little off straight (17 degrees): pressed")
	pressed.clear()
	player = _build(WALLED, Vector2i(1, 1))
	World.niche_edges[Terrain.edge_key(Vector2i(2, 1), Vector2i(0, 1))] = "hidden"
	World.niche_edges[Terrain.edge_key(Vector2i(1, 1), Vector2i(0, 1))] = "hidden"
	_hold(player, Vector2(0, 1), 2)
	pressed.clear()
	_hold(player, Vector2(1, 0.3).normalized(), 4)
	_check(pressed.is_empty() and player.tile.x >= 2, "brushing east along the wall over the niches: nothing pressed (at %s)" % player.free_pos)
	World.niche_pressed.disconnect(on_press)
	var grid := _build(WALLED, Vector2i(2, 1))
	World.free_walk = false
	World.niche_edges[key] = "hidden"
	World.niche_pressed.connect(on_press)
	World.try_move(grid, Vector2i(0, 1))
	_check(pressed.size() == 1 and pressed[0][1] == key, "on the grid a refused step presses it as ever")
	World.niche_pressed.disconnect(on_press)
	World.free_walk = true


func _test_press_edge() -> void:
	print("
== pressing the map's edge: walked off, as a refused step there is (a neighbour's way) ==")
	var player := _build(OPEN, Vector2i(0, 2))
	var off: Array = []
	var on_off := func(entity: GridEntity, direction: Vector2i) -> void: off.append([entity, direction])
	World.walked_off.connect(on_off)
	_hold(player, Vector2(-1, 0), World.FREE_PRESS_TICKS + 1)
	_check(off.size() == 1 and off[0][1] == Vector2i(-1, 0), "west against the map's edge: walked off west (%s)" % [off])
	off.clear()
	_hold(player, Vector2(0, 1), 3)
	_check(off.is_empty(), "walking south along it: nothing")
	World.walked_off.disconnect(on_off)


func _test_held_door() -> void:
	print("
== a door held shut (the Hall's seal) stops a free body as it stops a step ==")
	var player := _build(WALLED, Vector2i(2, 3))
	var door := Door.build({"script": "res://sim/door.gd", "name": "Door", "edge": [DOOR_KEY.x, DOOR_KEY.y, DOOR_KEY.z], "props": {"max_hp": 20}})
	_room.add_child(door)
	World.hold_door(door, true, "ossuary_dead")
	_hold(player, Vector2(1, 0), 6)
	_check(not door.open and player.tile == Vector2i(2, 3) and player.free_pos.x <= 2.2 + 0.001,
			"pressed east into it 6 ticks: shut, the body a radius off it (%s)" % player.free_pos)
	World.hold_door(door, false, "ossuary_dead")
	_hold(player, Vector2(1, 0), 6)
	_check(player.tile.x >= 3, "let go of: it opens to the press as any door (%s)" % player.tile)


func _test_link_cells() -> void:
	print("
== a link's cell: taken by moving onto it (entity_moved), and bumped when someone stands there ==")
	var player := _build(OPEN, Vector2i(2, 2))
	World.fields.link_cells[Vector2i(4, 2)] = true
	var moved_to: Array = []
	var on_moved := func(entity: GridEntity, _from: Vector2i, to: Vector2i) -> void:
		if entity == player:
			moved_to.append(to)
	World.entity_moved.connect(on_moved)
	_hold(player, Vector2(1, 0), 6)
	_check(moved_to.has(Vector2i(4, 2)), "walked east onto it: moved there, as Main._take_link hears (%s)" % [moved_to])
	World.entity_moved.disconnect(on_moved)
	player = _build(OPEN, Vector2i(2, 2))
	World.fields.link_cells[Vector2i(4, 2)] = true
	_spawn("res://sim/player.gd", "Player2", Vector2i(4, 2))  # (No monster steps onto a link: 571.)
	var bumped: Array = []
	var on_bump := func(entity: GridEntity, at: Vector2i) -> void: bumped.append(at)
	World.link_bumped.connect(on_bump)
	_hold(player, Vector2(1, 0), 6)
	_check(bumped.has(Vector2i(4, 2)), "someone on it: pressed into, the link bumped all the same (571; %s)" % [bumped])
	World.link_bumped.disconnect(on_bump)


func _test_glide() -> void:
	print("\n== free_glide: the same move, touching nothing (688 amended; a client's replay) ==")
	var player := _build(WALLED, Vector2i(1, 1))
	var glided: Array = World.free_glide(player, player.free_pos, Vector2(1, 1).normalized(), 6.0)
	_check(player.free_pos == Vector2(1, 1) and player.tile == Vector2i(1, 1) and player.free_way == Vector2.ZERO,
			"6 ticks south-east glided from (1, 1): the body where it was")
	_hold(player, Vector2(1, 1).normalized(), 6)
	_check((glided[0] as Vector2).distance_to(player.free_pos) < 0.001 and (glided[1] as Vector2).is_equal_approx(player.free_way),
			"the server's own 6 ticks end where the glide said: %s, %s" % [glided[0], player.free_pos])
	player = _build(WALLED, Vector2i(2, 3))
	var door := Door.build({"script": "res://sim/door.gd", "name": "Door", "edge": [DOOR_KEY.x, DOOR_KEY.y, DOOR_KEY.z], "props": {"max_hp": 20}})
	_room.add_child(door)
	glided = World.free_glide(player, player.free_pos, Vector2(1, 0), 6.0)
	_check(not door.open and is_equal_approx((glided[0] as Vector2).x, 2.2),
			"glided into the closed door: it stays shut, the glide stops a radius off it (%s)" % glided[0])
	var crate := EntityFactory.build({"script": "res://sim/pushable.gd", "shape": "sphere", "name": "Crate", "props": {"mass": 20.0}})
	_room.add_child(crate)
	World.spawn(crate, Vector2i(2, 2))
	glided = World.free_glide(player, player.free_pos, Vector2(0, -1), 6.0)
	_check(crate.tile == Vector2i(2, 2) and is_equal_approx((glided[0] as Vector2).y, 2.8),
			"glided into a crate: not shifted, stopped a radius off it (%s)" % glided[0])
	_check(World.free_cell(player, Vector2(2.55, 3)) == Vector2i(2, 3) and World.free_cell(player, Vector2(2.65, 3)) == Vector2i(3, 3)
			and World.free_cell(player, Vector2(1.4, 2.35)) == Vector2i(1, 2) and player.tile == Vector2i(2, 3),
			"free_cell: (2, 3) at 0.55 east, (3, 3) at 0.65, (1, 2) diagonally past both, nothing claimed")


## A client's replay (ui's 689): the commands glided one after another from
## where the body began, each whole, against the server's own turns, which
## split them by its bank, a claim between substeps.
func _test_replay_matches() -> void:
	print("\n== a replay of its commands ends where the server's body does ==")
	for room: Array in [[OPEN, Vector2i(1, 2)], [WALLED, Vector2i(1, 1)], [CORNER, Vector2i(1, 1)], [OPEN, Vector2i(0, 0), "fords"]]:
		var player := _build(room[0], room[1])
		var fords := room.size() > 2
		if fords:
			# Mixed ground (688 amended (3)): fords on every other column, so
			# a command's speed changes cell to cell, wherever the bank splits it.
			for x in [1, 3, 5, 7]:
				for y in 5:
					World._fords[Vector2i(x, y)] = true
		elif room[0] == OPEN:
			_spawn("res://sim/monster.gd", "Dummy", Vector2i(4, 3))
		var start := player.free_pos
		var start_cell := player.tile
		var room_name: String = "across fords" if fords else "open with a dummy" if room[0] == OPEN else "walled" if room[0] == WALLED else "at the corner"
		var sent: Array[Array] = []
		var worst := 0.0
		var compared := 0
		var cells_match := true
		for i in 40:
			var angle := 0.6 + 0.9 * sin(i * 0.37)
			var intent := Vector2(cos(angle), sin(angle))
			var seconds := 0.025 + 0.02 * float(i % 3)
			sent.append([intent, seconds])
			World.free_input(player, intent, seconds, i)
			if i % 3 != 2:
				continue
			# A tick at a time till the bank has had them all, the split
			# falling wherever it does.
			for _tick in 4:
				World.step()
				if not player.free_inputs.is_empty():
					continue
				var replay := start
				var held := start_cell
				for command: Array in sent:
					var glided: Array = World.free_glide(player, replay, command[0], command[1] * World.TICK_RATE, held)
					replay = glided[0]
					held = glided[2]
				cells_match = cells_match and held == player.tile
				worst = maxf(worst, replay.distance_to(player.free_pos))
				compared += 1
				break
		# Open ground and fords exactly; by walls a hundredth or so, a circle
		# rounding a corner going a little otherwise as its substeps fall.
		var allowed := 0.02 if room[0] == WALLED or room[0] == CORNER else 0.001
		_check(compared >= 10 and worst < allowed, "%s: 40 commands of 25 to 65 ms turning: the replay at most %.4f off the server (%d times)" % [
				room_name, worst, compared])
		_check(cells_match, "%s: the replay holds the server's cell each time" % room_name)


func _test_acks() -> void:
	print("\n== the server's ack: each command done with, applied or dropped (688 amended) ==")
	var player := _build(OPEN, Vector2i(1, 2))
	_check(player.free_acked == -1 and player.free_used == 0.0, "none yet: -1, 0")
	for seq in [1, 2]:
		World.free_input(player, Vector2(1, 0), World.TICK_DT * 0.5, seq)
	World.free_input(player, Vector2(1, 0), World.TICK_DT * 2.5, 3)
	World.step()
	_check(player.free_acked == 2 and is_equal_approx(player.free_used, 0.0) and player.free_inputs.size() == 1,
			"half a tick each of 1 and 2, then 3 not begun this tick's bank: acked 2, used 0 (%d, %s)" % [player.free_acked, player.free_used])
	World.step()
	_check(player.free_acked == 2 and is_equal_approx(player.free_used, 1.0), "a tick of 3's 2.5: acked 2, used 1 (%s)" % player.free_used)
	World.free_input(player, Vector2(1, 0), World.TICK_DT, 4)
	World.halt(player, World.tick + 1)
	_check(player.free_acked == 4 and player.free_used == 0.0 and player.free_inputs.is_empty(), "halted: 3 and 4 dropped, acked 4")
	World.step()
	World.free_input(player, Vector2(1, 0), World.TICK_DT, 5)
	player.raised = "draw"
	World.step()
	_check(player.free_acked == 5, "a bow drawn: 5's time spent standing, acked 5 all the same")
	player.raised = ""
	for seq in World.FREE_INPUTS_MAX + 1:
		World.free_input(player, Vector2(1, 0), World.TICK_DT, 10 + seq)
	_check(player.free_acked == 10 and player.free_inputs.size() == World.FREE_INPUTS_MAX,
			"%d sent at once: the first dropped and acked (%d)" % [World.FREE_INPUTS_MAX + 1, player.free_acked])


func _test_walk_helper() -> void:
	print("\n== the walk-to test helper, either way ==")
	for free: bool in [false, true]:
		var player := _build(WALLED, Vector2i(0, 0))
		World.free_walk = free
		var started := World.tick
		_check(Walk.to(player, Vector2i(2, 2)) and Walk.arrived(player, Vector2i(2, 2)),
				"%s: from (0, 0) round the wall to (2, 2) in %d ticks" % ["free" if free else "grid", World.tick - started])


## A room from [param rows] with a player at [param at], free_walk on.
## Open ground [param w] x [param h] in the double-resolution format.
static func _open(w: int, h: int) -> Array[String]:
	var rows: Array[String] = []
	for y in h:
		var row := ""
		for x in w:
			row += ". " if x < w - 1 else "."
		rows.append(row)
		if y < h - 1:
			rows.append(" ".repeat(row.length()))
	return rows


func _draugr(at: Vector2i, facing: Vector2i) -> Monster:
	var by := EntityFactory.build({"script": "res://sim/draugr.gd", "shape": "capsule", "name": "Draugr", "kind": "draugr", "tile": at}) as Monster
	by.sight_range = 0
	by.acts = false
	_room.add_child(by)
	World.spawn(by, at)
	by.max_stamina = 100
	by.stamina = by.max_stamina
	by.slots = Items.tidy(["", "", "", "", "", ""], Items.CARRIED)
	World.set_slots(by, Items.tidy(["", "", "", "", "battle_axe" if Items.exists("battle_axe") else "giant_axe", ""], Items.CARRIED))
	World.face(by, facing)
	return by


## A dodge that looks clean is clean (the coordinator's free-walk audit, 1):
## a blow finds a free body by World.struck_cell, the cell it holds while
## its circle overlaps it. The claim moves 0.1 past the edge, under the
## circle's 0.3, so a body clear of the red has already claimed past it;
## through its own companion, whose cell its claim waits on, by its centre.
func _test_free_dodge() -> void:
	print("
== a dodge that looks clean is clean: the spin, the throw's line, through one's own companion ==")
	var struck: Array[float] = []
	for x: float in [4.3, 4.45, 4.55, 4.62, 4.75, 4.85]:
		var player := _sturdy(_build(_open(10, 5), Vector2i(4, 2)))
		var by := _draugr(Vector2i(2, 2), Vector2i(1, 0))
		World.try_spin(by)
		player.free_pos = Vector2(x, 2)
		World._free_claim(player, 2.5)
		for i in 16:
			World.step()
		if player.hp < player.max_hp:
			struck.append(x)
	_check(struck == [4.3, 4.45], "the spin's red ends at 4.5: struck with the centre at %s, in it; none from 4.55 on, the centre out of it (699)" % [struck])
	_check(struck.all(func(x: float) -> bool: return x - World.FREE_RADIUS < 4.5), "never struck with its circle clear of the red")
	struck.clear()
	for y: float in [2.3, 2.55, 2.65, 2.85]:
		var player := _sturdy(_build(_open(10, 5), Vector2i(6, 2)))
		var by := _draugr(Vector2i(2, 2), Vector2i(1, 0))
		World.try_axe_throw(by, Vector2i(8, 2))
		player.free_pos = Vector2(6, y)
		World._free_claim(player, 2.5)
		for i in 14:
			World.step()
		if player.hp < player.max_hp:
			struck.append(y)
	_check(struck == [2.3], "the throw's line, a side step: struck at %s, not with the centre past 2.5 (699)" % [struck])
	var player := _sturdy(_build(_open(10, 5), Vector2i(4, 2)))
	var pet := EntityFactory.build({"script": "res://sim/companion.gd", "shape": "capsule", "name": "Garrow", "props": {"max_hp": 10}}) as Companion
	pet.acts = false
	_room.add_child(pet)
	World.spawn(pet, Vector2i(5, 2))
	pet.keeper = player
	var by := _draugr(Vector2i(2, 2), Vector2i(1, 0))
	World.try_spin(by)
	for i in 3:
		World.free_input(player, Vector2(1, 0), World.TICK_DT)
		World.step()
	var held := player.tile
	for i in 13:
		World.step()
	_check(held == Vector2i(4, 2) and player.hp == player.max_hp,
			"into his companion's cell out of the red, his claim still on the red cell (%s): not struck (centre %s, %d hp)" % [held, player.free_pos, player.hp])
	# The charge (physics' rush, _lunge_cell) by the same rule: his held cell
	# stops it, for two bodies never share a cell, but strikes nobody.
	player = _sturdy(_build(_open(10, 5), Vector2i(4, 2)))
	pet = EntityFactory.build({"script": "res://sim/companion.gd", "shape": "capsule", "name": "Garrow", "props": {"max_hp": 10}}) as Companion
	pet.acts = false
	_room.add_child(pet)
	World.spawn(pet, Vector2i(5, 2))
	pet.keeper = player
	by = _draugr(Vector2i(2, 2), Vector2i(1, 0))
	for i in 3:
		World.free_input(player, Vector2(1, 0), World.TICK_DT)
		World.step()
	var ended: Array = []
	var heard := func(entity: GridEntity, reason: String, _at: Variant = null, _result: Variant = null) -> void:
		if entity == by:
			ended.append(reason)
	World.rush_ended.connect(heard)
	World.rush(by, Vector2(1, 0), 6, {"blow": {"impulse": 40.0}})
	for i in 12:
		World.step()
	World.rush_ended.disconnect(heard)
	_check(player.tile == Vector2i(4, 2) and by.tile == Vector2i(3, 2) and ended == ["body"] and player.hp == player.max_hp and pet.hp == 10,
			"a charge along the row: stopped at %s by the cell he holds, %s, nobody struck (%d hp, hers %d; ended %s)" % [by.tile, player.tile, player.hp, pet.hp, ended])


## A monster's blows on a free body that walks away and zig-zags (the
## audit, 2): reach by bodies (699), so no blow lands past World.reach_limit
## between the centres, and the monster closes on strike cells (699,
## enemy-ai's side) rather than waiting out of reach; no dance at a cell's
## border (a dart's in and out is its tactic).
func _test_free_chase() -> void:
	print("
== a monster after a free body: blows within reach by bodies, no dance at a border ==")
	for kind: String in ["imp", "brute", "skeleton", "robber"]:
		var player := _sturdy(_build(_open(24, 9), Vector2i(4, 4)))
		var foe := EntityFactory.build({"script": "res://sim/monster.gd", "shape": "capsule", "name": "Foe", "kind": kind, "tile": Vector2i(2, 4), "temperament": "bold", "props": Monster.bodies()[kind]}) as Monster
		_room.add_child(foe)
		World.spawn(foe, Vector2i(2, 4))
		foe.sight_range = 12
		foe.senses.cone_cos = -1.0
		var hits: Array[float] = []
		var hurt := func(entity: GridEntity, _amount: int, source: GridEntity, _cause: StringName) -> void:
			if entity == player and source == foe:
				hits.append(snappedf(player.free_pos.distance_to(Vector2(foe.tile)), 0.01))
		World.entity_damaged.connect(hurt)
		var turns := 0
		var last_way := Vector2i.ZERO
		var last_tile := foe.tile
		for i in 200:
			var way := Vector2(1, 0) if i < 40 else Vector2(-1, 0.6 if (i / 6) % 2 == 0 else -0.6).normalized()
			World.free_input(player, way, World.TICK_DT)
			World.step()
			if foe.tile != last_tile:
				var d := foe.tile - last_tile
				if last_way != Vector2i.ZERO and d == -last_way:
					turns += 1
				last_way = d
				last_tile = foe.tile
		World.entity_damaged.disconnect(hurt)
		var reach := World.reach_limit(foe) + 0.005  # The hits are snapped to 0.01.
		_check(not hits.is_empty() and hits.max() <= reach and (turns <= 1 or kind == "imp"),
				"%s: %d blows, at centres %s apart (reach by bodies: at most %.2f); back-and-forth steps %d" % [kind, hits.size(), hits, reach, turns])


## Kiting (the audit, 3; reported to the coordinator, not changed): a free
## body walks 0.4 cells a tick any way, a diagonal no slower; a grid
## walker's diagonal costs 1.5 its pace. Circling at 4 cells, no kind is as
## quick (a sneak's 3.0 the nearest, a player's 2.5), and none lands a blow. This pins what is so:
## a change that answers kiting turns it.
func _test_free_kite() -> void:
	print("
== kiting: a free body circling a grid walker at 4 (as found, reported) ==")
	for kind: String in ["imp", "brute", "robber", "sneak"]:
		var player := _sturdy(_build(_open(24, 24), Vector2i(12, 8)))
		var foe := EntityFactory.build({"script": "res://sim/monster.gd", "shape": "capsule", "name": "Foe", "kind": kind, "tile": Vector2i(12, 12), "temperament": "bold", "props": Monster.bodies()[kind]}) as Monster
		_room.add_child(foe)
		World.spawn(foe, Vector2i(12, 12))
		foe.sight_range = 20
		foe.senses.cone_cos = -1.0
		var near := 99.0
		for i in 400:
			var off := player.free_pos - Vector2(12, 12)
			var way := Vector2(-off.y, off.x).normalized() - off.normalized() * (off.length() - 4.0) * 0.3
			World.free_input(player, way.limit_length(1.0), World.TICK_DT)
			World.step()
			if i > 50:
				near = minf(near, player.free_pos.distance_to(Vector2(foe.tile)))
		_check(player.hp == player.max_hp, "%s (its pace %.1f): no blow in 400 ticks of circling; nearest %.2f" % [kind, foe._pace, near])


func _sturdy(player: Player) -> Player:
	player.max_hp = 9999
	player.hp = player.max_hp
	return player


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
