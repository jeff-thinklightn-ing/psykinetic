extends Node
## How monsters fight: each kind its own way (Monster.TACTICS), each monster
## in its own manner (Monster._temper), a pack round its target rather than
## in a queue (Monster._pick_slot). Steps World by hand.

const SPECS := {
	"P": {"script": "res://sim/player.gd", "shape": "capsule", "props": {"max_hp": 999}},
	"m": {"script": "res://sim/monster.gd", "shape": "capsule"},
	"i": {"script": "res://sim/monster.gd", "shape": "capsule", "kind": "imp"},
	"b": {"script": "res://sim/monster.gd", "shape": "capsule", "kind": "brute"},
	"s": {"script": "res://sim/monster.gd", "shape": "capsule", "kind": "sneak"},
	"c": {"script": "res://sim/pushable.gd", "shape": "cube"},
	"r": {"script": "res://sim/animal.gd", "shape": "capsule", "kind": "rabbit"},
	"d": {"script": "res://sim/animal.gd", "shape": "capsule", "kind": "deer"},
	"D": {"script": "res://sim/animal.gd", "shape": "capsule", "kind": "stag"},
	"o": {"script": "res://sim/animal.gd", "shape": "capsule", "kind": "boar"},
	"w": {"script": "res://sim/animal.gd", "shape": "capsule", "kind": "wolf"},
	"a": {"script": "res://sim/monster.gd", "shape": "capsule", "kind": "imp"},
}
const NAMES := {"P": "Player", "m": "Monster", "i": "Imp", "b": "Brute", "s": "Sneak", "c": "Crate",
	"r": "Rabbit", "d": "Doe", "D": "Stag", "o": "Boar", "w": "Wolf", "a": "Archer"}

var _failures := 0
var _room: Node2D
var _damage_log: Array[Dictionary] = []


func _ready() -> void:
	World.set_process(false)
	World.entity_damaged.connect(func(entity: GridEntity, amount: int, source: GridEntity, cause: StringName) -> void:
		_damage_log.append({"entity": entity, "amount": amount, "source": source, "cause": cause, "tick": World.tick}))

	_test_temper()
	_test_weather()
	_test_surround()
	_test_dart()
	_test_windup()
	_test_charge()
	_test_flank()
	_test_hold_back()
	_test_reaction()
	_test_kind_saved()
	_test_facing()
	_test_guard()
	_test_wander()
	_test_patrol()
	_test_gather()
	_test_idle_pace()
	_test_home_after_a_fight()
	_test_roster()
	_test_tiers()
	_test_world_tick()
	_test_monsters_write_no_log()
	_test_look_skipped_far()
	_test_straight_beyond_view()
	_test_plans_per_step()
	_test_walk_round_held_ground()
	_test_sight_cone()
	_test_sight_by_light()
	_test_hearing()
	_test_noise_reach()
	_test_hunt()
	_test_leash()
	_test_roused()
	_test_door_openers()
	_test_hiding()
	_test_brute_breaks()
	_test_locks()
	_test_kinds_table()
	_test_temperament()
	_test_flee()
	_test_call_and_rout()
	_test_raid_march()
	_test_raid_beaten()
	_test_raid_takes()
	_test_noticing()
	_test_wild_kinds()
	_test_wild_prey()
	_test_wild_ears()
	_test_wild_scent()
	_test_wild_boar()
	_test_wild_wolf()
	_test_wild_remains()
	_test_lead_occupied()
	_test_raid_townsfolk()
	_test_charging()
	_test_archer()
	_test_shield()

	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_temper() -> void:
	print("\n== each monster its own manner, from its name; a kind its own body ==")
	var e := _build(["#######", "#iibm.#", "#.....#", "#######"])
	var imps: Array = e["i"]
	var a: Monster = imps[0]
	var b: Monster = imps[1]
	var manner := func(m: Monster) -> Array:
		return [snappedf(m.move_ticks, 0.001), m.attack_ticks, m.reaction_ticks, snappedf(m.boldness, 0.001), snappedf(m.pause_chance, 0.001)]
	_check(manner.call(a) != manner.call(b), "two imps differ (%s, %s)" % [manner.call(a), manner.call(b)])
	_check(a.tactic == Monster.Tactic.DART and absf(a.move_ticks - 4.0) <= 4.0 * Monster.PACE_SPREAD + 0.001
			and absi(a.attack_ticks - 10) <= Monster.COOLDOWN_SPREAD, "an imp darts, near the imp's pace and cooldown")
	var first: Array = manner.call(a)
	var again := _build(["#######", "#iibm.#", "#.....#", "#######"])
	_check(manner.call(again["i"][0]) == first, "the same imp (by name) the same each time it is made")
	var brute: Monster = again["b"][0]
	_check(brute.tactic == Monster.Tactic.HEAVY and brute.attack_damage == 2 and absf(brute.move_ticks - 5.0) <= 5.0 * Monster.PACE_SPREAD + 0.001,
			"a brute plods (%.2f) and hits for 2" % brute.move_ticks)
	var plain: Monster = again["m"][0]
	_check(plain.tactic == Monster.Tactic.PLAIN and plain.move_ticks == 4.0 and plain.attack_ticks == 10 and plain.reaction_ticks == 0,
			"a monster of no kind is as monsters were")


func _test_surround() -> void:
	print("\n== a pack surrounds its target, each to its own tile, rather than queueing ==")
	var e := _build([
		"###########",
		"#.........#",
		"#.........#",
		"#....P....#",
		"#.........#",
		"#.........#",
		"#bbbb.....#",
		"###########",
	])
	var player: GridEntity = e["P"][0]
	for brute: Monster in e["b"]:
		_bold(brute)
	var most := 0
	var sides := {}
	for i in 80:
		World.step()
		var beside := 0
		for imp: Monster in e["b"]:
			if World.are_adjacent(imp.tile, player.tile):
				beside += 1
				sides[imp.tile - player.tile] = true
		most = maxi(most, beside)
	_check(most == 4, "all four reach it at once (at most %d beside it)" % most)
	_check(sides.size() >= 4, "from all round it (%d sides)" % sides.size())


func _test_dart() -> void:
	print("\n== an imp darts in, strikes, darts out while it cools down, and comes back ==")
	var e := _build(["#########", "#.......#", "#..Pi...#", "#.......#", "#########"])
	var player: GridEntity = e["P"][0]
	var imp: Monster = e["i"][0]
	_bold(imp)
	var distances: Array[int] = []
	for i in 40:
		World.step()
		distances.append(World.distance(imp.tile, player.tile))
	var blows := _damage_log.filter(func(d: Dictionary) -> bool: return d["source"] == imp).size()
	var struck := _damage_log.filter(func(d: Dictionary) -> bool: return d["source"] == imp).map(func(d: Dictionary) -> int: return d["tick"])
	var first_out := distances.find(2, 1)
	_check(not struck.is_empty() and first_out - (int(struck[0]) - 1) >= Monster.DART_AFTER_TICKS,
			"its blow played out before it goes (struck on tick %s, out on %d)" % [struck[0] if not struck.is_empty() else "-", first_out + 1])
	var out := distances.find(2)
	var back := distances.find(1, maxi(out, 0))
	_check(blows >= 2, "it strikes again and again (%d blows)" % blows)
	_check(out > 0 and back > out, "out of reach between blows (%s)" % [distances])


func _test_windup() -> void:
	print("\n== a brute winds up its blow: it lands on whoever is still in reach ==")
	var e := _build(["#########", "#.......#", "#..Pb...#", "#.......#", "#########"])
	var player: GridEntity = e["P"][0]
	var brute: Monster = e["b"][0]
	_bold(brute)
	var wound := []
	brute.winding.connect(func(direction: Vector2i, ticks: int) -> void: wound.append([World.tick, direction, ticks]))
	World.step()
	_check(wound.size() == 1 and _damage_log.is_empty(), "it winds up (%s), nothing yet" % [wound])
	for i in Monster.WINDUP_TICKS:
		World.step()
	var landed := _damage_log.filter(func(d: Dictionary) -> bool: return d["source"] == brute and d["cause"] == &"attack")
	_check(landed.size() == 1 and int(landed[0]["amount"]) == 2 and int(landed[0]["tick"]) - int(wound[0][0]) == Monster.WINDUP_TICKS,
			"and %d ticks on it lands, for 2 (%s)" % [Monster.WINDUP_TICKS, landed])

	# Its target gone for good before the blow lands (a player who left),
	# another in sight: it swings at the air where the first stood, no error.
	e = _build(["#########", "#.......#", "#..Pb..P#", "#.......#", "#########"])
	brute = e["b"][0]
	_bold(brute)
	var air := []
	brute.swung.connect(func(direction: Vector2i) -> void: air.append(direction))
	World.step()
	var gone: GridEntity = e["P"][0]
	World.despawn(gone)
	gone.free()
	for i in Monster.WINDUP_TICKS:
		World.step()
	_check(air.size() == 1 and brute._windup.is_empty(), "its target freed while it winds up: it swings at the air (%s)" % [air])

	e = _build(["#########", "#.......#", "#..Pb...#", "#.......#", "#########"])
	player = e["P"][0]
	brute = e["b"][0]
	_bold(brute)
	var swings := []
	brute.swung.connect(func(direction: Vector2i) -> void: swings.append(direction))
	World.step()
	World.order_step(player, Vector2i(-1, 0), 0, false)
	for i in Monster.WINDUP_TICKS:
		World.step()
	_check(_damage_log.filter(func(d: Dictionary) -> bool: return d["source"] == brute).is_empty() and swings.size() == 1,
			"stepped out of reach in time: a whiff (%d swings, player at %s)" % [swings.size(), player.tile])

	e = _build(["#########", "#.......#", "#..Pb...#", "#.......#", "#########"])
	player = e["P"][0]
	brute = e["b"][0]
	_bold(brute)
	World.step()
	World.order_shove(player, brute)
	for i in Monster.WINDUP_TICKS:
		World.step()
	_check(_damage_log.filter(func(d: Dictionary) -> bool: return d["source"] == brute and d["cause"] == &"attack").is_empty(),
			"shoved off its feet mid wind-up: no blow (brute at %s)" % brute.tile)


func _test_charge() -> void:
	print("\n== a brute charges the last few tiles ==")
	var e := _build(["##############", "#P..........b#", "##############"])
	var brute: Monster = e["b"][0]
	_bold(brute)
	var pace := brute.move_ticks
	var charged := -1
	for i in 60:
		World.step()
		if brute.move_ticks < pace and charged < 0:
			charged = World.distance(brute.tile, e["P"][0].tile)
	_check(charged > 1 and charged <= Monster.CHARGE_RANGE, "far off it plods (%.2f); %d tiles off it charges" % [pace, charged])


func _test_flank() -> void:
	print("\n== a sneak works round to its target's back, and stabs harder there ==")
	var e := _build(["#########", "#.......#", "#...Ps..#", "#.......#", "#########"])
	var player: GridEntity = e["P"][0]
	var sneak: Monster = e["s"][0]
	_bold(sneak)
	player.facing = Vector2i(1, 0)  # Facing it.
	for i in 30:
		World.step()
		if not _damage_log.is_empty():
			break
	var blow: Dictionary = _damage_log[0] if not _damage_log.is_empty() else {}
	var from := sneak.tile - player.tile
	_check(not blow.is_empty() and Vector2(from).dot(Vector2(player.facing)) <= 0.0,
			"it strikes from its side or back (%s), not its front" % from)
	_check(not blow.is_empty() and int(blow["amount"]) == (2 if Vector2(from).dot(Vector2(player.facing)) < 0.0 else 1),
			"for %s (behind: 2)" % blow.get("amount"))


func _test_hold_back() -> void:
	print("
== a timid monster waits until another is at its target ==")
	var e := _build(["##########", "#........#", "#P...i...#", "#........#", "#........#", "##########"])
	var player: GridEntity = e["P"][0]
	var timid: Monster = e["i"][0]
	_bold(timid)
	timid.boldness = 0.0
	timid.temper = Monster.Temper.CAUTIOUS  # Waits for one other at its target.
	for i in 40:
		World.step()
	_check(World.distance(timid.tile, player.tile) >= 2 and World.distance(timid.tile, player.tile) <= Monster.HOLD_BACK_RANGE,
			"alone, it hangs back (%d tiles off)" % World.distance(timid.tile, player.tile))
	# Another comes (one there from the start would hear the standoff and
	# come to it: an occupied lead is walked to its side).
	var other := EntityFactory.build(SPECS["i"].merged({"name": "Imp2"})) as Monster
	_room.add_child(other)
	World.spawn(other, Vector2i(8, 4))
	_bold(other)
	other.sight_range = 12
	var joined := false
	for i in 60:
		World.step()
		if World.are_adjacent(timid.tile, player.tile):
			joined = true
	_check(joined, "with another at it, it joins in")


func _test_reaction() -> void:
	print("\n== a slow one takes a moment to act on what it sees ==")
	var e := _build(["##########", "#P.....i.#", "##########"])
	var imp: Monster = e["i"][0]
	_bold(imp)
	imp.reaction_ticks = 5
	var from := imp.tile
	for i in 5:
		World.step()
	_check(imp.tile == from, "five ticks sizing it up")
	for i in 3:
		World.step()
	_check(imp.tile != from, "then it comes")


func _test_kind_saved() -> void:
	print("\n== a monster's kind is saved with it (for one that is no level entity) ==")
	var e := _build(["######", "#b.s.#", "######"])
	var saving: Array[GridEntity] = []
	saving.append_array(e["b"] + e["s"])
	var entries := Snapshot._entries(saving)
	_check(entries.size() == 2 and entries[0].get("kind") == "brute" and entries[1].get("kind") == "sneak", "saved: %s" % [entries.map(func(x: Dictionary) -> Variant: return x.get("kind"))])
	var parsed := Snapshot._parse_entry(JSON.parse_string(JSON.stringify(entries[0])))
	_check(parsed["spec"].get("kind") == "brute", "and loaded")


func _test_facing() -> void:
	print("\n== a monster's facing: its level entry's, or one of its own; saved and synced ==")
	var config := {"entities": [
		{"at": [2, 1], "facing": [1, -1], "idle": {"mode": "patrol", "route": [[2, 1], [5, 1]], "loop": false}},
		{"at": [4, 1], "idle": "nonsense"},
	]}
	var markers := {Vector2i(2, 1): "monster_brute", Vector2i(4, 1): "monster_imp"}
	var layout := Level.image_from_rows(["#############", "#.#.#.#.#.#.#", "#############"], markers)
	Level.register("facing_test", layout, null, config)
	var level := Level.load_level("facing_test")
	Level.unregister("facing_test")
	var specs: Array = level["entities"]
	var brute: Dictionary = specs[0]
	var imp: Dictionary = specs[1]
	_check(brute.get("facing") == Vector2i(1, -1) and brute.get("home") == Vector2i(2, 1),
			"level.json's facing and the home tile in the spec (%s, %s)" % [brute.get("facing"), brute.get("home")])
	_check(brute.get("idle", {}).get("mode") == "patrol" and brute["idle"].get("route") == [Vector2i(2, 1), Vector2i(5, 1)]
			and brute["idle"].get("loop") == false, "and its idling, route and all (%s)" % [brute.get("idle")])
	_check(not imp.has("idle") and (level["warnings"] as Array).any(func(w: String) -> bool: return "unknown idle mode" in w),
			"an unknown idle mode is warned of and left out")
	var e := _build(["#######", "#b.i.i#", "#######"], {"b": {"facing": Vector2i(1, -1)}})
	var set_one: Monster = e["b"][0]
	_check(set_one.facing == Vector2i(1, -1) and set_one.home_facing == Vector2i(1, -1), "spawned facing it (%s)" % set_one.facing)
	var own: Array = e["i"].map(func(m: Monster) -> Vector2i: return m.facing)
	var entries := Snapshot._entries([set_one] as Array[GridEntity])
	var parsed := Snapshot._parse_entry(JSON.parse_string(JSON.stringify(entries[0])))
	_check(parsed["facing"] == Vector2i(1, -1), "saved and loaded with it (%s)" % parsed["facing"])
	var again := _build(["#######", "#b.i.i#", "#######"])
	_check(again["i"].map(func(m: Monster) -> Vector2i: return m.facing) == own and own.all(func(f: Vector2i) -> bool: return f in Monster.AROUND),
			"none set: one of its own, the same each time (%s)" % [own])
	var config_ok := false
	for node in again["b"][0].find_children("*", "MultiplayerSynchronizer", true, false):
		var replication := (node as MultiplayerSynchronizer).replication_config
		config_ok = replication.has_property(NodePath(".:facing")) and replication.property_get_spawn(NodePath(".:facing")) \
				and replication.has_property(NodePath(".:pose"))
	_check(config_ok, "replicated to every peer, from its spawn on (facing, and its pose)")


func _test_guard() -> void:
	print("\n== guard: stays put, faces its way, glances aside now and then and back ==")
	var e := _build(["#######", "#.....#", "#..b..#", "#.....#", "#######"], {"b": {"facing": Vector2i(1, 0)}})
	var brute: Monster = e["b"][0]
	var home := brute.tile
	var turns := {}
	var moved := false
	var back := 0
	for i in 400:
		World.step()
		moved = moved or brute.tile != home
		if brute.facing != Vector2i(1, 0):
			turns[brute.facing] = true
		elif not turns.is_empty():
			back += 1
	var steps := turns.keys().map(func(f: Vector2i) -> int: return absi(Monster.AROUND.find(f) - Monster.AROUND.find(Vector2i(1, 0))))
	_check(not moved, "never off its tile")
	_check(turns.size() >= 2 and steps.all(func(s: int) -> bool: return s >= 1 and s <= Monster.GLANCE_STEPS_MAX),
			"glances either way, no more than 90 degrees (%s)" % [turns.keys()])
	_check(back > 0, "and turns back to its way between")


func _test_wander() -> void:
	print("\n== wander: strolls to spots near home, pausing between ==")
	var e := _build(["###########", "#.........#", "#.........#", "#....i....#", "#.........#", "#.........#", "###########"])
	var imp: Monster = e["i"][0]
	var home := imp.tile
	var spots := {}
	var furthest := 0
	var still := 0
	var longest_still := 0
	var last := imp.tile
	for i in 600:
		World.step()
		furthest = maxi(furthest, World.distance(home, imp.tile))
		spots[imp.tile] = true
		still = still + 1 if imp.tile == last else 0
		longest_still = maxi(longest_still, still)
		last = imp.tile
	_check(spots.size() >= 6, "about the place (%d tiles stood on)" % spots.size())
	_check(furthest <= Monster.WANDER_RADIUS, "never more than %d from home (%d)" % [Monster.WANDER_RADIUS, furthest])
	_check(longest_still >= Monster.WANDER_PAUSE_TICKS.x, "pausing between (%d ticks at most in one spot)" % longest_still)


func _test_patrol() -> void:
	print("\n== patrol: waypoint to waypoint, a pause at each; a loop, or back and forth ==")
	var room: Array[String] = ["#########", "#.......#", "#s......#", "#.......#", "#########"]
	var route: Array[Vector2i] = [Vector2i(1, 1), Vector2i(7, 1), Vector2i(7, 3)]
	for loop: bool in [true, false]:
		var e := _build(room, {"s": {"idle": {"mode": "patrol", "route": route, "loop": loop}}})
		var sneak: Monster = e["s"][0]
		var visits: Array[Vector2i] = []
		var paused := 0
		var still := 0
		for i in 900:
			World.step()
			if sneak.tile in route and (visits.is_empty() or visits.back() != sneak.tile):
				visits.append(sneak.tile)
			still = still + 1 if sneak.tile in route else 0
			paused = maxi(paused, still)
		var expect := [route[0], route[1], route[2], route[0], route[1]] if loop \
				else [route[0], route[1], route[2], route[1], route[0]]
		_check(visits.slice(0, 5) == expect, "%s: %s" % ["a loop" if loop else "back and forth", visits.slice(0, 6)])
		_check(paused >= Monster.PATROL_PAUSE_TICKS.x, "a pause at each (%d ticks)" % paused)
	var e := _build(["###########", "#.........#", "#.........#", "#....s....#", "#.........#", "#.........#", "###########"])
	var sneak: Monster = e["s"][0]
	var stood := {}
	for i in 900:
		World.step()
		if sneak.tile in sneak.route:
			stood[sneak.tile] = true
	_check(sneak.route.size() >= 3 and stood.size() == sneak.route.size(),
			"a sneak with no route set walks a short loop of its own (%s, all %d stood on)" % [sneak.route, stood.size()])


func _test_gather() -> void:
	print("\n== gather: round a point, each in a place of its own, facing it ==")
	var point := Vector2i(5, 3)
	var e := _build(["###########", "#.........#", "#.........#", "#....~....#", "#.........#", "#iiii.....#", "###########"],
			{"i": {"idle": {"mode": "gather", "point": point}}})
	for i in 300:
		World.step()
	var imps: Array = e["i"]
	var places := imps.map(func(m: Monster) -> Vector2i: return m.tile)
	var near := imps.all(func(m: Monster) -> bool: return World.distance(m.tile, point) <= Monster.GATHER_RADIUS and m.tile != point)
	var facing_it := imps.all(func(m: Monster) -> bool:
		var toward := point - m.tile
		return m.facing == Vector2i(signi(toward.x), signi(toward.y)))
	_check(near, "all round it, none in the fire (%s)" % [places])
	_check(_set_of(places).size() == places.size(), "each its own place")
	_check(facing_it, "facing it (%s)" % [imps.map(func(m: Monster) -> Vector2i: return m.facing)])
	var poses := imps.map(func(m: Monster) -> int: return m.pose)
	_check(poses.all(func(p: int) -> bool: return p == Monster.Pose.SIT or p == Monster.Pose.STAND), "sitting or standing (%s)" % [poses])


func _test_idle_pace() -> void:
	print("\n== idling it walks slower than it chases ==")
	var e := _build(["#############", "#...........#", "#.i.........#", "#...........#", "#############"])
	var imp: Monster = e["i"][0]
	_bold(imp)
	imp.sight_range = 0
	for i in 40:
		World.step()
	var idling := imp.move_ticks
	imp.sight_range = 12
	var player := EntityFactory.build(SPECS["P"].merged({"name": "Player1", "tile": Vector2i(10, 2)}))
	_room.add_child(player)
	World.spawn(player, Vector2i(10, 2))
	for i in 3:
		World.step()
	_check(idling > imp.move_ticks * 1.4, "a step %.2f ticks idling, %.2f chasing" % [idling, imp.move_ticks])


func _test_home_after_a_fight() -> void:
	print("\n== after a fight it walks back home and goes on as before ==")
	var e := _build(["#############", "#...........#", "#.b.........#", "#...........#", "#############"], {"b": {"facing": Vector2i(0, 1)}})
	var brute: Monster = e["b"][0]
	_bold(brute)
	var home := brute.tile
	var player := EntityFactory.build(SPECS["P"].merged({"name": "Player1", "tile": Vector2i(8, 2)}))
	_room.add_child(player)
	World.spawn(player, Vector2i(8, 2))
	var left := false
	for i in 80:
		World.step()
		left = left or World.distance(brute.tile, home) >= 3
	_check(left and brute.target == player, "it goes for whoever it sees (at %s)" % brute.tile)
	World.despawn(player)
	var back_at := -1
	for i in 300:
		World.step()
		if brute.tile == home and back_at < 0:
			back_at = i
	_check(back_at >= 0, "home again (%d ticks on)" % back_at)
	_check(brute.facing == brute.home_facing or brute._glancing, "facing its way again (%s)" % brute.facing)
	var e2 := _build(["#########", "#.......#", "#...s...#", "#########"],
			{"s": {"idle": {"mode": "patrol", "route": [Vector2i(1, 1), Vector2i(7, 1)], "loop": true}}})
	var sneak: Monster = e2["s"][0]
	sneak._returning = true
	var on_route := false
	for i in 300:
		World.step()
		on_route = on_route or sneak.tile in sneak.route
	_check(on_route and not sneak._returning, "a patrol takes up its route again")


func _set_of(values: Array) -> Dictionary:
	var out := {}
	for value: Variant in values:
		out[value] = true
	return out


## No hanging back, no pause, no delay: what a test is after, at once.
func _bold(monster: Monster) -> void:
	monster.boldness = 1.0
	monster.temper = Monster.Temper.BOLD
	monster.pause_chance = 0.0
	monster.reaction_ticks = 0
	monster.sight_range = 12
	monster.senses.cone_cos = -1.0  # All round: these test how it fights, not what it sees.


## [param extra]: per symbol, more for its spawn spec ({"b": {"facing": ...}}).
func _test_roster() -> void:
	print("\n== what a monster looks for: the zone's players and companions, its monsters, kept up ==")
	var e := _build(["#######", "#PicmP#", "#.....#", "#######"])
	var players: Array = e["P"]
	var imp: Monster = e["i"][0]
	var other: Monster = e["m"][0]
	_check(World.sought() == players, "the players, in id order (%s)" % [World.sought()])
	_check(World.monsters() == [other, imp], "the monsters, in id order (spawned m then i), not the crate (%s)" % [World.monsters()])
	World.despawn(imp)
	_check(World.monsters() == [other], "a monster gone is gone from them (%s)" % [World.monsters()])
	var late := EntityFactory.build({"script": "res://sim/monster.gd", "shape": "capsule", "name": "Late", "tile": Vector2i(1, 2)})
	_room.add_child(late)
	World.spawn(late, Vector2i(1, 2))
	_check(World.monsters() == [other, late], "a monster come is in them (%s)" % [World.monsters()])
	var elsewhere := World.add_zone("roster_elsewhere")
	var was := World.enter(elsewhere)
	_check(World.sought().is_empty() and World.monsters().is_empty(), "another zone has its own: none here")
	World.enter(was)
	_check(World.sought() == players and World.monsters() == [other, late], "and back, this zone's again")
	World.zones.erase("roster_elsewhere")


## A long hall: the player at one end, an imp NEAR (out of sight), one MID
## and one FAR from it (World.Tier).
func _tier_hall() -> Dictionary:
	var floor := ".".repeat(78)
	return _build(["#".repeat(80), "#" + floor + "#", "#P" + ".".repeat(9) + "i" + ".".repeat(34) + "i"
			+ ".".repeat(29) + "i" + "...#", "#" + floor + "#", "#".repeat(80)])


func _test_tiers() -> void:
	print("\n== far from everyone a monster thinks less often, or not at all ==")
	var e := _tier_hall()
	var player: Player = e["P"][0]
	var imps: Array = e["i"]
	var near: Monster = imps[0]
	var mid: Monster = imps[1]
	var far: Monster = imps[2]
	var homes: Array = imps.map(func(m: Monster) -> Vector2i: return m.tile)
	World.step()
	var woke_at := World.tick
	_check(near._idle_from == woke_at + near.id % World.WAKE_SPREAD_TICKS and mid._idle_from >= woke_at
			and mid._idle_from < woke_at + World.WAKE_SPREAD_TICKS + World.TIER_EVERY_TICKS and far._idle_from == 0,
			"woken by someone near, each idles from a moment of its own (%d, %d after %d); the far one is not woken" % [
			near._idle_from, mid._idle_from, woke_at])
	var moved := [0, 0, 0]
	var thought := [0, 0, 0]
	var origins := World._tier_origins()
	for i in 400:
		for j in 3:
			if World._thinks(imps[j], origins):
				thought[j] += 1
		World.step()
		origins = World._tier_origins()
		for j in 3:
			moved[j] = maxi(moved[j], World.distance(homes[j], imps[j].tile))
	_check(not near.beyond_view and mid.beyond_view, "beyond %d tiles of everyone (the mid one at %d), on nobody's screen" % [
			World.VIEW_TILES, World.distance(mid.tile, player.tile)])
	_check([near.tier, mid.tier, far.tier] == [World.Tier.NEAR, World.Tier.MID, World.Tier.FAR],
			"near, mid and far by distance (%s)" % [[near.tier, mid.tier, far.tier]])
	_check(thought[0] == 400 and absi(thought[1] * World.MID_EVERY_TICKS - 400) <= World.MID_EVERY_TICKS and thought[2] == 0,
			"near thinks every tick, mid one in %d, far never (%s)" % [World.MID_EVERY_TICKS, thought])
	_check(moved[0] > 0 and moved[1] > 0 and moved[2] == 0, "near and mid wander, far stands (%s)" % [moved])
	far.target = player
	_check(World._tier(far, origins) == World.Tier.NEAR, "one in a fight thinks every tick, however far")
	far.target = null
	far.tier_tick = -1  # Looked at again at once, not on its next turn.
	World.despawn(player)
	_check(World._tier_origins() == origins and World._tier(far, World._tier_origins()) == World.Tier.FAR,
			"the player dead and gone: measured from where they last stood (%s)" % [World._tier_origins()])
	_build(["#####", "#.i.#", "#####"])
	_check(World._tier_origins().is_empty() and World._thinks(World.monsters()[0], []),
			"a room nobody has stood in thinks at the full rate")


func _test_straight_beyond_view() -> void:
	print("\n== on nobody's screen an idler walks only straight; on someone's it finds a way round ==")
	var e := _build(["#######", "#..#..#", "#.i#..#", "#.....#", "#######"])
	var imp: Monster = e["i"][0]
	var goal := Vector2i(4, 2)
	var from := imp.tile
	_check(not imp._idle_step(goal, Monster.IDLE_SEARCH_TILES, true) and imp.tile == from,
			"straight at a wall, out of view: it does not search, it waits (%s)" % [imp.tile])
	imp.next_move_tick = 0
	_check(imp._idle_step(goal, Monster.IDLE_SEARCH_TILES, false) and imp.tile != from,
			"in someone's view: a way round the wall (%s)" % [imp.tile])


func _test_look_skipped_far() -> void:
	print("\n== far beyond its sight it does not look; someone come beside it is seen at once ==")
	var e := _build(["#" + "#".repeat(60) + "#", "#P" + ".".repeat(48) + "m" + ".".repeat(10) + "#", "#" + "#".repeat(60) + "#"])
	var m: Monster = e["m"][0]
	m.sight_range = 7
	m.senses.sight_range = 7
	for i in World.TIER_EVERY_TICKS:
		World.step()
	_check(m.nearest_sought > m.sight_range + Monster.LOOK_MARGIN_TILES and m._nearest_visible_target() == null,
			"the nearest player %d tiles off: nobody to look at" % m.nearest_sought)
	var late := EntityFactory.build({"script": "res://sim/player.gd", "shape": "capsule", "name": "Late", "tile": m.tile + Vector2i(2, 0)})
	_room.add_child(late)
	World.spawn(late, m.tile + Vector2i(2, 0))
	late.protected = false
	_check(m._nearest_visible_target() == late, "a player come two tiles off is seen at once, its measure old or not")


func _test_monsters_write_no_log() -> void:
	print("\n== a fight among monsters writes no log lines: blows on one too heavy to shift, doors they open ==")
	var e := _build(["#########", "#.......#", "#..iPi..#", "#...b...#", "#########"])
	var player: Player = e["P"][0]
	player.mass = 10000.0
	player.max_hp = 100000
	player.hp = player.max_hp
	for m: Monster in e["i"] + e["b"]:
		_bold(m)
	var door := Door.build({"script": "res://sim/door.gd", "name": "Door", "edge": [1, 1, Terrain.EAST],
		"props": {"max_hp": 20, "body_material": GridEntity.BodyMaterial.WOOD}})
	_room.add_child(door)
	var before := World.logged
	for i in 80:
		World.step()
	World.try_toggle_door(e["i"][0], Vector3i(1, 1, Terrain.EAST))
	World._set_door(door, true, e["i"][0])
	var hits := _damage_log.filter(func(d: Dictionary) -> bool: return d["entity"] == player).size()
	_check(hits > 0 and World.logged == before, "%d blows landed, a door opened, %d log lines" % [hits, World.logged - before])
	World._set_door(door, false, player)
	_check(World.logged == before + 1, "a player shutting it is logged")


func _test_world_tick() -> void:
	print("\n== the world tick moves a far monster on: back where it idles after a fight ==")
	var e := _tier_hall()
	var far: Monster = e["i"][2]
	var near: Monster = e["i"][0]
	var far_home := far.home
	var near_home := near.home
	World.step()
	for m: Monster in [far, near]:
		World._relocate(m, m.home + Vector2i(-2, 1))
		m._returning = true
	World.world_tick()
	_check(far.tile == far_home and not far._returning,
			"the far one has walked home in the time (%s, home %s)" % [far.tile, far_home])
	_check(near.tile == near_home + Vector2i(-2, 1) and near._returning,
			"a near one is left to walk back (%s)" % [near.tile])
	var blocker := EntityFactory.build({"script": "res://sim/pushable.gd", "shape": "cube", "name": "Blocker", "tile": far_home})
	_room.add_child(blocker)
	World._relocate(far, far_home + Vector2i(-2, 1))
	far._returning = true
	World.spawn(blocker, far_home)
	World.world_tick()
	_check(far.tile == far_home + Vector2i(-2, 1) and far._returning, "home taken: it waits for the next")
	World.despawn(blocker)
	for i in World.WORLD_TICK_STEPS:
		World.step()
	_check(far.tile == far_home and not far._returning,
			"the step's own world tick, every %d steps, takes it home once it is free" % World.WORLD_TICK_STEPS)
	# Ten tiles off, and two seconds: only as far as it walks in that time.
	World._relocate(far, far_home + Vector2i(-10, 0))
	far._returning = true
	far._world_tick(2.0)
	var steps := floori(2.0 * World.TICK_RATE / World.step_ticks(far, Vector2i(1, 0)))
	_check(far.tile == far_home + Vector2i(-10 + steps, 0) and far._returning,
			"a short time, a short way: %d steps toward home, to %s" % [steps, far.tile])
	far._world_tick(30.0)
	_check(far.tile == far_home and not far._returning, "and the rest of the way the next time (%s)" % [far.tile])


func _test_plans_per_step() -> void:
	print("\n== a crowd that comes near at once works its patrols out over a few steps ==")
	var rows: Array[String] = ["#".repeat(42)]
	for y in 4:
		rows.append("#" + ("s......." if y % 2 == 0 else "........").repeat(5) + "#")
	rows.append("#" + ".".repeat(40) + "#")
	rows.append("#".repeat(42))
	var e := _build(rows)
	var sneaks: Array = e["s"]
	var planned: Array[int] = []
	for i in 4:
		World.step()
		planned.append(sneaks.filter(func(m: Monster) -> bool: return not m.route.is_empty()).size())
	_check(sneaks.size() == 10 and planned[0] <= World.PLANS_PER_STEP and planned[-1] == sneaks.size(),
			"%d patrols, routes worked out by step: %s (%d a step at most)" % [sneaks.size(), planned, World.PLANS_PER_STEP])


func _test_walk_round_held_ground() -> void:
	print("\n== a far monster walking back does not walk over ground another faction holds ==")
	# A hall with the town's farm across it at x 15 (radius 1: the whole
	# column, and the cells beside its middle), an imp (the goblins') home at x 5, sent back from x 25.
	var floor := "#" + ".".repeat(30) + "#"
	var e := _build(["#".repeat(32), floor, "#" + ".".repeat(24) + "i" + ".".repeat(5) + "#", floor, "#".repeat(32)])
	var imp: Monster = e["i"][0]
	var block_rows: Array[String] = []
	for y in 9:
		block_rows.append(".".repeat(63))
	Level.register("held_hall", Level.image_from_rows(block_rows), null, {"places": {
		"farm": {"at": [15, 2], "kind": "farm", "radius": 1, "holder": "town"}}})
	var names: Array[String] = ["held_hall"]
	var was_holdings := World.holdings
	var was_name := World.zone.name
	World.holdings = Holdings.new(WorldMap.build(names), Factions.read())
	World.zone.name = "held_hall"
	var home := Vector2i(5, 2)
	imp.home = home
	imp._returning = true
	imp._world_tick(60.0)
	_check(imp.tile.x == 16 and not World.held_against(imp).has(imp.tile) and imp._returning,
			"it walks to the edge of the town's farm and stops there (%s)" % [imp.tile])
	World.holdings.take("held_hall/farm", "goblins")
	imp._world_tick(60.0)
	_check(imp.tile == home and not imp._returning, "the goblins take the farm: it is theirs to cross, and it is home (%s)" % [imp.tile])
	World.holdings.take("held_hall/farm", "town")
	World._relocate(imp, Vector2i(15, 2))
	imp._returning = true
	imp._world_tick(60.0)
	_check(imp.tile == Vector2i(15, 2), "standing in the town's ground, it has met them there and does not walk (%s)" % [imp.tile])
	World.holdings = was_holdings
	World.zone.name = was_name


## [param edges]: walls ("#") and doors ("+", each with its Door) at
## positions of the expanded rows (Terrain.expand: the edge east of cell
## (x, y) is at (2x + 1, 2y)).
func _build(rows: Array[String], extra := {}, edges := {}) -> Dictionary:
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
	var expanded := Terrain.expand(cell_rows)
	for at: Vector2i in edges:
		var row := expanded[at.y]
		while row.length() <= at.x:
			row += " "
		expanded[at.y] = row.substr(0, at.x) + str(edges[at]) + row.substr(at.x + 1)
	World.load_terrain(Terrain.parse(expanded))
	for at: Vector2i in edges:
		if edges[at] == "+":
			var key := Vector3i((at.x - 1) / 2, at.y / 2, Terrain.EAST) if at.x % 2 == 1 \
					else Vector3i(at.x / 2, (at.y - 1) / 2, Terrain.SOUTH)
			_room.add_child(Door.build({"script": "res://sim/door.gd", "name": "Door%d_%d" % [key.x, key.y],
				"edge": [key.x, key.y, key.z], "props": {"max_hp": 20, "body_material": GridEntity.BodyMaterial.WOOD}}))
	var out := {}
	for symbol: String in SPECS:
		out[symbol] = []
		for spawn in spawns:
			if spawn[0] != symbol:
				continue
			var spec: Dictionary = SPECS[symbol].duplicate(true)
			if spec.has("kind"):
				var kind_props: Dictionary = Level.MONSTER_TYPES[spec["kind"]]
				spec["props"] = kind_props.duplicate()
			spec.merge(extra.get(symbol, {}), true)
			spec["name"] = "%s%d" % [NAMES[symbol], out[symbol].size() + 1]
			spec["tile"] = spawn[1]
			var entity := EntityFactory.build(spec)
			_room.add_child(entity)
			if entity is Monster:
				entity.sight_range = 0  # Stands still unless a test turns it on.
			World.spawn(entity, spawn[1])
			out[symbol].append(entity)
	return out


func _test_sight_cone() -> void:
	print("\n== a monster of a kind sees in a cone before it; one of no kind all round ==")
	Monster.idling = false
	var north := {"facing": Vector2i(0, -1)}
	var e := _build(["#######", "#.....#", "#..b..#", "#.....#", "#..P..#", "#.....#", "#######"], {"b": north})
	var brute: Monster = e["b"][0]
	var player: GridEntity = e["P"][0]
	brute.sight_range = 7
	World.step()
	_check(brute.target == null, "facing north, it does not see the player behind it")
	_move_to(player, Vector2i(3, 1))
	World.step()
	_check(brute.target == player, "in front of it, it does (%s)" % [brute.target])
	_move_to(player, Vector2i(3, 5))
	World.step()
	_check(brute.target == player, "and once it has someone it keeps them, behind it or not")
	_check(brute.senses.last_seen(player).get("at") == Vector2i(3, 5), "it remembers where it saw them (%s)" % [brute.senses.last_seen(player)])
	e = _build(["#######", "#.....#", "#..m..#", "#.....#", "#..P..#", "#######"], {"m": north})
	var plain: Monster = e["m"][0]
	plain.sight_range = 7
	World.step()
	_check(plain.target == e["P"][0], "a monster of no kind sees all round, as monsters did")
	e = _build(["#######", "#.....#", "#..b..#", "#..P..#", "#######"], {"b": north})
	(e["b"][0] as Monster).sight_range = 7
	World.step()
	_check((e["b"][0] as Monster).target == e["P"][0], "right behind it, it notices them anyway")
	Monster.idling = true


func _test_sight_by_light() -> void:
	print("\n== in the dark it sees only what is lit, or carries a light ==")
	Monster.idling = false
	var e := _build(["#########", "#.......#", "#.......#", "#...b...#", "#.......#", "#########"], {"b": {"facing": Vector2i(0, -1)}})
	World.fields.ambient = 0.0
	World.fields_changed()
	var brute: Monster = e["b"][0]
	brute.sight_range = 7
	var player: Player = EntityFactory.build(SPECS["P"].merged({"name": "Player1", "tile": Vector2i(4, 1)}))
	_room.add_child(player)
	World.spawn(player, Vector2i(4, 1))
	player.toggle_lantern()
	World.step()
	_check(player.emit_light == 0.0 and brute.target == null, "its lantern covered, in the dark before it: unseen")
	player.toggle_lantern()
	World.step()
	_check(player.emit_light > 0.0 and brute.target == player, "its lantern lit: seen")
	_check(Senses.is_lit(Vector2i(5, 1)), "its lantern lights the cells by it")
	player.toggle_lantern()
	brute.target = null
	var friend: Player = EntityFactory.build(SPECS["P"].merged({"name": "Player2", "tile": Vector2i(2, 1)}))
	_room.add_child(friend)
	World.spawn(friend, Vector2i(2, 1))
	World.step()
	_check(brute.senses.sees(player), "covered, but beside one with a lantern lit: seen")
	friend.toggle_lantern()
	brute.target = null
	World.step()
	_check(brute.target == null, "both covered: neither seen")
	_check(Senses.is_lit(Vector2i(4, 1)) == false, "nothing lights the dark then")
	_check(Senses.light_level(Vector2i(4, 1)) == 0.0 and brute.senses.sees_cell(Vector2i(4, 1), 0.0)
			and not brute.senses.sees_cell(Vector2i(4, 1)), "how light it is there, and a cell seen by a threshold of the asker's")
	World.fields.ambient = 1.0
	World.fields_changed()
	World.step()
	_check(brute.target != null, "in the light, seen covered or not")
	Monster.idling = true


func _test_weather() -> void:
	print("
== outdoors, fog shortens sight and a storm covers noise; not indoors, not a lantern ==")
	Monster.idling = false
	var e := _build(["#########", "#.......#", "#.......#", "#.......#", "#.......#", "#.......#", "#.......#", "#...b...#", "#########"],
			{"b": {"facing": Vector2i(0, -1)}})
	var brute: Monster = e["b"][0]
	brute.sight_range = 7
	var player: Player = EntityFactory.build(SPECS["P"].merged({"name": "Player1", "tile": Vector2i(4, 2)}))
	_room.add_child(player)
	World.spawn(player, Vector2i(4, 2))
	player.toggle_lantern()
	World.step()
	_check(brute.senses.sees(player), "indoors, in the light, five cells off: seen")
	World.fields.outdoor = true
	Weather.overrides = {Level.DEFAULT_REGION: {"kind": "fog", "from": -1000000, "until": 1000000}}
	World.step()
	_check(World.weather_sight_at(brute.tile) < 0.6, "outdoors in fog, sight is cut (%.2f)" % World.weather_sight_at(brute.tile))
	_check(not brute.senses.sees(player) and not brute.senses.sees_cell(player.tile), "in fog, five cells off: unseen, its cell too")
	player.toggle_lantern()
	_check(brute.senses.sees(player), "a lantern in the fog still shows")
	player.toggle_lantern()
	Weather.overrides = {Level.DEFAULT_REGION: {"kind": "storm", "from": -1000000, "until": 1000000}}
	World.step()
	var near := brute.tile + Vector2i(0, -2)
	brute.senses.heard.clear()
	World.noise(near, 3, &"step", player)
	_check(brute.senses.heard.is_empty(), "in a storm a step two cells off is not heard (cover %.2f)" % World.weather_hearing_at(near))
	World.noise(near, 3, &"speech", player)
	_check(not brute.senses.heard.is_empty(), "speech keeps its reach")
	World.fields.outdoor = false
	World.step()
	near = brute.tile + Vector2i(0, -2)
	brute.senses.heard.clear()
	World.noise(near, 3, &"step", player)
	_check(World.weather_hearing_at(near) == 1.0 and not brute.senses.heard.is_empty(),
			"indoors the same storm is nothing: the step is heard")
	Weather.overrides = {}
	Monster.idling = true


func _test_hearing() -> void:
	print("\n== a monster hears steps, turns, and sees who made them ==")
	var e := _build(["#######", "#.....#", "#..b..#", "#.....#", "#.....#", "#..P..#", "#######"], {"b": {"facing": Vector2i(0, -1)}})
	var brute: Monster = e["b"][0]
	var player: GridEntity = e["P"][0]
	brute.sight_range = 7
	World.step()
	_check(brute.target == null, "behind it, unseen")
	var moved := false
	for i in 5:
		if not moved:
			moved = World.try_move(player, Vector2i(0, -1))
		World.step()
	_check(moved and not brute.senses.heard.is_empty() and brute.senses.heard.back()["kind"] == &"step",
			"its step is heard (%s)" % [brute.senses.heard])
	_check(brute.target == player, "it turned to the noise, and saw them (facing %s)" % [brute.facing])
	_check(brute.senses.heard_since(0).back()["source"] == player, "who made it, now it sees them")
	brute.senses.forget()
	_check(brute.senses.heard_since(0).is_empty() and brute.senses.last_seen(player).is_empty(), "forget lets go of all of it")
	_check(Senses.way_toward(Vector2i(0, 0), Vector2i(5, 1)) == Vector2i(1, 0)
			and Senses.way_toward(Vector2i(0, 0), Vector2i(-3, -3)) == Vector2i(-1, -1), "a noise's way is the nearest of the eight")


func _test_noise_reach() -> void:
	print("\n== a noise carries its radius, half that through a wall; words further in capitals ==")
	var e := _build(["#########", "#b..#..b#", "#...#...#", "#...#...#", "#########"])
	var near: Monster = e["b"][0]
	var walled: Monster = e["b"][1]
	World.noise(Vector2i(3, 1), 6, &"test")
	_check(near.senses.heard.size() == 1, "heard in the same room")
	_check(walled.senses.heard.is_empty(), "not through the wall, 4 off (half of 6 is 3)")
	World.noise(Vector2i(3, 1), 10, &"test")
	_check(walled.senses.heard.size() == 1, "a louder one, through the wall")
	World.noise(Vector2i(1, 1), 3, &"test", near)
	_check(near.senses.heard.size() == 2, "its own noise it does not hear")
	_check(Senses.speech_radius("HELP ME") == Senses.NOISE_SHOUT and Senses.speech_radius("Help me") == Senses.NOISE_SPEECH
			and Senses.speech_radius("OK") == Senses.NOISE_SPEECH and Senses.speech_radius("WHO? 123!") == Senses.NOISE_SHOUT,
			"capitals are a shout, a short word is not")
	var sneak: GridEntity = EntityFactory.build(SPECS["s"].merged({"name": "S", "props": Level.MONSTER_TYPES["sneak"]}))
	var player: GridEntity = EntityFactory.build(SPECS["P"].merged({"name": "P"}))
	var heavy: GridEntity = EntityFactory.build(SPECS["c"].merged({"name": "C", "props": {"mass": 200.0}}))
	_check(Senses.step_radius(player) == Senses.NOISE_STEP and Senses.step_radius(sneak) == 2 and Senses.step_radius(heavy) == 4,
			"steps carry by mass: a player's 3, a sneak's 2, a heavy thing's 4")
	for entity: GridEntity in [sneak, player, heavy]:
		entity.free()
	e = _build(["#########", "#b.c....#", "#########"])
	near = e["b"][0]
	World.damage(e["c"][0], 999, null, &"impact")
	_check(not near.senses.heard.is_empty() and near.senses.heard.back()["kind"] == &"break", "a crate smashed is heard: break")


func _test_hunt() -> void:
	print("\n== out of sight, it hunts: to where it last saw them and on, looks round, gives up, goes back ==")
	Monster.idling = true
	var e := _build(["################", "#.........#....#", "#.i.......#....#", "#.........#....#", "#....P....#....#",
		"################"], {"i": {"facing": Vector2i(1, 1)}})
	var imp: Monster = e["i"][0]
	var player: GridEntity = e["P"][0]
	imp.sight_range = 7
	imp.reaction_ticks = 0
	World.step()
	_check(imp.target == player and imp.alert == Monster.Alert.FIGHTING, "it sees them: fighting")
	var home := imp.home
	# They step east twice, then are gone (out of its sight, far off).
	for x in [6, 7]:
		_move_to(player, Vector2i(x, 4))
		World.step()
	_move_to(player, Vector2i(13, 2))  # Into a room it cannot see into.
	World.step()
	_check(imp.alert == Monster.Alert.HUNTING and imp.target == null, "lost from sight: hunting (%s)" % Monster.Alert.keys()[imp.alert])
	_check(imp._lead == Vector2i(9, 4), "making for where it last saw them, and on the way they went (%s)" % imp._lead)
	var lead := imp._lead
	var reached := false
	var faced := {}
	for i in 80:
		World.step()
		reached = reached or imp.tile == lead
		if reached and imp.tile == lead:
			faced[imp.facing] = true
	_check(reached and imp.alert == Monster.Alert.HUNTING, "it gets there, still hunting (at %s)" % imp.tile)
	_check(faced.size() >= 3, "and looks round (%d ways)" % faced.size())
	for i in Monster.HUNT_TICKS + Monster.SUSPICIOUS_TICKS:
		World.step()
	_check(imp.alert == Monster.Alert.IDLE, "in time it gives up (%s)" % Monster.Alert.keys()[imp.alert])
	for i in 80:
		World.step()
	_check(World.distance(imp.tile, home) <= imp.wander_radius, "and goes back home (%s, home %s)" % [imp.tile, home])


func _test_leash() -> void:
	print("\n== too far from where it took up the chase, it gives up, and lets them be a while ==")
	Monster.idling = false
	var e := _build(["##################################", "#i...............................#",
		"#................................#", "#...............................P#", "##################################"],
			{"i": {"facing": Vector2i(1, 0)}})
	var imp: Monster = e["i"][0]
	var player: GridEntity = e["P"][0]
	imp.sight_range = 40
	imp.reaction_ticks = 0
	imp.senses.cone_cos = -1.0  # All round: this tests the leash.
	for i in World.MID_EVERY_TICKS:
		World.step()  # Far from the player, it thinks one tick in so many.
	_check(imp.alert == Monster.Alert.FIGHTING and imp._post == Vector2i(1, 1), "fighting, from (1, 1)")
	World._relocate(imp, Vector2i(1 + Monster.LEASH + 1, 1))
	World.step()
	_check(imp.alert == Monster.Alert.IDLE and imp.target == null, "past its leash: it gives up (%s)" % Monster.Alert.keys()[imp.alert])
	World.step()
	_check(imp.target == null, "and does not take them up again, in sight as they are")
	World._relocate(imp, Vector2i(15, 1))  # Walked back (idling is off here).
	for i in World.MID_EVERY_TICKS:
		World.step()
	_check(imp.target == null, "walking back, still not")
	_move_to(player, Vector2i(5, 3))
	for i in World.MID_EVERY_TICKS:
		World.step()
	_check(imp.target == player, "until they come near where it took up the chase")
	e = _build(["##################################", "#i...............................#",
		"#................................#", "#...............................P#", "##################################"],
			{"i": {"facing": Vector2i(1, 0)}})
	imp = e["i"][0]
	imp.sight_range = 40
	imp.reaction_ticks = 0
	imp.senses.cone_cos = -1.0
	for i in World.MID_EVERY_TICKS:
		World.step()
	World._relocate(imp, Vector2i(1 + Monster.LEASH + 1, 1))
	World.step()
	World._relocate(imp, Vector2i(5, 1))
	for i in Monster.GIVE_UP_TICKS + World.MID_EVERY_TICKS:
		World.step()
	_check(imp.target == e["P"][0], "or the while is over")
	Monster.idling = true


func _test_roused() -> void:
	print("\n== a noise sends it to look; a fight, or a blow from one unseen, to hunt; a glimpse to look ==")
	Monster.idling = false
	var e := _build(["##########", "#........#", "#...b....#", "#........#", "#........#", "#.......P#", "##########"],
			{"b": {"facing": Vector2i(0, -1)}})
	var brute: Monster = e["b"][0]
	var player: GridEntity = e["P"][0]
	brute.sight_range = 3
	World.noise(Vector2i(6, 2), Senses.NOISE_DOOR, &"door", null)
	World.step()
	_check(brute.alert == Monster.Alert.SUSPICIOUS and brute._lead == Vector2i(6, 2), "a door: it goes to look (%s, %s)" % [
		Monster.Alert.keys()[brute.alert], brute._lead])
	World.noise(Vector2i(1, 4), Senses.NOISE_FIGHT, &"fight", null)
	World.step()
	_check(brute.alert == Monster.Alert.HUNTING and brute._lead == Vector2i(1, 4), "a fight: it hunts (%s)" % Monster.Alert.keys()[brute.alert])
	e = _build(["#######", "#.b#..#", "#######"], {"b": {"facing": Vector2i(-1, 0)}})
	brute = e["b"][0]
	World.noise(Vector2i(4, 1), Senses.NOISE_FIGHT, &"fight", null)
	World.step()
	_check(brute.senses.heard.back()["muffled"] and brute.alert == Monster.Alert.SUSPICIOUS,
			"a fight heard through a wall: it goes to look, no more (%s)" % Monster.Alert.keys()[brute.alert])
	e = _build(["##########", "#........#", "#...b....#", "#........#", "#........#", "#.......P#", "##########"],
			{"b": {"facing": Vector2i(0, -1)}})
	brute = e["b"][0]
	player = e["P"][0]
	World.noise(brute.tile, Senses.NOISE_FIGHT, &"fight", player)
	World.step()
	_check(brute.alert == Monster.Alert.HUNTING and brute._lead == player.tile and brute._quarry == player,
			"struck by one it does not see: after them (%s)" % brute._lead)
	e = _build(["##########", "#........#", "#...b....#", "#........#", "#........#", "#...P....#", "##########"],
			{"b": {"facing": Vector2i(0, 1)}})
	brute = e["b"][0]
	player = e["P"][0]
	brute.sight_range = 7
	(player as Player).toggle_lantern()
	World.fields.ambient = 0.2
	World.fields_changed()
	World.step()
	_check(brute.target == null and brute.alert == Monster.Alert.SUSPICIOUS and brute._lead == Vector2i(4, 5),
			"dimly lit before it: a glimpse, it goes to look (%s, %s)" % [Monster.Alert.keys()[brute.alert], brute._lead])
	World.fields.ambient = 1.0
	World.fields_changed()
	brute._world_tick(1.0)
	_check(brute.alert == Monster.Alert.IDLE, "the world tick (far off) calms it")
	Monster.idling = true

## Two rooms split between x = 6 and 7, a door at (6, 3) east: the rows,
## and the edges for _build.
const SPLIT: Array[String] = ["##############", "#............#", "#............#", "#............#",
	"#............#", "#............#", "##############"]
const SPLIT_DOOR := Vector3i(6, 3, Terrain.EAST)


func _split_edges() -> Dictionary:
	var edges := {}
	for y in range(1, 6):
		edges[Vector2i(13, y * 2)] = "+" if y == 3 else "#"
	return edges


func _test_door_openers() -> void:
	print("\n== doors: imps and sneaks open them, brutes do not; the way and the world tick's walk know it ==")
	Monster.idling = false
	var rows := SPLIT.duplicate()
	rows[2] = "#.b..........#"
	rows[4] = "#.i..........#"
	var e := _build(rows, {}, _split_edges())
	var brute: Monster = e["b"][0]
	var imp: Monster = e["i"][0]
	var door: Door = World.door_on(SPLIT_DOOR)
	_check(door != null and not door.open, "a shut door between the rooms")
	_check(imp.opens_doors and not brute.opens_doors, "an imp opens doors, a brute does not")
	_check(World.find_path(brute.tile, Vector2i(10, 2), false, null, 400, false, {}, false).is_empty(),
			"no way through a shut door for one that does not open it")
	_check(not World.find_path(imp.tile, Vector2i(10, 4), false, null, 400, false, {}, true).is_empty(),
			"a way through for one that does")
	_check(not World.walk(brute, Vector2i(10, 2), 200.0) and brute.tile.x <= 6, "a brute's world-tick walk stops at the door (%s)" % brute.tile)
	_check(World.walk(imp, Vector2i(10, 4), 200.0) and imp.tile == Vector2i(10, 4), "an imp's goes through (%s)" % imp.tile)
	World._relocate(brute, Vector2i(6, 3))
	World.step()
	_check(not World.try_move(brute, Vector2i(1, 0)) and not door.open, "a brute walking into it does not open it")
	World._relocate(imp, Vector2i(6, 3))
	World.step()
	_check(World.try_move(imp, Vector2i(1, 0)) and door.open, "an idle imp walking into it opens it")
	Monster.idling = true


func _test_hiding() -> void:
	print("\n== behind a shut door, quiet, you can hide; a noise from there brings it in ==")
	Monster.idling = false
	var rows := SPLIT.duplicate()
	rows[3] = "#..i.........#"
	var e := _build(rows, {"i": {"facing": Vector2i(1, 0)}}, _split_edges())
	var imp: Monster = e["i"][0]
	imp.sight_range = 7
	imp.reaction_ticks = 0
	var door: Door = World.door_on(SPLIT_DOOR)
	var player: Player = EntityFactory.build(SPECS["P"].merged({"name": "Player1", "tile": Vector2i(10, 1)}))
	_room.add_child(player)
	World.spawn(player, Vector2i(10, 1))
	# It saw them in its room, running for the door; then they were gone
	# through it, and it is shut.
	imp.alert = Monster.Alert.FIGHTING
	imp._post = imp.tile
	imp._quarry_from = Vector2i(5, 3)
	imp._quarry_at = Vector2i(6, 3)
	imp._hunt(player)
	_check(imp.alert == Monster.Alert.HUNTING and imp._lead == Vector2i(6, 3),
			"it hunts to where it saw them, this side of the door: no seeing on past it (%s)" % imp._lead)
	var opened := false
	for i in 120:
		World.step()
		opened = opened or door.open
	_check(not opened and World.distance(imp.tile, Vector2i(6, 3)) <= 1, "it comes to the door, and does not open it (at %s)" % imp.tile)
	_check(imp.alert != Monster.Alert.FIGHTING, "it does not find them")
	for i in Monster.HUNT_TICKS + Monster.SUSPICIOUS_TICKS:
		World.step()
		opened = opened or door.open
	_check(not opened and imp.alert == Monster.Alert.IDLE, "and gives up, the door shut (%s)" % Monster.Alert.keys()[imp.alert])
	# Again, and this time a noise behind the door.
	imp._post = imp.tile
	imp.alert = Monster.Alert.FIGHTING
	imp._quarry_from = Vector2i(5, 3)
	imp._quarry_at = Vector2i(6, 3)
	World._relocate(imp, Vector2i(5, 3))
	imp._hunt(player)
	for i in 20:
		World.step()
	World.noise(Vector2i(8, 3), Senses.NOISE_SPEECH, &"speech", player)
	for i in 40:
		World.step()
		opened = opened or door.open
	_check(opened, "a voice behind the door: it opens it and comes in (at %s)" % imp.tile)
	# Seen beyond the door as it shut: after them, fresh, it opens it.
	e = _build(rows, {"i": {"facing": Vector2i(1, 0)}}, _split_edges())
	imp = e["i"][0]
	door = World.door_on(SPLIT_DOOR)
	player = EntityFactory.build(SPECS["P"].merged({"name": "Player1", "tile": Vector2i(11, 5)}))
	_room.add_child(player)
	World.spawn(player, Vector2i(11, 5))
	imp.alert = Monster.Alert.FIGHTING
	imp._post = imp.tile
	imp._quarry_from = Vector2i(7, 3)
	imp._quarry_at = Vector2i(8, 3)
	imp._hunt(player)
	opened = false
	for i in 60:
		World.step()
		opened = opened or door.open
	_check(opened, "seen beyond it as it shut: it opens it, the hunt fresh (at %s)" % imp.tile)
	Monster.idling = true


func _test_brute_breaks() -> void:
	print("\n== a brute with a reason behind the door breaks it down ==")
	Monster.idling = false
	var rows := SPLIT.duplicate()
	rows[3] = "#....b.......#"
	var e := _build(rows, {"b": {"facing": Vector2i(1, 0)}}, _split_edges())
	var brute: Monster = e["b"][0]
	var door: Door = World.door_on(SPLIT_DOOR)
	World.noise(Vector2i(9, 3), Senses.NOISE_FIGHT * 2, &"fight", null)
	var broke_at := -1
	for i in 120:
		World.step()
		if door.is_broken() and broke_at < 0:
			broke_at = i
	_check(broke_at > 0 and door.state() == "broken", "a fight behind it: it breaks the door down (in %d ticks)" % broke_at)
	_check(brute.tile.x >= 7, "and goes through (at %s)" % brute.tile)
	Monster.idling = true


func _test_locks() -> void:
	print("\n== a locked door opens only for one with its key (World.key_check, the items') ==")
	var rows := SPLIT.duplicate()
	rows[3] = "#...b.P......#"
	var e := _build(rows, {}, _split_edges())
	var player: Player = e["P"][0]
	var listener: Monster = e["b"][0]
	var door: Door = World.door_on(SPLIT_DOOR)
	door.lock = "keep"
	_check(door.state() == "locked", "shut with a lock: locked")
	_check(not World.try_toggle_door(player, SPLIT_DOOR) and not World.try_move(player, Vector2i(1, 0)) and not door.open,
			"no key: it will not open, by hand or walking into it")
	_check(listener.senses.heard.back()["kind"] == &"door_rattle", "and the rattle is heard")
	var was := World.key_check
	World.key_check = func(entity: GridEntity, lock: String) -> bool: return entity == player and lock == "keep"
	_check(World.try_toggle_door(player, SPLIT_DOOR) and door.open and door.state() == "open", "with the key it opens")
	World.key_check = was
	door.lock = ""
	door.open = false
	_check(door.state() == "closed" and Door.STATES.has("barred"), "unlocked and shut: closed (barred is kept for later)")

func _test_kinds_table() -> void:
	print("\n== a kind is a row of levels/monsters.json: body, tactic, idling, doors, temperaments ==")
	var kinds := Monster.kinds()
	_check(kinds.has("imp") and kinds.has("brute") and kinds.has("sneak"), "imp, brute and sneak are its rows")
	_check(kinds["imp"]["tactic"] == Monster.Tactic.DART and kinds["brute"]["tactic"] == Monster.Tactic.HEAVY
			and kinds["sneak"]["tactic"] == Monster.Tactic.FLANK, "each its tactic, as before")
	_check(Monster.idle_of("imp") == Monster.Idle.WANDER and Monster.idle_of("brute") == Monster.Idle.GUARD
			and Monster.idle_of("sneak") == Monster.Idle.PATROL and Monster.idle_of("nobody") == Monster.Idle.NONE,
			"and its idling, as before")
	_check(Level.MONSTER_TYPES["brute"]["mass"] == 70.0 and Level.MONSTER_TYPES["sneak"]["max_hp"] is int
			and Level.MONSTER_TYPES["brute"]["attack_ticks"] == 14,
			"Level.MONSTER_TYPES is each kind's body (%s)" % [Level.MONSTER_TYPES])
	var e := _build(["#######", "#i.b.s#", "#######"])
	_check(e["i"][0].opens_doors and not e["b"][0].opens_doors and e["b"][0].door_force == 3, "doors from the table")
	_check(Monster.read_kinds("res://levels/nothing_here.json").is_empty(), "a missing table gives no kinds (with a warning)")


func _test_temperament() -> void:
	print("\n== each monster a temperament: its level entry's, else its kind's by name ==")
	var e := _build(["#########", "#i.i.i.b#", "#########"], {"b": {"temperament": "cowardly"}})
	var brute: Monster = e["b"][0]
	_check(brute.temper == Monster.Temper.COWARDLY, "a level entry's temperament")
	var span: Vector2 = Monster.BOLDNESS[Monster.Temper.COWARDLY]
	_check(brute.boldness >= span.x and brute.boldness <= span.y, "its boldness within its temperament's (%.2f)" % brute.boldness)
	var first: Array = e["i"].map(func(m: Monster) -> int: return m.temper)
	var again := _build(["#########", "#i.i.i.b#", "#########"])
	_check(again["i"].map(func(m: Monster) -> int: return m.temper) == first, "the same name, the same temperament (%s)" % [first])
	var drawn := {}
	for i in 60:
		var m: Monster = EntityFactory.build(SPECS["b"].merged({"name": "Brute%d" % i, "props": Level.MONSTER_TYPES["brute"]}))
		_room.add_child(m)
		drawn[m.temper] = drawn.get(m.temper, 0) + 1
	_check(not drawn.has(Monster.Temper.COWARDLY) and drawn.get(Monster.Temper.BOLD, 0) > drawn.get(Monster.Temper.CAUTIOUS, 0),
			"brutes are bold more than cautious, never cowardly (%s)" % [drawn])
	e = _build(["#########", "#b......#", "#########"], {"b": {"temperament": "bold"}})
	_check(e["b"][0].leash == roundi(Monster.LEASH * Monster.BOLD_LEASH), "a bold one's leash is longer (%d)" % e["b"][0].leash)


func _test_flee() -> void:
	print("\n== hurt past its temperament's mark it breaks and runs; nobody near, it comes back ==")
	Monster.idling = false
	var e := _build(["##############", "#............#", "#..P.i.......#", "#............#", "##############"],
			{"i": {"temperament": "cowardly", "facing": Vector2i(-1, 0)}})
	var imp: Monster = e["i"][0]
	var player: GridEntity = e["P"][0]
	imp.sight_range = 7
	imp.reaction_ticks = 0
	imp.hp = 6  # Under 60% of 12.
	World.step()
	_check(imp.alert == Monster.Alert.FLEEING and imp.target == null, "a coward at half hp sees them and breaks (%s)" % Monster.Alert.keys()[imp.alert])
	var hits_before := _damage_log.size()
	for i in 30:
		World.step()
	_check(World.distance(imp.tile, player.tile) > 3, "and runs from them (%d off)" % World.distance(imp.tile, player.tile))
	_check(_damage_log.slice(hits_before).all(func(hit: Dictionary) -> bool: return hit["source"] != imp), "striking no one")
	World.despawn(player)
	for i in Monster.FLEE_TICKS + 10:
		World.step()
	_check(imp.alert != Monster.Alert.FLEEING, "with nobody near it recovers (%s)" % Monster.Alert.keys()[imp.alert])
	e = _build(["##########", "#..P.b...#", "##########"], {"b": {"temperament": "bold", "facing": Vector2i(-1, 0)}})
	var brute: Monster = e["b"][0]
	brute.sight_range = 7
	brute.hp = 4  # A third of 12: over a bold one's 15%.
	World.step()
	_check(brute.alert == Monster.Alert.FIGHTING, "a bold one at a third of its hp fights on")
	Monster.idling = true


func _test_call_and_rout() -> void:
	print("\n== a call brings its side; one breaking breaks the cowards and the hurt ==")
	Monster.idling = false
	var e := _build(["################", "#..............#", "#.P.i..........#", "#..............#", "#..........i...#",
		"################"], {"i": {"temperament": "cautious", "facing": Vector2i(-1, 0)}})
	var caller: Monster = e["i"][0]
	var other: Monster = e["i"][1]
	other.facing = Vector2i(1, 0)  # Looking away.
	caller.sight_range = 7
	caller.reaction_ticks = 0
	var cries: Array[StringName] = []
	caller.cried.connect(func(kind: StringName) -> void: cries.append(kind))
	World.step()
	World.step()
	_check(caller.alert == Monster.Alert.FIGHTING and other.senses.heard.any(func(n: Dictionary) -> bool: return n["kind"] == &"call"),
			"a cautious one that sees someone calls, and its side hears it")
	_check(cries == [&"call"], "and cries out, for views and sound (%s)" % [cries])
	_check(other.alert == Monster.Alert.HUNTING and other._lead == e["P"][0].tile,
			"and comes after whom it fights (%s, %s)" % [Monster.Alert.keys()[other.alert], other._lead])
	e = _build(["################", "#..............#", "#.P.i...i...b..#", "#..............#", "################"])
	var breaking: Monster = e["i"][0]
	var coward: Monster = e["i"][1]
	var bold: Monster = e["b"][0]
	coward.temper = Monster.Temper.COWARDLY
	bold.temper = Monster.Temper.BOLD
	var routs: Array[StringName] = []
	breaking.cried.connect(func(kind: StringName) -> void: routs.append(kind))
	breaking._flee(e["P"][0].tile)
	World.step()
	_check(coward.alert == Monster.Alert.FLEEING, "one breaking: a coward who hears it breaks too")
	_check(routs == [&"rout"], "the one breaking cries out (%s)" % [routs])
	_check(bold.alert != Monster.Alert.FLEEING, "a bold one does not")
	bold._world_tick(1.0)
	coward._world_tick(1.0)
	_check(coward.alert == Monster.Alert.IDLE, "the world tick calms a runner too")
	Monster.idling = true

## Moves [param entity] to [param to] at once (a test's hand).
func _move_to(entity: GridEntity, to: Vector2i) -> void:
	World.despawn(entity)
	World.spawn(entity, to)


## A raid group's raiders: spawned into the room as a level's are, and a
## town at [param town] (its ground the cells within 1).
func _raid_room(rows: Array[String], town: Vector2i) -> Raids:
	var room := _build(rows)
	World.raids.clear()
	World.spawn_spec = func(spec: Dictionary) -> GridEntity:
		var entity := EntityFactory.build(spec)
		_room.add_child(entity)
		if not World.spawn(entity, spec["tile"]):
			entity.free()
			return null
		return entity
	var raids := World.raids
	raids.town_cell = func(_town: String, _area: String) -> Vector2i: return town
	raids.on_town = func(_town: String, cell: Vector2i) -> bool: return World.distance(cell, town) <= 1
	return raids


func _test_raid_march() -> void:
	print("\n== a raid group comes in as raiders of its faction, marches on the town, raids it and goes home ==")
	Monster.idling = true
	var raids := _raid_room(["##############################", "#............................#",
		"#............................#", "#............................#", "##############################"], Vector2i(26, 2))
	var arrived: Array[Dictionary] = []
	raids.arrive = func(town: String, group: Dictionary) -> Dictionary:
		arrived.append({"town": town, "group": group})
		return {"repelled": false, "took": {"food": 3, "items": []}, "captives": [{"id": "smith"}]}
	var done: Array[String] = []
	var left: Array[Dictionary] = []
	raids.raid_done.connect(func(id: String, _report: Dictionary) -> void: done.append(id))
	raids.raid_left.connect(func(id: String, strength: float, area: String, cell: Vector2i, carries: Dictionary) -> void:
		left.append({"id": id, "strength": strength, "area": area, "cell": cell, "carries": carries}))
	var count := raids.enter({"id": "g1", "faction": "goblins", "strength": 5.0, "town": "t"}, World.zone.name, Vector2i(2, 2))
	var kinds := {}
	for each in raids.raiders("g1"):
		kinds[each.spawn_spec["kind"]] = true
	_check(count >= 2 and kinds.keys().all(func(k: String) -> bool: return k in ["imp", "brute", "sneak"]),
			"its strength in goblins (%d: %s)" % [count, kinds.keys()])
	_check(is_equal_approx(raids.strength("g1"), 5.0), "their shares are its strength (%.2f)" % raids.strength("g1"))
	for i in 1500:
		World.step()
		if not done.is_empty():
			break
	_check(done == ["g1"] and arrived.size() == 1 and is_equal_approx(float(arrived[0]["group"]["strength"]), 5.0),
			"they reach the town, which is raided with the strength left (%s)" % [arrived])
	for i in 1500:
		World.step()
		if not left.is_empty():
			break
	_check(left.size() == 1 and World.distance(left[0]["cell"], Vector2i(2, 2)) <= Raids.ARRIVE_TILES + 1,
			"and go back the way they came, handed back to maps there (%s)" % [left])
	_check(not left.is_empty() and left[0]["carries"]["captives"] == ["smith"] and is_equal_approx(left[0]["strength"], 5.0),
			"with what they took and their strength")
	_check(raids.ids().is_empty() and World.monsters().is_empty(),
			"and off the map")


func _test_raid_beaten() -> void:
	print("\n== a raid group beaten drops what it carries; a zone gone to sleep hands it back ==")
	Monster.idling = true
	var raids := _raid_room(["##############################", "#............................#",
		"#............................#", "#............................#", "##############################"], Vector2i(26, 2))
	var beaten: Array[Dictionary] = []
	raids.raid_beaten.connect(func(id: String, area: String, cell: Vector2i) -> void:
		beaten.append({"id": id, "area": area, "cell": cell}))
	var sack := World.items.mint("sack", "raid test")
	raids.enter({"id": "g2", "faction": "goblins", "strength": 2.0, "town": "t", "carries": {"items": [sack], "captives": []}},
		World.zone.name, Vector2i(2, 2))
	_check(raids.raiders("g2").size() == 2, "two imps' worth, two raiders (%d)" % raids.raiders("g2").size())
	for i in 20:
		World.step()
	var first := raids.raiders("g2")[0]
	World.damage(first, 999)
	World.step()
	_check(beaten.is_empty() and is_equal_approx(raids.strength("g2"), 1.0), "one falls: half its strength (%.1f)" % raids.strength("g2"))
	var last := raids.raiders("g2")[0]
	var at := last.tile
	World.damage(last, 999)
	World.step()
	_check(beaten.size() == 1 and beaten[0]["cell"] == at, "the last falls: beaten where it fell (%s)" % [beaten])
	var dropped := false
	for cell: Vector2i in World.zone.ground:
		dropped = dropped or sack in World.zone.ground[cell]
	_check(dropped, "and what it carried lies there")
	var left: Array[String] = []
	raids.raid_left.connect(func(id: String, _s: float, _a: String, _c: Vector2i, _k: Dictionary) -> void: left.append(id))
	raids.enter({"id": "g3", "faction": "goblins", "strength": 2.0, "town": "t"}, World.zone.name, Vector2i(2, 2))
	raids.hand_back(World.zone.name)
	_check(left == ["g3"] and raids.ids().is_empty(), "its zone asleep, a group goes back to maps")


func _test_raid_takes() -> void:
	print("\n== a raider kills a player, but a companion it beats down is taken ==")
	Monster.idling = false
	var raids := _raid_room(["##########", "#........#", "#........#", "##########"], Vector2i(8, 1))
	raids.enter({"id": "g4", "faction": "goblins", "strength": 1.0, "town": "t"}, World.zone.name, Vector2i(2, 1))
	var raider := raids.raiders("g4")[0]
	var companion := EntityFactory.build({"script": "res://sim/companion.gd", "shape": "capsule", "name": "Garrow",
		"props": {"max_hp": 10}}) as Companion
	companion.keeper_id = "p1"
	_room.add_child(companion)
	World.spawn(companion, Vector2i(5, 2))
	var player := EntityFactory.build(SPECS["P"].merged({"name": "Pat", "props": {"max_hp": 10}})) as GridEntity
	_room.add_child(player)
	World.spawn(player, Vector2i(7, 2))
	var taken: Array = []
	var died: Array = []
	World.entity_taken.connect(func(e: GridEntity, by: String) -> void: taken.append([e, by]))
	var on_died := func(e: GridEntity, _cause: StringName) -> void: died.append(e)
	World.entity_died.connect(on_died)
	World.damage(companion, 999, raider)
	_check(taken.size() == 1 and taken[0][0] == companion and taken[0][1] == "g4" and companion.hp == 1
			and not died.has(companion), "a companion beaten down by a raider is taken, at 1 hp, not killed")
	_check(raids.carries("g4")["captives"] == ["companion:p1"], "and the group carries her off (%s)" % [raids.carries("g4")])
	World.damage(player, 999, raider)
	_check(died.has(player), "a player it beats down dies")
	var freed: Array[String] = []
	World.companion_freed = func(who: String, place: String) -> void: freed.append(who + "@" + place)
	World.damage(raider, 999)
	World.step()
	_check(freed == ["p1@"], "the group beaten, the companion it took is free, back beside her player (%s)" % [freed])
	World.companion_freed = Callable()
	World.entity_died.disconnect(on_died)
	World.spawn_spec = Callable()
	raids.clear()
	Monster.idling = true


## Wild: out of doors, under one kind of weather always (Weather.KINDS);
## the way the wind blows then.
func _outdoors(kind: String) -> Vector2:
	Weather.use({"default": {"weights": {kind: 1}}})
	World.fields.outdoor = true
	World.fields.update_weather(DayNight.now())
	return World.fields.weather.get("wind_dir", Vector2.ZERO)


func _indoors() -> void:
	World.fields.outdoor = false
	World.fields.update_weather(DayNight.now())
	Weather.reload()


func _test_wild_kinds() -> void:
	print("\n== animals are rows of monsters.json of side wild: Animals, of no side but their herd's ==")
	_check(Animal.is_wild("deer") and Animal.is_wild("wolf") and not Animal.is_wild("imp"), "deer and wolves are wild, imps not")
	_check(Level._spec_for("monster_deer", Level.MONSTER_TYPES)["script"] == Level.ANIMAL
			and Level._spec_for("monster_imp", Level.MONSTER_TYPES)["script"] == Level.MONSTER, "a level's deer is an Animal")
	var e := _build(["##########", "#d.D.o.i.#", "##########"])
	var doe: Animal = e["d"][0]
	_check(doe._same_side(e["D"][0]) and not doe._same_side(e["o"][0]) and not doe._same_side(e["i"][0]),
			"a doe's side: the stag (her herd), not a boar or an imp")
	_check(not (e["i"][0] as Monster)._same_side(e["o"][0]) and not (e["i"][0] as Monster)._same_side(doe),
			"an imp's side has no animals in it")


func _test_wild_prey() -> void:
	print("\n== prey grazes; it bolts from whoever it sees, and the herd with it ==")
	Monster.idling = true
	var e := _build(["####################", "#..................#", "#.........d.D......#", "#..................#",
		"#..................#", "####################"], {"d": {"facing": Vector2i(-1, 0)}})
	var doe: Animal = e["d"][0]
	var stag: Animal = e["D"][0]
	doe.sight_range = 9
	stag.sight_range = 9
	for i in 80:
		World.step()
	_check(doe.alert == Monster.Alert.IDLE and (doe.pose == Monster.Pose.SIT or stag.pose == Monster.Pose.SIT),
			"nobody about: they graze (head down between strolls)")
	var player := EntityFactory.build(SPECS["P"].merged({"name": "Hunter"})) as GridEntity
	_room.add_child(player)
	World.spawn(player, doe.tile + Vector2i(-4, 0))
	World.face(doe, Vector2i(-1, 0))
	doe.pose = Monster.Pose.STAND
	var cries: Array[StringName] = []
	doe.cried.connect(func(kind: StringName) -> void: cries.append(kind))
	World.step()
	World.step()
	_check(doe.alert == Monster.Alert.FLEEING and cries == [&"rout"], "the doe sees a hunter and bolts, crying (%s %s)" % [Monster.Alert.keys()[doe.alert], cries])
	World.step()
	_check(stag.alert == Monster.Alert.FLEEING, "the stag of her herd bolts with her")
	var before := World.distance(doe.tile, player.tile)
	for i in 25:
		World.step()
	_check(World.distance(doe.tile, player.tile) > before, "away from the hunter (%d off)" % World.distance(doe.tile, player.tile))


func _test_wild_ears() -> void:
	print("\n== a step heard: head up, turned to it; a fight heard: off ==")
	Monster.idling = true
	var e := _build(["##############", "#............#", "#....r.......#", "#............#", "##############"],
		{"r": {"facing": Vector2i(1, 0)}})
	var rabbit: Animal = e["r"][0]
	rabbit.sight_range = 0  # Sees nothing: ears only.
	World.noise(rabbit.tile + Vector2i(-3, 0), 3, &"step", null)
	World.step()
	_check(rabbit.alert == Monster.Alert.SUSPICIOUS and rabbit.facing == Vector2i(-1, 0) and rabbit.pose == Monster.Pose.STAND,
			"a step behind it: it turns to it, head up, and stays (%s, %s)" % [Monster.Alert.keys()[rabbit.alert], rabbit.facing])
	World.noise(rabbit.tile + Vector2i(-3, 0), Senses.NOISE_FIGHT, &"fight", null)
	World.step()
	_check(rabbit.alert == Monster.Alert.FLEEING, "a fight: it bolts")


func _test_wild_scent() -> void:
	print("
== downwind of you it smells you before it sees you; upwind it does not ==")
	Monster.idling = false
	var rows: Array[String] = ["#########################"]
	for y in 23:
		rows.append("#.......................#")
	rows.append("#########################")
	for downwind in [true, false]:
		var e := _build(rows)
		var doe := EntityFactory.build(SPECS["d"].merged({"name": "Doe", "props": Level.MONSTER_TYPES["deer"]})) as Animal
		_room.add_child(doe)
		World.spawn(doe, Vector2i(12, 12))
		doe.sight_range = 9
		var blows := _outdoors("wind")
		var way := Vector2i(roundi(blows.x * 7.0), roundi(blows.y * 7.0))
		var player := EntityFactory.build(SPECS["P"].merged({"name": "Hunter"})) as GridEntity
		_room.add_child(player)
		World.spawn(player, doe.tile - way if downwind else doe.tile + way)
		# Looking away from the hunter.
		World.face(doe, Senses.way_toward(player.tile, doe.tile))
		World.step()
		World.step()
		if downwind:
			_check(doe.alert == Monster.Alert.FLEEING, "the wind from the hunter to the doe: she smells them, 7 off, and bolts")
		else:
			_check(doe.alert != Monster.Alert.FLEEING, "the wind the other way: she grazes on, none the wiser")
	_indoors()
	Monster.idling = true


func _test_wild_boar() -> void:
	print("\n== a boar struck charges whoever struck it, crying; then runs ==")
	Monster.idling = false
	var e := _build(["############", "#..........#", "#....Po....#", "#..........#", "############"],
		{"o": {"facing": Vector2i(1, 0)}})
	var boar: Animal = e["o"][0]
	var player: GridEntity = e["P"][0]
	boar.sight_range = 6
	var cries: Array[StringName] = []
	boar.cried.connect(func(kind: StringName) -> void: cries.append(kind))
	World.damage(boar, 2, player)
	World.step()
	_check(boar.alert == Monster.Alert.FIGHTING and boar.target == player and cries == [&"charge"],
			"struck, it turns on the striker (%s, %s)" % [Monster.Alert.keys()[boar.alert], cries])
	for i in Animal.CHARGE_TICKS + 5:
		World.step()
	_check(boar.alert == Monster.Alert.FLEEING or World.distance(boar.tile, player.tile) > 1,
			"its charge spent, it runs (%s)" % Monster.Alert.keys()[boar.alert])
	Monster.idling = true


func _test_wild_wolf() -> void:
	print("\n== a wolf hunts deer; by day it lets a lone hunter be, by night it does not ==")
	Monster.idling = false
	var e := _build(["####################", "#..................#", "#..P.w.....d.......#", "#..................#",
		"####################"], {"w": {"facing": Vector2i(1, 0)}, "d": {"facing": Vector2i(1, 0)}})
	var wolf: Animal = e["w"][0]
	var doe: Animal = e["d"][0]
	wolf.sight_range = 8
	doe.sight_range = 6
	_outdoors("clear")
	DayNight.set_hour(12.0)
	for i in 3:
		World.step()
	_check(wolf.target == doe, "by day it goes for the doe, not the hunter behind it (%s)" % [wolf.target])
	for i in 30:
		World.step()
	_check(doe.alert == Monster.Alert.FLEEING, "she hears it coming and runs")
	e = _build(["####################", "#..................#", "#..P.w.............#", "#..................#",
		"####################"], {"w": {"facing": Vector2i(-1, 0)}})
	wolf = e["w"][0]
	wolf.sight_range = 8
	_outdoors("clear")
	DayNight.set_hour(12.0)
	for i in 3:
		World.step()
	_check(wolf.target == null, "by day, facing a lone hunter, it lets them be")
	DayNight.set_hour(0.0)
	for i in Animal.PREY_LOOK_TICKS + 2:
		World.step()
	_check(wolf.target == e["P"][0] and wolf.temper == Monster.Temper.BOLD, "at night it is bold, and goes for them")
	DayNight.reset()
	_indoors()
	Monster.idling = true

func _test_noticing() -> void:
	print("
== Monster.noticing off (a test staging a level): nobody is noticed ==")
	Monster.idling = false
	var e := _build(["#########", "#.P..i..#", "#########"], {"i": {"facing": Vector2i(-1, 0)}})
	var imp: Monster = e["i"][0]
	imp.sight_range = 7
	imp.reaction_ticks = 0
	Monster.noticing = false
	for i in 5:
		World.step()
	_check(imp.target == null and imp.alert == Monster.Alert.IDLE, "an imp facing a player lets them be")
	Monster.noticing = true
	World.step()
	_check(imp.alert == Monster.Alert.FIGHTING, "on again, it goes for them")
	Monster.idling = true


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


func _test_wild_remains() -> void:
	print("
== a slain animal leaves its kind's drops on the ground; an imp leaves nothing ==")
	Monster.idling = true
	var e := _build(["############", "#..........#", "#..D....i..#", "#..........#", "############"])
	var stag: Animal = e["D"][0]
	var imp: Monster = e["i"][0]
	var at := stag.tile
	World.damage(stag, stag.hp)
	var laid: Array[String] = []
	for cell: Vector2i in World.zone.ground:
		if World.distance(cell, at) <= World.GROUND_SPILL:
			for id in World.ground_at(cell):
				laid.append(id)
	var meat := laid.count("meat")
	_check(not stag.spawned and meat >= 4 and meat <= 5 and laid.count("hide") == 1 and laid.count("antlers") == 1
			and laid.size() == meat + 2, "the stag: 4-5 meat, a hide, its antlers, about where it fell (%s)" % [laid])
	var uid: int = World.ground_uids(World.zone.ground.keys().filter(
			func(cell: Vector2i) -> bool: return "antlers" in World.ground_at(cell))[0])[0]
	_check(World.items.history(uid)["events"][0]["kind"] == "remains", "the antlers' history begins as its remains")
	var before := World.zone.ground.size()
	World.damage(imp, imp.hp)
	_check(not imp.spawned and World.zone.ground.size() == before, "an imp's row drops nothing")


func _test_lead_occupied() -> void:
	print("
== its lead stood on (a crate): round the wall to beside it, on the door search's way ==")
	Monster.idling = false
	var e := _build(["##########", "#i.#.....#", "#..#..c..#", "#..#.....#", "#........#", "##########"])
	var monster: Monster = e["i"][0]
	var crate: GridEntity = e["c"][0]
	monster._follow(crate.tile, Monster.Alert.SUSPICIOUS, 400)
	var closest := World.distance(monster.tile, crate.tile)
	for i in 150:
		World.step()
		closest = mini(closest, World.distance(monster.tile, crate.tile))
	_check(closest <= 1, "it got beside the crate on its lead (%d off at best)" % closest)
	Monster.idling = true


func _test_raid_townsfolk() -> void:
	print("\n== a raider goes for a town's resident too, and takes one it beats down; other monsters let them be ==")
	Monster.idling = false
	var raids := _raid_room(["############", "#..........#", "#......i...#", "#..........#", "############"], Vector2i(10, 1))
	var imp: Monster = World.monsters()[0]
	raids.enter({"id": "g5", "faction": "goblins", "strength": 1.0, "town": "t"}, World.zone.name, Vector2i(2, 2))
	var raider := raids.raiders("g5")[0]
	var smith := EntityFactory.build({"script": "res://sim/resident.gd", "shape": "capsule", "name": "Smith"}) as Resident
	smith.worker_id = "w1"
	_room.add_child(smith)
	World.spawn(smith, Vector2i(4, 2))
	_bold(raider)
	_bold(imp)
	World.step()
	World.step()
	_check(raider.target == smith, "the raider goes for the resident (%s)" % [raider.target])
	_check(imp.target == null, "the imp that is no raider lets the resident be")
	var taken: Array = []
	var on_taken := func(e: GridEntity, by: String) -> void: taken.append([e, by])
	World.entity_taken.connect(on_taken)
	World.damage(smith, 999, raider)
	_check(taken.size() == 1 and taken[0][0] == smith and taken[0][1] == "g5", "beaten down, the resident is taken")
	_check("resident:w1" in raids.carries("g5")["captives"], "the group carries them off (%s)" % [raids.carries("g5")])
	var resting := EntityFactory.build({"script": "res://sim/resident.gd", "shape": "capsule", "name": "Garrow"}) as Resident
	resting.worker_id = "companion:p1"  # A companion resting in town.
	_room.add_child(resting)
	World.spawn(resting, Vector2i(5, 3))
	World.damage(resting, 999, raider)
	_check("companion:p1" in raids.carries("g5")["captives"] and "resident:companion:p1" not in raids.carries("g5")["captives"],
			"a companion resting in town goes as a companion (%s)" % [raids.carries("g5")])
	World.entity_taken.disconnect(on_taken)
	World.spawn_spec = Callable()
	raids.clear()
	Monster.idling = true


func _test_charging() -> void:
	print("\n== charging(): a brute closing its last tiles, a boar in its charge ==")
	Monster.idling = false
	var e := _build(["##############", "#P..........b#", "##############"])
	var brute: Monster = e["b"][0]
	_bold(brute)
	var charged := false
	for i in 40:
		World.step()
		if brute.charging():
			charged = World.distance(brute.tile, e["P"][0].tile) <= Monster.CHARGE_RANGE
			break
	_check(charged, "the brute charges its last CHARGE_RANGE tiles")
	e = _build(["############", "#..........#", "#....Po....#", "#..........#", "############"])
	var boar: Animal = e["o"][0]
	_check(not boar.charging(), "a boar grazing is not charging")
	World.damage(boar, 2, e["P"][0])
	World.step()
	_check(boar.charging(), "struck, the boar charges")
	Monster.idling = true


func _test_archer() -> void:
	print("\n== an archer stands off, draws and shoots; holds while someone is in the way; steps back from one close ==")
	Monster.idling = false
	var e := _build(["##############", "#............#", "#.P......a...#", "#............#", "##############"])
	var archer: Monster = e["a"][0]
	var player: GridEntity = e["P"][0]
	_bold(archer)
	archer.slots = PackedStringArray(["", "", "", "", "bow", ""])  # As Level arms one wielding a bow.
	_check(World.off_hand(archer) == "draw", "a bow in its hands: it draws")
	var from := archer.tile
	var shot: Dictionary = {}
	var drawn := false
	for i in 40:
		World.step()
		drawn = drawn or archer.raised == "draw"
		for hit: Dictionary in _damage_log:
			if hit["cause"] == &"shot" and hit["source"] == archer:
				shot = hit
		if not shot.is_empty():
			break
	_check(drawn and not shot.is_empty() and shot["entity"] == player and archer.tile == from,
			"it draws where it stands and shoots the player 7 off (%s)" % [shot])
	_check(not shot.is_empty() and int(shot["tick"]) >= 20, "at full draw (tick %s)" % shot.get("tick"))
	# Struck as it draws: the draw starts again.
	for i in 12:
		World.step()
	var was := World.draw_of(archer)
	World.damage(archer, 1, player)
	World.step()
	_check(was > 0.0 and World.draw_of(archer) < was, "struck while drawing, its draw is spoilt (%.2f to %.2f)" % [was, World.draw_of(archer)])
	# Someone in the way (a friend would be; a crate stays put): it does
	# not shoot from there, but moves till it has a clear line.
	e = _build(["##############", "#............#", "#.P...c..a...#", "#............#", "##############"])
	archer = e["a"][0]
	_bold(archer)
	archer.slots = PackedStringArray(["", "", "", "", "bow", ""])  # As Level arms one wielding a bow.
	from = archer.tile
	var shot_from := Vector2i(-1, -1)
	for i in 60:
		World.step()
		if shot_from == Vector2i(-1, -1) and _damage_log.any(func(hit: Dictionary) -> bool: return hit["cause"] == &"shot"):
			shot_from = archer.tile
	_check(shot_from != Vector2i(-1, -1) and shot_from != from and shot_from.y != from.y,
			"a crate on its line: it moves off it (to %s), then shoots" % [shot_from])
	# One too close.
	e = _build(["##############", "#............#", "#....P.a.....#", "#............#", "##############"])
	archer = e["a"][0]
	player = e["P"][0]
	_bold(archer)
	archer.slots = PackedStringArray(["", "", "", "", "bow", ""])  # As Level arms one wielding a bow.
	for i in 10:
		World.step()
	_check(World.distance(archer.tile, player.tile) >= Monster.KEEP_NEAR, "2 off, it steps back to %d" % World.distance(archer.tile, player.tile))
	Monster.idling = true


func _test_shield() -> void:
	print("\n== a shield is up, turned to its foe, while it is near; down far off or out of breath; a sneak goes round a raised one ==")
	Monster.idling = false
	var e := _build(["############", "#..........#", "#.P......i.#", "#..........#", "############"])
	var imp: Monster = e["i"][0]
	var player: GridEntity = e["P"][0]
	_bold(imp)
	imp.slots = PackedStringArray(["", "", "", "", "", "shield"])  # As Level arms one wielding a shield.
	World.step()
	_check(World.off_hand(imp) == "block" and imp.raised.is_empty(), "far off, its shield is down")
	for i in 40:
		World.step()
		if World.distance(imp.tile, player.tile) <= Monster.GUARD_TILES:
			break
	World.step()
	_check(imp.raised == "block" and not World.guarding(imp, player).is_empty(),
			"near, it is up and turned to the player (%s, facing %s)" % [imp.raised, imp.facing])
	imp.stamina = 5
	World.step()
	_check(imp.raised.is_empty(), "out of breath, it lowers it")
	# A sneak against a player's raised shield: it strikes round it.
	e = _build(["############", "#..........#", "#....P.s...#", "#..........#", "############"])
	player = e["P"][0]
	var sneak: Monster = e["s"][0]
	_bold(sneak)
	player.slots[Items.LEFT_HAND] = "shield"
	World.face(player, Vector2i(1, 0))
	World.try_stance(player, "block")
	var struck := 0
	for i in 60:
		World.step()
		for hit: Dictionary in _damage_log:
			if hit["source"] == sneak and int(hit["tick"]) == World.tick:
				struck += 1
	_check(struck > 0, "the sneak gets blows in (%d) round the shield" % struck)
	Monster.idling = true
