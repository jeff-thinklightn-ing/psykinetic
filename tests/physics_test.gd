extends Node
## The knockback model (decision 592): a blow's push by the two masses, the
## attacker's momentum and the angle, and what a sliding body meets. Scripted
## like push_test: small rooms, World stepped by hand, numbers checked.
##
## Numbers from levels/physics.json: shove_scale 0.1, ATTACK_FORCE_FACTOR
## 0.5, slide_per_speed 1.5, max_travel 10, momentum_scale 0.25,
## restitution 0.2, impact_per_energy 0.075, knockback_min_speed 1.5. A
## player is 80 kg, strength 10; with a war hammer (3 kg, force 3) 83 kg, so
## its blow pushes a body of m kg at 10 * 83 * 0.1 * 0.5 * 3 / m = 124.5 / m.

const SPECS := {
	"P": {"script": "res://sim/player.gd", "shape": "capsule"},
	"m": {"script": "res://sim/monster.gd", "shape": "capsule"},
	"o": {"script": "res://sim/pushable.gd", "shape": "sphere",
		"props": {"mass": 200.0, "body_material": GridEntity.BodyMaterial.STONE}},
	"c": {"script": "res://sim/cargo.gd", "shape": "slab", "art": "prop.mine_cart", "props": {"mass": 60.0, "capacity": 8}},
}
const NAMES := {"P": "Player", "m": "Dummy", "o": "Boulder", "c": "Cart"}

var _failures := 0
var _room: Node2D
var _damage_log: Array[Dictionary] = []
var _rush_ends: Array[Dictionary] = []


func _ready() -> void:
	World.set_process(false)
	World.entity_damaged.connect(_on_entity_damaged)
	World.rush_ended.connect(_on_rush_ended)
	# The model measured with the hammer as its tool: its one-cell cap (305
	# amended, checked in combat_test) lifted in this process only.
	_check(Items.set_verb("hammer", "max_cells", 0), "the hammer's cap lifted for the model's numbers")

	_test_rules_file()
	_test_mass_decides()
	_test_momentum()
	_test_angle()
	_test_wall_by_mass()
	_test_body_on_body()
	_test_brace()
	_test_lunge()
	_test_charge()
	_test_launch()
	_test_rush()
	_test_sweep()
	_test_hurl()
	_test_pack_throw()
	_test_ground()
	_test_rush_in_its_zone()
	_test_load()
	_test_clank()
	_test_falls()
	_test_cart_roll()
	_test_plate_need()

	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_rules_file() -> void:
	print("\n== the numbers come from levels/physics.json ==")
	_check(is_equal_approx(World.slide_per_speed, 1.5) and World.max_travel == 10 and is_equal_approx(World.restitution, 0.2),
			"slide_per_speed 1.5, max_travel 10, restitution 0.2 (%s, %s, %s)" % [World.slide_per_speed, World.max_travel, World.restitution])
	World.load_physics_rules('{"slide_per_speed": 2.0, "max_travel": 4}')
	_check(is_equal_approx(World.slide_per_speed, 2.0) and World.max_travel == 4, "a rules text sets them (2.0, 4)")
	World.load_physics_rules('{"slide_per_speed": -1, "max_travel": "far"}')
	_check(is_equal_approx(World.slide_per_speed, 2.0) and World.max_travel == 4, "a value under 0 or not a number keeps what was")
	World.load_physics_rules(FileAccess.get_file_as_string(World.PHYSICS_RULES))
	_check(is_equal_approx(World.slide_per_speed, 1.5) and World.max_travel == 10, "the file again: 1.5, 10")


func _test_mass_decides() -> void:
	print("\n== one hammer blow, four masses: the lighter goes farther ==")
	var cells: Array[int] = []
	for mass: float in [25.0, 40.0, 70.0, 90.0]:
		var e := _build(["##############", "#Pm..........#", "##############"], mass)
		var player: GridEntity = e["P"][0]
		var dummy: GridEntity = e["m"][0]
		_give(player, "hammer")
		_check(is_equal_approx(player.mass, 83.0), "the player with a hammer weighs 83 (%s)" % player.mass)
		_blow(player, dummy)
		cells.append(dummy.tile.x - 2)
	# 124.5 / m x 1.5: 7.47, 4.67, 2.67; 90 kg's 1.38 under the 1.5 threshold.
	_check(cells == [7, 4, 2, 0], "25, 40, 70, 90 kg knocked 7, 4, 2, 0 cells (%s)" % [cells])

	var e := _build(["######", "#Pm..#", "######"], 40.0)
	_blow(e["P"][0], e["m"][0])
	_check(e["m"][0].tile == Vector2i(2, 1), "a fist on 40 kg (speed 1.0, under 1.5): damage only, no slide")


func _test_momentum() -> void:
	print("\n== moving into a blow adds the attacker's momentum ==")
	# 85 kg: a hammer standing, 124.5 / 85 = 1.46, under the threshold.
	var e := _build(["############", "#P.m.......#", "############"], 85.0)
	var player: GridEntity = e["P"][0]
	var dummy: GridEntity = e["m"][0]
	_give(player, "hammer")
	World._relocate(player, Vector2i(2, 1))
	_blow(player, dummy)
	_check(dummy.tile == Vector2i(3, 1), "standing: 1.46, it stays (at %s)" % dummy.tile)
	_check(World.body_velocity(player) == Vector2.ZERO, "standing, no velocity")

	e = _build(["############", "#P.m.......#", "############"], 85.0)
	player = e["P"][0]
	dummy = e["m"][0]
	_give(player, "hammer")
	# A player walks free (703, step 2): 3 ticks east, to x 2.2, the dummy's
	# neighbour still.
	var duration := World.step_ticks(player, Vector2i.RIGHT)
	for i in 3:
		World.free_input(player, Vector2(1, 0), World.TICK_DT)
		World.step()
	var velocity := World.body_velocity(player)
	_check(velocity.is_equal_approx(Vector2(1.0 / duration, 0.0)), "its velocity, a cell over %.1f ticks (%s)" % [duration, velocity])
	# 1.46 + 0.25 x 83 x 0.4 / 85 = 1.56: over 1.5, 2.34 cells.
	_blow(player, dummy)
	_check(dummy.tile == Vector2i(5, 1), "stepping in: 1.56, knocked 2 cells (at %s)" % dummy.tile)

	e = _build(["############", "#.Pm.......#", "############"], 85.0)
	player = e["P"][0]
	dummy = e["m"][0]
	_give(player, "hammer")
	World.free_input(player, Vector2(-1, 0), World.TICK_DT)
	World.step()
	_check(player.tile == Vector2i(2, 1) and World.body_velocity(player).x < 0.0, "a tick's walk away from it, its cell kept (%s)" % player.free_pos)
	_blow(player, dummy)
	_check(dummy.tile == Vector2i(3, 1), "backing away takes nothing off and adds nothing: 1.46, it stays (at %s)" % dummy.tile)


func _test_angle() -> void:
	print("\n== a push along any angle, traced a cell at a time ==")
	var e := _build([
		"##############",
		"#............#",
		"#.Pm.........#",
		"#............#",
		"#............#",
		"#............#",
		"##############",
	], 25.0)
	var player: GridEntity = e["P"][0]
	var dummy: GridEntity = e["m"][0]
	# 100 / 25 = 4, 6 cells along (2, 1): (1, 1), (2, 1), (3, 2), (4, 2), (5, 3), (6, 3) from (3, 2).
	var result := World.apply_blow(player, dummy, {"impulse": 100.0, "direction": Vector2(2, 1)})
	_check(dummy.tile == Vector2i(9, 5), "it ends 6 cells off along (2, 1), at (9, 5), off every compass line (at %s)" % dummy.tile)
	_check(result["moved"] and result["distance"] == 6 and result["stopped_by"] == "nothing (force spent)",
			"apply_blow says: moved %s, %d cells, stopped by %s" % [result["moved"], result["distance"], result["stopped_by"]])
	_check(is_equal_approx(result["speed"], 4.0), "at speed 4 (%s)" % result["speed"])

	e = _build(["######", "#Pm..#", "######"], 40.0)
	result = World.apply_blow(e["P"][0], e["m"][0], {"impulse": 40.0})
	_check(not result["moved"] and e["m"][0].tile == Vector2i(2, 1), "an impulse of 40 on 40 kg (speed 1.0): held to the threshold")


func _test_wall_by_mass() -> void:
	print("\n== the same shove into a wall hurts a light body more ==")
	var hurt: Array[int] = []
	for mass: float in [25.0, 40.0, 70.0]:
		var e := _build(["####", "#Pm#", "####"], mass)
		var dummy: GridEntity = e["m"][0]
		World.order_shove(e["P"][0], dummy)
		World.step()
		hurt.append(_damage(dummy, &"impact"))
	# Speed 80 / m into the wall at once: 0.075 x 1/2 m (80 / m)^2 = 240 / m.
	_check(hurt == [10, 6, 3], "25, 40, 70 kg take 10, 6, 3 (%s)" % [hurt])


func _test_body_on_body() -> void:
	print("\n== a body knocked into a body: mass decides who goes on ==")
	var e := _build(["##########", "#Pmm.....#", "##########"], 40.0)
	var player: GridEntity = e["P"][0]
	_give(player, "hammer")
	_blow(player, e["m"][0])
	# 3.11 into the second at once: it goes on at 1.2 x 40 x 3.11 / 80 = 1.87, 2 cells.
	_check(e["m"][0].tile == Vector2i(2, 1) and e["m"][1].tile == Vector2i(5, 1),
			"a goblin into a goblin: the first stops, the second goes on 2 (at %s, %s)" % [e["m"][0].tile, e["m"][1].tile])
	_check(_damage(e["m"][0], &"impact") == 5 and _damage(e["m"][1], &"impact") == 5,
			"the energy lost, 193.8 - 69.8, shared: 5 each (%d, %d)" % [_damage(e["m"][0], &"impact"), _damage(e["m"][1], &"impact")])

	e = _build(["##########", "#Pmo.....#", "##########"], 40.0)
	_give(e["P"][0], "hammer")
	_blow(e["P"][0], e["m"][0])
	# 1.2 x 40 x 3.11 / 240 = 0.62: under a cell's worth.
	_check(e["o"][0].tile == Vector2i(3, 1) and e["m"][0].tile == Vector2i(2, 1),
			"a goblin into a 200 kg boulder: neither moves (at %s, %s)" % [e["m"][0].tile, e["o"][0].tile])

	e = _build(["##########", "#Pmm.....#", "##########"], 70.0)
	var imp: GridEntity = e["m"][1]
	imp.mass = 25.0
	_give(e["P"][0], "hammer")
	_blow(e["P"][0], e["m"][0])
	# 124.5 / 70 = 1.78; 1.2 x 70 x 1.78 / 95 = 1.57 into the imp: 2 cells.
	_check(e["m"][0].tile == Vector2i(2, 1) and imp.tile == Vector2i(5, 1),
			"a brute into an imp: the brute stops, the imp flies on 2 (at %s, %s)" % [e["m"][0].tile, imp.tile])


func _test_brace() -> void:
	print("\n== a braced spear turns a charge by its own momentum ==")
	var e := _build(["##############", "#P...........#", "##############"], 40.0)
	var host: GridEntity = e["P"][0]
	_give(host, "spear")
	var boar := EntityFactory.build({"script": "res://sim/animal.gd", "shape": "capsule", "name": "Boar", "tile": Vector2i(5, 1),
		"kind": "boar", "props": {"mass": 80.0, "max_hp": 18}}) as Animal
	_room.add_child(boar)
	World.spawn(boar, Vector2i(5, 1))
	boar.acts = false
	host._world_set_facing(Vector2i.RIGHT)
	host.last_step_tick = World.tick - World.BRACE_TICKS
	_check(World.braced(host), "the host stood still facing the lane: braced")
	boar._foe = host
	boar._charge_until = World.tick + 50
	boar._world_set_facing(Vector2i.LEFT)
	boar.next_move_tick = 0
	_check(World.try_move(boar, Vector2i.LEFT), "a charging step at four cells")
	var speed := World.body_velocity(boar).length()
	boar.next_move_tick = 0
	_check(not World.try_move(boar, Vector2i.LEFT), "the next, into the spear's reach: stopped")
	World._resolve_hits()
	# The spear's blow 10 x 82 x 0.1 x 0.5 / 80 = 0.51, plus its whole momentum
	# over its mass, turned: (1 + 1) x its speed.
	var back := 0.51 + 2.0 * speed
	var cells := floori(back * 1.5 + 0.001)
	_check(cells >= 1 and boar.tile.x == 4 + cells,
			"thrown back by the blow and its own charge, %.2f: %d cells (at %s)" % [back, cells, boar.tile])


func _test_lunge() -> void:
	print("
== a lunge stops at the first body and lands its blow, its momentum added (596) ==")
	var cells: Array[int] = []
	for mass: float in [25.0, 70.0]:
		var e := _build(["##############", "#P.m.........#", "##############"], mass)
		var result := World.lunge(e["P"][0], Vector2(1, 0), 2, {"blow": {"impulse": 40.0}})
		_check(e["P"][0].tile == Vector2i(2, 1) and result["cells"] == 1 and result["stopped_by"] == "Dummy1",
				"the lunger goes 1 cell and meets it (at %s, %d, %s)" % [e["P"][0].tile, result["cells"], result["stopped_by"]])
		cells.append(e["m"][0].tile.x - 3)
	# 40 / m plus 0.25 x 80 x 1 / m: 2.4 on 25 kg (3 cells); 0.86 on 70 kg, under the threshold.
	_check(cells == [3, 0], "25 kg knocked 3 cells, 70 kg not at all (%s)" % [cells])

	var e := _build(["######", "#P..##", "######"], 40.0)
	var result := World.lunge(e["P"][0], Vector2(1, 0), 4)
	_check(e["P"][0].tile == Vector2i(3, 1) and result["cells"] == 2 and result["stopped_by"] == "wall",
			"a wall ends it: 2 cells of 4 (at %s, %s)" % [e["P"][0].tile, result["stopped_by"]])
	_check(is_equal_approx(e["P"][0].next_move_tick, World.tick + 2.0), "and it may step again when its 2 lunge steps are done")


func _test_charge() -> void:
	print("
== a charge goes through bodies by mass: a goblin is knocked on, an ogre stops it (596) ==")
	var e := _build(["##############", "#P.m.........#", "##############"], 40.0)
	var player: GridEntity = e["P"][0]
	var goblin: GridEntity = e["m"][0]
	var result := World.lunge(player, Vector2(1, 0), 6, {"through": true, "blow": {"impulse": 41.0}})
	# Met at speed 1: the goblin 1.2 x 80 / 120 + 41 / 40 = 1.83, 2 cells; the
	# charge on at 72 / 120 = 0.6, meets it again: 0.48 + 1.03 = 1.5, 2 more;
	# the charge at 0.36 stops.
	_check(goblin.tile == Vector2i(7, 1) and player.tile == Vector2i(4, 1) and result["cells"] == 3,
			"the goblin knocked on twice to (7, 1), the charger 3 cells to (4, 1) (at %s, %s, %d)" % [goblin.tile, player.tile, result["cells"]])
	_check(result["struck"].size() == 2, "it met the goblin twice (%d)" % result["struck"].size())

	e = _build(["##############", "#P.m.........#", "##############"], 200.0)
	player = e["P"][0]
	var ogre: GridEntity = e["m"][0]
	result = World.lunge(player, Vector2(1, 0), 6, {"through": true, "blow": {"impulse": 41.0}})
	# 1.2 x 80 / 280 + 41 / 200 = 0.55, under a cell; the charge on at 40 / 280 = 0.14.
	_check(ogre.tile == Vector2i(3, 1) and player.tile == Vector2i(2, 1) and result["stopped_by"] == "Dummy1",
			"a 200 kg ogre: neither moves past the meeting, the charge stops dead (at %s, %s)" % [ogre.tile, player.tile])
	_check(result["impact_damage"] == 1 and _damage(ogre, &"impact") == 1,
			"the energy lost, 40 - 0.8 - 11.8, shared: 1 each (%d, %d)" % [result["impact_damage"], _damage(ogre, &"impact")])


func _test_launch() -> void:
	print("
== a launched body: thrown along a line by mass, not held to the threshold (598) ==")
	var cells: Array[int] = []
	for mass: float in [25.0, 70.0]:
		var e := _build(["##############", "#Pm..........#", "##############"], mass)
		var result := World.launch(e["P"][0], e["m"][0], Vector2(1, 0), 100.0)
		cells.append(result["distance"])
	# 100 / 25 = 4, 6 cells; 100 / 70 = 1.43 (under the blow's 1.5, but a throw), 2.
	_check(cells == [6, 2], "an impulse of 100 throws 25 kg 6 cells and 70 kg 2 (%s)" % [cells])

	var e := _build(["##########", "#Pmm.....#", "##########"], 40.0)
	var result := World.launch(e["P"][0], e["m"][0], Vector2(1, 0), 120.0)
	# 3.0 into the second at once: it goes on at 1.2 x 40 x 3 / 80 = 1.8, 2 cells.
	_check(e["m"][0].tile == Vector2i(2, 1) and e["m"][1].tile == Vector2i(5, 1) and result["struck"].size() == 1,
			"a goblin thrown into a goblin knocks it on 2 (at %s, %s)" % [e["m"][0].tile, e["m"][1].tile])

	e = _build(["##########", "#....Pm..#", "##########"], 40.0)
	result = World.launch(e["P"][0], e["m"][0], Vector2(-1, 0), 120.0)
	# 3.0, 4 cells: 2 over the thrower's head, then 2 more beyond it.
	_check(e["m"][0].tile == Vector2i(2, 1) and result["distance"] == 4,
			"thrown back over its thrower: lands behind and slides on, 4 cells to (2, 1) (at %s, %d)" % [e["m"][0].tile, result["distance"]])
	_check(not World.launch(e["P"][0], e["P"][0], Vector2(1, 0), 50.0)["moved"], "nobody throws itself")


func _test_rush() -> void:
	print("
== a rush: a charge spread over time, stopped by what it meets, by mass (604) ==")
	# A 120 kg dummy (the draugr's mass) rushing west, a cell a tick at speed 1.
	var e := _build(["##############", "#............#", "#.P.......m..#", "#............#", "#............#", "##############"], 120.0)
	var dummy: GridEntity = e["m"][0]
	_check(World.rush(dummy, Vector2(-1, 0), 8, {"to": Vector2i(5, 2)}), "it starts")
	_check(not World.rush(dummy, Vector2(-1, 0), 8), "and cannot start another while it runs")
	for i in 5:
		World.step()
	_check(dummy.tile == Vector2i(5, 2) and _rush_ends.back()["reason"] == "arrived",
			"5 ticks, 5 cells: arrived at its cell (at %s, %s)" % [dummy.tile, _rush_ends.back()["reason"]])
	_check(not World.rushing(dummy), "and is rushing no more")

	# A sword from the front: 10 x 81.5 x 0.05 / 120 = 0.34 off its speed, less
	# as each swing spends the player's stamina (597): 0.34, 0.32, 0.30 leave
	# 0.04, under rush_stop_speed 0.1.
	e = _build(["##############", "#............#", "#.P.......m..#", "#............#", "#............#", "##############"], 120.0)
	var player: GridEntity = e["P"][0]
	dummy = e["m"][0]
	_give(player, "sword")
	World.rush(dummy, Vector2(-1, 0), 8, {"through": true})
	var hits := 0
	while World.rushing(dummy) and hits < 5:
		World._relocate(player, dummy.tile + Vector2i.LEFT)
		_blow(player, dummy)
		hits += 1
	_check(hits == 3 and _rush_ends.back()["reason"] == "blow", "three sword hits from the front stop it (%d, %s)" % [hits, _rush_ends.back()["reason"]])

	e = _build(["##############", "#............#", "#.P.......m..#", "#............#", "#............#", "##############"], 120.0)
	player = e["P"][0]
	dummy = e["m"][0]
	_give(player, "hammer")
	World.rush(dummy, Vector2(-1, 0), 8, {"through": true})
	World._relocate(player, dummy.tile + Vector2i.LEFT)
	_blow(player, dummy)
	# 10 x 83 x 0.05 x 3 / 120 = 1.04: spent at once, and under 1.5, so not knocked back.
	_check(not World.rushing(dummy) and _rush_ends.back()["reason"] == "blow" and dummy.tile == Vector2i(10, 2),
			"a hammer stops it dead in one, where it stands (%s, at %s)" % [_rush_ends.back()["reason"], dummy.tile])

	e = _build(["##############", "#............#", "#.P.......m..#", "#............#", "#............#", "##############"], 120.0)
	player = e["P"][0]
	dummy = e["m"][0]
	_give(player, "sword")
	World.rush(dummy, Vector2(-1, 0), 8, {"through": true})
	for i in 4:
		World._relocate(player, dummy.tile + Vector2i.RIGHT)
		_blow(player, dummy)
	_check(World.rushing(dummy) and is_equal_approx(World._rushers[dummy]["u"], 1.0),
			"four sword hits from behind: nothing (still rushing at %.2f)" % World._rushers[dummy]["u"] if World.rushing(dummy) else "four sword hits from behind: nothing (it stopped)")

	World.apply_blow(player, dummy, {"impulse": 240.0, "direction": Vector2(0, 1)})
	_check(not World.rushing(dummy) and _rush_ends.back()["reason"] == "knocked",
			"a blow from the side that moves it: knocked off its line (%s)" % _rush_ends.back()["reason"])

	# A player standing in its line: met at 1, shoved 1 cell (1.2 x 120 / 200 = 0.72);
	# it goes on at 104 / 200 = 0.52, meets them again too slow to move them, and ends.
	e = _build(["##############", "#............#", "#..P...m.....#", "#............#", "#............#", "##############"], 120.0)
	player = e["P"][0]
	dummy = e["m"][0]
	World.rush(dummy, Vector2(-1, 0), 8, {"through": true})
	for i in 8:
		World.step()
		if not World.rushing(dummy):
			break
	_check(_rush_ends.back()["reason"] == "body" and player.tile == Vector2i(2, 2) and dummy.tile == Vector2i(3, 2),
			"one player in its line: shoved a cell to (2, 2), and the rush ends against them at (3, 2) (%s, %s, %s)" % [
			_rush_ends.back()["reason"], player.tile, dummy.tile])

	e = _build(["########", "#......#", "#.m....#", "#......#", "########"], 120.0)
	dummy = e["m"][0]
	World.rush(dummy, Vector2(-1, 0), 8)
	for i in 3:
		World.step()
	_check(_rush_ends.back()["reason"] == "wall" and dummy.tile == Vector2i(1, 2), "a wall ends it (%s, at %s)" % [_rush_ends.back()["reason"], dummy.tile])

	e = _build(["##############", "#............#", "#.P.......m..#", "#............#", "#............#", "##############"], 120.0)
	dummy = e["m"][0]
	World.rush(dummy, Vector2(-1, 0), 8)
	World._stun_for(dummy, 5)
	World.step()
	_check(_rush_ends.back()["reason"] == "stunned" and dummy.tile == Vector2i(10, 2), "a stun ends it (%s)" % _rush_ends.back()["reason"])

	e = _build(["##############", "#............#", "#.P.......m..#", "#............#", "#............#", "##############"], 120.0)
	var host: GridEntity = e["P"][0]
	dummy = e["m"][0]
	_give(host, "spear")
	host._world_set_facing(Vector2i.RIGHT)
	host.last_step_tick = World.tick - World.BRACE_TICKS
	World.rush(dummy, Vector2(-1, 0), 10, {"through": true})
	for i in 10:
		World.step()
		if not World.rushing(dummy):
			break
	_check(_rush_ends.back()["reason"] == "brace", "a braced spear stops it (%s, at %s)" % [_rush_ends.back()["reason"], dummy.tile])


func _test_sweep() -> void:
	print("
== a sweep through a cone: each body pushed out along its own line (605) ==")
	var rows: Array[String] = ["################"]
	for y in 11:
		rows.append("#..............#")
	rows.append("################")
	var e := _build(rows, 80.0)
	var source := EntityFactory.build({"script": "res://sim/player.gd", "shape": "capsule", "name": "Sweeper", "tile": Vector2i(5, 6)})
	_room.add_child(source)
	World.spawn(source, Vector2i(5, 6))
	var bodies := {}
	for each: Array in [["A", Vector2i(6, 6), 80.0], ["B", Vector2i(6, 7), 70.0], ["C", Vector2i(7, 5), 40.0], ["D", Vector2i(4, 6), 80.0]]:
		var body := EntityFactory.build({"script": "res://sim/monster.gd", "shape": "capsule", "name": each[0], "tile": each[1],
			"props": {"mass": each[2], "max_hp": 50}})
		(body as Monster).sight_range = 0
		_room.add_child(body)
		World.spawn(body, each[1])
		body.hp = 50
		bodies[each[0]] = body
	var struck := World.sweep(source, Vector2(1, 0), 90.0, 2, {"impulse": 178.0})
	# 178 / m along each one's own line: A 2.23 east, 3 cells; B 2.54 south-east,
	# 3; C 4.45 along (2, -1), 6; D is behind.
	_check(struck.size() == 3, "three in the cone struck (%d)" % struck.size())
	_check(bodies["A"].tile == Vector2i(9, 6), "80 kg ahead knocked 3 cells east (at %s)" % bodies["A"].tile)
	_check(bodies["B"].tile == Vector2i(9, 10), "70 kg at the cone's edge knocked 3 cells south-east (at %s)" % bodies["B"].tile)
	_check(bodies["C"].tile == Vector2i(13, 2), "40 kg two cells off knocked 6 along its own line (at %s)" % bodies["C"].tile)
	_check(bodies["D"].tile == Vector2i(4, 6), "the one behind untouched (at %s)" % bodies["D"].tile)

	e = _build(["######", "#P#m.#", "######"], 40.0)
	_check(World.sweep(e["P"][0], Vector2(1, 0), 90.0, 2, {"impulse": 178.0}).is_empty(), "no sweep through a wall")

	e = _build(["######", "#Pm..#", "######"], 40.0)
	_give(e["P"][0], "giant_axe")
	# 10 x 85 x 0.1 x 0.5 x 1 + 5 x 20.
	_check(is_equal_approx(World.swing_impulse(e["P"][0], "giant_axe"), 142.5),
			"a giant axe's swing: the blow 42.5 and its 5 kg swung, 142.5 (%s)" % World.swing_impulse(e["P"][0], "giant_axe"))


func _test_hurl() -> void:
	print("
== a thing thrown down a line: it launches the first body and lands at its feet (606) ==")
	var e := _build(["##############", "#P....m......#", "##############"], 25.0)
	var player: GridEntity = e["P"][0]
	var dummy: GridEntity = e["m"][0]
	_give(player, "hammer")
	var told: Array = []
	player.hurled.connect(func(id: String, to: Vector2i) -> void: told.append([id, to]))
	var out := World.hurl(player, Player.RIGHT_HAND, Vector2(1, 0), 8, 20.0)
	# 3 kg x 20 = 60 on 25 kg: 2.4, 3 cells.
	_check(out["hit"] == dummy and dummy.tile == Vector2i(9, 1), "a 3 kg hammer at 20 knocks 25 kg 3 cells (at %s)" % dummy.tile)
	_check(out["landed"] == Vector2i(6, 1) and player.slots[Player.RIGHT_HAND].is_empty(),
			"and lands at its feet, (6, 1), out of the hand (%s)" % out["landed"])
	_check(told.size() == 1 and told[0][0] == "hammer" and told[0][1] == Vector2i(6, 1), "the views are told its flight (%s)" % [told])

	e = _build(["##############", "#P...........#", "##############"], 25.0)
	_give(e["P"][0], "hammer")
	out = World.hurl(e["P"][0], Player.RIGHT_HAND, Vector2(1, 0), 4, 20.0)
	_check(out["hit"] == null and out["landed"] == Vector2i(5, 1), "nobody on its line: it lands at the line's end, 4 off (%s)" % out["landed"])

	e = _build(["##############", "#P..#........#", "##############"], 25.0)
	_give(e["P"][0], "hammer")
	out = World.hurl(e["P"][0], Player.RIGHT_HAND, Vector2(1, 0), 8, 20.0)
	_check(out["landed"] == Vector2i(3, 1), "a wall stops it before (%s)" % out["landed"])

	# The draugr's case: a monster with hands throws its axe at a player.
	e = _build(["##############", "#..P.....m...#", "##############"], 120.0)
	player = e["P"][0]
	var thrower: GridEntity = e["m"][0]
	var hands := PackedStringArray()
	hands.resize(Items.CARRIED)
	thrower.slots = hands
	hands[Player.RIGHT_HAND] = "giant_axe"
	World.set_slots(thrower, hands)
	out = World.hurl(thrower, Player.RIGHT_HAND, Vector2(-1, 0), 8, 20.0)
	# 5 kg x 20 = 100 on the 80 kg player: 1.25. A player's free body
	# slides it all, slide_per_speed 1.5 a unit (688 amended (2)): 1.875
	# cells, to x 1.125, (1, 1); the grid's step would floor it to 1 cell.
	_check(out["hit"] == player and player.tile == Vector2i(1, 1) and out["landed"] == Vector2i(3, 1),
			"a monster throws its 5 kg axe: the player's free body slid 1.875 cells, the axe where they stood (%s, %s)" % [player.tile, out["landed"]])


func _test_pack_throw() -> void:
	print("
== the pack's throw is a hurl: a thing thrown moves what it hits by mass (606 amended) ==")
	# A 10 kg sack carries a cell (throw_reach): the imp stands beside the thrower.
	var e := _build(["##############", "#Pm..........#", "##############"], 25.0)
	var player: GridEntity = e["P"][0]
	var imp: GridEntity = e["m"][0]
	_give(player, "ore_sack")
	var hp := imp.hp
	_check(World.try_throw(player, Player.RIGHT_HAND, Vector2i(4, 1)), "a 10 kg sack thrown at a 25 kg body")
	# 10 x 2 = 20 on 25 kg: 0.8, 1 cell; its energy 0.075 x 1/2 x 10 x 2^2 = 1.5, 2 hp.
	_check(imp.tile == Vector2i(3, 1) and hp - imp.hp == 2, "it is knocked 1 cell and hurt 2 (at %s, %d)" % [imp.tile, hp - imp.hp])
	_check(not World.ground_uids(Vector2i(1, 1)).is_empty(), "and the sack fell before it, at the thrower's feet")

	e = _build(["##############", "#Pm..........#", "##############"], 80.0)
	player = e["P"][0]
	var heavy: GridEntity = e["m"][0]
	_give(player, "ore_sack")
	World.try_throw(player, Player.RIGHT_HAND, Vector2i(4, 1))
	_check(heavy.tile == Vector2i(2, 1) and World.is_stunned(heavy) and not World.ground_uids(Vector2i(1, 1)).is_empty(),
			"at 80 kg beside the thrower: not moved (0.25), staggered, the sack at the thrower's feet (%s)" % heavy.tile)


func _test_ground() -> void:
	print("
== the ground in one place: a ford slows a walk and shortens a slide alike (607) ==")
	# A shove gives 40 kg speed 2: 3 cells of open ground.
	var e := _build(["##########", "#Pm......#", "##########"], 40.0)
	World.order_shove(e["P"][0], e["m"][0])
	World.step()
	_check(e["m"][0].tile == Vector2i(5, 1), "on open ground the shove slides it 3 cells (at %s)" % e["m"][0].tile)

	e = _build(["##########", "#Pm......#", "##########"], 40.0)
	for x in range(3, 9):
		World._fords[Vector2i(x, 1)] = true
	_check(is_equal_approx(World.ground_drag(Vector2i(2, 1), Vector2i.RIGHT), World.FORD_TICK_SCALE), "a ford's drag is its wading scale, 2")
	World.order_shove(e["P"][0], e["m"][0])
	World.step()
	# 3 cells' worth of ground at 2 a ford cell: 1 cell, then spent.
	_check(e["m"][0].tile == Vector2i(3, 1), "through a ford the same shove slides it 1 cell (at %s)" % e["m"][0].tile)
	var walker: GridEntity = e["P"][0]
	_check(is_equal_approx(World.step_ticks(walker, Vector2i.RIGHT, Vector2i(2, 1)), walker.move_ticks * World.FORD_TICK_SCALE),
			"and a step into it takes its walk twice as long, as before (%s)" % World.step_ticks(walker, Vector2i.RIGHT, Vector2i(2, 1)))

	# A rush (607 amended): a ford's cells take twice the time and halve its
	# speed in them; its drive comes back on open ground.
	e = _build(["##############", "#............#", "#.P.......m..#", "#............#", "#............#", "##############"], 120.0)
	var dummy: GridEntity = e["m"][0]
	for x in [6, 7]:
		World._fords[Vector2i(x, 2)] = true
	World.rush(dummy, Vector2(-1, 0), 8, {"to": Vector2i(3, 2)})
	var steps := 0
	var speeds := {}
	while World.rushing(dummy) and steps < 20:
		World.step()
		steps += 1
		speeds[dummy.tile.x] = snappedf(World.body_velocity(dummy).length(), 0.01)
	# 7 cells, 2 of them ford: 5 + 2 x 2 = 9 ticks.
	_check(dummy.tile == Vector2i(3, 2) and steps == 9, "7 cells with 2 of ford take 9 ticks, not 7 (at %s, %d)" % [dummy.tile, steps])
	_check(speeds.get(7) == 0.5 and speeds.get(6) == 0.5 and speeds.get(5) == 1.0,
			"its speed 0.5 in the ford, what a spear or a body met there feels, and 1 again past it (%s)" % [speeds])



func _test_rush_in_its_zone() -> void:
	print("
== a rush is tended in its own zone, on its own clock (604 amended) ==")
	# Two zones awake, each with a player: a lair at tick 0 with a 120 kg
	# rusher, and another far ahead of it (the box's overworld, awake since
	# boot). The other zone's step must not take the rush's cells.
	World.clear_zones()
	var lair := World.add_zone("lair")
	var other := World.add_zone("other")
	World.enter(other)
	World.load_terrain(Terrain.parse(Terrain.expand(["#####", "#...#", "#####"])))
	var away := EntityFactory.build({"script": "res://sim/player.gd", "shape": "capsule", "name": "Away"})
	var away_room := Node2D.new()  # Not _room, which _build frees.
	add_child(away_room)
	away_room.add_child(away)
	World.spawn(away, Vector2i(1, 1))
	World.tick = 5000
	World.enter(lair)
	var e := _build(["##############", "#............#", "#.P.......m..#", "#............#", "#............#", "##############"], 120.0)
	var dummy: GridEntity = e["m"][0]
	World.rush(dummy, Vector2(-1, 0), 8, {"to": Vector2i(5, 2)})
	var highest := 0.0
	for i in 8:
		World.step()
		highest = maxf(highest, dummy.next_move_tick)
	_check(other.awake and lair.awake, "both zones awake")
	_check(dummy.tile == Vector2i(5, 2) and not World.rushing(dummy), "its 5 cells on the lair's clock, arrived (at %s)" % dummy.tile)
	_check(highest <= World.tick + 1, "its next step never on the other zone's clock (at most %.0f, the lair at %d, the other at %d)" % [highest, World.tick, other.tick])
	_check(not other.occupancy.values().has(dummy), "and never put down in the other zone")
	World.clear_zones()
	away_room.free()


# --- helpers ------------------------------------------------------------------

## A cell map as push_test's: '#' solid, '.' floor, 'P' player, 'm' a dummy
## monster of [param mass] kg (AI off, 50 hp), 'o' a 200 kg boulder.
## The load (decision 676): what is carried where slows what that part
## does. An 80 kg player with a bow and arrows walks, draws, drains and
## breathes as before; in plate (20 kg: 4 on the arms, 16 on the body) the
## walk takes 1.025 of its ticks, the draw 1.1, a held draw drains 1.10625
## as fast and the breath comes back 1 / 1.06 as fast.
func _test_load() -> void:
	print("
== the load: plate slows the walk, the draw, the drain and the breath; a bow alone nothing (676) ==")
	var e := _build(["#########", "#P......#", "#########"], 25.0)
	var player: GridEntity = e["P"][0]
	World.put_item(player, player, Player.RIGHT_HAND, World.items.mint("bow", "built"))
	World.put_item(player, player, Player.LEFT_HAND, World.items.mint("arrows", "built"))
	var verb := Items.verb_of("bow")
	var full := Items.step_ticks(verb, int(verb["full"]))
	_check(is_equal_approx(player.load_arms, 1.6) and is_equal_approx(player.load_body, 0.0) and World.load_band(player) == "light",
			"a bow and arrows: 1.6 kg on the arms, none on the body, light (%s, %s, %s)" % [player.load_arms, player.load_body, World.load_band(player)])
	_check(is_equal_approx(World.step_ticks(player, Vector2i(1, 0)), player.move_ticks) and is_equal_approx(World.draw_full_ticks(player), full)
			and is_equal_approx(World.draw_drain_load(player), 1.0) and is_equal_approx(World.load_breath(player), 1.0),
			"and walks %s ticks a cell, draws in %s, drains and breathes as before" % [World.step_ticks(player, Vector2i(1, 0)), World.draw_full_ticks(player)])
	World.put_item(player, player, Items.ARMOUR, World.items.mint("plate_armour", "built"))
	_check(is_equal_approx(player.load_arms, 5.6) and is_equal_approx(player.load_body, 16.0) and World.load_band(player) == "burdened",
			"in plate: 5.6 kg on the arms, 16 on the body, burdened (%s, %s, %s)" % [player.load_arms, player.load_body, World.load_band(player)])
	_check(is_equal_approx(World.step_ticks(player, Vector2i(1, 0)), player.move_ticks * 1.025),
			"the walk: 16 of 80 is 0.05 past the free 0.15, x 0.5: %s ticks a cell, not %s" % [World.step_ticks(player, Vector2i(1, 0)), player.move_ticks])
	_check(is_equal_approx(World.draw_full_ticks(player), full * 1.1),
			"the draw: 5.6 of the arms' 16 is 0.2 past: %s ticks to full draw, not %s" % [World.draw_full_ticks(player), full])
	_check(is_equal_approx(World.draw_drain_load(player), 1.10625) and is_equal_approx(World.load_breath(player), 1.0 / 1.06),
			"a held draw drains %s as fast; the breath comes back %.3f as fast" % [World.draw_drain_load(player), World.load_breath(player)])
	var drained := 0
	for n in 160:
		drained += World._carried(World.draw_drain_load(player), n)
	_check(drained == 177, "160 ticks held at full draw: %d stamina, not 160" % drained)
	# A client never weighs: it reads the replicated kg against its spawned mass.
	var mirror := Player.new()
	mirror.load_body = player.load_body
	mirror.load_arms = player.load_arms
	_check(is_equal_approx(World.step_ticks(mirror, Vector2i(1, 0), Vector2i(1, 1)), World.step_ticks(player, Vector2i(1, 0), Vector2i(1, 1))),
			"a client's body with the replicated load walks at the server's pace (%s)" % World.step_ticks(mirror, Vector2i(1, 0), Vector2i(1, 1)))
	mirror.free()
	World.load_k = 1.0
	_check(is_equal_approx(World.step_ticks(player, Vector2i(1, 0)), player.move_ticks * 1.05), "load_k 1: the walk 1.05 (F7's physics.load_k)")
	World.load_physics_rules(FileAccess.get_file_as_string(World.PHYSICS_RULES))
	_check(is_equal_approx(World.load_k, 0.5) and is_equal_approx(World.load_free, 0.15) and is_equal_approx(World.load_heavy, 0.3)
			and is_equal_approx(World.load_overloaded, 0.5), "physics.json: load_k 0.5, free 0.15, heavy 0.3, overloaded 0.5")
	World.put_item(player, player, 0, World.items.mint("ore_sack", "built"))
	_check(World.load_band(player) == "heavy", "a sack of ore in the pack too: 31.6 of 80, heavy (%s)" % World.load_band(player))
	World.put_item(player, player, 1, World.items.mint("ore_sack", "built"))
	_check(World.load_band(player) == "overloaded", "two: 41.6 of 80, overloaded (%s)" % World.load_band(player))


## A worn piece's clank (decision 676 step 1b): its material's cells a kg
## times its kg at a walk: plate's 20 kg 0.25 a kg, 5 cells; mail's 10 kg
## 0.2, 2; leather none. Its own &"clank" noise beside the step's, so prey
## run from it (enemy-ai's) where a step only turns them.
func _test_clank() -> void:
	print("
== a worn piece clanks by its material and kg: plate 5 cells, mail 2, leather none (676 1b) ==")
	_check(World.armour_noise("plate_armour") == {"radius": 5, "kind": "plate"} and World.armour_noise("mail_armour") == {"radius": 2, "kind": "mail"}
			and World.armour_noise("leather_armour") == {"radius": 0, "kind": "none"} and World.armour_noise("") == {"radius": 0, "kind": "none"},
			"at a walk: plate %s, mail %s, leather %s" % [World.armour_noise("plate_armour"), World.armour_noise("mail_armour"), World.armour_noise("leather_armour")])
	_check(int(World.armour_noise("plate_armour", 2.0)["radius"]) == 10 and int(World.armour_noise("plate_armour", 0.5)["radius"]) == 3,
			"twice the pace, twice the noise (10); half, 3 (rounded)")
	for worn: String in ["plate_armour", "leather_armour"]:
		var e := _build(["##########", "#P....m..#", "##########"], 25.0)
		var player: GridEntity = e["P"][0]
		var dummy := e["m"][0] as Monster
		World.put_item(player, player, Items.ARMOUR, World.items.mint(worn, "built"))
		dummy.senses.heard.clear()
		for i in 8:
			if player.tile != Vector2i(1, 1):
				break
			World.free_input(player, Vector2(1, 0), World.TICK_DT)
			World.step()
		_check(player.tile == Vector2i(2, 1), "%s: walked free into the next cell east" % worn)
		var kinds: Array = dummy.senses.heard.map(func(n: Dictionary) -> String: return "%s %d" % [n["kind"], n["radius"]])
		# 4 cells off: leather's body (86 kg) steps 3 and reaches nobody there; plate's
		# (100 kg) steps 4 (Senses.step_radius), and its clank (5 at its own pace, 2.56 ticks) too.
		var want: Array = ["step 4", "clank 5"] if worn == "plate_armour" else []
		_check(kinds == want, "%s: a dummy 4 cells off hears %s" % [worn, kinds])


func _build(rows: Array[String], mass: float) -> Dictionary:
	World.reset()
	if _room != null:
		_room.free()
	_damage_log.clear()
	_room = Node2D.new()
	add_child(_room)
	var cell_rows: Array[String] = []
	var spawns: Array[Array] = []
	for y in rows.size():
		var cells := ""
		for x in rows[y].length():
			var symbol := rows[y][x]
			if symbol in ["#", "."]:
				cells += symbol
			else:
				cells += "."
				spawns.append([symbol, Vector2i(x, y)])
		cell_rows.append(cells)
	World.load_terrain(Terrain.parse(Terrain.expand(cell_rows)))
	var out := {}
	for kind: String in SPECS:
		out[kind] = []
		for spawn in spawns:
			if spawn[0] != kind:
				continue
			var spec: Dictionary = SPECS[kind].duplicate(true)
			spec["name"] = "%s%d" % [NAMES[kind], out[kind].size() + 1]
			spec["tile"] = spawn[1]
			if kind == "m":
				spec["props"] = {"mass": mass, "max_hp": 50}
			var entity := EntityFactory.build(spec)
			if entity is Monster:
				entity.sight_range = 0
			_room.add_child(entity)
			World.spawn(entity, spawn[1])
			if kind == "m":
				entity.hp = 50
			out[kind].append(entity)
	return out


## Falls (decision 783): a pit [param levels] deep on x 1..2 of the room
## just built (rows of [param width]), the rest floor at its rim's height.
func _sink(width: int, height: int, levels: int) -> void:
	var field := PackedFloat32Array()
	field.resize(width * height)
	for y in height:
		for x in width:
			field[y * width + x] = 0.0 if x in [1, 2] else levels * Relief.LEVEL_M
	World._relief = field
	World._relief_size = Vector2i(width, height)


func _test_falls() -> void:
	print("\n== falls into a shaft: the lip, damage by depth, a deadly one the shover's kill (decision 783) ==")
	var rows: Array[String] = ["#########", "#..mP...#", "#########"]
	var e := _build(rows, 40.0)
	_sink(9, 3, 2)
	var player: GridEntity = e["P"][0]
	var imp: GridEntity = e["m"][0]
	_check(World.height_step(Vector2i(3, 1), Vector2i(-1, 0)) == 2, "the pit lies two levels down off (3, 1)")
	World._push(player, imp, Vector2(-1, 0), 1.0)
	_check(imp.tile == Vector2i(3, 1) and imp.teeter == Vector2i(-1, 0) and imp.hp == 50 and World.is_stunned(imp),
			"a light shove (1.0, 0.33 left at the rim): it teeters on the rim, unhurt, stunned (%s, %s, %d)" % [imp.tile, imp.teeter, imp.hp])
	World.step()
	World.apply_blow(player, imp, {"impulse": 10.0, "direction": Vector2(1, 0)})
	_check(imp.tile == Vector2i(3, 1) and imp.teeter != Vector2i.ZERO, "a tap away from the drop: still on the rim")
	World.apply_blow(player, imp, {"impulse": 10.0, "direction": Vector2(-1, 0)})
	_check(imp.tile == Vector2i(2, 1) and imp.teeter == Vector2i.ZERO and imp.hp == 50 - 6 and World.is_down(imp),
			"a tap toward it (0.25, under the knockback floor): over, two levels for 6, lying (%s, %d hp)" % [imp.tile, imp.hp])

	e = _build(rows, 40.0)
	_sink(9, 3, 2)
	imp = e["m"][0]
	World._push(e["P"][0], imp, Vector2(-1, 0), 1.0)
	for i in World.teeter_ticks + 1:
		World.step()
	_check(imp.tile == Vector2i(3, 1) and imp.teeter == Vector2i.ZERO and not World.is_stunned(imp),
			"left alone %d ticks it finds its feet on the rim" % World.teeter_ticks)
	World._push(e["P"][0], imp, Vector2(-1, 0), 3.0)
	_check(imp.tile == Vector2i(2, 1) and imp.hp == 50 - 6, "a hard knock (3.0, 2.33 left) goes straight over (%s, %d)" % [imp.tile, imp.hp])

	# A free body (a player) teeters at its circle's edge alike.
	e = _build(["#########", "#..PP...#", "#########"], 40.0)
	_sink(9, 3, 2)
	var them: GridEntity = e["P"][0]
	World._push(e["P"][1], them, Vector2(-1, 0), 1.0)
	_check(World.free_body(them) and them.tile == Vector2i(3, 1) and them.teeter == Vector2i(-1, 0),
			"a player shoved lightly teeters too (%s, %s)" % [them.tile, them.teeter])
	World.step()
	World.apply_blow(e["P"][1], them, {"impulse": 10.0, "direction": Vector2(-1, 0)})
	_check(them.tile == Vector2i(2, 1) and them.teeter == Vector2i.ZERO, "and a tap sends them over (%s)" % [them.tile])

	# Deadly: fall_lethal_levels (8) or more. The shover's kill.
	e = _build(rows, 40.0)
	_sink(9, 3, 8)
	imp = e["m"][0]
	World._push(e["P"][0], imp, Vector2(-1, 0), 3.0)
	_check(not World._alive(imp) and (imp as Monster).struck_by == e["P"][0],
			"eight levels down kills, and the kill is the shover's (struck_by %s)" % [(imp as Monster).struck_by])

	# A sword's blow sending its foe over a deadly drop: one deed, felled
	# (combat's ask: never the blow's and the kill's both).
	e = _build(rows, 20.0)
	_sink(9, 3, 8)
	player = e["P"][0]
	imp = e["m"][0]
	player.set("player_id", "fall_test")
	_give(player, "sword")
	var uid: int = player.slot_items[Player.RIGHT_HAND]
	_blow(player, imp)
	var deeds := {}
	for row: Dictionary in World.items._book[uid]["carriers"]:
		deeds.merge(row["deeds"])
	_check(not World._alive(imp) and deeds == {"felled": 1},
			"a sword's knockback over eight levels: dead, and the sword's one deed is felled (%s)" % [deeds])


func _give(entity: GridEntity, id: String) -> void:
	World.put_item(entity, entity, Player.RIGHT_HAND, World.items.mint(id, "built"))


## A blow struck now and resolved.
func _blow(attacker: GridEntity, target: GridEntity) -> void:
	attacker.next_attack_tick = 0
	World.try_attack(attacker, target)
	World._resolve_hits()


func _damage(entity: GridEntity, cause: StringName) -> int:
	var total := 0
	for entry in _damage_log:
		if entry.entity == entity and entry.cause == cause:
			total += entry.amount
	return total


## Track on row [param row] from [param from_x] to [param to_x] (decision
## 794's World._track, as "mine_track" decor gives it), buffers (3) at
## [param buffers] ends.
func _lay_track(row: int, from_x: int, to_x: int, buffers := true) -> void:
	for x in range(from_x, to_x + 1):
		World._track[Vector2i(x, row)] = 3 if buffers and (x == from_x or x == to_x) else 1


## The ground in metres by [param height_of] (x -> metres), over
## [param width] x [param height] cells.
func _slope(width: int, height: int, height_of: Callable) -> void:
	var field := PackedFloat32Array()
	field.resize(width * height)
	for y in height:
		for x in width:
			field[y * width + x] = float(height_of.call(x))
	World._relief = field
	World._relief_size = Vector2i(width, height)


## Steps the world until [param cart] stops rolling (at most
## [param most] steps); the steps it took.
func _roll_out(cart: GridEntity, most := 600) -> int:
	var steps := 0
	while World.is_rolling(cart) and steps < most:
		World.step()
		steps += 1
	return steps


func _test_cart_roll() -> void:
	print("\n== mine carts roll on their rails: drag, slope, buffers, bends, a body bowled (decision 794) ==")
	var rows: Array[String] = ["##########################", "#Pc......................#", "#........................#", "##########################"]
	var e := _build(rows, 40.0)
	var player: GridEntity = e["P"][0]
	var cart: GridEntity = e["c"][0]
	_lay_track(1, 2, 24)
	World._push(player, cart, Vector2(1, 0), 1.33)
	_check(World.is_rolling(cart) and cart.tile == Vector2i(2, 1), "a shove along its rails sets it rolling, not sliding (%s)" % cart.tile)
	var steps := _roll_out(cart)
	var flat := cart.tile.x - 2
	_check(not World.is_rolling(cart) and flat >= 8 and flat <= 12 and steps > flat,
			"on the flat it rolls on, cell by cell, %d cells over %d steps (a slide's 1.33 m/s goes 2)" % [flat, steps])
	_check(cart.move_ticks > 2.0 and cart.move_ticks <= World.TICK_RATE / World.cart_stop_speed,
			"its last step slow, %.1f ticks (replicated move_ticks)" % cart.move_ticks)

	e = _build(rows, 40.0)
	cart = e["c"][0]
	_lay_track(1, 2, 24)
	_slope(26, 4, func(x: int) -> float: return 10.0 - 0.3 * x)
	World._push(e["P"][0], cart, Vector2(1, 0), 1.33)
	_roll_out(cart)
	_check(cart.tile == Vector2i(24, 1), "downhill it gains, and runs to the buffer at the end (%s, flat %d cells)" % [cart.tile, flat])

	e = _build(rows, 40.0)
	cart = e["c"][0]
	_lay_track(1, 2, 24)
	_slope(26, 4, func(x: int) -> float: return 0.3 * x)
	World._push(e["P"][0], cart, Vector2(1, 0), 2.0)
	var turned := false
	var high := 2
	for i in 400:
		World.step()
		high = maxi(high, cart.tile.x)
		if World.is_rolling(cart) and World._rolling[cart]["way"] == Vector2i(-1, 0):
			turned = true
		if not World.is_rolling(cart):
			break
	_check(turned and high > 2 and cart.tile.x < high, "uphill it slows, stalls at %d and rolls back down to %s" % [high, cart.tile])

	e = _build(rows, 40.0)
	cart = e["c"][0]
	_lay_track(1, 2, 6, false)
	World._track[Vector2i(6, 1)] = 2
	World._track[Vector2i(6, 2)] = 3
	World._push(e["P"][0], cart, Vector2(1, 0), 3.0)
	_roll_out(cart)
	_check(cart.tile == Vector2i(6, 2), "round a bend: it follows its rails south to the buffer (%s)" % cart.tile)
	World._push(e["P"][0], cart, Vector2(0, 1), 3.0)
	_check(not World.is_rolling(cart), "pushed past its buffer it does not roll")

	e = _build(rows, 40.0)
	cart = e["c"][0]
	_lay_track(1, 2, 24)
	World._push(e["P"][0], cart, Vector2(0, 1), 3.0)
	_check(not World.is_rolling(cart) and cart.tile != Vector2i(2, 1), "pushed across its rails it slides as any push (%s)" % cart.tile)

	# Walked into: it rolls on at the walker's pace, or its shove's if less.
	e = _build(rows, 40.0)
	player = e["P"][0]
	cart = e["c"][0]
	_lay_track(1, 2, 24)
	World._shift(player, cart, Vector2i(1, 0), player.mass, 2.0, float(World.tick))
	var given: float = World._rolling[cart]["v"] if World.is_rolling(cart) else 0.0
	_check(cart.tile == Vector2i(3, 1) and is_equal_approx(given, minf(World.TICK_RATE / 2.0, World.push_force(player, cart))),
			"walked into along its rails: a cell, then rolling on at %.2f" % given)

	# A loaded cart bowls a kobold into the pit beyond the track's end, the
	# kill (eight levels) the pusher's.
	var pit_rows: Array[String] = ["############", "#Pc...m....#", "############"]
	e = _build(pit_rows, 20.0)
	player = e["P"][0]
	cart = e["c"][0]
	var kobold: GridEntity = e["m"][0]
	_lay_track(1, 2, 6)
	_slope(12, 3, func(x: int) -> float: return 0.0 if x <= 6 else -8.0 * Relief.LEVEL_M)
	World._push(player, cart, Vector2(1, 0), 3.0)
	_roll_out(cart)
	_check(not World._alive(kobold) or kobold.hp <= 0, "the cart at speed sends a 20 kg kobold off the rim, eight levels: dead")
	_check(cart.tile.x <= 6, "the cart stays on its rails (%s)" % cart.tile)
	_check(is_instance_valid(kobold) and (kobold as Monster).struck_by == player, "the kill the pusher's: struck_by %s" % [(kobold as Monster).struck_by if is_instance_valid(kobold) else "freed"])

	# Too slow to go over: the kobold teeters on the rim (783).
	e = _build(pit_rows, 20.0)
	cart = e["c"][0]
	kobold = e["m"][0]
	_lay_track(1, 2, 6)
	_slope(12, 3, func(x: int) -> float: return 0.0 if x <= 6 else -2.0 * Relief.LEVEL_M)
	World._push(e["P"][0], cart, Vector2(1, 0), 1.0)
	_roll_out(cart)
	_check(kobold.tile == Vector2i(6, 1) and kobold.teeter == Vector2i(1, 0), "a slow cart only sets it teetering on the rim (%s, %s)" % [kobold.tile, kobold.teeter])


## 813 amended (3), the co-op forge's treadle: a plate with a "need" (kg)
## is held only by a player or a companion whatever they weigh, or by a
## body of at least its need; one without keeps 813's anything-holds.
func _test_plate_need() -> void:
	print("\n== a plate's need: a player and a companion always hold it, else the body's mass (813 amended (3)) ==")
	# The level's "need": one for every plate, or a list; anything else said and left out.
	var door_key := Terrain.edge_key(Vector2i(1, 0), Vector2i(0, -1))
	var terrain := {"floor": [Vector2i(1, 1), Vector2i(4, 1)], "edges": {door_key: Terrain.Edge.DOOR}}
	var warnings: Array[String] = []
	var set_of := func(need: Variant) -> Dictionary:
		var entry := {"id": "forge", "cells": [[1, 1], [4, 1]], "door": [1, 0, 0, -1], "room": "forge"}
		if need != null:
			entry["need"] = need
		return {"plates": [entry]}
	var parsed := Level.plates_from(set_of.call(50), terrain, warnings)
	_check(parsed.size() == 1 and parsed[0]["need"] == [50.0, 50.0] and warnings.is_empty(), "\"need\": 50 is 50 kg on every plate (%s)" % [parsed])
	parsed = Level.plates_from(set_of.call([50, 0]), terrain, warnings)
	_check(parsed.size() == 1 and parsed[0]["need"] == [50.0, 0.0], "a list is one per plate (%s)" % [parsed])
	parsed = Level.plates_from(set_of.call(null), terrain, warnings)
	_check(parsed.size() == 1 and not parsed[0].has("need") and warnings.is_empty(), "no need: none carried (813's rule)")
	for bad: Variant in ["heavy", -5, [50]]:
		warnings.clear()
		parsed = Level.plates_from(set_of.call(bad), terrain, warnings)
		_check(parsed.is_empty() and warnings.size() == 1, "need %s is said and the set left out (%s)" % [bad, warnings])

	# Who holds a need-50 plate (masses: player 80, companion 75, boulder 200, cart 60, crate 30).
	var rows: Array[String] = ["#########", "#P.m.o.c#", "#########"]
	var e := _build(rows, 3.0)  # The monster an imp: 3 kg.
	var crate := EntityFactory.build(Level.CRATE.duplicate(true).merged({"name": "Crate"}))
	_room.add_child(crate)
	World.spawn(crate, Vector2i(2, 1))
	var wren := EntityFactory.build({"script": "res://sim/companion.gd", "shape": "capsule", "name": "Wren", "props": {"max_hp": 10}}) as Companion
	_room.add_child(wren)
	World.spawn(wren, Vector2i(4, 1))
	var player: GridEntity = e["P"][0]
	var imp: GridEntity = e["m"][0]
	var boulder: GridEntity = e["o"][0]
	var cart: GridEntity = e["c"][0]
	var light := {}
	for body: GridEntity in [player, wren, imp, boulder, cart, crate]:
		light[body.name] = World.plate_weighs(body, 50.0)
	_check(light == {player.name: true, "Wren": true, imp.name: false, boulder.name: true, cart.name: true, "Crate": false},
		"need 50: the player, Wren, the boulder and the cart hold it; the imp (3) and the empty crate (30) do not (%s)" % [light])
	player.mass = 1.0
	wren.mass = 1.0  # Travelling light: a person holds it whatever they weigh.
	_check(World.plate_weighs(player, 50.0) and World.plate_weighs(wren, 50.0) and World.plate_weighs(player, 10000.0),
		"the lightest player and Wren (1 kg) still hold it, and any need")
	_check(World.plate_weighs(imp, 0.0) and World.plate_weighs(crate, 0.0) and not World.plate_weighs(null, 0.0),
		"with no need anything holds it, as 813 has it (the imp, the crate)")
	crate.mass = 55.0  # What it carries counts (entity.mass): a loaded crate.
	_check(World.plate_weighs(crate, 50.0), "a crate loaded past the need holds it")

	# plate_held over a set: plate 0 needs 50, plate 1 needs none.
	var zone_name := World.zone.name
	var had_zone := World.zones.has(zone_name)
	World.zones[zone_name] = World.zone
	var kept_plates := World.zone.plates
	World.zone.plates = [{"id": "forge", "cells": [imp.tile, wren.tile], "edge": door_key, "room": "forge", "need": [50.0, 0.0]}]
	_check(not World.plate_held(zone_name, "forge", 0) and World.plate_held(zone_name, "forge", 1) and not World.plate_held(zone_name, "forge"),
		"the imp on the treadle does not hold it, Wren on the plain plate does: the set not held")
	World.zone.plates[0]["cells"] = [boulder.tile, wren.tile]
	_check(World.plate_held(zone_name, "forge"), "the boulder on the treadle and Wren on the other: held")
	World.zone.plates = kept_plates
	if not had_zone:
		World.zones.erase(zone_name)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


func _on_rush_ended(entity: GridEntity, reason: String, at: Vector2i, _result: Dictionary) -> void:
	_rush_ends.append({"entity": entity, "reason": reason, "at": at})


func _on_entity_damaged(entity: GridEntity, amount: int, _source: GridEntity, cause: StringName) -> void:
	_damage_log.append({"entity": entity, "amount": amount, "cause": cause})
