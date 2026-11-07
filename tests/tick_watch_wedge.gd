extends Node
## tick_watch_test's child (decision 817): a 3 s tick watchdog, one frame
## at tick 7 after the part "act: monsters", then a main loop that never
## comes back. Its watchdog ends it; "NOT ENDED" if 20 s pass first.


func _ready() -> void:
	var watch := preload("res://sim/tick_watch.gd").new()
	watch.stall_msec = 3000
	watch.start()
	watch.alive(7)
	watch.note_part("act: monsters")
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 20000:
		OS.delay_msec(100)
	print("NOT ENDED")
	watch.stop()
	get_tree().quit(1)
