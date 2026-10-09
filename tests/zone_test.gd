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


# --- Helpers ---------------------------------------------------------------------

## [param peer]'s player wherever it is.
func _player(peer: int) -> Player:
	var player: Player = _main._players.get(peer)
	return player if is_instance_valid(player) and player.spawned else null


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
