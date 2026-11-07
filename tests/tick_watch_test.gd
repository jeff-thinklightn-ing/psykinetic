extends Node
## The server's tick watchdog (decision 817, sim/tick_watch.gd): its stall
## line names the tick, the last part done and the last error; held frames
## are no stall; the hourly line averages the ticks; and a Godot whose main
## loop wedges (tests/tick_watch_wedge.tscn, a 3 s watch) is ended by its own
## watchdog, the line printed. Prints PASS/FAIL per assertion and quits with
## exit code 1 if any assertion failed, 0 otherwise.

const TickWatch := preload("res://sim/tick_watch.gd")

var _failures := 0


func _ready() -> void:
	_test_line()
	_test_hour()
	_test_wedged()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _test_line() -> void:
	print("\n== the stall's line: none before the first frame or within the wait; then the tick, the last part, the last error ==")
	var watch := TickWatch.new()
	watch.stall_msec = 1000000000  # Its thread never trips here.
	watch.start()
	var now := Time.get_ticks_msec()
	_check(watch.stalled_line(now + 10000000).is_empty(), "no line before World's first frame (loading never trips it)")
	watch.alive(41)
	watch.stall_msec = 30000
	var at := Time.get_ticks_msec()
	_check(watch.stalled_line(at + 29000).is_empty(), "within 30 s of a frame: none")
	watch.note_part("towns")
	watch._logger._log_error("_run", "res://sim/towns.gd", 12, "", "Invalid call. Nonexistent function 'x' in base 'Nil'.",
			false, Logger.ERROR_TYPE_SCRIPT, [])
	var line := watch.stalled_line(at + 31000)
	var ok := line.begins_with("[tick] stalled:") and "since tick 41" in line and "the last part done: towns" in line 			and "SCRIPT ERROR: Invalid call. Nonexistent function 'x' in base 'Nil'. (res://sim/towns.gd:12, _run)" in line
	# The line is shown only on a failure: land.sh fails a scene printing an
	# engine error's words, and this one quotes one.
	_check(ok, "past 30 s: the tick, the last part and the last error named%s" % ("" if ok else ": " + line.replace("ERROR", "E_RROR")))
	watch.alive(42)
	_check(watch.stalled_line(Time.get_ticks_msec() + 1000).is_empty(), "a frame again (a held tick runs frames): no stall")
	watch.stop()
	_check(not watch._thread.is_alive(), "stopped: its thread ended")


func _test_hour() -> void:
	print("\n== the hourly line: the ticks' average and worst ==")
	var watch := TickWatch.new()
	watch.beat(1, 2000)
	watch.beat(2, 4000)
	watch.beat(3, 12000)
	_check(watch.hour_line() == "[tick] avg 6.0 ms, worst 12.0 ms, ticks 3 over the last hour", watch.hour_line())


func _test_wedged() -> void:
	print("\n== a wedged main loop: its watchdog prints the line and ends it ==")
	var output: Array = []
	var started := Time.get_ticks_msec()
	OS.execute(OS.get_executable_path(), ["--log-file", ProjectSettings.globalize_path("res://build/logs/tick_watch_wedge.log"),
		"--headless", "--audio-driver", "Dummy", "--path", ProjectSettings.globalize_path("res://"),
		"--scene", "res://tests/tick_watch_wedge.tscn"], output, true)
	var took := (Time.get_ticks_msec() - started) / 1000.0
	var text := "".join(output)
	_check("[tick] stalled: the main loop stuck" in text and "since tick 7" in text and "the last part done: act: monsters" in text,
			"the stall's line printed (%s)" % text.substr(text.find("[tick]"), 160).strip_edges())
	_check(not "NOT ENDED" in text and took < 60.0, "ended by its watchdog, not by its own end (%.1f s)" % took)
