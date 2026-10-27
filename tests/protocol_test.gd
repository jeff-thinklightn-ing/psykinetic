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
	_test_self_update()
	_test_fingerprint()
	_test_token_from_env()
	_test_token_lockout()
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


func _test_self_update() -> void:
	print("== when a client updates itself (decision 241) ==")
	var dir := preload("res://tests/test_ports.gd").scratch_path("self_update")
	DirAccess.make_dir_recursive_absolute(dir)
	for name in [SelfUpdate.SCRIPT, SelfUpdate.MARKER]:
		DirAccess.remove_absolute(dir.path_join(name))
	var now := int(Time.get_unix_time_from_system())
	var newer := "99.0.0"
	_check(SelfUpdate.refusal("server out of date", newer, dir, now) != "", "never when the server is the one behind")
	_check(SelfUpdate.refusal("client out of date", "0.0.1", dir, now) != "", "never for a server that is not a newer build")
	_check(SelfUpdate.refusal("client out of date", newer, "", now) == "not an exported game", "never run from the editor or a checkout")
	var why := SelfUpdate.refusal("client out of date", newer, dir, now)
	_check(why.begins_with("no update.ps1"), "never without update.ps1 beside the game (%s)" % why)
	FileAccess.open(dir.path_join(SelfUpdate.SCRIPT), FileAccess.WRITE).store_line("# a stand-in")
	why = SelfUpdate.refusal("client out of date", newer, dir, now)
	_check(why == "", "a newer server and update.ps1 there: it updates (%s)" % why)
	FileAccess.open(dir.path_join(SelfUpdate.MARKER), FileAccess.WRITE).store_line("just now")
	why = SelfUpdate.refusal("client out of date", newer, dir, now)
	_check(why.begins_with("it updated"), "but not again within 10 minutes of the last (%s)" % why)
	why = SelfUpdate.refusal("client out of date", newer, dir, now + SelfUpdate.MIN_GAP_SEC + 5)
	_check(why == "", "and again once they are past (%s)" % why)


func _test_fingerprint() -> void:
	print("== protocol() ==")
	var signatures := Net.rpc_signatures(load("res://net/net.gd"))
	_check("authenticate(hello)" in signatures and "rejected(reason,server_version)" in signatures,
		"it takes each RPC with its arguments' names (%s)" % ", ".join(signatures))
	_check(Net.protocol().length() == 12 and Net.protocol() == Net.protocol(), "a 12-character fingerprint, the same each time (%s)" % Net.protocol())


## The service gives the token only in the environment (decision 690): it is
## used when no --token is given, and an explicit --token, read after, wins.
func _test_token_from_env() -> void:
	print("== the token from PSYKINETIC_TOKEN ==")
	var was_token := Net.token
	var was_env := OS.get_environment("PSYKINETIC_TOKEN")
	Net.token = ""
	OS.set_environment("PSYKINETIC_TOKEN", "from-env")
	Net._token_from_env()
	_check(Net.token == "from-env", "no --token: the environment's token is used")
	Net._set_option("--token", "from-flag")
	_check(Net.token == "from-flag", "an explicit --token, read after, overrides it")
	OS.unset_environment("PSYKINETIC_TOKEN")
	Net.token = ""
	Net._token_from_env()
	_check(Net.token == "", "no PSYKINETIC_TOKEN: the token is left alone")
	if was_env != "":
		OS.set_environment("PSYKINETIC_TOKEN", was_env)
	Net.token = was_token


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


## A token guessed at (701): TOKEN_TRIES wrong ones from one address within
## the window lock it out for TOKEN_LOCKOUT_SECONDS; misses spread wider
## than the window never do; another address is not touched.
func _test_token_lockout() -> void:
	print("
== wrong tokens from one address: locked out after %d in %d s, for %d s ==" % [
		Net.TOKEN_TRIES, roundi(Net.TOKEN_WINDOW_SECONDS), roundi(Net.TOKEN_LOCKOUT_SECONDS)])
	var window := roundi(Net.TOKEN_WINDOW_SECONDS * 1000.0)
	var lockout := roundi(Net.TOKEN_LOCKOUT_SECONDS * 1000.0)
	var t0 := 1000000
	var locked := false
	for i in Net.TOKEN_TRIES - 1:
		locked = Net.token_missed("10.0.0.1", t0 + i * 1000) or locked
	_check(not locked and not Net.token_locked("10.0.0.1", t0 + 5000), "%d wrong: still let try" % (Net.TOKEN_TRIES - 1))
	_check(Net.token_missed("10.0.0.1", t0 + 6000) and Net.token_locked("10.0.0.1", t0 + 7000), "the %dth within the window: locked out" % Net.TOKEN_TRIES)
	_check(not Net.token_locked("10.0.0.2", t0 + 7000), "another address: not")
	_check(Net.token_locked("10.0.0.1", t0 + 6000 + lockout - 1000) and not Net.token_locked("10.0.0.1", t0 + 6000 + lockout + 1000),
			"for %d s, then let in again" % roundi(Net.TOKEN_LOCKOUT_SECONDS))
	locked = false
	for i in Net.TOKEN_TRIES * 2:
		locked = Net.token_missed("10.0.0.3", t0 + i * (window / (Net.TOKEN_TRIES - 1) + 1000)) or locked
	_check(not locked, "wrong ones spread wider than the window: never locked out")
	Net._token_misses.clear()
	Net._locked_out.clear()
