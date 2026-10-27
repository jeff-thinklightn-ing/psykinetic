extends Node
## The temple counter (decision 434, on items' 424 and buildings' counter),
## in Main on the test room with its chest made a temple counter of a town
## whose priest works there: a thing handed in with no gold is refused and
## stays; with the offering (half its value, at least 1) it goes to the
## priest, the gold to the treasury; after bless.steps it is blessed for
## its owner and held at the temple, the counter shows it to them, they
## take it back blessed, and nobody is held for any more; with the priest
## away it is refused; what is held is in the saved world and read back.
## The counter's work (decision 438): the temple counter's view prices a
## blessing for each thing carried; a shop counter offers a named
## weapon's reforges with the town's materials and a fee, refuses an
## unnamed one and a fee they can't pay, takes the order, reforges it on
## the same uid after the smith's steps, and they collect it.
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
	_test_reforge()
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
	# The room's imps outnumber a lone host and close in (decision 698): too
	# tough to die of them while the counter is worked.
	player.max_hp = 1000000
	player.hp = player.max_hp
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


func _test_reforge() -> void:
	print("
== a named weapon reforged at the shop counter ==")
	var counter: Chest = null
	for entity in World.get_entities():
		if entity is Chest:
			counter = entity
	var player := _player()
	var who: String = player.player_id
	var view := World.counter_view(player, counter)
	_check(view["kind"] == "temple" and view["jobs"].any(func(job: Dictionary) -> bool: return job["effect"] == "bless" and job["slot"] == 0),
		"the temple counter prices a blessing for what is in hand")
	# The counter a shop counter of a town that holds a store over it.
	counter.temple = false
	counter.shop = true
	var town := "%s/store" % World.zone.name
	World.holdings._places[town] = {"id": town, "area": World.zone.name, "key": "store", "cell": counter.tile, "name": "the store",
		"kind": "stockpile", "radius": 3, "worth": 0, "start": "town"}
	World.holdings._holder[town] = "town"
	World.holdings._strength[town] = 1
	World.holdings._since[town] = World.steps
	World.towns._town(town)["buildings"]["forge"] = {"kind": "forge", "level": 1, "state": Towns.STANDING, "since": 0, "job": 0}
	World.production.add_worker("smith:" + town, "Odo", ["smith"], town)
	World.production.add_workshop(town + ":forge", "smith", town)
	World.production.assign(town + ":forge", "smith:" + town)
	var uid := World.slot_uid(player, 0)
	var targets := Items.reforge_targets("dagger")
	_check(not targets.is_empty(), "(a dagger can become %s)" % [targets])
	var to_id: String = targets[0]
	view = World.counter_view(player, counter)
	var row: Array = view["jobs"].filter(func(job: Dictionary) -> bool: return job["to_id"] == to_id)
	_check(view["kind"] == "shop" and row.size() == 1 and not row[0]["ok"] and row[0]["why"] == "only a named thing can be reforged",
		"unnamed: offered, but refused with why (%s)" % [row])
	World.items.set_name(uid, {"form": "holder_possessive", "holder": "Bo", "who": "player:" + who, "made_step": World.steps, "text": "Bo's dagger"}, "")
	var cost := Items.reforge_cost("dagger", to_id)
	for what: String in cost["from"]:
		World.stockpile.deposit(town, what, int(cost["from"][what]) + 1)
	World.economy.add_gold(who, -World.economy.gold(who), "test")
	_check(World.counter_order(player, counter, 0, "reforge", to_id) == "the fee is %d gold" % World.reforge_fee(to_id), "no gold for the fee: refused")
	World.economy.add_gold(who, World.reforge_fee(to_id), "test")
	_check(World.counter_order(player, counter, 0, "reforge", "giant_axe_nope") != "", "a target it can't become: refused")
	_check(World.counter_order(player, counter, 0, "reforge", to_id) == "" and World.slot_uid(player, 0) == 0 and World.economy.gold(who) == 0,
		"ordered: handed in, the fee paid")
	view = World.counter_view(player, counter)
	_check(view["working"].size() == 1 and view["working"][0]["uid"] == uid and int(view["working"][0]["left_seconds"]) > 0,
		"being worked on, %d seconds left" % (int(view["working"][0]["left_seconds"]) if not view["working"].is_empty() else -1))
	var until := World.steps + int(cost["steps"]) + World.WORLD_TICK_STEPS * 2
	while World.steps < until:
		World.step()
	_check(World.items.id_of(uid) == to_id and not World.items.name_of(uid).is_empty(), "reforged on the same uid, its name kept (%s)" % World.items.id_of(uid))
	view = World.counter_view(player, counter)
	_check(view["waiting"].size() == 1 and view["waiting"][0]["uid"] == uid, "waiting for them")
	_check(World.counter_collect(player, counter, uid) == "" and uid in Array(player.slot_items), "collected into their slots")
	_check(World.counter_view(player, counter)["waiting"].is_empty(), "nothing waiting now")


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
