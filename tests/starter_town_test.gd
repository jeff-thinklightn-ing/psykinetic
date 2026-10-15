extends Node
## The starter town in the wilds (levels/wilds, buildings' layout with the
## town_store prefab) is a town: its store a stockpile place the town holds,
## Stockpile.check finds nothing wrong with it, its linked forge and kitchen
## stand once Towns is seeded from the world map (decision 306), a rescued
## smith and cook are seated at them, the shop lists its goods priced
## (what the smith makes on the world tick, once the catalog has recipes;
## until then a thing put on the counter), and a companion left in town is
## a resident. Reads the repo's levels, never the shared overlay.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const TOWN := "wilds/store"
const TICKS := 400
const STEPS_PER_TICK := 100

var _failures := 0
var _now := 0


func _ready() -> void:
	World.set_process(false)
	var overlay := Level.overlay_dir
	Level.overlay_dir = preload("res://tests/test_ports.gd").scratch("starter_town_test/no_overlay/")
	_test_town()
	Level.overlay_dir = overlay
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_town() -> void:
	print("\n== the wilds' starter town ==")
	var made := Level.source("wilds")
	var config: Dictionary = made["config"]
	var store: Dictionary = config.get("places", {}).get("store", {})
	_check(store.get("kind") == "stockpile" and store.get("holder") == Stockpile.TOWN, "levels/wilds has the store, a stockpile the town holds (%s)" % [store])
	var warnings := Stockpile.check(config)
	_check(warnings.is_empty(), "Stockpile.check: nothing wrong; its depot and counter are covered (%s)" % [warnings])
	var clock := func() -> int: return _now
	var world_map := WorldMap.build()
	var holdings := Holdings.new(world_map, Factions.read(), {}, clock)
	_check(holdings.holder(TOWN) == Stockpile.TOWN, "Holdings: %s is the town's (%s)" % [TOWN, holdings.holder(TOWN)])
	var book := ItemBook.new(clock)
	var stock := Stockpile.new({}, clock, book)
	var work := Production.new({}, stock, holdings, clock)
	var towns := Towns.new({}, work, {}, clock)
	var economy := Economy.new({}, stock, work, clock)
	var seeded := towns.seed_from(world_map)
	_check(seeded == [TOWN + "/forge", TOWN + "/kitchen"], "seeded from the map: the forge and the kitchen (%s)" % [seeded])
	var forge := towns.building(TOWN, "forge")
	var kitchen := towns.building(TOWN, "kitchen")
	_check(forge.get("state") == Towns.STANDING and forge.get("level") == 1 and kitchen.get("state") == Towns.STANDING and kitchen.get("level") == 1,
		"both standing, level 1 (%s, %s)" % [forge, kitchen])
	towns.note_rescue(TOWN, "smith_1", "Odo", "smith")
	towns.note_rescue(TOWN, "cook_1", "Mags", "cook")
	_check(work.workshop(TOWN + ":forge").get("worker") == "smith_1" and work.workshop(TOWN + ":kitchen").get("worker") == "cook_1",
		"Odo the smith is seated at the forge, Mags the cook at the kitchen")
	var recipes := Economy.items_defs().keys().filter(func(id: String) -> bool: return not Economy.items_defs()[id].get("made", {}).is_empty())
	if recipes.is_empty():
		# No recipe in the catalog yet (items' "made"): the smith has nothing
		# to make, so the counter is stocked as a sold thing would be.
		print("  (the item catalog has no recipes yet: nothing for the smith to make)")
		stock.stock_shop(TOWN, book.mint("bandaging_kit", "made", "a test"), "test")
	else:
		for what: String in ["ore", "wood", "food", "cloth"]:
			stock.deposit(TOWN, what, 40, "test")
		for tick in TICKS:
			_now += STEPS_PER_TICK
			towns.tick()
			work.tick()
			if not economy.goods(TOWN).is_empty():
				break
	var goods := economy.goods(TOWN)
	_check(not goods.is_empty() and goods.all(func(each: Dictionary) -> bool: return int(each["price"]) > 0),
		"the shop lists its goods, priced, by step %d (%s)" % [_now, goods.slice(0, 3)])
	print("  log: %s" % [towns.log_of(TOWN).map(func(line: Dictionary) -> String: return line["what"])])
	var before := towns.residents(TOWN).size()
	towns.note_companion_in(TOWN, "Wren", "carpenter")
	_check(towns.residents(TOWN).size() == before + 1, "Wren left in town is a resident (%s)" % [towns.residents(TOWN)])


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
