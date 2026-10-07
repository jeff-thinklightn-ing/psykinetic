extends Node
## Companions, with the ScriptedMind, against the real room in main.tscn.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

var _failures := 0
var _main: Node


func _ready() -> void:
	World.set_process(false)
	Net.port = 17786  # Not 7777: the editor may be hosting there.
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)

	_test_follows_through_the_passage()
	_test_attacks_a_hostile_in_range()
	_test_falls_back_when_the_target_dies()
	_test_retreats_on_low_hp()
	_test_holds_on_order()
	_test_persists_and_resumes()
	_test_idles_while_owner_offline()
	_test_malformed_llm_reply_uses_scripted()
	_test_llm_reasoning_is_off_and_stripped()
	_test_native_ollama_endpoint()
	_test_yields_when_bumped()
	_test_says_so_with_no_room()
	_test_slow_mind_gets_the_scripted_yield()
	_test_old_record_gets_a_companion()

	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_follows_through_the_passage() -> void:
	print("\n== follows the owner through the two-wide passage ==")
	_kill_monsters()
	var owner := _player()
	var pet := _companion()
	_check(pet != null and pet.keeper == owner, "the host has a companion that knows its owner")
	_check(pet != null and World.distance(pet.tile, owner.tile) == 1, "spawned adjacent (at %s, owner at %s)" % [pet.tile, owner.tile])
	_check(pet != null and pet.current_intent == Companion.Intent.FOLLOW, "and is following")
	_walk_to(owner, Vector2i(5, 11))
	_walk_to(owner, Vector2i(12, 12))
	for i in 12:
		World.step()
	_check(owner.tile == Vector2i(12, 12), "owner crossed the passage (at %s)" % owner.tile)
	_check(World.distance(pet.tile, owner.tile) <= 2, "companion kept up (at %s)" % pet.tile)


func _test_attacks_a_hostile_in_range() -> void:
	print("\n== attacks a monster that comes within range ==")
	var pet := _companion()
	var imp := _spawn_imp(Vector2i(10, 11))
	_step_until(func() -> bool: return pet.current_intent == Companion.Intent.ATTACK, 40)
	_check(pet.current_intent == Companion.Intent.ATTACK and pet.intent_target == imp, "intent is ATTACK on the imp (%s)" % pet.intent_name())
	_step_until(func() -> bool: return imp.hp < imp.max_hp, 40)
	_check(imp.hp < imp.max_hp, "and it hits (imp hp %d/%d)" % [imp.hp, imp.max_hp])


func _test_falls_back_when_the_target_dies() -> void:
	print("\n== falls back to FOLLOW when its target dies ==")
	var pet := _companion()
	var imp := pet.intent_target
	_check(imp != null and pet.current_intent == Companion.Intent.ATTACK, "still attacking")
	World.damage(imp, 999)
	World.step()
	_check(pet.current_intent == Companion.Intent.FOLLOW, "target dead: FOLLOW (%s)" % pet.intent_name())
	_check(pet.last_mind == "scripted", "decided by the scripted mind")


func _test_retreats_on_low_hp() -> void:
	print("\n== retreats toward the owner below 30% hp ==")
	var owner := _player()
	var pet := _companion()
	_walk_to(owner, Vector2i(8, 12))
	for i in 8:
		World.step()
	pet.hp = 5
	pet.request_decision("hurt")
	World.step()
	_check(pet.current_intent == Companion.Intent.RETREAT, "intent is RETREAT (%s)" % pet.intent_name())
	_walk_to(owner, Vector2i(12, 12))
	for i in 10:
		World.step()
	_check(World.distance(pet.tile, owner.tile) <= 1, "and it stays by the owner (at %s, owner at %s)" % [pet.tile, owner.tile])
	pet.hp = pet.max_hp


func _test_holds_on_order() -> void:
	print("\n== holds position on order while a monster approaches ==")
	var owner := _player()
	var pet := _companion()
	_main.handle_order(owner, 2)
	World.step()
	_check(pet.current_intent == Companion.Intent.HOLD, "order 2: HOLD (%s)" % pet.intent_name())
	var held := pet.tile
	var imp := _spawn_imp(Vector2i(8, 11))
	imp.sight_range = 7
	for i in 20:
		World.step()
	_check(pet.tile == held, "it did not move (at %s)" % pet.tile)
	_check(World.distance(imp.tile, pet.tile) <= 2 or World.distance(imp.tile, owner.tile) <= 2, "while the imp closed in (at %s)" % imp.tile)
	World.damage(imp, 999)
	_main.handle_order(owner, 1)
	World.step()
	_check(pet.current_intent == Companion.Intent.FOLLOW, "order 1: FOLLOW again (%s)" % pet.intent_name())


func _test_persists_and_resumes() -> void:
	print("\n== persists through a restart and resumes following ==")
	var owner := _player()
	var pet := _companion()
	pet.hp = 13
	var pet_name := String(pet.name)
	var pet_tile := pet.tile
	Net.state_path = OS.get_user_data_dir().path_join("companion_test_world.json")
	_main._save_state()
	_main._start_level(true)
	var back := _companion()
	_check(back != null and back != pet, "a companion is back after the rebuild from the snapshot")
	_check(back != null and String(back.name) == pet_name and back.hp == 13, "with its name and hp (%s, hp %d)" % [back.name if back else "", back.hp if back else -1])
	_check(back != null and World.distance(back.tile, pet_tile) <= 1, "near where it was (at %s, was %s)" % [back.tile if back else Vector2i(-1, -1), pet_tile])
	_check(back != null and back.keeper == _player() and back.current_intent == Companion.Intent.FOLLOW, "following its owner again")
	DirAccess.remove_absolute(Net.state_path)
	Net.state_path = ""


func _test_idles_while_owner_offline() -> void:
	print("\n== idles, and monsters ignore it, while the owner is offline ==")
	var pet := _companion()
	var owner := _player()
	var where := pet.tile
	_main._on_peer_disconnected(Net.local_id)
	_check(not is_instance_valid(owner) or not owner.spawned, "owner despawned")
	World.step()
	_check(pet.keeper == null and pet.current_intent == Companion.Intent.IDLE, "companion idles (%s)" % pet.intent_name())
	var hp_before := pet.hp
	var imp := _spawn_imp(where + Vector2i(-3, 0))
	imp.sight_range = 7
	for i in 20:
		World.step()
	_check(imp.tile == where + Vector2i(-3, 0), "a monster with line of sight does not come for it (imp at %s)" % imp.tile)
	_check(pet.tile == where and pet.hp == hp_before, "and it stood still, unhurt")
	World.damage(imp, 999)
	_main._join_player(Net.local_id, Net.player_id, Net.player_name)
	World.step()
	_check(pet.keeper == _player() and pet.current_intent == Companion.Intent.FOLLOW, "owner back: FOLLOW again (%s)" % pet.intent_name())


func _test_malformed_llm_reply_uses_scripted() -> void:
	print("\n== a malformed LLM reply falls back to the scripted answer ==")
	var pet := _companion()
	var mind := OllamaMind.new("http://127.0.0.1:1/v1/chat/completions", "stub", _main)
	pet.mind = mind
	mind.stub_next_reply("this is { not json")
	pet.request_decision("test")
	World.step()
	_check(pet.last_mind == "scripted", "the window used the scripted mind (%s)" % pet.last_mind)
	_check(not mind.last_error.is_empty(), "and the failure was recorded (%s)" % mind.last_error)
	_check(pet.current_intent == Companion.Intent.FOLLOW, "intent is a valid one (%s)" % pet.intent_name())
	mind.stub_next_reply(JSON.stringify({"choices": [{"message": {"content": '{"intent": "HOLD", "target": null, "say": "Holding here."}'}}]}))
	pet.request_decision("test")
	World.step()
	World.step()
	_check(pet.current_intent == Companion.Intent.HOLD and pet.last_mind == "ollama", "a well-formed reply is applied when it arrives (%s by %s)" % [pet.intent_name(), pet.last_mind])
	pet.mind = ScriptedMind.new()


func _test_llm_reasoning_is_off_and_stripped() -> void:
	print("\n== reasoning is turned off in the request and stripped from the reply ==")
	var pet := _companion()
	var mind := OllamaMind.new("http://127.0.0.1:1/v1/chat/completions", "stub", _main)
	var body: Variant = JSON.parse_string(mind.request_body({"hp": 1}))
	_check(body is Dictionary and body.get("think") == false, "the request body carries \"think\": false")

	# Back to FOLLOW first, so the reply below visibly changes something.
	pet.mind = ScriptedMind.new()
	pet.give_order("follow")
	World.step()
	_check(pet.current_intent == Companion.Intent.FOLLOW, "starting from FOLLOW (%s)" % pet.intent_name())

	# A think block ahead of the answer, with a decoy JSON object inside it.
	pet.mind = mind
	var content := "<think>\nThe owner is fine. Maybe {\"intent\": \"ATTACK\", \"target\": \"nobody\"}? No.\n</think>\n" \
			+ "{\"intent\": \"HOLD\", \"target\": null, \"say\": \"\"}"
	mind.stub_next_reply(JSON.stringify({"choices": [{"message": {"content": content}}]}))
	pet.request_decision("test")
	World.step()
	World.step()
	_check(mind.last_error.is_empty(), "a reply with a <think> block parses (%s)" % mind.last_error)
	_check(pet.current_intent == Companion.Intent.HOLD and pet.last_mind == "ollama",
			"and the answer after the block is the one applied (%s by %s)" % [pet.intent_name(), pet.last_mind])

	_check(OllamaMind.strip_think("reasoning...</think>{\"intent\": \"FOLLOW\"}") == "{\"intent\": \"FOLLOW\"}",
			"a stray closing tag drops everything before it")
	_check(OllamaMind.strip_think("{\"intent\": \"FOLLOW\"}<THINK>never closed") == "{\"intent\": \"FOLLOW\"}",
			"an unclosed block drops everything after it, whatever the case")
	_check(OllamaMind.strip_think("{\"intent\": \"FOLLOW\"}") == "{\"intent\": \"FOLLOW\"}", "a reply without one is untouched")
	pet.mind = ScriptedMind.new()


func _test_native_ollama_endpoint() -> void:
	print("\n== Ollama's native /api/chat: request and reply shape ==")
	var pet := _companion()
	_check(Net.DEFAULT_LLM_URL == "http://127.0.0.1:11434/api/chat", "the default URL is the native endpoint")
	var mind := OllamaMind.new(Net.DEFAULT_LLM_URL, "stub", _main)
	_check(not mind.openai_shaped, "/api/chat is spoken to natively")
	var body: Variant = JSON.parse_string(mind.request_body({"hp": 1}))
	_check(body is Dictionary and body.get("model") == "stub" and body.get("think") == false
			and body.get("stream") == false and body.get("format") == "json"
			and int(body.get("keep_alive", 0)) == -1 and body.get("messages") is Array,
			"the body is model, think false, stream false, format json, keep_alive -1, messages")
	_check(body is Dictionary and not body.has("temperature") and not ("/no_think" in str(body["messages"][0]["content"])),
			"with nothing else, and no /no_think in the prompt")

	pet.mind = ScriptedMind.new()
	pet.give_order("follow")
	World.step()
	pet.mind = mind
	# What /api/chat sends back: the answer in message.content.
	mind.stub_next_reply(JSON.stringify({
		"model": "stub", "created_at": "2026-10-06T00:00:00Z", "done": true, "done_reason": "stop",
		"message": {"role": "assistant", "content": "{\"intent\": \"HOLD\", \"target\": null, \"say\": \"\"}"},
	}))
	pet.request_decision("test")
	World.step()
	World.step()
	_check(mind.last_error.is_empty() and pet.current_intent == Companion.Intent.HOLD and pet.last_mind == "ollama",
			"a native reply is read from message.content and applied (%s by %s%s)" % [
				pet.intent_name(), pet.last_mind, ", " + mind.last_error if not mind.last_error.is_empty() else ""])

	# The same body on an OpenAI-style URL is not what that endpoint returns.
	var openai := OllamaMind.new("http://127.0.0.1:11434/v1/chat/completions", "stub", _main)
	_check(openai.openai_shaped, "a URL ending in /chat/completions is spoken to OpenAI-style")
	var openai_body: Variant = JSON.parse_string(openai.request_body({"hp": 1}))
	_check(openai_body is Dictionary and not openai_body.has("format") and not openai_body.has("keep_alive")
			and openai_body.get("think") == false, "its body has no format or keep_alive, and still think false")
	pet.mind = ScriptedMind.new()


func _test_old_record_gets_a_companion() -> void:
	print("\n== a returning player whose record predates companions gets one ==")
	# A snapshot as an older server wrote it: a player record, no companion.
	Net.state_path = OS.get_user_data_dir().path_join("companion_test_old_world.json")
	var file := FileAccess.open(Net.state_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "tick": 0, "entities": [], "respawns": [], "players": [{
		"player_id": Net.player_id, "index": 1, "name": "Talos", "tile": [11, 2], "hp": 20, "stamina": 100,
		"facing": [0, 1], "color": "59a6ff", "last_seen": 0,
	}]}))
	file.close()
	_main._start_level(true)
	var record: PlayerRecord = _main._records.get(Net.player_id)
	var pet := _companion()
	_check(record != null and _player() != null and _player().tile == Vector2i(11, 2), "the old record was loaded and its player is back")
	_check(pet != null and pet.keeper == _player(), "a companion was created for it and follows")
	_check(record != null and record.companion.get("name") is String and record.companion.get("alive") == true,
			"and is now in the record (%s)" % [record.companion.get("name") if record else ""])

	# A companion that died stays dead: the owner coming back does not bring it back.
	World.damage(pet, 999)
	_main._on_peer_disconnected(Net.local_id)
	_main._join_player(Net.local_id, Net.player_id, Net.player_name)
	_check(_companion() == null and record.companion.get("alive") == false, "a dead companion stays dead when the owner returns")

	# Rebuilding the room (console 'reset', R on a host) is what brings it back.
	_main.admin_command("reset")
	pet = _companion()
	_check(pet != null and pet.keeper == _player() and pet.hp == pet.max_hp, "'reset' brings it back at full hp, with its owner")
	_check(pet != null and World.distance(pet.tile, _player().tile) == 1 and record.companion.get("alive") == true,
			"beside the owner, and alive in the record again")

	# The owner was last seen among the imps' spawn tiles: a rebuilt room puts
	# the owner on a safe start tile, and the companion must come too.
	_kill_monsters()
	_walk_to(_player(), Vector2i(4, 6))
	var last_seen: Vector2i = _player().tile
	World.damage(_companion(), 999)
	_check(_companion() == null and record.companion.get("alive") == false, "it dies again, with its owner at %s" % last_seen)
	var reply: String = _main.admin_command("reset")
	_check("companions brought back: %s" % record.companion["name"] in reply, "'reset' says who it brought back (%s)" % reply)
	pet = _companion()
	_check(_player().tile in _main.PLAYER_STARTS and _player().tile != last_seen, "the owner is put on a start tile, away from the imps (at %s)" % _player().tile)
	_check(pet != null and World.distance(pet.tile, _player().tile) == 1, "and the companion is beside the owner, not left by the imps (at %s)" % [pet.tile if pet else Vector2i(-1, -1)])
	reply = _main.admin_command("reset")
	_check("no dead companions" in reply, "a reset with none dead says so (%s)" % reply)

	# A living companion left near monsters also returns beside its owner.
	_main._on_peer_disconnected(Net.local_id)
	record.companion["tile"] = [3, 6]
	World.despawn(_companion())
	record.companion["alive"] = true
	_main._companions.clear()
	_main._join_player(Net.local_id, Net.player_id, Net.player_name)
	pet = _companion()
	_check(pet != null and World.distance(pet.tile, _player().tile) == 1, "a companion saved next to an imp comes back beside its owner instead (at %s)" % [pet.tile if pet else Vector2i(-1, -1)])
	DirAccess.remove_absolute(Net.state_path)
	Net.state_path = ""


func _test_yields_when_bumped() -> void:
	print("\n== walking into her: she steps out of the way at once ==")
	_kill_monsters()
	var owner := _player()
	var pet := _companion()
	pet.mind = ScriptedMind.new()
	_settle(pet)
	_put(owner, Vector2i(9, 6))
	_put(pet, Vector2i(10, 6))
	var log_size: int = _main.party_log.size()
	World.order_step(owner, Vector2i(1, 0), owner.refusals, false)
	World.step()
	_check(owner.tile == Vector2i(9, 6), "the step into her is refused")
	_check(pet.current_intent == Companion.Intent.YIELD and pet.last_mind == "scripted",
			"the scripted mind answers YIELD on the spot (%s by %s)" % [pet.intent_name(), pet.last_mind])
	_check(_main.party_log.size() > log_size and "bumped into %s" % pet.name in _main.party_log.last(1)[0],
			"the bump is in the party log (%s)" % [_main.party_log.last(1)])
	for i in 4:
		World.step()
	var line: Array[Vector2i] = [Vector2i(10, 6), Vector2i(11, 6), Vector2i(12, 6)]
	_check(pet.tile not in line and World.distance(pet.tile, Vector2i(10, 6)) == 1,
			"she is one step off the owner's line (at %s)" % pet.tile)
	World.order_step(owner, Vector2i(1, 0), owner.refusals, false)
	World.step()
	_check(owner.tile == Vector2i(10, 6), "and the owner walks on through (%s)" % owner.tile)


func _test_says_so_with_no_room() -> void:
	print("\n== bumped in the dead end, with nowhere to go: she stays and says so ==")
	var owner := _player()
	var pet := _companion()
	_settle(pet)
	_put(pet, Vector2i(1, 8))
	_put(owner, Vector2i(2, 8))
	var heard: Array[String] = []
	var listen := func(text: String) -> void: heard.append(text)
	pet.said.connect(listen)
	World.order_step(owner, Vector2i(-1, 0), owner.refusals, false)
	World.step()
	pet.said.disconnect(listen)
	_check(pet.current_intent == Companion.Intent.YIELD and pet.tile == Vector2i(1, 8),
			"YIELD, staying put (%s at %s)" % [pet.intent_name(), pet.tile])
	_check(heard.size() == 1 and heard[0] == Companion.NO_ROOM_LINE, "and says there is no room (%s)" % [heard])


func _test_slow_mind_gets_the_scripted_yield() -> void:
	print("\n== a mind that has not yielded within a decision window: the scripted yield ==")
	var owner := _player()
	var pet := _companion()
	_settle(pet)
	_put(owner, Vector2i(9, 6))
	_put(pet, Vector2i(10, 6))
	# An endpoint nobody answers on: the reply never comes in time.
	pet.mind = OllamaMind.new("http://10.255.255.1:9/api/chat", "stub", _main)
	var bumped_at := World.tick + 1
	World.order_step(owner, Vector2i(1, 0), owner.refusals, false)
	World.step()
	_check(pet.current_intent != Companion.Intent.YIELD, "no yield yet: the mind is still thinking (%s)" % pet.intent_name())
	_step_until(func() -> bool: return pet.current_intent == Companion.Intent.YIELD, Companion.DECISION_INTERVAL_TICKS + 2)
	_check(pet.current_intent == Companion.Intent.YIELD and pet.last_mind == "scripted",
			"YIELD by the scripted mind (%s by %s)" % [pet.intent_name(), pet.last_mind])
	_check(World.tick - bumped_at == Companion.DECISION_INTERVAL_TICKS,
			"one decision window after the bump (%d ticks)" % (World.tick - bumped_at))
	pet.mind = ScriptedMind.new()


# --- helpers ------------------------------------------------------------------

## Lets a yield window and a bump's repeat guard run out, then has her
## follow, so the next bump is a fresh one.
func _settle(pet: Companion) -> void:
	for i in Companion.BUMP_REPEAT_TICKS + Companion.DECISION_INTERVAL_TICKS + 1:
		World.step()
	pet.current_intent = Companion.Intent.FOLLOW
	pet.intent_target = null
	pet.hp = pet.max_hp


## Moves [param entity] to [param tile] (a test's set-up, not a move).
func _put(entity: GridEntity, tile: Vector2i) -> void:
	if entity.tile == tile:
		return
	var occupant := World.get_entity_at(tile)
	if occupant != null:
		var aside: Vector2i = _main._nearest_free(tile + Vector2i(0, 2))
		World._relocate(occupant, aside)
	World._relocate(entity, tile)
	if entity is Player:
		entity.queued_steps.clear()
		entity.has_move_order = false

func _player() -> Player:
	for entity in World.get_entities():
		if entity is Player and entity.spawned:
			return entity
	return null


func _companion() -> Companion:
	for entity in World.get_entities():
		if entity is Companion and entity.spawned:
			return entity
	return null


func _spawn_imp(tile: Vector2i) -> Monster:
	var imp := _main._spawn({"script": "res://sim/monster.gd", "shape": "capsule",
		"name": "TestImp%d" % World.tick, "tile": tile}) as Monster
	imp.sight_range = 0
	return imp


func _kill_monsters() -> void:
	for entity in World.get_entities():
		if entity is Monster:
			World.damage(entity, 999)


func _walk_to(entity: GridEntity, tile: Vector2i) -> void:
	World.order_move(entity, tile)
	for i in 120:
		if entity.tile == tile:
			return
		World.step()


func _step_until(condition: Callable, limit: int) -> void:
	for i in limit:
		if condition.call():
			return
		World.step()


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
