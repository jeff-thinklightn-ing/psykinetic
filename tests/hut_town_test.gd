extends Node
## A healer's hut buys its mend from the nearest town by world route (733 amended (1); the coordinator's ruling,
## 11-15). Main._hut_town ranked the towns without routes, which counts only the hut's own area: the forest's hut,
## with no store in the forest, had no town, so its keeper's mend was never ordered (the box, 11-14: a ruin, kept,
## nobody raised there since). On the laid world: the forest's hut buys from Umbrage's store, and its ruin is mended
## for 10 wood; a hut no town can be reached from has none, and kept it still gives care and brings the fallen back,
## its walls waiting, nothing erring.

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
	Net.port = ports.of(17996)
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
	print("RESULT: %s (%d failed)" % ["PASS" if _failed == 0 else "FAIL", _failed])
	Net.state_path = ""
	get_tree().quit(0 if _failed == 0 else 1)


func _check(ok: bool, label: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + label)
	if not ok:
		_failed += 1
