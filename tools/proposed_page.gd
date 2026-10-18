extends Node
## Rebuilds the proposals list for Jeff, docs/lore/proposed.md (lore's page;
## decision 458), from a world snapshot: the towns' memory logs' entries the
## lawspeaker (448) marked "proposed", rendered by TownMemory.proposed_page,
## keeping the status lines written by hand into the page it overwrites.
## Local or test snapshots only: it never reads the box's world.json (copy
## one down first if that is wanted), and nothing here touches lore's
## entries. A scene, so the autoloads load (the day's length for the day
## numbers); it reads no level and writes nothing but --out. Headless:
##   godot --headless --path <repo> --scene res://tools/proposed_page.tscn -- --snapshot=<world.json> --out=<proposed.md>
## With --chronicle=<town id> it writes that town's chronicle instead (the
## scholar's page, decision 491; TownMemory.chronicle, every memory, no cut),
## the proposals' statuses read from --statuses=<proposed.md> when given.

var _chronicle := ""
var _statuses_from := ""


func _ready() -> void:
	var snapshot := ""
	var out := ""
	var chronicle := ""
	var statuses_from := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snapshot="):
			snapshot = arg.trim_prefix("--snapshot=")
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--chronicle="):
			chronicle = arg.trim_prefix("--chronicle=")
		elif arg.begins_with("--statuses="):
			statuses_from = arg.trim_prefix("--statuses=")
	_chronicle = chronicle
	_statuses_from = statuses_from
	get_tree().quit(_run(snapshot, out))


func _run(snapshot: String, out: String) -> int:
	if snapshot.is_empty() or out.is_empty():
		push_error("proposed_page: --snapshot=<world.json> and --out=<proposed.md> are needed")
		return 2
	if snapshot.begins_with("/var/lib/psykinetic") or snapshot.begins_with("user://"):
		push_error("proposed_page: a local or test snapshot only, never the box's or the shared user:// one")
		return 2
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(snapshot)) if FileAccess.file_exists(snapshot) else null
	if not data is Dictionary:
		push_error("proposed_page: %s is not a snapshot" % snapshot)
		return 1
	var towns: Variant = data.get("towns", {})
	var workers: Variant = data.get("production", {}).get("workers", {}) if data.get("production") is Dictionary else {}
	var logs := {}
	var names := {}
	if towns is Dictionary:
		for town: String in towns:
			var record: Variant = towns[town]
			if record is Dictionary and record.get("memory") is Array:
				logs[town] = record["memory"]
				names[town] = town.get_slice("/", 0)
	var who := func(id: String) -> String:
		var worker: Variant = workers.get(id, {}) if workers is Dictionary else {}
		if not worker is Dictionary or worker.is_empty():
			return id
		var trades: Array = worker.get("trades", [])
		return "%s the %s" % [worker.get("name", id), str(trades[0]).replace("_", " ")] if not trades.is_empty() else str(worker.get("name", id))
	var statuses := TownMemory.proposed_statuses(FileAccess.get_file_as_string(out)) if FileAccess.file_exists(out) else {}
	var page := TownMemory.proposed_page(logs, names, who, statuses)
	if not _chronicle.is_empty():
		# One town's chronicle (decision 491): every memory, its scholar as keeper when it has one.
		if not logs.has(_chronicle):
			push_error("proposed_page: no town %s in the snapshot (towns: %s)" % [_chronicle, ", ".join(logs.keys())])
			return 1
		var keeper := "nobody yet"
		var town_names: Array = []
		if workers is Dictionary:
			for id: String in workers:
				var worker: Variant = workers[id]
				if worker is Dictionary and str(worker.get("town", "")) == _chronicle:
					town_names.append(str(worker.get("name", "")))
					if str(worker.get("type", "")) == "scholar":
						keeper = who.call(id)
		if not _statuses_from.is_empty() and FileAccess.file_exists(_statuses_from):
			statuses = TownMemory.proposed_statuses(FileAccess.get_file_as_string(_statuses_from))
		page = "\n".join(TownMemory.chronicle(logs[_chronicle], names.get(_chronicle, _chronicle), keeper, who, [], statuses, _chronicle, 1000000, 0, town_names)) + "\n"
	var file := FileAccess.open(out, FileAccess.WRITE)
	if file == null:
		push_error("proposed_page: cannot write %s (%s)" % [out, error_string(FileAccess.get_open_error())])
		return 1
	file.store_string(page)
	file.close()
	var count := 0
	for town: String in logs:
		for entry: Variant in logs[town]:
			if entry is Dictionary and bool(entry.get("proposed", false)):
				count += 1
	print("proposed_page: %d proposed in %d towns -> %s" % [count, logs.size(), out])
	return 0
