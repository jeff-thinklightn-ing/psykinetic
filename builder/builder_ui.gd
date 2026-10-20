class_name BuilderUI
extends Node
## Builder mode on a client (BuilderHost on the server does the asking): B
## turns it on and off. On, a left drag picks an area (outlined on the
## ground) and a box opens for the request ("a pond here"); the server's
## proposal shows over the area as a ghost, with Claude's words. Then Enter
## (the box empty) accepts it, a request in the box is a follow-up
## ("bigger"), Esc discards it; Ctrl+Z takes back the last change to this
## level. Left clicks pick areas while it is on: walking waits.

## Main: the local player, the cursor's cell, the HUD, the 3D view.
var main: Node
var active := false
var area := Rect2i()
## "idle" (no area), "asking" (the box open), "working", "proposal".
var state := "idle"
var _drag_from := Vector2i(-1, -1)
var _box: LineEdit
var _status: Label
## The cursor's cell and the player's, while on (decision 537).
var _coords: Label
var _coords_at := Vector2i(-2, -2)
var _coords_me := Vector2i(-2, -2)
var _proposal := {}
## --test-builder with a request starting "+": accept the proposal when it comes.
var _test_accept := false


func _ready() -> void:
	_status = Label.new()
	_status.name = "BuilderStatus"
	_status.anchor_left = 0.5
	_status.anchor_right = 0.5
	_status.offset_left = -900
	_status.offset_right = 900
	_status.offset_top = 90
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.theme_type_variation = &"Outlined"
	_status.visible = false
	main.get_node("HUD").add_child(_status)
	_coords = Label.new()
	_coords.name = "BuilderCoords"
	_coords.anchor_left = 0.5
	_coords.anchor_right = 0.5
	_coords.offset_left = -400
	_coords.offset_right = 400
	_coords.offset_top = 40
	_coords.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coords.theme_type_variation = &"Outlined"
	_coords.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coords.visible = false
	main.get_node("HUD").add_child(_coords)
	_box = LineEdit.new()
	_box.name = "BuilderBox"
	_box.max_length = BuilderHost.MAX_TEXT
	_box.visible = false
	_box.anchor_left = 0.5
	_box.anchor_right = 0.5
	_box.offset_left = -800
	_box.offset_right = 800
	_box.offset_top = 270
	_box.offset_bottom = 350
	_box.text_submitted.connect(_submitted)
	_box.gui_input.connect(func(event: InputEvent) -> void:
		var key := event as InputEventKey
		if key != null and key.pressed and key.keycode == KEY_ESCAPE:
			escape()
			main.get_viewport().set_input_as_handled())
	main.get_node("HUD").add_child(_box)


func _process(_delta: float) -> void:
	if not active or _coords == null:
		return
	var at: Vector2i = main._mouse_tile()
	var me: Player = main._local_player()
	var standing: Vector2i = me.tile if me != null else main.NONE
	if at == _coords_at and standing == _coords_me:
		return
	_coords_at = at
	_coords_me = standing
	_coords.text = coords_text(at, standing, main.NONE)


## The coordinates line (decision 537): "212, 207      you 210, 205".
static func coords_text(at: Vector2i, standing: Vector2i, none: Vector2i) -> String:
	var parts := PackedStringArray()
	if at != none:
		parts.append("%d, %d" % [at.x, at.y])
	if standing != none:
		parts.append("you %d, %d" % [standing.x, standing.y])
	return "      ".join(parts)


## The building of [param buildings] (Level.parse's) whose footprint holds
## [param tile], or {} (decision 537).
static func building_at(buildings: Array, tile: Vector2i) -> Dictionary:
	for building: Dictionary in buildings:
		var blocks: Array = building.get("blocks", [])
		if (blocks if not blocks.is_empty() else [building["rect"]]).any(func(rect: Rect2i) -> bool: return rect.has_point(tile)):
			return building
	return {}


## A building's code and name, the cursor hint's and the label's: "H3 house".
static func building_words(building: Dictionary) -> String:
	var name := str(building.get("kind", ""))
	if name.is_empty():
		name = str(building.get("slot", "building")).trim_prefix("building.")
	return ("%s %s" % [building.get("code", ""), name.replace("_", " ")]).strip_edges()


## The party log's line for a building clicked in builder mode:
## "H3 house at 212, 207, facing south, use: inn".
static func building_line(building: Dictionary) -> String:
	var at: Vector2i = building.get("cell", Vector2i.ZERO)
	var facing: Vector2i = building.get("facing", Vector2i(0, 1))
	var side: String = {Vector2i(0, -1): "north", Vector2i(1, 0): "east", Vector2i(0, 1): "south", Vector2i(-1, 0): "west"}.get(facing, str(facing))
	var line := "%s at %d, %d, facing %s" % [building_words(building), at.x, at.y, side]
	if not str(building.get("use", "")).is_empty():
		line += ", use: %s" % building["use"]
	if not str(building.get("town", "")).is_empty():
		line += ", town: %s" % building["town"]
	return line


func is_typing() -> bool:
	return _box != null and _box.visible and _box.has_focus()


## Main's input, first: true if builder mode took it.
func handle_input(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if Keys.matches(key.keycode, "builder") and not key.ctrl_pressed and not is_typing():
			toggle()
			return true
		if not active:
			return false
		if key.keycode == KEY_ESCAPE:
			escape()
			return true
		if key.keycode == KEY_Z and key.ctrl_pressed:
			_send({"op": "undo"})
			_say("taking back the last change to this level...")
			return true
		if key.keycode in [KEY_ENTER, KEY_KP_ENTER] and state == "proposal":
			_send({"op": "accept"})
			return true
		return false
	if not active:
		return false
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		var at: Vector2i = main._mouse_tile()
		if button.pressed and at != main.NONE:
			var clicked := building_at(main.level.get("buildings", []), at)
			if not clicked.is_empty():
				main.talk.add_line("Builder", building_line(clicked), true, true)
		if button.pressed and at != main.NONE and state in ["idle", "asking", "proposal"]:
			if state == "proposal":
				_send({"op": "discard"})
			_drag_from = at
			_set_area(Rect2i(at, Vector2i.ONE))
		elif not button.pressed and _drag_from != Vector2i(-1, -1):
			_drag_from = Vector2i(-1, -1)
			_open_box()
		return true
	var motion := event as InputEventMouseMotion
	if motion != null and _drag_from != Vector2i(-1, -1):
		var at: Vector2i = main._mouse_tile()
		if at != main.NONE:
			var corner := Vector2i(mini(at.x, _drag_from.x), mini(at.y, _drag_from.y))
			var size := ((at - _drag_from).abs() + Vector2i.ONE).min(BuilderHost.MAX_AREA)
			_set_area(Rect2i(corner, size))
		return false
	return false


func toggle() -> void:
	active = not active
	_coords.visible = active
	_coords_at = Vector2i(-2, -2)
	if main._client3d != null:
		main._client3d.show_building_codes(active)
	if active:
		_say("Builder mode: drag out an area, then say what to make there.   B leaves.")
	else:
		if state == "proposal":
			_send({"op": "discard"})
		_reset()
		_status.visible = false


## Esc: the proposal discarded, else the box closed, else the area let go.
func escape() -> void:
	if state == "proposal":
		_send({"op": "discard"})
		_proposal = {}
		_show_area()
		_open_box()
		_say("Discarded. Ask again, or drag out another area.")
	elif _box.visible:
		_box.visible = false
		_reset()
		_say("Builder mode: drag out an area.   B leaves.")
	else:
		_reset()


func _reset() -> void:
	state = "idle"
	area = Rect2i()
	_proposal = {}
	_box.visible = false
	_box.text = ""
	if main._client3d != null:
		main._client3d.clear_builder()


func _set_area(rect: Rect2i) -> void:
	area = rect
	_proposal = {}
	_show_area()


func _show_area() -> void:
	if main._client3d == null:
		return
	var beyond := Rect2i()
	var footprint: Array = _proposal.get("new_area", {}).get("footprint", [])
	if footprint.size() == 4:
		beyond = Rect2i(int(footprint[0]), int(footprint[1]), int(footprint[2]), int(footprint[3]))
	main._client3d.show_builder(area, _proposal.get("cells", []), _proposal.get("edges", []), beyond, _proposal.get("heights", []), _proposal.get("roofs", []))


func _open_box() -> void:
	if area.size == Vector2i.ZERO:
		return
	state = "asking" if state != "proposal" else state
	_box.placeholder_text = "what goes in these %d x %d cells? (Enter asks, Esc cancels)" % [area.size.x, area.size.y]
	_box.visible = true
	_box.grab_focus()


func _submitted(text: String) -> void:
	var asked := text.strip_edges()
	_box.text = ""
	if asked.is_empty():
		if state == "proposal":
			_send({"op": "accept"})
		return
	_send({"op": "ask", "area": [area.position.x, area.position.y, area.size.x, area.size.y], "text": asked})
	state = "working"
	_say("Asking: %s ..." % asked)


func _send(args: Dictionary) -> void:
	var me: Player = main._local_player()
	if me == null:
		_say("no player to build as yet")
		return
	World.command(me, "builder", args)


## The server's answer (BuilderHost's "builder" message).
func on_message(data: Dictionary) -> void:
	match str(data.get("state", "")):
		"working":
			state = "working"
		"proposal":
			state = "proposal"
			_proposal = data
			var given: Array = data.get("area", [])
			if given.size() == 4:
				area = Rect2i(int(given[0]), int(given[1]), int(given[2]), int(given[3]))
			_show_area()
			var made: Dictionary = data.get("new_area", {})
			var beyond := "" if made.is_empty() else "\nA new level, %s (%d x %d), beyond the %s edge (outlined in orange)." % [
				made.get("name", ""), int(made.get("size", [0, 0])[0]), int(made.get("size", [0, 0])[1]), made.get("side", "")]
			_say("%s%s\n($%.3f; this area $%.3f)   Enter accepts, a request in the box changes it, Esc discards." % [
				data.get("summary", ""), beyond, float(data.get("cost", 0.0)), float(data.get("total", 0.0))])
			_box.placeholder_text = "Enter accepts; or say what to change (\"bigger\", \"move it north\")"
			_box.visible = true
			_box.grab_focus()
			if _test_accept:
				_test_accept = false
				_send({"op": "accept"})
		"accepted":
			_reset()
			_say("Built. Drag out another area, Ctrl+Z takes it back, B leaves.")
		"discarded":
			pass
		"undone":
			_say("Taken back.")
		"nothing":
			_say("Nothing to do.")
		"error":
			state = "proposal" if not _proposal.is_empty() else ("asking" if area.size != Vector2i.ZERO else "idle")
			_say("Builder: %s" % data.get("error", "something went wrong"))


## --test-builder: "x,y,w,h:request" asked as if dragged out and typed.
func test_ask(spec: String) -> void:
	var parts := spec.split(":", true, 1)
	var numbers := parts[0].split(",")
	if parts.size() < 2 or numbers.size() != 4:
		push_warning("[builder] --test-builder=%s: x,y,w,h:request" % spec)
		return
	active = true
	_test_accept = parts[1].begins_with("+")
	_set_area(Rect2i(numbers[0].to_int(), numbers[1].to_int(), numbers[2].to_int(), numbers[3].to_int()))
	_open_box()
	_submitted(parts[1].trim_prefix("+"))


func _say(text: String) -> void:
	_status.text = text
	_status.visible = true
	print("[builder] " + text.get_slice("\n", 0))
