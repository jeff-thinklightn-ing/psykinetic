extends "res://tests/view_land_test.gd"
## The second half of view_land_test's list (278 amended (9)): the forest
## floor from _test_forest_floor_whole on, curve passes, clearings, roads,
## worn ground, relief, sight, fields and the world map kept. The same script
## with a port of its own, beside view_land_test in the suite; view_land_test
## runs the first half (the horizon, sky, hills, shores, the forest's edge).


func _base_port() -> int:
	return preload("res://tests/test_ports.gd").of(17724)


func _half() -> int:
	return 1
