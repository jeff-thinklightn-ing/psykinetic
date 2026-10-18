extends Node
## A server's status before joining (decision 431): the request is padded
## to 512 bytes and the reply is never larger; a short request, another
## version or junk gets nothing; a server answers a query on localhost with
## its version, protocol, players and whether it takes more, and nothing
## else; the same address asking again within a second gets nothing (the
## rate limit), so that query reads "no answer" after 2 s; nobody listening
## reads "no answer" too; Net.query_status says so through status_received,
## with compatible worked out. Run it with tests/run.ps1 or tests/run.sh.

const BASE_PORT := 17850

var _failures := 0


func _ready() -> void:
	World.set_process(false)
	_test_packets()
	await _test_exchange()
	await _test_net()
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
