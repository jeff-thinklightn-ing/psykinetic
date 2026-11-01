extends RefCounted
## Stills for a cut's lines read by eye (playtest), off-screen:
## sh tools/tour.sh stills --offscreen. The forest floor at the wilds' south
## edge below Umbrage (753: the pit was 6.7 m south of the town), and the
## sleepers in their huts' beds seen from inside the door, the roof hidden
## as it is for a player there (751).

## Toward the wilds' south edge below Umbrage, and either side.
const EDGE_SPOTS := [Vector2i(212, 246), Vector2i(196, 246), Vector2i(228, 246)]
## The huts by the temple (Aldous's, Snagfin's): their doors face north.
const HUTS := [Vector2i(204, 217), Vector2i(212, 219)]

var _last_md5 := ""


func run(bot: Node) -> void:
	await bot.admin("hour 12")
	for wanted: Vector2i in EDGE_SPOTS:
		# The southmost cell a route reaches in that column: the land's edge.
		var at := wanted
		for y in range(255, 200, -1):
			if not World.walk_path(bot.cell(), Vector2i(wanted.x, y), bot.me()).is_empty():
				at = Vector2i(wanted.x, y)
				break
		bot.log_line("forest edge: the southmost reachable cell in column %d is %s" % [wanted.x, at])
		await bot.walk_to(at, 1, 120.0)
		bot.log_line("forest edge: at %s (wanted %s)" % [bot.cell(), at])
		for yaw: float in [135.0, 180.0, 225.0]:
			await _still(bot, "edge_%d_%d_y%d_low" % [at.x, at.y, int(yaw)], yaw, true)
		await _still(bot, "edge_%d_%d_y180_high" % [at.x, at.y], 180.0, false)
	await bot.admin("hour 1")
	await bot.seconds(60.0)
	for hut: Vector2i in HUTS:
		var sleeper: GridEntity = null
		for body: GridEntity in bot.seen("Resident"):
			if World.distance(body.tile, hut) <= 3 and str(body.get("activity")) == "sleep":
				sleeper = body
		if sleeper == null:
			bot.log_line("hut %s: no sleeper within 3 cells" % hut)
			continue
		# Inside, beside them: not on their cell (a click there is a click on them).
		await bot.walk_to(sleeper.tile, 2, 60.0)
		bot.log_line("hut %s: %s asleep at %s, I am at %s" % [hut, bot.label(sleeper), sleeper.tile, bot.cell()])
		_bed_report(bot, sleeper)
		for yaw: float in [0.0, 90.0, 180.0, 270.0]:
			await _still(bot, "bed_%d_%d_y%d" % [hut.x, hut.y, int(yaw)], yaw, false)
	await bot.admin("hour 12")


## How the client lays a sleeper (751, Client3D._sync_bedroll): its puppet,
## the bed whose head is its cell, whether its cell is indoors; one indoors
## lies on a bed.
func _bed_report(bot: Node, sleeper: GridEntity) -> void:
	var view: Node = bot.main.get("_client3d")
	if view == null:
		bot.log_line("  no 3D view (headless): no bed report")
		return
	var puppets: Dictionary = view.get("_puppets")
	var puppet: Node3D = puppets.get(sleeper.get_instance_id())
	var bed: Dictionary = view.call("_bed_under", sleeper.tile)
	var indoors: bool = view.call("_indoors", sleeper.tile)
	var person := str(sleeper.get("person"))
	bot.log_line("  %s: cell %s facing %s, indoors %s, bed under %s, puppet at %s turned %.0f deg, bed_height %s, bedroll %s" % [person,
		sleeper.tile, sleeper.get("facing"), indoors, bed, puppet.global_position if puppet != null else "-",
		rad_to_deg(puppet.global_rotation.y) if puppet != null else 0.0, puppet.get_meta("bed_height", "-") if puppet != null else "-",
		puppet.get_meta("bedroll", "-") if puppet != null else "-"])
	for building: Variant in view.call("_drawn_buildings"):
		if building is Dictionary and (building as Dictionary).get("rect") is Rect2i and ((building as Dictionary)["rect"] as Rect2i).grow(1).has_point(sleeper.tile):
			bot.log_line("    in %s %s: beds %s" % [building.get("slot", "?"), building["rect"], building.get("beds", [])])
	bot.expect(not indoors or not bed.is_empty(), "%s, asleep indoors, lies on a bed's head cell" % person,
		"cell %s indoors with no bed's head there" % sleeper.tile)


func _still(bot: Node, name: String, yaw: float, low: bool) -> void:
	var path: String = await bot.still(name, yaw, low)
	if path.is_empty():
		return
	var md5 := FileAccess.get_md5(path)
	bot.expect(md5 != _last_md5, "still %s drew a new frame" % name, "the same image as the one before")
	_last_md5 = md5
