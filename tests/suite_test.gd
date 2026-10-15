extends Node
## The suite's own rules (decision 278): tests/run.sh runs a checkout's
## scenes at once, and tests/land.sh runs net_test and state_test beside
## them, so no two may listen on one port or write one scratch folder. This
## reads every script under tests/ and fails, naming both places, on two
## tests with one base port (test_ports.gd's of(<base>), or the shell
## tests' "<base> + PORT_OFFSET" and the ports they count from it) or one
## scratch name, and on a test setting Net.port without test_ports.gd.
## Run it with tests/run.ps1 or tests/run.sh.

const DIR := "res://tests/"

var _failures := 0


func _ready() -> void:
	var ports := {}  # port -> ["owner", "file:line"]
	var names := {}  # scratch name -> ["owner", "file:line"]
	var bare: Array[String] = []
	var port_clashes := 0
	var name_clashes := 0
	var of_base := RegEx.create_from_string("test_ports\\.gd\"\\)\\.of\\((\\d+)\\)")
	var shell_base := RegEx.create_from_string("(\\d{5}) \\+ \\$?(PORT_OFFSET|portOffset)")
	var shell_more := RegEx.create_from_string("\\$?(PORT|port) \\+ (\\d+)")
	var scratch := RegEx.create_from_string("scratch(_path)?\\(\"([^\"]+)\"\\)")
	var literal_port := RegEx.create_from_string("Net\\.port = \\d")
	for file in DirAccess.get_files_at(DIR):
		if not (file.ends_with(".gd") or file.ends_with(".sh") or file.ends_with(".ps1")) or file == "test_ports.gd":
			continue
		var owner := file.get_basename()  # net_test.sh and net_test.ps1 are one test
		var lines := FileAccess.get_file_as_string(DIR + file).split("\n")
		var base := 0
		for i in lines.size():
			var line := lines[i]
			if line.strip_edges().begins_with("#"):
				continue
			var at := "tests/%s:%d" % [file, i + 1]
			var found: Array[int] = []
			for hit in of_base.search_all(line):
				found.append(hit.get_string(1).to_int())
			var shell := shell_base.search(line)
			if shell != null:
				base = shell.get_string(1).to_int()
				found.append(base)
			elif base > 0:
				for hit in shell_more.search_all(line):
					found.append(base + hit.get_string(2).to_int())
			for port in found:
				port_clashes += _claim(ports, port, owner, at, "port %d" % port)
			for hit in scratch.search_all(line):
				name_clashes += _claim(names, hit.get_string(2), owner, at, "scratch name %s" % hit.get_string(2))
			if file.ends_with(".gd") and literal_port.search(line) != null:
				bare.append(at)
	print("== every test listens on ports of its own ==")
	_check(port_clashes == 0 and ports.size() > 10, "%d ports, each one test's (%s)" % [ports.size(), ", ".join(_sorted(ports.keys()))])
	print("== every test writes scratch folders of its own ==")
	_check(name_clashes == 0 and names.size() > 10, "%d scratch names, each one test's" % names.size())
	print("== no test picks a port without test_ports.gd ==")
	for at in bare:
		print("    %s sets Net.port to a number: use preload(\"res://tests/test_ports.gd\").of(<base>)" % at)
	_check(bare.is_empty(), "every Net.port comes from test_ports.gd")
	_check(preload("res://tests/test_ports.gd").scene() == "suite_test", "test_ports.gd knows the scene it runs in (%s)" % preload("res://tests/test_ports.gd").scene())
	var path: String = preload("res://tests/test_ports.gd").scratch("x.json")
	_check(path.ends_with("/suite_test/x.json"), "and puts it in scratch paths (%s)" % path)
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## [param what] at [param at] belongs to [param owner]: 1, printing both
## places, if another owner had it already, else 0.
func _claim(claims: Dictionary, key: Variant, owner: String, at: String, what: String) -> int:
	if not claims.has(key):
		claims[key] = [owner, at]
	elif claims[key][0] != owner:
		print("    %s: %s and %s: give one of them another" % [what, claims[key][1], at])
		return 1
	return 0


func _sorted(keys: Array) -> Array[String]:
	keys.sort()
	var out: Array[String] = []
	for key: Variant in keys:
		out.append(str(key))
	return out


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
