extends "res://tests/tour/tours/axes.gd"
## The draugr as the level arms him (Level._arm: his battle axe and its row),
## timed as the axes tour times its foe: moved by the console to the
## Ossuary (barrow_deep), found, fought. Run with a heavy axe in hand:
##   TOUR_SERVER_ARGS="--test-foe=rat,giant_axe" sh tools/tour.sh draugr
## (--test-foe's own foe stays behind in the wilds). Combat's numbers: wind-up
## 8, then 3 ticks planted before his next step (949f0dce).
## Not yet passing (2026-11-01): his hall stays sealed while the Ossuary's dead
## stand (666), and they rise faster than a lone 20-hp bot puts them down. The
## timings themselves pass on the armed test foe (axes tour, 9e6bfb2e); a check
## on real ground waits on a test-only boost, logged as such (coordinator).


const DRAUGR_HALL := Vector2i(49, 75)
## The hall's door (lock "ossuary_dead"), an edge of (49, 55).
const HALL_EDGE := Vector3i(49, 55, 1)
const HALL_DOOR := Vector2i(49, 55)


func run(bot: Node) -> void:
	await bot.admin("zone move Tourbot barrow_deep")
	if not bot.expect(await bot.until(func() -> bool: return bot.zone() == "barrow_deep", 30.0), "moved to the Ossuary"):
		return
	await bot.settled()
	bot.log_line("in barrow_deep at %s" % bot.cell())
	# His hall's door stays shut while the Ossuary's dead stand (666): they are
	# fought first, as a player must; tried once first for the line it gives.
	await bot.walk_to(HALL_DOOR, 0, 60.0)  # On the door's own cell: E reaches a door from its edge's cells.
	bot.log_line("at the hall door: %s" % bot.cell())
	var door: Door = World.door_on(HALL_EDGE)
	if door != null and not door.open:
		var since: int = bot.now_msec()
		await bot.tap_e_door(door)
		await bot.seconds(1.5)
		bot.expect(not bot.told_since(since, "dead bar").is_empty(), "E at the sealed hall door tells me the dead bar the way",
			"told: %s" % str(bot.told_since(since)).left(200))
	var end: int = bot.now_msec() + 480000
	while bot.now_msec() < end and (door == null or not door.open):
		if bot.me() == null or int(bot.me().hp) <= 0 or bot.zone() != "barrow_deep":
			await bot.until(func() -> bool: return bot.me() != null and int(bot.me().hp) > 0 and bot.zone() != "barrow_deep", 120.0)
			await bot.admin("zone move Tourbot barrow_deep")
			await bot.until(func() -> bool: return bot.zone() == "barrow_deep", 30.0)
			await bot.settled()
			door = World.door_on(HALL_EDGE)
			continue
		var dead: Array = bot.seen("Monster").filter(func(e: GridEntity) -> bool:
			return e.zone == bot.me().zone and int(e.get("hp")) > 0 and not "raugr" in bot.label(e) and not String(e.name).begins_with("Foe"))
		if dead.is_empty():
			bot.log_line("none of the dead in view; the door %s" % ("open" if door != null and door.open else "shut"))
			await bot.walk_to(HALL_DOOR, 1, 30.0)
			await bot.guard(5.0)
			continue
		dead.sort_custom(func(a: GridEntity, b: GridEntity) -> bool: return World.distance(a.tile, bot.cell()) < World.distance(b.tile, bot.cell()))
		bot.log_line("the dead: %s; fighting %s" % [dead.size(), bot.label(dead[0])])
		await bot.fight(dead[0], 90.0)
		door = World.door_on(HALL_EDGE)
	if not bot.expect(door != null and door.open, "the hall door opens once the Ossuary's dead are down"):
		return
	await bot.walk_to(DRAUGR_HALL, 6, 60.0)
	var found: bool = await bot.until(func() -> bool: return _foe(bot) != null, 10.0)
	if not found:
		# Not in view from the arrival: walk toward each monster known until he is.
		for body: GridEntity in bot.seen("Monster"):
			bot.log_line("  known: %s at %s" % [bot.label(body), body.tile])
		bot.expect(false, "the draugr is in view in the Ossuary")
		return
	bot.log_line("the draugr at %s" % _foe(bot).tile)
	await super.run(bot)


func _foe(bot: Node) -> GridEntity:
	for entity: GridEntity in bot.seen("Monster"):
		if "draugr" in bot.label(entity).to_lower() and entity.zone == bot.me().zone:
			return entity
	return null
