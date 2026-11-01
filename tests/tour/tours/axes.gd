extends RefCounted
## The heavy axes' timing (playtest, for combat's 750 side (2)): run with a
## foe and a weapon from the server,
##   TOUR_SERVER_ARGS="--test-foe=draugr,giant_axe" sh tools/tour.sh axes
## (Main._test_foe: that weapon in my hand, that monster 3 cells east).
## Timed from the client's own events, as Brand's sledge in the barrow tour:
## a wind-up's ticks and its winding to swung; how soon after a blow the
## wielder moves again (a monster: its next step; me: a move ordered at the
## blow, until my body is seen to move).
## Combat's numbers: the axes wind up 8 ticks and stand planted 5 after
## (a player's free body held to its next blow, ~1.0 s for the giant axe);
## the draugr's strike 3 planted with enemy-ai's row; the sledge 9 and 8.

const TICK_MS := 100.0


func run(bot: Node) -> void:
	await bot.until(func() -> bool: return "axe" in _weapon(bot), 10.0)
	var weapon := _weapon(bot)
	bot.log_line("in hand: %s" % weapon)
	var got: bool = await bot.until(func() -> bool: return _foe(bot) != null, 20.0)
	if not bot.expect(got, "the test foe is there"):
		return
	var foe: GridEntity = _foe(bot)
	bot.log_line("the foe: %s at %s" % [bot.label(foe), foe.tile])
	if "raugr" in bot.label(foe):
		# The Draugr speaks first (his challenge): his window opened and refused,
		# "and he fights you for it".
		await bot.click(foe.tile)
		await bot.seconds(2.0)
		var words: Array = bot.buttons().map(func(b: Dictionary) -> String: return str(b["text"]))
		bot.log_line("his window: %s" % [words])
		for answer: String in ["refuse", "fight", "no"]:
			if bot.press(answer):
				break
		await bot.seconds(2.0)
	var foe_id := foe.get_instance_id()
	var ids: Array = [foe_id]
	var steps: Array = []  # The foe's tile changes: {"msec", "tile"}.
	var mine: Array = []  # My moves ordered at a blow: {"blow", "moved"}.
	var since: int = bot.now_msec()
	var watch := {"tile": foe.tile}
	var end: int = bot.now_msec() + 60000
	var last_seen := 0
	while bot.now_msec() < end and bot.me() != null and int(bot.me().hp) > 0:
		if not is_instance_valid(foe):
			foe = _foe(bot)  # Out of view and back: the same body, a new node.
			if foe == null:
				await bot.frames(1)
				continue
			foe_id = foe.get_instance_id()
			ids.append(foe_id)
		if int(foe.get("hp")) <= 0:
			break
		if foe.tile != watch["tile"]:
			steps.append({"msec": bot.now_msec(), "tile": foe.tile})
			watch["tile"] = foe.tile
		var my_swings: Array = _of(bot, bot.me().get_instance_id(), "swung", since)
		if my_swings.size() > last_seen and mine.size() < 3:
			last_seen = my_swings.size()
			# At my blow, a move away ordered: when does my body go?
			var blow_msec: int = my_swings[-1]["msec"]
			# Where my body is drawn (the client's own, as a player sees it).
			var start: Vector2 = (bot.me() as Node2D).position
			var start_cell: Vector2i = bot.cell()
			var away: Vector2i = bot.cell() + (bot.cell() - foe.tile).sign() * 3
			await bot.click(away)
			var moved: bool = await bot.until(func() -> bool:
				# A cell left: the blow's own lunge shifts the drawn body ~15 px in place.
				return bot.me() != null and bot.cell() != start_cell, 4.0)
			mine.append({"blow": blow_msec, "moved": bot.now_msec() if moved else -1})
			# The drawn body over the next 1.5 s: a step the server refused would
			# come back (a snap); a real one keeps going.
			var track: Array = []
			var tiles: Array = []
			for i in 15:
				await bot.seconds(0.1)
				if bot.me() == null:
					break
				track.append(snappedf((bot.me() as Node2D).position.distance_to(start), 0.1))
				tiles.append(bot.cell())
			bot.log_line("    drawn distance from where I stood, each 0.1 s: %s; my cell %s" % [track, tiles])
			bot.log_line("  my blow at %d ms: moved %s" % [blow_msec - since, "after %d ms" % (bot.now_msec() - blow_msec) if moved else "not within 4 s"])
			continue
		if bot.frames_since_click() > 20:
			await bot.click(foe.tile)  # Attack: go to it and strike.
		await bot.frames(1)
	bot.log_line("over: my hp %s, its hp %s" % [bot.me().get("hp") if bot.me() != null else "-", foe.get("hp") if is_instance_valid(foe) else "gone"])
	_report(bot, "my %s" % weapon, bot.me().get_instance_id() if bot.me() != null else 0, since, 8, [])
	for id: int in ids:
		_report(bot, "the draugr", id, since, -1, steps)
	# My own companion beside me is spared my axe's arc (343 amended).
	var friend: GridEntity = bot.companion()
	if friend != null:
		var who: String = bot.label(friend)
		# The server's "down: <name> knocked down by PlayerN": any but the foe's.
		var downed: Array = bot.server_lines("knocked down by Player").filter(func(line: String) -> bool:
			return not "Foe" in line and not "raugr" in line)
		bot.expect(downed.is_empty(), "my axe's arc spares my own companion (%s)" % who, "%d times: %s" % [downed.size(), str(downed.slice(0, 2)).left(200)])
	var gaps: Array = mine.filter(func(m: Dictionary) -> bool: return m["moved"] > 0).map(func(m: Dictionary) -> int: return m["moved"] - m["blow"])
	bot.log_line("my %s: blow to my body moving (a move ordered at the blow) %s ms" % [weapon, gaps])
	if not gaps.is_empty():
		# Combat: ~10 ticks (giant axe), ~11 (battle axe): 688's halt to the next blow, over the 5.
		bot.expect(gaps.all(func(g: int) -> bool: return g >= 5 * TICK_MS - 50 and g <= 13 * TICK_MS), "after my %s's blow my body is held 5 to about 11 ticks" % weapon, "%s ms" % [gaps])


func _report(bot: Node, who: String, id: int, since: int, want_ticks: int, steps: Array) -> void:
	var winds: Array = _of(bot, id, "winding", since).filter(func(b: Dictionary) -> bool: return int(b["ticks"]) > 0 and int(b["ticks"]) < 15)
	var swings: Array = _of(bot, id, "swung", since)
	var ticks: Array = winds.map(func(b: Dictionary) -> int: return int(b["ticks"]))
	var to_blow: Array = []
	var all_winds: Array = _of(bot, id, "winding", since)
	for wind: Dictionary in winds:
		var next: Array = swings.filter(func(b: Dictionary) -> bool: return b["msec"] >= wind["msec"])
		# A wind-up given up (a winding of 0 ticks) before the next blow is not that blow's.
		var given_up: Array = all_winds.filter(func(b: Dictionary) -> bool:
			return int(b["ticks"]) == 0 and b["msec"] > wind["msec"] and (next.is_empty() or b["msec"] <= next[0]["msec"]))
		if not next.is_empty() and given_up.is_empty():
			to_blow.append(int(next[0]["msec"]) - int(wind["msec"]))
	var planted: Array = []
	for swing: Dictionary in swings:
		var next_step: Array = steps.filter(func(s: Dictionary) -> bool: return s["msec"] > swing["msec"])
		if not next_step.is_empty():
			planted.append(int(next_step[0]["msec"]) - int(swing["msec"]))
	bot.log_line("%s: %d wind-ups, ticks %s, wind-up to blow %s ms, %d blows, blow to its next step %s ms" % [who, winds.size(), ticks, to_blow, swings.size(), planted])
	if want_ticks > 0 and not winds.is_empty():
		bot.expect(ticks.all(func(t: int) -> bool: return t == want_ticks), "%s winds up %d ticks" % [who, want_ticks], "ticks %s" % [ticks])
	if not to_blow.is_empty():
		bot.expect(to_blow.all(func(g: int) -> bool: return absi(g - int(ticks[0]) * int(TICK_MS)) <= int(TICK_MS) + 50), "%s's blow falls as wound (within a tick)" % who, "%s ms for %s ticks" % [to_blow, ticks])
	if want_ticks < 0 and not winds.is_empty():
		bot.expect(ticks.all(func(t: int) -> bool: return t == 8), "%s's plain strike winds up 8 ticks (his spin's 15 left out)" % who, "ticks %s" % [ticks])
	if not planted.is_empty():
		bot.expect(planted.all(func(g: int) -> bool: return g >= 3 * int(TICK_MS) - 50), "%s does not step within 3 ticks of a blow" % who, "%s ms" % [planted])


func _of(bot: Node, id: int, kind: String, since: int) -> Array:
	return bot.blows.filter(func(b: Dictionary) -> bool: return b["who"] == id and b["kind"] == kind and b["msec"] >= since)


func _foe(bot: Node) -> GridEntity:
	for entity: GridEntity in bot.seen(""):
		if not entity is Monster:
			continue
		# --test-foe's: named "Foe", or (since 9e6bfb2e) made as its kind's own class.
		if String(entity.name).begins_with("Foe") or "raugr" in bot.label(entity):
			return entity
	return null


func _weapon(bot: Node) -> String:
	var slots: Array = Array(bot.me().get("slots")) if bot.me() != null else []
	for item in slots:
		if "axe" in str(item):
			return str(item)
	return str(slots)
