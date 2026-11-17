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
	_test_journal_mask()
	_test_guide_lore()
	_test_here()
	_test_ways()
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


## 279 amended (4): World._log's printed line puts each companion of the zone as
## her tag, by whole word; the line as written stays in last_log and recent_logs.
func _test_journal_mask() -> void:
	print("\n== the journal's World._log line: a companion as her tag, a whole word ==")
	var tags: Dictionary[String, String] = {"Ash": "#1", "Rhea": "#2", "Rhea2": "#3"}
	var pattern := World.mask_pattern(tags)
	_check(World.mask_line("push: Ash -> Crate1", tags, pattern) == "push: #1 -> Crate1", "her name as a whole word is her tag")
	var wolf := World.mask_line("hurt: Ashen Wolf loses 3 to Ash's blow", tags, pattern)
	_check(wolf == "hurt: Ashen Wolf loses 3 to #1's blow", "Ash never inside Ashen; Ash's is hers (%s)" % wolf)
	var two := World.mask_line("guard: Rhea takes Ash's blow (4, force 1.00) for 2 stamina", tags, pattern)
	_check(two == "guard: #2 takes #1's blow (4, force 1.00) for 2 stamina", "two companions in one line, each by her own tag (%s)" % two)
	_check(World.mask_line("push: Rhea2 -> Rhea", tags, pattern) == "push: #3 -> #2", "Rhea2 is hers, not Rhea's with a 2 left over")
	_check(World.mask_line("push: Player1 -> Crate1", tags, pattern) == "push: Player1 -> Crate1", "a line naming no companion is as written")
	var pet := _companion()
	if pet == null:
		_check(false, "a companion to mask")
		return
	var tag := Companion.tag(pet.keeper_id)
	var line := "push: %s -> Crate1 dir=(1, 0) tiles=1" % pet.name
	var before := World.logged
	World._log(line)
	_check(World.last_log == line and World.recent_logs.back() == line and World.logged == before + 1,
		"last_log and recent_logs keep the line as written (tests read them)")
	var printed := World.masked(line)
	_check(printed == "push: %s -> Crate1 dir=(1, 0) tiles=1" % tag and not String(pet.name) in printed,
		"the printed line: her node's name as her tag (%s)" % printed)
	if not pet.label.is_empty():
		_check(World.masked("downed: %s lies downed" % pet.label) == "downed: %s lies downed" % tag, "her label too")
	# The cost: a fight's worth of World._log lines, she in the zone and in half of them.
	var fight: Array[String] = []
	for i in 400:
		var who := String(pet.name) if i % 2 == 0 else "Robber%d" % i
		fight.append("hurt: %s loses %d to a robber's dagger (blow), hp %d/40" % [who, i % 7, 40 - i % 40])
		fight.append("guard: Robber%d takes %s's blow (%d, force 1.20) for 3 stamina" % [i, who, i % 5])
	var start := Time.get_ticks_usec()
	for each in fight:
		World.masked(each)
	var masked_us := float(Time.get_ticks_usec() - start) / fight.size()
	start = Time.get_ticks_usec()
	for each in fight:
		var _plain := "[tick %d] %s" % [World.tick, each]
	var plain_us := float(Time.get_ticks_usec() - start) / fight.size()
	print("  (the mask: %.1f us a line over %d lines, %.2f ms in all; the line's format alone %.1f us)" % [
		masked_us, fight.size(), masked_us * fight.size() / 1000.0, plain_us])
	_check(masked_us < 100.0, "a fight's lines through the mask cost under 100 us each (%.1f)" % masked_us)


## 945 amended (2): what lore puts in her hand. The tie in lore's file order (a stable sort), pinned
## at today's weights: no topic, the town ("Umbrage", the coordinator's (b)) and the wilds; where
## she stands as the screens name it; her guide's facts (Jeff's own words, each place's own entry);
## the guide tier in a newcomer's window and for a player lost, the share in town, a place found
## dropping out, an offer narrowing it, the town's curse in every combination, off with the package.
func _test_guide_lore() -> void:
	print("\n== her lore: lore's file order on a tie; the place she stands in; her guide's unfound places first (945 amended (2)) ==")
	var pet := _companion()
	var player := _player()
	if pet == null or player == null:
		_check(false, "(a player and their companion)")
		return
	var who := Companion._name_of(pet)
	# Pinned at today's weights, in lore's file order (Lore.FILES): change a weight or move a fact in
	# its file and this row says what moved; lore owns that order.
	var none := ["town.cursed", "town.curse_why", "town.in_region", "town.threat", "farmstead.where", "farmstead.abandoned", "the_land.deadly"]
	var town := ["town.cursed", "town.curse_why", "last_light.name", "town.name", "towerside.where", "hollowfell.barrow_gold", "crypt.mound",
		"town.in_region", "temple.in_town"]
	var wilds := ["farmstead.abandoned", "the_land.brought_back", "pond.river", "healers_hut.in_wilds", "deer.graze", "rabbit.graze", "boar.wilds",
		"wolf.hunt", "town.cursed", "temple.in_town", "the_land.deadly"]
	for knower: String in ["Wren", who]:
		var got_none := Companion.lore_words(knower)
		var got_town := Companion.lore_words(knower, PackedStringArray(), PackedStringArray(["Umbrage"]))
		var got_wilds := Companion.lore_words(knower, PackedStringArray(), PackedStringArray(["The Wilds"]))
		_check(got_none == _lore_said(knower, none) and Companion.lore_words(knower) == got_none,
			"%s, no topic: the curse group, then the farmstead and the land, in lore's file order, the same each time (%s)" % [knower, got_none])
		_check(got_town == _lore_said(knower, town), "%s in the town: the curse and its why first, the Mughouse by name (%s)" % [knower, got_town])
		_check(got_wilds == _lore_said(knower, wilds), "%s in the wilds: the wilds' facts first, the curse after (%s)" % [knower, got_wilds])
	# Where she stands, as the screens name it.
	var record: PlayerRecord = _main._records.get(Net.player_id)
	_lull(pet, player)
	var square := player.tile
	var out_there: Vector2i = _main._nearest_free(Vector2i(150, 214))
	_check(pet.place_topics() == PackedStringArray(["Umbrage"]) and pet.stands_in_town(), "on the square: \"Umbrage\", a town (%s)" % [pet.place_topics()])
	_put(player, out_there)
	_check(pet.place_topics() == PackedStringArray(["The Wilds"]) and not pet.stands_in_town(), "out at %s: the level's own name, \"The Wilds\", no town (%s)" % [out_there, pet.place_topics()])
	_put(player, square)
	_check(Companion.where_in("umbrage_tavern", Vector2i(2, 2)) == "Umbrage", "inside the Mughouse: its town, \"Umbrage\" (%s)" % Companion.where_in("umbrage_tavern", Vector2i(2, 2)))
	# Her guide's facts: Jeff's own words, each place's own entry; none of the game's, no rumour, no secret.
	var facts := Companion.guide_facts(who, FirstSteps.PLACES)
	var ids := facts.map(func(fact: Dictionary) -> String: return str(fact["id"]))
	_check(ids == ["last_light.name", "healers_hut.in_wilds", "medicine_man.brings_back", "the_land.brought_back", "temple.in_town",
			"temple.charm_blessed", "temple.offering", "priest.brings_back", "old_mound.outside_town", "old_mound.spears"],
		"her guide's facts, in her places' order, are lore's table's Jeff's-words lines (%s)" % [ids])
	_check(facts.all(func(fact: Dictionary) -> bool: return fact["source"] == "Jeff" and not fact["hearsay"] and not fact["secret"] and not fact["memory"]),
		"each common and in Jeff's own words")
	var temple: Array[String] = ["temple"]
	var pond: Array[String] = ["pond"]
	var temple_ids := Companion.guide_facts(who, temple).map(func(fact: Dictionary) -> String: return str(fact["id"]))
	var says_temple := Lore.known_by(Companion.lore_knower(who), PackedStringArray(["temple"])).map(func(fact: Dictionary) -> String: return str(fact["id"]))
	_check("crypt.mound" in says_temple and "crypt.mound" not in temple_ids and "theus.followed" not in temple_ids,
		"a fact of Jeff's that says \"temple\" but is the crypt's (crypt.mound) stays out of the temple's (%s)" % [temple_ids])
	_check(Companion.guide_facts(who, pond).is_empty(), "the pond gives none: its facts are the game's")
	# The town's curse in every combination of unfound places, guiding (no share) or in town (the share).
	var lost_curse: Array[String] = []
	var cursed := _lore_said(who, ["town.cursed"]).trim_prefix("What you know of the world: ")
	for mask in 32:
		var some: Array[String] = []
		for i in FirstSteps.PLACES.size():
			if mask & (1 << i):
				some.append(FirstSteps.PLACES[i])
		for share: int in [0, int(FirstSteps.guide_rules().get("share", 0))]:
			if cursed not in Companion.lore_words(who, PackedStringArray(), PackedStringArray(["Umbrage"]), some, share):
				lost_curse.append("%s/%d" % [some, share])
	_check(lost_curse.is_empty() and not cursed.is_empty(), "in the town, \"%s\" stays in her hand under every set of places, share or none (lost in %s)" % [cursed, lost_curse])
	var share_words := Companion.lore_words(who, PackedStringArray(), PackedStringArray(["Umbrage"]), FirstSteps.PLACES, 200)
	_check(_lore_said(who, ["town.curse_why"]).trim_prefix("What you know of the world: ") in share_words,
		"and with the share, its why too (%s)" % share_words)
	# Main's side: the window, found, an offer, lost, the town's share, out of town, off.
	var fs := pet.first_steps
	var card_was := fs.card.duplicate(true)
	var known_was := record.known_places.duplicate()
	var explored_was := record.explored_places.duplicate()
	var areas_was := record.known_areas.duplicate()
	fs.card = {"done": ["mughouse", "pond", "catch"], "ended": true, "days": {}}
	record.known_places.clear()
	record.explored_places.clear()
	record.known_areas.assign(["wilds"])
	fs.quiet_until = World.tick + 100000  # No offer of hers meanwhile.
	fs.offer = {}
	_main._guide_offers.erase(pet.keeper_id)
	fs.first_words_tick = World.tick
	fs.lost_at = -1
	fs.last_new_tick = World.tick
	fs.cells_since_new = 0
	_guide_tick(pet)
	var first := pet.guide_places.duplicate()
	_check(not first.is_empty() and pet.guide_share == 0 and first.all(func(kind: String) -> bool: return kind in FirstSteps.PLACES),
		"in a newcomer's first minutes: the places not found, no share (%s, %d)" % [first, pet.guide_share])
	var words := Companion.lore_words(who, PackedStringArray(), pet.place_topics(), pet.guide_places, pet.guide_share)
	var lead := Companion.guide_facts(who, pet.guide_places)
	_check(not lead.is_empty() and words.begins_with("What you know of the world: " + Hearsay.said_of(lead[0])) and words in pet.voice_prompt("test")
		and cursed in words, "her lore leads with the nearest one's, keeps the curse, and her voice is told it (%s)" % words)
	var found := str(first[0]) if not first.is_empty() else ""
	var dest: Dictionary = _main._first_dest(found, pet, player, record) if not found.is_empty() else {}
	record.known_places.append(str(dest.get("key", "")))
	_guide_tick(pet)
	_check(not found.is_empty() and found not in pet.guide_places, "the nearest, %s, found (in their record): out of her set (%s)" % [found, pet.guide_places])
	fs.offer = {"kind": "temple", "tick": World.tick}
	_guide_tick(pet)
	_check(pet.guide_places.size() == 1 and pet.guide_places[0] == "temple", "an offer of hers standing: its place alone (%s)" % [pet.guide_places])
	fs.offer = {}
	fs.first_words_tick = World.tick - 100000
	_guide_tick(pet)
	_check(pet.guide_share == int(FirstSteps.guide_rules().get("share", 0)) and pet.guide_share > 0 and not pet.guide_places.is_empty(),
		"past the window, in the town: the share (%d, %s)" % [pet.guide_share, pet.guide_places])
	fs.last_new_tick = -100000
	fs.cells_since_new = 1000
	pet._keeper_spoke_tick = -100000
	_guide_tick(pet)
	_check(fs.lost_at >= 0 and pet.guide_share == 0 and not pet.guide_places.is_empty(), "nothing new for a while and quiet: lost, the places first (%s)" % [pet.guide_places])
	World.step()
	pet._keeper_spoke_tick = World.tick
	_guide_tick(pet)
	_check(fs.lost_at < 0 and pet.guide_share > 0, "they speak to her: lost no more, the town's share again")
	_put(player, out_there)
	_guide_tick(pet)
	_check(pet.guide_places.is_empty(), "out of the town, neither new nor lost: none (%s)" % [pet.guide_places])
	_put(player, square)
	FirstSteps.forced = 0
	_guide_tick(pet)
	_check(pet.guide_places.is_empty(), "off: none (%s)" % [pet.guide_places])
	FirstSteps.forced = 1
	fs.card = card_was
	record.known_places.assign(known_was)
	record.explored_places.assign(explored_was)
	record.known_areas.assign(areas_was)
	fs.quiet_until = -100000
	fs.lost_at = -1
	fs.last_new_tick = World.tick
	fs.cells_since_new = 0
	pet.guide_places = []
	pet.guide_share = 0


func _test_here() -> void:
	print("\n== where she stands, one line first in her Now: (945 amended (2), the coordinator's design word) ==")
	var pet := _companion()
	var player := _player()
	if pet == null or player == null:
		_check(false, "(a player and their companion)")
		return
	var record: PlayerRecord = _main._records.get(Net.player_id)
	var known_was := record.known_places.duplicate()
	var explored_was := record.explored_places.duplicate()
	record.known_places.clear()
	record.explored_places.clear()
	var none := func(_id: String) -> bool: return false
	# In the town's bounds.
	_lull(pet, player)
	_put(pet, _main._nearest_free(Vector2i(196, 214)))
	var square := pet.here_words()
	_check(square == "You are in Umbrage." or square.begins_with("You are in Umbrage, by "), "in the square: the town by its name (%s)" % square)
	var prompt := pet.voice_prompt("test")
	_check(("Now: " + square) in prompt and " There is a town here, and you are in it." in prompt,
		"first in her Now:, and her world says she is in the town")
	_check(pet.place_brief("wilds")["text"].begins_with("You are in Umbrage."), "asked of the place, its head is the town, not the Wilds (%s)" % pet.place_brief("wilds")["text"])
	var who := pet.keeper_name()
	pet._exchange.append({"role": "user", "text": "Where are we?", "speaker": who})
	var where_turn := str(pet.voice_messages(true, "%s: Where are we?" % who).back()["content"])
	pet._exchange.pop_back()
	_check(where_turn.ends_with("%s: Where are we?\n[%s %s]" % [who, square, Companion.WHERE_LEAD]) and "What do you make of" not in where_turn,
		"\"Where are we?\": their own line, then where she stands and to say it by name, never the place ask on one thing (%s)" % where_turn.right(200))
	pet._exchange.append({"role": "user", "text": "What do you think of this place?", "speaker": who})
	var place_turn := str(pet.voice_messages(true, "%s: What do you think of this place?" % who).back()["content"])
	pet._exchange.pop_back()
	_check(Companion.WHERE_LEAD not in place_turn, "asked what they think of it: the place ask as before (%s)" % place_turn.right(160))
	var temple := Vector2i(189, 201)
	var by_temple := Vector2i(-1, -1)
	for d in range(1, Companion.HERE_BY):
		for at: Vector2i in [temple + Vector2i(0, d), temple + Vector2i(d, 0), temple + Vector2i(0, -d), temple + Vector2i(-d, 0)]:
			if by_temple.x < 0 and Companion._zone_buildings.get("wilds", {}).get(at, {}).is_empty() and World.is_walkable(at):
				by_temple = at
	_check(by_temple.x >= 0 and Companion.here_in("wilds", by_temple, none) == "You are in Umbrage, by the temple.",
		"beside the temple: by it, named though not found (he stands beside it) (%s: %s)" % [by_temple, Companion.here_in("wilds", by_temple, none)])
	var in_temple := Vector2i(-1, -1)
	for cell: Vector2i in Companion._zone_buildings.get("wilds", {}):
		if str(Companion._zone_buildings["wilds"][cell].get("use", "")) == "temple" 				and (in_temple.x < 0 or World.distance(cell, temple) < World.distance(in_temple, temple)):
			in_temple = cell  # Umbrage's temple (a building of blocks, its use "temple"), by its place's cell.
	_check(in_temple.x >= 0 and Companion.here_in("wilds", in_temple, none) == "You are in Umbrage, inside the temple.",
		"inside the temple: inside it (%s)" % Companion.here_in("wilds", in_temple, none))
	_check("crypt stair" not in Companion.here_in("wilds", Vector2i(199, 200), none), "the crypt stair is no kind of hers: never her by-place (%s)" % Companion.here_in("wilds", Vector2i(199, 200), none))
	# Away from the town: the town always; another place only when found.
	var hut_near := Vector2i(152, 226)
	var unfound := Companion.here_in("wilds", hut_near, none)
	_check(unfound == "You are in the Wilds; Umbrage lies a short walk to the east.", "by the healer's hut not yet found: the Wilds, and the town (%s)" % unfound)
	var hut_found := func(id: String) -> bool: return id == "wilds/healers_hut@152,232"
	var found := Companion.here_in("wilds", hut_near, hut_found)
	_check(found == "You are in the Wilds; the healer's hut lies close by.", "found by their record: the hut, nearer, close by and no way said (%s)" % found)
	_check(" lies " in Companion.here_in("wilds", Vector2i(150, 150), none) and "a fair walk" in Companion.here_in("wilds", Vector2i(150, 150), none)
		and Companion.here_in("wilds", Vector2i(20, 20), none).ends_with("lies a long walk to the south-east."),
		"farther off, in words, never a number (%s / %s)" % [Companion.here_in("wilds", Vector2i(150, 150), none), Companion.here_in("wilds", Vector2i(20, 20), none)])
	_put(pet, _main._nearest_free(hut_near))
	var live := pet.here_words()
	_check(live.begins_with("You are in the Wilds; Umbrage lies "), "her own line out there, the record read through Main: the town (%s)" % live)
	record.known_places.append("wilds/healers_hut@152,232")
	_check(pet.here_words().begins_with("You are in the Wilds; the healer's hut lies "), "and once their record holds the hut, the hut (%s)" % pet.here_words())
	# A level with no town: its own name, no place from another.
	_check(Companion.here_in("barrow", Vector2i(30, 5), none) == "You are in the First Hall, in the Crypt of the Fallen."
		and Companion.here_in("barrow", Vector2i(2, 30), none) == "You are in the Crypt of the Fallen.",
		"in the crypt: the room the screens name and the level, else the level (%s / %s)" % [Companion.here_in("barrow", Vector2i(30, 5), none), Companion.here_in("barrow", Vector2i(2, 30), none)])
	_check(Companion.here_in("umbrage_tavern", Vector2i(2, 2), none) == "You are in the Last Light Mughouse, in Umbrage.",
		"in the Mughouse: its own name and its town (%s)" % Companion.here_in("umbrage_tavern", Vector2i(2, 2), none))
	_check(Companion.here_in("hills", Vector2i(20, 20), none) == "You are in the Hills.", "in the hills: their name alone (%s)" % Companion.here_in("hills", Vector2i(20, 20), none))
	record.known_places.assign(known_was)
	record.explored_places.assign(explored_was)
	_lull(pet, player)


func _test_ways() -> void:
	print("\n== where to go: true ways, the hut's once found (945 amended (2), the coordinator's design on transcript 3) ==")
	var pet := _companion()
	var player := _player()
	if pet == null or player == null:
		_check(false, "(a player and their companion)")
		return
	var record: PlayerRecord = _main._records.get(Net.player_id)
	var known_was := record.known_places.duplicate()
	var explored_was := record.explored_places.duplicate()
	record.known_places.clear()
	record.explored_places.clear()
	var none := func(_id: String) -> bool: return false
	var hut_found := func(id: String) -> bool: return id == "wilds/healers_hut@152,232"
	var square: Vector2i = _main._nearest_free(Vector2i(196, 214))
	var doors: Array = Companion._where_level("wilds").get("doors", [])
	var mughouse: Vector2i = doors[0]["at"] if not doors.is_empty() else Vector2i(-1, -1)
	_check(doors.size() == 1 and str(doors[0]["inside"]) == "umbrage_tavern", "the wilds' one building with a level inside: the Mughouse (%s)" % [doors])
	var way := func(name: String, at: Vector2i, from: Vector2i) -> String:
		var far := maxi(absi(at.x - from.x), absi(at.y - from.y))
		return "%s lies %s to the %s." % [name, Companion.here_far(far), World.compass(Vector2(at - from))]
	var temple_way: String = way.call("The temple", Vector2i(189, 201), square)
	var store_way: String = way.call("The town's store", Vector2i(192, 195), square)
	var mug_way: String = way.call("The Last Light Mughouse", mughouse, square)
	var ways := Companion.ways_in("wilds", square, none, "Where should we go?")
	_check(ways.size() == 3 and temple_way in ways and store_way in ways and mug_way in ways,
		"in the square, where to go: the temple, the store and the Mughouse, each its true way (%s)" % [ways])
	var fars: Array[int] = []
	for at: Vector2i in [Vector2i(189, 201), Vector2i(192, 195), mughouse]:
		fars.append(maxi(absi(at.x - square.x), absi(at.y - square.y)))
	var order := [temple_way, store_way, mug_way]
	var sorted_order := [0, 1, 2]
	sorted_order.sort_custom(func(a: int, b: int) -> bool: return fars[a] < fars[b])
	_check(ways == [order[sorted_order[0]], order[sorted_order[1]], order[sorted_order[2]]], "nearest first (%s)" % [fars])
	_check(not ways.any(func(line: String) -> bool: return "hut" in line or "stall" in line or "post" in line or "fire" in line or "crypt" in line),
		"no stall, post, fire or crypt stair, and no hut not found")
	_check(Companion.ways_in("wilds", square, none, "Where is the temple?") == [temple_way], "\"Where is the temple?\": its way alone")
	_check(Companion.ways_in("wilds", square, none, "Where's the inn?") == [mug_way], "\"Where's the inn?\": a kind word finds the Mughouse")
	_check(Companion.ways_in("wilds", square, none, "How do I get to the Mughouse?") == [mug_way], "by the name folk call it")
	_check(Companion.ways_in("wilds", square, none, "Where can I buy a sword?") == [store_way], "\"buy\": the town's store")
	var kinds := {"Where should we go?": "go", "Which way?": "go", "Where can I buy bread?": "buy", "Where can we trade?": "buy",
		"Where is the blacksmith?": "none", "Where can I find a boat?": "none", "Where can I get bread?": "none",
		"Where's the inn?": "named", "Where is the healer's hut?": "named", "Where is the woodlot?": "named"}
	var kinds_wrong: Array[String] = []
	for asked: String in kinds:
		if Companion.way_kind("wilds", square, asked) != kinds[asked]:
			kinds_wrong.append("%s -> %s" % [asked, Companion.way_kind("wilds", square, asked)])
	_check(kinds_wrong.is_empty(), "what a where-question asks: to go, to buy, a place of the level, nothing she has (%s)" % [kinds_wrong])
	# The store's shelf as it stands (the coordinator's ruling on transcript 6): bare, gear without food, food first.
	var town := ""
	var wilds_places: Dictionary = Level.load_level("wilds").get("places", {})
	for key: Variant in wilds_places:
		if str(wilds_places[key].get("kind", "")) == "stockpile" and wilds_places[key].get("cell") == Vector2i(192, 195):
			town = "wilds/%s" % key
	var stock: Stockpile = World.economy.stockpile
	var shelf_was := stock.shop(town)
	var makers_was := shelf_was.map(func(uid: int) -> String: return stock.maker_of(town, uid))
	for uid: int in shelf_was:
		stock.take_from_shop(town, uid, "test")
	var reads_before := Level.loads.duplicate()
	var bare := Companion.store_words("wilds", square)
	_check(not town.is_empty() and bare == store_way.trim_suffix(".") + "; its shelf is bare just now.",
		"to buy, the shelf bare: the town's store, its way, and its shelf bare (%s; %s)" % [town, bare])
	var minted: Array[int] = []
	for id: String in ["sword", "bandaging_kit", "bandaging_kit"]:
		minted.append(stock.book.mint(id, "made", "test"))
		stock.stock_shop(town, minted.back(), "test", "")
	var gear := Companion.store_words("wilds", square)
	_check(gear == store_way.trim_suffix(".") + "; on its shelf now: 2 bandaging kits and a sword, and nothing else; no food today.",
		"gear and no food: what is on it, the most first, closed, and no food today (%s)" % gear)
	for id: String in ["roast", "cooked_fish", "cooked_fish"]:
		minted.append(stock.book.mint(id, "made", "test"))
		stock.stock_shop(town, minted.back(), "test", "")
	var store_line := Companion.store_words("wilds", square)
	_check(store_line == store_way.trim_suffix(".") + "; on its shelf now: 2 roast perch, some roast meat, 2 bandaging kits and a sword, and nothing else.",
		"with food: the food first, then the rest, some roast meat, closed (%s)" % store_line)
	_check(Companion.store_words("wilds", square, "Player: Where can I buy bread?") == store_line.trim_suffix(".") + "; it has no bread."
		and Companion.store_words("wilds", square, "Player: Where can I buy a sword?") == store_line,
		"asked for bread: the shelf ends \"it has no bread\"; asked for a sword, no bread said (%s)" % Companion.store_words("wilds", square, "Where can I buy bread?"))
	for id: String in ["dagger", "shield", "ration", "herbs"]:
		minted.append(stock.book.mint(id, "made", "test"))
		stock.stock_shop(town, minted.back(), "test", "")
	var many := Companion.shelf_words(town)
	_check(many.ends_with(", and more besides, but no bread") and many.count(",") >= Companion.SHELF_MOST - 1,
		"more kinds than SHELF_MOST: the first of them, more besides but no bread (%s)" % many)
	_check("a bunch of herbs" in many and not "some bunch" in many and Companion._shelf_plural("herbs", "bunch of herbs") == "bunches of herbs"
			and Companion._shelf_plural("wine", "flask of wine") == "flasks of wine" and Companion._shelf_plural("cooked_fish", "roast perch") == "roast perch"
			and Companion._shelf_plural("bandaging_kit", "bandaging kit") == "bandaging kits",
		"a name with its own measure is counted by it: \"a bunch of herbs\", \"2 flasks of wine\", never \"some bunch\" (%s)" % many)
	World.towns.raise_threat(town, "wolves", "test")
	var shut := Companion.shelf_words(town)
	World.towns.release_threat(town, "test")
	(World.towns._towns[town] as Dictionary).erase("threat")
	_check(shut == Companion.SHELF_SHUT and Companion.shelf_words(town) == many,
		"the town threatened: the store shut (economy: no sale then), its shelf again once the threat is gone (%s)" % shut)
	_check(Companion.shelf_words(town, true).ends_with(", and more besides, but it has no bread"),
		"asked for bread, more besides: \"but it has no bread\" (%s)" % Companion.shelf_words(town, true))
	# The tripwire (the coordinator's ruling, from economy's record: the game has no bread item, recipe
	# or baker): her Now says "it has no bread" because none exists; the day one lands, this fails.
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://levels/items.json"))
	var breads := []
	for entry: Variant in (catalog.get("items", []) if catalog is Dictionary else []):
		if entry is Dictionary and ("bread" in str(entry.get("id", "")).to_lower() or "bread" in str(entry.get("name", "")).to_lower()):
			breads.append(str(entry.get("id", "")))
	_check(catalog is Dictionary and breads.is_empty(),
		"no bread in levels/items.json, so her Now's \"it has no bread\" (Companion.SHELF_NO_BREAD, sim/companion.gd) is true: a bread item now (%s) makes it false; ask voice and economy for its new words" % [breads])
	_check(Level.loads == reads_before, "the shelf read from memory: no level read (%s -> %s)" % [reads_before, Level.loads])
	var from_wilds := Companion.store_words("wilds", Vector2i(152, 226))
	_check(from_wilds == str(way.call("The town's store", Vector2i(192, 195), Vector2i(152, 226))).trim_suffix(".") + "; " + many + ".",
		"from the wilds too, its true way, its shelf the same (%s)" % from_wilds)
	for uid: int in minted:
		stock.take_from_shop(town, uid, "test")
	stock.stock_shop(town, minted[1], "test", "")
	stock.stock_shop(town, minted[3], "test", "")
	store_line = Companion.store_words("wilds", square, "Where can I buy bread?")  # The live bread turn below: a kit and a roast on the shelf.
	_check(Companion.ways_in("wilds", square, none, "Where is the healer's hut?").is_empty(), "the hut not found: no way to it, not even another place's")
	var hut_from_square := Companion.ways_in("wilds", square, hut_found, "Where is the healer's hut?")
	_check(hut_from_square == [way.call("The healer's hut", Vector2i(152, 232), square)], "found: its true way (%s)" % [hut_from_square])
	var by_temple := Companion.ways_in("wilds", Vector2i(191, 203), none, "Where is the temple?")
	_check(by_temple == ["The temple lies close by."], "close by: no way said (%s)" % [by_temple])
	# Out in the wilds: the town, and a found place.
	var hut_near := Vector2i(152, 226)
	_check(Companion.ways_in("wilds", hut_near, none, "Where should we go?") == ["Umbrage lies a short walk to the east."],
		"in the wilds, the hut not found: the town alone (%s)" % [Companion.ways_in("wilds", hut_near, none, "Where should we go?")])
	_check(Companion.ways_in("wilds", hut_near, hut_found, "Where should we go?") == ["The healer's hut lies close by.", "Umbrage lies a short walk to the east."],
		"found: the hut first, nearer (%s)" % [Companion.ways_in("wilds", hut_near, hut_found, "Where should we go?")])
	_check(Companion.ways_in("barrow", Vector2i(30, 5), none, "Where should we go?").is_empty(), "in the crypt: no ways (no town in its level)")
	# Her turn.
	_lull(pet, player)
	_put(pet, square)
	var who := pet.keeper_name()
	var here := pet.here_words()
	pet._exchange.append({"role": "user", "text": "Where should we go?", "speaker": who})
	var messages := pet.voice_messages(true, "%s: Where should we go?" % who)
	pet._exchange.pop_back()
	var turn := str(messages.back()["content"])
	var system := str(messages[0]["content"])
	var live_ways := Companion.ways_in("wilds", square, none, "Where should we go?")
	_check(turn.ends_with("%s: Where should we go?\n[%s %s %s]" % [who, here, " ".join(live_ways), Companion.WAY_LEAD]),
		"\"Where should we go?\": their line, then where she stands, the ways and the lead (%s)" % turn.right(400))
	var now := system.get_slice("Now: ", 1).get_slice("\n\n", 0)
	_check(not Companion.has_compass(now), "her Now gives no other compass word: her player told by how far alone (%s)" % now.left(300))
	_check(Companion.VOICE_COMPASS in system, "the primer's compass sentence kept: her ways give one")
	pet._exchange.append({"role": "user", "text": "Where can I buy bread?", "speaker": who})
	var bread := pet.voice_messages(true, "%s: Where can I buy bread?" % who)
	pet._exchange.pop_back()
	var bread_now := str(bread[0]["content"]).get_slice("Now: ", 1).get_slice("

", 0)
	_check(str(bread.back()["content"]).ends_with("[%s %s]" % [here, Companion.BUY_LEAD]) and bread_now.begins_with(here + " " + store_line)
		and Companion.VOICE_COMPASS in str(bread[0]["content"]),
		"to buy bread: the store and its way after where she stands in her Now, the buying lead, never what it has (%s)" % bread_now.left(240))
	pet._exchange.append({"role": "user", "text": "Where is the blacksmith?", "speaker": who})
	var smith := pet.voice_messages(true, "%s: Where is the blacksmith?" % who)
	pet._exchange.pop_back()
	_check(str(smith.back()["content"]).ends_with("[%s %s]" % [here, Companion.WAY_NONE]) and Companion.VOICE_COMPASS not in str(smith[0]["content"]),
		"a place she has nothing of: she knows of no such place here, no way, no compass sentence")
	# Out by the hut, found: the here line's way is not given again in the ways (voice's read).
	record.known_places.append("wilds/healers_hut@152,232")
	_put(pet, _main._nearest_free(Vector2i(152, 226)))
	var out_here := pet.here_words()
	pet._exchange.append({"role": "user", "text": "Where should we go?", "speaker": who})
	var out_turn := str(pet.voice_messages(true, "%s: Where should we go?" % who).back()["content"])
	pet._exchange.pop_back()
	_check(out_turn.to_lower().count("healer's hut lies close by") == 1 and out_turn.contains(out_here),
		"by the found hut: its way said once, in where she stands (%s)" % out_turn.right(300))
	record.known_places.clear()
	_put(pet, square)
	var plain := str(pet.voice_messages(true, "%s: Nice day." % who)[0]["content"])
	_check(not Companion.has_compass(plain.get_slice("Now: ", 1).get_slice("\n\n", 0)) or Companion.VOICE_COMPASS in plain,
		"any other turn: the compass sentence kept when her Now gives a way (her player's, as before)")
	# No level read in her turn (perf's find: here_name read it from disk each call, 343 ms at her first words;
	# Level.loads, 853 amended (21), counted, never timed). The crypt's and the Mughouse's kept by the rows above.
	var before := Level.loads.duplicate()
	pet._exchange.append({"role": "user", "text": "Where should we go?", "speaker": who})
	pet.voice_messages(true, "%s: Where should we go?" % who)
	pet._exchange.pop_back()
	pet.voice_messages(true, "%s: Nice day." % who)
	var greeting := Companion.FIRST_WORDS % pet.here_name()
	Companion.here_in("barrow", Vector2i(30, 5), none)
	Companion.ways_in("barrow", Vector2i(30, 5), none, "Where should we go?")
	Companion.here_in("umbrage_tavern", Vector2i(2, 2), none)
	var read: Array[String] = []
	for level_name: String in Level.loads:
		if int(Level.loads[level_name]) > int(before.get(level_name, 0)):
			read.append(level_name)
	_check(read.is_empty() and "Umbrage" in greeting,
		"her turns in the wilds, her first words' place, the crypt's and the Mughouse's lines: no level read (%s; %s)" % [read, greeting])
	record.known_places.assign(known_was)
	record.explored_places.assign(explored_was)
	stock.take_from_shop(town, minted[1], "test")
	stock.take_from_shop(town, minted[3], "test")
	for i in shelf_was.size():
		stock.stock_shop(town, shelf_was[i], "test", str(makers_was[i]))  # The town's shelf as it was.
	_lull(pet, player)


## Main's first steps' second, her guide's places worked out afresh.
func _guide_tick(pet: Companion) -> void:
	pet.first_steps.guide_at = -100000
	_tick()


## [param ids] as lore_words says them for [param who], in that order.
func _lore_said(who: String, ids: Array) -> String:
	var by_id := {}
	for fact in Lore.known_by(Companion.lore_knower(who)):
		by_id[str(fact["id"])] = fact
	var said: Array[String] = []
	for id: String in ids:
		if by_id.has(id):
			said.append(Hearsay.said_of(by_id[id]))
	return "What you know of the world: %s" % " ".join(said)


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
