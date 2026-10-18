extends Node
## The Blood Rot and its allies (decision 416): levels/factions.json's
## goblins (shown as the Blood Rot, its lore entry blood_rot), with the orcs
## (brutes) and kobolds (sneaks) allied to it; an ally is on its lead's side
## and takes on its enemies; a bad allied_to is dropped with a warning; held
## ground: an ally's does not block, and two allies' is not contested but
## the lead's; a Blood Rot raid draws on its allies' kinds, an ally's on its
## own; monsters of allied kinds are one side. Run it with tests/run.ps1 or
## tests/run.sh.

var _failures := 0


func _ready() -> void:
	World.set_process(false)
	var factions := Factions.read()
	print("== levels/factions.json ==")
	_check(factions.display_name("goblins") == "the Blood Rot" and factions.lore_id("goblins") == "blood_rot",
		"the goblins are the Blood Rot, lore's blood_rot")
	_check(factions.of_kind("imp") == "goblins" and factions.of_kind("brute") == "orcs" and factions.of_kind("sneak") == "kobolds",
		"imps are goblins, brutes orcs, sneaks kobolds")
	_check(factions.allies_of("goblins") == _strings(["kobolds", "orcs"]) and factions.allies_of("orcs").is_empty(),
		"the orcs and kobolds are the Blood Rot's allies; an ally has none")
	_check(factions.lore_id("orcs") == "goblins" and factions.lore_id("town") == "town", "lore ids: the allies' facts are in goblins; the town its own")

	print("== sides ==")
	_check(factions.side("orcs") == "goblins" and factions.side("goblins") == "goblins" and factions.side("town") == "town", "each ally's side is the Blood Rot's")
	_check(factions.same_side("orcs", "kobolds") and factions.same_side("orcs", "goblins") and not factions.same_side("orcs", "town"),
		"allies are one side, not the town's")
	_check(factions.hostile("orcs", "town") and factions.hostile("town", "kobolds") and factions.hostile("goblins", "town"),
		"an ally takes on its lead's enemy, the town")
	_check(not factions.hostile("orcs", "goblins") and not factions.hostile("nobody", "orcs"), "never one side, nor nobody")
	_check(factions.same_side(Factions.NOBODY, Factions.NOBODY) and not factions.same_side(Factions.NOBODY, "orcs"),
		"nobody is its own, no faction's")

	var folder: String = preload("res://tests/test_ports.gd").scratch("factions_test/")
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder + "bad.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"a": {"allied_to": "b"}, "b": {"allied_to": "a"}, "c": {"allied_to": "nowhere"}}))
	file.close()
	var bad := Factions.read(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check(bad.side("c") == "c" and bad.side("a") == "a" and bad.side("b") == "a",
		"an allied_to naming no faction, or one that is an ally itself, is dropped: no chains (a %s, b %s, c %s)" % [bad.side("a"), bad.side("b"), bad.side("c")])

	print("== held ground ==")
	var rows: Array[String] = []
	for y in 2 * 10 - 1:
		rows.append(".".repeat(2 * 30 - 1))
	Level.register("fa_land", Level.image_from_rows(rows), null, {"outdoor": true, "places": {
		"den": {"at": [5, 5], "kind": "camp", "holder": "goblins", "radius": 3},
		"pit": {"at": [8, 5], "kind": "camp", "holder": "orcs", "radius": 3},
		"farm": {"at": [20, 5], "kind": "stockpile", "holder": "town", "radius": 3}}})
	var names: Array[String] = ["fa_land"]
	var holdings := Holdings.new(WorldMap.build(names), factions, {})
	_check(holdings.ground("fa_land", Vector2i(7, 5)) == "goblins", "the Blood Rot's ground and the orcs' together read as the Blood Rot's, not contested")
	_check(holdings.ground("fa_land", Vector2i(10, 5)) == "orcs", "the orcs' alone is theirs")
	var blocked := holdings.blocked_cells("fa_land", "kobolds")
	_check(not blocked.has(Vector2i(5, 5)) and not blocked.has(Vector2i(8, 5)) and blocked.has(Vector2i(20, 5)),
		"a kobold walks the Blood Rot's and the orcs' ground, not the town's")
	_check(holdings.blocked_cells("fa_land", "town").has(Vector2i(8, 5)), "the town does not walk the orcs'")

	print("== raids and monsters ==")
	_check(Raids._kinds_of("goblins") == _strings(["brute", "imp", "sneak"]), "a Blood Rot raid draws on imps, brutes and sneaks, as before (%s)" % [Raids._kinds_of("goblins")])
	_check(Raids._kinds_of("orcs") == _strings(["brute"]), "an orc raid on brutes only")
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
