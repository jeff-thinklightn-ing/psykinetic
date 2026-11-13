extends Node
## The suite's own rules (decision 278): tests/run.sh runs a checkout's
## scenes at once, and tests/land.sh runs net_test and state_test beside
## them, so no two may listen on one port or write one scratch folder. This
## reads every script under tests/ and fails, naming both places, on two
## tests with one port (each test_ports.gd of(...) a test calls, or the shell
## tests' "<base> + PORT_OFFSET" and the ports they count from it) or one
## scratch name, and on a test setting Net.port without test_ports.gd.
## 278 amended (2): of(...) is read by any name the file preloads
## test_ports.gd under, its argument a number, a constant of the file's or
## either + k; one it cannot read fails, named (status_test's of(BASE_PORT + 8)
## was camp_fall_test's port and went unseen, 431 amended (3)).
## Run it with tests/run.ps1 or tests/run.sh.

const DIR := "res://tests/"

var _failures := 0


func _ready() -> void:
	var ports := {}  # port -> ["owner", "file:line"]
	var names := {}  # scratch name -> ["owner", "file:line"]
	var bare: Array[String] = []
	var unread: Array[String] = []
	var port_clashes := 0
	var name_clashes := 0
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
		var of_ports := _of_ports(lines) if file.ends_with(".gd") else {}
		for i in lines.size():
			var line := lines[i]
			if line.strip_edges().begins_with("#"):
				continue
			var at := "tests/%s:%d" % [file, i + 1]
			var found: Array[int] = []
			if of_ports.has(i):
				found.append_array(of_ports[i]["ports"])
				for call: String in of_ports[i]["unread"]:
					unread.append("%s: %s" % [at, call])
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
	for at in unread:
		print("    %s: a port this cannot read; use a number, a const of the file's, or either + k" % at)
	_check(unread.is_empty(), "every test_ports.gd of(...) is read")
	_test_of_ports()
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


## The ports a .gd test's [param lines] ask test_ports.gd for, by line index:
## {i: {"ports": [base, ...], "unread": ["of(...)", ...]}} for each line that
## calls of(...) by any name the file preloads test_ports.gd under, with a
## number, a constant of the file's, or either + k; any other argument is
## unread (278 amended (2)).
func _of_ports(lines: PackedStringArray) -> Dictionary:
	var alias := RegEx.create_from_string("(?:var|const)\\s+(\\w+)\\s*:?=\\s*preload\\(\"res://tests/test_ports\\.gd\"\\)")
	var constant := RegEx.create_from_string("^const\\s+(\\w+)\\s*(?::\\s*int\\s*)?:?=\\s*(\\d+)\\s*(#.*)?$")
	var receivers: Array[String] = ["test_ports\\.gd\"\\)"]
	var constants := {}
	for line in lines:
		for hit in alias.search_all(line):
			receivers.append("\\b" + hit.get_string(1))
		var named := constant.search(line.strip_edges())
		if named != null:
			constants[named.get_string(1)] = named.get_string(2).to_int()
	var called := RegEx.create_from_string("(?:%s)\\.of\\(([^()]*)\\)" % "|".join(receivers))
	var form := RegEx.create_from_string("^\\s*(\\w+)\\s*(?:\\+\\s*(\\d+))?\\s*$")
	var out := {}
	for i in lines.size():
		if lines[i].strip_edges().begins_with("#"):
			continue
		for hit in called.search_all(lines[i]):
			var entry: Dictionary = out.get_or_add(i, {"ports": [], "unread": []})
			var parts := form.search(hit.get_string(1))
			var head := parts.get_string(1) if parts != null else ""
			if head.is_valid_int():
				entry["ports"].append(head.to_int() + parts.get_string(2).to_int())
			elif constants.has(head):
				entry["ports"].append(int(constants[head]) + parts.get_string(2).to_int())
			else:
				entry["unread"].append(hit.get_string(0))
	return out


func _test_of_ports() -> void:
	var lines := PackedStringArray([
		"const BASE_PORT := 17000",
		"const OTHER: int = 17100  # a note",
		"var a := preload(\"res://tests/test_ports.gd\").of(17200)",
		"\tvar ports := preload(\"res://tests/test_ports.gd\")",
		"\tNet.port = ports.of(17300)",
		"\tvar b: int = preload(\"res://tests/test_ports.gd\").of(BASE_PORT + 8)",
		"\tvar c := ports.of( OTHER + 2 ) + ports.of(BASE_PORT)",
		"\tvar d := ports.of(port_here)",
		"\t# ports.of(17999) in a comment",
		"\tvar e := Offers.of(\"someone\", pid)",
	])
	var got := _of_ports(lines)
	var want := {2: {"ports": [17200], "unread": []}, 4: {"ports": [17300], "unread": []},
		5: {"ports": [17008], "unread": []}, 6: {"ports": [17102, 17000], "unread": []},
		7: {"ports": [], "unread": ["ports.of(port_here)"]}}
	_check(got == want, "of(...) read by a preloaded name, a constant and + k; a variable unread; Offers.of and comments not ports (%s)" % [got])


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
