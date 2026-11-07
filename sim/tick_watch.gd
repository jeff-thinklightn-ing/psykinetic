extends RefCounted
## The server's tick watchdog (decision 817). A thread outside the sim
## looks at when World's last frame ran (alive(): a tick held or not due is
## no stall, a step that never ends is): none for STALL_MSEC (the worst
## tick measured, a 16-player day turn in the town soak, was 1.3 s; the box's
## worst today 193 ms) and it prints one line naming the last part of the
## tick that finished (World.part) and the last error the engine reported,
## then kills its own process (SIGKILL on the box: a failure to systemd's
## Restart=on-failure, which starts it again; on Windows the exit code is 0).
## Armed by World's first frame, after the world is loaded. Each hour it prints
## "[tick] avg N ms, worst M ms, ticks T over the last hour". Made and fed
## by World on a dedicated server only (World._watch).

const STALL_MSEC := 30000
const HOUR_MSEC := 3600000
## How often the thread looks.
const LOOK_MSEC := 1000

var stall_msec := STALL_MSEC
var hour_msec := HOUR_MSEC
var _mutex := Mutex.new()
var _thread: Thread
var _stop := false
var _beat_msec := -1  # When the last tick was done; -1 till the first.
var _tick := 0
var _part := ""  # The last part of a tick that finished (World.part).
var _error := ""  # The last error the engine reported (_ErrorSeen).
var _logger: _ErrorSeen
# This hour's ticks, for the hourly line (main thread only).
var _hour_from := 0
var _hour_ticks := 0
var _hour_usec := 0
var _hour_worst := 0


## Keeps the last error the engine reports, from any thread.
class _ErrorSeen extends Logger:
	var watch: WeakRef

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var owner: Variant = watch.get_ref()
		if owner == null:
			return
		var kind := "SCRIPT ERROR" if error_type == ERROR_TYPE_SCRIPT else "ERROR"
		owner._seen("%s: %s (%s:%d, %s)" % [kind, rationale if not rationale.is_empty() else code, file, line, function])

	func _log_message(_message: String, _error: bool) -> void:
		pass


func start() -> void:
	_hour_from = Time.get_ticks_msec()
	_logger = _ErrorSeen.new()
	_logger.watch = weakref(self)
	OS.add_logger(_logger)
	_thread = Thread.new()
	_thread.start(_watch)


func stop() -> void:
	_mutex.lock()
	_stop = true
	_mutex.unlock()
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	if _logger != null:
		OS.remove_logger(_logger)
		_logger = null


## A frame of World's: the main loop goes on (main thread).
func alive(tick: int) -> void:
	_mutex.lock()
	_beat_msec = Time.get_ticks_msec()
	_tick = tick
	_mutex.unlock()


## A tick done, [param usec] long (main thread): for the hourly line.
func beat(tick: int, usec: int) -> void:
	alive(tick)
	_hour_ticks += 1
	_hour_usec += usec
	_hour_worst = maxi(_hour_worst, usec)
	var now := Time.get_ticks_msec()
	if now - _hour_from >= hour_msec:
		print(hour_line())
		_hour_from = now
		_hour_ticks = 0
		_hour_usec = 0
		_hour_worst = 0


## The hourly line, for this hour's ticks so far.
func hour_line() -> String:
	return "[tick] avg %.1f ms, worst %.1f ms, ticks %d over the last hour" % [
		_hour_usec / 1000.0 / maxi(_hour_ticks, 1), _hour_worst / 1000.0, _hour_ticks]


## A part of the tick finished (World.part).
func note_part(name: String) -> void:
	_mutex.lock()
	_part = name
	_mutex.unlock()


func _seen(error: String) -> void:
	_mutex.lock()
	_error = error
	_mutex.unlock()


## The stall's line, or "" if the main loop goes on (the thread's look; also
## for tests).
func stalled_line(now_msec: int) -> String:
	_mutex.lock()
	var line := ""
	if _beat_msec >= 0 and now_msec - _beat_msec >= stall_msec:
		line = "[tick] stalled: the main loop stuck %.0f s, since tick %d; the last part done: %s; the last error: %s; quitting for a restart" % [
			(now_msec - _beat_msec) / 1000.0, _tick, _part if not _part.is_empty() else "none",
			_error if not _error.is_empty() else "none"]
	_mutex.unlock()
	return line


func _watch() -> void:
	while true:
		OS.delay_msec(LOOK_MSEC)
		_mutex.lock()
		var stopping := _stop
		_mutex.unlock()
		if stopping:
			return
		var line := stalled_line(Time.get_ticks_msec())
		if not line.is_empty():
			printerr(line)
			OS.kill(OS.get_process_id())
			return
