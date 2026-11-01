extends RefCounted
## Every townsperson talked to, at noon and at night (playtest, step 4: every
## vendor and quest giver, night and day): sh tools/tour.sh folk
## Umbrage's people found as a player finds them, walking to each one seen
## (the client knows only who is near), clicked as a player clicks (Main's
## greet and talk bar, 560). Awake: the bar comes up, a trader's with its
## wares or a way to them; asleep (751): told they sleep, never spoken to.
## Never a raw node name in what is shown. Each person's buttons logged, a
## table of who was met at the end.

const HOURS := [12, 23]
## Where the town is walked from (Umbrage's square), and how long a pass may take.
const SQUARE := Vector2i(212, 205)
## The town walked through each pass: the square, its edges, the temple's huts, the store.
const SPOTS := [Vector2i(212, 205), Vector2i(219, 195), Vector2i(196, 190), Vector2i(228, 214),
	Vector2i(204, 216), Vector2i(212, 218)]
const PASS_SECONDS := 600.0
const TRADE_WORDS := ["gold", "buy", "ware", "trade", "sell", "barter"]

var _met := {}  # "person|hour" -> {name, trade, activity, buttons, heard}


func run(bot: Node) -> void:
	await bot.admin("gold Tourbot 100 tour")
	for hour: int in HOURS:
		await bot.admin("hour %d" % hour)
		await bot.walk_to(SQUARE, 3, 120.0)
		await bot.seconds(5.0 if hour == HOURS[0] else 60.0)  # At night, to their beds first.
		await _pass(bot, hour)
	await bot.admin("hour 12")
	var people := {}
	for key: String in _met:
		people[key.get_slice("|", 0)] = true
	# Each met at night was met by day too (the day pass walks the whole town).
	var by_day: Array = _met.keys().filter(func(k: String) -> bool: return k.ends_with("|%d" % HOURS[0])).map(func(k: String) -> String: return k.get_slice("|", 0))
	bot.expect(people.size() >= 3 and people.keys().all(func(p: String) -> bool: return p in by_day),
		"every townsperson was met by day (%d in all)" % people.size(), "in all %s; by day %s" % [people.keys(), by_day])
	bot.log_line("met, by hour:")
	for key: String in _met:
		var m: Dictionary = _met[key]
		bot.log_line("  h%s %s (%s, trade \"%s\"): buttons %s; heard %s" % [key.get_slice("|", 1), m["name"], m["activity"], m["trade"], m["buttons"], m["heard"]])


## One pass of the town at [param hour]: the nearest not yet met, walked to
## and clicked, until none is seen or the time is up.
func _pass(bot: Node, hour: int) -> void:
	var end: int = bot.now_msec() + int(PASS_SECONDS * 1000.0)
	var tried := {}
	while bot.now_msec() < end:
		if bot.me() == null or int(bot.me().hp) <= 0:
			bot.log_line("down in the town; the pass ends")
			return
		var left: Array = bot.seen("").filter(func(e: GridEntity) -> bool:
			return e is Resident and not tried.has(_who(e)))
		if left.is_empty():
			# None new in view: on to the next of the town's spots, then done.
			var spot: int = tried.get("_spot", 0)
			if spot >= SPOTS.size():
				break
			tried["_spot"] = spot + 1
			await bot.walk_to(SPOTS[spot], 3, 60.0)
			continue
		left.sort_custom(func(a: GridEntity, b: GridEntity) -> bool: return World.distance(a.tile, bot.cell()) < World.distance(b.tile, bot.cell()))
		var person: GridEntity = left[0]
		tried[_who(person)] = true
		await _talk_to(bot, person, hour)
	bot.log_line("hour %d: %d people tried" % [hour, tried.size() - (1 if tried.has("_spot") else 0)])


func _who(entity: GridEntity) -> String:
	var person := str(entity.get("person"))
	return person if not person.is_empty() else String(entity.name)


func _talk_to(bot: Node, person: GridEntity, hour: int) -> void:
	var name := _who(person)  # Their own name, as they are told of.
	var since: int = bot.now_msec()  # The walk's own click on them may be what they answer.
	await bot.walk_to(person.tile, 2, 40.0)
	if not is_instance_valid(person):
		return
	var asleep := str(person.get("activity")) == "sleep"
	var path := str(person.get_path())
	await bot.click(person.tile)
	await bot.seconds(3.0)
	if not is_instance_valid(person):
		return
	var buttons: Array = bot.buttons().filter(func(b: Dictionary) -> bool: return str(b["text"]) != "World map") \
		.map(func(b: Dictionary) -> String: return str(b["text"]))
	var heard: Array = bot.heard_from(path, since).map(func(l: Dictionary) -> String: return str(l["text"]).left(60))
	var trade := str(person.get("trade"))
	_met["%s|%d" % [_who(person), hour]] = {"name": name, "trade": trade, "activity": str(person.get("activity")), "buttons": buttons, "heard": heard}
	var shown := " ".join(bot.texts())
	var raw: Array = bot.node_names_in(shown)
	bot.expect(raw.is_empty(), "no raw node name shown after clicking %s" % name, "shown: %s" % [raw])
	if asleep:
		var told: Array = bot.told_since(since).filter(func(l: Dictionary) -> bool:
			return name in str(l["text"]))
		bot.expect(not told.is_empty(), "%s, asleep, is said to sleep when clicked" % name,
			"told: %s" % [bot.told_since(since).map(func(l: Dictionary) -> String: return str(l["text"]).left(60))])
		bot.expect(heard.is_empty(), "%s, asleep, says nothing" % name, "heard %s" % [heard])
		# Sleepers don't trade (the coordinator's ruling, 11-01; npc's to fix, the
		# server refusing too): no Barter on the bar, and an order sent anyway
		# (as Main's Barter sends it) refused.
		bot.expect(not "Barter" in buttons, "%s, asleep, offers no Barter (sleepers don't trade)" % name, "buttons %s" % [buttons])
		if trade == "merchant" or trade in Items.TRADES:
			bot.main.barter_data = {}
			var args := {"resident": str(person.get_path())}
			if trade == "merchant":
				var counter: GridEntity = bot.main._shop_counter_near(person)
				args = {"shop": str(counter.get_path())} if counter != null else {}
				if counter != null:
					await bot.walk_to(counter.tile, 1, 30.0)  # At the counter: a refusal for the reach is no answer.
			if not args.is_empty():
				World.command(bot.me(), "barter", args)
				await bot.until(func() -> bool: return not (bot.main.barter_data as Dictionary).is_empty(), 4.0)
				var data: Dictionary = bot.main.barter_data
				var why := str(data.get("why", ""))
				bot.expect(not data.is_empty() and not why.is_empty() and not "too far" in why, "a barter order sent to %s asleep, from the counter, is refused" % name,
					"the server's answer: why \"%s\", %d goods" % [data.get("why", ""), (data.get("goods", []) as Array).size()] if not data.is_empty() else "no answer")
			if bot.main.barter_panel != null and bot.main.barter_panel.visible:
				bot.main.barter_panel.hide()
	else:
		bot.expect(not buttons.is_empty() or not heard.is_empty(), "%s answers a click (the talk bar or a greeting)" % name,
			"no buttons, nothing heard; activity %s" % person.get("activity"))
		# A merchant fronting a shop, or a maker (Main._barters): a priest has none.
		if (trade == "merchant" or trade in Items.TRADES) and not buttons.is_empty():
			bot.expect(buttons.any(func(t: String) -> bool: return TRADE_WORDS.any(func(w: String) -> bool: return w in t.to_lower())),
				"%s, a %s, shows wares or a way to them" % [name, trade], "buttons %s" % [buttons])
	bot.press("close")  # Else the bar goes as I walk on to the next.
	await bot.seconds(0.5)
