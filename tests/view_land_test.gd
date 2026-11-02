extends "res://tests/view_test.gd"
## The 3D view's sections on the world plane's big outdoor levels (the
## hills, the wilds, the foothills, the castle and the rest, each rebuilt in
## seconds), run as a scene of their own beside view_test in the suite
## (278 amended): view_test.gd's _land() list, its own port.


func _base_port() -> int:
	return preload("res://tests/test_ports.gd").of(17722)


func _land() -> bool:
	return true
