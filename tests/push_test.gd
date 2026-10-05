extends Node
## Scripted sim test. Builds small rooms, steps World by hand, checks outcomes.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.
##
## Numbers below assume the scene defaults: player mass 80 / shove force 3,
## imp mass 40 / hp 12, crate mass 30 / hp 12, impact_per_force 2, ratio
## clamp 1.5. So a shoved imp or crate has ratio 1.5.

const SCENES := {
	"P": preload("res://entities/player.tscn"),
	"m": preload("res://entities/monster.tscn"),
	"c": preload("res://entities/pushable.tscn"),
}
const NAMES := {"P": "Player", "m": "Imp", "c": "Crate"}

var _failures := 0
var _room: Node2D
var _damage_log: Array[Dictionary] = []


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
	_check(_damage(imp, &"impact") == 9, "full force 3 -> impact 3 * 2 * 1.5 = 9 (got %d)" % _damage(imp, &"impact"))
	_check(imp.hp == 3, "imp hp 12 -> 3 (got %d)" % imp.hp)
	_check(_damage(e["P"][0], &"impact") == 0, "only the pushed entity takes wall impact")

	e = _build([
		"######",
		"#Pm.##",
		"######",
	])
	imp = e["m"][0]
	_shove(e["P"][0], imp)
	_check(imp.tile == Vector2i(3, 1), "imp with one free tile travels 1")
	_check(_damage(imp, &"impact") == 6, "remaining force 2 -> impact 6 (got %d)" % _damage(imp, &"impact"))


func _test_shove_monster_into_monster() -> void:
	print("\n== shove a monster into a monster ==")
	var e := _build([
		"########",
		"#Pm.m..#",
		"########",
	])
	var first: GridEntity = e["m"][0]
	var second: GridEntity = e["m"][1]
	_shove(e["P"][0], first)
	_check(first.tile == Vector2i(3, 1), "first imp travels 1 then is stopped by the second")
	_check(_damage(first, &"impact") == 6, "first imp takes impact 6 (got %d)" % _damage(first, &"impact"))
	_check(_damage(second, &"impact") == 6, "second imp takes impact 6 (got %d)" % _damage(second, &"impact"))
	_check(second.tile == Vector2i(5, 1), "second imp moves exactly one tile (at %s)" % second.tile)


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
	_check(shoves == 2, "took 2 shoves: 3 after sliding 2 tiles, then 9 flush (took %d)" % shoves)
	_check(hp_always_dropped, "every shove into the wall cost the crate hp")
	_check(_damage(crate, &"impact") == 12, "total impact equals crate hp 12 (got %d)" % _damage(crate, &"impact"))
	_check(World.get_entity_at(Vector2i(4, 1)) == null, "broken crate leaves its tile empty")


func _test_push_onto_fire() -> void:
	print("\n== push a monster onto fire ==")
	var e := _build([
		"#######",
		"#Pm.~.#",
		"#######",
	])
	var imp: GridEntity = e["m"][0]
	_shove(e["P"][0], imp)
	_check(imp.tile == Vector2i(4, 1), "imp stops on the fire tile, not past it (at %s)" % imp.tile)
	_check(_damage(imp, &"impact") == 3, "stopping on fire counts as a stop: impact 3 (got %d)" % _damage(imp, &"impact"))
	_check(_damage(imp, &"fire") == 2, "fire ticks the same tick: 2 (got %d)" % _damage(imp, &"fire"))
	_check(imp.hp == 7, "imp hp 12 - 3 - 2 = 7 (got %d)" % imp.hp)


func _test_diagonals() -> void:
	print("\n== eight directions ==")
	var e := _build([
		"####",
		"#P##",
		"#..#",
		"####",
	])
	var player: GridEntity = e["P"][0]
	_check(not World.try_move(player, Vector2i(1, 1)), "diagonal past a wall corner is refused")
	_check(World.find_path(Vector2i(1, 1), Vector2i(2, 2)).size() == 2, "A* goes around the corner in 2 steps")

	e = _build([
		"#####",
		"#Pm.#",
		"#m..#",
		"#...#",
		"#####",
	])
	player = e["P"][0]
	_check(World.find_path(Vector2i(1, 1), Vector2i(3, 3)).size() == 2, "A* uses diagonals: 2 steps to (3, 3)")
	_check(World.try_move(player, Vector2i(1, 1)), "diagonal between two creatures is allowed")
	_check(player.tile == Vector2i(2, 2), "player is at (2, 2)")
	_check(player.next_move_tick - World.tick == 3, "diagonal step takes 3 ticks (got %d)" % (player.next_move_tick - World.tick))
	_walk_to(player, Vector2i(3, 2))
	_check(player.next_move_tick - World.tick == 2, "orthogonal step takes 2 ticks (got %d)" % (player.next_move_tick - World.tick))


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
	_check(_damage(imp, &"impact") == 6, "and hit the wall once: impact 6 (got %d)" % _damage(imp, &"impact"))


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
	brute.mass = 100.0
	World.step()
	_check(player.tile == Vector2i(1, 1), "brute (100) knocks the player back one tile (at %s)" % player.tile)


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
	_check(_damage(imp, &"impact") == 9, "players can still shove monsters (impact %d)" % _damage(imp, &"impact"))


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
	World.step()
	_check(imp.tile == Vector2i(2, 1), "imp steps next to the player on tick 1")
	for i in imp.move_ticks - 1:
		World.step()
	_check(player.hp == 20, "no damage while the imp is still crossing (tick %d, hp %d)" % [World.tick, player.hp])
	World.step()
	_check(player.hp == 19, "imp hits on the tick its step ends (tick %d, hp %d)" % [World.tick, player.hp])


# --- helpers ------------------------------------------------------------------

## '#' wall, '.' floor, '~' fire, 'P' player, 'm' imp (AI off), 'c' crate.
## Players spawn first so they hold the lowest ids.
func _build(rows: Array[String]) -> Dictionary:
	World.reset()
	if _room != null:
		_room.free()
	_damage_log.clear()
	_room = Node2D.new()
	add_child(_room)

	var floor_tiles: Array[Vector2i] = []
	var wall_tiles: Array[Vector2i] = []
	var fire_tiles: Array[Vector2i] = []
	var spawns: Array[Array] = []
	for y in rows.size():
		for x in rows[y].length():
			var tile := Vector2i(x, y)
			floor_tiles.append(tile)
			match rows[y][x]:
				"#": wall_tiles.append(tile)
				"~": fire_tiles.append(tile)
				".": pass
				var symbol: spawns.append([symbol, tile])
	World.load_terrain(floor_tiles, wall_tiles, fire_tiles)

	var out := {}
	for kind: String in SCENES:
		out[kind] = []
		for spawn in spawns:
			if spawn[0] != kind:
				continue
			var entity: GridEntity = SCENES[kind].instantiate()
			if entity is Monster:
				entity.sight_range = 0  # Stands still unless a test turns it on.
			entity.name = "%s%d" % [NAMES[kind], out[kind].size() + 1]
			_room.add_child(entity)
			World.spawn(entity, spawn[1])
			out[kind].append(entity)
	return out


func _shove(attacker: GridEntity, target: GridEntity) -> void:
	while World.tick < maxi(attacker.next_attack_tick, attacker.next_move_tick):
		World.step()
	World.order_shove(attacker, target)
	World.step()


func _walk_to(entity: GridEntity, tile: Vector2i) -> void:
	World.order_move(entity, tile)
	for i in 40:
		if entity.tile == tile:
			return
		World.step()


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
