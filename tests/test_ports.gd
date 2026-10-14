extends RefCounted
## A test's port for this checkout: its base port plus the checkout's offset from
## tests/port_offsets.txt, so worktrees can run their tests at the same time.
## No class_name, so other worktrees need no reimport: preload it.
##   Net.port = preload("res://tests/test_ports.gd").of(17790)

const OFFSETS := "res://tests/port_offsets.txt"


static func of(base: int) -> int:
	return base + offset()


static func offset() -> int:
	var forced := OS.get_environment("PSYKINETIC_TEST_PORT_OFFSET")
	if forced.is_valid_int():
		return forced.to_int()
	var folder := ProjectSettings.globalize_path("res://").trim_suffix("/").get_file()
	var text := FileAccess.get_file_as_string(OFFSETS)
	for line in text.split("\n"):
		var fields := line.strip_edges().split(" ", false)
		if fields.size() == 2 and fields[0] == folder and fields[1].is_valid_int():
			return fields[1].to_int()
	var total := 0
	for byte in folder.to_utf8_buffer():
		total += byte
	return 1000 + 200 * (total % 20)
