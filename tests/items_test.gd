extends Node
## Items: the catalog reads every definition from levels/items.json and
## refuses what makes no sense; an ItemBook keeps each instance's carriers
## (time held counted as they let go) and at most five events (where it
## came from kept); in the game a level chest's kit gets its instance when
## first taken, "found" by its first carrier, "given" from one carrier to
## another (a companion moves things as a player does), taken out of and
## put back into slots (the stockpile's way); a restart keeps every
## instance and its history; a save from before instances gets new ones
## ("migrated"); a rebuilt room ends what its chests held as lost; nothing
## leaks from the book.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const BO := 2
const BO_ID := "b0b0b0b0-0000-4000-8000-0000000000c1"
const KIT := "bandaging_kit"

var _failures := 0
var _main: Node


func _ready() -> void:
	World.set_process(false)
	Net.port = preload("res://tests/test_ports.gd").of(17799)
	Net.companions = false
	Net.state_path = preload("res://tests/test_ports.gd").scratch_path("items_test_world.json")
	if FileAccess.file_exists(Net.state_path):
		DirAccess.remove_absolute(Net.state_path)

	_test_catalog()
	_test_book()
	_test_leather()

	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	for i in 3:
		World.step()
	_test_found_and_held()
	_test_given()
	_test_take_and_put()
	_test_hands()
	_test_ground()
	_test_throw()
	_test_containers()
	_test_bandage()
	_test_icons()
	_test_use()
	_test_buffs()
	_test_weapons()
	_test_blows()
	_test_block()
	_test_bash()
	_test_axe()
	_test_wind_up()
	_test_spear()
	_test_pickup()
	_test_kills()
	_test_bane()
	_test_style()
	_test_short()
	_test_bound()
	_test_gold_drop()
	_test_grave()
	_test_totem()
	_test_battle_axe()
	_test_cache()
	_test_stacks()
	_test_armour()
	_test_story()
	_test_bless()
	_test_reforge()
	_test_names()
	_test_curse()
	_test_arrows()
	_test_loot()
	_test_remedy_heal()  # After the timed checks: its 400 ticks would shift them.
	_test_bandage_reach()  # So too its ticks.
	_test_inventory()
	await _test_restart()
	await _test_migration()
	_test_rebuild()

	DirAccess.remove_absolute(Net.state_path)
	Net.state_path = ""
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_catalog() -> void:
	print("\n== the catalog ==")
	_check(not Items.ids().is_empty(), "levels/items.json has %d items" % Items.ids().size())
	var bad := []
	for id: String in Items.ids():
		var item := Items.def(id)
		if item["name"].is_empty() or item["weight"] <= 0.0 or not item["art"].begins_with("item.") \
				or item["hands"] not in [0, 1, 2] or item["kind"] not in ["held", "cell"]:
			bad.append(id)
		if "resource" in item["tags"] and Items.yield_of(id).is_empty():
			bad.append(id + " (a resource yielding nothing)")
	_check(bad.is_empty(), "each has a name, a weight, an item.<id> art slot, hands and a kind (%s)" % [bad])
	_check(Items.name_of(KIT) == "bandaging kit" and Items.short_of(KIT) == "Bandages" and Items.def(KIT)["use"] == "bandage",
			"the bandaging kit is as it was, used to bandage")
	_check(Items.yield_of("ore_sack") == {"ore": 5} and Items.yield_of(KIT).is_empty(), "a sack of ore banks as 5 ore; a kit as nothing")
	_check(Items.tidy([KIT, "no_such_thing"], 3) == PackedStringArray([KIT, "", ""]), "an unknown id is dropped from slots")
	var unknown_drops := []
	for kind: String in Monster.kinds():
		for drop: Variant in Monster.kinds()[kind]["drops"]:
			if not Items.exists(str(drop.get("item", ""))):
				unknown_drops.append("%s: %s" % [kind, drop])
	_check(unknown_drops.is_empty(), "every monster's drops name a thing in the catalog (%s)" % [unknown_drops])
	_check(Items.yield_of("meat") == {"meat": 1} and Items.value_of("antlers") == 5, "meat banks as meat (decision 405); antlers are worth 5")
	var generated: Variant = JSON.parse_string(FileAccess.get_file_as_string(Items.ART_SLOTS)) if FileAccess.file_exists(Items.ART_SLOTS) else null
	_check(generated is Dictionary and generated == JSON.parse_string(JSON.stringify(Items.art_slots())),
			"%s is current with the catalog (else: tools/items_art_slots.gd)" % Items.ART_SLOTS)
	_check(Items.art_slots()["slots"]["item.wood_bundle"]["sockets"].has("grip_2") \
			and not Items.art_slots()["slots"]["item.bandaging_kit"]["sockets"].has("grip_2"), "two hands, two grips")
	var made := Items.read(JSON.stringify({"items": [
		{"id": "sword", "name": "sword", "made": {"by": "smith", "from": {"ore": 3, "wood": 1}, "steps": 3000}},
		{"id": "fine_sword", "name": "fine sword", "made": {"by": "smith", "rework": "sword", "steps": 1500}},
		{"id": "odd", "name": "odd", "made": {"by": "baker", "from": {"ore": 1}, "steps": 10}},
		{"id": "odder", "name": "odder", "made": {"by": "smith", "from": {"moonbeams": 1}, "steps": 10}}]}))
	_check(made["sword"]["made"] == {"by": "smith", "from": {"ore": 3, "wood": 1}, "steps": 3000}
			and made["fine_sword"]["made"]["rework"] == "sword", "made: a sword from ore and wood by a smith; a fine one reworked from it")
	_check(made["odd"]["made"].is_empty() and made["odder"]["made"].is_empty(), "made by no trade, or from nothing known: left out")
	Items.add_for_test({"id": "test_sword", "name": "test sword", "hands": 1})
	_check(Items.exists("test_sword"), "a test can add a thing")
	Items.reset()
	_check(not Items.exists("test_sword") and Items.exists(KIT), "and reset brings back the catalog alone")
	var read := Items.read('{"items": [{"id": "a", "name": "A", "weight": 2}, {"name": "no id"}, {"id": "a", "name": "again"}]}')
	_check(read.keys() == ["a"] and read["a"]["name"] == "A" and read["a"]["hands"] == 1,
			"a catalog with an entry with no id and an id twice: the first a, filled in (%s)" % [read.keys()])


func _test_leather() -> void:
	print("\n== leather's uses: bundles mended by the carpenter, the tanner's buckler (decision 413) ==")
	var mend := {"by": "fletcher", "from": {"leather": 1, "wood": 1}, "steps": 600}
	_check(["arrows", "flame_arrows", "barbed_arrows"].all(func(id: String) -> bool: return Items.mend_of(id) == mend),
			"every bundle is mended by the carpenter from leather and wood (%s)" % Items.mend_of("arrows"))
	_check(Items.mend_of("sword").is_empty(), "a sword has no mend")
	var buckler := Items.verb_of("buckler")
	_check(buckler.get("kind") == "block" and buckler.get("arc") == 0 and buckler.get("absorb") == 0.75 and buckler.get("stamina") == 6
			and buckler.get("breaks_at") == 1.5 and buckler.get("bash_force") == 1.0 and Items.weight_of("buckler") == 1.5,
			"a buckler: straight ahead only, takes three quarters, 6 stamina, breaks at 1.5, a light bash; 1.5 kg (%s)" % buckler)
	_check(Items.def("buckler")["made"] == {"by": "tanner", "from": {"leather": 2, "wood": 1}, "steps": 1800}
			and "shield" in Items.def("buckler")["tags"], "made by the tanner from leather and wood, a shield the town wants")


func _test_book() -> void:
	print("\n== a book's history ==")
	var now := [100]
	var book := ItemBook.new(func() -> int: return now[0])
	var uid := book.mint("sword", "stocked", "Chest1", "castle", Vector2i(3, 4))
	_check(book.id_of(uid) == "sword" and book.history(uid)["events"][0]["kind"] == "stocked", "made, stocked in a chest")
	book.place(uid, "player:a", "player:a", "Ann")
	now[0] = 160
	_check(book.held_by(uid, "player:a") == 60, "Ann has held it 60 steps so far (%d)" % book.held_by(uid, "player:a"))
	book.place(uid, "castle/Chest1")
	now[0] = 500
	_check(book.held_by(uid, "player:a") == 60, "in the chest, her time stops")
	book.place(uid, "player:a", "player:a", "Ann")
	now[0] = 510
	_check(book.held_by(uid, "player:a") == 70 and book.history(uid)["carriers"].size() == 1, "back with her, one row, 70")
	for i in 9:
		book.place(uid, "player:%d" % i, "player:%d" % i, "P%d" % i)
		now[0] += 10 + i
	var carriers: Array = book.history(uid)["carriers"]
	_check(carriers.size() == ItemBook.MAX_CARRIERS and carriers.any(func(row: Dictionary) -> bool: return row["who"] == "player:8"),
			"ten carriers: the %d who held it longest are kept, with who has it now" % ItemBook.MAX_CARRIERS)
	_check(not carriers.any(func(row: Dictionary) -> bool: return row["who"] == "player:0"), "the one who held it least is gone")
	for i in 6:
		book.note(uid, "felled", "goblin %d" % i, "castle", Vector2i(i, 0))
	var events: Array = book.history(uid)["events"]
	_check(events.size() == ItemBook.MAX_EVENTS and events[0]["kind"] == "stocked" and events[-1]["what"] == "goblin 5" \
			and events[1]["what"] == "goblin 2", "six more events: five kept, where it came from and the newest four")
	var copy := ItemBook.from_dict(JSON.parse_string(JSON.stringify(book.to_dict())), func() -> int: return now[0])
	_check(copy.history(uid) == book.history(uid), "saved and read back as JSON, the same")
	var other := copy.mint("ore_sack", "built")
	_check(other > uid, "and new uids go on from the saved ones (%d)" % other)
	var last := copy.end(other, "banked", "stockpile")
	_check(not copy.has(other) and last["events"][-1]["kind"] == "banked", "banked: gone from the book, its last event banked")
	_check(copy.orphans([uid]).is_empty() and copy.orphans([]) == [uid], "orphans: none when every holder is counted")


func _test_found_and_held() -> void:
	print("\n== a chest's kit: found, and held ==")
	var chest := _chest()
	var host := _player(Net.local_id)
	_check(chest.slots[0] == KIT and (chest.slot_items.is_empty() or chest.slot_items[0] == 0),
			"the chest's kit has no instance until it is needed")
	_beside(host, chest)
	_check(World.try_transfer(host, chest, 0, host, 0), "the host takes it")
	var uid := host.slot_items[0]
	var history := World.items.history(uid)
	_check(uid != 0 and World.items.id_of(uid) == KIT, "it is an instance now (%d)" % uid)
	_check(history["events"].size() == 2 and history["events"][0]["kind"] == "stocked" and history["events"][1]["kind"] == "found",
			"stocked in the chest, found by the host (%s)" % [history["events"]])
	_check(history["carriers"][0]["who"] == "player:" + Net.player_id and history["at"] == "player:" + Net.player_id,
			"the host carries it, and it is with them")
	World.steps += 100
	_check(World.items.held_by(uid, "player:" + Net.player_id) == 100, "100 steps on, they have held it 100")
	World.try_transfer(host, host, 0, chest, 2)
	World.steps += 40
	_check(World.items.held_by(uid, "player:" + Net.player_id) == 100 and World.items.at_of(uid) == "%s/%s" % [chest.zone, chest.name],
			"back in the chest: it is there, and their time stops")
	World.try_transfer(host, chest, 2, host, 0)
	_check(host.slot_items[0] == uid and World.items.history(uid)["events"].size() == 2, "taken again: the same thing, not found again")


func _test_given() -> void:
	print("\n== given from one carrier to another; a companion does as a player does ==")
	Net.companions = true
	var host := _player(Net.local_id)
	var record: PlayerRecord = _main._records[Net.player_id]
	_main._join_companion(record, host)
	var pet: Companion = _main._companions.get(Net.player_id)
	var uid := host.slot_items[0]
	_check(World.try_transfer(host, host, 0, pet, 1), "the host gives the kit to %s" % pet.name)
	var events: Array = World.items.history(uid)["events"]
	_check(events[-1]["kind"] == "given" and pet.name in str(events[-1]["what"]), "given, to her (%s)" % [events[-1]])
	_check(Array(record.companion.get("items", [])) == [0, uid, 0, 0, 0, 0, 0, 0, 0, 0, 0], "her player's record has its instance")
	World.steps += 20
	_check(World.try_transfer(pet, pet, 1, host, 3), "she hands it back herself")
	_check(World.items.held_by(uid, World.holder_key(pet)) == 20 and host.slot_items[3] == uid, "she held it 20 steps; the host has it")
	_print_history(uid)
	_main._admit(BO, BO_ID, "Bo")
	var bo := _player(BO)
	_check(not World.try_transfer(pet, pet, 0, bo, 0) and not World.reaches(pet, bo), "she cannot reach into Bo's pack")
	_main._leave(BO, bo, BO_ID)


func _test_take_and_put() -> void:
	print("\n== taken out of slots and put back (the stockpile's way) ==")
	var host := _player(Net.local_id)
	var uid := host.slot_items[3]
	_check(World.take_item(host, host, 3) == uid and host.slots[3] == "" and host.slot_items[3] == 0, "taken out: the slot is empty")
	_check(World.items.has(uid) and World.items.at_of(uid) == "", "and it is still in the book, nowhere yet")
	_check(not World.put_item(host, host, 3, 999999), "an unknown thing cannot be put anywhere")
	_check(World.put_item(host, host, 1, uid) and host.slots[1] == KIT and host.slot_items[1] == uid, "put back, in slot 2")
	_check(World.take_item(host, host, 0) == 0, "nothing to take from an empty slot")


func _test_hands() -> void:
	print("\n== two hands: what can be held, and how; what is carried weighs ==")
	var host := _player(Net.local_id)
	var base := host.mass if host.base_mass < 0.0 else host.base_mass
	_check(host.slots[1] == KIT and host.slots.size() == Player.SLOTS, "a pack of 4, two hands and the armour slot; the kit in the pack")
	_check(World.try_transfer(host, host, 1, host, Player.RIGHT_HAND), "the kit goes into the right hand")
	_check(World.try_transfer(host, host, Player.RIGHT_HAND, host, Player.LEFT_HAND) and host.slots[Player.LEFT_HAND] == KIT,
			"and from one hand to the other")
	var wood := _give(host, "wood_bundle", 0)
	_check(host.slots[0] == "wood_bundle", "a bundle of wood (two-handed) in the pack")
	_check(not World.try_transfer(host, host, 0, host, Player.RIGHT_HAND), "it cannot go in the right hand while the left holds the kit")
	World.try_transfer(host, host, Player.LEFT_HAND, host, 1)
	_check(not World.try_transfer(host, host, 0, host, Player.LEFT_HAND), "nor ever in the left")
	_check(World.try_transfer(host, host, 0, host, Player.RIGHT_HAND), "the hands empty, it goes in the right")
	_check(not World.try_transfer(host, host, 1, host, Player.LEFT_HAND), "and the left takes nothing while it is held")
	Items.add_for_test({"id": "test_boulder", "name": "boulder", "weight": 50, "hands": 0})
	_give(host, "test_boulder", 2)
	_check(not World.try_transfer(host, host, 2, host, Player.LEFT_HAND) and World.free_slot_for(host, "test_boulder") == 0,
			"a thing for the pack alone goes in no hand")
	_check(is_equal_approx(host.mass, base + 8.0 + 0.5 + 50.0), "carried, they weigh: %.1f = %.1f + 8 + 0.5 + 50" % [host.mass, base])
	World.items.end(World.take_item(host, host, 2), "gone")
	Items.reset()
	_check(is_equal_approx(host.mass, base + 8.5), "set down, the weight goes (%.1f)" % host.mass)
	_check(host.slot_items[Player.RIGHT_HAND] == wood, "the wood in the right hand is the same thing")


func _test_ground() -> void:
	print("\n== put down and picked up; the ground keeps four a cell ==")
	var host := _player(Net.local_id)
	var cell := host.tile
	var wood := host.slot_items[Player.RIGHT_HAND]
	_check(World.try_drop(host, Player.RIGHT_HAND), "the host puts the wood down")
	_check(World.ground_at(cell) == PackedStringArray(["wood_bundle"]) and host.slots[Player.RIGHT_HAND] == "",
			"it lies at their feet (%s)" % [World.ground_at(cell)])
	var pile: GroundPile = World.zone.piles.get(cell)
	_check(is_instance_valid(pile) and pile.ids == PackedStringArray(["wood_bundle"]) and pile.zone == World.zone.name,
			"a pile is there to be seen")
	var was_mode: Net.Mode = Net.mode
	Net.mode = Net.Mode.CLIENT
	var seen := World.ground_at(cell)
	World.zone.ground.erase(cell)
	var seen_bare := World.ground_at(cell)
	Net.mode = was_mode
	World.zone.ground[cell] = PackedInt32Array([wood])
	_check(seen == PackedStringArray(["wood_bundle"]) and seen_bare == seen,
			"a client, with no Zone.ground, reads the pile: its hover says F pick up (Jeff's deer remains, v0.1.150) (%s)" % [seen])
	_check(World.items.at_of(wood) == "%s@%d,%d" % [World.zone.name, cell.x, cell.y] and World.items.history(wood)["holder"] == "",
			"the wood knows where it lies, carried by nobody")
	var host_mass := host.mass
	_check(World.try_pick_up(host, cell) and host.slot_items[Player.RIGHT_HAND] == wood, "picked up again: into the right hand")
	_check(not World.zone.piles.has(cell) and World.ground_at(cell).is_empty(), "and the ground is bare")
	_check(host.mass > host_mass, "it weighs again")
	World.try_drop(host, Player.RIGHT_HAND)
	var kits: Array[int] = []
	for i in 4:
		var uid := World.items.mint("knife", "built")  # Things that don't stack (decision 619).
		kits.append(uid)
		World.put_on_ground(uid, cell)
	_check(World.ground_at(cell).size() == World.GROUND_PER_CELL, "four things on one cell (%s)" % [World.ground_at(cell)])
	var spilt := World.items.at_of(kits[-1])
	_check(spilt != "%s@%d,%d" % [World.zone.name, cell.x, cell.y] and spilt.begins_with(World.zone.name + "@"),
			"the fifth spills to a cell beside (%s)" % spilt)
	var far := cell + Vector2i(3, 0)
	_check(not World.try_pick_up(host, far) and not World.try_drop(host, 1, far), "nothing picked up or put down three cells off")
	for i in 3:
		World.items.end(World.take_from_ground(cell, World.ground_uids(cell).size() - 1), "gone")
	var left := World.ground_uids(cell)
	_check(left.size() == 1 and left[0] == wood, "the wood is left there (%s)" % [World.ground_at(cell)])
	for each: Vector2i in World.zone.ground.keys():
		if each != cell:
			while not World.ground_uids(each).is_empty():
				World.items.end(World.take_from_ground(each, 0), "gone")


func _test_throw() -> void:
	print("\n== thrown: as far as strength and weight allow, and a body hit feels it ==")
	var host := _player(Net.local_id)
	World._relocate(host, _open_line(host, 1))
	World.try_transfer(host, host, 1, host, Player.RIGHT_HAND)
	var kit := host.slot_items[Player.RIGHT_HAND]
	var reach := World.throw_reach(host, KIT)
	_check(reach >= 4 and World.throw_reach(host, "ore_sack") <= 2, "a kit goes %d cells, a sack of ore %d" % [reach, World.throw_reach(host, "ore_sack")])
	var target := _open_line(host, 3)
	_check(target != World.NO_CELL, "three free cells in a line from the host (to %s)" % target)
	var from := host.tile
	_check(World.try_throw(host, Player.RIGHT_HAND, target) and World.items.at_of(kit) == "%s@%d,%d" % [World.zone.name, target.x, target.y],
			"the kit lands on the cell aimed at (%s)" % World.items.at_of(kit))
	var pile: GroundPile = World.zone.piles.get(target)
	_check(is_instance_valid(pile) and pile.thrown_from == from, "its pile says where it was thrown from")
	_check(not World.try_throw(host, 1, target), "nothing is thrown from the pack")
	World._relocate(host, target)
	World.try_pick_up(host, target)
	World.try_transfer(host, host, Player.RIGHT_HAND, host, 1)
	_main._admit(BO, BO_ID, "Bo")
	var bo := _player(BO)
	var beside := _open_line(host, 1)
	World._relocate(bo, beside)
	var ore := _give(host, "ore_sack", 0)
	World.try_transfer(host, host, 0, host, Player.RIGHT_HAND)
	var hp := bo.hp
	_check(World.try_throw(host, Player.RIGHT_HAND, beside + (beside - host.tile) * 3), "the host throws a sack of ore at Bo, beside them")
	_check(bo.hp < hp and World.is_stunned(bo), "Bo is hurt (%d to %d) and staggered" % [hp, bo.hp])
	_check(World.items.history(ore)["events"][-1]["kind"] == "thrown" and World.ground_uids(host.tile).has(ore),
			"the sack fell at the host's feet, its history says thrown at Bo")
	World.items.end(World.take_from_ground(host.tile, World.ground_uids(host.tile).find(ore)), "gone")
	_main._leave(BO, bo, BO_ID)


func _test_containers() -> void:
	print("\n== crates and carts carry things: opened from beside, heavier full, spilling when broken ==")
	var host := _player(Net.local_id)
	var crate: GridEntity = null
	for entity in World.get_entities():
		if entity.name == "Crate1":
			crate = entity
	_check(crate is Cargo and crate.slots == PackedStringArray(["", "", "", ""]) and crate.pushable,
			"the test room's crate is a container of 4, empty, and still pushable")
	var spot := _open_line(host, 1)
	var cart := _main._spawn({"script": Level.CARGO, "shape": "slab", "name": "TestCart", "tile": spot,
		"props": {"capacity": 8, "mass": 60.0, "slots": [KIT, "ore_sack"]}}) as Cargo
	_check(cart != null and cart.slots.size() == 8 and cart.slots[0] == KIT and cart.slots[1] == "ore_sack",
			"a cart of 8, with a kit and a sack of ore in it from its props")
	_check(World.reaches(host, cart), "the host, beside it, reaches into it")
	var mass := cart.mass
	var kit := _give(host, KIT, 0)
	_check(World.try_transfer(host, host, 0, cart, 2) and cart.slot_items[2] == kit, "the host puts a kit in")
	_check(is_equal_approx(cart.mass, mass + 0.5) and World.items.history(kit)["holder"] == "",
			"the cart is heavier by it (%.1f), and carries it as a place, not a carrier" % cart.mass)
	var away := cart.tile + (cart.tile - host.tile) * 2
	if World.is_free(away):
		World._relocate(cart, away)
		_check(not World.reaches(host, cart) and cart.slot_items[2] == kit, "pushed off two cells, it is out of reach, the kit still in it")
		World._relocate(cart, spot)
	_main.pack_panel.player = host
	_main._e_target = cart
	_main._e_held = true
	_main._e_since = Time.get_ticks_msec()
	_main._release_e()
	_check(_main.pack_panel.other == cart and _main.pack_panel.title_shown(false) == "Cart",
			"a tap of E on it beside you opens it: \"%s\"" % _main.pack_panel.title_shown(false))
	_main.close_other()
	var held := cart.contents_uids()
	var at := cart.tile
	World.damage(cart, 1000, host, &"impact")
	var lying: Array = []
	for cell: Vector2i in World.zone.ground:
		lying.append_array(Array(World.ground_uids(cell)))
	_check(not is_instance_valid(cart) or not cart.spawned, "broken, the cart is gone")
	_check(held.size() == 3 and held.all(func(uid: int) -> bool: return uid in lying),
			"and what it held lies on the ground at %s, the same things (%s)" % [at, held])
	for uid: int in held:
		for cell: Vector2i in World.zone.ground.keys():
			var index := Array(World.ground_uids(cell)).find(uid)
			if index >= 0:
				World.items.end(World.take_from_ground(cell, index), "gone")
	var box := _main._spawn({"script": Level.CARGO, "shape": "cube", "name": "TestCrate", "tile": spot,
		"props": {"capacity": 4, "slots": [KIT]}}) as Cargo
	var emptied := World.empty_container(box)
	_check(emptied.size() == 1 and World.items.id_of(emptied[0]) == KIT and box.slots[0] == "" and World.items.at_of(emptied[0]) == "",
			"emptied at once (the stockpile's way): its kit's uid, the crate empty")
	World.items.end(emptied[0], "gone")
	World.despawn(box)


func _test_use() -> void:
	print("\n== using things: a key by carrying it, a purse opened into gold; thuds ==")
	var host := _player(Net.local_id)
	Items.add_for_test({"id": "test_key", "name": "cellar key", "weight": 0.1, "opens": "cellar", "value": 3})
	_check(Items.opens_of("test_key") == "cellar" and Items.value_of("test_key") == 3 and Items.value_of(KIT) == 0,
			"the catalog says what a key opens and what a thing is worth")
	_check(Items.read('{"items": [{"id": "x", "value": -2}]}')["x"]["value"] == 0, "a value under 0 is none")
	_check(not World.has_key(host, "cellar"), "no key: the cellar stays locked to the host")
	var slot := host.slots.find("")
	_give(host, "test_key", slot)
	_check(World.has_key(host, "cellar") and not World.has_key(host, "keep"), "carrying the cellar key opens the cellar, not the keep")
	_check(not World.try_use(host, slot), "a key is not used up or used: carrying it is enough")
	World.items.end(World.take_item(host, host, slot), "gone")
	_check(not World.try_use(host, slot), "an empty slot: nothing to use")
	var imp: Monster = World.monsters()[0] if not World.monsters().is_empty() else null
	if imp != null:
		var was := imp.tile
		World._relocate(imp, _free_near(host, 3))
		imp.senses.heard.clear()
		_give(host, "ore_sack", slot)
		World.try_drop(host, slot)
		var heard: Dictionary = imp.senses.heard.back() if not imp.senses.heard.is_empty() else {}
		_check(heard.get("kind") == &"thud", "a sack of ore put down: the imp hears a thud (%s)" % heard)
		World.try_pick_up(host, host.tile)
		World.items.end(World.take_item(host, host, host.slots.find("ore_sack")), "gone")
		World._relocate(imp, was)
	Items.reset()


func _test_buffs() -> void:
	print("\n== buffs: a ration eaten makes you heavier for a while; never below baseline ==")
	var host := _player(Net.local_id)
	var bad := Items.read('{"items": [{"id": "x", "effects": [{"kind": "mass", "amount": -5, "ticks": 10}, {"kind": "luck", "amount": 1, "ticks": 10}, {"kind": "wits", "amount": 2, "ticks": 10}]}]}')
	_check(bad["x"]["effects"].size() == 1 and bad["x"]["effects"][0]["kind"] == "wits",
			"effects that would lower you or raise nothing known are left out (%s)" % [bad["x"]["effects"]])
	var mass := host.mass
	var slot := host.slots.find("")
	_give(host, "ration", slot)
	var with_ration := host.mass
	_check(World.try_use(host, slot) and host.slots[slot].is_empty(), "the host eats the ration: gone")
	_check(is_equal_approx(host.mass, with_ration - 0.5 + 10.0), "fed: 10 kg heavier (%.1f to %.1f)" % [mass, host.mass])
	var imp_force_before := 0.0
	var imp: Monster = World.monsters()[0] if not World.monsters().is_empty() else null
	if imp != null:
		imp_force_before = World.push_force(imp, host)
		host.buffs = {}
		World._weigh(host)
		_check(World.push_force(imp, host) > imp_force_before, "and harder to shove: an imp's push %.3f fed, %.3f not" % [
			imp_force_before, World.push_force(imp, host)])
		World.add_buff(host, "mass", 10.0, 1800)
	var until: int = host.buffs["mass"][1]
	World.add_buff(host, "mass", 4.0, 3000)
	_check(host.buffs["mass"][0] == 10.0 and host.buffs["mass"][1] > until and is_equal_approx(host.mass, mass + 10.0),
			"a second, smaller meal does not add up: still +10, for longer")
	World.add_buff(host, "aura", 2.0, 5)
	_check(World.buff(host, "aura") == 2.0 and World.buff(host, "wits") == 0.0, "an aura buff is there to read (2), wits none")
	var faded: Array[String] = []
	var on_faded := func(entity: GridEntity, kind: String, state: StringName) -> void:
		if entity == host and state == &"faded":
			faded.append(kind)
	World.buff_changed.connect(on_faded)
	_steps(6)
	_check(faded == ["aura"] and World.buff(host, "aura") == 0.0 and host.buffs.has("mass"), "the aura wears off first (%s)" % [faded])
	host.buffs = {"mass": [host.buffs["mass"][0], World.tick + 1]}  # Its time up next tick.
	_steps(2)
	_check(faded.has("mass") and host.buffs.is_empty() and is_equal_approx(host.mass, mass),
			"then the meal: back to baseline, not below (%.1f)" % host.mass)
	World.buff_changed.disconnect(on_faded)
	_test_stamina_potion()


func _test_stamina_potion() -> void:
	print("\n== the stamina potion: quicker steps, reset not added (decision 562) ==")
	var host := _player(Net.local_id)
	var potion := Items.def("stamina_potion")
	_check(potion.get("made", {}) == {"by": "medicine_man", "from": {"herbs": 3}, "steps": 600, "stock": 3}
			and Items.effects_of("stamina_potion", potion.get("effects", [])) == [{"kind": "speed", "amount": 0.25, "ticks": 18000}],
			"made by the medicine man from 3 herbs, a shelf of 3; +25%% for 30 minutes (%s)" % [potion.get("effects")])
	var had := host.buffs.duplicate(true)
	host.buffs = {}
	var plain := World.step_ticks(host, Vector2i.RIGHT)
	var slot := host.slots.find("")
	_give(host, "stamina_potion", slot)
	_check(World.try_use(host, slot) and host.slots[slot].is_empty(), "drunk from the pack: gone")
	_check(is_equal_approx(World.step_ticks(host, Vector2i.RIGHT), plain / 1.25), "a step 25%% quicker (%.3f from %.3f)" % [World.step_ticks(host, Vector2i.RIGHT), plain])
	var until: int = host.buffs["speed"][1]
	_steps(3)
	World.add_buff(host, "speed", 0.25, 18000)
	_check(World.buff(host, "speed") == 0.25 and int(host.buffs["speed"][1]) > until, "a second resets the time, not the amount (+25% still)")
	_check(Items.made_problem({"by": "medicine_man", "from": {"herbs": 1}, "steps": 1, "stock": 0}, {}) != "", "a shelf of none is refused")
	host.buffs = {"speed": [0.25, World.tick + 1]}
	_steps(2)
	_check(not host.buffs.has("speed") and is_equal_approx(World.step_ticks(host, Vector2i.RIGHT), plain), "then it fades: back to the plain pace")
	host.buffs = had
	_test_steadying_draught()


func _test_steadying_draught() -> void:
	print("
== the steadying draught: a narrower cone, not a longer reach (decision 642) ==")
	var host := _player(Net.local_id)
	var draught := Items.def("steadying_draught")
	_check(draught.get("made", {}) == {"by": "medicine_man", "from": {"herbs": 2, "antlers": 1}, "steps": 600, "stock": 3}
			and Items.effects_of("steadying_draught", draught.get("effects", [])) == [{"kind": "steady", "amount": 0.4, "ticks": 18000}],
			"made by the medicine man from 2 herbs and an antler, a shelf of 3; 40%% narrower for 30 minutes (%s)" % [draught.get("effects")])
	var had := host.buffs.duplicate(true)
	var right := host.slots[Player.RIGHT_HAND]
	host.buffs = {}
	if not right.is_empty():
		World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")
	_give(host, "bow", Player.RIGHT_HAND)
	host.raised = "draw"
	host.raised_tick = World.tick - 5
	var plain := World.spread_of(host)
	var range_plain := World.longest_range(host)
	var slot := host.slots.find("")
	_give(host, "steadying_draught", slot)
	_check(World.try_use(host, slot) and host.slots[slot].is_empty(), "drunk from the pack: gone")
	host.raised = "draw"  # Drinking lowers the bow; drawn again, the same hold.
	host.raised_tick = World.tick - 5
	_check(plain > 0.0 and is_equal_approx(World.spread_of(host), plain * 0.6),
			"the same hold's cone 40%% narrower (%.4f from %.4f)" % [World.spread_of(host), plain])
	_check(World.longest_range(host) == range_plain, "the reach unchanged (%d cells)" % range_plain)
	host.raised = ""
	_check(World.spread_of(host) == -1.0, "not drawing: no cone")
	World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")
	host.buffs = had


func _test_remedy_heal() -> void:
	print("
== the remedy heals over time: 20 hp in 20 s, through a hit, beside a bandage (decision 682) ==")
	var host := _player(Net.local_id)
	var remedy := Items.def("remedy")
	_check(Items.effects_of("remedy", remedy.get("effects", [])) == [{"kind": "heal", "amount": 1.0, "ticks": 200}]
			and Items.value_of("remedy") == 6 and remedy["made"] == {"by": "medicine_man", "from": {"herbs": 2}, "steps": 600, "stock": 3},
			"1 hp a second for 200 ticks; worth 6, a shelf of 3, still 2 herbs (%s)" % [remedy.get("effects")])
	var had := host.buffs.duplicate(true)
	var had_max := host.max_hp
	host.max_hp = 100  # Room to heal 20 and more (a player's own is 20).
	host.buffs = {}
	host.mending = 0  # No bandaging or mending left from the tests before.
	World._mending.erase(host)
	World._bandaging.erase(host)
	var had_tile := host.tile
	host.hp = host.max_hp - 50
	for ending: int in [0, 5]:  # Drunk on a tick ending in 0, then in 5: 20 hp either way (physics' check).
		while World.tick % 10 != ending:
			_steps(1)
		host.hp = host.max_hp - 50
		var slot := host.slots.find("")
		_give(host, "remedy", slot)
		_check(World.try_use(host, slot) and host.slots[slot].is_empty() and World.buff(host, "heal") == 1.0, "drunk from the pack: gone, healing")
		var lasted := 0
		while host.buffs.has("heal") and lasted < 400:
			_steps(1)
			lasted += 1
		_check(host.hp == host.max_hp - 30 and lasted == 200,
				"drunk on tick ...%d: 20 hp over its whole life, 200 ticks (%d hp, %d ticks)" % [ending, host.hp - (host.max_hp - 50), lasted])
	World.add_buff(host, "heal", 1.0, 200)
	_steps(50)
	var before := host.hp
	World.damage(host, 3)
	_check(host.buffs.has("heal") and host.hp == before - 3, "a hit takes its hp and the heal goes on")
	_steps(50)
	_check(host.hp == before - 3 + 5, "5 more in the next 50 ticks (%d)" % host.hp)
	host.hp = host.max_hp - 1
	_steps(30)
	_check(host.hp == host.max_hp, "never past full")
	host.hp = 0
	_steps(1)
	_check(not host.buffs.has("heal"), "death ends it")
	host.hp = host.max_hp - 40
	host.buffs = {}
	World.add_buff(host, "heal", 1.0, 200)
	World.add_buff(host, "heal", 1.0, 200)
	_check(World.buff(host, "heal") == 1.0, "a second only refreshes the time, not doubles the rate")
	_steps(int(World.BANDAGE_CALM_TICKS) + 1)
	var kit := _give(host, "bandaging_kit", 0) if host.slots[0].is_empty() else 0
	for cell: Vector2i in _main._terrain["floor"]:  # Somewhere no monster from the tests before is near.
		if World.bandage_refusal(host, host) != "not_safe":
			break
		if World.is_free(cell):
			World._relocate(host, cell)
	var why := World.bandage_refusal(host, host)
	var started := World.try_bandage(host, host)
	_steps(World.BANDAGE_TICKS + 1)
	_check(started and host.mending == 2, "a bandage done beside it: the heal breaks no bandage (started %s %s, mending %d)" % [started, why, host.mending])
	if kit != 0:
		World.items.end(World.take_item(host, host, 0), "gone")
	_check(Items.effect_value("effects.remedy.heal.amount") == 1.0 and Items.set_effect_value("effects.remedy.heal.ticks", 100)
			and Items.def("remedy")["effects"][0]["ticks"] == 100 and not Items.set_effect_value("effects.remedy.heal.amount", -1)
			and Items.effect_fields().any(func(row: Dictionary) -> bool: return row["path"] == "effects.remedy.heal.amount"),
			"F7 tunes the heal: effects.remedy.heal.amount and .ticks")
	Items.set_effect_value("effects.remedy.heal.ticks", 200)
	host.buffs = had
	host.mending = 0  # The bandage's mending, done with.
	World._mending.erase(host)
	World._relocate(host, had_tile)
	host.max_hp = had_max
	host.hp = host.max_hp


func _test_weapons() -> void:
	print("\n== weapons are verbs: seven in the catalog, each a verb, hands and a recipe ==")
	var kinds := {"hammer": "knockback", "sword": "block", "shield": "block", "giant_axe": "knockdown",
		"spear": "reach", "dagger": "backstab", "bow": "ranged"}
	for id: String in kinds:
		var verb := Items.verb_of(id)
		_check(verb.get("kind") == kinds[id] and verb.has("speed") and Items.def(id)["made"].get("by") == "smith",
				"%s: %s, %d-handed, %.1f kg, made by the smith (%s)" % [id, kinds[id], Items.def(id)["hands"], Items.weight_of(id), verb])
	_check(Items.def("giant_axe")["hands"] == 2 and Items.def("bow")["hands"] == 1, "the giant axe takes both hands; the bow one, its arrows the other (decision 375)")
	_check(Items.verb_of("dagger")["speed"] < 1.0 and Items.verb_of("giant_axe")["speed"] > 1.0 and Items.verb_of("spear")["cells"] == 2,
			"a dagger is quick, a giant axe slow, a spear hits two cells away")
	_check(Items.verb_of(KIT).is_empty() and Items.verb_of("knife").is_empty(), "a kit or a knife is no weapon verb")
	var odd := Items.read('{"items": [{"id": "a", "verb": {"kind": "smite"}}, {"id": "b", "verb": {"kind": "reach", "cells": -1, "glow": 2}}]}')
	_check(odd["a"]["verb"].is_empty() and odd["b"]["verb"]["cells"] == 2 and not odd["b"]["verb"].has("glow"),
			"an unknown verb is none; a bad number its default; an unknown key left out")
	var host := _player(Net.local_id)
	var right := host.slots[Player.RIGHT_HAND]
	var left := host.slots[Player.LEFT_HAND]
	_check(right.is_empty() and left.is_empty() and World.wielded(host) == "" and World.guard(host).is_empty(),
			"bare hands: no weapon, no guard")
	_give(host, "shield", Player.LEFT_HAND)
	_check(World.wielded(host) == "shield" and World.guard(host)["absorb"] == 1.0, "a shield alone: it is what guards")
	_give(host, "hammer", Player.RIGHT_HAND)
	_check(World.wielded(host) == "hammer" and World.guard(host)["kind"] == "block", "hammer and shield: fights with the hammer, guards with the shield")
	World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")
	_give(host, "sword", Player.RIGHT_HAND)
	_check(World.wielded(host) == "sword" and World.guard(host)["absorb"] == 1.0, "sword and shield: the sword, the shield's guard over the sword's")
	print("\n== the right button is the off hand: a shield raised, a bow drawn and loosed (decision 329) ==")
	_check(World.off_hand(host) == "block" and _main._raise_off_hand(host) and host.raised == "block",
			"with a shield in the left hand, the right button raises it (stance %s)" % host.raised)
	_main._lower_off_hand(host)
	_check(host.raised == "", "let go, it is lowered")
	_main._raise_off_hand(host)
	World.items.end(World.take_item(host, host, Player.LEFT_HAND), "gone")
	_check(host.raised == "" and World.off_hand(host) == "", "the shield out of the hand, the guard drops; a sword alone has no off hand")
	_check(not _main._raise_off_hand(host), "and the right button shoves as ever")
	World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")
	_give(host, "bow", Player.RIGHT_HAND)
	_check(World.off_hand(host) == "" and not World.try_stance(host, "draw"), "a bow without arrows: nothing to draw (decision 375)")
	_give(host, "arrows", Player.LEFT_HAND)
	var shots := []
	var shot := func(by: GridEntity, angle: float, step: int) -> void: shots.append([by, angle, step])
	World.loosed.connect(shot)
	_check(World.off_hand(host) == "draw" and World.try_stance(host, "draw") and host.raised == "draw", "a bow, and a bundle of arrows in the other hand: the right button draws it")
	host.raised_tick = World.tick - 2
	_check(World.range_of(host) == 0 and World.draw_step(host) == -1 and not World.try_loose(host, 0.0) and shots.is_empty() and host.raised == "",
			"let go before draw_min (3 ticks): no shot, the bow lowered")
	World.try_stance(host, "draw")
	var reached := []
	var stepped_to := []
	for drawn in [3, 5, 6, 9, 10, 14, 15, 20, 21, 26, 27, 60]:
		host.raised_tick = World.tick - drawn
		reached.append(World.range_of(host))
		stepped_to.append(World.full_range_of(host))
	_check(reached == [5, 5, 7, 7, 9, 9, 11, 11, 13, 13, 15, 15] and World.longest_range(host) == 15,
			"range by the hold (decisions 669, 669 amended (2)): 5 cells at 3 ticks, 7 at 6, full draw's 9 at 10, then the bands, 11 at 15, 13 at 21, 15 at 27, held there (%s)" % [reached])
	_check(stepped_to == [0, 0, 0, 0, 9, 9, 9, 9, 9, 9, 9, 9], "the full-strength edge shown from full draw on, at 9 cells (%s)" % [stepped_to])
	host.raised_tick = World.tick - 5
	_check(is_equal_approx(World.draw_of(host), 0.5), "drawn 5 ticks of full draw's 10: half the pull's pose (%.2f)" % World.draw_of(host))
	var cones := []
	for drawn in [0, 3, 5, 7, 9, 12, 18, 60]:
		host.raised_tick = World.tick - drawn
		cones.append(snappedf(rad_to_deg(World.spread_of(host)), 0.1))
	var cones_ok := true
	for i in cones.size():
		cones_ok = cones_ok and is_equal_approx(cones[i], [20.0, 20.0, 13.3, 8.5, 5.5, 4.0, 4.0, 4.0][i])
	_check(cones_ok, "the cone narrows with the draw (decisions 620, 669): 20 degrees till the first step (3 ticks), 10 at the second (6), 4 at full draw (10), lerped between, held at 4 past it (%s)" % [cones])
	var bow_verb := Items.verb_of("bow")
	var by_distance := []
	for away in [1, 9, 10, 11, 12, 13, 14, 15]:
		by_distance.append(Items.damage_for(bow_verb, 5, away))
	_check(by_distance == [1.6, 1.6, 1.6, 1.6, 1.2, 1.2, 0.8, 0.8] and Items.damage_for(bow_verb, 0, 3) == 0.8 and Items.damage_for(bow_verb, 1, 6) == 1.2
			and Items.damage_for(bow_verb, 3, 14) == 1.6,
			"strength by the draw, then by the struck body's band past full draw: 0.8, 1.2, 1.6 drawing up; 1.6 within 11 cells, 1.2, 0.8 in the bands out (669 amended) (%s)" % [by_distance])
	host.raised_tick = World.tick - 40
	var cone := World.spread_of(host)
	var strayed := true
	var salt := World.shot_salt
	for each in 200:
		World.shot_salt = each
		var flies := World.scatter(host, 0.5, cone)
		strayed = strayed and absf(flies - 0.5) <= cone + 0.0001
	World.shot_salt = 12345
	var flown := World.scatter(host, 0.5, cone)
	_check(strayed and flown != 0.5 and is_equal_approx(World.scatter(host, 0.5, cone), flown) and World.scatter(host, 0.5, 0.0) == 0.5,
			"the arrow's line is rolled in the cone, the same for the same salt, name and tick; no cone, the aim (%.3f of 0.5, cone %.3f)" % [flown, cone])
	var flew := []
	var landed := func(to: Vector2, _struck: StringName) -> void: flew.append(to)
	host.shot.connect(landed)
	_check(World.try_loose(host, 0.5) and shots.size() == 1 and shots[0] == [host, 0.5, 5] and host.raised == "",
			"held past the last band: loosed at the angle, at its longest step, for combat to shoot (%s)" % [shots])
	_check(flew.size() == 1 and is_equal_approx(snappedf((flew[0] - Vector2(host.tile)).angle(), 0.001), snappedf(flown, 0.001)),
			"it flies the rolled line, read in the cone before the bow is lowered (%s, %.3f)" % [flew, flown])
	host.shot.disconnect(landed)
	World.shot_salt = salt
	_check(World.spread_of(host) == -1.0, "not drawing: no cone")
	_check(not World.try_stance(host, "block"), "a bow is no shield")
	World.loosed.disconnect(shot)
	print("\n== the bow shoots along a ray at any angle: the first body, full draw hardest (decisions 335, 583, 669) ==")
	var imp: GridEntity = null
	for monster in World.monsters():
		imp = monster
		break
	var mark := _open_line(host, 4)
	_check(imp != null and mark != World.NO_CELL, "an imp, and an open line 4 cells long")
	if imp != null and mark != World.NO_CELL:
		var toward := Vector2(mark - host.tile).angle()
		var line: Array[Vector2i] = World.shot_ray(host.tile, toward, 8)["cells"]
		_check(line.size() >= 4 and line[3] == mark and line.all(func(cell: Vector2i) -> bool: return World.distance(host.tile, cell) <= 8),
				"the ray runs through the aim and on, never past 8 cells (%s)" % [line])
		var slant: Array[Vector2i] = World.shot_ray(host.tile, atan2(1.0, 2.0), 6)["cells"]
		var touching := true
		var last := host.tile
		for cell in slant:
			touching = touching and absi(cell.x - last.x) + absi(cell.y - last.y) == 1
			last = cell
		_check(touching, "at a slant every cell it crosses, side by side: no slipping past a corner (%s)" % [slant])
		var corner: Dictionary = World.shot_ray(host.tile, PI / 4.0, 1)
		var beside: Array = [host.tile + Vector2i(1, 0), host.tile + Vector2i(0, 1)]
		_check(corner["cells"].has(host.tile + Vector2i(1, 1)) == false or beside.all(func(cell: Vector2i) -> bool:
				return corner["cells"].has(cell) or not World.is_walkable(cell) or World._terrain_blocks_step(host.tile, cell - host.tile, false, false)),
				"through a corner exactly: the cells beside it too (%s)" % [corner["cells"]])
		var near := host.tile + (mark - host.tile) / 2
		var imp_hp := imp.hp
		World._relocate(imp, mark)
		var ends := []
		var seen := func(to: Vector2, struck: StringName) -> void: ends.append([to, struck])
		host.shot.connect(seen)
		var hp := imp.hp
		_check(World.shoot(host, toward, 2) == imp and imp.hp == hp - 6 and ends.size() == 1
				and ends[0][0].is_equal_approx(Vector2(mark)) and ends[0][1] == &"body",
				"full draw (9 cells, x1.6): the imp, the first body, hit for 6 (a blow of 2, the bow's 2) (%d -> %d); the arrow ends at it (%s)" % [hp, imp.hp, ends])
		var aim := World.shot_aim(host, toward, 7)
		_check(aim["hit"] == imp and aim["cell"] == mark and aim["struck"] == &"body",
				"the aim while drawing reads the same ray: the imp outlined, where the arrow ends")
		imp.hp = imp.max_hp
		hp = imp.hp
		_check(World.shoot(host, toward, 1) == imp and imp.hp == hp - 5, "the second step (x1.2): 5 (%d -> %d)" % [hp, imp.hp])
		imp.hp = imp.max_hp
		hp = imp.hp
		_check(World.shoot(host, toward, 0) == imp and imp.hp == hp - 3, "the first step (x0.8): 3 (%d -> %d)" % [hp, imp.hp])
		imp.hp = imp.max_hp
		hp = imp.hp
		_check(World.shoot(host, toward, 5) == imp and imp.hp == hp - 6, "the last band, the imp within full draw's 9 cells: full strength, 6 (%d -> %d)" % [hp, imp.hp])
		imp.hp = imp.max_hp
		hp = imp.hp
		var friend := Resident.new()
		friend.name = "Tam"
		World._relocate(imp, _far_cell(host))
		_check(World.spawn(friend, mark), "(a resident stands where the imp stood)")
		var friend_hp := friend.hp
		_check(World.shoot(host, toward, 3) == null and friend.hp == friend_hp and friend.ailments.is_empty() and ends.back()[1] == &"body",
				"a shot meets a friend: it ends there, no harm (Jeff: arrows dont harm friendlies, decision 456)")
		_check(World.spares(host, friend) and not World.spares(imp, host) and not World.spares(host, imp), "a player's arrow spares a friend; a monster's spares nobody")
		World.despawn(friend)
		hp = imp.hp
		_check(World.shot_aim(host, toward)["hit"] == null and World.shot_aim(host, NAN).is_empty(), "the aim with nobody on the ray: no body; none at no angle")
		_check(World.shoot(host, toward, 3) == null and imp.hp == hp, "nothing on the ray: nothing hit")
		host.shot.disconnect(seen)
		imp.hp = maxi(1, imp_hp - 7)  # Left as hurt as its shots here always left it: the tests after count on it.
		World.try_stance(host, "draw")
		host.raised_tick = World.tick - 24
		var drawn_from := host.raised_tick
		var stood := host.tile
		var stepped := false
		var way := Vector2i.ZERO
		for direction: Vector2i in World.DIRECTIONS:
			if World.is_free(host.tile + direction):
				host.next_move_tick = 0
				way = direction
				stepped = World.try_move(host, direction)
				break
		_check(not stepped and host.tile == stood and host.raised == "draw" and host.raised_tick == drawn_from and World.range_of(host) == 13,
				"a step while drawn: refused, the body stands firm and the draw is kept (583 amended)")
		# The step taken let down, as the tests after it have always had it.
		host.raised = ""
		host.next_move_tick = 0
		World.try_move(host, way)
		host.raised = "draw"
		World.try_stance(host, "")
		var quiver := World.quiver_check
		World.quiver_check = func(_entity: GridEntity) -> bool: return false
		_check(not World.try_stance(host, "draw"), "with the quiver hook saying no, the bow will not draw")
		World.quiver_check = quiver
	for slot in [Player.RIGHT_HAND, Player.LEFT_HAND]:
		World.items.end(World.take_item(host, host, slot), "gone")




func _test_blows() -> void:
	print("
== the weapon in the blow: its speed, damage and force; a dagger from behind; monsters wield (decision 338) ==")
	var host := _player(Net.local_id)
	for slot in [Player.RIGHT_HAND, Player.LEFT_HAND]:
		if not host.slots[slot].is_empty():
			World.items.end(World.take_item(host, host, slot), "gone")
	var imp: GridEntity = null
	for monster in World.monsters():
		imp = monster
		break
	var beside := World.NO_CELL
	for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if World.is_free(host.tile + direction) and World.can_melee(host.tile, host.tile + direction):
			beside = host.tile + direction
			break
	_check(imp != null and beside != World.NO_CELL, "an imp beside the host")
	if imp == null or beside == World.NO_CELL:
		return
	World._relocate(imp, beside)
	imp.acts = false
	# A blow queued and taken back before it lands: its damage, force and the wait after it.
	var blow := func(by: GridEntity, at: GridEntity) -> Array:
		by.next_attack_tick = 0
		by.next_move_tick = 0
		var queued: int = World._hits.size()
		if not World.try_attack(by, at) or World._hits.size() == queued:
			return []
		var hit: Variant = World._hits.pop_back()
		return [hit.damage, hit.force, by.next_attack_tick - World.tick]
	var bare: Array = blow.call(host, imp)
	_check(bare.size() == 3 and bare[0] == 2 and bare[2] == 5, "bare hands: 2, every 5 ticks (%s)" % [bare])
	_give(host, "hammer", Player.RIGHT_HAND)
	var hammer: Array = blow.call(host, imp)
	_check(hammer[0] == 2 and hammer[1] >= World.knockback_min_force and hammer[1] > bare[1] and hammer[2] == 7,
			"a hammer: the same 2, but three times the push, enough to knock back (%.2f against %.2f bare), and slower: 7 ticks" % [hammer[1], bare[1]])
	World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")
	_give(host, "dagger", Player.RIGHT_HAND)
	imp._world_set_facing(host.tile - imp.tile)
	var front: Array = blow.call(host, imp)
	imp._world_set_facing(imp.tile - host.tile)
	var back: Array = blow.call(host, imp)
	_check(front[0] == 1 and back[0] == 2 and front[2] == 3, "a dagger: quick (3 ticks), 1 to the face, 2 in the back (%s, %s)" % [front, back])
	World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")
	_give(host, "bow", Player.RIGHT_HAND)
	_check((blow.call(host, imp) as Array)[0] == 2, "a bow is no club: a blow with it is bare-handed")
	World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")
	imp.slots = Items.tidy(["", "", "", "", "dagger", "shield"], Items.CARRIED)
	_check(World.holds_in_hands(imp) and not World.has_hands(imp) and World.wielded(imp) == "dagger" and World.guard(imp)["absorb"] == 1.0,
			"a monster given hands fights with them: a dagger, a shield's guard; it is no carrier")
	host._world_set_facing(imp.tile - host.tile)
	_check((blow.call(imp, host) as Array)[2] == roundi(imp.attack_ticks * 0.6), "its blows come at a dagger's pace")
	imp.slots = PackedStringArray()
	var rows: Array[String] = ["#####", "#...#", "#####"]
	var markers := {Vector2i(1, 1): "monster_imp", Vector2i(2, 1): "monster_brute", Vector2i(3, 1): "start"}
	var config := {"name": "arms_test", "entities": [{"at": [1, 1], "wields": {"right": "spear", "left": "shield"}},
		{"at": [2, 1], "wields": {"right": "giant_axe", "left": "shield"}}]}
	var level := Level.parse(Level.image_from_rows(Terrain.expand(rows), markers, config), null, config)
	var by_tile := {}
	for spec: Dictionary in level["entities"]:
		by_tile[spec["tile"]] = spec["props"].get("slots", PackedStringArray())
	_check(by_tile[Vector2i(1, 1)] == PackedStringArray(["", "", "", "", "spear", "shield", "", "", "", "", ""]), "an entry's wields: spear and shield in the hands (%s)" % by_tile[Vector2i(1, 1)])
	_check(by_tile[Vector2i(2, 1)][Items.RIGHT_HAND] == "giant_axe" and by_tile[Vector2i(2, 1)][Items.LEFT_HAND] == ""
			and level["warnings"].any(func(w: String) -> bool: return "no left hand" in w), "a giant axe takes both: the shield left out, and said")
	imp.acts = true


func _test_block() -> void:
	print("
== block: a raised shield takes blows from ahead, for stamina; a heavy one breaks it; a sword parries straight on (decision 340) ==")
	var host := _player(Net.local_id)
	var imp: GridEntity = null
	for monster in World.monsters():
		imp = monster
		break
	var beside := World.NO_CELL
	for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if World.is_free(host.tile + direction) and World.can_melee(host.tile, host.tile + direction) 				and World.is_free(host.tile - direction):
			beside = host.tile + direction
			break
	_check(imp != null and beside != World.NO_CELL, "an imp beside the host, room behind")
	if imp == null or beside == World.NO_CELL:
		return
	World._relocate(imp, beside)
	imp.acts = false
	var ahead := imp.tile - host.tile
	host._world_set_facing(ahead)
	host.stamina = host.max_stamina
	_give(host, "shield", Player.LEFT_HAND)
	_check(World.guarding(host, imp).is_empty(), "a shield not raised: no guard")
	World.try_stance(host, "block")
	_check(World.guarding(host, imp).get("absorb") == 1.0, "raised, facing the imp: its guard")
	host._world_set_facing(-ahead)
	_check(World.guarding(host, imp).is_empty(), "turned away: the blow comes from behind, unguarded")
	host._world_set_facing(Vector2i(ahead.x + ahead.y, ahead.y - ahead.x).clamp(Vector2i(-1, -1), Vector2i(1, 1)))
	_check(not World.guarding(host, imp).is_empty(), "faced one step aside: still within the shield's arc")
	host._world_set_facing(ahead)
	var met: Variant = World._meet_guard(host, imp, 1, 0.8)
	_check(met == [0, 0.0] and host.stamina == host.max_stamina - 15, "an imp's blow (1, force 0.8, weighing 1.8): nothing gets through; 15 stamina (%s, %d)" % [met, host.stamina])
	var hp := host.hp
	imp._world_set_facing(-ahead)
	imp.next_attack_tick = 0
	imp.next_move_tick = 0
	World.try_attack(imp, host)
	World._resolve_hits()
	_check(host.hp == hp and host.raised == "block", "a real blow, resolved: the host unhurt, the shield still up")
	met = World._meet_guard(host, imp, 2, 3.0)
	_check(met == [2, 3.0] and host.raised == "" and World.is_stunned(host), "a hammer's blow (2, force 3; over the shield's 2): the guard breaks, the blow lands whole, the host staggered")
	host.stunned_until_tick = 0
	host.guard_broken_until = World.tick
	World.try_stance(host, "block")
	met = World._meet_guard(host, imp, 2, 0.2)
	_check(met == [2, 0.2] and host.raised == "", "a brute's (2, force 0.2): heavy enough to break it too")
	host.stunned_until_tick = 0
	_check(not World.try_stance(host, "block"), "and the shield will not come up again at once")
	host.guard_broken_until = World.tick
	_check(World.try_stance(host, "block"), "a while later it will")
	host.stamina = 3
	met = World._meet_guard(host, imp, 1, 0.8)
	_check(met == [1, 0.8] and host.raised == "" and host.stamina == 0, "out of stamina: the guard gives way")
	host.stunned_until_tick = 0
	host.guard_broken_until = 0
	host.stamina = host.max_stamina
	World.items.end(World.take_item(host, host, Player.LEFT_HAND), "gone")
	_give(host, "sword", Player.RIGHT_HAND)
	host.next_attack_tick = 0
	_check(World.guarding(host, imp).get("absorb") == 0.5 and World._meet_guard(host, imp, 1, 0.8) == [0, 0.4],
			"a sword, ready, parries an imp's blow straight on: half, the damage rounded away")
	host._world_set_facing(Vector2i(ahead.x + ahead.y, ahead.y - ahead.x).clamp(Vector2i(-1, -1), Vector2i(1, 1)))
	_check(World.guarding(host, imp).is_empty(), "but not from a step aside")
	host._world_set_facing(ahead)
	host.next_attack_tick = World.tick + 3
	_check(World.guarding(host, imp).is_empty(), "nor mid-swing")
	World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")
	imp.slots = Items.tidy(["", "", "", "", "", "shield"], Items.CARRIED)
	imp.raised = "block"
	imp._world_set_facing(-ahead)
	_give(host, "bow", Player.RIGHT_HAND)
	hp = imp.hp
	_check(World.shoot(host, Vector2(imp.tile - host.tile).angle(), 2) == imp and imp.hp == hp, "a shot into a raised shield: taken on it (%d -> %d)" % [hp, imp.hp])
	World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")
	imp.raised = ""
	imp.slots = PackedStringArray()
	imp.acts = true


func _test_bash() -> void:
	print("\n== the shield bash: the left button with the shield raised shoves and staggers, no damage; it opens a guard; stamina and a cooldown (decision 379) ==")
	var host := _player(Net.local_id)
	var far := _open_line(host, 4)
	_check(far != World.NO_CELL, "an open line four cells long from the host")
	if far == World.NO_CELL:
		return
	var d := (far - host.tile) / 4
	var imp := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "name": "BashImp%d" % World.tick,
		"tile": host.tile + d, "kind": "imp", "props": {"sight_range": 0}}) as GridEntity
	imp.acts = false
	imp.max_hp = 50
	imp.hp = 50
	var put_back := func() -> void:
		if imp.tile != host.tile + d:
			World._relocate(imp, host.tile + d)
		imp.stunned_until_tick = 0
		host._world_set_facing(d)
		host.stamina = host.max_stamina
		host.next_move_tick = 0
	put_back.call()
	host.next_attack_tick = 0
	host.next_bash_tick = 0
	var shield := _give(host, "shield", Player.LEFT_HAND)
	var verb := World.bash_verb(host)
	_check(verb.get("bash_force") == 2.0 and verb.get("bash_stagger") == 4 and verb.get("bash_stamina") == 3 and verb.get("bash_ticks") == 20,
			"a shield bashes, its numbers in its verb (%s)" % verb)
	_check(Items.verb_of("sword").get("bash_force") == 0.0, "a sword does not")
	_give(host, "sword", Player.RIGHT_HAND)
	var bashes := []
	var bashed := func(by: GridEntity, target: GridEntity, opened: bool) -> void: bashes.append(opened)
	World.shield_bashed.connect(bashed)
	# Lowered, the left button is the sword's.
	var hp := imp.hp
	World.command_attack(host, imp)
	_steps(1)
	_check(imp.hp < hp and bashes.is_empty() and host.next_bash_tick == 0, "the shield lowered: the left button strikes with the sword (%d -> %d)" % [hp, imp.hp])
	# Raised, it bashes.
	put_back.call()
	World.try_stance(host, "block")
	host.next_attack_tick = World.tick + 100  # The sword not ready: the bash is the shield's own.
	hp = imp.hp
	var expect := World.push_force(host, imp) * World.ATTACK_FORCE_FACTOR * 2.0
	var from := imp.tile
	var at := World.tick
	World.order_signature(host, imp)  # Ctrl and a click (decision 593; 379's left button with the shield up before).
	_steps(1)
	_check(bashes == [false] and imp.hp == hp and World.is_stunned(imp), "the signature bashes; no damage, the imp staggered")
	_check(host.stamina == host.max_stamina - 3 and host.next_bash_tick >= at + 20 and not World.bash_ready(host),
			"3 stamina (%d of %d), and not again for 20 ticks" % [host.stamina, host.max_stamina])
	_check((imp.tile != from) == (expect >= World.knockback_min_force),
			"pushed only past the least knockback force (%.2f against %.2f; moved %s)" % [expect, World.knockback_min_force, imp.tile != from])
	_check(World.guarding(host, imp).is_empty(), "the bearer's own shield is down for the bash's moment")
	_steps(5)
	_check(host.raised == "block" and not World.guarding(host, imp).is_empty(), "and up again after it, the button still held")
	_check(World.items.history(shield)["carriers"][0]["deeds"].get("guarded", 0) == 1, "the bash counts for the shield as guarded (365)")
	# Under the least force: a stagger alone.
	put_back.call()
	host.next_bash_tick = 0
	var least := World.knockback_min_force
	World.knockback_min_force = 99.0
	from = imp.tile
	_check(World.try_bash(host, imp), "bashed again")
	_steps(1)
	World.knockback_min_force = least
	_check(imp.tile == from and World.is_stunned(imp) and imp.stunned_until_tick <= World.tick + 4, "too light to move it: staggered where it stands")
	_check(not World.try_bash(host, imp), "and not a third time at once")
	# Against a raised guard: opened.
	put_back.call()
	host.next_bash_tick = 0
	imp.slots = Items.tidy(["", "", "", "", "", "shield"], Items.CARRIED)
	imp._world_set_facing(-d)
	imp.raised = "block"
	_check(not World.guarding(imp, host).is_empty(), "the imp's shield up against the host")
	World.knockback_min_force = 99.0  # No knockback: a push stuns by its own rule (_push), as a hammer's does.
	World.try_bash(host, imp)
	_steps(1)
	World.knockback_min_force = least
	_check(bashes.back() == true and imp.raised == "" and imp.guard_broken_until > World.tick and World.is_stunned(imp)
			and imp.stunned_until_tick <= World.tick + 4 and not World.try_stance(imp, "block"),
			"bashed: its guard open and kept down, staggered only the bash's ticks, not a broken guard's")
	# Short of stamina: no bash.
	put_back.call()
	host.next_bash_tick = 0
	host.stamina = 2
	_check(not World.bash_ready(host) and not World.try_bash(host, imp), "with 2 stamina, no bash")
	World.shield_bashed.disconnect(bashed)
	host.raised = ""
	host.stamina = host.max_stamina
	host.next_attack_tick = 0
	host.next_bash_tick = 0
	World.items.end(World.take_item(host, host, Player.LEFT_HAND), "gone")
	World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")
	World.despawn(imp)


func _test_axe() -> void:
	print("
== the giant axe: slow, a 3-cell arc, each struck knocked down; lying, they cannot act and push easily (decision 343) ==")
	var host := _player(Net.local_id)
	var home := host.tile
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var spot := home + Vector2i(dx, dy)
			if World.is_free(spot) and World.DIRECTIONS.all(func(d: Vector2i) -> bool: return World.is_free(spot + d) and World.can_melee(spot, spot + d)):
				World._relocate(host, spot)
				break
		if host.tile != home:
			break
	var cells: Array[Vector2i] = []
	for aim: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var left := Vector2(aim).rotated(-PI / 4.0)
		var right := Vector2(aim).rotated(PI / 4.0)
		var trio: Array[Vector2i] = [host.tile + aim, host.tile + Vector2i(roundi(left.x), roundi(left.y)), host.tile + Vector2i(roundi(right.x), roundi(right.y))]
		if trio.all(func(cell: Vector2i) -> bool: return World.is_free(cell) and World.can_melee(host.tile, cell)):
			cells = trio
			break
	_check(cells.size() == 3, "three free cells in an arc before the host (%s)" % [cells])
	if cells.size() != 3:
		return
	var foes: Array[GridEntity] = []
	for i in 3:
		var foe := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "name": "AxeImp%d_%d" % [i, World.tick],
			"tile": cells[i], "kind": "imp", "props": {"mass": 40.0, "sight_range": 0}}) as GridEntity
		foe.acts = false
		foes.append(foe)
	_give(host, "giant_axe", Player.RIGHT_HAND)
	host._world_set_facing(cells[0] - host.tile)
	host.next_attack_tick = 0
	host.next_move_tick = 0
	var before: Array = foes.map(func(foe: GridEntity) -> int: return foe.hp)
	_check(World.try_attack(host, foes[0]) and host.next_attack_tick - World.tick == 10, "a swing at the middle one; slow: 10 ticks to the next")
	World._resolve_hits()
	var hurt := range(3).all(func(i: int) -> bool: return foes[i].hp == before[i] - 3)
	_check(hurt, "all three in the arc struck for 3 (2 times 1.5) (%s -> %s)" % [before, foes.map(func(foe: GridEntity) -> int: return foe.hp)])
	_check(foes.all(func(foe: GridEntity) -> bool: return World.is_down(foe) and World.is_stunned(foe) and foe.down_until == World.tick + 15),
			"and all three knocked down for 15 ticks, unable to act")
	var lying := foes[1]
	_check(is_equal_approx(World.pushed_mass(lying), lying.mass * World.DOWN_MASS_FACTOR), "lying, pushed as if half its mass (%.1f of %.1f)" % [World.pushed_mass(lying), lying.mass])
	lying.slots = Items.tidy(["", "", "", "", "", "shield"], Items.CARRIED)
	_check(not World.try_stance(lying, "block"), "a shield cannot come up lying down")
	World.tick += 16
	_check(not World.is_down(lying) and World.try_stance(lying, "block"), "15 ticks on it is up, and can")
	World.tick -= 16
	World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")
	for foe in foes:
		if is_instance_valid(foe) and foe.spawned:
			World.despawn(foe)
	World._relocate(host, home)


func _test_wind_up() -> void:
	print("
== the wind-up: a giant axe's blow wound up 8 ticks, then struck through any guard; a step or a stun gives it up; out of reach it whiffs (decision 392) ==")
	var host := _player(Net.local_id)
	var home := host.tile
	var far := _open_line(host, 4)
	_check(far != World.NO_CELL, "an open line four cells long from the host")
	if far == World.NO_CELL:
		return
	var d := (far - host.tile) / 4
	var imp := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "name": "WindImp%d" % World.tick,
		"tile": host.tile + d, "kind": "imp", "props": {"mass": 40.0, "sight_range": 0}}) as GridEntity
	imp.acts = false
	imp.max_hp = 50
	imp.hp = 50
	imp.slots = Items.tidy(["", "", "", "", "", "shield"], Items.CARRIED)
	var pets: Array = World.get_entities().filter(func(e: GridEntity) -> bool: return e is Companion and e.acts)
	for pet: GridEntity in pets:
		pet.acts = false  # Nobody else fights the imp.
	var ready := func() -> void:
		if host.tile != home:
			World._relocate(host, home)
		if imp.tile != home + d:
			World._relocate(imp, home + d)
		imp.stunned_until_tick = 0
		imp.down_until = 0
		imp.guard_broken_until = 0
		imp._world_set_facing(-d)
		imp.raised = "block"
		host._world_set_facing(d)
		host.stunned_until_tick = 0
		host.next_attack_tick = 0
		host.next_move_tick = 0
	var wound := []
	var wind := func(_direction: Vector2i, ticks: int) -> void: wound.append(ticks)
	var swings := []
	var swing := func(direction: Vector2i) -> void: swings.append(direction)
	host.winding.connect(wind)
	host.swung.connect(swing)
	_check(World.windup_ticks(host) == 0, "bare-handed, no wind-up")
	_give(host, "hammer", Player.RIGHT_HAND)
	_check(World.windup_ticks(host) == 0, "nor a hammer's")
	World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")
	_give(host, "giant_axe", Player.RIGHT_HAND)
	_check(World.windup_ticks(host) == 8, "a giant axe winds up 8 ticks")
	ready.call()
	var hp := imp.hp
	World.command_attack(host, imp)
	_steps(1)
	_check(wound == [8] and not World.winding(host).is_empty() and imp.hp == hp, "the attack: wound up, the views told 8 ticks; nothing struck yet")
	_steps(8)
	_check(World.winding(host).is_empty() and imp.hp < hp and imp.raised == "" and World.is_down(imp),
			"8 ticks on it is struck through the raised shield, which breaks; the imp knocked down (%d -> %d)" % [hp, imp.hp])
	# Given up by a move order.
	ready.call()
	wound.clear()
	World.command_attack(host, imp)
	_steps(1)
	World.free_input(host, Vector2(-d).normalized(), 1.0)  # A free move straight away (392 amended).
	_steps(1)
	_check(World.winding(host).is_empty() and wound == [8, 0], "a free move away gives it up; the views told (0 ticks) (%s)" % [wound])
	World.free_drop(host)
	hp = imp.hp
	_steps(10)
	_check(imp.hp == hp, "and nothing is struck")
	# Given up by a stun.
	ready.call()
	wound.clear()
	World.command_attack(host, imp)
	_steps(1)
	World._stun_for(host, 3)
	_steps(1)
	_check(World.winding(host).is_empty() and wound == [8, 0], "a stun gives it up (%s)" % [wound])
	# Out of reach when it lands: a whiff.
	ready.call()
	wound.clear()
	World.command_attack(host, imp)
	_steps(1)
	World._relocate(imp, home + d * 3)
	hp = imp.hp
	swings.clear()
	_steps(8)
	_check(imp.hp == hp and swings.size() == 1 and wound == [8], "its target stepped out of reach: the blow whiffs at the air")
	# However light, a wound-up blow breaks a guard.
	ready.call()
	_check(World._meet_guard(imp, host, 1, 0.0, false, true) == [1, 0.0] and imp.raised == "", "a wound-up blow breaks a guard however light it is")
	host.winding.disconnect(wind)
	host.swung.disconnect(swing)
	World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")
	imp.raised = ""
	for uid in World.slot_uids(imp):
		if uid != 0:
			World.items.end(uid, "gone")
	imp.slots = PackedStringArray()
	World.despawn(imp)
	ready.call()
	for pet: GridEntity in pets:
		pet.acts = true


func _test_spear() -> void:
	print("
== the spear: a blow two cells off through an empty cell; braced, it stops a charge (decision 344) ==")
	var host := _player(Net.local_id)
	var home := host.tile
	var aim := Vector2i.ZERO
	for dy in range(-8, 9):
		for dx in range(-8, 9):
			var spot := home + Vector2i(dx, dy)
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var lane := [spot, spot + d, spot + d * 2, spot + d * 3, spot + d * 4, spot + Vector2i(d.y, d.x) + d * 2]
				if aim == Vector2i.ZERO and (spot == host.tile or World.is_free(spot)) 						and lane.slice(1).all(func(cell: Vector2i) -> bool: return World.is_free(cell)) 						and range(4).all(func(i: int) -> bool: return World.can_melee(spot + d * i, spot + d * (i + 1))):
					World._relocate(host, spot)
					aim = d
	_check(aim != Vector2i.ZERO, "an open lane four cells long from the host")
	if aim == Vector2i.ZERO:
		return
	var imp := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "name": "SpearImp%d" % World.tick,
		"tile": host.tile + aim * 2, "kind": "imp", "props": {"mass": 40.0, "sight_range": 0}}) as GridEntity
	imp.acts = false
	_check(not World.in_reach(host, imp), "bare-handed, two cells off is out of reach")
	_give(host, "spear", Player.RIGHT_HAND)
	_check(World.in_reach(host, imp), "with a spear, in reach")
	host.next_attack_tick = 0
	host.next_move_tick = 0
	var hp := imp.hp
	_check(World.try_attack(host, imp), "and struck from there")
	World._resolve_hits()
	_check(imp.hp == hp - 2, "for the blow's 2 (%d -> %d)" % [hp, imp.hp])
	var blocker := _main._spawn({"script": "res://sim/pushable.gd", "shape": "cube", "name": "SpearCrate%d" % World.tick, "tile": host.tile + aim}) as GridEntity
	_check(not World.in_reach(host, imp), "a crate between: not through it")
	World.despawn(blocker)
	World._relocate(imp, host.tile + aim * 2 + Vector2i(aim.y, aim.x))
	_check(not World.in_reach(host, imp), "a knight's move off: not a straight line")
	World._relocate(imp, host.tile + aim * 3)
	_check(not World.in_reach(host, imp), "three cells: past its two")
	World.despawn(imp)
	var boar := _main._spawn({"script": "res://sim/animal.gd", "shape": "capsule", "name": "SpearBoar%d" % World.tick,
		"tile": host.tile + aim * 4, "kind": "boar", "props": {"mass": 80.0, "max_hp": 18}}) as Animal
	boar.acts = false
	host._world_set_facing(aim)
	host.last_step_tick = World.tick - World.BRACE_TICKS
	_check(World.braced(host), "the host stood still %d ticks facing the lane: braced" % World.BRACE_TICKS)
	boar._foe = host
	boar._charge_until = World.tick + 50
	boar._world_set_facing(-aim)
	_check(boar.charging(), "the boar charges")
	boar.next_move_tick = 0
	_check(World.try_move(boar, -aim), "a step at four cells: free")
	boar.next_move_tick = 0
	hp = boar.hp
	var at := boar.tile
	_check(not World.try_move(boar, -aim), "the next, into the spear's reach: stopped")
	World._resolve_hits()
	_check(boar.hp == hp - 4 and World.distance(boar.tile, host.tile) > World.distance(at, host.tile) and World.is_stunned(boar),
			"struck for 4 (twice the blow), thrown back by its own weight (%s -> %s), staggered" % [at, boar.tile])
	World._relocate(boar, host.tile + aim * 3)
	boar.stunned_until_tick = 0
	boar.next_move_tick = 0
	host.last_step_tick = World.tick
	_check(World.try_move(boar, -aim), "a spear not braced (the holder just stepped): the charge goes in")
	World.despawn(boar)
	World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")
	World._relocate(host, home)


func _test_pickup() -> void:
	print("
== monsters: what they carry weighs; a free hand takes up a weapon lying beside it (decision 347) ==")
	var host := _player(Net.local_id)
	var spot := World.NO_CELL
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var cell := host.tile + Vector2i(dx, dy)
			if spot == World.NO_CELL and World.distance(cell, host.tile) > 2 and World.is_free(cell) 					and World.DIRECTIONS.all(func(d: Vector2i) -> bool: return World.is_free(cell + d) and World.can_melee(cell, cell + d)):
				spot = cell
	_check(spot != World.NO_CELL, "an open spot for an imp")
	if spot == World.NO_CELL:
		return
	var laden := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "name": "LadenImp%d" % World.tick,
		"tile": spot, "kind": "imp", "props": {"mass": 40.0, "sight_range": 0, "slots": Items.tidy(["sword", "ration"], 4)}}) as GridEntity
	_check(is_equal_approx(laden.mass, 40.0 + Items.weight_of("sword") + Items.weight_of("ration")),
			"an imp spawned carrying a sword and a ration weighs 40 and them (%.1f)" % laden.mass)
	World.despawn(laden)
	var imp := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "name": "PickImp%d" % World.tick,
		"tile": spot, "kind": "imp", "props": {"mass": 40.0, "sight_range": 0}}) as GridEntity
	imp.acts = false
	_check(World.weapon_near(imp) == World.NO_CELL and not World.try_pick_up_weapon(imp), "nothing lying near: nothing to take up")
	var beside := spot + Vector2i(1, 0)
	World.put_on_ground(World.items.mint("ration", "built"), beside)
	_check(World.weapon_near(imp) == World.NO_CELL, "a ration is no weapon")
	var dagger := World.items.mint("dagger", "built")
	World.put_on_ground(dagger, beside)
	_check(World.weapon_near(imp) == beside, "a dagger beside it: there")
	var mass := imp.mass
	_check(World.try_pick_up_weapon(imp) and imp.slots.size() == Items.CARRIED and imp.slots[Items.RIGHT_HAND] == "dagger"
			and imp.slot_items[Items.RIGHT_HAND] == dagger and World.wielded(imp) == "dagger",
			"taken up into its right hand: it has hands now, and fights with it (%s)" % imp.slots)
	_check(is_equal_approx(imp.mass, mass + Items.weight_of("dagger")) and World.ground_at(beside) == PackedStringArray(["ration"]),
			"it weighs on it (%.1f); the ration still lies there" % imp.mass)
	var events: Array = World.items.history(dagger)["events"]
	_check(events[-1]["kind"] == "taken up" and str(events[-1]["what"]).begins_with("by PickImp"), "the dagger's history says who took it up (%s)" % [events[-1]])
	World.put_on_ground(World.items.mint("giant_axe", "built"), beside)
	_check(World.weapon_near(imp) == World.NO_CELL, "a giant axe needs both hands: not for it now")
	World.put_on_ground(World.items.mint("shield", "built"), spot + Vector2i(0, 1))
	_check(World.try_pick_up_weapon(imp) and imp.slots[Items.LEFT_HAND] == "shield" and World.guard(imp)["absorb"] == 1.0, "a shield, into the left")
	_check(not World.try_pick_up_weapon(imp), "hands full: no more")
	var at := imp.tile
	World.damage(imp, 1000, host)
	var lying := []
	for cell: Vector2i in World.zone.ground.keys():
		if World.distance(cell, at) <= 2:
			while not World.ground_uids(cell).is_empty():
				var uid := World.take_from_ground(cell, 0)
				lying.append(World.items.id_of(uid))
				World.items.end(uid, "gone")
	lying.sort()
	_check("dagger" in lying and "shield" in lying, "beaten, it drops what it took up (%s)" % [lying])

func _test_kills() -> void:
	print("\n== kill counts: what a thing has felled, by kind, whoever held it; its note shows it (decision 415) ==")
	var host := _player(Net.local_id)
	var far := _open_line(host, 2)
	_check(far != World.NO_CELL, "an open cell beside the host")
	if far == World.NO_CELL:
		return
	var d := (far - host.tile) / 2
	var dagger := _give(host, "dagger", Player.RIGHT_HAND)
	World.items.fell(dagger, "imp")
	_check(World.items.felled_of(dagger).is_empty() and not World.items.grows(dagger), "a plain dagger keeps no tally: it has no character yet (decision 472)")
	World.items.give_character(dagger, "named")
	var arrows := World.items.mint("arrows", "built")
	World.items.give_character(arrows, "blessed")
	var kit := World.items.mint("bow", "built")
	World.items.bless(kit, "player:test")
	var row := {"who": "player:test", "name": "Wren", "since": 0, "held": 0, "deeds": {"shot": 20}, "ill": 0.0, "ill_at": 0}
	var plain := World.items.mint("sword", "built")
	World.items._book[plain]["holder"] = "player:test"
	World.items._book[plain]["carriers"] = [row]
	_check(not World.items.grows(arrows) and World.items.grows(kit) and World.items.character_of(kit) == "blessed"
			and World.items.grows(dagger) and World.items.history(dagger)["events"].back()["kind"] == "character",
			"a bundle of arrows never grows; a blessed bow does; earning it is in the history")
	_check(World.items.name_due(plain, 99999, 10).is_empty() and not World.items.name_due(plain, 99999, 10, 20).is_empty(),
			"20 deeds earn it however short the holding; without that route, not before held_days (%s)" % [World.items.name_due(plain, 99999, 10, 20)])
	var before := ItemBook.from_dict({"book": {"1": {"id": "dagger", "felled": {"imp": 2}}, "2": {"id": "dagger"}}})
	_check(before.grows(1) and not before.grows(2), "a save from before: a tallied thing has grown already, a plain one not")
	for each in [arrows, kit, plain]:
		World.items.end(each, "gone")
	var fell := func(kind: String) -> void:
		var foe := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "name": "KillImp%d" % World.tick,
			"tile": host.tile + d, "kind": kind, "props": {"sight_range": 0}}) as GridEntity
		foe.acts = false
		foe.hp = 1
		host._world_set_facing(d)
		host.next_attack_tick = 0
		host.next_move_tick = 0
		World.try_attack(host, foe)
		World._resolve_hits()
		while not World.ground_uids(host.tile + d).is_empty():
			World.items.end(World.take_from_ground(host.tile + d, 0), "gone")  # What it carried (loot, decision 330).
	_check(World.kills_line(dagger).is_empty(), "a new dagger has felled nothing")
	fell.call("imp")
	fell.call("imp")
	fell.call("wolf")
	_check(World.items.felled_of(dagger) == {"imp": 2, "wolf": 1}, "two imps and a wolf, counted by kind (%s)" % World.items.felled_of(dagger))
	_check(World.kills_line(dagger) == "felled 3: 2 imps, 1 wolf", "the tally: %s" % World.kills_line(dagger))
	_check(host.slot_notes.size() > Player.RIGHT_HAND and host.slot_notes[Player.RIGHT_HAND] == "dagger\nfelled 3: 2 imps, 1 wolf",
			"the slot's note: its name, the tally under it (%s)" % [host.slot_notes])
	var back := ItemBook.from_dict(World.items.to_dict())
	_check(back.felled_of(dagger) == {"imp": 2, "wolf": 1}, "saved and read back")
	World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")


func _test_style() -> void:
	print("\n== a thing's make: dwarven or dark elven, from its source (decision 474) ==")
	var rows: Array[String] = ["#######", "#.....#", "#.....#", "#######"]
	var markers := {Vector2i(1, 1): "chest", Vector2i(3, 1): "chest", Vector2i(5, 1): "chest", Vector2i(2, 2): "monster_imp",
		Vector2i(3, 2): "crate", Vector2i(5, 2): "start"}
	var config := {"name": "style_test", "item_style": "dwarven",
		"entities": [{"at": [3, 1], "props": {"style": "dark elven"}}, {"at": [5, 1], "props": {"style": "elvish"}}]}
	var level := Level.parse(Level.image_from_rows(Terrain.expand(rows), markers, config), null, config)
	var style_at := {}
	for spec: Dictionary in level["entities"]:
		style_at[spec["tile"]] = spec.get("props", {}).get("style", "")
	_check(style_at.get(Vector2i(1, 1)) == "dwarven" and style_at.get(Vector2i(2, 2)) == "dwarven",
			"the level's item_style: its chest and its imp are dwarven (%s)" % [style_at])
	_check(style_at.get(Vector2i(3, 2)) == "dwarven", "and its crate's goods (dungeon's halls lay crates)")
	_check(style_at.get(Vector2i(3, 1)) == "dark elven", "a marker's own style wins over the level's")
	_check(style_at.get(Vector2i(5, 1)) == "dwarven" and level["warnings"].any(func(w: String) -> bool: return "elvish" in w),
			"an unknown make: warned, the level's instead")
	var plain := World.items.mint("dagger", "made", "", "", Vector2i(-1, -1), "elvish")
	var dwarven := World.items.mint("dagger", "made", "", "", Vector2i(-1, -1), "dwarven")
	_check(World.items.style_of(plain).is_empty() and World.items.style_of(dwarven) == "dwarven", "minted of a known make only")
	_check(World.item_note(dwarven) == "dwarven dagger" and World.story_line(dwarven).ends_with("dwarven work"),
			"its note and story say so (%s; %s)" % [World.item_note(dwarven), World.story_line(dwarven)])
	_check(ItemBook.from_dict(World.items.to_dict()).style_of(dwarven) == "dwarven", "saved and read back")
	World.items.end(plain, "gone")
	World.items.end(dwarven, "gone")
	var imp: GridEntity = null
	for monster in World.monsters():
		if str(monster.spawn_spec.get("kind", "")) == "imp":
			imp = monster
			break
	_check(imp != null, "an imp to carry and drop things")
	if imp == null:
		return
	var props: Dictionary = imp.spawn_spec.get("props", {})
	var had_props := props.duplicate()
	var had_slots := imp.slots
	props["style"] = "dark elven"
	imp.spawn_spec["props"] = props
	imp.slots = Items.tidy(["dagger"], Items.CARRIED)
	var held := World.slot_uid(imp, 0)
	_check(World.items.style_of(held) == "dark elven", "what a dark elven imp carries is dark elven (%s)" % World.items.style_of(held))
	var row: Dictionary = Monster.kinds()["imp"]
	var had_drops: Variant = row.get("drops")
	row["drops"] = [{"item": "dagger"}, {"item": "ration", "style": "dwarven"}]
	var had_purse: Variant = row.get("purse")
	row["purse"] = [0, 0]  # No gold here (decision 601 has its own test).
	var dropped := (imp as Monster).remains()
	row["purse"] = had_purse
	_check(dropped.size() == 2 and World.items.style_of(dropped[0]) == "dark elven" and World.items.style_of(dropped[1]) == "dwarven",
			"its remains: of its make, a row's own style winning")
	if had_drops == null:
		row.erase("drops")
	else:
		row["drops"] = had_drops
	for uid in dropped:
		World.items.end(uid, "gone")
	World.items.end(held, "gone")
	imp.slots = had_slots
	imp.spawn_spec["props"] = had_props


func _test_short() -> void:
	print("\n== short measure: a scoundrel's sack or bundle, never gear (decision 493) ==")
	_check(Items.measured("food_sack") and Items.measured("arrows") and Items.measured("hide")
			and Items.measured("cloth_bolt") and Items.measured("herbs")
			and not Items.measured("sword") and not Items.measured("bow") and not Items.measured("shield") and not Items.measured("ration") and not Items.measured("remedy"),
			"measured: sacks, hides, bolts, herbs, a bundle of arrows; never a weapon, gear, or a whole ration")
	_check(Items.def("cloth_bolt")["made"].get("by") == "weaver" and Items.def("remedy")["made"].get("by") == "medicine_man"
			and Items.yield_of("cloth_bolt") == {"cloth": 3} and Items.yield_of("herbs") == {"herbs": 1},
			"the weaver's bolt (500) and the medicine man's remedy from herbs (501, 562)")
	var luxuries := true
	for id: String in ["wine", "spice", "silver_ring"]:
		luxuries = luxuries and Items.has_tag(id, "luxury") and Items.yield_of(id).is_empty() \
				and not Items.has_tag(id, "food") and not Items.has_tag(id, "resource")
	_check(luxuries and Items.def("silver_ring")["made"].get("by") == "smith" and Items.def("wine")["made"].is_empty(),
			"the luxuries: tagged luxury, no yield, not food nor resource; the ring the smith's, wine imported")
	var sword := World.items.mint("sword", "made")
	_check(not World.items.make_short(sword) and World.items.short_of(sword) == 1.0, "a sword is never short")
	var sack := World.items.mint("food_sack", "made")
	_check(World.items.make_short(sack) and World.items.yields_of(sack) == {"food": 3} and Items.yield_of("food_sack") == {"food": 5},
			"a short food sack banks 3 food of 5 (%s)" % [World.items.yields_of(sack)])
	_check(not World.items.make_short(sack, 0.1) and World.items.yields_of(sack) == {"food": 3}, "short once only")
	_check(World.item_note(sack) == Items.name_of("food_sack") + ", short measure" and World.story_line(sack).ends_with("short measure")
			and World.items.history(sack)["events"].back()["kind"] == "short" and World.items.history(sack)["events"].back()["what"] == "",
			"its note and story say so, naming no one (%s)" % World.item_note(sack))
	var arrows := World.items.mint("arrows", "made")
	World.items.make_short(arrows)
	_check(World.items.condition_of(arrows) == 6, "a short bundle: 6 arrows of 10")
	var hide := World.items.mint("hide", "made")
	World.items.make_short(hide)
	_check(World.items.yields_of(hide) == {"hide": 1}, "a single hide's one stays one")
	var back := ItemBook.from_dict(World.items.to_dict())
	_check(back.yields_of(sack) == {"food": 3} and back.short_of(sword) == 1.0, "saved and read back")
	for uid in [sword, sack, arrows, hide]:
		World.items.end(uid, "gone")


func _test_gold_drop() -> void:
	print("
== a humanoid's gold where it falls, a count, never a thing; none from an animal or the undead (decision 601, 601 amended) ==")
	var kinds := Monster.kinds()
	_check(kinds["imp"]["purse"] == [1, 3] and kinds["sneak"]["purse"] == [1, 3] and kinds["brute"]["purse"] == [4, 10]
			and kinds["wolf"]["purse"] == [0, 0] and kinds["skeleton"]["purse"] == [0, 0] and kinds["draugr"]["purse"] == [0, 0],
			"the goblin, the kobold and the orc carry a purse; the wolf, the skeleton and the draugr none")
	var host := _player(Net.local_id)
	var beside := _plain_cell(host)
	var imp := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "name": "PurseImp%d" % World.tick,
		"tile": beside, "kind": "imp", "props": {"mass": 40.0, "sight_range": 0}}) as Monster
	imp.acts = false
	var row: Dictionary = kinds["imp"]
	var had_drops: Variant = row.get("drops")
	row["drops"] = []
	var at := imp.tile
	var before := World.ground_uids(at)
	var gold_before := World.ground_gold(at)
	World.damage(imp, imp.hp, host, &"attack")
	var gold := World.ground_gold(at) - gold_before
	_check(gold >= 1 and gold <= 3 and World.ground_uids(at) == before, "a goblin falls: %d gold (1 to 3) on its cell, a count; no thing" % gold)
	var pile: GroundPile = World.zone.piles.get(at)
	_check(is_instance_valid(pile) and pile.gold == gold_before + gold and Main.pile_words(pile.ids, pile.gold).begins_with("%d gold" % (gold_before + gold)),
			"its pile shows it: %s" % (Main.pile_words(pile.ids, pile.gold) if is_instance_valid(pile) else "no pile"))
	var saved := Main.ground_entries(World.zone).filter(func(entry: Dictionary) -> bool: return Vector2i(int(entry["cell"][0]), int(entry["cell"][1])) == at)
	_check(saved.size() == 1 and int(saved[0].get("gold", 0)) == gold_before + gold, "kept through a save (%s)" % [saved])
	var parsed: Array = Snapshot.parse_zone({"tick": 0, "entities": [], "ground": JSON.parse_string(JSON.stringify(saved))})["ground"]
	_check(parsed.size() == 1 and int(parsed[0]["gold"]) == gold_before + gold, "and read back")
	if had_drops == null:
		row.erase("drops")
	else:
		row["drops"] = had_drops
	# F: the gold into the record's, no slot (601 amended).
	var host_at := host.tile
	var slots_before := host.slots.duplicate()
	World._relocate(host, at)
	var player_id: String = host.player_id
	var had := World.gold_of(player_id)
	var got := World.try_pick_up_gold(host, at)
	_check(got == gold_before + gold and (World.gold_of(player_id) == had + got or World.economy == null) and World.ground_gold(at) == 0
			and host.slots == slots_before, "picked up: %d gold into the record's (%d to %d), none left, no slot taken" % [got, had, World.gold_of(player_id)])
	_check(World.try_pick_up_gold(host, at) == 0, "nothing more to pick up")
	_check(before.is_empty() == not is_instance_valid(World.zone.piles.get(at)), "the pile goes with its gold, if that was all")
	World._relocate(host, host_at)
	# An old coin purse, saved before 601 amended: its gold, never the thing.
	var contents := Array(host.slots)
	var free := contents.find("")
	if free >= 0:
		contents[free] = World.OLD_PURSE
		had = World.gold_of(player_id)
		World.set_slots(host, contents, host.slot_items)
		_check(host.slots[free].is_empty() and (World.gold_of(player_id) == had + World.OLD_PURSE_GOLD or World.economy == null),
				"a saved purse in a pack: %d gold into the record's, the slot empty" % World.OLD_PURSE_GOLD)
	var lying := _plain_cell(host)
	var lay_gold := World.ground_gold(lying)
	_main._restore_ground([{"cell": lying, "ids": [World.OLD_PURSE, "ration"], "items": []}])
	_check(World.ground_gold(lying) == lay_gold + World.OLD_PURSE_GOLD and "ration" in World.ground_at(lying) and not World.OLD_PURSE in World.ground_at(lying),
			"a saved purse on the ground: its gold as a count there, the rest as it was")
	while "ration" in World.ground_at(lying):
		World.items.end(World.take_from_ground(lying, World.ground_at(lying).find("ration")), "gone")
	World.zone.ground_gold.erase(lying)
	World.ground_changed.emit(World.zone.name, lying, World.NO_CELL)
	var wolf := _main._spawn({"script": "res://sim/animal.gd", "shape": "capsule", "name": "PurseWolf%d" % World.tick,
		"tile": beside, "kind": "wolf", "props": {"sight_range": 0}}) as GridEntity
	if wolf != null:
		wolf.acts = false
		var wolf_at := wolf.tile
		var ground := World.ground_uids(wolf_at)
		var gold_was := World.ground_gold(wolf_at)
		World.damage(wolf, wolf.hp, host, &"attack")
		_check(World.ground_gold(wolf_at) == gold_was, "a wolf falls: no gold")
		for cell: Vector2i in [wolf_at] + Array(World.DIRECTIONS).map(func(d: Vector2i) -> Vector2i: return wolf_at + d):
			for uid in World.ground_uids(cell):
				if not uid in ground:
					World.take_from_ground(cell, World.ground_uids(cell).find(uid))
					World.items.end(uid, "gone")


## A free floor cell 3 or more from [param entity], not a level link's (gold
## put down there would land beside it, and a body stood there leaves).
## Every unit [param entity] carries, stacks too (decision 619).
func _units_of(entity: GridEntity) -> Array[int]:
	var units: Array[int] = []
	for slot in entity.slots.size():
		units.append_array(World.slot_units(entity, slot))
	return units


func _plain_cell(entity: GridEntity) -> Vector2i:
	for cell: Vector2i in _main._terrain["floor"]:
		if World.distance(cell, entity.tile) >= 3 and World.is_free(cell) and not World.is_link_cell(cell) and not World.is_water(cell):
			return cell
	return _far_cell(entity)


func _test_bound() -> void:
	print("
== bound for life: the draugr's halves (decision 544) ==")
	var host := _player(Net.local_id)
	var owner := World.holder_key(host)
	var had_slots := host.slots.duplicate()
	var had_uids := host.slot_items.duplicate()
	var half := World.mint_bound("barrow_half", owner, host)
	_check(World.items.bound_to(half) == owner and World.items.history(half)["events"].back()["kind"] == "bound",
			"minted bound to its player, noted (%s)" % World.items.bound_to(half))
	World.items.bind(half, "player:someone else")
	_check(World.items.bound_to(half) == owner and World.items.character_of(half).is_empty(), "bound once, for life; no character")
	_check(not World.carries_bound(host, "barrow_half", owner), "not carried until it is put in a slot")
	var slot := host.slots.find("")
	_check(slot >= 0 and World.put_item(host, host, slot, half), "put in a free slot")
	_check(World.carries_bound(host, "barrow_half", owner) and not World.carries_bound(host, "barrow_half", "player:someone else")
			and not World.carries_bound(host, "return_token", owner), "carried: its own player's, of its own kind only")
	_check("bound" in World.item_note(half), "its note says so (%s)" % World.item_note(half))
	World.items.place(half, "zone/stranger", "zone/stranger", "a stranger")
	_check(World.items.bound_to(half) == owner, "taken by another, still bound to its player")
	_check(ItemBook.from_dict(World.items.to_dict()).bound_to(half) == owner, "saved and read back")
	_check(Items.def("barrow_half")["verb"].is_empty() and not Items.has_tag("barrow_half", "tool") and Items.def("return_token")["made"].is_empty(),
			"no verb, not a tool, not made: never named (365), never sold or made")
	World.set_slots(host, had_slots, had_uids)
	World.items.end(half, "gone")


func _test_battle_axe() -> void:
	print("
== the draugr's battle axe, left at his feet when he yields (decision 603, items' side) ==")
	var verb := Items.verb_of("battle_axe")
	_check(Items.def("battle_axe")["hands"] == 2 and is_equal_approx(Items.def("battle_axe")["weight"], 7.0) and verb["kind"] == "knockdown"
			and verb["arc"] == 1 and verb["down_ticks"] == 15 and is_equal_approx(verb["damage"], 1.6) and is_equal_approx(verb["speed"], 2.2) and verb["windup"] == 8,
			"two hands, 7 kg, a knockdown: arc 1, 15 ticks down, x1.6, x2.2 slower, wound up 8 (%s)" % [verb])
	_check(Items.def("battle_axe")["made"].is_empty() and Monster.kinds()["draugr"]["yields"] == [{"item": "battle_axe"}],
			"nobody makes one; the draugr's row yields it")
	var host := _player(Net.local_id)
	var imp := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "name": "YieldImp%d" % World.tick,
		"tile": _far_cell(host), "kind": "imp", "props": {"mass": 40.0, "sight_range": 0}}) as Monster
	imp.acts = false
	var row: Dictionary = Monster.kinds()["imp"]
	row["yields"] = [{"item": "battle_axe"}]
	var laid := imp.yielded()
	row["yields"] = []
	_check(laid.size() == 1 and World.items.id_of(laid[0]) == "battle_axe" and World.items.at_of(laid[0]).contains("@")
			and World.distance(_ground_cell(laid[0]), imp.tile) <= World.GROUND_SPILL and World.items.history(laid[0])["events"][0]["kind"] == "remains",
			"yielded: the axe on the ground at its feet, its remains (%s, it at %s)" % [World.items.at_of(laid[0]) if not laid.is_empty() else "", imp.tile])
	_check(imp.spawned and imp.yielded().is_empty(), "it stands; a row with no yields leaves nothing")
	for uid in laid:
		World.take_from_ground(_ground_cell(uid), World.ground_uids(_ground_cell(uid)).find(uid))
		World.items.end(uid, "gone")
	World.despawn(imp)


## Where a thing on the ground lies (its "zone@x,y").
func _ground_cell(uid: int) -> Vector2i:
	var xy := World.items.at_of(uid).get_slice("@", 1).split(",")
	return Vector2i(int(xy[0]), int(xy[1])) if xy.size() == 2 else World.NO_CELL


func _test_totem() -> void:
	print("\n== the Encolpion Amulet (was the Draugr's Totem): the charges on one thing that never leaves its player (decisions 573 amended, 714) ==")
	var host := _player(Net.local_id)
	var record: PlayerRecord = _main._records[Net.player_id]
	var had_slots := host.slots.duplicate()
	var had_uids := World.slot_uids(host)
	var had_barrow := record.barrow.duplicate()
	_check(World.totem_of(Net.player_id) == 0, "no totem before the draugr is beaten")
	var uid := World.mint_totem(host)
	var slot := host.slot_items.find(uid)
	_check(uid != 0 and slot >= 0 and slot < Items.PACK and World.mint_totem(host) == uid and World.totem_of(Net.player_id) == uid,
			"minted once, bound to its player, in the pack (slot %d); again, the same one" % slot)
	_check(World.items.bound_to(uid) == "player:" + Net.player_id and World.soulbound(uid), "bound for life, soulbound")
	_check(World.totem_add(uid, 5, 3) == 3 and World.totem_charges(uid) == 3 and World.totem_add(uid, 2, 3) == 0,
			"charges up to its capacity: 3 of 5 taken, the rest spill; full, none more")
	_check(World.totem_spend(uid) and World.totem_charges(uid) == 2, "one spent: 2 left")
	var note := World.item_note(uid)
	_check(note.begins_with("Encolpion Amulet") and "2 charges" in note and not "Aldous" in note
			and "another chance to fight" in str(Items.def(World.TOTEM)["about"]),
			"its note: its charges; its about the tip's (%s)" % note)
	var chest := _chest()
	var host_at := host.tile
	_beside(host, chest)
	var free := chest.slots.find("")
	_check(free < 0 or not World.try_transfer(host, host, slot, chest, free), "never put in a chest")
	_check(not World.try_drop(host, slot) and World.take_item(host, host, slot) == 0 and host.slot_items[slot] == uid,
			"never dropped, thrown or taken out of their slots")
	var other := (slot + 1) % Items.PACK
	_check(World.try_transfer(host, host, slot, host, other) and host.slot_items[other] == uid, "moved within their own pack: yes")
	_check(ItemBook.from_dict(World.items.to_dict()).charges_of(uid) == 2, "its charges saved and read back")
	record.barrow["tokens"] = 4
	_check(_main.migrate_totem(record) == uid and World.totem_charges(uid) == 6 and not record.barrow.has("tokens"),
			"a record's old tokens moved onto the totem, off the record")
	_check(_main.migrate_totem(record) == 0, "nothing more to move")
	# A saved totem (714): its old id reads as the amulet, the same uid, binding and charges.
	var saved := World.items.to_dict().duplicate(true)  # to_dict hands out the live entries.
	saved["book"][str(uid)]["id"] = "draugr_totem"
	var read := ItemBook.from_dict(saved)
	_check(read.id_of(uid) == World.TOTEM and read.charges_of(uid) == 6 and read.bound_to(uid) == "player:" + Net.player_id,
			"a saved Draugr's Totem reads back as the amulet: uid, binding and charges kept")
	var old_slots := host.slots.duplicate()
	old_slots[other] = "draugr_totem"
	World.set_slots(host, old_slots, World.slot_uids(host))
	_check(host.slots[other] == World.TOTEM and host.slot_items[other] == uid, "a saved slot holding the totem: the amulet, the same uid")
	# ui's quest reset (672 amended, items' side): the amulet gone, wherever.
	var cleared := World.reset_totem(Net.player_id)
	_check(cleared.size() == 1 and World.totem_of(Net.player_id) == 0 and host.slot_items.find(uid) < 0 and not World.items.has(uid),
			"reset: the amulet taken from the pack and ended (%s)" % [cleared])
	_check(World.reset_totem(Net.player_id).is_empty(), "reset again: nothing to clear")
	# The relic (714): a knight's remains, bound to its finder, consumed when given.
	var relic := World.mint_relic("Ser Aldric", 2, host)
	World.put_item(host, host, other, relic)
	_check(World.relic_of(relic) == {"knight": "Ser Aldric", "tier": 2} and World.soulbound(relic)
			and World.item_title(relic) == "the holy remains of Ser Aldric" and World.item_note(relic).begins_with("the holy remains of Ser Aldric"),
			"a relic: its knight and tier, soulbound, named for him (%s)" % World.item_note(relic))
	_check(ItemBook.from_dict(World.items.to_dict()).relic_of(relic) == {"knight": "Ser Aldric", "tier": 2}, "its knight and tier saved and read back")
	_check(World.take_item(host, host, other) == 0, "never taken out by the usual ways")
	_check(not World.consume(chest, relic, "given"), "consume: false from one who does not hold it")
	_check(World.consume(host, relic, "laid on the altar") and host.slots[other] == "" and not World.items.has(relic),
			"consume: out of the pack past the soulbound rule, ended")
	_check(World.relic_of(9999999).is_empty() and World.mint_relic("x", 1, null) == 0, "no relic: {}; no finder: none minted")
	# into_pack (714, dungeon's side (2)): a full pack gives up its last plain
	# thing, never a bound one; a pack all bound, the new one at their feet.
	var pack := Items.PACK_SLOTS.filter(func(i: int) -> bool: return i < host.slots.size())
	var before_slots := host.slots.duplicate()
	var before_uids := World.slot_uids(host)
	var full_slots := host.slots.duplicate()
	var full_uids := World.slot_uids(host)
	var bound: Array[int] = []
	for at: int in pack:
		var each := World.mint_relic("Ser Aldric", 0, host)
		bound.append(each)
		full_slots[at] = World.RELIC
		full_uids[at] = each
	var plain := World.items.mint("bandaging_kit", "made")
	full_slots[pack[0]] = "bandaging_kit"
	full_uids[pack[0]] = plain
	World.set_slots(host, full_slots, full_uids)
	var into := World.mint_relic("Ser Aldric", 1, host)
	_check(World.into_pack(host, into) == pack[0] and World.slot_uid(host, pack[0]) == into
			and pack.slice(1).all(func(at: int) -> bool: return World.soulbound(World.slot_uid(host, at))),
			"a full pack: the one plain thing goes to the ground for it, no bound thing moved")
	var spare := World.mint_relic("Ser Aldric", 2, host)
	_check(World.into_pack(host, spare) == -1 and not Array(World.slot_uids(host)).has(spare) and World.items.has(spare) and World.soulbound(spare),
			"a pack all bound: -1, the new one put down at their feet, still bound")
	for each in bound + [into]:
		if not World.consume(host, each, "test") and World.items.has(each):
			World.items.end(each, "test")  # The first, its slot given to the kit.
	# What they put down (the kit, the spare relic) taken up and ended.
	for cell: Vector2i in [host.tile] + World.DIRECTIONS.map(func(d: Vector2i) -> Vector2i: return host.tile + d):
		var on := Array(World.ground_uids(cell))
		for index in range(on.size() - 1, -1, -1):
			if on[index] in [plain, spare]:
				World.items.end(World.take_from_ground(cell, index), "test")
	World.set_slots(host, before_slots, before_uids)
	var sledge := Items.def("tomb_sledge")
	_check(int(sledge["hands"]) == 2 and float(sledge["weight"]) >= 9.0 and Items.has_tag("tomb_sledge", "trophy") and Items.has_tag("tomb_sledge", "weapon")
			and not Items.has_tag("tomb_sledge", "soulbound") and Items.stack_of("tomb_sledge") == 1,
			"the Tomb Sledge: two-handed, 9 kg, a weapon and a trophy, unbound, single")
	World.set_slots(host, had_slots, had_uids)
	World._relocate(host, host_at)
	record.barrow = had_barrow


func _test_cache() -> void:
	print("\n== a cache: each player's find, once (decision 599) ==")
	var host := _player(Net.local_id)
	var chest := _chest()
	var record: PlayerRecord = _main._records[Net.player_id]
	_check(Items.roll_loot("farmstead_cache", "x", 64).count("bandaging_kit") == 2, "the farmstead's table: two bandaging kits, a knife, maybe a pick")
	var rows: Array[String] = ["#######", "#.....#", "#######"]
	var markers := {Vector2i(1, 1): "chest", Vector2i(3, 1): "chest", Vector2i(5, 1): "start"}
	var config := {"name": "cache_test", "loot": {"chest": "supplies"}, "entities": [
		{"at": [1, 1], "props": {"cache": "farmstead_cache", "cache_place": "the old farmstead"}}, {"at": [3, 1], "props": {"cache": "no_such_cache"}}]}
	var level := Level.parse(Level.image_from_rows(Terrain.expand(rows), markers, config), null, config)
	var kept := {}
	for spec: Dictionary in level["entities"]:
		kept[spec["tile"]] = Items.tidy(spec.get("props", {}).get("slots", []), Chest.SLOTS)
	_check(kept.get(Vector2i(1, 1)) == Items.tidy([], Chest.SLOTS) and level["warnings"].any(func(w: String) -> bool: return "no_such_cache" in w),
			"a cache in a level keeps no slots, though the level stocks its chests; an unknown table is said (%s)" % [level["warnings"]])
	var had_slots := chest.slots.duplicate()
	chest.cache = "farmstead_cache"
	chest.cache_place = "the old farmstead"
	var host_at := host.tile
	_beside(host, chest)
	var had := _units_of(host)
	var ground_before := World.ground_uids(host.tile)
	_check(_main.search(host, chest), "searched: something found")
	var got: Array[int] = []
	for uid in _units_of(host):
		if not uid in had:
			got.append(uid)
	for uid in World.ground_uids(host.tile):
		if not uid in ground_before:
			got.append(uid)
	var ids: Array[String] = []
	for uid in got:
		ids.append(World.items.id_of(uid))
	_check(ids.count("bandaging_kit") == 2 and ids.count("knife") == 1 and ids.size() <= 4,
			"two bandaging kits and a knife (and maybe a pick), in hand, pack or at their feet (%s)" % [ids])
	_check(not got.is_empty() and World.story_line(got[0]).contains("found in the old farmstead"),
			"its story: found in the old farmstead (%s)" % (World.story_line(got[0]) if not got.is_empty() else ""))
	_check("farmstead_cache" in record.caches and not _main.search(host, chest) and chest.slots == had_slots,
			"once per player: searched again, nothing more; the chest's own slots untouched")
	_check(PlayerRecord.from_dict(record.to_dict()).caches == record.caches, "the record keeps it through a save")
	record.caches.erase("farmstead_cache")  # As another player's record, who has not searched it.
	var held_now := _units_of(host)
	var ground_now := World.ground_uids(host.tile)
	_check(_main.search(host, chest), "a player who has not searched it finds theirs")
	for uid in _units_of(host):
		if not uid in held_now:
			got.append(uid)
	for uid in World.ground_uids(host.tile):
		if not uid in ground_now:
			got.append(uid)
	for uid: int in World.items._book.keys():  # Every cached find, wherever it went (a pile may spill to the next cell).
		var events: Array = World.items.history(uid).get("events", [])
		if events.is_empty() or events[0]["kind"] != "cached":
			continue
		var at := World.items.at_of(uid)
		if World.slot_of_unit(host, uid) >= 0:
			World.take_units(host, [uid])
		elif at.contains("@"):
			var xy := at.get_slice("@", 1).split(",")
			var cell := Vector2i(int(xy[0]), int(xy[1]))
			World.take_from_ground(cell, World.ground_uids(cell).find(uid))
		World.items.end(uid, "gone")
	record.caches.erase("farmstead_cache")
	World._relocate(host, host_at)
	chest.cache = ""
	chest.cache_place = ""


func _test_stacks() -> void:
	print("\n== stacks: small things share a slot, each its own (decision 619) ==")
	_check(Items.stack_of("herbs") == 10 and Items.stack_of("antlers") == 5 and Items.stack_of("knife") == 1 and Items.stack_of("arrows") == 1,
			"herbs stack 10, antlers 5; a knife and a bundle of arrows alone")
	var odd := Items.read('{"items": [{"id": "blade", "tags": ["weapon"], "stack": 5}, {"id": "seed", "stack": 20}]}')
	_check(int(odd["blade"]["stack"]) == 1 and int(odd["seed"]["stack"]) == 20, "a weapon that says it stacks is held alone (warned)")
	var host := _player(Net.local_id)
	var had_slots := host.slots.duplicate()
	var had_uids := World.slot_uids(host)
	World.set_slots(host, Items.tidy([], Player.SLOTS), [])
	var cell := _plain_cell(host)
	World._relocate(host, cell)
	var bare_mass := host.mass
	var herbs: Array[int] = []
	for i in 3:
		herbs.append(World.items.mint("herbs", "gathered"))
		World.put_on_ground(herbs[i], cell)
	_check(World._ground_takes(PackedInt32Array()), "a bare cell takes anything")
	_check(World.try_pick_up(host, cell) and World.ground_at(cell).is_empty(), "F picks up the three herbs at once")
	var slot := World.slot_of_unit(host, herbs[0])
	_check(slot >= 0 and World.slot_count(host, slot) == 3 and host.slots.count("herbs") == 1,
			"one slot holds the three (%s, %s)" % [Array(host.slots), host.slot_counts])
	_check(host.slot_counts.size() == host.slots.size() and host.slot_counts[slot] == 3, "its count replicated (%s)" % host.slot_counts)
	_check(host.slot_notes.size() <= slot or not host.slot_notes[slot].begins_with("3 × "),
			"its note does not say so: the slot draws the count from slot_counts (619, ui's side)")
	_check(is_equal_approx(host.mass - bare_mass, 3 * Items.weight_of("herbs")), "weighed a unit at a time (%.2f)" % (host.mass - bare_mass))
	for each in herbs:
		_check(World.items.history(each)["holder"] == World.holder_key(host), "herb %d carried by them, its own history" % each)
	for i in 9:
		var more := World.items.mint("herbs", "gathered")
		herbs.append(more)
		World.put_on_ground(more, cell)
	World.try_pick_up(host, cell)
	var second := -1
	for i in host.slots.size():
		if host.slots[i] == "herbs" and i != slot:
			second = i
	_check(World.slot_count(host, slot) == 10 and second >= 0 and World.slot_count(host, second) == 2 and World.count_of(host, "herbs") == 12,
			"twelve: a full stack of ten and two beside it (%s)" % host.slot_counts)
	# A split, and a join.
	var free := host.slots.find("")
	_check(World.try_transfer(host, host, slot, host, free, 4) and World.slot_count(host, slot) == 6 and World.slot_count(host, free) == 4,
			"four split off onto an empty slot (%s)" % host.slot_counts)
	_check(World.try_transfer(host, host, free, host, second) and World.slot_count(host, second) == 6 and host.slots[free].is_empty(),
			"and joined onto the two (%s)" % host.slot_counts)
	_check(World.count_of(host, "herbs") == 12 and World.units(host, "herbs").size() == 12, "still twelve, each one its own")
	# A grave-marked herb keeps a slot of its own.
	var marked := World.items.mint("herbs", "gathered")
	World.items.mark_grave(marked, "a barrow")
	_check(not World.stacks_onto(World.slot_uid(host, slot), marked) and World.room_for(host, marked) != slot and World.room_for(host, marked) != second,
			"a grave-marked herb never hides in a clean stack")
	World.items.end(marked, "gone")
	# Put down a count.
	_check(World.try_drop(host, second, null, 3) and World.slot_count(host, second) == 3 and World.ground_at(cell).count("herbs") == 3,
			"three of six put down (%s)" % [World.ground_at(cell)])
	_check(World._ground_takes(World.ground_uids(cell)) and World.ground_uids(cell).size() == 3, "three herbs on a cell are one heap")
	World.try_pick_up(host, cell)
	_check(World.count_of(host, "herbs") == 12, "picked up again")
	# One at a time out (eaten, banked, sold).
	var before := World.slot_count(host, slot)
	var one := World.take_item(host, host, slot)
	_check(one in herbs and World.slot_count(host, slot) == before - 1 and World.items.at_of(one).is_empty(), "taken out: one unit, the rest stay")
	World.items.end(one, "gone")
	var first := World.slot_uid(host, slot)
	_check(World.take_units(host, [first]).size() == 1 and World.slot_count(host, slot) == before - 2 and World.slot_uid(host, slot) != first
			and World.slot_uid(host, slot) in herbs, "the first taken: the next stands for the stack")
	World.items.end(first, "gone")
	var copy := ItemBook.from_dict(JSON.parse_string(JSON.stringify(World.items.to_dict())))
	var head := World.slot_uid(host, slot)
	_check(copy.stack_of(head) == World.items.stack_of(head) and copy.stack_of(head).size() == before - 3, "a stack is saved with the book")
	# Put back as it was.
	for uid in _units_of(host):
		World.take_units(host, [uid])
		World.items.end(uid, "gone")
	World.set_slots(host, had_slots, had_uids)
	_check(World.items.orphans(_all_uids()).is_empty(), "and all put back, nothing in the book nobody holds (%s)" % [World.items.orphans(_all_uids())])


func _test_armour() -> void:
	print("\n== armour: one slot, worn, never held (decision 622) ==")
	_check(Items.CARRIED == 11 and Items.ARMOUR == 6 and Player.SLOTS == 11 and Companion.SLOTS == 11 and Items.PACK_SLOTS == [0, 1, 2, 3, 7, 8, 9, 10],
			"a seventh carried slot, the armour worn; the pack 8 round it (722)")
	_check(Items.armour_of("mail_armour").get("look") == "mail" and Items.armour_of("robes").get("look") == "robes"
			and Items.armour_of("knife").is_empty() and not Items.armour_of("plate_armour").has("range_steps"),
			"four kinds, each with its look and stats; a knife is not armour")
	var odd := Items.read('{"items": [{"id": "cloak", "armour": {"look": "fur"}}]}')
	_check(odd["cloak"]["armour"].is_empty(), "an unknown look is no armour (warned)")
	var shares := {"leather_armour": 0.2, "mail_armour": 0.25, "plate_armour": 0.2, "robes": 0.1}
	var all_on := true
	for id: String in shares:
		var on: Dictionary = Items.armour_of(id).get("on", {})
		all_on = all_on and is_equal_approx(float(on.get("arms", -1)), shares[id]) and is_equal_approx(float(on["arms"]) + float(on["body"]), 1.0)
	_check(all_on, "each armour says where its mass sits, arms and body adding to 1 (items-as-mass step 1)")
	var ons := Items.read('{"items": [{"id": "a", "armour": {"look": "mail", "on": {"arms": 1, "body": 3}}}, {"id": "b", "armour": {"look": "mail", "on": {"arms": -1}}}, {"id": "c", "armour": {"look": "mail", "on": "arms"}}]}')
	_check(ons["a"]["armour"]["on"] == {"arms": 0.25, "body": 0.75} and not ons["b"]["armour"].has("on") and not ons["c"]["armour"].has("on"),
			"shares not adding to 1 are scaled to it; a negative or a word is left out (all on the body, warned)")
	var old := PlayerRecord.from_dict({"player_id": "old", "tile": [1, 1], "slots": ["knife", "", "", "", "sword", ""], "items": [0, 0, 0, 0, 0, 0]})
	_check(old != null and old.slots.size() == Player.SLOTS and old.slots[Items.RIGHT_HAND] == "sword" and old.slots[Items.ARMOUR] == "",
			"a six-slot record from before armour: the hands where they were, the armour slot empty (%s)" % [Array(old.slots)])
	var host := _player(Net.local_id)
	var had_slots := host.slots.duplicate()
	var had_uids := World.slot_uids(host)
	World.set_slots(host, Items.tidy([], Player.SLOTS), [])
	var said: Array[String] = []
	var hear := func(_by: GridEntity, why: String) -> void: said.append(why)
	World.slot_refused.connect(hear)
	var bare := host.mass
	var leather := World.items.mint("leather_armour", "made")
	var cell := _plain_cell(host)
	World._relocate(host, cell)
	World.put_on_ground(leather, cell)
	_check(World.try_pick_up(host, cell) and World.slot_of_unit(host, leather) < Items.PACK, "picked up: into the pack, not a hand")
	var packed := World.slot_of_unit(host, leather)
	_check(not World.try_transfer(host, host, packed, host, Items.RIGHT_HAND) and said == ["armour is worn, not held"],
			"into a hand: refused, and they are told (%s)" % [said])
	_check(World.try_transfer(host, host, packed, host, Items.ARMOUR) and host.worn == "leather_armour"
			and is_equal_approx(host.mass - bare, Items.weight_of("leather_armour")), "worn: its slot, worn says so, its weight carried")
	_check(World.worn_armour(host).get("look") == "leather" and is_equal_approx(float(World.worn_armour(host)["on"]["arms"]), 0.2), "worn_armour reads its stats")
	# The bow under armour (decision 622, step 2): none caps the reach (622 amended);
	# the draw's time is the arms' load's (676), no longer the armour's own multiple.
	_give(host, "bow", Player.RIGHT_HAND)
	_give(host, "arrows", Player.LEFT_HAND)
	_check(World.try_stance(host, "draw"), "drawn in leather")
	host.raised_tick = World.tick - 11
	# 1.2 kg of leather on the arms beside the bow and arrows' 1.6: 2.8 of 16, 0.025 past the free 0.15.
	_check(is_equal_approx(host.load_arms, 2.8) and is_equal_approx(World.draw_quick(host), 1.0125),
			"in leather the arms carry 2.8 kg: the draw takes 1.0125 of the ticks (%s, %s)" % [host.load_arms, World.draw_quick(host)])
	host.raised = ""
	var plate := World.items.mint("plate_armour", "made")
	_check(World.try_transfer(host, host, Items.ARMOUR, host, 2) and World.put_item(host, host, Items.ARMOUR, plate) and host.worn == "plate_armour",
			"the leather off, plate on")
	World.try_stance(host, "draw")
	host.raised_tick = World.tick - 100
	_check(World.range_of(host) == 15 and World.longest_range(host) == 15 and World.draw_step(host) == 5 and is_equal_approx(World.draw_of(host), 1.0)
			and Items.damage_for(Items.verb_of("bow"), World.draw_step(host), 15) == 0.8,
			"in plate a bow held long stretches to 15 cells, as with none: armour caps no reach (622 amended) (%d)" % World.range_of(host))
	host.raised = ""
	World.try_transfer(host, host, Items.ARMOUR, host, 3)
	World.try_transfer(host, host, 2, host, Items.ARMOUR)
	var knife := World.items.mint("knife", "made")
	World.put_item(host, host, 0, knife)
	said.clear()
	_check(not World.try_transfer(host, host, 0, host, Items.ARMOUR) and said == ["only armour is worn there"] and host.worn == "leather_armour",
			"a knife onto the armour slot: refused, said (%s)" % [said])
	_check(World.try_transfer(host, host, Items.ARMOUR, host, 1) and host.worn == "", "taken off into the pack: nothing worn")
	World.slot_refused.disconnect(hear)
	for uid in _units_of(host):
		World.take_units(host, [uid])
		World.items.end(uid, "gone")
	World.set_slots(host, had_slots, had_uids)


func _test_grave() -> void:
	print("\n== grave goods: marked where they are minted (decision 555) ==")
	var rows: Array[String] = ["#######", "#.....#", "#.....#", "#######"]
	var markers := {Vector2i(1, 1): "chest", Vector2i(3, 1): "chest", Vector2i(2, 2): "monster_imp", Vector2i(4, 2): "monster_draugr", Vector2i(5, 2): "start"}
	var config := {"name": "grave_test", "grave_goods": true, "legend": {"monster_draugr": "#5a4636"},
		"entities": [{"at": [3, 1], "props": {"grave": false}}]}
	var level := Level.parse(Level.image_from_rows(Terrain.expand(rows), markers, config), null, config)
	var grave_at := {}
	for spec: Dictionary in level["entities"]:
		grave_at[spec["tile"]] = spec.get("props", {}).get("grave", false)
	_check(grave_at.get(Vector2i(1, 1)) == true and grave_at.get(Vector2i(2, 2)) == true and grave_at.get(Vector2i(3, 1)) == false,
			"the level's grave_goods: its chest and its imp; a marker's own false wins (%s)" % [grave_at])
	_check(grave_at.get(Vector2i(4, 2)) == true, "a kind with a class of its own, the draugr, is a monster too (%s)" % [grave_at])
	var imp: GridEntity = null
	for monster in World.monsters():
		if str(monster.spawn_spec.get("kind", "")) == "imp":
			imp = monster
			break
	_check(imp != null, "an imp to carry and drop grave goods")
	if imp == null:
		return
	var props: Dictionary = imp.spawn_spec.get("props", {})
	var had_props := props.duplicate()
	var had_slots := imp.slots
	_check(World.grave_from(imp).is_empty(), "no grave goods without the mark")
	props["grave"] = true
	imp.spawn_spec["props"] = props
	imp.slots = Items.tidy(["dagger"], Items.CARRIED)
	var held := World.slot_uid(imp, 0)
	_check(World.items.is_grave(held) and World.items.grave_of(held) == World._label_of(imp)
			and World.items.history(held)["events"].back()["kind"] == "grave goods",
			"what it carries is grave goods from it (%s)" % World.items.grave_of(held))
	var row: Dictionary = Monster.kinds()["imp"]
	var had_drops: Variant = row.get("drops")
	row["drops"] = [{"item": "ration"}]
	var had_purse: Variant = row.get("purse")
	row["purse"] = [0, 0]  # No gold here (decision 601 has its own test).
	var dropped := (imp as Monster).remains()
	row["purse"] = had_purse
	_check(dropped.size() == 1 and World.items.is_grave(dropped[0]), "and so is what it drops")
	_check("grave goods" in World.item_note(held) and World.story_line(held).ends_with("taken from the grave"),
			"its note and story say so (%s; %s)" % [World.item_note(held), World.story_line(held)])
	World.items.mark_grave(held, "somewhere else")
	_check(World.items.grave_of(held) == World._label_of(imp), "marked once, for life")
	_check(ItemBook.from_dict(World.items.to_dict()).is_grave(held) and not World.items.is_grave(0), "saved and read back; an unknown uid is not")
	if had_drops == null:
		row.erase("drops")
	else:
		row["drops"] = had_drops
	for uid in dropped:
		World.items.end(uid, "gone")
	World.items.end(held, "gone")
	imp.slots = had_slots
	imp.spawn_spec["props"] = had_props


func _test_bane() -> void:
	print("\n== bane and vengeance: a thing that fells enough of a kind is its bane; one whose holders a kind hurt most holds a grudge, paid in their felling; one growth per thing (decisions 417, 473) ==")
	var host := _player(Net.local_id)
	var far := _open_line(host, 2)
	_check(far != World.NO_CELL, "an open cell beside the host")
	if far == World.NO_CELL:
		return
	var d := (far - host.tile) / 2
	Items.set_growth_for_test({"bane_after": 3, "grudge_paid": 2, "grudge_after": 30})
	var grew := []
	var growing := func(_entity: GridEntity, _uid: int, mark: String, kind: String) -> void: grew.append([mark, kind])
	World.item_grew.connect(growing)
	var dagger := _give(host, "dagger", Player.RIGHT_HAND)
	World.items.give_character(dagger, "named")  # Only a thing with character grows (decision 472).
	var foe_of := func(kind: String) -> GridEntity:
		var foe := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "name": "BaneFoe%d" % World.tick,
			"tile": host.tile + d, "kind": kind, "props": {"sight_range": 0}}) as GridEntity
		foe.acts = false
		return foe
	var strike := func(foe: GridEntity) -> void:
		host._world_set_facing(d)
		host.next_attack_tick = 0
		host.next_move_tick = 0
		World.try_attack(host, foe)
		World._resolve_hits()
		while not World.ground_uids(host.tile + d).is_empty():
			World.items.end(World.take_from_ground(host.tile + d, 0), "gone")
	var hurt_by := func(foe: GridEntity, hp: int) -> void:
		host.hp = host.max_hp
		World.damage(host, hp, foe)
		host.hp = host.max_hp
	# A grudge (decision 473): one kind hurts its holders 30 hp, more than any other.
	var goblin: GridEntity = foe_of.call("goblin")
	hurt_by.call(goblin, 14)
	goblin.hp = 1
	strike.call(goblin)
	var wolf: GridEntity = foe_of.call("wolf")
	hurt_by.call(wolf, 12)
	_check(World.items.hurt_of(dagger) == {"goblin": 14, "wolf": 12} and World.items.grudge_of(dagger).is_empty() and grew.is_empty(),
			"a goblin hurts its holder 14, a wolf 12: counted, no grudge yet (%s)" % [World.items.hurt_of(dagger)])
	hurt_by.call(wolf, 12)
	hurt_by.call(wolf, 8)
	_check(World.items.grudge_of(dagger) == {"kind": "wolf", "paid": 0} and World.holder_grudge(host, "wolf") and grew.back() == ["grudge", "wolf"]
			and World.items.hurt_of(dagger) == {"wolf": 32, "goblin": 14},
			"wolves have hurt it 32 (30 here too), more than goblins' 14: it holds a grudge against wolves (%s)" % [World.items.hurt_of(dagger)])
	_check(World.item_note(dagger) == "dagger, vengeance on wolves", "and says so (%s)" % World.item_note(dagger))
	var plain := _give(host, "dagger", Player.LEFT_HAND)
	hurt_by.call(wolf, 15)
	_check(World.items.hurt_of(plain).is_empty() and World.items.grudge_of(plain).is_empty(), "a plain thing in the other hand keeps no tally (decision 472)")
	World.items.end(World.take_item(host, host, Player.LEFT_HAND), "gone")
	wolf.max_hp = 50
	wolf.hp = 50
	wolf.stunned_until_tick = 0
	strike.call(wolf)
	_check(World.is_stunned(wolf) and wolf.stunned_until_tick == World.tick + 4, "its blow on a wolf staggers it 4 ticks")
	wolf.hp = 1
	strike.call(wolf)
	_check(World.items.grudge_of(dagger).get("paid") == 1, "one wolf felled: paid one of two")
	var other: GridEntity = foe_of.call("wolf")
	other.hp = 1
	strike.call(other)
	_check(World.items.grudge_of(dagger).is_empty() and not World.holder_grudge(host, "wolf") and grew.back() == ["avenged", "wolf"]
			and World.items.history(dagger)["events"].any(func(e: Dictionary) -> bool: return e["kind"] == "avenged")
			and World.items.hurt_of(dagger) == {"goblin": 14},
			"two wolves: the grudge lifts, avenged in its history, and wolves' hurt starts over (%s)" % [World.items.hurt_of(dagger)])
	goblin = foe_of.call("goblin")
	hurt_by.call(goblin, 16)
	_check(World.items.grudge_of(dagger).get("kind") == "goblin" and grew.back() == ["grudge", "goblin"], "goblins reach 30: a grudge against them now")
	goblin.hp = 1
	strike.call(goblin)
	# A bane: one growth per thing, so the grudge gives way.
	for i in 3:
		var imp: GridEntity = foe_of.call("imp")
		imp.hp = 1
		strike.call(imp)
	_check(World.items.bane_of(dagger) == "imp" and World.holder_bane(host, "imp") and not World.holder_bane(host, "wolf")
			and grew.slice(-1) == [["bane", "imp"]], "three imps felled (3 here, 25 in play): the dagger is their bane (%s)" % [grew])
	_check(World.items.grudge_of(dagger).is_empty() and not World.holder_grudge(host, "goblin") and World.items.hurt_of(dagger).is_empty()
			and World.items.history(dagger)["events"].any(func(e: Dictionary) -> bool: return e["kind"] == "gave way"),
			"one growth per thing: its grudge on goblins gave way to the bane (decision 473)")
	_check(not World.holder_bane(host, "") and not World.holder_grudge(host, ""), "no kind: nobody's bane or grudge (enemy-ai's find)")
	_check(World.item_note(dagger) == "dagger, imp-bane", "its note says so (%s)" % World.item_note(dagger))
	var wolf3: GridEntity = foe_of.call("wolf")
	hurt_by.call(wolf3, 15)
	hurt_by.call(wolf3, 15)
	_check(World.items.grudge_of(dagger).is_empty() and World.items.hurt_of(dagger) == {"wolf": 30} and grew.back() == ["bane", "imp"],
			"a bane takes no grudge, though wolves hurt it 30 (%s)" % [World.items.hurt_of(dagger)])
	wolf3.hp = 1
	strike.call(wolf3)
	var back := ItemBook.from_dict(World.items.to_dict())
	_check(back.bane_of(dagger) == "imp" and back.hurt_of(dagger) == {"wolf": 30}, "the bane and the hurt saved and read back")
	World.item_grew.disconnect(growing)
	World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")
	Items.reset()


func _test_story() -> void:
	print("\n== a thing's story and the words for what it does (decision 421, for ui's tooltip) ==")
	var host := _player(Net.local_id)
	var dagger := _give(host, "dagger", Player.RIGHT_HAND)
	_check(World.story_line(dagger).is_empty(), "just taken up: no story yet")
	World.items._book[dagger]["carriers"][0]["held"] = DayNight.day_steps * 3
	var carrier: String = World.items.history(dagger)["carriers"][0]["name"]
	_check(World.story_line(dagger) == "story: carried by %s for 3 days" % carrier, "three days carried (%s)" % World.story_line(dagger))
	World.items.set_name(dagger, {"form": "holder_possessive", "holder": "Wren", "who": "companion:test:Wren", "made_step": World.steps,
		"text": "Wren's dagger"}, "quiet")
	World._show_notes(host)
	_check(World.story_line(dagger) == "story: carried by %s for 3 days; named for Wren" % carrier, "named (%s)" % World.story_line(dagger))
	_check(host.slot_notes[Player.RIGHT_HAND].split("\n")[-1] == World.story_line(dagger), "the note's last line (%s)" % [host.slot_notes])
	World.items.note(dagger, "avenged", "wolf")
	World.items.note(dagger, "avenged", "goblin_archer_of_the_long_marsh")
	_check(World.story_line(dagger).length() <= World.STORY_LONGEST and World.story_line(dagger).ends_with("avenged on wolves"),
			"too long: cut from the end to %d (%s)" % [World.STORY_LONGEST, World.story_line(dagger)])
	World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")
	_check(["hammer", "sword", "shield", "buckler", "giant_axe", "spear", "dagger", "bow"].all(
			func(id: String) -> bool: return not str(Items.verb_of(id).get("says", "")).is_empty()), "every weapon says what it does")
	_check(Items.verb_of("dagger")["says"] == "quick; twice the hurt from behind", "the dagger: %s" % Items.verb_of("dagger")["says"])
	_check(Items.naming()["strengths"].values().all(func(row: Dictionary) -> bool: return not str(row.get("says", "")).is_empty()),
			"every strength says what it means")
	_check(not str(Items.growth()["says"].get("bane", "")).is_empty() and not str(Items.growth()["says"].get("vengeance", "")).is_empty(),
			"and bane and vengeance")


func _test_bless() -> void:
	print("\n== the temple's blessing: a kept thing cleansed, no ill while blessed, lost if taken again (decision 424) ==")
	var host := _player(Net.local_id)
	var pets: Array = World.get_entities().filter(func(e: GridEntity) -> bool: return e is Companion)
	_check(not pets.is_empty(), "a companion to take it")
	if pets.is_empty():
		return
	var pet: GridEntity = pets[0]
	var dagger := _give(host, "dagger", Player.RIGHT_HAND)
	World.items.set_name(dagger, {"form": "holder_possessive", "holder": "Wren", "who": "companion:test:Wren", "made_step": World.steps,
		"text": "Wren's dagger"}, "quiet")
	World._taken(dagger, host, "")
	var me := World.holder_key(host)
	_check(World.items.kept_from(dagger) == "companion:test:Wren", "taken up, not given: kept from Wren (370)")
	World.items.bless(dagger, me)
	_check(World.items.kept_from(dagger).is_empty() and World.items.ill_of(dagger, me) == 0.0 and World.items.blessed_for(dagger) == me,
			"blessed for the host: cleansed, no longer kept, no ill")
	World._show_notes(host)
	_check(World.item_note(dagger).ends_with(", blessed") and World.story_line(dagger).contains("blessed at the temple"),
			"its note and story say so (%s | %s)" % [World.item_note(dagger), World.story_line(dagger)])
	World._taken(dagger, pet, me)
	_check(World.items.blessed_for(dagger) == World.holder_key(pet) and World.items.kept_from(dagger).is_empty(),
			"given by its owner: the blessing goes with it")
	World._taken(dagger, host, "")
	_check(World.items.blessed_for(dagger).is_empty() and World.items.kept_from(dagger) == "companion:test:Wren"
			and World.items.history(dagger)["events"].any(func(e: Dictionary) -> bool: return e["kind"] == "unblessed"),
			"taken from whom it was blessed for, not given: no longer blessed, and kept again")
	var back := ItemBook.from_dict(World.items.to_dict())
	World.items.bless(dagger, me)
	_check(ItemBook.from_dict(World.items.to_dict()).blessed_for(dagger) == me and back.blessed_for(dagger).is_empty(), "saved and read back")
	World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")


func _test_reforge() -> void:
	print("\n== the reforge: a named thing made another of the smith's, the same uid, its name and marks kept (decision 432) ==")
	_check(Items.reforge_cost("dagger", "sword") == {"by": "smith", "from": {"ore": 2, "wood": 1}, "steps": 1500},
			"a dagger into a sword: half the sword's ore and wood, rounded up; half its steps (%s)" % Items.reforge_cost("dagger", "sword"))
	_check(Items.reforge_cost("giant_axe", "dagger") == {"by": "smith", "from": {"ore": 1}, "steps": 600}, "a giant axe into a dagger: 1 ore, 600 steps")
	_check(Items.reforge_cost("dagger", "giant_axe").is_empty(), "not into more hands")
	_check(Items.reforge_cost("dagger", "buckler").is_empty() and Items.reforge_cost("dagger", "dagger").is_empty()
			and Items.reforge_cost("ration", "sword").is_empty(), "nor into the tanner's buckler, nor itself, nor from a ration")
	_check(not Items.reforge_targets("buckler").is_empty() and "giant_axe" not in Items.reforge_targets("sword"),
			"a buckler may become the smith's things (%s)" % [Items.reforge_targets("buckler")])
	_check(Items.strength_fits("quiet", "sword") and not Items.strength_fits("quiet", "shield") and Items.strength_fits("steady", "shield")
			and not Items.strength_fits("steady", "dagger") and Items.strength_fits("dread", "bow") and not Items.strength_fits("heavy", "hammer"),
			"strengths fit their verbs")
	var host := _player(Net.local_id)
	var dagger := _give(host, "dagger", Player.RIGHT_HAND)
	var uid := World.take_item(host, host, Player.RIGHT_HAND)
	_check(not World.items.reforge(uid, "sword"), "an unnamed dagger is not reforged")
	World.items.set_name(uid, {"form": "holder_possessive", "holder": "Wren", "who": "companion:test:Wren", "made_step": World.steps,
		"text": "Wren's dagger"}, "quiet")
	World.items.fell(uid, "imp")
	_check(World.items.reforge(uid, "sword") and World.items.id_of(uid) == "sword" and World.items.strength_of(uid) == "quiet"
			and World.items.felled_of(uid) == {"imp": 1} and World.items.name_of(uid)["holder"] == "Wren",
			"Wren's dagger into a sword: the same uid, its name, its quiet strength and its tally kept")
	_check(World.items.reforge(uid, "shield") and World.items.strength_of(uid).is_empty()
			and World.items.history(uid)["events"].back()["what"] == "sword into shield; quiet lost",
			"into a shield: quiet does not fit, lost, and the history says so (%s)" % World.items.history(uid)["events"].back())
	_check(World.story_line(uid).contains("reforged from a"), "its story tells it (%s)" % World.story_line(uid))
	World.items.end(uid, "gone")
	dagger = 0


func _test_names() -> void:
	print("\n== names from long-time holders and the strength they leave (decision 365) ==")
	var book := ItemBook.new()
	var uid := book.mint("dagger", "built")
	book.place(uid, "player:a", "player:a", "Ash")
	book.deed(uid, "player:a", "behind")
	book.deed(uid, "player:b", "behind")
	_check(book.history(uid)["carriers"][0]["deeds"] == {"behind": 1}, "a deed counts for who carries it, and nobody else")
	_check(book.name_due(uid, 0, 2).is_empty() and not book.name_due(uid, 0, 1).is_empty(), "named only with deeds enough")
	book.set_name(uid, {"form": "holder_possessive", "holder": "Ash", "made_step": 0, "text": "Ash's dagger"}, "quiet")
	book.set_name(uid, {"form": "holder_possessive", "holder": "Bo", "made_step": 0, "text": "Bo's dagger"}, "")
	_check(book.name_of(uid)["text"] == "Ash's dagger" and book.strength_of(uid) == "quiet" and book.name_due(uid, 0, 0).is_empty(),
			"one name for life: a second is refused")
	for i in ItemBook.MAX_EVENTS + 2:
		book.note(uid, "seen", str(i))
	var kinds: Array = book.history(uid)["events"].map(func(e: Dictionary) -> String: return e["kind"])
	_check(kinds.size() == ItemBook.MAX_EVENTS and kinds[0] == "built" and "named" in kinds, "its naming stays in its history (%s)" % [kinds])
	var back := ItemBook.from_dict(JSON.parse_string(JSON.stringify(book.to_dict())))
	_check(back.name_of(uid) == book.name_of(uid) and back.strength_of(uid) == "quiet" and back.history(uid)["carriers"][0]["deeds"] == {"behind": 1},
			"saved and read back: name, strength and deeds")
	_check(Items.strength_from({"behind": 6, "struck": 2}) == "quiet" and Items.strength_from({"behind": 2, "struck": 6}) == ""
			and Items.strength_from({"guarded": 3, "shot": 3}) == "steady", "the strength of the most-done deed; plain blows leave none; ties to the earlier")
	_check(Items.is_gear("dagger") and Items.is_gear("shield") and not Items.is_gear("meat") and not Items.is_gear("ration"), "weapons and tools are gear; food is not")
	var host := _player(Net.local_id)
	for slot in [Player.RIGHT_HAND, Player.LEFT_HAND]:
		if not host.slots[slot].is_empty():
			World.items.end(World.take_item(host, host, slot), "gone")
	var beside := World.NO_CELL
	for direction: Vector2i in World.DIRECTIONS:
		if beside == World.NO_CELL and World.is_free(host.tile + direction) and World.can_melee(host.tile, host.tile + direction):
			beside = host.tile + direction
	_check(beside != World.NO_CELL, "room beside the host")
	if beside == World.NO_CELL:
		return
	var imp := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "name": "NameImp%d" % World.tick,
		"tile": beside, "kind": "imp", "props": {"mass": 40.0, "sight_range": 0}}) as GridEntity
	imp.acts = false
	Items.set_naming_for_test({"held_days": 0.0, "deeds": 3})
	# Its own lore forms (decision 366's Lore.use): a draft holder form, so
	# the agreed gate is tested whatever names.json says.
	Lore.use([], [], [{"id": "holder_possessive", "how": "holder", "form": "{holder}'s {thing}", "status": "draft", "source": "lore"}])
	var dagger := _give(host, "dagger", Player.RIGHT_HAND)
	var stab := func() -> void:
		imp.hp = imp.max_hp
		World._relocate(imp, beside)
		imp._world_set_facing(imp.tile - host.tile)
		host.next_attack_tick = 0
		World.try_attack(host, imp)
		World.step()
	for i in 3:
		stab.call()
	var deeds: Dictionary = World.items.history(dagger)["carriers"][0]["deeds"]
	_check(deeds == {"behind": 3}, "three stabs in the back counted (%s)" % [deeds])
	_check(World.items.name_of(dagger).is_empty(), "no name while lore's holder form is only a draft (in play)")
	World.name_least = "draft"
	stab.call()
	var named := "%s's dagger" % World._label_of(host)
	_check(World.items.name_of(dagger).get("text") == named and World.items.strength_of(dagger) == "quiet"
			and World.items.name_of(dagger).get("form") == "holder_possessive",
			"the form counting, the next deed names it: %s, quiet from its stabs in the back" % World.items.name_of(dagger).get("text"))
	_check(host.slot_notes.size() == Items.CARRIED and host.slot_notes[Player.RIGHT_HAND].split("
")[0] == named + " (quiet)",
			"the hand shows it (%s)" % [host.slot_notes])
	_check(World.items.history(dagger)["events"][-1]["kind"] == "named", "its history says when")
	_check(is_equal_approx(float(Items.strength_value(World.slot_strength(host, Player.RIGHT_HAND), "noise", 1.0)), 0.5),
			"its blows make half the noise")
	# Time away is not held.
	var who := World._carrier_of(host)[0]
	var held := World.items.held_by(dagger, who)
	World._let_go_things(host)
	_steps(20)
	_check(World.items.held_by(dagger, who) == held, "gone from the world, the host holds it no longer (%d)" % World.items.held_by(dagger, who))
	World.set_slots(host, host.slots, host.slot_items)
	_steps(5)
	_check(World.items.held_by(dagger, who) == held + 5, "back, the time counts again (%d)" % World.items.held_by(dagger, who))
	World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")
	_check(host.slot_notes.is_empty(), "nothing named in hand: no names sent")
	# A quick bow; a set spear; dread.
	var bow := _give(host, "bow", Player.RIGHT_HAND)
	var verb := Items.verb_of("bow")
	host.raised = "draw"
	host.raised_tick = World.tick - roundi(float(verb["draw_full"]) * 0.8)
	var plain := World.draw_of(host)
	World.items.set_name(bow, {"form": "holder_possessive", "holder": "Ash", "made_step": 0, "text": "Ash's bow"}, "quick")
	_check(plain < 1.0 and is_equal_approx(World.draw_of(host), 1.0), "a quick bow is fully drawn sooner (%.2f, plain %.2f)" % [World.draw_of(host), plain])
	host.raised = ""
	World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")
	var spear := _give(host, "spear", Player.RIGHT_HAND)
	host.last_step_tick = World.tick - 3
	_check(not World.braced(host), "a spear is not braced 3 ticks after a step")
	World.items.set_name(spear, {"form": "holder_possessive", "holder": "Ash", "made_step": 0, "text": "Ash's spear"}, "set")
	_check(World.braced(host), "a set one is")
	_check(not World.holder_dread(host), "no dread in a set spear")
	World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")
	var sword := _give(host, "sword", Player.RIGHT_HAND)
	World.items.set_name(sword, {"form": "holder_possessive", "holder": "Ash", "made_step": 0, "text": "Ash's sword"}, "dread")
	_check(World.holder_dread(host), "a dread sword: its holder is dreaded (for enemy-ai)")
	World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")
	World.despawn(imp)
	World.name_least = "agreed"
	Items._naming = {}
	Lore.reload()


func _test_curse() -> void:
	print("\n== a named thing kept from its namer, not given, is ill-starred until it is back (decision 370) ==")
	var host := _player(Net.local_id)
	var pet: GridEntity = null
	for entity in World.get_entities():
		if entity is Companion and entity.spawned and entity.keeper_peer == host.owner_peer:
			pet = entity
	for slot in [Player.RIGHT_HAND, Player.LEFT_HAND]:
		if not host.slots[slot].is_empty():
			World.items.end(World.take_item(host, host, slot), "gone")
	var day := float(DayNight.day_steps)
	Items.set_curse_for_test({"full_days": 100.0 / day})  # Ill full after 100 steps held.
	var dagger := _give(host, "dagger", Player.RIGHT_HAND)
	var namer := World._carrier_of(host)[0]
	World.items.set_name(dagger, {"form": "holder_possessive", "holder": World._label_of(host), "who": namer, "made_step": 0,
		"text": "%s's dagger" % World._label_of(host)}, "quiet")
	World._slots_changed(host)
	# Down on the ground and taken up again by its namer: nothing.
	var cell := host.tile
	var dropped := World.put_on_ground(World.take_item(host, host, Player.RIGHT_HAND), cell)
	_check(World.try_pick_up(host, dropped) and World.items.kept_from(dagger).is_empty(), "its namer takes it up again: not kept")
	_check(pet != null, "a companion to take it")
	if pet == null:
		return
	for direction: Vector2i in World.DIRECTIONS:
		if pet.tile != host.tile + direction and World.is_free(host.tile + direction) and World.can_melee(host.tile, host.tile + direction) 				and World.distance(pet.tile, host.tile) > 1:
			World._relocate(pet, host.tile + direction)
	pet.acts = false
	# Handed over: a gift.
	var free := World.free_slot_for(pet, "dagger")
	var from_slot := host.slot_items.find(dagger)
	_check(World.try_transfer(host, host, from_slot, pet, free) and World.items.kept_from(dagger).is_empty(), "handed from its namer's hand: a gift, not kept (slot %d, %s, near %s)" % [free, pet.slots, World.reaches(host, pet)])
	World.try_transfer(host, pet, pet.slot_items.find(dagger), host, Player.RIGHT_HAND)
	_check(host.slot_items[Player.RIGHT_HAND] == dagger, "handed back")
	# Down, and taken up by another: kept.
	var landed := World.put_on_ground(World.take_item(host, host, Player.RIGHT_HAND), cell)
	var lying := World.take_from_ground(landed, Array(World.ground_uids(landed)).find(dagger))
	_check(lying == dagger, "lying where it was dropped")
	World.put_item(pet, pet, World.free_slot_for(pet, "dagger"), dagger)
	var slot := pet.slot_items.find(dagger)
	_check(World.items.kept_from(dagger) == namer, "taken up by another, not given: kept from its namer")
	_check(slot >= 0 and pet.slot_notes.size() > slot and pet.slot_notes[slot].split("
")[0].ends_with("(quiet, ill-starred)"), "and marked (%s)" % [pet.slot_notes])
	_check(World.items.history(dagger)["events"].any(func(e: Dictionary) -> bool: return e["kind"] == "kept"), "its history says so")
	var who := World._carrier_of(pet)[0]
	_steps(50)
	var half := World.items.ill_of(dagger, who)
	_check(absf(half - 0.5) < 0.05 and is_equal_approx(World.ill_of(pet), half), "ill grows as it is held: half way after half the time (%.2f)" % half)
	_steps(60)
	_check(is_equal_approx(World.items.ill_of(dagger, who), 1.0), "full at most (%.2f)" % World.items.ill_of(dagger, who))
	# Put down and taken up again: nothing cleared; the ill fades at half the rate meanwhile.
	var down := World.put_on_ground(World.take_item(pet, pet, slot), pet.tile)
	_steps(40)
	var faded := World.items.ill_of(dagger, who)
	_check(absf(faded - 0.8) < 0.05, "put down, it fades at half the rate (%.2f)" % faded)
	World.put_item(pet, pet, World.free_slot_for(pet, "dagger"), World.take_from_ground(down, Array(World.ground_uids(down)).find(dagger)))
	_check(World.items.kept_from(dagger) == namer, "taken up again: still kept")
	# Another taker: follows the thing.
	var held := World.items.ill_of(dagger, namer)
	World.try_transfer(pet, pet, pet.slot_items.find(dagger), host, Player.RIGHT_HAND)
	_check(World.items.kept_from(dagger).is_empty() and host.slot_notes[Player.RIGHT_HAND].split("
")[0].ends_with("(quiet)"),
			"back in its namer's hands: lifted (%s)" % host.slot_notes[Player.RIGHT_HAND])
	_check(World.items.history(dagger)["events"].any(func(e: Dictionary) -> bool: return e["kind"] == "back") and is_equal_approx(held, 0.0), "noted; the namer never gathered ill")
	_steps(20)
	_check(World.items.ill_of(dagger, who) < faded, "its keeper's ill fades away")
	# Taker only: a third holder gathers none.
	var book := ItemBook.new(func() -> int: return World.steps)
	var uid := book.mint("sword", "built")
	book.place(uid, "player:a", "player:a", "Ash")
	book.set_name(uid, {"form": "holder_possessive", "holder": "Ash", "who": "player:a", "made_step": 0, "text": "Ash's sword"}, "")
	book.place(uid, "", "")
	book.place(uid, "player:b", "player:b", "Bo")
	book.keep(uid, "player:b", "Bo")
	book.place(uid, "player:c", "player:c", "Cy")
	_steps(20)
	var thing := book.ill_of(uid, "player:c")
	Items.set_curse_for_test({"follows": "taker"})
	_check(thing > 0.1 and is_equal_approx(book.ill_of(uid, "player:c"), 0.0), "follows the thing: a third holder gathers ill (%.2f); the taker only: none" % thing)
	_check(Items.curse()["below_baseline"] == null, "what ill does waits on Jeff: below_baseline unset")
	World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")
	pet.acts = true
	Items._curse = {}


func _test_arrows() -> void:
	print("\n== arrows in a bundle: held in the bow's other hand, never used up, worn by blunt hits; flame burns, barbed bleeds (decision 375) ==")
	var host := _player(Net.local_id)
	for slot in [Player.RIGHT_HAND, Player.LEFT_HAND]:
		if not host.slots[slot].is_empty():
			World.items.end(World.take_item(host, host, slot), "gone")
	_give(host, "bow", Player.LEFT_HAND)
	var bundle := _give(host, "arrows", Player.RIGHT_HAND)
	_check(World.off_hand(host) == "draw" and World.bundle_slot(host) == Player.RIGHT_HAND, "the bow in either hand, the bundle in the other")
	_check(World.items.condition_of(bundle) == 10 and host.slot_notes[Player.RIGHT_HAND] == "bundle of arrows, 10 of 10",
			"a bundle is whole when made, and says so (%s)" % [host.slot_notes])
	var beside := World.NO_CELL
	for direction: Vector2i in World.DIRECTIONS:
		if beside == World.NO_CELL and World.is_free(host.tile + direction) and World.can_melee(host.tile, host.tile + direction):
			beside = host.tile + direction
	_check(beside != World.NO_CELL, "room beside the host")
	if beside == World.NO_CELL:
		return
	var pets: Array = World.get_entities().filter(func(e: GridEntity) -> bool: return e is Companion and e.acts)
	for pet: GridEntity in pets:
		pet.acts = false  # Nobody else fights the imp while it burns and bleeds.
	var imp := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule", "name": "ArrowImp%d" % World.tick,
		"tile": beside, "kind": "imp", "props": {"mass": 40.0, "sight_range": 0}}) as GridEntity
	imp.acts = false
	imp.hp = imp.max_hp
	World.shoot(host, Vector2(imp.tile - host.tile).angle(), 2)
	_check(host.slot_items[Player.RIGHT_HAND] == bundle and World.items.condition_of(bundle) == 10 and imp.ailments.is_empty(),
			"a shot uses nothing up; a plain arrow does nothing more")
	# Blunt hits wear it.
	imp.slots = Items.tidy(["", "", "", "", "hammer", ""], Items.CARRIED)
	imp.next_attack_tick = 0
	host.hp = host.max_hp
	World.try_attack(imp, host)
	World.step()
	_check(World.items.condition_of(bundle) == 9 and host.slot_notes[Player.RIGHT_HAND] == "bundle of arrows, 9 of 10",
			"a hammer's blow wears it (%s)" % host.slot_notes[Player.RIGHT_HAND])
	imp.slots = Items.tidy(["", "", "", "", "dagger", ""], Items.CARRIED)
	imp.next_attack_tick = 0
	World.try_attack(imp, host)
	World.step()
	_check(World.items.condition_of(bundle) == 9, "a dagger's does not")
	imp.slots = PackedStringArray()
	World.knock_down(host, imp, 1)
	_check(World.items.condition_of(bundle) == 8, "a knockdown wears it")
	_steps(3)
	World.items.set_condition(bundle, 1)
	World.try_stance(host, "draw")
	World._wear_bundle(host)
	_check(World.items.condition_of(bundle) == 0 and World.off_hand(host) == "" and host.raised == "" and not World.try_stance(host, "draw"),
			"spent: the draw drops, and there is nothing to draw")
	World.items.set_condition(bundle, 10)
	_check(World.off_hand(host) == "draw", "mended (the fletcher's job), it shoots again")
	var back := ItemBook.from_dict(JSON.parse_string(JSON.stringify(World.items.to_dict())))
	World.items.set_condition(bundle, 4)
	_check(back.condition_of(bundle) == 10 and ItemBook.from_dict(JSON.parse_string(JSON.stringify(World.items.to_dict()))).condition_of(bundle) == 4,
			"its condition is saved")
	World.items.set_condition(bundle, 3)
	# Another bundle on the ground: taken up, it swaps for the held one.
	var fresh := World.items.mint("arrows", "built")
	var lay := World.put_on_ground(fresh, host.tile)
	var swaps := []
	var swapped := func(by: GridEntity, taken: int, left: int) -> void: swaps.append([taken, left])
	World.bundle_swapped.connect(swapped)
	_check(World.try_pick_up(host, lay) and host.slot_items[Player.RIGHT_HAND] == fresh and Array(World.ground_uids(lay)) == [bundle]
			and swaps == [[fresh, bundle]] and World.item_note(bundle) == "bundle of arrows, 3 of 10",
			"a fresh bundle taken up: the worn one is put down in its place (%s)" % World.item_note(bundle))
	_check(World.try_pick_up(host, lay) and host.slot_items[Player.RIGHT_HAND] == bundle, "and back again: keeping the one you would rather mend")
	World.bundle_swapped.disconnect(swapped)
	World.items.end(World.take_from_ground(lay, 0), "gone")
	World.items.set_condition(bundle, 10)
	# Flame and barbed.
	World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")
	_give(host, "flame_arrows", Player.RIGHT_HAND)
	imp.hp = imp.max_hp
	World.shoot(host, Vector2(imp.tile - host.tile).angle(), 2)
	var shot_hp := imp.hp
	_check(imp.ailments.has("burn"), "a flame arrow sets it burning (%s)" % [imp.ailments])
	_steps(30)
	_check(imp.hp < shot_hp and not imp.ailments.has("burn"), "it burns a while, then goes out (%d -> %d)" % [shot_hp, imp.hp])
	World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")
	_give(host, "barbed_arrows", Player.RIGHT_HAND)
	imp.hp = imp.max_hp
	World.shoot(host, Vector2(imp.tile - host.tile).angle(), 2)
	shot_hp = imp.hp
	_check(imp.ailments.has("bleed"), "a barbed one bleeds it")
	_steps(60)
	_check(imp.hp == shot_hp - 2 and imp.ailments.has("bleed"), "1 hp every 30 ticks (%d -> %d)" % [shot_hp, imp.hp])
	World.despawn(imp)
	World.afflict(host, "bleed", 150, 30, 1)
	host.hp = host.max_hp - 3
	_steps(31)
	_check(host.ailments.has("bleed") and host.hp == host.max_hp - 4 and World.calm(host),
			"a bleed is no blow: 31 ticks on, bleeding, still calm enough to bandage")
	var kit := _give(host, "bandaging_kit", 0) if host.slots[0].is_empty() else 0
	var started := World.try_bandage(host, host)
	_check(started and not host.ailments.has("bleed"), "a bandage stops bleeding at once (started %s)" % started)
	if kit != 0:
		World.items.end(World.take_item(host, host, 0), "gone")
	for slot in [Player.RIGHT_HAND, Player.LEFT_HAND]:
		if not host.slots[slot].is_empty():
			World.items.end(World.take_item(host, host, slot), "gone")
	World.cure(host, "bleed")
	host.hp = host.max_hp
	for pet: GridEntity in pets:
		pet.acts = true


func _test_loot() -> void:
	print("
== loot: tables as data, named by a level for a chest or a monster; a monster drops what it carried (decision 330) ==")
	_check(Items.has_loot("supplies") and Items.has_loot("armoury") and Items.has_loot("pockets"), "levels/loot.json: %s" % [Items.loot_tables().keys()])
	var read := Items.read_loot('{"tables": {"t": [{"item": "no_such"}, {"item": "dagger", "count": [3], "chance": 4}, {"item": "ration", "count": [2, 1]}]}}')
	_check(read["t"] == [{"item": "dagger", "count": [1, 1], "chance": 1.0}, {"item": "ration", "count": [2, 2], "chance": 1.0}],
			"an unknown thing left out; a bad count [1, 1], most never under least; a chance kept to 0 to 1 (%s)" % [read["t"]])
	Items.add_loot_for_test("test_sure", [{"item": "ration", "count": [2, 2]}, {"item": "dagger"}, {"item": "sword", "chance": 0.0}])
	_check(Items.roll_loot("test_sure", "x", 9) == PackedStringArray(["ration", "ration", "dagger"]), "every row with chance 1, none with 0: two rations and a dagger")
	_check(Items.roll_loot("test_sure", "x", 2).size() == 2 and Items.roll_loot("no_such_table", "x", 4).is_empty(), "kept to the room there is; an unknown table gives nothing")
	var same := true
	for i in 20:
		same = same and Items.roll_loot("supplies", "seed%d" % i, 4) == Items.roll_loot("supplies", "seed%d" % i, 4)
	_check(same, "one seed, the same roll every time")
	var rows: Array[String] = ["#######", "#.....#", "#.....#", "#######"]
	var markers := {Vector2i(1, 1): "chest", Vector2i(3, 1): "chest", Vector2i(5, 1): "chest", Vector2i(2, 2): "monster_imp",
		Vector2i(4, 2): "monster_brute", Vector2i(5, 2): "start"}
	var config := {"name": "loot_test", "loot": {"chest": "test_sure", "brute": "test_sure"},
		"entities": [{"at": [1, 1], "props": {"slots": ["bandaging_kit", "", "", ""]}}, {"at": [3, 1], "loot": "no_such_table"},
			{"at": [2, 2], "loot": "test_sure"}]}
	var level := Level.parse(Level.image_from_rows(Terrain.expand(rows), markers, config), null, config)
	var by_tile := {}
	for spec: Dictionary in level["entities"]:
		by_tile[spec["tile"]] = spec
	var slots_at := func(cell: Vector2i) -> PackedStringArray: return by_tile[cell].get("props", {}).get("slots", PackedStringArray())
	_check(slots_at.call(Vector2i(1, 1)) == PackedStringArray(["bandaging_kit", "ration", "ration", "dagger"]),
			"a chest with the level's chest table: its own kit kept, the empty slots filled (%s)" % slots_at.call(Vector2i(1, 1)))
	_check(slots_at.call(Vector2i(3, 1)).is_empty() and level["warnings"].any(func(w: String) -> bool: return "no_such_table" in w),
			"a table that is not there: nothing, and a warning")
	_check(slots_at.call(Vector2i(2, 2)) == PackedStringArray(["ration", "ration", "dagger", ""]) and slots_at.call(Vector2i(4, 2))[2] == "dagger",
			"the imp its entry's table, the brute its kind's (%s, %s)" % [slots_at.call(Vector2i(2, 2)), slots_at.call(Vector2i(4, 2))])
	_check(Level.parse(Level.image_from_rows(Terrain.expand(rows), markers, config), null, config)["entities"] == level["entities"],
			"built again, stocked the same")
	var host := _player(Net.local_id)
	var foe: GridEntity = null
	for monster in World.monsters():
		foe = monster
		break
	_check(foe != null, "a monster to drop things")
	if foe == null:
		return
	foe.slots = PackedStringArray(["dagger", "", "ration", ""])
	var at := foe.tile
	var foe_row: Dictionary = Monster.kinds().get(str(foe.spawn_spec.get("kind", "")), {})
	var had_purse: Variant = foe_row.get("purse")
	foe_row["purse"] = [0, 0]  # Only what it carried here (decision 601 has its own test).
	World.damage(foe, 1000, host)
	foe_row["purse"] = had_purse
	var dropped := []
	for cell: Vector2i in World.zone.ground.keys():
		if World.distance(cell, at) <= 1:
			while not World.ground_uids(cell).is_empty():
				var uid := World.take_from_ground(cell, 0)
				dropped.append(World.items.id_of(uid))
				World.items.end(uid, "gone")
	dropped.sort()
	_check(not is_instance_valid(foe) or not foe.spawned, "the monster is dead")
	_check(dropped == ["dagger", "ration"], "what it carried lies where it fell (%s; taken up again)" % [dropped])
	var doc := MapDoc.new()
	doc.folder = preload("res://tests/test_ports.gd").scratch("items_test_builder/")
	doc.map = LevelMap.new(Vector2i(12, 12))
	for y in 12:
		for x in 12:
			doc.map.set_cell(Vector2i(x, y), "grass")
	doc.config = {"name": "Loot Test", "outdoor": true}
	var session := BuilderSession.new(doc, Rect2i(1, 1, 10, 10), "loot_test", StubClaude.new())
	_check(session.run_tool("place", {"at": [3, 3], "thing": "chest", "loot": "supplies"})["ok"]
			and session.run_tool("place", {"at": [5, 5], "thing": "imp", "loot": "pockets"})["ok"], "the builder places a chest and an imp, each with a table")
	var entries: Array = session.working.config.get("entities", [])
	_check(entries.any(func(entry: Dictionary) -> bool: return entry["at"] == [3, 3] and entry["loot"] == "supplies")
			and entries.any(func(entry: Dictionary) -> bool: return entry["at"] == [5, 5] and entry["loot"] == "pockets"), "named in their entries (%s)" % [entries])
	var refused := session.run_tool("place", {"at": [7, 7], "thing": "crate", "loot": "supplies"})
	var unknown := session.run_tool("place", {"at": [7, 7], "thing": "chest", "loot": "dragon_hoard"})
	_check(not refused["ok"] and not unknown["ok"] and "supplies" in unknown["text"],
			"a crate with a table, or a table that is not there: refused (%s / %s)" % [refused["text"], unknown["text"]])
	Items.reset()

func _test_icons() -> void:
	print("\n== icons: framed from the game's angle; headless, names only ==")
	var view := ItemIcons.view_basis()
	_check(view.z.y > 0.0, "the icon camera looks down on the thing (back axis %s)" % view.z)
	for bounds: AABB in [AABB(Vector3(-0.09, 0, -0.04), Vector3(0.18, 0.12, 0.08)),
			AABB(Vector3(2, -1, 5), Vector3(0.3, 0.9, 0.3)), AABB(Vector3.ZERO, Vector3(3, 0.2, 0.5))]:
		var fit := ItemIcons.frame(bounds, view)
		var camera: Transform3D = fit["transform"]
		var half: float = fit["size"] * 0.5
		var inside := true
		var touches := false
		for i in 8:
			var at := camera.affine_inverse() * bounds.get_endpoint(i)
			inside = inside and absf(at.x) <= half and absf(at.y) <= half and -at.z > 0.05 and -at.z < fit["far"]
			touches = touches or absf(at.x) > half / ItemIcons.MARGIN - 0.001 or absf(at.y) > half / ItemIcons.MARGIN - 0.001
		_check(inside and touches, "a %s box is all in frame and fills it (size %.2f)" % [bounds.size, fit["size"]])
	var long := AABB(Vector3(-0.15, 0, -0.15), Vector3(0.3, 0.9, 0.3))
	var laid := ItemIcons.pose(long.size)
	var turned := ItemIcons.frame(long, view, Transform3D(laid))
	_check(laid != Basis.IDENTITY and turned["size"] <= ItemIcons.frame(long, view)["size"] * 1.05,
			"a long thing (a bundle of wood) lies across the diagonal, framed as tight (%.2f)" % turned["size"])
	_check(ItemIcons.pose(Vector3(0.35, 0.45, 0.3)) == Basis.IDENTITY, "a sack stands as it is")
	var icons: ItemIcons = _main.item_icons
	_check(icons != null and _main.pack_panel.icons == icons, "the pack panel takes its icons from Main's ItemIcons")
	_check(icons.icon(KIT) == null and not icons.enabled, "headless, no icon is drawn")
	var host := _player(Net.local_id)
	var slot := host.slots.find("")
	_give(host, KIT, slot)
	_main.pack_panel.player = host
	_main.pack_panel._refresh()
	_check(_main.pack_panel.icon_in(true, slot) == null and _main.pack_panel.shown_in(true, slot) == Items.short_of(KIT),
			"so the pack shows the kit's name: \"%s\"" % _main.pack_panel.shown_in(true, slot))
	World.items.end(World.take_item(host, host, slot), "gone")


func _test_bandage() -> void:
	print("\n== bandaging: a kit, out of combat; then mending, a point at a time, while you walk away ==")
	var host := _player(Net.local_id)
	var pet: Companion = _main._companions.get(Net.player_id)
	var kit := _give(host, KIT, 2)
	# One imp kept, still and far off; the rest gone, so nothing wanders near.
	var imp: GridEntity = null
	for monster in World.monsters():
		if imp == null:
			imp = monster
			imp.acts = false
			World._relocate(imp, _far_cell(host))
		else:
			World.despawn(monster)
	World.damage(host, 8)
	var hurt := host.hp
	_check(not World.try_bandage(host, host), "hurt just now: not yet (out of combat first)")
	_steps(World.BANDAGE_CALM_TICKS)
	_main._e_target = null
	_main._e_held = true
	_main._e_since = Time.get_ticks_msec() - Main.BANDAGE_HOLD_MSEC
	_main._check_bandage_hold()
	_check(host.mending == 1 and not _main._e_held, "a while later the host holds E, no one under the cursor: bandages themselves")
	_check(not World.try_bandage(host, host), "not twice at once")
	_check(host.tending == String(host.name), "tending itself, for the views' kneel (%s)" % host.tending)
	_steps(World.BANDAGE_TICKS)
	_check(host.mending == 2 and World._mending[host]["left"] == World.BANDAGE_HEAL - 1 and host.hp == hurt + 1,
			"bandaged: the first point as it is done (713), mending now (%d more to come)" % (World.BANDAGE_HEAL - 1))
	_check(host.tending == "", "done: tending no one")
	World._relocate(host, _open_line(host, 1))
	_steps(World.BANDAGE_REGEN_TICKS * 3)
	_check(host.mending == 2 and World._mending[host]["left"] == World.BANDAGE_HEAL - 4 and host.hp >= hurt + 4,
			"walking about, a point every %d ticks: %d to %d" % [World.BANDAGE_REGEN_TICKS, hurt, host.hp])
	World.damage(host, 1)
	_steps(1)
	_check(host.mending == 0, "hurt again: the mending stops")
	_check(host.slot_items[2] == kit, "the kit is still in the pack: gear is not used up")
	_steps(World.BANDAGE_CALM_TICKS)
	World.try_bandage(host, host)
	World._relocate(host, _open_line(host, 1))
	_steps(1)
	_check(host.mending == 0 and host.tending == "", "moving while bandaging breaks it off, tending no one")
	_check(World.try_bandage(host, host) and host.mending == 1, "bandaging again")
	World.lay_downed(host, 1)
	_check(host.mending == 0 and host.tending == "" and World.bandage_broke_why == "hurt",
			"downed while bandaging: broken off, the patient free to be bandaged again (%d, %s)" % [host.mending, World.bandage_broke_why])
	World.raise_downed(host, host.hp)  # Up again (a downed body whose time runs out bleeds to death).
	if pet != null and pet.spawned:
		World.try_transfer(host, host, 2, pet, 0)
		World._relocate(pet, _open_line(host, 1))
		World.damage(host, 5)
		_steps(World.BANDAGE_CALM_TICKS)
		_check(World.try_bandage(pet, host) and host.mending == 1 and pet.tending == String(host.name),
				"%s, with the kit, bandages the host beside her, tending them" % pet.name)
		if imp != null:
			var was := imp.tile
			World._relocate(imp, _free_near(host, 3))
			_steps(1)
			_check(host.mending == 0 and pet.tending == "", "an imp comes within %d cells: broken off, tending no one" % World.BANDAGE_SAFE)
			_check(not World.try_bandage(pet, host), "and it cannot start with the imp near")
			World._relocate(imp, was)
		World.try_transfer(host, pet, 0, host, 2)
	World.items.end(World.take_item(host, host, 2), "gone")


## Jeff's bandage-kneel.md (decision 713): the heal as it is done, a
## companion bandaged from two cells, an E-hold out of reach not turned on
## yourself, and banked free steps dropped at the start.
func _test_bandage_reach() -> void:
	var host := _player(Net.local_id)
	var pet: GridEntity = null
	for entity in World.get_entities():
		if entity is Companion and entity.spawned and entity.keeper_peer == host.owner_peer:
			pet = entity
	_check(pet != null, "a companion to bandage")
	if pet == null:
		return
	var kit := _give(host, "bandaging_kit", 2) if host.slots[2].is_empty() else 0
	var host_was := host.tile
	World._relocate(pet, _open_line(host, 1))
	print("\n== bandaging from two cells, the heal as it is done (decision 713) ==")
	var parked: Dictionary[GridEntity, Vector2i] = {}  # The run's monsters (and any respawned) out of the way: calm here.
	var park := func() -> void:
		for monster: GridEntity in World.monsters():
			if not parked.has(monster):
				parked[monster] = monster.tile
				World._occupancy.erase(monster.tile)
				monster.acts = false
		World._roster_current = false
	park.call()
	var settle := func() -> void:
		World._bandaging.erase(host)
		World._mending.erase(host)
		World._mending.erase(pet)
		host.mending = 0
		pet.mending = 0
		host.tending = ""
		_steps(World.BANDAGE_CALM_TICKS + 1)
		park.call()
	var pet_was := pet.tile
	settle.call()
	# The first hp the tick it is done.
	host.hp = host.max_hp - 5
	_check(World.try_bandage(host, host), "case: bandaging yourself starts")
	_steps(World.BANDAGE_TICKS)
	_check(host.mending == 2 and host.hp == host.max_hp - 4, "case: done, the first hp at once, not a second later (%d)" % host.hp)
	# A companion two cells off, a clear line.
	settle.call()
	var two := _open_line(host, 2)
	World._relocate(pet, two)
	pet.hp = pet.max_hp - 6
	_check(World.distance(host.tile, pet.tile) == 2 and World.bandage_refusal(host, pet) == "" and World.try_bandage(host, pet),
			"case: a companion two cells off, nothing between: bandaged (%s -> %s, '%s')" % [host.tile, pet.tile, World.bandage_refusal(host, pet)])
	World._relocate(pet, host.tile + (two - host.tile) / 2)
	_steps(1)
	_check(pet.mending == 1 and host.tending == String(pet.name), "case: she steps closer within reach: it goes on")
	var far := host.tile
	for cell: Vector2i in _main._terrain["floor"]:  # Five off: her follow step back still leaves her out of reach.
		if World.distance(cell, host.tile) == 5 and World.is_free(cell) and not World.zone.ground.has(cell):
			far = cell
			break
	World._relocate(pet, far)
	_check(World.bandage_refusal(host, pet) == "not_beside", "case: out of reach: not begun, too far (%s -> %s)" % [host.tile, pet.tile])
	_steps(1)
	_check(pet.mending == 0 and host.tending == "" and World.bandage_broke_why == "patient_moved",
			"case: she goes out of reach: broken off, she moved (%s)" % World.bandage_broke_why)
	# An E-hold on her out of reach says why; it never bandages you instead.
	settle.call()
	host.hp = host.max_hp - 3
	_main._e_target = pet
	_main._e_held = true
	_main._e_since = Time.get_ticks_msec() - 10000
	World._relocate(pet, far)
	_main._check_bandage_hold()
	_check(host.mending == 0 and pet.mending == 0, "case: E held on her out of reach: not you instead, not her (the server's line says why)")
	# Banked free steps dropped as it starts.
	settle.call()
	World.free_input(host, Vector2(1, 0), 1.0)
	World.free_input(host, Vector2(1, 0), 1.0)
	var queued := host.free_inputs.size()
	_check(World.try_bandage(host, host) and host.free_inputs.is_empty(),
			"case: free walk, %d steps banked: dropped as the bandage starts" % queued)
	_steps(2)
	_check(host.mending == 1 and host.tending == String(host.name), "case: and it is still running two ticks on (not broken by a banked step)")
	settle.call()
	host.hp = host.max_hp
	pet.hp = pet.max_hp
	World._relocate(pet, pet_was)
	World._relocate(host, host_was)
	for monster: GridEntity in parked:
		World._occupancy[parked[monster]] = monster
		monster.acts = true
	World._roster_current = false
	if kit != 0:
		World.items.end(World.take_item(host, host, 2), "gone")



## Jeff's inventory (decision 722): a pack of 8, double-click equips into
## the right place or not at all, his own 48-slot chest at a town's locker.
func _test_inventory() -> void:
	print("\n== the pack of 8, double-click equip, the locker's own chest (decision 722) ==")
	var host := _player(Net.local_id)
	var record: PlayerRecord = _main._records[Net.player_id]
	var had_slots := host.slots.duplicate()
	var had_uids := World.slot_uids(host)
	var had_at := host.tile
	var empty: Array = []
	empty.resize(Items.CARRIED)
	empty.fill("")
	World.set_slots(host, empty)  # Its own things put back at the end.
	_check(host.slots.size() == 11 and Items.PACK_SLOTS.size() == 8 and not Items.is_pack(Items.RIGHT_HAND) and not Items.is_pack(Items.ARMOUR)
			and Items.is_pack(7) and Items.is_pack(10), "case: 11 slots, the pack 8 (0-3 and 7-10), the hands and armour not in it")
	var old := PlayerRecord.from_dict({"player_id": "old", "tile": [1, 1], "slots": ["ration", "", "", "", "sword", "", "robes"]})
	_check(old.slots.size() == 11 and old.slots[0] == "ration" and old.slots[Items.RIGHT_HAND] == "sword" and old.slots[Items.ARMOUR] == "robes"
			and old.slots[10] == "", "case: a record saved with 7 slots reads as 11, everything where it was")
	# Double-click equips.
	var sword := _give(host, "sword", 0)
	_check(World.try_equip(host, host, 0) == "" and host.slots[Items.RIGHT_HAND] == "sword" and host.slots[0] == "",
			"case: a one-handed weapon to the right hand")
	var dagger := _give(host, "dagger", 1)
	_check(World.try_equip(host, host, 1) == "" and host.slots[Items.RIGHT_HAND] == "dagger" and host.slot_items[1] == sword,
			"case: another: swapped, the sword into the slot it left")
	var shield := _give(host, "shield", 2)
	_check(World.try_equip(host, host, 2) == "" and host.slots[Items.LEFT_HAND] == "shield", "case: a shield to the left hand")
	var axe := _give(host, "giant_axe", 3)
	_check(World.try_equip(host, host, 3) == "" and host.slots[Items.RIGHT_HAND] == "giant_axe" and host.slots[Items.LEFT_HAND] == ""
			and host.slot_items.has(dagger) and host.slot_items.has(shield) and Items.is_pack(host.slot_items.find(shield)),
			"case: a two-handed one: both hands, the dagger and the shield into the pack")
	var shield_at := host.slot_items.find(shield)
	_check(World.try_equip(host, host, shield_at) == "" and host.slots[Items.LEFT_HAND] == "shield" and host.slots[Items.RIGHT_HAND] == ""
			and Items.is_pack(host.slot_items.find(axe)), "case: the shield with the axe held: the axe into the pack")
	var mail := _give(host, "mail_armour", World.free_pack_slot(host))
	var mail_at := host.slot_items.find(mail)
	_check(World.try_equip(host, host, mail_at) == "" and host.slots[Items.ARMOUR] == "mail_armour" and host.slots[mail_at] == "",
			"case: armour to the armour slot")
	var robes := _give(host, "robes", World.free_pack_slot(host))
	var robes_at := host.slot_items.find(robes)
	_check(World.try_equip(host, host, robes_at) == "" and host.slots[Items.ARMOUR] == "robes" and host.slot_items[robes_at] == mail,
			"case: other armour: swapped, the mail into its slot")
	_check(World.try_equip(host, host, Items.ARMOUR) == "" and host.slots[Items.ARMOUR] == "" and Items.is_pack(host.slot_items.find(robes)),
			"case: double-click the armour: off, into the pack")
	var fillers: Array[int] = []
	while World.free_pack_slot(host) >= 0:
		fillers.append(_give(host, "knife", World.free_pack_slot(host)))
	_check(World.try_equip(host, host, Items.LEFT_HAND).begins_with("no room") and host.slots[Items.LEFT_HAND] == "shield",
			"case: the pack full: the shield stays on, and why")
	var sword_at := host.slot_items.find(sword)
	World.try_equip(host, host, sword_at)  # The sword in the right hand, the shield in the left.
	fillers.append(_give(host, "knife", sword_at))  # The pack full again.
	var axe_at := host.slot_items.find(axe)
	_check(World.try_equip(host, host, axe_at).begins_with("no room") and host.slots[Items.RIGHT_HAND] == "sword" and host.slots[Items.LEFT_HAND] == "shield",
			"case: a two-handed one with both hands full and the pack full: nothing moves")
	World.items.end(World.take_item(host, host, host.slot_items.find(fillers[0])), "gone")
	var herbs := _give(host, "herbs", World.free_pack_slot(host))
	_check(World.try_equip(host, host, host.slot_items.find(herbs)) == "" and host.slots[Items.RIGHT_HAND] == "herbs",
			"case: a held thing that is no weapon goes to the right hand too")
	_clear(host)
	# The locker: his own chest, at a town's locker, seen by him alone.
	var prop_at := _free_near(host, 2)
	var prop := _main._spawn({"script": "res://sim/chest.gd", "name": "TestLocker", "tile": prop_at}) as Chest
	prop.locker = true
	_beside(host, prop)
	var kit := _give(host, "bandaging_kit", 0)
	var kit2 := _give(host, "bandaging_kit", 7)
	var held := _give(host, "dagger", Items.RIGHT_HAND)
	var locker: Locker = _main.open_locker(host, prop)
	_check(locker != null and locker.slots.size() == Locker.LOCKER_SLOTS and locker.tile == prop.tile and World._occupancy.get(prop.tile) == prop
			and locker.opened == 1 and World.locker_of(Net.player_id) == locker, "case: opened at the locker: his chest of 48, on its cell, the locker still there")
	_check(locker._visible_to(host.owner_peer) == World.peer_sees(host.owner_peer, locker.zone) and not locker._visible_to(host.owner_peer + 1000),
			"case: sent to him alone")
	_check(_main.deposit_all(host, locker) == 2 and locker.slots[0] == "bandaging_kit" and World.slot_count(locker, 0) == 2
			and host.slots[0] == "" and host.slots[7] == "" and host.slots[Items.RIGHT_HAND] == "dagger",
			"case: deposit unequipped: the pack's two kits as one stack, the dagger in hand kept")
	_check(record.locker_slots[0] == "bandaging_kit" and record.locker_items[0] in [kit, kit2], "case: his record has it at once")
	_check(_main._move_slot(host, locker, 0, host) and host.slots[0] == "bandaging_kit" and World.slot_count(host, 0) == 2 and locker.slots[0] == "",
			"case: double-click it in the chest: the whole stack back to the pack")
	_check(_main._move_slot(host, host, 0, locker) and locker.slots[0] == "bandaging_kit" and host.slots[0] == "", "case: double-click it in the pack: the stack in")
	_check(not _main._move_slot(host, host, Items.RIGHT_HAND, locker) and host.slots[Items.RIGHT_HAND] == "dagger", "case: a hand's thing is not deposited")
	var saved := record.to_dict()
	var back := PlayerRecord.from_dict(saved.duplicate(true))
	_check(back.locker_slots[0] == "bandaging_kit" and back.locker_items[0] == record.locker_items[0] and back.locker_slots.size() == Locker.LOCKER_SLOTS,
			"case: saved and read back with the record")
	_check(PlayerRecord.from_dict({"player_id": "x", "tile": [1, 1]}).locker_slots.count("") == Locker.LOCKER_SLOTS
			and not PlayerRecord.new().to_dict().has("locker") or PlayerRecord.new().to_dict()["locker"].is_empty(), "case: none saved: empty, nothing written")
	var snapshot_entries := Snapshot._entries(World.get_entities())
	_check(not snapshot_entries.any(func(e: Dictionary) -> bool: return str(e.get("script", "")).ends_with("locker.gd")), "case: never in the world's snapshot")
	World.despawn(locker)
	_check(World.locker_of(Net.player_id) == null and World.items.has(record.locker_items[0]), "case: closed: gone from the world, its things still in the book")
	locker = _main.open_locker(host, prop)
	_check(locker != null and locker.slots[0] == "bandaging_kit" and World.slot_count(locker, 0) == 2 and locker.opened == 1, "case: opened again: the same things")
	# Stacking (722): tokens and the heavy sacks stack; gear and bound things never.
	_check(Items.stack_of("barrow_half") == 10 and Items.stack_of("ore_sack") == 5 and Items.stack_of("stamina_potion") == 5
			and Items.stack_of("sword") == 1 and Items.stack_of("encolpion_amulet") == 1 and Items.stack_of("mail_armour") == 1 and Items.stack_of("arrows") == 1,
			"case: tokens, sacks and drinks stack; weapons, the amulet, armour and arrow bundles stay single")
	_clear(locker)
	World.despawn(locker)
	World.despawn(prop)
	_clear(host)
	World.set_slots(host, had_slots, had_uids)
	World._relocate(host, had_at)



## Everything in [param entity]'s slots ended and the slots emptied.
func _clear(entity: GridEntity) -> void:
	for slot in entity.slots.size():
		for uid in World.slot_units(entity, slot):
			World.items.end(uid, "gone")
	World.set_slots(entity, [])


func _steps(count: int) -> void:
	for i in count:
		World.step()


## A free floor cell beyond BANDAGE_SAFE of [param entity].
func _far_cell(entity: GridEntity) -> Vector2i:
	for cell: Vector2i in _main._terrain["floor"]:
		if World.distance(cell, entity.tile) > World.BANDAGE_SAFE + 1 and World.is_free(cell):
			return cell
	return entity.tile


## A free floor cell [param cells] or so from [param entity].
func _free_near(entity: GridEntity, cells: int) -> Vector2i:
	for cell: Vector2i in _main._terrain["floor"]:
		if World.distance(cell, entity.tile) == cells and World.is_free(cell):
			return cell
	return entity.tile


func _test_restart() -> void:
	print("\n== a restart keeps every instance and its history ==")
	var host := _player(Net.local_id)
	var uid := host.slot_items[1]
	var history := World.items.history(uid)
	var count := World.items.size()
	_main._save_state()
	await _restart()
	host = _player(Net.local_id)
	_check(host.slots[1] == KIT and host.slot_items[1] == uid, "the host has the same kit (%s)" % [host.slot_items])
	var after := World.items.history(uid)
	_check(after["events"] == history["events"] and after["carriers"].size() == history["carriers"].size(),
			"with its history (%s)" % [after["events"]])
	_check(World.items.size() == count, "the book as big as it was (%d)" % World.items.size())
	var lying: Array = []
	for cell: Vector2i in World.zone.ground:
		lying.append_array(Array(World.ground_uids(cell)))
	_check(lying.size() == 1 and World.items.id_of(lying[0]) == "wood_bundle"
			and World.zone.piles.values().filter(func(pile: GroundPile) -> bool: return not pile.ids.is_empty()).size() == 1,
			"the wood still lies where it was, the same thing, its pile there (%s)" % [lying])
	_check(World.items.orphans(_all_uids()).is_empty(), "and nothing in it that nobody holds (%s)" % [World.items.orphans(_all_uids())])


func _test_migration() -> void:
	print("\n== a save from before instances ==")
	await _restart(func(data: Dictionary) -> void:
		data.erase("items")
		for zone: Dictionary in data["zones"].values():
			for entry: Dictionary in zone["entities"]:
				entry.erase("items")
		for record: Dictionary in data["players"]:
			record.erase("items")
			if record.get("companion") is Dictionary:
				record["companion"].erase("items"))
	var host := _player(Net.local_id)
	var uid := host.slot_items[1]
	_check(host.slots[1] == KIT and uid != 0, "the host's kit is there, an instance again (%d)" % uid)
	_check(World.items.history(uid)["events"][0]["kind"] == "migrated", "come from the old save (%s)" % [World.items.history(uid)])
	_check(World.items.orphans(_all_uids()).is_empty(), "nothing leaked")


func _test_rebuild() -> void:
	print("\n== a rebuilt room ends what its chests held ==")
	var chest := _chest()
	var host := _player(Net.local_id)
	_beside(host, chest)
	World.try_transfer(host, host, 1, chest, 0)
	var uid := chest.slot_items[0]
	_main._start_level(false, true)
	chest = _chest()
	_check(not World.items.has(uid), "the kit left in the chest is gone from the book")
	_check(World.zone.ground.is_empty() and World.zone.piles.is_empty(), "and what lay on the ground with it")
	_check(chest.slots[0] == KIT and World.slot_uid(chest, 0) != uid, "the rebuilt chest has a new one from the level")
	_check(World.items.orphans(_all_uids()).is_empty(), "nothing leaked (%s)" % [World.items.orphans(_all_uids())])


## A restart; [param edit] (given the snapshot's data) changes the saved
## file between the old server's last save and the new one's load.
func _restart(edit := Callable()) -> void:
	remove_child(_main)
	_main.free()
	World.clear_zones()
	World.items = ItemBook.new()  # Only what the snapshot holds comes back.
	if edit.is_valid():
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Net.state_path))
		edit.call(data)
		var file := FileAccess.open(Net.state_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame


func _print_history(uid: int) -> void:
	var history := World.items.history(uid)
	print("    #%d %s, at %s" % [uid, Items.name_of(history["id"]), history["at"]])
	for row: Dictionary in history["carriers"]:
		print("      carried by %s for %d steps%s" % [row["name"], row["held"], " (now)" if row["since"] >= 0 else ""])
	for event: Dictionary in history["events"]:
		print("      step %d: %s %s, %s %s" % [event["step"], event["kind"], event["what"], event["zone"], event["tile"]])


## Every uid anyone holds: entities' slots and the records' (companions
## kept there too).
func _all_uids() -> Array:
	var uids := []
	for entity in World.get_entities():
		uids.append_array(Array(World.slot_uids(entity)))
	for cell: Vector2i in World.zone.ground:
		uids.append_array(Array(World.ground_uids(cell)))
	if World.stockpile != null:
		uids.append_array(Array(World.stockpile.all_items()))
	for record: PlayerRecord in _main._records.values():
		uids.append_array(Array(record.slot_items))
		uids.append_array(record.companion.get("items", []))
	return uids.filter(func(uid: Variant) -> bool: return int(uid) != 0)


func _give(entity: GridEntity, id: String, slot: int) -> int:
	var uid := World.items.mint(id, "built")
	World.put_item(entity, entity, slot, uid)
	return uid


## A cell [param cells] away from [param entity] in a straight line with
## every cell on the way free and open; World.NO_CELL if none.
func _open_line(entity: GridEntity, cells: int) -> Vector2i:
	for direction: Vector2i in World.DIRECTIONS:
		var at := entity.tile
		var open := true
		for i in cells:
			if World._terrain_blocks_step(at, direction, false, false) or not World.is_free(at + direction) \
					or World.zone.ground.has(at + direction):
				open = false
				break
			at += direction
		if open:
			return at
	return World.NO_CELL


func _beside(entity: GridEntity, chest: Chest) -> void:
	for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if World.is_free(chest.tile + offset) and World.can_melee(chest.tile + offset, chest.tile):
			World._relocate(entity, chest.tile + offset)
			return


func _chest() -> Chest:
	for entity in World.get_entities():
		if entity is Chest:
			return entity
	return null


func _player(peer: int) -> Player:
	var player: Player = _main._players.get(peer)
	return player if is_instance_valid(player) and player.spawned else null


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
