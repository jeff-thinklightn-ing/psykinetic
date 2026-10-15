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
## "proposal" (summary, cost, total, area, cells: [[x, y, meaning]...],
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
## levels/: edited in the game, not yet copied back into the repo.
static func warn_overlays() -> void:
	for level_name in Level.overlay_names():
		push_warning("[builder] %s is read from %s (edited in the game), not from %s: \"builder export\", then \"builder drop %s\" once it is in the repo" % [
			level_name, ProjectSettings.globalize_path(Level.overlay_dir + level_name), Level.DIR + level_name, level_name])


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
		session = BuilderSession.new(doc, area, zone_name, (StubClaude.new(test_turns) if not test_turns.is_empty() else _stub_for(area, text, doc.map.size)) if Net.builder_stub else claude)
		session.model = Net.builder_model
		session.effort = Net.builder_effort
		session.max_cost = Net.builder_max_cost
		sessions[peer] = session
		_session_zone[peer] = zone_name
	claude.log_tag = "%s in %s" % [player_id, zone_name]
	_reply(peer, {"state": "working"})
	var result: Dictionary = await session.ask(text)
	spent += float(result["cost"])
	print("[builder] %s in %s %s: \"%s\" -> %s, $%.4f (session $%.4f, %d in, %d out; server $%.4f)" % [player_id, zone_name,
		[area.position.x, area.position.y, area.size.x, area.size.y], text, "ok" if result["ok"] else result["error"],
		result["cost"], session.usage["cost"], session.usage["input"] + session.usage["cache_read"] + session.usage["cache_write"],
		session.usage["output"], spent])
	if not result["ok"] and session.proposal()["cells"].is_empty() and session.proposal()["edges"].is_empty():
		_reply(peer, {"state": "error", "error": result["error"]})
		return
	var reply := proposal_message(session)
	reply["summary"] = str(result["summary"]) + ("" if result["ok"] else "\n(" + str(result["error"]) + ")")
	var warnings: Array = result.get("warnings", [])
	if not warnings.is_empty():
		reply["summary"] += "\nThe town's store: " + "; ".join(warnings)
	reply["cost"] = result["cost"]
	reply["total"] = session.usage["cost"]
	_reply(peer, reply)


## [param session]'s proposal as the "builder" message's fields.
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
	var message := {"state": "proposal", "area": [session.area.position.x, session.area.position.y, session.area.size.x, session.area.size.y],
		"cells": cells, "edges": edges}
	if proposal.has("new_area"):
		var plan: Dictionary = proposal["new_area"]
		var footprint: Rect2i = plan["footprint"]
		message["new_area"] = {"name": plan["name"], "side": plan["side"], "size": [plan["size"].x, plan["size"].y],
			"footprint": [footprint.position.x, footprint.position.y, footprint.size.x, footprint.size.y]}
	return message


func _accept(peer: int, player_id: String) -> void:
	var session: BuilderSession = sessions.get(peer)
	if session == null or session.busy:
		_reply(peer, {"state": "nothing"})
		return
	var zone_name: String = _session_zone[peer]
	var plan := session.new_area.duplicate()
	if not session.accept():
		_reply(peer, {"state": "nothing"})
		return
	if session.created_doc != null:
		# The new level first, so the way to it never leads nowhere.
		if not session.created_doc.save():
			push_warning("[builder] " + session.created_doc.report)
		created[session.created] = {"parent": zone_name, "side": plan["side"]}
		print("[builder] %s made a new level, %s (%d x %d), beyond the %s edge of %s" % [player_id, session.created,
			plan["size"].x, plan["size"].y, plan["side"], zone_name])
	if not _save_and_reload(zone_name):
		_reply(peer, {"state": "error", "error": "could not save: %s" % session.doc.report})
		return
	print("[builder] %s accepted their change to %s" % [player_id, zone_name])
	_reply(peer, {"state": "accepted"})


func _undo(peer: int, player_id: String, zone_name: String) -> void:
	var doc: MapDoc = docs.get(zone_name)
	if doc == null or doc.undo_steps.is_empty():
		_reply(peer, {"state": "nothing"})
		return
	# A new level the step made goes with it: not while anyone is in it.
	for level_name: String in created:
		if created[level_name]["parent"] == zone_name and doc.undo_steps.back().has("config neighbours") \
				and not World.peers_in(level_name).is_empty():
			_reply(peer, {"state": "error", "error": "someone is in %s: it cannot be taken back now" % level_name})
			return
	doc.undo()
	for each: int in sessions:
		if _session_zone.get(each, "") == zone_name:
			sessions[each].discard()
	if not _save_and_reload(zone_name):
		_reply(peer, {"state": "error", "error": "could not save: %s" % doc.report})
		return
	for level_name: String in created.keys():
		var made: Dictionary = created[level_name]
		if made["parent"] == zone_name and str(doc.config.get("neighbours", {}).get(made["side"], "")) != level_name:
			created.erase(level_name)
			docs.erase(level_name)
			remove_overlay(level_name)
			print("[builder] %s is gone with it" % level_name)
	print("[builder] %s took back the last change to %s" % [player_id, zone_name])
	_reply(peer, {"state": "undone"})


## Saves the zone's doc to the overlay, has Main reload the zone, and says
## what the world map now finds wrong, if anything.
func _save_and_reload(zone_name: String) -> bool:
	var doc: MapDoc = docs[zone_name]
	if not doc.save():
		push_warning("[builder] " + doc.report)
		return false
	main.reload_zone(zone_name)
	var world_map := WorldMap.build()
	if World.holdings != null:
		# Places added, moved or gone with the change.
		World.holdings.rebind(world_map)
	var problems := world_map.problems()
	for problem in problems:
		push_warning("[builder] after the change to %s: %s" % [zone_name, problem])
	return true


## The "terrain" message for level [param level_name]: its files as the
## game reads them now, for clients (whose own copy is the pck's).
static func terrain_message(level_name: String) -> Dictionary:
	var made := Level.source(level_name)
	var layout: Image = made["layout"]
	var height: Image = made["height"]
	return {"name": level_name, "layout": layout.save_png_to_buffer() if layout != null else PackedByteArray(),
		"height": height.save_png_to_buffer() if height != null else PackedByteArray(), "config": made["config"]}


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
	var config: Variant = data.get("config", {})
	Level.register(str(data.get("name", "")), layout, height, config if config is Dictionary else {})
	return true


## The stub's script for an area: a patch of dirt in its middle third, a
## chest and a torch on it; or, asked for a "new area" with the area on the
## edge of a map [param size] across, a new level beyond that edge.
static func _stub_for(area: Rect2i, text := "", size := Vector2i.ZERO) -> StubClaude:
	if text.to_lower().begins_with("new area"):
		var sides := {"north": area.position.y == 0, "east": area.end.x == size.x, "south": area.end.y == size.y, "west": area.position.x == 0}
		for side: String in sides:
			if sides[side]:
				return StubClaude.new([[{"name": "new_area", "input": {"side": side, "width": 48, "height": 48, "name": "Stub Fields"}}],
					"(Stub) A new level beyond the %s edge." % side])
	var middle := Rect2i(area.position + area.size / 3, (area.size / 3).max(Vector2i.ONE))
	var centre := middle.position + middle.size / 2
	return StubClaude.new([
		[{"name": "paint", "input": {"ground": "dirt", "rects": [{"x": middle.position.x, "y": middle.position.y, "w": middle.size.x, "h": middle.size.y}]}},
			{"name": "place", "input": {"at": [centre.x, centre.y], "thing": "chest", "items": ["bandaging_kit"]}},
			{"name": "place", "input": {"at": [middle.position.x, middle.position.y], "thing": "torch"}}],
		"(Stub) A patch of dirt with a chest and a torch.",
	])


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
		return "builder mode: %s, builders: host%s; %d sessions; $%.4f spent since start; edited levels: %s" % [
			"stub" if Net.builder_stub else Net.builder_model, ", " + ", ".join(Net.builders) if not Net.builders.is_empty() else "",
			sessions.size(), spent, ", ".join(Level.overlay_names()) if not Level.overlay_names().is_empty() else "none"]
	return BuilderHost.overlay_command(words, main)


## The console's "builder export" and "builder drop <name>", which work
## with builder mode off too (the overlay is there either way).
static func overlay_command(words: PackedStringArray, reloader: Node) -> String:
	match words[1] if words.size() > 1 else "":
		"export":
			var lines := PackedStringArray()
			for level_name in Level.overlay_names():
				var folder := ProjectSettings.globalize_path(Level.overlay_dir + level_name)
				for file in DirAccess.get_files_at(folder):
					if not file.ends_with(".import"):
						lines.append("%s/%s -> levels/%s/%s" % [folder, file, level_name, file])
			return "\n".join(lines) if not lines.is_empty() else "no edited levels"
		"drop":
			if words.size() < 3 or not Level.overlaid(words[2]):
				return "usage: builder drop <name> (an edited level: %s)" % ", ".join(Level.overlay_names())
			remove_overlay(words[2])
			if reloader != null and reloader.has_method("forget_level_edits"):
				reloader.forget_level_edits(words[2])
			return "dropped the edits to %s: it is the repo's again" % words[2]
	return "usage: builder | builder export | builder drop <name>"
