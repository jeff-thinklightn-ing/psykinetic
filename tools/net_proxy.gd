extends SceneTree
## A bad link on localhost: a UDP relay between clients and a server that
## holds each packet a while, varies it, and drops some, either way (ENet is
## UDP, so a client pointed at the relay's port plays through it unaware).
## For measuring how the game looks over a real connection (tools/net_smooth.sh)
## without installing anything (Clumsy and its like need a driver and admin).
##
##   godot --headless --script res://tools/net_proxy.gd -- --listen=<port> --server=<port>
##       [--delay=<ms>] [--jitter=<ms>] [--loss=<percent>] [--burst=<packets>]
##       [--seconds=<s>] [--seed=<n>]
##
## --delay is each way (a round trip pays it twice), --jitter adds up to that
## much more or less to each packet at random, but never puts a packet before
## the one sent ahead of it (a link delays, it seldom reorders). --loss is the
## share of packets dropped each way, in bursts --burst packets long on average
## (1: each packet on its own; a Wi-Fi fade or a congested hop drops several
## together). It quits after --seconds (0: when killed) and prints what it
## carried and dropped.

const POLL_USEC := 250

var _listen := 0
var _server := 0
var _delay := 0.0
var _jitter := 0.0
var _loss := 0.0
var _burst := 1.0
var _seconds := 0.0
var _rng := RandomNumberGenerator.new()
var _udp := UDPServer.new()
## One per client address: {down: PacketPeerUDP (to the client), up:
## PacketPeerUDP (to the server), to_server: [], to_client: [], each a queue
## of [due msec, bytes], and each way's last due time and loss state}.
var _links: Array[Dictionary] = []
var _carried := 0
var _dropped := 0
var _started := 0


func _initialize() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for arg in args:
		var pair := arg.split("=", true, 1)
		if pair.size() != 2:
			continue
		match pair[0]:
			"--listen": _listen = pair[1].to_int()
			"--server": _server = pair[1].to_int()
			"--delay": _delay = pair[1].to_float()
			"--jitter": _jitter = pair[1].to_float()
			"--loss": _loss = clampf(pair[1].to_float() / 100.0, 0.0, 0.9)
			"--burst": _burst = maxf(pair[1].to_float(), 1.0)
			"--seconds": _seconds = pair[1].to_float()
			"--seed": _rng.seed = pair[1].to_int()
	if _listen <= 0 or _server <= 0:
		printerr("net_proxy: --listen=<port> and --server=<port> are needed")
		quit(1)
		return
	var error := _udp.listen(_listen, "127.0.0.1")
	if error != OK:
		printerr("net_proxy: cannot listen on %d: %s" % [_listen, error_string(error)])
		quit(1)
		return
	_started = Time.get_ticks_msec()
	print("[proxy] %d -> %d: %.0f ms each way, jitter %.0f ms, loss %.1f%% in bursts of %.1f" % [
		_listen, _server, _delay, _jitter, _loss * 100.0, _burst])


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_msec()
	_udp.poll()
	while _udp.is_connection_available():
		var down := _udp.take_connection()
		var up := PacketPeerUDP.new()
		up.connect_to_host("127.0.0.1", _server)
		_links.append({"down": down, "up": up, "to_server": [], "to_client": [],
			"due_server": 0.0, "due_client": 0.0, "bad_server": false, "bad_client": false})
		print("[proxy] client %s:%d" % [down.get_packet_ip(), down.get_packet_port()])
	for link in _links:
		var down: PacketPeerUDP = link["down"]
		var up: PacketPeerUDP = link["up"]
		while down.get_available_packet_count() > 0:
			_hold(link, "server", down.get_packet(), now)
		while up.get_available_packet_count() > 0:
			_hold(link, "client", up.get_packet(), now)
		_send_due(link["to_server"], up, now)
		_send_due(link["to_client"], down, now)
	if _seconds > 0.0 and now - _started >= _seconds * 1000.0:
		_finish()
		return true
	OS.delay_usec(POLL_USEC)
	return false


## [param bytes] going [param way] ("server" or "client"): dropped, or
## queued for when its delay is up.
func _hold(link: Dictionary, way: String, bytes: PackedByteArray, now: int) -> void:
	# Gilbert's two states: in a bad spell every packet is lost, and a spell
	# ends with 1/burst a packet; one starts at the rate that loses _loss
	# of all packets on average.
	var bad: bool = link["bad_" + way]
	if bad:
		bad = _rng.randf() >= 1.0 / _burst
	elif _loss > 0.0:
		bad = _rng.randf() < _loss / (_burst * (1.0 - _loss))
	link["bad_" + way] = bad
	if bad:
		_dropped += 1
		return
	var due := now + _delay + _rng.randf_range(-_jitter, _jitter)
	due = maxf(due, link["due_" + way])
	link["due_" + way] = due
	link["to_" + way].append([due, bytes])


func _send_due(queue: Array, peer: PacketPeerUDP, now: int) -> void:
	while not queue.is_empty() and queue[0][0] <= now:
		peer.put_packet(queue.pop_front()[1])
		_carried += 1


func _finish() -> void:
	print("[proxy] carried %d packets, dropped %d (%.1f%%)" % [
		_carried, _dropped, 100.0 * _dropped / maxi(_carried + _dropped, 1)])
