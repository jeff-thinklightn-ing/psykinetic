class_name ServerStatus
extends RefCounted
## A server's status asked before joining (decision 431): a tiny UDP
## exchange beside the game's ENet port, so the menu can say whether the
## server is there, its build and how full it is. Not an RPC on Net:
## Godot numbers RPCs by each node's methods, which change between builds
## (what Net.protocol() guards, decision 239), and this must work across
## them. The client sends {"status": VERSION} padded to REQUEST_SIZE bytes;
## the server answers {"status", "version", "protocol", "players",
## "accepting"} and nothing else (no token, no names), never more bytes
## than the request held and at most once a RATE_MSEC per address, so it
## cannot be used to amplify traffic. A server answers only when started
## with --status-port (the box's unit: the game port + PORT_STEP; + 1 is
## the admin console's TCP number there); a client asks at --status-port or
## settings status_port=, else the game port + PORT_STEP.

## The exchange's own version: a reply with another is read as no answer.
const VERSION := 1
const REQUEST_SIZE := 512
const RATE_MSEC := 1000
const ANSWER_SEC := 2.0
const PORT_STEP := 2


## The status port for a game on [param game_port], [param given] if set.
static func port_for(game_port: int, given := 0) -> int:
	return given if given > 0 else game_port + PORT_STEP


## The request's bytes: {"status": VERSION}, padded with spaces.
static func request() -> PackedByteArray:
	var text := JSON.stringify({"status": VERSION})
	return (text + " ".repeat(REQUEST_SIZE - text.length())).to_utf8_buffer()


## The server's answer to [param packet] given what [param info] says
## ({version, protocol, players, accepting}), or empty for a packet that
## is not a request (too short, not this version) or a reply that would be
## larger than it.
static func reply(packet: PackedByteArray, info: Dictionary) -> PackedByteArray:
	if packet.size() < REQUEST_SIZE:
		return PackedByteArray()
	var asked: Variant = _parse(packet)
	if not asked is Dictionary or int((asked as Dictionary).get("status", 0)) != VERSION:
		return PackedByteArray()
	var out := JSON.stringify({"status": VERSION, "version": str(info.get("version", "")),
		"protocol": str(info.get("protocol", "")), "players": int(info.get("players", 0)),
		"accepting": bool(info.get("accepting", false))}).to_utf8_buffer()
	return out if out.size() <= packet.size() else PackedByteArray()


## [param packet] read as JSON, null if it is not (quietly: a stranger's
## junk is no error worth logging).
static func _parse(packet: PackedByteArray) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(packet.get_string_from_utf8()) == OK else null


## The server's side: listens on the status port and answers, polled from
## Net's _process.
class Responder:
	extends RefCounted
	var _udp := PacketPeerUDP.new()
	## Address -> when it was last answered (msec).
	var _answered: Dictionary[String, int] = {}
	## () -> {version, protocol, players, accepting}.
	var info: Callable

	func listen(port: int) -> Error:
		return _udp.bind(port)

	func is_listening() -> bool:
		return _udp.is_bound()

	func close() -> void:
		_udp.close()

	## Answers what has come in; returns how many it answered.
	func poll(now := Time.get_ticks_msec()) -> int:
		var count := 0
		while _udp.get_available_packet_count() > 0:
			var packet := _udp.get_packet()
			var from_ip := _udp.get_packet_ip()
			var from_port := _udp.get_packet_port()
			if _answered.has(from_ip) and now - _answered[from_ip] < RATE_MSEC:
				continue
			var out := ServerStatus.reply(packet, info.call() if info.is_valid() else {})
			if out.is_empty():
				continue
			_answered[from_ip] = now
			_udp.set_dest_address(from_ip, from_port)
			_udp.put_packet(out)
			count += 1
		if _answered.size() > 256:
			for ip: String in _answered.keys():
				if now - _answered[ip] >= RATE_MSEC:
					_answered.erase(ip)
		return count


## The client's side: one question, answered within ANSWER_SEC or not.
class Query:
	extends RefCounted
	var address := ""
	var port := 0
	var _udp := PacketPeerUDP.new()
	var _deadline := 0
	var _result := {}

	## Asks the server at [param with_address] whose status port is
	## [param status_port].
	func send(with_address: String, status_port: int) -> void:
		address = with_address
		port = status_port
		_deadline = Time.get_ticks_msec() + roundi(ANSWER_SEC * 1000.0)
		var ip := with_address if with_address.is_valid_ip_address() else IP.resolve_hostname(with_address)
		if ip.is_empty():
			_result = {"ok": false, "why": "no such server: %s" % with_address}
			return
		if _udp.set_dest_address(ip, status_port) != OK or _udp.put_packet(ServerStatus.request()) != OK:
			_result = {"ok": false, "why": "could not ask %s" % with_address}

	## The answer once there is one ({ok: true, version, protocol, players,
	## accepting}, or {ok: false, why}), else {} while still waiting.
	func poll(now := Time.get_ticks_msec()) -> Dictionary:
		if not _result.is_empty():
			return _result
		while _udp.get_available_packet_count() > 0:
			var answer: Variant = ServerStatus._parse(_udp.get_packet())
			if answer is Dictionary and int((answer as Dictionary).get("status", 0)) == VERSION:
				_result = {"ok": true, "version": str(answer.get("version", "")), "protocol": str(answer.get("protocol", "")),
					"players": int(answer.get("players", 0)), "accepting": bool(answer.get("accepting", false))}
				_udp.close()
				return _result
		if now >= _deadline:
			_result = {"ok": false, "why": "no answer"}
			_udp.close()
		return _result
