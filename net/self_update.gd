class_name SelfUpdate
extends RefCounted
## The client updating itself (decision 241): turned away as "client out of
## date" by a server of a newer build, an exported game starts update.ps1
## beside it, which waits for the game to quit, installs the latest release
## and starts the game again. Never on "server out of date", and never twice
## within MIN_GAP_SEC, by a marker file beside the game, so a release that
## still does not match the server cannot loop.

const MIN_GAP_SEC := 600
const MARKER := "update_marker.txt"
const SCRIPT := "update.ps1"


## The folder of an exported game ("" for one run from the editor or a
## checkout, which never updates itself).
static func game_dir() -> String:
	return OS.get_executable_path().get_base_dir() if OS.has_feature("template") else ""


## Why the game in [param dir] should not update itself now that a server of
## [param server_version] turned it away for [param reason], or "" if it
## should. [param now] is the unix time.
static func refusal(reason: String, server_version: String, dir: String, now: int) -> String:
	if reason != "client out of date":
		return "the server is the one behind" if reason == "server out of date" else reason
	if not Net.newer_version(server_version, Net.claimed_version()):
		return "the server's v%s is not newer than this v%s" % [server_version, Net.claimed_version()]
	if dir.is_empty():
		return "not an exported game"
	if not FileAccess.file_exists(dir.path_join(SCRIPT)):
		return "no %s beside the game" % SCRIPT
	var marker := dir.path_join(MARKER)
	if FileAccess.file_exists(marker):
		var since := now - FileAccess.get_modified_time(marker)
		if since < MIN_GAP_SEC:
			return "it updated %d s ago, and does at most once in %d s" % [since, MIN_GAP_SEC]
	return ""


## Writes the marker and starts update.ps1 from [param dir]; the caller then
## quits. False, starting nothing, if the marker cannot be written (without
## it nothing stops a loop) or PowerShell cannot be started.
static func start(dir: String) -> bool:
	var marker := FileAccess.open(dir.path_join(MARKER), FileAccess.WRITE)
	if marker == null:
		return false
	marker.store_line("v%s updated itself at %s" % [Net.version, Time.get_datetime_string_from_system()])
	marker.close()
	return OS.create_process("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass",
		"-WindowStyle", "Hidden", "-File", dir.path_join(SCRIPT)]) > 0
