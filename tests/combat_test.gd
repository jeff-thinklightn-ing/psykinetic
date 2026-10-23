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
	_test_spin()
	_test_spin_broken()
	_test_throw_and_charge()
	_test_bound_axe()
	_test_level_draugr_armed()
	_test_own_blow()

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


## A boss for the moves (decision 603): the dummy made a 120 kg draugr's
## like, a two-handed weapon (the giant axe till items' battle axe), 100
## stamina it pays from, its blow 3.
func _boss(dummy: GridEntity) -> void:
	dummy.max_stamina = 100
	dummy.stamina = 100
	dummy.pays_swings = true
	dummy.attack_damage = 3
	dummy.strength = 6
	dummy.facing = Vector2i(-1, 0)
	dummy.slots = Items.tidy(["", "", "", "", "", ""], Items.CARRIED)  # Hands to hold it, as a kind's "wields".
	World.set_slots(dummy, Items.tidy(["", "", "", "", "giant_axe", ""], Items.CARRIED))


func _test_spin() -> void:
	print("\n== the spin: 1.5 s standing, the cone struck, the gap behind spared, then spent (decision 603) ==")
	var e := _build(["#########", "#...P...#", "#..PmP..#", "#.......#", "#########"])
	var boss: GridEntity = e["m"][0]
	_boss(boss)
	var front: GridEntity = e["P"][1]  # (3,2), the way he faces.
	var behind: GridEntity = e["P"][2]  # (5,2), straight behind.
	var side: GridEntity = e["P"][0]  # (4,1), beside.
	var hp := [front.hp, behind.hp, side.hp]
	_check(World.spin_targets(boss).size() == 2 and front in World.spin_targets(boss) and behind not in World.spin_targets(boss),
			"the cone holds the one ahead and the one beside, not the one behind")
	_check(World.try_spin(boss) and World.boss_busy(boss) and World.telegraphs().size() == 1, "he winds up: busy, a telegraph shown")
	_check(not World.try_spin(boss), "not twice at once")
	for i in 14:
		World.step()
	_check(front.hp == hp[0], "nothing yet at 14 ticks")
	World.step()
	World.step()
	_check(front.hp < hp[0] and side.hp < hp[1 + 1] and behind.hp == hp[1],
			"at 15: ahead and beside struck (%d, %d), behind spared (%d)" % [front.hp, side.hp, behind.hp])
	_check(World.is_down(front) and front.tile != Vector2i(3, 2), "the one ahead knocked down and thrown (%s)" % front.tile)
	_check(side.spawned and side.hp > 0 and side.hp <= 5, "the one beside, swept into the wall from full: left at a sliver (%d)" % side.hp)
	_check(boss.stamina <= 10 and World.is_winded(boss), "spent: %d stamina, winded" % boss.stamina)
	_check(not World.try_spin(boss), "winded: no spin")
	_check(World.telegraphs().is_empty(), "its telegraph over")


func _test_spin_broken() -> void:
	print("\n== a shield bash in the wind-up breaks the spin; a sword blow does not ==")
	var e := _build(["#########", "#..PmP..#", "#########"])
	var boss: GridEntity = e["m"][0]
	_boss(boss)
	var swordsman: GridEntity = e["P"][1]  # (5,1), behind him.
	var bearer: GridEntity = e["P"][0]  # (3,1), ahead.
	_give(swordsman, "sword")
	World.put_item(bearer, bearer, Player.LEFT_HAND, World.items.mint("shield", "built"))
	_check(World.try_spin(boss), "he winds up")
	_blow(swordsman, boss)
	World.step()
	_check(World.boss_busy(boss) and World.telegraphs().size() == 1, "a sword blow: still winding up")
	bearer.next_move_tick = 0
	_check(World.try_bash(bearer, boss), "the bearer bashes him")
	World._resolve_hits()
	var hp := bearer.hp
	for i in 20:
		World.step()
	_check(World.telegraphs().is_empty() and bearer.hp == hp and boss.stamina > 10,
			"the spin given up: nobody struck, not spent (%d)" % boss.stamina)


func _test_throw_and_charge() -> void:
	print("\n== the throw down its line, the axe lying before the one struck; the charge stopped, then made ==")
	var e := _build(["##############", "#P....m......#", "#............#", "##############"])
	var boss: GridEntity = e["m"][0]
	_boss(boss)
	var target: GridEntity = e["P"][0]  # (1,1), five cells west.
	_check(World.axe_line_hit(boss, target.tile) == target, "the line's first body: the target")
	var hp := target.hp
	_check(World.try_axe_throw(boss, target.tile) and boss.stamina == 60, "he winds up the throw: 40 stamina (%d)" % boss.stamina)
	for i in 13:
		World.step()
	var axe := World.axe_state(boss)
	_check(target.hp < hp and axe["where"] == "ground", "thrown: the target struck (%d -> %d), the axe on the ground at %s" % [hp, target.hp, axe["cell"]])
	_check(Vector2i(axe["cell"]).x >= 1 and World.ground_uids(axe["cell"]).has(int(axe["uid"])),
			"it lies before the one it struck, or at their feet (physics' hurl, 606)")
	# A body in the way: the charge is stopped, he is disarmed.
	var cell: Vector2i = axe["cell"]
	var blocker_at := boss.tile + Vector2i(-1, 0)
	World._relocate(target, blocker_at)
	_check(World.try_axe_charge(boss), "he roars and charges")
	for i in 12:
		World.step()
	_check(World.is_disarmed(boss) and World.axe_state(boss)["where"] == "ground" and not World.boss_busy(boss),
			"stopped by the body in his way: disarmed, the axe still lying")
	_check(not World.try_axe_charge(boss) and not World.try_axe_throw(boss, target.tile), "disarmed: no charge, no throw")
	# Again with the way clear (a fresh throw): he reaches it and takes it up.
	World._axes.erase(boss)
	World._relocate(target, Vector2i(12, 2))
	var uid := World.take_from_ground(cell, World.ground_uids(cell).find(int(axe["uid"])))
	World._hand_set(boss, Player.RIGHT_HAND, uid)
	boss.stamina = 100
	boss.winded = false
	_check(World.try_axe_throw(boss, Vector2i(1, 1)), "thrown again, nobody in the way")
	for i in 13:
		World.step()
	_check(World.axe_state(boss)["where"] == "ground", "it lies at the line's end (%s)" % World.axe_state(boss)["cell"])
	_check(World.try_axe_charge(boss), "he charges")
	for i in 20:
		World.step()
	_check(World.axe_state(boss)["where"] == "hand" and not World.is_disarmed(boss), "he reached it: the axe in his hands again")


## His thrown axe bound to him while it lies (603 amended; Jeff: "player
## can't pick up the axe mid fight, its magically bound to him"): nobody
## picks it up; disarmed, he is armed again once he walks back to it; his
## fight over, it comes back to his hands; gone, it is free.
func _test_bound_axe() -> void:
	print("
== his axe bound to him: nobody takes it up; disarmed till he walks back to it; recalled; free once he is gone ==")
	var e := _build(["###########", "#.P...m...#", "#.........#", "###########"])
	var boss: GridEntity = e["m"][0]
	_boss(boss)
	World.set_slots(boss, Items.tidy(["", "", "", "", "battle_axe", ""], Items.CARRIED))
	var player: GridEntity = e["P"][0]
	_check(World.try_axe_throw(boss, Vector2i(1, 1)), "he throws down the row")
	World._relocate(player, Vector2i(2, 2))  # Out of its line.
	for i in 13:
		World.step()
	var axe := World.axe_state(boss)
	var cell: Vector2i = axe["cell"]
	_check(axe["where"] == "ground" and World.axe_bound(int(axe["uid"])), "it lies at %s, bound to him" % cell)
	World._relocate(player, cell + Vector2i(0, 1))
	_check(not World.try_pick_up(player, cell) and World.ground_uids(cell).has(int(axe["uid"])) and player.slots[Player.RIGHT_HAND].is_empty(),
			"the player beside it cannot pick it up")
	var purse := World.items.mint("ration", "built")  # 601 amended: a coin purse is no thing now.
	World.zone.ground[cell] = PackedInt32Array([purse, int(axe["uid"])])  # A ration under his axe.
	_check(World.try_pick_up(player, cell) and player.slots.has("ration") and World.ground_uids(cell) == PackedInt32Array([int(axe["uid"])]),
			"a ration on the same cell is picked up past it; the axe stays")
	World._relocate(player, boss.tile + Vector2i(-1, 0))
	_check(World.try_axe_charge(boss), "he charges for it")
	for i in 12:
		World.step()
	_check(World.is_disarmed(boss), "the player in his way: disarmed")
	World._relocate(player, Vector2i(9, 2))
	for i in 3:
		World.step()
	_check(World.is_disarmed(boss) and World.axe_state(boss)["where"] == "ground", "away from it, he stays disarmed")
	World._relocate(boss, cell + Vector2i(1, 0))
	World.step()
	_check(not World.is_disarmed(boss) and World.axe_state(boss)["where"] == "hand", "walked back beside it: he takes it up, armed again")
	boss.stamina = 100
	boss.winded = false
	_check(World.try_axe_throw(boss, Vector2i(1, 1)), "thrown once more")
	for i in 13:
		World.step()
	World.recall_axe(boss)
	_check(World.axe_state(boss)["where"] == "hand" and not World.axe_bound(int(axe["uid"])), "his fight over: recalled to his hands")
	boss.stamina = 100
	_check(World.try_axe_throw(boss, Vector2i(1, 1)), "and thrown again")
	for i in 13:
		World.step()
	var last := World.axe_state(boss)
	World._forget_jobs(boss)  # As when he is killed and despawned.
	_check(not World.axe_bound(int(last["uid"])) and World.ground_uids(last["cell"]).has(int(last["uid"])), "he is gone: it lies free, loot")
	World._relocate(player, last["cell"] + Vector2i(0, 1))
	_check(World.try_pick_up(player, last["cell"]) and player.slots.has("battle_axe"), "and a player beside it picks it up")


## A draugr a level places is armed, looted and housed as a Monster is
## (Level._own_class): his class of his own once left him empty-handed, so
## the barrow's draugr had no axe to throw or charge for (v0.1.165).
func _test_level_draugr_armed() -> void:
	print("
== a level's draugr: his kind's battle axe in his hands, his home where he stands ==")
	var rows: Array[String] = ["#####", "#...#", "#####"]
	var markers := {Vector2i(2, 1): "monster_draugr", Vector2i(3, 1): "start"}
	var config := {"name": "draugr_arms_test", "legend": {"monster_draugr": "#5a6b5e"},
		"entities": [{"at": [2, 1], "facing": [1, 0], "idle": {"mode": "guard"}}]}
	var level := Level.parse(Level.image_from_rows(Terrain.expand(rows), markers, config), null, config)
	var draugr: Dictionary = {}
	for spec: Dictionary in level["entities"]:
		if spec.get("kind", "") == "draugr":
			draugr = spec
	var slots: PackedStringArray = draugr.get("props", {}).get("slots", PackedStringArray())
	_check(draugr.get("script", "") == "res://sim/draugr.gd", "his own class (%s)" % draugr.get("script", ""))
	_check(slots.size() == Items.CARRIED and slots[Items.RIGHT_HAND] == "battle_axe",
			"his kind's wields: the battle axe in his right hand (%s)" % slots)
	_check(draugr.get("home", null) == Vector2i(2, 1) and draugr.get("facing", null) == Vector2i(1, 0) and not draugr.get("idle", {}).is_empty(),
			"his home, facing and idle from the level, as a Monster's (%s, %s)" % [draugr.get("home", null), draugr.get("facing", null)])


## His kind's own blow with his axe (603 amended; the coordinator's (a)):
## the draugr's row makes his plain battle-axe blow a heavy strike, no
## knockdown (the spin floors alone); the axe in a player's hands is the
## catalog's.
func _test_own_blow() -> void:
	print("
== the draugr's own blow: his battle axe a heavy strike in his hands, the catalog's in a player's ==")
	var own: Dictionary = Monster.kinds()["draugr"].get("blows", {}).get("battle_axe", {})
	_check(own.get("kind", "") == "knockback" and not own.has("down_ticks") and is_equal_approx(float(own.get("speed", 0.0)), 2.2)
			and int(own.get("windup", 0)) == 8, "his row's blow, filled in as a catalog verb: %s" % own)
	var e := _build(["#####", "#PmP#", "#####"])
	var boss: GridEntity = e["m"][0]
	_boss(boss)
	boss.blows = Monster.kinds()["draugr"]["blows"]
	World.set_slots(boss, Items.tidy(["", "", "", "", "battle_axe", ""], Items.CARRIED))
	var player: GridEntity = e["P"][0]
	World.put_item(player, player, Player.RIGHT_HAND, World.items.mint("battle_axe", "built"))
	_check(World.blow_verb(boss) == own and World.windup_ticks(boss) == 8, "his blow is his row's: %s" % World.blow_verb(boss).get("kind"))
	_check(World.blow_verb(player) == Items.verb_of("battle_axe"), "a player's is the axe's own (%s)" % World.blow_verb(player).get("kind"))
	boss.blows = {}
	World.set_slots(boss, Items.tidy(["", "", "", "", "giant_axe", ""], Items.CARRIED))
	_check(World.blow_verb(boss) == Items.verb_of("giant_axe"), "a thing his row names no blow for: its own verb")
