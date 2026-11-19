extends "res://tests/first_steps_test_base.gd"
## Her first steps played through World.step (decision 945): run A replayed (the chain's
## Mughouse, a yes, its door, in and out by the link, the pond, the catch's taker, her end
## told, then 300 s over known ground), and the rod step (945 amended (4)): a player with no
## rod led to Rolf's stall before the pond, at night told once that it opens in the morning,
## a lapse offered once more, and asked "Where to?" the stall in the pond's place. Split from
## first_steps_test (the coordinator, 11-18), whose other rows it leaves there; the shared part
## is tests/first_steps_test_base.gd. Prints PASS/FAIL per assertion and quits with exit code 1
## if any assertion failed, 0 otherwise.


func _ready() -> void:
	var ports := preload("res://tests/test_ports.gd")
	Net.port = ports.of(18011)
	await _setup(ports.scratch("first_steps_walk_world.json"), ports.scratch("first_steps_walk_overlay/"))
	_test_run_a()
	_test_no_rod()
	_test_rod_night()
	_test_rod_lapse()
	_test_rod_asked()
	_finish()


func _hear() -> void:
	var pet := _companion()
	if pet != null:
		pet.said.connect(func(line: String) -> void: _said.append(line))


## Run A as ui-design's look played it (guidea6, the coordinator's row): a new record's card, her chain
## through the server's own ticks: the Mughouse offered and taken, its door, in and out by the link, the
## pond, the catch's taker, her end told, then nothing new for 240 s over 60 cells. No offer after the visit
## names the Mughouse as unseen. In play the wilds' clock ran ahead of the Mughouse's (World.tick is each
## zone's own), and her second's tick, held on the zone's clock, never ran inside.
func _test_run_a() -> void:
	print("\n== run A through the server's ticks: the Mughouse visited, never offered as unseen after ==")
	var pet := _companion()
	var player := _player()
	var record: PlayerRecord = _main._record_of(pet) if pet != null else null
	if pet == null or player == null or record == null:
		_check(false, "(a player and their companion)")
		return
	var keep := pet.first_steps
	var lists := [record.known_places, record.explored_places, record.known_areas]
	var lists_was := lists.map(func(each: Array) -> Array: return each.duplicate())
	for kind: String in ["mughouse", "pond"]:
		var key := str(_main._first_dest(kind, pet, player, record).get("key", ""))
		for each: Array in lists:
			each.erase(key)  # A newcomer's: neither known nor found.
	keep.offer = {}
	_main._guide_offers.erase(pet.keeper_id)
	# The wilds' clock ahead of the Mughouse's, as in the look (in at t557 there, out at its t67).
	var tavern: Variant = World.zones.get("umbrage_tavern")
	var tavern_tick: int = (tavern as Zone).tick if tavern is Zone else 0
	if World.tick < tavern_tick + 300:
		_play(float(tavern_tick + 300 - World.tick) / World.TICK_RATE)
	var fresh := FirstSteps.new()
	record.companion["first_steps"] = {"done": []}
	fresh.card = record.companion["first_steps"]
	_main._first_steps_live[record.player_id] = fresh
	pet.first_steps = fresh
	pet.first_words = false
	_lull(pet, player)
	fresh.fought = -100000
	_said.clear()
	var offered := _play(30, func() -> bool: return str(fresh.offer.get("kind", "")) == "mughouse")
	var heard := str(_said[-1]) if not _said.is_empty() else ""
	_check(offered and _in_deck(heard, "offer.mughouse", pet), "her chain's Mughouse offer, on the server's own second (%s; %s)" % [_said, _why(pet, player)])
	if not offered:
		_restore_run_a(keep, record, lists, lists_was)
		return
	_press_y(pet, heard)
	pet._last_unasked_tick = -100000
	_led("chain", "mughouse")
	_main.travel(Net.local_id, "umbrage_tavern")
	_hear()
	_play(7)
	var day := Townsfolk.day_of(World.steps)
	_check(fresh.reached_today("mughouse", day) and fresh.was_inside,
		"inside, on its own clock, her second's tick runs: the Mughouse reached today, \"came back out\" to come (days %s, in %s, its tick %d, hers at %d)" % [
			fresh.card.get("days", {}), World.zone.name, World.tick, _main._first_steps_at])
	_main.travel(Net.local_id, "wilds")
	_hear()
	pet = _companion()
	player = _player()
	_said.clear()
	var pond := _play(60, func() -> bool: return str(fresh.offer.get("kind", "")) == "pond")
	if pond:
		_press_y(_companion(), str(_said[-1]) if not _said.is_empty() else "")
		_led("chain", "pond")
	var slot := World.free_slot_for(player, "fish")
	var fish := World.items.mint("fish", "built")
	World.put_item(player, player, slot, fish)
	if _play(30, func() -> bool: return str(fresh.offer.get("kind", "")) == "catch" or fresh.next_step() == ""):
		if str(fresh.offer.get("kind", "")) == "catch":
			_press_y(_companion(), str(_said[-1]) if not _said.is_empty() else "")
			_led("chain", "catch")
	World.consume(player, fish, "test")
	var told := _play(120, func() -> bool: return fresh.end_told(), true)  # Walked back from the stall, as run A did.
	_check(pond and told, "out again: the pond, the catch's taker, her end told (pond %s, told %s; %s)" % [pond, told, _said])
	_said.clear()
	var offers: Array[String] = []
	_play(300, func() -> bool:
		if not fresh.offer.is_empty() and not str(fresh.offer.get("kind", "")) in offers:
			offers.append(str(fresh.offer.get("kind", "")))
		return false
	, true)
	var unseen := _said.filter(func(each: String) -> bool:
		return _in_deck(each, "go.mughouse", _companion()) or _in_deck(each, "offer.mughouse", _companion()))
	_check(unseen.is_empty() and not "mughouse" in offers,
		"300 s with nothing new over hundreds of cells: no offer names the Mughouse as unseen (offers %s; %s)" % [offers, _said])
	_check(not "pond" in offers and not _said.any(func(each: String) -> bool: return _in_deck(each, "go.pond", _companion())),
		"nor the pond she brought them to (offers %s)" % [offers])
	_restore_run_a(keep, record, lists, lists_was)


## Every rod on [param player] taken off (945 amended (4)'s rows: a fresh character has none).
func _no_rod(player: Player) -> void:
	for i in 8:
		var slot := World.rod_slot(player)
		if slot < 0:
			return
		World.consume(player, World.slot_uid(player, slot), "test")


## A rod in [param player]'s pack (bought from Rolf), unless one is on them.
func _at_rod_step(record: PlayerRecord) -> FirstSteps:
	var fresh := _fresh_card(record)
	fresh.card.erase("told")
	fresh.card["done"] = ["mughouse"]
	fresh.was_inside = true
	_no_rod(_player())
	return fresh


## 945 amended (4), the coordinator's row (TASK 7, "she leads a new player to the pond with no rod and says
## nothing"): a fresh character with no rod, through the server's ticks. Her chain's Mughouse, a Y, in and out by
## the link; then, by day, Rolf's stall for a rod (not the pond), a Y, her arrive line before his counter; by the
## stall with no rod yet, no pond; the rod bought, the pond. On main she offered the pond to a player who could
## not fish there.
func _test_no_rod() -> void:
	print("\n== a newcomer with no rod: the Mughouse, Rolf's stall for a rod, then the pond ==")
	var pet := _companion()
	var player := _player()
	var record: PlayerRecord = _main._record_of(pet) if pet != null else null
	if pet == null or player == null or record == null:
		_check(false, "(a player and their companion)")
		return
	var keep := pet.first_steps
	var lists := [record.known_places, record.explored_places, record.known_areas]
	var lists_was := lists.map(func(each: Array) -> Array: return each.duplicate())
	for kind: String in ["mughouse", "pond"]:
		var key := str(_main._first_dest(kind, pet, player, record).get("key", ""))
		for each: Array in lists:
			each.erase(key)
	keep.offer = {}
	_main._guide_offers.erase(pet.keeper_id)
	_check(_rolf_keeps(), "by day Rolf keeps his stall (%s)" % [_main._first_stall("wilds")])
	var fresh := FirstSteps.new()
	record.companion["first_steps"] = {"done": []}
	fresh.card = record.companion["first_steps"]
	_main._first_steps_live[record.player_id] = fresh
	pet.first_steps = fresh
	pet.first_words = false
	_no_rod(player)
	_lull(pet, player)
	_said.clear()
	var offered := _play(30, func() -> bool: return str(fresh.offer.get("kind", "")) == "mughouse")
	if not offered:
		_check(false, "her chain's Mughouse offer (%s; %s)" % [_said, _why(pet, player)])
		_restore_run_a(keep, record, lists, lists_was)
		_a_rod(_player())
		return
	_press_y(pet, str(_said[-1]))
	pet._last_unasked_tick = -100000
	_led("chain", "mughouse")
	_main.travel(Net.local_id, "umbrage_tavern")
	_hear()
	_play(7)
	_main.travel(Net.local_id, "wilds")
	_hear()
	pet = _companion()
	player = _player()
	DayNight.set_hour(12.0)
	_said.clear()
	var next := _play(60, func() -> bool: return str(fresh.offer.get("kind", "")) in ["rod", "pond"])
	var heard := str(_said[-1]) if not _said.is_empty() else ""
	_check(next and str(fresh.offer.get("kind", "")) == "rod" and _in_deck(heard, "offer.rod", pet)
		and not _said.any(func(each: String) -> bool: return _in_deck(each, "offer.pond", pet)),
		"out of the Mughouse with no rod, she offers Rolf's stall for one, not the pond (offer %s; %s; stall %s)" % [
			fresh.offer, _said, _main._first_stall("wilds")])
	if str(fresh.offer.get("kind", "")) != "rod":
		_restore_run_a(keep, record, lists, lists_was)
		_a_rod(_player())
		return
	_check(FirstSteps.offer_said(heard) and not "First one" in heard, "her stall offer arms Y and names no price (%s)" % heard)
	_press_y(pet, heard)
	_led("chain", "rod")
	_check(fresh.next_step() == "pond" and not fresh.stall.is_empty(), "there, the rod's step done, the stall kept for the pond's wait (next %s)" % fresh.next_step())
	var off: Vector2i = _main._nearest_free(fresh.stall["cell"] + Vector2i(0, 5))
	_lull(pet, player, off)  # Stepped off Rolf (by him her lull holds: Main._keeper_busy), still by his stall.
	_said.clear()
	var early := _play(45, func() -> bool: return not fresh.offer.is_empty())
	_check(not early and fresh.chain_running() and not _said.any(func(each: String) -> bool: return _in_deck(each, "offer.pond", pet)),
		"by the stall with no rod yet: no pond offered, the chain waits (offer %s; %s)" % [fresh.offer, _said])
	_a_rod(player)
	_lull(pet, player, off)
	var pond := _play(30, func() -> bool: return str(fresh.offer.get("kind", "")) == "pond")
	_check(pond and _in_deck(str(_said[-1]) if not _said.is_empty() else "", "offer.pond", pet),
		"the rod bought, the pond offered (%s; %s)" % [_said, _why(pet, player)])
	_restore_run_a(keep, record, lists, lists_was)
	_a_rod(_player())


## 945 amended (4), the coordinator's (2): out of the Mughouse at night with no rod, Rolf abed. At the moment the
## stall's offer would have come, one line, once, that his stall opens in the morning (no offer, no Y); her
## at-a-loss offers go on through the wait; by day, the stall's offer. The catch at night waits on his hours too.
func _test_rod_night() -> void:
	print("\n== no rod at night: once, the stall opens in the morning; her other offers go on; by day, the stall ==")
	var pet := _companion()
	var player := _player()
	var record: PlayerRecord = _main._record_of(pet) if pet != null else null
	if pet == null or player == null or record == null:
		_check(false, "(a player and their companion)")
		return
	var keep := pet.first_steps
	var lists := [record.known_places, record.explored_places, record.known_areas]
	var lists_was := lists.map(func(each: Array) -> Array: return each.duplicate())
	for kind: String in FirstSteps.PLACES:
		var key := str(_main._first_dest(kind, pet, player, record).get("key", ""))
		for each: Array in lists:
			each.erase(key)
	var fs := _at_rod_step(record)
	DayNight.set_hour(20.0)
	_check(_main._first_stall("wilds").get("night") == true and _main._first_stall("wilds").get("kept") == false,
		"at 20:00 Rolf does not keep his stall (%s)" % [_main._first_stall("wilds")])
	_lull(pet, player)
	_said.clear()
	_tick()
	var line := str(_said[0]) if _said.size() == 1 else ""
	_check(_in_deck(line, "rod.morning", pet) and fs.offer.is_empty() and not FirstSteps.offer_said(line) and fs.next_step() == "rod",
		"one line that his stall opens in the morning: no offer, no Y, the step kept (%s; offer %s; %s)" % [_said, fs.offer, _why(pet, player)])
	_said.clear()
	var unasked := _play(300, func() -> bool: return fs.offer.get("unasked") == true, true)
	_check(not _said.any(func(each: String) -> bool: return _in_deck(each, "rod.morning", pet)), "and only once (%s)" % [_said])
	_check(unasked and fs.next_step() == "rod", "her at-a-loss offers go on through the wait (offer %s; %s)" % [fs.offer, _said])
	_check(not _said.any(func(each: String) -> bool: return _in_deck(each, "go.pond", pet)), "never the pond to a player with no rod (%s)" % [_said])
	fs.offer = {}
	_main._guide_offers.erase(pet.keeper_id)
	pet.guide = null
	_main._guides.erase(pet.keeper_id)
	_said.clear()
	var kept := _rolf_keeps()
	var stall := _play(200, func() -> bool: return str(fs.offer.get("kind", "")) == "rod")
	_check(kept and stall and _said.any(func(each: String) -> bool: return _in_deck(each, "offer.rod", _companion())),
		"by day, Rolf at his stall: her stall offer (%s; %s)" % [_said, _main._first_stall("wilds")])
	# The catch: fish in the pack by the pond at night waits on Rolf (the stall takes fish); by day, offered.
	var catch_fs := _fresh_card(record)
	catch_fs.card.erase("told")
	catch_fs.card["done"] = ["mughouse", "rod", "pond"]
	_a_rod(_player())
	_lull(_companion(), _player())
	catch_fs.pond = {"area": "wilds", "cell": _player().tile}
	var fish := World.items.mint("fish", "built")
	World.put_item(_player(), _player(), World.free_slot_for(_player(), "fish"), fish)
	var taker: Dictionary = _main._first_taker(_player())
	if not str(taker.get("taker", "")).begins_with("Rolf"):
		_check(true, "(the catch's taker is not Rolf here: %s)" % [taker])
	else:
		DayNight.set_hour(20.0)
		_said.clear()
		_tick()
		_check(str(catch_fs.offer.get("kind", "")) != "catch" and catch_fs.next_step() == "catch" and _main._first_taker(_player()).get("closed") == true,
			"with fish at night: no offer to Rolf abed, the catch's step waits (offer %s; %s)" % [catch_fs.offer, _said])
		catch_fs.offer = {}
		_main._guide_offers.erase(_companion().keeper_id)
		_companion().guide = null
		_main._guides.erase(_companion().keeper_id)
		_said.clear()
		_rolf_keeps()
		if catch_fs.offer.is_empty():
			_lull(_companion(), _player())
			_tick()
		_check(str(catch_fs.offer.get("kind", "")) == "catch" and _said.any(func(each: String) -> bool: return _in_deck(each, "offer.catch", _companion())),
			"by day: the catch offered to Rolf at the stall (%s)" % [_said])
	World.consume(_player(), fish, "test")
	_restore_run_a(keep, record, lists, lists_was)
	_a_rod(_player())


## 945 amended (4), the coordinator's (3): a lapse is not a no. The stall's offer left to lapse is made once more at
## her next lull; a second lapse passes it (no rod: the pond and the catch with it), her end told next. A no to it
## passes them at once; so does walking off from the stall with no rod. The pond's lapse, once more too.
func _test_rod_lapse() -> void:
	print("\n== the stall's offer: a lapse once more, a second passes; a no, or walking off rodless, passes the pond ==")
	var pet := _companion()
	var player := _player()
	var record: PlayerRecord = _main._record_of(pet) if pet != null else null
	if pet == null or player == null or record == null:
		_check(false, "(a player and their companion)")
		return
	var keep := pet.first_steps
	var lapse := FirstSteps.ticks("lapse_s", 90)
	_check(_rolf_keeps(), "by day Rolf keeps his stall")
	var fs := _at_rod_step(record)
	_lull(_companion(), _player())
	_said.clear()
	_tick()
	_check(str(fs.offer.get("kind", "")) == "rod", "the stall offered (%s; %s)" % [_said, _why(_companion(), _player())])
	fs.offer["tick"] = World.tick - lapse - 1
	_tick()
	_check(fs.next_step() == "rod" and fs.offer.is_empty() and fs.chain_running(), "left to lapse: the step kept, not passed (next %s)" % fs.next_step())
	_lull(_companion(), _player())
	_said.clear()
	_tick()
	_check(fs.offer.is_empty(), "not at once: at her next lull (%s)" % [_said])
	fs.again_tick = World.tick - 1  # Her next lull come.
	_lull(_companion(), _player())
	_tick()
	_check(str(fs.offer.get("kind", "")) == "rod" and _in_deck(str(_said[-1]) if not _said.is_empty() else "", "offer.rod", _companion()),
		"once more, the stall offered (%s)" % [_said])
	fs.offer["tick"] = World.tick - lapse - 1
	_tick()
	_check(not fs.chain_running(), "a second lapse: the rod's, the pond's and the catch's steps pass (card %s)" % [fs.card])
	_lull(_companion(), _player())
	_said.clear()
	_tick()
	_check(_said.size() == 1 and _in_deck(_said[0], "chain_end", _companion()), "her end told next (%s)" % [_said])
	# A no.
	fs = _at_rod_step(record)
	_lull(_companion(), _player())
	_tick()
	_said.clear()
	_says("No thanks.")
	_check(not fs.chain_running() and _said.size() == 1 and _in_deck(_said[0], "no", _companion()), "a no to the stall: no pond nor catch (%s; card %s)" % [_said, fs.card])
	# Walked off from the stall with no rod.
	fs = _at_rod_step(record)
	fs.card["done"] = ["mughouse", "rod"]
	fs.stall = _main._first_dest("rod", _companion(), _player(), record)
	_lull(_companion(), _player(), Vector2i(150, 214))
	fs.was_inside = true
	_said.clear()
	_tick()
	_check(not fs.chain_running() and _said.is_empty(), "walked off from the stall with no rod: the pond and the catch pass, nothing said (%s; card %s; stall %s)" % [_said, fs.card, fs.stall.get("cell")])
	# The pond's lapse, once more too.
	fs = _at_rod_step(record)
	fs.card["done"] = ["mughouse", "rod"]
	_a_rod(_player())
	_lull(_companion(), _player())
	_tick()
	_check(str(fs.offer.get("kind", "")) == "pond", "with a rod, the pond offered (%s)" % [fs.offer])
	fs.offer["tick"] = World.tick - lapse - 1
	_tick()
	fs.again_tick = World.tick - 1
	_lull(_companion(), _player())
	_tick()
	_check(str(fs.offer.get("kind", "")) == "pond" and fs.chain_running(), "the pond's lapse: offered once more (%s)" % [fs.offer])
	fs.offer["tick"] = World.tick - lapse - 1
	_tick()
	_check(not fs.chain_running(), "its second lapse ends the chain, as before (card %s)" % [fs.card])
	_main._guide_offers.erase(_companion().keeper_id)
	_restore_run_a(keep, record, [], [])
	_a_rod(_player())


## 945 amended (4), the coordinator's (4): never the pond to a player with no rod, asked or at a loss. Asked by day,
## Rolf's stall for a rod in the pond's place, its clause and the stall taken by naming it; at night neither.
func _test_rod_asked() -> void:
	print("\n== asked, no rod: Rolf's stall in the pond's place; never the pond unasked ==")
	var pet := _companion()
	var player := _player()
	var record: PlayerRecord = _main._record_of(pet) if pet != null else null
	if pet == null or player == null or record == null:
		_check(false, "(a player and their companion)")
		return
	var keep := pet.first_steps
	var lists := [record.known_places, record.explored_places, record.known_areas]
	var lists_was := lists.map(func(each: Array) -> Array: return each.duplicate())
	for kind: String in FirstSteps.PLACES:
		var key := str(_main._first_dest(kind, pet, player, record).get("key", ""))
		for each: Array in lists:
			each.erase(key)
	_check(_rolf_keeps(), "by day Rolf keeps his stall")
	var fs := _fresh_card(record)
	_no_rod(_player())
	var firsts := func(unasked: bool) -> Array:
		return _main._first_choices(_companion(), _player(), record, unasked).map(func(each: Dictionary) -> String: return str(each["first"]))
	_check(not "pond" in firsts.call(true) and not "rod" in firsts.call(true), "unasked, no rod: neither the pond nor the stall (%s)" % [firsts.call(true)])
	_check(not "pond" in firsts.call(false) and "rod" in firsts.call(false), "asked, no rod, by day: the stall in the pond's place (%s)" % [firsts.call(false)])
	_lull(_companion(), _player())
	_said.clear()
	_says("Where to?")
	var answer := str(_said[-1]) if not _said.is_empty() else ""
	var clause := FirstSteps.lines("choice.rod", "")
	_check(not clause.is_empty() and str(clause[0]) in answer and not "the pond" in answer,
		"her answer names Rolf's stall for a rod, not the pond (%s)" % answer)
	_says("The stall, then.")
	var walk: Guide = _companion().guide
	_check(walk != null and str(walk.goal.get("first", "")) == "rod", "naming the stall takes it (%s)" % [walk.goal if walk != null else {}])
	_companion().guide = null
	_main._guides.erase(_companion().keeper_id)
	DayNight.set_hour(20.0)
	_check(not "pond" in firsts.call(false) and not "rod" in firsts.call(false), "asked at night, no rod: neither (%s)" % [firsts.call(false)])
	_a_rod(_player())
	DayNight.set_hour(12.0)
	_check("pond" in firsts.call(false) and not "rod" in firsts.call(false), "with a rod, the pond as before (%s)" % [firsts.call(false)])
	fs.offer = {}
	_restore_run_a(keep, record, lists, lists_was)


## Every place her first steps lead to, by each path that offers it (the coordinator's rows, 945 amended (3), after
## run A on guide-look-6: her arrival at the hut said and logged nothing). The chain's three are run A's (_led).
## Unasked: each place, the others seen (her card's days, as visits write them), her player walking known ground
## till nothing is new, her offer on the server's own second, a Y, the walk. Asked: "Where to?" names the first
## two places not where they stand (FirstSteps.PLACES' order): from the square the Mughouse (a yes) and the pond
## (named); by the pond the Mughouse and the hut (named). The temple and the mound come third or later wherever
## one stands in the wilds, so her asked answer never names them.
