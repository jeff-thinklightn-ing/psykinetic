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
}
const NAMES := {"P": "Player", "m": "Monster", "i": "Imp", "b": "Brute", "s": "Sneak", "c": "Crate"}

var _failures := 0
var _room: Node2D
var _damage_log: Array[Dictionary] = []


func _ready() -> void:
	World.set_process(false)
	World.entity_damaged.connect(func(entity: GridEntity, amount: int, source: GridEntity, cause: StringName) -> void:
		_damage_log.append({"entity": entity, "amount": amount, "source": source, "cause": cause, "tick": World.tick}))

	_test_temper()
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
	_test_look_skipped_far()
	_test_straight_beyond_view()
	_test_plans_per_step()
	_test_walk_round_held_ground()
	_test_sight_cone()
	_test_sight_by_light()
	_test_hearing()
	_test_noise_reach()

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
	print("\n== a timid monster waits until another is at its target ==")
	var e := _build(["##########", "#........#", "#P...i...#", "#........#", "#.......i#", "##########"])
	var player: GridEntity = e["P"][0]
	var timid: Monster = e["i"][0]
	var other: Monster = e["i"][1]
	_bold(timid)
	_bold(other)
	timid.boldness = 0.0
	other.sight_range = 0
	for i in 40:
		World.step()
	_check(World.distance(timid.tile, player.tile) >= 2 and World.distance(timid.tile, player.tile) <= Monster.HOLD_BACK_RANGE,
			"alone, it hangs back (%d tiles off)" % World.distance(timid.tile, player.tile))
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
	monster.pause_chance = 0.0
	monster.reaction_ticks = 0
	monster.sight_range = 12
	monster.senses.cone_cos = -1.0  # All round: these test how it fights, not what it sees.


## [param extra]: per symbol, more for its spawn spec ({"b": {"facing": ...}}).
func _test_roster() -> void:
	print("
== what a monster looks for: the zone's players and companions, its monsters, kept up ==")
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
	print("
== far from everyone a monster thinks less often, or not at all ==")
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
	print("
== on nobody's screen an idler walks only straight; on someone's it finds a way round ==")
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
	print("
== far beyond its sight it does not look; someone come beside it is seen at once ==")
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


func _test_world_tick() -> void:
	print("
== the world tick moves a far monster on: back where it idles after a fight ==")
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
	print("
== a crowd that comes near at once works its patrols out over a few steps ==")
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
	print("
== a far monster walking back does not walk over ground another faction holds ==")
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


func _build(rows: Array[String], extra := {}) -> Dictionary:
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
	print("
== a monster of a kind sees in a cone before it; one of no kind all round ==")
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
	print("
== in the dark it sees only what is lit, or carries a light ==")
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


func _test_hearing() -> void:
	print("
== a monster hears steps, turns, and sees who made them ==")
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
	print("
== a noise carries its radius, half that through a wall; words further in capitals ==")
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


## Moves [param entity] to [param to] at once (a test's hand).
func _move_to(entity: GridEntity, to: Vector2i) -> void:
	World.despawn(entity)
	World.spawn(entity, to)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
