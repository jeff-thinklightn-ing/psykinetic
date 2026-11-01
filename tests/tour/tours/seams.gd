extends RefCounted
## The seam tour (playtest): stills read by eye, run off-screen
## (sh tools/tour.sh seams --offscreen). At each road between two zones, from
## a few cells inside, looking across, at noon and at dusk, the camera low;
## and around Umbrage for the forest floor (753's holes), high. The stills
## go beside the report; a still the same as the one before (an off-screen
## window that kept its frame) is flagged.

## Where to stand and what is beyond: [zone, cell, words].
const SPOTS := [
	["foothills", Vector2i(128, 5), "the foothills' north road: the castle beyond"],
	["wilds", Vector2i(128, 25), "the wilds' north road: the foothills beyond"],
	["foothills", Vector2i(128, 90), "the foothills' south road: the wilds beyond"],
	["castle", Vector2i(18, 20), "the castle's south road: the foothills beyond"],
]
const YAWS := [0.0, 90.0, 180.0, 270.0]
const HOURS := [12, 19]
## Umbrage's edges, for the forest floor between the trees.
const TOWN_SPOTS := [Vector2i(212, 205), Vector2i(196, 190), Vector2i(228, 214)]
## Where the cut tour saw them lie down at 1 o'clock (Rolf and Hale; Aldous; Snagfin).
const SLEEP_SPOTS := [Vector2i(219, 195), Vector2i(204, 216), Vector2i(212, 218)]

var _last_md5 := ""


func run(bot: Node) -> void:
	for hour: int in HOURS:
		await bot.admin("hour %d" % hour)
		for spot: Array in SPOTS:
			await _shoot_at(bot, spot[0], spot[1], spot[2], hour, true)
	await bot.admin("hour 12")
	for at: Vector2i in TOWN_SPOTS:
		await _shoot_at(bot, "wilds", at, "Umbrage's forest edge", 12, false)
	# Townsfolk asleep (751): on beds indoors, on bedrolls by the fire.
	await bot.admin("hour 1")
	await bot.seconds(60.0)
	for body: GridEntity in bot.seen("Resident"):
		bot.log_line("  %s %s at %s" % [bot.label(body), str(body.get("activity")), body.tile])
	for at: Vector2i in SLEEP_SPOTS:
		await _shoot_at(bot, "wilds", at, "sleepers", 1, false, [0.0, 180.0])
	await bot.admin("hour 12")


func _shoot_at(bot: Node, zone_name: String, at: Vector2i, words: String, hour: int, low: bool, yaws: Array = YAWS) -> void:
	if bot.zone() != zone_name:
		await bot.admin("zone move Tourbot %s" % zone_name)
		if not await bot.until(func() -> bool: return bot.zone() == zone_name, 40.0):
			bot.expect(false, "moved to %s for %s" % [zone_name, words], "still in %s" % bot.zone())
			return
		await bot.settled()
	await bot.walk_to(at, 2, 90.0)
	bot.log_line("%s: at %s (wanted %s), hour %d" % [words, bot.cell(), at, hour])
	for yaw: float in yaws:
		var name := "%s_%d_%d_h%d_y%d" % [zone_name, at.x, at.y, hour, int(yaw)]
		var path: String = await bot.still(name, yaw, low)
		if path.is_empty():
			continue
		var md5 := FileAccess.get_md5(path)
		bot.expect(md5 != _last_md5, "still %s drew a new frame" % name, "the same image as the one before")
		_last_md5 = md5
