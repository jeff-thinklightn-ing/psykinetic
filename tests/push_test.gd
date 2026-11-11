extends Node
## Scripted sim test. Builds small rooms, steps World by hand, checks outcomes.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.
##
## Numbers below assume the scene defaults: player mass 80 / strength 10 /
## stamina 100, imp mass 40 / hp 12 / strength 6 / stamina 60, crate mass 30 /
## hp 12, boulder mass 200, and levels/physics.json's (decision 592)
## shove_scale 0.1, slide_per_speed 1.5, impact_per_energy 0.075,
## restitution 0.2, momentum_scale 0.25. So a player's shove has force (the
## speed it gives) 10 * 80 * 0.1 / 40 = 2.0 on a rested imp, 3 cells, and
## 2.67 on a crate, and costs 5 + force * mass * 0.15 = 17 stamina; against
## a wall at once it hurts 0.075 * 1/2 * 40 * 2^2 = 6. Force is then
## scaled by the shover's stamina fraction. Regen is 2 per tick, starting 10
## ticks after the last exertion.

const SPECS := {
	"P": {"script": "res://sim/player.gd", "shape": "capsule"},
	"m": {"script": "res://sim/monster.gd", "shape": "capsule"},
	"c": {"script": "res://sim/pushable.gd", "shape": "cube"},
	"o": {"script": "res://sim/pushable.gd", "shape": "sphere",
		"props": {"mass": 200.0, "body_material": GridEntity.BodyMaterial.STONE}},
}
const NAMES := {"P": "Player", "m": "Imp", "c": "Crate", "o": "Boulder"}

var _failures := 0
var _room: Node2D
var _damage_log: Array[Dictionary] = []


const Walk := preload("res://tests/walk.gd")


func _ready() -> void:
	World.set_process(false)
	World.entity_damaged.connect(_on_entity_damaged)

	_test_shove_into_wall()
	_test_shove_monster_into_monster()
	_test_shove_crate_until_it_breaks()
	_test_push_onto_fire()
	_test_diagonals()
	_test_resolution_order()
	_test_mass_gate()
	_test_no_attack_mid_step()
	_test_no_friendly_fire()
	_test_stamina()
	_test_stun()
	_test_toss()
	_test_beside_own_companion()
	_test_charge_skim()

	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_shove_into_wall() -> void:
	print("\n== shove a monster into a wall ==")
	var e := _build([
		"#####",
		"#Pm##",
		"#####",
	])
	var imp: GridEntity = e["m"][0]
	_shove(e["P"][0], imp)
	_check(imp.tile == Vector2i(2, 1), "imp against the wall does not move")
	_check(_damage(imp, &"impact") == 6, "full force 2 -> impact 2 * 2 * 1.5 = 6 (got %d)" % _damage(imp, &"impact"))
	_check(imp.hp == 6, "imp hp 12 -> 6 (got %d)" % imp.hp)
	_check(_damage(e["P"][0], &"impact") == 0, "only the pushed entity takes wall impact")

	e = _build([
		"######",
		"#Pm.##",
		"######",
	])
	imp = e["m"][0]
	_shove(e["P"][0], imp)
	_check(imp.tile == Vector2i(3, 1), "imp with one free tile travels 1")
	_check(_damage(imp, &"impact") == 3, "remaining force 1 -> impact 3 (got %d)" % _damage(imp, &"impact"))


func _test_shove_monster_into_monster() -> void:
	print("\n== shove a monster into a monster ==")
	var e := _build([
		"########",
		"#Pmm...#",
		"########",
	])
	var first: GridEntity = e["m"][0]
	var second: GridEntity = e["m"][1]
	_shove(e["P"][0], first)
	_check(first.tile == Vector2i(2, 1), "first imp is stopped at once by the second")
	# A collision (decision 592): the second goes on at 1.2 * 40 * 2 / 80
	# = 1.2 (one tile), and the energy lost, 80 - 28.8, is shared: 2 each.
	_check(_damage(first, &"impact") == 2, "first imp takes impact 2 (got %d)" % _damage(first, &"impact"))
	_check(_damage(second, &"impact") == 2, "second imp takes impact 2 (got %d)" % _damage(second, &"impact"))
	_check(second.tile == Vector2i(4, 1), "second imp moves exactly one tile (at %s)" % second.tile)


func _test_shove_crate_until_it_breaks() -> void:
	print("\n== shove a crate into a wall until it breaks ==")
	var e := _build([
		"######",
		"#Pc..#",
		"######",
	])
	var player: GridEntity = e["P"][0]
	var crate: GridEntity = e["c"][0]
	var shoves := 0
	var hp_always_dropped := true
	while crate.spawned and shoves < 6:
		_walk_to(player, crate.tile + Vector2i.LEFT)
		var hp_before := crate.hp
		_shove(player, crate)
		shoves += 1
		hp_always_dropped = hp_always_dropped and crate.hp < hp_before
	_check(not crate.spawned, "crate broke")
	_check(shoves == 3, "took 3 shoves, each a little weaker as the player tires (took %d)" % shoves)
	_check(hp_always_dropped, "every shove into the wall cost the crate hp")
	_check(World.get_entity_at(Vector2i(4, 1)) == null, "broken crate leaves its tile empty")


func _test_push_onto_fire() -> void:
	print("\n== push a monster onto fire ==")
	var e := _build([
		"#######",
		"#Pm~..#",
		"#######",
	])
	var imp: GridEntity = e["m"][0]
	_shove(e["P"][0], imp)
	_check(imp.tile == Vector2i(3, 1), "imp stops on the fire tile, not past it (at %s)" % imp.tile)
	_check(_damage(imp, &"impact") == 3, "stopping on fire counts as a stop: impact 3 (got %d)" % _damage(imp, &"impact"))
	_check(_damage(imp, &"fire") == 2, "fire ticks the same tick: 2 (got %d)" % _damage(imp, &"fire"))
	_check(imp.hp == 7, "imp hp 12 - 3 - 2 = 7 (got %d)" % imp.hp)


func _test_diagonals() -> void:
	print("\n== eight directions ==")
	var e := _build([
		"####",
		"#m##",
		"#..#",
		"####",
	])
	# A monster walks the grid; a player walks free (703, step 2).
	var walker: GridEntity = e["m"][0]
	_check(not World.try_move(walker, Vector2i(1, 1)), "diagonal past a wall corner is refused")
	_check(World.find_path(Vector2i(1, 1), Vector2i(2, 2)).size() == 2, "A* goes around the corner in 2 steps")

	e = _build([
		"#####",
		"#mm.#",
		"#m..#",
		"#...#",
		"#####",
	])
	walker = e["m"][0]
	_check(World.find_path(Vector2i(1, 1), Vector2i(3, 3)).size() == 2, "A* uses diagonals: 2 steps to (3, 3)")
	_check(World.try_move(walker, Vector2i(1, 1)), "diagonal between two creatures is allowed")
	_check(walker.tile == Vector2i(2, 2), "the walker is at (2, 2)")
	var straight := World.step_ticks(walker, Vector2i(1, 0))
	_check(is_equal_approx(walker._move_duration, straight * World.DIAGONAL_TICK_SCALE),
			"the diagonal step took DIAGONAL_TICK_SCALE times a straight one (%s, %s)" % [walker._move_duration, straight])


func _test_resolution_order() -> void:
	print("\n== ascending id, stale pushes dropped ==")
	var e := _build([
		"#######",
		"#.P...#",
		"#Pm...#",
		"#.....#",
		"#######",
	])
	var low: GridEntity = e["P"][0]   # at (2, 1), id 1: shoves the imp down
	var high: GridEntity = e["P"][1]  # at (1, 2), id 2: shoves the imp right
	var imp: GridEntity = e["m"][0]
	World.order_shove(high, imp)
	World.order_shove(low, imp)
	World.step()
	_check(low.id < high.id, "ids ascend in spawn order")
	_check(imp.tile == Vector2i(2, 3), "lower id resolves first: imp went down (at %s)" % imp.tile)
	_check(_damage(imp, &"impact") == 3, "and hit the wall once: impact 3 (got %d)" % _damage(imp, &"impact"))


func _test_mass_gate() -> void:
	print("\n== mass gate applies to the player too ==")
	var e := _build([
		"#####",
		"#.Pm#",
		"#####",
	])
	var player: GridEntity = e["P"][0]
	var imp: Monster = e["m"][0]
	imp.sight_range = 7
	imp.lead_ticks = 0  # Its blow at once: the lead is monster_test's (338 amended (4)).
	World.step()
	_check(player.hp == 19, "imp attack lands: player hp 20 -> 19 (got %d)" % player.hp)
	_check(player.tile == Vector2i(2, 1), "imp (40) cannot move the player (80)")

	e = _build([
		"#####",
		"#.Pm#",
		"#####",
	])
	player = e["P"][0]
	var brute: Monster = e["m"][0]
	brute.sight_range = 7
	brute.lead_ticks = 0  # Its blow at once: the lead is monster_test's (338 amended (4)).
	brute.mass = 100.0
	brute.strength = 20  # An attack carries half force: 20 * 100 / 80 * 0.1 / 2 = 1.25.
	World.step()
	_check(player.hp < 20 and player.tile == Vector2i(2, 1),
			"a blow under knockback_min_force (1.25 < %.1f) hurts but does not move the player (at %s)" % [World.knockback_min_force, player.tile])

	e = _build([
		"#####",
		"#.Pm#",
		"#####",
	])
	player = e["P"][0]
	brute = e["m"][0]
	brute.sight_range = 7
	brute.lead_ticks = 0  # Its blow at once: the lead is monster_test's (338 amended (4)).
	brute.mass = 100.0
	brute.strength = 30  # 30 * 100 / 80 * 0.1 / 2 = 1.875, over the threshold.
	World.step()
	_check(player.tile == Vector2i(1, 1), "a heavy, strong monster knocks the player back one tile (at %s)" % player.tile)


func _test_no_friendly_fire() -> void:
	print("\n== players cannot attack or shove each other ==")
	var e := _build([
		"######",
		"#PP.m#",
		"######",
	])
	var first: GridEntity = e["P"][0]
	var second: GridEntity = e["P"][1]
	var imp: GridEntity = e["m"][0]
	first.owner_peer = 1
	second.owner_peer = 2
	World.order_shove(first, second)
	World.step()
	_check(second.tile == Vector2i(2, 1), "shoved player does not move (at %s)" % second.tile)
	World.order_attack(first, second)
	World.step()
	_check(second.hp == second.max_hp, "attacked player takes no damage (hp %d)" % second.hp)
	_check(first.next_attack_tick == 0, "the refused hits cost no cooldown")
	_walk_to(second, Vector2i(3, 1))
	_shove(second, imp)
	# Its step just taken adds momentum (decision 592): 2.2 against the wall, 7.
	_check(_damage(imp, &"impact") == 7, "players can still shove monsters (impact %d)" % _damage(imp, &"impact"))


func _test_stamina() -> void:
	print("\n== stamina ==")
	var lane: Array[String] = [
		"##########",
		"#Pm......#",
		"##########",
	]
	var e := _build(lane)
	var player: GridEntity = e["P"][0]
	var imp: GridEntity = e["m"][0]
	_shove(player, imp)
	var full_tiles := imp.tile.x - 2
	_check(full_tiles == 3, "full-stamina shove throws a rested imp 3 tiles (got %d)" % full_tiles)
	_check(player.stamina == 83, "that shove cost 5 + 2.0 * 40 * 0.15 = 17 (stamina %d)" % player.stamina)
	for i in World.stamina_regen_delay:
		World.step()
	_check(player.stamina == 83, "nothing comes back for %d ticks after a shove (stamina %d)" % [World.stamina_regen_delay, player.stamina])
	World.step()
	_check(player.stamina == 85, "then a resting tick regains 2 (stamina %d)" % player.stamina)
	World.free_input(player, Vector2(1, 0), World.TICK_DT)
	World.step()
	_check(player.free_pos.x > 1.0 and player.stamina == 87, "a walking tick regains 2 as well (stamina %d)" % player.stamina)

	e = _build(lane)
	player = e["P"][0]
	imp = e["m"][0]
	player.stamina = 50
	_shove(player, imp)
	var low_tiles := imp.tile.x - 2
	_check(low_tiles == 1, "at half stamina the force is half: 1 tile (got %d)" % low_tiles)
	_check(low_tiles < full_tiles, "a low-stamina shove throws a monster less far than a full one")
	_check(player.stamina == 39, "and a weaker shove costs less: 5 + 1.0 * 40 * 0.15 = 11 (stamina %d)" % player.stamina)

	e = _build(lane)
	player = e["P"][0]
	imp = e["m"][0]
	player.stamina = 4
	_shove(player, imp)
	_check(player.stamina == 0, "a shove it cannot afford spends everything that was left (stamina %d)" % player.stamina)

	e = _build([
		"#####",
		"#Pm.#",
		"#####",
	])
	player = e["P"][0]
	imp = e["m"][0]
	player.stamina = 0
	_shove(player, imp)
	_check(imp.tile == Vector2i(2, 1), "a shove from 0 stamina has no force")

	e = _build([
		"######",
		"#Po..#",
		"######",
	])
	player = e["P"][0]
	var boulder: GridEntity = e["o"][0]
	_shove(player, boulder)
	_check(boulder.tile == Vector2i(2, 1), "shoving a boulder moves nothing")
	_check(player.stamina == 83, "but still costs stamina: 5 + 0.4 * 200 * 0.15 = 17 (stamina %d)" % player.stamina)

	e = _build(lane)
	player = e["P"][0]
	imp = e["m"][0]
	imp.stamina = 0
	_shove(player, imp)
	var exhausted_tiles := imp.tile.x - 2
	_check(exhausted_tiles == 6, "an imp at 0 stamina counts as half its mass: thrown 6 tiles (got %d)" % exhausted_tiles)
	_check(exhausted_tiles > full_tiles, "a monster at 0 stamina is pushed farther than one at full")

	e = _build([
		"#####",
		"#Pm##",
		"#####",
	])
	player = e["P"][0]
	imp = e["m"][0]
	imp.max_hp = 0  # Indestructible, so it stays put to be shoved again.
	var shoves := 0
	while player.stamina > 0 and shoves < 30:
		_shove(player, imp)
		shoves += 1
	_check(shoves == 10, "shoving nonstop empties a full bar in 10 ever-cheaper shoves (took %d)" % shoves)

	# Chase one imp down a long lane, shoving it again each time.
	e = _build([
		"###############",
		"#Pm...........#",
		"###############",
	])
	player = e["P"][0]
	imp = e["m"][0]
	var thrown: Array[int] = []
	for i in 6:
		_walk_to(player, imp.tile + Vector2i.LEFT)
		var before := imp.tile.x
		_shove(player, imp)
		thrown.append(imp.tile.x - before)
	# Each shove comes straight off a walk, its momentum keeping the last
	# one moving (decision 592). A free body's walk up (703, step 2) carried
	# the fourth one cell farther than the grid's step did; with a blow's
	# stand now BLOW_STAND_TICKS (Jeff's lost clicks) the walk up differs
	# and it is the grid's again, (3, 2, 2, 1, 1, 1): fading either way.
	_check(thrown == [3, 2, 2, 1, 1, 1], "knockback fades shove by shove instead of cutting out: %s" % [thrown])


func _test_stun() -> void:
	print("\n== collisions stun ==")
	# Thrown one tile into a wall with force 1 left: stunned 4 + 3 = 7 ticks.
	var e := _build([
		"#####",
		"#Pm.#",
		"#####",
	])
	var player: GridEntity = e["P"][0]
	var imp: Monster = e["m"][0]
	imp.sight_range = 7  # It wants to walk straight back to the player.
	_shove(player, imp)
	_check(imp.tile == Vector2i(3, 1) and World.is_stunned(imp), "imp thrown into a wall is stunned")
	_check(imp.stunned_until_tick == World.tick + 9, "for its 2-tick slide + 7, longer than 4 + 1 * 3 (until %d, now %d)" % [imp.stunned_until_tick, World.tick])
	for i in 8:
		World.step()
	_check(imp.tile == Vector2i(3, 1), "it does not move while stunned (tick %d, at %s)" % [World.tick, imp.tile])
	World.step()
	_check(imp.tile == Vector2i(2, 1), "and walks back the tick the stun ends (tick %d, at %s)" % [World.tick, imp.tile])

	e = _build([
		"########",
		"#Pm..m.#",
		"########",
	])
	var first: GridEntity = e["m"][0]
	var second: GridEntity = e["m"][1]
	_shove(e["P"][0], first)
	_check(first.tile == Vector2i(4, 1) and second.tile == Vector2i(5, 1), "first imp flies two tiles and stops against the second")
	_check(_damage(first, &"impact") == 0 and _damage(second, &"impact") == 0, "with 0.67 speed left, the collision does no damage")
	_check(World.is_stunned(first) and World.is_stunned(second), "but both imps are stunned")
	_check(first.stunned_until_tick == World.tick + 11, "the thrown one for its 4-tick slide + 7 (until %d, now %d)" % [first.stunned_until_tick, World.tick])
	_check(second.stunned_until_tick == World.tick + 6, "the one run into for 4 + 3 x 0.67 ticks (until %d, now %d)" % [second.stunned_until_tick, World.tick])
	_check(not World.is_stunned(e["P"][0]), "the shover is not")

	# Knocked back across open ground, hitting nothing: still stunned a beat.
	e = _build([
		"#########",
		"#Pm.....#",
		"#########",
	])
	imp = e["m"][0]
	imp.sight_range = 7
	_shove(e["P"][0], imp)
	var slid := imp.tile.x - 2
	_check(slid > 0 and _damage(imp, &"impact") == 0, "an imp shoved across open ground slides %d, unhurt" % slid)
	var ticks := World.push_slide_ticks(slid) + World.knockback_stun_ticks
	_check(imp.stunned_until_tick == World.tick + ticks,
			"and is stunned for its slide + %d (until %d, now %d)" % [World.knockback_stun_ticks, imp.stunned_until_tick, World.tick])
	var at := imp.tile
	for i in ticks - 1:
		World.step()
	_check(imp.tile == at, "it stays put while stunned (at %s)" % imp.tile)
	World.step()
	_check(imp.tile == at + Vector2i.LEFT, "and walks back the tick the stun ends (at %s)" % imp.tile)

	e = _build([
		"######",
		"#Pc.##",
		"######",
	])
	_shove(e["P"][0], e["c"][0])
	_check(not World.is_stunned(e["c"][0]), "crates are not stunned")


func _test_toss() -> void:
	print("\n== toss: a shove aimed in a chosen direction ==")
	var room: Array[String] = [
		"#######",
		"#.....#",
		"#..m..#",
		"#..P..#",
		"#######",
	]
	var e := _build(room)
	var player: GridEntity = e["P"][0]
	var imp: GridEntity = e["m"][0]
	World.order_shove(player, imp, Vector2i(1, 0))
	World.step()
	_check(imp.tile == Vector2i(5, 2), "imp north of the player is tossed east, not north (at %s)" % imp.tile)
	_check(player.stamina == 83, "a toss costs what a shove costs (stamina %d)" % player.stamina)
	_check(player.facing == Vector2i(0, -1), "the player still faces the imp it threw")
	_check(imp.tossed, "and the views are told it was a toss")

	e = _build(room)
	player = e["P"][0]
	imp = e["m"][0]
	World.order_shove(player, imp, Vector2i(-1, -1))
	World.step()
	_check(imp.tile == Vector2i(2, 1), "a diagonal toss works too (at %s)" % imp.tile)

	e = _build(room)
	player = e["P"][0]
	imp = e["m"][0]
	World.order_shove(player, imp)
	var before := Vector2(imp.facing).normalized()
	World.step()
	_check(imp.tile.y < 2 and not imp.tossed, "a plain shove straight on is a push back, not a toss (at %s)" % imp.tile)
	for i in 4:
		imp._process(0.05)
	_check(imp.shown_facing().dot(before) > 0.99,
			"knocked along its slide, it does not turn to face it (shows %s, faced %s)" % [imp.shown_facing(), before])

	e = _build(room)
	player = e["P"][0]
	imp = e["m"][0]
	World.order_shove(player, imp, Vector2i(0, 1))
	World.step()
	_check(imp.tile == Vector2i(3, 2), "tossed back over the thrower with a wall behind: nowhere to land, refused")
	_check(player.stamina == 100, "and that refused toss costs nothing (stamina %d)" % player.stamina)

	var deep_room: Array[String] = [
		"#######",
		"#.....#",
		"#..m..#",
		"#..P..#",
		"#.....#",
		"#.....#",
		"#######",
	]
	e = _build(deep_room)
	player = e["P"][0]
	imp = e["m"][0]
	World.order_shove(player, imp, Vector2i(0, 1))
	World.step()
	_check(imp.tile == Vector2i(3, 5), "with room behind, the imp goes over the thrower's head: 2 tiles to clear, 1 more (at %s)" % imp.tile)
	_check(player.tile == Vector2i(3, 3) and World.is_occupancy_consistent(), "the thrower stays put and occupancy is consistent")
	_check(player.stamina == 83, "it costs what a shove costs (stamina %d)" % player.stamina)

	e = _build(deep_room)
	player = e["P"][0]
	imp = e["m"][0]
	imp.mass = 70.0
	World.order_shove(player, imp, Vector2i(0, 1))
	World.step()
	_check(imp.tile == Vector2i(3, 2), "an imp too heavy to throw two tiles cannot be lifted overhead")
	_check(player.stamina < 100, "but the attempt is paid for (stamina %d)" % player.stamina)

	e = _build([
		"#######",
		"#.....#",
		"#..m..#",
		"#..P..#",
		"#..m..#",
		"#######",
	])
	player = e["P"][0]
	imp = e["m"][0]
	World.order_shove(player, imp, Vector2i(0, 1))
	World.step()
	_check(imp.tile == Vector2i(3, 2) and player.stamina == 100, "something standing behind the thrower also blocks it, for free")

	e = _build(room)
	player = e["P"][0]
	imp = e["m"][0]
	World.order_shove(player, imp, Vector2i(2, 0))
	World.step()
	_check(imp.tile == Vector2i(3, 2) and player.action_order == GridEntity.Order.NONE, "a direction that is not a grid step is ignored")


## 688 amended (11), playtest's bear run (companions' brk_1, tick 168): a player walks through
## his own companion, so his free body may stand in her cell's edge; a push's slide meets her
## as solid, and the shove out of her cell was read as meeting her, behind him: the push
## bounced between them, three impacts each in one tick. Now a slide stops only when held back
## along its way, and a body a push already set moving, met again, ends its chain unhurt.
func _test_beside_own_companion() -> void:
	print("\n== 688 amended (11): a push beside his own companion meets her once, or not at all ==")
	var rows: Array[String] = ["m.......", "...P....", "........"]
	# His centre at 2.55 in (3, 1), 0.25 into her cell's edge: deeper than a slide's first
	# substep (FREE_SUBSTEP 0.2) carries him, so that substep shoves him out of her cell.
	# Pushed away from her, his edge in her cell: the old reading named her, behind him.
	var e := _build(rows)
	var player: Player = e["P"][0]
	var her := _companion_of(player, Vector2i(2, 1))
	player.free_pos = Vector2(2.55, 1)
	World._test_overlap_stops = true
	var slid := World._push(e["m"][0], player, Vector2(1, 0), 2.0)
	World._test_overlap_stops = false
	_check(not slid.is_empty() and slid[0]["stopped_by"] == her.name,
			"before the mend: pushed east off her edge, he was stopped by her behind him (%s)" % [slid[0]["stopped_by"] if not slid.is_empty() else "-"])
	e = _build(rows)
	player = e["P"][0]
	her = _companion_of(player, Vector2i(2, 1))
	player.free_pos = Vector2(2.55, 1)
	slid = World._push(e["m"][0], player, Vector2(1, 0), 2.0)
	_check(slid.size() == 1 and slid[0]["stopped_by"] == "nothing (force spent)" and player.tile.x > 3,
			"pushed east off her edge: he slides on, nothing named (%s, to %s)" % [slid[0]["stopped_by"] if not slid.is_empty() else "-", player.tile])
	_check(_hits(player) == 0 and _hits(her) == 0, "and neither takes impact (%d, %d)" % [_hits(player), _hits(her)])
	# Pushed toward her, into her: the honest knock-on, once.
	e = _build(rows)
	player = e["P"][0]
	her = _companion_of(player, Vector2i(4, 1))
	player.free_pos = Vector2(3.25, 1)
	slid = World._push(e["m"][0], player, Vector2(1, 0), 2.0)
	_check(slid.size() == 2 and slid[0]["stopped_by"] == her.name and slid[1]["body"] == her and her.tile.x > 4,
			"pushed east into her: he meets her, she slides on (%s)" % [slid.map(func(s: Dictionary) -> String: return "%s %s" % [s["body"].name, s["stopped_by"]])])
	_check(_hits(player) <= 1 and _hits(her) <= 1, "each hurt once at most (%d, %d)" % [_hits(player), _hits(her)])
	# Three in a row, the bear's swipe on her, his edge in her cell: she knocks him on.
	for old_reading in [true, false]:
		e = _build(rows)
		player = e["P"][0]
		her = _companion_of(player, Vector2i(2, 1))
		player.free_pos = Vector2(2.55, 1)
		World._test_overlap_stops = old_reading
		slid = World._push(e["m"][0], her, Vector2(1, 0), 3.73)
		World._test_overlap_stops = false
		var blow: int = slid[0]["impact"] if not slid.is_empty() else -1
		var how := "the overlap read as a stop" if old_reading else "as it is now"
		_check(slid.size() == 2 and slid[0]["stopped_by"] == player.name and slid[1]["body"] == player,
				"%s: swiped into him, she knocks him on, and the chain ends there (%s)" % [how, slid.map(func(s: Dictionary) -> String: return "%s %s" % [s["body"].name, s["stopped_by"]])])
		_check(blow > 0 and _hits(her) == 1 and _hits(player) == 1 and _damage(her, &"impact") == blow and _damage(player, &"impact") == blow,
				"%s: each takes the one blow's impact once (%d: her %d, him %d)" % [how, blow, _damage(her, &"impact"), _damage(player, &"impact")])
		if old_reading:
			_check(slid.size() == 2 and slid[1]["stopped_by"] == "%s (met again)" % her.name and slid[1]["impact"] == 0,
					"the overlap read as a stop: she, met again, ends the chain, and the end hurts nobody (%s)" % [slid[1]["stopped_by"] if slid.size() > 1 else "-"])


## [param player]'s own companion, standing still at [param tile].
## 688 amended (14): a charge moves only bodies in its told cells. A rush along row 0 passes
## (3, 0) while a standing free body's centre is in (3, 1), 0.15 from (3, 0)'s square, its circle
## over that cell's edge: not shoved off the rushing body's cell, nor struck. Its cell taken under
## his centre still stops it, as a body met.
func _test_charge_skim() -> void:
	print("\n== 688 amended (14): a charge brushing a free body's edge neither shoves nor strikes it ==")
	var e := _build(["m.......", "...P....", "........"])
	var player: Player = e["P"][0]
	var by: GridEntity = e["m"][0]
	player.free_pos = Vector2(3.0, 0.65)
	var least := player.free_pos.y
	var most := player.free_pos.y
	var passed := false
	World.rush(by, Vector2(1, 0), 6)
	for i in 14:
		# Walking slowly east beside its line, as wire3_4's player was: his tend meets the cell.
		World.free_input(player, Vector2(0.15, 0), World.TICK_DT)
		World.step()
		least = minf(least, player.free_pos.y)
		most = maxf(most, player.free_pos.y)
		passed = passed or by.tile.x > 3
	_check(passed and absf(least - 0.65) < 0.001 and absf(most - 0.65) < 0.001 and _hits(player) == 0,
			"walking beside it, the charge passed (%s) and his centre held at y %.2f-%.2f, unhurt (%d hits)" % [by.tile, least, most, _hits(player)])
	# Its centre in a told cell: the charge meets him there, as ever.
	e = _build(["m.......", "...P....", "........"])
	player = e["P"][0]
	by = e["m"][0]
	player.free_pos = Vector2(3.0, 0.45)
	World._free_claim(player, 2.5)
	World.rush(by, Vector2(1, 0), 6)
	for i in 14:
		World.step()
	_check(by.tile.x <= 2 or player.free_pos.y > 0.65,
			"his centre in (3, 0), a told cell: the charge meets him there (it at %s, he at %s)" % [by.tile, player.free_pos])


func _companion_of(player: Player, tile: Vector2i) -> Companion:
	var her := EntityFactory.build({"script": "res://sim/companion.gd", "shape": "capsule", "name": "Rhea", "props": {"max_hp": 20}}) as Companion
	her.acts = false
	_room.add_child(her)
	World.spawn(her, tile)
	her.keeper = player
	return her


## How many times [param entity] took impact.
func _hits(entity: GridEntity) -> int:
	return _damage_log.filter(func(entry: Dictionary) -> bool: return entry.entity == entity and entry.cause == &"impact").size()


func _test_no_attack_mid_step() -> void:
	print("\n== no attacking mid-step ==")
	var e := _build([
		"######",
		"#P.m.#",
		"######",
	])
	var player: GridEntity = e["P"][0]
	var imp: Monster = e["m"][0]
	imp.sight_range = 7
	imp.lead_ticks = 0  # Its blow at once: the lead is monster_test's (338 amended (4)).
	World.step()
	_check(imp.tile == Vector2i(2, 1), "imp steps next to the player on tick 1")
	for i in imp.move_ticks - 1:
		World.step()
	_check(player.hp == 20, "no damage while the imp is still crossing (tick %d, hp %d)" % [World.tick, player.hp])
	World.step()
	_check(player.hp == 20, "its step ended, it stands its settle first (338 amended (4): tick %d, hp %d)" % [World.tick, player.hp])
	for i in imp.settle_ticks:
		World.step()
	_check(player.hp == 19, "imp hits once it has stood its settle (tick %d, hp %d)" % [World.tick, player.hp])


# --- helpers ------------------------------------------------------------------

## A cell map: '#' a solid cell (nothing, walled on every side it meets
## floor; see Terrain.expand), '.' floor, '~' fire, 'P' player, 'm' imp (AI
## off), 'c' crate, 'o' boulder.
## Players spawn first so they hold the lowest ids.
func _build(rows: Array[String]) -> Dictionary:
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
			if symbol in ["#", ".", "~"]:
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
			var entity := EntityFactory.build(spec)
			if entity is Monster:
				entity.sight_range = 0  # Stands still unless a test turns it on.
			_room.add_child(entity)
			World.spawn(entity, spawn[1])
			out[kind].append(entity)
	return out


func _shove(attacker: GridEntity, target: GridEntity) -> void:
	while World.tick < maxf(attacker.next_attack_tick, attacker.next_move_tick):
		World.step()
	World.order_shove(attacker, target)
	World.step()


## Walks [param entity] to [param tile]: a player's free body pressed
## straight at its centre a tick at a time till it holds the cell (703, step
## 2: a player walks free), anything else ordered there on the grid.
func _walk_to(entity: GridEntity, tile: Vector2i) -> void:
	if entity is Player:
		for i in 40:
			if entity.tile == tile:
				return
			World.free_input(entity, (Vector2(tile) - entity.free_pos).normalized(), World.TICK_DT)
			World.step()
		return
	Walk.to(entity, tile, 40)  # A monster on the grid.


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
