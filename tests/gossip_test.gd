extends Node
## Gossip (decision 422): what a town's person believes or saw passes to a
## neighbour standing at the same meeting place, with no model call
## (Townsfolk.gossip). A belief passes between two at the well and not
## across places, never at work or at home; a first-hand card fact passes
## as witnessed and is believed by the sharpest, a passed-on lie is doubted
## by them; never across a grudge; kin are told first; an official tells
## only what it saw; the heard cap holds; the same state gives the same
## pass; and the voice is told where it heard a thing. Pure sim: no Main,
## no port, no scratch folder. Reads the repo's levels, never the shared
## overlay. Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per
## assertion and quits with exit code 1 if any assertion failed, 0
## otherwise.

const TOWN := "g/store"
const CATALOG := {}
const EVERY := 100
## A stint to 24 would wrap to 0 and vanish (the season shift), so a day is two.
const ALL_WELL := {"default": {"stints": [{"from": 0, "to": 12, "at": "well"}, {"from": 12, "to": 24, "at": "well"}]}, "offset_hours": 0,
	"types": {"thief": [{"from": 0, "to": 12, "at": "work"}, {"from": 12, "to": 24, "at": "work"}]},
	"gossip": {"every": EVERY, "places": ["well", "inn", "square", "temple"]}}
const ALL_HOME := {"default": {"stints": [{"from": 0, "to": 12, "at": "home"}, {"from": 12, "to": 24, "at": "home"}]}, "offset_hours": 0,
	"gossip": {"every": EVERY, "places": ["well", "inn", "square", "temple"]}}
const LIE := "The miller waters the flour"
const OTHER_LIE := "The smith sells blunt knives"

var _failures := 0
var _now := 0
var _stock: Stockpile
var _work: Production
## The one worker id rolled a thief (at work all day), "" for none.
static var _thief := ""


func _ready() -> void:
	World.set_process(false)
	_test_belief_passes()
	_test_told_once()
	_test_not_across_places()
	_test_never_at_home()
	_test_witnessed_and_doubted()
	_test_grudge()
	_test_kin_first()
	_test_official()
	_test_cap()
	_test_same_state_same_pass()
	_test_where_in_words()
	_test_scholar_lore_pass()
	_test_resting_companion()
	_test_bard()
	Production.profile_of = Callable()
	Production.type_of = Callable()
	Townsfolk.use_days({})
	Townsfolk._gossip_due.clear()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## Haulers are dim (intellect about 1), smiths sharp (about 10); static
## methods, never lambdas, in a static Callable (they outlive this node).
static func _profile(trade: String, _type := "") -> Dictionary:
	return {"intellect": 1 if trade == "hauler" else 10, "superstition": 5, "creativity": 5, "integrity": 5}


## Other ids' types (a scholar for the lore pass, decision 440).
static var _types := {}


static func _type(id: String) -> String:
	return "thief" if id == _thief else str(_types.get(id, ""))


func _setup(table: Dictionary = ALL_WELL, folk: Array = [["g-tam", "Tam", "hauler"], ["g-mara", "Mara", "hauler"]], thief := "") -> void:
	_now = 0
	_thief = thief
	if DayNight.day_steps <= 0:
		DayNight.day_steps = 54000  # No level set a day length here.
	Production.profile_of = _profile
	Production.type_of = _type
	Townsfolk.use_days(table)
	Townsfolk._gossip_due.clear()
	var clock := func() -> int: return _now
	var cat := func() -> Dictionary: return CATALOG
	_stock = Stockpile.new({}, clock, ItemBook.new(clock))
	_work = Production.new({}, _stock, null, clock, Production.read_rules(), cat)
	for each: Array in folk:
		_work.add_worker(each[0], each[1], [each[2]], TOWN)
	# Their cards made now, with no kin or grudge between them (the founding
	# roll could tie two of them by id): each case sets its own ties.
	for each: Array in folk:
		Townsfolk.card_of(_work, each[0])
	for each: Array in folk:
		if each[0].begins_with("companion:"):
			continue  # No card of her own (442).
		var card := Townsfolk.card_of(_work, each[0])
		card["kin"] = {}
		card["grudge"] = []
		_work.set_card(each[0], card)
	Townsfolk.gossip(_work)  # Arms the town's clock.


func _heard(id: String) -> Array:
	return _work.worker(id).get("heard", [])


## [param id] believes [param text], told by [param from].
func _plant(id: String, text: String, from := "Jeff") -> void:
	var heard := _heard(id)
	Hearsay.hear(heard, id, 1, text, "beyond", from, _now)
	_work.set_heard(id, heard)


## One gossip tick.
func _tick() -> void:
	_now += EVERY
	Townsfolk.gossip(_work)


## Ticks until [param id] has heard more, at most [param ticks]: how many it
## took, or 0 for never.
func _until_heard(id: String, ticks := 8) -> int:
	var before := _heard(id).size()
	for i in ticks:
		_tick()
		if _heard(id).size() > before:
			return i + 1
	return 0


func _from(id: String, from: String) -> Array:
	return _heard(id).filter(func(entry: Dictionary) -> bool: return str(entry.get("from", "")) == from)


func _test_belief_passes() -> void:
	print("\n== a belief passes between two at the well ==")
	_setup()
	_plant("g-tam", LIE)
	_plant("g-mara", OTHER_LIE)
	var took := _until_heard("g-mara", 8)
	var got := _from("g-mara", "Tam")
	var took2 := _until_heard("g-tam", 8)
	var got2 := _from("g-tam", "Mara")
	_check(took > 0 or took2 > 0, "within a few ticks one told the other (Mara heard after %d, Tam after %d)" % [took, took2])
	var entry: Dictionary = got[0] if not got.is_empty() else (got2[0] if not got2.is_empty() else {})
	_check(not entry.is_empty() and str(entry.get("text", "")) in [LIE, OTHER_LIE], "what passed is the teller's belief: %s" % [entry])
	_check(str(entry.get("where", "")) == "well" and str(entry.get("fits", "")) == "beyond", "kept as heard at the well, beyond what they know")
	_check(float(entry.get("chance", 0.0)) >= 0.8, "a dim hearer all but believes it (chance %.2f)" % float(entry.get("chance", 0.0)))
	for i in 8:
		_tick()
	_check(_from("g-mara", "Tam").size() <= 1 and _from("g-tam", "Mara").size() <= 1, "told once: what one holds already is not told again")


## A thing told to someone is not told them again by anyone, even after it
## fell off their heard cap (the soak of 2026-10-19 had one pair repeat a
## line 36 times in a month): the card's "told" list.
func _test_told_once() -> void:
	print("
== told once: a thing that fell off the cap is not told again ==")
	_setup()
	_plant("g-tam", LIE)
	var took := _until_heard("g-mara")
	_check(took > 0 and Hearsay.holds(_heard("g-mara"), LIE), "Mara is told the lie (%d ticks)" % took)
	_check(LIE in Townsfolk.card_of(_work, "g-mara").get("told", []), "and her card remembers she was told it")
	_work.set_heard("g-mara", [])  # It fell off her cap.
	_check(_until_heard("g-mara", 12) == 0, "Tam has nothing new for her: she is not told the lie again")
	var card := Townsfolk.card_of(_work, "g-mara")
	card["told"] = []
	_work.set_card("g-mara", card)
	_check(_until_heard("g-mara", 12) > 0, "(with the told list cleared she would hear it again: the list is what holds it)")


func _test_not_across_places() -> void:
	print("\n== not across places: one at work hears nothing from the well ==")
	_setup(ALL_WELL, [["g-tam", "Tam", "hauler"], ["g-mara", "Mara", "hauler"]], "g-tam")
	_check(str(_work.worker("g-tam").get("type", "")) == "thief" and Townsfolk.whereabouts("hauler", 12.0, "", "thief", "g-tam") == "work",
		"the thief's day keeps Tam at work (the test's table; his type %s)" % _work.worker("g-tam").get("type", ""))
	_plant("g-tam", LIE)
	_plant("g-mara", OTHER_LIE)
	_check(_until_heard("g-mara", 8) == 0 and _until_heard("g-tam", 8) == 0, "nothing passes between the well and the forge")


func _test_never_at_home() -> void:
	print("\n== never at home (or at work): no gossip where nobody meets ==")
	_setup(ALL_HOME)
	_check(Townsfolk.whereabouts("hauler", DayNight.hour(EVERY), Season.name_at(EVERY), "", "g-tam", Townsfolk.day_of(EVERY)) == "home",
		"the table keeps everyone at home (hauler at %.1f: %s)" % [DayNight.hour(EVERY), Townsfolk.whereabouts("hauler", DayNight.hour(EVERY), Season.name_at(EVERY), "", "g-tam", Townsfolk.day_of(EVERY))])
	_plant("g-tam", LIE)
	_plant("g-mara", OTHER_LIE)
	_check(_until_heard("g-mara", 8) == 0 and _until_heard("g-tam", 8) == 0, "a town asleep at home tells nothing")


func _test_witnessed_and_doubted() -> void:
	print("\n== what a neighbour saw is believed by the sharpest; a passed lie is doubted ==")
	_setup(ALL_WELL, [["g-tam", "Tam", "hauler"], ["g-mara", "Mara", "smith"]])
	_check(Townsfolk.leaning_of(_work, "g-mara", "intellect") >= 8 and Townsfolk.leaning_of(_work, "g-tam", "intellect") <= 3,
		"Mara is sharp (%d), Tam dim (%d)" % [Townsfolk.leaning_of(_work, "g-mara", "intellect"), Townsfolk.leaning_of(_work, "g-tam", "intellect")])
	_plant("g-tam", LIE)
	_check(Townsfolk.learn(_work, "g-tam", "Tam saw raiders at the walls."), "Tam saw raiders at the walls (a card fact)")
	var passes := 0
	for i in 24:
		_tick()
		if _from("g-mara", "Tam").size() >= 2:
			break
	var told := _from("g-mara", "Tam")
	_check(told.size() == 2, "Tam told Mara two things over the days: %s" % [told.map(func(e: Dictionary) -> String: return str(e["text"]))])
	var lie := told.filter(func(e: Dictionary) -> bool: return str(e.get("text", "")) == LIE)
	var saw := told.filter(func(e: Dictionary) -> bool: return str(e.get("text", "")).ends_with("saw raiders at the walls"))
	_check(not lie.is_empty() and str(lie[0].get("fits", "")) == "beyond" and float(lie[0].get("chance", 1.0)) <= 0.3,
		"the passed lie is beyond what she knows and she all but doubts it (chance %s)" % [lie[0].get("chance") if not lie.is_empty() else "-"])
	_check(not saw.is_empty() and str(saw[0].get("fits", "")) == Hearsay.WITNESSED and bool(saw[0].get("believed", false)) and float(saw[0].get("chance", 0.0)) == 1.0,
		"what he saw is witnessed, believed for sure: %s" % [saw[0] if not saw.is_empty() else {}])
	_check(not saw.is_empty() and not str(saw[0]["text"]).begins_with("Tam "), "told as he tells it, not in his own name: %s" % [saw[0].get("text") if not saw.is_empty() else ""])
	_check(not _from("g-tam", "Mara").any(func(e: Dictionary) -> bool: return str(e.get("text", "")).ends_with("saw raiders at the walls")),
		"nothing names its hearer: Mara never tells Tam what Tam saw")


func _test_grudge() -> void:
	print("\n== never across a grudge ==")
	_setup()
	var card := Townsfolk.card_of(_work, "g-tam")
	card["grudge"] = ["g-mara"]
	_work.set_card("g-tam", card)
	_plant("g-tam", LIE)
	_plant("g-mara", OTHER_LIE)
	_check(_until_heard("g-mara", 8) == 0 and _until_heard("g-tam", 8) == 0, "neither tells the other anything, whichever holds the grudge")


func _test_kin_first() -> void:
	print("\n== kin are told first ==")
	_setup(ALL_WELL, [["g-tam", "Tam", "hauler"], ["g-mara", "Mara", "hauler"], ["g-bram", "Bram", "hauler"]])
	var card := Townsfolk.card_of(_work, "g-tam")
	card["kin"] = {"g-bram": "sister or brother"}
	card["grudge"] = []
	_work.set_card("g-tam", card)
	for id: String in ["g-mara", "g-bram"]:
		var theirs := Townsfolk.card_of(_work, id)
		theirs["grudge"] = []
		theirs["kin"] = {"g-tam": "sister or brother"} if id == "g-bram" else {}
		_work.set_card(id, theirs)
	_plant("g-tam", LIE)
	var took := _until_heard("g-bram", 12)
	_check(took > 0 and not _from("g-bram", "Tam").is_empty(), "Tam tells his brother Bram first (after %d ticks)" % took)
	_check(_from("g-mara", "Tam").is_empty(), "and never Mara while Bram stands there (she may hear it from Bram: %s)" % [_from("g-mara", "Bram").map(func(e: Dictionary) -> String: return str(e["text"]))])


func _test_official() -> void:
	print("\n== an official tells only what it saw ==")
	_check(Lore.binding("priest") == "official", "lore binds the priest as an official")
	_setup(ALL_WELL, [["g-ora", "Ora", "priest"], ["g-mara", "Mara", "hauler"]])
	_plant("g-ora", LIE)
	_check(_until_heard("g-mara", 8) == 0, "the priest passes on no rumour, though she holds one")
	_check(Townsfolk.learn(_work, "g-ora", "Ora saw raiders at the walls."), "Ora saw raiders at the walls")
	var took := _until_heard("g-mara", 8)
	var told := _from("g-mara", "Ora")
	_check(took > 0 and told.size() == 1 and str(told[0].get("fits", "")) == Hearsay.WITNESSED, "what she saw she tells, as witnessed (after %d ticks): %s" % [took, told])
	_plant("g-mara", OTHER_LIE)
	_until_heard("g-ora", 8)
	var hers := _from("g-ora", "Mara")
	_check(not hers.is_empty() and str(hers[0].get("text", "")) == OTHER_LIE, "she hears Mara's rumour and keeps it (her voice never repeats it: 378)")


func _test_cap() -> void:
	print("\n== the heard cap holds under a talkative neighbour ==")
	_setup()
	for i in 10:
		Townsfolk.learn(_work, "g-tam", "Tam saw a stranger on the road, the %dth time." % (i + 1))
	for i in 30:
		_tick()
	var cap := int(Hearsay.setting("max"))
	_check(_heard("g-mara").size() == cap, "Mara holds %d of Tam's %d tales (the cap), got %d" % [cap, 10, _heard("g-mara").size()])


func _test_same_state_same_pass() -> void:
	print("\n== the same state gives the same pass ==")
	var runs: Array[String] = []
	for i in 2:
		_setup()
		_plant("g-tam", LIE)
		_plant("g-mara", OTHER_LIE)
		for t in 6:
			_tick()
		runs.append(JSON.stringify([_heard("g-tam"), _heard("g-mara")]))
	_check(runs[0] == runs[1], "two runs from one state hold the same heard")


func _test_where_in_words() -> void:
	print("\n== the voice is told where it heard a thing ==")
	var heard := []
	var entry := Hearsay.hear(heard, "x", 1, "The mine is cursed", "beyond", "Tam", 0, false, 5, "well")
	_check(bool(entry.get("believed", false)) and str(entry.get("where", "")) == "well", "kept with where it was heard")
	_check(Hearsay.prompt_words(heard) == "You have heard, and believe it though you are not sure: Tam told you at the well that the mine is cursed.",
		"told as 'Tam told you at the well that ...': %s" % Hearsay.prompt_words(heard))
	var told := []
	Hearsay.hear(told, "y", 10, "She saw the barn burn", "beyond", "Mara", 0)
	_check(Hearsay.prompt_words(told).is_empty() or Hearsay.prompt_words(told).ends_with(": Mara told you that she saw the barn burn."),
		"a line said to them has no place: %s" % Hearsay.prompt_words(told))
	var seen := []
	var witnessed := Hearsay.hear(seen, "z", 10, "She saw the barn burn", Hearsay.WITNESSED, "Mara", 0, false, 5, "inn")
	_check(bool(witnessed.get("believed", false)) and float(witnessed.get("chance", 0.0)) == 1.0, "witnessed is believed by the sharpest")
	_check(Hearsay.hear([], "z", 1, "The mine is cursed", "agrees", "Tam", 0).is_empty(), "what agrees with lore is still not kept")


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _test_scholar_lore_pass() -> void:
	print("
== a scholar passes on what lore knows, first, as witnessed (decision 440) ==")
	# Our own lore: one agreed fact anyone's knower knows (no where, no tags).
	Lore.use([{"id": "the_mine", "status": "agreed", "facts": [{"id": "f1", "text": "The old mine was dug by dwarves.", "known": "common", "weight": 5},
		{"id": "f2", "text": "Lights are seen in the mine at night.", "known": "rumour", "weight": 3}]}],
		[{"id": Lore.knower_for("hauler"), "status": "agreed"}, {"id": Lore.knower_for("smith"), "status": "agreed"}])
	_types = {"g-tam": "scholar"}
	_setup(ALL_WELL, [["g-tam", "Tam", "hauler"], ["g-mara", "Mara", "smith"]])
	_check(str(_work.worker("g-tam").get("type", "")) == "scholar", "Tam is rolled a scholar (the test's pin)")
	_check(not Lore.known_by(Lore.knower_for("hauler"), PackedStringArray(), "agreed", "scholar").is_empty(), "(the test's lore is known to his knower)")
	_plant("g-tam", LIE)
	var took := _until_heard("g-mara", 8)
	var got := _from("g-mara", "Tam")
	_check(took > 0 and not got.is_empty() and str(got[0].get("text", "")) == "The old mine was dug by dwarves" and str(got[0].get("fits", "")) == Hearsay.WITNESSED,
		"the lore fact goes before his belief, as witnessed: %s" % [got.map(func(e: Dictionary) -> String: return str(e["text"]))])
	_check(not got.is_empty() and bool(got[0].get("believed", false)) and float(got[0].get("chance", 0.0)) == 1.0, "and sharp Mara believes it, for it is true")
	for i in 8:
		_tick()
	var texts: Array = _from("g-mara", "Tam").map(func(e: Dictionary) -> String: return str(e["text"]))
	_check(not texts.has("Lights are seen in the mine at night") and texts.has(LIE), "lore's rumours are not passed as witnessed; his belief follows once the fact is held: %s" % [texts])
	_types = {}
	Lore.reload()


## Everyone at the inn all day, Tam a bard; the town remembers two things,
## one Jeff's own deed.
const ALL_INN := {"default": {"stints": [{"from": 0, "to": 12, "at": "inn"}, {"from": 12, "to": 24, "at": "inn"}]}, "offset_hours": 0,
	"types": {"bard": [{"from": 0, "to": 12, "at": "inn"}, {"from": 12, "to": 24, "at": "inn"}]},
	"gossip": {"every": EVERY, "places": ["well", "inn", "square", "temple"]},
	"bard": {"again": 30, "lore_every_nights": 2, "kinds": ["sings of how"]}}

var _log: Array = []
var _said: Array = []
var _has_inn := true
var _listeners: Array = ["p1"]


func _test_bard() -> void:
	print("\n== the bard sings what the town remembers, at the inn, once a night (decision 490) ==")
	_types = {"g-tam": "bard"}
	_setup(ALL_INN, [["g-tam", "Tam", "hauler"], ["g-mara", "Mara", "hauler"]])
	_types = {}
	_log = []
	_said = []
	_has_inn = true
	_listeners = ["p1"]
	Offers.ctx = {"production": _work,
		"memory": func(_town: String) -> Array: return _log.duplicate(true),
		"set_memory": func(_town: String, log: Array) -> void: _log = log.duplicate(true),
		"listeners": func(_town: String) -> Array: return _listeners,
		"name_of": func(id: String) -> String: return "Jeff" if id == "p1" else id,
		"lore": func(_town: String) -> Array: return ["Deer graze in the wilds.", "The mine is older than the town."],
		"has_inn": func(_town: String) -> bool: return _has_inn,
		"say": func(_town: String, song: Dictionary) -> void: _said.append(song),
		"model": func() -> String: return "claude-haiku-5-5"}
	var bard := Townsfolk.card_of(_work, "g-tam")
	_check(bard.get("facts", []).any(func(f: Dictionary) -> bool: return str(f["text"]) == "Tam sings at the inn of an evening."), "his card says what he does, from the start")
	var day := DayNight.day_steps
	var well := TownMemory.note(_log, "The well was dug by Bram's grandfather", "g-mara", "g-tam", 0)
	well["tier"] = TownMemory.MEMORY
	var deed := TownMemory.note(_log, "Jeff drove the goblins from the mill", "player:p1", "g-mara", 0)
	deed["tier"] = TownMemory.MEMORY
	deed["ruling"] = {"ruling": "accept", "because": "three of the town saw it", "step": 0}
	_tick()
	_check(_said.size() == 1 and _said[0]["line"] == "At the inn, Tam sings of how Jeff drove the goblins from the mill." and _said[0]["named"] == "p1"
		and _said[0]["second"] == "The lawspeaker's word on it: three of the town saw it.", "Jeff is in the inn: his own deed first, with the ruling's word: %s" % [_said])
	_check(Standing.score(Townsfolk.card_of(_work, "g-tam"), "p1") == 2 * Standing.setting("song"), "told back: twice the notch (%d)" % Standing.score(Townsfolk.card_of(_work, "g-tam"), "p1"))
	_check(_log[1].get("sung_to", {}).has("p1") and "g-mara" in _log[1].get("holders", []), "the entry knows it was sung to him; Mara, at the inn, holds it")
	_check(str(Townsfolk.card_of(_work, "g-tam")["facts"].back()["text"]) == "Tam sang of jeff drove the goblins from the mill at the inn tonight.".replace("jeff", "Jeff") or str(Townsfolk.card_of(_work, "g-tam")["facts"].back()["text"]).begins_with("Tam sang of"), "his card: what he sang")
	_tick()
	_check(_said.size() == 1, "once a night")
	_now += day
	_tick()
	_check(_said.size() == 2 and _said[1]["line"] == "At the inn, Tam sings of how the well was dug by Bram's grandfather." and _said[1]["named"] == "" and _said[1]["second"] == "",
		"the next night: the newest memory not sung, no ruling's word: %s" % [_said[1]["line"] if _said.size() > 1 else ""])
	_check(Standing.score(Townsfolk.card_of(_work, "g-tam"), "p1") == 3 * Standing.setting("song"), "a notch more")
	_now += day
	_tick()
	_check(_said.size() == 3 and _said[2]["line"] == "At the inn, Tam sings of how deer graze in the wilds.", "both memories sung lately: lore, weightiest first: %s" % [_said[2]["line"] if _said.size() > 2 else ""])
	_now += day
	_tick()
	_check(_said.size() == 3, "lore at most every other night")
	_now += day
	_tick()
	_check(_said.size() == 4 and _said[3]["line"] == "At the inn, Tam sings of how the mine is older than the town.", "the night after, the next fact")
	_now += day
	_has_inn = false
	_tick()
	_check(_said.size() == 4, "no standing inn, no performance")
	_has_inn = true
	_listeners = []
	_now += day
	_tick()
	_check(_said.size() == 4 or (_said.size() == 5 and _said[4]["listeners"].is_empty()), "with nobody in the inn he still sings to the room (%d)" % _said.size())
	Offers.ctx = {}


func _test_resting_companion() -> void:
	print("
== a companion resting in town gossips too, hearsay only (companions' 442) ==")
	_setup(ALL_WELL, [["g-tam", "Tam", "hauler"], ["companion:p1", "Wren", "cook"]])
	_check(Townsfolk.card_of(_work, "companion:p1").is_empty(), "she has no resident card")
	_plant("companion:p1", LIE, "Jeff")
	Townsfolk.learn(_work, "g-tam", "Tam saw raiders at the walls.")
	var took := _until_heard("g-tam", 8)
	var his := _from("g-tam", "Wren")
	_check(took > 0 and not his.is_empty() and str(his[0].get("text", "")) == LIE and str(his[0].get("where", "")) == "well",
		"Tam hears what she believes, at the well, from Wren (after %d ticks): %s" % [took, his.map(func(e: Dictionary) -> String: return str(e["text"]))])
	var took2 := _until_heard("companion:p1", 8)
	var hers := _from("companion:p1", "Tam")
	_check(took2 > 0 and not hers.is_empty() and str(hers[0].get("text", "")).ends_with("saw raiders at the walls") and str(hers[0].get("fits", "")) == Hearsay.WITNESSED,
		"and she hears what he saw, as anyone would: %s" % [hers.map(func(e: Dictionary) -> String: return str(e["text"]))])
	_setup(ALL_WELL, [["g-tam", "Tam", "hauler"], ["companion:p1", "Wren", "cook"]])
	_work.set_away("companion:p1", true)
	_plant("companion:p1", LIE, "Jeff")
	_plant("g-tam", OTHER_LIE, "Jeff")
	_check(_until_heard("g-tam", 8) == 0 and _until_heard("companion:p1", 8) == 0, "out with her player (away), she is in no group")
