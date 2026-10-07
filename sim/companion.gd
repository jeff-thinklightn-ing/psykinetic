class_name Companion
extends GridEntity
## A creature that belongs to a player. It obeys every rule a monster does;
## what sets it apart is that a mind (CompanionMind) picks its intent and
## the sim carries that intent out through the same A*, try_move, try_attack
## and try_shove everything else uses. No movement code of its own.
##
## The mind only answers; this script validates the answer and acts. An
## intent whose target is gone or unreachable falls back to FOLLOW.
##
## The owner walking into her (bumped) asks for a decision at once, with
## the trigger, the way the owner was going and the free cells around her.
## YIELD steps to the nearest free cell off the owner's line and waits
## there for a decision window; with no such cell she stays and says so.
## A mind that answers later (the language model) has one decision window
## to yield; if it has not by then and there is room, the scripted answer
## (YIELD) is applied.
##
## A decision holds: an answer from her mind stands until its next one. A
## mind that answers later leaves her doing what she was while it thinks;
## the scripted mind fills in only when she has no decision of her mind's
## yet. Reflexes come first: below REFLEX_BELOW of her hp with a hostile
## next to her, only RETREAT, YIELD and HOLD are taken, from any mind and
## at any tick, and anything else is overridden by RETREAT. Her owner
## speaking to her (owner_spoke) asks for a decision at once, with what
## they said in the context as data. Every decision goes in the mind log
## (MindLog).

enum Intent { FOLLOW, HOLD, ATTACK, SHOVE, RETREAT, IDLE, YIELD }

const INTENT_NAMES: Array[String] = ["FOLLOW", "HOLD", "ATTACK", "SHOVE", "RETREAT", "IDLE", "YIELD"]
## The context's trigger for a bump.
const BUMPED := "owner bumped into you"
## A bump this soon after the last one is the same bump (a held key).
const BUMP_REPEAT_TICKS := 10
## How far ahead of the owner, along the way they were going, counts as
## their path.
const YIELD_PATH_CELLS := 3
## A yield cell is at most this many steps away.
const YIELD_REACH := 2
const NO_ROOM_LINE := "There's no room for me to move."
const NONE := Vector2i(-1, -1)
const DECISION_INTERVAL_TICKS := 30
## One line of speech per this many ticks.
const SPEECH_INTERVAL_TICKS := 50
const SIGHT_RANGE := 7
const LOG_LINES_FOR_MIND := 20
## The context's trigger for her owner's words.
const OWNER_SPOKE := "your owner just said to you"
## Below this share of her hp with a hostile next to her, only these.
const REFLEX_BELOW := 0.3
const REFLEX_INTENTS: Array[Intent] = [Intent.RETREAT, Intent.YIELD, Intent.HOLD]
## Blows on her and her owner within this many ticks go in the context.
const RECENT_HIT_TICKS := 100
const RECENT_HITS_KEPT := 10

## Emitted when the mind said something and the rate limit allows it.
signal said(text: String)

## The player_id this companion belongs to.
var keeper_id := ""
## The owner's live player entity while they are online; null while away.
var keeper: GridEntity
var card := "A loyal, cautious companion who guards its friend."
var mind: CompanionMind
var party_log: PartyLog

var current_intent := Intent.FOLLOW
## The entity an ATTACK or SHOVE means, or null.
var intent_target: GridEntity
## Where HOLD stands.
var hold_tile := Vector2i.ZERO
## "" | "follow" | "hold" | "attack" | "fallback"
var last_order := ""
var order_target: GridEntity
## Which mind's answer was last applied: "scripted", "ollama", "none".
var last_mind := "none"

var _next_decision_tick := 0
var _decision_reason := ""
## The way the owner was walking when they last bumped into her; ZERO
## once that has been dealt with.
var _bump_direction := Vector2i.ZERO
var _last_bump_tick := -1000
## Tick by which a later-answering mind must have yielded, or -1.
var _bump_deadline := -1
## Where YIELD goes; her own tile when there was nowhere.
var _yield_tile := NONE
var _known_hostiles: Dictionary[int, bool] = {}
var _last_speech_tick := -1000
## The mind whose decision she is carrying out; null while she has none of
## her mind's (the scripted mind is filling in).
var _decided_by: CompanionMind
## What her owner just said, for the next decision only.
var _owner_said := ""
## Recent blows on her and her owner: {on, by, amount, cause, tick}.
var _hits: Array[Dictionary] = []


func _init() -> void:
	super()
	mass = 75.0
	move_ticks = 2
	max_hp = 20
	attack_damage = 2
	strength = 8
	max_stamina = 80
	attack_ticks = 8


func intent_name() -> String:
	return INTENT_NAMES[current_intent]


## Something happened that deserves a fresh decision at the next tick.
func request_decision(reason: String) -> void:
	_decision_reason = reason


## Her owner walked into her going [param direction]: decide now. False
## (and nothing done) for the same bump again, or while already yielding.
func bumped(direction: Vector2i) -> bool:
	if World.tick - _last_bump_tick < BUMP_REPEAT_TICKS or current_intent == Intent.YIELD:
		return false
	_last_bump_tick = World.tick
	_bump_direction = direction
	request_decision(BUMPED)
	_decide()
	return true


## Her owner said [param text] to her: decide now, with it in the context.
func owner_spoke(text: String) -> void:
	_owner_said = text
	request_decision(OWNER_SPOKE)
	_decide()


## A blow landed on her ([param on_her]) or her owner, for the context.
func note_hit(on_her: bool, by: String, amount: int, cause: StringName) -> void:
	_hits.append({"on": "you" if on_her else "your owner", "by": by, "amount": amount,
		"cause": String(cause), "tick": World.tick})
	if _hits.size() > RECENT_HITS_KEPT:
		_hits.pop_front()


## The owner pressed an order key. Slots 1..4; others are accepted and ignored.
func give_order(order: String, target: GridEntity = null) -> void:
	last_order = order
	order_target = target
	request_decision("order %s" % order)


func _sim_tick() -> void:
	if keeper == null or not is_instance_valid(keeper) or not keeper.spawned:
		# Nobody to follow: stand still until the owner is back.
		current_intent = Intent.IDLE
		return
	_notice_hostiles()
	if mind != null:
		for result: Dictionary in mind.take_results():
			_take_result(result)
	if _bump_deadline != -1 and World.tick >= _bump_deadline:
		# The mind had its window and did not yield: the scripted answer.
		_bump_deadline = -1
		if current_intent != Intent.YIELD and _find_yield_tile() != NONE:
			print("[mind] %s: no yield from %s in time; the scripted answer" % [name, mind.kind])
			var context := _context(BUMPED)
			_apply(ScriptedMind.new().decide(context), "scripted", {"trigger": BUMPED,
				"prompt": JSON.stringify(context), "note": "no yield from the mind in time"}, true)
		_bump_direction = Vector2i.ZERO
	if not _decision_reason.is_empty() or World.tick >= _next_decision_tick:
		_decide()
	if _reflex_active() and current_intent not in REFLEX_INTENTS:
		_reflex_override(intent_name(), {"trigger": "reflex"})
	_execute()


# --- Deciding -----------------------------------------------------------------

func _decide() -> void:
	var reason := _decision_reason
	_next_decision_tick = World.tick + DECISION_INTERVAL_TICKS
	_decision_reason = ""
	var context := _context(reason)
	_owner_said = ""
	var answer: Dictionary = mind.decide(context) if mind != null else {}
	var entry := {"trigger": context["trigger"]}
	if not answer.is_empty():
		# A mind that answers at once: what it was told is the context.
		entry["prompt"] = JSON.stringify(context)
		entry["reply"] = JSON.stringify(answer)
		entry["latency_ms"] = 0
		_apply(answer, mind.kind, entry)
		return
	if mind != null and context["trigger"] == BUMPED:
		# Waiting on a slower mind: it has one window to yield (see _sim_tick).
		_bump_deadline = World.tick + DECISION_INTERVAL_TICKS
		return
	if mind != null and _decided_by == mind:
		return  # Her mind's last decision stands while it thinks.
	# No decision of her mind's yet: the scripted one fills in.
	var scripted := ScriptedMind.new().decide(context)
	entry["prompt"] = JSON.stringify(context)
	entry["reply"] = JSON.stringify(scripted)
	entry["latency_ms"] = 0
	entry["note"] = "no decision yet; the scripted mind fills in"
	_apply(scripted, "scripted", entry, true)


## A slower mind's request came back: its answer is applied, or, with
## none, her decision stands; either way it is logged.
func _take_result(result: Dictionary) -> void:
	var entry := {"trigger": result.get("trigger", ""), "prompt": result.get("prompt", ""),
		"reply": result.get("raw", ""), "latency_ms": result.get("latency_ms", 0)}
	var answer: Dictionary = result.get("answer", {})
	if answer.is_empty():
		entry["companion"] = String(name)
		entry["mind"] = mind.kind
		entry["outcome"] = "held"
		entry["note"] = "no answer (%s); %s stands" % [result.get("error", ""), intent_name()]
		MindLog.record(entry)
		return
	_apply(answer, mind.kind, entry)


## Below REFLEX_BELOW of her hp with a hostile next to her.
func _reflex_active() -> bool:
	if max_hp <= 0 or float(hp) / max_hp >= REFLEX_BELOW:
		return false
	for entity in World.get_entities():
		if entity is Monster and entity.spawned and World.distance(tile, entity.tile) == 1:
			return true
	return false


## The reflex wins over [param rejected]: RETREAT, logged as an override.
func _reflex_override(rejected: String, entry: Dictionary) -> void:
	print("[mind] %s: reflex: %s rejected below %d%% hp with a hostile next to her; RETREAT" % [
		name, rejected, roundi(REFLEX_BELOW * 100.0)])
	entry["note"] = "reflex: %s rejected below %d%% hp with a hostile adjacent" % [rejected, roundi(REFLEX_BELOW * 100.0)]
	entry["reflex"] = true
	_apply({"intent": "RETREAT", "target": null, "say": ""}, "scripted", entry, true)


## Validates a mind's answer against the whitelist, the reflexes and the
## live world and adopts it. An answer that does not hold up is rejected:
## her decision stands, or with none she follows. [param entry] is the
## mind log line so far; [param filling_in] for the scripted mind standing
## in, which does not count as her mind's decision.
func _apply(answer: Dictionary, source: String, entry := {}, filling_in := false) -> void:
	var intent_text := str(answer.get("intent", "")).strip_edges().to_upper()
	var target_text := str(answer.get("target", "")) if answer.get("target") != null else ""
	var intent := INTENT_NAMES.find(intent_text)
	var target: GridEntity = null
	var ok := intent != -1
	if ok and (intent == Intent.ATTACK or intent == Intent.SHOVE):
		target = _entity_named(target_text)
		ok = target != null and target != self and target != keeper
	entry["companion"] = String(name)
	entry["mind"] = source
	entry["intent"] = intent_text
	entry["target"] = target_text
	if answer.has("why"):
		entry["why"] = str(answer["why"])
	if not ok:
		entry["outcome"] = "rejected"
		if _decided_by != null:
			entry["note"] = "not a valid intent and target; %s stands" % intent_name()
			print("[mind] %s (%s): invalid answer %s; %s stands" % [name, source, answer, intent_name()])
			MindLog.record(entry)
			return
		entry["note"] = "not a valid intent and target; following"
		print("[mind] %s (%s): invalid answer %s; following" % [name, source, answer])
		intent = Intent.FOLLOW
		target = null
	elif intent not in REFLEX_INTENTS and _reflex_active() and not entry.get("reflex", false):
		entry["outcome"] = "reflex override"
		_reflex_override(intent_text, entry)
		return
	if not entry.has("outcome"):
		entry["outcome"] = "reflex override" if entry.get("reflex", false) \
				else "scripted fill-in" if filling_in else "applied"
	last_mind = source
	if not filling_in or entry.get("reflex", false):
		_decided_by = mind
	var before := current_intent
	current_intent = intent as Intent
	intent_target = target
	var line_said := str(answer.get("say", "")).strip_edges()
	if intent == Intent.YIELD:
		_bump_deadline = -1
		_bump_direction = _bump_direction if _bump_direction != Vector2i.ZERO else facing
		_yield_tile = _find_yield_tile()
		_bump_direction = Vector2i.ZERO
		# Stay out of the way for a window before thinking again.
		_next_decision_tick = World.tick + DECISION_INTERVAL_TICKS
		if _yield_tile == NONE:
			_yield_tile = tile
			if line_said.is_empty():
				line_said = NO_ROOM_LINE
			_last_speech_tick = -1000  # Said whatever the rate limit.
	if intent == Intent.HOLD:
		var tile_text := target_text.split(",")
		hold_tile = Vector2i(tile_text[0].to_int(), tile_text[1].to_int()) \
				if tile_text.size() == 2 and tile_text[0].strip_edges().is_valid_int() else tile
	if current_intent != before:
		print("[mind] %s (%s): %s%s" % [
			name, source, intent_name(), " " + target.name if target != null else ""])
	entry["say"] = line_said
	MindLog.record(entry)
	# An answer to her owner's words is always said; otherwise one line a while.
	var answering: bool = entry.get("trigger", "") == OWNER_SPOKE
	if not line_said.is_empty() and (answering or World.tick - _last_speech_tick >= SPEECH_INTERVAL_TICKS):
		_last_speech_tick = World.tick
		said.emit(line_said.left(120))


## What her mind is told. [param reason] is why it is asked now ("" for
## an ordinary window).
func _context(reason := "") -> Dictionary:
	var nearby: Array[Dictionary] = []
	for entity in World.get_entities():
		if entity == self or not entity.spawned:
			continue
		var offset: Vector2i = entity.tile - tile
		if maxi(absi(offset.x), absi(offset.y)) > SIGHT_RANGE:
			continue
		var seen := {
			"name": _name_of(entity), "type": _type_of(entity),
			"dx": offset.x, "dy": offset.y, "hostile": entity is Monster,
		}
		if entity.max_hp > 0:
			seen["hp"] = entity.hp
			seen["max_hp"] = entity.max_hp
		nearby.append(seen)
	var recent_hits: Array[Dictionary] = []
	for hit in _hits:
		if World.tick - int(hit["tick"]) <= RECENT_HIT_TICKS:
			recent_hits.append({"on": hit["on"], "by": hit["by"], "amount": hit["amount"],
				"cause": hit["cause"], "ticks_ago": World.tick - int(hit["tick"])})
	var owner_info := {}
	if keeper != null and is_instance_valid(keeper) and keeper.spawned:
		var offset: Vector2i = keeper.tile - tile
		owner_info = {
			"name": _name_of(keeper), "hp": keeper.hp, "max_hp": keeper.max_hp,
			"stamina": keeper.stamina, "max_stamina": keeper.max_stamina,
			"dx": offset.x, "dy": offset.y,
		}
	var trigger := reason
	var owner_direction := {}
	var free_cells: Array[Dictionary] = []
	if _bump_direction != Vector2i.ZERO:
		trigger = BUMPED
		owner_direction = {"dx": _bump_direction.x, "dy": _bump_direction.y}
		for direction in World.DIRECTIONS:
			if World.is_free(tile + direction) and not World._terrain_blocks_step(tile, direction, true):
				free_cells.append({"dx": direction.x, "dy": direction.y})
	return {
		"card": card,
		"trigger": trigger,
		"owner_said": _owner_said,
		"owner_direction": owner_direction,
		"free_cells": free_cells,
		"recent_hits": recent_hits,
		"log": party_log.last(LOG_LINES_FOR_MIND) if party_log != null else [],
		"nearby": nearby,
		"hp": hp, "max_hp": max_hp, "stamina": stamina, "max_stamina": max_stamina,
		"owner": owner_info,
		"last_order": last_order,
		"order_target": String(order_target.name) if _alive(order_target) else "",
		"intent": intent_name(),
		"reason": reason,
	}


## What an entity is called in her context: its label (a player's name, as
## the party log calls them) or, with none, its node name.
static func _name_of(entity: GridEntity) -> String:
	return entity.label if not entity.label.is_empty() else String(entity.name)


static func _type_of(entity: GridEntity) -> String:
	if entity is Player:
		return "player"
	if entity is Monster:
		return "monster"
	if entity is Companion:
		return "companion"
	return "object"


func _entity_named(entity_name: String) -> GridEntity:
	if entity_name.is_empty():
		return null
	for entity in World.get_entities():
		if entity.spawned and (String(entity.name) == entity_name or _name_of(entity) == entity_name):
			return entity
	return null


## A hostile coming into line of sight for the first time asks for a decision.
func _notice_hostiles() -> void:
	for entity in World.get_entities():
		if entity is Monster and entity.spawned \
				and World.distance(tile, entity.tile) <= SIGHT_RANGE \
				and World.has_line_of_sight(tile, entity.tile):
			var instance := entity.get_instance_id()
			if not _known_hostiles.has(instance):
				_known_hostiles[instance] = true
				request_decision("hostile in sight: %s" % entity.name)


# --- Acting -------------------------------------------------------------------

func _execute() -> void:
	match current_intent:
		Intent.FOLLOW, Intent.RETREAT:
			_approach(keeper, 1)
		Intent.HOLD:
			if tile != hold_tile and World.is_free(hold_tile):
				_step_toward(hold_tile, true)
		Intent.ATTACK:
			if not _alive(intent_target):
				_fall_back("target is gone")
			elif World.can_melee(tile, intent_target.tile):
				World.try_attack(self, intent_target)
			else:
				_approach(intent_target, 1)
		Intent.SHOVE:
			if not _alive(intent_target):
				_fall_back("target is gone")
			elif World.can_melee(tile, intent_target.tile):
				World.try_shove(self, intent_target)
			else:
				_approach(intent_target, 1)
		Intent.YIELD:
			if _yield_tile != NONE and tile != _yield_tile and World.is_free(_yield_tile):
				_step_toward(_yield_tile, false)
		Intent.IDLE:
			pass


## The nearest free cell that is not fire, at most YIELD_REACH steps away,
## and not on the owner's line ahead (YIELD_PATH_CELLS along the way they were going);
## of equally near ones, the least far along that line. NONE if there is
## none.
func _find_yield_tile() -> Vector2i:
	if not _alive(keeper):
		return NONE
	var direction := _bump_direction if _bump_direction != Vector2i.ZERO else facing
	var line: Dictionary[Vector2i, bool] = {}
	for k in range(1, YIELD_PATH_CELLS + 1):
		line[keeper.tile + direction * k] = true
	var best := NONE
	var best_steps := YIELD_REACH + 1
	var best_ahead := INF
	for dy in range(-YIELD_REACH, YIELD_REACH + 1):
		for dx in range(-YIELD_REACH, YIELD_REACH + 1):
			var cell := tile + Vector2i(dx, dy)
			if cell == tile or line.has(cell) or not World.is_free(cell) or World.is_fire(cell):
				continue
			var path := World.find_path(tile, cell)
			if path.is_empty() or path.size() > YIELD_REACH:
				continue
			var ahead := Vector2(cell - keeper.tile).dot(Vector2(direction))
			if path.size() < best_steps or (path.size() == best_steps and ahead < best_ahead):
				best = cell
				best_steps = path.size()
				best_ahead = ahead
	return best


## Walks until within [param reach] of [param target].
func _approach(target: Variant, reach: int) -> void:
	if not _alive(target) or World.distance(tile, target.tile) <= reach:
		return
	# A FOLLOW that cannot get closer just waits; anything else gives up.
	if not _step_toward(target.tile, true):
		if current_intent != Intent.FOLLOW:
			_fall_back("cannot reach %s" % target.name)


## One A* step toward [param goal]. False if there is no way there.
func _step_toward(goal: Vector2i, occupied_goal_ok: bool) -> bool:
	if World.tick < next_move_tick:
		return true
	var path := World.find_path(tile, goal, occupied_goal_ok)
	if path.is_empty():
		return false
	World.try_move(self, path[0] - tile)
	return true


func _fall_back(why: String) -> void:
	print("[mind] %s: %s; following" % [name, why])
	current_intent = Intent.FOLLOW
	intent_target = null
	if last_order == "attack":
		last_order = ""
		order_target = null
	request_decision("fell back")


## Safe to call with a freed reference, which a target that died can be.
static func _alive(entity: Variant) -> bool:
	return entity != null and is_instance_valid(entity) and entity.spawned
