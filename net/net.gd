extends Node
## Launch mode and ENet setup (autoload "Net").
##
##   --host                       listen server: runs the sim, has a local player (default)
##   --server                     dedicated: runs the sim, no local player, fine with --headless
##   --client --address=<ip>      connects to a server; runs no sim
##   --port=<n>                   default 7777
##   --token=<string>             server: required; a peer must send it (Net.authenticate)
##                                within 5 s or it is disconnected. host: optional; without
##                                it anyone may join (local play). client: sent on connect
##   --state=<path>               server/host: JSON snapshot of entity state, written every
##                                30 ticks and on clean shutdown, loaded on start if present
##
## Test hooks (used by tests/net_test):
##   --test-move=<dx>,<dy>        once the local player exists, order it to move by this offset
##   --test-contest=<x>,<y>,<tick> at that server tick, order the local player to tile (x, y)
##   --test-exit-after=<seconds>  quit after this long
##
## Options are read from both the engine argument list and the user arguments
## after "--". Use the --name=value form: a bare value before "--" would be
## taken by Godot as a scene path.

enum Mode { HOST, SERVER, CLIENT }

const DEFAULT_PORT := 7777
## ENet connections, including ones still waiting to authenticate.
const MAX_CLIENTS := 8
## Authenticated peers at once; later ones are refused.
const MAX_PLAYERS := 4
## Seconds a connected peer has to send the token.
const AUTH_TIMEOUT := 5.0

## A peer has sent the right token (or none was required) and may be given a
## player. Main spawns players on this, never on peer_connected.
signal peer_authenticated(peer: int)

var mode := Mode.HOST
var address := "127.0.0.1"
var port := DEFAULT_PORT
## Snapshot file for the authority, or "" for none.
var state_path := ""
## Join token. Never written anywhere in the repo; see server/env.example.
var token := ""
## Server only: peers that have authenticated.
var _authenticated: Dictionary[int, bool] = {}
## True once an ENet peer is in place. False means offline single-player.
var online := false

## This peer's id: 1 on the server, host and offline; ENet's id on a client.
## Cached because a closed ENet peer can no longer be asked.
var local_id := 1

var test_move := Vector2i.ZERO
var test_contest_tile := Vector2i.ZERO
var test_contest_tick := 0
var test_exit_after := 0.0

var mispredicts_total := 0
## Times (msec) of mispredictions in the last minute.
var _mispredict_times: Array[int] = []


func _enter_tree() -> void:
	_parse_args()


## Round trip time to the server in milliseconds, as measured by ENet.
## 0 on the server, the host, offline, and before a client has connected.
func rtt_ms() -> float:
	if mode != Mode.CLIENT or not online:
		return 0.0
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null or enet.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return 0.0
	var server := enet.get_peer(1)
	if server == null:
		return 0.0
	return server.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)


## The same in sim ticks, capped so a bad reading cannot stall reconciliation.
func rtt_ticks() -> float:
	return minf(rtt_ms() / 1000.0 * World.TICK_RATE, 10.0)


func record_mispredict() -> void:
	mispredicts_total += 1
	_mispredict_times.append(Time.get_ticks_msec())


## Mispredictions in the last 60 seconds.
func mispredicts_per_minute() -> int:
	var cutoff := Time.get_ticks_msec() - 60000
	while not _mispredict_times.is_empty() and _mispredict_times[0] < cutoff:
		_mispredict_times.pop_front()
	return _mispredict_times.size()


func _notification(what: int) -> void:
	# Leave cleanly when the window is closed so the other side sees it at once.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		shutdown()


## The authority gate used by every mutation: multiplayer.is_server(), except
## that a process started as a client is never the authority. That matters
## before it connects and after its connection closes, when is_server() would
## either say yes (offline peer) or fail (closed ENet peer), and a mirror must
## never start simulating.
func is_authority() -> bool:
	if mode == Mode.CLIENT:
		return false
	# A server or host whose peer is closed (shutting down, or never opened)
	# is simply offline: still the only authority there is. A closed ENet peer
	# cannot even be asked is_server(), so settle it here.
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return true
	return multiplayer.is_server()


## Server side: has [param peer] sent the right token? The authority itself
## always has.
func is_peer_authenticated(peer: int) -> bool:
	return peer == local_id or _authenticated.has(peer)


## Sent by a client right after it connects. On the server, a correct token
## lets the peer in; anything else gets it disconnected.
@rpc("any_peer", "call_remote", "reliable")
func authenticate(offered: String) -> void:
	if not is_authority():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0 or _authenticated.has(peer):
		return
	if token == "" or offered != token:
		_reject(peer, "empty token" if offered == "" else "wrong token")
	elif _authenticated.size() >= MAX_PLAYERS:
		_reject(peer, "server full")
	else:
		_admit(peer)


func _on_peer_connected(peer: int) -> void:
	if _authenticated.size() >= MAX_PLAYERS:
		_reject(peer, "server full")
	elif token == "":
		# A host without a token is local play: anyone may join.
		_admit(peer)
	else:
		get_tree().create_timer(AUTH_TIMEOUT).timeout.connect(_on_auth_timeout.bind(peer))


func _on_auth_timeout(peer: int) -> void:
	if online and peer in multiplayer.get_peers() and not _authenticated.has(peer):
		_reject(peer, "no token after %d s" % roundi(AUTH_TIMEOUT))


func _on_peer_disconnected(peer: int) -> void:
	_authenticated.erase(peer)


func _admit(peer: int) -> void:
	_authenticated[peer] = true
	print("[net] peer %d authenticated (%d of %d)" % [peer, _authenticated.size(), MAX_PLAYERS])
	peer_authenticated.emit(peer)


func _reject(peer: int, why: String) -> void:
	print("[net] rejected peer %d from %s (%s)" % [peer, _peer_address(peer), why])
	multiplayer.multiplayer_peer.disconnect_peer(peer)


func _peer_address(peer: int) -> String:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return "?"
	var packet_peer := enet.get_peer(peer)
	return packet_peer.get_remote_address() if packet_peer != null else "?"


## Closes the connection, if any. Safe to call more than once.
func shutdown() -> void:
	if online:
		online = false
		multiplayer.multiplayer_peer.close()


## Creates the ENet peer for the chosen mode. Called once by Main, after its
## MultiplayerSpawner is ready to receive.
func start() -> void:
	if online:
		return
	var peer := ENetMultiplayerPeer.new()
	if mode == Mode.CLIENT:
		var error := peer.create_client(address, port)
		if error != OK:
			push_error("[net] cannot connect to %s:%d (%s)" % [address, port, error_string(error)])
			return
		multiplayer.connected_to_server.connect(_on_connected_to_server)
		multiplayer.connection_failed.connect(
				func() -> void: print("[net] connection to %s:%d failed" % [address, port]))
		multiplayer.server_disconnected.connect(_on_server_disconnected)
		print("[net] client connecting to %s:%d" % [address, port])
	else:
		if mode == Mode.SERVER and token == "":
			push_error("[net] --server needs --token=<string>: refusing to run an open server")
			get_tree().quit(1)
			return
		var error := peer.create_server(port, MAX_CLIENTS)
		if error != OK:
			if mode == Mode.SERVER:
				push_error("[net] cannot listen on port %d (%s)" % [port, error_string(error)])
				get_tree().quit(1)
			else:
				# Single-player must keep working when the port is taken.
				print("[net] port %d unavailable (%s); running offline" % [port, error_string(error)])
			return
		print("[net] %s listening on port %d%s" % [
			"server" if mode == Mode.SERVER else "host", port,
			", token required" if token != "" else ", no token: open to anyone"])
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.multiplayer_peer = peer
	local_id = multiplayer.get_unique_id()
	online = true


func _on_connected_to_server() -> void:
	print("[net] connected as peer %d" % multiplayer.get_unique_id())
	authenticate.rpc_id(1, token)


func _on_server_disconnected() -> void:
	online = false
	print("[net] server disconnected")


func _parse_args() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var key := args[i]
		var value := ""
		var has_value := false
		var equals := key.find("=")
		if equals != -1:
			value = key.substr(equals + 1)
			key = key.substr(0, equals)
			has_value = true
		match key:
			"--host":
				mode = Mode.HOST
			"--server":
				mode = Mode.SERVER
			"--client":
				mode = Mode.CLIENT
			"--address", "--port", "--state", "--token", "--test-move", "--test-contest", "--test-exit-after":
				if not has_value and i + 1 < args.size():
					i += 1
					value = args[i]
				_set_option(key, value)
		i += 1


func _set_option(key: String, value: String) -> void:
	match key:
		"--address":
			address = value
		"--port":
			if value.is_valid_int():
				port = value.to_int()
		"--state":
			state_path = value
		"--token":
			token = value
		"--test-move":
			var parts := value.split(",")
			if parts.size() == 2:
				test_move = Vector2i(parts[0].to_int(), parts[1].to_int())
		"--test-contest":
			var parts := value.split(",")
			if parts.size() == 3:
				test_contest_tile = Vector2i(parts[0].to_int(), parts[1].to_int())
				test_contest_tick = parts[2].to_int()
		"--test-exit-after":
			test_exit_after = value.to_float()
