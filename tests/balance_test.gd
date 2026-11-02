extends Node
## Keep the balance (decision 761, phase 1) on a clock of its own, with the
## real rules (levels/economy.json "balance" and "herds") and made-up
## ground: a test area whose herds say "balance" (no real level keeps it)
## beside one that doesn't. Wolves the area holds follow its deer and the
## meat lying; meat lies from where it lands till it is taken up, eaten or
## rots, and who left it is noted; meat brought to a store counts home; a
## fold that loses sheep asks, and is judged: balanced (lambs, wool and meat
## to the town), off (thinned too far: the flock lost, back some days on) or
## badly (meat left lying: the flock lost and wolves at the town's nights,
## cleared by killing them or once their nights pass); no sheep counted
## while the wolves are out as bodies; Herds.fed; saved and loaded as it was.
## Reads the repo's levels, never the shared overlay.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const DAY := 54000
const SIZE := 200
const FOLD := "meadow/fold"
const TOWN := "meadow/town"
const AT := Vector2i(100, 100)

var _failures := 0
var _now := 0
var _areas := {}
var _herds: Herds
var _stock: Stockpile
var _balance: Balance
var _ids := {}
var _removed: Array = []
var _asked: Array = []
var _judged: Array = []
var _threats: Array = []


func _ready() -> void:
	World.set_process(false)
	Level.overlay_dir = preload("res://tests/test_ports.gd").scratch("balance_test/no_overlay/")
	DayNight.day_steps = DAY
	var open := {}
	for y in SIZE:
		for x in SIZE:
			open[Vector2i(x, y)] = true
	_areas = {"meadow": {"floor": open, "outdoor": true, "herds": {"balance": true}},
		"fields": {"floor": open, "outdoor": true}}
	_test_capacity()
	_test_meat()
	_test_balanced()
	_test_off()
	_test_badly()
	_test_bodies_out()
	_test_fed()
	_test_saved()
	_test_ask_now()
	_herds.balance = null  # The two hold each other: let them go.
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + what)
	if not ok:
		_failures += 1


## A fresh world: herds with their ground weighed and seeded, a stockpile, a
## fold of 8 sheep selling to TOWN, and the balance over them.
func _fresh() -> void:
	if _herds != null:
		_herds.balance = null  # The last pair hold each other: let them go.
	_now = 0
	_herds = Herds.new({}, _areas, {}, func() -> int: return _now)
	_herds.camps = func() -> Array: return []
	_stock = Stockpile.new({}, func() -> int: return _now)
	_balance = Balance.new({}, _herds, _stock, {}, func() -> int: return _now)
	_herds.balance = _balance
	_balance.id_of = func(uid: int) -> String: return str(_ids.get(uid, ""))
	_balance.folds = func() -> Array:
		return [{"id": FOLD, "area": "meadow", "cell": AT, "town": TOWN, "farmer": "Asa"}]
	_removed.clear()
	_balance.remove = func(area: String, cell: Vector2i, uid: int, why: String) -> bool:
		_removed.append([area, cell, uid, why])
		return true
	_asked.clear()
	_judged.clear()
	_threats.clear()
	_balance.asked.connect(func(id: String) -> void: _asked.append(id))
	_balance.judged.connect(func(id: String, result: String) -> void: _judged.append([id, result]))
	_balance.threat_changed.connect(func(town: String, kind: String, on: bool) -> void: _threats.append([town, kind, on]))
	_stock.deposit(FOLD, "sheep", 8, "Asa", "a drove of their own")
	_stock.deposit(TOWN, "food", 10, "test", "")
	_stock.deposit(TOWN, "meat", 2, "test", "")
	for i in 40:
		_herds.tick()
		_now += 10
	_herds.tick()


## [param area]'s [param species] all in its first group, [param count] of
## them (the rest emptied).
func _put(area: String, species: String, count: float) -> void:
	var groups := _herds.groups_in(area, species)
	if groups.is_empty():
		_herds._add_group(area, species, AT, count)
		return
	for each in groups:
		each["count"] = 0.0
	groups[0]["count"] = count


## [param days] whole days on, ticked ten times a day.
func _days(days: float) -> void:
	for i in roundi(days * 10.0):
		_now += DAY / 10
		_herds.tick()
		_balance.tick()


## Days on until [param done] says so or [param most] pass: whether it did.
func _until(done: Callable, most: int) -> bool:
	for i in most * 10:
		if done.call():
			return true
		_now += DAY / 10
		_herds.tick()
		_balance.tick()
	return done.call()


## The test area at the quest's start: deer at [param share] of what the
## ground keeps, six wolves.
func _start(share: float) -> float:
	var room := _herds.capacity("meadow", "deer")
	_put("meadow", "deer", room * share)
	_put("meadow", "wolf", 6.0)
	return room


func _test_capacity() -> void:
	print("\n== the wolves an area keeping the balance holds: its deer and the meat lying ==")
	_fresh()
	var room := _herds.capacity("meadow", "deer")
	_check(room >= 40.0, "the test area's ground keeps deer enough (%.1f)" % room)
	_put("meadow", "deer", 48.0)
	_check(is_equal_approx(_herds.capacity("meadow", "wolf"), 6.0), "48 deer hold 6 wolves (%.2f)" % _herds.capacity("meadow", "wolf"))
	_ids[9001] = "meat"
	_ids[9002] = "meat"
	_ids[9003] = "hide"
	_balance.cell_changed("meadow", AT, PackedInt32Array([9001, 9002, 9003]))
	_check(_balance.lying("meadow") == 2, "two meat lying, the hide not counted (%d)" % _balance.lying("meadow"))
	_check(is_equal_approx(_herds.capacity("meadow", "wolf"), 6.5), "and they hold half a wolf more (%.2f)" % _herds.capacity("meadow", "wolf"))
	var breed := float(_balance.rules.get("wolf_breed", 1.0))
	_check(is_equal_approx(_balance.breed_factor("meadow"), breed * 2.0), "and the wolves breed twice as fast (%.1f)" % _balance.breed_factor("meadow"))
	_check(not _balance.steers("fields", "wolf") and _herds.capacity("fields", "wolf") > 0.0 			and not is_equal_approx(_herds.capacity("fields", "wolf"), _herds.total("fields", "deer") / 8.0),
		"an area that doesn't keep it holds wolves by its ground, as ever")
	_balance.cell_changed("fields", AT, PackedInt32Array([9001]))
	_check(_balance.lying("fields") == 0, "and its meat isn't counted")
	# Past what they hold, wolves leave.
	_put("meadow", "wolf", 12.0)
	_balance.cell_changed("meadow", AT, PackedInt32Array())
	_days(1.0)
	var wolves := _herds.total("meadow", "wolf")
	_check(wolves < 9.0 and wolves > 6.5, "twelve wolves where six are held: most of the excess leave in a day (%.2f)" % wolves)


func _test_meat() -> void:
	print("\n== meat lying: taken up, brought home, eaten, rotted; who left it ==")
	_fresh()
	_start(0.8)
	_until(func() -> bool: return not _asked.is_empty(), 6)
	_check(_asked.size() == 1, "six wolves on plenty of deer take sheep, and the fold asks (%d sheep left)" % _stock.count(FOLD, "sheep"))
	var cell := AT + Vector2i(3, 0)
	for uid in [101, 102, 103, 104]:
		_ids[uid] = "meat"
	_balance.cell_changed("meadow", cell, PackedInt32Array([101, 102, 103, 104]), {101: "Bo", 102: "Bo", 103: "Bo", 104: "Cy"})
	var near := _balance.meat_near("meadow", AT, 5)
	_check(near.size() == 4 and near[0]["cell"] == cell, "meat near the fold, found within reach (%d)" % near.size())
	_check(_balance.meat_near("meadow", AT, 2).is_empty(), "and not beyond it")
	# Bo takes one up and brings it to the store.
	_balance.cell_changed("meadow", cell, PackedInt32Array([102, 103, 104]))
	_check(_balance.lying("meadow") == 3, "one taken up: three lying")
	_balance.banked(101, "Bo")
	var quest := _balance.quest(FOLD)
	_check(int(quest["home"]) == 1 and int(quest["home_by"].get("Bo", 0)) == 1, "and it's brought home, by Bo (%s)" % [quest["home_by"]])
	_check(_balance.eat(104) and not _balance.eat(104), "a wolf eats Cy's: once")
	_check(_removed.size() == 1 and _removed[0][2] == 104 and _removed[0][3] == "eaten by wolves", "taken off the ground as eaten (%s)" % [_removed])
	_days(1.0)
	quest = _balance.quest(FOLD)
	_check(_balance.lying("meadow") == 0 and int(quest["left"]) == 3, "a day on the rest has rotted: three left lying (%d)" % int(quest["left"]))
	_check(int(quest["left_by"].get("Bo", 0)) == 2 and int(quest["left_by"].get("Cy", 0)) == 1, "the ledger: Bo left two, Cy one (%s)" % [quest["left_by"]])


func _test_balanced() -> void:
	print("\n== thinned to the band and the meat brought home: balanced, the farm thrives ==")
	_fresh()
	var room := _start(0.85)
	_check(_until(func() -> bool: return not _asked.is_empty(), 10), "the fold asks (day %d)" % (_now / DAY))
	var sheep := _stock.count(FOLD, "sheep")
	_put("meadow", "deer", room * 0.45)
	_check(_until(func() -> bool: return not _judged.is_empty(), 6), "judged at the deadline")
	_check(_judged.size() == 1 and _judged[0][1] == "balanced", "balanced (%s; wolves %.1f, deer %.1f of %.1f)" % [_judged, _herds.total("meadow", "wolf"), _herds.total("meadow", "deer"), room])
	var most := int(_balance.rules.get("judge", {}).get("lost_most", 1))
	_check(_stock.count(FOLD, "sheep") >= sheep - most + int(_balance.rules.get("thrive", {}).get("lambs", 2)),
		"lambs to the fold, past the few lost (%d from %d)" % [_stock.count(FOLD, "sheep"), sheep])
	_check(_stock.count(TOWN, "wool") == 4 and _stock.count(TOWN, "meat") == 5, "wool and meat to the town (%d, %d)" % [_stock.count(TOWN, "wool"), _stock.count(TOWN, "meat")])
	_check(_balance.quest(FOLD).is_empty() and _threats.is_empty(), "the quest is done, and no threat")


func _test_off() -> void:
	print("\n== thinned too far: hungry wolves take the flock; it comes back ==")
	_fresh()
	var room := _start(0.85)
	_until(func() -> bool: return not _asked.is_empty(), 10)
	_put("meadow", "deer", room * 0.1)
	_check(_balance.hunger("meadow") > 0.5, "the wolves go hungry (%.2f)" % _balance.hunger("meadow"))
	_until(func() -> bool: return not _judged.is_empty(), 6)
	_check(_judged.size() == 1 and _judged[0][1] == "off", "off (%s)" % [_judged])
	_check(_stock.count(FOLD, "sheep") == 0, "the flock is lost")
	_check(_threats.is_empty(), "no wolves at the town for it")
	_days(5.0)
	_check(_stock.count(FOLD, "sheep") == 3, "five days on, a flock again (%d)" % _stock.count(FOLD, "sheep"))


func _test_badly() -> void:
	print("\n== meat left lying: badly off, the wolves come to the town ==")
	_fresh()
	_start(0.85)
	_until(func() -> bool: return not _asked.is_empty(), 10)
	var uids := PackedInt32Array()
	for i in 14:
		_ids[500 + i] = "meat"
		uids.append(500 + i)
	_balance.cell_changed("meadow", AT + Vector2i(10, 10), uids, {})
	_check(_herds.capacity("meadow", "wolf") > _herds.total("meadow", "deer") / 8.0 + 3.0, "fourteen meat lying hold over three wolves more")
	_until(func() -> bool: return not _judged.is_empty(), 6)
	_check(_judged.size() == 1 and _judged[0][1] == "badly", "badly off (%s)" % [_judged])
	_check(_stock.count(FOLD, "sheep") == 0, "the flock is lost")
	_check(_threats.size() == 1 and _threats[0] == [TOWN, "wolves", true], "and wolves come to the town (%s)" % [_threats])
	_check(_balance.threat(TOWN) == "wolves" and _balance.wolves_at(TOWN) == 3, "three of them")
	_stock.deposit(TOWN, "meat", 2, "test", "")
	var meat := _stock.count(TOWN, "meat")
	_check(_balance.night_take(TOWN) == "meat" and _stock.count(TOWN, "meat") == meat - 1, "one at the store takes meat (%d)" % meat)
	_check(_stock.count(TOWN, "gold") == 0 and _balance.night_take("elsewhere") == "", "never gold; nothing where there are none")
	_balance.town_wolf_killed(TOWN)
	_balance.town_wolf_killed(TOWN)
	_check(_balance.threat(TOWN) == "wolves", "two killed: one still to come")
	_balance.town_wolf_killed(TOWN)
	_check(_balance.threat(TOWN) == "" and _threats.back() == [TOWN, "wolves", false], "the third killed: cleared (%s)" % [_threats])
	# Left alone, they take what they find each night and go back after three.
	_fresh()
	_start(0.85)
	_until(func() -> bool: return not _asked.is_empty(), 10)
	_balance.cell_changed("meadow", AT + Vector2i(10, 10), uids, {})
	_until(func() -> bool: return not _judged.is_empty(), 6)
	var food := _stock.count(TOWN, "food") + _stock.count(TOWN, "meat")
	_days(3.0)
	_check(_balance.threat(TOWN) == "" and _stock.count(TOWN, "food") + _stock.count(TOWN, "meat") < food, "unmet, they eat into the store and go back after their nights (%d -> %d)" % [food, _stock.count(TOWN, "food") + _stock.count(TOWN, "meat")])


func _test_bodies_out() -> void:
	print("\n== wolves out as bodies take sheep themselves: no count beside them ==")
	_fresh()
	_start(0.85)
	_herds.groups_in("meadow", "wolf")[0]["out"] = 2
	var sheep := _stock.count(FOLD, "sheep")
	# The balance alone (the herds' day would take the bodies back: none here).
	for i in 60:
		_now += DAY / 10
		_balance.tick()
	_check(_stock.count(FOLD, "sheep") == sheep and _asked.is_empty(), "six days with bodies out: no sheep counted (%d)" % _stock.count(FOLD, "sheep"))
	_check(_balance.take_sheep(FOLD) and _stock.count(FOLD, "sheep") == sheep - 1, "a body takes one through take_sheep")
	var fold: Dictionary = _balance.folds_in("meadow")[0]
	_check(fold["id"] == FOLD and int(fold["sheep"]) == sheep - 1 and _balance.folds_in("fields").is_empty(), "the fold as enemy-ai reads it (%s)" % [fold])


func _test_fed() -> void:
	print("\n== Herds.fed: a pack's last day ==")
	_fresh()
	_start(0.85)
	var wolves: String = _herds.groups_in("meadow", "wolf")[0]["id"]
	var deer: String = _herds.groups_in("meadow", "deer")[0]["id"]
	_days(1.1)
	_check(is_equal_approx(_herds.fed(wolves), 1.0), "fed on plenty of deer (%.2f)" % _herds.fed(wolves))
	_check(_herds.fed(deer) == 1.0 and _herds.fed("nobody") == 1.0, "deer hunt nothing; no group, 1")
	_put("meadow", "deer", 0.0)
	_put("meadow", "rabbit", 0.0)  # Their other prey.
	_put("meadow", "wolf", 6.0)
	_days(2.5)
	_check(_herds.fed(wolves) < 0.1, "no deer, no rabbits: unfed (%.2f)" % _herds.fed(wolves))


## Asked now (the console's "balance ask": tours and tests): a calm fold's
## quest opens at once, once; no such fold, why not.
func _test_ask_now() -> void:
	print("== asked now ==")
	_fresh()
	_start(0.3)
	_days(1.0)
	_check(_asked.is_empty(), "a calm fold has not asked")
	_check(_balance.ask_now(FOLD) == "" and _asked == [FOLD] and not _balance.quest(FOLD).is_empty(), "asked now (%s)" % [_asked])
	_check(_balance.ask_now(FOLD) == "already asked" and _asked.size() == 1, "once")
	_check(not _balance.ask_now("nowhere").is_empty(), "no such fold: why not")
	_check(_balance.calm("meadow") > 0.0 and _balance.calm("fields") > 0.0, "the calm wolves, by the deer room (%.1f)" % _balance.calm("meadow"))


func _test_saved() -> void:
	print("\n== saved and loaded as it was ==")
	_fresh()
	_start(0.85)
	_until(func() -> bool: return not _asked.is_empty(), 10)
	_ids[700] = "meat"
	_balance.cell_changed("meadow", AT, PackedInt32Array([700]), {700: "Bo"})
	_balance.cell_changed("meadow", AT, PackedInt32Array())
	_ids[701] = "meat"
	_balance.cell_changed("meadow", AT, PackedInt32Array([701]), {701: "Cy"})
	var saved := _balance.to_dict()
	var again := Balance.new(JSON.parse_string(JSON.stringify(saved)), _herds, _stock, {}, func() -> int: return _now)
	_check(JSON.stringify(again.to_dict()) == JSON.stringify(saved), "the same again through JSON")
	_check(again.lying("meadow") == 1, "its meat lying")
	_check(JSON.stringify(again.quest(FOLD)) == JSON.stringify(_balance.quest(FOLD)), "and its quest (%s / %s)" % [again.quest(FOLD), _balance.quest(FOLD)])
	again.banked(700, "")
	_check(int(again.quest(FOLD)["home_by"].get("Bo", 0)) == 1, "and meat taken up before still counts home, Bo's")
