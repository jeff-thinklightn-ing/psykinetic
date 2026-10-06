class_name Companion
extends GridEntity
## A creature that belongs to a player. It obeys every rule a monster does;
## what sets it apart is that a mind (CompanionMind) picks its intent and
## the sim carries that intent out through the same A*, try_move, try_attack
## and try_shove everything else uses. No movement code of its own.
##
## The mind only answers; this script validates the answer and acts. An
## intent whose target is gone or unreachable falls back to FOLLOW.

enum Intent { FOLLOW, HOLD, ATTACK, SHOVE, RETREAT, IDLE }

const INTENT_NAMES: Array[String] = ["FOLLOW", "HOLD", "ATTACK", "SHOVE", "RETREAT", "IDLE"]
const DECISION_INTERVAL_TICKS := 30
## One line of speech per this many ticks.
const SPEECH_INTERVAL_TICKS := 50
const SIGHT_RANGE := 7
const LOG_LINES_FOR_MIND := 20

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
var _known_hostiles: Dictionary[int, bool] = {}
var _last_speech_tick := -1000


func intent_name() -> String:
	return INTENT_NAMES[current_intent]


## Something happened that deserves a fresh decision at the next tick.
func request_decision(reason: String) -> void:
	_decision_reason = reason


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
		var late := mind.poll()
		if not late.is_empty():
			_apply(late, mind.kind)
	if not _decision_reason.is_empty() or World.tick >= _next_decision_tick:
		_decide()
	_execute()


# --- Deciding -----------------------------------------------------------------

func _decide() -> void:
	_next_decision_tick = World.tick + DECISION_INTERVAL_TICKS
	_decision_reason = ""
	var context := _context()
	var answer: Dictionary = mind.decide(context) if mind != null else {}
	var source := mind.kind if mind != null else "none"
	if answer.is_empty():
		answer = ScriptedMind.new().decide(context)
		source = "scripted"
	_apply(answer, source)


## Validates a mind's answer against the whitelist and the live world and
## adopts it. Anything that does not hold up becomes FOLLOW, and is logged.
func _apply(answer: Dictionary, source: String) -> void:
	last_mind = source
	var intent_text := str(answer.get("intent", "")).strip_edges().to_upper()
	var target_text := str(answer.get("target", "")) if answer.get("target") != null else ""
	var intent := INTENT_NAMES.find(intent_text)
	var target: GridEntity = null
	var ok := intent != -1
	if ok and (intent == Intent.ATTACK or intent == Intent.SHOVE):
		target = _entity_named(target_text)
		ok = target != null and target != self and target != keeper
	if not ok:
		print("[mind] %s (%s): invalid answer %s; following" % [name, source, answer])
		intent = Intent.FOLLOW
		target = null
	var before := current_intent
	current_intent = intent as Intent
	intent_target = target
	if intent == Intent.HOLD:
		var tile_text := target_text.split(",")
		hold_tile = Vector2i(tile_text[0].to_int(), tile_text[1].to_int()) \
				if tile_text.size() == 2 and tile_text[0].strip_edges().is_valid_int() else tile
	if current_intent != before:
		print("[mind] %s (%s): %s%s" % [
			name, source, intent_name(), " " + target.name if target != null else ""])
	var line_said := str(answer.get("say", "")).strip_edges()
	if not line_said.is_empty() and World.tick - _last_speech_tick >= SPEECH_INTERVAL_TICKS:
		_last_speech_tick = World.tick
		said.emit(line_said.left(120))


func _context() -> Dictionary:
	var nearby: Array[Dictionary] = []
	for entity in World.get_entities():
		if entity == self or not entity.spawned:
			continue
		var offset: Vector2i = entity.tile - tile
		if maxi(absi(offset.x), absi(offset.y)) > SIGHT_RANGE:
			continue
		nearby.append({
			"name": String(entity.name), "type": _type_of(entity),
			"dx": offset.x, "dy": offset.y, "hostile": entity is Monster,
		})
	var owner_info := {}
	if keeper != null and is_instance_valid(keeper) and keeper.spawned:
		var offset: Vector2i = keeper.tile - tile
		owner_info = {
			"name": String(keeper.name), "hp": keeper.hp, "max_hp": keeper.max_hp,
			"stamina": keeper.stamina, "max_stamina": keeper.max_stamina,
			"dx": offset.x, "dy": offset.y,
		}
	return {
		"card": card,
		"log": party_log.last(LOG_LINES_FOR_MIND) if party_log != null else [],
		"nearby": nearby,
		"hp": hp, "max_hp": max_hp, "stamina": stamina, "max_stamina": max_stamina,
		"owner": owner_info,
		"last_order": last_order,
		"order_target": String(order_target.name) if _alive(order_target) else "",
		"intent": intent_name(),
		"reason": _decision_reason,
	}


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
		if entity.spawned and String(entity.name) == entity_name:
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
		Intent.IDLE:
			pass


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
