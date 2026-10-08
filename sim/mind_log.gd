class_name MindLog
extends RefCounted
## The companion minds' decisions, one JSON object a line, for reading back
## what a mind was told and what it said. Server only. The file is
## Net.mind_log_path (--mind-log=, by default /var/lib/psykinetic/mind.log
## on a dedicated server when that directory is there); the console turns
## it on and off (mind log on|off) and shows a companion's last line (mind
## last <name>).
##
## Each line: time (UTC, ISO), tick, companion, mind (which answered),
## trigger, prompt (system prompt and context, as sent), reply (raw), why
## (the mind's own reason, with --mind-why), intent and target as parsed,
## outcome (applied, held, rejected, reflex override, scripted fill-in),
## note (why that outcome), latency_ms.
##
## Rotated: a file that has reached MAX_BYTES becomes <path>.1 (replacing
## the one before) and a new one is started, so the last MAX_BYTES or more
## are kept and at most twice that is on disk.

## Writing is on while there is a path and nobody turned it off.
static var enabled := true
## Companion name -> its last entry, kept whether or not the file is written.
static var last: Dictionary[String, Dictionary] = {}
## Entries written this run, for tests.
static var written := 0
## Rotate at this size (bytes); a var for the tests.
static var max_bytes := 5 * 1024 * 1024


static func record(entry: Dictionary) -> void:
	var stamped := entry.duplicate()
	stamped["time"] = Time.get_datetime_string_from_system(true) + "Z"
	stamped["tick"] = World.tick
	last[str(entry.get("companion", ""))] = stamped
	var path: String = Net.mind_log_path
	if not enabled or path.is_empty():
		return
	var file := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) \
			else FileAccess.open(path, FileAccess.WRITE)
	if file != null and file.get_length() >= max_bytes:
		file.close()
		_rotate(path)
		file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[mind] cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	file.seek_end()
	file.store_line(JSON.stringify(stamped))
	file.close()
	written += 1


static func _rotate(path: String) -> void:
	var old := path + ".1"
	if FileAccess.file_exists(old):
		DirAccess.remove_absolute(old)
	var error := DirAccess.rename_absolute(path, old)
	if error != OK:
		push_warning("[mind] cannot rotate %s (%s)" % [path, error_string(error)])
