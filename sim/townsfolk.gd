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
static func tick(production: Production, stockpile: Stockpile) -> void:
	if production == null or stockpile == null:
		return
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
		if _chance(id, due) < float(thief.get("chance", 1.0)):
			lift(stockpile, str(who["town"]), thief)


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


## At founding, [param card]'s kin and grudge (resident_traits.json "kin",
## "grudge": a chance each, by the id) among [param town]'s residents who
## have cards: the facts written into both cards.
static func _found_among(production: Production, worker_id: String, card: Dictionary, town: String) -> void:
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
		var both := ResidentCard.kin_facts(card, theirs, str(kin["kinds"][kind_pick % kin["kinds"].size()]))
		_true(card, step, both[0])
		_true(theirs, step, both[1])
		production.set_card(other, theirs)
	if grudge_draw < float(grudge.get("chance", 0.0)) and grudge.get("causes") is Array and not grudge["causes"].is_empty():
		var other := others[grudge_pick % others.size()]
		var theirs: Dictionary = production.worker(other)["card"]
		var text := ResidentCard.grudge_fact(card, theirs, str(grudge["causes"][cause_pick % grudge["causes"].size()]))
		_true(card, step, text)
		_true(theirs, step, text)
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
