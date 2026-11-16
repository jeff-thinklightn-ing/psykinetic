extends RefCounted
## The barrow tour (playtest): the route Jeff played on v0.1.194, from
## the wilds' town (Umbrage's store) to the barrow, through the fallen
## knight's quest, with the companion along. First cut: Rolf's stall, the
## walk to the barrow, the arrival, the knight and his quest window.
## In by the crypt's front door, Umbrage's temple stair (decision 715: the
## temple carries the link to the barrow's from_chapel), as a newcomer comes;
## the mound in the wilds at (160, 160) is the band's breach (from_breach),
## its back door, which arrives 51 cells from the knight.
## Run with TOUR_SERVER_ARGS=--test-hp for the count at the taking (one of
## the band felled by the console's strike before the quest is taken, ticked
## at the taking: 747 amended (8)); without it that row is said skipped.

## The temple's link to the crypt, read from the wilds as the client has it
## (_crypt_door); the mound's breach only if it is not there.
const BARROW_BREACH := Vector2i(160, 160)
## Where the crypt's door (BARROW_DOOR) sets one down in the wilds: the
## temple's from_crypt.
const TEMPLE_ARRIVAL := Vector2i(198, 199)
## Felled before the quest is taken, for the count at the taking.
const FELLED_FIRST := "tull"
const BARROW_ARRIVAL := Vector2i(40, 2)
## The fallen knight's post, by the First Hall's bier (747 amended (8); the
## Low Hall, his old room, gone since 747 amended (13)).
const KNIGHT_AT := Vector2i(39, 10)
## How far from its link's arrival a crossing may land a player.
const ARRIVAL_REACH := 4
## The robbers' camp chest (742 amended), opened only with Brand's key.
const CAMP_CHEST := Vector2i(14, 43)
const BARROW_DOOR := Vector2i(40, 1)
## Umbrage's square, by the well.
const TOWN_SQUARE := Vector2i(212, 205)

var _boss_bar_checked := false
var _chest_gold := 0
var _phase := 1


func run(bot: Node) -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--tour-phase="):
			_phase = int(arg.trim_prefix("--tour-phase="))
	if _phase > 1:  # After a server restart (TOUR_PHASES=2): the knight talked to again.
		await _after_restart(bot)
		return
	if OS.get_environment("TOUR_ONLY") == "knight":  # His talk before and during the quest, then saved.
		await _to_barrow(bot)
		await _knight(bot)
		# Handed in, as a player who did it on 194-196 is (its mark, Main.QUEST_DONE,
		# set by the console: the band not fought here), then talked to.
		bot.log_line("setup: %s" % await bot.admin("mark Tourbot barrow_quest"))
		await bot.seconds(2.0)
		bot.press("close")
		# The mark is the whole circle done, his remains laid (896, the altar step on).
		await _talk_knight(bot, "after the quest (its mark set)", "", AstralKnight.DONE_LAID, true)
		bot.press("close")
		await _keep_knight(bot, true)
		return
	if OS.get_environment("TOUR_ONLY") == "niche":  # The cold niche alone, the quest's mark set by the console.
		await _to_barrow(bot)
		await _niche_shut(bot)
		bot.log_line("setup: %s" % await bot.admin("mark Tourbot barrow_quest"))
		await bot.seconds(2.0)
		await _niche(bot)
		return
	if OS.get_environment("TOUR_ONLY") == "wall":  # A cut's line: the wall turn alone.
		await _to_barrow(bot)
		await _wall_turn(bot)
		bot.expect(int(bot.flips["most"]) < 6, "no long walk-flip in the run (longest %d)" % int(bot.flips["most"]))
		return
	await _rolf(bot)
	await _sleepers(bot)
	await _to_barrow(bot)
	await _niche_shut(bot)
	await _knight(bot)
	await _names(bot)
	await _fights(bot)
	await _wall_turn(bot)  # The band down: the camp's way quiet.
	await _chest(bot)
	await _turn_in(bot)
	await _niche(bot)
	await _keep_knight(bot)
	await _out_to_rolf(bot)
	# 724 amended: no walk this tour stepped back and forth on the spot.
	bot.expect(int(bot.flips["most"]) < 6, "no walk paced back and forth between two cells (6 flips or more)",
		"the longest run %d flips between %s at %.1f s" % [bot.flips["most"], bot.flips["cells"], int(bot.flips["msec"]) / 1000.0])


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
	# The barter window's store layout (560; ui, 11-16): no Buy button, one click on a
	# ware's square buys it at its price (StoreView.square_pressed, as a click emits).
	var panel: BarterPanel = bot.main.get("barter_panel")
	var wares: Array = panel.boxes_shown() if panel != null else []
	bot.log_line("Rolf's wares: %s" % [wares])
	if not bot.expect(not wares.is_empty(), "Rolf's window shows his wares", "%d squares" % wares.size()):
		return
	var gold_before := int(bot.main.gold)
	var hands_before := str(bot.me().get("slots")) if bot.me() != null and "slots" in bot.me() else ""
	var sword := ""
	for shown: String in wares:  # "ware <id> gold <cost>"
		if shown.get_slice(" ", 1).ends_with("|sword"):
			sword = shown.get_slice(" ", 1)
	var cost := int(panel.ware_entry(sword).get("cost", -1)) if not sword.is_empty() else -1
	if bot.expect(not sword.is_empty() and cost >= 0 and cost <= gold_before, "with 50 gold, Rolf's sword is within the purse",
			"sword \"%s\", cost %d, the client's purse %d" % [sword, cost, gold_before]):
		panel._store_view.square_pressed.emit("ware", sword)
		await bot.seconds(2.0)
		bot.expect(int(bot.main.gold) == gold_before - cost, "a click on the sword's square buys it: the purse falls by its price",
			"purse %d -> %d, cost %d; why \"%s\"" % [gold_before, int(bot.main.gold), cost, panel.why_shown()])
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


## The wilds' link into the crypt by the temple (to_map barrow, to_spawn
## from_chapel), from the level the client holds; the breach if none.
func _crypt_door(bot: Node) -> Vector2i:
	var level: Dictionary = bot.main.get("level") if bot.main.get("level") is Dictionary else {}
	for link: Dictionary in level.get("links", []):
		if str(link.get("to_map", "")) == "barrow" and str(link.get("to_spawn", "")) == "from_chapel":
			return link["tile"]
	bot.log_line("no temple link to the crypt in the client's level; the breach instead")
	return BARROW_BREACH


func _to_barrow(bot: Node) -> void:
	var door := _crypt_door(bot)
	bot.log_line("the crypt's door by the temple at %s" % door)
	var arrived: bool = await bot.walk_to(door, 0, 120.0)
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
	_one_knight_at_bier(bot, knight)
	_guard_room_gone(bot)
	await _talk_knight(bot, "before the quest", AstralKnight.ASK_TITLE)
	_names_read(bot, "the knight's window and his words")
	# The count at the taking (747 amended (8)): one of the band felled before.
	var struck: String = await bot.admin("strike Tourbot %s" % FELLED_FIRST)
	var felled_first: bool = struck.begins_with("strike: Tourbot struck")
	bot.log_line("before the taking: %s" % (struck if felled_first else "count at the taking skipped (%s)" % struck.left(80)))
	await bot.seconds(1.0)
	var took: bool = bot.press("Prove")
	bot.expect(took, "the knight's window offers his quest")
	await bot.seconds(2.0)
	var quest: Dictionary = bot.me().get("quest") if bot.me() != null else {}
	bot.expect(not quest.is_empty(), "the quest tracker has his quest", str(quest).left(300))
	if felled_first:
		var first := FELLED_FIRST.capitalize()
		var ticked: Array = (quest.get("items", []) as Array).filter(func(item: Dictionary) -> bool:
			return str(item.get("name", "")) == first and bool(item.get("done", false)))
		bot.expect(not ticked.is_empty(), "%s, felled before the quest was taken, is ticked at the taking" % first, str(quest.get("items", [])).left(300))
	bot.press("close")
	await bot.seconds(1.0)
	await _talk_knight(bot, "during the quest", AstralKnight.NOT_YET_TITLE, AstralKnight.NOT_YET)
	bot.press("close")
	await bot.seconds(1.0)
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


## Jeff's "astral knight still in wrong room" (11-14; 747 amended (13)): one
## fallen knight among the bodies the client knows, standing within 2 cells
## of the First Hall's bier (the burial table nearest him in the client's
## level).
func _one_knight_at_bier(bot: Node, knight: GridEntity) -> void:
	var knights: Array = bot.seen("AstralKnight")
	bot.expect(knights.size() == 1, "one fallen knight in the barrow, as the client knows it",
		"%d: %s" % [knights.size(), knights.map(func(k: GridEntity) -> String: return "%s@%s" % [bot.label(k), k.tile])])
	var level: Dictionary = bot.main.get("level") if bot.main.get("level") is Dictionary else {}
	var nearest := -1
	var bier := Rect2i()
	for entry: Variant in level.get("buildings", []):
		if not entry is Dictionary or str((entry as Dictionary).get("slot", "")) != "building.burial_table":
			continue
		var rect: Variant = Level.building_rect(entry)
		if not rect is Rect2i:
			continue
		var r: Rect2i = rect
		var near := Vector2i(clampi(knight.tile.x, r.position.x, r.end.x - 1), clampi(knight.tile.y, r.position.y, r.end.y - 1))
		var apart := World.distance(knight.tile, near)
		if nearest < 0 or apart < nearest:
			nearest = apart
			bier = r
	bot.expect(nearest >= 0 and nearest <= 2, "the fallen knight stands by the First Hall's bier", "at %s; the nearest bier %s, %d cells off" % [knight.tile, bier, nearest])


## Jeff's "remove it all together" (11-14, the room with two guards, a chest
## and a knight; 747 amended (13)): every cell of the barrow block's "rock"
## (its place) is no floor on the client's map, and no body stands in it.
func _guard_room_gone(bot: Node) -> void:
	var rocks: Array = Regen.config_of("barrow").get("rock", [])
	if not bot.expect(not rocks.is_empty(), "the barrow's block names the old guard room's place (its \"rock\")"):
		return
	for each: Variant in rocks:
		var rect := Rect2i(int(each[0]), int(each[1]), int(each[2]), int(each[3]))
		var floor: Array[Vector2i] = []
		for cell in Level.rect_cells(rect):
			if World.is_walkable(cell):
				floor.append(cell)
		var inside: Array = bot.seen().filter(func(e: GridEntity) -> bool: return rect.has_point(e.tile))
		bot.expect(floor.is_empty() and inside.is_empty(), "the old guard room's place %s is solid rock on my map, nobody in it" % rect,
			"%d floor cells %s; bodies %s" % [floor.size(), floor.slice(0, 6), inside.map(func(e: GridEntity) -> String: return "%s@%s" % [bot.label(e), e.tile])])


## The band, as a player clears the barrow: the named ones the tracker
## has not ticked, nearest first, Brand last; each felled one ticked. Going
## down is play, not a failure (the bot is a poor fighter): brought back,
## where it wakes is checked, and it walks back in. Most [param minutes].
func _fights(bot: Node, minutes := 12.0) -> void:
	var end: int = bot.now_msec() + int(minutes * 60000.0)
	var since: int = bot.now_msec()
	var deaths := 0
	var bosses := {}
	var to_camp := false
	while bot.now_msec() < end:
		for boss: GridEntity in bot.seen("robber").filter(func(e: GridEntity) -> bool: return e.get("boss") == true):
			bosses[boss.get_instance_id()] = str(boss.get("given_name"))
		if not _boss_bar_checked and bot.me() != null and bot.zone() == "barrow":
			await _boss_bar(bot)
		if bot.me() == null or bot.zone() != "barrow" or int(bot.me().hp) <= 0:
			var never_heard := _fell_heard(bot, 0).is_empty()
			if not await _back_in(bot):
				break
			deaths += 1
			to_camp = false
			if deaths == 1 and not _unticked(bot).is_empty():
				await _knight_after_fall(bot, never_heard)
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
		if foes.is_empty() and not to_camp:
			# The band keeps to its camp (Brand at the chest's post): walked to, as a
			# player goes looking, not waited for where the last fight ended.
			to_camp = true
			bot.log_line("none of %s in sight; to the camp by %s" % [left, CAMP_CHEST])
			await bot.walk_to(CAMP_CHEST, 4, 90.0)
			continue
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


## The knight's line after a fall (747 amended (15), voice's words): after the first fall
## in the barrow with his task open, his next greeting is AstralKnight.FELL, word for word
## in the joined client's talk text (his window and the line said); the greeting after it
## is "not yet" again; before any fall it was never heard ([param never_heard]).
func _knight_after_fall(bot: Node, never_heard: bool) -> void:
	bot.expect(never_heard, "before any fall the knight's line after a fall was never heard",
		"heard %s" % [_fell_heard(bot, 0).map(func(t: String) -> String: return t.left(60))])
	var since: int = bot.now_msec()
	await _talk_knight(bot, "after a fall, the quest open", "", AstralKnight.FELL, true)
	var panel: Control = bot.main.deal_panel
	var shown: String = " ".join(bot.texts(panel)) if panel != null else ""
	bot.expect(AstralKnight.FELL in shown, "after a fall: his window reads the knight's line after a fall, word for word", shown.left(300))
	bot.expect(not _fell_heard(bot, since).is_empty(), "after a fall: the line is said to me, word for word",
		"told %s" % [bot.told_since(since).map(func(l: Dictionary) -> String: return str(l["text"]).left(80))])
	bot.press("close")
	await bot.seconds(1.0)
	since = bot.now_msec()
	await _talk_knight(bot, "the greeting after that", "", AstralKnight.NOT_YET, true)
	shown = " ".join(bot.texts(panel)) if panel != null else ""
	bot.expect(not AstralKnight.FELL in shown and _fell_heard(bot, since).is_empty(),
		"the greeting after that is the ordinary one (\"not yet\"), the fall's line not again", shown.left(300))
	bot.press("close")
	await bot.seconds(1.0)


## The told and heard lines since [param since] holding AstralKnight.FELL whole.
func _fell_heard(bot: Node, since: int) -> Array:
	var out: Array = []
	var lines: Array = []
	lines.append_array(bot.told_since(since))
	lines.append_array(bot.heard.filter(func(l: Dictionary) -> bool: return l["msec"] >= since))
	for line: Dictionary in lines:
		if AstralKnight.FELL in str(line["text"]):
			out.append(str(line["text"]))
	return out


## The turn round a wall's end to a shut door (724 amended (2), physics'
## fix for the 11-01 stall: from (8, 25) toward the robbers past the door
## south of (15, 27) the body paced (15, 27)-(14, 27) for a minute). The
## barrow is regenerated: only when those doors are there; (16, 26)'s shut
## first so the route goes the wall's way. Arrives with the door opened as a
## player does (E at a stall), and no flips on the way.
const WALL_TURN_FROM := Vector2i(8, 25)
const WALL_TURN_DOOR := Vector3i(15, 27, 1)
const WALL_TURN_SIDE := Vector3i(16, 26, 0)


func _wall_turn(bot: Node) -> void:
	var door: Door = World.door_on(WALL_TURN_DOOR)
	if door == null:
		bot.log_line("wall turn: no door at %s in this generation; skipped" % WALL_TURN_DOOR)
		return
	var side: Door = World.door_on(WALL_TURN_SIDE)
	if side != null and side.open:
		await bot.walk_to(Vector2i(WALL_TURN_SIDE.x, WALL_TURN_SIDE.y), 0, 60.0)
		await bot.tap_e_door(side)
		await bot.seconds(1.0)
		bot.log_line("wall turn: the side door %s shut first: %s" % [WALL_TURN_SIDE, not side.open])
	if door.open:
		await bot.walk_to(Vector2i(WALL_TURN_DOOR.x, WALL_TURN_DOOR.y), 0, 60.0)
		await bot.tap_e_door(door)
		await bot.seconds(1.0)
	await bot.walk_to(WALL_TURN_FROM, 1, 60.0)
	var before: int = bot.flips["most"]
	bot.flips["most"] = 0
	var goal := Vector2i(WALL_TURN_DOOR.x, WALL_TURN_DOOR.y + 2)
	bot.log_line("wall turn: %s -> %s, the door %s %s" % [bot.cell(), goal, WALL_TURN_DOOR, "open" if door.open else "shut"])
	var got: bool = await bot.walk_to(goal, 1, 60.0)
	var most: int = bot.flips["most"]
	bot.flips["most"] = maxi(before, most)
	bot.expect(got and most < 6, "round the wall's end and through the shut door at %s without pacing" % WALL_TURN_DOOR,
		"arrived %s at %s; the longest flip run %d between %s" % [got, bot.cell(), most, bot.flips["cells"]])


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
	await bot.walk_to(_crypt_door(bot), 0, 120.0)
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
		# Another winding before that blow (one of 0 ticks: given up; or a new
		# one, the blow between unseen): that blow is not this wind-up's.
		var between: Array = his.filter(func(b: Dictionary) -> bool:
			return b["kind"] == "winding" and b["msec"] > wind["msec"] and b["msec"] <= next_swing[0]["msec"])
		if not between.is_empty():
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
	# 896 (the altar step, on): the band leaves the tracker and his remains are
	# its one step, to be brought to his bier.
	var after: Dictionary = bot.me().get("quest") if bot.me() != null else {}
	var steps: Array = (after.get("items", []) as Array).map(func(item: Dictionary) -> String: return str(item.get("name", "")))
	bot.expect(pressed and steps.size() == 1 and "remains" in steps[0].to_lower(), "handing the quest in leaves his remains its one step (896)",
		"pressed %s; quest %s" % [pressed, str(after).left(200)])
	# His reward is the way below (AstralKnight.REVEALED): the hidden niche's door.
	var said: Array = bot.heard.filter(func(line: Dictionary) -> bool:
		return line["msec"] >= since and "breathes cold air" in str(line["text"]))
	bot.expect(not said.is_empty(), "the knight reveals the way below at the turn-in",
		"heard since: %s" % [bot.heard.filter(func(l: Dictionary) -> bool: return l["msec"] >= since).map(func(l: Dictionary) -> String: return str(l["text"]).left(80))])
	for each: Dictionary in bot.told_since(since):
		bot.log_line("told at the turn-in: %s" % each["text"])
	# His words after the turn-in (AstralKnight.AWAIT, 896: his remains wait in
	# the Hall of Fallen Souls): his window closed, then he is talked to again.
	bot.press("close")
	await bot.seconds(1.0)
	await _talk_knight(bot, "after the band's turn-in", "", AstralKnight.AWAIT, true)
	bot.press("close")
	bot.log_line("purse %d -> %d at the turn-in" % [before, int(bot.main.gold)])


## The way below, as a player meets it (Jeff on v0.1.186, said again since:
## "the hidden niche ... doesn't activate by stepping on that tile"; 608,
## 688 amended (4), 747; the coordinator's cases, 11-16). Every press is the
## click scheme's, by real input events (Input.parse_input_event), the
## cursor put over its cell by a parsed motion (headless, the viewport reads
## Input's mouse position). Once the knight has revealed it: a tap on the
## niche's floor cell alone opens nothing; a tap on the slab, as most players
## click (press and release 0.05 s apart), from the hall and from the floor
## cell, walks me into it and opens it (the door, and the server's line); the
## held button steering into it is tried only if no tap opened it, so the
## rest is walked. The stair below takes me to barrow_deep, its way up brings
## me back. A press by E is never tried: it would hide a walk that does
## nothing.
func _niche(bot: Node) -> void:
	if bot.zone() != "barrow" and not await _back_in(bot):
		return
	var p := _niche_parts(bot)
	if p.is_empty():
		return
	if not bot.expect(not bool(p["open"]), "the slab is shut before I walk into it"):
		return
	var edge: Vector3i = p["edge"]
	await bot.walk_to(p["hall"], 0, 90.0)
	var floor_tap := await _tap_and_watch(bot, "after the turn-in, from the hall, a tap on the niche's floor cell", p["from"], edge, 4.0)
	await bot.seconds(3.0)
	var door: Door = World.door_on(edge)
	bot.expect(not floor_tap["opened"] and not (door != null and door.open), "a tap on the niche's floor cell, then standing there, opens nothing",
		"at %s; told %s" % [bot.cell(), floor_tap["told"]])
	await bot.walk_to(p["hall"], 0, 30.0)
	var from_hall := await _tap_and_watch(bot, "after the turn-in, from the hall, a tap on the slab", p["inside"], edge)
	bot.expect(from_hall["opened"], "after the turn-in, a tap on the slab from the hall walks me into it and it opens", "at %s; told %s" % [bot.cell(), from_hall["told"]])
	if from_hall["opened"]:
		await _shut_again(bot, p)
	await bot.walk_to(p["from"], 0, 30.0)
	var from_floor := await _tap_and_watch(bot, "after the turn-in, on its floor cell, a tap on the slab", p["inside"], edge)
	bot.expect(from_floor["opened"], "after the turn-in, a tap on the slab from its floor cell walks me into it and it opens", "at %s; told %s" % [bot.cell(), from_floor["told"]])
	var opened: bool = from_floor["opened"]
	if not opened:
		await bot.walk_to(p["from"], 0, 30.0)
		var since: int = bot.now_msec()
		opened = await _walk_into(bot, p["from"], p["inside"], edge, 4.0)
		bot.log_line("no tap opened it; the button held into it: %s; told %s" % ["opened" if opened else "shut", bot.told_since(since).map(func(l: Dictionary) -> String: return str(l["text"]))])
	if not opened:
		return
	var opened_at: int = bot.now_msec()
	# Down the stair: the hidden link to barrow_deep (608: under the slab).
	var stair := _link_to(bot, "barrow_deep")
	bot.log_line("the stair down: %s" % (str(stair) if stair != Vector2i(-1, -1) else "not in the client's level; walked through the niche"))
	await bot.walk_to(stair if stair != Vector2i(-1, -1) else p["inside"], 0, 60.0)
	await bot.until(func() -> bool: return bot.zone() == "barrow_deep" and bot.me() != null, 20.0)
	if not bot.expect(bot.zone() == "barrow_deep", "through the opened niche, the stair takes me down to the Ossuary's level (barrow_deep)",
			"zone %s at %s" % [bot.zone(), bot.cell()]):
		return
	var down_s: float = (bot.now_msec() - opened_at) / 1000.0
	# 608 amended (8): a click on the stair the moment the slab opens waits out the
	# finder's hold and walks on (Main._found_hold), never ended: one click.
	bot.expect(down_s < 2.0, "the stair clicked as the slab opens: down it in under 2 s, one click", "%.1f s" % down_s)
	await bot.settled()
	var up := _link_to(bot, "barrow")
	if not bot.expect(up != Vector2i(-1, -1), "the way back up is in barrow_deep's level"):
		return
	await bot.walk_to(up, 0, 60.0)
	await bot.until(func() -> bool: return bot.zone() == "barrow" and bot.me() != null, 20.0)
	bot.expect(bot.zone() == "barrow", "back up the stair into the barrow", "zone %s at %s" % [bot.zone(), bot.cell()])
	await bot.settled()


## Before the turn-in (the way not revealed to me): tapped from the hall,
## tapped from its floor cell, and walked into with the button held, the slab
## stays shut, and nothing I am told speaks of a way (no slab line, no
## draught); what I am told logged.
func _niche_shut(bot: Node) -> void:
	var p := _niche_parts(bot)
	if p.is_empty():
		return
	var edge: Vector3i = p["edge"]
	var told: Array = []
	await bot.walk_to(p["hall"], 0, 60.0)
	var a := await _tap_and_watch(bot, "before the turn-in, from the hall, a tap on the slab", p["inside"], edge)
	await bot.walk_to(p["from"], 0, 30.0)
	var b := await _tap_and_watch(bot, "before the turn-in, on its floor cell, a tap on the slab", p["inside"], edge)
	var since: int = bot.now_msec()
	var held := await _walk_into(bot, p["from"], p["inside"], edge, 2.0)
	told.append_array(a["told"])
	told.append_array(b["told"])
	told.append_array(bot.told_since(since).map(func(l: Dictionary) -> String: return str(l["text"])))
	bot.expect(not a["opened"] and not b["opened"] and not held, "before the turn-in the slab stays shut, tapped or walked into",
		"from the hall %s, from its floor %s, held %s" % [a["opened"], b["opened"], held])
	var false_words: Array = told.filter(func(t: String) -> bool: return "slab" in t or "draught" in t or "stair" in t)
	bot.expect(false_words.is_empty(), "before the turn-in nothing I am told speaks of a way (no slab, draught or stair)", "told %s" % [told])
	bot.log_line("before the turn-in, at the slab, told: %s" % [told])
	await bot.walk_to(p["hall"], 0, 30.0)  # Off the slab: no press of mine left leaning into it.


## The First Hall's hidden niche as the client holds it: its door's edge,
## its floor cell ("from"), the slab's cell ("inside"), a hall cell 3 or 2
## from the floor cell, straight out from the slab ("hall"), "open"; {} if
## the client holds none.
func _niche_parts(bot: Node) -> Dictionary:
	var niche: Dictionary = World.hidden_niche()
	if not bot.expect(not niche.is_empty(), "the client holds the First Hall's hidden niche", "%d niche edges" % World.niche_edges.size()):
		return {}
	var edge: Vector3i = niche["edge"]
	var from: Vector2i = niche["cell"]
	var cells: Array = Terrain.edge_cells(edge)
	var inside: Vector2i = cells[1] if cells[0] == from else cells[0]
	var away := from - inside
	var hall := from
	for n: int in [3, 2]:
		if World.is_walkable(from + away * n):
			hall = from + away * n
			break
	bot.log_line("the cold niche: its floor cell %s, the slab toward %s (edge %s, open %s); the hall's tapping spot %s" % [from, inside, edge, niche["open"], hall])
	return {"edge": edge, "from": from, "inside": inside, "hall": hall, "open": bool(niche["open"])}


## A tap as most players click, by parsed input events: the cursor over
## [param cell], the left button pressed and let go 0.05 s apart; then up
## to [param most] s for the door on [param edge] to open. {opened, told}
## (the texts told since), logged as [param what] with the pick and where I
## came to stand.
func _tap_and_watch(bot: Node, what: String, cell: Vector2i, edge: Vector3i, most := 5.0) -> Dictionary:
	var since: int = bot.now_msec()
	var started: Vector2i = bot.cell()
	var pick := await _point_at(bot, cell)
	_button(true, _screen_of(bot, cell))
	await bot.seconds(0.05)
	_button(false, _screen_of(bot, cell))
	await bot.until(func() -> bool:
		var shut: Door = World.door_on(edge)
		return shut != null and shut.open, most)
	await bot.seconds(0.5)
	var door: Door = World.door_on(edge)
	var opened := door != null and door.open
	var told: Array = bot.told_since(since).map(func(l: Dictionary) -> String: return str(l["text"]))
	bot.log_line("%s: tapped %s (the pick %s) from %s; now at %s; the slab %s; told %s" % [what, cell, pick, started, bot.cell(), "open" if opened else "shut", told])
	return {"opened": opened, "told": told}


## The opened slab shut again for the next case (setup, not a press under
## test): E at it with it under the cursor, from its floor cell.
func _shut_again(bot: Node, p: Dictionary) -> void:
	await bot.walk_to(p["from"], 0, 30.0)
	var door: Door = World.door_on(p["edge"])
	if door != null and door.open:
		await bot.tap_e_door(door)
		await bot.until(func() -> bool: return not door.open, 3.0)
	bot.log_line("setup: the slab shut again by E: %s" % ("shut" if door != null and not door.open else "still open"))


## The click scheme's walk into [param inside] from [param from]: the cursor
## over my own cell, the left button pressed (a click there, the route
## nothing), the cursor moved over the niche, the button held past
## Main.FREE_HOLD_SECONDS so it steers, all as parsed input events; held
## till the door on [param edge] opens, most [param most] seconds; let go.
## True if it opened. The cursor's cell and the steer logged.
func _walk_into(bot: Node, from: Vector2i, inside: Vector2i, edge: Vector3i, most: float) -> bool:
	var saved := str(Net.controls)
	Net.controls = "click"
	await _point_at(bot, from)
	bot.log_line("cursor over my cell %s (screen %s): the pick reads %s" % [from, _screen_of(bot, from), bot.main._pick_grid])
	_button(true, _screen_of(bot, from))
	await bot.frames(2)
	var end: int = bot.now_msec() + int(most * 1000.0)
	var picks := {}
	var door: Door = World.door_on(edge)
	while bot.now_msec() < end and not (door != null and door.open):
		_motion(_screen_of(bot, inside))
		await bot.frames(1)
		picks[Vector2i(Vector2(bot.main._pick_grid).round())] = true
		door = World.door_on(edge)
	_button(false, _screen_of(bot, inside))
	await bot.frames(2)
	Net.controls = saved
	bot.log_line("held into the niche: cursor cells %s; at %s; door %s" % [picks.keys(), bot.cell(), "open" if door != null and door.open else "shut"])
	return door != null and door.open


## Where [param cell] is on the screen, for the cursor: the 3D view's, or
## (headless, no 3D view) the 2D pick's inverse (Main._update_pick:
## Iso.local_to_grid of Main's local cursor point).
func _screen_of(bot: Node, cell: Vector2i) -> Vector2:
	var view: Node = bot.main.get("_client3d")
	if view != null:
		return view.screen_of_tile(cell)
	var main: Node2D = bot.main
	return main.get_viewport().get_screen_transform() * main.get_global_transform_with_canvas() * Iso.grid_to_local(Vector2(cell))


## The cursor put over [param cell] by parsed motions, again each frame till
## Main's pick reads it (within half a cell; the camera follows the body),
## 12 frames at most; the pick it reads.
func _point_at(bot: Node, cell: Vector2i) -> Vector2:
	var pick := Vector2(NAN, NAN)
	for i in 12:
		_motion(_screen_of(bot, cell))
		await bot.frames(1)
		pick = bot.main._pick_grid
		if not is_nan(pick.x) and pick.distance_to(Vector2(cell)) < 0.5:
			break
	return pick


func _motion(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else 0
	Input.parse_input_event(event)


func _button(pressed: bool, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	Input.parse_input_event(event)


## The cell of the client's level's link to [param map], or (-1, -1).
func _link_to(bot: Node, map: String) -> Vector2i:
	var level: Dictionary = bot.main.get("level") if bot.main.get("level") is Dictionary else {}
	for link: Dictionary in level.get("links", []):
		if str(link.get("to_map", "")) == map and link.get("tile") is Vector2i:
			return link["tile"]
	return Vector2i(-1, -1)


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
			bot.log_line("down on the way out; brought back in %s at %s, the temple's arrival not seen" % [bot.zone(), bot.cell()])
		elif not bot.expect(out, "out through the barrow's door", "zone %s at %s" % [bot.zone(), bot.cell()]):
			return
		await bot.settled()
		if not revived:
			bot.expect(World.distance(bot.cell(), TEMPLE_ARRIVAL) <= ARRIVAL_REACH, "set down in the temple, by its stair", "at %s, %d cells from %s" % [bot.cell(), World.distance(bot.cell(), TEMPLE_ARRIVAL), TEMPLE_ARRIVAL])
	await bot.admin("hour 12")
	# To the square, then find him.
	await bot.walk_to(TOWN_SQUARE, 3, 120.0)
	await bot.until(func() -> bool: return bot.find("Rolf") != null, 60.0)
	var rolf: GridEntity = bot.find("Rolf")
	if not bot.expect(rolf != null, "Rolf is in the town after the barrow", "at %s" % bot.cell()):
		return
	await bot.walk_to(rolf.tile, 2, 120.0)
	await bot.click(rolf.tile)
	await bot.seconds(2.0)
	# The chest's gold buys a ware with a click on its square (ui, 11-16: the store layout).
	var panel: BarterPanel = bot.main.get("barter_panel")
	var wares: Array = panel.boxes_shown() if panel != null else []
	var purse := int(bot.main.gold)
	var pick := ""
	var cost := -1
	for shown: String in wares:  # "ware <id> gold <cost>"
		var id := shown.get_slice(" ", 1)
		var entry: Dictionary = panel.ware_entry(id)
		if not entry.is_empty() and int(entry.get("cost", purse + 1)) <= purse:
			pick = id
			cost = int(entry.get("cost"))
			break
	if not bot.expect(not pick.is_empty(), "with the chest's gold (purse %d), one of Rolf's wares is within it" % purse,
			"%d wares shown: %s" % [wares.size(), wares]):
		return
	panel._store_view.square_pressed.emit("ware", pick)
	await bot.seconds(2.0)
	bot.expect(int(bot.main.gold) == purse - cost, "a click on \"%s\"'s square buys it with the chest's gold: the purse falls by its price" % pick,
		"purse %d -> %d, cost %d; why \"%s\"" % [purse, int(bot.main.gold), cost, panel.why_shown()])


## A click on the fallen knight opens his talk (Jeff on v0.1.197: "the fallen
## knight wasn't interactable"), [param when] in his quest: walked to as a
## player does, the client takes the click as talk, not a blow
## (Main.talks_on_click: a peaceable talking monster, his "peaceable" the
## server's, replicated), and he answers within 6 s: his window's button
## holding [param title] (his offer for the step), or his [param words] told
## or said. What was up and what was heard logged either way.
func _talk_knight(bot: Node, when: String, title: String, words := "", window := false) -> bool:
	var knight: GridEntity = bot.find("AstralKnight")
	if not bot.expect(knight != null, "%s: the fallen knight is there to talk to" % when, "in %s at %s" % [bot.zone(), bot.cell()]):
		return false
	if World.distance(bot.cell(), knight.tile) > 2:
		await bot.walk_to(knight.tile, 2, 90.0)
	var on_click: bool = bot.main.talks_on_click(knight)
	bot.log_line("%s: the knight at %s, talks %s, peaceable %s; a click talks: %s" % [when, knight.tile,
		knight.get("talks"), knight.get("peaceable"), on_click])
	var since: int = bot.now_msec()
	var said_words := words.left(24)
	await bot.click(knight.tile)
	var answered := func() -> bool:
		var shown: bool = not title.is_empty() and bot.buttons().any(func(b: Dictionary) -> bool: return title.to_lower() in str(b["text"]).to_lower())
		var said: bool = not said_words.is_empty() and (not bot.told_since(since, said_words).is_empty() or bot.heard.any(func(l: Dictionary) -> bool:
			return l["msec"] >= since and said_words in str(l["text"])))
		if window:  # His window up with his words in it (dungeon, 11-01: a chat line alone is no talk).
			var panel: Control = bot.main.deal_panel
			return panel != null and panel.is_visible_in_tree() and said_words in " ".join(bot.texts(panel))
		return shown or said
	var ok: bool = await bot.until(answered, 6.0)
	if bot.main.deal_panel != null:
		bot.log_line("%s: his window %s; it reads %s" % [when, "up" if bot.main.deal_panel.is_visible_in_tree() else "not up",
			bot.texts(bot.main.deal_panel).map(func(t: String) -> String: return t.left(60))])
	_list_buttons(bot, "the knight clicked, %s" % when)
	bot.expect(on_click, "%s: a click on the fallen knight is talk, not a blow" % when,
		"talks %s, peaceable %s" % [knight.get("talks"), knight.get("peaceable")])
	bot.expect(ok, "%s: clicked, the fallen knight answers (%s%s)" % [when, title if not title.is_empty() else words.left(40), ", in his window" if window else ""],
		"buttons %s; told %s; heard %s" % [bot.buttons().map(func(b: Dictionary) -> String: return str(b["text"])),
			bot.told_since(since).map(func(l: Dictionary) -> String: return str(l["text"]).left(60)),
			bot.heard.filter(func(l: Dictionary) -> bool: return l["msec"] >= since).map(func(l: Dictionary) -> String: return str(l["text"]).left(60))])
	return ok


## Where the knight's quest stood, kept for a phase after a server restart
## (TOUR_PHASES=2): "open" (taken, not ready), "ready", "done" (handed in),
## or "ask"; the world saved.
func _keep_knight(bot: Node, marked := false) -> void:
	var quest: Dictionary = bot.me().get("quest") if bot.me() != null else {}
	var step := "ask"
	if marked:
		step = "done"
	elif not quest.is_empty():
		step = "ready" if bool(quest.get("ready", false)) else "open"
	elif not bot.told.filter(func(l: Dictionary) -> bool: return "proven" in str(l["text"]) and "fallen knight" in str(l["text"])).is_empty() \
			or not bot.heard.filter(func(l: Dictionary) -> bool: return "breathes cold air" in str(l["text"])).is_empty():
		step = "done"
	var file := FileAccess.open(bot.out_dir.path_join("knight_phase1.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"step": step}))
	file.close()
	bot.log_line("the knight's quest kept as %s; save: %s" % [step, await bot.admin("save")])


## After the restart: back to the knight (into the barrow if not woken
## there), his talk as the quest stood before it.
func _after_restart(bot: Node) -> void:
	var kept: Variant = JSON.parse_string(FileAccess.get_file_as_string(bot.out_dir.path_join("knight_phase1.json")))
	var step := str((kept as Dictionary).get("step", "")) if kept is Dictionary else ""
	await bot.settled()
	bot.log_line("after the restart: the quest stood %s; woke in %s at %s" % [step, bot.zone(), bot.cell()])
	if not bot.expect(not step.is_empty(), "phase 1 kept where the knight's quest stood"):
		return
	if bot.zone() != "barrow":
		await _to_barrow(bot)
	var quest: Dictionary = bot.me().get("quest") if bot.me() != null else {}
	if step in ["open", "ready"]:
		bot.expect(not quest.is_empty(), "after the restart the quest is still on my tracker", str(quest).left(200))
	var by_step := {"ask": [AstralKnight.ASK_TITLE, ""], "open": [AstralKnight.NOT_YET_TITLE, AstralKnight.NOT_YET],
		"ready": [AstralKnight.TURN_IN_TITLE, ""], "done": ["", AstralKnight.DONE_LAID]}
	var want: Array = by_step.get(step, ["", ""])
	await _talk_knight(bot, "after a server restart (the quest %s)" % step, want[0], want[1], step == "done")
	bot.press("close")
