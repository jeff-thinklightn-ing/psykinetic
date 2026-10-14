extends Node
## What each client is sent (net/interest.gd, decision 217): on a big map
## made in code, a second player (a peer of its own, as map_bench's) is sent
## what is round it and not what is far; a chunk comes in within 36 cells
## or so and goes only beyond 44; its companion it always sees; doors as
## entities; moving players and things change it; a zone rebuilt keeps it.
## The filters are what the spawner asks, so their answers are what a
## client gets. Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL
## per assertion and quits with exit code 1 if any assertion failed.

const MAP := "interest_big"
const SIZE := 120
const FAR_PEER := 1000

var _failures := 0
var _main: Node


func _ready() -> void:
	World.set_process(false)
	Net.port = preload("res://tests/test_ports.gd").of(17830)
	Net.companions = false
	_register_map()
	Net.map_name = MAP
	_main = preload("res://main.tscn").instantiate()
	add_child(_main)
	_main._admit(FAR_PEER, "11111111-0000-4000-8000-000000001000", "Far")

	_test_near_and_far()
	_test_moving()
	_test_rebuild()

	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## SIZE x SIZE cells of floor, starts at (5, 5), a crate every 10 cells
## from (10, 10), a door between (20, 5) and (21, 5) and one between
## (100, 100) and (101, 100).
func _register_map() -> void:
	var rows: Array[String] = []
	for y in 2 * SIZE - 1:
		rows.append(".".repeat(2 * SIZE - 1))
	rows[10] = rows[10].substr(0, 41) + "+" + rows[10].substr(42)
	rows[200] = rows[200].substr(0, 201) + "+" + rows[200].substr(202)
	var markers := {Vector2i(5, 5): "start", Vector2i(6, 5): "start"}
	for y in range(10, SIZE, 10):
		for x in range(10, SIZE, 10):
			markers[Vector2i(x, y)] = "crate"
	Level.register(MAP, Level.image_from_rows(rows, markers), null, {})


func _far_player() -> Player:
	return _main._players.get(FAR_PEER)


## The crate standing on [param cell], or null.
func _crate(cell: Vector2i) -> GridEntity:
	for entity in World.get_entities():
		if entity.tile == cell and not entity is Player:
			return entity
	return null


func _sees(node: Object) -> bool:
	if node is Door:
		return World.peer_sees(FAR_PEER, node.zone) and Net.interest.sees(FAR_PEER, node)
	return node._visible_to(FAR_PEER)


func _test_near_and_far() -> void:
	print("\n== near and far ==")
	var player := _far_player()
	_check(player != null and player.tile.distance_to(Vector2i(5, 5)) <= 2, "the far peer's player joined at the start (%s)" % [player.tile if player else "none"])
	_check(_sees(player), "it is sent its own player")
	_check(_sees(_crate(Vector2i(10, 10))) and _sees(_crate(Vector2i(30, 30))), "and the crates within 36 cells or so: (10, 10), (30, 30)")
	_check(not _sees(_crate(Vector2i(50, 50))) and not _sees(_crate(Vector2i(110, 110))), "not those beyond: (50, 50), (110, 110)")
	_check(_sees(World.door_on(Vector3i(20, 5, Terrain.EAST))) and not _sees(World.door_on(Vector3i(100, 100, Terrain.EAST))),
		"a door near is sent, a door far is not")
	var count := Net.interest.count_seen(FAR_PEER, MAP)
	_check(count > 0 and count < 40, "%d of the map's %d things are sent to it" % [count, World.get_entities().size() + 2])
	var host_player: Player = _main._players.get(Net.local_id)
	_check(host_player != null and not _sees(host_player) == false, "the host's player beside it is sent too")


func _test_moving() -> void:
	print("\n== moving ==")
	var player := _far_player()
	World._relocate(player, Vector2i(60, 60))
	_check(_sees(_crate(Vector2i(50, 50))) and _sees(_crate(Vector2i(90, 90))), "walked to (60, 60): the crates round it now, (50, 50) to (90, 90)")
	_check(not _sees(_crate(Vector2i(10, 10))), "and the one at (10, 10), 50 away, is no longer sent")
	var host_player: Player = _main._players.get(Net.local_id)
	_check(not _sees(host_player), "nor the host's player back at the start")
	# Hysteresis: the crate at (20, 60) is in chunk (2, 7); from chunk 6
	# (x 48-55) it is 4 chunks off and comes in, from chunk 7 (x 56-63) it is
	# 5 off and stays, from chunk 8 (x 64-71) it is 6 off and goes.
	var edge := _crate(Vector2i(20, 60))
	World._relocate(player, Vector2i(52, 60))
	var came := _sees(edge)
	World._relocate(player, Vector2i(60, 60))
	_check(came and _sees(edge), "a crate 4 chunks off comes in, and stays at 5 chunks: no flicker at the edge")
	World._relocate(player, Vector2i(68, 60))
	_check(not _sees(edge), "and goes at 6 chunks (beyond 44 cells)")
	World._relocate(player, Vector2i(60, 60))
	_check(not _sees(edge), "coming back to 5 chunks does not bring it back (only 4 does)")
	var crate := _crate(Vector2i(70, 70))
	World._relocate(crate, Vector2i(110, 110))
	_check(not _sees(crate), "a crate carried far off is no longer sent")
	World._relocate(crate, Vector2i(71, 71))
	_check(_sees(crate), "and is sent again when it comes back near")


func _test_rebuild() -> void:
	print("\n== the zone rebuilt (a builder change accepted) ==")
	var player := _far_player()
	World._relocate(player, Vector2i(60, 60))
	_main.reload_zone(MAP)
	var again := _far_player()
	_check(again != null and _sees(_crate(Vector2i(60, 60))) and not _sees(_crate(Vector2i(10, 10))),
		"rebuilt: the far peer is sent what is round its player again, and not the rest (%s)" % [again.tile if again else "none"])
	_check(Net.interest.count_seen(FAR_PEER, MAP) < World.get_entities().size() / 2, "still what is round it, not the map (%d of %d)" % [
		Net.interest.count_seen(FAR_PEER, MAP), World.get_entities().size()])


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
