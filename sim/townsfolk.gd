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
## What the side-doings did since the start, by key ("lifted", "store_lifted",
## "fenced", "caught", "strayed", "walked_home"): for tools and tests
## (tools/town_soak reads it; the store's ledger keeps only its last lines).
static var tally := {}

static func _tally(key: String, by := 1) -> void:
	tally[key] = int(tally.get(key, 0)) + by
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
	sicken(production)  # Someone takes to their bed, and the sick get up (decision 501).
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
		_tally("store_lifted")
		var catcher := _catcher(production, town, id, "", at, due, thief)
		if not catcher.is_empty():
			_tally("caught")
			stockpile.deposit(town, goods, 1, "returned")
			_caught(production, town, id, catcher, "", "taking %s from the store" % goods.replace("_", " "), at, thief)
			continue
		var merchant := _merchant(production, town, id)
		if not merchant.is_empty() and economy != null and economy.has_method("fence"):
			if int(economy.fence(town, merchant, id, goods, float(thief.get("fence", 0.5)), float(thief.get("margin", 0.4)))) > 0:
				_tally("fenced")


## Economy's line for a rich purse (economy.json folk.rich_above, the same
## line its dole and prices use): [param economy]'s rules, else the file's.
static func _rich_line(economy: Economy) -> int:
	var rules: Dictionary = economy.rules if economy != null and economy.rules is Dictionary else Production.read_rules(Economy.PATH)
	return int(rules.get("folk", {}).get("rich_above", 25))


const BARD := "bard"
const SCOUNDREL := "scoundrel"


## A thing made by [param worker_id] of [param town] (economy's word that
## the job finished, the instance [param uid] in [param book]) comes out
## short when the maker is a scoundrel (decision 492): only a thing
## measured by count or weight (Items.measured: a sack, a bolt, a bundle;
## never a weapon, tool or piece of gear, Jeff's rule), by a seeded draw
## against "scoundrel.short", to "scoundrel.weight" of its full
## (ItemBook.make_short, items'), noted in the thing's history and nowhere
## else: the counter sells it at the full price and the thing tells on him
## in the hand. Whether it was shorted.
static func made_short(production: Production, town: String, worker_id: String, uid: int, book: ItemBook) -> bool:
	if production == null or book == null or uid == 0 or str(production.worker(worker_id).get("type", "")) != SCOUNDREL:
		return false
	var rule: Dictionary = rules().get("scoundrel", {})
	var id := book.id_of(uid)
	if id.is_empty() or not Callable(Items, "measured").is_valid() or not Items.measured(id) or not book.has_method("make_short"):
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("short:%s:%d" % [worker_id, uid])
	if rng.randf() >= float(rule.get("short", 0.0)):
		return false
	book.make_short(uid, float(rule.get("weight", 0.6)))
	print("[townsfolk] %s: a %s made short, step %d" % [town, id.replace("_", " "), production.now()])
	return true


## The bank's cap on a debt (economy.json "bank".cap), read once.
static var _bank_cap := -1
static func bank_cap() -> int:
	if _bank_cap < 0:
		_bank_cap = int(Production.read_rules(Economy.PATH).get("bank", {}).get("cap", 30))
	return _bank_cap


## A scoundrel's debt first at the bank's cap (decision 492; economy never
## has him pay back on his own, so it gets there): the town's official (the
## one whose trade binds official, 459; else the richest neighbour) learns
## it as a thing seen, "X owes the town all it will lend and pays nothing
## back", which gossip passes as witnessed (422); his own card learns what
## he owes; with a sitting lawspeaker and rulings on, the same sentence is
## a dispute before him (486's shape, said by the official, no pair: it is
## the town's quarrel). Once per climb: cleared when he is worked down
## under half the cap, so the next climb is talked of again.
static func _debt_capped(production: Production, worker_id: String, owed: float) -> void:
	var who := production.worker(worker_id)
	var town := str(who.get("town", ""))
	var name := str(who.get("name", worker_id))
	var card := card_of(production, worker_id)
	if town.is_empty() or card.is_empty() or bool(card.get("capped", false)):
		return
	card["capped"] = true
	production.set_card(worker_id, card)
	learn(production, worker_id, "%s owes the town %d gold and pays nothing of it." % [name, ceili(owed)])
	var official := ""
	var richest := ""
	var most := -1
	for id: String in production.worker_ids(town):
		if id == worker_id or id.begins_with(COMPANION) or bool(production.worker(id).get("away", false)):
			continue
		if official.is_empty() and Lore.binding(_trade_of(production, id), str(production.worker(id).get("type", ""))) == "official":
			official = id
		if int(production.worker(id).get("purse", 0)) > most:
			most = int(production.worker(id).get("purse", 0))
			richest = id
	var teller := official if not official.is_empty() else richest
	if teller.is_empty():
		return
	var text := "%s owes the town all it will lend and pays nothing back" % name
	learn(production, teller, text + ".")
	var law := str(Offers._call(Offers.ctx, "lawspeaker_of", [town]))
	var model := str(Offers._call(Offers.ctx, "model"))
	if law.is_empty() or law == "<null>" or model.is_empty() or model == "off" or model == "<null>":
		return
	var log: Variant = Offers._call(Offers.ctx, "memory", [town])
	if not log is Array:
		return
	var entry := TownMemory.note(log, text, teller, worker_id, production.now())
	if not entry.is_empty() and str(entry.get("tier", "")) in [TownMemory.BELIEF, TownMemory.CANDIDATE] and entry.get("ruling", {}).is_empty():
		entry["tier"] = TownMemory.CANDIDATE
		entry["dispute"] = true
		Offers._call(Offers.ctx, "set_memory", [town, log])


## The bard's piece (decision 490; residents.json "bard"): among [param
## at_inn] (the ids whose whereabouts is the inn now) the first bard, once
## a night, with the town's inn standing (Offers.ctx "has_inn", true when
## nobody says), sings one true thing: first a town memory (447's MEMORY
## tier, the lawspeaker's sentences) naming a player in the inn tonight
## (Offers.ctx "listeners", "name_of") not yet sung to them; else the
## newest memory not sung within "again" days; else lore's facts for the
## town (Offers.ctx "lore"), the weightiest not sung within "again" days,
## at most every "lore_every_nights" nights (with the lawspeaker off the
## town remembers nothing, and the inn should not hear the same three
## facts nightly). The words are a kind drawn by seed round the entry's
## own sentence, and a second line of the ruling's "because" when it has
## one. Residents at the inn hold the memory; each listening player's
## standing with the bard moves "song" (twice for their own deed); the
## bard's card learns it; Main is told ("say": the lines to those players
## and the body's speech). What was sung: {bard, line, second, listeners,
## named, text}; {} for no performance.
static func perform(production: Production, town: String, at_inn: Array, at: int) -> Dictionary:
	if production == null or at_inn.is_empty():
		return {}
	var rule: Dictionary = days().get("bard", {})
	var bards: Array = at_inn.filter(func(id: Variant) -> bool: return not str(id).begins_with(COMPANION) and str(production.worker(str(id)).get("type", "")) == BARD)
	if bards.is_empty():
		return {}
	bards.sort()
	var bard := str(bards[0])
	var day := day_of(at)
	var card := card_of(production, bard)
	if card.is_empty() or int(card.get("sang", -1)) == day:
		return {}
	var inn: Variant = Offers._call(Offers.ctx, "has_inn", [town])
	if inn == false:
		return {}
	var listeners: Array = []
	var given: Variant = Offers._call(Offers.ctx, "listeners", [town])
	if given is Array:
		listeners = given.duplicate()
	listeners.sort()
	var again := int(rule.get("again", 30)) * maxi(DayNight.day_steps, 1)
	var log: Variant = Offers._call(Offers.ctx, "memory", [town])
	var memories: Array = TownMemory.of_tier(log, TownMemory.MEMORY) if log is Array else []
	var entry := {}
	var named := ""
	# A listener's own deed, told back to them once.
	for player_id: Variant in listeners:
		var name := str(Offers._call(Offers.ctx, "name_of", [player_id]))
		for each: Dictionary in memories:
			var text := str(each.get("text", ""))
			var theirs: bool = str(each.get("said_by", "")) == TownMemory.PLAYER + str(player_id) or (not name.is_empty() and name != "<null>" and text.contains(name))
			if theirs and not each.get("sung_to", {}).has(str(player_id)):
				entry = each
				named = str(player_id)
				break
		if not entry.is_empty():
			break
	# Else the newest memory not sung lately.
	if entry.is_empty():
		for i in range(memories.size() - 1, -1, -1):
			if at - int(memories[i].get("sung", -again)) >= again:
				entry = memories[i]
				break
	var text := ""
	var because := ""
	if not entry.is_empty():
		text = str(entry.get("text", ""))
		because = str(entry.get("ruling", {}).get("because", ""))
	else:
		# Lore, every other night at most.
		if day - int(card.get("lore_day", -99)) < int(rule.get("lore_every_nights", 2)):
			return {}
		var lore: Variant = Offers._call(Offers.ctx, "lore", [town])
		var sung: Dictionary = card.get("sung_lore", {})
		if lore is Array:
			for fact: Variant in lore:
				if at - int(sung.get(str(fact), -again)) >= again:
					text = str(fact)
					break
		if text.is_empty():
			return {}
		sung[text] = at
		card["sung_lore"] = sung
		card["lore_day"] = day
	var kinds: Array = rule.get("kinds", ["sings of how"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("song:%s:%d" % [bard, day])
	var kind := str(kinds[rng.randi() % kinds.size()]) if not kinds.is_empty() else "sings of how"
	var name := str(production.worker(bard).get("name", bard))
	# The sentence as the town has it, its first letter lowered after "how"
	# unless the first word is somebody's name (a deed starts with its doer).
	var clean := text.strip_edges().trim_suffix(".")
	var first := clean.get_slice(" ", 0).trim_suffix(",").trim_suffix("'s")
	var known := listeners.map(func(id: Variant) -> String: return str(Offers._call(Offers.ctx, "name_of", [id])))
	for id: String in production.worker_ids(town):
		known.append(str(production.worker(id).get("name", "")))
	if first not in known:
		clean = Hearsay._lower_first(clean)
	var line := "At the inn, %s %s %s." % [name, kind, clean]
	var second := "The lawspeaker's word on it: %s." % because.trim_suffix(".") if not because.is_empty() else ""
	# What it leaves behind: the night on the bard's card, the entry sung,
	# the inn's people holding it, the listeners' regard.
	card["sang"] = day
	ResidentCard.add_fact(card, at, "%s sang of %s at the inn tonight." % [name, clean])
	for player_id: Variant in listeners:
		Standing.met(card, str(player_id), at)
		Standing.bump(card, str(player_id), Standing.setting("song") * (2 if str(player_id) == named else 1), "heard %s sing" % name, at)
	production.set_card(bard, card)
	if not entry.is_empty() and log is Array:
		entry["sung"] = at
		if not named.is_empty():
			entry.get_or_add("sung_to", {})[named] = day
		for id: Variant in at_inn:
			if str(id) != bard and not str(id).begins_with(COMPANION):
				TownMemory.hold(log, text, str(id), bard, at)
		Offers._call(Offers.ctx, "set_memory", [town, log])
	var out := {"bard": bard, "name": name, "line": line, "second": second, "listeners": listeners, "named": named, "text": clean,
		"spoken": "Hear now how %s." % clean}
	print("[bard] %s: %s%s" % [town, line, " " + second if not second.is_empty() else ""])
	Offers._call(Offers.ctx, "say", [town, out])
	return out


# --- Sickness (decision 501) ----------------------------------------------------------

## The card key of a sickness: {since (the day), kind (words), treated (the
## day, or -1), cured_by (a name, or "")}. A resident's is on the townsfolk
## card; a companion resting in town keeps hers on her player's companion
## card, through Offers.ctx "companion_sick" (get) and "set_companion_sick"
## (companions' side reads it, never writes it).
const SICK := "sick"
static var _sick_due := {}


## The untreated length in days (townsfolk.json "sick".days; companions
## read it for a sick companion taken out of town).
static func sick_days() -> int:
	return int(rules().get("sick", {}).get("days", 5))


## [param id]'s sickness record, {} for well.
static func sickness_of(production: Production, id: String) -> Dictionary:
	if id.begins_with(COMPANION):
		var hers: Variant = Offers._call(Offers.ctx, "companion_sick", [id])
		return hers if hers is Dictionary else {}
	var record: Variant = card_of(production, id).get(SICK)
	return record if record is Dictionary else {}


static func is_sick(production: Production, id: String) -> bool:
	return production != null and not sickness_of(production, id).is_empty()


static func _set_sickness(production: Production, id: String, record: Dictionary) -> void:
	if id.begins_with(COMPANION):
		Offers._call(Offers.ctx, "set_companion_sick", [id, record])
		return
	var card := card_of(production, id)
	if card.is_empty():
		return
	if record.is_empty():
		card.erase(SICK)
	else:
		card[SICK] = record
	production.set_card(id, card)


## Sickness on the world tick (decision 501): by town, once a day, first
## every sickness runs on (treated, it ends this morning; untreated, it ends
## after sick_days: the old of the town's own die by "death_old", the rest
## are on their feet again), then one new case at most: each resident not
## away and not sick (a resting companion too, 442) draws against "chance"
## times the season's, the hungry's and the old's factors, by a seed of the
## town and the day. The sick keep to their bed (Resident) and economy
## counts them out of work but not out of need (Production.set_sick).
static func sicken(production: Production) -> void:
	if production == null:
		return
	var rule: Dictionary = rules().get("sick", {})
	if float(rule.get("chance", 0.0)) <= 0.0:
		return
	var at := production.now()
	var day := day_of(at)
	var towns := {}
	for id: String in production.worker_ids():
		var town := str(production.worker(id).get("town", ""))
		if not town.is_empty():
			towns.get_or_add(town, []).append(id)
	var names: Array = towns.keys()
	names.sort()
	for town: String in names:
		if int(_sick_due.get(town, -1)) == day:
			continue
		_sick_due[town] = day
		var ended := {}  # Up this morning, or dead: not rolled again today.
		for id: String in towns[town]:
			var record := sickness_of(production, id)
			if record.is_empty():
				continue
			if int(record.get("treated", -1)) >= 0 and day > int(record["treated"]):
				_sick_ends(production, town, id, record, true, at)
				ended[id] = true
			elif day - int(record.get("since", day)) >= sick_days():
				_sick_ends(production, town, id, record, false, at)
				ended[id] = true
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("sick:%s:%d" % [town, day])
		var winter := Season.name_at(at) == "winter"
		var ids: Array = towns[town].duplicate()
		ids.sort()
		for id: String in ids:
			var who := production.worker(id)
			if who.is_empty() or ended.has(id) or bool(who.get("away", false)) or not sickness_of(production, id).is_empty():
				continue
			var p := float(rule.get("chance", 0.0))
			if winter:
				p *= float(rule.get("winter", 1.0))
			if str(who.get("fed", "")) in ["hungry", "dole"]:
				p *= float(rule.get("hungry", 1.0))
			if _is_old(production, id):
				p *= float(rule.get("old", 1.0))
			if rng.randf() < p:
				_falls_sick(production, town, id, day, rng)
				break  # One new case a town a day.


static func _is_old(production: Production, id: String) -> bool:
	return str(card_of(production, id).get("look", {}).get("age", "")) == "old"


static func _falls_sick(production: Production, town: String, id: String, day: int, rng: RandomNumberGenerator) -> void:
	var kinds: Array = rules().get("sick", {}).get("kinds", ["a fever"])
	var kind := str(kinds[rng.randi() % kinds.size()]) if not kinds.is_empty() else "a fever"
	_set_sickness(production, id, {"since": day, "kind": kind, "treated": -1, "cured_by": ""})
	if production.has_method("set_sick"):
		production.set_sick(id, true)
	var name := str(production.worker(id).get("name", id))
	var card := card_of(production, id)
	if not card.is_empty():
		learn(production, id, "%s took to %s bed with %s." % [name, _their(card), kind])
		for kin_id: Variant in card.get("kin", {}):
			if not production.worker(str(kin_id)).is_empty():
				learn(production, str(kin_id), "%s, %s %s, lies sick at home with %s." % [name, _their(card_of(production, str(kin_id))), Offers._relation(str(card["kin"][kin_id]), card), kind])
	print("[townsfolk] %s: %s took to bed with %s, day %d" % [town, name, kind, day])


## [param id] is treated (decision 501) by [param by_name] ([param how]: "the
## medicine man", "the healer", "a remedy"): the sickness ends the next
## morning; the cards remember; the pleas to see to them are met
## (Offers.healed: the notice, the pay, the standing). False if not sick.
static func treat(production: Production, id: String, by_name: String, how: String, player_id := "") -> bool:
	var record := sickness_of(production, id)
	if record.is_empty() or int(record.get("treated", -1)) >= 0:
		return false
	var day := day_of(production.now())
	record["treated"] = day
	record["cured_by"] = by_name
	_set_sickness(production, id, record)
	var name := str(production.worker(id).get("name", id))
	var town := str(production.worker(id).get("town", ""))
	if not card_of(production, id).is_empty():
		var ailment := str(record.get("kind", "fever")).trim_prefix("a ").trim_prefix("the ")
		if how == "the medicine man":
			learn(production, id, "%s the medicine man saw to %s, and the %s broke that night." % [by_name, name, ailment])
		else:
			learn(production, id, "%s saw to %s with %s, and the %s broke that night." % [by_name, name, how, ailment])
	print("[townsfolk] %s: %s treated by %s (%s), day %d" % [town, name, by_name, how, day])
	Offers.healed(town, id, player_id, by_name, how)
	return true


## A sickness ends (decision 501): [param treated], on their feet; else, run
## its course: one of the town's own who is old dies by "death_old" (never
## a rescued captive, a settled arrival or a companion: the coordinator's
## guard for this step), through economy's Towns.died (Offers.ctx "died");
## the rest are on their feet, thinner. The kin's card and the pleas close.
static func _sick_ends(production: Production, town: String, id: String, record: Dictionary, treated: bool, at: int) -> void:
	var who := production.worker(id)
	var name := str(who.get("name", id))
	var kind := str(record.get("kind", "a fever"))
	var origin := str(who.get("origin", ""))
	var dies := false
	if not treated and not id.begins_with(COMPANION) and _is_old(production, id) and not origin.begins_with("rescued:") and origin != "settled":
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("death:%s:%d" % [id, day_of(at)])
		dies = rng.randf() < float(rules().get("sick", {}).get("death_old", 0.0))
	_set_sickness(production, id, {})
	if production.has_method("set_sick"):
		production.set_sick(id, false)
	if dies:
		for kin_id: Variant in card_of(production, id).get("kin", {}):
			if not production.worker(str(kin_id)).is_empty():
				learn(production, str(kin_id), "%s died of %s." % [name, kind])
		var law := str(Offers._call(Offers.ctx, "lawspeaker_of", [town]))
		var model := str(Offers._call(Offers.ctx, "model"))
		if not law.is_empty() and law != "<null>" and not model.is_empty() and model != "off" and model != "<null>":
			var log: Variant = Offers._call(Offers.ctx, "memory", [town])
			if log is Array:
				var entry := TownMemory.note(log, "%s died of %s in the %s" % [name, kind, Season.name_at(at)], law, "", at)
				if not entry.is_empty() and str(entry.get("tier", "")) == TownMemory.BELIEF:
					entry["tier"] = TownMemory.CANDIDATE
				Offers._call(Offers.ctx, "set_memory", [town, log])
		print("[townsfolk] %s: %s died of %s, day %d" % [town, name, kind, day_of(at)])
		Offers.healed(town, id, "", "", "died")
		Offers._call(Offers.ctx, "died", [town, id, kind])
		return
	if not card_of(production, id).is_empty():
		if treated:
			learn(production, id, "%s is on %s feet again." % [name, _their(card_of(production, id))])
		else:
			learn(production, id, "%s is on %s feet again after %s, thinner for it." % [name, _their(card_of(production, id)), kind])
	if not treated:
		Offers.healed(town, id, "", "", "recovered")


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
				Offers.walked_home(town, id, "", "")  # The kin's pleas close unpaid: no lapse against anyone (the soak).
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
		_tally("strayed")
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
	_tally("lifted")
	_tally("lifted_gold", taken)
	var catcher := _catcher(production, town, thief, victim, at, due, rule)
	if not catcher.is_empty():
		_tally("caught")
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
	if str(who.get("type", "")) == BARD:
		ResidentCard.add_fact(card, production.now(), "%s sings at the inn of an evening." % who.get("name", worker_id))  # Decision 490.
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
	if production.has_signal("made"):
		# A thing made, before it reaches the shelf (economy's 492 side): a scoundrel's may be short.
		production.made.connect(func(town: String, worker_id: String, uid: int) -> void:
			var kept: Production = weak.get_ref()
			if kept != null and kept.stockpile != null:
				made_short(kept, town, worker_id, uid, kept.stockpile.book))
	if towns != null:
		towns.raided.connect(func(town: String, report: Dictionary) -> void:
			var kept: Production = weak.get_ref()
			if kept != null:
				_raided(kept, town, report))
		towns.rescued.connect(func(town: String, who_id: String, by: String) -> void:
			var kept: Production = weak.get_ref()
			if kept != null:
				_rescued(kept, town, who_id, by))

# --- The road's news (decision 504, npc's side) ------------------------------------

## Caravan id -> {town, far, goods, members, home, sold, struck_by}: what a
## town's wagon took out, for the words when it comes home. Not saved: after
## a restart the words say what the payload says and no more.
static var _wagons: Dictionary = {}
static var _watching_road: Dictionary = {}


## The road's news (decision 504, npc's side): maps' TradeRoutes [param trade]
## tells what a town's wagon did (left, arrived, struck, lost) and its people,
## their kin and the town's officials carry it as card facts (learn), spread
## by gossip and the counter as every fact is; a raid or a lost wagon is a
## candidate for the town's memory. Economy's [param economy] may tell the
## sale (caravan_sold) for "sold well" in the traveller's words.
static func watch_road(production: Production, trade: Object, economy: Object = null) -> void:
	if production == null or trade == null or not trade.has_signal("caravan_left"):
		return
	var held: Variant = _watching_road.get(trade.get_instance_id())
	if held is WeakRef and held.get_ref() == trade:
		return
	var weak: WeakRef = weakref(production)
	var road: WeakRef = weakref(trade)
	_watching_road[trade.get_instance_id()] = road
	trade.caravan_left.connect(func(id: String, route_id: String, cargo: Dictionary) -> void:
		var kept: Production = weak.get_ref()
		if kept != null:
			wagon_left(kept, road.get_ref(), id, route_id, cargo))
	trade.caravan_arrived.connect(func(id: String, route_id: String, at_end: String, cargo: Dictionary) -> void:
		var kept: Production = weak.get_ref()
		if kept != null:
			wagon_arrived(kept, road.get_ref(), id, route_id, at_end, cargo))
	trade.caravan_raided.connect(func(id: String, route_id: String, camp_id: String, taken: Dictionary) -> void:
		var kept: Production = weak.get_ref()
		if kept != null:
			wagon_raided(kept, road.get_ref(), id, route_id, camp_id, taken))
	trade.caravan_lost.connect(func(id: String, route_id: String, why: String) -> void:
		var kept: Production = weak.get_ref()
		if kept != null:
			wagon_lost(kept, road.get_ref(), id, route_id, why))
	if economy != null and economy.has_signal("caravan_sold"):
		economy.caravan_sold.connect(func(id: String, _town: String, _market: String, proceeds: int, wages: int) -> void:
			wagon_sold(id, proceeds, wages))


## A wagon set out: its people, their kin and the officials know where to
## and for how long. Setting out from the far end is the way home (the same
## people): the record moves to the new id, nobody in town to tell.
static func wagon_left(production: Production, trade: Object, id: String, route_id: String, cargo: Dictionary) -> void:
	var members: Array = cargo.get("members", [])
	if members.is_empty():
		return
	for out_id: String in _wagons.keys():
		var went: Dictionary = _wagons[out_id]
		if not bool(went.get("home", false)) and members.all(func(who: Variant) -> bool: return str(who) in went["members"]):
			went["home"] = true
			went["back"] = cargo.get("goods", {}).duplicate()
			_wagons.erase(out_id)
			_wagons[id] = went
			return
	var town := str(production.worker(str(members[0])).get("town", ""))
	if town.is_empty():
		return
	var far := _far_end(trade, route_id, town)
	_wagons[id] = {"town": town, "far": far, "goods": cargo.get("goods", {}).duplicate(), "members": members.duplicate(), "all": members.duplicate(), "home": false}
	var where := _end_words(far)
	var days := _trip_words(trade, route_id)
	var names := _names(production, members)
	for who: Variant in members:
		var name := str(production.worker(str(who)).get("name", who))
		learn(production, str(who), "%s went with the wagon to %s, a trip of %s there and back." % [name, where, days])
		for kin_id: Variant in card_of(production, str(who)).get("kin", {}):
			if str(kin_id) in members or production.worker(str(kin_id)).is_empty():
				continue
			var theirs := card_of(production, str(kin_id))
			learn(production, str(kin_id), "%s, %s %s, has gone to %s with the wagon, back in %s." % [name, _their(theirs),
				Offers._relation(str(card_of(production, str(who)).get("kin", {}).get(kin_id, "")), card_of(production, str(who))), where, days])
	for official: String in _officials(production, town):
		if official in members:
			continue
		learn(production, official, "%s left with the wagon for %s, due back in %s." % [names, where, days])


## A wagon arrived: at the far end nothing is said at home; home again, its
## people tell what went and what came back (and how it sold, if economy
## said), the town saw them come, and the town's memory may keep it.
static func wagon_arrived(production: Production, trade: Object, id: String, route_id: String, at_end: String, cargo: Dictionary) -> void:
	var members: Array = cargo.get("members", [])
	var went: Dictionary = _wagons.get(id, {})
	var town := str(went.get("town", ""))
	if town.is_empty() and not members.is_empty():
		town = str(production.worker(str(members[0])).get("town", ""))
	if town.is_empty() or at_end != town:
		return  # At the far end: the travellers are away, nobody at home hears yet.
	_wagons.erase(id)
	var where := _end_words(str(went.get("far", "")))
	var took := _goods_words(went.get("goods", {}))
	var back := _goods_words(cargo.get("goods", {}))
	var load := ""
	if not took.is_empty() and not back.is_empty():
		load = "the wagon took %s, and brought back %s." % [took, back]
	elif not took.is_empty():
		load = "the wagon took %s, and came back empty." % took
	elif not back.is_empty():
		load = "the wagon brought back %s." % back
	else:
		load = "the wagon came back as it went."
	var sold := _sold_words(went)
	var names := _names(production, members)
	for who: Variant in members:
		var name := str(production.worker(str(who)).get("name", who))
		learn(production, str(who), "%s came home from %s: %s%s" % [name, where, load, sold])
	for other: String in production.worker_ids(town):
		if other in members or other.begins_with(COMPANION) or bool(production.worker(other).get("away", false)):
			continue
		learn(production, other, "%s saw %s come home from %s with the wagon." % [production.worker(other).get("name", other), names, where])
	if not members.is_empty():
		var home := "%s's wagon came home from %s%s" % [production.worker(str(members[0])).get("name", members[0]), where,
			" with " + back if not back.is_empty() else ""]
		_remember(town, home, str(members[0]), false, production.now())
		_road_news(production, trade, town, "arrived", route_id, str(went.get("far", "")), "", back, members, home)


## A camp struck a wagon: the taken are captives already (maps, through
## Towns' 331 path, so the kin's commission stands at the counter); their
## cards and the survivors' say so, and the town's memory holds it as a
## candidate for the lawspeaker.
static func wagon_raided(production: Production, trade: Object, id: String, route_id: String, camp_id: String, taken: Dictionary) -> void:
	var went: Dictionary = _wagons.get(id, {})
	var taken_ids: Array = taken.get("members", [])
	var members: Array = went.get("members", taken_ids)
	var town := str(went.get("town", ""))
	if town.is_empty() and not members.is_empty():
		town = str(production.worker(str(members[0])).get("town", ""))
	if town.is_empty():
		return
	var far := str(went.get("far", _far_end(trade, route_id, town)))
	var where := _end_words(far)
	var holder: Variant = Offers._call(Offers.ctx, "holder_of", [camp_id])
	var raiders := ResidentCard.faction_name(str(holder)) if holder is String and not str(holder).is_empty() else "raiders"
	if not went.is_empty():
		went["struck_by"] = raiders
		for who: Variant in taken_ids:
			went["members"].erase(who)
	var left: Array = members.filter(func(who: Variant) -> bool: return not who in taken_ids)
	for who: Variant in taken_ids:
		learn(production, str(who), "%s was carried off from the wagon by %s on the road to %s." % [production.worker(str(who)).get("name", who), raiders, where])
	var taken_names := _names(production, taken_ids)
	for who: Variant in left:
		var name := str(production.worker(str(who)).get("name", who))
		if not taken_ids.is_empty():
			learn(production, str(who), "%s saw %s carried off from the wagon by %s on the road to %s." % [name, taken_names, raiders, where])
		if not taken.get("goods", {}).is_empty():
			learn(production, str(who), "%s took the wagon's food on the road to %s." % [_upper_first(raiders), where])
	var teller := str(left[0]) if not left.is_empty() else _lawspeaker(town)
	if teller.is_empty() and not taken_ids.is_empty():
		teller = str(taken_ids[0])
	if not teller.is_empty():
		var text := "%s struck the town's wagon on the road to %s" % [_upper_first(raiders), where]
		if not taken_ids.is_empty():
			text += " and carried off %s" % taken_names
		_remember(town, text, teller, true, production.now())
		_road_news(production, trade, town, "raided", route_id, far, camp_id, _goods_words(taken.get("goods", {})), went.get("all", members), text)


## A wagon lost: nobody left after a raid ("taken"), a candidate for the
## memory by the lawspeaker; its way closed ("no way"), a word on the
## officials' cards (economy brings its people straight home).
static func wagon_lost(production: Production, trade: Object, id: String, route_id: String, why: String) -> void:
	var went: Dictionary = _wagons.get(id, {})
	_wagons.erase(id)
	var town := str(went.get("town", ""))
	if town.is_empty():
		return  # Not a wagon this town saw leave (a restart): nothing to tell.
	var where := _end_words(str(went.get("far", _far_end(trade, route_id, town))))
	if why == "taken":
		var teller := _lawspeaker(town)
		var officials := _officials(production, town)
		if teller.is_empty() and not officials.is_empty():
			teller = officials[0]
		var raiders := str(went.get("struck_by", "raiders"))
		var gone := _names(production, went.get("all", []))
		var lost := "The wagon to %s was lost on the road to %s%s" % [where, raiders, ", and %s with it" % gone if not gone.is_empty() else ""]
		if not teller.is_empty():
			_remember(town, lost, teller, true, production.now())
		_road_news(production, trade, town, "lost", route_id, str(went.get("far", _far_end(trade, route_id, town))), "", "", went.get("all", []), lost)
	elif why == "no way":
		for official: String in _officials(production, town):
			learn(production, official, "The wagon to %s turned back: the road is closed." % where)


## The road's news to whoever else listens (decision 551, npc's side:
## companions' guide, a companion's heard dangers): ctx "road_news"(town,
## news) once per event, right after the town's memory line, with news =
## {kind: "raided" | "arrived" | "lost", day, hour, step, route, far (the
## far end's id), camp (a raid's camp, else ""), goods (the words: taken,
## brought back, or ""), members (the crew's worker ids), areas (the
## route's, in walking order from its from-end; [] unknown), text (the
## townsfolk's own line), told (the players in the town's zone now, ctx
## "players_in")}. Nothing happens here without the key.
static func _road_news(production: Production, trade: Object, town: String, kind: String, route_id: String, far: String, camp: String, goods: String, members: Array, text: String) -> void:
	if not Offers.ctx.has("road_news"):
		return
	var areas: Array[String] = []
	if trade != null and trade.has_method("route"):
		var way: Variant = trade.route(route_id)
		if way is Dictionary:
			for area: Variant in way.get("areas", []):
				areas.append(str(area))
	var told: Array[String] = []
	var here: Variant = Offers._call(Offers.ctx, "players_in", [town.get_slice("/", 0)])
	if here is Array:
		for id: Variant in here:
			told.append(str(id))
	var crew: Array[String] = []
	for who: Variant in members:
		crew.append(str(who))
	var now := production.now()
	var news := {"kind": kind, "day": day_of(now), "hour": DayNight.hour(now), "step": now, "route": route_id, "far": far, "camp": camp,
		"goods": goods, "members": crew, "areas": areas, "text": text, "told": told}
	Offers._call(Offers.ctx, "road_news", [town, news])


## Economy's caravan_sold: how the wagon's load sold, for the words home.
static func wagon_sold(id: String, proceeds: int, wages: int) -> void:
	if _wagons.has(id):
		_wagons[id]["sold"] = {"proceeds": proceeds, "wages": wages}


## " It sold well." / " It sold poorly." against the goods' value (ctx
## "value_of", economy's), "" with no sale told or no value known.
static func _sold_words(went: Dictionary) -> String:
	var sold: Dictionary = went.get("sold", {})
	if sold.is_empty():
		return ""
	var value := 0
	var goods: Dictionary = went.get("goods", {})
	for kind: Variant in goods:
		var each: Variant = Offers._call(Offers.ctx, "value_of", [str(kind)])
		if each is int or each is float:
			value += int(goods[kind]) * int(each)
	if value <= 0:
		return ""
	var proceeds := int(sold.get("proceeds", 0))
	if proceeds >= value:
		return " It sold well."
	if proceeds * 2 < value:
		return " It sold poorly."
	return " It sold fairly."


## The town's memory takes [param text] from [param teller]: a belief, or a
## candidate for the lawspeaker when [param candidate] (as a death is, 501).
static func _remember(town: String, text: String, teller: String, candidate: bool, at: int) -> void:
	var log: Variant = Offers._call(Offers.ctx, "memory", [town])
	if not log is Array:
		return
	var entry := TownMemory.note(log, text, teller, "", at)
	if candidate and not entry.is_empty() and str(entry.get("tier", "")) == TownMemory.BELIEF:
		entry["tier"] = TownMemory.CANDIDATE
	Offers._call(Offers.ctx, "set_memory", [town, log])


## The route's end that is not [param town]: a market or the other town.
static func _far_end(trade: Object, route_id: String, town: String) -> String:
	if trade == null or not trade.has_method("route"):
		return ""
	var way: Variant = trade.route(route_id)
	if not way is Dictionary or way.is_empty():
		return ""
	return str(way["to"]) if str(way.get("from", "")) == town else str(way.get("from", ""))


## "the castle market" for "market:castle"; a town by its name (ctx
## "town_name"); "the far end" for nothing known.
static func _end_words(end: String) -> String:
	if end.is_empty():
		return "the far end"
	if end.begins_with("market:"):
		return "the %s market" % end.trim_prefix("market:").replace("_", " ")
	var name: Variant = Offers._call(Offers.ctx, "town_name", [end])
	return str(name) if name is String and not str(name).is_empty() else "the next town"


## "about four days": the route's eta (world ticks) there and back, in days.
static func _trip_words(trade: Object, route_id: String) -> String:
	var ticks := -1
	if trade != null and trade.has_method("eta"):
		ticks = int(trade.eta(route_id))
	if ticks < 0:
		return "some days"
	var days := maxi(ceili(float(ticks) * 2.0 * World.WORLD_TICK_STEPS / maxf(float(DayNight.day_steps), 1.0)), 1)
	const WORDS := ["", "a day", "two days", "three days", "four days", "five days", "six days", "seven days", "eight days", "nine days", "ten days"]
	return ("about " if days > 1 else "") + (WORDS[days] if days < WORDS.size() else "%d days" % days)


## "10 leather and 4 hide": economy's goods by kind, as its ledger says them.
static func _goods_words(goods: Dictionary) -> String:
	var parts: Array[String] = []
	var kinds: Array = goods.keys()
	kinds.sort()
	for kind: Variant in kinds:
		if int(goods[kind]) > 0:
			parts.append("%d %s" % [int(goods[kind]), str(kind).replace("_", " ")])
	if parts.size() <= 1:
		return "".join(parts)
	return ", ".join(parts.slice(0, parts.size() - 1)) + " and " + parts[parts.size() - 1]


## "Ren", "Ren and Oda", "Ren, Oda and Bram".
static func _names(production: Production, ids: Array) -> String:
	var names: Array[String] = []
	for who: Variant in ids:
		names.append(str(production.worker(str(who)).get("name", who)))
	if names.size() <= 1:
		return "".join(names)
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + names[names.size() - 1]


## The town's officials: its appointed ones (404), at the counter.
static func _officials(production: Production, town: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in production.worker_ids(town):
		if str(production.worker(id).get("origin", "")) == "appointed" and not bool(production.worker(id).get("away", false)):
			out.append(id)
	return out


static func _lawspeaker(town: String) -> String:
	var law: Variant = Offers._call(Offers.ctx, "lawspeaker_of", [town])
	return str(law) if law is String else ""


static func _upper_first(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1) if not text.is_empty() else text


## A level-placed captive (decision 518): [param who_id] of [param town] is
## held by [param raiders] (lore's name for the camp's holder) from before
## any player came; no raid, no date. The captive's card, the kin's
## ([param kin_id], who is their [param relation]: "father", "sister") and
## the officials' say so; the rest hear it by gossip.
static func placed_captive(production: Production, town: String, who_id: String, kin_id: String, relation: String, raiders: String) -> void:
	var who := production.worker(who_id)
	if who.is_empty():
		return
	var name := str(who.get("name", who_id))
	var card := card_of(production, who_id)
	var their := _their(card) if not card.is_empty() else "them"
	var him := "her" if str(card.get("traits", {}).get("pronoun", "")) == "she" else "him"
	learn(production, who_id, "%s was carried off by %s; they hold %s at their camp." % [name, raiders, him])
	var kin_name := ""
	if not kin_id.is_empty() and not production.worker(kin_id).is_empty():
		kin_name = str(production.worker(kin_id).get("name", kin_id))
		var theirs := card_of(production, kin_id)
		learn(production, kin_id, "%s, %s %s, was carried off by %s before you came; they hold %s at their camp." % [name, _their(theirs), relation, raiders, him])
	for official: String in _officials(production, town):
		if official == kin_id or official == who_id:
			continue
		learn(production, official, "%s%s is held at the camp of %s, taken before you came." % [name,
			", %s's %s," % [kin_name, _kin_word(relation, their)] if not kin_name.is_empty() else "", raiders])


## "son" for a relation word of the captive's side ("father" -> the kin is
## their father, so the captive is the kin's son or daughter).
static func _kin_word(relation: String, their: String) -> String:
	match relation:
		"father", "mother":
			return "daughter" if their == "her" else "son"
		"son", "daughter":
			return "mother" if their == "her" else "father"
		"brother", "sister":
			return "sister" if their == "her" else "brother"
	return "cousin"


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
		perform(production, town, groups.get("inn", []), at)  # The bard's piece (decision 490).


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
## How many things a hearer remembers being told (the card's "told"), so
## a thing that fell off their heard cap is not told to them again (the
## soak of 2026-10-19: one pair told the same thing 36 times in a month).
const TOLD_MAX := 64


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
	var hearer_card := card_of(production, hearer)
	var told: Array = hearer_card.get("told", [])  # What they were told before: a thing that fell off their heard cap is not told them again.
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
			if not lore_text.is_empty() and not bool(fact.get("hearsay", false)) and not Hearsay.holds(heard, lore_text) and lore_text not in told:
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
			if not Hearsay.holds(heard, said) and said not in told:
				if not hearer_card.is_empty() and Standing.heard(hearer_card, newest_id, signi(int(newest["score"])), str(newest["why"].back()), teller_name, at):
					production.set_card(hearer, hearer_card)
				text = said
				fits = Hearsay.WITNESSED
	if text.is_empty() and not official:
		var beliefs: Array = production.worker(teller).get("heard", [])
		for i in range(beliefs.size() - 1, -1, -1):
			var entry: Dictionary = beliefs[i]
			var said := str(entry.get("text", ""))
			if bool(entry.get("believed", false)) and not said.is_empty() and not said.contains(hearer_name) and not Hearsay.holds(heard, said) and said not in told:
				text = said
				# A thing someone told of themselves ("he is a goblin among humans") keeps
				# its subject when passed on, else the next hearer takes "he" for the teller.
				var first := said.get_slice(" ", 0).to_lower()
				var from := str(entry.get("from", ""))
				if first in ["he", "she", "they"] and not from.is_empty() and from != teller_name:
					text = "%s says %s" % [from, said]
				fits = "beyond"
				omen = bool(entry.get("omen", false))
				break
	if text.is_empty():
		var facts: Array = card.get("facts", [])
		for i in range(facts.size() - 1, -1, -1):
			var fact := str(facts[i].get("text", "")) if facts[i] is Dictionary else ""
			var told_as := _as_told(fact, card)
			if fact.is_empty() or fact.contains(hearer_name) or Hearsay.holds(heard, told_as) or told_as in told:
				continue
			text = told_as
			fits = Hearsay.WITNESSED
			break
	if text.is_empty():
		return ""
	var entry := Hearsay.hear(heard, hearer, leaning_of(production, hearer, "intellect"), text, fits, teller_name, at,
		omen, leaning_of(production, hearer, "superstition"), place)
	if entry.is_empty():
		return ""
	production.set_heard(hearer, heard)
	if not hearer_card.is_empty():
		hearer_card = card_of(production, hearer)  # Fresh: Standing.heard may have written it.
		var remembered: Array = hearer_card.get("told", [])
		remembered.append(text)
		while remembered.size() > TOLD_MAX:
			remembered.pop_front()
		hearer_card["told"] = remembered
		production.set_card(hearer, hearer_card)
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
	# A scoundrel at the cap (decision 492), and the next climb once worked down.
	if str(who.get("type", "")) == SCOUNDREL:
		if owed >= float(bank_cap()) - 1.0:
			_debt_capped(production, worker_id, owed)
		elif owed < float(bank_cap()) * 0.5:
			var mine := card_of(production, worker_id)
			if bool(mine.get("capped", false)):
				mine.erase("capped")
				production.set_card(worker_id, mine)
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
