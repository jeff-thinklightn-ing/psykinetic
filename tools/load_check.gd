extends SceneTree
## tools/load_check.sh's loader (278 amended (7); enemy-ai's probe of 11-12):
## each script named after "--" is loaded for real and asked whether it can
## be instanced, in _process, when the project's autoloads (Net, World) are
## in, so a name of theirs compiles as it does in the game. One line a script,
## "LOAD ok <path>" or "LOAD FAIL <path>", then "LOAD_CHECK: PASS|FAIL (...)",
## and the exit is 1 when any failed. The engine's own SCRIPT ERROR lines,
## printed as each loads, say why.

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var paths := OS.get_cmdline_user_args()
	var failed := 0
	for path: String in paths:
		var script := load(path) as Script
		var loaded := script != null and script.can_instantiate()
		print("LOAD %s %s" % ["ok" if loaded else "FAIL", path])
		if not loaded:
			failed += 1
	print("LOAD_CHECK: %s (%d of %d scripts failed to load)" % ["FAIL" if failed > 0 else "PASS", failed, paths.size()])
	quit(1 if failed > 0 else 0)
	return false
