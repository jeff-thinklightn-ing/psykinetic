extends RefCounted
## The seam tour (playtest): stills read by eye, run off-screen
## (sh tools/tour.sh seams --offscreen). At each road between two zones, from
## a few cells inside, looking across, at noon and at dusk, the camera low;
## and around Umbrage for the forest floor (753's holes), high. The stills
## go beside the report; a still the same as the one before (an off-screen
## window that kept its frame) is flagged.

## Every way between zones (coordinator, 11-01: "grow the seam tour to every
## link"): each outdoor level's links (level.json), stood by and looked
## across, at noon and at dusk. Each zone is entered afresh for its set (the
## castle's dead took the bot within a minute at dusk on the first run).
## The plane's levels (world_plane.json, 650) are also measured along their
## edges: where two of them touch, the ground's height on either side of
## the seam must meet (an assert, EDGE_RISE), not only be looked at.
const OUTDOOR := ["wilds", "foothills", "castle", "hills", "forest", "held"]
## The most two touching cells either side of a seam may differ (metres): a
## walkable step's rise (Relief's WALK_RISE is per cell; a seam is one cell).
## Asserted within LINK_REACH of a link's crossing and where both cells are
## walkable (maps' ruling, 11-01: the rest is forest band or off-land rows,
## never crossed, the neighbour's relief never drawn beside ours); the rest
## of each seam is reported, its cells in the CSV.
const EDGE_RISE := 1.0
const LINK_REACH := 3
const YAWS := [0.0, 90.0, 180.0, 270.0]
const HOURS := [12, 19]
## Umbrage's edges, for the forest floor between the trees.
const TOWN_SPOTS := [Vector2i(212, 205), Vector2i(196, 190), Vector2i(228, 214)]
## Where the cut tour saw them lie down at 1 o'clock (Rolf and Hale; Aldous; Snagfin).
const SLEEP_SPOTS := [Vector2i(219, 195), Vector2i(204, 216), Vector2i(212, 218)]

var _last_md5 := ""


var _edges := {}  # A world cell on a level's edge: {zone, height, out: Vector2i}.


func run(bot: Node) -> void:
	for hour: int in HOURS:
		await bot.admin("hour %d" % hour)
		for zone_name: String in OUTDOOR:
			var links := _links(zone_name)
			if links.is_empty():
				continue
			if not await _enter(bot, zone_name):
				continue
			if hour == HOURS[0]:
				_measure_edges(bot, zone_name)
			for link: Dictionary in links:
				var words := "%s's way to %s%s" % [zone_name, link["to"], " (closed)" if link["closed"] else ""]
				await _shoot_at(bot, zone_name, link["at"], words, hour, true)
	_compare_edges(bot)
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


## [param zone_name]'s links: [{at, to, closed}], from its level.json.
func _links(zone_name: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://levels/%s/level.json" % zone_name))
	for link: Variant in (data.get("links", []) if data is Dictionary else []):
		var at: Variant = link.get("at")
		if at is Array and at.size() == 2:
			out.append({"at": Vector2i(int(at[0]), int(at[1])), "to": str(link.get("to_map", "?")), "closed": bool(link.get("closed", false))})
	return out


## Into [param zone_name] by the console, afresh (its start), up and standing.
func _enter(bot: Node, zone_name: String) -> bool:
	await bot.admin("zone move Tourbot %s" % zone_name)
	if not await bot.until(func() -> bool: return bot.zone() == zone_name and bot.me() != null and int(bot.me().hp) > 0, 60.0):
		bot.expect(false, "moved to %s, standing" % zone_name, "in %s, hp %s" % [bot.zone(), bot.me().get("hp") if bot.me() != null else "-"])
		return false
	await bot.settled()
	return true


## Every edge cell of this zone's ground, as world cells on the plane with
## their height (the plane's height for the level plus the cell's
## elevation, decision 525) and the way out of the level there.
func _measure_edges(bot: Node, zone_name: String) -> void:
	var plane := Level.world_plane()
	var zone: Variant = plane["zones"].get(zone_name)
	var size: Vector2i = World.get("_relief_size")
	if zone == null or size == Vector2i.ZERO:
		bot.log_line("edges: %s has no place on the plane or no relief; not measured" % zone_name)
		return
	var origin: Vector2i = zone["origin"]
	var base: float = zone["height"]
	var count := 0
	for x in size.x:
		for y in size.y:
			var outs: Array[Vector2i] = []
			if x == 0: outs.append(Vector2i(-1, 0))
			if y == 0: outs.append(Vector2i(0, -1))
			if x == size.x - 1: outs.append(Vector2i(1, 0))
			if y == size.y - 1: outs.append(Vector2i(0, 1))
			for out: Vector2i in outs:
				var cell := Vector2i(x, y)
				_edges["%s|%s" % [origin + cell, out]] = {"zone": zone_name, "cell": cell, "world": origin + cell, "out": out,
					"height": base + World.elevation_at(cell), "walk": World.is_walkable(cell)}
				count += 1
	bot.log_line("edges: %s measured, %d edge cells, size %s, origin %s, base %.2f m" % [zone_name, count, size, origin, base])


## Where two measured levels touch (a cell's way out lands on the other's
## edge cell, facing back): the heights either side within EDGE_RISE.
func _compare_edges(bot: Node) -> void:
	var plane := Level.world_plane()
	var crossings: Array[Vector2i] = []  # World cells of the links between plane levels.
	for zone_name: String in OUTDOOR:
		var zone: Variant = plane["zones"].get(zone_name)
		for link: Dictionary in _links(zone_name):
			if zone != null and plane["zones"].has(link["to"]):
				crossings.append((zone["origin"] as Vector2i) + (link["at"] as Vector2i))
	var seams := {}  # "a|b" -> {count, worst, at, heights}
	for key: String in _edges:
		var a: Dictionary = _edges[key]
		var across: Vector2i = a["world"] + a["out"]
		var back: Variant = _edges.get("%s|%s" % [across, -(a["out"] as Vector2i)])
		if back == null or back["zone"] == a["zone"] or str(a["zone"]) > str(back["zone"]):
			continue
		var pair := "%s|%s" % [a["zone"], back["zone"]]
		var seam: Dictionary = seams.get(pair, {"count": 0, "worst": 0.0, "at": Vector2i.ZERO, "heights": [], "over": 0})
		var rise := absf(float(a["height"]) - float(back["height"]))
		seam["count"] += 1
		seam["sum"] = float(seam.get("sum", 0.0)) + (float(a["height"]) - float(back["height"]))
		seam["rows"] = seam.get("rows", []) + ["%d,%d,%d,%d,%.2f,%.2f,%.2f" % [a["world"].x, a["world"].y, back["world"].x, back["world"].y,
			a["height"], back["height"], float(a["height"]) - float(back["height"])]]
		if rise > EDGE_RISE:
			seam["over"] += 1
			var world: Vector2i = a["world"]
			if crossings.any(func(c: Vector2i) -> bool: return World.distance(c, world) <= LINK_REACH):
				seam["at_link"] = seam.get("at_link", []) + ["link %s %.2f m" % [world, rise]]
			elif bool(a["walk"]) and bool(back["walk"]):
				seam["at_link"] = seam.get("at_link", []) + ["walkable %s %.2f m" % [world, rise]]
		if rise > float(seam["worst"]):
			seam["worst"] = rise
			seam["at"] = [a["zone"], a["cell"], back["zone"], back["cell"]]
			seam["heights"] = [snappedf(a["height"], 0.01), snappedf(back["height"], 0.01)]
		seams[pair] = seam
	if not bot.expect(not seams.is_empty(), "the plane's levels touch somewhere (edges measured: %d)" % _edges.size()):
		return
	for pair: String in seams:
		var seam: Dictionary = seams[pair]
		# Each seam's cells for its owner: world cells either side, heights, a - b.
		var csv := FileAccess.open(bot.out_dir.path_join("seam_%s.csv" % pair.replace("|", "_")), FileAccess.WRITE)
		if csv != null:
			csv.store_string("a_x,a_y,b_x,b_y,a_m,b_m,a_minus_b
" + "
".join(seam["rows"]) + "
")
			csv.close()
		bot.log_line("seam %s: mean a - b %.2f m over %d cells" % [pair.replace("|", "-"), float(seam["sum"]) / maxi(1, int(seam["count"])), seam["count"]])
		bot.log_line("seam %s report: %d cells along it, %d over %.1f m; the worst %.2f m at %s (heights %s)" % [pair.replace("|", "-"),
			seam["count"], seam["over"], EDGE_RISE, seam["worst"], seam["at"], seam["heights"]])
		var at_link: Array = seam.get("at_link", [])
		bot.expect(at_link.is_empty(), "the ground meets across the %s seam at its links (%d cells either way) and wherever both sides are walkable (within %.1f m)" % [pair.replace("|", "-"), LINK_REACH, EDGE_RISE],
			"over at a link: %s" % [at_link])


func _shoot_at(bot: Node, zone_name: String, at: Vector2i, words: String, hour: int, low: bool, yaws: Array = YAWS) -> void:
	if bot.zone() != zone_name and not await _enter(bot, zone_name):
		return
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
