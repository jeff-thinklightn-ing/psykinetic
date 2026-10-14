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
	# A folder of this checkout's own: other worktrees run tests too.
	var folder := OS.get_temp_dir().path_join("psykinetic-%s" % ProjectSettings.globalize_path("res://").md5_text().left(8))
	DirAccess.make_dir_recursive_absolute(folder)
	Net.state_path = folder.path_join("stockpile_test_world.json")
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
	await _test_restart()
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
	var markers := {Vector2i(2, 2): "start", Vector2i(5, 2): "chest", Vector2i(9, 2): "chest", Vector2i(9, 5): "chest"}
	Level.register(TOWN, Level.image_from_rows(rows, markers), null, {
		"name": "Stockpile town", "centre": [6, 4], "starts": [[2, 2]],
		"entities": [
			{"at": [5, 2], "name": "Depot1", "props": {"depot": true}},
			{"at": [9, 2], "name": "StrayDepot", "props": {"depot": true}},
			{"at": [9, 5], "name": "Chest1", "props": {"slots": [KIT, "", "", ""]}},
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
	_check(Array(host.slots) == [KIT, "", "", ""], "it's in the host's pack (%s)" % [Array(host.slots)])
	_check(World.stockpile.count(STORE, KIT) == 0 and World.stockpile.places().is_empty(), "and the stockpile has nothing")


func _test_banking() -> void:
	print("\n== the depot banks what is put in ==")
	var host := _player(Net.local_id)
	var depot := _entity("Depot1")
	World._relocate(host, Vector2i(5, 3))
	World.steps = 1234
	_check(World.try_transfer(host, host, 0, depot, 2), "the host puts the kit in the depot")
	_check(Array(host.slots) == ["", "", "", ""] and Array(depot.slots) == ["", "", "", ""],
		"the pack's slot is empty, and so is the depot (%s, %s)" % [Array(host.slots), Array(depot.slots)])
	_check(World.stockpile.count(STORE, KIT) == 1 and World.stockpile.items(STORE) == _strings([KIT]),
		"the store holds one kit (%s)" % [World.stockpile.items(STORE)])
	var ledger := World.stockpile.ledger(STORE)
	_check(ledger.size() == 1 and ledger[0] == {"step": 1234, "what": KIT, "count": 1, "by": String(host.name), "from": String(host.name)},
		"its ledger: who and at which world step (%s)" % [ledger])
	_check(not World.try_transfer(host, depot, 0, host, 0), "nothing to take back out of the depot")


func _test_refused() -> void:
	print("\n== a depot outside a town-held stockpile refuses ==")
	var host := _player(Net.local_id)
	World.set_slots(host, [KIT, "", "", ""])
	World._relocate(host, Vector2i(9, 3))
	_check(not World.try_transfer(host, host, 0, _entity("StrayDepot"), 0), "the stray depot refuses the kit")
	_check(Array(host.slots) == [KIT, "", "", ""] and World.stockpile.count(STORE, KIT) == 1, "it stays in the pack (%s)" % [Array(host.slots)])
	World._relocate(host, Vector2i(5, 3))
	World.holdings.take(STORE, "goblins")
	_check(not World.try_transfer(host, host, 0, _entity("Depot1"), 0), "with the goblins holding the store, its depot refuses")
	_check(Array(host.slots) == [KIT, "", "", ""] and World.stockpile.count(STORE, KIT) == 1, "the kit stays, the store keeps its one")
	World.holdings.take(STORE, "town")
	_check(World.try_transfer(host, host, 0, _entity("Depot1"), 0), "the town takes it back: the depot banks again")
	_check(World.stockpile.count(STORE, KIT) == 2, "two kits now (%d)" % World.stockpile.count(STORE, KIT))


func _test_resources() -> void:
	print("\n== resources count up, and only the town's work takes them ==")
	var stock := World.stockpile
	_check(stock.deposit(STORE, "gold", 10, "Bo", "castle") and stock.deposit(STORE, "ore", 5, "Bo", "mine"), "10 gold and 5 ore banked")
	_check(stock.resources(STORE) == {"gold": 10, "ore": 5, "wood": 0, "cloth": 0, "food": 0}, "counted (%s)" % [stock.resources(STORE)])
	_check(not stock.deposit(STORE, "dragon", 1) and not stock.deposit(STORE, "ore", 0) and not stock.deposit("", "ore", 1),
		"no banking of what is not a resource or item, of nothing, or nowhere")
	_check(stock.take(STORE, "ore", 3, "smith: a blade") and stock.count(STORE, "ore") == 2, "the smith takes 3 ore: 2 left")
	_check(not stock.take(STORE, "ore", 3) and stock.count(STORE, "ore") == 2, "3 more is more than there is: nothing taken")
	_check(stock.take(STORE, KIT, 1, "shop") and stock.count(STORE, KIT) == 1, "the shop takes a kit: 1 left")
	_check(stock.ledger(STORE).back() == {"step": World.steps, "what": KIT, "count": -1, "by": "shop", "from": ""},
		"the ledger says why (%s)" % [stock.ledger(STORE).back()])
	var other := Stockpile.new()
	for i in Stockpile.LEDGER_SIZE + 5:
		other.deposit("x/y", "wood", 1)
	_check(other.ledger("x/y").size() == Stockpile.LEDGER_SIZE and other.count("x/y", "wood") == Stockpile.LEDGER_SIZE + 5,
		"the ledger keeps the last %d lines; the count keeps everything" % Stockpile.LEDGER_SIZE)


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
	_check(World.stockpile.resources(STORE) == {"gold": 10, "ore": 2, "wood": 0, "cloth": 0, "food": 0}
		and World.stockpile.items(STORE) == _strings([KIT]), "after the restart: the same resources and the kit (%s)" % [World.stockpile.to_dict()])
	_check(World.stockpile.ledger(STORE) == before[STORE]["ledger"], "and the same ledger")


func _test_old_and_odd_snapshots() -> void:
	print("\n== older snapshots, and nonsense in one ==")
	var path := Net.state_path.get_base_dir().path_join("stockpile_test_old.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": Snapshot.VERSION, "zones": {}, "players": [], "steps": 7}))
	file.close()
	var old := Snapshot.load(path)
	DirAccess.remove_absolute(path)
	_check(old["ok"] and old["stockpile"] == {}, "a snapshot from before the stockpile loads with none (%s)" % [old.get("stockpile")])
	var odd := Stockpile.new({"gone/place": {"resources": {"gold": 3, "ore": -4, "wood": "lots"}, "items": [KIT, "dragon"]},
		"junk": 5})
	_check(odd.places() == _strings(["gone/place"]), "a store whose place is gone is kept; junk is left out (%s)" % [odd.places()])
	_check(odd.resources("gone/place") == {"gold": 3, "ore": 0, "wood": 0, "cloth": 0, "food": 0}
		and odd.items("gone/place") == _strings([KIT]), "counts under 0, counts that aren't numbers and unknown items are left out (%s)" % [odd.to_dict()])


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


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
