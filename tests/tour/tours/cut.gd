extends RefCounted
## The cut tour (playtest): what a bot can check of a cut's checklist,
## through the client's own paths. Today's lines (the 11-01 cut): the world
## map's key and button, the purse following gold, townsfolk asleep, and the
## barrow's ways out (749's arrival). What needs eyes (the sledge's swing,
## seams, the forest floor) goes to stills, not here.

## The wilds' link to the barrow, and the barrow's links (its level.json).
const WILDS_BARROW_LINK := Vector2i(170, 180)
const BARROW_TO_WILDS := Vector2i(40, 1)
const BARROW_TO_DEEP := Vector2i(52, 16)
## How far from the mound a way out of the barrow may set me down.
const MOUND_REACH := 6


func run(bot: Node) -> void:
	await _world_map(bot)
	await _purse(bot)
	await _sleepers(bot)
	await _ways_out(bot)


## J opens and closes the world map; the "World map" button under the corner
## map opens it; M with it open gives way to the zone's map (445 amended).
func _world_map(bot: Node) -> void:
	var main: Node = bot.main
	var panel: Control = main.get("world_map_panel")
	if not bot.expect(panel != null, "the world map panel exists"):
		return
	await bot.key(KEY_J)
	await bot.seconds(0.5)
	bot.expect(panel.visible, "J opens the world map")
	await bot.key(KEY_J)
	await bot.seconds(0.5)
	bot.expect(not panel.visible, "J again closes the world map")
	var pressed: bool = bot.press("World map")
	bot.expect(pressed, "a \"World map\" button is up", "buttons: %s" % ", ".join(bot.buttons().map(func(b: Dictionary) -> String: return str(b["text"]))).left(300))
	await bot.seconds(0.5)
	if pressed:
		bot.expect(panel.visible, "the \"World map\" button opens the world map")
	var minimap: Node = main.get("minimap")
	await bot.key(KEY_M)
	await bot.seconds(0.5)
	bot.expect(not panel.visible and minimap != null and bool(minimap.get("big")), "M with the world map open shows the zone's map instead",
		"world map %s, zone map big %s" % [panel.visible, minimap.get("big") if minimap != null else "-"])
	await bot.key(KEY_M)
	await bot.seconds(0.5)
	bot.expect(minimap != null and not bool(minimap.get("big")), "M again closes the zone's map")


## Gold given outside any shop reaches the client's purse (736 amended).
func _purse(bot: Node) -> void:
	# The console's gold gives (adds); never takes.
	var start := int(bot.main.gold)
	var amount := start
	for given: int in [37, 120]:
		await bot.admin("gold Tourbot %d tour" % given)
		amount += given
		var got: bool = await bot.until(func() -> bool: return int(bot.main.gold) == amount, 5.0)
		bot.expect(got, "the purse follows gold given: %d" % amount, "the client's purse reads %d" % int(bot.main.gold))
		var shown: bool = bot.texts().any(func(text: String) -> bool: return text.strip_edges() == str(amount) or ("%d gold" % amount) in text.to_lower())
		bot.log_line("  purse %d on screen: %s" % [amount, shown])


## At night (751): townsfolk lie down under a roof or by the fire, say
## nothing, and a click tells me "<Name> is asleep."
func _sleepers(bot: Node) -> void:
	await bot.admin("hour 1")
	var any: bool = await bot.until(func() -> bool: return not _sleeping(bot).is_empty(), 30.0)
	if not bot.expect(any, "townsfolk are asleep at night", "%d residents seen" % bot.seen("Resident").size()):
		await bot.admin("hour 9")
		return
	# Bedtime is not all at once: a minute for the rest to lie down.
	await bot.seconds(60.0)
	var sleepers: Array = _sleeping(bot)
	for body: GridEntity in sleepers:
		bot.log_line("  asleep: %s at %s" % [bot.label(body), body.tile])
	var awake: Array = bot.seen("Resident").filter(func(e: GridEntity) -> bool: return str(e.get("activity")) != "sleep")
	for body: GridEntity in awake:
		bot.log_line("  up: %s at %s (%s)" % [bot.label(body), body.tile, e_activity(body)])
	var clicked := 0
	for body: GridEntity in sleepers:
		if clicked >= 3 or not is_instance_valid(body):
			break
		# Stamped before the walk: a walk's click on their cell is a click on them.
		var since: int = bot.now_msec()
		await bot.walk_to(body.tile, 2, 40.0)
		if not is_instance_valid(body):
			continue
		var path := String(body.get_path())
		var person := str(body.get("person"))
		await bot.click(body.tile)
		await bot.seconds(3.0)
		var said: Array = bot.heard_from(path, since)
		bot.expect(said.is_empty(), "%s, asleep, says nothing when clicked" % person, "said %s" % str(said).left(200))
		# One of voice's lines (townsfolk.json "asleep"), with their name.
		var lines: Array = bot.told_since(since, person)
		bot.expect(not lines.is_empty() and ("sleep" in str(lines[0]["text"]).to_lower() or "stir" in str(lines[0]["text"]).to_lower()),
			"clicking %s tells me they are asleep" % person, "told: %s" % str(bot.told_since(since)).left(200))
		bot.expect(is_instance_valid(body) and str(body.get("activity")) == "sleep", "%s sleeps on after the click" % person)
		clicked += 1
	await bot.admin("hour 9")


func _sleeping(bot: Node) -> Array:
	return bot.seen("Resident").filter(func(e: GridEntity) -> bool: return str(e.get("activity")) == "sleep")


func e_activity(body: GridEntity) -> String:
	return str(body.get("activity"))


## Each way out of the barrow (749): to the wilds by the mound, set down by
## it; down to the Ossuary, where it is open.
func _ways_out(bot: Node) -> void:
	await bot.admin("zone move Tourbot barrow")
	if not bot.expect(await bot.until(func() -> bool: return bot.zone() == "barrow", 30.0), "moved into the barrow for its ways out"):
		return
	await bot.settled()
	bot.log_line("in the barrow at %s" % bot.cell())
	# Up the steps to the wilds.
	await bot.walk_to(BARROW_TO_WILDS, 0, 60.0)
	var out: bool = await bot.until(func() -> bool: return bot.zone() == "wilds", 20.0)
	if bot.expect(out, "the barrow's door takes me out to the wilds", "zone %s at %s" % [bot.zone(), bot.cell()]):
		await bot.settled()
		var at: Vector2i = bot.cell()
		bot.expect(World.distance(at, WILDS_BARROW_LINK) <= MOUND_REACH, "leaving the barrow sets me down by the mound",
			"at %s, %d cells from the mound at %s" % [at, World.distance(at, WILDS_BARROW_LINK), WILDS_BARROW_LINK])
		var foes: Array = bot.seen("Monster").filter(func(e: GridEntity) -> bool: return e.zone == bot.me().zone and World.distance(e.tile, at) <= 3 and int(e.get("hp")) > 0)
		bot.expect(foes.is_empty(), "no monster within 3 cells where I am set down", "near: %s" % ", ".join(foes.map(func(e: GridEntity) -> String: return "%s@%s" % [bot.label(e), e.tile])))
	# Down to the Ossuary: hidden, behind the niche; reached only if open.
	await bot.admin("zone move Tourbot barrow")
	await bot.until(func() -> bool: return bot.zone() == "barrow", 30.0)
	await bot.settled()
	var reached: bool = await bot.walk_to(BARROW_TO_DEEP, 0, 90.0)
	var deep: bool = await bot.until(func() -> bool: return bot.zone() == "barrow_deep", 15.0)
	bot.log_line("the way down at %s: %s (zone %s at %s)" % [BARROW_TO_DEEP, "taken" if deep else "not taken", bot.zone(), bot.cell()])
	if deep:
		await bot.settled()
		bot.log_line("in barrow_deep at %s" % bot.cell())
