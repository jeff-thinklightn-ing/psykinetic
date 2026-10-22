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
}
const NAMES := {"P": "Player", "m": "Dummy", "o": "Boulder"}

var _failures := 0
var _room: Node2D
var _damage_log: Array[Dictionary] = []


func _ready() -> void:
	World.set_process(false)
	World.entity_damaged.connect(_on_entity_damaged)

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
	_check(World.try_move(player, Vector2i.RIGHT), "a step toward it")
	var duration := player.next_move_tick - World.tick
	while World.tick < player.next_move_tick:
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
	_check(World.try_move(player, Vector2i.LEFT), "a step away from it")
	while World.tick < player.next_move_tick:
		World.step()
	World._relocate(player, Vector2i(2, 1))
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


# --- helpers ------------------------------------------------------------------

## A cell map as push_test's: '#' solid, '.' floor, 'P' player, 'm' a dummy
## monster of [param mass] kg (AI off, 50 hp), 'o' a 200 kg boulder.
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


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


func _on_entity_damaged(entity: GridEntity, amount: int, _source: GridEntity, cause: StringName) -> void:
	_damage_log.append({"entity": entity, "amount": amount, "cause": cause})
