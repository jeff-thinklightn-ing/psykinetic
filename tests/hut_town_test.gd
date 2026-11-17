extends Node
## A healer's hut buys its mend from the nearest town by world route (733 amended (1); the coordinator's ruling,
## 11-15). Main._hut_town ranked the towns without routes, which counts only the hut's own area: the forest's hut,
## with no store in the forest, had no town, so its keeper's mend was never ordered (the box, 11-14: a ruin, kept,
## nobody raised there since). On the laid world: the forest's hut buys from Umbrage's store, and its ruin is mended
## for 10 wood; a hut no town can be reached from has none, and kept it still gives care and brings the fallen back,
## its walls waiting, nothing erring. 918 amended (1): with no woodcutter in Umbrage, the kept ruin's 10 wood calls
## one, as a queued repair short of wood does.

const FOREST := "forest/healers_hut@45,31"
const WILDS := "wilds/healers_hut@152,232"
const UMBRAGE := "wilds/store"
const NOWHERE := "hut_town_nowhere/healers_hut@3,3"

var _failed := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	World.set_process(false)
	var ports := preload("res://tests/test_ports.gd")
	Net.port = ports.of(18003)
	Net.companions = false
	Net.map_name = "wilds"
	Net.lawspeaker = "off"
	Net.state_path = ports.scratch_path("hut_town_world.json")
	if FileAccess.file_exists(Net.state_path):
		DirAccess.remove_absolute(Net.state_path)
	var main: Node = preload("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	_test_first_sync_reads(main)
	print("== a healer's hut buys its mend from the nearest town by route (733 amended (1)) ==")
	_check(not World.holdings.place(FOREST).is_empty() and not World.holdings.place(WILDS).is_empty(), "(the forest's and the wilds' huts on the laid world)")
	_check(main._hut_town(WILDS) == UMBRAGE, "the wilds' hut: Umbrage's store, its own area's (%s)" % main._hut_town(WILDS))
	_check(main._hut_town(FOREST) == UMBRAGE, "the forest's hut, no store in the forest: Umbrage's, the nearest by route (%s)" % main._hut_town(FOREST))
	# The forest's hut a ruin, kept: mended from Umbrage's store, 10 wood and no cloth.
	var keeper := str(World.production.workshop(FOREST).get("worker", ""))
	_check(not keeper.is_empty() and World.towns.hut_kept(FOREST), "(the forest's hut has its keeper, seated at the boot)")
	World.towns._huts[FOREST] = {"state": Towns.RUIN, "level": 0, "job": 0, "ruin": 0}
	_check(not main._hut_shut(FOREST), "a ruin he keeps: open, care and a return point (733 amended (1))")
	World.stockpile.take(UMBRAGE, "wood", World.stockpile.count(UMBRAGE, "wood"), "test")
	World.stockpile.deposit(UMBRAGE, "wood", 10, "test")
	World.production.pay(keeper, 100, "test")
	World.towns._huts_turn()
	var job := int(World.towns._huts[FOREST]["job"])
	_check(job != 0 and World.stockpile.count(UMBRAGE, "wood") == 0 and World.production.job(job).get("recipe", "") == Towns.HUT_REPAIR + FOREST,
		"10 wood in Umbrage's store: the forest's ruin's mend ordered, the wood taken from Umbrage (job %d, wood left %d)" % [job, World.stockpile.count(UMBRAGE, "wood")])
	# 918 amended (1): a ruin's wood calls a woodcutter when the town has none (the box, 11-15: Umbrage's left for
	# wages; _woodcutter_comes read only a planned building's wood).
	var record: Dictionary = World.towns._town(UMBRAGE)
	for who: String in World.towns.residents(UMBRAGE).duplicate():
		if "woodcutter" in World.production.trades_of(who):
			record["residents"].erase(who)
	record.erase("woodcutter_wanted")
	World.towns._huts[FOREST] = {"state": Towns.STANDING, "level": 1, "job": 0}
	World.towns._woodcutter_comes(UMBRAGE)
	_check(not World.towns.has_resident(UMBRAGE, "woodcutter") and not record.has("woodcutter_wanted"),
		"(no woodcutter in Umbrage, nothing waiting on wood: none called)")
	World.towns._huts[FOREST] = {"state": Towns.RUIN, "level": 0, "job": 0, "ruin": 0}
	World.towns._woodcutter_comes(UMBRAGE)
	_check(int(record.get("woodcutter_wanted", -1)) >= 0, "the forest's kept ruin wants 10 wood, Umbrage has %d and no woodcutter: one called (wanted since %d)"
		% [World.stockpile.count(UMBRAGE, "wood"), int(record.get("woodcutter_wanted", -1))])
	World.towns._huts[FOREST]["job"] = -1  # Its mend ordered: the hut no longer waits on Umbrage's wood.
	record.erase("woodcutter_wanted")
	World.towns._woodcutter_comes(UMBRAGE)
	_check(not record.has("woodcutter_wanted"), "its mend ordered: no call for it")
	_check(World.towns.damage(UMBRAGE, "kitchen") and World.towns._repair(UMBRAGE), "(Umbrage's kitchen damaged, its repair ordered)")
	var repair := int(World.towns.building(UMBRAGE, "kitchen").get("job", 0))
	var wood := int(World.production.job(repair).get("cost", {}).get("wood", 0))
	World.towns._woodcutter_comes(UMBRAGE)
	_check(wood > World.stockpile.count(UMBRAGE, "wood") and str(World.production.job(repair).get("state", "")) == "queued" and int(record.get("woodcutter_wanted", -1)) >= 0,
		"a repair queued for %d wood, none in the store: a woodcutter called" % wood)
	World.towns._huts[FOREST]["job"] = 0
	# A hut no town can be reached from: no town; kept, open, its walls waiting, its turn erring nowhere.
	World.holdings._places[NOWHERE] = {"id": NOWHERE, "area": "hut_town_nowhere", "key": "healers_hut@3,3", "cell": Vector2i(3, 3), "name": "a lost hut",
		"kind": "healers_hut", "radius": 2, "worth": 0, "start": Factions.NOBODY}
	World.holdings._holder[NOWHERE] = Factions.NOBODY
	World.production.add_workshop(NOWHERE, "medicine_man", NOWHERE)
	World.production.add_worker("medicine_man:" + NOWHERE, "Lost Hob", ["medicine_man"], NOWHERE, "settled")
	World.production.assign(NOWHERE, "medicine_man:" + NOWHERE)
	_check(main._hut_town(NOWHERE) == "", "a hut no town can be reached from: no town (%s)" % main._hut_town(NOWHERE))
	World.towns._huts[NOWHERE] = {"state": Towns.DISREPAIR, "level": 1, "job": 0, "decay": -100}
	World.towns._huts_turn()
	_check(World.towns.hut(NOWHERE) == {"state": Towns.DISREPAIR, "level": 1} and int(World.towns._huts[NOWHERE]["job"]) == 0 and not main._hut_shut(NOWHERE),
		"kept, no town: in disrepair still, nothing ordered, open (%s)" % [World.towns.hut(NOWHERE)])
	World.towns._huts[NOWHERE]["state"] = Towns.RUIN
	World.towns._huts[NOWHERE]["level"] = 0
	_check(not main._hut_shut(NOWHERE) and main.care_rule(NOWHERE) is Dictionary, "a ruin, kept, no town: still open")
	_test_reload_keeps_decor(main)
	_test_rack(main)
	print("RESULT: %s (%d failed)" % ["PASS" if _failed == 0 else "FAIL", _failed])
	Net.state_path = ""
	get_tree().quit(0 if _failed == 0 else 1)


## 853 amended (21) (perf's, in npc's place on the coordinator's ruling, 2026-11-16): the wilds' seat cells, bedrolls
## and carts are kept as its level is laid, so the residents part never reads it from disk. Its first sync read the
## wilds again for the fire's seats (Main._seat_cells), about 370 ms of tick 30 on every boot. Here on the boot, before
## any tick (World is not processing), then the residents part's calls as Main's tick makes them, the reads counted
## (Level.loads), never timed. The tavern's level, never laid at the boot, is still read once at the first sync
## (Main._zone_level, its inn spots): printed, not failed; listed for the coordinator.
func _test_first_sync_reads(main: Node) -> void:
	print("== the first sync reads no laid level from disk (853 amended (21)) ==")
	var decor: Array = Level.load_level("wilds").get("terrain", {}).get("decor", [])
	var seats: Dictionary = Main.seat_cells_of(decor, Level.DECOR_KINDS)
	_check(World.tick < Main.RESIDENT_SYNC_TICKS and main._seat_decor.has("wilds") and main._seat_decor["wilds"] == seats,
		"before the first sync (tick %d) the wilds' seat cells are kept, as its level holds them (%d; none till maps' logs are in)" % [World.tick, seats.size()])
	_check(main._camp_bedrolls.has("wilds") and main._camp_carts.has("wilds"), "and its bedrolls and carts (%d, %d)"
		% [(main._camp_bedrolls.get("wilds", {}) as Dictionary).size(), (main._camp_carts.get("wilds", []) as Array).size()])
	var fire := false
	for each: Dictionary in main._fire_places.get("wilds", []):
		fire = fire or not str(each.get("town", "")).is_empty()
	_check(fire, "(the wilds lays a town's fire: the sync reaches the fire's seats)")
	var laid: Array = []
	for zone: Zone in World.zones.values():
		laid.append(zone.name)
	for sync in 2:
		var before := Level.loads.duplicate()
		main._sync_residents()
		main._sync_bands()
		main._warm_rests()
		World.burn_hearths()
		var read := {}
		for level_name: String in Level.loads:
			if Level.loads[level_name] != int(before.get(level_name, 0)):
				read[level_name] = Level.loads[level_name] - int(before.get(level_name, 0))
		var again := read.keys().filter(func(level_name: String) -> bool: return level_name in laid)
		if sync == 0:
			_check(again.is_empty(), "the first residents part reads no laid level (%s laid; read: %s)" % [", ".join(laid), read])
		else:
			_check(read.is_empty(), "the second reads no level at all (read: %s)" % read)


## A zone reloaded (a builder's accept, Main.reload_zone) keeps its decor again from the level it lays, not what was
## kept before (853 amended (21)): read once a zone, an edit's seats were never seen till a restart.
func _test_reload_keeps_decor(main: Node) -> void:
	print("== a reloaded zone's decor kept again from the level laid (853 amended (21)) ==")
	var stale := {Vector2i(-9, -9): true}
	main._seat_decor["wilds"] = stale
	main._camp_carts["wilds"] = [Vector2i(-9, -9)]
	var before := Level.loads.duplicate()
	main.reload_zone("wilds")
	var seats: Dictionary = Main.seat_cells_of(main.level.get("terrain", {}).get("decor", []), Level.DECOR_KINDS)
	_check(main._seat_decor.get("wilds") == seats and not (main._camp_carts.get("wilds", []) as Array).has(Vector2i(-9, -9)),
		"after the reload the wilds' seats and carts are the laid level's (%d seats), not the stale ones" % seats.size())
	_check(int(Level.loads.get("wilds", 0)) - int(before.get("wilds", 0)) == 1, "one read, the reload's own (%d)"
		% (int(Level.loads.get("wilds", 0)) - int(before.get("wilds", 0))))


## 733 amended (2), package "wood at the hut's door", joined: the wilds' hut a ruin, its rack's cell beside its
## door (on the floor, outside the turf house, never its front cell); the "huts" message carries [laid, need]
## and the cell only while on; the host's "hut_give" from too far takes nothing; near, his bundles laid up to the
## need, the rest kept; kept, the full rack mended at once without buying; his first care there free.
func _test_rack(main: Node) -> void:
	print("== the log rack, joined (733 amended (2)) ==")
	var host: Player = main._players.get(Net.local_id)
	World.towns._huts[WILDS] = {"state": Towns.RUIN, "level": 0, "job": 0, "ruin": 0}
	World.stockpile.take(WILDS, "wood", World.stockpile.count(WILDS, "wood"), "test")
	_check(not main.huts_of("wilds")[WILDS].has("rack"), "off: no rack in the huts message")
	World.towns.rules["healers"]["rack"]["on"] = true
	var front: Vector2i = World.holdings.place(WILDS)["cell"]
	var cell: Vector2i = main.rack_cell(WILDS)
	var level := Level.load_level("wilds")
	var rect := Rect2i()
	for each: Dictionary in level["buildings"]:
		if each.get("front", Level.front_cell(each["rect"], each["facing"])) == front:
			rect = each["rect"]
	_check(cell != main.NO_RACK and not rect.has_point(cell) and (level["terrain"]["floor"] as Array).has(cell) and absi(cell.x - front.x) <= 1 and absi(cell.y - front.y) <= 1
		and cell.x != front.x, "the rack's cell beside the door, on the floor outside the turf house and its bank (front %s, rack %s)" % [front, cell])
	var sent: Dictionary = main.huts_of("wilds")[WILDS]
	_check(sent.get("rack") == [0, 2] and sent.get("rack_cell") == [cell.x, cell.y] and not str(sent).contains(host.player_id),
		"on: the huts message, [0, 2] bundles and its cell, no id (%s)" % [sent])
	for i in 3:
		main._hand_item(host.player_id, "wood_bundle", "test")
	World._relocate(host, cell + Vector2i(0, -4) if World.is_walkable(cell + Vector2i(0, -4)) else cell + Vector2i(0, 4))
	_check(main.hut_give(host, {"hut": WILDS}) == 0 and World.count_of(host, "wood_bundle") == 3, "4 cells off: nothing laid")
	World._relocate(host, cell + Vector2i(0, -2) if World.is_walkable(cell + Vector2i(0, -2)) else cell + Vector2i(0, 2))
	var keeper := str(World.production.workshop(WILDS).get("worker", ""))
	var town_wood := World.stockpile.count(UMBRAGE, "wood")
	var laid: int = main.hut_give(host, {"hut": WILDS})
	_check(laid == 10 and World.count_of(host, "wood_bundle") == 1, "2 cells off: two bundles laid, 10 wood, the third kept (laid %d, kept %d)" % [laid, World.count_of(host, "wood_bundle")])
	var job := int(World.towns._huts[WILDS]["job"])
	_check(not keeper.is_empty() and job != 0 and World.stockpile.count(UMBRAGE, "wood") == town_wood and not main.huts_of("wilds")[WILDS].has("rack"),
		"kept: the mend ordered at once, nothing bought from Umbrage, the rack gone (job %d)" % job)
	_check(World.towns.care_free(WILDS, host.player_id) and main._care_free(WILDS, host.player_id), "the host's first care there free")
	_check(main.hut_give(host, {"hut": WILDS}) == 0 and World.count_of(host, "wood_bundle") == 1, "its mend under way: no rack, nothing taken")
	World.towns.rules["healers"]["rack"]["on"] = false


func _check(ok: bool, label: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + label)
	if not ok:
		_failed += 1
