extends Node
## The keep-the-balance quest (decision 761) day by day on a real area's
## ground, for tuning: the area's herds seeded as the game seeds them, the
## balance on, one fold kept at its herder's sheep, and a player who takes
## N deer over the quest's first days and carries all the meat home. Prints
## each day's deer, wolves, what the ground keeps and the sheep lost, the
## day the fold asks and the judgement, for each N.
## Reads the repo's levels in memory: its overlay_dir is a private scratch
## folder, never the shared overlay. Run it through the gate as a scene:
## godot --headless --audio-driver Dummy --path . --scene tools/balance_table.tscn -- --run-marker=<n>
##   [--area=hills] [--fold=hill_shieling] [--takes=0,4,8,15] [--rules=<json of balance rules over the real ones>]
##   [--deer=<times the level's deer>] [--days=<days before the player starts, if the fold never asks>]
##   [--cycle=<days>: a settled zone over that many days instead, each N its own run: the player takes N
##    deer at every ask, the fold keeps what Balance leaves it (its regrowth, its flock come back) and the
##    herder's keep of 2; prints each ask's day, its ending and the days between asks]

const TICKS_A_DAY := 10

var _now := 0
var _day := 0


func _ready() -> void:
	World.set_process(false)
	Level.overlay_dir = preload("res://tests/test_ports.gd").scratch("balance_table/no_overlay/")
	var args := {}
	for each in OS.get_cmdline_user_args():
		if each.begins_with("--") and each.contains("="):
			args[each.substr(2, each.find("=") - 2)] = each.substr(each.find("=") + 1)
	var area := str(args.get("area", "hills"))
	var fold_place := str(args.get("fold", "hill_shieling"))
	var takes: Array = str(args.get("takes", "0,4,8,15")).split(",")
	var rules: Dictionary = Production.read_rules().get("balance", {}).duplicate(true)
	if args.has("rules"):
		var over: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(args["rules"])))
		if over is Dictionary:
			_merge(rules, over)
	var map := WorldMap.build([area] as Array[String])
	var holdings := Holdings.new(map)
	var richness := WorldRichness.new(map, holdings)
	var areas := Herds.areas_of(map)
	var herds_of: Dictionary = (areas[area]["herds"] as Dictionary).duplicate()
	herds_of["balance"] = true
	if args.has("deer"):
		herds_of["deer"] = float(args["deer"])
	areas[area]["herds"] = herds_of
	var place: Dictionary = map.areas[area].get("places", {}).get(fold_place, {})
	var cell: Vector2i = place.get("cell", Vector2i.ZERO)
	print("balance table: %s, fold %s at %s, rules %s" % [area, fold_place, cell, JSON.stringify(rules)])
	if args.has("cycle"):
		for n: String in takes:
			_cycle(area, cell, areas, holdings, richness, rules, int(n), int(args["cycle"]))
		get_tree().quit(0)
		return
	for n: String in takes:
		_run(area, cell, areas, holdings, richness, rules, int(n), int(args.get("days", 10)))
	get_tree().quit(0)


func _merge(into: Dictionary, over: Dictionary) -> void:
	for key: Variant in over:
		if into.get(key) is Dictionary and over[key] is Dictionary:
			_merge(into[key], over[key])
		else:
			into[key] = over[key]


func _run(area: String, cell: Vector2i, areas: Dictionary, holdings: Holdings, richness: WorldRichness, rules: Dictionary, take: int, wait: int) -> void:
	var day_steps := maxi(DayNight.day_steps, 1)
	_now = 0
	var herds := Herds.new({}, areas, {}, func() -> int: return _now, holdings)
	herds.richness = richness.richness
	herds.camps = func() -> Array: return []
	var stock := Stockpile.new({}, func() -> int: return _now)
	var balance := Balance.new({}, herds, stock, rules, func() -> int: return _now)
	herds.balance = balance
	balance.id_of = func(_uid: int) -> String: return "meat"
	balance.folds = func() -> Array: return [{"id": "fold", "area": area, "cell": cell, "town": "town", "farmer": "herder"}]
	var said := {"asked": -1, "judged": ""}
	balance.asked.connect(func(_id: String) -> void: said["asked"] = _day)
	balance.judged.connect(func(_id: String, result: String) -> void: said["judged"] = result)
	herds.seed_now(area)
	herds.tick()
	balance.tick()
	print("\n== %s: the player takes %d deer from the ask (or day %d), all the meat home ==" % [area, take, wait])
	print("day  deer  room  wolves  wolf_cap  hunger  lost  quest")
	var start := -1
	var left := take
	for day in 30:
		_day = day
		# The herder keeps his fold at 6 (he drives and lambs; the wolves' take is what counts here).
		if stock.count("fold", "sheep") < 6:
			stock.deposit("fold", "sheep", 6 - stock.count("fold", "sheep"), "herder", "kept")
		if start < 0 and (int(said["asked"]) >= 0 or day >= wait):
			start = day
		# The player's take: over the first two days of the quest, all brought home.
		if start >= 0 and left > 0 and day - start < 2:
			var today := left if day - start == 1 else ceili(take / 2.0)
			today = mini(today, left)
			_take_deer(herds, area, today)
			left -= today
		for i in TICKS_A_DAY:
			_now += day_steps / TICKS_A_DAY
			herds.tick()
			balance.tick()
		var quest := balance.quest("fold")
		var state := "asked" if int(said["asked"]) == day else ("open, %s if judged now" % balance.outcome("fold") if not quest.is_empty() else "")
		if not str(said["judged"]).is_empty():
			state = "JUDGED %s" % said["judged"]
		print("%3d  %4.0f  %4.0f  %6.1f  %8.1f  %6.2f  %4d  %s" % [day + 1, herds.total(area, "deer"), herds.capacity(area, "deer"),
			herds.total(area, "wolf"), herds.capacity(area, "wolf"), balance.hunger(area), 6 - stock.count("fold", "sheep") if str(said["judged"]).is_empty() else -1, state])
		if not str(said["judged"]).is_empty():
			break
	herds.balance = null


func _cycle(area: String, cell: Vector2i, areas: Dictionary, holdings: Holdings, richness: WorldRichness, rules: Dictionary, take: int, days: int) -> void:
	var day_steps := maxi(DayNight.day_steps, 1)
	_now = 0
	var herds := Herds.new({}, areas, {}, func() -> int: return _now, holdings)
	herds.richness = richness.richness
	herds.camps = func() -> Array: return []
	var stock := Stockpile.new({}, func() -> int: return _now)
	var balance := Balance.new({}, herds, stock, rules, func() -> int: return _now)
	herds.balance = balance
	balance.id_of = func(_uid: int) -> String: return "meat"
	balance.folds = func() -> Array: return [{"id": "fold", "area": area, "cell": cell, "town": "town", "farmer": "herder"}]
	var asks: Array[int] = []
	var ends: Array[String] = []
	balance.asked.connect(func(_id: String) -> void: asks.append(_day))
	balance.judged.connect(func(_id: String, result: String) -> void: ends.append(result))
	herds.seed_now(area)
	herds.tick()
	balance.tick()
	stock.deposit("fold", "sheep", 4, "herder", "start")
	var left := 0
	var start := -1
	for day in days:
		_day = day
		if stock.count("fold", "sheep") < 2:
			stock.deposit("fold", "sheep", 2 - stock.count("fold", "sheep"), "herder", "keep")
		if not asks.is_empty() and asks[-1] == day - 1 and start != asks[-1]:
			start = asks[-1]
			left = take
		if left > 0:
			var today := mini(ceili(take / 2.0), left)
			_take_deer(herds, area, today)
			left -= today
		for i in TICKS_A_DAY:
			_now += day_steps / TICKS_A_DAY
			herds.tick()
			balance.tick()
	var gaps: Array[int] = []
	for i in range(1, asks.size()):
		gaps.append(asks[i] - asks[i - 1])
	var mean := 0.0
	for gap in gaps:
		mean += gap
	mean = mean / gaps.size() if not gaps.is_empty() else 0.0
	print("cycle %s, N=%d over %d days: asks on days %s, endings %s, gaps %s (mean %.1f days = %.1f real hours at %d min a day); at the end deer %.0f of %.0f, wolves %.1f" % [
		area, take, days, asks, ends, gaps, mean, mean * day_steps / 36000.0, day_steps / 600,
		herds.total(area, "deer"), herds.capacity(area, "deer"), herds.total(area, "wolf")])
	herds.balance = null


func _take_deer(herds: Herds, area: String, count: int) -> void:
	var left := float(count)
	for each in herds.groups_in(area, "deer"):
		var off := minf(float(each["count"]), left)
		each["count"] = float(each["count"]) - off
		left -= off
		if left <= 0.0:
			return
