extends "res://tests/view_test.gd"
## The second part of view_test's list (278 amended (9)): places and decor
## from _test_dais on, water and streams, buildings and doors, the
## telegraphs, the every-var check (_test_neighbour_swap), piles, music and
## the options panel. The same script with a port of its own, beside view_test
## and view_bodies_test in the suite; view_test runs the first part (sounds,
## the camera, the ground's look), view_bodies_test the bodies (278 amended
## (13): people, their looks, gear and clips, creatures' clips, hair).


func _base_port() -> int:
	return preload("res://tests/test_ports.gd").of(17723)


func _half() -> int:
	return 1
