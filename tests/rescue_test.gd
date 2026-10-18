extends Node
## Rescues (decision 428), on a clock of their own with the real rules
## (levels/economy.json "rescue", "stand_in"): a hostile camp holds a
## stranger for its home town, drawn by the camp (the same every run),
## weighted to trades the town has nobody of; when the camp falls to
## nobody or the town (Holdings.place_taken -> camp_taken) the residents a
## raid took and it holds come home to their work, and the stranger joins
## the town with their trade, logged; taken by another hostile faction,
## nothing; restocked only after rescue.restock_days; a raid group's
## captives freed by free_held; saved and loaded. The fletcher mends a
## worn bundle; with no fletcher in town the carpenter stands in. Someone
## the town remembers moves in (460) only with room, once, no xp or gold.
## Reads the repo's levels, never the shared overlay.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const TOWN := "rc/store"
const CAMP := "rc/camp@40,40"
const DAY := 54000

var _failures := 0
var _now := 0
var _rules := {}


func _ready() -> void:
	World.set_process(false)
	DayNight.day_steps = DAY
	_rules = Production.read_rules()
	_test_strangers()
	_test_freed()
	_test_lacking()
	_test_fletcher()
	_test_lawspeaker()
	_test_move_in()
	_test_sick_and_died()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _towns() -> Towns:
	_now = 0
	var clock := func() -> int: return _now
	var stock := Stockpile.new({}, clock, ItemBook.new(clock))
	var work := Production.new({}, stock, null, clock, _rules)
	var towns := Towns.new({}, work, _rules, clock)
	towns.camps = func() -> Array: return [{"id": CAMP, "area": "rc", "cell": Vector2i(40, 40), "faction": "goblins"}]
	towns.home_of = func(_camp: String) -> String: return TOWN
	towns.note_rescue(TOWN, "r1", "Dag", "carpenter")
	return towns


func _test_strangers() -> void:
	print("\n== a hostile camp holds a stranger ==")
	var towns := _towns()
	towns.tick()
	var held: Array = towns.strangers(TOWN).get(CAMP, [])
	_check(held.size() == int(_rules["rescue"]["per_camp"]) and str(held[0]["trade"]) in _rules["rescue"]["trades"],
		"per_camp strangers, of a rescue trade (%s)" % [held])
	var again := _towns()
	again.tick()
	_check(again.strangers(TOWN) == towns.strangers(TOWN), "the same stranger every run")
	towns.tick()
	_check(towns.strangers(TOWN)[CAMP].size() == held.size(), "held once, not again each tick")
	towns.set_memory(TOWN, [{"id": "m1", "tier": "rumour", "text": "the well is cursed"}])
	towns.set_lawspeaker(TOWN, {"name": "Ulf", "last_round": 3, "rulings": []})
	var saved := Towns.new(JSON.parse_string(JSON.stringify(towns.to_dict())), towns.production, _rules, func() -> int: return _now)
	_check(saved.strangers(TOWN) == towns.strangers(TOWN), "saved and loaded")
	_check(saved.memory(TOWN)[0]["text"] == "the well is cursed" and saved.lawspeaker(TOWN)["name"] == "Ulf" and saved.memory("x/none") == [],
		"npc's memory and lawspeaker kept with the town, as they are")


func _test_freed() -> void:
	print("\n== the camp falls: everyone it holds comes home ==")
	var towns := _towns()
	towns.tick()
	var stranger: Dictionary = towns.strangers(TOWN)[CAMP][0]
	towns._take(TOWN, "r1", "goblins", "g1")
	towns.carried_home(TOWN, "g1", "goblins", ["r1"], CAMP)
	_check("r1" not in towns.residents(TOWN) and towns.captives(TOWN).size() == 1, "(Dag taken in a raid and held at the camp)")
	towns.camp_taken(CAMP, "goblins", "orcs")
	_check("r1" not in towns.residents(TOWN), "taken by another hostile faction: nobody freed")
	var xp := towns.xp_earned(TOWN)
	towns.camp_taken(CAMP, "goblins", Factions.NOBODY)
	_check("r1" in towns.residents(TOWN) and not towns.production.worker("r1")["away"], "Dag comes home to his work")
	_check(str(stranger["id"]) in towns.residents(TOWN) and towns.production.worker(str(stranger["id"]))["trades"] == [stranger["trade"]],
		"the stranger joins the town as a %s" % stranger["trade"])
	_check(towns.xp_earned(TOWN) == xp + 2 * int(_rules["xp"]["rescue"]), "experience for each rescue")
	_check(towns.log_of(TOWN).any(func(line: Dictionary) -> bool: return line["what"] == "%s the %s was held at %s" % [stranger["name"], str(stranger["trade"]).replace("_", " "), CAMP]),
		"the log says where they were held")
	_check(towns.strangers(TOWN).is_empty(), "nobody held there now")
	towns.tick()
	_check(towns.strangers(TOWN).is_empty(), "retaken at once: not restocked yet")
	_now += int(float(_rules["rescue"]["restock_days"]) * DAY) + 1
	towns.tick()
	_check(towns.strangers(TOWN).get(CAMP, []).size() == int(_rules["rescue"]["per_camp"]), "after restock_days, someone new")

	print("  a raid group that breaks up on the way frees what it carries")
	var group := _towns()
	group._take(TOWN, "r1", "goblins", "g2")
	_check(group.free_held("g2") == ["r1"] and "r1" in group.residents(TOWN), "free_held by the group's id")


## A town with every trade has the weights as they are; one with none of
## them draws each lacking trade rescue.lacking times as often.
func _test_lacking() -> void:
	print("\n== strangers are drawn toward what the town lacks ==")
	var towns := _towns()
	var counts := {}
	var draw := RandomNumberGenerator.new()
	for i in 600:
		draw.seed = i
		var trade := towns._draw_trade(TOWN, draw)
		counts[trade] = int(counts.get(trade, 0)) + 1
	var weights: Dictionary = _rules["rescue"]["trades"]
	_check(int(counts.get("carpenter", 0)) < int(counts.get("smith", 0)), "the town has a carpenter: fewer carpenters drawn than smiths (%s)" % [counts])
	_check(int(counts.get("hunter", 0)) > int(counts.get("smith", 0)) * float(weights["hunter"]) / float(weights["smith"]) * 0.6,
		"hunters by their weight (%s)" % [counts])


func _test_fletcher() -> void:
	print("\n== the fletcher mends; the carpenter stands in ==")
	for with_fletcher in [true, false]:
		_now = 0
		var clock := func() -> int: return _now
		var work := Production.new({}, Stockpile.new({}, clock, ItemBook.new(clock)), null, clock, _rules)
		var worn := work.book().mint("arrows", "made", "test")
		work.book().set_condition(worn, 2)
		work.stockpile.bank(TOWN, worn, "Bo")
		work.stockpile.deposit(TOWN, "leather", 2)
		work.stockpile.deposit(TOWN, "wood", 2)
		work.add_worker("p1", "Pell", ["carpenter"], TOWN)
		work.add_workshop(TOWN + ":carpenter", "carpenter", TOWN)
		work.assign(TOWN + ":carpenter", "p1")
		if with_fletcher:
			work.add_worker("f1", "Ivo", ["fletcher"], TOWN)
			work.add_workshop(TOWN + ":fletcher", "fletcher", TOWN)
			work.assign(TOWN + ":fletcher", "f1")
		var shop := ""
		for i in 20:
			_now += World.WORLD_TICK_STEPS
			work.tick()
			for id in work.jobs():
				if work.job(id)["kind"] == "work":
					shop = str(work.job(id)["workshop"])
			if not shop.is_empty():
				break
		var expect := TOWN + (":fletcher" if with_fletcher else ":carpenter")
		_check(shop == expect, "%s: mended at %s" % ["a fletcher in town" if with_fletcher else "no fletcher", shop])


## A town of official_from residents of its own gets its lawspeaker (npc's
## 459, economy's side): appointed once, paid as an official.
func _test_lawspeaker() -> void:
	print("
== the lawspeaker ==")
	var towns := _towns()
	var from := int(_rules["official"]["lawspeaker"]["from"])
	for i in from - 2:
		towns.note_rescue(TOWN, "f%d" % i, "Folk%d" % i, "hauler")
	towns.tick()
	var lawspeakers := func() -> Array: return towns.residents(TOWN).filter(func(who: String) -> bool: return "lawspeaker" in towns.production.worker(who)["trades"])
	_check(lawspeakers.call().is_empty() and towns.residents(TOWN).size() == from - 1, "%d residents: none yet" % towns.residents(TOWN).size())
	towns.note_rescue(TOWN, "f9", "Folk9", "hauler")
	towns.tick()
	towns.tick()
	var appointed: Array = lawspeakers.call()
	_check(appointed.size() == 1 and towns.production.worker(appointed[0])["origin"] == "appointed"
		and str(towns.production.worker(appointed[0])["name"]) in _rules["official"]["lawspeaker"]["names"], "%d: one is appointed (%s)" % [from, appointed])
	_check(_rules["official"]["lawspeaker"]["wage"] == _rules["official"]["priest"]["wage"], "paid as the priest")


## Someone the town remembers moves in (decision 460's economy side).
func _test_move_in() -> void:
	print("
== moving in ==")
	var towns := _towns()
	var gold := towns.production.stockpile.count(TOWN, "gold")
	var xp := towns.xp_earned(TOWN)
	var told := []
	towns.rescued.connect(func(_town: String, who: String, _by: String) -> void: told.append(who))
	var marta := "remembered:%s:Marta" % TOWN
	_check(towns.move_in(TOWN, marta, "Marta", "cook"), "Marta moves in")
	var w := towns.production.worker(marta)
	_check(marta in towns.residents(TOWN) and w["origin"] == "remembered" and w["trades"] == ["cook"]
		and towns.log_of(TOWN).any(func(line: Dictionary) -> bool: return line["what"] == "Marta is found to have lived here all along"), "a resident, remembered, a cook, logged")
	_check(towns.xp_earned(TOWN) == xp and towns.production.stockpile.count(TOWN, "gold") == gold and told.is_empty(), "no xp, no gold, no rescued signal")
	_check(not towns.move_in(TOWN, marta, "Marta", "cook"), "not twice")
	_check(towns.move_in(TOWN, "snagfin", "Snagfin", "hauler", "remembered", "thief") and towns.production.worker("snagfin")["type"] == "thief", "a type when given")
	while towns.residents(TOWN).size() < towns.room(TOWN):
		towns.note_rescue(TOWN, "f%d" % towns.residents(TOWN).size(), "Folk", "hauler")
	_check(not towns.move_in(TOWN, "remembered:%s:Timmy" % TOWN, "Timmy", "hauler") and towns.production.worker("remembered:%s:Timmy" % TOWN).is_empty(),
		"no room: they wait (%d residents)" % towns.residents(TOWN).size())
	_check(towns.move_in(TOWN, "settler", "Snag", "merchant", "settled"), "one settled comes with no room: his own stall, not the town's growth")


## Sickness's economy side (decision 501): a sick resident kept from work
## with their needs still due; a death by npc's word, the purse to the loan
## then the treasury, the residents and records cleared, the log told.
func _test_sick_and_died() -> void:
	print("
== sick, and died ==")
	var towns := _towns()
	var work := towns.production
	towns.note_rescue(TOWN, "h1", "Hob", "hunter")
	work.set_sick("h1", true)
	_check(Production.off_work(work.worker("h1")) and not bool(work.worker("h1")["away"]), "sick: kept from work, not away")
	var told := []
	towns.resident_died.connect(func(town: String, who: String, name: String, why: String) -> void: told.append([town, who, name, why]))
	work.pay("h1", 12)
	work.set_loan("h1", 5.0)
	var gold := work.stockpile.count(TOWN, "gold")
	_check(towns.died(TOWN, "h1", "the fever") and "h1" not in towns.residents(TOWN) and work.worker("h1").is_empty()
		and work.stockpile.count(TOWN, "gold") == gold + 12 and told == [[TOWN, "h1", "Hob", "the fever"]]
		and towns.log_of(TOWN).any(func(line: Dictionary) -> bool: return line["what"] == "Hob died of the fever"),
		"died: gone from the town, the 12 gold to the loan and the treasury, the log and the signal")
	_check(not towns.died(TOWN, "h1", "the fever") and not towns.died(TOWN, "companion:x", "the fever"), "nobody twice, and never a companion")


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
