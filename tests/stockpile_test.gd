extends Node
## The town's stockpile: a test town (made in code, no level file) with a
## stockpile place the town holds, a depot chest in it, a stray depot
## outside it and a plain chest with a bandaging kit. Picking the kit up
## banks nothing; putting it in the depot banks it (the slot empties, the
## ledger says who and when); a stray depot, or one whose place the
## goblins hold, refuses; resources count up and are taken only for the
## town's use; a restart keeps the store; a snapshot from before the
## stockpile, or with nonsense in it, loads as much as makes sense.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const TOWN := "sp_town"
const STORE := "sp_town/store"
const KIT := "bandaging_kit"

var _failures := 0
var _main: Node


func _ready() -> void:
	World.set_process(false)
	Net.port = preload("res://tests/test_ports.gd").of(17794)
	Net.companions = false
	Net.state_path = preload("res://tests/test_ports.gd").scratch("stockpile_test_world.json")
	if FileAccess.file_exists(Net.state_path):
		DirAccess.remove_absolute(Net.state_path)
	_register_town()
	Net.map_name = TOWN
	await _boot()

	_test_boot()
	_test_pickup_banks_nothing()
	_test_banking()
	_test_refused()
	_test_resources()
	_test_resource_items()
	await _test_restart()
	await _test_hauling()
	await _test_cart()
	_test_old_and_odd_snapshots()

	remove_child(_main)
	_main.free()
	World.clear_zones()
	DirAccess.remove_absolute(Net.state_path)
	Net.state_path = ""
	Net.map_name = ""
	Level.unregister(TOWN)
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## sp_town: 12 x 8 cells of stone in a wall; the start at (2, 2); the store
## (a stockpile the town holds) at (5, 3), radius 2, its depot at (5, 2); a
## stray depot at (9, 2) outside it; a chest with the kit at (9, 5).
func _register_town() -> void:
	var rows: Array[String] = []
	for y in 15:
		rows.append("#".repeat(23) if y == 0 or y == 14 else "#" + ".".repeat(21) + "#")
	var markers := {Vector2i(2, 2): "start", Vector2i(5, 2): "chest", Vector2i(9, 2): "chest", Vector2i(9, 5): "chest", Vector2i(1, 6): "cart"}
	Level.register(TOWN, Level.image_from_rows(rows, markers), null, {
		"name": "Stockpile town", "centre": [6, 4], "starts": [[2, 2]],
		"entities": [
			{"at": [5, 2], "name": "Depot1", "props": {"depot": true}},
			{"at": [9, 2], "name": "StrayDepot", "props": {"depot": true}},
			{"at": [9, 5], "name": "Chest1", "props": {"slots": [KIT, "", "", ""]}},
			{"at": [1, 6], "name": "Cart1"},
		],
		"places": {"store": {"at": [5, 3], "kind": "stockpile", "radius": 2, "holder": "town", "name": "the stockpile"}},
	})


## Main, booted; Holdings take in the test town too (levels made in code are
## not among Level.names).
func _boot() -> void:
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	var names := Level.names()
	names.append(TOWN)
	World.holdings.rebind(WorldMap.build(names))
	for i in 3:
		World.step()


func _test_boot() -> void:
	print("\n== the town, its stockpile place and depot ==")
	var level := Level.load_level(TOWN)
	_check(level["warnings"].is_empty(), "the town loads cleanly (%s)" % [level["warnings"]])
	_check(World.stockpile != null and World.stockpile.places().is_empty(), "World has a stockpile, nothing in it yet")
	_check(World.holdings.place(STORE).get("kind") == "stockpile" and World.holdings.holder(STORE) == "town",
		"the store is a stockpile place the town holds (%s)" % [World.holdings.place(STORE)])
	var depot := _entity("Depot1") as Chest
	_check(depot != null and depot.depot and not (_entity("Chest1") as Chest).depot, "Depot1 is a depot, Chest1 is not")
	_check(Stockpile.place_at(World.holdings, TOWN, Vector2i(5, 2)) == STORE
		and Stockpile.place_at(World.holdings, TOWN, Vector2i(9, 2)).is_empty(), "the depot is in the store's ground, the stray one is not")


func _test_pickup_banks_nothing() -> void:
	print("\n== picking loot up counts for nothing ==")
	var host := _player(Net.local_id)
	World._relocate(host, Vector2i(9, 4))
	_check(World.try_transfer(host, _entity("Chest1"), 0, host, 0), "the host takes the kit from Chest1")
	_check(Array(host.slots) == [KIT, "", "", "", "", ""], "it's in the host's pack (%s)" % [Array(host.slots)])
	_check(World.stockpile.count(STORE, KIT) == 0 and World.stockpile.places().is_empty(), "and the stockpile has nothing")


func _test_banking() -> void:
	print("\n== the depot banks what is put in ==")
	var host := _player(Net.local_id)
	var depot := _entity("Depot1")
	World._relocate(host, Vector2i(5, 3))
	World.steps = 1234
	var uid := World.slot_uid(host, 0)
	var who := World._label_of(host)
	_check(World.try_transfer(host, host, 0, depot, 2), "the host puts the kit in the depot")
	_check(Array(host.slots) == ["", "", "", "", "", ""] and Array(depot.slots) == ["", "", "", ""],
		"the pack's slot is empty, and so is the depot (%s, %s)" % [Array(host.slots), Array(depot.slots)])
	_check(World.stockpile.count(STORE, KIT) == 1 and World.stockpile.items(STORE) == _ints([uid])
		and World.stockpile.item_ids(STORE) == _strings([KIT]), "the store holds the kit, by its uid #%d (%s)" % [uid, World.stockpile.items(STORE)])
	var history := World.items.history(uid)
	_check(World.items.at_of(uid) == Stockpile.holder(STORE) and history.get("holder") == ""
		and history["events"].back()["kind"] == "banked", "in the book it is at the store, carried by nobody, its last event banked (%s)" % [history])
	_check(history["carriers"].any(func(row: Dictionary) -> bool: return int(row["since"]) < 0),
		"and the host's time carrying it is counted (%s)" % [history["carriers"]])
	var ledger := World.stockpile.ledger(STORE)
	_check(ledger.size() == 1 and ledger[0] == {"step": 1234, "what": KIT, "count": 1, "by": who, "from": who, "uid": uid},
		"its ledger: who, which thing and at which world step (%s)" % [ledger])
	_check(not World.try_transfer(host, depot, 0, host, 0), "nothing to take back out of the depot")


func _test_refused() -> void:
	print("\n== a depot outside a town-held stockpile refuses ==")
	var host := _player(Net.local_id)
	World.set_slots(host, [KIT, "", "", ""])
	World._relocate(host, Vector2i(9, 3))
	_check(not World.try_transfer(host, host, 0, _entity("StrayDepot"), 0), "the stray depot refuses the kit")
	_check(Array(host.slots) == [KIT, "", "", "", "", ""] and World.stockpile.count(STORE, KIT) == 1, "it stays in the pack (%s)" % [Array(host.slots)])
	World._relocate(host, Vector2i(5, 3))
	World.holdings.take(STORE, "goblins")
	_check(not World.try_transfer(host, host, 0, _entity("Depot1"), 0), "with the goblins holding the store, its depot refuses")
	_check(Array(host.slots) == [KIT, "", "", "", "", ""] and World.stockpile.count(STORE, KIT) == 1, "the kit stays, the store keeps its one")
	World.holdings.take(STORE, "town")
	_check(World.try_transfer(host, host, 0, _entity("Depot1"), 0), "the town takes it back: the depot banks again")
	_check(World.stockpile.count(STORE, KIT) == 2, "two kits now (%d)" % World.stockpile.count(STORE, KIT))


func _test_resources() -> void:
	print("\n== resources count up, and only the town's work takes them ==")
	var stock := World.stockpile
	_check(stock.deposit(STORE, "gold", 10, "Bo", "castle") and stock.deposit(STORE, "ore", 5, "Bo", "mine"), "10 gold and 5 ore banked")
	_check(stock.resources(STORE) == {"gold": 10, "ore": 5, "wood": 0, "cloth": 0, "food": 0}, "counted (%s)" % [stock.resources(STORE)])
	_check(not stock.deposit(STORE, "dragon", 1) and not stock.deposit(STORE, KIT, 1) and not stock.deposit(STORE, "ore", 0)
		and not stock.deposit("", "ore", 1), "no depositing of what is not a resource (gear is banked by uid), of nothing, or nowhere")
	_check(stock.take(STORE, "ore", 3, "smith: a blade") and stock.count(STORE, "ore") == 2, "the smith takes 3 ore: 2 left")
	_check(not stock.take(STORE, "ore", 3) and stock.count(STORE, "ore") == 2, "3 more is more than there is: nothing taken")
	var kit := stock.items(STORE)[0]
	_check(not stock.bank(STORE, kit) and not stock.bank(STORE, 99999), "a uid already here, or not in the book, is not banked")
	_check(stock.take_item(STORE, kit, "shop") and stock.count(STORE, KIT) == 1 and World.items.at_of(kit) == "",
		"the shop takes a kit: 1 left, the taken one nowhere in the book until it is put somewhere")
	_check(stock.ledger(STORE).back() == {"step": World.steps, "what": KIT, "count": -1, "by": "shop", "from": "", "uid": kit},
		"the ledger says why (%s)" % [stock.ledger(STORE).back()])
	_check(not stock.take_item(STORE, kit), "it can't be taken twice")
	var host := _player(Net.local_id)
	_check(World.put_item(host, host, 1, kit) and host.slots[1] == KIT and World.items.has(kit),
		"the town hands it to a player (World.put_item): the same thing, history and all")
	var depot := _entity("Depot1")
	_check(World.try_transfer(host, host, 1, depot, 0) and stock.items(STORE).has(kit), "and it can be banked again")
	var other := Stockpile.new()
	for i in Stockpile.LEDGER_SIZE + 5:
		other.deposit("x/y", "wood", 1)
	_check(other.ledger("x/y").size() == Stockpile.LEDGER_SIZE and other.count("x/y", "wood") == Stockpile.LEDGER_SIZE + 5,
		"the ledger keeps the last %d lines; the count keeps everything" % Stockpile.LEDGER_SIZE)


func _test_resource_items() -> void:
	print("\n== a sack of ore is banked as its ore ==")
	var host := _player(Net.local_id)
	World.set_slots(host, ["ore_sack", "", "", ""])
	var sack := World.slot_uid(host, 0)
	_check(Items.yield_of("ore_sack") == {"ore": 5} and World.items.has(sack), "a sack of ore yields 5 ore, and is a thing in the book (#%d)" % sack)
	_check(World.try_transfer(host, host, 0, _entity("Depot1"), 0), "the host puts it in the depot")
	_check(World.stockpile.count(STORE, "ore") == 7 and World.stockpile.count(STORE, "ore_sack") == 0 and host.slots[0] == "",
		"the store has 5 more ore (%d), no sack, and the pack's slot is empty" % World.stockpile.count(STORE, "ore"))
	_check(not World.items.has(sack), "the sack's instance has ended (banked)")
	var line: Dictionary = World.stockpile.ledger(STORE).back()
	_check(line["what"] == "ore" and line["count"] == 5 and line["uid"] == 0, "the ledger counts the ore (%s)" % [line])


func _test_hauling() -> void:
	print("\n== hauling: what lands on the store's ground is banked; what is carried is not ==")
	var stock := World.stockpile
	var host := _player(Net.local_id)
	var who := World._label_of(host)
	var ore := stock.count(STORE, "ore")
	var kits := stock.count(STORE, KIT)
	World._relocate(host, Vector2i(9, 5))
	World.set_slots(host, ["ore_sack", KIT, "", "", "", ""])
	World._relocate(host, Vector2i(5, 4))
	await get_tree().process_frame
	_check(Stockpile.place_at(World.holdings, TOWN, host.tile) == STORE, "the host walks onto the store's ground at %s" % host.tile)
	_check(stock.count(STORE, "ore") == ore and stock.count(STORE, KIT) == kits and Array(host.slots) == ["ore_sack", KIT, "", "", "", ""],
		"carrying a sack and a kit in banks nothing (%s)" % [Array(host.slots)])
	var sack := World.slot_uid(host, 0)
	_check(World.try_drop(host, 0), "the host puts the sack down")
	_check(World.ground_at(host.tile) == PackedStringArray(["ore_sack"]), "it lies on the ground until the change is done")
	await get_tree().process_frame
	_check(stock.count(STORE, "ore") == ore + 5 and World.ground_at(host.tile).is_empty() and not World.items.has(sack),
		"then it's banked as 5 ore, off the ground, its instance ended (%d ore)" % stock.count(STORE, "ore"))
	var line: Dictionary = stock.ledger(STORE).back()
	_check(line["by"] == who and line["from"] == "the ground at %d,%d" % [host.tile.x, host.tile.y], "the ledger says who put it down, and where (%s)" % [line])
	var kit := World.slot_uid(host, 1)
	World.try_drop(host, 1)
	await get_tree().process_frame
	_check(stock.items(STORE).has(kit) and World.items.history(kit)["events"].back()["kind"] == "banked",
		"the kit put down is banked as itself (#%d)" % kit)

	World._relocate(host, Vector2i(8, 3))
	World.set_slots(host, ["", "", "", "", "ore_sack", ""])
	_check(Stockpile.place_at(World.holdings, TOWN, host.tile).is_empty(), "from %s, off the store's ground" % host.tile)
	_check(World.try_throw(host, Items.RIGHT_HAND, Vector2i(5, 3)), "the host throws a sack toward the store")
	await get_tree().process_frame
	_check(stock.count(STORE, "ore") == ore + 10, "it lands on the store's ground and is banked (%d ore)" % stock.count(STORE, "ore"))

	World.set_slots(host, ["ore_sack", "", "", "", "", ""])
	World._relocate(host, Vector2i(10, 6))
	World.try_drop(host, 0)
	await get_tree().process_frame
	_check(World.ground_at(Vector2i(10, 6)) == PackedStringArray(["ore_sack"]) and stock.count(STORE, "ore") == ore + 10,
		"put down off the store's ground, it just lies there")
	World.try_pick_up(host, Vector2i(10, 6))
	World._relocate(host, Vector2i(5, 4))
	World.holdings.take(STORE, "goblins")
	World.try_drop(host, _slot_of(host, "ore_sack"))
	await get_tree().process_frame
	_check(World.ground_at(host.tile) == PackedStringArray(["ore_sack"]) and stock.count(STORE, "ore") == ore + 10,
		"with the goblins holding the store, a sack put down there stays on the ground")
	World.holdings.take(STORE, "town")
	World.try_pick_up(host, host.tile)
	World.try_drop(host, _slot_of(host, "ore_sack"))
	await get_tree().process_frame
	_check(stock.count(STORE, "ore") == ore + 15 and World.ground_at(host.tile).is_empty(), "the town takes it back: picked up and put down, it's banked")


func _test_cart() -> void:
	print("
== a cart pushed onto the store's ground is unloaded into it, and stays ==")
	var stock := World.stockpile
	var cart := _entity("Cart1")
	_check(cart is Cargo and cart.slots.size() == 8, "Cart1 is a cart: 8 slots")
	World.set_slots(cart, ["ore_sack", "ore_sack", KIT, "", "", "", "", ""])
	var kit := World.slot_uid(cart, 2)
	var ore := stock.count(STORE, "ore")
	World._relocate(cart, Vector2i(1, 5))
	await get_tree().process_frame
	_check(stock.count(STORE, "ore") == ore and cart.slots[0] == "ore_sack", "moved about off the store's ground, it keeps its load")
	World._relocate(cart, Vector2i(3, 3))
	await get_tree().process_frame
	_check(stock.count(STORE, "ore") == ore + 10 and stock.items(STORE).has(kit),
		"pushed onto it: two sacks become 10 ore, the kit is banked as itself (%d ore)" % stock.count(STORE, "ore"))
	_check(is_instance_valid(cart) and cart.spawned and cart.tile == Vector2i(3, 3) and Array(cart.slots).all(func(id: String) -> bool: return id.is_empty()),
		"the cart stays where it is, empty (%s)" % [Array(cart.slots)])
	var line: Dictionary = stock.ledger(STORE).back()
	_check(line["from"] == World._label_of(cart), "the ledger says it came on the cart (%s)" % [line])
	World._relocate(cart, Vector2i(1, 5))
	World.set_slots(cart, ["ore_sack", "", "", "", "", "", "", ""])
	World.holdings.take(STORE, "goblins")
	World._relocate(cart, Vector2i(3, 4))
	await get_tree().process_frame
	_check(cart.slots[0] == "ore_sack" and stock.count(STORE, "ore") == ore + 10, "with the goblins holding the store, a cart pushed in keeps its load")
	World.holdings.take(STORE, "town")
	World._relocate(cart, Vector2i(2, 3))
	World.set_slots(cart, [KIT, "", "", "", "", "", "", ""])
	var host := _player(Net.local_id)
	World._relocate(host, Vector2i(1, 3))
	var pushed := World.slot_uid(cart, 0)
	_check(World.try_move(host, Vector2i(1, 0)) and cart.tile == Vector2i(3, 3), "the host pushes the cart onto the store's ground (%s)" % cart.tile)
	await get_tree().process_frame
	line = stock.ledger(STORE).back()
	_check(stock.items(STORE).has(pushed) and line["by"] == World._label_of(host) and line["from"] == World._label_of(cart),
		"its kit is banked, the ledger crediting who pushed it home (%s)" % [line])
	World._relocate(cart, Vector2i(1, 5))
	World.set_slots(cart, [])


func _slot_of(entity: GridEntity, id: String) -> int:
	return Array(entity.slots).find(id)


func _test_restart() -> void:
	print("\n== a restart keeps the store ==")
	var before := World.stockpile.to_dict()
	_main._save_state()
	var snapshot := Snapshot.load(Net.state_path)
	_check(snapshot["stockpile"] == JSON.parse_string(JSON.stringify(before)), "the snapshot has the store")
	remove_child(_main)
	_main.free()
	World.clear_zones()
	World.stockpile = null
	await _boot()
	var kits: Array[int] = []
	kits.assign(before[STORE]["items"])
	_check(World.stockpile.resources(STORE) == {"gold": 10, "ore": 7, "wood": 0, "cloth": 0, "food": 0}
		and World.stockpile.items(STORE) == kits and World.stockpile.item_ids(STORE) == _strings([KIT, KIT]),
		"after the restart: the same resources and the same two kits (%s)" % [World.stockpile.to_dict()])
	_check(kits.all(func(uid: int) -> bool: return World.items.at_of(uid) == Stockpile.holder(STORE)),
		"the book still has them at the store")
	_check(World.stockpile.ledger(STORE) == before[STORE]["ledger"], "and the same ledger")
	_check(World.items.orphans(World.stockpile.all_items()).all(func(uid: int) -> bool: return World.items.at_of(uid) != Stockpile.holder(STORE)),
		"every thing the book has at the store, the store holds")


func _test_old_and_odd_snapshots() -> void:
	print("\n== older snapshots, and nonsense in one ==")
	var path := Net.state_path.get_base_dir().path_join("stockpile_test_old.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": Snapshot.VERSION, "zones": {}, "players": [], "steps": 7}))
	file.close()
	var old := Snapshot.load(path)
	DirAccess.remove_absolute(path)
	_check(old["ok"] and old["stockpile"] == {}, "a snapshot from before the stockpile loads with none (%s)" % [old.get("stockpile")])
	var book := ItemBook.new()
	var odd := Stockpile.new({"gone/place": {"resources": {"gold": 3, "ore": -4, "wood": "lots"}, "items": [KIT, "dragon", 4242]},
		"junk": 5}, Callable(), book)
	_check(odd.places() == _strings(["gone/place"]), "a store whose place is gone is kept; junk is left out (%s)" % [odd.places()])
	_check(odd.resources("gone/place") == {"gold": 3, "ore": 0, "wood": 0, "cloth": 0, "food": 0}
		and odd.item_ids("gone/place") == _strings([KIT]),
		"counts under 0, counts that aren't numbers, unknown items and uids the book hasn't are left out (%s)" % [odd.to_dict()])
	var migrated := odd.items("gone/place")[0]
	_check(book.history(migrated)["events"][0]["kind"] == "migrated" and book.at_of(migrated) == Stockpile.holder("gone/place"),
		"a kit saved by its id (before uids) is a new thing, migrated, at the store (%s)" % [book.history(migrated)])


func _entity(entity_name: String) -> GridEntity:
	for entity in World.get_entities():
		if entity.name == entity_name:
			return entity
	return null


func _player(peer: int) -> Player:
	var player: Player = _main._players.get(peer)
	return player if is_instance_valid(player) and player.spawned else null


func _strings(values: Array) -> Array[String]:
	var out: Array[String] = []
	out.assign(values)
	return out


func _ints(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
