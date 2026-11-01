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
## The robbers' camp chest (742 amended), opened only with Brand's key.
const CAMP_CHEST := Vector2i(14, 43)
const BARROW_DOOR := Vector2i(40, 1)
## Umbrage's square, by the well.
const TOWN_SQUARE := Vector2i(212, 205)

var _boss_bar_checked := false
var _chest_gold := 0


func run(bot: Node) -> void:
	await _rolf(bot)
	await _sleepers(bot)
	await _to_barrow(bot)
	await _knight(bot)
	await _names(bot)
	await _fights(bot)
	await _chest(bot)
	await _turn_in(bot)
	await _out_to_rolf(bot)


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
	var since: int = bot.now_msec()
	var deaths := 0
	var bosses := {}
	while bot.now_msec() < end:
		for boss: GridEntity in bot.seen("robber").filter(func(e: GridEntity) -> bool: return e.get("boss") == true):
			bosses[boss.get_instance_id()] = str(boss.get("given_name"))
		if not _boss_bar_checked and bot.me() != null and bot.zone() == "barrow":
			await _boss_bar(bot)
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
			foes = foes.filter(func(e: GridEntity) -> bool: return not e.get("boss") == true)
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
	# Brand's swings as the client saw them, whoever he swung at.
	bot.expect(not bosses.is_empty(), "a boss was seen in the barrow")
	for id: int in bosses:
		_sledge(bot, bosses[id], id, since)


## Brand's keys in my pack.
func _keys(bot: Node) -> int:
	return (Array(bot.me().get("slots")) if bot.me() != null else []).count("camp_key")


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


## The boss bar (752, ui's) with the boss's name, once he is within
## BossBar.SIGHT: checked the first time a living boss is in sight.
func _boss_bar(bot: Node) -> void:
	var bosses: Array = bot.seen("robber").filter(func(e: GridEntity) -> bool: return e.get("boss") == true and int(e.get("hp")) > 0)
	if bosses.is_empty():
		return
	_boss_bar_checked = true
	var boss: GridEntity = bosses[0]
	var given := str(boss.get("given_name"))
	await bot.walk_to(boss.tile, BossBar.SIGHT - 2, 30.0)
	var bar: Control = bot.main.get("boss_bar")
	var shown: bool = await bot.until(func() -> bool: return bar != null and bar.is_visible_in_tree(), 5.0)
	bot.expect(shown and given in ", ".join(bot.texts(bar)), "%s's boss bar is up with his name when he is near" % given,
		"bar %s, reads %s, %s cells off" % ["shown" if shown else "hidden", bot.texts(bar) if bar != null else [],
		World.distance(bot.cell(), boss.tile) if is_instance_valid(boss) else "-"])


## The Tomb Sledge's swing (750): Brand winds up 0.9 s (9 ticks) before the
## blow falls, and stands planted 0.8 s after it, as the client saw him.
func _sledge(bot: Node, given: String, boss_id: int, since: int) -> void:
	var his: Array = bot.blows.filter(func(b: Dictionary) -> bool: return b["who"] == boss_id and b["msec"] >= since)
	var winds: Array = his.filter(func(b: Dictionary) -> bool: return b["kind"] == "winding" and int(b["ticks"]) > 0)
	var gaps: Array = []
	var after: Array = []
	for wind: Dictionary in winds:
		var next_swing: Array = his.filter(func(b: Dictionary) -> bool: return b["kind"] == "swung" and b["msec"] >= wind["msec"])
		if next_swing.is_empty():
			continue
		gaps.append(int(next_swing[0]["msec"]) - int(wind["msec"]))
		var next_wind: Array = his.filter(func(b: Dictionary) -> bool: return b["kind"] == "winding" and b["msec"] > next_swing[0]["msec"])
		if not next_wind.is_empty():
			after.append(int(next_wind[0]["msec"]) - int(next_swing[0]["msec"]))
	if winds.is_empty():
		bot.log_line("  this %s never wound up in view (%d of his blows seen)" % [given, his.size()])
		return
	var ticks: Array = winds.map(func(b: Dictionary) -> int: return int(b["ticks"]))
	bot.log_line("%s's sledge: %d wind-ups, ticks %s, wind-up to blow (ms) %s, blow to next wind-up (ms) %s" % [given, winds.size(), ticks, gaps, after])
	if not bot.expect(not winds.is_empty(), "%s winds the sledge up before he swings" % given, "%d of his blows seen" % his.size()):
		return
	bot.expect(ticks.all(func(t: int) -> bool: return t == 9), "%s's sledge winds up 0.9 s (9 ticks)" % given, "ticks %s" % [ticks])
	if gaps.is_empty():
		bot.log_line("  no blow of his seen after a wind-up (gone from view, or felled first)")
		return
	bot.expect(gaps.all(func(g: int) -> bool: return g >= 750 and g <= 1200),
		"%s's blow falls about 0.9 s after his wind-up, as drawn" % given, "gaps %s ms" % [gaps])
	bot.expect(after.all(func(g: int) -> bool: return g >= 800), "%s stands planted at least 0.8 s after a blow" % given, "blow to next wind-up %s ms" % [after])


## Brand's key and the camp chest (742 amended): whoever fells Brand, me or
## my companion, I have his key; the chest takes it and pays its gold
## straight into my purse, once; again, it is empty.
func _chest(bot: Node) -> void:
	# Brand still up after the fights: gone after on purpose (his key is the chest's).
	var end: int = bot.now_msec() + 300000
	while bot.server_lines("[named] Brand the Ox fell").is_empty() and bot.now_msec() < end:
		if bot.me() == null or bot.zone() != "barrow" or int(bot.me().hp) <= 0:
			if not await _back_in(bot):
				return
			continue
		var brand: GridEntity = null
		for body: GridEntity in bot.seen("robber"):
			if body.get("boss") == true and int(body.get("hp")) > 0:
				brand = body
		if brand == null:
			await bot.walk_to(CAMP_CHEST, 4, 60.0)  # His camp, by the chest.
			await bot.guard(5.0)
			continue
		bot.log_line("after Brand at %s" % brand.tile)
		await bot.fight(brand, 120.0)
	if bot.server_lines("[named] Brand the Ox fell").is_empty():
		bot.expect(false, "Brand falls (for his key)", "still up after 5 minutes more")
		return
	if bot.zone() != "barrow" or bot.me() == null or int(bot.me().hp) <= 0:
		if not await _back_in(bot):
			return
	var has_key: bool = "camp_key" in str(bot.me().get("slots"))
	if not bot.expect(has_key, "Brand's key is in my pack once he fell", "slots %s" % str(bot.me().get("slots")).left(200)):
		return
	# The band camps by its chest: whoever is there (Brand again, risen) fought first.
	for round in 6:
		await bot.walk_to(CAMP_CHEST, 6, 60.0)
		if bot.me() == null or int(bot.me().hp) <= 0 or bot.zone() != "barrow":
			if not await _back_in(bot):
				return
			continue
		var near: GridEntity = bot.nearest_foe(8)
		if near == null:
			break
		bot.log_line("by the chest: %s at %s" % [bot.label(near), near.tile])
		await bot.fight(near, 90.0)
	var chests: Array = bot.seen("Chest").filter(func(e: GridEntity) -> bool: return World.distance(e.tile, CAMP_CHEST) <= 2)
	if not bot.expect(not chests.is_empty(), "the robbers' camp chest is by %s" % CAMP_CHEST):
		return
	var chest: GridEntity = chests[0]
	if not "camp_key" in str(bot.me().get("slots")):
		bot.expect(false, "Brand's key is still in my pack at the chest", "slots %s" % str(bot.me().get("slots")).left(200))
		return
	await bot.walk_to(chest.tile, 1, 90.0)
	if not World.can_melee(bot.cell(), chest.tile):
		await bot.click(chest.tile)  # A left click on a chest walks beside it.
		await bot.until(func() -> bool: return World.can_melee(bot.cell(), chest.tile), 15.0)
	bot.log_line("at the chest: %s (beside it %s)" % [bot.cell(), World.can_melee(bot.cell(), chest.tile)])
	var before := int(bot.main.gold)
	var since: int = bot.now_msec()
	var keys_before := _keys(bot)
	await bot.key(KEY_E, chest.tile)
	await bot.seconds(3.0)
	var lines: Array = bot.told_since(since, "gold")
	var found := 0
	if not lines.is_empty():
		var hit := RegEx.create_from_string("([0-9]+) gold").search(str(lines[0]["text"]))
		found = int(hit.get_string(1)) if hit != null else 0
	if not bot.expect(found > 0, "Brand's key opens the chest and I am told the gold", "told: %s" % str(bot.told_since(since)).left(240)):
		return
	var paid: bool = await bot.until(func() -> bool: return int(bot.main.gold) == before + found, 3.0)
	bot.expect(paid, "the chest's %d gold is in my purse" % found, "purse %d -> %d" % [before, int(bot.main.gold)])
	# One key used: Brand risen and fallen again gives another (Main._quest_credit).
	bot.expect(_keys(bot) == keys_before - 1, "one key is used up in the lock", "keys %d -> %d; slots %s" % [keys_before, _keys(bot), str(bot.me().get("slots")).left(200)])
	_chest_gold = found
	since = bot.now_msec()
	await bot.key(KEY_E, chest.tile)
	await bot.seconds(2.0)
	bot.expect(not bot.told_since(since, "empty").is_empty(), "searched again, the chest is empty", "told: %s" % str(bot.told_since(since)).left(200))
	bot.expect(int(bot.main.gold) == before + found, "nothing more from it", "purse %d" % int(bot.main.gold))


## The knight's quest handed in, once every name on the tracker is ticked.
func _turn_in(bot: Node) -> void:
	if bot.zone() != "barrow" and not await _back_in(bot):
		return
	if not _unticked(bot).is_empty():
		await _finish_band(bot)
	var quest: Dictionary = bot.me().get("quest") if bot.me() != null else {}
	if not bot.expect(not quest.is_empty() and bool(quest.get("ready", false)), "every Mound-breaker is down: the quest is ready to hand in",
			"left %s" % [_unticked(bot)]):
		return
	if bot.zone() != "barrow" and not await _back_in(bot):
		return
	var knight: GridEntity = bot.find("AstralKnight")
	if not bot.expect(knight != null, "the knight is there to hand the quest in to"):
		return
	await bot.walk_to(knight.tile, 2, 90.0)
	var before := int(bot.main.gold)
	await bot.click(knight.tile)
	await bot.seconds(2.0)
	_list_buttons(bot, "the knight, the quest ready")
	var since: int = bot.now_msec()
	# The step's button is the step's own words (AstralKnight.TURN_IN_TITLE).
	var pressed: bool = bot.press("robbers are put down")
	await bot.seconds(3.0)
	bot.expect(pressed and (bot.me().get("quest") as Dictionary).is_empty(), "handing the quest in clears the tracker",
		"pressed %s; quest %s" % [pressed, str(bot.me().get("quest")).left(200)])
	# His reward is the way below (AstralKnight.REVEALED): the hidden niche's door.
	var said: Array = bot.heard.filter(func(line: Dictionary) -> bool:
		return line["msec"] >= since and "breathes cold air" in str(line["text"]))
	bot.expect(not said.is_empty(), "the knight reveals the way below at the turn-in",
		"heard since: %s" % [bot.heard.filter(func(l: Dictionary) -> bool: return l["msec"] >= since).map(func(l: Dictionary) -> String: return str(l["text"]).left(80))])
	for each: Dictionary in bot.told_since(since):
		bot.log_line("told at the turn-in: %s" % each["text"])
	# His closing words (AstralKnight.DONE: a greeting with nothing left to
	# offer): his window closed, then he is talked to again.
	bot.press("close")
	await bot.seconds(1.0)
	await bot.click(knight.tile)
	await bot.seconds(3.0)
	var closing: Array = bot.told_since(since, "way below is open") + bot.heard.filter(func(line: Dictionary) -> bool:
		return line["msec"] >= since and "way below is open" in str(line["text"]))
	bot.expect(not closing.is_empty(), "talked to again, the knight's closing words: the way below is open",
		"told since: %s" % [bot.told_since(since).map(func(l: Dictionary) -> String: return str(l["text"]).left(80))])
	bot.press("close")
	bot.log_line("purse %d -> %d at the turn-in" % [before, int(bot.main.gold)])


## Every name made ticked before the turn-in (coordinator, 11-01): one who
## got away by a door (decision 702) is gone till his spawn returns, so the
## console's "respawn" brings the dead back now and the barrow is swept,
## its floor visited a waypoint at a time, for the names still unticked;
## each fought down. Three sweeps at most, 10 minutes in all.
func _finish_band(bot: Node) -> void:
	var end: int = bot.now_msec() + 600000
	for sweep in 3:
		if _unticked(bot).is_empty() or bot.now_msec() > end:
			break
		bot.log_line("sweep %d for %s: %s" % [sweep + 1, _unticked(bot), await bot.admin("respawn")])
		var points := _waypoints(bot)
		while not points.is_empty() and bot.now_msec() < end and not _unticked(bot).is_empty():
			if bot.me() == null or int(bot.me().hp) <= 0 or bot.zone() != "barrow":
				if not await _back_in(bot):
					return
				points = _waypoints(bot)
				continue
			var foe := _named_in_sight(bot)
			if foe != null:
				var given := str(foe.get("given_name"))
				bot.log_line("found %s at %s" % [given, foe.tile])
				var result: String = await bot.fight(foe, 120.0)
				if result == "won":
					await bot.seconds(1.0)
					bot.expect(not given in _unticked(bot), "%s is ticked on the tracker once felled" % given, "left: %s" % [_unticked(bot)])
				elif result in ["escaped", "lost", "timeout"]:
					await _hold_the_door(bot, given)
				continue
			var near: GridEntity = bot.nearest_foe(3)
			if near != null:
				await bot.fight(near, 60.0)  # One in the way.
				continue
			points.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return World.distance(a, bot.cell()) < World.distance(b, bot.cell()))
			var to: Vector2i = points.pop_front()
			await bot.walk_to(to, 3, 40.0)
	bot.log_line("the band after the sweeps: left %s" % [_unticked(bot)])


## [param given] ran (decision 702: the band flees by the barrow's door):
## the bot to the door, ahead of him if it can, and he is fought there.
func _hold_the_door(bot: Node, given: String) -> void:
	bot.log_line("%s ran; to the door to cut him off" % given)
	await bot.walk_to(BARROW_DOOR + Vector2i(0, 2), 1, 40.0)
	var end: int = bot.now_msec() + 45000
	while bot.now_msec() < end and given in _unticked(bot) and bot.zone() == "barrow":
		var foe := _named_in_sight(bot)
		if foe != null and World.distance(foe.tile, bot.cell()) <= 8:
			bot.log_line("at the door: %s at %s" % [str(foe.get("given_name")), foe.tile])
			await bot.fight(foe, 60.0)
			await bot.seconds(1.0)
			continue
		await bot.frames(5)
	if given in _unticked(bot):
		bot.log_line("%s %s" % [given, "got away" if not bot.server_lines("got away").is_empty() else "never came to the door"])


## An unticked name of the band in sight, or null.
func _named_in_sight(bot: Node) -> GridEntity:
	var left := _unticked(bot)
	for each: GridEntity in bot.seen("robber"):
		if each is Monster and int(each.get("hp")) > 0 and str(each.get("given_name")) in left:
			return each
	return null


## The barrow's floor as waypoints about 10 cells apart, each reachable.
func _waypoints(bot: Node) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for at: Vector2i in World.floor_cells():
		if out.any(func(p: Vector2i) -> bool: return World.distance(p, at) < 10):
			continue
		if World.walk_path(bot.cell(), at, bot.me()).is_empty():
			continue
		out.append(at)
	return out


## Out through the barrow's door to the wilds, and to Rolf with the purse
## the chest filled: his wares can be bought with it (the real path of the
## 10-31 purse bug: gold from a chest, then a shop).
func _out_to_rolf(bot: Node) -> void:
	if _chest_gold <= 0:
		bot.log_line("no chest gold: the purse path is not walked")
		return
	if bot.zone() == "barrow":
		# Hurt from the fights, maybe down and bleeding: said, so a fall on the way reads as one.
		if bot.me() != null and int(bot.me().hp) > 0:
			bot.log_line("hp %s before the walk out" % bot.me().hp)
		var walk_since: int = bot.now_msec()
		await bot.walk_to(BARROW_DOOR, 0, 120.0)
		var out: bool = await bot.until(func() -> bool: return bot.zone() == "wilds", 20.0)
		await bot.settled()
		# Down on the way: the revival's word comes a moment after the arrival.
		await bot.until(func() -> bool: return not bot.told_since(walk_since, "brought you back").is_empty(), 3.0)
		var revived: bool = not bot.told_since(walk_since, "brought you back").is_empty()
		if revived:
			# Down on the way and brought back at the temple: not the door's arrival.
			bot.log_line("down on the way out; brought back in %s at %s, the mound's arrival not seen" % [bot.zone(), bot.cell()])
		elif not bot.expect(out, "out through the barrow's door", "zone %s at %s" % [bot.zone(), bot.cell()]):
			return
		await bot.settled()
		if not revived:
			bot.expect(World.distance(bot.cell(), BARROW_LINK) <= 6, "set down by the mound", "at %s" % bot.cell())
	await bot.admin("hour 12")
	# The town is out of view from the mound: to the square, then find him.
	await bot.walk_to(TOWN_SQUARE, 3, 120.0)
	await bot.until(func() -> bool: return bot.find("Rolf") != null, 60.0)
	var rolf: GridEntity = bot.find("Rolf")
	if not bot.expect(rolf != null, "Rolf is in the town after the barrow", "at %s" % bot.cell()):
		return
	await bot.walk_to(rolf.tile, 2, 120.0)
	await bot.click(rolf.tile)
	await bot.seconds(2.0)
	var buys: Array = bot.buttons().filter(func(b: Dictionary) -> bool: return "gold" in String(b["text"]).to_lower() or "buy" in String(b["text"]).to_lower())
	var enabled: Array = buys.filter(func(b: Dictionary) -> bool: return not b["disabled"])
	bot.expect(not enabled.is_empty(), "with the chest's gold (purse %d), Rolf's wares can be bought" % int(bot.main.gold),
		"%d of %d ware buttons on" % [enabled.size(), buys.size()])
