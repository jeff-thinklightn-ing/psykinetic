extends Node
## A player record keeps every key the game writes through a save and a load
## (decision 687): PlayerRecord.from_dict rebuilds the record field by field
## and the companion key by key, and once dropped "left", "focus" and "mood"
## unseen (a companion who left came back after every restart).
## 1. Every key the code writes onto a companion (companion["key"] = ...,
##    found in the source) has a sample here: a new key fails, named, until
##    it is loaded and added.
## 2. A record filled with every sample comes back equal after to_dict, JSON
##    and from_dict: each key dropped or changed fails, named.
## 3. The same for the player's own fields (every script variable).

var _failures := 0

## A companion key -> a value from_dict must give back as it is.
var _companion := {}
## A player field -> a value from_dict must give back as it is.
var _player := {}
## Companion keys written but deliberately not saved: none yet. Each needs
## its reason beside it.
const NOT_SAVED := {}


func _ready() -> void:
	var grown := CompanionFacts.from_record([], [])
	grown.add_fact("Wren keeps a lantern lit at night.", "event", "p")
	_companion = {
		"name": "Wren", "card": "Wren, a woman of the hills.", "hp": 3, "stamina": 4, "tile": [5, 6], "tile_zone": "t", "alive": true,
		"said": ["Over here."], "slots": Array(Items.tidy(["dagger"], Companion.SLOTS)), "items": [7],
		"traits": {"name": "Wren", "birthplace": "the hill farms", "look": {"build": "lean"}, "leanings": {"intellect": 7, "superstition": 4}, "justice": 8},
		"how_we_met": "In the square.", "card_by": "model", "facts": grown.facts, "beliefs": grown.beliefs, "talk": ["What was that?"],
		"resident": {"place": "t/store", "zone": "t", "trade": "smith"}, "taken": {"by": "raid-1", "zone": "z", "at": 5},
		"home": {"place": "t/store", "zone": "t", "trade": "smith"},
		"heard": [{"id": "h1", "text": "The mine is cursed", "from": "Tam", "step": 1, "fits": "beyond", "believed": true}],
		"standing": {"p": {"score": -7, "met": 1, "since": 2, "why": ["let you bleed out"], "own": true}},
		"bond_day": 3, "bond_best": 2, "bond_carry": 0.5, "games": {"hers": 1, "theirs": 2},
		"needs": {"leisure": 0.6, "faith": 0.3}, "need_weights": {"wonder": 1.3}, "needs_day": 4, "needs_today": {"day": 4, "deeds": ["fire"]},
		"want": {"key": "town", "need": "company", "since": 4}, "wants_met": {"fire": 3}, "want_rest": 5,
		"bond_said": {"day": 1, "hurt": 1, "sorry": 0}, "bond_today": {"day": 1, "deeds": ["gift"]}, "marks": ["draugr"],
		"sick": {"since": 1, "kind": "a cough", "cured_by": "", "treated": -1}, "was_sick": {"since": 1, "ended": 3, "cured_by": "rest"},
		"roads": {"areas": ["a"], "places": ["p"], "dangers": [{"area": "a", "day": 2, "why": "raided"}], "passed": {"a": 3}},
		"focus": {"fight": 50.5, "magic": 24.75, "stealth": 24.75}, "focus_day": {"day": 4, "grown": 1.5},
		"mood": "apart", "warned_area": "rs_road",
		"left": {"day": 2, "deed": "let_bleed", "why": "let you bleed out", "place": "t/store", "repaired": false, "area": "",
			"grave": [12, 40], "words": ["You left them.", "In time."], "favour_today": {"day": 3, "kinds": ["gift"]}, "checked": 3,
			"visit": {"from": 900}},
		"leaving": {"deed": "harsh", "why": "shouted at you", "day": 2},
		"parted": {"day": 5, "place": "t/store"},
		"from_worker": "w-bram",
	}
	_player = {
		"player_id": "p", "index": 2, "name": "Jeff", "body": &"female", "look": "", "tile": Vector2i(3, 4), "hp": 9, "stamina": 8,
		"facing": Vector2i(1, 0), "color": Color.html("336699"), "zone": "wilds", "last_seen": 1234,
		"companion": _companion, "commissions": [{"id": "c1", "town": "t/store"}],
		"slots": Items.tidy(["dagger"], Player.SLOTS), "slot_items": PackedInt32Array([5]),
		"known_areas": ["a", "b"] as Array[String], "known_places": ["p"] as Array[String], "seen_generation": {"barrow": 2},
		"marks": ["draugr"] as Array[String], "barrow": {"best": "hard", "containers": ["c1"]}, "care": {"hut": "gold"},
		"paid_deals": {"barrow": {"level": "easy", "paid_step": 40}}, "barrow_task": {"taken": true, "slain": ["brand", "crake"]}, "care_given": {"hut": {"herbs": 2}},
		"caches": ["k1"] as Array[String], "explored_places": ["wilds/far_bank"] as Array[String],
		"arts": {"swordplay": {"m": 0.42, "peak": 0.5, "quiet": 1200}, "bow": {"m": 0.1, "peak": 0.1, "quiet": 0}},
		"locker_slots": Items.tidy(["bandaging_kit"], Locker.LOCKER_SLOTS), "locker_items": PackedInt32Array([6]),
		"former": [{"companion": {"name": "Nix", "card": "", "hp": 0, "stamina": 0, "tile": null, "alive": true, "said": [],
			"slots": Array(Items.tidy([], Companion.SLOTS)), "items": [], "parted": {"day": 2, "place": "t/store"},
			"standing": {"p": {"score": 2, "met": 1, "since": 2, "why": ["travelled with you"], "own": true}}}, "worker": "settled:Nix"}],
	}
	_test_written_keys_have_samples()
	_test_companion_round_trip()
	_test_player_round_trip()
	_test_solo_round_trip()
	_test_arts_before_766()
	_test_arts_flag()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_written_keys_have_samples() -> void:
	print("\n== every key the code writes onto a companion is checked through a save (decision 687) ==")
	var written := {}
	var assign := RegEx.create_from_string("companion\\[\"(\\w+)\"\\]\\s*=[^=]")
	var files: Array[String] = ["res://main.gd"]
	for folder: String in ["res://sim", "res://net"]:
		for file: String in DirAccess.get_files_at(folder):
			if file.ends_with(".gd"):
				files.append("%s/%s" % [folder, file])
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		for found in assign.search_all(text):
			written[found.get_string(1)] = path
	var missing: Array[String] = []
	for key: String in written:
		if not _companion.has(key) and not NOT_SAVED.has(key):
			missing.append("%s (%s)" % [key, written[key]])
	_check(written.size() >= 20, "(the source scanned: %d companion keys written)" % written.size())
	_check(missing.is_empty(), "each written key has a sample here; load it in PlayerRecord.from_dict and add it: %s" % [missing])


func _test_companion_round_trip() -> void:
	print("\n== a companion with every key comes back the same (decision 687) ==")
	var record := PlayerRecord.new()
	record.player_id = "p"
	record.companion = _companion.duplicate(true)
	var back := PlayerRecord.from_dict(JSON.parse_string(JSON.stringify(record.to_dict())))
	_check(back != null, "(loaded)")
	if back == null:
		return
	var lost: Array[String] = []
	for key: String in _companion:
		if not back.companion.has(key):
			lost.append("%s dropped" % key)
		elif not _same(back.companion[key], _companion[key]):
			lost.append("%s changed: %s, saved %s" % [key, back.companion[key], _companion[key]])
	_check(lost.is_empty(), "every companion key kept as saved: %s" % [lost])


func _test_player_round_trip() -> void:
	print("\n== a player's own fields come back the same (decision 687) ==")
	var record := PlayerRecord.new()
	var unsampled: Array[String] = []
	for property: Dictionary in record.get_property_list():
		if not property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			continue
		var field := str(property["name"])
		if not _player.has(field):
			unsampled.append(field)
			continue
		record.set(field, _player[field].duplicate(true) if _player[field] is Dictionary or _player[field] is Array else _player[field])
	_check(unsampled.is_empty(), "each field of a player's record has a sample here; save and load it, and add it: %s" % [unsampled])
	var back := PlayerRecord.from_dict(JSON.parse_string(JSON.stringify(record.to_dict())))
	_check(back != null, "(loaded)")
	if back == null:
		return
	var lost: Array[String] = []
	for field: String in _player:
		if not _same(back.get(field), _player[field]):
			lost.append("%s: %s, saved %s" % [field, back.get(field), _player[field]])
	_check(lost.is_empty(), "every field kept as saved: %s" % [lost])


## A record saved before weapon memory (766) has no "arts": it loads as a
## fresh player's, and nonsense in it is dropped.
func _test_arts_before_766() -> void:
	print("\n== a record from before weapon memory loads with fresh arts (766) ==")
	var old := PlayerRecord.from_dict({"player_id": "p", "tile": [1, 2]})
	_check(old != null and old.arts.is_empty(), "no arts saved: none (%s)" % [old.arts if old != null else null])
	var odd := PlayerRecord.from_dict({"player_id": "p", "tile": [1, 2], "arts": {"swordplay": {"m": 4.0}, "juggling": {"m": 0.5}, "bow": 3}})
	_check(odd != null and odd.arts.keys() == ["swordplay"] and float(odd.arts["swordplay"]["m"]) == 1.0,
			"an art not known, or not a dictionary, dropped; a memory past 1 held at 1 (%s)" % [odd.arts if odd != null else null])


## --test-arts is read from the command line (766, combat's side (2):
## playtest's server ignored it, missing from the options that take a value).
func _test_arts_flag() -> void:
	print("
== --test-arts is read, either form (766, combat's side (2)) ==")
	var kept := Net.test_arts.duplicate()
	Net._parse_args(["--test-arts=swordplay:1,bow:0.5"])
	_check(Net.test_arts == {"swordplay": 1.0, "bow": 0.5}, "--test-arts=swordplay:1,bow:0.5 (%s)" % [Net.test_arts])
	Net._parse_args(["--test-arts", "bow:2"])
	_check(Net.test_arts == {"bow": 1.0}, "--test-arts bow:2, held at 1 (%s)" % [Net.test_arts])
	Net.test_arts = kept


func _test_solo_round_trip() -> void:
	print("
== nobody with them by their choice stays so through a save (686) ==")
	var record := PlayerRecord.new()
	record.player_id = "p"
	record.companion = {"solo": true}
	var back := PlayerRecord.from_dict(JSON.parse_string(JSON.stringify(record.to_dict())))
	_check(back != null and back.companion == {"solo": true}, "solo kept, not given one again (%s)" % [back.companion if back != null else null])


## Whether [param a] and [param b] hold the same: numbers by value (JSON
## gives back floats), tables and lists all the way down.
func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for key: Variant in b:
			if not a.has(key) or not _same(a[key], b[key]):
				return false
		return true
	if (a is Array or a is PackedInt32Array) and (b is Array or b is PackedInt32Array):
		if a.size() != b.size():
			return false
		for i in b.size():
			if not _same(a[i], b[i]):
				return false
		return true
	if (a is String or a is StringName) and (b is String or b is StringName):
		return str(a) == str(b)
	return typeof(a) == typeof(b) and a == b


func _check(ok: bool, label: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1
