extends Node
## A tour (playtest, decision 754): the game's own Main, joined as a client
## to a local server (tools/tour.sh starts both), played by a Bot through the
## client's input paths; the tour named by --tour=<name> is
## tests/tour/tours/<name>.gd, whose run(bot) plays it. Exit code 0 when
## every check passed, 1 when one failed, 2 when it never joined or the tour
## would not load, 3 when it ran past --tour-minutes (default 20).
## --tour-admin=<port>: the server's admin console, for setup.
## --tour-out=<folder>: where report.md and stills go.

const Bot := preload("res://tests/tour/bot.gd")

var _main: Node
var _bot: Node
var _done := false


func _ready() -> void:
	var options := _options()
	var tour_name: String = options.get("tour", "smoke")
	var script_path := "res://tests/tour/tours/%s.gd" % tour_name
	# Loaded before joining: a tour that will not parse fails at once.
	var script: GDScript = load(script_path) if ResourceLoader.exists(script_path) else null
	if script == null or not script.can_instantiate():
		print("RESULT: FAIL (tour %s would not load: %s)" % [tour_name, script_path])
		get_tree().quit(2)
		return
	# At /root/Main, where the server's is: replication finds nodes by path.
	_main = preload("res://main.tscn").instantiate()
	_main.name = "Main"
	get_tree().root.add_child.call_deferred(_main)
	_bot = Bot.new(_main, int(options.get("tour-admin", "0")), String(options.get("tour-out", "")))
	_bot.name = "TourBot"
	add_child(_bot)
	# A stuck tour (a script error mid-await leaves it waiting) ends here.
	get_tree().create_timer(float(options.get("tour-minutes", "20")) * 60.0).timeout.connect(func() -> void:
		_bot.expect(false, "the tour finished in time", "still running after %s minutes" % options.get("tour-minutes", "20"))
		_finish(tour_name, 3))
	_run.call_deferred(tour_name, script)


func _run(tour_name: String, script: GDScript) -> void:
	_bot.log_line("tour %s: joining %s:%d" % [tour_name, Net.address, Net.port])
	if not await _bot.joined():
		_bot.expect(false, "joined the server", "no player after 120 s")
		_finish(tour_name, 2)
		return
	_bot.log_line("joined: zone %s at %s" % [_bot.zone(), _bot.cell()])
	var tour: Object = script.new()
	await tour.run(_bot)
	_finish(tour_name, 0 if _bot.failures() == 0 else 1)


func _finish(tour_name: String, code: int) -> void:
	if _done:
		return
	_done = true
	_bot.write_report(tour_name)
	print("RESULT: %s (tour %s, %d failed)" % ["PASS" if code == 0 else "FAIL", tour_name, _bot.failures()])
	Net.shutdown()
	get_tree().quit(code)


## --key=value pairs among the arguments, for keys that begin with "tour".
func _options() -> Dictionary:
	var out := {}
	for arg: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg.begins_with("--tour") and "=" in arg:
			out[arg.substr(2, arg.find("=") - 2)] = arg.substr(arg.find("=") + 1)
	return out
