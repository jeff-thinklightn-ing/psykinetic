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


const REBUILT_START := "[Rebuilt from the mind log: each line is timed when it was first seen.]"
const REBUILT_END := "[End of what was rebuilt.]"


## Rebuilds the transcripts from the mind logs at [param paths] (oldest
## first): every voice ask carries the exchange as it stood, so her
## player's words and the events are all there, though only the last few
## of each ask; overlapping asks are joined. Each day's rebuilt lines go at
## the top of that day's file, between REBUILT_START and REBUILT_END,
## before anything written live; rebuilding again replaces them. The
## console's transcript rebuild.
static func rebuild(paths: Array[String]) -> String:
	var dir: String = Net.transcripts_dir
	if dir.is_empty():
		return "no transcripts kept: --transcripts=<dir>"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var lines_of: Dictionary[String, Array] = {}
	# Her player's name, as last known: asks made while they were down
	# named them "the one you travel with".
	var keepers: Dictionary[String, String] = {}
	var asks := 0
	for path in paths:
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		while file != null and not file.eof_reached():
			var json := JSON.new()
			if json.parse(file.get_line()) != OK or json.data is not Dictionary:
				continue
			var entry: Dictionary = json.data
			var companion := str(entry.get("companion", ""))
			if entry.get("kind") != "voice" or companion.is_empty() or entry.get("prompt") is not String:
				continue
			asks += 1
			var stamp := str(entry.get("time", "")).trim_suffix("Z")
			var at := Time.get_datetime_string_from_unix_time(Time.get_unix_time_from_datetime_string(stamp) + bias)
			var keeper := keeper_in(str(entry["prompt"]))
			if not keeper.is_empty():
				keepers[companion] = keeper
			var seen := exchange_in(str(entry["prompt"]), companion, keepers.get(companion, ""))
			if not lines_of.has(companion):
				lines_of[companion] = []
			_join(lines_of[companion], seen, at)
			var said := str(entry.get("say", ""))
			if entry.get("outcome") == "said" and not said.is_empty():
				# Placed by the next ask, where it stands in its true order
				# (events may come in while she answers); kept as it is
				# if no later ask shows it.
				lines_of[companion].append({"text": "%s: %s" % [companion, said], "at": at, "pending": true})
	var oldest := Time.get_date_string_from_unix_time(
			Time.get_unix_time_from_datetime_string(Time.get_date_string_from_system()) - KEEP_DAYS * 86400)
	var files := 0
	var written_lines := 0
	for companion: String in lines_of:
		# A line first seen later than one after it happened no later than that one.
		var lines: Array = lines_of[companion]
		for i in range(lines.size() - 2, -1, -1):
			if str(lines[i]["at"]) > str(lines[i + 1]["at"]):
				lines[i]["at"] = lines[i + 1]["at"]
		var by_day: Dictionary[String, Array] = {}
		for line: Dictionary in lines_of[companion]:
			var day := str(line["at"]).left(10)
			if day >= oldest:
				if not by_day.has(day):
					by_day[day] = []
				by_day[day].append("%s %s" % [str(line["at"]).substr(11), line["text"]])
		for day: String in by_day:
			if not DirAccess.dir_exists_absolute(dir):
				DirAccess.make_dir_recursive_absolute(dir)
			var path := path_of(dir, companion, day)
			var live := _live_lines(path)
			var first_live := live[0].left(8) if not live.is_empty() else "99:99:99"
			var rebuilt: Array[String] = []
			for line: String in by_day[day]:
				if line.left(8) < first_live:
					rebuilt.append(line)
			if rebuilt.is_empty():
				continue
			var out := FileAccess.open(path, FileAccess.WRITE)
			if out == null:
				return "cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())]
			out.store_line("%s %s" % [rebuilt[0].left(8), REBUILT_START])
			for line in rebuilt:
				out.store_line(line)
			out.store_line("%s %s" % [rebuilt.back().left(8), REBUILT_END])
			for line in live:
				out.store_line(line)
			out.close()
			files += 1
			written_lines += rebuilt.size()
	return "rebuilt %d lines into %d files from %d voice asks" % [written_lines, files, asks]


## The exchange in a voice ask's [param prompt] (Companion.render), a
## transcript line each: "Jeff: ...", "Pip: ...", "[An imp fell.]". An ask
## from before the voice was a chat gives only her player's words, if any.
static func exchange_in(prompt: String, companion: String, known_keeper := "") -> Array[String]:
	var lines: Array[String] = []
	var keeper := keeper_in(prompt)
	if keeper.is_empty():
		keeper = known_keeper
	var turns := RegEx.create_from_string("\\n\\n(user|assistant): ").search_all(prompt)
	if turns.is_empty():
		var words := RegEx.create_from_string("just said to you: \"(.*)\"").search_all(prompt)
		if not words.is_empty() and not keeper.is_empty():
			lines.append("%s: %s" % [keeper, words.back().get_string(1)])
		return lines
	for i in turns.size():
		var end := turns[i + 1].get_start() if i + 1 < turns.size() else prompt.length()
		var content := prompt.substr(turns[i].get_end(), end - turns[i].get_end())
		var mine := turns[i].get_string(1) == "assistant"
		for line in content.split("\n", false):
			var text := line.strip_edges()
			if text.is_empty() or text == "[A moment passes.]":
				continue
			if mine:
				lines.append("%s: %s" % [companion, text])
			elif text.begins_with("["):
				lines.append(text)
			elif RegEx.create_from_string("^[^\\[:][^:]{0,30}: ").search(text) != null:
				lines.append(text)  # Labelled with its speaker already (from v0.1.66).
			elif not keeper.is_empty():
				lines.append("%s: %s" % [keeper, text])
	return lines


## Her player's name in a voice ask's [param prompt], or "" when it does
## not say (or said only "the one you travel with", while they were down).
static func keeper_in(prompt: String) -> String:
	var found := RegEx.create_from_string("You travel with (.+?) by choice\\.").search(prompt)
	if found == null or found.get_string(1) == "the one you travel with":
		return ""
	return found.get_string(1)


## Adds to [param have] what [param seen] holds past the overlap of its
## start with have's end, timed [param at].
static func _join(have: Array, seen: Array[String], at: String) -> void:
	var pending: Array = []
	while not have.is_empty() and have.back().get("pending", false):
		pending.push_front(have.pop_back())
	var said: Dictionary[String, String] = {}
	for line: Dictionary in pending:
		said[str(line["text"])] = str(line["at"])
	var overlap := _overlap(have, seen)
	if overlap == 0 and not pending.is_empty():
		# No overlap: a new exchange (a restart). Her last line stands as logged.
		for line: Dictionary in pending:
			have.append({"text": line["text"], "at": line["at"]})
		overlap = _overlap(have, seen)
	for line in seen.slice(overlap):
		# Her pending line, now in its place, keeps the time she said it.
		have.append({"text": line, "at": said.get(line, at)})


## The most lines [param seen] starts with that [param have] ends with.
static func _overlap(have: Array, seen: Array[String]) -> int:
	for k in range(mini(have.size(), seen.size()), 0, -1):
		var same := true
		for j in k:
			if have[have.size() - k + j]["text"] != seen[j]:
				same = false
				break
		if same:
			return k
	return 0


## A day's file without its rebuilt part: the lines written live.
static func _live_lines(path: String) -> Array[String]:
	var live: Array[String] = []
	if not FileAccess.file_exists(path):
		return live
	var inside := false
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		if line.ends_with(REBUILT_START):
			inside = true
		elif line.ends_with(REBUILT_END):
			inside = false
		elif not inside:
			live.append(line)
	return live


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
	# The name as typed, in any case: she need not be here to be looked up.
	var wanted := path_of(dir, companion, date).get_file().to_lower()
	var files := DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray()
	for file in files:
		if file.to_lower() == wanted:
			return FileAccess.get_file_as_string(dir.path_join(file)).strip_edges(false, true)
	var dates: Array[String] = []
	var prefix := (companion.validate_filename() + "-").to_lower()
	for file in files:
		if file.to_lower().begins_with(prefix) and file.length() == prefix.length() + 14 and not date_in(file).is_empty():
			dates.append(date_in(file))
	dates.sort()
	return "no transcript of %s on %s%s" % [companion, date,
		" (there are: %s)" % ", ".join(dates) if not dates.is_empty() else ""]
