extends Node
## The tour bot (playtest): a player at a real networked client, driven
## through the client's own input paths, as Jeff plays. A click is Main's
## own click handler with the cell under the cursor set (the pointer's
## pixel pick is the one step skipped: a headless window has no cursor,
## and a windowed tour must never move Jeff's); a key is Main's own key
## handler. It asserts only what a player could see or hear at the
## client: where it stands, which windows and buttons are up, what is said.
## Setup a player could not do (the hour, a place to start from) goes
## through the server's admin console, named as setup in the report.

## The client's Main (main.tscn), which the tour scene made.
var main: Node
## The server's admin console port on 127.0.0.1 (0: none).
var admin_port := 0
## Where the report and stills go (a folder, absolute).
var out_dir := ""
## The report's lines: {"ok": bool, "what": String, "detail": String};
## "ok" null for a plain log line.
var lines: Array[Dictionary] = []
var _started_msec := 0
## What the client heard said: {"speaker", "text", "entity" (its path),
## "msec"}, from the "speech" messages, as the bubbles show them.
var heard: Array[Dictionary] = []
var told: Array[Dictionary] = []
var _clicked_frame := 0
## Blows the client saw: {"who" (the body's instance id), "label", "at", "toward" (the cell
## the swing points at), "kind" ("swung" or "struck"), "msec"}.
var blows: Array[Dictionary] = []
var _watched: Dictionary[int, bool] = {}


func _init(client_main: Node, console_port: int, folder: String) -> void:
	main = client_main
	admin_port = console_port
	out_dir = folder
	_started_msec = Time.get_ticks_msec()
	Net.message_received.connect(_on_message)


func _on_message(kind: String, data: Dictionary) -> void:
	if kind == "speech":
		heard.append({"speaker": str(data.get("speaker", "")), "text": str(data.get("text", "")),
			"entity": str(data.get("entity", "")), "msec": Time.get_ticks_msec()})
		log_line("heard %s: \"%s\"" % [data.get("speaker", ""), str(data.get("text", "")).left(160)])
	elif kind == "party":
		told.append({"from": str(data.get("from", "")), "text": str(data.get("text", "")), "msec": Time.get_ticks_msec()})
		log_line("told (%s): \"%s\"" % [data.get("from", ""), str(data.get("text", "")).left(160)])


## Lines told to me alone (party messages) since [param since_msec] that
## hold [param words].
func told_since(since_msec: int, words := "") -> Array[Dictionary]:
	return told.filter(func(line: Dictionary) -> bool:
		return line["msec"] >= since_msec and (words.is_empty() or words.to_lower() in String(line["text"]).to_lower()))


## Each frame: every body the client knows of is watched for its swings
## and the blows it takes.
func _process(_delta: float) -> void:
	for entity: GridEntity in World.get_entities():
		var id := entity.get_instance_id()
		if _watched.has(id):
			continue
		_watched[id] = true
		entity.swung.connect(func(direction: Vector2i) -> void:
			if is_instance_valid(entity):
				blows.append({"who": id, "label": label(entity), "at": entity.tile, "toward": entity.tile + direction,
					"kind": "swung", "msec": Time.get_ticks_msec()}))
		entity.struck.connect(func(amount: int, cause: StringName) -> void:
			if is_instance_valid(entity):
				blows.append({"who": id, "label": label(entity), "at": entity.tile, "toward": entity.tile,
					"kind": "struck", "amount": amount, "cause": String(cause), "msec": Time.get_ticks_msec()}))
		entity.winding.connect(func(direction: Vector2i, ticks: int) -> void:
			if is_instance_valid(entity):
				blows.append({"who": id, "label": label(entity), "at": entity.tile, "toward": entity.tile + direction,
					"kind": "winding", "ticks": ticks, "msec": Time.get_ticks_msec()}))


## The swings seen since [param since_msec] by [param who] that point at
## [param target]'s cell (or a cell beside it, a step either way).
func swings_at(who: GridEntity, target: GridEntity, since_msec := 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for blow in blows:
		if blow["kind"] == "swung" and blow["who"] == who.get_instance_id() and blow["msec"] >= since_msec \
				and is_instance_valid(target) and World.distance(blow["toward"], target.tile) <= 1:
			out.append(blow)
	return out


## Lines heard since [param since_msec] from the body at [param path].
func heard_from(path: String, since_msec := 0) -> Array[Dictionary]:
	return heard.filter(func(line: Dictionary) -> bool: return line["entity"] == path and line["msec"] >= since_msec)


## The local player's own companion, or null.
func companion() -> GridEntity:
	for entity in seen("Companion"):
		if "keeper_peer" in entity and int(entity.get("keeper_peer")) == Net.local_id:
			return entity
	var all := seen("Companion")
	return all[0] if not all.is_empty() else null


func now_msec() -> int:
	return Time.get_ticks_msec()


# --- Reading what a player sees -------------------------------------------

## The local player, or null (not joined yet, dead, between zones).
func me() -> Player:
	return main._local_player()


## The zone the client is in ("" before the first map).
func zone() -> String:
	var player := me()
	return String(player.zone) if player != null else String(main.map_name)


## Where the local player stands (NONE if there is none).
func cell() -> Vector2i:
	var player := me()
	return player.tile if player != null else Vector2i(-1, -1)


## The spawned entities the client knows of, nearest first, whose name
## holds [param words] (any case), or every one with "".
func seen(words := "") -> Array[GridEntity]:
	var out: Array[GridEntity] = []
	var player := me()
	for entity: GridEntity in World.get_entities():
		if entity == player or not entity.spawned:
			continue
		if words.is_empty() or words.to_lower() in label(entity).to_lower():
			out.append(entity)
	if player != null:
		out.sort_custom(func(a: GridEntity, b: GridEntity) -> bool:
			return World.distance(player.tile, a.tile) < World.distance(player.tile, b.tile))
	return out


## What a player would call [param entity], as the bot reads it: its node
## name, a resident's person, a monster's kind and named id, its class.
func label(entity: GridEntity) -> String:
	var parts: Array[String] = [String(entity.name)]
	for key: String in ["person", "kind", "named_id"]:
		if key in entity and str(entity.get(key)) != "":
			parts.append(str(entity.get(key)))
	var script := entity.get_script() as Script
	if script != null and script.get_global_name() != &"":
		parts.append(String(script.get_global_name()))
	return " ".join(parts)


## The last [param lines] lines of the server's log (tools/tour.sh writes
## it beside the report) that hold [param words].
func server_lines(words: String) -> Array[String]:
	var out: Array[String] = []
	var text := FileAccess.get_file_as_string(out_dir.path_join("server.log"))
	for line in text.split("\n"):
		if words in line:
			out.append(line)
	return out


## The nearest entity whose name holds [param words], or null.
func find(words: String) -> GridEntity:
	var all := seen(words)
	return all[0] if not all.is_empty() else null


## Every visible Button under [param root] (Main's whole UI by default):
## {"text", "disabled", "path", "node"}.
func buttons(root: Node = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_collect_buttons(root if root != null else main, out)
	return out


## Every visible text under [param root] (Main's whole UI by default):
## labels, rich labels and buttons, as a player reads them.
func texts(root: Node = null) -> Array[String]:
	var out: Array[String] = []
	_collect_texts(root if root != null else main, out)
	return out


func _collect_texts(node: Node, out: Array[String]) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is Label or node is Button:
		var text := str(node.get("text"))
		if not text.strip_edges().is_empty():
			out.append(text)
	elif node is RichTextLabel:
		var text := (node as RichTextLabel).get_parsed_text()
		if not text.strip_edges().is_empty():
			out.append(text)
	for child in node.get_children():
		_collect_texts(child, out)


## Node names a player should never read ("AstralKnight1", "Draugr2",
## "Robber5"): a capitalised word run straight into digits.
static var _node_name := RegEx.create_from_string("\\b[A-Z][A-Za-z]+[0-9]+\\b")


## The node-like names in [param text], if any.
func node_names_in(text: String) -> Array[String]:
	var out: Array[String] = []
	for found in _node_name.search_all(text):
		out.append(found.get_string())
	return out


func _collect_buttons(node: Node, out: Array[Dictionary]) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is BaseButton:
		out.append({"text": str(node.get("text")) if "text" in node else "", "disabled": (node as BaseButton).disabled,
			"path": str(main.get_path_to(node)), "node": node})
	for child in node.get_children():
		_collect_buttons(child, out)


# --- Acting as a player ----------------------------------------------------

## A click at [param at] with [param button] (left by default): Main's own
## click handler, with the cell under the cursor set to [param at].
func click(at: Vector2i, button := MOUSE_BUTTON_LEFT) -> void:
	_clicked_frame = Engine.get_process_frames()
	for pressed: bool in [true, false]:
		main._pick_grid = Vector2(at)
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		main._unhandled_input(event)
		if pressed:
			await frames(1)


## A tap of [param keycode] with the cursor over [param at] (if given):
## Main's own key handler.
## A tap of E on [param door]: Main's own press and release, the door under
## the cursor set as its pixel pick would (headless has no cursor: the one
## step skipped, as click's cell).
func tap_e_door(door: Door) -> void:
	main._press_e()
	main._e_door = door
	await frames(1)
	main._release_e()


## Frames since the last click (a re-click's pace).
func frames_since_click() -> int:
	return Engine.get_process_frames() - _clicked_frame


func key(keycode: Key, at := Vector2i(-1, -1)) -> void:
	for pressed: bool in [true, false]:
		if at != Vector2i(-1, -1):
			main._pick_grid = Vector2(at)
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		main._unhandled_input(event)
		if pressed:
			await frames(1)


## Clicks [param at] and waits till the player stands on it (or within
## [param near] cells of it), most [param seconds]: true if it got there.
## Clicks again when the walk stalls (a long route, a body in the way).
func walk_to(at: Vector2i, near := 0, seconds := 60.0) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	var last := cell()
	var still_since := Time.get_ticks_msec()
	var from_zone := zone()
	var route := World.walk_path(cell(), at, me())
	log_line("walk %s -> %s: a route of %d cells" % [cell(), at, route.size()])
	if route.is_empty():
		var nearest := World.find_path(cell(), at, true, me(), 0, true)
		log_line("  no way there (%s walkable: %s); nearest reachable %s, %d cells off" % [
			at, World.is_walkable(at), nearest.back() if not nearest.is_empty() else cell(),
			World.distance(nearest.back() if not nearest.is_empty() else cell(), at)])
	await click(at)
	while Time.get_ticks_msec() < until:
		await frames(1)
		if zone() != from_zone:
			log_line("  a link took me to %s at %s" % [zone(), cell()])
			return true
		if me() != null and World.distance(cell(), at) <= near:
			return true
		if cell() != last:
			last = cell()
			still_since = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - still_since > 3000:
			still_since = Time.get_ticks_msec()
			var player := me()
			var beside: Array = seen().filter(func(e: GridEntity) -> bool: return World.distance(e.tile, cell()) <= 2) \
				.map(func(e: GridEntity) -> String: return "%s@%s" % [label(e), e.tile])
			log_line("  stalled at %s (hp %s): route %d cells, the click's %d; beside me: %s" % [cell(),
				player.get("hp") if player != null else "-", World.walk_path(cell(), at, player).size(),
				(main._free.get("path", []) as Array).size(), ", ".join(beside)])
			var doors_near: Array = World.get_doors().filter(func(d: Door) -> bool: return World.distance(Vector2i(d.key.x, d.key.y), cell()) <= 2) \
				.map(func(d: Door) -> String: return "%s %s%s" % [d.key, "open" if d.open else "shut", (" lock " + d.lock) if not d.lock.is_empty() else ""])
			if not doors_near.is_empty():
				log_line("    doors within 2: %s" % ", ".join(doors_near))
			# A shut door beside me: opened as a player does, E with it under the cursor.
			for door: Door in World.get_doors():
				var spot := Vector2i(door.key.x, door.key.y)
				if not door.open and World.distance(spot, cell()) <= 1:
					log_line("  a shut door at %s (lock \"%s\"): E" % [door.key, door.lock])
					await tap_e_door(door)
					await seconds(1.0)
					break
			await click(at)
	return me() != null and World.distance(cell(), at) <= near


## Fights [param foe] as a player does: a left click on it (Main's click:
## the attack order and the chase), clicked again every
## [param reclick] seconds while it stands. "won" once it is down or
## gone, "died" if the local player is, "fled" if its hp falls under
## [param flee_at] of its most, "timeout" after [param most] seconds.
func fight(foe: GridEntity, most := 60.0, flee_at := 0.0, reclick := 1.5) -> String:
	var end := Time.get_ticks_msec() + int(most * 1000.0)
	var player := me()
	var start_hp := int(player.get("hp")) if player != null and "hp" in player else 0
	log_line("fight %s at %s (its hp %s, mine %d)" % [label(foe), foe.tile, foe.get("hp") if "hp" in foe else "?", start_hp])
	var foe_name := String(foe.name)
	var given := str(foe.get("given_name")) if "given_name" in foe else ""
	var fallen_before := server_lines("[named] %s fell" % given).size() if not given.is_empty() else 0
	var away_before := server_lines("%s got away" % foe_name).size()
	var from_zone := zone()
	while Time.get_ticks_msec() < end:
		player = me()
		if player == null or zone() != from_zone or ("hp" in player and int(player.get("hp")) <= 0):
			log_line("  died")
			return "died"
		if not is_instance_valid(foe) or not foe.spawned or ("hp" in foe and int(foe.get("hp")) <= 0) \
				or ("gone" in foe and bool(foe.get("gone"))):
			await seconds(0.5)
			# Out of the client's sight is not a kill (interest drops a far body;
			# a robber may run for the door): the server's own lines say which.
			if not given.is_empty() and server_lines("[named] %s fell" % given).size() > fallen_before:
				log_line("  won")
				return "won"
			if server_lines("%s got away" % foe_name).size() > away_before:
				log_line("  it got away (the server: %s)" % server_lines("%s got away" % foe_name).back().strip_edges())
				return "escaped"
			if given.is_empty() and is_instance_valid(foe) and "hp" in foe and int(foe.get("hp")) <= 0:
				log_line("  won")
				return "won"
			log_line("  lost sight of it")
			return "lost"
		var most_hp := int(player.get("max_hp")) if "max_hp" in player else 0
		if flee_at > 0.0 and most_hp > 0 and float(player.get("hp")) / most_hp < flee_at:
			log_line("  fled at hp %d" % int(player.get("hp")))
			return "fled"
		await click(foe.tile)
		await seconds(reclick)
	log_line("  timeout (its hp %s)" % [foe.get("hp") if is_instance_valid(foe) and "hp" in foe else "?"])
	return "timeout"


## The nearest monster within [param reach] cells that would fight: not
## peaceable (the fallen knight, a seated draugr), not down, or null.
func nearest_foe(reach := 4) -> GridEntity:
	var player := me()
	if player == null:
		return null
	for entity in seen():
		if World.distance(player.tile, entity.tile) > reach:
			break
		if entity is Monster and not ("peaceable" in entity and bool(entity.get("peaceable"))) \
				and not ("hp" in entity and int(entity.get("hp")) <= 0) and not ("gone" in entity and bool(entity.get("gone"))):
			return entity
	return null


## Waits [param count] seconds as a player would stand: anything that
## comes to fight within [param reach] cells is fought. Whether the player
## is still standing after.
func guard(count: float, reach := 4) -> bool:
	var end := Time.get_ticks_msec() + int(count * 1000.0)
	while Time.get_ticks_msec() < end:
		if me() == null:
			return false
		var foe := nearest_foe(reach)
		if foe != null:
			if await fight(foe, 60.0) == "died":
				return false
		await frames(5)
	return me() != null


## Presses the visible button whose text holds [param words] (any case):
## its own pressed signal, as a click on it. False if none is up.
func press(words: String, root: Node = null) -> bool:
	for each in buttons(root):
		if words.to_lower() in String(each["text"]).to_lower() and not each["disabled"]:
			log_line("press \"%s\" (%s)" % [each["text"], each["path"]])
			(each["node"] as BaseButton).pressed.emit()
			return true
	return false


# --- Time ------------------------------------------------------------------

func frames(count: int) -> void:
	for i in count:
		await main.get_tree().process_frame


func seconds(count: float) -> void:
	await main.get_tree().create_timer(count).timeout


## Waits till [param test] (a Callable returning bool) holds, most
## [param most] seconds: whether it did.
func until(test: Callable, most := 30.0) -> bool:
	var end := Time.get_ticks_msec() + int(most * 1000.0)
	while Time.get_ticks_msec() < end:
		if test.call():
			return true
		await frames(1)
	return bool(test.call())


## Waits for the player to be in the world, most [param most] seconds.
func joined(most := 120.0) -> bool:
	var end := Time.get_ticks_msec() + int(most * 1000.0)
	var next_note := 0
	while Time.get_ticks_msec() < end:
		if me() != null and not zone().is_empty() and not main._arriving():
			return true
		if Time.get_ticks_msec() >= next_note:
			next_note = Time.get_ticks_msec() + 10000
			log_line("waiting to join: online %s, peer %d, zone \"%s\", %d entities, player %s" % [
				Net.online, Net.local_id, zone(), World.get_entities().size(), me()])
		await frames(1)
	return false


## After a crossing or a return: waits till the player stands in the zone
## and the bodies the client knows have stopped coming for a second (the
## zone's spawns arrive over the first frames), most [param most] seconds.
func settled(most := 20.0) -> void:
	await until(func() -> bool: return me() != null and not main._arriving(), most)
	var count := -1
	var steady_since := Time.get_ticks_msec()
	var end := Time.get_ticks_msec() + int(most * 1000.0)
	while Time.get_ticks_msec() < end:
		var now := World.get_entities().size()
		if now != count:
			count = now
			steady_since = Time.get_ticks_msec()
		elif count > 1 and Time.get_ticks_msec() - steady_since > 1000:
			break
		await frames(1)
	log_line("settled in %s at %s: %d bodies known" % [zone(), cell(), count])


# --- Setup (the server's console, never a player's power) --------------------

## One admin console line; its reply ("" if none came).
func admin(line: String, most := 10.0) -> String:
	if admin_port <= 0:
		return ""
	var tcp := StreamPeerTCP.new()
	if tcp.connect_to_host("127.0.0.1", admin_port) != OK:
		return ""
	var end := Time.get_ticks_msec() + int(most * 1000.0)
	while tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() < end:
		tcp.poll()
		await frames(1)
	if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return ""
	tcp.put_data((line + "\n").to_utf8_buffer())
	var reply := ""
	while Time.get_ticks_msec() < end:
		tcp.poll()
		if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		if tcp.get_available_bytes() > 0:
			reply += tcp.get_utf8_string(tcp.get_available_bytes())
		await frames(1)
	log_line("setup: admin \"%s\" -> %s" % [line, reply.strip_edges().left(200)])
	return reply.strip_edges()


# --- The report ------------------------------------------------------------

func log_line(text: String) -> void:
	var stamp := "%6.1fs" % ((Time.get_ticks_msec() - _started_msec) / 1000.0)
	print("[tour] %s %s" % [stamp, text])
	lines.append({"ok": null, "what": text, "detail": "", "at": stamp})


## One check a player would notice: PASS or FAIL in the report.
func expect(ok: bool, what: String, detail := "") -> bool:
	var stamp := "%6.1fs" % ((Time.get_ticks_msec() - _started_msec) / 1000.0)
	print("[tour] %s %s  %s%s" % [stamp, "PASS" if ok else "FAIL", what, ("  (%s)" % detail) if not detail.is_empty() else ""])
	lines.append({"ok": ok, "what": what, "detail": detail, "at": stamp})
	return ok


func failures() -> int:
	var count := 0
	for line in lines:
		if line["ok"] == false:
			count += 1
	return count


## A still of what the window shows, saved as <out>/<name>.png, the camera
## turned to [param yaw] degrees (NAN keeps it) and low or high. Only with a
## window (tour.sh --offscreen); headless it logs and returns "". The view is
## forced to draw first: an off-screen window may not present its frames.
func still(name: String, yaw := NAN, low := true) -> String:
	if DisplayServer.get_name() == "headless":
		log_line("still %s: skipped (headless)" % name)
		return ""
	Net.set_camera_low(low, false)
	main._pick_grid = Vector2(-1000, -1000)  # No hover label over the shot.
	var view: Node = main.get("_client3d")
	if view != null and not is_nan(yaw):
		view.set("yaw", yaw)
		view.set("_yaw_step", yaw)
	await seconds(2.0)
	RenderingServer.force_draw()
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := out_dir.path_join("%s.png" % name)
	var error := image.save_png(path) if image != null and not image.is_empty() else ERR_UNAVAILABLE
	var player := me()
	log_line("still %s: %s (at %s in %s, hour %.1f, yaw %s, %s)" % [name, path if error == OK else "FAILED %d" % error,
		cell(), zone(), DayNight.hour(DayNight.now()), yaw, "low" if low else "high"])
	return path if error == OK else ""


func write_report(tour_name: String) -> void:
	if out_dir.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	var file := FileAccess.open(out_dir.path_join("report.md"), FileAccess.WRITE)
	if file == null:
		return
	var checks := 0
	for line in lines:
		if line["ok"] != null:
			checks += 1
	file.store_line("# Tour %s: %s (%d checks, %d failed)" % [tour_name, "PASS" if failures() == 0 else "FAIL", checks, failures()])
	file.store_line("")
	for line in lines:
		var mark := "    " if line["ok"] == null else ("PASS" if line["ok"] else "FAIL")
		file.store_line("- `%s` %s %s%s" % [line["at"], mark, line["what"], (" (%s)" % line["detail"]) if not String(line["detail"]).is_empty() else ""])
