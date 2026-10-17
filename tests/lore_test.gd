extends Node
## Lore: every file under levels/lore/ follows docs/lore/README.md (decisions
## 257, 258): entries and facts have unique ids, a known type, status and
## knowledge level; an asked one names its question; relations, where and
## knowers name ids that exist; a rumour says whether it is true; ids shared
## with other files (factions, resources, place kinds, items, levels) are
## theirs, and every region has a climate.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const DIR := "res://levels/lore/"
const FILES := ["world", "factions", "regions", "materials", "creatures", "people", "history"]
const TYPES := ["world", "faction", "people", "region", "place", "material", "creature", "person", "weapon", "event"]
const STATUSES := ["agreed", "draft", "asked"]
const KNOWN := ["common", "rumour", "secret", "lived"]
const RELATIONS := ["in", "holds", "enemy", "feud", "ally", "from", "member", "carries", "took", "held_at"]

var _failures := 0
var _entries := {}
var _knowers := {}


func _ready() -> void:
	_test_read()
	_test_entries()
	_test_facts()
	_test_shared_ids()
	_test_known_by_files()
	_test_known_by()
	_test_names_file()
	_test_names()
	_test_roles_file()
	_test_roles()
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _read(file: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(DIR + file + ".json"))


func _test_read() -> void:
	print("\n== every lore file reads, ids unique across them ==")
	var dupes: Array = []
	for file in FILES:
		var data: Variant = _read(file)
		_check(data is Dictionary and data.get("entries") is Array, "%s.json is {entries: [...]}" % file)
		if not data is Dictionary:
			continue
		for entry in data.get("entries", []):
			if _entries.has(entry.get("id")):
				dupes.append(entry.get("id"))
			_entries[entry.get("id")] = entry
	_check(dupes.is_empty(), "entry ids are unique across the files %s" % [dupes])
	var known: Variant = _read("knowers")
	_check(known is Dictionary and known.get("knowers") is Array, "knowers.json is {knowers: [...]}")
	for knower in known.get("knowers", []) if known is Dictionary else []:
		_knowers[knower.get("id")] = knower


func _test_entries() -> void:
	print("\n== an entry has an id, a known type and status, a source and a summary ==")
	var bad: Array = []
	for id in _entries:
		var entry: Dictionary = _entries[id]
		var ok: bool = id is String and _is_id(id) and entry.get("type") in TYPES and _status_ok(entry) \
				and entry.get("name") is String and entry.get("source") is String \
				and entry.get("summary") is String and entry.get("facts") is Array
		for relation in entry.get("relations", []):
			ok = ok and relation.get("kind") in RELATIONS and _entries.has(relation.get("to"))
		if not ok:
			bad.append(id)
	_check(bad.is_empty(), "every entry is well formed, its relations to known entries %s" % [bad])
	bad = []
	for id in _entries:
		if _personal(str(_entries[id].get("summary", ""))):
			bad.append(id)
	_check(bad.is_empty(), "every summary is in the third person %s" % [bad])
	bad = []
	for id in _knowers:
		var knower: Dictionary = _knowers[id]
		if not (_is_id(id) and _status_ok(knower) and _regions_ok(knower.get("where")) and knower.get("tags") is Array):
			bad.append(id)
	_check(bad.is_empty(), "every knower is well formed, its where regions %s" % [bad])


func _test_facts() -> void:
	print("\n== a fact belongs to its entry, says who knows it, and states no line ==")
	var bad: Array = []
	var ids := {}
	for id in _entries:
		for fact in _entries[id]["facts"]:
			var fid: Variant = fact.get("id")
			var ok: bool = fid is String and fid.begins_with(id + ".") and not ids.has(fid) \
					and fact.get("text") is String and fact.get("known") in KNOWN \
					and _regions_ok(fact.get("where")) and _status_ok(fact, false) \
					and (not fact.has("source") or fact["source"] is String)
			ids[fid] = true
			var known: Variant = fact.get("known")
			if known == "rumour":
				ok = ok and fact.get("true") is bool
			if known == "secret" or known == "lived":
				ok = ok and fact.get("knowers") is Array and not fact["knowers"].is_empty()
			for knower in fact.get("knowers", []):
				ok = ok and _knowers.has(knower)
			# A line to say would be quoted speech, or spoken in the first or second person.
			ok = ok and not String(fact.get("text", "")).contains("\"") and not _personal(String(fact.get("text", ""))) \
					and (not fact.has("weight") or (fact["weight"] is float and fact["weight"] > 0.0))
			if not ok:
				bad.append(fid)
	_check(bad.is_empty(), "every fact is well formed %s" % [bad])
	_check(not ids.is_empty(), "there are facts (%d)" % ids.size())


func _test_shared_ids() -> void:
	print("\n== ids shared with other files are theirs ==")
	var factions: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://levels/factions.json"))
	var bad: Array = []
	for id in _entries:
		var entry: Dictionary = _entries[id]
		match entry["type"]:
			"faction":
				# A new faction waits for maps to add its key before it can be agreed.
				if entry["status"] == "agreed" and not factions.has(id):
					bad.append(id)
			"material":
				if entry.has("resource") and not entry["resource"] in Stockpile.RESOURCES:
					bad.append(id)
			"place":
				if entry.has("place_kind") and not entry["place_kind"] in Level.PLACE_KINDS:
					bad.append(id)
				if entry.has("level") and not Level.exists(entry["level"]):
					bad.append(id)
			"weapon":
				if entry.has("item") and not Items.exists(entry["item"]):
					bad.append(id)
	_check(bad.is_empty(), "factions, resources, place kinds, levels and items named exist %s" % [bad])
	# Environment owns levels/climates.json (keyed by region id); an asked region needs none yet.
	var climates: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://levels/climates.json"))
	bad = []
	for id in _entries:
		if _entries[id]["type"] == "region" and _entries[id]["status"] != "asked" \
				and not (climates is Dictionary and climates.has(id)):
			bad.append(id)
	_check(bad.is_empty(), "every region has a climate in levels/climates.json %s" % [bad])


func _test_known_by_files() -> void:
	print("\n== Lore.known_by on the files: only agreed counts, never an asked one, truth kept back ==")
	Lore.reload()
	_check(Lore.entries().size() == _entries.size() and Lore.knowers().size() == _knowers.size(),
			"Lore reads every entry and knower (%d, %d)" % [Lore.entries().size(), Lore.knowers().size()])
	var agreed := 0
	for id in _entries:
		agreed += 1 if _entries[id]["status"] == "agreed" else 0
	if agreed == 0:
		_check(Lore.known_by("townsfolk").is_empty(), "with nothing agreed, townsfolk know nothing yet")
	var drafts := Lore.known_by("townsfolk", PackedStringArray(), "draft")
	_check(not drafts.is_empty(), "previewing drafts, townsfolk know %d facts" % drafts.size())
	var asked := []
	for fact in drafts:
		if fact.has("true") or fact.has("known"):
			asked.append(fact["id"])
		for id in _entries:
			for each in _entries[id]["facts"]:
				if each["id"] == fact["id"] and (each.get("status", _entries[id]["status"]) == "asked" or _entries[id]["status"] == "asked"):
					asked.append(fact["id"])
	_check(asked.is_empty(), "no asked fact is known, and no fact says whether it is true %s" % [asked])


func _test_known_by() -> void:
	print("\n== Lore.known_by: where, tags, hearsay, secrets, memory, the status gate ==")
	var entries := [
		{"id": "near", "type": "region", "status": "agreed", "facts": []},
		{"id": "far", "type": "region", "status": "agreed", "facts": []},
		{"id": "a", "status": "agreed", "facts": [
			{"id": "a.here", "text": "here", "known": "common", "where": ["near"]},
			{"id": "a.there", "text": "there", "known": "common", "where": ["far"]},
			{"id": "a.all", "text": "all", "known": "common", "where": []},
			{"id": "a.old", "text": "old", "known": "common", "where": ["far"], "tags": ["history"]},
			{"id": "a.said", "text": "said", "known": "rumour", "where": ["near"], "true": false},
			{"id": "a.hid", "text": "hid", "known": "secret", "where": [], "knowers": ["sage"]},
			{"id": "a.mine", "text": "mine", "known": "lived", "where": [], "knowers": ["wren"]},
			{"id": "a.draft", "text": "draft", "known": "common", "where": [], "status": "draft"},
			{"id": "a.asked", "text": "asked", "known": "common", "where": [], "status": "asked", "ask": "X"},
		]},
		{"id": "b", "status": "draft", "facts": [
			{"id": "b.over", "text": "over", "known": "common", "where": [], "status": "agreed"},
		]},
	]
	var knowers := [
		{"id": "folk", "status": "agreed", "where": ["near"], "tags": []},
		{"id": "sage", "status": "agreed", "where": [], "tags": ["history"]},
		{"id": "wren", "status": "agreed", "where": ["near"], "tags": []},
		{"id": "maybe", "status": "draft", "where": ["near"], "tags": []},
	]
	Lore.use(entries, knowers)
	var ids := func(knower: String, least := "agreed") -> Array:
		return Lore.known_by(knower, PackedStringArray(), least).map(func(fact: Dictionary) -> String: return fact["id"])
	_check(ids.call("folk") == ["a.here", "a.all", "a.said"], "folk know their own region's facts and rumours and what everyone knows, not another region's %s" % [ids.call("folk")])
	_check(ids.call("sage") == ["a.all", "a.old", "a.hid"], "a sage knows what shares its tag wherever it is, and the secret it is named in %s" % [ids.call("sage")])
	_check("a.mine" in ids.call("wren") and not "a.mine" in ids.call("folk"), "a lived fact is known to the one who lived it only")
	var said: Dictionary = Lore.known_by("folk").filter(func(fact: Dictionary) -> bool: return fact["id"] == "a.said")[0]
	var mine: Dictionary = Lore.known_by("wren").filter(func(fact: Dictionary) -> bool: return fact["id"] == "a.mine")[0]
	_check(said["hearsay"] and not said.has("true") and mine["memory"] and not said["memory"], "a rumour comes as hearsay, its truth kept back; a lived fact as memory")
	_check(not "a.draft" in ids.call("folk") and "a.draft" in ids.call("folk", "draft"), "a draft fact counts only when drafts are previewed")
	_check(not "a.asked" in ids.call("folk", "draft"), "an asked fact never counts")
	_check(not "b.over" in ids.call("folk"), "an agreed fact in a draft entry does not count")
	_check(ids.call("maybe").is_empty() and not ids.call("maybe", "draft").is_empty(), "a draft knower knows nothing until previewed")
	_check(ids.call("nobody").is_empty(), "an unknown knower knows nothing")
	_check(said["where"] == ["near"] and said["weight"] == Lore.DEFAULT_WEIGHT, "a fact comes with its where and, giving none, the default weight")
	var about := func(topics: Array) -> Array:
		return Lore.known_by("sage", PackedStringArray(topics)).map(func(fact: Dictionary) -> String: return fact["id"])
	_check(about.call(["history"]) == ["a.old"], "about a tag: the facts with that tag %s" % [about.call(["history"])])
	_check(about.call(["HID"]) == ["a.hid"] and about.call(["alls"]) == [] and about.call(["al"]) == [], "about a word: whole words of the text, any case %s" % [about.call(["HID"])])
	_check(about.call(["a"]).size() == 3, "about an entry's id: all its facts known")
	_check(about.call(["history", "hid"]) == ["a.old", "a.hid"], "about several topics: a fact on any of them")
	_check(about.call([]).size() == 3, "about nothing: everything known")
	Lore.reload()
	var ore := Lore.known_by("learned", PackedStringArray(["ore"]), "draft").map(func(fact: Dictionary) -> String: return fact["id"])
	_check("blighted_ore.carries" in ore and not "the_land.fire" in ore, "on the files, about the ore: the ore's facts, not the fire's %s" % [ore])
	var weighted: Array = Lore.known_by("learned", PackedStringArray(), "draft").filter(func(fact: Dictionary) -> bool: return fact["weight"] != Lore.DEFAULT_WEIGHT)
	_check(weighted.is_empty(), "no fact is weighted until Jeff weighs them")


func _test_names_file() -> void:
	print("\n== names.json: forms filled only from known slots, thing words, the status gate (decision 366) ==")
	var data: Variant = _read("names")
	_check(data is Dictionary and data.get("forms") is Array and data.get("things") is Array, "names.json is {forms: [...], things: [...]}")
	if not data is Dictionary:
		return
	var bad: Array = []
	var ids := {}
	for form in data.get("forms", []):
		var text: Variant = form.get("form")
		var ok: bool = _is_id(form.get("id")) and not ids.has(form.get("id")) and form.get("how") in Lore.NAME_HOWS \
				and _status_ok(form) and form.get("source") is String and text is String and text.contains("{")
		ids[form.get("id")] = true
		if ok:
			var bare: String = text
			for slot in Lore.NAME_SLOTS:
				bare = bare.replace("{%s}" % slot, "")
			# A name is a name, not a line: no other slot, no quotes, no I or you.
			ok = not bare.contains("{") and not bare.contains("}") and not bare.contains("\"") and not _personal(bare)
		if not ok:
			bad.append(form.get("id"))
	_check(bad.is_empty(), "every form is well formed, filled only from %s %s" % [Lore.NAME_SLOTS, bad])
	bad = []
	for thing in data.get("things", []):
		if not (_is_id(thing.get("id")) and not ids.has(thing.get("id")) and thing.get("for") is String \
				and thing.get("words") is String and not thing["words"].is_empty() and _status_ok(thing) and thing.get("source") is String):
			bad.append(thing.get("id"))
		ids[thing.get("id")] = true
	_check(bad.is_empty(), "every thing word is well formed %s" % [bad])
	Lore.reload()
	var drafts := Lore.name_forms("", "draft").map(func(form: Dictionary) -> String: return form["id"])
	_check("holder_possessive" in drafts, "the holder form from style.md is there to preview %s" % [drafts])


func _test_names() -> void:
	print("\n== Lore.name_forms, thing_word, render_name ==")
	var forms := [
		{"id": "held", "how": "holder", "form": "{holder}'s {thing}", "status": "agreed"},
		{"id": "slayer", "how": "deed", "form": "{deed}", "status": "draft"},
		{"id": "open", "how": "maker", "form": "{maker}'s work", "status": "asked", "ask": "X"},
	]
	var things := [
		{"id": "brand", "for": "sword", "words": "brand", "status": "agreed"},
		{"id": "edge", "for": "blade", "words": "edge", "status": "agreed"},
		{"id": "pole", "for": "spear", "words": "pole", "status": "draft"},
	]
	Lore.use([], [], forms, things)
	var form_ids := func(how: String, least := "agreed") -> Array:
		return Lore.name_forms(how, least).map(func(form: Dictionary) -> String: return form["id"])
	_check(form_ids.call("") == ["held"] and form_ids.call("", "draft") == ["held", "slayer"], "only agreed forms count; drafts when previewed; never an asked one")
	_check(form_ids.call("deed", "draft") == ["slayer"] and form_ids.call("maker", "draft").is_empty(), "forms by how the name came")
	_check(Lore.thing_word("sword") == "brand" and Lore.thing_word("axe", PackedStringArray(["blade"])) == "edge", "a thing's word by its item id, else by a tag")
	_check(Lore.thing_word("sword", PackedStringArray(["blade"])) == "brand", "the item id wins over a tag")
	_check(Lore.thing_word("spear") == "" and Lore.thing_word("spear", PackedStringArray(), "draft") == "pole", "a draft word counts only when previewed")
	var wren := {"form": "held", "holder": "Wren", "made_step": 10}
	_check(Lore.render_name(wren, "sword") == "Wren's brand" and Lore.render_name(wren, "dagger", PackedStringArray(), "dagger") == "Wren's dagger",
			"a name renders with lore's word for the thing, else the item's own")
	_check(Lore.render_name(wren, "spear", PackedStringArray(), "spear") == "Wren's spear", "reforged into a spear, it keeps the name with the new word")
	_check(Lore.render_name({"form": "slayer", "deed": "Goblin-bane"}, "sword") == "Goblin-bane", "a stored form renders whatever its status now")
	_check(Lore.render_name({"form": "gone", "holder": "Wren"}, "sword") == "" and Lore.render_name({"form": "held"}, "sword") == ""
			and Lore.render_name({"form": "held", "holder": "Wren"}, "axe") == "", "an unknown form, a missing holder or no word for the thing renders nothing")
	Lore.reload()


func _test_roles_file() -> void:
	print("\n== roles.json: professions by economy's trade ids, hidden personality types (decision 376) ==")
	var data: Variant = _read("roles")
	_check(data is Dictionary and data.get("professions") is Array and data.get("types") is Array, "roles.json is {professions: [...], types: [...]}")
	if not data is Dictionary:
		return
	var trades := _trades()
	var bad: Array = []
	var ids := {}
	var jobless: Array = []
	for list in ["professions", "types"]:
		for role in data.get(list, []):
			var id: Variant = role.get("id")
			var shown: Variant = role.get("profile")
			var ok: bool = _is_id(id) and not ids.has(id) and role.get("name") is String and _status_ok(role) \
					and role.get("source") is String and (not role.has("binding") or role["binding"] in Lore.BINDINGS) \
					and (list == "types" or role.has("binding"))
			ok = ok and shown is Dictionary and shown.get("domain") is Array and _status_ok(shown) and shown.get("source") is String
			for stat in Lore.STATS:
				# A profession sets every stat; a type only those it changes.
				ok = ok and shown is Dictionary and (shown.get(stat) in Lore.LEVELS or (list == "types" and not shown.has(stat)))
			# A binding is Jeff's word: the profile (a type's over a plain mid one) must make it.
			if ok and role.has("binding") and Lore.derived_binding(shown) != role["binding"]:
				ok = false
			ids[id] = true
			if not ok:
				bad.append(id)
			if list == "professions" and not trades.has(id):
				jobless.append(id)
	var plain: Variant = data.get("townsfolk")
	var plain_ok: bool = plain is Dictionary and _status_ok(plain) and Lore.derived_binding(plain) == Lore.TOWNSFOLK
	for stat in Lore.STATS:
		plain_ok = plain_ok and plain is Dictionary and plain.get(stat) in Lore.LEVELS
	_check(bad.is_empty() and plain_ok, "every profession, type and the townsfolk have a well formed profile that makes its binding %s" % [bad])
	_check(data.get("default_type") in data.get("types", []).map(func(role: Dictionary) -> Variant: return role.get("id")), "the default type is a type")
	print("  (professions with no job yet: %s)" % [jobless])
	bad = []
	for id in _entries:
		var role: Variant = _entries[id].get("role")
		if role != null and not (ids.has(role) or trades.has(role)):
			bad.append(id)
	_check(bad.is_empty(), "an entry's role is a listed profession or a trade %s" % [bad])
	Lore.reload()
	_check(Lore.binding("priest") == "official" and Lore.binding("hauler") == Lore.TOWNSFOLK and Lore.binding("hauler", "thief") == "free",
			"on the files: a priest is official, a hauler townsfolk, a thieving hauler free")
	_check(Lore.binding("priest", "thief") == "free", "a thieving priest may lie")
	_check(Lore.knower_for("priest") == "priest" and Lore.knower_for("hauler") == "townsfolk", "a priest knows as a priest; a hauler as the townsfolk")
	var healer := Lore.profile("medicine_man")
	_check(healer.get("intellect") == 8 and healer.get("creativity") == 2 and healer["words"]["superstition"] == "high"
			and healer["domain"] == ["nature"] and healer["binding"] == "official", "on the files: Jeff's medicine man, as words and numbers %s" % [healer])
	var thieving := Lore.profile("medicine_man", "thief")
	_check(thieving["integrity"] == 2 and thieving["creativity"] == 8 and thieving["intellect"] == 8 and thieving["domain"] == ["nature", "commerce", "goods"]
			and thieving["binding"] == "free", "a thieving medicine man: the type's stats over his, both domains %s" % [thieving])
	_check("thief" in Lore.types() and not "steady" in Lore.types(), "Lore.types lists the agreed types (Jeff's thief, not the draft steady) %s" % [Lore.types()])


func _test_roles() -> void:
	print("\n== Lore.binding and profile: professions, types, the status gate ==")
	var plain := {"domain": [], "superstition": "mid", "creativity": "low", "intellect": "mid", "integrity": "mid", "status": "draft"}
	Lore.use_roles([
		{"id": "reeve", "binding": "official", "status": "agreed", "profile": {"domain": ["law"], "superstition": "low",
				"creativity": "low", "intellect": "high", "integrity": "high", "status": "agreed"}},
		{"id": "porter", "binding": "official", "status": "agreed", "profile": {"domain": ["a"], "creativity": "low", "integrity": "high",
				"superstition": "mid", "intellect": "mid", "status": "draft"}},
		{"id": "maybe", "binding": "official", "status": "asked", "ask": "X", "profile": {"status": "asked", "ask": "X"}},
	], [
		{"id": "steady", "status": "agreed", "profile": {"domain": [], "status": "agreed"}},
		{"id": "liar", "binding": "free", "status": "agreed", "profile": {"domain": ["b"], "integrity": "low", "status": "agreed"}},
		{"id": "dreamer", "binding": "free", "status": "agreed", "profile": {"domain": [], "creativity": "high", "status": "draft"}},
	], plain)
	_check(Lore.binding("reeve") == "official" and Lore.binding("nobody") == Lore.TOWNSFOLK, "a profession's binding; townsfolk when unlisted")
	_check(Lore.binding("porter") == "official", "a profession whose profile is a draft stands on its binding")
	_check(Lore.binding("maybe", "", "draft") == Lore.TOWNSFOLK, "an asked profession never counts")
	_check(Lore.binding("reeve", "liar") == "free" and Lore.binding("nobody", "dreamer") == "free", "a type that may lie makes anyone free, its profile counted or its binding")
	var reeve := Lore.profile("reeve", "liar")
	_check(reeve["integrity"] == 2 and reeve["intellect"] == 8 and reeve["domain"] == ["law", "b"], "a type's stats over the profession's where set; both domains %s" % [reeve])
	_check(Lore.profile("porter").is_empty() and Lore.profile("porter", "", "draft")["superstition"] == 5, "a draft profile counts only when previewed")
	_check(Lore.profile("nobody").is_empty() and Lore.profile("nobody", "", "draft")["binding"] == Lore.TOWNSFOLK, "an unlisted trade has the townsfolk's profile")
	_check(Lore.profile("nobody", "liar")["integrity"] == 2 and Lore.profile("nobody", "liar")["creativity"] == 5, "a type alone: its stats, the rest mid")
	_check(Lore.derived_binding({"creativity": "low", "integrity": "high"}) == "official" and Lore.derived_binding({"creativity": "high", "integrity": "high"}) == "free"
			and Lore.derived_binding({"integrity": "low"}) == "free" and Lore.derived_binding({"creativity": "low"}) == Lore.TOWNSFOLK,
			"low creativity and high integrity speak only lore; high creativity or low integrity may make things up; else townsfolk")
	_check(Lore.types() == PackedStringArray(["steady", "liar", "dreamer"]), "the types that count, to roll from")
	Lore.use([
		{"id": "near", "type": "region", "status": "agreed", "facts": []},
		{"id": "far", "type": "region", "status": "agreed", "facts": []},
		{"id": "law", "status": "agreed", "tags": [], "facts": [
			{"id": "law.old", "text": "old", "known": "common", "where": ["far"]},
		]},
		{"id": "b", "status": "agreed", "tags": [], "facts": [
			{"id": "b.far", "text": "far", "known": "common", "where": ["far"]},
			{"id": "b.hid", "text": "hid", "known": "secret", "where": [], "knowers": ["folk"]},
		]},
	], [
		{"id": "reeve", "status": "agreed", "where": ["near"], "tags": []},
		{"id": "townsfolk", "status": "agreed", "where": ["near"], "tags": []},
	])
	var known := func(knower: String, type := "") -> Array:
		return Lore.known_by(knower, PackedStringArray(), "agreed", type).map(func(fact: Dictionary) -> String: return fact["id"])
	_check(known.call("reeve") == ["law.old"], "a profession knows what is on its domain wherever it is, not others' secrets %s" % [known.call("reeve")])
	_check(known.call("reeve", "liar") == ["law.old", "b.far"] and known.call("townsfolk", "liar") == ["b.far"], "a type adds its domain %s" % [known.call("reeve", "liar")])
	_check(known.call("townsfolk").is_empty(), "plain townsfolk know only their home's")
	Lore.reload()


## Economy's trade ids: levels/economy.json's official jobs and its buildings'
## trade and built_by, and items.json's made.by.
func _trades() -> Dictionary:
	var out := {}
	var economy: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://levels/economy.json"))
	if economy is Dictionary:
		for trade in economy.get("official", {}):
			out[trade] = true
		for building in economy.get("buildings", {}).values():
			for key in ["trade", "built_by"]:
				if building.get(key) is String:
					out[building[key]] = true
	var items: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://levels/items.json"))
	if items is Dictionary:
		for item in items.get("items", []):
			if item is Dictionary and item.get("made") is Dictionary and item["made"].get("by") is String:
				out[item["made"]["by"]] = true
	return out


## Whether [param text] speaks as I or we, or to you: lore is stated in the
## third person ("mine" is the place, so it is not counted).
func _personal(text: String) -> bool:
	for word in text.to_lower().replace(",", " ").replace(".", " ").replace(":", " ").replace(";", " ").split(" ", false):
		if word in ["i", "me", "my", "we", "us", "our", "you", "your", "yours"]:
			return true
	return false


func _is_id(id: Variant) -> bool:
	if not id is String or id.is_empty():
		return false
	for c in id:
		if not (c == "_" or (c >= "a" and c <= "z") or (c >= "0" and c <= "9")):
			return false
	return true


## An entry's status is required; a fact's defaults to its entry's. An asked
## one names its question.
func _status_ok(thing: Dictionary, required := true) -> bool:
	if not thing.has("status"):
		return not required
	return thing["status"] in STATUSES and (thing["status"] != "asked" or thing.get("ask") is String)


func _regions_ok(where: Variant) -> bool:
	if not where is Array:
		return false
	for region in where:
		if not _entries.has(region) or _entries[region]["type"] != "region":
			return false
	return true


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
