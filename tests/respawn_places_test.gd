extends Node
## Where the fallen come back (decision 372): a placed temple and healer's
## hut make places of their kinds on the cell outside the middle of their
## front, held by nobody (the temple's ground the town's by the stockpile's
## radius, the hut's nobody's); a level with neither has none; moving the
## building moves its place; Holdings.nearest finds the nearest by walking
## steps, across an edge too, or in the same area without routes. Run it
## with tests/run.ps1 or tests/run.sh.

var _failures := 0


func _ready() -> void:
	World.set_process(false)
	var rows: Array[String] = []
	for y in 2 * 20 - 1:
		rows.append(".".repeat(2 * 40 - 1))
	var ground := Level.image_from_rows(rows)
	Level.register("rp_town", ground, null, {"outdoor": true, "neighbours": {"east": "rp_wild"},
		"buildings": [{"slot": "building.temple", "at": [10, 5], "facing": [0, 1]}],
		"places": {"store": {"at": [12, 14], "kind": "stockpile", "holder": "town", "radius": 8}}})
	Level.register("rp_wild", ground, null, {"outdoor": true, "neighbours": {"west": "rp_town"},
		"buildings": [{"slot": "building.healers_hut", "at": [30, 10], "facing": [0, -1]}]})
	Level.register("rp_plain", ground, null, {"outdoor": true})

	print("== a placed temple and healer's hut make places ==")
	var town := Level.load_level("rp_town")
	var temple: Dictionary = town["places"].get("temple@11,11", {})
	_check(temple.get("kind") == "temple" and temple.get("cell") == Vector2i(11, 11) and temple.get("holder") == "nobody",
			"the temple (4 x 6 at 10, 5, facing south): a temple place outside its front's middle, 11, 11 (%s)" % [town["places"].keys()])
	var wild := Level.load_level("rp_wild")
	var hut: Dictionary = wild["places"].get("healers_hut@31,9", {})
	_check(hut.get("kind") == "healers_hut" and hut.get("cell") == Vector2i(31, 9), "the healer's hut (facing north): at 31, 9 (%s)" % [wild["places"].keys()])
	var plain := Level.load_level("rp_plain")
	_check((plain["places"] as Dictionary).is_empty() and (plain["warnings"] as Array).filter(func(w: String) -> bool: return "place" in w).is_empty(),
			"a level with neither: no places, no warnings about them")
	Level.register("rp_moved", ground, null, {"outdoor": true, "buildings": [{"slot": "building.temple", "at": [20, 2], "facing": [1, 0]}]})
	var moved: Dictionary = Level.load_level("rp_moved")["places"]
	_check(moved.keys() == ["temple@26,3"], "a temple moved (and turned east) has its place moved with it, outside its east side (6 x 4 turned: %s)" % [moved.keys()])

	print("== held ground ==")
	var names: Array[String] = ["rp_town", "rp_wild"]
	var map := WorldMap.build(names)
	var holdings := Holdings.new(map, Factions.read(), {})
	_check(holdings.ground("rp_town", Vector2i(11, 11)) == "town", "the temple stands on the town's ground (the stockpile's radius)")
	_check(holdings.ground("rp_wild", Vector2i(31, 9)) == Factions.NOBODY and holdings.holder("rp_wild/healers_hut@31,9") == Factions.NOBODY,
			"the hut is nobody's, and holds no ground")

	print("== the nearest, by walking ==")
	var kinds: Array[String] = ["temple", "healers_hut"]
	var routes := map.routes()
	routes.wait()
	_check(holdings.nearest(kinds, "rp_town", Vector2i(3, 3), routes) == "rp_town/temple@11,11", "in town: the temple")
	_check(holdings.nearest(kinds, "rp_wild", Vector2i(36, 15), routes) == "rp_wild/healers_hut@31,9", "out in the wilds: the hut")
	var temples: Array[String] = ["temple"]
	_check(holdings.nearest(temples, "rp_wild", Vector2i(36, 15), routes) == "rp_town/temple@11,11", "only temples asked: the town's, across the edge")
	_check(holdings.nearest(temples, "rp_wild", Vector2i(36, 15)) == "", "without routes, only the same area: none")
	_check(holdings.nearest(kinds, "rp_wild", Vector2i(36, 15)) == "rp_wild/healers_hut@31,9", "and the hut there")
	var order := holdings.ranked(kinds, "rp_wild", Vector2i(36, 15), routes)
	_check(order == _strings(["rp_wild/healers_hut@31,9", "rp_town/temple@11,11"]),
		"ranked: every one that can be walked to, nearest first, for the first manned (decision 503; %s)" % [order])
	routes = null
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _strings(values: Array) -> Array[String]:
	var out: Array[String] = []
	out.assign(values)
	return out


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
