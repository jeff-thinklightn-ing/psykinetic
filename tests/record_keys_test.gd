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
		"name": "Wren", "card": "Wren, a woman of the hills.", "hp": 3, "stamina": 4, "tile": [5, 6], "alive": true,
		"said": ["Over here."], "slots": Array(Items.tidy(["dagger"], Companion.SLOTS)), "items": [7],
		"traits": {"name": "Wren", "birthplace": "the hill farms", "look": {"build": "lean"}, "leanings": {"intellect": 7, "superstition": 4}, "justice": 8},
		"how_we_met": "In the square.", "card_by": "model", "facts": grown.facts, "beliefs": grown.beliefs, "talk": ["What was that?"],
		"resident": {"place": "t/store", "zone": "t", "trade": "smith"}, "taken": {"by": "raid-1", "zone": "z", "at": 5},
		"home": {"place": "t/store", "zone": "t", "trade": "smith"},
		"heard": [{"id": "h1", "text": "The mine is cursed", "from": "Tam", "step": 1, "fits": "beyond", "believed": true}],
		"standing": {"p": {"score": -7, "met": 1, "since": 2, "why": ["let you bleed out"], "own": true}},
		"bond_day": 3, "bond_best": 2, "bond_carry": 0.5, "games": {"hers": 1, "theirs": 2},
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
	}
	_player = {
		"player_id": "p", "index": 2, "name": "Jeff", "body": &"female", "look": "", "tile": Vector2i(3, 4), "hp": 9, "stamina": 8,
		"facing": Vector2i(1, 0), "color": Color.html("336699"), "zone": "wilds", "last_seen": 1234,
		"companion": _companion, "commissions": [{"id": "c1", "town": "t/store"}],
		"slots": Items.tidy(["dagger"], Player.SLOTS), "slot_items": PackedInt32Array([5]),
		"known_areas": ["a", "b"] as Array[String], "known_places": ["p"] as Array[String], "seen_generation": {"barrow": 2},
		"marks": ["draugr"] as Array[String], "barrow": {"best": "hard", "containers": ["c1"]}, "care": {"hut": "gold"},
		"paid_deals": {"barrow": {"level": "easy", "paid_step": 40}}, "care_given": {"hut": {"herbs": 2}},
		"caches": ["k1"] as Array[String],
	}
	_test_written_keys_have_samples()
	_test_companion_round_trip()
	_test_player_round_trip()
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
