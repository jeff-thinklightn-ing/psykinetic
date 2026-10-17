extends Node
## Resident routines (decision 404): where one of a trade is at an hour,
## from the clock alone (Townsfolk.whereabouts): the file's stints per
## trade cover the day with no gap or overlap and name known places; the
## default stands in for a trade not listed; any uncovered hour is the
## square; a resident's own clock runs ahead or behind within offset_hours,
## by id; a hidden type's stints come first; a season moves the day's
## edges and keeps the day whole; the temple day comes round every so many
## days by id, the hour at the temple; Resident.doing_at maps the words.
## Reads the repo's levels, never the shared overlay. Run it with
## tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion and quits
## with exit code 1 if any assertion failed, 0 otherwise.

var _failures := 0


func _ready() -> void:
	World.set_process(false)
	_test_file()
	_test_whereabouts()
	_test_offsets()
	_test_types_and_seasons()
	_test_temple_day()
	_test_doing()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## Each hour of [param trade]'s day, 48 half hours, with no offset.
func _day(trade: String, season := "", type := "", id := "", day := -1) -> Array[String]:
	var out: Array[String] = []
	for half in 48:
		out.append(Townsfolk.whereabouts(trade, half / 2.0, season, type, id, day))
	return out


func _test_file() -> void:
	print("\n== levels/residents.json: stints per trade, whole days, known places ==")
	Townsfolk.use_days({})
	var table := Townsfolk.days()
	var trades: Array[String] = []
	for key: String in table:
		if table[key] is Dictionary and table[key].has("stints"):
			trades.append(key)
	_check(trades.has("default") and trades.size() >= 4, "trades with a day: %s" % [trades])
	var bad: Array[String] = []
	for trade: String in trades:
		var covered := 0.0
		for stint: Dictionary in table[trade]["stints"]:
			var from := float(stint["from"])
			var to := float(stint["to"])
			covered += to - from if from < to else 24.0 - from + to
			if not str(stint.get("at", "")) in Townsfolk.PLACES:
				bad.append("%s: %s" % [trade, stint])
		if absf(covered - 24.0) > 0.001:
			bad.append("%s covers %.1f hours" % [trade, covered])
		var seen := {}
		for half in 48:
			seen[Townsfolk.whereabouts(trade, half / 2.0)] = true
		if seen.has("square") and not table[trade]["stints"].any(func(stint: Dictionary) -> bool: return stint["at"] == "square"):
			bad.append("%s has a gap" % trade)
	_check(bad.is_empty(), "every trade's stints cover 24 hours, no gap, places known %s" % [bad])
	_check(float(table.get("offset_hours", 0)) > 0.0 and float(table.get("offset_hours", 9)) <= 1.0, "offset_hours is set, within an hour")
	_check(table.get("types") is Dictionary and table.get("seasons") is Dictionary and int(table.get("temple", {}).get("every_days", 0)) > 0, "types, seasons and the temple day are set")


func _test_whereabouts() -> void:
	print("\n== where a smith is through the day ==")
	Townsfolk.use_days({})
	_check(Townsfolk.whereabouts("smith", 6.5) == "well" and Townsfolk.whereabouts("smith", 9.0) == "work" and Townsfolk.whereabouts("smith", 12.5) == "inn"
		and Townsfolk.whereabouts("smith", 15.0) == "work" and Townsfolk.whereabouts("smith", 19.0) == "inn" and Townsfolk.whereabouts("smith", 23.0) == "home"
		and Townsfolk.whereabouts("smith", 3.0) == "home", "the well at dawn, the forge, the inn at midday and evening, home at night")
	_check(_day("tanner") == _day("default"), "a trade not listed keeps the default's day")
	Townsfolk.use_days({"default": {"stints": [{"from": 8, "to": 18, "at": "work"}]}})
	_check(Townsfolk.whereabouts("smith", 20.0) == "square" and Townsfolk.whereabouts("smith", 10.0) == "work", "an hour no stint covers is the square")
	Townsfolk.use_days({})


func _test_offsets() -> void:
	print("\n== each resident's own clock, by id, within offset_hours ==")
	Townsfolk.use_days({})
	var most := float(Townsfolk.days()["offset_hours"])
	var least := 0.0
	var greatest := 0.0
	var differ := false
	for i in 200:
		var offset := Townsfolk.offset_of("rt-%d" % i)
		least = minf(least, offset)
		greatest = maxf(greatest, offset)
		if Townsfolk.whereabouts("smith", 7.0, "", "", "rt-%d" % i) != Townsfolk.whereabouts("smith", 7.0):
			differ = true
	_check(least >= -most and greatest <= most and least < -most * 0.5 and greatest > most * 0.5, "offsets spread within %.2f h (%.2f .. %.2f)" % [most, least, greatest])
	_check(differ, "so at the stroke of a stint some are already there and some not yet")
	_check(Townsfolk.offset_of("rt-7") == Townsfolk.offset_of("rt-7") and Townsfolk.offset_of("") == 0.0, "the same id keeps its offset; no id has none")


func _test_types_and_seasons() -> void:
	print("\n== a hidden type's stints first; the season moves the day's edges ==")
	Townsfolk.use_days({})
	_check(Townsfolk.whereabouts("smith", 21.0, "", "bard") == "inn" and Townsfolk.whereabouts("smith", 21.0) == "home", "a bard's evening runs late at the inn")
	_check(Townsfolk.whereabouts("smith", 23.5, "", "thief") == "square" and Townsfolk.whereabouts("smith", 0.5, "", "thief") == "square" and Townsfolk.whereabouts("smith", 2.0, "", "thief") == "home",
		"a thief is in the square after dark, over midnight, then home")
	_check(Townsfolk.whereabouts("smith", 6.5, "winter") == "home" and Townsfolk.whereabouts("smith", 7.5, "winter") == "well" and Townsfolk.whereabouts("smith", 19.5, "winter") == "home",
		"winter: out an hour later, home an hour earlier")
	_check(Townsfolk.whereabouts("smith", 6.0, "summer") == "well" and Townsfolk.whereabouts("smith", 20.5, "summer") == "inn", "summer: out earlier, the inn later")
	var bad: Array[String] = []
	for season: String in Season.NAMES:
		for trade: String in ["smith", "cook", "carpenter", "priest", "guard", "medicine_man", "default"]:
			var seen := {}
			for place: String in _day(trade, season):
				seen[place] = true
			var stints: Array = Townsfolk.days()[trade]["stints"]
			if seen.has("square") and not stints.any(func(stint: Dictionary) -> bool: return stint["at"] == "square"):
				bad.append("%s in %s" % [trade, season])
	_check(bad.is_empty(), "the day stays whole in every season (no gap opens) %s" % [bad])


func _test_temple_day() -> void:
	print("\n== the temple day, every so many days by id ==")
	Townsfolk.use_days({})
	var every := int(Townsfolk.days()["temple"]["every_days"])
	# On their own clock the hour falls a little earlier or later: look through the morning.
	var at_temple := func(id: String, day: int) -> bool:
		for quarter in range(32, 44):
			if Townsfolk.whereabouts("smith", quarter / 4.0, "", "", id, day) == "temple":
				return true
		return false
	var went: Array[int] = []
	for day in every * 3:
		if at_temple.call("rt-bram", day):
			went.append(day)
	_check(went.size() == 3 and went[1] - went[0] == every and went[2] - went[1] == every, "a smith goes every %d days (%s)" % [every, went])
	_check(not went.is_empty() and Townsfolk.whereabouts("smith", 12.0, "", "", "rt-bram", went[0]) in ["work", "inn"], "and is back at work after the hour")
	var days_of := {}
	for i in 60:
		for day in every:
			if at_temple.call("rt-%d" % i, day):
				days_of[day] = true
	_check(days_of.size() >= every - 1, "different residents go on different days (%d of %d days)" % [days_of.size(), every])
	_check(Townsfolk.whereabouts("smith", 9.5, "", "", "rt-bram") == "work", "with no day given (tests, spawns before the clock), no temple")
	_check(Townsfolk.day_of(0.0) == 0 and Townsfolk.day_of(DayNight.day_steps * 2.5) == 2, "day_of counts the world clock's days")


func _test_doing() -> void:
	print("\n== Resident.doing_at maps the words ==")
	Townsfolk.use_days({})
	_check(Resident.doing_at("smith", 6.5) == Resident.Doing.WELL and Resident.doing_at("smith", 9.0) == Resident.Doing.WORK and Resident.doing_at("smith", 12.5) == Resident.Doing.INN
		and Resident.doing_at("smith", 23.0) == Resident.Doing.HOME and Resident.doing_at("smith", 9.5, "", "scholar") == Resident.Doing.TEMPLE,
		"well, work, inn, home, temple")
	_check(Resident.PLACE_OF.size() == Resident.Doing.size() and Resident.WHERE_WORDS.size() == Resident.Doing.size(), "every Doing has a place and words")
	for place: String in Townsfolk.PLACES:
		if not Resident.DOING_AT.has(place):
			_check(false, "place %s has a Doing" % place)


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
