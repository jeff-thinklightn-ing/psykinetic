extends Node
## Zones: many maps live at once. Two players, one takes a link and the
## other stays; each is sent only their own zone; a companion follows its
## player across; an empty zone sleeps and wakes; a restart puts both back in
## their own zones; the console's zones, zone reset and zone move.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion
## and quits with exit code 1 if any assertion failed, 0 otherwise.

const BO := 2
const BO_ID := "b0b0b0b0-0000-4000-8000-0000000000b0"

var _failures := 0
var _main: Node


func _ready() -> void:
	World.set_process(false)
	Net.port = 17792
	Net.companions = true
	Net.state_path = OS.get_user_data_dir().path_join("zone_test_world.json")
	if FileAccess.file_exists(Net.state_path):
		DirAccess.remove_absolute(Net.state_path)
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	for i in 3:
		World.step()

	await _test_one_takes_a_link()
	_test_each_sees_their_own()
	_test_companion_follows()
	_test_empty_zone_sleeps()
	await _test_restart()
	_test_console()
	_test_speech_by_zone()
	_test_overheard()

	DirAccess.remove_absolute(Net.state_path)
	Net.state_path = ""
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_one_takes_a_link() -> void:
	print("\n== two players: one takes the link, the other stays ==")
	_main._admit(BO, BO_ID, "Bo")
	var host := _player(Net.local_id)
	var bo := _player(BO)
	_check(host != null and bo != null and host.zone == "test_room" and bo.zone == "test_room",
		"both start in the test room (%s, %s)" % [host.zone if host else "-", bo.zone if bo else "-"])
	_check(World.zones.keys() == ["test_room"], "only the test room is loaded (%s)" % [World.zones.keys()])
	var host_tile := host.tile
	World._relocate(bo, Vector2i(2, 1))
	for i in 6:
		World.step()
	_check(World.try_move(bo, Vector2i(-1, 0)), "Bo steps onto the link at (1, 1)")
	await get_tree().process_frame
	await get_tree().process_frame
	var moved := _player(BO)
	_check(World.zones.has("sample"), "the sample zone is loaded on its first visit")
	_check(moved != null and moved.zone == "sample" and _main._records[BO_ID].zone == "sample",
		"Bo is in the sample zone, and his record says so")
	var starts: Array = Level.load_level("sample")["starts"]
	_check(moved != null and (World.distance(moved.tile, Vector2i(13, 5)) <= 1 or moved.tile in starts),
		"at its spawn point, path_end, or (a brute is near it) a safe start (%s)" % [moved.tile if moved else "-"])
	var still := _player(Net.local_id)
	_check(still == host and still.zone == "test_room" and still.tile == host_tile, "the host did not move: %s at %s" % [still.zone, still.tile])
	_check(World.zone.name == "test_room" and _main.map_name == "test_room", "and the host's view is still the test room")


func _test_each_sees_their_own() -> void:
	print("\n== each is sent only their own zone ==")
	var leaks: Array[String] = []
	for each: Zone in World.zones.values():
		var was := World.enter(each)
		for entity in World.get_entities():
			var for_bo: bool = entity._visible_to(BO)
			var for_host: bool = entity._visible_to(Net.local_id)
			if for_bo != (each.name == "sample") or for_host != (each.name == "test_room"):
				leaks.append("%s in %s" % [entity.name, each.name])
		for door: Door in World.get_doors():
			if World.peer_sees(BO, door.zone) != (each.name == "sample"):
				leaks.append("%s in %s" % [door.name, each.name])
		World.enter(was)
	_check(leaks.is_empty(), "every entity and door is visible to the players in its zone and no one else %s" % [leaks])
	_main._show_home_zone()
	var room: Node2D = _main.get_node("YSort/Entities/test_room")
	var sample: Node2D = _main.get_node("YSort/Entities/sample")
	_check(room.visible and not sample.visible, "the host draws the test room, not the sample")
	_check(str(World.peers_in("sample")) == str([BO]) and Net.local_id in World.peers_in("test_room"), "peers by zone")
	var names: Array[String] = []
	for entity in World.get_entities():
		names.append(String(entity.name))
	_check("Sneak" not in names and "Player2" not in names, "the test room's World has none of the sample's (%s)" % ", ".join(names))


func _test_companion_follows() -> void:
	print("\n== a companion follows her player across ==")
	var bo := _player(BO)
	var pet: Companion = _main._companions.get(BO_ID)
	_check(pet != null and pet.zone == "sample" and pet.keeper == bo, "Bo's companion is in the sample, his (%s)" % [pet.name if pet else "none"])
	_check(pet != null and World.distance(pet.tile, bo.tile) <= 2, "beside him (%s, he is at %s)" % [pet.tile if pet else "-", bo.tile])
	var left_behind := 0
	for entity in World.get_entities():
		if entity is Companion and (entity as Companion).keeper_id == BO_ID:
			left_behind += 1
	_check(left_behind == 0, "and not in the test room any more")
	var host_pet: Companion = _main._companions.get(Net.player_id)
	_check(host_pet != null and host_pet.zone == "test_room", "the host's companion stayed with the host")


func _test_empty_zone_sleeps() -> void:
	print("\n== an empty zone sleeps, and wakes when someone arrives ==")
	_check(_main.travel(BO, "test_room", "from_sample"), "Bo goes back to the test room")
	var sample: Zone = World.zones["sample"]
	World.step()
	var asleep_at := sample.tick
	var monster: GridEntity = null
	for entity in sample.entities:
		if entity is Monster:
			monster = entity
	var monster_at: Vector2i = monster.tile if monster != null else Vector2i.ZERO
	var room_tick := World.tick
	for i in 20:
		World.step()
	_check(not sample.awake and sample.tick == asleep_at, "the sample, empty, does not tick (tick %d, was %d)" % [sample.tick, asleep_at])
	_check(monster == null or monster.tile == monster_at, "its monsters stand frozen")
	_check(World.tick == room_tick + 20, "while the test room goes on (%d -> %d)" % [room_tick, World.tick])
	_check(_main.travel(BO, "sample"), "Bo goes to the sample again")
	World.step()
	World.step()
	_check(sample.awake and sample.tick == asleep_at + 2, "it wakes and ticks again (%d)" % sample.tick)


func _test_restart() -> void:
	print("\n== a restart puts both players back in their own zones ==")
	_main._save_state()
	var snapshot := Snapshot.load(Net.state_path)
	var zones: Dictionary = snapshot["zones"]
	_check(snapshot["ok"] and zones.has("test_room") and zones.has("sample"), "the snapshot holds both zones (%s)" % [zones.keys()])
	var where := {}
	for record: PlayerRecord in snapshot["players"]:
		where[record.name] = record.zone
	_check(where.get("Bo") == "sample" and where.get(Net.player_name) == "test_room", "and each player's zone (%s)" % [where])
	var sample_entities := (zones["sample"]["entities"] as Array).size()
	# The server stops and starts again.
	remove_child(_main)
	_main.free()
	World.clear_zones()
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	_check(World.zones.has("test_room") and World.zones.has("sample"), "both zones come back (%s)" % [World.zones.keys()])
	_check(World.zones["sample"].entities.size() >= sample_entities, "the sample as it was saved (%d entities)" % World.zones["sample"].entities.size())
	var host := _player(Net.local_id)
	_check(host != null and host.zone == "test_room", "the host is back in the test room")
	_main._admit(BO, BO_ID, "Bo")
	var bo := _player(BO)
	_check(bo != null and bo.zone == "sample", "Bo comes back in the sample (%s)" % [bo.zone if bo else "-"])


func _test_console() -> void:
	print("\n== the console: zones, zone reset, zone move ==")
	var listed: String = _main.admin_command("zones")
	_check(listed.begins_with("2 zones") and "test_room: awake" in listed and "sample: awake" in listed and "Bo" in listed,
		"zones lists the zones and who is in each:\n%s" % listed)
	_check(_main.admin_command("zone reset nowhere").begins_with("no map nowhere"), "an unknown map is refused")
	var reply: String = _main.admin_command("zone reset sample")
	_check(reply.begins_with("zone sample rebuilt") and _player(BO) != null and _player(BO).zone == "sample",
		"zone reset sample rebuilds it, Bo still there: %s" % reply)
	_check(World.zone.name == "test_room", "and the console is back in the host's zone")
	reply = _main.admin_command("zone move bo test_room")
	_check(reply == "Bo moved to test_room" and _player(BO).zone == "test_room", "zone move bo test_room: %s" % reply)
	_check(_main.admin_command("zone move nobody sample") == "no player nobody online", "an unknown player is refused")


func _test_speech_by_zone() -> void:
	print("\n== speech stays in its zone and earshot; party chat crosses, unheard by companions ==")
	_main.travel(BO, "sample")
	var heard: Array[Dictionary] = []
	var listen := func(kind: String, data: Dictionary) -> void: heard.append({"kind": kind, "data": data})
	Net.message_received.connect(listen)
	var host := _player(Net.local_id)
	var bo := _player(BO)
	var host_pet: Companion = _main._companions.get(Net.player_id)
	var bo_pet: Companion = _main._companions.get(BO_ID)
	_main._chat_tick.clear()
	var was := World.enter_named("sample")
	_main._player_said(bo, "Anyone there?")
	var in_sample: Array[int] = _main.hearers(bo.tile)
	var sample_log: PartyLog = _main.party_log
	World.enter(was)
	_check(_kinds(heard, "chat").is_empty() and BO in in_sample and Net.local_id not in in_sample,
		"Bo speaks in the sample: he is heard there, not by the host in the test room (%s)" % [in_sample])
	_check(sample_log != _main.party_log and _logged(sample_log, "Anyone there?") and not _logged(_main.party_log, "Anyone there?"),
		"it is in the sample's party log, not the test room's")
	_check(bo_pet != null and _heard(bo_pet, "Anyone there?") and not _heard(host_pet, "Anyone there?"),
		"his companion, beside him, hears it; the host's does not")
	heard.clear()
	_main._chat_tick.clear()
	_main._player_said(host, "Hello?")
	_check(_kinds(heard, "chat").size() == 1 and BO not in _main.hearers(host.tile), "the host speaks: heard in the test room, not in the sample")
	# Earshot, in one zone.
	_main.travel(BO, "test_room")
	bo = _player(BO)
	var far := host.tile
	for cell: Vector2i in _main._terrain["floor"]:
		if World.is_free(cell) and World.distance(host.tile, cell) > _main.HEARING_RANGE:
			far = cell
			break
	World._relocate(bo, far)
	_check(BO not in _main.hearers(host.tile), "the same zone, %d cells off: out of earshot" % World.distance(host.tile, bo.tile))
	World._relocate(bo, _main._nearest_free(host.tile + Vector2i(0, 2)))
	_check(BO in _main.hearers(host.tile), "%d cells off: heard" % World.distance(host.tile, bo.tile))
	# Party chat crosses zones; no companion hears it.
	_main.travel(BO, "sample")
	bo = _player(BO)
	heard.clear()
	_main._chat_tick.clear()
	was = World.enter_named("sample")
	_main._party_said(bo, "Regroup at the door")
	var sample_log_after: PartyLog = _main.party_log
	World.enter(was)
	var party := _kinds(heard, "party")
	_check(party.size() == 1 and party[0]["text"] == "Regroup at the door" and party[0]["from"] == "Bo",
		"Bo's party chat, from the sample, reaches the host in the test room (%s)" % [party])
	_check(not _heard(host_pet, "Regroup") and not _heard(bo_pet, "Regroup")
		and not _logged(_main.party_log, "Regroup") and not _logged(sample_log_after, "Regroup"),
		"no companion hears it, and no party log has it")
	heard.clear()
	_main._chat_tick.clear()
	_main._chat_sent_at = -100000
	_main._send_chat("/p on my way")
	_check(_kinds(heard, "party").size() == 1 and _kinds(heard, "chat").is_empty(), "/p in the chat box is party chat")
	var shown: Array = _main.talk.lines.back()
	_check(shown[1] == Net.player_name and shown[2] == "on my way", "and the talk panel shows it (%s)" % [shown])
	Net.message_received.disconnect(listen)


func _test_overheard() -> void:
	print("\n== companions hear everyone near; who else is here; a line not for her, a line for her ==")
	_main.travel(BO, "test_room")
	var host := _player(Net.local_id)
	var bo := _player(BO)
	World._relocate(bo, _main._nearest_free(host.tile + Vector2i(0, 2)))
	var pip: Companion = _main._companions.get(Net.player_id)
	var nix: Companion = _main._companions.get(BO_ID)
	for pet in [pip, nix]:
		World._relocate(pet, _main._nearest_free(host.tile + Vector2i(1, 1)))
	var pip_mind := StubMind.new()
	var nix_mind := StubMind.new()
	pip.mind = pip_mind
	nix.mind = nix_mind
	for pet in [pip, nix]:
		pet._exchange.clear()
		pet._said.clear()
		pet._last_speech_tick = -1000
	var others := pip.others_here()
	_check("Bo is " in others and "near enough to hear" in others and ("%s, who travels with Bo," % nix.label) in others,
		"Pip's prompt says who else is here, where, and who can hear: %s" % others)
	_check(pip.others_here() in pip.voice_prompt("test"), "it is in her voice's now")
	# A line to Bo: Pip hears it as her player's, Nix as Jeff's; neither is told it is for them.
	pip_mind.voice_answer = {"say": "...", "stance": "PRESS"}
	nix_mind.voice_answer = {"say": "...", "stance": "PRESS"}
	_main._chat_tick.clear()
	_main._player_said(host, "Bo, take the left side.")
	var pip_ask: Dictionary = pip_mind.voice_asks.back() if not pip_mind.voice_asks.is_empty() else {}
	var nix_ask: Dictionary = nix_mind.voice_asks.back() if not nix_mind.voice_asks.is_empty() else {}
	var pip_text := Companion.render(pip_ask.get("messages", []))
	var nix_text := Companion.render(nix_ask.get("messages", []))
	_check(pip_text.ends_with("%s: Bo, take the left side." % Net.player_name) and nix_text.ends_with("%s: Bo, take the left side." % Net.player_name),
		"both companions get the line, labelled with who said it")
	_check("Not everything said near you is meant for you" in pip_text and "Bo is " in pip_text,
		"Pip is told a line may not be for her, and that Bo is there to be spoken to")
	_check(MindLog.last[String(pip.name)].get("outcome") == "silent" and pip._said.is_empty() and pip.stance != Companion.Stance.PRESS
			and MindLog.last[String(pip.name)].get("stance_ignored") == "PRESS",
		"meant for Bo: she answers \"...\", says nothing, and the stance with it is not taken (%s)" % MindLog.last[String(pip.name)].get("note", ""))
	_check(not "[STANCE:" in str(nix_ask.get("system", "")) and nix.stance != Companion.Stance.PRESS,
		"Nix: someone else's player's words never set her stance, nor is she offered one")
	# A line to her: she answers.
	pip_mind.voice_answer = {"say": "Right here, Jeff.", "stance": ""}
	nix_mind.voice_answer = {"say": "...", "stance": ""}
	_main._chat_tick.clear()
	_main._player_said(host, "%s, stay with me." % pip.name)
	_check(pip._said.back() == "Right here, Jeff." if not pip._said.is_empty() else false, "a line to Pip by name: she answers (%s)" % [pip._said])
	_check(MindLog.last[String(nix.name)].get("outcome") == "silent", "and Nix, not named, keeps quiet")
	_check("%s: Right here, Jeff." % pip.name in Companion.render(nix.voice_messages()), "Nix heard Pip's answer too, labelled")
	_check(nix_mind.voice_asks.size() == 2, "a companion's words are no ask for another (only the two lines of Jeff's)")
	# The fallen hear, but cannot speak.
	World.damage(bo, 999)
	_check(_player(BO) == null and BO in _main.hearers(host.tile), "Bo, fallen, still hears what is said near where he fell")
	for pet in [pip, nix]:
		pet.mind = ScriptedMind.new()


# --- Helpers ---------------------------------------------------------------------

func _kinds(heard: Array[Dictionary], kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for message in heard:
		if message["kind"] == kind:
			out.append(message["data"])
	return out


func _logged(log: PartyLog, text: String) -> bool:
	return log != null and text in "\n".join(log.last(40))


func _heard(pet: Companion, text: String) -> bool:
	if pet == null:
		return false
	for heard: Dictionary in pet._heard:
		if text in str(heard["text"]):
			return true
	return false

## [param peer]'s player wherever it is.
func _player(peer: int) -> Player:
	var player: Player = _main._players.get(peer)
	return player if is_instance_valid(player) and player.spawned else null


## A mind that answers at once with what it is set to, keeping its asks.
class StubMind:
	extends CompanionMind

	var voice_asks: Array[Dictionary] = []
	var voice_answer := {"say": "", "stance": ""}

	func _init() -> void:
		kind = "stub"

	func stance(_ask: Dictionary) -> Dictionary:
		return {"stance": "GUARD"}

	func voice(ask: Dictionary) -> Dictionary:
		voice_asks.append(ask)
		return OllamaMind.parse_voice(str(voice_answer["say"]) + ("\n[STANCE: %s]" % voice_answer["stance"] if voice_answer["stance"] != "" else ""))


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
