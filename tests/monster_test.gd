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
	"k": {"script": "res://sim/monster.gd", "shape": "capsule", "kind": "skeleton"},
	"g": {"script": "res://sim/monster.gd", "shape": "capsule", "kind": "skeleton_guard"},
	"x": {"script": "res://sim/monster.gd", "shape": "capsule", "kind": "robber"},
	"u": {"script": "res://sim/draugr.gd", "shape": "capsule", "kind": "draugr"},
}
const NAMES := {"P": "Player", "m": "Monster", "i": "Imp", "b": "Brute", "s": "Sneak", "c": "Crate",
	"r": "Rabbit", "d": "Doe", "D": "Stag", "o": "Boar", "w": "Wolf", "a": "Archer", "k": "Skeleton", "g": "Guard",
	"x": "Robber", "u": "Draugr"}

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
	_test_dread()
	_test_quarry_gone()
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
	_test_cover()
	_test_sight_by_light()
	_test_hearing()
	_test_noise_reach()
	_test_hunt()
	_test_downed_not_hunted()
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
	_test_clank()
	_test_band_stands()
	_test_wild_shot_near()
	_test_far_pace()
	_test_strike_cells()
	_test_rout_way_out()
	_test_named()
	_test_band()
	_test_wild_scent()
	_test_din()
	_test_wild_boar()
	_test_wild_wolf()
	_test_wild_remains()
	_test_kobold_dagger_and_pick()
	_test_herd_hunt()
	_test_herd_sleeps()
	_test_wolf_den()
	_test_lead_occupied()
	_test_raid_townsfolk()
	_test_sides_on_sight()
	_test_homeward()
	_test_room_guard()
	_test_struck_answers()
	_test_draugr()
	_test_draugr_paid()
	_test_ossuary_sealed()
	_test_fight_data()
	_test_fight_panel()
	_test_barrow_layers()
	_test_draugr_mind()
	_test_draugr_waves()
	_test_hall_waits()
	_test_room_leash()
	_test_two_zones_charge()
	_test_charging()
	_test_threatens()
	_test_quieter()
	_test_wolf_pack_bold()
	_test_archer()
	_test_archer_hold()
	_test_worn_bundles()
	_test_shield()
	_test_monster_bash()
	_test_monster_wind_up()
	_test_meets_wind_up()
	_test_bane_and_grudge()
	_test_boar_turns()
	_test_pick_up()
	_test_art_slots()

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
	for i in Monster.WINDUP_TICKS:
		if i < 3:
			World.free_input(player, Vector2(-1, 0), World.TICK_DT)  # A step back, out of its reach (699).
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


func _test_dread() -> void:
	print("\n== a dread weapon: cowards count its holder as two, the cautious wait for two and break sooner ==")
	var e := _build(["##########", "#........#", "#P...i...#", "#........#", "#........#", "##########"])
	var player: GridEntity = e["P"][0]
	var imp: Monster = e["i"][0]
	_bold(imp)
	imp.target = player
	imp.temper = Monster.Temper.CAUTIOUS
	imp.hp = int(imp.max_hp * 0.45)
	_check(imp._others_needed() == 1 and not imp._should_flee(), "a plain foe: the cautious wait for one, hold at 45% hp")
	var sword := World.items.mint("sword", "built", "test")
	World.put_item(player, player, Player.RIGHT_HAND, sword)
	World.items.set_name(sword, {"form": "holder_possessive", "holder": "Ash", "made_step": 0, "text": "Ash's sword"}, "dread")
	_check(World.holder_dread(player), "the player is dreaded")
	_check(imp._others_needed() == 2 and imp._should_flee(), "a dread holder: the cautious wait for two, break at 45% hp")
	imp.temper = Monster.Temper.BOLD
	_check(imp._others_needed() == 1 and not imp._should_flee(), "the bold take no notice")
	World.items.end(World.take_item(player, player, Player.RIGHT_HAND), "gone")
	var e1 := _build(["#######", "#P.i..#", "#######"])
	player = e1["P"][0]
	imp = e1["i"][0]
	_bold(imp)
	imp.target = player
	imp.temper = Monster.Temper.COWARDLY
	_check(not imp._should_flee(), "a coward alone against one plain foe stands")
	sword = World.items.mint("sword", "built", "test")
	World.put_item(player, player, Player.RIGHT_HAND, sword)
	World.items.set_name(sword, {"form": "holder_possessive", "holder": "Ash", "made_step": 0, "text": "Ash's sword"}, "dread")
	_check(imp._should_flee(), "against a dread holder it runs")
	var wolf := Animal.new()
	wolf.temper = Monster.Temper.CAUTIOUS
	wolf.target = player
	_check(not wolf._dreads_target(), "a wolf (cautious by its row) takes no notice")
	wolf.free()
	# Holding back: a cautious one bolder than HOLD_BACK_BELOW comes on
	# alone, but not at a dread holder.
	var e2 := _build(["##########", "#........#", "#P...i...#", "#........#", "#........#", "##########"])
	player = e2["P"][0]
	imp = e2["i"][0]
	_bold(imp)
	imp.temper = Monster.Temper.CAUTIOUS
	imp.boldness = 0.5
	sword = World.items.mint("sword", "built", "test")
	World.put_item(player, player, Player.RIGHT_HAND, sword)
	World.items.set_name(sword, {"form": "holder_possessive", "holder": "Ash", "made_step": 0, "text": "Ash's sword"}, "dread")
	for i in 40:
		World.step()
	_check(World.distance(imp.tile, player.tile) >= 2 and World.distance(imp.tile, player.tile) <= Monster.HOLD_BACK_RANGE,
			"a bold-enough cautious one hangs back from a dread holder (%d tiles off)" % World.distance(imp.tile, player.tile))
	World.items.end(World.take_item(player, player, Player.RIGHT_HAND), "gone")
	var closed := false
	for i in 30:
		World.step()
		if World.are_adjacent(imp.tile, player.tile):
			closed = true
	_check(closed, "the sword gone, it comes on")


func _test_quarry_gone() -> void:
	print("\n== hunting past its leash a quarry since gone, it gives up and goes back ==")
	var e := _build(["##########", "#....i...#", "##########"])
	var imp: Monster = e["i"][0]
	_bold(imp)
	var gone := GridEntity.new()
	imp._quarry = gone
	gone.free()
	imp.alert = Monster.Alert.HUNTING
	imp._alert_until = World.tick + 100
	imp._post = imp.tile + Vector2i(imp.leash + 5, 0)
	imp._alert_tick()
	_check(imp.alert == Monster.Alert.IDLE and imp._returning, "calm and going back (alert %d)" % imp.alert)


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
				and replication.has_property(NodePath(".:pose")) and replication.has_property(NodePath(".:raised")) \
				and replication.has_property(NodePath(".:raised_tick")) and replication.has_property(NodePath(".:hands")) \
				and replication.property_get_spawn(NodePath(".:hands")) and not replication.has_property(NodePath(".:slots"))
	_check(config_ok, "replicated to every peer, from its spawn on (facing, its pose, its bow drawn or guard up and since when, its hands but not its pack)")


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
## [param zone_name]: the zone named so before anything spawns (a level
## registered under it gives its level.json: graves, anchors).
func _build(rows: Array[String], extra := {}, edges := {}, zone_name := "") -> Dictionary:
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
	if zone_name != "":
		World.zone.name = zone_name
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


func _test_cover() -> void:
	print("\n== tall grass hides one still in it; a mover is glimpsed far off, seen near or followed (decision 508) ==")
	Monster.idling = false
	var e := _build(["#############", "#...........#", "#...........#", "#.b.....P...#", "#...........#", "#...........#", "#############"],
			{"b": {"facing": Vector2i(1, 0)}})
	var brute: Monster = e["b"][0]
	var player: GridEntity = e["P"][0]
	brute.sight_range = 7
	var grass: Array[Vector2i] = []
	for x in range(6, 11):
		for y in range(1, 6):
			grass.append(Vector2i(x, y))
	World._load_cover({"tall_grass": grass})
	var d := World.distance(brute.tile, player.tile)
	player.emit_light = 0.0  # No lantern (its own case below).
	player.last_step_tick = World.tick - Senses.STILL_TICKS
	World.step()
	_check(World.cover_at(player.tile) > 0.0 and brute.target == null and not brute.senses.sees(player, d, false),
			"still in the grass %d off, it is not seen, nor kept by one that had it" % d)
	player.last_step_tick = World.tick
	_check(not brute.senses.sees(player, d) and brute.senses.glimpses(player, d),
			"moving in it far off: not seen, but glimpsed (the grass stirs)")
	_check(brute.senses.sees(player, d, false), "but one already following it keeps it while it moves")
	_move_to(player, Vector2i(6, 3))
	player.last_step_tick = World.tick
	_check(not brute.senses.sees(player, 4), "moving 4 off in 0.7 grass, sight 7: still past 7 x 0.3, not seen")
	brute.sight_range = 14
	_check(brute.senses.sees(player, 4), "within its sight x (1 - cover), seen")
	brute.sight_range = 7
	player.last_step_tick = World.tick - Senses.STILL_TICKS
	_move_to(player, Vector2i(3, 3))
	_check(brute.senses.sees(player, 1), "beside it, seen still or not")
	_move_to(player, Vector2i(5, 3))
	_check(brute.senses.sees(player, 3), "out of the grass, seen still")
	_move_to(player, Vector2i(8, 3))
	player.emit_light = Player.LANTERN
	_check(World.light_at(player.tile, false) >= Senses.DARK and not brute.senses.sees(player, d),
			"its lantern lit by day gives nothing away (in the dark it would: Senses.hidden_by_cover)")
	player.last_step_tick = World.tick
	_check(not brute.senses.sees(player, d) and brute.senses.glimpses(player, d), "moving, lantern and all, it is glimpsed")
	player.last_step_tick = World.tick - Senses.STILL_TICKS
	player.emit_light = 0.0
	var companion := EntityFactory.build({"script": "res://sim/companion.gd", "shape": "capsule", "name": "Garrow",
		"props": {"max_hp": 10}}) as Companion
	_room.add_child(companion)
	World.spawn(companion, Vector2i(3, 1))
	companion.facing = Vector2i(1, 0)
	_check(not companion.senses.sees(player), "a companion not hers does not see the still player in the grass")
	companion.keeper = player
	_check(companion.senses.sees(player), "her own player she sees in the grass, still or moving")
	World._load_cover({})


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
	var start := player.tile
	for i in 5:
		if not moved:
			World.free_input(player, Vector2(0, -1), World.TICK_DT)  # Walked free: a cell's claim is a step.
		World.step()
		moved = player.tile != start
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


func _test_downed_not_hunted() -> void:
	print("
== its target downed (Mortally Wounded): not lost but fallen; no hunt, back to its idle ==")
	Monster.idling = true
	var e := _build(["##########", "#........#", "#.i......#", "#........#", "#....P...#", "##########"], {"i": {"facing": Vector2i(1, 1)}})
	var imp: Monster = e["i"][0]
	var player: GridEntity = e["P"][0]
	imp.sight_range = 7
	imp.reaction_ticks = 0
	World.step()
	_check(imp.target == player and imp.alert == Monster.Alert.FIGHTING, "it sees them: fighting")
	World.lay_downed(player, 300)
	World.step()
	_check(imp.target == null and imp.alert != Monster.Alert.HUNTING and imp.alert != Monster.Alert.FIGHTING,
		"downed: no target, and no hunt over the body (%s)" % Monster.Alert.keys()[imp.alert])
	World.raise_downed(player, player.max_hp)  # World.reset keeps its downed: none left behind.


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
	var by_hand := World.try_toggle_door(player, SPLIT_DOOR)
	var held := player.tile
	for i in 4:
		World.free_input(player, Vector2(1, 0), World.TICK_DT)  # Walking free into it.
		World.step()
	_check(not by_hand and player.tile == held and not door.open,
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
	_check(str(kinds["robber"]["person"]).contains("headwear=hood") and str(kinds["imp"]["person"]) == "",
			"a row's person words are kept (the robber's hood), none for an imp")
	_check(kinds["draugr"]["swing_stamina"] == true and kinds["draugr"]["stamina_regen_every"] > 1 and kinds["draugr"]["stamina_regen"] > 0
			and kinds["imp"]["swing_stamina"] == false and kinds["imp"]["stamina_regen_every"] == 1 and kinds["imp"]["stamina_regen"] == 0,
			"and its breath: the draugr pays his swings, %d back every %d ticks; an imp neither" % [kinds["draugr"]["stamina_regen"], kinds["draugr"]["stamina_regen_every"]])
	_check(kinds["draugr"]["blows"].has("battle_axe") and kinds["imp"]["blows"].is_empty(), "and the draugr's own blow with his axe (603 amended); an imp none")
	var robber := EntityFactory.build({"script": Level.MONSTER, "shape": "capsule", "props": {}, "kind": "robber", "name": "Robber", "tile": Vector2i(1, 1)})
	_check(Client3D.person_words(robber) == str(kinds["robber"]["person"]), "so the client draws a robber as a person, not a capsule")
	robber.free()


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
	# Two near: the coward and the bold one no longer outnumber them (698).
	e = _build(["################", "#..............#", "#.PPi...i...b..#", "#..............#", "################"])
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
	var labels := ["deer", "stag", "boar", "rabbit", "wolf", "imp"].map(
			func(kind: String) -> String: return str(Level._spec_for("monster_" + kind, Level.MONSTER_TYPES).get("label", "")))
	_check(labels == ["Wild doe", "Wild stag", "Wild boar", "Wild rabbit", "Wolf", ""],
			"an animal's spec is labelled by its kind, no number; an imp's not (%s)" % [labels])
	_check(["deer", "stag", "boar", "rabbit", "wolf"].all(func(kind: String) -> bool: return Monster.art_of(kind) == "creature." + kind),
			"each animal names its creature slot")
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


## Worn armour clanks (676 1b, physics' World.try_move; Jeff: "armor should
## add a clank sound that scares prey"): its own kind beside the step, so
## game bolts from it within its reach, turns only to a step, and a monster
## goes to look.
## A band counts its own (Jeff on v0.1.186, the barrow: "the grave robbers
## tend to scatter upon us entering the room not putting up a fight even
## though theres 4 of them"): four cowards spread over a room stand against
## a player and a companion; with two of them down, the rest may break. A
## pair is no band (band_min), and none closes on one in his spawn grace.
func _test_band_stands() -> void:
	print("\n== four robbers stand against two; two down, the rest may break; a pair holds back; the spawn grace holds ==")
	Monster.idling = false
	var e := _build(["##################", "#................#", "#.........x......#", "#............x...#", "#......P........#",
		"#......P........#", "#..........x.....#", "#.............x..#", "#................#", "##################"])
	var band: Array = e["x"]
	for robber: Monster in band:
		robber.temper = Monster.Temper.COWARDLY
		robber.sight_range = 8  # A lit room, eyes all round: they see the two come in.
		robber.senses.cone_cos = -1.0
	var broke := []
	for i in 40:
		World.step()
		for robber: Monster in band:
			if robber.alert == Monster.Alert.FLEEING and not robber in broke:
				broke.append(robber)
	var fighting := band.filter(func(r: Monster) -> bool: return r.alert == Monster.Alert.FIGHTING)
	var closed := band.filter(func(r: Monster) -> bool: return e["P"].any(func(p: GridEntity) -> bool: return World.are_adjacent(r.tile, p.tile)))
	_check(broke.is_empty() and fighting.size() == 4 and closed.size() >= 2,
			"four against two: none breaks, they close and fight (%d broke, %d fighting, %d at them)" % [broke.size(), fighting.size(), closed.size()])
	for robber: Monster in [band[0], band[1]]:
		robber.hp = robber.max_hp
		World.despawn(robber)
	var rest: Array = [band[2], band[3]]
	for robber: Monster in rest:
		robber.hp = robber.max_hp
	for i in 10:
		World.step()
	_check(rest.all(func(r: Monster) -> bool: return r.alert != Monster.Alert.FLEEING),
			"two down: the pair left is no band, but not alone either: they fight on, as a pair did")
	rest[0].hp = rest[0].max_hp / 2  # Under a coward's FLEE_BELOW: it breaks, crying a rout.
	for i in 10:
		World.step()
	_check(rest.all(func(r: Monster) -> bool: return r.alert == Monster.Alert.FLEEING),
			"one of them hurt: it breaks, and its rout breaks the other (%s)" % [rest.map(func(r: Monster) -> String: return Monster.Alert.keys()[r.alert])])
	# A pair is no band (band_min 3): it holds back as before 698.
	e = _build(["##################", "#................#", "#.........x......#", "#......P.........#",
		"#......P.........#", "#..........x.....#", "#................#", "##################"])
	for robber: Monster in e["x"]:
		robber.temper = Monster.Temper.CAUTIOUS
		robber.sight_range = 8
		robber.senses.cone_cos = -1.0
	for i in 40:
		World.step()
	var pair_at := (e["x"] as Array).filter(func(r: Monster) -> bool: return e["P"].any(func(p: GridEntity) -> bool: return World.are_adjacent(r.tile, p.tile)))
	_check(pair_at.is_empty(), "a pair of cautious ones against two: they hold back, as before (%d at them)" % pair_at.size())
	# One just come back (spawn grace, Main.SPAWN_GRACE_TICKS): no band closes on him.
	e = _build(["############", "#..........#", "#..a...a...#", "#....P.....#", "#..a...a...#", "#....a.....#", "############"])
	var back: GridEntity = e["P"][0]
	for imp: Monster in e["a"]:
		imp.temper = Monster.Temper.CAUTIOUS
		imp.sight_range = 8
		imp.senses.cone_cos = -1.0
	World.protect(back, 30)
	var full: int = back.hp
	var aimed := false
	for i in 28:  # The grace ends on its 30th tick.
		World.step()
		aimed = aimed or (e["a"] as Array).any(func(m: Monster) -> bool: return m.target == back)
	_check(back.hp == full and not aimed, "five beside one in his spawn grace: none goes for him (%d of %d hp)" % [back.hp, full])
	for i in 30:
		World.step()
	_check((e["a"] as Array).any(func(m: Monster) -> bool: return m.target == back), "the grace over, they do")
	Monster.idling = true


func _test_clank() -> void:
	print("\n== a clank heard: game bolts, a monster goes to look; a step only turns it ==")
	Monster.idling = true
	var e := _build(["####################", "#P.................#", "#........r.........#", "#..................#",
		"####################"], {"r": {"facing": Vector2i(1, 0)}})
	var rabbit: Animal = e["r"][0]
	var player: GridEntity = e["P"][0]
	rabbit.sight_range = 0  # Sees nothing: ears only.
	var off := rabbit.tile + Vector2i(-6, 0)
	World.noise(off, 6, &"step", player)
	World.step()
	_check(rabbit.alert == Monster.Alert.SUSPICIOUS and rabbit.facing == Vector2i(-1, 0),
			"a step 6 off, heard: it turns to it and stays (%s)" % Monster.Alert.keys()[rabbit.alert])
	World.noise(off, 5, &"clank", player)
	World.step()
	_check(rabbit.alert != Monster.Alert.FLEEING, "a clank that carries 5, from 6 off: not heard (%s)" % Monster.Alert.keys()[rabbit.alert])
	World.noise(off, 8, &"clank", player)
	World.step()
	_check(rabbit.alert == Monster.Alert.FLEEING, "a clank that carries 8: it bolts (%s)" % Monster.Alert.keys()[rabbit.alert])
	Monster.idling = false
	e = _build(["##########", "#........#", "#...b....#", "#........#", "#........#", "#.......P#", "##########"],
			{"b": {"facing": Vector2i(0, -1)}})
	var brute: Monster = e["b"][0]
	brute.sight_range = 3
	World.noise(Vector2i(8, 4), 8, &"clank", e["P"][0])
	World.step()
	_check(brute.alert == Monster.Alert.SUSPICIOUS and brute._lead == Vector2i(8, 4), "a monster hears it: it goes to look (%s, %s)" % [
		Monster.Alert.keys()[brute.alert], brute._lead])
	Monster.idling = true


## A miss lands with a thud (397 amended (2); Jeff's hunting: "you want to
## have distance"): game beside where the arrow fell bolts, far from the bow.
func _test_wild_shot_near() -> void:
	print("
== a shot that misses lands with a thud: game beside it bolts, far from the bow ==")
	Monster.idling = true
	var e := _build(["######################", "#....................#", "#.m..................#", "#....................#",
		"######################"])
	var archer: Monster = e["m"][0]
	archer.slots = PackedStringArray(["", "", "", "", "bow", "arrows"])
	var verb := Items.verb_of("bow")
	var step := (verb["steps"] as Array).size() - 1
	var aim: Dictionary = World.shot_aim(archer, 0.0, int(verb["steps"][step]))
	var fell: Vector2i = aim["cell"]
	var spec := {"script": "res://sim/animal.gd", "shape": "capsule", "kind": "rabbit", "name": "ShotRabbit", "tile": fell + Vector2i(0, 1)}
	var rabbit := EntityFactory.build(spec) as Animal
	_room.add_child(rabbit)
	World.spawn(rabbit, fell + Vector2i(0, 1))
	rabbit.sight_range = 0  # Ears only.
	_check(World.distance(archer.tile, rabbit.tile) > World.NOISE_BOW + 1, "the rabbit far beyond the bow's own noise (%d cells)" % World.distance(archer.tile, rabbit.tile))
	World.step()
	_check(rabbit.alert != Monster.Alert.FLEEING, "it grazes on")
	_check(World.shoot(archer, 0.0, step) == null, "a shot along the row, past it")
	World.step()
	_check(rabbit.alert == Monster.Alert.FLEEING, "the arrow falls beside it with a thud: it bolts (%s)" % Monster.Alert.keys()[rabbit.alert])
	World.despawn(rabbit)


## Smooth where it is seen (Jeff's hunting: "the stag started to run and
## phase glitch while at a distance"): past NEAR_TILES a monster on MID
## stepped only on its every MID_EVERY_TICKS think, a cell at twice its
## pace, the client's tween at its pace running and stopping. One fleeing
## keeps every tick, as one with a target does, and so does one walking
## within VIEW_TILES (238 amended (2)): its steps come at its pace.
func _test_far_pace() -> void:
	print("%s== past %d cells, a fleeing stag and a walking brute step at their own pace ==" % [char(10), World.NEAR_TILES])
	Monster.idling = true
	var rows: Array[String] = ["#".repeat(70)]
	for y in 5:
		rows.append("#" + ".".repeat(68) + "#")
	rows.append("#".repeat(70))
	var e := _build(rows)
	var hunter := EntityFactory.build(SPECS["P"].merged({"name": "FarHunter"})) as GridEntity
	_room.add_child(hunter)
	World.spawn(hunter, Vector2i(2, 3))
	var stag := EntityFactory.build({"script": "res://sim/animal.gd", "shape": "capsule", "kind": "stag", "name": "FarStag", "tile": Vector2i(12, 3)}) as Animal
	_room.add_child(stag)
	World.spawn(stag, Vector2i(12, 3))
	stag._pace = 4.4  # Its run a little over MID_EVERY_TICKS (its kind's spread rolls about it): on MID, a cell in 8.
	World.step()
	var gaps: Array[int] = []
	var last := stag.tile
	var at := World.tick
	var fled := true
	for i in 120:
		if i % 15 == 0 and stag.tile.x < 60:
			World.noise(stag.tile - Vector2i(2, 0), Senses.NOISE_FIGHT, &"fight", hunter)  # Kept on the run.
		World.step()
		fled = fled and stag.alert == Monster.Alert.FLEEING
		if stag.tile != last:
			if fled and World.distance(stag.tile, hunter.tile) > World.NEAR_TILES + 1 and World.distance(stag.tile, hunter.tile) <= World.VIEW_TILES:
				gaps.append(World.tick - at)
			last = stag.tile
			at = World.tick
			fled = stag.alert == Monster.Alert.FLEEING  # A flee run out, it stands a moment: not counted.
	_check(gaps.size() >= 4 and gaps.max() <= ceili(stag.move_ticks) + 1,
		"fleeing past %d cells: a cell every %s ticks, its pace %.2f (no MID gap of %d)" % [World.NEAR_TILES, gaps, stag.move_ticks, 2 * World.MID_EVERY_TICKS])
	World.despawn(stag)
	var walker := EntityFactory.build(SPECS["b"].merged({"name": "FarBrute", "tile": Vector2i(26, 3)})) as Monster
	_room.add_child(walker)
	World.spawn(walker, Vector2i(26, 3))
	walker.home = Vector2i(32, 3)  # Away home along its row, in view: it walks there.
	gaps.clear()
	last = walker.tile
	at = World.tick
	for i in 80:
		World.step()
		if walker.tile != last:
			gaps.append(World.tick - at)
			last = walker.tile
			at = World.tick
	var paced := gaps.slice(2)  # Its first steps wait for a think and its tier, as before.
	_check(paced.size() >= 2 and paced.max() < 2 * World.MID_EVERY_TICKS,
		"a brute walking home %d cells off, in view: a cell every %s ticks, its pace %.2f" % [World.distance(walker.tile, hunter.tile), gaps, walker.move_ticks])
	World.despawn(walker)
	World.despawn(hunter)


## A free body standing at the back of its cell (decision 699, enemy-ai's
## side): the cell beside it is out of reach by bodies, so a robber makes for
## a strike cell (World.strike_cells) and strikes from there, never waiting
## at the neighbour it could once strike from.
func _test_strike_cells() -> void:
	print("%s== a robber closes on a free body at the back of its cell from a strike cell ==" % char(10))
	Monster.idling = false
	var rows: Array[String] = ["############"]
	for y in 7:
		rows.append("#..........#")
	rows.append("############")
	var e := _build(rows)
	var player := EntityFactory.build(SPECS["P"].merged({"name": "BackOfCell"})) as Player
	_room.add_child(player)
	World.spawn(player, Vector2i(6, 4))
	player.free_pos = Vector2(6.58, 4.0)  # Its cell still (6, 4); (5, 4) is 1.58 off.
	var robber := EntityFactory.build(SPECS["x"].merged({"name": "Closer", "temperament": "bold", "props": Monster.bodies()["robber"]})) as Monster
	_room.add_child(robber)
	World.spawn(robber, Vector2i(2, 4))
	robber.sight_range = 12
	robber.senses.cone_cos = -1.0
	var struck_at := -1
	var from := World.NO_CELL
	var waited := 0
	var longest := 0
	for i in 80:
		var hp := player.hp
		player.free_pos = Vector2(6.58, 4.0)
		World.step()
		if player.hp < hp and struck_at < 0:
			struck_at = i
			from = robber.tile
		if World.are_adjacent(robber.tile, player.tile) and not World.in_reach(robber, player):
			waited += 1
			longest = maxi(longest, waited)
		else:
			waited = 0
	_check(struck_at >= 0 and struck_at < 60 and longest <= ceili(robber.move_ticks) + 1 and from != Vector2i(5, 4),
			"struck on tick %d from %s (%.2f off), at most %d ticks beside it out of reach (its pace %.1f)" % [struck_at, from, Vector2(from).distance_to(Vector2(6.58, 4.0)), longest, robber.move_ticks])
	World.despawn(robber)
	World.despawn(player)


## Routed in a dungeon (decision 702; Jeff on v0.1.187: "they dont know
## where to run to, they should run to the entrance"): robbers broken deep
## in the barrow run for its entrance, the link up to the wilds (never the
## hidden way down to the deep), and leave by it, gone, not dead; a skeleton
## (bound) and a robber outdoors flee as ever.
func _test_rout_way_out() -> void:
	print("%s== routed robbers run for the barrow's entrance and are gone by it ==" % char(10))
	Monster.idling = false
	var level := Level.load_level("barrow")
	var entrance := Vector2i(40, 1)
	_check(level["links"].any(func(l: Dictionary) -> bool: return l["tile"] == entrance and l["to_map"] == "wilds"),
			"the barrow's entrance, the link to the wilds, at %s" % entrance)
	var e := _build(["###"])
	World.load_terrain(level["terrain"])
	_check(World.ways_out() == [entrance] and World.is_link_cell(Vector2i(52, 16)),
			"its ways out %s: the entrance alone, the hidden way down not among them" % [World.ways_out()])
	var path: Array[Vector2i] = []
	for cell: Vector2i in level["terrain"]["floor"]:  # The deepest way in from the entrance.
		var way := World.find_path(entrance + Vector2i(0, 1), cell)
		if way.size() > path.size() and not World.is_link_cell(cell):
			path = way
	_check(path.size() >= 13, "a way in from the entrance %d cells deep" % path.size())
	var player := EntityFactory.build(SPECS["P"].merged({"name": "Router"})) as GridEntity
	_room.add_child(player)
	World.spawn(player, path[11])
	var gone: Dictionary = {}
	var left := func(entity: GridEntity) -> void:
		gone[String(entity.name)] = entity.tile
	World.entity_despawned.connect(left)
	var robbers: Array[Monster] = []
	for i in 3:
		var robber := EntityFactory.build(SPECS["x"].merged({"name": "Fleer%d" % i, "props": Monster.bodies()["robber"]})) as Monster
		_room.add_child(robber)
		World.spawn(robber, path[9 - i])
		robbers.append(robber)
	var bones := EntityFactory.build(SPECS["k"].merged({"name": "Bones", "props": Monster.bodies()["skeleton"]})) as Monster
	_room.add_child(bones)
	World.spawn(bones, path[12])
	for robber in robbers:
		robber._flee(player.tile)
	bones._flee(player.tile)
	var ways := robbers.map(func(r: Monster) -> Vector2i: return r._way_out)
	var ticks := 0
	for i in 400:
		World.step()
		ticks += 1
		if gone.size() >= robbers.size():
			break
	_check(ways == [entrance, entrance, entrance] and gone.size() == 3 			and gone.values().all(func(at: Vector2i) -> bool: return World.distance(at, entrance) <= 1),
			"three robbers routed 8 to 10 cells in, the player deeper: making for %s, gone beside it by tick %d (%s)" % [ways, ticks, gone])
	_check(bones._way_out == Monster.NO_TILE and bones.spawned and not gone.has("Bones"),
			"a skeleton routed beside them (bound to its barrow): no way out, still there at %s" % bones.tile)
	World.entity_despawned.disconnect(left)
	World.outdoor = true
	var outside := EntityFactory.build(SPECS["x"].merged({"name": "Outside", "props": Monster.bodies()["robber"]})) as Monster
	_room.add_child(outside)
	World.spawn(outside, path[3])
	outside._flee(player.tile)
	_check(outside._way_out == Monster.NO_TILE and outside.alert == Monster.Alert.FLEEING,
			"a robber routed under the sky: the plain flee, no way out sought")
	World.outdoor = false
	World.despawn(outside)
	World.despawn(bones)
	World.despawn(player)


func _test_named() -> void:
	print("\n== a named one (716): its own fixed strength, dies, rises days later with its weapon, never grows ==")
	NamedEnemy.define_for_test("test_named", {"name": "Gorm", "kind": "robber", "rise_days": 1.0,
		"strength": {"hp": 1.5, "damage": 2.0, "speed": 1.0}})
	var events: Array = []
	var on_event := func(id: String, kind: String, player_id: String) -> void: events.append([id, kind, player_id])
	World.named_event.connect(on_event)
	var e := _build(["#######", "#.Px..#", "#######"], {"x": {"named": "test_named"}})
	var gorm: Monster = e["x"][0]
	var player: Player = e["P"][0]
	player.player_id = "p1"
	var spec := gorm.spawn_spec.duplicate(true)
	var base_hp := int(Level.MONSTER_TYPES["robber"]["max_hp"])
	_check(gorm.named_id == "test_named" and str(gorm.spawn_spec.get("label")) == "Gorm", "its name over it (%s)" % gorm.spawn_spec.get("label"))
	_check(gorm.max_hp == roundi(base_hp * 1.5) and gorm.hp == gorm.max_hp, "its hp its kind's times its strength (%d)" % gorm.max_hp)
	var damage := gorm.attack_damage
	var slots := Items.tidy([], Items.CARRIED)  # A robber's hands, as Level arms it.
	slots[Items.RIGHT_HAND] = "dagger"
	gorm.slots = Items.tidy([], Items.CARRIED)
	World.set_slots(gorm, slots)
	spec["props"]["slots"] = Items.tidy([], Items.CARRIED)
	var dagger := World.slot_uid(gorm, Items.RIGHT_HAND)
	_check(dagger != 0 and World.holder_key(gorm) == "named:test_named" and World._names_things(gorm),
			"its dagger held by it by name, which can name it (365)")
	World.damage(gorm, 1, player)
	World.damage(gorm, 1, player)
	_check(events.count(["test_named", "fought", "p1"]) == 1, "fought told once a life (%s)" % [events])
	World.damage(gorm, 999, player)
	var record := World.named_record("test_named")
	_check(not gorm.spawned and not bool(record["alive"]) and events.has(["test_named", "killed_by", "p1"]), "it dies, killed_by told")
	_check(World.items.at_of(dagger) == NamedEnemy.KEPT % "test_named" and int(record["weapon_uid"]) == dagger,
			"its dagger kept for it, not dropped (%s)" % World.items.at_of(dagger))
	_check(not World.named_may_rise(spec), "it does not rise at once")
	World.steps = int(record["returns_at"])
	_check(World.named_may_rise(spec), "it may rise when its day is past")
	var strength: Dictionary = record["strength"].duplicate()
	for life in 10:
		var back := EntityFactory.build(spec.duplicate(true)) as Monster
		_room.add_child(back)
		World.spawn(back, Vector2i(3, 1))
		if life == 0 or life == 9:
			_check(back.max_hp == roundi(base_hp * 1.5) and back.attack_damage == damage and World.slot_uid(back, Items.RIGHT_HAND) == dagger,
					"life %d: the same numbers and its own dagger in hand" % (life + 2))
		World.damage(back, 999, player)
		World.steps = int(World.named_record("test_named")["returns_at"])
	record = World.named_record("test_named")
	_check(record["strength"] == strength and int(record["lives"]) == 11 and events.count(["test_named", "rose", ""]) == 10,
			"ten risings: strength untouched, lives %d" % int(record["lives"]))
	var faked := record.duplicate(true)
	faked["strength"] = {"hp": 9.0}
	World.set_named_record("test_named", faked)
	_check(World.named_record("test_named")["strength"] == strength, "npc's writes never change its strength")
	World.named_event.disconnect(on_event)
	NamedEnemy.reset_for_test()
	World.steps = 0

## One of the band (714) at [param at]: its kind's spawn, armed as a
## level's (Level.arm), named [param id].
func _band_one(id: String, kind: String, at: Vector2i) -> Monster:
	var spec := Level._spec_for("monster_" + kind, Level.MONSTER_TYPES)
	spec["name"] = "Band%s%d" % [id.capitalize(), World.tick]
	spec["tile"] = at
	spec["named"] = id
	Level.arm(spec)
	var one := EntityFactory.build(spec) as Monster
	_room.add_child(one)
	World.spawn(one, at)
	return one


func _test_band() -> void:
	print("\n== the barrow's band (714): Brand the Ox wields the Tomb Sledge, due again 5 minutes after it is won (714 amended (2)); a maul (the hammer) till then; a plain robber cannot lift it ==")
	_build(["###########", "#.........#", "#.........#", "###########"], {}, {}, "mt_band")
	var host := Main.new()
	var trophy_was := NamedEnemy.trophy_s
	World.trophy_due = host.trophy_due
	World.trophy_taken = host.trophy_taken
	var player := EntityFactory.build(SPECS["P"].merged({"name": "Player1"})) as Player
	player.player_id = "p1"
	_room.add_child(player)
	World.spawn(player, Vector2i(1, 1))
	var brand := _band_one("brand", "robber_brute", Vector2i(5, 1))
	var sledge := World.slot_uid(brand, Items.RIGHT_HAND)
	_check(str(brand.spawn_spec.get("label")) == "Brand the Ox" and brand.tactic == Monster.Tactic.HEAVY and World.wielded(brand) == "tomb_sledge"
			and World.holder_key(brand) == "named:brand", "Brand the Ox, a heavy, the Tomb Sledge in his hands (%s)" % World.wielded(brand))
	var crake := _band_one("crake", "robber", Vector2i(8, 2))
	_check(str(crake.spawn_spec.get("label")) == "Crake" and World.wielded(crake) == "dagger", "Crake, a plain robber with his dagger")
	World.damage(brand, 999, player)
	var cell := World.NO_CELL
	for at: Vector2i in World.zone.ground:
		if sledge in World.ground_uids(at):
			cell = at
	_check(not brand.spawned and cell != World.NO_CELL, "struck down by a player, the Sledge falls where he fell, not kept (%s)" % World.items.at_of(sledge))
	_check(int(World.named_record("brand").get("trophy_won", -1)) == World.steps and not host.trophy_due("p1", "brand", "tomb_sledge")
			and int(World.named_record("brand")["returns_at"]) - World.steps == roundi(300 * World.TICK_RATE),
			"won now: not due again yet, and he rises 5 minutes on (rise_s 300)")
	for kind: String in ["robber", "robber_brute"]:
		var spec := Level._spec_for("monster_" + kind, Level.MONSTER_TYPES)  # Unarmed: both hands free.
		spec["name"] = "Bare" + kind.capitalize().replace(" ", "")
		spec["tile"] = cell + Vector2i(0, 1) if World.is_free(cell + Vector2i(0, 1)) else cell + Vector2i(0, -1)
		var one := EntityFactory.build(spec) as Monster
		_room.add_child(one)
		World.spawn(one, spec["tile"])
		_check(World.weapon_near(one) == (World.NO_CELL if kind == "robber" else cell),
				"beside the Sledge, hands free: a %s %s lift it (lifts %.0f kg, it %.0f)" % [kind, "cannot" if kind == "robber" else "can", one.lifts, Items.weight_of("tomb_sledge")])
		World.despawn(one)
	NamedEnemy.trophy_s = 900.0  # Three of his risings, to see him rise twice without it.
	var record := World.named_record("brand")
	World.steps = int(record["returns_at"])
	brand = _band_one("brand", "robber_brute", Vector2i(5, 1))
	_check(World.wielded(brand) == "hammer", "risen before it is due: his maul (the hammer), not a second Sledge (%s)" % World.wielded(brand))
	var maul := World.slot_uid(brand, Items.RIGHT_HAND)
	World.damage(brand, 999, player)
	_check(World.items.at_of(maul) == NamedEnemy.KEPT % "brand", "his maul kept for him, as any named one's (716)")
	World.steps = int(World.named_record("brand")["returns_at"])
	brand = _band_one("brand", "robber_brute", Vector2i(5, 1))
	_check(World.slot_uid(brand, Items.RIGHT_HAND) == maul, "and back in his hands when he rises")
	World.damage(brand, 999, player)
	World.steps = int(World.named_record("brand")["returns_at"])
	brand = _band_one("brand", "robber_brute", Vector2i(5, 1))
	var second := World.slot_uid(brand, Items.RIGHT_HAND)
	_check(World.wielded(brand) == "tomb_sledge" and second != sledge, "trophy_s past since it was won: a Sledge is his again, to be won once more")
	World.damage(brand, 999, null)
	_check(World.items.at_of(second) == NamedEnemy.KEPT % "brand", "felled by no player: the Sledge kept for him, not dropped")
	World.steps = int(World.named_record("brand")["returns_at"])
	brand = _band_one("brand", "robber_brute", Vector2i(5, 1))
	_check(World.slot_uid(brand, Items.RIGHT_HAND) == second, "and he rises with that same Sledge")
	World.damage(brand, 999, player)
	NamedEnemy.trophy_s = trophy_was
	World.steps = int(World.named_record("brand")["returns_at"])
	brand = _band_one("brand", "robber_brute", Vector2i(5, 1))
	_check(World.wielded(brand) == "tomb_sledge" and World.slot_uid(brand, Items.RIGHT_HAND) != second,
			"as set (300 s, his rise's own): won, he is back in 5 minutes with a new Sledge")
	World.trophy_due = Callable()
	World.trophy_taken = Callable()
	host.free()
	World.steps = 0


func _test_din() -> void:
	print("
== wildlife keeps out of the din: a town's, a fire's, a fight's; a doe walks out, a wolf heeds a player's none (740) ==")
	Monster.idling = true
	var rows: Array[String] = ["#".repeat(32)]
	for y in 11:
		rows.append("#" + ".".repeat(30) + "#")
	rows.append("#".repeat(32))
	var town_at := Vector2i(5, 6)
	var cells: Array[String] = []
	for y in 2 * rows.size() - 1:
		cells.append(".".repeat(2 * 32 - 1))
	Level.register("mt_din", Level.image_from_rows(cells), null, {"outdoor": true, "places": {
		"square": {"at": [town_at.x, town_at.y], "kind": "stockpile", "holder": "town", "radius": 2, "worth": 0}}})
	_build(rows, {}, {}, "mt_din")
	var was_holdings := World.holdings
	var was_towns := World.towns
	var names: Array[String] = ["mt_din"]
	World.holdings = Holdings.new(WorldMap.build(names), Factions.read(), {})
	World.towns = null
	World._din_tick = -1000000
	var town := World.din_at(town_at + Vector2i(3, 0))
	_check(town.get("kind") == "town" and is_equal_approx(float(town["radius"]), float(World.din_rules["town_base"]))
			and World.din_at(Vector2i(25, 6)).is_empty(), "a town's din: its base radius with nobody living there (%s)" % [town])
	var doe := EntityFactory.build(SPECS["d"].merged({"name": "TownDoe", "props": Level.MONSTER_TYPES["deer"], "tile": town_at + Vector2i(3, 1)})) as Animal
	_room.add_child(doe)
	World.spawn(doe, doe.spawn_spec["tile"])
	doe.sight_range = 0
	var ran := false
	for i in 400:
		World.step()
		ran = ran or doe.alert == Monster.Alert.FLEEING
	var off := Vector2(doe.tile - town_at).length()
	_check(off > float(World.din_rules["town_base"]) and not ran,
			"a doe grazing in it walks out and grazes past its edge, never running (%.1f off)" % off)
	var hunter := EntityFactory.build(SPECS["P"].merged({"name": "Hunter"})) as Player
	_room.add_child(hunter)
	World.spawn(hunter, Vector2i(25, 3))
	World._din_tick = -1000000
	_check(World.din_at(Vector2i(26, 3)).get("kind") == "player" and World.din_at(Vector2i(26, 3), true).is_empty()
			and World.din_at(town_at + Vector2i(3, 0), true).get("kind") == "town",
			"a player's din keeps prey off; a wolf heeds it not, but heeds a town's")
	World.noise(Vector2i(20, 9), 10, &"fight")
	World._din_tick = -1000000
	_check(World.din_at(Vector2i(22, 9)).get("kind") == "fight", "a fight's din where it was heard")
	World.tick += roundi(float(World.din_rules["fight_seconds"]) * World.TICK_RATE) + 1
	World._din_tick = -1000000
	_check(World.din_at(Vector2i(22, 9)).get("kind") != "fight", "gone once fight_seconds have passed")
	World._fire[Vector2i(28, 10)] = true
	World._din_tick = -1000000
	_check(World.din_at(Vector2i(26, 10)).get("kind") == "fire" and World.din_at(Vector2i(26, 10), true).get("kind") == "fire",
			"a fire's din, heeded by prey and wolf alike")
	World._fire.erase(Vector2i(28, 10))
	World.holdings = was_holdings
	World.towns = was_towns
	World._din_tick = -1000000


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

## A zone fallen asleep (397 amended (3)): its herd bodies back into their
## counts at once, through Main's zone_slept hook (_retire_sleeping), so a
## sleeping zone holds counts only; a wounded one back whole; a level's own
## animal (no group) stays.
func _test_herd_sleeps() -> void:
	print("%s== a zone asleep: its herd bodies back into their counts (397 amended (3)) ==" % char(10))
	var e := _build(["##############", "#.............", "#.............", "#.............", "##############"])
	var floor := {}
	for cell in World.floor_cells():
		floor[cell] = true
	var herds := Herds.new({}, {"meadow": {"floor": floor, "outdoor": true}}, Production.read_rules().get("herds", {}), func() -> int: return 0)
	World.herds = herds
	World.keepers.append(herds)
	herds.here = func() -> String: return "meadow"
	herds.spawn = func(spec: Dictionary) -> GridEntity:
		var body := EntityFactory.build(spec) as GridEntity
		_room.add_child(body)
		if not World.spawn(body, spec["tile"]):
			body.free()
			return null
		return body
	herds.free_near = func(cell: Vector2i, _reach: int) -> Vector2i:
		for x in range(1, 13):
			for y in range(1, 4):
				if World.is_free(Vector2i(x, y)):
					return Vector2i(x, y)
		return cell
	var deer := herds._add_group("meadow", "deer", Vector2i(7, 2), 4.0)
	herds.recall_near(Vector2i(7, 2), 20)
	var made := World.monsters().filter(func(m: GridEntity) -> bool: return m is Animal and str((m as Animal).spawn_spec.get("group", "")) == deer["id"])
	_check(made.size() == 4 and int(deer["out"]) == 4 and float(deer["count"]) == 0.0, "4 bodies out, none kept (out %d)" % deer["out"])
	World.damage(made[0], 2, null)  # Wounded, alive.
	var plain := EntityFactory.build(Level._spec_for("monster_deer", Level.MONSTER_TYPES).merged({"name": "LevelDoe", "kind": "deer"})) as Animal
	_room.add_child(plain)
	World.spawn(plain, Vector2i(12, 3))
	var host := Main.new()
	host._retire_sleeping(World.zone)
	var left := World.monsters().filter(func(m: GridEntity) -> bool: return m is Animal and m.spawned and (m as Animal).spawn_spec.has("group"))
	_check(left.is_empty() and int(deer["out"]) == 0 and is_equal_approx(float(deer["count"]), 4.0),
		"asleep: no body left, out 0, kept 4 (the wounded one whole) (out %d, kept %.1f)" % [deer["out"], deer["count"]])
	_check(plain.spawned, "a level's own deer (no group) stays")
	host.free()
	World.despawn(plain)
	World.keepers.erase(herds)
	World.herds = null


func _test_herd_hunt() -> void:
	print("\n== a hunt (W4): a herd's bodies come out of the hunter's sight; a kill leaves the herd for good; a deer run off the east edge goes to the next area's herd ==")
	Monster.idling = true
	const W := 34
	var rows: Array[String] = ["#".repeat(W)]
	for y in 5:
		rows.append("#" + ".".repeat(W - 1))  # Open to the east: the map's edge.
	rows.append("#".repeat(W))
	var e := _build(rows)
	_outdoors("clear")
	DayNight.set_hour(12.0)
	var hunter := EntityFactory.build(SPECS["P"].merged({"name": "Hunter"})) as GridEntity
	_room.add_child(hunter)
	World.spawn(hunter, Vector2i(14, 3))
	var floor := {}
	for cell in World.floor_cells():
		floor[cell] = true
	var areas := {"meadow": {"floor": floor, "outdoor": true}, "fields": {"floor": floor, "outdoor": true}}
	var herds := Herds.new({}, areas, Production.read_rules().get("herds", {}), func() -> int: return 0)
	World.herds = herds
	herds.here = func() -> String: return "meadow"
	herds.spawn = func(spec: Dictionary) -> GridEntity:
		var body := EntityFactory.build(spec) as GridEntity
		_room.add_child(body)
		if not World.spawn(body, spec["tile"]):
			body.free()
			return null
		return body
	herds.free_near = func(cell: Vector2i, reach: int) -> Vector2i:
		var draw := RandomNumberGenerator.new()
		draw.seed = hash(cell)
		var near: Array[Vector2i] = [hunter.tile]
		var unseen := Animal.unseen_cell(cell, reach, near, draw)
		return unseen if unseen != World.NO_CELL else cell
	var deer := herds._add_group("meadow", "deer", Vector2i(26, 3), 5.0)
	herds.recall_near(hunter.tile, W)
	var bodies: Array[Animal] = []
	for monster in World.monsters():
		if monster is Animal and str((monster as Animal).spawn_spec.get("group", "")) == deer["id"]:
			bodies.append(monster)
	_check(bodies.size() == 5 and int(deer["out"]) == 5, "the herd near the hunter made bodies (%d, out %d)" % [bodies.size(), deer["out"]])
	_check(bodies.all(func(body: Animal) -> bool: return World.distance(body.tile, hunter.tile) > Animal.UNSEEN_TILES),
			"each out of the hunter's sight (more than %d off)" % Animal.UNSEEN_TILES)
	var fell := bodies[0].tile
	World.damage(bodies[0], 999, hunter)
	_check(int(deer["out"]) == 4 and is_equal_approx(herds.total("meadow", "deer"), 4.0), "one killed: gone from the herd for good (out %d)" % deer["out"])
	# Its drops still spill, on open ground where it fell, for the hunter to take (Jeff's v0.1.150 playtest).
	var laid: Array[String] = []
	var open := true
	for cell: Vector2i in World.zone.ground:
		if World.distance(cell, fell) <= World.GROUND_SPILL:
			laid.append_array(World.ground_at(cell))
			open = open and World.is_free(cell)
	_check(laid.count("meat") >= 3 and laid.count("meat") <= 4 and laid.count("hide") == 1 and open,
			"its meat and hide lie on open ground where it fell (%s)" % [laid])
	# Hunted to the edge: the rest bolt east, and off it.
	var map := WorldMap.new()
	map.areas = {"meadow": {"size": Vector2i(W, rows.size()), "neighbours": {"east": "fields"}},
		"fields": {"size": Vector2i(W, rows.size()), "neighbours": {}}}
	var crossed: Array[Dictionary] = []
	var off := func(entity: GridEntity, direction: Vector2i) -> void:
		if entity is Animal:
			var cross := Animal.crossing_off(entity as Animal, direction, map, "meadow")
			if not cross.is_empty():
				crossed.append(cross)
				herds.moved(str((entity as Animal).spawn_spec["group"]), cross["to"], cross["at"])
				World.despawn(entity)  # As Main's _animal_crossed: kept, not dead.
	World.walked_off.connect(off)
	World.despawn(hunter)
	World.spawn(hunter, Vector2i(22, 3))
	for i in 120:
		World.step()
		if crossed.size() >= 2:
			break
	World.walked_off.disconnect(off)
	_check(not crossed.is_empty() and crossed[0]["to"] == "fields" and crossed[0]["side"] == "east" and (crossed[0]["at"] as Vector2i).x == 0,
			"a deer runs off the east edge into fields, at its west edge (%s)" % [crossed.slice(0, 1)])
	var there := herds.groups_in("fields", "deer")
	_check(not there.is_empty() and is_equal_approx(float(there[0]["count"]), float(crossed.size())) and int(there[0]["out"]) == 0
			and int(deer["out"]) == 4 - crossed.size(), "its unit is kept in the fields' deer now (%d moved)" % crossed.size())
	# One of no group (a level's own) at the edge stays.
	var plain := EntityFactory.build(Level._spec_for("monster_deer", Level.MONSTER_TYPES).merged({"name": "LevelDoe", "kind": "deer"})) as Animal
	_room.add_child(plain)
	World.spawn(plain, Vector2i(W - 1, 1))
	plain.alert = Monster.Alert.FLEEING
	_check(Animal.crossing_off(plain, Vector2i(1, 0), map, "meadow").is_empty(), "a level's own deer (no group) never leaves")
	World.herds = null
	DayNight.reset()
	_indoors()


func _test_wolf_den() -> void:
	print("\n== a wolf keeps to its den by day and ranges by night ==")
	Monster.idling = true
	var e := _build(["##########", "#...w....#", "##########"])
	var wolf: Animal = e["w"][0]
	_outdoors("clear")
	DayNight.set_hour(12.0)
	for i in Animal.PREY_LOOK_TICKS + 2:
		World.step()
	_check(wolf.wander_radius == Animal.DEN_RADIUS, "by day it wanders %d from home" % wolf.wander_radius)
	DayNight.set_hour(0.0)
	for i in Animal.PREY_LOOK_TICKS + 2:
		World.step()
	_check(wolf.wander_radius == Monster.WANDER_RADIUS * 2, "by night %d" % wolf.wander_radius)
	DayNight.reset()
	_indoors()


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
	var before := World.zone.ground.duplicate()
	World.damage(imp, imp.hp)
	var fell: Array[String] = []
	for cell: Vector2i in World.zone.ground:
		for each in World.ground_uids(cell):
			if not each in before.get(cell, PackedInt32Array()):
				fell.append(World.items.id_of(each))
	_check(not imp.spawned and fell.is_empty(),
			"an imp's row drops no meat or hide, and its gold is a count, not a thing (601 amended; %s)" % [fell])


func _test_kobold_dagger_and_pick() -> void:
	print("\n== a kobold fights with a dagger, armed in a raid too; it drops a pick 1 time in 5 (decision 481) ==")
	var spec := Level._spec_for("monster_sneak", Level.MONSTER_TYPES)
	spec["tile"] = Vector2i(3, 3)
	Level.arm(spec)
	var slots: Array = spec.get("props", {}).get("slots", [])
	_check(slots.size() == Items.CARRIED and slots[Items.RIGHT_HAND] == "dagger" and slots[Items.LEFT_HAND] == "",
			"a sneak spawned outside a level (a raider) holds its kind's dagger (%s)" % [slots])
	_check(Items.verb_of("dagger").get("kind") == "backstab", "a backstabber's weapon, for a flanker")
	# Its hands follow its slots, and a client's slots follow its hands (decision 483).
	var server := Monster.new()
	var held := Items.tidy(["meat"], Items.CARRIED)
	held[Items.RIGHT_HAND] = "dagger"
	server.slots = held
	var bare := Monster.new()
	bare.slots = PackedStringArray(["meat"])
	var client := Monster.new()
	client.hands = PackedStringArray(["", "bow"])
	_check(server.hands == PackedStringArray(["dagger", ""]) and bare.hands.is_empty(),
			"a monster's hands follow its slots, right then left; none without hands (%s)" % [server.hands])
	_check(client.slots.size() == Items.CARRIED and client.slots[Items.LEFT_HAND] == "bow" and client.slots[Items.RIGHT_HAND] == ""
			and client.slots[0] == "" and World.drawn_with(client) == "bow",
			"on a client its hands are written into its slots, the pack empty, so a drawn bow is found (%s)" % [client.slots])
	for each: Monster in [server, bare, client]:
		each.free()
	var roll := RandomNumberGenerator.new()
	roll.seed = 471
	var picks := 0
	for i in 1000:
		picks += Monster.dropped({"item": "pick", "count": [1, 1], "chance": 0.2}, roll)
	var always := 0
	var never := 0
	for i in 100:
		always += Monster.dropped({"item": "meat", "count": [1, 1]}, roll)
		never += Monster.dropped({"item": "meat", "count": [1, 1], "chance": 0.0}, roll)
	_check(picks >= 150 and picks <= 250 and always == 100 and never == 0,
			"a chance of 0.2 drops about 1 in 5 (%d of 1000), no chance always, 0 never" % picks)
	var drops: Array = Monster.kinds()["sneak"]["drops"]
	_check(drops.size() == 1 and drops[0]["item"] == "pick" and is_equal_approx(float(drops[0]["chance"]), 0.2),
			"the sneak's row: a pick, 1 in 5 (%s)" % [drops])


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


func _test_sides_on_sight() -> void:
	print("
== sides (decision 545): the barrow's dead and robbers fight each other and the residents on sight; others let them be ==")
	Monster.idling = false
	var was_holdings := World.holdings
	World.holdings = null
	var folder: String = preload("res://tests/test_ports.gd").scratch("monster_test/")
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder + "factions.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"dead": {"monsters": ["imp"], "hostile_to": ["robbers", "town"], "on_sight": ["robbers", "town"], "holds": false},
		"robbers": {"monsters": ["sneak"], "hostile_to": ["dead", "town"], "on_sight": ["dead", "town"], "holds": false},
		"town": {"monsters": []}}))
	file.close()
	var sides := Factions.read(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Monster._read_factions = sides
	var e := _build(["#############", "#...........#", "#.i.......s.#", "#...........#", "#############"])
	var dead: Monster = e["i"][0]
	var robber: Monster = e["s"][0]
	_check(dead.foes == _strings(["robbers", "town"]) and robber.foes == _strings(["dead", "town"]), "each kind's foes, from its faction")
	_bold(dead)
	_bold(robber)
	World.step()
	_check(dead.target == robber and robber.target == dead, "they go for each other (%s, %s)" % [dead.target, robber.target])
	var hurt := false
	for i in 200:
		World.step()
		if robber.hp < robber.max_hp or dead.hp < dead.max_hp:
			hurt = true
			break
	_check(hurt, "and come to blows")
	e = _build(["#############", "#...........#", "#.i.........#", "#...........#", "#############"])
	dead = e["i"][0]
	_bold(dead)
	var pip := EntityFactory.build({"script": "res://sim/resident.gd", "shape": "capsule", "name": "Pip"}) as Resident
	pip.worker_id = "w-pip"
	_room.add_child(pip)
	World.spawn(pip, Vector2i(7, 2))
	World.step()
	_check(dead.target == pip, "the dead go for a resident walking the barrow (%s)" % [dead.target])
	Monster._read_factions = null
	e = _build(["#############", "#...........#", "#.i.......s.#", "#...........#", "#############"])
	_bold(e["i"][0])
	_bold(e["s"][0])
	World.step()
	World.step()
	_check(e["i"][0].foes.is_empty() and e["i"][0].target == null and e["s"][0].target == null,
		"an imp and a sneak (the Blood Rot's, levels/factions.json) let each other be")
	World.holdings = was_holdings
	Monster.idling = true


func _test_homeward() -> void:
	print("
== the barrow's dead rest standing on the cell they were laid on and walk back to it; they fight only who is in the way, or strikes them (decision 547; 631 amended) ==")
	Monster.idling = true
	var rows: Array[String] = ["###############", "#.............#", "#.k...........#", "#.............#", "###############"]
	Level.register("mt_barrow", Level.image_from_rows(rows), null, {"graves": [[3, 3, 2], [12, 1, 0], [12, 3, 1]]})  # Listed, no longer read.
	var e := _build(rows, {}, {}, "mt_barrow")
	var walker: Monster = e["k"][0]
	var laid_on := walker.tile
	_check(walker.idle == Monster.Idle.HOMEWARD and walker.fearless and not walker._should_flee(), "a skeleton walks home and never flees")
	walker.hp = 1
	_check(not walker._should_flee(), "not even at 1 hp")
	walker.hp = walker.max_hp
	for i in 400:
		World.step()
		if walker.laid:
			break
	_check(walker.laid and walker.grave == laid_on and walker.tile == laid_on, "its grave is the cell it was laid on, not a listed one, and it rests there at once (%s)" % [walker.grave])
	_check(not World.is_down(walker) and walker.down_until <= World.tick and walker.facing == walker.home_facing, "resting, it stands: never knocked down, turned its home's way")
	var props: Dictionary = walker.spawn_spec["props"]
	_check(props.get("laid") == true and not props.get("grave") is Vector2i, "a save keeps it resting, and no grave cell in its props (555's grave goods keep the key) (%s)" % [props])
	World.damage(walker, 1, null)
	for i in 5:
		World.step()
	_check(walker.laid and walker.tile == laid_on and not World.is_down(walker), "struck, it stands still")
	walker.rise()
	_check(not walker.laid and walker.idle == Monster.Idle.GUARD and walker.home == laid_on and walker.down_until <= World.tick, "risen, it guards its cell, with no getting up")
	# Led away and left (631 amended; the coordinator): back to its laid cell, standing.
	walker.idle = Monster.Idle.HOMEWARD
	_move_to(walker, Vector2i(12, 3))
	for i in 400:
		World.step()
		if walker.laid:
			break
	for i in 10:
		World.step()
	_check(walker.laid and walker.tile == laid_on and not World.is_down(walker) and walker.facing == walker.home_facing,
		"led away and left, it walks back to the cell it was laid on and stands there, turned its home's way (%s)" % [walker.tile])
	# A foe in sight (580 amended): it sits up as one passes; stilled by the
	# draugr's rest, never.
	var passer := EntityFactory.build(SPECS["P"].merged({"name": "Passer"})) as Player
	passer.player_id = "pp"
	_room.add_child(passer)
	World.spawn(passer, Vector2i(13, 1))
	walker.lay_down()
	walker.sight_range = 5
	walker.senses.dark_sight = true
	World.step()
	_check(walker.laid, "one 11 off, past its sight: it rests on")
	_move_to(passer, Vector2i(5, 2))
	World.dead_rest["mt_barrow"] = {"until": World.steps + 100, "side": walker._factions().of_kind(World.kind_of(walker))}
	World.step()
	_check(walker.laid, "stilled by the draugr's rest, it rests on with one near")
	World.dead_rest.clear()
	World.step()  # His rest over: it gets up of itself.
	walker.lay_down()
	World.step()
	var went := false
	for i in 10:
		World.step()
		went = went or walker.target == passer
	_check(not walker.laid and walker.idle == Monster.Idle.GUARD and went,
		"resting at its grave, one within its sight: it wakes and goes for them (target %s)" % [walker.target])
	passer.queue_free()
	World.despawn(passer)

	rows = ["###########", "#k.....P..#", "###########"]
	Level.register("mt_barrow", Level.image_from_rows(rows), null, {})
	e = _build(rows, {}, {}, "mt_barrow")
	walker = e["k"][0]
	walker.home = Vector2i(9, 1)  # Its laid cell down the way: led off it.
	var player: GridEntity = e["P"][0]
	walker.sight_range = 7
	walker.senses.cone_cos = -1.0
	var met := false
	for i in 200:
		World.step()
		if walker.target == player:
			met = true
			break
	_check(met and World.distance(walker.tile, player.tile) == 1, "one standing in its way it fights (%s)" % [walker.tile])

	rows = ["#############", "#.....P.....#", "#k..........#", "#...........#", "#############"]
	Level.register("mt_barrow", Level.image_from_rows(rows), null, {})
	e = _build(rows, {}, {}, "mt_barrow")
	walker = e["k"][0]
	walker.home = Vector2i(11, 2)
	player = e["P"][0]
	walker.sight_range = 7
	walker.senses.cone_cos = -1.0
	var bothered := false
	for i in 300:
		World.step()
		bothered = bothered or walker.target != null
		if walker.laid:
			break
	_check(walker.laid and not bothered, "one standing beside its way it passes by, and rests at home (laid %s, bothered %s, at %s, grave %s)" % [walker.laid, bothered, walker.tile, walker.grave])
	walker.rise()
	walker.idle = Monster.Idle.HOMEWARD
	walker.grave = Vector2i(1, 2)
	World.damage(walker, 1, player)
	World.step()
	_check(walker.target == player, "struck, it fights back (%s)" % [walker.target])

	Monster._read_factions = null
	e = _build(["########", "#k.k.xP#", "########"])
	_check(not e["k"][0]._may_fight(e["k"][1]) and e["k"][0]._may_fight(e["x"][0]) and e["k"][0]._may_fight(e["P"][0]),
		"a fellow of its side in its way it waits behind; a robber it fights, as a player")
	rows = ["###############", "#k............#", "###############"]
	Level.register("mt_barrow", Level.image_from_rows(rows), null, {})
	e = _build(rows, {}, {}, "mt_barrow")
	walker = e["k"][0]
	walker.home = Vector2i(13, 1)
	walker._world_tick(60.0)
	_check(walker.laid and walker.tile == Vector2i(13, 1) and not World.is_down(walker), "far from everyone, it walks home all the same and rests standing (%s)" % [walker.tile])
	Level.unregister("mt_barrow")


func _test_room_guard() -> void:
	print("
== the altar's guards see and fight only who is in their room, and never leave it (decision 547) ==")
	Monster.idling = true
	var rows: Array[String] = ["############", "#..........#", "#.g........#", "#..........#", "############"]
	Level.register("mt_altar", Level.image_from_rows(rows), null, {"regenerate": {"anchors": [{"rect": [1, 1, 4, 3], "name": "altar"}]}})
	var e := _build(rows, {}, {}, "mt_altar")
	var guard: Monster = e["g"][0]
	var player := EntityFactory.build(SPECS["P"].merged({"name": "Player1"})) as GridEntity
	_room.add_child(player)
	World.spawn(player, Vector2i(7, 2))
	_bold(guard)
	_check(guard.keeps_room and guard._room == Rect2i(1, 1, 4, 3), "its room is the anchor round its post (%s)" % [guard._room])
	World.step()
	World.step()
	_check(guard.target == null, "one outside the room it lets be")
	_move_to(player, Vector2i(4, 2))
	World.step()
	_check(guard.target == player, "one inside it, it goes for")
	_move_to(player, Vector2i(9, 2))
	var left := false
	for i in 60:
		World.step()
		left = left or not guard._room.has_point(guard.tile)
	_check(guard.target == null and not left, "gone out of the room, it is let go, and the guard never left the room")
	Level.unregister("mt_altar")
	Monster.idling = true


## Jeff: "barrow guards aren't aggro enough sometimes just stand and take
## hits". A guard struck answers the one who struck it within a few ticks:
## from behind it (out of its cone), and from just outside the room it keeps
## (a doorway, a spear's reach).
func _test_struck_answers() -> void:
	print("%s== a struck guard answers who struck it: from behind, from outside its room ==" % char(10))
	Monster.idling = true
	var rows: Array[String] = ["############", "#..........#", "#...g......#", "#..........#", "############"]
	Level.register("mt_struck", Level.image_from_rows(rows), null, {"regenerate": {"anchors": [{"rect": [1, 1, 4, 3], "name": "altar"}]}})
	for case: Array in [["behind it, inside its room", Vector2i(3, 2), Vector2i(1, 0)], ["just outside its room", Vector2i(5, 2), Vector2i(-1, 0)],
			["outside its room, a reach of two", Vector2i(6, 2), Vector2i(-1, 0)]]:
		var e := _build(rows, {"g": {"facing": case[2]}}, {}, "mt_struck")
		var guard: Monster = e["g"][0]
		var player := EntityFactory.build(SPECS["P"].merged({"name": "Player1"})) as GridEntity
		_room.add_child(player)
		World.spawn(player, case[1])
		_bold(guard)
		World.face(guard, case[2])
		World.step()
		var answered := -1
		var landed := -1
		for i in 40:
			if i % 8 == 0:
				World.damage(guard, 1, player)
			World.step()
			if answered < 0 and guard.target == player:
				answered = i
			if landed < 0 and _damage_log.any(func(hit: Dictionary) -> bool: return hit["source"] == guard):
				landed = i
		_check(answered >= 0 and answered <= 5 and landed >= 0 and landed <= 30,
				"%s: it turns on them (tick %d) and strikes (tick %d)" % [case[0], answered, landed])
		_move_to(player, Vector2i(10, 2))
		for i in Monster.ANSWER_TICKS + 60:
			World.step()
		_check(guard.target == null and guard._room.has_point(guard.tile), "%s: let be once the blows stop, back in its room (%s)" % [case[0], guard.tile])
	Level.unregister("mt_struck")


## Paid once, fought again (548 amended; Jeff: "as long as you paid once you
## get unlimited attempts"): npc's record through World.paid_deal and
## World.deal_paid, stubbed here.
## The barrow's seal (666, enemy-ai's side): the draugr says ossuary_sealed
## at his first tick and on each change, true while a skeleton or grave
## guard of his zone stands, false once every one is dead or laid.
func _test_ossuary_sealed() -> void:
	print("%s== the draugr's ossuary_sealed: sealed while his zone's dead stand (666) ==" % char(10))
	Monster.idling = true
	var e := _build(["###########", "#.........#", "#.k..u..g.#", "#.........#", "###########"])
	var draugr := e["u"][0] as Draugr
	var bones := e["k"][0] as Monster
	var guard := e["g"][0] as Monster
	var said: Array = []
	draugr.ossuary_sealed.connect(func(sealed: bool) -> void: said.append(sealed))
	World.step()
	_check(said == [true], "his first tick: sealed, the dead stand (%s)" % [said])
	World.step()
	_check(said == [true], "said once, not each tick")
	World.damage(bones, 9999, null)
	World.step()
	_check(said == [true], "one dead, the grave guard stands: still sealed (%s)" % [said])
	guard.lay_down()
	World.step()
	_check(said == [true, false], "the guard laid at rest, none stands: unsealed (%s)" % [said])
	guard.rise()
	World.step()
	_check(said == [true, false, true], "it rises: sealed again (%s)" % [said])
	for body: GridEntity in [draugr, bones, guard]:
		if is_instance_valid(body) and body.spawned:
			World.despawn(body)


func _test_draugr_paid() -> void:
	print("\n== the draugr: paid once, a payer fights him again for no gold till won (548 amended) ==")
	if not "paid_deal" in World:
		print("  (skipped: npc's World.paid_deal and deal_paid are not in yet)")
		return
	Monster.idling = true
	var rows: Array[String] = ["#############", "#...........#", "#.....u.....#", "#...........#", "#...........#", "#############"]
	Level.register("mt_paidlair", Level.image_from_rows(rows), null, {"regenerate": {"anchors": [{"rect": [1, 1, 8, 4], "name": "lair"}]}})
	var e := _build(rows, {}, {}, "mt_paidlair")
	var draugr := e["u"][0] as Draugr
	var player := EntityFactory.build(SPECS["P"].merged({"name": "Payer"})) as Player
	player.player_id = "p1"
	_room.add_child(player)
	World.spawn(player, Vector2i(7, 2))
	var was_economy := World.economy
	World.economy = Economy.new({"purses": {"p1": 200, "p2": 200}})
	var book := {}
	World.set("paid_deal", func(player_id: String, zone_name: String) -> Dictionary:
		return book.get("%s|%s" % [player_id, zone_name], {}))
	World.set("deal_paid", func(player_id: String, zone_name: String, level: String) -> void:
		if level.is_empty():
			book.erase("%s|%s" % [player_id, zone_name])
		else:
			book["%s|%s" % [player_id, zone_name]] = {"level": level, "paid_step": World.steps})
	var taken := draugr.accept_offer(player, draugr.offers_for("p1")[0], 60)
	_check(taken["ok"] and draugr.state == Draugr.State.PACT and book.get("p1|mt_paidlair", {}).get("level") == "normal",
		"60 gold buys the normal pact, and the payer's deal is kept (%s)" % [book])
	_move_to(player, Vector2i(11, 2))
	World.step()
	var offers := draugr.offers_for("p1")
	_check(draugr.state == Draugr.State.SEATED and book.has("p1|mt_paidlair") and offers.size() == 2
		and offers[1]["id"] == "deal:%d:refuse" % draugr.id and offers[0]["id"] == "deal:%d:again" % draugr.id and offers[0]["cost"] == 0 and offers[0]["what"]["level"] == "normal"
		and offers[0]["words"] == Draugr.AGAIN_WORDS,
		"the pact lost, the gold forfeit: his deal kept, and to the payer he offers the fight again, no gold (%s)" % [offers])
	_check(draugr.offers_for("p2")[0]["cost"] == 10, "to one who never paid, his gold deal as ever")
	var gold_was := World.gold_of("p1")
	var twice := draugr.accept_offer(player, {"id": "deal:%d" % draugr.id}, 50)
	_check(not twice["ok"] and World.gold_of("p1") == gold_was and draugr.state == Draugr.State.SEATED,
		"the payer never pays twice: a gold deal is refused, the gold kept")
	_move_to(player, Vector2i(7, 2))
	var again := draugr.accept_offer(player, offers[0], 0)
	_check(again["ok"] and draugr.state == Draugr.State.PACT and draugr.difficulty == "normal" and World.gold_of("p1") == gold_was,
		"the fight again, at the level paid for, for no gold (%s)" % again)
	World.damage(draugr, 9999, player)
	_check(draugr.state == Draugr.State.AT_REST and draugr.blessed_last == ["p1"] and not book.has("p1|mt_paidlair"),
		"won: blessed, and the paid deal is spent (%s)" % [book])
	World.set("paid_deal", Callable())
	World.set("deal_paid", Callable())
	World.dead_rest.clear()
	World.economy = was_economy
	World.despawn(draugr)
	World.despawn(player)
	Level.unregister("mt_paidlair")


## The panel's "monsters" source (673 step 2; Main registers it on a host):
## its rows listed, a value set reaching the next spawn, reset back.
func _test_fight_panel() -> void:
	print("\n== the fight's feel on combat's tuning panel: the monsters source (673 step 2) ==")
	var mode := Net.mode
	Net.mode = Net.Mode.HOST
	Monster.set_fight_block(null)
	Tuning.register_source("monsters", Monster.tuning_value, Monster.set_tuning_value, Monster.tuning_fields)
	var rows: Array = Tuning.fields().filter(func(r: Dictionary) -> bool: return str(r["path"]).begins_with("monsters."))
	var windup: Array = rows.filter(func(r: Dictionary) -> bool: return r["path"] == "monsters.fight.windup_ticks")
	_check(rows.size() == 17 and windup.size() == 1 and windup[0]["kind"] == "int" and windup[0]["takes"] == "spawn",
		"17 rows listed (698's band_min too), windup_ticks an int taken at spawn (%s)" % [windup])
	_check(Tuning.apply("monsters.fight.windup_ticks", 9) and Tuning.apply("monsters.fight.flee_below.bold", 0.2),
		"windup_ticks and the bold one's flee_below set")
	var e := _build(["#####", "#.b.#", "#####"])
	var brute := e["b"][0] as Monster
	_check(brute.windup_ticks == 9 and is_equal_approx(brute.flee_below[Monster.Temper.BOLD], 0.2)
		and is_equal_approx(brute.flee_below[Monster.Temper.COWARDLY], 0.6), "the next spawn fights with them, the rest as they were")
	_check(Tuning.reset("monsters.fight.windup_ticks") and Tuning.reset("monsters.fight.flee_below.bold")
		and Monster.fight_for("brute")["windup_ticks"] == 6 and is_equal_approx(Monster.fight_for("brute")["flee_below"]["bold"], 0.15),
		"reset: the file's values again")
	World.despawn(brute)
	Tuning._sources.erase("monsters")
	Monster.set_fight_block(null)
	Net.mode = mode


## The fight's feel as data (673 step 2; release: "the move must not change
## any fight"): every kind's fight from levels/monsters.json is the old
## in-code constants', its row's overrides included, and a spawned one
## carries them; the tuning panel's block reaches new spawns, and null
## reads the file again.
func _test_fight_data() -> void:
	print("\n== the fight's feel as data: every kind's as the constants were (673 step 2) ==")
	Monster.set_fight_block(null)
	var old := {"windup_ticks": 6, "charge_range": 4, "charge_pace": 0.5, "dart_after_ticks": 3, "backstab_damage": 1,
		"pace_spread": 0.15, "cooldown_spread": 2, "flank_patience_ticks": 20, "flee_ticks": 60, "flee_tiles": 6,
		"flee_near_tiles": 4, "rout_hurt": 0.7, "dread_flee_below": 0.5, "flee_below": {"bold": 0.15, "cautious": 0.35, "cowardly": 0.6},
		"band_min": 3}
	var differ: Array[String] = []
	for kind: String in Monster.kinds():
		var rules := Monster.fight_for(kind)
		for key: String in old:
			if str(rules.get(key)) != str(old[key]) or typeof(rules.get(key)) != typeof(old[key]):
				differ.append("%s.%s: %s" % [kind, key, rules.get(key)])
	_check(differ.is_empty() and Monster.kinds().size() > 10 and not Monster.kinds().has("fight"),
		"each of %d kinds fights as the constants did, overrides included, and \"fight\" is no kind (%s)" % [Monster.kinds().size(), differ])
	var rows: Array[String] = ["#####", "#.b.#", "#####"]
	var e := _build(rows)
	var brute := e["b"][0] as Monster
	_check(brute.windup_ticks == Monster.WINDUP_TICKS and brute.charge_range == Monster.CHARGE_RANGE and is_equal_approx(brute.charge_pace, Monster.CHARGE_PACE)
		and brute.flee_ticks == Monster.FLEE_TICKS and is_equal_approx(brute.flee_below[Monster.Temper.CAUTIOUS], 0.35),
		"a spawned brute carries them (windup %d, charge %d)" % [brute.windup_ticks, brute.charge_range])
	Monster.set_fight_block({"windup_ticks": 9, "flee_below": {"bold": 0.2}})
	var later := Monster.fight_for("brute")
	_check(later["windup_ticks"] == 9 and is_equal_approx(later["flee_below"]["bold"], 0.2) and is_equal_approx(later["flee_below"]["cowardly"], 0.6)
		and brute.windup_ticks == Monster.WINDUP_TICKS, "the panel's block reaches new spawns, the rest as they were, the spawned one unchanged")
	Monster.set_fight_block(null)
	_check(Monster.fight_for("brute")["windup_ticks"] == 6, "null reads the file again")
	# The tuning panel's source "monsters" (673 step 2; combat's Tuning.register_source).
	var rows_listed := Monster.tuning_fields()
	_check(rows_listed.size() == Monster.FIGHT_DEFAULTS.size() + 2 and rows_listed.all(func(r: Dictionary) -> bool:
			return r["group"] == "Monsters" and r["owner"] == "enemy-ai" and r["takes"] == "spawn" and Monster.tuning_value(r["path"]) != null),
		"the panel lists each fight value, flee_below by temper, every one read (%d rows)" % rows_listed.size())
	_check(Monster.tuning_value("monsters.fight.windup_ticks") == 6 and Monster.tuning_value("monsters.fight.flee_below.cautious") == 0.35
		and Monster.tuning_value("monsters.imp.fight.windup_ticks") == null and Monster.tuning_value("monsters.fight.nothing") == null
		and Monster.tuning_value("monsters.nobody.fight.windup_ticks") == null, "each value read; a kind's own null where it has none, an unknown one null")
	_check(Monster.set_tuning_value("monsters.fight.windup_ticks", 8.0) and Monster.set_tuning_value("monsters.fight.flee_below.bold", 0.3)
		and Monster.set_tuning_value("monsters.imp.fight.windup_ticks", 12) and not Monster.set_tuning_value("monsters.fight.nothing", 1)
		and not Monster.set_tuning_value("monsters.fight.flee_below.brave", 0.1),
		"set through the source; an unknown one refused")
	var imp_rules := Monster.fight_for("imp")
	var brute_rules := Monster.fight_for("brute")
	_check(brute_rules["windup_ticks"] == 8 and typeof(brute_rules["windup_ticks"]) == TYPE_INT and is_equal_approx(brute_rules["flee_below"]["bold"], 0.3)
		and imp_rules["windup_ticks"] == 12 and Monster.tuning_value("monsters.imp.fight.windup_ticks") == 12,
		"the block for every kind, an int kept an int, and the imp's own over it (%s, %s)" % [brute_rules["windup_ticks"], imp_rules["windup_ticks"]])
	Monster.set_fight_block(null)
	Monster.kinds()["imp"]["fight"] = {}
	World.despawn(brute)


func _test_draugr() -> void:
	print("
== the draugr: talks first, a pact for gold at a deal, his level by the charges in his zone, the living's coming heals him, yields at 1 hp, rests and stills the dead, rises again (decisions 548, 573) ==")
	Monster.idling = true
	var rows: Array[String] = ["#############", "#...........#", "#.....u.....#", "#...........#", "#..........k#", "#############"]
	Level.register("mt_lair", Level.image_from_rows(rows), null, {"regenerate": {"anchors": [{"rect": [1, 1, 8, 4], "name": "lair"}]}})
	var e := _build(rows, {}, {}, "mt_lair")
	var draugr := e["u"][0] as Draugr
	var skeleton: Monster = e["k"][0]
	_check(draugr != null and Level._spec_for("monster_draugr", Level.MONSTER_TYPES)["script"] == "res://sim/draugr.gd",
		"a draugr marker spawns a Draugr (his kind's script)")
	var player := EntityFactory.build(SPECS["P"].merged({"name": "Player1"})) as Player
	player.player_id = "p1"
	_room.add_child(player)
	World.spawn(player, Vector2i(11, 2))
	draugr.sight_range = 8
	draugr.senses.cone_cos = -1.0
	var was_economy := World.economy
	World.economy = Economy.new({"purses": {"p1": 200}})
	var spawned: Array[GridEntity] = []
	World.spawn_spec = func(spec: Dictionary) -> GridEntity:
		var risen := EntityFactory.build(spec)
		_room.add_child(risen)
		World.spawn(risen, spec["tile"])
		spawned.append(risen)
		return risen
	var spoken: Array = []
	draugr.offer_spoken.connect(func(id: String, offer: Dictionary) -> void: spoken.append([id, offer]))
	var said: Array = []
	draugr.said.connect(func(text: String) -> void: said.append(text))
	var doors: Array = []
	draugr.hall_door.connect(func(open: bool) -> void: doors.append(open))
	var offers := draugr.offers_for("p1")
	_check(draugr.talks and offers.size() == 2 and offers[0]["kind"] == "deal" and offers[0]["cost"] == 10
		and offers[0]["what"]["most"] == 100 and offers[0]["what"]["steps"] == [10, 50, 100] and offers[1]["id"] == "deal:%d:refuse" % draugr.id,
		"he talks, and offers a pact at the deals' steps (Jeff: the least 10 gold), and the refusal after (%s)" % [offers])
	World.step()
	_check(spoken.is_empty(), "outside his lair he says nothing")
	_move_to(player, Vector2i(7, 2))
	World.step()
	_check(doors == [false] and said == [Draugr.ASKED % player.name] and spoken.is_empty() and draugr.hall_shut,
		"come into his lair: his Hall shuts, and he asks why (%s, %s)" % [doors, said])
	for i in Draugr.ASK_DELAY_TICKS + 5:
		World.step()
	_check(spoken.size() == 1 and spoken[0][0] == "p1" and spoken[0][1]["words"] == Draugr.WORDS and said.size() == 1,
		"after a pause he asks for the gold, once, and explains nothing more (%s)" % [spoken.size()])
	_check(draugr.target == null and player.hp == player.max_hp, "seated, he fights nobody unasked")
	var zones_asked: Array = []
	World.charges_in = func(zone_name: String) -> int:
		zones_asked.append(zone_name)
		return 10
	var taken := draugr.accept_offer(player, offers[0], 60)
	_check(taken["ok"] and draugr.state == Draugr.State.PACT and draugr.difficulty == "normal" and World.gold_of("p1") == 140,
		"60 gold: the normal deal (50 reached, not 100), and the gold his (%s, %s)" % [taken, World.gold_of("p1")])
	var waves := World.has_method("try_spin")  # The waves ride with combat's moves (603).
	_check(zones_asked.size() == 1 and draugr.charges_met == 10 and draugr.max_hp == roundi(30 * (1.5 + 10 * Draugr.CHARGE_SCALE)) and draugr.hp == draugr.max_hp
		and spawned.size() == (0 if waves else 2) and draugr._risen_left == (2 if waves else 0) and draugr.offers_for("p1").is_empty(),
		"10 charges in his zone: he grows to normal's and a step a charge, his dead (normal's one and one more) %s, and offers nothing while it is on (%d hp)" % ["to rise in waves" if waves else "risen", draugr.max_hp])
	World.charges_in = Callable()
	World.damage(draugr, 16, player)
	_check(spawned.size() == (1 if waves else 2), "past three quarters of his hp: the first wave (%d)" % spawned.size())
	World.damage(draugr, 24, player)
	_check(spawned.size() == 2 and draugr._risen_left == 0, "past a half, the rest (%d)" % spawned.size())
	var hurt := draugr.hp
	draugr.living_came(player)
	_check(draugr.hp == mini(hurt + roundi(draugr.max_hp * Draugr.LIVING_HEAL), draugr.max_hp) and draugr.hp > hurt and draugr.max_hp == 60,
		"the living come in: half his most back at once, his level as it was (%d to %d of %d)" % [hurt, draugr.hp, draugr.max_hp])
	var before := draugr.hp
	World.lay_downed(player, 50)
	World.step()
	World.step()
	_check(draugr.state == Draugr.State.PACT and draugr.hp == before and draugr.challenger_id == "p1",
		"his challenger downed in his lair: the pact holds, and he does not heal (Mortally Wounded)")
	World.raise_downed(player, player.max_hp)
	var fought := false
	for i in 20:
		World.step()
		if draugr.target == player:
			fought = true
			break
	_check(fought, "he fights his challenger")
	_check(said.count(Draugr.ANGER) == 1, "taking up the fight he says his anger, once (%s)" % [said])
	World.knock_down(draugr, player, 10)
	_check(not World.is_down(draugr) and draugr.down_until <= World.tick and World.is_stunned(draugr),
		"knocked down, he only staggers: never on the floor (573 amended (4))")
	var fell := draugr.tile
	World.damage(draugr, 999, player)
	_check(draugr.spawned and draugr.hp == draugr.max_hp and draugr.max_hp == 30 and draugr.blessed_last == ["p1"],
		"beaten, he yields, never dies: the players in his lair are blessed (%s)" % [draugr.blessed_last])
	_check(said.back() == Draugr.WON and doors.back() == true and not draugr.hall_shut, "\"%s\", and his Hall opens" % said.back())
	_check(draugr.state == Draugr.State.AT_REST and draugr.rests_until == World.steps + Draugr.rest_steps()
		and draugr.spawn_spec["props"].get("rests_until") == draugr.rests_until and not World.is_down(draugr),
		"and rests rise_s (300 s, 714 amended (2)), standing (573 amended (3): never lying), kept in his props")
	_check(draugr.gone and not draugr.holds_cell and draugr.pile_at == fell and draugr.tile == draugr.home
		and World.get_entity_at(draugr.home) != draugr and World.get_entity_at(fell) != draugr and not World.can_target(player, draugr)
		and draugr.pile_facing in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
		and draugr.spawn_spec["props"].get("pile") == [fell.x, fell.y],
		"beaten, he is gone (573 amended (4)): his remains where he fell (%s, facing %s), he at his seat holding no cell, struck by nothing" % [draugr.pile_at, draugr.pile_facing])
	_check(Main.talk_cell(draugr) == fell, "the one who would talk to him talks at his remains")
	_check(draugr.peaceable and draugr.resting() and draugr.offers_for("p1").is_empty() and draugr.rest_words() == "He rests. Come back in 5 minutes.",
		"at rest a click talks, he offers nothing, and the one who asks hears how long (%s)" % draugr.rest_words())
	_check(spawned.all(func(r: GridEntity) -> bool: return not r.spawned) and skeleton.laid, "his risen gone, the barrow's dead lie still")
	var resting_till := draugr.rests_until
	var purse := World.gold_of("p1")
	var refused := draugr.accept_offer(player, {"id": "deal:%d" % draugr.id}, 20)
	_check(not refused["ok"] and draugr.state == Draugr.State.AT_REST and World.gold_of("p1") == purse and draugr.rests_until == resting_till
		and str(refused["line"]) == draugr.rest_words(), "no pact is bought while he rests: the gold kept, his rest's words (%s)" % refused["line"])
	var heard := spoken.size()
	_move_to(player, Vector2i(11, 2))
	World.step()
	_move_to(player, Vector2i(7, 2))
	for i in Draugr.ASK_DELAY_TICKS + 2:
		World.step()
	_check(spoken.size() == heard and not draugr.hall_shut, "at rest he is silent: no deal spoken to one come in, no hall shut")
	draugr.home = Vector2i(2, 2)
	World.step()
	_check(draugr.tile == draugr.home and draugr.gone and World.get_entity_at(draugr.home) == null and draugr.state == Draugr.State.AT_REST,
		"at rest he is kept at his seat, holding no cell (%s)" % draugr.tile)
	_move_to(player, draugr.home)
	_check(player.tile == draugr.home, "his seat is free to stand on while he is gone")
	World.steps = draugr.rests_until
	World.step()
	_check(draugr.state == Draugr.State.SEATED and not skeleton.laid and draugr.rests_until == -1, "rested, he rises, and the dead stir")
	_check(not draugr.gone and draugr.holds_cell and World.get_entity_at(draugr.tile) == draugr and World.distance(draugr.tile, draugr.home) == 1
		and draugr.pile_at == Draugr.NO_TILE and draugr.spawn_spec["props"].get("pile") == null,
		"back, his seat taken: he stands beside it, his remains gone (%s)" % draugr.tile)
	draugr.blessed_last = []
	_move_to(player, Vector2i(7, 2))
	for i in Draugr.ASK_DELAY_TICKS + 2:
		World.step()
	# Jeff on v0.1.192 ("got stuck in draugr room because i dont have gold
	# and can't attack him"; "instead of no just put the word "refuse""):
	# under the least deal, the refusal is his first deal, free, and taking
	# it provokes him as a strike does, with his line, not ANGER.
	var held_gold := World.gold_of("p1")
	World.add_gold("p1", -held_gold, "test")
	var poor := draugr.offers_for("p1")
	_check(poor.size() == 2 and poor[0]["id"] == "deal:%d:refuse" % draugr.id and int(poor[0]["cost"]) == 0 and (poor[0]["what"]["steps"] as Array).is_empty()
		and poor[0]["title"] == "Refuse" and int(poor[1]["cost"]) == 10 and DealPanel.no_deal(poor) == poor[0]
		and DealPanel.first_deal(poor) == poor[1],
		"no gold: his first deal is the free refusal (what an older panel shows), the panel's Refuse, his gold deal after (%s)" % [poor.map(func(o: Dictionary) -> String: return str(o["id"]))])
	var anger_was := said.count(Draugr.ANGER)
	var drawn := draugr.accept_offer(player, poor[0], 0)
	World.step()
	_check(drawn["ok"] and draugr.target == player and draugr._provoked == player and not draugr.peaceable and World.gold_of("p1") == 0
		and said.back() == Draugr.REFUSED and said.count(Draugr.ANGER) == anger_was,
		"refused: \"Then I'll take it from you by force!\", and he fights them, no gold paid, no ANGER after (%s, %s)" % [drawn, said.slice(-2)])
	draugr._provoked = null
	draugr.target = null
	draugr._angered = false
	World.add_gold("p1", held_gold, "test")
	var gold_was := World.gold_of("p1")
	var short := draugr.accept_offer(player, draugr.offers_for("p1")[0], 9)
	World.step()
	_check(short["ok"] and World.gold_of("p1") == gold_was - 9 and draugr.state == Draugr.State.SEATED and draugr.target == player and draugr.max_hp == 30,
		"9 gold, under the least deal (10): he keeps it and attacks, at his own level")
	_check(said.count(Draugr.ANGER) == 2, "a new fight: his anger once more (%d)" % said.count(Draugr.ANGER))
	World.damage(draugr, 999, player)
	_check(draugr.blessed_last.is_empty() and draugr.state == Draugr.State.AT_REST and draugr.hp == 30 and said.back() == Draugr.RESPECT
		and doors.back() == true and skeleton.laid,
		"beaten unpaid, his \"death\": his respect, no blessing, laid to rest with the dead stilled, his Hall open")
	var words_were := said.size()
	var rest_was := draugr.rests_until
	World.damage(draugr, 999, player)
	World.damage(draugr, 999, player)
	_check(said.size() == words_were and draugr.hp == 30 and draugr.state == Draugr.State.AT_REST and draugr.rests_until == rest_was,
		"a stray blow at rest finds nothing: gone, silent, his rest as it was (said %d more, %d hp)" % [said.size() - words_were, draugr.hp])
	draugr.hp = draugr.max_hp
	draugr.living_came(player)
	_check(draugr.hp == 30, "seated, the living's coming gives him nothing")
	_check(Draugr.deal_for(500)["name"] == "hard" and Draugr.deal_for(99)["name"] == "normal" and Draugr.deal_for(10)["name"] == "easy" and Draugr.deal_for(9).is_empty(),
		"a hundred or more, hard; between steps, the lower")
	# Put back from the level's table (a room reset, a restart, a regeneration: its props never had his
	# rest), he rests on by World.dead_rest, which Main saves (573 amended (3)).
	var rest_left := draugr.rests_until
	var pile := draugr.pile_at
	var pile_way := draugr.pile_facing
	_check(World.dead_rest.get("mt_lair", {}).get("pile") == [pile.x, pile.y], "his remains kept in his zone's rest (%s)" % [World.dead_rest.get("mt_lair")])
	var spec := draugr.spawn_spec.duplicate(true)
	for key in ["rests_until", "pile", "pile_facing"]:
		(spec["props"] as Dictionary).erase(key)
	spec["name"] = "DraugrAgain"
	var at := draugr.tile
	World.despawn(draugr)
	var again := EntityFactory.build(spec) as Draugr
	_room.add_child(again)
	World.spawn(again, at)
	_check(again.state == Draugr.State.AT_REST and again.rests_until == rest_left and again.peaceable and again.offers_for("p1").is_empty(),
		"put back without his props, he rests on by his zone's rest (till %d)" % again.rests_until)
	World.step()
	_check(again.gone and not again.holds_cell and again.pile_at == pile and again.pile_facing == pile_way and World.get_entity_at(at) == null,
		"and is gone again, his remains laid where they were (%s)" % again.pile_at)
	World.dead_rest.clear()
	World.despawn(again)
	World.economy = was_economy
	World.spawn_spec = Callable()
	Level.unregister("mt_lair")


func _strings(values: Array) -> Array[String]:
	var out: Array[String] = []
	for value: Variant in values:
		out.append(str(value))
	return out


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
	var verb := Items.verb_of("bow")
	var spread: Array = verb["spread"]
	verb["spread"] = []  # Straight, as before the cone (decision 620): these check its standing off and drawing, not its aim.
	var e := _build(["##############", "#............#", "#.P......a...#", "#............#", "##############"])
	var archer: Monster = e["a"][0]
	var player: GridEntity = e["P"][0]
	_bold(archer)
	archer.slots = PackedStringArray(["", "", "", "", "bow", "arrows"])  # As Level arms one wielding a bow (and its arrows, decision 375).
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
	_check(not shot.is_empty() and int(shot["tick"]) >= 7, "once its draw's step reaches it, 7 cells, 7 ticks (decisions 583, 669; tick %s)" % shot.get("tick"))
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
	archer.slots = PackedStringArray(["", "", "", "", "bow", "arrows"])  # As Level arms one wielding a bow (and its arrows, decision 375).
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
	archer.slots = PackedStringArray(["", "", "", "", "bow", "arrows"])  # As Level arms one wielding a bow (and its arrows, decision 375).
	for i in 10:
		World.step()
	_check(World.distance(archer.tile, player.tile) >= Monster.KEEP_NEAR, "2 off, it steps back to %d" % World.distance(archer.tile, player.tile))
	# Its arrows spent (blunt blows wear them, decision 375): it can't draw,
	# and comes on as its kind does.
	e = _build(["##############", "#............#", "#.P......a...#", "#............#", "##############"])
	archer = e["a"][0]
	player = e["P"][0]
	_bold(archer)
	archer.slots = PackedStringArray(["", "", "", "", "bow", "arrows"])
	World.items.set_condition(World.slot_uid(archer, Items.LEFT_HAND), 0)
	_check(World.off_hand(archer) == "", "its arrows spent, it can't draw")
	var closed := false
	for i in 40:
		World.step()
		closed = closed or World.are_adjacent(archer.tile, player.tile)
	_check(closed and archer.raised != "draw", "it comes on to fight hand to hand")
	Monster.idling = true
	verb["spread"] = spread


## Ticks an archer held its draw when it loosed, and whether its arrow
## struck [param avoid] (decision 620, enemy-ai's side); -1 for no loose.
func _held_at_loose(e: Dictionary, archer: Monster, ticks: int, avoid: GridEntity = null) -> Array:
	var held := [-1]
	var on_loose := func(by: GridEntity, _angle: float, _step: int) -> void:
		if by == archer and held[0] < 0:
			held[0] = World.tick - archer.raised_tick
	World.loosed.connect(on_loose)
	var struck := false
	for i in ticks:
		World.step()
		struck = struck or (avoid != null and _damage_log.any(func(hit: Dictionary) -> bool: return hit["entity"] == avoid))
		if held[0] >= 0:
			break
	World.loosed.disconnect(on_loose)
	return [held[0], struck]


func _test_archer_hold() -> void:
	print("
== an archer holds its draw till its cone closes to its kind's aim_spread, or its hold cap; a friend on an edge holds it (decision 620) ==")
	Monster.idling = false
	var kinds := Monster.kinds()
	_check(is_equal_approx(float(kinds["imp"]["aim_spread"]), 16.0) and int(kinds["imp"]["aim_hold_max"]) == 12
			and is_equal_approx(float(kinds["skeleton"]["aim_spread"]), 4.0) and is_equal_approx(float(kinds["skeleton_guard"]["aim_spread"]), 4.0) and float(kinds["wolf"]["aim_spread"]) == 0.0,
			"the rows' holds read: imp 16/12, skeleton and guard 4/30 (full draw, 669), none for a wolf")
	var folder: String = preload("res://tests/test_ports.gd").scratch("monster_test/")
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder + "aim_kinds.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"steady": {"aim_spread": 0.5, "aim_hold_max": 40}}))
	file.close()
	var read := Monster.read_kinds(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check(is_equal_approx(float(read["steady"]["aim_spread"]), float(Items.verb_of("bow")["spread_floor"])),
			"an aim_spread under the bow's floor is raised to it, with a warning (%s)" % read["steady"]["aim_spread"])
	# Three off, its first step reaches: the draw's cone says when it looses.
	for hold: Array in [[0.0, 0, 3, "no hold: as soon as the draw reaches, 3 ticks"], [16.0, 0, 5, "16 degrees: on the way to the second step, 5 ticks"],
			[6.0, 0, 9, "6 degrees: on the way to full draw, 9 ticks (669 amended (2))"], [2.0, 25, 25, "under the floor, capped at 25: at the cap, 25 ticks"]]:
		var e := _build(["##########", "#........#", "#..P..a..#", "#........#", "##########"])
		var archer: Monster = e["a"][0]
		_bold(archer)
		archer.reaction_ticks = 0
		archer.slots = PackedStringArray(["", "", "", "", "bow", "arrows"])
		archer.aim_spread = hold[0]
		archer.aim_hold_max = hold[1]
		var held: int = _held_at_loose(e, archer, 60)[0]
		_check(held == hold[2], "%s (held %d)" % [hold[3], held])
	# Five off, a crate beside its line two cells out, inside its cone as it
	# draws: it holds past its cap (4, not firing while blocked) till the
	# cone clears it (about 11 degrees, 7 ticks; decision 669's draw).
	var e := _build(["#############", "#...........#", "#....P....a.#", "#.......c...#", "#############"])
	var archer: Monster = e["a"][0]
	var crate: GridEntity = e["c"][0]
	_bold(archer)
	archer.reaction_ticks = 0
	archer.slots = PackedStringArray(["", "", "", "", "bow", "arrows"])
	archer.aim_spread = 16.0
	archer.aim_hold_max = 4
	var r := _held_at_loose(e, archer, 80, crate)
	_check(int(r[0]) > archer.aim_hold_max, "a crate on its cone's edge: it holds past its cap (held %d)" % r[0])
	_check(int(r[0]) >= 0 and not r[1], "then looses once the cone clears it, the crate unstruck")
	Monster.idling = true


func _test_worn_bundles() -> void:
	print("\n== archers' arrows: some come worn (4 to 9 of 10), most whole; a saved bundle keeps its wear ==")
	Monster.idling = false
	var rows: Array[String] = ["######################"]
	for y in 3:
		rows.append("#aaaaaaaaaaaaaaaaaaaa#")
	rows.append("######################")
	var e := _build(rows)
	var worn := 0
	var whole := 0
	var odd := 0
	for archer: Monster in e["a"]:
		archer.slots = PackedStringArray(["", "", "", "", "bow", "arrows"])
	World.step()
	for archer: Monster in e["a"]:
		var condition := World.items.condition_of(World.slot_uid(archer, Items.LEFT_HAND))
		if condition == Items.condition_max("arrows"):
			whole += 1
		elif condition >= Monster.WORN_BUNDLE.x and condition <= Monster.WORN_BUNDLE.y:
			worn += 1
		else:
			odd += 1
	_check(odd == 0 and worn >= 9 and worn <= 27, "of 60, %d worn, %d whole, %d neither" % [worn, whole, odd])
	# One from a save: its bundle's instance came with it.
	e = _build(["#####", "#.a.#", "#####"])
	var saved: Monster = e["a"][0]
	saved.slots = PackedStringArray(["", "", "", "", "bow", "arrows"])
	var uid := World.slot_uid(saved, Items.LEFT_HAND)
	World.items.set_condition(uid, 2)
	for i in 3:
		World.step()
	_check(World.items.condition_of(uid) == 2, "a saved bundle keeps its wear (%d)" % World.items.condition_of(uid))
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


func _test_monster_bash() -> void:
	print("
== a shield-bearer bashes a guard up against it, then strikes; never an open foe; cornered, it bashes free (decision 411) ==")
	Monster.idling = false
	var bashes: Array[Dictionary] = []
	var on_bash := func(by: GridEntity, target: GridEntity, opened: bool) -> void:
		bashes.append({"by": by, "target": target, "opened": opened, "tick": World.tick})
	World.shield_bashed.connect(on_bash)
	# An open foe: blows, no bash.
	var e := _build(["#######", "#.Pi..#", "#######"])
	var imp: Monster = e["i"][0]
	var player: GridEntity = e["P"][0]
	_bold(imp)
	imp.slots = PackedStringArray(["", "", "", "", "", "shield"])
	var struck := 0
	for i in 60:
		World.step()
		for hit: Dictionary in _damage_log:
			if hit["source"] == imp and int(hit["tick"]) == World.tick:
				struck += 1
	_check(struck > 0 and bashes.is_empty(), "at an open foe it strikes (%d blows) and never bashes (%d)" % [struck, bashes.size()])
	# A foe behind a raised shield: bashed open, then struck.
	e = _build(["#######", "#.Pi..#", "#######"])
	imp = e["i"][0]
	player = e["P"][0]
	_bold(imp)
	imp.slots = PackedStringArray(["", "", "", "", "", "shield"])
	player.slots[Items.LEFT_HAND] = "shield"
	World.face(player, Vector2i(1, 0))
	World.try_stance(player, "block")
	_check(not World.guarding(player, imp).is_empty(), "the player's shield is up against it")
	var bashed_at := -1
	var struck_after := 0
	for i in 60:
		World.step()
		if bashed_at < 0 and not bashes.is_empty():
			bashed_at = World.tick
		if player.raised.is_empty() and player.guard_broken_until <= World.tick:
			World.try_stance(player, "block")  # The player raises it again as soon as it may.
		for hit: Dictionary in _damage_log:
			if hit["source"] == imp and int(hit["tick"]) == World.tick and bashed_at >= 0:
				struck_after += 1
	_check(not bashes.is_empty() and bashes[0]["by"] == imp and bashes[0]["target"] == player and bashes[0]["opened"],
		"it bashes the guard open (%s)" % [bashes.slice(0, 1)])
	_check(struck_after > 0, "and its blows land after (%d)" % struck_after)
	# Cornered while it flees: a bash to break free.
	bashes.clear()
	e = _build(["######", "#iP..#", "######"])
	imp = e["i"][0]
	player = e["P"][0]
	_bold(imp)
	imp.slots = PackedStringArray(["", "", "", "", "", "shield"])
	imp._flee(player.tile)
	for i in 30:
		World.step()
	_check(not bashes.is_empty() and bashes[0]["by"] == imp, "cornered, it bashes the one hemming it in (%d)" % bashes.size())
	# And without a shield it only waits.
	bashes.clear()
	e = _build(["######", "#iP..#", "######"])
	imp = e["i"][0]
	player = e["P"][0]
	_bold(imp)
	imp._flee(player.tile)
	for i in 30:
		World.step()
	_check(bashes.is_empty(), "no shield, no bash")
	World.shield_bashed.disconnect(on_bash)
	Monster.idling = true


func _test_monster_wind_up() -> void:
	print("
== a monster with a giant axe winds its blow up (World.try_wind_up) and stands till it falls; a brute with one uses only that ==")
	Monster.idling = false
	for symbol in ["i", "b"]:
		var e := _build(["#######", "#.P" + symbol + "..#", "#######"])
		var monster: Monster = e[symbol][0]
		var player: GridEntity = e["P"][0]
		_bold(monster)
		monster.slots = PackedStringArray(["", "", "", "", "giant_axe", ""])  # As Level arms one wielding it.
		var wound := {}
		var stood := true
		var struck_at := -1
		for i in 40:
			World.step()
			if wound.is_empty():
				wound = World.winding(monster).duplicate()
			elif World.tick <= int(wound["lands"]) and monster.tile != wound["from"]:
				stood = false
			for hit: Dictionary in _damage_log:
				if hit["source"] == monster and int(hit["tick"]) == World.tick and struck_at < 0:
					struck_at = World.tick
			if struck_at >= 0:
				break
		_check(not wound.is_empty() and wound["target"] == player and monster._windup.is_empty(),
			"the %s winds up through World (%s), not its own wind-up" % [monster.name, wound])
		_check(stood and not wound.is_empty() and struck_at >= int(wound["lands"]),
			"it stands while winding and the blow falls when due (tick %d, due %s)" % [struck_at, wound.get("lands")])
	Monster.idling = true


func _test_meets_wind_up() -> void:
	print("
== a foe winding a heavy blow up at it: the cautious step out of reach, a shield-bearer bashes, the bold fight on ==")
	Monster.idling = false
	for case in ["cautious", "shield", "bold", "sword"]:
		var e := _build(["########", "#.Pi...#", "########"])
		var imp: Monster = e["i"][0]
		var player: GridEntity = e["P"][0]
		_bold(imp)
		if case == "cautious" or case == "sword":
			imp.temper = Monster.Temper.CAUTIOUS
		if case == "shield" or case == "sword":
			imp.slots = PackedStringArray(["", "", "", "", "", "shield"])
		player.slots[Items.RIGHT_HAND] = "sword" if case == "sword" else "giant_axe"
		for i in 30:
			World.step()
			if imp.target == player and World.try_wind_up(player, imp):
				break
		var wound := World.winding(player).duplicate()
		_check(not wound.is_empty(), "%s: the player winds up at it" % case)
		var hits_on_imp := 0
		var reached_when_due := false
		var stood := true
		for i in World.windup_ticks(player) + 2:
			if World.tick < int(wound.get("lands", -1)):
				stood = stood and imp.tile == Vector2i(3, 1)
			World.step()
			if World.tick == int(wound.get("lands", -1)):
				reached_when_due = World.in_reach(player, imp)
			for hit: Dictionary in _damage_log:
				if hit["source"] == player and hit["entity"] == imp and int(hit["tick"]) == World.tick:
					hits_on_imp += 1
		match case:
			"cautious":
				_check(hits_on_imp == 0 and not reached_when_due, "a cautious one steps out of reach and keeps out: the blow strikes the air")
			"shield":
				_check(hits_on_imp == 0 and World.winding(player).is_empty() and player.next_bash_tick == 0 and imp.next_bash_tick > 0,
					"a shield-bearer bashes it: the wind-up given up, no blow")
			"bold":
				_check(hits_on_imp == 1 and imp.tile == Vector2i(3, 1), "a bold one stands and takes it (%d blows)" % hits_on_imp)
			"sword":
				_check(hits_on_imp == 1 and stood and imp.next_bash_tick == 0,
					"a sword's lead (338 amended (2)) is no heavy blow: a cautious shield-bearer neither steps out nor bashes, and takes it (%d blows)" % hits_on_imp)
	Monster.idling = true


func _test_bane_and_grudge() -> void:
	print("\n== its kind's bane: dreaded whatever its temper, seen and heard farther; a grudge against its kind: sought first (decision 420) ==")
	Monster.idling = false
	var far := float(Items.growth()["bane_notice"])
	for bane in [false, true]:
		var e := _build(["###################", "#i...............P#", "###################"])  # 16 apart.
		var imp: Monster = e["i"][0]
		var player: GridEntity = e["P"][0]
		_bold(imp)
		player.slots[Items.RIGHT_HAND] = "dagger"
		var uid := World.slot_uid(player, Items.RIGHT_HAND)
		if bane:
			World.items.set_bane(uid, "imp")
		var d := World.distance(imp.tile, player.tile)
		for i in 3:
			World.step()
		if bane:
			_check(imp.target == player and d > imp.sight_range and d <= imp.sight_range * far,
				"its bane's bearer %d off (sight %d): seen" % [d, imp.sight_range])
			_check(imp._dreads_target(), "and dreaded, bold as it is")
		else:
			_check(imp.target == null, "a plain dagger's bearer %d off (sight %d): not seen" % [d, imp.sight_range])
		# Heard: a fight's noise 6 round the bearer, the imp 8 off.
		imp.senses.forget()
		World.despawn(imp)
		World.spawn(imp, player.tile - Vector2i(8, 0))
		var heard_before := imp.senses.heard.size()
		World.noise(player.tile, 6, &"fight", player)
		var heard := imp.senses.heard.size() > heard_before
		_check(heard == bane, "a noise of radius 6, 8 off: %s" % ("heard (its bane's bearer)" if bane else "not heard"))
	# A beast's bane too, and one not of its kind changes nothing.
	var e := _build(["#########", "#P..w...#", "#########"])
	var wolf: Animal = e["w"][0]
	var player: GridEntity = e["P"][0]
	player.slots[Items.RIGHT_HAND] = "dagger"
	World.items.set_bane(World.slot_uid(player, Items.RIGHT_HAND), "imp")
	wolf.target = player
	_check(not wolf._dreads_target(), "an imp-bane is nothing to a wolf")
	player.slots[Items.RIGHT_HAND] = "sword"
	World.items.set_bane(World.slot_uid(player, Items.RIGHT_HAND), "wolf")
	_check(wolf._dreads_target(), "a wolf-bane it dreads, beast as it is")
	# A grudge: the far bearer before the near one.
	e = _build(["############", "#P.i......P#", "############"])
	var imp: Monster = e["i"][0]
	var near: GridEntity = e["P"][0]
	var wronged: GridEntity = e["P"][1]
	_bold(imp)
	wronged.slots[Items.RIGHT_HAND] = "sword"
	World.items.give_character(World.slot_uid(wronged, Items.RIGHT_HAND), "named")  # Only a thing with character grows (items' 472).
	World.items.set_grudge(World.slot_uid(wronged, Items.RIGHT_HAND), "imp")
	World.step()
	_check(imp.target == wronged, "both seen, it goes for the one whose sword holds a grudge against imps (%s), not the nearer" % [imp.target])
	Monster.idling = true


func _test_boar_turns() -> void:
	print("\n== a boar running from a hunter, struck from afar, turns and charges ==")
	Monster.idling = false
	var e := _build(["####################", "#..................#", "#..P.....o.........#", "#..................#",
		"####################"], {"o": {"facing": Vector2i(-1, 0)}})
	var boar: Animal = e["o"][0]
	var player: GridEntity = e["P"][0]
	boar.sight_range = 8
	for i in 3:
		World.step()
	_check(boar.alert == Monster.Alert.FLEEING, "it sees the hunter and runs")
	for i in 5:
		World.step()
	World.damage(boar, 1, player, &"shot")
	World.step()
	_check(boar.alert == Monster.Alert.FIGHTING and boar.target == player and boar.charging(),
			"an arrow in it, it turns on the hunter (%s)" % Monster.Alert.keys()[boar.alert])
	Monster.idling = true


func _test_pick_up() -> void:
	print("\n== one of a kind that picks up takes up a dagger at its feet, idle or fighting bare-handed; others leave it ==")
	Monster.idling = true
	var e := _build(["##########", "#........#", "#...i....#", "#........#", "##########"])
	var imp: Monster = e["i"][0]
	World.put_on_ground(World.items.mint("dagger", "built", "test"), imp.tile + Vector2i(1, 0))
	for i in Monster.PICK_UP_EVERY + 2:
		World.step()
	_check(World.wielded(imp).is_empty(), "an imp of a kind that does not pick up leaves it")
	imp.picks_up = true
	for i in Monster.PICK_UP_EVERY + 2:
		World.step()
	_check(World.wielded(imp) == "dagger", "one that picks up takes it up (%s)" % World.wielded(imp))
	Monster.idling = false
	e = _build(["############", "#..........#", "#.P....i...#", "#..........#", "############"])
	imp = e["i"][0]
	_bold(imp)
	imp.picks_up = true
	World.put_on_ground(World.items.mint("dagger", "built", "test"), imp.tile + Vector2i(-1, 1))
	var armed_at := -1
	var first_blow := -1
	for i in 40:
		World.step()
		if armed_at < 0 and World.wielded(imp) == "dagger":
			armed_at = World.tick
		if first_blow < 0 and _damage_log.any(func(hit: Dictionary) -> bool: return hit["source"] == imp):
			first_blow = World.tick
	_check(armed_at >= 0 and (first_blow < 0 or armed_at < first_blow),
			"fighting bare-handed, it takes up the dagger beside it before it closes (tick %d, first blow %d)" % [armed_at, first_blow])
	Monster.idling = true


func _test_art_slots() -> void:
	print("
== a row's art names an ArtKit slot its view draws from ==")
	_check(Monster.art_of("boar") == "creature.boar" and Monster.art_of("imp") == "", "the boar's is creature.boar; an imp has none")
	var unknown: Array[String] = []
	for kind: String in Monster.kinds():
		var slot := Monster.art_of(kind)
		if not slot.is_empty() and not ArtKit.has(slot):
			unknown.append("%s: %s" % [kind, slot])
	_check(unknown.is_empty(), "every row's art is a slot ArtKit knows (%s)" % [unknown])


func _test_threatens() -> void:
	print("
== threatens(): whom a monster would fight, for companions' guide (decision 551) ==")
	Monster.idling = false
	Monster._read_factions = null
	var rows: Array[String] = ["#############", "#P.....i.k.x#", "#.g.........#", "#############"]
	Level.register("mt_threat", Level.image_from_rows(rows), null, {"regenerate": {"anchors": [{"rect": [1, 1, 3, 2], "name": "altar"}]}})
	var e := _build(rows, {}, {}, "mt_threat")
	var player: GridEntity = e["P"][0]
	var imp: Monster = e["i"][0]
	var skeleton: Monster = e["k"][0]
	var guard: Monster = e["g"][0]
	var robber: Monster = e["x"][0]
	player.protected = false
	_check(imp.threatens(player) and skeleton.threatens(player) and robber.threatens(player), "a player, to any of them (a skeleton walking home too)")
	_check(not imp.threatens(skeleton) and skeleton.threatens(robber) and robber.threatens(skeleton) and not skeleton.threatens(guard),
		"a monster of its foes alone: the dead and robbers each other, never their own, and the imp neither")
	_check(guard.threatens(player), "a room keeper, one in its room")
	_move_to(player, Vector2i(5, 2))
	_check(not guard.threatens(player) and imp.threatens(player), "and not one outside it")
	player.protected = true
	_check(not imp.threatens(player), "nobody in their spawn grace")
	player.protected = false
	var pip := EntityFactory.build({"script": "res://sim/resident.gd", "shape": "capsule", "name": "Pip"}) as Resident
	pip.worker_id = "w-pip"
	_room.add_child(pip)
	World.spawn(pip, Vector2i(6, 2))
	World.step()
	_check(pip in World.townsfolk() and skeleton.threatens(pip) and robber.threatens(pip) and not imp.threatens(pip),
		"a resident, to a side that fights the town, not the imp")
	imp.raid = "mt_raid"
	_check(imp.threatens(pip), "and to a raider")
	imp.raid = ""
	skeleton.lay_down()
	_check(not skeleton.threatens(player) and not skeleton.threatens(robber), "lying in its grave, nobody")
	Level.unregister("mt_threat")

	rows = ["#############", "#.....u.....#", "#...........#", "#..........P#", "#############"]
	Level.register("mt_threat_lair", Level.image_from_rows(rows), null, {"regenerate": {"anchors": [{"rect": [1, 1, 8, 3], "name": "lair"}]}})
	e = _build(rows, {}, {}, "mt_threat_lair")
	var draugr := e["u"][0] as Draugr
	var challenger := e["P"][0] as Player
	challenger.player_id = "p1"
	challenger.protected = false
	_move_to(challenger, Vector2i(4, 2))
	_check(not draugr.threatens(challenger), "the draugr seated: nobody unasked")
	draugr._provoked = challenger
	_check(draugr.threatens(challenger), "one that struck him, in his lair")
	draugr._provoked = null
	draugr.state = Draugr.State.PACT
	draugr.challenger_id = "p1"
	_check(draugr.threatens(challenger), "his pact's challenger in his lair")
	_move_to(challenger, Vector2i(10, 3))
	_check(not draugr.threatens(challenger), "but not out of it")
	_move_to(challenger, Vector2i(4, 2))
	draugr.state = Draugr.State.AT_REST
	_check(not draugr.threatens(challenger), "resting, nobody")
	draugr.state = Draugr.State.SEATED
	draugr.challenger_id = ""
	Level.unregister("mt_threat_lair")

	e = _build(["##############", "#P..w..r..d..#", "##############"])
	var wolf: Animal = e["w"][0]
	var hunter: GridEntity = e["P"][0]
	hunter.protected = false
	wolf._bold = false
	wolf.hurt_tick = -100000
	_check(not wolf.threatens(hunter) and wolf.threatens(e["d"][0]) and not e["r"][0].threatens(hunter) and not e["d"][0].threatens(hunter),
		"a wolf by day: its diet, not a hunter; prey nobody")
	wolf._bold = true
	_check(wolf.threatens(hunter), "a bold wolf, the hunter")
	Monster.idling = true


func _test_quieter() -> void:
	print("
== the barrow made quieter (decision 561; 631 amended): the dead rest at once where they were laid, a blocked one waits, nearer sight and calls, longer respawns ==")
	Monster.idling = true
	Monster._read_factions = null
	var rows: Array[String] = ["###############", "#k.k.k.k......#", "#.............#", "#.............#", "###############"]
	Level.register("mt_quiet", Level.image_from_rows(rows), null, {"graves": [[2, 2, 2], [6, 2, 2], [13, 1, 0], [13, 3, 0]],
		"respawn_s": {"skeleton": 600, "robber": 300}})
	var e := _build(rows, {}, {}, "mt_quiet")
	for i in 400:
		World.step()
	_check(e["k"].all(func(each: Monster) -> bool: return each.laid and each.tile == each.grave and each.grave == each.home),
		"all four rest at once on the cells they were laid on (631 amended: none walks to a listed grave)")
	_check(Monster.respawn_ticks("skeleton", 600) == 6000 and Monster.respawn_ticks("robber", 600) == 3000 and Monster.respawn_ticks("imp", 600) == 600,
		"the level's respawn_s by kind, in ticks; a kind it does not name waits as ever")
	Level.unregister("mt_quiet")
	Level.register("mt_quiet", Level.image_from_rows(rows), null, {"respawn_s": 30})
	_build(rows, {}, {}, "mt_quiet")
	_check(Monster.respawn_ticks("imp", 600) == 300, "one number, every kind")
	Level.unregister("mt_quiet")

	rows = ["###########", "#k.....P..#", "###########"]
	Level.register("mt_quiet", Level.image_from_rows(rows), null, {})
	e = _build(rows, {}, {}, "mt_quiet")
	var walker: Monster = e["k"][0]
	walker.home = Vector2i(9, 1)  # Its laid cell down the way: led off it.
	var player: GridEntity = e["P"][0]
	walker.sight_range = 7
	walker.senses.cone_cos = -1.0
	var met := -1
	var backed := false
	var fought := -1
	for i in 300:
		World.step()
		if met < 0 and World.distance(walker.tile, player.tile) == 1:
			met = World.tick
		backed = backed or (met >= 0 and World.distance(walker.tile, player.tile) > 1)
		if walker.target == player:
			fought = World.tick
			break
	_check(met >= 0 and backed and fought - met >= Monster.BLOCKED_WAIT_TICKS,
		"blocked, it steps back and waits %d ticks before it fights (met %d, fought %d, stepped back %s)" % [Monster.BLOCKED_WAIT_TICKS, met, fought, backed])
	Level.unregister("mt_quiet")

	e = _build(["###########", "#x.g.k.u.i#", "###########"])
	_check(e["x"][0].call_reach == 6 and e["i"][0].call_reach == Senses.NOISE_CALL, "a robber calls 6 cells, an imp as ever")
	_check(["robber", "skeleton_guard", "skeleton", "draugr"].all(func(kind: String) -> bool: return Monster.bodies()[kind].get("sight_range") == 5)
			and e["x"][0].leash == 14,
		"the barrow's kinds see 5 cells; a robber goes 14 from home (580; 10 in 561)")
	Monster.idling = true


## [param draugr]'s axe out of his hands onto [param cell], him disarmed
## there (as combat's stopped charge leaves it).
func _disarm(draugr: Draugr, cell: Vector2i) -> void:
	var slot := World._axe_slot(draugr)
	if slot < 0:
		return
	var uid: int = World._take_out(draugr, slot)
	var lay := World.put_on_ground(uid, cell)
	World._axes[draugr] = {"uid": uid, "cell": lay, "disarmed": true}


## The counts of [param waves], in order.
func _counts(waves: Array[Dictionary]) -> Array:
	return waves.map(func(w: Dictionary) -> int: return int(w["count"]))


func _test_draugr_waves() -> void:
	print("
== his waves of the dead, the fight's difficulty (603 amended, Jeff): his row's table, today's numbers by default ==")
	var row: Array = Monster.kinds()["draugr"]["waves"]
	_check(row.size() == 3 and float(row[0]["at"]) == 0.75, "his row's waves are read (%d)" % row.size())
	var normal := Draugr.plan_waves(row, "normal", 0, 1)
	var hard := Draugr.plan_waves(row, "hard", 0, 1)
	_check(_counts(normal) == [1, 0, 0] and _counts(hard) == [1, 1, 0] and _counts(Draugr.plan_waves(row, "easy", 0, 1)) == [0, 0, 0],
		"alone: normal's one at three quarters, hard's at three quarters and a half, easy's none (%s, %s)" % [_counts(normal), _counts(hard)])
	_check(_counts(Draugr.plan_waves(row, "normal", 1, 1)) == [1, 1, 0] and _counts(Draugr.plan_waves(row, "normal", 3, 1)) == [2, 1, 1]
		and _counts(Draugr.plan_waves(row, "hard", 3, 1)) == [2, 2, 1],
		"the charges' extra dead each to the wave with fewest, as the pool split them")
	_check(Draugr.plan_waves(row, "hard", 0, 1) == Draugr.plan_waves(Draugr.DEFAULT_WAVES, "hard", 0, 1), "the row's table is the default one")
	var party := [{"at": 0.5, "count": {"normal": 1}, "kinds": ["skeleton", "skeleton_guard"], "per_player": 1},
		{"at": 0.9, "count": {"normal": 0}, "per_player": 0.5}]
	var four := Draugr.plan_waves(party, "normal", 0, 4)
	_check(four[0]["at"] == 0.9 and _counts(four) == [2, 4] and four[1]["kinds"] == ["skeleton", "skeleton_guard"] and four[0]["kinds"] == ["skeleton"],
		"a party of four: per player past the first, earliest wave first, skeletons by default (%s)" % [_counts(four)])
	_check(_counts(Draugr.plan_waves(party, "normal", 0, 1)) == [0, 1], "alone, the same table: only its base")


func _test_room_leash() -> void:
	print("
== a room keeper's leash is its room: the draugr walks to one 17 off at his hall's far end (decision 645; Jeff: \"draugr no longer walks\") ==")
	Monster.idling = true
	var rows: Array[String] = ["######################", "#....................#", "#.u..................#", "#....................#", "######################"]
	Level.register("mt_long", Level.image_from_rows(rows), null, {"regenerate": {"anchors": [{"rect": [1, 1, 20, 3], "name": "lair"}]}})
	var e := _build(rows, {}, {}, "mt_long")
	var draugr := e["u"][0] as Draugr
	draugr.sight_range = 20
	draugr.senses.cone_cos = -1.0
	var player := EntityFactory.build(SPECS["P"].merged({"name": "Player1"})) as Player
	player.player_id = "p1"
	_room.add_child(player)
	World.spawn(player, Vector2i(19, 2))
	World.damage(draugr, 1, player)  # Struck unasked, from his hall's far end.
	var reached := -1
	var gave_up := false
	for i in 200:
		World.step()
		gave_up = gave_up or draugr._returning
		if World.are_adjacent(draugr.tile, player.tile):
			reached = i
			break
	_check(draugr.leash < 17 and reached > 0 and not gave_up,
		"his leash %d, the player 17 off in his room: he walks the whole way, never turning back (beside them at tick %d)" % [draugr.leash, reached])
	Level.unregister("mt_long")


func _test_two_zones_charge() -> void:
	print("
== with another zone awake far ahead, his throw and charge keep his steps on his lair's clock (604 amended, physics; Jeff: \"draugr no longer walks\") ==")
	if not World.has_method("try_axe_charge"):
		print("  (combat's moves not in: skipped)")
		return
	Monster.idling = true
	var rows: Array[String] = ["##############", "#............#", "#............#", "#.....u......#", "#............#", "#............#", "##############"]
	Level.register("mt_far", Level.image_from_rows(rows), null, {"regenerate": {"anchors": [{"rect": [1, 1, 12, 5], "name": "lair"}]}})
	World.clear_zones()
	var lair := World.add_zone("mt_far")
	var other := World.add_zone("mt_other")
	World.enter(other)
	World.load_terrain(Terrain.parse(Terrain.expand(["#####", "#...#", "#####"])))
	var away := EntityFactory.build(SPECS["P"].merged({"name": "Away"})) as Player
	var away_room := Node2D.new()  # Not _room, which _build frees.
	add_child(away_room)
	away_room.add_child(away)
	World.spawn(away, Vector2i(1, 1))
	World.tick = 50000  # The box's overworld, awake since boot.
	World.enter(lair)
	var draugr := _build(rows, {}, {}, "mt_far")["u"][0] as Draugr
	draugr.max_stamina = 100
	draugr.pays_swings = true
	draugr.slots = Items.tidy(["", "", "", "", "", ""], Items.CARRIED)
	draugr.stamina = 100
	draugr.sight_range = 12
	draugr.senses.cone_cos = -1.0
	World.set_slots(draugr, Items.tidy(["", "", "", "", "giant_axe", ""], Items.CARRIED))
	var a := EntityFactory.build(SPECS["P"].merged({"name": "PlayerA"})) as Player
	a.player_id = "pa"
	_room.add_child(a)
	World.spawn(a, Vector2i(12, 3))
	var was_economy := World.economy
	World.economy = Economy.new({"purses": {"pa": 200}})
	draugr.accept_offer(a, draugr.offers_for("pa")[0], 20)
	draugr.target = a
	draugr.next_move_tick = World.tick + 1000  # He holds his ground till he has thrown.
	for i in 30:
		World.step()
		if World.boss_busy(draugr) and draugr._next_throw > World.tick:
			break
	draugr.next_move_tick = World.tick
	var charged := false
	var stepped := false
	var worst := 0
	var at := Vector2i.ZERO
	for i in 200:
		World.step()
		worst = maxi(worst, draugr.next_move_tick - World.tick)
		if str(World.axe_state(draugr)["where"]) == "ground" and World.boss_busy(draugr):
			charged = true
		if charged and not World.boss_busy(draugr) and str(World.axe_state(draugr)["where"]) == "hand":
			if at == Vector2i.ZERO:
				at = draugr.tile
				World._relocate(a, Vector2i(2, 3))  # The player off across his hall.
			elif draugr.tile != at:
				stepped = true
				break
	_check(other.awake and lair.awake and charged, "both zones awake, and he threw and charged for his axe")
	_check(worst <= 30, "his next step never past his lair's clock by more than a step's wait (worst %d ahead; the lair at %d, the other at %d)" % [worst, World.tick, other.tick])
	_check(stepped, "his axe back in hand, the player off across his hall: he walks after them (from %s to %s)" % [at, draugr.tile])
	World.economy = was_economy
	World.dead_rest.clear()
	World._axes.erase(draugr)
	World.clear_zones()
	away_room.free()
	Level.unregister("mt_far")


func _test_hall_waits() -> void:
	print("
== his Hall waits for the first one's companion coming along, up to 5 s; never for one told to wait (573 amended) ==")
	Monster.idling = true
	var rows: Array[String] = ["###############", "#.............#", "#.....u.......#", "#.............#", "#.............#", "###############"]
	Level.register("mt_hall", Level.image_from_rows(rows), null, {"regenerate": {"anchors": [{"rect": [1, 1, 8, 4], "name": "lair"}]}})
	for case in ["coming", "flat", "waits"]:
		var e := _build(rows, {}, {}, "mt_hall")
		var draugr := e["u"][0] as Draugr
		var player := EntityFactory.build(SPECS["P"].merged({"name": "Player1"})) as Player
		player.player_id = "p1"
		_room.add_child(player)
		World.spawn(player, Vector2i(7, 2))
		var pet := EntityFactory.build({"script": "res://sim/companion.gd", "shape": "capsule", "name": "Garrow",
			"props": {"max_hp": 10}}) as Companion
		_room.add_child(pet)
		World.spawn(pet, Vector2i(12, 3))
		pet.keeper = player
		if case == "waits":
			pet.order = "wait"
		var doors: Array = []
		draugr.hall_door.connect(func(open: bool) -> void: doors.append(open))
		var shut_at := -1
		var in_at := -1
		var from := World.tick
		for i in 70:
			if case == "coming":
				_move_to(pet, Vector2i(maxi(12 - i / 3, 8), 3))  # A cell nearer every third tick.
				if in_at < 0 and pet.tile.x <= 8:
					in_at = World.tick - from
			else:
				_move_to(pet, Vector2i(12, 3))
			World.step()
			if shut_at < 0 and draugr.hall_shut:
				shut_at = World.tick - from
		match case:
			"coming":
				_check(in_at > 0 and shut_at >= in_at and shut_at <= in_at + 2 and doors == [false],
					"she comes along 4 off: it waits till she is in (in at %d, shut at %d)" % [in_at, shut_at])
			"flat":
				_check(shut_at >= Draugr.DOOR_WAIT_TICKS and shut_at <= Draugr.DOOR_WAIT_TICKS + 2,
					"she stands 4 off, no farther: it waits its 50 ticks, then shuts (%d)" % shut_at)
			"waits":
				_check(shut_at >= 0 and shut_at <= 2, "she was told to wait: it shuts at once (%d)" % shut_at)
	Level.unregister("mt_hall")


func _test_draugr_mind() -> void:
	print("
== the draugr's mind in his fight (603): crowded he spins, spent he backs off with his dead, one standing off takes the axe, then he charges for it ==")
	if not World.has_method("try_spin"):
		print("  (combat's moves not in: skipped)")
		return
	Monster.idling = true
	var rows: Array[String] = ["##############", "#............#", "#............#", "#.....u......#", "#............#", "#............#", "##############"]
	Level.register("mt_mind", Level.image_from_rows(rows), null, {"regenerate": {"anchors": [{"rect": [1, 1, 12, 5], "name": "lair"}]}})
	var e := _build(rows, {}, {}, "mt_mind")
	var draugr := e["u"][0] as Draugr
	draugr.max_stamina = 100
	draugr.stamina = 100
	draugr.pays_swings = true
	draugr.sight_range = 8
	draugr.senses.cone_cos = -1.0
	draugr.slots = Items.tidy(["", "", "", "", "", ""], Items.CARRIED)
	World.set_slots(draugr, Items.tidy(["", "", "", "", "giant_axe", ""], Items.CARRIED))
	var a := EntityFactory.build(SPECS["P"].merged({"name": "PlayerA"})) as Player
	a.player_id = "pa"
	_room.add_child(a)
	World.spawn(a, Vector2i(5, 3))
	var b := EntityFactory.build(SPECS["P"].merged({"name": "PlayerB"})) as Player
	b.player_id = "pb"
	_room.add_child(b)
	World.spawn(b, Vector2i(6, 2))
	var was_economy := World.economy
	World.economy = Economy.new({"purses": {"pa": 200, "pb": 0}})
	var risen: Array[GridEntity] = []
	World.spawn_spec = func(spec: Dictionary) -> GridEntity:
		var made := EntityFactory.build(spec)
		_room.add_child(made)
		World.spawn(made, spec["tile"])
		risen.append(made)
		return made
	draugr.accept_offer(a, draugr.offers_for("pa")[0], 50)
	draugr.target = a
	var spun := false
	for i in 10:
		World.step()
		if World.boss_busy(draugr) and draugr._next_spin > World.tick:
			spun = true
			break
	_check(spun, "two of them within his sweep: he winds up the spin")
	var backed := false
	for i in 40:
		World.step()
		if draugr.backing_off:
			backed = true
			break
	_check(backed and draugr.stamina <= Draugr.BACK_OFF_STAMINA + 5 and risen.size() == 1,
		"the sweep spends him: he backs off, and his dead (normal's one) rise to cover him (stamina %d, %d risen)" % [draugr.stamina, risen.size()])
	World.dead_rest.clear()

	# One standing off, nobody beside him, his breath back: the throw, then the charge.
	e = _build(rows, {}, {}, "mt_mind")
	draugr = e["u"][0] as Draugr
	draugr.max_stamina = 100
	draugr.stamina = 100
	draugr.pays_swings = true
	draugr.sight_range = 8
	draugr.senses.cone_cos = -1.0
	draugr.slots = Items.tidy(["", "", "", "", "", ""], Items.CARRIED)
	World.set_slots(draugr, Items.tidy(["", "", "", "", "giant_axe", ""], Items.CARRIED))
	a = EntityFactory.build(SPECS["P"].merged({"name": "PlayerA"})) as Player
	a.player_id = "pa"
	_room.add_child(a)
	_move_to(draugr, Vector2i(5, 3))
	World.spawn(a, Vector2i(12, 3))
	draugr.accept_offer(a, draugr.offers_for("pa")[0], 20)
	draugr.target = a
	draugr.next_move_tick = World.tick + 1000  # He holds his ground while it closes.
	World.step()
	_move_to(a, Vector2i(11, 3))
	var threw := false
	for i in Draugr.CLOSING_TICKS:
		World.step()
		threw = threw or World.boss_busy(draugr)
	_check(not threw, "one closing on him, 7 off to 6: no throw (the coordinator's ruling)")
	draugr.next_move_tick = World.tick
	for i in 10:
		World.step()
		if World.boss_busy(draugr) and draugr._next_throw > World.tick:
			threw = true
			break
	_check(threw and World.distance(draugr.tile, a.tile) >= Draugr.THROW_NEAR, "one standing %d off: he winds up the throw" % World.distance(draugr.tile, a.tile))
	var charged := false
	for i in 60:
		World.step()
		if str(World.axe_state(draugr)["where"]) == "ground" and World.boss_busy(draugr):
			charged = true
			break
	_check(charged, "the axe flown and lying: he charges for it")
	if World.has_method("recall_axe"):
		# Disarmed (combat's stopped charge), his axe lying 4 off: he walks back
		# for it, with a foe beside him only after FISTS_BEFORE_AXE blows.
		for i in 200:
			World.step()
			if not World.boss_busy(draugr) and str(World.axe_state(draugr)["where"]) == "hand":
				break
		_move_to(a, Vector2i(12, 1))
		_move_to(draugr, Vector2i(5, 3))
		_disarm(draugr, Vector2i(9, 3))
		draugr.target = a
		var walked := false
		for i in 120:
			World.step()
			if str(World.axe_state(draugr)["where"]) == "hand":
				walked = true
				break
		_check(walked and not World.is_disarmed(draugr) and World.distance(draugr.tile, Vector2i(9, 3)) <= 1,
			"disarmed, nobody beside him: he walks back to his axe and takes it up (%s)" % draugr.tile)
		_move_to(draugr, Vector2i(5, 3))
		_move_to(a, Vector2i(6, 3))
		_disarm(draugr, Vector2i(9, 3))
		draugr._fists = 0
		draugr._fist_seen = -1
		draugr.next_attack_tick = 0
		var stayed := true
		for i in 4:
			World.step()
			stayed = stayed and draugr.tile == Vector2i(5, 3)
		_check(stayed and World.is_disarmed(draugr), "a foe beside him: his fists first, he stays")
		a.hp = a.max_hp
		var went := false
		for i in 200:
			a.hp = a.max_hp
			World.step()
			if draugr.tile != Vector2i(5, 3):
				went = true
				break
		_check(went and draugr._fists >= Draugr.FISTS_BEFORE_AXE,
			"after %d blows of his fists he goes for it, the foe beside him or not (%d blows)" % [Draugr.FISTS_BEFORE_AXE, draugr._fists])
		_disarm(draugr, Vector2i(9, 3))
		draugr._end_pact()
		_check(str(World.axe_state(draugr)["where"]) == "hand" and not World.is_disarmed(draugr), "his fight over, his axe comes back to his hands")
	World.economy = was_economy
	World.spawn_spec = Callable()
	World.dead_rest.clear()
	Level.unregister("mt_mind")


func _test_barrow_layers() -> void:
	print("
== the barrow in layers (580): a hand-drawn lair's own anchors; his rest stills the dead of the zones his level names, asleep or not, and lifts on time ==")
	Monster.idling = true
	var rows: Array[String] = ["##############", "#............#", "#.....u......#", "#............#", "#...........k#", "##############"]
	Level.register("mt_handlair", Level.image_from_rows(rows), null, {"anchors": [{"rect": [1, 1, 9, 4], "name": "lair"}], "stills": ["mt_deep"]})
	var e := _build(rows, {}, {}, "mt_handlair")
	var draugr := e["u"][0] as Draugr
	var skeleton: Monster = e["k"][0]
	_check(Monster.room_of(Vector2i(3, 2)) == Rect2i(1, 1, 9, 4) and Monster.room_of(Vector2i(12, 4)) == Rect2i(),
		"a level drawn by hand: its top-level anchors are its rooms (%s)" % Monster.room_of(Vector2i(3, 2)))
	_check(draugr._in_lair_cell(Vector2i(9, 4)) and not draugr._in_lair_cell(Vector2i(12, 4)), "his lair is that anchor, not a leash circle")
	var player := EntityFactory.build(SPECS["P"].merged({"name": "Player1"})) as Player
	player.player_id = "p1"
	_room.add_child(player)
	World.spawn(player, Vector2i(4, 2))
	var was_economy := World.economy
	World.economy = Economy.new({"purses": {"p1": 100}})
	var risen: Array[GridEntity] = []
	World.spawn_spec = func(spec: Dictionary) -> GridEntity:
		var made := EntityFactory.build(spec)
		_room.add_child(made)
		World.spawn(made, spec["tile"])
		risen.append(made)
		return made
	draugr.accept_offer(player, draugr.offers_for("p1")[0], 100)
	World.damage(draugr, roundi(draugr.max_hp * 0.8), player)  # Past every wave but the last: all hard's dead up.
	var near_seen := true
	for r in risen:
		near_seen = near_seen and World.distance(draugr.tile, r.tile) <= Draugr.RETINUE_REACH and World.has_line_of_sight(draugr.tile, r.tile)
	_check(risen.size() == 2 and near_seen, "hard: two rise within %d of him, in his sight" % Draugr.RETINUE_REACH)
	World.damage(draugr, 9999, player)
	var until := draugr.rests_until
	var side := Monster._factions().of_kind("draugr")
	_check(World.dead_rest.get("mt_handlair", {}).get("until") == until and World.dead_rest.get("mt_deep", {}).get("until") == until
		and World.dead_rest["mt_deep"]["side"] == side, "laid to rest: his rest is laid over his zone and the deep (%s)" % [World.dead_rest])
	World.step()
	_check(skeleton.laid and skeleton.stilled, "his own zone's dead lie still")
	var rest_kept := World.dead_rest.duplicate(true)

	# The deep, another level: its dead lie as they think, his zone asleep or gone.
	Level.register("mt_deep", Level.image_from_rows(["#######", "#.k.x.#", "#######"]), null, {})
	e = _build(["#######", "#.k.x.#", "#######"], {}, {}, "mt_deep")
	World.dead_rest = rest_kept
	var deep: Monster = e["k"][0]
	var robber: Monster = e["x"][0]
	World.steps = until - 10
	World.step()
	_check(deep.laid and deep.stilled and deep.spawn_spec["props"].get("stilled") == true and not robber.laid,
		"in the deep his side's dead lie still, kept in its props; a robber does not")
	World.steps = until
	World.step()
	_check(not deep.laid and not deep.stilled, "his rest run out, the deep's dead rise without him")
	World.dead_rest.clear()
	World.economy = was_economy
	World.spawn_spec = Callable()
	Level.unregister("mt_handlair")
	Level.unregister("mt_deep")

	# The lair's oldest dead: its level's word on them (barrow_lair's "dead").
	var dark_rows: Array[String] = ["#######", "#.k.x.#", "#######"]
	Level.register("mt_dark", Level.image_from_rows(dark_rows), null, {"dead": {"temper": "bold", "sees_in_dark": true, "graves": false}})
	e = _build(dark_rows, {}, {}, "mt_dark")
	var old: Monster = e["k"][0]
	var thief: Monster = e["x"][0]
	_check(old.temper == Monster.Temper.BOLD and old.idle == Monster.Idle.WANDER and old.senses.dark_sight,
		"on a level with a word on its dead: bold, wandering, no grave, seeing in the dark")
	_check(not thief.senses.dark_sight, "a robber there as ever")
	Level.unregister("mt_dark")
	e = _build(dark_rows, {}, {}, "mt_plain")
	_check(e["k"][0].idle == Monster.Idle.HOMEWARD and not e["k"][0].senses.dark_sight, "elsewhere the dead walk home to their graves, and need light")


func _test_wolf_pack_bold() -> void:
	print("
== wolves by day: a pack of 3 lets a hunter be, of 4 it is bold (397 amended) ==")
	Monster.idling = false
	var e := _build(["##############", "#..w.w.w.....#", "#.P..........#", "##############"])
	_outdoors("clear")
	DayNight.set_hour(12.0)
	for i in Animal.PREY_LOOK_TICKS + 2:
		World.step()
	_check(e["w"].all(func(wolf: Animal) -> bool: return not wolf._bold and not wolf.threatens(e["P"][0])), "three by day: none bold")
	e = _build(["##############", "#..w.w.w.w...#", "#.P..........#", "##############"])
	_outdoors("clear")
	DayNight.set_hour(12.0)
	for i in Animal.PREY_LOOK_TICKS + 2:
		World.step()
	_check(e["w"].all(func(wolf: Animal) -> bool: return wolf._bold), "four by day: bold")
	_check(Monster.kinds()["wolf"]["leash"] == 15 and Animal.NIGHT_SIGHT == 1, "it chases 15 from its den, and sees 1 farther at night")
	DayNight.reset()
	_indoors()
	Monster.idling = true
