extends Node
## The temple counter (decision 434, on items' 424 and buildings' counter),
## in Main on the test room with its chest made a temple counter of a town
## whose priest works there: a thing handed in with no gold is refused and
## stays; with the offering (half its value, at least 1) it goes to the
## priest, the gold to the treasury; after bless.steps it is blessed for
## its owner and held at the temple, the counter shows it to them, they
## take it back blessed, and nobody is held for any more; with the priest
## away it is refused; what is held is in the saved world and read back.
## The general job: a mend is its effect "mend".
## Reads the repo's levels, never the shared overlay.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const TOWN := "bt/store"

var _failures := 0
var _main: Node


func _ready() -> void:
	Net.port = preload("res://tests/test_ports.gd").of(17841)
	Net.companions = false
	Net.state_path = preload("res://tests/test_ports.gd").scratch_path("blessing_test_world.json")
	if FileAccess.file_exists(Net.state_path):
		DirAccess.remove_absolute(Net.state_path)
	_main = preload("res://main.tscn").instantiate()
	_main.returns = false
	add_child(_main)
	_test_counter()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_counter() -> void:
	print("\n== a thing handed to the priest at the temple counter ==")
	var counter: Chest = null
	for entity in World.get_entities():
		if entity is Chest:
			counter = entity
	var player := _player()
	_check(counter != null and player != null, "(the test room's chest and a player)")
	counter.temple = true
	counter.shop = false
	counter.depot = false
	World.counter_town = func(_counter: GridEntity) -> String: return TOWN
	World.production.add_worker("priest:" + TOWN, "Osric", ["priest"], TOWN, "appointed")
	World.production.add_workshop(TOWN + ":temple", "priest", TOWN)
	World.production.assign(TOWN + ":temple", "priest:" + TOWN)
	var others := Array(counter.slots).filter(func(each: String) -> bool: return not each.is_empty()).size()
	World.towns._town(TOWN)["buildings"]["temple"] = {"kind": "temple", "level": 1, "state": Towns.STANDING, "since": 0, "job": 0}
	# Beside the counter, a dagger in hand.
	World._relocate(player, _beside(counter.tile))
	var uid := World.items.mint("dagger", "made", "test")
	player.slots = ["dagger"] + Array(player.slots).slice(1)
	player.slot_items = PackedInt32Array([uid] + Array(player.slot_items).slice(1))
	var who: String = player.player_id
	World.economy.add_gold(who, -World.economy.gold(who), "test")
	_check(not World.try_transfer(player, player, 0, counter, 0) and World.slot_uid(player, 0) == uid, "no gold: refused, it stays in hand")
	var rule: Dictionary = World.production.rules["bless"]
	var offering := maxi(ceili(World.economy.value_of("dagger") * float(rule["offering"])), int(rule["least"]))
	World.economy.add_gold(who, offering + 3, "test")
	var treasury := World.stockpile.count(TOWN, "gold")
	_check(World.try_transfer(player, player, 0, counter, 0) and World.slot_uid(player, 0) == 0, "with the offering (%d gold) it is handed in" % offering)
	_check(World.economy.gold(who) == 3 and World.stockpile.count(TOWN, "gold") == treasury + offering, "the offering into the treasury")
	var jobs := World.production.jobs().filter(func(id: int) -> bool: return World.production.job(id)["kind"] == "work")
	_check(jobs.size() == 1 and World.production.job(jobs[0])["effect"] == "bless" and World.production.job(jobs[0])["for"] == "player:" + who,
		"a bless job for its owner")
	World.show_held(counter, player)
	_check(Array(counter.slot_items).find(uid) < 0, "not ready yet: nothing to collect")
	var steps := int(rule["steps"])
	var until := World.steps + steps + World.WORLD_TICK_STEPS * 2
	while World.steps < until:
		World.step()
	_check(World.items.blessed_for(uid) == "player:" + who, "blessed for its owner")
	_check(World.towns.held(TOWN, "player:" + who) == [uid], "held at the temple for them")
	World.show_held(counter, player)
	var slot := Array(counter.slot_items).find(uid)
	_check(slot >= 0, "the counter shows it to its owner")
	World.show_held(counter, null)
	_main._save_state(true)
	var saved := Snapshot.load(Net.state_path)
	var towns := Towns.new(saved.get("towns", {}), World.production, World.production.rules)
	_check(towns.held(TOWN, "player:" + who) == [uid], "held in a saved world, and read back from it")
	World.show_held(counter, player)
	slot = Array(counter.slot_items).find(uid)
	World.show_held(counter, null)
	_check(Array(counter.slot_items).find(uid) < 0 and World.towns.held(TOWN, "player:" + who) == [uid], "nobody there: put back in the town's keeping")
	_check(Array(counter.slots).filter(func(each: String) -> bool: return not each.is_empty()).size() == others, "what else was in the counter stays (%d)" % others)
	World.show_held(counter, player)
	slot = Array(counter.slot_items).find(uid)
	_check(World.try_transfer(player, counter, slot, player, 0) and World.slot_uid(player, 0) == uid, "taken back")
	_check(World.towns.held(TOWN, "player:" + who).is_empty(), "nothing held for them now")
	World.production.set_away("priest:" + TOWN, true)
	World.economy.add_gold(who, offering, "test")
	_check(not World.try_transfer(player, player, 0, counter, 0), "the priest away: refused")


func _beside(cell: Vector2i) -> Vector2i:
	for direction in World.DIRECTIONS:
		if World.is_free(cell + direction) and World.can_melee(cell + direction, cell):
			return cell + direction
	return cell


func _player() -> Player:
	for entity in World.get_entities():
		if entity is Player and entity.spawned:
			return entity
	return null


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
