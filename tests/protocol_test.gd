extends Node
## What may join is decided by Net.protocol(), not the build (decision 239),
## so everything that goes over the wire has to be in it. This walks the
## project's scripts and fails, naming the file and line, on a message kind
## not in Net.MESSAGE_KINDS, a script with RPCs not in Net.RPC_SCRIPTS, or a
## property replicate()d that is not in Net.SUBCLASS_REPLICATED (and on
## names listed there that nothing uses any more). It also checks the
## version comparison the join uses, and that protocol() sees RPC
## arguments. Run it with tests/run.ps1 or tests/run.sh.

const SKIP: Array[String] = ["res://.godot", "res://build", "res://tests", "res://tools", "res://addons"]

var _failures := 0


func _ready() -> void:
	World.set_process(false)
	var scripts := _scripts("res://")
	_test_message_kinds(scripts)
	_test_rpc_scripts(scripts)
	_test_replicated(scripts)
	_test_versions()
	_test_fingerprint()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## Every .gd under [param dir] but SKIP's folders: path -> its lines.
func _scripts(dir: String) -> Dictionary:
	var out := {}
	for sub in DirAccess.get_directories_at(dir):
		var path := dir.path_join(sub)
		if path not in SKIP:
			out.merge(_scripts(path))
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			out[dir.path_join(file)] = FileAccess.get_file_as_string(dir.path_join(file)).split("\n")
	return out


func _test_message_kinds(scripts: Dictionary) -> void:
	print("== every message kind sent is in Net.MESSAGE_KINDS ==")
	var call := RegEx.create_from_string("(?:message_to|broadcast_to|broadcast)\\(")
	var literal := RegEx.create_from_string("\"([a-z_]+)\"")
	var found := {}
	var unlisted: Array[String] = []
	for path: String in scripts:
		var lines: PackedStringArray = scripts[path]
		for i in lines.size():
			var line := lines[i]
			if line.strip_edges().begins_with("func ") or line.strip_edges().begins_with("#"):
				continue
			var at := call.search(line)
			if at == null:
				continue
			var kind := literal.search(line, at.get_end())
			if kind == null:
				continue  # A kind passed on in a variable (Net's own helpers).
			found[kind.get_string(1)] = true
			if kind.get_string(1) not in Net.MESSAGE_KINDS:
				unlisted.append("message kind \"%s\" at %s:%d is not in Net.MESSAGE_KINDS (net/net.gd): add it there, which changes protocol()" % [
					kind.get_string(1), path.trim_prefix("res://"), i + 1])
	for line in unlisted:
		print("    " + line)
	_check(unlisted.is_empty(), "every kind sent is listed (%s)" % ", ".join(found.keys()))
	var unused := Net.MESSAGE_KINDS.filter(func(kind: String) -> bool: return not found.has(kind))
	_check(unused.is_empty(), "and every kind listed is sent somewhere (unused: %s)" % [unused])


func _test_rpc_scripts(scripts: Dictionary) -> void:
	print("== every script with RPCs is in Net.RPC_SCRIPTS ==")
	var missing: Array[String] = []
	for path: String in scripts:
		var lines: PackedStringArray = scripts[path]
		for i in lines.size():
			if lines[i].begins_with("@rpc") and path not in Net.RPC_SCRIPTS:
				missing.append("%s:%d has an @rpc, but %s is not in Net.RPC_SCRIPTS (net/net.gd): add it there, which changes protocol()" % [
					path.trim_prefix("res://"), i + 1, path])
				break
	for line in missing:
		print("    " + line)
	_check(missing.is_empty(), "every script with RPCs is listed (%s)" % [Net.RPC_SCRIPTS])


func _test_replicated(scripts: Dictionary) -> void:
	print("== every property replicate()d is in Net.SUBCLASS_REPLICATED ==")
	var call := RegEx.create_from_string("\\breplicate\\(\"([a-z_]+)\"\\)")
	var found := {}
	var unlisted: Array[String] = []
	for path: String in scripts:
		var lines: PackedStringArray = scripts[path]
		for i in lines.size():
			for each in call.search_all(lines[i]):
				found[each.get_string(1)] = true
				if each.get_string(1) not in Net.SUBCLASS_REPLICATED:
					unlisted.append("replicate(\"%s\") at %s:%d is not in Net.SUBCLASS_REPLICATED (net/net.gd): add it there, which changes protocol()" % [
						each.get_string(1), path.trim_prefix("res://"), i + 1])
	for line in unlisted:
		print("    " + line)
	_check(unlisted.is_empty(), "every replicated property is listed (%s)" % ", ".join(found.keys()))
	var unused := Net.SUBCLASS_REPLICATED.filter(func(name: String) -> bool: return not found.has(name))
	_check(unused.is_empty(), "and every one listed is replicated somewhere (unused: %s)" % [unused])


func _test_versions() -> void:
	print("== which build is newer ==")
	_check(Net.newer_version("0.1.140", "0.1.139") and not Net.newer_version("0.1.139", "0.1.140"), "0.1.140 is newer than 0.1.139")
	_check(Net.newer_version("0.2.0", "0.1.999") and Net.newer_version("0.1.10", "0.1.9"), "by number, not by text: 0.2.0 > 0.1.999, 0.1.10 > 0.1.9")
	_check(not Net.newer_version("0.1.139", "0.1.139"), "a build is not newer than itself")
	_check(Net.newer_version("0.0.1", "0.0.0") and Net.newer_version("0.0.1", "nonsense") and not Net.newer_version("", "0.0.1"),
		"a version that does not read as numbers is older than any that does")


func _test_fingerprint() -> void:
	print("== protocol() ==")
	var signatures := Net.rpc_signatures(load("res://net/net.gd"))
	_check("authenticate(hello)" in signatures and "rejected(reason,server_version)" in signatures,
		"it takes each RPC with its arguments' names (%s)" % ", ".join(signatures))
	_check(Net.protocol().length() == 12 and Net.protocol() == Net.protocol(), "a 12-character fingerprint, the same each time (%s)" % Net.protocol())


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
