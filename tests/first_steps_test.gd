extends Node
## Her first steps with a newcomer and a player at a loss (decision 945; the
## coordinator's package "the first five minutes"): a host on the wilds, its
## player new to her, the package forced on (FirstSteps.forced; the JSON's
## "on" stays false until it is whole). Her chain (the Mughouse's door, the
## pond, the catch's taker), a yes, a no, a lapse, her end told once; asked
## "Where to?", two true choices, the second taken by naming it; an unasked
## offer's rules (the gap, a no's quiet, two noes); a rising's line; a walk
## stepped off (one call, resumed) and one met by a fight (no line); off, none
## of it. Prints PASS/FAIL per assertion and quits with exit code 1 if any
## assertion failed, 0 otherwise.

var _failures := 0
var _main: Node
var _said: Array[String] = []


func _ready() -> void:
	World.set_process(false)
	var ports := preload("res://tests/test_ports.gd")
	Net.port = ports.of(18010)
	Net.companions = true
	Net.map_name = "wilds"
	Net.state_path = ports.scratch("first_steps_world.json")
	if FileAccess.file_exists(Net.state_path):
		DirAccess.remove_absolute(Net.state_path)
	Level.overlay_dir = ports.scratch("first_steps_overlay/")
	Companion.tends_unasked = false
	FirstSteps.forced = 1
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	for i in 5:
		await get_tree().process_frame
	for i in 3:
		World.step()
	for body: GridEntity in World.townsfolk().duplicate():
		World.despawn(body)  # Nobody to be busy with (Main._keeper_busy).
	DayNight.set_hour(12.0)
	var pet := _companion()
	if pet != null:
		pet.said.connect(func(line: String) -> void: _said.append(line))
	_test_tables()
	_test_card()
	_test_chain()
	_test_asked()
	_test_unasked()
	_test_rising()
	_test_stray_and_fight()
	_test_travel()
	_test_log_lines()
	_test_off()
	FirstSteps.forced = -1
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _player() -> Player:
	for entity in World.get_entities():
		if entity is Player and entity.spawned:
			return entity
	return null


func _companion() -> Companion:
	for entity in World.get_entities():
		if entity is Companion and entity.spawned:
			return entity
	return null


func _put(entity: GridEntity, tile: Vector2i) -> void:
	if entity != null and entity.tile != tile:
		World._relocate(entity, tile)


## Her player by the square, she beside them, and a lull: nobody spoke, no
## line of hers, no fight, no walk, the next second's tick due.
func _lull(pet: Companion, player: Player, at := Vector2i(196, 214)) -> void:
	_put(player, _main._nearest_free(at))
	_put(pet, _main._nearest_free(player.tile + Vector2i(1, 0)))
	pet._keeper_spoke_tick = -100000
	pet._last_unasked_tick = -100000
	pet._last_speech_tick = -100000
	pet._fight_ended_tick = -100000
	pet._held_line = {}
	pet.first_steps.fought = -100000
	pet.guide = null
	_main._guides.erase(pet.keeper_id)
	_main._chat_tick.clear()
	_main._first_steps_at = -100000
	player.hp = player.max_hp
	pet.first_steps.hp = -1
	pet.first_steps.hurt_since = -1


func _tick() -> void:
	_main._first_steps_at = -100000
	_main._first_steps_tick()


## Why no line came (a failing row's): each clause of Main._first_lull, and her chain's door.
func _why(pet: Companion, player: Player) -> String:
	var now := World.tick
	var fs := pet.first_steps
	return "quiet %s downed %s/%s idle_ok %s floor %s spoke %s fought %s zone %s dist %d hostile %s busy %s heard %s guide %s; door %s; next %s; offer %s; first_words %s at %d; lull %s" % [
		pet.quiet(), World.is_downed(pet), World.is_downed(player), pet._idle_ok(), now - pet._last_unasked_tick >= Companion.FLOOR_TICKS,
		now - pet._keeper_spoke_tick, now - fs.fought, pet.zone == player.zone, World.distance(pet.tile, player.tile),
		pet._hostile_within(Companion.SIGHT_RANGE), _main._keeper_busy(pet), pet.heard_by_anyone(), pet.guide != null and pet.guide.going(),
		_main._first_door(player.zone), fs.next_step(), fs.offer, pet.first_words, fs.first_words_tick, _main._first_lull(pet, player)]


func _says(line: String) -> void:
	_main._chat_tick.clear()
	_main._player_said(_player(), line)


func _in_deck(line: String, key: String, pet: Companion) -> bool:
	for each: Variant in FirstSteps.lines(key, str(pet.traits.get("temperament", ""))):
		var words := str(each)
		if words == line or "%s" in words and RegEx.create_from_string("^" + _escaped(words).replace("%s", ".+") + "$").search(line) != null:
			return true
	return false


static func _escaped(text: String) -> String:
	var out := ""
	for c in text:
		out += "\\" + c if c in ".?*+()[]{}|^$\\" else c
	return out


func _test_tables() -> void:
	print("\n== her decks and rules are the table's (companion_traits.json first_steps) ==")
	var table := FirstSteps.table()
	_check(table.get("on") == false, "the package's switch is off in the JSON (%s)" % [table.get("on")])
	var keys := ["offer.mughouse", "offer.pond", "offer.catch", "arrive.mughouse", "arrive.pond", "arrive.catch", "go.mughouse",
		"go.pond", "go.healer", "go.temple", "go.barrow", "sit", "bed", "hurt", "risen.temple_paid", "risen.temple", "risen.healer",
		"choice.barrow", "choice.healer", "choice.mughouse", "choice.pond", "choice.temple", "asked", "asked_one", "no", "stray", "chain_end"]
	var missing := keys.filter(func(key: String) -> bool: return FirstSteps.lines(key, "").is_empty())
	_check(missing.is_empty(), "every deck of the design is written (missing: %s)" % [missing])
	var barred := RegEx.create_from_string("(?i)(^go to|\\b(you must|you need to|you should|lost|stuck|quest|click|press|menu|window|offering)\\b)")
	var bad: Array[String] = []
	for key: String in keys:
		for line: Variant in FirstSteps.lines(key, ""):
			if barred.search(str(line)) != null and not (key == "risen.temple_paid" and "offering" in str(line)):
				bad.append(str(line))
	_check(bad.is_empty(), "no deck line orders, names the trouble or the screen (%s)" % [bad])
	_check(FirstSteps.ticks("gap_s", 0) == 180 * World.TICK_RATE and FirstSteps.ticks("lapse_s", 0) == 90 * World.TICK_RATE
		and int(FirstSteps.rule("per_hour", 0)) == 4, "the rules are the design's (gap 180 s, lapse 90 s, 4 an hour)")


func _test_card() -> void:
	print("\n== a newcomer's companion has a chain card; one met before 945 has none ==")
	var pet := _companion()
	var record: PlayerRecord = _main._record_of(pet) if pet != null else null
	_check(pet != null and pet.first_steps != null and record != null and record.companion.get("first_steps") is Dictionary
		and pet.first_steps.card == record.companion["first_steps"], "her first steps' card is her record's (%s)" % [
		record.companion.get("first_steps") if record != null else null])
	_check(pet != null and pet.first_steps.next_step() == "mughouse", "her chain starts at the Mughouse")
	var kept := PlayerRecord.from_dict(JSON.parse_string(JSON.stringify(record.to_dict()))) if record != null else null
	_check(kept != null and kept.companion.get("first_steps") is Dictionary and kept.companion["first_steps"].get("done") == [],
		"and is kept through a save and a load (%s)" % [
		kept.companion.get("first_steps") if kept != null else null])
	var old := FirstSteps.new()
	old.reached("pond", 3)
	_check(not old.chain_running() and old.end_told() and old.days_at("pond") == [3], "an old companion's card holds no chain, only places reached")


func _test_chain() -> void:
	print("\n== her chain: the Mughouse's door, then the pond; a no to the pond ends it, its end told once ==")
	var pet := _companion()
	var player := _player()
	if pet == null or player == null:
		_check(false, "(a player and their companion)")
		return
	var fs := pet.first_steps
	pet.first_words = false
	fs.first_words_tick = World.tick - 1000
	_lull(pet, player)
	_said.clear()
	_tick()
	var offer: Dictionary = _main._guide_offers.get(pet.keeper_id, {})
	var to: Dictionary = offer.get("to", {})
	var points: Dictionary = Level.load_level("wilds").get("spawn_points", {})
	var door: Variant = null
	for name: String in Main.FIRST_DOOR_POINTS:
		if points.get(name) is Vector2i:
			door = points[name]
			break
	_check(str(fs.offer.get("kind", "")) == "mughouse" and not _said.is_empty() and _in_deck(_said[-1], "offer.mughouse", pet),
		"in a lull after her first words she offers the Mughouse in her deck's words (%s%s)" % [_said, "" if not _said.is_empty() else "; " + _why(pet, player)])
	_check(to.get("first") == "mughouse" and to.get("cell") == door and int(to.get("arrive", 0)) == 1,
		"its walk ends on the door's stop cell, %s (%s)" % [door, to.get("cell")])
	_said.clear()
	_tick()
	_check(_said.is_empty(), "one offer stands at a time: nothing more the next second")
	_says("Yes.")
	_check(pet.guide != null and pet.guide.going() and pet.guide.goal.get("first") == "mughouse", "a yes sets her off to the door")
	_said.clear()
	pet._last_unasked_tick = -100000  # Her offer this tick holds a NEEDED line under the floor; in play the walk takes longer.
	_main._guide_done(pet, "arrived")
	_check(fs.next_step() == "pond" and _said.size() == 1 and _in_deck(_said[0], "arrive.mughouse", pet) and pet.guide == null,
		"there, her arrival line, the deck's, and she stops: the choice to go in is theirs (%s)" % [_said])
	_lull(pet, player)
	_said.clear()
	_tick()
	_check(_said.is_empty(), "the pond is not offered at once by the door")
	fs.was_inside = true  # Back out of the Mughouse.
	_tick()
	_check(str(fs.offer.get("kind", "")) == "pond" and _said.size() == 1 and _in_deck(_said[0], "offer.pond", pet),
		"coming back out, she offers the pond (%s)" % [_said])
	_said.clear()
	_says("No thanks.")
	_check(_said.size() == 1 and _in_deck(_said[0], "no", pet) and not fs.chain_running() and fs.offer.is_empty()
		and not _main._guide_offers.has(pet.keeper_id), "a no: one no-line, and her chain ends (%s)" % [_said])
	_lull(pet, player)
	_said.clear()
	_tick()
	_check(_said.size() == 1 and _in_deck(_said[0], "chain_end", pet) and fs.end_told(), "at the next lull she says once they can ask her (%s)" % [_said])
	_lull(pet, player)
	_said.clear()
	_tick()
	_check(_said.is_empty(), "and only once")
	# A lapse: the Mughouse's offer unanswered passes to the pond.
	var lapsed := FirstSteps.new()
	lapsed.card = {"done": []}
	var keep := pet.first_steps
	pet.first_steps = lapsed
	lapsed.first_words_tick = World.tick - 1000
	_lull(pet, player)
	_tick()
	lapsed.offer["tick"] = World.tick - FirstSteps.ticks("lapse_s", 90) - 1
	_tick()
	_check(lapsed.next_step() == "pond" and lapsed.lapses == 1 and lapsed.offer.is_empty(), "an offer unanswered 90 s lapses: the Mughouse passed, the pond next (lapses %d)" % lapsed.lapses)
	# The catch: fish in the pack by the pond, to its taker by the pointer's rule.
	lapsed.card = {"done": ["mughouse", "pond"]}
	lapsed.pond = {"area": "wilds", "cell": player.tile}
	lapsed.lapses = 0
	_lull(pet, player)
	var slot := World.free_slot_for(player, "fish")
	var fish := World.items.mint("fish", "built")
	World.put_item(player, player, slot, fish)
	_said.clear()
	_tick()
	var taker: Dictionary = _main._first_taker(player)
	var catch_to: Dictionary = (_main._guide_offers.get(pet.keeper_id, {}) as Dictionary).get("to", {})
	_check(taker.is_empty() and lapsed.next_step() == "" or str(lapsed.offer.get("kind", "")) == "catch" and _said.size() == 1
		and _in_deck(_said[0], "offer.catch", pet) and str(taker.get("taker", "")) in _said[0] and catch_to.get("first") == "catch",
		"with fish in the pack she offers to take them to their taker, %s (%s)" % [taker.get("taker", "nobody"), _said])
	_check(not "store" in " ".join(_said).to_lower(), "she never says the store")
	World.consume(player, fish, "test")
	pet.first_steps = keep
	_main._guide_offers.erase(pet.keeper_id)


func _test_asked() -> void:
	print("\n== asked \"Where to?\": two true choices; naming the second takes it ==")
	var pet := _companion()
	var player := _player()
	var fs := pet.first_steps
	fs.add_no("pond")
	fs.add_no("pond")
	_lull(pet, player)
	_said.clear()
	_says("Where to?")
	var or_to: Dictionary = fs.offer.get("or", {})
	_check(_said.size() == 1 and _in_deck(_said[0], "asked", pet) and _said[0].left(1) == _said[0].left(1).to_upper() and not or_to.is_empty(),
		"her answer joins two choices, the first capitalised (%s)" % [_said])
	_check(fs.noes("pond") == 0, "asking clears the noes")
	var two: Array[String] = ["the Mughouse, for a fire and an ale", "the pond, to fish a while"]
	var joined: Array[String] = []
	var wrong: Array[String] = []
	for key: String in ["asked", "asked_one"]:
		for joiner: Variant in FirstSteps.lines(key, ""):
			var line := FirstSteps.joined(str(joiner), two)
			joined.append(line)
			var lead := str(joiner).get_slice("%s", 0)
			var right := line.left(1) == line.left(1).to_upper() and (lead.is_empty() and line.begins_with("The Mughouse")
				or not lead.is_empty() and line.begins_with(lead + "the Mughouse")) and not "Or The" in line
			if not right:
				wrong.append(line)
	_check(wrong.is_empty() and joined.any(func(line: String) -> bool: return line.begins_with("I'd say the Mughouse")),
		"each joiner capitalises the line, never a clause mid-line: \"I'd say the Mughouse\" (wrong: %s; %s)" % [wrong, joined])
	var first_to: Dictionary = (_main._guide_offers.get(pet.keeper_id, {}) as Dictionary).get("to", {})
	var second := str(or_to.get("first", ""))
	var word: String = FirstSteps.PLACE_WORDS.get(second, [""])[0]
	_says("The %s, then." % word)
	_check(pet.guide != null and pet.guide.goal.get("first") == second and first_to.get("first") != second,
		"\"the %s\" takes the second choice (%s, not %s)" % [word, pet.guide.goal.get("first") if pet.guide != null else "no walk", first_to.get("first")])
	_lull(pet, player)
	_says("What now?")
	var expect := str(fs.offer.get("kind", ""))
	_says("Yes.")
	var took: Variant = pet.guide.goal.get("first") if pet.guide != null else null
	_check(not expect.is_empty() and took == expect, "a yes takes the first (%s, offered %s)" % [took, expect])


func _test_unasked() -> void:
	print("\n== an unasked offer: nothing new for a while; its gap, a no's quiet, two noes ==")
	var pet := _companion()
	var player := _player()
	var fs := pet.first_steps
	_lull(pet, player)
	fs.offer = {}
	_main._guide_offers.erase(pet.keeper_id)
	fs.last_unasked_tick = -100000
	fs.quiet_until = -100000
	fs.unasked_ticks.clear()
	fs.lapses = 0
	fs.no_where.clear()
	fs.clear_noes()
	fs.last_new_tick = World.tick - FirstSteps.ticks("nothing_new_s", 240) - 10
	fs.cells_since_new = 100
	fs.known = _known(player)
	fs.zone = player.zone
	_said.clear()
	_tick()
	var kind := str(fs.offer.get("kind", ""))
	_check(not kind.is_empty() and _said.size() == 1 and _in_deck(_said[0], "go." + kind, pet) and fs.offer.get("unasked") == true,
		"nothing new for 4 minutes over 60 cells: one offer of a place (%s: %s)" % [kind, _said])
	_said.clear()
	_says("Not now.")
	_check(_said.size() == 1 and _in_deck(_said[0], "no", pet) and fs.quiet_until > World.tick and fs.noes(kind) == 1,
		"a no: her no-line, and quiet for 10 minutes")
	_lull(pet, player)
	_said.clear()
	_tick()
	_check(_said.is_empty(), "nothing in the quiet")
	fs.quiet_until = -100000
	fs.last_unasked_tick = -100000
	_lull(pet, player)
	_tick()
	var next := str(fs.offer.get("kind", ""))
	_check(not next.is_empty() and next != kind, "the kind said no to stays quiet in this zone and hour (next: %s, after %s)" % [next, kind])
	fs.offer = {}
	_main._guide_offers.erase(pet.keeper_id)
	_lull(pet, player)
	_said.clear()
	_tick()
	_check(_said.is_empty(), "and one more waits the gap (3 minutes)")
	fs.offer = {}
	_main._guide_offers.erase(pet.keeper_id)
	fs.add_no(kind)
	fs.no_where.clear()
	_check(not _main._first_may(fs, kind, player), "two noes to a kind: quiet for good, till asked")
	fs.clear_noes()
	_lull(pet, player)
	fs.lapses = 2
	fs.last_unasked_tick = -100000
	fs.lapse_tile = player.tile
	fs.lapse_spoke = pet._keeper_spoke_tick
	_said.clear()
	_tick()
	_check(_said.is_empty() and fs.lapses == 2, "two lapses in a row: none till they move or speak")
	_put(player, _main._nearest_free(player.tile + Vector2i(0, 6)))
	_tick()
	_check(fs.lapses == 0, "moving off clears them")
	fs.offer = {}
	_main._guide_offers.erase(pet.keeper_id)


func _known(player: Player) -> int:
	var record: PlayerRecord = _main._records.get(player.player_id)
	return record.known_areas.size() + record.known_places.size() + record.explored_places.size()


func _test_rising() -> void:
	print("\n== risen at the temple: her line, by the offering paid ==")
	var pet := _companion()
	var player := _player()
	_lull(pet, player)
	for paid: int in [3, 0]:
		_main._first_steps_rise[player.player_id] = {"kind": "temple", "paid": paid, "tick": World.tick}
		_said.clear()
		_tick()
		_check(_said.size() == 1 and _in_deck(_said[0], "risen.temple_paid" if paid > 0 else "risen.temple", pet),
			"an offering of %d: %s" % [paid, _said])
		_lull(pet, player)
	_main._first_steps_rise[player.player_id] = {"kind": "healers_hut", "paid": 0, "tick": World.tick}
	_said.clear()
	_tick()
	_check(_said.size() == 1 and _in_deck(_said[0], "risen.healer", pet) and not "offering" in _said[0], "at the healer's hut: those in his care (%s)" % [_said])


func _test_stray_and_fight() -> void:
	print("\n== her walk stepped off: one call, then resumed by her side; a fight: no line ==")
	var pet := _companion()
	var player := _player()
	var fs := pet.first_steps
	_lull(pet, player)
	var to: Dictionary = _main._first_dest("temple", pet, player, _main._record_of(pet))
	_main._start_guide(pet, player, to)
	_said.clear()
	pet._last_unasked_tick = -100000
	_main._guide_done(pet, "moved")
	_check(_said.size() == 1 and _in_deck(_said[0], "stray", pet) and not fs.stray.is_empty(), "her player's own step off: one call (%s)" % [_said])
	_said.clear()
	_tick()
	_check(_said.is_empty(), "no second call")
	fs.stray["tick"] = World.tick - World.TICK_RATE * 2
	_put(player, _main._nearest_free(pet.tile + Vector2i(0, 1)))
	_tick()
	_check(fs.stray.is_empty() and pet.guide != null and pet.guide.going(), "back by her side, the walk resumes")
	_said.clear()
	_main._guide_done(pet, "danger")
	_check(_said.is_empty() and pet.guide == null, "a fight starting mid-walk ends it with no line")
	_main._start_guide(pet, player, to)
	_main._guide_done(pet, "moved")
	fs.stray["tick"] = World.tick - FirstSteps.ticks("stray_wait_s", 20) - 1
	_put(player, _main._nearest_free(pet.tile + Vector2i(9, 0)))
	_said.clear()
	_tick()
	_check(fs.stray.is_empty() and _said.is_empty() and not _main._guides.has(pet.keeper_id), "not back in 20 s: dropped, quietly")


func _test_travel() -> void:
	print("
== into the Mughouse and back: her first steps live on; the travel ends her walk ==")
	var fs := _companion().first_steps
	fs.was_inside = false
	fs.quiet_until = World.tick + 1000
	fs.stray = {"goal": {"first": "mughouse", "key": "umbrage_tavern/tavern", "area": "wilds", "cell": Vector2i(181, 208)}, "tick": World.tick}
	fs.offer = {"kind": "pond", "tick": World.tick, "chain": "", "unasked": true}
	_main.travel(Net.local_id, "umbrage_tavern")
	var inside := _companion()
	_check(inside != null and inside.first_steps == fs and fs.stray.is_empty() and fs.offer.is_empty() and fs.quiet_until > World.tick,
		"inside, she is beside them with the same first steps, her walk's stray and offer ended, her quiet kept (%s)" % [World.zone.name])
	_tick()
	_check(fs.was_inside, "inside the Mughouse is noted")
	_main.travel(Net.local_id, "wilds")
	var out := _companion()
	_check(out != null and out.first_steps == fs and fs.was_inside, "back out in the wilds, still hers: \"came back out\" holds for the pond")
	if out != null:
		out.said.connect(func(line: String) -> void: _said.append(line))
	fs.quiet_until = -100000


func _test_log_lines() -> void:
	print("\n== her [firststeps] lines carry no name ==")
	var source := FileAccess.get_file_as_string("res://main.gd")
	var bad: Array[String] = []
	for line: String in source.split("\n"):
		if "\"[firststeps]" in line and ["_name_of", "player_id", "keeper_id", "_display_name", "record.name", "[\"name\"]"].any(
				func(word: String) -> bool: return word in line):
			bad.append(line.strip_edges())
	_check(bad.is_empty() and source.count("\"[firststeps]") >= 6, "place key, cell, tick and kind only (%s)" % [bad])


func _test_off() -> void:
	print("\n== off (the package not whole): none of it ==")
	var pet := _companion()
	var player := _player()
	FirstSteps.forced = 0
	_lull(pet, player)
	pet.first_steps.offer = {}
	_main._guide_offers.erase(pet.keeper_id)
	pet.first_steps.last_new_tick = -100000
	pet.first_steps.cells_since_new = 1000
	_said.clear()
	_tick()
	_check(_said.is_empty() and pet.first_steps.offer.is_empty(), "no offer")
	_check(not _main._first_steps_said(player, pet, "Where to?"), "\"Where to?\" is hers to answer as before")
	FirstSteps.forced = 1
