extends Node
## Towns seeded from the map's buildings (decision 306): a building linked
## to its town ("use" and "town", decision 297) stands in it at level 1 when
## the town has no record of it, and a smith waiting for a forge is seated
## at it; seeding again changes nothing; a record the town has (raised,
## damaged) is never lowered or mended by it; a building whose town is no
## stockpile place is left out.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const AREA := "seed_town"
const TOWN := AREA + "/store"

var _failures := 0


func _ready() -> void:
	World.set_process(false)
	_test_seed()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## The world map of one area: the town_store prefab, a hut used as the
## store's forge and a shed used as a kitchen of a town that isn't there.
func _world_map() -> WorldMap:
	var doc := MapDoc.new()
	doc.folder = preload("res://tests/test_ports.gd").scratch("towns_seed_test/")
	doc.map = LevelMap.new(Vector2i(30, 20))
	for y in 20:
		for x in 30:
			doc.map.set_cell(Vector2i(x, y), "grass")
	doc.config = {"name": "Seed Town", "outdoor": true}
	var session := BuilderSession.new(doc, Rect2i(0, 0, 30, 20), AREA, StubClaude.new())
	session.run_tool("stamp", {"prefab": "town_store", "at": [8, 7]})
	session.run_tool("stamp", {"prefab": "building_hut", "at": [16, 8]})
	session.run_tool("stamp", {"prefab": "building_shed", "at": [2, 2]})
	var config: Dictionary = session.working.config.duplicate(true)
	for entry: Dictionary in config.get("buildings", []):
		if entry["slot"] == "building.hut":
			entry["use"] = "forge"
			entry["town"] = "store"
		elif entry["slot"] == "building.shed":
			entry["use"] = "kitchen"
			entry["town"] = "nowhere"
	return WorldMap.build([AREA], {AREA: {"layout": session.working.map.to_image(), "height": null, "config": config}})


func _test_seed() -> void:
	print("\n== the map's buildings stand in their town ==")
	var clock := func() -> int: return 100
	var book := ItemBook.new()
	var stock := Stockpile.new({}, clock, book)
	var work := Production.new({}, stock, null, clock)
	var towns := Towns.new({}, work, {}, clock)
	towns.note_rescue(TOWN, "smith_1", "Odo", "smith")
	_check(towns.building(TOWN, "forge").is_empty() and work.workshop(TOWN + ":forge").is_empty(), "before: no forge, Odo the smith waits for one")
	var world_map := _world_map()
	var linked: Array = world_map.areas[AREA]["buildings"].filter(func(house: Dictionary) -> bool: return not str(house["use"]).is_empty())
	_check(linked.size() == 1 and linked[0]["use"] == "forge" and linked[0]["town"] == "store",
		"the world map has the hut linked as the store's forge; the shed's town is none (%s)" % [linked])
	var changed: Array[String] = []
	towns.building_changed.connect(func(town: String, kind: String) -> void: changed.append(town + ":" + kind))
	var seeded := towns.seed_from(world_map)
	var forge := towns.building(TOWN, "forge")
	_check(seeded == [TOWN + "/forge"] and forge.get("level") == 1 and forge.get("state") == Towns.STANDING,
		"seeded: the forge stands, level 1 (%s, %s)" % [seeded, forge])
	_check(changed == [TOWN + ":forge"], "and building_changed said so (%s)" % [changed])
	_check(work.workshop(TOWN + ":forge").get("worker") == "smith_1", "Odo is seated at it (%s)" % [work.workshop(TOWN + ":forge")])
	_check(towns.building(TOWN, "kitchen").is_empty() and towns.building(AREA + "/nowhere", "kitchen").is_empty(), "the shed, of no town, is no kitchen")
	_check(towns.seed_from(world_map).is_empty() and towns.building(TOWN, "forge")["level"] == 1, "seeded again: nothing changes")
	var saved := towns.to_dict()
	saved[TOWN]["buildings"]["forge"]["level"] = 2
	saved[TOWN]["buildings"]["forge"]["state"] = Towns.DAMAGED
	var later := Towns.new(saved, Production.new(work.to_dict(), stock, null, clock), {}, clock)
	_check(later.seed_from(world_map).is_empty() and later.building(TOWN, "forge")["level"] == 2 and later.building(TOWN, "forge")["state"] == Towns.DAMAGED,
		"a forge the town has at level 2, damaged: left so, not lowered or mended")


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
