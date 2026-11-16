class_name BuilderHost
extends Node
## Builder mode on the server (or a host): a player allowed to build picks
## an area and asks for something there; this runs their BuilderSession
## (one a player, Claude through ClaudeClient, or StubClaude with
## --builder-stub), sends them the proposal to show as a ghost, and on
## accept lays it on the zone's MapDoc (one undo step), saves the level to
## the overlay (Level.overlay_dir: an exported server cannot write its
## levels), and has Main reload the zone and send everyone in it the new
## terrain. Undo takes back the zone's last change the same way.
##
## Who may build: a host's own player, and the player ids in --builders
## (PSYKINETIC_BUILDERS). It is on only with ANTHROPIC_API_KEY in the
## server's environment, or --builder-stub.
##
## Commands from a client (World.command "builder"): {op: "ask", area:
## [x, y, w, h], text}, {op: "accept"}, {op: "discard"}, {op: "undo"}.
## Answers to that client (message "builder"): {state: "working" |
## "proposal" (summary, parts (885: [{head, lines, fault}...], the
## summary for the answer panel; an old client reads summary alone), cost, total, area, cells: [[x, y, meaning]...],
## edges: [[x, y, side, kind]...], new_area: {name, side, size, footprint:
## [x, y, w, h] beyond the edge} when one is proposed) | "error" (error) | "accepted" |
## "discarded" | "undone" | "nothing"}.

## The biggest area one request may cover.
const MAX_AREA := Vector2i(64, 64)
const MAX_TEXT := 500

## Main: reload_zone(name), and the peer -> player id map.
var main: Node
var claude: ClaudeClient
var sessions: Dictionary[int, BuilderSession] = {}
## A session's zone, by peer.
var _session_zone: Dictionary[int, String] = {}
var docs: Dictionary[String, MapDoc] = {}
var spent := 0.0
## Levels made with new_area since the server started: name -> {parent,
## side}. Undone (its neighbour gone from the parent), the level is removed.
var created: Dictionary[String, Dictionary] = {}
## Tests: what the stub does instead of its own script ([] for its own).
var test_turns: Array = []


## Whether builder mode can run here: a key, or the stub.
static func available() -> bool:
	return Net.builder_stub or OS.get_environment("ANTHROPIC_API_KEY") != ""


func _ready() -> void:
	claude = ClaudeClient.new()
	add_child(claude)
	print("[builder] on (%s; builders: host%s)" % ["stub" if Net.builder_stub else Net.builder_model,
		", " + ", ".join(Net.builders) if not Net.builders.is_empty() else ""])


## Says, at boot, which levels the game reads from the overlay instead of
## levels/: a warning for each edited in the game, not yet copied back into
## the repo; a plain line for each the regenerator laid (199 amended (2)).
static func warn_overlays() -> void:
	for line: Dictionary in boot_lines():
		if line["warn"]:
			push_warning(line["text"])
		else:
			print(line["text"])


## warn_overlays' lines, in name order: [{warn: an edit's warning, else a
## laid generation's plain line; text}].
static func boot_lines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for level_name in Level.overlay_names():
		if laid_generation(level_name).is_empty():
			out.append({"warn": true, "text": "[builder] %s is read from %s (edited in the game), not from %s: \"builder export\", then \"builder drop %s\" once it is in the repo" % [
				level_name, ProjectSettings.globalize_path(Level.overlay_dir + level_name), Level.DIR + level_name, level_name]})
		else:
			out.append({"warn": false, "text": "[builder] " + laid_line(level_name)})
	return out


## 199 amended (2): the overlay's level.json of level [param level_name] when
## it is a laid generation, the regenerator's (a "regenerate" block in it:
## Regen.write's own test, which writes over such a level and refuses any
## other), else {} (an edit made in the game, or no overlay).
static func laid_generation(level_name: String) -> Dictionary:
	var path := Level.overlay_dir + level_name + "/level.json"
	var there: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return there if there is Dictionary and (there as Dictionary).get("regenerate") is Dictionary else {}


## The overlay's levels by kind: {"edited": made in the game, "laid": the
## regenerator's generations}, each sorted.
static func overlay_kinds() -> Dictionary:
	var edited: Array[String] = []
	var laid: Array[String] = []
	for level_name in Level.overlay_names():
		(edited if laid_generation(level_name).is_empty() else laid).append(level_name)
	return {"edited": edited, "laid": laid}


## "edited levels: ...; laid generations: ..." for the console's lines.
static func overlay_summary() -> String:
	var kinds := overlay_kinds()
	var named := func(names: Array[String]) -> String: return ", ".join(names) if not names.is_empty() else "none"
	return "edited levels: %s; laid generations: %s" % [named.call(kinds["edited"]), named.call(kinds["laid"])]


## Level [param level_name]'s laid generation in one line: its number, the
## template it was laid from (Regen.write's "laid_from" mark, 465 amended
## (4), its first 8) and when its level.json was written (UTC).
static func laid_line(level_name: String) -> String:
	var config := laid_generation(level_name)
	var mark := str(config.get("laid_from", ""))
	var written := FileAccess.get_modified_time(Level.overlay_dir + level_name + "/level.json")
	return "%s is a laid generation (generation %d), from the template of %s, written %s UTC" % [level_name,
		int(config.get("generation", 0)), mark.left(8) if not mark.is_empty() else "before 465 amended (4) (no mark)",
		Time.get_datetime_string_from_unix_time(written, true)]


func allowed(peer: int, player_id: String) -> bool:
	return peer == Net.local_id or player_id in Net.builders


## The zone's doc, opened the first time.
func doc_of(zone_name: String) -> MapDoc:
	if not docs.has(zone_name):
		var doc := MapDoc.from_level(zone_name)
		if doc == null:
			return null
		docs[zone_name] = doc
	return docs[zone_name]


## A builder command from [param peer] (player [param player_id], in
## [param zone_name]); see the class doc.
func command(peer: int, player_id: String, zone_name: String, args: Dictionary) -> void:
	if not allowed(peer, player_id):
		_reply(peer, {"state": "error", "error": "you may not build on this server"})
		return
	match str(args.get("op", "")):
		"ask":
			await _ask(peer, player_id, zone_name, args)
		"accept":
			_accept(peer, player_id)
		"discard":
			if sessions.has(peer) and sessions[peer].busy:
				# 867 amended (1): kept to the ask's end, "discarded" said then (_ask).
				sessions[peer].discard()
				return
			if sessions.has(peer):
				sessions[peer].discard()
			_reply(peer, {"state": "discarded"})
		"undo":
			_undo(peer, player_id, zone_name)
		_:
			_reply(peer, {"state": "error", "error": "no builder op \"%s\"" % args.get("op", "")})


func _ask(peer: int, player_id: String, zone_name: String, args: Dictionary) -> void:
	var given: Variant = args.get("area")
	var text := str(args.get("text", "")).strip_edges().left(MAX_TEXT)
	if not given is Array or (given as Array).size() != 4 or text.is_empty():
		_reply(peer, {"state": "error", "error": "an area and a request, please"})
		return
	var doc := doc_of(zone_name)
	if doc == null:
		_reply(peer, {"state": "error", "error": "no level %s" % zone_name})
		return
	var area := Rect2i(int(given[0]), int(given[1]), clampi(int(given[2]), 1, MAX_AREA.x), clampi(int(given[3]), 1, MAX_AREA.y))
	area = area.intersection(Rect2i(Vector2i.ZERO, doc.map.size))
	if area.size == Vector2i.ZERO:
		_reply(peer, {"state": "error", "error": "the area is off the map"})
		return
	var session: BuilderSession = sessions.get(peer)
	if session != null and session.busy:
		_reply(peer, {"state": "error", "error": "still working on the last request"})
		return
	if session == null or session.area != area or _session_zone.get(peer, "") != zone_name or session.doc != doc:
		session = BuilderSession.new(doc, area, zone_name, (StubClaude.new(test_turns) if not test_turns.is_empty() else _stub_for(area, text, doc.map.size, BuilderSession.is_dungeon(doc.config), doc.config.get("places", {}))) if Net.builder_stub else claude)
		session.model = Net.builder_model
		session.effort = Net.builder_effort
		session.max_cost = Net.builder_max_cost
		sessions[peer] = session
		_session_zone[peer] = zone_name
	claude.log_tag = "%s in %s" % [player_id, zone_name]
	_reply(peer, {"state": "working"})
	# 867 amended (1): once a reply's tool calls start, the builder's panel says "Checking:".
	session.on_checking = func() -> void: _reply(peer, {"state": "working", "checking": true})
	# 933: the world map this host runs on now (a new one adopted on an accept or a regeneration), asked at
	# each of the ask's steps on the main thread: the session never builds its own, nor names Main.
	session.world_map_of = func() -> WorldMap: return main._world_map if main != null and "_world_map" in main else null
	var result: Dictionary = await session.ask(text)
	spent += float(result["cost"])
	print("[builder] %s in %s %s: \"%s\" -> %s, $%.4f (session $%.4f, %d in, %d out; server $%.4f)" % [player_id, zone_name,
		[area.position.x, area.position.y, area.size.x, area.size.y], text, "ok" if result["ok"] else result["error"],
		result["cost"], session.usage["cost"], session.usage["input"] + session.usage["cache_read"] + session.usage["cache_write"],
		session.usage["output"], spent])
	if result.get("discarded", false):
		_reply(peer, {"state": "discarded"})  # Esc came while it ran, done now (867 amended (1)).
		return
	var proposed := session.proposal()
	if not result["ok"] and proposed["cells"].is_empty() and proposed["edges"].is_empty() and proposed["heights"].is_empty():
		_reply(peer, {"state": "error", "error": result["error"]})
		return
	var reply := proposal_message(session)
	await BuilderSession.breathe()
	var parts := answer_parts(session, result)
	reply["summary"] = summary_of(parts)
	reply["parts"] = panel_parts(parts, building_codes_of(session))
	reply["cost"] = result["cost"]
	reply["total"] = session.usage["cost"]
	_reply(peer, reply)


## The answer's parts' heads (885). A layout fault keeps the proposal from
## being accepted; the rest are told.
const STORE_HEAD := "The town's store"
const HEIGHTS_HEAD := "Heights"
const SITES_HEAD := "Work sites"
const STREETS_HEAD := "Streets"
const SPOTS_HEAD := "Spots, who comes"
const ARRIVALS_HEAD := "Arrivals (a player coming in there lands inside a fight)"
const LAYOUT_HEAD := "Layout (can't be accepted until fixed)"
## The stub's "slow " hold, in the server's frames (about 15 s at 60).
const STUB_SLOW_FRAMES := 900
## The panel's order after Claude's words and the fault (ui-design's mock, 885).
const PANEL_ORDER: Array[String] = [STORE_HEAD, STREETS_HEAD, SITES_HEAD, SPOTS_HEAD, HEIGHTS_HEAD, ARRIVALS_HEAD]


## An answer as parts (885), in the summary's order: Claude's words first
## (head "", one line: the words, and the error when it stopped short), then
## each check's lines under its head, {head, lines, fault}; a check with
## nothing to say has no part.
static func answer_parts(session: BuilderSession, result: Dictionary) -> Array:
	var parts: Array = [{"head": "", "lines": [str(result["summary"]) + ("" if result["ok"] else "\n(" + str(result["error"]) + ")")], "fault": false}]
	var add := func(head: String, lines: Array, fault := false) -> void:
		if not lines.is_empty():
			parts.append({"head": head, "lines": lines.map(func(line: Variant) -> String: return str(line)), "fault": fault})
	add.call(STORE_HEAD, result.get("warnings", []))
	add.call(HEIGHTS_HEAD, result.get("height_warnings", []))
	add.call(SITES_HEAD, result.get("site_warnings", []))
	add.call(STREETS_HEAD, result.get("street_warnings", []))
	# Who comes to the spots the proposal lays or changes (859), before Enter.
	if str(session.working.config.get("spots")) != str(session.doc.config.get("spots")):
		add.call(SPOTS_HEAD, session.spot_preview())
	add.call(ARRIVALS_HEAD, result.get("arrival_warnings", []))
	add.call(LAYOUT_HEAD, result.get("layout_warnings", []), true)
	return parts


## The proposal's "summary" (one string, as before 885, whole for an old
## client: release's condition): the words, then a line a part,
## "Head: line; line".
static func summary_of(parts: Array) -> String:
	var out := str(parts[0]["lines"][0]) if not parts.is_empty() else ""
	for part: Dictionary in parts.slice(1):
		out += "\n%s: %s" % [part["head"], "; ".join(PackedStringArray(part["lines"]))]
	return out


## The codes of the buildings the session's level has, before and after.
static func building_codes_of(session: BuilderSession) -> Array[String]:
	var codes: Array[String] = []
	for config: Dictionary in [session.doc.config, session.working.config]:
		for entry: Variant in config.get("buildings", []):
			var code := str(entry.get("code", "")) if entry is Dictionary else ""
			if not code.is_empty() and code not in codes:
				codes.append(code)
	return codes


## The proposal's "parts" for the panel (885; ui-design's mock): Claude's
## words, then the layout fault, then the rest in PANEL_ORDER. A line a fault
## already says is not said again under its own head (the coordinator's note
## on the mock). Each of [param codes] standing alone in a part's line is
## marked "[T1]", so the panel draws it as a chip (UiCodeChip) and T1 never
## reads "Ti"; Claude's words are left as they are said.
static func panel_parts(parts: Array, codes: Array[String]) -> Array:
	if parts.is_empty():
		return []
	var faults: Array = []
	for part: Dictionary in parts:
		if part["fault"]:
			faults.append_array(part["lines"])
	var ordered: Array = [parts[0]]
	ordered.append_array(parts.filter(func(part: Dictionary) -> bool: return part["fault"]))
	for head in PANEL_ORDER:
		for part: Dictionary in parts:
			if part["head"] == head and not part["fault"]:
				var lines: Array = (part["lines"] as Array).filter(func(line: String) -> bool: return line not in faults)
				if not lines.is_empty():
					ordered.append({"head": head, "lines": lines, "fault": false})
	var marks: RegEx = null
	if not codes.is_empty():
		marks = RegEx.create_from_string("(?<![\\w\\[])(" + "|".join(codes) + ")(?![\\w\\]])")
	var out: Array = []
	for part: Dictionary in ordered:
		var lines: Array = part["lines"]
		if marks != null and not str(part["head"]).is_empty():
			lines = lines.map(func(line: String) -> String: return marks.sub(line, "[$1]", true))
		out.append({"head": part["head"], "lines": lines, "fault": part["fault"]})
	return out


## [param session]'s proposal as the "builder" message's fields.
## The townsfolk spots in the session's area for the ghost (859 amended
## (2)): [[x, y, face_x, face_y, pose, use, state]...], state "new" (none on
## its cell in the level), "changed", "kept" (in the level as it is, drawn
## fainter, so the whole place shows while spots are laid) or "gone" (in the
## level, taken away). [] when the area has none either side.
static func proposal_spots(session: BuilderSession) -> Array:
	var had := {}
	for spot: Dictionary in Level.spots_from(session.doc.config, [] as Array[String]):
		if session.area.has_point(spot["cell"]):
			had[spot["cell"]] = spot
	var out: Array = []
	var row := func(spot: Dictionary, state: String) -> Array:
		var cell: Vector2i = spot["cell"]
		var face: Vector2i = spot["face"]
		return [cell.x, cell.y, face.x, face.y, spot["pose"], spot["use"], state]
	var now := {}
	for spot: Dictionary in Level.spots_from(session.working.config, [] as Array[String]):
		if not session.area.has_point(spot["cell"]):
			continue
		now[spot["cell"]] = true
		var was: Variant = had.get(spot["cell"])
		out.append(row.call(spot, "new" if was == null else ("kept" if str(was) == str(spot) else "changed")))
	for cell: Vector2i in had:
		if not now.has(cell):
			out.append(row.call(had[cell], "gone"))
	return out


static func proposal_message(session: BuilderSession) -> Dictionary:
	var proposal := session.proposal()
	var cells: Array = []
	for at: Vector2i in proposal["cells"]:
		cells.append([at.x, at.y, proposal["cells"][at]])
	for at: Vector2i in proposal["covers"]:
		if not proposal["cells"].has(at):
			cells.append([at.x, at.y, session.working.map.cell(at)])  # Its settings changed.
	var edges: Array = []
	for key: Vector3i in proposal["edges"]:
		edges.append([key.x, key.y, key.z, proposal["edges"][key]])
	var heights: Array = []
	for at: Vector2i in proposal["heights"]:
		heights.append([at.x, at.y, proposal["heights"][at]])
	var message := {"state": "proposal", "area": [session.area.position.x, session.area.position.y, session.area.size.x, session.area.size.y],
		"cells": cells, "edges": edges, "heights": heights}
	# Roofs the proposal adds or changes, outlined (decision 364's records).
	if proposal.get("config", {}).has("roofs"):
		var roofs: Array = []
		for entry: Variant in proposal["config"]["roofs"]:
			var rect: Variant = Level.town_wall_rect(entry)
			if rect != null and not session.doc.config.get("roofs", []).has(entry):
				roofs.append([rect.position.x, rect.position.y, rect.size.x, rect.size.y])
		message["roofs"] = roofs
	var spots := proposal_spots(session)
	if not spots.is_empty():
		message["spots"] = spots
	if proposal.has("new_area"):
		var plan: Dictionary = proposal["new_area"]
		var footprint: Rect2i = plan["footprint"]
		message["new_area"] = {"name": plan["name"], "side": plan["side"], "size": [plan["size"].x, plan["size"].y],
			"footprint": [footprint.position.x, footprint.position.y, footprint.size.x, footprint.size.y]}
	return message


## What an accept or undo in a zone whose last one is still being laid is refused with (956; voice's words).
const LAYING_SAYS := "another change to this level is still being saved; try again in a moment"


func _accept(peer: int, player_id: String) -> void:
	var session: BuilderSession = sessions.get(peer)
	if session == null or session.busy:
		_reply(peer, {"state": "nothing"})
		return
	var zone_name: String = _session_zone[peer]
	if laying.has(zone_name):
		_reply(peer, {"state": "error", "error": LAYING_SAYS})
		return
	# 956: laid off the frame, but a new level beyond an edge (two levels saved, the coordinator's ruling:
	# today's path) and --builder-inline (933's switch, the old path whole).
	if Net.builder_inline or not session.new_area.is_empty():
		_accept_inline(peer, player_id, session, zone_name)
		return
	# Frame A: the stale check as accept() makes it; the change's proposal, and the level's own faults
	# when they are kept, read here; the rest on the worker, from a copy of the doc.
	var began_a := Time.get_ticks_usec()
	if session._doc_read().revision != session.based_on:
		_reply(peer, {"state": "error", "error": BuilderSession.STALE_SAYS})
		return
	var changes := session.proposal()  # Once: spots_only() would make it again.
	var spots_alone := BuilderSession.spots_only_of(changes)
	var doc: MapDoc = docs[zone_name]
	_start_laying({"kind": "accept", "peer": peer, "player_id": player_id, "zone": zone_name, "spots": spots_alone,
		"changes": changes, "baseline": null if spots_alone else session.kept_layout_faults(), "doc": doc,
		"began_a": began_a})


func _accept_inline(peer: int, player_id: String, session: BuilderSession, zone_name: String) -> void:
	var plan := session.new_area.duplicate()
	var spots_alone := session.spots_only()  # Before accept: after it the proposal is the level's own.
	if not session.accept():
		# 806: a layout fault the change adds keeps it off the level.
		_reply(peer, {"state": "error", "error": session.refused} if not session.refused.is_empty() else {"state": "nothing"})
		return
	if session.created_doc != null:
		# The new level first, so the way to it never leads nowhere.
		if not session.created_doc.save(false):
			push_warning("[builder] " + session.created_doc.report)
		created[session.created] = {"parent": zone_name, "side": plan["side"]}
		print("[builder] %s made a new level, %s (%d x %d), beyond the %s edge of %s" % [player_id, session.created,
			plan["size"].x, plan["size"].y, plan["side"], zone_name])
	var saved := _save_spots(zone_name) if spots_alone and session.created_doc == null else _save_and_reload(zone_name)
	if not saved:
		_reply(peer, {"state": "error", "error": "could not save: %s" % session.doc.report})
		return
	print("[builder] %s accepted their change to %s%s" % [player_id, zone_name, " (spots only)" if spots_alone else ""])
	_reply(peer, {"state": "accepted"})


func _undo(peer: int, player_id: String, zone_name: String) -> void:
	var doc: MapDoc = docs.get(zone_name)
	if doc == null or doc.undo_steps.is_empty():
		_reply(peer, {"state": "nothing"})
		return
	if laying.has(zone_name):
		_reply(peer, {"state": "error", "error": LAYING_SAYS})
		return
	# A new level the step made goes with it: not while anyone is in it.
	for level_name: String in created:
		if created[level_name]["parent"] == zone_name and doc.undo_steps.back().has("config neighbours") \
				and not World.peers_in(level_name).is_empty():
			_reply(peer, {"state": "error", "error": "someone is in %s: it cannot be taken back now" % level_name})
			return
	if not Net.builder_inline:
		_start_laying({"kind": "undo", "peer": peer, "player_id": player_id, "zone": zone_name, "spots": false,
			"changes": {}, "baseline": [], "doc": doc})
		return
	doc.undo()
	for each: int in sessions:
		if _session_zone.get(each, "") == zone_name:
			sessions[each].discard()
	if not _save_and_reload(zone_name):
		_reply(peer, {"state": "error", "error": "could not save: %s" % doc.report})
		return
	_forget_created(zone_name, doc)
	print("[builder] %s took back the last change to %s" % [player_id, zone_name])
	_reply(peer, {"state": "undone"})


## The levels a new_area of [param zone_name]'s made that its doc's neighbours no longer name (an undo
## took the step that made one back): forgotten and their overlay removed.
func _forget_created(zone_name: String, doc: MapDoc) -> void:
	for level_name: String in created.keys():
		var made: Dictionary = created[level_name]
		if made["parent"] == zone_name and str(doc.config.get("neighbours", {}).get(made["side"], "")) != level_name:
			created.erase(level_name)
			docs.erase(level_name)
			remove_overlay(level_name)
			print("[builder] %s is gone with it" % level_name)


# --- An accept laid off the server's frame (956) -------------------------------------------------

## The accepts and undos being laid, by zone: {job, thread, stop, began}. One a zone: another accept or
## undo there is refused (LAYING_SAYS) until frame B.
var laying: Dictionary[String, Dictionary] = {}
## Tests: a rename of this folder (globalized, no trailing slash) fails, as a folder held open does on Windows.
var fail_rename_from := ""
## Tests: called on the main thread between frame A and the worker's start (a write that slips past the
## busy mark), with the job.
var test_between := Callable()
## The main thread's longest frame while any accept was being laid, in ms (logged at frame B).
var _longest_frame := 0.0
var _frame_at := 0
## What the last frame B logged, for tests and the probe: {frame_a, worker, frame_b, longest} in ms.
var last_laid := {}


## Asks the worker of a job to stop at its next step, read under a lock by both threads.
class Stop:
	var _mutex := Mutex.new()
	var _stopped := false

	func stop() -> void:
		_mutex.lock()
		_stopped = true
		_mutex.unlock()

	func asked() -> bool:
		_mutex.lock()
		var out := _stopped
		_mutex.unlock()
		return out


## The folder an accept's files are written in, and its old level kept in while they are swapped:
## beside the overlay, never in it (a folder in the overlay holding a layout.png reads as a level).
static func laying_dir() -> String:
	return Level.overlay_dir.trim_suffix("/") + "_laying/"


## Frame A of an accept or an undo (956): the session busy, a copy of the zone's doc taken with what its
## worker reads (the linked levels' configs; Level.kinds warmed: its first use fills a static), what frame
## B checks taken (the doc's revision, the level's mark), and the worker started at below-normal priority.
func _start_laying(job: Dictionary) -> void:
	var began: int = job.get("began_a", Time.get_ticks_usec())  # Frame A from the accept's stale check.
	var zone_name: String = job["zone"]
	var doc: MapDoc = job["doc"]
	var session: BuilderSession = sessions.get(job["peer"])
	if session != null:
		session.busy = true
	Level.kinds()
	job["revision"] = doc.revision
	job["mark"] = _level_mark(zone_name)
	job["templates"] = Level.templates_now()
	job["copy"] = doc.copy()
	job["into"] = laying_dir() + zone_name + ".new/"
	job.erase("doc")  # The live doc stays on the main thread.
	if test_between.is_valid():
		test_between.call(job)
	var stop := Stop.new()
	var thread := Thread.new()
	thread.start(_lay.bind(job, stop), Thread.PRIORITY_LOW)
	_frame_at = Time.get_ticks_usec()
	if laying.is_empty():
		_longest_frame = 0.0
	laying[zone_name] = {"job": job, "thread": thread, "stop": stop, "began": Time.get_ticks_usec(),
		"frame_a": (Time.get_ticks_usec() - began) / 1000.0}


## What frame B checks the level's files against (956): a level registered in memory (a laid generation)
## by its digest, else Level.files_key. Moved, another write reached the level while the worker ran.
static func _level_mark(level_name: String) -> String:
	if Level._registered.has(level_name):
		return "made " + str(Level._registered[level_name].get("digest", ""))
	return Level.files_key(level_name)


## The worker (956), on its own thread: [param job]'s copy changed as the accept or undo changes the doc,
## the whole level written into job.into, read back and parsed once; the layout checked on that parse
## (806, an accept's: a fault it adds refuses it, the folder removed); the zone's level, the world map's
## read of it and its terrain message made from it. Touches no node, signal with a listener, resource
## cache or static (the copy is its own; the templates and kinds read on the main thread first).
## {ok, copy, level, read, message} or {ok: false, refused | error | stopped}.
static func _lay(job: Dictionary, stop: Stop) -> Dictionary:
	var copy: MapDoc = job["copy"]
	var templates: Dictionary = job["templates"]
	copy.parse_templates = templates
	var into: String = job["into"]
	var baseline: Variant = job["baseline"]
	if job["kind"] == "undo":
		copy.undo()
	else:
		if not job["spots"] and baseline == null:
			baseline = BuilderSession.layout_faults(copy, copy.parsed(templates))  # None kept: the level's own.
		copy.apply_changes(job["changes"])
	if stop.asked():
		return {"ok": false, "stopped": true}
	remove_folder(into)  # One a stopped run left.
	if not (copy.save_config(into) if job["spots"] else copy.save(false, {}, into)):
		remove_folder(into)
		return {"ok": false, "error": copy.report}
	if job["spots"]:
		return {"ok": true, "copy": copy}
	if stop.asked():
		remove_folder(into)
		return {"ok": false, "stopped": true}
	var made := Level.source_at(into)
	var parsed := Level.parse(made["layout"], made["height"], made["config"], made.get("relief"), templates)
	if job["kind"] == "accept":
		var news := BuilderSession.fault_news(baseline, BuilderSession.layout_faults(copy, parsed))
		if not news.is_empty():
			remove_folder(into)
			return {"ok": false, "refused": "the change breaks the layout rules: " + "; ".join(news)}
	var level := Level.level_from(job["zone"], made, templates, parsed.duplicate(true))
	return {"ok": true, "copy": copy, "level": level, "read": WorldMap.read_of(job["zone"], made, parsed),
		"message": terrain_message_of(job["zone"], made), "config": made["config"], "warnings": level["warnings"]}


func _process(_delta: float) -> void:
	if laying.is_empty():
		return
	var now := Time.get_ticks_usec()
	_longest_frame = maxf(_longest_frame, (now - _frame_at) / 1000.0)
	_frame_at = now
	for zone_name: String in laying.keys():
		var entry: Dictionary = laying[zone_name]
		if (entry["thread"] as Thread).is_alive():
			continue
		var result: Dictionary = (entry["thread"] as Thread).wait_to_finish()
		laying.erase(zone_name)
		_laid(entry, result)


## Frame B (956): the stale check again; the new folder swapped in for the overlay's; the live doc changed
## as the copy was, taking what its save made; the zone reloaded from the worker's parse and the world map
## given its read; the builder answered. On a refusal, a failed save or swap, or a stale check, the folder
## is removed and the doc, the files and the zone are as they were.
func _laid(entry: Dictionary, result: Dictionary) -> void:
	var began := Time.get_ticks_usec()
	_laps.clear()
	_lap_at = began
	var reads := Level.folder_reads
	var parses := Level.parses
	var job: Dictionary = entry["job"]
	var zone_name: String = job["zone"]
	var peer: int = job["peer"]
	var session: BuilderSession = sessions.get(peer)
	var doc: MapDoc = docs[zone_name]
	var into: String = job["into"]
	var answer := {}
	if not result["ok"]:
		remove_folder(into)
		if result.has("refused"):
			answer = {"state": "error", "error": result["refused"]}
		elif result.has("error"):
			push_warning("[builder] " + str(result["error"]))
			answer = {"state": "error", "error": "could not save: %s" % result["error"]}
	elif doc.revision != job["revision"] or _level_mark(zone_name) != job["mark"]:
		# The world ran while the worker did: another write reached the level (coordinator, 11-16).
		remove_folder(into)
		answer = {"state": "error", "error": BuilderSession.STALE_SAYS}
	else:
		_lap("join and check")
		var swapped := _swap_in(zone_name, into)
		_lap("renames")
		if not swapped.is_empty():
			push_warning("[builder] %s: %s" % [zone_name, swapped])
			answer = {"state": "error", "error": "could not save: %s" % swapped}
		else:
			answer = _take_laid(job, result, doc, session)
	if session != null:
		session.busy = false
		if session.discard_waiting:
			session.discard_waiting = false
			session._fresh_working()
	if not _laps.is_empty():
		_lap("adopt and the rest")
	var frame_b := (Time.get_ticks_usec() - began) / 1000.0
	last_laid = {"frame_a": entry["frame_a"], "worker": (began - int(entry["began"])) / 1000.0, "frame_b": frame_b,
		"longest": _longest_frame, "answer": answer.get("state", "nothing"),
		"reads_in_b": Level.folder_reads - reads, "parses_in_b": Level.parses - parses, "steps": ", ".join(_laps)}
	print("[builder] %s %s laid off the frame: frame A %.1f ms, the worker %.0f ms (the longest frame meanwhile %.1f ms), frame B %.1f ms (%s)" % [
		zone_name, job["kind"], last_laid["frame_a"], last_laid["worker"], _longest_frame, frame_b, last_laid["steps"]])
	_reply(peer, answer if not answer.is_empty() else {"state": "nothing"})


## The swapped-in change taken into the running game (frame B's rest): the doc, the session, the zone and
## the world map. The answer to the builder.
func _take_laid(job: Dictionary, result: Dictionary, doc: MapDoc, session: BuilderSession) -> Dictionary:
	var zone_name: String = job["zone"]
	var held_before := camps_holding(doc.config)  # The doc is the files it was saved as until now.
	doc.take_laid(result["copy"])  # The worker's copy, changed and saved: the same revision checked above.
	_lap("the doc")
	if job["kind"] == "undo":
		for each: int in sessions:
			if _session_zone.get(each, "") == zone_name:
				sessions[each].discard()
	elif session != null:
		session._fresh_working()  # As accept() leaves it.
	if not job["spots"]:
		for warning: String in result.get("warnings", []):
			push_warning("[level] %s: %s" % [zone_name, warning])
		_after_save(zone_name, held_before, result)
	elif not _spots_into_world(zone_name):
		_after_save(zone_name, held_before)  # A world map without the zone: the whole way, read from the files.
	if job["kind"] == "undo":
		_forget_created(zone_name, doc)
		print("[builder] %s took back the last change to %s" % [job["player_id"], zone_name])
		return {"state": "undone"}
	print("[builder] %s accepted their change to %s%s" % [job["player_id"], zone_name, " (spots only)" if job["spots"] else ""])
	return {"state": "accepted"}


## Frame B's steps, timed for its log line (956: the box probe reads frame B's own steps).
var _laps: Array[String] = []
var _lap_at := 0


func _lap(step: String) -> void:
	var now := Time.get_ticks_usec()
	_laps.append("%s %.1f" % [step, (now - _lap_at) / 1000.0])
	_lap_at = now


## [param into] (a whole level written there) swapped in for level [param zone_name]'s overlay folder:
## the old folder renamed aside into laying_dir, the new one renamed in, the old removed. "" when done,
## else why not, with everything as it was: a second rename that fails puts the old folder back; if even
## that fails, both stay whole in laying_dir and the next boot puts the old back (recover_overlays).
func _swap_in(zone_name: String, into: String) -> String:
	var folder := ProjectSettings.globalize_path(Level.overlay_dir + zone_name)
	var new_folder := ProjectSettings.globalize_path(into).trim_suffix("/")
	var old_folder := ProjectSettings.globalize_path(laying_dir() + zone_name + ".old")
	remove_folder(old_folder)
	var had := DirAccess.dir_exists_absolute(folder)
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(Level.overlay_dir)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Level.overlay_dir))
	if had and not _rename(folder, old_folder):
		remove_folder(new_folder)
		return "could not move %s aside" % zone_name
	if not _rename(new_folder, folder):
		if had and not _rename(old_folder, folder):
			push_warning("[builder] %s: neither its new files nor its old could be put back; the next start puts the old back" % zone_name)
			return "could not put %s's files in place" % zone_name
		remove_folder(new_folder)
		return "could not put %s's files in place" % zone_name
	if had and not remove_folder(old_folder):
		push_warning("[builder] %s: its old files stay in %s until the next start" % [zone_name, laying_dir()])
	return ""


## A folder renamed, tried three times 100 ms apart (a file scanned as it was written may be held open
## for a moment on Windows; on the box it is one call). The test hook fails it.
func _rename(from: String, to: String) -> bool:
	for attempt in 3:
		if from != fail_rename_from and DirAccess.rename_absolute(from, to) == OK:
			return true
		if attempt < 2:
			OS.delay_msec(100)
	return false


## [param path]'s folder and the files in it removed (a level's folder holds no folders). Whether it is gone.
static func remove_folder(path: String) -> bool:
	var folder := ProjectSettings.globalize_path(path).trim_suffix("/")
	if not DirAccess.dir_exists_absolute(folder):
		return true
	for file in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(file))
	return DirAccess.remove_absolute(folder) == OK


## At boot, before any level is read (956): what an accept stopped in the middle of left in laying_dir
## put right, every level whole, old or new. A level's folder there with the level's own in the overlay:
## removed (the swap was done, or never begun). An old folder there with none in the overlay: put back
## (stopped between the two renames). Said in a line each.
static func recover_overlays() -> void:
	var dir := ProjectSettings.globalize_path(laying_dir())
	if not DirAccess.dir_exists_absolute(dir):
		return
	var overlay := ProjectSettings.globalize_path(Level.overlay_dir)
	for name: String in DirAccess.get_directories_at(dir):
		var level_name := name.get_basename()
		var in_overlay := DirAccess.dir_exists_absolute(overlay.path_join(level_name))
		if name.ends_with(".old") and not in_overlay:
			DirAccess.make_dir_recursive_absolute(overlay)
			if DirAccess.rename_absolute(dir.path_join(name), overlay.path_join(level_name)) == OK:
				print("[builder] %s: put back as it was before an accept the last run stopped in" % level_name)
				continue
		remove_folder(dir.path_join(name))
		print("[builder] %s: an unfinished accept's %s files removed" % [level_name, name.get_extension()])


## Quitting (956): each accept being laid asked to stop and joined. One whose worker had finished is
## swapped in (its level saved as accepted); one stopped is removed, before any rename.
func finish_laying() -> void:
	for zone_name: String in laying.keys():
		var entry: Dictionary = laying[zone_name]
		(entry["stop"] as Stop).stop()
		var result: Dictionary = (entry["thread"] as Thread).wait_to_finish()
		laying.erase(zone_name)
		var into: String = entry["job"]["into"]
		if result.get("ok", false) and _swap_in(zone_name, into).is_empty():
			print("[builder] %s: an accept being laid as the server stopped saved" % zone_name)
		else:
			remove_folder(into)


func _exit_tree() -> void:
	finish_laying()


## Saves the zone's doc to the overlay, has Main reload the zone, and says
## what the world map now finds wrong, if anything.
## A spots-only accept (867 amended (2), BuilderSession.spots_only): level.json saved alone, and the
## spots read again (Level.spots_from on the area's floor, as Level.parse reads them) into each place
## the running world holds them: Main's world map, which the residents' places are made from at each
## sync (197 amended (1)), and an interior's parse Main keeps (_zone_levels, the taverner's work spots).
## No layout.png written, no reload_zone, no WorldMap built: on the box those were 1.2 s of one frame.
## No terrain message: no client reads spots. Whether it saved.
func _save_spots(zone_name: String) -> bool:
	var doc: MapDoc = docs[zone_name]
	if not doc.save_config():
		push_warning("[builder] " + doc.report)
		return false
	if not _spots_into_world(zone_name):
		return _save_and_reload(zone_name)  # A world map without the zone: the whole way.
	return true


## The zone's spots, its level.json saved, read again into each place the running world holds them
## (_save_spots'). False, nothing done, when Main's world map has no such area.
func _spots_into_world(zone_name: String) -> bool:
	var doc: MapDoc = docs[zone_name]
	var world_map: WorldMap = main._world_map if main != null else null
	var area: Dictionary = world_map.areas.get(zone_name, {}) if world_map != null else {}
	if area.is_empty():
		return false
	var warnings: Array[String] = []
	var spots := Level.spots_from(doc.config, warnings, area["floor"])
	area["spots"] = spots
	var kept: Dictionary = main._zone_levels.get(zone_name, {})
	if not kept.is_empty():
		kept["spots"] = spots.duplicate(true)
	if main._level_stamps.has(zone_name):
		main._level_stamps[zone_name] = main._level_stamp(zone_name)  # Read as it is: the console's reload all leaves it.
	for warning in warnings:
		push_warning("[builder] after the change to %s: %s" % [zone_name, warning])
	return true


func _save_and_reload(zone_name: String) -> bool:
	var doc: MapDoc = docs[zone_name]
	# The camps holding captives before the change (decision 519): one gone with it lets them go home.
	var held_before := camps_holding(Level.source(zone_name).get("config", {}))
	if not doc.save(false):  # 867 amended (2): no report's parse; builder mode shows a report only when it fails.
		push_warning("[builder] " + doc.report)
		return false
	_after_save(zone_name, held_before)
	return true


## The zone, its level saved, reloaded, the world map built and adopted, the towns and captives as the
## change leaves them, and what the map finds wrong said (_save_and_reload's). [param laid] (956): the
## worker's {level, message, read} of the files it wrote, so nothing is read back from disk here.
func _after_save(zone_name: String, held_before: Array[String], laid := {}) -> void:
	var doc: MapDoc = docs[zone_name]
	main.reload_zone(zone_name, laid.get("level", {}), laid.get("message", {}), laid.get("config", {}))
	_lap("reload_zone")
	if laid.has("read"):
		WorldMap.keep_read(zone_name, laid["read"], Level.files_key(zone_name))
	var world_map := WorldMap.build()
	_lap("world map")
	if main != null and main.has_method("adopt_world_map"):
		# 197 amended (1): the new map everywhere one is held, as a regenerated level's is: the residents'
		# places (read from Main's each sync: spots, homes, work), the holdings (places added, moved or gone,
		# a gone one forgotten by those who knew it), the raid groups, the trade, the richness, the forage.
		main.adopt_world_map(world_map)
	elif World.holdings != null:
		# Places added, moved or gone with the change.
		World.holdings.rebind(world_map)
	if World.towns != null:
		# A building linked to its town with the change stands in it.
		World.towns.seed_from(world_map)
	if main != null and main.has_method("_place_captives"):
		# Captives a camp holds from the start (npc's 518): the new placed, a gone camp's home.
		var held_now := camps_holding(doc.config)
		var gone: Array[String] = []
		for key in held_before:
			if key not in held_now:
				gone.append("%s/%s" % [zone_name, key])
		var placed: int = main._place_captives(world_map, gone)
		if placed > 0 or not gone.is_empty():
			print("[builder] after the change to %s: %d captives placed, %d camps gone" % [zone_name, placed, gone.size()])
	var problems := world_map.problems()
	for problem in problems:
		push_warning("[builder] after the change to %s: %s" % [zone_name, problem])


## The keys of [param config]'s camps that hold captives (level.json
## "places", kind camp, with holds).
static func camps_holding(config: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var places: Variant = config.get("places", {})
	if places is Dictionary:
		for key: Variant in places:
			var place: Variant = places[key]
			if place is Dictionary and str(place.get("kind", "")) == "camp" and place.get("holds") is Array and not (place["holds"] as Array).is_empty():
				out.append(str(key))
	return out


## The "terrain" message for level [param level_name]: its files as the
## game reads them now, for clients (whose own copy is the pck's).
static func terrain_message(level_name: String) -> Dictionary:
	return terrain_message_of(level_name, Level.source(level_name))


## terrain_message's, from [param made] ({layout, height, config, relief}) rather than the level as
## the game reads it now (956: made on an accept's worker from the files it wrote). Touches no node.
static func terrain_message_of(level_name: String, made: Dictionary) -> Dictionary:
	var layout: Image = made["layout"]
	var height: Image = made["height"]
	var relief: Image = made.get("relief")
	# A level's secrets (the co-op tomb's loose niche and its clues) stay
	# on the server: no client is told where they are.
	var config: Dictionary = made["config"]
	if config.has("secrets"):
		config = config.duplicate()
		config.erase("secrets")
	return {"name": level_name, "layout": layout.save_png_to_buffer() if layout != null else PackedByteArray(),
		"height": height.save_png_to_buffer() if height != null else PackedByteArray(), "config": config,
		"relief": relief.save_png_to_buffer() if relief != null else PackedByteArray()}


## A client: makes level [param data]["name"] from a "terrain" message
## (Level.register), so it is read so from now on. False if it is not one.
static func register_terrain(data: Dictionary) -> bool:
	var layout := Image.new()
	if layout.load_png_from_buffer(data.get("layout", PackedByteArray())) != OK:
		return false
	var height: Image = null
	var height_bytes: PackedByteArray = data.get("height", PackedByteArray())
	if not height_bytes.is_empty():
		height = Image.new()
		if height.load_png_from_buffer(height_bytes) != OK:
			height = null
	var relief: Image = null
	var relief_bytes: PackedByteArray = data.get("relief", PackedByteArray())
	if not relief_bytes.is_empty():
		relief = Image.new()
		if relief.load_png_from_buffer(relief_bytes) != OK:
			relief = null
	var config: Variant = data.get("config", {})
	Level.register(str(data.get("name", "")), layout, height, config if config is Dictionary else {}, relief)
	return true


## The stub's script for an area: a patch of dirt in its middle third, a
## chest and a torch on it; or, asked for a "new area" with the area on the
## edge of a map [param size] across, a new level beyond that edge; or
## "spots ..." (stub_spots); or "name <key> <words>" (stub_name, the level's
## [param places]); or "chest", an unguarded chest a dungeon's layout check refuses. "slow "
## before any of them holds the reply STUB_SLOW_FRAMES (a still of the panel
## while it works).
static func _stub_for(area: Rect2i, text := "", size := Vector2i.ZERO, dungeon := false, places := {}) -> StubClaude:
	if text.to_lower().begins_with("slow "):
		var held := _stub_for(area, text.substr(5), size, dungeon, places)
		held.wait_frames = STUB_SLOW_FRAMES
		return held
	if text.to_lower().begins_with("new area"):
		var sides := {"north": area.position.y == 0, "east": area.end.x == size.x, "south": area.end.y == size.y, "west": area.position.x == 0}
		for side: String in sides:
			if sides[side]:
				return StubClaude.new([[{"name": "new_area", "input": {"side": side, "width": 48, "height": 48, "name": "Stub Fields"}}],
					"(Stub) A new level beyond the %s edge." % side])
	if text.to_lower().begins_with("spots"):
		return stub_spots(text)
	if text.to_lower().begins_with("name "):
		return stub_name(text, places)
	var middle := Rect2i(area.position + area.size / 3, (area.size / 3).max(Vector2i.ONE))
	var centre := middle.position + middle.size / 2
	# "chest" (885 amended (1), for a still of a refused answer): a chest of loot at the middle with no
	# guard by it, which a dungeon's chest rule refuses.
	if text.to_lower().begins_with("chest"):
		return StubClaude.new([[{"name": "place", "input": {"at": [centre.x, centre.y], "thing": "chest", "items": ["bandaging_kit"]}}],
			"(Stub) A chest in the middle of the area, nobody guarding it."])
	# Jeff's chest rules (807 amended (4), 806 amended (7)): a chest of things
	# only in a dungeon, with a guard by it; elsewhere a shop counter's.
	var calls: Array = [{"name": "paint", "input": {"ground": "dirt", "rects": [{"x": middle.position.x, "y": middle.position.y, "w": middle.size.x, "h": middle.size.y}]}},
		{"name": "place", "input": {"at": [centre.x, centre.y], "thing": "chest", "items": ["bandaging_kit"]} if dungeon \
			else {"at": [centre.x, centre.y], "thing": "chest", "use": "shop"}},
		{"name": "place", "input": {"at": [middle.position.x, middle.position.y], "thing": "torch"}}]
	if dungeon:
		calls.append({"name": "place", "input": {"at": [middle.end.x - 1, middle.end.y - 1], "thing": "imp", "idle": {"mode": "guard"}}})
	return StubClaude.new([calls, "(Stub) A patch of dirt with a chest and a torch."])


## The stub's spots (859 amended (2), for a shot of the ghost): "spots x,y
## x,y ..." (or ";" between) lays a spot on each cell named, facing east, the
## uses and poses in turn (a fire seat, a square standing, a cook leaning);
## its closing words pass on each tool's answer, so a refused spot's reason
## shows as Claude's would.
static func stub_spots(text: String) -> StubClaude:
	var kinds := [{"use": "fire", "pose": "sit"}, {"use": "square", "pose": "stand"}, {"use": "work", "trade": "cook", "pose": "lean"}]
	var calls: Array = []
	# Cells apart by spaces or ";" (a shot's command line keeps no spaces).
	for word: String in text.substr(5).replace(";", " ").strip_edges().split(" ", false):
		var parts := word.split(",")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			continue
		var at := Vector2i(int(parts[0]), int(parts[1]))
		var input: Dictionary = (kinds[calls.size() % kinds.size()] as Dictionary).duplicate()
		input["at"] = [at.x, at.y]
		input["face"] = [at.x + 1, at.y]
		calls.append({"name": "spot", "input": input})
	if calls.is_empty():
		return StubClaude.new(["(Stub) No cells named: spots x,y x,y ..."])
	return StubClaude.new([calls, "(Stub) Spots laid where I could:\n{results}"])


## The stub's "name <key> <words>" (197 amended (2), for a joined run's
## world map): the place <key> of [param places] (the level's, as level.json
## holds it) marked again with mark_place as it stands, named <words>. Its
## at, kind, radius, holder, town, rect and cells go as they are; its facing
## as a side's word; a field mark_place does not take (a worth) goes as
## Claude's mark_place would lose it, and the take-back brings it back.
static func stub_name(text: String, places: Dictionary) -> StubClaude:
	var words := text.substr(5).strip_edges()
	var key := words.get_slice(" ", 0)
	var called := words.substr(key.length()).strip_edges()
	var place: Variant = places.get(key)
	if not place is Dictionary or called.is_empty():
		return StubClaude.new(["(Stub) Name what: name <place key> <words> (keys here: %s)" % ", ".join(places.keys())])
	var input: Dictionary = (place as Dictionary).duplicate(true)
	input.erase("cell")
	input["at"] = place.get("at", place.get("cell"))
	input["key"] = key
	input["name"] = called
	if input.get("facing") is Array and (input["facing"] as Array).size() == 2:
		var step := Vector2i(int(input["facing"][0]), int(input["facing"][1]))
		for side: String in BuilderSession.SIDES:
			if BuilderSession.SIDES[side] == step:
				input["facing"] = side
	return StubClaude.new([[{"name": "mark_place", "input": input}], "(Stub) Named %s:\n{results}" % key])


## Removes level [param level_name]'s files from the overlay.
static func remove_overlay(level_name: String) -> void:
	var folder := ProjectSettings.globalize_path(Level.overlay_dir + level_name)
	if not DirAccess.dir_exists_absolute(folder):
		return
	for file in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(file))
	DirAccess.remove_absolute(folder)


func _reply(peer: int, data: Dictionary) -> void:
	Net.broadcast_to([peer], "builder", data)


# --- The console -------------------------------------------------------------------------

## "builder" (how it is), "builder export" (where the edited levels' files
## are, to copy into the repo), "builder drop <name>" (forget a level's
## edits: the repo's version again).
func admin(words: PackedStringArray) -> String:
	if words.size() < 2:
		return "builder mode: %s, builders: host%s; %d sessions; $%.4f spent since start; %s" % [
			"stub" if Net.builder_stub else Net.builder_model, ", " + ", ".join(Net.builders) if not Net.builders.is_empty() else "",
			sessions.size(), spent, overlay_summary()]
	return BuilderHost.overlay_command(words, main)


## The console's "builder export" and "builder drop <name>", which work
## with builder mode off too (the overlay is there either way).
static func overlay_command(words: PackedStringArray, reloader: Node) -> String:
	match words[1] if words.size() > 1 else "":
		"export":
			# 199 amended (2): only the edits are copied into levels/; a laid generation copied
			# there would stand as the template it is laid from.
			var kinds := overlay_kinds()
			var lines := PackedStringArray()
			for level_name: String in kinds["edited"]:
				var folder := ProjectSettings.globalize_path(Level.overlay_dir + level_name)
				for file in DirAccess.get_files_at(folder):
					if not file.ends_with(".import"):
						lines.append("%s/%s -> levels/%s/%s" % [folder, file, level_name, file])
			if lines.is_empty():
				lines.append("no edited levels")
			if not (kinds["laid"] as Array).is_empty():
				lines.append("laid generations, the regenerator's, not to copy: %s" % ", ".join(kinds["laid"]))
			return "\n".join(lines)
		"drop":
			if words.size() < 3 or not Level.overlaid(words[2]):
				return "usage: builder drop <name> (%s)" % overlay_summary()
			var host: Variant = reloader.get("_builder") if reloader != null else null
			if host is BuilderHost and (host as BuilderHost).laying.has(words[2]):
				return "%s: a builder's change is being laid there; drop it once that is done" % words[2]  # 956.
			remove_overlay(words[2])
			if reloader != null and reloader.has_method("forget_level_edits"):
				reloader.forget_level_edits(words[2])
			return "dropped the edits to %s: it is the repo's again" % words[2]
	return "usage: builder | builder export | builder drop <name>"
