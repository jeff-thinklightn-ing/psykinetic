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
