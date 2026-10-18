extends Node
## Resident cards (decision 398): a card per town resident, rolled by worker
## id from levels/resident_traits.json (the same every time; the tables well
## formed), how they came from a real rescue else the table, a look the
## character generator reads (no beard for a woman, grey hair likelier when
## old), the plain card's words and the written paragraph taken only when
## it is one; kept on economy's worker record through Townsfolk.card_of
## (made once, a save from before gets one, a companion none); kin and a
## grudge rolled at founding into both residents' cards; facts from the
## town's events by templates (a raid's captives and witnesses, a homecoming,
## a loan taken and paid back, raiders seen), each once, capped, told to the
## voice newest first within the budget; the resident's voice reads the card
## and its hidden type. Reads the repo's levels, never the shared overlay;
## no network. Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL
## per assertion and quits with exit code 1 if any assertion failed, 0
## otherwise.

const TOWN := "rc/store"

var _failures := 0
var _now := 0
var _stock: Stockpile
var _work: Production
var _towns: Towns


func _ready() -> void:
	World.set_process(false)
	Production.type_of = Townsfolk.roll_type
	_test_tables()
	_test_roll()
	_test_plain_card()
	_test_record()
	_test_kin_and_grudge()
	_test_events()
	_test_voice()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _setup(saved := {}) -> void:
	_now = 1000
	var clock := func() -> int: return _now
	var cat := func() -> Dictionary: return {}
	_stock = Stockpile.new({}, clock, ItemBook.new(clock))
	_work = Production.new(saved, _stock, null, clock, Production.read_rules(), cat)
	_towns = Towns.new({}, _work, {}, clock)
	Townsfolk.watch(_work, _towns)


func _resident(id: String, name: String, trade := "cook", origin := "placeholder") -> void:
	_work.add_worker(id, name, [trade], TOWN, origin, Townsfolk.STEADY)


func _texts(id: String) -> Array:
	return Townsfolk.card_of(_work, id).get("facts", []).map(func(fact: Dictionary) -> String: return str(fact["text"]))


func _test_tables() -> void:
	print("\n== levels/resident_traits.json: the tables, the look, kin, grudge, growth ==")
	ResidentCard.use_tables({})
	var table := ResidentCard.tables()
	var bad: Array[String] = []
	for key: String in ResidentCard.KEYS + ["came"]:
		if not table.get(key) is Array or table[key].size() < 4:
			bad.append(key)
	var look: Dictionary = table.get("look", {})
	for key: String in ResidentCard.LOOK_KEYS + ["age"]:
		if not look.get(key) is Array or look[key].is_empty():
			bad.append("look." + key)
	_check(bad.is_empty(), "every trait table and look table has entries %s" % [bad])
	var kin: Dictionary = table.get("kin", {})
	var grudge: Dictionary = table.get("grudge", {})
	_check(float(kin.get("chance", -1)) >= 0.0 and float(kin.get("chance", 2)) <= 1.0 and kin.get("kinds") is Array
		and float(grudge.get("chance", -1)) >= 0.0 and float(grudge.get("chance", 2)) <= 1.0 and grudge.get("causes") is Array,
		"kin and grudge have a chance in 0..1 and their kinds and causes")
	var growth: Dictionary = table.get("growth", {})
	_check(int(growth.get("facts_max", 0)) >= 8 and int(growth.get("shown", 0)) >= 3 and int(growth.get("prompt_chars", 0)) >= 200, "growth caps are set")
	var modern := ["okay", "pressure", "stress", "team", "player", "game"]
	var found: Array[String] = []
	for key: String in ResidentCard.KEYS + ["came"]:
		for entry: Variant in table.get(key, []):
			for word: String in modern:
				if (" " + str(entry) + " ").contains(" " + word):
					found.append(str(entry))
	_check(found.is_empty(), "no modern or game words in the tables (lore's style) %s" % [found])


func _test_roll() -> void:
	print("\n== the roll: by id, how they came, the look ==")
	ResidentCard.use_tables({})
	var first := ResidentCard.roll("rc-bram", "Bram", "smith")
	var again := ResidentCard.roll("rc-bram", "Bram", "smith")
	_check(first == again, "the same id rolls the same card")
	var other := ResidentCard.roll("rc-mara", "Mara", "cook")
	_check(first["traits"] != other["traits"] or first["look"] != other["look"], "another id rolls another")
	for key: String in ResidentCard.KEYS:
		if str(first["traits"].get(key, "")).is_empty():
			_check(false, "trait %s rolled" % key)
	_check(first["traits"]["name"] == "Bram" and first["traits"]["trade"] == "smith" and first["facts"].is_empty() and first["card"] == "",
		"the card carries the name and trade, no facts, no written paragraph yet")
	var rescued := ResidentCard.roll("rc-tam", "Tam", "carpenter", "rescued:camp_north", "Jeff")
	_check(rescued["came"] == "was rescued from captivity and brought home to the town by Jeff", "a rescued resident's coming is the rescue, by whoever did it (%s)" % rescued["came"])
	var rescued_unknown := ResidentCard.roll("rc-tam", "Tam", "carpenter", "rescued:camp_north")
	_check(rescued_unknown["came"] == "was rescued from captivity and brought home to the town", "or without a name")
	_check(not str(first["came"]).is_empty() and not str(first["came"]).begins_with("was rescued"), "a placeholder resident's coming is the table's (%s)" % first["came"])
	var look: Dictionary = first["look"]
	var keys_ok := look.has("seed") and look["seed"] is int
	for key: String in ResidentCard.LOOK_KEYS + ["age"]:
		keys_ok = keys_ok and look.has(key) and not str(look[key]).is_empty()
	_check(keys_ok, "the look has a seed and every word %s" % [look])
	var women_bearded := 0
	var grey_old := 0
	var grey_young := 0
	var old := 0
	var young := 0
	for i in 600:
		var card := ResidentCard.roll("rc-look-%d" % i, "X", "")
		var their: Dictionary = card["look"]
		if card["traits"]["pronoun"] == "she" and their["beard"] != "none":
			women_bearded += 1
		if their["age"] == "old":
			old += 1
			grey_old += 1 if their["hair_colour"] == "grey" else 0
		elif their["age"] == "young":
			young += 1
			grey_young += 1 if their["hair_colour"] == "grey" else 0
	_check(women_bearded == 0, "no woman has a beard")
	_check(old > 0 and young > 0 and float(grey_old) / old > float(grey_young) / maxi(young, 1), "grey hair is likelier for the old (%.2f) than the young (%.2f)" % [float(grey_old) / old, float(grey_young) / maxi(young, 1)])


func _test_plain_card() -> void:
	print("\n== the card's words ==")
	ResidentCard.use_tables({})
	var card := ResidentCard.roll("rc-bram", "Bram", "medicine_man")
	var words := ResidentCard.plain_card(card)
	_check(words.begins_with("Bram was born in %s" % card["traits"]["birthplace"]) and words.contains(card["came"]) and words.contains("a medicine man")
		and words.contains(card["traits"]["fear"]) and words.contains(card["look"]["stature"]), "the plain card says where they were born, how they came, their trade spaced, their fear and their look")
	_check(not words.contains("\"") and not words.contains("..") and not words.contains(", ."), "and reads clean: %s" % words)
	print("\n== the look string for the character generator (decision 419) ==")
	var spec := ResidentCard.look_spec(card, "medicine_man")
	var pairs := {}
	for part: String in spec.split(" "):
		pairs[part.get_slice("=", 0)] = part.get_slice("=", 1)
	_check(spec.begins_with("seed=%d " % card["look"]["seed"]) and pairs.get("apron") == "yes" and pairs.has("headwear") and pairs.has("shoulders")
		and pairs.get("hair_colour") == card["look"]["hair_colour"], "seed first, every look word as key=value, an apron for the medicine man: %s" % spec)
	_check(pairs.get("body", "") == {"she": "female", "he": "male"}.get(card["traits"]["pronoun"], ""), "body from the pronoun (%s -> %s)" % [card["traits"]["pronoun"], pairs.get("body", "none")])
	_check(ResidentCard.look_spec(card, "hauler").ends_with("apron=no trade=hauler"), "no apron for a hauler, and his trade last (decision 480)")
	var outcast := card.duplicate(true)
	outcast["outcast"] = true
	_check(outcast.get("outcast") == true and ResidentCard.look_spec(outcast, "merchant").ends_with("apron=no") and not ResidentCard.look_spec(outcast, "merchant").contains("trade="),
		"an outcast's string names no trade: he stays as drawn (471)")
	var bound := card.duplicate(true)
	bound["look"]["hair"] = "bound up"
	bound["traits"]["pronoun"] = "they"
	bound["look"].erase("headwear")
	var their := ResidentCard.look_spec(bound, "")
	_check(their.contains("hair=bound ") and not their.contains("body=") and not their.contains("headwear=") and not their.contains("trade="),
		"'bound up' is written bound, 'they' leaves body to the seed, an old card without headwear leaves it out, no trade no word: %s" % their)
	_check(ResidentCard.look_spec({}, "smith").is_empty(), "no look, no string")
	_check(ResidentCard.words(card) == words, "words() is the plain card while nothing is written")
	_check(not ResidentCard.take_written(card, "Too short.") and not ResidentCard.take_written(card, "He says \"hello\" and this is long enough to pass the length test but has speech in it, so no."),
		"a short paragraph or one with speech is not taken")
	var paragraph := "Bram is a broad, quiet smith who came to the town as a child and never left it. He keeps bees behind the forge and says little, in short whole sentences. He fears fire more than anything, having seen a roof go up as a boy."
	_check(ResidentCard.take_written(card, paragraph) and ResidentCard.words(card) == paragraph and card["card_by"] == "model", "a paragraph is taken and stands as the card")
	var facts := ResidentCard.facts(card)
	_check(facts.contains("name: Bram") and facts.contains("pronoun: ") and facts.contains("how they came to the town:") and facts.contains("work: medicine man") and facts.contains("looks:"),
		"the card call's facts, one a line")


func _test_record() -> void:
	print("\n== the card on economy's record: made once, saved, a save from before, none for a companion ==")
	ResidentCard.use_tables({})
	_setup()
	_resident("rc-bram", "Bram", "smith")
	_resident("companion:jeff", "Wren", "cook", "companion:jeff")
	_check(_work.worker("rc-bram").get("card", {}).is_empty(), "a new record has no card until one is needed")
	var card := Townsfolk.card_of(_work, "rc-bram")
	_check(not card.is_empty() and _work.worker("rc-bram")["card"] == card, "card_of makes it and keeps it on the record")
	_check(Townsfolk.card_of(_work, "rc-bram") == card, "and gives the same one after")
	_check(Townsfolk.card_of(_work, "companion:jeff").is_empty() and _work.worker("companion:jeff").get("card", {}).is_empty(), "a companion resting in town has none here")
	var saved := _work.to_dict()
	_setup(saved)
	_check(_work.worker("rc-bram")["card"] == card, "the card is saved and loaded as it is")
	_setup({"workers": {"rc-old": {"name": "Old", "trades": ["smith"], "town": TOWN}}})
	_check(_work.worker("rc-old").get("card", {}).is_empty() and Townsfolk.card_of(_work, "rc-old")["traits"]["name"] == "Old", "a save from before has none and gets one when needed")


func _test_kin_and_grudge() -> void:
	print("\n== kin and a grudge at founding, in both cards ==")
	var table := ResidentCard.tables().duplicate(true)
	table["kin"] = {"chance": 1.0, "kinds": ["sister or brother"]}
	table["grudge"] = {"chance": 1.0, "causes": ["over a dog"]}
	ResidentCard.use_tables(table)
	_setup()
	_resident("rc-a", "Ann")
	_resident("rc-b", "Bram")
	Townsfolk.card_of(_work, "rc-a")
	_check(_texts("rc-a").is_empty(), "the first resident has nobody to be kin to")
	Townsfolk.card_of(_work, "rc-b")
	var a_facts := _texts("rc-a")
	var b_facts := _texts("rc-b")
	var a_she: bool = _work.worker("rc-a")["card"]["traits"]["pronoun"] == "she"
	var b_she: bool = _work.worker("rc-b")["card"]["traits"]["pronoun"] == "she"
	_check(b_facts.has("Bram is Ann's %s." % ("sister" if b_she else "brother")) and a_facts.has("Ann is Bram's %s." % ("sister" if a_she else "brother")),
		"the newcomer is kin to a neighbour, written in both cards %s / %s" % [a_facts, b_facts])
	_check(b_facts.has("Bram bears a grudge against Ann over a dog.") and a_facts.has("Bram bears a grudge against Ann over a dog."), "and bears a grudge, which both know")
	table["kin"]["kinds"] = ["parent and child"]
	ResidentCard.use_tables(table)
	_setup()
	_resident("rc-a", "Ann")
	_resident("rc-c", "Cael")
	Townsfolk.card_of(_work, "rc-a")
	Townsfolk.card_of(_work, "rc-c")
	a_she = _work.worker("rc-a")["card"]["traits"]["pronoun"] == "she"
	var c_she: bool = _work.worker("rc-c")["card"]["traits"]["pronoun"] == "she"
	_check(_texts("rc-c").has("Ann is Cael's %s." % ("mother" if a_she else "father")) and _texts("rc-a").has("Cael is Ann's %s." % ("daughter" if c_she else "son")),
		"the one in the town first is the parent %s" % [_texts("rc-c")])
	table["kin"]["chance"] = 0.0
	table["grudge"]["chance"] = 0.0
	ResidentCard.use_tables(table)
	_setup()
	_resident("rc-a", "Ann")
	_resident("rc-b", "Bram")
	Townsfolk.card_of(_work, "rc-a")
	Townsfolk.card_of(_work, "rc-b")
	_check(_texts("rc-a").is_empty() and _texts("rc-b").is_empty(), "with no chance, no kin and no grudge")
	ResidentCard.use_tables({})


func _test_events() -> void:
	print("\n== facts from the town's events, by templates, once each ==")
	var table := ResidentCard.tables().duplicate(true)
	table["kin"]["chance"] = 0.0
	table["grudge"]["chance"] = 0.0
	table["growth"] = {"facts_max": 4, "shown": 2, "prompt_chars": 600}
	ResidentCard.use_tables(table)
	_setup()
	_resident("rc-a", "Ann")
	_resident("rc-b", "Bram")
	_resident("rc-c", "Cael")
	_work.set_away("rc-c", true)
	var goblins := ResidentCard.faction_name("goblins")
	_check(goblins.begins_with("the "), "a faction is named as lore names it (%s)" % goblins)
	_towns.raided.emit(TOWN, {"town": TOWN, "faction": "goblins", "repelled": true, "captives": []})
	_check(_texts("rc-a").is_empty(), "a raid fought off leaves no mark")
	_towns.raided.emit(TOWN, {"town": TOWN, "faction": "goblins", "repelled": false, "captives": [{"id": "rc-b", "name": "Bram", "trade": "cook"}]})
	_check(_texts("rc-a").has("Ann saw Bram carried off by %s." % goblins) and _texts("rc-b").has("Bram was carried off by %s." % goblins),
		"a raid: the witness saw, the captive was carried off %s" % [_texts("rc-a")])
	_check(_texts("rc-c").is_empty(), "one away saw nothing")
	_towns.raided.emit(TOWN, {"town": TOWN, "faction": "goblins", "repelled": false, "captives": [{"id": "rc-b", "name": "Bram", "trade": "cook"}]})
	_check(_texts("rc-a").size() == 1, "the same fact twice is one")
	_towns.rescued.emit(TOWN, "rc-b", "goblins")
	_check(_texts("rc-b").has("Bram came home from %s." % goblins) and _texts("rc-a").has("Ann saw Bram come home from %s." % goblins), "home again: both remember")
	_resident("rc-d", "Dara", "smith", "rescued:camp")
	_towns.rescued.emit(TOWN, "rc-d", "")
	_check(Townsfolk.card_of(_work, "rc-d")["came"].begins_with("was rescued") and _texts("rc-a").has("Ann saw Dara come to the town, rescued from captivity."),
		"a newcomer rescued elsewhere: their card says so, the neighbours saw them come")
	_work.loan_changed.emit("rc-a", 10.0, false)
	_check(_texts("rc-a").has("Ann borrowed from the town's coffer."), "a loan is remembered")
	_work.loan_changed.emit("rc-a", 12.0, true)
	_check(_texts("rc-a").has("Ann works off a debt to the town."), "and working it off")
	_work.loan_changed.emit("rc-a", 0.0, false)
	_check(_texts("rc-a").has("Ann paid the town's coffer back."), "and paying it back")
	_work.loan_changed.emit("rc-b", 0.0, false)
	_check(not _texts("rc-b").has("Bram paid the town's coffer back."), "nothing paid back by one who never borrowed")
	Townsfolk.saw_raiders(_work, "rc-a")
	Townsfolk.saw_raiders(_work, "rc-a")
	var a_facts := _texts("rc-a")
	_check(a_facts.size() == 4 and a_facts.back() == "Ann saw raiders at the walls." and not a_facts.has("Ann saw Bram carried off by %s." % goblins),
		"past facts_max the oldest goes: %s" % [a_facts])
	var words := ResidentCard.facts_words(Townsfolk.card_of(_work, "rc-a"))
	_check(words == "Also true of Ann: Ann paid the town's coffer back. Ann saw raiders at the walls.", "the voice is told the newest, within shown, in the order they happened (%s)" % words)
	_check(Townsfolk.card_of(_work, "companion:jeff").is_empty() and not Townsfolk.learn(_work, "companion:jeff", "x"), "a companion learns nothing here")
	ResidentCard.use_tables({})


func _test_voice() -> void:
	print("\n== the resident's voice reads the card, the hidden type and the facts ==")
	ResidentCard.use_tables({})
	_setup()
	_resident("rc-sly", "Sly", "cook")
	World.production = _work
	var body := Resident.new()
	body.worker_id = "rc-sly"
	body.person = "Sly"
	body.trade = "cook"
	body.type = "thief"
	Townsfolk.learn(_work, "rc-sly", "Sly saw raiders at the walls.")
	var words := body.card_words()
	var card := Townsfolk.card_of(_work, "rc-sly")
	_check(words.begins_with(ResidentCard.plain_card(card)) and words.contains("Sly is a thief, and keeps it hidden.") and words.ends_with("Also true of Sly: Sly saw raiders at the walls."),
		"card, type, facts: %s" % words)
	body.card = "Her own card."
	_check(body.card_words() == "Her own card.", "a companion resting in town reads her own card")
	body.free()
	World.production = null


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
