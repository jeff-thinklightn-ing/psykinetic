extends Node
## Raids on a town (Towns.raid_arrives, decision 295) on a clock of its own,
## with Production and a stockpile beneath it and a test catalog and rules:
## a group no stronger than the town's defence (walls by level, residents
## in town) is fought off; a stronger one takes food only (stockpile food,
## then meals from the shop), its losses in the ledger by "raid:<faction>",
## which turns the town to defend; past a margin it damages a building
## (walls first), past a greater one it carries off a resident; gold, ore, wood, experience and levels are never taken. A
## damaged building stops its work and a carpenter repairs it first, for
## half its cost and time; a captive waits, held where maps says, and is
## home as themselves when rescued; a restart keeps the captives; threat
## from a hook, else from the town's safety, puts walls first. A companion
## (decision 331): a resident whose player is known is taken only when
## nobody plays the town, Main told (in play nobody is carried off by
## the numbers; a resident beaten down is taken by resident_taken); one taken in play gets her captive
## entry when her group is home (carried_home); rescued, Main frees her
## into the town.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const TOWN := "rt/store"
const CATALOG := {
	"meal": {"id": "meal", "tags": ["food"], "made": {"by": "cook", "from": {"food": 2}, "steps": 600}},
	"sword": {"id": "sword", "tags": ["weapon"], "made": {"by": "smith", "from": {"ore": 3}, "steps": 3000}},
}
const RULES := {
	"window": 6000, "tier_hold": 1, "starve_after": 3,
	"comfort": {"gold": 50, "ore": 5, "wood": 5, "cloth": 2, "food": 4},
	"wants": {}, "shop_cap": 0,
	"tiers": {"defend": [], "stock": [], "surplus": []},
	"work_up": {}, "busy": {"quiet_below": 0, "busy_from": 100000},
	"wage": 0, "rent": 0, "rent_every": 6000, "gold_floor": 0, "level_speed": 0.25,
	"xp": {"rescue": 10, "objective": 50},
	"residents": {"base": 6, "per_inn": 3},
	"raids": {
		"raiders": "goblins",
		"defence": {"per_wall_level": 4, "per_resident": 1},
		"takes": [{"what": "food", "share": 0.5}, {"tag": "food", "count": 2}],
		"damage": {"margin": 3, "prefer": ["walls", "kitchen", "forge"]},
		"captives": {"margin": 6, "count": 1},
		"repair": {"share": 0.5},
		"threat_default": {"threatened": 0.6, "uneasy": 0.3, "safe": 0.0},
		"walls_from": 0.5,
	},
	"buildings": {
		"forge": {"trade": "smith", "built_by": "carpenter", "xp": 0, "cost": {"wood": 10, "ore": 5}, "steps": 6000, "max_level": 1},
		"walls": {"built_by": "carpenter", "xp": 0, "cost": {"wood": 20}, "steps": 6000, "max_level": 1},
	},
}

var _failures := 0
var _now := 0
var _book: ItemBook
var _stock: Stockpile
var _work: Production
var _towns: Towns
var _reports: Array[Dictionary] = []
var _changed: Array[String] = []
var _last_state := {}


func _ready() -> void:
	World.set_process(false)
	_fresh()
	_test_town_ready()
	_test_fought_off()
	_test_raided()
	_test_worse()
	_test_repair()
	_test_rescue()
	_test_restart()
	_test_threat()
	_test_companions()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _fresh() -> void:
	_now = 0
	var clock := func() -> int: return _now
	_book = ItemBook.new(clock)
	_stock = Stockpile.new({}, clock, _book)
	for what: String in ["gold", "ore", "wood", "food"]:
		_stock.deposit(TOWN, what, {"gold": 100, "ore": 30, "wood": 60, "food": 40}[what], "test")
	_work = Production.new({}, _stock, null, clock, RULES, func() -> Dictionary: return CATALOG)
	_towns = Towns.new({}, _work, RULES, clock)
	_towns.raided.connect(func(town: String, report: Dictionary) -> void: _reports.append(report))
	_towns.building_changed.connect(func(_town: String, kind: String) -> void:
		# Each building's change of state: a build's or a repair's stages
		# (decision 566) tell the views again in the same state.
		var state := str(_towns.building(_town, kind).get("state", ""))
		if not kind.is_empty() and _last_state.get(kind) != state:
			_last_state[kind] = state
			_changed.append("%s %s" % [kind, state]))


func _at(step: int) -> void:
	_now = step
	_towns.tick()
	_work.tick()


func _test_town_ready() -> void:
	print("\n== a town with walls, a forge, three residents and meals ==")
	_towns.note_rescue(TOWN, "dag", "Dag", "carpenter")
	_towns.note_rescue(TOWN, "bram", "Bram", "smith")
	_towns.note_companion_in(TOWN, "Wren", "cook")
	_towns.unlock(TOWN, "walls")
	_at(0)
	_at(6000)
	_towns.unlock(TOWN, "forge")
	_at(6000)
	_at(12000)
	for i in 3:
		_stock.stock_shop(TOWN, _book.mint("meal", "made", "test"), "Wren")
	_check(_towns.building(TOWN, "walls").get("state") == Towns.STANDING and _towns.building(TOWN, "forge").get("state") == Towns.STANDING,
		"walls and forge stand (%s, %s)" % [_towns.building(TOWN, "walls"), _towns.building(TOWN, "forge")])
	_check(_work.workshop_of("bram") == "%s:forge" % TOWN, "Bram works at the forge")
	_check(_towns.defence(TOWN) == 7.0, "defence 7: walls level 1 (4) and three residents (%.1f)" % _towns.defence(TOWN))
	_check(_stock.count(TOWN, "food") == 40 and _stock.shop(TOWN).size() == 3, "40 food in store, 3 meals in the shop")


func _test_fought_off() -> void:
	print("\n== a weak raid is fought off ==")
	_now = 12100
	var report := _towns.raid_arrives(TOWN, {"id": "g1", "faction": "goblins", "strength": 5.0, "from": "forest/camp"})
	_check(report["repelled"] and report["took"] == {"items": []} and report["captives"].is_empty() and report["damaged"] == "",
		"strength 5 against 7: fought off, nothing taken (%s)" % [report])
	_check(_stock.count(TOWN, "food") == 40 and _reports.size() == 1 and _reports[0]["group"] == "g1", "the food untouched; raided told")


func _test_raided() -> void:
	print("\n== a raid that gets past: food, and the walls damaged ==")
	_now = 12200
	var report := _towns.raid_arrives(TOWN, {"id": "g2", "faction": "goblins", "strength": 10.0, "from": "forest/camp"})
	_check(not report["repelled"] and report["margin"] == 3.0, "strength 10 against 7: 3 gets past")
	_check(report["took"].get("food") == 6 and report["took"]["items"].size() == 1 and _stock.count(TOWN, "food") == 34
		and _stock.shop(TOWN).size() == 2, "it takes 6 food (half, at 3/10) and a meal (%s)" % [report["took"]])
	var meal: int = report["took"]["items"][0]
	_check(_book.at_of(meal) == "raid:g2" and _book.history(meal)["events"].any(func(event: Dictionary) -> bool: return event["kind"] == "taken"),
		"the meal is carried by the group in the book")
	_check(report["damaged"] == "walls" and _towns.building(TOWN, "walls")["state"] == Towns.DAMAGED and _towns.building(TOWN, "walls")["level"] == 1,
		"the walls are damaged, still level 1")
	_check(report["captives"].is_empty(), "under 6: nobody is taken")
	_check(_stock.ledger(TOWN).any(func(line: Dictionary) -> bool: return line["by"] == "raid:goblins" and line["what"] == "food" and line["count"] == -6),
		"the ledger says the goblins took 6 food")
	_check(_stock.count(TOWN, "gold") == 100 and _stock.count(TOWN, "ore") == 25 and _stock.count(TOWN, "wood") == 30,
		"gold, ore and wood untouched")
	_check(_towns.defence(TOWN) == 3.0, "damaged walls defend nothing: defence 3")


func _test_worse() -> void:
	print("\n== a strong raid: the forge damaged, Bram carried off ==")
	var xp := _towns.xp_earned(TOWN)
	_now = 12300
	var report := _towns.raid_arrives(TOWN, {"id": "g3", "faction": "goblins", "strength": 14.0, "from": "forest/camp"})
	_check(report["margin"] == 11.0 and report["took"].get("food") == 13 and report["took"]["items"].size() == 2,
		"11 gets past: 13 food and both meals (%s)" % [report["took"]])
	_check(report["damaged"] == "forge" and _towns.building(TOWN, "forge")["state"] == Towns.DAMAGED, "the walls already down, the forge is damaged")
	_check(report["captives"] == [{"id": "bram", "name": "Bram", "trade": "smith"}], "Bram is carried off, the newest who isn't a companion (%s)" % [report["captives"]])
	_check("bram" not in _towns.residents(TOWN) and _work.worker("bram")["away"] and "companion:Wren" in _towns.residents(TOWN),
		"he is no resident now, his work waits; Wren the companion stays")
	var held := _towns.captives(TOWN)
	_check(held.size() == 1 and held[0]["held_by"] == "g3" and held[0]["by"] == "goblins" and held[0]["taken_at"] == 12300,
		"a captive of the goblins, held by the group g3 (%s)" % [held])
	_check(_towns.xp_earned(TOWN) == xp and _towns.building(TOWN, "forge")["level"] == 1, "no experience or level lost")
	_check(not _towns.allows({"trade": "smith", "town": TOWN}), "a damaged forge: no smith works there")
	_at(12400)
	_at(12500)
	_check(_work.tier(TOWN) == Production.DEFEND, "the raids turned the town to defend (%s)" % _work.tier(TOWN))


func _test_repair() -> void:
	print("\n== the carpenter repairs, first of all, for half ==")
	var wood := _stock.count(TOWN, "wood")
	var ore := _stock.count(TOWN, "ore")
	_at(12600)
	var forge := _towns.building(TOWN, "forge")
	var job := _work.job(int(forge["job"]))
	_check(job.get("recipe") == "repair:forge" and job.get("worker") == "dag" and job.get("needed") == 3000,
		"a repair of the forge (first by name), Dag on it, 3000 steps (%s)" % [job])
	_check(job.get("resources") == {"wood": 5, "ore": 3} and _stock.count(TOWN, "wood") <= wood and _stock.count(TOWN, "ore") <= ore,
		"half its cost, taken from the store: 5 wood, 3 ore (%s)" % [job.get("resources")])
	_at(15600)
	_check(_towns.building(TOWN, "forge")["state"] == Towns.STANDING and _towns.building(TOWN, "forge")["level"] == 1,
		"at 15600 the forge stands again, level 1")
	_at(15700)
	var walls := _towns.building(TOWN, "walls")
	_check(_work.job(int(walls["job"])).get("recipe") == "repair:walls", "then the walls")
	_at(18700)
	_check(_towns.building(TOWN, "walls")["state"] == Towns.STANDING and _towns.defence(TOWN) == 6.0,
		"the walls stand: defence 6 (Bram is away)")
	_check(_changed.slice(-4) == ["walls damaged", "forge damaged", "forge standing", "walls standing"]
		and _towns.buildings_of(TOWN) == {"walls": {"state": "standing", "level": 1, "walls": true}, "forge": {"state": "standing", "level": 1, "walls": true}},
		"building_changed told each damage and repair; buildings_of for the views (%s)" % [_changed])


func _test_rescue() -> void:
	print("\n== Bram is held at the camp, then rescued ==")
	_check(_towns.captive_held("bram", "forest/camp") and _towns.captives(TOWN)[0]["held_by"] == "forest/camp",
		"maps says the group is home: held at forest/camp")
	_check(not _towns.captive_held("nobody", "x"), "no such captive: false")
	var xp := _towns.xp_earned(TOWN)
	_check(_towns.note_rescue(TOWN, "bram", "Bram", "smith"), "Bram, freed, reaches the town")
	_check(_towns.captives(TOWN).is_empty() and "bram" in _towns.residents(TOWN) and not _work.worker("bram")["away"]
		and _work.worker("bram")["origin"] == "rescued:bram" and _work.workshop_of("bram") == "%s:forge" % TOWN,
		"home as himself: a resident again, back at his forge")
	_check(_towns.xp_earned(TOWN) == xp + 10, "and the rescue's experience")
	_check(_towns.taken_before("bram") == 1 and _towns.taken_before("dag") == 0, "Bram taken once before, Dag never (taken_before)")


func _test_restart() -> void:
	print("\n== a restart keeps the captives ==")
	_now = 19000
	_towns.raid_arrives(TOWN, {"id": "g4", "faction": "goblins", "strength": 20.0})
	var held := _towns.captives(TOWN)
	var clock := func() -> int: return _now
	var saved: Array = JSON.parse_string(JSON.stringify([_book.to_dict(), _stock.to_dict(), _work.to_dict(), _towns.to_dict()]))
	var book := ItemBook.from_dict(saved[0], clock)
	var stock := Stockpile.new(saved[1], clock, book)
	var work := Production.new(saved[2], stock, null, clock, RULES, func() -> Dictionary: return CATALOG)
	var towns := Towns.new(saved[3], work, RULES, clock)
	_check(held.size() == 1 and towns.captives(TOWN) == held, "the same captive after a restart (%s)" % [held])
	_check(towns.note_rescue(TOWN, held[0]["id"], held[0]["name"], held[0]["trade"]), "and can still be rescued")
	_check(towns.taken_before(held[0]["id"]) == _towns.taken_before(held[0]["id"]) and towns.taken_before(held[0]["id"]) >= 1, "and how often each was taken")


func _test_threat() -> void:
	print("\n== threat: a hook, else the town's safety ==")
	_fresh()
	_check(_towns.threat_of(TOWN) == 0.0, "a fresh town with no territory: safe, 0")
	_towns.raid_arrives(TOWN, {"id": "g5", "strength": 10.0})
	_check(_towns.threat_of(TOWN) == 0.6, "raided: threatened, 0.6 (%.1f)" % _towns.threat_of(TOWN))
	_fresh()
	_check(_towns.choose(TOWN) == "", "safe, nothing waiting: no building wanted")
	_towns.threat = func(_town: String) -> float: return 0.7
	_check(_towns.threat_of(TOWN) == 0.7 and _towns.choose(TOWN) == "walls", "maps says 0.7: walls first")
	_check(_reports.size() >= 5, "raided told each time")


func _test_companions() -> void:
	print("
== companions as captives (decision 331) ==")
	_fresh()
	var calls: Array[String] = []
	var playing := [true]
	_towns.in_play = func(_town: String) -> bool: return playing[0]
	_towns.companion_taken = func(player_id: String, by: String) -> bool:
		calls.append("taken %s by %s" % [player_id, by])
		return true
	_towns.companion_freed = func(player_id: String, place: String) -> bool:
		calls.append("freed %s to %s" % [player_id, place])
		return true
	_towns.companion_of = func(player_id: String) -> Dictionary:
		return {"name": {"p1": "Wren", "p2": "Nix"}.get(player_id, ""), "trade": "cook"}
	_towns.note_rescue(TOWN, "dag", "Dag", "carpenter")
	_towns.note_companion_in(TOWN, "Wren", "cook", "p1")
	_check(_work.worker("companion:Wren")["origin"] == "companion:p1", "Wren in town: her origin her player's id")
	_now = 20000
	var report := _towns.raid_arrives(TOWN, {"id": "g6", "faction": "goblins", "strength": 30.0})
	_check(report["captives"].is_empty() and "companion:Wren" in _towns.residents(TOWN) and "dag" in _towns.residents(TOWN) and calls.is_empty(),
		"the town in play: its raiders' blows take people, not raid_arrives: Wren and Dag stay (%s)" % [report["captives"]])
	playing[0] = false
	report = _towns.raid_arrives(TOWN, {"id": "g7", "faction": "goblins", "strength": 30.0})
	_check(report["captives"] == [{"id": "companion:p1", "name": "Wren", "trade": "cook"}] and calls == ["taken p1 by g7"],
		"nobody there: Wren carried off by her player's id, Main told (%s, %s)" % [report["captives"], calls])
	_check("companion:Wren" not in _towns.residents(TOWN) and _work.worker("companion:Wren")["away"]
		and _towns.captives(TOWN)[0]["held_by"] == "g7", "no resident now, her work waits, held by g7")
	var held := _towns.carried_home(TOWN, "g8", "goblins", ["companion:p1", "companion:p2", "nobody"], "forest/camp")
	var captives := _towns.captives(TOWN)
	_check(held == ["companion:p1", "companion:p2"] and captives.size() == 2 and captives.all(func(each: Dictionary) -> bool: return each["held_by"] == "forest/camp")
		and captives[1]["name"] == "Nix" and captives[1]["origin"] == "companion:p2" and captives[1]["by"] == "goblins",
		"home at forest/camp: Wren held there, and Nix, taken in play, gets her entry (%s)" % [captives])
	var clock := func() -> int: return _now
	var saved: Variant = JSON.parse_string(JSON.stringify(_towns.to_dict()))
	_check(Towns.new(saved, _work, RULES, clock).captives(TOWN) == captives, "a restart keeps both")
	var xp := _towns.xp_earned(TOWN)
	_check(_towns.note_rescue(TOWN, "companion:p2", "Nix", "cook") and calls.back() == "freed p2 to %s" % TOWN
		and _towns.captives(TOWN).size() == 1 and _towns.xp_earned(TOWN) == xp + 10,
		"Nix rescued: Main frees her into the town, the rescue's experience (%s)" % [calls])
	_check(_towns.note_rescue(TOWN, "companion:p1", "Wren", "cook") and calls.back() == "freed p1 to %s" % TOWN
		and _towns.captives(TOWN).is_empty(), "and Wren")
	_check(_towns.resident_taken(TOWN, "dag", "g9") and "dag" not in _towns.residents(TOWN) and _work.worker("dag")["away"]
		and _towns.captives(TOWN).back()["held_by"] == "g9" and _towns.captives(TOWN).back()["by"] == "goblins",
		"Dag beaten down in play: a captive of the goblins, held by g9 (%s)" % [_towns.captives(TOWN).back()])
	_check(not _towns.resident_taken(TOWN, "dag", "g9") and not _towns.resident_taken(TOWN, "nobody", "g9"),
		"no such resident (or one taken already): false")
	_check(_towns.note_rescue(TOWN, "dag", "Dag", "carpenter") and "dag" in _towns.residents(TOWN), "and home again when rescued")
	_check(_towns.taken_before("dag") == 1 and _towns.taken_before("companion:Wren") == 1, "each taken once (%d, %d)" % [_towns.taken_before("dag"), _towns.taken_before("companion:Wren")])


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
