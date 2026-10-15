extends Node
## Every script under tools/ compiles. No suite scene loads the tools, so a change elsewhere
## (a renamed function, a class_name) once left tools/clip.gd failing to parse unnoticed.
## Loading a script compiles it; a parse error prints a SCRIPT ERROR, which fails the run.
## Run it with tests/run.ps1 or tests/run.sh. Prints PASS/FAIL per assertion and quits
## with exit code 1 if any assertion failed, 0 otherwise.

const TOOLS := "res://tools/"

var _failures := 0


func _ready() -> void:
	print("== every tools/*.gd script compiles ==")
	var names := DirAccess.get_files_at(TOOLS)
	var count := 0
	for name in names:
		if not name.ends_with(".gd"):
			continue
		count += 1
		var script := load(TOOLS + name) as GDScript
		_check(script != null and script.can_instantiate(), "tools/%s compiles" % name)
	_check(count > 0, "found tools scripts (%d)" % count)
	print("\nRESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		_failures += 1
