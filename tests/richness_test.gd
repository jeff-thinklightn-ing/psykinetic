extends Node
## Game's richness (decision 368), on two outdoor strips joined east to
## west with a mine at the west end of the first, a goblin camp and the
## town's store on them, a building's roof, an indoor level and a dead one:
## nothing in the sky's absence, on dead ground or on a faction's held
## ground; the town's and open ground full, thinned by the walking steps
## from the mine, across the edge into the next area too; no mine, no
## thinning. Also WorldMap.is_dead and Holdings.camps. Run it with
## tests/run.ps1 or tests/run.sh.

const RULES := {"mine_dead": 10.0, "mine_full": 50.0}

var _failures := 0


func _ready() -> void:
	World.set_process(false)
	var rows: Array[String] = []
	for y in 2 * 5 - 1:
		rows.append(".".repeat(2 * 60 - 1))
	var strip := Level.image_from_rows(rows)
	Level.register("rc_near", strip, null, {"outdoor": true, "neighbours": {"east": "rc_far"},
		"places": {"mine": {"at": [2, 2], "kind": "mine", "holder": "nobody"},
			"store": {"at": [30, 2], "kind": "stockpile", "holder": "town", "radius": 3}}})
	Level.register("rc_far", strip, null, {"outdoor": true, "neighbours": {"west": "rc_near"},
		"places": {"camp": {"at": [40, 2], "kind": "camp", "holder": "goblins", "worth": 5, "radius": 3}}})
	Level.register("rc_cave", strip, null, {})
	Level.register("rc_dead", strip, null, {"outdoor": true, "dead_ground": true})
	var names: Array[String] = ["rc_near", "rc_far", "rc_cave", "rc_dead"]
	var map := WorldMap.build(names)
	var holdings := Holdings.new(map, Factions.read(), {})
	# A building's roof over a corner of the far strip (as a level's buildings
	# read: only the rect matters here).
	map.areas["rc_far"]["buildings"] = [{"rect": Rect2i(50, 0, 3, 2)}]
	var rich := WorldRichness.new(map, holdings, RULES)
	rich.start()

	print("== nothing lives out of the sky, on dead ground, or on held ground ==")
	_check(map.is_dead("rc_dead") and not map.is_dead("rc_near"), "WorldMap.is_dead: the level that says so")
	_check(rich.richness("rc_dead", Vector2i(30, 2)) == 0.0, "dead ground: 0")
	_check(rich.richness("rc_cave", Vector2i(30, 2)) == 0.0, "an indoor level: 0")
	_check(rich.richness("rc_far", Vector2i(51, 1)) == 0.0 and rich.richness("rc_far", Vector2i(51, 3)) > 0.0,
			"under a roof: 0, beside it not")
	_check(rich.richness("rc_far", Vector2i(40, 2)) == 0.0 and rich.richness("rc_far", Vector2i(42, 4)) == 0.0,
			"the goblins' camp's ground: 0")
	var camps := holdings.camps("goblins")
	_check(camps.size() == 1 and camps[0]["id"] == "rc_far/camp" and camps[0]["area"] == "rc_far" and holdings.camps("town").is_empty(),
			"Holdings.camps(faction): the goblins' one (%s)" % [camps])

	print("== thinning toward the mine ==")
	_check(is_equal_approx(rich.steps_from_mine("rc_near", Vector2i(12, 2)), 10.0), "steps from the mine walked: 10 at (12, 2)")
	_check(rich.richness("rc_near", Vector2i(2, 2)) == 0.0 and rich.richness("rc_near", Vector2i(12, 2)) == 0.0,
			"nothing within mine_dead (10 steps)")
	var halfway := rich.richness("rc_near", Vector2i(32, 2))
	_check(is_equal_approx(halfway, 0.5), "half at 30 steps, halfway to mine_full: %.2f" % halfway)
	_check(is_equal_approx(rich.richness("rc_near", Vector2i(30, 2)), 0.45), "the town's ground keeps its game, thinned the same (28 steps): %.2f" % rich.richness("rc_near", Vector2i(30, 2)))
	var across := rich.steps_from_mine("rc_far", Vector2i(0, 2))
	_check(across > 57.0 and across < 60.0 and rich.richness("rc_far", Vector2i(0, 2)) == 1.0,
			"across the edge the steps go on (%.1f): full" % across)

	print("== no mine ==")
	var none := WorldRichness.new(WorldMap.build(["rc_far"] as Array[String]), Holdings.new(WorldMap.build(["rc_far"] as Array[String]), Factions.read(), {}), RULES)
	_check(none.mines.is_empty() and none.richness("rc_far", Vector2i(5, 2)) == 1.0, "nothing thins")
	rich.finish()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
