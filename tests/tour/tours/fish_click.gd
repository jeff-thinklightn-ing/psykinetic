extends RefCounted
## "Fishing that works" played by clicks only (805 amended (11), items): a
## fresh player, no pack window ever opened. A click on far water with no rod
## (the answer), Rolf's rod bought, then put in the pack (a sword in hand), a
## click on far water: walked to the bank, the rod to hand by itself, the
## cast; at the bite a click strikes; a step puts the sword back. Then the
## Reed Pond and a small pool. Every line told is logged.

const TOWN_SQUARE := Vector2i(212, 205)
const REED := Vector2i(32, 118)

var bot: Node


func run(b: Node) -> void:
	bot = b
	Net.message_received.connect(_on_message)
	await bot.settled()
	await bot.admin("hour 9")
	await bot.admin("weather clear 60 all")
	bot.log_line("setup: %s" % await bot.admin("gold Tourbot 5 tour"))
	await bot.admin("give Tourbot sword 1")
	await bot.seconds(1.0)
	_slots("start")
	# No rod: a click on water answers, once.
	var near := _nearest_water(bot.cell(), 60)
	bot.log_line("nearest water %s" % near)
	if near != World.NO_CELL:
		var since: int = bot.now_msec()
		await bot.click(near)
		await bot.seconds(2.0)
		await bot.click(near)
		await bot.seconds(2.0)
		var told: Array = bot.told_since(since, "rod")
		bot.expect(told.size() == 1, "no rod: a click on water says who has them, once", "%s" % [told.map(func(l: Dictionary) -> String: return l["text"])])
		await bot.walk_to(TOWN_SQUARE, 4, 120.0)
	# The rod: Rolf's.
	var rolf: GridEntity = bot.find("Rolf")
	if not bot.expect(rolf != null, "Rolf is there"):
		return
	await bot.walk_to(rolf.tile, 2, 90.0)
	await bot.click(rolf.tile)
	await bot.seconds(2.5)
	var barter: Node = bot.main.barter_panel
	for box: String in barter.boxes_shown():
		var parts := box.split(" ")
		if parts.size() > 1 and parts[0] == "ware" and parts[1].ends_with("|fishing_rod"):
			barter.click_box("ware", parts[1])
			break
	await bot.seconds(0.5)
	bot.press("buy")
	await bot.until(func() -> bool: return bot.me().slots.has("fishing_rod"), 8.0)
	bot.key(KEY_ESCAPE)
	await bot.seconds(1.0)
	_slots("after Rolf")
	# The rod into the pack, the sword into the hand (as a player who'd rather walk armed).
	var me: Player = bot.me()
	var rod_at := Array(me.slots).find("fishing_rod")
	var sword_at := Array(me.slots).find("sword")
	if rod_at == Items.RIGHT_HAND and sword_at >= 0:
		bot.main._transfer(me, rod_at, me, sword_at)  # A drag of the rod onto the sword: swapped.
	await bot.seconds(1.5)
	_slots("the sword in hand, the rod packed")
	# Waters: the nearest few and the Reed Pond.
	var targets: Array[Vector2i] = []
	if near != World.NO_CELL:
		targets.append(near)
	var small := _small_water()
	if small != World.NO_CELL:
		targets.append(small)
	targets.append(_nearest_water(REED, 6))
	var caught := 0
	for water: Vector2i in targets:
		caught += await _cast_by_click(water)
	bot.expect(caught > 0, "a fish landed by clicks alone", "%d" % caught)


func _slots(when: String) -> void:
	var held: Array[String] = []
	for slot in bot.me().slots.size():
		if not bot.me().slots[slot].is_empty():
			held.append("%d:%s" % [slot, bot.me().slots[slot]])
	bot.log_line("my slots (%s): %s" % [when, held])


func _nearest_water(from: Vector2i, reach: int) -> Vector2i:
	var best := World.NO_CELL
	for cell: Vector2i in World._water:
		if World.distance(cell, from) <= reach and (best == World.NO_CELL or World.distance(cell, from) < World.distance(best, from)):
			best = cell
	return best


## A water body of under 8 cells, nearest the player, NO_CELL if none.
func _small_water() -> Vector2i:
	var waters := World.fish_waters_of({"water": World._water.keys()})
	var counts := World.fish_body_counts(waters)
	var best := World.NO_CELL
	for cell: Vector2i in waters:
		if int(counts[waters[cell]]) < World.FISH_BODY_SMALL and (best == World.NO_CELL or World.distance(cell, bot.cell()) < World.distance(best, bot.cell())):
			best = cell
	bot.log_line("small bodies: %s" % [counts.keys().filter(func(k: String) -> bool: return int(counts[k]) < World.FISH_BODY_SMALL)])
	return best


## Clicks [param water] (far: walked to the bank first), waits for the cast,
## clicks again at the bite (the strike); three casts. Fish landed.
func _cast_by_click(water: Vector2i) -> int:
	var landed := 0
	for cast in 3:
		var since: int = bot.now_msec()
		var fish_before: int = _fish_units()
		await bot.click(water)
		var cast_up: bool = await bot.until(func() -> bool: return str(bot.me().fishing.get("state", "")) != "", 120.0)
		var told: Array = bot.told_since(since).map(func(l: Dictionary) -> String: return l["text"])
		bot.log_line("CLICK %s (cast %d): from %s, cast %s, state %s, hand %s, told %s" % [water, cast + 1, bot.cell(), cast_up,
			bot.me().fishing, bot.me().slots[Items.RIGHT_HAND], told])
		if not cast_up:
			return landed
		var bit: bool = await bot.until(func() -> bool: return str(bot.me().fishing.get("state", "")) in ["bite", ""], 45.0)
		if str(bot.me().fishing.get("state", "")) == "bite":
			await bot.seconds(0.6)  # A person's answer.
			await bot.click(bot.cell() + Vector2i(1, 1))  # Anywhere: the strike.
		await bot.until(func() -> bool: return str(bot.me().fishing.get("state", "")) in ["landed", "missed", ""], 10.0)
		bot.log_line("cast %d: bite seen %s, ended %s, fish %d -> %d" % [cast + 1, bit, bot.me().fishing, fish_before, _fish_units()])
		landed += 1 if _fish_units() > fish_before else 0
		await bot.until(func() -> bool: return bot.me().fishing.is_empty(), 5.0)
	# A step: the sword back.
	var stood: Vector2i = bot.cell()
	await bot.walk_to(stood + Vector2i(0, 1) if World.is_walkable(stood + Vector2i(0, 1)) else stood + Vector2i(1, 0), 0, 10.0)
	await bot.seconds(1.0)
	bot.log_line("after a step: hand %s" % bot.me().slots[Items.RIGHT_HAND])
	return landed


var catches := 0


func _on_message(kind: String, data: Dictionary) -> void:
	if kind == "reward" and str(data.get("track", "")) == "catch":
		catches += 1


func _fish_units() -> int:
	return catches
