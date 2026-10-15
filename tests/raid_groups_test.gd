extends Node
## Raid groups on the world map (decision 328), on two areas side by side: a
## goblin camp in one, the town's store in the other. The camps make the
## town's threat; nothing is sent while raids are off; a group set out walks
## the route on its faction's layer, never on the town's ground; at a town
## nobody watches it raids by the numbers (Towns.raid_arrives) and carries
## food and a captive home, where the captive is held at the camp; a group
## walking into an awake zone is handed to World.raids (a stand-in here) and
## stands still until it is handed back, then goes on, not walking straight
## back in; a beaten group is gone; a restart keeps the groups and the
## switch, one in play going on from where it was. Run it with tests/run.ps1
## or tests/run.sh.

const RaidsTest := preload("res://tests/raids_test.gd")
const TOWN := "rg_town/store"
const CAMP := "rg_camp/camp"
const RULES := {"send_chance": 1000.0, "strength_per_size": 2.0, "steps_per_world_tick": 12.0}


## World.raids as far as raid groups use it.
class StubRaids:
	extends RefCounted
	signal raid_left(group_id: String, strength: float, area: String, cell: Vector2i, carries: Dictionary)
	signal raid_done(group_id: String, report: Dictionary)
	signal raid_beaten(group_id: String, area: String, cell: Vector2i)
	var entered: Array = []

	func enter(group: Dictionary, area: String, arrival: Vector2i, goal: Vector2i) -> int:
		entered.append({"group": group, "area": area, "arrival": arrival, "goal": goal})
		return 3


var _failures := 0
var _now := 0
var _towns: Towns
var _holdings: Holdings
var _groups: WorldRaids


func _ready() -> void:
	World.set_process(false)
	_register()
	_fresh({})
	_test_threat()
	_test_unseen_raid()
	_test_handed_over()
	_test_saved()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## Two strips of open ground, 30 by 5 cells, joined east to west.
func _register() -> void:
	var rows: Array[String] = []
	for y in 2 * 5 - 1:
		rows.append(".".repeat(2 * 30 - 1))
	var strip := Level.image_from_rows(rows)
	Level.register("rg_camp", strip, null, {"neighbours": {"east": "rg_town"},
		"places": {"camp": {"at": [3, 2], "kind": "camp", "holder": "goblins", "worth": 10}}})
	Level.register("rg_town", strip, null, {"neighbours": {"west": "rg_camp"},
		"places": {"store": {"at": [20, 2], "kind": "stockpile", "holder": "town", "radius": 3}}})


func _fresh(saved: Dictionary) -> void:
	var clock := func() -> int: return _now
	var book := ItemBook.new(clock)
	var stock := Stockpile.new({}, clock, book)
	stock.deposit(TOWN, "food", 40, "test")
	var work := Production.new({}, stock, null, clock, RaidsTest.RULES, func() -> Dictionary: return RaidsTest.CATALOG)
	_towns = Towns.new({}, work, RaidsTest.RULES, clock)
	_towns.note_rescue(TOWN, "dag", "Dag", "carpenter")
	var names: Array[String] = ["rg_camp", "rg_town"]
	var map := WorldMap.build(names)
	_holdings = Holdings.new(map, Factions.read(), {}, clock)
	_groups = WorldRaids.new(map, _holdings, _towns, saved, RULES)
	_groups.clock = clock
	_groups.routes.wait()


func _tick(times := 1) -> void:
	for i in times:
		_now += 600
		_groups.world_tick()


func _test_threat() -> void:
	print("== the camps make the town's threat ==")
	_check(_groups.camps().size() == 1 and _groups.camps()[0]["id"] == CAMP and _groups.targets("goblins") == _strings([TOWN]),
		"one goblin camp, and the town it would raid (%s)" % [_groups.camps()])
	var threat := _groups.threat_of(TOWN)
	_check(threat > 0.0 and threat < 1.0, "a camp of worth 10 a few dozen steps off threatens the town: %.2f" % threat)
	_check(not _groups.on and not _towns.threat.is_valid(), "off: the town's threat is its own default, not the camps'")
	_tick(5)
	_check(_groups.groups.is_empty(), "and nothing is sent, however likely")
	_groups.set_on(true)
	_check(is_equal_approx(_towns.threat_of(TOWN), threat), "on: Towns.threat is the camps' (%.2f)" % _towns.threat_of(TOWN))


func _test_unseen_raid() -> void:
	print("== a raid nobody watches ==")
	_tick()
	_check(_groups.groups.size() == 1, "a group sets out (%s)" % [_groups.groups.keys()])
	var id: String = _groups.groups.keys()[0] if not _groups.groups.is_empty() else ""
	_tick(3)
	_check(_groups.groups.size() == 1, "one group a camp and a town at a time")
	var on_town_ground := false
	var reached := false
	for i in 40:
		if not _groups.groups.has(id):
			break
		var group: Dictionary = _groups.groups[id]
		if _holdings.ground(group["area"], group["cell"]) == "town":
			on_town_ground = true
		if group["state"] == WorldRaids.HOME:
			reached = true
			break
		_tick()
	_check(reached, "it reaches the town")
	_check(not on_town_ground, "never standing on the town's ground (held ground is physical)")
	var group: Dictionary = _groups.groups.get(id, {})
	var carries: Dictionary = group.get("carries", {})
	_check(int(carries.get("food", 0)) > 0 and carries.get("captives", []).has("dag"),
		"it carries off food and Dag (%s)" % [carries])
	var book := _towns.production.book()
	var sword := book.mint("sword", "stocked")
	book.place(sword, "raid:%s" % id)
	if carries.has("items"):
		carries["items"].append(sword)
	for i in 60:
		if not _groups.groups.has(id):
			break
		_tick()
	var held: Array = _towns.captives(TOWN).map(func(captive: Dictionary) -> String: return str(captive.get("held_by", "")))
	_check(not _groups.groups.has(id) and held.has(CAMP), "home, its captive held at the camp (%s)" % [held])
	var events: Array = book.history(sword).get("events", [])
	_check(book.at_of(sword) == "camp:" + CAMP and not events.is_empty() and events[-1]["kind"] == "carried home",
		"and a sword it took is kept at the camp, its history saying so (decision 348; %s, %s)" % [book.at_of(sword), events.back() if not events.is_empty() else {}])


func _test_handed_over() -> void:
	print("== a group walking into an awake zone ==")
	var stub := StubRaids.new()
	_groups.hook(stub)
	_groups.live = func(area: String) -> bool: return area == "rg_town"
	_tick()
	var id: String = _groups.groups.keys()[0] if not _groups.groups.is_empty() else ""
	for i in 30:
		if _groups.groups.get(id, {}).get("state") == WorldRaids.PRESENT:
			break
		_tick()
	var group: Dictionary = _groups.groups.get(id, {})
	_check(group.get("state") == WorldRaids.PRESENT and stub.entered.size() == 1 and stub.entered[0]["area"] == "rg_town"
		and stub.entered[0]["goal"] == Raids.NO_CELL, "it is handed to World.raids in the town's zone, to march on the town (%s)" % [stub.entered])
	var stood: Vector2i = group.get("cell", Vector2i.ZERO)
	_tick(3)
	_check(_groups.groups[id]["cell"] == stood, "in play it does not move on the world map")
	stub.raid_done.emit(id, {"town": TOWN, "repelled": false, "took": {"food": 5, "items": []}})
	stub.raid_left.emit(id, 4.0, "rg_town", Vector2i(12, 2), {"items": [], "captives": []})
	group = _groups.groups[id]
	_check(group["state"] == WorldRaids.HOME and is_equal_approx(group["strength"], 4.0), "handed back after the raid: going home, as strong as it came back")
	_tick()
	_check(stub.entered.size() == 1, "and not walked straight back into play")
	for i in 30:
		if _groups.groups.get(id, {}).get("area") == "rg_camp":
			break
		_tick()
	_check(_groups.groups.has(id) and _groups.groups[id]["area"] == "rg_camp", "it walks on home on the world map")
	_groups.groups[id]["state"] = WorldRaids.PRESENT
	stub.raid_beaten.emit(id, "rg_camp", Vector2i(5, 2))
	_check(not _groups.groups.has(id), "a beaten group is gone")


func _test_saved() -> void:
	print("== a restart ==")
	var id := _groups.send(CAMP, TOWN)
	_groups.groups[id]["state"] = WorldRaids.PRESENT
	_groups.groups[id]["state_before"] = WorldRaids.OUT
	var saved := _groups.to_dict()
	_fresh(JSON.parse_string(JSON.stringify(saved)))
	_check(_groups.on and _groups.groups.has(id), "raids are still on and the group still out")
	_check(_groups.groups.get(id, {}).get("state") == WorldRaids.OUT, "one in play when saved (raiders are not) goes on from where it was")


func _strings(values: Array) -> Array[String]:
	var out: Array[String] = []
	out.assign(values)
	return out


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
