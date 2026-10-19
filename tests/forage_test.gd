extends Node
## What grows wild (Forage, decision 502), in the game on the repo's wilds:
## a day lays per_day herbs as ground piles, each grown ("grew" its first
## event) on grass under the sky outside the town's ring and its buildings
## and within reach of its store, on nobody's ground; the same day lays no
## more; never more than most lie at once; wither_days on they are gone
## (ended "withered"); an item the catalog lacks lays nothing; take_near
## gives the nearest one within reach off the ground; a restart keeps them
## as grown things, counted and withered as before; the client stands a
## pile of herbs as the kit's plant and draws any other as things. The
## herbs item is added for the test (items' entry may not be on main yet).
## Reads the repo's levels, never the shared overlay.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const AREA := "wilds"

var _failures := 0
var _main: Node


func _ready() -> void:
	World.set_process(false)
	Net.port = preload("res://tests/test_ports.gd").of(17885)
	Net.companions = false
	Net.map_name = AREA
	Level.overlay_dir = preload("res://tests/test_ports.gd").scratch("forage_test/no_overlay/")
	Net.state_path = preload("res://tests/test_ports.gd").scratch_path("forage_test_world.json")
	if FileAccess.file_exists(Net.state_path):
		DirAccess.remove_absolute(Net.state_path)
	if not Items.exists(Forage.HERBS):
		Items.add_for_test({"id": Forage.HERBS, "name": "herbs", "weight": 0.2, "value": 1})
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	for i in 3:
		World.step()
	_check(World.forage != null and World.zone.name == AREA, "the server has its forage, in %s" % World.zone.name)
	_test_lay()
	_test_most()
	_test_wither()
	_test_missing()
	_test_take()
	await _test_restart()
	_test_drawn()
	get_tree().quit(1 if _failures > 0 else 0)


func _rule() -> Dictionary:
	return World.forage.rules[Forage.HERBS]


func _count() -> int:
	var count := 0
	for uids: Array in World.forage.lying(Forage.HERBS).values():
		count += uids.size()
	return count


func _test_lay() -> void:
	print("\n== a day's herbs ==")
	var rule := _rule()
	_check(int(rule["per_day"]) == 4 and int(rule["most"]) == 10, "the rules are economy.json's (%s)" % [rule])
	World.forage.daily(1)
	var found := World.forage.lying(Forage.HERBS)
	_check(_count() == int(rule["per_day"]), "per_day of them lie in %s (%d)" % [AREA, _count()])
	var towns := World.forage.towns_in(AREA)
	var size: Vector2i = World.forage.world_map.areas[AREA]["size"]
	var grass: PackedByteArray = World.forage.world_map.areas[AREA]["grass"]
	for cell: Vector2i in found:
		var nearest := INF
		var ring := 0.0
		for town in towns:
			var away := Vector2(cell - town).length()
			if away < nearest:
				nearest = away
				ring = World.forage.ring_of(AREA, town, rule)
		var uid: int = found[cell][0]
		_check(grass[cell.y * size.x + cell.x] == 1 and World.richness.under_sky(AREA, cell) and not World.is_water(cell),
				"%s is grass under the sky" % cell)
		_check(nearest > ring and nearest <= float(rule["reach"]) and World.holdings.ground(AREA, cell) == Factions.NOBODY,
				"%s is %.0f from the store: past the town's ring (%.0f), within reach, nobody's" % [cell, nearest, ring])
		_check(World.items.history(uid)["events"][0]["kind"] == Forage.GREW and World.zone.piles.has(cell),
				"it grew there, a pile anyone sees")
	_check(towns.size() > 0 and World.forage.ring_of(AREA, towns[0], rule) > float(rule["ring"]),
			"the town's ring goes out past its buildings (%.0f)" % World.forage.ring_of(AREA, towns[0], rule))
	var before := _count()
	World.forage.tick()
	World.forage.tick()
	_check(_count() - before <= int(rule["per_day"]), "the tick lays a day's at most once (%d, %d)" % [before, _count()])


func _test_most() -> void:
	print("\n== never more than most ==")
	for day in range(2, 6):
		World.forage.daily(day)
	_check(_count() == int(_rule()["most"]), "%d lie after five days, most" % _count())


func _test_wither() -> void:
	print("\n== they wither ==")
	var old := World.forage.lying(Forage.HERBS)
	var uids: Array = []
	for each: Array in old.values():
		uids.append_array(each)
	World.steps += int(_rule()["wither_days"]) * DayNight.day_steps
	World.forage.daily(10)
	var gone := uids.filter(func(uid: int) -> bool: return not World.items.has(uid))
	_check(gone.size() == uids.size(), "every one of the old is gone from the book (%d of %d)" % [gone.size(), uids.size()])
	_check(_count() == int(_rule()["per_day"]), "and the day's new lie (%d)" % _count())


func _test_missing() -> void:
	print("\n== an item the catalog lacks ==")
	var forage := Forage.new(World.forage.world_map, World.holdings, {"no_such_herb": {"per_day": 5}})
	var piles := World.zone.piles.size()
	forage.daily(1)
	_check(World.zone.piles.size() == piles and forage.lying("no_such_herb").is_empty(), "lays nothing")


func _test_take() -> void:
	print("\n== the medicine man takes one ==")
	var found := World.forage.lying(Forage.HERBS)
	_check(not found.is_empty(), "some lie to take")
	if found.is_empty():
		return
	var cell: Vector2i = found.keys()[0]
	var count := _count()
	_check(World.forage.take_near(AREA, cell + Vector2i(9, 9), 3) == 0, "none within 3 of a cell 9 away")
	var uid := World.forage.take_near(AREA, cell + Vector2i(1, 0), 1)
	_check(uid == int(found[cell][0]) and World.items.at_of(uid) == "" and not World.zone.ground.has(cell),
			"the one beside: off the ground, nowhere yet (%d, %s)" % [uid, World.items.at_of(uid)])
	_check(_count() == count - 1 and World.forage.take_near("no_such_area", cell, 1) == 0, "one fewer lie; none from an area not loaded")
	World.items.end(uid, "banked")


func _test_restart() -> void:
	print("\n== a restart keeps them ==")
	var before := World.forage.lying(Forage.HERBS)
	_main._save_state()
	remove_child(_main)
	_main.free()
	World.clear_zones()
	World.items = ItemBook.new(World.steps_now)
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	var after := World.forage.lying(Forage.HERBS)
	_check(after.keys().size() == before.keys().size() and after.keys().all(func(cell: Vector2i) -> bool: return before.has(cell)),
			"the same cells, grown things still (%d)" % after.size())
	World.steps += int(_rule()["wither_days"]) * DayNight.day_steps
	World.forage.daily(20)
	var withered := before.values().all(func(uids: Array) -> bool: return not World.items.has(int(uids[0])) or World.items.id_of(int(uids[0])) != Forage.HERBS)
	_check(withered, "and wither as they would have")


func _test_drawn() -> void:
	print("\n== drawn standing ==")
	var plant := Client3D.growing_slot(PackedStringArray([Forage.HERBS, Forage.HERBS]))
	_check(plant in Forage.PLANTS and ArtKit.has(plant), "a pile of herbs stands as %s" % plant)
	_check(Client3D.growing_slot(PackedStringArray([Forage.HERBS, "wood_bundle"])).is_empty()
			and Client3D.growing_slot(PackedStringArray()).is_empty(), "with anything else in it, things")


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_failures += 1
