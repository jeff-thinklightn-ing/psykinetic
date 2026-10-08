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
## Why she is asked, as kept internally; _trigger_text turns each into
## what her mind reads, the player named ("Jeff bumped into you").
const BUMPED := "bumped"
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
const OWNER_SPOKE := "spoke"
const OWNER_BACK := "back"
## Below this share of her hp with a hostile next to her, only RETREAT.
const REFLEX_BELOW := 0.3
const REFLEX_INTENTS: Array[Intent] = [Intent.RETREAT]
## The trigger of an ordinary window. While a hostile is within
## COMBAT_RANGE of her or her player the window only asks if the fight
## changed (_what_changed); out of a fight it asks unless she is going for a
## target that lives and is in reach (SIGHT_RANGE).
const ROUTINE := "routine"
const COMBAT_RANGE := 4
## Something her player says that reads as an instruction (is_instruction)
## stands for INSTRUCTION_TICKS or until they give another; for
## INSTRUCTION_LOCK_TICKS after a new one only reflexes, hp thresholds,
## their words and bumps ask her again.
const INSTRUCTION_TICKS := 600
const INSTRUCTION_LOCK_TICKS := 60
const IMPERATIVES: Array[String] = ["stay", "come", "follow", "go", "get", "attack", "hit", "kill", "fight",
	"fall", "back", "retreat", "run", "flee", "wait", "hold", "stop", "help", "guard", "protect", "defend",
	"keep", "move", "leave", "push", "shove", "step", "let", "don't", "dont", "do", "watch", "take",
	"hide", "charge", "rest", "heal", "look", "with", "behind", "here", "over", "out", "away", "kill",
	"save", "cover", "split", "regroup", "careful", "be", "never", "always", "please"]
## Her own last lines, kept for the context (you_said_recently).
const SAID_KEPT := 5
const SAID_RULE := "Never repeat these. Usually say nothing."
## Blows on her and her owner within this many ticks go in the context.
const RECENT_HIT_TICKS := 100
const RECENT_HITS_KEPT := 10
## Blows ask her again, but at most once per HURT_REASK_TICKS since her last
## decision and only if the fight changed since then (_what_changed);
## otherwise her decision holds.
const HIT := "you were hit"
const OWNER_HIT := "keeper hit"
const TRIGGER_TEXTS := {
	BUMPED: "%s bumped into you", OWNER_SPOKE: "%s just said to you",
	OWNER_HIT: "%s was hit", OWNER_BACK: "%s is back",
}
const HURT_TRIGGERS: Array[String] = [HIT, OWNER_HIT]
const HURT_REASK_TICKS := 30
## Crossing one of these fractions of her or her owner's hp, either way, is
## a change.
const HP_THRESHOLDS: Array[float] = [0.5, 0.3]
## Her context names objects this close, hostiles this close or going for
## her or her owner, others in sight; at most NEARBY_KEPT, nearest first.
const OBJECT_RANGE := 2
const HOSTILE_RANGE := 4
const NEARBY_KEPT := 6
## The party log's tail is read this far back, runs of the same line
## collapsed, and the last LOG_LINES_FOR_MIND of those kept.
const LOG_LINES_SCANNED := 60

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
## When she last decided and how the fight stood then (_situation_now).
var _last_decision_tick := -1000
var _situation := {}
## A blow's trigger waiting for HURT_REASK_TICKS to pass, or "".
var _hurt_pending := ""
## Her player's standing instruction and when it was given.
var _instruction := ""
var _instruction_tick := -100000
## Her own last lines, newest last.
var _said: Array[String] = []


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


## Something happened that deserves a fresh decision at the next tick. A
## blow (HURT_TRIGGERS) waits on the throttle instead (see _sim_tick); a
## reason she may speak to is not overwritten by one she may not.
func request_decision(reason: String) -> void:
	if reason in HURT_TRIGGERS:
		_hurt_pending = reason
		return
	if may_speak(_trigger_text(_decision_reason)) and not may_speak(_trigger_text(reason)):
		return
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


## Her owner said [param text] to her (typed or a quick phrase): decide
## now, with it in the context.
func owner_spoke(text: String) -> void:
	_owner_said = text
	if is_instruction(text):
		_instruction = text
		_instruction_tick = World.tick
	request_decision(OWNER_SPOKE)
	_decide()


## A line she said, for you_said_recently.
func remember_said(line: String) -> void:
	_said.append(line)
	if _said.size() > SAID_KEPT:
		_said.pop_front()


## A blow landed on her ([param on_her]) or her owner, for the context.
func note_hit(on_her: bool, by: String, amount: int, cause: StringName) -> void:
	_hits.append({"on": "you" if on_her else keeper_name(), "by": by, "amount": amount,
		"cause": String(cause), "tick": World.tick})
	if _hits.size() > RECENT_HITS_KEPT:
		_hits.pop_front()


## The player she travels with, by name, as her mind reads them.
func keeper_name() -> String:
	return _name_of(keeper) if keeper != null and is_instance_valid(keeper) else "your companion"


## What her mind reads for [param reason]: a trigger's words, the player
## named; anything else as it is.
func _trigger_text(reason: String) -> String:
	var head := reason.get_slice(": ", 0)
	if not TRIGGER_TEXTS.has(head):
		return reason
	var text: String = TRIGGER_TEXTS[head] % keeper_name()
	return text + reason.substr(head.length())


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
			_apply(ScriptedMind.new().decide(context), "scripted", {"trigger": _trigger_text(BUMPED),
				"prompt": JSON.stringify(context), "note": "no yield from the mind in time"}, true)
		_bump_direction = Vector2i.ZERO
	if not _hurt_pending.is_empty() and World.tick - _last_decision_tick >= HURT_REASK_TICKS:
		var change := _what_changed()
		if not change.is_empty() and _decision_reason.is_empty():
			_decision_reason = "%s: %s" % [_hurt_pending, change]
		_hurt_pending = ""
	if not _decision_reason.is_empty() and not _may_reask(_decision_reason):
		print("[mind] %s: %s; %s's instruction stands" % [name, _trigger_text(_decision_reason), keeper_name()])
		_decision_reason = ""
	if not _decision_reason.is_empty():
		_decide()
	elif World.tick >= _next_decision_tick:
		_routine_window()
	if _reflex_active() and current_intent not in REFLEX_INTENTS:
		_reflex_override(intent_name(), {"trigger": "reflex"})
	_execute()


# --- Deciding -----------------------------------------------------------------

## The ordinary window, every DECISION_INTERVAL_TICKS: in a fight it asks
## only if the fight changed, out of one unless she has a live target in
## reach; not at all just after an instruction, but for an hp threshold.
func _routine_window() -> void:
	_next_decision_tick = World.tick + DECISION_INTERVAL_TICKS
	var change := _what_changed()
	if in_fight():
		if change.is_empty() or not _may_reask(change):
			return
		_decision_reason = "fight changed: %s" % change
	else:
		if _instruction_locked() or _target_in_reach():
			return
		_decision_reason = ROUTINE
	_decide()


## A hostile within COMBAT_RANGE of her or her player.
func in_fight() -> bool:
	var player_here := keeper != null and is_instance_valid(keeper) and keeper.spawned
	for entity in World.get_entities():
		if entity is Monster and entity.spawned and (World.distance(tile, entity.tile) <= COMBAT_RANGE
				or player_here and World.distance(keeper.tile, entity.tile) <= COMBAT_RANGE):
			return true
	return false


func _target_in_reach() -> bool:
	return current_intent in [Intent.ATTACK, Intent.SHOVE] and intent_target != null and _alive(intent_target) \
			and World.distance(tile, intent_target.tile) <= SIGHT_RANGE


## Within INSTRUCTION_LOCK_TICKS of a new instruction.
func _instruction_locked() -> bool:
	return not _instruction.is_empty() and World.tick - _instruction_tick < INSTRUCTION_LOCK_TICKS


## Whether [param reason] may ask her now: always, but in the lock after an
## instruction, when only her player's words, a bump or an hp threshold may.
func _may_reask(reason: String) -> bool:
	if not _instruction_locked():
		return true
	return reason.get_slice(": ", 0) in [OWNER_SPOKE, BUMPED] or "hp crossed" in reason


## The instruction standing now, or "" (none, or older than INSTRUCTION_TICKS).
func standing_instruction() -> String:
	if _instruction.is_empty() or World.tick - _instruction_tick > INSTRUCTION_TICKS:
		return ""
	return _instruction


## Whether [param text] reads as an instruction: not a question, and it
## starts with an imperative ("Stay back!", "Get them", "Don't...") or is
## exclaimed. A plain heuristic; the mind reads the words themselves.
static func is_instruction(text: String) -> bool:
	var line := text.strip_edges()
	if line.is_empty() or line.ends_with("?"):
		return false
	var first := line.get_slice(" ", 0).to_lower().rstrip("!.,;:")
	return first in IMPERATIVES or line.ends_with("!")


## Whether her mind is asked for a line with this trigger (its words): to
## her player's words, a death, an hp threshold. Otherwise "say" is not in
## the reply's schema, and any line she gives is dropped.
func may_speak(trigger: String) -> bool:
	return trigger == _trigger_text(OWNER_SPOKE) or trigger.ends_with(" died") or "hp crossed" in trigger


func _decide() -> void:
	var reason := _decision_reason if not _decision_reason.is_empty() else ROUTINE
	_next_decision_tick = World.tick + DECISION_INTERVAL_TICKS
	_decision_reason = ""
	_last_decision_tick = World.tick
	_situation = _situation_now()
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
	if mind != null and _bump_direction != Vector2i.ZERO:
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


## How the fight stands, to tell later whether it changed: the hostiles
## next to her or her owner, which HP_THRESHOLDS band each of them is in,
## whether her target lives.
func _situation_now() -> Dictionary:
	var owner_here := keeper != null and is_instance_valid(keeper) and keeper.spawned
	var adjacent: Array[int] = []
	for entity in World.get_entities():
		if entity is Monster and entity.spawned and (World.distance(tile, entity.tile) == 1
				or owner_here and World.distance(keeper.tile, entity.tile) == 1):
			adjacent.append(entity.get_instance_id())
	return {"adjacent": adjacent, "hp_band": _hp_band(self),
		"owner_hp_band": _hp_band(keeper) if owner_here else -1,
		"target": intent_target != null and _alive(intent_target)}


## How many of HP_THRESHOLDS [param entity]'s hp is below.
static func _hp_band(entity: GridEntity) -> int:
	var band := 0
	for threshold in HP_THRESHOLDS:
		if entity.max_hp > 0 and float(entity.hp) / entity.max_hp < threshold:
			band += 1
	return band


## What changed in the fight since her last decision, in words for the
## trigger, or "" for nothing that calls for a new one. Her player's
## words and bumps ask her at once and need no change.
func _what_changed() -> String:
	var now := _situation_now()
	var before := _situation
	for id: int in now["adjacent"]:
		if id not in before.get("adjacent", []):
			return "a new hostile next to you or %s" % keeper_name()
	if now["hp_band"] != before.get("hp_band", now["hp_band"]):
		return "your hp crossed %s" % _threshold_crossed(before.get("hp_band", 0), now["hp_band"])
	if now["owner_hp_band"] != before.get("owner_hp_band", now["owner_hp_band"]) and now["owner_hp_band"] != -1 \
			and before.get("owner_hp_band", -1) != -1:
		return "%s's hp crossed %s" % [keeper_name(), _threshold_crossed(before["owner_hp_band"], now["owner_hp_band"])]
	if before.get("target", false) and not now["target"]:
		return "your target is gone"
	return ""


static func _threshold_crossed(before: int, now: int) -> String:
	var threshold: float = HP_THRESHOLDS[maxi(before, now) - 1]
	return "%d%%" % roundi(threshold * 100.0)


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
	if not line_said.is_empty() and not may_speak(str(entry.get("trigger", ""))):
		entry["say_dropped"] = line_said
		line_said = ""
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
	var answering: bool = entry.get("trigger", "") == _trigger_text(OWNER_SPOKE)
	if not line_said.is_empty() and (answering or World.tick - _last_speech_tick >= SPEECH_INTERVAL_TICKS):
		_last_speech_tick = World.tick
		remember_said(line_said.left(120))
		said.emit(line_said.left(120))


## What her mind is told. [param reason] is why it is asked now ("" for
## an ordinary window).
func _context(reason := "") -> Dictionary:
	var nearby: Array[Dictionary] = []
	for entity in World.get_entities():
		if entity == self or entity == keeper or not entity.spawned:
			continue  # The player she travels with has a field of their own.
		var offset: Vector2i = entity.tile - tile
		var distance := maxi(absi(offset.x), absi(offset.y))
		if entity is Monster:
			var monster := entity as Monster
			var after_us := monster.target != null and (monster.target == self or monster.target == keeper)
			if distance > HOSTILE_RANGE and not after_us:
				continue
		elif distance > (OBJECT_RANGE if _type_of(entity) == "object" else SIGHT_RANGE):
			continue
		var seen := {
			"name": _name_of(entity), "type": _type_of(entity),
			"dx": offset.x, "dy": offset.y, "hostile": entity is Monster,
		}
		if entity.max_hp > 0:
			seen["hp"] = entity.hp
			seen["max_hp"] = entity.max_hp
		nearby.append(seen)
	nearby.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := maxi(absi(int(a["dx"])), absi(int(a["dy"])))
		var db := maxi(absi(int(b["dx"])), absi(int(b["dy"])))
		return da < db or da == db and str(a["name"]) < str(b["name"]))
	nearby = nearby.slice(0, NEARBY_KEPT)
	var recent_hits: Array[Dictionary] = []
	for hit in _hits:
		if World.tick - int(hit["tick"]) <= RECENT_HIT_TICKS:
			recent_hits.append({"on": hit["on"], "by": hit["by"], "amount": hit["amount"],
				"cause": hit["cause"], "ticks_ago": World.tick - int(hit["tick"])})
	var companion_info := {}
	if keeper != null and is_instance_valid(keeper) and keeper.spawned:
		var offset: Vector2i = keeper.tile - tile
		companion_info = {
			"name": _name_of(keeper), "hp": keeper.hp, "max_hp": keeper.max_hp,
			"stamina": keeper.stamina, "max_stamina": keeper.max_stamina,
			"dx": offset.x, "dy": offset.y,
		}
	var trigger := _trigger_text(reason)
	var companion_direction := {}
	var free_cells: Array[Dictionary] = []
	if _bump_direction != Vector2i.ZERO:
		trigger = _trigger_text(BUMPED)
		companion_direction = {"dx": _bump_direction.x, "dy": _bump_direction.y}
		for direction in World.DIRECTIONS:
			if World.is_free(tile + direction) and not World._terrain_blocks_step(tile, direction, true):
				free_cells.append({"dx": direction.x, "dy": direction.y})
	var log_lines: Array[String] = []
	if party_log != null:
		var own := "%s said: " % name
		for line in party_log.last(LOG_LINES_SCANNED):
			if not line.begins_with(own):
				log_lines.append(line)
	var instruction := standing_instruction()
	return {
		"situation": situation_text(),
		"card": "%s Do what %s asks. Go against it only to save %s's life or yours, and say why when you do." % [
			card, keeper_name(), keeper_name()],
		"standing_instruction": {"said": instruction, "ticks_ago": World.tick - _instruction_tick} \
				if not instruction.is_empty() else {},
		"you_said_recently": {"lines": _said.duplicate(), "rule": SAID_RULE},
		"_say": may_speak(trigger),
		"together": "%s is your companion. You travel together by choice." % keeper_name(),
		"trigger": trigger,
		"companion_said": _owner_said,
		"companion_direction": companion_direction,
		"free_cells": free_cells,
		"recent_hits": recent_hits,
		"log": collapse_log(log_lines).slice(-LOG_LINES_FOR_MIND),
		"nearby": nearby,
		"hp": hp, "max_hp": max_hp, "stamina": stamina, "max_stamina": max_stamina,
		"companion": companion_info,
		"intent": intent_name(),
		"reason": trigger if not reason.is_empty() else "",
	}


## [param lines] with each run of the same line made one, its count added
## ("Brute hit Player for 1 ×6."), and each run of two lines taking turns
## too ("Pip hit Brute for 2 ×4, shoved Brute ×4."; the second's subject
## dropped when it is the first's).
static func collapse_log(lines: Array[String]) -> Array[String]:
	var out: Array[String] = []
	var i := 0
	while i < lines.size():
		var run := 1
		while i + run < lines.size() and lines[i + run] == lines[i]:
			run += 1
		if run > 1:
			out.append("%s ×%d." % [lines[i].trim_suffix("."), run])
			i += run
			continue
		var pairs := 0
		if i + 1 < lines.size():
			while i + 2 * pairs + 1 < lines.size() and lines[i + 2 * pairs] == lines[i] \
					and lines[i + 2 * pairs + 1] == lines[i + 1]:
				pairs += 1
		if pairs >= 2:
			var first := lines[i].trim_suffix(".")
			var second := lines[i + 1].trim_suffix(".")
			var subject := first.get_slice(" ", 0) + " "
			if second.begins_with(subject):
				second = second.substr(subject.length())
			out.append("%s ×%d, %s ×%d." % [first, pairs, second, pairs])
			i += 2 * pairs
			continue
		out.append(lines[i])
		i += 1
	return out


## The situation in two to four plain sentences, first in her context: the
## monsters next to her, her hp, her player's distance and hp, who is in
## danger (below 30% hp, or below half with a monster next to them).
func situation_text() -> String:
	const NUMBERS: Array[String] = ["No", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight"]
	var next_to_her := _monsters_next_to(tile)
	var sentences: Array[String] = []
	var count := NUMBERS[mini(next_to_her, NUMBERS.size() - 1)]
	sentences.append("%s monster%s next to you." % [count, " is" if next_to_her == 1 else "s are"])
	sentences.append("You have %d of %d HP." % [hp, max_hp])
	var her_danger := _in_danger(self, next_to_her)
	var their_danger := false
	var who := keeper_name()
	if keeper != null and is_instance_valid(keeper) and keeper.spawned:
		var distance := World.distance(tile, keeper.tile)
		sentences.append("%s is %s with %d of %d HP." % [who,
			"next to you" if distance <= 1 else "%d cells away" % distance, keeper.hp, keeper.max_hp])
		their_danger = _in_danger(keeper, _monsters_next_to(keeper.tile))
	else:
		sentences.append("%s is not here." % who)
	if her_danger and their_danger:
		sentences.append("You are both in danger.")
	elif her_danger:
		sentences.append("You are in danger.")
	elif their_danger:
		sentences.append("%s is in danger." % who)
	else:
		sentences.append("Neither of you is in danger.")
	return " ".join(sentences)


static func _monsters_next_to(at: Vector2i) -> int:
	var count := 0
	for entity in World.get_entities():
		if entity is Monster and entity.spawned and World.distance(at, entity.tile) == 1:
			count += 1
	return count


static func _in_danger(entity: GridEntity, monsters_next: int) -> bool:
	if entity.max_hp <= 0:
		return false
	var share := float(entity.hp) / entity.max_hp
	return share < REFLEX_BELOW or share < 0.5 and monsters_next > 0


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
	request_decision("fell back")


## Safe to call with a freed reference, which a target that died can be.
static func _alive(entity: Variant) -> bool:
	return entity != null and is_instance_valid(entity) and entity.spawned
