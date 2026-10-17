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
	_test_axe()
	_test_spear()
	_test_pickup()
	_test_names()
	_test_curse()
	_test_arrows()
	_test_loot()
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
	_check(Items.yield_of("meat") == {"food": 1} and Items.value_of("antlers") == 5, "meat banks as food; antlers are worth 5")
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
	_check(Array(record.companion.get("items", [])) == [0, uid, 0, 0, 0, 0], "her player's record has its instance")
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
	_check(host.slots[1] == KIT and host.slots.size() == 6, "a pack of 4 and two hands; the kit in the pack")
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
	_check(World.items.at_of(wood) == "%s@%d,%d" % [World.zone.name, cell.x, cell.y] and World.items.history(wood)["holder"] == "",
			"the wood knows where it lies, carried by nobody")
	var host_mass := host.mass
	_check(World.try_pick_up(host, cell) and host.slot_items[Player.RIGHT_HAND] == wood, "picked up again: into the right hand")
	_check(not World.zone.piles.has(cell) and World.ground_at(cell).is_empty(), "and the ground is bare")
	_check(host.mass > host_mass, "it weighs again")
	World.try_drop(host, Player.RIGHT_HAND)
	var kits: Array[int] = []
	for i in 4:
		var uid := World.items.mint(KIT, "built")
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
	var purse := _give(host, "coin_purse", slot)
	var player_id: String = host.get("player_id")
	var gold := World.gold_of(player_id)
	_check(World.try_use(host, slot), "the host opens the coin purse")
	_check(World.gold_of(player_id) == gold + 10 or World.economy == null, "10 gold: %d to %d" % [gold, World.gold_of(player_id)])
	_check(host.slots[slot].is_empty() and not World.items.has(purse), "the purse is gone (opened)")
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
	var shot := func(by: GridEntity, at: Vector2i, strength: float) -> void: shots.append([by, at, strength])
	World.loosed.connect(shot)
	_check(World.off_hand(host) == "draw" and World.try_stance(host, "draw") and host.raised == "draw", "a bow, and a bundle of arrows in the other hand: the right button draws it")
	host.raised_tick = World.tick - 3
	_check(World.draw_of(host) == 0.0 and not World.try_loose(host, host.tile + Vector2i(4, 0)) and shots.is_empty() and host.raised == "",
			"let go before draw_min (5 ticks): no shot, the bow lowered")
	World.try_stance(host, "draw")
	host.raised_tick = World.tick - 10
	_check(is_equal_approx(World.draw_of(host), 0.5), "drawn 10 ticks of 20: half (%.2f)" % World.draw_of(host))
	host.raised_tick = World.tick - 40
	var aim := host.tile + Vector2i(4, 0)
	_check(World.try_loose(host, aim) and shots.size() == 1 and shots[0] == [host, aim, 1.0] and host.raised == "",
			"drawn past draw_full: loosed at the aim, full strength, for combat to shoot (%s)" % [shots])
	_check(not World.try_stance(host, "block"), "a bow is no shield")
	World.loosed.disconnect(shot)
	print("\n== the bow shoots: the first body on the line, harder the longer the draw (decision 335) ==")
	var imp: GridEntity = null
	for monster in World.monsters():
		imp = monster
		break
	var mark := _open_line(host, 4)
	_check(imp != null and mark != World.NO_CELL, "an imp, and an open line 4 cells long")
	if imp != null and mark != World.NO_CELL:
		var line := World.shot_line(host.tile, mark, 8)
		_check(line.size() >= 4 and line[3] == mark and line.all(func(cell: Vector2i) -> bool: return World.distance(host.tile, cell) <= 8),
				"the line runs through the aim and on, never past 8 cells (%s)" % [line])
		var near := host.tile + (mark - host.tile) / 2
		World._relocate(imp, mark)
		var ends := []
		var seen := func(to: Vector2i) -> void: ends.append(to)
		host.shot.connect(seen)
		var hp := imp.hp
		_check(World.shoot(host, mark + (mark - host.tile), 1.0) == imp and imp.hp == hp - 4 and ends == [mark],
				"a full draw aimed past it: the imp, the first body, hit for 4 (a blow of 2, the bow's 2) (%d -> %d); the arrow ends there" % [hp, imp.hp])
		hp = imp.hp
		_check(World.shoot(host, mark, 0.5) == imp and imp.hp == hp - 2, "a half draw: 2 (%d -> %d)" % [hp, imp.hp])
		_check(World.shoot(host, mark, 0.1) == imp and imp.hp == hp - 3, "a short draw: still at least 1")
		World._relocate(imp, _far_cell(host))
		hp = imp.hp
		_check(World.shoot(host, near, 1.0) == null and imp.hp == hp, "nothing on the line: nothing hit")
		host.shot.disconnect(seen)
		World.try_stance(host, "draw")
		host.raised_tick = World.tick - 30
		var stepped := false
		for direction: Vector2i in World.DIRECTIONS:
			if World.is_free(host.tile + direction):
				host.next_move_tick = 0
				stepped = World.try_move(host, direction)
				break
		_check(stepped and host.raised == "draw" and host.raised_tick == World.tick and World.draw_of(host) == 0.0,
				"a step while drawn: still drawn, but the draw starts again")
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
	_check(by_tile[Vector2i(1, 1)] == PackedStringArray(["", "", "", "", "spear", "shield"]), "an entry's wields: spear and shield in the hands (%s)" % by_tile[Vector2i(1, 1)])
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
	_check(World.shoot(host, imp.tile, 1.0) == imp and imp.hp == hp, "a shot into a raised shield: taken on it (%d -> %d)" % [hp, imp.hp])
	World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")
	imp.raised = ""
	imp.slots = PackedStringArray()
	imp.acts = true


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
	_check(host.slot_notes.size() == Items.CARRIED and host.slot_notes[Player.RIGHT_HAND] == named + " (quiet)",
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
	_check(slot >= 0 and pet.slot_notes.size() > slot and pet.slot_notes[slot].ends_with("(quiet, ill-starred)"), "and marked (%s)" % [pet.slot_notes])
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
	_check(World.items.kept_from(dagger).is_empty() and host.slot_notes[Player.RIGHT_HAND].ends_with("(quiet)"),
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
	World.shoot(host, imp.tile, 1.0)
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
	World.shoot(host, imp.tile, 1.0)
	var shot_hp := imp.hp
	_check(imp.ailments.has("burn"), "a flame arrow sets it burning (%s)" % [imp.ailments])
	_steps(30)
	_check(imp.hp < shot_hp and not imp.ailments.has("burn"), "it burns a while, then goes out (%d -> %d)" % [shot_hp, imp.hp])
	World.items.end(World.take_item(host, host, Player.RIGHT_HAND), "gone")
	_give(host, "barbed_arrows", Player.RIGHT_HAND)
	imp.hp = imp.max_hp
	World.shoot(host, imp.tile, 1.0)
	shot_hp = imp.hp
	_check(imp.ailments.has("bleed"), "a barbed one bleeds it")
	_steps(60)
	_check(imp.hp == shot_hp - 2 and imp.ailments.has("bleed"), "1 hp every 30 ticks (%d -> %d)" % [shot_hp, imp.hp])
	World.despawn(imp)
	World.afflict(host, "bleed", 150, 30, 1)
	host.hp = host.max_hp - 3
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
	foe.slots = PackedStringArray(["dagger", "", "coin_purse", ""])
	var at := foe.tile
	World.damage(foe, 1000, host)
	var dropped := []
	for cell: Vector2i in World.zone.ground.keys():
		if World.distance(cell, at) <= 1:
			while not World.ground_uids(cell).is_empty():
				var uid := World.take_from_ground(cell, 0)
				dropped.append(World.items.id_of(uid))
				World.items.end(uid, "gone")
	dropped.sort()
	_check(not is_instance_valid(foe) or not foe.spawned, "the monster is dead")
	_check(dropped == ["coin_purse", "dagger"], "what it carried lies where it fell (%s; taken up again)" % [dropped])
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
	_steps(World.BANDAGE_TICKS)
	_check(host.mending == 2 and World._mending[host]["left"] == World.BANDAGE_HEAL, "bandaged: mending now (%d hp to come)" % World.BANDAGE_HEAL)
	World._relocate(host, _open_line(host, 1))
	_steps(World.BANDAGE_REGEN_TICKS * 3)
	_check(host.mending == 2 and World._mending[host]["left"] == World.BANDAGE_HEAL - 3 and host.hp >= hurt + 3,
			"walking about, a point every %d ticks: %d to %d" % [World.BANDAGE_REGEN_TICKS, hurt, host.hp])
	World.damage(host, 1)
	_steps(1)
	_check(host.mending == 0, "hurt again: the mending stops")
	_check(host.slot_items[2] == kit, "the kit is still in the pack: gear is not used up")
	_steps(World.BANDAGE_CALM_TICKS)
	World.try_bandage(host, host)
	World._relocate(host, _open_line(host, 1))
	_steps(1)
	_check(host.mending == 0, "moving while bandaging breaks it off")
	if pet != null and pet.spawned:
		World.try_transfer(host, host, 2, pet, 0)
		World._relocate(pet, _open_line(host, 1))
		World.damage(host, 5)
		_steps(World.BANDAGE_CALM_TICKS)
		_check(World.try_bandage(pet, host) and host.mending == 1, "%s, with the kit, bandages the host beside her" % pet.name)
		if imp != null:
			var was := imp.tile
			World._relocate(imp, _free_near(host, 3))
			_steps(1)
			_check(host.mending == 0, "an imp comes within %d cells: broken off" % World.BANDAGE_SAFE)
			_check(not World.try_bandage(pet, host), "and it cannot start with the imp near")
			World._relocate(imp, was)
		World.try_transfer(host, pet, 0, host, 2)
	World.items.end(World.take_item(host, host, 2), "gone")


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
	_check(lying.size() == 1 and World.items.id_of(lying[0]) == "wood_bundle" and World.zone.piles.size() == 1,
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
