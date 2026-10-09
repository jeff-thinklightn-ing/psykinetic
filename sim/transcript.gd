class_name Transcript
extends RefCounted
## What was said to each companion and by her, a plain-text file per
## companion per day: Net.transcripts_dir/<companion>-<YYYY-MM-DD>.txt
## (--transcripts=, by default /var/lib/psykinetic/transcripts on a
## dedicated server when /var/lib/psykinetic is there). One timestamped
## line each, exactly as her voice sees the exchange (Companion._add_turn):
## her player's words, her lines, and events as bracketed notes.
##
##   14:02:11 Jeff: Stay back!
##   14:02:12 [Imp1 fell.]
##   14:02:13 Pip: Done. It won't get up again.
##
## Times and days are the server's local time. Files older than KEEP_DAYS
## are deleted, checked on the first line of each day. The console prints
## one: transcript <name> [<date>].

const KEEP_DAYS := 30
## Lines written this run, for tests.
static var written := 0
static var _pruned_on := ""


## [param companion] heard or said [param text]: [param speaker] is who
## said it ("" for an event, written as it is: "[Imp1 fell.]").
static func record(companion: String, speaker: String, text: String) -> void:
	var dir: String = Net.transcripts_dir
	if dir.is_empty() or companion.is_empty():
		return
	var today := Time.get_date_string_from_system()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	if _pruned_on != today:
		_pruned_on = today
		prune(dir, today)
	var path := path_of(dir, companion, today)
	var file := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) \
			else FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[transcript] cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	var line := text.strip_edges().replace("\n", " ")
	file.seek_end()
	file.store_line("%s %s" % [Time.get_time_string_from_system(), line if speaker.is_empty() else "%s: %s" % [speaker, line]])
	file.close()
	written += 1


static func path_of(dir: String, companion: String, date: String) -> String:
	return dir.path_join("%s-%s.txt" % [companion.validate_filename(), date])


## Deletes transcripts in [param dir] from more than KEEP_DAYS before
## [param today] (YYYY-MM-DD).
static func prune(dir: String, today: String) -> int:
	var day := Time.get_unix_time_from_datetime_string(today)
	var oldest := Time.get_date_string_from_unix_time(day - KEEP_DAYS * 86400)
	var removed := 0
	for file in DirAccess.get_files_at(dir):
		var date := date_in(file)
		if not date.is_empty() and date < oldest:
			if DirAccess.remove_absolute(dir.path_join(file)) == OK:
				removed += 1
	return removed


## The YYYY-MM-DD a transcript's file name ends with, or "".
static func date_in(file: String) -> String:
	if not file.ends_with(".txt") or file.length() < 15:
		return ""
	var date := file.trim_suffix(".txt").right(10)
	return date if is_date(date) and file[file.length() - 15] == "-" else ""


static func is_date(text: String) -> bool:
	var parts := text.split("-")
	return text.length() == 10 and parts.size() == 3 and parts[0].length() == 4 and parts[1].length() == 2 \
			and parts[2].length() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int() and parts[2].is_valid_int()


## The console's transcript command: [param companion]'s transcript of
## [param date] (today for ""), or why there is none.
static func show(companion: String, date := "") -> String:
	var dir: String = Net.transcripts_dir
	if dir.is_empty():
		return "no transcripts kept: --transcripts=<dir>"
	if date.is_empty():
		date = Time.get_date_string_from_system()
	elif not is_date(date):
		return "a date is YYYY-MM-DD"
	var path := path_of(dir, companion, date)
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_string(path).strip_edges(false, true)
	var dates: Array[String] = []
	var prefix := companion.validate_filename() + "-"
	for file in DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray():
		if file.begins_with(prefix) and file.length() == prefix.length() + 14 and not date_in(file).is_empty():
			dates.append(date_in(file))
	dates.sort()
	return "no transcript of %s on %s%s" % [companion, date,
		" (there are: %s)" % ", ".join(dates) if not dates.is_empty() else ""]
