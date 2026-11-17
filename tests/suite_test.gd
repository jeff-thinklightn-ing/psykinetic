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
## 278 amended (11): every offset is a multiple of test_ports.gd's STEP, so two checkouts' ports
## meet only where two claimed ports differ by a multiple of it. Every claimed port (the tests'
## and the shell tools' "<base> + PORT_OFFSET" under tools/) keeps a remainder mod STEP of its
## own and lies in PORT_LOW..PORT_HIGH; every listed offset is a multiple of STEP and stays a
## whole step below the unlisted range (hashed()), whose top stays under 49152 with room.
## Run it with tests/run.ps1 or tests/run.sh.

const DIR := "res://tests/"
const TOOLS := "res://tools/"
## Where every claimed port lies (278 amended (11)).
const PORT_LOW := 17700
const PORT_HIGH := 18099
## The unlisted range's top port stays this far under 49152, the ephemeral range's start.
const TOP_ROOM := 1000

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
	var owned := {}  # owner -> [port, ...] (278 amended (11))
	var files: Array[String] = []
	for file in DirAccess.get_files_at(DIR):
		files.append(DIR + file)
	for file in DirAccess.get_files_at(TOOLS):
		if file.ends_with(".sh") or file.ends_with(".ps1"):
			files.append(TOOLS + file)  # the net tools' shell ports (278 amended (11))
	for full in files:
		var file := full.get_file()
		if not (file.ends_with(".gd") or file.ends_with(".sh") or file.ends_with(".ps1")) or full == DIR + "test_ports.gd":
			continue
		var in_tools := full.begins_with(TOOLS)
		var owner := ("tools/" if in_tools else "") + file.get_basename()  # net_test.sh and net_test.ps1 are one test
		var lines := FileAccess.get_file_as_string(full).split("\n")
		var base := 0
		var of_ports := _of_ports(lines) if file.ends_with(".gd") and not in_tools else {}
		for i in lines.size():
			var line := lines[i]
			if line.strip_edges().begins_with("#"):
				continue
			var at := "%s:%d" % [full.trim_prefix("res://"), i + 1]
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
				var mine: Array = owned.get_or_add(owner, [])
				if not mine.has(port):
					mine.append(port)
			if in_tools:
				continue
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
	_test_remainders(ports, owned)
	_test_offsets(ports.keys())
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


## 278 amended (11): no two claimed ports share a remainder mod STEP, so no two checkouts' ports
## meet at any offset difference; all lie in PORT_LOW..PORT_HIGH.
func _test_remainders(ports: Dictionary, owned: Dictionary) -> void:
	var step: int = preload("res://tests/test_ports.gd").STEP
	print("== no two claimed ports share a remainder mod %d (278 amended (11)) ==" % step)
	var by_rest := {}  # remainder -> port
	var shared := 0
	var outside: Array[String] = []
	for port: int in _sorted_ints(ports.keys()):
		if port < PORT_LOW or port > PORT_HIGH:
			outside.append("%d (%s)" % [port, ports[port][1]])
		var rest := port % step
		if by_rest.has(rest):
			var other: int = by_rest[rest]
			print("    ports %d (%s) and %d (%s) share the remainder %d mod %d: two checkouts %d apart meet on them; move one to a free remainder" % [
				other, ports[other][1], port, ports[port][1], rest, step, port - other])
			shared += 1
		else:
			by_rest[rest] = port
	_check(shared == 0, "every claimed port's remainder mod %d is its own (%d ports, the net tools' among them)" % [step, ports.size()])
	for each in outside:
		print("    port %s lies outside %d..%d" % [each, PORT_LOW, PORT_HIGH])
	_check(outside.is_empty(), "every claimed port lies in %d..%d" % [PORT_LOW, PORT_HIGH])
	# The four pairs exactly a step apart before 278 amended (11) (economy's four bases moved).
	var met: Array[String] = []
	for pair: Array in [["companion_test", "door_day_test"], ["zone_test", "visitor_road_test"],
			["resident_test", "hut_town_test"], ["builder_zone_test", "repair_site_test"]]:
		var mine: Array = owned.get(pair[0], [])
		var theirs: Array = owned.get(pair[1], [])
		if mine.is_empty() or theirs.is_empty():
			met.append("%s or %s claims no port" % pair)
		for a: int in mine:
			for b: int in theirs:
				if (a - b) % step == 0:
					met.append("%s %d, %s %d" % [pair[0], a, pair[1], b])
	_check(met.is_empty(), "companion/door_day, zone/visitor_road, resident/hut_town, builder_zone/repair_site meet at no offset difference %s" % [met])


## 278 amended (11): the listed offsets are multiples of STEP and stay a whole step below every
## unlisted one; hashed() is a real hash of the name (the cases test_ports.sh and .ps1 are held
## to as well, tests/port_hash_cases.txt) and its top stays under 49152.
func _test_offsets(claimed: Array) -> void:
	var tp := preload("res://tests/test_ports.gd")
	print("== listed offsets below the unlisted range; unlisted by md5 (278 amended (11)) ==")
	var listed := {}
	var bad: Array[String] = []
	for line in FileAccess.get_file_as_string(tp.OFFSETS).split("\n"):
		var fields := line.strip_edges().split(" ", false)
		if fields.size() != 2 or line.begins_with("#"):
			continue
		if not fields[1].is_valid_int() or fields[1].to_int() < 0 or fields[1].to_int() % tp.STEP != 0:
			bad.append(line.strip_edges())
		else:
			listed[fields[0]] = fields[1].to_int()
	_check(bad.is_empty() and listed.size() > 10, "%d listed offsets, each a multiple of %d %s" % [listed.size(), tp.STEP, bad])
	var low: int = _sorted_ints(claimed)[0]
	var high: int = _sorted_ints(claimed)[-1]
	var top_listed: int = _sorted_ints(listed.values())[-1]
	var listed_ports := {}
	for offset: int in listed.values():
		for port: int in claimed:
			listed_ports[port + offset] = true
	var touched := 0
	for k in tp.UNLISTED_COUNT:
		for port: int in claimed:
			if listed_ports.has(port + tp.UNLISTED_BASE + tp.STEP * k):
				touched += 1
	_check(touched == 0 and high + top_listed + tp.STEP <= low + tp.UNLISTED_BASE,
		"no listed checkout's port is any unlisted one's: the highest listed %d, the lowest unlisted %d, more than a step apart" % [high + top_listed, low + tp.UNLISTED_BASE])
	var top: int = high + tp.UNLISTED_BASE + tp.STEP * (tp.UNLISTED_COUNT - 1)
	_check(top <= 49152 - TOP_ROOM, "the unlisted range's top port %d stays %d under 49152" % [top, TOP_ROOM])
	var cases := {}
	var wrong: Array[String] = []
	for line in FileAccess.get_file_as_string("res://tests/port_hash_cases.txt").split("\n"):
		var fields := line.strip_edges().split(" ", false)
		if fields.size() == 2 and not line.begins_with("#"):
			cases[fields[0]] = fields[1].to_int()
			if tp.hashed(fields[0]) != fields[1].to_int():
				wrong.append("%s: %d, the case says %s" % [fields[0], tp.hashed(fields[0]), fields[1]])
	_check(wrong.is_empty() and cases.size() >= 6, "hashed() gives each of port_hash_cases.txt's %d names its offset, as test_ports.sh and .ps1 must %s" % [cases.size(), wrong])
	_check(not listed.has("twohands") and not listed.values().has(tp.hashed("twohands")),
		"animation's scratch twohands no longer takes psykinetic-release's offset (the old byte sum's 3400) or any listed one (%d)" % tp.hashed("twohands"))
	_check(tp.hashed("wtrack") != tp.hashed("envfill"), "two names the old byte sum put together (wtrack, envfill: both 3400) now differ (%d, %d)" % [tp.hashed("wtrack"), tp.hashed("envfill")])
	_check(tp.hashed("perf-abc") != tp.hashed("perf-cba") and tp.hashed("maps-den") != tp.hashed("maps-ned"),
		"an anagram pair differs (perf-abc %d, perf-cba %d; maps-den %d, maps-ned %d)" % [tp.hashed("perf-abc"), tp.hashed("perf-cba"), tp.hashed("maps-den"), tp.hashed("maps-ned")])
	_check(tp.hashed("Perf-Ports") == tp.hashed("perf-ports"), "one case: a name's offset is its lower-cased name's (%d)" % tp.hashed("Perf-Ports"))


func _sorted_ints(keys: Array) -> Array[int]:
	var out: Array[int] = []
	for key: Variant in keys:
		out.append(int(key))
	out.sort()
	return out


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
