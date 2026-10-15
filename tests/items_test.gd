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
	_main._toss_target = cart
	_main._toss_from = _main.get_global_mouse_position()
	_main._release_toss(host)
	_check(_main.pack_panel.other == cart and _main.pack_panel.title_shown(false) == "Cart",
			"a plain right click on it beside you opens it: \"%s\"" % _main.pack_panel.title_shown(false))
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
	_check(Items.def("giant_axe")["hands"] == 2 and Items.def("bow")["hands"] == 2, "the giant axe and the bow take both hands")
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
	for slot in [Player.RIGHT_HAND, Player.LEFT_HAND]:
		World.items.end(World.take_item(host, host, slot), "gone")


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
	_check(World.try_bandage(host, host) and host.mending == 1, "a while later the host bandages themselves")
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
