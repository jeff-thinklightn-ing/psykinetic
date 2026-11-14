extends "res://tests/view_test.gd"
## The second half of view_test's list (278 amended (9)): places and decor
## from _test_dais on, water and streams, buildings and doors, people and
## gear, creatures and their clips, music and the options panel. The same
## script with a port of its own, beside view_test in the suite; view_test
## runs the first half (sounds, the camera, the ground's look).


func _base_port() -> int:
	return preload("res://tests/test_ports.gd").of(17723)


func _half() -> int:
	return 1
