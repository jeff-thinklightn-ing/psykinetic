extends "res://tests/view_test.gd"
## The bodies' part of view_test's list (278 amended (13), cut out of
## view_world_test's, in its order): people and their looks, gear and worn
## pieces, their clips (blows and tells, the gaits, the stops and stands, the
## variation, the held pieces and poses), creatures' clips, and hair and the
## look's pins. The same script with a port of its own, beside view_test and
## view_world_test in the suite; it opens with _as_at_the_cut(), as
## view_world_test does.


func _base_port() -> int:
	return preload("res://tests/test_ports.gd").of(17725)


func _half() -> int:
	return 2
