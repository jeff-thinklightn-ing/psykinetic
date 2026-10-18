extends Node
## The wildlife's herds (decision 367), on a clock of their own with the
## real rules (levels/economy.json "herds") and made-up ground: an outdoor
## area is seeded once to half what its ground keeps, in groups of each
## species' size about cells of its floor, an indoor one never; herds breed
## toward capacity and never past it, wolves keep their prey lower; once a
## day a group roams its home within its roam, a big one splits; saved and
## loaded as they were; as the far tier's keeper (decision 352) a group is
## made into bodies near someone (out_per_group, out_per_zone), each with
## its group and home, kept animals conserved, retire takes one back, a
## kill is gone for good, a flight moves it to the next area's group; old
## animal records fold into groups (not a level's own slots); a body's
## group and home are in its snapshot entry. Taken from (decision 407):
## camps and hunters only above each group's reserve, never from one with
## bodies out, at most take_share of the spare a day; a camp eats by its
## size and camp_fed says how well; a hunter's catch is one animal; wolves
## short of food starve, fed ones do not. Reads the repo's levels, never
## the shared overlay.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const DAY := 54000
const SIZE := 200

var _failures := 0
var _now := 0
var _rules := {}
var _areas := {}
var _bodies: Array[Animal] = []


func _ready() -> void:
	World.set_process(false)
	Level.overlay_dir = preload("res://tests/test_ports.gd").scratch("herds_test/no_overlay/")
	DayNight.day_steps = DAY
	_rules = Production.read_rules().get("herds", {})
	var open := {}
	for y in SIZE:
		for x in SIZE:
			open[Vector2i(x, y)] = true
	var cave := {}
	for y in 40:
		for x in 40:
			cave[Vector2i(x, y)] = true
	_areas = {"meadow": {"floor": open, "outdoor": true}, "fields": {"floor": open, "outdoor": true},
		"cave": {"floor": cave, "outdoor": false}}
	_test_seed()
	_test_breed()
	_test_daily()
	_test_saved()
	_test_bodies()
	_test_records()
	_test_taken()
	_test_multiplier()
	for body in _bodies:
		body.free()
	get_tree().quit(1 if _failures > 0 else 0)


func _herds(rules := _rules, saved := {}) -> Herds:
	return Herds.new(saved, _areas, rules, func() -> int: return _now)


func _sum(herds: Herds, area: String) -> float:
	var sum := 0.0
	for each in herds.groups_in(area):
		sum += float(each["count"]) + int(each["out"])
	return sum


func _test_seed() -> void:
	print("\n== seeding: half of what the ground keeps, outdoors only ==")
	_now = 0
	var herds := _herds()
	herds.tick()
	var good := true
	for species: String in _rules["species"]:
		var cap := herds.capacity("meadow", species)
		var have := herds.total("meadow", species)
		var size: Array = _rules["species"][species]["size"]
		var sizes_ok := herds.groups_in("meadow", species).all(func(each: Dictionary) -> bool:
			return float(each["count"]) <= float(size[-1]) and _areas["meadow"]["floor"].has(each["home"]))
		print("  %s: capacity %.1f, seeded %.0f in %d groups" % [species, cap, have, herds.groups_in("meadow", species).size()])
		good = good and cap > 0.0 and absf(have - floorf(cap * float(_rules["seed"]))) < 0.01 and sizes_ok
	_check(good, "each species seeded to half its capacity, groups of its size on the floor")
	_check(herds.capacity("meadow", "deer") > herds.capacity("meadow", "wolf"), "fewer wolves than deer kept")
	_check(herds.groups_in("cave").is_empty() and herds.capacity("cave", "deer") == 0.0, "an indoor area keeps no game")
	var count := herds.groups_in("meadow").size()
	_now = DAY
	herds.tick()
	_check(_sum(herds, "meadow") > 0.0 and herds.groups_in("meadow").size() >= count - 2, "seeded once: a new day does not seed again")
	var again := _herds_at_zero()
	_check(JSON.stringify(again.to_dict()) == JSON.stringify(_herds_at_zero().to_dict()), "the same ground seeds the same herds")


func _herds_at_zero() -> Herds:
	_now = 0
	var herds := _herds()
	herds.tick()
	return herds


func _test_breed() -> void:
	print("\n== breeding toward capacity; wolves keep their prey lower ==")
	var calm := _rules.duplicate(true)
	calm["species"]["wolf"]["eats"] = 0.0
	var tame := _herds(calm)
	var wild := _herds()
	_now = 0
	tame.tick()
	wild.tick()
	var over := false
	for day in 120:
		for step in DAY / World.WORLD_TICK_STEPS:
			_now += World.WORLD_TICK_STEPS
			tame.tick()
			wild.tick()
		for species: String in _rules["species"]:
			over = over or tame.total("meadow", species) > tame.capacity("meadow", species) + 0.01
		if day % 30 == 29:
			print("  day %d: deer %.1f / %.1f (with wolves %.1f), rabbits %.1f / %.1f (%.1f), wolves %.1f" % [day + 1,
				tame.total("meadow", "deer"), tame.capacity("meadow", "deer"), wild.total("meadow", "deer"),
				tame.total("meadow", "rabbit"), tame.capacity("meadow", "rabbit"), wild.total("meadow", "rabbit"),
				wild.total("meadow", "wolf")])
	_check(not over, "no species ever past its capacity")
	_check(tame.total("meadow", "deer") > tame.capacity("meadow", "deer") * 0.6, "deer bred up from half (%.1f of %.1f)" % [tame.total("meadow", "deer"), tame.capacity("meadow", "deer")])
	_check(wild.total("meadow", "rabbit") < tame.total("meadow", "rabbit") and wild.total("meadow", "deer") <= tame.total("meadow", "deer"),
		"wolves keep rabbits and deer lower (%.1f < %.1f)" % [wild.total("meadow", "rabbit"), tame.total("meadow", "rabbit")])
	_check(wild.total("meadow", "rabbit") > 1.0, "but do not eat them out (%.1f rabbits)" % wild.total("meadow", "rabbit"))


func _test_daily() -> void:
	print("\n== once a day: roaming within its roam, a big group splits ==")
	var herds := _herds_at_zero()
	var before := {}
	for each in herds.groups_in("meadow"):
		before[each["id"]] = each["home"]
	_now = DAY
	herds.tick()
	var moved := 0
	var within := true
	for id: String in before:
		var each := herds.group(id)
		if each.is_empty():
			continue
		var home: Vector2i = each["home"]
		var reach := int(_rules["species"][each["species"]]["roam"])
		var far := maxi(absi(home.x - before[id].x), absi(home.y - before[id].y))
		within = within and far <= reach
		moved += 1 if far > 0 else 0
	_check(moved > 0 and within, "homes roamed, each within its roam (%d moved)" % moved)
	var deer := herds.groups_in("meadow", "deer")[0]
	deer["count"] = 20.0
	var groups := herds.groups_in("meadow", "deer").size()
	var all := herds.total("meadow", "deer")
	_now = 2 * DAY
	herds.tick()
	_check(herds.groups_in("meadow", "deer").size() == groups + 1 and absf(float(deer["count"]) - 10.0) < 0.5,
		"a group of 20 deer splits in two")
	_check(absf(herds.total("meadow", "deer") - all) < 1.0, "splitting loses none")


func _test_saved() -> void:
	print("\n== saved and loaded ==")
	var herds := _herds_at_zero()
	_now = DAY + 300
	herds.tick()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(herds.to_dict()))
	var loaded := _herds(_rules, saved)
	_check(JSON.stringify(loaded.to_dict()) == JSON.stringify(herds.to_dict()), "the herds as they were")
	var group: Dictionary = loaded.groups_in("meadow")[0]
	_check(group["home"] is Vector2i and group["count"] is float, "a group's home a cell again, its count a number")
	_now += 300
	loaded.tick()
	_check(loaded.groups_in("meadow").size() == herds.groups_in("meadow").size(), "a loaded world is not seeded again")
	var none := _herds(_rules, {})
	_check(none.groups_in("meadow").is_empty(), "a snapshot from before the herds has none till the tick seeds them")
	var bad := _herds(_rules, {"groups": {"x": {"species": "deer"}, "y": 3}})
	_check(bad.group("x").is_empty() and bad.group("y").is_empty(), "a group that makes no sense is left out")


func _test_taken() -> void:
	print("\n== taken from by camps and hunters, above the reserves; wolves starving (decision 407) ==")
	_now = 0
	var herds := _herds(_rules, {"seeded": ["meadow", "fields", "cave"]})
	var deer := herds._add_group("meadow", "deer", Vector2i(20, 20), 10.0)
	var other := herds._add_group("meadow", "deer", Vector2i(24, 20), 10.0)
	var near := herds._add_group("meadow", "deer", Vector2i(60, 60), 7.0)
	near["out"] = 2  # A player is on these.
	var least := float(_rules["species"]["deer"]["size"][0])
	_check(is_equal_approx(herds.spare(deer), 10.0 - least) and herds.spare(near) == 0.0,
		"a group spares what it has above its reserve (%.1f); one with bodies out nothing" % herds.spare(deer))
	herds.tick()
	var budget := (20.0 - 2.0 * least) * float(_rules["take_share"])
	_check(is_equal_approx(float(herds._budget["meadow"]), budget),
		"the day's budget: take_share of the spare (%.2f)" % float(herds._budget["meadow"]))
	var caught: Array[String] = []
	for i in 10:
		var kind := herds.hunt_one("meadow", Vector2i(0, 0))
		if kind.is_empty():
			break
		caught.append(kind)
	_check(caught.size() == floori(budget) and caught.all(func(k: String) -> bool: return k in ["deer", "stag"]),
		"a hunter catches one deer at a time, within the budget (%s)" % [caught])
	_check(float(deer["count"]) == 10.0 - caught.size() and float(near["count"]) == 7.0, "from the nearest group first; the stalked herd untouched (%.1f, %.1f)" % [deer["count"], near["count"]])
	deer["count"] = least
	other["count"] = least
	_now = DAY
	herds.tick()
	_check(herds.hunt_one("meadow", Vector2i(0, 0)) == "", "nothing above the reserves: no game")

	print("  a camp eats by its size")
	_now = 0
	var fed := _herds(_rules, {"seeded": ["meadow", "fields", "cave"]})
	var herd := fed._add_group("meadow", "deer", Vector2i(30, 30), 10.0)
	var others: Array[Dictionary] = []
	for i in 3:  # Enough to spare at take_share for the camp's fill.
		others.append(fed._add_group("meadow", "deer", Vector2i(36 + 6 * i, 30), 10.0))
	fed.camps = func() -> Array: return [{"id": "meadow/camp", "area": "meadow", "cell": Vector2i(30, 32), "size": 1.0, "faction": "goblins"}]
	_check(fed.camp_fed("meadow/camp") == 1.0, "before a day has passed it reads fed")
	fed.tick()
	for step in DAY / World.WORLD_TICK_STEPS:
		_now += World.WORLD_TICK_STEPS
		fed.tick()
	var eaten: float = 40.0 - float(herd["count"]) - others.reduce(func(sum: float, each: Dictionary) -> float: return sum + float(each["count"]), 0.0)
	_check(eaten > 0.0 and fed.camp_fed("meadow/camp") > 0.9, "the camp ate its fill of a big herd (%.1f, fed %.2f)" % [eaten, fed.camp_fed("meadow/camp")])
	herd["count"] = least + 0.2
	for each in others:
		each["count"] = least
	fed._budget["meadow"] = 0.0  # Today's budget spent: what is left to take is what breeds.
	for step in DAY / World.WORLD_TICK_STEPS:
		_now += World.WORLD_TICK_STEPS
		fed.tick()
	_now += World.WORLD_TICK_STEPS
	fed.tick()
	_check(fed.camp_fed("meadow/camp") < 0.9 and float(herd["count"]) >= least - 0.01,
		"a herd at its reserve: the camp goes short, eating only what breeds (fed %.2f), the herd kept (%.2f)" % [fed.camp_fed("meadow/camp"), herd["count"]])
	var again := _herds(_rules, JSON.parse_string(JSON.stringify(fed.to_dict())))
	_check(is_equal_approx(again.camp_fed("meadow/camp"), fed.camp_fed("meadow/camp")), "how it ate is saved")

	print("  wolves short of food starve")
	var hungry := _herds(_rules, {"seeded": ["meadow", "fields", "cave"]})
	var pack := hungry._add_group("meadow", "wolf", Vector2i(50, 50), 5.0)
	hungry._hunt("meadow", "wolf", 1.0)
	_check(is_equal_approx(float(pack["count"]), 5.0 - float(_rules["starve"]) * 5.0), "no prey: they lose starve x their number a day (%.2f)" % pack["count"])
	var full := _herds(_rules, {"seeded": ["meadow", "fields", "cave"]})
	var pack2 := full._add_group("meadow", "wolf", Vector2i(50, 50), 5.0)
	full._add_group("meadow", "rabbit", Vector2i(52, 50), 30.0)
	full._hunt("meadow", "wolf", 1.0)
	_check(float(pack2["count"]) == 5.0, "fed, they keep their number")


func _test_multiplier() -> void:
	print("
== a level's own wildlife (decision 367 amended) ==")
	var plain := _herds()
	var areas := _areas.duplicate(true)
	areas["meadow"]["herds"] = {"all": 2.5, "wolf": 4.0}
	var rich := Herds.new({}, areas, _rules, func() -> int: return _now)
	_check(is_equal_approx(rich.capacity("meadow", "deer"), plain.capacity("meadow", "deer") * 2.5), "\"all\": 2.5 keeps two and a half times the deer")
	_check(is_equal_approx(rich.capacity("meadow", "wolf"), plain.capacity("meadow", "wolf") * 10.0), "\"wolf\": 4 on top: ten times the wolves")
	_check(is_equal_approx(rich.capacity("fields", "deer"), plain.capacity("fields", "deer")), "another level as it was")
	_now = 0
	rich.tick()
	plain.tick()
	_check(rich.total("meadow", "wolf") > plain.total("meadow", "wolf") * 5.0, "seeded by it (%.0f wolves, %.0f)" % [rich.total("meadow", "wolf"), plain.total("meadow", "wolf")])
	var empty: Array[String] = []
	_check(Herds.areas_of(WorldMap.build(empty)).is_empty(), "(areas_of with no levels)")


func _spawn(spec: Dictionary) -> Object:
	var body := Animal.new()
	body.spawn_spec = spec
	body.tile = spec["tile"]
	_bodies.append(body)
	return body


func _test_bodies() -> void:
	print("\n== bodies near someone: the far tier's keeper ==")
	var herds := _herds_at_zero()
	var zone := "meadow"
	herds.here = func() -> String: return zone
	herds.spawn = _spawn
	herds.free_near = func(cell: Vector2i, _reach: int) -> Vector2i: return cell
	var all := _sum(herds, "meadow")
	var deer: Dictionary = herds.groups_in("meadow", "deer")[0]
	var home: Vector2i = deer["home"]
	var made := _bodies.size()
	herds.recall_near(home, 0)
	var out := _bodies.slice(made)
	_check(int(deer["out"]) == mini(floori(float(deer["count"]) + int(deer["out"])), int(_rules["out_per_group"])) and out.size() == int(deer["out"]),
		"the deer at hand made bodies (%d), out_per_group at most" % out.size())
	_check(out.all(func(body: Animal) -> bool:
		return body.spawn_spec["group"] == deer["id"] and body.spawn_spec["home"] == home and str(body.spawn_spec["kind"]) in ["deer", "stag"]),
		"each body has its group, its home and a deer's kind")
	_check(out.all(func(body: Animal) -> bool: return herds.takes(body)), "the keeper takes them")
	var plain := _spawn({"tile": Vector2i.ZERO, "kind": "deer"}) as Animal
	_check(not herds.takes(plain), "an animal with no group is not the herds' (perf's records)")
	_check(absf(_sum(herds, "meadow") - all) < 0.001, "making bodies keeps every animal counted")
	herds.recall_near(Vector2i(SIZE / 2, SIZE / 2), SIZE)
	var bodies := 0
	for each in herds.groups_in("meadow"):
		bodies += int(each["out"])
	_check(bodies == int(_rules["out_per_zone"]), "out_per_zone bodies in the zone at most (%d)" % bodies)
	zone = "fields"
	var elsewhere := _bodies.size()
	herds.recall_near(home, 0)
	_check(_bodies.size() == elsewhere, "only the zone World is in makes its groups")
	zone = "meadow"
	var body: Animal = out[0]
	var kept := float(deer["count"])
	herds.retire(body)
	_check(int(deer["out"]) == out.size() - 1 and float(deer["count"]) == kept + 1.0, "retired, it is kept in its group's count again")
	herds.killed(str(deer["id"]), "deer")
	_check(int(deer["out"]) == out.size() - 2 and absf(_sum(herds, "meadow") - (all - 1.0)) < 0.001, "a kill is gone for good")
	var into := herds.moved(str(deer["id"]), "fields", Vector2i(3, 3))
	_check(int(deer["out"]) == out.size() - 3 and float(herds.group(into)["count"]) >= 1.0 and int(herds.group(into)["out"]) == 0
		and herds.group(into)["area"] == "fields", "a flight off the edge: kept in a deer group in the next area (%s)" % into)
	_check(herds.moved(str(deer["id"]), "fields", Vector2i(5, 3)) == into, "the next one joins the same group there")
	var gone := herds.groups_in("meadow", "boar")[0]
	gone["count"] = 0.0
	gone["out"] = 0
	var boar := _spawn({"tile": gone["home"], "kind": "boar", "group": "no_such_group", "zone": "meadow"}) as Animal
	herds.retire(boar)
	_check(herds.total("meadow", "boar") >= 1.0, "a body whose group is gone joins its kind's nearest, or a new one")


func _test_records() -> void:
	print("\n== animals kept as records before the herds fold into groups ==")
	var herds := _herds_at_zero()
	var all := herds.total("meadow", "rabbit")
	var records := [
		{"entry": {"name": "Herd1_2_rabbit_1", "kind": "rabbit", "tile": [10, 10], "spawn": -1}},
		{"entry": {"name": "Imp", "kind": "imp", "tile": [12, 10], "spawn": -1}},
		{"entry": {"name": "Hare", "kind": "rabbit", "tile": [14, 10], "spawn": 3}},
	]
	var left := herds.fold_records("meadow", records)
	_check(herds.total("meadow", "rabbit") == all + 1.0, "the rabbit record is a rabbit of a group")
	_check(left.size() == 2 and left[0]["entry"]["name"] == "Imp" and left[1]["entry"]["name"] == "Hare",
		"a monster's record and a level's own animal stay records")
	var parsed := Snapshot.parse_entry({"script": "res://sim/animal.gd", "name": "meadow_deer_1_1", "tile": [4, 5],
		"kind": "deer", "group": "meadow_deer_1", "home": [6, 7]})
	_check(parsed["spec"].get("group") == "meadow_deer_1" and parsed["spec"].get("home") == Vector2i(6, 7),
		"a body's group and home come back from its snapshot entry")
	var before := Snapshot.parse_entry({"script": "res://sim/animal.gd", "name": "Old", "tile": [4, 5], "kind": "deer"})
	_check(not before["spec"].has("group") and not before["spec"].has("home"), "an entry from before has neither")


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
