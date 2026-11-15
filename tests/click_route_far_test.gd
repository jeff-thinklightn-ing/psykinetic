extends "res://tests/click_route_test.gd"
## click_route_test's far half (decision 935): the agree row in the three
## largest open lands (FAR_ZONES: the hills, foothills and forest), a port of
## its own. Run it with tests/run.sh.


func _port() -> int:
	return preload("res://tests/test_ports.gd").of(17868)


func _far() -> bool:
	return true
