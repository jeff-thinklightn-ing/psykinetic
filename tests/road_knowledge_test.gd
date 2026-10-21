extends Node
## RoadKnowledge (decision 551 phase 2, npc's side): what a companion knows
## of the roads and how fresh it is. The road's news heard (a wagon struck
## by a camp becomes a heard danger of the camp's area; home again or lost,
## nothing; one a camp a day), the weight of a route's dangers fading by
## age (whole for fresh_days, nothing at twice that, pruned), a cleared
## camp dropping its heard dangers, a passage halving an area's dangers
## once a day, the words of the worst, and the rules from
## companion_traits.json "guide". Pure sim: no Main, no port, no scratch
## folder; the level is registered in memory. Run it with tests/run.ps1 or
## tests/run.sh. Prints PASS/FAIL per assertion and quits with exit code 1
## if any assertion failed, 0 otherwise.

const ZONE := "rk_wilds"
const CAMP := "rk_wilds/camp"
const DAY := 10

var _failures := 0
var _holdings: Holdings
var _world_map: WorldMap


func _ready() -> void:
	World.set_process(false)
	var rows: Array[String] = []
	for y in 2 * 20 - 1:
		rows.append(".".repeat(2 * 30 - 1))
	Level.register(ZONE, Level.image_from_rows(rows), null, {"outdoor": true, "name": "the Wilds", "places": {
		"camp": {"at": [9, 9], "kind": "camp", "holder": "goblins", "radius": 1, "worth": 4}}})
	var names: Array[String] = [ZONE]
	_world_map = WorldMap.build(names)
	_holdings = Holdings.new(_world_map, Factions.read(), {})
	_check(_holdings.holder(CAMP) == "goblins", "a goblin camp in the test's zone")
	_test_heard()
	_test_fading()
	_test_lived()
	_test_cleared()
	_test_passed()
	_test_words()
	_test_rules()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _news(kind: String, day := DAY, camp := CAMP, goods := "3 wool") -> Dictionary:
	return {"kind": kind, "day": day, "hour": 9.0, "step": day * 100, "route": "r1", "far": "o/market", "camp": camp,
		"goods": goods, "members": ["a", "b"], "areas": [ZONE, "o/hills"], "text": "news", "told": []}


func _lived(day := DAY, why := "taken", weight := 3) -> Dictionary:
	return {"area": ZONE, "place": "", "why": why, "from": "lived", "day": day, "weight": weight}


func _test_heard() -> void:
	print("\n== the road's news heard ==")
	var card := {}
	var entry := RoadKnowledge.heard(card, _news("raided"), _holdings, {})
	_check(entry.get("area") == ZONE and entry.get("camp") == CAMP and entry.get("why") == "raided" and entry.get("from") == "heard",
		"a wagon struck by the camp is a heard danger of the camp's area (%s)" % [entry])
	_check(entry.get("faction") == "the Blood Rot" and entry.get("goods") == "3 wool" and int(entry.get("day", 0)) == DAY and int(entry.get("weight", 0)) == 2,
		"with the camp's faction word at the time, the goods, the day and heard_weights' raided 2")
	_check(RoadKnowledge.dangers_of(card).size() == 1 and RoadKnowledge.dangers_of(card)[0] == entry, "kept on her card's roads.dangers")
	_check(RoadKnowledge.heard(card, _news("raided"), _holdings, {}).is_empty() and RoadKnowledge.dangers_of(card).size() == 1,
		"the same camp on the same day is no new one")
	_check(not RoadKnowledge.heard(card, _news("raided", DAY + 1), _holdings, {}).is_empty() and RoadKnowledge.dangers_of(card).size() == 2,
		"another day's strike is")
	_check(RoadKnowledge.heard(card, _news("arrived", DAY, ""), _holdings, {}).is_empty(), "a wagon home again adds nothing")
	_check(RoadKnowledge.heard(card, _news("lost", DAY, ""), _holdings, {}).is_empty(), "nor a wagon lost, which names no camp")
	_check(RoadKnowledge.heard(card, _news("raided", DAY, "o/nowhere/camp"), _holdings, {}).is_empty(), "nor a camp Holdings does not know")
	_check(RoadKnowledge.dangers_of(card).size() == 2, "nothing else was added")
	var roads: Dictionary = card["roads"]
	_check(roads.has("areas") and roads.has("places") and roads.has("passed"), "roads made whole in Guide's shape, plus passed")


func _test_fading() -> void:
	print("\n== a heard danger fades over the days ==")
	var card := {}
	RoadKnowledge.heard(card, _news("raided"), _holdings, {})
	var at := RoadKnowledge.weigh(card, [ZONE], DAY, _holdings, {})
	_check(is_equal_approx(at["weight"], 2.0) and at["worst"].get("camp") == CAMP and is_equal_approx(at["worst"].get("standing", 0.0), 2.0),
		"the day it is heard it weighs its whole, 2, and is the worst (%s)" % [at])
	_check(is_equal_approx(RoadKnowledge.weigh(card, [ZONE], DAY + 4, _holdings, {})["weight"], 2.0), "still whole after fresh_days (4)")
	_check(is_equal_approx(RoadKnowledge.weigh(card, [ZONE], DAY + 6, _holdings, {})["weight"], 1.0), "half way down two days later")
	_check(is_equal_approx(RoadKnowledge.weigh(card, ["o/hills"], DAY + 6, _holdings, {})["weight"], 0.0), "nothing on a route not through its area")
	_check(RoadKnowledge.dangers_of(card).size() == 1, "and still on the card")
	var gone := RoadKnowledge.weigh(card, [ZONE], DAY + 8, _holdings, {})
	_check(is_equal_approx(gone["weight"], 0.0) and gone["worst"].is_empty() and RoadKnowledge.dangers_of(card).is_empty(),
		"nothing at twice fresh_days, and pruned from the card")


func _test_lived() -> void:
	print("\n== what she lived through outlasts hearsay ==")
	var card := {"roads": {"areas": [ZONE], "places": [], "dangers": [_lived()]}}
	RoadKnowledge.heard(card, _news("raided"), _holdings, {})
	var at := RoadKnowledge.weigh(card, [ZONE], DAY, _holdings, {})
	_check(is_equal_approx(at["weight"], 5.0) and at["worst"].get("from") == "lived" and at["worst"].get("why") == "taken",
		"heard 2 and lived 3 together weigh 5, the lived one the worst (%s)" % [at])
	_check(is_equal_approx(RoadKnowledge.weigh(card, [ZONE], DAY + 8, _holdings, {})["weight"], 3.0),
		"eight days on the hearsay is gone and the lived danger still whole")
	_check(is_equal_approx(RoadKnowledge.weigh(card, [ZONE], DAY + 12, _holdings, {})["weight"], 1.5), "half way down at twelve")
	_check(is_equal_approx(RoadKnowledge.weigh(card, [ZONE], DAY + 16, _holdings, {})["weight"], 0.0) and RoadKnowledge.dangers_of(card).is_empty(),
		"gone at sixteen")


func _test_cleared() -> void:
	print("\n== a cleared camp lets her go ==")
	var card := {"roads": {"areas": [ZONE], "places": [], "dangers": [_lived()]}}
	RoadKnowledge.heard(card, _news("raided"), _holdings, {})
	_check(is_equal_approx(RoadKnowledge.weigh(card, [ZONE], DAY + 1, _holdings, {})["weight"], 5.0), "camp standing: 5")
	_check(_holdings.take(CAMP, Factions.NOBODY), "the camp falls")
	var at := RoadKnowledge.weigh(card, [ZONE], DAY + 1, _holdings, {})
	_check(is_equal_approx(at["weight"], 3.0) and at["worst"].get("from") == "lived" and RoadKnowledge.dangers_of(card).size() == 1,
		"its heard danger is dropped on sight; what she lived through stays (%s)" % [at])
	_check(RoadKnowledge.heard(card, _news("raided", DAY + 1), _holdings, {}).get("faction") == "",
		"news of a camp nobody holds is heard with no faction word")
	_check(is_equal_approx(RoadKnowledge.weigh(card, [ZONE], DAY + 1, _holdings, {})["weight"], 3.0), "and dropped at the next weighing")
	_check(_holdings.take(CAMP, "goblins"), "the camp retaken for the tests after")


func _test_passed() -> void:
	print("\n== a safe passage halves the area's dangers, once a day ==")
	var card := {"roads": {"areas": [ZONE], "places": [], "dangers": [_lived()]}}
	RoadKnowledge.heard(card, _news("raided"), _holdings, {})
	_check(RoadKnowledge.passed(card, ZONE, DAY), "led through without a stop: halved")
	var weights: Array = RoadKnowledge.dangers_of(card).map(func(d: Dictionary) -> int: return int(d["weight"]))
	_check(weights == [1, 1], "3 and 2 become 1 and 1, whole numbers (%s)" % [weights])
	_check(not RoadKnowledge.passed(card, ZONE, DAY), "not twice in a day")
	_check(not RoadKnowledge.passed(card, "o/hills", DAY), "an area with no dangers: nothing moved")
	_check(RoadKnowledge.passed(card, ZONE, DAY + 1), "the next day again")
	var at := RoadKnowledge.weigh(card, [ZONE], DAY + 1, _holdings, {})
	_check(is_equal_approx(at["weight"], 0.0) and RoadKnowledge.dangers_of(card).is_empty(), "nothing left, and pruned (%s)" % [at])
	_check(int(card["roads"]["passed"].get(ZONE, -1)) == DAY + 1, "roads.passed remembers the day")


func _test_words() -> void:
	print("\n== the clause after \"it isn't safe\" ==")
	var card := {}
	var entry := RoadKnowledge.heard(card, _news("raided"), _holdings, {})
	_check(RoadKnowledge.reason(entry, DAY + 4, _world_map) == "there are bandits on the road through the Wilds: the Blood Rot struck a wagon carrying 3 wool there four days back",
		"heard: the road's area by its name, the faction, the goods, the days (%s)" % RoadKnowledge.reason(entry, DAY + 4, _world_map))
	_check(RoadKnowledge.reason(entry, DAY) == "there are bandits on the road through rk wilds: the Blood Rot struck a wagon carrying 3 wool there today",
		"without the map, the area id's last word; today")
	var bare := RoadKnowledge.heard({}, _news("raided", DAY + 1, CAMP, ""), _holdings, {})
	bare["faction"] = ""
	_check(RoadKnowledge.reason(bare, DAY + 2) == "there are bandits on the road through rk wilds: raiders struck a wagon there yesterday",
		"no goods, no faction word: raiders, yesterday")
	_check(RoadKnowledge.reason(_lived(), DAY + 6) == "I was carried off there, six days back", "lived, first person: carried off")
	_check(RoadKnowledge.reason(_lived(DAY, "downed"), DAY + 12) == "I went down there, 12 days back", "downed; digits past ten")
	_check(RoadKnowledge.reason(_lived(DAY, "fell"), DAY) == "you fell there, today" and RoadKnowledge.reason(_lived(DAY, "hurt"), DAY + 1) == "we were hurt badly there, yesterday",
		"fell and hurt")
	_check(RoadKnowledge.reason({}, DAY) == "", "nothing for nothing")


func _test_rules() -> void:
	print("\n== the rules from companion_traits.json ==")
	var rules: Variant = CompanionCard.tables().get("guide", {})
	_check(rules is Dictionary and rules.get("heard_weights", {}).get("raided") == 2 and rules.get("fresh_days", {}).get("heard") == 4 and rules.get("fresh_days", {}).get("lived") == 8,
		"guide rules carry heard_weights raided 2 and fresh_days heard 4, lived 8")
	var card := {}
	var entry := RoadKnowledge.heard(card, _news("raided"), _holdings, {"heard_weights": {"raided": 5}, "fresh_days": {"heard": 1}})
	_check(int(entry.get("weight", 0)) == 5, "a rule's weight is read")
	_check(is_equal_approx(RoadKnowledge.weigh(card, [ZONE], DAY + 1, _holdings, {"fresh_days": {"heard": 1}})["weight"], 5.0)
		and is_equal_approx(RoadKnowledge.weigh(card, [ZONE], DAY + 2, _holdings, {"fresh_days": {"heard": 1}})["weight"], 0.0),
		"and a rule's fresh_days: whole at one day, gone at two")
	_check(RoadKnowledge.fresh_days({}, "lived") == 8 and RoadKnowledge.fresh_days({}, "heard") == 4, "defaults without rules")


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
