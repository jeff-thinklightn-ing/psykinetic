extends Node
## Swings cost stamina and being winded (decision 597): the cost by the
## weapon's weight against the wielder's own mass, a whiff's more, a
## wind-up's paid as it begins; winded from 0 until back at recover_at,
## with slower steps, weaker blows, no bash and a longer wait for regen; a
## monster pays only by its row's switch. Scripted like physics_test: small
## rooms, World stepped by hand.
##
## Numbers from levels/combat.json: swing_base 3, swing_per_kg 2, ref_mass
## 70, whiff_scale 1.25, recover_at 25, winded_move_scale 1.5,
## winded_blow_scale 0.5, winded_regen_delay 20. A player is 80 kg with 100
## stamina: fists 3, a sword (1.5 kg) ceil(3 + 2 x 1.5 x 70 / 80) = 6, the
## giant axe (5 kg) 12.

const SPECS := {
	"P": {"script": "res://sim/player.gd", "shape": "capsule"},
	"m": {"script": "res://sim/monster.gd", "shape": "capsule"},
}
const NAMES := {"P": "Player", "m": "Dummy"}

var _failures := 0
var _room: Node2D


func _ready() -> void:
	World.set_process(false)

	_test_rules_file()
	_test_costs()
	_test_paid_on_a_blow()
	_test_winded()
	_test_monsters_switch()
	_test_telegraph_shapes()
	_test_telegraph_ground()
	_test_telegraph_lifecycle()

	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_rules_file() -> void:
	print("\n== the numbers come from levels/combat.json ==")
	_check(is_equal_approx(World.swing_base, 3.0) and is_equal_approx(World.whiff_scale, 1.25) and World.recover_at == 25,
			"swing_base 3, whiff_scale 1.25, recover_at 25 (%s, %s, %s)" % [World.swing_base, World.whiff_scale, World.recover_at])
	World.load_combat_rules('{"swing_base": 5, "recover_at": 40}')
	_check(is_equal_approx(World.swing_base, 5.0) and World.recover_at == 40, "a rules text sets them (5, 40)")
	World.load_combat_rules('{"swing_base": -1, "recover_at": "soon"}')
	_check(is_equal_approx(World.swing_base, 5.0) and World.recover_at == 40, "a value under 0 or not a number keeps what was")
	World.load_combat_rules(FileAccess.get_file_as_string(World.COMBAT_RULES))
	_check(is_equal_approx(World.swing_base, 3.0) and World.recover_at == 25, "the file again: 3, 25")


func _test_costs() -> void:
	print("\n== a swing's cost: the weapon's weight against the wielder's own mass ==")
	var e := _build(["#######", "#P.m..#", "#######"])
	var player: GridEntity = e["P"][0]
	_check(World.swing_cost(player) == 3, "fists: 3 (%d)" % World.swing_cost(player))
	_give(player, "sword")
	_check(World.swing_cost(player) == 6 and World.swing_cost(player, true) == 8,
			"a sword: 6, a whiff 8 (%d, %d)" % [World.swing_cost(player), World.swing_cost(player, true)])
	_clear(player)
	_give(player, "giant_axe")
	_check(World.swing_cost(player) == 12, "the giant axe: 12 (%d)" % World.swing_cost(player))
	var own := player.base_mass
	player.base_mass = 50.0
	var light := World.swing_cost(player)
	player.base_mass = 90.0
	var heavy := World.swing_cost(player)
	player.base_mass = own
	_check(light == 17 and heavy == 11, "a 50 kg build pays 17 for it, a 90 kg one 11 (%d, %d)" % [light, heavy])


func _test_paid_on_a_blow() -> void:
	print("\n== a blow, a whiff and a wind-up are paid for ==")
	var e := _build(["#######", "#Pm...#", "#######"])
	var player: GridEntity = e["P"][0]
	var dummy: GridEntity = e["m"][0]
	_give(player, "sword")
	_blow(player, dummy)
	_check(player.stamina == 94, "a sword blow: 100 -> 94 (%d)" % player.stamina)
	player.next_attack_tick = 0
	World.try_swing(player, Vector2i(-1, 0))
	_check(player.stamina == 86, "a swing at the air: 8 more, 86 (%d)" % player.stamina)
	_clear(player)
	_give(player, "giant_axe")
	player.stamina = 100
	player.next_attack_tick = 0
	_check(World.try_wind_up(player, dummy) and player.stamina == 88, "the giant axe's wind-up pays 12 as it begins (%d)" % player.stamina)
	for i in World.windup_ticks(player) + 2:
		World.step()
	_check(player.stamina >= 88 and player.wind_up.is_empty(), "and its blow lands without paying again (%d)" % player.stamina)


func _test_winded() -> void:
	print("\n== whiffs till winded: slower, weaker, no bash; back at 25 ==")
	var e := _build(["#######", "#.Pm..#", "#######"])
	var player: GridEntity = e["P"][0]
	var dummy: GridEntity = e["m"][0]
	_give(player, "sword")
	var fresh := _blow_damage(player, dummy)
	var swings := 0
	while player.stamina > 0 and swings < 50:
		player.next_attack_tick = 0
		World.try_swing(player, Vector2i(-1, 0))
		swings += 1
	_check(player.stamina == 0 and swings == 13, "13 sword whiffs (8 each) empty 100 (%d swings, %d left)" % [swings, player.stamina])
	World.step()
	_check(World.is_winded(player), "out of stamina: winded")
	var step := World.step_ticks(player, Vector2i(-1, 0))
	_check(is_equal_approx(step, player.move_ticks * 1.5), "a step takes 1.5 times the ticks (%.2f of %.2f)" % [step, player.move_ticks])
	var tired := _blow_damage(player, dummy)
	_check(tired == maxi(1, roundi(fresh * 0.5)), "a blow does half (%d, fresh %d)" % [tired, fresh])
	_clear(player)
	World.put_item(player, player, Player.LEFT_HAND, World.items.mint("shield", "built"))
	player.stamina = 10
	_check(not World.bash_ready(player), "a shield and 10 stamina, but winded: no bash")
	player.stamina = 0
	var at := World.tick
	while player.stamina == 0 and World.tick < at + 40:
		World.step()
	_check(World.tick - at > 20, "regen waits out winded_regen_delay, 20 ticks (%d)" % (World.tick - at))
	while player.stamina < 24:
		World.step()
	_check(World.is_winded(player), "still winded at %d" % player.stamina)
	while player.stamina < 25:
		World.step()
	World.step()
	_check(not World.is_winded(player), "back at 25: not winded (%d)" % player.stamina)


func _test_monsters_switch() -> void:
	print("\n== a monster pays only by its row's swing_stamina ==")
	var e := _build(["#######", "#Pm...#", "#######"])
	var player: GridEntity = e["P"][0]
	var dummy: GridEntity = e["m"][0]
	dummy.max_stamina = 60
	dummy.stamina = 60
	dummy.attack_damage = 1
	_check(not dummy.pays_swings, "a monster with no row: off")
	_blow(dummy, player)
	_check(dummy.stamina == 60, "its blow costs nothing (%d)" % dummy.stamina)
	dummy.pays_swings = true
	_blow(dummy, player)
	_check(dummy.stamina < 60, "switched on, it pays (%d)" % dummy.stamina)


func _test_telegraph_shapes() -> void:
	print("
== the telegraph's shapes (decision 602): a cone with a gap behind, a line, a ring ==")
	var o := Vector2i(10, 10)
	var cone := Telegraph.cells(Telegraph.cone(o, Vector2(1, 0), 2.0, 150.0))
	_check(o not in cone and Vector2i(11, 10) in cone and Vector2i(12, 11) in cone and Vector2i(9, 9) in cone,
			"a 2-cell cone of 150 degrees either side: ahead, the knight's cell, back corners (%d cells)" % cone.size())
	_check(Vector2i(9, 10) not in cone and Vector2i(8, 10) not in cone and Vector2i(12, 12) not in cone,
			"not straight behind (the gap), nor the far corner")
	_check(cone.size() == 16, "16 cells: 20 within reach, 4 in the gap behind (%d)" % cone.size())
	var line := Telegraph.cells(Telegraph.line(o, Vector2(1, 0), 8.0))
	_check(line.size() == 8 and Vector2i(18, 10) in line and Vector2i(19, 10) not in line, "a line of 8 east: 8 cells (%d)" % line.size())
	var slant := Telegraph.cells(Telegraph.line(o, Vector2(1, 1), 8.0))
	_check(Vector2i(11, 11) in slant and Vector2i(15, 15) in slant and Vector2i(16, 16) not in slant,
			"a slanting line: the diagonal cells within 8 (%s)" % [slant])
	var ring := Telegraph.cells({"kind": "ring", "origin": [10, 10], "facing": [1, 0], "length": 2.0, "inner": 1.5})
	_check(Vector2i(11, 10) not in ring and Vector2i(12, 10) in ring, "a ring: the inner cells left out")
	_check(Telegraph.cells({"kind": "blob", "origin": [0, 0], "facing": [1, 0], "length": 2}).is_empty()
			and Telegraph.cells({"kind": "cone", "origin": [0, 0], "facing": [0, 0], "length": 2}).is_empty(),
			"a shape that does not read: no cells")


func _test_telegraph_ground() -> void:
	print("
== on the ground: walls clip it, a line ends at one ==")
	var e := _build(["##########", "#P......##", "#....#...#", "##########"])
	var player: GridEntity = e["P"][0]
	var line := World.telegraph_cells(Telegraph.line(player.tile, Vector2(1, 0), 8.0))
	_check(line.size() == 6 and Vector2i(7, 1) in line and Vector2i(8, 1) not in line,
			"a line east from (1,1) stops at the wall at (8,1): 6 cells (%s)" % [line])
	var cone := World.telegraph_cells(Telegraph.cone(Vector2i(4, 1), Vector2(1, 0), 2.0, 150.0))
	_check(Vector2i(5, 2) not in cone and Vector2i(4, 0) not in cone and Vector2i(5, 1) in cone,
			"a cone keeps to the floor: no wall cell (%s)" % [cone])


func _test_telegraph_lifecycle() -> void:
	print("
== shown, landed or given up; its source gone ends it ==")
	var e := _build(["#######", "#Pm...#", "#######"])
	var dummy: GridEntity = e["m"][0]
	var started := []
	var ended := []
	var on_start := func(id: int, data: Dictionary) -> void: started.append([id, data])
	var on_end := func(id: int, landed: bool) -> void: ended.append([id, landed])
	World.telegraph_started.connect(on_start)
	World.telegraph_ended.connect(on_end)
	var id := World.telegraph(dummy, "spin", Telegraph.cone(dummy.tile, Vector2(-1, 0), 2.0, 150.0), 15)
	_check(id > 0 and started.size() == 1 and World.telegraphs().has(id), "shown: an id, told, kept")
	var data: Dictionary = started[0][1]
	var cells: Array = data["cells"]
	var want := World.telegraph_cells(data["shape"])
	_check(data["kind"] == "spin" and int(data["lands_tick"]) - int(data["from_tick"]) == 15 and cells.size() == want.size()
			and [Vector2i(1, 1).x, Vector2i(1, 1).y] in cells, "its data: kind, 15 ticks, the very cells it strikes (%s)" % [cells])
	World.end_telegraph(id, true)
	_check(ended == [[id, true]] and not World.telegraphs().has(id), "landed: told, gone")
	World.end_telegraph(id, true)
	_check(ended.size() == 1, "ended twice: told once")
	var second := World.telegraph(dummy, "throw", Telegraph.line(dummy.tile, Vector2(1, 0), 8.0), 12)
	World.despawn(dummy)
	_check(ended.back() == [second, false], "its source gone: given up (%s)" % [ended.back()])
	_check(World.telegraph(e["P"][0], "spin", {"kind": "cone"}, 15) == 0, "a shape that does not read: no telegraph")
	World.telegraph_started.disconnect(on_start)
	World.telegraph_ended.disconnect(on_end)


func _build(rows: Array[String]) -> Dictionary:
	World.reset()
	World.load_combat_rules(FileAccess.get_file_as_string(World.COMBAT_RULES))
	if _room != null:
		_room.free()
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
				spec["props"] = {"mass": 200.0, "max_hp": 500}
			var entity := EntityFactory.build(spec)
			if entity is Monster:
				entity.sight_range = 0
			_room.add_child(entity)
			World.spawn(entity, spawn[1])
			if kind == "m":
				entity.hp = 500
			out[kind].append(entity)
	return out


func _give(entity: GridEntity, id: String) -> void:
	World.put_item(entity, entity, Player.RIGHT_HAND, World.items.mint(id, "built"))


func _clear(entity: GridEntity) -> void:
	for slot in [Player.RIGHT_HAND, Player.LEFT_HAND]:
		if not entity.slots[slot].is_empty():
			World.items.end(World.take_item(entity, entity, slot), "gone")


## A blow struck now and resolved.
func _blow(attacker: GridEntity, target: GridEntity) -> void:
	attacker.next_attack_tick = 0
	attacker.next_move_tick = 0
	World.try_attack(attacker, target)
	World._resolve_hits()


## The damage a blow does now, the target's hp put back after.
func _blow_damage(attacker: GridEntity, target: GridEntity) -> int:
	var hp := target.hp
	var stamina := attacker.stamina
	_blow(attacker, target)
	var done := hp - target.hp
	target.hp = hp
	attacker.stamina = stamina
	return done


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
