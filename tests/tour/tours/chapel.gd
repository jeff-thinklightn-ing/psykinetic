extends RefCounted
## Umbrage's chapel (734 amended (2), buildings: the wilds temple as the
## temple kind, 6x10 at 215-220 x 191-200, doors (217, 200) and (218, 200),
## its counter (217, 195)), toured as a player: sh tools/tour.sh chapel
## (1) Aldous at his work in it, talked to; (2) townsfolk visit it; (3) the
## sealed shortcut both ways: refused without the "draugr" mark (the draugr
## beaten, decision 540; given here by the console, that fight's outcome, as
## a lone bot can't win it), with it barrow_deep (49, 77) up to (217, 192)
## and the chapel's north-west stair (215, 191) down to (49, 76); (4) a
## fallen player brought back at the temple, outside its door (217, 201).

const TEMPLE := Rect2i(215, 191, 6, 10)
const OUTSIDE_DOOR := Vector2i(217, 201)
const INSIDE := Vector2i(217, 197)
const UP_ARRIVAL := Vector2i(217, 192)
const STAIR_DOWN := Vector2i(215, 191)
const DEEP_ARRIVAL := Vector2i(49, 76)
const DEEP_LINK := Vector2i(49, 77)
## Where the Ossuary's dead stand (barrow_deep's first halls): a lone bot
## goes down there.
const AMONG_THE_DEAD := Vector2i(49, 40)


func run(bot: Node) -> void:
	if OS.get_environment("TOUR_ONLY") == "shortcut":  # The sealed way alone, both ways.
		await _shortcut(bot)
		return
	if OS.get_environment("TOUR_ONLY") == "respawn":  # Run with TOUR_SERVER_ARGS="--test-foe=draugr,stick".
		await _fall_to_foe(bot)
		await _brought_back(bot)
		return
	await _aldous(bot)
	await _visits(bot)
	await _shortcut(bot)
	await _respawn(bot)


func _aldous(bot: Node) -> void:
	await bot.admin("hour 12")
	await bot.walk_to(OUTSIDE_DOOR, 0, 120.0)
	await bot.walk_to(INSIDE, 1, 30.0)
	bot.expect(TEMPLE.has_point(bot.cell()), "in through the temple's door", "at %s" % bot.cell())
	await bot.until(func() -> bool: return bot.find("Aldous") != null, 30.0)
	var aldous: GridEntity = bot.find("Aldous")
	if not bot.expect(aldous != null, "Aldous is seen from inside the temple"):
		return
	await bot.until(func() -> bool: return TEMPLE.has_point(aldous.tile), 60.0)
	bot.expect(TEMPLE.has_point(aldous.tile), "Aldous is at his work in the temple at noon",
		"at %s, %s" % [aldous.tile, aldous.get("activity")])
	var since: int = bot.now_msec()
	await bot.walk_to(aldous.tile, 2, 20.0)
	await bot.click(aldous.tile)
	await bot.seconds(3.0)
	var buttons: Array = bot.buttons().filter(func(b: Dictionary) -> bool: return str(b["text"]) != "World map") \
		.map(func(b: Dictionary) -> String: return str(b["text"]))
	var heard: Array = bot.heard_from(str(aldous.get_path()), since)
	bot.expect(not buttons.is_empty() or not heard.is_empty(), "Aldous answers a click in the temple", "buttons %s; heard %d" % [buttons, heard.size()])
	bot.press("close")


## Townsfolk come to the temple: a short day (a game hour in 30 s) from 9,
## the temple watched from inside; any resident in it but Aldous.
func _visits(bot: Node) -> void:
	await bot.admin("hour 9")
	await bot.admin("day_minutes 12")
	var seen := {}
	var end: int = bot.now_msec() + 240000
	while bot.now_msec() < end:
		for body: GridEntity in bot.seen(""):
			if body is Resident and TEMPLE.has_point(body.tile):
				var who := str(body.get("person"))
				if who != "Aldous" and not seen.has(who):
					seen[who] = true
					bot.log_line("a visitor in the temple: %s at %s (%s)" % [who, body.tile, body.get("activity")])
		await bot.seconds(1.0)
	await bot.admin("day_minutes 90")
	await bot.admin("hour 12")
	bot.expect(not seen.is_empty(), "townsfolk visit the temple (watched 4 minutes, about 8 game hours from 9)", "none came in")


## The shortcut sealed by the draugr: refused without his mark, both ways with it.
func _shortcut(bot: Node) -> void:
	await bot.admin("mark Tourbot -draugr")
	await bot.admin("move Tourbot %d %d barrow_deep" % [DEEP_ARRIVAL.x, DEEP_ARRIVAL.y])
	if not bot.expect(await bot.until(func() -> bool: return bot.zone() == "barrow_deep", 30.0), "moved to barrow_deep by the shortcut"):
		return
	await bot.settled()
	await bot.walk_to(DEEP_LINK, 0, 10.0)
	await bot.seconds(2.0)
	bot.expect(bot.zone() == "barrow_deep", "without the draugr's mark, the way up is refused (the seal holds)", "in %s at %s" % [bot.zone(), bot.cell()])
	bot.log_line("mark: %s" % await bot.admin("mark Tourbot draugr"))
	await bot.walk_to(DEEP_ARRIVAL, 0, 10.0)
	await bot.walk_to(DEEP_LINK, 0, 15.0)
	var up: bool = await bot.until(func() -> bool: return bot.zone() == "wilds", 15.0)
	if bot.expect(up, "with the mark, barrow_deep's way up takes me to the wilds", "in %s at %s" % [bot.zone(), bot.cell()]):
		await bot.settled()
		# On a free cell beside the stair (714, Main._beside_link; the spawn point is the fallback): inside.
		bot.expect(TEMPLE.has_point(bot.cell()), "come up inside the chapel (beside its stair, or %s)" % UP_ARRIVAL, "at %s" % bot.cell())
		await bot.walk_to(STAIR_DOWN, 0, 15.0)
		var down: bool = await bot.until(func() -> bool: return bot.zone() == "barrow_deep", 15.0)
		if bot.expect(down, "the chapel's north-west stair %s takes me down" % STAIR_DOWN, "in %s at %s" % [bot.zone(), bot.cell()]):
			await bot.settled()
			bot.expect(World.distance(bot.cell(), DEEP_ARRIVAL) <= 1, "set down at barrow_deep %s" % DEEP_ARRIVAL, "at %s" % bot.cell())
	await bot.admin("mark Tourbot -draugr")


## Down among the Ossuary's dead, bled out: brought back at the temple's door.
func _respawn(bot: Node) -> void:
	await bot.admin("move Tourbot %d %d barrow_deep" % [AMONG_THE_DEAD.x, AMONG_THE_DEAD.y])
	await bot.until(func() -> bool: return bot.zone() == "barrow_deep", 30.0)
	await bot.settled()
	var fell: bool = await bot.until(func() -> bool: return bot.me() == null or int(bot.me().hp) <= 0, 240.0)
	if not bot.expect(fell, "the dead take me down (to be brought back)", "hp %s at %s after 4 minutes" % [bot.me().get("hp") if bot.me() != null else "-", bot.cell()]):
		return
	await _brought_back(bot)


## The armed test draugr beside me (--test-foe): his challenge refused, then
## stood still for him; down within 7 minutes.
func _fall_to_foe(bot: Node) -> void:
	await bot.settled()
	await bot.seconds(2.0)
	for body: GridEntity in bot.seen(""):
		if body is Monster and (String(body.name).begins_with("Foe") or "raugr" in bot.label(body)):
			await bot.click(body.tile)
			await bot.seconds(2.0)
			for answer: String in ["refuse", "fight", "no"]:
				if bot.press(answer):
					break
	var fell: bool = await bot.until(func() -> bool: return bot.me() == null or int(bot.me().hp) <= 0, 420.0)
	bot.expect(fell, "the test draugr takes me down (to be brought back)", "hp %s at %s" % [bot.me().get("hp") if bot.me() != null else "-", bot.cell()])


func _brought_back(bot: Node) -> void:
	if bot.me() != null and int(bot.me().hp) > 0:
		return
	await bot.seconds(2.0)
	bot.log_line("buttons while down: %s" % [bot.buttons().map(func(b: Dictionary) -> String: return str(b["text"]))])
	bot.press("bleed out")
	var back: bool = await bot.until(func() -> bool: return bot.me() != null and int(bot.me().hp) > 0 and bot.zone() == "wilds", 150.0)
	if bot.expect(back, "brought back in the wilds", "in %s, hp %s" % [bot.zone(), bot.me().get("hp") if bot.me() != null else "-"]):
		await bot.settled()
		bot.expect(World.distance(bot.cell(), OUTSIDE_DOOR) <= 2, "brought back at the temple, outside its door %s" % OUTSIDE_DOOR, "at %s" % bot.cell())
