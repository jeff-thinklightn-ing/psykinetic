extends "res://tests/level_test_base.gd"
## Levels from pixel maps (sim/level.gd), the laid levels: the barrow and its deep, the crypts
## (ways, spacing, the arrival and giver rules, chests kept guardable, torches seen, the hall
## shortcut, niches, latches and double doors), the draugr's hall, throne and altars, the
## barrow's quest and charges, camps and bands, the castle and its halls, towers, decor, and
## the ways out of the barrow. Split from level_test (the coordinator, 11-16), whose land,
## buildings, towns and links it leaves there; the shared part is tests/level_test_base.gd.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.


func _ready() -> void:
	Net.port = preload("res://tests/test_ports.gd").of(17772)
	_setup()
	_test_barrow_won()
	await _test_hall_door()
	_test_hall_door_heard()
	await _test_hidden_niche()
	await _test_robbers_latch()
	_test_double_doors()
	_test_camp_chest()
	_test_band()
	_test_crypt_ways()
	_test_arrival_rule()
	_test_giver_rule()
	_test_deep_crypt()
	_test_torches_seen()
	_test_chest_guardable()
	_test_crypt_spacing()
	_test_hall_shortcut()
	await _test_throne_way_held()
	await _test_draugr_hall_is_his_room()
	await _test_throne_home()
	_test_barrow_quest()
	await _test_knights_altar()
	await _test_altar_charges()
	await _test_full_circle_on()
	_test_quest_card_place()
	_test_decor()
	_test_barrow_level()
	_test_castle_halls_level()
	_test_tower_levels()
	await _test_castle()
	await _test_barrow_exits()
	_finish()


## The draugr's win as the record keeps it (decision 573, dungeon's side):
## the deal's charges up to the capacity, the spill said, the count on the
## player, a zone's sum, a record from before migrated.
func _test_barrow_won() -> void:
	print("\n== the barrow's charges (573, 573 amended; 714): the win's amulet uncharged and the sepulcher's relic, its charges on the altar, the capacity, the zone's sum ==")
	_main.load_map("test_link_s")
	var player := _player()
	var id: String = _main._peer_ids[Net.local_id]
	var record: PlayerRecord = _main._records[id]
	record.marks.erase("draugr")
	record.barrow = {}
	var had := World.totem_of(id)
	if had != 0:
		World.items.set_charges(had, 0)
	_main._sync_charges(record)
	_check(player.charges == 0 and player.charge_room == 0 and _main.charges_in_zone("test_link_s") == 0, "unblessed: no charges, no room, none in the zone")
	# 714, dungeon's side (2): the win gives the amulet uncharged and, from
	# the sepulcher, a relic of the generation's knight at the deal's tier;
	# the charges come when Aldous lays it on the altar (charge_from_relic).
	var kept: Variant = _main._regen.get("barrow_deep")
	_main._regen["barrow_deep"] = {"generation": 2, "at_step": 0}
	var knight: String = _main.barrow_knight()
	var relics := func() -> Array:
		return Array(World.slot_uids(player)).filter(func(each: int) -> bool: return World.relic_of(each).get("knight") == knight)
	var relics_before: int = relics.call().size()
	_check(_main.barrow_won([id], "normal") == 1 and record.barrow == {"best": "normal", "containers": []} and "draugr" in record.marks,
		"laid to rest at the normal deal: blessed, best normal, no count on the record (%s)" % [record.barrow])
	var uid := World.totem_of(id)
	var won: Array = relics.call()
	_check(uid != 0 and World.soulbound(uid) and World.totem_charges(uid) == 0 and player.slots.has(World.TOTEM) and player.charges == 0 and player.charge_room == 50,
		"the amulet is minted into their pack, bound for life, uncharged: the win gives no charges (0 of 50)")
	_check(not knight.is_empty() and won.size() == relics_before + 1 and World.relic_of(won[-1]) == {"knight": knight, "tier": 1} and World.soulbound(won[-1]),
		"from the sepulcher, the holy remains of %s at the normal deal's tier, bound to the winner, in their pack (%s)" % [knight, World.relic_of(won[-1]) if not won.is_empty() else {}])
	_check(_main.party_log.last(3) == ["The draugr yields. %s is blessed and takes up the %s, uncharged." % [record.name, Items.name_of(World.TOTEM)],
			_main.sepulcher_plaque() % knight, "%s takes the holy remains, %s." % [record.name, _main.remains_for()]],
		"the win, the plaque as its own line and the taking kept in the party log in the third person (%s)" % [_main.party_log.last(3)])
	_check(_heard.slice(-3) == ["The draugr yields. You are blessed, and take up the %s, uncharged." % Items.name_of(World.TOTEM),
			_main.sepulcher_plaque() % knight, "You take the holy remains, %s." % _main.remains_for()],
		"and on the winner's screen as said to them (133 amended (2)): \"You are blessed\", the plaque's carved words, \"You take\" (%s)" % [_heard.slice(-3)])
	var others_from := _heard.size()
	var another := Net.local_id + 1000  # A peer not this one: its you-line goes to it, never here.
	var both: Array[int] = [Net.local_id, another]
	_main.say_to_pair(another, "You test the line.", "Someone tests the line.", both)
	_check(_heard.slice(others_from) == ["Someone tests the line."] and _main.party_log.last(1) == ["Someone tests the line."],
		"say_to_pair: a line about another player reaches the rest in the third person, never their you-form (%s)" % [_heard.slice(others_from)])
	_check(_main.charge_from_relic(player, 1) == 10 and player.charges == 10 and _main.charges_in_zone("test_link_s") == 10 and _main.charges_in_zone("wilds") == 0,
		"the relic on the altar: the deal's 10 charges, 10 of 50; the zone's sum is 10, another zone's 0")
	_main.barrow_won([id], "easy")
	_check(World.totem_of(id) == uid and World.totem_charges(uid) == 10 and record.barrow["best"] == "normal"
		and _main.party_log.last(3)[0] == "The draugr yields. %s stands over him again." % record.name and World.relic_of(relics.call()[-1])["tier"] == 0
		and _heard.slice(-3)[0] == "The draugr yields. You stand over him again.",
		"won again at an easier deal: the same amulet, no charges, best kept, an easy relic (%s %s)" % [_main.party_log.last(3), _heard.slice(-3)])
	_check(_main.charge_from_relic(player, 0) == 5 and World.totem_charges(uid) == 15, "its relic adds its 5")
	World.items.set_charges(uid, 45)
	_check(_main.charge_from_relic(player, 0) == 5 and World.totem_charges(uid) == 50, "at the room's edge what fits is taken")
	_check(_main.charge_from_relic(player, 0) == 0 and World.totem_charges(uid) == 50 and _main.party_log.last(1) == ["The relic's gift spills: 5 more than %s can hold." % record.name],
		"full: the gift spills and is said (%s)" % [_main.party_log.last(1)])
	_main.barrow_won([id], "hard")
	_check(_main.charge_from_relic(player, 2) == 15 and World.totem_charges(uid) == 65 and record.barrow["best"] == "hard" and player.charge_room == 75,
		"the hard deal raises best and the room to 75; its relic's 15: 65 of 75")
	var saved := PlayerRecord.from_dict(JSON.parse_string(JSON.stringify(record.to_dict())).merged({"player_id": id}))
	_check(saved.barrow == record.barrow, "best and containers are kept through a save and a load (%s)" % [saved.barrow])
	# A record from before 573 amended: its count moves onto the totem on join (items' Main.migrate_totem).
	record.barrow["tokens"] = 4
	_check(_main.migrate_totem(record) == uid and World.totem_charges(uid) == 69 and not record.barrow.has("tokens"),
		"a count from before moves onto the totem on join (%d)" % World.totem_charges(uid))
	_check(_main.barrow_won(["nobody"], "easy") == 0, "no record: nobody blessed")
	# 714 amended (3): beaten unpaid, the knight's remains all the same: no tier, nothing else, the plaque said.
	var marks_were: Array = record.marks.duplicate()
	var charges_were := World.totem_charges(uid)
	var best_was: Dictionary = record.barrow.duplicate(true)
	var unpaid_of := func() -> int:
		return relics.call().filter(func(each: int) -> bool: return int(World.relic_of(each).get("tier", 0)) == Main.RELIC_UNPAID).size()
	var unpaid_before: int = unpaid_of.call()
	_check(_main.remains_unpaid([id, "nobody"]) == 1 and unpaid_of.call() == unpaid_before + 1 and World.totem_charges(uid) == charges_were
		and record.marks == marks_were and record.barrow == best_was
		and _main.party_log.last(2) == [_main.sepulcher_plaque() % knight, "%s takes the holy remains, %s." % [record.name, _main.remains_for()]]
		and _heard.slice(-2) == [_main.sepulcher_plaque() % knight, "You take the holy remains, %s." % _main.remains_for()],
		"beaten unpaid: the holy remains of %s at no tier, the plaque and the taking said as a winner's are; no charge, no mark, best unchanged; nobody without a record (%s %s)" % [knight, _main.party_log.last(2), _heard.slice(-2)])
	# 714, dungeon's side (1): a relic laid on the altar charges the amulet
	# with its tier's deal, up to the room; the spill said.
	_check(_main.charge_from_relic(player, 0) == 5 and World.totem_charges(uid) == 74 and player.charges == 74,
		"a relic of the least deal adds its 5: 74 of 75, the player told")
	_check(_main.charge_from_relic(player, 1) == 1 and World.totem_charges(uid) == 75
		and _main.party_log.last(1) == ["The relic's gift spills: 9 more than %s can hold." % record.name],
		"a normal deal's 10 at the room's edge: 1 taken, the 9 spilled and said (%s)" % [_main.party_log.last(1)])
	_check(_main.charge_from_relic(player, 1) == 0 and _main.charge_from_relic(player, 7) == 0 and _main.charge_from_relic(player, -1) == 0,
		"full, nothing taken; no such tier, nothing")
	# 672 amended, dungeon's side: quests reset, the barrow as if never come.
	_main._draft_told["%s@lt_niche" % id] = 1
	var cleared: Array[String] = _main.reset_barrow(id)
	_check(cleared == ["the draugr's blessing", "the deal won", "the totem's charges", "the draft felt"]
		and not "draugr" in record.marks and record.barrow.is_empty() and World.totem_charges(uid) == 0
		and not _main._draft_told.has("%s@lt_niche" % id) and player.charges == 0 and player.charge_room == 0,
		"reset_barrow: the blessing off, the deal won gone, the totem emptied, the draft said again, the player told (%s)" % [cleared])
	_check(_main.reset_barrow(id).is_empty() and _main.reset_barrow("nobody").is_empty(), "nothing more to clear the second time; no record, nothing")
	# 714 (1): the amulet taken away (items' reset_totem), a relic mints one,
	# uncharged while they are unblessed (no room); blessed again, it fills.
	World.reset_totem(id)
	_check(World.totem_of(id) == 0 and _main.charge_from_relic(player, 2) == 0 and World.totem_of(id) != 0
		and World.totem_charges(World.totem_of(id)) == 0, "no amulet: the relic mints one, empty, as there is no room unblessed")
	record.barrow = {"best": "easy", "containers": []}
	_check(_main.charge_from_relic(player, 2) == 15 and _main.charge_from_relic(player, 2) == 10 and World.totem_charges(World.totem_of(id)) == 25,
		"blessed at the easy deal (room 25): a hard relic's 15, then 10 of the next, full at 25 (%d)" % World.totem_charges(World.totem_of(id)))
	# 870, riding it: a blessed hand at zero is told the true way to more,
	# Aldous's for a holy knight's remains (714), not the draugr's.
	_main.mark_player(id, Main.BLESSED)  # reset_barrow above took the blessing off; the reset below takes it again.
	World.items.set_charges(World.totem_of(id), 0)
	_main._sync_charges(record)
	World.lay_downed(player, 300)
	_heard.clear()
	_check(not _main._start_channel(player, player) and _heard.slice(-1) == [Main.SPENT_LINE_ALTAR]
		and Main.SPENT_LINE_ALTAR == "Your amulet is spent. The knight in the crypt's First Hall blesses it again when you lay a holy knight's remains on his bier.",
		"at zero charges: no return, and the spent amulet's line on their screen, the knight's altar its way back since 896's switch-on (%s)" % [_heard.slice(-1)])
	World.raise_downed(player, player.max_hp)
	_main.reset_barrow(id)
	# 714 (1): the generation's knight, lore's fourteen, drawn by its seed.
	var knights: Array = Regen.config_of("barrow_deep").get("knights", [])
	_main._regen.erase("barrow_deep")
	_check(knights.size() == 14 and _main.barrow_knight() == "", "before barrow_deep's first generation, no knight; lore's fourteen listed")
	var named: Array[String] = []
	for generation in range(1, 9):
		_main._regen["barrow_deep"] = {"generation": generation, "at_step": 0}
		named.append(_main.barrow_knight())
	_main._regen["barrow_deep"] = {"generation": 3, "at_step": 0}
	_check(named.all(func(knight: String) -> bool: return knight in knights) and _main.barrow_knight() == named[2]
		and named.any(func(knight: String) -> bool: return knight != named[0]),
		"each generation names one of them, the same each time asked, not always the same (%s)" % [named])
	if kept == null:
		_main._regen.erase("barrow_deep")
	else:
		_main._regen["barrow_deep"] = kept


## The draugr's hall door held shut (573 amended, dungeon's side): the door
## edges on the lair anchor's rim lock behind the first player in (a key
## nobody holds, stone), no walk or E opens them, and let go they open.
func _test_hall_door() -> void:
	print("\n== the draugr's hall door (573 amended): held shut, no way through, let go ==")
	_register_hall("lt_hall")
	_main.load_map("lt_hall")
	var player := _player()
	var key := Terrain.edge_key(Vector2i(5, 4), Vector2i(0, -1))
	var door := World.door_on(key)
	_check(door != null and not door.open and door.lock.is_empty() and _main._hall_doors("lt_hall").size() == 1 and _main._hall_doors("lt_hall")[0] == door,
		"the hall's one door, on its lair anchor's north wall, is found (%s)" % [door])
	_put(player, Vector2i(5, 3))
	var heard: Array[String] = []
	var hear := func(kind: String, data: Dictionary) -> void:
		if kind == "party":
			heard.append(str(data.get("text", "")))
	Net.message_received.connect(hear)
	_main._told_dead.clear()
	_main._dead_near.clear()
	_put(player, Vector2i(5, 4))  # In the Hall as it shuts (573 amended (2): the shut line is theirs).
	_main._hold_hall_door("lt_hall", true)
	_put(player, Vector2i(5, 3))
	_check(door != null and not door.open and door.lock == "draugr_hall" and door.body_material == GridEntity.BodyMaterial.STONE
		and _main.party_log.last(1) == ["The hall's door shuts behind you."] and _heard.slice(-1) == ["The hall's door shuts behind you."],
		"held: shut, locked with a key nobody holds, stone, and said to the one inside (%s %s)" % [_main.party_log.last(1), _heard.slice(-1)])
	_hold_free(player, Vector2(0, 1), 8)
	_check(player.tile == Vector2i(5, 3) and player.free_pos.y < 3.6, "no walk goes through it: stopped at its face (%s)" % player.free_pos)
	_check(not heard.has(_main.DEAD_LINE), "a challenge's held door says nothing of the dead to a walk into it (%s)" % [heard])
	_check(not World.try_toggle_door(player, key) and not door.open, "and E rattles it")
	_main._hold_hall_door("lt_hall", false)
	_check(door.lock.is_empty() and not door.open and _main.party_log.last(1) == ["The hall's door opens."] and _heard.slice(-1) == ["The hall's door opens."],
		"let go: the lock lifted, still shut till opened, and said to the one at its door (%s)" % [_heard.slice(-1)])
	await get_tree().process_frame
	_check(World.try_toggle_door(player, key) and door.open, "E opens it now")
	# 608 amended (3): the warning ahead of his Hall, once a visit, while he sits waiting.
	var draugr := _main._spawn({"script": "res://sim/draugr.gd", "shape": "capsule", "name": "LtHallDraugr",
		"tile": Vector2i(5, 7), "props": Level.MONSTER_TYPES["draugr"].duplicate()}) as Draugr
	draugr.acts = false
	heard.clear()
	_main._told_hall.clear()
	_put(player, Vector2i(5, 2))
	_check(heard.is_empty(), "a step short of the Hall's door: nothing said (%s)" % [heard])
	_put(player, Vector2i(5, 3))
	_check(heard == [_main.HALL_AHEAD_LINE], "at the open Hall door, the draugr seated within: told what waits (%s)" % [heard])
	_put(player, Vector2i(5, 2))
	_put(player, Vector2i(5, 3))
	_check(heard.count(_main.HALL_AHEAD_LINE) == 1, "once a visit: back at the door, not again (%s)" % [heard])
	_main._told_hall[player.owner_peer] = "lt_elsewhere"
	_put(player, Vector2i(5, 2))
	_put(player, Vector2i(5, 3))
	_check(heard.count(_main.HALL_AHEAD_LINE) == 2, "a visit after one elsewhere: told again (%s)" % [heard])
	for state: Draugr.State in [Draugr.State.PACT, Draugr.State.AT_REST]:
		draugr.state = state
		_main._told_hall.clear()
		_put(player, Vector2i(5, 2))
		_put(player, Vector2i(5, 3))
	_check(heard.count(_main.HALL_AHEAD_LINE) == 2, "in a pact or at rest he asks nothing: nothing said (%s)" % [heard])
	World.despawn(draugr)
	_main._told_hall.clear()
	# The dead's seal (666): held while they stand, entry only, under a challenge's lock.
	_main._seal_hall("lt_hall", true)
	_check(not door.open and door.lock == _main.DEAD_LOCK and door.body_material == GridEntity.BodyMaterial.STONE and not World.try_toggle_door(player, key),
		"the Ossuary's dead standing: the hall's door sealed with a key nobody holds, E rattles it (%s)" % door.lock)
	heard.clear()
	_hold_free(player, Vector2(0, 1), 8)
	_check(player.tile == Vector2i(5, 3) and player.free_pos.y < 3.6, "and stops a walk at its face (%s)" % player.free_pos)
	_check(heard.count(_main.DEAD_LINE) == 1, "walking into it tells them \"%s\" once, not every step (%s)" % [_main.DEAD_LINE, heard])
	# Once as they meet it (666 amended (2); playtest's look_bossbar_window: eight lines running).
	var edge := [key.x, key.y, key.z]
	_main._on_command(player, "door", {"edge": edge})
	_main._on_command(player, "door", {"edge": edge})
	_check(heard.count(_main.DEAD_LINE) == 1, "E at it straight after: nothing more (%s)" % [heard])
	_main._told_dead[player.owner_peer] -= roundi(_main.DEAD_TOLD_S * World.TICK_RATE)
	_hold_free(player, Vector2(0, 1), 2)
	_main._on_command(player, "door", {"edge": edge})
	_check(heard.count(_main.DEAD_LINE) == 1, "a push held there, or E, with %.0f s gone but never stepped away: nothing more (%s)" % [_main.DEAD_TOLD_S, heard])
	_put(player, Vector2i(5, 3 - _main.DEAD_AWAY))
	_put(player, Vector2i(5, 3))
	_main._on_command(player, "door", {"edge": edge})
	_check(heard.count(_main.DEAD_LINE) == 1, "a step back still within %d cells of it is not away: nothing (%s)" % [_main.DEAD_AWAY, heard])
	_main._told_dead[player.owner_peer] = World.tick
	_put(player, Vector2i(5, 2 - _main.DEAD_AWAY))
	_put(player, Vector2i(5, 3))
	_main._on_command(player, "door", {"edge": edge})
	_check(heard.count(_main.DEAD_LINE) == 1, "away and back inside %.0f s of the last telling: nothing (the floor) (%s)" % [_main.DEAD_TOLD_S, heard])
	_main._told_dead[player.owner_peer] -= roundi(_main.DEAD_TOLD_S * World.TICK_RATE)
	_main._on_command(player, "door", {"edge": edge})
	_main._on_command(player, "door", {"edge": edge})
	_hold_free(player, Vector2(0, 1), 2)
	_check(heard.count(_main.DEAD_LINE) == 2, "stepped away and come back with %.0f s gone: told again, once (%s)" % [_main.DEAD_TOLD_S, heard])
	Net.message_received.disconnect(hear)
	_main._told_dead.clear()
	_main._dead_near.clear()
	_main._seal_hall("lt_hall", false)
	_check(door.lock.is_empty(), "every one of them down: the seal lifted")
	await get_tree().process_frame
	World.try_toggle_door(player, key)
	_hold_free(player, Vector2(0, 1), 8)
	_check(door.open and player.tile.y >= 5, "opened, it is walked through into the hall (%s)" % [player.tile])
	_put(player, Vector2i(5, 6))
	_main._seal_hall("lt_hall", true)
	_check(door.lock.is_empty(), "risen while a living player stands in the hall: no seal, nobody shut in by the dead")
	_put(player, Vector2i(5, 3))
	for i in _main.HALL_SEAL_EVERY:
		World.step()
	_check(door.lock == _main.DEAD_LOCK, "the hall empty, the waiting seal takes hold within a second")
	_main._hold_hall_door("lt_hall", true)
	_check(door.lock == "draugr_hall", "a challenge's lock goes over the seal")
	_main._hold_hall_door("lt_hall", false)
	_check(door.lock == _main.DEAD_LOCK, "and when it lets go, the dead's seal holds again by its own rule")
	_main._hall_seals.erase("lt_hall")
	World.hold_door(door, false, _main.DEAD_LOCK)
	_main._hold_hall_door("nowhere", true)
	_check(_main._hall_doors("test_room").is_empty(), "a level with no lair anchor has no hall door; an unknown zone is let be")
	# A retired level (666): its saved players moved to its heir's cell, its saved state dropped.
	var kept_records: Dictionary = _main._records.duplicate()
	var gone := PlayerRecord.new()
	gone.player_id = "lt-retired"
	gone.zone = "barrow_lair"
	gone.tile = Vector2i(49, 60)
	gone.companion = {"tile": Vector2i(48, 60)}
	var stays := PlayerRecord.new()
	stays.player_id = "lt-stays"
	stays.zone = "barrow"
	stays.tile = Vector2i(40, 2)
	_main._records[gone.player_id] = gone
	_main._records[stays.player_id] = stays
	_main._regen["barrow_lair"] = {"generation": 4}
	_main._move_off_retired({"zones": {"barrow_lair": {"entities": []}}})
	_check(gone.zone == "barrow_deep" and gone.tile == Vector2i(49, 2) and gone.companion.get("tile") == null and stays.zone == "barrow" and stays.tile == Vector2i(40, 2)
		and not _main._regen.has("barrow_lair"), "one saved in the dark below wakes at the Ossuary's stair foot, its generation dropped; others are let be (%s %s)" % [gone.zone, gone.tile])
	_main._records = kept_records
	_main.load_map("test_room")
	Level.unregister("lt_hall")


## Who is told the hall's door shuts and opens (573 amended, ui-design's
## look_hall2b, two joined players: one walked into the Hall, the other,
## waiting outside the door, was told "The hall's door shuts behind you."):
## the players inside its lair's rect hear the shut line; one outside with a
## door cell within 6 cells and in sight hears voice's line naming who went
## in; one off at the level's far side, and one within 6 cells behind a
## wall, hear nothing; the opening is said to the same two. Inside is the
## lair's rect (Main.hall_lair_rect, as its doors are found), which
## Draugr.in_hall reads too.
func _test_hall_door_heard() -> void:
	print("\n== the hall's door: its shut and its opening said to those inside, and to those outside who see it (573 amended) ==")
	_register_hall_heard("lt_hall_heard")
	_main.load_map("lt_hall_heard")
	var host := _player()
	var made: Array[Player] = []
	for at: Vector2i in [Vector2i(9, 9), Vector2i(9, 4), Vector2i(4, 4)]:
		made.append(_main._spawn({"script": "res://sim/player.gd", "shape": "capsule", "name": "LtHallHeard%d" % made.size(), "tile": at}) as Player)
	_check(host != null and made.all(func(p: Player) -> bool: return p != null), "(the host and three more players)")
	if host == null or made.any(func(p: Player) -> bool: return p == null):
		return
	var inside := made[0]
	var at_door := made[1]
	var walled := made[2]
	inside.owner_peer = 4301
	at_door.owner_peer = 4302
	walled.owner_peer = 4303
	_put(host, Vector2i(17, 1))
	var key := Terrain.edge_key(Vector2i(9, 6), Vector2i(0, -1))
	_check(_main._hall_doors("lt_hall_heard").size() == 1 and _main._hall_doors("lt_hall_heard")[0] == World.door_on(key),
		"(the hall's one door, between (9,5) and (9,6))")
	# His kind's row (levels/monsters.json: keeps_room) gives him his home's anchor as his room.
	var draugr := _main._spawn({"script": "res://sim/draugr.gd", "shape": "capsule", "name": "LtHallHeardDraugr", "kind": "draugr",
		"tile": Vector2i(9, 11), "props": Level.MONSTER_TYPES["draugr"].duplicate()}) as Draugr
	_check(draugr != null, "(the draugr in his Hall)")
	if draugr != null:
		draugr.acts = false
		_check(draugr._room == _main.hall_lair_rect("lt_hall_heard") and draugr.in_hall(inside) and not draugr.in_hall(at_door)
				and not draugr.in_hall(walled) and not draugr.in_hall(host),
				"Main.hall_lair_rect and Draugr.in_hall agree on who is inside (%s, %s)" % [draugr._room, _main.hall_lair_rect("lt_hall_heard")])
		World.despawn(draugr)
	var outside_line := "The hall's door shuts behind %s, and the bolt drops. It won't open till it's over in there." % World.shown_name(inside)
	var peers := {"inside": inside.owner_peer, "at the door": at_door.owner_peer, "behind a wall": walled.owner_peer, "far off": host.owner_peer}
	Net.test_sends.clear()
	Net.test_keep_sends = true
	_main._hold_hall_door("lt_hall_heard", true)
	var shut := _hall_lines(peers)
	_check(shut["inside"] == ["The hall's door shuts behind you."], "sealed: the one inside is told it shuts behind them (%s)" % [shut])
	_check(shut["at the door"] == [outside_line], "the one waiting outside at the door is told who went in, the bolt, and till when (%s)" % [shut])
	_check(shut["far off"].is_empty() and shut["behind a wall"].is_empty(),
		"the far side of the level, and a player within 6 cells behind a wall, are told nothing (%s)" % [shut])
	Net.test_sends.clear()
	_main._hold_hall_door("lt_hall_heard", false)
	var opened := _hall_lines(peers)
	_check(opened["inside"] == ["The hall's door opens."] and opened["at the door"] == ["The hall's door opens."]
			and opened["far off"].is_empty() and opened["behind a wall"].is_empty(),
			"let go: the opening said to the same two, nobody else (%s)" % [opened])
	Net.test_keep_sends = false
	Net.test_sends.clear()
	for each: Player in made:
		World.despawn(each)
	_main.load_map("test_room")
	Level.unregister("lt_hall_heard")


## The "party" lines Net.test_sends holds for each of [param peers] (name -> peer).
func _hall_lines(peers: Dictionary) -> Dictionary:
	var out := {}
	for name: String in peers:
		var lines: Array[String] = []
		for send: Array in Net.test_sends:
			if send[1] == "party" and (send[0] as Array).has(peers[name]):
				lines.append(str((send[2] as Dictionary).get("text", "")))
		out[name] = lines
	return out


## A 20 x 14 level [param level_name]: the Hall (its lair anchor, 6,6 8x7)
## shut off but for one door in its north wall at x 9; an antechamber
## (2..17, 1..5) before it; a side room (2..4, 1..5) walled off from it.
func _register_hall_heard(level_name: String) -> void:
	var floor_at := func(x: int, y: int) -> bool:
		return (x >= 2 and x <= 17 and y >= 1 and y <= 5) or (x >= 6 and x <= 13 and y >= 6 and y <= 12)
	var rows: Array[String] = []
	for py in 14 * 2 - 1:
		var row := ""
		for px in 20 * 2 - 1:
			var cx := px / 2
			var cy := py / 2
			if px % 2 == 0 and py % 2 == 0:
				row += "." if floor_at.call(cx, cy) else " "
			elif px % 2 == 0:
				row += ("+" if cx == 9 else "#") if cy == 5 and cx >= 6 and cx <= 13 else " "
			elif py % 2 == 0:
				row += "#" if cx == 4 and cy >= 1 and cy <= 5 else " "
			else:
				row += " "
		rows.append(row)
	Level.register(level_name, Level.image_from_rows(rows, {Vector2i(9, 2): "start"}), null,
		{"regenerate": {"anchors": [{"rect": [6, 6, 8, 7], "name": "lair"}]}})


## A 12 x 10 level [param level_name]: open floor, a lair anchor
## (2, 4, 8, 5) walled along its north edge with one door at (5, 4).
func _register_hall(level_name: String) -> void:
	var rows: Array[String] = []
	for py in 10 * 2 - 1:
		var row := ""
		for px in 12 * 2 - 1:
			var floor_here := px % 2 == 0 and py % 2 == 0
			var north_wall := py == 7 and px % 2 == 0 and px / 2 >= 2 and px / 2 <= 9
			row += ("+" if px / 2 == 5 else "#") if north_wall else ("." if floor_here else " ")
		rows.append(row)
	Level.register(level_name, Level.image_from_rows(rows, {Vector2i(5, 1): "start"}), null,
		{"regenerate": {"anchors": [{"rect": [2, 4, 8, 5], "name": "lair"}]}})


## A 12 x 10 level [param level_name]: open floor walled across between
## y 3 and 4 from x 2 to 9, with doors side by side at x 5 and 6 (and a
## third, lone one at x 8, locked when [param locked]);
## [param generated] gives it a regenerate block.
func _register_pair(level_name: String, generated: bool) -> void:
	var rows: Array[String] = []
	for py in 10 * 2 - 1:
		var row := ""
		for px in 12 * 2 - 1:
			var floor_here := px % 2 == 0 and py % 2 == 0
			var north_wall := py == 7 and px % 2 == 0 and px / 2 >= 2 and px / 2 <= 9
			row += ("+" if px / 2 in [5, 6, 8] else "#") if north_wall else ("." if floor_here else " ")
		rows.append(row)
	var config := {"regenerate": {"anchors": [{"rect": [0, 4, 12, 6], "name": "below"}]}} if generated else {}
	Level.register(level_name, Level.image_from_rows(rows, {Vector2i(5, 4): "start"}), null, config)


## The robbers' clear (714, dungeon's side (4)): in the robbers' barrow the
## hidden niche gives and its draft is felt only once none of them stands,
## dead or fled; the first time, it latches for the generation (saved), and
## robbers come back do not undo it.
func _test_robbers_latch() -> void:
	print("
== the robbers' clear (714): the hidden way only once the band is down, latched for the generation ==")
	if World.economy == null:
		_check(false, "no economy to read the robbers from")
		return
	var rules: Dictionary = World.economy.rules.get("robbers", {}).duplicate(true)
	World.economy.rules["robbers"] = rules.merged({"barrow": "lt_niche"}, true)
	_register_niche("lt_niche")
	_main.load_map("lt_niche")
	var kept: Variant = _main._regen.get("lt_niche")
	_main._regen["lt_niche"] = {"generation": 1, "at_step": 0}
	var player := _player()
	var key := Terrain.edge_key(Vector2i(6, 1), Vector2i(0, -1))
	var door := World.door_on(key)
	var spawn_robber := func(at: Vector2i) -> GridEntity:
		return _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "kind": "robber", "name": "Robber%d" % at.x, "tile": _main._nearest_free(at)})
	var robber: GridEntity = spawn_robber.call(Vector2i(1, 4))
	_check(robber != null and not _main.robbers_cleared("lt_niche") and _main.robbers_cleared("test_room"),
		"a robber stands in their barrow: not cleared; another level has none to clear")
	var heard: Array[String] = []
	var hear := func(kind: String, data: Dictionary) -> void:
		if kind == "party":
			heard.append(str(data.get("text", "")))
	Net.message_received.connect(hear)
	_main._tell_draft(player, Vector2i(3, 3))
	_put(player, Vector2i(6, 1))
	for i in 6:
		_hold_free(player, Vector2(0, -1), 1)
	_check(not door.open and door.lock == Main.HIDDEN_LOCK and _main.party_log.last(1) == [Main.NICHE_SHUT_LINE]
		and not heard.any(func(text: String) -> bool: return "draft" in text),
		"with one up, the hidden niche is any niche: shut, the shut line, no draft (%s)" % [_main.party_log.last(1)])
	World.damage(robber, 999)
	_check(bool(_main._regen["lt_niche"].get("robbers_down", false)) and _main.robbers_cleared("lt_niche"),
		"the last one falls: the clear latches for the generation (%s)" % [_main._regen["lt_niche"]])
	var back: GridEntity = spawn_robber.call(Vector2i(2, 4))
	_check(back != null and _main.robbers_cleared("lt_niche") and Regen.states_from(JSON.parse_string(JSON.stringify(_main._regen)))["lt_niche"].get("robbers_down") == true,
		"one come back after does not undo it, and a save keeps it")
	_main._draft_told.erase("%s@lt_niche" % player.player_id)  # _test_hidden_niche's, told already this generation.
	_main._tell_draft(player, Vector2i(3, 3))
	_check(not heard.has("You feel a cool draught coming from one of the niches.") and not _main.way_revealed(player.player_id, "lt_niche"),
		"cleared, but the way is not revealed to them (747: the fallen knight's quest not done): no draft (%s)" % [heard])
	_main.mark_player(player.player_id, Main.QUEST_DONE)
	_main._tell_draft(player, Vector2i(3, 3))
	_check(heard.has("You feel a cool draught coming from one of the niches."), "his quest done: now the draft is felt (%s)" % [heard])
	_put(player, Vector2i(6, 1))
	for i in 10:
		_hold_free(player, Vector2(0, -1), 1)
		if door.open:
			break
	_check(door.open, "and the hidden niche gives")
	# Fled out (702: despawned at a way out) counts as down too.
	_main._regen["lt_niche"] = {"generation": 2, "at_step": 0}
	_check(not _main.robbers_cleared("lt_niche"), "a new generation: the one come back stands, not cleared")
	World.despawn(back)
	_check(bool(_main._regen["lt_niche"].get("robbers_down", false)), "he gets away out of the barrow: down, latched")
	# The coordinator (714 (4)): with a 5-minute rise, each of the band fallen
	# once this generation is clear, though one has risen again.
	_check(_main.band_ids("barrow") == ["brand", "crake", "mott", "nabb", "wicket", "fenn", "rook", "sedge", "tull"],
		"the barrow's band, Brand and the eight (%s)" % [_main.band_ids("barrow")])
	_main._regen["lt_niche"] = {"generation": 3, "at_step": 0}
	var named_one := func(id: String, at: Vector2i) -> Monster:
		var monster := spawn_robber.call(at) as Monster
		if monster != null:
			monster.named_id = id
		return monster
	var t1: Monster = named_one.call("t1", Vector2i(1, 4))
	var t2: Monster = named_one.call("t2", Vector2i(3, 4))
	World.damage(t1, 999)
	var risen: Monster = named_one.call("t1", Vector2i(1, 4))
	_check(_main._regen["lt_niche"].get("robbers_fallen", []) == ["t1"] and not _main._band_fallen("lt_niche", ["t1", "t2"])
		and not bool(_main._regen["lt_niche"].get("robbers_down", false)),
		"one of two fallen, risen again: kept as fallen, not yet clear (%s)" % [_main._regen["lt_niche"]])
	World.damage(t2, 999)
	_check(_main._band_fallen("lt_niche", ["t1", "t2"]) and risen != null and risen.hp > 0
		and (Regen.states_from(JSON.parse_string(JSON.stringify(_main._regen)))["lt_niche"].get("robbers_fallen", []) as Array) == ["t1", "t2"],
		"the other falls: each fallen once though the first stands again, and the fallen saved (%s)" % [_main._regen["lt_niche"]])
	World.despawn(risen)
	_main.mark_player(player.player_id, Main.QUEST_DONE, false)
	Net.message_received.disconnect(hear)
	World.economy.rules["robbers"] = rules
	if kept == null:
		_main._regen.erase("lt_niche")
	else:
		_main._regen["lt_niche"] = kept
	_main.load_map("test_room")
	Level.unregister("lt_niche")


## The generated halls' doors two edges wide (725): the pair side by side
## swings as one (World.door_partner, the client's Level.door_pairs), the
## lone third its own; a level that does not regenerate keeps 403's rule,
## each edge its own door.
func _test_double_doors() -> void:
	print("
== the generated halls' double doors swing as one (725) ==")
	var pairs := Level.door_pairs([Vector3i(5, 3, 1), Vector3i(6, 3, 1), Vector3i(7, 3, 1), Vector3i(9, 3, 1), Vector3i(10, 3, 1)], func(_key: Vector3i) -> bool: return true)
	_check(pairs == {Vector3i(5, 3, 1): Vector3i(6, 3, 1), Vector3i(9, 3, 1): Vector3i(10, 3, 1)},
		"pairs two at a time from a run's start, a third left on its own (%s)" % [pairs])
	for generated: bool in [true, false]:
		var name := "lt_pair" if generated else "lt_pair_plain"
		_register_pair(name, generated)
		_main.load_map(name)
		var player := _player()
		var left := World.door_on(Terrain.edge_key(Vector2i(5, 4), Vector2i(0, -1)))
		var right := World.door_on(Terrain.edge_key(Vector2i(6, 4), Vector2i(0, -1)))
		var lone := World.door_on(Terrain.edge_key(Vector2i(8, 4), Vector2i(0, -1)))
		player.next_move_tick = 0
		var opened := World.try_toggle_door(player, left.key)
		if generated:
			_check(opened and left.open and right.open and not lone.open and World.door_partner(left) == right and World.door_partner(right) == left and World.door_partner(lone) == null,
				"in a generated hall the pair opens as one, the lone door stays shut (%s %s %s)" % [left.open, right.open, lone.open])
			player.next_move_tick = 0
			World.try_toggle_door(player, left.key)
			_check(not left.open and not right.open, "and shuts as one")
		else:
			_check(opened and left.open and not right.open and World.door_partner(left) == null,
				"a level that does not regenerate: each edge its own door (403)")
		_main.load_map("test_room")
		Level.unregister(name)


## The hidden door (608): the first hall's one true niche is a door spawned
## locked and stone; a step into any niche presses on it (Main.NICHE_SHUT_LINE
## once a stand), the true one gives, the stair behind it is
## taken, and a climb from below pushes it open from behind.
func _test_hidden_niche() -> void:
	print("\n== the hidden door (608): niches pressed, the true one found, the stair behind it, opened from below; the draft felt (608 amended) ==")
	_register_niche("lt_niche")
	var parsed := Level.load_level("lt_niche")
	_check(parsed["warnings"].is_empty() and parsed["terrain"]["niches"].size() == 3 and parsed["links"][0]["hidden"],
		"the level parses: three niches on the north wall, the stair link hidden (%s)" % [parsed["warnings"]])
	_main.load_map("lt_niche")
	var player := _player()
	var key := Terrain.edge_key(Vector2i(6, 1), Vector2i(0, -1))
	var door := World.door_on(key)
	_check(door != null and not door.open and door.lock == "hidden_niche" and door.body_material == GridEntity.BodyMaterial.STONE
		and World.niche_edges.size() == 3 and World.niche_edges.get(key) == "hidden" and World.niche_edges.get(Terrain.edge_key(Vector2i(2, 1), Vector2i(0, -1))) == "a",
		"the hidden niche's door spawns shut, locked with a key nobody holds and stone; World knows the three niche edges (%s)" % [World.niche_edges])
	# 608 amended: the marker every clue reads, the hall, and the draft line
	# to the player alone on their first step in the hall, once a generation,
	# while the door is shut.
	var heard: Array[String] = []
	var hear := func(kind: String, data: Dictionary) -> void:
		if kind == "party":
			heard.append(str(data.get("text", "")))
	Net.message_received.connect(hear)
	var draft := "You feel a cool draught coming from one of the niches."
	_check(_main.hall_rect("lt_niche") == Rect2i(0, 0, 8, 6) and _main.hall_rect("test_room") == Rect2i(),
		"the hall is the entrance anchor's rect, none for a level that does not regenerate (%s)" % [_main.hall_rect("lt_niche")])
	_check(World.hidden_niche() == {"cell": Vector2i(6, 1), "edge": key, "open": false},
		"World.hidden_niche is the marker: its floor cell, its door's edge, shut (%s)" % [World.hidden_niche()])
	_hold_free(player, Vector2(1, 0), 3)
	_check(player.tile == Vector2i(4, 3) and heard.count(draft) == 1,
		"the first cell crossed in the hall says the draft line to the player alone (%s)" % [heard])
	_hold_free(player, Vector2(1, 0), 3)
	_check(player.tile == Vector2i(5, 3) and heard.count(draft) == 1, "the next says it no more")
	_put(player, Vector2i(2, 1))
	_hold_free(player, Vector2(0, -1), 6)
	var line := Main.NICHE_SHUT_LINE
	_check(player.tile == Vector2i(2, 1) and _main.party_log.last(1) == [line] and heard.count(line) == 1,
		"pressing into a plain niche is stopped and says the line, to the player's screen (%s)" % [heard])
	var told: Array = _main.party_log.last(3)
	_hold_free(player, Vector2(0, -1), 6)
	_check(_main.party_log.last(3) == told, "pressing on at it says nothing more")
	_put(player, Vector2i(4, 1))
	_hold_free(player, Vector2(0, -1), 6)
	_check(_main.party_log.last(2) == [line, line] and heard.count(line) == 2, "another niche says it again (%s)" % [heard])
	_put(player, Vector2i(6, 1))
	_check(not World.may_open(player, door) and not World.try_toggle_door(player, key) and not door.open, "no walk opens the hidden niche's door and E rattles it")
	for i in 10:
		_hold_free(player, Vector2(0, -1), 1)
		if door.open:
			break
	_check(player.tile == Vector2i(6, 1) and door.open and door.lock == "hidden_niche"
		and _main.party_log.last(1) == ["The slab swings aside: a stair goes down into the dark."] and heard.has("The slab swings aside: a stair goes down into the dark."),
		"pressing into the hidden niche finds it, said on the finder's screen too: the door open, its lock kept (747: shut, it gives only to those it is revealed to), and said (%s)" % [_main.party_log.last(1)])
	_check(World.hidden_niche()["open"], "the marker says open")
	# 608 amended (2): the finder stands while the slab gives way, pressing
	# on or not; the stair behind is not taken through the shut slab.
	_check(World.free_held(player), "the finder is held while the slab gives way")
	_hold_free(player, Vector2(0, -1), 5)
	_check(player.tile == Vector2i(6, 1) and World.zone.name == "lt_niche", "pressing on, held: still before it, the stair not yet taken (%s)" % [player.tile])
	# 608 amended (2): a shut, locked door before a link shuts the way: the
	# press finds the niche (again, here: held anew), it never takes the
	# stair through the slab.
	door.open = false
	door.lock = "hidden_niche"
	var taken: Array = []
	var on_bump := func(by: GridEntity, at: Vector2i) -> void: taken.append(at)
	World.link_bumped.connect(on_bump)
	World._step_refused(player, Vector2i(0, -1))
	_check(taken.is_empty(), "a step at the link through the locked slab is no bump on the link (%s)" % [taken])
	# The same through a free body's press (_free_pressed), free walk on.
	_hold_free(player, Vector2(0, 0), Main.NICHE_FOUND_HOLD)
	door.open = false
	door.lock = "hidden_niche"
	for i in 10:
		_hold_free(player, Vector2(0, -1), 1)
		if door.open:
			break
	World.link_bumped.disconnect(on_bump)
	_check(World.free_body(player) and taken.is_empty() and door.open and player.tile == Vector2i(6, 1) and World.zone.name == "lt_niche",
		"pressed with free walk on: the slab found, the stair behind it not taken through it (%s, %s)" % [taken, player.tile])
	_check(door.open and door.lock == "hidden_niche", "the press found it again")
	_hold_free(player, Vector2(0, 0), Main.NICHE_FOUND_HOLD)
	# 608 amended: found, no draft, not even in a new generation; laid again
	# with the door shut, it is felt again.
	_main._regen["lt_niche"] = {"generation": 1, "at_step": 0}
	_hold_free(player, Vector2(-1, 0), 4)
	_check(player.tile == Vector2i(5, 1) and heard.count(draft) == 1,
		"found, a cell crossed in the hall feels no draft (%s)" % [heard])
	World.hold_door(door, true, "hidden_niche")
	_hold_free(player, Vector2(1, 0), 4)
	_check(not door.open and player.tile == Vector2i(6, 1) and heard.count(draft) == 2,
		"laid again with the door shut, the draft is felt once more (%s)" % [heard])
	Net.message_received.disconnect(hear)
	World.hold_door(door, false, "hidden_niche")
	door.open = true
	_hold_free(player, Vector2(0, -1), 6)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(World.zone.name == "test_room" or World.peer_zone.get(Net.local_id, "") == "test_room", "the alcove behind it is walked into and its stair taken (%s)" % [World.peer_zone.get(Net.local_id, "")])
	# Shut and locked again (a restart lays the door locked): a climb from
	# below pushes it open from behind.
	var there: Zone = World.zones["lt_niche"]
	var was := World.enter(there)
	World.hold_door(door, true, "hidden_niche")
	World.enter(was)
	_check(not door.open and door.lock == "hidden_niche", "locked again")
	_main.travel(Net.local_id, "lt_niche", "from_below")
	_check(door.open and door.lock.is_empty() and _player().tile == Vector2i(6, 1) and _main.party_log.last(2)[0] == "The slab swings aside from behind."
		and _heard.has("The slab swings aside from behind."),
		"come up from below, the slab is pushed open from behind and said, on their screen too; the player stands before it (%s)" % [_main.party_log.last(2)])
	# 672 amended, dungeon's side: the world's barrow is every player's,
	# laid again by the console's zone reset, the slab shut and locked.
	_main.admin_command("zone reset lt_niche")
	var laid := World.door_on(key)
	_check(laid != null and not laid.open and laid.lock == "hidden_niche", "zone reset lays the found niche shut and locked again")
	_main.load_map("test_room")
	_main._regen.erase("lt_niche")
	Level.unregister("lt_niche")


func _test_barrow_level() -> void:
	print("\n== levels/barrow, barrow_deep (decisions 542, 580, 666): the barrow in two depths, the Hall off the Ossuary; a test run never writes them ==")
	var barrow := Level.load_level("barrow")
	var deep := Level.load_level("barrow_deep")
	_check(barrow["display_name"] == "The Crypt of the Fallen" and barrow["size"] == Vector2i(80, 60) and barrow["warnings"].is_empty(),
		"The Crypt of the Fallen, 80 x 60 (580), parses with no warning (%s)" % [barrow["warnings"]])
	_check(deep["display_name"] == "The Ossuary" and deep["size"] == Vector2i(100, 80) and deep["warnings"].is_empty()
		and not Level.exists("barrow_lair") and not Level.overlaid("barrow_lair") and Level.RETIRED.get("barrow_lair") == ["barrow_deep", Vector2i(49, 2)],
		"the Ossuary, 100 x 80, parses with no warning; the dark below is retired, its players bound for the Ossuary's stair foot (666; %s)" % [deep["warnings"]])
	# Moss and webs (647): the templates' own, the rest rolled by a generation.
	var corner_webs := func(level: Dictionary) -> int:
		return level["terrain"]["decor"].filter(func(d: Dictionary) -> bool: return d["kind"] == "web_corner").size()
	# 806 amended (3): and the light shaft under the temple yard's grate, its skylight.
	var shafts: Array = barrow["terrain"]["decor"].filter(func(d: Dictionary) -> bool: return d["kind"] == "light_shaft")
	var skylights: Array = barrow["terrain"]["skylights"]
	# And the band's bedding in its camp (870; the coordinator's ruling, combat's ask: the kits lie by it).
	var bedding: Array = barrow["terrain"]["decor"].filter(func(d: Dictionary) -> bool: return d["kind"] == "bedroll")
	_check(barrow["terrain"]["decor"].size() == 6 and bedding.size() == 2 and corner_webs.call(barrow) == 2 and shafts.size() == 1 and skylights.size() == 1
			and shafts[0]["cell"] == Vector2i(46, 13) and skylights[0]["at"] == Vector2i(46, 13)
			and deep["terrain"]["decor"].size() == 30 and corner_webs.call(deep) == 4,
		"the first hall holds two cobwebbed corners, a strip of moss and the light shaft under its skylight, the Ossuary's Hall of Fallen Souls its moss and four webbed corners (%d, %s, %d)" % [barrow["terrain"]["decor"].size(), skylights, deep["terrain"]["decor"].size()])
	_check(Regen.marked("barrow") and Regen.config_of("barrow")["anchors"].size() == 4 and int(Regen.config_of("barrow").get("layer", 0)) == 1
		and Regen.marked("barrow_deep") and Regen.config_of("barrow_deep")["anchors"].size() == 2 and int(Regen.config_of("barrow_deep").get("layer", 0)) == 2
		and Regen.config_of("barrow_deep")["anchors"][1]["name"] == "lair" and Regen.config_of("barrow_deep").get("monsters") == {"skeleton": 6, "skeleton_guard": 3}
		and int(Regen.config_of("barrow").get("ways", 0)) == 5 and int(Regen.config_of("barrow_deep").get("ways", 0)) == 5,
		"both depths are marked to regenerate in the barrow style, layers 1 and 2, every way five wide; the Ossuary's far anchor the lair, its dead three grave guards each leading two skeletons (823, dungeon's side)")
	var kinds := {}
	var grave_marked := {}
	var guards_marked := 0
	for level: Dictionary in [barrow, deep]:
		for spec: Dictionary in level["entities"]:
			var kind := str(spec.get("kind", spec["name"].rstrip("0123456789").to_lower()))
			kinds[kind] = int(kinds.get(kind, 0)) + 1
			# Grave goods (555, dungeon's side): the level key marks the altar,
			# the guards and the draugr; the runner's pack, a robber's, is exempt.
			var marked: bool = spec.get("props", {}).get("grave", false) == true
			grave_marked[spec["name"]] = marked
			if kind == "skeleton_guard" and marked:
				guards_marked += 1
	var stone_at: Array = (barrow["entities"] as Array).filter(func(spec: Dictionary) -> bool: return spec["name"].begins_with("Offering stone")).map(func(spec: Dictionary) -> Variant: return spec["tile"])
	_check(not kinds.has("skeleton_guard") and kinds.get("draugr", 0) == 1 and kinds.get("offering stone", 0) == 1 and kinds.get("runner's pack", 0) == 1
		and kinds.get("robbers' chest", 0) == 1 and kinds.get("astral_knight", 0) == 1 and stone_at == [OFFERING_AT]
		and kinds.get("robbers' bundle", 0) == 1 and barrow["places"].has("niche") and barrow["entities"].size() == 5 and deep["entities"].size() == 2 and kinds.get("chest", 0) == 1,
		"the Offering stone in the First Hall east of the bier, the Low Hall's guards gone (747 amended (13)), the fallen knight (747), Pip's niche, the Runner's pack and the robbers' chest (742), the Robbers' bundle by their bedding (870) on the first layer, the draugr in his hall in the Ossuary and its chest by the throne (%s, the stone at %s)" % [kinds, stone_at])
	_check(grave_marked.get("Offering stone", false) and grave_marked.get("Draugr", false) and not grave_marked.get("Runner's pack", true) and not grave_marked.get("Robbers' bundle", true) and guards_marked == 0,
		"grave_goods marks the offering stone and the draugr as grave goods, the runner's pack exempt (%s)" % [grave_marked])
	# 747 amended (13): the stone moved by the template's word, so a saved one comes back on it,
	# things and all; and what lies outside the anchors at a re-lay gathers at the arrival.
	_check(Regen.moved_markers("barrow") == {"38,30": OFFERING_AT} and Regen.keep_cell("barrow") == Vector2i(39, 2),
		"the barrow names the stone's move from the Low Hall (38,30) to %s, and its re-lay gathers the ground on the arrival (%s, %s)" % [OFFERING_AT, Regen.moved_markers("barrow"), Regen.keep_cell("barrow")])
	_check(barrow["links"].size() == 3 and barrow["links"][0]["to_map"] == "wilds" and barrow["links"][0]["to_spawn"] == "from_crypt"
		and barrow["links"][1]["to_map"] == "barrow_deep" and barrow["links"][1]["to_spawn"] == "from_above"
		and barrow["links"][2]["tile"] == Vector2i(31, 52) and barrow["links"][2]["to_map"] == "wilds" and barrow["links"][2]["to_spawn"] == "from_barrow"
		and deep["links"].size() == 1 and deep["links"][0]["to_map"] == "barrow" and deep["links"][0]["to_spawn"] == "from_below"
		and not deep["spawn_points"].has("from_temple") and barrow["spawn_points"].has("from_deep") and barrow["terrain"]["floor"].has(Vector2i(30, 8))
		and not deep["terrain"]["floor"].has(Vector2i(49, 77)),
		"the stairs link the depths both ways; 832 switched on: the First Hall's stair up to the chapel, the camp's breach out by the mound; 896 switched on: no shortcut either way, (30,8) plain floor, (49,77) rock, from_temple gone, from_deep kept for the throne's sitter (%s)" % [barrow["links"]])
	# The rooms named on entering (666, ui's 665 card).
	var barrow_rooms: Dictionary = Level.template_config("barrow").get("rooms", {})
	var deep_rooms: Dictionary = Level.template_config("barrow_deep").get("rooms", {})
	_check(barrow_rooms.keys() == ["entrance", "camp"] and str(barrow_rooms["entrance"]["name"]) == "The First Hall"
		and deep_rooms.keys() == ["entrance", "lair"] and str(deep_rooms["lair"]["name"]) == "The Hall of Fallen Souls" and Level.town_wall_rect(deep_rooms["lair"]) == Rect2i(34, 56, 32, 22)
		and str(deep_rooms["entrance"]["name"]) == "The Charnel Vault" and Level.town_wall_rect(deep_rooms["entrance"]) == Rect2i(46, 1, 8, 6),
		"the first hall and the camp are named on the barrow (the Low Hall gone, 747 amended (13)), the Charnel Vault (714) and the Hall of Fallen Souls on the Ossuary, each on its anchor (%s %s)" % [barrow_rooms.keys(), deep_rooms.keys()])
	# The hidden door (608): the template's stair lies behind the south-east
	# niche's door, the link hidden; the 14 niches read.
	var niches: Array = barrow["terrain"]["niches"]
	var hidden: Array = niches.filter(func(n: Dictionary) -> bool: return n["kind"] == "hidden")
	_check(barrow["links"][1]["hidden"] and barrow["links"][1]["tile"] == Vector2i(52, 16) and not barrow["links"][0]["hidden"] and not deep["links"][0]["hidden"]
		and niches.size() == 14 and hidden.size() == 1 and hidden[0]["cell"] == Vector2i(51, 16) and hidden[0]["edge"] == Terrain.edge_key(Vector2i(51, 16), Vector2i(1, 0))
		and hidden[0]["out"] == Vector2i(-1, 0) and barrow["terrain"]["edges"][hidden[0]["edge"]] == Terrain.Edge.DOOR and barrow["spawn_points"]["from_below"] == Vector2i(51, 16),
		"the template's stair down is hidden behind the first hall's south-east niche, a door edge, from_below before it; 14 niches on the hall's walls (%d, %s)" % [niches.size(), hidden])
	var floor_ok := true
	for pair: Array in [[barrow, "from_chapel"], [barrow, "from_deep"], [barrow, "from_breach"], [barrow, "from_below"], [deep, "from_above"]]:
		var level: Dictionary = pair[0]
		if not level["spawn_points"].has(pair[1]) or not level["terrain"]["floor"].has(level["spawn_points"][pair[1]]):
			floor_ok = false
	var wilds := Level.load_level("wilds")
	var shortcut: Array = barrow["links"].filter(func(l: Dictionary) -> bool: return l["to_spawn"] == "from_temple")
	var chapel_stair: Array = wilds["links"].filter(func(l: Dictionary) -> bool: return l["to_spawn"] == "from_chapel")
	_check(floor_ok and shortcut.is_empty()
		and chapel_stair.size() == 1 and chapel_stair[0]["to_map"] == "barrow" and chapel_stair[0]["sealed"] == ""
		and wilds["links"].filter(func(l: Dictionary) -> bool: return l["to_map"] == "barrow_deep").is_empty(),
		"every spawn point the stairs and the wilds come in by is floor; no quick way down from the First Hall (896 switched on), the wilds' temple stair open into the First Hall, none from the wilds into the deep")
	_check(Level.template_config("barrow_deep").get("stills", []) == ["barrow"] and not Level.template_config("barrow_deep").has("damp")
		and not Level.template_config("barrow_deep").has("ambient") and not Level.template_config("barrow_deep").has("dead"),
		"his rest stills the barrow above as well as his own zone; the dark below's damp, light and word on the dead are gone with it (666)")
	# The halls dressed (580 step 3): the burial table and the pillars are
	# solid doorless buildings (their cells out of the floor, sight stopped),
	# the dais one level up with its front row stairs and its sides ledges,
	# and no way in the dressed halls is one cell wide (612, heights seen).
	var king_table: Array = barrow["buildings"].filter(func(b: Dictionary) -> bool: return b["slot"] == "building.burial_table")
	var pillars: Array = deep["buildings"].filter(func(b: Dictionary) -> bool: return b["slot"] == "building.crypt_pillar")
	_check(king_table.size() == 1 and king_table[0]["rect"] == Rect2i(38, 8, 3, 2) and barrow["terrain"]["solid"].size() == 6
		and not barrow["terrain"]["floor"].has(Vector2i(39, 8)) and pillars.size() == 5 and deep["terrain"]["solid"].size() == 20 + 9 + 8 and deep["terrain"]["floor"].has(Vector2i(49, 70))
		and not deep["terrain"]["floor"].has(Vector2i(49, 60)) and deep["terrain"]["floor"].has(Vector2i(48, 62)),
		"the burial table (3 x 2), the five pillars (2 x 2; none before his seat, 580 amended (2)), the round table (3 x 3) and the four broken tables (2 x 1) stand as solid buildings, their cells out of the floor (%d, %d solid)" % [barrow["terrain"]["solid"].size(), deep["terrain"]["solid"].size()])
	# The feast (3b): the chairs and the throne are walked onto, the throne at
	# the draugr's cell facing the hall, the broken tables along the walls.
	var by_slot := {}
	for b: Dictionary in deep["buildings"]:
		by_slot[b["slot"]] = int(by_slot.get(b["slot"], 0)) + 1
	var throne: Array = deep["buildings"].filter(func(b: Dictionary) -> bool: return b["slot"] == "building.throne")
	var broken: Array = deep["buildings"].filter(func(b: Dictionary) -> bool: return b["slot"] == "building.broken_table")
	var draugr: Array = deep["entities"].filter(func(spec: Dictionary) -> bool: return spec["name"] == "Draugr")
	_check(by_slot.get("building.hall_chair", 0) == 8 and by_slot.get("building.round_table", 0) == 1 and broken.size() == 4
		and throne.size() == 1 and throne[0]["rect"] == Rect2i(49, 75, 1, 1) and throne[0]["facing"] == Vector2i(0, -1)
		and draugr.size() == 1 and draugr[0]["tile"] == Vector2i(49, 75) and deep["terrain"]["floor"].has(Vector2i(49, 75)) and deep["terrain"]["floor"].has(Vector2i(48, 63))
		and not deep["terrain"]["floor"].has(Vector2i(49, 65)) and broken.all(func(b: Dictionary) -> bool: return (b["rect"] as Rect2i).size == Vector2i(1, 2) and (b["rect"] as Rect2i).position.x in [34, 65]),
		"eight chairs and the throne walked onto, the throne at the draugr's cell facing the hall, the round table solid, the broken tables two cells along the east and west walls (%s)" % [by_slot])
	var dais_ok := true
	for cell in Level.rect_cells(Rect2i(44, 74, 12, 4)):
		if int(deep["terrain"]["heights"].get(cell, 0)) != 1:
			dais_ok = false
	var stairs: Dictionary = deep["terrain"]["stairs"]
	var stairs_ok := stairs.size() == 12
	for x in range(44, 56):
		if stairs.get(Vector2i(x, 73)) != Vector2i(0, 1):
			stairs_ok = false
	_check(dais_ok and stairs_ok and int(deep["terrain"]["heights"].get(Vector2i(43, 75), 0)) == 0 and int(deep["terrain"]["heights"].get(Vector2i(49, 73), 0)) == 0
		and deep["terrain"]["floor"].has(Vector2i(49, 76)),
		"the dais is one level up, its front row twelve stairs climbing south, its back row against the wall, the cell behind the throne floor (%d stairs)" % stairs.size())
	_check(Level.narrow_runs(barrow["terrain"]).is_empty() and Level.narrow_runs(deep["terrain"]).is_empty(),
		"no way in the dressed halls is one cell wide, the table, the pillars and the dais's ledges seen (%s)" % [Level.narrow_runs(deep["terrain"]).slice(0, 8)])
	var made := Regen.generate("barrow", 1)
	var made_deep := Regen.generate("barrow_deep", 1)
	_check(not made.is_empty() and Regen.connected(LevelMap.from_image(made["layout"], made["config"]), made["anchors"])
		and not made_deep.is_empty() and Regen.connected(LevelMap.from_image(made_deep["layout"], made_deep["config"]), made_deep["anchors"]),
		"a generation of each depth is laid and joins every anchor (%d and %d tries)" % [made.get("tries", 0), made_deep.get("tries", 0)])
	var gen_barrow := Level.parse(made["layout"], made["height"], made["config"])
	# 806 amended (5): each chest's guard holds its post (Idle.GUARD), the
	# robbers' chest's (Brand, named and guarding) among them.
	var posts: Array[Vector2i] = []
	var brand_guards := false
	for spec: Dictionary in gen_barrow["entities"]:
		if (spec.get("idle", {}) as Dictionary).get("mode", "") == "guard":
			posts.append(spec["tile"])
			brand_guards = brand_guards or spec.get("named", "") == "brand"
	var loose: Array = []
	for spec: Dictionary in gen_barrow["entities"]:
		if str(spec.get("script", "")) == Level.CHEST and (spec.get("props", {}) as Dictionary).has("cache") 				and not posts.any(func(p: Vector2i) -> bool: return _cells_apart(p, spec["tile"]) <= 4):
			loose.append(spec["tile"])
	_check(loose.is_empty() and posts.size() >= 3 and brand_guards,
		"the barrow's chests each with a guard holding its post within 4 cells, Brand at the robbers' chest (%d posts, loose %s)" % [posts.size(), loose])
	var gen_deep := Level.parse(made_deep["layout"], made_deep["height"], made_deep["config"])
	# The crypt's (806 amended): the First Hall's table, and each tomb's
	# sarcophagi and the chapel's bier the generation lays, all solid.
	var laid_solid := 0
	for building: Dictionary in gen_barrow["buildings"]:
		laid_solid += (building["rect"] as Rect2i).get_area()
	# 832: the deep laid by the crypt (its switch-on) adds its tomb chambers'
	# sarcophagi, all solid, to the Hall's own 37 (pillars, table, throne).
	var deep_laid := 0
	if str(Regen.config_of("barrow_deep").get("generator", "")) == "crypt":
		var hall_pieces: Array = Level.template_config("barrow_deep").get("buildings", []).map(func(b: Dictionary) -> Vector2i: return Vector2i(int(b["at"][0]), int(b["at"][1])))
		for building: Dictionary in gen_deep["buildings"]:
			if not (building["rect"] as Rect2i).position in hall_pieces:
				deep_laid += (building["rect"] as Rect2i).get_area()
	_check(gen_barrow["warnings"].is_empty() and gen_deep["warnings"].is_empty() and gen_barrow["terrain"]["solid"].size() == laid_solid and laid_solid > 6 and gen_deep["terrain"]["solid"].size() == 20 + 9 + 8 + deep_laid
		and gen_deep["terrain"]["stairs"].size() == 12 and int(gen_deep["terrain"]["heights"].get(Vector2i(49, 75), 0)) == 1 and made_deep["height"] != null
		and Level.narrow_runs(gen_barrow["terrain"]).is_empty() and Level.narrow_runs(gen_deep["terrain"]).is_empty()
		and made["config"].get("rooms", {}).size() == 2 and made_deep["config"].get("rooms", {}).has("lair"),
		"a generation keeps the dressed halls: the table and pillars solid, the dais raised with its stairs, no way one cell wide, and the named rooms (%s %s; solid %d of %d laid; deep solid %d of %d; narrow %s)" % [gen_barrow["warnings"], gen_deep["warnings"],
			gen_barrow["terrain"]["solid"].size(), laid_solid, gen_deep["terrain"]["solid"].size(), 37 + deep_laid, Level.narrow_runs(gen_barrow["terrain"]).slice(0, 8)])
	# The co-op family tomb (crypt landing 2): one plate set, two plates at
	# least three apart, its door a door edge with the vault's cache chest
	# behind it and a boulder in the tomb; one loose niche with voice's three
	# clues; the co-op rule clean; and the secrets never in the terrain
	# message a client is sent.
	var plates: Array = gen_barrow["terrain"]["plates"]
	var secrets: Array = gen_barrow["secrets"]
	var plate_ok := plates.size() == 1 and (plates[0]["cells"] as Array).size() == 2
	var behind := {}
	var boulders := 0
	for spec: Dictionary in gen_barrow["entities"]:
		if spec.get("script") == Level.CHEST and not str(spec.get("props", {}).get("cache", "")).is_empty():
			behind[spec["tile"]] = true
		elif spec.get("script") == Level.PUSHABLE:
			boulders += 1
	if plate_ok:
		var cells: Array = plates[0]["cells"]
		var gap: Vector2i = (cells[0] as Vector2i) - (cells[1] as Vector2i)
		var sides := Terrain.edge_cells(plates[0]["edge"])
		plate_ok = absi(gap.x) + absi(gap.y) >= 3 and int(gen_barrow["terrain"]["edges"].get(plates[0]["edge"], 0)) == Terrain.Edge.DOOR \
			and (behind.has(sides[0]) or behind.has(sides[1])) and boulders >= 1
	var coop_faults := Regen.layout_faults(made, Regen.config_of("barrow")).filter(func(fault: Dictionary) -> bool: return fault["rule"] == "coop")
	_check(plate_ok and secrets.size() == 1 and (secrets[0]["clues"] as Array).size() == 3 and coop_faults.is_empty(),
		"the crypt's sealed vault is the co-op tomb: two plates three apart, a cache behind its bricked door, a boulder for a lone player, a loose niche with three clues (%s; %s; %s)" % [plates, secrets.map(func(secret: Dictionary) -> Array: return [secret["cell"], secret["clues"]]), coop_faults])
	Level.register("coop_secrets_test", made["layout"], made["height"], made["config"])
	var sent: Dictionary = BuilderHost.terrain_message("coop_secrets_test")["config"]
	_check(not sent.has("secrets") and made["config"].has("secrets") and Level.secrets_of("coop_secrets_test").size() == 1,
		"a level's secrets stay on the server: its terrain message has none, its level still does")
	Level.unregister("coop_secrets_test")
	# Armour as grave goods (622, dungeon's side): the Ossuary's chests roll
	# mail shirts; every generated chest's goods carry the grave mark; nowhere
	# else gives armour. The rolls are seeded by level and cell, so which
	# generation gives what is fixed. The Hall's one chest, on the dais beside
	# the throne, rolls its own table, plate among it (666, the coordinator).
	var first_mail := 0
	var first_plate := 0
	var unmarked := 0
	var chests_seen := 0
	for generation in range(1, 25):
		var laid := Regen.generate("barrow_deep", generation)
		var parsed := Level.parse(laid["layout"], laid["height"], laid["config"])
		for spec: Dictionary in parsed["entities"]:
			if str(spec.get("script", "")) != Level.CHEST:
				continue
			chests_seen += 1
			var props: Dictionary = spec.get("props", {})
			if props.get("grave", false) != true:
				unmarked += 1
			# 599 amended (2): a loot chest is laid as its table's cache, so its goods
			# are what that table gives (rolled here by the generation and cell).
			var goods: Array = Array(Items.roll_loot(str(props["cache"]), "deep%d:%s" % [generation, spec["tile"]], 64, true)) if props.has("cache") \
					else props.get("slots", [])
			if spec["tile"] == Sheet.LAIR_CHEST:
				if goods.has("plate_armour") and first_plate == 0:
					first_plate = generation
			elif goods.has("mail_armour") and first_mail == 0:
				first_mail = generation
		if first_mail > 0 and first_plate > 0 and chests_seen >= 6:  # 832: the crypt deep lays three and the Hall's one a generation
			break
	var hall_entry: Array = Level.template_config("barrow_deep").get("entities", []).filter(func(e: Dictionary) -> bool: return Vector2i(int(e["at"][0]), int(e["at"][1])) == Sheet.LAIR_CHEST)
	_check(first_mail > 0 and unmarked == 0 and chests_seen >= 6 and hall_entry.size() == 1 and hall_entry[0].get("loot") == "fallen_grave",
		"a generation places mail in the Ossuary, every chest's goods grave marked; the Hall's chest rolls fallen_grave (first mail in generation %d; %d chests, %d unmarked)" % [first_mail, chests_seen, unmarked])
	_check(first_plate > 0, "a generation puts plate in the Hall's chest (first in generation %d of 24)" % first_plate)
	var armour_elsewhere: Array[String] = []
	for table: String in Items.loot_tables():
		if table in ["ossuary_grave", "fallen_grave"]:
			continue
		for row: Dictionary in Items.loot_tables()[table]:
			if Items.has_tag(str(row["item"]), "armour") and table not in armour_elsewhere:
				armour_elsewhere.append(table)
	_check(armour_elsewhere.is_empty() and Level.template_config("barrow_deep").get("loot", {}).get("chest", "") == "ossuary_grave" and not Level.template_config("barrow").has("loot"),
		"the crypt's chests are the only loot that gives armour: the Ossuary's table, none on the first layer (%s)" % [armour_elsewhere])
	_check(not Net.regenerate and not Regen.may_write() and not _main._regenerate_if_due("barrow") and not Level.overlaid("barrow"),
		"off unless the server runs --regenerate: nothing is laid, the barrow stays its template")
	_check(_main.admin_command("regenerate on") == "regenerate on: the shifting levels are laid again when due" and Net.regenerate, "the console switches it on")
	_check(Regen.in_test_run() and not Regen.may_write() and not _main._regenerate_if_due("barrow") and not Level.overlaid("barrow"),
		"and even on, a test run on the shared overlay writes nothing there")
	_check(Regen.is_test_scene(PackedStringArray(["--headless", "--scene", "tests/level_test.tscn"])) and Regen.is_test_scene(PackedStringArray(["res://tests" + char(92) + "x.tscn"]))
		and not Regen.is_test_scene(PackedStringArray(["--scene", "tools/make_hills.tscn"])) and not Regen.is_test_scene(PackedStringArray(["--server", "--regenerate"])),
		"a scene under tests/ is a test run without the marker too (199 amended); a tool's scene or the server is not")
	var listed: String = _main.admin_command("regenerate")
	_check(listed.begins_with("regenerate on") and "barrow: generation 0, every 3 days" in listed and "barrow_deep: generation 0, every 3 days" in listed
		and not "barrow_lair" in listed, "the console lists both depths, the retired one not (%s)" % listed.replace("\n", "; "))
	_check(_main.admin_command("regenerate off").begins_with("regenerate off") and not Net.regenerate, "and switches it off")
	_check(_main.admin_command("regenerate now barrow") == "regenerate now: refused in a test run on the shared overlay" and not Level.overlaid("barrow"),
		"regenerate now (541 amended) is refused in a test run on the shared overlay: the barrow stays its template")
	_check(_main.admin_command("regenerate now castle").begins_with("regenerate now: castle is no shifting level"), "and names a level that does not shift")


## Moss and webs (647): level.json's "decor" read by Level.decor_from,
## each kind held to its place, the bad ones said and left out.
func _test_decor() -> void:
	print("\n== moss and webs (647): a patch on the floor, a strip at a wall's foot, a web in a corner or across an open niche; the misplaced left out ==")
	# The hidden door's 8 x 6 room again: three niches in its north wall,
	# the east one hidden with its alcove behind a door edge.
	var rows: Array[String] = []
	for py in 6 * 2 - 1:
		var row := ""
		for px in 8 * 2 - 1:
			var cell := Vector2i(px / 2, py / 2)
			var floor_here := px % 2 == 0 and py % 2 == 0 and (cell.x >= 1 and cell.x <= 6 and cell.y >= 1 and cell.y <= 4 or cell == Vector2i(6, 0))
			row += "+" if px == 12 and py == 1 else ("." if floor_here else " ")
		rows.append(row)
	Level.register("lt_decor", Level.image_from_rows(rows, {Vector2i(3, 3): "start", Vector2i(6, 0): "link"}), null,
		{"niches": [[2, 1, 0, -1, "a", 1], [4, 1, 0, -1, "c", 2], [6, 1, 0, -1, "hidden", 1]],
			"links": [{"at": [6, 0], "to_map": "test_room", "to_spawn": "", "hidden": true}],
			"decor": [[3, 3, 0, 0, "moss_patch", 3], [2, 4, 0, 1, "moss_strip", 2], [1, 1, -1, -1, "web_corner", 1], [2, 1, 0, -1, "web_niche", 2],
				[4, 1, 0, -1, "web_niche", 1], [6, 1, 0, -1, "web_niche", 1], [3, 2, 1, 0, "moss_strip", 1], [3, 3, 1, 0, "moss_patch", 1],
				[3, 3, 1, 1, "web_corner", 1], [3, 2, 0, 0, "moss_patch", 4], [3, 3, 0, 0, "moss_patch", 1], [5, 5, 0, 0, "moss_patch", 1], [1, 1, "x"],
				# 658: a faced flat piece and a rolled one, an edge piece on a wall edge and on an open one; a flat piece on a diagonal and an edge piece with no step are not.
				[5, 2, 1, 0, "fallen_guard", 2], [5, 3, 0, 0, "fallen_guard", 1], [1, 2, -1, 0, "grave_fence", 3], [4, 3, 0, -1, "grave_fence", 1],
				[5, 4, 1, 1, "fallen_guard", 1], [4, 4, 0, 0, "grave_fence", 1]]})
	var parsed := Level.load_level("lt_decor")
	var decor: Array = parsed["terrain"]["decor"]
	var kinds := decor.map(func(d: Dictionary) -> String: return d["kind"])
	_check(decor.size() == 8 and kinds == ["moss_patch", "moss_strip", "web_corner", "web_niche", "fallen_guard", "fallen_guard", "grave_fence", "grave_fence"],
		"the eight well placed are read in order: a patch, a strip, a corner web, a niche web, two fallen guards, two fence sections (%s)" % [kinds])
	_check(decor.size() == 8 and decor[0]["out"] == Vector2i.ZERO and not decor[0].has("edge") and decor[0]["variant"] == 3
		and decor[1]["edge"] == Terrain.edge_key(Vector2i(2, 4), Vector2i(0, 1)) and decor[1]["out"] == Vector2i(0, 1)
		and decor[2]["out"] == Vector2i(-1, -1) and not decor[2].has("edge")
		and decor[3]["edge"] == parsed["terrain"]["niches"][0]["edge"] and decor[3]["out"] == Vector2i(0, -1) and decor[3]["variant"] == 2,
		"each as terrain reads it: the patch with no edge, the strip and the niche web with theirs, the corner web with its diagonal (%s)" % [decor])
	_check(decor.size() == 8 and decor[4]["out"] == Vector2i(1, 0) and not decor[4].has("edge") and decor[4]["variant"] == 2 and decor[5]["out"] == Vector2i.ZERO
		and decor[6]["edge"] == Terrain.edge_key(Vector2i(1, 2), Vector2i(-1, 0)) and decor[7]["edge"] == Terrain.edge_key(Vector2i(4, 3), Vector2i(0, -1))
		and int(parsed["terrain"]["edges"].get(decor[7]["edge"], Terrain.Edge.OPEN)) == Terrain.Edge.OPEN,
		"658: the faced guard keeps his facing and no edge, the rolled one his (0, 0); the fence sections carry their edge, the wall's and the open one's alike (%s)" % [decor.slice(4)])
	var warnings: Array = parsed["warnings"].filter(func(w: String) -> bool: return w.begins_with("decor "))
	_check(warnings.size() == 11 and parsed["warnings"].size() == 11,
		"the eleven misplaced are said and left out: a web on a sealed niche, on the hidden one, a strip on an open edge, a patch with a step, a corner with no wall, a variant the kind has not, a second patch on the cell, one in the rock, one malformed, a guard on a diagonal, a fence with no step (%s)" % [warnings])
	Level.register("lt_decor_bad", Level.image_from_rows(rows, {Vector2i(3, 3): "start"}), null, {"decor": {"moss": 1}})
	_check(Level.load_level("lt_decor_bad")["warnings"] == ["\"decor\" in level.json is not a list"], "a \"decor\" that is no list is said")
	# Out of doors (658; maps' grave fence on Held, 654): an edge piece on an
	# open grass edge and on the map's own edge, a flat piece on grass, read
	# in with nothing said.
	var grass := Image.create_empty(6 * 2 + 1, 4 * 2 + 1, false, Image.FORMAT_RGBA8)
	grass.fill(Color(str(Level.LEGEND["grass"])))
	grass.set_pixel(2, 2, Color(str(Level.LEGEND["start"])))
	Level.register("lt_decor_out", grass, null, {"name": "Fenced", "outdoor": true,
		"decor": [[2, 1, 0, 1, "grave_fence", 2], [3, 1, 0, 1, "grave_fence", 1], [0, 0, -1, 0, "grave_fence", 3], [4, 2, -1, 0, "fallen_guard", 1]]})
	var out := Level.load_level("lt_decor_out")
	var fence: Array = out["terrain"]["decor"]
	_check(out["warnings"].is_empty() and fence.size() == 4 and fence[0]["edge"] == Terrain.edge_key(Vector2i(2, 1), Vector2i(0, 1))
		and fence[1]["edge"] == Terrain.edge_key(Vector2i(3, 1), Vector2i(0, 1)) and fence[2]["edge"] == Terrain.edge_key(Vector2i(0, 0), Vector2i(-1, 0))
		and fence[3]["kind"] == "fallen_guard" and fence[3]["out"] == Vector2i(-1, 0),
		"out of doors a fence runs along two open grass edges and the map's edge, a body lies on the grass facing west, nothing said (%s; %s)" % [out["warnings"], fence])


## The Dwarven Halls under the castle (613, dungeon's side): the template,
## its stair both ways with the castle's guardroom (maps' side), the
## smith's place between the forge's anvils.
func _test_castle_halls_level() -> void:
	print("\n== levels/castle_halls (613): the Dwarven Halls and the castle's guardroom stair ==")
	var halls := Level.load_level("castle_halls")
	var castle := Level.load_level("castle")
	_check(halls["display_name"] == "The Dwarven Halls" and halls["size"] == Vector2i(90, 70) and halls["warnings"].is_empty()
		and int(Level.template("castle_halls")["config"].get("depth", 0)) == 1,
		"The Dwarven Halls, 90 x 70, depth 1, parse with no warning (%s)" % [halls["warnings"]])
	var block := Regen.config_of("castle_halls")
	_check(Regen.marked("castle_halls") and block.get("style") == "dwarven" and int(block.get("ways", 0)) == 5 and block["anchors"].size() == 3 and block.get("entrance") == "stair_foot"
		and block.get("monsters") == {"imp": 4, "sneak": 3, "brute": 1} and block.get("packs") is Dictionary and block["packs"].keys() == ["sneak"] and str(block["packs"]["sneak"].get("of")) == "sneak" and int(block["packs"]["sneak"].get("size", 0)) == 3 and block.get("uses") == "hold" and block.get("heart") == "forge",
		"marked to regenerate in the dwarven style, ways five wide, three anchors, depth from the stair foot, enemy-ai's four imps, three sneaks as a pack (824) and a brute (806 amended (4): one a room, a guard before the forge), the hold's uses, the forge its heart (%s)" % [block.keys()])
	_check(halls["links"].size() == 1 and halls["links"][0]["tile"] == Vector2i(44, 1) and halls["links"][0]["to_map"] == "castle" and halls["links"][0]["to_spawn"] == "from_halls"
		and halls["spawn_points"].get("from_castle") == Vector2i(44, 2) and halls["terrain"]["floor"].has(Vector2i(44, 2)),
		"the stair up in the stair foot's north wall leads to the castle's from_halls; from_castle on the floor beside it")
	var down: Array = castle["links"].filter(func(link: Dictionary) -> bool: return link["to_map"] == "castle_halls")
	_check(down.size() == 1 and down[0]["tile"] == Vector2i(11, 18) and down[0]["to_spawn"] == "from_castle" and castle["spawn_points"].get("from_halls") == Vector2i(12, 18)
		and castle["terrain"]["floor"].has(Vector2i(12, 18)) and castle["terrain"]["floor"].has(Vector2i(11, 18)),
		"the castle's stair down stands in the guardroom at (11, 18), from_halls beside it on the floor (613, maps' side)")
	_check(castle["terrain"]["edges"].get(Terrain.edge_key(Vector2i(13, 19), Vector2i(1, 0))) == Terrain.Edge.DOOR
		and castle["terrain"]["edges"].get(Terrain.edge_key(Vector2i(11, 17), Vector2i(0, -1))) == Terrain.Edge.WALL
		and castle["terrain"]["edges"].get(Terrain.edge_key(Vector2i(11, 18), Vector2i(-1, 0))) == Terrain.Edge.WALL,
		"the guardroom's door opens onto the gate passage's west jamb; its north and west sides are walled")
	var place: Dictionary = halls["places"].get("dwarven_forge", {})
	_check(place.get("cell") == Vector2i(43, 64) and place.get("kind") == "refuge" and place.get("radius") == 3 and place.get("where") == "castle_dungeon",
		"the smith's refuge, dwarven_forge, stands between the forge's anvils, a refuge under the castle (%s)" % [place])
	var pillars: Array = halls["buildings"].filter(func(building: Dictionary) -> bool: return building["slot"] == "building.crypt_pillar")
	_check(pillars.size() == 4 and pillars.all(func(building: Dictionary) -> bool: return int(building.get("variant", 1)) == 2),
		"four dwarven pillars (crypt_pillar, variant 2)")
	# 613 amended: the forge and the rack stand solid, the guards lie where they fell.
	var forge: Array = halls["buildings"].filter(func(building: Dictionary) -> bool: return building["slot"] == "building.dwarven_forge")
	var rack: Array = halls["buildings"].filter(func(building: Dictionary) -> bool: return building["slot"] == "building.weapon_rack")
	_check(forge.size() == 1 and forge[0]["rect"] == Rect2i(42, 65, 6, 3) and forge[0]["facing"] == Vector2i(0, -1)
		and not halls["terrain"]["floor"].has(Vector2i(42, 65)) and not halls["terrain"]["floor"].has(Vector2i(47, 67)) and halls["terrain"]["solid"].has(Vector2i(44, 66))
		and halls["terrain"]["floor"].has(Vector2i(43, 64)),
		"the great forge stands 6 x 3 against the south wall facing north, solid, the stand cell before its anvils floor (%s)" % [forge])
	_check(rack.size() == 1 and rack[0]["rect"] == Rect2i(50, 67, 2, 1) and rack[0]["facing"] == Vector2i(0, -1)
		and not halls["terrain"]["floor"].has(Vector2i(50, 67)) and not halls["terrain"]["floor"].has(Vector2i(51, 67)) and halls["terrain"]["floor"].has(Vector2i(49, 67)) and halls["terrain"]["floor"].has(Vector2i(52, 67)),
		"the goblins' weapon rack stands 2 x 1 against the south wall east of the forge, solid, floor either side (%s)" % [rack])
	var guards: Array = halls["terrain"]["decor"].filter(func(d: Dictionary) -> bool: return d["kind"] == "fallen_guard")
	_check(halls["terrain"]["decor"].size() == 3 and guards.size() == 3 and guards[0]["cell"] == Vector2i(23, 30) and guards[0]["out"] == Vector2i(1, 0)
		and guards[1]["out"] == Vector2i(0, -1) and guards[1]["variant"] == 2 and guards[2]["out"] == Vector2i(-1, 0) and guards[2]["variant"] == 2
		and guards.all(func(d: Dictionary) -> bool: return Level.in_anchors(Regen.config_of("castle_halls")["anchors"], d["cell"])),
		"three of the smith's guards lie in the ambush, each with a facing, so all read as fallen from the usual camera: one on his side facing the cart, one face down running north, one face down toward the west wall (%s)" % [guards])
	_check(halls["entities"].size() == 5 and halls["links"][0]["cue"] == "up" and down[0]["cue"] == "down",
		"the template's five markers alone stand in the halls (the cart, two crates, two chests); the stairs cue up and down (%d, %s, %s)" % [halls["entities"].size(), halls["links"][0]["cue"], down[0]["cue"]])
	# 757, dungeon's side: every plain chest in the halls, the template's and
	# each generation's, rolls economy's dwarven_hoard (no armour: 622).
	var hoard: Array = (Items.loot_tables().get("dwarven_hoard", []) as Array).map(func(row: Dictionary) -> String: return str(row["item"]))
	var chests_seen := 0
	var stocked := 0
	var strays: Array = []
	for generation in range(1, 7):
		var laid := Regen.generate("castle_halls", generation)
		var parsed := Level.parse(laid["layout"], laid["height"], laid["config"])
		for spec: Dictionary in parsed["entities"]:
			var props: Dictionary = spec.get("props", {})
			if str(spec.get("script", "")) != Level.CHEST or props.get("depot", false) or props.get("shop", false) or props.has("cache"):
				continue
			chests_seen += 1
			var goods: Array = (props.get("slots", []) as Array).filter(func(id: String) -> bool: return not id.is_empty())
			if not goods.is_empty():
				stocked += 1
			for id: String in goods:
				if id not in hoard or Items.has_tag(id, "armour"):
					strays.append(id)
	# 806 amended (4): the generations' chests are caches (castle_cache, the
	# armoury's armoury); the forge's two, the refuge's hoard, stay stocked.
	_check(Level.template_config("castle_halls").get("loot", {}).get("chest", "") == "dwarven_hoard" and not hoard.is_empty()
		and chests_seen == 6 * 2 and stocked == chests_seen and strays.is_empty(),
		"the forge's hoard chests roll dwarven_hoard every generation, no armour; the rest are caches (%d chests, %d stocked, strays %s)" % [chests_seen, stocked, strays])


## Every way out of the barrow lands at its own door (Jeff, v0.1.194: "when
## exiting the barrows after the quest is complete - the game placed me by
## the foothills zone line in the wilds"): each real link taken by the
## server's own handler (Main._take_link), the arrival read off the player.
## The mound's door to the wilds at the mound, the Ossuary's shortcut and the
## temple's stair by the temple, the niche and the stair between the depths
## at their feet. A private overlay: a depth laid on opening is never written
## to the shared one.
func _test_barrow_exits() -> void:
	print("
== the barrow's ways out: each lands at its own mound, temple or stair foot ==")
	var overlay := Level.overlay_dir
	Level.overlay_dir = preload("res://tests/test_ports.gd").scratch("level_test/barrow_exits/")
	var id: String = _main._peer_ids[Net.local_id]
	_main.mark_player(id, "draugr")  # The shortcut and the temple's stair open to the blessed.
	var wilds := Level.load_level("wilds")
	var temple_stair := Main.building_link_back(wilds, "barrow")
	# [from level, link cell, to level, where it should land, within]. 832
	# switched on: the First Hall's stair up comes out beside the chapel
	# stair, the camp's breach at the mound (its named spawn, not the stair).
	# 896 switched on: the sealed shortcut both ways is gone; the throne is
	# the way home (_test_throne_home).
	var ways: Array = [
		["barrow", Vector2i(40, 1), "wilds", temple_stair, 1],
		["barrow", Vector2i(31, 52), "wilds", wilds["spawn_points"]["from_barrow"], 1],
		["barrow", Vector2i(52, 16), "barrow_deep", Vector2i(49, 2), 1],
		["barrow_deep", Vector2i(49, 1), "barrow", Vector2i(51, 16), 1],
	]
	var landed := {}
	for way: Array in ways:
		_main.load_map("test_room")
		_main.travel(Net.local_id, way[0], "")
		await get_tree().process_frame
		var player := _player()
		var linked := false
		for link: Dictionary in _main.level.get("links", []):
			linked = linked or link["tile"] == way[1] and link["to_map"] == way[2]
		_main._take_link(player, way[1])
		await get_tree().process_frame
		await get_tree().process_frame
		player = _player()
		var at: Vector2i = player.tile if player != null else World.NO_CELL
		_check(linked and _main.map_name == way[2] and player != null and World.distance(at, way[3]) <= way[4],
			"%s's way out at %s lands in %s within %d of %s (%s, at %s)" % [way[0], way[1], way[2], way[4], way[3], _main.map_name, at])
		landed[way[1]] = at
	# 832 switched on (Main.travel): two ways out of the barrow into the wilds;
	# the breach's named spawn stands at the mound's door, another way back
	# down, so it holds, where the First Hall's stair follows the temple's.
	var by_breach: Vector2i = landed.get(Vector2i(31, 52), World.NO_CELL)
	var by_stair: Vector2i = landed.get(Vector2i(40, 1), World.NO_CELL)
	_check(World.distance(by_breach, Vector2i(160, 159)) <= 1 and World.distance(by_stair, temple_stair) <= 1 and World.distance(by_breach, by_stair) > 20,
		"from the barrow by the breach one comes out at the mound (%s), by the First Hall's stair beside the temple's stair (%s): a named spawn beside another way back down holds" % [by_breach, by_stair])
	# 749 amended: spawn safety counts only monsters that are not peaceable:
	# the cell behind the throne (the shortcut's end till 896 switched on),
	# his draugr peaceable beside it, is safe; provoked, it is not.
	_main.load_map("test_room")
	_main.travel(Net.local_id, "barrow_deep", "")
	var by_throne := Vector2i(49, 76)
	var seated: Array = World.get_entities().filter(func(e: GridEntity) -> bool: return e is Draugr and e.spawned)
	_check(seated.size() == 1 and (seated[0] as Draugr).peaceable and World.distance(seated[0].tile, by_throne) <= 1
		and _main._safe_tile_near(by_throne) == by_throne,
		"behind the throne, the draugr peaceable beside it: a safe cell (%s)" % [_main._safe_tile_near(by_throne)])
	if seated.size() == 1:
		(seated[0] as Draugr).peaceable = false  # As provoked, the same tick (Draugr._sim_tick).
		var moved: Vector2i = _main._safe_tile_near(by_throne)
		_check(moved != by_throne and (moved == World.NO_CELL or World.distance(moved, seated[0].tile) > Main.SPAWN_SAFE_DISTANCE),
			"the draugr provoked, spawn safety moves an arrival there off (to %s)" % [moved])
	_main.mark_player(id, "draugr", false)
	_main.load_map("test_room")
	Level.overlay_dir = overlay


func _test_castle() -> void:
	print("\n== the castle, and the way there from the test room ==")
	var castle := Level.load_level("castle")
	_check(not castle.is_empty() and castle["display_name"] == "The Castle" and castle["warnings"].is_empty(),
			"levels/castle is \"The Castle\" and loads cleanly (%s)" % [castle.get("warnings", "missing")])
	_check(load("res://levels/castle/layout.png") is Image, "its layout.png is imported as an Image")
	_check(castle["links"].size() == 3 and str(castle["links"].slice(0, 2)) == str([{"tile": Vector2i(27, 12), "to_map": "test_room", "to_spawn": "from_castle", "one_way": false, "closed": false, "sealed": "", "hidden": false, "cue": "none"},
			{"tile": Vector2i(16, 23), "to_map": "foothills", "to_spawn": "from_castle", "one_way": false, "closed": false, "sealed": "", "hidden": false, "cue": "waystones"}])
			and castle["links"][2]["tile"] == Vector2i(11, 18) and castle["links"][2]["to_map"] == "castle_halls" and castle["links"][2]["to_spawn"] == "from_castle",
			"its link at (27, 12) goes to the test room, at the foot of its road to the foothills (the wilds till 745), and from the guardroom down to the Dwarven Halls (613) (%s)" % [castle["links"]])
	var room := Level.load_level("test_room")
	var back: Array = (room["links"] as Array).filter(func(link: Dictionary) -> bool: return link["to_map"] == "castle")
	_check(back.size() == 1 and back[0]["tile"] == Vector2i(30, 34) and back[0]["to_spawn"] == "from_test_room",
			"the test room's link at (30, 34) goes to the castle")
	_main.load_map("test_room")
	var player := _player()
	var start := player.tile
	var path: Array = World.find_path(start, Vector2i(30, 34))
	_check(not path.is_empty(), "a path from the start, %s, to that link (%d steps)" % [start, path.size()])
	var turns: Array[Vector2i] = []
	for i in path.size():
		var here: Vector2i = path[i]
		var before: Vector2i = start if i == 0 else path[i - 1]
		var after: Vector2i = path[i + 1] if i + 1 < path.size() else here
		if i + 1 == path.size() or after - here != here - before:
			turns.append(here)
	print("    the way: %s -> %s" % [start, " -> ".join(turns.map(func(t: Vector2i) -> String: return str(t)))])
	_put(player, Vector2i(30, 33))
	_hold_free(player, Vector2(0, 1), 6)
	await get_tree().process_frame
	await get_tree().process_frame
	var there := _player()
	_check(World.outdoor and castle["terrain"]["outdoor"] and not room["terrain"]["outdoor"],
			"the castle is outdoors (level.json \"outdoor\"), the test room is not")
	_check(_main.map_name == "castle" and there != null and there.tile == Vector2i(26, 13),
			"Player walks onto it and arrives in the castle beside its link, at (26, 13) (%s %s)" % [_main.map_name, there.tile if there else "none"])
	_hold_free(there, Vector2(1, -1).normalized(), 8)
	await get_tree().process_frame
	await get_tree().process_frame
	var home := _player()
	_check(not World.outdoor, "walking onto the castle's link, World is indoors again in the test room")
	_check(_main.map_name == "test_room" and home != null and home.tile == Vector2i(30, 33),
			"and is back in the test room beside its link, at (30, 33) (%s %s)" % [_main.map_name, home.tile if home else "none"])


## 832 (the crypt's ways in): the barrow's arrivals, from_chapel and
## from_deep in the First Hall and from_breach in the Robbers' Camp, inside
## an anchor and on floor in the template and every generation, so the
## switch-on's links (maps') land on ground.
func _test_crypt_ways() -> void:
	print("
== the crypt's ways in (832): the barrow's arrivals ==")
	var template := Level.load_level("barrow")
	var arrivals := {"from_chapel": "entrance", "from_deep": "entrance", "from_breach": "breach"}  # 832: the breach a dig off the camp, out of its sight
	var wrong: Array[String] = []
	var anchors: Dictionary = {}
	for anchor: Dictionary in Regen.config_of("barrow")["anchors"]:
		var rect: Variant = anchor["rect"]
		anchors[str(anchor["name"])] = rect if rect is Rect2i else Rect2i(rect[0], rect[1], rect[2], rect[3])
	for spawn: String in arrivals:
		var at: Variant = template["spawn_points"].get(spawn)
		if not at is Vector2i or not (anchors[arrivals[spawn]] as Rect2i).has_point(at):
			wrong.append("template: %s at %s, not in %s" % [spawn, at, arrivals[spawn]])
	for generation in range(1, 4):
		var made := Regen.generate("barrow", generation)
		var level := Level.parse(made["layout"], made["height"], made["config"])
		var map := LevelMap.from_image(made["layout"], made["config"])
		for spawn: String in arrivals:
			var at: Variant = level["spawn_points"].get(spawn)
			if not at is Vector2i or not map.walkable(at):
				wrong.append("g%d: %s at %s" % [generation, spawn, at])
		# 832 (the coordinator: no arrival puts a player inside a fight); 747
		# amended (8): the knight reached from each but the robbers' own door.
		for fault: Dictionary in LAYOUT_SENSE.arrival_faults(level, str(Regen.config_of("barrow").get("foes_door", ""))):
			wrong.append("g%d: %s" % [generation, fault["what"]])
	_check(wrong.is_empty() and template["warnings"].is_empty(), "the barrow's three arrivals in their anchors and on floor in the template and generations 1-3, each beyond every foe's reach (%s %s)" % [wrong, template["warnings"]])
	# The breach a dig off the camp's south side, its way out and arrival at
	# its far end, round its bend from the camp: the camp's every cell beyond
	# a wandering robber's reach of it (ARRIVAL_CLEAR and WANDER_RADIUS).
	var breach: Vector2i = template["spawn_points"]["from_breach"]
	var nearest := 1 << 30
	for cell in Level.rect_cells(anchors["camp"]):
		nearest = mini(nearest, maxi(absi(cell.x - breach.x), absi(cell.y - breach.y)))
	var way_out: Array = template["links"].filter(func(l: Dictionary) -> bool: return l["tile"] == Vector2i(31, 52))
	_check(nearest >= LAYOUT_SENSE.ARRIVAL_CLEAR + Monster.WANDER_RADIUS and (anchors["breach"] as Rect2i).has_point(Vector2i(31, 52)) and way_out.size() == 1,
		"the breach comes in at the dig's far end, %d cells from the nearest of the camp (%d wanted), its way out beside it (%s)" % [nearest, LAYOUT_SENSE.ARRIVAL_CLEAR + Monster.WANDER_RADIUS, way_out])


## 747 amended (8) (Jeff: "it makes more sense if the knight is at the
## beginning by the actual altar"; the coordinator's ruling): the quest
## giver is reached from every arrival without passing the band, GIVER_CLEAR
## beyond a hostile's reach; the one arrival not asked, the barrow's
## breach, the robbers' own door, named in its block alone.
func _test_giver_rule() -> void:
	print("
== layout sense: the quest giver reached clear of the band from every arrival (747 amended (8)) ==")
	var floor: Array[Vector2i] = []
	for y in 3:
		for x in 31:
			floor.append(Vector2i(x, y))
	var knight := {"tile": Vector2i(30, 1), "home": Vector2i(30, 1), "kind": "astral_knight"}
	var guard := {"tile": Vector2i(15, 1), "home": Vector2i(15, 1), "kind": "brute", "idle": {"mode": "guard"}}
	var hall := func(entities: Array, door := "") -> Array:
		return LAYOUT_SENSE.arrival_faults({"spawn_points": {"from_test": Vector2i(0, 1)}, "entities": entities, "terrain": {"floor": floor}}, door)
	_check(hall.call([knight]).is_empty(), "the giver down an empty hall: reached")
	var barred: Array = hall.call([knight, guard])
	_check(barred.size() == 1 and str(barred[0]["what"]).contains("from_test") and str(barred[0]["what"]).contains("brute"),
		"a foe standing on the way between: a fault naming the arrival and the nearest foe (%s)" % [barred])
	_check(hall.call([knight, guard], "from_test").is_empty(), "the foes' own door is not asked the walk")
	_check(hall.call([guard]).is_empty(), "no giver, no walk asked")
	var doors := {}
	for level_name: String in DirAccess.get_directories_at(Level.DIR):
		var block: Variant = Level.template_config(level_name).get("regenerate", {})
		if block is Dictionary and (block as Dictionary).has("foes_door"):
			doors[level_name] = block["foes_door"]
	_check(doors == {"barrow": "from_breach"}, "the one arrival exempt anywhere: the barrow's breach, the robbers' own door (%s)" % [doors])
	var tries: Array[int] = []
	var faults := {}
	var unbundled := {}
	var hidden_at := {}
	var untold := {}
	var at := Vector2i(-1, -1)
	var facing := Vector2i.ZERO
	for generation in range(1, 9):
		var made := Regen.generate("barrow", generation)
		if made.is_empty():
			faults[generation] = "not laid"
			continue
		tries.append(int(made["tries"]))
		hidden_at[generation] = _hidden_niche_of(made["config"])
		var level := Level.parse(made["layout"], made["height"], made["config"])
		var tells: Array = (level["terrain"].get("decor", []) as Array).filter(func(piece: Dictionary) -> bool: return piece["kind"] == "candle_draft")
		if tells.size() != 1 or tells[0]["cell"] != hidden_at[generation]:
			untold[generation] = tells.map(func(piece: Dictionary) -> Vector2i: return piece["cell"])
		var found := LAYOUT_SENSE.arrival_faults(level, "from_breach")
		if not found.is_empty():
			faults[generation] = found.map(func(fault: Dictionary) -> String: return str(fault["what"]))
		# The two kits by the band's bedding (870, combat's ask), kept by every generation.
		var bundles: Array = level.get("entities", []).filter(func(spec: Dictionary) -> bool: return str(spec.get("name", "")) == "Robbers' bundle")
		var beds: Array = (level["terrain"].get("decor", []) as Array).filter(func(piece: Dictionary) -> bool: return piece["kind"] == "bedroll")
		if bundles.size() != 1 or bundles[0]["tile"] != Vector2i(6, 48) or Array(bundles[0]["props"].get("slots", [])).count("bandaging_kit") != 2 or beds.size() != 2:
			unbundled[generation] = [bundles.map(func(spec: Dictionary) -> String: return "%s %s" % [spec["tile"], spec["props"].get("slots")]), beds.size()]
		for spec: Dictionary in level.get("entities", []):
			if str(spec.get("kind", "")) == "astral_knight":
				at = spec["tile"]
				facing = spec.get("facing", Vector2i.ZERO)
	_check(unbundled.is_empty(), "the barrow's generations 1-8: the Robbers' bundle at (6, 48) holding two bandaging kits, by the band's two bedrolls (%s)" % [unbundled])
	_check(faults.is_empty(), "the barrow's generations 1-8: from the temple stair, the start, from_deep and from_below the knight is reached clear, and every arrival clear (tries %s; %s)" % [tries, faults])
	_check(at == Vector2i(39, 10) and facing == Vector2i(0, -1), "the knight behind the First Hall's bier, facing the stair (%s, %s)" % [at, facing])
	# 608 amended (3) (the coordinator: "a secret off the main way, never a
	# far corner"): the hidden niche only on the First Hall's west wall,
	# within 4 cells of its way out (27, 9)-(27, 10), on these generations and
	# later ones; still moving between them.
	for generation: int in [118, 119, 120, 121]:
		var made := Regen.generate("barrow", generation)
		hidden_at[generation] = _hidden_niche_of(made.get("config", {}))
	var astray := hidden_at.keys().filter(func(generation: int) -> bool:
		var cell: Vector2i = hidden_at[generation]
		return cell.x != 28 or mini(absi(cell.y - 9), absi(cell.y - 10)) > 4)
	var places := {}
	for generation: int in hidden_at:
		places[hidden_at[generation]] = true
	_check(astray.is_empty() and places.size() >= 2,
		"the hidden niche on the west wall within 4 of the hall's way out, on generations 1-8 and 118-121, moving among them (%s)" % [hidden_at])
	_check(untold.is_empty(), "its tell (the block's hidden_tell, art-kit's candles bent by the draught) laid at the hidden niche and nowhere else, each of generations 1-8, kept by the parse (608 amended (3)) (%s)" % [untold])


## The hall cell before the hidden niche in a generated config's "niches"
## (608), or (-1, -1).
func _hidden_niche_of(config: Dictionary) -> Vector2i:
	for niche: Variant in config.get("niches", []):
		if niche is Array and str(niche[4]) == "hidden":
			return Vector2i(int(niche[0]), int(niche[1]))
	return Vector2i(-1, -1)


func _test_arrival_rule() -> void:
	print("
== layout sense: no arrival inside a fight (832) ==")
	var spawn := Vector2i(20, 20)
	var at := func(entities: Array) -> Array:
		return LAYOUT_SENSE.arrival_faults({"spawn_points": {"from_test": spawn}, "entities": entities})
	var guard := {"tile": Vector2i(29, 20), "home": Vector2i(29, 20), "kind": "brute", "idle": {"mode": "guard"}}
	var guard_far := {"tile": Vector2i(30, 20), "home": Vector2i(30, 20), "kind": "brute", "idle": {"mode": "guard"}}
	var wanderer := {"tile": Vector2i(32, 24), "home": Vector2i(32, 24), "kind": "robber"}
	var wanderer_far := {"tile": Vector2i(33, 20), "home": Vector2i(33, 20), "kind": "robber"}
	var draugr := {"tile": Vector2i(21, 20), "home": Vector2i(21, 20), "kind": "draugr"}
	var patrol := {"tile": Vector2i(40, 20), "home": Vector2i(40, 20), "kind": "sneak", "idle": {"mode": "patrol", "route": [Vector2i(40, 20), Vector2i(25, 20)]}}
	_check(at.call([guard]).size() == 1 and at.call([guard_far]).is_empty(), "a standing foe 9 cells off is a fault, 10 off is not (%s)" % [at.call([guard])])
	_check(at.call([wanderer]).size() == 1 and at.call([wanderer_far]).is_empty(), "a wanderer 12 off is a fault (its reach 3 more), 13 off is not")
	_check(at.call([draugr]).is_empty(), "the seated draugr beside an arrival is no fight")
	_check(at.call([patrol]).size() == 1, "a patrol's waypoint 5 off is a fault though its post is 20 off")
	_check(LAYOUT_SENSE.RULES.has("arrival"), "arrival is one of layout sense's rules")
	var holding: Array[String] = []
	var as_held: bool = Regen.layout_options({"held": ["door", "arrival"]}).get("arrival") == true and Regen.layout_options({"held": ["door"]}).get("arrival") == false
	for level_name: String in Regen.marked_levels():
		var block := Regen.config_of(level_name)
		as_held = as_held and Regen.layout_options(block).get("arrival") == ("arrival" in (block.get("held", []) as Array))
		if "arrival" in (block.get("held", []) as Array):
			holding.append(level_name)
	_check(as_held, "checked in generation only where a block holds it (806 amended (11): off till 832's switch-on holds it in both barrow depths; held now: %s)" % [holding])
	# A block holding it: the crypt lays its monsters clear of the arrivals
	# (the barrow, from_breach left out: main's unused one sits in the camp
	# till 832 moves it), and a try with an arrival fault is never laid (an
	# arrival put in the camp, by its robbers).
	var prepared := Regen.prepare("barrow")
	if not "arrival" in (prepared["config"]["held"] as Array):
		(prepared["config"]["held"] as Array).append("arrival")
	var kept: Dictionary = prepared["made"]["config"]["spawn_points"].duplicate()
	kept["in_camp"] = [10, 45]
	prepared["made"]["config"]["spawn_points"].erase("from_breach")
	prepared["config"]["arrivals"].erase("from_breach")
	var clear := true
	for generation in [1, 2, 3]:
		var made := Regen.generate_prepared(prepared, generation)
		clear = clear and not made.is_empty() and Regen.layout_faults(made, prepared["config"]).all(func(f: Dictionary) -> bool: return f["rule"] != "arrival")
	_check(clear, "a barrow held to it: generations 1-3 laid with every arrival clear, the crypt laying its robbers clear")
	prepared["made"]["config"]["spawn_points"] = kept
	_check(Regen.generate_prepared(prepared, 1).is_empty(), "and with an arrival no try can clear (one in the robbers' camp), none is laid: the last laid copy stands")
	# The rule's scope (the coordinator): every level a player can reach, laid
	# by hand or a template, its arrivals clear: each start, and each spawn
	# point some link names (main's barrow from_breach, named by none till
	# 832, is not one); the test levels exempt, castle maps' to mend.
	var named := {}
	var folders := DirAccess.get_directories_at(Level.DIR)
	for folder: String in folders:
		var config := Level.template_config(folder)
		for link: Variant in config.get("links", []):
			if link is Dictionary:
				named["%s/%s" % [link.get("to_map", ""), link.get("to_spawn", "")]] = true
	var faulted: Array = []
	var read := 0
	for folder: String in folders:
		if folder in LAYOUT_SENSE.ARRIVAL_EXEMPT or LAYOUT_SENSE.ARRIVAL_NOT_YET.has(folder) or not FileAccess.file_exists(Level.DIR + folder + "/layout.png") or not FileAccess.file_exists(Level.DIR + folder + "/level.json"):
			continue
		read += 1
		var made := Level.template(folder)
		var laid := Level.parse(made["layout"], made.get("height"), made["config"], made.get("relief"))
		var reached := {}
		for spawn_name: Variant in laid.get("spawn_points", {}):
			if named.has("%s/%s" % [folder, spawn_name]):
				reached[spawn_name] = laid["spawn_points"][spawn_name]
		laid["spawn_points"] = reached
		for fault: Dictionary in LAYOUT_SENSE.arrival_faults(laid, str(Regen.config_of(folder).get("foes_door", ""))):
			faulted.append("%s: %s" % [folder, fault["what"]])
	_check(read >= 15 and faulted.is_empty(), "every level a player reaches (%d read; sample and test_room exempt, castle maps' to mend) has its arrivals clear (%s)" % [read, faulted])
	var castle := Level.template("castle")
	_check(not LAYOUT_SENSE.arrival_faults(Level.parse(castle["layout"], castle.get("height"), castle["config"], castle.get("relief"))).is_empty(),
		"castle's arrivals still want mending (drop it from ARRIVAL_NOT_YET once maps has)")


func _test_hall_shortcut() -> void:
	print("
== the First Hall's sealed way down (832) ==")
	var level_name := "barrow"
	var template := Level.template("barrow")
	var config: Dictionary = (template["config"] as Dictionary).duplicate(true)
	if not (config["links"] as Array).any(func(l: Dictionary) -> bool: return l["at"] == HALL_SHORTCUT["at"]):
		var layout: Image = (template["layout"] as Image).duplicate()
		layout.set_pixel(HALL_SHORTCUT["at"][0] * 2, HALL_SHORTCUT["at"][1] * 2, Color("#ff00ff"))
		config["links"].append(HALL_SHORTCUT.duplicate(true))
		level_name = "hall_shortcut_test"
		Level.register(level_name, layout, template.get("height"), config)
	var level := Level.parse(Level.template(level_name)["layout"], Level.template(level_name).get("height"), config)
	var link: Dictionary = {}
	for each: Dictionary in level["links"]:
		if each["tile"] == Vector2i(30, 8):
			link = each
	var cue: Dictionary = {}
	for each: Dictionary in level["terrain"]["link_cues"]:
		if each["tile"] == Vector2i(30, 8):
			cue = each
	_check(link.get("to_map") == "barrow_deep" and link.get("to_spawn") == "from_temple" and link.get("sealed") == "draugr"
			and level_name == "hall_shortcut_test" and level["warnings"].is_empty(),
		"the First Hall's way down at (30,8): to the Ossuary's from_temple, sealed by the draugr (%s, %s)" % [link, level["warnings"]])
	_check(cue.get("cue") == "sealed" and not cue.has("words") and not cue.has("text"),
		"it reads as a shut way: the sealed slab, no words (%s)" % [cue])
	var id: String = _main._peer_ids.get(Net.local_id, "")
	var record: PlayerRecord = _main._records.get(id)
	if record == null:
		_check(false, "a player record to try the way with")
		return
	var kept_marks := record.marks.duplicate()
	var kept_hers: Variant = record.companion.get("marks", []).duplicate()
	record.companion["marks"] = []
	record.marks.assign([])
	_check(not _main.sealed_open(link, Net.local_id), "unmarked, the way stays shut")
	record.marks.assign(["draugr"])
	var saved := PlayerRecord.from_dict(record.to_dict().merged({"player_id": record.player_id}))
	_main._records[id] = saved
	_check("draugr" in saved.marks and _main.sealed_open(link, Net.local_id),
		"a player who beat him before the build (the mark in their saved record) finds it open")
	_main._records[id] = record
	record.marks.assign(kept_marks)
	record.companion["marks"] = kept_hers


## The crypt bar (crypt_bar.md section 5; the coordinator's picks P1 and O1):
## the band's posts kept out of each other's join reach (barrow "apart"
## robber [10, 7], Labyrinth.in_sight; main's 4 had 10-19 pairs inside the
## reach on generations 1-8, up to 6 at one post), and the Ossuary's packs
## kept 11 apart wall or no wall, so no two of its rooms wake together (on
## main, two packs within 10 on g1-5, 7 and 118). The first robber a player
## meets from the chapel stair stands alone (the held "first" rule; playtest's
## walk on v0.1.211: four came within 6 s of the first).
func _test_crypt_spacing() -> void:
	print("
== the crypt bar: band posts out of join reach, the Ossuary's packs apart ==")
	var pairs := {}
	var most := 0
	var unalone := {}
	var known := {}
	var was := str(World.zone.name)
	for generation in range(1, 9):
		var made := Regen.generate("barrow", generation)
		var map := LevelMap.from_image(made["layout"], made["config"])
		var posts: Array[Vector2i] = []
		for cell: Vector2i in map.cells:
			if map.cells[cell] in ["monster_robber", "monster_robber_brute"]:
				posts.append(cell)
		var count := 0
		for a in posts:
			var near := 0
			for b in posts:
				if a != b and LABYRINTH._too_near(map, a, b, 10, 7):
					near += 1
					count += 1
			most = maxi(most, near)
		pairs[generation] = count / 2
		var level := Level.parse(made["layout"], made["height"], made["config"])
		var walks := LAYOUT_SENSE.band_walks(level, ["robber", "robber_brute"], Regen.first_alone(made["config"].get("regenerate", {})), "from_breach")
		var met: Array = walks.get("from_chapel", [])
		if met.is_empty() or not (met[0]["callers"] as Array).is_empty():
			unalone[generation] = met[0] if not met.is_empty() else "no post met"
		# 870 with 806 amended (17): the band's own measure on the laid level
		# (Monster.knows_of_fight: heard within RALLY_HEAR, seen within
		# RALLY_SEE in World's line of sight). No mate knows of the first
		# post's fight, so the rally never answers it; if the grid's in_sight
		# and World's sight ever part, this says so.
		World.load_terrain(level["terrain"])
		var mates := {}
		for arrival: String in walks:
			for post: Dictionary in walks[arrival]:
				mates[post["at"]] = true
		if not met.is_empty():
			var first: Vector2i = met[0]["at"]
			var knowing: Array = mates.keys().filter(func(cell: Vector2i) -> bool: return cell != first and Monster.knows_of_fight(cell, first))
			if not knowing.is_empty():
				known[generation] = [first, knowing]
	_check(pairs.values().all(func(n: int) -> bool: return n <= 8) and most <= 4,
		"the barrow's generations 1-8: at most 8 band pairs inside the join reach and 4 at one post (pairs %s, most %d; main's 4 apart had 10-19 and 6)" % [pairs, most])
	_main.load_map(was)
	_check(Regen.first_alone({"held": ["first"]}) == [Monster.RALLY_SEE, Monster.RALLY_HEAR] and Regen.first_alone({}).is_empty(),
		"the first-alone rule reads the band's rally, seen and heard, from the AI's own constants (806 amended (17)): %s" % [Regen.first_alone({"held": ["first"]})])
	_check(unalone.is_empty(), "the barrow's generations 1-8: the first robber met from the chapel stair has no other post within the rally's reach, %d in sight, %d through a wall (870, first-alone; %s)" % [Monster.RALLY_SEE, Monster.RALLY_HEAR, unalone])
	_check(known.is_empty(), "the barrow's generations 1-8, laid: no mate of the band knows of the first post's fight by the rally's own measure (Monster.knows_of_fight), so none answers it (%s)" % [known])
	var near_packs := {}
	for generation: int in [1, 2, 3, 4, 5, 6, 7, 8, 109, 118]:
		var made := Regen.generate("barrow_deep", generation)
		var packs := {}
		for spec: Dictionary in made["config"].get("entities", []):
			var id := str(spec.get("props", {}).get("pack", ""))
			if not id.is_empty():
				(packs.get_or_add(id, []) as Array).append(Vector2i(spec["at"][0], spec["at"][1]))
		var ids := packs.keys()
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				for a: Vector2i in packs[ids[i]]:
					for b: Vector2i in packs[ids[j]]:
						if maxi(absi(a.x - b.x), absi(a.y - b.y)) <= 10:
							near_packs[generation] = [a, b]
		if ids.size() != 3:
			near_packs[generation] = "%d packs" % ids.size()
	_check(near_packs.is_empty(), "the Ossuary's generations 1-8, 109 and 118: three packs, no two within 10 cells (%s)" % [near_packs])


## 806 amended (15): a chest only where its guard can stand. On main the
## barrow kept an unguarded cache chest on generations 56, 191 and 215 (the
## saturn sweep, 3 of 300), each in a room by from_below inside the arrival
## rule's reach; now no chest goes to such a room and a kept chest fault
## ranks worst, so each lays every chest guarded: three, or fewer where too
## few rooms can hold a guard (191 lays two; the saturn sweep, 6 of 300 short,
## main 2).
func _test_chest_guardable() -> void:
	print("
== a chest only where its guard can stand (806 amended (15)) ==")
	var kept := {}
	var counted := {}
	for generation: int in [56, 191, 215, 1, 2]:
		var made := Regen.generate("barrow", generation)
		var block := Regen.config_of("barrow")
		var chests := (made["config"].get("entities", []) as Array).filter(func(spec: Dictionary) -> bool:
			return str(spec.get("props", {}).get("cache", "")) == str(block.get("cache", "")))
		var faults := Regen.held_faults(made, block, block.get("held", [])).filter(func(fault: Dictionary) -> bool: return fault["rule"] == "chest")
		counted[generation] = chests.size()
		if not faults.is_empty() or chests.is_empty() or chests.size() > int(block.get("chests", 0)):
			kept[generation] = [chests.size(), faults.map(func(fault: Dictionary) -> String: return str(fault["what"]))]
	_check(kept.is_empty(), "the barrow's generations 56, 191, 215 (main's unguarded three), 1 and 2: every cache chest guarded, at most the block's three, fewer where too few rooms can hold a guard (%s; laid %s)" % [kept, counted])


func _test_deep_crypt() -> void:
	print("
== the deep laid as a crypt (832) ==")
	var template := Level.template("barrow_deep")
	var config: Dictionary = (template["config"] as Dictionary).duplicate(true)
	if not config["regenerate"].has("deep"):
		config["regenerate"].merge(DEEP_SWITCH, true)
	Level.register("deep_crypt_test", template["layout"], template.get("height"), config)
	var block: Dictionary = config["regenerate"]
	_check(LAYOUT_SENSE.RULES.all(func(rule: String) -> bool: return rule in block.get("held", [])),
		"the deep holds every layout rule (step 4; %s)" % [block.get("held")])
	for generation in range(1, 7):
		var made := Regen.generate("deep_crypt_test", generation)
		if made.is_empty():
			_check(false, "deep crypt generation %d made" % generation)
			continue
		var laid_config: Dictionary = made["config"]
		var level := Level.parse(made["layout"], made["height"], laid_config)
		var uses := {}
		var wing: Array = []
		for laid: Dictionary in laid_config.get("laid_rooms", []):
			uses[laid["use"]] = int(uses.get(laid["use"], 0)) + 1
			if laid.has("wing"):
				wing.append(laid)
		var packs := {}
		var kinds := {}
		for spec: Dictionary in level["entities"]:
			kinds[str(spec.get("kind", ""))] = int(kinds.get(str(spec.get("kind", "")), 0)) + 1
			var id := str((spec.get("props", {}) as Dictionary).get("pack", ""))
			if not id.is_empty():
				packs[id] = int(packs.get(id, 0)) + 1
		var rooms_ok: bool = int(uses.get("ossuary", 0)) == 1 and int(uses.get("tomb_chamber", 0)) >= 4 			and uses.keys().all(func(use: String) -> bool: return use in ["ossuary", "tomb_chamber", "entrance", "lair"])
		var wing_ok: bool = wing.is_empty() or (wing.size() >= 2 and wing.all(func(laid: Dictionary) -> bool: return laid["wing"] == "old_graves"))
		var packs_ok: bool = packs.size() == 3 and packs.values().all(func(n: int) -> bool: return n == 3)
		var links: Array = level["links"].map(func(link: Dictionary) -> Vector2i: return link["tile"])
		var torches := 0
		var map := LevelMap.from_image(made["layout"], laid_config)
		# The coordinator's condition on lit_way: the spine only; no torch in a
		# room (the Old Graves' among them); _torches lays none off the way.
		var in_rooms := {}
		for laid: Dictionary in laid_config.get("laid_rooms", []):
			for pair: Variant in laid.get("cells", []):
				in_rooms[Vector2i(int(pair[0]), int(pair[1]))] = true
		var stray: Array[Vector2i] = []
		for cell: Vector2i in map.cells:
			if map.cells[cell] == "torch" and not Level.in_anchors(Regen.config_of("deep_crypt_test")["anchors"], cell):
				torches += 1
				if in_rooms.has(cell):
					stray.append(cell)
		# 608 amended (4), (5): the Charnel Vault's pair, the template's, at the ends of its way out
		# (the way open below each, its mouth between and beside them).
		var mouth := range(47, 53).filter(func(x: int) -> bool: return map.walkable(Vector2i(x, 7)))
		_check(VAULT_TORCHES.all(func(cell: Vector2i) -> bool: return map.cells.get(cell) == "torch" and map.walkable(cell + Vector2i(0, 1)))
				and mouth.size() >= 4,
				"deep crypt generation %d: the Charnel Vault's two torches kept, at its way out's ends %s, the way open below each (x %s at y 7)"
				% [generation, VAULT_TORCHES, mouth])
		var faults: Array = LAYOUT_SENSE.check(level, laid_config.get("laid_rooms", []), Regen.layout_options(block))
		_check(rooms_ok and wing_ok and packs_ok and int(kinds.get("draugr", 0)) == 1 and Vector2i(49, 1) in links and not Vector2i(49, 77) in links
				and torches >= 4 and stray.is_empty() and faults.is_empty() and level["warnings"].is_empty(),
				"deep crypt generation %d: uses %s, the wing %d rooms, packs %s, the draugr, the stair up and no way behind the throne (896), %d torches along its way (lit_way, the Umbrage crypt follow-up), none in a room %s, faults %s %s"
				% [generation, uses, wing.size(), packs.values(), torches, stray, LAYOUT_SENSE.counts(faults), level["warnings"]])


## 608 amended (5): every torch in a crypt is a torch a player sees from the
## default view (Client3D's resting camera, yaw 0, south-east of the player
## looking north-west), never a light alone. Client3D draws a post and its
## flame on every torch cell (_add_torch), so what can hide one is a wall on
## its near side: the cell walkable, and its south neighbour open floor with
## no wall or door on the edge between (ui-design's torch5, joined, the
## default camera: the Vault's (46,6) and (53,6), each with the vault's south
## wall on its south edge, drew no post or flame, only their light on the wall
## ends; the Ossuary's spine torches with a wall on the east edge alone,
## (51,11) and (51,18), were read drawn whole). On barrow, barrow_deep
## and hollowfell, generations 1 to 5. And the Vault's pair stands at the
## way out's ends, a walk from the stair's foot through the way out routing
## with both posts counted solid, at least two cells of the mouth clear.
##
## 608 amended (6): "seen" is the default camera's, a line walked from the
## flame toward it (_torch_seen), no longer the south edge alone. ui-design's
## torch7 (barrow generation 1 from (19,7), nearest zoom) drew no post or flame
## at (24,7), its own east wall between; torch6b, read post by post from
## Client3D's projection, drew none at the Vault's (52,6), the corner of the
## wall round (53,7) between; the Ossuary's east spine torches read whole only
## inside the player's see-through band. So the Vault's pair is (49,6) and
## (51,6), even about the mouth's middle, (48,6) and (52,6) left free; and the
## Ossuary's torches are counted beside the barrow's.
func _test_torches_seen() -> void:
	print("\n== 608 amended (5), (6): every crypt torch seen from the default camera, never a light alone ==")
	var template := LevelMap.from_image(Level.template("barrow_deep")["layout"], Level.template("barrow_deep")["config"])
	var corner_only := Vector2i(52, 6)
	_check(not _torch_seen(template, Vector2i(46, 6)) and not _torch_seen(template, Vector2i(53, 6)) and not _torch_seen(template, corner_only),
		"the row's own check: the Vault's old corners (46,6) and (53,6), behind its south wall, and (5)'s (52,6), behind the corner of the wall east of the mouth, read hidden")
	var open_room := LevelMap.new(Vector2i(8, 8))
	for y in 8:
		for x in 8:
			open_room.cells[Vector2i(x, y)] = CRYPT_GEN.FLOOR
	var walled := {}
	for step: Vector2i in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
		var one := _map_copy(open_room)
		one.set_edge(Terrain.edge_key(Vector2i(4, 4), step), "wall")
		walled[step] = _torch_seen(one, Vector2i(4, 4))
	var se_edge := _map_copy(open_room)
	se_edge.set_edge(Terrain.edge_key(Vector2i(5, 4), Vector2i(0, 1)), "wall")
	var far_edge := _map_copy(open_room)
	far_edge.set_edge(Terrain.edge_key(Vector2i(5, 5), Vector2i(0, 1)), "wall")
	_check(_torch_seen(open_room, Vector2i(4, 4)) and not walled[Vector2i(0, 1)] and not walled[Vector2i(1, 0)] and walled[Vector2i(-1, 0)] and walled[Vector2i(0, -1)]
			and not _torch_seen(se_edge, Vector2i(4, 4)) and _torch_seen(far_edge, Vector2i(4, 4)),
		"the walk: open floor seen; a wall on its own south or east edge hides it, on its west or north it does not (%s); one meeting its south-east corner from the east cell hides it; one a cell beyond is under the line" % [walled])
	for level_name: String in ["barrow", "barrow_deep", "hollowfell"]:
		for generation in range(1, 6):
			var made := Regen.generate(level_name, generation)
			if made.is_empty():
				_check(false, "%s generation %d made" % [level_name, generation])
				continue
			var map := LevelMap.from_image(made["layout"], made["config"])
			var torches: Array[Vector2i] = []
			for cell: Vector2i in map.cells:
				if map.cells[cell] == "torch":
					torches.append(cell)
			torches.sort()
			var hidden := torches.filter(func(cell: Vector2i) -> bool: return not _torch_seen(map, cell))
			_check(hidden.is_empty(), "%s generation %d: all %d torches seen from the default camera, hidden: %s" % [level_name, generation, torches.size(), hidden])
			if level_name == "hollowfell":
				continue
			_torches_moved(level_name, map, generation, torches)
			if level_name != "barrow_deep":
				continue
			var mouth := range(47, 53).filter(func(x: int) -> bool: return map.walkable(Vector2i(x, 7)) and not Vector2i(x, 6) in VAULT_TORCHES)
			_check(VAULT_TORCHES.all(func(cell: Vector2i) -> bool: return map.cells.get(cell) == "torch") and mouth.size() >= 2 and _routes_past(map, Vector2i(49, 2), 8, VAULT_TORCHES)
					and VAULT_TORCHES_BEFORE.all(func(cell: Vector2i) -> bool: return map.cells.get(cell) != "torch" and map.walkable(cell)),
				"barrow_deep generation %d: the Vault's torches at %s, even about the mouth's middle, %s free, the way out routing past them from the stair's foot, the mouth's clear cells x %s" % [generation, VAULT_TORCHES, VAULT_TORCHES_BEFORE, mouth])


## A copy of [param map] (cells, edges, size) a row may change.
static func _map_copy(map: LevelMap) -> LevelMap:
	var out := LevelMap.new(map.size)
	out.cells = map.cells.duplicate()
	out.edges = map.edges.duplicate()
	return out


## 608 amended (5), (6), a crypt's own torches: generation [param generation]
## of [param level_name] laid again as before the mends (Crypt.lay_in_view
## false) lays the same rooms and ways (every cell and edge alike, torches
## read as floor); the torches before and after counted, how many moved (a
## cell north, west, north-west or south-west of where they stood) and how many not
## laid, and which way's pairs now stand uneven (one moved off its wall, its
## mate not); every way still routes from the arrival with every post counted
## solid (no cell cut off), and a moved post leaves at least two clear cells
## across the way it moved in.
func _torches_moved(level_name: String, map: LevelMap, generation: int, torches: Array[Vector2i]) -> void:
	CRYPT_GEN.lay_in_view = false
	var made_old := Regen.generate(level_name, generation)
	var old := LevelMap.from_image(made_old["layout"], made_old["config"])
	CRYPT_GEN.lay_in_view = true
	var before: Array[Vector2i] = []
	var differ: Array[Vector2i] = []
	for cell: Vector2i in old.cells:
		if old.cells[cell] == "torch":
			before.append(cell)
	before.sort()
	# The band and the dead are laid on the floor after the torches (Crypt._monsters,
	# a shuffle of the floor cells), so a torch moved can lay a foe elsewhere: counted, not a fault.
	var foes_moved := {}
	for cell: Vector2i in old.cells.keys() + map.cells.keys():
		var a := old.cell(cell)
		var b := map.cell(cell)
		if a == b or a in ["torch", CRYPT_GEN.FLOOR] and b in ["torch", CRYPT_GEN.FLOOR]:
			continue
		if a.begins_with("monster_") and b in ["torch", CRYPT_GEN.FLOOR] or b.begins_with("monster_") and a in ["torch", CRYPT_GEN.FLOOR]:
			foes_moved[cell] = true
		elif not differ.has(cell):
			differ.append(cell)
	var edges_alike := old.edges == map.edges
	var froms := {}
	var stray: Array[Vector2i] = []
	for cell in torches:
		if before.has(cell):
			continue
		var from := Vector2i(-1, -1)
		for back: Vector2i in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, -1)]:
			if before.has(cell + back) and not torches.has(cell + back) and not froms.values().has(cell + back):
				from = cell + back
				break
		if from == Vector2i(-1, -1):
			stray.append(cell)
		else:
			froms[cell] = from
	var gone := before.filter(func(cell: Vector2i) -> bool: return not torches.has(cell) and not froms.values().has(cell))
	# A pair uneven: a moved post's mate, the torch across the way from where it stood, stayed on its wall.
	var uneven: Array = []
	for cell: Vector2i in froms:
		var from: Vector2i = froms[cell]
		var away: Vector2i = Vector2i(signi((from - cell).x), signi((from - cell).y))
		for axis: Vector2i in [Vector2i(away.x, 0), Vector2i(0, away.y)]:
			if axis == Vector2i.ZERO:
				continue
			var at := from - axis
			while old.walkable(at) and old.edge(Terrain.edge_key(at + axis, -axis)) == "clear":
				if before.has(at) and at != from:
					if torches.has(at):
						uneven.append([cell, at])
					break
				at -= axis
	_check(differ.is_empty() and edges_alike and stray.is_empty(),
		"%s generation %d: the same rooms and ways as before the mends (cells differing %s, edges alike %s; foes' cells changed %d); torches %d before, %d after: %d moved %s, %d not laid %s; pairs uneven %d %s"
		% [level_name, generation, differ, edges_alike, foes_moved.size(), before.size(), torches.size(), froms.size(), froms, gone.size(), gone, uneven.size(), uneven])
	var arrival: Vector2i = Regen.keep_cell(level_name) if Regen.keep_cell(level_name) is Vector2i else Vector2i(49, 2)
	var open := _reach(map, arrival, [])
	var solid := _reach(map, arrival, torches)
	var cut := open.keys().filter(func(cell: Vector2i) -> bool: return not torches.has(cell) and not solid.has(cell))
	var narrow := froms.keys().filter(func(cell: Vector2i) -> bool:
		var from: Vector2i = froms[cell]
		for axis: Vector2i in [Vector2i(0, 1) if from.y != cell.y else Vector2i.ZERO, Vector2i(1, 0) if from.x != cell.x else Vector2i.ZERO]:
			if axis == Vector2i.ZERO:
				continue
			var clear := 0
			for way: Vector2i in [axis, -axis]:
				var at: Vector2i = cell
				while map.walkable(at + way) and map.edge(Terrain.edge_key(at, way)) == "clear":
					at += way
					clear += 0 if torches.has(at) else 1
			if clear < 2:
				return true
		return false)
	_check(cut.is_empty() and narrow.is_empty(),
		"%s generation %d: every way routes from the arrival %s with all %d posts solid (cut off %s); every moved post leaves two clear cells across (narrower %s)" % [level_name, generation, arrival, torches.size(), cut, narrow])


## The cells of [param map] a walk from [param from] reaches, stepping on
## walkable cells, never [param solid] ones, no wall edge crossed (a door
## is a way).
static func _reach(map: LevelMap, from: Vector2i, solid: Array[Vector2i]) -> Dictionary:
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var at: Vector2i = queue.pop_front()
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := at + step
			if seen.has(next) or not map.walkable(next) or next in solid or map.edge(Terrain.edge_key(at, step)) == "wall":
				continue
			seen[next] = true
			queue.append(next)
	return seen


## Whether a torch on [param cell] of [param map] is seen from the default
## camera (608 amended (6), the coordinator's "one check that walks the
## default view's line from the torch's flame toward the camera"): from the
## flame, VIEW_FLAME over the cell's middle, and from either side of the post
## (VIEW_POST_HALF across the view), a line walked toward the camera on the
## +x +z diagonal, rising at VIEW_PITCH, until it is over the walls; seen when
## no line passes through a drawn wall (an edge with a wall or door on it, or
## floor on one side only), VIEW_WALL tall and 2 VIEW_WALL_HALF thick, its
## ends' posts as thick. Cells are 1 m, centred on their coordinates. The walk
## knows nothing of which edges the generator reads (Crypt.hidden_from_view),
## so it checks that rule as well as the torches.
static func _torch_seen(map: LevelMap, cell: Vector2i) -> bool:
	if not map.walkable(cell):
		return false
	var rise := tan(deg_to_rad(VIEW_PITCH)) * sqrt(2.0)  # Height gained per metre along x (and z).
	var reach := (VIEW_WALL - VIEW_FLAME) / rise
	for side: float in [-VIEW_POST_HALF, 0.0, VIEW_POST_HALF]:
		var start := Vector2(cell) + Vector2(1.0, -1.0) * side / sqrt(2.0)
		var t := 0.0
		while t <= reach:
			if _in_drawn_wall(map, start + Vector2(t, t)):
				return false
			t += 0.02
	return true


## Whether the point [param at] (x, z in cells) is inside a wall Client3D draws
## on one of the edges round it (608 amended (6)'s walk).
static func _in_drawn_wall(map: LevelMap, at: Vector2) -> bool:
	var near := Vector2i(roundi(at.x), roundi(at.y))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := near + Vector2i(dx, dy)
			for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var other := c + step
				var drawn := map.walkable(c) != map.walkable(other) or map.walkable(c) and map.edge(Terrain.edge_key(c, step)) != "clear"
				if not drawn:
					continue
				var middle := Vector2(c) + Vector2(step) * 0.5
				var half := Vector2(VIEW_WALL_HALF, 0.5 + VIEW_WALL_HALF) if step.x == 1 else Vector2(0.5 + VIEW_WALL_HALF, VIEW_WALL_HALF)
				if absf(at.x - middle.x) <= half.x and absf(at.y - middle.y) <= half.y:
					return true
	return false


## Whether a walk on [param map] from [param from] reaches row [param row]
## with [param solid] cells counted as blocked: steps on walkable cells, no
## wall edge crossed, a door a way (608 amended (5)).
static func _routes_past(map: LevelMap, from: Vector2i, row: int, solid: Array[Vector2i]) -> bool:
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var at: Vector2i = queue.pop_front()
		if at.y >= row:
			return true
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := at + step
			if seen.has(next) or not map.walkable(next) or next in solid or map.edge(Terrain.edge_key(at, step)) == "wall":
				continue
			seen[next] = true
			queue.append(next)
	return false


## 714, dungeon's side (4): the barrow's robbers are enemy-ai's named band
## (716): each generation lays Brand the Ox (robber_brute) and the eight,
## each spawn named (Regen.band_of, Level.parse's "named").
func _test_band() -> void:
	print("
== the barrow's named band (714 (4)) ==")
	var want := ["brand", "crake", "fenn", "mott", "nabb", "rook", "sedge", "tull", "wicket"]
	var wrong: Array[String] = []
	# 747 amended (13): five generations and the box's two of 11-14 (136, 137).
	for generation: int in [1, 2, 3, 4, 5, 136, 137]:
		var made := Regen.generate("barrow", generation)
		if made.is_empty():
			wrong.append("g%d: not made" % generation)
			continue
		var level := Level.parse(made["layout"], made["height"], made["config"])
		var named := {}
		for spec: Dictionary in level["entities"]:
			if spec.has("named"):
				named[str(spec["named"])] = str(spec.get("kind", ""))
		var ids: Array = named.keys()
		ids.sort()
		if ids != want or named.get("brand") != "robber_brute" or named.values().count("robber") != 8:
			wrong.append("g%d: %s" % [generation, named])
		var knights := (level["entities"] as Array).filter(func(spec: Dictionary) -> bool: return spec.get("kind") == "astral_knight")
		if knights.size() != 1 or knights[0]["tile"] != KNIGHT_AT:
			wrong.append("g%d: fallen knights at %s" % [generation, knights.map(func(spec: Dictionary) -> Variant: return spec["tile"])])  # One, by the bier (747 amended (8)).
		# The Low Hall gone (747 amended (13), Jeff 11-14): no altar anchor, no room
		# of that name, none of its guards; the stone in the First Hall; the hidden
		# way down inside the First Hall (the knight's reveal); Pip's niche joined.
		var stones := (level["entities"] as Array).filter(func(spec: Dictionary) -> bool: return str(spec["name"]).begins_with("Offering stone"))
		var down := (level["links"] as Array).filter(func(link: Dictionary) -> bool: return link["to_map"] == "barrow_deep")
		var anchors: Array = made["anchors"]
		var anchor_names := anchors.map(func(anchor: Dictionary) -> String: return str(anchor["name"]))
		var rooms: Dictionary = made["config"].get("rooms", {})
		if "altar" in anchor_names or rooms.has("altar") or (level["entities"] as Array).any(func(spec: Dictionary) -> bool: return spec.get("kind") == "skeleton_guard"):
			wrong.append("g%d: the Low Hall still laid (%s, %s)" % [generation, anchor_names, rooms.keys()])
		if stones.size() != 1 or stones[0]["tile"] != OFFERING_AT:
			wrong.append("g%d: offering stones at %s" % [generation, stones.map(func(spec: Dictionary) -> Variant: return spec["tile"])])
		if down.size() != 1 or not FIRST_HALL.has_point(down[0]["tile"]):
			wrong.append("g%d: the way down at %s, not in the First Hall %s" % [generation, down.map(func(link: Dictionary) -> Variant: return link["tile"]), FIRST_HALL])
		var laid_map := LevelMap.from_image(made["layout"], made["config"])
		if not "niche" in anchor_names or not Regen.connected(laid_map, anchors):
			wrong.append("g%d: Pip's niche not joined (%s)" % [generation, anchor_names])
		var in_hall := Level.rect_cells(LOW_HALL).filter(func(cell: Vector2i) -> bool: return laid_map.walkable(cell))
		if not in_hall.is_empty():
			wrong.append("g%d: floor where the Low Hall stood %s" % [generation, in_hall.slice(0, 4)])
		if (level["warnings"] as Array).any(func(w: String) -> bool: return "names an entity" in w):
			wrong.append("g%d warned: %s" % [generation, level["warnings"]])
	_check(wrong.is_empty(), "five generations and the box's 136 and 137: the nine named, Brand the brute and eight robbers, each a spawn; one fallen knight, at %s by the bier; the Low Hall gone, its place rock, its guards with it, the Offering stone at %s in the First Hall, the hidden way down inside the First Hall %s, Pip's niche joined (%s)" % [KNIGHT_AT, OFFERING_AT, FIRST_HALL, wrong])


## 742, amended (Jeff: "the chest only opens with a key from the boss and
## only hold gold once per player"): the barrow's camp holds the robbers'
## chest; it opens only with Brand's key (given to his slayer, used up),
## puts economy's camp gold into the purse once per player for good, then
## is empty.
func _test_camp_chest() -> void:
	print("
== the robbers' camp chest (742 amended): Brand's key, once per player ==")
	var camp: Dictionary = _main._camp_rules()
	var barrow := Level.load_level("barrow")
	var placed := (barrow.get("entities", []) as Array).filter(func(spec: Dictionary) -> bool:
		return spec.get("tile") == Vector2i(14, 43) and spec.get("props", {}).get("cache") == "robbers_camp")
	_check(int(camp.get("gold", 0)) == 25 and camp.get("lock") == "robbers_camp" and camp.get("cache") == "robbers_camp" and placed.size() == 1
		and Items.opens_of(Main.CAMP_KEY) == "robbers_camp"
		and not (barrow.get("warnings", []) as Array).any(func(w: String) -> bool: return "robbers_camp" in w),
		"economy's camp rule (25 gold, Brand's key's lock), the key opens it, and the chest in the barrow's camp (%s)" % [camp])
	var player := _player()
	if player == null:
		_check(false, "a player to search with")
		return
	var beside := Vector2i(-1, -1)
	for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if World.is_free(player.tile + step):
			beside = player.tile + step
			break
	if beside == Vector2i(-1, -1):
		print("  (no free cell beside the player: skipped)")
		return
	var chest := _main._spawn({"script": Level.CHEST, "shape": "cube", "name": "CampChestTest", "tile": beside,
		"props": {"cache": "robbers_camp", "cache_place": "the robbers' chest"}}) as Chest
	if chest == null:
		_check(false, "a camp chest spawned beside the player")
		return
	var id := str(player.player_id)
	var record: PlayerRecord = _main._records.get(id)
	var caches_were := record.caches.duplicate()
	record.caches.erase("robbers_camp")
	var gold_was := World.gold_of(id)
	_check(not _main.search(player, chest) and World.gold_of(id) == gold_was, "no key: locked, no gold (742 amended)")
	# Brand felled by them: his key in their pack.
	var brand := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "kind": "robber_brute", "name": "KeyBrand%d" % World.tick,
		"tile": _main._nearest_free(player.tile + Vector2i(0, 2))}) as Monster
	brand.named_id = Main.CAMP_KEY_FROM
	brand.note_struck(player)
	World.damage(brand, 9999)
	var keys := func() -> int: return Array(player.slots).count(Main.CAMP_KEY)
	_check(keys.call() == 1 and _heard.slice(-1) == ["You take the key from Brand's belt."]
		and _main.party_log.last(4).has("%s takes the key from Brand's belt." % _main._display_name(player)),
		"Brand felled by them: his key in their pack, and said on their screen (%s %s)" % [player.slots, _heard.slice(-1)])
	var first: bool = _main.search(player, chest)
	var after_first := World.gold_of(id)
	_check(first and after_first == gold_was + 25 and keys.call() == 0 and "robbers_camp" in record.caches,
		"opened with his key: 25 gold to the purse, the key used up (%d -> %d)" % [gold_was, after_first])
	var brand2 := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "kind": "robber_brute", "name": "KeyBrand%d" % World.tick,
		"tile": _main._nearest_free(player.tile + Vector2i(0, 2))}) as Monster
	brand2.named_id = Main.CAMP_KEY_FROM
	brand2.note_struck(player)
	World.damage(brand2, 9999)
	_check(not _main.search(player, chest) and World.gold_of(id) == after_first and keys.call() == 1,
		"once per player for good: with another key, empty, the key kept")
	var rec2 := PlayerRecord.from_dict(JSON.parse_string(JSON.stringify(record.to_dict())))
	_check("robbers_camp" in rec2.caches, "the opening is saved with their record")
	for slot in player.slots.size():
		if player.slots[slot] == Main.CAMP_KEY:
			var slots := player.slots.duplicate()
			var uids := World.slot_uids(player)
			slots[slot] = ""
			uids[slot] = 0
			World.set_slots(player, slots, uids)
	World.add_gold(id, gold_was - World.gold_of(id), "test")
	record.caches.assign(caches_were)
	World.despawn(chest)


## 752, dungeon's side (the playtest's "AstralKnight1"): a monster is never
## called by its node name. [param knight] is the fallen knight, spawned.
func _test_monster_names(knight: AstralKnight) -> void:
	var node_name := RegEx.create_from_string("^[A-Za-z_]+\\d+$")
	var sir: String = _main.barrow_knight()
	var robber := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "kind": "robber", "name": "NameRobber%d" % World.tick,
		"tile": _main._nearest_free(knight.tile + Vector2i(0, 2))}) as Monster
	var words := []
	for monster: Monster in [knight, robber]:
		words.append(_main._display_name(monster))
		words.append(_main._speaker_name(monster))
	_check(words.all(func(word: String) -> bool: return node_name.search(word) == null and not word.is_empty()),
		"no node name for a monster, in a sentence or as a speaker: %s" % [words])
	_check(_main._display_name(knight) == (sir if not sir.is_empty() else Main.KNIGHT_UNNAMED)
		and _main._speaker_name(knight) == Main.capital_first(sir if not sir.is_empty() else Main.KNIGHT_UNNAMED),
		"the knight is the generation's sepulcher knight (%s)" % _main._speaker_name(knight))
	_check(_main._display_name(robber) == "the grave robber" and _main._speaker_name(robber) == "The grave robber",
		"an unnamed robber: \"the grave robber\", \"The grave robber\" as a speaker")
	robber.given_name = "Crake"
	_check(_main._display_name(robber) == "Crake" and _main._speaker_name(robber) == "Crake", "a named one by its given name (752)")
	var log := PartyLog.new()
	log.add("the draugr hits you.")
	_check(log.last(1) == ["The draugr hits you."], "a party-log line opening on a monster's name has its capital")
	World.despawn(robber)


## The fallen knight's quest (747; Jeff: "a astral projection of a fallen
## knight in the altar room that gives the quest ... stop the grave robbers
## and ill then give access to the crypt"; 747 amended (8): "at the
## beginning by the actual altar"): he stands in the First Hall behind its
## bier and is never hurt; his ask, the nine named robbers on the taker's
## list once each (own and own companion's kills, this generation's before
## the taking counted at it),
## the turn-in sets the flag and reveals the way; an old record loads as no
## quest; the reset clears it.
func _test_barrow_quest() -> void:
	print("
== the fallen knight's quest (747): his ask, the nine on the list, the turn-in, the way revealed ==")
	_main.altar_turn_in = false  # The turn-in's own end first; the altar step below (896, on since its switch-on).
	var barrow := Level.load_level("barrow")
	var knights := (barrow.get("entities", []) as Array).filter(func(spec: Dictionary) -> bool: return spec.get("kind") == "astral_knight")
	_check(knights.size() == 1 and knights[0]["script"] == "res://sim/astral_knight.gd" and knights[0]["tile"] == Vector2i(39, 10),
		"the barrow's First Hall has the fallen knight, behind its bier (747 amended (8)) (%s)" % [knights.map(func(k: Dictionary) -> Variant: return k.get("tile"))])
	var player := _player()
	var id := player.player_id
	var record: PlayerRecord = _main._records.get(id)
	if record == null:
		_check(false, "no record for the test player")
		return
	var kept := {"marks": record.marks.duplicate(), "task": record.barrow_task.duplicate(true)}
	_main.mark_player(id, Main.QUEST_DONE, false)
	record.barrow_task = {}
	_main._sync_quest(record)
	var band: Array = _main.band_ids("barrow")
	var knight := _main._spawn({"script": "res://sim/astral_knight.gd", "shape": "capsule", "kind": "astral_knight", "name": "QuestKnight%d" % World.tick,
		"tile": _main._nearest_free(player.tile + Vector2i(2, 0)), "props": Level.MONSTER_TYPES["astral_knight"].duplicate()}) as AstralKnight
	var hp := knight.hp
	World.damage(knight, 50, player)
	_check(knight.spawned and knight.hp == hp and knight.talks and knight.peaceable and _main.talks_peaceably(knight) and not knight.threatens(player),
		"he talks peaceably, threatens nobody, and a blow passes through him (%d -> %d)" % [hp, knight.hp])
	var ids := func() -> Array: return knight.offers_for(id).map(func(offer: Dictionary) -> String: return str(offer["id"]).get_slice(":", 2))
	_check(_main.barrow_quest_of(id) == "ask" and ids.call() == ["ask"] and player.quest.is_empty() and not _main.way_revealed(id, "barrow"),
		"a stranger: his ask, no quest yet, the way not revealed (%s)" % [ids.call()])
	_test_monster_names(knight)
	var sir: String = _main.barrow_knight()
	var asked := str(knight.offers_for(id)[0].get("words", ""))
	_check(asked == (AstralKnight.ASK_UNNAMED if sir.is_empty() else AstralKnight.ASK_WORDS % sir),
		"his ask names him, the generation's sepulcher knight (747 amended (2)): %s" % asked.get_slice(",", 0))
	var slay := func(named: String, by: GridEntity) -> void:
		var robber := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "kind": "robber", "name": "QuestRobber%d" % World.tick,
			"tile": _main._nearest_free(player.tile + Vector2i(0, 2))}) as Monster
		robber.named_id = named
		if by != null:
			robber.note_struck(by)
		World.damage(robber, 999)
	# 747 amended (8) (the coordinator; Jeff reached the knight over the band's dead): a band
	# member felled this generation before the taking counts at it; nobody's kill does not.
	_main._plain_band_slain.clear()
	if _main._regen.has("barrow"):
		(_main._regen["barrow"] as Dictionary).erase("band_slain")
	slay.call(band[1], player)
	slay.call(band[1], player)
	slay.call(band[3], null)
	_check(record.barrow_task.is_empty() and _main._band_slain_by(id) == [band[1]],
		"%s felled twice before the taking (risen): kept once for the generation, not yet on a list (%s)" % [band[1], _main._band_slain_by(id)])
	var saved_slain: Variant = JSON.parse_string(JSON.stringify({"barrow": {"generation": 2, "at_step": 5, "band_slain": {band[1]: [id]}}}))
	_check(Regen.states_from(saved_slain)["barrow"].get("band_slain") == {band[1]: [id]},
		"whom they felled is saved and read back with the generation: a restart keeps it (747 amended (8))")
	var kept_label := player.label
	player.label = "Wren of the Test"  # The name the plate shows, not the node's (548 amended (2)'s World.shown_name).
	_main._monster_accepts(knight, player, {"id": "quest:%d:ask" % knight.id}, 0)
	var took := {"ok": _main.barrow_quest_of(id) == "open"}
	var taking_logged: Array = _main.party_log.last(1)
	player.label = kept_label
	_check(_heard.slice(-1) == ["You take up the fallen knight's task."] and taking_logged == ["Wren of the Test takes up the fallen knight's task."],
		"the deal's line (the knight's taking) reaches the screens there, not the party log alone, naming the player as their plate does (%s, %s)" % [_heard.slice(-1), taking_logged])
	var items: Array = player.quest.get("items", [])
	_check(took["ok"] and _main.barrow_quest_of(id) == "open" and ids.call() == ["not_yet"]
		and player.quest.get("title") == Main.QUEST_TITLE and player.quest.get("giver") == "the fallen knight" and items.size() == 9
		and items[0] == {"name": "Brand the Ox", "done": false} and items[1]["done"] == true and items[3]["done"] == false
		and not bool(player.quest.get("ready", true)) and record.barrow_task.get("slain") == [band[1]],
		"taken: open, \"not yet\"; the tracker's nine, the one felled before checked, nobody's kill not (%s)" % [player.quest])
	# 747 amended (6): the card shows only in the quest's own place, named from the level data.
	_check(player.quest.get("zones") == ["barrow", "barrow_deep"] and _main.quest_zones() == ["barrow", "barrow_deep"],
		"its card's places: the band's barrow and its depths, the knight among them (%s)" % [player.quest.get("zones")])
	slay.call(band[1], player)
	slay.call(band[1], player)
	_check(record.barrow_task.get("slain") == [band[1]] and (player.quest["items"] as Array)[1]["done"] == true,
		"%s felled twice more (risen): on the list once, checked (%s)" % [band[1], record.barrow_task])
	slay.call(band[2], null)
	_check(not (band[2] in record.barrow_task.get("slain", [])), "a kill not theirs is not on their list")
	# 747 amended (15) (the coordinator, voice's words): a fall in the band's zone with the task
	# open, and his next greeting says FELL in place of "not yet", once.
	var home_zone := player.zone
	AstralKnight.fallen.erase(id)
	_main.note_barrow_fall(player)
	var outside_fall := str(knight.offers_for(id)[0]["words"])
	player.zone = "barrow"
	_main.note_barrow_fall(player)
	player.zone = home_zone
	var after_fall := str(knight.offers_for(id)[0]["words"])
	_main._monster_greeted(player, knight)
	var greeted_said: Array = _main.party_log.last(1)
	var window_after := str(knight.offers_for(id)[0]["words"])
	_main._monster_greeted(player, knight)
	var next_said: Array = _main.party_log.last(1)
	_check(outside_fall == AstralKnight.NOT_YET and after_fall == AstralKnight.FELL and str(greeted_said).contains(AstralKnight.FELL)
		and window_after == AstralKnight.FELL and str(next_said).contains(AstralKnight.NOT_YET)
		and str(knight.offers_for(id)[0]["words"]) == AstralKnight.NOT_YET and not AstralKnight.fallen.has(id),
		"a fall elsewhere: \"not yet\"; in the barrow: FELL at the next greeting, his window asked after it the same, the greeting after \"not yet\" (%s, %s)" % [greeted_said, next_said])
	var old := record.to_dict()
	old.erase("barrow_task")
	_check(PlayerRecord.from_dict(JSON.parse_string(JSON.stringify(record.to_dict()))).barrow_task == record.barrow_task
		and PlayerRecord.from_dict(JSON.parse_string(JSON.stringify(old))).barrow_task.is_empty(),
		"saved and loaded the same; a record saved before 747 loads as no quest")
	_check(not knight.accept_offer(player, {"id": "quest:%d:turn_in" % knight.id}, 0)["ok"], "no turn-in before all nine")
	for named: String in band:
		if named != band[1]:
			slay.call(named, player)
	_check(_main.barrow_quest_of(id) == "ready" and ids.call() == ["turn_in"] and bool(player.quest.get("ready", false))
		and (player.quest["items"] as Array).all(func(item: Dictionary) -> bool: return item["done"]),
		"all nine: ready, the turn-in, every box checked")
	var turned: Dictionary = knight.accept_offer(player, {"id": "quest:%d:turn_in" % knight.id}, 0)
	_check(turned["ok"] and Main.QUEST_DONE in record.marks and record.barrow_task.is_empty() and player.quest.is_empty()
		and _main.barrow_quest_of(id) == "" and ids.call() == ["done"] and _main.way_revealed(id, "barrow"),
		"turned in: the flag set, the tracker gone, the way revealed to them, only his closing words offered")
	# 747 amended (5) (Jeff on v0.1.197: "fallen knight was not interactable"): done, a click
	# still opens his window: DONE alone, accept "none", no gold; no record, nothing.
	var closing: Array = knight.offers_for(id)
	_check(closing.size() == 1 and closing[0]["words"] == AstralKnight.DONE and closing[0]["accept"] == AstralKnight.WORDS_ONLY
		and str(closing[0]["title"]).is_empty() and int(closing[0]["cost"]) == 0 and DealPanel.is_quest(closing[0])
		and knight.offers_for("no-such-player").is_empty(),
		"done, his window still opens: his closing words alone, accept \"none\" (%s)" % [closing])
	_check(_main.reset_barrow(id).has("the fallen knight's quest") and _main.barrow_quest_of(id) == "ask" and not _main.way_revealed(id, "barrow"),
		"the reset (quests reset all's reset_barrow): the flag cleared, his ask again")
	_check(_main._band_slain_by(id).is_empty(), "and the reset forgets whom they felled this generation (747 amended (8))")
	for named: String in band:
		slay.call(named, player)
	var over_the_dead: Dictionary = knight.accept_offer(player, {"id": "quest:%d:ask" % knight.id}, 0)
	_check(over_the_dead["ok"] and _main.barrow_quest_of(id) == "ready" and ids.call() == ["turn_in"] and bool(player.quest.get("ready", false)),
		"taken over the whole band felled first: straight to ready, the turn-in offered (747 amended (8))")
	# 896 ("full circle"): the altar step on, the turn-in goes on to his remains, laid by his row.
	_drop_relics(player)  # An earlier case's remains (714 amended (3)) are not his to lay here.
	_main.altar_turn_in = true
	var revealed: Dictionary = knight.accept_offer(player, {"id": "quest:%d:turn_in" % knight.id}, 0)
	_check(revealed["ok"] and _main.barrow_quest_of(id) == "altar" and not (Main.QUEST_DONE in record.marks) and ids.call() == ["await"]
		and player.quest.get("items", []) == [{"name": Main.ALTAR_STEP, "done": false}] and not bool(player.quest.get("ready", true))
		and str(knight.offers_for(id)[0]["words"]) == AstralKnight.AWAIT,
		"altar on, turned in: not yet done, the card's one step to the altar, his words that the remains wait (%s)" % [player.quest])
	slay.call(band[2], player)
	_check(not record.barrow_task.has("slain"), "a robber felled after the turn-in counts nowhere (%s)" % [record.barrow_task])
	var relic := World.mint_relic(sir if not sir.is_empty() else "Sir Test", 0, player)
	World.into_pack(player, relic)
	_main._sync_quest(record)
	_check(_main.barrow_quest_of(id) == "carried" and ids.call() == ["lay"] and bool(player.quest.get("ready", false))
		and str(knight.offers_for(id)[0]["title"]) == AstralKnight.LAY_TITLE,
		"his remains in the pack: carried, his row to lay them, the card ready (%s)" % [ids.call()])
	var laid: Dictionary = knight.accept_offer(player, {"id": "quest:%d:lay" % knight.id}, 0)
	_check(laid["ok"] and Main.QUEST_DONE in record.marks and record.barrow_task.is_empty() and player.quest.is_empty()
		and _main.knights_relic_slot(player) < 0 and str(knight.offers_for(id)[0]["words"]) == AstralKnight.DONE_LAID
		and knight.remains_laid and knight.spawn_spec["props"].get("remains_laid") == true
		and str(laid.get("you_line", "")) == "You lay %s's remains on the bier." % (sir if not sir.is_empty() else "Sir Test"),
		"laid by his row: the remains gone from the pack, the quest done, the card closed, his thanks after, the line naming them on the bier (%s)" % [laid])
	_main.altar_turn_in = false
	_main.reset_barrow(id)
	World.despawn(knight)
	for state: Dictionary in _main._regen.values() + [_main._plain_band_slain]:
		state.erase("remains_laid")  # The bier bare again for the tests after (remains_laid_in).
	for slot in player.slots.size():
		if player.slots[slot] == Main.CAMP_KEY:  # Brand's, from the nine.
			var slots := player.slots.duplicate()
			var uids := World.slot_uids(player)
			slots[slot] = ""
			uids[slot] = 0
			World.set_slots(player, slots, uids)
	record.marks.assign(kept["marks"])
	record.barrow_task = kept["task"]
	_main.altar_turn_in = true
	_main._sync_quest(record)


## 747 amended (6) with ui's half (747 amended (7)): a taken quest carries
## its zones to the player and the HUD's own card (Main.quest_panel, ui's
## QuestPanel, reading the local player as the client does) shows only on
## the crypt's two floors: travelled to each place as a player is, the card
## drawn in the barrow and barrow_deep, gone in the bear's cave and the wilds
## (Umbrage).
func _test_quest_card_place() -> void:
	print("
== the quest card only in its own place (747 amended (6)): the HUD's card, place by place ==")
	var player := _player()
	if player == null or _main.quest_panel == null:
		_check(false, "a player and the HUD's quest card to test with")
		return
	var id := player.player_id
	var record: PlayerRecord = _main._records.get(id)
	var was := str(World.zone.name)
	var kept := {"marks": record.marks.duplicate(), "task": record.barrow_task.duplicate(true)}
	_main.mark_player(id, Main.QUEST_DONE, false)
	record.barrow_task = {"taken": true, "slain": []}
	var seen := {}
	var joined := {}
	for place: String in ["barrow", "barrow_deep", "bear_cave", "wilds"]:
		_main.load_map(place)
		var here := _player()
		_main._sync_quest(record)
		_main.quest_panel.step(1.0)
		_main.quest_panel.step(1.0)
		seen[place] = [here.zone if here != null else "", (here.quest.get("zones", []) if here != null else []), _main.quest_panel.visible]
		# 747 amended (9): as a joined client stands here. Its World.zone has
		# no name and its bodies none (World.spawn writes the zone's); the
		# level loaded names the place. The host-only check above passed while
		# the card hid everywhere on a client (playtest's walk on b411043ec).
		var zone_name := str(World.zone.name)
		var body_zone := here.zone if here != null else ""
		World.zone.name = ""
		if here != null:
			here.zone = ""
		_main.quest_panel.step(1.0)
		_main.quest_panel.step(1.0)
		joined[place] = [_main._quest_zone(), _main.quest_panel.visible]
		World.zone.name = zone_name
		if here != null:
			here.zone = body_zone
	_check(seen["barrow"][2] and seen["barrow_deep"][2] and not seen["bear_cave"][2] and not seen["wilds"][2]
		and seen.values().all(func(row: Array) -> bool: return row[1] == ["barrow", "barrow_deep"]),
		"the card on both crypt floors, gone in the bear's cave and the wilds; the quest's zones reach the player in each (%s)" % [seen])
	_check(joined["barrow"] == ["barrow", true] and joined["barrow_deep"] == ["barrow_deep", true]
		and joined["bear_cave"] == ["bear_cave", false] and joined["wilds"] == ["wilds", false],
		"a joined client (its zone unnamed, its body's too): the card on both crypt floors, gone in the bear's cave and the wilds (Umbrage), each place named by the level loaded (%s)" % [joined])
	record.marks.assign(kept["marks"])
	record.barrow_task = kept["task"]
	_main.load_map(was)
	_main._sync_quest(record)


## The tower's floors (659): the sample tower in memory, each floor parsing
## clean, the stairs linking floor to floor both ways with their cues up and
## down, the foot's door out an arch and its way down to the mine sealed.
func _test_tower_levels() -> void:
	print("
== the tower's floors (659): stairs both ways, the door and the sealed hatch at the foot ==")
	var floors := Sheet.TOWER_FLOORS
	for floor in range(1, floors + 1):
		var sample := Sheet.sample_tower(floor, floors, "lt_tower")
		Level.register("lt_tower_%d" % floor, sample["layout"], null, sample["config"])
	var c := Sheet.TOWER_ACROSS / 2
	var cue_at := func(level: Dictionary, at: Vector2i) -> String:
		for cue: Dictionary in level["terrain"]["link_cues"]:
			if cue["tile"] == at:
				return str(cue["cue"])
		return ""
	var link_at := func(level: Dictionary, at: Vector2i) -> Dictionary:
		for link: Dictionary in level["links"]:
			if link["tile"] == at:
				return link
		return {}
	for floor in range(1, floors + 1):
		var level := Level.load_level("lt_tower_%d" % floor)
		_check(not level.is_empty() and level["warnings"].is_empty() and level["size"] == Vector2i(Sheet.TOWER_ACROSS, Sheet.TOWER_ACROSS)
			and Regen.marked("lt_tower_%d" % floor) and Regen.config_of("lt_tower_%d" % floor).get("style") == "tower",
			"floor %d parses with no warning, marked to regenerate in the tower style (%s)" % [floor, level.get("warnings")])
		if floor < floors:
			var above := Level.load_level("lt_tower_%d" % (floor + 1))
			var up: Dictionary = link_at.call(level, Vector2i(c + 1, c))
			_check(up.get("to_map") == "lt_tower_%d" % (floor + 1) and up.get("to_spawn") == "from_below" and cue_at.call(level, Vector2i(c + 1, c)) == "up"
				and above["spawn_points"].get("from_below") == Vector2i(c - 1, c + 1) and above["terrain"]["floor"].has(Vector2i(c - 1, c + 1)),
				"floor %d's stair up (cue up) leads to floor %d's from_below, a floor cell beside its stair down (%s)" % [floor, floor + 1, up])
		else:
			_check(link_at.call(level, Vector2i(c + 1, c)).is_empty(), "the top floor has no stair up")
		if floor > 1:
			var below := Level.load_level("lt_tower_%d" % (floor - 1))
			var down: Dictionary = link_at.call(level, Vector2i(c - 1, c))
			_check(down.get("to_map") == "lt_tower_%d" % (floor - 1) and down.get("to_spawn") == "from_above" and cue_at.call(level, Vector2i(c - 1, c)) == "down"
				and below["spawn_points"].get("from_above") == Vector2i(c + 1, c + 1) and below["terrain"]["floor"].has(Vector2i(c + 1, c + 1)),
				"floor %d's stair down (cue down) leads to floor %d's from_above, a floor cell beside its stair up (%s)" % [floor, floor - 1, down])
		else:
			_check(link_at.call(level, Vector2i(c - 1, c)).is_empty(), "the foot has no stair down")
			var door: Dictionary = link_at.call(level, Vector2i(c, Sheet.TOWER_ACROSS - 2))
			var arch: Array = level["terrain"]["link_cues"].filter(func(cue: Dictionary) -> bool: return cue["tile"] == Vector2i(c, Sheet.TOWER_ACROSS - 2))
			_check(door.get("to_map") == "lt_tower_outside" and cue_at.call(level, Vector2i(c, Sheet.TOWER_ACROSS - 2)) == "arch"
				and arch.size() == 1 and arch[0]["variant"] == 3 and level["spawn_points"].get("from_outside") == Vector2i(c, Sheet.TOWER_ACROSS - 3),
				"the foot's door out at the south edge is the dark arch (variant 3) with from_outside inside it (%s)" % [door])
			var hatch: Dictionary = link_at.call(level, Vector2i(c, 2))
			_check(hatch.get("to_map") == "lt_tower_mine" and hatch.get("sealed") == "tower_mine" and cue_at.call(level, Vector2i(c, 2)) == "sealed",
				"the mine's way down under the north wall is a sealed link (%s)" % [hatch])


## The way behind the throne under the fight lock (540 amended (1); Jeff's report,
## 2026-11-12: "draugr room to the rear his throne there is a exit to return
## to the crypt entrance"; his rule, "the door closes when you enter"). 896
## switched on took that way out both ends (the throne is the way home): the
## held Hall has no way out in it and no way from the barrow arrives in it;
## the lock still holds a way laid in a held lair, whatever level lays one.
func _test_throne_way_held() -> void:
	print("\n== no way out behind the throne; the held lair holds any way in it (540 amended (1), 896) ==")
	_main.load_map("test_room")
	_main.travel(Net.local_id, "barrow_deep", "")
	await get_tree().process_frame
	_main._hold_hall_door("barrow_deep", true)
	var lair: Rect2i = _main.hall_lair_rect("barrow_deep")
	var in_lair: Array = _main.level.get("links", []).filter(func(link: Dictionary) -> bool: return lair.has_point(link["tile"]))
	_check(_main.map_name == "barrow_deep" and _main.hall_held("barrow_deep") and lair.has_area() and in_lair.is_empty(),
		"the Hall held: no way out in its lair (%s, %s)" % [lair, in_lair])
	var into: Array = Level.load_level("barrow").get("links", []).filter(func(link: Dictionary) -> bool:
		return link["to_map"] == "barrow_deep" and _main.hall_link_held(link, "barrow"))
	_check(into.is_empty(), "no way from the barrow arrives in the held Hall (%s)" % [into])
	var laid := {"tile": Vector2i(49, 77), "to_map": "barrow", "to_spawn": "from_deep", "sealed": "draugr"}
	_check(_main.hall_link_held(laid), "a way laid in the held lair would be held all the same")
	_main._hold_hall_door("barrow_deep", false)
	_check(not _main.hall_held("barrow_deep") and not _main.hall_link_held(laid), "let go: not held")
	_main.load_map("test_room")


## The draugr's Hall is the room he keeps (548 amended (4); dungeon's read, the
## coordinator's ruling): barrow_deep as the game lays it, his room (his row's
## keeps_room, Monster.room_of(home)) is the rect Main.hall_lair_rect gives the
## Hall's door lines (573 amended (6)), one source for both; a player in the door
## row or beside its walls is not in it, one inside its far corners is. And none
## outside it can strike him where he sits: no walkable cell outside his rect lies
## within the longest reach of any ranged verb or move in the items and monsters
## data (a wider Hall, a moved seat or a longer reach reopens the question), on
## the template and on the crypt generated round it (generations 1-8, 109, 118).
func _test_draugr_hall_is_his_room() -> void:
	print("
== the draugr's Hall is the room he keeps, and nobody outside it reaches his seat (548 amended (4)) ==")
	_main.load_map("test_room")
	_main.travel(Net.local_id, "barrow_deep", "")
	await get_tree().process_frame
	var lair: Rect2i = _main.hall_lair_rect("barrow_deep")
	var draugr: Draugr = null
	for each: Monster in World.monsters():
		if each is Draugr:
			draugr = each
	_check(draugr != null and draugr.keeps_room and lair.has_area() and draugr._room == lair,
		"his room is the Hall's rect (%s, %s)" % [draugr._room if draugr != null else "no draugr", lair])
	if draugr == null:
		_main.load_map("test_room")
		return
	var read := {}
	for cell: Vector2i in [Vector2i(49, 54), Vector2i(49, 55), Vector2i(31, 70), Vector2i(67, 70), Vector2i(49, 56), Vector2i(34, 77), Vector2i(65, 56)]:
		read[cell] = draugr._in_lair_cell(cell)
	_check(not read[Vector2i(49, 54)] and not read[Vector2i(49, 55)] and not read[Vector2i(31, 70)] and not read[Vector2i(67, 70)]
		and read[Vector2i(49, 56)] and read[Vector2i(34, 77)] and read[Vector2i(65, 56)],
		"outside the door, in its row and beside the walls: not his Hall; inside to its corners: his Hall (%s)" % [read])
	var longest := 0
	var by := ""
	for id: String in Items.ids():
		var verb: Variant = Items.def(id).get("verb", {})
		if verb is Dictionary:
			for step: Variant in verb.get("steps", []):
				if int(step) > longest:
					longest = int(step)
					by = id
			if verb.get("reach") is int or verb.get("reach") is float:
				if int(verb["reach"]) > longest:
					longest = int(verb["reach"])
					by = id
	var kinds: Dictionary = Monster.kinds()
	for kind: String in kinds:
		var moves: Variant = kinds[kind].get("moves", {})
		if moves is Dictionary:
			for move: String in moves:
				for key: String in ["reach", "day_reach"]:
					var reach: Variant = moves[move].get(key) if moves[move] is Dictionary else null
					if (reach is int or reach is float) and int(reach) > longest:
						longest = int(reach)
						by = "%s's %s" % [kind, move]
	var seat := draugr.home
	var nearest := 9999
	var at := Vector2i(-1, -1)
	for cell: Vector2i in World.floor_cells():
		if not lair.has_point(cell) and World.distance(seat, cell) < nearest:
			nearest = World.distance(seat, cell)
			at = cell
	_check(longest > 0 and nearest > longest,
		"no floor outside his Hall within the longest ranged reach of his seat %s: the nearest %s, %d off; the longest reach %d (%s)" % [seat, at, nearest, longest, by])
	# The template's floor is the Hall and the Charnel Vault alone; the crypt
	# the game lays is generated round them, so its generations are read too.
	var near := {}
	for generation: int in [1, 2, 3, 4, 5, 6, 7, 8, 109, 118]:
		var made := Regen.generate("barrow_deep", generation)
		var ground: Array = Level.parse(made["layout"], made["height"], made["config"])["terrain"]["floor"]
		var gen_lair: Rect2i = lair
		for anchor: Dictionary in made["config"].get("anchors", Regen.config_of("barrow_deep").get("anchors", [])):
			if str(anchor.get("name", "")) == "lair":
				gen_lair = anchor["rect"]
		var best := 9999
		var best_at := Vector2i(-1, -1)
		var seat_in := false
		for cell: Vector2i in ground:
			seat_in = seat_in or cell == seat
			if not gen_lair.has_point(cell) and World.distance(seat, cell) < best:
				best = World.distance(seat, cell)
				best_at = cell
		if not seat_in or gen_lair != lair or best <= longest:
			near[generation] = "seat on its floor %s, lair %s, nearest outside %s %d off, of %d floor cells" % [seat_in, gen_lair, best_at, best, ground.size()]
		elif generation == 1:
			print("  generation 1: nearest floor outside his Hall %s, %d off his seat, of %d floor cells" % [best_at, best, ground.size()])
	_check(near.is_empty(), "the crypt's generations 1-8, 109 and 118: his Hall where the template has it, his seat on its floor, no floor outside it within %d of the seat (%s)" % [longest, near])
	_main.load_map("test_room")


## The draugr's throne, the way home once he is downed (896, "full circle";
## Jeff, 2026-11-12: "it would be cool if sitting on the throne kicks you
## back to the entrance, but only possible if the draugr is downed"). Off,
## a click on it is nothing; on, while he holds it he is told THRONE_HIS once;
## at rest, a stand on it alone sends no one, a sit is undone by a step off
## or another order, and a sit held THRONE_SIT_S sends the sitter to the
## First Hall's from_deep.
func _test_throne_home() -> void:
	print("\n== the draugr's throne: the way home once he is downed (896) ==")
	var kept_switch: bool = _main.throne_home
	_main.load_map("test_room")
	_main.travel(Net.local_id, "barrow_deep", "")
	await get_tree().process_frame
	var throne := Vector2i(49, 75)
	var draugr: Draugr = null
	for entity in World.get_entities():
		if entity is Draugr:
			draugr = entity as Draugr
	var player := _player()
	if draugr == null or player == null or _main.throne_at("barrow_deep", throne).is_empty():
		_check(false, "barrow_deep's draugr, a player and the throne at %s (%s, %s)" % [throne, draugr, player])
		_main.throne_home = kept_switch
		_main.load_map("test_room")
		return
	var heard: Array[String] = []
	var hear := func(kind: String, data: Dictionary) -> void:
		if kind == "party":
			heard.append(str(data.get("text", "")))
	Net.message_received.connect(hear)
	var front: Vector2i = _main._beside(throne, throne + Vector2i(0, -2))
	_put(player, front)
	_main.throne_home = false
	_main._told_throne.erase(Net.local_id)
	_main._on_command(player, "throne", {"at": [throne.x, throne.y]})
	_check(player.seated == "" and heard.count(_main.THRONE_HIS) == 0 and not _main._throne_sits.has(Net.local_id),
		"off: asked from beside it, nothing (%s, %s)" % [player.seated, heard])
	_main.throne_home = true
	_main._on_command(player, "throne", {"at": [throne.x, throne.y]})
	_main._on_command(player, "throne", {"at": [throne.x, throne.y]})
	_check(draugr.state == Draugr.State.SEATED and player.seated == "" and heard.count(_main.THRONE_HIS) == 1,
		"on, while he sits it: told once that it is his, not sat (%s, %s)" % [player.seated, heard])
	# Laid to rest by the test-only console (896's switch-on, for playtest's walk): unknown without --test-hp.
	var had_hp: bool = Net.test_hp
	Net.test_hp = false
	var refused: String = _main.admin_command("rest draugr")
	Net.test_hp = true
	# Asked from another zone (11-13's saturn stop at (49,74): the rest
	# vacated a cell in the zone World was in, and his seat stayed held).
	var bar_before: bool = _main.boss_in_sight() == draugr
	var seat_at: Vector2i = draugr.tile
	var other := ""
	for each: String in World.zones:
		if each != "barrow_deep":
			other = each
	var was_zone := World.enter_named(other) if not other.is_empty() else World.zone
	var rested: String = _main.admin_command("rest draugr")
	var still_other: bool = World.zone.name == other
	var again: String = _main.admin_command("rest draugr")
	World.enter(was_zone)
	Net.test_hp = had_hp
	_check(refused.begins_with("unknown command") and rested == "rest draugr: barrow_deep's draugr laid to rest" and draugr.resting()
		and again == "rest draugr: the draugr in barrow_deep already rests",
		"the test-only console lays him to rest, once; without --test-hp it is unknown, as on the box (%s / %s / %s)" % [refused, rested, again])
	_check(not other.is_empty() and still_other and World.get_entity_at(seat_at) != draugr and not draugr.holds_cell,
		"asked from another zone (%s): his own zone's seat freed, World left where it was (%s)" % [other, seat_at])
	_check(bar_before and _main.boss_in_sight() == null,
		"the boss bar: over him seated, gone once he rests and holds no cell (in v0.1.214 it stood over him)")
	# A joined client's mirror: his going (replicated "gone") frees his seat
	# there too, so a click's route can end on the throne (look_circle3).
	var kept_mode: int = Net.mode
	Net.mode = Net.Mode.CLIENT
	draugr.gone = false
	var held_mirrored: bool = World.get_entity_at(draugr.tile) == draugr
	draugr.gone = true
	var freed_mirrored: bool = World.get_entity_at(draugr.tile) != draugr
	Net.mode = kept_mode
	_check(held_mirrored and freed_mirrored and not draugr.holds_cell,
		"on a client, his going frees his seat in the mirror (held %s, freed %s)" % [held_mirrored, freed_mirrored])
	# Laid to rest on his seat, his remains lie on the throne: a click or E
	# there is the throne's, not his rest words (playtest's look_circle2).
	_main.throne_home = false
	var pile_talks: bool = _main.remains_at(draugr.pile_at) == draugr
	_main.throne_home = true
	_check(draugr.pile_at == throne and pile_talks and _main.remains_at(throne) == null,
		"his remains on the throne's cell: with the throne off a click there talks to him; on, it is the throne's (%s)" % [draugr.pile_at])
	# The whole click as a player makes it (look_circle3 and the two-phase
	# walk on 32438be87: joined, the walk stopped a cell short and nobody
	# sat): from two cells off, him at rest and his remains on the seat, the
	# click's own route walked out by the free drive, the throne asked on
	# arrival (_update_throne), seated.
	var two_off := throne + Vector2i(0, -2)
	_put(player, two_off)
	player.free_view = null
	player.free_halt_until = 0
	_main._throne_click(player, throne)
	var route: Array = (_main._free["path"] as Array).duplicate()
	var wanted: Vector2i = _main._throne_wanted
	var sat_by_click := false
	for i in 600:
		player.free_allowance = World.FREE_COMMANDS_PER_SECOND  # The test runs faster than the clock.
		_main._free_drive(1.0 / 60.0)
		_main._update_throne()
		if i % 6 == 5:
			World.step()
		if player.seated == "throne":
			sat_by_click = true
			break
	_check(sat_by_click, "a click on the throne from two cells off, him at rest: walked onto it and seated (route %s, wanted %s, at %s, free at %s)"
			% [route, wanted, player.tile, player.free_pos])
	if sat_by_click:
		_main._throne_stand(Net.local_id)
	_main._free["path"] = []
	_put(player, throne)
	for i in roundi(_main.THRONE_SIT_S * World.TICK_RATE) + 3:
		World.step()
	_check(_main.map_name == "barrow_deep" and player.seated == "",
		"downed, a walk onto it alone sends no one (%s, %s)" % [_main.map_name, player.seated])
	_main._on_command(player, "throne", {"at": [throne.x, throne.y]})
	_check(player.seated == "throne" and player.facing == Vector2i(0, -1) and _main._throne_sits.has(Net.local_id),
		"asked on it while he rests: she sits, facing the hall (%s, %s)" % [player.seated, player.facing])
	World.step()
	_put(player, front)
	World.step()
	_check(player.seated == "" and not _main._throne_sits.has(Net.local_id) and _main.map_name == "barrow_deep",
		"a step off before the send stands her up, sent nowhere (%s, %s)" % [player.seated, _main.map_name])
	_put(player, throne)
	_main._on_command(player, "throne", {"at": [throne.x, throne.y]})
	_main._on_command(player, "stance", {"kind": ""})
	_check(player.seated == "" and not _main._throne_sits.has(Net.local_id), "another order stands her up as well (%s)" % player.seated)
	_main._on_command(player, "throne", {"at": [throne.x, throne.y]})
	_main._on_command(player, "say", {"text": "home"})
	_check(player.seated == "throne", "talk leaves her seated (%s)" % player.seated)
	for i in roundi(_main.THRONE_SIT_S * World.TICK_RATE) + 2:
		World.step()
		if _main.map_name != "barrow_deep":
			break
	await get_tree().process_frame
	await get_tree().process_frame
	player = _player()
	var at: Vector2i = player.tile if player != null else World.NO_CELL
	_check(_main.map_name == "barrow" and World.distance(at, Vector2i(31, 8)) <= 1 and player.seated == "" and _main._throne_sits.is_empty(),
		"held THRONE_SIT_S, she is sent home to the First Hall's from_deep (%s, at %s)" % [_main.map_name, at])
	Net.message_received.disconnect(hear)
	var deep: Zone = World.zones.get("barrow_deep")
	if deep != null:
		var was := World.zone
		World.enter(deep)
		for entity in World.get_entities():
			if entity is Draugr:
				(entity as Draugr)._rise_again()
		World.enter(was)
	_main.throne_home = kept_switch
	_main.load_map("test_room")


## Package "full circle" switched on (896): one switch turns the throne
## and the altar together, on by default; the shortcut's two ends gone, so
## an arrival by its old spawn or a saved stand on its old cell lands on
## open floor; no cell a player lays from beside the bier is the knight's.
func _test_full_circle_on() -> void:
	print("\n== package full circle switched on (896) ==")
	_check(_main.full_circle and _main.throne_home and _main.altar_turn_in and AstralKnight.altar_on, "on by default: the throne, the altar and his words")
	# The sepulcher's plaque and the taking line by the switch (voice): on, the bier above; off, the temple's altar.
	var plaque_on: String = _main.sepulcher_plaque()
	var for_on: String = _main.remains_for()
	_main.altar_turn_in = false
	var plaque_off: String = _main.sepulcher_plaque()
	var for_off: String = _main.remains_for()
	_main.altar_turn_in = true
	_check(plaque_on == "Here rest the holy remains of %s, knight of Theus, until they are laid on the bier above." and for_on == "for his bier"
		and plaque_off == "Here rest the holy remains of %s, knight of Theus, until the altar calls them home." and for_off == "for the altar",
		"the plaque and the taking: the bier above when on, the temple's altar when off (%s / %s)" % [for_on, for_off])
	# The test-only relic verb (playtest's walk): a brother's remains in the pack, by name.
	var had_hp: bool = Net.test_hp
	Net.test_hp = true
	var me := _player()
	var my_record: PlayerRecord = _main._records.get(me.player_id) if me != null else null
	var my_name := my_record.name if my_record != null else ""
	var given: String = _main.admin_command("relic %s Sir Ansel the Faithful" % my_name)
	Net.test_hp = had_hp
	var brother_slot := -1
	if me != null:
		for slot in me.slots.size():
			if str(World.relic_of(World.slot_uid(me, slot)).get("knight", "")) == "Sir Ansel the Faithful":
				brother_slot = slot
	_check(given == "relic: the remains of Sir Ansel the Faithful at %s's pack" % my_name and brother_slot >= 0,
		"the test-only relic verb puts a named knight's remains in the pack (%s)" % given)
	if brother_slot >= 0:
		World.consume(me, World.slot_uid(me, brother_slot), "test")
	# The test-only strike verb: the player's blow of all its hp, the player its slayer.
	_main.load_map("test_room")
	_main.travel(Net.local_id, "barrow_deep", "")
	await get_tree().process_frame
	me = _player()
	# The template lays no monsters of its own (a generation does), so one is spawned beside the player.
	var foe: Monster = null
	if me != null:
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(2, 0), Vector2i(0, 2)]:
			if World.is_walkable(me.tile + step):  # An occupied cell: World.spawn refuses it, _spawn gives null.
				foe = _main._spawn({"script": Level.MONSTER, "shape": "capsule", "name": "Struck_test", "tile": me.tile + step, "props": {"sight_range": 0}})
				if foe != null:
					break
	Net.test_hp = true
	var struck_words: String = _main.admin_command("strike %s %s" % [my_name, _main.monster_name(foe)]) if foe != null else ""
	var nobody: String = _main.admin_command("strike %s nobody at all" % my_name)
	Net.test_hp = had_hp
	var refused: String = _main.admin_command("strike %s nobody at all" % my_name)
	_check(foe != null and struck_words.begins_with("strike: %s struck " % my_name) and (not is_instance_valid(foe) or foe.hp <= 0 or foe.struck_by == me),
		"the test-only strike verb fells a monster in the player's zone, the player its slayer (%s)" % struck_words)
	_check(nobody.begins_with("strike: no monster in barrow_deep") and not refused.begins_with("strike"),
		"a name nobody bears strikes nothing, and without --test-hp the verb is unknown (%s / %s)" % [nobody, refused])
	_main.full_circle = false
	_check(not _main.throne_home and not _main.altar_turn_in and not AstralKnight.altar_on, "the one switch turns both halves off together")
	_main.full_circle = true
	_check(_main.throne_home and _main.altar_turn_in and AstralKnight.altar_on, "and on again")
	# Mid-crossing at the switch-on: a send still naming from_temple, and a
	# player saved on (49,77), the shortcut's cell, now rock.
	_main.load_map("test_room")
	_main.travel(Net.local_id, "barrow_deep", "from_temple")
	await get_tree().process_frame
	var player := _player()
	var at: Vector2i = player.tile if player != null else World.NO_CELL
	_check(_main.map_name == "barrow_deep" and World.is_walkable(at), "sent by the old spawn: in the Ossuary on open floor (at %s)" % [at])
	_main.load_map("test_room")
	_main.travel(Net.local_id, "barrow_deep", "", {}, Vector2i(49, 77))
	await get_tree().process_frame
	player = _player()
	at = player.tile if player != null else World.NO_CELL
	_check(_main.map_name == "barrow_deep" and at != Vector2i(49, 77) and World.is_walkable(at),
		"saved on the shortcut's old cell: placed on open floor, not in the rock (at %s)" % [at])
	_main.load_map("test_room")
	_main.travel(Net.local_id, "barrow", "", {}, Vector2i(30, 8))
	await get_tree().process_frame
	player = _player()
	at = player.tile if player != null else World.NO_CELL
	_check(_main.map_name == "barrow" and World.is_walkable(at) and World.distance(at, Vector2i(30, 8)) <= 1,
		"saved on the First Hall's old way down: plain floor there (at %s)" % [at])
	# No laying cell is the knight's (the coordinator's (1), 11-13: he holds his cell).
	var bier: Rect2i = _main.knights_altar("barrow")
	var knight: GridEntity = null
	for entity in World.get_entities():
		if entity is AstralKnight:
			knight = entity
	var on_him: Array[Vector2i] = []
	if bier.has_area() and knight != null:
		# From every walkable cell, his own among them (a shove or a bring-back
		# could put a player there): the pick never names a cell another body
		# holds; only the caller's own cell, held by a player, may be named.
		for cell in Level.rect_cells(bier.grow(4)):
			if not World.is_walkable(cell):
				continue
			var picked: Vector2i = _main.altar_beside(bier, cell)
			var holder: GridEntity = World.get_entity_at(picked) if picked != Main.NONE else null
			if picked == knight.tile or holder != null and not (picked == cell and holder is Player):
				on_him.append(cell)
	_check(bier.has_area() and knight != null and World.get_entity_at(knight.tile) == knight and on_him.is_empty(),
		"from any cell near the bier, the cell to lay from is never the knight's (%s, from %s)" % [knight.tile if knight != null else World.NO_CELL, on_him])
	# A click on the bier sends with any holy knight's remains in the pack,
	# not only the quest's ready step (playtest's look_circle: a later run's
	# or a brother's were never sent, nor refused aloud).
	var walker := _player()
	if walker != null and bier.has_area():
		var stand: Vector2i = _main.altar_beside(bier, walker.tile)
		_put(walker, stand)
		var had_quest: Dictionary = walker.quest
		walker.quest = {}
		_drop_relics(walker)
		var bare: bool = _main._altar_click(walker, Vector2i(38, 8))
		var brother: int = World.mint_relic("Sir Ansel the Faithful", 0, walker)
		World.into_pack(walker, brother)
		var carrying: bool = _main._altar_click(walker, Vector2i(38, 8))
		_check(not bare and carrying, "a click on the bier: with nothing to lay it walks; with a brother's remains in the pack, no quest ready, it asks the server (%s, %s)" % [bare, carrying])
		_drop_relics(walker)
		walker.quest = had_quest
	_main.load_map("test_room")


## The knight's thanks charges the amulet (896 amended (1), Jeff's answer):
## off the quest the altar takes any holy knight's remains a player carries,
## his own again or a brother's, charges by their tier and says which; an
## amulet that can hold no more, or one never blessed, keeps them; remains
## won unpaid are laid with no charge; the hidden way is the player's on the
## altar step; a record saved on that step keeps it.
func _test_altar_charges() -> void:
	print("\n== the knight's altar charges the amulet (896 amended (1)) ==")
	var player := _player()
	var id := player.player_id
	var record: PlayerRecord = _main._records.get(id)
	if record == null:
		_check(false, "no record for the test player")
		return
	var kept := {"marks": record.marks.duplicate(), "task": record.barrow_task.duplicate(true), "barrow": record.barrow.duplicate(true)}
	_main.load_map("test_room")
	_main.travel(Net.local_id, "barrow", "")
	await get_tree().process_frame
	player = _player()
	var bier: Rect2i = _main.knights_altar("barrow")
	var knight: AstralKnight = null
	for entity in World.get_entities():
		if entity is AstralKnight:
			knight = entity
	var said: Array[String] = []
	var hear := func(words: String) -> void: said.append(words)
	if knight == null or not bier.has_area():
		_check(false, "the knight and his bier in the barrow (%s)" % [bier])
		return
	knight.said.connect(hear)
	_put(player, _main.altar_beside(bier, player.tile))
	_drop_relics(player)
	var deals := Economy.deals(_main._field_rules())
	record.barrow = {"best": str(deals[0].get("name", "")), "containers": []}  # Blessed once: room on the amulet.
	_main.mark_player(id, Main.QUEST_DONE)
	record.barrow_task = {}
	_main.altar_turn_in = true
	var sir: String = _main.barrow_knight()
	var own := sir if not sir.is_empty() else "Sir Test"
	var charges := func() -> int: return World.totem_charges(World.totem_of(id))
	var lay := func(name: String, tier: int) -> int:
		var uid := World.mint_relic(name, tier, player)
		World.into_pack(player, uid)
		said.clear()
		_main._on_command(player, "altar", {"at": [bier.position.x, bier.position.y]})
		return uid
	var before: int = charges.call()
	var uid: int = lay.call(own, 0)
	_check(not player.slot_items.has(uid) and charges.call() > before and said == [AstralKnight.LAID_AGAIN] and Main.QUEST_DONE in record.marks,
		"a later run, his own remains: laid, the amulet charged, his thanks again (%s, %d -> %d)" % [said, before, charges.call()])
	_check(_heard.slice(-1) == ["You lay %s's remains on the bier." % own]
		and _main.party_log.last(1) == ["%s lays %s's remains on the bier." % [_main._display_name(player), own]],
		"the party line names his remains, on the bier (voice): to the layer and in the log (%s, %s)" % [_heard.slice(-1), _main.party_log.last(1)])
	before = charges.call()
	uid = lay.call("Sir Brother of the Test", 0)
	_check(not player.slot_items.has(uid) and charges.call() > before and said == [Main.laid_words(false, 1, 0, "Sir Brother of the Test", sir)],
		"an earlier generation's knight: taken, charged, his thanks by whose they are (%s)" % [said])
	_check(_heard.slice(-1) == ["You lay Sir Brother of the Test's remains on the bier."]
		and _main.party_log.last(1) == ["%s lays Sir Brother of the Test's remains on the bier." % _main._display_name(player)],
		"a brother's: the party line names the remains laid, not the generation's knight (%s)" % [_heard.slice(-1)])
	_check(AstralKnight.laid_whose("") == "a brother knight's" and AstralKnight.laid_whose("Sir Ansel the Faithful") == "Sir Ansel the Faithful's",
		"remains with no name read as a brother knight's (voice)")
	_check(Main.laid_words(false, 1, 0, "Sir Brother of the Test", "Sir Own") == AstralKnight.LAID_BROTHER
		and Main.laid_words(false, 1, 0, "Sir Own", "Sir Own") == AstralKnight.LAID_AGAIN and Main.laid_words(false, 0, -1, "Sir Own", "Sir Own") == AstralKnight.LAID_NO_BLESSING
		and Main.laid_words(true, 3, 0, "Sir Own", "Sir Own") == AstralKnight.LAID_QUEST and Main.laid_words(true, 0, 0, "Sir Own", "Sir Own") == AstralKnight.LAID,
		"his words by whose remains: a brother's when a generation names another knight, his own again, unpaid, the quest's charged or not")
	World.totem_add(World.totem_of(id), 1000, Economy.barrow_capacity(record.barrow, _main._field_rules()))  # Full.
	before = charges.call()
	uid = lay.call(own, 0)
	_check(player.slot_items.has(uid) and charges.call() == before and said == [AstralKnight.LAID_FULL],
		"an amulet that holds no more: kept, nothing laid, he says why (%s)" % [said])
	World.consume(player, uid, "test")
	record.barrow = {}  # Never blessed (or a quest reset).
	uid = lay.call(own, 0)
	_check(player.slot_items.has(uid) and said == [AstralKnight.LAID_UNBLESSED], "never blessed below: kept, he says why (%s)" % [said])
	World.consume(player, uid, "test")
	before = charges.call()
	uid = lay.call(own, Main.RELIC_UNPAID)
	_check(not player.slot_items.has(uid) and charges.call() == before and said == [AstralKnight.LAID_NO_BLESSING],
		"remains won unpaid: laid though never blessed, no charge, no blessing on them (%s)" % [said])
	_main.altar_turn_in = false
	uid = lay.call(own, 0)
	_check(player.slot_items.has(uid) and said.is_empty(), "off: the bier takes nothing")
	_main.altar_turn_in = true
	World.consume(player, uid, "test")
	# The hidden way on the altar step, and the step kept by a save.
	var robbers_zone := str(World.economy.rules.get("robbers", {}).get("barrow", "")) if World.economy != null else ""
	_main.mark_player(id, Main.QUEST_DONE, false)
	record.barrow_task = {"taken": true, "step": "altar"}
	_check(robbers_zone.is_empty() or _main.way_revealed(id, robbers_zone), "turned in, his remains still below: the hidden way is theirs (way_revealed)")
	var back := PlayerRecord.from_dict(record.to_dict())
	_check(str(back.barrow_task.get("step", "")) == "altar" and bool(back.barrow_task.get("taken", false)),
		"a record saved on the altar step loads on it (%s)" % [back.barrow_task])
	record.barrow_task = {"taken": true, "slain": []}
	_check(robbers_zone.is_empty() or not _main.way_revealed(id, robbers_zone), "taken, not turned in: not yet")
	var saved := record.to_dict()
	saved["barrow_task"] = {"taken": true, "slain": ["7"]}  # As a record before 896 amended (1) was saved.
	back = PlayerRecord.from_dict(saved)
	_check(back.barrow_task == {"taken": true, "slain": ["7"]}, "a record saved before the change, mid-quest, loads as it was (%s)" % [back.barrow_task])
	knight.said.disconnect(hear)
	record.marks.assign(kept["marks"])
	record.barrow_task = kept["task"]
	record.barrow = kept["barrow"]
	_main._sync_quest(record)
	_main.load_map("test_room")


## The knight's altar in the barrow itself (896, "full circle"): the bier
## he stands by is the First Hall's (38-40 by 8-9); off, a click on it lays
## nothing; on, from beside it with his remains, it is laid there and the
## quest is done.
func _test_knights_altar() -> void:
	print("\n== the knight's altar: his remains laid on the First Hall's bier (896) ==")
	var player := _player()
	var id := player.player_id
	var record: PlayerRecord = _main._records.get(id)
	if record == null:
		_check(false, "no record for the test player")
		return
	var kept := {"marks": record.marks.duplicate(), "task": record.barrow_task.duplicate(true)}
	_main.load_map("test_room")
	_main.travel(Net.local_id, "barrow", "")
	await get_tree().process_frame
	player = _player()
	var bier: Rect2i = _main.knights_altar("barrow")
	var knight: AstralKnight = null
	for entity in World.get_entities():
		if entity is AstralKnight:
			knight = entity
	var was_laid := knight != null and knight.remains_laid
	_check(bier == Rect2i(38, 8, 3, 2), "the altar is the bier the knight stands by, 38-40 by 8-9 (%s)" % [bier])
	_main.mark_player(id, Main.QUEST_DONE, false)
	record.barrow_task = {"taken": true, "step": "altar"}
	var sir: String = _main.barrow_knight()
	_drop_relics(player)
	var relic := World.mint_relic(sir if not sir.is_empty() else "Sir Test", 0, player)
	World.into_pack(player, relic)
	var beside: Vector2i = _main.altar_beside(bier, player.tile)
	_check(beside != Main.NONE and not bier.has_point(beside) and World.is_walkable(beside), "a free cell beside the bier to stand on (%s)" % [beside])
	_put(player, beside)
	_main.altar_turn_in = false
	_main._on_command(player, "altar", {"at": [38, 8]})
	_check(_main.knights_relic_slot(player) >= 0 and not (Main.QUEST_DONE in record.marks), "off: a click on the bier lays nothing")
	_main.altar_turn_in = true
	_main._on_command(player, "altar", {"at": [38, 8]})
	_check(_main.knights_relic_slot(player) < 0 and Main.QUEST_DONE in record.marks and record.barrow_task.is_empty() and player.quest.is_empty(),
		"on, from beside it with his remains: laid, the quest done, the card closed (%s, %s)" % [beside, record.barrow_task])
	_check(not was_laid and knight != null and knight.remains_laid, "and his remains lie on the bier for the generation (remains_laid, for art-kit's piece)")
	# Kept through a restart: in the level's regen state, which a save keeps
	# and a new generation replaces; a knight made again there is laid.
	var regen_state: Dictionary = _main._regen.get("barrow", _main._plain_band_slain)
	var round_trip: Dictionary = Regen.states_from(JSON.parse_string(JSON.stringify({"barrow": regen_state})))
	var again: AstralKnight = null
	if knight != null:
		var spec: Dictionary = knight.spawn_spec.duplicate(true)
		(spec.get_or_add("props", {}) as Dictionary).erase("remains_laid")
		spec["tile"] = knight.tile
		World.despawn(knight)
		await get_tree().process_frame
		again = _main._spawn(spec) as AstralKnight
	_check(_main.remains_laid_in("barrow") and bool(round_trip.get("barrow", {}).get("remains_laid", false)) and again != null and again.remains_laid,
		"and through a restart: the level's state keeps them through a save, and the knight made again there has them laid")
	if _main._regen.has("barrow"):
		_main._regen["barrow"].erase("remains_laid")
	_main._plain_band_slain.erase("remains_laid")
	_main.altar_turn_in = true
	record.marks.assign(kept["marks"])
	record.barrow_task = kept["task"]
	_main._sync_quest(record)
	_main.load_map("test_room")


## Every relic off [param player] (896's cases): only the one a case mints is theirs to lay.
func _drop_relics(player: Player) -> void:
	for slot in player.slots.size():
		var uid := World.slot_uid(player, slot)
		if not World.relic_of(uid).is_empty():
			World.consume(player, uid, "test")
