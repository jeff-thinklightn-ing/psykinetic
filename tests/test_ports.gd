extends RefCounted
## A test's port for this checkout: its base port plus the checkout's offset from
## tests/port_offsets.txt, so worktrees can run their tests at the same time.
## No class_name, so other worktrees need no reimport: preload it.
##   Net.port = preload("res://tests/test_ports.gd").of(<base>)
## Each test's base port is its own: tests/suite_test fails, naming both, on two tests
## (or net_test, state_test) with one base, as the suite runs scenes at once.
## scratch() gives a user:// folder of this checkout's and this scene's own: every
## worktree shares one user:// (the project's), so a fixed "user://x/" lets two trees'
## suites clash, and tests/run.sh runs a checkout's scenes at once (decision 278).
##   var folder: String = preload("res://tests/test_ports.gd").scratch("editor_test/")

const OFFSETS := "res://tests/port_offsets.txt"
## Every offset is a multiple of STEP; tests/suite_test keeps every claimed port's remainder mod
## STEP its own, so no two checkouts' ports meet at any offset difference (278 amended (11)).
const STEP := 200
const UNLISTED_BASE := 5600
const UNLISTED_COUNT := 100


static func of(base: int) -> int:
	return base + offset()


## "user://tests_<checkout folder>/<scene>/<name>": a test's own place under
## user://, the scene being the one run (--scene), left out when there is none.
## Its parent folder is made if missing.
static func scratch(name: String) -> String:
	var running := scene()
	var path := "user://tests_%s/%s%s" % [checkout(), running + "/" if not running.is_empty() else "", name]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return path


## scratch() as an absolute path, for things that want one (a state file, a log).
static func scratch_path(name: String) -> String:
	return ProjectSettings.globalize_path(scratch(name))


## The scene this process runs (its file name without .tscn: "zone_test"), from
## --scene, or "" for none.
static func scene() -> String:
	var args := OS.get_cmdline_args()
	for i in args.size():
		var arg := args[i]
		if arg == "--scene" and i + 1 < args.size():
			return args[i + 1].get_file().get_basename()
		if arg.begins_with("--scene="):
			return arg.trim_prefix("--scene=").get_file().get_basename()
	return ""


## The checkout's folder name: psykinetic, perf, maps, ...
static func checkout() -> String:
	return ProjectSettings.globalize_path("res://").trim_suffix("/").get_file()


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
	return hashed(folder)


## The offset of a folder not listed in tests/port_offsets.txt (278 amended (11)): UNLISTED_BASE
## plus STEP times the md5 of its name, lower-cased, mod UNLISTED_COUNT (its first 8 hex digits).
## The listed offsets stay below the range by more than a step (tests/suite_test checks), so an
## unlisted folder never takes a listed tree's ports; the old byte sum, 1000 + 200 * (sum mod 20),
## always did (animation's scratch "twohands" ran on psykinetic-release's, 11-16). Two unlisted
## folders still meet one time in UNLISTED_COUNT. tests/test_ports.sh and .ps1 give the same.
static func hashed(folder: String) -> int:
	return UNLISTED_BASE + STEP * (folder.to_lower().md5_text().substr(0, 8).hex_to_int() % UNLISTED_COUNT)
