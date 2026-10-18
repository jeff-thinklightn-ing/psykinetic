class_name Townsfolk
extends RefCounted
## Who the town's people are beyond their trade (decision 393, the npc
## tree's): each resident has a hidden personality type (lore's roles.json
## "types": steady for most, thief, bard, scoundrel and, once Jeff agrees
## them, scholar and merchant), rolled once at founding and never shown
## (not in the label, no panel, no prose, no ledger name). The type and the
## profession together make the person's speech profile (Lore.profile) and
## what they do on the side.
##
## The roll (roll_type) is by worker id, the same every time, as a
## companion's card is, so an older save rolls the same type on load and a
## record made again keeps it. Only the types that count (Lore.types(),
## agreed) are rolled, by levels/townsfolk.json's type_weights, each a share
## per 100 residents; past them the person is steady. A companion resting
## in town ("companion:<player id>") has no type: her card is who she is.
## Economy's Production keeps the type on the worker record
## (Production.type_of is this roll, set by Main) and saves it.
##
## Side-doings, one per type, on the world tick after the residents' own
## trade (World.world_tick, slice 0; tick): a thief in town, every "every"
## steps on a "lift" clock in the record's needs, with "chance", takes one of
## the first of "takes" the store holds more than "leave" of (never gold,
## never the last of anything) through Stockpile.take with reason MISSING:
## the ledger says only that something is missing from the store. The goods
## vanish; no gold is made or moved. Server only.
##
## Each resident's card (decision 398, ResidentCard) is kept here too:
## card_of makes it when first needed (rolled by the id; kin and a grudge
## against the neighbours who have cards) and keeps it on the worker
## record; watch grows every card from the town's events (Towns.raided,
## Towns.rescued, Production.loan_changed), saw_raiders from what a body
## sees, and learn is the one way a fact is written: once, told to the
## transcript and the mind log.

const FILE := "res://levels/townsfolk.json"
const STEADY := "steady"
const THIEF := "thief"
const SCHOLAR := "scholar"
## The thief's clock in the worker record's needs (Production.need_due).
const LIFT := "lift"
## The ledger's "by" for a lift: no name.
const MISSING := "missing"
const COMPANION := "companion:"

static var _rules := {}


## The rules (FILE), read on first use.
static func rules() -> Dictionary:
	if _rules.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE)) if FileAccess.file_exists(FILE) else null
		if data is Dictionary:
			_rules = data
		else:
			push_warning("[townsfolk] %s is missing or not a JSON object: no types are rolled" % FILE)
			_rules = {"_none": true}
	return _rules


## Uses [param given] in place of FILE ({} to read the file again): tests.
static func use_rules(given: Dictionary) -> void:
	_rules = given.duplicate(true)


## Each type's share per 100 residents at the founding roll, as the rules
## have it (a type not listed is never rolled).
static func type_weights() -> Dictionary:
	var out := {}
	var weights: Variant = rules().get("type_weights", {})
	if weights is Dictionary:
		for type: Variant in weights:
			out[str(type)] = maxf(float(weights[type]), 0.0)
	return out


## The hidden personality type of the resident whose worker id is
## [param worker_id]: one draw of 0..100 seeded by the id, walked over the
## agreed types' weights in roles.json's order; past them STEADY. "" (none)
## for a companion resting in town or no id.
static func roll_type(worker_id: String) -> String:
	if worker_id.is_empty() or worker_id.begins_with(COMPANION):
		return ""
	var weights := type_weights()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("type:" + worker_id)
	var draw := rng.randf() * 100.0
	var at := 0.0
	for type: String in Lore.types():
		at += float(weights.get(type, 0.0))
		if draw < at:
			return type
	return STEADY


## Every resident's side-doing that is due: the thief's lift (lift). Called
## by the world tick after Economy.tick; tests call it with a clock of
## their own.
static func tick(production: Production, stockpile: Stockpile, economy: Economy = null) -> void:
	if production == null or stockpile == null:
		return
	stray(production)  # Someone lost beyond the walls, and the lost come home (decision 487).
	var thief: Dictionary = rules().get("thief", {})
	var every := int(thief.get("every", 0))
	if every <= 0:
		return
	var at := production.now()
	for id: String in production.worker_ids():
		var who := production.worker(id)
		if str(who.get("type", "")) != THIEF or bool(who.get("away", false)) or str(who.get("town", "")).is_empty():
			continue
		var due := production.need_due(id, LIFT)
		if due == 0:
			production.set_need_due(id, LIFT, at + every)
			continue
		if at < due:
			continue
		production.set_need_due(id, LIFT, at + every)
		if _chance(id, due) >= float(thief.get("chance", 1.0)):
			continue
		if int(production.worker(id).get("card", {}).get("lie_low_until", 0)) > at:
			continue  # Caught too often: he lies low a while (decision 461).
		var town := str(who["town"])
		# Gold from the richest purse above the line first (decision 461:
		# "thieves could be the answer to balancing the economy"), else goods.
		var victim := _mark(production, town, id, thief, _rich_line(economy))
		if not victim.is_empty():
			var gold := _lift_gold(production, town, id, victim, thief, at, due)
			if gold != 0:
				continue
		var goods := lift(stockpile, town, thief)
		if goods.is_empty():
			continue
		var catcher := _catcher(production, town, id, "", at, due, thief)
		if not catcher.is_empty():
			stockpile.deposit(town, goods, 1, "returned")
			_caught(production, town, id, catcher, "", "taking %s from the store" % goods.replace("_", " "), at, thief)
			continue
		var merchant := _merchant(production, town, id)
		if not merchant.is_empty() and economy != null and economy.has_method("fence"):
			economy.fence(town, merchant, id, goods, float(thief.get("fence", 0.5)), float(thief.get("margin", 0.4)))


## Economy's line for a rich purse (economy.json folk.rich_above, the same
## line its dole and prices use): [param economy]'s rules, else the file's.
static func _rich_line(economy: Economy) -> int:
	var rules: Dictionary = economy.rules if economy != null and economy.rules is Dictionary else Production.read_rules(Economy.PATH)
	return int(rules.get("folk", {}).get("rich_above", 25))


## The card key of someone lost beyond the walls (decision 487): {since,
## cell: [x, y] once Main chose where they stand}.
const STRAYED := "strayed"
static var _stray_due := {}


## Strays (decision 487; townsfolk.json "strays"): every "every" steps, by
## town, a seeded draw against "chance" sends one of the town's people of
## the listed trades (not away, never an official, the merchant or an
## outcast) beyond the walls: the card says so, economy counts them away
## (no work, no meals), a fact on their card; one at a time per town. The
## lost come home on their own after "days" (came_home with nobody), so no
## one is ever stranded. Where they stand is Main's to choose, with the
## zone in hand (set_stray_cell).
static func stray(production: Production) -> void:
	if production == null:
		return
	var rule: Dictionary = rules().get("strays", {})
	var every := int(rule.get("every", 0))
	if every <= 0:
		return
	var at := production.now()
	var day := maxi(DayNight.day_steps, 1)
	var towns := {}
	for id: String in production.worker_ids():
		var town := str(production.worker(id).get("town", ""))
		if not town.is_empty() and not id.begins_with(COMPANION):
			towns.get_or_add(town, []).append(id)
	var names: Array = towns.keys()
	names.sort()
	for town: String in names:
		var lost := strayed_of(production, town)
		var home_today := false
		for id: String in lost:
			if at - int(lost[id].get("since", at)) >= int(rule.get("days", 3)) * day:
				came_home(production, id, "")
				home_today = true
		var due := int(_stray_due.get(town, 0))
		if due == 0:
			_stray_due[town] = at + every
			continue
		if at < due:
			continue
		_stray_due[town] = at + every
		if home_today or not strayed_of(production, town).is_empty():
			continue  # One at a time, and not again the day one came home.
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("stray:%s:%d" % [town, due])
		if rng.randf() >= float(rule.get("chance", 0.0)):
			continue
		var trades: Array = rule.get("trades", [])
		var could: Array[String] = []
		for id: String in towns[town]:
			var who := production.worker(id)
			if bool(who.get("away", false)) or str(who.get("origin", "")) == "appointed" or str(who.get("type", "")) == "merchant":
				continue
			if _trade_of(production, id) not in trades or bool(card_of(production, id).get("outcast", false)):
				continue
			could.append(id)
		if could.is_empty():
			continue
		could.sort()
		var id := could[rng.randi() % could.size()]
		var card := card_of(production, id)
		card[STRAYED] = {"since": at}
		production.set_card(id, card)
		production.set_away(id, true)
		var name := str(production.worker(id).get("name", id))
		learn(production, id, "%s lost %s way beyond the walls." % [name, _their(card)])
		print("[townsfolk] %s: %s has not come back from beyond the walls, step %d" % [town, name, at])


## The lost of [param town]: id -> the card's strayed record ({since, cell?}).
static func strayed_of(production: Production, town: String) -> Dictionary:
	var out := {}
	for id: String in production.worker_ids(town):
		var record: Variant = production.worker(id).get("card", {}).get(STRAYED)
		if record is Dictionary:
			out[id] = record
	return out


## Where the lost [param id] stands, once Main chose it; null before.
static func stray_cell(production: Production, id: String) -> Variant:
	var record: Variant = card_of(production, id).get(STRAYED)
	if record is Dictionary and record.get("cell") is Array and record["cell"].size() == 2:
		return Vector2i(int(record["cell"][0]), int(record["cell"][1]))
	return null


## Main chose [param cell] for the lost [param id] (kept on the card, so a
## body is made there again after a zone change or a save).
static func set_stray_cell(production: Production, id: String, cell: Vector2i) -> void:
	var card := card_of(production, id)
	if card.get(STRAYED) is Dictionary:
		card[STRAYED]["cell"] = [cell.x, cell.y]
		production.set_card(id, card)


## The lost [param id] is home: walked by [param by_name] (a player), or on
## their own (""): the card's record goes, economy counts them back, a
## fact says how.
static func came_home(production: Production, id: String, by_name: String) -> void:
	var card := card_of(production, id)
	if not card.get(STRAYED) is Dictionary:
		return
	var since := int(card[STRAYED].get("since", production.now()))
	card.erase(STRAYED)
	production.set_card(id, card)
	production.set_away(id, false)
	var name := str(production.worker(id).get("name", id))
	if by_name.is_empty():
		var days := maxi(int((production.now() - since) / maxi(DayNight.day_steps, 1)), 1)
		learn(production, id, "%s found %s own way home after %d day%s beyond the walls." % [name, _their(card), days, "" if days == 1 else "s"])
	else:
		learn(production, id, "%s walked %s home from beyond the walls." % [by_name, name])


## "her", "his" or "their" for [param card]'s pronoun.
static func _their(card: Dictionary) -> String:
	return {"she": "her", "he": "his"}.get(str(card.get("traits", {}).get("pronoun", "")), "their")


## Quarrels before the lawspeaker (decision 486): in [param town], with a
## sitting lawspeaker and rulings on (Offers.ctx "lawspeaker_of", "model"),
## every pair of its people whose card holds a grudge against the other
## gets one entry in [param log] if none is open for the pair: "A and B are
## at odds" (since the card's latest fact naming the other, when there is
## one), said by the one whose grudge it is, a candidate from the start
## with "dispute" and "pair", so his next batch takes it first. Nothing
## with the lawspeaker off: the box's grudges stay as they were. Whether
## anything was noted.
static func note_disputes(production: Production, town: String, log: Array, at: int) -> bool:
	if production == null:
		return false
	var law := str(Offers._call(Offers.ctx, "lawspeaker_of", [town]))
	var model := str(Offers._call(Offers.ctx, "model"))
	if law.is_empty() or law == "<null>" or model.is_empty() or model == "off" or model == "<null>":
		return false
	var changed := false
	var ids := production.worker_ids(town)
	ids.sort()
	for a: String in ids:
		if a.begins_with(COMPANION):
			continue
		for other: Variant in production.worker(a).get("card", {}).get("grudge", []):
			var b := str(other)
			if b.begins_with(COMPANION) or production.worker(b).is_empty() or str(production.worker(b).get("town", "")) != town:
				continue
			if not dispute_of(log, a, b).is_empty():
				continue
			var a_name := str(production.worker(a).get("name", a))
			var b_name := str(production.worker(b).get("name", b))
			var text := "%s and %s are at odds" % [a_name, b_name]
			var why := _why_at_odds(production, a, b_name)
			if not why.is_empty():
				text += " since " + why
			var entry := TownMemory.note(log, text, a, b, at)
			if entry.is_empty() or str(entry.get("tier", "")) not in [TownMemory.BELIEF, TownMemory.CANDIDATE] or not entry.get("ruling", {}).is_empty():
				continue  # The same words already ruled on: that quarrel is closed.
			entry["tier"] = TownMemory.CANDIDATE
			entry["dispute"] = true
			entry["pair"] = [a, b]
			changed = true
	return changed


## The open dispute of [param log] between [param a] and [param b], either
## way round (noted, not yet ruled); {} for none.
static func dispute_of(log: Array, a: String, b: String) -> Dictionary:
	for entry: Variant in log:
		if not entry is Dictionary or not entry.get("pair") is Array:
			continue
		var pair: Array = entry["pair"]
		if (pair == [a, b] or pair == [b, a]) and str(entry.get("tier", "")) in [TownMemory.BELIEF, TownMemory.CANDIDATE] and entry.get("ruling", {}).is_empty():
			return entry
	return {}


## The latest fact on [param a]'s card from after its founding (an event:
## a catch, a word; never the founding's kin lines) that names
## [param b_name], as a clause ("odo caught sly with a hand in odo's purse",
## lower-cased at the front, no full stop); "" for none.
static func _why_at_odds(production: Production, a: String, b_name: String) -> String:
	var facts: Array = card_of(production, a).get("facts", [])
	if facts.is_empty():
		return ""
	var founding := int(facts[0].get("step", 0)) if facts[0] is Dictionary else 0
	for i in range(facts.size() - 1, -1, -1):
		if not facts[i] is Dictionary or int(facts[i].get("step", 0)) <= founding:
			continue
		var text := str(facts[i].get("text", ""))
		if text.contains(b_name):
			return Hearsay._lower_first(text.trim_suffix("."))
	return ""


## The richest of [param town]'s people above [param line] (economy's
## folk.rich_above; never [param thief], a resting companion, one on the
## dole or hungry), with at least the take to spare; "" for none.
static func _mark(production: Production, town: String, thief: String, rule: Dictionary, line: int) -> String:
	var take := int(rule.get("gold_take", 0))
	var best := ""
	var most := 0
	for id: String in production.worker_ids(town):
		if id == thief or id.begins_with(COMPANION):
			continue
		var who := production.worker(id)
		if bool(who.get("away", false)) or str(who.get("fed", "")) in ["dole", "hungry"]:
			continue
		var purse := int(who.get("purse", 0))
		if purse > line and purse >= line + take and purse > most:
			most = purse
			best = id
	return best


## [param thief] lifts the take from [param victim]'s purse (economy's
## Production.lift_gold), the victim's card remembering a loss with no name;
## or is caught at it. The gold moved (0 for none, or caught).
static func _lift_gold(production: Production, town: String, thief: String, victim: String, rule: Dictionary, at: int, due: int) -> int:
	if not production.has_method("lift_gold"):
		return 0
	var taken := int(production.lift_gold(victim, int(rule.get("gold_take", 0)), thief))
	if taken <= 0:
		return 0
	var catcher := _catcher(production, town, thief, victim, at, due, rule)
	if not catcher.is_empty():
		if production.has_method("return_gold"):
			production.return_gold(thief, victim, taken)
		_caught(production, town, thief, catcher, victim, "with a hand in %s's purse" % production.worker(victim).get("name", victim), at, rule)
		return taken
	var pronoun := str(production.worker(victim).get("card", {}).get("traits", {}).get("pronoun", "their"))
	learn(production, victim, "%s missed %d gold from %s purse." % [production.worker(victim).get("name", victim), taken,
		{"she": "her", "he": "his"}.get(pronoun, "their")])
	return taken


## Who catches [param thief] at [param at], if anyone: the victim when their
## routine puts them where the thief is at the hour he picks (drawn by the
## day between six and ten at night: his clock ticks at one hour of the
## day, and a fixed hour would never meet anyone), a meeting place; or a
## guard at the same place (or at work, for the store); by a seeded draw
## against "caught" / "caught_guard". "" for nobody.
static func _catcher(production: Production, town: String, thief: String, victim: String, at: int, due: int, rule: Dictionary) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("caught:%s:%d" % [thief, due])
	var draw := rng.randf()
	var hour := 6.0 + rng.randf() * 16.0
	var season := Season.name_at(at)
	var day := day_of(at)
	var where := whereabouts(_trade_of(production, thief), hour, season, THIEF, thief, day)
	var meeting := where in ["well", "inn", "square", "temple"]
	if not victim.is_empty() and meeting:
		var theirs := whereabouts(_trade_of(production, victim), hour, season, str(production.worker(victim).get("type", "")), victim, day)
		if theirs == where and draw < float(rule.get("caught", 0.0)):
			return victim
	for id: String in production.worker_ids(town):
		if id == thief or _trade_of(production, id) != "guard" or bool(production.worker(id).get("away", false)):
			continue
		var post := whereabouts("guard", hour, season, str(production.worker(id).get("type", "")), id, day)
		if (victim.is_empty() and post == "work") or (not victim.is_empty() and post == where and meeting):
			if draw < float(rule.get("caught_guard", 0.0)):
				return id
	return ""


## Caught: facts on the catcher's, the victim's and the thief's cards, a
## grudge from the catcher and the victim against him, a dispute for the
## lawspeaker in the town's memory log, and, caught enough times in a
## season, lying low.
static func _caught(production: Production, town: String, thief: String, catcher: String, victim: String, doing: String, at: int, rule: Dictionary) -> void:
	var thief_name := str(production.worker(thief).get("name", thief))
	var catcher_name := str(production.worker(catcher).get("name", catcher))
	learn(production, catcher, "%s caught %s %s." % [catcher_name, thief_name, doing])
	learn(production, thief, "%s was caught %s by %s." % [thief_name, doing, catcher_name])
	for id: String in ([catcher] if victim.is_empty() or victim == catcher else [catcher, victim]):
		if id != catcher:
			learn(production, id, "%s caught %s %s." % [catcher_name, thief_name, doing])
		var card := card_of(production, id)
		if not card.is_empty():
			var grudges: Array = card.get("grudge", [])
			if thief not in grudges:
				grudges.append(thief)
				card["grudge"] = grudges
				production.set_card(id, card)
	var log: Variant = Offers._call(Offers.ctx, "memory", [town])
	if log is Array:
		var dispute := TownMemory.note(log, "%s was caught %s" % [thief_name, doing], catcher, "", at)
		if not dispute.is_empty() and str(dispute.get("tier", "")) in [TownMemory.BELIEF, TownMemory.CANDIDATE] and dispute.get("ruling", {}).is_empty():
			dispute["dispute"] = true  # For the lawspeaker's rounds (phase 3).
			dispute["tier"] = TownMemory.CANDIDATE  # Before him at once, not talk to spread (decision 486).
			dispute["pair"] = [catcher, thief]
		Offers._call(Offers.ctx, "set_memory", [town, log])
	var mine := card_of(production, thief)
	if mine.is_empty():
		return
	var season := int(rule.get("caught_season_days", 90)) * maxi(DayNight.day_steps, 1)
	var times: Array = mine.get("caught", []).filter(func(step: Variant) -> bool: return at - int(step) < season)
	times.append(at)
	mine["caught"] = times
	if times.size() >= int(rule.get("caught_before_lying_low", 3)):
		mine["lie_low_until"] = at + int(rule.get("lie_low_days", 30)) * maxi(DayNight.day_steps, 1)
		mine["caught"] = []
	production.set_card(thief, mine)


## A merchant of [param town] who is not [param thief], to fence through; "".
static func _merchant(production: Production, town: String, thief: String) -> String:
	for id: String in production.worker_ids(town):
		if id != thief and not id.begins_with(COMPANION) and str(production.worker(id).get("type", "")) == "merchant" \
				and not bool(production.worker(id).get("away", false)):
			return id
	return ""


## A thief's lift at [param town]'s store: one of the first of the rules'
## takes ([param thief]: the rules' "thief" when none is given) the store
## holds more than leave of, taken with reason MISSING. What went missing,
## "" for nothing.
static func lift(stockpile: Stockpile, town: String, thief: Dictionary = {}) -> String:
	var rule: Dictionary = thief if not thief.is_empty() else rules().get("thief", {})
	var leave := int(rule.get("leave", 2))
	for what: Variant in rule.get("takes", []):
		var goods := str(what)
		if goods == "gold" or stockpile.count(town, goods) <= leave:
			continue
		if stockpile.take(town, goods, 1, MISSING):
			return goods
	return ""


## A draw in 0..1 for [param worker_id]'s lift due at [param due]: the same
## every time, so a replayed day lifts the same.
static func _chance(worker_id: String, due: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("lift:%s:%d" % [worker_id, due])
	return rng.randf()


# --- Resident cards (decision 398) ---------------------------------------------------

## Resident [param worker_id]'s card (ResidentCard), from the worker record;
## made when first needed (rolled by the id, the same every time, kin and a
## grudge rolled against the neighbours who have cards already) and kept on
## the record (Production.set_card). {} for a companion or no such worker.
static func card_of(production: Production, worker_id: String) -> Dictionary:
	if production == null or worker_id.begins_with(COMPANION):
		return {}
	var who := production.worker(worker_id)
	if who.is_empty():
		return {}
	var card: Variant = who.get("card", {})
	if card is Dictionary and not card.is_empty():
		return card
	var trades: Array = who.get("trades", [])
	card = ResidentCard.roll(worker_id, str(who.get("name", worker_id)), str(trades[0]) if not trades.is_empty() else "", str(who.get("origin", "")))
	production.set_card(worker_id, card)
	_found_among(production, worker_id, card, str(who.get("town", "")))
	production.set_card(worker_id, card)
	return card


## The people settled in a town by name (residents.json "settled", decision
## 471): id -> {name, town, trade, type, kind, home, came, fact, outcast}.
static func settled() -> Dictionary:
	var table: Variant = days().get("settled", {})
	var out := {}
	if table is Dictionary:
		for id: String in table:
			if table[id] is Dictionary and not id.begins_with("_"):
				out[id] = table[id]
	return out


## At founding, [param card]'s kin and grudge (resident_traits.json "kin",
## "grudge": a chance each, by the id) among [param town]'s residents who
## have cards: the facts written into both cards.
static func _found_among(production: Production, worker_id: String, card: Dictionary, town: String) -> void:
	if bool(card.get("outcast", false)):
		return  # Tolerated, not kin to anyone (decision 471).
	var table := ResidentCard.tables()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("kin:" + worker_id)
	var others: Array[String] = []
	for id: String in production.worker_ids(town):
		if id != worker_id and not id.begins_with(COMPANION) and production.worker(id).get("card", {}) is Dictionary \
				and not production.worker(id).get("card", {}).is_empty():
			others.append(id)
	var step := production.now()
	var kin: Dictionary = table.get("kin", {})
	var kin_draw := rng.randf()
	var kin_pick := rng.randi()
	var kind_pick := rng.randi()
	var grudge: Dictionary = table.get("grudge", {})
	var grudge_draw := rng.randf()
	var grudge_pick := rng.randi()
	var cause_pick := rng.randi()
	if others.is_empty():
		return
	if kin_draw < float(kin.get("chance", 0.0)) and kin.get("kinds") is Array and not kin["kinds"].is_empty():
		var other := others[kin_pick % others.size()]
		var theirs: Dictionary = production.worker(other)["card"]
		var kind := str(kin["kinds"][kind_pick % kin["kinds"].size()])
		var both := ResidentCard.kin_facts(card, theirs, kind)
		_true(card, step, both[0])
		_true(theirs, step, both[1])
		# Kept by id too (decision 422: kin hear gossip first).
		card.get_or_add("kin", {})[other] = kind
		theirs.get_or_add("kin", {})[worker_id] = kind
		production.set_card(other, theirs)
	if grudge_draw < float(grudge.get("chance", 0.0)) and grudge.get("causes") is Array and not grudge["causes"].is_empty():
		var other := others[grudge_pick % others.size()]
		var theirs: Dictionary = production.worker(other)["card"]
		var text := ResidentCard.grudge_fact(card, theirs, str(grudge["causes"][cause_pick % grudge["causes"].size()]))
		_true(card, step, text)
		_true(theirs, step, text)
		# Kept by id too (decision 422: no gossip across a grudge).
		card.get_or_add("grudge", []).append(other)
		theirs.get_or_add("grudge", []).append(worker_id)
		production.set_card(other, theirs)


## Grows the cards from the town's events: Towns.raided (a neighbour
## carried off, witnessed), Towns.rescued (home again), and
## Production.loan_changed. Once per instance.
static var _watching: Dictionary = {}

static func watch(production: Production, towns: Towns) -> void:
	if production == null:
		return
	var held: Variant = _watching.get(production.get_instance_id())
	if held is WeakRef and held.get_ref() == production:
		return
	# The closures hold the record weakly: one holding it strongly, hung on its
	# own signal, is a cycle that keeps it (and these scripts) alive at exit.
	var weak: WeakRef = weakref(production)
	_watching[production.get_instance_id()] = weak
	production.loan_changed.connect(func(worker_id: String, owed: float, working_off: bool) -> void:
		var kept: Production = weak.get_ref()
		if kept != null:
			_loan(kept, worker_id, owed, working_off))
	if towns != null:
		towns.raided.connect(func(town: String, report: Dictionary) -> void:
			var kept: Production = weak.get_ref()
			if kept != null:
				_raided(kept, town, report))
		towns.rescued.connect(func(town: String, who_id: String, by: String) -> void:
			var kept: Production = weak.get_ref()
			if kept != null:
				_rescued(kept, town, who_id, by))


## Gossip (decision 422): what a town's person believes or saw passes to a
## neighbour standing at the same meeting place. Every "gossip.every" steps
## (residents.json) per town, its residents (not away, not companions) are
## grouped by where they are now (whereabouts); in each group of two or
## more at one of "gossip.places" (the well, the inn, the square, the
## temple: never at work or at home) one teller passes one thing to one
## hearer, by a roll seeded by the town, the place and the step: the
## teller's newest believed hearsay the hearer does not hold, else the
## teller's newest card fact the hearer has not heard (never one naming the
## hearer). The hearer keeps it through Hearsay.hear from the teller's name,
## with the believe roll on its intellect: a passed-on belief as "beyond",
## a first-hand fact as "witnessed" (believed always), "where" the place.
## Kin are picked first as hearers; nobody gossips with one they hold a
## grudge against, either way. An official (Lore.binding) tells only what
## it saw, and what it hears never reaches its voice (378 as it is). One
## pass per group per tick; the heard cap as it is. No model call. Each
## pass to the transcript under both names and to mind.log (kind "gossip").
static var _gossip_due: Dictionary = {}

static func gossip(production: Production) -> void:
	if production == null:
		return
	var rule: Dictionary = days().get("gossip", {})
	var every := int(rule.get("every", 0))
	if every <= 0:
		return
	var at := production.now()
	var hour := DayNight.hour(at)
	if is_nan(hour) or is_inf(hour):
		return  # No day length set: nobody knows where anyone is.
	var towns := {}  # town -> [worker ids]
	for id: String in production.worker_ids():
		# A companion resting in town (her record there and not away) stands
		# among them (companions' 442): she tells only what she believes.
		var who := production.worker(id)
		if bool(who.get("away", false)) or str(who.get("town", "")).is_empty():
			continue
		towns.get_or_add(str(who["town"]), []).append(id)
	var places: Array = rule.get("places", ["well", "inn", "square", "temple"])
	var names: Array = towns.keys()
	names.sort()
	for town: String in names:
		var due := int(_gossip_due.get(town, 0))
		if due == 0:
			_gossip_due[town] = at + every
			continue
		if at < due:
			continue
		_gossip_due[town] = at + every
		var log: Variant = Offers._call(Offers.ctx, "memory", [town])
		if log is Array:
			var changed := not TownMemory.candidates(log, at).is_empty()  # Beliefs that spread and hold: candidates (phase 1).
			changed = _arrive(production, town, log, at) or changed  # Remembered people moving in (phase 4).
			changed = note_disputes(production, town, log, at) or changed  # Quarrels for the lawspeaker (decision 486).
			if changed:
				Offers._call(Offers.ctx, "set_memory", [town, log])
		for id: String in towns[town]:
			# Standing fades toward 0 with time (decision 443): residents' cards only.
			if id.begins_with(COMPANION):
				continue
			var card: Dictionary = production.worker(id).get("card", {})
			if card.get("standing") is Dictionary and not Standing.decay(card, at).is_empty():
				production.set_card(id, card)
		var groups := {}  # place -> [worker ids]
		for id: String in towns[town]:
			var where := whereabouts(_trade_of(production, id), hour, Season.name_at(at),
				str(production.worker(id).get("type", "")), id, day_of(at))
			if where in places:
				groups.get_or_add(where, []).append(id)
		var keys: Array = groups.keys()
		keys.sort()
		for place: String in keys:
			if groups[place].size() >= 2:
				_pass(production, town, place, groups[place], at)


## Remembered people moving in (decision 460): each entry of [param log]
## the lawspeaker ruled ready arrives through economy (Offers.ctx
## "move_in": Towns.move_in, which refuses when the town has no room), as
## "remembered:<town>:<name>" with the trade the talk names, their card
## rolled as anyone's and then written from the talk; the entry keeps who
## arrived. Whether the log changed. They leave or die only through the
## world.
static func _arrive(production: Production, town: String, log: Array, at: int) -> bool:
	var changed := false
	var trades: Array = []
	for id: String in production.worker_ids(town):
		for trade: Variant in production.worker(id).get("trades", []):
			if str(trade) not in trades:
				trades.append(str(trade))
	for entry: Dictionary in TownMemory.arrivals(log):
		var person := TownMemory.person_of(entry, trades)
		if person.is_empty():
			continue
		var who := "remembered:%s:%s" % [town, str(person["name"]).to_lower()]
		if not production.worker(who).is_empty():
			entry["arrived"] = who
			changed = true
			continue
		var came: Variant = Offers._call(Offers.ctx, "move_in", [town, who, str(person["name"]), str(person["trade"])])
		if came != true:
			continue  # No room, or no call to make: they wait.
		entry["arrived"] = who
		changed = true
		var card := ResidentCard.roll(who, str(person["name"]), str(person["trade"]), "remembered")
		card["came"] = "has lived here all along, as the town tells it"
		if bool(person.get("old", false)):
			card["look"]["age"] = "old"
		for text: String in TownMemory.talk_of(log, str(person["name"])):
			ResidentCard.add_fact(card, at, text)
		production.set_card(who, card)
		_found_among(production, who, card, town)
		production.set_card(who, card)
		Transcript.record(str(person["name"]), str(person["name"]), "[%s is found to have lived in the town all along: %s]" % [person["name"], entry.get("text", "")])
		MindLog.record({"kind": "arrival", "companion": str(person["name"]), "mind": "resident", "say": str(entry.get("text", "")), "outcome": "arrived", "town": town})
	return changed


## One pass of gossip at [param place] in [param town] among [param
## members] (worker ids): what was told, or "" for nothing.
static func _pass(production: Production, town: String, place: String, members: Array, at: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("gossip:%s:%s:%d" % [town, place, at])
	members.sort()
	var teller: String = members[rng.randi_range(0, members.size() - 1)]
	# {} for a resting companion (no card): no kin, no grudge, no facts of her own.
	var card := card_of(production, teller)
	var grudges: Array = card.get("grudge", [])
	var kin: Dictionary = card.get("kin", {})
	var hearers: Array = []
	for id: String in members:
		if id != teller and id not in grudges and teller not in card_of(production, id).get("grudge", []):
			hearers.append(id)
	if hearers.is_empty():
		return ""
	var close := hearers.filter(func(id: String) -> bool: return kin.has(id))
	var pool: Array = close if not close.is_empty() else hearers
	var hearer: String = pool[rng.randi_range(0, pool.size() - 1)]
	var hearer_name := str(production.worker(hearer).get("name", ""))
	var teller_name := str(production.worker(teller).get("name", ""))
	var heard: Array = production.worker(hearer).get("heard", []).duplicate(true)
	var text := ""
	var fits := ""
	var omen := false
	var teller_type := str(production.worker(teller).get("type", ""))
	var official := Lore.binding(_trade_of(production, teller), teller_type) == "official"
	if teller_type == SCHOLAR:
		# A scholar passes on what lore knows first (decision 440): true, so
		# witnessed, the weightiest the hearer has not heard.
		var known := Lore.known_by(Lore.knower_for(_trade_of(production, teller)), PackedStringArray(), "agreed", teller_type)
		known.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("weight", 0)) > float(b.get("weight", 0)))
		for fact: Dictionary in known:
			var lore_text := str(fact.get("text", "")).strip_edges().trim_suffix(".")
			if not lore_text.is_empty() and not bool(fact.get("hearsay", false)) and not Hearsay.holds(heard, lore_text):
				text = lore_text
				fits = Hearsay.WITNESSED
				break
	if text.is_empty():
		# What the teller thinks of a player, when it is strong and their own
		# (decision 443): "Jeff brought Bram home", and the hearer leans the
		# same way a little, if they have no dealings of their own.
		var views: Variant = card.get("standing", {})
		var newest := {}
		var newest_id := ""
		if views is Dictionary:
			for player_id: String in views:
				var it: Dictionary = views[player_id]
				var value := int(it.get("score", 0))
				if bool(it.get("own", false)) and (value >= Standing.setting("trusted") or value <= Standing.setting("wronged")) 						and (newest.is_empty() or int(it.get("since", 0)) > int(newest.get("since", 0))):
					newest = it
					newest_id = player_id
		if not newest.is_empty() and not newest.get("why", []).is_empty():
			var player_name := str(Offers._call(Offers.ctx, "name_of", [newest_id]))
			if player_name.is_empty() or player_name == "<null>":
				player_name = newest_id
			var said := "%s %s" % [player_name, str(newest["why"].back())]
			if not Hearsay.holds(heard, said):
				var hearer_card := card_of(production, hearer)
				if not hearer_card.is_empty() and Standing.heard(hearer_card, newest_id, signi(int(newest["score"])), str(newest["why"].back()), teller_name, at):
					production.set_card(hearer, hearer_card)
				text = said
				fits = Hearsay.WITNESSED
	if text.is_empty() and not official:
		var beliefs: Array = production.worker(teller).get("heard", [])
		for i in range(beliefs.size() - 1, -1, -1):
			var entry: Dictionary = beliefs[i]
			var said := str(entry.get("text", ""))
			if bool(entry.get("believed", false)) and not said.is_empty() and not said.contains(hearer_name) and not Hearsay.holds(heard, said):
				text = said
				fits = "beyond"
				omen = bool(entry.get("omen", false))
				break
	if text.is_empty():
		var facts: Array = card.get("facts", [])
		for i in range(facts.size() - 1, -1, -1):
			var fact := str(facts[i].get("text", "")) if facts[i] is Dictionary else ""
			var told := _as_told(fact, card)
			if fact.is_empty() or fact.contains(hearer_name) or Hearsay.holds(heard, told):
				continue
			text = told
			fits = Hearsay.WITNESSED
			break
	if text.is_empty():
		return ""
	var entry := Hearsay.hear(heard, hearer, leaning_of(production, hearer, "intellect"), text, fits, teller_name, at,
		omen, leaning_of(production, hearer, "superstition"), place)
	if entry.is_empty():
		return ""
	production.set_heard(hearer, heard)
	if fits == "beyond" and bool(entry.get("believed", false)):
		# A belief that spreads is the town's to remember (the lawspeaker, phase 1).
		var log: Variant = Offers._call(Offers.ctx, "memory", [town])
		if log is Array:
			TownMemory.hold(log, text, hearer, teller, at)
			Offers._call(Offers.ctx, "set_memory", [town, log])
	var where := Hearsay.place_words(place)
	var line := "[%s, %s told %s: %s]" % [where.left(1).to_upper() + where.substr(1), teller_name, hearer_name, text]
	Transcript.record(hearer_name, teller_name, line)
	if teller_name != hearer_name:
		Transcript.record(teller_name, teller_name, line)
	MindLog.record({"kind": "gossip", "companion": hearer_name, "mind": "resident", "say": text, "from": teller_name,
		"where": place, "fits": fits, "outcome": "believed" if bool(entry.get("believed", false)) else "doubted"})
	return text


## A card fact as its own teller tells it: "Mara saw Bram carried off"
## becomes "she saw Bram carried off".
static func _as_told(fact: String, card: Dictionary) -> String:
	var traits: Dictionary = card.get("traits", {})
	var name := str(traits.get("name", ""))
	if name.is_empty() or not fact.begins_with(name + " "):
		return fact
	return str(traits.get("pronoun", "they")) + fact.substr(name.length())


## [param worker_id]'s first trade, "" for none.
static func _trade_of(production: Production, worker_id: String) -> String:
	var trades: Array = production.worker(worker_id).get("trades", [])
	return str(trades[0]) if not trades.is_empty() else ""


## One of [param worker_id]'s leanings ("intellect", "superstition",
## "creativity", "integrity"), 1..10: the record's own when economy rolled
## it, else about its trade's and type's profile (Production.mind_of).
static func leaning_of(production: Production, worker_id: String, key: String) -> int:
	var who := production.worker(worker_id)
	var own: Variant = who.get(key)
	if own is int or own is float:
		return int(own)
	return Production.mind_of(worker_id, _trade_of(production, worker_id), key, str(who.get("type", "")))


## [param text] is now true of resident [param worker_id]: on the card
## (made if need be), told to the transcript and the mind log. Whether new.
static func learn(production: Production, worker_id: String, text: String) -> bool:
	var card := card_of(production, worker_id)
	if card.is_empty():
		return false
	if not _true(card, production.now(), text):
		return false
	production.set_card(worker_id, card)
	return true


## Resident [param worker_id] saw raiders at the walls (Resident, as it
## hides): a fact, once.
static func saw_raiders(production: Production, worker_id: String) -> void:
	var who := production.worker(worker_id) if production != null else {}
	if not who.is_empty():
		learn(production, worker_id, "%s saw raiders at the walls." % who.get("name", worker_id))


static func _true(card: Dictionary, step: int, text: String) -> bool:
	if not ResidentCard.add_fact(card, step, text):
		return false
	var name := str(card.get("traits", {}).get("name", ""))
	Transcript.record(name, name, "[Now true of %s: %s]" % [name, text])
	MindLog.record({"kind": "fact", "companion": name, "mind": "resident", "say": text, "outcome": "applied"})
	return true


static func _raided(production: Production, town: String, report: Dictionary) -> void:
	if bool(report.get("repelled", false)):
		# Fought off with a player in the town (decision 443): every resident
		# thinks the better of them, once per raid.
		var area: Variant = Offers._call(Offers.ctx, "area_of", [town])
		var there: Variant = Offers._call(Offers.ctx, "players_in", [str(area)]) if area is String and not str(area).is_empty() else null
		if there is Array and not there.is_empty():
			for id: String in production.worker_ids(town):
				if id.begins_with(COMPANION):
					continue
				for player_id: Variant in there:
					Offers._regard(production, id, str(player_id), Standing.setting("raid"), "stood with the town when raiders came")
		return
	var faction := ResidentCard.faction_name(str(report.get("faction", "")))
	var taken: Array = report.get("captives", [])
	var taken_ids := taken.map(func(each: Dictionary) -> String: return str(each.get("id", "")))
	for each: Dictionary in taken:
		learn(production, str(each.get("id", "")), "%s was carried off by %s." % [each.get("name", ""), faction])
	for id: String in production.worker_ids(town):
		if id in taken_ids or id.begins_with(COMPANION) or bool(production.worker(id).get("away", false)):
			continue
		var name := str(production.worker(id).get("name", id))
		if taken.is_empty():
			learn(production, id, "%s lived through a raid by %s." % [name, faction])
		for each: Dictionary in taken:
			learn(production, id, "%s saw %s carried off by %s." % [name, each.get("name", ""), faction])


static func _rescued(production: Production, town: String, who_id: String, by: String) -> void:
	var who := production.worker(who_id)
	if who.is_empty():
		return
	var name := str(who.get("name", who_id))
	var from := "from %s" % ResidentCard.faction_name(by) if not by.is_empty() else "rescued from captivity"
	if not by.is_empty():
		learn(production, who_id, "%s came home %s." % [name, from])
	else:
		card_of(production, who_id)  # Their coming is in the card's own words.
	for id: String in production.worker_ids(town):
		if id == who_id or id.begins_with(COMPANION) or bool(production.worker(id).get("away", false)):
			continue
		var other := str(production.worker(id).get("name", id))
		learn(production, id, "%s saw %s %s." % [other, name, "come home " + from if not by.is_empty() else "come to the town, " + from])


static func _loan(production: Production, worker_id: String, owed: float, working_off: bool) -> void:
	var who := production.worker(worker_id)
	if who.is_empty() or worker_id.begins_with(COMPANION):
		return
	var name := str(who.get("name", worker_id))
	if owed > 0.0 and working_off:
		learn(production, worker_id, "%s works off a debt to the town." % name)
	elif owed > 0.0:
		learn(production, worker_id, "%s borrowed from the town's coffer." % name)
	else:
		var card := card_of(production, worker_id)
		if card.get("facts", []).any(func(fact: Dictionary) -> bool: return str(fact.get("text", "")).contains("borrowed from the town's coffer")):
			learn(production, worker_id, "%s paid the town's coffer back." % name)


# --- Routines (decision 404) ----------------------------------------------------------

const DAYS_FILE := "res://levels/residents.json"
const PLACES: Array[String] = ["work", "home", "square", "well", "inn", "temple", "rounds"]


## The lawspeaker's rounds (decision 459): of [param count] homes, the ones
## he visits on day [param day], "rounds.homes_a_day" of them in turn, so
## every home has its day; the indices, in the order of the day's stops.
static func round_stops(count: int, day: int) -> Array[int]:
	var out: Array[int] = []
	if count <= 0:
		return out
	var a_day := maxi(int(days().get("rounds", {}).get("homes_a_day", 3)), 1)
	for k in mini(a_day, count):
		var index := (day * a_day + k) % count
		if index not in out:
			out.append(index)
	return out


## Which of the day's stops he is at by [param hour]: the day's rounds
## hours split among them, in order.
static func round_stop(count: int, day: int, hour: float) -> int:
	var stops := round_stops(count, day)
	if stops.is_empty():
		return -1
	var k := int(clampf((hour - 6.0) / 13.0, 0.0, 0.999) * stops.size())
	return stops[k]


## Who the lawspeaker [param lawspeaker_id] stands with on the day of
## [param at]: of [param ids] (the town's people in the order Main gives
## homes by: sorted), those at today's stops, himself left out.
static func visits(ids: Array, lawspeaker_id: String, at: int) -> Array[String]:
	var out: Array[String] = []
	var homes: Array = ids.filter(func(id: Variant) -> bool: return str(id) != lawspeaker_id)
	for index: int in round_stops(homes.size(), day_of(at)):
		out.append(str(homes[index]))
	return out
static var _days := {}


## The days by trade and the rest of residents.json, read on first use.
static func days() -> Dictionary:
	if _days.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DAYS_FILE)) if FileAccess.file_exists(DAYS_FILE) else null
		_days = data if data is Dictionary else {}
		if not _days.has("default"):
			_days["default"] = {"stints": [{"from": 8, "to": 18, "at": "work"}, {"from": 21, "to": 6, "at": "home"}]}
	return _days


## Uses [param given] in place of DAYS_FILE ({} to read it again): tests.
static func use_days(given: Dictionary) -> void:
	_days = given.duplicate(true)
	if not given.is_empty() and not _days.has("default"):
		_days["default"] = {"stints": [{"from": 8, "to": 18, "at": "work"}, {"from": 21, "to": 6, "at": "home"}]}


## Where one of [param trade] is at [param hour] (0..24): one of PLACES,
## from the clock alone, so a body spawned when a player walks up starts at
## the right stint. In order: the temple day ([param day], the day's count
## on the world clock, every so many days by [param worker_id]); the hidden
## [param type]'s stints; the trade's stints (the default's for a trade not
## listed), their edges moved by [param season]; else the square. The hour
## is read on the resident's own clock, ahead of or behind the town's by
## their offset (offset_hours at most, by the id).
static func whereabouts(trade: String, hour: float, season := "", type := "", worker_id := "", day := -1) -> String:
	var table := days()
	var at := fposmod(hour - offset_of(worker_id), 24.0)
	var temple: Dictionary = table.get("temple", {})
	var every := int(temple.get("every_days", 0))
	if day >= 0 and every > 0 and (day + absi(hash("temple:" + worker_id))) % every == 0 \
			and _within(at, float(temple.get("from", 9)), float(temple.get("to", 10))):
		return "temple"
	for stint: Variant in table.get("types", {}).get(type, []):
		if stint is Dictionary and _within(at, float(stint.get("from", 0)), float(stint.get("to", 0))):
			return str(stint.get("at", "square"))
	var edges: Dictionary = table.get("seasons", {}).get(season, {})
	var morning := float(edges.get("morning", 0.0))
	var evening := float(edges.get("evening", 0.0))
	var day_of: Dictionary = table.get(trade, table["default"]) if table.get(trade) is Dictionary else table["default"]
	for stint: Variant in day_of.get("stints", []):
		if not stint is Dictionary:
			continue
		var from := float(stint.get("from", 0))
		var to := float(stint.get("to", 0))
		from = fposmod(from + (morning if from < 12.0 else evening), 24.0)
		to = fposmod(to + (morning if to < 12.0 else evening), 24.0)
		if _within(at, from, to):
			return str(stint.get("at", "square"))
	return "square"


## How far resident [param worker_id]'s own clock runs ahead (+) or behind
## the town's, in hours: within offset_hours, by the id; 0 for no id.
static func offset_of(worker_id: String) -> float:
	if worker_id.is_empty():
		return 0.0
	var most := float(days().get("offset_hours", 0.0))
	return (float(absi(hash("clock:" + worker_id)) % 1000) / 999.0 * 2.0 - 1.0) * most


## The day's count on the world clock at [param steps].
static func day_of(steps: float) -> int:
	return int(floor(steps / float(maxi(DayNight.day_steps, 1))))


static func _within(hour: float, from: float, to: float) -> bool:
	if from == to:
		return false
	return from <= hour and hour < to if from < to else hour >= from or hour < to
