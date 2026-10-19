extends Node
## A balance run of the wilds town on its own clock, no players: the real
## rules (levels/economy.json), the real map, herds and weather, a level-1
## field, nine residents (smith, cook, carpenter, hunter, tanner, farmer,
## two haulers; the priest is appointed). Prints a line a week: the
## treasury, each trade's purse, loans, all the town's gold, meals so far
## (bought, store, dole, hungry), food, and the thief's lifts (gold and
## store), fences and catches, from the store's ledger (the last
## LEDGER_SIZE lines); the residents at the end. For the
## coordinator's balance runs (decisions 354, 449, 461): no state written,
## nothing in the shared user:// (Level.overlay_dir a private folder).
##   godot --headless --path <repo> res://tools/town_balance.tscn -- --days=90 [--thief=hand_1] [--merchant=hand_2] [--no-field]
## Run it through the gate, its output to a file: sh tools/heavy_job.sh run <tree> bench -- "$GODOT_PATH" --headless --path . res://tools/town_balance.tscn -- --days=90 > balance.txt

const TOWN := "wilds/store"
const DAY := 54000
const FOLK := [["smith_1", "Odo", "smith"], ["cook_1", "Mags", "cook"], ["carp_1", "Pell", "carpenter"],
	["hunt_1", "Hob", "hunter"], ["tan_1", "Hew", "tanner"], ["farm_1", "Tam", "farmer"],
	["hand_1", "Ash", "hauler"], ["hand_2", "Bea", "hauler"]]

var _now := 0


func _ready() -> void:
	World.set_process(false)
	Level.overlay_dir = preload("res://tests/test_ports.gd").scratch("town_balance/no_overlay/")
	var days := 90
	var thief := ""
	var merchant := ""
	var field := true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--days="):
			days = maxi(int(arg.trim_prefix("--days=")), 1)
		elif arg.begins_with("--thief="):
			thief = arg.trim_prefix("--thief=")
		elif arg.begins_with("--merchant="):
			merchant = arg.trim_prefix("--merchant=")
		elif arg == "--no-field":
			field = false
	DayNight.day_steps = DAY
	Season.season_days = 7
	Season.year_phase = 0.0
	Season.year_anchor = 0
	_run(days, thief, merchant, field)
	get_tree().quit(0)


func _run(days: int, thief: String, merchant: String, field: bool) -> void:
	var clock := func() -> int: return _now
	var names: Array[String] = ["wilds", "hills", "castle"]
	var world_map := WorldMap.build(names)
	var holdings := Holdings.new(world_map, Factions.read(), {}, clock)
	var stock := Stockpile.new({}, clock, ItemBook.new(clock))
	var work := Production.new({}, stock, holdings, clock)
	var towns := Towns.new({}, work, {}, clock)
	var economy := Economy.new({}, stock, work, clock)
	work.deliver = economy.deliver
	work.buy_materials = economy.buy_materials
	economy.shortfall = towns.shortfall
	work.build_lacks = func(town: String) -> Dictionary: return towns.shortfall(town).get("needs", {})
	work.town_pays = economy.owe_or_pay
	work.settle_fund = economy.settle_fund
	economy.building_stands = func(town: String, kind: String) -> bool:
		var house := towns.building(town, kind)
		return int(house.get("level", 0)) >= 1 and house.get("state") in [Towns.STANDING, Towns.BUILDING]
	var herds := Herds.new({}, Herds.areas_of(world_map), {}, clock, holdings)
	work.hunt = func(town: String) -> String:
		var place := holdings.place(town)
		return herds.hunt_one(str(place.get("area", "wilds")), place.get("cell", Vector2i.ZERO))
	var region := str(world_map.areas["wilds"].get("region", Level.DEFAULT_REGION))
	towns.wells = func(_town: String) -> int: return 1
	towns.rain = func(_town: String, from: float, to: float) -> float: return Weather.rain_between(region, from, to)
	towns.storms = func(_town: String, from: float, to: float) -> Array:
		var least := float(Weather.climate_of(region).get("storm_min", Weather.STORM_MIN))
		return Weather.storms_between(region, from, to).filter(func(storm: Dictionary) -> bool: return float(storm["strength"]) >= least)
	towns.seed_from(world_map)
	if field:
		towns._town(TOWN)["buildings"]["field"] = {"kind": "field", "level": 1, "state": Towns.STANDING, "since": 0, "job": 0}
	for each in FOLK:
		if each[2] == "farmer" and not field:
			continue
		towns.note_rescue(TOWN, each[0], each[1], each[2])
	if not thief.is_empty():
		if work.worker(thief).is_empty():
			print("no resident %s to make a thief" % thief)
		else:
			work._workers[thief]["type"] = "thief"
	if not merchant.is_empty():
		if work.worker(merchant).is_empty():
			print("no resident %s to make a merchant" % merchant)
		else:
			work._workers[merchant]["type"] = "merchant"  # The thief's fence runs through him (decision 461).
	print("######## %d days%s%s%s ########" % [days, ", %s a thief" % thief if not thief.is_empty() else "",
		", %s a merchant" % merchant if not merchant.is_empty() else "", "" if field else ", no field"])
	var meals := {"dole": 0, "hungry": 0, "bought": 0, "store": 0}
	for day in days:
		var day_end := (day + 1) * DAY
		while _now < day_end:
			_now += World.WORLD_TICK_STEPS
			towns.tick()
			work.tick()
			economy.tick()
			Townsfolk.tick(work, stock, economy)  # With the economy: the thief's fence (decision 461).
			herds.tick()
			for id in work.worker_ids(TOWN):
				var fed := str(work.worker(id).get("fed", ""))
				var key := "%s:%s" % [id, work.worker(id).get("needs", {}).get("meal", 0)]
				if fed in meals and not meals.has(key):
					meals[key] = true
					meals[fed] += 1
		if (day + 1) % 7 == 0 or day == 0 or day + 1 == days:
			_line(day + 1, towns, work, stock, meals)
	print("residents at the end:")
	for id in work.worker_ids(TOWN):
		var w := work.worker(id)
		print("  %s %s (%s): purse %d, loan %.0f, fed %s" % [w["name"], w["trades"], w.get("type", ""), w["purse"], w["loan"], w["fed"]])


func _line(day: int, towns: Towns, work: Production, stock: Stockpile, meals: Dictionary) -> void:
	var purses := {}
	var loans := 0
	var gold := stock.count(TOWN, "gold")
	for id in work.worker_ids(TOWN):
		var w := work.worker(id)
		purses["%s %s" % [w["trades"][0], w["name"]]] = int(w["purse"])
		loans += roundi(float(w["loan"]))
		gold += int(w["purse"])
	var told := towns.log_of(TOWN).map(func(line: Dictionary) -> String: return str(line["what"]))
	var ledger := stock.ledger(TOWN).map(func(line: Dictionary) -> String: return "%s %s" % [line.get("by", ""), line.get("from", "")])
	print("day %2d %-6s | treasury %3d | all gold %d | loans %3d | meals: bought %d store %d dole %d hungry %d | food %d | lifted %d fenced %d caught %d | %s"
		% [day, Season.name_at(_now), stock.count(TOWN, "gold"), gold, loans, meals["bought"], meals["store"], meals["dole"], meals["hungry"],
		stock.count(TOWN, "food"), ledger.filter(func(l: String) -> bool: return l.begins_with("lifted:") or l.begins_with("missing") or l.contains(" missing")).size(),
		ledger.filter(func(l: String) -> bool: return l.ends_with(" a dealer")).size(),
		ledger.filter(func(l: String) -> bool: return l.begins_with("returned")).size(), purses])
