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
## Umbrage's chapel (734 amended (2), buildings), its doors, counter and the
## visit's front cell: a visitor stands inside, beyond a cell of each (the
## coordinator, 11-01, after npc's 734 amended (4)).
const CHAPEL := Rect2i(215, 191, 6, 10)
const CHAPEL_KEEP_OFF := [Vector2i(217, 200), Vector2i(218, 200), Vector2i(217, 195), Vector2i(217, 201)]
const TRADE_WORDS := ["gold", "buy", "ware", "trade", "sell", "barter"]

var _met := {}
var _counter_by_day := {}  # A merchant's name -> the counter's goods at noon.  # "person|hour" -> {name, trade, activity, buttons, heard}


func run(bot: Node) -> void:
	await bot.admin("gold Tourbot 100 tour")
	for hour: int in HOURS:
		await bot.admin("hour %d" % hour)
		await bot.walk_to(SQUARE, 3, 120.0)
		await bot.seconds(5.0 if hour == HOURS[0] else 60.0)  # At night, to their beds first.
		await _pass(bot, hour)
	await _chapel_visit(bot)
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
		# Sleepers don't trade (751 amended (2), npc): no Barter on the bar, and
		# a barter with the person (Main's {resident}, a maker's or one sent
		# anyway) is answered only by the asleep line; the shop's counter stays
		# open at night (the coordinator's ruling, 11-01: goods at a price, as if
		# paid into the box).
		bot.expect(not "Barter" in buttons, "%s, asleep, offers no Barter (sleepers don't trade)" % name, "buttons %s" % [buttons])
		if trade == "merchant" or trade in Items.TRADES:
			bot.main.barter_data = {}
			var asked: int = bot.now_msec()
			World.command(bot.me(), "barter", {"resident": str(person.get_path())})
			await bot.seconds(2.0)
			var answered: Array = bot.told_since(asked).filter(func(l: Dictionary) -> bool: return name in str(l["text"]))
			bot.expect((bot.main.barter_data as Dictionary).is_empty() and not answered.is_empty(), "a barter with %s asleep is refused, told they sleep" % name,
				"told %s; a barter answer %s" % [bot.told_since(asked).map(func(l: Dictionary) -> String: return str(l["text"]).left(60)),
					str(bot.main.barter_data).left(120)])
			var counter: GridEntity = bot.main._shop_counter_near(person) if trade == "merchant" else null
			if counter != null:
				await bot.walk_to(counter.tile, 1, 30.0)  # At the counter: a refusal for the reach is no answer.
				bot.main.barter_data = {}
				World.command(bot.me(), "barter", {"shop": str(counter.get_path())})
				await bot.until(func() -> bool: return not (bot.main.barter_data as Dictionary).is_empty(), 4.0)
				var data: Dictionary = bot.main.barter_data
				var goods: Array = data.get("goods", []) if not data.is_empty() else []
				# As open as by day: not refused, the goods the noon answer had (a
				# fresh world's store may hold none yet).
				var by_day: int = _counter_by_day.get(name, -1)
				bot.expect(not data.is_empty() and str(data.get("why", "")).is_empty() and (by_day < 0 or goods.size() == by_day),
					"%s's counter still sells while %s sleeps, as by day (intended)" % [name, name],
					"the answer: why \"%s\", %d goods (by day %d)" % [data.get("why", ""), goods.size(), by_day] if not data.is_empty() else "no answer")
			if bot.main.barter_panel != null and bot.main.barter_panel.visible:
				bot.main.barter_panel.hide()
	else:
		bot.expect(not buttons.is_empty() or not heard.is_empty(), "%s answers a click (the talk bar or a greeting)" % name,
			"no buttons, nothing heard; activity %s" % person.get("activity"))
		if trade == "merchant":
			var counter: GridEntity = bot.main._shop_counter_near(person)
			if counter != null:
				await bot.walk_to(counter.tile, 1, 30.0)
				bot.main.barter_data = {}
				World.command(bot.me(), "barter", {"shop": str(counter.get_path())})
				await bot.until(func() -> bool: return not (bot.main.barter_data as Dictionary).is_empty(), 4.0)
				var day: Dictionary = bot.main.barter_data
				_counter_by_day[name] = (day.get("goods", []) as Array).size() if not day.is_empty() else -1
				bot.log_line("  %s's counter by day: why \"%s\", %d goods" % [name, day.get("why", ""), _counter_by_day[name]])
				if bot.main.barter_panel != null and bot.main.barter_panel.visible:
					bot.main.barter_panel.hide()
		# A merchant fronting a shop, or a maker (Main._barters): a priest has none.
		if (trade == "merchant" or trade in Items.TRADES) and not buttons.is_empty():
			bot.expect(buttons.any(func(t: String) -> bool: return TRADE_WORDS.any(func(w: String) -> bool: return w in t.to_lower())),
				"%s, a %s, shows wares or a way to them" % [name, trade], "buttons %s" % [buttons])
	bot.press("close")  # Else the bar goes as I walk on to the next.
	await bot.seconds(0.5)


## Townsfolk come into the chapel at a visiting hour: watched from inside its
## door over a quick morning (a game hour in 30 s, from 9), a Resident not the
## priest (Aldous works there) on a cell of the chapel more than a cell from its
## doors, its counter and the visit's front cell.
func _chapel_visit(bot: Node) -> void:
	await bot.admin("hour 9")
	await bot.walk_to(Vector2i(217, 198), 1, 120.0)
	# With npc's --test-temple-day (TOUR_TEMPLE_DAY=1 and TOUR_SERVER_ARGS
	# carrying the flag): today is everyone's temple day, watched 9:00 to about
	# 10:45 (each one's own clock, +-0.75 h) at a normal clock, and judged.
	var judged := OS.get_environment("TOUR_TEMPLE_DAY") == "1"
	if not judged:
		await bot.admin("day_minutes 12")
	var inside := {}
	var end: int = bot.now_msec() + (420000 if judged else 240000)
	while bot.now_msec() < end and inside.is_empty():
		for body: GridEntity in bot.seen(""):
			if body is Resident and str(body.get("trade")) != "priest" and CHAPEL.has_point(body.tile) 					and CHAPEL_KEEP_OFF.all(func(c: Vector2i) -> bool: return World.distance(c, body.tile) > 1):
				inside[_who(body)] = body.tile
				bot.log_line("in the chapel: %s at %s (%s)" % [_who(body), body.tile, body.get("activity")])
		await bot.seconds(1.0)
	await bot.admin("day_minutes 90")
	# The priest at his work (npc's 734 amended (4)): in the chapel, never on or
	# beside its doors, its counter or the respawn cell (the coordinator, 11-01).
	await bot.admin("hour 12")
	var found := {}  # A lambda's own assignment never reaches out (captured by value).
	await bot.until(func() -> bool:
		for body: GridEntity in bot.seen(""):
			if body is Resident and str(body.get("trade")) == "priest" and CHAPEL.has_point(body.tile):
				found["priest"] = body
		return found.has("priest"), 60.0)
	var priest: GridEntity = found.get("priest")
	if bot.expect(priest != null, "the priest is at his work in the chapel at noon"):
		await bot.seconds(5.0)  # Settled at his spot.
		bot.expect(CHAPEL.has_point(priest.tile) and CHAPEL_KEEP_OFF.all(func(c: Vector2i) -> bool: return World.distance(c, priest.tile) > 1),
			"%s works in the chapel off its doors, its counter and the respawn cell" % _who(priest), "at %s" % priest.tile)
	# Reported, not judged: a visit comes on a person's temple day (residents.json
	# "temple", every 7 days by their id), which the tour can't choose yet (asked
	# 11-01 for a test hook); one morning has about a 63% chance of nobody's.
	if judged:
		bot.expect(not inside.is_empty(), "on a temple day a townsperson comes into the chapel (beyond its doors and counter)",
			"%s" % (inside if not inside.is_empty() else "none from 9:00 to about 10:45"))
	else:
		bot.log_line("chapel visitors from 9:00 (not judged without --test-temple-day): %s" % (inside if not inside.is_empty() else "none"))
