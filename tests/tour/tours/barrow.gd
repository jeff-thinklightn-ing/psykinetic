extends RefCounted
## The barrow tour (playtest): the route Jeff played on v0.1.194, from
## the wilds' town (Umbrage's store) to the barrow, through the fallen
## knight's quest, with the companion along. First cut: Rolf's stall, the
## walk to the barrow, the arrival, the knight and his quest window.

## The wilds' link to the barrow and where the barrow's arrival is.
const BARROW_LINK := Vector2i(170, 180)
const BARROW_ARRIVAL := Vector2i(40, 2)
## The fallen knight's post, below the Altar Room's altar (747).
const KNIGHT_AT := Vector2i(38, 32)
## How far from its link's arrival a crossing may land a player.
const ARRIVAL_REACH := 4


func run(bot: Node) -> void:
	await _rolf(bot)
	await _sleepers(bot)
	await _to_barrow(bot)
	await _knight(bot)
	await _names(bot)
	await _fights(bot)


## Rolf the vendor (736): talked to, his window has buttons that buy.
func _rolf(bot: Node) -> void:
	await bot.admin("gold Tourbot 50 tour")
	await bot.until(func() -> bool: return bot.find("Rolf") != null, 90.0)
	var rolf: GridEntity = bot.find("Rolf")
	if not bot.expect(rolf != null, "Rolf is in the town"):
		_list(bot, "all seen", bot.seen())
		return
	bot.log_line("Rolf at %s" % rolf.tile)
	await bot.walk_to(rolf.tile, 2, 30.0)
	await bot.click(rolf.tile)
	await bot.seconds(2.0)
	_list_buttons(bot, "after clicking Rolf")
	var buys: Array = bot.buttons().filter(func(b: Dictionary) -> bool: return "gold" in String(b["text"]).to_lower() or "buy" in String(b["text"]).to_lower())
	if not bot.expect(not buys.is_empty(), "Rolf's window has buy buttons", "%d buttons up" % bot.buttons().size()):
		return
	var enabled: Array = buys.filter(func(b: Dictionary) -> bool: return not b["disabled"])
	bot.expect(not enabled.is_empty(), "with 50 gold, Rolf's wares can be bought", "every ware button is off; the client's purse reads %d" % int(bot.main.gold))
	if enabled.is_empty():
		# The purse the client never got (reported 2026-10-31, ui's): set to the
		# server's so the tour can go on armed; the check above stays failed.
		bot.log_line("workaround: the client's purse set to 50, Rolf clicked again")
		bot.main.gold = 50
		await bot.click(rolf.tile)
		await bot.seconds(2.0)
	var gold_before := int(bot.main.gold)
	var hands_before := str(bot.me().get("slots")) if bot.me() != null and "slots" in bot.me() else ""
	bot.press("sword")
	await bot.seconds(2.0)
	bot.press("shield")
	await bot.seconds(2.0)
	bot.log_line("purse %d -> %d" % [gold_before, int(bot.main.gold)])
	var hands_after := str(bot.me().get("slots")) if bot.me() != null and "slots" in bot.me() else ""
	bot.expect(hands_after != hands_before and "sword" in hands_after.to_lower(), "the sword is in my hands", "slots %s" % hands_after.left(200))


## Townsfolk at night (751; Jeff: they slept on bare ground in a pose that
## looked dead, and talked while asleep): one asleep, clicked, says nothing.
func _sleepers(bot: Node) -> void:
	await bot.admin("hour 1")
	var asleep := func() -> Array:
		return bot.seen("Resident").filter(func(r: GridEntity) -> bool: return str(r.get("activity")) == "sleep")
	await bot.until(func() -> bool: return not asleep.call().is_empty(), 90.0)
	var sleepers: Array = asleep.call()
	_list(bot, "asleep at 1 o'clock", sleepers)
	if not bot.expect(not sleepers.is_empty(), "someone in town is asleep at night", "%d residents seen" % bot.seen("Resident").size()):
		await bot.admin("hour 9")
		return
	var sleeper: GridEntity = sleepers[0]
	await bot.walk_to(sleeper.tile, 2, 40.0)
	var since: int = bot.now_msec()
	await bot.click(sleeper.tile)
	await bot.seconds(4.0)
	var said: Array = bot.heard_from(String(sleeper.get_path()), since)
	bot.expect(said.is_empty(), "%s, asleep, says nothing when clicked" % bot.label(sleeper),
		"; ".join(said.map(func(l: Dictionary) -> String: return str(l["text"]).left(80))))
	await bot.admin("hour 9")


func _to_barrow(bot: Node) -> void:
	var arrived: bool = await bot.walk_to(BARROW_LINK, 0, 120.0)
	await bot.until(func() -> bool: return bot.zone() == "barrow", 30.0)
	if not bot.expect(bot.zone() == "barrow", "the wilds' barrow link takes me into the barrow", "zone %s at %s (walked there: %s)" % [bot.zone(), bot.cell(), arrived]):
		return
	await bot.settled()
	var apart := World.distance(bot.cell(), BARROW_ARRIVAL)
	bot.expect(apart <= ARRIVAL_REACH, "I arrive by the barrow's door", "at %s, %d cells from %s" % [bot.cell(), apart, BARROW_ARRIVAL])


func _knight(bot: Node) -> void:
	if bot.zone() != "barrow":
		return
	var knight: GridEntity = bot.find("AstralKnight")
	if not bot.expect(knight != null, "the fallen knight is in the barrow"):
		return
	bot.log_line("knight at %s" % knight.tile)
	for door: Door in World.get_doors():
		bot.log_line("door %s open %s lock \"%s\" hp %d" % [door.key, door.open, door.lock, door.hp])
	var got_there: bool = await bot.walk_to(knight.tile, 2, 120.0)
	bot.expect(got_there, "I can walk to the knight", "at %s" % bot.cell())
	await bot.click(knight.tile)
	await bot.seconds(2.0)
	_list_buttons(bot, "after clicking the knight")
	_names_read(bot, "the knight's window and his words")
	var took: bool = bot.press("Prove")
	bot.expect(took, "the knight's window offers his quest")
	await bot.seconds(2.0)
	var quest: Dictionary = bot.me().get("quest") if bot.me() != null else {}
	bot.expect(not quest.is_empty(), "the quest tracker has his quest", str(quest).left(300))
	# The companion beside him for a while: never his foe (Jeff, v0.1.194:
	# "wren aggros against the fallen knight and starts punching him").
	var friend: GridEntity = bot.companion()
	if bot.expect(friend != null, "my companion came into the barrow with me"):
		var since: int = bot.now_msec()
		await bot.guard(15.0)
		if is_instance_valid(friend) and is_instance_valid(knight):
			bot.log_line("%s at %s, %d cells from the knight" % [bot.label(friend), friend.tile, World.distance(friend.tile, knight.tile)])
			var at_him: Array = bot.swings_at(friend, knight, since)
			bot.expect(at_him.is_empty(), "my companion never swings at the fallen knight", "%d swings at him in 15 s" % at_him.size())
		else:
			bot.log_line("my companion or the knight left the view during the watch (I am %s)" % ("standing" if bot.me() != null else "down"))
	var knight_id := knight.get_instance_id() if is_instance_valid(knight) else 0
	var hits: Array = bot.blows.filter(func(b: Dictionary) -> bool: return b["who"] == knight_id and b["kind"] == "struck")
	bot.expect(hits.is_empty(), "nobody strikes the fallen knight", "%d blows on him" % hits.size())


## The band, as a player clears the barrow: the named ones the tracker
## has not ticked, nearest first, Brand last; each felled one ticked. Going
## down is play, not a failure (the bot is a poor fighter): brought back,
## where it wakes is checked, and it walks back in. Most [param minutes].
func _fights(bot: Node, minutes := 12.0) -> void:
	var end: int = bot.now_msec() + int(minutes * 60000.0)
	var deaths := 0
	while bot.now_msec() < end:
		if bot.me() == null or bot.zone() != "barrow" or int(bot.me().hp) <= 0:
			if not await _back_in(bot):
				break
			deaths += 1
			continue
		var left := _unticked(bot)
		if (bot.me().get("quest") as Dictionary).is_empty():
			bot.log_line("no quest taken: nothing to fight for")
			break
		if left.is_empty():
			bot.log_line("the tracker ticks every name")
			break
		var foes: Array = bot.seen("robber").filter(func(e: GridEntity) -> bool:
			return e is Monster and str(e.get("given_name")) in left)
		if foes.size() > 1:
			foes = foes.filter(func(e: GridEntity) -> bool: return not bool(e.get("boss")))
		if foes.is_empty():
			bot.log_line("none of %s in sight; waiting" % [left])
			await bot.guard(10.0)
			continue
		var foe: GridEntity = foes[0]
		var given := str(foe.get("given_name"))
		var result: String = await bot.fight(foe, 120.0)
		if result == "won":
			await bot.seconds(1.0)
			bot.expect(not given in _unticked(bot), "%s is ticked on the tracker once felled" % given, "left: %s" % [_unticked(bot)])
	bot.log_line("fights over: %d times down; left %s" % [deaths, _unticked(bot)])


## The quest's names not yet ticked.
func _unticked(bot: Node) -> Array[String]:
	var out: Array[String] = []
	var quest: Dictionary = bot.me().get("quest") if bot.me() != null else {}
	for item: Dictionary in quest.get("items", []):
		if not bool(item.get("done", false)):
			out.append(str(item.get("name", "")))
	return out


## Down: waits to be brought back, says where, and walks back into the
## barrow. False if it never stood again.
func _back_in(bot: Node) -> bool:
	bot.log_line("down; waiting to be brought back")
	if not await bot.until(func() -> bool: return bot.me() != null and bot.zone() != "barrow" and int(bot.me().hp) > 0, 120.0):
		bot.expect(false, "brought back after going down", "still down after 120 s")
		return false
	bot.log_line("brought back in %s at %s" % [bot.zone(), bot.cell()])
	if bot.zone() != "wilds":
		return false
	await bot.walk_to(BARROW_LINK, 0, 120.0)
	await bot.until(func() -> bool: return bot.zone() == "barrow" and bot.me() != null, 30.0)
	await bot.settled()
	return bot.zone() == "barrow"


## The band's names over them and the boss marked (Jeff, v0.1.194: named
## robbers showed no names, the boss no marker): what the client is given.
func _names(bot: Node) -> void:
	if bot.zone() != "barrow":
		return
	var quest: Dictionary = bot.me().get("quest") if bot.me() != null else {}
	var wanted: Array = (quest.get("items", []) as Array).map(func(item: Dictionary) -> String: return str(item.get("name", "")))
	var robbers: Array = bot.seen("robber")
	_list(bot, "robbers seen", robbers)
	var named: Array[String] = []
	var bosses: Array[String] = []
	for robber: GridEntity in robbers:
		var given := str(robber.get("given_name")) if "given_name" in robber else ""
		if not given.is_empty():
			named.append(given)
		if "boss" in robber and bool(robber.get("boss")):
			bosses.append(given if not given.is_empty() else bot.label(robber))
	var has_field: bool = not robbers.is_empty() and "given_name" in robbers[0]
	bot.expect(not named.is_empty(), "the client is told the named robbers' names",
		("named %s; the quest wants %s" % [named, wanted]) if has_field else "%d robbers seen, none with a name field" % robbers.size())
	bot.expect(not bosses.is_empty(), "Brand is marked as the boss", "bosses %s" % [bosses])


## No text up (a window's title, the talk log) and no speaker heard is a
## node's name ("AstralKnight1"): what a player reads names people.
func _names_read(bot: Node, where: String) -> void:
	var bad: Array[String] = []
	for text: String in bot.texts():
		for found: String in bot.node_names_in(text):
			if not found in bad:
				bad.append(found)
	for line: Dictionary in bot.heard:
		for found: String in bot.node_names_in(String(line["speaker"])):
			if not found in bad:
				bad.append(found)
	bot.expect(bad.is_empty(), "no node names in what I read (%s)" % where, "read: %s" % ", ".join(bad))


func _list(bot: Node, what: String, entities: Array) -> void:
	bot.log_line("%s: %s" % [what, ", ".join(entities.map(func(e: GridEntity) -> String: return "%s@%s" % [bot.label(e), e.tile]))])


func _list_buttons(bot: Node, when: String) -> void:
	var texts: Array = bot.buttons().map(func(b: Dictionary) -> String: return "%s%s" % [b["text"], " (off)" if b["disabled"] else ""])
	bot.log_line("buttons %s: %s" % [when, ", ".join(texts)])
