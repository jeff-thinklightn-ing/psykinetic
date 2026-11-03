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
## Every player name seen this run (Main adds each on joining), scrubbed from
## entries with the live players' own (decision 781).
static var player_names: Dictionary[String, bool] = {}


## Decision 781: the log keeps no player names. Every string in [param entry]
## but its "companion" has [param keeper]'s name (the companion's own player)
## put as "her player" and any other player's as "a player", whole words
## only. Only the log is scrubbed: the model's prompt is sent as it was.
static func scrub(entry: Dictionary, keeper := "") -> Dictionary:
	var names: Dictionary[String, bool] = player_names.duplicate()
	if World != null:
		for entity: GridEntity in World.entities():
			if entity is Player and not entity.label.is_empty():
				names[entity.label] = true
	if not keeper.is_empty():
		names[keeper] = true
	var ordered: Array = names.keys().filter(func(each: String) -> bool: return each.strip_edges().length() > 1)
	ordered.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	var out := {}
	for key: Variant in entry:
		out[key] = entry[key] if str(key) == "companion" else _scrubbed(entry[key], ordered, keeper)
	return out


static func _scrubbed(value: Variant, names: Array, keeper: String) -> Variant:
	if value is String or value is StringName:
		var text := str(value)
		for each: String in names:
			if each not in text:
				continue
			var pattern := RegEx.create_from_string("(?<![\\w])" + _escaped(each) + "(?![\\w])")
			text = pattern.sub(text, "her player" if each == keeper else "a player", true)
		return text
	if value is Array:
		return (value as Array).map(func(each: Variant) -> Variant: return _scrubbed(each, names, keeper))
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[key] = _scrubbed(value[key], names, keeper)
		return out
	return value


static func _escaped(text: String) -> String:
	var out := ""
	for character in text:
		out += ("\\" + character) if character in ".^$*+?()[]{}|/-\\" else character
	return out


static func record(entry: Dictionary, keeper := "") -> void:
	var stamped := scrub(entry, keeper)
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
