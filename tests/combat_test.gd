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
	_test_telegraph_outline()
	_test_telegraph_ground()
	_test_telegraph_lifecycle()
	_test_spin()
	_test_spin_broken()
	_test_dropped_moves()
	_test_throw_and_charge()
	_test_bound_axe()
	_test_level_draugr_armed()
	_test_own_blow()
	_test_other_zone_waits()
	_test_cone_spread()
	_test_draw_held()
	_test_armour()

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

## Smooth telegraphs (Jeff: "draugr abilities should be in a smooth pattern
## like a cone similar to archery, not blocky tiles"): the drawn outline holds
## exactly the struck cells' centres, cones, rings and lines at every angle;
## only a centre within a hundredth of a cell of the drawn edge is let be.
func _test_telegraph_outline() -> void:
	print("
== the telegraph drawn smooth: a centre inside the outline is struck, outside is not ==")
	var shapes: Array[Dictionary] = []
	for turn in 72:
		var facing := Vector2.from_angle(turn * TAU / 72.0 + 0.013)
		for length in [1.0, 2.0, 5.0, 8.0, 12.0]:
			for half in [20.0, 45.0, 90.0, 150.0, 180.0]:
				shapes.append(Telegraph.cone(Vector2i.ZERO, facing, length, half))
			for width in [1, 3]:
				shapes.append(Telegraph.line(Vector2i.ZERO, facing, length, width))
	for axis: Vector2 in [Vector2(1, 0), Vector2(0, 1), Vector2(1, 1), Vector2(2, 1), Vector2(-1, 2)]:
		shapes.append(Telegraph.cone(Vector2i.ZERO, axis, 2.0, 150.0))
		shapes.append(Telegraph.cone(Vector2i.ZERO, axis, 3.0, 45.0))
		shapes.append(Telegraph.line(Vector2i.ZERO, axis, 8.0))
		shapes.append(Telegraph.line(Vector2i.ZERO, axis, 12.0))
	shapes.append({"kind": "ring", "origin": [0, 0], "facing": [1, 0], "length": 2.0, "inner": 1.5})
	shapes.append({"kind": "ring", "origin": [0, 0], "facing": [0, 1], "length": 5.0, "inner": 2.0})
	shapes.append({"kind": "ring", "origin": [0, 0], "facing": [1, 1], "length": 4.0, "inner": 2.0, "half_angle": 120.0})
	var wrong := []
	var close := 0
	for shape in shapes:
		var drawn := Telegraph.outline(shape)
		var struck := {}
		for cell in Telegraph.cells(shape):
			struck[cell] = true
		var reach := ceili(float(shape["length"])) + 2
		for y in range(-reach, reach + 1):
			for x in range(-reach, reach + 1):
				var centre := Vector2(x, y)
				if _edge_distance(drawn, centre) < 0.01:
					close += 1
					continue
				var inside := _crossed(drawn, centre) and centre != Vector2.ZERO
				if inside != struck.has(Vector2i(x, y)) and wrong.size() < 5:
					wrong.append([shape, Vector2i(x, y), inside])
	_check(wrong.is_empty(), "%d shapes at every angle: inside the outline exactly the struck centres (%d centres on an edge let be) %s" % [shapes.size(), close, wrong])
	var slant := Telegraph.cells(Telegraph.line(Vector2i.ZERO, Vector2.from_angle(0.5236), 8.0))
	var way := Vector2.from_angle(0.5236)
	var ordered := true
	var joined := true
	var banded := true
	for i in slant.size():
		banded = banded and absf(Vector2(-way.y, way.x).dot(Vector2(slant[i]))) < 0.5
		if i > 0:
			ordered = ordered and way.dot(Vector2(slant[i])) >= way.dot(Vector2(slant[i - 1]))
			joined = joined and slant.slice(0, i).any(func(c: Vector2i) -> bool: return (c - slant[i]).abs().x <= 1 and (c - slant[i]).abs().y <= 1)
	_check(ordered and joined and banded and slant.size() >= 7,
			"a line at 30 degrees: the centres within half a cell of it, in order along it, no gap (%s)" % [slant])

## Whether [param point] is inside [param polygon] by the even-odd rule
## (Geometry2D.is_point_in_polygon misreads some fine circles).
func _crossed(polygon: PackedVector2Array, point: Vector2) -> bool:
	var inside := false
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		if (a.y > point.y) != (b.y > point.y) and point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x:
			inside = not inside
	return inside


## How near [param point] is to [param polygon]'s edge.
func _edge_distance(polygon: PackedVector2Array, point: Vector2) -> float:
	var nearest := INF
	for i in polygon.size():
		var on := Geometry2D.get_closest_point_to_segment(point, polygon[i], polygon[(i + 1) % polygon.size()])
		nearest = minf(nearest, on.distance_to(point))
	return nearest



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

## The cone of flight (decisions 620, 669; combat's design): what a hold
## buys, 400 rolls at each of 0.5 s (the first step, 5 cells), 1.2 s (full
## draw, 9) and 3.3 s (the last band, 15) held. The miss is how far the line
## flown passes from the aimed line at the step's range, in cells (a third
## of the cone's half-angle times the range): 0.43, 0.21, then 0.35, the
## cone held at full draw's but the range longer.
func _test_cone_spread() -> void:
	print("
== the cone of flight: a snap shot scattered, full draw true, a long lob strays farther out (decisions 620, 669) ==")
	var e := _build(["#####", "#.P.#", "#####"])
	var host: GridEntity = e["P"][0]
	_give(host, "bow")
	World.put_item(host, host, Player.LEFT_HAND, World.items.mint("arrows", "built"))
	_check(World.try_stance(host, "draw"), "a bow drawn")
	var salt := World.shot_salt
	var means := []
	var inside := true
	var centred := true
	for held in [5, 12, 33]:
		host.raised_tick = World.tick - held
		var cone := World.spread_of(host)
		var cells := World.range_of(host)
		var miss := 0.0
		var signed := 0.0
		for each in 400:
			World.shot_salt = each
			var off := World.scatter(host, 0.5, cone) - 0.5
			inside = inside and absf(off) <= cone + 0.0001
			miss += absf(cells * sin(off))
			signed += off
		means.append(snappedf(miss / 400.0, 0.01))
		centred = centred and absf(signed / 400.0) < cone * 0.1
	World.shot_salt = salt
	var table := [0.43, 0.21, 0.35]
	var near := true
	for i in 3:
		near = near and absf(means[i] - table[i]) <= 0.05
	_check(near and means[0] > means[1] and means[2] > means[1],
			"the mean miss at 0.5, 1.2 and 3.3 s held, within 0.05 cells of the design's 0.43, 0.21, 0.35: least at full draw (%s)" % [means])
	_check(inside and centred, "every roll inside the cone, centred on the aim")
	var plain := Items.verb_of("bow").duplicate()
	plain.erase("spread")
	_check(is_zero_approx(Items.spread_at(plain, 60.0)) and World.scatter(host, 0.5, 0.0) == 0.5,
			"a bow verb without a spread: no cone, the aim flown")
	host.raised = ""

## The bow held (decision 669): at full draw or past it the holder's
## stamina drains, none coming back, and at 0 the arms give out (the bow let
## down, nothing loosed); below full draw nothing drains; the damage by the
## struck body's band past full draw.
func _test_draw_held() -> void:
	print("
== a bow held at full draw tires the arms; past it the reach grows, weaker the farther out (decision 669) ==")
	var e := _build(["####################", "#P.......m.....m...#", "####################"])
	var host: GridEntity = e["P"][0]
	var near: GridEntity = e["m"][0]  # 8 cells off.
	var far: GridEntity = e["m"][1]  # 14 cells off.
	_give(host, "bow")
	World.put_item(host, host, Player.LEFT_HAND, World.items.mint("arrows", "built"))
	var blow := host.attack_damage * float(Items.verb_of("bow")["damage"])
	near.max_hp = 100
	near.hp = 100
	far.max_hp = 100
	far.hp = 100
	World.shoot(host, 0.0, 5)
	_check(near.hp == 100 - roundi(blow * 1.6), "drawn to the last band, a body within 9 cells takes full strength (%d)" % (100 - near.hp))
	World.despawn(near)
	World.shoot(host, 0.0, 5)
	_check(far.hp == 100 - roundi(blow * 0.8), "one 14 cells out, in the last band, takes the least (669 amended: 0.8) (%d)" % (100 - far.hp))
	far.hp = 100
	World.shoot(host, 0.0, 4)
	_check(far.hp == 100, "drawn only to the second band (13 cells), the arrow falls short of it")
	_check(World.try_stance(host, "draw"), "drawn")
	host.stamina = 50
	for i in 5:
		World.step()
	_check(host.raised == "draw" and host.stamina >= 50, "below full draw nothing drains (%d)" % host.stamina)
	host.raised_tick = World.tick - 12
	var given := []
	var shots := []
	var on_given := func(by: GridEntity) -> void: given.append(by)
	var on_loose := func(by: GridEntity, _angle: float, _step: int) -> void: shots.append(by)
	World.draw_given_up.connect(on_given)
	World.loosed.connect(on_loose)
	host.stamina = 5
	World.step()
	_check(host.stamina == 4 and host.raised == "draw", "at full draw, 1 a tick (669 amended) (%d)" % host.stamina)
	for i in 3:
		World.step()
	_check(host.stamina == 1 and host.raised == "draw", "none comes back while held (%d)" % host.stamina)
	World.step()
	_check(host.stamina == 0 and host.raised == "" and given == [host] and shots.is_empty(),
			"at 0 the arms give out: the bow let down, nothing loosed (%s)" % [given])
	World.step()
	_check(host.winded, "and winded")
	World.draw_given_up.disconnect(on_given)
	World.loosed.disconnect(on_loose)


## Armour, combat's side (decision 622): the worn kind's deflect_shot after
## a shield, deflect_pierce on a backstab's or a reach verb's blow after
## the guard (at least 1 through), and breath at 1 - its kg / 100.
func _test_armour() -> void:
	print("
== armour turns arrows and thrusts, and plate breathes slower (decision 622, combat's side) ==")
	var e := _build(["######", "#mP..#", "######"])
	var dummy: GridEntity = e["m"][0]
	var host: GridEntity = e["P"][0]
	var through := {}
	for worn in ["", "leather_armour", "mail_armour", "plate_armour", "robes"]:
		_wear(host, worn)
		through[worn if not worn.is_empty() else "none"] = [World.armour_turns(host, 10, "deflect_shot"),
				World.armour_turns(host, 10, "deflect_pierce"), World.armour_turns(host, 1, "deflect_shot")]
	_check(through == {"none": [10, 10, 1], "leather_armour": [10, 10, 1], "mail_armour": [7, 8, 1],
			"plate_armour": [5, 7, 1], "robes": [10, 10, 1]},
			"of a 10-point shot and thrust: mail lets 7 and 8 through, plate 5 and 7, the rest all; a 1-point shot still 1 (%s)" % [through])
	dummy.slots = Items.tidy([], Items.CARRIED)  # Hands to hold it.
	World.set_slots(dummy, Items.tidy(["", "", "", "", "spear", ""], Items.CARRIED))
	dummy.attack_damage = 10
	host.max_hp = 500
	host.hp = 500
	_wear(host, "")
	var bare := _blow_damage(dummy, host)
	_wear(host, "plate_armour")
	var plated := _blow_damage(dummy, host)
	World.set_slots(dummy, Items.tidy(["", "", "", "", "sword", ""], Items.CARRIED))
	_wear(host, "")
	var cut := _blow_damage(dummy, host)
	_wear(host, "plate_armour")
	var cut_plated := _blow_damage(dummy, host)
	_check(plated == bare - roundi(bare * 0.3) and plated < bare and cut_plated == cut,
			"a spear's thrust in plate: %d of %d; a sword's cut is not a thrust: %d of %d" % [plated, bare, cut_plated, cut])
	var gained := {}
	for worn in ["", "mail_armour", "plate_armour"]:
		_wear(host, worn)
		host.stamina = 0
		host.winded = false
		host._world_note_exertion(World.tick - 100)
		var start := World.tick
		for i in 30:
			World.tick += 1
			World._regen_stamina()
		gained[worn if not worn.is_empty() else "none"] = host.stamina
		World.tick = start
	_check(gained == {"none": 60, "mail_armour": 54, "plate_armour": 48},
			"30 ticks' breath from empty: 60 bare, mail (10 kg) 54, plate (20 kg) 48 (%s)" % [gained])
	_wear(host, "")


## [param id] worn in [param entity]'s armour slot ("" takes it off).
func _wear(entity: GridEntity, id: String) -> void:
	if not entity.slots[Items.ARMOUR].is_empty():
		World.items.end(World.take_item(entity, entity, Items.ARMOUR), "gone")
	if not id.is_empty():
		World.put_item(entity, entity, Items.ARMOUR, World.items.mint(id, "built"))

## A boss's moves are tended by its own zone's step alone (603 amended;
## physics' finding, Jeff's "the draugr doesn't walk"): another awake zone,
## its tick far ahead, neither lands his spin nor strikes his wind-up nor
## hands him his axe; back in his own zone they go on as ever.
func _test_other_zone_waits() -> void:
	print("
== another zone's step leaves a boss's spin, wind-up and axe to his own ==")
	var e := _build(["#########", "#...P...#", "#..PmP..#", "#.......#", "#########"])
	var boss: GridEntity = e["m"][0]
	_boss(boss)
	var front: GridEntity = e["P"][1]
	var hp := front.hp
	_check(World.try_spin(boss), "he winds up his spin")
	var elsewhere := World.add_zone("combat_elsewhere")
	elsewhere.tick = World.tick + 1000
	var home := World.enter(elsewhere)
	World._tend_boss_moves()
	World.enter(home)
	World.zones.erase("combat_elsewhere")  # (Else step() steps only the zones it holds.)
	_check(World.boss_busy(boss) and World.telegraphs().size() == 1 and front.hp == hp,
			"the other zone's step, 1000 ticks on: his spin still winding, nothing struck")
	for i in 16:
		World.step()
	_check(not World.boss_busy(boss) and front.hp < hp, "his own zone's steps: it lands as ever (%d -> %d)" % [hp, front.hp])
	var e2 := _build(["#######", "#.Pm..#", "#######"])
	boss = e2["m"][0]
	_boss(boss)
	boss.blows = Monster.kinds()["draugr"]["blows"]
	World.set_slots(boss, Items.tidy(["", "", "", "", "battle_axe", ""], Items.CARRIED))
	var player: GridEntity = e2["P"][0]
	hp = player.hp
	_check(World.try_wind_up(boss, player) and not boss.wind_up.is_empty(), "he winds up a blow")
	elsewhere = World.add_zone("combat_elsewhere")
	elsewhere.tick = World.tick + 1000
	home = World.enter(elsewhere)
	World._tend_wind_ups()
	World.enter(home)
	_check(not boss.wind_up.is_empty() and player.hp == hp, "the other zone's step: still winding, nobody struck")
	World.cancel_wind_up(boss)
	World._axes[boss] = {"uid": 0, "cell": boss.tile + Vector2i(1, 0), "disarmed": true}
	home = World.enter(elsewhere)
	World._tend_disarmed()
	World.enter(home)
	_check(not World.boss_busy(boss) and bool(World._axes[boss]["disarmed"]), "disarmed beside his axe, not busy: the other zone's step does not arm him")
	World._axes.erase(boss)
	World.zones.erase("combat_elsewhere")



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


## 603 amended (3): a boss's move under way dropped (he yields or rests):
## nothing of it lands, its telegraph gone, his axe where it was.
func _test_dropped_moves() -> void:
	print("
== a move dropped as he yields: the spin, the throw and the charge land nothing (603 amended (3)) ==")
	var e := _build(["##############", "#P....m......#", "#.....P......#", "##############"])
	var boss: GridEntity = e["m"][0]
	_boss(boss)
	var far: GridEntity = e["P"][0]  # (1,1), down his row.
	var near: GridEntity = e["P"][1]  # (6,2), beside him.
	var hp := [far.hp, near.hp]
	boss._world_set_facing(Vector2i(0, 1))
	_check(World.try_spin(boss) and World.telegraphs().size() == 1, "he winds up the spin")
	World.step()
	World.drop_boss_move(boss)
	_check(not World.boss_busy(boss) and World.telegraphs().is_empty(), "dropped: not busy, its telegraph gone")
	for i in 20:
		World.step()
	_check(near.hp == hp[1] and not World.is_down(near), "nobody swept (%d)" % near.hp)
	boss.stamina = 100
	boss.winded = false
	boss.next_move_tick = 0
	_check(World.try_axe_throw(boss, far.tile), "he winds up the throw")
	World.drop_boss_move(boss)
	for i in 20:
		World.step()
	_check(far.hp == hp[0] and World.axe_state(boss)["where"] == "hand" and World.telegraphs().is_empty(),
			"dropped: nobody struck, the axe still in his hands")
	# A charge, roaring and then under way, dropped.
	World._relocate(near, Vector2i(7, 2))  # Out of the row.
	_check(World.try_axe_throw(boss, Vector2i(1, 1)), "thrown down the row")
	for i in 13:
		World.step()
	_check(World.axe_state(boss)["where"] == "ground", "it lies at %s" % World.axe_state(boss)["cell"])
	_check(World.try_axe_charge(boss), "he roars")
	World.drop_boss_move(boss)
	_check(not World.boss_busy(boss) and World.telegraphs().is_empty(), "dropped in the roar: not busy, no telegraph")
	var at := boss.tile
	for i in 10:
		World.step()
	_check(boss.tile == at, "and he does not run (%s)" % boss.tile)
	World._axes[boss]["disarmed"] = false
	_check(World.try_axe_charge(boss), "he roars again")
	var ran := false
	for i in 30:
		World.step()
		if boss.tile != at:
			ran = true
			break
	at = boss.tile
	World.drop_boss_move(boss)
	_check(ran and not World.boss_busy(boss) and not World._rushers.has(boss), "dropped under way: the rush over, not busy")
	for i in 10:
		World.step()
	_check(boss.tile == at and World.axe_state(boss)["where"] == "ground", "he stops where he was, the axe still lying (%s)" % boss.tile)


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
