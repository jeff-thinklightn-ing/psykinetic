extends Node
## A server's status before joining (decision 431): the request is padded
## to 512 bytes and the reply is never larger; a short request, another
## version or junk gets nothing; a server answers a query on localhost with
## its version, protocol, players and whether it takes more, and nothing
## else; the same address asking again within a second gets nothing (the
## rate limit), so that query reads "no answer" after 2 s; nobody listening
## reads "no answer" too; Net.query_status says so through status_received,
## with compatible worked out. 431 amended (2): an answer from another port
## than the one asked is not read; a question to this machine holds no socket
## past the loopback. Run it with tests/run.ps1 or tests/run.sh.

const BASE_PORT := 17850

var _failures := 0


func _ready() -> void:
	World.set_process(false)
	_test_packets()
	await _test_exchange()
	await _test_net()
	await _test_only_from_asked()
	_test_loopback_socket()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _info() -> Dictionary:
	return {"version": "0.1.150", "protocol": "abc123", "players": 3, "accepting": true}


func _test_packets() -> void:
	print("== the packets ==")
	var asked := ServerStatus.request()
	_check(asked.size() == ServerStatus.REQUEST_SIZE, "the request is padded to %d bytes" % ServerStatus.REQUEST_SIZE)
	var answer := ServerStatus.reply(asked, _info())
	var read: Variant = JSON.parse_string(answer.get_string_from_utf8())
	_check(not answer.is_empty() and answer.size() <= asked.size(), "the reply is no larger than the request (%d of %d)" % [answer.size(), asked.size()])
	_check(read is Dictionary and (read as Dictionary).keys().size() == 5 and read["players"] == 3 and read["accepting"] == true
		and read["version"] == "0.1.150", "it holds status, version, protocol, players and accepting, nothing else (%s)" % [read])
	_check(ServerStatus.reply(JSON.stringify({"status": 1}).to_utf8_buffer(), _info()).is_empty(), "an unpadded request gets nothing")
	var other := (JSON.stringify({"status": 2}) + " ".repeat(500)).to_utf8_buffer()
	_check(ServerStatus.reply(other, _info()).is_empty(), "another version gets nothing")
	var junk := PackedByteArray()
	junk.resize(600)
	_check(ServerStatus.reply(junk, _info()).is_empty(), "junk gets nothing")
	var long_info := _info()
	long_info["version"] = "x".repeat(600)
	_check(ServerStatus.reply(asked, long_info).is_empty(), "a reply that would outgrow the request is not sent")
	_check(ServerStatus.port_for(7777) == 7779 and ServerStatus.port_for(7777, 9000) == 9000, "the status port: the game's + 2, unless given")


func _test_exchange() -> void:
	print("== asked on localhost ==")
	var port: int = preload("res://tests/test_ports.gd").of(BASE_PORT)
	var server := ServerStatus.Responder.new()
	server.info = _info
	_check(server.listen(port) == OK, "the server listens on %d" % port)
	var first := ServerStatus.Query.new()
	first.send("127.0.0.1", port)
	var result := await _answer(first, server)
	_check(result.get("ok") == true and result.get("players") == 3 and result.get("protocol") == "abc123" and result.get("accepting") == true,
		"answered: v0.1.150, 3 players, taking more (%s)" % [result])
	var again := ServerStatus.Query.new()
	again.send("127.0.0.1", port)
	result = await _answer(again, server)
	_check(result == {"ok": false, "why": "no answer"}, "asked again within a second: nothing, so no answer (%s)" % [result])
	server.close()
	var nobody := ServerStatus.Query.new()
	nobody.send("127.0.0.1", port)
	result = await _answer(nobody, null)
	_check(result == {"ok": false, "why": "no answer"}, "nobody listening: no answer")


func _test_net() -> void:
	print("== Net.query_status ==")
	var port: int = preload("res://tests/test_ports.gd").of(BASE_PORT + 4)
	var server := ServerStatus.Responder.new()
	server.info = func() -> Dictionary: return {"version": Net.version, "protocol": Net.protocol(), "players": 0, "accepting": true}
	server.listen(ServerStatus.port_for(port))
	var heard: Array = []
	Net.status_received.connect(func(address: String, game_port: int, result: Dictionary) -> void: heard.append([address, game_port, result]))
	Net.query_status("127.0.0.1", port)
	var frames := 0
	while heard.is_empty() and frames < 400:
		server.poll()
		await get_tree().process_frame
		frames += 1
	server.close()
	var result: Dictionary = heard[0][2] if not heard.is_empty() else {}
	_check(heard.size() == 1 and heard[0][0] == "127.0.0.1" and heard[0][1] == port and result.get("ok") == true
		and result.get("compatible") == true, "status_received once, for the address and game port asked, compatible (%s)" % [heard])


func _test_only_from_asked() -> void:
	print("== an answer only from where it asked (431 amended (2)) ==")
	# An ephemeral port, never one of the suite's fixed ones (431 amended (3)): BASE_PORT + 8 was
	# camp_fall_test's game port, and with both scenes running at once the listen failed unseen and
	# the question went to that game's server ("no answer", animation's saturn landing, 11-13).
	var server := ServerStatus.Responder.new()
	server.info = _info
	_check(server.listen(0, "127.0.0.1") == OK, "the server listens on an ephemeral loopback port")
	var port: int = server._udp.get_local_port()
	var query := ServerStatus.Query.new()
	query.send("127.0.0.1", port)
	# A stranger (another port on this machine) sends a well-formed answer first.
	var stranger := PacketPeerUDP.new()
	stranger.bind(0, "127.0.0.1")
	stranger.set_dest_address("127.0.0.1", query._udp.get_local_port())
	var forged := ServerStatus.reply(ServerStatus.request(), {"version": "9.9.9", "protocol": "forged", "players": 99, "accepting": false})
	_check(not forged.is_empty() and stranger.put_packet(forged) == OK, "a stranger sends a well-formed answer to the query's port")
	for i in 5:
		await get_tree().process_frame
	_check(query.poll().is_empty(), "the query has not read it")
	var result := await _answer(query, server)
	_check(result.get("ok") == true and result.get("protocol") == "abc123",
		"the server's own answer is the one read (%s)" % [result])
	stranger.close()
	server.close()


## The local addresses of this process's UDP sockets, or null when the
## platform's tool cannot be asked (Windows: Get-NetUDPEndpoint; Linux: ss).
func _udp_sockets() -> Variant:
	var out: Array = []
	var pid := OS.get_process_id()
	var code := 0
	if OS.get_name() == "Windows":
		code = OS.execute("powershell", ["-NoProfile", "-NonInteractive", "-Command",
			"Get-NetUDPEndpoint -OwningProcess %d -ErrorAction SilentlyContinue | ForEach-Object { $_.LocalAddress + ' ' + $_.LocalPort }" % pid], out)
		if code != 0 or out.is_empty():
			return null
		return (out[0] as String).strip_edges().split("\n", false)
	code = OS.execute("ss", ["-uanpH"], out)
	if code != 0 or out.is_empty():
		return null
	var mine: Array[String] = []
	for line in (out[0] as String).split("\n", false):
		if line.contains("pid=%d," % pid):
			var words := line.split(" ", false)
			if words.size() > 3:
				var local := words[3]
				var at := local.rfind(":")
				mine.append("%s %s" % [local.substr(0, at).trim_prefix("[").trim_suffix("]"), local.substr(at + 1)])
	return mine


func _test_loopback_socket() -> void:
	print("== a question to this machine holds no socket past the loopback (431 amended (2)) ==")
	# Asked of a sink on an ephemeral port, not a fixed one another scene may hold (431 amended (3)).
	var sink := PacketPeerUDP.new()
	sink.bind(0, "127.0.0.1")
	var query := ServerStatus.Query.new()
	query.send("127.0.0.1", sink.get_local_port())
	var local := query._udp.get_local_port()
	var sockets: Variant = _udp_sockets()
	if sockets == null:
		print("  SKIP  this platform's socket list could not be read")
		return
	var found := ""
	for line: String in sockets:
		if line.strip_edges().ends_with(" %d" % local):
			found = line.strip_edges()
	_check(found.begins_with("127.0.0.1 "), "the query's socket (port %d) is on 127.0.0.1: %s" % [local, found if found != "" else "not found in %s" % [sockets]])


## [param query]'s answer, with [param server] (if any) answering meanwhile.
func _answer(query: ServerStatus.Query, server: ServerStatus.Responder) -> Dictionary:
	while true:
		if server != null:
			server.poll()
		var result := query.poll()
		if not result.is_empty():
			return result
		await get_tree().process_frame
	return {}


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
