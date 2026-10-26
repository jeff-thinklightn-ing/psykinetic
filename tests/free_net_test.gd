extends Node
## Free movement's wire (decision 689; physics' free body, 688): the
## commands and the state packed and read back, what the server takes from
## a client (its own body only, the right shape, each seq once, at most
## World.FREE_COMMANDS_PER_SECOND, an intent at most a unit long, the bank
## the only speed), and the own body's view by replay (FreeNet.Own) agreeing
## with the server under lag and loss. World stepped by hand, a frame a
## sixtieth of a second, a tick every six.

const FreeNet := preload("res://net/free_net.gd")

const OPEN: Array[String] = [
	". . . . . . . . . . . .",
	"                       ",
	". . . . . . . . . . . .",
	"                       ",
	". . . . . . . . . . . .",
	"                       ",
	". . . . . . . . . . . .",
	"                       ",
	". . . . . . . . . . . .",
]
## A wall along the south edges of (2, 1) to (5, 1).
const WALLED: Array[String] = [
	". . . . . . . . .",
	"                 ",
	". . . . . . . . .",
	"    # # # #      ",
	". . . . . . . . .",
	"                 ",
	". . . . . . . . .",
]
const FRAME := 1.0 / 60.0

var _failures := 0
var _room: Node2D
var _frame := 0


func _ready() -> void:
	World.set_process(false)
	_test_packing()
	_test_hostile()
	_test_allowance()
	_test_bank()
	_test_own_view()
	_test_lag_and_loss()
	_test_lag_across_fords()
	_test_kick_under_lag()
	_test_companion_on_a_client()
	_test_switch()
	World.free_walk = false
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_packing() -> void:
	print("\n== the wire: commands and state packed and read back ==")
	var commands: Array[Dictionary] = [
		{"seq": 65535, "intent": Vector2(1, 0), "ticks": 0.33},
		{"seq": 0, "intent": FreeNet.quantise(Vector2(-0.6, 0.8)), "ticks": 0.5}]
	var back := FreeNet.unpack_commands(FreeNet.pack_commands(commands))
	_check(back.size() == 2 and int(back[0]["seq"]) == 65535 and int(back[1]["seq"]) == 0, "seqs kept, wrapping")
	_check((back[1]["intent"] as Vector2).distance_to(commands[1]["intent"]) < 0.01, "the intent kept to 1/127")
	_check(absf(float(back[0]["ticks"]) - 0.33) < 0.011, "its time kept to a millisecond (%.3f ticks)" % back[0]["ticks"])
	_check(FreeNet.seq_after(0, 65535) and FreeNet.seq_after(5, 1) and not FreeNet.seq_after(1, 5) and not FreeNet.seq_after(3, 3),
			"seq order wraps at 65536")
	var odd := FreeNet.pack_commands(commands)
	odd.resize(odd.size() - 1)
	_check(FreeNet.unpack_commands(odd).is_empty(), "a packet of the wrong size is nothing")
	var many: Array[Dictionary] = []
	for i in FreeNet.SEND_REPEAT + 1:
		many.append({"seq": i, "intent": Vector2.RIGHT, "ticks": 0.3})
	_check(FreeNet.unpack_commands(FreeNet.pack_commands(many)).is_empty(), "more than %d commands in a packet is nothing" % FreeNet.SEND_REPEAT)
	var raw := PackedByteArray([1, 0, 127, 127, 30])
	var long: Vector2 = FreeNet.unpack_commands(raw)[0]["intent"]
	_check(long.length() <= 1.0001, "an intent read back at most a unit long (%.3f)" % long.length())
	var state := FreeNet.unpack_state(FreeNet.pack_state(Vector2(1234.567, -3.25), 65534, 0.4, 70000, Vector2i(1235, -3)), 70003)
	_check(state["pos"].distance_to(Vector2(1234.567, -3.25)) < 0.001 and int(state["acked"]) == 65534
			and absf(float(state["used"]) - 0.4) < 0.02 and int(state["tick"]) == 70000 and state["held"] == Vector2i(1235, -3), "the state read back: %s" % state)
	_check(FreeNet.unpack_state(PackedByteArray([1, 2, 3]), 0).is_empty(), "a state of the wrong size is nothing")


func _test_hostile() -> void:
	print("\n== what the server takes: its own body, the right shape, each seq once ==")
	var player := _build(OPEN, Vector2i(2, 2))
	var other := _spawn("res://sim/player.gd", "Player2", Vector2i(6, 2)) as Player
	other.owner_peer = 9999
	var one := _packet([[1, Vector2.RIGHT, 30]])
	_check(not World.free_from(Net.local_id, other.get_path(), one), "a command for another's body is refused")
	_check(other.free_inputs.is_empty(), "(and nothing queued on it)")
	_check(not World.free_from(Net.local_id, NodePath("/root/Nobody"), one), "a command for no body is refused")
	_check(not World.free_from(Net.local_id, player.get_path(), PackedByteArray([1, 2, 3])), "a packet of the wrong size is refused")
	_check(World.free_from(Net.local_id, player.get_path(), one), "its own body's command is taken")
	_check(player.free_inputs.size() == 1, "one command queued")
	World.free_from(Net.local_id, player.get_path(), _packet([[1, Vector2.RIGHT, 30], [2, Vector2.RIGHT, 30]]))
	_check(player.free_inputs.size() == 2, "a seq sent again is taken once (%d queued)" % player.free_inputs.size())
	World.free_from(Net.local_id, player.get_path(), _packet([[1, Vector2.RIGHT, 30]]))
	_check(player.free_inputs.size() == 2, "an old seq is nothing")


func _test_allowance() -> void:
	print("\n== at most %d commands a second ==" % World.FREE_COMMANDS_PER_SECOND)
	var player := _build(OPEN, Vector2i(2, 2))
	player.free_allowance_at = Time.get_ticks_msec()
	player.free_allowance = World.FREE_COMMANDS_PER_SECOND
	var taken := 0
	for seq in range(1, 201, 4):
		World.free_from(Net.local_id, player.get_path(), _packet([[seq, Vector2.RIGHT, 1], [seq + 1, Vector2.RIGHT, 1],
			[seq + 2, Vector2.RIGHT, 1], [seq + 3, Vector2.RIGHT, 1]]))
	taken = player.free_inputs.size()
	_check(taken <= int(World.FREE_COMMANDS_PER_SECOND) + 1, "200 at once: %d taken" % taken)
	_check(taken >= int(World.FREE_COMMANDS_PER_SECOND) - 1, "(the allowance itself taken: %d)" % taken)


func _test_bank() -> void:
	print("\n== the bank is the only speed: many long commands move a tick's walk a tick ==")
	var player := _build(OPEN, Vector2i(1, 2))
	var pace := 1.0 / World.step_ticks(player, Vector2i.RIGHT)
	for i in 4:
		World.step()  # The bank full.
	var seq := 1
	for i in 10:
		World.free_from(Net.local_id, player.get_path(), _packet([[seq, Vector2(5, 0), 255]]))
		seq += 1
	var from := player.free_pos
	World.step()
	var went := player.free_pos.x - from.x
	_check(went <= pace * World.FREE_BANK_TICKS + 0.001, "one tick moved %.2f cells, the bank's most %.2f" % [went, pace * World.FREE_BANK_TICKS])
	from = player.free_pos
	World.step()
	_check(player.free_pos.x - from.x <= pace + 0.001, "and the next %.2f, a tick's walk %.2f" % [player.free_pos.x - from.x, pace])


func _test_own_view() -> void:
	print("\n== the own body's view: shown at once, the server's state agreeing ==")
	var player := _build(OPEN, Vector2i(1, 2))
	player.owner_peer = Net.local_id
	var own := FreeNet.Own.new()
	player.free_view = own
	var from := own.shown(player)
	own.hold(player, Vector2.RIGHT, FRAME)
	_check(own.shown(player).x > from.x, "a frame's input shown that frame (%.3f cells)" % (own.shown(player).x - from.x))
	_frames(player, own, Vector2.RIGHT, 60)
	_check(own.corrections == 0, "a second's walk east: no corrections (%d)" % own.corrections)
	var ahead := own.shown(player).x - player.free_pos.x
	_check(ahead >= 0.0 and ahead < 0.6, "the view ahead of the server by what it has not applied (%.2f)" % ahead)
	_frames(player, own, Vector2.ZERO, 30)
	_check(own.shown(player).distance_to(player.free_pos) < 0.01, "let go: the view and the server agree (%s, %s)" % [own.shown(player), player.free_pos])
	_check(own.pending.is_empty(), "every command applied")
	_frames(player, own, Vector2.DOWN, 40)
	_frames(player, own, Vector2.ZERO, 30)
	_check(own.corrections == 0 and own.shown(player).distance_to(player.free_pos) < 0.01, "a turn and a stop: still none (%d)" % own.corrections)
	_frames(player, own, Vector2.LEFT, 4)
	World._relocate(player, Vector2i(8, 4))
	player._world_place(player.id, Vector2i(8, 4))  # A respawn: the server's count starts again.
	player.pack_free()
	_check(own.pending.is_empty() and own.shown(player).distance_to(Vector2(8, 4)) < 0.01,
			"placed again: what was sent before is dropped, the view on its new cell (%s)" % own.shown(player))


func _test_lag_and_loss() -> void:
	print("\n== under lag and loss: the view ends where the server does ==")
	var player := _build(WALLED, Vector2i(1, 2))
	# North-east along the wall's south side, then up past its end.
	var own := _lagged(player, [[Vector2(1, -1).normalized(), 150], [Vector2.UP, 40], [Vector2.ZERO, 80]])
	_check(own.shown(player).distance_to(player.free_pos) < 0.02, "the view ends on the server's centre (%s, %s)" % [own.shown(player), player.free_pos])
	_check(player.free_pos.y < 1.0, "the body slid along the wall and went up past its end (%s)" % player.free_pos)
	_check(own.corrections <= 2, "corrections under a third lost: %d" % own.corrections)


## Across fords (688 amended (3)): the replay carries the server's held cell,
## so a command crossing from slow ground to open goes as the server's did.
func _test_lag_across_fords() -> void:
	print("
== under lag and loss across fords: no corrections ==")
	var player := _build(OPEN, Vector2i(0, 0))
	for x in [1, 3, 5, 7]:
		for y in 5:
			World._fords[Vector2i(x, y)] = true
	var own := _lagged(player, [[Vector2(1, 0.5).normalized(), 90], [Vector2(1, -0.3).normalized(), 60], [Vector2.ZERO, 80]])
	World._fords.clear()
	_check(player.free_pos.x > 4.0, "it crossed the fords (%s)" % player.free_pos)
	_check(own.shown(player).distance_to(player.free_pos) < 0.02 and own.corrections == 0,
			"the view ends on the server's centre, never corrected (%d, %s)" % [own.corrections, own.shown(player)])


## Walks [param player] by [param plan] ([intent, frames]) through an Own,
## 150 ms each way, every third packet lost; returns the Own.
func _lagged(player: Player, plan: Array) -> FreeNet.Own:
	player.owner_peer = 4242  # Not this peer's: its states come to `own` by hand, late.
	var own := FreeNet.Own.new()
	var to_server: Array[Array] = []  # [due frame, commands]
	var to_client: Array[Array] = []  # [due frame, state]
	var lag := 9  # Frames each way: 150 ms.
	var frame := 0
	var sent := 0
	for leg: Array in plan:
		for i in int(leg[1]):
			frame += 1
			var commands := own.hold(player, leg[0], FRAME)
			if not commands.is_empty():
				sent += 1
				if sent % 3 != 0:  # Every third packet lost.
					to_server.append([frame + lag, FreeNet.pack_commands(commands)])
			while not to_server.is_empty() and int(to_server[0][0]) <= frame:
				player.free_allowance = World.FREE_COMMANDS_PER_SECOND  # The test runs faster than the clock.
				World.take_free(player, FreeNet.unpack_commands(to_server.pop_front()[1]))
			if frame % 6 == 0:
				World.step()
				player.pack_free()
				to_client.append([frame + lag, player.free_state.duplicate()])
			while not to_client.is_empty() and int(to_client[0][0]) <= frame:
				own.confirm(player, FreeNet.unpack_state(to_client.pop_front()[1], World.tick))
	return own


## A push on the own body under lag (688 amended (2), physics' with ui): the
## server decides the slide at once and drops what the client had sent, so
## the replay drops it too, and the view ends on the server's centre with
## the walk taken up again after.
func _test_kick_under_lag() -> void:
	print("\n== pushed while walking, under lag and loss: the commands the slide overrode are dropped ==")
	var player := _build(OPEN, Vector2i(3, 2))
	player.owner_peer = 4242
	var pusher := _spawn("res://sim/monster.gd", "Pusher", Vector2i(0, 0)) as Monster
	pusher.acts = false
	pusher.sight_range = 0
	var own := FreeNet.Own.new()
	var to_server: Array[Array] = []
	var to_client: Array[Array] = []
	var lag := 9
	var frame := 0
	var sent := 0
	var pushed_at := Vector2.INF
	var slid_to := Vector2.INF
	var tiles := 0
	# What is drawn from the push on: its moves along x, east (+1) or west
	# (-1), and the times it turns (a rubber band: back with the key held,
	# then with the slide again).
	var drawn_was := Vector2.INF
	var drawn_way := 0
	var turns := 0
	var plan: Array[Array] = [[Vector2.RIGHT, 40], [Vector2.RIGHT, 50], [Vector2.ZERO, 80]]
	for leg in plan:
		for i in int(leg[1]):
			frame += 1
			var commands := own.hold(player, leg[0], FRAME)
			if not commands.is_empty():
				sent += 1
				if sent % 3 != 0:
					to_server.append([frame + lag, FreeNet.pack_commands(commands)])
			while not to_server.is_empty() and int(to_server[0][0]) <= frame:
				player.free_allowance = World.FREE_COMMANDS_PER_SECOND
				World.take_free(player, FreeNet.unpack_commands(to_server.pop_front()[1]))
			if frame == 42:
				pushed_at = player.free_pos
				World._push(pusher, player, Vector2(-1, 0.5), 2.0)
				slid_to = player.free_kick_path[player.free_kick_path.size() - 1]
				tiles = roundi(pushed_at.distance_to(slid_to))
			if frame == 42 + lag:
				own.pushed(tiles)  # The body's `pushed`, as a client hears it.
			if frame % 6 == 0:
				World.step()
				player.pack_free()
				to_client.append([frame + lag, player.free_state.duplicate()])
			while not to_client.is_empty() and int(to_client[0][0]) <= frame:
				own.confirm(player, FreeNet.unpack_state(to_client.pop_front()[1], World.tick))
			if frame >= 42:
				var drawn := own.shown(player)
				if drawn_was != Vector2.INF and absf(drawn.x - drawn_was.x) > 0.002:
					var way := 1 if drawn.x > drawn_was.x else -1
					if drawn_way != 0 and way != drawn_way:
						turns += 1
					drawn_way = way
				drawn_was = drawn
	# The slide west, then east again once let go: a turn, two at most.
	_check(turns <= 2, "drawn: the slide back and the walk on, no rubber band (%d turns)" % turns)
	_check(slid_to.x < pushed_at.x - 1.5, "pushed west-south-west at 2 from %s: slid to %s" % [pushed_at, slid_to])
	_check(player.free_pos.x > slid_to.x + 0.5, "walked east again after the slide (%s)" % player.free_pos)
	_check(own.pending.is_empty() and own.shown(player).distance_to(player.free_pos) < 0.02,
			"the view ends on the server's centre, nothing left to replay (%s, %s)" % [own.shown(player), player.free_pos])


func _test_companion_on_a_client() -> void:
	print("
== the replay passes through its own companion as the server does, her keeper unknown on a client ==")
	var player := _build(OPEN, Vector2i(1, 2))
	var pet := EntityFactory.build({"script": "res://sim/companion.gd", "shape": "capsule", "name": "Garrow", "props": {"max_hp": 10}}) as Companion
	pet.acts = false
	_room.add_child(pet)
	World.spawn(pet, Vector2i(3, 2))
	pet.keeper = null  # As a client has her: only her keeper's peer.
	pet.keeper_peer = player.owner_peer
	var glided: Array = World.free_glide(player, Vector2(1, 2), Vector2.RIGHT, 10.0)
	_check((glided[0] as Vector2).is_equal_approx(Vector2(5, 2)), "10 ticks east through her: at (5, 2) (%s)" % glided[0])
	pet.keeper_peer = player.owner_peer + 1
	glided = World.free_glide(player, Vector2(1, 2), Vector2.RIGHT, 10.0)
	_check((glided[0] as Vector2).x < 2.25, "another's companion stops it (%s)" % glided[0])


func _test_switch() -> void:
	print("\n== the admin's switch: off puts each body on its cell, on starts it there ==")
	var player := _build(OPEN, Vector2i(2, 2))
	for i in 3:
		World.free_input(player, Vector2(1, 0.3), World.TICK_DT)
		World.step()
		player.pack_free()
	_check(not player.free_state.is_empty(), "walking free: its state on the wire")
	World.set_free_walk(false)
	_check(player.free_state.is_empty() and player.free_pos == Vector2(player.tile), "off: on its cell %s, the wire empty" % player.tile)
	_check(World.get_entity_at(player.tile) == player, "(the cell its own)")
	World.set_free_walk(true)
	_check(not player.free_state.is_empty() and player.free_pos == Vector2(player.tile), "on again: from its cell's centre")


## World stepped [param frames] frames with [param own] holding [param intent], a host's way.
func _frames(player: Player, own: FreeNet.Own, intent: Vector2, frames: int) -> void:
	for i in frames:
		var commands := own.hold(player, intent, FRAME)
		if not commands.is_empty():
			player.free_allowance = World.FREE_COMMANDS_PER_SECOND  # The test runs faster than the clock.
			World.take_free(player, commands)
		_frame += 1
		if _frame % 6 == 0:
			World.step()
			player.pack_free()  # Heard by its own view (Player._free_heard).


func _packet(commands: Array) -> PackedByteArray:
	var list: Array[Dictionary] = []
	for each: Array in commands:
		list.append({"seq": each[0], "intent": each[1], "ticks": float(each[2]) / 1000.0 * World.TICK_RATE})
	return FreeNet.pack_commands(list)


func _build(rows: Array[String], at: Vector2i) -> Player:
	World.reset()
	World.free_walk = true
	if _room != null:
		_room.free()
	_room = Node2D.new()
	add_child(_room)
	World.load_terrain(Terrain.parse(rows))
	var player := _spawn("res://sim/player.gd", "Player1", at) as Player
	player.owner_peer = Net.local_id
	player.free_allowance = World.FREE_COMMANDS_PER_SECOND
	player.free_allowance_at = Time.get_ticks_msec()
	return player


func _spawn(script: String, entity_name: String, at: Vector2i) -> GridEntity:
	var entity := EntityFactory.build({"script": script, "shape": "capsule", "name": entity_name, "tile": at})
	_room.add_child(entity)
	World.spawn(entity, at)
	return entity


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1
