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
##   --admin-port=<n>             server/host: accept console commands on 127.0.0.1:<n> (TCP)
##   --console                    read console commands from stdin (--server does this anyway)
##   --settings=<path>            client settings file to use instead of the one next to the exe
##   --player-id=<id> --name=<s>  client: identity to present instead of the settings file's
##
## With no mode argument: an exported build reads settings.cfg (address=,
## port=, token=, player_id=, name=) next to the exe and joins as a client,
## or asks for those once if the file is missing; a run from the project is
## a host. display_delay= (ticks, default 2) sets how far in the past other
## entities are drawn. player_id is a UUID made on first run; the server remembers each
## player by it. A host run from the project uses a fixed dev id.
##
## The game version comes from version.txt at the project root. A client
## sends it with its token and a server rejects any other version.
##
## Test hooks (used by tests/net_test):
##   --test-move=<dx>,<dy>        once the local player exists, order it to move by this offset
##   --test-contest=<x>,<y>,<tick> at that server tick, order the local player to tile (x, y)
##   --test-exit-after=<seconds>  quit after this long
##   --test-version=<x.y.z>       client: claim this version instead of the real one
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
## Seconds between telling a peer why it is rejected and disconnecting it.
const REJECT_GRACE := 0.25

## A peer has sent a good hello and may be given a player. Main spawns
## players on this, never on peer_connected.
signal peer_authenticated(peer: int, player_id: String, player_name: String)
## Client: the server turned this peer away and said why, just before
## disconnecting it.
signal join_rejected(reason: String, server_version: String)

const SETTINGS_FILE := "settings.cfg"
const UNKNOWN_VERSION := "0.0.0"
## The identity a host run from the project uses, so its state persists too.
const DEV_PLAYER_ID := "dev-host"
const DEFAULT_NAME := "Player"
const MAX_NAME_LENGTH := 24

## From version.txt at the project root. Sent on join; must match the server.
var version := UNKNOWN_VERSION

var mode := Mode.HOST
var address := "127.0.0.1"
var port := DEFAULT_PORT
## Snapshot file for the authority, or "" for none.
var state_path := ""
## Localhost TCP port for console commands, or 0 for none.
var admin_port := 0
## Read console commands from stdin. Always on for --server.
var console := false
## Join token. Never written anywhere in the repo; see server/env.example.
var token := ""
## Who this client says it is. From settings.cfg, --player-id/--name, or
## for a project host the dev id.
var player_id := ""
var player_name := DEFAULT_NAME
## Server only: authenticated peer -> its player_id.
var _authenticated: Dictionary[int, String] = {}
## True when an exported build has no settings file and must ask for one.
var needs_setup := false
var _mode_given := false
var _settings_override := ""
var _test_version := ""
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
var snaps_total := 0
## Times (msec) of snaps in the last minute.
var _snap_times: Array[int] = []
## Times (msec) of mispredictions in the last minute.
var _mispredict_times: Array[int] = []


func _enter_tree() -> void:
	version = _read_version()
	_parse_args()
	if not _mode_given:
		_apply_settings()
	if player_id.is_empty():
		# A client run from the command line gets a throwaway id; a host or
		# server run from the project is always the same dev player.
		player_id = new_uuid() if mode == Mode.CLIENT else DEV_PLAYER_ID
	player_name = tidy_name(player_name)


## A random UUID v4, as a player identity.
static func new_uuid() -> String:
	var bytes := PackedByteArray()
	bytes.resize(16)
	for i in 16:
		bytes[i] = randi() & 0xFF
	bytes[6] = (bytes[6] & 0x0F) | 0x40
	bytes[8] = (bytes[8] & 0x3F) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]


static func tidy_name(raw: String) -> String:
	var tidy := raw.strip_edges().substr(0, MAX_NAME_LENGTH)
	return tidy if not tidy.is_empty() else DEFAULT_NAME


## Server side: the player_id an authenticated peer presented, or "".
func player_of(peer: int) -> String:
	return _authenticated.get(peer, "")


func _read_version() -> String:
	var text := FileAccess.get_file_as_string("res://version.txt").strip_edges()
	if text.is_empty():
		push_warning("[net] version.txt missing; reporting %s" % UNKNOWN_VERSION)
		return UNKNOWN_VERSION
	return text


## Where the client settings file lives: next to the exe in an exported
## build, wherever --settings points, or nowhere ("") in a project run.
func settings_path() -> String:
	if _settings_override != "":
		return _settings_override
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir().path_join(SETTINGS_FILE)
	return ""


## No mode on the command line: join from settings.cfg if there is one, ask
## for one in an exported build, otherwise host.
func _apply_settings() -> void:
	var path := settings_path()
	if path == "":
		return
	if not FileAccess.file_exists(path):
		needs_setup = true
		mode = Mode.CLIENT
		return
	var settings := _read_settings(path)
	configure_client(settings.get("address", address), int(settings.get("port", str(port))),
			settings.get("token", ""))
	player_name = tidy_name(settings.get("name", DEFAULT_NAME))
	var delay := str(settings.get("display_delay", ""))
	if delay.is_valid_int():
		World.display_delay_ticks = clampi(delay.to_int(), 0, 10)
	player_id = str(settings.get("player_id", "")).strip_edges()
	if player_id.is_empty():
		# First run with a hand-written file: give it an identity and keep it.
		player_id = new_uuid()
		save_settings(address, port, token, player_name)
		print("[net] gave %s a new player id" % path)
	print("[net] using %s" % path)


## Plain key=value lines; blank lines, comments and [sections] are ignored.
func _read_settings(path: String) -> Dictionary:
	var settings := {}
	for line in FileAccess.get_file_as_string(path).split("\n"):
		line = line.strip_edges()
		if line.is_empty() or line.begins_with("#") or line.begins_with(";") or line.begins_with("["):
			continue
		var equals := line.find("=")
		if equals > 0:
			settings[line.substr(0, equals).strip_edges()] = line.substr(equals + 1).strip_edges()
	return settings


## Writes the settings file, keeping (or minting) this client's player id.
## False if it cannot.
func save_settings(new_address: String, new_port: int, new_token: String,
		new_name: String) -> bool:
	var path := settings_path()
	if path == "":
		return false
	if player_id.is_empty():
		player_id = new_uuid()
	player_name = tidy_name(new_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[net] cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string("address=%s\nport=%d\ntoken=%s\nplayer_id=%s\nname=%s\ndisplay_delay=%d\n" % [
		new_address, new_port, new_token, player_id, player_name, World.display_delay_ticks])
	file.close()
	return true


func configure_client(new_address: String, new_port: int, new_token: String) -> void:
	mode = Mode.CLIENT
	address = new_address
	port = new_port
	token = new_token
	needs_setup = false


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
func record_snap() -> void:
	snaps_total += 1
	_snap_times.append(Time.get_ticks_msec())


## Snaps (mispredictions too big to blend) in the last 60 seconds.
func snaps_per_minute() -> int:
	var cutoff := Time.get_ticks_msec() - 60000
	while not _snap_times.is_empty() and _snap_times[0] < cutoff:
		_snap_times.pop_front()
	return _snap_times.size()


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


## The hello a client sends right after it connects: {token, version,
## player_id, name}. On the server, a matching version, the right token (if
## one is required) and an id nobody else is using let the peer in; anything
## else gets it told why and disconnected.
@rpc("any_peer", "call_remote", "reliable")
func authenticate(hello: Dictionary) -> void:
	if not is_authority():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0 or _authenticated.has(peer):
		return
	var offered := str(hello.get("token", ""))
	var client_version := str(hello.get("version", ""))
	var id := str(hello.get("player_id", "")).strip_edges()
	var player_name_given := tidy_name(str(hello.get("name", "")))
	if client_version != version:
		_reject(peer, "client out of date", "client %s, server %s" % [client_version, version])
	elif token != "" and offered != token:
		_reject(peer, "authentication failed", "empty token" if offered == "" else "wrong token")
	elif id.is_empty() or id.length() > 64:
		_reject(peer, "authentication failed", "bad player id")
	elif id in _authenticated.values():
		_reject(peer, "already connected", "already connected as %s" % id.left(8))
	elif _authenticated.size() >= MAX_PLAYERS:
		_reject(peer, "server full")
	else:
		_admit(peer, id, player_name_given)


func _on_peer_connected(peer: int) -> void:
	if _authenticated.size() >= MAX_PLAYERS:
		_reject(peer, "server full")
	else:
		# Even without a token the peer must say hello, so its version is checked.
		get_tree().create_timer(AUTH_TIMEOUT).timeout.connect(_on_auth_timeout.bind(peer))


func _on_auth_timeout(peer: int) -> void:
	if online and peer in multiplayer.get_peers() and not _authenticated.has(peer):
		_reject(peer, "authentication failed", "nothing sent in %d s" % roundi(AUTH_TIMEOUT))


func _on_peer_disconnected(peer: int) -> void:
	_authenticated.erase(peer)


func _admit(peer: int, id: String, player_name_given: String) -> void:
	_authenticated[peer] = id
	print("[net] peer %d authenticated as %s (%s) (%d of %d)" % [
		peer, player_name_given, id.left(8), _authenticated.size(), MAX_PLAYERS])
	peer_authenticated.emit(peer, id, player_name_given)


## [param reason] is what the player sees; [param detail] is for the log.
func _reject(peer: int, reason: String, detail := "") -> void:
	print("[net] rejected peer %d from %s (%s)" % [
		peer, _peer_address(peer), reason if detail == "" else detail])
	# Tell it why first. Disconnecting at once would drop that packet, and a
	# deferred ENet disconnect leaves the peer in a state replication cannot
	# send to, so give the message a moment to go out, then cut the peer.
	rejected.rpc_id(peer, reason, version)
	get_tree().create_timer(REJECT_GRACE).timeout.connect(func() -> void:
		if online and peer in multiplayer.get_peers():
			multiplayer.multiplayer_peer.disconnect_peer(peer))


@rpc("authority", "call_remote", "reliable")
func rejected(reason: String, server_version: String) -> void:
	print("[net] %s (server %s, this client %s)" % [reason, server_version, claimed_version()])
	join_rejected.emit(reason, server_version)


## What this client tells the server it is: the real version, unless a test
## hook says otherwise.
func claimed_version() -> String:
	return _test_version if _test_version != "" else version


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
	authenticate.rpc_id(1, {
		"token": token, "version": claimed_version(), "player_id": player_id, "name": player_name})


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
				_mode_given = true
			"--server":
				mode = Mode.SERVER
				_mode_given = true
			"--client":
				mode = Mode.CLIENT
				_mode_given = true
			"--console":
				console = true
			"--address", "--port", "--state", "--admin-port", "--token", "--settings", "--player-id", "--name", \
					"--test-move", "--test-contest", "--test-exit-after", "--test-version":
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
		"--settings":
			_settings_override = value
		"--player-id":
			player_id = value.strip_edges()
		"--name":
			player_name = value
		"--admin-port":
			if value.is_valid_int():
				admin_port = value.to_int()
		"--test-version":
			_test_version = value
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
