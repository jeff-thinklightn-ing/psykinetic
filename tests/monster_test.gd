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
	"B": {"script": "res://sim/great_bear.gd", "shape": "capsule", "kind": "great_bear"},
	"G": {"script": "res://sim/old_wolf.gd", "shape": "capsule", "kind": "old_wolf"},
	"K": {"script": "res://sim/boar_king.gd", "shape": "capsule", "kind": "boar_king"},
}
const NAMES := {"P": "Player", "m": "Monster", "i": "Imp", "b": "Brute", "s": "Sneak", "c": "Crate",
	"r": "Rabbit", "d": "Doe", "D": "Stag", "o": "Boar", "w": "Wolf", "a": "Archer", "k": "Skeleton", "g": "Guard",
	"x": "Robber", "u": "Draugr", "B": "Bear", "G": "OldGrey", "K": "BoarKing"}

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
	_test_great_bear()
	_test_bear_party()
	_test_apex_lair()
	_test_bandit_rows()
	_test_chiefs()
	_test_lone_guard()
	_test_ambush_choice()
	_test_band_robbers()
	_test_old_wolf()
	_test_old_wolf_lair()
	_test_apex_heal_fighters()
	_test_watch_wave()
	_test_wanderers()
	_test_hill_cat()
	_test_raid_takes()
	_test_noticing()
	_test_senses()
	_test_crouch()
	_test_wild_kinds()
	_test_wild_prey()
	_test_wild_ears()
	_test_clank()
	_test_band_stands()
	_test_wild_shot_near()
	_test_far_pace()
	_test_strike_cells()
	_test_strike_reach()
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
	_test_balance_wolves()
	_test_deer_hunted()
	_test_archer()
	_test_archer_hold()
	_test_worn_bundles()
	_test_shield()
	_test_monster_bash()
	_test_shield_recoil()
	_test_lowered_shield()
	_test_bash_told()
	_test_sword_beats_guard()
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
	# Each blow on the player is one hurt line (544 amended (2)); nothing else.
	_check(hits > 0 and World.logged == before + hits, "%d blows landed on the player, a door opened, %d log lines (one hurt line a blow)" % [hits, World.logged - before])
	World._set_door(door, false, player)
	_check(World.logged == before + hits + 1, "a player shutting it is logged")


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


## The great bear's tells at reach and its party (780 amended (8)): a free
## body 2 cells off in its reach gets a tell, never a plain blow; each player
## who joins its fight raises its hp, 3 at most; asleep, its base again.
## Decision 793: the bandits' kinds are the grave robbers' rows under their
## own names, drawn as people in a vest; a client without the rows (an older
## build, a kind it has never heard of) draws such a monster plainly: no
## person, no model, no creature, and no error.
func _test_bandit_rows() -> void:
	print("== the bandits' rows (793) ==")
	var kinds := Monster.kinds()
	for pair: Array in [["bandit", "robber"], ["bandit_brute", "robber_brute"]]:
		var row: Dictionary = kinds.get(pair[0], {})
		var like: Dictionary = kinds.get(pair[1], {})
		_check(not row.is_empty() and row.get("body") == like.get("body") and row.get("tactic") == like.get("tactic")
				and row.get("wields") == like.get("wields") and row.get("strength") == like.get("strength"),
			"%s fights as a %s" % pair)
		_check(str(row.get("person", "")).contains("garb=vest") and str(row.get("label", "")).contains("andit"),
			"%s is drawn as a person in a vest and named for a bandit (%s)" % [pair[0], row.get("label", "")])
	var unknown := Monster.new()
	unknown.spawn_spec = {"kind": "kind_never_heard_of"}
	_check(Client3D.person_words(unknown) == "" and Client3D.model_for(unknown).is_empty()
			and Client3D.creature_slot_for(unknown) == "" and Monster.art_of("kind_never_heard_of") == "",
		"a kind a client lacks is drawn plainly")
	unknown.free()


## 790 amended (2): Hollowfell's chiefs, by their named rows.
## Grull holds his post: he takes up no one beyond it and a blow's reach, and
## his leash is the post's, not where he took up the chase. Skeech lurks: a
## player in plain sight is let be until its side engages near it (a blow's
## noise) or it is struck, then it fights; with nobody left it lurks again.
func _test_chiefs() -> void:
	print("
== Hollowfell's chiefs (790 amended): grull holds his post, skeech lurks ==")
	Monster.idling = false
	var grull_row := NamedEnemy.def("grull")
	var skeech_row := NamedEnemy.def("skeech")
	_check(grull_row.get("kind") == "brute" and skeech_row.get("kind") == "sneak"
			and grull_row.get("trophy") == "rot_hammer" and skeech_row.get("trophy") == "rot_spike"
			and not str(grull_row.get("name", "")).to_lower().contains("grull") and not str(skeech_row.get("name", "")).to_lower().contains("skeech"),
		"their rows: an orc brute with the chief's pick-hammer, a kobold sneak with the chief's spike, names off screen (%s, %s)" % [grull_row.get("name"), skeech_row.get("name")])
	var e := _build(["##############", "#............#", "#.b..........#", "#............#", "##############"], {"b": {"named": "grull", "facing": Vector2i(1, 0)}})
	var grull: Monster = e["b"][0]
	var player := EntityFactory.build(SPECS["P"].duplicate(true).merged({"name": "Player1"})) as Player
	_room.add_child(player)
	World.spawn(player, Vector2i(9, 2))
	grull.sight_range = 9
	grull.facing = Vector2i(1, 0)
	_check(grull.holds_post == int(grull_row["holds"]) and grull.leash == grull.holds_post and grull.home == Vector2i(2, 2),
		"grull holds his post (%d cells, home %s)" % [grull.holds_post, grull.home])
	for i in 6:
		World.step()
	_check(grull.target == null, "a player 7 off, in his sight but beyond his post, is not taken up (%s)" % [grull.target])
	_move_to(player, Vector2i(5, 2))
	for i in 6:
		World.step()
	_check(grull.target == player, "3 off, at his post, he is (%s)" % [grull.target])
	_move_to(grull, Vector2i(7, 2))
	_check(grull._beyond_leash(), "5 from his post he is beyond his leash, wherever he took up the chase")
	_move_to(grull, Vector2i(4, 2))
	_check(not grull._beyond_leash(), "2 from it he is not")
	e = _build(["##############", "#............#", "#.s..b.......#", "#............#", "##############"], {"s": {"named": "skeech", "facing": Vector2i(1, 0)}})
	var skeech: Monster = e["s"][0]
	var guard: Monster = e["b"][0]
	player = EntityFactory.build(SPECS["P"].duplicate(true).merged({"name": "Player1"})) as Player
	_room.add_child(player)
	World.spawn(player, Vector2i(6, 2))
	skeech.sight_range = 7
	skeech.facing = Vector2i(1, 0)
	_check(skeech.lurks and skeech.idle == Monster.Idle.GUARD and skeech.lurking(), "skeech lurks, standing where it was put")
	for i in 6:
		World.step()
	_check(skeech.target == null and skeech.tile == Vector2i(2, 2), "a player 4 off in plain sight is let be (%s at %s)" % [skeech.target, skeech.tile])
	World.noise(player.tile, Senses.NOISE_FIGHT, &"fight", guard)
	for i in 6:
		World.step()
	_check(skeech.target == player, "its guard strikes beside it: roused, it takes up the player (%s)" % [skeech.target])
	e = _build(["##############", "#............#", "#.s..........#", "#............#", "##############"], {"s": {"named": "skeech", "facing": Vector2i(1, 0)}})
	skeech = e["s"][0]
	player = EntityFactory.build(SPECS["P"].duplicate(true).merged({"name": "Player1"})) as Player
	_room.add_child(player)
	World.spawn(player, Vector2i(3, 2))
	skeech.note_struck(player)
	_check(not skeech.lurking(), "struck, it lurks no more")
	_test_ambush()
	Monster.idling = true


## The ambush's told cell(s) shown now (790 amended (4)): [] for none.
func _ambush_cells() -> Array:
	for id: int in World.telegraphs():
		var data: Dictionary = World.telegraphs()[id]
		if str(data["kind"]) == "ambush":
			return data["cells"]
	return []


## 790 amended (4): skeech's told strike from behind (enemy-ai chooses when;
## here begun by hand): told and cried, it lands on one who stays, a step
## out of it a miss and an opening, a stun breaks it; the chiefs' hp.
func _test_ambush() -> void:
	var grull_row := NamedEnemy.def("grull")
	var skeech_row := NamedEnemy.def("skeech")
	_check(is_equal_approx(float(grull_row["strength"]["hp"]), 1.2) and is_equal_approx(float(skeech_row["strength"]["hp"]), 1.15),
		"the chiefs make a longer fight of it: hp 1.2 and 1.15 on 823's kinds (%s, %s)" % [grull_row["strength"], skeech_row["strength"]])
	var rows: Array[String] = ["##############", "#............#", "#.s..........#", "#............#", "##############"]
	var e := _build(rows, {"s": {"named": "skeech", "facing": Vector2i(1, 0)}})
	var skeech: Monster = e["s"][0]
	var player := EntityFactory.build(SPECS["P"].duplicate(true).merged({"name": "Player1"})) as Player
	_room.add_child(player)
	World.spawn(player, Vector2i(3, 2))
	_check(int(skeech.ambush.get("windup", 0)) == 8 and int(skeech.ambush.get("damage", 0)) == 5,
		"skeech has the ambush, its row's numbers (%s)" % [skeech.ambush])
	var cries: Array[StringName] = []
	skeech.cried.connect(func(kind: StringName) -> void: cries.append(kind))
	var hp := player.hp
	_check(skeech.begin_ambush(player) and skeech.ambushing(), "begun on the player beside it")
	_check(Vector2i(3, 2) in _ambush_cells().map(func(c: Array) -> Vector2i: return Vector2i(c[0], c[1])),
		"the player's cell told (%s)" % [_ambush_cells()])
	_check(cries.has(&"ambush"), "its cue cried (%s)" % [cries])
	_check(not skeech.begin_ambush(player), "never two at once")
	for i in 7:
		World.tick += 1
		skeech._tend_ambush()
	_check(player.hp == hp and skeech.ambushing(), "held through its windup, nothing struck yet (%d)" % player.hp)
	World.tick += 1
	skeech._tend_ambush()
	_check(player.hp == hp - 5 and _ambush_cells().is_empty(), "the player who stayed: struck for 5, the tell gone (%d of %d)" % [player.hp, hp])
	_check(World.tick >= skeech._ambush_open_until, "struck home: no opening after")
	# A step out of it: a miss, and it stands open.
	e = _build(rows, {"s": {"named": "skeech", "facing": Vector2i(1, 0)}})
	skeech = e["s"][0]
	player = EntityFactory.build(SPECS["P"].duplicate(true).merged({"name": "Player1"})) as Player
	_room.add_child(player)
	World.spawn(player, Vector2i(3, 2))
	hp = player.hp
	_check(skeech.begin_ambush(player), "begun again")
	_move_to(player, Vector2i(3, 3))
	for i in 8:
		World.tick += 1
		skeech._tend_ambush()
	_check(player.hp == hp and skeech.ambushing() and _ambush_cells().is_empty(), "stepped out of it: missed, and it stands open (%d)" % player.hp)
	World.tick += int(skeech.ambush["recover"])
	_check(not skeech.ambushing(), "the opening past: it fights on")
	# A stun in its windup breaks it.
	_check(skeech.begin_ambush(player), "begun a third time")
	skeech.stunned_until_tick = World.tick + 5
	World.tick += 1
	_check(not skeech._tend_ambush() and not skeech.ambushing() and _ambush_cells().is_empty(), "staggered in its windup: broken, nothing told")
	_check(player.hp == hp, "and nothing struck (%d)" % player.hp)
	skeech.stunned_until_tick = 0
	# One with no ambush in its row never begins one.
	e = _build(rows, {"s": {"named": "grull", "facing": Vector2i(1, 0)}})
	player = EntityFactory.build(SPECS["P"].duplicate(true).merged({"name": "Player1"})) as Player
	_room.add_child(player)
	World.spawn(player, Vector2i(3, 2))
	_check(not (e["s"][0] as Monster).begin_ambush(player) and (e["s"][0] as Monster).ambush.is_empty(), "grull has none")
	_test_lunge()
	_test_plain_lead()
	_test_stop_to_strike()
	_test_heavy_cycle()
	_test_sneak_pack()
	_test_aim_struck_cell()
	_test_tell_through_rush()
	_test_boar_king()
	_test_boar_king_close()
	_test_boar_king_far_chase()
	_test_boar_king_rates()
	_test_old_wolf_lunge_line()
	_test_old_wolf_rates()
	_test_boar_king_aim()
	_test_boar_king_tell_through_rush()
	_test_boar_king_lair()
	_test_bold_comes_in()
	_test_given_strength()


func _telegraph_cells(kind: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for id: int in World.telegraphs():
		var data: Dictionary = World.telegraphs()[id]
		if str(data["kind"]) == kind:
			for c: Array in data["cells"]:
				out.append(Vector2i(c[0], c[1]))
	return out


## A robber and a player in a row: the robber at (2,2) facing east, the
## player at (3,2) facing it.
func _lunge_room() -> Array:
	var rows: Array[String] = ["##############", "#............#", "#.x..........#", "#............#", "##############"]
	var e := _build(rows, {"x": {"facing": Vector2i(1, 0)}})
	var robber: Monster = e["x"][0]
	var player := EntityFactory.build(SPECS["P"].duplicate(true).merged({"name": "Player1"})) as Player
	_room.add_child(player)
	World.spawn(player, Vector2i(3, 2))
	player.facing = Vector2i(-1, 0)
	robber.target = player
	return [robber, player]


## 338 amended (4), "blows you can see": a monster's plain blow draws back
## its kind's lead_ticks (3), told as a winding, before it lands; it stands
## through it, and strikes as often as before (the lead comes out of its
## cycle). A step out of reach in the lead spares; lead_ticks 0, at once.
func _test_plain_lead() -> void:
	print("
== 338 amended (4): a monster's plain blow is led ==")
	var rows: Array[String] = ["########", "#......#", "#.kP...#", "#......#", "########"]
	var e := _build(rows)
	var skeleton: Monster = e["k"][0]
	var player: Player = e["P"][0]
	_check(skeleton.lead_ticks == 3, "a skeleton's lead is the fight block's 3 (%d)" % skeleton.lead_ticks)
	_bold(skeleton)
	skeleton.idle = Monster.Idle.NONE  # A crypt skeleton's homeward idle fights only what is in its way.
	skeleton.target = player
	skeleton.next_attack_tick = 0
	var began: Array[int] = []
	var struck: Array[int] = []
	var hp := player.hp
	var at := skeleton.tile
	for i in 40:
		World.step()
		var w := World.winding(skeleton)
		if not w.is_empty() and (began.is_empty() or began[-1] != int(w["began"])):
			began.append(int(w["began"]))
		if player.hp < hp:
			struck.append(World.tick)
			hp = player.hp
	_check(began.size() >= 2 and struck.size() >= 2, "it led and struck more than once (began %s, struck %s)" % [began, struck])
	var led := true
	for k in mini(began.size(), struck.size()):
		led = led and struck[k] - began[k] >= 3 and struck[k] - began[k] <= 4
	_check(led, "each blow lands 3 ticks after it draws back (began %s, struck %s)" % [began, struck])
	_check(skeleton.tile == at, "it stood its ground through them (%s)" % skeleton.tile)
	var cycle := World.attack_ticks_of(skeleton)
	_check(struck.size() >= 2 and struck[1] - struck[0] <= cycle + skeleton.cooldown_spread + 1,
		"as often as before: %d ticks apart, its cycle %d" % [struck[1] - struck[0] if struck.size() >= 2 else -1, cycle])
	# Stepped out of reach in the lead: spared.
	e = _build(rows)
	skeleton = e["k"][0]
	player = e["P"][0]
	_bold(skeleton)
	skeleton.idle = Monster.Idle.NONE  # A crypt skeleton's homeward idle fights only what is in its way.
	skeleton.target = player
	skeleton.next_attack_tick = 0
	hp = player.hp
	for i in 10:
		World.step()
		if not World.winding(skeleton).is_empty():
			break
	_check(not World.winding(skeleton).is_empty(), "drawing back")
	_move_to(player, Vector2i(5, 2))
	World.step()
	World.step()
	World.step()
	_check(player.hp == hp, "stepped out of reach in its lead: spared (%d of %d)" % [player.hp, hp])
	# lead_ticks 0: at once, as before.
	e = _build(rows)
	skeleton = e["k"][0]
	player = e["P"][0]
	skeleton.lead_ticks = 0
	_bold(skeleton)
	skeleton.idle = Monster.Idle.NONE  # A crypt skeleton's homeward idle fights only what is in its way.
	skeleton.target = player
	skeleton.next_attack_tick = 0
	hp = player.hp
	var none := true
	for i in 20:
		World.step()
		none = none and World.winding(skeleton).is_empty()
	_check(none and player.hp < hp, "lead_ticks 0: struck at once, never wound (%d of %d)" % [player.hp, hp])


## 338 amended (4), enemy-ai's side, stop to strike: a monster stands
## settle_ticks where its step brought it before its blow begins, and takes
## no step till strike_recover_ticks after its blow lands, so it is seen to
## stop, strike and stand (combat's numbers, the fight block's 4 and 1).
func _test_stop_to_strike() -> void:
	print("\n== 338 amended (4), enemy-ai's side: stop to strike ==")
	var e := _build(["#########", "#.......#", "#.k..P..#", "#.......#", "#########"])
	var skeleton: Monster = e["k"][0]
	var player: Player = e["P"][0]
	_check(skeleton.strike_recover_ticks == 4 and skeleton.settle_ticks == 1,
		"the fight block's strike_recover_ticks 4 and settle_ticks 1 (%d, %d)" % [skeleton.strike_recover_ticks, skeleton.settle_ticks])
	_bold(skeleton)
	skeleton.idle = Monster.Idle.NONE  # A crypt skeleton's homeward idle fights only what is in its way.
	skeleton.target = player
	skeleton.next_attack_tick = 0
	var stepped := -1
	var began := -1
	var lands := -1
	var at := skeleton.tile
	for i in 60:
		World.step()
		if skeleton.tile != at:
			at = skeleton.tile
			stepped = World.tick
		var w := World.winding(skeleton)
		if not w.is_empty() and began < 0:
			began = int(w["began"])
			lands = int(w["lands"])
			break
	_check(stepped >= 0 and began >= 0, "it came in and drew back (stepped %d, began %d)" % [stepped, began])
	var stood := began - stepped
	_check(stood >= ceili(skeleton.move_ticks) + 1,
		"it stood its step's %d ticks and a settle before drawing back (%d ticks after the step)" % [ceili(skeleton.move_ticks), stood])
	# Its blow landed: the player steps off, and it stands its recover first.
	while World.tick < lands:
		World.step()
	_move_to(player, Vector2i(7, 2))
	var from := skeleton.tile
	var moved := -1
	for i in 30:
		World.step()
		if skeleton.tile != from:
			moved = World.tick
			break
	_check(moved >= lands + 4, "no step till 4 ticks after its blow (landed %d, stepped %d)" % [lands, moved])
	# strike_recover_ticks 0 and settle_ticks 0: as before.
	e = _build(["#########", "#.......#", "#.kP....#", "#.......#", "#########"])
	skeleton = e["k"][0]
	player = e["P"][0]
	skeleton.strike_recover_ticks = 0
	_bold(skeleton)
	skeleton.idle = Monster.Idle.NONE
	skeleton.target = player
	skeleton.next_attack_tick = 0
	lands = -1
	for i in 20:
		World.step()
		var w := World.winding(skeleton)
		if not w.is_empty():
			lands = int(w["lands"])
			break
	while World.tick < lands:
		World.step()
	_check(lands >= 0 and skeleton.next_move_tick < lands + 4,
		"strike_recover_ticks 0: free to step once it lands (next step %d, landed %d)" % [skeleton.next_move_tick, lands])


## 338 amended (5) (combat's numbers): a HEAVY one's own wind-up comes out
## of its cycle, as a lead does: its blows land attack_ticks_of apart, not
## that and its windup_ticks.
func _test_heavy_cycle() -> void:
	print("\n== 338 amended (5): a HEAVY one's wind-up out of its cycle ==")
	var e := _build(["#######", "#.Pb..#", "#######"])
	var brute: Monster = e["b"][0]
	var player: Player = e["P"][0]
	_bold(brute)
	brute.target = player
	brute.next_attack_tick = 0
	var struck: Array[int] = []
	var hp := player.hp
	for i in 80:
		World.step()
		if player.hp < hp:
			struck.append(World.tick)
			hp = player.hp
		if player.hp <= 0:
			break
	var cycle := World.attack_ticks_of(brute)
	var apart := struck[1] - struck[0] if struck.size() >= 2 else -1
	_check(struck.size() >= 2 and brute.tactic == Monster.Tactic.HEAVY and apart <= cycle + brute.cooldown_spread,
		"its blows land %d ticks apart: its cycle %d, not with its windup %d on top (struck %s)" % [apart, cycle, brute.windup_ticks, struck])


## 824, sneak packs: a pack (props "pack" on a kind whose row has a "pack"
## block) wakes as one with one whistle, comes at its target from different
## sides, never more than "in_reach" of it at it at once, and its last one
## flees; the prop on another kind (barrow_deep's grave guards) changes nothing.
func _test_sneak_pack() -> void:
	print("\n== 824: a sneak pack harries from several sides ==")
	var sneak_props: Dictionary = (Level.MONSTER_TYPES["sneak"] as Dictionary).duplicate()
	sneak_props["pack"] = "pack_9_4"
	var skeleton_props: Dictionary = (Level.MONSTER_TYPES["skeleton"] as Dictionary).duplicate()
	skeleton_props["pack"] = "pack_2_2"
	var e := _build(["###############", "#.............#", "#.k...........#", "#.............#", "#...P....s....#",
			"#........s....#", "#.........s...#", "#.............#", "###############"],
			{"s": {"props": sneak_props}, "k": {"props": skeleton_props}})
	var sneaks: Array = e["s"]
	var player: Player = e["P"][0]
	var skeleton: Monster = e["k"][0]
	_check((sneaks[0] as Monster).pack_id == "pack_9_4" and (sneaks[0] as Monster).band_fights
		and int((sneaks[0] as Monster).pack_rules["in_reach"]) == 2,
		"a sneak laid with a pack is of it, its row's rules (%s, %s)" % [(sneaks[0] as Monster).pack_id, (sneaks[0] as Monster).pack_rules])
	_check(skeleton.pack_id == "", "a skeleton laid with the prop is of no pack: its row has no block")
	player.max_hp = 999
	player.hp = 999
	var whistles: Array[StringName] = []
	for s: Monster in sneaks:
		s.cried.connect(func(kind: StringName) -> void: whistles.append(kind))
		s.temper = Monster.Temper.CAUTIOUS
	(sneaks[0] as Monster).sight_range = 8  # Only one sees: the rest take up its fight.
	var woke := -1
	var most_at := 0
	var sides := {}
	for i in 120:
		World.step()
		var fighting := sneaks.filter(func(s: Monster) -> bool: return s.target == player)
		if woke < 0 and fighting.size() == 3:
			woke = World.tick
		var at := 0
		for s: Monster in sneaks:
			if s._in_strike_reach(player):
				at += 1
				var way := Vector2i(signi(s.tile.x - player.tile.x), signi(s.tile.y - player.tile.y))
				sides[way] = true
		most_at = maxi(most_at, at)
	_check(woke >= 0, "the whole pack took up the one's fight (all three by tick %d)" % woke)
	var whistled := whistles.filter(func(kind: StringName) -> bool: return kind == &"whistle").size()
	_check(whistled == 1, "one whistle as it woke (%s)" % [whistles])
	_check(most_at >= 1 and most_at <= 2, "never more than 2 of the pack at it at once (%d)" % most_at)
	_check(sides.size() >= 2, "it came from more than one side (%s)" % [sides.keys()])
	# Two of them down: the last one flees.
	World.despawn(sneaks[1])
	World.despawn(sneaks[2])
	var last: Monster = sneaks[0]
	var fled := false
	for i in 10:
		World.step()
		fled = fled or last.alert == Monster.Alert.FLEEING
	_check(fled, "the last of its pack flees")


## 790 amended (4): the crypt robbers' told lunge, from in front or
## side-on: a line two cells long told before it lands, a step aside spares,
## a step back along it does not, a miss stands it open; from behind its
## plain poke as before; a raised guard still meets it.
func _test_lunge() -> void:
	var pair := _lunge_room()
	var robber: Monster = pair[0]
	var player: Player = pair[1]
	_check(int(robber.lunge.get("windup", 0)) == 6 and int(robber.lunge.get("damage", 0)) == 3 and int(robber.lunge.get("reach", 0)) == 2,
		"the robber has its row's lunge (%s)" % [robber.lunge])
	var hp := player.hp
	_check(robber.begin_lunge(player) and robber.ambushing(), "begun on the player in front")
	var told := _telegraph_cells("lunge")
	_check(Vector2i(3, 2) in told and Vector2i(4, 2) in told and not Vector2i(2, 2) in told,
		"its line told, two cells, not its own (%s)" % [told])
	_check(not robber.begin_lunge(player) and not robber.begin_ambush(player), "never two at once")
	for i in 5:
		World.tick += 1
		robber._tend_ambush()
	_check(player.hp == hp and robber.ambushing(), "held through its windup (%d)" % player.hp)
	World.tick += 1
	robber._tend_ambush()
	_check(player.hp == hp - 3 and _telegraph_cells("lunge").is_empty(), "stayed: struck for 3, the tell gone (%d of %d)" % [player.hp, hp])
	_check(World.tick >= robber._ambush_open_until and World.tick < robber.next_attack_tick, "struck home: no opening, its next blow later")
	# A step back along the line is still struck.
	pair = _lunge_room()
	robber = pair[0]
	player = pair[1]
	hp = player.hp
	_check(robber.begin_lunge(player), "begun again")
	_move_to(player, Vector2i(4, 2))
	for i in 6:
		World.tick += 1
		robber._tend_ambush()
	_check(player.hp == hp - 3, "a step back along it: still struck (%d of %d)" % [player.hp, hp])
	# A step aside: missed, and it stands open.
	pair = _lunge_room()
	robber = pair[0]
	player = pair[1]
	hp = player.hp
	_check(robber.begin_lunge(player), "begun a third time")
	_move_to(player, Vector2i(3, 3))
	for i in 6:
		World.tick += 1
		robber._tend_ambush()
	_check(player.hp == hp and robber.ambushing(), "a step aside: missed, and it stands open (%d)" % player.hp)
	World.tick += int(robber.lunge["recover"])
	_check(not robber.ambushing(), "the opening past: it fights on")
	# Its blow from in front is told; from behind, its poke as before.
	pair = _lunge_room()
	robber = pair[0]
	player = pair[1]
	robber._strike()
	_check(robber.ambushing() and not _telegraph_cells("lunge").is_empty(), "its blow from in front: a told lunge")
	pair = _lunge_room()
	robber = pair[0]
	player = pair[1]
	player.facing = Vector2i(1, 0)
	robber._strike()
	_check(not robber.ambushing() and _telegraph_cells("lunge").is_empty(), "from behind: its plain poke, untold")
	# A raised shield facing it still takes it.
	pair = _lunge_room()
	robber = pair[0]
	player = pair[1]
	player.slots[Items.LEFT_HAND] = "shield"
	player.raised = "block"
	player.stamina = player.max_stamina
	hp = player.hp
	_check(robber.begin_lunge(player), "begun on a raised shield")
	for i in 6:
		World.tick += 1
		robber._tend_ambush()
	_check(player.hp == hp, "the shield took it (%d of %d)" % [player.hp, hp])
	_check(World.is_stunned(robber) and robber.stun_cause == &"guarded" and robber.stunned_until_tick - World.tick <= World.SHIELD_RECOIL_STUN
			and player.raised == "block",
			"340 amended: the robber thrown back off it, &\"guarded\" (%s, %d ticks left)" % [robber.stun_cause, robber.stunned_until_tick - World.tick])
	# A kind with no lunge never begins one.
	var e := _build(["#######", "#.sP..#", "#######"])
	_check(not (e["s"][0] as Monster).begin_lunge(e["P"][0]) and (e["s"][0] as Monster).lunge.is_empty(), "a sneak has none")


## 716 amended: a row's given strength past the rolled spans (a chief's),
## and winning over a record made before the tune; a rolled one kept.
func _test_given_strength() -> void:
	var rows: Array[String] = ["##############", "#............#", "#.s....b.....#", "#............#", "##############"]
	var e := _build(rows)
	var sneak_hp: int = (e["s"][0] as Monster).max_hp
	var brute_hp: int = (e["b"][0] as Monster).max_hp
	e = _build(rows, {"s": {"named": "skeech"}, "b": {"named": "grull"}})
	var skeech: Monster = e["s"][0]
	var grull: Monster = e["b"][0]
	_check(skeech.max_hp == roundi(sneak_hp * 1.15) and grull.max_hp == roundi(brute_hp * 1.2),
		"the chiefs as spawned: skeech %d (a sneak's %d x 1.15), grull %d (a brute's %d x 1.2; 823)" % [skeech.max_hp, sneak_hp, grull.max_hp, brute_hp])
	# A record made before the tune (the box's, from v0.1.206): its strength
	# taken from the row at the next spawn, the rest of it kept.
	var plain := EntityFactory.build(SPECS["s"].duplicate(true).merged({"name": "Sneak6"})) as Monster
	_room.add_child(plain)
	World.spawn(plain, Vector2i(9, 3))
	var built_hp := plain.max_hp  # Built here, not through _build: its own base.
	var record: Dictionary = World.named["skeech"]
	record["strength"] = {"hp": 1.2, "damage": 1.2, "speed": 1.1}
	record["lives"] = 3
	record["card"] = {"seen": "Player1"}
	var again := EntityFactory.build(SPECS["s"].duplicate(true).merged({"name": "Sneak9", "named": "skeech"})) as Monster
	_room.add_child(again)
	World.spawn(again, Vector2i(10, 1))
	_check(again.max_hp == roundi(built_hp * 1.15) and is_equal_approx(float(World.named["skeech"]["strength"]["hp"]), 1.15),
		"an older record's strength: the row's at the next spawn (%d, %s)" % [again.max_hp, World.named["skeech"]["strength"]])
	_check(int(World.named["skeech"]["lives"]) == 3 and World.named["skeech"]["card"] == {"seen": "Player1"} and str(World.named["skeech"]["name"]) == "Kobold chief",
		"and nothing else of the record touched (%s)" % [World.named["skeech"]])
	_check(is_equal_approx(NamedEnemy.given_strength("grull")["hp"], 1.2) and NamedEnemy.GIVEN_SPANS["hp"][1] > NamedEnemy.STRENGTH_SPANS["hp"][1],
		"a given strength is the row's, and may pass the rolled spans (823: grull's 1.2 within them)")
	# A rolled strength stays as it rolled.
	NamedEnemy.define_for_test("test_rolled", {"name": "Rolled One", "kind": "sneak"})
	var rolled := EntityFactory.build(SPECS["s"].duplicate(true).merged({"name": "Sneak8", "named": "test_rolled"})) as Monster
	_room.add_child(rolled)
	World.spawn(rolled, Vector2i(11, 1))
	var first := float(World.named["test_rolled"]["strength"]["hp"])
	_check(first >= 0.8 and first <= 1.6 and NamedEnemy.given_strength("test_rolled").is_empty(), "a row with none: rolled in the spans (%.2f)" % first)
	World.named["test_rolled"]["strength"]["hp"] = 0.9
	var rolled2 := EntityFactory.build(SPECS["s"].duplicate(true).merged({"name": "Sneak7", "named": "test_rolled"})) as Monster
	_room.add_child(rolled2)
	World.spawn(rolled2, Vector2i(12, 1))
	_check(rolled2.max_hp == roundi(built_hp * 0.9), "its stored strength kept at the next spawn (%d)" % rolled2.max_hp)
	NamedEnemy.reset_for_test()  # The test row gone; the file's read again.


## A lone guard's standoff (806 amended (8); companions' barrow find: a timid
## robber on a cache's post, its band dead, held back FIGHTING for minutes).
func _test_lone_guard() -> void:
	print("\n== a lone guard never hangs: it presses in near its post, or watches from it ==")
	var room: Array[String] = ["##################", "#................#", "#.x..............#", "#................#", "##################"]
	var guard_spec := {"x": {"idle": {"mode": "guard"}, "facing": Vector2i(1, 0)}}
	var e := _build(room, guard_spec)
	var robber: Monster = e["x"][0]
	var post := robber.tile
	robber.boldness = 0.05  # Timid: it holds back alone.
	robber.temper = Monster.Temper.CAUTIOUS
	robber.sight_range = 9
	var player := EntityFactory.build(SPECS["P"].duplicate(true).merged({"name": "Player1"})) as Player
	_room.add_child(player)
	World.spawn(player, post + Vector2i(3, 0))
	var struck_at := -1
	var start := World.tick
	for i in 200:
		World.step()
		if struck_at < 0 and _damage_log.any(func(d: Dictionary) -> bool: return d["entity"] == player and d["source"] == robber):
			struck_at = World.tick
			break
	_check(struck_at >= 0 and struck_at - start <= 90,
		"a player 3 from its post: alone, it comes in and strikes (806 amended (9); %d ticks)" % [struck_at - start])
	World.despawn(player)
	var home_at := -1
	for i in 300:
		World.step()
		if robber.tile == post and robber.target == null:
			home_at = World.tick
			break
	_check(home_at >= 0 and robber.alert != Monster.Alert.FIGHTING, "the player gone, it goes back to its post (%s, alert %d)" % [robber.tile, robber.alert])

	# Sealed off by crates (no way in), 3 from its post and in its sight.
	var sealed: Array[String] = ["##################", "#...c............#", "#.x.c............#", "#...c............#", "##################"]
	e = _build(sealed, guard_spec)
	robber = e["x"][0]
	post = robber.tile
	robber.boldness = 0.05
	robber.temper = Monster.Temper.CAUTIOUS
	robber.sight_range = 9
	player = EntityFactory.build(SPECS["P"].duplicate(true).merged({"name": "Player1"})) as Player
	_room.add_child(player)
	World.spawn(player, post + Vector2i(3, 0))
	var fought := false
	var watched_at := -1
	start = World.tick
	for i in 150:
		World.step()
		fought = fought or robber.alert == Monster.Alert.FIGHTING
		if fought and robber.alert != Monster.Alert.FIGHTING and robber.target == null:
			watched_at = World.tick
			break
	_check(fought and watched_at >= 0 and watched_at - start <= 80 and not robber._pressing and robber._watched >= 0,
		"no way in: it stops fighting within about 6 s and watches, not pressing (%d ticks)" % [watched_at - start])
	for i in 30:
		World.step()
	var way := Senses.way_toward(robber.tile, player.tile)
	_check(robber.tile == post and robber.target == null and robber.alert != Monster.Alert.FIGHTING and robber.facing == way,
		"at its post it watches them, facing them, 3 s on (%s facing %s, alert %d)" % [robber.tile, robber.facing, robber.alert])
	robber.note_struck(player)
	for i in 6:
		World.step()
	_check(robber.target == player, "watching, a blow rouses it (%s)" % [robber.target])

	e = _build(room, guard_spec)
	robber = e["x"][0]
	post = robber.tile
	robber.boldness = 0.05
	robber.temper = Monster.Temper.CAUTIOUS
	robber.sight_range = 9
	player = EntityFactory.build(SPECS["P"].duplicate(true).merged({"name": "Player1"})) as Player
	_room.add_child(player)
	World.spawn(player, post + Vector2i(8, 0))
	robber._watch(player)
	for i in 10:
		World.step()
	_check(robber.target == null, "watched, 8 from its post, the player is let be (%s)" % [robber.target])
	_move_to(player, post + Vector2i(4, 0))
	for i in 10:
		World.step()
	_check(robber.target == null, "4 from its post, still let be (%s)" % [robber.target])
	_move_to(player, post + Vector2i(2, 0))
	for i in 10:
		World.step()
	_check(robber.target == player, "2 from its post it takes them up again (%s)" % [robber.target])


## The crypt's robbers fight right (806 amended (9); Jeff: "fighting the
## robbers is not great right now"): alone, one comes in and strikes from the
## front; it goes round only while a mate holds the front, and never the long
## way round a sarcophagus; hurt, it runs only to call a mate, and comes back.
func _test_band_robbers() -> void:
	print("\n== the crypt's robbers fight right: alone straight in, round only with a mate, run only to call ==")
	var weights: Dictionary = Monster.kinds()["robber"]["temperament"]
	_check(weights[Monster.Temper.BOLD] == 1.0 and weights[Monster.Temper.CAUTIOUS] == 2.0 and weights[Monster.Temper.COWARDLY] == 0.0
			and bool(Monster.kinds()["robber"]["band_fights"]) and not bool(Monster.kinds()["sneak"]["band_fights"]),
		"the robber's temper roll is bold 1, cautious 2, cowardly 0, and it fights as a band (%s)" % [weights])
	var room: Array[String] = ["############", "#..........#", "#.x...P....#", "#..........#", "############"]
	var e := _build(room, {"x": {"facing": Vector2i(1, 0)}})
	var robber: Monster = e["x"][0]
	var player: GridEntity = e["P"][0]
	World.face(player, Vector2i(-1, 0))
	robber.sight_range = 9  # A lit crypt: it sees them.
	robber.boldness = 0.05  # Timid: it held back alone before.
	robber.temper = Monster.Temper.CAUTIOUS
	var struck_at := -1
	var start := World.tick
	var went_round := false
	for i in 120:
		World.step()
		went_round = went_round or robber._front_ticks > 0
		if _damage_log.any(func(d: Dictionary) -> bool: return d["entity"] == player and d["source"] == robber):
			struck_at = World.tick
			break
	_check(struck_at >= 0 and struck_at - start <= 45 and not went_round and robber._in_front(),
		"alone, a timid robber comes straight in and strikes from the front (%d ticks, went round %s)" % [struck_at - start, went_round])

	# A crypt's sarcophagi: the player's back is only the long way round.
	var crypt: Array[String] = ["############", "#..........#", "#.x...####.#", "#...xP.....#", "#.....####.#", "#..........#", "############"]
	e = _build(crypt, {"x": {"facing": Vector2i(1, 0)}})
	var flanker: Monster = e["x"][0]
	var mate: Monster = e["x"][1]
	player = e["P"][0]
	World.face(player, Vector2i(-1, 0))
	flanker.target = player
	mate.target = player
	_check(flanker._flanks_now(), "with a mate beside the player, it may go round (%s)" % [mate.tile])
	var picked := flanker._pick_slot()
	flanker.slot = picked
	_check(picked.x < player.tile.x and World.are_adjacent(picked, player.tile),
		"but the way to the player's back is long round the sarcophagi: the nearest free cell (%s)" % [picked])
	var open: Array[String] = ["############", "#..........#", "#.x........#", "#...xP.....#", "#..........#", "#..........#", "############"]
	e = _build(open, {"x": {"facing": Vector2i(1, 0)}})
	flanker = e["x"][0]
	mate = e["x"][1]
	player = e["P"][0]
	World.face(player, Vector2i(-1, 0))
	flanker.target = player
	mate.target = player
	picked = flanker._pick_slot()
	_check(picked.x > player.tile.x - 1 and picked != mate.tile,
		"in the open, with a mate in front, it makes for the player's side or back (%s)" % [picked])
	World.despawn(mate)
	flanker.slot = Monster.NO_TILE
	_check(not flanker._flanks_now(), "its mate gone, it no longer goes round")

	# Hurt, with a mate in the crypt: it runs to call, and comes back.
	e = _build(room, {"x": {"facing": Vector2i(1, 0)}})
	robber = e["x"][0]
	player = e["P"][0]
	var far_mate := EntityFactory.build(SPECS["x"].duplicate(true).merged({"name": "Mate"})) as Monster
	_room.add_child(far_mate)
	World.spawn(far_mate, Vector2i(10, 3))
	robber.sight_range = 9
	robber.temper = Monster.Temper.CAUTIOUS
	robber.hp = 3  # Under its flee_below (0.35 of 10).
	var cries: Array[StringName] = []
	robber.cried.connect(func(kind: StringName) -> void: cries.append(kind))
	var ran := false
	for i in 40:
		World.step()
		if robber.alert == Monster.Alert.FLEEING:
			ran = true
			break
	_check(ran and cries.has(&"call") and not cries.has(&"rout") and robber._ran_to_call,
		"hurt, with a mate, it runs to call its band, never a rout (%s)" % [cries])
	var back := false
	for i in 200:
		World.step()
		if robber.target == player and robber.alert == Monster.Alert.FIGHTING:
			back = true
			break
	_check(back, "it comes back to fight (%s, alert %d)" % [robber.target, robber.alert])
	var ran_again := false
	for i in 80:
		World.step()
		ran_again = ran_again or robber.alert == Monster.Alert.FLEEING
	_check(not ran_again, "and fights on: it runs once a fight")

	# Hurt and alone: it never runs.
	e = _build(room, {"x": {"facing": Vector2i(1, 0)}})
	robber = e["x"][0]
	player = e["P"][0]
	robber.sight_range = 9
	robber.temper = Monster.Temper.CAUTIOUS
	robber.hp = 3
	ran = false
	struck_at = -1
	for i in 80:
		World.step()
		ran = ran or robber.alert == Monster.Alert.FLEEING
		if _damage_log.any(func(d: Dictionary) -> bool: return d["entity"] == player and d["source"] == robber):
			struck_at = World.tick
			break
	_check(not ran and struck_at >= 0, "hurt with no mate left, it never runs: it fights (struck %s)" % [struck_at >= 0])


## Skeech chooses his told strike (790 amended (4), enemy-ai's side): once a
## lurk-break, on his first blow from behind; never two; lurking again re-arms it.
func _test_ambush_choice() -> void:
	print("
== skeech's told strike: once a lurk-break, on his first blow from behind ==")
	var rows: Array[String] = ["##############", "#............#", "#.s.....b....#", "#............#", "##############"]
	var e := _build(rows, {"s": {"named": "skeech", "facing": Vector2i(1, 0)}})
	var guard: Monster = e["b"][0]
	var skeech: Monster = e["s"][0]
	var player := EntityFactory.build(SPECS["P"].duplicate(true).merged({"name": "Player1"})) as Player
	_room.add_child(player)
	World.spawn(player, Vector2i(4, 2))
	World.face(player, Vector2i(1, 0))  # Its back to him.
	var cries: Array[StringName] = []
	skeech.cried.connect(func(kind: StringName) -> void: cries.append(kind))
	_check(skeech.lurking() and skeech._ambush_armed, "lurking, his told strike armed")
	skeech.sight_range = 7
	for i in 6:
		World.step()
	World.noise(player.tile, Senses.NOISE_FIGHT, &"fight", guard)  # His side fights beside him.
	var plain := 0
	var hp := player.hp
	for i in 300:
		World.face(player, Vector2i(1, 0))
		World.step()
	for d: Dictionary in _damage_log:
		if d["entity"] == player and d["source"] == skeech and d["cause"] != &"ambush":
			plain += 1
	_check(cries.count(&"ambush") == 1 and not skeech._ambush_armed,
		"roused, his first blow from behind is the told strike, and only one (%d cues; %s at %s, target %s, alert %d, player at %s)" % [cries.count(&"ambush"), skeech.name, skeech.tile, skeech.target, skeech.alert, player.tile])
	_check(plain >= 1 and player.hp < hp, "his blows after it are his plain ones (%d)" % plain)
	World.despawn(player)
	for i in 400:
		World.step()
		if skeech.lurking():
			break
	World.step()
	_check(skeech.lurking() and skeech._ambush_armed, "nobody left, he lurks again, armed again")


## The lair rule (780 amended (13)): the great bear in its lair, out in its
## land, back, dead and risen, between two zones.
func _test_apex_lair() -> void:
	print("
== an apex in its lair and its land: laid at its den, out unattacked, beaten back through its door, dead its rise ==")
	# The real places: the den, the doors either side, the roaming grounds.
	Apex.clear()
	var real_row: Dictionary = Monster.kinds()["great_bear"]["lair"]
	var real := Apex._places_of("great_bear", real_row)
	var roads := Level.safe_paths(Level.load_level("hills")["terrain"])
	var clear_of_roads := (real.get("roam", []) as Array).all(func(cell: Vector2i) -> bool:
		for path: Vector2i in roads:
			if maxi(absi(path.x - cell.x), absi(path.y - cell.y)) <= int(real_row["path_margin"]):
				return false
		return true)
	_check(real.get("den") == Vector2i(6, 7) and real.get("lair_door") == Vector2i(4, 24) and real.get("land_door") == Vector2i(117, 104)
			and (real.get("roam", []) as Array).size() > 20 and clear_of_roads,
			"its den in bear_cave, the doors either side, and %d roaming grounds in the hills, every one off the safe paths" % (real.get("roam", []) as Array).size())
	_check(Apex.holds_marker({"spawn": 0, "kind": "great_bear"}, "bear_cave") and not Apex.holds_marker({"spawn": 0, "kind": "great_bear"}, "bear_yard")
			and not Apex.holds_marker({"kind": "great_bear"}, "bear_cave") and not Apex.holds_marker({"spawn": 0, "kind": "wolf"}, "bear_cave"),
			"its marker in its lair is its den, never a level entity; in the bear yard it is")
	# Two zones of our own: the land (here) and the lair.
	var land_rows: Array[String] = ["#".repeat(40)]
	for y in 8:
		land_rows.append("#" + ".".repeat(38) + "#")
	land_rows.append("#".repeat(40))
	_build(land_rows, {}, {}, "ap_land")
	World.spawn_spec = func(spec: Dictionary) -> GridEntity:
		var entity := EntityFactory.build(spec)
		_room.add_child(entity)
		if not World.spawn(entity, spec["tile"]):
			entity.free()
			return null
		return entity
	var land := World.zone
	World.zones[land.name] = land
	var lair := World.add_zone("ap_lair")
	World.enter(lair)
	var lair_rows: Array[String] = ["#".repeat(20)]
	for y in 8:
		lair_rows.append("#" + ".".repeat(18) + "#")
	lair_rows.append("#".repeat(20))
	World.load_terrain(Terrain.parse(Terrain.expand(lair_rows)))
	World.enter(land)
	var kinds := Monster.kinds()
	var row_was: Dictionary = kinds["great_bear"]["lair"]
	var row: Dictionary = row_was.duplicate(true)
	row["zone"] = "ap_lair"
	row["land"] = ["ap_land"]
	kinds["great_bear"]["lair"] = row
	Apex.clear()
	World.apexes.clear()
	Apex._places["great_bear"] = {"den": Vector2i(14, 4), "lair_door": Vector2i(2, 4), "land_door": Vector2i(3, 4),
			"roam": [Vector2i(30, 4)] as Array[Vector2i]}
	DayNight.set_hour(12.0)
	var idling_was := Monster.idling
	Monster.idling = true
	var keeper := EntityFactory.build(SPECS["P"].merged({"name": "LairKeeper"})) as Player
	_room.add_child(keeper)
	World.enter(lair)
	World.spawn(keeper, Vector2i(2, 7))
	World.enter(land)
	Apex._check("great_bear", row)
	var bear := Apex.body_of("great_bear")
	var rec := Apex.record("great_bear")
	_check(bear != null and bear.zone == "ap_lair" and bear.tile == Vector2i(14, 4) and rec["state"] == "lair" and bear.hp == bear.max_hp,
		"in its lair, its zone awake: laid at its den, whole (%s)" % [rec])
	# Unattacked its wait, by day, nobody seeing it: out at once.
	World.enter(lair)
	World.despawn(keeper)
	World.enter(land)
	var walker := EntityFactory.build(SPECS["P"].merged({"name": "LandWalker"})) as Player
	_room.add_child(walker)
	World.spawn(walker, Vector2i(36, 8))
	rec["attacked"] = World.steps - Apex._steps(row, "venture_after_s", 1800.0)
	Apex._check("great_bear", row)
	_check(rec["state"] == "out" and (not is_instance_valid(bear) or not (bear as Monster).spawned), "unattacked its wait, by day, unseen: gone from its lair (%s)" % [rec["state"]])
	Apex._check("great_bear", row)
	bear = Apex.body_of("great_bear")
	_check(bear != null and bear.zone == "ap_land" and World.distance(bear.tile, Vector2i(3, 4)) <= 1 and (bear as GreatBear).apex_out
		and bear.home == Vector2i(30, 4), "out of its door in its land, off to roam its ground (%s)" % [bear.home if bear != null else null])
	for i in 120:
		World.step()
	_check(World.distance(bear.tile, Vector2i(30, 4)) <= 8 and not (bear as GreatBear).asleep, "it walks out to its ground and roams there (%s)" % bear.tile)
	# Beaten back, seen: it walks to its door, then is in its lair.
	World.despawn(walker)
	World.spawn(walker, bear.tile + Vector2i(-3, 0))
	bear.hp = roundi(bear.max_hp * 0.3)
	var hurt := bear.hp
	Apex._check("great_bear", row)
	_check((bear as GreatBear).apex_goal == Vector2i(3, 4) and rec["state"] == "out", "beaten down, seen: it makes for its door")
	for i in 400:
		World.step()
		if rec["state"] == "lair":
			break
	_check(rec["state"] == "lair" and not (is_instance_valid(bear) and bear.spawned) and int(rec["hp"]) == hurt,
		"at its door it is gone into its lair (%s, hp kept %d)" % [rec["state"], int(rec["hp"])])
	# In its lair again (a player there), struck on its way out: it stays.
	World.enter(lair)
	World.spawn(keeper, Vector2i(10, 4))
	World.enter(land)
	Apex._check("great_bear", row)
	bear = Apex.body_of("great_bear")
	_check(bear != null and bear.zone == "ap_lair", "back in its lair, laid at its den")
	rec["attacked"] = World.steps - Apex._steps(row, "venture_after_s", 1800.0)
	Apex._check("great_bear", row)
	_check(bear != null and (bear as GreatBear).apex_goal == Vector2i(2, 4), "its wait out, a player in its lair sees it go to its door")
	Apex.struck(bear)
	Apex._check("great_bear", row)
	_check(rec["state"] == "lair" and (bear as GreatBear).apex_goal == Monster.NO_TILE and bear.spawned, "struck on its way, it stays")
	# Killed: dead its rise, then in its lair.
	World.enter(lair)
	World.damage(bear, bear.hp + 10)
	World.enter(land)
	_check(rec["state"] == "dead" and int(rec["dead_until"]) == World.steps + Apex._steps(row, "rise_s", 1800.0),
		"killed: dead its rise_s (%s)" % [rec])
	Apex._check("great_bear", row)
	_check(rec["state"] == "dead", "and dead till then")
	rec["dead_until"] = World.steps
	Apex._check("great_bear", row)
	_check(rec["state"] == "lair", "then in its lair again")
	World.enter(lair)
	World.despawn(keeper)
	World.enter(land)
	World.despawn(walker)
	kinds["great_bear"]["lair"] = row_was
	Apex.clear()
	World.apexes.clear()
	World.zones.erase("ap_lair")
	World.zones.erase("ap_land")
	World.enter(land)
	Monster.idling = idling_was
	World.spawn_spec = Callable()


func _test_bear_party() -> void:
	print("
== the great bear: every blow told, a free body 2 off in reach too; its hp grows by who joins its fight, 3 at most ==")
	Monster.idling = false
	DayNight.set_hour(12.0)
	var rows: Array[String] = ["#".repeat(40)]
	for y in 5:
		rows.append("#" + ".".repeat(38) + "#")
	rows.append("#".repeat(40))
	var row := rows[3]
	rows[3] = row.substr(0, 4) + "B" + row.substr(5)
	var e := _build(rows)
	var bear: GreatBear = e["B"][0]
	bear.sight_range = 8
	bear._next_swipe = World.tick + 100000
	bear._next_slam = World.tick + 100000
	bear._next_charge = World.tick + 100000
	var hunters: Array[GridEntity] = []
	for i in 4:
		var each := EntityFactory.build(SPECS["P"].merged({"name": "PartyHunter%d" % i})) as GridEntity
		_room.add_child(each)
		World.spawn(each, Vector2i(6 + 2 * i, 3 if i == 0 else 1))
		hunters.append(each)
	var near := hunters[0]
	near.free_pos = Vector2(bear.tile) + Vector2(1.4, 0.0)  # Its tile kept 2 off (FREE_HYSTERESIS), its body in the bear's reach.
	_check(World.distance(bear.tile, near.tile) == 2 and World.in_reach(bear, near),
			"a free body 2 cells off, its centre 1.4 away: in the bear's reach")
	World.damage(bear, 1, near)
	var before := near.hp
	for i in 40:
		World.step()
	_check(near.hp == before and bear.party_size == 1 and bear.max_hp == bear._base_hp,
			"its swipe and slam held back, it stands: no plain blow at reach (%d hp lost); one in the fight, its base %d hp" % [before - near.hp, bear.max_hp])
	var tells := func(kind: String) -> Array:
		return World.telegraphs().values().filter(func(t: Dictionary) -> bool: return t["kind"] == kind and t["source"] == str(bear.get_path()))
	bear._next_swipe = 0
	var told := false
	for i in 10:
		World.step()
		if not tells.call("swipe").is_empty():
			told = true
			break
	_check(told, "its swipe ready: a tell at the free body 2 off, as at one beside it")
	_check(bear.party.get("flank_guard_per_player") == 25.0 and bear.party.get("most") == 3.0 and Monster.kinds()["great_bear"]["party"] is Dictionary,
			"its party block as its row has it, all of it (combat's flank guard reads it: %s)" % [bear.party])
	var base: int = bear._base_hp
	var share := float(bear.hp) / float(bear.max_hp)
	World.damage(bear, 1, hunters[1])
	var two := bear.max_hp
	World.damage(bear, 1, hunters[2])
	var three := bear.max_hp
	World.damage(bear, 1, hunters[3])
	World.damage(bear, 1, near)
	var per := float(bear.party["hp_per_player"])
	_check(two == roundi(base * (1.0 + per)) and three == roundi(base * (1.0 + 2.0 * per)) and bear.max_hp == three and bear.party_size == 3,
			"each who strikes it joins its fight: %d, %d, then %d for a fourth and a second blow (3 at most; hp_per_player %s)" % [two, three, bear.max_hp, per])
	_check(absf(float(bear.hp) / float(bear.max_hp) - share) < 0.05, "its hp kept in the same share as it grows (%d/%d)" % [bear.hp, bear.max_hp])
	bear._sleep()
	_check(bear.party_size == 1 and bear.max_hp == base and bear.hp <= base, "asleep: its base again (%d/%d)" % [bear.hp, bear.max_hp])
	# 780 amended (10): a companion who joins counts companion_share of a player; party_size stays the players.
	bear.asleep = false
	var cshare := float(bear.party["companion_share"])
	var kin := EntityFactory.build({"script": "res://sim/companion.gd", "shape": "capsule", "name": "BearKin",
		"props": {"max_hp": 10}}) as Companion
	_room.add_child(kin)
	World.spawn(kin, Vector2i(6, 5))
	World.damage(bear, 1, near)
	World.damage(bear, 1, kin)
	World.damage(bear, 1, kin)
	_check(cshare == 0.75 and bear.party_size == 1 and bear.companions == 1 and bear.max_hp == roundi(base * (1.0 + per * cshare)),
			"a player and a companion in its fight: party %d, companions %d, %d hp (companion_share %s)" % [bear.party_size, bear.companions, bear.max_hp, cshare])
	World.damage(bear, 1, hunters[1])
	_check(bear.party_size == 2 and bear.companions == 1 and bear.max_hp == roundi(base * (1.0 + per * (1.0 + cshare))),
			"a second player: party 2, the companion still counted (%d hp)" % bear.max_hp)
	bear._sleep()
	_check(bear.party_size == 1 and bear.companions == 0 and bear.max_hp == base, "asleep: companions forgotten too (%d)" % bear.max_hp)
	World.despawn(kin)
	# playtest's bear14E: one who leaves and comes back (a new body, the same player_id) is still one.
	bear.asleep = false
	var first := EntityFactory.build(SPECS["P"].merged({"name": "PartyBack"})) as GridEntity
	(first as Player).player_id = "party_back"
	_room.add_child(first)
	World.spawn(first, Vector2i(12, 5))
	World.damage(bear, 1, first)
	World.despawn(first)
	var again := EntityFactory.build(SPECS["P"].merged({"name": "PartyBack2"})) as GridEntity
	(again as Player).player_id = "party_back"
	_room.add_child(again)
	World.spawn(again, Vector2i(12, 5))
	World.damage(bear, 1, again)
	_check(bear.party_size == 1 and bear.max_hp == base, "one who comes back is the same one: party %d (%d hp)" % [bear.party_size, bear.max_hp])
	World.damage(bear, 1, hunters[1])
	_check(bear.party_size == 2, "a second player still joins: party %d" % bear.party_size)
	bear._sleep()
	World.despawn(again)
	Monster.idling = true


## The great bear (decision 780): its den at (4, 3), a long room.
func _test_great_bear() -> void:
	print("\n== the great bear: asleep by night at its den, woken by a blow; swipe, slam and charge on their tells; a broken tell; off its ground it breaks off ==")
	Monster.idling = true
	DayNight.set_hour(0.0)  # Night: it sleeps (780 amended (2)).
	var rows: Array[String] = ["#".repeat(40)]
	for y in 5:
		rows.append("#" + ".".repeat(38) + "#")
	rows.append("#".repeat(40))
	var row := rows[3]
	rows[3] = row.substr(0, 4) + "B" + row.substr(5)
	var e := _build(rows)
	var bear: GreatBear = e["B"][0]
	var row_moves: Dictionary = Monster.kinds()["great_bear"]["moves"]
	_check(int(bear.swipe["damage"]) == int(row_moves["swipe"]["damage"]) and int(bear.slam["windup"]) == int(row_moves["slam"]["windup"])
			and int(bear.charge["every"]) == int(row_moves["charge"]["every"]), "its moves' numbers are its monsters.json row's \"moves\" (tuning is data)")
	var drop_items: Array = (Monster.kinds()["great_bear"]["drops"] as Array).map(func(d: Dictionary) -> String: return str(d["item"]))
	_check(Monster.is_apex("great_bear") and not Monster.is_apex("wolf") and not Monster.is_apex("no_such_kind")
			and drop_items == ["bear_pelt", "bear_claw", "bear_grease"] and drop_items.all(func(item: String) -> bool: return Items.all().has(item)),
			"an apex creature by its row (Monster.is_apex), its pelt and claws its drops, and its grease now the medicine man's charms use it (780 amended (4), 789, the coordinator 11-06 and 11-08; %s)" % [drop_items])
	var cries: Array[StringName] = []
	bear.cried.connect(func(kind: StringName) -> void: cries.append(kind))
	for i in 5:
		World.step()
	_check(bear.asleep and bear.pose == Monster.Pose.SIT and bear.den == Vector2i(4, 3), "by night, nobody about: it sleeps at its den")
	var hunter := EntityFactory.build(SPECS["P"].merged({"name": "BearHunter"})) as GridEntity
	_room.add_child(hunter)
	World.spawn(hunter, Vector2i(8, 3))
	for i in 10:
		World.step()
	_check(bear.asleep, "a hunter 4 off: it sleeps on (it sees %d asleep)" % GreatBear.SLEEP_SIGHT)
	World.despawn(hunter)
	World.spawn(hunter, Vector2i(5, 3))
	World.damage(bear, 3, hunter)
	World.step()
	_check(not bear.asleep and &"roar" in cries, "struck asleep, it wakes with a roar (%s)" % [cries])
	_check(bear.engaged_with(hunter) and not bear.engaged_with(null), "engaged with whoever struck it (GreatBear.engaged_with, for companions)")
	bear._next_charge = World.tick + 100000  # Its charge waits for its own check below.
	# The swipe: a cone, then the blow and the push.
	var tells := func(kind: String) -> Array:
		return World.telegraphs().values().filter(func(t: Dictionary) -> bool: return t["kind"] == kind and t["source"] == str(bear.get_path()))
	var swiped := false
	for i in 10:
		World.step()
		if not tells.call("swipe").is_empty():
			swiped = true
			break
	_check(swiped and &"swipe" in cries, "the hunter beside it: a swipe's tell first (a cone), and its growl")
	var before := hunter.hp
	for i in bear.swipe["windup"] + 1:
		World.step()
	_check(hunter.hp == before - int(bear.swipe["damage"]) and World.distance(hunter.tile, bear.tile) >= 2,
			"then the swipe lands: %d hp and swept back (%d off)" % [before - hunter.hp, World.distance(hunter.tile, bear.tile)])
	# A tell broken: knocked down mid-tell, the move is lost.
	World.despawn(hunter)
	World.spawn(hunter, bear.tile + Vector2i(1, 0))
	bear._next_swipe = 0
	for i in 10:
		World.step()
		if not tells.call("swipe").is_empty():
			break
	before = hunter.hp
	World.knock_down(bear, hunter, 8)
	bear._next_swipe = World.tick + 100000  # No second swipe in the window.
	for i in bear.swipe["windup"] + 10:  # Down 8: its tell ends unlanded when it rises.
		World.step()
	_check(hunter.hp == before and tells.call("swipe").is_empty(), "knocked down mid-tell: the swipe is broken off, no blow")
	bear._next_swipe = World.tick + 100000
	for i in 30:
		World.step()
		if bear._move.is_empty():
			break
	# Flanked (combat's 780 side): a blow from behind mid-tell staggers it, the move lost.
	World.despawn(hunter)
	World.spawn(hunter, bear.tile + Vector2i(1, 0))
	bear._next_swipe = 0
	bear._next_slam = World.tick + 100000  # No slam with the flanker beside it; the slam's own check sets it.
	for i in 20:
		World.step()
		if not tells.call("swipe").is_empty():
			break
	var flanker := EntityFactory.build(SPECS["P"].merged({"name": "BearFlanker"})) as GridEntity
	_room.add_child(flanker)
	World.spawn(flanker, bear.tile - bear.facing)
	var engaged_before := bear.engaged_with(flanker)
	var swipe_id := int(bear._move.get("telegraph", 0))
	var flank_marked := swipe_id != 0 and bool(World._telegraphs.get(swipe_id, {}).get("flank", false))
	var flanked := World._try_flank(flanker, bear)
	bear._next_swipe = World.tick + 100000
	before = hunter.hp
	for i in bear.swipe["windup"] + 6:
		World.step()
	_check(flank_marked and flanked and hunter.hp == before and tells.call("swipe").is_empty(),
			"its tells are flank-marked: struck from behind mid-swipe, it staggers and the swipe is lost (marked %s, flanked %s)" % [flank_marked, flanked])
	_check(not engaged_before and bear.engaged_with(hunter), "not engaged with one who has not struck it nor is its foe; its foe is")
	World.despawn(flanker)
	for i in 30:
		World.step()
		if bear._move.is_empty():
			break
	# The slam: two beside it.
	var second := EntityFactory.build(SPECS["P"].merged({"name": "BearHunter2"})) as GridEntity
	_room.add_child(second)
	World.despawn(hunter)
	World.spawn(hunter, bear.tile + Vector2i(1, 0))
	World.spawn(second, bear.tile + Vector2i(0, 1) if World.is_free(bear.tile + Vector2i(0, 1)) else bear.tile + Vector2i(0, -1))
	bear._next_slam = 0
	bear._next_swipe = World.tick + 1000
	var slammed := false
	for i in 20:
		World.step()
		if not tells.call("slam").is_empty():
			slammed = true
			break
	var slam_cells: Array = tells.call("slam")[0]["cells"] if slammed else []
	_check(slammed and slam_cells.size() == 8, "two beside it: it rears, a ring's tell round it (%d cells)" % slam_cells.size())
	var hp_before := [hunter.hp, second.hp]
	for i in bear.slam["windup"] + 1:
		World.step()
	_check(hunter.hp < hp_before[0] and second.hp < hp_before[1] and World.is_down(hunter) and World.is_down(second),
			"the slam: both struck and knocked down")
	World.despawn(second)
	for i in 30:
		World.step()
	# The charge: a foe 5 off on a line, then the rush.
	bear._next_swipe = World.tick + 1000
	bear._next_slam = World.tick + 1000
	bear._next_charge = 0
	World.despawn(hunter)
	World.spawn(hunter, bear.tile + Vector2i(5, 0))
	var charged := false
	for i in 20:
		World.step()
		if not tells.call("charge").is_empty():
			charged = true
			break
	_check(charged, "a foe 5 off: the charge's tell, a line to them")
	# Stepped off the line before it runs: the charge meets nobody; winded.
	var off := hunter.tile + Vector2i(0, 2) if World.is_free(hunter.tile + Vector2i(0, 2)) else hunter.tile + Vector2i(0, -2)
	World.despawn(hunter)
	World.spawn(hunter, off)
	before = hunter.hp
	var winded := false
	for i in 60:
		World.step()
		if World.is_winded(bear):
			winded = true
			break
	_check(winded and hunter.hp == before, "dodged, the charge runs past and leaves it winded: the opening")
	# Off its ground: it breaks off and goes home.
	for i in 40:
		World.step()
	bear.den = Vector2i(-200, 3)
	for i in 5:
		World.step()
	_check(bear.target == null, "its foe off its ground (its den far off): it breaks off")
	World.despawn(hunter)
	bear._sleep()
	DayNight.set_hour(12.0)
	cries.clear()
	World.step()
	_check(not bear.asleep and &"roar" in cries, "at dawn it wakes with a roar, to roam by day")
	# Read from afar (780 amended (2)): its roar told past sight, its prints.
	var far: Array[StringName] = []
	var on_far := func(source: GridEntity, cry: StringName, reach: int) -> void:
		if source == bear and reach == GreatBear.ROAR_REACH:
			far.append(cry)
	World.far_cry.connect(on_far)
	bear._roar("test")
	World.far_cry.disconnect(on_far)
	_check(far == [&"roar"], "its roar goes out as a far cry, %d cells" % GreatBear.ROAR_REACH)
	var was_outdoor := World.fields.outdoor
	World.fields.outdoor = true
	World.tracks.clear()
	var marked: Array[PackedInt32Array] = []
	var on_tracks := func(_level: String, add: PackedInt32Array, _gone: PackedInt32Array, _full: bool) -> void: marked.append(add)
	World.tracks_changed.connect(on_tracks)
	bear._last_tile = Monster.NO_TILE
	for x in [20, 21, 22, 23, 24]:
		World.despawn(bear)
		World.spawn(bear, Vector2i(x, 3))
		bear._track()
	World.tracks_changed.disconnect(on_tracks)
	var level := World.fields.level
	var cells := World.track_cells(level)
	_check(marked.size() == 2 and cells.size() == 8 and cells[0] == 21 and cells[1] == 3 and cells[3] == 2 and cells[4] == 23 and cells[2] > 0,
			"walking east it leaves a print each %d cells, facing east (%s)" % [GreatBear.TRACK_STRIDE, cells])
	var saved := World.tracks_to_dict()
	World.tracks_from_dict(saved)
	_check(World.track_cells(level).size() == 8, "its prints keep in the snapshot")
	World.tracks.clear()
	World.fields.outdoor = was_outdoor
	# The bear yard (playtest's tour ground, a dev level): it reads clean.
	var yard := Level.load_level("bear_yard")
	var kinds: Array[String] = []
	for each: Dictionary in yard.get("entities", []):
		kinds.append(str(each.get("kind", each.get("name", ""))))
	_check(not yard.is_empty() and (yard["warnings"] as Array).is_empty() and bool(yard["terrain"]["outdoor"]) and "great_bear" in kinds
			and kinds.count("KitChest1") + kinds.count("KitChest2") + kinds.count("chest") >= 2 and "bear_yard" in Level.DEV_LEVELS,
			"the bear yard: outdoors, its bear and the kit's chests, no warnings, a dev level (%s, %s)" % [kinds, yard.get("warnings")])
	# Its level's "great_bear": {} merges over the row's body, never replaces it (playtest: 12/12).
	var bear_hp := -1
	for each: Dictionary in yard.get("entities", []):
		if str(each.get("kind", "")) == "great_bear":
			bear_hp = int((each.get("props", {}) as Dictionary).get("max_hp", -1))
	var row_hp := int(Monster.kinds()["great_bear"]["body"]["max_hp"])
	_check(bear_hp == row_hp and row_hp > 12, "the yard's bear has its row's %d hp, not a Monster's 12 (%d)" % [row_hp, bear_hp])
## The night watch's waves (decision 771, npc's Watch calls them): a town's
## ground about (4, 3), its guard post at (21, 3) out east on its spoke.
func _test_watch_wave() -> void:
	print("\n== a night watch's wave comes in out of sight on the post's spoke, cues, fights the watch, is beaten or breaks through ==")
	Monster.idling = true
	var rows: Array[String] = ["#".repeat(100)]
	for y in 5:
		rows.append("#" + ".".repeat(98) + "#")
	rows.append("#".repeat(100))
	var raids := _raid_room(rows, Vector2i(4, 3))
	raids.on_town = func(_town: String, cell: Vector2i) -> bool: return World.distance(cell, Vector2i(4, 3)) <= 2
	raids.town_area = func(_town: String) -> String: return World.zone.name
	var post := Rect2i(20, 2, 2, 2)
	var watcher := EntityFactory.build(SPECS["P"].merged({"name": "Watcher"})) as GridEntity
	_room.add_child(watcher)
	World.spawn(watcher, Vector2i(22, 3))
	var cues: Array[Dictionary] = []
	var ends := {"beaten": [], "broke": [], "faded": []}
	raids.wave_coming.connect(func(id: String, _area: String, kind: String, cell: Vector2i, at: Vector2i) -> void:
		cues.append({"id": id, "kind": kind, "cell": cell, "post": at}))
	raids.wave_beaten.connect(func(id: String, _town: String) -> void: ends["beaten"].append(id))
	raids.wave_broke.connect(func(id: String, _town: String) -> void: ends["broke"].append(id))
	raids.wave_faded.connect(func(id: String, _town: String) -> void: ends["faded"].append(id))
	_check(raids.wave("t", post, "ghosts", 3) == "", "a kind it has no monsters for: no wave")
	var id := raids.wave("t", post, "dead", 3)
	var dead := raids.raiders(id)
	var kinds := dead.map(func(each: Monster) -> String: return str(each.spawn_spec.get("kind", "")))
	_check(id != "" and dead.size() == 3 and kinds.all(func(k: String) -> bool: return k in ["skeleton", "skeleton_guard"]),
			"three of the dead come (%s: %s)" % [id, kinds])
	_check(dead.all(func(each: Monster) -> bool: return World.distance(each.tile, watcher.tile) > World.VIEW_TILES and each.tile.x > post.position.x),
			"out of the watcher's sight, out along the spoke past the post (%s)" % [dead.map(func(each: Monster) -> Vector2i: return each.tile)])
	_check(cues.size() == 1 and cues[0]["kind"] == "dead" and cues[0]["post"] == post.get_center() and raids.waves_at("t") == [id],
			"its cue as it comes in (%s)" % [cues])
	var met := false
	for i in 1500:
		World.step()
		if dead.any(func(each: Monster) -> bool: return is_instance_valid(each) and World.distance(each.tile, watcher.tile) <= 1):
			met = true
			break
	_check(met and cues.size() == 2 and World.distance(cues[1]["cell"], post.get_center()) < World.distance(cues[0]["cell"], post.get_center()),
			"they march on the post, cued again halfway, nearer (%s)" % [cues.map(func(c: Dictionary) -> Vector2i: return c["cell"])])
	_check(ends["broke"].is_empty(), "the watch stands in their way: no break-through yet")
	for each in raids.raiders(id):
		World.damage(each, 999)
	World.step()
	_check(ends["beaten"] == [id] and raids.waves_at("t").is_empty() and raids.raiders(id).is_empty(), "every one down: the wave is beaten (%s)" % [ends])
	# The post unwatched: wolves, more than a wave holds, go by it to the town.
	World.despawn(watcher)
	World.spawn(watcher, Vector2i(2, 1))
	var wolves_id := raids.wave("t", post, "wolves", 20)
	var wolves := raids.raiders(wolves_id)
	_check(wolves.size() == Raids.WAVE_MOST and wolves.all(func(each: Monster) -> bool: return each is Animal),
			"twenty asked: a wave of %d wolves at most (%d)" % [Raids.WAVE_MOST, wolves.size()])
	for i in 2000:
		World.step()
		if not ends["broke"].is_empty():
			break
	_check(ends["broke"] == [wolves_id], "past the empty post they reach the town: a break-through (%s)" % [ends])
	raids.hand_back(World.zone.name)
	_check(ends["faded"] == [wolves_id] and raids.ids().is_empty() and World.monsters().is_empty(),
			"its zone asleep, the wave fades, off the map (%s)" % [ends])


## Decision 805 amended (2): a beast drawn to someone fishing
## (Wanderers; economy's wanderer_due says when).
func _test_wanderers() -> void:
	print("\n== a wanderer: a boar comes in out of sight to the one fishing, charges, is driven off and gone; wolves give up ==")
	Monster.idling = true
	var rows: Array[String] = ["#".repeat(100)]
	for y in 5:
		rows.append("#" + ".".repeat(98) + "#")
	rows.append("#".repeat(100))
	_raid_room(rows, Vector2i(4, 3))
	World.outdoor = true
	var wanderers := World.wanderers
	wanderers.clear()
	var fisher := EntityFactory.build(SPECS["P"].merged({"name": "Fisher", "props": {"max_hp": 400}})) as GridEntity
	_room.add_child(fisher)
	World.spawn(fisher, Vector2i(10, 3))
	wanderers.player_of = func(id: String) -> Player: return fisher as Player if id == "p1" else null
	var cast := Vector2i(11, 3)
	_check(wanderers.come("pond_a", "p1", "deer", cast) == "" and wanderers.come("pond_a", "p9", "boar", cast) == "",
			"an unknown kind, or a player not here: none comes")
	var id := wanderers.come("pond_a", "p1", "boar", cast)
	var boars := wanderers.beasts(id)
	_check(id != "" and boars.size() == 1 and str(boars[0].spawn_spec.get("kind", "")) == "boar" and boars[0].drawn
			and boars[0].wanderer == id, "a boar comes, drawn (%s)" % [id])
	var boar: Animal = boars[0] if not boars.is_empty() else null
	if boar == null:
		return
	_check(World.distance(boar.tile, fisher.tile) > World.VIEW_TILES, "in at %s, out of the fisher's sight" % boar.tile)
	_check(Snapshot._entries([boar] as Array[GridEntity]).is_empty(), "never saved")
	var hurt := false
	var hp0 := fisher.hp
	for i in 1500:
		World.step()
		if fisher.hp < hp0:
			hurt = true
			break
	_check(hurt and World.distance(boar.tile, fisher.tile) <= 2, "it walks to the cast and goes at the fisher, not bolting (%d hp, at %s)" % [fisher.hp, boar.tile])
	World.damage(boar, boar.hp - boar.max_hp / 2 + 1, fisher)
	var gone := false
	for i in 1500:
		World.step()
		if not boar.spawned:
			gone = true
			break
	_check(not boar.drawn and gone and wanderers.ids().is_empty(), "under half its hp it is driven off, runs, and is gone out of sight; the wanderer is over")
	# Wolves, a pair, that never reach anyone before their time is up.
	var pair_id := wanderers.come("pond_a", "p1", "wolf", cast)
	var wolves := wanderers.beasts(pair_id)
	_check(wolves.size() == 2 and wolves.all(func(w: Animal) -> bool: return str(w.spawn_spec.get("kind", "")) == "wolf" and w.drawn),
			"\"wolf\" is a pair, drawn (%d)" % wolves.size())
	for w in wolves:
		w._bold_tick = -1
		w._settle_bold()
	_check(wolves.all(func(w: Animal) -> bool: return w._bold), "drawn wolves are bold by day")
	wanderers._in_play[pair_id]["start"] = World.tick - Wanderers.LINGER_TICKS
	World.step()
	_check(wanderers.ids().is_empty() and wolves.all(func(w: Animal) -> bool: return not w.spawned),
			"their time up and nobody in a fight, they turn back and are gone, out of sight")
	World.outdoor = false
	World.spawn_spec = Callable()
	wanderers.player_of = Callable()
	World.despawn(fisher)


## Decision 814: the hill cat. Its perch's place read (kind "perch",
## "watch"); laid on its perch, lying, unsaved; a player on its watch looking
## away is pounced on (a told line, hurt, never to 0); one looking its way
## spots it (once, World.cat_spotted) and is let be; one who steps off the
## line is missed and it lands open; under half it breaks off and is gone
## out of sight, its perch closed; killed, closed longer.
func _test_hill_cat() -> void:
	print("
== the hill cat (814): lies up, pounces on the unwary, lets be who spots it ==")
	Monster.idling = true
	var warnings: Array[String] = []
	var read := Level.places_from({"places": {"p": {"at": [1, 1], "kind": "perch", "watch": [[2, 2], [3, 3]]}}}, warnings)
	_check(read.get("p", {}).get("kind") == "perch" and read["p"].get("watch") == [Vector2i(2, 2), Vector2i(3, 3)] and warnings.is_empty(),
		"a perch place and its watch are read (%s; %s)" % [read.get("p", {}), warnings])
	var rows: Array[String] = ["#".repeat(40)]
	for y in 9:
		rows.append("#" + ".".repeat(38) + "#")
	rows.append("#".repeat(40))
	_raid_room(rows, Vector2i(35, 5))
	World.outdoor = true
	HillCat.clear_perches()
	var watch: Array = []
	for x in range(6, 10):
		for y in range(3, 8):
			watch.append(Vector2i(x, y))
	var place := {"key": "perch_t", "cell": Vector2i(5, 5), "watch": watch}
	var cat := HillCat._lay("t/perch_t", place)
	_check(cat != null and cat.tile == Vector2i(5, 5) and cat.lying() and HillCat.on_perch("t/perch_t") == cat
		and cat.watch.size() == watch.size(), "a cat lies up on its perch")
	if cat == null:
		return
	_check(Snapshot._entries([cat] as Array[GridEntity]).is_empty(), "never saved")
	cat.pounce["day_reach"] = cat.pounce["reach"]  # Its night reach, whatever the hour here.
	var walker := EntityFactory.build(SPECS["P"].merged({"name": "Walker", "props": {"max_hp": 20}})) as Player
	_room.add_child(walker)
	walker.player_id = "p1"
	World.spawn(walker, Vector2i(8, 5))
	walker.protected = false
	World.face(walker, Vector2i(1, 0))  # Eyes ahead, away from the rocks.
	var spotted: Array = []
	var on_spotted := func(c: GridEntity, pid: String) -> void: spotted.append([c, pid])
	World.cat_spotted.connect(on_spotted)
	var hp0 := walker.hp
	for i in 40:
		World.step()
		if walker.hp < hp0:
			break
	_check(walker.hp == hp0 - int(cat.pounce["damage"]) and not cat.lying() and World.distance(cat.tile, walker.tile) <= 1 and spotted.is_empty(),
		"one walking on below, eyes ahead, is pounced on: %d hurt, the cat beside them at %s" % [hp0 - walker.hp, cat.tile])
	# Off its perch it fights as a bold predator, alone: no cautious holding
	# back for mates who never come (its roll a cautious one's, its temper bold).
	cat.boldness = 0.1
	var after := walker.hp
	var struck_at := -1
	var from := World.tick
	for i in 60:
		World.step()
		if walker.hp < after:
			struck_at = World.tick - from
			break
	_check(struck_at >= 0 and struck_at <= 40, "after its pounce, off its perch, it fights on alone (struck again after %d ticks)" % struck_at)
	walker.hp = walker.max_hp
	# Never downed by it.
	World.despawn(cat)
	var cat2 := HillCat._lay("t/perch_t", place, true)
	cat2.pounce["day_reach"] = cat2.pounce["reach"]
	walker.hp = 3
	walker.protected = false
	for i in 40:
		World.step()
		if walker.hp < 3:
			break
	_check(walker.hp == 1 and not World.is_downed(walker), "a pounce never downs: left at %d" % walker.hp)
	World.despawn(cat2)
	walker.hp = walker.max_hp
	# Spotted first: let be.
	var cat3 := HillCat._lay("t/perch_t", place, true)
	cat3.pounce["day_reach"] = cat3.pounce["reach"]
	World.face(walker, Vector2i(-1, 0))  # Looking up at the rocks.
	for i in HillCat.SPOT_LOOK_TICKS - 1:
		World.step()
	_check(not cat3.spotted_by("p1") and walker.hp == walker.max_hp, "a look takes a while: not spotted at once, and not pounced on mid-look")
	for i in 60:
		World.step()
	_check(cat3.spotted_by("p1") and spotted.size() == 1 and walker.hp == walker.max_hp and cat3.lying(),
		"one looking its way spots it (once) and is let be (%s, %d hp)" % [spotted.size(), walker.hp])
	cat3.mark_spotted("p1")
	_check(spotted.size() == 1, "spotted once a cat a player")
	# Stepped off the line: missed, it lands open.
	World.despawn(cat3)
	var cat4 := HillCat._lay("t/perch_t", place, true)
	cat4.pounce["day_reach"] = cat4.pounce["reach"]
	World.face(walker, Vector2i(1, 0))
	for i in 10:
		World.step()
		if not cat4._move.is_empty():
			break
	_check(not cat4._move.is_empty(), "it crouches for the walker (a told pounce)")
	World._relocate(walker, Vector2i(8, 8))
	for i in 20:
		World.step()
		if cat4.tile != Vector2i(5, 5):
			break
	_check(walker.hp == walker.max_hp and cat4.tile == Vector2i(8, 5), "stepped off the line: missed, it lands where they stood (%s)" % cat4.tile)
	# A cell beside the aim, as a path bends round the rocks: still under its
	# paws (the told line 3 wide); two off, clear.
	for off in [1, 2]:
		World.despawn(cat4)
		cat4 = HillCat._lay("t/perch_t", place, true)
		cat4.pounce["day_reach"] = cat4.pounce["reach"]
		walker.hp = walker.max_hp
		walker.protected = false
		World._relocate(walker, Vector2i(8, 5))
		World.face(walker, Vector2i(1, 0))
		for i in 12:
			World.step()
			if not cat4._move.is_empty():
				break
		World._relocate(walker, Vector2i(8, 5 + off))
		for i in 20:
			World.step()
			if cat4._move.is_empty():
				break
		_check((walker.hp < walker.max_hp) == (off == 1),
			"one %d cell%s beside the aimed cell at the landing is %s (%d hp)" % [off, "" if off == 1 else "s", "hit" if off == 1 else "clear", walker.hp])
	# A walker who keeps on: it aims at where they will be (the lead), and
	# one walking on blind is hit there; one who stops at the tell is missed.
	for stops in [false, true]:
		World.despawn(cat4)
		cat4 = HillCat._lay("t/perch_t", place, true)
		cat4.pounce["day_reach"] = cat4.pounce["reach"]
		walker.hp = walker.max_hp
		walker.protected = false
		World._relocate(walker, Vector2i(8, 3))
		World.face(walker, Vector2i(1, 0))
		walker.move_ticks = 4.0
		walker.next_move_tick = 0
		var crouch_at: Vector2i = HillCat.NO_TILE
		for i in 60:
			if crouch_at == HillCat.NO_TILE and not cat4._move.is_empty():
				crouch_at = walker.tile
			var walking: bool = walker.tile.y < 9 and not (stops and crouch_at != HillCat.NO_TILE)
			if walking:
				World.try_move(walker, Vector2i(0, 1))  # A cell every 4 ticks, eyes down the way: its lead about 3 on.
			World.step()
			if walker.hp < walker.max_hp or (crouch_at != HillCat.NO_TILE and cat4._move.is_empty()):
				break
		if stops:
			_check(crouch_at != HillCat.NO_TILE and walker.hp == walker.max_hp,
				"one who stops at the tell is missed (crouched at them on %s, they stood at %s)" % [crouch_at, walker.tile])
		else:
			_check(crouch_at != HillCat.NO_TILE and crouch_at.y < 7 and walker.hp == walker.max_hp - int(cat4.pounce["damage"]),
				"a walker walking on blind is hit at their lead (crouched with them on %s, hit on %s)" % [crouch_at, walker.tile])
	World._relocate(walker, Vector2i(8, 5))
	walker.hp = walker.max_hp
	walker.move_ticks = 2.5
	# Beaten off: gone out of sight, its perch closed.
	World.damage(cat4, cat4.hp - cat4.max_hp / 2 + 1, walker)
	for i in 30:
		World.step()
		if cat4._broke_off:
			break
	World.step()
	var broken_pace: float = cat4.move_ticks
	var lay_hurt := false
	var slunk := false
	for i in 500:  # The walker stands where they were, the cat in their sight: not following.
		World.step()
		lay_hurt = lay_hurt or cat4._lying_hurt
		slunk = slunk or cat4._slinking
		if not cat4.spawned:
			break
	var cat_at := cat4.tile
	var walker_at := walker.tile
	World.despawn(walker)
	print("  (the cat at %s, the walker at %s)" % [cat_at, walker_at])
	_check(not cat4.spawned and lay_hurt and slunk and HillCat.on_perch("t/perch_t") == null and broken_pace == HillCat.BROKEN_PACE and int(HillCat._perches["t/perch_t"]["closed_until"]) > World.steps,
		"under half it breaks off, lies up hurt, and with nobody coming after it (one standing in sight) it limps off and is gone, its perch empty a while")
	# Followed: it runs a short way, bleeding, and lies up hurt; a walker who
	# follows the trail finds it there and it fights where it lies.
	HillCat.clear_perches()
	var fields_outdoor_was: bool = World.fields.outdoor
	World.fields.outdoor = true  # Blood is marked out of doors (764).
	var blood_was: Dictionary = World.blood.duplicate(true)
	var cat6 := HillCat._lay("t/perch_t", place, true)
	var chaser := EntityFactory.build(SPECS["P"].merged({"name": "Chaser", "props": {"max_hp": 20}})) as Player
	_room.add_child(chaser)
	chaser.player_id = "p2"
	World.spawn(chaser, Vector2i(6, 5))
	chaser.protected = false
	cat6._lying = false
	World.damage(cat6, cat6.hp - cat6.max_hp / 2 + 1, chaser)
	var broke_from := cat6.tile
	var bled := 0
	var found := false
	var fled_after := 0
	for i in 400:
		if cat6._lying_hurt and not found and World.distance(chaser.tile, cat6.tile) > 1:
			var way := (cat6.tile - chaser.tile).clamp(Vector2i(-1, -1), Vector2i(1, 1))
			World.try_move(chaser, way)
		World.step()
		if not cat6.spawned:
			break
		if cat6._roused and not found:
			found = true
			broke_from = cat6.tile
		if found:
			fled_after = maxi(fled_after, World.distance(cat6.tile, broke_from))
			if i % 6 == 0:
				World.damage(cat6, 3, chaser)
	for cell: Vector2i in World.blood.get(World.fields.level, {}):
		bled += 1
	_check(found and not cat6.spawned and fled_after <= 1 and bled >= 3,
		"broken, it runs a short way bleeding (%d marks), lies up hurt, and a walker who follows finds it and finishes it where it lies (moved %d once found)" % [bled, fled_after])
	World.despawn(chaser)
	World.fields.outdoor = fields_outdoor_was
	World.blood = blood_was  # Its trail is not the next test's.
	# Killed: closed longer.
	HillCat.clear_perches()
	var cat5 := HillCat._lay("t/perch_t", place, true)
	World.damage(cat5, cat5.hp + 5)
	_check(int(HillCat._perches.get("t/perch_t", {}).get("closed_until", 0)) >= World.steps + int(HillCat.KILLED_DAYS * DayNight.day_steps) - 1,
		"killed, its perch is empty for %.0f days" % HillCat.KILLED_DAYS)
	# The perches' own laying: Holdings' perch place (its watch carried), an
	# awake zone, the perch out of the player's sight.
	HillCat.clear_perches()
	var zone_name: String = World.zone.name
	Level.register(zone_name, Level.image_from_rows(rows), null, {"outdoor": true, "places": {
		"perch_z": {"at": [5, 5], "kind": "perch", "watch": [[6, 5], [7, 5]]}}})
	var held_was := World.holdings
	var names: Array[String] = [zone_name]
	World.holdings = Holdings.new(WorldMap.build(names), Factions.read(), {})
	var far := EntityFactory.build(SPECS["P"].merged({"name": "FarOff"})) as Player
	_room.add_child(far)
	World.spawn(far, Vector2i(38, 8))
	World.step()
	HillCat.step_perches()
	var laid := HillCat.on_perch("%s/perch_z" % zone_name)
	_check(laid != null and laid.tile == Vector2i(5, 5) and laid.watch.size() == 2 and laid.perch == "%s/perch_z" % zone_name,
		"step_perches lays a cat on an empty perch of an awake zone, its watch from Holdings")
	World.despawn(far)
	World.holdings = held_was
	World.cat_spotted.disconnect(on_spotted)
	HillCat.clear_perches()
	World.outdoor = false
	World.spawn_spec = Callable()


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
	_check(rest[0].alert == Monster.Alert.FLEEING and rest[0]._ran_to_call and rest[1].alert == Monster.Alert.FIGHTING,
			"one of them hurt: it runs to call, no rout, and the other fights on (806 amended (9); %s)" % [rest.map(func(r: Monster) -> String: return Monster.Alert.keys()[r.alert])])
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
	player.step_gap = Animal.STALK_STEP_TICKS + 1  # A stalk's slow step (764): unheeded.
	World.noise(off, 6, &"step", player)
	World.step()
	_check(rabbit.alert == Monster.Alert.IDLE, "a slow step 6 off (a stalk): unheeded (764)")
	player.step_gap = 3  # Walking on: hurried.
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
	# One routed beside the way out: its path there was a bare [] in a ternary,
	# untyped, and the assign failed (playtest's barrow tour, a camp robber at its door).
	var beside := EntityFactory.build(SPECS["x"].merged({"name": "Beside", "props": Monster.bodies()["robber"]})) as Monster
	_room.add_child(beside)
	World.spawn(beside, entrance + Vector2i(0, 1))
	beside._flee(player.tile)
	var sought_out := beside._way_out
	var out_by := -1
	for i in 40:
		World.step()
		if not beside.spawned:
			out_by = i + 1
			break
	_check(sought_out == entrance and out_by > 0,
			"a robber routed beside the entrance: making for it (%s), gone by it at tick %d (at %s)" % [sought_out, out_by, beside.tile])
	if beside.spawned:
		World.despawn(beside)
	World.outdoor = true
	var outside := EntityFactory.build(SPECS["x"].merged({"name": "Outside", "props": Monster.bodies()["robber"]})) as Monster
	_room.add_child(outside)
	World.spawn(outside, path[3])
	outside._flee(player.tile)
	_check(outside._way_out == Monster.NO_TILE and outside.alert == Monster.Alert.FLEEING,
			"a robber routed under the sky: the plain flee, no way out sought")
	World.outdoor = false
	# 702 amended: a level that is its kind's home ("home_kinds") keeps it.
	Level.register("mt_home", Level.image_from_rows(["..."]), null, {"home_kinds": ["robber"]})
	var was_name := World.zone.name
	World.zone.name = "mt_home"
	var homed := EntityFactory.build(SPECS["x"].merged({"name": "Homed", "props": Monster.bodies()["robber"]})) as Monster
	_room.add_child(homed)
	World.spawn(homed, path[8])
	homed._flee(player.tile)
	var sought := homed._way_out
	for i in 120:
		World.step()
	_check(homed.at_home() and sought == Monster.NO_TILE and homed._way_out == Monster.NO_TILE and homed.spawned,
			"a robber routed where robbers are at home: no way out, still there at %s" % homed.tile)
	World.zone.name = was_name
	Level.unregister("mt_home")
	World.despawn(homed)
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
	var due_was := int(record["returns_at"])
	record["returns_at"] = World.steps + NamedEnemy.rise_steps("test_named") + 100
	_check(World.named_may_rise(spec), "saved under a longer rise than its own now (758): it waits no longer than its rise")
	record["returns_at"] = due_was
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
	_check(brand.given_name == "Brand the Ox" and brand.boss and crake.given_name == "Crake" and not crake.boss
			and brand.sync.replication_config.has_property(NodePath(".:given_name")) and brand.sync.replication_config.has_property(NodePath(".:boss")),
			"752: their names shown over them, Brand a boss, Crake not, both replicated (%s %s, %s %s)" % [brand.given_name, brand.boss, crake.given_name, crake.boss])
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
	# Its notice (784) fills before it knows them: a second or two at 2 cells.
	for i in Animal.PREY_LOOK_TICKS + 2 + 2 * int(Monster.NOTICE_FILL_TICKS):
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



## Decision 784: a kind's "senses" (the wave kinds and the bear): sight in the
## dark by its night, a cone, an ear, and a notice that fills before it knows
## whom it sees; a kind with none as before.
func _test_senses() -> void:
	print("\n== senses (784): a robber's notice fills by how near, its ear by its hearing; an imp as before ==")
	Monster.idling = true
	DayNight.set_hour(12.0)
	var imp: Monster = _build(["#####", "#.i.#", "#####"])["i"][0]
	_check(imp.notice_rate == 0.0 and imp.senses.night < 0.0 and imp.hearing == 1.0, "an imp (no \"senses\") as before: knows whom it sees at once")
	var e := _build(["##############", "#............#", "#.....P...x..#", "#............#", "##############"], {"x": {"facing": Vector2i(-1, 0)}})
	var robber: Monster = e["x"][0]
	var player: GridEntity = e["P"][0]
	robber.reaction_ticks = 0
	robber.sight_range = 5  # _build stills it (sight 0); its row's 5.
	Monster.idling = false  # Standing, not wandering off out of its own cone.
	_outdoors("clear")  # By daylight: its notice, not the dark, is what this measures.
	var row: Dictionary = Monster.kinds()["robber"]["senses"]
	_check(robber.notice_rate > 0.0 and is_equal_approx(robber.senses.night, float(row["night"])) and absf(robber.senses.cone_cos - 0.5) < 0.01
			and robber.alert_sight == int(row["alert_sight"]) and robber.senses.alert_cone_cos < robber.senses.cone_cos,
			"a robber's senses are its row's: night %.1f, a 120-degree cone, wider looking about" % robber.senses.night)
	_check(Monster.cone_cos_of(360.0) == -1.0 and Monster.hearing_most() >= 1.5, "all round at 360; the keenest ear is the wolf's 1.5")
	# Any agent's eyes from the same block (784 amended: npc's guards).
	var eyes := Senses.new(player, 7)
	eyes.take({})
	var unchanged := eyes.night < 0.0 and eyes.extra_sight == 0
	eyes.take({"night": 0.45})
	_check(unchanged and is_equal_approx(eyes.night, 0.45) and eyes.cone_cos == -1.0 and eyes.extra_sight == 0,
			"Senses.take: an empty block changes nothing; {night: 0.45} sets its night, all round, nothing more")
	# Woken by them near, it looks from a moment of its own (a few ticks).
	var first := 0.0
	var waited := 0
	while first <= 0.0 and waited < 12:
		World.step()
		waited += 1
		first = robber.notice_of(player)
	_check(robber.target == null and first > 0.0 and first < 1.0,
			"a player 4 off in its cone: it notices them, not yet knowing them (%.2f after %d; sees %s, %s)"
			% [first, waited, robber.senses.sees(player), robber.senses.dark_reach(player.tile, robber.sight_range)])
	var known := -1
	for i in 120:
		World.step()
		if robber.notice_of(player) >= Monster.NOTICE_FULL:
			known = i + 1
			break
	_check(known > 2, "it knows them after %d ticks more, past a glance (turning to look on the way; %.2f)" % [known, robber.notice_of(player)])
	_check(World.tick_parts.has("senses"), "its look is a part of the tick by name, \"senses\" (%s)" % [World.tick_parts.keys()])
	# Its ear: a noise 4 off with a reach of 5 is heard by an ear of 1, not by one of 0.5.
	World.despawn(player)
	robber.target = null
	var heard := robber.senses.heard.size()
	robber.hearing = 0.5
	World.noise(robber.tile + Vector2i(-4, 0), 5, &"thud")
	var dull := robber.senses.heard.size() == heard
	robber.hearing = 1.0
	World.noise(robber.tile + Vector2i(-4, 0), 5, &"thud")
	_check(dull and robber.senses.heard.size() == heard + 1, "a noise 4 off, reach 5: a dull ear (0.5) misses it, a plain one hears it")
	# Gone from its sight: its notice fades and goes, never growing.
	for i in 120:
		World.step()
	_check(robber._notice.is_empty(), "the player gone: its notice fades to nothing (%s)" % [robber._notice])
	_indoors()
	Monster.idling = true



## Decision 784 amended (2): a crouched player creeps at World.crouch_pace,
## heard half as far and seen from 0.8 as far (never under 2 cells).
func _test_crouch() -> void:
	print("
== crouch (784 amended (2)): it creeps, quieter and harder to see ==")
	DayNight.set_hour(12.0)
	var e := _build(["##########", "#........#", "#.P....x.#", "#........#", "##########"], {"x": {"facing": Vector2i(-1, 0)}})
	var player := e["P"][0] as Player
	var robber: Monster = e["x"][0]
	robber.sight_range = 6
	_outdoors("clear")
	var walk := World.step_ticks(player, Vector2i(1, 0))
	var noise := World.step_noise(player)
	var seen := robber.senses.sees(player)
	player.crouched = true
	var creep := World.step_ticks(player, Vector2i(1, 0))
	_check(is_equal_approx(creep, walk / World.crouch_pace(player)), "crouched it creeps at %.2f of a walk (%.1f ticks a step, %.1f walking)" % [World.crouch_pace(player), creep, walk])
	_check(World.step_noise(player) == maxi(1, roundi(noise * 0.5)), "its steps carry half as far (%d, %d standing)" % [World.step_noise(player), noise])
	_check(seen and not robber.senses.sees(player), "5 cells off a robber that sees 6: seen standing, not crouched (6 x 0.8 = 4.8)")
	player.crouched = false
	var f := _build(["#####", "#P.x#", "#####"], {"x": {"facing": Vector2i(-1, 0)}})
	var near: Monster = f["x"][0]
	near.sight_range = 2
	var low := f["P"][0] as Player
	low.crouched = true
	_check(near.senses.sees(low), "2 off, crouched, is still seen: never under 2 cells")
	low.crouched = false
	_indoors()


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
	_check(rows.size() == 20 and windup.size() == 1 and windup[0]["kind"] == "int" and windup[0]["takes"] == "spawn",
		"20 rows listed (698's band_min, 338 amended (4)'s lead_ticks, strike_recover_ticks and settle_ticks too), windup_ticks an int taken at spawn (%s)" % [windup])
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
	# Rows tuned since (each its decision's): the hill cat's dart (814, combat's).
	var tuned := {"hill_cat.dart_after_ticks": 6}
	for kind: String in Monster.kinds():
		var rules := Monster.fight_for(kind)
		for key: String in old:
			var at := "%s.%s" % [kind, key]
			if tuned.has(at):
				if rules.get(key) != tuned[at]:
					differ.append("%s: %s, not its tuned %s" % [at, rules.get(key), tuned[at]])
				continue
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
	_check(draugr.boss and draugr.given_name == "" and not skeleton.boss and skeleton.given_name == "",
		"752: the draugr a boss by his kind, no name given; a skeleton neither")
	_check(int(draugr.blows.get("battle_axe", {}).get("recover", 0)) == 3,
		"his plain heavy blow with his axe plants him 3 ticks after it (750's recover, through World.blow_verb)")
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
		and poor[0]["title"] == "Refuse" and poor[0]["words"] == Draugr.WORDS and int(poor[1]["cost"]) == 10 and DealPanel.no_deal(poor) == poor[0]
		and DealPanel.first_deal(poor) == poor[1],
		"no gold: his first deal is the free refusal (what an older panel shows), the panel's Refuse, his own demand its words (735 amended), his gold deal after (%s)" % [poor.map(func(o: Dictionary) -> String: return str(o["id"]))])
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


## A blow at [param target] from [param by], at once (no lead, no AI), resolved.
func _blow_at(by: Monster, target: GridEntity) -> void:
	by.lead_ticks = 0
	by.next_attack_tick = 0
	by.next_move_tick = 0
	World.try_attack(by, target)
	World.step()


## 340 amended: a blow a raised shield takes whole throws its attacker back,
## stunned SHIELD_RECOIL_STUN (cause &"guarded"), the holder's opening; a
## sword's parry, a broken guard, and the buckler too.
func _test_shield_recoil() -> void:
	print("
== 340 amended: a blow taken on a raised shield throws its attacker back ==")
	var had_noticing := Monster.noticing
	Monster.noticing = false  # These test what a blow does, not how a monster picks one.
	for shield: String in ["shield", "buckler"]:
		for kind: String in ["i", "x"]:
			var e := _build(["#######", "#.P%s..#" % kind, "#######"])
			var foe: Monster = e[kind][0]
			var player: GridEntity = e["P"][0]
			player.slots[Items.LEFT_HAND] = shield
			World.face(player, Vector2i(1, 0))
			World.try_stance(player, "block")
			var told: Array = []
			foe.stunned.connect(func(ticks: int, cause: StringName) -> void: told.append([ticks, cause]))
			var hp := player.hp
			_blow_at(foe, player)
			_check(World.is_stunned(foe) and foe.stun_cause == &"guarded" and told == [[World.SHIELD_RECOIL_STUN, &"guarded"]]
					and player.raised == "block",
					"%s's blow on a raised %s: thrown back %d ticks, &\"guarded\", the guard held (%s, %s, hp %d of %d)" % [
					foe.name, shield, World.SHIELD_RECOIL_STUN, told, player.raised, player.hp, hp])
	# A sword's parry: no recoil.
	var e := _build(["#######", "#.Pi..#", "#######"])
	var imp: Monster = e["i"][0]
	var player: GridEntity = e["P"][0]
	player.slots[Items.RIGHT_HAND] = "sword"
	World.face(player, Vector2i(1, 0))
	player.next_attack_tick = 0
	_blow_at(imp, player)
	_check(not World.is_stunned(imp), "a sword's parry throws nothing back")
	# A blow that breaks it: none, the holder stunned as before (&"broken").
	e = _build(["#######", "#.Pi..#", "#######"])
	imp = e["i"][0]
	player = e["P"][0]
	player.slots[Items.LEFT_HAND] = "shield"
	World.face(player, Vector2i(1, 0))
	World.try_stance(player, "block")
	imp.attack_damage = 4
	_blow_at(imp, player)
	_check(not World.is_stunned(imp) and World.is_stunned(player) and player.stun_cause == &"broken",
			"a blow that breaks it: no recoil, the holder stunned (&\"%s\")" % player.stun_cause)
	Monster.noticing = had_noticing


## 340 amended: a lowered shield guards its arm's side (the holder's left)
## at half its absorb, with no recoil; the other side, nothing.
func _test_lowered_shield() -> void:
	print("
== 340 amended: a lowered shield half-guards its own side ==")
	var had_noticing := Monster.noticing
	Monster.noticing = false
	var taken := {}
	for at: Vector2i in [Vector2i(3, 1), Vector2i(3, 3)]:  # Facing east: north is its left, south its right.
		var e := _build(["#######", "#.....#", "#.....#", "#.....#", "#######"])
		var player := EntityFactory.build(SPECS["P"].duplicate(true).merged({"name": "Player1"})) as Player
		_room.add_child(player)
		World.spawn(player, Vector2i(3, 2))
		player.slots[Items.LEFT_HAND] = "shield"
		World.face(player, Vector2i(1, 0))
		var imp := EntityFactory.build(SPECS["i"].duplicate(true).merged({"name": "Imp9"})) as Monster
		_room.add_child(imp)
		World.spawn(imp, at)
		_check(World.guarding(player, imp).is_empty(), "lowered, guarding (the AI's) sees no guard from %s" % at)
		var hp := player.hp
		_blow_at(imp, player)
		taken[at] = hp - player.hp
		_check(not World.is_stunned(imp), "no recoil off a lowered shield (from %s)" % at)
	_check(int(taken[Vector2i(3, 1)]) == 0 and int(taken[Vector2i(3, 3)]) >= 1,
			"an imp's poke from its shield side: %d taken; from the other: %d" % [taken[Vector2i(3, 1)], taken[Vector2i(3, 3)]])
	var e := _build(["#######", "#.....#", "#.....#", "#######"])
	var player := EntityFactory.build(SPECS["P"].duplicate(true).merged({"name": "Player1"})) as Player
	_room.add_child(player)
	World.spawn(player, Vector2i(3, 2))
	player.slots[Items.LEFT_HAND] = "shield"
	World.face(player, Vector2i(1, 0))
	var imp := EntityFactory.build(SPECS["i"].duplicate(true).merged({"name": "Imp9"})) as Monster
	_room.add_child(imp)
	World.spawn(imp, Vector2i(3, 1))
	var lowered := World.lowered_guard(player, imp)
	_check(is_equal_approx(float(lowered.get("absorb", 0.0)), 0.5) and lowered.get("lowered", false),
			"the round shield lowered: absorb 0.5 of its 1.0 (%s)" % [lowered.get("absorb")])
	player.winded = true
	_check(World.lowered_guard(player, imp).is_empty(), "winded, nothing")
	Monster.noticing = had_noticing


## 340 amended, the coordinator's check: recoil goes both ways, so a
## skeleton guard's raised shield meets a sword player's blows; a sword still
## beats it from the front in fair time (its blow weighs past 3.5 and breaks
## the guard), no stalemate.
func _test_sword_beats_guard() -> void:
	print("
== 340 amended: a sword beats a skeleton guard's shield from the front ==")
	Monster.idling = false
	var e := _build(["#########", "#.......#", "#..Pg...#", "#.......#", "#########"])  # Toe to toe: a guard holds its post.
	var guard: Monster = e["g"][0]
	var player: GridEntity = e["P"][0]
	_bold(guard)
	guard.slots = PackedStringArray(["", "", "", "", "", "shield"])  # As Level arms one with a shield.
	player.slots[Items.RIGHT_HAND] = "sword"
	player.max_hp = 999
	player.hp = 999
	var thrown: Array[int] = [0]  # Arrays: a lambda takes ints by value.
	var broken: Array[int] = [0]
	var swings: Array[int] = [0]
	var on_stun := func(_ticks: int, cause: StringName) -> void:
		if cause == &"guarded":
			thrown[0] += 1
	player.stunned.connect(on_stun)
	var on_break := func(target: GridEntity, _source: GridEntity, was_broken: bool) -> void:
		if target == guard and was_broken:
			broken[0] += 1
	World.guard_met.connect(on_break)
	var ticks := 0
	while ticks < 600 and guard.spawned and guard.hp > 0:
		if World.distance(player.tile, guard.tile) <= 1:
			World.face(player, guard.tile - player.tile)
			swings[0] += 1 if World.try_attack(player, guard) else 0
		World.step()
		ticks += 1
	World.guard_met.disconnect(on_break)
	_check(not guard.spawned or guard.hp <= 0,
			"a sword brings a shielded skeleton guard down in %.1f s (%d swings, its guard broken %d times, the player thrown back %d, raised %s)" % [ticks / 10.0, swings[0], broken[0], thrown[0], guard.raised])
	_check(ticks <= 300, "in fair time, no stalemate (%d ticks)" % ticks)
	Monster.idling = true


## 379 amended: the one bashed is told so, which way and by whom, and its
## stun carries &"bash".
func _test_bash_told() -> void:
	print("
== 379 amended: a bash told to the one bashed ==")
	var had_noticing := Monster.noticing
	Monster.noticing = false
	var e := _build(["########", "#.Pi...#", "########"])
	var imp: Monster = e["i"][0]
	var player: GridEntity = e["P"][0]
	player.slots[Items.LEFT_HAND] = "shield"
	World.face(player, Vector2i(1, 0))
	World.try_stance(player, "block")
	var told: Array = []
	imp.bashed.connect(func(direction: Vector2i, by: NodePath) -> void: told.append([direction, by]))
	_check(World.try_bash(player, imp), "the player bashes the imp")
	World.step()
	_check(told.size() == 1 and told[0][1] == player.get_path() and (told[0][0] == Vector2i(1, 0) or told[0][0] == Vector2i.ZERO),
			"told once, by the player, driven east or held (%s)" % [told])
	_check(imp.stun_cause == &"bash", "its stagger's cause: &\"%s\"" % imp.stun_cause)
	Monster.noticing = had_noticing


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
		if case == "bold":
			# Not a dart's step out after its own blow (392 amended (5)'s 6-tick
			# wind-up lands in the imp's dart, an 8-tick one did not).
			imp.tactic = Monster.Tactic.PLAIN
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


## Decision 761, enemy-ai's side, in a room whose herds say "balance": a
## wolf smells meat lying and eats it (Balance.eat); a fed one lets the fold
## be at night, a hungry one (Herds.fed) is bold and takes one sheep a night
## (Balance.take_sheep); a town's wolf goes to the store and takes one
## thing (night_take), never goes at people, and killed is one fewer to come.
func _test_balance_wolves() -> void:
	print("\n== keeping the balance (761, enemy-ai's side): meat, the fold, the town's night ==")
	Monster.idling = true
	var rows: Array[String] = ["######################", "#....................#", "#.w..................#",
		"#....................#", "#....................#", "#....................#", "######################"]
	var e := _build(rows)
	var wolf: Animal = e["w"][0]
	_outdoors("clear")
	DayNight.set_hour(12.0)
	var area := World.zone.name
	var open := {}
	for y in rows.size():
		for x in rows[y].length():
			if rows[y][x] != "#":
				open[Vector2i(x, y)] = true
	var stock := Stockpile.new({}, World.steps_now)
	var herds := Herds.new({}, {area: {"floor": open, "outdoor": true, "herds": {"balance": true}}}, {}, World.steps_now)
	herds.camps = func() -> Array: return []
	var balance := Balance.new({}, herds, stock, {}, World.steps_now)
	herds.balance = balance
	balance.id_of = func(_uid: int) -> String: return "meat"
	var removed: Array[int] = []
	balance.remove = func(_area: String, _cell: Vector2i, uid: int, _why: String) -> bool:
		removed.append(uid)
		return true
	var fold_at := Vector2i(18, 4)
	balance.folds = func() -> Array: return [{"id": "t/fold", "area": area, "cell": fold_at, "town": "t/town", "farmer": "Asa"}]
	World.herds = herds
	World.balance = balance
	# Meat lying 10 cells off, by day: it goes and eats.
	balance.cell_changed(area, Vector2i(12, 2), PackedInt32Array([901]), {901: "Asa"})
	var ate := false
	for i in 300:
		World.step()
		if 901 in removed:
			ate = true
			break
	_check(ate and balance.lying(area) == 0 and World.distance(wolf.tile, Vector2i(12, 2)) <= 1,
			"it smells the meat 10 off and eats it where it lies (at %s)" % wolf.tile)
	# The fold, at night: fed, it lets it be; hungry, one sheep, once a night.
	var pack := herds._add_group(area, "wolf", wolf.tile, 1.0)
	wolf.spawn_spec["group"] = str(pack["id"])
	stock.deposit("t/fold", "sheep", 5, "Asa", "a test flock")
	DayNight.set_hour(0.0)
	for i in 200:
		World.step()
	_check(stock.count("t/fold", "sheep") == 5 and not wolf._hungry, "fed, at night it lets the fold be")
	herds._pack_fed["%s/wolf" % area] = 0.2
	var took := false
	for i in 400:
		World.step()
		if stock.count("t/fold", "sheep") < 5:
			took = true
			break
	_check(took and wolf._hungry and wolf._bold, "hungry it is bold, and takes a sheep from the fold at night")
	for i in 300:
		World.step()
	_check(stock.count("t/fold", "sheep") == 4, "one a night: %d left" % stock.count("t/fold", "sheep"))
	# A town's wolf of a night.
	e = _build(["######################", "#....................#", "#.w..................#",
		"#....................#", "#.......P............#", "#....................#", "######################"])
	World.herds = herds
	World.balance = balance
	var town_wolf: Animal = e["w"][0]
	var player: GridEntity = e["P"][0]
	town_wolf.town_wolf = "t/town"
	town_wolf.town_store = [18, 2]
	_outdoors("clear")
	DayNight.set_hour(0.0)
	balance._threats["t/town"] = {"kind": "wolves", "left": 2, "nights": 3}
	stock.deposit("t/town", "meat", 3, "Asa", "a test store")
	var taken := false
	var went_at := false
	for i in 400:
		World.step()
		went_at = went_at or town_wolf.target == player or town_wolf.threatens(player)
		if stock.count("t/town", "meat") < 3:
			taken = true
			break
	_check(taken and stock.count("t/town", "meat") == 2 and not went_at,
			"a town's wolf goes to the store and takes one thing, past a player it lets be")
	town_wolf.remains()
	_check(balance.wolves_at("t/town") == 1, "killed, it is one fewer to come")
	herds.balance = null
	World.herds = null
	World.balance = null
	DayNight.reset()
	_indoors()


## Decision 764: a deer bolts in a burst, then trots; wounded it bleeds
## (never to death) and rests after each burst; low, it goes down and can
## be finished, and gets up in time; a slow stalk from behind goes unheard
## to its side, where it startles a moment before it bolts; a hurried
## approach is heard.
func _test_deer_hunted() -> void:
	print("\n== hunting a deer (764): burst then trot, wounded it tires and goes down, a stalk ==")
	Monster.idling = false
	var rows: Array[String] = ["##############################################"]
	for y in 5:
		rows.append("#............................................#")
	rows.append("##############################################")
	var setup := func(hp: int, doe_at: Vector2i, hunter_at: Vector2i) -> Array:
		_build(rows)
		var doe := EntityFactory.build(SPECS["d"].merged({"name": "Doe", "props": Level.MONSTER_TYPES["deer"]})) as Animal
		_room.add_child(doe)
		World.spawn(doe, doe_at)
		var hunter := EntityFactory.build(SPECS["P"].merged({"name": "Hunter"})) as GridEntity
		_room.add_child(hunter)
		World.spawn(hunter, hunter_at)
		_outdoors("clear")
		World.fields.weather["wind"] = 0.0  # No scent: sight and hearing only.
		DayNight.set_hour(12.0)
		World.face(doe, Vector2i(1, 0))  # Looking away from the hunter (west of her).
		doe.hp = hp
		World.step()
		return [doe, hunter]
	# The burst, then the trot.
	var pair: Array = setup.call(14, Vector2i(10, 3), Vector2i(4, 3))
	var doe: Animal = pair[0]
	var pace := doe._pace
	doe._flee(Vector2i(4, 3))
	World.step()
	_check(is_equal_approx(doe.move_ticks, pace * Animal.BURST_PACE), "she bolts in a burst (%.2f a cell)" % doe.move_ticks)
	for i in Animal.BURST_TICKS + 1:
		World.step()
	_check(doe.alert == Monster.Alert.FLEEING and is_equal_approx(doe.move_ticks, pace), "then trots at her pace (%.2f)" % doe.move_ticks)
	# Wounded: after her burst, a slower trot.
	pair = setup.call(6, Vector2i(10, 3), Vector2i(4, 3))
	doe = pair[0]
	doe._flee(Vector2i(4, 3))
	for i in Animal.BURST_TICKS + 2:
		World.step()
	_check(doe.alert == Monster.Alert.FLEEING and is_equal_approx(doe.move_ticks, pace * Animal.WOUNDED_TROT),
			"wounded, after her burst she trots slower (%.2f a cell)" % doe.move_ticks)
	var trail := World.blood_cells(World.fields.level)
	var fresh := trail.size() >= 3 and trail[2] > 200 and trail[2] <= int(ceil(World.BLOOD_DAYS * DayNight.day_steps / World.TICK_RATE))
	_check(trail.size() / 3 >= 5 and fresh, "and leaves a trail of blood behind her (%d cells, %d s left on one)" % [trail.size() / 3, trail[2] if trail.size() >= 3 else -1])
	World.blood.clear()
	# Bleeding, never to death.
	pair = setup.call(6, Vector2i(30, 3), Vector2i(2, 1))
	doe = pair[0]
	for i in Animal.BLEED_TICKS + 2:
		World.step()
	var bled := doe.hp
	doe.hp = 1
	for i in Animal.BLEED_TICKS * 2 + 2:
		World.step()
	_check(bled == 5 and doe.hp == 1 and doe.spawned, "wounded, she bleeds (6 to %d), never to death (%d)" % [bled, doe.hp])
	# Low: down after her burst, finishable; up in time.
	pair = setup.call(3, Vector2i(10, 3), Vector2i(4, 3))
	doe = pair[0]
	doe._flee(Vector2i(4, 3))
	for i in Animal.BURST_TICKS + 3:
		World.step()
	var down_at := doe.tile
	var hunter: GridEntity = pair[1]
	for i in 60:
		World.step()
	_check(World.tick < doe._down_until and doe.tile == down_at and doe.pose == Monster.Pose.DOWN,
			"low, she goes down after her burst and stays down")
	for i in Animal.DOWN_TICKS:
		World.step()
	_check(doe._down_until < 0 and doe.pose != Monster.Pose.DOWN, "left be, she gets up in time")
	# A slow stalk from behind: unheard to her side, a start, then she bolts.
	pair = setup.call(14, Vector2i(20, 3), Vector2i(14, 3))
	doe = pair[0]
	hunter = pair[1]
	var heeded := false
	while hunter.tile.x < 19:
		for i in Animal.STALK_STEP_TICKS + 2:
			World.step()
			heeded = heeded or doe.alert != Monster.Alert.IDLE
		World.try_move(hunter, Vector2i(1, 0))
	World.step()
	World.step()
	var startled := doe.alert == Monster.Alert.SUSPICIOUS and doe.tile == Vector2i(20, 3)
	for i in Animal.STARTLE_TICKS + 3:
		World.step()
	_check(not heeded and startled and doe.alert == Monster.Alert.FLEEING,
			"stalked slowly from behind she hears nothing; at her side she starts, then bolts (%s)" % Monster.Alert.keys()[doe.alert])
	# Hurried: heard.
	pair = setup.call(14, Vector2i(20, 3), Vector2i(14, 3))
	doe = pair[0]
	hunter = pair[1]
	heeded = false
	while hunter.tile.x < 19 and not heeded:
		for i in 3:
			World.step()
			heeded = heeded or doe.alert != Monster.Alert.IDLE
		World.try_move(hunter, Vector2i(1, 0))
	_check(heeded and hunter.tile.x < 19, "walked up on, she hears it first (at %d)" % hunter.tile.x)
	# Struck: a long burst (a wounding shot costs a chase).
	pair = setup.call(14, Vector2i(10, 3), Vector2i(4, 3))
	doe = pair[0]
	hunter = pair[1]
	World.damage(doe, 6, hunter)
	for i in Animal.BURST_TICKS + 5:
		World.step()
	_check(doe.alert == Monster.Alert.FLEEING and World.tick < doe._burst_until and is_equal_approx(doe.move_ticks, pace * Animal.BURST_PACE),
			"struck, she bolts in a long burst (still at %.2f a cell after %d ticks)" % [doe.move_ticks, Animal.BURST_TICKS + 5])
	# A kill seen: the herd wary, every step heeded, home moved off.
	pair = setup.call(14, Vector2i(20, 3), Vector2i(2, 3))
	doe = pair[0]
	var sister := EntityFactory.build(SPECS["d"].merged({"name": "Sister", "props": Level.MONSTER_TYPES["deer"]})) as Animal
	_room.add_child(sister)
	World.spawn(sister, Vector2i(24, 3))
	World.step()
	var sight := sister.sight_range
	var home_was := sister.home
	doe.remains()
	World.step()
	_check(sister._wary_until > World.tick and sister.sight_range == sight + Animal.WARY_SIGHT and sister.alert == Monster.Alert.FLEEING
			and (home_was == Monster.NO_TILE or World.distance(sister.home, Vector2i(20, 3)) > World.distance(home_was, Vector2i(20, 3))),
			"her herd saw the kill: wary, sees %d farther, runs, and moves its home off" % Animal.WARY_SIGHT)
	for i in Animal.WARY_TICKS:
		World.step()
	_check(not sister.wary(), "in time, calm again")
	# One struck crying out: her herd 35 off is wary too.
	pair = setup.call(14, Vector2i(5, 3), Vector2i(1, 1))
	doe = pair[0]
	hunter = pair[1]
	var far_sister := EntityFactory.build(SPECS["d"].merged({"name": "FarSister", "props": Level.MONSTER_TYPES["deer"]})) as Animal
	_room.add_child(far_sister)
	World.spawn(far_sister, Vector2i(40, 3))
	World.step()
	World.damage(doe, 2, hunter)
	World.step()
	_check(far_sister.wary() and Animal.WARY_REACH == 40, "a deer struck cries out: her herd %d cells off is wary" % World.distance(doe.tile, far_sister.tile))
	# A blow on her unawares, from her side: felled, to be finished; from
	# afar, or on a boar, not.
	pair = setup.call(14, Vector2i(20, 3), Vector2i(19, 3))
	doe = pair[0]
	hunter = pair[1]
	World.damage(doe, 2, hunter)
	for i in 30:
		World.step()
	_check(World.tick < doe._down_until and doe.tile == Vector2i(20, 3) and doe.hp == 12,
			"struck unawares from her side, she is felled where she stood, to be finished")
	var boar := EntityFactory.build(SPECS["o"].merged({"name": "Boar", "props": Level.MONSTER_TYPES["boar"]})) as Animal
	_room.add_child(boar)
	World.spawn(boar, Vector2i(30, 3))
	World.step()
	var boar_hunter := EntityFactory.build(SPECS["P"].merged({"name": "Hunter2"})) as GridEntity
	_room.add_child(boar_hunter)
	World.spawn(boar_hunter, Vector2i(31, 3))
	World.damage(boar, 2, boar_hunter)
	World.step()
	_check(boar._down_until < 0 and not bool(Monster.kinds()["boar"]["felled_by_surprise"]), "a boar so struck is not felled: it turns on them")
	# Chased and struck low, she goes down then, not after another burst.
	pair = setup.call(5, Vector2i(20, 3), Vector2i(17, 3))
	doe = pair[0]
	hunter = pair[1]
	doe._flee(hunter.tile)
	World.step()
	World.damage(doe, 2, hunter)
	World.step()
	_check(World.tick < doe._down_until and doe.hp == 3, "fleeing and struck low (3 of 14), she goes down at once")
	# Her companion stalks with a stalking player.
	pair = setup.call(14, Vector2i(20, 3), Vector2i(14, 3))
	doe = pair[0]
	hunter = pair[1]
	var rhea := Companion.new()
	rhea.keeper = hunter
	rhea.tile = Vector2i(13, 3)
	rhea.step_gap = 3  # Walking at her own pace...
	hunter.step_gap = Animal.STALK_STEP_TICKS + 4  # ...behind a creeping keeper.
	var judged := doe._walker_of(rhea)
	hunter.step_gap = 3
	_check(judged == hunter and doe._walker_of(rhea).step_gap <= Animal.STALK_STEP_TICKS,
			"a companion's step is judged by her keeper's pace: she stalks with him")
	rhea.free()
	# Cornered: along the wall, not standing (playtest's doe stood 4 minutes).
	pair = setup.call(14, Vector2i(1, 1), Vector2i(2, 2))
	doe = pair[0]
	hunter = pair[1]
	var far := World.distance(doe.tile, hunter.tile)
	for i in 40:
		World.step()
		far = maxi(far, World.distance(doe.tile, hunter.tile))
	_check(far >= 4, "in a corner, the hunter at her side, she slips along the wall and away (%d off at most)" % far)
	DayNight.reset()
	_indoors()
	Monster.idling = true


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


## Striking distance, enemy-ai's side (699 amended; combat's spec): on a
## free body a monster takes the strike cell nearest its reach (0.85 of its
## weapon's span), never one chest to chest (under 0.5 + FOE_GAP of the
## body's centre), unless that is all there is.
func _test_strike_reach() -> void:
	print("%s== on a free body a monster strikes from near its reach, not chest to chest; a longer weapon farther; a close cell only when it is all ==" % char(10))
	Monster.idling = false
	var open: Array[String] = ["############"]
	for y in 5:
		open.append("#..........#")
	open.append("############")
	var bare := _strike_from(open, Vector2i(3, 2), Vector2(3.4, 2.0), Vector2i(9, 2), "")
	_check(bare["struck"] and bare["gap"] >= 0.5 + World.FOE_GAP - 0.01,
		"bare-handed (span %.1f), on a free player at the back of its cell: strikes from %s, %.2f off its centre" % [World.span_of({}), bare["from"], bare["gap"]])
	var axe := _strike_from(open, Vector2i(3, 2), Vector2(3.4, 2.0), Vector2i(9, 2), "battle_axe")
	_check(axe["struck"] and axe["wields"] == "battle_axe" and bare["wields"] == "" and axe["gap"] > bare["gap"],
		"with a battle axe (span 1.8) it strikes from farther: %s, %.2f off" % [axe["from"], axe["gap"]])
	var pocket: Array[String] = ["#######", "#######", "#.....#", "#######", "#######"]
	var close := _strike_from(pocket, Vector2i(1, 2), Vector2(1.4, 2.0), Vector2i(5, 2), "")
	_check(close["struck"] and close["from"] == Vector2i(2, 2),
		"in a dead end with only a close cell open, it takes that cell and strikes (%s, %.2f off)" % [close["from"], close["gap"]])
	Monster.idling = true


## A bold robber (armed with [param weapon] alone, or bare-handed) from [param from] on a
## free player held at [param free_pos] in [param cell]: whether it struck,
## from where, and how far that cell is from the player's centre.
func _strike_from(rows: Array[String], cell: Vector2i, free_pos: Vector2, from: Vector2i, weapon: String) -> Dictionary:
	_build(rows)
	var player := EntityFactory.build(SPECS["P"].merged({"name": "HeldFree"})) as Player
	_room.add_child(player)
	World.spawn(player, cell)
	player.free_pos = free_pos
	var reacher := EntityFactory.build(SPECS["x"].merged({"name": "Reacher", "temperament": "bold", "props": Monster.bodies()["robber"]})) as Monster
	_room.add_child(reacher)
	World.spawn(reacher, from)
	reacher._bundle_rolled = true  # Armed as the test says, not from its kind's bundle.
	var hands := Items.tidy([], Items.CARRIED)
	hands[Items.RIGHT_HAND] = weapon
	reacher.slots = Items.tidy([], Items.CARRIED)
	World.set_slots(reacher, hands)
	reacher.sight_range = 12
	reacher.senses.cone_cos = -1.0
	var out := {"struck": false, "from": World.NO_CELL, "gap": 0.0, "wields": World.wielded(reacher)}
	for i in 120:
		var hp := player.hp
		player.free_pos = free_pos
		World.step()
		if player.hp < hp:
			out = {"struck": true, "from": reacher.tile, "gap": Vector2(reacher.tile).distance_to(free_pos), "wields": World.wielded(reacher)}
			break
	World.despawn(reacher)
	World.despawn(player)
	return out


## The old grey (780 amended (15)): he hangs back while his pack lives and
## comes in at an opening; his howl sends his pack in at once, and a blow
## breaks it off; his told lunge bites and he pants after; never into a
## downing; his pack fights his target.
func _test_old_wolf() -> void:
	print("\n== the old grey: hangs back behind his pack, the howl and its rush (broken by a blow), the told lunge and the pant, never into a downing ==")
	Monster.idling = false
	DayNight.set_hour(12.0)
	var row: Dictionary = Monster.kinds()["old_wolf"]
	_check(Monster.is_apex("old_wolf") and str(row["escort"]["kind"]) == "wolf" and int(row["escort"]["count"][0]) == 2 and int(row["lair"]["fall_back_escort"]) == 1
			and (row["drops"] as Array).map(func(d: Dictionary) -> String: return str(d["item"])) == ["grey_pelt", "grey_fang"]
			and not (row["moves"] as Dictionary).has("lunge"),
		"an apex, two wolves his escort, beaten back at one left; his pelt and fang; his spring is his own, not combat's told lunge")
	var rows: Array[String] = ["#".repeat(30)]
	for y in 7:
		rows.append("#" + ".".repeat(28) + "#")
	rows.append("#".repeat(30))
	for put: Array in [[4, 4, "w"], [5, 3, "w"], [5, 5, "w"], [7, 4, "G"], [15, 4, "P"]]:
		rows[put[1]] = rows[put[1]].substr(0, put[0]) + str(put[2]) + rows[put[1]].substr(put[0] + 1)
	var e := _build(rows)
	var grey: OldWolf = e["G"][0]
	var player: GridEntity = e["P"][0]
	var pack: Array = e["w"]
	_check(int(grey.spring["windup"]) == int(row["moves"]["spring"]["windup"]) and int(grey.howl["every"]) == int(row["moves"]["howl"]["every"]),
		"his moves' numbers are his row's (tuning is data)")
	grey.sight_range = 12
	for wolf: Animal in pack:
		wolf.sight_range = 12
		wolf.escort_lead = grey
	World.face(player, Vector2i(-1, 0))  # Facing him: no opening.
	grey._next_howl = World.tick + 100000
	grey._next_spring = World.tick + 100000
	var nearest := 99
	var struck := false
	var pack_fights := false
	for i in 120:
		World.step()
		World.face(player, Senses.way_toward(player.tile, grey.tile))
		if grey.target == player:
			nearest = mini(nearest, World.distance(grey.tile, player.tile))
		struck = struck or _damage_log.any(func(d: Dictionary) -> bool: return d["source"] == grey)
		pack_fights = pack_fights or pack.all(func(wolf: Animal) -> bool: return wolf.target == player)
	_check(grey.target == player and nearest >= int(OldWolf.HANG[0]) - 1 and not struck,
		"while his pack lives he keeps off at the fight's edge (nearest %d) and strikes nobody" % nearest)
	_check(pack_fights, "his pack fights his target")
	World.face(player, Senses.way_toward(grey.tile, player.tile))
	_check(grey._opening(), "his target turned away: his opening")
	World.face(player, Senses.way_toward(player.tile, grey.tile))
	_check(not grey._opening(), "facing him: none")
	# The howl: his pack sent in at once; a blow while he howls breaks it off.
	var cries: Array[StringName] = []
	grey.cried.connect(func(kind: StringName) -> void: cries.append(kind))
	grey._begin_howl()
	_check(cries.has(&"howl") and str(grey._move.get("move", "")) == "howl", "his howl, told (a cry, his head up)")
	for i in int(grey.howl["windup"]) + 1:
		World.step()
	var rushed := pack.filter(func(wolf: Animal) -> bool: return wolf.spawned and wolf._burst_until > World.tick)
	_check(grey._move.is_empty() and rushed.size() >= 2, "at its end his pack about his target darts in at once (%d)" % rushed.size())
	grey._begin_howl()
	grey.note_struck(player)
	_check(grey._move.is_empty(), "struck while he howls, he breaks it off")
	# No lunge into a downing.
	var near_wolf: Animal = pack[0]
	player.hp = player.max_hp / 2 - 1
	World.despawn(near_wolf)
	World.spawn(near_wolf, _free_beside(player.tile))
	_check(not grey._may_lunge(grey.pack()), "his target under half hp with his pack beside them: no lunge")
	player.hp = player.max_hp
	_check(grey._may_lunge(grey.pack()), "whole: he may")
	# Alone, the told lunge: a line, the bite, then the pant.
	for wolf: Animal in pack:
		if wolf.spawned:
			World.despawn(wolf)
	World.despawn(grey)
	World.spawn(grey, player.tile + Vector2i(-3, 0))
	World.face(grey, Vector2i(1, 0))
	grey._move = {}
	grey._next_spring = World.tick
	grey.target = player
	_damage_log.clear()
	var told := false
	var bitten := -1
	for i in 40:
		World.step()
		told = told or str(grey._move.get("move", "")) == "lunge"
		if _damage_log.any(func(d: Dictionary) -> bool: return d["source"] == grey and d["entity"] == player):
			bitten = World.tick
			break
	_check(told and bitten >= 0, "alone, his lunge told on a line, then the bite (%s, %d)" % [told, bitten])
	var at := grey.tile
	var stood := 0
	for i in int(grey.pant["ticks"]) - 2:
		World.step()
		if grey.tile == at and str(grey._move.get("move", "")) == "pant":
			stood += 1
	_check(stood >= int(grey.pant["ticks"]) - 3 and not _damage_log.any(func(d: Dictionary) -> bool: return d["source"] == grey and int(d["tick"]) > bitten),
		"after it he pants, standing, striking nobody: the opening (%d ticks)" % stood)
	DayNight.reset()
	Monster.idling = true


## A told line drawn to where a blow strikes (810 amended): the great
## bear's charge and the old grey's spring at a body off its cell's middle
## (its free centre in the next cell) are told through that cell, not held
## back (the boar king's hold run found the line to the tile missing it).
## A told charge's line stays down until the rush it warns of has stopped
## (810 amended (2); the coordinator's rule, from playtest's king hold run):
## it ended as the rush began, so a rush's far cells were struck unmarked.
func _test_tell_through_rush() -> void:
	print("%s== a told rush's line stays down until the rush stops: the great bear's charge, the old grey's spring (810 amended (2)) ==" % char(10))
	Monster.idling = false
	DayNight.set_hour(12.0)
	for kind: String in ["B", "G"]:
		var rows: Array[String] = ["#".repeat(20)]
		for y in 9:
			rows.append("#" + ".".repeat(18) + "#")
		rows.append("#".repeat(20))
		var at := Vector2i(9, 5) if kind == "B" else Vector2i(8, 5)
		rows[5] = rows[5].substr(0, 5) + kind + rows[5].substr(6)
		rows[at.y] = rows[at.y].substr(0, at.x) + "P" + rows[at.y].substr(at.x + 1)
		var e := _build(rows)
		var beast: Monster = e[kind][0]
		var player: GridEntity = e["P"][0]
		player.protected = false
		player.max_hp = 100
		player.hp = 100
		beast.sight_range = 12
		beast.target = player
		if kind == "B":
			beast.set("_roared_fight", true)
			beast.set("_next_charge", 0)
		else:
			beast.set("_next_howl", World.tick + 100000)
			beast.set("_next_spring", 0)
		beast.call("_special_tick")
		var id := int((beast.get("_move") as Dictionary).get("telegraph", 0))
		var rush_ticks := 0
		var live := 0
		var over := false
		for i in 60:
			World.step()
			if World.rushing(beast):
				rush_ticks += 1
				live += 1 if World.telegraphs().has(id) else 0
			elif rush_ticks > 0:
				over = true
				break
		_check(id != 0 and rush_ticks > 0 and live == rush_ticks and over and not World.telegraphs().has(id),
			"the %s's told line live at every tick of its rush (%d of %d), ended once it stopped" % ["great bear" if kind == "B" else "old grey", live, rush_ticks])
	DayNight.reset()
	Monster.idling = true


func _test_aim_struck_cell() -> void:
	print("%s== the great bear's charge and the old grey's spring at a body off its cell's middle: told through where it is struck (810 amended) ==" % char(10))
	Monster.idling = false
	DayNight.set_hour(12.0)
	for kind: String in ["B", "G"]:
		var rows: Array[String] = ["#".repeat(20)]
		for y in 9:
			rows.append("#" + ".".repeat(18) + "#")
		rows.append("#".repeat(20))
		var at := Vector2i(9, 5) if kind == "B" else Vector2i(8, 5)
		rows[5] = rows[5].substr(0, 5) + kind + rows[5].substr(6)
		rows[at.y] = rows[at.y].substr(0, at.x) + "P" + rows[at.y].substr(at.x + 1)
		var e := _build(rows)
		var beast: Monster = e[kind][0]
		var player: GridEntity = e["P"][0]
		player.protected = false
		player.max_hp = 100
		player.hp = 100
		beast.sight_range = 12
		beast.target = player
		player.free_pos = Vector2(at) + Vector2(0.0, 0.6)
		var struck := World.struck_cell(player)
		var move := "charge" if kind == "B" else "lunge"
		if kind == "B":
			beast.set("_roared_fight", true)
			beast.set("_next_charge", 0)
		else:
			beast.set("_next_howl", World.tick + 100000)
			beast.set("_next_spring", 0)
		beast.call("_special_tick")
		var begun: Dictionary = beast.get("_move")
		var told: Array[Vector2i] = []
		if begun.has("shape"):
			told = World.telegraph_cells(begun["shape"])
		_check(struck != player.tile and str(begun.get("move", "")) == move and struck in told,
			"the %s's %s at a body struck at %s (its tile %s): told, through it" % ["great bear" if kind == "B" else "old grey", move, struck, player.tile])
		if int(begun.get("telegraph", 0)) != 0:
			World.end_telegraph(int(begun["telegraph"]), false)
	# The base told strikes (combat's ruling: a told blow strikes its told
	# cells, who is in one World.struck_cell): an ambush and a lunge at a body
	# off its cell's middle tell the cell it is struck in.
	var rows: Array[String] = ["##############", "#............#", "#.s..........#", "#............#", "##############"]
	var e := _build(rows, {"s": {"named": "skeech", "facing": Vector2i(1, 0)}})
	var skeech: Monster = e["s"][0]
	var someone := EntityFactory.build(SPECS["P"].duplicate(true).merged({"name": "Player1"})) as Player
	_room.add_child(someone)
	World.spawn(someone, Vector2i(3, 2))
	someone.free_pos = Vector2(3.0, 2.6)
	var at := World.struck_cell(someone)
	var begun := skeech.begin_ambush(someone)
	var cells: Array = skeech._ambush.get("cells", [])
	_check(at != someone.tile and begun and at in cells,
		"the ambush at a body struck at %s (its tile %s): its told cell is that one (%s)" % [at, someone.tile, cells])
	if begun:
		World.end_telegraph(int(skeech._ambush["telegraph"]), false)
	var pair := _lunge_room()
	var robber: Monster = pair[0]
	var player: Player = pair[1]
	player.free_pos = Vector2(3.0, 2.6)
	at = World.struck_cell(player)
	begun = robber.begin_lunge(player)
	cells = robber._ambush.get("cells", [])
	_check(at != player.tile and begun and at in cells,
		"the lunge at a body struck at %s (its tile %s): told through it (%s)" % [at, player.tile, cells])
	if begun:
		World.end_telegraph(int(robber._ambush["telegraph"]), false)
	DayNight.reset()
	Monster.idling = true


## The boar king (780 amended (16)): off while his lair is held back; his
## told charge lands, gores and knocks aside; a miss skids him, a wall stuns
## him (&"crash"); never at a foe under a third of their hp, and never
## below 1 hp; his sounder joins his charge, and holds off a low foe while
## he charges.
func _test_boar_king() -> void:
	print("
== the boar king: the told charge, the skid, the crash, never into a downing, his sounder ==")
	Monster.idling = false
	DayNight.set_hour(12.0)
	var row: Dictionary = Monster.kinds()["boar_king"]
	_check(Monster.is_apex("boar_king") and str(row["escort"]["kind"]) == "boar" and int(row["escort"]["count"][0]) == 3
			and int(row["lair"]["fall_back_escort"]) == 0 and str(row["lair"]["zone"]) == "boar_lair"
			and (row["drops"] as Array).map(func(d: Dictionary) -> String: return str(d["item"])) == ["boar_king_tusk", "boar_king_hide", "meat"],
		"an apex, a sounder of three boars his escort, beaten back with it cleared; his tusk, hide and meat")
	_check(Apex.rows().has("boar_king") == not Level.SHELVED.has("boar_lair") and Apex.rows().has("old_wolf"),
		"while the boar's lair is held back (SHELVED) Apex holds no boar king: he is in the world only with his lair")
	var arena: Array[String] = ["#".repeat(30)]
	for y in 9:
		arena.append("#" + ".".repeat(28) + "#")
	arena.append("#".repeat(30))
	var put := func(rows: Array[String], at: Vector2i, symbol: String) -> void:
		rows[at.y] = rows[at.y].substr(0, at.x) + symbol + rows[at.y].substr(at.x + 1)
	# The charge told, then run: the foe met gored and knocked aside.
	var rows := arena.duplicate()
	put.call(rows, Vector2i(5, 5), "K")
	put.call(rows, Vector2i(11, 5), "P")
	var e := _build(rows)
	var king: BoarKing = e["K"][0]
	var player: GridEntity = e["P"][0]
	_check(int(king.charge["windup"]) == int(row["moves"]["charge"]["windup"]) and float(king.charge["not_below"]) == float(row["moves"]["charge"]["not_below"]),
		"his charge's numbers are his row's (tuning is data)")
	player.max_hp = 100
	player.hp = 100
	king.sight_range = 12
	var cries: Array[StringName] = []
	king.cried.connect(func(kind: StringName) -> void: cries.append(kind))
	var told := -1
	var gored := -1
	var from_y := player.tile.y
	for i in 60:
		World.step()
		if told < 0 and str(king._move.get("move", "")) == "charge":
			told = World.tick
		if _damage_log.any(func(d: Dictionary) -> bool: return d["source"] == king and d["entity"] == player):
			gored = World.tick
			break
	_check(told >= 0 and cries.has(&"snort") and gored > told + int(king.charge["windup"]) - 2 and cries.has(&"charge"),
		"his charge told (a snort, a line) and run (its cry), then the blow (told %d, struck %d)" % [told, gored])
	for i in 4:
		World.step()
	_check(player.tile.y != from_y, "the one he met knocked aside off his line (row %d to %d)" % [from_y, player.tile.y])
	# A miss: he runs to its end and skids, standing, his flank open.
	rows = arena.duplicate()
	put.call(rows, Vector2i(4, 5), "K")
	put.call(rows, Vector2i(9, 5), "P")
	e = _build(rows)
	king = e["K"][0]
	player = e["P"][0]
	player.max_hp = 100
	player.hp = 100
	king.sight_range = 12
	cries = []
	king.cried.connect(func(kind: StringName) -> void: cries.append(kind))
	var stepped_off := false
	var skidded := -1
	for i in 60:
		World.step()
		if not stepped_off and str(king._move.get("move", "")) == "charge":
			stepped_off = true
			World.despawn(player)
			World.spawn(player, Vector2i(9, 8))  # Aside, off his line.
		if str(king._move.get("move", "")) == "skid":
			skidded = World.tick
			break
	_check(skidded >= 0 and cries.has(&"skid") and not _damage_log.any(func(d: Dictionary) -> bool: return d["source"] == king),
		"stepped aside, his charge meets nobody: he skids (%d)" % skidded)
	var at := king.tile
	var stood := 0
	for i in int(king.charge["skid"]) - 2:
		World.step()
		if king.tile == at:
			stood += 1
	_check(stood >= int(king.charge["skid"]) - 3, "skidding he stands (%d ticks): the opening" % stood)
	# A wall at its end: stunned, its cause the crash.
	rows = arena.duplicate()
	put.call(rows, Vector2i(20, 5), "K")
	put.call(rows, Vector2i(27, 5), "P")
	e = _build(rows)
	king = e["K"][0]
	player = e["P"][0]
	player.max_hp = 100
	player.hp = 100
	king.sight_range = 12
	var crashed := false
	stepped_off = false
	for i in 60:
		World.step()
		if not stepped_off and str(king._move.get("move", "")) == "charge":
			stepped_off = true
			World.despawn(player)
			World.spawn(player, Vector2i(27, 8))
		if World.is_stunned(king) and king.stun_cause == &"crash":
			crashed = true
			break
	_check(crashed, "run into the wall, he is stunned, its cause the crash")
	# His sounder (the coordinator's ruling after playtest's run): one boar at
	# his target at a time, the rest ringing; nobody at a dodge's opening; a
	# dodged charge sends nobody, a hit one the one; at a low foe, one of them.
	rows = arena.duplicate()
	put.call(rows, Vector2i(5, 5), "K")
	put.call(rows, Vector2i(11, 5), "P")
	put.call(rows, Vector2i(10, 3), "o")
	put.call(rows, Vector2i(12, 3), "o")
	put.call(rows, Vector2i(11, 8), "o")
	e = _build(rows)
	king = e["K"][0]
	player = e["P"][0]
	var sounder: Array = e["o"]
	for boar: Animal in sounder:
		boar.escort_lead = king
		boar.sight_range = 12
	player.max_hp = 200
	player.hp = 200
	player.protected = false
	king.sight_range = 12
	king._next_charge = World.tick + 100000  # His plain fight, no charge.
	var striking := {}
	var ringed := 0
	_damage_log.clear()
	for i in 150:
		World.step()
		if i > 40:
			ringed = maxi(ringed, sounder.filter(func(b: Animal) -> bool:
				return b.spawned and World.distance(b.tile, player.tile) >= Animal.SOUNDER_RING.x and World.distance(b.tile, player.tile) <= Animal.SOUNDER_RING.y + 1).size())
	for d: Dictionary in _damage_log:
		if sounder.has(d["source"]):
			striking[d["source"]] = true
	_check(striking.size() == 1 and ringed >= 2,
		"one boar of his sounder at his target at a time (%d struck), the rest ringing it (%d)" % [striking.size(), ringed])
	# His opening: skidding, nobody strikes.
	king._move = {"move": "skid", "telegraph": 0, "lands": World.tick + 15, "from": World.tick}
	_damage_log.clear()
	for i in 14:
		World.step()
	_check(not _damage_log.any(func(d: Dictionary) -> bool: return sounder.has(d["source"]) or d["source"] == king),
		"while he skids, nobody strikes: the dodge's opening is whole")
	# A dodged charge sends nobody; a hit one sends the one.
	for boar: Animal in sounder:
		boar._burst_until = -1
	king.target = player
	king._move = {"move": "rush", "toward": Vector2(1, 0)}
	World.rush_ended.emit(king, "arrived", king.tile, {"struck": []})
	_check(sounder.all(func(b: Animal) -> bool: return b._burst_until < 0), "a dodged charge: none of his sounder sent in")
	king._move = {"move": "rush", "toward": Vector2(1, 0)}
	World.rush_ended.emit(king, "body", king.tile, {"struck": [{"body": player}]})
	_damage_log.clear()
	var hushed := true
	for i in int(king.charge["quiet"]) - 1:
		World.step()
		hushed = hushed and not _damage_log.any(func(d: Dictionary) -> bool: return sounder.has(d["source"]))
	var early := sounder.filter(func(b: Animal) -> bool: return b._burst_until > World.tick).size()
	for i in 3:
		World.step()
	_check(hushed and early == 0 and sounder.filter(func(b: Animal) -> bool: return b._burst_until > World.tick).size() == 1,
		"a charge that hits: no boar strikes for %d ticks (the charge is the hit), then the one sent in (%d early)" % [int(king.charge["quiet"]), early])
	# Never into a downing: no charge at a third, and one of them at such a foe.
	king._move = {}
	player.hp = 50
	_check(not king.may_charge(player), "a foe under a third of their hp: no charge")
	_damage_log.clear()
	var piled := 0
	for i in 80:
		World.step()
		player.hp = 50
		var king_in := king._in_strike_reach(player) or World.distance(king.tile, player.tile) <= 1
		if king_in and _damage_log.any(func(d: Dictionary) -> bool: return sounder.has(d["source"]) and int(d["tick"]) == World.tick):
			piled += 1
	_check(piled == 0, "at a low foe his sounder strikes not while he can (%d ticks of both)" % piled)
	player.hp = 2
	king._gore(player, Vector2(1, 0))
	_check(player.hp == 1, "his charge's blow never takes a player below 1 hp (%d)" % player.hp)
	DayNight.reset()
	Monster.idling = true


## His aim at a body off its cell's middle (playtest's hold run, the
## coordinator's forcing of its cause): mid back-off at the run's two clear
## spots, the bot's free centre set off its tile's middle; each offset
## charges, none paws again.
## His told line stays down until his run stops (810 amended (2), his half;
## the coordinator: before he is unshelved).
func _test_boar_king_tell_through_rush() -> void:
	print("%s== the boar king's told line live at every tick of his run (810 amended (2)) ==" % char(10))
	Monster.idling = false
	DayNight.set_hour(12.0)
	var rows: Array[String] = ["#".repeat(30)]
	for y in 14:
		rows.append("#" + ".".repeat(28) + "#")
	rows.append("#".repeat(30))
	rows[7] = rows[7].substr(0, 6) + "K" + rows[7].substr(7, 5) + "P" + rows[7].substr(13)
	var e := _build(rows)
	var king: BoarKing = e["K"][0]
	var player: GridEntity = e["P"][0]
	player.protected = false
	player.max_hp = 100
	player.hp = 100
	king.sight_range = 12
	king.target = player
	king._next_charge = 0
	king._move = {"move": "back", "telegraph": 0, "lands": World.tick + 14, "from": World.tick}
	var id := 0
	var rush_ticks := 0
	var live := 0
	var over := false
	for i in 80:
		World.step()
		if id == 0 and str(king._move.get("move", "")) == "charge":
			id = int(king._move.get("telegraph", 0))
		if World.rushing(king):
			rush_ticks += 1
			live += 1 if World.telegraphs().has(id) else 0
		elif rush_ticks > 0:
			over = true
			break
	_check(id != 0 and rush_ticks > 0 and live == rush_ticks and over and not World.telegraphs().has(id),
		"his told line live at every tick of his run (%d of %d), ended once it stopped" % [live, rush_ticks])
	DayNight.reset()
	Monster.idling = true


func _test_boar_king_aim() -> void:
	print("%s== the boar king's aim at a body off its cell's middle: clear, he charges ==" % char(10))
	var pawed: Array[String] = []
	var charged := 0
	Monster.idling = false
	DayNight.set_hour(12.0)
	var arena: Array[String] = ["#".repeat(30)]
	for y in 14:
		arena.append("#" + ".".repeat(28) + "#")
	arena.append("#".repeat(30))
	var put := func(rows: Array[String], at: Vector2i, symbol: String) -> void:
		rows[at.y] = rows[at.y].substr(0, at.x) + symbol + rows[at.y].substr(at.x + 1)
	var offs: Array[Vector2] = [Vector2.ZERO, Vector2(0.6, 0.0), Vector2(-0.6, 0.0), Vector2(0.0, 0.6), Vector2(0.0, -0.6),
		Vector2(0.6, 0.6), Vector2(-0.6, -0.6), Vector2(0.6, -0.6), Vector2(-0.6, 0.6), Vector2(0.45, 0.0), Vector2(0.0, 0.45)]
	for spot: Array in [[Vector2i(9, 11), Vector2i(12, 8)], [Vector2i(9, 4), Vector2i(12, 7)]]:
		for off: Vector2 in offs:
			var rows := arena.duplicate()
			put.call(rows, spot[0], "K")
			put.call(rows, spot[1], "P")
			var e := _build(rows)
			var king: BoarKing = e["K"][0]
			var player: GridEntity = e["P"][0]
			player.protected = false
			player.max_hp = 100
			player.hp = 100
			king.sight_range = 12
			king.target = player
			king._next_charge = 0
			player.free_pos = Vector2(spot[1]) + off
			var sc := World.struck_cell(player)
			king._move = {"move": "back", "telegraph": 0, "lands": World.tick + 14, "from": World.tick}
			var result := "none"
			for i in 10:
				World.step()
				var mv := str(king._move.get("move", ""))
				if mv == "charge" or mv == "paw":
					result = mv
					break
			if result == "charge":
				charged += 1
			else:
				pawed.append("%s %s" % [spot[0], off])
			print("  PROBE-AIM %s->%s off %s struck %s tile %s after %s: %s (king at %s)" % [spot[0], spot[1], off, sc, player.tile, World.struck_cell(player), result, king.tile])
	_check(pawed.is_empty(), "clear at both spots, every offset of the body: a told charge (%d), no paw again %s" % [charged, pawed])
	DayNight.reset()
	Monster.idling = true


## The boar king up close (780 amended (16), his back-off; playtest's run:
## a foe kept close never saw a charge): his charge ready, a foe under
## "from" off, he stands pawing on his snort, backs off facing them, and
## charges from "from" clear; followed step for step, the short charge from
## where he stands; his bite one each 30 ticks, 3 hp.
func _test_boar_king_close() -> void:
	print("%s== the boar king up close: he backs off and charges; followed, the short charge; his bite slow ==" % char(10))
	Monster.idling = false
	DayNight.set_hour(12.0)
	var row: Dictionary = Monster.kinds()["boar_king"]
	var arena: Array[String] = ["#".repeat(30)]
	for y in 9:
		arena.append("#" + ".".repeat(28) + "#")
	arena.append("#".repeat(30))
	var put := func(rows: Array[String], at: Vector2i, symbol: String) -> void:
		rows[at.y] = rows[at.y].substr(0, at.x) + symbol + rows[at.y].substr(at.x + 1)
	for follow: bool in [false, true]:
		var rows := arena.duplicate()
		put.call(rows, Vector2i(14, 5), "K")
		put.call(rows, Vector2i(15, 5), "P")
		var e := _build(rows)
		var king: BoarKing = e["K"][0]
		var player: GridEntity = e["P"][0]
		player.protected = false
		player.max_hp = 100
		player.hp = 100
		king.sight_range = 12
		king.target = player
		var cries: Array[StringName] = []
		king.cried.connect(func(kind: StringName) -> void: cries.append(kind))
		var start := World.tick
		var pawed := -1
		var paw_tile := Vector2i(-1, -1)
		var still := true
		var faced := true
		var backed := 0
		var told := -1
		var run := 0
		for i in 60:
			World.step()
			var move := str(king._move.get("move", ""))
			if move == "paw":
				if pawed < 0:
					pawed = World.tick
					paw_tile = king.tile
				still = still and king.tile == paw_tile
			if move == "back":
				backed = maxi(backed, World.distance(king.tile, paw_tile))
				faced = faced and king.facing == Senses.way_toward(king.tile, player.tile)
			if move == "charge":
				told = World.tick
				run = int(king._move["cells"])
				break
			if follow and World.distance(player.tile, king.tile) > 1:
				World.try_move(player, Senses.way_toward(player.tile, king.tile))
		var snorts := cries.count(&"snort")
		if not follow:
			_check(pawed >= 0 and still and snorts == 1 and backed >= int(king.charge["from"]) - 1 and faced,
				"a foe at his side: he stands pawing on one snort, then backs off facing them (%d cells, still %s, faced %s, %d snorts)" % [backed, still, faced, snorts])
			_check(told >= 0 and told - start <= 30 and run >= int(king.charge["from"]),
				"and charges from clear of them, told within 3 s (%d ticks, a run of %d)" % [told - start, run])
		else:
			_check(told >= 0 and told - start <= int(king.charge["paw"]) + int(king.charge["back"]) + 3 and run <= int(king.charge["from"]),
				"followed step for step, he gets no room: the short charge from where he stands (%d ticks, a run of %d)" % [told - start, run])
	# His bite, close, his charge not ready: one each 30 ticks, 3 hp.
	var rows := arena.duplicate()
	put.call(rows, Vector2i(14, 5), "K")
	put.call(rows, Vector2i(15, 5), "P")
	var e := _build(rows)
	var king: BoarKing = e["K"][0]
	var player: GridEntity = e["P"][0]
	player.protected = false
	player.max_hp = 100
	player.hp = 100
	king.sight_range = 12
	king.target = player
	king._next_charge = World.tick + 100000
	_damage_log.clear()
	for i in 150:
		World.step()
	var bites: Array = _damage_log.filter(func(d: Dictionary) -> bool: return d["source"] == king and d["entity"] == player)
	var gap := 1 << 30
	for k in range(1, bites.size()):
		gap = mini(gap, int(bites[k]["tick"]) - int(bites[k - 1]["tick"]))
	_check(int(row["body"]["attack_ticks"]) == 30 and int(row["body"]["attack_damage"]) == 3 and bites.size() >= 2 and gap >= 28
			and bites.all(func(d: Dictionary) -> bool: return int(d["amount"]) <= 3),
		"his bite slow and light: %d in 15 s, the shortest gap %d ticks, %s hp" % [bites.size(), gap, bites.map(func(d: Dictionary) -> int: return int(d["amount"]))])
	# His charge's hit: "damage" in all, its knock-aside's impact part of it.
	player.hp = 100
	king.hp = king.max_hp
	_damage_log.clear()
	king._gore(player, Vector2(1, 0))
	for i in 4:
		World.step()
	var gored := 100 - player.hp
	_check(gored == int(king.charge["damage"]),
		"his charge's hit, knock-aside and all, is %d hp, not more (%d)" % [int(king.charge["damage"]), gored])
	# Low, in his lair: he breaks off to his wallow, never fleeing; struck on
	# the way, he bites back at the one beside him, but neither chases nor
	# charges.
	rows = arena.duplicate()
	put.call(rows, Vector2i(20, 5), "K")
	put.call(rows, Vector2i(21, 5), "P")
	e = _build(rows)
	king = e["K"][0]
	player = e["P"][0]
	player.protected = false
	player.max_hp = 100
	player.hp = 100
	king.den = Vector2i(4, 5)
	king.sight_range = 12
	king.hp = int(float(king.max_hp) * float(king.charge["wallow_below"])) - 1
	king.target = player
	king.note_struck(player)
	_damage_log.clear()
	var fled := false
	var charged := false
	var from_den := World.distance(king.tile, king.den)
	for i in 12:
		World.step()
		fled = fled or king.alert == Monster.Alert.FLEEING
		charged = charged or str(king._move.get("move", "")) in ["paw", "back", "charge", "rush"]
	var bit := _damage_log.any(func(d: Dictionary) -> bool: return d["source"] == king and d["entity"] == player)
	for i in 80:
		World.step()
		fled = fled or king.alert == Monster.Alert.FLEEING
		charged = charged or str(king._move.get("move", "")) in ["paw", "back", "charge", "rush"]
	_check(not fled and not charged and king.target == null and World.distance(king.tile, king.den) <= from_den - 8,
		"under his wallow line he breaks off home, never fleeing nor charging (%d to %d from his den)" % [from_den, World.distance(king.tile, king.den)])
	_check(bit and World.distance(player.tile, Vector2i(21, 5)) == 0,
		"struck on his way, he bites back at the one beside him, not chasing them (bit %s)" % bit)
	# Aimed where a blow strikes: a free body off its cell's middle (its
	# centre in the next cell) still gets the charge (playtest's hold run).
	rows = arena.duplicate()
	put.call(rows, Vector2i(10, 4), "K")
	put.call(rows, Vector2i(14, 4), "P")
	e = _build(rows)
	king = e["K"][0]
	player = e["P"][0]
	player.protected = false
	player.max_hp = 100
	player.hp = 100
	king.sight_range = 12
	king.target = player
	player.free_pos = Vector2(14.0, 4.6)
	var off_cell := World.struck_cell(player)
	var aimed := king._try_charge(World.distance(king.tile, off_cell) + int(king.charge["past"]), true)
	_check(off_cell != player.tile and aimed and off_cell in king.told_line,
		"a body off its cell's middle (struck at %s, its tile %s): his charge told through where it is struck" % [off_cell, player.tile])
	World.end_telegraph(int(king._move.get("telegraph", 0)), false)
	# A rock behind him: he backs off aside and still charges a held foe.
	rows = arena.duplicate()
	put.call(rows, Vector2i(14, 5), "K")
	put.call(rows, Vector2i(15, 5), "P")
	for at: Vector2i in [Vector2i(13, 4), Vector2i(13, 5), Vector2i(13, 6), Vector2i(12, 5)]:
		put.call(rows, at, "#")
	e = _build(rows)
	king = e["K"][0]
	player = e["P"][0]
	player.protected = false
	player.max_hp = 100
	player.hp = 100
	king.sight_range = 12
	king.target = player
	var start := World.tick
	var told := -1
	var paws := 0
	for i in 60:
		World.step()
		if str(king._move.get("move", "")) == "paw" and int(king._move["from"]) == World.tick - 1:
			paws += 1
		if str(king._move.get("move", "")) == "charge":
			told = World.tick
			break
	_check(told >= 0 and told - start <= 30 and paws <= 1,
		"a rock behind him, a foe held at his side: one paw, a charge told (%d ticks, %d paws)" % [told - start, paws])
	# His move windows are his: no boar of his sounder strikes while he paws,
	# backs off, tells, runs, skids or lies stunned, nor "quiet" after a hit;
	# held still, a told charge at least once in 100 ticks.
	rows = arena.duplicate()
	put.call(rows, Vector2i(14, 5), "K")
	put.call(rows, Vector2i(15, 5), "P")
	for at: Vector2i in [Vector2i(17, 3), Vector2i(17, 7), Vector2i(13, 8)]:
		put.call(rows, at, "o")
	e = _build(rows)
	king = e["K"][0]
	player = e["P"][0]
	var boars: Array = e["o"]
	for boar: Animal in boars:
		boar.escort_lead = king
		boar.escort_follow = 4
	player.protected = false
	player.max_hp = 200
	player.hp = 200
	king.sight_range = 12
	king.target = player
	_damage_log.clear()
	var in_window := 0
	var tells: Array[int] = []
	var boar_hp := 0
	var all_hp := 0
	var was := ""
	for i in 300:
		var windowed := king.in_move_window() or World.tick < king._quiet_until
		World.step()
		player.hp = maxi(player.hp, 150)
		var move := str(king._move.get("move", ""))
		if move == "charge" and was != "charge":
			tells.append(World.tick)
		was = move
		for d: Dictionary in _damage_log:
			if int(d["tick"]) != World.tick or d["entity"] != player:
				continue
			all_hp += int(d["amount"])
			if boars.has(d["source"]):
				boar_hp += int(d["amount"])
				if windowed:
					in_window += 1
	var gaps_ok := tells.size() >= 3
	for k in range(1, tells.size()):
		gaps_ok = gaps_ok and tells[k] - tells[k - 1] <= 100
	_check(in_window == 0, "no boar of his sounder strikes in his move windows or the quiet after a hit (%d)" % in_window)
	_check(gaps_ok and (all_hp == 0 or float(boar_hp) / float(all_hp) < 0.4),
		"held still, a told charge at least each 100 ticks (%s), his boars under 40%% of the harm (%d of %d)" % [tells, boar_hp, all_hp])
	# A foe by his den: going home is no retreat; away and alone, the far
	# way, never through their reach.
	rows = arena.duplicate()
	put.call(rows, Vector2i(8, 5), "K")
	put.call(rows, Vector2i(7, 6), "P")
	e = _build(rows)
	king = e["K"][0]
	player = e["P"][0]
	player.protected = false
	player.max_hp = 100
	player.hp = 100
	king.den = Vector2i(6, 5)
	king.sight_range = 12
	king.hp = int(float(king.max_hp) * float(king.charge["wallow_below"])) - 1
	king.target = player
	var nearest := 99
	for i in 80:
		World.step()
		if i >= 3:
			nearest = mini(nearest, World.distance(king.tile, player.tile))
	_check(king._wallow_far and World.distance(king.tile, player.tile) >= BoarKing.WALLOW_CLEAR and nearest >= 2
			and king.target == null,
		"a foe by his den: he goes the far way, %d off them, never back through their reach (nearest %d), and stands alone" % [World.distance(king.tile, player.tile), nearest])
	DayNight.reset()
	Monster.idling = true


## Broken off the far way and followed (the coordinator, for his unshelve):
## a plain walker at a player's pace who follows him step for step from his
## first step away corners him, and a fight is his again, inside 150 ticks;
## striking him too, it ends him inside 150. In the open: his roam of his den
## lies clear of every wall, and none is beside him when cornered.
func _test_boar_king_far_chase() -> void:
	print("%s== the boar king broken off the far way, followed: cornered and ended inside 15 s, no wall ==" % char(10))
	Monster.idling = false
	DayNight.set_hour(12.0)
	var arena: Array[String] = ["#".repeat(46)]
	for y in 25:
		arena.append("#" + ".".repeat(44) + "#")
	arena.append("#".repeat(46))
	var den := Vector2i(23, 13)
	for strikes: bool in [false, true]:
		var rows := arena.duplicate()
		rows[13] = rows[13].substr(0, 24) + "K" + rows[13].substr(25)
		rows[13] = rows[13].substr(0, 22) + "P" + rows[13].substr(23)
		var e := _build(rows)
		var king: BoarKing = e["K"][0]
		var player: GridEntity = e["P"][0]
		player.protected = false
		player.max_hp = 100
		player.hp = 100
		king.den = den
		king.sight_range = 12
		king.hp = int(float(king.max_hp) * float(king.charge["wallow_below"])) - 1
		king.target = player
		king.note_struck(player)
		var reach := king.wander_radius * 2 + 2
		var open := den.x - reach >= 2 and den.x + reach <= 43 and den.y - reach >= 2 and den.y + reach <= 24
		var from_tile := king.tile
		var first_away := -1
		var cornered := -1
		var died := -1
		var walled := false
		var far := false
		var steps := 0
		var last_tile := king.tile
		var next_strike := 0
		_damage_log.clear()
		for i in 400:
			if strikes and World.distance(player.tile, king.tile) <= 1 and World.tick >= next_strike:
				World.face(player, king.tile - player.tile)
				if World.try_attack(player, king):
					next_strike = World.tick + World.attack_ticks_of(player)
			elif World.distance(player.tile, king.tile) > 1:
				World.try_move(player, Senses.way_toward(player.tile, king.tile))
			World.step()
			far = far or king._wallow_far
			if not king.spawned or king.hp <= 0:
				died = World.tick
				break
			if king.tile != last_tile:
				steps += 1
				last_tile = king.tile
				if first_away < 0 and king.tile != from_tile:
					first_away = World.tick
			if first_away >= 0 and cornered < 0 and king._wallow_far and (king.target != null or str(king._move.get("move", "")) != ""):
				cornered = World.tick
				for way: Vector2i in World.DIRECTIONS:
					walled = walled or not World.is_walkable(king.tile + way)
				if not strikes:
					break
		if not strikes:
			_check(far and open and first_away >= 0 and cornered >= 0 and cornered - first_away <= 150 and not walled,
				"followed by a walker, the far way, he is cornered and fights in %d ticks from his first step away (%d steps; roam clear of walls %s, a wall beside him %s)" % [cornered - first_away if cornered >= 0 else -1, steps, open, walled])
		else:
			_check(far and first_away >= 0 and died >= 0 and died - first_away <= 150,
				"followed and struck, the far way, he falls %d ticks after his first step away (%d steps)" % [died - first_away if died >= 0 else -1, steps])
	DayNight.reset()
	Monster.idling = true


## The old grey as the server lays him (Apex._lay names him "Apex_old_wolf",
## and his name seeds his roll: Monster's _rng) at [param at] in this room.
## His roll is asserted where he's measured, so a rename or a change to the
## seed fails a test rather than quietly changing him.
func _live_grey(at: Vector2i) -> OldWolf:
	var spec := Level._spec_for("monster_old_wolf", Level.MONSTER_TYPES)
	spec["name"] = ("Apex_" + "old_wolf").validate_node_name()
	spec["tile"] = at
	Level.arm(spec)
	var grey := EntityFactory.build(spec) as OldWolf
	_room.add_child(grey)
	World.spawn(grey, at)
	return grey


## His lunge strikes only who its told line shows (780 amended (23), the
## coordinator's ruling: step off the red and you're clear): a player who
## steps one cell off the line before it lands takes nothing from it though
## his run ends beside her, and he pants all the same (the missed lunge the
## reader's opening); one left on it is bitten and dragged toward his pack.
func _test_old_wolf_lunge_line() -> void:
	print("%s== the old grey's lunge: off its told line you're clear; on it you're bitten and dragged ==" % char(10))
	Monster.idling = false
	DayNight.set_hour(12.0)
	for case: String in ["on", "beside"]:
		var rows: Array[String] = ["#".repeat(20)]
		for y in 11:
			rows.append("#" + ".".repeat(18) + "#")
		rows.append("#".repeat(20))
		rows[5] = rows[5].substr(0, 10) + "P" + rows[5].substr(11)
		var e := _build(rows)
		var player: GridEntity = e["P"][0]
		player.protected = false
		player.max_hp = 1000
		player.hp = 1000
		var grey := _live_grey(Vector2i(7, 5))
		var mate_spec := Level._spec_for("monster_wolf", Level.MONSTER_TYPES)
		mate_spec["name"] = "Mate"
		mate_spec["tile"] = Vector2i(10, 10)
		var mate := EntityFactory.build(mate_spec) as Monster
		_room.add_child(mate)
		World.spawn(mate, Vector2i(10, 10))
		mate.acts = false  # His one mate stands off: a drag's way, and no howl (that takes two).
		grey.target = player
		grey.sight_range = 12
		grey._next_spring = 0
		_damage_log.clear()
		var told: Array[Vector2i] = []
		for i in 60:
			World.step()
			if str(grey._move.get("move", "")) == "lunge":
				var shown: Dictionary = World.telegraphs().get(int(grey._move["telegraph"]), {})
				for c: Array in shown.get("cells", []):
					told.append(Vector2i(int(c[0]), int(c[1])))
				break
		_check(not told.is_empty() and player.tile in told, "%s: he tells his lunge at her (%s)" % [case, told])
		if case == "beside":
			var aside := Vector2i(0, 1) if not player.tile + Vector2i(0, 1) in told else Vector2i(0, -1)
			for i in 6:
				if World.try_move(player, aside):
					break
				World.step()
			_check(not World.struck_cell(player) in told, "beside: she stands one cell off his line, at %s" % player.tile)
		var before := player.tile
		var panted := false
		for i in 40:
			World.step()
			if str(grey._move.get("move", "")) == "pant":
				panted = true
				break
		var bit := 0
		for d: Dictionary in _damage_log:
			if d["entity"] == player and d["source"] == grey:
				bit += int(d["amount"])
		if case == "on":
			_check(bit > 0 and World.distance(player.tile, mate.tile) < World.distance(before, mate.tile),
				"on his line she's bitten (%d) and dragged toward his mate (%s to %s)" % [bit, before, player.tile])
		else:
			_check(bit == 0 and World.distance(grey.tile, player.tile) <= 1,
				"one cell off it she takes nothing (%d), though his run ends beside her" % bit)
		_check(panted, "%s: his lunge ends in his pant, landed or not" % case)
	DayNight.reset()
	Monster.idling = true


## The old grey alone on one player with a sword, the standing bar for a
## boss (the coordinator's rulings on playtest's 843 set and on the name
## roll), on the live body (_live_grey, his roll asserted), 2 minutes each
## in the open, he and the player kept up so the rates hold: held still;
## careless (every 2nd told lunge missed, held still through it); reading
## his lines (off the lunge's line, striking beside him, the pant included);
## and answering his bite too (out of reach in its lead). Her time to die
## (20 hp) against his to fall (his max_hp): the careless one loses, the
## line-reader comes out about even (she falls no sooner than four fifths
## of his time), the answerer wins with half her health left.
func _test_old_wolf_rates() -> void:
	print("%s== the old grey alone on one player: one who reads his lunge and his bite beats him; one careless loses ==" % char(10))
	Monster.idling = false
	DayNight.set_hour(12.0)
	var arena: Array[String] = ["#".repeat(46)]
	for y in 25:
		arena.append("#" + ".".repeat(44) + "#")
	arena.append("#".repeat(46))
	var row: Dictionary = Monster.kinds()["old_wolf"]
	var his_hp := int(row["body"]["max_hp"])
	var her_hp := 20
	var taken := {}
	var lost := {}
	for mode: String in ["still", "careless", "reader", "answers"]:
		var rows := arena.duplicate()
		rows[13] = rows[13].substr(0, 24) + "P" + rows[13].substr(25)
		var e := _build(rows)
		var grey := _live_grey(Vector2i(18, 13))
		var player: GridEntity = e["P"][0]
		if mode == "still":
			_check(World.attack_ticks_of(grey) == 31 and absf(grey.boldness - 0.75) < 0.005 and grey.reaction_ticks == 5,
				"his roll as the server lays him (%s): attack_ticks 31 (his row's 30, rolled), boldness 0.75, reaction 5 (%d, %.3f, %d)" % [
				grey.name, World.attack_ticks_of(grey), grey.boldness, grey.reaction_ticks])
		player.protected = false
		player.max_hp = 1000
		player.hp = 1000
		player.slots[Items.RIGHT_HAND] = "sword"
		grey.max_hp = 100000
		grey.hp = 100000
		grey.sight_range = 12
		grey.target = player
		_damage_log.clear()
		var lunges := 0
		var was := ""
		var ignoring := false
		var next_strike := 0
		var held_line: Array[Vector2i] = []
		var src := {"bites": 0, "bites_hp": 0, "lunges_hp": 0, "in_pant": 0}
		var ticks := 1200
		for i in ticks:
			if int(grey._move.get("telegraph", 0)) != 0 and grey._move.has("shape"):
				held_line = World.telegraph_cells(grey._move["shape"])
			elif str(grey._move.get("move", "")) != "rush":
				held_line = []
			var aimed: bool = (not World.winding(grey).is_empty() and World.winding(grey).get("target") == player) \
					or (not grey._windup.is_empty() and grey._windup.get("target") == player)
			if mode != "still":
				var acted := false
				if not held_line.is_empty() and player.tile in held_line and not ignoring:
					for way: Vector2i in World.DIRECTIONS:
						var cell := player.tile + way
						if not cell in held_line and World.is_walkable(cell) and World.is_free(cell):
							acted = World.try_move(player, way)
							break
				elif mode == "answers" and aimed:
					var best := Vector2i.ZERO
					var best_d := 0
					for way: Vector2i in World.DIRECTIONS:
						var cell := player.tile + way
						if World.is_walkable(cell) and World.is_free(cell) and not cell in held_line and World.distance(cell, grey.tile) > best_d:
							best_d = World.distance(cell, grey.tile)
							best = way
					if best != Vector2i.ZERO:
						World.try_move(player, best)
					acted = true
				if not acted:
					if World.distance(player.tile, grey.tile) <= 1:
						if World.tick >= next_strike:
							World.face(player, grey.tile - player.tile)
							if World.try_attack(player, grey):
								next_strike = World.tick + World.attack_ticks_of(player)
					elif held_line.is_empty() and not ignoring:
						World.try_move(player, Senses.way_toward(player.tile, grey.tile))
			var n0 := _damage_log.size()
			var t0 := World.tick
			var panting := str(grey._move.get("move", "")) == "pant"
			World.step()
			var move := str(grey._move.get("move", ""))
			var lunge_landed := move == "pant" and int(grey._move.get("from", -1)) >= t0
			for k in range(n0, _damage_log.size()):
				var d: Dictionary = _damage_log[k]
				if d["entity"] == player and d["source"] == grey:
					src["lunges_hp" if lunge_landed else "bites_hp"] += int(d["amount"])
					if not lunge_landed:
						src["bites"] += 1
				elif d["entity"] == grey and d["source"] == player and panting:
					src["in_pant"] += 1
			if move == "lunge" and was != "lunge":
				lunges += 1
				ignoring = mode == "careless" and lunges % 2 == 0
			if move == "pant":
				ignoring = false
			was = move
			player.hp = maxi(player.hp, 900)
		var per := 600.0 / float(ticks)
		var by_him := 0
		var on_him := 0
		for d: Dictionary in _damage_log:
			if d["entity"] == player and d["source"] == grey:
				by_him += int(d["amount"])
			elif d["entity"] == grey:
				on_him += int(d["amount"])
		taken[mode] = by_him * per
		lost[mode] = on_him * per
		print("  %s (a sword): %.0f hp a minute taken (bites %.1f a minute, %.0f hp; lunges %.0f hp), his %.0f lost (%.1f blows a minute in his pant), %.1f lunges a minute; she falls in %.1f s, he in %s" % [
			mode, taken[mode], src["bites"] * per, src["bites_hp"] * per, src["lunges_hp"] * per, lost[mode], src["in_pant"] * per, lunges * per,
			60.0 * her_hp / maxf(taken[mode], 0.01), "%.1f s" % (60.0 * his_hp / lost[mode]) if lost[mode] > 0.0 else "never"])
	var falls := func(mode: String) -> float: return 60.0 * her_hp / maxf(float(taken[mode]), 0.01)
	var beaten := func(mode: String) -> float: return 60.0 * his_hp / float(lost[mode]) if float(lost[mode]) > 0.0 else INF
	_check(int(row["body"]["attack_ticks"]) == 30 and int(row["body"]["attack_damage"]) == 4 and int(row["fight"]["lead_ticks"]) == 6,
		"his bite slow and told: 4 a bite, a 6-tick lead, one each 3 s (the coordinator's ruling)")
	_check(falls.call("careless") < beaten.call("careless"),
		"one who misses every 2nd told lunge loses: she falls in %.1f s, he in %.1f s" % [falls.call("careless"), beaten.call("careless")])
	_check(falls.call("reader") >= 0.8 * beaten.call("reader"),
		"one who reads his lunge's line comes out about even: she falls in %.1f s, he in %.1f s (within a fifth)" % [falls.call("reader"), beaten.call("reader")])
	_check(float(taken["answers"]) * beaten.call("answers") / 60.0 <= her_hp / 2.0,
		"one who steps out of his lunge and his bite wins with half her health left: %.0f of %d lost by the time he falls (%.1f s)" % [
		float(taken["answers"]) * beaten.call("answers") / 60.0, her_hp, beaten.call("answers")])
	DayNight.reset()
	Monster.idling = true


## His harm per minute alone on one player (the coordinator, for his
## unshelve), 2 minutes each in the open: held still; circling him 1-2 off;
## a reader stepping off every told line and striking him when beside; and
## one missing every 2nd told line, held still through it; and a reader who
## also steps out of his bite's wind-up. Every blow of his that hurts is told:
## the reader takes no charge, the still and the missing ones do, and one who
## answers his bite too takes nothing. Rates printed for the tuning (today:
## still 78 hp/min, circling 0, reader 24, every 2nd missed 48, answering 0).
func _test_boar_king_rates() -> void:
	print("%s== the boar king's harm per minute, alone on one player: told charges read are never struck ==" % char(10))
	var rate := {}
	Monster.idling = false
	DayNight.set_hour(12.0)
	var arena: Array[String] = ["#".repeat(46)]
	for y in 25:
		arena.append("#" + ".".repeat(44) + "#")
	arena.append("#".repeat(46))
	for cfg: Array in [[int(Monster.kinds()["boar_king"]["body"]["attack_damage"]), int(BoarKing.CHARGE["every"]), "today"]]:
		for mode: String in ["still", "circling", "reader", "miss2", "answers"]:
			var rows := arena.duplicate()
			rows[13] = rows[13].substr(0, 18) + "K" + rows[13].substr(19)
			rows[13] = rows[13].substr(0, 23) + "P" + rows[13].substr(24)
			var e := _build(rows)
			var king: BoarKing = e["K"][0]
			var player: GridEntity = e["P"][0]
			player.protected = false
			player.max_hp = 1000
			player.hp = 1000
			king.max_hp = 100000
			king.hp = 100000
			king.sight_range = 12
			king.attack_damage = int(cfg[0])
			king.charge["every"] = int(cfg[1])
			king.target = player
			_damage_log.clear()
			var tells := 0
			var was := ""
			var bites := 0
			var bite_hp := 0
			var hits := 0
			var hit_hp := 0
			var spin := 1
			var reader_next := 0
			var leads_answered := 0
			var ignoring := false
			var strikes := 0
			var ticks := 1200
			for i in ticks:
				var before := str(king._move.get("move", ""))
				if mode == "answers" and not king._windup.is_empty() and king._windup.get("target") == player:
					# His bite's lead seen: a step out of his reach, away from him.
					var out := Vector2i.ZERO
					for way: Vector2i in World.DIRECTIONS:
						var cell := player.tile + way
						if World.distance(cell, king.tile) >= 2 and not cell in king.told_line and World.is_walkable(cell) and World.is_free(cell):
							out = way
							break
					if out != Vector2i.ZERO:
						if World.try_move(player, out):
							leads_answered += 1
				elif mode == "reader" or mode == "miss2" or mode == "answers":
					# Reads every tell (miss2: every 2nd missed, held still through it): off his told line at once; else at him, striking when beside and ready.
					if player.tile in king.told_line and not ignoring:
						var off := Vector2i.ZERO
						for way: Vector2i in World.DIRECTIONS:
							if not (player.tile + way) in king.told_line and World.is_walkable(player.tile + way) and World.is_free(player.tile + way):
								off = way
								break
						if off != Vector2i.ZERO:
							World.try_move(player, off)
					elif World.distance(player.tile, king.tile) <= 1:
						if World.tick >= reader_next:
							World.face(player, king.tile - player.tile)
							if World.try_attack(player, king):
								reader_next = World.tick + World.attack_ticks_of(player)
								strikes += 1
					elif king.told_line.is_empty() and not ignoring:
						World.try_move(player, Senses.way_toward(player.tile, king.tile))
				elif mode == "circling":
					var d := World.distance(player.tile, king.tile)
					if d > 2:
						World.try_move(player, Senses.way_toward(player.tile, king.tile))
					else:
						var v := player.tile - king.tile
						var way := Vector2i(clampi(-v.y * spin, -1, 1), clampi(v.x * spin, -1, 1))
						if not World.try_move(player, way) and World.tick >= player.next_move_tick:
							spin = -spin
				World.step()
				var move := str(king._move.get("move", ""))
				if move == "charge" and was != "charge":
					tells += 1
					ignoring = mode == "miss2" and tells % 2 == 0
				if move == "" and was == "rush" or move == "skid":
					ignoring = false
				was = move
				for dd: Dictionary in _damage_log:
					if int(dd["tick"]) != World.tick or dd["entity"] != player or dd["source"] != king:
						continue
					if before == "rush" or move == "rush" or before == "charge":
						hits += 1
						hit_hp += int(dd["amount"])
					else:
						bites += 1
						bite_hp += int(dd["amount"])
				player.hp = maxi(player.hp, 900)
			var per := 600.0 / float(ticks)
			rate[mode] = [hit_hp * per, (hit_hp + bite_hp) * per, strikes * per]
			if mode == "answers":
				print("  his bite's wind-up %d ticks; steps out of it %d" % [king.windup_ticks, leads_answered])
			print("  rate %s, %s: per minute %.1f tells, %.1f charge hits (%.1f hp), %.1f bites (%.1f hp), harm %.1f hp/min; its strikes %.1f/min" % [cfg[2], mode,
				tells * per, hits * per, hit_hp * per, bites * per, bite_hp * per, (hit_hp + bite_hp) * per, strikes * per])
	_check(rate["reader"][0] == 0.0 and rate["still"][0] > 0.0 and rate["miss2"][0] > 0.0,
		"his charge strikes only one in its told line: a reader %.0f hp/min of charge, held still %.0f, every 2nd tell missed %.0f" % [rate["reader"][0], rate["still"][0], rate["miss2"][0]])
	_check(rate["answers"][1] == 0.0 and rate["answers"][2] > 0.0,
		"his bite is answered too: one who also steps out of its %d-tick wind-up takes %.0f hp/min, striking %.0f times a minute" % [int(Monster.WINDUP_TICKS), rate["answers"][1], rate["answers"][2]])
	_check(rate["still"][1] > rate["miss2"][1] and rate["miss2"][1] > rate["reader"][1],
		"each misread costs: harm a minute held still %.0f, every 2nd tell missed %.0f, reading every one %.0f, circling %.0f" % [rate["still"][1], rate["miss2"][1], rate["reader"][1], rate["circling"][1]])
	DayNight.reset()
	Monster.idling = true


## The boar king's lair and land (780 amended (16), the switch-on): his den
## in the open boar_lair, his door to the forest, roaming grounds off its
## pads; laid with his sounder about him; out with it following; his sounder
## cleared, beaten back (apex_beaten, once), home with nobody.
func _test_boar_king_lair() -> void:
	print("
== the boar king's lair: open, his den and doors, his sounder laid with him and following, beaten back by clearing it ==")
	if not Level.playable("boar_lair"):
		print("  the boar's lair held back (Level.SHELVED): his lair's checks shelved, skipped")
		return
	Apex.clear()
	var real_row: Dictionary = Monster.kinds()["boar_king"]["lair"]
	var real := Apex._places_of("boar_king", real_row)
	var roam: Array = real.get("roam", [])
	print("  his places: den %s, lair door %s, land door %s, %d roaming grounds" % [real.get("den"), real.get("lair_door"), real.get("land_door"), roam.size()])
	_check(Level.playable("boar_lair") and Apex.rows().has("boar_king") and Apex.holds_marker({"spawn": 0, "kind": "boar_king"}, "boar_lair"),
		"the boar's lair open (out of Level.SHELVED): Apex holds the boar king, his marker in it his den")
	_check(real.get("den") == Vector2i(14, 5) and real.get("lair_door") is Vector2i and real.get("land_door") is Vector2i and roam.size() > 20
			and roam.all(func(cell: Vector2i) -> bool: return World.distance(cell, real["land_door"]) <= int(real_row["range"]) + 1),
		"his den in the lair, its door and the forest's, and %d roaming grounds within his range" % roam.size())
	var land_rows: Array[String] = ["#".repeat(40)]
	for y in 8:
		land_rows.append("#" + ".".repeat(38) + "#")
	land_rows.append("#".repeat(40))
	_build(land_rows, {}, {}, "bk_land")
	World.spawn_spec = func(spec: Dictionary) -> GridEntity:
		var entity := EntityFactory.build(spec)
		_room.add_child(entity)
		if not World.spawn(entity, spec["tile"]):
			entity.free()
			return null
		return entity
	var land := World.zone
	World.zones[land.name] = land
	var lair := World.add_zone("bk_lair")
	World.enter(lair)
	var lair_rows: Array[String] = ["#".repeat(20)]
	for y in 8:
		lair_rows.append("#" + ".".repeat(18) + "#")
	lair_rows.append("#".repeat(20))
	World.load_terrain(Terrain.parse(Terrain.expand(lair_rows)))
	World.enter(land)
	var kinds := Monster.kinds()
	var row_was: Dictionary = kinds["boar_king"]["lair"]
	var row: Dictionary = row_was.duplicate(true)
	row["zone"] = "bk_lair"
	row["land"] = ["bk_land"]
	kinds["boar_king"]["lair"] = row
	Apex.clear()
	World.apexes.clear()
	Apex._places["boar_king"] = {"den": Vector2i(14, 4), "lair_door": Vector2i(2, 4), "land_door": Vector2i(3, 4),
			"roam": [Vector2i(30, 4)] as Array[Vector2i]}
	DayNight.set_hour(2.0)  # By night too: boars keep no hours.
	var idling_was := Monster.idling
	Monster.idling = true
	var beaten: Array = []
	var on_beaten := func(kind: String, _body: GridEntity, at: Vector2i) -> void: beaten.append([kind, at])
	World.apex_beaten.connect(on_beaten)
	var keeper := EntityFactory.build(SPECS["P"].merged({"name": "WallowKeeper"})) as Player
	_room.add_child(keeper)
	World.enter(lair)
	World.spawn(keeper, Vector2i(2, 7))
	World.enter(land)
	Apex._check("boar_king", row)
	var king := Apex.body_of("boar_king")
	var sounder: Array = Apex._escorts.get("boar_king", [])
	_check(king is BoarKing and king.zone == "bk_lair" and Apex.living_escort("boar_king") == 3
			and sounder.all(func(b: Animal) -> bool: return b.escort_lead == king and b.zone == "bk_lair" and World.distance(b.tile, king.tile) <= 3 and Apex.is_body(b)),
		"in his lair: laid at his den with his three boars about him, none ever saved")
	World.enter(lair)
	World.despawn(keeper)
	World.enter(land)
	var walker := EntityFactory.build(SPECS["P"].merged({"name": "Forager"})) as Player
	_room.add_child(walker)
	World.spawn(walker, Vector2i(37, 8))
	var rec := Apex.record("boar_king")
	rec["attacked"] = World.steps - Apex._steps(row, "venture_after_s", 2700.0)
	Apex._check("boar_king", row)
	_check(rec["state"] == "out", "left alone his while, by night as by day, he goes out (%s)" % rec["state"])
	Apex._check("boar_king", row)
	king = Apex.body_of("boar_king")
	sounder = Apex._escorts.get("boar_king", [])
	_check(king != null and king.zone == "bk_land" and Apex.living_escort("boar_king") == 3, "out of his door in his land, his sounder with him")
	for i in 150:
		World.step()
	var far := 0
	for b: Animal in sounder:
		if b.spawned:
			far = maxi(far, World.distance(b.tile, king.tile))
	_check(World.distance(king.tile, Vector2i(30, 4)) <= 10 and far <= int(Monster.kinds()["boar_king"]["escort"]["follow"]) + 3,
		"he walks out to his ground, his boars following, never bolting (%s, farthest %d)" % [king.tile, far])
	for b: Animal in sounder.duplicate():
		World.damage(b, 999)
	World.step()
	Apex._check("boar_king", row)
	_check(Apex.living_escort("boar_king") == 0 and beaten.size() == 1 and beaten[0][0] == "boar_king",
		"his sounder cleared: beaten back, apex_beaten once (%s)" % [beaten])
	for i in 700:
		World.step()
		if rec["state"] == "lair":
			break
	_check(rec["state"] == "lair" and beaten.size() == 1, "gone home to his lair (%s)" % rec["state"])
	World.apex_beaten.disconnect(on_beaten)
	World.despawn(walker)
	kinds["boar_king"]["lair"] = row_was
	Apex.clear()
	World.apexes.clear()
	World.zones.erase("bk_lair")
	World.zones.erase("bk_land")
	World.enter(land)
	Monster.idling = idling_was
	World.spawn_spec = Callable()
	DayNight.reset()


## A beast made bold at run time (Animal._settle_bold: a wolf by night)
## keeps no cautious holding back, alone (its spawn roll a cautious one's):
## bold means it comes in.
func _test_bold_comes_in() -> void:
	print("
== a wolf bold by night comes in alone: no cautious holding back ==")
	var idling_was := Monster.idling
	Monster.idling = false
	var e := _build(["##########", "#........#", "#.w...P..#", "#........#", "##########"], {"w": {"facing": Vector2i(1, 0)}})
	_outdoors("clear")
	DayNight.set_hour(1.0)
	var wolf: Animal = e["w"][0]
	var player: GridEntity = e["P"][0]
	player.max_hp = 100
	player.hp = 100
	wolf.sight_range = 8
	wolf.boldness = 0.1  # A cautious roll (wolves' temperament is cautious).
	player.protected = false
	var struck := -1
	for i in 120:
		World.step()
		if player.hp < 100:
			struck = World.tick
			break
	_check(wolf.temper == Monster.Temper.BOLD and struck >= 0, "bold by night, it comes in and strikes, alone (tick %d, temper %d, target %s)" % [struck, wolf.temper, wolf.target])
	DayNight.reset()
	_indoors()
	Monster.idling = idling_was


func _free_beside(at: Vector2i) -> Vector2i:
	for way in World.DIRECTIONS:
		if World.is_walkable(at + way) and World.is_free(at + way):
			return at + way
	return World.NO_CELL


## No lair heal while one who struck it in this fight is in its lair (780
## amended (20); the coordinator's ruling on playtest's boar king den-side
## runs: broken off the far way, out of the fight, he was whole again 30 s
## on with the player still by his den). Whole once they have all been out
## of it LAIR_HEAL_STEPS; one fresh, or downed and back, counts once they strike.
func _test_apex_heal_fighters() -> void:
	print("%s== an apex is not whole again while one who struck it stands in its lair: the great bear, the old grey (780 amended (20)) ==" % char(10))
	var idling_was := Monster.idling
	Monster.idling = true
	DayNight.set_hour(12.0)
	for kind: String in ["great_bear", "old_wolf"]:
		Apex.clear()
		var land_rows: Array[String] = ["#".repeat(40)]
		for y in 8:
			land_rows.append("#" + ".".repeat(38) + "#")
		land_rows.append("#".repeat(40))
		_build(land_rows, {}, {}, "ah_land")
		World.spawn_spec = func(spec: Dictionary) -> GridEntity:
			var entity := EntityFactory.build(spec)
			_room.add_child(entity)
			if not World.spawn(entity, spec["tile"]):
				entity.free()
				return null
			return entity
		var land := World.zone
		World.zones[land.name] = land
		var lair := World.add_zone("ah_lair")
		World.enter(lair)
		var lair_rows: Array[String] = ["#".repeat(20)]
		for y in 8:
			lair_rows.append("#" + ".".repeat(18) + "#")
		lair_rows.append("#".repeat(20))
		World.load_terrain(Terrain.parse(Terrain.expand(lair_rows)))
		World.enter(land)
		var kinds := Monster.kinds()
		var row_was: Dictionary = kinds[kind]["lair"]
		var row: Dictionary = row_was.duplicate(true)
		row["zone"] = "ah_lair"
		row["land"] = ["ah_land"]
		kinds[kind]["lair"] = row
		World.apexes.clear()
		Apex._places[kind] = {"den": Vector2i(14, 4), "lair_door": Vector2i(2, 4), "land_door": Vector2i(3, 4),
				"roam": [Vector2i(30, 4)] as Array[Vector2i]}
		var fighter := EntityFactory.build(SPECS["P"].merged({"name": "Fighter"})) as Player
		_room.add_child(fighter)
		var fresh := EntityFactory.build(SPECS["P"].merged({"name": "Fresh"})) as Player
		_room.add_child(fresh)
		World.enter(lair)
		World.spawn(fighter, Vector2i(2, 7))
		World.enter(land)
		Apex._check(kind, row)
		var body := Apex.body_of(kind)
		var rec := Apex.record(kind)
		var who := "great bear" if kind == "great_bear" else "old grey"
		if body == null:
			_check(false, "the %s laid in its lair" % who)
			kinds[kind]["lair"] = row_was
			continue
		# Struck, then 30 s with its fighter out of its sight but in its lair.
		Apex.struck(body, fighter)
		var half := roundi(body.max_hp * 0.5)
		body.hp = half
		body.target = null
		rec["attacked"] = World.steps - Apex.LAIR_HEAL_STEPS
		Apex._check(kind, row)
		_check(body.hp == half, "the %s struck, its foe out of its sight 30 s but still in its lair: not whole (%d of %d)" % [who, body.hp, body.max_hp])
		# The fighter gone, a fresh one come: whole once the fighter has been gone the while.
		World.enter(lair)
		World.despawn(fighter)
		World.spawn(fresh, Vector2i(5, 7))
		World.enter(land)
		Apex._check(kind, row)
		var soon := body.hp
		Apex._fight_seen[kind] = World.steps - Apex.LAIR_HEAL_STEPS
		Apex._check(kind, row)
		_check(soon == half and body.hp == body.max_hp,
			"its foe just gone: not yet (%d); gone the while, one who never struck it there: whole (%d of %d)" % [soon, body.hp, body.max_hp])
		# The fresh one strikes: their fight; downed and back, out of it till they strike again.
		Apex.struck(body, fresh)
		body.hp = half
		body.target = null
		rec["attacked"] = World.steps - Apex.LAIR_HEAL_STEPS
		Apex._check(kind, row)
		var fought := body.hp
		World.enter(lair)
		fresh.protected = false
		World.damage(fresh, fresh.hp + 10)
		if fresh.spawned:
			World.despawn(fresh)
		fresh.hp = fresh.max_hp
		World.spawn(fresh, Vector2i(5, 7))
		World.enter(land)
		Apex._fight_seen[kind] = World.steps - Apex.LAIR_HEAL_STEPS
		Apex._check(kind, row)
		_check(fought == half and body.hp == body.max_hp,
			"one who struck it there: not whole (%d); they fell and came back, not striking: whole (%d of %d)" % [fought, body.hp, body.max_hp])
		World.enter(lair)
		if fresh.spawned:
			World.despawn(fresh)
		World.enter(land)
		kinds[kind]["lair"] = row_was
		Apex.clear()
		World.apexes.clear()
		World.zones.erase("ah_lair")
		World.zones.erase("ah_land")
		World.enter(land)
	Monster.idling = idling_was
	World.spawn_spec = Callable()
	DayNight.reset()


## The old grey's lair and land (780 amended (15)): his den in grey_den, off
## the land's pads; laid with his escort; out with it following him; his
## escort cleared, beaten back (apex_beaten, once); those killed stay dead
## till his pack is whole again.
func _test_old_wolf_lair() -> void:
	print("\n== the old grey's lair: his den and doors, his escort laid with him and following, beaten back by clearing it, the dead staying dead ==")
	Apex.clear()
	var real_row: Dictionary = Monster.kinds()["old_wolf"]["lair"]
	var real := Apex._places_of("old_wolf", real_row)
	var roam: Array = real.get("roam", [])
	var off_pads := roam.all(func(cell: Vector2i) -> bool:
		return Vector2(cell - Vector2i(128, 0)).length() > 30.0 and Vector2(cell - Vector2i(128, 95)).length() > 30.0)
	_check(real.get("den") == Vector2i(18, 4) and real.get("lair_door") == Vector2i(4, 20) and real.get("land_door") == Vector2i(97, 33)
			and roam.size() > 20 and off_pads,
		"his den in grey_den, the doors either side, and %d roaming grounds in the foothills, all 30 off the castle's and the wilds' pads" % roam.size())
	_check(Apex.holds_marker({"spawn": 0, "kind": "old_wolf"}, "grey_den") and Level.playable("grey_den"),
		"his marker in his den is his den; the den is open (out of Level.SHELVED)")
	var land_rows: Array[String] = ["#".repeat(40)]
	for y in 8:
		land_rows.append("#" + ".".repeat(38) + "#")
	land_rows.append("#".repeat(40))
	_build(land_rows, {}, {}, "gw_land")
	World.spawn_spec = func(spec: Dictionary) -> GridEntity:
		var entity := EntityFactory.build(spec)
		_room.add_child(entity)
		if not World.spawn(entity, spec["tile"]):
			entity.free()
			return null
		return entity
	var land := World.zone
	World.zones[land.name] = land
	var lair := World.add_zone("gw_lair")
	World.enter(lair)
	var lair_rows: Array[String] = ["#".repeat(20)]
	for y in 8:
		lair_rows.append("#" + ".".repeat(18) + "#")
	lair_rows.append("#".repeat(20))
	World.load_terrain(Terrain.parse(Terrain.expand(lair_rows)))
	World.enter(land)
	var kinds := Monster.kinds()
	var row_was: Dictionary = kinds["old_wolf"]["lair"]
	var row: Dictionary = row_was.duplicate(true)
	row["zone"] = "gw_lair"
	row["land"] = ["gw_land"]
	kinds["old_wolf"]["lair"] = row
	Apex.clear()
	World.apexes.clear()
	Apex._places["old_wolf"] = {"den": Vector2i(14, 4), "lair_door": Vector2i(2, 4), "land_door": Vector2i(3, 4),
			"roam": [Vector2i(30, 4)] as Array[Vector2i]}
	DayNight.set_hour(12.0)
	var idling_was := Monster.idling
	Monster.idling = true
	var beaten: Array = []
	var on_beaten := func(kind: String, _body: GridEntity, at: Vector2i) -> void: beaten.append([kind, at])
	World.apex_beaten.connect(on_beaten)
	var keeper := EntityFactory.build(SPECS["P"].merged({"name": "DenKeeper"})) as Player
	_room.add_child(keeper)
	World.enter(lair)
	World.spawn(keeper, Vector2i(2, 7))
	World.enter(land)
	Apex._check("old_wolf", row)
	var grey := Apex.body_of("old_wolf")
	var escort: Array = Apex._escorts.get("old_wolf", [])
	_check(grey is OldWolf and grey.zone == "gw_lair" and Apex.living_escort("old_wolf") == 2
			and escort.all(func(w: Animal) -> bool: return w.escort_lead == grey and w.zone == "gw_lair" and World.distance(w.tile, grey.tile) <= 3 and Apex.is_body(w)),
		"in his lair: laid at his den with his two wolves about him, none ever saved")
	# Out: his pack with him, following.
	World.enter(lair)
	World.despawn(keeper)
	World.enter(land)
	var walker := EntityFactory.build(SPECS["P"].merged({"name": "HillWalker"})) as Player
	_room.add_child(walker)
	World.spawn(walker, Vector2i(37, 8))
	var rec := Apex.record("old_wolf")
	rec["attacked"] = World.steps - Apex._steps(row, "venture_after_s", 1800.0)
	Apex._check("old_wolf", row)
	_check(rec["state"] == "out" and not Apex._escorts.has("old_wolf"), "out unseen: gone from his lair, his pack with him")
	Apex._check("old_wolf", row)
	grey = Apex.body_of("old_wolf")
	escort = Apex._escorts.get("old_wolf", [])
	_check(grey != null and grey.zone == "gw_land" and Apex.living_escort("old_wolf") == 2, "out of his door in his land, two wolves with him")
	for i in 150:
		World.step()
	var far := 0
	for w: Animal in escort:
		far = maxi(far, World.distance(w.tile, grey.tile))
	_check(World.distance(grey.tile, Vector2i(30, 4)) <= 10 and far <= int(Monster.kinds()["old_wolf"]["escort"]["follow"]) + 3,
		"he walks out to his ground, his pack following within reach (%s, farthest %d)" % [grey.tile, far])
	# His escort cleared to one: beaten back, once.
	World.damage(escort[0], 999)
	World.step()
	_check(int(rec.get("escort_down", 0)) == 1 and Apex.living_escort("old_wolf") == 1, "one of his wolves killed: down, one lives")
	Apex._check("old_wolf", row)
	_check(beaten.size() == 1 and beaten[0][0] == "old_wolf", "his pack cleared to one: beaten back, apex_beaten once (%s)" % [beaten])
	for i in 700:
		World.step()
		if rec["state"] == "lair":
			break
	_check(rec["state"] == "lair" and beaten.size() == 1 and not Apex._escorts.has("old_wolf"), "gone into his lair, his last wolf with him (%s)" % rec["state"])
	# Back in his lair: those killed stay dead till his pack is whole again.
	World.enter(lair)
	World.spawn(keeper, Vector2i(2, 7))
	World.enter(land)
	Apex._check("old_wolf", row)
	grey = Apex.body_of("old_wolf")
	_check(grey != null and Apex.living_escort("old_wolf") == 1 and str(rec["state"]) == "lair" and grey.get("apex_goal") == Monster.NO_TILE,
		"laid in his lair with the one left, and there he waits, his wait out or not, till his pack is whole (%d)" % Apex.living_escort("old_wolf"))
	rec["attacked"] = World.steps - Apex.LAIR_HEAL_STEPS
	rec["escort_whole_at"] = World.steps
	rec["escort_fell"] = World.steps - 1
	Apex._check("old_wolf", row)
	_check(Apex.living_escort("old_wolf") == 1 and int(rec["escort_down"]) == 1,
		"one of his pack just fallen, his target lapsed between foes: no new wolf till the fight is over (%d)" % Apex.living_escort("old_wolf"))
	rec["escort_fell"] = World.steps - Apex.LAIR_HEAL_STEPS
	Apex._check("old_wolf", row)
	_check(Apex.living_escort("old_wolf") == 2 and int(rec["escort_down"]) == 0, "his rise_s after: his pack whole again (%d)" % Apex.living_escort("old_wolf"))
	# Killed: his pack, its fight over, is gone with him.
	World.enter(lair)
	World.damage(grey, grey.hp + 10)
	World.enter(land)
	World.step()
	_check(rec["state"] == "dead" and not Apex._escorts.has("old_wolf"), "killed: dead his rise, his pack gone (%s)" % rec["state"])
	World.apex_beaten.disconnect(on_beaten)
	World.enter(lair)
	World.despawn(keeper)
	World.enter(land)
	World.despawn(walker)
	kinds["old_wolf"]["lair"] = row_was
	Apex.clear()
	World.apexes.clear()
	World.zones.erase("gw_lair")
	World.zones.erase("gw_land")
	World.enter(land)
	Monster.idling = idling_was
	World.spawn_spec = Callable()
	DayNight.reset()
