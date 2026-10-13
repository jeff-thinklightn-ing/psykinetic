class_name NetStats
extends RefCounted
## How smooth the network is, measured, over the last WINDOW_MSEC.
##   Server: how long each sim tick takes (World.step), the longest frame,
##   and bytes sent and received a second. The admin's "net" command and a
##   log line once a minute while anyone is connected.
##   Client: each correction of the local player (the server had it
##   somewhere the prediction did not), how far the sprite was off and
##   whether it blended or snapped. The F3 overlay and a log line once a
##   minute.

const WINDOW_MSEC := 60000
## The window is trimmed this often as samples come in, whether or not
## anything reads it: a server nobody is on for hours keeps a minute of
## samples, not hours of them.
const TRIM_EVERY_MSEC := 1000

## [msec, usec, tick] for each sim tick in the window.
var _ticks: Array[Array] = []
## [msec, usec] for each frame's process time in the window.
var _frames: Array[Array] = []
## [msec, sent bytes, received bytes] a sample a second.
var _traffic: Array[Array] = []
## [msec, tiles, snapped] for each correction in the window.
var _corrections: Array[Array] = []
var corrections_total := 0
var worst_correction_ever := 0.0
var _next_log_msec := WINDOW_MSEC
var _next_trim_msec := 0


func record_tick(usec: int, tick: int) -> void:
	_ticks.append([Time.get_ticks_msec(), usec, tick])
	_trim_due()


func record_frame(usec: int) -> void:
	_frames.append([Time.get_ticks_msec(), usec])
	_trim_due()


func record_traffic(sent: int, received: int) -> void:
	_traffic.append([Time.get_ticks_msec(), sent, received])
	_trim_due()


## The local player was corrected: its sprite was [param tiles] from the
## server's tile, and was [param snapped] there or blended.
func record_correction(tiles: float, snapped: bool) -> void:
	_corrections.append([Time.get_ticks_msec(), tiles, snapped])
	corrections_total += 1
	worst_correction_ever = maxf(worst_correction_ever, tiles)


func _trim_due() -> void:
	var now := Time.get_ticks_msec()
	if now >= _next_trim_msec:
		_next_trim_msec = now + TRIM_EVERY_MSEC
		_trim()


## Drops the samples older than the window: all of them at once (they are
## in time order), not one at a time from the front, which moves the rest
## each time.
func _trim() -> void:
	var cutoff := Time.get_ticks_msec() - WINDOW_MSEC
	_ticks = _within(_ticks, cutoff)
	_frames = _within(_frames, cutoff)
	_traffic = _within(_traffic, cutoff)
	_corrections = _within(_corrections, cutoff)


static func _within(list: Array[Array], cutoff: int) -> Array[Array]:
	var old := list.bsearch_custom([cutoff], func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	if old == 0:
		return list
	return list.slice(old)


## Server: "tick avg 0.42 ms, worst 3.10 ms (tick 812) over 600; frame
## worst 8.0 ms; sent 4.1 KB/s, received 0.6 KB/s".
func server_text() -> String:
	_trim()
	if _ticks.is_empty():
		return "no ticks in the last minute"
	var total := 0
	var worst: Array = _ticks[0]
	for entry in _ticks:
		total += int(entry[1])
		if int(entry[1]) > int(worst[1]):
			worst = entry
	var frame_worst := 0
	for entry in _frames:
		frame_worst = maxi(frame_worst, int(entry[1]))
	var sent := 0
	var received := 0
	for entry in _traffic:
		sent += int(entry[1])
		received += int(entry[2])
	var seconds := maxf(_traffic.size(), 1.0)
	return "tick avg %.2f ms, worst %.2f ms (tick %d) over %d ticks; frame worst %.1f ms; sent %.1f KB/s, received %.1f KB/s" % [
		total / 1000.0 / _ticks.size(), int(worst[1]) / 1000.0, int(worst[2]), _ticks.size(),
		frame_worst / 1000.0, sent / 1024.0 / seconds, received / 1024.0 / seconds]


func corrections_per_minute() -> int:
	_trim()
	return _corrections.size()


## The furthest the local player's sprite was off when corrected, in the
## window, in tiles.
func worst_correction() -> float:
	_trim()
	var worst := 0.0
	for entry in _corrections:
		worst = maxf(worst, float(entry[1]))
	return worst


## Client: "corrections 3/min (1 snapped), worst 0.62 tiles (ever 1.40)".
func client_text() -> String:
	_trim()
	var snapped := 0
	for entry in _corrections:
		if entry[2]:
			snapped += 1
	return "corrections %d/min (%d snapped), worst %.2f tiles (ever %.2f)" % [
		_corrections.size(), snapped, worst_correction(), worst_correction_ever]


## True once a minute: time for the log line.
func log_due() -> bool:
	var now := Time.get_ticks_msec()
	if now < _next_log_msec:
		return false
	_next_log_msec = now + WINDOW_MSEC
	return true
